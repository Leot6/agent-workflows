#!/usr/bin/env bash
# 70-fingerprint — lib/compose.sh attempt fingerprints (mechanism level):
# nonce/volatile-header stable across attempts; owed-artifact content change ->
# novel; referenced-input change -> novel; failure-class change -> novel; and
# the K=4 history-match idiom the ferry parks on. The end-to-end no_novelty
# park is the drill's row.
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/fixtures/lib.sh"
. "$RS/lib/state.sh"
. "$RS/lib/compose.sh"

base=$(sc_tmpdir)
read -r repo branch < <(mk_repo "$base/repo")
ws=$(mk_full_ws "$base" fptopic "$repo" "$branch")
outd=$(sc_tmpdir)

compose() { # nonce attempt out
  compose_prompt "$ws" plan-validate 00 1 "$2" "$1" cold "$3"
}

echo "-- volatile header exclusion: nonce/attempt/timestamps do not blind the detector --"
compose nonceAAA 1 "$outd/p1.md" > /dev/null || bad "compose attempt 1 failed"
sleep 1
compose nonceBBB 2 "$outd/p2.md" > /dev/null || bad "compose attempt 2 failed"
precond "the two prompts DIFFER as files (nonce+attempt+time in header)" \
  bash -c '! cmp -s "$1" "$2"' _ "$outd/p1.md" "$outd/p2.md"
precond "prompt 1 carries its nonce in the volatile header" \
  command grep -q "nonce=nonceAAA" "$outd/p1.md"
fp1=$(compose_fingerprint "$ws" plan-validate 00 "$outd/p1.md" none)
fp2=$(compose_fingerprint "$ws" plan-validate 00 "$outd/p2.md" none)
precond "fingerprints are non-empty md5s" \
  bash -c 'printf "%s" "$1" | command grep -qE "^[0-9a-f]{32}$"' _ "$fp1"
[ "$fp1" = "$fp2" ] \
  && ok "identical attempt -> identical fingerprint despite fresh nonce (stable)" \
  || bad "nonce leaked into the fingerprint: $fp1 != $fp2 — every attempt would look novel, blinding the loop detector"

