#!/usr/bin/env bash
# 36-verbs-readers — the behaviour suites of the two reader verbs this tree
# grew in the monitor batch: peek (the read-only look) and status --rounds
# (the per-round clock). Split out of 35-verbs as that file APPROACHED
# cap.selftest_file (972 of 1000 at the split, measured per-commit) — but the
# reason is the seam, not the number: 35-verbs is the DOC-CLOSURE check
# (docs <-> dispatch <-> architecture §9); these arms are behaviour, and each
# rule component here is mutation-killed by name. (The OTHER split this batch
# made — launch.sh -> lib/readers.sh — WAS cap-forced: the inline form
# reconstructs to ~850 lines against cap.source_file=800 (867 as measured
# includes the extracted file's own 20-line header; either way above cap).)
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/fixtures/lib.sh"
. "$RS/lib/state.sh"
LAUNCH="$RS/launch.sh"

base=$(sc_tmpdir)
read -r repo branch < <(mk_repo "$base/repo")

echo "-- peek: the read-only look (one pane per session, fault != absent) --"
# The look half of the look/type split: capture-pane makes no client and cannot
# change geometry, so peek is the verb for "what is it saying" without the harm
# attach carries. The reader branches are the tree's standing discipline: a
# corrupt surface refuses as CORRUPT (never "nothing to look at"), present-empty
# is not absent (close-out clears the surface), a gone session points at the
# pane log it left, and --attach PRINTS the command instead of running it.
# (state_set ALWAYS gets a piped or /dev-null stdin here: it reads its body
# from stdin, and an unpiped call inside this check inherits the SUITE
# RUNNER's name pipe — measured: one unpiped call ate the remaining check
# names and nine checks silently never launched.)
pk=$(mk_ws "$base" peektopic "$repo" "$branch")
( . "$RS/lib/state.sh"
  printf 'role=author name=delivery-peektopic-01-spec pane_pid=1 pane_start=1 server_pid=1 server_start=1 socket=/nonexistent/x nonce=n1 mode=cold backend=claude t=1\n' \
    | state_set "$pk" sessions ferry ) > /dev/null
corrupt_surface "$pk" sessions
out=$("$LAUNCH" peek "$pk" 2>&1); rc=$?
[ $rc -ne 0 ] && printf '%s\n' "$out" | command grep -q 'CORRUPT' \
  && ok "peek over a CORRUPT sessions surface refuses as corrupt (rc=$rc)" \
  || bad "rc=$rc over a corrupt sessions surface: $out"
pk2=$(mk_ws "$base" peeknever "$repo" "$branch")
out=$("$LAUNCH" peek "$pk2" 2>&1); rc=$?
[ $rc -eq 0 ] && printf '%s\n' "$out" | command grep -q 'topic has never started' \
  && ok "peek on a never-started topic says so (absent, not a fault)" \
  || bad "rc=$rc on a never-started topic: $out"
pk3=$(mk_ws "$base" peekempty "$repo" "$branch")
( . "$RS/lib/state.sh"; state_set "$pk3" sessions ferry < /dev/null ) > /dev/null
out=$("$LAUNCH" peek "$pk3" 2>&1); rc=$?
[ $rc -eq 0 ] && printf '%s\n' "$out" | command grep -q 'surface is EMPTY — sessions were cleared at close-out' \
  && ok "peek over a present-but-EMPTY surface says sessions were cleared at close-out (empty != absent)" \
  || bad "rc=$rc over an empty sessions surface: $out"
pk4=$(mk_ws "$base" peekgone "$repo" "$branch")
( . "$RS/lib/state.sh"
  printf 'role=author name=delivery-peekgone-01-spec pane_pid=1 pane_start=1 server_pid=1 server_start=1 socket=/nonexistent/x nonce=n1 mode=cold backend=claude t=1\n' \
    | state_set "$pk4" sessions ferry ) > /dev/null
mkdir -p "$pk4/.runtime/logs"
printf 'stale pane text\n' > "$pk4/.runtime/logs/01-spec.log"
out=$("$LAUNCH" peek "$pk4" 2>&1); rc=$?
[ $rc -eq 0 ] && printf '%s\n' "$out" | command grep -q 'logs/01-spec.log' \
  && ok "a row whose session is GONE points at the pane log it left (name minus the delivery-<topic>- prefix)" \
  || bad "a gone session did not point at its pane log: $out"
out=$("$LAUNCH" peek "$pk4" --attach 2>&1); rc=$?
[ $rc -eq 0 ] && printf '%s\n' "$out" | command grep -q 'session is gone' \
  && printf '%s\n' "$out" | command grep -q 'logs/01-spec.log' \
  && ! printf '%s\n' "$out" | command grep -q 'attach -r' \
  && ok "--attach over a GONE session points at the pane log, never the dead socket's command (an unrunnable line is worse than nothing — same rule as pending)" \
  || bad "--attach printed something runnable or nothing over a gone session: $out"
# A pending socket owes a statement, not a command — the monitor's own rule for
# its attach block. --attach is exactly the mode whose output gets copied, so
# an unrunnable line here is worse than nothing.
pk5=$(mk_ws "$base" peekpending "$repo" "$branch")
( . "$RS/lib/state.sh"
  printf 'role=author name=delivery-peekpending-01-spec pane_pid=1 pane_start=1 server_pid=1 server_start=1 socket=pending nonce=n1 mode=cold backend=claude t=1\n' \
    | state_set "$pk5" sessions ferry ) > /dev/null
out=$("$LAUNCH" peek "$pk5" --attach 2>&1); rc=$?
[ $rc -eq 0 ] && printf '%s\n' "$out" | command grep -q 'still starting' \
  && ! printf '%s\n' "$out" | command grep -q 'attach -r' \
  && ok "--attach over a PENDING socket says 'still starting' and prints NO command (never an unrunnable line)" \
  || bad "--attach printed something runnable or nothing over a pending socket: $out"
out=$(timeout 3 "$LAUNCH" peek "$pk5" --follow 2>&1 || true)
printf '%s\n' "$out" | command grep -q 'still starting' \
  && ok "--follow renders the pending session's statement too (the roster path is shared)" \
  || bad "--follow over a pending session: $(printf '%s\n' "$out" | tail -2 | tr '\n' ' ')"
out=$(timeout 3 "$LAUNCH" peek "$pk2" --follow 2>&1 || true)
printf '%s\n' "$out" | command grep -q 'never started' \
  && ok "--follow on an absent surface SAYS so every tick (watching for the topic to come up), never a silent blank" \
  || bad "--follow over an absent surface went silent: $(printf '%s\n' "$out" | tail -1)"
# A role filter with nothing to show SAYS so and names what the surface holds —
# silence is the one answer this verb must never give (empty rc=0 is
# indistinguishable from not-running or cleared-at-close-out). And implementer
# is a sub-agent inside the author's pane: no sessions row will ever carry it
# (the surface is keyed by owed-stage role), so it answers where it lives.
out=$("$LAUNCH" peek "$pk4" reviewer 2>&1); rc=$?
[ $rc -eq 0 ] && printf '%s\n' "$out" | command grep -q 'no reviewer session' \
  && printf '%s\n' "$out" | command grep -q 'holds: author' \
  && ok "a filter that matches nothing SAYS so and names what the surface holds (not silence)" \
  || bad "filtered-to-nothing peek: rc=$rc out='$out'"
out=$("$LAUNCH" peek "$pk4" implementer 2>&1); rc=$?
[ $rc -eq 0 ] && printf '%s\n' "$out" | command grep -q 'sub-agent' \
  && printf '%s\n' "$out" | command grep -q 'peek .*author' \
  && ok "peek implementer explains itself (sub-agent inside the author pane — never a sessions row) instead of an empty screen" \
  || bad "peek implementer: rc=$rc out='$out'"
# The explanation is CONDITIONAL on the surface really holding no implementer
# row: the day the sessions surface's keying grows one, the filter must SHOW
# it, not explain it away — a pre-read branch would hide real rows behind a
# convenience answer (silent-hide, the one thing this tree never tolerates).
pk7=$(mk_ws "$base" peekimplrow "$repo" "$branch")
( . "$RS/lib/state.sh"
  printf 'role=implementer name=delivery-peekimplrow-01-impl pane_pid=1 pane_start=1 server_pid=1 server_start=1 socket=/nonexistent/i nonce=n7 mode=cold backend=claude t=1\n' \
    | state_set "$pk7" sessions ferry ) > /dev/null
out=$("$LAUNCH" peek "$pk7" implementer 2>&1); rc=$?
[ $rc -eq 0 ] && printf '%s\n' "$out" | command grep -q 'implementer · delivery-peekimplrow-01-impl' \
  && ! printf '%s\n' "$out" | command grep -q 'sub-agent' \
  && ok "a surface that HAS an implementer row shows it — the explanation yields to real data, never hides it" \
  || bad "peek implementer over a surface holding the row: rc=$rc out='$out'"
