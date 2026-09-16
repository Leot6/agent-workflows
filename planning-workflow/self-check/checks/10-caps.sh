#!/usr/bin/env bash
# 10-caps — every formal document is under its `§defaults` cap, and every
# formal document HAS a cap. The second direction is the load-bearing one: a
# new doc added without a cap row is uncapped forever and nothing else notices.
#
# HONEST BOUNDARY: a line count says nothing about whether the content earns
# the space. A file at 799/800 of dense restatement passes; the deletion lens
# (protocol §7) is what reads for that.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/fixtures/lib.sh"

cap_for() { # <abs path> -> constant name, or "" if the file is exempt
  case "${1#"$WF_ROOT"/}" in
    design/architecture.md)   echo DOC_CAP_ARCH ;;
    design/rationale.md)      echo DOC_CAP_RATIONALE ;;
    README.md)                echo DOC_CAP_README ;;
    runtime-docs/protocol.md) echo DOC_CAP_PROTOCOL ;;
    runtime-docs/claims.md)   echo DOC_CAP_CLAIMS ;;
    runtime-docs/prompts/*)   echo DOC_CAP_PROMPT ;;
    runtime-docs/templates/*) echo DOC_CAP_TEMPLATE ;;
    *)                        echo "" ;;
  esac
}

declare -A CAP
while IFS=$'\t' read -r n v; do CAP[$n]=$v; done < <(defaults_table)
precond "§defaults parsed" test "${#CAP[@]}" -ge 15

n=0
while IFS= read -r doc; do
  [ -f "$doc" ] || continue
  rel=${doc#"$WF_ROOT"/}
  c=$(cap_for "$doc")
  if [ -z "$c" ]; then
    bad "$rel is in the formal region but no cap governs it"
    continue
  fi
  limit=${CAP[$c]:-}
  if [ -z "$limit" ]; then bad "$rel maps to $c, which has no §defaults row"; continue; fi
  lines=$(wc -l < "$doc")
  n=$((n + 1))
  [ "$lines" -le "$limit" ] \
    && ok "$rel $lines/$limit ($c)" \
    || bad "$rel $lines/$limit ($c) — over cap"
done < <(formal_docs)
precond "the sweep saw the whole formal region" test "$n" -ge 20

# The two exemptions are stated, not assumed (protocol §1's closing paragraph).
command grep -qE 'iteration-log(/|\.md)` carries no line cap' "$WF_ROOT/runtime-docs/protocol.md" \
\
  && ok "the iteration log's exemption is stated (pointer + directory alike)" \
  || bad "the iteration log is uncapped with no stated exemption"

# No .md may sit outside the region A§5.1 partitions — such a file is uncapped,
# unscanned by 40-regions, and invisible to every other check.
strays=$(stray_docs)
[ -z "$strays" ] \
  && ok "no .md outside the formal region, the state file, discussion/ or self-check/" \
  || bad "documents outside every rule's reach: $(printf '%s' "$strays" | sed "s|$WF_ROOT/||" | tr '\n' ' ')"

# Non-vacuity: route a fabricated over-cap file through the check's OWN
# mapping and limit lookup, not through a re-typed comparison.
probe_over_cap() {
  local d; d=$(sc_tmpdir); mkdir -p "$d/runtime-docs/templates"
  local f="$d/runtime-docs/templates/probe.md"
  seq 1 $(( ${CAP[DOC_CAP_TEMPLATE]} + 1 )) > "$f"
  local c; c=$(WF_ROOT="$d" cap_for "$f")
  [ -n "$c" ] || return 2
  [ "$(wc -l < "$f")" -le "${CAP[$c]}" ]
}
known_bad "a file one line over its own cap is caught" probe_over_cap

check_done
