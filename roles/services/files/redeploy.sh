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
OLD_CONTAINER_NEW_NAME="OLD-$IMAGE_NAME"

log_message() {
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    echo "$timestamp - $1"
}

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
    log_message "$REPO_DIR has already been cloned. Updating main branch..."
    cd "$REPO_DIR" || exit 1
    git checkout main --force
		git fetch -p
		git reset --hard origin/main
else
    log_message "Cloning $REPO_URL into $REPO_DIR..."
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
		docker rename "$IMAGE_NAME" "$OLD_CONTAINER_NEW_NAME"
    log_message "Stopping $OLD_CONTAINER_NEW_NAME ($CURRENT_CONTAINER_ID)..."
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
    log_message "$NEW_CONTAINER_NAME has successfully started."
		if [ -n "$CURRENT_CONTAINER_ID" ]; then
		  log_message "Deleting $OLD_CONTAINER_NEW_NAME ($CURRENT_CONTAINER_ID)..."
		  docker rm "$CURRENT_CONTAINER_ID"
		fi
else
    log_message "$NEW_CONTAINER_NAME has NOT successfully started."
		log_message "Deleting $NEW_CONTAINER_NAME..."
    docker rm -f "$NEW_CONTAINER_NAME"

    if [ -n "$CURRENT_CONTAINER_ID" ]; then
		    log_message "Trying to restore $CURRENT_CONTAINER_ID..."
        docker start "$CURRENT_CONTAINER_ID"
		    docker rename "$OLD_CONTAINER_NEW_NAME" "$IMAGE_NAME"
        log_message "$IMAGE_NAME ($CURRENT_CONTAINER_ID) has started"
    else
        log_message "No previous container to start."
    fi
fi
