#!/usr/bin/env bash
# lib/plan_binds.sh — the charter's DECLARED plan binding, and the ONE
# resolution of it that both doors call.
#
# Why a declared field. The per-slice plan excerpt keyed only on `# W-<id>:`
# item headings — a planning-side convention 3 of the 10 plans on disk use. On
# the rest the composer gave up whole and every spec and precheck prompt fell
# back to *read the plan in full*, which is the cost the excerpt exists to
# remove. What those charters carry instead is a `**plan binding**` PROSE
# paragraph: a convention no template, card, gate or script in this tree ever
# defined, which is why it grew three mutually unreadable dialects across seven
# charters and why two charters carry no binding at all. A key swept over the
# prose over-collects — the slice sections hold far more section tokens than
# the binding paragraphs do, and some point at workflow docs rather than the
# plan — and it cannot follow a paragraph that defers to another slice in
# words, so it drops bound material silently. This field replaces the
# archaeology: the author declares the binding, the emit gate refuses a token
# that resolves nowhere, and the composer cuts on exactly what was declared.
#
# ONE derivation called by each door (`maintenance.md` §2 step 2): the composer
# builds the excerpt from these spans and `gates_plan_binds` reds on this same
# function's UNRESOLVED lines. A second parser would be a second place every
# correction has to reach — the drift shape this tree has measured most often.
#
# THE GRAMMAR, stated once here and taught by `runtime-docs/templates/prompts/
# split.warm.md` (the card carries the sentence that changes behaviour and
# points there; it does not restate the form):
#
#     plan-binds:
#     - §2
#     - §4 切片 A（commit 1，先行独立）：route brief 点检查上提
#
# The heading text is quoted IN FULL. An abbreviated one resolves nowhere —
# matching is normalised equality, not substring — and the first version of the
# worked example in both this comment and the split prompt elided a path with
# `...` two lines above the instruction to quote it as found. It was refused at
# emit when an independent reader ran it.
#
# `plan-binds:` alone on a line inside the slice's `## slice NN` section; each
# following `- §…` line is one anchor; the list ends at the first line that is
# not one. `§N` binds that whole numbered section. `§N <heading text>` binds ONE
# subsection of it, matched on heading text with whitespace and backticks
# ignored — measured necessary: of the twelve subsection headings one charter
# quotes from its plan, five match byte-for-byte and twelve match normalised.
# No in-line separator, deliberately: both `·` and `§` occur inside real plan
# headings on disk, so any delimiter would collide with the text it delimits.
# One anchor per line cannot.

# The field's anchors for one slice, one per line, `§` already stripped.
# Prints nothing when the section carries no `plan-binds:` label — the signal to
# fall through to the W-<id> arm, never an error. Two sentinels are printed
# INSTEAD of anchors, because silence and a broken field must not look alike:
#   !EMPTY      the label is there and yielded no anchor at all
#   !DUPLICATE  a second label opens a second list in the same section
# Both were live defects: a label written `**plan-binds:**` (the shape of the
# PROSE convention this field replaces, so the likeliest transcription), or with
# a blank line before its first item, parsed to nothing — and nothing is exactly
# what a section with no field parses to, so both doors fell through silently to
# the behaviour this mechanism exists to end.
_PLAN_BINDS_LIB_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
. "$_PLAN_BINDS_LIB_DIR/md_span.sh"   # the shared Markdown extent rule (md_scan/endof)

