#!/usr/bin/env bash
# drill/drill-backend.sh — the ASSIGNMENT rows: the profile is a pure function
# of the (stage, backend) assignment, and a mid-run backend switch is not
# silently defeated by warm reuse. One file because S13 spawns on the `test2`
# declaration S12 writes into the shadow tree. Split from drill.sh so the
# short rows and these run concurrently under `check.sh --jobs`.
# Rows: S12 per-assignment profile · S13 backend switch + config snapshot.
# Skips (rc 77) without tmux.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

echo "-- S12 (the profile is a pure function of the assignment): a reviewer on ANOTHER backend gets ITS profile --"
# The profile used to be derived TWICE: launch.sh baked .runtime/profile.json
# from agent.author.backend at TOPIC level, and every spawn re-used that one
# file — so the reviewer's declaration was never consulted, and a slice-level
# override never could be. It misfired invisibly only because the Claude Code
# declarations happened to name the same profile file. The discriminating fixture is
# therefore two backends with DISTINCT profile templates: the assertion reads
# the REVIEWER session's own rendered profile and looks for a marker that
# exists only in the reviewer's template. Both directions, because a fixture
# where both sessions render the reviewer's template would pass a broken rule.
cat > "$SHADOW/config/profiles/test-reviewer.json" <<'EOF'
{ "//": "DRILL-REVIEWER-ONLY-MARKER — rendered only from test2.kv's own template",
  "root": "{WORKFLOW_ROOT}", "ws": "{WORKSPACE}", "session": "{SESSION_NAME}",
  "hooks": {} }
EOF
sed 's|^profile=.*|profile=profiles/test-reviewer.json|' "$SHADOW/config/backends/test.kv" \
  > "$SHADOW/config/backends/test2.kv"
precond "the two mock declarations name DIFFERENT profile templates (else nothing here can discriminate)" \
  bash -c '[ "$(command grep -m1 "^profile=" "$1")" != "$(command grep -m1 "^profile=" "$2")" ]' \
  _ "$SHADOW/config/backends/test.kv" "$SHADOW/config/backends/test2.kv"
ws=$(mk_drill_ws drillS12 "agent.reviewer.backend=test2")
precond "topic.kv binds the reviewer to test2 and the author to test" \
  bash -c 'command grep -q "^agent.reviewer.backend=test2$" "$1/config/topic.kv" && command grep -q "^agent.author.backend=test$" "$1/config/topic.kv"' \
  _ "$ws"
printf 'plan-validate=ready\nsplit=done\nsplit-check=die\n' > "$ws/.mock/plan"
log=$(sc_tmpdir)/ferry.log
run_ferry "$ws" "$log"; rc=$?
[ $rc -eq 20 ] && ok "the run reaches its planned park (exit 20)" || bad "rc=$rc ($(tail -3 "$log"))"
a_prof="$ws/.runtime/profile-delivery-drillS12-00-plan-validate.json"
r_prof="$ws/.runtime/profile-delivery-drillS12-00-split-check.json"
precond "both sessions rendered a per-session profile (author + reviewer)" \
  bash -c '[ -s "$1" ] && [ -s "$2" ]' _ "$a_prof" "$r_prof"
command grep -q 'DRILL-REVIEWER-ONLY-MARKER' "$r_prof" \
  && ok "the REVIEWER session's profile came from the REVIEWER's declaration's template" \
  || bad "the reviewer session got someone else's profile: $(head -c 120 "$r_prof" 2>/dev/null | tr '\n' ' ')"
command grep -q 'DRILL-REVIEWER-ONLY-MARKER' "$a_prof" \
  && bad "the AUTHOR session also got the reviewer's template — the assertion above cannot discriminate" \
  || ok "and the author session did NOT (the marker is discriminating, not universal)"
command grep -q 'session/heartbeat.sh' "$a_prof" \
  && ok "the author session's profile is its own template rendered, not a stub or an empty file" \
  || bad "author profile has no heartbeat hook: $(head -c 120 "$a_prof" 2>/dev/null | tr '\n' ' ')"
command grep -q "{WORKFLOW_ROOT}\|{WORKSPACE}\|{SESSION_NAME}" "$a_prof" \
  && bad "an unsubstituted placeholder survived into a rendered profile (the hooks would not run)" \
  || ok "every placeholder is substituted at the one render (WORKFLOW_ROOT, WORKSPACE and SESSION_NAME together)"
command grep -q "delivery-drillS12-00-split-check" "$r_prof" \
  && ok "the reviewer's own SESSION NAME is baked into its profile (the Stop gate scopes to its caller)" \
  || bad "the reviewer profile carries no session name"
[ -e "$ws/.runtime/profile.json" ] \
  && bad "the topic-level baked profile still exists — the second derivation is still there" \
  || ok "no topic-level .runtime/profile.json exists at all (one derivation, one file per session)"
# The assignment is a run-time parameter with an AUDIT obligation: no evidence
# rests on it (a cu's SHA and the project's gates are identical whichever CLI
# produced them), but it PRODUCED that evidence, so a run that loses the
# attribution has nothing left to reconstruct it from. Two backends in one
# topic is exactly the case where the ledger must say which ran where.
state_get "$ws" ledger | command grep 'event=spawn .*stage=plan-validate' | command grep -q 'backend=test ' \
  && ok "the spawn ledger event records the RESOLVED backend (author stage: backend=test)" \
  || bad "no backend on the author spawn: $(state_get "$ws" ledger | command grep 'stage=plan-validate' | head -1)"
