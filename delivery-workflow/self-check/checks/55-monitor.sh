#!/usr/bin/env bash
# 55-monitor — what the read-only renderer lets the operator SEE, and the
# panel properties that make it readable (config-and-adapters.md §6).
#
# Content: (a) WHICH CHECKOUT the active slice is bound to — after the two-repo
# split a doc-bound slice's gates SKIP structurally and its commits land in the
# other repo, and no line on the screen said so; (b) ledger records, which were
# raw epochs and kv soup on a screen whose header was already humanized.
# Fault ≠ absent applies to the binding too: an unreadable slices index must
# render FAULT, never the code default (the same read config.sh's binding_kind
# refuses to make silently).
#
# Layout: the panel's shape is a contract, not decoration, and each property
# below has a failure it prevents — escape bytes in `launch.sh status`'s pipe,
# a capture whose bytes depend on the capturing terminal's width, and blanks
# that are invisible on screen but make a byte-diffed frame repaint anyway.
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/fixtures/lib.sh"
. "$RS/lib/state.sh"

base=$(sc_tmpdir)
read -r repo branch < <(mk_repo "$base/code")
read -r drepo dbranch < <(mk_doc_repo "$base/doc")
precond "the doc fixture's branch differs from the code fixture's (else a wrong-branch render is undetectable)" \
  test "$dbranch" != "$branch"

new_ws() { # name -> ws (code+doc pair declared, stage active on slice 01)
  local ws
  ws=$(mk_full_ws "$base" "$1" "$repo" "$branch")
  printf 'doc.repo=%s\ndoc.branch=%s\n' "$drepo" "$dbranch" >> "$ws/project.kv"
  ( state_put "$ws" run ferry "topic=$1" "mode=cold" "t_start=$(date +%s)"
    state_put "$ws" stage ferry "slice=01" "stage=impl" "round=1" "attempt=1" \
      "state=running" "nonce=n55" "spawn_t=$(date +%s)" ) > /dev/null
  printf '%s\n' "$ws"
}
ledger_block() { # rendered-output -> the record rows under the ledger heading
  printf '%s\n' "$1" | awk '/^recent /{on=1;next} /^-----/{on=0} on'
}

echo "-- the active slice's repo binding is on the screen (code) --"
ws=$(new_ws moncode)
assert_rc 0 "monitor --once renders" -- "$RS/monitor.sh" "$ws" --once
assert_out_has "binding   code" "the binding row names the checkout kind"
assert_out_has "$repo @ $branch" "and resolves to the code repo at its branch"

echo "-- a doc-bound slice renders the OTHER checkout, not the code default --"
wsd=$(new_ws mondoc)
( printf 'id=01 status=active risk=low title=one rederive=0 repo=doc\n' \
  | state_set "$wsd" slices ferry ) > /dev/null
assert_rc 0 "monitor --once renders the doc-bound topic" -- "$RS/monitor.sh" "$wsd" --once
assert_out_has "binding   doc" "kind=doc for a slice bound to the doc repo"
assert_out_has "$drepo @ $dbranch" "the DOC repo at the DOC branch (not the project repo)"
command grep -q "$repo @ $branch" <<< "$SC_OUT" \
  && bad "the code checkout still shows on a doc-bound slice (binding not resolved per-slice)" \
  || ok "the code checkout does not appear in the binding row"

echo "-- an unreadable slices index renders FAULT, never the code default --"
wsf=$(new_ws monfault)
corrupt_surface "$wsf" slices
assert_rc 0 "monitor --once still exits 0 over a corrupt slices surface (it reports, it does not fall over)" -- \
  "$RS/monitor.sh" "$wsf" --once
assert_out_has "binding   STORE FAULT" "the binding row says FAULT"
command grep -q "binding   code" <<< "$SC_OUT" \
  && bad "a corrupt index still rendered a binding kind — fault read as absent, the exact read binding_kind refuses" \
  || ok "no kind rendered over the fault"

echo "-- WHO is working, the census, and a command for EVERY live session --"
# The panel named the stage but never the agent; then it named the agent but
# suppressed the held sibling — and the operator inspecting a held author
# while a reviewer runs had to go find the session name by hand. The attach
# block lists every live session (▶ marks the active one, picked by nonce);
# the agent row's census answers "how many" at a glance.
wsa=$(new_ws monagent)
( state_put "$wsa" stage ferry "stage=plan-validate" "backend=claude"
  printf 'role=reviewer name=delivery-monagent-01-precheck pane_pid=0 pane_start=0 server_pid=0 server_start=0 socket=/tmp/s1 nonce=OTHER mode=cold t=1\n%s\n' \
    "role=author name=delivery-monagent-00-plan-validate pane_pid=0 pane_start=0 server_pid=0 server_start=0 socket=/tmp/s2 nonce=n55 mode=cold t=2" \
  | state_set "$wsa" sessions ferry ) > /dev/null
assert_rc 0 "monitor --once renders an active author stage" -- "$RS/monitor.sh" "$wsa" --once
assert_out_has "agent     author" "the role card the stage runs under is named"
assert_out_has "· 1 working · 1 held" "the agent row carries the session census"
assert_out_has "▶ 00-plan-validate" "the ACTIVE session leads the attach block, marked (picked by the stage's nonce, not by role order)"
assert_out_has "tmux -S /tmp/s2 attach -r -t '=delivery-monagent-00-plan-validate'" \
  "with its read-only attach command, exact-match target and all"
assert_out_has "(reviewer·cold)" \
  "the held sibling appears with its role·mode tag (REVERSED: the old panel suppressed it, and the operator had no way to look)"