# …and a row whose role merely STARTS WITH the asked one is named, never
# explained away. The guard at the top of verb_peek greps the PREFIX
# `^role=implementer` while this filter is anchored `^role=$PEEK_ROLE( |$)`, and
# that difference is load-bearing in one direction only: the wider guard means
# the explanation fires ONLY when the filter would also miss, so a
# `role=implementer_sub` row reaches the honest line. A debt row recorded the drift
# and prescribed unifying the two expressions byte-for-byte; that was MEASURED
# here and it regresses — anchoring the guard makes the explanation fire over
# `implementer_sub` and the row disappears behind it, which is the silent-hide
# the guard's own comment forbids. So the relation is pinned rather than
# removed, and this arm is what reds if either predicate moves alone.
pk8=$(mk_ws "$base" peeksubrow "$repo" "$branch")
( . "$RS/lib/state.sh"
  printf 'role=implementer_sub name=delivery-peeksubrow-01-impl pane_pid=1 pane_start=1 server_pid=1 server_start=1 socket=/nonexistent/i nonce=n8 mode=cold backend=claude t=1\n' \
    | state_set "$pk8" sessions ferry ) > /dev/null
out=$("$LAUNCH" peek "$pk8" implementer 2>&1); rc=$?
[ $rc -eq 0 ] && printf '%s\n' "$out" | command grep -q 'the surface holds: implementer_sub' \
  && ! printf '%s\n' "$out" | command grep -q 'sub-agent' \
  && ok "a role that merely STARTS WITH the asked one is NAMED honestly, not explained away (the guard's prefix must stay wider than the filter's anchor)" \
  || bad "peek implementer over a surface holding only implementer_sub: rc=$rc out='$out'"
assert_rc 2 "peek with TWO roles refuses, naming both" -- "$LAUNCH" peek "$pk4" author reviewer
assert_out_has "one role only" "the refusal names the shape (same policy as --follow/--attach)"
assert_rc 2 "status with two alternative flags refuses (no silent precedence)" -- "$LAUNCH" status "$pk4" --slices --rounds
assert_out_has "pick one" "the refusal names the clash"
assert_rc 2 "peek with an unknown arg refuses, naming the usage" -- "$LAUNCH" peek "$pk4" --bogus
assert_out_has "usage: peek" "the refusal names the verb's shape"
assert_rc 2 "peek --follow --attach refuses (nothing to refresh in attach mode)" -- "$LAUNCH" peek "$pk4" --follow --attach
assert_out_has "pick one" "the refusal names the incompatibility"
assert_rc 2 "peek with the flag BEFORE the workspace refuses (need_ws names it)" -- "$LAUNCH" peek --follow "$pk4"
assert_out_has "is not a directory" "the refusal names the misplaced argument"
# Silence is the one answer this verb must never give — and the outer guards
# decide on role PRESENCE while the printer needs a printable name=, so a
# surface whose rows lack name= passed every guard and printed nothing
# (measured: rc=0, zero bytes, in all of peek / peek author / peek --attach).
# The counters inside _peek_once are the belt under that predicate gap.
pk6=$(mk_ws "$base" peeknameless "$repo" "$branch")
( . "$RS/lib/state.sh"
  printf 'role=author pane_pid=1 pane_start=1 server_pid=1 server_start=1 socket=/nonexistent/x nonce=n1 mode=cold backend=claude t=1\n' \
    | state_set "$pk6" sessions ferry ) > /dev/null
for shape in "plain" "author" "--attach"; do
  if [ "$shape" = "plain" ]; then out=$("$LAUNCH" peek "$pk6" 2>&1)
  else out=$("$LAUNCH" peek "$pk6" $shape 2>&1); fi
  rc=$?
  [ $rc -eq 0 ] && [ -n "$out" ] && printf '%s\n' "$out" | command grep -q 'no name=' \
    && ok "peek ($shape) over a NAMELESS row says so — never a silent rc=0" \
    || bad "peek ($shape) went silent or wrong: rc=$rc out='$out'"
done
# The OTHER half of the no-silence belt: zero rows SHOWN. A filtered peek over
# a surface whose only matching row is nameless prints BOTH messages — the
# nameless count and "nothing was shown". Disabling the zero-shown branch left
# 168 green (the nameless arms only grep the skipped message), so this path
# had no guard of its own until now.
( . "$RS/lib/state.sh"
  printf 'role=reviewer name=delivery-peekgone-01-precheck pane_pid=1 pane_start=1 server_pid=1 server_start=1 socket=/nonexistent/x nonce=n2 mode=cold backend=claude t=1\nrole=author pane_pid=9\n' \
    | state_set "$pk4" sessions ferry ) > /dev/null
out=$("$LAUNCH" peek "$pk4" author 2>&1); rc=$?
[ $rc -eq 0 ] && printf '%s\n' "$out" | command grep -q 'no name=' \
  && printf '%s\n' "$out" | command grep -q 'nothing was shown' \
  && ok "a filtered peek whose only match is nameless says BOTH: the nameless row AND 'nothing was shown' (the zero-shown half of the belt)" \
  || bad "the zero-shown path: rc=$rc out='$out'"
# and the skipped count follows the FILTER: a nameless row of a role the
# operator did not ask about is not reported
out=$("$LAUNCH" peek "$pk4" reviewer 2>&1); rc=$?
# ! grep -q, not grep -qv: -qv passed while the leak WAS present (other lines
# simply lacked the phrase) — the same vacuity shape F1 pinned, caught here by
# re-running this arm own mutation.
[ $rc -eq 0 ] && printf '%s\n' "$out" | command grep -q '──── reviewer' \
  && ! printf '%s\n' "$out" | command grep -q 'no name=' \
  && ok "the nameless count follows the filter (peek reviewer does not report the unrelated nameless author row)" \
  || bad "unfiltered skip count leaked into a filtered peek: $out"
out=$(timeout 3 "$LAUNCH" peek "$pk5" reviewer --follow 2>&1 || true)
printf '%s\n' "$out" | command grep -q 'no reviewer session' \
  && ok "--follow with a filter that matches nothing SAYS so on every tick (the follow path shares the no-match branch)" \
  || bad "--follow filtered-to-nothing went silent: $(printf '%s\n' "$out" | tail -1)"

echo "-- status --rounds: the per-stage per-round clock, from the ledger's own t= fields --"
# A pure reader over the ledger: a round OPENS at enter and CLOSES at the next
# advance for the same (slice, stage); a park inside the round is annotated
# with its reason and the gap it held (park t -> the next event for that
# stage). The wall of a parked round includes its park gap on purpose — that
# is the "why did this take so long" the reader exists to answer — and the
# stage subtotal says how much of the wall was park.
rws=$(mk_ws "$base" roundstopic "$repo" "$branch")
rt=$(( $(date +%s) - 7200 ))
( . "$RS/lib/state.sh"
  state_append "$rws" ledger ferry "v=1 t=$rt event=enter slice=00 stage=split round=1"
  state_append "$rws" ledger ferry "v=1 t=$((rt + 600)) event=advance slice=00 stage=split verdict=done target=split-check"
  state_append "$rws" ledger ferry "v=1 t=$((rt + 601)) event=enter slice=01 stage=spec round=1"
  state_append "$rws" ledger ferry "v=1 t=$((rt + 602)) event=spawn slice=01 stage=spec round=1 attempt=1 mode=cold mode_src=designed session=s backend=claude model=m effort=low"
  state_append "$rws" ledger ferry "v=1 t=$((rt + 900)) event=park reason=testpark slice=01 stage=spec detail=fixture"
  state_append "$rws" ledger ferry "v=1 t=$((rt + 1200)) event=advance slice=01 stage=spec verdict=drafted target=precheck"
  state_append "$rws" ledger ferry "v=1 t=$((rt + 1201)) event=enter slice=01 stage=precheck round=1" ) > /dev/null
out=$("$LAUNCH" status "$rws" --rounds 2>&1); rc=$?
[ $rc -eq 0 ] && printf '%s\n' "$out" | command grep -q 'slice 00 · split' \
  && ok "status --rounds renders (rc=0), grouped by slice · stage" \
  || bad "rc=$rc: $(printf '%s\n' "$out" | head -3 | tr '\n' ' ')"
printf '%s\n' "$out" | command grep -qE 'r1 +[0-9-]+ [0-9:]+ +10m +done -> split-check' \
  && ok "a closed round shows its wall (enter t -> advance t = 10m) and its verdict -> target" \
  || bad "the closed round's row: $(printf '%s\n' "$out" | command grep 'split' | head -2 | tr '\n' ' ')"
