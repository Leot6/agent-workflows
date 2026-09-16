#!/usr/bin/env bash
# 97-plan-dir — the directory-form plan's three mechanical invariants
# (P-6⑤⑥): concatenation is DETERMINISTIC (two runs byte-identical —
# delivery's hash pin and the convergence row's single-file hash lean on
# it); headings survive concatenation IN ORDER (spec-template durable
# anchors cite plan.md#heading; an order that moved on re-run would rot
# every citation); and the shipped template DIRECTORY has the required
# shape (00_context with the amend line verbatim, an items scaffold with
# the A§4 field set, and the four top-level files the concat order names).
#
# HONEST BOUNDARY: this proves the mechanism's shape, never a real version's
# content — a topic's plan_v<N>/ can still be missing fields (the lens set
# and the convergence checklist read those); and determinism here is
# asserted over the concatenation only, not over git checkouts (a version
# directory is immutable by the freeze lock, but that is §4.4's duty, not
# this check's).
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/fixtures/lib.sh"

TPL="$WF_ROOT/runtime-docs/templates/plan-dir"
CONCAT="$WF_ROOT/runtime-scripts/plan_concat.sh"
precond "plan_concat.sh exists and parses" bash -n "$CONCAT"
precond "template directory exists" test -f "$TPL/00_context.md"

# --- fixture: a minimal but fully-shaped version -----------------------------
d=$(sc_tmpdir)/plan_v9
mkdir -p "$d/items"
printf '# plan v9 — ctx\n## Repositories\n- R\n' > "$d/00_context.md"
printf '# W-1: alpha\n- **sites**: s\n' > "$d/items/W-1.md"
printf '# W-2: beta\n- **sites**: s\n' > "$d/items/W-2.md"
printf '# W-10: kappa\n- **sites**: s\n' > "$d/items/W-10.md"
printf '# invariants\n## inv-one\n' > "$d/invariants.md"
printf '# rederivation\n' > "$d/rederivation.md"
printf '# delta\n' > "$d/delta.md"
printf '# scaffold\n' > "$d/items/_W-template.md"

# 1) determinism: two runs byte-identical
"$CONCAT" "$d" > "$d/../run1.md"; rc1=$?
"$CONCAT" "$d" > "$d/../run2.md"; rc2=$?
[ $rc1 -eq 0 ] && [ $rc2 -eq 0 ] && cmp -s "$d/../run1.md" "$d/../run2.md" \
  && ok "concatenation is deterministic (two runs byte-identical)" \
  || bad "concat not deterministic or failed (rc=$rc1/$rc2)"

# 2) heading order: context → items ascending (numeric: W-2 before W-10) →
#    invariants → rederivation → delta; scaffold excluded
order=$("$CONCAT" "$d" | grep -nE '^# ' | grep -oE 'W-[0-9]+|ctx|invariants|rederivation|delta' | tr '\n' ' ' | sed 's/ $//')
want="ctx W-1 W-2 W-10 invariants rederivation delta"
[ "$order" = "$want" ] \
  && ok "heading order preserved and numeric (W-2 before W-10): $order" \
  || bad "heading order wrong: got '$order' want '$want'"
"$CONCAT" "$d" | grep -q scaffold \
  && bad "the _-prefixed scaffold leaked into the concatenation" \
  || ok "scaffold (_W-template.md) excluded from concatenation"

# 3) empty-directory refusal (a plan with no context and no items)
e=$(sc_tmpdir)/empty; mkdir -p "$e"
"$CONCAT" "$e" >/dev/null 2>&1; rc=$?
[ $rc -eq 2 ] && ok "an empty version directory is refused (rc=2), not concatenated" \
  || bad "empty directory concatenated or wrong rc (got $rc; want 2)"

# 4) shipped template shape: amend line byte-identical to protocol §7's
a_auth=$(grep -m1 '^    read <ABS workflow>.*amend topic at <ABS topic root>' "$WF_ROOT/runtime-docs/protocol.md" | sed 's/^ *//')
a_inst=$(grep -m1 'amend topic at <ABS topic root>' "$TPL/00_context.md" | sed 's/^ *//')
[ -n "$a_auth" ] && [ "$a_auth" = "$a_inst" ] \
  && ok "the template's amend entry line is byte-identical to protocol §7" \
  || bad "amend line divergence (80-verbatim covers this too; re-run it)"

# item scaffold carries the A§4 field vocabulary (spot: the four unconditional
# fields whose 'none' forms 90-plan-absence guards)
for f in 'abort/rollback' 'interface delta' 'migration/compat' 'acceptance'; do
  grep -q -- "**$f**" "$TPL/items/_W-template.md" \
    && ok "item scaffold carries the '$f' field" \
    || bad "item scaffold lacks the '$f' field — 90-plan-absence's sweep went vacuous"
done

# known-bad: reordered items (a lexicographic sort would put W-10 before W-2)
bad_d=$(sc_tmpdir)/plan_lex; mkdir -p "$bad_d/items"
printf '# ctx\n' > "$bad_d/00_context.md"
printf '# W-2\n' > "$bad_d/items/W-2.md"; printf '# W-10\n' > "$bad_d/items/W-10.md"
o=$("$CONCAT" "$bad_d" | grep -E '^# W-' | tr '\n' ' ')
[ "$o" = "# W-2 # W-10 " ] \
  && ok "known-bad: numeric order held (W-2 before W-10 — a lexicographic sort would flip it)" \
  || bad "numeric order broke: got '$o'"

check_done