assert_out_has "tmux -S /tmp/s1 attach -r -t '=delivery-monagent-01-precheck'" \
  "and its own copy-pasteable command"
# The ▶ must track the session the ferry recorded, not a constant: the
# reviewer stages hold their own pane. (impl is the AUTHOR's card — the
# implementer is a subagent dispatched inside that pane, and nothing in the
# store says whether one is running, so the panel does not claim it.)
( state_put "$wsa" stage ferry "stage=precheck" "nonce=OTHER" ) > /dev/null
assert_rc 0 "monitor --once renders a reviewer stage" -- "$RS/monitor.sh" "$wsa" --once
assert_out_has "agent     reviewer" "a reviewer stage names the reviewer, and picks the OTHER session"
assert_out_has "▶ 01-precheck" "the marker follows the nonce to the reviewer's session"

echo "-- a dead held session gets NO command; a starting one says so; the census says dead --"
( : ) & _dpid=$!; wait "$_dpid" 2>/dev/null
( state_put "$wsa" stage ferry "stage=plan-validate" "nonce=n55"
  printf '%s\n%s\n%s\n' \
    "role=author name=delivery-monagent-00-plan-validate pane_pid=0 pane_start=0 server_pid=0 server_start=0 socket=/tmp/s2 nonce=n55 mode=cold t=2" \
    "role=reviewer name=delivery-monagent-01-precheck pane_pid=$_dpid pane_start=0 server_pid=0 server_start=0 socket=/tmp/s1 nonce=OTHER mode=cold t=1" \
    "role=probe name=delivery-monagent-02-spec pane_pid=0 pane_start=0 server_pid=0 server_start=0 socket=pending nonce=PENDH mode=cold t=3" \
  | state_set "$wsa" sessions ferry ) > /dev/null
assert_rc 0 "monitor --once renders live + dead + starting sessions" -- "$RS/monitor.sh" "$wsa" --once
assert_out_has "(reviewer·dead)" "a held row whose recorded pid no longer runs is tagged dead (kill -0 hint; the ferry's pty_alive stays the authority)"
assert_out_has "process gone — torn down" "and gets a statement, not a command"
command grep -q "tmux -S /tmp/s1" <<< "$SC_OUT" \
  && bad "an attach command for a torn-down session — the operator would run it into nothing" \
  || ok "no attach command for the dead session"
assert_out_has "02-spec" "a pre-spawn held row still appears"
assert_out_has "(session still starting)" "as starting, with no command (placeholder socket)"
assert_out_has "· 1 working · 1 held · 1 dead" "the census counts all three states (dead named only when present)"

# The ferry writes the sessions row BEFORE the spawn returns (socket=pending):
# an attach command built from it cannot work, and a command that cannot work
# is worse than none.
( printf 'role=author name=delivery-x-00-plan-validate pane_pid=0 pane_start=0 server_pid=0 server_start=0 socket=pending nonce=PEND mode=cold t=3\n' \
  | state_set "$wsa" sessions ferry
  state_put "$wsa" stage ferry "stage=plan-validate" "nonce=PEND" ) > /dev/null
assert_rc 0 "monitor --once renders a session that has not finished spawning" -- "$RS/monitor.sh" "$wsa" --once
assert_out_has "agent     author" "the role is known as soon as the row exists"
command grep -q 'tmux -S pending' <<< "$SC_OUT" \
  && bad "an attach command built on the placeholder socket — it cannot work, and the operator would run it" \
  || ok "no attach command is offered until the session has a real socket"

echo "-- every '-> N left' names a criterion that actually fires --"
# The stage row measured (now - spawn_t) against liveness.stage_timeout, but
# watch.sh:150 measures CONTINUOUS INACTIVITY: a busy stage never reaches it.
# The panel therefore showed a healthy stage as draining, and an operator read
# it as "this agent will be stopped in 13 minutes" (second anchor, live).
wsc=$(new_ws monclock)
now=$(date +%s)
# live_age and (now - spawn_t) are DELIBERATELY different here: clock-jump
# amnesty shifts spawn_t inside watch.sh's local only, so the surface's
# spawn_t drifts from the age the ceiling is actually measured against. The
# panel must show the loop's own number.
( state_put "$wsc" stage ferry "stage=impl" "spawn_t=$((now - 4830))" \
    "live_class=busy" "live_hb_age=24" "live_idle=24" "live_working=0" "live_age=1200" ) > /dev/null
assert_rc 0 "monitor --once renders a long, healthy stage" -- "$RS/monitor.sh" "$wsc" --once
assert_out_has "idle      24s" "the inactivity clock — the quantity watch.sh actually compares — is on the panel"
assert_out_has "elapsed   20m" "elapsed is the loop's published age, not the surface's spawn_t recomputed (they differ after a clock-jump amnesty)"
command grep -q '1h20m' <<< "$SC_OUT" \
  && bad "the panel recomputed now-spawn_t and ignored the amnesty-corrected age" \
  || ok "the drifted spawn_t did not reach the screen"
assert_out_has "ceiling 3h00m" "the ceiling is named as the cap it is"
command grep -qE 'elapsed .*timeout' <<< "$SC_OUT" \
  && bad "total elapsed is still measured against stage_timeout — the clock that never fires for a busy stage" \
  || ok "elapsed is not compared to the inactivity timeout"
( state_put "$wsc" stage ferry "live_class=working" "live_working=600" ) > /dev/null
assert_rc 0 "monitor --once renders a working-classified stage" -- "$RS/monitor.sh" "$wsc" --once
assert_out_has "working   10m" "the working-overage clock appears only while the class is working"

