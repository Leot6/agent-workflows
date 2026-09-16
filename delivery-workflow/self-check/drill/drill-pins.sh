#!/usr/bin/env bash
# drill/drill-pins.sh — the moved-ground pins row: plan_changed and
# workflow_changed PARKING against a shadow workflow tree that is a REAL git
# repo, and it closed a validation-debt row. The drill's shadow root has never been a git repo
# (the pin reads "no-git" and disables itself — a named degradation the audit
# carries), so both parks' RESUME paths are deterministic in 45-halt but the
# FIRING has never been exercised by anything but live traffic, and the live
# traffic that hit it (the dogfood topic's ten workflow_changed parks) hit a
# DIFFERENT, pre-subtree-shape comparison.
#
# Making the shadow a git repo changes what run_init pins: the subtree object
# of runtime-scripts/ + config/ + runtime-docs/ at HEAD. The scenarios:
#   S17  mid-topic plan.md edit       -> park plan_changed (ferry exits 20)
#   S18  a committed shadow change    -> park workflow_changed; relaunch adopts
#                                        (repins + audit line), the designed path
# Rows: S17 · S18. Skips (rc 77) without tmux.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

# The shadow tree lib.sh built is three directories; make it a git repo so
# workflow_sha pins the SUBTREE OBJECT (ferry.sh's ruling: the tree these
# sessions EXECUTE, not the repo HEAD).
git -C "$SHADOW" init -q
git -C "$SHADOW" config user.email drill@invalid
git -C "$SHADOW" config user.name drill
git -C "$SHADOW" add -A
git -C "$SHADOW" commit -qm "chore: shadow tree base"
precond "the shadow is now a git repo (the pin's precondition)" \
  git -C "$SHADOW" rev-parse --git-dir >/dev/null

echo "-- S17: a mid-topic plan.md edit parks plan_changed --"
ws=$(mk_drill_ws drillS17)
log=$(sc_tmpdir)/ferry.log
# Park the topic by KILLING the ferry between attempts (a crash/pause, NOT a
# halt: the resume gate runs BEFORE the pin checks by design — a class_u park
# would exit at resume and never reach the pin. A killed topic has no halt, so
# the relaunched ferry walks resume -> pins, which is where both parks fire).
# spec:1=stall12s keeps the killed run's spec attempt LIVE at the kill point.
cat > "$ws/.mock/plan" <<'EOF'
plan-validate=ready
split=done
split-check=concur
spec=drafted
spec:1=stall12s
precheck=ready
impl=built
postcheck=conforms
turnover=done
close-out=done
EOF
# Kill the first ferry at a live spec attempt (its spawn event is the
# attempt's birth record), leaving the topic pinned and unparked.
bg_ferry_until "$ws" "$log" 'event=spawn.*stage=spec '
precond "ferry killed past split (plan pinned, spec attempt live)" \
  test -n "$(state_field "$ws" run plan_hash)"
precond "no halt stands (a killed topic, not a parked one)" \
  test -z "$(halt_kv "$ws" reason)"
# THE MOVE: mutate plan.md under the live topic.
echo "# owner edit: the plan moved" >> "$(dirname "$ws")/plan.md"
run_ferry "$ws" "$log"; rc=$?
[ "$rc" -eq 20 ] && [ "$(halt_kv "$ws" reason)" = "plan_changed" ] \
  && ok "a mutated plan.md PARKS plan_changed (the fired pin, not the resume path)" \
  || bad "rc=$rc halt=$(halt_kv "$ws" reason) — the plan pin did not fire"
halt_kv "$ws" detail | command grep -qE 'plan.md hash changed' \
  && ok "the park names the mechanism (plan.md hash changed after split pinned it)" \
  || bad "park detail: $(halt_kv "$ws" detail)"
# The resume: plan_changed is ruling-gated (a ruling re-pins and re-enters
# split) — 45-halt's deterministic arm; this row claims the FIRING, which no
# fixture had ever exercised.

echo "-- S18: a committed shadow change parks workflow_changed; relaunch ADOPTS --"
ws2=$(mk_drill_ws drillS18)
cat > "$ws2/.mock/plan" <<'EOF'
plan-validate=ready
split=done
split-check=concur
spec=drafted
spec:1=stall12s
precheck=ready
impl=built
postcheck=conforms
turnover=done
close-out=done
EOF
log2=$(sc_tmpdir)/ferry2.log
# Same kill point as S17: a live spec attempt under the first ferry.
bg_ferry_until "$ws2" "$log2" 'event=spawn.*stage=spec '
pinned=$(state_field "$ws2" run workflow_sha)
precond "run_init pinned the workflow subtree SHA" test -n "$pinned"
precond "no halt stands (a killed topic)" test -z "$(halt_kv "$ws2" reason)"
# THE MOVE: land a COMMITTED change in the shadow tree (the maintenance
# window's shape — a real upgrade, not dirt; dirt is 45-halt's dirty arm).
echo "# shadow edit for S18" >> "$SHADOW/config/defaults.kv"
git -C "$SHADOW" add -A
git -C "$SHADOW" commit -qm "chore: shadow upgrade under a live topic"
run_ferry "$ws2" "$log2"; rc=$?
[ "$rc" -eq 20 ] && [ "$(halt_kv "$ws2" reason)" = "workflow_changed" ] \
  && ok "a committed workflow change PARKS workflow_changed (pinned $pinned)" \
  || bad "rc=$rc halt=$(halt_kv "$ws2" reason) — the workflow pin did not fire"
# The designed adoption: the deliberate relaunch IS it (resume.sh: workflow
# repins + audit). Continuation is proven by the FIRST advance past the halt
# — spec completing and precheck ENTERING is the topic running again under
# the new tree; walking the remaining stages to COMPLETE would re-prove
# walk-coverage drill-walk already owns, at ~35s of pure wall (measured: the
# full adoption pass was 63s of the drill's 79s).
bg_ferry_until "$ws2" "$log2" 'event=enter slice=01 stage=precheck'
[ "$(ledger_count "$ws2" 'event=enter.*stage=precheck')" -ge 1 ] \
  && ok "the ADOPTING relaunch repins and the topic CONTINUES (spec completed, precheck entered)" \
  || bad "adoption never advanced past the halt: $(tail -3 "$log2")"
repinned=$(state_field "$ws2" run workflow_sha)
[ -n "$repinned" ] && [ "$repinned" != "$pinned" ] \
  && ok "the pin MOVED to the new subtree SHA (adoption is a repin, not a dismiss)" \
  || bad "pin did not move: $pinned -> ${repinned:-empty}"
state_get "$ws2" audit 2>/dev/null | command grep -q "relaunch adopted the upgrade" \
  && ok "the adoption is AUDITED (workflow SHA repinned, freeze point named)" \
  || bad "no adoption audit line: $(state_get "$ws2" audit 2>/dev/null | tail -2)"

scen_end
check_done
