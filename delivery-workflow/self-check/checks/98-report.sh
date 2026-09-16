#!/usr/bin/env bash
# 98-report — derive_report.sh and derive_cost.sh derive what the surfaces
# actually hold, and the maintenance WARN fires only over cap. The file is
# organised as known-bad DIRECTIONS rather than a fixed count, because a
# counted list here has gone short twice: a FAIL record must count as a real
# catch; an ABSENT gates surface must print INPUT EMPTY (never "all gates
# zero-fired" — absent ≠ zero, the store's own doctrine); the WARN function
# must fire over cap and stay silent under it; the mention probe must survive
# its own pasted output without flipping a row; a 0/0 ratio must refuse to
# divide rather than answer 100%; a routing verdict must be carried and never
# parsed, with a fenced grammar example refused as one; a cost split must
# bucket by the DECLARED stage scope and drop nothing it cannot classify; and
# every way git can fail to answer must print its own named none. The WARN arm
# runs against the REAL function in check.sh (sourced, not copied — a guard
# re-typed here would prove nothing about the summary that ships).
#
# HONEST BOUNDARY: fixtures use synthetic surfaces; real-store quirks
# (rotation tails, multi-line bodies) are exercised only by the first live
# close-out paste — that firing is the row this check leaves to
# validation-debt.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/fixtures/lib.sh"
. "$RS/lib/state.sh"   # fixtures write THROUGH the store tools (valid headers)

DR="$RS/derive_report.sh"
precond "derive_report.sh exists and parses" bash -n "$DR"

mk_ws() { # -> workspace with a store dir
  local d; d=$(sc_tmpdir); mkdir -p "$d/.runtime/state"; echo "$d"
}

# --- good direction: FAILs counted, zero-FAIL gates named ---------------------
# Fixtures write THROUGH state_append so headers verify — hand-writing a
# surface body would fault at read (the store's own doctrine, and this
# check's first lesson).
ws=$(mk_ws)
state_append "$ws" gates gate "v=1 t=1 gate=claims result=FAIL sha=a detail=x" >/dev/null
state_append "$ws" gates gate "v=1 t=2 gate=claims result=PASS sha=a detail=x" >/dev/null
state_append "$ws" gates gate "v=1 t=3 gate=caps result=PASS sha=a detail=x" >/dev/null
out=$("$DR" "$ws" 2>&1)
printf '%s\n' "$out" | grep -q 'claims.*2 attests.*1 FAIL' \
  && ok "FAIL counted as a real catch (claims 2 attests / 1 FAIL)" \
  || bad "claims FAIL count wrong; got:$(printf '%s' "$out" | grep claims)"
printf '%s\n' "$out" | grep -q 'caps.*1 attests.*0 FAIL' \
  && ok "a gate that caught nothing on this topic is still counted and named" \
  || bad "caps zero-FAIL line missing; got:$(printf '%s' "$out" | grep caps)"
# ...and the line does NOT read as a retirement verdict. The removal window was
# retired 2026-08-31 because this zero is identical for a dead gate and a
# working floor; the label has to say so where the close-out author reads it.
printf '%s\n' "$out" | grep -q 'caps.*a floor reads the same' \
  && ok "the zero-FAIL line names its own ambiguity (never a removal feed)" \
  || bad "zero-FAIL line reads as a verdict; got:$(printf '%s' "$out" | grep caps)"

# --- known-bad A: absent gates surface must NOT read as zero-fired -------------
ws=$(mk_ws)
out=$("$DR" "$ws" 2>&1); rc=$?
printf '%s\n' "$out" | grep -q 'INPUT EMPTY' \
  && ok "known-bad: absent gates surface prints INPUT EMPTY (rc=$rc — report still produced)" \
  || bad "absent surface read as a verdict; got:$(printf '%s' "$out" | head -4)"

# --- known-bad B: WARN over/under cap, against the REAL function ---------------
# shellcheck disable=SC1091
. "$SC_ROOT/check.sh"   # guarded main; we only want maintenance_warns
w=$(maintenance_warns 999999 0)
printf '%s' "$w" | grep -q 'checks sum 999999s' \
  && ok "WARN fires over the suite cap (a 999999s checks sum > configured cap)" \
  || bad "over-cap WARN silent; got:'$w'"
w=$(maintenance_warns 1 0)
[ -z "$w" ] \
  && ok "no WARN under cap (1s sum, 0 vd rows — silent)" \
  || bad "under-cap WARN fired anyway; got:'$w'"
w=$(maintenance_warns 1 999999)
printf '%s' "$w" | grep -q 'validation-debt rows 999999' \
  && ok "WARN fires over the vd cap with the explicit count" \
  || bad "vd-cap WARN silent; got:'$w'"

# A STANDING row is not payable debt and the cap must not count it. Both
# readers of the payable table — this WARN and derive_report's worklist — stop
# at `## standing` EXPLICITLY rather than by position, so reordering the
# sections cannot silently re-include them. Counted here through the same awk
# the shipped readers use, over a file built for the purpose.
vdf=$(sc_tmpdir)/vd.md
{ printf '| id | a | b | c |\n|---|---|---|---|\n| VD-1 | x | y | z |\n| VD-2 | x | y | z |\n'
  printf '\n## standing (not payable debt)\n\n| id | a | b | c |\n|---|---|---|---|\n| VD-98 | x | y | z |\n'
  printf '\n## closed\n\n| id | a | b |\n|---|---|---|\n| VD-99 | x | y |\n'; } > "$vdf"
n=$(awk '/^## (closed|standing)/{done=1} !done && /^\| VD-[0-9]+ \|/' "$vdf" | command grep -c .)
[ "$n" -eq 2 ] \
  && ok "the payable count stops at ## standing: 2 counted, the standing and closed rows excluded" \
  || bad "payable count is $n, expected 2 — a standing or closed row is being counted as debt"
# known-bad: the OLD positional reading (stop at ## closed only) must differ, or
# the change is decorative and a standing row silently rides the cap again.
nold=$(awk '/^## closed/{done=1} !done && /^\| VD-[0-9]+ \|/' "$vdf" | command grep -c .)
[ "$nold" -eq 3 ] && [ "$nold" -ne "$n" ] \
  && ok "known-bad: stopping at ## closed alone counts the standing row (3) — the explicit heading is load-bearing" \
  || bad "the two readings agree ($nold vs $n) — the ## standing stop is doing nothing"
# The parallel gate's floor is the slowest single check, and the cap on it is
# the instrument defaults.kv's own notes kept naming: a regression attributable
# to one file's scenarios, not to a sum. Third quantity, both directions.
w=$(maintenance_warns "" 0 999999 drillX)
printf '%s' "$w" | grep -q 'slowest check drillX 999999s' \
  && ok "WARN fires over the check cap, naming the straggler (drillX 999999s)" \
  || bad "check-cap WARN silent or anonymous; got:'$w'"
w=$(maintenance_warns "" 0 1 drillX)
[ -z "$w" ] \
  && ok "no WARN for a 1s slowest check (and an unmeasured sum compares against nothing)" \
  || bad "under-cap check WARN fired, or the empty sum was compared; got:'$w'"
w=$(maintenance_warns "" 0 "" drillX)
[ -z "$w" ] \
  && ok "an unmeasured SLOWEST compares against nothing too (the same 'not measured' contract the sum has)" \
  || bad "an empty slowest-secs was compared anyway; got:'$w'"
# THE MODE GATING, which nothing covered and which is why the defect lived.
# Both time caps are calibrated on the -j12 schedule; serially a check costs
# ~2x and the sum ~50% more. suite_cap always knew that and check_cap did not,
# so a serial run fired on healthy checks — measured on one commit in both
# modes, `record` 18s parallel / 44s serial. Every arm above drives
# maintenance_warns as a pure function with explicit arguments, so none of them
# could see what the RUNNER passes. These read the call site's own source.
echo "-- the time caps are compared only against the schedule they were calibrated on --"
# Both caps are calibrated on -j12 AND on a quiet box, so both terms are one
# question. Driven as a PREDICATE in every direction: a behavioural test would
# have to arrange a real loadavg, which is a fixture measuring the machine.
caps_comparable 12 5   && ok "the gate's own schedule on a quiet box COMPARES (jobs 12, load 5)" \
                       || bad "the calibrated schedule was suppressed"
caps_comparable 12 13  && bad "a loaded run compared its seconds against a quiet-box cap (jobs 12, load 13)" \
                       || ok "a machine carrying more than the suite suppresses (jobs 12, load 13)"
caps_comparable 12 12  && bad "load == jobs compared; the boundary belongs to the suppressing side" \
                       || ok "load EQUAL to the job count already suppresses (the suite was given 12; 12 more is not its own cost)"
caps_comparable 1 0    && bad "a serial run compared a -j12 cap" \
                       || ok "serial suppresses whatever the load (jobs 1)"
caps_comparable 2 4    && bad "jobs 2 under load 4 compared" \
                       || ok "the two reasons compose — fewer jobs than load suppresses too (jobs 2, load 4)"

# Pinned on the CALLS, not on a line-range. This was a `sed` range anchored to
# the literal `if [ "$JOBS" -gt 1 ]; then`, and the moment that condition grew a
# second term the range matched a DIFFERENT `if` earlier in the file (the mode
# banner) and reported all three invariants broken while the call site was fine.
# A window is not a construct: assert the arguments and the notes themselves.
gate_call=$(command grep -nE 'maintenance_warns |NOTE: (serial|loaded) run' "$SC_ROOT/check.sh")
precond "the maintenance call sites were extracted from check.sh" test -n "$gate_call"
[ "$(printf '%s\n' "$gate_call" | command grep -c 'maintenance_warns "\$SUM_SECS" "" "\$MAX_SECS" "\$MAX_NAME"')" = 1 ] \
  && ok "exactly ONE call passes BOTH time quantities (the comparable schedule: -j>1 on a quiet box)" \
  || bad "the comparing call is not unique: $(printf '%s' "$gate_call" | command grep 'maintenance_warns' | tr '\n' ' ')"