echo "-- a park record's detail cannot blow the frame apart --"
wst=$(new_ws monwide)
( state_append "$wst" ledger ferry \
    "v=1 t=$(date +%s) event=park slice=01 stage=impl reason=class_u detail=$(printf 'x%.0s' $(seq 1 900))" ) > /dev/null
assert_rc 0 "monitor --once renders a ledger carrying a 900-char detail" -- "$RS/monitor.sh" "$wst" --once
blk=$(ledger_block "$SC_OUT")
# width is COUNTED IN CELLS (a UTF-8 continuation byte is not a column)
cellwidth() { LC_ALL=C awk '{ n = gsub(/[\200-\277]/, "", $0); w = length($0) - n; if (w > m) m = w } END { print m+0 }'; }
[ "$(printf '%s\n' "$blk" | cellwidth)" -le 74 ] \
  && ok "every ledger row fits the frame (the full record is one state_get away; the live park's detail summarizes in the headline block with a pointer)" \
  || bad "a ledger row ran to $(printf '%s\n' "$blk" | cellwidth) columns — the panel is unreadable exactly when something went wrong"
printf '%s\n' "$blk" | command grep -q 'park' \
  && ok "the truncated row still names its event" || bad "truncation ate the event name"

echo "-- a corrupt HALT surface is loud: a park hidden there is the worst silent state --"
wsh=$(new_ws monhaltfault)
( state_put "$wsh" halt ferry "reason=class_u" "slice=01" "stage=impl" "resolved=0" \
    "t=$(date +%s)" "detail=fixture" ) > /dev/null
corrupt_surface "$wsh" halt
assert_rc 0 "monitor --once renders over a corrupt halt surface" -- "$RS/monitor.sh" "$wsh" --once
assert_out_has "STORE FAULT in the halt surface" "the headline says the park surface is unreadable"
command grep -q '▶ RUNNING' <<< "$SC_OUT" \
  && bad "a RUNNING headline over an unreadable halt surface — the panel reports 'all fine' while a park may be sitting in the fault" \
  || ok "no running-and-fine headline is claimed over the fault"

echo "-- a corrupt RUN surface names itself, not the halt surface --"
# The token refactor collapsed two pre-refactor paint branches into one token
# and, with them, their texts — a corrupt RUN surface came to paint the
# HALT-surface sentence, naming the wrong surface. Found by an independent
# audit of the landing commit; this arm is what keeps it from coming back. The
# poll token is one state (STORE_FAULT) either way; the panel names the surface
# that faulted.
wsr=$(new_ws monrunfault)
corrupt_surface "$wsr" run
assert_rc 0 "monitor --once renders over a corrupt run surface" -- "$RS/monitor.sh" "$wsr" --once
assert_out_has "the run surface is corrupt; do not treat as absent" "the headline names the RUN surface (the pre-refactor text, restored)"
assert_out_lacks "in the halt surface" "and does not name the halt surface it did not read a fault from"
printf '%s\n' "$SC_OUT" | command grep -q '^state=STORE_FAULT ' \
  && ok "the machine line still reads the one token — a poll sees the store is corrupt, the panel says which surface" \
  || bad "machine line over a corrupt run surface: $(printf '%s\n' "$SC_OUT" | command grep '^state=' || echo ABSENT)"

echo "-- ledger records: human time, columns, no raw epoch, nothing dropped --"
wsl=$(new_ws monledger)
t1=$(( $(date +%s) - 3600 ))
( state_append "$wsl" ledger ferry "v=1 t=$t1 event=stage.done slice=01 stage=spec round=1" ) > /dev/null
assert_rc 0 "monitor --once renders the ledger" -- "$RS/monitor.sh" "$wsl" --once
assert_out_has "$(date -d "@$t1" '+%m-%d %H:%M:%S')" "the record carries its local clock time"
blk=$(ledger_block "$SC_OUT")
command grep -qE '(^| )t=[0-9]{9,}( |$)' <<< "$blk" \
  && bad "a raw epoch t= is still in the ledger block: $(printf '%s\n' "$blk" | command grep -E '(^| )t=[0-9]{9,}( |$)' | head -1)" \
  || ok "no bare epoch left in the rendered ledger"
printf '%s\n' "$blk" | command grep -qE 'stage\.done +01 spec +round=1' \
  && ok "the record is columnised (time · event · slice stage) with its remaining fields verbatim" \
  || bad "the record did not columnise: $(printf '%s\n' "$blk" | tail -2 | tr '\n' ' ')"

echo "-- a record whose t= is unusable is rendered verbatim (fail-safe: never drop a line) --"
wsb=$(new_ws monbadt)
( state_append "$wsb" ledger ferry "v=1 t=notanepoch event=hand.edited slice=01" ) > /dev/null
assert_rc 0 "monitor --once renders a record with an unusable timestamp" -- "$RS/monitor.sh" "$wsb" --once
assert_out_has "t=notanepoch event=hand.edited" "the unparseable record is shown as-is rather than dropped or mangled"

echo "-- the park owns the headline, and carries the command that answers it --"
wsp=$(new_ws monpark)
scr="$wsp/.runtime/logs/screen-fixture.txt"
printf 'pane line one\npane line two\n' > "$scr"
( state_put "$wsp" halt ferry "reason=class_u" "slice=01" "stage=impl" "resolved=0" \
    "t=$(date +%s)" "detail=implementer raised a scope question the plan does not answer" \
    "screen_file=$scr" ) > /dev/null
