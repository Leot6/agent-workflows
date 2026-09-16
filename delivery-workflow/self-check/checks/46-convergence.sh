#!/usr/bin/env bash
# 46-convergence — the two REVIEW-LOOP CONVERGENCE PREDICATES, split verbatim
# out of 45-halt.sh: check_severity_trend (precheck↔revise and postcheck↔fix,
# its repeat-aware park, its round bound and its ruled discharge) and
# check_decomposition_fixpoint (the topic loop's bound, computed on the slices
# index rather than on a finding count), plus the disagreement round-trip both
# of them discharge through and the input validation that keeps a corrupted
# count from silently disarming either.
#
# WHY IT IS A FILE OF ITS OWN, so the split does not read as arbitrary later:
# 45-halt reached 976 against cap.selftest_file=1000 and the next arm owed to
# either predicate would have had to be placed away from its natural home. The
# precedent is 50-record.sh at 1013, whose closed-vocabulary sweeps moved
# verbatim into 52-vocab.sh, and 30-closure.sh at 998 → 31-backends.sh; their
# reasoning applies unchanged — a cap saying a file is full is not answered by
# removing what the file explains. So this is a MOVE, byte-for-byte, not a
# rewrite: every assertion below is the assertion that was in 45-halt, and the
# pair's combined content is unchanged. The family is coherent on its own
# terms: it is the whole of what the ferry does when a review loop will not
# converge, and 45-halt keeps what it does when a stage HALTS — resume gating,
# ruling identity, the workflow pin, budgets, admission and the probe.
#
# WHERE THIS DIFFERS FROM THE 31-backends PRECEDENT, stated because the
# difference is the part a later reader would otherwise have to rediscover:
# that split was clean because the family needed NONE of 30-closure's shared
# setup. This one does. `new_ws`, `put_halt` and `put_ruling` are used by BOTH
# halves, so the setup below is a COPY and not part of the move — it is the
# only text here that is not the line it was. `halt_field` is not copied: it
# is used 40 times in what 45-halt keeps and not once in what moved.
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

echo "-- disagreement: an owner ruling buys a real advance, not a re-park --"
ws=$(new_ws haltd)
mk_artifact "$ws/slices/01/precheck.2.md" "precheck round 2" claims
( . "$RS/lib/state.sh"
  state_append "$ws" handoff session \
    "v=1 t=10 slice=01 stage=precheck attempt=1 round=1 nonce=nD1 verdict=issues confidence=HIGH findings.substantive=3 findings.wording=0"
  state_append "$ws" handoff session \
    "v=1 t=20 slice=01 stage=precheck attempt=1 round=2 nonce=nD2 verdict=issues confidence=HIGH findings.substantive=3 findings.wording=0"
  state_put "$ws" stage ferry "slice=01" "stage=precheck" "round=2" "attempt=1" \
    "state=done" "nonce=nD2" "spawn_t=1" ) > /dev/null
put_halt "$ws" disagreement 01 precheck 2 100
put_ruling "$ws" 01 any 200 "continue: findings are narrowing"
assert_rc 0 "resume + advance after a disagreement ruling reaches revise (no identical re-park)" -- \
  bash -c ". '$hf' '$ws' > /dev/null 2>&1; resume_halt_gate && { load_position; do_advance; }"
[ "$(state_field "$ws" stage stage)" = "revise" ] \
  && ok "the slice advanced into revise (the ruling bought a spawnable stage)" \
  || bad "stage is '$(state_field "$ws" stage stage)' — the ruling bought nothing"

echo "-- severity-trend zero-guard: a wording-only pair never parks disagreement --"
ws=$(new_ws halte)
( . "$RS/lib/state.sh"
  state_append "$ws" handoff session \
    "v=1 t=10 slice=01 stage=precheck attempt=1 round=1 nonce=nE1 verdict=issues confidence=HIGH findings.substantive=0 findings.wording=2" ) > /dev/null