[ "$(printf '%s\n' "$gate_call" | command grep -c 'maintenance_warns "" "" "" ""')" = 1 ] \
  && ok "exactly ONE call passes NEITHER (one suppression path, so a new reason cannot grow a silent branch)" \
  || bad "the suppressing call is not unique: $(printf '%s' "$gate_call" | command grep 'maintenance_warns' | tr '\n' ' ')"
# and EVERY reason the suppression can fire for says so — absent is not zero
for reason in serial loaded; do
  printf '%s\n' "$gate_call" | command grep -q "NOTE: $reason run" \
    && ok "a suppressed comparison SAYS so for the $reason case (never silence, which reads as a pass)" \
    || bad "the $reason suppression is silent — absent is not zero, and this is the one place it was"
done
# THE DEFAULT SCHEDULE IS THE CALIBRATED ONE. By owner ruling: a bare
# `check.sh` is the gate, not the diagnosis form. Pinned in two directions
# because a silent revert to 1 would restore the exact trap it closed — every
# bare run producing per-check seconds no cap in the tree is comparable
# against, while still printing WARNs about them.
[ "${_SC_DEFAULT_JOBS:-1}" -gt 1 ] \
  && ok "a bare check.sh runs the GATE, not the diagnosis form (default --jobs ${_SC_DEFAULT_JOBS})" \
  || bad "the default job count is ${_SC_DEFAULT_JOBS:-unset} — a bare run is serial again, and its seconds compare against nothing"
capnote=$(sed -n '/^# The floor: the slowest single check under -j/,/^maintenance\.check_cap=/p' "$WF_ROOT/config/defaults.kv")
precond "check_cap's calibration note was extracted" test -n "$capnote"
printf '%s\n' "$capnote" | command grep -qF -- "-j${_SC_DEFAULT_JOBS}" \
  && ok "…and it is the SAME number check_cap says it was calibrated on (-j${_SC_DEFAULT_JOBS}) — the two cannot drift apart silently" \
  || bad "the default is ${_SC_DEFAULT_JOBS} but check_cap's note calibrates on a different schedule: $(printf '%s' "$capnote" | command grep -o -- '-j[0-9]*' | sort -u | tr '\n' ' ')"

# A green needs a denominator, PER COLLECTION SOURCE: emptying checks/ left
# the drills to carry a green "11 passed" (measured, trial tree), and emptying
# both read green at "0 passed, 0 failed". Each direction against the REAL
# function in check.sh, sourced above; the wiring in main is exercised by
# every run's summary counts. Scoped runs filter AFTER collection, so a
# --only/--changed subset never trips this.
f=$(collection_floor 0 12); frc=$?
[ "$frc" -eq 1 ] && printf '%s' "$f" | command grep -q '^FAIL: the checks/ collection matched nothing' \
  && printf '%s' "$f" | command grep -q '12 drill' \
  && ok "an emptied checks/ is a FAIL that names the 12 drills which would have carried the green" \
  || bad "checks-empty: rc=$frc, got:'$f'"
f=$(collection_floor 21 0); frc=$?
[ "$frc" -eq 1 ] && printf '%s' "$f" | command grep -q '^FAIL: the drill collection matched nothing' \
  && ok "an emptied drill collection is a FAIL of its own (the scenarios never ran)" \
  || bad "drills-empty: rc=$frc, got:'$f'"
f=$(collection_floor 21 12); frc=$?
[ "$frc" -eq 0 ] && [ -z "$f" ] \
  && ok "a healthy collection is silent (21 checks, 12 drills — nothing to say)" \
  || bad "healthy collection spoke: rc=$frc, got:'$f'"

# A CHECK that asserts nothing is a pass about nothing — the per-check form
# of the collection floor. check_done (fixtures/lib.sh, sourced above) is the
# closing bracket every non-sweep check calls; three directions against the
# real function, including the SETUP-RIDE shape (a drill body entirely dead
# still counts the two shared setup assertions — measured on a neutered
# drill-budget before the _SC_SETUP_N seam existed). The probes run FIRST
# with the counters snapshotted, and the ok/bad verdicts are cast only AFTER
# the restore — ok/bad inside the probe region would have been wiped by the
# restore (measured on this very arm before it landed: a probe bad restored
# away reads as a green check).
_n=$_SC_N; _f=$_SC_FAILS; _b=${_SC_SETUP_N:-0}
_SC_N=0; _SC_FAILS=0; _SC_SETUP_N=0
cdo0=$(check_done); rc0=$?
_SC_N=2; _SC_FAILS=0; _SC_SETUP_N=2
cdor=$(check_done); rcr=$?
_SC_N=3; _SC_FAILS=0; _SC_SETUP_N=2
cdos=$(check_done); rcs=$?
_SC_N=$_n; _SC_FAILS=$_f; _SC_SETUP_N=$_b
[ "$rc0" -eq 1 ] && printf '%s\n' "$cdo0" | command grep -q 'asserted nothing of its own' \
  && printf '%s\n' "$cdo0" | command grep -q '(0 assertions, 0 failed)' \
  && ok "a check reporting zero assertions FAILS (rc 1, the empty verdict named)" \
  || bad "zero-assertion check_done: rc=$rc0, got:'$cdo0'"
[ "$rcr" -eq 1 ] && printf '%s\n' "$cdor" | command grep -q 'beyond 2 setup' \
  && ok "a body-dead drill riding its 2 setup assertions FAILS too (the setup-ride shape, measured before the seam)" \
  || bad "setup-ride check_done: rc=$rcr, got:'$cdor'"
[ "$rcs" -eq 0 ] && printf '%s\n' "$cdos" | command grep -q '(3 assertions, 0 failed)' \
  && ok "and one own assertion past the setup baseline closes green (3 assertions, 2 of them setup)" \
  || bad "healthy check_done: rc=$rcs, got:'$cdos'"

# --- leak_class counts ONE source, and prints the whole closed set ------------
# review-standards §9 C9: "the class is recorded on the learnings surface ... THE
# SURFACE, NOT THE REVIEW FILE, is what the learning loop reads". The earlier
# form unioned the two streams while this file's own boundary said the surface
# was read "instead", so a finding recorded in both homes — which
# _emit_leak_evidence exists to FORCE — counted twice. Measured on one real
# topic: 41 file tags + 40 surface rows printed over ~40 findings.
ws=$(mk_ws)
mkdir -p "$ws/slices/03"
printf 'leak_class: conformance\n' > "$ws/slices/03/postcheck.1.md"
state_append "$ws" learnings session "v=1 t=1 slice=03 leak_class=conformance text=x" >/dev/null
out=$("$DR" "$ws" 2>&1)
printf '%s\n' "$out" | command grep -qE '^  conformance +1$' \
  && ok "a finding tagged in BOTH homes counts ONCE (the surface is the authority)" \
  || bad "double count returned; got:$(printf '%s' "$out" | sed -n '/leak_class/,+6p')"
printf '%s\n' "$out" | command grep -qE 'cross-check.*1 surface rows against 1 ' \
  && ok "…and the review file rides as a named cross-check, never as an addend" \
  || bad "cross-check line wrong; got:$(printf '%s' "$out" | command grep cross-check)"
# The whole closed set prints, zeros included: an absent row and a zero row read
# identically, and this tree has met that shape twice — decisions' dead status
# vocabulary, and leak_class=gate itself (0 across four topics and 65 rows). An
# explicit 0 asks the question at every close-out instead of leaving it to an
# archive sweep nobody runs.
for lc in conformance precheck gate novel; do
  printf '%s\n' "$out" | command grep -qE "^  $lc +[0-9]+$" \
    || bad "the closed set is not fully printed: $lc missing"
done
printf '%s\n' "$out" | command grep -qE '^  gate +0$' \
  && ok "a class with no findings prints an explicit 0 (absent is not zero — gate is the live instance)" \
  || bad "zero-valued classes are omitted; got:$(printf '%s' "$out" | sed -n '/leak_class/,+6p')"
# known-bad: a tag in the review file with NO surface row must not be counted —
# that is a measured defect of its own, and the cross-check names it.
ws2=$(mk_ws); mkdir -p "$ws2/slices/03"
printf 'leak_class: novel\n' > "$ws2/slices/03/postcheck.1.md"
state_append "$ws2" learnings session "v=1 t=1 slice=03 note=no-class-here" >/dev/null
out2=$("$DR" "$ws2" 2>&1)
printf '%s\n' "$out2" | command grep -qE '^  novel +0$' \
  && printf '%s\n' "$out2" | command grep -qE 'cross-check.*0 surface rows against 1 ' \
  && ok "known-bad: a file tag with no surface row counts 0 and the divergence is printed" \
  || bad "file-only tag leaked into the count; got:$(printf '%s' "$out2" | sed -n '/leak_class/,+6p')"
# `gate` alone is grouped by the record its predicate would read, because THAT
# is the harvest's unit of work: an instrument is a predicate over one record,
# so three gate tags naming `progress` are one candidate, not three. The line
# is silent at zero, which is why the arm asserts both directions — a line that
# always prints would say nothing, and one that never prints would be the same
# defect as the zero-row omission two arms up.
command grep -q 'gate by record' <<< "$out" \
  && bad "the gate-by-record line prints with no gate rows — it should be silent at zero" \
  || ok "no gate rows: the by-record line stays silent (the closed-set 0 already asks the question)"
