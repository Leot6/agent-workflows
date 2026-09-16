#!/usr/bin/env bash
# 45-halt — the ferry's halt/resume semantics (resume_halt_gate + park +
# check_severity_trend + check_budgets), unit-tested through the headless
# ferry. Covers: ruling identity binding (a ruling for another slice must NOT
# resolve an unrelated halt), the disagreement round-trip (an owner ruling must
# buy a real advance, not an identical re-park), moved-ground recovery
# (workflow_changed repins on deliberate relaunch; plan_changed is
# ruling-gated), the at-least-once notified flag (never set on a failed/absent
# transport), the severity-trend zero-guard, and budget-park reason naming.
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/fixtures/lib.sh"
. "$RS/lib/state.sh"

base=$(sc_tmpdir)
read -r repo branch < <(mk_repo "$base/repo")
hf=$(mk_headless_ferry)

new_ws() { # name -> ws
  local ws
  ws=$(mk_full_ws "$base" "$1" "$repo" "$branch")
  printf '%s\n' "$ws"
}

# The bounded-version-query arm (asserted further down, at its own heading)
# is a real-time proof: probe.sh's `timeout 10` around cmd.version must fire on
# a command that never answers, and only waiting the ten seconds proves it.
# It depends on nothing the arms between here and there produce — the headless
# probe symlink and a workspace of its own — so the wait is STARTED here, in
# the background, and collected where the assertions are made in this shell
# (a subshell's ok/bad would never reach the counters). Ten seconds of this
# check used to be spent doing nothing else.
hang_ws=$(new_ws halthang)
hangdecl=$(sc_tmpdir)/hang.kv
printf 'family=pty_tmux\ncmd.version=sleep 120\ncap=pty,subagent,stop_gate,heartbeat\n' > "$hangdecl"
hang_out=$(sc_tmpdir)/verify.rc
( t0=$(date +%s)
  timeout 40 bash "$(dirname "$hf")/probe.sh" --verify "$hang_ws" "$hangdecl" hangbe > /dev/null 2>&1
  printf '%s %s\n' "$?" "$(( $(date +%s) - t0 ))" > "$hang_out" ) &
hang_pid=$!
put_halt() { # ws reason slice stage round t [notified] [resolved]
  ( . "$RS/lib/state.sh"
    { echo "reason=$2"; echo "detail=fixture"; echo "slice=$3"; echo "stage=$4"
      echo "round=$5"; echo "t=$6"; echo "notified=${7:-1}"; echo "resolved=${8:-0}"
    } | state_set "$1" halt ferry ) > /dev/null
}
put_ruling() { # ws slice stage t text
  ( . "$RS/lib/state.sh"
    state_append "$1" rulings operator \
      "v=1 t=$4 slice=$2 stage=$3 n=1 file=slices/$2/ruling.1.md text=$5" ) > /dev/null
}
halt_field() { state_field "$1" halt "$2" 2>/dev/null || true; }

echo "-- ruling identity: a slice-99 ruling must NOT resolve a slice-01 halt --"
ws=$(new_ws halta)
put_halt "$ws" class_u 01 spec 1 100
put_ruling "$ws" 99 any 200 "unrelated"
assert_rc 20 "resume with only a FOREIGN ruling stays parked" -- \
  bash -c ". '$hf' '$ws' > /dev/null 2>&1; resume_halt_gate"
[ "$(halt_field "$ws" resolved)" = "0" ] \
  && ok "halt NOT resolved by the foreign ruling" \
  || bad "cross-slice ruling resolved the halt (identity unbound)"
put_ruling "$ws" 01 any 201 "the real answer"
assert_rc 0 "a ruling addressed to the halt's slice resumes" -- \
  bash -c ". '$hf' '$ws' > /dev/null 2>&1; resume_halt_gate"
[ "$(halt_field "$ws" resolved)" = "1" ] && ok "halt resolved by the matching ruling" \
  || bad "matching ruling did not resolve"

echo "-- ruling identity: stage-addressed ruling must match the halted stage --"
ws=$(new_ws haltb)
put_halt "$ws" class_u 01 spec 1 100
put_ruling "$ws" 01 postcheck 200 "wrong stage"
assert_rc 20 "a ruling addressed to another STAGE stays parked" -- \
  bash -c ". '$hf' '$ws' > /dev/null 2>&1; resume_halt_gate"
put_ruling "$ws" 01 spec 201 "right stage"
assert_rc 0 "a stage-matching ruling resumes" -- \
  bash -c ". '$hf' '$ws' > /dev/null 2>&1; resume_halt_gate"

echo "-- ruling identity: a SAME-SECOND ruling resolves (halt-id binding, not clock order) --"
ws=$(new_ws haltid)
now=$(date +%s)
( . "$RS/lib/state.sh"
  { echo "reason=class_u"; echo "detail=fixture"; echo "slice=01"; echo "stage=spec"
    echo "round=1"; echo "t=$now"; echo "notified=1"; echo "resolved=0"
    echo "halt_id=HFIX1"; } | state_set "$ws" halt ferry ) > /dev/null
"$RS/launch.sh" rule "$ws" --slice 01 --text "same-second answer" > /dev/null 2>&1 \
  || bad "launch.sh rule failed"
assert_rc 0 "a ruling written in the SAME epoch second as the halt resolves it (epoch seconds are the platform's granularity — a strict newer-than comparison loses this race)" -- \
  bash -c ". '$hf' '$ws' > /dev/null 2>&1; resume_halt_gate"
[ "$(halt_field "$ws" resolved)" = "1" ] \
  && ok "halt resolved by the same-second ruling" || bad "same-second ruling invisible"

echo "-- ruling identity: a ruling bound to a PREVIOUS halt never resolves a new one --"
ws=$(new_ws haltid2)
now=$(date +%s)
( . "$RS/lib/state.sh"
  state_append "$ws" rulings operator \
    "v=1 t=$((now + 50)) slice=01 stage=any n=1 halt_id=HOLD file=slices/01/ruling.1.md text=answers the OLD halt" ) > /dev/null
( . "$RS/lib/state.sh"
  { echo "reason=class_u"; echo "detail=fixture"; echo "slice=01"; echo "stage=spec"
    echo "round=1"; echo "t=$now"; echo "notified=1"; echo "resolved=0"
    echo "halt_id=HNEW"; } | state_set "$ws" halt ferry ) > /dev/null
assert_rc 20 "a clock-newer ruling carrying ANOTHER halt's id stays parked (identity, not time, answers a halt)" -- \
  bash -c ". '$hf' '$ws' > /dev/null 2>&1; resume_halt_gate"
[ "$(halt_field "$ws" resolved)" = "0" ] \
  && ok "stale-bound ruling did not resolve the new halt" \
  || bad "a ruling for a previous halt resolved a new one (time comparison, not identity)"

echo "-- class_u round-trip keeps re-entering the suspended stage --"
ws=$(new_ws haltc)
( . "$RS/lib/state.sh"
  state_put "$ws" stage ferry "slice=01" "stage=spec" "round=1" "attempt=1" \
    "state=done" "nonce=nC" "spawn_t=1" ) > /dev/null
put_halt "$ws" class_u 01 spec 1 100
put_ruling "$ws" 01 any 200 "ruled"
assert_rc 0 "resume passes" -- bash -c ". '$hf' '$ws' > /dev/null 2>&1; resume_halt_gate"
[ "$(state_field "$ws" stage state)" = "failed" ] \
  && ok "suspended done-stage reset to re-enter WITH the ruling in its manifest" \
  || bad "stage state is '$(state_field "$ws" stage state)', not failed"

