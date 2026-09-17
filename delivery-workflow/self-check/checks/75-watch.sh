#!/usr/bin/env bash
# 75-watch — watch_wait's timeout semantics (state-and-liveness.md §5):
# stage_timeout is a CONTINUOUS-INACTIVITY deadline — any activity observation
# (fresh heartbeat, CPU delta) resets it; only unbroken silence past the limit
# kills. hard_ceiling stays the absolute total cap. Three directions:
# busy-throughout rides to the ceiling; INTERMITTENT busy (bursts separated by
# sub-limit pauses) survives — a total-elapsed reading would miskill it; and
# unbroken inactivity past stage_timeout still dies (the guard is not
# deleted). Deterministic: pty/classify/CPU are function overrides, literals
# shrunk via topic.kv (every threshold an independent literal).
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/fixtures/lib.sh"
. "$RS/lib/state.sh"
. "$RS/lib/watch.sh"

base=$(sc_tmpdir)
read -r repo branch < <(mk_repo "$base/repo")
ws=$(mk_ws "$base" watchtopic "$repo" "$branch")
# The loop runs on a VIRTUAL clock here (the seam block below): every arm's
# outcome is arithmetic on its own literals, landing at a fixed virtual second
# whatever the machine is doing. Before the seam, startup (~2s of config
# resolution) and each stretched iteration counted against spawn_t in real
# time, and a loaded machine could carry an arm past a small deadline between
# two activity observations (FAIL timeout where FAIL idle was wanted — measured
# under -j12 and reproduced serially at loadavg 8.7).
# Every threshold is an independent literal and several arms need their own
# window, so the window is ONE base with per-arm overrides rather than four
# near-copies. Four near-copies is how a threshold gets silently dropped:
# written out straight, the restore after the idle-noise arm was copied from
# the block at the top of this file and lost `stop_gate_blocks_max=3`, which
# returned the counter to the default 6 and took every wedge arm below it red.
# A base plus overrides cannot lose a key it was not told to change.
window() { # k=v ... -> rewrite topic.kv as the base plus overrides
  local base kv k
  base='liveness.poll=1
liveness.heartbeat_fresh=1
liveness.quiet_grace=1
liveness.stage_timeout=6
liveness.working_max_age=30
liveness.nudge_grace=2
liveness.hard_ceiling=12
liveness.stop_gate_blocks_max=3'
  for kv in "$@"; do
    k=${kv%%=*}
    base=$(printf '%s\n' "$base" | awk -v k="$k=" 'index($0, k) != 1')
    base="$base
$kv"
  done
  printf '%s\n' "$base" > "$ws/config/topic.kv"
}
window
decl="$WF_ROOT/config/backends/claude.kv"

# Overrides (defined after sourcing watch.sh, so they shadow the real ones).
pty_alive() { echo running; }
pty_classify_screen() { echo awaiting_input; }
pty_inject() { return 0; }
cnt="$base/cpu.n"; echo 0 > "$cnt"
cpu_mode="$base/cpu.mode"; echo increasing > "$cpu_mode"
# The burst is sized in REAL jiffies now that the CPU test is a rate test:
# liveness.cpu_busy_pct=25 of one core over a poll=1 window is 25 jiffies at
# the usual CLK_TCK=100, so 200 is unambiguous work and the 5 used further
# down is unambiguous idle noise. The old stub added ONE jiffy per poll and
# passed, which is the whole defect: an idle CLI produces that too.
watch_subtree_cpu() {
  local n
  n=$(cat "$cnt")
  if [ "$(cat "$cpu_mode")" = "increasing" ]; then echo $((n + 200)) > "$cnt"; fi
  cat "$cnt"
}

echo "-- the loop's clock is a seam: real by default, shadowed here --"
# watch_wait reads time through two one-line functions, _wt_now and _wt_sleep,
# and nothing else in its body. Their DEFAULTS are the real thing, asserted
# first against the real functions (before this file shadows them): a seam
# whose production side drifted would turn every live stage's timers into
# fiction while this fixture stayed green on its own clock.
_has_seams() { declare -F _wt_now > /dev/null && declare -F _wt_sleep > /dev/null; }   # in-process: a `bash -c` would see none of watch.sh
precond "watch.sh defines the two clock seams" _has_seams
r0=$(date +%s); rn=$(_wt_now 2>/dev/null || echo 0); r1=$(date +%s)
[ "$rn" -ge "$r0" ] && [ "$rn" -le "$r1" ] \
  && ok "default _wt_now is the real epoch ($rn, between $r0 and $r1)" \
  || bad "default _wt_now returned '$rn' against real $r0..$r1 — production timers would be fiction"
s0=$(date +%s); _wt_sleep 1; s1=$(date +%s)
[ $((s1 - s0)) -ge 1 ] \
  && ok "default _wt_sleep 1 took $((s1 - s0))s of real time — production still waits" \
  || bad "default _wt_sleep 1 returned in $((s1 - s0))s — the live loop would spin"
# The wait between polls returns EARLY on the record and not otherwise —
# asserted against the real function before it is shadowed below. The early
# return is the whole point (a stage end seen in half a second, not a poll);
# the late return is what keeps every liveness read on its settled cadence.
# Real time, generous bounds: a 3s poll with no record must cost at least 3s,
# and with the record present must come back well inside 3s.
wwws=$(sc_tmpdir); mkdir -p "$wwws/.runtime/state"
w0=$(date +%s); _wt_wait "$wwws" nonceWW 3; w1=$(date +%s)
[ $((w1 - w0)) -ge 3 ] \
  && ok "_wt_wait with no record sleeps the whole poll ($((w1 - w0))s of 3)" \
  || bad "_wt_wait returned after $((w1 - w0))s with no record — liveness reads would run before the pane settles"
( . "$RS/lib/state.sh"; state_append "$wwws" handoff session "v=1 t=1 slice=01 stage=spec nonce=nonceWW verdict=drafted" ) > /dev/null
w0=$(date +%s); _wt_wait "$wwws" nonceWW 3; w1=$(date +%s)
[ $((w1 - w0)) -lt 3 ] \
  && ok "_wt_wait returns early once the record is on the handoff surface ($((w1 - w0))s of 3)" \
  || bad "_wt_wait slept the full poll with the record present — a stage end is still seen a poll late"
# "early" is not the property; ZERO sleeps is. A record already on the surface
# when the wait is entered must cost NOTHING, and the wall-clock bound above
# cannot see the difference between that and one 0.5s sleep — which is exactly
# what the function used to do, at every stage end, measured as 9.52s of a
# 38.1s drill walk. Counted rather than timed, by shadowing the seam for one
# call and restoring the real body straight after (the arms below install their
# own virtual clock; this must not leak into them).
_wt_sleep_real=$(declare -f _wt_sleep)
_wt_n_sleeps=0
_wt_sleep() { _wt_n_sleeps=$((_wt_n_sleeps + 1)); sleep "$1"; }
# The counter is floored FIRST, against a wait that must sleep: a 1s poll is
# two 0.5s sleeps. Without this the zero below passes just as well when the
# shim was never installed, which is the vacuous-arm shape this suite exists
# to refuse.
_wt_wait "$wwws" absentNonce 1
[ "$_wt_n_sleeps" -eq 30 ] \
  && ok "the wake COUNT is fixed at 30 per poll regardless of its length (a 1s poll = 30 wakes, not 2)" \
  || bad "sleep counter read $_wt_n_sleeps for a 1s no-record poll, wanted 30 — either the shim is not installed (and the zero below is vacuous) or the step stopped subdividing the poll"
_wt_n_sleeps=0
_wt_wait "$wwws" nonceWW 3
[ "$_wt_n_sleeps" -eq 0 ] \
  && ok "…and with the record already present it sleeps ZERO times (the check precedes the first sleep)" \
  || bad "_wt_wait slept $_wt_n_sleeps time(s) with the record already present — the look-then-sleep order regressed"
