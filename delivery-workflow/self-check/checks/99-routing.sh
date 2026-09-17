#!/usr/bin/env bash
# 99-routing — the routing-outcome block of derive_report.sh: the lane verdict is
# CARRIED and parsed nowhere, the cost split buckets by the DECLARED stage scope
# over ONE pairing shared with derive_cost.sh, and every way an input can fail to
# answer prints its own named `none`.
#
# Why it is its own file rather than more of `98-report`. That file had grown to
# cover four concerns — derive_report's five sections, derive_cost, the
# maintenance WARN function, and the runner's own tree verdict — and these
# assertions took it past `cap.selftest_file`, which `60-gates` caught on the
# commit that did it. The cap is not a line budget to route around: it targets
# files nobody can review whole. So this is the sanctioned move, a
# concern-coherent split under an honest header (architecture §12, ferry
# halves), and the concern is one instrument's contract.
#
# THE CONTRACT UNDER TEST, stated once so no arm below has to restate it: the
# verdict is an opaque string with two homes and no precedence between them
# (`design/config-and-adapters.md` §3). Nothing here asserts what a lane value
# MEANS — the moment this tree interpreted one it would own a rule it cannot
# keep current — and that absence is deliberate, not an omission.
#
# HONEST BOUNDARY: every fixture here is synthetic except the git ones, which
# build real repositories because `git show --numstat` has behaviours no mock
# reproduces (an empty file list for a merge, a dash for a binary). What no
# fixture can stage is a human writing a verdict at all; that is VD-57.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/fixtures/lib.sh"
. "$RS/lib/state.sh"   # fixtures write THROUGH the store so headers verify

DR="$RS/derive_report.sh"
precond "derive_report.sh exists and parses" bash -n "$DR"

echo "-- routing outcome: the verdict is CARRIED from both homes, and parsed nowhere --"
# The block exists so a routing decision can be set beside what the run cost —
# six topics ran with theirs written nowhere a machine reads. Every arm here is
# about carrying a string faithfully or naming its absence: the moment this file
# INTERPRETED a lane value it would own a rule it cannot keep current
# (`design/config-and-adapters.md` §3), so there is deliberately no assertion
# anywhere below about what a verdict MEANS.
mk_topic() { # -> <topic>/delivery workspace, so ../plan.md is isolated per fixture
  local t; t=$(sc_tmpdir); mkdir -p "$t/delivery/.runtime/state"; printf '%s' "$t/delivery"
}
ro_sec() { printf '%s\n' "$1" | sed -n '/^## routing outcome/,/^## open validation-debt/p'; }
ro_run() { ro_sec "$("$DR" "$1" 2>&1)"; }

# (1) NEITHER home filled. The arm a first live topic is likeliest to print, so
# its wording has to name both places it looked and point upstream rather than
# read as a fault in this report.
wr=$(mk_topic); printf '# a plan\n\n## 1. work\n' > "$wr/../plan.md"
printf 'repo=/nonexistent\n' > "$wr/project.kv"    # an adapter that WAS read and carries no route=
o=$(ro_run "$wr")
command grep -qF 'verdict  none (no route line in plan preamble; project.kv declares no route=)' <<< "$o" \
  && ok "neither home filled: one none, naming BOTH places it looked" \
  || bad "absent arm wrong; got: $(printf '%s' "$o" | command grep -i verdict | head -2)"
# and an ABSENT plan is a different absence from a plan without the line
wr2=$(mk_topic)
command grep -qF 'none (no plan.md beside the workspace' <<< "$(ro_run "$wr2")" \
  && ok "…and a missing plan.md says so, rather than reading as a plan that carries no verdict" \
  || bad "the two absences print the same sentence"
# THE SAME PAIR ON THE ADAPTER SIDE, which is the half this file used to pin
# BACKWARDS: every fixture here is built without a project.kv, and the arm above
# asserted the sentence for an adapter that had been read and found silent. The
# two states come from different lines of `project_get` (rc 2 no file, rc 1 no
# key) and now print differently. A fixture per state, so neither can drift into
# the other: the one above HAS an adapter, this one has none.
wr3=$(mk_topic); printf '# a plan\n\n## 1. work\n' > "$wr3/../plan.md"
o3=$(ro_run "$wr3")
command grep -qF 'no project.kv beside the workspace' <<< "$o3" \
  && ok "no adapter AT ALL reads as a missing file, not as an adapter silent on route=" \
  || bad "absent-adapter arm wrong; got: $(printf '%s' "$o3" | command grep '  verdict' | head -1)"
command grep -qF 'project.kv declares no route=' <<< "$o3" \
  && bad "the absent-adapter arm still claims the adapter was read" \
  || ok "…and it does NOT also claim the adapter declares nothing — one state, one sentence"

# THE TITLE AND THE PLAN MUST NAME THE SAME TOPIC. `$WS/..` was resolved twice:
# by the kernel for `-f "$WS/../plan.md"`, which follows a symlinked workspace
# to its real parent, and by the shell for the report title, which is logical
# and stops at the symlink's parent. Through a symlink the report titled itself
# after one directory and read the other's plan, saying nothing about it. One
# physical resolution now serves both, and this arm is the shape that showed it.
wrs=$(mk_topic); printf '# a plan\n\nroute: delivery — through a symlink\n\n## 1. work\n' > "$wrs/../plan.md"
sym=$(sc_tmpdir)/ws-link; ln -sfn "$wrs" "$sym"
os=$("$DR" "$sym" 2>&1)
want=$(basename "$(cd -P "$wrs/.." && pwd -P)")
printf '%s\n' "$os" | head -1 | command grep -qF "governance report — $want" \
  && command grep -qF 'through a symlink' <<< "$os" \
  && ok "through a symlinked workspace the title and the plan it reads name the SAME topic" \
  || bad "symlinked workspace: title and plan disagree; title=$(printf '%s' "$os" | head -1)"

# A plan.md that EXISTS and cannot be read is a fault, not an absence — the
# third place in this block those two had to be told apart, after the ledger and
# the empty declaration. The awk distinguishes them by exit status: 1 is
# searched-and-not-found, anything else is could-not-read.
wr=$(mk_topic)
printf '# a plan\n\nroute: delivery — unreachable\n\n## 1. work\n' > "$wr/../plan.md"
chmod 000 "$wr/../plan.md"
if [ -r "$wr/../plan.md" ]; then
  ok "SKIP (named): this user reads a mode-000 file, so the unreadable-plan arm cannot be staged here"
else
  command grep -qF 'could not be READ' <<< "$(ro_run "$wr" 2>/dev/null)" \
    && ok "known-bad: an unreadable plan.md reports a FAULT, never 'no route line in plan preamble'" \
    || bad "an unreadable plan was reported as a plan carrying no verdict"
fi
chmod 644 "$wr/../plan.md"

# (2) the plan preamble alone, blockquoted — which is how real preambles carry
# their pin rows, so the de-quoting is load-bearing rather than cosmetic.
wr=$(mk_topic)
printf '# a plan\n\n> **baseline**\n> route: delivery — Q1 yes: forced; Q2 yes; Q3 yes\n\n## 1. work\n' > "$wr/../plan.md"
o=$(ro_run "$wr")
command grep -qF '[plan preamble] delivery — Q1 yes: forced; Q2 yes; Q3 yes' <<< "$o" \
  && ok "a blockquoted route line is carried whole, with its source labelled" \
  || bad "blockquoted verdict lost; got: $(printf '%s' "$o" | command grep -i verdict | head -2)"