ws3=$(mk_ws); mkdir -p "$ws3/slices/03"
state_append "$ws3" learnings session "v=1 t=1 slice=03 leak_class=gate record=progress text=a" >/dev/null
state_append "$ws3" learnings session "v=1 t=2 slice=03 leak_class=gate record=progress text=b" >/dev/null
state_append "$ws3" learnings session "v=1 t=3 slice=03 leak_class=gate record=git text=c" >/dev/null
state_append "$ws3" learnings session "v=1 t=4 slice=03 leak_class=novel record= text=d" >/dev/null
out3=$("$DR" "$ws3" 2>&1)
printf '%s\n' "$out3" | command grep -qE '^  gate +3$' \
  && ok "gate rows still count in the closed-set line" \
  || bad "gate count wrong; got:$(printf '%s' "$out3" | sed -n '/leak_class/,+6p')"
gline=$(printf '%s\n' "$out3" | command grep 'gate by record')
printf '%s\n' "$gline" | command grep -qF 'progress×2' \
  && printf '%s\n' "$gline" | command grep -qF 'git×1' \
  && ok "…and group by record: two tags on one record are ONE candidate, not two (progress×2, git×1)" \
  || bad "gate-by-record grouping wrong; got: $gline"
command grep -q 'novel' <<< "$gline" \
  && bad "a non-gate row's empty record= leaked into the gate breakdown" \
  || ok "a non-gate row's EMPTY record= contributes nothing (the field is present on every row)"

# --- the mention probe is idempotent under its own paste ----------------------
# The close-out card duty pastes this report into closeout.md, and closeout.md
# is in the probe's corpus — so without the filter the paste is a listing of
# every open row id and a re-run scores all of them "mentioned". Measured live
# before the fix: 24 no-mention rows all flipped. Both directions here, plus
# the arm that keeps the filter surgical: a genuine PROSE mention in the same
# file must still count, or the fix would have thrown away the signal.
ws=$(mk_ws)
first=$("$DR" "$ws" 2>&1)
vd_open_id=$(printf '%s\n' "$first" | sed -n 's/^ *\(VD-[0-9]*\) *open — judge from the store.*/\1/p' | head -1)
precond "the worklist listed at least one open row to re-run against" test -n "$vd_open_id"
# no buckets to flip any more, so idempotence is measured on the POINTER counts:
# the whole section must come back byte-identical after its own paste.
n_nomention() { printf '%s\n' "$1" | command grep -c 'open — judge from the store' || true; }
vd_section() { printf '%s\n' "$1" | sed -n '/^## open validation-debt rows/,$p'; }
before=$(n_nomention "$first")
printf '%s\n' "$first" > "$ws/closeout.md"          # the card's own paste, verbatim
second=$("$DR" "$ws" 2>&1)
[ "$(vd_section "$first")" = "$(vd_section "$second")" ] && [ "$before" -gt 0 ] \
  && ok "the worklist is byte-identical under its own pasted output ($before rows, pointer counts unmoved)" \
  || bad "the paste moved the section: the corpus is counting the report as evidence"
# surgical: the SAME file mentioning a row in prose still counts it
{ printf '%s\n' "$first"; printf '\nWe worked on %s this topic (prose, not the report).\n' "$vd_open_id"; } > "$ws/closeout.md"
out=$("$DR" "$ws" 2>&1)
printf '%s\n' "$out" | command grep -qE "^ *$vd_open_id +open .*prose mentions this topic: [1-9]" \
  && ok "a genuine prose mention in closeout.md still counts on its row ($vd_open_id) — the filter drops the report's own lines, not the file" \
  || bad "the filter is too wide: $vd_open_id has a prose mention in closeout.md and its pointer still reads 0"
# membership must NOT move: the worklist is every open row, and a prose mention
# changes a pointer on one of them. This is what the un-bucketed shape buys —
# there is no longer a bucket a row can be moved between by talking about it.
[ "$(n_nomention "$out")" -eq "$before" ] \
  && ok "every open row is still listed exactly once — a prose mention moves a pointer, never membership" \
  || bad "worklist membership moved with a prose mention: $before rows before, $(n_nomention "$out") after"

echo "-- closed rows can pre-register readings: the WANTED line, asked where nothing else asks --"
# §5's worklist used to
# stop at `## closed`, so a closed row's pre-registered request sat in prose
# under a heading that means finished. The convention lands with this arm: a
# closed row writes `WANTED: <reading>` in a cell, and the report asks for it
# beneath the open worklist. DR_VD_FILE drives the section against a scratch
# table (the env knob is derive_report's own named seam); the scratch WANTED
# text deliberately NAMES the open row's id — the strongest case for the
# idempotence filter, since a pasted report carrying it must not score that
# row "mentioned".
wsw=$(mk_ws)
cat > "$wsw/vd.md" <<'VDEOF'
# validation debt

| id | what is unvalidated | why self-check cannot close it | closes on |
|---|---|---|---|
| VD-90 | fixture open row | fixture | fixture |

## standing

## closed

| id | was | closed on |
|---|---|---|
| VD-91 | fixture closed row | closed on fixture evidence. WANTED: the benign shape of VD-90's next touched-file set, per this row's own pre-registration |
VDEOF
outw=$(DR_VD_FILE="$wsw/vd.md" "$DR" "$wsw" 2>&1)
printf '%s\n' "$outw" | command grep -q '^  VD-90 ' \
  && ok "the scratch table's open row is still the worklist" \
  || bad "worklist lost under DR_VD_FILE: $(printf '%s\n' "$outw" | tail -3)"
printf '%s\n' "$outw" | command grep -q '^    WANTED: the benign shape of VD-90' \
  && ok "a closed row's WANTED: marker prints beneath the worklist, naming its reading" \
  || bad "no WANTED line for the marker the closed row carries"
# THE IDEMPOTENCE DIRECTION, strongest form: paste the report (whose WANTED
# line names VD-90) into closeout.md and re-run — the mention pointer must not
# move, or the asking mechanism would contaminate the very probe it rides on.
printf '%s\n' "$outw" > "$wsw/closeout.md"
outw2=$(DR_VD_FILE="$wsw/vd.md" "$DR" "$wsw" 2>&1)
printf '%s\n' "$outw2" | command grep -q '^  VD-90  open — judge from the store (prose mentions this topic: 0, a pointer only)$' \
  && ok "the pasted WANTED line (which NAMES the open row) does not score it mentioned — the asking is idempotent" \
  || bad "the WANTED paste contaminated the mention probe: $(printf '%s\n' "$outw2" | command grep '^  VD-90')"
# scope: an OPEN row's WANTED never prints — an open row IS the worklist.
sed -i 's#| VD-90 | fixture open row | fixture | fixture |#| VD-90 | fixture open row | fixture | fixture. WANTED: open rows are the worklist, no marker |#' "$wsw/vd.md"
outw3=$(DR_VD_FILE="$wsw/vd.md" "$DR" "$wsw" 2>&1)
[ "$(printf '%s\n' "$outw3" | command grep -c 'WANTED:')" -le 1 ] \
  && ok "a WANTED in an OPEN row does not print — the marker is the closed table's voice, and the open row is already listed" \
  || bad "an open row's WANTED printed: $(printf '%s\n' "$outw3" | command grep 'WANTED:')"
# the no-marker floor and the fall-through: no open rows at all, one closed
# WANTED — the report names the empty worklist AND still asks.
cat > "$wsw/vd2.md" <<'VDEOF'
# validation debt

## standing

## closed

| id | was | closed on |
|---|---|---|
| VD-92 | fixture closed-only table | closed. WANTED: anything at all |
VDEOF
outw4=$(DR_VD_FILE="$wsw/vd2.md" "$DR" "$wsw" 2>&1)
printf '%s\n' "$outw4" | command grep -q '(no open VD rows)' \
  && printf '%s\n' "$outw4" | command grep -q '^    WANTED: anything at all$' \
  && ok "with no open rows the worklist is named empty and the closed WANTED still asks (the fall-through §5 used to skip)" \
  || bad "closed-only table lost the asking: $(printf '%s\n' "$outw4" | tail -3)"

echo "-- reviewer coverage: the CATCH side, and the ratio that must refuse to divide --"
# The handoff surface carries findings.substantive/wording beside every verdict.
# The ferry reads those fields per (slice, stage, round) for the severity-trend
# predicate; nothing read the AGGREGATE, which is how the coverage figure came to
# be hand-computed once and quoted thereafter.
wsc2=$(mk_ws); mkdir -p "$wsc2/slices/01"
state_append "$wsc2" handoff session "v=1 t=1 slice=01 stage=precheck round=1 verdict=issues confidence=HIGH findings.substantive=5 findings.wording=2" >/dev/null
state_append "$wsc2" handoff session "v=1 t=2 slice=01 stage=precheck round=2 verdict=ready confidence=HIGH findings.substantive=1 findings.wording=3" >/dev/null
state_append "$wsc2" handoff session "v=1 t=3 slice=01 stage=postcheck round=1 verdict=findings confidence=HIGH findings.substantive=4 findings.wording=1" >/dev/null
state_append "$wsc2" handoff session "v=1 t=4 slice=01 stage=spec round=1 verdict=drafted confidence=HIGH refine.rounds=2" >/dev/null
state_append "$wsc2" learnings session "v=1 t=5 slice=01 stage=postcheck round=1 leak_class=precheck record= text=a" >/dev/null
state_append "$wsc2" learnings session "v=1 t=6 slice=01 stage=postcheck round=1 leak_class=novel record= text=b" >/dev/null
outc3=$("$DR" "$wsc2" 2>&1)
printf '%s\n' "$outc3" | command grep -qE '^  precheck +2 +6 +5   issues 1 / ready 1' \
  && ok "coverage sums substantive and wording ACROSS rounds, with the verdict split (precheck 2 emits, 6+5)" \
  || bad "coverage row wrong; got: $(printf '%s' "$outc3" | command grep -E '^  precheck ')"