assert_rc 0 "monitor --once renders a parked topic" -- "$RS/monitor.sh" "$wsp" --once
assert_out_has "PARKED — needs you" "the park is the headline, not a line buried below the timeline"
assert_out_has "reason    class_u · slice 01 · impl" "the reason row names the halt's own slice and stage"
assert_out_has "launch.sh rule <workspace> --slice 01 --text" "the next row is the command that answers THIS park"
assert_out_has "| pane line two" "the saved screen's tail rides along (the ferry captured it; the monitor never captures)"

# A hand-edited timestamp must not become a nonsense age: unguarded, bash reads
# the non-numeric token as 0 in the arithmetic and the park renders as ~20000d
# old — a confident wrong number, which is worse than no number.
( state_put "$wsp" halt ferry "t=notanepoch" ) > /dev/null
assert_rc 0 "monitor --once renders a halt whose t= is unusable" -- "$RS/monitor.sh" "$wsp" --once
command grep -q 'PARKED.*ago' <<< "$SC_OUT" \
  && bad "an age was computed from an unusable timestamp: $(printf '%s\n' "$SC_OUT" | command grep -m1 PARKED)" \
  || ok "no age shown rather than an age invented from a non-numeric timestamp"


echo "-- the machine line: a poll's first line, and the FAIL count no live surface carried --"
# Measured: 26 quality-gate refusals over
# twelve hours while every operator-facing surface read flawless — refusals are
# absorbed in-session by design (operations §3), so parks, pages and the panel
# never see them, and the number that best describes how hard a topic was was
# the one number no live surface carried. The cheaper variant the entry names:
# a line on launch.sh status (== monitor --once), NOT the panel — the machine
# line is ONCE-gated inside render, and the loop form never prints it (asserted
# structurally here; driving the 2s loop in a fixture would time-travel).
( state_put "$wsp" halt ferry "reason=class_u" "slice=01" "stage=impl" "resolved=0" \
    "t=$(date +%s)" "detail=d" ) > /dev/null
assert_rc 0 "monitor --once renders the parked topic again" -- "$RS/monitor.sh" "$wsp" --once
printf '%s\n' "$SC_OUT" | command grep -q '^state=PARKED reason=class_u ' \
  && ok "the first machine line reads state=PARKED with the park's reason (a poll keys on the token, not the paint)" \
  || bad "parked machine line wrong: $(printf '%s\n' "$SC_OUT" | command grep '^state=' || echo ABSENT)"
[ "$(printf '%s\n' "$SC_OUT" | command grep -c '^state=')" -eq 1 ] \
  && ok "exactly one machine line per once-render (the loop form is ONCE-gated and never prints it)" \
  || bad "machine line count: $(printf '%s\n' "$SC_OUT" | command grep -c '^state=')"
( state_append "$wsp" gates gate "v=1 t=1 gate=claims result=FAIL sha=a detail=x" \
    && state_append "$wsp" gates gate "v=1 t=2 gate=env_sweep result=FAIL sha=a detail=x" \
    && state_append "$wsp" gates gate "v=1 t=3 gate=caps result=PASS sha=a detail=x" \
    && state_append "$wsp" gates gate "v=1 t=4 gate=claims result=PASS sha=a detail=x" \
    && state_append "$wsp" gates gate "v=1 t=5 gate=structure result=PASS sha=a detail=x" ) > /dev/null
assert_rc 0 "monitor --once renders with a gates surface holding 2 FAIL of 5" -- "$RS/monitor.sh" "$wsp" --once
printf '%s\n' "$SC_OUT" | command grep -q '^state=PARKED reason=class_u gate_fails=2 attestations=5$' \
  && ok "the running FAIL count rides the machine line: gate_fails=2 attestations=5 — the quality number, live" \
  || bad "fails line wrong: $(printf '%s\n' "$SC_OUT" | command grep '^state=')"
wsfresh=$(new_ws monfresh)
assert_rc 0 "monitor --once renders a workspace with no gates surface yet" -- "$RS/monitor.sh" "$wsfresh" --once
printf '%s\n' "$SC_OUT" | command grep -q '^state=RUNNING gate_fails=absent attestations=0$' \
  && ok "an absent gates surface reads gate_fails=absent (absent is named, never zero)" \
  || bad "absent direction wrong: $(printf '%s\n' "$SC_OUT" | command grep '^state=')"
echo "-- panel properties: a captured frame is plain, fixed-width and blank-free --"
# A notify body is the row whose value is BUILT by joining lines, so it is where
# a trailing blank appears first; the default-preset frames above would never
# show one. Written by the operator class — the store refuses any other writer.
( state_put "$wsp" notify operator "preset=key-points" "event.park=on" "event.commit.done=off" ) > /dev/null
( state_put "$wsp" halt ferry "reason=class_u" "slice=01" "stage=impl" "resolved=0" \
    "t=$(date +%s)" "detail=implementer raised a scope question the plan does not answer" \
    "screen_file=$scr" ) > /dev/null
assert_rc 0 "monitor --once renders a topic with an explicit notify policy" -- "$RS/monitor.sh" "$wsp" --once
assert_out_has "event.park=on" "the policy in effect is on the panel"
command grep -q "$(printf '\033')" <<< "$SC_OUT" \
  && bad "ANSI escapes in a NON-TTY capture — launch.sh status pipes this; escape bytes are noise there" \
  || ok "no escape bytes when stdout is not a terminal (color is a TTY affordance)"
