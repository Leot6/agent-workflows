#!/usr/bin/env bash
# lib/report_routing.sh — section 4 of derive_report.sh, the routing outcome:
# the lane verdict from its two homes, the cost split by stages.tsv's scope
# column over derive_cost.sh's one pairing, and the review-driven commit units
# with their file lists. The one section of the report that reads git and is a
# SNAPSHOT rather than a derivation (derive_report.sh's boundary (d)).
#
# Split out of derive_report.sh at cap.source_file=800 on the ferry-halves
# precedent (architecture §12): a concern-coherent split under an honest header.
# It is sourced by derive_report.sh and by nothing else, and it reads that
# file's globals — WS, TOPIC_DIR, DR_DIR, WF_ROOT — and its _dr_fault. The
# check that pins every branch of this section is 99-routing, which copies this
# file beside derive_report.sh into its fake trees.
report_routing_outcome() {
# ---- 4. routing outcome ------------------------------------------------------
# The verdict and the outcome side by side, which is the whole of it: a routing
# rule whose predictions are never set against results has thresholds made of
# belief. Nothing here scores anything — every field prints, and the judging is
# the harvest's and the owner's. See boundary (d) above for why this is the one
# section that is a snapshot rather than a derivation.
# BEFORE YOU REMOVE OR RENAME THIS BLOCK, OR SECTION 3 ABOVE IT: three files at
# the repository root cite them by name — the routing rule, its calibration
# ledger and one deferred slot. What they name is this script, `derive_cost.sh`,
# and the two section headings a ledger row is copied from: "routing outcome"
# for the cost and "reviewer coverage" for the review. No count is given, and
# that is deliberate — the first version of this sentence carried one, an edit
# at the root added a citation, and the number was wrong the same day. Nothing
# checks any of it: the root has no harness, and this tree may not reference the
# root to build one (the standalone promise runs one way), so a grep cannot live
# here either. A rename rots them silently and the next reader of the rule meets
# a command or a heading that does not exist. This tree owes them nothing at run
# time and can be copied out without them; what it owes is this sentence, at the
# point where someone would break them.
echo "## routing outcome — the lane this topic was routed into, beside what the run cost"

# -- the verdict, from BOTH homes, each labelled, neither preferred ------------
# `design/config-and-adapters.md` §3: the plan preamble and `project.kv` carry
# the same fact with NO precedence between them, so this prints whichever exist
# and NAMES a disagreement rather than resolving one. Verbatim: the vocabulary
# of lanes is defined outside this tree, and parsing it here would make this
# driver the owner of a rule it cannot keep current.
# TRAILING WHITESPACE IS NOT PART OF A VERDICT, and this is not a nicety: two
# trailing spaces is Markdown's own line-break syntax, so a plan preamble is one
# of the likeliest places on disk to carry them. Untrimmed, two IDENTICAL
# verdicts printed as a DISAGREEMENT — a false conflict, which is worse than the
# silent pick this block refuses to make, because it sends the close-out author
# to record something that is not there. Both homes are trimmed on the way in.
# PRESENCE travels on the exit status, the value on stdout — the same two
# channels `project_get` uses for the other home, so the two read alike in the
# code as well as in the design. That distinction is load-bearing: absent-is-not-
# zero applies to a declaration too, and an author who wrote the key and left it
# blank has not done what an author who never wrote it did. Reporting those alike
# would hide a half-done copy behind a sentence about an absent one.
# NOTE FOR EDITORS, and it applies to BOTH awk programs in this file: each is a
# single-quoted shell string, so a comment inside one may contain no apostrophe.
# `derive_cost.sh` carries the same warning because it paid for it — a draft
# comment wrote a possessive, closed the string, and broke the file. Written here
# rather than assumed transferable: the hazard belongs to the quoting, not to the
# other script.
_dr_route_in_preamble() { # plan file -> the verdict on stdout; rc 1 if no route line
  # A partial CommonMark block-structure reader, and the discipline is that
  # each block-level fact is stated ONCE and COMPLETELY: indent is measured
  # in columns (a tab always reaches a stop of four, so "contains a tab or
  # ≥4 spaces" IS the code test, at both levels below), a blockquote marker
  # consumes itself and at most ONE following space, a fence is 3+ of one
  # marker character whose closer uses the SAME character, is at least as
  # long, carries nothing but spaces and sits at the SAME quote depth —
  # while the fence itself lives and dies inside the quote level that
  # opened it — a break is 3+ of one character with spaces allowed between
  # and around, and the preamble ends at the first heading in any of its
  # three forms. CRLF endings are normalised on entry. The first version of
  # this reader was a pile of strips and gates; the second restated it but
  # only for the shapes probes had tried; the third pass asked what each
  # rule did not SAY; the fourth asked what the rules did not say about
  # EACH OTHER, and found the fence-quote binding.
  # WHAT "PARTIAL" MEANS, so the next editor inherits a map rather than a
  # surprise: modelled — paragraph, indented code, fenced code, blockquote
  # markers, ATX and setext headings, thematic breaks, CRLF endings.
  # Unmodelled — lists, tables, HTML blocks, setext across quote levels
  # (a divider directly under a quoted paragraph is an underline here, so
  # the preamble ends early — the false-`none` direction), and ATX below
  # `##` (an h3 does not end the preamble; the documented boundary, and
  # every plan this workflow has run opens its sections with `##`).
  # Lists and tables fail toward the preamble ending EARLY (a `none` that
  # points upstream, never a fabricated verdict, because a route: inside
  # either carries a prefix this reader cannot match); an HTML block can
  # adopt a route: line inside it, the one unmodelled adoption path — no
  # plan on disk carries HTML in its preamble, and the failure this block
  # exists to prevent (a grammar sample adopted as a verdict) needs code
  # or fence, both modelled.
  # The shapes below are pinned in 99-routing, at their boundaries.
  awk '
    { s = $0
      # a CRLF plan defeats every dollar-anchored test below (no underline,
      # no divider ever matches over the carriage return), which fails toward
      # the ADOPTION direction — stripped once, here, so every test is
      # line-ending-agnostic
      sub(/\r$/, "", s)
      # raw indent: 0-3 columns admit the line; 4+ spaces or a leading tab is
      # an indented code block — skipped whole, marker and all, because the
      # marker inside code is literal text
      n = 0; while (substr(s, 1, 1) == " ") { n++; s = substr(s, 2) }
      if (n >= 4 || substr(s, 1, 1) == "\t") next
      # blockquote markers, each consuming itself plus at most one space
      # (CommonMark); a tab after a marker is content, never the space —
      # which is what leaves it for the indent rule to judge as code. q
      # remembers how deep this line sat: a fence lives and dies inside
      # the quote level that opened it.
      q = 0
      while (substr(s, 1, 1) == ">") {
        q++; s = substr(s, 2)
        if (substr(s, 1, 1) == " ") s = substr(s, 2) }
      # content indent, the SAME column rule once more: a tab after the
      # markers always lands on a stop of four, so it is code by this test
      # too, whatever spaces preceded it
      n = 0; while (substr(s, 1, 1) == " ") { n++; s = substr(s, 2) }
      if (n >= 4 || substr(s, 1, 1) == "\t") next
      # structural tests read a copy without trailing whitespace: trailing
      # spaces are legal on an underline and on a break line, and the verdict
      # value is trimmed by the caller for BOTH homes — this copy carries
      # structure, not value
      t = s; sub(/[ \t]+$/, "", t)
      # fences: 3+ of one marker character, and the block lives and dies
      # inside the quote level that opened it. The closer must use the SAME
      # character, be at least as long, carry nothing but spaces after it,
      # and sit at the SAME quote depth — an info string OPENS a fence and
      # never closes one, and a quoted fence line is content of a top-level
      # fence, never its closer. And code cannot be lazily continued, so a
      # line shallower than the quote level that opened the fence means the
      # quote ended and the fence ended with it, unclosed — the line is then
      # processed at its own level, where it may itself open a fresh fence.
      # A fence also interrupts a paragraph, so it clears the setext memory.
      if (fence && q < fq) { fence = 0; fm = ""; fl = 0; fq = 0 }
      if (substr(t, 1, 3) == "```" || substr(t, 1, 3) == "~~~") {
        m = substr(t, 1, 1); L = 0; r = t
        while (substr(r, 1, 1) == m) { L++; r = substr(r, 2) }
        if (fence) {
          if (q != fq) next
          if (m == fm && L >= fl && r ~ /^ *$/) { fence = 0; fm = ""; fl = 0; fq = 0 } }
        else { fence = 1; fm = m; fl = L; fq = q }
        para = 0; next }
      if (fence) next
      # the preamble ends at the first heading — ATX at any legal indent
      # (raw or quoted, the strips above normalised both), or a setext
      # underline: dashes or equals with no internal spaces, directly under
      # a paragraph line. A thematic break is never paragraph content: 3+ of
      # one character — dash, star or underscore — with spaces allowed
      # between and around, so a spaced break arms no memory and a padded
      # underline still underlines. A dash or equals line that underlines
      # nothing falls through to the paragraph update like any text, because
      # that is what the grammar says it then is.
      if (t ~ /^## /) exit
      if (para && (t ~ /^-+$/ || t ~ /^=+$/)) exit
      b = t; gsub(/[ \t]/, "", b)
      if (length(b) >= 3 && (b ~ /^-+$/ || b ~ /^\*+$/ || b ~ /^_+$/)) { para = 0; next }
      if (t ~ /^route:/) { v = t; sub(/^route:[ \t]*/, "", v)
                           print v; found = 1; exit }
      para = (t != "") }
    # rc 1 means SEARCHED AND NOT FOUND. Any other non-zero is awk failing to
    # read the file at all, which the caller reports as a fault rather than as
    # an absence — the third place in this section where those two had to be
    # told apart, after the ledger and the empty declaration.
    END { exit(found ? 0 : 1) }' "$1"
}
# ONE trim, applied to both homes at the same point. Trailing whitespace is not
# part of a verdict — two trailing spaces are a Markdown line break — and the
# rule was briefly implemented twice, once in the awk above and once here, which
# is one rule in two languages waiting to disagree. The awk finds the line and
# strips the key; everything after that is common to both homes, including the
# emptiness test, so `route:` followed only by spaces reads EMPTY on either side.
_dr_rtrim() { printf '%s' "${1%"${1##*[![:space:]]}"}"; }
ro_plan_f="$TOPIC_DIR/plan.md"
ro_plan=""; ro_plan_seen=0; ro_plan_why="no route line in plan preamble"
if [ -f "$ro_plan_f" ]; then
  ro_plan=$(_dr_route_in_preamble "$ro_plan_f"); ro_plan_rc=$?
  case $ro_plan_rc in
    0) ro_plan_seen=1; ro_plan=$(_dr_rtrim "$ro_plan")
       [ -n "$ro_plan" ] || ro_plan_why="a route line in the plan preamble whose value is EMPTY" ;;
    1) ro_plan="" ;;   # searched, not there
    *) ro_plan=""; ro_plan_why="plan.md is present but could not be READ (rc $ro_plan_rc) — a fault, not an absence" ;;
  esac
else ro_plan_why="no plan.md beside the workspace"; fi
# THE ADAPTER HAS THE SAME THREE STATES AS THE PLAN, and until a line-by-line
# comparison of this block's two halves they were not told apart: `project_get`
# returns 2 when there is no project.kv AT ALL and 1 when the adapter was read
# and carries no route=, and both printed the sentence written for the second.
# A workspace with no adapter was reported as an adapter found silent — the
# absent-file/absent-key pair the plan half above distinguishes in its own
# `case`. Every fixture in `99-routing` has no project.kv, so the suite pinned
# the wrong sentence along with it.
# WHY THIS DOOR STATES THE CAUSE while the ledger and the slice binding below
# FORWARD the callee's words verbatim: forward when a non-zero rc does not
# determine the cause — derive_cost declines for several reasons and
# binding_repo for several more, so only its own sentence says which — and
# state it here when it does. `project_get` returns 2 from exactly one line,
# and the advice that rides its message ("the project adapter is required")
# is addressed to a caller that requires one, which this reader does not.
ro_kv=""; ro_kv_seen=0; ro_kv_why="project.kv declares no route="
ro_raw=$(project_get "$WS" route 2>/dev/null); ro_kv_rc=$?
case $ro_kv_rc in
  0) ro_kv_seen=1; ro_kv=$(_dr_rtrim "$ro_raw")
     [ -n "$ro_kv" ] || ro_kv_why="project.kv's route= is declared EMPTY" ;;
  1) : ;;   # the adapter was READ and carries no route= — the default above
  *) ro_kv_why="no project.kv beside the workspace" ;;
