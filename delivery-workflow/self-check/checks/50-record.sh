#!/usr/bin/env bash
# 50-record — session/record.sh + the ferry's record-side seams: the emit
# refusal chain (missing owed -> refuse; success; nonce reuse -> refuse), the
# Stop gate (exit 2 before a record, 0 after), role fields owed per stages.tsv
# role, the --halt path (class_u/blocked bypass owed, --detail required, ferry
# routes HALT_* from ANY stage), split --slices validation, and the
# ruling-gated resume: a ruling-gated halt re-enters the suspended stage
# instead of re-parking.
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/fixtures/lib.sh"
. "$RS/lib/state.sh"
RECORD="$RS/session/record.sh"

base=$(sc_tmpdir)
read -r repo branch < <(mk_repo "$base/repo")
ws=$(mk_ws "$base" rectopic "$repo" "$branch")

echo "-- emit outside a stage session --"
assert_rc 2 "emit with no active stage refuses" -- "$RECORD" emit "$ws" \
  --stage spec --nonce n1 --verdict drafted --confidence HIGH \
  --refine-rounds 1
assert_out_has "no active stage" "refusal explains the context"
assert_rc 0 "stop-gate outside a stage session passes (not a stage session)" -- \
  "$RECORD" stop-gate "$ws"

echo "-- refusal chain: missing owed -> refuse; success; nonce reuse -> refuse --"
activate_stage "$ws" spec 01 1 nA
assert_rc 2 "stop-gate BLOCKS (exit 2) while no record exists for the attempt" -- \
  "$RECORD" stop-gate "$ws"
assert_out_has "turn end BLOCKED" "block message tells the agent its final action"
assert_rc 2 "emit refuses while spec.md missing, listing it" -- "$RECORD" emit "$ws" \
  --stage spec --nonce nA --verdict drafted --confidence HIGH \
  --refine-rounds 1
assert_out_has "spec.md" "the missing item is listed"
mk_spec "$ws" 01 1
assert_rc 2 "wrong stage claim refuses (active is spec)" -- "$RECORD" emit "$ws" \
  --stage impl --nonce nA --verdict built --confidence HIGH \
  --refine-rounds 1
assert_rc 2 "foreign nonce refuses (not in sessions surface)" -- "$RECORD" emit "$ws" \
  --stage spec --nonce nZ --verdict drafted --confidence HIGH \
  --refine-rounds 1
assert_rc 2 "verdict outside the stage's closed vocabulary refuses" -- "$RECORD" emit "$ws" \
  --stage spec --nonce nA --verdict shipped --confidence HIGH \
  --refine-rounds 1
assert_out_has "closed vocabulary" "refusal names the vocabulary"
assert_rc 0 "emit succeeds with owed present + valid fields" -- "$RECORD" emit "$ws" \
  --stage spec --nonce nA --verdict drafted --confidence HIGH \
  --refine-rounds 2
assert_out_has "recorded: spec" "success is announced"
precond "handoff surface holds the record" \
  bash -c '. "$1/lib/state.sh"; state_get "$2" handoff | command grep -q "nonce=nA .*verdict=drafted\|verdict=drafted"' _ "$RS" "$ws"
assert_rc 0 "stop-gate PASSES after the record exists" -- "$RECORD" stop-gate "$ws"
# …and SAYS SO on the audit surface. The onboarding probe's `stop_gate` item was
# a BEHAVIOURAL test — it asked the agent to make a mistake and then searched
# the pane for `turn end BLOCKED` — so an agent that read the prompt, wrote its
# owed artifact first and emitted before ending never tripped the instrument,
# and a correct backend was refused with "declarations are promises, the probe
# makes them facts". Measured twice, two independent claude/sonnet sessions;
# it blocked a live backend switch. The property that actually matters is not
# "a block was observed" but "the gate ran and ruled correctly", and on the
# allow path that ruling was otherwise invisible: the probe store's audit
# surface did not exist at all.
sgal=$( . "$RS/lib/state.sh"; state_get "$ws" audit 2>/dev/null \
        | command grep -cE "stop_gate_allow nonce=nA( |$)" || true)
[ "${sgal:-0}" -ge 1 ] \
  && ok "the record-present allow appends a nonce-scoped stop_gate_allow line (saw $sgal) — the gate's ruling is readable without a block having happened" \
  || bad "audit carries $sgal stop_gate_allow lines for an attempt whose record IS present; the only evidence the gate ever ran is a refusal"
assert_rc 2 "nonce reuse refuses (single-use)" -- "$RECORD" emit "$ws" \
  --stage spec --nonce nA --verdict drafted --confidence HIGH \
  --refine-rounds 1
assert_out_has "already used" "reuse refusal self-describing"

echo "-- role fields owed per stages.tsv role --"
activate_stage "$ws" spec 01 1 nB
assert_rc 2 "author stage without --refine-rounds refuses" -- "$RECORD" emit "$ws" \
  --stage spec --nonce nB --verdict drafted --confidence HIGH
assert_out_has "refine-rounds" "names the owed author field"
# refine.last_severity is RETIRED: a declared value set (A|B|C|wording|none) with
# no fill rule and no reader. Measured before retiring it: three spellings across
# the tree, six live values that fit neither "this round's own findings" nor "what
# it absorbed", and a pilot who twice built a forecast on it and twice retracted.
# The flag is refused rather than ignored — a silently-dropped argument is how a
# session believes it reported something.
assert_rc 2 "the retired --refine-last-severity is refused, not ignored" -- "$RECORD" emit "$ws" \
  --stage spec --nonce nB --verdict drafted --confidence HIGH \
  --refine-rounds 1 --refine-last-severity none
assert_out_has "retired" "the refusal says the field is gone, not that the arg is unknown"
assert_rc 2 "bad confidence refuses" -- "$RECORD" emit "$ws" \
  --stage spec --nonce nB --verdict drafted --confidence VERY \
  --refine-rounds 1
mk_review "$ws/slices/01/precheck.1.md" precheck 01 1
activate_stage "$ws" precheck 01 1 nC
assert_rc 2 "reviewer stage without --findings-substantive refuses" -- "$RECORD" emit "$ws" \
  --stage precheck --nonce nC --verdict ready --confidence HIGH
assert_out_has "findings-substantive" "names the owed reviewer field (severity-trend input)"
assert_rc 0 "reviewer emit succeeds with findings fields" -- "$RECORD" emit "$ws" \
  --stage precheck --nonce nC --verdict ready --confidence HIGH \
  --findings-substantive 0 --findings-wording 1
precond "reviewer record carries findings.substantive" \
  bash -c '. "$1/lib/state.sh"; state_get "$2" handoff | command grep -q "nonce=nC"' _ "$RS" "$ws"
( . "$RS/lib/state.sh"; state_get "$ws" handoff | command grep "nonce=nC" \
    | command grep -q "findings.substantive=0" ) \
  && ok "findings fields land in the record" || bad "findings fields missing from record"
# The new/repeat split (review-standards §1): derived at round 1, owed from
# round 2, and a PARTITION of the count — the emit refuses any other arithmetic.
( . "$RS/lib/state.sh"; state_get "$ws" handoff | command grep "nonce=nC" \
    | command grep -q "findings.substantive.new=0 findings.substantive.repeat=0" ) \
  && ok "a round-1 emit with no split derives new=all repeat=0 (nothing to repeat yet)" \
  || bad "the round-1 record lacks the derived split: $( . "$RS/lib/state.sh"; state_get "$ws" handoff | command grep "nonce=nC")"
activate_stage "$ws" precheck 01 1 nC1b
assert_rc 2 "round 1 with --findings-repeat 1 refuses (there is no previous round to repeat)" -- "$RECORD" emit "$ws" \
  --stage precheck --nonce nC1b --verdict issues --confidence HIGH \
  --findings-substantive 1 --findings-wording 0 --findings-new 0 --findings-repeat 1