rec2="v=1 t=20 slice=01 stage=precheck attempt=1 round=2 nonce=nE2 verdict=issues confidence=HIGH findings.substantive=0 findings.wording=1"
assert_rc 0 "substantive 0 -> 0 does NOT trip the predicate (wording never blocks alone)" -- \
  bash -c ". '$hf' '$ws' > /dev/null 2>&1; G_SLICE=01 G_STAGE=precheck G_ROUND=2; check_severity_trend '$rec2'"
# The reviewer's split of the count (review-standards §1): the predicate acts on
# REPEATS. Four directions, because the change moves a park in both: a 1->1 whose
# one finding survived the previous round still parks (the predicate is not
# weakened); a 1->1 whose finding is NEW does not (9 of the 11 disagreement
# parks on the archived ledgers were this shape); a record with NO split
# predates the field and keeps its old
# reading (all-repeat); a garbage split is a stall_record, never a silent pass.
( . "$RS/lib/state.sh"
  state_append "$ws" handoff session \
    "v=1 t=15 slice=01 stage=precheck attempt=1 round=1 nonce=nE1b verdict=issues confidence=HIGH findings.substantive=1 findings.wording=0" ) > /dev/null
rec2b="v=1 t=20 slice=01 stage=precheck attempt=1 round=2 nonce=nE2 verdict=issues confidence=HIGH findings.substantive=1 findings.wording=0 findings.substantive.new=0 findings.substantive.repeat=1"
assert_rc 20 "substantive 1 -> 1 with repeat=1 still parks (a finding survived the round; predicate not weakened)" -- \
  bash -c ". '$hf' '$ws' > /dev/null 2>&1; G_SLICE=01 G_STAGE=precheck G_ROUND=2; check_severity_trend '$rec2b'"
assert_out_has "repeat=1 new=0" "the park detail carries the split the owner rules on"
# The owner's question set for this halt class is the reviewer's own absorption
# section, so the park must NAME both review files and point at it (the live park
# that prompted this carried the predicate text alone).
assert_out_has "slices/01/precheck.1.md" "the park names the previous round's review file"
assert_out_has "slices/01/precheck.2.md" "…and this round's"
assert_out_has "## 3. absorption" "…and points at the section the owner rules from"
rec2c="v=1 t=20 slice=01 stage=precheck attempt=1 round=2 nonce=nE2c verdict=issues confidence=HIGH findings.substantive=1 findings.wording=0 findings.substantive.new=1 findings.substantive.repeat=0"
assert_rc 0 "substantive 1 -> 1 with repeat=0 (all new) does NOT park — the loop absorbed everything and found new material" -- \
  bash -c ". '$hf' '$ws' > /dev/null 2>&1; G_SLICE=01 G_STAGE=precheck G_ROUND=2; check_severity_trend '$rec2c'"
rec2d="v=1 t=20 slice=01 stage=precheck attempt=1 round=2 nonce=nE2d verdict=issues confidence=HIGH findings.substantive=1 findings.wording=0"
assert_rc 20 "a record with NO split (pre-field) still parks on 1 -> 1 — it reads as all-repeat, so old records keep their interpretation" -- \
  bash -c ". '$hf' '$ws' > /dev/null 2>&1; G_SLICE=01 G_STAGE=precheck G_ROUND=2; check_severity_trend '$rec2d'"
assert_out_has "new=unfielded" "and the park says the split was absent rather than inventing one"
rec2e="v=1 t=20 slice=01 stage=precheck attempt=1 round=2 nonce=nE2e verdict=issues confidence=HIGH findings.substantive=1 findings.wording=0 findings.substantive.new=x findings.substantive.repeat=abc"
assert_rc 20 "a non-numeric repeat count parks stall_record (a hand-edited split cannot disarm the predicate)" -- \
  bash -c ". '$hf' '$ws' > /dev/null 2>&1; G_SLICE=01 G_STAGE=precheck G_ROUND=2; check_severity_trend '$rec2e'"
