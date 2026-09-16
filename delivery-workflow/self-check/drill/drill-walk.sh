#!/usr/bin/env bash
# drill/drill-walk.sh — the LONG row: one slice walked end to end, plan-validate
# through close-out to COMPLETE (the transition chain, warm + cold spawns,
# teardown of displaced sessions). It spends real time because spending it is
# the point. Its two siblings that used to share this file — the re-slice
# round-trip (drill-reslice.sh) and the two-repo doc delivery
# (drill-tworepo.sh) — each build their own shadow tree and tmux server, so the
# three run concurrently under `check.sh --jobs` and the gate's floor is the
# longest ONE walk, not their sum.
# Rows: S5 happy path (plan-validate .. close-out -> COMPLETE).
# Skips (rc 77) without tmux.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

echo "-- S5: full happy-path slice walk -> COMPLETE (transition chain, warm + cold spawns) --"
ws=$(mk_drill_ws drillS5)
cat > "$ws/.mock/plan" <<'EOF'
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
run_ferry "$ws" "$log"; rc=$?
[ $rc -eq 0 ] && ok "ferry exits 0: topic COMPLETE" \
  || bad "rc=$rc; halt=$(halt_kv "$ws" reason); log tail: $(tail -5 "$log"); mock: $(tail -8 "$ws/.mock/log" 2>/dev/null)"
chain=$(state_get "$ws" ledger 2>/dev/null \
  | command grep -oE 'event=advance slice=[0-9]+ stage=[a-z-]+' \
  | awk '{print $3}' | cut -d= -f2 | paste -sd, -)
want="plan-validate,split,split-check,spec,precheck,impl,postcheck,turnover,close-out"
[ "$chain" = "$want" ] \
  && ok "advance chain walks the whole table: $chain" \
  || bad "advance chain '$chain' != '$want'"
[ "$(halt_kv "$ws" reason)" = "push_gate" ] \
  && ok "terminal halt is push_gate (push stays Class U; the workflow never pushes)" \
  || bad "terminal halt: $(halt_kv "$ws" reason)"
state_get "$ws" slices | command grep "id=01" | command grep -q "status=done" \
  && ok "slice 01 marked done in the index" || bad "slices index: $(state_get "$ws" slices)"
sha=$(state_get "$ws" progress | command grep -oE 'sha=[0-9a-f]+' | head -1 | cut -d= -f2)
precond "progress surface carries the landed SHA" test -n "$sha"
s5repo=$(sed -n 's/^repo=//p' "$ws/project.kv" | head -1)   # DR_REPO dies with mk_drill_ws's subshell
git -C "$s5repo" rev-parse -q --verify "$sha^{commit}" > /dev/null \
  && ok "progress SHA resolves in the scratch repo git log (completion evidence = the repo)" \
  || bad "progress SHA $sha does not resolve"
state_get "$ws" ledger | command grep "event=spawn .*stage=split " | command grep -q "mode=warm" \
  && ok "split reused the author session warm (inject through the single primitive)" \
  || bad "split spawn was not warm: $(state_get "$ws" ledger | command grep 'stage=split ' | head -1)"
state_get "$ws" ledger | command grep "event=spawn .*stage=precheck" | command grep -q "mode=cold" \
  && ok "precheck round 1 spawned cold (independent floor)" \
  || bad "precheck spawn not cold"
command grep -q "none (" "$ws/.runtime/prompts/00-plan-validate-r1-a1.md" \
  && ok "optional-missing manifest item rendered 'none' in a live prompt (good direction)" \
  || bad "no 'none' marker in the live prompt"
# The release arm below reads ABSENCE at a hardcoded path, so the lock must
# first be proven TAKEN by this walk — else a ferry that stopped taking it
# (or a lock rename) reads as "released" without ever having been held. The
# audit surface's wiring trace is the pin, the same idiom drill-tworepo and
# drill.sh's S2 carry.
_takes=$(state_get "$ws" audit 2>/dev/null | command grep -c "repo lock taken" || true)
precond "this walk's production entry took the repo lock (saw $_takes audit line(s)) — release is asserted of a held lock" \
  test "${_takes:-0}" -ge 1
s5lock=$(git -C "$s5repo" rev-parse --absolute-git-dir)/delivery.lock
[ -f "$s5lock" ] \
  && bad "repo lock left behind after COMPLETE" || ok "repo lock released at close-out"
live=$(tmux list-sessions -F '#{session_name}' 2>/dev/null | command grep -c '^delivery-' || true)
# Naming side first: the counter greps '^delivery-' and the ferry mints
# "delivery-$TOPIC-…" (attempt.sh), so a naming drift turns a LEAK into the
# counter's zero — the worst reading this arm could make. The run's own spawn
# rows are the durable proof of which convention THIS walk used.
_nsp=$(state_get "$ws" ledger 2>/dev/null | command grep -c 'event=spawn .*session=delivery-' || true)
precond "this walk's spawn rows name delivery- sessions (saw $_nsp) — the counter greps the convention the ferry actually used" \
  test "${_nsp:-0}" -ge 1
if [ "${live:-0}" -eq 0 ]; then
  ok "ZERO live delivery-* sessions at COMPLETE (displaced sessions torn down; close-out closed)"
else
  bad "$live delivery-* session(s) still alive at COMPLETE (unbounded accumulation): $(tmux list-sessions -F '#{session_name}' 2>/dev/null | tr '\n' ' ')"
fi
# Pattern side, LAST (after the count above, so the probe session cannot
# perturb it): a counter whose grep drifted reads ZERO over a real leak, and
# the arm above would agree with it. Prove the pattern can still see one.
_probe="delivery-selfcheck-probe"
tmux new-session -d -s "$_probe" "sleep 5" 2>/dev/null
_seen=$(tmux list-sessions -F '#{session_name}' 2>/dev/null | command grep -c '^delivery-' || true)
tmux kill-session -t "$_probe" 2>/dev/null
precond "the leak counter can count a delivery- session (saw $_seen with a probe session live) — a drifted pattern would read ZERO over a real leak" \
  test "${_seen:-0}" -ge 1
[ "$(ledger_count "$ws" 'event=teardown')" -ge 3 ] \
  && ok "displacement/boundary teardowns were LEDGERED (visible lifecycle)" \
  || bad "teardown events missing from the ledger: $(ledger_count "$ws" 'event=teardown')"
scen_end

check_done