echo "-- the volatile header states no spawn mode (the templates say it never does) --"
# Two anchors eleven slices apart (slice 01 postcheck.2, slice 12 postcheck):
# the templates say "this prompt never states the session's spawn mode;
# freshness in your provenance header is yours to derive" while the rendered
# header stamped mode=. Worse than redundant: the stamped value is
# decide_mode's INTENDED mode, resolved BEFORE the spawn, and a warm intent
# cold-falls back whenever the held session is dead, refuses injection, or —
# since the backend comparison landed — was produced by another backend. So
# the field could be FALSE at the moment a reviewer read it. What survives is
# the template the prompt rendered from (warm vs cold body) and the ledger's
# own mode=, which records what actually happened rather than what was meant.
tplsays=$(command grep -lc "never states the session's spawn mode" \
          "$WF_ROOT"/runtime-docs/templates/prompts/*.md 2>/dev/null | command grep -c . || true)
[ "${tplsays:-0}" -ge 1 ] \
  && ok "the prompt templates carry the rule ($tplsays of them) — the render must not contradict it" \
  || bad "no template carries the never-states-the-mode rule; this arm has nothing to hold the render to"
hdr=$(awk '/volatile-header-begin/{on=1;next} /volatile-header-end/{exit} on' "$outd/p1.md")
precond "the volatile header was extracted (non-empty)" test -n "$hdr"
command grep -q 'mode=' <<< "$hdr" \
  && bad "the rendered header states a spawn mode: '$(printf '%s\n' "$hdr" | command grep 'mode=')' — the template says it never does, and the value is the pre-spawn INTENT, which a cold-fallback falsifies" \
  || ok "the rendered volatile header states no spawn mode — template rule and render agree"
command grep -q "stage=plan-validate slice=00 round=1 attempt=1" <<< "$hdr" \
  && ok "and the rest of the identity line is intact (stage/slice/round/attempt)" \
  || bad "identity line damaged: $(printf '%s\n' "$hdr" | command grep '^stage=')"

echo "-- owed-artifact content change -> novel (owed delta = progress) --"
echo "revised finding" >> "$ws/slices/00/validation_note.md"
fp3=$(compose_fingerprint "$ws" plan-validate 00 "$outd/p2.md" none)
[ "$fp3" != "$fp2" ] \
  && ok "changed owed artifact changes the fingerprint (checkpointing spawns freely)" \
  || bad "owed content change NOT reflected — real progress would park as no_novelty"

echo "-- referenced input change -> novel (owner hand-edit before relaunch) --"
echo "clarified" >> "$ws/project.kv"
fp4=$(compose_fingerprint "$ws" plan-validate 00 "$outd/p2.md" none)
[ "$fp4" != "$fp3" ] \
  && ok "a referenced workspace input change reads as novelty" \
  || bad "input change invisible — wrong no_novelty park would follow"

echo "-- boundary input: plan.md (one level ABOVE the workspace) is manifest-resolved input --"
echo "owner clarified the plan" >> "$ws/../plan.md"
fp4b=$(compose_fingerprint "$ws" plan-validate 00 "$outd/p2.md" none)
[ "$fp4b" != "$fp4" ] \
  && ok "an owner hand-edit to plan.md reads as novelty (the settled ruling: manifest-RESOLVED input content, not just \$ws-prefixed tokens)" \
  || bad "plan.md edit invisible to the fingerprint — the standard recovery move (fix the plan, relaunch) would park no_novelty"
fp4=$fp4b

echo "-- failure-class change -> novel --"
fp5=$(compose_fingerprint "$ws" plan-validate 00 "$outd/p2.md" dead)
[ "$fp5" != "$fp4" ] \
  && ok "different last-failure class -> different fingerprint" \
  || bad "failure class not part of the fingerprint"
fp5b=$(compose_fingerprint "$ws" plan-validate 00 "$outd/p2.md" dead)
[ "$fp5" = "$fp5b" ] && ok "fingerprint is deterministic (same inputs, same hash)" \
  || bad "fingerprint nondeterministic"

echo "-- manifest/template change -> novel --"
compose nonceCCC 3 "$outd/p3.md" > /dev/null
( . "$RS/lib/state.sh"
  state_append "$ws" rulings operator "v=1 t=$(date +%s) slice=00 n=1 text=ruled" ) > /dev/null
compose nonceDDD 4 "$outd/p4.md" > /dev/null
precond "a landed ruling changes the composed body (RULING manifest entry)" \
  bash -c '! cmp -s "$1" "$2"' _ "$outd/p3.md" "$outd/p4.md"
fpA=$(compose_fingerprint "$ws" plan-validate 00 "$outd/p3.md" none)
fpB=$(compose_fingerprint "$ws" plan-validate 00 "$outd/p4.md" none)
[ "$fpA" != "$fpB" ] \
  && ok "a ruling in the manifest is novelty (a post-ruling respawn is never 'identical')" \
  || bad "ruling invisible to the fingerprint"

echo "-- the rulings bundle is content-addressed: path identity = content identity --"
# The stale-read defect (two anchors):
# the bundle used to live at one stable per-slice path rewritten at every
# composition, so a warm session met a path it had already read whose content
# had changed. The fix names the bundle BY ITS CONTENT. Three properties:
#   1. unchanged ruling set -> the SAME path re-resolves (a warm session may
#      skip the re-read as provably lossless, and the fingerprint stays stable)
#   2. a new ruling -> a path never seen before, carrying the new text
#   3. the filename's hash IS the md5 of the file's bytes (self-verifying)
_bundle() { command grep -oE '[^ ]*rulings\.00\.[0-9a-f]{32}\.txt' "$1" | head -1; }
rb4=$(_bundle "$outd/p4.md")
[ -n "$rb4" ] \
  && ok "a composed manifest carries a content-addressed bundle path ($(basename "$rb4"))" \
  || bad "no content-addressed rulings bundle in the composed manifest (p4)"
compose nonceEEE 7 "$outd/rb1.md" > /dev/null
rb1=$(_bundle "$outd/rb1.md")
[ -n "$rb4" ] && [ "$rb4" = "$rb1" ] \
  && ok "unchanged ruling set -> same path (a warm re-read skip is provably lossless; fingerprint stable)" \
  || bad "unchanged ruling set changed the bundle path ($rb4 -> $rb1) — every attempt would read as novel"
( . "$RS/lib/state.sh"
  state_append "$ws" rulings operator "v=1 t=$(date +%s) slice=00 n=2 text=ruled-again" ) > /dev/null
compose nonceFFF 8 "$outd/rb2.md" > /dev/null
rb2=$(_bundle "$outd/rb2.md")
if [ -n "$rb2" ] && [ "$rb2" != "$rb1" ] && command grep -q "ruled-again" "$rb2"; then
  ok "a new ruling -> a NEW path carrying the new text (a warm session cannot mistake it for what it read)"
else
  bad "new ruling did not yield a new path with the new text: ${rb2:-none}"
fi
fh=$(basename "${rb2:-x}" .txt); fh=${fh#rulings.00.}
[ -n "$rb2" ] && [ "$(md5sum < "$rb2" | cut -c1-32)" = "$fh" ] \
  && ok "the bundle path is self-verifying (filename hash = md5 of the file's bytes)" \
  || bad "bundle path not content-addressed: ${rb2:-none}"
# and the changed bundle is what makes the post-ruling attempt novel — the
# fingerprint pair over the SAME composition boundary, re-derived:
fpC=$(compose_fingerprint "$ws" plan-validate 00 "$outd/rb1.md" none)
fpD=$(compose_fingerprint "$ws" plan-validate 00 "$outd/rb2.md" none)
[ "$fpC" != "$fpD" ] \
  && ok "the content-address change itself reads as novelty (resume's ruling round-trip contract)" \
  || bad "bundle content change invisible to the fingerprint"

echo "-- K=4 history idiom (the ferry's match + retention) --"
hist_push() { # fp hist -> new hist (the ferry's exact retention pipeline)
  printf '%s,%s' "$1" "$2" | tr ',' '\n' | command grep -v '^$' | head -4 | paste -sd, -
}
hist=""
for f in f1 f2 f3 f4; do hist=$(hist_push "$f" "$hist"); done
[ "$hist" = "f4,f3,f2,f1" ] && ok "history retains last K=4, newest first" \
  || bad "history retention wrong: $hist"
hist=$(hist_push f5 "$hist")
[ "$hist" = "f5,f4,f3,f2" ] && ok "5th entry evicts the oldest (period-2 oscillation stays caught)" \
  || bad "eviction wrong: $hist"
match() { case ",$2," in *",$1,"*) return 0 ;; *) return 1 ;; esac; }
match f3 "$hist" && ok "a fingerprint in history MATCHES (park no_novelty fires)" \
  || bad "in-history fingerprint not matched — the loop detector is blind"
match f1 "$hist" && bad "evicted fingerprint still matches (stale park)" \
  || ok "evicted fingerprint no longer matches (bounded memory, K=4)"
match f9 "$hist" && bad "novel fingerprint spuriously matches" \
  || ok "novel fingerprint does not match (spawn proceeds)"
match f "$hist" && bad "substring fingerprint matches (comma anchoring broken)" \
  || ok "substring cannot false-match (comma anchoring)"

echo "-- observation-stream surfaces never feed the fingerprint --"
# The attempt ITSELF appends to ledger (spawn events) and gates (gate runs):
# hashing their dumps makes every retry read as novel, so no_novelty could
# never fire for the stages that carry them (turnover/close-out/postcheck).
# Session work products (decisions/observations/learnings/progress) stay IN —
# their change is genuine novelty.
mkdir -p "$ws/.runtime/prompts"
printf 'stable body\n' > "$outd/p6.md"
printf 'seed ledger line\n' > "$ws/.runtime/prompts/surface.ledger.txt"
printf 'seed gates line\n'  > "$ws/.runtime/prompts/surface.gates.txt"
# the slice-scoped dumps (<surface>@nn) are the same streams under another
# name and are excluded for the same reason
printf 'seed ledger 01\n' > "$ws/.runtime/prompts/surface.ledger.01.txt"
printf 'seed gates 01\n'  > "$ws/.runtime/prompts/surface.gates.01.txt"
printf 'real input v1\n'    > "$outd/real-input.txt"
printf '%s\n%s\n%s\n%s\n%s\n' "$ws/.runtime/prompts/surface.ledger.txt" \
  "$ws/.runtime/prompts/surface.gates.txt" "$ws/.runtime/prompts/surface.ledger.01.txt" \
  "$ws/.runtime/prompts/surface.gates.01.txt" "$outd/real-input.txt" > "$outd/p6.md.inputs"
fpL1=$(compose_fingerprint "$ws" turnover 01 "$outd/p6.md" none)
printf 'event=spawn appended by the NEXT attempt\n' >> "$ws/.runtime/prompts/surface.ledger.txt"
printf 'gate run appended\n' >> "$ws/.runtime/prompts/surface.gates.txt"
printf 'event=spawn appended (sliced)\n' >> "$ws/.runtime/prompts/surface.ledger.01.txt"
printf 'gate run appended (sliced)\n' >> "$ws/.runtime/prompts/surface.gates.01.txt"
fpL2=$(compose_fingerprint "$ws" turnover 01 "$outd/p6.md" none)
# Floor before the equality: two EMPTY fingerprints are identical too, and
# the difference-arm below only proves the plan-stage call returns something.
precond "the turnover-stage fingerprint is non-empty (the equality below is over a real hash, not two empties)" \
  test -n "$fpL2"
[ "$fpL1" = "$fpL2" ] \
  && ok "ledger/gates churn leaves the fingerprint IDENTICAL (loop detector stays alive)" \
  || bad "observation-stream append made the retry read as novel — no_novelty structurally dead for these stages"
printf 'real input v2 — an owner hand-edit\n' > "$outd/real-input.txt"
fpL3=$(compose_fingerprint "$ws" turnover 01 "$outd/p6.md" none)
[ "$fpL2" != "$fpL3" ] \
  && ok "a REAL manifest input change still flips the fingerprint (exclusion is surgical, not blanket)" \
  || bad "real input change invisible — exclusion swallowed the sidecar"

echo "-- the prev-turnover annotation is NOT a novelty source (why it lives in the header) --"
# compose re-resolves the previous slice's turnover commit references at
# hand-over and annotates the volatile header (32-compose owns the verdicts).
# It depends on AMBIENT repo state — a branch someone else rewrites, or a repo
# that grows a commit whose abbreviation matches a hex word — so in the BODY it
# would manufacture novelty the loop detector cannot tell from a real input
# change, and no_novelty could never price out a genuine identical retry.
# Header placement is what prevents that, and this arm is its consequence.
fbase=$(sc_tmpdir)
read -r frepo fbranch < <(mk_repo "$fbase/repo")
fws=$(mk_full_ws "$fbase" fpturnover "$frepo" "$fbranch")
for n in 1 2; do
  echo "line $n" >> "$frepo/base.txt"
  git -C "$frepo" commit -qam "feat: unit $n"
done
fc1=$(git -C "$frepo" rev-parse HEAD~1); fc2=$(git -C "$frepo" rev-parse HEAD)
printf 'id=01 status=done risk=low repo=code title=a rederive=0\nid=02 status=active risk=low repo=code title=b rederive=0\n' \
  | state_set "$fws" slices ferry > /dev/null
mkdir -p "$fws/slices/01"
printf 'tip %s, units %s -> %s\n' "$fc2" "$fc1" "$fc2" > "$fws/slices/01/turnover.md"
compose_prompt "$fws" spec 02 1 1 nonceT1 cold "$outd/t1.md" > /dev/null 2>&1
git -C "$frepo" reset -q --hard "$fc1"          # the branch moves under the written turnover
compose_prompt "$fws" spec 02 1 1 nonceT1 cold "$outd/t2.md" > /dev/null 2>&1
# Discriminability floor: unless the annotation actually CHANGED, equality of
# the fingerprints below would be trivially true and this arm would be vacuous.
precond "the rewrite actually changed the rendered annotation" \
  bash -c '! cmp -s <(command grep "^prev-turnover:" "$1") <(command grep "^prev-turnover:" "$2")' \
  _ "$outd/t1.md" "$outd/t2.md"
command grep -q '^prev-turnover:.*WARNING' "$outd/t2.md" \
  && ok "the moved branch is reported in the second render (the input to this arm is real)" \
  || bad "no WARNING after the rewrite: $(command grep -m1 '^prev-turnover:' "$outd/t2.md")"
fpT1=$(compose_fingerprint "$fws" spec 02 "$outd/t1.md" none)
fpT2=$(compose_fingerprint "$fws" spec 02 "$outd/t2.md" none)
[ "$fpT1" = "$fpT2" ] \
  && ok "the annotation changed and the fingerprint did NOT — ambient branch state cannot manufacture novelty" \
  || bad "fingerprint moved with the annotation ($fpT1 != $fpT2): a colleague's rebase would buy a fresh attempt budget"

echo "-- a corrupt rulings surface is never narrated as 'no rulings' (store fault ≠ absent) --"
# state_get returns 3 on a checksum/parse fault (state.sh's own convention);
# the rulings branch must not fold that into NONE, whose rendered sentence —
# "none (no referent by construction)" — claims the store was read and holds
# nothing. Corrupt the surface body in place (header sum now lies) and compose:
# the manifest must name the FAULT visibly. LAST block on purpose: the store
# is deliberately broken from here on.
surf="$ws/.runtime/state/rulings"
precond "the rulings surface exists to corrupt" test -f "$surf"
printf 'X' >> "$surf"
compose nonceHHH 9 "$outd/rb3.md" > /dev/null
command grep -q "rulings surface FAULT" "$outd/rb3.md" \
  && ok "a corrupt rulings surface renders as a visible FAULT in the manifest, not 'no referent by construction'" \
  || bad "corrupt surface narrated as: $(command grep -oE 'none \([^)]*' "$outd/rb3.md" | head -1)"

check_done