echo "-- a --topic ruling addressed to a slice still resolves THAT slice's halt (scope= rides beside slice=, never instead of it) --"
wst=$(new_ws haltts)
put_halt "$wst" class_u 01 spec 1 100
( . "$RS/lib/state.sh"
  state_append "$wst" rulings operator \
    "v=1 t=200 slice=01 stage=any scope=topic n=1 file=slices/01/ruling.1.md text=a mechanism rule for every slice" ) > /dev/null
assert_rc 0 "resume with a scope=topic ruling naming slice 01 resolves the slice-01 halt" -- \
  bash -c ". '$hf' '$wst' > /dev/null 2>&1; resume_halt_gate"
[ "$(halt_field "$wst" resolved)" = "1" ] \
  && ok "halt resolved — the scope token is carriage, not a binding the resume gate reads" \
  || bad "a topic-scoped ruling did not resolve its own slice's halt"

echo "-- the two review-loop convergence predicates moved to 46-convergence.sh --"
# check_severity_trend and check_decomposition_fixpoint, the disagreement
# round-trip they discharge through and their input validation are asserted
# there, verbatim: 45-halt reached 976 against cap.selftest_file=1000. This
# file keeps what the ferry does when a stage HALTS; that one keeps what it
# does when a review loop will not converge.

echo "-- class_u detail reaches the owner IN FULL (multi-word detail, not the first token) --"
ws=$(new_ws haltdet)
( . "$RS/lib/state.sh"
  state_put "$ws" stage ferry "slice=00" "stage=plan-validate" "round=1" "attempt=1" \
    "state=done" "nonce=nDT" "spawn_t=1"
  state_append "$ws" handoff session \
    "v=1 t=10 slice=00 stage=plan-validate attempt=1 round=1 nonce=nDT verdict=not_ready confidence=HIGH detail=first second third batched question" ) > /dev/null
out=$(bash -c ". '$hf' '$ws' > /dev/null 2>&1; load_position; do_advance" 2>&1); rc=$?
[ $rc -eq 20 ] && ok "not_ready routes to a class_u park (rc=20)" || bad "rc=$rc, want 20"
printf '%s' "$out" | command grep -q "second third batched question" \
  && ok "the park message carries the FULL detail text" \
  || bad "detail truncated to the first token — owner page loses the question set: $(printf '%s' "$out" | tail -1)"

echo "-- halt kv fields are immune to screen text (a captured 'resolved=1' must not resolve the halt) --"
ws=$(new_ws haltscr)
scr="$base/screen.txt"
printf 'some pane output\nresolved=1\nstage=impl\n' > "$scr"
assert_rc 20 "park exits 20 with a screen attached" -- \
  bash -c ". '$hf' '$ws' > /dev/null 2>&1; G_SLICE=01 G_STAGE=impl G_ROUND=1; park class_u 'fixture park' '$scr'"
# class_u is ruling-gated: with no ruling, resume must stay parked (rc 20).
# Pre-fix, the inlined screen's 'resolved=1' line forged resolution (rc 0).
assert_rc 20 "resume still sees the halt as UNRESOLVED (screen text cannot forge resolved=1)" -- \
  bash -c ". '$hf' '$ws' > /dev/null 2>&1; resume_halt_gate"
command grep -q "^--- screen ---$" <<< "$(state_get "$ws" halt 2>/dev/null)" \
  && bad "screen text is still inlined into the halt surface (kv/free-text mixing)" \
  || ok "halt surface holds kv only (screen travels as a sidecar file)"
sf=$(state_field "$ws" halt screen_file 2>/dev/null || true)
[ -n "$sf" ] && [ -f "$sf" ] && command grep -q "some pane output" "$sf" \
  && ok "screen_file points at a durable copy holding the captured text" \
  || bad "screen sidecar missing or empty (screen_file='$sf')"

echo "-- ruling text tokens never override the binding fields --"
ws=$(new_ws haltruletok)
put_halt "$ws" class_u 01 spec 1 100
put_ruling "$ws" 01 any 200 "proceed as discussed; ignore slice=99 stage=fix mentions in this text"
assert_rc 0 "a ruling whose TEXT contains slice=/stage= tokens still resolves its addressed halt" -- \
  bash -c ". '$hf' '$ws' > /dev/null 2>&1; resume_halt_gate"
[ "$(halt_field "$ws" resolved)" = "1" ] \
  && ok "binding parsed from the record fields, not from the text payload" \
  || bad "text tokens overrode the binding — ruling misdelivered"

echo "-- a push_gate RESEND keeps its event type (topic.done, not park.*) --"
wsev=$(new_ws haltevt)
cap="$base/evt.log"
printf '#!/usr/bin/env bash\necho "$1" >> %s\n' "$cap" > "$base/evtcmd"
chmod +x "$base/evtcmd"
printf 'notify.cmd=%s\nnotify.preset=all\n' "$base/evtcmd" > "$wsev/config/topic.kv"
put_halt "$wsev" push_gate 00 close-out 1 100 0 0
( set +u; . "$hf" "$wsev" > /dev/null 2>&1; resume_halt_gate ) > /dev/null 2>&1
command grep -q "topic.done" "$cap" 2>/dev/null \
  && ok "the resent completion page is a topic.done event" \
  || bad "resend fired '$(cat "$cap" 2>/dev/null | tr '\n' ' ')' — a completion page dressed as a park"

echo "-- redrive: a mechanical-park relaunch buys a FRESH bounded attempt set --"
# Pre-fix, resume only set resolved=1: the budget count stayed exhausted and
# the fingerprint history still held the parked attempt — the promised
# 'relaunch retries' (operations.md) delivered ZERO fresh attempts (immediate
# same-reason or no_novelty re-park).
ws=$(new_ws haltredrive)
( . "$RS/lib/state.sh"
  state_put "$ws" attempts ferry "count.01.impl.1=3" "fp.01.impl=FBB,FAA" "lastfail.01.impl=dead" ) > /dev/null
put_halt "$ws" dead 01 impl 1 100
assert_rc 0 "mechanical halt clears on relaunch" -- \
  bash -c ". '$hf' '$ws' > /dev/null 2>&1; resume_halt_gate"
cnt=$(state_field "$ws" attempts "count.01.impl.1" 2>/dev/null || true)
[ "${cnt:-0}" = "0" ] || [ -z "$cnt" ] \
  && ok "attempt count cleared — the relaunch owns a fresh budget (redrive)" \
  || bad "count still '$cnt' — relaunch re-parks on the exhausted budget with zero new attempts"
fph=$(state_field "$ws" attempts "fp.01.impl" 2>/dev/null || true)
[ -z "$fph" ] \
  && ok "fingerprint history cleared — the respawn is not no_novelty-blocked" \
  || bad "fp history still '$fph' — the first respawn fingerprint-matches the parked attempt"


echo "-- ruling archive numbering is max+1, never count+1 (a gap must not cause overwrite) --"
wsg=$(new_ws haltgap)
mkdir -p "$wsg/slices/01"
echo "first" > "$wsg/slices/01/ruling.1.md"
echo "third" > "$wsg/slices/01/ruling.3.md"
"$RS/launch.sh" rule "$wsg" --slice 01 --text "the fourth ruling" > /dev/null 2>&1 \
  || bad "launch.sh rule failed"
[ -f "$wsg/slices/01/ruling.4.md" ] \
  && ok "new ruling archived as ruling.4.md (max+1)" \
  || bad "ruling.4.md absent — count+1 numbering"
command grep -q "third" "$wsg/slices/01/ruling.3.md" \
  && ok "ruling.3.md not overwritten" \
  || bad "ruling.3.md was OVERWRITTEN: $(cat "$wsg/slices/01/ruling.3.md")"

echo "-- workflow_changed: deliberate relaunch repins (operations.md §3 contract) --"
ws=$(new_ws haltf)
( . "$RS/lib/state.sh"
  state_put "$ws" run ferry "topic=haltf" "workflow_sha=OLDSHA" "t_start=1" ) > /dev/null