command grep -q 'stage=spec' <<< "$outc3" \
  && bad "an AUTHOR stage leaked into the reviewer coverage table" \
  || ok "author stages are absent — they carry refine.rounds, not findings, and have no coverage"
# The new/repeat split line: a round>=2 row WITHOUT the field is counted as
# unfielded (never as repeat=0), and one WITH it feeds the sums. Both directions
# on one fixture, before and after the fielded row lands.
printf '%s\n' "$outc3" | command grep -qF 'round>=2 review emits: 1 · carrying the new/repeat split: 0 (new 0 · repeat 0) · unfielded: 1' \
  && ok "a pre-field round-2 row reads as UNFIELDED, not as a zero split" \
  || bad "split line wrong for an unfielded row; got: $(printf '%s' "$outc3" | command grep 'round>=2')"
state_append "$wsc2" handoff session "v=1 t=7 slice=01 stage=postcheck round=2 verdict=findings confidence=HIGH findings.substantive=1 findings.wording=0 findings.substantive.new=1 findings.substantive.repeat=0" >/dev/null
outc3b=$("$DR" "$wsc2" 2>&1)
printf '%s\n' "$outc3b" | command grep -qF 'round>=2 review emits: 2 · carrying the new/repeat split: 1 (new 1 · repeat 0) · unfielded: 1' \
  && ok "…and a fielded row feeds the sums while the unfielded one stays counted apart" \
  || bad "split line wrong after a fielded row; got: $(printf '%s' "$outc3b" | command grep 'round>=2')"
printf '%s\n' "$outc3" | command grep -qE 'efficiency: 6 caught / 1 leaked = 85\.7%.*n=7 · small-n' \
  && ok "DRE joins the two surfaces (handoff caught, learnings leaked) and prints n with the small-n mark" \
  || bad "DRE line wrong; got: $(printf '%s' "$outc3" | command grep -i efficiency)"
printf '%s\n' "$outc3" | command grep -q 'postcheck has NO computable DRE' \
  && ok "…and says postcheck has none — nothing detects what escapes the last reviewer" \
  || bad "the postcheck asymmetry is unstated, so a reader may take its absence for an oversight"
printf '%s\n' "$outc3" | command grep -q 'UPPER BOUND' \
  && ok "…and carries its own upper bound (a defect escaping BOTH reviews is invisible to this)" \
  || bad "the DRE prints without its upper-bound caveat"
# known-bad: the 0/0 case must REFUSE to divide. This is the defect this file
# already caught once in derive_cost the same day — a fatal awk divide killing
# the report — and the wrong-but-plausible answer here is 100%, not a crash.
wsc3=$(mk_ws)
state_append "$wsc3" handoff session "v=1 t=1 slice=01 stage=precheck round=1 verdict=ready confidence=HIGH findings.substantive=0 findings.wording=0" >/dev/null
outc4=$("$DR" "$wsc3" 2>&1); rcc4=$?
[ "$rcc4" -eq 0 ] && printf '%s\n' "$outc4" | command grep -q 'efficiency: n/a' \
  && ok "known-bad: no findings and no leaks prints n/a, not 100% and not a divide-by-zero" \
  || bad "the 0/0 case (rc=$rcc4); got: $(printf '%s' "$outc4" | command grep -i efficiency)"
printf '%s\n' "$outc4" | command grep -q 'absent, not 100%' \
  && ok "…and names the wrong answer it is refusing to give" \
  || bad "the n/a line does not say what it is refusing"
# A 100% that is really an EMPTY LEAK SURFACE. Found by auditing the section
# after it shipped: an archived topic reads 13 caught / 0 leaked = 100.0%, and
# it is the one that predates the emit-time door forcing a learnings row per
# finding — so its zero means "nothing recorded", not "nothing escaped". The
# small-n mark fires there but says the wrong thing; this says the right one.
wsc4=$(mk_ws)
state_append "$wsc4" handoff session "v=1 t=1 slice=01 stage=precheck round=1 verdict=issues confidence=HIGH findings.substantive=9 findings.wording=0" >/dev/null
outc5=$("$DR" "$wsc4" 2>&1)
printf '%s\n' "$outc5" | command grep -qE 'efficiency: 9 caught / 0 leaked = 100\.0%' \
  && printf '%s\n' "$outc5" | command grep -q 'ZERO leaks is the reading to distrust first' \
  && ok "a 100% built on zero leaks says so — 'nothing recorded' and 'nothing escaped' are the same number here" \
  || bad "the zero-leak caveat is missing; got: $(printf '%s' "$outc5" | command grep -A1 -i efficiency | head -2)"
command grep -q 'ZERO leaks is the reading to distrust first' <<< "$outc3" \
  && bad "the zero-leak caveat printed for a topic that HAS leaks — it would become noise" \
  || ok "…and stays silent when leaks exist (1 leaked on the earlier fixture)"
# STRUCTURAL: coverage must precede the validation-debt worklist. vd_section()
# below reads that header to END OF FILE, so a section placed after it would be
# swallowed into the worklist and silently change what the idempotence arm
# compares. The constraint is invisible from either file alone.
awk '/^## reviewer coverage/{c=NR} /^## open validation-debt rows/{v=NR}
     END{ exit !(c>0 && v>0 && c<v) }' <<< "$outc3" \
  && ok "the coverage section precedes the validation-debt worklist (vd_section reads that header to EOF)" \
  || bad "coverage sits at or after the worklist header — vd_section would swallow it"

# STRUCTURAL: the header's input list must NAME every store surface the file
# reads directly. That list went short twice — once on the sections it
# enumerates, once on the inputs — and both times someone had to count by hand.
# WHAT THIS CANNOT SEE, which is the way it went short the second time: a
# surface reached through a lib/ helper (the slices index, read by section 4
# through `binding_repo`) matches no `state_get` here and is invisible to this
# arm. So it floors the common shape and no more; the header says the rest.
dr_missing=""
for dr_s in $(command grep -oE 'state_get "\$WS" [a-z]+' "$DR" | awk '{print $3}' | sort -u); do
  sed -n '1,30p' "$DR" | command grep -q "$dr_s" || dr_missing="$dr_missing $dr_s"
done
[ -z "$dr_missing" ] \
  && ok "every surface derive_report.sh reads with state_get is named in its header's input list" \
  || bad "the header's input list is short by:$dr_missing"

echo "-- the runner's two modes report the SAME verdicts (--jobs is opt-in, not a different truth) --"
# check.sh gained an opt-in concurrent mode. The risk it introduces is not the
# concurrency — every check already owns its temp dirs and both tmux users
# mktemp their own TMUX_TMPDIR — it is that TWO run paths could drift into
# reporting the same verdict differently. So they share one renderer, and both
# it and the parallel driver are exercised HERE against the real code, on
# fixture checks rather than on the suite itself (a check that writes into
# self-check/checks/ would be seen by the run that is executing it).
. "$SELFCHECK_DIR/check.sh"     # sourceable: the runner lives behind a main() guard
CHECK_DURATIONS_DIR=$(sc_tmpdir)/durations   # the fixture checks below must not feed the real launch order
fx=$(sc_tmpdir)
printf '#!/usr/bin/env bash\necho "  (7 assertions, 0 failed)"\nexit 0\n'      > "$fx/a.sh"
printf '#!/usr/bin/env bash\necho "  FAIL: deliberate"\nexit 1\n'             > "$fx/b.sh"
printf '#!/usr/bin/env bash\necho "SKIP: no tmux on this machine"\nexit 77\n' > "$fx/c.sh"

PASS=0; FAIL=0; SKIP=0; FAILED_NAMES=""; VERBOSE=0; SUM_SECS=0; MAX_SECS=0; MAX_NAME=""
render alpha 0  1 "$fx/a.sh.log" 2>/dev/null || true   # log absent: must not explode
PASS=0; FAIL=0; SKIP=0; FAILED_NAMES=""; SUM_SECS=0; MAX_SECS=0; MAX_NAME=""
: > "$fx/log0"; echo "  (7 assertions, 0 failed)" > "$fx/log0"
: > "$fx/log1"; echo "  FAIL: deliberate" > "$fx/log1"
: > "$fx/log77"; echo "SKIP: no tmux on this machine" > "$fx/log77"
r0=$(render alpha 0 1 "$fx/log0"); r1=$(render beta 1 2 "$fx/log1"); r77=$(render gamma 77 3 "$fx/log77")
printf '%s\n' "$r0" | command grep -q '^PASS alpha (1s) (7 assertions, 0 failed)$' \
  && ok "render: a 0 exit prints PASS with the check's own last line" || bad "got: $r0"
printf '%s\n' "$r1" | command grep -q '^FAIL beta (rc=1, 2s) — full output:' \
  && ok "render: a non-zero exit prints FAIL with the rc and dumps the log" || bad "got: $(printf '%s' "$r1" | head -1)"
printf '%s\n' "$r77" | command grep -q '^SKIP gamma — no tmux on this machine$' \
  && ok "render: rc 77 prints SKIP with the stated reason" || bad "got: $r77"