# (3) a FENCED grammar example is not a verdict. This is the false positive the
# shape invites: wherever the routing rule itself is written down, the verdict
# line appears inside a fenced block as its grammar — paste that into a preamble
# as a template and a naive first-match reader adopts the example.
wr=$(mk_topic)
printf '# a plan\n\n```\nroute: <lane> — Q1 …; Q2 …; Q3 …\n```\n\nroute: direct — Q1 yes; Q2 yes; Q3 yes\n\n## 1. work\n' > "$wr/../plan.md"
o=$(ro_run "$wr")
command grep -qF '[plan preamble] direct — Q1 yes; Q2 yes; Q3 yes' <<< "$o" \
  && ok "known-bad: a fenced grammar example is skipped and the real line below it is taken" \
  || bad "the fenced example was adopted as the verdict; got: $(printf '%s' "$o" | command grep -i verdict | head -2)"
wr=$(mk_topic)
printf '# a plan\n\n```\nroute: <lane> — the grammar\n```\n\n## 1. work\n' > "$wr/../plan.md"
command grep -qF 'verdict  none (no route line in plan preamble' <<< "$(ro_run "$wr")" \
  && ok "…and a preamble holding ONLY the fenced example reads as no verdict at all" \
  || bad "a plan carrying only a grammar example reported a verdict"

# (3b) THE OTHER MARKDOWN A PREAMBLE MAY LEGALLY CARRY. The first form of the
# reader knew one fence marker and one heading shape; an independent read
# running the SHIPPED script over hostile plans found four legal shapes it
# mishandled, each printing a grammar sample or a post-heading sentence as the
# topic verdict. All four are pinned here, and the last arm is the regression
# half: a `---` after a BLANK line is a divider, not a setext underline, and
# three real plans carry exactly that divider shape inside their preambles —
# the preamble must NOT end at one.
wr=$(mk_topic)
printf '# a plan\n\n~~~\nroute: R2 — the tilde-fenced grammar sample\n~~~\n\n## 1. work\n' > "$wr/../plan.md"
o=$(ro_run "$wr")
command grep -qF 'verdict  none (no route line in plan preamble' <<< "$o" \
  && ok "known-bad: a TILDE-fenced grammar sample is skipped, not adopted as the verdict" \
  || bad "a tilde-fenced sample was adopted; got: $(printf '%s' "$o" | command grep -i verdict | head -2)"
# …and the fence must OPEN and CLOSE on the tilde marker: a reader that knew
# no tilde fence adopts the sample; one that opens but cannot close swallows
# the real line below it. Three states, three outputs — this is the arm that
# tells them apart.
wr=$(mk_topic)
printf '# a plan\n\n~~~\nroute: R2 — the tilde-fenced grammar sample\n~~~\n\nroute: direct — the real verdict\n\n## 1. work\n' > "$wr/../plan.md"
o=$(ro_run "$wr")
command grep -qF '[plan preamble] direct — the real verdict' <<< "$o" \
  && ok "known-bad: a tilde fence opens AND closes — the sample inside it skipped, the real line below taken" \
  || bad "the tilde fence did not both open and close; got: $(printf '%s' "$o" | command grep -i verdict | head -2)"
# an ATX heading indented 1-3 spaces is a heading (CommonMark), and the
# preamble ends at it exactly as at an unindented one
wr=$(mk_topic)
printf '# a plan\n\n  ## 1. work\n\nroute: direct — a post-heading sentence, not the verdict\n' > "$wr/../plan.md"
o=$(ro_run "$wr")
command grep -qF 'verdict  none (no route line in plan preamble' <<< "$o" \
  && ok "known-bad: a 1-3-space-indented heading ends the preamble — a route: after it is not the verdict" \
  || bad "an indented heading did not end the preamble; got: $(printf '%s' "$o" | command grep -i verdict | head -2)"
# a SETEXT heading: a paragraph line directly underlined with dashes
wr=$(mk_topic)
printf '# a plan\n\nFirst section\n-------------\n\nroute: direct — after a setext heading, not the verdict\n' > "$wr/../plan.md"
o=$(ro_run "$wr")
command grep -qF 'verdict  none (no route line in plan preamble' <<< "$o" \
  && ok "known-bad: a setext-underlined heading ends the preamble — no raw-line test can see it" \
  || bad "a setext heading did not end the preamble; got: $(printf '%s' "$o" | command grep -i verdict | head -2)"
# an INDENTED CODE BLOCK: 4+ spaces is code, not text — a route: inside one is
# a sample, and stripping the indent first (the first form) made it the verdict
wr=$(mk_topic)
printf '# a plan\n\nThe grammar:\n\n    route: R1 — an indented code block sample\n\n## 1. work\n' > "$wr/../plan.md"
o=$(ro_run "$wr")
command grep -qF 'verdict  none (no route line in plan preamble' <<< "$o" \
  && ok "known-bad: a route: in a 4-space indented code block is skipped, not adopted" \
  || bad "an indented code sample was adopted; got: $(printf '%s' "$o" | command grep -i verdict | head -2)"
# …and a TAB indents a code block too, by the same CommonMark count of four
wr=$(mk_topic)
printf '# a plan\n\n\troute: R1 — a tab-indented code block sample\n\n## 1. work\n' > "$wr/../plan.md"
o=$(ro_run "$wr")
command grep -qF 'verdict  none (no route line in plan preamble' <<< "$o" \
  && ok "…and a tab-indented code line is skipped the same way" \
  || bad "a tab-indented sample was adopted; got: $(printf '%s' "$o" | command grep -i verdict | head -2)"
# the REGRESSION half: a `---` after a blank line is a DIVIDER, not a setext
# underline — three real plans carry exactly this shape inside their preambles
# (pin rows quoted, a divider, more quoted rows) and the preamble must not end
# at the divider. A false boundary here reads as `none` on a plan that DOES
# carry its verdict, which is the silent half of every failure above.
wr=$(mk_topic)
printf '# a plan\n\n> **baseline** — pin rows quoted the way real preambles carry them\n\n---\n\n> route: delivery — after a divider, still the preamble\n\n## 1. work\n' > "$wr/../plan.md"
o=$(ro_run "$wr")
command grep -qF '[plan preamble] delivery — after a divider, still the preamble' <<< "$o" \
  && ok "a divider (blank line before the dashes) does NOT end the preamble — the real plans' shape" \
  || bad "a divider was read as a heading and the preamble ended early; got: $(printf '%s' "$o" | command grep -i verdict | head -2)"

# (3c) THE RE-VERIFICATION PASS found the fix above carrying its own dead
# gate. The post-quote indented-code test sat AFTER a quote-strip that
# consumed EVERY space following the marker, so no line could reach it with
# its indent intact: the quoted code shapes below were still adopted as
# verdicts, while the comment claimed the gate covered them — the
# vacuous-protection shape this file's own card arm warns about, reproduced
# by the fix that warned of it. The first two arms were RED against the
# first fix and are pinned here; the last two pin shapes that first fix
# already handled, so they stay handled.
wr=$(mk_topic)
printf '# a plan\n\n>     route: R1 — a quoted indented code block sample\n\n## 1. work\n' > "$wr/../plan.md"
o=$(ro_run "$wr")
command grep -qF 'verdict  none (no route line in plan preamble' <<< "$o" \
  && ok "known-bad: a route: in a QUOTED indented code block (marker + 5 spaces) is skipped" \
  || bad "a quoted indented code sample was adopted; got: $(printf '%s' "$o" | command grep -i verdict | head -2)"
wr=$(mk_topic)
printf '# a plan\n\n> \troute: R1 — a quoted tab-indented code sample\n\n## 1. work\n' > "$wr/../plan.md"
o=$(ro_run "$wr")
command grep -qF 'verdict  none (no route line in plan preamble' <<< "$(ro_run "$wr")" \
  && ok "known-bad: a marker + space + TAB is quoted code, not a verdict" \
  || bad "a quoted tab-indented sample was adopted; got: $(printf '%s' "$o" | command grep -i verdict | head -2)"
