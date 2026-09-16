#!/usr/bin/env bash
# derive_report.sh — topic governance summary, DERIVED not registered
# (the deletion side of governance gets an instrument of its own).
#
# Everything this prints is derived from inputs that already exist. The full
# list, grouped by the section that reads it — §1 the gates surface (every
# PASS/FAIL attestation `_gates_record` ever appended); §2 the learnings
# surface and the postcheck review files; §3 the handoff surface; §4
# `<ws>/../plan.md`, `<ws>/project.kv`, the ledger (through `derive_cost.sh`),
# `config/stages.tsv`, the progress surface, the slices surface (through
# `binding_repo`) and git; §5 `self-check/validation-debt.md` and, for the
# mention corpus alone, the audit, observations, rulings and ledger surfaces
# plus every `<ws>/slices/*/*.md` and `<ws>/closeout.md`.
# THIS LIST IS THE SAME ENUMERATION AS THE SECTION LIST BELOW AND WENT SHORT
# THE SAME WAY: it named neither the slices surface — read by §4 through
# `binding_repo`, added by the commit that added §4 — nor the surfaces §5 reads
# to build its mention corpus, nor the artifact texts beside them; and it
# claimed to be in read order while listing two entries out of it. Grouped by
# section, the edit that adds a read and the edit that declares it are one line
# apart instead of forty. No new state, no registration: the same
# design gene as owed.sh's single derivation called from three doors. Read-only;
# output is pasted by the close-out author into closeout.md (card duty). The
# list is kept because a reader deciding whether this can run on an archived
# tree needs it — and git is the one entry that answers differently there,
# which boundary (d) is about.
#
# FIVE sections, and this list is the enumeration that goes short: it read
# "Three sections" while the file printed four, having never gained the reviewer
# coverage section added beneath it. An enumeration of a file's own output, kept
# in that file, is worth exactly the discipline of extending it in the same
# commit as the output.
#   1. gate firing history   — FAIL count per gate (a real catch), and which
#      gates caught nothing on this topic. This is a reading of THIS topic,
#      never a retirement feed: a zero here is identical for a dead gate and
#      for a working floor, so it decides nothing on its own (boundary (a)).
#   2. leak_class distribution — postcheck findings by class (the workflow's
#      DRE counterpart; data was always being stored, just never read)
#   3. reviewer coverage — what each review stage CAUGHT, and the precheck
#      defect-removal efficiency the leak counts of section 2 are the other
#      half of. Aggregate only; the ferry reads these fields per round.
#   4. routing outcome — the lane this topic was routed into, printed beside
#      what the run cost: the verdict verbatim from its two homes, the
#      topic-level ceremony against the per-slice work, and the commit units a
#      review drove. The one section that is a SNAPSHOT rather than a
#      derivation (boundary (d)).
#   5. open validation-debt rows — the WORKLIST the harvest judges, one line
#      per row and no ranking. `mention` is a proxy for `work` that fails in
#      both directions (a firing writes gate names, never row ids; a paste
#      names every open row), so bucketing rows by it produced a verdict-shaped
#      output whose silent bucket was anti-correlated with reality. The count
#      rides each row as a pointer into prose and settles nothing; the corpus
#      filter below keeps a re-run from counting its own previous paste.
#
# HONEST BOUNDARIES (per the tree's doctrine, in the header where the check
# reads them): (a) FAIL counts measure DETECTED catches, not prevented
# defects — a gate that never fired because authors learned to comply is
# working, not dead. A window counting zero FAILs across topics was tried for
# three decision points and retired: it cannot separate the two
# readings, and the separable half (can the gate fire at all?) is floored in
# the suite instead, one red-proof per gate function. (b) The leak_class
# distribution is counted from the LEARNINGS
# SURFACE alone, which §9 C9 names as the authority; the review files' tags are
# free-form markdown (six written forms measured) and ride as a cross-check
# line, never as an addend. The whole closed set prints, zeros included. (c) section 5 ranks
# NOTHING. It used to bucket rows by whether anyone mentioned them, which is a
# proxy for `work` that fails both ways — the rows with live firing evidence are
# exactly the ones it scored silent, measured four for four on one topic — and a
# two-bucket output reads as a verdict however its header is labelled. It is now
# a worklist: every open row, one shape, with the mention count annotated as the
# pointer it is. The judgment it used to imply is the harvest's duty, which the
# harvest owes for every row regardless. (d) Section 4 is the only part of this
# report that cannot be re-derived later, and the only part that reads git.
# Sections 1-3 and 5 read append-only store surfaces: run this on an archived
# tree a year from now and it prints what it printed then. Section 4 asks git
# which files a review-driven commit touched — the one fact no surface holds,
# since the store records cu -> SHA and the subject and nothing more — and the
# close-out that pastes this report is the same close-out that PROPOSES history
# consolidation (`operations.md` §8). After that lands and the loose objects go,
# those SHAs resolve to nothing and the rows read `none (sha not found: ...)`.
# That later empty reading is the rewrite, never a defect; the block is a
# snapshot taken while the history still says what it said. Its LENGTH grows
# with fix units, so with slice count: every other section is bounded by a closed
# set, a stage list or a capped table, and this one is O(slices). The per-unit
# file list is display-capped and says when it truncates; the block as a whole is
# not bounded, which is registered rather than engineered for — the measured
# paste is 577 of 2000 lines and no topic has approached the ceiling. A topic
# that does will show it as a cap refusal at close-out emit, with this note as
# the explanation and a compact form as the obvious knob.
#
# Usage: derive_report.sh <workspace>
# Exit: 0 report produced · 2 usage/store fault.
set -uo pipefail
export LC_ALL=C
DR_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
. "$DR_DIR/lib/state.sh"
. "$DR_DIR/lib/config.sh"   # project_get / binding_repo — section 4 only