# PRODUCTION IS BIT-IDENTICAL, and that is the claim worth pinning rather than
# asserting in a comment: at the shipped `liveness.poll=15` the step must still
# be 0.5s and the count still 30 — the same 30 half-second wakes the hard-coded
# form did. A step that drifted here would change the live loop's cadence while
# every drill stayed green, since the drills all run poll=1.
_wt_n_sleeps=0; _wt_steps=""
_wt_sleep() { _wt_n_sleeps=$((_wt_n_sleeps + 1)); _wt_steps="$_wt_steps $1"; }
_wt_wait "$wwws" absentNonce 15
[ "$_wt_n_sleeps" -eq 30 ] && [ "$(printf '%s' "$_wt_steps" | tr ' ' '\n' | sort -u | tr -d '\n')" = "0.500" ] \
  && ok "at the shipped liveness.poll=15 the wait is 30 wakes of 0.500s — bit-identical to the hard-coded form it replaced" \
  || bad "poll=15 now yields $_wt_n_sleeps wakes of$(printf '%s' "$_wt_steps" | tr ' ' '\n' | sort -u | tr '\n' ' ') — production cadence changed"
_wt_n_sleeps=0; _wt_steps=""
_wt_wait "$wwws" absentNonce 1
[ "$(printf '%s' "$_wt_steps" | tr ' ' '\n' | sort -u | tr -d '\n')" = "0.033" ] \
  && ok "…and a drill's declared poll=1 finally reaches the step (0.033s, not the old fixed 0.5s)" \
  || bad "poll=1 step is$(printf '%s' "$_wt_steps" | tr ' ' '\n' | sort -u | tr '\n' ' ') — the declared poll is still being ignored"
_wt_n_sleeps=0; _wt_steps=""
_wt_wait "$wwws" absentNonce 0
[ "$(printf '%s' "$_wt_steps" | tr ' ' '\n' | sort -u | tr -d '\n')" = "0.010" ] \
  && ok "known-bad: a zero poll floors at 0.010s instead of spinning on sleep 0.000" \
  || bad "poll=0 step is$(printf '%s' "$_wt_steps" | tr ' ' '\n' | sort -u | tr '\n' ' ') — the busy-spin floor is gone"
eval "$_wt_sleep_real"
command grep -q '_wt_n_sleeps' <<< "$(declare -f _wt_sleep)" \
  && bad "the counting shim is still installed — the virtual-clock arms below would inherit it" \
  || ok "the real seam is restored (the arms below install their own clock onto a clean one)"
# Structural pin, so a later edit cannot reintroduce a third clock into the
# loop beside the seam: the function body — from its header to the first
# column-0 closing brace — carries neither `date +%s` nor a bare `sleep`.
# Printed, not counted, so a hit names its line. The extraction is a pair of
# functions so the known-bad below drives the SAME code, never a re-typed
# copy; and it is floored, because an awk that stopped matching (rename,
# `watch_wait ()` reformat) would read as clean — the extraction must be
# non-trivial AND must reference the seam, or it is not the loop's body.
ww_extract() { # <file> -> watch_wait's body, header to first column-0 close brace
  awk '/^watch_wait\(\)/{p=1} p{print} p && /^}/{exit}' "$1"
}
ww_direct_clock() { # <body> -> direct clock reads with line numbers
  printf '%s\n' "$1" | command grep -nE 'date \+%s|(^|[^_a-z])sleep ' || true
}
ww_body=$(ww_extract "$RS/lib/watch.sh")
precond "the seam scan extracted watch_wait's real body ($(printf '%s\n' "$ww_body" | command grep -c .) lines, seam references present — a rename or reformat would read as clean)" \
  bash -c 'printf "%s\n" "$1" | command grep -q "_wt_" && [ "$(printf "%s\n" "$1" | command grep -c .)" -ge 20 ]' _ "$ww_body"
ww_direct=$(ww_direct_clock "$ww_body")
[ -z "$ww_direct" ] \
  && ok "watch_wait's body reads time only through the seam (no direct date/sleep, $(printf '%s\n' "$ww_body" | command grep -c .) lines scanned)" \
  || bad "watch_wait reads the clock beside the seam:$(printf '\n    %s' "$ww_direct")"
# known-bad: a body carrying both banned forms must fire, or the scan above
# is a permanent green over nothing.
wwb=$(sc_tmpdir)/watch-bad.sh
printf 'watch_wait() {\n  now=$(date +%%s)\n  sleep 1\n}\n' > "$wwb"
wwb_body=$(ww_extract "$wwb")
[ -n "$(ww_direct_clock "$wwb_body")" ] \
  && ok "known-bad: a direct date and a bare sleep inside watch_wait are what the scan exists to catch" \
  || bad "the seam scan cannot fire — a direct clock read would read as clean"

# Now the shadow. CONSTRAINT, not a choice: `now` is not a private counter —
# the loop compares it against stamps OTHER writers put down in real epoch
# (`hb_age = now - hb` from the heartbeat surface; notify_events rows' `t=`)
# and writes it INTO the ledger as `t=$now` — so the virtual clock must start
# at the real epoch and only ever run ahead of it. Seeded from `date` on the
# first read after a reset; `_wt_sleep n` jumps it by n and returns at once.
# Each arm resets it (vstart) so no arm inherits another's lead over real
# time, and passes the seed as spawn_t so `age` is exactly the virtual elapsed.
# A frozen clock must FAIL an arm, never hang it: with `now` on the seam but
# a wait that no longer advances it, the loop's time stands still and nothing
# it compares ever crosses a deadline (measured: the mutation `sleep "$poll"`
# in place of `_wt_sleep` hung this check, and the runner has no per-check
# timeout). So reads between advances are counted and the loop's subshell is
# aborted past a bound no terminating arm approaches (one read per virtual
# second; the widest window here is 60).
vclk="$base/vclock"; vseed="$base/vclock.seed"; vreads="$base/vclock.reads"
_wt_now() {
  if [ ! -s "$vclk" ]; then date +%s | tee "$vclk" > "$vseed"; : > "$vreads"; fi
  echo . >> "$vreads"
  if [ "$(command grep -c . "$vreads")" -gt 1000 ]; then
    echo "FIXTURE ABORT: 1000 clock reads with no advance — the loop's time is frozen" >&2; exit 99
  fi
  cat "$vclk"
}
_wt_sleep() { echo $(( $(_wt_now) + $1 )) > "$vclk"; : > "$vreads"; }
_wt_wait()  { _wt_sleep "$3"; }                                    # no arm here ever lands a record
vstart()   { rm -f "$vclk" "$vseed" "$vreads"; _wt_now; }          # -> the seed (use as spawn_t)
velapsed() { echo $(( $(cat "$vclk" 2>/dev/null || echo 0) - $(cat "$vseed" 2>/dev/null || echo 0) )); }   # -> virtual seconds the loop lived (0 = it never touched the clock)
# The real `sleep` is shadowed too, as a RECORDER: it still sleeps, and it
# writes its caller down. An arm then asserts watch_wait never reached it —
# the proof that the wait was virtual, with no wall clock in the assertion.
# Bounded for the same reason as the reads: a loop on a real sleep and a
# frozen `now` would otherwise spend the reads bound one real second at a time.
real_sleeps="$base/real_sleeps"; : > "$real_sleeps"
sleep() {
  echo "${FUNCNAME[1]:-?}" >> "$real_sleeps"
  if [ "$(command grep -cx watch_wait "$real_sleeps")" -gt 20 ]; then
    echo "FIXTURE ABORT: watch_wait reached the real sleep more than 20 times — the wait is not virtual" >&2; exit 99
  fi
  command sleep "$@"
}

echo "-- busy-but-silent extends past stage_timeout up to hard_ceiling --"
echo 0 > "$cnt"; echo increasing > "$cpu_mode"
t0=$(vstart)
out=$(watch_wait "$ws" "$decl" fakesess 1 1 1 1 nonceW spec 01 1 "$t0")
dt=$(velapsed)
[ "$out" = "FAIL hard_ceiling" ] \
  && ok "increasing subtree CPU rode past stage_timeout=6 to the hard ceiling ('$out')" \
  || bad "outcome '$out' — CPU-busy did not extend (stage_timeout fired first?)"
