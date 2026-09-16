#!/usr/bin/env bash
# 85-watchdog — exit-code classification: deliberate exits (0/20) stop the
# driving with a final-state write; crashes get the bounded relaunch budget and
# then CIRCUIT-BROKEN; a park hands over to the pager, which re-pages an
# unresolved halt to a cap, an ack HOLDING it for one window. Tested against a stub ferry in a
# shadow script dir (the real watchdog.sh + real libs; only ferry.sh is the stub).
# A park arm with NO halt on the store must return at once — the pager decides
# before its first sleep, or this check would hold the default 2700 s interval.
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/fixtures/lib.sh"

base=$(sc_tmpdir)
read -r repo branch < <(mk_repo "$base/repo")

mk_wd() { # rc-of-stub-ferry -> shadow dir
  local d="$base/wd$1"
  mkdir -p "$d"
  cp "$RS/watchdog.sh" "$d/"
  [ -e "$d/lib" ] || ln -sn "$RS/lib" "$d/lib"   # -n: guard against creating inside the real lib
  # The stub runs INSIDE the watchdog's lifetime, so it is the one observer
  # that can see the pidfile held with no race: it records whether the
  # exclusion window was open while the ferry ran. Without that pin, the
  # "cleaned on exit" arm below passes vacuously the day watchdog.sh stops
  # WRITING the pidfile (the refusal arms hand-write their own).
  # …and whether a final-state was on disk WHILE it drove: launch/stop read
  # "class=parked + live pid" as the pager, so a stale final-state beside a
  # live driver must have been cleared by the watchdog before the ferry ran.
  printf '#!/usr/bin/env bash\necho "ferry-stub ws=$1 pidfile=$( [ -e "$1/.runtime/watchdog.pid" ] && echo held || echo MISSING ) final=$( [ -e "$1/.runtime/final-state" ] && echo present || echo absent )" >> "%s/runs.%s"\nexit %s\n' \
    "$base" "$1" "$1" > "$d/ferry.sh"
  chmod +x "$d/ferry.sh"
  printf '%s\n' "$d"
}

echo "-- deliberate exits stop the watchdog --"
ws=$(mk_ws "$base" wdtopic1 "$repo" "$branch")
d=$(mk_wd 0)
assert_rc 0 "ferry rc 0 (complete) -> watchdog exits 0" -- "$d/watchdog.sh" "$ws"
precond "stub ferry ran exactly once" \
  bash -c '[ "$(command grep -c . "$1/runs.0")" = 1 ]' _ "$base"
command grep -q 'class=complete' "$ws/.runtime/final-state" \
  && ok "final-state written: complete (the documented store bypass)" \
  || bad "final-state missing/wrong: $(cat "$ws/.runtime/final-state" 2>/dev/null)"
command grep -q 'pidfile=held' "$base/runs.0" \
  && ok "the pidfile was HELD while the ferry ran (observed from inside the stub — the exclusion window is real)" \
  || bad "the watchdog ran the ferry without holding its pidfile: $(cat "$base/runs.0" 2>/dev/null)"
[ ! -e "$ws/.runtime/watchdog.pid" ] && ok "pidfile cleaned on exit" \
  || bad "pidfile left behind"

ws2=$(mk_ws "$base" wdtopic2 "$repo" "$branch")
d=$(mk_wd 20)
mkdir -p "$ws2/.runtime"; printf 'class=parked detail=a previous run t=1\n' > "$ws2/.runtime/final-state"
assert_rc 0 "ferry rc 20 (deliberate park) -> watchdog exits 0, no relaunch" -- \
  "$d/watchdog.sh" "$ws2"
precond "park stub ran exactly once (no relaunch of a deliberate park)" \
  bash -c '[ "$(command grep -c . "$1/runs.20")" = 1 ]' _ "$base"
command grep -q 'class=parked' "$ws2/.runtime/final-state" \
  && ok "final-state: parked, pointing at the halt surface" || bad "final-state wrong"
command grep -q 'final=absent' "$base/runs.20" \
  && ok "a STALE final-state from a previous run was cleared before the ferry ran (else a relaunch would read a live driver as the pager and kill it)" \
  || bad "the stale final-state was still on disk while the ferry drove: $(cat "$base/runs.20")"

echo "-- crash -> bounded relaunch -> CIRCUIT-BROKEN --"
ws3=$(mk_ws "$base" wdtopic3 "$repo" "$branch")
d=$(mk_wd 7)
assert_rc 1 "crashing ferry exhausts the relaunch budget -> exit 1" -- \
  "$d/watchdog.sh" "$ws3"