printf '%s\n' "$out" | command grep -qE 'parked 1x testpark 5m' \
  && ok "a park inside a round is annotated with its reason and its gap (park t -> next event for the stage = 5m)" \
  || bad "the park annotation: $(printf '%s\n' "$out" | command grep -E 'spec|parked' | head -2 | tr '\n' ' ')"
printf '%s\n' "$out" | command grep -qE 'RUNNING' \
  && ok "a round with enter and no advance renders RUNNING (the live round), not a fabricated verdict" \
  || bad "no RUNNING row for the open round: $(printf '%s\n' "$out" | tail -3 | tr '\n' ' ')"
printf '%s\n' "$out" | command grep -qE '= wall 10m, of which parked 0s' \
  && ok "the stage subtotal separates wall from parked (a parked stage reads as parked, not as slow)" \
  || bad "the subtotal line: $(printf '%s\n' "$out" | command grep '= wall' | head -2 | tr '\n' ' ')"
# A park still open at EOF is the reader's most important case — the topic is
# parked RIGHT NOW when the owner asks why it is taking so long. The ongoing
# gap must count as parked and the round must say PARKED, not RUNNING (the
# first version showed RUNNING with parked 0s over a two-hour park).
rws3=$(mk_ws "$base" roundspark "$repo" "$branch")
pt=$(( $(date +%s) - 3600 ))
( . "$RS/lib/state.sh"
  state_append "$rws3" ledger ferry "v=1 t=$pt event=enter slice=01 stage=precheck round=1"
  state_append "$rws3" ledger ferry "v=1 t=$((pt + 300)) event=park reason=class_u slice=01 stage=precheck detail=fixture" ) > /dev/null
out=$("$LAUNCH" status "$rws3" --rounds 2>&1); rc=$?
[ $rc -eq 0 ] && printf '%s\n' "$out" | command grep -q 'PARKED class_u' \
  && ok "a round parked RIGHT NOW says PARKED <reason>, not RUNNING" \
  || bad "the parked round's verdict: $(printf '%s\n' "$out" | command grep 'r1' | head -1)"
printf '%s\n' "$out" | command grep -qE 'of which parked 5[0-9]m' \
  && ok "and the ONGOING park gap counts as parked (enter+300s park held to now ≈ 55m of a 60m wall)" \
  || bad "the ongoing park gap: $(printf '%s\n' "$out" | command grep '= wall' | head -1)"
# Two closing-rule shapes the first fixture does not reach: a WARM resume does
# no spawn, so the stage's next event is the resumed work's own record — the
# park must close at the first ferry_start, not swallow the resumed work; and a
# park whose row carries no stage (workflow_changed at a relaunch) is real park
# time — reported in a tail line, never dropped.
rws4=$(mk_ws "$base" roundswarm "$repo" "$branch")
wt=$(( $(date +%s) - 7200 ))
( . "$RS/lib/state.sh"
  state_append "$rws4" ledger ferry "v=1 t=$wt event=enter slice=01 stage=spec round=1"
  state_append "$rws4" ledger ferry "v=1 t=$((wt + 60)) event=park reason=operator_stop slice=01 stage=spec detail=fixture"
  state_append "$rws4" ledger ferry "v=1 t=$((wt + 360)) event=ferry_start pid=99"
  state_append "$rws4" ledger ferry "v=1 t=$((wt + 1800)) event=record slice=01 stage=spec nonce=x"
  state_append "$rws4" ledger ferry "v=1 t=$((wt + 1800)) event=advance slice=01 stage=spec verdict=drafted target=precheck"
  state_append "$rws4" ledger ferry "v=1 t=$((wt + 1810)) event=park reason=workflow_changed slice= stage= detail=fixture pin moved"
  state_append "$rws4" ledger ferry "v=1 t=$((wt + 2400)) event=ferry_start pid=100"
  state_append "$rws4" ledger ferry "v=1 t=$((wt + 2500)) event=enter slice=01 stage=precheck round=1" ) > /dev/null
out=$("$LAUNCH" status "$rws4" --rounds 2>&1); rc=$?
[ $rc -eq 0 ] && printf '%s\n' "$out" | command grep -qE 'parked 1x operator_stop 5m' \
  && ok "a WARM-resume park closes at the first ferry_start (5m), not at the resumed work's record (would read 29m of work as park)" \
  || bad "the warm-resume park gap: $(printf '%s\n' "$out" | command grep 'r1' | head -1)"
printf '%s\n' "$out" | command grep -qE 'park\(s\) outside any round \(workflow_changed\) — 9m' \
  && ok "a park whose row carries no stage is REPORTED in the tail line with its reason and gap (9m), never dropped" \
  || bad "the stage-less tail line: $(printf '%s\n' "$out" | command grep 'outside any round')"
# A park arriving while another is still open (measured on a real ledger:
# park(operator_stop) then park(workflow_changed) with no resume between — the
# second park's t is the moment the first halt was discharged). The first gap
# must close at the superseding park, not at the later ferry_start — and the
# superseding stage-less park must still register (an earlier draft lost it
# behind the occupied open-park slot).
rws5=$(mk_ws "$base" roundssup "$repo" "$branch")
st5=$(( $(date +%s) - 7200 ))
( . "$RS/lib/state.sh"
  state_append "$rws5" ledger ferry "v=1 t=$st5 event=enter slice=01 stage=spec round=1"
  state_append "$rws5" ledger ferry "v=1 t=$((st5 + 60)) event=park reason=operator_stop slice=01 stage=spec detail=fixture"
  state_append "$rws5" ledger ferry "v=1 t=$((st5 + 360)) event=park reason=workflow_changed slice= stage= detail=fixture pin moved"
  state_append "$rws5" ledger ferry "v=1 t=$((st5 + 460)) event=ferry_start pid=101"
  state_append "$rws5" ledger ferry "v=1 t=$((st5 + 470)) event=enter slice=01 stage=spec round=2"
  state_append "$rws5" ledger ferry "v=1 t=$((st5 + 600)) event=advance slice=01 stage=spec verdict=drafted target=precheck" ) > /dev/null
out=$("$LAUNCH" status "$rws5" --rounds 2>&1); rc=$?
[ $rc -eq 0 ] && printf '%s\n' "$out" | command grep -qE 'r1 .* parked 1x operator_stop 5m' \
  && ok "a park SUPERSEDED by a later park closes at that park's t (5m), not at the later ferry_start (6m40s)" \
  || bad "the superseded park's gap: $(printf '%s\n' "$out" | command grep 'r1' | head -1)"
printf '%s\n' "$out" | command grep -qE 'park\(s\) outside any round \(workflow_changed\) — 1m' \
  && ok "the superseding stage-less park itself registers (1m40s renders 1m) — not lost behind the occupied slot" \
  || bad "the superseding stage-less park: $(printf '%s\n' "$out" | command grep 'outside any round')"
# An out-of-round park does NOT close at a bare record: a foreign slice's
# record between the park and the ferry_start is not a resume — the gap must
# run to the ferry_start (a first draft closed at ANY event and read 10s
# where the halt stood 10m40s). An orphan KEYED park (its stage has no open
# round — spawn+park with no enter) rides the same tail line, named with its
# stage; a 0-round header beside it must not read as "nothing parked".
rws6=$(mk_ws "$base" roundsearly "$repo" "$branch")
e6=$(( $(date +%s) - 7200 ))
( . "$RS/lib/state.sh"
  state_append "$rws6" ledger ferry "v=1 t=$e6 event=enter slice=01 stage=spec round=1"
  state_append "$rws6" ledger ferry "v=1 t=$((e6 + 100)) event=advance slice=01 stage=spec verdict=drafted target=precheck"
  state_append "$rws6" ledger ferry "v=1 t=$((e6 + 200)) event=park reason=workflow_changed slice= stage= detail=x"
  state_append "$rws6" ledger ferry "v=1 t=$((e6 + 210)) event=record slice=09 stage=spec nonce=z"
  state_append "$rws6" ledger ferry "v=1 t=$((e6 + 840)) event=ferry_start pid=7" ) > /dev/null
out=$("$LAUNCH" status "$rws6" --rounds 2>&1); rc=$?
[ $rc -eq 0 ] && printf '%s\n' "$out" | command grep -qE 'outside any round \(workflow_changed\) — 10m' \
  && ok "an out-of-round park closes at the ferry_start (10m40s renders 10m), NOT at a foreign record 10s after it" \
  || bad "the early-close gap: $(printf '%s\n' "$out" | command grep 'outside any round')"
rws7=$(mk_ws "$base" roundsorphan "$repo" "$branch")
o7=$(( $(date +%s) - 3600 ))
( . "$RS/lib/state.sh"
  state_append "$rws7" ledger ferry "v=1 t=$o7 event=spawn slice=03 stage=impl round=1 attempt=1 mode=cold session=s backend=claude model=m effort=low"
  state_append "$rws7" ledger ferry "v=1 t=$o7 event=park reason=operator_stop slice=03 stage=impl detail=fixture" ) > /dev/null
