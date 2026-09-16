#!/usr/bin/env bash
# drill/drill-recovery-respawn.sh — the DEAD-session half of the
# kill-and-relaunch row (drill-recovery.sh holds the live-pane re-attach
# half): same kill, but every pane is dead at relaunch, so recover_running
# must mark the attempt failed(dead) and spawn EXACTLY ONE fresh attempt —
# no ghost re-attach, no thrash. Split from drill-recovery.sh so the two
# halves run concurrently under `check.sh --jobs` by owner ruling
# (the serial pair rode the 30s check_cap line; measured S14 ≈ 23s,
# S15 ≈ 12s, and the two build separate workspaces and tmux servers
# anyway — the split changes nothing the scenarios share).
# Rows: S15 dead-session restart.
# Skips (rc 77) without tmux.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

echo "-- S15: same kill, but the pane is DEAD at relaunch -> failed(dead), one respawn --"
# Kill the pane too: recover_running's dead arm must mark the attempt
# failed(dead) and the loop spawns a FRESH attempt (visit 2 = built), not
# re-attach a ghost. Same live-attempt kill point: visit 1 sleeps 12s before
# completing, we kill the ferry AND every pane mid-sleep, so the relaunch
# finds a dead session pointer and must respawn (visit 2 completes fast).
ws2=$(mk_drill_ws drillS15)
cat > "$ws2/.mock/plan" <<'EOF'
plan-validate=ready
split=done
split-check=concur
spec=drafted
precheck=ready
impl:1=stall12s
impl=built
postcheck=conforms
turnover=done
close-out=done
EOF
log2=$(sc_tmpdir)/ferry2.log
setsid env CONFIG_WORKFLOW_ROOT="$SHADOW" OWED_WORKFLOW_ROOT="$SHADOW" "$FERRY" "$ws2" >> "$log2" 2>&1 &
fpid2=$!
killed2=0
for _ in $(seq 1 "$(drill_ticks)"); do
  if [ "$(state_field "$ws2" stage stage 2>/dev/null)" = "impl" ] \
     && [ "$(state_field "$ws2" stage state 2>/dev/null)" = "running" ] \
     && [ "$(ledger_count "$ws2" 'event=spawn.*stage=impl ')" -ge 1 ]; then
    kill -9 -- -"$fpid2" 2>/dev/null
    killed2=1
    break
  fi
  sleep 0.5
done
[ "$killed2" -eq 1 ] && ok "second ferry SIGKILLed at a live impl attempt" \
  || { bad "S15 never reached a live impl attempt in ${DRILL_PATIENCE_S}s (loadavg $(drill_load)) — a loaded box and a wedged ferry look alike here, so both readings are printed; log tail: $(tail -5 "$log2")"; scen_end; check_done; exit $?; }
# Kill every delivery session pane: the crash took the pane with it (or the
# operator cleaned up) — the sessions row is now a dead pointer.
tmux list-sessions -F '#{session_name}' 2>/dev/null | command grep '^delivery-' \
  | while IFS= read -r s; do tmux kill-session -t "=$s" 2>/dev/null; done
# The relaunch must run to completion; give the respawned attempt its turn.
n15_before=$(ledger_count "$ws2" 'event=spawn.*stage=impl ')
# The dead-session restart's evidence completes at the FRESH attempt's impl
# advance (the failed(dead) audit + exactly-one respawn + that advance); the
# rest of the walk is drill-walk's coverage, so the restart ferry is stopped
# at the advance.
bg_ferry_until "$ws2" "$log2" 'event=advance slice=01 stage=impl'
state_get "$ws2" audit 2>/dev/null | command grep -q "attempt session dead, marked failed(dead)" \
  && ok "the dead attempt was marked failed(dead) — the audit names what the restart found" \
  || bad "no failed(dead) audit line: $(state_get "$ws2" audit 2>/dev/null | tail -2)"
n15_after=$(ledger_count "$ws2" 'event=spawn.*stage=impl ')
[ "$n15_after" -eq $((n15_before + 1)) ] \
  && ok "the dead attempt respawned EXACTLY ONCE ($n15_before -> $n15_after; no ghost re-attach, no thrash)" \
  || bad "impl spawns across the dead-session restart: $n15_before -> $n15_after (want +1)"
state_get "$ws2" ledger 2>/dev/null | command grep -q "event=advance slice=01 stage=impl verdict=built" \
  && ok "the FRESH attempt completed impl (stall then built, per the plan's visit table)" \
  || bad "impl never advanced after the dead-session restart"

scen_end

check_done
