#!/usr/bin/env bash
# 51-record-commit — the impl/fix CLOSE side of session/record.sh: everything
# between a commit landing and the stage that owns it emitting. The commit
# conventions and the acceptance record; the ledger's DERIVED subject and sha;
# the three registration doors (the project's message convention, the
# workflow's own ids, the handed-over axis answered by LOOKUP); the acceptance
# pin against a moved or dirtied worktree; fix-round evidence; the doc-bound
# close, where progress takes a DOC sha and acceptance is a structural SKIP.
#
# Split out of 50-record.sh as a PURE MOVE (the arms below are byte-identical
# to lines 261-683 of that file at the split commit; only this preamble is
# new). The reason is two caps pointing at one fact: 50-record ran 44-45s
# against maintenance.check_cap=30 and sat at 994 lines against
# cap.selftest_file=1000, and the tree's precedent for both is SPLIT rather
# than shave -- 52-vocab.sh and 62-gates-commit.sh are the same move, each
# following a subject boundary that already existed. This one is that
# boundary: 50-record keeps the EMIT door (verdicts, owed sets, nonces, roles,
# structure/claims gates, halt, split --slices, the stop gate) and this file
# takes the COMMIT door. The block was self-contained already -- it never
# touched 50-record's own workspace, and nothing after it depended on the repo
# state it leaves -- which is why the move needed no edits to the arms.
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/fixtures/lib.sh"
. "$RS/lib/state.sh"
RECORD="$RS/session/record.sh"

base=$(sc_tmpdir)
read -r repo branch < <(mk_repo "$base/repo")

echo "-- impl emit: commit conventions + acceptance record are load-bearing --"
wsg=$(mk_ws "$base" gatestopic "$repo" "$branch")
mk_spec "$wsg" 01 1
mk_artifact "$wsg/slices/01/conformance.md" conformance
mk_dispatch "$wsg" 01
( cd "$repo" && echo i1 > i1.txt && git add i1.txt && git commit -qm "feat: landed unit one" )
sha_ok=$(git -C "$repo" rev-parse HEAD)
activate_stage "$wsg" impl 01 1 nI1
assert_rc 0 "progress records the landed cu (active impl stage)" -- \
  "$RECORD" progress "$wsg" --cu 1 --sha "$sha_ok"
( . "$RS/lib/state.sh"; state_get "$wsg" progress | command grep "cu=1" \
    | command grep -q "stage=impl" ) \
  && ok "progress record carries its stage stamp (fix-round evidence is distinguishable)" \
  || bad "progress record has no stage stamp: $( . "$RS/lib/state.sh"; state_get "$wsg" progress | tail -1)"

echo "-- the ledger's subject and sha are DERIVED, never argued (single source: git) --"
# Measured on one topic: six of seven rows carried a subject and slice 03's cu-1
# carried the empty string, under a prompt byte-identical to the six; and the same
# seven rows carried the sha in TWO forms (40-char and 8-char) from three sessions.
# Both fields are the class where the writer already holds the authoritative value,
# so the writer takes it — an optional argument is a second source for a fact git
# already answers, which is what review-standards §2's single-source rule forbids.
prow=$( . "$RS/lib/state.sh"; state_get "$wsg" progress | command grep "cu=1" | tail -1)
printf '%s' "$prow" | command grep -q "subject=feat: landed unit one" \
  && ok "subject is derived from the commit (no --subject was passed)" \
  || bad "subject not derived from git: $prow"
printf '%s' "$prow" | command grep -qE "(^| )sha=[0-9a-f]{40}( |$)" \
  && ok "sha is normalised to the 40-char form the verify resolved" \
  || bad "sha is not canonical in the row: $prow"
# a SHORT sha in, the canonical form out — the form must not be the author's choice
( cd "$repo" && echo i1b >> i1.txt && git add i1.txt && git commit -qm "feat: landed unit one again" )
sha_short=$(git -C "$repo" rev-parse --short=8 HEAD)
out_re=$("$RECORD" progress "$wsg" --cu 1 --sha "$sha_short" 2>&1); rc_re=$?
( . "$RS/lib/state.sh"; state_get "$wsg" progress | tail -1 ) \
  | command grep -qE "(^| )sha=[0-9a-f]{40}( |$)" \
  && ok "a short sha argument is stored in the canonical form (one shape per surface)" \
  || bad "short sha stored verbatim: $( . "$RS/lib/state.sh"; state_get "$wsg" progress | tail -1)"
# Append-only is never-destroy-history, not write-once per key: the second
# registration of cu 1 at a new sha SUPERSEDES the first, and the row says so —
# the earlier reader had to reconcile the orphan against git by hand.
[ "$rc_re" -eq 0 ] && ( . "$RS/lib/state.sh"; state_get "$wsg" progress | tail -1 ) \
  | command grep -qE "(^| )supersedes=$sha_ok( |$)" \
  && ok "re-registering cu 1 at a new sha marks the row supersedes=<the earlier sha>" \
  || bad "the re-registration carries no supersedes= naming the earlier sha (rc=$rc_re): $( . "$RS/lib/state.sh"; state_get "$wsg" progress | tail -1)"
