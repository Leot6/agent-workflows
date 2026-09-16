#!/usr/bin/env bash
# 25-xref — section cross-references resolve. The formal region's docs point
# at each other by "`file.md` §N" / "§N of `file.md`" / bare-name "file §N" /
# same-file "(§N)". A stale section number is the worst AI-reader confuser:
# the pointer LOOKS authoritative and lands on the wrong topic. Numbered
# references are machine-checkable (integer part of §N must exist as a
# `## N.`-level heading in the target); name anchors (§takeover) are not
# covered here (they fail loudly as a plain grep miss when followed).
# HONEST BOUNDARY: this catches DANGLING numbers (a section was inserted,
# removed or renumbered — every reference to the shifted range reds at once).
# A §N that exists but points at the wrong TOPIC is semantic staleness and
# stays the review sweep's job — no mechanical check can read intent.
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/fixtures/lib.sh"

# scan set = the formal markdown region
DOCS=$(find "$WF_ROOT/design" "$WF_ROOT/runtime-docs" "$WF_ROOT/iteration-log" -name '*.md'; \
       echo "$WF_ROOT/README.md"; echo "$WF_ROOT/self-check/validation-debt.md")
precond "formal markdown set found" test "$(printf '%s\n' "$DOCS" | command grep -c .)" -ge 25

# bare doc names that may appear without .md (design shorthand)
resolve_doc() { # name-or-path -> absolute path (empty if unknown)
  local b=${1##*/}; b=${b%.md}
  case "$b" in
    architecture|backend-seam|config-and-adapters|migration-and-acceptance|review-and-slices|state-and-liveness)
      echo "$WF_ROOT/design/$b.md" ;;
    protocol|operations|review-standards)
      echo "$WF_ROOT/runtime-docs/$b.md" ;;
    README) echo "$WF_ROOT/README.md" ;;
    *) echo "" ;;
  esac
}

section_exists() { # file N -> rc
  command grep -qE "^## $2[. ]" "$1"
}

