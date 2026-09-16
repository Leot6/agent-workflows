#!/usr/bin/env bash
# drill/drill-probe.sh — the onboarding probe's CHAIN, against a real mock
# session in a real tmux pane: S9 proves a live pass, and S9c/S9d/S9d2 then
# reuse THAT workspace to prove what the cache does and does not answer —
# while S9c edits the shadow declaration in place and S9d/2 edits the shadow
# adapter, so they need a shadow tree nobody else is reading. The probe rows
# that stand on their own (fencing, the ferry-side quota park, the three
# refusal directions) live in drill-probe-rows.sh, so the two files run
# concurrently under `check.sh --jobs` and this chain is the gate's floor
# rather than the sum of both.
# Rows: S9 pass · S9c cache identity · S9d quota vs declaration · S9d/2 halt
#   bypass + implementation-keyed cache.
# Skips (rc 77) without tmux.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

echo "-- S9 (onboarding probe): declarations proven against a live mock session --"
ws=$(mk_drill_ws drillS9 "probe.timeout=60")
# A probe SCENARIO must start from no stored result: mk_drill_ws fabricates the
# record ferry.sh's fact guard reads, and that record is — by design, one
# derivation — exactly what probe.sh's own cache accepts, so leaving it here
# would serve every arm below a "cached pass" instead of running the live probe.
rm -f "$ws"/.runtime/probe/*.kv
precond "no stored probe result stands before the live probe (the fabricated one is cleared)" \
  bash -c '! ls "$1"/.runtime/probe/*.kv > /dev/null 2>&1' _ "$ws"
printf 'plan-validate=probe\n' > "$ws/.mock/plan"
PROBE="$SHADOW/runtime-scripts/probe.sh"
precond "probe.sh exists in the shadow tree" test -f "$PROBE"
out=$(shadow_env timeout 120 bash "$PROBE" "$ws" "$SHADOW/config/backends/test.kv" test m0 low 2>&1); rc=$?
[ $rc -eq 0 ] && ok "probe PASSES against a fully-behaving mock backend" \
  || bad "probe rc=$rc: $(printf '%s' "$out" | tail -4 | tr '\n' ' ')"
pk="$ws/.runtime/probe/test.kv"
precond "probe result file exists" test -f "$pk"
command grep -q '^result=pass' "$pk" && ok "result=pass recorded" || bad "result: $(cat "$pk" | tr '\n' ' ')"
for item in heartbeat=ok stop_gate=ok emit=ok awaiting_input=ok inject=ok dead_detect=ok; do
  command grep -q "$item" "$pk" && ok "probe attests $item" || bad "missing $item in $pk"
done
# The injection telemetry, asserted because both halves of it were computed and
# thrown away until 2026-09-03: phase C sent pty_inject's stdout to /dev/null,
# and phase D captured it into `ghost_out` and never read it, so `ghost_rc`
# stood alone and rc 3 has three causes. Nothing in the suite touched these
# fields, which means they could be deleted again with nothing going red — the
# reason this arm exists at all rather than the values being self-evident.
command grep -qE '^ghost_rc=[0-9]* ghost_why=[^ ]+ inject_why=[^ ]+$' "$pk" \
  && ok "the probe record carries BOTH injection reasons beside their rc ($(command grep -oE 'ghost_why=[^ ]+' "$pk"))" \
  || bad "probe telemetry line missing or malformed: [$(command grep '^ghost_rc' "$pk" 2>/dev/null)]"
# version token: the extraction is last-line+first-version-token,
# so the mock's `mock-cli-0.1` pins as `0.1` — the same one-time identity
# migration codex takes (`codex-cli 0.148.0` -> `0.148.0`). What the
# assertion must pin is that the record carries the extraction's OWN reading.
command grep -qE '^version=0\.1$' "$pk" \
  && ok "CLI version pinned in the probe record (version TOKEN of mock-cli-0.1)" || bad "no version pin: $(command grep '^version=' "$pk")"
out=$(shadow_env timeout 30 bash "$PROBE" "$ws" "$SHADOW/config/backends/test.kv" test m0 low 2>&1); rc=$?
[ $rc -eq 0 ] && printf '%s' "$out" | command grep -q cached \
  && ok "same-version re-probe is a cached pass (no second session spent)" \
  || bad "cache miss on unchanged version: rc=$rc $out"
live=$(tmux list-sessions -F '#{session_name}' 2>/dev/null | command grep -c '^delivery-' || true)
# Naming side first (the same two-sided floor drill-walk carries): the counter
# greps '^delivery-' and the probe mints "delivery-$TOPIC-probe-$BACKEND"
# (probe.sh), seeding the row into its SCRATCH workspace's sessions surface —
# .runtime/probe/ws-<backend>/ persists after the run, and it is the durable
# proof of which naming THIS probe used. A drift turns a leak into the
# counter's zero.
_nsp=$(command grep -c 'name=delivery-' "$ws/.runtime/probe/ws-test/.runtime/state/sessions" 2>/dev/null || true)
precond "the probe's session row carries the delivery- prefix the counter greps for (saw $_nsp)" \
  test "${_nsp:-0}" -ge 1
[ "${live:-0}" -eq 0 ] && ok "probe left zero live sessions" \
  || bad "probe leaked sessions: $(tmux list-sessions 2>/dev/null | tr '\n' ' ')"
# Pattern side, LAST: prove the counter can still see one.
_probe="delivery-selfcheck-probe"
tmux new-session -d -s "$_probe" "sleep 5" 2>/dev/null
_seen=$(tmux list-sessions -F '#{session_name}' 2>/dev/null | command grep -c '^delivery-' || true)
tmux kill-session -t "$_probe" 2>/dev/null
precond "the leak counter can count a delivery- session (saw $_seen with a probe session live)" \
  test "${_seen:-0}" -ge 1

echo "-- S9c (cache identity): a changed declaration at the SAME version is never a cached pass --"
TDECL="$SHADOW/config/backends/test.kv"
cp "$TDECL" "$TDECL.orig"
sed -i 's|^sig.awaiting_input=.*|sig.awaiting_input=NEVER-MATCHES-ANYTHING-XYZZY|' "$TDECL"
precond "the declaration mutation landed" \
  bash -c 'command grep -q XYZZY "$1"' _ "$TDECL"
out=$(shadow_env timeout 120 bash "$PROBE" "$ws" "$TDECL" test m0 low 2>&1); rc=$?
command grep -q cached <<< "$out" \
  && bad "a MUTATED declaration at an unchanged version returned a cached pass — 'declarations are promises, the probe makes them facts' does not survive a declaration edit" \
  || ok "changed declaration -> the cache does not answer (fresh probe forced)"
[ $rc -eq 1 ] && printf '%s' "$out" | command grep -q 'awaiting_input=miss' \
  && ok "the fresh probe FAILS on the broken signature (rc=1, awaiting_input=miss named)" \
  || bad "probe rc=$rc on a broken awaiting signature (want 1 + awaiting_input=miss): $(printf '%s' "$out" | tail -3 | tr '\n' ' ')"
mv "$TDECL.orig" "$TDECL"
out=$(shadow_env timeout 120 bash "$PROBE" "$ws" "$TDECL" test m0 low 2>&1); rc=$?
[ $rc -eq 0 ] \
  && ok "the restored declaration probes green again (rc=$rc — the fail record did not wedge the cache)" \
  || bad "restored declaration rc=$rc: $(printf '%s' "$out" | tail -3 | tr '\n' ' ')"
echo "-- S9d (availability vs capability): a quota-dead backend is not a broken declaration --"
# Measured: a relaunch inside a zero-quota window printed "cached pass", spawned
# two sessions that were born dead, and a third whose stage clock ran there. The
# cache is not widened — quota is a property of none of its keys — it is
# BYPASSED on the workflow's own evidence, and the live probe then names the
# real cause instead of burning probe.timeout and blaming the declaration.
wsq=$(mk_drill_ws drillS9d "probe.timeout=60")
# A probe SCENARIO must start from no stored result: mk_drill_ws fabricates the
# record ferry.sh's fact guard reads, and that record is — by design, one
# derivation — exactly what probe.sh's own cache accepts, so leaving it here
# would serve every arm below a "cached pass" instead of running the live probe.
rm -f "$wsq"/.runtime/probe/*.kv
precond "no stored probe result stands before the live probe (the fabricated one is cleared)" \
  bash -c '! ls "$1"/.runtime/probe/*.kv > /dev/null 2>&1' _ "$wsq"
printf 'plan-validate=quota\n' > "$wsq/.mock/plan"
out=$(shadow_env timeout 120 bash "$PROBE" "$wsq" "$SHADOW/config/backends/test.kv" test m0 low 2>&1); rc=$?
[ $rc -eq 4 ] \
  && ok "a quota-dead backend exits 4 (its own code), not 1 — nothing about the declaration was disproved" \
  || bad "probe rc=$rc on a quota-dead backend (want 4): $(printf '%s' "$out" | tail -3 | tr '\n' ' ')"
printf '%s' "$out" | command grep -q "out of quota" \
  && ok "the refusal names the backend, not the declaration" \
  || bad "refusal text blames the wrong thing: $(printf '%s' "$out" | tail -2 | tr '\n' ' ')"
printf '%s' "$out" | command grep -q "resets 19:45 Asia/Shanghai" \
  && ok "and forwards the pane's OWN reset time verbatim (19:45 Asia/Shanghai — never a computed or default one)" \
  || bad "the captured quota line did not reach the operator: $(printf '%s' "$out" | tail -2 | tr '\n' ' ')"
command grep -q '^result=backend_quota' "$wsq/.runtime/probe/test.kv" \
  && ok "recorded as result=backend_quota — never a pass (no cache to poison), never a fail (no declaration to hunt)" \
  || bad "probe record: $(cat "$wsq/.runtime/probe/test.kv" 2>/dev/null | tr '\n' ' ')"

echo "-- S9d/1b: a backend that is UP and REFUSING is the same shape and a different fact --"
# The 529 class. Without its own arm the probe waits out probe.timeout and then
# reports the items it could not reach as MISSING — "declarations are promises"
# against a declaration that is fine, which is the failure the quota signature
# was added to stop, one layer up. The pane shape here is deliberately the same
# as the quota fixture's (banner in the transcript, empty composer): what must
# differ is the RESULT and the ADVICE.
wso=$(mk_drill_ws drillS9d1b "probe.timeout=60")
rm -f "$wso"/.runtime/probe/*.kv
precond "no stored probe result stands before the live probe (drillS9d1b)" \
  bash -c '! ls "$1"/.runtime/probe/*.kv > /dev/null 2>&1' _ "$wso"
printf 'plan-validate=overload\n' > "$wso/.mock/plan"
out=$(shadow_env timeout 120 bash "$PROBE" "$wso" "$SHADOW/config/backends/test.kv" test m0 low 2>&1); rc=$?
[ $rc -eq 4 ] \
  && ok "an overloaded backend exits 4 (the availability code), not 1 — nothing about the declaration was disproved" \
  || bad "probe rc=$rc on an overloaded backend (want 4): $(printf '%s' "$out" | tail -3 | tr '\n' ' ')"
printf '%s' "$out" | command grep -q "up and refusing" \
  && ok "the refusal names the backend, not the declaration" \
  || bad "refusal text blames the wrong thing: $(printf '%s' "$out" | tail -2 | tr '\n' ' ')"
printf '%s' "$out" | command grep -q "relaunch on judgment rather than on a clock" \
  && ok "and it says there is NO reset time to wait for — the one thing that differs from the quota refusal" \
  || bad "the advice did not reach the operator: $(printf '%s' "$out" | tail -3 | tr '\n' ' ')"
command grep -q '^result=backend_overloaded' "$wso/.runtime/probe/test.kv" \
  && ok "recorded as result=backend_overloaded — the value admission.sh reads to pick which park to write" \
  || bad "probe record: $(cat "$wso/.runtime/probe/test.kv" 2>/dev/null | tr '\n' ' ')"

echo "-- S9d/2: an unresolved backend_quota halt makes the cached pass step aside --"
( . "$RS/lib/state.sh"
  printf 'reason=backend_quota\nslice=00\nstage=plan-validate\nresolved=0\nt=%s\n' "$(date +%s)" \
    | state_set "$ws" halt ferry ) > /dev/null
printf 'plan-validate=probe\n' > "$ws/.mock/plan"
out=$(shadow_env timeout 120 bash "$PROBE" "$ws" "$SHADOW/config/backends/test.kv" test m0 low 2>&1); rc=$?
command grep -q "probe: cached pass" <<< "$out" \
  && bad "a standing backend_quota halt still served a cached pass — the relaunch that was measured spawning dead sessions is unchanged" \
  || ok "the standing halt bypasses the cache (capability was proven; availability was not)"
[ $rc -eq 0 ] \
  && ok "and the live re-probe passes once the backend answers again (rc=0) — the bypass is not a wedge" \
  || bad "re-probe rc=$rc: $(printf '%s' "$out" | tail -3 | tr '\n' ' ')"
# The bypass reads a CLASS of halt, not one literal: a 529-overload halt makes
# the backend unable to serve exactly the way an exhausted quota does, and a
# stored pass answers neither.
( . "$RS/lib/state.sh"
  printf 'reason=backend_overloaded\nslice=00\nstage=plan-validate\nresolved=0\nt=%s\n' "$(date +%s)" \
    | state_set "$ws" halt ferry ) > /dev/null
out=$(shadow_env timeout 60 bash "$PROBE" "$ws" "$SHADOW/config/backends/test.kv" test m0 low 2>&1)
command grep -q "probe: cached pass" <<< "$out" \
  && bad "a standing backend_overloaded halt still served a cached pass — the same relaunch-into-a-dead-window the quota bypass exists to stop" \
  || ok "an unresolved backend_overloaded halt bypasses the cache too (the bypass reads the availability CLASS, not one literal)"
( . "$RS/lib/state.sh"
  printf 'reason=backend_quota\nslice=00\nstage=plan-validate\nresolved=1\nt=%s\n' "$(date +%s)" \
    | state_set "$ws" halt ferry ) > /dev/null
out=$(shadow_env timeout 30 bash "$PROBE" "$ws" "$SHADOW/config/backends/test.kv" test m0 low 2>&1)
printf '%s' "$out" | command grep -q "probe: cached pass" \
  && ok "a RESOLVED quota halt returns the cache to service (the bypass reads the standing fact, not history)" \
  || bad "the cache stayed bypassed after the halt was cleared: $out"

sed -i 's/^probe_impl=.*/probe_impl=STALE-IMPL/' "$ws/.runtime/probe/test.kv"
out=$(shadow_env timeout 120 bash "$PROBE" "$ws" "$TDECL" test m0 low 2>&1); rc=$?
command grep -q cached <<< "$out" \
  && bad "a pass attested by a DIFFERENT probe/adapter implementation was served from cache — a mutated primitive coasts on its pre-mutation pass" \
  || ok "stale implementation generation -> the cache does not answer (fresh probe forced)"
