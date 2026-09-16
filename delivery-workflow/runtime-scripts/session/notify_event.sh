#!/usr/bin/env bash
# session/notify_event.sh — the Notification-hook half of protocol-derived
# idleness (design/state-and-liveness.md §5). The profile wires Claude Code's
# Notification event here: the CLI reports its own state transitions as facts,
# where the watch loop could only infer them from the pane. Exit codes and
# stderr from this hook are IGNORED by the CLI, so this can only observe, never
# block — the same one-way shape as heartbeat.sh.
#
# Field extraction is defensive (this tree has no jq). TWO sources, tried in
# order, and the row records which one answered in `type_src=`:
#   field   — the payload carried `"type"` or `"notification_type"` with a
#             lowercase value; used as-is. The second spelling is the one the
#             live CLI sends, measured from the first raw payload this file ever
#             kept.
#   message — no such pair, so the MESSAGE TEXT is matched against a
#             live-measured literal. The degraded path, kept because a build that
#             drops the field must still classify.
#   none    — neither answered; the row still lands as `type=unparsed`, because
#             a postmortem that sees nothing is the failure this file was
#             already fixed for once.
# The literal is live-measured and versioned like every `sig.*` in this tree:
# recalibrate at the onboarding probe on a cmd.version change. ONE literal
# covers everything that reaches this file — claude.kv is the one user of
# profiles/settings-hooks.json, and codex.hooks.json wires no
# Notification event — so no third shape arrives here. No message literal maps
# to permission_prompt: it has never been measured, and an invented signature
# does not belong in the one file that has already shipped a wrong assumption
# about this payload.
#
# The RAW payload is persisted under .runtime/, bounded, because its absence WAS
# the missing evidence: this file once kept `type` and a 120-char `msg` slice
# and discarded the JSON, so "what shape arrives" stayed open through three
# topics. Two files, one job each — `notify-raw.first.json` is written once and
# answers what arrives; `notify-raw.unparsed.json` holds the most recent payload
# NOTHING classified, and stops being written the day classification works.
#
# The watch arm keys on type=idle_prompt only — permission_prompt events are
# recorded for the audit trail but deliberately NOT acted on (a permission
# modal under dontAsk is config drift, surfaced not auto-answered —
# backend-seam §3's standing rule; an Enter-shaped nudge would answer it).
set -uo pipefail
export LC_ALL=C
_NE_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
. "$_NE_DIR/../lib/state.sh"

ws=${1:?usage: notify_event.sh <workspace> [session-name]}
sname=${2:-}

input=$(cat)
# `"(notification_)?type"` and never a bare `type`: the leading quote is what
# keeps `"prompt_type"`-shaped keys out, and the value class stays lowercase so
# `"hook_event_name":"Notification"` cannot answer.
type=$(printf '%s' "$input" | command grep -oE '"(notification_)?type" *: *"[a-z_]+"' | head -1 \
        | sed 's/.*"\([a-z_]*\)"$/\1/')
msg=$(printf '%s' "$input" | command grep -oE '"message" *: *"[^"]{0,120}' | head -1 \
        | sed 's/.*: *"//' | tr '\n\t' '  ')
# The CLI hands us the path of its OWN transcript, which retains the tool stdout
# the pane log does not (VD-59).
# Kept so a `closes on` that wants tool output has an instrument — one that
# lives OUTSIDE the workspace and survives the tree cleanup — and so the mapping
# is per session rather than guessed from cwd and timing. Bounded and
# whitespace-refusing, because a row field is space-delimited: a path carrying
# a space would silently eat the fields after it. `none` is the honest value for
# absent-or-unusable, the same word `msg` uses.
transcript=$(printf '%s' "$input" | command grep -oE '"transcript_path" *: *"[^"]{0,512}"' | head -1 \
        | sed 's/.*: *"//; s/"$//')
case "$transcript" in
  ''|*[[:space:]]*) transcript=none ;;
esac
if [ -n "$type" ]; then
  type_src=field
else
  # Prefix match, not equality: the row's msg is a 120-char slice of the CLI's
  # own sentence, and a build that appends to it must not silently stop
  # classifying. A build that CHANGES the sentence is meant to fall through to
  # unparsed and leave its payload in notify-raw.unparsed.json to be read.
  case "$msg" in
    "Claude is waiting for your input"*) type=idle_prompt; type_src=message ;;
    *)                                   type=unparsed;   type_src=none ;;
  esac
fi

# Bounded, best-effort, and never able to fail the hook: this path is one-way.
# Guarded on a NON-EMPTY payload, and that guard is load-bearing in both files.
# An empty stdin carries no shape, and without the guard the FIRST firing to
# arrive empty would claim notify-raw.first.json permanently (it is write-once)
# and leave the shape question open forever, while a later empty one would
# overwrite an informative notify-raw.unparsed.json with nothing. The row still
# records the empty case as it always did, `type=unparsed msg=none`.
if [ -n "$input" ] && [ -d "$ws/.runtime" ]; then
  if [ ! -f "$ws/.runtime/notify-raw.first.json" ]; then
    printf '%s' "$input" | head -c 4096 > "$ws/.runtime/notify-raw.first.json" 2>/dev/null || true
  fi
  if [ "$type_src" = none ]; then
    printf '%s' "$input" | head -c 4096 > "$ws/.runtime/notify-raw.unparsed.json" 2>/dev/null || true
  fi
fi

state_append "$ws" notify_events session \
  "v=1 t=$(date +%s) session=$sname type=$type type_src=$type_src transcript=$transcript msg=${msg:-none}" > /dev/null 2>&1 \
  || echo "notify_event: append failed (surface fault? the next launch parks store_fault)" >&2
exit 0