put_halt "$ws" workflow_changed 01 impl 1 100
assert_rc 0 "relaunch resume clears the workflow_changed halt" -- \
  bash -c ". '$hf' '$ws' > /dev/null 2>&1; workflow_sha() { echo NEWSHA; }; resume_halt_gate"
[ "$(state_field "$ws" run workflow_sha)" = "NEWSHA" ] \
  && ok "run surface repinned to the new workflow SHA (upgrade adopted, audited)" \
  || bad "workflow_sha still '$(state_field "$ws" run workflow_sha)' — relaunch loops on the same park"
( . "$RS/lib/state.sh"; state_get "$ws" audit | command grep 'adopted' | command grep -q 'slice=01' ) \
  && ok "the adoption audit names the freeze point (slice/stage where the topic froze)" \
  || bad "adoption audit carries no freeze point — the seam is invisible to postmortem"

echo "-- workflow pin sees a DIRTY tree: HEAD unchanged, uncommitted edits park --"
# Bug pin_blind_to_uncommitted: committed drift parked loudly, uncommitted
# drift was adopted silently — while live sessions execute the live tree by
# absolute hook paths. The pin folds the subtree's porcelain status into the
# value; check_workflow_pin itself is unchanged (fires at every run_attempt).
wsd=$(new_ws haltdirty)
wtree=$(sc_tmpdir)
( cd "$wtree" && git init -q . \
  && git config user.email sc@example.invalid && git config user.name selfcheck \
  && mkdir wf && echo lib > wf/lib.sh && echo other > toplevel.txt \
  && git add -A && git commit -qm "chore: fixture workflow tree" )
pin=$(bash -c ". '$hf' '$wsd' > /dev/null 2>&1; WROOT='$wtree/wf'; workflow_sha")
( . "$RS/lib/state.sh"
  state_put "$wsd" run ferry "topic=haltdirty" "workflow_sha=$pin" "t_start=1" ) > /dev/null
assert_rc 0 "a clean tree matches its pin" -- \
  bash -c ". '$hf' '$wsd' > /dev/null 2>&1; WROOT='$wtree/wf'; check_workflow_pin"
echo tampered >> "$wtree/wf/lib.sh"
assert_rc 20 "HEAD unchanged + a tracked edit inside the workflow subtree PARKS (pre-fix: silent adoption)" -- \
  bash -c ". '$hf' '$wsd' > /dev/null 2>&1; G_SLICE=01 G_STAGE=impl G_ROUND=1; WROOT='$wtree/wf'; check_workflow_pin"
[ "$(halt_field "$wsd" reason)" = "workflow_changed" ] \
  && ok "the dirty-tree park is the same self-describing workflow_changed halt" \
  || bad "park reason '$(halt_field "$wsd" reason)', want workflow_changed"
git -C "$wtree" checkout -q wf/lib.sh
echo new-script > "$wtree/wf/new-check.sh"
assert_rc 20 "an UNTRACKED file inside the subtree parks too (a brand-new script is exactly the edit that bites)" -- \
  bash -c ". '$hf' '$wsd' > /dev/null 2>&1; G_SLICE=01 G_STAGE=impl G_ROUND=1; WROOT='$wtree/wf'; check_workflow_pin"
rm "$wtree/wf/new-check.sh"
echo drift > "$wtree/toplevel.txt"
assert_rc 0 "dirt OUTSIDE the workflow subtree does NOT park (git -C walks to the repo toplevel; the status is scoped -- .)" -- \
  bash -c ". '$hf' '$wsd' > /dev/null 2>&1; WROOT='$wtree/wf'; check_workflow_pin"
echo "-- the pin is the SUBTREE object: a sibling tree's COMMIT must not park --"
# Measured on the dogfood topic: of ten workflow_changed parks, SIX compared
# pin-to-pin identical delivery-workflow subtrees. The repo holds a second
# workflow under daily development (111 commits in one day), and every one of
# its commits moved the HEAD the pin used to read. The dirty term was already
# subtree-scoped; the committed term now agrees with it.
( cd "$wtree" && git add toplevel.txt && git commit -qm "chore: sibling tree work" )
assert_rc 0 "a COMMIT outside the workflow subtree does NOT park (pre-fix: HEAD moved, so it did)" -- \
  bash -c ". '$hf' '$wsd' > /dev/null 2>&1; WROOT='$wtree/wf'; check_workflow_pin"
( cd "$wtree" && echo real >> wf/lib.sh && git add wf/lib.sh \
  && git commit -qm "chore: workflow tree work" )
assert_rc 20 "a COMMIT inside the subtree still parks — the pin narrowed, it did not go blind" -- \
  bash -c ". '$hf' '$wsd' > /dev/null 2>&1; G_SLICE=01 G_STAGE=impl G_ROUND=1; WROOT='$wtree/wf'; check_workflow_pin"

echo tampered >> "$wtree/wf/lib.sh"
put_halt "$wsd" workflow_changed 01 impl 1 100
assert_rc 0 "a deliberate relaunch ADOPTS the dirty tree (repin, audited)" -- \
  bash -c ". '$hf' '$wsd' > /dev/null 2>&1; WROOT='$wtree/wf'; resume_halt_gate"
case "$(state_field "$wsd" run workflow_sha)" in
  *-dirty:*) ok "the repinned value carries the dirty fingerprint (self-describing pin shape)" ;;
  *) bad "repinned value '$(state_field "$wsd" run workflow_sha)' has no -dirty suffix" ;;
esac
assert_rc 0 "the SAME dirt then compares equal (the topic runs; more edits would re-park)" -- \
  bash -c ". '$hf' '$wsd' > /dev/null 2>&1; WROOT='$wtree/wf'; check_workflow_pin"

echo "-- plan_changed: ruling-gated (never resume on a silently moved plan) --"
ws=$(new_ws haltg)
( . "$RS/lib/state.sh"
  state_put "$ws" run ferry "topic=haltg" "plan_hash=OLDHASH" "t_start=1" > /dev/null
  state_put "$ws" stage ferry "slice=01" "stage=impl" "round=1" "attempt=1" \
    "state=done" "nonce=nPG" "spawn_t=1" > /dev/null
  printf 'id=01 status=active risk=low title=one rederive=0\nid=02 status=pending risk=low title=two rederive=0\n' \
    | state_set "$ws" slices ferry ) > /dev/null
put_halt "$ws" plan_changed "" "" "" 100
assert_rc 20 "plan_changed without a ruling stays parked" -- \
  bash -c ". '$hf' '$ws' > /dev/null 2>&1; resume_halt_gate"
put_ruling "$ws" 00 any 200 "re-split against the new plan"
assert_rc 0 "plan_changed with an owner ruling resumes" -- \
  bash -c ". '$hf' '$ws' > /dev/null 2>&1; resume_halt_gate"
cur=$(md5sum "$ws/../plan.md" | awk '{print $1}')
[ "$(state_field "$ws" run plan_hash)" = "$cur" ] \
  && ok "plan hash repinned to the current plan on the ruled resume" \
  || bad "plan_hash not repinned"
[ "$(state_field "$ws" stage stage)" = "plan-validate" ] \
  && ok "the ruled resume re-enters plan-validate (the earliest stage whose premise the plan binds), not the frozen stage" \
  || bad "position is '$(state_field "$ws" stage slice 2>/dev/null)/$(state_field "$ws" stage stage 2>/dev/null)' — the decomposition premise is stale but the pipeline resumes past validation/split"
