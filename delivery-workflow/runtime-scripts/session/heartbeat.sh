#!/usr/bin/env bash
# session/heartbeat.sh — PreToolUse hook: stamp the heartbeat surface with the
# current epoch (writer class: session). Liveness signal #2 in the stack
# (state-and-liveness.md §5); covers sub-agent tool calls where the backend
# declares heartbeat_covers_subagents. Deliberately fast: one store write, no
# config load. Always exits 0 — a heartbeat failure must never block the
# agent's tool call; staleness is the ferry's signal either way.

set -u
export LC_ALL=C
_HB_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
. "$_HB_DIR/../lib/state.sh"

ws=${1:-}
if [ -z "$ws" ]; then
  echo "heartbeat.sh: missing <workspace> argument" >&2
  exit 0
fi
printf 't=%s\n' "$(date +%s)" | state_set "$ws" heartbeat session \
  || echo "heartbeat.sh: store write failed (ferry will see staleness)" >&2
exit 0