printf '%s' "$out_re" | command grep -q "SUPERSEDES" \
  && ok "…and the confirmation says which registration it retired" \
  || bad "the confirmation is silent about the supersede: $out_re"
printf '%s\n' "$prow" | command grep -qE "(^| )supersedes=( |$)" \
  && ok "a FIRST registration carries supersedes= empty — present on every row, so absent and not-applicable never look alike" \
  || bad "the first registration lacks the (empty) supersedes field: $prow"
assert_rc 2 "re-registering cu 1 at the SAME sha refuses (a duplicate row is not a landing)" -- \
  "$RECORD" progress "$wsg" --cu 1 --sha "$sha_short"
assert_out_has "already registered" "the refusal names the duplicate and the way to replace a unit"
# known-bad: the second source is refused, and the refusal says why
out=$("$RECORD" progress "$wsg" --cu 1 --sha "$sha_ok" --subject "a hand-written label" 2>&1); rc=$?
[ $rc -ne 0 ] && printf '%s' "$out" | command grep -q "DERIVED from the sha" \
  && ok "known-bad: --subject is refused, and the refusal names git as the single source" \
  || bad "--subject accepted or refused without a reason (rc=$rc): $out"
echo "-- registration is the FIRST door for the whole MESSAGE convention --"
# The project's own axes were asked at emit only, where every failing message is
# already buried under the units landed since — measured: one topic's subject
# convention was caught at close-out and paid for with a hand rewrite of the
# branch. The registration door is the same derivation asked while the commit is
# still the tip. What may NOT move here is the diff cap: its remedy is a
# re-split, so a wall would strand the ledger record of a commit that landed.
( cd "$repo" && echo sr > subjreg.txt && git add -A && git commit -qm "Added stuff badly" )
sha_badsubj=$(git -C "$repo" rev-parse HEAD)
assert_rc 2 "progress REFUSES a subject that fails the project regex" -- \
  "$RECORD" progress "$wsg" --cu 1 --sha "$sha_badsubj"
assert_out_has "fails project regex" "the refusal names the project's own rule, quoted"
assert_out_has "IS the tip" "and the fix is the cheap one, because registration is where it still is the tip"
echo "commit.forbid_trailers=Co-Authored-By" >> "$wsg/project.kv"
( cd "$repo" && echo ft > forbtrail.txt && git add -A \
  && git commit -qm "feat: land a unit with a banned trailer" \
       -m "Co-Authored-By: Someone <x@y.invalid>" )
assert_rc 2 "progress REFUSES a trailer the project forbids (same derivation as emit)" -- \
  "$RECORD" progress "$wsg" --cu 1 --sha "$(git -C "$repo" rev-parse HEAD)"
assert_out_has "forbidden trailer" "the prohibition and its source key are named"
sed -i '/^commit.forbid_trailers=/d' "$wsg/project.kv"
# A tab inside a failure's text is not exotic — git subjects may hold one, and
# the transport between the derivation and this refusal IS tab-delimited. Split
# on more than the first tab and the reader loses the tail of the sentence: here,
# the regex it was refused against.
( cd "$repo" && echo tb > tabsubj.txt && git add -A \
  && git commit -qm "$(printf 'Added\tstuff badly')" )
assert_rc 2 "a subject carrying a TAB is refused like any other" -- \
  "$RECORD" progress "$wsg" --cu 1 --sha "$(git -C "$repo" rev-parse HEAD)"
assert_out_has "fails project regex" "and the refusal keeps everything past the tab (split on the FIRST one only)"
( cd "$repo" && seq 1 600 | sed 's/^/line /' > oversize.txt && git add -A \
  && git commit -qm "feat: land an oversize but well-named unit" )
assert_rc 0 "a commit OVER the diff cap still registers — the ledger records what landed; the cap is the emit gate's" -- \
  "$RECORD" progress "$wsg" --cu 1 --sha "$(git -C "$repo" rev-parse HEAD)"

echo "-- registration is the FIRST door for the workflow's own ids --"
# Same rule the emit-time commit gate closes, asked where it costs one amend
# instead of one per landed unit. The measured leak went the other way: the ids
# reached the repo's permanent history, where they resolve to nothing.
( cd "$repo" && echo wid > wid.txt && git add wid.txt \
  && git commit -qm "feat: land the unit for cu-3" )
sha_wid=$(git -C "$repo" rev-parse HEAD)
assert_rc 2 "progress REFUSES a commit whose message names a workflow id" -- \
  "$RECORD" progress "$wsg" --cu 1 --sha "$sha_wid"
assert_out_has "resolve only in this topic's own planning and workspace artifacts" \
  "the refusal names the class"
