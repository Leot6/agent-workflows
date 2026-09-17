#!/usr/bin/env bash
# 52-vocab — a closed value set stated in more than one place must be ONE set.
# Extracted from 50-record when that file reached its own 1000-line cap (the
# `32-compose.sh` precedent: a coherent family moves out rather than the host
# shedding reasoning to fit). It belongs here on its own merits too — these
# sweeps read five files, only one of which is record.sh; they were only ever
# in 50-record because record.sh writes leak_class.
# A closed set stated in more than one place drifts. Each arm
# extracts from the SOURCE's own form and never by grepping for the expected
# list, and each carries a known-bad that widens or narrows one statement and
# asserts the drift is observable.
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/fixtures/lib.sh"
echo "-- leak_class is ONE closed set, and its FIVE statements agree --"
# The third instance of a shape this tree has already paid for twice: a closed
# vocabulary written down in more than one place, with nothing keeping the
# statements one set. The decisions status vocabulary was the first (a
# declared set larger than the writer's; 30-closure now refuses a declared value
# no writer can produce) and the claims type set was the second (60-gates).
# leak_class is the sharpest of the three, because one of its statements is a
# CONSUMER THAT DROPS SILENTLY: derive_report.sh tallies the governance report's
# distribution by grepping the literal alternation, so a fifth class added to
# record.sh would simply not appear — no error, a quietly short report, and that
# report is what an owner reads to decide which gates to retire.
# Extract from each source's OWN form, never by grepping for the expected list.
lc_authority() { sed -n 's/.*case "\$lc" in \([a-z|]*\)).*/\1/p' "$RS/session/record.sh" \
  | tr '|' '\n' | command grep -v '^$' | sort -u; }
# derive_report states the set ONCE, as LC_SET, and derives both its matcher
# and its printer from that — so this extractor reads the declaration itself,
# not a regex that happens to spell the list out. (Its earlier form read the
# alternation inside the matcher; when the section was rewritten to count the
# learnings surface alone, the matcher changed shape and this arm went red,
# which is the check doing its job on its own author.)
lc_report()    { sed -n 's/^LC_SET="\([a-z ]*\)".*/\1/p' "$RS/derive_report.sh" \
  | head -1 | tr ' ' '\n' | command grep -v '^$' | sort -u; }
lc_prompt()    { sed -n 's/.*--leak-class <\([a-z|]*\)>.*/\1/p' "$WF_ROOT/runtime-docs/templates/prompts/postcheck.cold.md" \
  | head -1 | tr '|' '\n' | command grep -v '^$' | sort -u; }
lc_prompt_warm() { sed -n 's/.*--leak-class <\([a-z|]*\)>.*/\1/p' "$WF_ROOT/runtime-docs/templates/prompts/postcheck.warm.md" \
  | head -1 | tr '|' '\n' | command grep -v '^$' | sort -u; }
lc_standard()  { awk '/\*\*`leak_class`\*\*/{f=1} f{print} f&&/counts \+ confidence/{exit}' \
  "$WF_ROOT/runtime-docs/review-standards.md" \
  | command grep -oE '`[a-z_]+`' | tr -d '`' | command grep -v '^leak_class$' | sort -u; }
a=$(lc_authority); r=$(lc_report); pc=$(lc_prompt); pw=$(lc_prompt_warm); st=$(lc_standard)
precond "record.sh states a leak_class set" test -n "$a"
precond "derive_report states one" test -n "$r"
precond "review-standards states one" test -n "$st"
if [ "$a" = "$r" ] && [ "$a" = "$pc" ] && [ "$a" = "$pw" ] && [ "$a" = "$st" ]; then
  ok "record.sh, derive_report, both postcheck prompts and review-standards name the same leak classes ($(printf '%s' "$a" | tr '\n' ' '))"
else
  bad "leak_class vocabulary drift — a closed set stated in five places must be one set."$'\n'"    record.sh (authority): $(printf '%s' "$a" | tr '\n' ' ')"$'\n'"    derive_report:         $(printf '%s' "$r" | tr '\n' ' ')"$'\n'"    postcheck.cold:        $(printf '%s' "$pc" | tr '\n' ' ')"$'\n'"    postcheck.warm:        $(printf '%s' "$pw" | tr '\n' ' ')"$'\n'"    review-standards:      $(printf '%s' "$st" | tr '\n' ' ')"
