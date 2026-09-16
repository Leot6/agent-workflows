#!/usr/bin/env bash
# drill/drill-cancel.sh — the operator cancels the ACTIVE slice while the ferry
# is driving it, and the run reroutes instead of erasing the cancel. This is the
# scenario the learning loop asked for in its own falsifiable
# expectation ("verify by drill scenario: mock a cancel-active + relaunch"); the
# fix landed with fixture coverage at the function level (`42-index` drives
# `slices_set_status` and `reroute_if_slice_retired` directly) and nothing until
# now ran the REAL ferry loop over the path.
#
# What the fixtures cannot show and this can: the cancel lands mid-attempt on a
# live session, the attempt is NOT killed, the ferry notices between attempts,
# tears the slice's sessions down and schedules the next pending id — and the
# topic still reaches COMPLETE with the cancelled slice recorded as cancelled
# rather than done.
# Rows: S16 cancel-active reroute.
# Skips (rc 77) without tmux.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

echo "-- S16 (cancel-active): the operator retires the slice the ferry holds --"
ws=$(mk_drill_ws drillS16)
cat > "$ws/.mock/plan" <<'EOF'
split.slices=01:low:code:first_slice;02:low:code:second_slice
plan-validate=ready
split=done
split-check=concur
spec=drafted
precheck=ready
impl=built
postcheck=conforms
turnover=done
close-out=done
EOF
log=$(sc_tmpdir)/ferry.log
setsid env CONFIG_WORKFLOW_ROOT="$SHADOW" OWED_WORKFLOW_ROOT="$SHADOW" \
  timeout "$DRILL_PATIENCE_S" "$FERRY" "$ws" >> "$log" 2>&1 &
fpid=$!

# Cancel at slice 01's FIRST spawn. Later is not equivalent: once turnover
# advances, `next_slice` marks 01 done and the verb refuses a done slice — the
# scenario would then be testing the refusal, not the reroute.
cancelled=0 vrc=-1
for _ in $(seq 1 "$(drill_ticks)"); do
  if command grep -q 'event=spawn slice=01 stage=spec' <<< "$(state_get "$ws" ledger 2>/dev/null)"; then
    shadow_env "$LAUNCH" slice "$ws" 01 cancelled >> "$log" 2>&1; vrc=$?
    case "$(command grep 'id=01' <<< "$(state_get "$ws" slices 2>/dev/null)")" in
      *status=cancelled*) cancelled=1 ;;
    esac
    break
  fi
  kill -0 "$fpid" 2>/dev/null || break
  sleep 0.2
done
# THE SCENARIO'S PREMISE, asserted rather than assumed. Matching the spawn line
# only proves the poll saw it; the verb can still have arrived after 01 advanced
# to done, in which case it REFUSES and the index reads `done` because nothing
# ever cancelled it. An earlier form of this drill set the flag on the poll and
# then reported that state as "the cancel was erased" — a false diagnosis of the
# code under test, produced by the fixture, which is the shape §2 step 4 exists
# for: assert the two states are observably different before reading either.
[ "$cancelled" -eq 1 ] \
  && ok "the operator's cancel was ACCEPTED (rc $vrc) while slice 01 was the held slice with a live attempt" \
  || { bad "the cancel did not take (verb rc=$vrc, index: $(command grep 'id=01' <<< "$(state_get "$ws" slices 2>/dev/null)")) after ${DRILL_PATIENCE_S}s at loadavg $(drill_load) — the scenario's premise never held, so nothing below is a verdict about the reroute; log tail: $(tail -5 "$log")"; scen_end; check_done; exit $?; }

# The attempt in flight is NOT killed by a cancel — that is `launch.sh stop`.
# It finishes, and the ferry acts at its next turn between attempts.
wait "$fpid" 2>/dev/null; rc=$?
[ "$rc" -eq 0 ] \
  && ok "the ferry ran to COMPLETE after the cancel (rc 0) — a retired slice reroutes, it does not wedge the topic" \
  || bad "rc=$rc; halt=$(halt_kv "$ws" reason) $(halt_kv "$ws" detail); log tail: $(tail -5 "$log")"

idx=$(state_get "$ws" slices 2>/dev/null)
case "$(command grep 'id=01' <<< "$idx")" in
  *status=cancelled*) ok "slice 01 is still CANCELLED at the end of the run (nothing overwrote the operator's decision)" ;;
  *) bad "the cancel was erased: $(command grep 'id=01' <<< "$idx")" ;;
esac
case "$(command grep 'id=02' <<< "$idx")" in
  *status=done*) ok "…and slice 02, the next schedulable id, ran to done" ;;
  *) bad "slice 02 did not run: $(command grep 'id=02' <<< "$idx")" ;;
esac

led=$(state_get "$ws" ledger 2>/dev/null)
case "$led" in
  *"event=slice_retired slice=01"*) ok "the reroute is on the ledger by name (a run's history shows WHY the slice changed)" ;;
  *) bad "no event=slice_retired row: $(command grep -E 'event=(enter|advance|slice_retired)' <<< "$led" | tail -5)" ;;
esac
# ORDER, not mere presence: the enter of 02 must FOLLOW the retirement of 01,
# or the reroute is not what scheduled it.
order=$(command grep -oE 'event=(slice_retired slice=01|enter slice=02)' <<< "$led" | paste -sd, -)
case "$order" in
  "event=slice_retired slice=01,event=enter slice=02"*) ok "…and slice 02 was entered AFTER it, so the reroute is what scheduled the next slice" ;;
  *) bad "reroute/enter order is '$order'" ;;
esac
# The sessions of a retired slice are torn down, not left holding panes.
case "$led" in
  *"event=teardown"*) ok "the retired slice's sessions were torn down (the cancel releases its panes)" ;;
  *) bad "no teardown after the cancel: $(command grep -c 'event=teardown' <<< "$led") teardown rows" ;;
esac
scen_end

check_done