plan_binds_tokens() { # charters.md slice
  local charter=$1 slice=$2
  [ -f "$charter" ] || return 0
  awk -v s="$slice" '
    $0 ~ ("^## slice " s "( |$)") { insec = 1; next }
    insec && /^## / { exit }
    !insec { next }
    # A fenced block inside the section is QUOTED material: a charter that shows
    # the reader an example must not thereby declare it.
    /^[ \t]?[ \t]?[ \t]?```/ { fence = !fence; next }
    fence { next }
    # <=3 leading spaces: more is an indented code block in markdown, and the
    # split prompt renders its own worked example as one.
    /^[ \t]?[ \t]?[ \t]?\*?\*?plan-binds:\*?\*?[[:space:]]*$/ {
      if (seen) { dup = 1 }
      seen = 1; infield = 1; n = 0; next
    }
    infield {
      if ($0 ~ /^[[:space:]]*$/) next                      # blank lines do not end the list
      if ($0 ~ /^[ \t]?[ \t]?[ \t]?[-*][[:space:]]*§/) {
        line = $0
        sub(/^[ \t]?[ \t]?[ \t]?[-*][[:space:]]*§[[:space:]]*/, "", line)
        sub(/[[:space:]]+$/, "", line)
        if (line != "") { n++; item[n] = line }
        next
      }
      infield = 0
    }
    END {
      if (!seen) exit
      if (dup) { print "!DUPLICATE"; exit }
      if (n == 0) { print "!EMPTY"; exit }
      for (i = 1; i <= n; i++) print item[i]
    }
  ' "$charter"
}

# Resolve each anchor against the plan. One line per anchor, in the order given:
#   RESOLVED <start-line> <end-line> <anchor>
#   UNRESOLVED <anchor>
# plus, for an anchor that is not top-level, one CONTEXT line per enclosing
# numbered ancestor — that heading and its own preamble, down to its first
# child:
#   CONTEXT <start-line> <end-line> <ancestor number>
# Without them the excerpt carries a `###` under no `##` and the reader cannot
# see which section the subsection belongs to. A SEPARATE verb on purpose: the
# composer adds CONTEXT to the keep-set, the anchor COUNT it prints stays the
# count of what the charter actually declared, and the gate reads neither.
# Both doors read this function and nothing else: the composer keeps the spans,
# the gate reds on any UNRESOLVED. An anchor list that is empty prints nothing,
# and each caller states its own floor for that — never this function's guess.
#
# The extent rule itself — number-descendant containment, fence-aware headings —
# is `lib/md_span.sh`, shared with the claims gate. It is not restated here: it
# was moved out the day a second door needed it, and a rule with two homes is a
# rule with two versions.
plan_binds_spans() { # plan.md < anchors-on-stdin
  local plan=$1
  [ -f "$plan" ] || return 0
  awk -v srcfile="$plan" "$MD_SPAN_AWK"'
    BEGIN { md_scan(srcfile) }
    # heading + preamble: down to the first heading nested inside it
    function preof(i,   j) {
      for (j = i + 1; j <= nh; j++) if (hline[j] > hline[i]) {
        if (hline[j] - 1 < endof(i)) return hline[j] - 1
        break
      }
      return endof(i)
    }
    function byname(x,   j) { for (j = 1; j <= nh; j++) if (hnum[j] == x) return j; return 0 }
    # every strict-prefix ancestor of x that exists as a heading, outermost first
    function ctx(x,   k, parts, i, acc, a) {
      k = split(x, parts, ".")
      for (i = 1; i < k; i++) {
        acc = (i == 1 ? parts[1] : acc "." parts[i])
        a = byname(acc)
        if (a > 0) print "CONTEXT " hline[a] " " preof(a) " " acc
      }
    }
    {
      anchor = $0
      if (anchor ~ /^!/) { print "UNRESOLVED " anchor; next }
      if (match(anchor, /^[0-9]+(\.[0-9]+)*/)) {
        num = substr(anchor, 1, RLENGTH)
        rest = substr(anchor, RLENGTH + 1)
        sub(/^[[:space:]]*[.、]?[[:space:]]*/, "", rest)
      } else { print "UNRESOLVED " anchor; next }
      parent = byname(num)
      if (parent == 0) { print "UNRESOLVED " anchor; next }
      if (rest == "") {
        ctx(num)
        print "RESOLVED " hline[parent] " " endof(parent) " " anchor
        next
      }
      want = norm(rest); pend = endof(parent); hit = 0
      for (i = parent + 1; i <= nh && hline[i] <= pend; i++) {
        if (hlev[i] > hlev[parent] && htext[i] == want) { hit = i; break }
      }
      if (hit == 0) { print "UNRESOLVED " anchor; next }
      e = endof(hit); if (e > pend) e = pend
      ctx(num)
      print "CONTEXT " hline[parent] " " preof(parent) " " num
      print "RESOLVED " hline[hit] " " e " " anchor
    }
  '
}

# The plan's HEAD: everything above its first NUMBERED heading — the title block
# and whatever preamble sits above section 1. Here rather than in the composer
# because it has to obey the same two rules the resolver does, and did not: it
# read `^## ` literally, so a plan whose sections are H1 emitted the WHOLE plan
# as head and then the declared spans again after it, and it counted a `# ` line
# inside a fenced block as a heading. Both are latent on the ten plans on disk
# (every one puts its first numbered heading at the first `## `), which is
# exactly why they belong in the shared derivation rather than in a caller.
plan_binds_head() { # plan.md
  local plan=$1
  [ -f "$plan" ] || return 0
  awk '
    /^[ \t]?[ \t]?[ \t]?```/ { fence = !fence; print; next }
    fence { print; next }
    /^#+[[:space:]]/ {
      t = $0; sub(/^#+[[:space:]]+/, "", t)
      if (t ~ /^[0-9]+(\.[0-9]+)*[.、]?([[:space:]]|$)/) exit
    }
    { print }
  ' "$plan"
}