budget=$(command grep '^budget.watchdog_relaunches=' "$WF_ROOT/config/defaults.kv" | cut -d= -f2)
runs=$(command grep -c . "$base/runs.7")
precond "config declares the budget ($budget)" test -n "$budget"
[ "$runs" = "$budget" ] \
  && ok "exactly budget=$budget launches (bounded, then stop)" \
  || bad "ran $runs times against budget $budget"
command grep -q 'class=broken' "$ws3/.runtime/final-state" \
  && ok "final-state: broken" || bad "final-state not broken"
command grep -q 'CIRCUIT-BROKEN' "$ws3/.runtime/final-state" \
  && ok "CIRCUIT-BROKEN named with the relaunch count and last rc" \
  || bad "final-state lacks CIRCUIT-BROKEN detail"

echo "-- second watchdog refused while one lives --"
d=$(mk_wd 0)
ws4=$(mk_ws "$base" wdtopic4 "$repo" "$branch")
mkdir -p "$ws4/.runtime"
sleep 60 & sleeper=$!
printf '%s\n' "$sleeper" > "$ws4/.runtime/watchdog.pid"
assert_rc 2 "live pidfile -> second watchdog refuses" -- "$d/watchdog.sh" "$ws4"
assert_out_has "refusing a second" "refusal self-describing"
kill "$sleeper" 2>/dev/null; wait "$sleeper" 2>/dev/null
printf '%s\n' "$sleeper" > "$ws4/.runtime/watchdog.pid"
assert_rc 0 "stale pidfile (dead pid) -> watchdog proceeds" -- "$d/watchdog.sh" "$ws4"

echo "-- the pager: an unresolved park is re-paged to the cap; an ack PAUSES one window, a completion or a resolution stops it --"
# The transport is a script that records every page it is handed, so the count
# and the text of what left the machine are asserted, not the rc.
pgt="$base/pager-transport.sh"
printf '#!/usr/bin/env bash\nprintf "%%s %%s\\n" "$1" "$2" >> "${PAGER_LOG:?}"\n' > "$pgt"; chmod +x "$pgt"
mk_park() { # ws reason halt_id -> an unresolved, already-paged halt on the store
  ( . "$RS/lib/state.sh"
    { echo "reason=$2"; echo "detail=fixture park"; echo "slice=01"; echo "stage=spec"; echo "round=1"
      echo "t=$(date +%s)"; echo "halt_id=$3"; echo "notified=1"; echo "resolved=0"; } | state_set "$1" halt ferry ) > /dev/null
}
d=$(mk_wd 20)
ws5=$(mk_ws "$base" wdtopic5 "$repo" "$branch")
printf 'notify.cmd=%s\nnotify.repage_interval=1\nnotify.repage_max=2\n' "$pgt" > "$ws5/config/topic.kv"
mk_park "$ws5" class_u H5
export PAGER_LOG="$base/pages.5"; : > "$PAGER_LOG"
t0=$(date +%s)
assert_rc 0 "ferry rc 20 over an unresolved, unacked park -> the watchdog re-pages to the cap and exits 0" -- "$d/watchdog.sh" "$ws5"
dt=$(( $(date +%s) - t0 ))
[ "$dt" -ge 2 ] \
  && ok "…waiting the interval before each re-page (${dt}s for repage_max=2 at repage_interval=1 — the config is read, not the default)" \
  || bad "returned in ${dt}s — no interval was waited, or the topic override was not read"
[ "$(command grep -c 'RE-PAGE [0-9]/2 ' "$PAGER_LOG" || true)" -eq 2 ] \
  && ok "exactly repage_max=2 re-pages left through the transport, each numbered n/max" \
  || bad "re-pages through the transport: $(cat "$PAGER_LOG")"
command grep -q 'RE-PAGE stopped after 2' "$PAGER_LOG" \
  && ok "…and the cap sends one final message saying the paging stopped (silence is never the last thing the owner hears)" \
  || bad "no cap message in the transport log: $(cat "$PAGER_LOG")"
command grep -q 'launch.sh ack' "$PAGER_LOG" \
  && ok "the re-page names the verb that stops it" || bad "the re-page does not tell the owner how to stop it"