wr=$(mk_topic)
printf '# a plan\n\n>  ## 1. work\n\nroute: direct — after a quoted indented heading\n' > "$wr/../plan.md"
o=$(ro_run "$wr")
command grep -qF 'verdict  none (no route line in plan preamble' <<< "$o" \
  && ok "a heading indented inside its quote (marker + 2 spaces) ends the preamble" \
  || bad "a quoted indented heading did not end the preamble; got: $(printf '%s' "$o" | command grep -i verdict | head -2)"
wr=$(mk_topic)
printf '# a plan\n\n    > route: R1 — a marker indented four spaces\n\n## 1. work\n' > "$wr/../plan.md"
command grep -qF 'verdict  none (no route line in plan preamble' <<< "$(ro_run "$wr")" \
  && ok "a quote MARKER indented four spaces is an indented code line, never de-quoted" \
  || bad "an indented quote marker was de-quoted into a verdict"

# (3d) THE BOUNDARY PAIRS of the column rule, pinned where they flip. Each
# pair differs by ONE column or ONE character; both sides are asserted, so a
# reader that drifts the count cannot pass one side and silently keep the
# other. All four were verified on the shipped reader BEFORE this block was
# written — these arms pin working behaviour, they do not introduce it.
# EQUALS joins dashes as a setext underline — the two are one rule, and only
# the dash half had an arm.
wr=$(mk_topic)
printf '# a plan\n\nFirst section\n=====\n\nroute: direct — after an equals setext heading\n' > "$wr/../plan.md"
command grep -qF 'verdict  none (no route line in plan preamble' <<< "$(ro_run "$wr")" \
  && ok "an EQUALS setext underline ends the preamble like a dash one" \
  || bad "an equals underline did not end the preamble"
# a fence INSIDE a blockquote still fences: the sample in it is not a verdict
wr=$(mk_topic)
printf '# a plan\n\n> ```\n> route: R1 — a quoted fenced sample\n> ```\n\n## 1. work\n' > "$wr/../plan.md"
command grep -qF 'verdict  none (no route line in plan preamble' <<< "$(ro_run "$wr")" \
  && ok "a fence inside a blockquote still fences — the route: in it is a sample" \
  || bad "a quoted fenced sample was adopted as the verdict"
# marker + 4 spaces: the marker consumed one, three remain, a heading at
# three columns is a HEADING — and at four (marker + 5) it is code. The pair
# is the column rule stated at its flip point.
wr=$(mk_topic)
printf '# a plan\n\n>    ## 1. work\n\nroute: direct — after a quoted 3-column heading\n' > "$wr/../plan.md"
command grep -qF 'verdict  none (no route line in plan preamble' <<< "$(ro_run "$wr")" \
  && ok "a heading at three content columns (marker+4) ends the preamble — the marker ate one space" \
  || bad "a marker+4 heading did not end the preamble"
wr=$(mk_topic)
printf '# a plan\n\n>     ## not a heading, quoted code\n\nroute: delivery — still the preamble\n\n## 1. work\n' > "$wr/../plan.md"
o=$(ro_run "$wr")
command grep -qF '[plan preamble] delivery — still the preamble' <<< "$o" \
  && ok "…and at four content columns (marker+5) it is CODE, so the preamble runs on past it" \
  || bad "the marker+5 line was read as a heading; got: $(printf '%s' "$o" | command grep -i verdict | head -1)"
# a LAZY continuation: CommonMark lets a quoted paragraph continue on an
# unquoted line, so this route: line is inside the quote — and it is the
# preamble's first route: line either way, which is the reading pinned here.
wr=$(mk_topic)
printf '# a plan\n\n> some paragraph\nroute: delivery — a lazy continuation of the quote\n\n## 1. work\n' > "$wr/../plan.md"
command grep -qF '[plan preamble] delivery — a lazy continuation of the quote' <<< "$(ro_run "$wr")" \
  && ok "a route: line lazily continuing a quoted paragraph is still the preamble's first route: line" \
  || bad "a lazy continuation was dropped from the preamble"

# (3e) THE BREAK RULE'S OTHER TWO CHARACTERS. A thematic break is three or
# more of ONE character, and the character set is `- * _` — the reader handled
# the dash half (setext underline under a paragraph, divider after a blank)
# and treated `***`/`___` lines as PARAGRAPH CONTENT, so a `***` directly
# under a paragraph armed the setext memory and a `---` right after it ended
# the preamble early: a false `none` on a plan that carries its verdict. An
# HTML block is the one construct still unmodelled, and it is named at the
# reader's header rather than patched here — see that comment for the failure
# directions.
wr=$(mk_topic)
printf '# a plan\n\nA paragraph\n***\n---\n\nroute: delivery — after a star break and a dash divider\n\n## 1. work\n' > "$wr/../plan.md"
o=$(ro_run "$wr")
command grep -qF '[plan preamble] delivery — after a star break and a dash divider' <<< "$o" \
  && ok "known-bad: a *** break interrupts the paragraph, so the --- after it is a divider, not a setext underline" \
  || bad "a star break armed the setext memory and the preamble ended early; got: $(printf '%s' "$o" | command grep -i verdict | head -1)"
wr=$(mk_topic)
printf '# a plan\n\nA paragraph\n___\n\nroute: delivery — after an underscore break\n\n## 1. work\n' > "$wr/../plan.md"
command grep -qF '[plan preamble] delivery — after an underscore break' <<< "$(ro_run "$wr")" \
  && ok "…and an underscore break is a break, never paragraph content" \
  || bad "an underscore break was read as paragraph content"

# (3f) WHAT THE RULE DID NOT SAY, found by re-reading each restated rule for
# the things it is silent on: where SPACES may sit, what a closer may CARRY,
# how a file may END its lines, and whether a skipped line still feeds the
# paragraph memory. Five divergences, every one verified on the shipped
# reader before this block was written:
# · a break may carry spaces BETWEEN its characters (`- - -` is a break) —
#   read as paragraph content, it armed the setext memory;
# · an underline may carry spaces AFTER it (`---   `) — unrecognized, the
#   heading did not end the preamble and a post-heading route: was ADOPTED;
# · a closer may carry NOTHING but spaces — a ```lang line inside an open
#   fence is content, and reading it as a closer adopted the sample after it;
# · a closer must be at least as long as its opener — a ``` inside a ````-fence
#   read as a closer stranded a real verdict INSIDE the fence (a false none);
# · a CRLF file's blank lines carry \r, so no underline ever matched — and a
#   CRLF plan's real headings do not end the preamble (the ADOPTION
#   direction; every real plan is LF today, verified).
# Plus the paragraph-memory rule: a line of `===` after a blank is a
# PARAGRAPH, so the dash line under it is its underline — an equals run that
# is not an underline must still feed the memory it is a paragraph.
wr=$(mk_topic)
printf '# p\n\nA paragraph\n- - -\n---\n\nroute: delivery — spaced break then divider\n\n## 1. work\n' > "$wr/../plan.md"
o=$(ro_run "$wr")
command grep -qF '[plan preamble] delivery — spaced break then divider' <<< "$o" \
  && ok "known-bad: a SPACED break (- - -) interrupts the paragraph, so the --- after it is a divider" \
  || bad "a spaced break armed the setext memory; got: $(printf '%s' "$o" | command grep -i verdict | head -1)"
wr=$(mk_topic)
printf '# p\n\nSection\n---   \n\nroute: direct — after a padded underline\n' > "$wr/../plan.md"
command grep -qF 'verdict  none (no route line in plan preamble' <<< "$(ro_run "$wr")" \
  && ok "known-bad: an underline with TRAILING SPACES still ends the preamble (a post-heading route: is not adopted)" \
  || bad "a padded underline was not recognized and the preamble ran past the heading"
wr=$(mk_topic)
printf '# p\n\n```\nroute: <lane> — the sample\n```js\nroute: R9 — the second sample\n```\n\nroute: delivery — the real verdict\n\n## 1. work\n' > "$wr/../plan.md"
o=$(ro_run "$wr")
command grep -qF '[plan preamble] delivery — the real verdict' <<< "$o" \
  && ok "known-bad: a fence line carrying an INFO STRING does not close — the sample after it stays fence content" \
  || bad "a lang-tagged fence line closed the fence and a sample was adopted; got: $(printf '%s' "$o" | command grep -i verdict | head -1)"