out=$("$LAUNCH" status "$rws7" --rounds 2>&1); rc=$?
[ $rc -eq 0 ] && printf '%s\n' "$out" | command grep -qE 'outside any round \(03·impl operator_stop\) — [0-9]+[hm]' \
  && ok "an orphan KEYED park (no round open for its stage) rides the tail line NAMED with its stage — never dropped behind a 0-round header" \
  || bad "the orphan park: $(printf '%s\n' "$out" | command grep 'outside any round')"
# A round superseded by a later enter of the same stage (no advance between)
# is marked, not silently reshaped; a finished ledger freezes its open rounds
# at the completion row, so archived readings are reproducible — and an open
# round behind the frontier says OPEN, not RUNNING (the ledger cannot claim
# liveness for a round that later events passed by).
rws8=$(mk_ws "$base" roundssupersed "$repo" "$branch")
s8=$(( $(date +%s) - 7200 ))
( . "$RS/lib/state.sh"
  state_append "$rws8" ledger ferry "v=1 t=$s8 event=enter slice=01 stage=spec round=1"
  state_append "$rws8" ledger ferry "v=1 t=$((s8 + 300)) event=enter slice=01 stage=spec round=2"
  state_append "$rws8" ledger ferry "v=1 t=$((s8 + 900)) event=advance slice=01 stage=spec verdict=drafted target=precheck"
  state_append "$rws8" ledger ferry "v=1 t=$((s8 + 910)) event=enter slice=02 stage=spec round=1"
  state_append "$rws8" ledger ferry "v=1 t=$((s8 + 1800)) event=complete topic=fixture" ) > /dev/null
out=$("$LAUNCH" status "$rws8" --rounds 2>&1); rc=$?
[ $rc -eq 0 ] && printf '%s\n' "$out" | command grep -q '(superseded)' \
  && ok "a round superseded by a later enter of the same stage is MARKED (superseded), not silently reshaped" \
  || bad "no superseded marker: $(printf '%s\n' "$out" | command grep 'r1' | head -1)"
printf '%s\n' "$out" | command grep -qE 'r1 +[0-9-]+ [0-9:]+ +14m +OPEN' \
  && ok "an open round behind the frontier on a COMPLETED ledger says OPEN and freezes at the completion row (enter 910 -> complete 1800 = 890s = 14m, not now-based)" \
  || bad "the frozen OPEN round: $(printf '%s\n' "$out" | command grep 'slice 02' -A1)"
# ! grep -q, NEVER grep -qv here: -qv asks "does ANY line lack RUNNING" — the
# vacuous form passed while slice 02 rendered RUNNING on a completed ledger,
# because some OTHER line (a subtotal, another round) lacked the word. This
# arm's own mutation is what proved it empty.
! printf '%s\n' "$out" | command grep -q 'RUNNING' \
  && ok "a completed ledger renders no round as RUNNING (liveness is not the ledger claim to make about a finished topic)" \
  || bad "a RUNNING verdict on a completed ledger: $(printf '%s\n' "$out" | command grep RUNNING)"
# An out-of-round park whose next closing event is an ENTER (not a park, not a
# ferry_start, not a same-key event): the enter is the resume signal and the
# gap must close there. This is the one shape that distinguishes the enter
# closer from every other component — an early draft dropped it and every
# other arm stayed green, because their fixtures all closed at ferry_start.
rws9=$(mk_ws "$base" roundsenter "$repo" "$branch")
n9=$(( $(date +%s) - 7200 ))
( . "$RS/lib/state.sh"
  state_append "$rws9" ledger ferry "v=1 t=$n9 event=enter slice=01 stage=spec round=1"
  state_append "$rws9" ledger ferry "v=1 t=$((n9 + 100)) event=advance slice=01 stage=spec verdict=drafted target=precheck"
  state_append "$rws9" ledger ferry "v=1 t=$((n9 + 200)) event=park reason=workflow_changed slice= stage= detail=x"
  state_append "$rws9" ledger ferry "v=1 t=$((n9 + 500)) event=enter slice=01 stage=precheck round=1"
  state_append "$rws9" ledger ferry "v=1 t=$((n9 + 900)) event=advance slice=01 stage=precheck verdict=ready target=impl" ) > /dev/null
out=$("$LAUNCH" status "$rws9" --rounds 2>&1); rc=$?
[ $rc -eq 0 ] && printf '%s\n' "$out" | command grep -qE 'outside any round \(workflow_changed\) — 5m' \
  && ok "an out-of-round park closes at the next ENTER (5m) — the one shape that pins the enter closer (dropping it reads ~1h50m to EOF)" \
  || bad "the enter-closed gap: $(printf '%s\n' "$out" | command grep 'outside any round')"
# A different stage's ENTER does not close THIS stage's in-round park: the
# enter-closer is restricted to OUT-OF-ROUND (@) parks. Broadening it to any
# enter reds here (the in-round park would close at the foreign enter and read
# a small gap, not the EOF PARKED gap). NOTE: this arm does NOT pin the
# same-key guard — that is pinned by the advance/spawn/record closer arms
# (mutation: drop `key == oparkkey` reds the 5m park-annotation arm). An arm
# only claims what its own mutation kills.
rws13=$(mk_ws "$base" roundsforeignkey "$repo" "$branch")
k13=$(( $(date +%s) - 3600 ))
( . "$RS/lib/state.sh"
  state_append "$rws13" ledger ferry "v=1 t=$k13 event=enter slice=01 stage=spec round=1"
  state_append "$rws13" ledger ferry "v=1 t=$((k13 + 100)) event=park reason=blocked slice=01 stage=spec detail=fixture"
  state_append "$rws13" ledger ferry "v=1 t=$((k13 + 300)) event=enter slice=02 stage=spec round=1" ) > /dev/null
out=$("$LAUNCH" status "$rws13" --rounds 2>&1); rc=$?
[ $rc -eq 0 ] && printf '%s\n' "$out" | command grep -A1 'slice 01 · spec' | command grep -q 'PARKED blocked' \
  && printf '%s\n' "$out" | command grep -A1 'slice 01 · spec' | command grep -qE 'parked 1x blocked 5[0-9]m' \
  && ok "a foreign-stage ENTER does not close an in-round park (the enter closer is @-only; slice 01 reads PARKED to EOF, not a 3m40s gap)" \
  || bad "foreign-key handling: $(printf '%s\n' "$out" | command grep -A1 'slice 01' | tr '\n' ' ')"
# The frontier is ONE round, even at a timestamp tie: a record for spec and an
# enter for impl in the same second leave both rounds open with the same
# last-event time — the earlier timestamp-comparison form rendered BOTH as
# RUNNING; the frontier names the round the ledger actually sits at (the
# later event's). Writer-reachable: parks and enters carry second-resolution
# t=, and a same-second park-then-enter across stages is one ruling away.
rws14=$(mk_ws "$base" roundstie "$repo" "$branch")
tie=$(( $(date +%s) - 600 ))
( . "$RS/lib/state.sh"
  state_append "$rws14" ledger ferry "v=1 t=$((tie - 300)) event=enter slice=01 stage=spec round=1"
  state_append "$rws14" ledger ferry "v=1 t=$tie event=record slice=01 stage=spec nonce=t"
  state_append "$rws14" ledger ferry "v=1 t=$tie event=enter slice=01 stage=impl round=1" ) > /dev/null
out=$("$LAUNCH" status "$rws14" --rounds 2>&1); rc=$?
tie_running=$(printf '%s\n' "$out" | command grep -c 'RUNNING')
[ $rc -eq 0 ] && [ "$tie_running" -eq 1 ] \
  && printf '%s\n' "$out" | command grep -A1 'slice 01 · impl' | command grep -q 'RUNNING' \
  && printf '%s\n' "$out" | command grep -A1 'slice 01 · spec' | command grep -q 'OPEN' \
  && ok "at a same-second tie exactly ONE round is RUNNING — the later event's (impl), the other says OPEN" \
  || bad "the tie rendered $tie_running RUNNING round(s): $(printf '%s\n' "$out" | command grep -E 'RUNNING|OPEN' | tr '\n' ' ')"
# A keyed event that attributes to NO round is activity the ledger sits at —
# the frontier clears, and every open round is behind it. Writer-reachable:
# a stale record for a CLOSED stage trailing a live round is the measured
# workflow_changed shape (a foreign record 10s after the park), the case the
# out-of-round closer already carries for gaps; this is its frontier half.
rws15=$(mk_ws "$base" roundsstray "$repo" "$branch")
s15=$(( $(date +%s) - 900 ))
( . "$RS/lib/state.sh"
  state_append "$rws15" ledger ferry "v=1 t=$s15 event=enter slice=01 stage=spec round=1"
  state_append "$rws15" ledger ferry "v=1 t=$((s15 + 100)) event=advance slice=01 stage=spec verdict=drafted target=precheck"
  state_append "$rws15" ledger ferry "v=1 t=$((s15 + 300)) event=enter slice=01 stage=impl round=1"
  state_append "$rws15" ledger ferry "v=1 t=$((s15 + 400)) event=record slice=01 stage=spec nonce=stale" ) > /dev/null
