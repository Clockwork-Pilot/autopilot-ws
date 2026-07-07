#!/bin/bash
set -euo pipefail

if [ -z "${PROJECT_ROOT:-}" ]; then
    echo "Error: PROJECT_ROOT is not set. Export it to an absolute host path to mount as /workspace." >&2
    echo "  e.g.  PROJECT_ROOT=/abs/path/to/repo $0 [cmd...]" >&2
    exit 1
fi

# default or external env DOCKER_FILES env:
DOCKER_FILES=${DOCKER_FILES:-"$(pwd)/docker-files"}

CLAUDE_JSON="$DOCKER_FILES/.claude.local.json"
CLAUDE_CREDENTIALS_DIR="$DOCKER_FILES/.credentials"
NVM_DIR="$DOCKER_FILES/.nvm"
CARGO_DIR="$DOCKER_FILES/.cargo"
LOCAL_DIR="$DOCKER_FILES/.local"
# use default if not provided externally
MODEL=${MODEL:-"claude-haiku-4-5"}
IMAGE_TAG=${IMAGE_TAG:-"autopilot-ws"}
DOCKER_FLAGS=${DOCKER_FLAGS:-}
DOCKER_RUNTIME=${DOCKER_RUNTIME:-}
SSH_PUBKEY=${SSH_PUBKEY:-"$HOME/.ssh/id_ed25519.pub"}

# mount support
mkdir -p $CLAUDE_CREDENTIALS_DIR $CARGO_DIR $LOCAL_DIR $NVM_DIR

# assign default value if file is empty
[ -s "$CLAUDE_JSON" ] || printf '{}\n' > "$CLAUDE_JSON"

if [ $# -gt 0 ]; then
    ENTRYPOINT_CMD="$*"
else
    # enable proxy wrapper just for claude
    ENTRYPOINT_CMD="claude --dangerously-skip-permissions --model $MODEL --plugin-dir /plugin"
fi

CMD=(bash -c "source /docker-scripts/user-entrypoint.sh ; $ENTRYPOINT_CMD")

# `-t` requires a TTY on stdin/stdout; skip it when invoked from a
# non-interactive shell (CI, background tasks) so docker doesn't bail
# with "the input device is not a TTY". `-i` (stdin attached) is fine
# either way.
TTY_FLAG=
[ -t 0 ] && [ -t 1 ] && TTY_FLAG=-t

docker run -i $TTY_FLAG --rm \
    $DOCKER_RUNTIME \
    -e PROJECT_ROOT=/workspace \
    -e PLUGIN_ROOT=/plugin \
    -e WORKSPACE_ROOT=/workspace \
    -e DISABLE_STOP_HOOK=${DISABLE_STOP_HOOK:-} \
    -v $CARGO_DIR:/home/node/.cargo:Z \
    -v $NVM_DIR:/home/node/.nvm:Z \
    -v $CLAUDE_CREDENTIALS_DIR:/home/node/.claude:Z \
    -v $CLAUDE_JSON:/home/node/.claude.json:Z \
    -v $LOCAL_DIR:/home/node/.local:Z \
    -v $PROJECT_ROOT:/workspace:Z \
    ${SSH_AUTH_SOCK:+-v "$SSH_AUTH_SOCK":/ssh-agent -e SSH_AUTH_SOCK=/ssh-agent} \
    ${SSH_PUBKEY:+-v "$SSH_PUBKEY":/home/node/.ssh/id_ed25519.pub:ro} \
    $DOCKER_FLAGS \
    "$IMAGE_TAG" "${CMD[@]}"
