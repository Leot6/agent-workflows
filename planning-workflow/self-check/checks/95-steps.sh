#!/usr/bin/env bash
# 95-steps — a declared step range still covers the numbered steps it claims.
#
# THE DEFECT THIS EXISTS FOR, measured: §0 gained a step 6 while §0.0 went on
# saying "steps 1–5 below do not apply". The range still *resolved* — steps 1
# through 5 all existed — so nothing caught it; what broke is that it no
# longer *covered* the list. Appending is the operation that falsifies a
# head-declared range, and a reader never needs the head, so re-reading does
# not find it. A§1 carve-out (i): the check lands at the first escape.
#
# Two live claims of this shape, both partitions over a numbered list:
#   §0.0   — "steps 1–N below do not apply" must cover every step §0 numbers
#            except step 0, which is the router making the claim.
#   §4.11  — the author's steps and the maintainer's steps must partition
#            §4.11's list exactly: no step unassigned, none assigned twice.
#            The maintainer half is restated in three other places, so the
#            rendered spec is compared against each.
#
# HONEST BOUNDARY, two parts. (1) This checks RANGES over NUMBERED lists.
# A cardinality declared over a prose list — "coverage, four directions"
# followed by four semicolon-separated clauses — has no reliable terminator a
# script can find, and the same session that produced the §0 defect produced
# one of those too. It is not covered here and is not cheaply mechanizable;
# it stays an editing precondition and the conformance lens's work. (2) A
# range that covers the list but assigns a step to the wrong actor passes.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/fixtures/lib.sh"

PROTO="$WF_ROOT/runtime-docs/protocol.md"
precond "protocol.md exists" test -f "$PROTO"

DASH=$'–'   # en dash, the one the tree writes ranges with
# Everything below normalises it to ASCII "-" FIRST. Under lib.sh's LC_ALL=C a
# multibyte char inside a bracket expression is three separate bytes and inside
# `tr` is three separate mappings — both silently produce garbage, and a
# known_bad that compares against garbage still "fires". Measured, on this file.
deash() { sed "s/$DASH/-/g"; }

# "1 and 6" -> 1 6 · "2-5 and 7" -> 2 3 4 5 7 · "1-6" -> 1 2 3 4 5 6
parse_spec() {
  # `printf '%s'` without the newline loses the LAST field: `read` returns
  # non-zero on an unterminated final line and the loop never sees it.
  # Measured on this file — "1 and 6" came back as just "1".
  printf '%s\n' "$1" | deash | sed 's/ and /,/g' | tr ',' '\n' \
  | while IFS= read -r part; do
      part=$(printf '%s' "$part" | tr -d ' ')
      case "$part" in
        *-*) seq "${part%%-*}" "${part##*-}" ;;
        [0-9]*) printf '%s\n' "$part" ;;
      esac
    done | sort -n | tr '\n' ' ' | sed 's/ $//'
}

# 2 3 4 5 7 -> "2–5 and 7"  (the tree's own rendering, so a changed set fails
# the literal comparison below rather than silently agreeing)
render_spec() {
  printf '%s\n' $1 | awk -v d="$DASH" '
    { n[NR] = $1 }
    END {
      out = ""; i = 1
      while (i <= NR) {
        j = i; while (j < NR && n[j+1] == n[j] + 1) j++
        piece = (j > i + 1) ? n[i] d n[j] : (j == i + 1 ? n[i] ", " n[j] : n[i])
        out = (out == "") ? piece : out " and " piece
        i = j + 1
      }
      print out
    }'
}

# --- §0: the router's range covers every step it routes past ---------------
sec0=$(awk '/^## 0\./{f=1} f&&/^## 1\./{exit} f' "$PROTO" | deash)
steps0=$(printf '%s\n' "$sec0" | grep -oE '^[0-9]+\. ' | tr -d '. ' | sort -n | tr '\n' ' ' | sed 's/ $//')
precond "§0's numbered steps were found" test "$(printf '%s\n' $steps0 | grep -c .)" -ge 5

declared0=$(printf '%s\n' "$sec0" | grep -oE "steps [0-9]+-[0-9]+" | head -1 | sed 's/steps //')
precond "§0.0 declares a step range" test -n "$declared0"

routed=$(printf '%s\n' $steps0 | grep -v '^0$' | tr '\n' ' ' | sed 's/ $//')
covered=$(parse_spec "$declared0")
[ "$covered" = "$routed" ] \
  && ok "§0.0's \"steps $declared0\" covers every step §0 numbers past the router ($routed)" \
  || bad "§0.0 declares \"steps $declared0\" = [$covered] but §0 numbers [$routed] — the range no longer covers the list"