out=$("$LAUNCH" status "$rws15" --rounds 2>&1); rc=$?
[ $rc -eq 0 ] && printf '%s\n' "$out" | command grep -A1 'slice 01 · impl' | command grep -q 'OPEN' \
  && ! printf '%s\n' "$out" | command grep -q 'RUNNING' \
  && ok "a stale keyed record for a CLOSED stage clears the frontier — the live round reads OPEN, not RUNNING (the ledger's last event is not its work)" \
  || bad "a stray keyed event did not demote the open round: $(printf '%s\n' "$out" | command grep -A1 'impl' | tr '\n' ' ')"
# And the attribution half of the same rule: a keyed event WITH an open round
# moves the frontier TO that round — the round the last keyed event belonged
# to, not the round opened most recently. (enters are keyed events too; the
# tie arm covers the enter-last order, this one the record-last order.)
rws16=$(mk_ws "$base" roundsfrontback "$repo" "$branch")
s16=$(( $(date +%s) - 900 ))
( . "$RS/lib/state.sh"
  state_append "$rws16" ledger ferry "v=1 t=$s16 event=enter slice=01 stage=spec round=1"
  state_append "$rws16" ledger ferry "v=1 t=$((s16 + 100)) event=enter slice=01 stage=impl round=1"
  state_append "$rws16" ledger ferry "v=1 t=$((s16 + 200)) event=record slice=01 stage=spec nonce=back" ) > /dev/null
out=$("$LAUNCH" status "$rws16" --rounds 2>&1); rc=$?
[ $rc -eq 0 ] && printf '%s\n' "$out" | command grep -A1 'slice 01 · spec' | command grep -q 'RUNNING' \
  && printf '%s\n' "$out" | command grep -A1 'slice 01 · impl' | command grep -q 'OPEN' \
  && ok "the frontier follows the last KEYED event's round — a later record for the older round moves it back (spec RUNNING, impl OPEN)" \
  || bad "the frontier did not follow the last keyed event: $(printf '%s\n' "$out" | command grep -E 'RUNNING|OPEN' | tr '\n' ' ')"
# A keyless park (workflow_changed / plan_changed — the adoption-door shapes,
# and exactly what a relaunch-then-read at the landing window produces) is a
# HALT and clears the frontier: a ledger ending in one has NOTHING running —
# the ferry exited. The glastround refactor let the pre-park round sit at the
# frontier and rendered RUNNING over the parked topic (found by the fourth
# cold reader; both with and without a preceding in-round park).
rws18=$(mk_ws "$base" roundskeylessend "$repo" "$branch")
s18=$(( $(date +%s) - 7200 ))
( . "$RS/lib/state.sh"
  state_append "$rws18" ledger ferry "v=1 t=$s18 event=enter slice=02 stage=turnover round=1"
  state_append "$rws18" ledger ferry "v=1 t=$((s18 + 60)) event=spawn slice=02 stage=turnover round=1 attempt=1 mode=cold session=s backend=claude model=m effort=low"
  state_append "$rws18" ledger ferry "v=1 t=$((s18 + 120)) event=park reason=operator_stop slice=02 stage=turnover detail=fixture"
  state_append "$rws18" ledger ferry "v=1 t=$((s18 + 4800)) event=park reason=workflow_changed slice= stage= detail=fixture" ) > /dev/null
out=$("$LAUNCH" status "$rws18" --rounds 2>&1); rc=$?
[ $rc -eq 0 ] && printf '%s\n' "$out" | command grep -A1 'slice 02 · turnover' | command grep -q 'OPEN' \
  && ! printf '%s\n' "$out" | command grep -q 'RUNNING' \
  && printf '%s\n' "$out" | command grep -q 'outside any round (workflow_changed)' \
  && ok "a ledger ending in a KEYLESS park renders the open round OPEN, not RUNNING — the park is a halt; the ferry has exited (the adoption-door shape)" \
  || bad "the keyless-park ending: $(printf '%s\n' "$out" | grep -A1 turnover | tr '\n' ' ')"
# THE PAIRING of the halt and its answer: a keyless park suspends the
# frontier round, and the ferry_start that answers it restores it — measured
# on real ledgers (one archive carries park(in-round) ->
# park(workflow_changed, keyless) -> ferry_start three times). Without the
# restore, the whole warm-resume gap before the first record read OPEN over a
# ferry that was up and resuming — the mirror image of the false RUNNING N1
# fixed (two defects, opposite directions, one line).
rws19=$(mk_ws "$base" roundspairresume "$repo" "$branch")
s19=$(( $(date +%s) - 7200 ))
( . "$RS/lib/state.sh"
  state_append "$rws19" ledger ferry "v=1 t=$s19 event=enter slice=02 stage=turnover round=1"
  state_append "$rws19" ledger ferry "v=1 t=$((s19 + 60)) event=spawn slice=02 stage=turnover round=1 attempt=1 mode=cold session=s backend=claude model=m effort=low"
  state_append "$rws19" ledger ferry "v=1 t=$((s19 + 120)) event=park reason=operator_stop slice=02 stage=turnover detail=fixture"
  state_append "$rws19" ledger ferry "v=1 t=$((s19 + 240)) event=park reason=workflow_changed slice= stage= detail=fixture"
  state_append "$rws19" ledger ferry "v=1 t=$((s19 + 4800)) event=ferry_start pid=1 role=author session=s" ) > /dev/null
out=$("$LAUNCH" status "$rws19" --rounds 2>&1); rc=$?
[ $rc -eq 0 ] && printf '%s\n' "$out" | command grep -A1 'slice 02 · turnover' | command grep -q 'RUNNING' \
  && ok "the ferry_start that answers a keyless park restores the suspended frontier — the resume gap reads RUNNING (the ferry is up, the record not yet landed)" \
  || bad "the pairing: $(printf '%s\n' "$out" | grep -A1 turnover | tr '\n' ' ')"
# The suspend is CONDITIONAL: a second keyless park (plan_changed on the
# heels of workflow_changed — a real pair in the oldest archive) must not
# overwrite what the first suspended with the now-empty frontier; the
# ferry_start that answers the pair restores the round the FIRST halt
# stopped. An unconditional suspend loses it and renders OPEN over a resume.
rws20=$(mk_ws "$base" roundsconckeyless "$repo" "$branch")
s20=$(( $(date +%s) - 7200 ))
( . "$RS/lib/state.sh"
  state_append "$rws20" ledger ferry "v=1 t=$s20 event=enter slice=02 stage=turnover round=1"
  state_append "$rws20" ledger ferry "v=1 t=$((s20 + 120)) event=park reason=operator_stop slice=02 stage=turnover detail=fixture"
  state_append "$rws20" ledger ferry "v=1 t=$((s20 + 240)) event=park reason=workflow_changed slice= stage= detail=fixture"
  state_append "$rws20" ledger ferry "v=1 t=$((s20 + 300)) event=park reason=plan_changed slice= stage= detail=fixture"
  state_append "$rws20" ledger ferry "v=1 t=$((s20 + 4800)) event=ferry_start pid=1 role=author session=s" ) > /dev/null
out=$("$LAUNCH" status "$rws20" --rounds 2>&1); rc=$?
[ $rc -eq 0 ] && printf '%s\n' "$out" | command grep -A1 'slice 02 · turnover' | command grep -q 'RUNNING' \
  && ok "a second keyless park does not clobber the suspended round — the answering ferry_start restores what the FIRST halt stopped (the measured pair)" \
  || bad "the consecutive-keyless pairing: $(printf '%s\n' "$out" | grep -A1 turnover | tr '\n' ' ')"
# An ENTER retires a suspension: the measured sequence parks
# workflow_changed then plan_changed, then a NEW round enters, and only then
# the ferry_start lands — it must not resurrect the round the enter
# superseded; the new round is the frontier.
rws21=$(mk_ws "$base" roundsenterretire "$repo" "$branch")
s21=$(( $(date +%s) - 7200 ))
( . "$RS/lib/state.sh"
  state_append "$rws21" ledger ferry "v=1 t=$s21 event=enter slice=00 stage=spec round=1"
  state_append "$rws21" ledger ferry "v=1 t=$((s21 + 120)) event=park reason=class_u slice=00 stage=spec detail=fixture"
  state_append "$rws21" ledger ferry "v=1 t=$((s21 + 240)) event=park reason=workflow_changed slice= stage= detail=fixture"
  state_append "$rws21" ledger ferry "v=1 t=$((s21 + 3600)) event=enter slice=00 stage=spec round=2"
  state_append "$rws21" ledger ferry "v=1 t=$((s21 + 3660)) event=ferry_start pid=1 role=author session=s" ) > /dev/null