assert_out_has "IS the tip" "and the fix path it prints is computed from the commit's position — here the tip, so one amend"
( . "$RS/lib/state.sh"; command grep -q "sha=$sha_wid" <<< "$(state_get "$wsg" progress)" ) \
  && bad "the refused commit was registered anyway (the refusal must precede the append)" \
  || ok "nothing was appended for the refused commit (refuse-before-write)"
( cd "$repo" && git -C "$repo" commit -q --amend -m "feat: land the third unit" )
assert_rc 0 "after the amend the new sha registers (the door is passable, not a dead end)" -- \
  "$RECORD" progress "$wsg" --cu 1 --sha "$(git -C "$repo" rev-parse HEAD)"
# Registering late is what buries the commit — and past the tip the door stops
# being a wall. A door may block only what the session can fix ON THE SPOT
# (config-and-adapters §3, the same rule that keeps the diff cap at emit): a
# wall here strands the ledger record of a commit that really did land, and an
# author who cannot pass it simply does not register, after which emit reports a
# MISSING cu record and hides the real cause. Recorded, named loudly, and the
# emit gate still refuses the stage.
( cd "$repo" && echo wid2 > wid2.txt && git add -A \
  && git commit -qm "feat: land the unit for DP-4" )
sha_wid2=$(git -C "$repo" rev-parse HEAD)
( cd "$repo" && echo later > later.txt && git add -A && git commit -qm "feat: land a later unit" )
assert_rc 0 "a BURIED message failure is RECORDED, not walled (the ledger's job is what LANDED)" -- \
  "$RECORD" progress "$wsg" --cu 1 --sha "$sha_wid2"
assert_out_has "WARNING" "it is named loudly rather than passing in silence"
assert_out_has "BELOW the tip" "with the position-true fix path — a branch rewrite, never an amend of someone else's commit"
( . "$RS/lib/state.sh"; state_get "$wsg" progress | command grep -q "sha=$sha_wid2" ) \
  && ok "the record really landed (a wall would have lost what the repo already carries)" \
  || bad "the buried commit was warned about but never recorded — the ledger lost a landed unit"
( . "$RS/lib/state.sh"; state_get "$wsg" audit | command grep -q "recorded over a message-convention failure" ) \
  && ok "and the ferry can see it: the audit surface carries the override" \
  || bad "no audit line for a warned registration — the operator has no way to learn of it"
# The tip arm is untouched by the split: still a wall, because there the fix IS local.
( cd "$repo" && echo wid3 > wid3.txt && git add -A \
  && git commit -qm "feat: land the unit for cu-7" )
assert_rc 2 "the TIP arm still refuses (one amend clears it, so the wall is legitimate there)" -- \
  "$RECORD" progress "$wsg" --cu 1 --sha "$(git -C "$repo" rev-parse HEAD)"
assert_out_has "IS the tip" "and says so"
# Leave the ledger's last word for cu.1 conformant: the warned record above is
# deliberately still in the surface, and the emit assertions further down gate
# the LAST record per cu — this is the fixture keeping its own premise honest.
( cd "$repo" && git -C "$repo" commit -q --amend -m "feat: land the clean unit" )
assert_rc 0 "the amended message registers (the door is passable at the tip, as before)" -- \
  "$RECORD" progress "$wsg" --cu 1 --sha "$(git -C "$repo" rev-parse HEAD)"

echo "-- registration asks the HANDED-OVER axis too, and answers it by LOOKUP --"
# `_gates_message_fails` merges both id axes before returning, so the emit gate
# and this door necessarily agree — but nothing here DROVE the second axis: the
# only anchor-shaped token in this check was `DP-4`, which the minted-id pattern
# catches on its own. So the door that matters most for this axis — the author
# has just been reading the plan that mints these ids, and here the commit is
# still the tip — had no fixture at all. Two assertions, one message, two plans:
# that difference IS the mechanism, and it is what keeps a later hand from
# degrading the lookup into a shape blocklist without going red.
( cd "$repo" && echo hov > handedover.txt && git add -A \
  && git commit -qm "refactor: rename the source per W-22" )
sha_hov=$(git -C "$repo" rev-parse HEAD)
printf '# fixture plan\nwork item W-22 renames the source to AssemblyRole.\n' > "$wsg/../plan.md"
precond "the topic's plan really names the token (else the lookup below is vacuous)" \
  bash -c 'command grep -qwF -- "W-22" "$1/../plan.md"' _ "$wsg"
assert_rc 2 "progress REFUSES an id the PLAN handed over — the workflow never minted it, and the repo still cannot resolve it" -- \
  "$RECORD" progress "$wsg" --cu 1 --sha "$sha_hov"
assert_out_has "W-22" "the refusal names the token it found"
assert_out_has "resolve only in this topic's own planning and workspace artifacts" \
  "and names a class that is true for THIS axis (the merged sentence must cover both)"