wide=$(COLUMNS=200 "$RS/monitor.sh" "$wsp" --once 2>&1)
[ "$(printf '%s\n' "$wide" | command grep -c '^-\{74\}$')" -ge 2 ] \
  && ok "the frame is 74 wide whatever COLUMNS says (a capture's bytes must not depend on who captured it)" \
  || bad "rule width followed the environment: $(printf '%s\n' "$wide" | command grep -m1 '^-\+$' | wc -c) chars"
command grep -qE '[[:space:]]+$' <<< "$SC_OUT" \
  && bad "trailing blanks in the frame: invisible on screen, but the follow-mode repaint diffs the frame BYTEWISE and would repaint on them" \
  || ok "no trailing blanks on any line"
# The right-hand half of a header line is OPTIONAL (a halt written without t=
# has no age to show), and that is the case where a padded empty half leaves a
# line of blanks. Rendered from a fixture that omits t= so the guard is live.
( state_put "$wsp" halt ferry "reason=class_u" "slice=01" "stage=impl" "resolved=0" \
    "t=" "detail=fixture" ) > /dev/null
assert_rc 0 "monitor --once renders a halt carrying no timestamp" -- "$RS/monitor.sh" "$wsp" --once
command grep -qE '[[:space:]]+$' <<< "$SC_OUT" \
  && bad "an absent right-hand half still padded: $(printf '%s\n' "$SC_OUT" | command grep -nE '[[:space:]]+$' | head -1)" \
  || ok "an absent right-hand half prints no padding either"

echo "-- durations are minute-coarse; liveness shows only once the ferry has classified --"
wsq=$(new_ws moncoarse)
( state_put "$wsq" stage ferry "spawn_t=$(( $(date +%s) - 1230 ))" ) > /dev/null   # no live_age yet: the pre-first-tick fallback
assert_rc 0 "monitor --once renders an elapsed stage" -- "$RS/monitor.sh" "$wsq" --once
# 1230s = 20.5m — mid-bucket, so the assertion cannot straddle a rollover.
assert_out_has "elapsed   20m" "elapsed renders in whole minutes, never seconds (a per-second field would repaint every poll)"
command grep -q 'liveness' <<< "$SC_OUT" \
  && bad "a liveness row before the wait loop's first tick — a row of '?' reads as a broken panel, not as 'not yet observed'" \
  || ok "no liveness row until there is a classification to show"
( state_put "$wsq" stage ferry "live_class=busy_cpu" "live_hb_age=41" "live_age=1230" ) > /dev/null
assert_rc 0 "monitor --once renders a classified stage" -- "$RS/monitor.sh" "$wsq" --once
assert_out_has "liveness  busy_cpu · heartbeat 41s ago" "the class the wait loop published is what the panel shows (the monitor never judges liveness itself)"
command grep -q '^  attempts' <<< "$SC_OUT" \
  && bad "an attempts row without an attempts surface — a runway invented from nothing" \
  || ok "no attempts/slice runway rows before the first count lands (absent ≠ zero)"

echo "-- slice + stage bars: done comes from the ledger's advance, never the attempts surface --"
# do_advance writes `advance` only after every park path has exited, so an
# advance strictly means "stage passed"; the attempts surface's round key
# means ENTERED — a parked stage would misrender as done under it.
wsbar=$(new_ws monbars)
( printf 'id=01 status=done risk=low title=a rederive=0\nid=02 status=active risk=low title=b rederive=0\nid=03 status=pending risk=low title=c rederive=0\nid=04 status=cancelled risk=low title=d rederive=0\n' \
    | state_set "$wsbar" slices ferry
  state_put "$wsbar" stage ferry "slice=02" "stage=impl" "round=1" "attempt=1" \
    "state=running" "nonce=nB1" "spawn_t=$(date +%s)"
  state_append "$wsbar" ledger ferry "v=1 t=10 event=advance slice=02 stage=spec verdict=drafted target=precheck"
  state_append "$wsbar" ledger ferry "v=1 t=11 event=advance slice=02 stage=precheck verdict=ready target=impl"
  # 1410s = 23.5m: MID-BUCKET on both sides (elapsed 23m spans 1380-1439;
  # left 7h36m spans 27360-27419, and 28800-1410=27390 sits mid) so seconds of
  # fixture-to-render skew cannot straddle a minute rollover (monclock's rule)
  state_put "$wsbar" attempts ferry "round.02.impl=1" "count.02.impl.1=1" \
    "slice.02.started=$(( $(date +%s) - 1410 ))" ) > /dev/null
assert_rc 0 "monitor --once renders the bars" -- "$RS/monitor.sh" "$wsbar" --once
assert_out_has "slices    01✓ 02▶ 03○ 04✗  (1 done · 1 active · 1 pending · 1 cancelled)" \
  "the slice bar renders every status with its glyph and the census, in id order"
assert_out_has "spec✓ precheck✓" "advanced stages are done"
assert_out_has "impl▶" "the current stage carries the marker"
assert_out_has "postcheck○" "a not-yet-entered stage is pending"
command grep -q 'impl✓' <<< "$SC_OUT" \
  && bad "an ENTERED stage rendered done — the attempts-surface trap (round.02.impl exists, no advance)" \
  || ok "entered-but-not-advanced is NOT done (a parked stage cannot misrender as passed)"

echo "-- runway rows name the criteria that fire: attempt budget + slice wallclock --"
assert_out_has "attempts  1/3 → 2 left" "the attempt count runs against the budget check_budgets parks on"
assert_out_has "slice     23m / wallclock 8h00m → 7h36m left" "the slice clock runs against budget.slice_wallclock"
( state_put "$wsbar" attempts ferry "count.02.impl.1=3" ) > /dev/null
assert_rc 0 "monitor --once renders an exhausted budget" -- "$RS/monitor.sh" "$wsbar" --once
assert_out_has "attempts  3/3 → 0 left" "an exhausted budget reads 0 left (the next attempt parks budget_attempts)"