assert_out_has "stall_record" "named as a record fault, not as convergence"

echo "-- the round bound: an all-new loop has no repeat to park on, so rounds bound it --"
# Without this the split above would leave a loop whose every round finds new
# material with wallclock as its only stop. Same halt class, own text, same ruled
# discharge; the cap is read from config (a topic override moves it).
wsrb=$(new_ws haltrb)
( . "$RS/lib/state.sh"
  state_append "$wsrb" handoff session \
    "v=1 t=70 slice=01 stage=precheck attempt=1 round=7 nonce=nR7 verdict=issues confidence=HIGH findings.substantive=3 findings.wording=0 findings.substantive.new=3 findings.substantive.repeat=0" ) > /dev/null
recr8="v=1 t=80 slice=01 stage=precheck attempt=1 round=8 nonce=nR8 verdict=issues confidence=HIGH findings.substantive=2 findings.wording=0 findings.substantive.new=2 findings.substantive.repeat=0"
assert_rc 20 "round 8 of an all-new loop parks at the default review.max_rounds=8 (3 -> 2, repeat=0: the trend predicate is silent, the bound is not)" -- \
  bash -c ". '$hf' '$wsrb' > /dev/null 2>&1; G_SLICE=01 G_STAGE=precheck G_ROUND=8; check_severity_trend '$recr8'"
assert_out_has "review round bound" "the park names the bound, not a disagreement it cannot establish"
assert_out_has "review.max_rounds=8" "and the cap it was compared against"
assert_out_has "slices/01/precheck.8.md" "and the review file to read (the round-bound park names its reviews too)"
recr7="v=1 t=70 slice=01 stage=precheck attempt=1 round=7 nonce=nR7b verdict=issues confidence=HIGH findings.substantive=2 findings.wording=0 findings.substantive.new=2 findings.substantive.repeat=0"
assert_rc 0 "round 7 of the same loop does NOT park (under the bound, no repeat)" -- \
  bash -c ". '$hf' '$wsrb' > /dev/null 2>&1; G_SLICE=01 G_STAGE=precheck G_ROUND=7; check_severity_trend '$recr7'"
mkdir -p "$wsrb/config"; printf 'review.max_rounds=3\n' > "$wsrb/config/topic.kv"
recr3="v=1 t=30 slice=01 stage=precheck attempt=1 round=3 nonce=nR3 verdict=issues confidence=HIGH findings.substantive=1 findings.wording=0 findings.substantive.new=1 findings.substantive.repeat=0"
assert_rc 20 "a topic override review.max_rounds=3 moves the bound (round 3 parks)" -- \
  bash -c ". '$hf' '$wsrb' > /dev/null 2>&1; G_SLICE=01 G_STAGE=precheck G_ROUND=3; check_severity_trend '$recr3'"
( . "$RS/lib/state.sh"; state_put "$wsrb" attempts ferry "trend_ok.01.precheck.3=1" ) > /dev/null
assert_rc 0 "a ruled continuation discharges the round bound for that (slice,stage,round) too" -- \
  bash -c ". '$hf' '$wsrb' > /dev/null 2>&1; G_SLICE=01 G_STAGE=precheck G_ROUND=3; check_severity_trend '$recr3'"
rm -f "$wsrb/config/topic.kv"

echo "-- the TOPIC loop converges on the DECIDED ARTIFACT, not on a finding count --"
# split↔split-check cannot borrow the severity-trend predicate, and the reason is
# what the two loops iterate over. §6's eight criteria are properties of the
# DECOMPOSITION; the findings land on charters.md, whose attestation prose grows
# every round by construction. Counting findings over a surface that only grows
# has no terminating condition — measured: 13 rounds, 21 substantive findings,
# none moving a boundary/id/binding/risk, against an index that emitted 13 times
# with ONE distinct value. So the bound is the index's own bytes.
IDX='01:low:code:relocate the substrate;02:med:code:release-set guard'
wsf=$(new_ws haltfx)
( . "$RS/lib/state.sh"
  state_append "$wsf" ledger ferry "v=1 t=10 event=slices_index slices=$IDX"
  state_append "$wsf" ledger ferry "v=1 t=20 event=slices_index slices=$IDX" ) > /dev/null