assert_out_has "IS the tip" "with the cheap fix path — which is the whole reason this axis is asked HERE and not only at emit"
( . "$RS/lib/state.sh"; command grep -q "sha=$sha_hov" <<< "$(state_get "$wsg" progress)" ) \
  && bad "the refused handed-over commit was registered anyway (refuse-before-write)" \
  || ok "nothing was appended for it either (the two axes share the door, not just the derivation)"
printf '# fixture plan\none slice of mock work.\n' > "$wsg/../plan.md"
assert_rc 0 "the SAME commit registers once the plan no longer names it — shape alone never decides" -- \
  "$RECORD" progress "$wsg" --cu 1 --sha "$sha_hov"

# The override's audit line is the DURABLE claim, so it may not precede the write
# it describes: a faulted append would leave the one artifact nobody can correct
# later asserting a record that never landed. Own workspace — this fixture
# corrupts a surface on purpose.
wsau=$(mk_ws "$base" auditorder "$repo" "$branch")
mk_spec "$wsau" 01 1
activate_stage "$wsau" impl 01 1 nAU
( cd "$repo" && echo au1 > au1.txt && git add -A \
  && git commit -qm "feat: land a clean unit that creates the surface" )
"$RECORD" progress "$wsau" --cu 1 --sha "$(git -C "$repo" rev-parse HEAD)" > /dev/null 2>&1
( cd "$repo" && echo au2 > au2.txt && git add -A \
  && git commit -qm "feat: land the unit for cu-11" )
sha_au=$(git -C "$repo" rev-parse HEAD)
( cd "$repo" && echo au3 > au3.txt && git add -A && git commit -qm "feat: land one more later unit" )
corrupt_surface "$wsau" progress
precond "the progress surface is really tampered (else the fault below is vacuous)" \
  bash -c 'command grep -q TAMPERED-BY-SELF-CHECK "$1/.runtime/state/progress"' _ "$wsau"
assert_rc 3 "a buried-failure registration whose append FAULTS exits 3 (store fault, never a silent pass)" -- \
  "$RECORD" progress "$wsau" --cu 1 --sha "$sha_au"
( . "$RS/lib/state.sh"
  command grep -q "recorded over a message-convention failure" \
    <<< "$(state_get "$wsau" audit 2>/dev/null)" ) \
  && bad "the audit surface claims an override whose record never landed — the durable claim ran ahead of the write" \
  || ok "no durable override claim when the append faulted (the audit line follows the write, the stderr warning does not)"

echo "acceptance=false" >> "$wsg/project.kv"
assert_rc 2 "impl emit refuses while no acceptance gate record exists for the current tree" -- \
  "$RECORD" emit "$wsg" --stage impl --nonce nI1 --verdict built --confidence HIGH \
  --refine-rounds 1
assert_out_has "acceptance" "refusal names the missing acceptance evidence"
( . "$RS/lib/gates.sh"; gates_project "$wsg" acceptance ) > /dev/null 2>&1
assert_rc 2 "a FAILED acceptance record still refuses (red gate never emitted over)" -- \
  "$RECORD" emit "$wsg" --stage impl --nonce nI1 --verdict built --confidence HIGH \
  --refine-rounds 1
sed -i 's/^acceptance=false/acceptance=true/' "$wsg/project.kv"
( . "$RS/lib/gates.sh"; gates_project "$wsg" acceptance ) > /dev/null 2>&1
assert_rc 0 "with a PASS acceptance record pinned to the current tree, impl emits" -- \
  "$RECORD" emit "$wsg" --stage impl --nonce nI1 --verdict built --confidence HIGH \
  --refine-rounds 1
( . "$RS/lib/state.sh"; state_get "$wsg" gates | command grep -q "gate=commit .*result=PASS" ) \
  && ok "the landed cu's commit gate was run and attested at emit" \
  || bad "no commit-gate attestation for the landed cu"
# Undeclared project gates record a NAMED SKIP at emit (build/lint/test here),
# and the spec's own claims table is re-resolved at the landed tip and recorded
# under its own gate name — never refused (a trial).
( . "$RS/lib/state.sh"; state_get "$wsg" gates | command grep -qE 'gate=build .*result=SKIP .*not-declared' ) \
  && ok "an undeclared project gate (build) records a named SKIP at emit rather than nothing" \
  || bad "no SKIP row for the undeclared build gate: $( . "$RS/lib/state.sh"; state_get "$wsg" gates | command grep 'gate=build' | tail -1)"
( . "$RS/lib/state.sh"; state_get "$wsg" gates | command grep -qE 'gate=spec_claims_tip .*result=PASS .*skipped=0' ) \
  && ok "the spec's claims table was re-resolved at the landed tip and recorded as spec_claims_tip (PASS, skipped=0)" \
  || bad "no spec_claims_tip row after the impl emit: $( . "$RS/lib/state.sh"; state_get "$wsg" gates | command grep 'spec_claims_tip' | tail -1)"