# The parallel driver is PURE — it prints a results table and touches no shell
# state. That is deliberate: the first version rendered inside it, and calling
# it on the wrong side of a pipe silently lost the counters, which is a GREEN
# SUMMARY OVER A RED CHECK. Now it cannot report anything at all.
JOBS=3; ptmp=$(sc_tmpdir)
tbl=$(printf 'alpha\t%s\nbeta\t%s\ngamma\t%s\n' "$fx/a.sh" "$fx/b.sh" "$fx/c.sh" | run_parallel "$ptmp")
seq=$(printf '%s\n' "$tbl" | cut -f1 | paste -sd, -)
[ "$seq" = "alpha,beta,gamma" ] \
  && ok "parallel returns rows in DECLARED order ($seq) though it LAUNCHES in reverse — the store's verdict still reads first" \
  || bad "row order was '$seq', want alpha,beta,gamma"
rcs=$(printf '%s\n' "$tbl" | cut -f2 | paste -sd, -)
[ "$rcs" = "0,1,77" ] \
  && ok "and each row carries its check's real exit code ($rcs)" || bad "rcs='$rcs', want 0,1,77"
# Rendered by the SAME renderer the serial path uses, in the caller's shell.
PASS=0; FAIL=0; SKIP=0; FAILED_NAMES=""; SUM_SECS=0; MAX_SECS=0; MAX_NAME=""
while IFS=$'\t' read -r n rc dt lg; do render "$n" "$rc" "$dt" "$lg"; done > /dev/null <<< "$tbl"
[ "$PASS" = "1" ] && [ "$FAIL" = "1" ] && [ "$SKIP" = "1" ] \
  && ok "rendering that table moves the counters (pass=$PASS fail=$FAIL skip=$SKIP) — a red cannot hide behind a green summary" \
  || bad "counters: pass=$PASS fail=$FAIL skip=$SKIP (want 1/1/1)"
# The same pass accumulates the two maintenance quantities — the renderer is
# their only source, so both modes measure them identically by construction.
# Fixture checks finish in 0s, so the seconds are given, not measured.
PASS=0; FAIL=0; SKIP=0; FAILED_NAMES=""; SUM_SECS=0; MAX_SECS=0; MAX_NAME=""
{ render alpha 0 1 "$fx/log0"; render gamma 77 3 "$fx/log77"; render beta 1 2 "$fx/log1"; } > /dev/null
[ "$SUM_SECS" = "6" ] && [ "$MAX_NAME" = "gamma" ] && [ "$MAX_SECS" = "3" ] \
  && ok "and accumulates the tax (sum ${SUM_SECS}s) and the floor (slowest $MAX_NAME ${MAX_SECS}s) from the same rows, whatever their order" \
  || bad "sum=$SUM_SECS slowest=$MAX_NAME/$MAX_SECS (want 6, gamma/3) — the maintenance quantities are not coming from the renderer"
printf '%s' "$FAILED_NAMES" | command grep -q beta \
  && ok "and the failing name is carried out for the summary line" || bad "FAILED_NAMES='$FAILED_NAMES'"

# A hung check is KILLED and named, never waited on forever: the runner bounds
# every check (CHECK_TIMEOUT) in both modes through one run_check, and the
# kill reaches the check's process group so its EXIT trap still runs — the
# fixture's trap leaves a marker, the way a drill's trap kills its tmux
# server. Both directions: the hang times out as rc 124 with the renderer
# naming it; a check under the bound is untouched.
hg=$(sc_tmpdir)
printf '#!/usr/bin/env bash\ntrap '"'"'echo trap-ran > %s/trap'"'"' EXIT\necho "  working..."\nsleep 30\n' "$hg" > "$hg/hang.sh"
CHECK_TIMEOUT=1
t0=$(date +%s); run_check "$hg/hang.sh" "$hg/hang.log"; hrc=$?; hdt=$(( $(date +%s) - t0 ))
[ "$hrc" -eq 124 ] && [ "$hdt" -lt 10 ] \
  && ok "a check that never returns is killed at the bound (rc 124 after ${hdt}s, bound 1s)" \
  || bad "hung check: rc=$hrc after ${hdt}s — the suite would have waited 30s, or forever"
[ "$(cat "$hg/trap" 2>/dev/null)" = "trap-ran" ] \
  && ok "and its EXIT trap ran (the kill reaches the process group — a drill still tears its server down)" \
  || bad "the killed check's EXIT trap did not run — a killed drill would leak its tmux server"
PASS=0; FAIL=0; SKIP=0; FAILED_NAMES=""; SUM_SECS=0; MAX_SECS=0; MAX_NAME=""
r124=$(render hang 124 1 "$hg/hang.log")
printf '%s\n' "$r124" | command grep -q '^FAIL hang (rc=124, TIMED OUT' \
  && ok "render names a timeout as one, not as a generic failure" || bad "got: $(printf '%s' "$r124" | head -1)"
run_check "$fx/a.sh" "$hg/a.log"; [ $? -eq 0 ] \
  && ok "a check under the bound runs to its own exit code unchanged" || bad "run_check altered a passing check's rc"
CHECK_TIMEOUT=600

# LAUNCH order is longest-first from recorded durations, so the pool's tail is
# the slowest check and not whichever long check happened to be declared last.
# With no records the order is the declared order reversed (what it always
# was); with records, the longest last run launches first and an unknown
# check launches before everything (unknown reads as long). Observed through
# a START timeline at --jobs 1, where launch order IS execution order.
ld=$(sc_tmpdir); ltl="$ld/timeline"; CHECK_DURATIONS_DIR="$ld/durations"   # a fresh, empty one for this arm
for n in a b c; do printf '#!/usr/bin/env bash\necho "START %s" >> %s\necho "  (1 assertions, 0 failed)"\nexit 0\n' "$n" "$ltl" > "$ld/$n.sh"; done
JOBS=1
printf 'a\t%s\nb\t%s\nc\t%s\n' "$ld/a.sh" "$ld/b.sh" "$ld/c.sh" | run_parallel "$ld" > /dev/null
[ "$(awk '{print $2}' "$ltl" | paste -sd, -)" = "c,b,a" ] \
  && ok "no recorded durations: launch order is the declared order reversed (c,b,a)" \
  || bad "launch order without records: $(awk '{print $2}' "$ltl" | paste -sd, -), want c,b,a"
[ -s "$CHECK_DURATIONS_DIR/a" ] && [ -s "$CHECK_DURATIONS_DIR/c" ] \
  && ok "and each run records its duration for the next launch order" \
  || bad "durations not recorded under $CHECK_DURATIONS_DIR"
: > "$ltl"; printf '1\n' > "$CHECK_DURATIONS_DIR/a"; printf '9\n' > "$CHECK_DURATIONS_DIR/b"; printf '5\n' > "$CHECK_DURATIONS_DIR/c"
printf 'a\t%s\nb\t%s\nc\t%s\n' "$ld/a.sh" "$ld/b.sh" "$ld/c.sh" | run_parallel "$ld" > /dev/null
[ "$(awk '{print $2}' "$ltl" | paste -sd, -)" = "b,c,a" ] \
  && ok "recorded durations 1/9/5: the 9s check launches first (b,c,a)" \
  || bad "launch order with records: $(awk '{print $2}' "$ltl" | paste -sd, -), want b,c,a"
: > "$ltl"; rm -f "$CHECK_DURATIONS_DIR/c"; printf '1\n' > "$CHECK_DURATIONS_DIR/a"; printf '9\n' > "$CHECK_DURATIONS_DIR/b"
printf 'a\t%s\nb\t%s\nc\t%s\n' "$ld/a.sh" "$ld/b.sh" "$ld/c.sh" | run_parallel "$ld" > /dev/null
[ "$(awk '{print $2}' "$ltl" | paste -sd, -)" = "c,b,a" ] \
  && ok "a check with no record launches before everything (unknown reads as long: c,b,a)" \
  || bad "launch order with one unknown: $(awk '{print $2}' "$ltl" | paste -sd, -), want c,b,a"
rows=$(printf 'a\t%s\nb\t%s\nc\t%s\n' "$ld/a.sh" "$ld/b.sh" "$ld/c.sh" | run_parallel "$ld" | cut -f1 | paste -sd, -)
[ "$rows" = "a,b,c" ] \
  && ok "and the results table still comes back in DECLARED order whatever the launch order" \
  || bad "rows in launch order, not declared: $rows"

# The POOL must stay bounded, including past a failing check — that is when the
# machine is least able to spare the load, because someone is diagnosing on it.
# (`wait -n` returns the finished job's status, so a non-zero one still means a
# slot freed; this pins that reading rather than trusting it.)
bd=$(sc_tmpdir); tl="$bd/timeline"
for i in 1 2 3 4 5 6; do
  brc=0; [ $((i % 2)) -eq 0 ] && brc=1
  printf '#!/usr/bin/env bash\necho "START $$" >> %s\nsleep 0.4\necho "END $$" >> %s\necho "  (1 assertions, 0 failed)"\nexit %s\n' \
    "$tl" "$tl" "$brc" > "$bd/c$i.sh"
done
JOBS=2
btbl=$(for i in 1 2 3 4 5 6; do printf 'c%s\t%s\n' "$i" "$bd/c$i.sh"; done | run_parallel "$bd")
[ "$(printf '%s\n' "$btbl" | command grep -c .)" = "6" ] \
  && ok "every check reports a row even when half of them fail ($(printf '%s\n' "$btbl" | cut -f2 | paste -sd, -))" \
  || bad "rows: $(printf '%s\n' "$btbl" | command grep -c .)"
# The concurrency read below is an awk over this timeline: a template whose
# echo lines rotted out would leave it EMPTY, peak would read 0, and
# "peak 0 of 2" would pass as the safest run ever measured. Floor the
# extraction before believing it.
precond "the timeline recorded all six fixture runs (START and END each 6 — the peak's only input)" \
  bash -c '[ "$(command grep -c "^START " "$1")" = 6 ] && [ "$(command grep -c "^END " "$1")" = 6 ]' _ "$tl"
