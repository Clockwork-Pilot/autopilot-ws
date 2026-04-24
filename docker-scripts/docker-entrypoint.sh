#!/usr/bin/env bash
set -euo pipefail

# Host-provided target UID/GID. The caller passes them via
# `-e HOST_UID=... -e HOST_GID=...`; defaults match the image's
# default `node` user (built at UID 1000 unless overridden at
# image-build time via --build-arg UID=/GID=).
: "${HOST_UID:=1000}"
: "${HOST_GID:=1000}"

mkdir -p "$WORKSPACE_ROOT"

# Runtime user rebranding. Fast path: if the image was built with the
# right UID/GID (`build-docker-workspace.sh` does this automatically
# for local dev), the node user already matches HOST_UID/HOST_GID and
# this block is a no-op. Slow path: an image published with one UID
# (e.g. UID=1000 on GHCR) being consumed by a host with a different
# UID (e.g. UID=1001 on GitHub-hosted runners) — usermod the image's
# node user so `/etc/passwd` has a matching entry, `~` resolves to
# `/home/node`, and the venv/bashrc/etc. are writable.
USER_UID=$(id -u node 2>/dev/null || echo 0)
USER_GID=$(getent group node | cut -d: -f3 || echo 0)
if [ "$USER_UID" != "$HOST_UID" ] || [ "$USER_GID" != "$HOST_GID" ]; then
    groupmod -g "$HOST_GID" node
    usermod  -u "$HOST_UID" -g "$HOST_GID" node
    chown -R "$HOST_UID:$HOST_GID" /home/node
fi

chown -R "$HOST_UID:$HOST_GID" "$WORKSPACE_ROOT"

if [ "$#" -eq 0 ]; then
    exec gosu "$HOST_UID:$HOST_GID" /bin/bash
else
    exec gosu "$HOST_UID:$HOST_GID" "$@"
fi