( . "$RS/lib/state.sh"; state_get "$ws" slices | command grep 'id=01' \
    | command grep -q 'status=pending.*rederive=1\|rederive=1.*status=pending' ) \
  && ok "the interrupted ACTIVE slice is demoted to pending + rederive (else next_pending_slice would skip it forever)" \
  || bad "interrupted slice not demoted: $( . "$RS/lib/state.sh"; state_get "$ws" slices | command grep 'id=01')"

echo "-- notified flag: never set when the transport is absent or failing --"
ws=$(new_ws halth)
assert_rc 20 "park exits 20 (no transport configured)" -- \
  bash -c ". '$hf' '$ws' > /dev/null 2>&1; G_SLICE=01 G_STAGE=spec G_ROUND=1; park owed_miss 'fixture miss'"
[ "$(halt_field "$ws" notified)" = "0" ] \
  && ok "notified stays 0 with no transport (at-least-once: relaunch re-sends)" \
  || bad "notified=1 written though nothing was delivered"
echo "notify.cmd=printf '%s|%s\\n' >> $base/resend.txt" > "$ws/config/topic.kv"
assert_rc 0 "relaunch resume clears the mechanical owed_miss halt (after re-sending)" -- \
  bash -c ". '$hf' '$ws' > /dev/null 2>&1; resume_halt_gate"
command grep -q 'RESEND' "$base/resend.txt" 2>/dev/null \
  && ok "halt-without-flag re-sent on relaunch (a duplicate page beats a lost one)" \
  || bad "no RESEND fired for a halt with notified=0"
[ "$(halt_field "$ws" notified)" = "1" ] \
  && ok "flag set only after the successful re-send" \
  || bad "flag still unset after a delivered re-send"

echo "-- complete_topic: an undelivered topic.done leaves notified=0 (at-least-once) --"
ws=$(new_ws haltk)
echo "notify.cmd=/bin/false" > "$ws/config/topic.kv"
( set +u; . "$hf" "$ws" > /dev/null 2>&1; complete_topic ) > /dev/null 2>&1
rc=$?
[ $rc -eq 0 ] && ok "complete_topic exits 0 (the topic IS complete)" \
  || bad "complete_topic rc=$rc, want 0"
[ "$(halt_field "$ws" reason)" = "push_gate" ] \
  && ok "push_gate halt written at COMPLETE" || bad "no push_gate halt"
[ "$(halt_field "$ws" notified)" = "0" ] \
  && ok "failed transport leaves notified=0 (a relaunch re-sends; the owner's page is never silently dropped)" \
  || bad "notified=1 though the transport failed — the completion page is lost forever"
echo "notify.cmd=printf '%s|%s\\n' >> $base/complete-resend.txt" > "$ws/config/topic.kv"
out=$(bash -c ". '$hf' '$ws' > /dev/null 2>&1; resume_halt_gate" 2>&1); rc=$?
command grep -q 'topic.done' "$base/complete-resend.txt" 2>/dev/null \
  && ok "relaunch re-sent the undelivered completion page (RESEND path)" \
  || bad "no re-send for the undelivered COMPLETE page"
[ "$(halt_field "$ws" notified)" = "1" ] \
  && ok "flag set only after the successful re-send" || bad "flag still 0 after re-send"
[ $rc -eq 0 ] \
  && ok "relaunch on a completed topic exits 0 (push_gate is a terminal marker, not a resumable gate)" \
  || bad "relaunch after COMPLETE rc=$rc — a completed topic demands a ruling to 'resume' into re-completing itself"
printf '%s' "$out" | command grep -qi 'complete' \
  && ok "the idempotent relaunch says the topic is COMPLETE and push is the owner's" \
  || bad "no COMPLETE message on relaunch: $out"
bash -c ". '$hf' '$ws' > /dev/null 2>&1; resume_halt_gate" > /dev/null 2>&1
[ "$(command grep -c 'topic.done' "$base/complete-resend.txt" 2>/dev/null)" = "1" ] \
  && ok "a second relaunch re-sends NOTHING (idempotent; no duplicate page per relaunch)" \
  || bad "duplicate completion pages: $(command grep -c 'topic.done' "$base/complete-resend.txt") sends"

echo "-- capability admission: a missing capability REFUSES, self-describing (contract row's own coverage) --"
ws=$(new_ws haltadm)
decl_ok=$(sc_tmpdir)/full.kv
decl_bad=$(sc_tmpdir)/nohb.kv
printf 'family=pty_tmux\ncap=pty,subagent,stop_gate,heartbeat\n' > "$decl_ok"
printf 'family=pty_tmux\ncap=pty,subagent,stop_gate\n' > "$decl_bad"
out=$( ( set +u; . "$hf" "$ws" > /dev/null 2>&1; G_SLICE=01 G_STAGE=spec G_ROUND=1
         check_admission author "$decl_bad" ) 2>&1 ); rc=$?
[ $rc -eq 20 ] && ok "author on a heartbeat-less backend parks (rc=20), never a silent fallback" \
  || bad "check_admission rc=$rc on a missing capability, want 20"
[ "$(halt_field "$ws" reason)" = "template_error" ] \
  && ok "the refusal parks template_error" || bad "park reason '$(halt_field "$ws" reason)'"
halt_field "$ws" detail | command grep -q "heartbeat" \
  && ok "the refusal NAMES the missing capability" || bad "detail: $(halt_field "$ws" detail)"
assert_rc 0 "a declaration with every required capability admits" -- \
  bash -c ". '$hf' '$ws' > /dev/null 2>&1; G_SLICE=01 G_STAGE=spec G_ROUND=1; check_admission author '$decl_ok'"

echo "-- the FACT is checked at the same line as the promise: a valid probe record must stand --"
# backend-seam.md §2: "Declarations are promises; the onboarding probe makes
# them facts." check_admission above reads the declared capability LIST — the
# promise — and nothing ever asked whether it had been PROVEN; the probe ran at
# launch over a different, smaller set, so a backend named only in a slice
# override could reach a real session unproven.
hfp=$(dirname "$hf")/probe.sh
precond "the headless ferry carries probe.sh (the guard resolves it through FERRY_DIR)" test -e "$hfp"
# The guard's question is no longer "is there a valid record" but "is this
# backend proven, or provable RIGHT NOW" — it re-proves inline before parking.
# So every arm below runs against a STUBBED probe whose answer the fixture
# controls: identity and --verify delegate to the real implementation (the
# record's key must stay the real one) and only the LIVE run is scripted.
# Without the stub these arms would still park — the fixture declaration
# declares no profile=, so a real probe refuses — and they would be passing
# for a reason they do not state.
hfd=$(sc_tmpdir)
ln -sn "$RS/lib" "$hfd/lib"; ln -sn "$RS/backends" "$hfd/backends"
sed '$d' "$RS/ferry.sh" > "$hfd/ferry-headless.sh"
CTL="$hfd/probe.ctl"
cat > "$hfd/probe.sh" <<STUB
#!/usr/bin/env bash
# stub probe: identity and --verify delegate to the real one; a LIVE run does
# what \$CTL says, and records the attempt so the test can count sessions.
case "\$1" in
  --identity|--verify) exec bash "$hfp" "\$@" ;;
esac
echo "\$@" >> "$hfd/live-runs"
case "\$(cat "$CTL" 2>/dev/null)" in
  pass) { bash "$hfp" --identity "\$2" "\$3"; echo "result=pass"; echo "t=\$(date +%s)"; } \
          > "\$1/.runtime/probe/\$3.kv"; exit 0 ;;
  quota) exit 4 ;;
  quotarec) { bash "$hfp" --identity "\$2" "\$3"; echo "result=backend_quota"; echo "t=\$(date +%s)"; } \
          > "\$1/.runtime/probe/\$3.kv"; exit 4 ;;
  overload) { bash "$hfp" --identity "\$2" "\$3"; echo "result=backend_overloaded"; echo "t=\$(date +%s)"; } \
          > "\$1/.runtime/probe/\$3.kv"; exit 4 ;;
  passbad) : > "\$1/.runtime/probe/\$3.kv"; exit 0 ;;   # exits 0, leaves nothing the guard accepts
  *) exit 1 ;;
