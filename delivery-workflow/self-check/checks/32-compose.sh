#!/usr/bin/env bash
# 32-compose — lib/compose.sh's HAND-OVER half (the fingerprint half is
# 70-fingerprint; 30-closure is at its own cap and could not absorb this).
#
# One mechanism: the previous slice's turnover is the only author artifact
# stages.tsv hands to a LATER slice, so it is the only one that ages between
# writing and reading while colleagues move the branch it describes. Compose
# re-resolves its commit references at hand-over and annotates the volatile
# header. Arms here pin every decision that function makes:
#   clean verdict · stale verdict names the SHA · the tip is the PREVIOUS
#   slice's binding (two-repo) · non-commit hex is never flagged · an
#   unresolvable tip reads UNCHECKED, never clean · no prev turnover is silent.
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/fixtures/lib.sh"
. "$RS/lib/state.sh"
. "$RS/lib/compose.sh"

base=$(sc_tmpdir)
read -r repo branch < <(mk_repo "$base/repo")
read -r drepo dbranch < <(mk_doc_repo "$base/docrepo")
ws=$(mk_full_ws "$base" cmptopic "$repo" "$branch")
outd=$(sc_tmpdir)
printf 'doc.repo=%s\ndoc.branch=%s\n' "$drepo" "$dbranch" >> "$ws/project.kv"

# Two more commits on the code branch; the turnover of slice 01 cites both.
for n in 1 2; do
  echo "line $n" >> "$repo/base.txt"
  git -C "$repo" commit -qam "feat: fixture unit $n"
done
c1=$(git -C "$repo" rev-parse HEAD~1)
c2=$(git -C "$repo" rev-parse HEAD)
tree=$(git -C "$repo" rev-parse 'HEAD^{tree}')
precond "fixture cut two distinct commits" test "$c1" != "$c2"
precond "fixture tree hash is not a commit id" test "$tree" != "$c2"

index() { printf '%s\n' "$1" | state_set "$ws" slices ferry > /dev/null; }
turnover() { # body -> writes slice 01's turnover
  mkdir -p "$ws/slices/01"; printf '%s\n' "$1" > "$ws/slices/01/turnover.md"
}
hdr() { # slice -> the prev-turnover header line of a freshly composed spec prompt
  compose_prompt "$ws" spec "$1" 1 1 "n0nce" cold "$outd/spec.md" > /dev/null 2>&1
  command grep -m1 '^prev-turnover:' "$outd/spec.md" || true
}

index 'id=01 status=done risk=low repo=code title=a rederive=0
id=02 status=active risk=low repo=code title=b rederive=0'
turnover "branch $branch, tip $c2, units resolving as $c1 -> $c2 (tree $tree)"

echo "-- clean reading: every cited commit still on the branch --"
line=$(hdr 02)
precond "a prev-turnover line was rendered at all" test -n "$line"
# FLOOR: a turnover citing NO resolvable commit would also read "all still on"
# — the count is what makes the clean verdict mean anything.
command grep -qE 'slice 01 — [1-9][0-9]* commit reference' <<< "$line" \
  && ok "clean reading names a NON-ZERO count of checked commit references" \
  || bad "clean reading has no non-zero count — a turnover citing nothing would read identically: $line"
command grep -q "all still on $branch" <<< "$line" \
  && ok "clean reading names the branch the references were tested against" \
  || bad "clean reading does not name the branch: $line"
command grep -q "$tree" <<< "$line" \
  && bad "the TREE hash was counted as a commit reference: $line" \
  || ok "a tree hash in the turnover is not judged (only tokens resolving to a COMMIT are)"

echo "-- stale reading: the branch moved under a written turnover --"
git -C "$repo" reset -q --hard "$c1"
line=$(hdr 02)
command grep -q WARNING <<< "$line" \
  && ok "a reference that fell off the branch turns the verdict to WARNING" \
  || bad "history rewritten under the turnover and the header still reads clean: $line"
command grep -q "$c2" <<< "$line" \
  && ok "the WARNING NAMES the off-branch commit (not just a count)" \
  || bad "WARNING does not name $c2: $line"
command grep -q "$c1" <<< "$line" \
  && bad "the still-on-branch commit $c1 was named as stale too: $line" \
  || ok "the reference still on the branch is not named (the verdict discriminates)"
git -C "$repo" reset -q --hard "$c2"