echo "-- the runway clocks meter WORKING time: credited park intervals subtract --"
# check_budgets subtracts parked.<slice>/parked_total; a panel that keeps
# billing calendar time shows a budget the real check never spends — the same
# misread class as elapsed-vs-timeout, one row lower. 420s parked on a 1410s
# elapsed slice -> 990s working = 16m (mid-bucket both sides, monclock's rule);
# t_start 1830s back with 600s parked -> 20m working against the 3d0h budget.
( state_put "$wsbar" attempts ferry "parked.02=420"
  state_put "$wsbar" run ferry "t_start=$(( $(date +%s) - 1830 ))" "parked_total=600" ) > /dev/null
assert_rc 0 "monitor --once renders the park-credited clocks" -- "$RS/monitor.sh" "$wsbar" --once
assert_out_has "slice     16m / wallclock 8h00m → 7h43m left" \
  "the slice row shows working time (23m calendar - 7m parked), the number check_budgets compares"
assert_out_has "20m / budget 3d0h → 2d23h left" \
  "the topic row subtracts parked_total the same way"

echo "-- and only where the criterion CAN fire: no slice runway for the topic scope --"
# 00 is exempt from the slice budget (its `started` is the topic's own), so a
# slice row there would render a cap the check never spends — the misread class
# this panel was already fixed for once. The topic row must still be there: the
# span is priced, just by the clock that owns it.
( state_put "$wsbar" stage ferry "slice=00" "stage=close-out" "state=running"
  state_put "$wsbar" attempts ferry "slice.00.started=$(( $(date +%s) - 400000 ))" ) > /dev/null
assert_rc 0 "monitor --once renders the topic scope" -- "$RS/monitor.sh" "$wsbar" --once
command grep -qE '^slice +[0-9]' <<< "$SC_OUT" \
  && bad "a slice runway row was drawn for the topic scope — it shows a budget check_budgets no longer spends" \
  || ok "no slice runway row for slice 00 (the exempt budget is not rendered as if it fired)"
assert_out_has "budget 3d0h" "the topic row still runs — the span is priced by the clock that owns it"

echo "-- a TOPIC-scope stage renders the topic stage set, keyed on slice 00 --"
( state_put "$wsbar" stage ferry "slice=00" "stage=split-check" "round=1" "nonce=nB2"
  state_append "$wsbar" ledger ferry "v=1 t=12 event=advance slice=00 stage=plan-validate verdict=ready target=split"
  state_append "$wsbar" ledger ferry "v=1 t=13 event=advance slice=00 stage=split verdict=done target=split-check" ) > /dev/null
assert_rc 0 "monitor --once renders a topic-scope position" -- "$RS/monitor.sh" "$wsbar" --once
assert_out_has "plan-validate✓ split✓ split-check▶ close-out○" \
  "the bar follows the current stage's scope (topic stages for a slice-00 stage)"

echo "-- a long park detail renders 2 summary lines + a pointer; a short one stays whole --"
wsdd=$(new_ws mondetail)
longd=$(printf 'y%.0s' $(seq 1 500))
( state_put "$wsdd" halt ferry "reason=class_u" "slice=01" "stage=impl" "resolved=0" \
    "t=$(date +%s)" "detail=$longd" ) > /dev/null
assert_rc 0 "monitor --once renders a 500-char park detail" -- "$RS/monitor.sh" "$wsdd" --once
assert_out_has "▸ full text 500 chars: launch.sh status <workspace> --halt" \
  "the pointer names the length and where the full text lives (halt surface)"
# …and the flag it names is one launch.sh actually accepts. The pointer read
# `--once` for five slices and two park classes; status has no such argument
# and monitor.sh --once renders this very frame, so the hint sent an operator
# in a circle at the moment the full text was the thing they needed. 35-verbs
# holds the other end (the flag taken from THIS string must run); this end
# keeps the string itself from drifting back.
sed -n '/^verb_status/,/^}/p' "$RS/launch.sh" | command grep -q -- '--halt)' \
  && ok "launch.sh's status verb has an arm for the flag this panel points at" \
  || bad "the panel points at a status flag launch.sh does not parse: $(sed -n '/^verb_status/,/^}/p' "$RS/launch.sh" | command grep -o '\-\-[a-z]*' | tr '\n' ' ')"
command grep -qE 'y{200}' <<< "$SC_OUT" \
  && bad "the full dump still reaches the panel — the ledger is buried exactly when something went wrong" \
  || ok "the dump stays in the halt surface; the panel keeps its shape"
( state_put "$wsdd" halt ferry "detail=one short question" ) > /dev/null
assert_rc 0 "monitor --once renders a short park detail" -- "$RS/monitor.sh" "$wsdd" --once
assert_out_has "detail    one short question" "a short detail still renders in full"
command grep -q '▸ full text' <<< "$SC_OUT" \
  && bad "a pointer under a detail that already fits is noise" \
  || ok "no pointer when the detail fits the panel"

echo "-- the CLI stays narrow: --once/--no-color only, anything else refuses --"
assert_rc 0 "--no-color is accepted" -- "$RS/monitor.sh" "$wsq" --once --no-color
assert_rc 2 "an unknown flag refuses with usage (rc 2), never renders something the caller did not ask for" -- \
  "$RS/monitor.sh" "$wsq" --once --follow-forever

