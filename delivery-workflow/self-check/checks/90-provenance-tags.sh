#!/usr/bin/env bash
# 90-provenance-tags — the formal tree carries no working-material provenance
# tags. The working material (the redesign brief, discussion notes, observation
# ledgers) is deletable; a reference to it in a formal file becomes a dangling
# cryptic token the moment it is deleted. Patterns are a CLOSED, conservative
# list (a false-positive-prone lint teaches people to ignore it). Formal
# regions: design/ runtime-docs/ runtime-scripts/ config/ self-check/
# iteration-log/ README.md.
#
# HONEST BOUNDARY, measured — this sweep is a REGRESSION FIXTURE for shapes that
# have leaked, never a closure of the class. The candidate space is 100 distinct
# tokens over the tracked tree
#   git grep -hoE '\b([A-Z]{1,4}-[0-9]+[a-z]?|[A-Z][0-9]{1,2}[a-z]?)\b' -- .
# and 21 of those also occur in working material. NINETEEN of the 21 are the
# tree's own live namespaces: C0..C9 and P1..P10 (review-standards' postcheck
# and precheck checklists), S1..S12 (drill scenarios, defined in drill.sh),
# M1..M9 (v1's retired ceremony). So a working document coining `C3` yields a
# token that is simultaneously correct twice in review-standards and dangling
# elsewhere — no pattern separates those, and neither does a "must resolve in
# the tree" test, because SHA-1 / UTF-8 / RFC-2119 / AVX-512 resolve nowhere and
# are fine. An inventory of the ~12 legitimate NAMESPACES would catch a newly
# coined family prospectively but still not the `C3` case; it was evaluated and
# deferred. The primary
# defense is the maintenance rule at `runtime-docs/maintenance.md` §1 — remove
# the tag, does the sentence still stand? — and this sweep is the cheap half.
set -uo pipefail
export LC_ALL=C
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/fixtures/lib.sh"

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
SELF="self-check/checks/90-provenance-tags.sh"

# Each entry: name<TAB>grep -E pattern. Built by concatenation so this file
# does not trigger itself.
BRIEF='DESIGN_'
BRIEF="${BRIEF}BRIEF"
patterns=$(cat <<EOF
brief-file	${BRIEF}
brief-ref	[Tt]he (design )?brief\b
root-cause	root[- ]cause #?[0-9]
observation-id	\bO-[0-9]+\b
scenario-code	\((A[1-7]b?|B[1-3]|C[1-4]|D[1-2]|E1|F[1-2]|G[1-3]|H[0-9]{1,2})([;,)]| both)
scenario-word	scenarios? (A[0-9]|[B-H][0-9])
ruling-date	ruling[s]? 2026|owner-ruled 2026|2026-08-0[0-9]
discussion-path	discussion/[A-Za-z0-9]
codename-DP	\b[DP]-[0-9]+\b
EOF
)

fails=0 total=0
while IFS=$(printf '\t') read -r name pat; do
  [ -n "$name" ] || continue
  total=$((total+1))
  hits=$(cd "$ROOT" && command grep -rEn "$pat" \
      design runtime-docs runtime-scripts config self-check iteration-log README.md 2>/dev/null \
    | command grep -v "^$SELF:" | command grep -v '\.rot:' || true)
  if [ -n "$hits" ]; then
    echo "FAIL provenance-tag '$name' in formal regions:"
    printf '%s\n' "$hits" | head -20 | sed 's/^/    /'
    n=$(printf '%s\n' "$hits" | command grep -c .)
    [ "$n" -gt 20 ] && echo "    ... ($n total)"
    fails=$((fails+1))
  fi
done <<EOF2
$patterns
EOF2

# Non-vacuity, PER PATTERN. The old bar was `>= 3` against a fixture that
# carried three shapes, so five of the eight registered patterns were never
# exercised by anything — including `discussion-path`, the one whose whole
# subject is this harm. A pattern nobody drives is a pattern nobody notices
# rotting, and the suite claims two-direction non-vacuity EVERYWHERE
# (`design/migration-and-acceptance.md` §3). One line carrying one instance of
# every registered shape, and an equality: registering a pattern now OWES its
# token here, mechanically, or this check goes red.
tmp=$(mktemp -d "${TMPDIR:-/tmp}/sc90.XXXXXX")
printf 'see %s §4.3, the design brief, root cause #5 (A6), scenario B1, O-12, ruling 2026, discussion/x.md, D-6\n' \
  "$BRIEF" > "$tmp/bad.md"
bad_hits=0 unfired=""
while IFS=$(printf '\t') read -r name pat; do
  [ -n "$name" ] || continue
  if command grep -qE "$pat" "$tmp/bad.md"; then bad_hits=$((bad_hits+1)); else unfired="$unfired $name"; fi
done <<EOF3
$patterns
EOF3
rm -rf "$tmp"
[ "$bad_hits" -eq "$total" ] \
  || { echo "FAIL vacuous: $bad_hits/$total patterns fire on the known-bad fixture; never exercised:$unfired"; fails=$((fails+1)); }

echo "provenance-tags: $total patterns swept, $fails failing"
[ "$fails" -eq 0 ]
