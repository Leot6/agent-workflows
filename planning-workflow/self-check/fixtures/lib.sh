#!/usr/bin/env bash
# self-check/fixtures/lib.sh — shared helpers for every check.
#
# Three rules the helpers exist to enforce, all of them the tree's own:
#   ok/bad      — a check reports affirmatively (A§8's release principle:
#                 never the absence of complaints).
#   precond     — a check that checked nothing FAILS. A sweep whose input set
#                 came out empty passes vacuously otherwise, which is the
#                 "verified table under a false summary" shape claims.md
#                 rule 1 names.
#   known_bad   — every check ends by proving it can fail: a fabricated
#                 violation must fire, routed through the check's OWN
#                 detection code. This is the acceptance-claim shape
#                 (claims.md) applied to the checker itself — a hand-picked
#                 passing point is not a proof, so a guard that would still
#                 fire with the detector deleted proves nothing.
#
# What the pair does and does not establish, stated because it is easy to
# over-read: `known_bad` proves the detection logic it invokes is live;
# `precond`'s counter proves the sweep ran over real INPUT — not that any
# assertion was made about it, so deleting a `bad` line while leaving the loop
# passes both guards. Measured. What catches that is review of the check, and
# the runner's requirement that every check reach `check_done`. Neither
# survives a counter that is deliberately faked — that is the deliberate-fraud case A§14's last row
# concedes for the whole tree, and no self-administered check escapes it.
set -uo pipefail
export LC_ALL=C

WF_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
export WF_ROOT

_FAIL=0
_LINES=0

ok() { printf '  ok   %s\n' "$*"; _LINES=$((_LINES + 1)); }
bad() { printf '  FAIL %s\n' "$*"; _FAIL=1; _LINES=$((_LINES + 1)); }
# note — a named non-assertion: a state the check deliberately does not sweep
# (a fresh log with no rows yet) is SAID, never left as silence.
note() { printf '  note %s\n' "$*"; }

# precond <description> <command...> — a false precondition is a check defect,
# not a tree defect, and is reported as such.
precond() {
  local desc=$1; shift
  if "$@"; then
    printf '  pre  %s\n' "$desc"
  else
    printf '  FAIL precondition not met (the check itself is broken or its input set is empty): %s\n' "$desc"
    _FAIL=1
  fi
}

# known_bad <description> <command...> — the command must FAIL on a fabricated
# violation. Two ways to be blind, both caught:
#   rc 0   — the detector ran and did not fire.
#   rc 127 — the detector was not there at all (renamed, typo'd, deleted).
#   any other rc — the probe could not even set up (a `return 2`, a grep
#            error). That is a broken guard, not a catch: only rc 1, the code
#            a failed test or a no-match grep returns, means the detector ran
#            and fired. The one mechanism proving a check is not blind must
#            not be blind to its own breakage.
known_bad() {
  local desc=$1; shift
  "$@"; local rc=$?
  case $rc in
    0)   printf '  FAIL validator blind — a fabricated violation was not caught: %s\n' "$desc"; _FAIL=1 ;;
    1)   printf '  ok   known-bad fires: %s\n' "$desc" ;;
    *)   printf '  FAIL known-bad guard is broken (rc %d — not found, or the probe could not set up), so it proves nothing: %s\n' "$rc" "$desc"; _FAIL=1 ;;
  esac
}

sc_tmpdir() {
  local d
  d=$(mktemp -d "${TMPDIR:-/tmp}/pwsc.XXXXXX")
  printf '%s' "$d"
}

# The formal region — the scan set for every doc check (A§5.1).
formal_docs() {
  find "$WF_ROOT/design" "$WF_ROOT/runtime-docs" -name '*.md' 2>/dev/null
  echo "$WF_ROOT/README.md"
}

# Every .md in the tree that formal_docs() does NOT cover and no rule exempts.
# A§5.1 partitions the tree as it stands; nothing re-partitions it when a file
# is added, so a doc dropped anywhere else would be uncapped, unscanned for
# dates and state ids, and invisible to every check. This is what notices.
stray_docs() {
  find "$WF_ROOT" -name '*.md' -not -path "$WF_ROOT/design/*" \
       -not -path "$WF_ROOT/runtime-docs/*" -not -path "$WF_ROOT/discussion/*" \
       2>/dev/null \
    | grep -v -e "^$WF_ROOT/README.md$" -e "^$WF_ROOT/iteration-log/.*$" || true
}

# The harvest set for reference/constant sweeps: the formal region plus the
# state file. Deliberately NOT the whole tree — discussion/ is gitignored and
# deletes as a unit (A§13), so scratch notes must neither red the harness nor
# satisfy its preconditions.
harvest_docs() {
  formal_docs
  find "$WF_ROOT/iteration-log" -name '*.md' -type f 2>/dev/null || true
}

# The §defaults table, one "NAME<TAB>VALUE" line per row.
defaults_table() {
  awk -F'|' '/^\| `[A-Z_0-9]+` \|/ {
    name=$2; val=$3
    gsub(/[` ]/, "", name); gsub(/^ +| +$/, "", val); gsub(/`/, "", val)
    print name "\t" val
  }' "$WF_ROOT/runtime-docs/protocol.md"
}

check_done() {
  if [ "$_FAIL" -eq 0 ]; then
    printf '  — %d assertions, all clean\n' "$_LINES"
    exit 0
  fi
  exit 1
}