peak=$(awk '{ if($1=="START"){n++; if(n>m)m=n} else n-- } END{print m+0}' "$tl")
[ "${peak:-99}" -le 2 ] \
  && ok "concurrency never exceeded --jobs (peak $peak of 2), failures included" \
  || bad "peak concurrency $peak with --jobs 2 — a failing check unbounded the pool"

echo "-- the runner measures its own isolation: the tree after the suite equals the tree before --"
# Per-check isolation was prose ("each owns its temp dirs") until the driver
# started hashing the workflow tree at both ends of a run. The two functions
# are proved here on a fixture tree, against the real code; the wiring in
# main is what every run's `tree:` summary line shows. Each direction a
# mutation can take is exercised once: content, a new entry, a deleted entry,
# a mode flip, an empty directory — and the one thing the snapshot must NOT
# see (a .git inside the root, for a standalone clone).
iso=$(sc_tmpdir); mkdir -p "$iso/sub" "$iso/.git/objects"
printf 'a\n' > "$iso/a.txt"; printf 'b\n' > "$iso/sub/b.txt"; chmod 644 "$iso/a.txt" "$iso/sub/b.txt"
printf 'x\n' > "$iso/.git/objects/x"
tree_snapshot "$iso" > "$iso.before" 2>/dev/null
_iso_listed() { command grep -q '^f 644 ./a.txt$' "$iso.before" && command grep -q '^f 644 ./sub/b.txt$' "$iso.before" && command grep -q '^d [0-9]* ./sub$' "$iso.before"; }
precond "the fixture snapshot lists both files (kind+mode) and the directory" _iso_listed
command grep -q '\.git' "$iso.before" \
  && bad "the snapshot descended into .git: $(command grep '\.git' "$iso.before" | head -2 | tr '\n' ' ')" \
  || ok "a .git inside the root is pruned from the snapshot (a standalone clone's index churn is not a mutation)"
tree_snapshot "$iso" > "$iso.same"
v=$(tree_verdict "$iso.before" "$iso.same" 2>/dev/null); vrc=$?
[ $vrc -eq 0 ] && printf '%s\n' "$v" | command grep -q '^tree: unchanged (' \
  && ok "an untouched tree verdicts 'unchanged' with rc 0: $v" \
  || bad "untouched tree: rc=$vrc, '$v'"
iso_mut() { # label mutation-command... -> the verdict must go rc 1 and name $ISO_PATH
  local label=$1; shift
  "$@"
  tree_snapshot "$iso" > "$iso.after"
  local v vrc
  v=$(tree_verdict "$iso.before" "$iso.after"); vrc=$?
  [ $vrc -eq 1 ] && printf '%s\n' "$v" | command grep -q '^tree: MUTATED' && printf '%s\n' "$v" | command grep -qF "$ISO_PATH" \
    && ok "$label -> MUTATED (rc 1), naming $ISO_PATH" \
    || bad "$label: rc=$vrc, verdict does not name $ISO_PATH: $(printf '%s' "$v" | head -3 | tr '\n' ' ')"
  cp "$iso.after" "$iso.before"    # each mutation is measured against the tree as it then stood
}
_iso_write() { printf '%s\n' "$2" > "$1"; }
ISO_PATH=./a.txt;     iso_mut "a file's CONTENT changed (same size)"   _iso_write "$iso/a.txt" c
ISO_PATH=./new.txt;   iso_mut "a file ADDED"                            _iso_write "$iso/new.txt" n
ISO_PATH=./sub/b.txt; iso_mut "a file DELETED"                          rm -f "$iso/sub/b.txt"
ISO_PATH=./a.txt;     iso_mut "only the MODE flipped (chmod +x)"        chmod 755 "$iso/a.txt"
ISO_PATH=./empty;     iso_mut "an empty DIRECTORY added"                mkdir "$iso/empty"
# The .git prune is the only blind spot, and it must stay the only one.
printf 'y\n' > "$iso/.git/objects/y"
tree_snapshot "$iso" > "$iso.after"
tree_verdict "$iso.before" "$iso.after" > /dev/null 2>&1 \
  && ok "a write under .git alone still verdicts unchanged (the prune is the stated blind spot, nothing else is)" \
  || bad "a .git write read as a tree mutation"

echo "-- derive_cost.sh: the cost counterpart, and its two refusals --"
# Same gene as derive_report: derived, read-only, no new state. What it must
# never do is turn a parked span into a cost, or read an unreadable ledger as
# an absent one — both are the store's "absent is not zero" doctrine applied to
# durations. Fixtures write THROUGH the store so headers verify.
DC="$RS/derive_cost.sh"
precond "derive_cost.sh exists and parses" bash -n "$DC"
wsc=$(mk_ws)
# two clean spans (one cold 600s, one warm 200s) and one span straddling a park
state_append "$wsc" ledger ferry "v=1 t=1000 event=spawn slice=01 stage=precheck mode=cold" >/dev/null
state_append "$wsc" ledger ferry "v=1 t=1600 event=record slice=01 stage=precheck" >/dev/null
state_append "$wsc" ledger ferry "v=1 t=2000 event=spawn slice=01 stage=revise mode=warm-author" >/dev/null
state_append "$wsc" ledger ferry "v=1 t=2200 event=record slice=01 stage=revise" >/dev/null
state_append "$wsc" ledger ferry "v=1 t=3000 event=spawn slice=02 stage=precheck mode=cold" >/dev/null
state_append "$wsc" ledger ferry "v=1 t=3500 event=park slice=02 reason=budget_wallclock" >/dev/null
state_append "$wsc" ledger ferry "v=1 t=99000 event=record slice=02 stage=precheck" >/dev/null
outc=$("$DC" "$wsc" 2>&1)
printf '%s\n' "$outc" | command grep -q 'kept 2, dropped 1 for containing a park' \
  && ok "a span straddling a park is DROPPED, and the drop is counted where the reader sees it" \
  || bad "park exclusion wrong; got: $(printf '%s' "$outc" | command grep paired)"
printf '%s\n' "$outc" | command grep -qE 'precheck +cold +1 +10m00' \
  && ok "the surviving cold span is measured spawn->record (600s = 10m00)" \
  || bad "cold span mis-measured; got: $(printf '%s' "$outc" | command grep precheck)"
# WHAT THE DROP COSTS. The header used to assert that no honest per-stage
# subtraction exists, citing `attempts parked.<nn>` — which is per-SLICE and
# names no stage. The LEDGER park row carries slice AND stage, so a dropped
# span whose parks are all its own IS attributable, and the drop is now a
# choice with a printed price rather than an asserted impossibility. Both
# directions, because the whole value is in telling the two apart.
wsd2=$(mk_ws)
state_append "$wsd2" ledger ferry "v=1 t=1000 event=spawn slice=01 stage=impl mode=warm" >/dev/null
state_append "$wsd2" ledger ferry "v=1 t=1100 event=park reason=blocked slice=01 stage=impl" >/dev/null
state_append "$wsd2" ledger ferry "v=1 t=1400 event=ferry_start" >/dev/null
state_append "$wsd2" ledger ferry "v=1 t=1600 event=record slice=01 stage=impl" >/dev/null
state_append "$wsd2" ledger ferry "v=1 t=2000 event=spawn slice=02 stage=spec mode=cold" >/dev/null
state_append "$wsd2" ledger ferry "v=1 t=2100 event=park reason=class_u slice=09 stage=turnover" >/dev/null
state_append "$wsd2" ledger ferry "v=1 t=2500 event=ferry_start" >/dev/null
state_append "$wsd2" ledger ferry "v=1 t=2600 event=record slice=02 stage=spec" >/dev/null
outd2=$("$DC" "$wsd2" 2>&1)
printf '%s\n' "$outd2" | command grep -qE 'of those 2: 1 carry only their OWN stage parks' \
  && ok "a dropped span whose park is its own is counted RECOVERABLE; one with a foreign park is not" \
  || bad "recoverability split wrong; got: $(printf '%s' "$outd2" | command grep 'of those')"
printf '%s\n' "$outd2" | command grep -qE '0\.2h raw, 0\.1h parked, 0\.1h of work' \
  && ok "…and the price is priced: 600s raw minus the 300s park leaves 300s of real work discarded" \
  || bad "recoverable arithmetic wrong; got: $(printf '%s' "$outd2" | command grep 'of those')"
printf '%s\n' "$outc" | command grep -qE 'revise +warm +1' \
  && ok "warm-author is bucketed as warm (the mode field is a prefix, not an equality)" \
  || bad "warm-author not bucketed warm; got: $(printf '%s' "$outc" | command grep revise)"
# known-bad A: an unreadable ledger must be NAMED, never silently shrink the sample
wsempty=$(mk_ws)
outc2=$("$DC" "$wsc" "$wsempty" 2>&1)
printf '%s\n' "$outc2" | command grep -q 'NOT read:' \
  && ok "known-bad: a topic with no ledger is named in the report's own range line" \
  || bad "an unreadable topic vanished silently: $(printf '%s' "$outc2" | head -3)"
