#!/usr/bin/env bash
# plan_concat.sh — promote a plan version directory to the single plan.md.
#
# The boundary constraint: planning's working form is a directory, delivery's
# consumed form is one file, and this script is the fixed point between them.
# Deterministic by construction: fixed file order, fixed separators, no
# timestamps — two runs over the same directory produce byte-identical output
# (the self-check asserts this; delivery's plan-hash pin and the convergence
# row's single-file hash both lean on it).
#
# Order (part of A§9's boundary contract):
#   00_context.md → items/*.md (ascending filename = ascending item id,
#   opaque ids with a fixed zero-pad stay ordered) → invariants.md →
#   rederivation.md → delta.md
# Each file's body is emitted verbatim; files are separated by exactly one
# blank line. Files absent from the directory are skipped (a version may omit
# invariants); an EMPTY directory is refused — a plan with no context and no
# items is a mistake, not a plan.
#
# The _W-template.md item scaffold is excluded: it is template scaffolding,
# never a work item.
#
# Usage: plan_concat.sh <plan_v<N>/ > plan.md   (output to stdout)
# Exit: 0 concatenated · 2 usage/empty-directory fault.
set -uo pipefail
DIR=${1:?usage: plan_concat.sh <plan-version-directory> (output on stdout)}
[ -d "$DIR" ] || { echo "refuse: not a directory: $DIR" >&2; exit 2; }

emit() { # <file>
  [ -f "$1" ] || return 0
  cat "$1"
  printf '\n'
}

# The version must have substance: at least a context file or one item.
if [ ! -f "$DIR/00_context.md" ] && ! ls "$DIR"/items/*.md >/dev/null 2>&1; then
  echo "refuse: $DIR has neither 00_context.md nor any items/*.md — an empty version is not a plan" >&2
  exit 2
fi

first=1
sep() { [ "$first" -eq 1 ] && first=0 || printf '\n'; }

sep; emit "$DIR/00_context.md"
# Numeric sort on the item id (W-10 sorts AFTER W-2; a lexicographic sort
# flips them — 97-plan-dir's known-bad caught exactly this on first run).
for f in $(ls "$DIR"/items/*.md 2>/dev/null | LC_ALL=C sort -t- -k2,2n); do
  case "$(basename "$f")" in _*) continue ;; esac   # scaffolding, not an item
  sep; emit "$f"
done
sep; emit "$DIR/invariants.md"
sep; emit "$DIR/rederivation.md"
sep; emit "$DIR/delta.md"
exit 0