fi
# known-bad: a class the authority gains and the report does not must be visible.
drift=$(printf 'case "$lc" in precheck|conformance|gate|novel|invented) : ;;\n' \
  | sed -n 's/.*case "\$lc" in \([a-z|]*\)).*/\1/p' | tr '|' '\n' | command grep -v '^$' | sort -u)
[ "$drift" != "$a" ] \
  && ok "known-bad: an authority that gains a class reads as different from the report (drift is observable)" \
  || bad "known-bad: a widened authority compared EQUAL — the extractor is blind"

echo "-- the confidence vocabulary is ONE closed set across every place that teaches it --"
# The largest unpinned vocabulary in the tree: one authority (record.sh's own
# case) and FOURTEEN restatements — twelve stage prompts, the review template,
# and the volatile header compose.sh renders. The expensive direction is a
# NARROWED authority: every prompt would go on teaching a value the emit gate now
# refuses, and the session finds out at emit, having done the whole stage. That is
# a measured shape — an instruction unsatisfiable as written —
# with fourteen copies of the instruction.
# Extract by POSITION (what follows the word), never by grepping for the expected
# list: a check that looks for what it expects can only find the set missing.
conf_at() { sed -nE 's/.*confidence[ <]+([A-Z|]+).*/\1/p' "$1" | head -1; }
conf_auth=$(sed -n 's/.*case "\$confidence" in \([A-Z|]*\)).*/\1/p' "$RS/session/record.sh")
precond "record.sh states a confidence vocabulary" test -n "$conf_auth"
conf_bad=""; conf_n=0; conf_files=0
for f in "$RS/lib/compose.sh" "$WF_ROOT/runtime-docs/templates/review.md" \
         "$WF_ROOT"/runtime-docs/templates/prompts/*.md; do
  conf_files=$((conf_files + 1))
  v=$(conf_at "$f")
  if [ -z "$v" ]; then
    # An enumerated site that states NO vocabulary is a finding, not a skip:
    # under a floor, sites could drop out of the sweep one at a time and the
    # arm would keep agreeing with itself over a shrinking population.
    conf_bad="$conf_bad"$'\n'"    $(basename "$f"): enumerates no confidence vocabulary at all — the site silently left the sweep"
    continue
  fi
  conf_n=$((conf_n + 1))
  [ "$v" = "$conf_auth" ] || conf_bad="$conf_bad"$'\n'"    $(basename "$f"): $v"
done
# a vacuous pass is the failure this precondition exists for: if the extractor
# stops matching, the loop above sees nothing and the arm would agree with itself.
# The floor is EXACT, not "enough sites" — every enumerated file must have
# been read to a vocabulary.
[ "$conf_n" -eq "$conf_files" ] \
  && ok "the sweep reached every enumerated site ($conf_n of $conf_files — the extractor still matches, none dropped out)" \
  || bad "only $conf_n of $conf_files sites matched — the extractor broke or a file stopped stating the set, and the check below would be vacuous"
[ -z "$conf_bad" ] \
  && ok "all $conf_n places that teach a confidence value name the authority's set ($conf_auth)" \
  || bad "confidence vocabulary drift — the authority is '$conf_auth' and these sites disagree with it or left the sweep:$conf_bad"
# known-bad: a narrowed authority must read as different from what the prompts teach.
narrowed=$(printf 'case "$confidence" in HIGH|LOW) : ;;\n' | sed -n 's/.*case "\$confidence" in \([A-Z|]*\)).*/\1/p')
[ "$narrowed" != "$conf_auth" ] \
  && ok "known-bad: an authority that drops a value reads as different (drift is observable)" \
  || bad "known-bad: a narrowed authority compared EQUAL — the extractor is blind"