echo "-- the tip is the PREVIOUS slice's binding, never the reader's --"
# A doc-bound slice reading a code-bound slice's turnover. mk_doc_repo's branch
# is deliberately named differently, so resolving the WRONG checkout is
# observable rather than hidden behind a same-named branch.
index 'id=01 status=done risk=low repo=code title=a rederive=0
id=02 status=active risk=low repo=doc title=b rederive=0'
line=$(hdr 02)
command grep -q "all still on $branch" <<< "$line" \
  && ok "a doc-bound reader still tests the code-bound writer's commits against the CODE branch" \
  || bad "the reader's own binding was used — every code commit would read off-branch: $line"
command grep -q "$dbranch" <<< "$line" \
  && bad "the doc branch $dbranch was used as the tip for a code-bound slice's turnover: $line" \
  || ok "the doc branch is not consulted for a code-bound writer"
index 'id=01 status=done risk=low repo=code title=a rederive=0
id=02 status=active risk=low repo=code title=b rederive=0'

echo "-- an unresolvable tip reads UNCHECKED, never clean (the absence floor) --"
saved=$(cat "$ws/project.kv")
printf '%s\n' "$saved" | sed "s|^branch=.*|branch=no/such/branch|" > "$ws/project.kv"
line=$(hdr 02)
command grep -q UNCHECKED <<< "$line" \
  && ok "a tip that does not resolve is named UNCHECKED" \
  || bad "an unresolvable tip did not read UNCHECKED: $line"
command grep -q "all still on" <<< "$line" \
  && bad "an unresolvable tip produced a CLEAN verdict — the check that never ran reads as green: $line" \
  || ok "UNCHECKED is not reported as a clean reading"
printf '%s\n' "$saved" > "$ws/project.kv"

echo "-- no previous turnover: silent, and the header is otherwise intact --"
line=$(hdr 01)
[ -z "$line" ] \
  && ok "the first slice (no previous turnover) renders no prev-turnover line" \
  || bad "slice 01 has no predecessor but a line was rendered: $line"
command grep -q '^binding: kind=' "$outd/spec.md" \
  && ok "the rest of the volatile header still renders when the line is absent" \
  || bad "the binding line vanished — the header block broke"

echo "-- placement: the annotation is inside the volatile header --"
# Body placement would make ambient repo state a novelty source the loop
# detector cannot tell from a real input change; 70-fingerprint pins the
# consequence, this arm pins the placement that causes it.
line=$(hdr 02)
precond "a prev-turnover line is present to place" test -n "$line"
awk -v b="$COMPOSE_VOLATILE_BEGIN" -v e="$COMPOSE_VOLATILE_END" \
    '$0==b{inh=1; next} $0==e{inh=0; next} inh && /^prev-turnover:/{f=1} END{exit !f}' \
    "$outd/spec.md" \
  && ok "the prev-turnover line sits between the volatile-header markers" \
  || bad "the prev-turnover line is outside the volatile header — it would enter the attempt fingerprint"

echo "-- a CANCELLED span between the handed turnover and this slice is NAMED --"
# `@prev` skips cancelled ids (correctly — nobody ran those stages), and said
# nothing about the gap. Measured on a live topic's slice 10: eight slices done by hand outside the
# workflow, the author handed slice 01's turnover, ~35 landed commits and no
# artifact mentioning them; the first draft cited a flag that had been retired
# INSIDE the span. Tonight's cancel-active fix makes mid-topic cancelled rows
# reachable where they previously got overwritten, so the gap gets commoner.
span() { # slice -> the prev-span header line
  compose_prompt "$ws" spec "$1" 1 1 "n0nce" cold "$outd/spec.md" > /dev/null 2>&1
  command grep -m1 '^prev-span:' "$outd/spec.md" || true
}
index 'id=01 status=done risk=low repo=code title=a rederive=0
id=02 status=cancelled risk=low repo=code title=b rederive=0
id=03 status=cancelled risk=low repo=code title=c rederive=0
id=04 status=active risk=low repo=code title=d rederive=0'
line=$(span 04)
precond "a prev-span line was rendered at all" test -n "$line"
case "$line" in
  *"02 03"*) ok "the skipped ids are ENUMERATED, not summarised as a count" ;;
  *) bad "the span line does not name 02 and 03: $line" ;;
