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
CARGO_DIR="$DOCKER_FILES/.cargo"
LOCAL_DIR="$DOCKER_FILES/.local"
# use default if not provided externally
MODEL=${MODEL:-"claude-haiku-4-5"}
IMAGE_TAG=${IMAGE_TAG:-"autopilot-ws"}
DOCKER_FLAGS=${DOCKER_FLAGS:-}
if [ -z "${PROXY_WRAPPER_CONFIG+x}" ]; then
    PROXY_WRAPPER_CONFIG="/docker-scripts/proxy_wrapper_config.json"
fi

# mount support
mkdir -p $CLAUDE_CREDENTIALS_DIR $CARGO_DIR $LOCAL_DIR

# assign default value if file is empty
[ -s "$CLAUDE_JSON" ] || printf '{}\n' > "$CLAUDE_JSON"

if [ $# -gt 0 ]; then
    ENTRYPOINT_CMD="$*"
else
    ENTRYPOINT_CMD="claude --dangerously-skip-permissions --model $MODEL --plugin-dir /plugin"
fi

CMD=(bash -c "source /docker-scripts/user-entrypoint.sh ; $ENTRYPOINT_CMD")

# Example of file with rules specified in AGENT_FILE_ACCESS_RULES:
# [
#     { "deny-rule": ["$WORKSPACE_ROOT/**"], "reason": "readonly" },
#     { "whitelist-rule": ["$WORKSPACE_ROOT/writable-file.txt"] }
# ]

# `-t` requires a TTY on stdin/stdout; skip it when invoked from a
# non-interactive shell (CI, background tasks) so docker doesn't bail
# with "the input device is not a TTY". `-i` (stdin attached) is fine
# either way.
TTY_FLAG=
[ -t 0 ] && [ -t 1 ] && TTY_FLAG=-t

docker run -i $TTY_FLAG --rm $DOCKER_FLAGS \
    -e PROJECT_ROOT=/workspace \
    -e PLUGIN_ROOT=/plugin \
    -e WORKSPACE_ROOT=/workspace \
    -e AGENT_FILE_ACCESS_RULES=/docker-scripts/y2-plugin-deny-file-rules.json \
    -e PROXY_WRAPPER_CONFIG="$PROXY_WRAPPER_CONFIG" \
    -e DISABLE_STOP_HOOK=${DISABLE_STOP_HOOK:-} \
    -v $CARGO_DIR:/home/node/.cargo:Z \
    -v $CLAUDE_CREDENTIALS_DIR:/home/node/.claude:Z \
    -v $CLAUDE_JSON:/home/node/.claude.json:Z \
    -v $LOCAL_DIR:/home/node/.local:Z \
    -v $PROJECT_ROOT:/workspace:Z \
    "$IMAGE_TAG" "${CMD[@]}"
