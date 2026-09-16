#!/usr/bin/env bash
# 60-gates — lib/gates.sh: caps two-direction with named exceedance,
# claims resolver (resolving anchor+echo passes; dead anchor fires; line-pin
# refused; missing echo/range/command fire), env sweep (dead path fires; the
# >=1-slash rule ignores bare basenames), structure gate, gate attestation
# records in the store.
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/fixtures/lib.sh"
. "$RS/lib/state.sh"
. "$RS/lib/gates.sh"

base=$(sc_tmpdir)
read -r repo branch < <(mk_repo "$base/repo")
ws=$(mk_ws "$base" gatetopic "$repo" "$branch")

echo "-- caps: two-direction + named exceedance + source layer --"
mkdir -p "$ws/src"
seq 1 100 | sed 's/^/line /' > "$ws/src/small.sh"
assert_rc 0 "file under cap passes" -- gates_caps "$ws" "$ws/src/small.sh"
seq 1 801 | sed 's/^/line /' > "$ws/src/big.sh"
assert_rc 1 "file over cap.source_file=800 FAILS" -- gates_caps "$ws" "$ws/src/big.sh"
assert_out_has "cap_exceeded" "exceedance named"
assert_out_has "lines=801" "measured value named"
assert_out_has "cap.source_file=800" "cap and value named"
assert_out_has "defaults.kv" "source layer named"
echo "cap.source_file=900" >> "$ws/project.kv"
assert_rc 0 "project.kv loosening the cap makes the same file pass (either direction)" -- \
  gates_caps "$ws" "$ws/src/big.sh"
sed -i '/^cap.source_file=/d' "$ws/project.kv"
echo "-- dirty fingerprint sees untracked files with SPACES in the name --"
printf 'v1\n' > "$repo/un tracked.txt"
fpA=$(gates_dirty_fp "$repo")
printf 'v2 with more bytes\n' > "$repo/un tracked.txt"
fpB=$(gates_dirty_fp "$repo")
rm -f "$repo/un tracked.txt"
[ "$fpA" != "$fpB" ] \
  && ok "a spaced-name untracked file's change flips the fingerprint" \
  || bad "spaced path silently dropped from the fingerprint (awk field split + swallowed stat)"

echo "-- line pins: a charter cites constructs, never line numbers --"
# A `path:NN` keeps RESOLVING after the file grows above it — to whatever now
# sits on that line — so the env sweep's "does it resolve" cannot see the rot.
# Measured on a live charter: 6 of 16 addresses re-pointed at a different
# construct, three of them instructions for slices still pending. Both
# directions, plus the two shapes that must NOT fire (a URL's port, a pin
# inside a fence — quoted data) and the one slashless shape that must (a
# bare `file.cc:393` is how the live charter wrote most of its sixteen).
ch="$ws/charters.md"
cat > "$ch" <<'EOF'
# charters

slice 12: rewrite the comment at src/planner/resolve.cc:185-191 and the
helper in deferred_cleanup.cc:393; see also docs/notes.md:7.
fetch from https://host.example:8443/repo/x:12 (a port, not a pin).

```
quoted: src/old.cc:12 is what the plan said (fenced — evidence, not a citation)
```
EOF
assert_rc 1 "a charter carrying line pins is REFUSED" -- gates_line_pins "$ws" "$ch"
assert_out_has "resolve.cc:185-191" "names the ranged pin"
assert_out_has "deferred_cleanup.cc:393" "names the slashless pin (the live charter's common shape)"
assert_out_has "docs/notes.md:7" "names the doc pin"
assert_out_has "3 citation" "counts exactly the three (the URL port and the fenced pin are not pins)"
command grep -q 'host.example:8443\|old.cc:12' <<< "$SC_OUT" \
  && bad "a URL port or a fenced pin was reported as a citation: $(printf '%s' "$SC_OUT" | command grep 'host.example\|old.cc')" \
  || ok "a URL's port and a fenced pin are left alone (quoted data, not citations)"
cat > "$ch" <<'EOF'
# charters