assert_out_has "no previous round" "the refusal says why a repeat is impossible here"
mk_review "$ws/slices/01/precheck.2.md" precheck 01 2
activate_stage "$ws" precheck 01 2 nC2
assert_rc 2 "a round-2 reviewer emit WITHOUT the split refuses" -- "$RECORD" emit "$ws" \
  --stage precheck --nonce nC2 --verdict issues --confidence HIGH \
  --findings-substantive 2 --findings-wording 0
assert_out_has "findings-new" "names the owed pair"
assert_rc 2 "a split that does not partition the count refuses (2 + 1 != 2)" -- "$RECORD" emit "$ws" \
  --stage precheck --nonce nC2 --verdict issues --confidence HIGH \
  --findings-substantive 2 --findings-wording 0 --findings-new 2 --findings-repeat 1
assert_out_has "must equal" "the arithmetic is stated"
assert_rc 0 "round 2 with new + repeat = substantive emits" -- "$RECORD" emit "$ws" \
  --stage precheck --nonce nC2 --verdict issues --confidence HIGH \
  --findings-substantive 2 --findings-wording 0 --findings-new 1 --findings-repeat 1
( . "$RS/lib/state.sh"; state_get "$ws" handoff | command grep "nonce=nC2" \
    | command grep -q "findings.substantive=2 findings.wording=0 findings.substantive.new=1 findings.substantive.repeat=1" ) \
  && ok "the record carries both halves beside the total (the ferry's predicate reads the repeat)" \
  || bad "split fields missing or misplaced: $( . "$RS/lib/state.sh"; state_get "$ws" handoff | command grep "nonce=nC2")"

echo "-- a postcheck with substantive findings owes their leak classes ON THE SURFACE before it can emit --"
# Measured on a live topic: slice 11's postcheck read `findings, substantive 2`
# and classified both in the review file, and the learnings surface — the only
# input the two-anchor judgment reads — carried zero rows for the slice; slice
# 10's rows each say they were written a round late. Nothing required the
# write and nothing noticed its absence. The door is postcheck emit, the same
# shape as the fix round's evidence rule: one learnings row per substantive
# finding, keyed to this (slice, stage, round). Precheck is not gated — §9 C9
# is postcheck's duty — and a clean postcheck owes nothing.
mk_review "$ws/slices/01/postcheck.1.md" postcheck 01 1
activate_stage "$ws" postcheck 01 1 nLK
assert_rc 2 "postcheck with 2 substantive findings and NO learnings rows refuses" -- "$RECORD" emit "$ws" \
  --stage postcheck --nonce nLK --verdict findings --confidence HIGH \
  --findings-substantive 2 --findings-wording 0
assert_out_has "learnings" "the refusal names the surface"
assert_out_has "record.sh learn" "and the write path that clears it"
assert_rc 0 "record.sh learn records a leak class inside the stage" -- "$RECORD" learn "$ws" \
  --leak-class conformance --text "finding 1: the report narrated a range run nothing attested"
lrow=$( . "$RS/lib/state.sh"; state_get "$ws" learnings | tail -1 )
printf '%s\n' "$lrow" | command grep -qE '(^| )slice=01( |$)' \
  && printf '%s\n' "$lrow" | command grep -qE '(^| )stage=postcheck( |$)' \
  && printf '%s\n' "$lrow" | command grep -qE '(^| )round=1( |$)' \
  && ok "the learnings row carries slice, stage and round — the key the door matches on" \
  || bad "learnings row lacks stage/round: $lrow"
assert_rc 2 "one row for two substantive findings is still short (one row per finding)" -- "$RECORD" emit "$ws" \
  --stage postcheck --nonce nLK --verdict findings --confidence HIGH \
  --findings-substantive 2 --findings-wording 0
assert_out_has "1 learnings row" "the refusal counts what it found"
"$RECORD" learn "$ws" --leak-class precheck --text "finding 2: a prose count precheck could have re-derived" > /dev/null
assert_rc 0 "two rows for two findings: the postcheck emits" -- "$RECORD" emit "$ws" \
  --stage postcheck --nonce nLK --verdict findings --confidence HIGH \
  --findings-substantive 2 --findings-wording 0
# The learn confirmation states the promotion rule for THIS class, and that is
# not cosmetic. review-standards §9 was rewritten 2026-09-01 to make the `gate`
# tag FREE — measured cause: it had never been written, 0 of 65 learning rows
# across four topics, while a reading of those same rows found 24
# machine-catchable findings tagged as something else. The old rule made it the
# only class of four whose USE cost the classifier a gate, at single anchor. A
# tool that still tells a reviewer its `gate` tag needs a second anchor is
# quietly pricing the tag again, so BOTH branches are pinned. Placed after the
# count-sensitive block above rather than inside it: these two calls add
# learnings rows, and the first form of this arm broke the "1 learnings row"
# refusal three lines up — an edit has two ends, and one of them was an
# assertion about a count.
lout=$("$RECORD" learn "$ws" --leak-class gate --record progress --text "finding G: a totals line the progress ledger contradicts" 2>&1)
printf '%s\n' "$lout" | command grep -q 'costs you nothing' \
  && printf '%s\n' "$lout" | command grep -q 'this one anchor' \
  && ok "a gate tag is confirmed FREE and single-anchor-promotable (§9's rewritten rule)" \
  || bad "the gate branch reprices the tag; got: $lout"
lout=$("$RECORD" learn "$ws" --leak-class novel --text "finding N: nothing upstream could have seen this" 2>&1)
printf '%s\n' "$lout" | command grep -q 'second independent anchor' \
  && ok "…and a judgment class still carries §14's two-anchor bar (the branch is per class, not a blanket)" \
  || bad "the non-gate branch lost its two-anchor sentence; got: $lout"

# §9's record-naming clause is a FIELD, and the point of a field is that it
# cannot be nodded at. Its VALUE SET is derived from lib/state.sh's writer
# registry (plus `git` and `artifact`), never listed twice — so a surface added
# to the registry is accepted here the day it lands, and this arm asserts the
# derivation rather than a hard-coded list: `notify_events` is picked precisely
# because it is a real registered surface that no reviewer would ever cite, so
# it can only pass by going through the registry.
assert_rc 2 "leak_class=gate without --record refuses (the clause is a field, not a sentence)" -- \
  "$RECORD" learn "$ws" --leak-class gate --text "finding G2: a cap the gates surface already holds"
assert_out_has "--record" "the refusal names the missing field"
assert_out_has "git | artifact" "and prints the value set, so naming one costs a word off a list"
assert_out_has "not yet a predicate" "and says what to do instead — the tag must never become a reason to downgrade"
assert_rc 2 "--record with a name the store does not hold refuses" -- \
  "$RECORD" learn "$ws" --leak-class gate --record the_thing_it_would_catch \
  --text "finding G3: names the defect, not the record"
assert_out_has "registered store surface" "the refusal says what kind of name it wanted"
assert_rc 0 "--record git is accepted (§9's first named case)" -- \
  "$RECORD" learn "$ws" --leak-class gate --record git --text "finding G4: a commit-metadata rule git log answers"
assert_rc 0 "--record artifact is accepted (§9's fourth case: the artifact's own enumeration)" -- \
  "$RECORD" learn "$ws" --leak-class gate --record artifact --text "finding G5: a claims table short of its own list"
assert_rc 0 "--record notify_events is accepted WITHOUT being named in record.sh (derived from the registry)" -- \
  "$RECORD" learn "$ws" --leak-class gate --record notify_events --text "finding G6: a surface only the registry knows"
