#!/usr/bin/env bash
# 95-shell-idioms — narrow lint for the shell idiom traps that have actually
# bitten this codebase (closed list). Each pattern names its incident. The
# header used to say broad linting belongs to shellcheck "which this machine
# lacks"; the machine has it now, and one narrow class of its findings is swept
# below — see the arm for why that class and not the rest.
set -uo pipefail
export LC_ALL=C
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/fixtures/lib.sh"
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)

fails=0

# Trap 1: unquoted command-substitution in a for-in header. Word-split output
# containing glob characters (*, park.*) expands against the cwd — the notify
# preset.all incident. Iterate with a read loop instead.
hits=$(cd "$ROOT" && command grep -rEn 'for [A-Za-z_]+ in \$\(' \
    runtime-scripts self-check/fixtures self-check/drill 2>/dev/null \
  | command grep -v '95-shell-idioms' \
  | command grep -vE ':[0-9]+:[[:space:]]*#' \
  | command grep -v 'in \$(seq ' || true)
if [ -n "$hits" ]; then
  echo "FAIL for-in-\$(...) (glob/word-split trap — the preset.all incident):"
  printf '%s\n' "$hits" | sed 's/^/    /'
  fails=$((fails+1))
fi

# Trap 2: a bare `[ ... ] && cmd` as a function's last statement. When the test
# is false the function returns 1; under pipefail a caller treats success as
# failure — the sessions_replace teardown incident. Require an `|| true` /
# explicit return, or invert to `[ ... ] || return 0`.
hits=$(cd "$ROOT" && awk '
  FNR==1 { prev="" }
  /^}/ && prev ~ /^[[:space:]]*\[ .* \] && [^|]*[^e]$/ && prev !~ /(\|\| true|return|exit)/ {
    printf "    %s:%d: %s\n", FILENAME, prevnr, prev
  }
  { prev=$0; prevnr=FNR }
' runtime-scripts/lib/*.sh runtime-scripts/session/*.sh runtime-scripts/backends/*.sh \
  runtime-scripts/*.sh 2>/dev/null || true)
if [ -n "$hits" ]; then
  echo "FAIL bare-test-&&-tail before } (pipefail false-failure — the teardown incident):"
  printf '%s\n' "$hits"
  fails=$((fails+1))
fi

# Trap 3: feeding a while-read from printf '%s' (no trailing newline) — read
# drops the final unterminated line; a single-entry stream processes NOTHING
# (the slices-index incident, and notify's before it). Use printf '%s\n'.
hits=$(cd "$ROOT" && command grep -rEn "< <\(printf '%s' " \
    runtime-scripts self-check/fixtures self-check/drill 2>/dev/null \
  | command grep -v '95-shell-idioms' \
  | command grep -vE ':[0-9]+:[[:space:]]*#' || true)
if [ -n "$hits" ]; then
  echo "FAIL while-read fed by printf without trailing newline (final-line drop):"
  printf '%s\n' "$hits" | sed 's/^/    /'
  fails=$((fails+1))
fi

# Non-vacuity: EVERY pattern must fire on a known-bad fixture (a trap added
# without one inherits this requirement).
tmp=$(mktemp -d "${TMPDIR:-/tmp}/sc95.XXXXXX")
printf 'for p in $(list_things); do echo "$p"; done\n' > "$tmp/bad1.sh"
printf 'f() {\n  [ -n "$1" ] && printf %%s "$1"\n}\n' > "$tmp/bad2.sh"
printf 'while IFS= read -r x; do :; done < <(printf '"'"'%%s'"'"' "$body")\n' > "$tmp/bad3.sh"
command grep -qE 'for [A-Za-z_]+ in \$\(' "$tmp/bad1.sh" || { echo "FAIL vacuous trap-1 fixture"; fails=$((fails+1)); }
bad2=$(awk '
  /^}/ && prev ~ /^[[:space:]]*\[ .* \] && [^|]*[^e]$/ && prev !~ /(\|\| true|return|exit)/ { print "hit" }
  { prev=$0 }
' "$tmp/bad2.sh")
[ -n "$bad2" ] || { echo "FAIL vacuous trap-2 fixture"; fails=$((fails+1)); }
command grep -qE "< <\(printf '%s' " "$tmp/bad3.sh" \
  || { echo "FAIL vacuous trap-3 fixture (final-line drop pattern cannot fire)"; fails=$((fails+1)); }
rm -rf "$tmp"

