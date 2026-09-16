#!/usr/bin/env bash
# 50-slots — every `{SLOT}` a prompt declares has a stated resolution rule in
# protocol §5.1, and no prompt hands an instrument a bare constant NAME. A
# no-lineage instrument is onboarded from its prompt file alone (A§3), so a
# symbol whose home it was never given is unresolvable to it — the prompt
# reads authoritative and the instrument cannot execute it.
#
# HONEST BOUNDARY: this checks that a resolution rule EXISTS for each slot,
# never that the author filled it correctly at run time — with ONE narrowing,
# added at the escape below: the *Template paths* group's targets must resolve
# on disk. Every other group's rule may still name the wrong artifact and pass
# here, caught if at all by the instrument returning off-mandate. The narrowing
# stops where decidability does: `{PLAN_DIR}` → "the current plan version
# directory" names no fixed path, and a check cannot tell a right pointer from
# a wrong one when the pointer is a description.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/fixtures/lib.sh"

PROTO="$WF_ROOT/runtime-docs/protocol.md"
# §5's span: the "## 5." heading to the next "## " heading.
spawn=$(awk '/^## 5\./{f=1} f&&/^## 6\./{exit} f' "$PROTO")
precond "protocol §5 extracted" test "$(printf '%s' "$spawn" | wc -l)" -ge 10

slots=$(grep -rhoE '\{[A-Z_]+\}' "$WF_ROOT/runtime-docs/prompts" | sort -u)
precond "prompts declare slots" test "$(printf '%s\n' "$slots" | grep -c .)" -ge 10

n=0
while IFS= read -r s; do
  [ -n "$s" ] || continue
  n=$((n + 1))
  printf '%s' "$spawn" | command grep -qF "$s" \
    || bad "$s is declared by a prompt and resolved nowhere in protocol §5"
done <<< "$slots"
[ "$_FAIL" -eq 0 ] && ok "all $n declared slots have a resolution rule in §5"

# No SPAWNED prompt may hand its instrument a bare constant name: the value
# goes in, because the instrument has only this file (A§3). Two exclusions,
# both principled rather than convenient:
#   refine_falsification — run by the AUTHOR, warm, who has protocol open;
#   the `(cap DOC_CAP_PROMPT)` marker — maintainer metadata in the title, not
#   an instruction to the instrument.
defined=$(defaults_table | cut -f1)
for c in $defined; do
  hit=$(grep -rln --exclude=refine_falsification.md -- "\`$c\`" \
        "$WF_ROOT/runtime-docs/prompts" || true)
  # drop files whose only hit is the cap marker
  real=""
  for f in $hit; do
    tot=$(grep -o -- "\`$c\`" "$f" | wc -l)
    capline=$(grep -o -- "(cap \`$c\`)" "$f" | wc -l)
    [ "$tot" -gt "$capline" ] && real="$real ${f#"$WF_ROOT"/}"
  done
  [ -z "$real" ] || bad "spawned prompt(s) cite the constant NAME \`$c\` instead of its value:$real"
done
[ "$_FAIL" -eq 0 ] && ok "no spawned prompt hands its instrument an unresolvable constant name"

# --- the Template-path group's targets resolve on disk -----------------------
# Measured escape (recorded round 0 and fired round 1 of a live topic): §5.1 resolved `{FIELD_SET_PATH}` to
# `templates/plan`, which stopped existing when the plan template went
# directory-shaped (3b29498) and the slot rule did not follow. The two
# siblings in its own sentence — `check-record`, `findings` — still resolved,
# and that is what hid it: a consistent naming convention masks single-point
# rot, and the assertion above ("a rule exists") was true the whole time. It
# fires only at the moment an `arch` lens is dispatched and is handed a path to
# a file that is not there; the topic author worked around it twice rather than
# edit a live tree (A§11). Gate-class, so the check lands at the first escape
# (A§1 carve-out i).
tblock=$(printf '%s\n' "$spawn" \
  | awk '/\*Template paths\*/{f=1} f&&/\*Delivery\*/{exit} f' | tr '\n' ' ')
precond "the Template-paths group was found" test -n "$tblock"

template_target_resolves() { # <stem> -> 0 if templates/<stem>.md is on disk
  [ -f "$WF_ROOT/runtime-docs/templates/$1.md" ]
}

t=0
while IFS= read -r pair; do
  [ -n "$pair" ] || continue
  t=$((t + 1))
  slot=$(printf '%s' "$pair" | sed 's/^`\({[A-Z_]*}\)`.*/\1/')
  stem=$(printf '%s' "$pair" | sed 's/.*`\([^`]*\)`$/\1/')
  template_target_resolves "$stem" \
    || bad "§5.1 resolves $slot to templates/$stem.md, which is not on disk — a dispatched instrument is handed a path to nothing"
done < <(printf '%s' "$tblock" | command grep -oE '`\{[A-Z_]+\}` +→ +`[A-Za-z0-9_/-]+`')
precond "Template-path pairs were parsed" test "$t" -ge 3
[ "$_FAIL" -eq 0 ] && ok "all $t *Template paths* targets resolve under runtime-docs/templates/"

known_bad "an unresolved slot is caught" bash -c '
  printf "read {NOT_A_DECLARED_SLOT} first\n" > "$1/probe.md"
  s=$(grep -ohE "\{[A-Z_]+\}" "$1/probe.md")
  printf "%s" "$2" | grep -qF "$s"' _ "$(sc_tmpdir)" "$spawn"

known_bad "a Template-path slot resolving to nothing is caught" \
  template_target_resolves "plan"

check_done
