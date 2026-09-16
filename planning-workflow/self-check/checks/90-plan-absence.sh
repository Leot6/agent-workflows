#!/usr/bin/env bash
# 90-plan-absence — every `none` form the PLAN template offers carries a range
# slot. `none` is in `claims.md`'s absence trigger list verbatim, and that
# shape's precondition is "state the full range read … No range ⇒ the claim
# does not hold". A template that offers a bare `none` instructs the author to
# write a claim the tree's own discipline says does not hold.
#
# WHY THE PLAN TEMPLATE ONLY, and not every `none` under `templates/`: the
# other 10 have their range determined by the artifact carrying them — a
# close-out's is its round (the file's own path), a grill sheet's is its
# batches (the Branch-closure heading), checklist E-2's is the executor's
# mandatory Range-read section, and the card's authorities inventory already
# writes the long form this check enforces. Only the plan's work-item fields
# state a range nowhere. And these reach an implementer who **acts** on them.
# A§9 keeps the decision log and the card readable to a consumer too, so the
# plan is not alone in being read after convergence — what sets it apart is
# that the card's absence rows carry an evidence column and a check record,
# and the plan's `none` forms carried neither.
#
# HONEST BOUNDARY, two parts. (1) This checks the SLOT exists in the template,
# never that an author filled it, and never that what they filled it with is a
# range rather than an opinion — `none — <because I said so>` passes. (2) It
# reads the `### W-` block only; a `none` the template offers elsewhere is out
# of scope by the paragraph above, deliberately, and a new field added outside
# that block is invisible here.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/fixtures/lib.sh"

PLAN_DIR="$WF_ROOT/runtime-docs/templates/plan-dir"
PLAN="$PLAN_DIR/items/_W-template.md"   # the none-forms live in item fields
precond "the plan template exists" test -f "$PLAN"

# Fields wrap across lines, so a per-line scan would read a continuation as a
# field of its own and miss the slot sitting one line down. Join first.
fields() { # <file> -> one line per `- **field**:`, continuations folded in
  awk 'BEGIN{f=1} /^## /{exit} f' "$1" \
  | awk '
      /^- \*\*/                      { if (buf != "") print buf; buf = $0; next }
      /^[[:space:]]+[^[:space:]]/    { if (buf != "") { s = $0; sub(/^[[:space:]]+/, "", s); buf = buf " " s }; next }
                                     { if (buf != "") { print buf; buf = "" } }
      END                            { if (buf != "") print buf }'
}

# `\bnone\b`, not `(^|[^a-z])none(...)`: an anchor inside an ERE alternation
# group silently matches nothing here, which would leave the sweep looking
# clean over zero fields. The counter below is what would catch that.
has_none() { printf '%s' "$1" | command grep -qiE '\bnone\b'; }
has_slot() { printf '%s' "$1" | command grep -qiE 'none[^<]*<'; }

n_fields=0
n_none=0
while IFS= read -r f; do
  [ -n "$f" ] || continue
  n_fields=$((n_fields + 1))
  has_none "$f" || continue
  n_none=$((n_none + 1))
  has_slot "$f" || bad "plan template field ${f%%:*} offers a bare \`none\` with no range slot:"$'\n'"        $f"
done < <(fields "$PLAN")

precond "the work-item block yielded fields"   test "$n_fields" -ge 8
precond "none-forms were found among them"     test "$n_none"   -ge 4
[ "$_FAIL" -eq 0 ] && ok "all $n_none \`none\` forms in the plan template's $n_fields work-item fields carry a range slot"

# Non-vacuity: route a real field line, mutated back to the bare form the tree
# actually shipped, through the check's OWN predicate.
probe='- **edges**: `after W-x (authoring)` · `after W-y (runtime)` / none'
probe_ok() { has_none "$probe" && has_slot "$probe"; }
known_bad "the bare \`none\` form this check was written for is caught" probe_ok

check_done
