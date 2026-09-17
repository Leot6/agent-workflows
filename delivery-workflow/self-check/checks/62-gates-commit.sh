#!/usr/bin/env bash
# 62-gates-commit — lib/gates_commit.sh: the commit gate's own family. The
# project's subject regex and trailer policy in both directions, the driver's
# own id axis (a workspace id resolves nowhere in the delivered history and is
# refused by LOOKUP against this topic's planning artifacts, never by a shape
# list), the pipe-in-a-cell refusal, and the amend-advice that depends on where
# the commit sits.
# Extracted from 60-gates when that file reached its own 1000-line cap. The seam
# is not arbitrary: `lib/gates_commit.sh` was itself relocated out of
# `lib/gates.sh` for the same reason, so the check now mirrors the library it
# tests. What stays in 60-gates is the one commit arm that rides the doc-repo
# workspace built for the binding-dispatch tests — its setup is that section's,
# not this file's.
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/fixtures/lib.sh"
. "$RS/lib/state.sh"
. "$RS/lib/gates.sh"

base=$(sc_tmpdir)
read -r repo branch < <(mk_repo "$base/repo")
ws=$(mk_ws "$base" gatetopic "$repo" "$branch")
echo "-- commit gate --"
cd "$repo"
echo c > c.txt; git add c.txt; git commit -qm "feat: add c file" ; sha=$(git rev-parse HEAD)
cd - > /dev/null
assert_rc 0 "conforming subject passes" -- gates_commit "$ws" "$sha"
cd "$repo"; echo d > d.txt; git add d.txt; git commit -qm "Added stuff badly"; badsha=$(git rev-parse HEAD); cd - > /dev/null
assert_rc 1 "non-conforming subject FIRES against the project regex" -- \
  gates_commit "$ws" "$badsha"
assert_out_has "fails project regex" "regex failure named"
assert_rc 2 "a non-commit refuses" -- gates_commit "$ws" 0000000

echo "-- commit gate: a FORBIDDEN trailer fires (the convention's other direction) --"
echo "commit.forbid_trailers=Co-Authored-By" >> "$ws/project.kv"
assert_rc 0 "a clean commit still passes under a forbid declaration (good direction)" -- \
  gates_commit "$ws" "$sha"
( cd "$repo" && echo t1 > t1.txt && git add t1.txt \
  && git commit -qm "feat: unit with a forbidden trailer" -m "Co-Authored-By: Someone <x@y.invalid>" )
fsha=$(git -C "$repo" rev-parse HEAD)
precond "the fixture commit really carries the trailer" \
  bash -c 'git -C "$1" log -1 --format=%B "$2" | command grep -qi "^co-authored-by:"' _ "$repo" "$fsha"
assert_rc 1 "a commit carrying a forbidden trailer FAILS" -- gates_commit "$ws" "$fsha"
assert_out_has "forbidden trailer" "the failure names the prohibition and its source key"
( cd "$repo" && echo t2 > t2.txt && git add t2.txt \
  && git commit -qm "feat: unit with a lowercased forbidden trailer" -m "co-authored-by: someone <x@y.invalid>" )
assert_rc 1 "casing does not evade the prohibition (git trailers are case-insensitive)" -- \
  gates_commit "$ws" "$(git -C "$repo" rev-parse HEAD)"
plat_sed_i '/^commit.forbid_trailers=/d' "$ws/project.kv"
assert_rc 0 "with the declaration removed, the same commit passes (the gate reads the project, never a baked-in list)" -- \
  gates_commit "$ws" "$fsha"

echo "-- commit gate: the workflow's OWN ids never ride into the delivered history --"
# Measured defect: four commits of one topic carried `cu-2`, `DP-2`, `slice 14`
# and a plan anchor — one in the subject line. The ids are the workflow's own,
# put in front of the authoring session by every prompt it is handed, and they
# resolve only inside the topic workspace: in the repo's history they point at
# nothing. Pre-fix, gates_commit read the message for trailers only.
for tok in "cu-2" "DP-2" "slice 14" "slices/07"; do
  ( cd "$repo" && echo "x$RANDOM" > "wsid-${tok//[^A-Za-z0-9]/_}.txt" && git add -A \
    && git commit -qm "feat: land the unit ($tok)" )
  assert_rc 1 "a message naming '$tok' FAILS the commit gate" -- \
    gates_commit "$ws" "$(git -C "$repo" rev-parse HEAD)"
  assert_out_has "resolve only in this topic's own planning and workspace artifacts" \
    "the failure names the class, not just the token"