echo "-- impl emit: a stale acceptance record (tree moved) refuses; EVERY declared project gate is pinned, not acceptance alone --"
# The measured hole: a slice shipped with zero build/lint/test rows while its
# siblings held three, and the emit — which pinned acceptance only — let it
# through. Declaring build and lint here makes
# the refusal name all three missing gates; running two leaves one named.
( cd "$repo" && echo i2 > i2.txt && git add i2.txt && git commit -qm "feat: landed unit two" )
sha2=$(git -C "$repo" rev-parse HEAD)
activate_stage "$wsg" fix 01 1 nI2
"$RECORD" progress "$wsg" --cu 1 --sha "$sha2" > /dev/null 2>&1
printf 'build=true\nlint=true\n' >> "$wsg/project.kv"
assert_rc 2 "fix emit refuses: the acceptance record predates the new commit (tree pin mismatch) and build/lint were never run" -- \
  "$RECORD" emit "$wsg" --stage fix --nonce nI2 --verdict built --confidence HIGH \
  --refine-rounds 1
assert_out_has " build lint acceptance" "the refusal names EVERY declared gate lacking a current PASS, in one line"
assert_out_has "project $wsg build" "…and prints the invocation for each (build)"
( . "$RS/lib/gates.sh"; gates_project "$wsg" build; gates_project "$wsg" lint ) > /dev/null 2>&1
assert_rc 2 "with build+lint run and acceptance still stale, the emit still refuses" -- \
  "$RECORD" emit "$wsg" --stage fix --nonce nI2 --verdict built --confidence HIGH \
  --refine-rounds 1
assert_out_has "state (sha=" "…naming the pinned state"
mlist=$("$RECORD" emit "$wsg" --stage fix --nonce nI2 --verdict built --confidence HIGH --refine-rounds 1 2>&1 \
  | awk '/no PASS record/{sub(/.*\): /, ""); print $1, $2; exit}')
[ "$mlist" = "acceptance —" ] \
  && ok "…and only acceptance is still named (the satisfied gates dropped out of the list)" \
  || bad "the missing-gate list is wrong after build+lint ran: '$mlist'"
( . "$RS/lib/gates.sh"; gates_project "$wsg" acceptance ) > /dev/null 2>&1
assert_rc 0 "re-run at the new tip -> fix emits" -- \
  "$RECORD" emit "$wsg" --stage fix --nonce nI2 --verdict built --confidence HIGH \
  --refine-rounds 1
# The arms below reuse this workspace and re-run acceptance alone before each
# emit; with build/lint still declared their pins would go stale on every new
# commit and the arms would read the wrong door. Back to the original set.
sed -i '/^build=true$/d; /^lint=true$/d' "$wsg/project.kv"

echo "-- the emit-time commit gate covers the LEDGER's units, not just the spec's --"
# The fix-stage escape, anchored twice (slice 01 postcheck.2, slice 12
# postcheck.2): the loop iterated owed_spec_cus — the SPEC's commit-unit list —
# while a fix round registers units the spec never listed. Slice 01's cu-5
# (d59fd3db, registered 53s before the emit) and slice 12's cu-3 (27129d5c,
# registered two minutes before) were both in the ledger at gate time and
# neither got a per-commit attestation; seven gates rows mentioned the first
# sha, none as a commit-gate subject. Covered only incidentally both times, by
# the no-arg acceptance run whose HEAD~1..HEAD range happened to equal the fix
# commit at the tip — which is luck, not a gate.
( cd "$repo" && echo lx > ledgeronly.txt && git add ledgeronly.txt \
  && git commit -qm "feat: land a fix-round unit the spec never listed" )
shalo=$(git -C "$repo" rev-parse HEAD)
precond "cu-9 is NOT in the slice's spec table (else this proves nothing)" \
  bash -c '! command grep -q "| cu-9 |" "$1/slices/01/spec.md"' _ "$wsg"
activate_stage "$wsg" fix 01 2 nLO
assert_rc 0 "a fix round registers a unit id the spec's table does not carry" -- \
  "$RECORD" progress "$wsg" --cu 9 --sha "$shalo"
( . "$RS/lib/gates.sh"; gates_project "$wsg" acceptance ) > /dev/null 2>&1
assert_rc 0 "the fix round emits" -- \
  "$RECORD" emit "$wsg" --stage fix --nonce nLO --verdict built --confidence HIGH \
  --refine-rounds 1
# The SUBJECT of the gate, not the row's HEAD stamp: _gates_record stamps
# sha=<HEAD> on every row it writes, and this unit IS the tip — grepping the
# bare sha would pass on the pre-fix tree by matching that stamp. The gate's
# own subject rides in detail=sha=<sha>.
( . "$RS/lib/state.sh"; state_get "$wsg" gates \
    | command grep 'gate=commit' | command grep -q "detail=sha=$shalo " ) \
  && ok "the ledger-only unit is the SUBJECT of its own commit-gate row (detail=sha=$shalo)" \
  || bad "no commit-gate row has $shalo as its subject — a fix-stage unit still escapes the per-commit attestation impl units get; rows: $( . "$RS/lib/state.sh"; state_get "$wsg" gates | command grep 'gate=commit' | command grep -o 'detail=sha=[0-9a-f]*' | tr '\n' ' ')"

