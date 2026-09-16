#!/usr/bin/env bash
# collect_watch.sh — deployment-layer wake-up for planning's park-on-dispatch.
# Planning has no watchdog: when an
# author parks after dispatching instruments ("dispatch ends the session's
# forward work"), something at the deployment layer must notice the
# deliverables landing and wake the collect restart. This is that thing.
#
# Contract it serves: spawn.sh's file-form delivery — each instrument writes
# <out> then <out>.done (the sentinel is the atomicity marker). Watching for
# *.done is watching for "an instrument finished writing", which is exactly
# the moment the parked round can advance.
#
# Deliberately dumb (deployment convenience, not workflow machinery):
#   - polls a directory tree for .done sentinels at a fixed interval;
#   - on first sight of a NEW sentinel: prints it and fires the notify
#     command if one is configured (COLLECT_WATCH_NOTIFY, evaluated by sh);
#   - optionally auto-collects (COLLECT_WATCH_AUTO=1) by invoking
#     spawn.sh collect <session> <out> for sentinels whose sibling .meta
#     carries the session name (spawn.sh launch can write one; absent .meta
#     means notify-only — we never guess a session name);
#   - never edits, never re-spawns, never tears down. Recovery discipline
#     stays with the human/author holding the restart line.
#
# Usage: collect_watch.sh <scratch-dir> [poll-seconds]
# Env:   COLLECT_WATCH_NOTIFY  sh command evaluated on each new sentinel
#        COLLECT_WATCH_AUTO    '1' = run spawn.sh collect when .meta names a session
#        SPAWN_SH              path to spawn.sh (default: sibling in tree)
set -uo pipefail
export LC_ALL=C

DIR=${1:?usage: collect_watch.sh <scratch-dir> [poll-seconds]}
POLL=${2:-60}
SPAWN_SH=${SPAWN_SH:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/planning-workflow/runtime-scripts/spawn.sh}

[ -d "$DIR" ] || { echo "collect_watch: not a directory: $DIR" >&2; exit 2; }
[ "$POLL" -ge 5 ] || { echo "collect_watch: poll < 5s would spin; refuse" >&2; exit 2; }

echo "collect_watch: watching $DIR every ${POLL}s for *.done sentinels"
declare -A SEEN
while :; do
  while IFS= read -r done_f; do
    [ -n "${SEEN[$done_f]:-}" ] && continue
    SEEN[$done_f]=1
    out=${done_f%.done}
    echo "$(date '+%F %T') DONE: $out"
    if [ -n "${COLLECT_WATCH_NOTIFY:-}" ]; then
      # one argument, one level of evaluation — the pattern spawn.sh's own
      # launch line taught (a variable handed to eval twice splits its words)
      COLLECT_WATCH_NOTIFY="$COLLECT_WATCH_NOTIFY" sh -c \
        'eval "$COLLECT_WATCH_NOTIFY" "$0"' "$out" || true
    fi
    if [ "${COLLECT_WATCH_AUTO:-0}" = "1" ] && [ -f "$out.meta" ]; then
      sess=$(sed -n 's/^session=//p' "$out.meta" | head -1)
      if [ -n "$sess" ]; then
        echo "  auto-collect: $SPAWN_SH collect $sess $out"
        "$SPAWN_SH" collect "$sess" "$out" || true
      fi
    fi
  done < <(find "$DIR" -name '*.done' -type f 2>/dev/null | sort)
  sleep "$POLL" &
  wait $!
done