# ONE formatter, called by every door that opens a surface, because the store's
# rule is tree-wide and this file applied it at ONE of its seven doors:
# "a checksum/parse failure is a fault — readers must propagate it (distinct
# rc), never read it as zero/absent" (`design/state-and-liveness.md` §1). Six
# doors here read `|| true`, which is that sentence's exact prohibition, and one
# of the six was added by the routing section. A faulted surface now NAMES
# itself inside the section that lost its data and the section prints on: the
# gates surface keeps its stronger refusal above, because a governance report
# whose gate history is corrupt has no subject, while a report missing one
# section still tells the truth about the rest.
# THE THREE CALL SITES BELOW READ `$?` IMMEDIATELY AFTER AN ASSIGNMENT, which
# means nothing may be inserted between the two — not a `printf`, not a `[`, not
# a comment-with-a-command. The status is the command substitution's, and the
# next command overwrites it. Written down because the edit that breaks it looks
# harmless and the failure is silent: a faulted surface would go back to reading
# as an empty one, which is the defect those three lines exist to prevent.
_dr_fault() { # surface -> the notice, in the section that lost the data
  printf '  !! the %s surface is FAULTED (checksum/parse) — this section is reading NOTHING, which is not the same as reading zero\n' "$1"
}

WS=${1:?usage: derive_report.sh <workspace>}
[ -d "$WS/.runtime/state" ] || { echo "refuse: no store under $WS" >&2; exit 2; }
WF_ROOT=$(cd "$DR_DIR/.." && pwd)
# ONE resolution of the topic directory, because there were two and they
# DISAGREE. `$WS/../plan.md` handed to `-f` is resolved by the kernel, which
# follows a symlinked workspace through to its real parent; `cd "$WS/.." && pwd`
# is resolved by the shell, which is logical and answers with the symlink's
# parent instead. Measured on a symlinked workspace: the report titled itself
# after one topic and the routing block read the OTHER topic's plan, with
# nothing in the output saying so. -P makes both physical, so the title and the
# inputs name the same directory. Same gene as everything else here: a rule
# stated twice in two languages is a rule waiting to disagree.
TOPIC_DIR=$(cd -P "$WS/.." && pwd -P) || { echo "refuse: cannot resolve $WS/.." >&2; exit 2; }

echo "# governance report — $(basename "$TOPIC_DIR") ($(date '+%F %T'))"

