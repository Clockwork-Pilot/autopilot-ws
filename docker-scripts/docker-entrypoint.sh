#!/usr/bin/env bash
set -euo pipefail

mkdir -p "$WORKSPACE_ROOT"
chown -R 1000:1000 "$WORKSPACE_ROOT"

# drop to regular user
if [ "$#" -eq 0 ]; then
    exec gosu 1000:1000 /bin/bash
else
    exec gosu 1000:1000 "$@"
fi
