#!/usr/bin/env bash
# lib/md_span.sh — the ONE answer to "where does a Markdown section end".
#
# Two doors need it and must not answer it differently. `lib/plan_binds.sh`
# cuts a plan into the extents a charter declares. `lib/gates_claims.sh` checks
# that a cite row's content echo falls inside the extent its `path#heading`
# anchor names — the anchor and the echo were verified as two independent greps
# over the whole file, so a row could point one section off its own evidence and
# pass. A second parser would be a
# second place every rule below has to be corrected, which is the drift shape
# this tree has measured most often.
#
# The rules, each one paid for:
#
#   * A SECTION'S EXTENT IS DECIDED BY ITS NUMBER, NOT ONLY ITS HEADING LEVEL.
#     A real plan writes `### 3.2` and its children
#     `### 3.2.1` `### 3.2.2` `### 3.2.3` all at H3; a level-only rule ended
#     §3.2 at its first child and handed back 22 lines of the 100 a reader means
#     by it — and RESOLVED, so the gate passed. A heading whose number is a
#     strict descendant of the anchor's is INSIDE it, whatever level it is
#     written at.
#
#   * FENCED CODE IS QUOTED MATERIAL, never the document's own structure — the
#     rule `lib/gates.sh`'s `_gates_strip_fences` already states for paths and
#     claim rows, applied here to headings. Read raw, a `# comment` line inside
#     a fence truncates the section above it: the archive sweep of cite rows
#     read 32 out-of-section rows with headings taken raw and 14 with them taken
#     fence-aware, and all 18 of the difference were fenced comments mistaken
#     for headings — a false-red surface, not a defect surface.
#
#   * The fence opener is `_gates_strip_fences`' `^[[:space:]]*(```|~~~)`, not
#     the three-space form this scan carried in its first home. The two were
#     measured against each other over every `*.md` in a plans tree plus this
#     workflow tree — 7,812 files, each read under both rules — and they
#     disagree about the heading/not-heading verdict of ZERO lines. So the tree
#     keeps one fence rule rather than two that happen to agree today.
#
# Callers get an awk PROGRAM TEXT rather than a command, because both doors do
# their own work over the same scan and neither wants a second process or a
# serialised intermediate. Prepend `$MD_SPAN_AWK` to your program and call
# `md_scan(<file>)` from BEGIN; it fills, for 1..nh:
#
#     hline[i]  the heading's line number        hnum[i]   its section number, or ""
#     hlev[i]   its `#` count                    hraw[i]   its text as written
#     htext[i]  its text, whitespace and backticks stripped (normalised equality)
#     total     the file's line count            endof(i)  the last line of i's extent

MD_SPAN_AWK=$(cat <<'MD_SPAN_AWK_TEXT'
function norm(s) { gsub(/[`[:space:]]/, "", s); return s }
function level(l) { match(l, /^#+/); return RLENGTH }
function isdesc(a, b) {  # a is a strict number-descendant of b
  return (b != "" && a != "" && substr(a, 1, length(b) + 1) == b ".")
}
function md_scan(f,   line, nl, t, n, fence) {
  nh = 0; nl = 0; fence = 0
  while ((getline line < f) > 0) {
    nl++
    if (line ~ /^[[:space:]]*(```|~~~)/) { fence = !fence; continue }
    if (fence) continue
    if (line ~ /^#+[[:space:]]/) {
      nh++
      hline[nh] = nl; hlev[nh] = level(line)
      t = line; sub(/^#+[[:space:]]+/, "", t)
      hraw[nh] = t
      htext[nh] = norm(t)
      hnum[nh] = ""
      if (match(t, /^[0-9]+(\.[0-9]+)*[.、]?([[:space:]]|$)/)) {
        n = substr(t, 1, RLENGTH); gsub(/[.、[:space:]]+$/, "", n); hnum[nh] = n
      }
    }
  }
  close(f)
  total = nl
}
function endof(i,   j) {
  for (j = i + 1; j <= nh; j++) {
    if (isdesc(hnum[j], hnum[i])) continue
    if (hlev[j] <= hlev[i]) return hline[j] - 1
    if (hnum[i] != "" && hnum[j] != "") return hline[j] - 1
  }
  return total
}
MD_SPAN_AWK_TEXT
)

# The extent of every heading a `path#heading` anchor's fragment resolves to,
# one `<start> <end>` pair per line, in file order. EMPTY output means the
# fragment names no heading — the caller's "moved target" case, kept distinct
# from "resolved but the echo is elsewhere".
#
# The match is the claims gate's own: case-folded, the fragment as a LITERAL
# substring of the heading's text, and at most six `#`s — a seventh is not a
# heading, and the gate's own regex already declined it. A fragment matching
# more than one heading yields more than one span and the caller passes on ANY
# of them: that is today's behaviour preserved exactly, so an ambiguous anchor
# cannot become a new refusal.
#
# The fragment travels in the ENVIRONMENT, not through `awk -v`: -v runs escape
# processing over its value, so an anchor or echo containing a backslash reaches
# the program as something else (`x\ty` matches nothing; via ENVIRON it matches).
# The gate this serves compares echoes with `grep -F`, a literal match, and a
# scope check that quietly disagrees with it would be worse than none.
md_heading_span() { # file fragment -> "<start> <end>" per matching heading
  [ -f "$1" ] || return 1
  MD_SPAN_FRAG=$2 awk -v srcfile="$1" "$MD_SPAN_AWK"'
    BEGIN {
      md_scan(srcfile)
      want = tolower(ENVIRON["MD_SPAN_FRAG"])
      for (i = 1; i <= nh; i++)
        if (hlev[i] <= 6 && index(tolower(hraw[i]), want) > 0)
          print hline[i] " " endof(i)
    }
  ' < /dev/null
}

# Every line of `file` carrying `text` as a literal substring — the echo arm's
# `grep -nF`, without the pipe, and through ENVIRON for the reason above.
md_literal_lines() { # file text -> line numbers, one per line
  [ -f "$1" ] || return 1
  MD_SPAN_TEXT=$2 awk 'index($0, ENVIRON["MD_SPAN_TEXT"]) { print NR }' "$1"
}

# rc 0 when any of `lines` (one per line) falls inside any of `spans`
# (`<start> <end>` per line). Both are small; both are already in hand.
md_span_covers() { # spans lines
  awk -v spans="$1" -v lines="$2" '
    BEGIN {
      ns = split(spans, s, "\n"); nl = split(lines, l, "\n")
      for (i = 1; i <= ns; i++) {
        split(s[i], p, " ")
        for (j = 1; j <= nl; j++)
          if (l[j] != "" && l[j] + 0 >= p[1] + 0 && l[j] + 0 <= p[2] + 0) exit 0
      }
      exit 1
    }' < /dev/null
}
