#!/usr/bin/env bash
# drill/drill.sh — the SHORT ferry rows: every way a run refuses, parks or is
# forced cold, each reaching its verdict in seconds. The longer rows live in
# their own files so `check.sh --jobs` runs them at once and the suite's wall
# is the longest ONE: drill-backend.sh (per-assignment profile, backend
# switch), drill-ruling.sh (class_u round-trip), drill-budget.sh (budget park),
# drill-walk.sh / drill-reslice.sh / drill-tworepo.sh (full walks) and
# drill-probe*.sh (the onboarding probe). All build their own shadow tree and
# tmux server (drill/lib.sh).
# Rows: S1 template_error · S11 config fault · S2 owed_miss · S3 no_novelty ·
#   S6 all_cold · S7b operator stop.
# Skips (rc 77) without tmux.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

echo "-- S1 template_error: required manifest missing -> park BEFORE any spawn --"
ws=$(mk_drill_ws drillS1)
precond "the fabricated probe record satisfies ferry.sh's OWN fact guard (else every scenario below parks template_error instead of testing what it says it tests)" \
  shadow_env bash "$SHADOW/runtime-scripts/probe.sh" --verify "$ws" "$SHADOW/config/backends/test.kv" test
rm -f "$ws/../plan.md"
log=$(sc_tmpdir)/ferry.log
run_ferry "$ws" "$log"; rc=$?
[ $rc -eq 20 ] && ok "ferry exits 20 (deliberate park)" || bad "rc=$rc, want 20 ($(tail -3 "$log"))"
[ "$(halt_kv "$ws" reason)" = "template_error" ] \
  && ok "halt reason=template_error" || bad "halt reason='$(halt_kv "$ws" reason)'"
halt_kv "$ws" detail | command grep -q "PLAN" \
  && ok "park detail NAMES the missing manifest item (PLAN=plan.md)" \
  || bad "detail does not name the item: $(halt_kv "$ws" detail)"
# The zero below is over THIS ledger, so the ledger must first be proven
# alive — a run whose ledger never got a row would read as the safest run
# there is. The park row is the run's own birth record on that surface.
_park=$(ledger_count "$ws" 'event=park reason=template_error')
precond "this park landed on the ledger (saw $_park row) — the spawn count below reads a live surface" \
  test "$_park" -ge 1
[ "$(ledger_count "$ws" 'event=spawn')" = "0" ] \
  && ok "no session was ever spawned (parked at compose)" || bad "spawn happened despite template_error"
scen_end

echo "-- S11 (config faults park, they do not kill): a slice override with an unknown key --"
# config_get validates EVERY file in the resolution chain on every read
# (defaults.kv, topic.kv, slice.<nn>.<agent>.kv) and the ferry answered rc 3
# with die_store: exit 30 under a store_fault banner, naming the STORE for an
# operator's typo. Loud, but misattributed and fatal where a park would do —
# the store is checksummed and a fault there is corruption, while a topic/slice
# kv file is a workflow/topic INPUT, which is what template_error already
# names. The watchdog also treated it as a crash and spent its relaunch budget
# re-running a config that could not resolve.
ws=$(mk_drill_ws drillS11)
printf 'plan-validate=ready\n' > "$ws/.mock/plan"
printf 'no.such.key=1\n' > "$ws/config/slice.00.author.kv"
precond "the fixture override really faults the resolver (rc 3, not merely absent)" \
  bash -c '. "$1/lib/config.sh"; config_get agent.author.backend --topic-dir "$2" --slice 00 --agent author >/dev/null 2>&1; [ $? -eq 3 ]' \
  _ "$RS" "$ws"
log=$(sc_tmpdir)/ferry.log
run_ferry "$ws" "$log"; rc=$?
[ $rc -eq 20 ] && ok "ferry PARKS (exit 20) on a config fault — never exit 30, which is the store's code" \
  || bad "rc=$rc, want 20 ($(tail -3 "$log"))"
