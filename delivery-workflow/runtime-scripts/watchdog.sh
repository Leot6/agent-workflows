#!/usr/bin/env bash
# watchdog.sh — exit-code classification, plus the pager (state-and-liveness.md §6).
# Spawns the ferry; a completion (0) stops; a deliberate park (20) stops the
# DRIVING and hands over to the pager below; crashes and store faults (30) get
# a bounded relaunch budget; on exhaustion: CIRCUIT-BROKEN + notify. Its
# relaunch budget comes from workflow defaults.kv; the pager's interval and cap
# may be overridden per topic. The final-state write bypasses the store (the
# ONE documented store-bypass exception: when the store itself may be the
# casualty, someone must still render a last state).

set -uo pipefail
export LC_ALL=C
WD_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
. "$WD_DIR/lib/config.sh"
. "$WD_DIR/lib/notify.sh"

[ $# -ge 1 ] || { echo "usage: watchdog.sh <workspace>" >&2; exit 2; }
WS=$(cd "$1" 2>/dev/null && pwd) || { echo "watchdog: workspace $1 not a directory" >&2; exit 2; }
PIDFILE="$WS/.runtime/watchdog.pid"
FINAL="$WS/.runtime/final-state"

mkdir -p "$WS/.runtime"
if [ -f "$PIDFILE" ]; then
  old=$(cat "$PIDFILE" 2>/dev/null || true)
  if [ -n "$old" ] && kill -0 "$old" 2>/dev/null; then
    echo "watchdog: another watchdog (pid $old) is live for $WS — refusing a second" >&2
    exit 2
  fi
fi
printf '%s\n' $$ > "$PIDFILE"
# A final-state exists only after this process stopped driving: launch.sh and
# stop read "class=parked + a live pid" as THE PAGER, so a stale parked
# final-state beside a live driver would get that driver killed.
rm -f "$FINAL"
trap 'rm -f "$PIDFILE"' EXIT
# The pager sleeps as a background child under `wait`: bash runs a trap the
# moment a signal arrives during `wait`, but only AFTER a foreground `sleep`
# returns — a relaunch's SIGTERM would otherwise sit unanswered for a whole
# interval and read as "did not exit". The EXIT trap then clears the pidfile.
PG_SLEEP=""
trap '[ -n "$PG_SLEEP" ] && kill "$PG_SLEEP" 2>/dev/null; exit 0' TERM

write_final() { # class detail  (direct write — the documented store bypass)
  printf 'class=%s detail=%s t=%s\n' "$1" "$2" "$(date +%s)" > "$FINAL" 2>/dev/null || true
}

# The pager (config-and-adapters §5). The park's page left the machine when the
# transport said so, and that is the last thing the ferry can observe; the leg
# to a human has no receipt. So while a park stays unresolved the watchdog
# re-pages every `notify.repage_interval`, up to `notify.repage_max`, then says
# it stopped. An ack (`launch.sh ack` writes the ack row on the audit surface)
# HOLDS that ladder for `notify.ack_timeout` and it then resumes — an ack is a
# claim of ownership, not proof of it, and a held cycle does not spend the cap.
# A completion (push_gate) is never re-paged; a stop
# request ends the paging; a relaunch takes over this process (launch.sh kills
# a paging watchdog before starting its own). Each re-page is audited, so
# `status --halt` can print how many went out and whether one was acknowledged.
_wd_field() { printf '%s\n' "$1" | awk -F= -v k="$2" '$1==k{v=substr($0,length(k)+2)} END{print v}'; }
# The audit surface's rows are SPACE-separated `k=v` on one line
# (`v=1 t=<epoch> by=<class> msg=<text>`), not one key per line like the halt
# surface — so `_wd_field` cannot read them and this is not a duplicate of it.
_wd_row_field() { printf '%s\n' "$1" | tr ' ' '\n' | awk -F= -v k="$2" '$1==k{print substr($0,length(k)+2); exit}'; }
_pager_open() { # rc 0 page · 1 the ladder is over · 2 acked recently, hold this interval
  local body
  body=$(state_get "$WS" halt 2>/dev/null) || return 1          # absent or faulted: nothing to page about
  body=$(printf '%s\n' "$body" | awk '/^--- screen ---$/{exit} {print}')
  [ "$(_wd_field "$body" resolved)" = "1" ] && return 1
  PG_REASON=$(_wd_field "$body" reason); PG_HID=$(_wd_field "$body" halt_id)
  [ "$PG_REASON" = "push_gate" ] && return 1
  [ -e "$WS/.runtime/stop-request" ] && return 1
  # ACK FRESHNESS, never ack EXISTENCE. The predicate used to be "an ack row
  # exists"; the proposition the ladder needs is "a human has this park", and
  # the two differ whenever a non-human-facing actor can ack — which
  # `cards/pilot.md` instructs the pilot to do as its FIRST move. Measured:
  # park at t=1788642980, pilot acked 71s later, owner arrived 8h09m35s after
  # the park; six pages suppressed and an audit row that was false when written.
  # A freshness test is correct regardless of WHO acked, so it needs no actor
  # field and no unverifiable claim, and its failure mode is noise rather than
  # silence — the side a default belongs on when it decides between the two.
  local ackrow t_ack
  ackrow=$(state_get "$WS" audit 2>/dev/null | command grep -F "msg=ack halt_id=$PG_HID " | tail -1)   # the trailing space: an id is never a prefix of another
  if [ -n "$ackrow" ]; then
    t_ack=$(_wd_row_field "$ackrow" t)
    case "$t_ack" in ''|*[!0-9]*) t_ack=0 ;; esac   # an unreadable stamp reads as ancient: page rather than go quiet
    [ $(( $(date +%s) - t_ack )) -lt "$PG_ACK_TIMEOUT" ] && return 2
  fi
  return 0
}
pager() {
  local interval max n=0 rc
  interval=$(config_get notify.repage_interval --topic-dir "$WS" 2>/dev/null) || interval=2700
  max=$(config_get notify.repage_max --topic-dir "$WS" 2>/dev/null) || max=6
  case "$interval" in ''|*[!0-9]*|0) interval=2700 ;; esac   # a 0 s interval would page in a tight loop
  case "$max" in ''|*[!0-9]*) max=6 ;; esac
  PG_ACK_TIMEOUT=$(config_get notify.ack_timeout --topic-dir "$WS" 2>/dev/null) || PG_ACK_TIMEOUT=""
  case "$PG_ACK_TIMEOUT" in ''|*[!0-9]*) PG_ACK_TIMEOUT=$interval ;; esac   # unreadable ⇒ exactly one silence window
  # 0 is the OFF SWITCH for holding, said on the audit surface rather than
  # silently: an ack then suppresses nothing and every page goes out on
  # schedule. Its neighbours already behave this way and 0 must not be the one
  # value that changes behaviour quietly — `notify.repage_max=0` disables
  # re-paging with an audit row, and `notify.repage_interval=0` falls back
  # rather than paging in a tight loop.
  if [ "$PG_ACK_TIMEOUT" -eq 0 ] 2>/dev/null; then
    state_audit "$WS" watchdog "ack holds disabled (notify.ack_timeout=0) — an ack will not suppress any page for this park"
  fi
  _pager_open; rc=$?               # decided before the first sleep: a park already RESOLVED never holds this
  [ $rc -eq 1 ] && return 0        # rc 2 (a fresh ack) still holds the process — the window expires and paging resumes
  if [ "$max" -eq 0 ]; then       # the documented off switch: said on the audit surface, never silent
    state_audit "$WS" watchdog "repage disabled (notify.repage_max=0) for halt $PG_HID — no re-pages will be sent"
    return 0
  fi
  while [ "$n" -lt "$max" ]; do
    sleep "$interval" & PG_SLEEP=$!
    wait "$PG_SLEEP"; PG_SLEEP=""
    _pager_open; rc=$?
    [ $rc -eq 1 ] && return 0
    if [ $rc -eq 2 ]; then
      # An ack PAUSES; it does not end the ladder, and it does not spend the
      # budget either — `n` is untouched, so `notify.repage_max` still bounds
      # the pages that actually go out and the worst case stays the existing
      # max over a park nobody resolved.
      state_audit "$WS" watchdog "repage held: halt $PG_HID acknowledged less than ${PG_ACK_TIMEOUT}s ago — paging pauses one interval and resumes while the park stands"
      continue
    fi
    n=$((n + 1))
    notify_fire "$WS" park "$PG_REASON" "RE-PAGE $n/$max — PARK $PG_REASON on $WS is still unresolved and unacknowledged. launch.sh status $WS --halt to read it; launch.sh ack $WS pauses these for one window" || true
    state_audit "$WS" watchdog "repage $n/$max halt_id=$PG_HID reason=$PG_REASON"
  done
  notify_fire "$WS" park "$PG_REASON" "RE-PAGE stopped after $max — PARK $PG_REASON on $WS is still unresolved; no further pages until a relaunch" || true
  state_audit "$WS" watchdog "repage cap reached ($max) for halt $PG_HID — paging stops"
}

budget=$(config_get budget.watchdog_relaunches 2>/dev/null) || budget=3
used=0
while :; do
  "$WD_DIR/ferry.sh" "$WS"
  rc=$?
  case $rc in
    0)
      write_final complete "ferry exited complete (rc=0)"
      exit 0 ;;
    20)
      write_final parked "ferry parked deliberately (rc=20); halt surface has the reason"
      pager
      exit 0 ;;
    30|*)
      used=$((used + 1))
      cls=$([ "$rc" -eq 30 ] && echo store_fault || echo crash)
      echo "watchdog: ferry $cls (rc=$rc), relaunch $used/$budget" >&2
      if [ "$used" -ge "$budget" ]; then
        write_final broken "CIRCUIT-BROKEN: relaunch budget exhausted ($used/$budget), last rc=$rc ($cls) — inspect $WS/.runtime/logs and the store; relaunch deliberately via launch.sh"
        notify_fire "$WS" broken "$cls" "CIRCUIT-BROKEN: ferry $cls x$used (last rc=$rc) on $WS" || true
        exit 1
      fi
      sleep 5 ;;
  esac
done