done
( cd "$repo" && echo body > wsid-body.txt && git add -A \
  && git commit -qm "feat: land the unit" -m "detail lives in $ws/slices/07/spec.md" )
assert_rc 1 "a workspace path in the BODY fails too (the gate reads the whole message)" -- \
  gates_commit "$ws" "$(git -C "$repo" rev-parse HEAD)"
( cd "$repo" && echo ok > wsid-ok.txt && git add -A \
  && git commit -qm "feat: thread the slot through the gate signatures" \
       -m "Documents the accumulator rewrite; cu counts and DP values are unrelated words here." )
assert_rc 0 "prose that merely uses the words (no id shapes) still passes — the gate matches minted ids, not vocabulary" -- \
  gates_commit "$ws" "$(git -C "$repo" rev-parse HEAD)"

echo "-- a claims cell cannot hold a pipe: the row splits and the command truncates --"
# Three anchors (two prechecks and a close-out self-catch) on evidence commands
# nobody could re-run as written. It is not only a reading problem: this gate
# parses with `awk -F'|'`, so `` `$ grep -o a f \| wc -l` `` arrives as NF=9
# with the command cut at the backslash — the gate accepted a shell fragment as
# the evidence. Escaping fixes the RENDER only: `\|` is a literal pipe to ERE
# and an escaped pipe to a shell, while §2 prescribes `grep -o … | wc -l` for
# occurrence counts. So the format forbade what the contract required.
cpipe="$base/claims-pipe.md"
{ echo "# doc"; echo; echo "## claims"; echo
  echo "| type | claim | anchor | echo | range | command |"
  echo "|---|---|---|---|---|---|"
  echo "| count | 7 call sites | - | - | src/mod.c:L1-L20 @ HEAD | \`\$ grep -o x f \\| wc -l\` → 7 |"
} > "$cpipe"
assert_rc 1 "an escaped pipe in a cell FAILS (pre-fix: the truncated fragment passed as evidence)" -- \
  gates_claims "$ws" "$cpipe"
assert_out_has "splits the row" "the failure names the mechanism, not just the character"
assert_out_has "evidence block" "and names where the command belongs instead"

cref="$base/claims-ref.md"
{ echo "# doc"; echo; echo "## claims"; echo
  echo "| type | claim | anchor | echo | range | command |"
  echo "|---|---|---|---|---|---|"
  echo "| count | 7 call sites | - | - | src/mod.c:L1-L20 @ HEAD | \`E1\` → 7 |"
} > "$cref"
assert_rc 1 "a named command with no definition FAILS — a reference that resolves nowhere is not evidence" -- \
  gates_claims "$ws" "$cref"
assert_out_has "resolves nowhere" "the dangling label is named"
printf '\n```\nE1: grep -o x src/mod.c | wc -l\n```\n' >> "$cref"
assert_rc 0 "once the evidence block defines E1, the same table passes — pipes and all, where a pipe is legal" -- \
  gates_claims "$ws" "$cref"

# A SUB-LETTERED label bound silently to the wrong command. The grammar was
# "backtick-optional E followed by digits", matched with -oE and anchored at
# ^ — so `E10b` matched the E10 PREFIX, and when an `E10:` line existed the
# row passed the gate while pointing at E10's command, which is not that row's
# evidence. Measured twice, on two slices: slice 13's spec minted E7a-d and
# E10b for readability — the three E7* failed loudly (no E7: line) and E10b
# PASSED against the kTable-census command while its claim was the registry
# count; slice 14's fix round minted E6b, which would have bound to an
# existing unrelated E6. Both were caught by the author re-running the whole
# table by hand, never by this gate.
# The failure mode is what makes it worth a structural fix rather than a
# convention: an ABSENT label fails loudly, a present-but-wrong one passes
# silently. So the shape is refused instead of truncated.
csub="$base/claims-sublabel.md"
{ echo "# doc"; echo; echo "## claims"; echo
  echo "| type | claim | anchor | echo | range | command |"
  echo "|---|---|---|---|---|---|"
  echo "| count | 12 registry entries | - | - | src/mod.c:L1-L99 @ HEAD | \`E10b\` → 12 |"
  printf '\n```\nE10: grep -c kTable src/mod.c\n```\n'
} > "$csub"
assert_rc 1 "a sub-lettered label FAILS even though its prefix resolves — E10b is not E10" -- \
  gates_claims "$ws" "$csub"