recflag="v=1 t=30 slice=00 stage=split-check attempt=1 round=2 nonce=nS2 verdict=flag confidence=HIGH findings.substantive=4 findings.wording=1"
assert_rc 20 "an index byte-identical across 2 emits + a flag verdict parks the topic loop" -- \
  bash -c ". '$hf' '$wsf' > /dev/null 2>&1; G_SLICE=00 G_STAGE=split-check G_ROUND=2; check_decomposition_fixpoint '$recflag'"
assert_out_has "fixpoint" "the park names the fixpoint, not a disagreement it cannot establish"
# The park used to assert that what a frozen-index round is still finding is
# "the charter's PROSE about the cut, not the cut". There is a measured
# counterexample: a 64-minute round left the index byte-identical and produced
# `00/DP-2`, a re-binding of which cases land in which slice's first commit.
# The index encodes
# id:risk:repo:title:after and cannot express a commit-unit assignment, so
# byte-identity bounds the CUT and says nothing about the ROUND. The park now
# states that and points at the surface that CAN answer it.
assert_out_has "DECISIONS surface" "the park names the surface that holds what the index cannot encode"
assert_out_lacks "still finding is the charter's PROSE" \
  "and no longer asserts the conclusion a measured round falsifies"
# these emits carry no decisions= field, so the park must SAY the count is
# unavailable rather than compute a delta from nothing.
assert_out_has "predate the decisions= field" \
  "an old ledger's missing count is named, never silently read as 'no decisions'"

# decisions= moving across the compared emits is the discriminator the index
# cannot be: same cut, different class=A count = the round re-bound something.
wsfd=$(new_ws haltfxd)
( . "$RS/lib/state.sh"
  state_append "$wsfd" ledger ferry "v=1 t=10 event=slices_index decisions=1 slices=$IDX"
  state_append "$wsfd" ledger ferry "v=1 t=20 event=slices_index decisions=2 slices=$IDX" ) > /dev/null
assert_rc 20 "a frozen index still parks when the decisions count moved (the cut is the bound, not the round)" -- \
  bash -c ". '$hf' '$wsfd' > /dev/null 2>&1; G_SLICE=00 G_STAGE=split-check G_ROUND=2; check_decomposition_fixpoint '$recflag'"
assert_out_has "ROUNDS WERE NOT EMPTY" "and the park says so, with the delta, instead of leaving the owner to find it"
assert_out_has "1 -> 2" "the delta is printed, not asserted"
# and the other direction: an unmoved count is the ONLY reading that supports
# 'nothing was decided', and the park must claim only that much.
wsfe=$(new_ws haltfxe)
( . "$RS/lib/state.sh"
  state_append "$wsfe" ledger ferry "v=1 t=10 event=slices_index decisions=3 slices=$IDX"
  state_append "$wsfe" ledger ferry "v=1 t=20 event=slices_index decisions=3 slices=$IDX" ) > /dev/null
assert_rc 20 "a frozen index with an unmoved decisions count parks too (the fixpoint is unchanged)" -- \
  bash -c ". '$hf' '$wsfe' > /dev/null 2>&1; G_SLICE=00 G_STAGE=split-check G_ROUND=2; check_decomposition_fixpoint '$recflag'"
