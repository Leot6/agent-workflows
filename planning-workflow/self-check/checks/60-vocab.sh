#!/usr/bin/env bash
# 60-vocab — closed vocabularies agree across the two homes that carry them.
# A§4 locks the owner-gated decision types and the decision-log template
# carries the row form; A§10 narrows reply types per brief class and protocol
# §6 and the brief template restate the narrowing; protocol §4.0 classifies a
# drift audit and the baseline card's pin header is the column those values are
# written into. A member added on one side only is a vocabulary that is closed
# in name and open in fact.
#
# HONEST BOUNDARY: membership drift is checked by COUNT for the decision types,
# by ANCHOR MEMBER for the narrowed reply classes, and by MEMBERSHIP BOTH WAYS
# for the drift values. A rename that preserves the count on both sides passes,
# and a non-anchor brief class dropped from one side passes. The drift arm
# reads its candidate set from a literal list in this file, so a fifth value
# invented in §4.0 under a name nobody here anticipated is not compared —
# it catches the drift measured, not every drift imaginable. Making these fully checkable needs a machine-readable single
# home for each vocabulary, which the tree does not have and which is not worth
# inventing until a drift is actually measured.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/fixtures/lib.sh"

ARCH="$WF_ROOT/design/architecture.md"
DLOG="$WF_ROOT/runtime-docs/templates/decision-log.md"
BRIEF="$WF_ROOT/runtime-docs/templates/owner-brief.md"
PROTO="$WF_ROOT/runtime-docs/protocol.md"

# --- decision types: A§4's list vs the decision-log row form ---------------
a4=$(awk '/^\*\*Owner-gated decisions\*\*/{f=1} f&&/^\*\*Decision-log row states/{exit} f' "$ARCH" \
     | grep -o '·' | wc -l)
tpl=$(grep '^| D-1 |' "$DLOG" | cut -d'|' -f3 | grep -o '·' | wc -l)
precond "both decision-type lists were found" test "$a4" -ge 5 -a "$tpl" -ge 5
[ "$a4" -eq "$tpl" ] \
  && ok "decision types: A§4 and the decision-log template both list $((a4 + 1))" \
  || bad "decision-type drift: A§4 lists $((a4 + 1)), the template lists $((tpl + 1))"