aud5=$( . "$RS/lib/state.sh"; state_get "$ws5" audit 2>/dev/null || true)
printf '%s\n' "$aud5" | command grep -q 'repage 1/2 halt_id=H5 ' && printf '%s\n' "$aud5" | command grep -q 'repage 2/2 halt_id=H5 ' \
  && printf '%s\n' "$aud5" | command grep -q 'repage cap reached (2) for halt H5' \
  && ok "every re-page and the cap are audited by halt_id (what status --halt counts)" \
  || bad "audit lacks the repage rows: $(printf '%s\n' "$aud5" | command grep repage)"
# ACKED: an ack PAUSES the ladder for notify.ack_timeout and then paging
# RESUMES while the park stands. The predicate is ack FRESHNESS, never ack
# existence — the old test was "an ack row exists", which is not the
# proposition the ladder needs ("a human has this park"): the two differ
# whenever a non-human-facing actor can ack, and cards/pilot.md instructs the
# pilot to ack as its FIRST move. Measured on a live run: pilot acked 71s after
# the park, owner arrived 8h09m35s after it, six pages suppressed.
# The fixture sets ack_timeout ALONGSIDE the shortened interval, which is what
# defaults.kv tells a project shortening repage_interval to do — they are
# separate knobs, and a fixture that shortened only one would wait 45 minutes.
# TWO fixtures, not one, and the split is the fix for a measured flake. The
# single arm here used to set ack_timeout=3, stamp the ack at fixture time and
# assert BOTH that the window held and that it then expired inside one run. That
# is an ORDER between two wall-clock moments the fixture only half controls: it
# picks t_ack, the pager reads `date +%s` whenever it gets scheduled. On
# 2026-09-09 it red three times in one evening at loadavg 30-60 with the same
# assertion — `no 'repage held' row ... 3 repage rows` — because more than three
# seconds passed between the ack row and the first pager cycle. Same shape as
# `50-record`'s ruling stamps, and `maintenance.md` §2 says the same thing about
# it: deterministic contention fixtures, never wall-clock races. Neither half
# below can lose that race, and together they prove more than the original did.
#
# HOLD: an ack that CANNOT go stale (timeout 3600s) must suppress every page and
# spend none of the budget. It holds forever by construction — a held cycle
# `continue`s without incrementing n — so the fixture ends it with SIGTERM, the
# same way the takeover arm below does.
ws6=$(mk_ws "$base" wdtopic6 "$repo" "$branch")
printf 'notify.cmd=%s\nnotify.repage_interval=1\nnotify.repage_max=2\nnotify.ack_timeout=3600\n' "$pgt" > "$ws6/config/topic.kv"
mk_park "$ws6" disagreement H6
( . "$RS/lib/state.sh"; state_audit "$ws6" operator "ack halt_id=H6 reason=disagreement — fixture ack" )
export PAGER_LOG="$base/pages.6"; : > "$PAGER_LOG"
"$d/watchdog.sh" "$ws6" > /dev/null 2>&1 & wpid6=$!
held6=0
for i in $(seq 1 100); do
  ( . "$RS/lib/state.sh"; state_get "$ws6" audit 2>/dev/null ) | command grep -q 'repage held: halt H6' && { held6=1; break; }
  kill -0 "$wpid6" 2>/dev/null || break
  sleep 0.1
done
kill "$wpid6" 2>/dev/null
for i in $(seq 1 30); do kill -0 "$wpid6" 2>/dev/null || break; sleep 0.1; done
wait "$wpid6" 2>/dev/null || true
aud6=$( . "$RS/lib/state.sh"; state_get "$ws6" audit 2>/dev/null )
[ "$held6" -eq 1 ] \
  && ok "an ack that cannot go stale HOLDS the ladder, and the audit says so" \
  || bad "no 'repage held' row — the ack did not pause the ladder: $(printf '%s\n' "$aud6" | command grep -c repage) repage rows"
# here-string, not a pipe: this arm reads GREEN on failure, and a SIGPIPE 141
# from the producer would report the regression absent (R19 / VD-76).
if command grep -qE 'repage [0-9]+/2 halt_id=H6 ' <<< "$aud6"; then
  bad "a held ladder still spent budget: $(command grep repage <<< "$aud6")"
else
  ok "…and spends NO budget while held (no 'repage n/max' row at all — n is untouched)"
fi
[ ! -s "$PAGER_LOG" ] \
  && ok "…and nothing reached the transport while the ack was fresh" \
  || bad "pages went out under a fresh ack: $(cat "$PAGER_LOG")"