# ---- 1. gate firing history -------------------------------------------------
gates_body=$(state_get "$WS" gates 2>/dev/null); gates_rc=$?
if [ "$gates_rc" -eq 3 ]; then
  echo "gates surface FAULT (checksum/parse) — report refuses to read it" >&2; exit 2
fi
if [ "$gates_rc" -ne 0 ] || [ -z "$gates_body" ]; then
  echo "## gate firing: INPUT EMPTY — no gates surface in this workspace"
  echo "(an absent surface is not 'every gate zero-fired'; refusing to read it as one)"
else
  printf '%s\n' "$gates_body" | awk '
    / gate=/ { g=""; r=""
      for (i=1;i<=NF;i++) { if ($i ~ /^gate=/) g=substr($i,6)
                             if ($i ~ /^result=/) r=substr($i,8) }
      if (g != "") { tot[g]++; if (r=="FAIL") fail[g]++ } }
    END { for (g in tot) printf "%s %d %d\n", g, tot[g], fail[g]+0 }' \
    | sort | while read -r g t f; do
        if [ "$f" -gt 0 ]; then
          printf '  %-18s %3d attests  %3d FAIL (real catches)\n' "$g" "$t" "$f"
        else
          printf '  %-18s %3d attests    0 FAIL — caught nothing HERE (a floor reads the same)\n' "$g" "$t"
        fi
      done
  n_att=$(printf '%s\n' "$gates_body" | grep -c ' gate=' || true)
  echo "  ($n_att attestations total)"
  # PER-SLICE PROJECT-GATE COVERAGE, and the reason it is a section rather than
  # a maintainer's grep: the totals above cannot show an ASYMMETRY. Measured
  # on one topic — one slice held ZERO build/lint/test rows while every other
  # slice of the same topic held all three, and the whole-topic tally read
  # `build 9 · lint 8 · test 8`, i.e. healthy. A reviewer found it by hand and
  # tagged the first `leak_class=gate` row this workflow has ever produced; the
  # instrument that tag names does not exist yet. This is not that
  # instrument — it refuses nothing and it cannot read a spec's gate plan, so it
  # cannot know which gates a slice OWED. It prints what each slice HAS, side by
  # side, which is the reading that made the asymmetry visible once someone
  # looked. `-` means no row of that gate for that slice: a slice that never ran
  # it and a slice whose adapter does not declare it read alike here, and the
  # named SKIP rows the gate itself writes are what tell them apart.
  echo "## project gates per slice (asymmetry is the reading; this counts rows, never obligations)"
  printf '%s\n' "$gates_body" \
    | awk '
        / gate=(build|lint|test|acceptance) / {
          sl=""; g=""; r=""
          for (i=1;i<=NF;i++) { if ($i ~ /^slice=/)  sl=substr($i,7)
                                 if ($i ~ /^gate=/)   g=substr($i,6)
                                 if ($i ~ /^result=/) r=substr($i,8) }
          if (sl=="" || g=="") next
          slices[sl]=1
          if (r=="PASS") pass[sl,g]++
          else if (r=="FAIL") fail[sl,g]++
          else skip[sl,g]++ }
        END {
          n=0; for (sl in slices) { ord[++n]=sl }
          if (n==0) { print "  (no project-gate rows on this surface)"; exit }
          for (i=1;i<n;i++) for (j=i+1;j<=n;j++) if (ord[i]>ord[j]) { t=ord[i]; ord[i]=ord[j]; ord[j]=t }
          printf "  slice   %-14s %-14s %-14s %-14s\n", "build", "lint", "test", "acceptance"
          split("build lint test acceptance", G, " ")
          for (i=1;i<=n;i++) { sl=ord[i]; line=sprintf("  %-7s", sl)
            for (k=1;k<=4;k++) { g=G[k]
              p=pass[sl,g]+0; f=fail[sl,g]+0; s=skip[sl,g]+0
              if (p+f+s==0) cell="-"
              else { cell=""
                     if (p) cell=cell sprintf("%dP", p)
                     if (f) cell=cell (cell!="" ? "/" : "") sprintf("%dF", f)
                     if (s) cell=cell (cell!="" ? "/" : "") sprintf("%dSKIP", s) }
              line=line sprintf(" %-14s", cell) }
            print line } }'
