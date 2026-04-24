#!/usr/bin/env bash
set -euo pipefail

# Host-provided target UID/GID. The caller (run-docker-workspace.sh,
# run-in-docker-no-claude.sh, etc.) passes `-e HOST_UID=... -e HOST_GID=...`
# so the entrypoint can:
#   1. chown the bind-mounted workspace to that UID (while we still have
#      root in the container and CAP_CHOWN),
#   2. gosu-drop the process to that UID before running the command.
# The UID normally matches the host user that owns $GITHUB_WORKSPACE,
# which keeps post-job host-side operations working (no EPERM on
# .git/config locks, cache restores, artifact uploads, etc.).
# Defaults target the image's "node" user so local dev stays ergonomic
# if the caller forgets to set them.
: "${HOST_UID:=1000}"
: "${HOST_GID:=1000}"

mkdir -p "$WORKSPACE_ROOT"
chown -R "$HOST_UID:$HOST_GID" "$WORKSPACE_ROOT"

if [ "$#" -eq 0 ]; then
    exec gosu "$HOST_UID:$HOST_GID" /bin/bash
else
    exec gosu "$HOST_UID:$HOST_GID" "$@"
fi