# RESUME: an ack that is already STALE must not suppress anything — an ack is a
# pause, never a kill. Stamped an hour in the past, so no scheduling delay can
# make it fresh again.
ws6b=$(mk_ws "$base" wdtopic6b "$repo" "$branch")
printf 'notify.cmd=%s\nnotify.repage_interval=1\nnotify.repage_max=2\nnotify.ack_timeout=3\n' "$pgt" > "$ws6b/config/topic.kv"
mk_park "$ws6b" disagreement H6B
( . "$RS/lib/state.sh"
  state_append "$ws6b" audit operator "v=1 t=$(( $(date +%s) - 3600 )) by=operator msg=ack halt_id=H6B reason=disagreement — a stale fixture ack" ) > /dev/null
export PAGER_LOG="$base/pages.6b"; : > "$PAGER_LOG"
# BOUNDED, and the bound is the point: if a regression makes a stale ack hold,
# a held cycle never increments n and this run would never return — the arm
# would HANG rather than fail. Measured while mutation-testing this very split
# (inverting the freshness comparison hung the check until it was killed by
# hand). `75-watch` states the rule for its virtual clock and it applies here:
# a stalled loop must FAIL an arm, never hang it. rc 124 is a named failure.
assert_rc 0 "a park whose ack has gone STALE -> the ladder runs to the cap (an ack pauses, it never kills; rc 124 = it hung, which is a regression not a slow box)" -- \
  timeout 60 "$d/watchdog.sh" "$ws6b"
aud6b=$( . "$RS/lib/state.sh"; state_get "$ws6b" audit 2>/dev/null )
case "$aud6b" in
  *"repage held: halt H6B"*) bad "a stale ack still held the ladder: $(command grep repage <<< "$aud6b")" ;;
  *) ok "…a stale ack holds NOTHING (freshness is the predicate, never existence)" ;;
esac
[ "$(command grep -c 'RE-PAGE [0-9]/2 ' "$PAGER_LOG" || true)" -eq 2 ] \
  && ok "…and exactly repage_max=2 pages went out past it" \
  || bad "pages past a stale ack: $(cat "$PAGER_LOG")"
printf '%s\n' "$aud6b" | command grep -q 'repage cap reached (2) for halt H6B' \
  && ok "…and the cap is reached and said" \
  || bad "no cap row past a stale ack: $(printf '%s\n' "$aud6b" | command grep repage)"

# notify.ack_timeout=0 is the OFF SWITCH for holding, and it must say so rather
# than behave differently in silence. Its neighbours already set that rule —
# repage_max=0 disables re-paging with an audit row, repage_interval=0 falls
# back — and 0 was the one value here that changed behaviour quietly: the guard
# rejected only non-numerics, so an ack simply never held and nothing said why.
ws6c=$(mk_ws "$base" wdtopic6c "$repo" "$branch")
printf 'notify.cmd=%s\nnotify.repage_interval=1\nnotify.repage_max=2\nnotify.ack_timeout=0\n' "$pgt" > "$ws6c/config/topic.kv"
mk_park "$ws6c" disagreement H6C
( . "$RS/lib/state.sh"; state_audit "$ws6c" operator "ack halt_id=H6C reason=disagreement — fixture ack" )
export PAGER_LOG="$base/pages.6c"; : > "$PAGER_LOG"
# Bounded for the same reason as the stale-ack arm above: EVERY watchdog run
# over a workspace that carries an ack row can hold forever if the freshness
# predicate regresses, because a held cycle never increments n. This one was the
# last unbounded such call, and it is what turned a mutation of `_pager_open`
# into a 600-second hang instead of a named failure — the other arms had already
# reported the regression correctly by then.
assert_rc 0 "ack_timeout=0 -> a fresh ack holds NOTHING and the ladder runs to the cap (rc 124 = it held, which is the off switch failing)" -- \
  timeout 60 "$d/watchdog.sh" "$ws6c"
aud6c=$( . "$RS/lib/state.sh"; state_get "$ws6c" audit 2>/dev/null )
printf '%s\n' "$aud6c" | command grep -q 'ack holds disabled (notify.ack_timeout=0)' \
  && ok "…and the off switch is SAID on the audit surface, never silent (repage_max=0's rule, applied to its neighbour)" \
  || bad "ack_timeout=0 changed behaviour with nothing on the audit surface"