wr=$(mk_topic)
printf '# p\n\n````\nroute: <lane> — inside the long fence\n```\nstill inside\n````\n\nroute: delivery — after the proper close\n\n## 1. work\n' > "$wr/../plan.md"
o=$(ro_run "$wr")
command grep -qF '[plan preamble] delivery — after the proper close' <<< "$o" \
  && ok "known-bad: a SHORTER fence does not close a longer one — the real verdict is outside, not stranded inside" \
  || bad "a 3-backtick line closed a 4-backtick fence; got: $(printf '%s' "$o" | command grep -i verdict | head -1)"
wr=$(mk_topic)
printf '# p\r\n\r\nSection\r\n---\r\n\r\nroute: direct — after a CRLF heading\r\n' > "$wr/../plan.md"
command grep -qF 'verdict  none (no route line in plan preamble' <<< "$(ro_run "$wr")" \
  && ok "known-bad: a CRLF plan's headings still end the preamble (no underline ever matched over \\r)" \
  || bad "a CRLF plan's heading did not end the preamble — the adoption direction"
wr=$(mk_topic)
printf '# p\r\n\r\n> intro\r\n\r\n---\r\n\r\nroute: delivery — a CRLF plan\r\n\r\n## 1. work\r\n' > "$wr/../plan.md"
o=$(ro_run "$wr")
command grep -qF '[plan preamble] delivery — a CRLF plan' <<< "$o" \
  && ok "…and a CRLF plan's divider is still a divider — the verdict after it is found, byte-clean" \
  || bad "a CRLF plan lost its verdict at the divider; got: $(printf '%s' "$o" | command grep -i verdict | head -1)"
wr=$(mk_topic)
printf '# p\n\n===\n---\n\nroute: direct — after an equals paragraph\n' > "$wr/../plan.md"
command grep -qF 'verdict  none (no route line in plan preamble' <<< "$(ro_run "$wr")" \
  && ok "known-bad: an equals run after a blank is a PARAGRAPH, so the dash line under it is its underline" \
  || bad "an equals line after a blank did not arm the paragraph memory"

# (3g) THE ONE INTERACTION the per-rule passes could not see: a fence and the
# quote level that holds it. CommonMark binds a fenced block INSIDE its
# container — the closer must sit at the same quote depth, code cannot be
# lazily continued, so when the quote ends the fence ends with it, unclosed.
# The reader's fence state was global: a QUOTED fence line closed a TOP-LEVEL
# fence (adopting whatever sample came after it — the adoption direction), a
# quoted OPENER outlived its quote and stranded every later line (a real
# verdict read as `none`, pointing upstream at the plan author — the wrong
# party, which is the failure the entry itself names), and a top-level fence
# opening where a quoted one died was read as content of the dead fence.
# All three verified on the shipped reader before this block was written.
wr=$(mk_topic)
printf '# p\n\n```\n> ```\nroute: R9 — the sample\n```\n\nroute: delivery — the real verdict\n\n## 1\n' > "$wr/../plan.md"
o=$(ro_run "$wr")
command grep -qF '[plan preamble] delivery — the real verdict' <<< "$o" \
  && ok "known-bad: a quoted fence line is CONTENT of a top-level fence, never its closer — the sample after it is not adopted" \
  || bad "a quoted line closed a top-level fence and a sample was adopted; got: $(printf '%s' "$o" | command grep -i verdict | head -1)"
wr=$(mk_topic)
printf '# p\n\n> As documented:\n> ```\nroute: delivery — Q1 no; Q2 yes; Q3 no\n\n## 1\n' > "$wr/../plan.md"
o=$(ro_run "$wr")
command grep -qF '[plan preamble] delivery — Q1 no; Q2 yes; Q3 no' <<< "$o" \
  && ok "known-bad: a fence opened inside a quote ENDS with the quote — the verdict after it is found, not stranded" \
  || bad "a quoted opener stranded the lines after its quote; got: $(printf '%s' "$o" | command grep -i verdict | head -1)"
wr=$(mk_topic)
printf '# p\n\n> ```\n```\nroute: R9 — inside the new fence\n```\n\nroute: delivery — after it\n\n## 1\n' > "$wr/../plan.md"
o=$(ro_run "$wr")
command grep -qF '[plan preamble] delivery — after it' <<< "$o" \
  && ok "known-bad: where a quoted fence dies with its quote, a top-level fence OPENS afresh — the route: after it is fence content" \
  || bad "the line after a dead quoted fence was not read as a new fence opener; got: $(printf '%s' "$o" | command grep -i verdict | head -1)"

# (4) the preamble ENDS at the first heading: a route line under a section is
# not the topic verdict, and treating it as one would make any later mention win
wr=$(mk_topic)
printf '# a plan\n\n## 1. work\n\nroute: direct — a sentence about routing, not the verdict\n' > "$wr/../plan.md"
command grep -qF 'verdict  none (no route line in plan preamble' <<< "$(ro_run "$wr")" \
  && ok "a route: line AFTER the first heading is outside the preamble and is not read" \
  || bad "a post-heading mention was adopted as the topic verdict"

# (5) project.kv alone, and (6) both homes agreeing / disagreeing. NO precedence
# exists between them by design, so the disagreement arm must NAME the conflict
# instead of silently resolving it — a silent pick is how a ledger row would
# come to record a verdict nobody wrote.
wr=$(mk_topic); printf '# a plan\n\n## 1. work\n' > "$wr/../plan.md"
printf 'repo=/tmp\nbranch=x\ncommit.subject_regex=^x\nroute=delivery — from the adapter\n' > "$wr/project.kv"
o=$(ro_run "$wr")
command grep -qF '[project.kv]    delivery — from the adapter' <<< "$o" \
  && ok "project.kv alone answers, labelled as the adapter (no schema entry needed for the key)" \
  || bad "adapter-only verdict lost; got: $(printf '%s' "$o" | command grep -i verdict | head -2)"
command grep -q 'DISAGREEMENT' <<< "$o" \
  && bad "a single home produced a disagreement line" \
  || ok "…and one home alone never reads as a conflict"
printf '# a plan\n\nroute: delivery — from the adapter\n\n## 1. work\n' > "$wr/../plan.md"
o=$(ro_run "$wr")
# DISCRIMINABILITY (review-standards §13 step 4): asserting only the ABSENCE of a
# disagreement would pass on a broken parser too — one home found, nothing to
# disagree with, arm green. The fixture must be shown to hold BOTH homes before
# the absence means anything.
command grep -qF '[plan preamble] delivery — from the adapter' <<< "$o" \
  && command grep -qF '[project.kv]    delivery — from the adapter' <<< "$o" \
  && ! command grep -q 'DISAGREEMENT' <<< "$o" \
  && ok "both homes present AND identical is not a conflict (the fixture proves both were read)" \
  || bad "the agreeing case is wrong, or the fixture only ever had one home: $(printf '%s' "$o" | command grep -iE 'verdict|DISAGREE')"
printf '# a plan\n\nroute: planning+delivery — from the plan\n\n## 1. work\n' > "$wr/../plan.md"
o=$(ro_run "$wr")
command grep -q 'DISAGREEMENT: the two homes carry different verdicts' <<< "$o" \
  && command grep -qF 'from the plan' <<< "$o" \
  && command grep -qF 'from the adapter' <<< "$o" \
  && ok "known-bad: two homes disagreeing prints BOTH and names the conflict, picking neither" \
  || bad "the disagreement was resolved silently; got: $(printf '%s' "$o" | command grep -iE 'verdict|DISAGREE')"