[ "$dt" -ge 7 ] \
  && ok "the loop's own clock ran ${dt}s — past stage_timeout (the extension was real)" \
  || bad "returned after ${dt}s of loop time — before the ceiling could matter"
# Deterministic now: hard_ceiling=12 fires on the first iteration where
# now - spawn_t exceeds it, and spawn_t IS the seed — virtual second 13, not a
# second either side, on any machine.
[ "$dt" -eq 13 ] \
  && ok "and it fired at exactly virtual second 13 = hard_ceiling + 1 (the outcome is arithmetic, not a race)" \
  || bad "fired at virtual second ${dt}, want 13 — the loop's time is not the seam's"
command grep -qx watch_wait "$real_sleeps" \
  && bad "watch_wait called the real sleep $(command grep -cx watch_wait "$real_sleeps") time(s) — the wait was not virtual" \
  || ok "and watch_wait never reached the real sleep (the wait was the seam's)"

echo "-- an inactive stage still hits stage_timeout (the budget is not deleted) --"
# The screen must CLAIM work while nothing moves: an awaiting screen with a
# stale heartbeat is the NUDGE path's territory (one nudge -> FAIL idle by
# design — this direction asserted timeout against it and only passed while
# slow config resolution delayed the first classification past the timeout).
pty_classify_screen() { echo working; }
echo 0 > "$cnt"; echo flat > "$cpu_mode"
t0=$(vstart)
out=$(watch_wait "$ws" "$decl" fakesess 1 1 1 1 nonceW2 spec 01 1 "$t0")
[ "$out" = "FAIL timeout" ] \
  && ok "working-claiming screen + flat CPU + stale heartbeat -> FAIL timeout ('$out')" \
  || bad "outcome '$out' — want FAIL timeout for a stage that claims work while nothing moves"
pty_classify_screen() { echo awaiting_input; }
echo 0 > "$cnt"; echo flat > "$cpu_mode"
t0=$(vstart)
out=$(watch_wait "$ws" "$decl" fakesess 1 1 1 1 nonceW2b spec 01 1 "$t0")
[ "$out" = "FAIL idle" ] \
  && ok "awaiting screen + stale heartbeat -> one nudge, then FAIL idle ('$out') — the self-heal window runs BEFORE any timeout" \
  || bad "outcome '$out' — an idle composer should exhaust the nudge window (FAIL idle), not ride to timeout"

# The nudge row must carry WHY the injection was refused, not just its rc. The
# ledger held `inject_rc=3` alone until 2026-09-03, and rc 3 is three different
# refusals — so the one live instance on record can never be attributed. Driven
# end to end here, through the real caller, with the primitive shadowed to fail
# the way it fails in production.
pty_inject() { echo composer_occupied; return 3; }
echo 0 > "$cnt"; echo flat > "$cpu_mode"
t0=$(vstart)
out=$(watch_wait "$ws" "$decl" fakesess 1 1 1 1 nonceW2c spec 01 1 "$t0")
nrow=$(state_get "$ws" ledger 2>/dev/null | command grep 'event=nudge' | tail -1)
command grep -q 'inject_rc=3 inject_why=composer_occupied' <<< "$nrow" \
  && ok "a refused nudge records WHICH refusal beside its rc (inject_rc=3 inject_why=composer_occupied)" \
  || bad "the nudge row does not carry the refusal reason: [$nrow]"
pty_inject() { return 0; }
echo 0 > "$cnt"; echo flat > "$cpu_mode"
t0=$(vstart)
out=$(watch_wait "$ws" "$decl" fakesess 1 1 1 1 nonceW2d spec 01 1 "$t0")
nrow=$(state_get "$ws" ledger 2>/dev/null | command grep 'event=nudge' | tail -1)
command grep -q 'inject_rc=0 inject_why=-' <<< "$nrow" \
  && ok "and a SUCCESSFUL nudge records '-' rather than an empty field — a reading, not a gap" \
  || bad "the successful nudge row's reason field is wrong: [$nrow]"

echo "-- INTERMITTENT busy survives: pauses shorter than the limit never kill --"
# CPU bursts on every SECOND poll read, flat reads between them: the pause is
# one poll iteration — below stage_timeout by construction at any machine
# load (a wall-clock-driven burst gap flaked here: watch_wait's first CPU
# read only sets the delta baseline, and loaded-machine startup + stretched
# iterations let inactivity reach the limit before the second burst landed).
# Total elapsed still blows well past stage_timeout, so a total-elapsed
# reading kills this pattern; the inactivity semantics ride it to the hard
# ceiling. Own literals: a wider timeout/ceiling pair keeps the one-iteration
# pause far from the limit while the ride stays visibly past the timeout.
window
calls="$base/cpu.calls"; echo 0 > "$calls"
watch_subtree_cpu() {
  local n c
  n=$(cat "$cnt"); c=$(( $(cat "$calls") + 1 )); echo "$c" > "$calls"
  if [ $((c % 2)) -eq 0 ]; then
    echo $((n + 200)) > "$cnt"   # a fresh burst after each one-iteration pause
  fi
  cat "$cnt"
}
echo 0 > "$cnt"
t0=$(vstart)
out=$(watch_wait "$ws" "$decl" fakesess 1 1 1 1 nonceW3 spec 01 1 "$t0")
dt=$(velapsed)
[ "$out" = "FAIL hard_ceiling" ] \
  && ok "busy-pause-busy alternation survives to the ceiling ('$out') — pauses below the limit are not a death sentence" \
  || bad "outcome '$out' after ${dt}s — an intermittently busy stage was killed (total-elapsed semantics, not inactivity)"
[ "$dt" -ge 9 ] \
  && ok "loop time ${dt}s: past stage_timeout=6 with only paused stretches in between — the alternation was exercised" \
  || bad "returned after ${dt}s — too early for the alternation to have been exercised"

echo "-- idle NOISE is not work: a below-floor CPU trickle must not extend anything --"
# The wedge that cost ~6h and a day's quota: an idle CLI at a few percent of a
# core produced a nonzero delta on every poll, the test was "any increase", and
# each poll therefore reset the inactivity clock, the nudge and the working
# episode. Nothing but the 3h ceiling could end it. Here the trickle is 5
# jiffies per 1s poll (5% of a core) against a floor of 25, and the loop must
# fall through to the classification it was skipping.
# This arm carries a WIDER liveness window than the three above, and the
# reason was measured before the loop ran on the seam: the intended exit is the
# awaiting-input ladder, wall-clocked from its own nudge, and it landed at
# roughly 6 + 1.6 x (per-iteration stretch) seconds — so the shared window's
# `stage_timeout=6` BEAT the ladder on any loaded machine (FAIL timeout at
# stretch 5 and 8, measured), the fixture racing itself. On the virtual clock
# the ladder lands at a fixed virtual second and nothing can stretch an
# iteration, so the race is gone; the window stays because its ratio mirrors
# production (nudge_grace 180 against stage_timeout 1800), and the `live_class`
# assertion below stays as the discriminator that needs no clock at all.
# `stage_timeout <= hard_ceiling` is a config RULE (rule.liveness_window), so
# both move together.
window liveness.stage_timeout=45 liveness.hard_ceiling=60
pty_classify_screen() { echo awaiting_input; }
watch_subtree_cpu() { local n; n=$(( $(cat "$cnt") + 5 )); echo "$n" > "$cnt"; echo "$n"; }
echo 0 > "$cnt"
t0=$(vstart)
out=$(watch_wait "$ws" "$decl" fakesess 1 1 1 1 nonceW4 spec 01 1 "$t0")
dt=$(velapsed)
[ "$out" = "FAIL idle" ] \
  && ok "a 5%-of-a-core trickle no longer reads as work ('$out' after ${dt}s) — pre-fix it rode to the ceiling" \
  || bad "outcome '$out' after ${dt}s — want FAIL idle; an idle CLI's baseline CPU is still counting as activity"