echo "-- refine.terminated_on is ONE closed set across the authority and every author prompt --"
# The same shape as confidence, one authority (record.sh's own case) and an
# instruction-shaped restatement in every author prompt's emit line — and a
# restatement a writer ACTS on is exactly the kind that owes an arm.
# Extract by position after the flag, never by grepping for the expected list;
# the site set is DERIVED from the prompts that carry `--refine-rounds`, so a new
# author template joins the sweep the day it lands.
rt_auth=$(sed -n 's/.*case "\$rterm" in \([a-z|]*\)).*/\1/p' "$RS/session/record.sh" | head -1)
precond "record.sh states a refine.terminated_on vocabulary" test -n "$rt_auth"
rt_bad=""; rt_n=0; rt_files=0
for f in "$WF_ROOT"/runtime-docs/templates/prompts/*.md; do
  command grep -q -- '--refine-rounds' "$f" || continue
  rt_files=$((rt_files + 1))
  v=$(sed -n 's/.*--refine-terminated-on <\([a-z|]*\)>.*/\1/p' "$f" | head -1)
  if [ -z "$v" ]; then rt_bad="$rt_bad"$'\n'"    $(basename "$f"): carries --refine-rounds but teaches no --refine-terminated-on vocabulary"; continue; fi
  rt_n=$((rt_n + 1))
  [ "$v" = "$rt_auth" ] || rt_bad="$rt_bad"$'\n'"    $(basename "$f"): $v"
done
[ "$rt_files" -ge 8 ] \
  && ok "the sweep enumerated the author prompts by their --refine-rounds line ($rt_files sites; a floor of 8, the templates that carry it today)" \
  || bad "only $rt_files prompt files carry --refine-rounds — the site derivation stopped matching, and the arm below is over a shrunken set"
[ -z "$rt_bad" ] && [ "$rt_n" -eq "$rt_files" ] \
  && ok "all $rt_n author prompts teach the authority's set ($rt_auth)" \
  || bad "refine.terminated_on vocabulary drift — the authority is '$rt_auth' and these sites disagree or left the sweep:$rt_bad"
rt_narrow=$(printf 'case "$rterm" in clean) : ;;\n' | sed -n 's/.*case "\$rterm" in \([a-z|]*\)).*/\1/p')
[ "$rt_narrow" != "$rt_auth" ] \
  && ok "known-bad: an authority that drops a value reads as different (drift is observable)" \
  || bad "known-bad: a narrowed refine.terminated_on authority compared EQUAL — the extractor is blind"

echo "-- the visual introduction's stage chips are ONE sequence with stages.tsv --"
# intro.html restates the stage vocabulary as a diagram — the closed-vocabulary
# criterion's INSTRUCTION shape: a page a newcomer reads first, teaching a flow
# that must not drift from the table that drives it. Extracted from the HTML's
# OWN form (the .st chips, in document order) and compared as a SEQUENCE with
# stages.tsv's data rows: a stage missing, extra, or reordered in either place
# reads as drift. grep -o, never sed s///p — the pipe puts many chips on one
# long line and a per-line substitution yields one per line.
iv_html() { /usr/bin/grep -oE 'class="st[^"]*">[a-z-]+' "$WF_ROOT/intro.html" | sed 's/.*>//'; }
iv_tsv()  { awk -F'\t' '/^#/{next} NF>=6 {print $1}' "$WF_ROOT/config/stages.tsv"; }
h=$(iv_html); t=$(iv_tsv)
precond "intro.html carries stage chips" test -n "$h"
precond "stages.tsv carries stage rows" test -n "$t"
if [ "$h" = "$t" ]; then
  ok "intro.html's diagram names stages.tsv's stages, in order ($(printf '%s' "$h" | tr '\n' ' '))"
else
  bad "stage vocabulary drift between intro.html and stages.tsv — the page a newcomer reads first must not teach a moved flow."$'\n'"    stages.tsv (authority): $(printf '%s' "$t" | tr '\n' ' ')"$'\n'"    intro.html chips:       $(printf '%s' "$h" | tr '\n' ' ')"
fi
# known-bad: a table that drops a stage must read as different from the page.
iv_drop=$(printf '%s\n' "$t" | command grep -v '^spec$')
[ "$iv_drop" != "$t" ] && [ -n "$iv_drop" ] \
  && ok "known-bad: a stages.tsv that dropped a stage reads as different from the page (drift is observable)" \
  || bad "known-bad: the dropped-stage fixture compared EQUAL — the extractor is blind"

check_done