out=$("$LAUNCH" status "$rws21" --rounds 2>&1); rc=$?
nrun21=$(printf '%s\n' "$out" | command grep -c 'RUNNING')
[ $rc -eq 0 ] && [ "$nrun21" -eq 1 ] \
  && printf '%s\n' "$out" | command grep -E 'r2.*RUNNING' | command grep -q . \
  && printf '%s\n' "$out" | command grep -qE 'r1.*\(superseded\)' \
  && ok "the enter between the pair and its ferry_start retires the suspension — the NEW round is the frontier; the superseded one is not resurrected" \
  || bad "the enter-retire shape: $nrun21 RUNNING round(s): $(printf '%s\n' "$out" | grep -A2 spec | tr '\n' ' ')"
# A duplicate (slice, stage, round) enter must not double-list the round or
# double the stage subtotal: the writers cannot produce it (the round counter
# on the attempts surface is monotonic and durable), but a hand-repaired or
# rolled-back surface is a measured event in this tree — and the fifth cold
# reader fuzzer found the double count in 1 of 1000 ledgers. The re-entered
# round restarts and is listed ONCE.
rws22=$(mk_ws "$base" roundsdupenter "$repo" "$branch")
s22=$(( $(date +%s) - 86400 ))
( . "$RS/lib/state.sh"
  state_append "$rws22" ledger ferry "v=1 t=$s22 event=enter slice=02 stage=impl round=1"
  state_append "$rws22" ledger ferry "v=1 t=$((s22 + 3600)) event=advance slice=02 stage=impl verdict=done target=postcheck"
  state_append "$rws22" ledger ferry "v=1 t=$s22 event=enter slice=02 stage=impl round=1" ) > /dev/null
out=$("$LAUNCH" status "$rws22" --rounds 2>&1); rc=$?
n_r1=$(printf '%s\n' "$out" | command grep -c 'r1 ')
[ $rc -eq 0 ] && printf '%s\n' "$out" | command grep -q 'slice 02 · impl — 1 round(s)' \
  && [ "$n_r1" -eq 1 ] \
  && printf '%s\n' "$out" | command grep -qE '= wall (23h[0-9]*m|1d0h), of which parked 0s' \
  && ok "a duplicate (slice,stage,round) enter lists the round ONCE and counts the wall once — the subtotal is not doubled by a hand-repaired surface" \
  || bad "the duplicate-enter shape ($n_r1 r1 rows): $(printf '%s\n' "$out" | grep -A3 impl | tr '\n' ' ')"
# The enter branch retires a suspension — the fourth component of the pairing,
# and for one round the only component with no arm: a new round claiming the
# frontier moots whatever was suspended. The shape isolates it: the stale
# post-advance record clears the frontier, so WITHOUT the retire the
# ferry_start resurrects the round the newer enter superseded — a superseded
# round rendering RUNNING (found by the sixth cold reader's mutation battery:
# dropping the clause survived 189 green).
rws23=$(mk_ws "$base" roundsenterretire2 "$repo" "$branch")
s23=$(( $(date +%s) - 3600 ))
( . "$RS/lib/state.sh"
  state_append "$rws23" ledger ferry "v=1 t=$s23 event=enter slice=01 stage=impl round=1"
  state_append "$rws23" ledger ferry "v=1 t=$((s23 + 60)) event=spawn slice=01 stage=impl round=1 attempt=1 mode=cold session=s backend=claude model=m effort=low"
  state_append "$rws23" ledger ferry "v=1 t=$((s23 + 120)) event=park reason=workflow_changed slice= stage= detail=fixture"
  state_append "$rws23" ledger ferry "v=1 t=$((s23 + 300)) event=enter slice=00 stage=plan-validate round=2"
  state_append "$rws23" ledger ferry "v=1 t=$((s23 + 400)) event=advance slice=00 stage=plan-validate verdict=pass target=split"
  state_append "$rws23" ledger ferry "v=1 t=$((s23 + 500)) event=record slice=00 stage=plan-validate nonce=stale"
  state_append "$rws23" ledger ferry "v=1 t=$((s23 + 600)) event=ferry_start pid=1 role=author session=s" ) > /dev/null
out=$("$LAUNCH" status "$rws23" --rounds 2>&1); rc=$?
[ $rc -eq 0 ] && printf '%s\n' "$out" | command grep -A1 'slice 01 · impl' | command grep -q 'OPEN' \
  && ! printf '%s\n' "$out" | command grep -q 'RUNNING' \
  && ok "the enter retires the suspension — the round the newer enter superseded renders OPEN after the stale-record clear and the ferry_start, never resurrected as RUNNING" \
  || bad "the retire shape: $(printf '%s\n' "$out" | grep -A1 'slice 01 · impl' | tr '\n' ' ')"
# A keyless park arriving over an OPEN IN-ROUND park suspends THAT round, not
# the (possibly cleared) frontier: a keyed row for a DIFFERENT slice can land
# between the two parks while the parked round was never advanced — measured
# in prw (park blocked slice=03, never advanced, ferry work for slice 09
# lands 44180s later) — and
# the frontier alone would then suspend nothing, the answering ferry_start
# would restore nothing, and the resumed round would read OPEN over a ferry
# that is up (the P1 failure surface, one stray row over).
rws24=$(mk_ws "$base" roundssuspendhold "$repo" "$branch")
s24=$(( $(date +%s) - 7200 ))
( . "$RS/lib/state.sh"
  state_append "$rws24" ledger ferry "v=1 t=$s24 event=enter slice=01 stage=precheck round=1"
  state_append "$rws24" ledger ferry "v=1 t=$((s24 + 60)) event=spawn slice=01 stage=precheck round=1 attempt=1 mode=cold session=s backend=claude model=m effort=low"
  state_append "$rws24" ledger ferry "v=1 t=$((s24 + 120)) event=park reason=operator_stop slice=01 stage=precheck detail=fixture"
  state_append "$rws24" ledger ferry "v=1 t=$((s24 + 200)) event=commit.done slice=01 stage=spec count=1"
  state_append "$rws24" ledger ferry "v=1 t=$((s24 + 300)) event=park reason=workflow_changed slice= stage= detail=fixture"
  state_append "$rws24" ledger ferry "v=1 t=$((s24 + 3600)) event=ferry_start pid=1 role=author session=s" ) > /dev/null
out=$("$LAUNCH" status "$rws24" --rounds 2>&1); rc=$?
[ $rc -eq 0 ] && printf '%s\n' "$out" | command grep -A1 'slice 01 · precheck' | command grep -q 'RUNNING' \
  && ok "a keyless park over an open IN-ROUND park suspends THAT round — the stray keyed row between them cannot erase it, and the answering ferry_start restores it (RUNNING)" \
  || bad "the suspend-hold shape: $(printf '%s\n' "$out" | grep -A1 precheck | tr '\n' ' ')"
# A row the parser cannot read is COUNTED and SAID, never silently dropped:
# a well-formed checksummed row with a future row spelling (v=2) or a
# non-numeric t= is invisible to the checksum, and the row-level parser is
# the only judge — without the count, an unreadable advance AND park rendered
# their round RUNNING over rc=0, silence as a verdict (found by the seventh
# cold reader; the empty-surface gate already holds "the gate may not be
# stricter than the parser", this is its row-level twin, and peek counts its
# unreadable rows for the same reason).
rws25=$(mk_ws "$base" roundsdropped "$repo" "$branch")
s25=$(( $(date +%s) - 3600 ))
( . "$RS/lib/state.sh"
  state_append "$rws25" ledger ferry "v=1 t=$s25 event=enter slice=01 stage=spec round=1"
  state_append "$rws25" ledger ferry "v=2 t_ms=1788761000000 event=advance slice=01 stage=spec verdict=drafted target=precheck"
  state_append "$rws25" ledger ferry "v=1 t=BAD event=park reason=operator_stop slice=01 stage=spec detail=fixture" ) > /dev/null
out=$("$LAUNCH" status "$rws25" --rounds 2>&1); rc=$?
[ $rc -eq 0 ] && printf '%s\n' "$out" | command grep -q '2 row(s) on the ledger carry no parseable event=/t=' \
  && printf '%s\n' "$out" | command grep -q 'not counted in any wall' \
  && ok "rows the parser cannot read are counted and SAID — never silently dropped over rc=0 (the unreadable advance and park would have read as a live RUNNING round)" \
  || bad "the dropped-row count: $(printf '%s\n' "$out" | tail -2 | tr '\n' ' ')"
