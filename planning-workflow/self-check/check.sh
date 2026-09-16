#!/usr/bin/env bash
# self-check/check.sh — the conformance harness for this workflow tree.
# Dev-time only; nothing here runs during a topic (A§7 rung 2's executable
# form: doc-cap conformance and the tree's other mechanical invariants).
#
# WHY IT EXISTS. A§7 sends judgment to the cheapest instrument that can hold
# it. These invariants are greppable, and for eight release rounds they were
# checked instead by no-lineage cold reads — the most expensive instrument in
# the tree, sampling a space a script covers exhaustively. Conformance defects
# still escaped (`design/rationale.md` §4c). This is that work, moved down a
# rung, so the cold reads are spent on the adversarial class where their yield
# does not fall.
#
# WHAT IT DOES NOT DO — the honest boundary, per check in each file's header,
# and in one line here: **every check catches a broken *reference*, never a
# wrong *idea*.** A §N that resolves but points at the wrong topic, a constant
# whose value is badly chosen, a vocabulary that matches on both sides and is
# wrong on both — all pass. Those stay the release round's two lens classes
# (`runtime-docs/protocol.md` §7). A green run is a precondition for a release
# round, never a substitute for one.
#
# Exit: 0 all clean · 1 any check failed.

set -uo pipefail
export LC_ALL=C
SC_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

usage() { echo "usage: check.sh [--list] [--only <name>]" >&2; exit 2; }

# Any digits then a hyphen — not exactly two, so the slot after 90- does not
# vanish silently. A file that does not match is reported, never skipped.
collect() { # "name<TAB>path", declared order = filename prefix
  local f
  for f in "$SC_DIR"/checks/*.sh; do
    [ -e "$f" ] || continue
    case "$(basename "$f")" in
      [0-9]*-*.sh) printf '%s\t%s\n' "$(basename "$f" .sh | sed 's/^[0-9]*-//')" "$f" ;;
      *) printf 'UNNAMED\t%s\n' "$f" ;;
    esac
  done
}
list_names() { collect | cut -f1; }

main() {
  local only="" list=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --list) list=1; shift ;;
      --only) only=${2:?--only needs a name}; shift 2 ;;
      *) usage ;;
    esac
  done
  [ "$list" -eq 1 ] && { list_names; exit 0; }
  if [ -n "$only" ] && ! list_names | command grep -qxF "$only"; then
    echo "unknown check '$only'" >&2; usage
  fi

  echo "== planning-workflow self-check =="
  echo "tree: $(cd "$SC_DIR/.." && pwd)"

  # The runner is a sweep, and lib.sh's precond doctrine binds it too: a run
  # that executed nothing must not report success. Without this, an emptied or
  # unreadable checks/ prints "0 passed, 0 failed" and exits 0 — the green
  # banner protocol §7 reads as the conformance class's first act.
  local n_avail; n_avail=$(collect | grep -c .)
  if [ "$n_avail" -lt 8 ]; then
    echo "FAIL runner: only $n_avail checks found (expected at least 8) — the"
    echo "     sweep's own input set is short; fix that before trusting a result."
    return 1
  fi
  local unnamed; unnamed=$(collect | grep -c '^UNNAMED') || true
  if [ "$unnamed" -gt 0 ]; then
    echo "FAIL runner: $unnamed file(s) in checks/ do not match <digits>-<name>.sh"
    collect | grep '^UNNAMED' | cut -f2 | sed 's/^/       /'
    return 1
  fi

  local pass=0 fail=0 failed="" name path log rc
  while IFS=$'\t' read -r name path; do
    [ -n "$only" ] && [ "$name" != "$only" ] && continue
    log=$(mktemp "${TMPDIR:-/tmp}/pwsc-log.XXXXXX")
    bash "$path" > "$log" 2>&1; rc=$?
    if [ "$rc" -eq 0 ] && ! grep -q '^  — ' "$log"; then
      # Exit 0 without check_done's summary line: the file is empty, or its
      # body never ran. Counting FILES (n_avail) cannot see that.
      fail=$((fail + 1)); failed="$failed $name"
      echo "FAIL $name — exited 0 without reaching check_done; it asserted nothing"
      sed 's/^/    /' "$log"
    elif [ "$rc" -eq 0 ]; then
      pass=$((pass + 1)); echo "PASS $name"; sed 's/^/    /' "$log"
    else
      fail=$((fail + 1)); failed="$failed $name"
      echo "FAIL $name (rc=$rc)"; sed 's/^/    /' "$log"
    fi
    rm -f "$log"
  done < <(collect)

  echo "-----------------------------------------------"
  echo "summary: $pass passed, $fail failed"
  [ -n "$failed" ] && echo "failed:$failed"
  [ "$fail" -eq 0 ]
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && main "$@"