# HOSTILE SHAPES in the one field that is arbitrary human text. The verdict is
# copied verbatim from a file a person wrote, so every shape a person can type
# reaches this printf: a percent (which would be a format if any value here were
# ever used as one — none is), a command substitution and backticks (data, never
# evaluated), a tab, and a pipe. All must survive BYTE-IDENTICAL, because the
# block's whole contract is that it carries and does not interpret. The pipe is
# the one with a consequence elsewhere: it is legal here and splits a row in the
# calibration table downstream, which that table now states and handles.
wrh=$(mk_topic)
printf '# a plan\n\nroute: delivery — 100%% forced; a|b pipe; $(id) and `id` literal\n\n## 1. work\n' \
  > "$wrh/../plan.md"
oh2=$(ro_run "$wrh")
command grep -qF 'delivery — 100% forced; a|b pipe; $(id) and `id` literal' <<< "$oh2" \
  && ok "a verdict carrying %, |, \$( ) and backticks is carried byte-identical (values are printf ARGUMENTS, never formats)" \
  || bad "the verdict was mangled, evaluated or truncated: $(printf '%s' "$oh2" | command grep -i verdict | head -2)"

# TRAILING WHITESPACE, which is where a false conflict comes from. Two trailing
# spaces is Markdown's own line-break syntax, so the plan preamble is one of the
# likeliest places on disk to carry them — and untrimmed they made two identical
# verdicts print as a DISAGREEMENT. A false conflict is worse than the silent
# pick this block refuses to make: it sends the close-out author to record
# something that is not there.
wr=$(mk_topic)
printf '# a plan\n\nroute: delivery — one verdict  \n\n## 1. work\n' > "$wr/../plan.md"
printf 'repo=/tmp\nbranch=x\ncommit.subject_regex=^x\nroute=delivery — one verdict\n' > "$wr/project.kv"
o=$(ro_run "$wr")
# Same discriminability rule as the agreeing arm above: prove both homes are in
# hand first, or a parser that dropped the trailing-space line would pass here.
command grep -qF '[plan preamble] delivery — one verdict' <<< "$o" \
  && command grep -qF '[project.kv]    delivery — one verdict' <<< "$o" \
  && ! command grep -q 'DISAGREEMENT' <<< "$o" \
  && ok "known-bad: trailing whitespace is trimmed off BOTH homes (both present, no conflict) — a markdown line break is not a disagreement" \
  || bad "the trailing-space case is wrong, or one home was silently dropped: $(printf '%s' "$o" | command grep -iE 'verdict|DISAGREE')"

# The SAME rule from the OTHER side, and it exists because an injection found the
# first half unpinned: the fixture above carries its trailing spaces in the plan,
# so deleting the adapter-side trim killed no check while the property claimed
# BOTH homes were trimmed. A property no mutation can kill is unpinned however
# many assertions surround it (review-standards §13 step 3). Here the adapter
# carries the whitespace and the plan does not.
wr=$(mk_topic)
printf '# a plan\n\nroute: delivery — one verdict\n\n## 1. work\n' > "$wr/../plan.md"
printf 'repo=/tmp\nbranch=x\ncommit.subject_regex=^x\nroute=delivery — one verdict   \n' > "$wr/project.kv"
o=$(ro_run "$wr")
command grep -qF '[plan preamble] delivery — one verdict' <<< "$o" \
  && command grep -qF '[project.kv]    delivery — one verdict' <<< "$o" \
  && ! command grep -q 'DISAGREEMENT' <<< "$o" \
  && ok "known-bad: trailing whitespace on the ADAPTER side is trimmed too (the other half of the same rule)" \
  || bad "the adapter-side trim is missing or one home was dropped: $(printf '%s' "$o" | command grep -iE 'verdict|DISAGREE')"

# DECLARED-BUT-EMPTY is a third state, not the absent one. An author who wrote
# the key and left it blank has not done what an author who never wrote it did,
# and the store's own absent-is-not-zero doctrine applies to a declaration.
wr=$(mk_topic)
printf '# a plan\n\nroute:\n\n## 1. work\n' > "$wr/../plan.md"
command grep -qF 'a route line in the plan preamble whose value is EMPTY' <<< "$(ro_run "$wr")" \
  && ok "known-bad: an empty route line reads as EMPTY, never as no line at all" \
  || bad "a declared-but-blank route line was reported as absent"
# …and a line whose value is WHITESPACE ONLY reads the same. This is the arm that
# breaks if the trailing trim is ever moved back into the awk: emptiness is
# tested AFTER the trim, at one place, for both homes, and `route:` followed by
# four spaces is a blank declaration and not a verdict made of spaces.
wr=$(mk_topic)
printf '# a plan\n\nroute:    \n\n## 1. work\n' > "$wr/../plan.md"
command grep -qF 'whose value is EMPTY' <<< "$(ro_run "$wr")" \
  && ok "…and a whitespace-only value reads EMPTY too (the trim and the test are one step apart, in that order)" \
  || bad "a whitespace-only route value was reported as a verdict"
wr=$(mk_topic)
printf '# a plan\n\nroute: delivery — from the plan\n\n## 1. work\n' > "$wr/../plan.md"
printf 'repo=/tmp\nbranch=x\ncommit.subject_regex=^x\nroute=\n' > "$wr/project.kv"
o=$(ro_run "$wr")
command grep -qF 'project.kv declares route= EMPTY (declared, not filled)' <<< "$o" \
  && command grep -qF '[plan preamble] delivery — from the plan' <<< "$o" \
  && ok "…and a half-done copy is named even when the OTHER home answered (the shape nobody would suspect)" \
  || bad "an empty declaration went unmentioned beside an answered one; got: $(printf '%s' "$o" | command grep -iE 'verdict|note')"

# The CARD's absent arms and this script's must name the same two states. Not an
# exact-string pin — the note is prose an author writes and the report is a
# machine field, and forcing one wording on both would put machine phrasing in a
# role card. What must not drift is the SET of states: absent, declared-empty,
# disagreeing. Pinned here rather than in a doc check because these are the same
# three arms the assertions above drive, and splitting them across two files is
# how the two halves came to disagree in the first place.
acard="$WF_ROOT/runtime-docs/cards/author.md"
precond "the author card is readable" test -f "$acard"
# Whitespace-NORMALISED before matching: a role card is prose and wraps where the
# column runs out, so a phrase can sit across two lines and mean exactly what it
# means. The first form of this arm grepped the raw segment and failed on the
# card's own line break — a check that fails on reflow is a check that will be
# "fixed" by reflowing, which teaches the wrong lesson.
cardseg=$(awk '/^- \*\*plan-validate\*\*/,/^- \*\*split\*\*/' "$acard" | tr -s '[:space:]' ' ')
# EVERY token here is a string the REPORT itself prints, and that is the whole
# selection rule. Two earlier forms failed it: `differing`, which broke when the
# card conjugated the verb differently (a check a reword breaks gets satisfied by
# rewording back), and then `differ`, which a MUTATION TEST showed was vacuous —
# it matched the word "difference" elsewhere in the same paragraph, so a card
# that never named the state would have passed. Machine-emitted strings have
# neither failure mode: they cannot be reworded without the program changing, and
# they do not occur incidentally in prose. Verify by mutation, not by reading.
for want in 'route:' 'project.kv' 'no route line in plan preamble' 'declared, not filled' 'DISAGREEMENT'; do
  command grep -qF "$want" <<< "$cardseg" \
    && ok "the card's plan-validate duty names '$want'" \
    || bad "the card's plan-validate segment does not name '$want' — the copy duty and the derived print have drifted apart"
done