# --- §4.11: author ∪ maintainer partitions the procedure -------------------
sec411=$(awk '/^### 4\.11/{f=1} f&&/^## 5\./{exit} f' "$PROTO" | deash)
steps411=$(printf '%s\n' "$sec411" | grep -oE '^[0-9]+\. ' | tr -d '. ' | sort -n | tr '\n' ' ' | sed 's/ $//')
precond "§4.11's numbered steps were found" test "$(printf '%s\n' $steps411 | grep -c .)" -ge 5

actor=$(printf '%s\n' "$sec411" | grep -m1 -A4 '^Actors')
auth_spec=$(printf '%s' "$actor" | grep -oE "steps [0-9]+ and [0-9]+" | head -1 | sed 's/steps //')
mnt_spec=$(printf '%s' "$actor" | grep -oE "steps [0-9]+-[0-9]+ and [0-9]+" | head -1 | sed 's/steps //')
precond "§4.11 names both actors' step sets" test -n "$auth_spec" -a -n "$mnt_spec"

union=$(printf '%s\n' $(parse_spec "$auth_spec") $(parse_spec "$mnt_spec") | sort -n | tr '\n' ' ' | sed 's/ $//')
dedup=$(printf '%s\n' $union | sort -nu | tr '\n' ' ' | sed 's/ $//')
[ "$union" = "$dedup" ] \
  && ok "§4.11's two actor sets are disjoint" \
  || bad "§4.11 assigns a step to both actors: author [$auth_spec] + maintainer [$mnt_spec]"
[ "$dedup" = "$steps411" ] \
  && ok "§4.11's author [$auth_spec] + maintainer [$mnt_spec] partition its $(printf '%s\n' $steps411 | grep -c .) steps" \
  || bad "§4.11 numbers [$steps411] but its actors cover [$dedup] — a step belongs to nobody"

# --- the maintainer half is restated elsewhere; the set must render the same
want="steps $(render_spec "$(parse_spec "$mnt_spec")")"
# EXACT, not a floor. Measured: with `-ge 4`, dropping "and 7" from one of the
# five restatements left four and passed — the one failure mode this assertion
# is for. The five: protocol §4.11's own Actors paragraph, §7 twice (the
# maintainer variant and the terminal-close-out paragraph), and the close-out
# template twice (Next's final-close-out line and the fence comment). A sixth
# legitimate restatement reds this and the number is bumped — which is the
# point: it cannot be added without someone reading it.
RESTATEMENTS=5
n=$(( $(harvest_docs | xargs grep -oF "$want" 2>/dev/null | wc -l) ))
[ "$n" -eq "$RESTATEMENTS" ] \
  && ok "the maintainer half renders as \"$want\" in all $n places that restate it" \
  || bad "§4.11's maintainer set renders as \"$want\", found $n times, expected $RESTATEMENTS — a restatement lost part of the set, or a new one was added unread"

# --- §5.1: the slot-resolution rules, a labelled list with a declared count -
# The same family as the two above, and the third instance the same session
# produced: two groups were appended in round 8 and the "three rules" at the
# head was never re-read. It survived three full-tree adversarial rounds. This
# one IS countable, because each group carries a markup label — which is why
# the labels were normalised when the count was fixed.
span=$(awk '/Every slot resolves/{f=1} f&&/Instrument . prompt file/{exit} f' "$PROTO")
precond "§5.1's slot-rule span was found" test "$(printf '%s' "$span" | wc -l)" -ge 10
declared5=$(printf '%s' "$span" | grep -oE "by one of [a-z]+ rules" | head -1 | sed 's/by one of //;s/ rules//')
# A rule label is a line-initial italic/bold phrase, whatever noun it ends in.
# Measured: the first version matched only (paths|content|slots) — the labels
# that existed when it was written — so a new rule labelled *Delivery* was not
# counted, and a duplicated label made the miscount cancel out to green. An
# extractor scoped to today's members cannot police tomorrow's.
# Not line-anchored: the first label shares a line with the declaration itself,
# so a '^' anchor drops it and reds a correct file. A label is recognised by
# what FOLLOWS it — the arrow or verb that opens its rule — which no other bold
# phrase in the span carries.
labels=$(printf '%s' "$span" | grep -oE '\*\*?[A-Z][a-z]+[a-z -]*\*\*? ?(→|carry|resolve)' | wc -l)
precond "§5.1 declares a rule count" test -n "$declared5"
declare -A W=( [one]=1 [two]=2 [three]=3 [four]=4 [five]=5 [six]=6 [seven]=7 )
[ "${W[$declared5]:-0}" -eq "$labels" ] \
  && ok "§5.1 declares $declared5 slot-resolution rules and labels $labels groups" \
  || bad "§5.1 declares \"$declared5\" slot-resolution rules but labels $labels groups — a group was appended without re-reading the head"

# Non-vacuity: route the exact defect this check was written for — a range one
# short of its list — through the check's OWN comparison.
probe_covers() { [ "$(parse_spec "1-5")" = "1 2 3 4 5 6" ]; }
known_bad "a range one step short of its list is caught" probe_covers

check_done