[ "$(halt_kv "$ws" reason)" = "template_error" ] \
  && ok "halt reason=template_error (the input-defect class), not store_fault" \
  || bad "halt reason='$(halt_kv "$ws" reason)'"
halt_kv "$ws" detail | command grep -q "agent.author.backend" \
  && ok "the park detail names the KEY whose resolution faulted" \
  || bad "detail: $(halt_kv "$ws" detail)"
command grep -q "no.such.key" "$log" \
  && ok "and the resolver's own CONFIG FAULT line names the offending key and file on stderr" \
  || bad "the unknown key was never named: $(tail -3 "$log")"
_park=$(ledger_count "$ws" 'event=park reason=template_error')
precond "this park landed on the ledger (saw $_park row) — the spawn count below reads a live surface" \
  test "$_park" -ge 1
[ "$(ledger_count "$ws" 'event=spawn')" = "0" ] \
  && ok "no session was spawned into a config that cannot resolve" \
  || bad "spawned despite the fault"
scen_end

echo "-- S2 (first-miss owed park): DONE record with missing owed -> park owed_miss on FIRST miss, no respawn --"
ws=$(mk_drill_ws drillS2)
printf 'plan-validate=direct\n' > "$ws/.mock/plan"
log=$(sc_tmpdir)/ferry.log
run_ferry "$ws" "$log"; rc=$?
[ $rc -eq 20 ] && ok "ferry exits 20" || bad "rc=$rc ($(tail -3 "$log"))"
precond "the direct (artifact-less) record actually landed" \
  bash -c '. "$1/lib/state.sh"; state_get "$2" handoff | command grep -q "stage=plan-validate .*verdict=ready\|verdict=ready"' _ "$RS" "$ws"
[ "$(halt_kv "$ws" reason)" = "owed_miss" ] \
  && ok "halt reason=owed_miss" || bad "halt reason='$(halt_kv "$ws" reason)'"
halt_kv "$ws" detail | command grep -q "validation_note" \
  && ok "park detail lists EXACTLY what is missing (validation_note)" \
  || bad "detail: $(halt_kv "$ws" detail)"
[ "$(ledger_count "$ws" 'event=spawn slice=00 stage=plan-validate')" = "1" ] \
  && ok "exactly ONE spawn — first miss parks, never an identical respawn" \
  || bad "spawn count $(ledger_count "$ws" 'event=spawn slice=00 stage=plan-validate')"
state_get "$ws" ledger | tail -1 | command grep -q "event=park reason=owed_miss" \
  && ok "park is the last ledger event (nothing after the miss)" \
  || bad "ledger tail: $(state_get "$ws" ledger | tail -1)"
# Exclusivity wiring trace: 15-locks proves the lock FUNCTIONS refuse a live
# holder; these lines prove the production main() actually TAKES them (a
# mutation deleting both take_* calls from main() left the whole suite green).
state_get "$ws" audit 2>/dev/null | command grep -q "host lock taken" \
  && ok "main() took the host lock (wiring trace in the audit surface)" \
  || bad "no 'host lock taken' audit line — the host lock is not wired into the production entry"
state_get "$ws" audit 2>/dev/null | command grep -q "repo lock taken" \
  && ok "main() took the repo lock (wiring trace)" \
  || bad "no 'repo lock taken' audit line — the repo lock is not wired into the production entry"
s2repo=$(awk -F= '$1=="repo"{print $2}' "$ws/project.kv")
s2lock=$(git -C "$s2repo" rev-parse --absolute-git-dir)/delivery.lock
[ -f "$s2lock" ] && command grep -q "drillS2" "$s2lock" \
  && ok "the parked topic still holds .delivery.lock naming its workspace (released only at COMPLETE/reclaim)" \
  || bad "repo lock absent or anonymous after a park: $(cat "$s2lock" 2>/dev/null | tr '\n' ' ')"