command grep -q 'notify_events' "$RS/session/record.sh" \
  && bad "record.sh hard-codes a surface name — the value set stopped being derived" \
  || ok "record.sh names no individual surface: the set lives in lib/state.sh's registry alone"
assert_rc 2 "--record on a class that names no predicate refuses (an unused field is a rot vector)" -- \
  "$RECORD" learn "$ws" --leak-class novel --record git --text "finding N2: novel, with a record it cannot have"
assert_out_has "only for leak_class=gate" "the refusal says which class the field belongs to"
lrow=$( . "$RS/lib/state.sh"; state_get "$ws" learnings | command grep -F 'record=git' | tail -1 )
printf '%s\n' "$lrow" | command grep -qE '(^| )record=git( |$)' \
  && ok "the value lands as its own space-delimited field, before text= (the harvest cuts on it)" \
  || bad "record= is not a cut-able field on the row: $lrow"
lrow=$( . "$RS/lib/state.sh"; state_get "$ws" learnings | command grep -F 'leak_class=novel ' | tail -1 )
printf '%s\n' "$lrow" | command grep -qE '(^| )record=( |$)' \
  && ok "a non-gate row carries record= EMPTY rather than omitting it (absent vs not-applicable never differ)" \
  || bad "a non-gate learnings row omits the record field entirely: $lrow"
mk_review "$ws/slices/01/postcheck.2.md" postcheck 01 2
activate_stage "$ws" postcheck 01 2 nLK2
assert_rc 2 "round 2 with findings owes ROUND-2 rows (round 1's do not carry over)" -- "$RECORD" emit "$ws" \
  --stage postcheck --nonce nLK2 --verdict findings --confidence HIGH \
  --findings-substantive 1 --findings-wording 0 --findings-new 1 --findings-repeat 0
assert_out_has "learnings" "the refusal is the leak-row door, not the split (the split was supplied)"
assert_rc 0 "a clean postcheck (0 substantive) owes no row" -- "$RECORD" emit "$ws" \
  --stage postcheck --nonce nLK2 --verdict conforms --confidence HIGH \
  --findings-substantive 0 --findings-wording 3
mk_review "$ws/slices/01/precheck.3.md" precheck 01 3
activate_stage "$ws" precheck 01 3 nLKp
assert_rc 0 "a precheck with substantive findings is NOT gated (leak_class is postcheck's duty, §9 C9)" -- "$RECORD" emit "$ws" \
  --stage precheck --nonce nLKp --verdict issues --confidence HIGH \
  --findings-substantive 2 --findings-wording 0 --findings-new 2 --findings-repeat 0

echo "-- refine bound: the self-loop hard bound is enforced at emit --"
activate_stage "$ws" spec 01 1 nRB
assert_rc 2 "refine.rounds above refine.max_rounds refuses (999 is not a refine log)" -- \
  "$RECORD" emit "$ws" --stage spec --nonce nRB --verdict drafted --confidence HIGH \
  --refine-rounds 999
assert_out_has "refine.max_rounds" "refusal names the bound"
assert_rc 2 "refine.rounds=0 refuses (the loop ran at least once or the record lies)" -- \
  "$RECORD" emit "$ws" --stage spec --nonce nRB --verdict drafted --confidence HIGH \
  --refine-rounds 0
# refine.terminated_on (review-standards §3): derived below the cap, OWED at it,
# and `bound` legal only there — five directions on the default cap of 3.
assert_rc 2 "AT the cap (rounds=3=max) without --refine-terminated-on refuses — the count cannot say what released it" -- \
  "$RECORD" emit "$ws" --stage spec --nonce nRB --verdict drafted --confidence HIGH \
  --refine-rounds 3
assert_out_has "refine-terminated-on clean" "names the owed field and both values"
assert_rc 2 "bound BELOW the cap refuses (rounds=1 against max 3: the cap bound nothing)" -- \
  "$RECORD" emit "$ws" --stage spec --nonce nRB --verdict drafted --confidence HIGH \
  --refine-rounds 1 --refine-terminated-on bound
assert_out_has "below refine.max_rounds" "and says why a bound below the cap is a lie"
assert_rc 2 "a value outside clean|bound refuses" -- \
  "$RECORD" emit "$ws" --stage spec --nonce nRB --verdict drafted --confidence HIGH \
  --refine-rounds 3 --refine-terminated-on maybe
assert_rc 0 "AT the cap with --refine-terminated-on bound emits (an unconverged release is legal, and said)" -- \
  "$RECORD" emit "$ws" --stage spec --nonce nRB --verdict drafted --confidence HIGH \
  --refine-rounds 3 --refine-terminated-on bound
( . "$RS/lib/state.sh"; state_get "$ws" handoff | command grep "nonce=nRB" \
    | command grep -q "refine.rounds=3 refine.terminated_on=bound" ) \
  && ok "the record carries refine.terminated_on=bound beside the round count" \
  || bad "the bound release is not on the record: $( . "$RS/lib/state.sh"; state_get "$ws" handoff | command grep "nonce=nRB")"
activate_stage "$ws" spec 01 1 nRB2
assert_rc 0 "below the cap with no flag emits, deriving clean (the only value possible there)" -- \
  "$RECORD" emit "$ws" --stage spec --nonce nRB2 --verdict drafted --confidence HIGH \
  --refine-rounds 2
( . "$RS/lib/state.sh"; state_get "$ws" handoff | command grep "nonce=nRB2" \
    | command grep -q "refine.rounds=2 refine.terminated_on=clean" ) \
  && ok "…and the derived value lands on the record, so no author record ever lacks the field" \
  || bad "the derived clean is not on the record: $( . "$RS/lib/state.sh"; state_get "$ws" handoff | command grep "nonce=nRB2")"

echo "-- the SPEC must match its template structure at emit (the door, not the gate) --"
# 60-gates proves gates_structure; this proves the door ROUTES the spec to it —
# delete the routing line and every other check stays green. The conformant
# direction needs no arm: mk_spec generates its headings from the template, so
# every other spec emit here is that arm. The break is the shape that shipped
# once in four topics (a section inserted, `## 8. refine log` pushed to `## 9`).
# Reasoning lives at the routing site and on the iteration-log row, not twice.
mk_spec "$ws" 01 1
sed -i 's/^## 8\. refine log/## 8. decisions — Class A\n## 9. refine log/' "$ws/slices/01/spec.md"
activate_stage "$ws" spec 01 1 nST1
assert_rc 2 "a spec whose contract sections are renumbered refuses at emit" -- \
  "$RECORD" emit "$ws" --stage spec --nonce nST1 --verdict drafted --confidence HIGH \
  --refine-rounds 1
assert_out_has "structure" "the refusal names the structure gate, not something downstream"

echo "-- a claims table in ANY owed artifact is resolved at emit (--optional routing) --"
# 60-gates proves the --optional mode; this proves the door ROUTES the other
# owed artifacts through it. The known-bad is the measured defect: six cite
# anchors across four archived topics' turnovers were LINE PINS, in the one
# artifact the next slice's author reads, while a turnover in the same corpus
# wrote the identical claim durably (`postcheck.1.md#5. verdict`).
mk_turnover "$ws" 01 2>/dev/null || printf '# turnover\n\nbody.\n' > "$ws/slices/01/turnover.md"
{ printf '\n## claims\n\n| type | claim | anchor | echo | range | command |\n|---|---|---|---|---|---|\n'
  printf '| cite | the verdict | slices/01/postcheck.1.md:156 | conforms | - | - |\n'; } >> "$ws/slices/01/turnover.md"