[ "$dt" -lt 45 ] \
  && ok "and it ended BEFORE the hard ceiling (${dt}s, ceiling 60) — the ceiling is no longer the only backstop" \
  || bad "took ${dt}s: the ceiling was still what ended it"
# The direct discriminator, which no deadline can race: the loop PUBLISHES the
# class it acted on. If the trickle had read as work the last note would be
# `busy_cpu` (that branch notes and continues), and with the bug present it is
# the only branch that ever runs. Measured against the buggy stub (500 jiffies
# a poll, over the floor): outcome FAIL hard_ceiling at 61s, last class busy_cpu.
lc=$(state_field "$ws" stage live_class 2>/dev/null || echo "(unset)")
[ "$lc" = "awaiting_input" ] \
  && ok "and the loop's own published class is 'awaiting_input', never 'busy_cpu' — the trickle was not acted on as work" \
  || bad "published live_class='$lc' — the CPU branch is what the loop acted on"
# restore the window the arms BELOW were written against — every key of it,
# `stop_gate_blocks_max=3` included: dropping that one silently returns the
# counter to the default 6 and the wedge arms below stop firing (measured).
window

echo "-- repeated Stop-gate blocks fail the attempt (the CLI can override the hook; the ferry cannot be blind to that) --"
# The gate blocked 9 times and the CLI's own block cap then forced the turn to
# end; no record ever came and the stage surface read running for hours. The
# hook's exit code is invisible to the ferry, so the count travels through the
# attempt's own audit trail.
( . "$RS/lib/state.sh"
  for i in 1 2 3; do
    state_append "$ws" audit session "v=1 t=$(date +%s) by=session msg=stop_gate_block nonce=nonceW5 stage=spec — turn end refused" > /dev/null
  done )
echo 0 > "$cnt"; echo flat > "$cpu_mode"
watch_subtree_cpu() { cat "$cnt"; }
pty_classify_screen() { echo working; }
t0=$(vstart)
out=$(watch_wait "$ws" "$decl" fakesess 1 1 1 1 nonceW5 spec 01 1 "$t0")
dt=$(velapsed)
[ "$out" = "FAIL wedged" ] \
  && ok "three blocks for this attempt -> FAIL wedged ('$out' after ${dt}s), not a working-claiming screen believed to the timeout" \
  || bad "outcome '$out' — a session that cannot finish its turn stayed invisible"
t0=$(vstart)
out=$(watch_wait "$ws" "$decl" fakesess 1 1 1 1 nonceOTHER spec 01 1 "$t0")
# Equality, not inequality: any output except the literal used to pass —
# including an EMPTY one from a run that never reached its verdict. The
# healthy verdict for a foreign nonce is the stage timeout, so the whole
# path is pinned: no blocks counted, and the run still concluded.
[ "$out" = "FAIL timeout" ] \
  && ok "another attempt's blocks do NOT fail this one ('$out', the healthy verdict — the count is nonce-scoped)" \
  || bad "outcome '$out', want FAIL timeout — blocks for a different nonce failed this attempt, or the run never reached its verdict"

# The wedge must be seen THROUGH activity: a fresh heartbeat (a tool-calling
# loop) and a busy CPU each `continue` past every branch below them, which is
# the shape that hid the measured one. This is the same wedged attempt with
# both signals alive.
( . "$RS/lib/state.sh"; printf 't=%s\n' "$(date +%s)" | state_set "$ws" heartbeat session ) > /dev/null
watch_subtree_cpu() { local n; n=$(( $(cat "$cnt") + 5000 )); echo "$n" > "$cnt"; echo "$n"; }
t0=$(vstart)
out=$(watch_wait "$ws" "$decl" fakesess 1 1 1 1 nonceW5 spec 01 1 "$t0")
[ "$out" = "FAIL wedged" ] \
  && ok "a fresh heartbeat AND an above-floor CPU burn do not hide it ('$out') — the session's own statement outranks both inferences" \
  || bad "outcome '$out' — a wedged session that still looks active stayed invisible"

echo "-- a zero-quota session reaches the stop-gate counter FIRST; the stronger statement still parks --"
# Measured 2026-08-21 on the live topic: a session born into a zero-quota window
# cannot work, so it re-ends its turn about once a second — attempt 1 took 9
# blocks in 9s, attempt 2 nine in 6s. stop_gate_blocks_max was therefore spent
# 38 lines before the screen is classified and 76 before the quota arm, so the
# `quota_exhausted` arm below CANNOT FIRE for the condition it was written for:
# the run FAILs wedged, the ferry respawns into the same dead window, and the
# halt reads `no_novelty`. probe.sh's own quota bypass keys on
# `halt reason == backend_quota`, so this defect silently disarms that one too.
# The pane here says exactly what the live one said (claude.kv's own signature).
( . "$RS/lib/state.sh"
  for i in 1 2 3; do
    state_append "$ws" audit session "v=1 t=$(date +%s) by=session msg=stop_gate_block nonce=nonceQ stage=spec — turn end refused" > /dev/null
  done )
_pty_capture() { printf '%s\n' "Claude usage limit reached. Your limit will reset at 3pm"; }
_watch_pane_history() { _pty_capture "$1"; }
echo 0 > "$cnt"; watch_subtree_cpu() { cat "$cnt"; }
pty_classify_screen() { echo working; }
out=$(watch_wait "$ws" "$decl" fakesess 1 1 1 1 nonceQ spec 01 1 "$(vstart)")
case "$out" in
  "PARK backend_quota "*)
    ok "quota line on the pane + the counter at cap -> PARK backend_quota ('$out')" ;;
  "FAIL wedged")
    bad "outcome '$out' — the counter got there first and the backend's own quota statement was never consulted; the ferry will respawn into a window where nothing can succeed" ;;
  *) bad "outcome '$out' — want PARK backend_quota" ;;
esac
command grep -q 'usage limit reached' <<< "$out" \
  && ok "the park detail carries the backend's own sentence verbatim (it names the reset time; the workflow never computes one)" \
  || bad "park line '$out' does not carry the pane's own quota sentence"

# The SAME question for the other statement that outranks "I cannot finish this
# turn": a backend returning 529 cannot finish one either, and the counter gets
# there first for the same reason (a session that cannot reach the model ends
# its turn fast). Asked second, because quota is the stronger statement.
_pty_capture() { printf '%s\n' "API Error: 529 Overloaded. This is a server-side issue, usually temporary"; }
_watch_pane_history() { _pty_capture "$1"; }
echo 0 > "$cnt"; watch_subtree_cpu() { cat "$cnt"; }
pty_classify_screen() { echo working; }
out=$(watch_wait "$ws" "$decl" fakesess 1 1 1 1 nonceQ spec 01 1 "$(vstart)")
case "$out" in
  "PARK backend_overloaded "*)
    ok "529 banner on the pane + the counter at cap -> PARK backend_overloaded ('$out')" ;;
  "FAIL wedged")
    bad "outcome '$out' — the counter got there first and the backend's own 529 banner was never consulted; the ferry respawns into a window where nothing can succeed" ;;
  *) bad "outcome '$out' — want PARK backend_overloaded" ;;
esac
_pty_capture() { printf '%s\n' "Claude usage limit reached. Your limit will reset at 3pm"; }
_watch_pane_history() { _pty_capture "$1"; }

# The decision is made on the visible frame; reading the operator-facing TEXT
# must not be able to RETRACT it. watch.sh runs under `pipefail`, so a
# history read that matches nothing makes the whole extraction pipeline exit
# non-zero — and the first version of this helper returned that status, which
# put the run back on `FAIL wedged` with the quota line plainly on screen.
# The race is real on a live pane: the frame is captured twice, and scrollback
# can move between them.
_watch_pane_history() { return 0; }   # history read comes back empty
out=$(watch_wait "$ws" "$decl" fakesess 1 1 1 1 nonceQ spec 01 1 "$(vstart)")
case "$out" in
  "PARK backend_quota "*)
    ok "an empty history read does not retract a decision the visible frame already made ('$out')" ;;
  *) bad "outcome '$out' — the text read overruled the decision; the pane says the backend is out and the ferry respawns anyway" ;;
