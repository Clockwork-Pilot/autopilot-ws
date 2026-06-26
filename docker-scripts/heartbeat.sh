#!/bin/bash
# Heartbeat timer loop - executes heartbeat.py every 30 seconds if it exists

HEARTBEAT_SCRIPT="${PLUGIN_ROOT}/heartbeat.py"
INTERVAL="${1:-30}"

if [ ! -f "$HEARTBEAT_SCRIPT" ]; then
  exit 0
fi

while true; do
  python3 "$HEARTBEAT_SCRIPT"
  sleep "$INTERVAL"
done