command grep -q 'repage held' <<< "$aud6c" \
  && bad "ack_timeout=0 still held a cycle" \
  || ok "…and no cycle was held at all"

# The red-proof for the other direction: INSIDE the window nothing goes out.
# A long ack_timeout against a 1s interval means the pager can only hold, so a
# bounded run must leave the transport untouched. Without the freshness test
# this same fixture pages immediately.
ws6b=$(mk_ws "$base" wdtopic6b "$repo" "$branch")
printf 'notify.cmd=%s\nnotify.repage_interval=1\nnotify.repage_max=2\nnotify.ack_timeout=900\n' "$pgt" > "$ws6b/config/topic.kv"
mk_park "$ws6b" disagreement H6B
( . "$RS/lib/state.sh"; state_audit "$ws6b" operator "ack halt_id=H6B reason=disagreement — fixture ack" )
export PAGER_LOG="$base/pages.6b"; : > "$PAGER_LOG"
timeout 6 "$d/watchdog.sh" "$ws6b" >/dev/null 2>&1
# FLOORED, because "zero pages" is also what a watchdog that never started
# produces — the same false-floor shape item 5(a) closed in 55-monitor. A held
# cycle audits itself, so the hold row is the proof the loop actually ran.
# The window was 5s, shortened to 3s to buy suite seconds under cap pressure,
# and 3s then FAILED this precond under load — a fixture whose deadline sits
# seconds from the machine's is measuring the machine, which this suite's own
# concurrency note warns about. Restored wider than it began: the seconds are
# cheap and the guarantee is not, and trading a fixture's margin for them is
# the wrong direction even when a cap is pressing.
aud6b=$( . "$RS/lib/state.sh"; state_get "$ws6b" audit 2>/dev/null )
precond "the pager actually ran inside the window (a held cycle is on the audit surface)" \
  bash -c 'printf "%s\n" "$1" | command grep -q "repage held"' _ "$aud6b"
[ ! -s "$PAGER_LOG" ] \
  && ok "zero pages inside the ack window (6s of a 900s window at a 1s interval), and the loop is proved to have run" \
  || bad "a page went out INSIDE the ack window: $(cat "$PAGER_LOG")"
# A COMPLETION is not an alarm: push_gate is never re-paged.
ws7=$(mk_ws "$base" wdtopic7 "$repo" "$branch")
printf 'notify.cmd=%s\nnotify.repage_interval=1\nnotify.repage_max=2\n' "$pgt" > "$ws7/config/topic.kv"
mk_park "$ws7" push_gate H7
export PAGER_LOG="$base/pages.7"; : > "$PAGER_LOG"
assert_rc 0 "a push_gate halt (COMPLETE) -> no re-paging" -- "$d/watchdog.sh" "$ws7"
[ ! -s "$PAGER_LOG" ] && ok "a completion is never re-paged" || bad "push_gate was re-paged: $(cat "$PAGER_LOG")"
# A RESOLVED halt (the ruling landed between the park and the first interval) stops it too.
ws8=$(mk_ws "$base" wdtopic8 "$repo" "$branch")
printf 'notify.cmd=%s\nnotify.repage_interval=1\nnotify.repage_max=2\n' "$pgt" > "$ws8/config/topic.kv"
mk_park "$ws8" class_u H8
( . "$RS/lib/state.sh"; state_put "$ws8" halt ferry "resolved=1" ) > /dev/null
export PAGER_LOG="$base/pages.8"; : > "$PAGER_LOG"
assert_rc 0 "a resolved halt -> no re-paging" -- "$d/watchdog.sh" "$ws8"
[ ! -s "$PAGER_LOG" ] && ok "a resolved park is never re-paged" || bad "a resolved park was re-paged: $(cat "$PAGER_LOG")"

# Rule interaction: a stop-request left by `stop` while the driver ran means
# the operator stopped this topic on purpose — the pager sends nothing.
ws11=$(mk_ws "$base" wdtopic11 "$repo" "$branch")
printf 'notify.cmd=%s\nnotify.repage_interval=1\nnotify.repage_max=2\n' "$pgt" > "$ws11/config/topic.kv"
mk_park "$ws11" class_u H11
mkdir -p "$ws11/.runtime"; printf 't=1 by=operator\n' > "$ws11/.runtime/stop-request"
export PAGER_LOG="$base/pages.11"; : > "$PAGER_LOG"
assert_rc 0 "a stop-request on disk -> the watchdog exits without paging" -- "$d/watchdog.sh" "$ws11"
[ ! -s "$PAGER_LOG" ] && ok "an operator-stopped park is never re-paged" || bad "a stopped park was re-paged: $(cat "$PAGER_LOG")"