esac
command grep -q 'not captured' <<< "$out" \
  && ok "and the park says the line was not captured rather than inventing one" \
  || bad "park line '$out' — with no text captured the detail must say so"
_watch_pane_history() { _pty_capture "$1"; }

# Staleness direction: the VISIBLE frame decides. An exhaustion line that has
# scrolled out of view is what the backend said earlier, not what it says now —
# reading it from the scrollback would turn every later wedge on this pane into
# a quota park.
# The line must be IN the scrollback and OUT of the visible frame, or this arm
# tests nothing: with both reads empty it passes whichever read the code
# consults, which is what the first version of it did (caught by mutating the
# consult to read history — the arm did not notice).
_pty_capture() { printf 'nothing to see here\n'; }
_watch_pane_history() { printf '%s\n' "Claude usage limit reached. Your limit will reset at 1pm"; }
# In-process: the overrides above live in THIS shell, so a `bash -c` probe
# would test a shell that has none of them.
_hist_has_sig() { _watch_pane_history x | command grep -qE "$(pty_decl_get "$decl" sig.quota_exhausted)"; }
precond "the scrollback really carries a line the signature matches (else the arm is vacuous)" _hist_has_sig
out=$(watch_wait "$ws" "$decl" fakesess 1 1 1 1 nonceQ spec 01 1 "$(vstart)")
[ "$out" = "FAIL wedged" ] \
  && ok "a quota line only in the SCROLLBACK does not park ('$out') — the visible frame is the domain, as in pty_classify_screen" \
  || bad "outcome '$out' — a scrolled-away quota line fabricated a park"
# Back to the fixture's paneless default: with no tmux session behind
# `fakesess`, this is what the real _pty_capture/_watch_pane_history do.
_pty_capture() { return 1; }
_watch_pane_history() { return 1; }

echo "-- a quota-dead backend parks instead of burning attempts on calls that cannot succeed --"
pty_classify_screen() { echo quota_exhausted; }
echo 0 > "$cnt"
t0=$(vstart)
out=$(watch_wait "$ws" "$decl" fakesess 1 1 1 1 nonceW6 spec 01 1 "$t0")
case "$out" in
  "PARK backend_quota "*) ok "quota_exhausted -> PARK backend_quota with the screen attached ('$out')" ;;
  *) bad "outcome '$out' — want PARK backend_quota (a respawn here spends attempts on a dead backend)" ;;
esac
pty_classify_screen() { echo awaiting_input; }

echo "-- a backend that is UP and REFUSING parks too, and says it has no clock to wait on --"
# The 529 case. Same economics as quota one arm up — the session is alive and
# correct, the backend cannot answer — but with NO reset time to forward.
# Measured 2026-09-03 (slice 05 postcheck): the class did not exist, the pane
# read `awaiting_input` once the CLI's retry ladder exhausted, and two attempts
# and ~17 minutes went to a backend that was out, ending in a `no_novelty` park
# on an identical fingerprint.
_pty_capture() { printf '%s\n' "API Error: 529 Overloaded. This is a server-side issue, usually temporary"; }
_watch_pane_history() { _pty_capture "$1"; }
pty_classify_screen() { echo backend_overloaded; }
echo 0 > "$cnt"
out=$(watch_wait "$ws" "$decl" fakesess 1 1 1 1 nonceOV spec 01 1 "$(vstart)")
case "$out" in
  "PARK backend_overloaded "*) ok "backend_overloaded -> PARK backend_overloaded ('$out')" ;;
  "FAIL idle"|"FAIL wedged") bad "outcome '$out' — the ferry respawns into a backend that cannot answer; this is the measured defect" ;;
  *) bad "outcome '$out' — want PARK backend_overloaded" ;;
esac
command grep -q '529 Overloaded' <<< "$out" \
  && ok "the park detail carries the backend's own banner verbatim" \
  || bad "park line '$out' does not carry the pane's own 529 banner"
# The one thing that must differ from quota's park text, because it is the one
# thing an operator acts on: quota forwards a RESET TIME and this state has
# none to forward. A park line that implied a wait would be inventing it.
command grep -q 'no reset time is published' <<< "$out" \
  && ok "and it says there is NO clock to wait on (relaunch on judgment — quota's park says the opposite, deliberately)" \
  || bad "park line '$out' — an operator cannot tell this from a quota park, and the two need opposite actions"

echo "-- a retrying backend is NOT nudged and does NOT fail as idle --"
# `error_retryable` was classified correctly and then handled as a liveness
# failure: it shared ONE case arm with `awaiting_input`, so a CLI in API
# backoff was nudged ("continue" into a mid-backoff client — harmless and
# useless) and its attempt failed as `idle`. The ledger then recorded
# `inject_rc=0` beside a failure the injection had nothing to do with, which is
# what made the live episode read as a stall.
_pty_capture() { printf '%s\n' "Retrying in 37s (attempt 9/10)"; }
_watch_pane_history() { _pty_capture "$1"; }
pty_classify_screen() { echo error_retryable; }
nudges_before=$( . "$RS/lib/state.sh"; state_get "$ws" ledger 2>/dev/null | command grep -c 'event=nudge' || true )
echo 0 > "$cnt"
# retry_grace shrunk to seconds so the arm can reach the bound; the shipped
# value is 900 and no fixture may wait it out.
printf 'liveness.retry_grace=1\n' >> "$ws/config/topic.kv"
out=$(watch_wait "$ws" "$decl" fakesess 1 1 1 1 nonceRT spec 01 1 "$(vstart)")
[ "$out" = "FAIL backend_retrying" ] \
  && ok "a ladder past its grace fails with the CAUSE named ('$out') — 'FAIL idle' here is a misattribution the ledger preserves" \
  || bad "outcome '$out' — want FAIL backend_retrying; a retrying backend that fails as 'idle' sends a postmortem to look at the session, and the session was fine"
nudges_after=$( . "$RS/lib/state.sh"; state_get "$ws" ledger 2>/dev/null | command grep -c 'event=nudge' || true )
[ "$nudges_after" = "$nudges_before" ] \
  && ok "and NOT ONE nudge was injected into a mid-backoff client ($nudges_before before, $nudges_after after)" \
  || bad "the loop nudged a retrying CLI ($nudges_before -> $nudges_after) — injection cannot help mid-backoff and the rc lands beside an unrelated failure"
# The other half of "its own clock": inside the grace it must WAIT, not fail.
# Without this the arm above would pass over a loop that failed instantly.
# stage_timeout is shrunk WITH it: this arm deliberately runs to the outer
# bound, and an earlier block in this file raised the fixture's timeout to 45s.
# Riding that costs the suite 45 seconds to prove a 3-second property.
plat_sed_i 's/^liveness.retry_grace=1$/liveness.retry_grace=9000/' "$ws/config/topic.kv"
printf 'liveness.stage_timeout=3\n' >> "$ws/config/topic.kv"
out=$(watch_wait "$ws" "$decl" fakesess 1 1 1 1 nonceRT2 spec 01 1 "$(vstart)")
[ "$out" != "FAIL backend_retrying" ] && [ "$out" != "FAIL idle" ] \
  && ok "inside its grace the ladder is allowed to run ('$out' — the stage timeout still bounds it from outside)" \
  || bad "outcome '$out' — the retry arm fails regardless of its own grace, so the grace is decoration"
plat_sed_i '/^liveness.retry_grace=/d; /^liveness.stage_timeout=3$/d' "$ws/config/topic.kv"
_pty_capture() { return 1; }
_watch_pane_history() { return 1; }
pty_classify_screen() { echo awaiting_input; }