echo "-- routing outcome: the cost split is stages.tsv's own scope column, over ONE pairing --"
# The bucketing must be the DECLARED scope, never a hand-listed set of stage
# names: a stage-name list standing in for a condition is the exact proxy that
# miscounted twice in the cost measurements (`split` matching `split-check`).
# And the split must not come from a second pairing — derive_cost.sh --stage-totals
# is the same awk, so the two instruments cannot disagree about what a span is.
wr=$(mk_topic)
state_append "$wr" ledger ferry "v=1 t=1000 event=spawn slice=00 stage=plan-validate mode=cold" >/dev/null
state_append "$wr" ledger ferry "v=1 t=1600 event=record slice=00 stage=plan-validate" >/dev/null
state_append "$wr" ledger ferry "v=1 t=2000 event=spawn slice=01 stage=spec mode=cold" >/dev/null
state_append "$wr" ledger ferry "v=1 t=3800 event=record slice=01 stage=spec" >/dev/null
o=$(ro_run "$wr")
command grep -qE 'topic-level ceremony +1 spans +0h10m +25\.0%.*plan-validate' <<< "$o" \
  && ok "plan-validate buckets as topic-level ceremony from the scope column (600s of 2400s = 25%)" \
  || bad "ceremony bucket wrong; got: $(printf '%s' "$o" | command grep -i ceremony)"
command grep -qE 'per-slice work +1 spans +0h30m +75\.0%.*spec' <<< "$o" \
  && ok "…and spec buckets as per-slice work (1800s = 75%)" \
  || bad "slice bucket wrong; got: $(printf '%s' "$o" | command grep -i 'per-slice')"
# ONE PAIRING: the two readers agree span for span, asserted rather than assumed
dc_paired=$("$RS/derive_cost.sh" --stage-totals "$wr" 2>/dev/null \
            | awk -F'\t' '$1=="paired"{printf "%s paired / %s kept / %s dropped", $2, $3, $4}')
precond "derive_cost --stage-totals answered with a paired row" test -n "$dc_paired"
command grep -qF "$dc_paired" <<< "$o" \
  && ok "the report's pairing line IS derive_cost's own reading, verbatim ($dc_paired)" \
  || bad "the two readers disagree about the pairing: derive_cost says '$dc_paired'"
# a stage the scope column does not declare is BUCKETED, never dropped — a
# silently dropped span would make the ceremony share look smaller than it is
wr2=$(mk_topic)
state_append "$wr2" ledger ferry "v=1 t=1000 event=spawn slice=01 stage=notastage mode=cold" >/dev/null
state_append "$wr2" ledger ferry "v=1 t=1600 event=record slice=01 stage=notastage" >/dev/null
o2=$(ro_run "$wr2")
command grep -qE 'UNDECLARED stage scope +1 spans.*notastage' <<< "$o2" \
  && command grep -q 'stages.tsv owes it a row' <<< "$o2" \
  && ok "known-bad: a stage stages.tsv does not declare lands in its own bucket and is named" \
  || bad "an undeclared stage vanished from the split; got: $(printf '%s' "$o2" | command grep -iE 'undeclared|spans')"
# A THIRD scope value must PRINT, not vanish into the denominator. The first
# form of the printer walked a hand-listed `topic slice unknown`, so a stage
# declaring any other scope would have joined `tot` and printed nowhere: the
# percentages would not sum and a whole bucket would be invisible. This is the
# shape architecture §12's anchor ruling names — enumerating shapes is precisely
# what failed — so the arm drives the SHIPPED script against a stages.tsv
# carrying a scope this tree does not use today.
wr5=$(mk_topic)
state_append "$wr5" ledger ferry "v=1 t=1000 event=spawn slice=01 stage=spec mode=cold" >/dev/null
state_append "$wr5" ledger ferry "v=1 t=1600 event=record slice=01 stage=spec" >/dev/null
state_append "$wr5" ledger ferry "v=1 t=2000 event=spawn slice=01 stage=sweep mode=cold" >/dev/null
state_append "$wr5" ledger ferry "v=1 t=2600 event=record slice=01 stage=sweep" >/dev/null
tree3=$(sc_tmpdir)/tree3; mkdir -p "$tree3/runtime-scripts/lib" "$tree3/config"
cp "$RS/derive_report.sh" "$RS/derive_cost.sh" "$tree3/runtime-scripts/"; cp "$RS/lib/report_routing.sh" "$tree3/runtime-scripts/lib/"
cp "$RS/lib/state.sh" "$RS/lib/config.sh" "$tree3/runtime-scripts/lib/"
{ printf 'spec\tslice\n'; printf 'sweep\tbatch\n'; } > "$tree3/config/stages.tsv"
o5=$(ro_sec "$(bash "$tree3/runtime-scripts/derive_report.sh" "$wr5" 2>&1)")
command grep -qE 'scope=batch +1 spans.*sweep' <<< "$o5" \
  && ok "known-bad: a scope the printer was never told about prints under its own name" \
  || bad "a third scope value vanished from the split; got: $(printf '%s' "$o5" | command grep -E 'spans')"
pcts=$(printf '%s\n' "$o5" | command grep -oE '[0-9]+\.[0-9]%' | tr -d '%' | awk '{t+=$1} END{printf "%.0f", t}')
[ "$pcts" = "100" ] \
  && ok "…and the shares still sum to 100% — a dropped bucket is exactly what would break that" \
  || bad "the printed shares sum to ${pcts}%, so a bucket is in the denominator and not on the page"

# The SAME half-fix, at the two doors this file did not open. A fault notice was
# added above sections 2 and 3 in an earlier pass, and the lines UNDER it went on
# printing a closed set of zeros and a claim about "this topic" — a true notice
# over false readings, which is the exact shape this block already refused once
# for the fix-unit field. Both doors are pinned here rather than in 98-report,
# because they are the same rule as everything else in this file.
# EACH fault is asserted against the section that READS that surface, and only
# that one — the first form of this arm demanded silence from section 2 under a
# HANDOFF fault, where learnings is healthy and its zero distribution is the
# correct output. An assertion that does not match the behaviour it wants is a
# red that teaches the wrong lesson.
mk_corrupt() { # surface -> a workspace whose <surface> fails its checksum
  local w; w=$(mk_topic)
  state_append "$w" "$1" session "v=1 t=1 slice=01 stage=postcheck round=1 leak_class=novel record= text=a" >/dev/null
  printf 'corrupt\n' >> "$w/.runtime/state/$1"; printf '%s' "$w"
}
ol=$("$DR" "$(mk_corrupt learnings)" 2>/dev/null)
command grep -qF 'the learnings surface is FAULTED' <<< "$ol" \
  && ok "a corrupt learnings surface is NAMED in the section that reads it" \
  || bad "a corrupt learnings surface was read as an empty one"
command grep -qE '^  (conformance|precheck|gate|novel) +0$' <<< "$ol" \
  && bad "the closed leak-class set still printed as zeros under a learnings fault — a true notice over false readings" \
  || ok "…and the closed set is NOT printed as zeros it never read"
oh=$("$DR" "$(mk_corrupt handoff)" 2>/dev/null)
command grep -qF 'the handoff surface is FAULTED' <<< "$oh" \
  && ok "a corrupt handoff surface is NAMED in the section that reads it" \
  || bad "a corrupt handoff surface was read as an empty one"
# Matched on a fragment that lives on ONE line. The first form grepped a phrase
# the output wraps across two, which is a line-based grep failing on prose for
# the second time in this file — the card arm hit it too and answered by
# normalising whitespace. Here the cheaper answer is to match what a single line
# actually holds.
command grep -qF 'a surface this ratio reads is FAULTED' <<< "$oh" \
  && ok "…and the DRE says a surface is faulted rather than claiming the topic had no findings" \
  || bad "the DRE n/a still names the topic over an unreadable surface"
command grep -qE '^  conformance +0$' <<< "$oh" \
  && ok "…while section 2, whose surface is healthy, still prints its distribution (the fault is scoped to its reader)" \
  || bad "a handoff fault silenced the leak-class section, which does not read handoff"