fi

# ---- 2. leak_class distribution ----------------------------------------------
# ONE source, and it is the one review-standards §9 C9 names: "the class is
# recorded on the learnings surface, one `record.sh learn` per finding ... THE
# SURFACE, NOT THE REVIEW FILE, is what the learning loop (§14) reads". The
# review file's tag is free-form markdown and cannot be counted: measured over
# four topics' postcheck files, the same tag appears as `leak_class: X.**`,
# `leak_class: **X**`, `leak_class **X**`, `leak_class**: X`, ``leak_class: X` ``
# and once as a table cell — six written forms, so every regex over it counts a
# different number. The earlier form of this section UNIONED the two streams
# while this file's own boundary (b) said the surface was read "instead", so a
# finding recorded in both homes — which `_emit_leak_evidence` exists to force —
# counted TWICE. Measured on one topic: 41 file tags + 40 surface rows printed
# over ~40 real findings.
echo "## leak_class distribution (postcheck findings; DRE counterpart)"
# The closed set is stated ONCE in this file and both the matcher and the
# printer derive from it — a second statement here is a second thing to drift,
# which is exactly what `52-vocab` exists to catch across the five files that
# each state it once.
LC_SET="conformance precheck gate novel"
lc_alt=$(printf '%s|' $LC_SET); lc_alt=${lc_alt%|}
learn_bad=0
learn=$(state_get "$WS" learnings 2>/dev/null); [ $? -eq 3 ] && { _dr_fault learnings; learn=""; learn_bad=1; }
lc_counts=$(printf '%s\n' "$learn" \
  | command grep -oE "leak_class=($lc_alt)" 2>/dev/null \
  | cut -d= -f2 | sort | uniq -c || true)
# The whole closed set prints, zeros included. A class with no findings and a
# class nobody can produce read identically when the row is simply absent, and
# this tree has met that shape twice (a dead decisions status value, and
# `gate` — zero across four topics and 65 rows). An explicit 0 asks the question
# at every close-out instead of leaving it to a four-topic archive sweep.
# The zero list exists to ask "did this class really produce nothing?" of a
# surface that was READ. Over a faulted one the same zeros answer a question
# nobody put, which is the notice above being contradicted by the lines under
# it — the half-fix this file already refused once, for the fix-unit field.
if [ "$learn_bad" -eq 1 ]; then
  echo "  (no distribution: the surface above is unreadable, so every class is UNKNOWN here — printing the closed set as zeros would answer a question nothing asked)"
else
  for lc_k in $LC_SET; do
    lc_n=$(printf '%s\n' "$lc_counts" | awk -v k="$lc_k" '$2==k{print $1}')
    printf '  %-12s %d\n' "$lc_k" "${lc_n:-0}"
  done
fi
# `gate` alone gets a second line, grouped by the record its predicate would
# read (§9's required --record field). This IS the harvest's worklist: the
# maintainer promotes an instrument, and an instrument is a predicate over one
# record, so gate rows sharing a record are one candidate and not three. The
# line is silent at zero — the printer above already asks that question.
lc_gate_recs=$(printf '%s\n' "$learn" \
  | command grep -F 'leak_class=gate ' 2>/dev/null \
  | command grep -oE 'record=[A-Za-z_]+' | cut -d= -f2 | sort | uniq -c \
  | awk '{printf "%s%s×%s", (NR>1 ? ", " : ""), $2, $1} END{print ""}' || true)
if [ -n "$lc_gate_recs" ]; then
  printf '    gate by record: %s\n' "$lc_gate_recs"
