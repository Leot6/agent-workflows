#!/usr/bin/env bash
# drill/drill-budget.sh — the attempt budget: novel-but-dying attempts exhaust
# budget.stage_attempts and the park names the class (dead), not just the
# budget. Split from drill.sh for `check.sh --jobs`.
# Rows: S7 budget park names the class.
# Skips (rc 77) without tmux.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

echo "-- S7 (budget park names the class): novel-but-dying attempts exhaust the budget -> park dead --"
ws=$(mk_drill_ws drillS7)
printf 'plan-validate=scribble\n' > "$ws/.mock/plan"
log=$(sc_tmpdir)/ferry.log
run_ferry "$ws" "$log"; rc=$?
[ $rc -eq 20 ] && ok "ferry exits 20" || bad "rc=$rc ($(tail -3 "$log"))"
[ "$(halt_kv "$ws" reason)" = "dead" ] \
  && ok "halt reason=dead (budget spent on deaths NAMES the class, not just 'budget')" \
  || bad "halt reason='$(halt_kv "$ws" reason)', want dead"
halt_kv "$ws" detail | command grep -q "attempt budget exhausted" \
  && ok "detail still carries the budget evidence (3/3 attempts)" \
  || bad "detail: $(halt_kv "$ws" detail)"
n=$(ledger_count "$ws" 'event=spawn slice=00 stage=plan-validate')
[ "$n" = "3" ] \
  && ok "exactly budget.stage_attempts=3 spawns (owed-delta kept each retry novel)" \
  || bad "spawn count $n, want 3"
scen_end

check_done