slice 12: rewrite the comment above src/planner/resolve.cc::ResolvePath ("// retained until
finalization") and the helper deferred_cleanup.cc::Finalize; see docs/notes.md#scope.
read range src/planner/resolve.cc:L185-L191 @ bdef8032 (a range stamp: process evidence, no pin).
EOF
assert_rc 0 "a charter citing constructs (path::symbol, path#heading, a comment's first line) passes" -- gates_line_pins "$ws" "$ch"
( . "$RS/lib/state.sh"; state_get "$ws" gates | command grep -q 'gate=line_pins result=PASS' ) \
  && ok "the verdict is attested on the gates surface (gate=line_pins)" \
  || bad "no line_pins attestation row"

echo "-- charter sections: one \`## slice NN\` per declared id --"
# The per-slice section is what a spec author is handed (and what the plan
# excerpt is derived from); an id with no section reads the whole charter or
# nothing. Both directions, a titled heading, and the id boundary (a
# `## slice 021` heading is not slice 02's).
cat > "$ch" <<'EOF'
# charters

## terminal decomposition table

## slice 01

first.

## slice 02 — the titled form

second.

## slice 021

not two.
EOF
assert_rc 1 "a declared id with no section is REFUSED" -- gates_charter_sections "$ws" "$ch" 01 02 03
assert_out_has "slice 03" "names the missing id"
command grep -qE 'slice 0[12]( |$|:)' <<< "$SC_OUT" \
  && bad "a present section was reported missing: $SC_OUT" \
  || ok "present sections (plain and titled headings) are not reported"
assert_rc 0 "every declared id has its section -> PASS" -- gates_charter_sections "$ws" "$ch" 01 02
printf '# charters\n\n## slice 021\n\nonly the longer id.\n' > "$ch"
assert_rc 1 "a lone \`## slice 021\` does not satisfy id 02 (the id is matched to its boundary)" -- \
  gates_charter_sections "$ws" "$ch" 02
( . "$RS/lib/state.sh"; state_get "$ws" gates | command grep -q 'gate=charter_sections result=PASS' ) \
  && ok "the verdict is attested on the gates surface (gate=charter_sections)" \
  || bad "no charter_sections attestation row"

echo "-- plan-binds: a DECLARED anchor that resolves nowhere is refused at emit --"
# The door the declared excerpt arm stands behind: the composer cuts on exactly
# what the charter declares, so an anchor naming a section the plan lacks costs
# that slice's author the material silently. Refused here, while the author is
# still holding both documents. It refuses a BROKEN declaration and never
# demands one — see the gate's own header for why that line and not a stricter
# one.
pb=$(sc_tmpdir); pbp="$pb/plan.md"; pbc="$pb/charters.md"
cat > "$pbp" <<'EOF'
# fixture plan

## 1. background

BG.

## 2. change spec

### the first cut

CUT.
EOF
printf '# charters\n\n## slice 01\n\nplan-binds:\n- §2\n- §2 the first cut\n' > "$pbc"
assert_rc 0 "every declared anchor resolves -> PASS" -- gates_plan_binds "$ws" "$pbc" "$pbp" 01
printf '# charters\n\n## slice 01\n\nplan-binds:\n- §2\n- §9 no such section\n' > "$pbc"
assert_rc 1 "an anchor naming a section the plan lacks is REFUSED" -- gates_plan_binds "$ws" "$pbc" "$pbp" 01
assert_out_has "§9" "the refusal names the anchor that did not resolve"
printf '# charters\n\n## slice 01\n\nplan-binds:\n- §2 a subsection that is not there\n' > "$pbc"
assert_rc 1 "an anchor naming a subsection the section lacks is REFUSED" -- gates_plan_binds "$ws" "$pbc" "$pbp" 01
# The floor: a declaration with no plan to resolve against is a FAULT, never a
# quiet pass — the unfloored-arm question asked of this arm.
printf '# charters\n\n## slice 01\n\nplan-binds:\n- §2\n' > "$pbc"
assert_rc 1 "a declaration with the plan ABSENT is refused, not passed" -- \
  gates_plan_binds "$ws" "$pbc" "$pb/no-such-plan.md" 01
# A label that yielded NO anchor, and two labels in one section, are refused BY
# NAME. Folded into the generic message they read as "no anchor resolved" — what
# a typo'd §N says too — and the author would go hunting the plan for a section
# that was never the problem.
printf '# charters\n\n## slice 01\n\n**plan-binds:**\n\nintent — prose\n' > "$pbc"
assert_rc 1 "a plan-binds label with no anchor under it is REFUSED" -- gates_plan_binds "$ws" "$pbc" "$pbp" 01
assert_out_has "no \`- §\` anchor" "the refusal names the FORM, not a missing section"
printf '# charters\n\n## slice 01\n\nplan-binds:\n- §2\n\nprose\n\nplan-binds:\n- §1\n' > "$pbc"
assert_rc 1 "two plan-binds labels in one section are REFUSED" -- gates_plan_binds "$ws" "$pbc" "$pbp" 01
assert_out_has "twice" "the refusal says the list was opened twice"
# and a charter that declares nothing is not this gate's business: no verdict,
# no row — the excerpt falls back exactly as it did before the field existed
printf '# charters\n\n## slice 01\n\nbinds W-1.\n' > "$pbc"
assert_rc 0 "a charter declaring no binding passes silently" -- gates_plan_binds "$ws" "$pbc" "$pbp" 01
# Six calls above declare a binding (PASS · unresolved §9 · unresolved
# subsection · plan absent · empty label · duplicate label) and one declares
# none. Only the six wrote a row. Asserted as the verdict LIST rather than a
# count: written as a count once, it said five where the surface held four.
pbrows=$( . "$RS/lib/state.sh"; state_get "$ws" gates | command grep 'gate=plan_binds' | command grep -oE 'result=[A-Z]+' | sort | tr '\n' ' ')
[ "$pbrows" = "result=FAIL result=FAIL result=FAIL result=FAIL result=FAIL result=PASS " ] \
  && ok "the six declaring calls attested and the silent one wrote no row (gate=plan_binds: $pbrows)" \
  || bad "plan_binds attestation rows are '$pbrows', expected five FAIL and one PASS"

echo "-- a lost gate attestation is LOUD (the record is the reviewer's authority) --"
( . "$RS/lib/state.sh"; printf 'seed' | state_set "$ws" gates gate ) > /dev/null 2>&1
corrupt_surface "$ws" gates
out=$(gates_caps "$ws" "$ws/src/small.sh" 2>&1); rc=$?
printf '%s' "$out" | command grep -qi "attest" \
  && ok "append failure to the gates surface warns on stderr (gate verdict rc unchanged: $rc)" \
  || bad "attestation silently lost — reviewer reads a stale gates surface with no trace"
( . "$RS/lib/state.sh"; printf 'reset' | state_set "$ws" gates gate ) > /dev/null 2>&1 || \
  rm -f "$ws/.runtime/state/gates"

echo "-- caps: linear-growth topic artifacts get cap.artifact_lines, not the source cap --"
# charters.md/closeout.md grow with slice count; the source-file fallback
# (800) refused them under a cap that names the wrong thing.
seq 1 900 | sed 's/^/charter line /' > "$ws/charters.md"
assert_rc 0 "a 900-line charters.md passes (grows linearly with slices; 800 is a source-file cap)" -- \
  gates_caps "$ws" "$ws/charters.md"
seq 1 2100 | sed 's/^/charter line /' > "$ws/charters.md"
assert_rc 1 "a 2100-line charters.md fails under its OWN cap" -- \
  gates_caps "$ws" "$ws/charters.md"
assert_out_has "cap.artifact_lines" "the topic-artifact cap is the one named"

mkdir -p "$ws/slices/01"
seq 1 1900 > "$ws/slices/01/spec.md"
assert_rc 0 "spec.md gets cap.spec_lines (2000), not the source cap" -- \
  gates_caps "$ws" "$ws/slices/01/spec.md"
assert_rc 1 "absent file FAILS the caps gate (never silently skipped)" -- \
  gates_caps "$ws" "$ws/src/ghost.sh"
assert_rc 0 "function-length note: honest downgrade when no tool declared" -- \
  gates_caps "$ws" "$ws/src/small.sh"
assert_out_has "no function_length_tool declared" "downgrade is named, not a fake gate"
echo "function_length_tool=clang-tidy:readability-function-size" >> "$ws/project.kv"
assert_rc 0 "with a declared tool the note names the delegation" -- \
  gates_caps "$ws" "$ws/src/small.sh"
assert_out_has "delegated to project tool" "delegation named"

echo "-- cap classification keys on the FILE, never on the path around it --"
# The self-test arm once read `*test*` over the whole path, so any file under a
# path merely CONTAINING test/Test silently took the looser self-test cap —
# found by an independent review reproducing it through the suite's own scratch
# dir (a TMPDIR with "test" in it flipped five assertions). The arms are sized
# to DISCRIMINATE: an 850-line file exceeds the source cap (800) and fits the
# self-test cap (1000), so a classifier that miscategorizes either direction
# below flips the assertion — the first cut of these arms used 1-2-line files,
# which pass under every cap class, and an independent reader demonstrated they
# were vacuous by monkey-patching the pre-fix classifier back in.
mkdir -p "$ws/unittest/src" "$ws/plain" "$ws/contest-dir"
awk 'BEGIN{for(i=1;i<=850;i++) print "# line " i}' > "$ws/unittest/src/plain.sh"
out=$(gates_caps "$ws" "$ws/unittest/src/plain.sh" 2>&1); rc=$?
[ $rc -eq 1 ] && printf '%s\n' "$out" | command grep -q 'cap.source_file' \
  && ok "an 850-line source file under a test-shaped DIRECTORY is refused under cap.source_file (the path is not the file)" \
  || bad "path-shaped misclassification: rc=$rc out=$out"
awk 'BEGIN{for(i=1;i<=850;i++) print "# line " i}' > "$ws/contest-dir/plain.cc"
out=$(gates_caps "$ws" "$ws/contest-dir/plain.cc" 2>&1); rc=$?
[ $rc -eq 1 ] && printf '%s\n' "$out" | command grep -q 'cap.source_file' \
  && ok "and under a directory whose NAME merely CONTAINS test (contest-*) — the TMPDIR-collision shape the review found" \
  || bad "substring-dir misclassification: rc=$rc out=$out"
mkdir -p "$ws/testsuite"
awk 'BEGIN{for(i=1;i<=850;i++) print "# line " i}' > "$ws/testsuite/gen.cc"
out=$(gates_caps "$ws" "$ws/testsuite/gen.cc" 2>&1); rc=$?
[ $rc -eq 0 ] \
  && ok "a testsuite/ directory is test code by location (the third shape the audit named — restored, and pinned here so it cannot silently disappear again)" \
  || bad "testsuite/ misclassified as source: rc=$rc out=$out"
awk 'BEGIN{for(i=1;i<=850;i++) print "# line " i}' > "$ws/plain/is_test_helper.sh"
out=$(gates_caps "$ws" "$ws/plain/is_test_helper.sh" 2>&1); rc=$?
[ $rc -eq 0 ] \
  && ok "an 850-line test-NAMED file still fits — the self-test cap is the file's own name's, wherever it sits" \
  || bad "name-shaped classification failed: rc=$rc out=$out"

echo "-- claims resolver: good direction --"
cat > "$repo/target.md" <<'EOF'
# design notes

## the contract
The frobnicator always closes its handle.
frobnicate_close() is the symbol.
EOF
art="$ws/slices/01/artifact.md"
cat > "$art" <<'EOF'
# fixture artifact

## claims

| type | claim | anchor | echo | range | command |
|---|---|---|---|---|---|
| cite | handle always closed | target.md#the contract | always closes its handle | - | - |
| cite | close symbol exists | target.md::frobnicate_close | frobnicate_close() is the symbol | - | - |
| count | two cite rows above | - | - | target.md:1-6 @ fixture | `grep -c cite` -> 2 |
| absence | no TODO left | - | - | target.md all 6 lines | `grep -c TODO` -> 0 |
| note | free prose, unchecked | - | - | - | - |
EOF
assert_rc 0 "resolving anchors + echoes + stamped count/absence rows PASS" -- \
  gates_claims "$ws" "$art"
rows=$(state_get "$ws" gates | command grep 'gate=claims' | tail -1 | command grep -oE 'rows=[0-9]+')
[ "$rows" = "rows=5" ] && ok "gate attests it saw all 5 rows (fixture precondition: N>0)" \
  || bad "claims gate row count wrong: '$rows' (want rows=5)"

echo "-- --at-tip: the spec's table re-resolved at the landed tip, own gate name, baseline rows skipped --"
# Measured: a slice's own commits rewrote the text a behavior
# row echoed and the once-at-spec-emit PASS rode to close-out. The tip re-run
# records under spec_claims_tip (never over the spec-emit `claims` row), and a
# row marked `baseline` in its range describes the pre-slice tree on purpose.
printf '| cite | the pre-slice wording | target.md#the contract | never closes its handle | baseline | - |\n' >> "$art"
assert_rc 0 "--at-tip PASSES with a dead-echo row marked baseline (skipped, not resolved)" -- \
  gates_claims "$ws" "$art" --at-tip
tiprow=$(state_get "$ws" gates | command grep 'gate=spec_claims_tip' | tail -1)
printf '%s\n' "$tiprow" | command grep -q 'result=PASS .*rows=6 skipped=1' \
  && ok "recorded as gate=spec_claims_tip PASS rows=6 skipped=1 (the skip is counted, never silent)" \
  || bad "spec_claims_tip row wrong: $tiprow"
assert_rc 1 "the SAME artifact without --at-tip FAILS on that row (baseline means nothing at spec-emit)" -- \
  gates_claims "$ws" "$art"
sed -i '$d' "$art"
sed -i 's/always closes its handle/now closes its handle late/' "$repo/target.md"
assert_rc 1 "--at-tip FAILS when the slice's own edit broke a live row's echo (the anchor's shape)" -- \
  gates_claims "$ws" "$art" --at-tip
assert_out_has "content echo" "…naming the echo that no longer holds"
state_get "$ws" gates | command grep 'gate=spec_claims_tip' | tail -1 | command grep -q 'result=FAIL' \
  && ok "…recorded FAIL under spec_claims_tip, leaving the spec-emit claims rows untouched" \
  || bad "no FAIL row under spec_claims_tip"
sed -i 's/now closes its handle late/always closes its handle/' "$repo/target.md"

echo "-- claims resolver: each bad direction fires --"
bad_art() { # rowline -> writes artifact with one data row
  { echo "## claims"; echo;
    echo "| type | claim | anchor | echo | range | command |"
    echo "|---|---|---|---|---|---|"
    echo "$1"; } > "$art"
}
bad_art "| cite | moved target | target.md#no such heading | always closes | - | - |"
assert_rc 1 "dead heading anchor FIRES" -- gates_claims "$ws" "$art"
assert_out_has "not found" "resolver failure is loud"
bad_art "| cite | dead file | nowhere.md#x | y | - | - |"
assert_rc 1 "dead path FIRES" -- gates_claims "$ws" "$art"
assert_out_has "resolves nowhere" "path failure named"
bad_art "| cite | line pin | target.md:3 | always closes | - | - |"
assert_rc 1 "line-pin anchor REFUSED (durable anchors only)" -- gates_claims "$ws" "$art"
assert_out_has "forbidden" "line-pin named as forbidden"
echo "-- cite SCOPE: the echo must sit inside the section the anchor names --"
# The gap this arm exists for: the cite gate proves a heading matching the
# anchor exists SOMEWHERE and the echo exists SOMEWHERE, and their conjunction
# reads as "this text is under this heading" without being it. target.md grows a
# second section so the two can be told apart.
printf '\n## known limits\nThe frobnicator sometimes leaks under load.\n' >> "$repo/target.md"
grec() { ( . "$RS/lib/state.sh"; state_get "$ws" gates 2>/dev/null ); }

bad_art "| cite | the leak | target.md#the contract | sometimes leaks | - | - |"
# FIRST the gap itself, so this suite records that the older gate cannot see it:
assert_rc 0 "the cite gate PASSES an echo drawn from another section (the gap, asserted rather than assumed)" -- \
  gates_claims "$ws" "$art"
assert_rc 1 "the scope gate FIRES on it" -- gates_claims_cite_scope "$ws" "$art"
assert_out_has "OUTSIDE" "the failure names the anchored section it fell outside of"
assert_out_has "anchor the heading whose section holds the text" "and says what to do about it"
if command grep -q 'gate=claims_cite_scope result=FAIL .*judged=1 out=1' <<< "$(grec)"; then
  ok "recorded as gate=claims_cite_scope FAIL judged=1 out=1 (its own name, the report's own PASS/FAIL)"
else
  bad "scope record wrong: $(command grep 'claims_cite_scope' <<< "$(grec)" | tail -1)"
fi

bad_art "| cite | the limit | target.md#known limits | sometimes leaks | - | - |"
assert_rc 0 "the SAME echo anchored on the section that holds it PASSES (the fix is re-anchoring, not deleting the row)" -- \
  gates_claims_cite_scope "$ws" "$art"
bad_art "| cite | handle | target.md#the contract | always closes its handle | - | - |"
assert_rc 0 "an in-section echo still passes — the change adds a red, it does not move the honest rows" -- \
  gates_claims_cite_scope "$ws" "$art"
if command grep -q 'gate=claims_cite_scope result=PASS .*judged=1 out=0' <<< "$(grec)"; then
  ok "a pass is recorded with its judged count too (the rate the owner weighs needs both ends)"
else
  bad "scope PASS record wrong: $(command grep 'claims_cite_scope' <<< "$(grec)" | tail -1)"
fi

# THE FLOOR. Only rows whose path resolves, whose fragment names a heading and
# whose echo is in the file are judged here; everything else is the cite gate's
# business. So a PASS can be vacuous, and `judged=` is what makes that visible
# in the report instead of indistinguishable from a real one.
bad_art "| cite | dead file | nowhere.md#x | y | - | - |"
assert_rc 0 "an unresolvable row is NOT this gate's red (the cite gate already refuses it)" -- \
  gates_claims_cite_scope "$ws" "$art"
if command grep -q 'gate=claims_cite_scope result=PASS .*judged=0' <<< "$(grec)"; then
  ok "and the vacuous PASS says judged=0 out loud — the floor every absence verdict owes"
else
  bad "judged=0 not recorded for an all-unresolvable table: $(command grep 'claims_cite_scope' <<< "$(grec)" | tail -1)"
fi
bad_art "| cite | symbol row | target.md::frobnicate_close | frobnicate_close() is the symbol | - | - |"
assert_rc 0 "a path::symbol anchor is out of scope (a heading's extent is the document's syntax; a symbol's would need a parser per language)" -- \
  gates_claims_cite_scope "$ws" "$art"
printf '# no table here\n\nbody.\n' > "$art"
assert_rc 0 "an artifact with no claims table is a SKIP, never a red" -- \
  gates_claims_cite_scope "$ws" "$art"
if command grep -q 'gate=claims_cite_scope result=SKIP' <<< "$(grec)"; then
  ok "the SKIP is attested like every other (a reader tells 'no table' from 'never ran')"
else
  bad "no claims_cite_scope SKIP row recorded"
fi


echo "-- --optional: the gate is attached to the FORMAT, not to a list of artifacts --"
# Measured over four archived topics: 336 claims rows lived in artifacts this
# gate was never routed to — conformance, turnover, charters, closeout, the
# validation note — 160 of them in turnover.md, and SIX of its cite anchors were
# line pins, which the arm directly above refuses wherever it runs. Widening
# needs exactly one thing: an absent table must mean "not owed here" instead of
# "FAIL". Three directions, because getting any one wrong is a regression.
printf '# an artifact whose contract owes no claims table\n\nbody, no table.\n' > "$art"
assert_rc 0 "--optional: no table is a named SKIP, not a failure" -- \
  gates_claims "$ws" "$art" --optional
assert_out_has "carries no claims table" "the SKIP names itself (never silent)"
( . "$RS/lib/state.sh"; state_get "$ws" gates 2>/dev/null ) | command grep -q 'gate=claims result=SKIP' \
  && ok "the SKIP is ATTESTED on the gates surface (a reader can tell 'not owed' from 'never ran')" \
  || bad "no SKIP row recorded — an unattested skip is indistinguishable from a gate that never ran"
assert_rc 1 "the SAME artifact without --optional still FAILS (spec/review/halt keep their duty)" -- \
  gates_claims "$ws" "$art"
# and a table that IS present is resolved under --optional exactly as elsewhere:
# the whole point is that writing one opts you in, not that it is unchecked.
bad_art "| cite | line pin in an optional artifact | target.md:3 | always closes | - | - |"
assert_rc 1 "--optional does NOT mean unchecked: a line pin in a table that IS present still FIRES" -- \
  gates_claims "$ws" "$art" --optional
bad_art "| cite | echo rotted | target.md#the contract | never closes anything | - | - |"
assert_rc 1 "stale content echo FIRES (the cited text moved or never said that)" -- \
  gates_claims "$ws" "$art"
bad_art "| cite | no echo | target.md#the contract | - | - | - |"
assert_rc 1 "missing content echo FIRES (existence is not verification)" -- \
  gates_claims "$ws" "$art"
bad_art "| count | unstamped | - | - | - | \`grep -c x\` |"
assert_rc 1 "count row without read-range stamp FIRES" -- gates_claims "$ws" "$art"
assert_out_has "read-range stamp" "names the missing stamp"
bad_art "| absence | no command | - | - | lines 1-6 | - |"
assert_rc 1 "absence row without evidence command FIRES" -- gates_claims "$ws" "$art"
bad_art "| conjecture | wild | - | - | - | - |"
assert_rc 1 "unknown claim type FIRES (closed set)" -- gates_claims "$ws" "$art"
printf '# no claims section at all\n' > "$art"
assert_rc 1 "artifact without a claims table FIRES (the artifact owes one)" -- \
  gates_claims "$ws" "$art"

echo "-- process rows: a claim about what the PROCESS did owes its OUTPUT, not its word --"
# The one claim class no reader checks by READING it. Measured across one slice
# pair: three drafting forms of one rule. A forward-only prohibition left the
# whole pre-existing backlog standing. The sweep written as an INSTRUCTION found
# two instances the review had not named, LEFT ONE, and reported itself complete
# ("§8 re-read in full, first entry to last, every line read this session").
# The sweep written as PRINTED EVIDENCE was re-run by the reviewer, which got
# its 29 hits back in the same order with the same line numbers and matched
# text, dispositions accounting for all 29 with no remainder, and issued ready.
# So the gate demands the third form: extent, command by label, and the output.
# What it does NOT check is that the dispositions leave no remainder — semantic,
# and already the reviewer's under §7 P4's run-every-command duty.
proc_art() { # rowline, evidence-block-lines -> artifact with one process row
  { echo "## claims"; echo;
    echo "| type | claim | anchor | echo | range | command |"
    echo "|---|---|---|---|---|---|"
    echo "$1"; echo; echo '```'; [ -n "$2" ] && printf '%s\n' "$2"; echo '```'; } > "$art"
}
proc_art "| process | §8 swept for self-tallies; 29 hits, all dispositioned | - | - | target.md:1-6 @ fix | E7 |" \
  "$(printf 'E7: grep -noE x target.md\nE7-out: 3:x · 5:x  (29 hits, no remainder)')"
assert_rc 0 "a process row with extent + labelled command + its OUTPUT passes" -- \
  gates_claims "$ws" "$art"
proc_art "| process | §8 re-read in full, first entry to last, every line this session | - | - | target.md:1-6 @ fix | E7 |" \
  "E7: grep -noE x target.md"
assert_rc 1 "the same row WITHOUT its E<n>-out output FIRES (the measured failing form)" -- \
  gates_claims "$ws" "$art"
assert_out_has "E7-out" "the refusal names the missing output line"
proc_art "| process | the gates re-ran on the edited text | - | - | - | E7 |" \
  "$(printf 'E7: bash gate.sh\nE7-out: PASS')"
assert_rc 1 "a process row with no EXTENT FIRES (what it covered, not that it happened)" -- \
  gates_claims "$ws" "$art"
assert_out_has "extent" "the refusal names the missing extent"
proc_art "| process | swept the log | - | - | target.md:1-6 @ fix | \`grep -c round target.md\` -> 29 |" ""
assert_rc 1 "a process row holding its command INLINE FIRES (output has to live on disk)" -- \
  gates_claims "$ws" "$art"
assert_out_has "LABEL" "the refusal names the label requirement"

echo "-- a project gate does not inherit the workflow's own LC_ALL (a gate must not change what it measures) --"
# Measured, on a delivered repo: its hygiene gate matched CJK with a PCRE \x{}
# escape above U+00FF, a COMPILE error outside a UTF-8 locale. Under the LC_ALL=C
# every entry point of this workflow exports, that grep exited 2, the script's own
# `|| true` absorbed it, and the gate reported 0 FINDINGS with the axis still
# listed as scanned. The same tree under a developer's locale reported the
# finding — which is why nobody saw it by hand. The workflow supplied the cause.
wsl=$(mk_ws "$base" localetopic "$repo" "$branch")
printf 'build=printf %%s "LC_ALL=[${LC_ALL-unset}]"\n' >> "$wsl/project.kv"
gates_project "$wsl" build > /dev/null 2>&1
glog=$(ls -t "$wsl"/.runtime/logs/gate-build-*.log 2>/dev/null | head -1)
precond "the project gate wrote its log" test -n "$glog"
command grep -q 'LC_ALL=\[unset\]' "$glog" \
  && ok "the project's command sees NO LC_ALL — the workflow's internal collation is not imposed on it" \
  || bad "the project command inherited the workflow's LC_ALL: $(command grep -o 'LC_ALL=\[[^]]*\]' "$glog" | head -1)"
command grep -q 'env: LC_ALL unset for the project command' "$glog" \
  && ok "and the log header records the environment, so the invocation is reproducible" \
  || bad "the gate log does not say what environment it ran under"
# known-bad: the workflow's own LC_ALL really is C at this point, so the arm is
# not vacuously passing on an environment that never had one.
[ "${LC_ALL:-}" = "C" ] \
  && ok "known-bad guard: the workflow's own LC_ALL IS C here, so the arm above measured a real drop" \
  || bad "the self-check's own LC_ALL is '${LC_ALL:-unset}' — the arm above proves nothing"

echo "-- the claim-type vocabulary is ONE closed set, and every place that states it agrees --"
# A closed vocabulary written down in four places drifts, and this tree has
# measured that exact failure: a template
# saying one thing while the render said another. The gate parses the set, the
# standard defines it, and the two templates are what an author actually fills
# in — a type the gate accepts but no template mentions is a facility nobody
# uses, and a type a template offers but the gate rejects is a refused emit.
# Extract from each source's OWN form, never by grepping for the expected list
# (a check that looks for what it expects can only find it missing, never wrong).
# The gate-side set moved to lib/gates_claims.sh when the claims family was split
# out of gates.sh, and this arm FAILED LOUDLY on that move rather than silently
# reading an empty set — which is the precondition line below doing its job.
claim_types_gate() { sed -n 's/.*closed set: \([a-z|]*\)).*/\1/p' "$WF_ROOT/runtime-scripts/lib/gates_claims.sh" \
  | tr '|' '\n' | command grep -v '^$' | sort -u; }
claim_types_std() { sed -n 's/^| type | \(.*\) — the closed set.*/\1/p' "$WF_ROOT/runtime-docs/review-standards.md" \
  | command grep -oE '`[a-z]+`' | tr -d '`' | sort -u; }
claim_types_tpl() { sed -n 's/^\([a-z|]*\)\. cite rows carry.*/\1/p' "$WF_ROOT/runtime-docs/templates/spec.md" \
  | tr '|' '\n' | command grep -v '^$' | sort -u; }
g=$(claim_types_gate); d=$(claim_types_std); t=$(claim_types_tpl)
precond "the gate states a claim-type set" test -n "$g"
precond "review-standards states a claim-type set" test -n "$d"
precond "the spec template states a claim-type set" test -n "$t"
if [ "$g" = "$d" ] && [ "$g" = "$t" ]; then
  ok "gate, standard and spec template name the same claim types ($(printf '%s' "$g" | tr '\n' ' '))"
else
  bad "claim-type vocabulary drift — a closed set stated in three places must be one set."$'\n'"    gate:     $(printf '%s' "$g" | tr '\n' ' ')"$'\n'"    standard: $(printf '%s' "$d" | tr '\n' ' ')"$'\n'"    template: $(printf '%s' "$t" | tr '\n' ' ')"
fi
# known-bad: drift must be visible, not just absence.
dv=$(sc_tmpdir); mkdir -p "$dv/runtime-scripts/lib"
printf 'echo "claims row $n: unknown type (closed set: cite|count|absence)"\n' > "$dv/runtime-scripts/lib/gates_claims.sh"
drift=$(sed -n 's/.*closed set: \([a-z|]*\)).*/\1/p' "$dv/runtime-scripts/lib/gates_claims.sh" | tr '|' '\n' | command grep -v '^$' | sort -u)
[ "$drift" != "$g" ] && ok "known-bad: a gate whose closed set lost a type reads as different (drift is observable)" \
  || bad "known-bad: a shortened closed set compared EQUAL — the extractor is blind"

echo "-- behavior rows: anchor + echo + rerun command, or the row fires --"
# The class that cleared two HIGH-confidence prechecks: every counted claim
# verified, the one "this test already does X" claim was false — nothing
# obliged anyone to open the file. behavior joins the checked set.
bad_art "| behavior | close always runs | target.md::frobnicate_close | frobnicate_close() is the symbol | - | \`bash -c true\` -> 0 |"
assert_rc 0 "a behavior row with path::symbol + echo + rerun command PASSES (pre-fix: unknown type)" -- \
  gates_claims "$ws" "$art"
bad_art "| behavior | heading anchored | target.md#the contract | always closes its handle | - | \`x\` |"
assert_rc 1 "a behavior row with a HEADING anchor fires (a behavior lives in code, not under a heading)" -- \
  gates_claims "$ws" "$art"
assert_out_has "path::symbol" "the failure names the required anchor shape"
bad_art "| behavior | no command | target.md::frobnicate_close | frobnicate_close() is the symbol | - | - |"
assert_rc 1 "a behavior row without the rerun command fires" -- gates_claims "$ws" "$art"
assert_out_has "rerun command" "the failure names the missing command"
bad_art "| behavior | no echo | target.md::frobnicate_close | - | - | \`x\` |"
assert_rc 1 "a behavior row without a content echo fires (existence is not verification)" -- \
  gates_claims "$ws" "$art"
bad_art "| behavior | dead symbol | target.md::no_such_symbol | anything | - | \`x\` |"
assert_rc 1 "a behavior row whose symbol does not resolve fires" -- gates_claims "$ws" "$art"

echo "-- stamp freshness: a forwarded spec stamp on a displaced line is refused --"
# Measured shape: the spec's function grew by net lines, every stamp below
# shifted, and a conformance claiming "@ HEAD re-read" carried the spec's
# numbers verbatim — true assertion, forwarded process claim.
wssf=$(mk_ws "$base" stampfresh "$repo" "$branch")
( . "$RS/lib/state.sh"
  printf 'id=01 status=active risk=low repo=code title=s rederive=0\n' \
    | state_set "$wssf" slices ferry ) > /dev/null
activate_stage "$wssf" impl 01 1 nSF
mkdir -p "$repo/src"
seq 1 20 | sed 's/^/line /' > "$repo/src/mod.c"
( cd "$repo" && git add src/mod.c && git commit -qm "feat: seed module for stamps" )
sfspec="$wssf/slices/01/spec.md"
mkdir -p "$wssf/slices/01"
{ echo "# spec"; echo "read stamps src/mod.c:15 and src/mod.c:2 at the baseline"
  claims_block; } > "$sfspec"
assert_rc 0 "the spec's claims gate runs (writes the sha-pinned attestation the baseline comes from)" -- \
  gates_claims "$wssf" "$sfspec"
( cd "$repo" && sed -i '5i inserted-a\ninserted-b\ninserted-c' src/mod.c \
  && git add src/mod.c && git commit -qm "feat: shift the numbering by three" )
sfconf="$wssf/slices/01/conformance.md"
printf '# conformance\nre-read at HEAD: src/mod.c:15 verified\n' > "$sfconf"
assert_rc 1 "an identical stamp on a line displaced +3 FIRES (the re-read would have printed the new number)" -- \
  gates_stamp_freshness "$wssf" "$sfconf" "$sfspec"
assert_out_has "src/mod.c:18" "the failure names the number an @HEAD re-read prints"
printf '# conformance\nre-read at HEAD: src/mod.c:18 verified\n' > "$sfconf"
assert_rc 0 "the RESTAMPED pin passes (the re-read really happened)" -- \
  gates_stamp_freshness "$wssf" "$sfconf" "$sfspec"
printf '# conformance\nre-read at HEAD: src/mod.c:2 unchanged\n' > "$sfconf"
assert_rc 0 "a shared stamp ABOVE the shift passes — its number did not move (identical is correct there)" -- \
  gates_stamp_freshness "$wssf" "$sfconf" "$sfspec"
printf '# conformance\n```\ntranscript quoting src/mod.c:15\n```\nlive: src/mod.c:18\n' > "$sfconf"
assert_rc 0 "a fenced transcript quote is data, not a stamp (the live citation still checks)" -- \
  gates_stamp_freshness "$wssf" "$sfconf" "$sfspec"
# Shared means the MAXIMAL token, never a substring: a spec stamp :154 does
# not share a conformance stamp :15 (its own fresh read of a displaced
# region), and a longer path is a different stamp too.
sed -i 's|src/mod.c:15 |src/mod.c:154 |' "$sfspec"
precond "the spec now stamps :154 and no bare :15 remains (whole file greped)" \
  bash -c '! command grep -qE "src/mod\.c:15([^0-9]|$)" "$1"' _ "$sfspec"
printf '# conformance\nfresh HEAD read: src/mod.c:15 — this document own stamp\n' > "$sfconf"
assert_rc 0 "a conformance-OWN stamp that is a substring of the spec's is NOT shared — no refusal (pre-fix: fixed-string match false-refused it)" -- \
  gates_stamp_freshness "$wssf" "$sfconf" "$sfspec"
sed -i 's|src/mod.c:154 |src/mod.c:15 |' "$sfspec"
echo "-- the second shape of the same lie: a COUNT that claims to be current --"
# The stamp axis sees `path:NN`. The measured miss forwarded a wc -l count from
# an earlier commit-unit into an "at HEAD" sentence, where no stamp existed to
# check. The gate does not parse what the number means — a total, a delta, a
# range — because that reader would be fragile and would refuse honest prose.
# It asks the one question needing no interpretation: show what produced it.
printf '# conformance\nthe registry is 412 lines at HEAD, unchanged from cu-1a.\n' > "$sfconf"
assert_rc 1 "a bare count asserted at HEAD FIRES (no command produced it)" -- \
  gates_stamp_freshness "$wssf" "$sfconf" "$sfspec"
assert_out_has "carries no command" "the failure names what is missing, not the number"
printf '# conformance\nthe registry is 412 lines at HEAD (`$ wc -l < src/mod.c`).\n' > "$sfconf"
assert_rc 0 "the same sentence with its inline command passes" -- \
  gates_stamp_freshness "$wssf" "$sfconf" "$sfspec"
printf '# conformance\nthe registry is 412 lines at HEAD (`E7`).\n\n```\nE7: wc -l < src/mod.c\n```\n' > "$sfconf"
assert_rc 0 "and with a NAMED command from the evidence block — the piped-command path stays open" -- \
  gates_stamp_freshness "$wssf" "$sfconf" "$sfspec"
printf '# conformance\nthe acceptance composite passed at HEAD; 64 tests registered.\n' > "$sfconf"
assert_rc 0 "prose that claims currency without asserting a COUNT is untouched (no false refusal)" -- \
  gates_stamp_freshness "$wssf" "$sfconf" "$sfspec"
printf '# conformance\ncu-1a measured 412 lines; see the spec claims table.\n' > "$sfconf"
assert_rc 0 "and a count that does NOT claim to be current is prose, not a measurement" -- \
  gates_stamp_freshness "$wssf" "$sfconf" "$sfspec"

wsnb=$(mk_ws "$base" stampnobase "$repo" "$branch")
mkdir -p "$wsnb/slices/01"
printf '# spec\nsrc/mod.c:15\n' > "$wsnb/slices/01/spec.md"
printf '# conformance\nsrc/mod.c:15\n' > "$wsnb/slices/01/conformance.md"
assert_rc 0 "no spec claims attestation -> named SKIP, never a guess" -- \
  gates_stamp_freshness "$wsnb" "$wsnb/slices/01/conformance.md" "$wsnb/slices/01/spec.md"
assert_out_has "SKIP" "the skip names itself"
# The emit path is record.sh plus the helper file it sources (session/emit_checks.sh
# holds the owed-and-gates pass); the wiring may live in either.
command grep -q 'gates_stamp_freshness "$ws" "$f"' "$RS/session/record.sh" "$RS/session/emit_checks.sh" \
  && ok "emit wiring: the emit path runs the gate on conformance.md (impl/fix owe it)" \
  || bad "gates_stamp_freshness is not wired into the emit path (record.sh + session/emit_checks.sh)"

echo "-- claims heading: the gate parses the SHIPPED templates' headings --"
cat > "$art" <<'EOF'
# artifact with the spec template's numbered heading

## 6. claims table

| type | claim | anchor | echo | range | command |
|---|---|---|---|---|---|
| note | numbered-heading fixture | - | - | - | - |
EOF
assert_rc 0 "an artifact using the spec template's '## 6. claims table' heading parses" -- \
  gates_claims "$ws" "$art"
tpl_rows=$(_gates_claims_rows "$WF_ROOT/runtime-docs/templates/spec.md" | command grep -c .)
[ "${tpl_rows:-0}" -ge 1 ] \
  && ok "the shipped spec template's own claims table is visible to the gate ($tpl_rows rows)" \
  || bad "gates_claims cannot see the spec template's claims table — every template-following spec fails its first emit"
rv_rows=$(_gates_claims_rows "$WF_ROOT/runtime-docs/templates/review.md" 2>/dev/null | command grep -c .)
[ "${rv_rows:-0}" -ge 1 ] \
  && ok "the shipped review template's claims table is visible to the gate ($rv_rows rows)" \
  || bad "review template absent or its claims heading invisible to the gate"
cat > "$art" <<'EOF'
# no claims anywhere
## 6. something else
prose only.
EOF
assert_rc 1 "an artifact with numbered headings but NO claims table still FIRES" -- \
  gates_claims "$ws" "$art"

echo "-- env sweep scope: prose slash tokens never fire (absolute paths + :NN pins only) --"
cat > "$art" <<'EOF'
# review fragment
severity classes A/B/C/wording route findings; decision routing is Class A/C/U.
risk class low/med/high re-derived; gates are build/lint/test/acceptance.
a progress record and/or a conformance change is fix-round evidence.
per runtime-docs/review-standards.md the compact form applies; the emit gate
lives in lib/gates.sh (prose reference, not a pinned read).
EOF
precond "the artifact holds raw slash tokens (the sweep must SEE and pass them)" \
  bash -c 'command grep -qE "[A-Za-z]/[A-Za-z]" "$1"' _ "$art"
assert_rc 0 "closed-vocabulary and prose relative tokens never fire (the sweep's scope is the design's: absolute paths + path:NN pins; free-prose refs are the reviewer's)" -- \
  gates_env_sweep "$ws" "$art"

echo "-- a project gate attests the COMMAND it ran, not only a log path --"
# Four conformance records across four slices described a composite
# `<base>..HEAD` acceptance close while every attested record was a
# single-commit run and the base sha appeared in neither log. A reader checking
# that claim had to open a log file, because the permanent surface carried only
# `log=<path>`. The workflow runs project.kv's string verbatim and passes no
# arguments, so the range that ran is whatever that string covers by default —
# which is the fact the surface was missing.
wsc=$(mk_ws "$base" gatecmd "$repo" "$branch")
printf 'acceptance=echo RANGE-MARKER-abc123..HEAD\n' >> "$wsc/project.kv"
assert_rc 0 "the declared acceptance gate runs" -- gates_project "$wsc" acceptance
grow="$( . "$RS/lib/state.sh"; state_get "$wsc" gates | command grep 'gate=acceptance' | tail -1)"
glog=$(printf '%s' "$grow" | command grep -oE 'log=[^ ]+' | cut -d= -f2-)
precond "the row names its log" test -n "$glog"
head -1 "$glog" | command grep -qF '$ echo RANGE-MARKER-abc123..HEAD' \
  && ok "the LOG's first line is the invocation, verbatim — the file a reader opens now says what produced it" \
  || bad "log head: $(head -2 "$glog" 2>/dev/null | tr '\n' ' ')"
printf '%s' "$grow" | command grep -qE 'cmd_fp=[0-9a-f]{8}( |$)' \
  && ok "the ROW carries a fixed-width fingerprint (same idiom as dirty=), never the foreign string itself" \
  || bad "acceptance row: $grow"
command grep -q 'RANGE-MARKER' <<< "$grow" \
  && bad "the project's own command string is inlined into a field-scanned record — the sidecar lesson park() already paid for" \
  || ok "and no project-controlled bytes reach the record's key=value region"
# The fingerprint's whole job: telling one declaration from another.
fp1=$(printf '%s' "$grow" | command grep -oE 'cmd_fp=[0-9a-f]{8}' | cut -d= -f2)
printf 'acceptance=false\n' >> "$wsc/project.kv"
assert_rc 1 "a failing gate still fails" -- gates_project "$wsc" acceptance
grow2="$( . "$RS/lib/state.sh"; state_get "$wsc" gates | command grep 'gate=acceptance' | tail -1)"
fp2=$(printf '%s' "$grow2" | command grep -oE 'cmd_fp=[0-9a-f]{8}' | cut -d= -f2)
[ -n "$fp2" ] && [ "$fp1" != "$fp2" ] \
  && ok "a CHANGED declaration gives a different fingerprint ($fp1 -> $fp2) — 'did project.kv move mid-topic' is answerable from the surface alone" \
  || bad "fingerprints '$fp1' / '$fp2' — the row cannot distinguish two declarations"
glog2=$(printf '%s' "$grow2" | command grep -oE 'log=[^ ]+' | cut -d= -f2-)
head -1 "$glog2" | command grep -qF '$ false' \
  && ok "and the FAIL path logs its invocation too (a postmortem's first question is what was run)" \
  || bad "failing log head: $(head -2 "$glog2" 2>/dev/null | tr '\n' ' ')"

echo "-- own-tree caps sweep: the workflow's own files obey the declared caps --"
sweep_tree() { # root -> violation lines
  local r=$1 f n
  for f in "$r"/runtime-docs/cards/*.md; do
    [ -f "$f" ] || continue; n=$(wc -l < "$f")
    [ "$n" -le 300 ] || echo "hot card over 300: $f ($n)"
  done
  # ENUMERATED FROM THE DIRECTORY, never a hand-listed set: this loop named
  # protocol/review-standards/operations by filename until 2026-09-08, so the
  # fourth top-level doc to land (commit-messages.md, the commit-message-contract
  # extraction) would
  # have grown uncapped while the sweep reported clean. 30-closure's WFDOCS
  # corpus was already a directory read for exactly this reason; the two now
  # agree, and a doc added tomorrow is capped the day it lands.
  for f in "$r"/runtime-docs/*.md; do
    [ -f "$f" ] || continue; n=$(wc -l < "$f")
    [ "$n" -le 800 ] || echo "reference doc over 800: $f ($n)"
  done
  for f in "$r"/runtime-scripts/*.sh "$r"/runtime-scripts/*/*.sh; do
    [ -f "$f" ] || continue; n=$(wc -l < "$f")
    [ "$n" -le 800 ] || echo "runtime script over 800: $f ($n)"
  done
  for f in "$r"/self-check/*.sh "$r"/self-check/*/*.sh; do
    [ -f "$f" ] || continue; n=$(wc -l < "$f")
    [ "$n" -le 1000 ] || echo "self-check file over 1000: $f ($n)"
  done
}
nf=$( { ls "$WF_ROOT"/runtime-docs/cards/*.md "$WF_ROOT"/runtime-scripts/*.sh \
        "$WF_ROOT"/runtime-scripts/*/*.sh "$WF_ROOT"/self-check/*.sh \
        "$WF_ROOT"/self-check/*/*.sh 2>/dev/null || true; } | command grep -c .)
precond "the sweep sees N>=20 own-tree files (saw $nf)" test "$nf" -ge 20
# Per-family, not just in total: a family whose glob matches nothing live
# sweeps nothing while the total floor stays satisfied — the half-empty
# collection reading green. And the three NAMED reference docs are skipped
# silently by the sweep's own existence guard, so their absence needs its own
# precond rather than a count.
nf_cards=$(ls "$WF_ROOT"/runtime-docs/cards/*.md 2>/dev/null | command grep -c . || true)
nf_scripts=$(ls "$WF_ROOT"/runtime-scripts/*.sh "$WF_ROOT"/runtime-scripts/*/*.sh 2>/dev/null | command grep -c . || true)
nf_sc=$(ls "$WF_ROOT"/self-check/*.sh "$WF_ROOT"/self-check/*/*.sh 2>/dev/null | command grep -c . || true)
precond "every glob family is non-empty live (cards $nf_cards, scripts $nf_scripts, self-check $nf_sc)" \
  bash -c '[ "$1" -ge 1 ] && [ "$2" -ge 1 ] && [ "$3" -ge 1 ]' _ "$nf_cards" "$nf_scripts" "$nf_sc"
precond "the three named reference docs exist for the cap sweep (protocol, review-standards, operations)" \
  test -f "$WF_ROOT"/runtime-docs/protocol.md -a -f "$WF_ROOT"/runtime-docs/review-standards.md -a -f "$WF_ROOT"/runtime-docs/operations.md
# and the family is floored like every other: a globbed loop over an emptied
# directory sweeps nothing and reads clean.
nf_refs=$(ls "$WF_ROOT"/runtime-docs/*.md 2>/dev/null | command grep -c . || true)
precond "the reference-doc family is non-empty live (saw $nf_refs top-level docs)" \
  test "${nf_refs:-0}" -ge 3
viol=$(sweep_tree "$WF_ROOT")
[ -z "$viol" ] \
  && ok "every own-tree file is under its declared cap (cards<=300, refs<=800 over all $nf_refs top-level docs, scripts<=800, self-check<=1000)" \
  || bad "own-tree cap violations: $viol"
# One known-bad per FAMILY, so each loop of the sweep is proved able to fire
# on its own subject — a loop whose fixture never exercises it is a loop
# nobody notices rotting.
fake=$(sc_tmpdir)
mkdir -p "$fake/runtime-docs/cards" "$fake/runtime-scripts" "$fake/self-check"
seq 1 301 > "$fake/runtime-docs/cards/bloated.md"
seq 1 801 > "$fake/runtime-docs/protocol.md"
# a reference doc whose NAME was never in the hand-list the loop used to carry:
# with the old three-filename loop this file read clean at 801 lines, so this
# fixture is what distinguishes a directory read from a hand-listed set. If it
# ever stops firing, the loop has regressed to naming its own corpus.
seq 1 801 > "$fake/runtime-docs/never-hand-listed.md"
seq 1 801 > "$fake/runtime-scripts/fat.sh"
seq 1 1001 > "$fake/self-check/heavy.sh"
viol=$(sweep_tree "$fake")
for want in bloated protocol.md never-hand-listed.md fat.sh heavy.sh; do
  printf '%s\n' "$viol" | command grep -q "$want" \
    && ok "the sweep flags an over-cap $want (that family's known-bad fires)" \
    || bad "own-tree sweep vacuous on $want — an over-cap file passed unseen"
done

echo "-- env sweep: dead absolute + dead/over-EOF pins fire; bare basenames ignored --"
mkdir -p "$repo/sub"; echo x > "$repo/sub/real.txt"
cat > "$art" <<EOF
# artifact
see the absolute $repo/sub/real.txt line and the pinned sub/real.txt:1 read.
a bare basename like missing.md is NOT a candidate (no slash).
EOF
assert_rc 0 "resolving absolute path + in-range pin PASS (bare basename correctly ignored)" -- \
  gates_env_sweep "$ws" "$art"
cand=$(state_get "$ws" gates | command grep 'gate=env_sweep' | tail -1 | command grep -oE 'candidates=[0-9]+' | cut -d= -f2)
precond "the sweep saw N>0 candidates (saw ${cand:-0}) — not a vacuous pass" \
  test "${cand:-0}" -ge 2
echo "also see $repo/sub/does-not-exist.txt here." >> "$art"
assert_rc 1 "a dead ABSOLUTE path token FIRES" -- gates_env_sweep "$ws" "$art"
assert_out_has "does not resolve" "dead token named"
sed -i '$d' "$art"
# The absolute arm reads a SECOND segment as the claim: a lone `/word` in prose
# (a fraction, an option name, a bare directory) was 8 of the 12 post-gate hits
# over six archived trees — none of them a
# citation, and nothing a delivery cites lives at the filesystem root.
echo "prose: the /Report option, a /fuzz/ directory, returns /nullptr, and 3/4 of /selfcheck/ — none a path claim." >> "$art"
assert_rc 0 "one-segment absolute tokens in prose do NOT fire (/Report, /fuzz/, /nullptr, /selfcheck/)" -- \
  gates_env_sweep "$ws" "$art"
cand2=$(state_get "$ws" gates | command grep 'gate=env_sweep' | tail -1 | command grep -oE 'candidates=[0-9]+' | cut -d= -f2)
[ "${cand2:-0}" = "${cand:-0}" ] \
  && ok "…and they are not counted as candidates either (candidates=$cand2, unchanged): prose is prose, not a passing claim" \
  || bad "prose tokens were counted as candidates: $cand -> $cand2"
sed -i '$d' "$art"
echo "a two-segment dead absolute /nowhere/at-all still fires." >> "$art"
assert_rc 1 "a dead two-segment absolute token (/a/b) FIRES (the second segment is the claim)" -- \
  gates_env_sweep "$ws" "$art"
sed -i '$d' "$art"
echo "a pinned one-segment absolute /Report:12 fires (a pin is always a claim)." >> "$art"
assert_rc 1 "a one-segment absolute token WITH a :NN pin FIRES (a pin is always a claim)" -- \
  gates_env_sweep "$ws" "$art"
sed -i '$d' "$art"
echo "pinned read: sub/real.txt:99 (file has 1 line)" >> "$art"
assert_rc 1 "a path:NN pin beyond EOF FIRES" -- gates_env_sweep "$ws" "$art"
assert_out_has "pins line 99" "over-EOF pin named"
sed -i '$d' "$art"
echo "a dead pinned citation lib/nowhere.sh:12 also fires." >> "$art"
assert_rc 1 "a dead :NN-pinned RELATIVE token FIRES (a pin is always a claim)" -- \
  gates_env_sweep "$ws" "$art"

echo "-- structure gate --"
tpl="$base/tpl.md"; doc="$base/doc.md"
printf '# review\n## provenance\n## findings\n## non-coverage\n' > "$tpl"
printf '# review\n## provenance\ntext\n## findings\nmore\n## non-coverage\n' > "$doc"
assert_rc 0 "doc matching template heading order PASSES" -- gates_structure "$ws" "$doc" "$tpl"
printf '# review\n## findings\n## provenance\n## non-coverage\n' > "$doc"
assert_rc 1 "out-of-order headings FIRE (a structure mismatch is a draft)" -- \
  gates_structure "$ws" "$doc" "$tpl"
# `^#+ ` plus an explicit depth test rather than `^#{1,6} `: mawk has no ERE
# intervals, and the sibling precondition below counts with `grep -cE`, which
# does — so the two must agree by construction, not by both happening to be gawk.
awk '{ if ($0 ~ /^#+ /) { match($0, /^#+/); if (RLENGTH <= 6) { print "prose mention of: " $0; next } } print }' "$tpl" > "$doc"
precond "the demoted doc has ZERO real heading lines (whole file, grep '^#{1,6} ')" \
  bash -c '[ "$(command grep -cE "^#{1,6} " "$1")" -eq 0 ]' _ "$doc"
assert_rc 1 "template headings quoted inside prose FIRE (a substring match is not a section)" -- \
  gates_structure "$ws" "$doc" "$tpl"
{ echo '```'; cat "$tpl"; echo '```'; } > "$doc"
assert_rc 1 "headings living ONLY inside a fenced code block FIRE (quoted data is not structure)" -- \
  gates_structure "$ws" "$doc" "$tpl"
{ cat "$tpl"; echo; echo '```'; echo '# stray fenced heading'; echo '```'; } > "$doc"
assert_rc 0 "real headings with fenced extras still PASS (the fence only removes, never reorders)" -- \
  gates_structure "$ws" "$doc" "$tpl"

echo "-- fences are quoted data for claims and the env sweep too --"
{ echo '# artifact with only a FENCED claims table'; echo '```'
  echo '## claims'; echo '| type | claim | anchor | echo | range | command |'
  echo '|---|---|---|---|---|---|'; echo '| note | fenced | - | - | - | - |'; echo '```'; } > "$art"
assert_rc 1 "a claims table living only inside a fence FIRES (the artifact still owes a real one)" -- \
  gates_claims "$ws" "$art"
{ echo '# review quoting a transcript'; echo '```'
  echo "\$ ls $repo/sub/does-not-exist-anymore.txt"; echo '```'
  echo "the live citation $repo/sub/real.txt resolves."; } > "$art"
assert_rc 0 "a dead absolute path QUOTED in a fenced transcript does not fire (evidence is data; the live citation still checks)" -- \
  gates_env_sweep "$ws" "$art"
printf 'no headings\n' > "$tpl"
assert_rc 2 "template without headings REFUSED (vacuous check refused)" -- \
  gates_structure "$ws" "$doc" "$tpl"

echo "-- the SHIPPED spec template is gateable: its own headings, and the H1 that used to block it --"
# The spec was the one templated artifact with no structure gate, and the cause
# was mechanical: gates_structure compares headings VERBATIM and the template's
# H1 was `# spec — slice <nn>: <slice title>`, which no filled-in spec can match.
# These arms pin the property that keeps it gateable, so a future edit that
# re-parameterises any spec-template heading reds here rather than at a live emit.
spectpl="$WF_ROOT/runtime-docs/templates/spec.md"
precond "the shipped spec template exists and declares headings" \
  bash -c '[ "$(command grep -cE "^#{1,6} " "$1")" -ge 8 ]' _ "$spectpl"
command grep -q '<' <<< "$(command grep -E '^#{1,6} ' "$spectpl")" \
  && bad "a spec-template heading carries a placeholder — verbatim matching makes it unsatisfiable: $(command grep -E '^#{1,6} ' "$spectpl" | command grep '<' | head -1)" \
  || ok "every spec-template heading is a constant (no placeholder survives into a heading)"
# a document built from the template's own headings must PASS, or the template
# forbids the very structure it prescribes
command grep -E '^#{1,6} ' "$spectpl" > "$doc"
assert_rc 0 "a doc carrying exactly the spec template's headings PASSES (the template permits its own shape)" -- \
  gates_structure "$ws" "$doc" "$spectpl"
# and the measured historical defect must FIRE: a section inserted so that a
# later contract section is renumbered away from where every reader looks
sed 's/^## 8\. refine log/## 8. decisions — Class A\n## 9. refine log/' "$doc" > "$doc.renum"
assert_rc 1 "a renumbered contract section FIRES (the one shipped spec in four topics that fails, reproduced)" -- \
  gates_structure "$ws" "$doc.renum" "$spectpl"
# additive tolerance is the property that makes this safe to run live: shipped
# specs add their own subsections and must keep passing
awk '{print} /^## 2\./{print "### 2.1 a subsection a real spec adds"}' "$doc" > "$doc.sub"
assert_rc 0 "extra subsections between template headings still PASS (shipped specs do this)" -- \
  gates_structure "$ws" "$doc.sub" "$spectpl"

echo "-- project gates run verbatim; undeclared = named SKIP --"
assert_rc 0 "undeclared gate records SKIP, never silently passes as green" -- \
  gates_project "$ws" build
assert_out_has "not declared" "SKIP is named"
echo "build=true" >> "$ws/project.kv"
assert_rc 0 "declared gate command runs verbatim and passes" -- gates_project "$ws" build
sed -i 's/^build=true/build=false/' "$ws/project.kv"
assert_rc 1 "failing gate command FAILS with rc and log path" -- gates_project "$ws" build
assert_out_has "log:" "failure points at the log"
assert_rc 2 "unknown gate name refused (closed set)" -- gates_project "$ws" deploy

echo "-- binding dispatch: a doc-bound slice's evidence comes from the DOC checkout --"
# The six gate functions and the reviewer's CLI form carry no slice argument:
# the active slice comes from the stage surface, the binding turns it into a
# checkout (two-layer resolution). Everything attested must then pin THAT repo.
read -r drepo dbranch < <(mk_doc_repo "$base/docrepo")
wsd=$(mk_ws "$base" docbound "$repo" "$branch")
printf 'doc.repo=%s\ndoc.branch=%s\nacceptance=touch %s/ACCEPTANCE_RAN\n' \
  "$drepo" "$dbranch" "$base" >> "$wsd/project.kv"
( . "$RS/lib/state.sh"
  printf 'id=01 status=active risk=low repo=code title=c rederive=0\nid=02 status=active risk=low repo=doc title=d rederive=0\n' \
    | state_set "$wsd" slices ferry ) > /dev/null
mkdir -p "$wsd/src"; seq 1 5 > "$wsd/src/f.sh"
precond "the two checkouts have DIFFERENT HEADs (else the pin assertion is vacuous)" \
  bash -c '[ "$(git -C "$1" rev-parse HEAD)" != "$(git -C "$2" rev-parse HEAD)" ]' _ "$repo" "$drepo"
activate_stage "$wsd" impl 02 1 nDOC
assert_rc 0 "a gate runs while the doc-bound slice is active" -- gates_caps "$wsd" "$wsd/src/f.sh"
rec=$(state_get "$wsd" gates | tail -1)
printf '%s\n' "$rec" | command grep -qF " sha=$(git -C "$drepo" rev-parse HEAD) " \
  && ok "the attestation pins the DOC repo's HEAD (evidence binds the slice's own checkout)" \
  || bad "attestation pinned the wrong checkout: $rec"
activate_stage "$wsd" impl 01 1 nCOD
assert_rc 0 "the same gate on the code-bound slice" -- gates_caps "$wsd" "$wsd/src/f.sh"
state_get "$wsd" gates | tail -1 | command grep -qF " sha=$(git -C "$repo" rev-parse HEAD) " \
  && ok "and pins the CODE repo's HEAD there (dispatch follows the binding, both directions)" \
  || bad "code-bound attestation: $(state_get "$wsd" gates | tail -1)"

echo "-- every attestation names the slice it was recorded under --"
# The gates surface is handed to postcheck reviewers; without a slice field
# a topic's whole gate history rides every review (560 rows by slice 17 on
# the pilot) and no consumer can scope it. The field is the stage surface's
# active slice; a workspace with no active stage records the literal none.
state_get "$wsd" gates | tail -1 | command grep -qE '(^| )slice=01( |$)' \
  && ok "the code-bound slice's attestation carries slice=01" \
  || bad "attestation lacks slice=01: $(state_get "$wsd" gates | tail -1)"
state_get "$wsd" gates | command grep -E '(^| )slice=02( |$)' | command grep -qF " sha=$(git -C "$drepo" rev-parse HEAD) " \
  && ok "the doc-bound slice's attestation carries slice=02 (the field follows the active slice, not a constant)" \
  || bad "no slice=02 row pinned to the doc repo among: $(state_get "$wsd" gates | tail -3)"
wsn=$(mk_ws "$base" noslice "$repo" "$branch")
mkdir -p "$wsn/src"; seq 1 3 > "$wsn/src/g.sh"
assert_rc 0 "a gate runs with no active stage at all" -- gates_caps "$wsn" "$wsn/src/g.sh"
state_get "$wsn" gates | tail -1 | command grep -qE '(^| )slice=none( |$)' \
  && ok "with no active stage the row says slice=none (never an empty field)" \
  || bad "no-stage attestation: $(state_get "$wsn" gates | tail -1)"

echo "-- D-i: a doc-bound slice records a STRUCTURAL acceptance SKIP; the code command never runs --"
activate_stage "$wsd" impl 02 1 nDOC2
assert_rc 0 "gates_project acceptance returns 0 for a doc-bound slice" -- gates_project "$wsd" acceptance
assert_out_has "doc-bound" "the SKIP names its structural reason, not a missing declaration"
state_get "$wsd" gates | command grep 'gate=acceptance' | tail -1 | command grep -q 'result=SKIP' \
  && ok "the SKIP is attested in the gates surface (named, never silent)" \
  || bad "no SKIP record: $(state_get "$wsd" gates | command grep 'gate=acceptance' | tail -1)"
[ ! -e "$base/ACCEPTANCE_RAN" ] \
  && ok "TRIPWIRE: the project's acceptance command was NEVER executed for the doc slice" \
  || bad "the code repo's acceptance command ran for a doc-bound slice (D-i broken)"
activate_stage "$wsd" impl 01 1 nCOD2
assert_rc 0 "the same call on a CODE-bound slice runs the declared command (good direction)" -- \
  gates_project "$wsd" acceptance
[ -e "$base/ACCEPTANCE_RAN" ] \
  && ok "the tripwire fires for the code slice — the SKIP above was binding-driven, not a dead command" \
  || bad "the acceptance command never ran at all; the tripwire proves nothing"

echo "-- cross-repo citations: binding checkout first, the other checkout as fallback --"
mkdir -p "$drepo/docs"; echo "shipped note" > "$drepo/docs/note.md"
echo "code side" > "$repo/only-in-code.txt"
activate_stage "$wsd" impl 02 1 nDOC3
[ "$(_gates_resolve_path "$wsd" docs/note.md)" = "$drepo/docs/note.md" ] \
  && ok "a doc-bound slice resolves a path in its own checkout" \
  || bad "resolved to '$(_gates_resolve_path "$wsd" docs/note.md)'"
[ "$(_gates_resolve_path "$wsd" only-in-code.txt)" = "$repo/only-in-code.txt" ] \
  && ok "a path living only in the OTHER checkout still resolves (cross-repo citations never dead-link)" \
  || bad "cross-repo fallback missing: '$(_gates_resolve_path "$wsd" only-in-code.txt)'"
assert_rc 1 "a path in neither checkout stays unresolvable (the fallback widens, never blinds)" -- \
  _gates_resolve_path "$wsd" nowhere/at-all.txt

echo "-- commit gate: a doc slice's cu is verified in the doc repo --"
( cd "$drepo" && echo d1 > d1.md && git add d1.md && git commit -qm "docs: add a shipped note" )
dsha=$(git -C "$drepo" rev-parse HEAD)
assert_rc 0 "a commit that exists only in the doc repo passes for the doc-bound slice" -- \
  gates_commit "$wsd" "$dsha"
activate_stage "$wsd" impl 01 1 nCOD3
assert_rc 2 "the same SHA refuses under a code binding (it is no commit there) — repo confusion is loud" -- \
  gates_commit "$wsd" "$dsha"

echo "-- attestation records --"
n=$(state_get "$ws" gates | command grep -c 'v=1')
precond "gates surface accumulated N>0 attested results (saw $n)" test "$n" -ge 10
state_get "$ws" gates | tail -1 | command grep -qE 'sha=[0-9a-f]+' \
  && ok "records pin the repo HEAD sha (staleness mechanically visible)" \
  || bad "gate record carries no sha pin"

check_done