fi
# The review files are a CROSS-CHECK, never an addend: a file tag with no
# surface row is a measured defect of its own, which is worth naming
# and is not worth adding up.
lc_files=$(command grep -rhoE 'leak_class' "$WS"/slices/*/postcheck.*.md 2>/dev/null | command grep -c . || true)
lc_rows=$(printf '%s\n' "$lc_counts" | awk '{s+=$1} END{print s+0}')
if [ "${lc_files:-0}" -gt 0 ] || [ "$lc_rows" -gt 0 ]; then
  printf '  (cross-check, not summed: %s surface rows against %s free-form mentions in the review files)\n' \
    "$lc_rows" "${lc_files:-0}"
fi

# ---- 3. reviewer coverage, the CATCH side of the leak counts above -------------
# Every emit records findings.substantive/wording beside its verdict, and the
# ferry reads those fields — per (slice, stage, round), for the severity-trend
# predicate that decides whether a review loop is converging. What nothing read
# was the AGGREGATE. Measured once by hand, quoted in an INDEX row
# and nowhere re-derived, which is the exact position two cost numbers were in
# when they went stale and the reason `derive_cost.sh` exists. So it is wired
# here rather than left as a figure someone remembers.
echo "## reviewer coverage — what each review stage CAUGHT (the counterpart to §2)"
hoff_bad=0
hoff=$(state_get "$WS" handoff 2>/dev/null); [ $? -eq 3 ] && { _dr_fault handoff; hoff=""; hoff_bad=1; }
printf '  %-13s %6s %12s %8s   %s\n' "stage" "emits" "substantive" "wording" "verdicts"
for rc_st in precheck postcheck split-check; do
  rc_rows=$(printf '%s\n' "$hoff" | command grep -E "(^| )stage=$rc_st( |$)" || true)
  rc_n=$(printf '%s\n' "$rc_rows" | command grep -c . || true)
  [ "${rc_n:-0}" -eq 0 ] && continue
  rc_s=$(printf '%s\n' "$rc_rows" | command grep -oE '(^| )findings\.substantive=[0-9]+' | cut -d= -f2 | awk '{n+=$1} END{print n+0}')
  rc_w=$(printf '%s\n' "$rc_rows" | command grep -oE '(^| )findings\.wording=[0-9]+' | cut -d= -f2 | awk '{n+=$1} END{print n+0}')
  rc_v=$(printf '%s\n' "$rc_rows" | command grep -oE '(^| )verdict=[A-Za-z_]+' | cut -d= -f2 \
         | sort | uniq -c | awk '{printf "%s%s %s", (NR>1 ? " / " : ""), $2, $1} END{print ""}')
  printf '  %-13s %6d %12d %8d   %s\n' "$rc_st" "$rc_n" "$rc_s" "$rc_w" "$rc_v"
done
# the split the predicate reads from round 2 (review-standards §1); an unfielded row predates the field and reads all-repeat, so it is counted apart
rc_r2=$(printf '%s\n' "$hoff" | command grep -E '(^| )stage=(precheck|postcheck|split-check)( |$)' | command grep -E '(^| )round=([2-9]|[1-9][0-9]+)( |$)' || true)
rc_r2n=$(printf '%s\n' "$rc_r2" | command grep -c . || true); rc_sp=$(printf '%s\n' "$rc_r2" | command grep -cE '(^| )findings\.substantive\.repeat=[0-9]+' || true)
rc_new=$(printf '%s\n' "$rc_r2" | command grep -oE '(^| )findings\.substantive\.new=[0-9]+' | cut -d= -f2 | awk '{n+=$1} END{print n+0}'); rc_rep=$(printf '%s\n' "$rc_r2" | command grep -oE '(^| )findings\.substantive\.repeat=[0-9]+' | cut -d= -f2 | awk '{n+=$1} END{print n+0}')
printf '  round>=2 review emits: %d · carrying the new/repeat split: %d (new %d · repeat %d) · unfielded: %d\n' "${rc_r2n:-0}" "${rc_sp:-0}" "$rc_new" "$rc_rep" $(( ${rc_r2n:-0} - ${rc_sp:-0} ))
# DRE is computable for PRECHECK ALONE, and the asymmetry is the point rather
# than an omission: a precheck escape is caught by postcheck and lands on the
# learnings surface as leak_class=precheck, so both terms exist. Nothing detects
# a postcheck escape — it reaches the delivered repository — so postcheck has no
# denominator and printing one would invent it.
rc_caught=$(printf '%s\n' "$hoff" | command grep -E '(^| )stage=precheck( |$)' \
            | command grep -oE '(^| )findings\.substantive=[0-9]+' | cut -d= -f2 | awk '{n+=$1} END{print n+0}')
rc_leaked=$(printf '%s\n' "$learn" | command grep -cE '(^| )leak_class=precheck( |$)' || true)
rc_tot=$(( ${rc_caught:-0} + ${rc_leaked:-0} ))
if [ "$rc_tot" -gt 0 ]; then
  printf '  precheck defect-removal efficiency: %d caught / %d leaked = %s%%   (n=%d%s)\n' \
    "$rc_caught" "$rc_leaked" \
    "$(awk -v c="$rc_caught" -v t="$rc_tot" 'BEGIN{printf "%.1f", 100*c/t}')" \
    "$rc_tot" "$( [ "$rc_tot" -lt 20 ] && printf ' · small-n' )"
  if [ "${rc_leaked:-0}" -eq 0 ]; then
    echo "    ZERO leaks is the reading to distrust first, and 'absent is not zero' is this store's"
    echo "    own doctrine: it means precheck caught everything OR nothing recorded what escaped."
    echo "    An archived topic reads exactly this at 13/0 = 100% because it predates the emit-time"
    echo "    door that forces a learnings row per finding. Check §2's row count before believing it."
  fi
  echo "    Two boundaries, printed because a bare percentage invites the wrong reaction."
  echo "    (1) UPPER BOUND: the leak term counts what POSTCHECK caught, so a defect that"
  echo "        escaped both reviews is invisible here and the true figure is lower."
  echo "    (2) Calibration: formal design and code inspections average ~85% DRE and the"
  echo "        all-methods US average is ~85%; >95% needs inspections AND static analysis"
  echo "        AND testing together (Capers Jones). At the benchmark is not below it."
  echo "    postcheck has NO computable DRE: nothing detects what escapes the last reviewer."
elif [ "$hoff_bad" -eq 1 ] || [ "$learn_bad" -eq 1 ]; then
  echo "  precheck defect-removal efficiency: n/a — a surface this ratio reads is FAULTED, so"
  echo "    neither term was obtained. This is not the topic having no findings; it is the"
  echo "    report being unable to count them."
else
  echo "  precheck defect-removal efficiency: n/a — no precheck findings and no precheck-class"
  echo "    leaks on this topic, so the ratio has no denominator (absent, not 100%)."
fi

# ---- 4. routing outcome — lib/report_routing.sh ------------------------------
# The one section that reads git and is a snapshot rather than a derivation
# (boundary (d)). Split out at this file's 800-line cap on the ferry-halves
# precedent; it reads WS, TOPIC_DIR, DR_DIR, WF_ROOT and _dr_fault from here,
# and 99-routing drives every branch of it.
. "$DR_DIR/lib/report_routing.sh"
report_routing_outcome

# ---- 5. open validation-debt rows (a worklist, not a ranking) ------------------------------------
echo "## open validation-debt rows — the harvest judges each, from the store"
echo "   (NOT a progress ranking, and deliberately so. 'Mentioned' is a PROXY for 'worked on'"
echo "    that fails in BOTH directions: a firing leaves gate=<name>, reason=<class>, a rendered"
echo "    excerpt path or a prompt header line and never a row id, so the rows with live evidence"
echo "    are the ones a mention-probe scores silent — measured, all four rows that fired on one"
echo "    topic; and a paste of any such listing names every open row at once. So this is a"
echo "    WORKLIST, not a verdict: every row below is open as of this run and owes the harvest a"
echo "    judgment against the gates/halt/prompt surfaces while the topic tree is still readable."
echo "    The prose-mention count rides each row as a POINTER — where someone talked about it —"
echo "    and settles nothing.)"
vd="${DR_VD_FILE:-$WF_ROOT/self-check/validation-debt.md}"
# DR_VD_FILE (env, named): 98-report drives §5's WANTED arm against a scratch
# table through it; unset, it is the workflow's own file. A test-only seam by
# admission — the alternative was grepping the awk out of this file, which
# would test a copy and not the code.
if [ ! -f "$vd" ]; then echo "  (no validation-debt.md — dev-time file absent)"; exit 0; fi
# open rows only: the payable table, which ends at `## standing` or `## closed`
# (explicit, never positional — a standing row is a guard whose firing would be
# a defect, and is excluded from the worklist and the WARN alike)
open_rows=$(awk '/^## (closed|standing)/{done=1} !done && /^\| VD-[0-9]+ \|/' "$vd")
[ -n "$open_rows" ] || echo "  (no open VD rows)"
# The mention corpus: every store record + every artifact text of this topic.
# _dr_strip_own_output makes the probe IDEMPOTENT. The close-out card duty is
# to paste this report into closeout.md, and closeout.md is in the corpus — so
# the paste IS a listing of every open row id, and any re-run over the same
# workspace scores all of them "mentioned". Measured on a live close-out: a
# post-paste re-run flipped all 24 no-mention rows to "mentioned (1)" while
# sections 1 and 2 stayed identical, their sources not including closeout.md.
# The filter drops only THIS probe's own emitted lines, by their exact shape,
# so a close-out that genuinely discusses a row in prose still counts — which
# excluding the file wholesale would have lost. What it cannot reach, stated
# because the boundary is the point: a report pasted with its lines reflowed,
# re-indented or quoted is no longer this shape and contaminates again.
_dr_strip_own_output() { command grep -vE '^[[:space:]]*(VD-[0-9]+[[:space:]]+open — judge from the store \(prose mentions this topic: [0-9]+, a pointer only\)|wanted — readings CLOSED rows pre-register.*|WANTED: .*)$'; }
# THE ONE PLACE THE NOTICE CANNOT GO, named rather than left looking like the
# other six: these four reads build the mention CORPUS inside a substitution, so
# a notice printed here would become corpus text and be counted as a mention. A
# fault here under-counts a number this section's own header calls "a pointer
# only" that "settles nothing" — so the loss is bounded and visible in the
# design, which is the trade being made on purpose.
corpus=$( { state_get "$WS" ledger 2>/dev/null || true
            state_get "$WS" audit 2>/dev/null || true
            state_get "$WS" observations 2>/dev/null || true
            state_get "$WS" rulings 2>/dev/null || true
            cat "$WS"/slices/*/*.md "$WS"/closeout.md 2>/dev/null || true
          } | _dr_strip_own_output | tr -cs 'A-Za-z0-9-' '\n')