assert_out_has "did not move" "and says the count held, which is what 'nothing was decided' actually rests on"
assert_out_lacks "ROUNDS WERE NOT EMPTY" "the two readings are not both printed"
# the field must NEVER enter the identity comparison: same cut + different
# counts is still a fixpoint (above). The inverse floor: a CHANGED cut with an
# IDENTICAL count must still not park, or decisions= has silently become the
# bound.
wsfg=$(new_ws haltfxg)
( . "$RS/lib/state.sh"
  state_append "$wsfg" ledger ferry "v=1 t=10 event=slices_index decisions=5 slices=$IDX"
  state_append "$wsfg" ledger ferry "v=1 t=20 event=slices_index decisions=5 slices=01:low:code:relocate the substrate;02:med:code:guard;03:low:doc:seam sync" ) > /dev/null
assert_rc 0 "a CHANGED cut with an identical decisions count still does not park (identity is the index's bytes alone)" -- \
  bash -c ". '$hf' '$wsfg' > /dev/null 2>&1; G_SLICE=00 G_STAGE=split-check G_ROUND=2; check_decomposition_fixpoint '$recflag'"
# GOOD DIRECTION 1 — a real re-cut must NOT park, or the guard would stop every
# healthy topic on its second round.
wsg2=$(new_ws haltfx2)
( . "$RS/lib/state.sh"
  state_append "$wsg2" ledger ferry "v=1 t=10 event=slices_index slices=$IDX"
  state_append "$wsg2" ledger ferry "v=1 t=20 event=slices_index slices=01:low:code:relocate the substrate;02:med:code:guard;03:low:doc:seam sync" ) > /dev/null
assert_rc 0 "an index that CHANGED between emits does not park (the re-cut is the loop working)" -- \
  bash -c ". '$hf' '$wsg2' > /dev/null 2>&1; G_SLICE=00 G_STAGE=split-check G_ROUND=2; check_decomposition_fixpoint '$recflag'"
# GOOD DIRECTION 2 — concur advances; only a verdict that loops can trip it.
recok="v=1 t=30 slice=00 stage=split-check attempt=1 round=2 nonce=nS3 verdict=concur confidence=HIGH findings.substantive=0 findings.wording=2"
assert_rc 0 "a concur verdict never parks, however frozen the index is" -- \
  bash -c ". '$hf' '$wsf' > /dev/null 2>&1; G_SLICE=00 G_STAGE=split-check G_ROUND=2; check_decomposition_fixpoint '$recok'"
# and one emit is not a fixpoint: "unchanged" needs two readings to differ from
# "never changed".
wsg3=$(new_ws haltfx3)
( . "$RS/lib/state.sh"
  state_append "$wsg3" ledger ferry "v=1 t=10 event=slices_index slices=$IDX" ) > /dev/null
assert_rc 0 "a single emit is not yet a fixpoint (one reading cannot show stability)" -- \
  bash -c ". '$hf' '$wsg3' > /dev/null 2>&1; G_SLICE=00 G_STAGE=split-check G_ROUND=2; check_decomposition_fixpoint '$recflag'"
# the owner's ruled continuation buys an advance here too — same discharge key,
# because both predicates park `disagreement` and a stage is in one loop only.
( . "$RS/lib/state.sh"; state_put "$wsf" attempts ferry "trend_ok.00.split-check.2=1" ) > /dev/null
assert_rc 0 "a ruled continuation discharges the fixpoint park for that (slice,stage,round)" -- \
  bash -c ". '$hf' '$wsf' > /dev/null 2>&1; G_SLICE=00 G_STAGE=split-check G_ROUND=2; check_decomposition_fixpoint '$recflag'"

# THE THRASH BOUND — the shape the fixpoint above cannot see, and the reason it
# is a second arm and not a wider first one. A cut that MOVES every round never
# freezes, so the fixpoint never fires and control reaches here; and split runs
# at slice 00, which attempt.sh exempts from the slice wallclock, so the only
# remaining stop was budget.topic_wallclock parking on a cause it never
# diagnosed. $wsg2 is the changed-index workspace from the good direction above:
# the same loop that must NOT park at round 2 MUST park once it will not stop.
assert_rc 20 "round 16 of a THRASHING split loop parks at the default split.max_rounds=16" -- \
  bash -c ". '$hf' '$wsg2' > /dev/null 2>&1; G_SLICE=00 G_STAGE=split-check G_ROUND=16; check_decomposition_fixpoint '$recflag'"