activate_stage "$ws" turnover 01 1 nTO1
assert_rc 2 "a turnover whose claims table carries a LINE PIN refuses at emit" -- \
  "$RECORD" emit "$ws" --stage turnover --nonce nTO1 --verdict done --confidence HIGH \
  --refine-rounds 1
assert_out_has "forbidden" "the refusal names the line pin, the rule the author card already teaches"
# The door sweeps the three forward-handed artifacts too (env-sweep-absolute-arm-
# reads-prose: widened after the arm stopped reading a lone /word as a path). A
# dead two-segment absolute path in a turnover refuses; a lone /word beside it
# does not fire, so the clean control passes with that prose still in place.
printf '# turnover\n\nbody. the /abort option stays; see /nowhere/at-all for the trace.\n' > "$ws/slices/01/turnover.md"
activate_stage "$ws" turnover 01 1 nTO2
assert_rc 2 "a turnover citing a dead two-segment absolute path refuses at emit (the env sweep now covers turnover/charters/close-out)" -- \
  "$RECORD" emit "$ws" --stage turnover --nonce nTO2 --verdict done --confidence HIGH --refine-rounds 1
assert_out_has "env sweep" "the refusal names the sweep"
assert_out_has "/nowhere/at-all" "…and the dead token"
printf '# turnover\n\nbody. the /abort option stays.\n' > "$ws/slices/01/turnover.md"
assert_rc 0 "the same turnover without the dead path passes (a lone /word in prose is not a claim)" -- \
  "$RECORD" emit "$ws" --stage turnover --nonce nTO2 --verdict done --confidence HIGH --refine-rounds 1

echo "-- review artifacts must match the review template structure at emit --"
# The template IS the rule the structure gate enforces, and the gate is
# additive-tolerant: a template that LOST a heading would fail nothing here
# (fixtures still write it). Pin the heading the disagreement park points the
# owner at — review-standards §1/§10 name it by number and text.
command grep -qE '^## 3\. absorption[[:space:]]*$' "$WF_ROOT/runtime-docs/templates/review.md" \
  && ok "the shipped review template declares '## 3. absorption' (the park text and review-standards §10 point the owner at it)" \
  || bad "templates/review.md no longer declares '## 3. absorption' — the disagreement park points at a section no review owes"
mk_artifact "$ws/slices/01/precheck.2.md" "free-form review" claims
activate_stage "$ws" precheck 01 2 nST
assert_rc 2 "a free-form review refuses at emit (structure mismatch is a draft)" -- \
  "$RECORD" emit "$ws" --stage precheck --nonce nST --verdict ready --confidence HIGH \
  --findings-substantive 0 --findings-wording 0
assert_out_has "structure" "refusal names the structure gate"
mk_review "$ws/slices/01/precheck.2.md" precheck 01 2
assert_rc 0 "a template-shaped review emits" -- \
  "$RECORD" emit "$ws" --stage precheck --nonce nST --verdict ready --confidence HIGH \
  --findings-substantive 0 --findings-wording 0

echo "-- --halt path: class_u/blocked bypass owed, require --detail --"
activate_stage "$ws" impl 01 1 nD
assert_rc 2 "--halt without --detail refuses" -- "$RECORD" emit "$ws" \
  --stage impl --nonce nD --halt class_u --confidence HIGH
assert_out_has "owes --detail" "halt refusal names the missing detail"
assert_rc 2 "--halt with an unknown class refuses" -- "$RECORD" emit "$ws" \
  --stage impl --nonce nD --halt confused --detail x --confidence HIGH
# A Class U halt owes its question set on disk — slices/<nn>/halt.<n>.md, n =
# this slice's class_u halt count, matching templates/halt.md's headings in
# order (the zero-context-ruler standard, §11, made structural). The pilot's
# only live halt wrote a 28 KB document under a name it invented, and the
# record carried one line: nothing named the file, nothing checked it.
rm -f "$ws/slices/01/halt."*.md
assert_rc 2 "--halt class_u with no question set on disk refuses" -- \
  "$RECORD" emit "$ws" --stage impl --nonce nD --halt class_u \
  --detail "Q1: scope?; Q2: api?" --confidence HIGH
assert_out_has "slices/01/halt.1.md" "the refusal names the expected path (first halt of the slice -> halt.1.md)"
printf '# halt — Class U\n\n## 1. the question\n\nonly one section.\n' > "$ws/slices/01/halt.1.md"
assert_rc 2 "a question set missing the template's sections refuses" -- \
  "$RECORD" emit "$ws" --stage impl --nonce nD --halt class_u \
  --detail "Q1: scope?; Q2: api?" --confidence HIGH
assert_out_has "structure" "the refusal is the structure gate's (heading missing or out of order)"
mk_halt "$ws" 01 1
assert_rc 0 "--halt class_u with its question set bypasses owed artifacts (none exist for impl here)" -- \
  "$RECORD" emit "$ws" --stage impl --nonce nD --halt class_u \
  --detail "Q1: scope?; Q2: api?" --confidence HIGH
( . "$RS/lib/state.sh"; state_get "$ws" handoff | command grep "nonce=nD" \
    | command grep -q "verdict=HALT_class_u" ) \
  && ok "halt record carries verdict=HALT_class_u" || bad "halt verdict not recorded"
( . "$RS/lib/state.sh"; state_get "$ws" handoff | command grep "nonce=nD" \
    | command grep -q "detail=question set: slices/01/halt.1.md — Q1: scope?; Q2: api?" ) \
  && ok "the record's detail leads with the question set's path (the park message and the owner's page carry it for free)" \
  || bad "detail does not lead with the path: $( . "$RS/lib/state.sh"; state_get "$ws" handoff | command grep nonce=nD)"
echo "-- the halt document's NUMBERS and CITATIONS are gated, not narrated --"
# It is the one artifact with no reviewer between it and a binding decision, and
# it used to be checked for headings and file size only. Measured on one topic's
# two Class U halts: a sentence attributed to "coding-rules §10's own words" that
# appears nowhere in that file's 503 lines, and an option arithmetic that did not
# reconcile — neither caught by a gate, a reviewer or a protocol step. Both are
# claims-table shapes: a cite row's echo resolves the first, a count row's
# evidence command the second. Its own workspace, so the halt COUNT is 1 here.
( cd "$repo" && printf '# rules\n\n## 10. commit size\n\nSplit along stable seams.\n' > coding-rules.md \
  && git add coding-rules.md && git commit -qm "docs: add the rules the halt will cite" ) > /dev/null 2>&1
wsh=$(mk_ws "$base" halttopic "$repo" "$branch")
activate_stage "$wsh" impl 01 1 nH1
mk_halt "$wsh" 01 1
sed -i 's#| note | fixture halt, no load-bearing number | - | - | - | - |#| cite | the rule forbids raising the cap | coding-rules.md\#10. commit size | Do not raise this | - | - |#' "$wsh/slices/01/halt.1.md"
assert_rc 2 "a halt whose cite row echoes text the cited file does not carry is REFUSED at emit" -- \
  "$RECORD" emit "$wsh" --stage impl --nonce nH1 --halt class_u --detail "Q1" --confidence HIGH
assert_out_has "content echo" "the refusal is the claims resolver's, naming the echo that did not resolve"
sed -i 's#| Do not raise this |#| Split along stable seams |#' "$wsh/slices/01/halt.1.md"
assert_rc 0 "…and the same halt with a resolving echo emits (the gate asks for a fix it then accepts)" -- \
  "$RECORD" emit "$wsh" --stage impl --nonce nH1 --halt class_u --detail "Q1" --confidence HIGH
( . "$RS/lib/state.sh"; state_get "$wsh" gates | command grep -q "gate=claims" ) \
  && ok "the halt document now carries a claims attestation on the gates surface" \
  || bad "no gate=claims row for the halt doc: $( . "$RS/lib/state.sh"; state_get "$wsh" gates | tail -2)"


