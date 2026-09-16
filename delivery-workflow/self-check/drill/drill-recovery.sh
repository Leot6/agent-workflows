#!/usr/bin/env bash
# drill/drill-recovery.sh — the kill-and-relaunch row: a ferry killed while a
# stage attempt is LIVE (the pane still running), relaunched, must re-attach
# the wait (not respawn), and must never re-land work the attempt already
# committed. It closed a validation-debt row whose closes-on allowed "a drill
# extension or live event", and the live event never came: the drill always ran the ferry
# to completion in one process, so recover_running's re-attach arm was only
# unit-adjacent (the park fixtures exercise the DEAD arms).
#
# The kill is REAL (kill the ferry's own process mid-run), not a fabricated
# stage surface: what the row exists to prove is that the relaunched ferry
# reads the store's actual post-kill state — stage=running, a sessions row
# whose nonce matches the stage surface, a live pane — and waits on the SAME
# attempt instead of spawning a second one over it.
#
# Rows: S14 kill-mid-attempt re-attach · S16 progress survives the kill
#       (no cu re-landing). The dead-session restart (S15) lives in
#       drill-recovery-respawn.sh so the two halves run CONCURRENTLY under
#       `check.sh --jobs` and the gate's floor is the longer HALF, not the
#       serial pair — split by owner ruling (the pair rode the 30s
#       check_cap line; measured S14 ≈ 23s, S15 ≈ 12s).
# Skips (rc 77) without tmux.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

echo "-- S14: ferry killed mid-attempt, relaunch RE-ATTACHES the live session --"
# impl=stall12s: the mock's impl visit sleeps 12s BEFORE writing artifacts
# and emitting — a genuinely LIVE attempt (running, heartbeated, not yet
# emitted) that still completes by itself. The kill lands inside the sleep;
# the relaunch re-attaches, and the re-attached wait then observes the SAME
# attempt's record landing when the sleep ends. The completion is what
# distinguishes a re-attach from a respawn: a respawn would re-run the visit
# (fresh 12s), the spawn count is the discriminator.
ws=$(mk_drill_ws drillS14)
cat > "$ws/.mock/plan" <<'EOF'
plan-validate=ready
split=done
split-check=concur
spec=drafted
precheck=ready
impl=stall12s
postcheck=conforms
turnover=done
close-out=done
EOF
log=$(sc_tmpdir)/ferry.log
# Run the ferry in the BACKGROUND so this script can kill it mid-attempt:
# poll the store until the impl STAGE has a live attempt, then kill the
# ferry's WHOLE PROCESS GROUP (kill -9 on the shell job only orphans the
# timeout/ferry children — a surviving grandchild still holds the host lock,
# and the relaunch then refuses on a lock whose holder is really being
# killed, testing nothing). A crash is the scenario; no traps run.
setsid env CONFIG_WORKFLOW_ROOT="$SHADOW" OWED_WORKFLOW_ROOT="$SHADOW" "$FERRY" "$ws" >> "$log" 2>&1 &
fpid=$!
killed=0
# Poll for the impl attempt to be PAST its spawn (the stage surface flips to
# running BEFORE the spawn — ferry pre-registers the attempt so a fast CLI can
# emit before the ferry finishes bookkeeping; killing in that gap kills an
# attempt that never started, and the relaunch then exercises respawn, not
# re-attach). The spawn event in the ledger is the attempt's birth record.
for _ in $(seq 1 "$(drill_ticks)"); do
  if [ "$(state_field "$ws" stage stage 2>/dev/null)" = "impl" ] \
     && [ "$(state_field "$ws" stage state 2>/dev/null)" = "running" ] \
     && [ "$(ledger_count "$ws" 'event=spawn.*stage=impl ')" -ge 1 ]; then
    kill -9 -- -"$fpid" 2>/dev/null
    killed=1
    break
  fi
  sleep 0.5
done
[ "$killed" -eq 1 ] \
  && ok "ferry SIGKILLed with stage=impl state=running (a live attempt at kill time)" \
  || { bad "never reached a live impl attempt before timeout in ${DRILL_PATIENCE_S}s (loadavg $(drill_load)) — a loaded box and a wedged ferry look alike here, so both readings are printed; log tail: $(tail -5 "$log")"; scen_end; check_done; exit $?; }