esac
if [ -z "$ro_plan" ] && [ -z "$ro_kv" ]; then
  printf '  verdict  none (%s; %s)\n' "$ro_plan_why" "$ro_kv_why"
  echo "           An absent verdict is this block's most likely first reading, and it points"
  echo "           UPSTREAM at whoever routed the work — not at this report. Adding it after"
  echo "           split is a plan_changed; project.kv stays writable (config-and-adapters §3)."
else
  [ -n "$ro_plan" ] && printf '  verdict  [plan preamble] %s\n' "$ro_plan"
  [ -n "$ro_kv" ]   && printf '  verdict  [project.kv]    %s\n' "$ro_kv"
  if [ -n "$ro_plan" ] && [ -n "$ro_kv" ] && [ "$ro_plan" != "$ro_kv" ]; then
    echo "  DISAGREEMENT: the two homes carry different verdicts. Neither is preferred and this"
    echo "           report picks neither — it is a finding for the close-out author to record."
  fi
  # A home declared and left blank while the other answered is a half-done copy,
  # and it is the one shape a reader of the answered line would never suspect.
  [ "$ro_plan_seen" -eq 1 ] && [ -z "$ro_plan" ] \
    && echo "  note: the plan preamble carries a route line whose value is EMPTY (declared, not filled)"
  [ "$ro_kv_seen" -eq 1 ] && [ -z "$ro_kv" ] \
    && echo "  note: project.kv declares route= EMPTY (declared, not filled)"