# The off switch: repage_max=0 sends nothing and says so on the audit surface;
# without the guard the loop body never ran and the "stopped after 0" page went
# out — a config that says OFF must not produce a page.
ws10=$(mk_ws "$base" wdtopic10 "$repo" "$branch")
printf 'notify.cmd=%s\nnotify.repage_interval=1\nnotify.repage_max=0\n' "$pgt" > "$ws10/config/topic.kv"
mk_park "$ws10" class_u H10
export PAGER_LOG="$base/pages.10"; : > "$PAGER_LOG"
assert_rc 0 "notify.repage_max=0 -> the watchdog exits at once" -- "$d/watchdog.sh" "$ws10"
[ ! -s "$PAGER_LOG" ] && ok "…sending NOTHING (not even a 'stopped after 0' page)" || bad "repage_max=0 still paged: $(cat "$PAGER_LOG")"
( . "$RS/lib/state.sh"; state_get "$ws10" audit 2>/dev/null | command grep -q 'repage disabled (notify.repage_max=0)' ) \
  && ok "…and the audit surface says re-paging is disabled (off is said, never silent)" || bad "no 'repage disabled' audit row"

echo "-- a relaunch's SIGTERM reaches the pager INSIDE its sleep --"
# bash runs a trap the moment a signal arrives during `wait`, but only AFTER a
# foreground `sleep` returns. The first pager slept in the foreground, so a
# takeover's SIGTERM would have sat unanswered for a whole 45-minute interval
# and launch would have refused with "did not exit". Found on re-verification,
# never by a fixture — this arm is that fixture.
ws9=$(mk_ws "$base" wdtopic9 "$repo" "$branch")
printf 'notify.cmd=%s\nnotify.repage_interval=60\nnotify.repage_max=2\n' "$pgt" > "$ws9/config/topic.kv"
mk_park "$ws9" class_u H9
export PAGER_LOG="$base/pages.9"; : > "$PAGER_LOG"
"$d/watchdog.sh" "$ws9" > /dev/null 2>&1 & wpid=$!
for i in $(seq 1 50); do [ -f "$ws9/.runtime/final-state" ] && break; sleep 0.1; done
sleep 0.3   # past _pager_open, into the wait
precond "the watchdog reached the pager (final-state parked on disk, process alive)" \
  bash -c 'command grep -q "^class=parked " "$1/.runtime/final-state" && kill -0 "$2"' _ "$ws9" "$wpid"
t0=$(date +%s%N)
kill "$wpid"
for i in $(seq 1 30); do kill -0 "$wpid" 2>/dev/null || break; sleep 0.1; done
wait "$wpid" 2>/dev/null; wrc=$?
dt=$(( ($(date +%s%N) - t0) / 1000000 ))
if ! kill -0 "$wpid" 2>/dev/null && [ "$dt" -lt 2500 ]; then
  ok "SIGTERM ended the paging watchdog in ${dt}ms with a 60s interval pending (the trap ran inside wait, not after the sleep)"
else
  bad "the paging watchdog survived SIGTERM for ${dt}ms with a 60s interval — a relaunch would refuse the takeover"
  kill -9 "$wpid" 2>/dev/null
fi
[ "$wrc" -eq 0 ] && ok "…and it exited 0 (a takeover is not a crash)" || bad "exit rc=$wrc on SIGTERM"
[ ! -e "$ws9/.runtime/watchdog.pid" ] && ok "…and cleared its pidfile on the way out" || bad "pidfile left behind after SIGTERM"
[ ! -s "$PAGER_LOG" ] && ok "…having sent no re-page (the interval had not elapsed)" || bad "a re-page went out: $(cat "$PAGER_LOG")"
unset PAGER_LOG