assert_out_has "E10b" "the refusal quotes the label as written"
assert_out_has "E10" "and names the command it would have bound to"
# Known-bad on the other side: the plain label still resolves, so the refusal
# is about the SHAPE and not about the definition being missing.
cok="$base/claims-plainlabel.md"
{ echo "# doc"; echo; echo "## claims"; echo
  echo "| type | claim | anchor | echo | range | command |"
  echo "|---|---|---|---|---|---|"
  echo "| count | 12 registry entries | - | - | src/mod.c:L1-L99 @ HEAD | \`E10\` → 12 |"
  printf '\n```\nE10: grep -c kTable src/mod.c\n```\n'
} > "$cok"
assert_rc 0 "the same table with the plain label passes (the grammar rejects the sub-letter, not the reference)" -- \
  gates_claims "$ws" "$cok"
# A suffix is a suffix whatever character starts it. The first version of this
# grammar compared the leading [A-Za-z0-9] run against the label, which caught
# `E10b` and let `E10-b`, `E10_b` and `E10.b` bind to E10 exactly as before —
# a fix that closed the measured spelling and not the mechanism. The rule is
# about TOKENS: the label is the cell's first word, and the first word must be
# the label exactly.
for suffixed in 'E10-b' 'E10_b' 'E10.b' 'E10b'; do
  csx="$base/claims-sfx.md"
  { echo "# doc"; echo; echo "## claims"; echo
    echo "| type | claim | anchor | echo | range | command |"
    echo "|---|---|---|---|---|---|"
    echo "| count | 12 registry entries | - | - | src/mod.c:L1-L99 @ HEAD | \`$suffixed\` → 12 |"
    printf '\n```\nE10: grep -c kTable src/mod.c\n```\n'
  } > "$csx"
  out=$(gates_claims "$ws" "$csx" 2>&1); rc=$?
  [ $rc -eq 1 ] && command grep -qF "$suffixed" <<< "$out" \
    && ok "'$suffixed' is refused and quoted as written (any suffix character, not just letters)" \
    || bad "'$suffixed' rc=$rc — it binds to E10's command silently: $(printf '%s' "$out" | head -1)"
done

echo "-- handed-over ids: the SHAPE is the candidate, the topic's plan is the verdict --"
# The worst measured instance was `refactor: … per R10-2` — a plan review-round
# anchor, in the SUBJECT. It is not ours to mint, but ours to hand over (PLAN
# rides the manifest), and the project's own gate missed it because its list
# held `R1-` and `R6x-` but not `R10-`. Enumerating shapes is what failed; the
# lookup is what discriminates. These two assertions are the same message
# against two different plans — that difference IS the mechanism.
( cd "$repo" && echo anchor > anchor.txt && git add anchor.txt \
  && git commit -qm "refactor: rename CandidateFlightSource to AssemblyRole per R10-2" )
anchsha=$(git -C "$repo" rev-parse HEAD)
printf '# fixture plan\nowner ruling R10-2 names AssemblyRole the single source.\n' \
  > "$ws/../plan.md"
assert_rc 1 "an anchor the topic's PLAN also names FAILS (it resolves in the workspace, nowhere else)" -- \
  gates_commit "$ws" "$anchsha"
assert_out_has "R10-2" "the failure names the token it found"
# And names the same CLASS the minted axis does. The two axes are merged before
# `_gates_ws_ids` returns, so the one sentence the refused reader gets must be
# true of both — and it was not: it said "workflow-internal id … resolves only
# inside the topic workspace … the cu→SHA mapping is the remedy", three clauses
# each false for an id the PLAN handed over. It survived because every fixture
# asserting the class name was an axis-1 fixture, so the wrong name was accurate
# for all of them. This assertion is what makes the class name answerable to the
# axis that actually fired in the field.
assert_out_has "resolve only in this topic's own planning and workspace artifacts" \
  "and the class it names is true for the HANDED-OVER axis too (one sentence, two axes)"
command grep -qF "workflow-internal" <<< "$SC_OUT" \
  && bad "the handed-over axis is still called workflow-internal — the workflow never minted this id" \
  || ok "and does not miscall it ours to mint (the plan minted it; we only handed it over)"
printf '# fixture plan\none slice of mock work.\n' > "$ws/../plan.md"
assert_rc 0 "the SAME commit passes once the plan does not name it — shape alone never decides" -- \
  gates_commit "$ws" "$anchsha"
# The lookup narrows to the artifacts it can read, and narrowing must be NAMED:
# with the plan gone, a token that resolves only there passes as a domain word
# and the verdict reads clean. (The path is hard-coded with no adapter key, so a
# renamed boundary artifact is exactly how this happens — logged DEFER.) Said
# only when it could change the verdict: candidates are in hand.
mv "$ws/../plan.md" "$ws/../plan.md.away"
assert_rc 0 "with the plan gone the same anchor message PASSES (nothing left to resolve it against)" -- \
  gates_commit "$ws" "$anchsha"