assert_out_has "split round bound" "the park names the bound, not a fixpoint it cannot establish"
assert_out_has "split.max_rounds=16" "and the cap it was compared against"
assert_out_has "slices/00/splitcheck.16.md" "and the review files to read (the round-bound park names its reviews too)"
assert_out_has "thrashing" "and says which of the two shapes this is, since the remedy differs"
assert_rc 0 "round 15 of the same thrashing loop does NOT park (under the bound)" -- \
  bash -c ". '$hf' '$wsg2' > /dev/null 2>&1; G_SLICE=00 G_STAGE=split-check G_ROUND=15; check_decomposition_fixpoint '$recflag'"
# The specific cause wins: a FROZEN index at or past the bound is a fixpoint and
# must say so, because the two shapes take different rulings — freeze is settled
# and thrash is a plan question. The fixpoint park returns before the bound.
wsfb=$(new_ws haltfxb)
( . "$RS/lib/state.sh"
  state_append "$wsfb" ledger ferry "v=1 t=10 event=slices_index slices=$IDX"
  state_append "$wsfb" ledger ferry "v=1 t=20 event=slices_index slices=$IDX" ) > /dev/null
assert_rc 20 "a FROZEN index at round 16 parks — and as the FIXPOINT, not as the round bound" -- \
  bash -c ". '$hf' '$wsfb' > /dev/null 2>&1; G_SLICE=00 G_STAGE=split-check G_ROUND=16; check_decomposition_fixpoint '$recflag'"
assert_out_has "fixpoint" "the more specific cause is the one the owner is handed"
# a concur still advances at the bound: the loop is over, whatever the round
# number says — the verdict gate is ahead of both arms.
assert_rc 0 "a concur verdict at round 16 never parks (the bound is not a deadline on a loop that ended)" -- \
  bash -c ". '$hf' '$wsg2' > /dev/null 2>&1; G_SLICE=00 G_STAGE=split-check G_ROUND=16; check_decomposition_fixpoint '$recok'"
mkdir -p "$wsg2/config"; printf 'split.max_rounds=4\n' > "$wsg2/config/topic.kv"
assert_rc 20 "a topic override split.max_rounds=4 moves the bound (round 4 parks)" -- \
  bash -c ". '$hf' '$wsg2' > /dev/null 2>&1; G_SLICE=00 G_STAGE=split-check G_ROUND=4; check_decomposition_fixpoint '$recflag'"
( . "$RS/lib/state.sh"; state_put "$wsg2" attempts ferry "trend_ok.00.split-check.4=1" ) > /dev/null
assert_rc 0 "a ruled continuation discharges the split round bound for that (slice,stage,round) too" -- \
  bash -c ". '$hf' '$wsg2' > /dev/null 2>&1; G_SLICE=00 G_STAGE=split-check G_ROUND=4; check_decomposition_fixpoint '$recflag'"
rm -f "$wsg2/config/topic.kv"
# the cap is READ, never assumed: a garbage or absent value is a config park,
# not a silently disarmed bound (the vacuous-arm duty — what does it do on
# empty input?).
mkdir -p "$wsg2/config"; printf 'split.max_rounds=notanumber\n' > "$wsg2/config/topic.kv"
assert_rc 20 "a non-numeric split.max_rounds parks config, never disarms the bound" -- \
  bash -c ". '$hf' '$wsg2' > /dev/null 2>&1; G_SLICE=00 G_STAGE=split-check G_ROUND=16; check_decomposition_fixpoint '$recflag'"