state_get "$ws" ledger | command grep 'event=spawn .*stage=split-check' | command grep -q 'backend=test2 ' \
  && ok "and the REVIEWER's own backend on its own spawn (backend=test2) — per-stage attribution, never a topic-level guess" \
  || bad "reviewer spawn does not carry test2: $(state_get "$ws" ledger | command grep 'stage=split-check' | head -1)"
scen_end

echo "-- S13 (a backend switch is not silently defeated): a warm stage must not reuse the OTHER backend's session --"
# config/stages.tsv gives warm-author to revise/impl/fix/turnover plus split.
# The warm-reuse path tested the held session for exactly ONE property —
# pty_alive — and the sessions surface could not support a second: its records
# carried role/name/pids/socket/nonce/mode/t and no backend at all, while the
# stage surface and the ledger both recorded the NEW backend. So the record
# said the switch happened and the work continued on the old session. The loud
# case is a dead old backend; the quiet one is worse — switching model for
# quality reasons with the old session healthy, and every warm stage silently
# producing the old model's work under the new one's name.
# The fixture switches the AUTHOR's backend across a park, which is the live
# operation (admission.sh advertises exactly it), and asserts both directions:
# same backend still reuses warm, changed backend cold-falls back.
ws=$(mk_drill_ws drillS13)
printf 'plan-validate=ready\nsplit:1=halt\nsplit:2=done\nsplit-check=die\n' > "$ws/.mock/plan"
log=$(sc_tmpdir)/ferry.log
run_ferry "$ws" "$log"; rc=$?
[ $rc -eq 20 ] && ok "run 1 parks at split (exit 20)" || bad "run 1 rc=$rc ($(tail -3 "$log"))"
[ "$(halt_kv "$ws" reason)" = "class_u" ] \
  && ok "run 1 halt reason=class_u — the author session is held, alive, and unchanged" \
  || bad "run 1 halt reason='$(halt_kv "$ws" reason)'"
# Good direction FIRST: with the backend unchanged, the warm path is unaffected.
state_get "$ws" ledger | command grep 'event=spawn .*stage=split ' | head -1 | command grep -q 'mode=warm' \
  && ok "same backend: split reused the author session warm (the reuse path is not broken by the new test)" \
  || bad "split visit 1 was not warm: $(state_get "$ws" ledger | command grep 'event=spawn .*stage=split ' | head -1)"
state_get "$ws" sessions | command grep -E '(^| )role=author( |$)' | command grep -q 'backend=test' \
  && ok "the sessions record carries the backend that PRODUCED the session (the field the comparison needs)" \
  || bad "no backend= on the author sessions row: $(state_get "$ws" sessions | command grep -E '(^| )role=author( |$)')"
# Now the switch, made where an operator makes it.
sed -i 's/^agent\.author\.backend=test$/agent.author.backend=test2/' "$ws/config/topic.kv"
precond "topic.kv now binds the author to test2" \
  bash -c 'command grep -q "^agent.author.backend=test2$" "$1/config/topic.kv"' _ "$ws"
sleep 1
shadow_env "$LAUNCH" rule "$ws" --slice 00 --text "MOCK-RULING: proceed on the new backend" > /dev/null 2>&1 \
  && ok "launch.sh rule recorded the ruling (the park is dischargeable)" || bad "launch.sh rule failed"
run_ferry "$ws" "$log"; rc=$?
sp2=$(state_get "$ws" ledger | command grep 'event=spawn .*stage=split ' | tail -1)
printf '%s\n' "$sp2" | command grep -q 'backend=test2' \
  && ok "run 2's split spawn resolved the NEW backend (backend=test2)" \
  || bad "split respawn did not resolve test2: $sp2"
printf '%s\n' "$sp2" | command grep -q 'mode=cold' \
  && ok "and it spawned COLD ('$sp2') — a session produced by another backend is not reusable, whatever its liveness says" \
  || bad "split respawned mode=warm on a session the OLD backend produced: $sp2 — the switch was recorded and then silently defeated"
state_get "$ws" audit | command grep -q 'backend .*: cold-fallback' \
  && ok "the fallback is audited by name (a postmortem can see WHY the session was not reused)" \
  || bad "no audit line naming the backend mismatch: $(state_get "$ws" audit | tail -3)"
# Same two runs, second mechanism: `config.snapshot.kv` is handed to every
# author and reviewer labelled "resolved config snapshot … effective
# caps/budgets with layers", and it was written inside the run-surface-ABSENT
# branch — so every launch after the first left it untouched. Measured on the
# live topic: one `run_init` row in the whole ledger and eight lines of the
# file false against the config it claims to resolve. This fixture makes the
# change the operator actually makes (edit topic.kv, relaunch) and reads the
# file the next agent would read.
snapf="$ws/.runtime/config.snapshot.kv"
precond "the snapshot exists after the first run" test -f "$snapf"
command grep -q '^agent.author.backend=test2$' "$snapf" \
  && ok "the snapshot handed to the next agent carries the CHANGED value after a relaunch (agent.author.backend=test2)" \
  || bad "snapshot's last agent.author.backend line reads '$(command grep '^agent.author.backend=' "$snapf" | tail -1)' after a relaunch that resolved test2 — every author and reviewer is handed a file labelled 'effective' that is not"
command grep -q '^liveness.poll=' "$snapf" \
  && ok "and the layers below it are still there (defaults + topic, in that order)" \
  || bad "the snapshot lost its lower layer: $(head -3 "$snapf" | tr '\n' ' ')"
scen_end

check_done