echo "-- the halt document's PATHS are swept, not just its claims --"
# The learning loop pre-registered BOTH gates ("run the claims and env-sweep
# gates on halt documents"); the claims half landed first and this is the other
# half. The question set is the one artifact an owner rules
# from with no reviewer between, so a dead absolute path in an option's
# evidence is the claims-echo defect wearing a different coat.
sed -i 's#^fixture\.$#See /no/such/dir/evidence.md for the ceiling this option rests on.#' "$wsh/slices/01/halt.1.md"
cp "$wsh/slices/01/halt.1.md" "$wsh/slices/01/halt.2.md"
activate_stage "$wsh" impl 01 1 nH2
assert_rc 2 "a halt whose §4 prose cites an absolute path that resolves nowhere is REFUSED at emit" -- \
  "$RECORD" emit "$wsh" --stage impl --nonce nH2 --halt class_u --detail "Q1" --confidence HIGH
assert_out_has "does not resolve" "the refusal is the env sweep's, naming the dead path"
( . "$RS/lib/state.sh"; state_get "$wsh" gates | command grep -q "gate=env_sweep" ) \
  && ok "the halt document carries an env_sweep attestation on the gates surface" \
  || bad "no gate=env_sweep row for the halt doc"
# and the fix is the author's one-line edit, accepted by the same door:
sed -i 's#/no/such/dir/evidence.md#coding-rules.md#' "$wsh/slices/01/halt.2.md"
activate_stage "$wsh" impl 01 1 nH3
assert_rc 0 "…and the same halt citing a file that resolves emits (repo-relative, the shape a real option cites)" -- \
  "$RECORD" emit "$wsh" --stage impl --nonce nH3 --halt class_u --detail "Q1" --confidence HIGH
echo "-- the emit door line-pins the TURNOVER, not just the charter --"
# Both artifacts are handed FORWARD to a later author, which is the property
# the gate is scoped on: the spec stage's manifest carries
# TURNOVER_PREV=slices/@prev/turnover.md, so slice N's turnover is read by
# slice N+1's author across a tree slice N has just landed commits into.
# Scope, stated because the arm above already covers the OTHER half: a
# turnover's CLAIMS TABLE was always resolved (gates_claims --optional, the
# "six cite anchors were LINE PINS" defect). This gates its PROSE, which
# nothing looked at. Measured over the six finished topics on disk
# (2026-09-05): 4 turnovers carried 13 pins and ALL FOUR carry zero
# claims-table rows, so every one of the 13 rode forward unchecked — sitting
# under headings like "what changed against the charter (deltas a later slice
# must not re-derive)". This arm proves the DOOR, not the resolver; 60-gates
# already drives `gates_line_pins` itself in both directions.
wst=$(mk_ws "$base" turntopic "$repo" "$branch")
activate_stage "$wst" turnover 01 1 nTO
mkdir -p "$wst/slices/01"
cat > "$wst/slices/01/turnover.md" <<'EOF'
# turnover — slice 01

the query declaration is at include/proj/constraint/conflict_windows.h:160,
defined at src/constraint/conflict_check.cc:97.
EOF
assert_rc 2 "a turnover carrying line pins is REFUSED at the door" -- \
  "$RECORD" emit "$wst" --stage turnover --nonce nTO --verdict done --confidence HIGH \
  --refine-rounds 1
assert_out_has "conflict_windows.h:160" "the refusal names the pin the next author would have followed"
( . "$RS/lib/state.sh"; state_get "$wst" gates \
    | command grep -q 'gate=line_pins result=FAIL.*turnover\.md' ) \
  && ok "the refusal is attested (gate=line_pins result=FAIL on the turnover)" \
  || bad "no line_pins FAIL row for the turnover: $( . "$RS/lib/state.sh"; state_get "$wst" gates | tail -3)"
cat > "$wst/slices/01/turnover.md" <<'EOF'
# turnover — slice 01

the query declaration is at conflict_windows.h::CollectConflictWindowsForPairs,
defined at conflict_check.cc::CollectConflictWindowsForPairs.
read range include/proj/constraint/conflict_windows.h:L160-L170 @ 778a6530.
EOF
assert_rc 0 "…and the construct-named repair emits (the gate asks for a fix it then accepts)" -- \
  "$RECORD" emit "$wst" --stage turnover --nonce nTO --verdict done --confidence HIGH \
  --refine-rounds 1
( . "$RS/lib/state.sh"; state_get "$wst" gates \
    | command grep -q 'gate=line_pins result=PASS.*turnover\.md' ) \
  && ok "the PASS is attested too (the arm is not a constant refusal)" \
  || bad "no line_pins PASS row after the repair"

activate_stage "$ws" spec 01 2 nD3
assert_rc 2 "a SECOND class_u halt of the same slice expects halt.2.md (count-derived, never reused)" -- \
  "$RECORD" emit "$ws" --stage spec --nonce nD3 --halt class_u --detail "Q3" --confidence HIGH
assert_out_has "slices/01/halt.2.md" "…and names it"
mk_halt "$ws" 01 2
assert_rc 0 "…which, once written, emits" -- \
  "$RECORD" emit "$ws" --stage spec --nonce nD3 --halt class_u --detail "Q3" --confidence HIGH
activate_stage "$ws" impl 01 1 nD2
rm -f "$ws/slices/01/halt."*.md
assert_rc 0 "--halt blocked also bypasses owed (and owes no question set — an obstacle is not a decision)" -- "$RECORD" emit "$ws" \
  --stage impl --nonce nD2 --halt blocked --detail "obstacle" --confidence HIGH

echo "-- split --slices validation --"
mk_artifact "$ws/charters.md" charters
activate_stage "$ws" split 00 1 nE
assert_rc 2 "split without --slices refuses" -- "$RECORD" emit "$ws" \
  --stage split --nonce nE --verdict done --confidence HIGH \
  --refine-rounds 1
assert_out_has "owes --slices" "split refusal names the machine index duty"
assert_rc 2 "malformed --slices refuses (id must be 2 digits, risk closed)" -- \
  "$RECORD" emit "$ws" --stage split --nonce nE --verdict done --confidence HIGH \
  --refine-rounds 1 --slices "1:lowish:code:x"
assert_rc 2 "a THREE-field --slices refuses: the repo binding is not optional" -- \
  "$RECORD" emit "$ws" --stage split --nonce nE --verdict done --confidence HIGH \
  --refine-rounds 1 --slices "01:low:x"
assert_out_has "id:risk:repo:title" "the refusal states the four-field grammar"
assert_rc 2 "a repo word outside {code,doc} refuses (closed vocabulary; one slice never spans two repos)" -- \
  "$RECORD" emit "$ws" --stage split --nonce nE --verdict done --confidence HIGH \
  --refine-rounds 1 --slices "01:low:wiki:x"
# The charter is read by every later slice's spec author; a line pin in it
# resolves forever and means something else after the first edit above it
# (owner-promoted 2026-08-22 on two anchors). The door is split emit.
printf '\nslice 01: rewrite the comment at src/planner/resolve.cc:185-191.\n' >> "$ws/charters.md"
assert_rc 2 "a charter carrying a line pin refuses at split emit" -- "$RECORD" emit "$ws" \
  --stage split --nonce nE --verdict done --confidence HIGH \
  --refine-rounds 1 --slices "01:low:code:first slice;02:high:doc:second"
assert_out_has "resolve.cc:185-191" "the refusal names the pin"
# Every declared id owes a `## slice NN` section: the section is what the
# slice's spec author is handed, and what the plan excerpt derives from.
mk_charter "$ws/charters.md" 01
assert_rc 2 "a charter with no section for a declared id refuses at split emit" -- "$RECORD" emit "$ws" \
  --stage split --nonce nE --verdict done --confidence HIGH \
  --refine-rounds 1 --slices "01:low:code:first slice;02:high:doc:second"