echo "-- the loop publishes the quantities it COMPARES, not just how long it has run --"
# The monitor renders `idle vs stage_timeout` and `elapsed vs hard_ceiling`.
# Those must come from here: idle (now - last_activity) is what line ~157
# compares, and it is NOT derivable from the age or the heartbeat age (a CPU
# delta resets it without any heartbeat). A panel that renders age against
# stage_timeout shows a healthy stage draining toward an unreachable limit —
# measured on the live topic, and misread by the operator.
idle=$(state_field "$ws" stage live_idle 2>/dev/null || true)
age=$(state_field "$ws" stage live_age 2>/dev/null || true)
case "$idle" in
  ''|*[!0-9]*) bad "no numeric live_idle on the stage surface after a real wait loop (got '$idle') — the panel's inactivity clock has no source" ;;
  *) ok "live_idle published ($idle s) — the inactivity clock the timeout is compared against" ;;
esac
case "$age" in
  ''|*[!0-9]*) bad "no numeric live_age (got '$age')" ;;
  *) [ "$age" -ge "$idle" ] \
       && ok "live_age ($age s) >= live_idle ($idle s): they are two different quantities, and the panel must not show one as the other" \
       || bad "live_age $age < live_idle $idle — the two clocks are wired backwards" ;;
esac

echo "-- protocol-derived idleness: a fresh CLI idle_prompt is primary over an unclassifiable pane --"
# Three directions (the protocol-idleness arm): FRESH event + unknown screen → the nudge
# ladder runs (FAIL idle eventually), never PARK unknown_screen; STALE event
# or NO surface → PARK unknown_screen, byte-identical to the pre-arm
# behavior — backends without the hook surface (codex today) ride this arm.
# pty_classify_screen overridden to unknown; pty_inject succeeds; no handoff
# record ever lands, so the ladder's end is FAIL idle (nudge_grace=2 after
# the one nudge).
window liveness.notify_fresh=30
pty_classify_screen() { echo unknown; }
# Flat CPU by override, not by mode-file reset: an earlier scenario may have
# replaced the stub wholesale (later definitions win in one shell), and a
# busy_cpu branch resets the nudge count every poll — the ladder would never
# terminate and these arms would hit the ceiling instead of their ends.
watch_subtree_cpu() { echo 0; }

# The PRODUCER half, run as the CLI runs it. Every arm below writes the
# notify_events surface with state_append, which proves what watch_wait does
# with a row and says nothing about whether a row can ever exist: the hook that
# writes it — `session/notify_event.sh`, wired in the profile as the
# Notification handler and asserted there by 30-closure — had never been
# EXECUTED by any check. heartbeat.sh, its one-way sibling, is executed (the
# drill's mock CLI calls it), which is the whole difference in how the two have
# held up. Runs the script the way the hook does: payload on stdin, workspace
# and session name as argv.
nev=$(sc_tmpdir); mkdir -p "$nev/.runtime/state"
printf '%s' '{"type":"idle_prompt","message":"waiting for your input"}' \
  | bash "$RS/session/notify_event.sh" "$nev" hooksess > "$nev/hook.err" 2>&1; hrc=$?
[ $hrc -eq 0 ] \
  && ok "the Notification hook exits 0 (it can only observe, never block the CLI)" \
  || bad "notify_event.sh exited $hrc: $(head -2 "$nev/hook.err")"
hrow=$(state_get "$nev" notify_events 2>/dev/null || true)
command grep -q 'session=hooksess type=idle_prompt' <<< "$hrow" \
  && ok "and the row it writes is the one watch_proto_idle reads (session + type)" \
  || bad "no idle_prompt row on the surface after the hook ran — the producer half is dead, and every arm below would still pass: surface=[$hrow] stderr=[$(head -2 "$nev/hook.err")]"
command grep -q 'msg=waiting for your input' <<< "$hrow" \
  && ok "and it carries the CLI's own message text for the postmortem" \
  || bad "message not recorded: $hrow"
# a shape the extractor does not know is RECORDED, never dropped (its own rule)
printf '%s' '{"kind":"something-else"}' \
  | bash "$RS/session/notify_event.sh" "$nev" hooksess > /dev/null 2>&1
state_get "$nev" notify_events 2>/dev/null | command grep -q 'type=unparsed' \
  && ok "an unrecognised payload lands as type=unparsed rather than vanishing" \
  || bad "an unparsed payload left no row — a postmortem cannot see what arrived"

# THE LIVE SHAPE, and what it now does. Both arms above drive the producer with
# a payload this CHECK authors, so between them they prove the extractor against
# its own writing — the one thing a fixture cannot be trusted to do alone. What
# production sends was never recorded until this round: the hook kept `type` and
# a 120-char `msg` slice and discarded the JSON, so there is no captured payload
# to replay here and this arm does not pretend to be one. What IS measured is
# the ROW production yields. Every notify_events surface that exists (three, all
# under plans/archives, each read whole): 74 + 25 + 28 = 127 rows across three
# topics, 2026-08-23 to 2026-08-31. 127 of 127 read `type=unparsed`; 127 of 127
# read `msg=Claude is waiting for your input`. Two things follow, and only those
# two are asserted here: the live payload carries nothing matching the
# extractor's type pattern, and the discriminator rides the message text. The
# fields standing around `message` in the fixture are neither measured nor
# load-bearing. Corroborated from a SECOND surface so this does not rest on one
# instrument: `protocol idleness` audit lines across the four archived audit
# surfaces number 0 of 731 rows — the arm had never once fired.
nevl=$(sc_tmpdir); mkdir -p "$nevl/.runtime/state"
# THE MEASURED PAYLOAD, byte for byte, from the first raw capture this tree ever
# kept (`.runtime/notify-raw.first.json`, CLI 2.1.259). It is here because the fixture that stood in this slot was a shape
# the CHECK invented — a payload with no type field at all — and the real one
# carries `notification_type`, which the extractor's `"type"` pattern cannot
# match. So the field arm had never fired, the message path carried all 62 live
# rows of that topic, and every arm in this file passed. That is the producer
# proving the extractor against the check's own writing, one layer out from the
# same defect this file already caught twice.
printf '%s' '{"session_id":"b2afee95-848d-4a5a-b8bc-f0de71d13ed4","transcript_path":"/home/x/b2afee95.jsonl","cwd":"/home/x/delivery","prompt_id":"c5ef4167-b97f-451f-902e-268d74836e86","hook_event_name":"Notification","message":"Claude is waiting for your input","notification_type":"idle_prompt"}' \
  | bash "$RS/session/notify_event.sh" "$nevl" measuredsess > /dev/null 2>&1
mrow=$(state_get "$nevl" notify_events 2>/dev/null || true)
command grep -q 'session=measuredsess type=idle_prompt type_src=field' <<< "$mrow" \
  && ok "the MEASURED live payload classifies from its FIELD (notification_type) — type_src=field" \
  || bad "the measured payload did not classify from its field: [$mrow]"
# And `hook_event_name":"Notification"` in the same payload must not answer:
# the value class is lowercase precisely so a capitalised event name cannot.
command grep -qv 'type=Notification' <<< "$mrow" \
  && ok "and the capitalised hook_event_name did not answer for it" \
  || bad "the event name was read as the type: [$mrow]"

# The payload's OTHER durable field. The CLI hands the path of its own
# transcript, which retains the tool stdout the pane log discards (measured
# 2026-09-05 with runtime-only literals: `learning recorded (leak_class=gate,
# record=gates)` reads 1 of 199 transcripts against 0 of 98 pane logs). This
# file used to read the payload for one field and drop the rest, so three
# validation-debt rows recorded "no instrument" for evidence that was
# addressable all along. Keeping the path is what makes it resolvable per
# session rather than guessable from cwd and timing.
command grep -qF 'transcript=/home/x/b2afee95.jsonl' <<< "$mrow" \
  && ok "the measured payload's transcript_path is kept on the row" \
  || bad "transcript_path was dropped from the row: [$mrow]"