violations=""
checked=0
for doc in $DOCS; do
  [ -f "$doc" ] || continue
  # one reference per line: "<lineno>\t<target-name>\t<N>"
  refs=$(awk '
    {
      line=$0; n=NR
      # cross-file: name(.md)? [§]N   and   §N of name(.md)?
      while (match(line, /[a-zA-Z-]+(\.md)?[` ]+§[0-9]+/)) {
        s=substr(line, RSTART, RLENGTH)
        gsub(/[` ]+§/, " ", s); split(s, a, " ")
        print n "\t" a[1] "\t" a[2]
        line=substr(line, RSTART+RLENGTH)
      }
      line=$0
      while (match(line, /§[0-9]+ of `[a-zA-Z.-]+`/)) {
        s=substr(line, RSTART, RLENGTH)
        gsub(/§/, "", s); gsub(/ of `/, " ", s); gsub(/`/, "", s); split(s, a, " ")
        print n "\t" a[2] "\t" a[1]
        line=substr(line, RSTART+RLENGTH)
      }
      # same-file: (§N) — only the parenthesised form, to avoid re-matching
      # the cross-file hits consumed above
      line=$0
      while (match(line, /\(§[0-9]+\)/)) {
        s=substr(line, RSTART, RLENGTH)
        gsub(/[^0-9]/, "", s)   # byte-safe: § is multi-byte under LC_ALL=C
        print n "\tSELF\t" s
        line=substr(line, RSTART+RLENGTH)
      }
    }' "$doc")
  while IFS=$'\t' read -r ln name num; do
    [ -n "$num" ] || continue
    if [ "$name" = "SELF" ]; then tgt="$doc"; else tgt=$(resolve_doc "$name"); fi
    [ -n "$tgt" ] && [ -f "$tgt" ] || continue   # unknown name: not ours to judge
    checked=$((checked + 1))
    section_exists "$tgt" "$num" \
      || violations="$violations$(basename "$doc"):$ln -> $(basename "$tgt") §$num (no '## $num.' heading)"$'\n'
  done <<< "$refs"
done

precond "the sweep actually checked references" test "$checked" -ge 40
if [ -z "$violations" ]; then
  ok "all $checked numbered section references resolve"
else
  bad "stale section references:"$'\n'"$violations"
fi

# ---------------------------------------------------------------------------
# Table cell alignment. GFM delimits cells on an UNESCAPED `|` and says so for
# inline spans too, so a row that inlines `a|b` in a code span silently gains a
# cell — and every cell after it renders one column right: a landing commit
# under "anchors", an open/ pointer under "landing". Nothing loud happens. The
# source reads fine, and every whole-line grep (97-iterlog's pointer sweep
# included) still finds the text it looks for.
# This tree has already paid for the same confusion once, on the CLAIMS table
# (60-gates carries the split-row fixture) — that lesson
# reached the gate that reads authors' tables and not the tables these docs are
# written in.
# HONEST BOUNDARY: alignment only — a row with the right cell COUNT and the
# wrong content is a reader's problem, not this arm's. Fenced blocks are
# skipped, because the document most likely to contain a deliberately broken
# table row is the one explaining this rule, and a lint that reds on its own
# documentation is a lint people switch off. Only fences at column 0 (``` or
# ~~~) are tracked; an indented fence would still be read as prose.
table_cell_defects() { # <file> -> prints one line per shifted row (empty = clean; awk's rc says nothing)
  awk '
    function cells(s,   t) { t=s; gsub(/\\\|/, "E", t); return split(t, _a, "|") - 2 }
    /^(```|~~~)/ { if (inblk) { flush(); inblk=0 }   # a fence ends any table
                   fence = !fence; next }
    fence { next }                                   # inside a fence nothing is a row
    /^\|/ {
      if (!inblk) { inblk=1; want=-1; nr=0; delete rows; delete rowln }
      if (want < 0 && $0 ~ /^\|[ :|-]+\|[ :|-]*$/) want=cells($0)
      nr++; rowln[nr]=NR; rows[nr]=$0; next
    }
    { if (inblk) { flush() ; inblk=0 } }
    END { if (inblk) flush() }
    function flush(   i) {
      if (want >= 0)                # no delimiter row: not a table
        for (i = 1; i <= nr; i++)   # index order, so a red reads top-to-bottom
          if (cells(rows[i]) != want)
            printf "%s:%d has %d cells, the table declares %d — unescaped `|` in a cell?\n", FILENAME, rowln[i], cells(rows[i]), want
      nr=0; delete rows; delete rowln
    }
  ' "$1"
}

t_out=""
for doc in $DOCS; do
  [ -f "$doc" ] || continue
  d_out=$(table_cell_defects "$doc") || true
  [ -n "$d_out" ] && t_out="$t_out$d_out"$'\n'
done
# Floor the sweep's own input: the detector's fixtures prove the awk can
# fire, but nothing else proves the TREE-side walk saw any rows at all — a
# formal region whose tables stopped matching `/^\|/` would sweep nothing
# and read as clean.
t_rows=0
for doc in $DOCS; do
  [ -f "$doc" ] || continue
  t_rows=$(( t_rows + $(command grep -c '^|' "$doc" 2>/dev/null || true) ))
done
precond "the table sweep saw N>=200 pipe-rows across the formal docs (saw $t_rows)" \
  test "$t_rows" -ge 200
if [ -z "$t_out" ]; then
  ok "every markdown table row in the formal region carries its table's cell count"
else
  bad "table rows whose cells are shifted by an unescaped pipe:"$'\n'"$(printf '%s' "$t_out" | sed "s|^$WF_ROOT/|    |")"
fi

# known-bad: the shape this arm exists for — a pipe inside a code span.
d=$(sc_tmpdir)/tbl.md
printf '| id | note |\n|---|---|\n| a | plain |\n| b | `x|y` |\n' > "$d"
out=$(table_cell_defects "$d")
printf '%s' "$out" | command grep -q ':4 has 3 cells' \
  && ok "known-bad: an unescaped pipe inside a code span is caught (row 4 reads as 3 cells)" \
  || bad "known-bad NOT caught — the arm is blind to the shape it exists for (out: $out)"
# a fenced block is not a table: the doc most likely to SHOW a broken row is the
# one explaining this rule, and it must not red the suite that ships it
printf '```\n| a | b | c |\n|---|---|\n| shown as an example |\n```\n\n| id | note |\n|---|---|\n| ok | fine |\n' > "$d"
[ -z "$(table_cell_defects "$d")" ] \
  && ok "rows inside a fenced block are prose, not table rows (the arm does not red its own documentation)" \
  || bad "a fenced example was read as a table: $(table_cell_defects "$d")"
# ...and a real broken table AFTER a fence is still caught (the fence must not blind the rest)
printf '```\n| x | y |\n```\n\n| id | note |\n|---|---|\n| b | `x|y` |\n' > "$d"
printf '%s' "$(table_cell_defects "$d")" | command grep -q ':7 has 3 cells' \
  && ok "and a real shifted row after a fence is still caught (row 7)" \
  || bad "the fence blinded the arm to the table after it: $(table_cell_defects "$d")"

# and the escaped form must PASS, or the arm would forbid the fix it asks for
printf '| id | note |\n|---|---|\n| b | `x\\|y` |\n' > "$d"
[ -z "$(table_cell_defects "$d")" ] \
  && ok "an escaped \\| inside a cell is accepted (the arm asks for a fix it does not then refuse)" \
  || bad "escaped pipe rejected — the arm would forbid its own remedy"

# non-vacuity: a fabricated stale reference must be caught
tmp=$(sc_tmpdir)/fake.md
printf 'see `protocol.md` §99 for details\n' > "$tmp"
fake=$(awk '{ if (match($0, /[a-zA-Z-]+(\.md)?[` ]+§[0-9]+/)) print "hit" }' "$tmp")
# The fixture line must have been EXTRACTED before the miss can mean anything:
# this awk is a re-typed copy of the main extractor's pattern, and a copy that
# drifted while real refs still match would short-circuit the chain below into
# its ok branch — "caught" without anything having been looked at.
precond "the known-bad fixture line was extracted by the reference pattern" test -n "$fake"
[ -n "$fake" ] && section_exists "$WF_ROOT/runtime-docs/protocol.md" 99 \
  && bad "validator blind: §99 read as existing" || ok "a fabricated §99 reference is caught (known-bad fires)"

check_done