mon=$("$RS/monitor.sh" "$ws" --once 2>/dev/null || true)   # capture, then grep: grep -q + pipefail would SIGPIPE the monitor
{ command grep -q "PARKED — needs you" <<< "$mon" \
  && command grep -q "reason .*owed_miss" <<< "$mon"; } \
  && ok "monitor --once renders the park as the headline, naming this park's reason (read-only store view)" \
  || bad "monitor does not show the park: $(printf '%s\n' "$mon" | command grep -m1 'PARKED\|reason')"
scen_end

echo "-- S3 (loop detector): second identical attempt -> park no_novelty --"
ws=$(mk_drill_ws drillS3)
printf 'plan-validate=die\n' > "$ws/.mock/plan"
log=$(sc_tmpdir)/ferry.log
run_ferry "$ws" "$log"; rc=$?
[ $rc -eq 20 ] && ok "ferry exits 20" || bad "rc=$rc ($(tail -3 "$log"))"
[ "$(halt_kv "$ws" reason)" = "no_novelty" ] \
  && ok "halt reason=no_novelty (not budget_attempts: the loop is proven before the budget)" \
  || bad "halt reason='$(halt_kv "$ws" reason)'"
halt_kv "$ws" detail | command grep -q "fingerprint" \
  && ok "detail names the fingerprint match" || bad "detail: $(halt_kv "$ws" detail)"
n=$(ledger_count "$ws" 'event=spawn slice=00 stage=plan-validate')
[ "$n" = "2" ] \
  && ok "exactly 2 spawns: death changes the failure class once (novel), then identical -> park" \
  || bad "spawn count $n, want 2"
scen_end

echo "-- S6: all_cold forces cold spawns but keeps the static template --"
ws=$(mk_drill_ws drillS6 "all_cold=true")
printf 'plan-validate=ready\nsplit=die\n' > "$ws/.mock/plan"
log=$(sc_tmpdir)/ferry.log
run_ferry "$ws" "$log"; rc=$?
[ "$(halt_kv "$ws" reason)" != "template_error" ] \
  && ok "no false template_error: warm-row stage under all_cold renders its warm template" \
  || bad "all_cold parked template_error: $(halt_kv "$ws" detail)"
state_get "$ws" ledger | command grep "event=spawn .*stage=split" | command grep -q "mode=cold" \
  && ok "split spawned mode=cold under all_cold" \
  || bad "split spawn mode not cold: $(state_get "$ws" ledger | command grep 'stage=split' | head -2)"
[ "$(halt_kv "$ws" reason)" = "no_novelty" ] \
  && ok "run then ends in the planned no_novelty park (die,die)" \
  || bad "unexpected end state: $(halt_kv "$ws" reason)"
scen_end

echo "-- S7b (operator stop): a stop request parks operator_stop before any spawn --"
ws=$(mk_drill_ws drillS7b)
printf 'plan-validate=ready\n' > "$ws/.mock/plan"
printf 't=%s by=operator\n' "$(date +%s)" > "$ws/.runtime/stop-request"
log=$(sc_tmpdir)/ferry.log
run_ferry "$ws" "$log"; rc=$?
[ $rc -eq 20 ] && ok "ferry exits 20" || bad "rc=$rc ($(tail -3 "$log"))"
[ "$(halt_kv "$ws" reason)" = "operator_stop" ] \
  && ok "halt reason=operator_stop (the graceful-stop park is real and named)" \
  || bad "halt reason='$(halt_kv "$ws" reason)'"
_park=$(ledger_count "$ws" 'event=park reason=operator_stop')
precond "this park landed on the ledger (saw $_park row) — the spawn count below reads a live surface" \
  test "$_park" -ge 1
[ "$(ledger_count "$ws" 'event=spawn')" = "0" ] \
  && ok "no spawn happened after the stop request" || bad "spawned despite stop request"
[ ! -e "$ws/.runtime/stop-request" ] \
  && ok "stop request consumed (next launch will not re-trip on it)" \
  || bad "stop-request file left behind"
scen_end

check_done