printf '%s\n' "$open_rows" | while IFS= read -r row; do
  id=$(printf '%s' "$row" | awk -F'|' '{gsub(/[ |*]/,"",$2); print $2}')
  [ -n "$id" ] || continue
  hits=$(printf '%s\n' "$corpus" | grep -cxF "$id" || true)
  # One line per open row, one shape for every row: no buckets. A two-bucket
  # output reads as a verdict however the header is labelled, and its "silent"
  # bucket is anti-correlated with reality. The mention count is annotated as
  # what it is — a pointer into prose — and the judgment duty is the same for
  # every row, which is what the harvest owes anyway.
  printf '  %-6s open — judge from the store (prose mentions this topic: %d, a pointer only)\n' "$id" "$hits"
done

# CLOSED rows can pre-register readings they still want (§5 used to stop at the `##
# closed` heading, so the request sat in prose under a heading that means
# finished, and landed twice only because a pilot read closed rows on their own
# initiative). The convention: a closed row writes `WANTED: <reading>` inside
# one of its cells; the marker is extracted from the closed section ONLY — an
# open row IS the worklist and needs no marker. Non-blocking by design: this
# asks, it never warns and never ranks.
wanted=$(sed -n '/^## closed/,$p' "$vd" | command grep -oE 'WANTED: [^|]*' || true)
if [ -n "$wanted" ]; then
  echo "  wanted — readings CLOSED rows pre-register, asked here because nothing else asks:"
  printf '%s\n' "$wanted" | sed -e 's/^/    /' -e 's/[[:space:]]*$//'
fi
exit 0