echo "-- the spawn write clears liveness: a new attempt never wears the dead one's numbers --"
# The six `live_*` keys have ONE writer (`_watch_stage_note`) and, until
# 2026-09-08, no clear site anywhere in the tree — so across a stage or attempt
# boundary the stage record held a NEW identity beside the PREVIOUS attempt's
# liveness until the next wait-loop tick. Measured 22s after a resume spawn: a
# zero-second-old stage rendered `busy · heartbeat 15s ago`, `idle 0s`,
# `elapsed 24m` — all the dead session's numbers. The contract the panel wants
# was already asserted above (no `live_age` => no liveness row, `elapsed` off
# `spawn_t`); production simply could not reach it after the first stage.
#
# THE KEY SET IS DERIVED FROM THE PUBLISHER AND THE CLEAR SITES ARE DERIVED
# FROM THE WRITE ITSELF. Neither is a named list, and the second half of that
# is a correction rather than a preference. This arm used to compare
# `watch.sh`'s key set against `attempt.sh`'s — two hand-picked filenames — and
# it passed while `ferry.sh`'s `enter_stage` wrote a NEW stage identity beside
# the PREVIOUS stage's liveness, because `ferry.sh` was in no one's corpus. The
# check's own comment argued for derivation over a hand-copied list and then
# hand-picked the files to derive from; an independent reader found the gap.
#
# The discriminator is a property of the write: A STAGE WRITE THAT NAMES
# `nonce=` IS AN IDENTITY WRITE, and an identity write must clear every key the
# publisher publishes. Verified against all nine stage-surface writes under
# runtime-scripts/ — `ferry.sh`'s enter_stage and `attempt.sh`'s spawn name
# `nonce=` and must clear; the six `state=` transitions (`resume.sh`'s among
# them) do not and must not; `watch.sh` is the publisher. A third identity
# site is found by the sweep, not by editing this check.
live_keys_of() { # file -> the live_* keys assigned on its state-writing lines, one per line
  command grep -ohE '"live_[a-z_]+=' "$1" | tr -d '"=' | sort -u
}
stage_writes() { # root -> "file:line<TAB>logical line" per write to the stage surface
  find "$1" -name '*.sh' -type f | sort | while read -r f; do
    awk -v F="$f" '
      {
        line = $0; n = FNR
        while (line ~ /\\$/ && (getline nxt) > 0) { sub(/\\$/, "", line); line = line nxt }
        if (line !~ /^[[:space:]]*#/ && line ~ /(sput stage |state_put [^ ]+ stage )/)
          printf "%s:%d\t%s\n", F, n, line
      }' "$f"
  done
}
identity_gaps() { # root keys -> "site: missing keys" per identity write that fails to clear
  local root=$1 keys=$2 row site body k missing
  stage_writes "$root" | command grep -F 'nonce=' | while IFS= read -r row; do
    site=${row%%$'\t'*}; body=${row#*$'\t'}; missing=""
    for k in $keys; do
      case "$body" in *"\"$k=\""*) : ;; *) missing="$missing $k" ;; esac
    done
    [ -n "$missing" ] && printf '%s ->%s\n' "${site#"$root/"}" "$missing"
  done
}
W_KEYS=$(live_keys_of "$RS/lib/watch.sh")
n_w=$(printf '%s\n' "$W_KEYS" | command grep -c . || true)
precond "the publisher's liveness key set was extracted from watch.sh (saw ${n_w:-0}, expect 6)" \
  test "${n_w:-0}" -eq 6
SW=$(stage_writes "$RS")
n_sw=$(printf '%s\n' "$SW" | command grep -c . || true)
precond "the stage-write sweep sees N>=6 writes under runtime-scripts/ (a zero here would be a floor, not a verdict)" \
  test "${n_sw:-0}" -ge 6
n_id=$(printf '%s\n' "$SW" | command grep -cF 'nonce=' || true)
precond "the sweep classified N>=2 of them as IDENTITY writes (they name nonce=)" \
  test "${n_id:-0}" -ge 2
gaps=$(identity_gaps "$RS" "$W_KEYS")
if [ -z "$gaps" ]; then
  ok "all $n_id identity writes to the stage surface clear all $n_w liveness keys (sites DERIVED from $n_sw stage writes under runtime-scripts/, not named here)"
else
  bad "an identity write leaves the previous stage's liveness on the surface — the panel draws it under the NEW identity unless parked:"$'\n'"    $(printf '%s' "$gaps" | tr '\n' '|')"
fi
# Non-vacuity for the sweep: strip the clear from ferry.sh's enter_stage in a
# COPY and confirm the discriminator names that site. Without this the arm's
# green is a claim about a predicate nobody has seen fire.
kbr=$(sc_tmpdir)
cp -a "$RS" "$kbr/runtime-scripts"
sed -i 's/ "live_class=" "live_hb_age=" "live_age=" "live_idle=" "live_working=" "live_t="//' "$kbr/runtime-scripts/ferry.sh"
kb_gaps=$(identity_gaps "$kbr/runtime-scripts" "$W_KEYS")
case "$kb_gaps" in
  *ferry.sh*) ok "known-bad: with the clear removed from ferry.sh's enter_stage the sweep NAMES it ($(printf '%s' "$kb_gaps" | head -1))" ;;
  *)          bad "known-bad DID NOT FIRE: the identity-write sweep cannot see a stage-enter write that keeps the previous liveness (got: ${kb_gaps:-<nothing>})" ;;
esac