esac
STUB
chmod +x "$hfd/probe.sh"
wsp=$(new_ws haltproven)
mkdir -p "$wsp/.runtime/probe"
decl_p=$(sc_tmpdir)/proven.kv
cp "$decl_ok" "$decl_p"
stamp_record() { # result
  { bash "$hfp" --identity "$decl_p" test1; echo "result=$1"; echo "t=$(date +%s)"; } \
    > "$wsp/.runtime/probe/test1.kv"
}
proven() { bash -c ". '$hfd/ferry-headless.sh' '$wsp' > /dev/null 2>&1; G_SLICE=01 G_STAGE=spec G_ROUND=1; check_backend_proven test1 '$decl_p' m0 low"; }
echo fail > "$CTL"; : > "$hfd/live-runs"
assert_rc 20 "a backend that is neither proven NOR provable parks at the SPAWN — not three stages later" -- proven
[ "$(command grep -c . "$hfd/live-runs" 2>/dev/null || echo 0)" -eq 1 ] \
  && ok "and it TRIED first — one inline probe, because an absent record and a stale one have the same mechanical recovery" \
  || bad "inline probe runs: $(cat "$hfd/live-runs" 2>/dev/null | tr '\n' ';')"
[ "$(halt_field "$wsp" reason)" = "template_error" ] \
  && ok "the park reason is template_error (an admission input the probe could not supply — the documented class)" \
  || bad "park reason '$(halt_field "$wsp" reason)'"
halt_field "$wsp" detail | command grep -q "test1" \
  && ok "the park NAMES the backend that could not be proven" || bad "detail: $(halt_field "$wsp" detail)"
halt_field "$wsp" detail | command grep -q "relaunch will not clear it" \
  && ok "and says a relaunch will NOT clear it — the probe RAN and refused, so the operator is sent to the declaration, not to the clock (launch.sh:95-98's rule about two sentences)" \
  || bad "the park does not say what a relaunch would do: $(halt_field "$wsp" detail)"
stamp_record pass
assert_rc 0 "a VALID pass record admits the spawn (good direction — the fixture can tell the two apart)" -- proven
stamp_record fail
assert_rc 20 "a record that is not a pass parks (result= is part of the predicate, not the file's mere existence)" -- proven
stamp_record pass
printf 'nudge_text=continue\n' >> "$decl_p"
assert_rc 20 "editing the DECLARATION after the record invalidates it (a pass attests the content it saw)" -- proven
stamp_record pass
assert_rc 0 "re-stamping against the edited declaration admits again — the guard reads an identity, it is not a wedge" -- proven
# The inline re-probe SPAWNS, so it cannot invent a model or an effort: an
# empty one substitutes into cmd.launch as a hole the placeholder guard cannot
# see (it only catches an unresolved `{...}`). A caller that cannot say what to
# run is a caller bug, and it must not reach a spawn. The guard sits on the
# SPAWNING path only — a valid record admits without one, and refusing there
# would break a call that had no reason to fail — so the record is invalidated
# first to reach it.
stamp_record fail
: > "$hfd/live-runs"
assert_rc 20 "calling the guard with no model/effort parks instead of spawning a hole" -- \
  bash -c ". '$hfd/ferry-headless.sh' '$wsp' > /dev/null 2>&1; G_SLICE=01 G_STAGE=spec G_ROUND=1; check_backend_proven test1 '$decl_p'"
[ ! -s "$hfd/live-runs" ] \
  && ok "and no probe was spawned on the way (the refusal precedes the session)" \
  || bad "a probe ran without a model/effort: $(cat "$hfd/live-runs")"

echo "-- a CLI self-update is re-proved inline, not parked for a human to retype the command --"
# Two anchors nine slices apart (slice 10 fix, slice 13 precheck), same
# mechanism: the CLI self-updated mid-run, --verify's stored version no longer
# matched, and the topic parked `template_error`. Diagnosed both times by the
# documented comparison — ONLY version= differed; decl_hash, profile_hash and
# probe_impl all matched. Three versions on this host in one day (2.1.235
# 02:45, 2.1.236 10:46, 2.1.237 12:12), each transition one park.
# template_error's other members — missing artifact, template render failure,
# config fault — all need an INPUT fixed first. This one needed a human to
# type `launch.sh launch <ws>` with no argument changed, and the pilot is
# optional middleware, so a full-auto topic simply stopped. The ferry now does
# the mechanical thing itself and parks only on what a human could answer.
# The probe is stubbed here: this arm is about the ferry's DECISION, and a real
# probe session is the drill's territory.
wsr=$(new_ws haltreprobe)
mkdir -p "$wsr/.runtime/probe" "$wsr/.runtime/logs"
decl_r=$(sc_tmpdir)/reprobe.kv
cp "$decl_ok" "$decl_r"
stale_record() { # write a record whose identity cannot match (the self-update shape)
  { bash "$hfp" --identity "$decl_r" test1 | sed 's/^version=.*/version=OLD-CLI-0.0/'
    echo "result=pass"; echo "t=$(date +%s)"; } > "$wsr/.runtime/probe/test1.kv"
}
reproven() { bash -c ". '$hfd/ferry-headless.sh' '$wsr' > /dev/null 2>&1; G_SLICE=01 G_STAGE=spec G_ROUND=1; check_backend_proven test1 '$decl_r' m0 low"; }
precond "the stale record differs from the live identity ONLY in version="   bash -c 'stale=$(sed -n "s/^version=//p" "$1"); live=$(bash "$2" --identity "$3" test1 | sed -n "s/^version=//p"); [ "$stale" != "$live" ]'   _ "$wsr/.runtime/probe/test1.kv" "$hfp" "$decl_r" 2>/dev/null || true
stale_record
echo pass > "$CTL"; : > "$hfd/live-runs"
assert_rc 0 "a stale probe record RE-PROVES inline and the spawn proceeds (rc=0, no park)" -- reproven
[ "$(command grep -c . "$hfd/live-runs" 2>/dev/null || echo 0)" -eq 1 ]   && ok "exactly one live probe was run — the mechanical recovery, done once"   || bad "live probe runs: $(cat "$hfd/live-runs" 2>/dev/null | tr '\n' ';')"
command grep -q '^result=pass' "$wsr/.runtime/probe/test1.kv"   && ok "and the record it left is the one --verify will accept next spawn"   || bad "record after the inline probe: $(tr '\n' ' ' < "$wsr/.runtime/probe/test1.kv")"
: > "$hfd/live-runs"
assert_rc 0 "the NEXT spawn takes the cached path (no second session for the same version)" -- reproven
[ ! -s "$hfd/live-runs" ]   && ok "no live probe on the second spawn — the inline re-prove is not a per-spawn tax"   || bad "a second live probe ran: $(cat "$hfd/live-runs")"
# Bad direction: the declaration really IS broken. The park must stay.
stale_record
echo fail > "$CTL"
assert_rc 20 "a stale record whose inline re-probe FAILS still parks (the guard is not disarmed)" -- reproven
[ "$(halt_field "$wsr" reason)" = "template_error" ]   && ok "and parks template_error — now naming a promise the probe actually disproved"   || bad "park reason '$(halt_field "$wsr" reason)'"
halt_field "$wsr" detail | command grep -qi 're-prov\|probe'   && ok "the detail says the inline re-probe was tried and what it said"   || bad "detail: $(halt_field "$wsr" detail)"
# A probe that exits 0 without leaving a record this guard accepts must NOT
# admit the spawn on its own say-so: the guard's question is the RECORD's
# identity, and the two disagreeing is a defect worth a loud park. Nothing
# exercised this until a mutation replaced the re-verify with `true` and the
# suite stayed green.
stale_record
echo passbad > "$CTL"
assert_rc 20 "a probe that PASSES but leaves no record the guard accepts still parks (re-asked, never assumed)" -- reproven
halt_field "$wsr" detail | command grep -q 'still does not verify' \
  && ok "and the park says the probe and the guard disagree about what identifies a pass" \
  || bad "detail: $(halt_field "$wsr" detail)"