# ORDERING is load-bearing and is asserted, not assumed: `msg` carries the
# CLI's own sentence and therefore spaces, so it must stay LAST or a
# field-scanning reader loses everything after it.
command grep -qE 'transcript=[^ ]+ msg=' <<< "$mrow" \
  && ok "…and it sits BEFORE msg, which must stay last because it carries spaces" \
  || bad "field order broken — msg is no longer last: [$mrow]"
# Absent field -> the honest value, the same word msg uses. The degraded
# fixture below carries no transcript_path at all.
nevt=$(sc_tmpdir); mkdir -p "$nevt/.runtime/state"
printf '%s' '{"hook_event_name":"Notification","message":"Claude is waiting for your input"}' \
  | bash "$RS/session/notify_event.sh" "$nevt" notrans > /dev/null 2>&1
state_get "$nevt" notify_events 2>/dev/null | command grep -q 'transcript=none' \
  && ok "a payload with no transcript_path lands transcript=none (absent is named, never blank)" \
  || bad "an absent transcript_path did not land 'none': [$(state_get "$nevt" notify_events 2>/dev/null)]"
# A path carrying whitespace would silently eat every field after it. The
# guard refuses it rather than corrupting the row, and the proof is that msg
# survives INTACT beside the refusal.
printf '%s' '{"transcript_path":"/home/x/a b.jsonl","hook_event_name":"Notification","message":"Claude is waiting for your input","notification_type":"idle_prompt"}' \
  | bash "$RS/session/notify_event.sh" "$nevt" spacetrans > /dev/null 2>&1
srow=$(state_get "$nevt" notify_events 2>/dev/null | command grep 'session=spacetrans' | tail -1)
command grep -q 'transcript=none' <<< "$srow" \
  && ok "a whitespace-bearing transcript_path is refused to 'none' (a row field is space-delimited)" \
  || bad "a path with a space was written into the row: [$srow]"
command grep -qF 'msg=Claude is waiting for your input' <<< "$srow" \
  && ok "…and the fields after it survive intact, which is what the guard is for" \
  || bad "the space-bearing path corrupted the row: [$srow]"

# The DEGRADED shape: a payload with no type field at all. Check-authored, and
# labelled as such — whether any live build sends this is unknown, because the
# 127 archived rows that read `type=unparsed` had their raw bytes discarded.
# The path is kept because a build that drops the field must still classify.
printf '%s' '{"hook_event_name":"Notification","message":"Claude is waiting for your input"}' \
  | bash "$RS/session/notify_event.sh" "$nevl" livesess > /dev/null 2>&1
lrow=$(state_get "$nevl" notify_events 2>/dev/null || true)
command grep -q 'session=livesess type=idle_prompt type_src=message' <<< "$lrow" \
  && ok "a payload with NO type field still classifies from its message text — type_src=message (the degraded path)" \
  || bad "the type-less payload did not classify: [$lrow]"
command grep -qF 'msg=Claude is waiting for your input' <<< "$lrow" \
  && ok "and its message text still survives intact for the postmortem" \
  || bad "the live message text was not preserved: [$lrow]"
# The consequence the whole path exists for. Before the message source landed,
# watch_proto_idle read NOTHING from the live shape — 127 of 127 rows discarded.
lpt=$(watch_proto_idle "$nevl" livesess "$(date +%s)" 30)
[ -n "$lpt" ] \
  && ok "and watch_proto_idle READS it (t=$lpt) — the protocol-idleness arm has a live input for the first time" \
  || bad "watch_proto_idle read nothing from the live shape — the protocol-idleness arm is inert again"
# The arm above is only meaningful if the reader answers from the store it was
# GIVEN. It did not: watch_proto_idle read an ambient $ws and its documented
# first parameter was dead, so this arm returned a false negative on its first
# run. Pinned in the direction that catches a regression — a store with no rows
# passed as $1, while the ambient $ws holds a matching fresh row.
nevx=$(sc_tmpdir); mkdir -p "$nevx/.runtime/state"
amb=$( ws=$nevl; watch_proto_idle "$nevx" livesess "$(date +%s)" 30 )
[ -z "$amb" ] \
  && ok "watch_proto_idle answers from the workspace it is PASSED, not from an ambient one" \
  || bad "watch_proto_idle returned $amb for an empty store — it is reading the ambient \$ws again"
# DISCRIMINABILITY (review-standards section 13 step 4): the same resulting type
# must be distinguishable by its SOURCE. Without this pair, a regression to the
# field-only extractor still passes every check-authored arm above.
printf '%s' '{"type":"idle_prompt","message":"whatever"}' \
  | bash "$RS/session/notify_event.sh" "$nevl" fieldsess > /dev/null 2>&1
state_get "$nevl" notify_events 2>/dev/null | command grep -q 'session=fieldsess type=idle_prompt type_src=field' \
  && ok "an explicit type still wins and is labelled type_src=field — same type as the arm above, different source" \
  || bad "an explicit type was not used or not labelled: [$(state_get "$nevl" notify_events 2>/dev/null | tail -1)]"
# An unclassifiable payload still lands, and now leaves its RAW bytes behind —
# the evidence whose absence kept this arm unproven through three topics and 127 rows.
printf '%s' '{"kind":"a shape nothing knows"}' \
  | bash "$RS/session/notify_event.sh" "$nevl" rawsess > /dev/null 2>&1
state_get "$nevl" notify_events 2>/dev/null | command grep -q 'session=rawsess type=unparsed type_src=none' \
  && ok "an unrecognised payload still lands type=unparsed, labelled type_src=none" \
  || bad "the unrecognised payload did not land as unparsed/none"
command grep -qF 'a shape nothing knows' "$nevl/.runtime/notify-raw.unparsed.json" 2>/dev/null \
  && ok "and its RAW payload is kept in notify-raw.unparsed.json — the shape question is answerable next time" \
  || bad "the unclassifiable payload's raw bytes were not persisted"
command grep -qF 'Claude is waiting for your input' "$nevl/.runtime/notify-raw.first.json" 2>/dev/null \
  && ok "notify-raw.first.json is write-once and still holds the FIRST payload, not the latest" \
  || bad "notify-raw.first.json does not hold the first payload: [$(cat "$nevl/.runtime/notify-raw.first.json" 2>/dev/null)]"
# An EMPTY payload must not claim the write-once slot. The first firing to arrive
# empty would otherwise hold notify-raw.first.json forever and leave the shape
# question permanently open — found by exercising the fix, not by reading it.
neve=$(sc_tmpdir); mkdir -p "$neve/.runtime/state"
printf '' | bash "$RS/session/notify_event.sh" "$neve" emptysess > /dev/null 2>&1
[ ! -e "$neve/.runtime/notify-raw.first.json" ] \
  && ok "an empty payload does NOT claim the write-once raw slot (it carries no shape to keep)" \
  || bad "an empty payload claimed notify-raw.first.json — the real first shape could never be recorded"
state_get "$neve" notify_events 2>/dev/null | command grep -q 'session=emptysess type=unparsed type_src=none transcript=none msg=none' \
  && ok "and the empty firing is still RECORDED as unparsed/none — never dropped (whole row shape pinned, transcript included)" \
  || bad "the empty firing left no row"

# The OTHER one-way session hook, for the same reason. heartbeat.sh IS executed
# by the drill's mock CLI, so it has never been silently broken — but nothing
# asserted what it WRITES, and a hook that stamps a constant survives the whole
# suite (measured). The stamp is liveness signal #2: with it frozen, `hb_age`
# never falls under `heartbeat_fresh`, so a genuinely busy session loses its
# primary evidence and rides on the CPU floor and the screen alone.
hbw=$(sc_tmpdir); mkdir -p "$hbw/.runtime/state"
t_before=$(date +%s)
bash "$RS/session/heartbeat.sh" "$hbw" > "$hbw/hb.err" 2>&1; hbrc=$?
hbt=$(state_field "$hbw" heartbeat t 2>/dev/null || echo "")
[ $hbrc -eq 0 ] && ok "the PreToolUse hook exits 0 (a heartbeat must never block a tool call)" \
  || bad "heartbeat.sh exited $hbrc: $(head -2 "$hbw/hb.err")"