# Trap 4: a variable REFERENCED under `set -u` that nothing assigns — usually a
# one-character misspelling of the name assigned a line above. Measured, and
# the reason this arm exists: `session/notify_event.sh` assigned `_NE_DIR` and
# sourced `"$NE_DIR/../lib/state.sh"`, so the Notification hook died on its
# first line every time the CLI fired it — the producer half of protocol-derived
# idleness, wired in the profile and asserted there by 30-closure, never able to
# write a row. Nothing went red: 75-watch wrote the surface itself.
# SCOPE, deliberately one class and not "run shellcheck": a broad pass over this
# tree returns a large style/quoting set that would be its own project, and a
# false-positive-prone lint teaches people to ignore it (90-provenance-tags'
# rule). SC2153/SC2154 are the unassigned-name class, they are the class that
# just cost a live mechanism, and the tree is clean of them — so a hit is news.
# The instrument was verified against the real defect before its silence was
# trusted: SC2154 alone does NOT catch it (shellcheck reports the misspelling
# case as SC2153), which is why both codes are named.
# The trap count is DERIVED from this file's own headers, never typed. It read
# "4 trap classes swept" while five traps stood in the file — a census kept
# inside the thing it counts, stale from the commit that appended trap 5 and
# stale by two the moment trap 6 landed. Counting the headers cannot drift.
_trap_classes=$(command grep -cE '^# Trap [0-9]+:' "${BASH_SOURCE[0]}" 2>/dev/null || echo 0)
[ "${_trap_classes:-0}" -ge 5 ] || { echo "FAIL the trap-header sweep found ${_trap_classes} classes in this file — the count is derived from '^# Trap N:' headers and something renamed them"; fails=$((fails+1)); }

if command -v shellcheck > /dev/null 2>&1; then
  sc_hits=$(cd "$ROOT" && find runtime-scripts self-check -name '*.sh' -type f | sort | while read -r f; do
      shellcheck -x -f gcc -i SC2153,SC2154 "$f" 2>/dev/null
    done)
  if [ -n "$sc_hits" ]; then
    echo "FAIL unassigned/misspelled variable under set -u (the notify_event.sh class):"
    printf '%s\n' "$sc_hits" | sed "s|$ROOT/||; s/^/    /"
    fails=$((fails+1))
  fi
  # Non-vacuity, same requirement every trap above carries.
  scbad=$(mktemp -d "${TMPDIR:-/tmp}/sc95b.XXXXXX")
  printf '#!/usr/bin/env bash\nset -u\n_X_DIR=$(pwd)\n. "$X_DIR/lib.sh"\n' > "$scbad/bad4.sh"
  # Captured, THEN matched: shellcheck exits non-zero when it has findings, and
  # under `pipefail` a `shellcheck | grep -q` pipeline reports that failure even
  # when the grep matched — the fixture would read as vacuous exactly when it
  # was firing. (Seen here, on this arm, before it landed.)
  scout=$(shellcheck -f gcc -i SC2153,SC2154 "$scbad/bad4.sh" 2>/dev/null || true)
  printf '%s\n' "$scout" | command grep -q 'SC215[34]' \
    || { echo "FAIL vacuous trap-4 fixture (shellcheck does not flag the misspelling this arm exists for)"; fails=$((fails+1)); }
  rm -rf "$scbad"
  sc_note="$_trap_classes trap classes swept"
else
  # Named, never silent: the doctrine this tree applies to every skip.
  echo "shell-idioms: SKIPPING trap 4 (unassigned-name class) — shellcheck is not on this machine; traps 1-3 still swept"
  sc_note="$((_trap_classes - 1)) trap classes swept, trap 4 skipped (no shellcheck)"
fi

# Trap 5: a green-on-FAILURE grep pipe — `PRODUCER | command grep -q X && bad
# "X is present" || ok "X is absent"`. Under pipefail a 141 (grep matched at the
# first hit and exited, the producer took SIGPIPE, pipefail surfaced the
# PRODUCER) makes `&& bad` skip and `|| ok` fire, so the arm reports the
# regression ABSENT at the exact moment it is present — the 141 requires an early
# match. Same family as trap 2 and as trap 4's own fixture note above: a pipefail
# consequence.
# The incident, and it is a reproduction rather than a field failure, said so
# plainly: 45-halt.sh's screen-inlining guard was driven through the real state
# store with `--- screen ---` sitting in a 340,950-byte halt surface, and it
# printed `ok: halt surface holds kv only`. Its regression is anti-correlated with
# its own detection — inlining a screen dump is what grows the surface past the
# ~64 KiB pipe-buffer floor. 77 constructs of this shape were converted to
# herestrings; this arm is what stops the shape coming back.
# Scope: every *.sh under self-check/, which is where ok/bad live, EXCEPT this
# file — traps 1 and 3 exclude themselves the same way, and here the exclusion
# costs nothing real: 95-shell-idioms never calls ok/bad, so the shape cannot
# exist in it, while its own known-bad fixture builder writes the shape on one
# line and would otherwise be reported as a hit against itself.
# The predicate is the census one: a non-comment line piping into
# `command grep -q` whose 3-line window reaches `|| ok` without `&& ok`.
_g5() { # file -> "file:line: text" per green-on-failure grep pipe
  awk '
    { L[NR]=$0 }
    END {
      for (i = 1; i <= NR; i++) {
        if (L[i] ~ /^[[:space:]]*#/) continue
        if (L[i] !~ /\|[[:space:]]*command grep -q/) continue
        win = L[i] "\n" L[i+1] "\n" L[i+2]
        if (index(win, "|| ok") > 0 && index(win, "&& ok") == 0)
          printf "%s:%d: %s\n", FILENAME, i, L[i]
      }
    }
  ' "$1"
}
# The floor this file's own history demands: an arm whose zero-state IS its
# expected state proves nothing until the set it sweeps is shown to be non-empty.
# (The false-floor class was fixed in 55-monitor, recurred in 45-halt, and caught
# the maintainer twice in one round on an empty-file byte-diff.) This file counts
# failures rather than calling ok/bad, so the precondition is written in that
# form.
n5=$(( $(cd "$ROOT" && find self-check -name '*.sh' -type f | wc -l) ))
if [ "$n5" -lt 20 ]; then
  echo "FAIL trap-5 sweep floor: only $n5 shell files under self-check/ — a zero from this sweep would be a floor, not a verdict"
  fails=$((fails+1))
fi
hits=$(cd "$ROOT" && find self-check -name '*.sh' -type f | sort \
  | command grep -v '/95-shell-idioms\.sh$' \
  | while read -r f; do _g5 "$f"; done)
if [ -n "$hits" ]; then
  echo "FAIL green-on-failure grep pipe (a 141 makes the arm report the regression ABSENT — the 45-halt screen-inlining reproduction):"
  printf '%s\n' "$hits" | sed 's/^/    /'
  fails=$((fails+1))
fi
# Non-vacuity, same requirement every trap above carries: the arm must name a
# planted instance with file:line.
t5=$(mktemp -d "${TMPDIR:-/tmp}/sc95c.XXXXXX")
{ printf 'state_get "$ws" halt | command grep -q "^--- screen ---$" \\\n'
  printf '  && bad "screen text is still inlined" \\\n'
  printf '  || ok "halt surface holds kv only"\n'; } > "$t5/bad5.sh"
h5=$(_g5 "$t5/bad5.sh")
case "$h5" in
  *"bad5.sh:1: "*) : ;;
  *) echo "FAIL vacuous trap-5 fixture (the sweep does not name the planted green-on-failure pipe; got: ${h5:-<nothing>})"; fails=$((fails+1)) ;;