echo "-- impl emit: acceptance PASS does not survive a DIRTIED worktree --"
( cd "$repo" && echo i3 > i3.txt && git add i3.txt && git commit -qm "feat: landed unit three" )
sha3=$(git -C "$repo" rev-parse HEAD)
activate_stage "$wsg" impl 01 2 nI2b
"$RECORD" progress "$wsg" --cu 1 --sha "$sha3" > /dev/null 2>&1
( . "$RS/lib/gates.sh"; gates_project "$wsg" acceptance ) > /dev/null 2>&1
echo tampered >> "$repo/i3.txt"
precond "the tracked worktree is dirty and HEAD^{tree} is unchanged by the dirt" \
  bash -c '[ -n "$(git -C "$1" status --porcelain)" ]' _ "$repo"
assert_rc 2 "impl emit refuses: the worktree moved since the acceptance PASS (HEAD tree alone cannot see uncommitted edits)" -- \
  "$RECORD" emit "$wsg" --stage impl --nonce nI2b --verdict built --confidence HIGH \
  --refine-rounds 1
git -C "$repo" checkout -q i3.txt
assert_rc 0 "with the worktree back at the recorded state, the same PASS emits" -- \
  "$RECORD" emit "$wsg" --stage impl --nonce nI2b --verdict built --confidence HIGH \
  --refine-rounds 1

echo "-- acceptance pin binds dirty CONTENT, not just dirty paths --"
( cd "$repo" && echo i4 > i4.txt && git add i4.txt && git commit -qm "feat: landed unit four" )
sha4=$(git -C "$repo" rev-parse HEAD)
activate_stage "$wsg" impl 01 3 nI2c
"$RECORD" progress "$wsg" --cu 1 --sha "$sha4" > /dev/null 2>&1
echo dirty-A > "$repo/i4.txt"
( . "$RS/lib/gates.sh"; gates_project "$wsg" acceptance ) > /dev/null 2>&1
echo dirty-B-different-bytes > "$repo/i4.txt"
precond "porcelain is IDENTICAL for the two dirty contents (paths cannot see the swap)" \
  bash -c '[ "$(git -C "$1" status --porcelain)" = " M i4.txt" ]' _ "$repo"
assert_rc 2 "impl emit refuses: the dirty CONTENT changed since the acceptance PASS (a path-only fingerprint reused the stale PASS)" -- \
  "$RECORD" emit "$wsg" --stage impl --nonce nI2c --verdict built --confidence HIGH \
  --refine-rounds 1
echo dirty-A > "$repo/i4.txt"
assert_rc 0 "with the exact dirty content back, the recorded state matches and the PASS emits" -- \
  "$RECORD" emit "$wsg" --stage impl --nonce nI2c --verdict built --confidence HIGH \
  --refine-rounds 1
git -C "$repo" checkout -q i4.txt

echo "-- impl emit: a cu whose commit breaks the project convention refuses --"
wsb=$(mk_ws "$base" badcommit "$repo" "$branch")
mk_spec "$wsb" 01 1
mk_artifact "$wsb/slices/01/conformance.md" conformance
mk_dispatch "$wsb" 01
( cd "$repo" && echo b1 > b1.txt && git add b1.txt \
  && git commit -qm "feat: land a unit under the convention of the day" )
sha_bad=$(git -C "$repo" rev-parse HEAD)
activate_stage "$wsb" impl 01 1 nI3
"$RECORD" progress "$wsb" --cu 1 --sha "$sha_bad" > /dev/null 2>&1
precond "the unit really reached the ledger (registration accepted it under the convention then declared)" \
  bash -c '. "$1/lib/state.sh"; state_get "$2" progress | command grep -q "sha=$3"' _ "$RS" "$wsb" "$sha_bad"
# Registration is a wall, not an authority: the emit gate re-derives from the
# project's CURRENT declaration, so a convention tightened after the unit landed
# still refuses. (Before the message half moved to the registration door, this
# fixture landed a subject that was non-conforming from the start — which that
# door now stops, so the case had to be built the way it really occurs.)
sed -i '/^commit.subject_regex=/d' "$wsb/project.kv"
printf 'commit.subject_regex=^(feat|fix)\\([a-z]+\\): [a-z]\n' >> "$wsb/project.kv"
assert_rc 2 "impl emit refuses on a landed subject the CURRENT convention rejects (registration is not the authority)" -- \
  "$RECORD" emit "$wsb" --stage impl --nonce nI3 --verdict built --confidence HIGH \
  --refine-rounds 1
assert_out_has "regex" "refusal points at the project convention"