# And an out-of-quota backend is an AVAILABILITY fact, not a broken promise —
# probe.sh's own cache bypass keys on exactly this halt reason.
stale_record
echo quota > "$CTL"
assert_rc 20 "an inline re-probe that finds NO QUOTA parks backend_quota, not template_error" -- reproven
[ "$(halt_field "$wsr" reason)" = "backend_quota" ]   && ok "the park names availability (the reason probe.sh's cache bypass reads)"   || bad "park reason '$(halt_field "$wsr" reason)' — a quota-dead backend would send the operator to the declaration"
# Exit 4 now means "the BACKEND refused" and there are TWO of those, so the
# reason is read from the record the probe just wrote. The two need OPPOSITE
# operator actions — quota names a reset time to wait for, 529-overload names
# none — so parking the wrong one sends the operator to wait out a clock that
# does not exist. Both directions, plus the no-record fallback above (a probe
# killed before it could write is the case that arm already covers).
stale_record
echo quotarec > "$CTL"
assert_rc 20 "a re-probe that WRITES result=backend_quota still parks backend_quota" -- reproven
[ "$(halt_field "$wsr" reason)" = "backend_quota" ] \
  && ok "the record's own result is read, not assumed (backend_quota)" \
  || bad "park reason '$(halt_field "$wsr" reason)' — want backend_quota"
stale_record
echo overload > "$CTL"
assert_rc 20 "a re-probe that finds an OVERLOADED backend parks backend_overloaded, not backend_quota" -- reproven
[ "$(halt_field "$wsr" reason)" = "backend_overloaded" ] \
  && ok "the park names the right availability class (529-overload, no reset time to wait on)" \
  || bad "park reason '$(halt_field "$wsr" reason)' — a 529 parked as backend_quota sends the operator to wait out a clock nothing publishes"
halt_field "$wsr" detail | command grep -q 'no reset time is published' \
  && ok "and the detail says there is no clock — the one thing that differs from a quota park" \
  || bad "detail: $(halt_field "$wsr" detail)"

echo "-- and the version query it runs is BOUNDED (it now runs at EVERY spawn) --"
# --verify asks the CLI what it is, inside the ferry's own process, once per
# spawn. This exact command has hung past four minutes on the CLI's own
# self-update prompt (backend-seam.md §2, a wrapper CLI's modal.self_update), and
# an unbounded hang there wedges the run SILENTLY: the watchdog classifies
# exits, so a driver that never exits is a driver nothing catches. Bounded, the
# same hang becomes `unknown`, fails the identity comparison, and parks loudly.
precond "the fixture declaration really names a version command that never answers" \
  bash -c 'command grep -qx "cmd.version=sleep 120" "$1"' _ "$hangdecl"
wait "$hang_pid"                      # started at the top of this check; see there
# The record must exist and hold its two numbers before the assertions below
# read it: the read's failure sentinels (999/0) sit exactly on the PASS side
# of both, so a run that never wrote anything would read as "verify returns,
# near its own bound" with no evidence either happened.
precond "the background --verify run recorded its rc and elapsed time" \
  bash -c 'test -s "$1" && read -r a b < "$1" && [ -n "$a" ] && [ -n "$b" ]' _ "$hang_out"
read -r vrc t_el < "$hang_out" || { vrc=999; t_el=0; }
[ "$vrc" -ne 124 ] \
  && ok "--verify RETURNS on a CLI that never answers (${t_el}s; the outer 40s guard never fired)" \
  || bad "--verify hung on cmd.version — at every spawn that wedges the ferry with nothing above it to notice"
[ "$t_el" -lt 30 ] \
  && ok "and it returns near its own bound (${t_el}s), not at the fixture's guard" \
  || bad "--verify took ${t_el}s: the bound is not doing its job"

echo "-- budget park names the dominant failure class (idle/dead), not just 'budget' --"
ws=$(new_ws halti)
( . "$RS/lib/state.sh"
  state_put "$ws" attempts ferry "count.01.spec.1=3" "lastfail.01.spec=idle" \
    "slice.01.started=$(date +%s)" ) > /dev/null
bash -c ". '$hf' '$ws' > /dev/null 2>&1; G_SLICE=01 G_STAGE=spec G_ROUND=1; check_budgets" 2>/dev/null
[ "$(halt_field "$ws" reason)" = "idle" ] \
  && ok "attempt budget spent on idle episodes parks 'idle' (design §4/§5 vocabulary)" \
  || bad "park reason is '$(halt_field "$ws" reason)', want idle"
( . "$RS/lib/state.sh"
  state_put "$ws" attempts ferry "lastfail.01.spec=dead" ) > /dev/null
bash -c ". '$hf' '$ws' > /dev/null 2>&1; G_SLICE=01 G_STAGE=spec G_ROUND=1; check_budgets" 2>/dev/null
[ "$(halt_field "$ws" reason)" = "dead" ] \
  && ok "attempt budget spent on deaths parks 'dead'" \
  || bad "park reason is '$(halt_field "$ws" reason)', want dead"
( . "$RS/lib/state.sh"
  state_put "$ws" attempts ferry "lastfail.01.spec=timeout" ) > /dev/null
bash -c ". '$hf' '$ws' > /dev/null 2>&1; G_SLICE=01 G_STAGE=spec G_ROUND=1; check_budgets" 2>/dev/null
[ "$(halt_field "$ws" reason)" = "budget_attempts" ] \
  && ok "other exhaustions still park budget_attempts (mapping is narrow)" \
  || bad "park reason is '$(halt_field "$ws" reason)', want budget_attempts"

echo "-- park time is credited at resume and excluded from the wallclock budgets --"
# Measured: an owner-level 18h park (ferry dead, zero attempts possible)
# spent the slice budget twice over — the budget priced calendar time, and a
# park is the one interval where the thrash it prices cannot happen.
ws=$(new_ws haltpark)
now=$(date +%s)
put_halt "$ws" dead 01 impl 1 $((now - 500))
assert_rc 0 "mechanical resume clears the halt" -- \
  bash -c ". '$hf' '$ws' > /dev/null 2>&1; resume_halt_gate"
pk=$(state_field "$ws" attempts "parked.01" 2>/dev/null || true)
[ -n "$pk" ] && [ "$pk" -ge 500 ] && [ "$pk" -le 510 ] \
  && ok "the parked interval landed in attempts parked.01 (${pk}s ~ 500s)" \
  || bad "parked.01='$pk', want ~500"
pt=$(state_field "$ws" run parked_total 2>/dev/null || true)
[ -n "$pt" ] && [ "$pt" -ge 500 ] && [ "$pt" -le 510 ] \
  && ok "and in run parked_total (topic account)" || bad "parked_total='$pt'"
bash -c ". '$hf' '$ws' > /dev/null 2>&1; resume_halt_gate" > /dev/null 2>&1
[ "$(state_field "$ws" attempts "parked.01" 2>/dev/null)" = "$pk" ] \
  && ok "a second resume adds NOTHING (resolved=1 short-circuits — no double count)" \
  || bad "double-counted: $(state_field "$ws" attempts "parked.01" 2>/dev/null) after re-resume"
