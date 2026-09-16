#!/usr/bin/env bash
# drill/drill-reslice.sh — the re-slice round-trip walked end to end: a
# turnover proposes a merge, split-check sees the proposal and flags, split
# re-derives the index (minting the merged id, superseding the old one), and
# the topic still reaches COMPLETE. Split from drill-walk.sh so the three
# full-slice walks run concurrently under `check.sh --jobs`.
# Rows: S8 re-slice round-trip.
# Skips (rc 77) without tmux.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

echo "-- S8 (re-slice round-trip): proposal visible to split-check; flag applies via split --"
ws=$(mk_drill_ws drillS8)
cat > "$ws/.mock/plan" <<'EOF'
plan-validate=ready
split=done
split:2=apply
split-check=concur
split-check:2=flag
spec=drafted
precheck=ready
impl=built
postcheck=conforms
turnover:1=reslice
turnover:2=done
close-out=done
EOF
log=$(sc_tmpdir)/ferry.log
run_ferry "$ws" "$log"; rc=$?
[ $rc -eq 0 ] && ok "ferry exits 0: topic COMPLETE through a full re-slice detour" \
  || bad "rc=$rc; halt=$(halt_kv "$ws" reason) $(halt_kv "$ws" detail); log tail: $(tail -5 "$log"); mock: $(tail -8 "$ws/.mock/log" 2>/dev/null)"
p2=$(ls "$ws/.runtime/prompts/00-split-check-r2-"*.md 2>/dev/null | head -1)
precond "split-check round-2 prompt exists" test -n "$p2"
command grep -q "slices/01/turnover.md" "$p2" \
  && ok "the round-2 split-check manifest CARRIES the proposing turnover (two-key concurrence sees the proposal)" \
  || bad "proposal not in the split-check manifest (PROPOSAL unresolved)"
state_get "$ws" slices | command grep "id=01" | command grep -q "status=superseded" \
  && ok "superseded id stays in the index as superseded (ids never reused)" \
  || bad "id=01: $(state_get "$ws" slices | command grep 'id=01')"
state_get "$ws" slices | command grep "id=02" | command grep -q "status=done" \
  && ok "the minted merge slice (02) ran to done" \
  || bad "id=02: $(state_get "$ws" slices | command grep 'id=02')"
chain=$(state_get "$ws" ledger 2>/dev/null \
  | command grep -oE 'event=advance slice=[0-9]+ stage=[a-z-]+' \
  | awk '{print $3}' | cut -d= -f2 | paste -sd, -)
printf '%s' "$chain" | command grep -q "turnover,split-check,split,split-check,spec" \
  && ok "advance chain walks the re-slice detour: …turnover(reslice) -> split-check(flag) -> split(apply) -> split-check(concur) -> spec…" \
  || bad "advance chain '$chain' lacks the re-slice detour"
scen_end

check_done