# A \037 byte inside a field value must not shift the render: the awk-to-shell
# handoff uses it as the record separator, so one byte in reason= walks the
# spawn count into the verdict column and truncates the reason (found by the
# seventh cold reader; the writers emit no control bytes, but an authorized
# manual state_append is the live entrance). The kv() sanitation is the one
# point every rendered field passes through.
rws26=$(mk_ws "$base" roundsunitsep "$repo" "$branch")
s26=$(( $(date +%s) - 7140 ))
us=$'\037'
( . "$RS/lib/state.sh"
  state_append "$rws26" ledger ferry "v=1 t=$s26 event=enter slice=01 stage=spec round=1"
  state_append "$rws26" ledger ferry "v=1 t=$((s26 + 60)) event=spawn slice=01 stage=spec round=1 attempt=1 mode=cold session=s backend=claude model=m effort=low"
  state_append "$rws26" ledger ferry "v=1 t=$((s26 + 120)) event=park reason=blo${us}cked slice=01 stage=spec detail=fixture"
  state_append "$rws26" ledger ferry "v=1 t=$((s26 + 7080)) event=ferry_start pid=1 role=author session=s" ) > /dev/null
out=$("$LAUNCH" status "$rws26" --rounds 2>&1); rc=$?
[ $rc -eq 0 ] && printf '%s\n' "$out" | command grep -q 'RUNNING · parked 1x blocked 1h56m' \
  && ! printf '%s\n' "$out" | command grep -qP '\x1f' \
  && ok "a unit separator inside a field value is sanitized at kv() — the reason renders whole (blocked), the columns hold, and no separator byte reaches the output" \
  || bad "the unit-separator shape: $(printf '%s\n' "$out" | grep 'r1 ' | cat -A | tr '\n' ' ')"
# The one interaction cell of the pairing matrix no round had driven: a
# TEARDOWN (or any other keyless bookkeeping row) between the keyless park
# and its answering ferry_start. Hand-computed before running: teardown is
# bookkeeping, not a resume — it does not discharge the halt (the sentinel
# holds the @ gap, exactly the rws12 rule) and does not disturb the
# suspension; the ferry_start still restores the round, and the gap books
# park -> ferry_start (58m in the fixture, not park -> EOF).
rws27=$(mk_ws "$base" roundsteardownmid "$repo" "$branch")
s27=$(( $(date +%s) - 7200 ))
( . "$RS/lib/state.sh"
  state_append "$rws27" ledger ferry "v=1 t=$s27 event=enter slice=01 stage=spec round=1"
  state_append "$rws27" ledger ferry "v=1 t=$((s27 + 60)) event=spawn slice=01 stage=spec round=1 attempt=1 mode=cold session=s backend=claude model=m effort=low"
  state_append "$rws27" ledger ferry "v=1 t=$((s27 + 120)) event=park reason=workflow_changed slice= stage= detail=fixture"
  state_append "$rws27" ledger ferry "v=1 t=$((s27 + 200)) event=teardown role=author session=s"
  state_append "$rws27" ledger ferry "v=1 t=$((s27 + 3600)) event=ferry_start pid=1 role=author session=s" ) > /dev/null
out=$("$LAUNCH" status "$rws27" --rounds 2>&1); rc=$?
[ $rc -eq 0 ] && printf '%s\n' "$out" | command grep -A1 'slice 01 · spec' | command grep -q 'RUNNING' \
  && printf '%s\n' "$out" | command grep -q 'outside any round (workflow_changed) — 5[0-9]m' \
  && ok "a teardown between the keyless park and its ferry_start changes neither half — the halt is not discharged (gap books park->ferry_start, ~58m) and the restore still fires (RUNNING)" \
  || bad "the teardown-mid pairing cell: $(printf '%s\n' "$out" | grep -E 'r1 |outside' | tr '\n' ' ')"
# The restore GUARD: when a keyed row of another open round claims the frontier
# between the keyless park and its ferry_start, the restore must NOT overwrite
# it — attribution is direct evidence (a row landed for that round); pairing is
# inference (the started ferry is probably resuming the suspended one). Found
# by round 18 mutation: deadening the guard condition survived 64 green, and
# this shape flips the verdict column (without the guard the resumed-by-
# inference round reads RUNNING over the round the ledger actually wrote).
rws28=$(mk_ws "$base" roundsguardattr "$repo" "$branch")
s28=$(( $(date +%s) - 7200 ))
( . "$RS/lib/state.sh"
  state_append "$rws28" ledger ferry "v=1 t=$s28 event=enter slice=01 stage=spec round=1"
  state_append "$rws28" ledger ferry "v=1 t=$((s28 + 60)) event=enter slice=02 stage=spec round=1"
  state_append "$rws28" ledger ferry "v=1 t=$((s28 + 120)) event=park reason=workflow_changed slice= stage= detail=fixture"
  state_append "$rws28" ledger ferry "v=1 t=$((s28 + 300)) event=record slice=01 stage=spec nonce=stray"
  state_append "$rws28" ledger ferry "v=1 t=$((s28 + 3600)) event=ferry_start pid=1 role=author session=s" ) > /dev/null
out=$("$LAUNCH" status "$rws28" --rounds 2>&1); rc=$?
[ $rc -eq 0 ] && printf '%s\n' "$out" | command grep -A1 'slice 01 · spec' | command grep -q 'RUNNING' \
  && printf '%s\n' "$out" | command grep -A1 'slice 02 · spec' | command grep -q 'OPEN' \
  && ok "the restore does not overwrite a frontier claimed by direct evidence — the round whose record landed between park and ferry_start reads RUNNING, not the suspended one" \
  || bad "the guard shape: $(printf '%s\n' "$out" | grep -A1 'slice 0' | tr '\n' ' ')"
# A ledger PAST THE PIPE BUFFER (~64KB) must render, never read as EMPTY:
# under set -o pipefail, `printf | grep -q` dies of SIGPIPE (141) — grep -q
# exits at its first match while printf keeps writing — and the `if !` read
# that as no-event-rows. Measured at 2001 rows (~150KB); ~900 rows is the
# threshold, which a long topic's ledger crosses (round 19, durability pass;
# the EMPTY gate now tests a shell glob and the peek gates use here-strings).
rws29=$(mk_ws "$base" roundspastpipe "$repo" "$branch")
# The body lands in the session's own mktemp, not a fixed /tmp name: a fixed
# path is the one file this suite owns outside its scratch dir, and two
# concurrent runs of this check would race on it (found as a leftover on this
# box by the portability review).
pb29=$(mktemp "${TMPDIR:-/tmp}/dwsc-36vp.XXXXXX")
{
  t29=$(( $(date +%s) - 86400*30 ))
  for s29 in $(seq -w 1 400); do
    for st29 in spec impl postcheck turnover; do
      printf 'v=1 t=%s event=enter slice=%s stage=%s round=1\nv=1 t=%s event=spawn slice=%s stage=%s round=1 attempt=1 mode=cold session=s backend=claude\nv=1 t=%s event=record slice=%s stage=%s nonce=n%s\nv=1 t=%s event=advance slice=%s stage=%s verdict=done target=next\n' \
        "$t29" "$s29" "$st29" "$((t29 + 10))" "$s29" "$st29" "$((t29 + 20))" "$s29" "$st29" "$t29" "$((t29 + 30))" "$s29" "$st29"
      t29=$((t29 + 40))
    done
  done
} > "$pb29"
( . "$RS/lib/state.sh"; state_set "$rws29" ledger ferry < "$pb29" ) > /dev/null
nrows=$(wc -l < "$pb29")
out=$("$LAUNCH" status "$rws29" --rounds 2>&1); rc=$?
# The arm's OWN assertions use here-strings for the same reason: the output
# here is ~290KB, and `printf | grep -q` over it would race the same SIGPIPE
# the arm exists to pin (found the self-demonstrating way — the first cut of
# this arm failed on its own 'slice 001' assertion).
[ $rc -eq 0 ] && [ "$nrows" -gt 900 ] \
  && ! command grep -q 'EMPTY' <<< "$out" \
  && command grep -q 'slice 400 · turnover' <<< "$out" \
  && command grep -q 'slice 001 · spec' <<< "$out" \
  && ok "a ${nrows}-row ledger (~500KB, past the pipe buffer) renders its rounds — never EMPTY through a SIGPIPE'd presence test" \
  || bad "the past-pipe shape (${nrows} rows): $(printf '%s\n' "$out" | head -2 | tr '\n' ' ')"