assert_out_has "slice 02" "the refusal names the id without a section"
mk_charter "$ws/charters.md" 01 02
assert_rc 0 "well-formed --slices emits" -- "$RECORD" emit "$ws" \
  --stage split --nonce nE --verdict done --confidence HIGH \
  --refine-rounds 1 --slices "01:low:code:first slice;02:high:doc:second"
( . "$RS/lib/state.sh"; state_get "$ws" handoff | command grep "nonce=nE" \
    | command grep -q "slices=01:low:code:first_slice;02:high:doc:second" ) \
  && ok "slices field recorded (spaces underscored, binding carried)" \
  || bad "slices field not recorded as expected"

echo "-- a re-split that re-binds an existing slice id refuses AT EMIT (in-session self-heal) --"
# The standing row wins by construction (ids are never reused, evidence already
# resolves through the binding) — so a changed declaration would be dropped in
# silence and the slice would keep landing in its old checkout. The author fixes
# it inside the session by minting a new id; no park, no owner round.
( . "$RS/lib/state.sh"
  printf 'id=01 status=done risk=low repo=code title=first rederive=0\nid=02 status=pending risk=low title=norepo rederive=0\n' \
    | state_set "$ws" slices ferry ) > /dev/null
activate_stage "$ws" split 00 1 nRB1
mk_charter "$ws/charters.md" 01 02 09 12 13
assert_rc 2 "re-declaring a code-bound id as doc refuses" -- "$RECORD" emit "$ws" \
  --stage split --nonce nRB1 --verdict done --confidence HIGH \
  --refine-rounds 1 --slices "01:low:doc:first;02:low:code:norepo"
assert_out_has "NEW id" "the refusal states the fix (mint a new id, omit the old one)"
assert_rc 2 "a row without repo= counts as code-bound, so re-declaring IT as doc refuses too (the dogfood's shape)" -- \
  "$RECORD" emit "$ws" --stage split --nonce nRB1 --verdict done --confidence HIGH \
  --refine-rounds 1 --slices "01:low:code:first;02:low:doc:norepo"
assert_rc 2 "declaring one id TWICE refuses — otherwise two index rows land and the LAST binding silently wins" -- \
  "$RECORD" emit "$ws" --stage split --nonce nRB1 --verdict done --confidence HIGH \
  --refine-rounds 1 --slices "07:low:code:a;07:low:doc:b"
assert_out_has "twice" "the refusal names the repeated id"
assert_rc 2 "a field breaking TWO rules refuses" -- "$RECORD" emit "$ws" \
  --stage split --nonce nRB1 --verdict done --confidence HIGH \
  --refine-rounds 1 --slices "01:low:doc:first;09:low:code:x;09:low:doc:y"
assert_out_has "re-binds" "…reporting the re-binding…"
assert_out_has "declared twice" "…AND the duplicate in the same refusal (all reasons at once — the author fixes one round, not one per rule)"
assert_rc 0 "the same emit with a NEW id for the doc work passes (good direction)" -- \
  "$RECORD" emit "$ws" --stage split --nonce nRB1 --verdict done --confidence HIGH \
  --refine-rounds 1 \
  --slices "01:low:code:first;02:low:code:norepo;09:low:doc:the_doc_work"

echo "-- split --slices carries delivery order: after= is validated at emit and rides the record --"
activate_stage "$ws" split 00 1 nAF1
assert_rc 2 "a malformed after= tail refuses at emit (it would fold into the title otherwise)" -- \
  "$RECORD" emit "$ws" --stage split --nonce nAF1 --verdict done --confidence HIGH \
  --refine-rounds 1 \
  --slices "01:low:code:first;12:low:code:x:after=9"
assert_out_has "malformed after=" "the refusal names the tail shape"
assert_rc 2 "a forward-referencing after refuses at emit (id order is delivery order)" -- \
  "$RECORD" emit "$ws" --stage split --nonce nAF1 --verdict done --confidence HIGH \
  --refine-rounds 1 \
  --slices "01:low:code:first;12:low:code:x:after=13"
assert_rc 0 "a backward after= within the declaration emits (good direction)" -- \
  "$RECORD" emit "$ws" --stage split --nonce nAF1 --verdict done --confidence HIGH \
  --refine-rounds 1 \
  --slices "01:low:code:first;02:low:code:norepo;12:low:code:x;13:low:code:y:after=12"
( . "$RS/lib/state.sh"; state_get "$ws" handoff | command grep "nonce=nAF1" \
    | command grep -q "13:low:code:y:after=12" ) \
  && ok "the after tail rides the recorded index field to the ferry's ingest" \
  || bad "after= missing from the record's slices field"

echo "-- ferry routes HALT_* from ANY stage (universal halt path) --"
hf=$(mk_headless_ferry)
routes=$( ( set +u; . "$hf" "$ws" 2>/dev/null
  for s in $(command grep -v '^#' "$WF_ROOT/config/stages.tsv" | cut -f1); do
    printf '%s:%s:%s\n' "$s" "$(stage_next_for "$s" HALT_class_u)" \
                             "$(stage_next_for "$s" HALT_blocked)"
  done ) )
nroutes=$(printf '%s\n' "$routes" | command grep -c .)
precond "walked N>=8 stages (saw $nroutes)" test "$nroutes" -ge 8
viol=$(printf '%s\n' "$routes" | command grep -v ':HALT_class_u:HALT_blocked$' || true)
[ -z "$viol" ] && ok "HALT_class_u/HALT_blocked route through from every stage" \
  || bad "stages not routing record-level halts: $viol"
tgt=$( ( set +u; . "$hf" "$ws" 2>/dev/null; stage_next_for spec bogus_verdict ) )
[ -z "$tgt" ] && ok "an unmapped verdict yields no target (ferry parks stall_record)" \
  || bad "unmapped verdict routed to '$tgt'"

echo "-- launch.sh slice: guarded index status edits --"
( . "$RS/lib/state.sh"
  printf 'id=01 status=pending risk=low title=a rederive=0\nid=02 status=done risk=low title=b rederive=0\nid=03 status=superseded risk=low title=c rederive=0\n' \
    | state_set "$ws" slices ferry ) > /dev/null
assert_rc 0 "operator cancels a pending slice" -- \
  "$RS/launch.sh" slice "$ws" 01 cancelled
( . "$RS/lib/state.sh"; state_get "$ws" slices | command grep "id=01" | command grep -q "status=cancelled" ) \
  && ok "index shows cancelled" || bad "cancel did not land"
assert_rc 2 "cancelling a done slice refused" -- "$RS/launch.sh" slice "$ws" 02 cancelled
assert_rc 2 "touching a superseded slice refused (retired ids never revived)" -- \
  "$RS/launch.sh" slice "$ws" 03 pending
assert_rc 2 "restoring a non-cancelled slice refused" -- "$RS/launch.sh" slice "$ws" 02 pending
assert_rc 2 "operator may not set ferry-owned statuses" -- "$RS/launch.sh" slice "$ws" 01 done
assert_rc 0 "restoring the cancelled slice" -- "$RS/launch.sh" slice "$ws" 01 pending
( . "$RS/lib/state.sh"; state_get "$ws" slices | command grep "id=01" | command grep -q "rederive=1" ) \
  && ok "restore sets the premise-rederive flag" || bad "rederive flag not set"

