#!/usr/bin/env bash
set -euo pipefail

mkdir -p "$WORKSPACE_ROOT"

# Local dev: container starts as real root — chown the bind-mounted
# workspace so the node user can write it, then gosu-drop to UID 1000.
# CI / restricted envs: container may start as non-root OR as a
# "neutered root" without CAP_CHOWN / CAP_SETUID (no-new-privileges,
# userns remap, security profile). In both cases we skip privilege
# ops (best-effort) and exec as whoever we are.
if [ "$(id -u)" = "0" ]; then
    chown -R 1000:1000 "$WORKSPACE_ROOT" 2>/dev/null || true
    if gosu 1000:1000 true 2>/dev/null; then
        if [ "$#" -eq 0 ]; then
            exec gosu 1000:1000 /bin/bash
        else
            exec gosu 1000:1000 "$@"
        fi
    fi
fi

if [ "$#" -eq 0 ]; then
    exec /bin/bash
else
    exec "$@"
fi