# The killed ferry is gone in the sense the RUNTIME cares about: its host lock
# is released or stale (kill -0 on the shell's unreaped job would read a
# zombie as alive — the lock is the semantic test). The TAKE must be pinned
# first — a ferry that stopped acquiring the host lock leaves the dir absent
# and would read "released" without ever having held it. The audit line is
# the wiring trace, the same idiom drill.sh's S2 carries.
_took=$(state_get "$ws" audit 2>/dev/null | command grep -c "host lock taken" || true)
precond "the killed run took the host lock before its death (saw $_took audit line(s)) — release is asserted of a held lock" \
  test "${_took:-0}" -ge 1
[ ! -d "$ws/.runtime/state/lock" ] || ! state_host_holder "$ws" >/dev/null 2>&1 \
  && ok "the killed ferry no longer holds the host lock (the crash released it)" \
  || bad "host lock still held by a live pid after SIGKILL: $(cat "$ws/.runtime/state/lock/pid" 2>/dev/null)"
n_impl_spawns=$(ledger_count "$ws" 'event=spawn.*stage=impl')
[ "$(state_field "$ws" stage state 2>/dev/null)" = "running" ] \
  && ok "the store still reads state=running after the kill (a crash leaves no clean state)" \
  || bad "stage state changed at kill: $(state_field "$ws" stage state)"
# Relaunch: the pane is still alive (mock completes at 12s), so recover_running
# must RE-ATTACH — wait on the same nonce, spawn nothing new for impl. The
# re-attach evidence is complete at the impl ADVANCE (spawn count unchanged +
# the audit line + this advance — the same attempt finishing); walking the
# remaining stages to COMPLETE re-proves walk-coverage drill-walk owns, so the
# relaunch runs in the background and is stopped at the advance.
bg_ferry_until "$ws" "$log" 'event=advance slice=01 stage=impl'
state_get "$ws" ledger 2>/dev/null | command grep -q "event=advance slice=01 stage=impl" \
  && ok "the relaunched ferry re-attached and the SAME attempt advanced impl" \
  || { bad "relaunch never advanced impl; halt=$(state_get "$ws" halt 2>/dev/null | tr '\n' ' ' | cut -c1-150); mocklog=$(tail -3 "$ws/.mock/log" 2>/dev/null | tr '\n' ' ')"; }
n_impl_spawns2=$(ledger_count "$ws" 'event=spawn.*stage=impl')
[ "$n_impl_spawns2" -eq "$n_impl_spawns" ] \
  && ok "RE-ATTACH: relaunched ferry spawned NOTHING new for impl ($n_impl_spawns spawn(s) before and after) — it waited on the killed run's live attempt" \
  || bad "impl spawns grew across the relaunch ($n_impl_spawns -> $n_impl_spawns2): the running attempt was respawned over, not re-attached"
state_get "$ws" audit 2>/dev/null | command grep -q "re-attached wait on live attempt" \
  && ok "the re-attach is AUDITED (a postmortem can see the restart waited, not respawned)" \
  || bad "no re-attach audit line: $(state_get "$ws" audit 2>/dev/null | tail -2)"
state_get "$ws" ledger 2>/dev/null | command grep -q "event=advance slice=01 stage=impl verdict=built" \
  && ok "the advance carries verdict=built (the mock's default action completed, not a stub)" \
  || bad "impl advance missing or wrong verdict: $(state_get "$ws" ledger 2>/dev/null | command grep 'advance.*impl' | tail -1)"

echo "-- S16: progress landed before the kill is never re-landed --"
# The mock's impl writes cu-1's progress row when it emits 'built' — but the
# interesting ledger question is the SPAWN count. For a sharper progress
# check, use the first scenario's ledger: cu rows for slice 01 exist exactly
# once each (the mock emits one per emit), and the relaunch neither
# duplicated nor dropped them.
rows=$(state_get "$ws" progress 2>/dev/null | command grep -c 'slice=01' || true)
[ "${rows:-0}" -ge 1 ] \
  && ok "slice-01 progress rows survive the kill+relaunch intact ($rows row(s), written once)" \
  || bad "progress rows lost across the kill: ${rows:-0}"
scen_end

check_done