echo "-- fix emit demands fix-round evidence: new commits OR a changed conformance --"
wsf=$(mk_ws "$base" fixevidence "$repo" "$branch")
mk_spec "$wsf" 01 1
mk_artifact "$wsf/slices/01/conformance.md" conformance
( cd "$repo" && echo f1 > f1.txt && git add f1.txt && git commit -qm "feat: fix evidence base" )
shaf=$(git -C "$repo" rev-parse HEAD)
activate_stage "$wsf" impl 01 1 nF0
"$RECORD" progress "$wsf" --cu 1 --sha "$shaf" > /dev/null 2>&1
cbf=$(md5sum "$wsf/slices/01/conformance.md" | awk '{print $1}')
activate_stage "$wsf" fix 01 1 nF1
( . "$RS/lib/state.sh"; state_put "$wsf" stage ferry "conformance_baseline=$cbf" ) > /dev/null
assert_rc 2 "fix emit refuses with no fix-round commits and an UNCHANGED conformance (zero-action fix cannot report built)" -- \
  "$RECORD" emit "$wsf" --stage fix --nonce nF1 --verdict built --confidence HIGH \
  --refine-rounds 1
assert_out_has "fix-round" "refusal names the missing fix-round evidence"
echo "rebuttal: finding 1 dispositioned with evidence" >> "$wsf/slices/01/conformance.md"
assert_rc 0 "a CHANGED conformance is fix-round evidence (a doc-only fix is legal, but visible)" -- \
  "$RECORD" emit "$wsf" --stage fix --nonce nF1 --verdict built --confidence HIGH \
  --refine-rounds 1
( cd "$repo" && echo f2 > f2.txt && git add f2.txt && git commit -qm "feat: fix round two lands" )
shaf2=$(git -C "$repo" rev-parse HEAD)
cbf2=$(md5sum "$wsf/slices/01/conformance.md" | awk '{print $1}')
activate_stage "$wsf" fix 01 2 nF2
( . "$RS/lib/state.sh"; state_put "$wsf" stage ferry "conformance_baseline=$cbf2" ) > /dev/null
"$RECORD" progress "$wsf" --cu 1 --sha "$shaf2" > /dev/null 2>&1
assert_rc 0 "a fix-round progress record is evidence (conformance untouched)" -- \
  "$RECORD" emit "$wsf" --stage fix --nonce nF2 --verdict built --confidence HIGH \
  --refine-rounds 1

echo "-- fix evidence: a PRE-EXISTING commit re-registered in the fix round is not evidence --"
cbf3=$(md5sum "$wsf/slices/01/conformance.md" | awk '{print $1}')
fhb3=$(git -C "$repo" rev-parse HEAD)
activate_stage "$wsf" fix 01 3 nF3
( . "$RS/lib/state.sh"
  state_put "$wsf" stage ferry "conformance_baseline=$cbf3" "fix_head_baseline=$fhb3" ) > /dev/null
"$RECORD" progress "$wsf" --cu 1 --sha "$shaf2" > /dev/null 2>&1
assert_rc 2 "re-registering a commit already contained in the fix-entry HEAD refuses (a zero-action fix cannot report built)" -- \
  "$RECORD" emit "$wsf" --stage fix --nonce nF3 --verdict built --confidence HIGH \
  --refine-rounds 1
( cd "$repo" && echo f3 > f3.txt && git add f3.txt && git commit -qm "feat: fix round three lands" )
shaf3=$(git -C "$repo" rev-parse HEAD)
"$RECORD" progress "$wsf" --cu 1 --sha "$shaf3" > /dev/null 2>&1
( . "$RS/lib/gates.sh"; gates_project "$wsf" acceptance ) > /dev/null 2>&1
assert_rc 0 "a commit NEW since fix entry is evidence" -- \
  "$RECORD" emit "$wsf" --stage fix --nonce nF3 --verdict built --confidence HIGH \
  --refine-rounds 1

echo "-- doc-bound impl close: progress takes a DOC sha, acceptance is a structural SKIP --"
read -r drepo dbranch < <(mk_doc_repo "$base/docrepo")
wsd=$(mk_ws "$base" recdoc "$repo" "$branch")
# acceptance=false: if the code gate were ever run for this slice it would FAIL
# and block the emit — the emit succeeding IS the proof it was never run.
printf 'doc.repo=%s\ndoc.branch=%s\nacceptance=false\n' "$drepo" "$dbranch" >> "$wsd/project.kv"
( . "$RS/lib/state.sh"
  printf 'id=02 status=active risk=low repo=doc title=d rederive=0\n' | state_set "$wsd" slices ferry ) > /dev/null
mk_spec "$wsd" 02 1
mk_artifact "$wsd/slices/02/conformance.md" conformance
mk_dispatch "$wsd" 02
( cd "$drepo" && echo dd > dd.md && git add dd.md && git commit -qm "docs: land the shipped note" )
dsha=$(git -C "$drepo" rev-parse HEAD)
activate_stage "$wsd" impl 02 1 nDR
assert_rc 0 "progress accepts a SHA that lives only in the doc repo (the registration wall follows the binding)" -- \
  "$RECORD" progress "$wsd" --cu 1 --sha "$dsha"