assert_out_has "split.max_rounds" "and the park names the key that could not be read"
printf 'split.max_rounds=1\n' > "$wsg2/config/topic.kv"
assert_rc 20 "a cap below 2 is refused too (a bound of 1 would park every first round)" -- \
  bash -c ". '$hf' '$wsg2' > /dev/null 2>&1; G_SLICE=00 G_STAGE=split-check G_ROUND=16; check_decomposition_fixpoint '$recflag'"
rm -f "$wsg2/config/topic.kv"

echo "-- severity-trend covers the postcheck↔fix loop (both review loops, one predicate) --"
# fix-round evidence keeps every fix fingerprint fresh and the attempt budget
# resets per round, so before this coverage the postcheck↔fix loop's only
# bound was wallclock — and its park reason misnamed the cause.
wsp=$(new_ws haltpc)
( . "$RS/lib/state.sh"
  state_append "$wsp" handoff session \
    "v=1 t=10 slice=01 stage=postcheck attempt=1 round=1 nonce=nP1 verdict=findings confidence=HIGH findings.substantive=3 findings.wording=0" ) > /dev/null
recp="v=1 t=20 slice=01 stage=postcheck attempt=1 round=2 nonce=nP2 verdict=findings confidence=HIGH findings.substantive=3 findings.wording=0"
assert_rc 20 "postcheck substantive 3 -> 3 parks disagreement (the fix loop is not converging)" -- \
  bash -c ". '$hf' '$wsp' > /dev/null 2>&1; G_SLICE=01 G_STAGE=postcheck G_ROUND=2; check_severity_trend '$recp'"
assert_out_has "postcheck" "the park message names the loop that tripped"
recp_dec="v=1 t=20 slice=01 stage=postcheck attempt=1 round=2 nonce=nP3 verdict=findings confidence=HIGH findings.substantive=1 findings.wording=0"
assert_rc 0 "postcheck substantive 3 -> 1 (decreasing) does NOT park" -- \
  bash -c ". '$hf' '$wsp' > /dev/null 2>&1; G_SLICE=01 G_STAGE=postcheck G_ROUND=2; check_severity_trend '$recp_dec'"

echo "-- trend discharge is STAGE-scoped (rounds are numbered per (slice,stage) — an unscoped key collides) --"
( . "$RS/lib/state.sh"
  state_put "$wsp" attempts ferry "trend_ok.01.precheck.2=1" ) > /dev/null
assert_rc 20 "a precheck-scoped discharge does NOT unlock the postcheck predicate at the same slice+round" -- \
  bash -c ". '$hf' '$wsp' > /dev/null 2>&1; G_SLICE=01 G_STAGE=postcheck G_ROUND=2; check_severity_trend '$recp'"
( . "$RS/lib/state.sh"
  state_put "$wsp" attempts ferry "trend_ok.01.postcheck.2=1" ) > /dev/null
assert_rc 0 "the postcheck-scoped discharge unlocks it" -- \
  bash -c ". '$hf' '$wsp' > /dev/null 2>&1; G_SLICE=01 G_STAGE=postcheck G_ROUND=2; check_severity_trend '$recp'"

echo "-- trend inputs are validated: a corrupted count parks loudly, never silently passes --"
wsn=$(new_ws haltnum)
( . "$RS/lib/state.sh"
  state_append "$wsn" handoff session \
    "v=1 t=10 slice=01 stage=precheck attempt=1 round=1 nonce=nX1 verdict=issues confidence=HIGH findings.substantive=2 findings.wording=0" ) > /dev/null
recx="v=1 t=20 slice=01 stage=precheck attempt=1 round=2 nonce=nX2 verdict=issues confidence=HIGH findings.substantive=abc findings.wording=0"
assert_rc 20 "a non-numeric substantive count parks stall_record (hand-edited record must not silently disarm the predicate)" -- \
  bash -c ". '$hf' '$wsn' > /dev/null 2>&1; G_SLICE=01 G_STAGE=precheck G_ROUND=2; check_severity_trend '$recx'"

check_done
