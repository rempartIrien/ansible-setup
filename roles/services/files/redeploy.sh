#!/bin/bash

# Check usage
if [ "$#" -lt 2 ]; then
    echo "Usage: $0 <repo_url> <image_name> [--build-arg <build_var1=value1> ...] [--env <env_var2=value2> ...] [--volume <build_var1=value1> ...]"
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
SSH_KEY_PATH="~/.ssh/id_rsa_$IMAGE_NAME"
export GIT_SSH_COMMAND="ssh -i $SSH_KEY_PATH"
CURRENT_CONTAINER_ID=$(docker ps -a --format "{{.ID}} {{.Names}}" | grep " $IMAGE_NAME$" | awk '{print $1}')
NEW_CONTAINER_NAME="$IMAGE_NAME"

# Browse all parameters and group them by type.
BUILD_ARGS=()
SECRETS=()
ENV_VARS=()
VOLUMES=()
INPUT="$@"
while [[ "$INPUT" ]]; do
    if [[ "$INPUT" =~ ^(.*?)(--env| -e)[[:space:]]+([^ ]+) ]]; then
        ENV_VARS+=(--env "${BASH_REMATCH[3]}")
        INPUT="${BASH_REMATCH[1]}${INPUT:${#BASH_REMATCH[0]}}"
    elif [[ "$INPUT" =~ ^(.*?)(--build-arg)[[:space:]]+([^ ]+) ]]; then
        BUILD_ARGS+=(--build-arg "${BASH_REMATCH[3]}")
        INPUT="${BASH_REMATCH[1]}${INPUT:${#BASH_REMATCH[0]}}"
    elif [[ "$INPUT" =~ ^(.*?)(--secret)[[:space:]]+([^ ]+) ]]; then
        SECRETS+=(--secret "${BASH_REMATCH[3]}")
        INPUT="${BASH_REMATCH[1]}${INPUT:${#BASH_REMATCH[0]}}"
    elif [[ "$INPUT" =~ ^(.*?)(--volume| -v)[[:space:]]+([^ ]+) ]]; then
        VOLUMES+=(--volume "${BASH_REMATCH[3]}")
        INPUT="${BASH_REMATCH[1]}${INPUT:${#BASH_REMATCH[0]}}"
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
IMAGE_WITH_TAG="$IMAGE_NAME:$COMMIT_ID"

# Build new Docker image from sources
DOCKER_BUILDKIT=1 docker buildx build \
  "${BUILD_ARGS[@]}" \
	"${SECRETS[@]}" \
	-t "$IMAGE_WITH_TAG" .

# Stop current container if any
if [ -n "$CURRENT_CONTAINER_ID" ]; then
    echo "Stopping $CURRENT_CONTAINER_ID..."
    docker stop "$CURRENT_CONTAINER_ID"
fi

# Start new container based on new image
docker run -d \
		--name "$NEW_CONTAINER_NAME" \
		--network caddy_net \
		--hostname "$IMAGE_NAME" \
		--restart unless-stopped \
		${ENV_VARS[@]} \
		${VOLUMES[@]} \
		"$IMAGE_WITH_TAG"

# Check that new container is running
if [ "$(docker ps -q -f name=$NEW_CONTAINER_NAME)" ]; then
    echo "$NEW_CONTAINER_NAME has successfully started."
		if [ -n "$CURRENT_CONTAINER_ID" ]; then
		  echo "Deleting $CURRENT_CONTAINER_ID..."
		  docker rm "$CURRENT_CONTAINER_ID"
		fi
else
    echo "$NEW_CONTAINER_NAME has NOT successfully started."

    if [ -n "$CURRENT_CONTAINER_ID" ]; then
		    echo "Trying to restore $CURRENT_CONTAINER_ID..."
        docker start "$CURRENT_CONTAINER_ID"
        echo "$CURRENT_CONTAINER_ID has started"
    else
        echo "No previous container to start."
    fi
		echo "Deleting $NEW_CONTAINER_NAME..."
    docker rm -f "$NEW_CONTAINER_NAME"
fi