esac
rm -rf "$t5"

# Trap 6: an ERE INTERVAL `{n,m}` inside an awk program. mawk 1.3.4 supports
# none of them — `/^#{1,6} /` simply never matches — and mawk is the DEFAULT awk
# on Debian and Ubuntu, where `/usr/bin/awk` is an alternatives symlink. The
# incident: both plan-excerpt arms and four checks were interval-keyed, so on
# such a box the runtime did not fail, it returned a WRONG CUT in silence (the
# W-arm kept another slice's item and the history it exists to drop), while the
# checks that would have caught it were themselves red for the same reason.
# `grep -E` and `sed -E` DO support intervals, so a hit on one of their lines is
# legal and excluded; what is left is an awk program, including the multi-line
# ones whose interval sits on a line carrying no command at all — which is
# exactly where this hid. Comment lines are excluded like every trap here.
_g6() { command grep -rHnE '\{[0-9]+,[0-9]*\}' "$@" 2>/dev/null \
  | command grep -vE ':[0-9]+:[[:space:]]*#' \
  | command grep -vE 'grep|sed|re\.match|re\.compile|re\.sub' \
  | command grep -v '95-shell-idioms' \
  | command grep -v '90-provenance-tags.sh:[0-9]*:scenario-code' || true; }
# The one carve-out, NAMED so it can only shrink: `90-provenance-tags`'s pattern
# table defines its regexes on bare data lines and feeds them to `grep -qE`,
# which supports intervals. Floored below against its own consumer, so a stale
# carve-out cannot pass its successor.
command grep -qE 'command grep -qE "\$pat"' "$ROOT/self-check/checks/90-provenance-tags.sh" \
  || { echo "FAIL trap-6 carve-out is stale: 90-provenance-tags no longer feeds its pattern table to grep -qE, so its intervals are no longer legal"; fails=$((fails+1)); }
hits=$(cd "$ROOT" && _g6 runtime-scripts self-check)
if [ -n "$hits" ]; then
  echo "FAIL ERE interval inside an awk program (mawk has no intervals — the silent-wrong-cut incident):"
  printf '%s\n' "$hits" | sed 's/^/    /'
  fails=$((fails+1))
fi
# Non-vacuity, both directions: the sweep must fire on a planted awk interval
# and must NOT fire on the same interval inside a grep -E, which is legal.
t6=$(mktemp -d "${TMPDIR:-/tmp}/sc95d.XXXXXX")
{ printf 'awk %s\n' "'/^#{1,6} / { print }'"; } > "$t6/bad6.sh"
case "$(_g6 "$t6/bad6.sh")" in
  *bad6.sh:1:*) : ;;
  *) echo "FAIL vacuous trap-6 fixture (a planted awk interval was not named; got: $(_g6 "$t6/bad6.sh"))"; fails=$((fails+1)) ;;
esac
printf 'command grep -qE "^#{1,6} " "$f"\n' > "$t6/good6.sh"
[ -z "$(_g6 "$t6/good6.sh")" ] \
  || { echo "FAIL trap-6 over-fires: an interval inside a grep -E is legal and was flagged"; fails=$((fails+1)); }
rm -rf "$t6"

echo "shell-idioms: $sc_note, $fails failing"
[ "$fails" -eq 0 ]