esac
case "$line" in
  *"slice 01"*) ok "…and it names the slice whose turnover WAS handed over, so the reader can size the gap" ;;
  *) bad "the span line does not name the turnover the author actually got: $line" ;;
esac
case "$line" in
  *"repository"*|*"charters.md"*) ok "…and says where those outcomes DO live, which is the reader's only route to them" ;;
  *) bad "the span line does not say where the skipped work can be found: $line" ;;
esac
# the prev-turnover line must still be there: two annotations, not one replacing
# the other.
command grep -q '^prev-turnover:' "$outd/spec.md" \
  && ok "the prev-turnover annotation still renders beside it (the two answer different questions)" \
  || bad "the span line displaced the prev-turnover line"
# placement, same reason as the line above it: body placement would make it a
# novelty source the loop detector cannot tell from a real input change.
awk -v b="$COMPOSE_VOLATILE_BEGIN" -v e="$COMPOSE_VOLATILE_END" \
    '$0==b{inh=1; next} $0==e{inh=0; next} inh && /^prev-span:/{f=1} END{exit !f}' \
    "$outd/spec.md" \
  && ok "the prev-span line sits between the volatile-header markers" \
  || bad "the prev-span line is outside the volatile header — it would enter the attempt fingerprint"

# FLOORS. A signal that fires on every topic is noise, so both silent cases:
index 'id=01 status=done risk=low repo=code title=a rederive=0
id=02 status=active risk=low repo=code title=b rederive=0'
line=$(span 02)
[ -z "$line" ] \
  && ok "known-bad floor: no cancelled span -> no line at all (the annotation is not boilerplate)" \
  || bad "a span line was rendered with nothing cancelled: $line"
# SUPERSEDED is deliberately not a span: that id was replaced by a re-split and
# its work never happened under it, so there is no outcome to go looking for.
index 'id=01 status=done risk=low repo=code title=a rederive=0
id=02 status=superseded risk=low repo=code title=b rederive=0
id=03 status=active risk=low repo=code title=c rederive=0'
line=$(span 03)
[ -z "$line" ] \
  && ok "known-bad floor: a SUPERSEDED id is not a span (nothing ran under it; the two statuses are not interchangeable)" \
  || bad "superseded read as a cancelled span: $line"
# A cancelled id BELOW the handed turnover is not this reader's gap: it was
# already past when prev's turnover was written. Without a fixture that places
# one there, dropping the `id > prev` bound changes nothing and the bound is
# unpinned — measured, that mutation survived every other arm here.
index 'id=01 status=cancelled risk=low repo=code title=a rederive=0
id=02 status=done risk=low repo=code title=b rederive=0
id=03 status=active risk=low repo=code title=c rederive=0'
mkdir -p "$ws/slices/02"; printf 'branch %s, tip %s\n' "$branch" "$c2" > "$ws/slices/02/turnover.md"
line=$(span 03)
[ -z "$line" ] \
  && ok "known-bad floor: a cancelled id BELOW the handed turnover is not reported (the span is the gap THIS reader has, not every cancel in the topic)" \
  || bad "a cancelled slice already past when prev's turnover was written was reported as this reader's gap: $line"
rm -rf "$ws/slices/02"
# and the case with NO prior turnover at all, which is the worse one: the
# author gets neither a turnover nor, before this, any hint that work happened.
index 'id=01 status=cancelled risk=low repo=code title=a rederive=0
id=02 status=active risk=low repo=code title=b rederive=0'
line=$(span 02)
case "$line" in
  *"NO prior context"*) ok "a cancelled span with no predecessor turnover says the author was handed nothing at all" ;;
  *) bad "the no-predecessor span reads wrong or is silent: '$line'" ;;
esac
# restore the fixture the later arms expect
index 'id=01 status=done risk=low repo=code title=a rederive=0
id=02 status=active risk=low repo=code title=b rederive=0'


echo "-- the sidecar input set stays clean (the annotation is not a path) --"
command grep -q 'prev-turnover' "$outd/spec.md.inputs" \
  && bad "the annotation leaked into the .inputs sidecar — compose_fingerprint would hash a non-existent file" \
  || ok "the .inputs sidecar carries resolved paths only"

