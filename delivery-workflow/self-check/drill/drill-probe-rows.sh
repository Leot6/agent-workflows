#!/usr/bin/env bash
# drill/drill-probe-rows.sh — the onboarding probe's INDEPENDENT rows, each on
# its own workspace against a real mock session: the scratch-session fence,
# the ferry-side quota park, and the three refusal directions. Split from
# drill-probe.sh (the S9 chain) because nothing here shares that chain's
# workspace or mutates the shadow tree, so the two files run concurrently
# under `check.sh --jobs` and neither waits on the other's AWAIT windows.
# Rows: S9f idempotent fencing · S9e ferry-side quota park · S9b no-heartbeat
#   FAIL · S9g gate ruled (allow path) · S9g/2 gate never ran.
# Skips (rc 77) without tmux.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

PROBE="$SHADOW/runtime-scripts/probe.sh"
precond "probe.sh exists in the shadow tree" test -f "$PROBE"

echo "-- S9f (probe idempotency): a leftover scratch session is fenced, not collided with --"
# The scratch name is fixed, so a launch killed while its probe hung (measured:
# hung on the CLI's self-update prompt) leaves an orphan sitting on it, and the
# next probe names into it. The ferry has fenced same-name sessions before every
# cold spawn all along; the probe had not.
wsf=$(mk_drill_ws drillS9f "probe.timeout=60")
# A probe SCENARIO must start from no stored result: mk_drill_ws fabricates the
# record ferry.sh's fact guard reads, and that record is — by design, one
# derivation — exactly what probe.sh's own cache accepts, so leaving it here
# would serve every arm below a "cached pass" instead of running the live probe.
rm -f "$wsf"/.runtime/probe/*.kv
precond "no stored probe result stands before the live probe (the fabricated one is cleared)" \
  bash -c '! ls "$1"/.runtime/probe/*.kv > /dev/null 2>&1' _ "$wsf"
printf 'plan-validate=probe\n' > "$wsf/.mock/plan"
tmux new-session -d -s "delivery-drillS9f-probe-test" "sleep 300" 2>/dev/null || true
precond "an orphan really occupies the probe's fixed session name" \
  bash -c 'tmux has-session -t "=delivery-drillS9f-probe-test" 2>/dev/null'
out=$(shadow_env timeout 120 bash "$PROBE" "$wsf" "$SHADOW/config/backends/test.kv" test m0 low 2>&1); rc=$?
[ $rc -eq 0 ] \
  && ok "the probe passes despite the orphan — a killed launch no longer poisons the next one" \
  || bad "probe rc=$rc with an orphan present: $(printf '%s' "$out" | tail -3 | tr '\n' ' ')"
printf '%s' "$out" | command grep -q "fenced a leftover scratch session" \
  && ok "and names what it displaced (loud fence, never a silent reuse)" \
  || bad "the orphan was never named: $(printf '%s' "$out" | head -3 | tr '\n' ' ')"
scen_end

echo "-- S9e (ferry-side quota park): the backend's OWN reset time reaches the halt --"
# Reset times differ per CLI — a daily window, a rolling hour, another timezone
# — so the workflow computes none and defaults to none: it forwards the pane's
# line. This asserts the line arrives where the operator and the notification
# actually read (the halt detail), not only in a screen file someone must open.
wse=$(mk_drill_ws drillS9e "liveness.heartbeat_fresh=2
liveness.quiet_grace=2
liveness.nudge_grace=2
liveness.stage_timeout=60
liveness.hard_ceiling=120")
printf 'plan-validate=quota\n' > "$wse/.mock/plan"
log=$(sc_tmpdir)/ferry.log
run_ferry "$wse" "$log"; rc=$?
[ $rc -eq 20 ] && ok "ferry parks (exit 20) on a quota-dead pane" || bad "rc=$rc ($(tail -3 "$log"))"
[ "$(halt_kv "$wse" reason)" = "backend_quota" ] \
  && ok "halt reason=backend_quota — not idle, not timeout, and not a respawn" \
  || bad "halt reason='$(halt_kv "$wse" reason)'"
halt_kv "$wse" detail | command grep -q "19:45 Asia/Shanghai" \
  && ok "the halt detail carries the backend's own reset time VERBATIM (nothing computed, nothing defaulted)" \
  || bad "halt detail lost the pane's reset time: $(halt_kv "$wse" detail)"
[ "$(ledger_count "$wse" 'event=spawn slice=00 stage=plan-validate')" = "1" ] \
  && ok "exactly ONE spawn — no attempt spent respawning into a backend that cannot answer" \
  || bad "spawn count $(ledger_count "$wse" 'event=spawn slice=00 stage=plan-validate')"
scen_end

echo "-- S9b (probe bad direction): a backend that never heartbeats FAILS the probe --"
ws=$(mk_drill_ws drillS9b "probe.timeout=60")
# A probe SCENARIO must start from no stored result: mk_drill_ws fabricates the
# record ferry.sh's fact guard reads, and that record is — by design, one
# derivation — exactly what probe.sh's own cache accepts, so leaving it here
# would serve every arm below a "cached pass" instead of running the live probe.
rm -f "$ws"/.runtime/probe/*.kv
precond "no stored probe result stands before the live probe (the fabricated one is cleared)" \
  bash -c '! ls "$1"/.runtime/probe/*.kv > /dev/null 2>&1' _ "$ws"
printf 'plan-validate=probe-nohb\n' > "$ws/.mock/plan"
out=$(shadow_env timeout 120 bash "$PROBE" "$ws" "$SHADOW/config/backends/test.kv" test m0 low 2>&1); rc=$?
[ $rc -eq 1 ] && ok "probe FAILS (rc=1) when the heartbeat hook never fires" \
  || bad "probe rc=$rc on a heartbeat-less backend (want 1)"
printf '%s' "$out" | command grep -qi 'heartbeat' \
  && ok "failure NAMES the broken promise (heartbeat)" || bad "failure does not name heartbeat: $out"
command grep -q '^result=fail' "$ws/.runtime/probe/test.kv" 2>/dev/null \
  && ok "result=fail recorded (a later launch refuses on it)" \
  || bad "no fail record: $(cat "$ws/.runtime/probe/test.kv" 2>/dev/null | tr '\n' ' ')"
scen_end

echo "-- S9g (the probe measures the GATE, not the agent's manners): a well-behaved session still proves it --"
# The probe prompt asks the agent to make a mistake — end a turn record-less —
# and probe.sh searched the pane for `turn end BLOCKED`. Measured twice on two
# independent claude/sonnet sessions at effort low: both read the prompt, saw
# both designed failure points, wrote the owed validation note FIRST, emitted
# once and printed done. No block was ever attempted, so `stop_gate=miss`,
# `result=fail`, and launch.sh refused a CORRECT backend with "declarations are
# promises, the probe makes them facts" — which sends the operator to a
# declaration that is entirely right. launch.sh:95-98 already insists the two
# ways to not start must not share a sentence; this was a third way borrowing
# the first one's.
# The gate was present and working the whole time. What was missing was any
# record of it having RULED on the allow path, so the signal is now "the gate
# ran and ruled correctly" and passes on both orderings.
wsg=$(mk_drill_ws drillS9g "probe.timeout=60")
rm -f "$wsg"/.runtime/probe/*.kv
precond "no stored probe result stands before the live probe" \
  bash -c '! ls "$1"/.runtime/probe/*.kv > /dev/null 2>&1' _ "$wsg"
printf 'plan-validate=probe-quiet\n' > "$wsg/.mock/plan"
out=$(shadow_env timeout 120 bash "$PROBE" "$wsg" "$SHADOW/config/backends/test.kv" test m0 low 2>&1); rc=$?
[ $rc -eq 0 ] \
  && ok "a session that never trips the gate still PASSES the probe (rc=0)" \
  || bad "probe rc=$rc on a well-behaved session — the instrument is still measuring manners: $(printf '%s' "$out" | tail -4 | tr '\n' ' ')"
pkg="$wsg/.runtime/probe/test.kv"
command grep -q '^result=pass' "$pkg" && ok "result=pass recorded" \
  || bad "result: $(cat "$pkg" 2>/dev/null | tr '\n' ' ')"
command grep -q 'stop_gate=ok' "$pkg" \
  && ok "stop_gate=ok attested from the gate's own ruling, with no block in sight" \
  || bad "stop_gate item: $(command grep -m1 heartbeat= "$pkg" 2>/dev/null)"
command grep -q 'stop_gate_block=unobserved' "$pkg" \
  && ok "and the record SAYS no block was observed — the two facts are separated, never conflated" \
  || bad "no stop_gate_block telemetry naming the unobserved block: $(command grep -m1 heartbeat= "$pkg" 2>/dev/null)"
( . "$RS/lib/state.sh"; state_get "$wsg/.runtime/probe/ws-test" audit 2>/dev/null ) \
  | command grep -q 'stop_gate_allow' \
  && ok "the probe store's audit surface carries the allow ruling (pre-fix that surface did not exist at all)" \
  || bad "no stop_gate_allow row in the probe store: $( . "$RS/lib/state.sh"; state_get "$wsg/.runtime/probe/ws-test" audit 2>/dev/null | tail -2 | tr '\n' ' ')"
scen_end

echo "-- S9g/2 (bad direction): a gate that never runs is still a MISS --"
# The widening must not make the item unfailable. Here the harness wiring is
# broken — no hook fires, nothing rules, the pane stays quiet — and the probe
# must still refuse, which is the whole reason the item exists.
wsn=$(mk_drill_ws drillS9g2 "probe.timeout=60")
rm -f "$wsn"/.runtime/probe/*.kv
precond "no stored probe result stands before the live probe (the fabricated one is cleared)" \
  bash -c '! ls "$1"/.runtime/probe/*.kv > /dev/null 2>&1' _ "$wsn"
printf 'plan-validate=probe-nogate\n' > "$wsn/.mock/plan"
out=$(shadow_env timeout 120 bash "$PROBE" "$wsn" "$SHADOW/config/backends/test.kv" test m0 low 2>&1); rc=$?
[ $rc -eq 1 ] \
  && ok "a backend whose Stop hook never runs FAILS the probe (rc=1)" \
  || bad "probe rc=$rc with no gate ruling at all (want 1) — the widened signal is vacuous: $(printf '%s' "$out" | tail -4 | tr '\n' ' ')"
command grep -q 'stop_gate=miss' "$wsn/.runtime/probe/test.kv" 2>/dev/null \
  && ok "and the record names stop_gate=miss" \
  || bad "probe record: $(cat "$wsn/.runtime/probe/test.kv" 2>/dev/null | tr '\n' ' ')"
scen_end

check_done