# ... and a SECOND, distinct park on the same slice ADDS to the first. The
# idempotence arm above only proves one park is not counted twice; a credit that
# REPLACED instead of adding passes it and still loses the earlier park's time —
# and ferry.sh subtracts this number from the slice wallclock, so the slice dies
# on a clock it was never running on. Mutation-checked: `parked.$hs=$dur`
# survived the entire suite before this arm.
put_halt "$ws" dead 01 impl 2 $(( $(date +%s) - 200 ))
bash -c ". '$hf' '$ws' > /dev/null 2>&1; resume_halt_gate" > /dev/null 2>&1
pk2=$(state_field "$ws" attempts "parked.01" 2>/dev/null || true)
[ -n "$pk2" ] && [ "$pk2" -ge $((pk + 200)) ] && [ "$pk2" -le $((pk + 215)) ] \
  && ok "a second park on the same slice ACCUMULATES (${pk}s + ~200s = ${pk2}s), never replaces" \
  || bad "parked.01='$pk2' after a second ~200s park on top of ${pk}s — the credit replaced instead of adding"
pt2=$(state_field "$ws" run parked_total 2>/dev/null || true)
[ -n "$pt2" ] && [ "$pt2" -ge $((pt + 200)) ] \
  && ok "and the topic account accumulates with it (${pt2}s)" \
  || bad "parked_total='$pt2', want at least $((pt + 200))"

wsr2=$(new_ws haltpark2)
put_halt "$wsr2" class_u 01 spec 1 $(( $(date +%s) - 300 ))
put_ruling "$wsr2" 01 any $(date +%s) "ruled"
bash -c ". '$hf' '$wsr2' > /dev/null 2>&1; resume_halt_gate" > /dev/null 2>&1
pk=$(state_field "$wsr2" attempts "parked.01" 2>/dev/null || true)
[ -n "$pk" ] && [ "$pk" -ge 300 ] && [ "$pk" -le 310 ] \
  && ok "a ruling-gated resume credits the same way (${pk}s ~ 300s)" \
  || bad "class_u credit: parked.01='$pk'"
wsr3=$(new_ws haltpark3)
put_halt "$wsr3" push_gate 00 close-out 1 $(( $(date +%s) - 400 )) 1 0
out=$(bash -c ". '$hf' '$wsr3' > /dev/null 2>&1; resume_halt_gate" 2>&1)
# The gate's own completion line is the premise pin: an absence below over a
# gate that never ran is a green about nothing.
printf '%s' "$out" | command grep -q "nothing to resume" \
  && ok "the gate took the push_gate branch (terminal marker, idempotent relaunch)" \
  || bad "push_gate resume did not identify itself: $out"
[ -z "$(state_field "$wsr3" run parked_total 2>/dev/null)" ] \
  && ok "push_gate credits nothing (terminal marker — no run resumes after it)" \
  || bad "credit written on push_gate: $(state_field "$wsr3" run parked_total 2>/dev/null)"

echo "-- check_budgets meters WORKING time: the credited park is subtracted --"
ws=$(new_ws haltbudget)
( . "$RS/lib/state.sh"
  state_put "$ws" attempts ferry "slice.01.started=$(( $(date +%s) - 30000 ))" \
    "parked.01=5000"
  state_put "$ws" run ferry "topic=haltbudget" "t_start=$(( $(date +%s) - 30000 ))" \
    "parked_total=5000" ) > /dev/null
assert_rc 0 "30000s elapsed but 5000s parked -> 25000s working < 28800s budget: NO park (pre-fix: parked on calendar time)" -- \
  bash -c ". '$hf' '$ws' > /dev/null 2>&1; G_SLICE=01 G_STAGE=spec G_ROUND=1; check_budgets"
( . "$RS/lib/state.sh"; state_put "$ws" attempts ferry "parked.01=0" ) > /dev/null
out=$(bash -c ". '$hf' '$ws' > /dev/null 2>&1; G_SLICE=01 G_STAGE=spec G_ROUND=1; check_budgets" 2>&1); rc=$?
[ $rc -eq 20 ] \
  && ok "the same elapsed with NO park credit still parks budget_wallclock (the budget did not weaken)" \
  || bad "rc=$rc, want 20 — the subtraction disarmed the budget"
printf '%s' "$out" | command grep -q "working" \
  && ok "the park message states the metered quantity (working time, parked excluded)" \
  || bad "park message: $out"
wst=$(new_ws haltbudgett)
( . "$RS/lib/state.sh"
  state_put "$wst" attempts ferry "slice.01.started=$(date +%s)"
  state_put "$wst" run ferry "topic=haltbudgett" "t_start=$(( $(date +%s) - 260000 ))" \
    "parked_total=5000" ) > /dev/null
assert_rc 0 "topic budget likewise subtracts parked_total (260000-5000 < 259200)" -- \
  bash -c ". '$hf' '$wst' > /dev/null 2>&1; G_SLICE=01 G_STAGE=spec G_ROUND=1; check_budgets"
( . "$RS/lib/state.sh"; state_put "$wst" run ferry "parked_total=0" ) > /dev/null
assert_rc 20 "and without the credit the topic budget still fires" -- \
  bash -c ". '$hf' '$wst' > /dev/null 2>&1; G_SLICE=01 G_STAGE=spec G_ROUND=1; check_budgets"

echo "-- run init names the same-model ceiling (review independence is config) --"
# review-standards §12: lineage independence is not cognitive diversity — a
# reviewer on the author's own backend+model caps every verdict at the
# same-model ceiling, and the deployment is the one place that can change it.
ws=$(new_ws haltsame)
bash -c ". '$hf' '$ws' > /dev/null 2>&1; ensure_run_surface" > /dev/null 2>&1
( . "$RS/lib/state.sh"; state_get "$ws" audit 2>/dev/null | command grep -q "same-model ceiling" ) \
  && ok "a same-backend+model deployment is named in the audit surface at run init (deliberate, never silent)" \
  || bad "no same-model audit line at run init"
wsdm=$(new_ws haltdiverse)
printf 'agent.reviewer.model=other-reviewer-model\n' > "$wsdm/config/topic.kv"
bash -c ". '$hf' '$wsdm' > /dev/null 2>&1; ensure_run_surface" > /dev/null 2>&1
# Premise pin: the diverse deployment writes NO same-model audit line by
# design, so the null control cannot be pinned on the audit surface itself —
# but run init DID run for it, and its run surface is the proof. Over a run
# that never happened, the absence below would agree with anything.
_t=$( . "$RS/lib/state.sh"; state_field "$wsdm" run topic 2>/dev/null)
precond "run init wrote the diverse deployment's run surface (topic=$_t)" \
  test "$_t" = "haltdiverse"
( . "$RS/lib/state.sh"; command grep -q "same-model ceiling" <<< "$(state_get "$wsdm" audit 2>/dev/null)" ) \
  && bad "a DIVERSE reviewer deployment still audited the ceiling (null control broken)" \
  || ok "a different reviewer model audits nothing (the ceiling is gone; null control)"

echo "-- the run surface's workspace field re-stamps at every launch (a moved workspace self-heals) --"
# The field was derived-at-create and survived a measured tree-wide migration
# pointing at a dead path; the observation's falsifiable expectation named
# this exact one-line fix (two anchors). The proof shape is
# a migration at fixture scale: init at path A, MOVE, relaunch, read the
# field — it must name where the workspace IS, not where it was born.
wsmv=$(new_ws haltmove)
bash -c ". '$hf' '$wsmv' > /dev/null 2>&1; ensure_run_surface" > /dev/null 2>&1
_moved="${wsmv}MOVED"
mv "$wsmv" "$_moved"
bash -c ". '$hf' '$_moved' > /dev/null 2>&1; ensure_run_surface" > /dev/null 2>&1
[ "$( . "$RS/lib/state.sh"; state_field "$_moved" run workspace 2>/dev/null)" = "$_moved" ] \
  && ok "a moved workspace re-stamps workspace= at the next launch (the field cannot be stale at a reader's moment)" \
  || bad "workspace field stale after the move: $( . "$RS/lib/state.sh"; state_field "$_moved" run workspace 2>/dev/null) (want $_moved)"

