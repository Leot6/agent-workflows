#!/usr/bin/env bash
# 99-anchor-writes — a non-retro commit may not raise any family's anchor count.
#
# WHY IT EXISTS. A§11 used to reserve the promoted tables to retro step 1
# outright, and an owner ruling (WQ-4 甲) opened one field of them to the
# maintainer: a family row's landing/status field, written in the landing
# commit, so the log stops describing a tree that has moved. That grant's own
# counter-argument is that the new boundary is PROSE — "only the status field
# moved" is not decidable by a script, and nothing mechanical stops a
# maintainer editing further.
#
# So the bar is not placed on the boundary. It is placed on the HARM the
# single-writer rule actually names: protocol §4.6.4, "one writer into the
# log, so one anchor per event". Anchor counts feed `ANCHOR_MIN`, A§1's
# promotion threshold — two parties each recording the same event inflates the
# count and corrupts a promotion decision. That is checkable, and it is the
# thing worth checking.
#
# HONEST BOUNDARY, three parts. (1) This catches an anchor count that GREW
# outside a retro ingest; it says nothing about whether the landing text a
# maintainer wrote is true, nor whether an anchor that grew inside a retro
# ingest was earned. (2) The rule's floor is the commit that last touched THIS
# FILE, so editing the check moves the floor forward and forgives the history
# behind it — deliberate, because a hardcoded SHA cannot be written by the
# commit that introduces it, and honest, because the check exists to catch the
# accident, not the fraud A§14's last row concedes tree-wide. (3) Counts are
# read from `open/OBS-<n>.md`, never from INDEX.md's table: claims.md rule 4
# ("a state table is not a parseable format") measured three failures splitting
# rows whose cells carry `|`, and the family files carry the same number in a
# field with no such hazard.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/fixtures/lib.sh"

RETRO_MARK='Retro-ingest:'   # protocol §4.11.7 — a retro ingest declares itself

# The detector, taking both count sets as arguments so the known-bad below runs
# this exact code path over a fabricated pair.
increases() { # <before> <after> -> prints "id before->after"; rc 1 if none
  local id a b
  while IFS=$'\t' read -r id a; do
    [ -n "$id" ] || continue
    b=$(printf '%s\n' "$1" | awk -F'\t' -v k="$id" '$1==k{print $2}')
    [ -n "$b" ] || b=0
    [ "$a" -gt "$b" ] && printf '%s %s->%s\n' "$id" "$b" "$a"
  done <<< "$2" | command grep .
}
no_increase() { ! increases "$1" "$2" >/dev/null 2>&1; }

# --- the parser, over the working tree (non-vacuity for the machinery) ------
counts_in_dir() { # <dir> -> "OBS-9<TAB>9"
  local f n
  for f in "$1"/OBS-*.md; do
    [ -e "$f" ] || continue
    n=$(sed -n 's/^- \*\*anchors\*\*:[[:space:]]*\([0-9][0-9]*\).*/\1/p' "$f" | head -1)
    [ -n "$n" ] && printf '%s\t%s\n' "$(basename "$f" .md)" "$n"
  done
}
# The parser is proven on a fabricated family file, so a fresh log with no
# families does not leave it unexercised; the live directory is then read for
# whatever it holds.
fx=$(sc_tmpdir)
printf '# OBS-7 — x\n\n- **anchors**: 3 (r1–r3)\n' > "$fx/OBS-7.md"
precond "family anchor counts parse from a fabricated family file" \
  test "$(counts_in_dir "$fx")" = "$(printf 'OBS-7\t3')"
here=$(counts_in_dir "$WF_ROOT/iteration-log/open")
[ -n "$here" ] || note "fresh state file: open/ holds no family files yet"

# --- the commit sweep -------------------------------------------------------
if git -C "$WF_ROOT" rev-parse --git-dir >/dev/null 2>&1; then
  TOP=$(git -C "$WF_ROOT" rev-parse --show-toplevel)
  REL=${WF_ROOT#"$TOP"/}
  SELF="$REL/self-check/checks/$(basename "${BASH_SOURCE[0]}")"
  floor=$(git -C "$TOP" log -1 --format=%H -- "$SELF" 2>/dev/null)
  [ -n "$floor" ] || floor=$(git -C "$TOP" rev-parse HEAD)

  counts_at() { # <rev> -> "OBS-9<TAB>9"
    local rev=$1 f n
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      n=$(git -C "$TOP" show "$rev:$f" 2>/dev/null \
            | sed -n 's/^- \*\*anchors\*\*:[[:space:]]*\([0-9][0-9]*\).*/\1/p' | head -1)
      [ -n "$n" ] && printf '%s\t%s\n' "$(basename "$f" .md)" "$n"
    done < <(git -C "$TOP" ls-tree -r --name-only "$rev" -- "$REL/iteration-log/open" 2>/dev/null)
  }

  n=0
  while IFS= read -r c; do
    [ -n "$c" ] || continue
    n=$((n + 1))
    git -C "$TOP" log -1 --format=%B "$c" | command grep -q "$RETRO_MARK" && continue
    hits=$(increases "$(counts_at "$c^")" "$(counts_at "$c")" | tr '\n' ' ')
    [ -z "$hits" ] || bad "commit $(git -C "$TOP" log -1 --format=%h "$c") is not a retro ingest and raises an anchor count: ${hits}— anchors are retro step 1's (A§11; the harm is protocol §4.6.4's one-anchor-per-event)"
  done < <(git -C "$TOP" log --format=%H "$floor..HEAD" -- "$REL/iteration-log/open" 2>/dev/null)

  # An empty range is the normal state right after the rule lands, and is not
  # a vacuous pass: the parser precond above already proved the machinery runs.
  [ "$_FAIL" -eq 0 ] && ok "$n log-touching commit(s) since the rule's floor, none raising an anchor count outside a retro ingest"
else
  ok "not a git checkout — the commit sweep is skipped (the parser above still ran)"
fi

known_bad "an anchor count that grew outside a retro ingest is caught" \
  no_increase "$(printf 'OBS-9\t9\n')" "$(printf 'OBS-9\t10\n')"

check_done