# --- the narrowed reply classes, stated in three places --------------------
# ruling-contradiction is answer-only: supersede or reaffirm. Checked in the
# VICINITY of the class name, not file-wide — the two words appear elsewhere in
# these files, and a file-wide grep would pass on an unrelated mention.
for f in "$ARCH" "$PROTO" "$BRIEF"; do
  rel=${f#"$WF_ROOT"/}
  near=$(grep -i -A2 -B2 'ruling-contradiction' "$f" || true)
  if [ -z "$near" ]; then
    bad "$rel does not name the ruling-contradiction class at all"
  elif printf '%s' "$near" | grep -qi 'supersede' && printf '%s' "$near" | grep -qi 'reaffirm'; then
    ok "$rel narrows ruling-contradiction to supersede|reaffirm, stated together"
  else
    bad "$rel names ruling-contradiction without its two permitted answers beside it"
  fi
done

# a foundations finding cannot be deferred — stated in A§10, and the stop
# rule's signed path depends on it.
grep -q 'cannot be deferred' "$ARCH" \
  && ok "A§10 still states foundations non-deferrability" \
  || bad "A§10 no longer states that a foundations finding cannot be deferred"

# --- every claim shape has a consumer -------------------------------------
# `claims.md` routes by the grammar of a sentence, not by the writer's care —
# which requires the writer to get from the artifact they are filling to the
# shape it discharges. When this check was written, nine of the then-ten
# shapes were named at their use sites (the card's shape column, the plan's
# "acceptance-claim shape", the disposition ledger's fix-claim stamp, the
# decision log's carried text). Measured: the
# decision-claim shape was named nowhere outside claims.md, so the one artifact
# that carries it — the re-derivation record — never said which shape it was
# discharging.
#
# HONEST BOUNDARY: this asserts the NAME appears somewhere, never that the
# artifact naming it actually applies the precondition. Only the first
# alternative of a slashed name is probed ("invariant / equality" → invariant),
# which is enough to catch an orphan and would miss a renamed second half.
CLAIMS="$WF_ROOT/runtime-docs/claims.md"
# Terminate at the next H2, not at that heading's wording. It used to read
# `/^## Three rules/`, which made a prose CARDINAL a parser anchor: renaming it
# to "Four rules" would not have failed, it would have scanned on silently and
# still returned the right shapes — a dead terminator that reports nothing.
# 95-steps records the same family biting once already, unread through three
# adversarial rounds.
shapes=$(awk '/^\| shape \| trigger grammar \|/{f=1} f&&/^## /{exit} f' "$CLAIMS" \
         | grep -oE '^\| \*\*[a-z /-]+\*\*' | sed 's/^| \*\*//;s/\*\*$//')
n_sh=0
while IFS= read -r sh; do
  [ -n "$sh" ] || continue
  n_sh=$((n_sh + 1))
  first=${sh%% /*}
  probe=$(printf '%s' "$first" | sed 's/[ -]/[- ]/g')
  # design/ is deliberately NOT probed. A§1(e) REQUIRES every admitted mechanism
  # to carry a §14 ceiling row, and a shape's ceiling row names the shape — so
  # probing design/ made every shape satisfy its own use-site check by the very
  # act of being admitted, and this arm could not fail for any shape that
  # followed §1. Measured while landing the prescription shape: with its only
  # use site deleted outright, the arm still reported ok. The regions below are
  # the ones an author or instrument actually FILLS or reads at run time, which
  # is what "can route to its precondition" means; all shapes clear them.
  hits=$(grep -rliE "$probe" --include='*.md' \
         "$WF_ROOT/runtime-docs/templates" "$WF_ROOT/runtime-docs/prompts" \
         "$WF_ROOT/runtime-docs/protocol.md" 2>/dev/null | wc -l)
  [ "$hits" -ge 1 ] || bad "claim shape \"$sh\" is defined in claims.md and named nowhere that uses it — an artifact carrying it cannot route to its precondition"
done <<< "$shapes"
precond "the shape table yielded rows" test "$n_sh" -ge 8
[ "$_FAIL" -eq 0 ] && ok "all $n_sh claim shapes are named at a use site outside claims.md"

# --- drift-audit results: protocol §4.0's set vs the card's pin header ------
# The pin header is where the values are actually WRITTEN, and its column
# enumerates them, so the two enumerations have to agree. Measured: §4.0 gained
# an `instrument:` class for build output the round's own instruments produced,
# and the baseline template's column still offered three values — an author
# filling the card from the template had no cell for the new one. Extracted
# from each home rather than re-typed here, so a fourth value added to one side
# reds instead of matching a hardcoded list. `note` joined the set with obs-57's
# audit-target sentence (a multi-checkout row's non-audit checkouts are `note`,
# never benign/blocking — one live round measured both verdicts on one drift).
drift_sec=$(awk '/^### 4\.0 /{f=1} f&&/^### 4\.1 /{exit} f' "$PROTO")
precond "protocol §4.0 was extracted" test "$(printf '%s' "$drift_sec" | wc -l)" -ge 10
pin_col=$(grep -o 'drift audits ([^)]*)' "$WF_ROOT/runtime-docs/templates/baseline.md" | head -1)
precond "the pin-header drift column was found" test -n "$pin_col"
nd=0
for v in clean benign blocking instrument note; do
  printf '%s' "$drift_sec" | command grep -q "$v" || continue
  nd=$((nd + 1))
  printf '%s' "$pin_col" | command grep -q "$v" \
    || bad "protocol §4.0 classifies drift as '$v' and the baseline template's pin-header column does not offer it"
done
precond "drift values were found in §4.0" test "$nd" -ge 3
[ "$_FAIL" -eq 0 ] && ok "all $nd drift-audit values in §4.0 are offered by the card's pin header"

# --- lens ids are declared in §3, the section that owns them ---------------
# Scoped to §3's span: a file-wide grep would pass on an id mentioned anywhere,
# while the failure message asserts §3.
lens_sec=$(awk '/^## 3\./{f=1} f&&/^## 4\./{exit} f' "$PROTO")
for l in arch red meta exec closure; do
  printf '%s' "$lens_sec" | command grep -q "\`$l\`" \
    || bad "lens id \`$l\` is not declared in protocol §3"
done
[ "$_FAIL" -eq 0 ] && ok "all five instrument ids are declared in §3 itself"

# Non-vacuity: run the check's OWN middot extraction over a fabricated pair
# whose counts differ. A guard proving `[` compares integers would still fire
# with every assertion above deleted.
probe_dir=$(sc_tmpdir)
printf '| D-1 | a · b · c |\n' > "$probe_dir/tpl.md"
probe_counts_agree() {
  local x y
  x=$a4
  y=$(grep '^| D-1 |' "$probe_dir/tpl.md" | cut -d'|' -f3 | grep -o '·' | wc -l)
  [ "$x" -eq "$y" ]
}
known_bad "a decision-type count mismatch is caught" probe_counts_agree

check_done