echo "-- startup order: resume gate precedes the pin checks in main --"
mainbody=$(sed -n '/^main() {/,/^}/p' "$RS/ferry.sh")
r=$(printf '%s\n' "$mainbody" | command grep -n 'resume_halt_gate' | head -1 | cut -d: -f1)
p=$(printf '%s\n' "$mainbody" | command grep -n 'check_workflow_pin' | head -1 | cut -d: -f1)
precond "main() calls both resume_halt_gate and check_workflow_pin" \
  test -n "$r" -a -n "$p"
if [ "$r" -lt "$p" ]; then
  ok "resume_halt_gate runs before check_workflow_pin (repin can happen at all)"
else
  bad "check_workflow_pin precedes resume_halt_gate — a workflow_changed halt re-parks before it can ever be resumed"
fi

echo "-- ledger append loss is loud + paged once; the startup gate parks the next launch --"
# Pre-fix, ledger() ended in '|| true': every append onto a corrupt-checksum
# surface vanished (a whole cycle's event ledger, found by accident), while
# whole-surface rewrites kept working so the pipeline LOOKED healthy.
wsl=$(new_ws haltledger)
lcap="$base/ledgerfault.log"
printf '#!/usr/bin/env bash\necho "$1" >> %s\n' "$lcap" > "$base/lfcmd"
chmod +x "$base/lfcmd"
printf 'notify.cmd=%s\nnotify.preset=all\n' "$base/lfcmd" > "$wsl/config/topic.kv"
( . "$RS/lib/state.sh"; state_append "$wsl" ledger ferry "v=1 t=1 event=seed" ) > /dev/null
corrupt_surface "$wsl" ledger
out=$(bash -c ". '$hf' '$wsl' > /dev/null 2>&1; ledger 'event=one'; ledger 'event=two'" 2>&1)
n=$(printf '%s' "$out" | command grep -c "LEDGER APPEND FAILED" || true)
[ "$n" = "2" ] \
  && ok "every lost event is named on stderr (2 appends -> 2 lines; pre-fix: '|| true' swallowed the rc)" \
  || bad "expected 2 loud losses, saw $n: '$(printf '%s' "$out" | head -2 | tr '\n' ' ')'"
[ "$(command grep -c 'park.store_fault' "$lcap" 2>/dev/null)" = "1" ] \
  && ok "exactly ONE store_fault page per ferry process (loud, never a pager storm)" \
  || bad "store_fault pages: $(command grep -c 'park.store_fault' "$lcap" 2>/dev/null || echo 0)"
out=$(bash -c ". '$hf' '$wsl' > /dev/null 2>&1; check_store_integrity" 2>&1); rc=$?
[ $rc -eq 30 ] \
  && ok "startup integrity gate dies store_fault (rc=30) over the corrupt surface" \
  || bad "check_store_integrity rc=$rc, want 30"
printf '%s' "$out" | command grep -q "ledger" \
  && ok "the fault names the surface" || bad "no surface name in: $out"
printf '%s' "$out" | command grep -q "tail -n +2" \
  && ok "and hands over the repair recipe" || bad "no repair recipe in the fault"
rm -f "$wsl/.runtime/state/ledger"
assert_rc 0 "with the corrupt surface removed the gate passes (absent = clean; null control)" -- \
  bash -c ". '$hf' '$wsl' > /dev/null 2>&1; check_store_integrity"
mainbody=$(sed -n '/^main() {/,/^}/p' "$RS/ferry.sh")
ci=$(printf '%s\n' "$mainbody" | command grep -n 'check_store_integrity' | head -1 | cut -d: -f1)
er=$(printf '%s\n' "$mainbody" | command grep -n 'ensure_run_surface' | head -1 | cut -d: -f1)
precond "main() calls check_store_integrity and ensure_run_surface" \
  test -n "$ci" -a -n "$er"
if [ "$ci" -lt "$er" ]; then
  ok "the integrity gate runs before the first store write of the run (wiring trace)"
else
  bad "check_store_integrity does not precede ensure_run_surface in main()"
fi

echo "-- doc closure: every disagreement predicate the ferry can RAISE is named where the pilot reads --"
# `ferry.sh` parks `disagreement` from three sites, each with its own literal
# message prefix; `operations.md` §3 and `cards/pilot.md` are the two documents
# a pilot's route reaches. Both named TWO of the three until 2026-09-08, and the
# count was not the harmful half: the card prescribed reading `## 3. absorption`
# plus the new/repeat split, which argues the OPPOSITE way on a fixpoint park
# whose predicate counts no findings at all — measured, a pilot reported a
# converging loop (3→1 substantive, repeat=0) under a park raised because the
# CUT had frozen. `review-standards.md` §10 had the third right all along; it is
# reviewer-facing and the operator pair never learned of it.
# The PRECOND FLOOR is the load-bearing half, not decoration: a doc-closure
# check whose extractor stops matching reads as clean at exactly the moment it
# has stopped checking anything, which is the failure mode this arm exists to
# prevent in the documents it guards.
pd_prefixes() { # <ferry.sh> -> the literal prefix of each `park disagreement` message
  command grep -oE 'park disagreement "[a-z][a-z -]*:' "$1" \
    | sed 's/^park disagreement "//; s/:$//' | sort -u
}
pd_unnamed() { # <prefix-file> <doc>... -> "prefix -> doc" for every pair the docs miss
  local pf=$1 d pfx; shift
  while IFS= read -r pfx; do
    [ -n "$pfx" ] || continue
    for d in "$@"; do
      command grep -qF "$pfx" "$d" || echo "    '$pfx' is not named in $(basename "$d")"
    done
  done < "$pf"
}
pdf=$(sc_tmpdir)/pd-prefixes.txt
pd_prefixes "$RS/ferry.sh" > "$pdf"
n_pd=$(command grep -c . "$pdf" || true)
precond "the sweep found N>=3 park-disagreement prefixes in ferry.sh (saw ${n_pd:-0}: $(tr '\n' ';' < "$pdf"))" \
  test "${n_pd:-0}" -ge 3
pd_out=$(pd_unnamed "$pdf" "$WF_ROOT/runtime-docs/operations.md" "$WF_ROOT/runtime-docs/cards/pilot.md")
[ -z "$pd_out" ] \
  && ok "every predicate ferry.sh can park on is named in BOTH operator documents" \
  || bad "a predicate the ferry raises is missing from an operator document:"$'\n'"$pd_out"

# red-proof (60-gates' standing rule): the comparison must FIRE on a document
# that names only two of the three — the exact state both docs were in.
pd_fake=$(sc_tmpdir)/twoofthree.md
printf 'the severity-trend predicate, or the review round bound. nothing else.\n' > "$pd_fake"
pd_bad=$(pd_unnamed "$pdf" "$pd_fake")
printf '%s\n' "$pd_bad" | command grep -q 'decomposition fixpoint' \
  && ok "known-bad: a document naming two of the three FIRES, naming the missing predicate" \
  || bad "doc-closure arm vacuous — a two-of-three document read as complete"
# and the extractor itself must not invent members
command grep -qx 'no-such-predicate' <<< "$(cat "$pdf")" \
  && bad "prefix extractor vacuous (matched a fabricated predicate)" \
  || ok "the prefix extractor rejects a fabricated predicate (known-bad fires)"

check_done