[ $rc -eq 0 ] \
  && ok "and the forced fresh probe RAN to its own pass (rc=0) — the absence above is over a run that executed, not one that crashed" \
  || bad "the fresh probe rc=$rc: $(printf '%s' "$out" | tail -3 | tr '\n' ' ')"

# The arm above forges the STORED key; this one changes the code for real, which
# is the case the key exists for. It could not be written while the key was the
# repo's HEAD sha: this shadow tree is not a git checkout, so every probe here
# keyed the constant `no-git` and a mutated adapter WAS served from cache.
mutant="$SHADOW/runtime-scripts/backends/pty_tmux.sh"
cp "$mutant" "$mutant.orig"
printf '\n# drill mutation: the adapter is not the one that attested the pass\n' >> "$mutant"
out=$(shadow_env timeout 120 bash "$PROBE" "$ws" "$TDECL" test m0 low 2>&1); rc=$?
command grep -q "cached pass" <<< "$out" \
  && bad "a REAL edit to the adapter was served a cached pass — the key does not see the code it attests" \
  || ok "editing the adapter itself invalidates the pass — the key is the code's content, not the repo's commit"
[ $rc -eq 0 ] \
  && ok "and the re-probe over the edited adapter RAN to its own pass (rc=0 — the edit is a comment; the behavior is intact) — the absence above is over a run that executed" \
  || bad "the re-probe rc=$rc: $(printf '%s' "$out" | tail -3 | tr '\n' ' ')"
mv "$mutant.orig" "$mutant"
# The mutant's own run rewrote the store, so the restore re-probes once more;
# the run AFTER that is the one that says whether identical content keys
# identically — a key that drifted per run would never answer from cache again.
shadow_env timeout 120 bash "$PROBE" "$ws" "$TDECL" test m0 low > /dev/null 2>&1
out=$(shadow_env timeout 120 bash "$PROBE" "$ws" "$TDECL" test m0 low 2>&1)
printf '%s' "$out" | command grep -q "cached pass" \
  && ok "two runs over identical content key the same — the cache answers again (a per-run key would cost a live session every launch, which is the defect this replaces)" \
  || bad "identical content did not key identically: $(printf '%s' "$out" | tail -2 | tr '\n' ' ')"

check_done