assert_out_has "WITHOUT" "and the narrowing is NAMED, not silent — the gate says what it could not read"
assert_out_has "plan.md" "naming the artifact it wanted"
( cd "$repo" && echo nocand > nocand.txt && git add -A \
  && git commit -qm "chore: tidy the accumulator loop" )
# FLOOR FOR THE ABSENCE VERDICT BELOW — the suite's standing duty
# ("every future absence verdict owes its floor or positive pin in the same
# commit that writes it"), which this arm was written after and did not carry.
# $SC_OUT below is EMPTY, and empty is BOTH the correct output for a clean commit
# AND what a gate that fell over would leave: the absence of "WITHOUT" cannot by
# itself tell the two apart. So the pin is a DISCRIMINATING PAIR — same gate,
# same plan-away fixture state, one variable changed (which commit) — run
# adjacent to the verdict it floors rather than four lines and a repo mutation
# away, so a reader can see the pairing without reconstructing it. Measured with
# a temporary probe while writing this: the pin's $SC_OUT is 317 bytes and the
# arm's is 0.
assert_rc 0 "positive pin: the same gate, same plan-away state, on the commit that DOES carry a candidate" -- \
  gates_commit "$ws" "$anchsha"
command grep -qF "WITHOUT" <<< "$SC_OUT" \
  && ok "positive pin: the notice DOES fire where the plan's absence changes the verdict — the construct below can see it" \
  || bad "the notice does not fire even where the plan's absence CHANGES the verdict — the arm below would be blind, not merely silent"
assert_rc 0 "a message carrying NO anchor candidate passes with the plan still gone" -- \
  gates_commit "$ws" "$(git -C "$repo" rev-parse HEAD)"
command grep -qF "WITHOUT" <<< "$SC_OUT" \
  && bad "the notice fired where the plan's absence could change nothing — that is noise, not a name" \
  || ok "and there it says nothing (the notice is verdict-scoped, not chatter)"
# The charter is the second planning input the lookup reads, and the one it
# had never actually opened: the path it looked at (`slices/00/charters.md`)
# is not where split writes it (`<ws>/charters.md` — stages.tsv, owed.sh,
# compose.sh, record.sh and every live topic agree), so an id that only the
# charter hands over passed as a domain word. Plan still away: the charter
# alone must carry the verdict.
printf '# charters\n\nslice 03 executes review-round anchor R10-2 as ruled.\n' > "$ws/charters.md"
assert_rc 1 "an anchor only the CHARTER names FAILS (the lookup reads the charter where split writes it)" -- \
  gates_commit "$ws" "$anchsha"
assert_out_has "R10-2" "the failure names the token the charter handed over"
rm -f "$ws/charters.md"
mv "$ws/../plan.md.away" "$ws/../plan.md"
( cd "$repo" && echo dom > dom.txt && git add dom.txt \
  && git commit -qm "fix: decode UTF-8 and drop the SHA-1 path" )
assert_rc 0 "domain tokens of the same shape (UTF-8, SHA-1) pass with no allowlist anywhere" -- \
  gates_commit "$ws" "$(git -C "$repo" rev-parse HEAD)"
# A ROUTE VERDICT quoted in a message, with the plan carrying the identical line
# so a lookup WOULD resolve it. Passing therefore proves the lane token never
# became a CANDIDATE — which is the property `config-and-adapters.md` §3's
# route= key rests on, and the one worth pinning rather than re-deriving from
# the regex by eye: the candidate shape needs a hyphen followed by digits, and
# `R2` / `direct` / `planning+delivery` have none. Stated so the boundary is not
# read as wider than it is: a project that chose a HYPHENATED lane code (`R-2`)
# would make it a candidate, judged by lookup like every other handed-over id —
# correctly, since such a code resolves only in a workspace the delivered
# history outlives. That is the designed behaviour, not a gap.
printf '# fixture plan\nroute: R2 — Q1 yes; Q2 yes; Q3 no: two repos\n\none slice of mock work.\n' \
  > "$ws/../plan.md"
( cd "$repo" && echo lane > lane.txt && git add lane.txt \
  && git commit -qm "chore: record the topic verdict route: R2 in the adapter" )
assert_rc 0 "a message quoting the route verdict passes though the PLAN carries the same line (a lane token is not an anchor candidate)" -- \
  gates_commit "$ws" "$(git -C "$repo" rev-parse HEAD)"