# …and the name it is reported under is its OWN, in EITHER argument form. The
# collection loop used to derive the name from `cd` after the delivery/
# fallback, so a WORKSPACE-form argument with no store probed
# <arg>/delivery/delivery, failed, and printed the basename of the argument
# itself — `delivery`, identically for every such topic. Measured on the real
# archives: four store-less topics are indistinguishable in one skip line,
# which is exactly the "an unreadable ledger is named" contract defeated. The
# arm below hands the instrument a workspace-form path whose topic directory
# EXISTS, so the failure is the naming and not a typo in the path.
wsempty2=$(sc_tmpdir); mkdir -p "$wsempty2/delivery"
outn=$("$DC" --stage-totals "$wsempty2/delivery" 2>&1); outn_rc=$?
[ "$outn_rc" -eq 2 ] && printf '%s\n' "$outn" | command grep -qF "$(basename "$wsempty2")(no ledger)" \
  && ok "known-bad: a workspace-form argument with no store is named by its TOPIC, never as a bare 'delivery'" \
  || bad "an unreadable workspace-form argument lost its name (rc=$outn_rc): $(printf '%s' "$outn" | head -1)"
# the topic-form half of the same rule, on a directory that does not exist at
# all: the name comes from the argument, and a path nobody can open still
# names what it was trying to be
outn2=$("$DC" --stage-totals "$(sc_tmpdir)/never_built" 2>&1)
printf '%s\n' "$outn2" | command grep -qF 'never_built(no ledger)' \
  && ok "…and a topic-form argument names its topic even when nothing exists to open" \
  || bad "a nonexistent topic-form argument lost its name: $(printf '%s' "$outn2" | head -1)"
# The --stage-totals success path writes NOTHING to stderr, which is the contract
# its one consumer rests on: `derive_report.sh` captures this mode with the
# streams merged and lets the exit status decide. A stderr line on a successful
# run would arrive there as a data row. Asserted rather than trusted to a comment,
# because the comment lives in this file's subject and the breaking edit is a
# stray `echo ... >&2` anywhere in a 370-line script.
dcerr=$("$DC" --stage-totals "$wsc" 2>&1 >/dev/null)
[ -z "$dcerr" ] \
  && ok "--stage-totals writes nothing to stderr on success (its consumer merges the streams)" \
  || bad "the totals mode wrote to stderr on a healthy run; its consumer would read this as data: '$dcerr'"

# An OPTION out of position is refused, never read as a path. The fallback was
# worse than the typo: it reached the reader, held no ledger, and reported
# itself as a topic with no ledger — a confident wrong diagnosis.
"$DC" "$wsc" --stage-totals > /dev/null 2>&1
[ $? -eq 2 ] \
  && ok "known-bad: an option after the first argument REFUSES (rc=2) rather than being read as a directory" \
  || bad "a misplaced option was accepted as a path"

# known-bad B: no readable ledger at all refuses, rather than printing an empty
# table that reads as "these stages cost nothing"
"$DC" "$wsempty" > /dev/null 2>&1
[ $? -eq 2 ] \
  && ok "known-bad: zero readable ledgers REFUSES (rc=2) instead of printing a zero-cost table" \
  || bad "empty input produced a report"
# known-bad C: the median convention. Four spans of 60/120/180/1000s have a
# lower-middle of 120 and a conventional median of 150 — the convention that
# moved two real ratios by more than 1.6x, so it is pinned rather than assumed.
wsm=$(mk_ws); t=0
for d in 60 120 180 1000; do
  t=$((t + 10000)); state_append "$wsm" ledger ferry "v=1 t=$t event=spawn slice=0$((t/10000)) stage=turnover mode=cold" >/dev/null
  state_append "$wsm" ledger ferry "v=1 t=$((t + d)) event=record slice=0$((t/10000)) stage=turnover" >/dev/null
done
printf '%s\n' "$("$DC" "$wsm" 2>&1)" | command grep -qE 'turnover +cold +4 +2m30' \
  && ok "known-bad: an even sample takes the CONVENTIONAL median (150s), not the lower middle (120s)" \
  || bad "median convention drifted; got: $("$DC" "$wsm" 2>&1 | command grep turnover)"
# known-bad D: TOPIC IDENTITY. The awk keys its park set and its open-spawn
# table on FILENAME, which is only a topic while the ledgers are ARGUMENTS —
# piped through `cat`, FILENAME is "-" for every row and the two structures
# merge. The four archived topics do not expose it (no park of one falls inside
# another's span, and every spawn pairs inside its own file), so the property
# gets a fixture BUILT to straddle rather than an archive that happens not to.
# Each half needs a fixture built to DISCRIMINATE, and the first draft of this
# arm was not: it gave topic B its own spawn, which under the pipe simply
# overwrote A's orphan before B's record arrived, so both forms printed the same
# thing and the arm proved nothing. Verified by running a piped copy of the
# script against each fixture below — the shapes here are the ones where the two
# forms diverge.
#   half 1, park leak: topic A holds ONLY a park, timed inside topic B's span.
#   Merged, that park drops B's span; separate, it cannot see it.
wsA=$(mk_ws); wsB=$(mk_ws)
state_append "$wsA" ledger ferry "v=1 t=9100 event=park slice=01 reason=budget_wallclock" >/dev/null
state_append "$wsB" ledger ferry "v=1 t=9000 event=spawn slice=01 stage=spec mode=cold" >/dev/null
state_append "$wsB" ledger ferry "v=1 t=9300 event=record slice=01 stage=spec" >/dev/null
outd=$("$DC" "$wsA" "$wsB" 2>&1)
printf '%s\n' "$outd" | command grep -q 'kept 1, dropped 0' \
  && ok "a park in one topic cannot drop another topic's span (FILENAME is a topic, not '-')" \
  || bad "cross-topic park leak; got: $(printf '%s' "$outd" | command grep paired)"
#   half 2, orphan adoption: topic A holds a spawn whose record never arrived;
#   topic B holds a record for the SAME slice+stage and no spawn of its own.
#   Merged, B's record adopts A's spawn and reports a 71-minute span that never
#   happened; separate, neither pairs and the report has nothing to measure.
wsC=$(mk_ws); wsD=$(mk_ws)
state_append "$wsC" ledger ferry "v=1 t=5000 event=spawn slice=01 stage=spec mode=cold" >/dev/null
state_append "$wsD" ledger ferry "v=1 t=9300 event=record slice=01 stage=spec" >/dev/null
oute=$("$DC" "$wsC" "$wsD" 2>&1)
printf '%s\n' "$oute" | command grep -q 'paired 0 spawn->record spans' \
  && ok "…and an unpaired spawn never adopts another topic's record (0 spans, not one of 71m40)" \
  || bad "cross-topic spawn adoption; got: $(printf '%s' "$oute" | command grep paired)"
# cold is TWO things wearing one word — a contract price and a degradation —
# and the tax table is worth nothing without the split. `unrecorded` is asserted
# too, because every existing archive predates the field and a bucket that
# silently became `designed` would report degradations as design forever.
wsr=$(mk_ws)
state_append "$wsr" ledger ferry "v=1 t=100 event=spawn slice=01 stage=spec mode=cold mode_src=designed" >/dev/null
state_append "$wsr" ledger ferry "v=1 t=400 event=record slice=01 stage=spec" >/dev/null
state_append "$wsr" ledger ferry "v=1 t=500 event=spawn slice=01 stage=impl mode=cold mode_src=reactivate_failed" >/dev/null
state_append "$wsr" ledger ferry "v=1 t=1100 event=record slice=01 stage=impl" >/dev/null
state_append "$wsr" ledger ferry "v=1 t=1200 event=spawn slice=02 stage=impl mode=cold" >/dev/null
state_append "$wsr" ledger ferry "v=1 t=1500 event=record slice=02 stage=impl" >/dev/null
state_append "$wsr" ledger ferry "v=1 t=1600 event=spawn slice=03 stage=impl mode=warm mode_src=warm" >/dev/null
state_append "$wsr" ledger ferry "v=1 t=1700 event=record slice=03 stage=impl" >/dev/null
outr=$("$DC" "$wsr" 2>&1)
printf '%s\n' "$outr" | command grep -qE 'designed +1 +0\.1h +25\.0%' \
  && ok "cold splits by WHY: a contract-cold span is 'designed' and shares against COLD, not the total" \
  || bad "designed row wrong; got: $(printf '%s' "$outr" | command grep -A 3 'why ')"
printf '%s\n' "$outr" | command grep -qE 'reactivate_failed +1 +0\.2h +50\.0%' \
  && ok "…a warm-capable stage whose reuse failed is named as such, at half the cold hours here" \
  || bad "reactivate_failed row wrong; got: $(printf '%s' "$outr" | command grep -A 4 'why ')"
printf '%s\n' "$outr" | command grep -qE 'unrecorded +1 ' \
  && ok "…and a spawn row from before the field reads 'unrecorded', never silently 'designed'" \
  || bad "a mode_src-less spawn was bucketed; got: $(printf '%s' "$outr" | command grep -A 4 'why ')"
# scoped to the table's own rows: the surrounding prose says "warm" four times,
# and the first form of this arm grepped the whole report and failed on its own
# section header
command grep -qE '^   warm ' <<< "$(printf '%s\n' "$outr" | sed -n '/^   why /,$p')" \
  && bad "a WARM span leaked into the cold-by-why table" \
  || ok "known-bad: warm spans contribute nothing to the cold breakdown"
printf '%s\n' "$("$DC" "$wsm" 2>&1)" | command grep -q 'cold, by WHY' \
  && ok "the section prints wherever cold spans exist" \
  || bad "the cold-by-why section did not print for an all-cold fixture"