case "$hbt" in
  ''|*[!0-9]*) bad "heartbeat wrote t='$hbt' — not an epoch, so hb_age is meaningless" ;;
  *) [ "$hbt" -ge "$t_before" ] && [ "$hbt" -le $(( t_before + 30 )) ] \
       && ok "and it stamps the CURRENT epoch ($hbt) — a frozen stamp would leave every session permanently stale" \
       || bad "heartbeat stamped t=$hbt against now=$t_before — the freshness window reads this difference" ;;
esac
bash "$RS/session/heartbeat.sh" > /dev/null 2>&1 \
  && ok "and a missing workspace argument still exits 0 (its own contract: never block the agent)" \
  || bad "heartbeat.sh with no argument exited non-zero — a hook failure would surface as a tool-call failure"

# absent surface: pre-arm behavior, unchanged
out=$(watch_wait "$ws" "$decl" fakesess 1 1 1 1 nonceP1 spec 01 1 "$(vstart)")
case "$out" in
  "PARK unknown_screen "*) ok "no notify_events surface -> PARK unknown_screen unchanged (backends without the hook ride this path)" ;;
  *) bad "outcome '$out' — want PARK unknown_screen with no protocol evidence" ;;
esac

# stale event: still no evidence (freshness window is the whole guard)
state_append "$ws" notify_events session \
  "v=1 t=$(( $(date +%s) - 3600 )) session=fakesess type=idle_prompt msg=stale" >/dev/null
out=$(watch_wait "$ws" "$decl" fakesess 1 1 1 1 nonceP2 spec 01 1 "$(vstart)")
case "$out" in
  "PARK unknown_screen "*) ok "stale idle_prompt (> freshness window) -> still PARK unknown_screen" ;;
  *) bad "outcome '$out' — a stale event must not reclassify" ;;
esac

# fresh event: the protocol statement reclassifies; the ladder runs
state_append "$ws" notify_events session \
  "v=1 t=$(date +%s) session=fakesess type=idle_prompt msg=idle" >/dev/null
out=$(watch_wait "$ws" "$decl" fakesess 1 1 1 1 nonceP3 spec 01 1 "$(vstart)")
case "$out" in
  "FAIL idle") ok "fresh idle_prompt + unknown screen -> awaiting_input ladder (FAIL idle past nudge grace), never parked" ;;
  "PARK unknown_screen "*)
    bad "fresh protocol event did NOT reclassify — the arm is dead" ;;
  *) bad "outcome '$out' — want FAIL idle (ladder), got something else" ;;
esac

# permission_prompt is recorded but NOT acted on (surfaced, not auto-answered).
# Function-level isolation: a session whose only event is a fresh
# permission_prompt gets NO protocol idleness (the loop's only key into the
# surface is this function, so empty here = no reclassification there).
state_append "$ws" notify_events session \
  "v=1 t=$(date +%s) session=permprobe type=permission_prompt msg=perm" >/dev/null
pt=$(watch_proto_idle "$ws" permprobe "$(date +%s)" 30)
[ -z "$pt" ] \
  && ok "a fresh permission_prompt alone yields NO protocol idleness (recorded for audit, never acted on)" \
  || bad "watch_proto_idle acted on permission_prompt (t=$pt) — config drift would be nudged, not surfaced"
grep -q 'session=permprobe type=permission_prompt' <(state_get "$ws" notify_events 2>/dev/null) \
  && ok "the permission_prompt event is recorded on the surface (audit trail)" \
  || bad "permission_prompt event not recorded — postmortems lose the fact"

pty_classify_screen() { echo awaiting_input; }

echo "-- every episode clock this loop compares against now is amnesty-shifted --"
# A GRAMMAR arm, not a list, and it exists because the list went short a member
# the first time one was added: `retry_since` (the backend-retry arm, 2026-09-04)
# was compared against `now` and not shifted, so a suspend or an NTP step during
# a backoff would have counted the suspended interval toward the retry grace and
# failed the attempt on a clock that never ran. Nothing was red — the amnesty is
# a hand-maintained enumeration, which is precisely the shape that goes short.
#
# The rule: every `now - <name>` inside watch_wait is either shifted in the
# amnesty block or named EXEMPT here with its reason. Exemptions are the two
# that are not episode clocks:
#   last_tick   — the amnesty's own INPUT (it measures the gap), reassigned to
#                 $now on the line after, so shifting it would be circular
#   hb / proto_t — values read fresh from the store each poll, not accumulated
#                 across polls, so there is no drift for a shift to correct
#   progress_seen — a COUNT of progress rows, not an epoch; the name is shared
#                 with the timers by accident of style
WATCH_AMNESTY_EXEMPT="last_tick hb proto_t progress_seen"
wsrc="$RS/lib/watch.sh"
# The function's own extent, not the file's: read from `watch_wait() {` to the
# next top-level closing brace, so a clock in a helper cannot answer for one here.
wbody=$(awk '/^watch_wait\(\) \{/{f=1} f{print} f && /^\}$/{exit}' "$wsrc")
precond "watch_wait's body was extracted (the sweep has something to read)" \
  test "$(printf '%s\n' "$wbody" | command grep -c .)" -ge 100
amnesty=$(printf '%s\n' "$wbody" | awk '/Clock-jump amnesty/{f=1} f{print} f && /^    last_tick=\$now$/{exit}')
precond "the amnesty block was located inside that body" \
  test "$(printf '%s\n' "$amnesty" | command grep -c .)" -ge 5
clocks=$(printf '%s\n' "$wbody" | command grep -oE 'now - [a-z_]+' | sed 's/^now - //' | sort -u)
precond "the sweep found clocks to check (saw: $(printf '%s' "$clocks" | tr '\n' ' '))" \
  test -n "$clocks"
unshifted=""
for c in $clocks; do
  case " $WATCH_AMNESTY_EXEMPT " in *" $c "*) continue ;; esac
  command grep -qE "\b$c=\\\$\(\($c \+ gap\)\)" <<< "$amnesty" || unshifted="$unshifted $c"
done
[ -z "$unshifted" ] \
  && ok "every non-exempt clock compared against now is shifted by the amnesty ($(printf '%s' "$clocks" | tr '\n' ' ')— exempt: $WATCH_AMNESTY_EXEMPT)" \
  || bad "clocks compared against now but NOT shifted by the clock-jump amnesty:$unshifted — a suspend or NTP step charges the suspended interval to them"
# The exemption list can only SHRINK: a name that is no longer a clock at all
# must leave it, or the list rots behind a comment nobody re-reads.
stale=""
for e in $WATCH_AMNESTY_EXEMPT; do
  command grep -qE "now - $e\b" <<< "$wbody" || stale="$stale $e"
done
[ -z "$stale" ] \
  && ok "and every exemption still names a clock this function actually compares" \
  || bad "stale amnesty exemptions (no longer compared against now):$stale"
# known-bad: a new clock added and not shifted must fire.
kb=$(printf '%s\n' "$wbody" | sed 's/^watch_wait() {/watch_wait() {\n  local ghost_since=0/')
kb_amn="$amnesty"
kb_unshifted=""
for c in $(printf '%s\n[ $((now - ghost_since)) -gt 1 ]\n' "$kb" | command grep -oE 'now - [a-z_]+' | sed 's/^now - //' | sort -u); do
  case " $WATCH_AMNESTY_EXEMPT " in *" $c "*) continue ;; esac
  command grep -qE "\b$c=\\\$\(\($c \+ gap\)\)" <<< "$kb_amn" || kb_unshifted="$kb_unshifted $c"
done
[ "$kb_unshifted" = " ghost_since" ] \
  && ok "known-bad: a newly added clock that the amnesty does not shift is caught by name" \
  || bad "known-bad did not fire as expected (got '$kb_unshifted') — the arm would miss the next omission"

check_done