# A ROTATED ledger segment must SAY it covers only the tail: the rotation row
# (event=rotated, written as the first row of every new segment, cap 8000) is
# real data on the surface — rounds before it live in the .rot archive, and
# rendering the tail as if it were the run is the census lying by omission.
# Found by round 24 reading operations.md §10 against the reader: the cap
# exists, the rotation writes the row, and the parser skipped it as an
# unknown keyless event — not even counted as dropped.
rws30=$(mk_ws "$base" roundsrotated "$repo" "$branch")
s30=$(( $(date +%s) - 7200 ))
( . "$RS/lib/state.sh"
  printf 'v=1 t=%s event=rotated cap=8000 rotated_to=ledger.1700000000.rot\nv=1 t=%s event=enter slice=05 stage=spec round=1\nv=1 t=%s event=advance slice=05 stage=spec verdict=done target=impl\n' \
    "$s30" "$((s30 + 60))" "$((s30 + 3600))" | state_set "$rws30" ledger ferry ) > /dev/null
out=$("$LAUNCH" status "$rws30" --rounds 2>&1); rc=$?
[ $rc -eq 0 ] && printf '%s\n' "$out" | command grep -q 'the ledger has rotated 1 time(s)' \
  && printf '%s\n' "$out" | command grep -q 'ledger.1700000000.rot' \
  && printf '%s\n' "$out" | command grep -q 'covers the current segment only' \
  && printf '%s\n' "$out" | command grep -q 'slice 05 · spec' \
  && ok "a rotated segment renders its tail's rounds AND names the archive — the census never presents the tail as the run" \
  || bad "the rotated shape: $(printf '%s\n' "$out" | tail -2 | tr '\n' ' ')"
# The freeze claims the ledger ENDS in complete — a stray post-complete row
# must leave the LIVE clock (a first form froze on any complete row and read
# the later round's wall as a negative '?'). Adversarial shape, judged
# unreachable by the writers (resume exits idempotent on push_gate before any
# append), pinned anyway because the rule's letter is what the doc claims.
rws10=$(mk_ws "$base" roundsmidcomp "$repo" "$branch")
m10=$(( $(date +%s) - 3600 ))
( . "$RS/lib/state.sh"
  state_append "$rws10" ledger ferry "v=1 t=$m10 event=enter slice=01 stage=spec round=1"
  state_append "$rws10" ledger ferry "v=1 t=$((m10 + 100)) event=advance slice=01 stage=spec verdict=drafted target=precheck"
  state_append "$rws10" ledger ferry "v=1 t=$((m10 + 200)) event=complete topic=fixture"
  state_append "$rws10" ledger ferry "v=1 t=$((m10 + 400)) event=enter slice=02 stage=spec round=1" ) > /dev/null
out=$("$LAUNCH" status "$rws10" --rounds 2>&1); rc=$?
s02r1=$(printf '%s\n' "$out" | command grep -A1 'slice 02 · spec' | command grep 'r1')
[ $rc -eq 0 ] && [ -n "$s02r1" ] && printf '%s\n' "$s02r1" | command grep -qE 'r1 +[0-9-]+ [0-9:]+ +[0-9]+[smhd] ' \
  && ! printf '%s\n' "$s02r1" | command grep -q '\?' \
  && ok "a ledger with events AFTER complete keeps the live clock (the later round renders a positive wall, never the negative-'?' the any-complete freeze produced)" \
  || bad "mid-ledger complete handling: slice-02 row '$s02r1'"
# A resumed round whose own park row is the last KEYED event, with a keyless
# ferry_start trailing it (the exact shape every warm relaunch writes): the
# round is RUNNING — keyless rows do not demote it. The first frontier rule
# compared against the ledger's LAST event of any kind and read OPEN here;
# measured on a copy of the live ledger, the Phase-3 relaunch ferry_start
# alone flipped the live round out of its true state.
rws11=$(mk_ws "$base" roundsfrontier "$repo" "$branch")
f11=$(( $(date +%s) - 3600 ))
( . "$RS/lib/state.sh"
  state_append "$rws11" ledger ferry "v=1 t=$f11 event=enter slice=01 stage=spec round=1"
  state_append "$rws11" ledger ferry "v=1 t=$((f11 + 100)) event=park reason=operator_stop slice=01 stage=spec detail=fixture"
  state_append "$rws11" ledger ferry "v=1 t=$((f11 + 200)) event=ferry_start pid=9" ) > /dev/null
out=$("$LAUNCH" status "$rws11" --rounds 2>&1); rc=$?
[ $rc -eq 0 ] && printf '%s\n' "$out" | command grep -qE 'r1 .*RUNNING' \
  && ! printf '%s\n' "$out" | command grep -q 'OPEN' \
  && ok "a resumed round stays RUNNING past a trailing keyless ferry_start (its own park row is the keyed frontier)" \
  || bad "the frontier verdict: $(printf '%s\n' "$out" | command grep 'r1')"
# A keyless row that is NOT park/ferry_start/enter (teardown, slices_index,
# run_init …) must not close an out-of-round park: without the sentinel key,
# the unset oparkkey matched the row own empty key and closed it (measured:
# a teardown 100s after the park capped a 59m gap at 1m).
rws12=$(mk_ws "$base" roundssentinel "$repo" "$branch")
s12=$(( $(date +%s) - 3600 ))
( . "$RS/lib/state.sh"
  state_append "$rws12" ledger ferry "v=1 t=$s12 event=enter slice=01 stage=spec round=1"
  state_append "$rws12" ledger ferry "v=1 t=$((s12 + 100)) event=advance slice=01 stage=spec verdict=drafted target=precheck"
  state_append "$rws12" ledger ferry "v=1 t=$((s12 + 200)) event=park reason=workflow_changed slice= stage= detail=fixture"
  state_append "$rws12" ledger ferry "v=1 t=$((s12 + 300)) event=teardown role=author session=s1" ) > /dev/null
out=$("$LAUNCH" status "$rws12" --rounds 2>&1); rc=$?
[ $rc -eq 0 ] && printf '%s\n' "$out" | command grep -qE 'outside any round \(workflow_changed\) — 5[0-9]m' \
  && ok "a keyless teardown does NOT close an out-of-round park (the gap runs to EOF, ~59m — the unset-key shape capped it at 1m)" \
  || bad "the sentinel gap: $(printf '%s\n' "$out" | command grep 'outside any round')"
corrupt_surface "$rws" ledger
out=$("$LAUNCH" status "$rws" --rounds 2>&1); rc=$?
[ $rc -ne 0 ] && printf '%s\n' "$out" | command grep -q 'CORRUPT' \
  && ok "a CORRUPT ledger refuses as corrupt (fault != absent — a corruption must not quietly omit rounds)" \
  || bad "rc=$rc over a corrupt ledger: $out"
rws2=$(mk_ws "$base" roundsnever "$repo" "$branch")
out=$("$LAUNCH" status "$rws2" --rounds 2>&1); rc=$?
[ $rc -ne 0 ] && printf '%s\n' "$out" | command grep -qi 'never' \
  && ok "a topic with no ledger refuses as never-run (absent, not empty)" \
  || bad "rc=$rc on a never-run topic: $out"
# The EMPTY gate (a ledger whose header exists but no event= rows) is
# itself pinned: a surface written with an empty body must SAY "the ledger is
# EMPTY", not render as a running topic (found by R42's per-arm audit: the
# past-pipe-buffer arm covers the SIGPIPE half, not the empty-body half).
rws_e=$(mk_ws "$base" roundsempty "$repo" "$branch")
( . "$RS/lib/state.sh"; printf '' | state_set "$rws_e" ledger ferry ) > /dev/null
out=$("$LAUNCH" status "$rws_e" --rounds 2>&1); rc=$?
[ $rc -eq 0 ] && command grep -q 'the ledger is EMPTY' <<< "$out"   && ok "a ledger with a header but no event rows says 'the ledger is EMPTY' (the gate's own behavior, not the SIGPIPE arm)"   || bad "empty-body ledger: $out"
# The EMPTY gate is the parser's own predicate (no event= rows), never a
# version prefix: a future row spelling with event=/t= must RENDER, not read
# as "no events yet" — the awk keys on fields, so the gate may not be stricter
# than the parser it gates for (a first form grepped '^v=1 ' and a v-next-only
# ledger would have printed EMPTY over parseable rows).
rws17=$(mk_ws "$base" roundsvnext "$repo" "$branch")
n17=$(( $(date +%s) - 300 ))
( . "$RS/lib/state.sh"
  printf 'v=2 t=%s event=enter slice=01 stage=spec round=1 future_field=x\n' "$n17" \
    | state_set "$rws17" ledger ferry ) > /dev/null
out=$("$LAUNCH" status "$rws17" --rounds 2>&1); rc=$?
[ $rc -eq 0 ] && printf '%s\n' "$out" | command grep -q 'slice 01 · spec' \
  && ! printf '%s\n' "$out" | command grep -q 'EMPTY' \
  && ok "a ledger whose rows carry a future version tag still parses — EMPTY is 'no event rows', the parser's own predicate, never a version prefix" \
  || bad "version-prefixed rows refused or read as EMPTY: $out"

check_done
