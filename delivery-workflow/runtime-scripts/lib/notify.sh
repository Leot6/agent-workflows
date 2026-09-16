#!/usr/bin/env bash
# lib/notify.sh — notification policy + transport (config-and-adapters.md §5,
# state-and-liveness.md §7).
# Decision inputs are the event type + reason class ONLY — both closed
# enums; the message is payload. Policy = the notify store surface (preset +
# per-event overrides), hot-read at emit → runtime-changeable without
# relaunch. Transport: <notify.cmd> <event> <message>, best-effort, config'd not
# env. At-least-once: the CALLER writes halt → fires → sets the notified flag;
# a relaunch finding halt-without-flag re-sends (a duplicate page beats a lost
# one). This library tolerates store faults (falls back to config defaults) —
# the lifeline must not die with the store.

_NOTIFY_LIB_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
. "$_NOTIFY_LIB_DIR/state.sh"
. "$_NOTIFY_LIB_DIR/config.sh"

_notify_presets_file() { printf '%s/config/notify-presets.kv' "$CONFIG_WORKFLOW_ROOT"; }

# Should this event fire? rc 0 yes, rc 1 suppressed-by-policy.
_notify_decide() { # workspace event
  local ws=$1 ev=$2 body preset override pat patterns
  [ "$ev" = "notify.test" ] && return 0
  body=$(state_get "$ws" notify 2>/dev/null || true)
  override=$(printf '%s\n' "$body" | awk -F= -v k="event.$ev" '$1==k{v=$2} END{print v}')
  case "$override" in
    on) return 0 ;;
    off) return 1 ;;
  esac
  preset=$(printf '%s\n' "$body" | awk -F= '$1=="preset"{v=$2} END{print v}')
  [ -n "$preset" ] || preset=$(config_get notify.preset --topic-dir "$ws" 2>/dev/null || echo key-points)
  patterns=$(awk -F= -v k="preset.$preset" '$1==k{print $2}' "$(_notify_presets_file)")
  if [ -z "$patterns" ]; then
    echo "notify: preset '$preset' not in $(_notify_presets_file) — treating as key-points (named fallback)" >&2
    patterns=$(awk -F= '$1=="preset.key-points"{print $2}' "$(_notify_presets_file)")
  fi
  # NB: read-loop, not `for pat in $(...)` — an unquoted expansion would glob
  # '*' (preset.all) and 'park.*' against the cwd and never match literally.
  while IFS= read -r pat; do
    [ -n "$pat" ] || continue
    case "$pat" in
      '*') return 0 ;;
      *'.*') case "$ev" in "${pat%.*}".*) return 0 ;; esac ;;
      *) [ "$pat" = "$ev" ] && return 0 ;;
    esac
  done < <(printf '%s\n' "$patterns" | tr ',' '\n')
  return 1
}

# fire(event_type, reason_class, message). event_type ∈ the closed vocabulary
# (park|broken|commit.done|slice.done|topic.done|spec.ready|notify.test);
# parks canonicalize to park.<reason_class>.
# rc contract (still best-effort — no caller may die on it):
#   0 the transport ACCEPTED it — it left the machine, which is the last thing
#     observable from here and is NOT a receipt (transports/bark.sh's own exit
#     codes say the same: 0 means Bark returned HTTP 200, never that a human
#     read the page) — or policy suppressed it (deliberate silence; no resend
#     owed either way).
#   1 undelivered: transport absent or failed — the caller must NOT set the
#     notified flag, so a relaunch re-sends (at-least-once; a duplicate page
#     beats a lost one). At-least-once is therefore at-least-once ONTO THE
#     TRANSPORT; the leg from there to a human has no acknowledgement and no
#     retry, and the preflight's test notification is the only place the tree
#     asks a human to confirm arrival at all.
notify_fire() { # workspace event_type reason_class message
  local ws=$1 type=$2 reason=$3 msg=$4 ev cmd
  if [ "$type" = "park" ]; then ev="park.$reason"; else ev=$type; fi
  if ! _notify_decide "$ws" "$ev"; then
    state_audit "$ws" ferry "notify suppressed by policy: $ev"
    return 0
  fi
  cmd=$(config_get notify.cmd --topic-dir "$ws" 2>/dev/null || true)
  # Pluggable transports: notify.cmd empty → notify.transport names an adapter
  # under runtime-scripts/transports/ (the backend seam's shape: a name
  # resolved against a directory, not an API baked into the tree — a new
  # platform is a dropped-in script plus one config line, never a workflow
  # change). notify.cmd, when set, wins outright: the explicit escape hatch
  # for adapters the tree does not ship.
  if [ -z "$cmd" ]; then
    local t adapter
    t=$(config_get notify.transport --topic-dir "$ws" 2>/dev/null || true)
    if [ -n "$t" ]; then
      case "$t" in
        *[!A-Za-z0-9_-]*|.*)
          state_audit "$ws" ferry "notify: transport name '$t' refused (shape) for $ev"
          echo "notify: notify.transport='$t' is not an adapter name ([A-Za-z0-9_-]+, no path) — it resolves against runtime-scripts/transports/, not the filesystem" >&2
          return 1 ;;
      esac
      adapter="$CONFIG_WORKFLOW_ROOT/runtime-scripts/transports/$t.sh"
      if [ -f "$adapter" ] && [ -x "$adapter" ]; then
        cmd="$adapter"
      else
        state_audit "$ws" ferry "notify: transport adapter '$t' absent for $ev"
        echo "notify: notify.transport='$t' resolves to no executable $adapter (shipped: $(ls "$CONFIG_WORKFLOW_ROOT/runtime-scripts/transports/" 2>/dev/null | command grep -E '\.sh$' | sed 's/\.sh$//' | tr '\n' ' '))— add the adapter, or set notify.cmd to any command" >&2
        return 1
      fi
    fi
  fi
  if [ -z "$cmd" ]; then
    state_audit "$ws" ferry "notify: no transport (notify.cmd empty) for $ev"
    echo "notify: no transport for '$ev' — arm one in the operator config ${XDG_CONFIG_HOME:-\$HOME/.config}/delivery-workflow/config.kv (notify.transport=<name> for a shipped adapter, notify.cmd=<command> otherwise; topic.kv overrides per-topic)" >&2
    return 1
  fi
  msg=$(printf '%s' "$msg" | tr '\n\t' '  ')
  if timeout 30 bash -c "$cmd \"\$1\" \"\$2\"" _ "$ev" "$msg" > /dev/null 2>&1; then
    state_audit "$ws" ferry "notify sent: $ev"
    return 0
  fi
  state_audit "$ws" ferry "notify transport FAILED for $ev (cmd: $cmd)"
  echo "notify: transport failed for '$ev' (best-effort; not fatal)" >&2
  return 1
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  set -uo pipefail
  export LC_ALL=C
  if [ $# -lt 4 ]; then
    echo "usage: notify.sh <workspace> <event_type> <reason_class> <message>" >&2
    exit 2
  fi
  notify_fire "$@"
fi
