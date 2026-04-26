#!/bin/bash
set -euo pipefail

if [ -z "${PROJECT_ROOT:-}" ]; then
    echo "Error: PROJECT_ROOT is not set. Export it to an absolute host path to mount as /workspace." >&2
    echo "  e.g.  PROJECT_ROOT=/abs/path/to/repo $0 [cmd...]" >&2
    exit 1
fi

CLAUDE_JSON="$(pwd)/docker-files/.claude.local.json"
CLAUDE_CREDENTIALS_DIR="$(pwd)/docker-files/.credentials"
CARGO_DIR="$(pwd)/docker-files/.cargo"
VENV_DIR="$(pwd)/docker-files/venv"
LOCAL_DIR="$(pwd)/docker-files/.local"
# use default if not provided externally
MODEL=${MODEL:-"claude-haiku-4-5"}

# mount support
mkdir -p $CLAUDE_CREDENTIALS_DIR $CARGO_DIR $VENV_DIR $LOCAL_DIR

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

docker run -i $TTY_FLAG --rm \
    -e PROJECT_ROOT=/workspace \
    -e PLUGIN_ROOT=/plugin \
    -e WORKSPACE_ROOT=/workspace \
    -e AGENT_FILE_ACCESS_RULES=/docker-scripts/y2-plugin-deny-file-rules.json \
    -e PROXY_WRAPPER_CONFIG=/docker-scripts/proxy_wrapper_config.json \
    -e DISABLE_STOP_HOOK=${DISABLE_STOP_HOOK:-} \
    -v $CARGO_DIR:/home/node/.cargo:Z \
    -v $VENV_DIR:/home/node/venv:Z \
    -v $CLAUDE_CREDENTIALS_DIR:/home/node/.claude:Z \
    -v $CLAUDE_JSON:/home/node/.claude.json:Z \
    -v $LOCAL_DIR:/home/node/.local:Z \
    -v $PROJECT_ROOT:/workspace:Z \
    autopilot-ws "${CMD[@]}"