echo "-- ruling-gated halt resumes by RE-ENTERING the suspended stage --"
ws2=$(mk_ws "$base" ruletopic "$repo" "$branch")
( . "$RS/lib/state.sh"
  state_put "$ws2" stage ferry "slice=00" "stage=plan-validate" "round=1" \
    "attempt=1" "state=done" "nonce=nH" "spawn_t=1" > /dev/null
  { echo "reason=class_u"; echo "detail=q"; echo "slice=00"; echo "stage=plan-validate"
    echo "t=$(date +%s)"; echo "notified=1"; echo "resolved=0"; } \
    | state_set "$ws2" halt ferry )
# no ruling yet -> resume must refuse (exit 20) and change nothing
out=$( ( set +u; . "$hf" "$ws2" 2>/dev/null; resume_halt_gate ) 2>&1 ); rc=$?
[ $rc -eq 20 ] && ok "resume without a ruling stays parked (exit 20)" \
  || bad "resume without ruling rc=$rc, want 20"
printf '%s' "$out" | command grep -q "is required to resume" \
  && ok "park message names the required action" || bad "no self-describing park message"
st=$(state_field "$ws2" stage state)
[ "$st" = "done" ] && ok "stage state untouched while parked" || bad "state mutated to '$st'"
sleep 1
"$RS/launch.sh" rule "$ws2" --slice 00 --text "ruling: proceed with option A" > /dev/null 2>&1 \
  || bad "launch.sh rule failed"
precond "ruling landed in the rulings surface" \
  bash -c '. "$1/lib/state.sh"; state_get "$2" rulings | command grep -q "slice=00"' _ "$RS" "$ws2"
precond "ruling archived to slices/00/ruling.1.md" test -s "$ws2/slices/00/ruling.1.md"
out=$( ( set +u; . "$hf" "$ws2" 2>/dev/null; resume_halt_gate; echo RESUMED ) 2>&1 ); rc=$?
printf '%s' "$out" | command grep -q RESUMED \
  && ok "resume with a ruling clears the halt gate" || bad "resume still parked: rc=$rc $out"
[ "$(state_field "$ws2" halt resolved)" = "1" ] \
  && ok "halt marked resolved" || bad "halt not resolved"
st=$(state_field "$ws2" stage state)
[ "$st" = "failed" ] \
  && ok "suspended stage re-enters (state=failed -> respawn WITH the ruling in its manifest), not re-advance into the same halt" \
  || bad "ruling round-trip broken: stage state is '$st' — a done state re-advances the same record into the same class_u park forever"

echo "-- not_ready owes --detail (protocol §4: it IS the class_u mechanism's common spelling) --"
# --halt class_u mandates --detail; not_ready rides the verdict path and did
# not — the ferry's class_u park takes its message from the record's detail
# field, so the owner's page arrived EMPTY (the question set stayed buried in
# the validation note).
wsnr=$(mk_ws "$base" nrtopic "$repo" "$branch")
activate_stage "$wsnr" plan-validate 00 1 nNR
mkdir -p "$wsnr/slices/00"
mk_artifact "$wsnr/slices/00/validation_note.md" "validation note" claims
assert_rc 2 "not_ready without --detail refuses (else the owner page is empty)" -- "$RECORD" emit "$wsnr" \
  --stage plan-validate --nonce nNR --verdict not_ready --confidence HIGH \
  --refine-rounds 1
assert_out_has "detail" "refusal names the missing flag"
assert_rc 0 "not_ready WITH --detail emits" -- "$RECORD" emit "$wsnr" \
  --stage plan-validate --nonce nNR --verdict not_ready --confidence HIGH \
  --refine-rounds 1 --detail "q1; q2; q3 batched"

echo "-- stop gate is scoped to the CALLING session (own record delivered -> free to end) --"
# The live defect (stop_gate_is_global): precheck emitted, the ferry advanced
# and overwrote the stage surface; the reviewer's still-open turn could then
# never end, and the block message instructed it to emit the NEXT stage's
# record. The gate's question is the caller's own debt, not the active
# attempt's: identity travels as the session NAME (stable across warm reuse;
# the nonce is not), resolved to its current nonce at gate time.
wssg=$(mk_ws "$base" stopgate "$repo" "$branch")
mk_review "$wssg/slices/01/precheck.1.md" precheck 01 1
activate_stage "$wssg" precheck 01 1 nSGr 1 sessREV
assert_rc 0 "the reviewer emits its own record" -- "$RECORD" emit "$wssg" \
  --stage precheck --nonce nSGr --verdict ready --confidence HIGH \
  --findings-substantive 0 --findings-wording 0
# the ferry advances: stage surface now impl/running under a NEW nonce; the
# author session joins the surface; the reviewer row stays (held, warm-reuse)
activate_stage "$wssg" impl 01 1 nSGa 1 sessAUT
assert_rc 0 "a superseded session that DELIVERED its record may end (gate scoped by name)" -- \
  "$RECORD" stop-gate "$wssg" sessREV
assert_rc 2 "the ACTIVE session without a record is still blocked (never-finish-silently holds)" -- \
  "$RECORD" stop-gate "$wssg" sessAUT
assert_out_has "turn end BLOCKED" "the active session still gets the block message"
assert_rc 0 "a torn-down session name owes nothing (absent from the sessions surface)" -- \
  "$RECORD" stop-gate "$wssg" sessGONE
assert_rc 2 "an unrendered {SESSION_NAME} placeholder falls back to the GLOBAL check (a broken template must never open the gate for the active attempt)" -- \
  "$RECORD" stop-gate "$wssg" "{SESSION_NAME}"
assert_rc 2 "no name still enforces globally (legacy profile compatibility)" -- \
  "$RECORD" stop-gate "$wssg"
# Each block leaves a nonce-scoped trace: the CLI's own block cap can override
# the hook and force the turn to end, and the ferry sees neither the block nor
# the override — it sees a stage that stays running. The wait loop counts these
# (liveness.stop_gate_blocks_max) and fails the attempt instead of believing
# the pane. Measured: 9 blocks, then a forced end, then hours of nothing.
sgn=$( . "$RS/lib/state.sh"; state_get "$wssg" audit 2>/dev/null \
       | command grep -cE "stop_gate_block nonce=nSGa( |$)" || true)
[ "${sgn:-0}" -ge 2 ] \
  && ok "each block appends a nonce-scoped stop_gate_block audit line (saw $sgn) — the ferry's only window into a hook's verdict" \
  || bad "audit carries $sgn stop_gate_block lines for the blocked attempt; the wait loop has nothing to count"
# Scope of the allow row: ONLY the record-present allow is a ruling about this
# attempt. The other exits — a session whose row holds another nonce, a name
# absent from the surface, an unrendered placeholder, no name at all — are the
# gate declining jurisdiction, and instrumenting them would let the probe pass
# on a gate that opened for the wrong reason. Every stop-gate call in THIS
# fixture took one of those exits or was blocked, so the count is zero.
sgj=$( . "$RS/lib/state.sh"; state_get "$wssg" audit 2>/dev/null \
       | command grep -c "stop_gate_allow" || true)
[ "${sgj:-0}" -eq 0 ] \
  && ok "no allow line from a jurisdiction exit (superseded nonce, torn-down name, unrendered placeholder, no name) — declining to rule is not a ruling" \
  || bad "$sgj allow lines from calls that never reached the record check — a 'not my business' exit is attesting a verdict"
# The wait loop counts stop_gate_block; a session that ends cleanly every turn
# must not accumulate toward its own wedge.
sgw=$( . "$RS/lib/state.sh"; state_get "$wssg" audit 2>/dev/null \
       | command grep -cE "stop_gate_block nonce=nSGr( |$)" || true)
[ "${sgw:-0}" -eq 0 ] \
  && ok "the allow rows are invisible to the wait loop's stop_gate_block count (0 for the delivered nonce) — a well-behaved session cannot wedge itself" \
  || bad "$sgw stop_gate_block lines for a nonce that was never blocked"


