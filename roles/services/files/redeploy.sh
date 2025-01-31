#!/bin/bash

# Check usage
if [ "$#" -lt 2 ]; then
    echo "Usage: $0 <repo_url> <image> [--build-arg <build_var1=value1> ...] [--env <env_var2=value2> ...] [--volume <build_var1=value1> ...]"
    exit 1
fi

REPO_URL="$1"
IMAGE_NAME="$2"

# dirname returns an empty string if the script is run without prepending path
# so we need a fallback
SCRIPT_DIR=$(dirname "$0")
if [ -z "$SCRIPT_DIR" ]; then
    SCRIPT_DIR="."
fi

REPO_DIR="$SCRIPT_DIR/$(basename "$REPO_URL" .git)"
CURRENT_CONTAINER_IMAGE_NAME=$(docker ps -a --format "{{.Names}}" | grep "^$IMAGE_NAME")
TIMESTAMP=$(date +%Y%m%d%H%M%S)
NEW_CONTAINER_NAME="${IMAGE_NAME}_container_${TIMESTAMP}"

# Browse all parameters and group them by type.
BUILD_ARGS=()
ENV_VARS=()
VOLUMES=()
INPUT="$@"
while [[ "$INPUT" ]]; do
    if [[ "$INPUT" =~ ^(.*?)(--env| -e)(.*) ]]; then
        ENV_VARS+=("${BASH_REMATCH[2]} ${BASH_REMATCH[3]}")
        INPUT="${BASH_REMATCH[1]}${BASH_REMATCH[4]}"
    elif [[ "$INPUT" =~ ^(.*?)(--build-arg)(.*) ]]; then
        BUILD_ARGS+=("${BASH_REMATCH[2]} ${BASH_REMATCH[3]}")
        INPUT="${BASH_REMATCH[1]}${BASH_REMATCH[4]}"
    elif [[ "$INPUT" =~ ^(.*?)(--volume| -v)(.*) ]]; then
        VOLUMES+=("${BASH_REMATCH[2]} ${BASH_REMATCH[3]}")
        INPUT="${BASH_REMATCH[1]}${BASH_REMATCH[4]}"
    else
        break
    fi
done

# Check if the repo has already been cloned
if [ -d "$REPO_DIR" ]; then
    echo "$REPO_DIR has already been cloned. Updating main branch..."
    cd "$REPO_DIR" || exit 1
    git checkout main --force
		git fetch -p
		git reset --hard origin/main
else
    echo "Cloning $REPO_URL into $REPO_DIR..."
    git clone "$REPO_URL" "$REPO_DIR"
    cd "$REPO_DIR" || exit 1
fi

COMMIT_ID=$(git rev-parse HEAD)

# Build new Docker image from sources
docker build "${BUILD_ARGS[@]}" -t "$IMAGE_NAME:$COMMIT_ID" .

# Stop current container if any
if [ -n "$CURRENT_CONTAINER_IMAGE_NAME" ]; then
    echo "Stopping $CURRENT_CONTAINER_IMAGE_NAME..."
    docker stop "$CURRENT_CONTAINER_IMAGE_NAME"
fi

# Start new container based on new image
docker run -d \
		--name "$NEW_CONTAINER_NAME" \
		--network caddy_net \
		--hostname "$IMAGE_NAME" \
		--restart unless-stopped \
		${ENV_VARS[@]} \
		${VOLUMES[@]} \
		"$IMAGE_NAME:$COMMIT_ID"

# Check that new container is running
if [ "$(docker ps -q -f name=$NEW_CONTAINER_NAME)" ]; then
    echo "$NEW_CONTAINER_NAME has successfully started."
		echo "Deleting $CURRENT_CONTAINER_IMAGE_NAME..."
		if [ -n "$CURRENT_CONTAINER_IMAGE_NAME" ]; then
		  docker rm "$CURRENT_CONTAINER_IMAGE_NAME"
		fi
else
    echo "$NEW_CONTAINER_NAME has NOT successfully started."

    if [ -n "$CURRENT_CONTAINER_IMAGE_NAME" ]; then
		    echo "Trying to restore $CURRENT_CONTAINER_IMAGE_NAME..."
        docker start "$CURRENT_CONTAINER_IMAGE_NAME"
        echo "$CURRENT_CONTAINER_IMAGE_NAME has started"
    else
        echo "No previous container to start."
    fi
		echo "Deleting $NEW_CONTAINER_NAME..."
    docker rm -f "$NEW_CONTAINER_NAME"
fi
