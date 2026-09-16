#!/usr/bin/env bash
# 96-state-exits — every state a row of `iteration-log/` can hold has a rule
# in protocol §4.11 that takes it OUT of the full-text section, to the index.
#
# WHY IT EXISTS. The log is the one file in the tree with no line cap:
# protocol §defaults says so in as many words, and A§11 says what stands in
# for one — entries "closed or retired at retro prune to one-line index rows
# … that, not a line cap, is what bounds it". So the bound is exactly as
# complete as the set of exit rules. A state with no exit is a class of row
# that accumulates in full text forever, and no cap check can see it, because
# the whole point is that there is no cap to breach. The classes that never
# leave are also the ones that grow: a row accretes anchors and resolution
# notes as it is confirmed, so the longest rows are the ones with no way out.
#
# HONEST BOUNDARY: this checks that an exit rule EXISTS and names the state.
# It does not check that anyone ran it, that it fires often enough to keep the
# file small, or that the row it prunes was the right one. Retro is the only
# party that prunes and no retro has ever run (VD-10 is the debt row for
# exactly that), so a green result here is a claim about the text, never about
# the file's size on disk. It also cannot tell a state that is deliberately
# permanent from one that was forgotten — the model-dependency register is
# permanent by design (A§11) and is out of this check's scan on purpose.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/fixtures/lib.sh"

LOG_DIR="$WF_ROOT/iteration-log"
LOG="$LOG_DIR/INDEX.md"      # rows: 'Open observations' table, status column
LEGEND="$LOG_DIR/TEMPLATE.md"  # the state vocabulary, one bullet per state
PROTO="$WF_ROOT/runtime-docs/protocol.md"

# --- the premise this check rests on ----------------------------------------
# If the log ever gained a line cap, pruning would stop being the only bound
# and this check's rationale would need re-reading rather than silently
# holding. Assert the premise instead of assuming it.
command grep -q 'carries no line cap' "$PROTO" \
  || bad "protocol §defaults no longer states that the log carries no line cap — this check's premise (pruning is the only bound) has moved"

# --- the declared state vocabulary ------------------------------------------
legend=$(sed -n '/^- \*\*state\*\*/,$p' "$LEGEND" | head -4)
precond "the log's state legend was found" test "$(printf '%s' "$legend" | wc -c)" -ge 100
states=$(printf '%s' "$legend" | grep -oE '(open|adopted|landing ordered|closed)' | sort -u)
precond "the legend declared states" test "$(printf '%s\n' "$states" | grep -c .)" -ge 2

retro=$(awk '/^### 4\.11/{f=1} f&&/^## 5\./{exit} f' "$PROTO")
precond "protocol §4.11 was extracted" test "$(printf '%s' "$retro" | wc -l)" -ge 20

# §4.11's steps, one block each. An exit rule spans lines — step 5 names
# "sintering candidates" on its first line and "index entry" on its second —
# so a line-at-a-time match would miss every one of them.
step_block() { # <n> -> step n's text, newlines flattened
  printf '%s' "$retro" | awk -v n="$1" '
    $0 ~ "^"n"\\. " {f=1; print; next}
    f && /^[0-9]+\. / {exit}
    f {print}' | tr '\n' ' '
}
precond "§4.11's steps are addressable" test -n "$(step_block 5)"

# The alias map is DECLARED, not guessed. §4.11 step 5 says "sintering
# candidates" and never says `open`; the binding that makes those the same
# thing lives in the legend itself ("`open` = awaiting its second anchor (A§4
# sintering candidate)"). Matching the bare token would pass `open` for the
# wrong reason and red it the day either wording moved. A state with no entry
# here is reported, never skipped — that is what makes a newly added state
# arrive as a failure instead of as silence.
state_alias() {
  case $1 in
    open)            echo 'sintering candidate' ;;
    adopted)         echo 'adopted' ;;
    closed)          echo 'adopted' ;;
    'landing ordered') echo 'sintering candidate' ;;
    *)               echo '' ;;
  esac
}

exit_exists() { # <alias phrase> -> 0 if some §4.11 step names it AND indexes
  local alias=$1 i blk
  for i in 1 2 3 4 5 6 7; do
    blk=$(step_block "$i")
    printf '%s' "$blk" | command grep -qi 'index' || continue
    printf '%s' "$blk" | command grep -qiF "$alias" && return 0
  done
  return 1
}

n=0
while IFS= read -r s; do
  [ -n "$s" ] || continue
  n=$((n + 1))
  alias=$(state_alias "$s")
  if [ -z "$alias" ]; then
    bad "the legend declares state \`$s\` and this check carries no exit phrase for it — a new state needs its §4.11 exit named here"
    continue
  fi
  exit_exists "$alias" \
    || bad "state \`$s\` has no exit: no protocol §4.11 step both names '$alias' and writes to the index, so rows in that state stay in full text forever — and the log has no line cap to catch it (§defaults)"
done <<< "$states"
precond "states were swept" test "$n" -ge 2
[ "$_FAIL" -eq 0 ] && ok "all $n declared row states have a §4.11 rule retiring them to the index"

# --- every row's state is one the legend declares ---------------------------
# Matched BY VALUE, never by column position: these rows carry embedded pipes,
# and reading a table column by index is the failure obs-30/obs-33 measured —
# a severity column came back three cells off, and the escape-aware split that
# fixes one case does not fix the other. A closed vocabulary needs neither.
r=0
while IFS= read -r row; do
  [ -n "$row" ] || continue
  r=$((r + 1))
  hit=0
  while IFS= read -r s; do
    [ -n "$s" ] || continue
    case "$row" in *"| $s |"*) hit=1 ;; esac
  done <<< "$states"
  [ "$hit" -eq 1 ] || bad "an OBS row carries no state from the legend's vocabulary: ${row:0:60}…"
done < <(awk -F'|' '/^\| OBS-/ {gsub(/ /,"",$3); print "| "$3" |"}' "$LOG")
if [ "$r" -gt 0 ]; then
  [ "$_FAIL" -eq 0 ] && ok "all $r OBS rows carry a legend-declared state"
else
  note "fresh state file: no OBS rows to check against the legend yet"
fi
# The by-value matcher, routed through a fabricated row so it is proven live
# whether or not the real log has rows.
row_has_state() { # <row> -> rc 0 if a legend state appears as a cell
  local s
  while IFS= read -r s; do
    [ -n "$s" ] || continue
    case "$1" in *"| $s |"*) return 0 ;; esac
  done <<< "$states"
  return 1
}
precond "the matcher accepts a legend state" row_has_state "| open |"
known_bad "a row whose state is outside the legend is caught" row_has_state "| retired |"

# Non-vacuity: route a fabricated exit phrase through the check's OWN detector
# against the real §4.11. A guard that tested a state name instead would prove
# only that the alias map has no such key.
known_bad "a state whose exit rule is absent from §4.11 is caught" \
  exit_exists "zzz-no-such-retirement-rule"

check_done