echo "-- emit is role-bound: the row carrying the presented nonce must match the stage's role --"
# The move the pre-fix block message INVITED: the superseded reviewer emitting
# the author stage's record. The refusal must name the role mismatch — the
# stale-nonce message alone reads as 'go find the active nonce', which is the
# impersonation path, not the fix.
assert_rc 2 "a reviewer session emitting an author stage's verdict refuses" -- \
  "$RECORD" emit "$wssg" --stage impl --nonce nSGr --verdict built --confidence HIGH \
  --refine-rounds 1
assert_out_has "role" "the refusal names the role binding, not just nonce staleness"


echo "-- the mid-flight door: a ruling newer than the attempt's spawn is refused until acknowledged by exact token --"
# lib/rulings.sh selects the rows; the door compares their t against the stage
# surface's spawn_t (activate_stage stamps now). Rows are appended as launch.sh
# rule writes them. A refusal does not consume the nonce, so one attempt
# carries the whole ladder.
rul() { # ws slice stage t n [scope]
  state_append "$1" rulings operator "v=1 t=$4 slice=$2 stage=$3 ${6:+scope=$6 }n=$5 file=slices/$2/ruling.$5.md text=fixture ruling" > /dev/null
}
# The stamps come from the workspace's OWN spawn_t, never from a `date` read at
# the top of the block. The door compares ruling.t against spawn_t, so what the
# fixture must establish is an ORDER — and an order built from two wall-clock
# reads is a race the box can win. These rulings were stamped five seconds past
# a timestamp taken above, while `activate_stage` writes `spawn_t=$(date +%s)`
# afterwards, so a run that stalled longer than that between the two inverted
# the pair and the emit correctly did not refuse. Measured 2026-09-09 at
# loadavg end 60.23: `want rc=2 got rc=0`, then a cascade as the arms below
# reused the nonce the refusal would not have consumed. `maintenance.md` §2
# names the remedy for exactly this shape: deterministic contention fixtures,
# never wall-clock races.
after_spawn() { # ws [delta] -> a stamp strictly newer than this workspace's spawn_t
  local t; t=$( . "$RS/lib/state.sh"; state_field "$1" stage spawn_t 2>/dev/null )
  printf '%s\n' $(( ${t:-0} + ${2:-5} ))
}
before_spawn() { # ws [delta] -> a stamp strictly older than this workspace's spawn_t
  local t; t=$( . "$RS/lib/state.sh"; state_field "$1" stage spawn_t 2>/dev/null )
  printf '%s\n' $(( ${t:-0} - ${2:-100} ))
}
wsR=$(mk_ws "$base" rulingA "$repo" "$branch"); mk_spec "$wsR" 01 1; activate_stage "$wsR" spec 01 1 nR1
rul "$wsR" 01 any "$(before_spawn "$wsR")" 1   # older than the spawn: it WAS in the manifest
rul "$wsR" 02 any "$(after_spawn "$wsR")" 1    # another slice's
rul "$wsR" 01 precheck "$(after_spawn "$wsR")" 2  # this slice, addressed to another stage
assert_rc 0 "an older ruling, another slice's, and another stage's are not mid-flight: emit passes with no flag" -- \
  "$RECORD" emit "$wsR" --stage spec --nonce nR1 --verdict drafted --confidence HIGH --refine-rounds 1
( command grep -q 'rulings.midflight=' <<< "$(state_get "$wsR" handoff | command grep -E '(^| )nonce=nR1( |$)')" ) \
  && bad "the record carries rulings.midflight= though nothing landed mid-flight" \
  || ok "…and the record carries no rulings.midflight= field (absent, not empty)"
wsR2=$(mk_ws "$base" rulingB "$repo" "$branch"); mk_spec "$wsR2" 01 1; activate_stage "$wsR2" spec 01 1 nR2
rul "$wsR2" 01 any "$(after_spawn "$wsR2")" 1
assert_rc 2 "a ruling for this slice newer than the spawn -> emit REFUSES" -- \
  "$RECORD" emit "$wsR2" --stage spec --nonce nR2 --verdict drafted --confidence HIGH --refine-rounds 1
assert_out_has "slices/01/ruling.1.md" "the refusal names the ruling's file (where to read it)"
assert_out_has "--ruling-ack 01.1" "the refusal names the exact flag and token to re-emit with"
assert_rc 2 "a WRONG token refuses (01.9 names no ruling)" -- \
  "$RECORD" emit "$wsR2" --stage spec --nonce nR2 --verdict drafted --confidence HIGH --refine-rounds 1 --ruling-ack 01.9
assert_rc 2 "a superfluous token refuses (01.1,01.9 — the set must be exact, not a superset)" -- \
  "$RECORD" emit "$wsR2" --stage spec --nonce nR2 --verdict drafted --confidence HIGH --refine-rounds 1 --ruling-ack 01.1,01.9
assert_rc 0 "the exact token passes" -- \
  "$RECORD" emit "$wsR2" --stage spec --nonce nR2 --verdict drafted --confidence HIGH --refine-rounds 1 --ruling-ack 01.1
( state_get "$wsR2" handoff | command grep -E '(^| )nonce=nR2( |$)' | command grep -qE '(^| )rulings.midflight=01.1( |$)' ) \
  && ok "the record carries rulings.midflight=01.1 (the reviewer sees what was absorbed late)" \
  || bad "record lacks rulings.midflight=01.1: $(state_get "$wsR2" handoff | tail -1)"
wsR3=$(mk_ws "$base" rulingC "$repo" "$branch"); mk_spec "$wsR3" 01 1; activate_stage "$wsR3" spec 01 1 nR3
rul "$wsR3" 00 any "$(after_spawn "$wsR3")" 1 topic
assert_rc 2 "a TOPIC-scoped ruling under slice 00, newer than the spawn -> refuses for slice 01 too" -- \
  "$RECORD" emit "$wsR3" --stage spec --nonce nR3 --verdict drafted --confidence HIGH --refine-rounds 1
assert_out_has "--ruling-ack 00.1" "…naming the topic ruling's token"
assert_rc 0 "…and 00.1 acknowledges it" -- \
  "$RECORD" emit "$wsR3" --stage spec --nonce nR3 --verdict drafted --confidence HIGH --refine-rounds 1 --ruling-ack 00.1
wsR4=$(mk_ws "$base" rulingD "$repo" "$branch"); mk_spec "$wsR4" 01 1; activate_stage "$wsR4" spec 01 1 nR4
assert_rc 2 "--ruling-ack with NOTHING landed refuses (a token that names nothing is a wrong claim)" -- \
  "$RECORD" emit "$wsR4" --stage spec --nonce nR4 --verdict drafted --confidence HIGH --refine-rounds 1 --ruling-ack 01.1
assert_out_has "no ruling landed" "the refusal says nothing landed"
# Rule interaction: the HALT path is inside the door — asking the owner what
# they just answered is the costliest shape, so a class_u emit with a
# mid-flight ruling is refused on the ruling before the question set is read.
wsR5=$(mk_ws "$base" rulingE "$repo" "$branch"); mk_spec "$wsR5" 01 1; activate_stage "$wsR5" spec 01 1 nR5
rul "$wsR5" 01 any "$(after_spawn "$wsR5")" 1
assert_rc 2 "a --halt class_u emit with a mid-flight ruling is refused by the door FIRST" -- \
  "$RECORD" emit "$wsR5" --stage spec --nonce nR5 --halt class_u --detail "a question the ruling may already answer" --confidence HIGH
assert_out_has "--ruling-ack 01.1" "…naming the ruling the halt may already be answered by"

check_done