# The PARK WAIT — the one interval in the report measured in a person's
# response rather than an agent's. Two directions plus the never-resumed case,
# because that last one is where a silent drop would hide: a park with no
# following ferry_start is a topic still sitting there, and counting only the
# resumed ones would report the healthy subset as the whole.
wsp=$(mk_ws)
state_append "$wsp" ledger ferry "v=1 t=1000 event=park reason=class_u slice=01 stage=spec" >/dev/null
state_append "$wsp" ledger ferry "v=1 t=1120 event=ferry_start" >/dev/null
state_append "$wsp" ledger ferry "v=1 t=2000 event=park reason=blocked slice=02 stage=impl" >/dev/null
state_append "$wsp" ledger ferry "v=1 t=30000 event=ferry_start" >/dev/null
state_append "$wsp" ledger ferry "v=1 t=40000 event=park reason=operator_stop slice=03 stage=fix" >/dev/null
outp=$("$DC" "$wsp" 2>&1)
printf '%s\n' "$outp" | command grep -qE 'parks 3 · resumed 2 · never resumed 1' \
  && ok "a park with no following ferry_start is counted as NEVER RESUMED, not dropped from the sample" \
  || bad "park accounting wrong; got: $(printf '%s' "$outp" | command grep -i 'parks ')"
printf '%s\n' "$outp" | command grep -qE 'max 7h46m \(blocked\)' \
  && ok "…the longest wait is reported in HOURS with the reason that caused it (7h46m blocked)" \
  || bad "long wait mis-formatted or mis-attributed; got: $(printf '%s' "$outp" | command grep -i 'median ')"
printf '%s\n' "$outp" | command grep -qE 'over 6h: 1 of 2' \
  && ok "…and the over-6h count is the number a re-page interval would have to cap" \
  || bad "over-6h count wrong; got: $(printf '%s' "$outp" | command grep -i 'over 6h')"
wsp2=$(mk_ws)
state_append "$wsp2" ledger ferry "v=1 t=100 event=spawn slice=01 stage=spec mode=cold" >/dev/null
state_append "$wsp2" ledger ferry "v=1 t=400 event=record slice=01 stage=spec" >/dev/null
command grep -q '## parks' <<< "$("$DC" "$wsp2" 2>&1)" \
  && bad "the parks section printed for a topic that never parked" \
  || ok "known-bad: a topic with no parks prints no park section (absent is not a zero-length wait)"
# known-bad E: a SUB-SECOND warm median. Durations are integer seconds, so a
# stage whose warm spans all finish inside one second medians to 0 — and
# dividing by it is fatal in awk, which killed the report mid-table and took
# every section below it with it. Every fixture above uses 600s/200s spans, so
# none of them could see it; the defect surfaced only when the instrument was
# pointed at the suite's own drill workspace, where the mock agent answers
# instantly. The arm asserts the report SURVIVES and that the row is still
# there saying the ratio is undefined — a row that simply vanished would read
# as "this stage has no cold/warm pair", the opposite of what happened.
wsz=$(mk_ws)
state_append "$wsz" ledger ferry "v=1 t=100 event=spawn slice=01 stage=turnover mode=cold" >/dev/null
state_append "$wsz" ledger ferry "v=1 t=140 event=record slice=01 stage=turnover" >/dev/null
state_append "$wsz" ledger ferry "v=1 t=200 event=spawn slice=02 stage=turnover mode=warm" >/dev/null
state_append "$wsz" ledger ferry "v=1 t=200 event=record slice=02 stage=turnover" >/dev/null
outz=$("$DC" "$wsz" 2>&1); rcz=$?
[ "$rcz" -eq 0 ] && ! printf '%s\n' "$outz" | command grep -qi 'division by zero' \
  && ok "known-bad: a sub-second warm median does not kill the report (rc 0, no awk fatal)" \
  || bad "sub-second warm median still fatal (rc=$rcz): $(printf '%s' "$outz" | command grep -i 'zero\|fatal' | head -2)"
printf '%s\n' "$outz" | command grep -qE 'turnover +1 +0m40 +1 +0m00 +n/a' \
  && ok "…and the row stays, reading n/a rather than vanishing (absent is not undefined)" \
  || bad "the zero-median row is missing or mis-rendered; got: $(printf '%s' "$outz" | command grep turnover | tail -2)"
printf '%s\n' "$outz" | command grep -q 'cold, by WHY' \
  && ok "…and the sections BELOW the division still print (the fatal took them with it)" \
  || bad "the cold-by-why section is still missing after a zero warm median"

echo "-- a FAILING check's output survives a filtered terminal --"
# render() has always printed the whole failing log, so the runner was never
# quiet. The loss is on the READER's side, and it has happened three times: the
# previous round's lost red, the handoff's undiagnosed drill-backend, and one
# on the commit that added this arm. A remedy has to survive the filter that
# causes it — hence a file, announced in the SUMMARY, which is the one part of
# a run that `tail` keeps by construction.
kl=$(sc_tmpdir)
printf '  ok: setup\n  FAIL: the assertion a filtered terminal would have eaten\n  (2 assertions, 1 failed)\n' > "$kl/red.log"
printf '  ok: everything fine\n  (1 assertions, 0 failed)\n' > "$kl/green.log"
( SC_FAILDIR=""; PASS=0; FAIL=0; SKIP=0; FAILED_NAMES=""; SUM_SECS=0; MAX_SECS=0; MAX_NAME=""
  render greenone 0 1 "$kl/green.log" > /dev/null
  printf '%s' "$SC_FAILDIR" ) > "$kl/after-green"
[ ! -s "$kl/after-green" ] \
  && ok "a PASSING check keeps nothing (the directory is not created on a green run)" \
  || bad "a green run created a failure directory: $(cat "$kl/after-green")"
( SC_FAILDIR=""; PASS=0; FAIL=0; SKIP=0; FAILED_NAMES=""; SUM_SECS=0; MAX_SECS=0; MAX_NAME=""
  render redone 1 1 "$kl/red.log" > /dev/null
  printf '%s' "$SC_FAILDIR" ) > "$kl/after-red"
kept=$(cat "$kl/after-red")
[ -n "$kept" ] && [ -f "$kept/redone.log" ] \
  && ok "a FAILING check's log is kept, named for the check" \
  || bad "no log kept for a failing check (SC_FAILDIR='$kept')"
if [ -n "$kept" ] && [ -f "$kept/redone.log" ]; then
  case "$(cat "$kept/redone.log")" in
    *"the assertion a filtered terminal would have eaten"*)
      ok "…and it holds the ASSERTION, not just the verdict line" ;;
    *) bad "the kept log lost the assertion: $(cat "$kept/redone.log")" ;;
  esac
  case "$kept" in
    "$WF_ROOT"/*) bad "the failure directory is INSIDE the tree — check.sh asserts a run leaves the tree unchanged" ;;
    *) ok "…and it lives outside the tree, so a run still reads 'tree: unchanged'" ;;
  esac
  rm -rf "$kept"
fi
# BOUNDED: the directory outlives the run on purpose, so an unbounded keep is a
# leak — 78 of them accumulated in the session that wrote the mechanism. Driven
# in an ISOLATED TMPDIR, never the real one, and the arm checks what the prune
# must NOT touch as well as what it must.
kb=$(sc_tmpdir)/keepbound; mkdir -p "$kb"
for x in a b c d e f g h i j k l; do mkdir -p "$kb/dwsc-failed.${x}${x}${x}${x}${x}${x}"; touch "$kb/dwsc-failed.${x}${x}${x}${x}${x}${x}/x.log"; sleep 0.01; done
mkdir -p "$kb/dwsc-KEEPME"; touch "$kb/dwsc-failed.notadir"
n_before=$(ls -d "$kb"/dwsc-failed.?????? 2>/dev/null | command grep -c .)
precond "the prune fixture has more directories than the bound (saw $n_before, keep 10)" test "$n_before" -gt 10
( TMPDIR="$kb"; SC_FAILDIR=""; SC_FAILDIR_KEEP=10
  printf 'ok\n' > "$kb/src.log"; _keep_failing_log probe "$kb/src.log" ) > /dev/null 2>&1
n_after=$(ls -d "$kb"/dwsc-failed.?????? 2>/dev/null | command grep -c .)
[ "$n_after" -eq 10 ] \
  && ok "the failing-run directories are bounded at SC_FAILDIR_KEEP ($n_before + 1 new -> $n_after)" \
  || bad "prune left $n_after directories, want 10"
[ -d "$kb/dwsc-KEEPME" ] && [ -e "$kb/dwsc-failed.notadir" ] \
  && ok "…and it touches neither a neighbouring directory nor a non-directory that matches the prefix" \
  || bad "the prune deleted something outside its own shape: KEEPME=$([ -d "$kb/dwsc-KEEPME" ] && echo kept || echo GONE) notadir=$([ -e "$kb/dwsc-failed.notadir" ] && echo kept || echo GONE)"
# the SURVIVORS must be the newest, or a bound that keeps the wrong ten is worse
# than none: the evidence a reader wants is the run that just failed.
[ -d "$kb/dwsc-failed.llllll" ] && [ ! -d "$kb/dwsc-failed.aaaaaa" ] \
  && ok "…and the ten it keeps are the NEWEST (oldest pruned first)" \
  || bad "prune kept the wrong end: newest present=$([ -d "$kb/dwsc-failed.llllll" ] && echo yes || echo no) oldest present=$([ -d "$kb/dwsc-failed.aaaaaa" ] && echo yes || echo no)"

# the summary must ANNOUNCE it, guarded — the file is useless if a tailed run
# does not learn the path, and that is the whole failure mode being fixed.
ann=$(command grep -nE 'failing output kept' "$SC_ROOT/check.sh")
[ -n "$ann" ] \
  && ok "the summary announces the kept path (the end of a run is what a tail keeps)" \
  || bad "check.sh never prints where the failing output went"
printf '%s' "$ann" | command grep -qF '[ -n "$SC_FAILDIR" ]' \
  && ok "…and the announcement is guarded, so a clean run stays silent" \
  || bad "the announcement is unguarded: $ann"


check_done