echo "-- decisions@nn: the slice view a reviewer's own checklist asks for --"
# review-standards §7 P8 audits "each decisions-surface entry of THIS SLICE" and
# §9 C0 sweeps the same set; both stages were handed neither the surface nor a
# slice view, so every reviewer went and found it. The filter is the one
# gates@nn/ledger@nn already use — proven here on its own subject, because a
# whole-surface dump passing as the slice view is the exact defect that pattern
# exists to prevent, and a filter that silently matched nothing would read as
# "this slice recorded no DP".
state_append "$ws" decisions session "v=1 t=1 slice=01 dp=01/DP-1 class=A text=mine" >/dev/null
state_append "$ws" decisions session "v=1 t=2 slice=02 dp=02/DP-1 class=A text=NOT-MINE" >/dev/null
state_append "$ws" decisions session "v=1 t=3 slice=01 dp=01/DP-2 class=C text=mine too" >/dev/null
dpath=$(_compose_resolve "$ws" 01 1 'decisions@nn')
case "$dpath" in
  MISSING:*|NONE) bad "decisions@nn did not resolve: $dpath" ;;
  *) n_mine=$(command grep -c 'slice=01' "$dpath" || true)
     n_other=$(command grep -c 'NOT-MINE' "$dpath" || true)
     [ "$n_mine" -eq 2 ] && [ "$n_other" -eq 0 ] \
       && ok "decisions@nn carries this slice's 2 rows and none of slice 02's" \
       || bad "slice view wrong: mine=$n_mine other=$n_other in $dpath"
     case "$dpath" in *.01.txt) ok "the view is slice-NAMED, so a stale whole-surface dump cannot pass as it" ;;
                      *) bad "slice view not slice-named: $dpath" ;; esac ;;
esac
# known-bad: a slice with no rows of its own must resolve to an EMPTY view, not
# to the whole surface — the filter failing open is the dangerous direction.
epath=$(_compose_resolve "$ws" 09 1 'decisions@nn')
[ -f "$epath" ] && [ ! -s "$epath" ] \
  && ok "known-bad: a slice with no DP rows gets an EMPTY view, never the whole surface" \
  || bad "empty-slice view is not empty: $(( $(wc -c < "$epath" 2>/dev/null) )) bytes"
# ...and the TEMPLATE must describe that, because this resolver hands a PATH to
# an empty file where an optional entry normally renders the literal "none".
# Found by rendering a real zero-DP slice, not by reading the patch: the first
# wording promised "none when the slice recorded no DP" and the prompt carried
# a path to a 0-byte file. That is a measured class — a
# template stating one thing while the render does another — and it is cheap to
# pin and expensive to notice.
for tpl in precheck.cold postcheck.cold; do
  t="$WF_ROOT/runtime-docs/templates/prompts/$tpl.md"
  command grep -q '{DECISIONS}' "$t" || { bad "$tpl lost its DECISIONS entry"; continue; }
  command grep -qi 'none when the slice recorded no DP' "$t" \
    && bad "$tpl promises \"none\" for a zero-DP slice; the resolver hands a path to an EMPTY file" \
    || ok "$tpl describes what a zero-DP slice actually receives (an empty file, not \"none\")"
done

echo "-- the completed review manifests actually RENDER their new entries --"
# 30-closure proves stages.tsv and the templates agree by NAME. That is not the
# same claim as: the entry resolves to a real path at compose time. A manifest
# item whose pattern resolved to MISSING would render "none (...)" for every
# reviewer, forever, and the name-level check would stay green.
compose_prompt "$ws" precheck 01 1 1 nDEC1 cold "$outd/pre.md" > "$outd/pre.err" 2>&1 \
  && ok "a precheck prompt composes with the completed manifest" \
  || bad "precheck compose failed: $(cat "$outd/pre.err")"
for want in 'plan excerpt for this slice' 'decisions-surface rows'; do
  command grep -q "$want" "$outd/pre.md" \
    && ok "precheck prompt carries the '$want' entry" \
    || bad "precheck prompt lost: $want"
done
# The path, not the label line: a manifest entry may wrap, and an assertion that
# depends on where the template breaks its line proves nothing about resolution.
command grep -qE '/surface\.decisions\.01\.txt' "$outd/pre.md" \
  && ok "…and its DECISIONS entry resolved to THIS slice's view, not to 'none'" \
  || bad "DECISIONS rendered unresolved: $(command grep -A1 'decisions-surface' "$outd/pre.md" | tr '\n' ' ')"