# THE ONLY UNBOUNDED PRINT in a report pasted whole into a capped artifact. The
# per-slice budget permits 30 files per unit and 8 units per slice, so one slice
# can contribute 240 file-list lines to a closeout capped at 2000 — measured at
# 577 today. The per-unit list is display-capped, and the truncation is NAMED
# with the command that shows the rest, because a silently short list reads as a
# small change, which is the opposite of what it is.
wrc=$(mk_topic)
bigrepo=$(sc_tmpdir)/bigrepo; mkdir -p "$bigrepo"
( cd "$bigrepo" && git init -q && git config user.email t@t && git config user.name t \
  && for i in $(seq 1 20); do echo x > "f$i.txt"; done && git add -A \
  && git commit -qm "test: twenty files in one unit" )
bigsha=$(git -C "$bigrepo" rev-parse HEAD)
printf 'repo=%s\nbranch=master\ncommit.subject_regex=^x\n' "$bigrepo" > "$wrc/project.kv"
state_append "$wrc" progress session "v=1 t=1 slice=01 stage=fix round=1 cu=1 sha=$bigsha subject=test: twenty files in one unit" >/dev/null
oc=$(ro_run "$wrc")
nfiles=$(printf '%s\n' "$oc" | command grep -cE '^ +\+1 +-0 +f[0-9]+\.txt$')
[ "$nfiles" -eq 12 ] \
  && ok "a unit touching 20 files prints 12 and stops (a display cap, not a read cap)" \
  || bad "the per-unit file list printed $nfiles lines, so the only unbounded print is still unbounded"
command grep -qF '…and 8 more file(s) — git show --numstat --format=' <<< "$oc" \
  && ok "…and the truncation is NAMED with the command that shows the rest" \
  || bad "the list was cut silently, which reads as a smaller change than it was"

# THE USE-BOUNDARIES ARE PRINTED, not left in a source comment. Every other
# section of this report carries its "this decides nothing on its own" line where
# the reader meets it — the close-out author and the harvest read the OUTPUT —
# and this block's only such sentence lived in the source until an incentive
# reading of the mechanism asked what measuring does to the measured.
wrb=$(mk_topic)
ob=$(ro_run "$wrb")
command grep -qF 'the ceremony SHARE moves with slice count' <<< "$ob" \
  && ok "the block prints the share's own caveat (a ratio moves when either term does)" \
  || bad "the ceremony share prints with no statement that it is not comparable across widths"
command grep -qF 'nothing here scores a person or a decision' <<< "$ob" \
  && ok "…and says plainly that none of it scores a person or a decision" \
  || bad "the block prints numbers beside a verdict with no boundary on their use"

# READ-BUT-UNPAIRABLE is not ABSENT either, and the two printed identically
# until the loop was WALKED end to end on a hand-built fixture whose rows carried
# no stage field: sixteen rows, an honest zero, and no way to tell it from a
# workspace holding no ledger. The same distinction every other door here owes.
wr6=$(mk_topic)
state_append "$wr6" ledger ferry "v=1 t=1 event=ferry_start" >/dev/null
o6=$(ro_run "$wr6")
command grep -qF 'the ledger was READ and holds no spawn->record pair at all' <<< "$o6" \
  && ok "known-bad: a ledger read with nothing pairable in it says so, never printing as an absent one" \
  || bad "an unpairable ledger printed like a missing one: $(printf '%s' "$o6" | command grep -iA2 'cost split')"

# FAULT IS NOT ABSENT, and the split must not collapse the two. derive_cost
# already distinguishes a missing ledger from a corrupt one; the report forwards
# its refusal in its own words rather than re-describing the outcome, which is
# how the two came to read alike in the first form of this section.
wr3=$(mk_topic)
o3=$(ro_run "$wr3")
command grep -qF 'cost split  none (derive_cost.sh declined' <<< "$o3" \
  && command grep -qF 'not one readable ledger' <<< "$o3" \
  && ok "no ledger prints one none carrying derive_cost's OWN refusal, never a split of zeroes" \
  || bad "an absent ledger produced a cost split, or the reason was re-worded here: $(printf '%s' "$o3" | command grep -i 'cost split')"
# the corrupt-surface arm: a store FAULT must not read as an absent ledger
wr4=$(mk_topic)
state_append "$wr4" ledger ferry "v=1 t=1 event=spawn slice=01 stage=spec mode=cold" >/dev/null
printf 'corrupt\n' >> "$wr4/.runtime/state/ledger"      # breaks the checksum, not the file
o4=$(ro_run "$wr4")
command grep -qF 'store FAULT' <<< "$o4" \
  && ok "known-bad: a CORRUPT ledger says store FAULT, never 'no ledger' (fault is not absent)" \
  || bad "a checksum fault was reported as an absent ledger; got: $(printf '%s' "$o4" | command grep -i 'cost split')"

# An unreadable stages.tsv would bucket EVERY stage as undeclared and blame the
# table for being short — two very different readings printing the same sentence,
# which is the store's own "absent is not zero" doctrine one layer up. Driven by
# running the shipped script with WF_ROOT pointed at a tree that has no
# stages.tsv, so the arm exercises the real derivation rather than a copy.
wrx=$(mk_topic)
state_append "$wrx" ledger ferry "v=1 t=1000 event=spawn slice=01 stage=spec mode=cold" >/dev/null
state_append "$wrx" ledger ferry "v=1 t=1600 event=record slice=01 stage=spec" >/dev/null
faketree=$(sc_tmpdir)/tree; mkdir -p "$faketree/runtime-scripts/lib" "$faketree/config"
cp "$RS/derive_report.sh" "$RS/derive_cost.sh" "$faketree/runtime-scripts/"; cp "$RS/lib/report_routing.sh" "$faketree/runtime-scripts/lib/"
cp "$RS/lib/state.sh" "$RS/lib/config.sh" "$faketree/runtime-scripts/lib/"
ox=$(ro_sec "$(bash "$faketree/runtime-scripts/derive_report.sh" "$wrx" 2>&1)")
command grep -q 'stages.tsv declared NO scopes' <<< "$ox" \
  && ok "known-bad: an unreadable stages.tsv says so, instead of reading as a table short by every row" \
  || bad "a missing scope table was reported as undeclared stages; got: $(printf '%s' "$ox" | command grep -iE 'undeclared|scopes')"

echo "-- routing outcome: the review-driven units, and the three ways git can answer --"
# The one git read in the file, for the one fact no store surface holds: WHICH
# FILES a review-driven commit touched. All three answers are printed shapes —
# a silent row here would read as "the review changed nothing".
wr=$(mk_topic)
command grep -qF 'none (no progress row at stage=fix' <<< "$(ro_run "$wr")" \
  && ok "no fix row prints its own none (a review that drove no commit is a real reading)" \
  || bad "an empty fix set printed nothing at all"
# FAULT IS NOT ABSENT, at the door this section opens. The store's rule is that
# a checksum failure is propagated and never read as zero, and this door read
# `|| true` until an injection-round contract re-read caught it — so both the
# notice and the field's own reason are pinned, because a true notice above a
# false `none` still ships a false line.
wr=$(mk_topic)
state_append "$wr" progress session "v=1 t=1 slice=01 stage=fix round=1 cu=1 sha=dead subject=x" >/dev/null
printf 'corrupt\n' >> "$wr/.runtime/state/progress"
o=$(ro_run "$wr")
command grep -qF 'the progress surface is FAULTED' <<< "$o" \
  && command grep -qvF 'no review-driven commit unit on this topic' <<< "$o" \
  && ok "known-bad: a corrupt progress surface is NAMED and its none says unreadable, never 'no fix row'" \
  || bad "a faulted progress surface read as an empty one: $(printf '%s' "$o" | command grep -iE 'fault|none \(')"
gitrepo=$(sc_tmpdir)/repo; mkdir -p "$gitrepo"
( cd "$gitrepo" && git init -q && git config user.email t@t && git config user.name t \
  && printf 'a\nb\n' > f.txt && git add f.txt && git commit -qm "test: pin the arm" )