echo "-- doc closure: the retired ack claim is gone from every OPERATOR-FACING surface --"
# One fact with many homes — a measured shape. The ack predicate was
# described in thirteen-plus places; one commit changed the mechanism
# and corrected four, and the claim that an ack ENDS the paging survived on
# twelve more, two of them directly against the code that replaced them and one
# denying, in a design document, the thing the commit implemented. Nothing
# watched that the correction reached all of them.
#
# NOT IN 30-closure, which is doc closure's natural home: that file is at
# 998/1000 against cap.selftest_file and cannot take an arm. f89ddc7's
# disagreement-prefix arm was displaced into 45-halt for the same reason. This
# one lands here because 85-watchdog owns the pager and the ack semantics it
# guards; a check displaced by a cap reads as arbitrary six months later, so the
# cap that caused it is written down while it is still live context.
#
# SCOPED BY AUDIENCE, NOT BY AN ALLOWLIST. `iteration-log/` is excluded because
# it is historical by contract — its entries QUOTE the retired text as the
# evidence for why the fix happened. Under `self-check/` the exclusion is
# `checks/` and `drill/` ONLY, and the narrowing is the point: those two hold
# failure strings that must KEEP the retired wording (the arm above prints "an
# ack still ends the ladder" when the fix is REVERTED — describing the wrong
# state correctly), but `validation-debt.md` is a DOCUMENT a future maintainer
# ACTS ON, and excluding the whole directory hid it. Measured: VD-66's mechanism
# text still described the retired behaviour three days after the fix, so a
# maintainer closing that row would have verified the wrong behaviour, and only a
# hand read reached it. Audience is the criterion, and a debt row's audience is
# a maintainer.
# This tree's own rule is why an allowlist would be the wrong instrument: a list
# of what is provably inert stays honest as the tree grows, while a list of
# dangers goes stale in silence — and an audience scope is DERIVABLE, whereas an
# allowlist is a second home for the judgment.
ack_retired() { # <path>... -> prints offending citations; rc 0 clean / 1 found-or-broken
  local hits
  # the retired claim is specifically "an ack ENDS the paging". "unacknowledged"
  # is NOT in the family: it stays legitimate in the re-page CONDITION, and a
  # raw sweep for it over-flags `operations.md` §1, which is already correct.
  #
  # MATCHED ACROSS LINES, and that is a correction. The shipped form was a
  # `grep -rnEi`, which is line-anchored — and this tree wraps prose. Two of the
  # twelve instances the fix removed were split across a line boundary and the
  # guard could see NEITHER: `launch.sh`'s banner ("...the watchdog stops" /
  # "re-paging it...") and `defaults.kv`'s ("...every interval until" /
  # "`launch.sh ack`"). Its three red-proofs were all synthetic single lines,
  # which is exactly why the gap survived the proof.
  # Three-line windows, whitespace collapsed; the JOINED lines lose their own
  # comment marker, because "stops" followed by "# re-paging" is one sentence to
  # the reader this guard protects and two to a matcher. The hit is reported at
  # the line the match STARTS on (RSTART within the first line's length), so a
  # single-line instance is still named at its own line, not at the two above it.
  hits=$(find "$@" \( -name checks -o -name drill \) -prune -o -type f -print 2>/dev/null | sort \
    | while read -r f; do
        awk -v F="$f" '
          # `rep()` BUILDS a bounded repetition — mawk has no ERE intervals, and
          # the bound is load-bearing here: it keeps a match local inside the
          # joined three-line window instead of spanning it. `cls "?"` n times
          # is exactly `cls{0,n}` and needs no interval to say so.
          function rep(cls, n,   i, s) { s = ""; for (i = 0; i < n; i++) s = s cls "?"; return s }
          BEGIN { np = 0
            P[np++] = "stops? re-paging"
            P[np++] = "re-paging stops"
            P[np++] = "ends the ladder"
            P[np++] = "until " rep("[^|]", 15) "launch\\.sh ack"
            P[np++] = "ack " rep(".", 20) " to stop"
          }
          function collapse(x) { gsub(/[ \t]+/, " ", x); sub(/^ /, "", x); sub(/ $/, "", x); return x }
          function decomment(x) { sub(/^[ \t]*(#+|>+|\/\/|\*)[ \t]*/, "", x); return x }
          { L[NR] = $0 }
          END {
            for (i = 1; i <= NR; i++) {
              a = collapse(L[i]); if (length(a) == 0) continue
              w = a " " collapse(decomment(L[i+1])) " " collapse(decomment(L[i+2]))
              lw = tolower(w); la = length(a)
              for (p = 0; p < np; p++)
                if (match(lw, P[p]) && RSTART <= la) { printf "%s:%d: %s\n", F, i, a; break }
              if (index(w, "无 ack、无重发") > 0 && index(a, "无 ack、无重发") > 0)
                printf "%s:%d: %s\n", F, i, a
            }
          }' "$f" || echo "SWEEPFAIL $f"
      done)
  # The rc split is KEPT (97-iterlog's rule) — a clean verdict and a matcher that
  # did not complete are not the same silence — but a per-file awk cannot carry
  # that in a pipeline's status, so the failure rides in the output instead.
  case "$hits" in
    *SWEEPFAIL*) printf '%s\n' "$hits"
                 echo "the operator-surface sweep did not complete — this is not a clean verdict"
                 return 1 ;;
  esac
  [ -z "$hits" ] && return 0
  printf '%s\n' "$hits"; return 1
}
ack_scope() { printf '%s\n' "$1/runtime-scripts" "$1/runtime-docs" "$1/config" "$1/design" "$1/self-check" "$1/README.md" "$1/overview.html"; }
# FLOORED: the day a directory is renamed the sweep would see nothing and read
# clean, which is the failure mode a doc-closure check exists to prevent.
# the floor counts EXACTLY what the sweep reads — same prune, or the precond
# would vouch for files the grep never opened.
n_ack=$(find $(ack_scope "$WF_ROOT") \( -name checks -o -name drill \) -prune -o -type f -print 2>/dev/null | command grep -c . || true)
precond "the operator-surface sweep sees N>=40 files (saw ${n_ack:-0})" test "${n_ack:-0}" -ge 40
# shellcheck disable=SC2046
ack_out=$(ack_retired $(ack_scope "$WF_ROOT")); ack_rc=$?
[ $ack_rc -eq 0 ] \
  && ok "no operator-facing surface still says an ack ENDS the paging (${n_ack} files swept)" \
  || bad "the retired ack claim survives on an operator surface:"$'\n'"$(printf '%s' "$ack_out" | sed 's|^|    |')"

# red-proof: re-introduce one retired phrase into a scratch copy of an IN-SCOPE
# file and confirm the arm names it, file and all.
ack_fake=$(sc_tmpdir)/opsurface
mkdir -p "$ack_fake/runtime-docs"
cp "$WF_ROOT/runtime-docs/cards/pilot.md" "$ack_fake/runtime-docs/pilot.md"
printf '\nthe watchdog stops re-paging once you ack.\n' >> "$ack_fake/runtime-docs/pilot.md"
ack_bad=$(ack_retired "$ack_fake"); [ $? -eq 1 ] \
  && printf '%s\n' "$ack_bad" | command grep -q 'pilot.md' \
  && ok "known-bad: one re-introduced phrase FIRES and names the file it is in" \
  || bad "the retired-claim sweep is vacuous — a re-introduced 'stops re-paging' read as clean"
# WRAPPED known-bad — the shape the line-anchored form could not see, both
# instances taken VERBATIM from the tree before the twelve were corrected. A
# synthetic single line cannot prove this arm; those were the proofs that let the
# gap through.
ack_wrap=$(sc_tmpdir)/opwrap
mkdir -p "$ack_wrap/runtime-scripts" "$ack_wrap/config"
printf '#   ack <ws>                     acknowledge the current park: the watchdog stops\n#                                re-paging it (nothing else changes; resume is\n#                                still rule / relaunch)\n' \
  > "$ack_wrap/runtime-scripts/launch.sh"
printf '# watchdog RE-PAGES an unresolved, unacknowledged park every interval until\n# `launch.sh ack`, a resolution, or the cap; the cap keeps an unattended\n# weekend from turning the channel into noise.\n' \
  > "$ack_wrap/config/defaults.kv"
ack_w=$(ack_retired "$ack_wrap"); [ $? -eq 1 ] \
  && printf '%s\n' "$ack_w" | command grep -q 'launch.sh:1:' \
  && printf '%s\n' "$ack_w" | command grep -q 'defaults.kv:1:' \
  && ok "known-bad: BOTH wrapped retired claims fire and are named at the line each STARTS on (the two the line-anchored form missed)" \
  || bad "the sweep is still line-anchored — a claim split across a line boundary reads as clean (got: ${ack_w:-<nothing>})"
# and the matcher must not invent one
printf 'the watchdog pauses re-paging for one window.\n' > "$ack_fake/runtime-docs/pilot.md"
ack_retired "$ack_fake" >/dev/null 2>&1 \
  && ok "…and the corrected wording does NOT fire (the family is the retired claim, not the word 'ack')" \
  || bad "the sweep fires on the CORRECTED wording — it would forbid the fix it exists to protect"

check_done