fi

# WHY close-out's MANIFEST GAINS NOTHING for any of this, asked before it could
# be noticed as missing: `config/stages.tsv`'s header rule says an artifact a
# stage checklist names is an artifact its manifest owes, and the close-out card
# now names a routing outcome drawn from `plan.md` and `project.kv`. The rule
# is not violated, because its own reason does not reach here — the manifest
# exists so a session is HANDED the contract it is graded against, and its
# content joins `compose_fingerprint`. The close-out author is graded on neither
# file; they run a script and paste what it prints, and handing them the plan
# would mean reading the whole plan at close-out, which this tree avoids
# everywhere else. The cost is stated rather than hidden: a route line added
# between two close-out attempts does not move the fingerprint, so a relaunch
# can meet `no_novelty` — which is a budget argument and not a refusal, and is
# already true of every other project.kv edit.

# -- what the run cost, split the way a lane choice turns on -------------------
# ONE PAIRING, TWO READERS: the spans come from derive_cost.sh --stage-totals,
# never from a second pairing written here, so the two instruments cannot
# disagree about what a span is. The bucketing is `config/stages.tsv`'s own
# `scope` column — declared, not a hand-listed set of stage names, which is the
# proxy that has miscounted in this tree before.
# The ceremony half is the quantity a lane choice actually turns on. It is NOT
# "paid once whatever the slice count", which this comment and the boundary it
# prints both said until the block was run over every finished topic on disk:
# `config/stages.tsv` sends a flagged split-check back to `split`, so the loop
# re-runs, and the measured ceremony spanned 6x across six real topics with the
# widest topic not the dearest. What a one-slice topic would pay is the FLOOR —
# one round of each of the four — and a topic's measured ceremony is an upper
# bound on it. The SPREAD is the one figure kept here, because "not fixed"
# without it invites the reader to assume "not fixed by much"; the readings
# themselves stay out of this file, which derives figures rather than storing
# them.
# NOT the topic clock. Slice 00's `started` stamp brackets the entire delivery
# (architecture.md §12, the ruling measured at 128394s of "working"), so it is
# the wrong instrument for this and is never read: these are per-stage
# spawn->record spans, and slice 00 contributes only the four stages it ran.
# The refusal is FORWARDED, never re-worded: derive_cost distinguishes a missing
# ledger from a corrupt one, and re-describing its outcome here would collapse
# fault into absent — which is the store's own cardinal error, and this file
# hard-stops on exactly that for the gates surface twenty lines up. One call:
# in totals mode nothing is written to stderr on success, so merging the streams
# is safe and the rc is what decides.
ro_tot=$("$DR_DIR/derive_cost.sh" --stage-totals "$WS" 2>&1); ro_cost_rc=$?
if [ "$ro_cost_rc" -ne 0 ]; then
  printf '  cost split  none (derive_cost.sh declined, in its own words: %s)\n' \
    "$(printf '%s' "$ro_tot" | head -1)"
