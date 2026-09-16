#!/usr/bin/env bash
# drill/drill-ruling.sh — the class_u ruling round-trip: a stage halts with
# batched owner questions, a relaunch without a ruling stays parked, a ruling
# recorded through launch.sh respawns the suspended stage with the ruling in
# its manifest. Split from drill.sh for `check.sh --jobs`.
# Rows: S4 class_u ruling round-trip.
# Skips (rc 77) without tmux.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

echo "-- S4: class_u ruling round-trip --"
ws=$(mk_drill_ws drillS4)
printf 'plan-validate:1=halt\nplan-validate:2=ready\nsplit=die\n' > "$ws/.mock/plan"
log=$(sc_tmpdir)/ferry.log
run_ferry "$ws" "$log"; rc=$?
[ $rc -eq 20 ] && ok "run 1: ferry exits 20" || bad "run 1 rc=$rc ($(tail -3 "$log"))"
[ "$(halt_kv "$ws" reason)" = "class_u" ] \
  && ok "halt reason=class_u (record-level --halt routed from the stage)" \
  || bad "halt reason='$(halt_kv "$ws" reason)'"
halt_kv "$ws" detail | command grep -q "MOCK-Q1" \
  && ok "the batched owner questions ride in the park detail" \
  || bad "detail: $(halt_kv "$ws" detail)"
run_ferry "$ws" "$log"; rc=$?
[ $rc -eq 20 ] && ok "run 2 (no ruling): still parked, exit 20" || bad "run 2 rc=$rc"
command grep -q "still parked: class_u" "$log" \
  && ok "resume without a ruling says so (no respawn)" || bad "no 'still parked' message"
[ "$(ledger_count "$ws" 'event=spawn slice=00 stage=plan-validate')" = "1" ] \
  && ok "run 2 spawned nothing (no ruling -> no respawn)" \
  || bad "respawn without a ruling"
sleep 1
shadow_env "$LAUNCH" rule "$ws" --slice 00 --text "MOCK-RULING: pick option A" > /dev/null 2>&1 \
  && ok "launch.sh rule recorded the ruling" || bad "launch.sh rule failed"
precond "ruling archived to slices/00/ruling.1.md" test -s "$ws/slices/00/ruling.1.md"
run_ferry "$ws" "$log"; rc=$?
[ "$(ledger_count "$ws" 'event=spawn slice=00 stage=plan-validate')" = "2" ] \
  && ok "run 3: the suspended stage RESPAWNED after the ruling (round-trip good direction)" \
  || bad "no respawn after ruling; spawns=$(ledger_count "$ws" 'event=spawn slice=00 stage=plan-validate')"
p2=$(ls "$ws/.runtime/prompts/00-plan-validate-"*-a2.md 2>/dev/null | head -1)
precond "attempt-2 prompt file exists" test -n "$p2"
rf=$(command grep -oE '[^ ]*rulings\.00\.[0-9a-f]{32}\.txt' "$p2" | head -1)
if [ -n "$rf" ] && command grep -q "MOCK-RULING" "$rf"; then
  ok "the respawned prompt's manifest carries the ruling (rulings.pending resolved, text present)"
else
  bad "ruling not in the respawn manifest (prompt: $p2)"
fi
# The bundle's name is its content: the manifest may only hand the session a
# path whose filename-hash IS the md5 of the bytes — so "a path I have read"
# can never be "a path whose content changed" (the stale-read defect, two
# anchors).
fh=$(basename "${rf:-x}" .txt); fh=${fh#rulings.00.}
[ -n "$rf" ] && [ "$(md5sum < "$rf" | cut -c1-32)" = "$fh" ] \
  && ok "the bundle path is content-addressed and self-verifying (filename hash = md5 of the file's bytes)" \
  || bad "bundle path not content-addressed: ${rf:-none}"
[ "$(ledger_count "$ws" 'event=enter slice=00 stage=split')" -ge 1 ] \
  && ok "run 3 advanced past the halt into split (ready verdict honored)" \
  || bad "never reached split after ruling"
scen_end

check_done