# behavioural half: dirty the liveness block, then apply the spawn write's own
# cleared pairs (built from the key set just derived) and re-render.
wsl=$(new_ws monlive)
( state_put "$wsl" stage ferry "spawn_t=$(( $(date +%s) - 1440 ))" \
    "live_class=busy" "live_hb_age=15" "live_age=1440" "live_idle=0" "live_working=0" "live_t=$(date +%s)" ) > /dev/null
assert_rc 0 "monitor --once renders the stale-liveness stage" -- "$RS/monitor.sh" "$wsl" --once
assert_out_has "liveness  busy · heartbeat 15s ago" "precondition: the stale block IS what the panel would show"
# the clear, exactly as attempt.sh writes it
cleared=""
for k in $W_KEYS; do cleared="$cleared $k="; done
# shellcheck disable=SC2086
# 300s = 5m, mid-bucket like the coarse-duration fixture above, so the
# assertion cannot straddle a minute rollover; the stale live_age was 1440 (24m).
( state_put "$wsl" stage ferry "spawn_t=$(( $(date +%s) - 300 ))" $cleared ) > /dev/null
# COUNTED, not just un-failed. In the red state this loop's key set is empty,
# the body never runs, and a bare `ok` after it printed a GREEN sentence while
# checking nothing — an assertion that can pass while blind is a false floor,
# which is the same discipline the precond above exists for. The verdict now
# requires all six keys to have been READ and found empty.
n_a=$(printf '%s\n' "$W_KEYS" | command grep -c . || true)
precond "the key set applied by this fixture came from the publisher (saw ${n_a:-0}, expect 6)" \
  test "${n_a:-0}" -eq 6
n_empty=0
for k in $W_KEYS; do
  v=$(state_field "$wsl" stage "$k" 2>/dev/null)
  if [ -z "$v" ]; then n_empty=$((n_empty + 1))
  else bad "after the spawn write, $k still reads '$v' — an empty value did not store as empty"; fi
done
[ "${n_empty:-0}" -eq 6 ] \
  && ok "all 6 liveness keys were READ back and are empty after the spawn write" \
  || bad "only ${n_empty:-0} of 6 liveness keys were verified empty — a verdict over an empty key set is not a floor"
assert_rc 0 "monitor --once renders the freshly spawned stage" -- "$RS/monitor.sh" "$wsl" --once
command grep -q 'liveness' <<< "$SC_OUT" \
  && bad "the new attempt still wears a liveness row — the dead session's numbers survived the spawn" \
  || ok "no liveness row after a spawn until the new loop's first tick (the measured defect, red before the clear)"
assert_out_has "elapsed   5m" "elapsed falls back to the NEW spawn_t (5m), not the dead attempt's live_age"
command grep -q '24m' <<< "$SC_OUT" \
  && bad "the dead attempt's 24m survived the spawn write somewhere on the panel" \
  || ok "the dead attempt's 24m appears nowhere on the panel"

# STAGE BOUNDARY — the window the previous round recorded as a "scope edge" and
# left open. `enter_stage` writes a NEW identity (`state=entered`, `attempt=0`,
# `spawn_t=0`, `nonce=-`) one ferry turn BEFORE the spawn write. That reasoning
# only considered a PARK raised in the window, where the panel suppresses the
# whole liveness block — but the ordinary transition is not parked, so the block
# drew the previous stage's numbers under the new stage's header. Measured
# before the fix: header `postcheck▶` with `busy · heartbeat 15s ago`, idle
# `0s`, elapsed `24m` — byte-identical to the running stage it replaced.
# The cleared pairs come from `ferry.sh`'s OWN write, so removing the clear
# there reds this behavioural arm as well as the derived sweep above.
F_KEYS=$(live_keys_of "$RS/ferry.sh")
n_f=$(printf '%s\n' "$F_KEYS" | command grep -c . || true)
precond "enter_stage's cleared key set was extracted from ferry.sh (saw ${n_f:-0}, expect 6)" \
  test "${n_f:-0}" -eq 6
wse=$(new_ws monenter)
( state_put "$wse" stage ferry "slice=01" "stage=impl" "round=2" "attempt=1" "state=running" \
    "nonce=nOLD" "spawn_t=$(( $(date +%s) - 1440 ))" \
    "live_class=busy" "live_hb_age=15" "live_age=1440" "live_idle=0" "live_working=0" \
    "live_t=$(date +%s)" ) > /dev/null
assert_rc 0 "monitor --once renders the RUNNING stage before the boundary" -- "$RS/monitor.sh" "$wse" --once
assert_out_has "liveness  busy · heartbeat 15s ago" "precondition: the stale block IS what would cross the stage boundary"
fcleared=""
for k in $F_KEYS; do fcleared="$fcleared $k="; done
# shellcheck disable=SC2086
( state_put "$wse" stage ferry "slice=01" "stage=postcheck" "round=1" "attempt=0" \
    "state=entered" "nonce=-" "spawn_t=0" $fcleared ) > /dev/null
assert_rc 0 "monitor --once renders the freshly ENTERED stage" -- "$RS/monitor.sh" "$wse" --once
assert_out_has "postcheck▶" "positive pin: the panel still draws the NEW stage (this arm is not green over an empty render)"
command grep -q 'liveness' <<< "$SC_OUT" \
  && bad "the entered stage still wears a liveness row — the previous stage's session survived enter_stage" \
  || ok "no liveness row after enter_stage and before the new loop's first tick"
command grep -q '24m' <<< "$SC_OUT" \
  && bad "the previous stage's 24m survived the stage-enter write somewhere on the panel" \
  || ok "the previous stage's 24m appears nowhere on the panel after enter_stage"

check_done