elif [ -z "$ro_tot" ]; then
  echo "  cost split  none (derive_cost.sh produced no rows and did not say why — report this)"
else
  printf '%s\n' "$ro_tot" | awk -F'\t' -v tsv="$WF_ROOT/config/stages.tsv" '
    function hm(s) { return sprintf("%dh%02dm", int(s/3600), int((s%3600)/60)) }
    BEGIN { nscope = 0
            while ((getline l < tsv) > 0) {
              if (l ~ /^#/ || l == "") continue
              if (split(l, f, "\t") < 2) continue
              scope[f[1]] = f[2]; nscope++ } }
    $1 == "paired" { np = $2; nk = $3; nd = $4 }
    $1 == "stage"  { sc = ($2 in scope) ? scope[$2] : "unknown"
                     cnt[sc] += $3; sec[sc] += $4; tot += $4
                     names[sc] = names[sc] (names[sc] == "" ? "" : " ") $2 }
    END {
      print "  cost split (spawn->record spans, parks excluded; one pairing shared with derive_cost.sh)"
      # EVERY bucket present is printed, and the set is not enumerated here. The
      # two this section exists for come first; anything else the scope column
      # declares follows, sorted, under its own name. A hand-listed set was the
      # first form, and it had the failure mode this tree already ruled on: a
      # third scope value would have joined the denominator and printed nowhere,
      # so the percentages would not sum and a whole bucket would be invisible.
      lab["topic"] = "topic-level ceremony"; lab["slice"] = "per-slice work"
      lab["unknown"] = "UNDECLARED stage scope"
      no = 0
      if ("topic" in cnt) ord[++no] = "topic"
      if ("slice" in cnt) ord[++no] = "slice"
      nr = 0
      for (sc in cnt) if (sc != "topic" && sc != "slice") rest[++nr] = sc
      for (i = 1; i <= nr; i++) for (j = i + 1; j <= nr; j++)
        if (rest[j] < rest[i]) { tsw = rest[i]; rest[i] = rest[j]; rest[j] = tsw }
      for (i = 1; i <= nr; i++) ord[++no] = rest[i]
      for (k = 1; k <= no; k++) { sc = ord[k]
        printf "    %-22s %3d spans  %8s  %5.1f%%   (%s)\n",
          (sc in lab) ? lab[sc] : ("scope=" sc),
          cnt[sc], hm(sec[sc]), (tot ? 100*sec[sc]/tot : 0), names[sc] }
      if (nscope == 0)
        print "    (stages.tsv declared NO scopes — unreadable or empty, so every stage above is undeclared for that reason and not because the table is short)"
      else if ("unknown" in cnt)
        print "    (a stage the scope column does not declare is bucketed, never dropped — stages.tsv owes it a row)"
      # A ledger that was READ and yielded no pair is not an absent ledger, and
      # the two printed identically until a loop-walk on a hand-built fixture
      # produced one: sixteen rows carrying no stage field, an honest 0/0/0, and
      # no way to tell it from a workspace with no ledger at all. Same
      # distinction the rest of this block owes everywhere else.
      if (np == 0)
        print "    the ledger was READ and holds no spawn->record pair at all — which is not an absent ledger; rows carrying no stage field, or a run that recorded none, both land here"
      else
        printf "    %d paired / %d kept / %d dropped for containing a park; a dropped span is in NEITHER row above\n", np, nk, nd
    }'
fi

# -- what a review actually changed --------------------------------------------
# The fix stage is where a postcheck finding becomes a commit, so these rows are
# the review loops output in the delivered repo. The store holds cu -> SHA and
# the subject; the FILE LIST lives only in the commit, which is why this is the
# one git read in the file (boundary (d)).
echo "  review-driven commit units (progress rows at stage=fix — what a postcheck finding landed)"
ro_prog_bad=0
ro_prog=$(state_get "$WS" progress 2>/dev/null); [ $? -eq 3 ] && { _dr_fault progress; ro_prog=""; ro_prog_bad=1; }
ro_fix=$(printf '%s\n' "$ro_prog" | command grep -E '(^| )stage=fix( |$)' || true)
if [ -z "$ro_fix" ]; then
  # the field's `none` carries a TRUE reason like every other one here: over a
  # faulted surface "no review-driven commit unit on this topic" is a claim
  # nobody read anything to support, and the notice above does not excuse the
  # line below repeating the absent wording.
  if [ "$ro_prog_bad" -eq 1 ]; then
    echo "    none (the progress surface is FAULTED — unreadable, which is not the same as holding no fix row)"
  else
    echo "    none (no progress row at stage=fix — no review-driven commit unit on this topic)"
  fi
else
  # The caveat rides the ROWS, not the report: on a topic with no fix units it
  # was four lines explaining a classification decision about output that is not
  # there, in an artifact the close-out author pastes whole.
  echo "    Production or test is the READERs call: no adapter key declares a test path, so this"
  echo "    prints paths and classifies nothing. A block of test-only paths and a block touching"
  echo "    production read very differently for a lane decision, and inventing the split here"
  echo "    would put a project convention in a driver that cannot keep it current."
  printf '%s\n' "$ro_fix" | while IFS= read -r ro_row; do
    [ -n "$ro_row" ] || continue
    ro_sl=$(printf '%s\n' "$ro_row"  | command grep -oE '(^| )slice=[^ ]+'  | cut -d= -f2)
    ro_cu=$(printf '%s\n' "$ro_row"  | command grep -oE '(^| )cu=[^ ]+'     | cut -d= -f2)
    ro_sha=$(printf '%s\n' "$ro_row" | command grep -oE '(^| )sha=[^ ]+'    | cut -d= -f2)
    # The absence test comes BEFORE the trim, and the order is the whole of it:
    # `${row#* subject=}` returns the row unchanged when there is no subject
    # field, and trimming first could then make the two differ — so the fallback
    # would never fire and the entire record would print as a subject.
    # THREE STATES, not two, and the third was found by running this block over
    # the six real topics on disk rather than over fixtures: 26 rows across
    # three of them carry `subject=` with NOTHING after it — 25 at stage=impl,
    # which this reader never opens, and ONE at stage=fix, which it does. That
    # one SHA resolves to a commit whose subject is a full sentence. The field is
    # empty on the ROW, not on the commit — old rows from before the writer
    # derived subjects, which is §13's adoption gap arriving in the open. A
    # blank tail after the sha said none of that; it read as a unit with a
    # short subject.
    ro_sub=${ro_row#* subject=}
    if [ "$ro_sub" = "$ro_row" ]; then ro_sub="(no subject on the row)"
    else ro_sub=${ro_sub%"${ro_sub##*[![:space:]]}"}   # the row keeps a trailing space; the subject does not own it
         [ -n "$ro_sub" ] || ro_sub="(subject= declared, not filled — the commit may still carry one)"; fi
    printf '    slice %s · cu-%s · %.8s  %s\n' "${ro_sl:-??}" "${ro_cu:-?}" "${ro_sha:-????????}" "$ro_sub"
    # The binding's own diagnosis is FORWARDED, not re-worded — the same rule
    # this block applies to derive_cost's refusal, and it was broken here in the
    # same way: `binding_kind` refuses a corrupt slices surface with rc 3 and a
    # named FAULT on stderr ("never read as the code default"), and sending that
    # to /dev/null replaced a precise cause with a vaguer one. A faulted index
    # and an unresolvable repo are different things, and only one of them means
    # the store needs inspecting.
    ro_bind_err=$(binding_repo "$WS" "$ro_sl" 2>&1 >/dev/null)
    ro_repo=$(binding_repo "$WS" "$ro_sl" 2>/dev/null) || ro_repo=""
    if [ -n "$ro_bind_err" ]; then
      printf '        none (the slice binding could not be resolved — %s)\n' \
        "$(printf '%s' "$ro_bind_err" | head -1)"
    elif [ -z "$ro_repo" ] || ! git -C "$ro_repo" rev-parse --git-dir >/dev/null 2>&1; then
      printf '        none (repo unreadable: %s)\n' "${ro_repo:-unresolved for slice $ro_sl}"
    elif ! git -C "$ro_repo" rev-parse -q --verify "$ro_sha^{commit}" >/dev/null 2>&1; then
      printf '        none (sha not found: %s) — consolidation or gc has moved this history\n' "$ro_sha"
    else
      # A MERGE commit, and an empty one, make `show --numstat` print nothing at
      # all — the one outcome every other branch here exists to prevent. Caught
      # by asking what git does when it succeeds and still says nothing.
      # A DISPLAY cap, and the reason it is not a config key: it bounds what this
      # block PRINTS, never what it reads, and a per-slice budget already bounds
      # what a unit may touch (30 files). The bound exists because this is the
      # only unbounded print in a report that gets pasted whole into an artifact
      # with a hard line cap — measured: the paste is 577 of 2000 lines today,
      # and the budgets permit 240 file-list lines from ONE slice's fix units.
      # Truncation is NAMED and carries the command that shows the rest, because
      # a silently short list would read as a small change.
      ro_files=$(git -C "$ro_repo" show --numstat --format= "$ro_sha" \
                 | awk -F'\t' -v cap=12 -v sha="$ro_sha" 'NF>=3 { n++
                     if (n <= cap) { if ($1 == "-") printf "        %11s  %s\n", "binary", $3
                                     else printf "        %5s %5s  %s\n", "+" $1, "-" $2, $3 } }
                   END { if (n > cap) printf "        …and %d more file(s) — git show --numstat --format= %s\n", n - cap, sha }')
      if [ -n "$ro_files" ]; then printf '%s\n' "$ro_files"
      else printf '        none (no file list: %.8s is a merge or an empty commit)\n' "$ro_sha"; fi
    fi
  done
fi
echo "  (the defect numbers this block would otherwise repeat are single-sourced above:"
echo "   leak_class in section 2, reviewer coverage and the precheck DRE in section 3)"
# HOW TO READ THESE, printed rather than left in a comment, because every other
# section of this report carries its use-boundary where the reader meets it and
# this one carried its only such sentence in the source. Two of the three are
# properties of the numbers; the third is about what measuring does to people.
echo "  Reading boundaries, because none of this is a target:"
echo "   · the ceremony SHARE moves with slice count, so shares are not comparable across"
echo "     topics of different widths — and the ABSOLUTE figure is not a constant either."
echo "     It is one round each of the four topic-scope stages PLUS however many times a"
echo "     flagged split-check sent the split back to be redone, so a narrow contested"
echo "     topic can pay several times a wide uncontested one. The SPAN COUNT beside the"
echo "     hours is where that shows: read it before treating one topic's ceremony as"
echo "     the price of admission."
echo "   · a long list of review-driven units is not a worse topic than a short one. It says"
echo "     the review loop reached the repository, which is what it is for; a topic with none"
echo "     is equally consistent with nothing to find and with nobody recording what was."
echo "   · nothing here scores a person or a decision. It is one topic's reading, put beside"
echo "     the verdict so a ROUTING RULE can be calibrated against outcomes over many topics."

}