command grep -q 'surface.decisions.01.txt' "$outd/pre.md.inputs" \
  && ok "…and the view is in the .inputs sidecar, so a DP recorded mid-round reads as novelty" \
  || bad "the slice decisions view is missing from the fingerprint input set"
command grep -qE 'citation authority P7 resolves against: /' "$outd/pre.md" \
  && ok "…and P7's plan resolved to a path (the authority chain has its authority)" \
  || bad "PLAN rendered unresolved: $(command grep 'citation authority' "$outd/pre.md")"
# The same claim for postcheck, because the wiring is PER STAGE: one stage's
# entry resolving proves nothing about the other's, and "renders none forever"
# is invisible to the name-level closure check either way.
printf '# conformance\n' > "$ws/slices/01/conformance.md"
printf '# precheck 1\n' > "$ws/slices/01/precheck.1.md"
if compose_prompt "$ws" postcheck 01 1 1 nDEC2 cold "$outd/post.md" > "$outd/post.err" 2>&1; then
  command grep -qE '/surface\.decisions\.01\.txt' "$outd/post.md" \
    && ok "postcheck's C0 sweep is handed the same slice view (its own manifest wiring, proven separately)" \
    || bad "postcheck DECISIONS unresolved"
  command grep -qE 'precheck\.1\.md' "$outd/post.md" \
    && ok "…and the precheck review C0's chain sweep compares against" \
    || bad "postcheck PRECHECK unresolved: $(command grep -A1 'precheck review' "$outd/post.md" | tr '\n' ' ')"
else
  bad "postcheck compose failed: $(cat "$outd/post.err")"
fi


echo "-- rulings.pending: a topic-scoped ruling rides every slice's bundle; a slice ruling rides only its own --"
# lib/rulings.sh is the one selector behind this resolver AND the emit door, so
# what is pinned here is the carriage rule itself (protocol §6 topic scope).
r9=$(_compose_resolve "$ws" 09 1 'rulings.pending')
[ "$r9" = "NONE" ] && ok "known-bad first: with no rulings on the store a slice resolves NONE" \
  || bad "empty rulings surface resolved to: $r9"
state_append "$ws" rulings operator "v=1 t=10 slice=02 stage=any n=1 file=slices/02/ruling.1.md text=SLICE-TWO-ONLY" >/dev/null
state_append "$ws" rulings operator "v=1 t=11 slice=02 stage=any scope=topic n=2 file=slices/02/ruling.2.md text=TOPIC-WIDE" >/dev/null
r3=$(_compose_resolve "$ws" 03 1 'rulings.pending')
case "$r3" in
  MISSING:*|NONE) bad "slice 03 resolved no bundle though a topic ruling stands: $r3" ;;
  *) command grep -q 'TOPIC-WIDE' "$r3" && ! command grep -q 'SLICE-TWO-ONLY' "$r3" \
       && ok "slice 03's bundle carries the topic ruling and NOT slice 02's own (scope=topic rides every slice)" \
       || bad "slice 03 bundle: $(cat "$r3")" ;;
esac
r2=$(_compose_resolve "$ws" 02 1 'rulings.pending')
[ -f "$r2" ] && command grep -q 'TOPIC-WIDE' "$r2" && command grep -q 'SLICE-TWO-ONLY' "$r2" \
  && ok "slice 02's bundle carries both its own ruling and the topic one" \
  || bad "slice 02 bundle: $(cat "$r2" 2>/dev/null)"
r0=$(_compose_resolve "$ws" 00 1 'rulings.pending')
[ -f "$r0" ] && command grep -q 'TOPIC-WIDE' "$r0" && ! command grep -q 'SLICE-TWO-ONLY' "$r0" \
  && ok "the topic-level stages (slice 00) get the topic ruling and nothing slice-scoped" \
  || bad "slice 00 bundle: $(cat "$r0" 2>/dev/null)"
[ "$r3" != "$r2" ] && ok "different sets, different content-addressed paths (a warm re-read cannot mistake one for the other)" \
  || bad "slices 02 and 03 resolved the same bundle path: $r2"
r9=$(_compose_resolve "$ws" 09 1 'rulings.pending')
[ -f "$r9" ] && command grep -q 'TOPIC-WIDE' "$r9" \
  && ok "a slice that never had a ruling of its own still carries the topic ruling" \
  || bad "slice 09 after the topic ruling: $r9"

check_done