realsha=$(git -C "$gitrepo" rev-parse HEAD)
wr=$(mk_topic)
printf 'repo=%s\nbranch=master\ncommit.subject_regex=^x\n' "$gitrepo" > "$wr/project.kv"
state_append "$wr" progress session "v=1 t=1 slice=01 stage=fix round=1 cu=5 sha=$realsha subject=test: pin the arm" >/dev/null
o=$(ro_run "$wr")
command grep -qE '^ +\+2 +-0 +f\.txt' <<< "$o" \
  && ok "a resolvable fix SHA prints its numstat file list from the slice's BOUND checkout" \
  || bad "file list missing; got: $(printf '%s' "$o" | command grep -A2 'cu-5')"
command grep -qF 'slice 01 · cu-5' <<< "$o" \
  && ok "…under a row naming slice, unit and the subject the store already derived from git" \
  || bad "the unit row is malformed: $(printf '%s' "$o" | command grep 'cu-5')"
# known-bad A: a SHA that no longer resolves — the state every close-out reaches
# once its own consolidation proposal lands and the loose objects are collected
wr=$(mk_topic)
printf 'repo=%s\nbranch=master\ncommit.subject_regex=^x\n' "$gitrepo" > "$wr/project.kv"
state_append "$wr" progress session "v=1 t=1 slice=01 stage=fix round=1 cu=5 sha=0123456789abcdef0123456789abcdef01234567 subject=test: gone" >/dev/null
command grep -qF 'none (sha not found: 0123456789abcdef0123456789abcdef01234567)' <<< "$(ro_run "$wr")" \
  && ok "known-bad: an unresolvable SHA names itself and says the history moved" \
  || bad "a vanished SHA produced silence or an error"
# A row with NO subject field, which is where an ordering bug lived: the absence
# test compared the TRIMMED value against the raw row, so a row carrying trailing
# whitespace and no subject made the two differ and the ENTIRE record printed as
# a subject. The fixture carries the trailing space on purpose — without it the
# arm passes under the broken order too.
wr=$(mk_topic)
printf 'repo=%s\nbranch=master\ncommit.subject_regex=^x\n' "$gitrepo" > "$wr/project.kv"
state_append "$wr" progress session "v=1 t=1 slice=01 stage=fix round=1 cu=8 sha=$realsha " >/dev/null
command grep -qF '(no subject on the row)' <<< "$(ro_run "$wr")" \
  && ok "known-bad: a progress row with no subject= says so, instead of printing the whole record as one" \
  || bad "a subject-less row printed its own record as the subject"
# AND THE THIRD STATE, which fixtures never produced and the real stores did:
# `subject=` present with nothing after it. 26 rows across three of the six
# topics on disk are in it; 25 are at stage=impl and ONE at stage=fix, which is
# the only stage the block reads, and that SHA resolves to a commit whose
# subject is a full sentence — rows written before the writer derived subjects.
# A blank tail after the sha read as a unit with a short subject.
wr=$(mk_topic)
printf 'repo=%s\nbranch=master\ncommit.subject_regex=^x\n' "$gitrepo" > "$wr/project.kv"
state_append "$wr" progress session "v=1 t=1 slice=01 stage=fix round=1 cu=9 sha=$realsha subject=" >/dev/null
oe=$(ro_run "$wr")
command grep -qF 'subject= declared, not filled' <<< "$oe" \
  && ok "known-bad: an EMPTY subject= is named, not printed as a blank tail (present is not filled)" \
  || bad "an empty subject printed as nothing; got: $(printf '%s' "$oe" | command grep -F 'cu-9' | head -1)"
command grep -qF '(no subject on the row)' <<< "$oe" \
  && bad "an empty subject= reported as an ABSENT one — two states, one sentence" \
  || ok "…and it does NOT borrow the absent-field sentence"

# A BINARY file numstats as `-  -`, which rendered as the nonsense `+-  --`.
wr=$(mk_topic)
binrepo=$(sc_tmpdir)/binrepo; mkdir -p "$binrepo"
( cd "$binrepo" && git init -q && git config user.email t@t && git config user.name t \
  && printf 'a\000b\000c\n' > blob.bin && git add blob.bin && git commit -qm "test: a binary unit" )
binsha=$(git -C "$binrepo" rev-parse HEAD)
printf 'repo=%s\nbranch=master\ncommit.subject_regex=^x\n' "$binrepo" > "$wr/project.kv"
state_append "$wr" progress session "v=1 t=1 slice=01 stage=fix round=1 cu=9 sha=$binsha subject=test: a binary unit" >/dev/null
o=$(ro_run "$wr")
command grep -qE '^ +binary +blob\.bin$' <<< "$o" \
  && ok "a binary file reads 'binary', not the nonsense a numstat dash renders as" \
  || bad "binary numstat rendered wrong; got: $(printf '%s' "$o" | command grep -A1 'cu-9' | tail -1)"

# known-bad C: a commit git resolves and still says nothing about. `show
# --numstat` prints an EMPTY file list for a merge and for an empty commit, so
# the success path had a silent branch of its own — the exact outcome the two
# known-bads above exist to prevent, reached through the door marked fine.
wr=$(mk_topic)
printf 'repo=%s\nbranch=master\ncommit.subject_regex=^x\n' "$gitrepo" > "$wr/project.kv"
( cd "$gitrepo" && git commit -q --allow-empty -m "test: an empty commit" )
emptysha=$(git -C "$gitrepo" rev-parse HEAD)
state_append "$wr" progress session "v=1 t=1 slice=01 stage=fix round=1 cu=7 sha=$emptysha subject=test: an empty commit" >/dev/null
command grep -qF 'none (no file list:' <<< "$(ro_run "$wr")" \
  && ok "known-bad: a resolvable commit with NO file list says so (a merge or an empty commit)" \
  || bad "an empty file list printed nothing at all — the success path has a silent branch"

# A FAULTED slice index is not an unreadable repo, and the difference is whose
# diagnosis reaches the reader. `binding_kind` refuses a corrupt slices surface
# with rc 3 and a named FAULT that says "never read as the code default"; this
# block sent that to /dev/null and substituted its own vaguer sentence — the
# same re-wording it forbids itself for derive_cost's refusal, committed twice.
# Found by a cross-reference sweep (review-standards §9 C5) of a pattern retired
# in one file and still live in another this code depends on.
wrbind=$(mk_topic)
printf 'repo=/tmp\nbranch=x\ncommit.subject_regex=^x\n' > "$wrbind/project.kv"
state_set_slices() { printf 'id=01 status=done risk=low repo=doc title=x\n'; }
state_set_slices > "$wrbind/.runtime/state/slices"   # header-less on purpose: unreadable
state_append "$wrbind" progress session "v=1 t=1 slice=01 stage=fix round=1 cu=1 sha=dead subject=x" >/dev/null
obind=$(ro_run "$wrbind")
command grep -qF 'the slice binding could not be resolved' <<< "$obind" \
  && command grep -qF 'never read as the code default' <<< "$obind" \
  && ok "known-bad: a faulted slice index forwards the BINDING's own words, not this block's paraphrase" \
  || bad "the binding fault was re-worded or swallowed: $(printf '%s' "$obind" | command grep -A1 'cu-1')"

# known-bad B: the repo itself unreadable (moved, or never a checkout)
wr=$(mk_topic)
printf 'repo=%s\nbranch=master\ncommit.subject_regex=^x\n' "$(sc_tmpdir)/notarepo" > "$wr/project.kv"
state_append "$wr" progress session "v=1 t=1 slice=01 stage=fix round=1 cu=5 sha=$realsha subject=test: nowhere" >/dev/null
command grep -qF 'none (repo unreadable:' <<< "$(ro_run "$wr")" \
  && ok "known-bad: an unreadable checkout is named and distinguished from a missing commit" \
  || bad "an unreadable repo was silent, or read as a missing SHA"

check_done