assert_rc 0 "the doc-bound impl emits with NO acceptance PASS pin (doc repo has no acceptance concept)" -- \
  "$RECORD" emit "$wsd" --stage impl --nonce nDR --verdict built --confidence HIGH \
  --refine-rounds 1
( . "$RS/lib/state.sh"; state_get "$wsd" gates | command grep 'gate=acceptance' | tail -1 \
    | command grep -q 'result=SKIP' ) \
  && ok "the close attested a structural acceptance SKIP (named, never silent)" \
  || bad "no acceptance SKIP record at the doc close: $( . "$RS/lib/state.sh"; state_get "$wsd" gates | tail -1)"
( . "$RS/lib/state.sh"; state_get "$wsd" gates | command grep -q "gate=commit .*result=PASS" ) \
  && ok "the doc cu's commit gate still ran (one commit convention for both checkouts)" \
  || bad "no commit-gate attestation for the doc cu"
echo "-- a doc-bound FIX round measures its evidence against the DOC checkout --"
# The fix baseline is the slice's own repo HEAD. Against the code repo, no doc
# commit could ever be an ancestor of it, so every re-registered doc commit
# would read as fresh work and a zero-action doc fix could report built — the
# exact hole the fix-evidence rule exists to close.
cbd=$(md5sum "$wsd/slices/02/conformance.md" | awk '{print $1}')
fhbd=$(git -C "$drepo" rev-parse HEAD)
activate_stage "$wsd" fix 02 1 nDF
( . "$RS/lib/state.sh"
  state_put "$wsd" stage ferry "conformance_baseline=$cbd" "fix_head_baseline=$fhbd" ) > /dev/null
"$RECORD" progress "$wsd" --cu 1 --sha "$dsha" > /dev/null 2>&1
assert_rc 2 "re-registering a doc commit already contained in the doc fix-entry HEAD refuses" -- \
  "$RECORD" emit "$wsd" --stage fix --nonce nDF --verdict built --confidence HIGH \
  --refine-rounds 1
assert_out_has "fix-round" "the refusal names the missing fix-round evidence"
( cd "$drepo" && echo d2 > d2.md && git add d2.md && git commit -qm "docs: revise the shipped note" )
"$RECORD" progress "$wsd" --cu 1 --sha "$(git -C "$drepo" rev-parse HEAD)" > /dev/null 2>&1
assert_rc 0 "a doc commit NEW since fix entry IS evidence (good direction)" -- \
  "$RECORD" emit "$wsd" --stage fix --nonce nDF --verdict built --confidence HIGH \
  --refine-rounds 1

# The rule above only holds if the value STAMPED at fix entry came from the doc
# checkout. No drill row runs a fix stage at all, so this is the pin for the
# ferry's own stamping.
hfd=$(mk_headless_ferry)
( set +u; . "$hfd" "$wsd" > /dev/null 2>&1; enter_stage 02 fix ) > /dev/null 2>&1
[ "$( . "$RS/lib/state.sh"; state_field "$wsd" stage fix_head_baseline 2>/dev/null)" \
  = "$(git -C "$drepo" rev-parse HEAD)" ] \
  && ok "enter_stage stamps the fix baseline from the slice's OWN checkout (doc HEAD)" \
  || bad "fix baseline stamped '$( . "$RS/lib/state.sh"; state_field "$wsd" stage fix_head_baseline 2>/dev/null)', want doc HEAD $(git -C "$drepo" rev-parse HEAD)"

echo "-- and a CODE-bound slice in the same topic still owes its acceptance pin --"
( . "$RS/lib/state.sh"
  printf 'id=02 status=active risk=low repo=doc title=d rederive=0\nid=03 status=active risk=low repo=code title=c rederive=0\n' \
    | state_set "$wsd" slices ferry ) > /dev/null
mk_spec "$wsd" 03 1
mk_artifact "$wsd/slices/03/conformance.md" conformance
mk_dispatch "$wsd" 03
( cd "$repo" && echo cc > cc.txt && git add cc.txt && git commit -qm "feat: land the code unit" )
activate_stage "$wsd" impl 03 1 nCR
"$RECORD" progress "$wsd" --cu 1 --sha "$(git -C "$repo" rev-parse HEAD)" > /dev/null 2>&1
assert_rc 2 "the code-bound slice still refuses without a current acceptance PASS (D-i is per-slice, not per-topic)" -- \
  "$RECORD" emit "$wsd" --stage impl --nonce nCR --verdict built --confidence HIGH \
  --refine-rounds 1
assert_out_has "acceptance" "the refusal still names the acceptance evidence"

echo "-- progress outside impl/fix refuses --"
activate_stage "$wsb" spec 01 1 nI4
assert_rc 2 "progress during a non-impl stage refuses (the ledger is impl/fix evidence)" -- \
  "$RECORD" progress "$wsb" --cu 1 --sha "$sha_bad"


check_done