printf '# fixture plan\none slice of mock work.\n' > "$ws/../plan.md"

echo "-- the fix line matches WHERE the commit sits (an amend only reaches the tip) --"
# The emit door judges EVERY landed cu of the slice, so at most one commit it
# fails can be amended at all. Before this, every message-class failure printed
# the same "amend the message and re-register" — which rewrites the TIP and
# leaves the named commit standing. Two measured instances of that instruction
# being followed: a close-out subject sweep that ended in a hand rewrite of the
# branch, and a maintainer amend that landed on a concurrent writer's commit.
( cd "$repo" && echo tipfail > tipfail.txt && git add -A \
  && git commit -qm "feat: land the unit for cu-9" )
tipsha=$(git -C "$repo" rev-parse HEAD)
assert_rc 1 "a failing message on the TIP fails" -- gates_commit "$ws" "$tipsha"
assert_out_has "IS the tip" "the tip arm offers the amend — the one position where it is true"
( cd "$repo" && echo a1 > above1.txt && git add -A && git commit -qm "feat: land a later unit" \
  && echo a2 > above2.txt && git add -A && git commit -qm "feat: land one more later unit" )
assert_rc 1 "the SAME commit still fails with two units landed on top" -- \
  gates_commit "$ws" "$tipsha"
assert_out_has "2 commit(s) BELOW the tip" "the buried arm counts exactly what a rewrite renumbers"
command grep -qF "IS the tip" <<< "$SC_OUT" \
  && bad "the buried commit was told to amend as well — the arms must be exclusive" \
  || ok "and it is NOT told to amend (following that would rewrite an innocent tip)"
( cd "$repo" && git checkout -q -b sidelane && echo s > side.txt && git add -A \
  && git commit -qm "feat: land a unit for cu-9 on another lane" )
sidesha=$(git -C "$repo" rev-parse HEAD)
( cd "$repo" && git checkout -q "$branch" )
precond "the side commit is really unreachable from the checked-out branch" \
  bash -c '! git -C "$1" merge-base --is-ancestor "$2" HEAD' _ "$repo" "$sidesha"
assert_rc 1 "a failing commit HEAD cannot reach fails" -- gates_commit "$ws" "$sidesha"
assert_out_has "is not on '$branch'" "the third arm names the real obstacle: the wrong branch is checked out"
# An amend rewrites HEAD; what ships is the DECLARED branch. Where those two are
# not one ref, no sentence about this commit's position helps — and comparing
# shas cannot see it: a HEAD detached AT the tip reads identical, and is exactly
# where an amend leaves the branch behind. (Self-audit of the commit that added
# the three arms above: it answered "IS the tip" to a detached checkout.)
( cd "$repo" && git checkout -q --detach HEAD )
precond "HEAD is really detached AT the branch tip (the sha-identical case a sha test cannot see)" \
  bash -c '! git -C "$1" symbolic-ref -q HEAD > /dev/null && [ "$(git -C "$1" rev-parse HEAD)" = "$(git -C "$1" rev-parse "$2")" ]' _ "$repo" "$branch"
assert_rc 1 "the same failing commit still fails while HEAD is detached" -- \
  gates_commit "$ws" "$tipsha"
assert_out_has "HEAD is detached" "the advice names the detachment BEFORE any claim about position"
command grep -qF "BELOW the tip" <<< "$SC_OUT" \
  && bad "a detached checkout was still given position advice — an amend there moves HEAD off the branch" \
  || ok "and it gets no position advice at all (position is meaningless off the branch)"
( cd "$repo" && git checkout -q sidelane )
assert_rc 1 "a failing commit judged while another branch is checked out fails" -- \
  gates_commit "$ws" "$sidesha"
assert_out_has "delivers '$branch'" "the advice names the branch this slice delivers, not the one in hand"
( cd "$repo" && git checkout -q "$branch" )
( cd "$repo" && seq 1 600 | sed 's/^/line /' > bulk.txt && git add -A \
  && git commit -qm "feat: land a large but well-named unit" )
assert_rc 1 "a clean message over the diff cap still FAILS" -- \
  gates_commit "$ws" "$(git -C "$repo" rev-parse HEAD)"
assert_out_has "cap_exceeded" "the cap failure is named"
command grep -qF "fix:" <<< "$SC_OUT" \
  && bad "a cap failure carried a message-rewrite fix line — rewording changes no diff" \
  || ok "a cap-only failure carries no fix line (the remedy is a re-split, not a reword)"


check_done
