#!/usr/bin/env bash
# 35-verbs — the operator surface is exactly what the docs say it is: every
# verb the formal docs name must exist in launch.sh's dispatch (a pilot card
# row that refuses at the shell is a broken action list); documented verb
# invocations carry their <workspace> argument; the session/operator write
# paths (observe / decision / learn) actually write their surfaces.
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/fixtures/lib.sh"
. "$RS/lib/state.sh"
LAUNCH="$RS/launch.sh"
RECORD="$RS/session/record.sh"

base=$(sc_tmpdir)
read -r repo branch < <(mk_repo "$base/repo")
ws=$(mk_ws "$base" verbstopic "$repo" "$branch")

echo "-- doc <-> dispatch closure --"
doc_verbs() {
  { command grep -hoE 'launch\.sh [a-z][a-z-]*' \
      "$WF_ROOT/README.md" "$WF_ROOT/runtime-docs/cards/pilot.md" \
      "$WF_ROOT/runtime-docs/operations.md" 2>/dev/null | awk '{print $2}'
    awk '/^## 2\./{on=1;next} /^## /{on=0} on && /^\| `/' \
      "$WF_ROOT/runtime-docs/operations.md" | sed 's/^| `\([a-z-]*\).*/\1/'
  } | sort -u | command grep -E '^[a-z]' || true
}
dispatch_verbs() {
  sed -n '/^case "\${1:-}" in/,/^esac$/p' "$LAUNCH" \
    | command grep -oE '^  [a-z][a-z-]*\)' | tr -d ' )'
}
dv=$(doc_verbs); di=$(dispatch_verbs)
precond "docs name N>=6 verbs (saw: $(printf '%s' "$dv" | tr '\n' ' '))" \
  test "$(printf '%s\n' "$dv" | command grep -c .)" -ge 6
missing=""
for v in $dv; do
  command grep -qxF "$v" <<< "$di" || missing="$missing $v"
done
[ -z "$missing" ] \
  && ok "every documented verb exists in launch.sh's dispatch" \
  || bad "documented verbs with no dispatch arm:$missing"
command grep -qxF "no-such-verb" <<< "$di" \
  && bad "dispatch extractor vacuous (matched a fabricated verb)" \
  || ok "dispatch extractor rejects a fabricated verb (known-bad fires)"

echo "-- design authority names every dispatch verb (architecture §9) --"
s9=$(sed -n '/^## 9\./,/^## 10/p' "$WF_ROOT/design/architecture.md")
precond "architecture §9 extracted (N>0 lines)" \
  test "$(printf '%s\n' "$s9" | command grep -c .)" -ge 5
missing9=""
for v in $di; do
  command grep -q "\`$v" <<< "$s9" || missing9="$missing9 $v"
done
[ -z "$missing9" ] \
  && ok "every launch.sh dispatch verb appears in architecture §9 ('the single entry' enumeration is complete)" \
  || bad "dispatch verbs absent from architecture §9:$missing9 — the authority's operator surface is incomplete"

echo "-- documented invocations carry their <workspace> argument --"
# An INVOCATION shows arguments (--flag or <id>); a bare verb name in prose is
# fine. Flag argument-bearing forms that skip straight past <workspace>.
# Floored on the loose family first: the bad-shape extractor alone would read
# as clean the day the docs' prose drifts off the `launch.sh <verb>` shape
# entirely — nothing would match, nothing would flag.
n_inv=$(command grep -hoE 'launch\.sh (rule|stop|slice|status|notify|observe|ack|peek) ' \
  "$WF_ROOT/README.md" "$WF_ROOT/runtime-docs/cards/pilot.md" \
  "$WF_ROOT/runtime-docs/operations.md" 2>/dev/null | command grep -c . || true)
precond "the invocation sweep sees N>=6 verb invocations in the docs (saw $n_inv)" \
  test "$n_inv" -ge 6
nows=$(command grep -hE 'launch\.sh (rule|stop|slice|status|notify|observe|ack|peek) (--|<id|[0-9])' \
  "$WF_ROOT/README.md" "$WF_ROOT/runtime-docs/cards/pilot.md" \
  "$WF_ROOT/runtime-docs/operations.md" 2>/dev/null || true)
[ -z "$nows" ] \
  && ok "no documented invocation puts arguments before <workspace>" \
  || bad "workspace-less invocations documented (agents copy these verbatim): $(printf '%s' "$nows" | head -3 | tr '\n' ' ')"

echo "-- observe: the operator write path for the observations surface --"
assert_rc 0 "launch.sh observe appends a workflow-defect observation" -- \
  "$LAUNCH" observe "$ws" --text "fixture: the monitor misrendered X"
( . "$RS/lib/state.sh"; state_get "$ws" observations | command grep -q "misrendered" ) \
  && ok "observation landed in the observations surface" \
  || bad "observations surface empty after observe"
assert_rc 2 "observe without --text refuses" -- "$LAUNCH" observe "$ws"
# --file (parity with rule): observations usefully carry code — and a live
# entry lost a backticked word to --text shell quoting while append reported
# success. The file path carries the bytes un-mangled.
obsf="$base/obs-with-code.txt"
printf 'regex fragment `continue` and $(subst) survive intact via --file\n' > "$obsf"
assert_rc 0 "observe --file appends the file's text (code fragments un-mangled)" -- \
  "$LAUNCH" observe "$ws" --file "$obsf"
( . "$RS/lib/state.sh"; state_get "$ws" observations | command grep -qF '`continue` and $(subst)' ) \
  && ok "backticks and dollar-parens landed byte-intact (pre-fix: --file was an unknown arg; --text ate them)" \
  || bad "code fragments mangled or missing: $( . "$RS/lib/state.sh"; state_get "$ws" observations | tail -1)"
assert_rc 2 "observe --file with an absent file refuses, naming it" -- \
  "$LAUNCH" observe "$ws" --file "$base/no-such-observation.txt"

echo "-- status --slices: the per-slice table, from surfaces that already exist --"
# Seventeen slices is a dump, not a panel, so the per-slice view sits behind a
# flag on a separate small reader rather than in the pinned live layout. Two
# rendering rules from config-and-adapters §6 are load-bearing here: BOTH clocks
# are labelled (working is what the budget spends, total is what a human feels —
# rendering either alone is the elapsed-vs-timeout misread the panel already
# paid for), and the backend column names the EXCEPTION, not the norm.
sws=$(mk_ws "$base" statusslices "$repo" "$branch")
printf 'agent.author.backend=claude\nagent.reviewer.backend=claude\n' > "$sws/config/topic.kv"
t0=$(( $(date +%s) - 7200 ))
( . "$RS/lib/state.sh"
  printf 'id=01 status=done risk=low title=first rederive=0\nid=02 status=active risk=high title=second rederive=0\n' \
    | state_set "$sws" slices ferry
  state_put "$sws" attempts ferry "slice.01.started=$t0" "parked.01=1800" "slice.02.started=$t0" > /dev/null
  state_append "$sws" ledger ferry "v=1 t=$t0 event=spawn slice=01 stage=spec round=1 attempt=1 mode=cold session=s1 backend=claude model=m effort=low"
  state_append "$sws" ledger ferry "v=1 t=$((t0 + 3600)) event=advance slice=01 stage=turnover verdict=done target=next_slice"
  state_append "$sws" ledger ferry "v=1 t=$((t0 + 3601)) event=spawn slice=02 stage=spec round=1 attempt=1 mode=cold session=s2 backend=codex model=m effort=low" ) > /dev/null
out=$("$LAUNCH" status "$sws" --slices 2>&1); rc=$?
[ $rc -eq 0 ] && ok "status --slices renders (rc=0)" || bad "rc=$rc: $(printf '%s' "$out" | head -3 | tr '\n' ' ')"
command grep -qE '^01 ' <<< "$out" && command grep -qE '^02 ' <<< "$out" \
  && ok "every index row is listed, in id order" || bad "rows missing: $out"
printf '%s\n' "$out" | command grep -E '^01 ' | command grep -q 'work 30m · total 1h00m' \
  && ok "BOTH clocks are rendered and LABELLED, and work EXCLUDES the credited park (1h wall, 30m parked -> work 30m)" \
  || bad "clock row: $(printf '%s\n' "$out" | command grep -E '^01 ')"
printf '%s\n' "$out" | command grep -E '^01 ' | command grep -q 'done' \
  && ok "a finished slice's clocks stop at its turnover advance, not at now" \
  || bad "row 01: $(printf '%s\n' "$out" | command grep -E '^01 ')"
printf '%s\n' "$out" | command grep -E '^02 ' | command grep -q 'codex' \
  && ok "the backend column NAMES a slice that ran on a backend the topic level does not (the exception)" \
  || bad "the exception is not rendered: $(printf '%s\n' "$out" | command grep -E '^02 ')"
command grep -q 'claude' <<< "$(printf '%s\n' "$out" | command grep -E '^01 ')" \
  && bad "the topic-level backend is rendered too — the column names the norm, so one backend everywhere is noise" \
  || ok "and stays SILENT for the slice that ran on the topic-level one (exception, not norm)"
command grep -qE '[[:space:]]$' <<< "$out" \
  && bad "a rendered row ends in the column pad — invisible on screen, not in a capture" \
  || ok "no row carries trailing blanks (the column pad is trimmed, as the panel trims its own)"
printf '%s\n' "$out" | tail -1 | command grep -q 'the topic level does not name' \
  && ok "the table's footer is the table's last line (its subject is named)" \
  || bad "the footer is not the last line — the arms below would read a data row: $(printf '%s\n' "$out" | tail -1)"
command grep -q 'claude + claude' <<< "$(printf '%s\n' "$out" | tail -1)" \
  && bad "the footer repeats one backend per ROLE — author and reviewer on the same backend is the norm, not two" \
  || ok "the footer names each distinct topic-level backend once"
assert_rc 2 "status with an unknown flag refuses, naming the usage" -- "$LAUNCH" status "$sws" --bogus
sws2=$(mk_ws "$base" statusnoindex "$repo" "$branch")
assert_rc 2 "status --slices before any split refuses (absent index is not an empty table)" -- \
  "$LAUNCH" status "$sws2" --slices
assert_out_has "split has not run" "and says so as ABSENT, not as a fault"
# fault != absent, in a read-only reader too: a corrupt index must not read as
# the ordinary pre-split state, and a faulted config must not collapse to an
# empty topic-level set — which would render every slice as an exception, a
# table quietly claiming the whole run went off-assignment.
corrupt_surface "$sws" slices
assert_rc 2 "a CORRUPT slices surface refuses as corrupt, never as 'no index yet'" -- \
  "$LAUNCH" status "$sws" --slices
assert_out_has "CORRUPT" "the refusal names the fault class"
# ...and on the SECONDARY surfaces the reader draws from, where the corruption
# is one step removed from the refusal the index already pins: a corrupt
# attempts surface collapsing to empty would render every clock as "-" (a table
# quietly claiming no slice ever started), and a corrupt ledger collapsing to
# empty would drop every turnover end (clocks running on to now) and every
# off-assignment backend — both a live-looking table over a broken source.
# Each fault gets its OWN workspace with the other surface VALID, so the
# refusal can only come from the check under test — a shared fixture would let
# the first corruption backstop the second arm, and a dead check would pass.
sws4=$(mk_ws "$base" statusledfault "$repo" "$branch")
printf 'agent.author.backend=claude\nagent.reviewer.backend=claude\n' > "$sws4/config/topic.kv"
( . "$RS/lib/state.sh"
  printf 'id=01 status=done risk=low title=first rederive=0\n' | state_set "$sws4" slices ferry
  state_put "$sws4" attempts ferry "slice.01.started=$t0" "parked.01=60" > /dev/null
  state_append "$sws4" ledger ferry "v=1 t=$t0 event=spawn slice=01 stage=spec round=1 attempt=1 mode=cold session=s1 backend=claude model=m effort=low" ) > /dev/null
corrupt_surface "$sws4" ledger
assert_rc 2 "a CORRUPT ledger refuses — slice ends and backends must not be read over a fault" -- \
  "$LAUNCH" status "$sws4" --slices
assert_out_has "CORRUPT" "the refusal names the fault class"
sws5=$(mk_ws "$base" statusattfault "$repo" "$branch")
printf 'agent.author.backend=claude\nagent.reviewer.backend=claude\n' > "$sws5/config/topic.kv"
( . "$RS/lib/state.sh"
  printf 'id=01 status=done risk=low title=first rederive=0\n' | state_set "$sws5" slices ferry
  state_put "$sws5" attempts ferry "slice.01.started=$t0" "parked.01=60" > /dev/null
  state_append "$sws5" ledger ferry "v=1 t=$t0 event=spawn slice=01 stage=spec round=1 attempt=1 mode=cold session=s1 backend=claude model=m effort=low" ) > /dev/null
corrupt_surface "$sws5" attempts
assert_rc 2 "a CORRUPT attempts surface refuses — the clocks must not render '-' over a fault" -- \
  "$LAUNCH" status "$sws5" --slices
assert_out_has "CORRUPT" "the refusal names the fault class"
sws3=$(mk_ws "$base" statusfaultcfg "$repo" "$branch")
printf 'liveness.quiet_grace=2\nliveness.nudge_grace=180\nliveness.stage_timeout=60\n' > "$sws3/config/topic.kv"
( . "$RS/lib/state.sh"
  printf 'id=01 status=active risk=low title=a rederive=0\n' | state_set "$sws3" slices ferry ) > /dev/null
precond "the config fixture really faults (else the next line proves nothing)" \
  bash -c '. "$1/lib/config.sh"; ! config_get agent.author.backend --topic-dir "$2" > /dev/null 2>&1' _ "$RS" "$sws3"
assert_rc 2 "a FAULTED config refuses rather than rendering a backend column it cannot ground" -- \
  "$LAUNCH" status "$sws3" --slices
assert_out_has "config fault" "naming the fault instead of guessing an empty topic-level set"

echo "-- slice restore: the documented 'restored' spelling works --"
( . "$RS/lib/state.sh"
  printf 'id=01 status=cancelled risk=low title=a rederive=0\n' \
    | state_set "$ws" slices ferry ) > /dev/null
assert_rc 0 "launch.sh slice <ws> 01 restored (docs' word) restores" -- \
  "$LAUNCH" slice "$ws" 01 restored
( . "$RS/lib/state.sh"; state_get "$ws" slices | command grep "id=01" \
    | command grep -q "status=pending.*rederive=1\|rederive=1.*status=pending" ) \
  || ( . "$RS/lib/state.sh"; state_get "$ws" slices | command grep "id=01" \
    | command grep -q "status=pending" )
[ $? -eq 0 ] && ok "restored -> pending with the rederive flag" \
  || bad "restore alias broken: $( . "$RS/lib/state.sh"; state_get "$ws" slices | command grep 'id=01')"

echo "-- session write paths: decision + learn + observe (record.sh) --"
activate_stage "$ws" impl 01 1 nV1
assert_rc 0 "record.sh decision appends a DP" -- \
  "$RECORD" decision "$ws" --dp 01/DP-1 --class A \
  --text "choice=x over y basis=coding-rules evidence=grep revert=swap"
( . "$RS/lib/state.sh"; state_get "$ws" decisions | command grep -q "dp=01/DP-1 class=A" ) \
  && ok "DP landed in the decisions surface" || bad "decisions surface missing the DP"
assert_rc 2 "decision with an unknown class refuses" -- \
  "$RECORD" decision "$ws" --dp 01/DP-2 --class Z --text x
assert_rc 2 "malformed DP id refuses (grammar is <slice>/DP-<n>)" -- \
  "$RECORD" decision "$ws" --dp garbage/DP-x --class A --text x
assert_rc 2 "a DP addressed to a FOREIGN slice refuses (audit-exactly-once needs the address to hold)" -- \
  "$RECORD" decision "$ws" --dp 02/DP-1 --class A --text x
assert_rc 2 "a duplicate DP id refuses (one DP = one choice)" -- \
  "$RECORD" decision "$ws" --dp 01/DP-1 --class A --text x
assert_out_has "--amend" "…and the refusal names the correction path, so a falsified DP is not pushed into prose"
# A recorded DP is corrected ON THE SURFACE (review-standards §11): --amend
# re-records the id, the row carries amends=<t of the row it replaces>, and
# re-enters pending_audit. Append-only is never-destroy-history, not write-once.
assert_rc 2 "--amend on an id with no row refuses (nothing to supersede)" -- \
  "$RECORD" decision "$ws" --dp 01/DP-9 --class A --text x --amend
assert_out_has "no row to amend" "the refusal says the id must be recorded first"
dp_t0=$( . "$RS/lib/state.sh"; state_get "$ws" decisions | command grep 'dp=01/DP-1 ' | tail -1 \
         | awk '{for(i=1;i<=NF;i++) if($i ~ /^t=/){sub(/^t=/,"",$i); print $i; exit}}')
precond "the first DP-1 row has a t= stamp to be named by the amend" test -n "$dp_t0"
( . "$RS/lib/state.sh"; state_get "$ws" decisions | command grep 'dp=01/DP-1 ' | head -1 \
    | command grep -qE '(^| )amends=( |$)' ) \
  && ok "a first record carries amends= EMPTY (present on every row, so absent and not-applicable never look alike)" \
  || bad "the first DP row lacks the empty amends field: $( . "$RS/lib/state.sh"; state_get "$ws" decisions | command grep 'dp=01/DP-1 ' | head -1)"
sleep 1   # the amend must carry a distinct stamp from the row it names
assert_rc 0 "--amend re-records an existing id" -- \
  "$RECORD" decision "$ws" --dp 01/DP-1 --class A --amend \
  --text "choice=x over y basis=coding-rules evidence=grep, count corrected 3->4 revert=swap"
dp_last=$( . "$RS/lib/state.sh"; state_get "$ws" decisions | command grep 'dp=01/DP-1 ' | tail -1)
command grep -qE "(^| )amends=$dp_t0( |$)" <<< "$dp_last" \
  && command grep -qE '(^| )status=pending_audit( |$)' <<< "$dp_last" \
  && ok "the amend row names the row it supersedes (amends=$dp_t0) and re-enters pending_audit" \
  || bad "the amend row is not a supersede: $dp_last"
[ "$( . "$RS/lib/state.sh"; state_get "$ws" decisions | command grep -c 'dp=01/DP-1 ')" -eq 2 ] \
  && ok "…and BOTH rows stay on the surface (history is never destroyed; the reader takes the latest)" \
  || bad "the amend did not append — rows for DP-1: $( . "$RS/lib/state.sh"; state_get "$ws" decisions | command grep -c 'dp=01/DP-1 ')"
mk_review "$ws/slices/01/postcheck.1.md" postcheck 01 1
activate_stage "$ws" postcheck 01 1 nV2
assert_rc 0 "record.sh learn appends a leak-tagged learning" -- \
  "$RECORD" learn "$ws" --leak-class precheck --text "finding X was precheck-catchable"
( . "$RS/lib/state.sh"; state_get "$ws" learnings | command grep -q "leak_class=precheck" ) \
  && ok "learning landed with its leak_class" || bad "learnings surface missing the entry"
assert_rc 2 "learn with an unknown leak class refuses (closed vocabulary)" -- \
  "$RECORD" learn "$ws" --leak-class vibes --text x
assert_rc 0 "record.sh observe appends a session-side observation" -- \
  "$RECORD" observe "$ws" --text "stage-side workflow friction Y"
( . "$RS/lib/state.sh"; state_get "$ws" observations | command grep -q "friction Y" ) \
  && ok "session observation landed" || bad "session observe did not write"

echo "-- whitespace in the workspace path refuses at preflight (quoting is not audited that deep) --"
wsp2="$base/bad dir/topics/goodtopic/delivery"   # space in a PARENT — the
mkdir -p "$wsp2/config"                          # topic-name charset guard
cp "$ws/project.kv" "$wsp2/project.kv" 2>/dev/null || true   # cannot see it
out=$(bash "$RS/launch.sh" launch "$wsp2" 2>&1); rc=$?
livelaunch=$out                      # every live-tree launch's output, for the
                                     # no-real-session floor at the end
[ $rc -ne 0 ] && command grep -qi "whitespace\|space" <<< "$out" \
  && ok "spaced workspace path refused with a self-describing message" \
  || bad "rc=$rc msg='$(printf '%s' "$out" | tail -1)' — hooks/cmd.launch interpolate this path unquoted"

echo "-- a stray schema-legal .kv at the workspace ROOT is NAMED at preflight --"
# Measured: a workspace prepared with topic.kv at <ws>/topic.kv resolved every
# value from defaults.kv, because config.sh reads the topic layer from
# <ws>/config/topic.kv. Nothing refused; the run silently lost the reviewer's
# backend and model, all_cold, and three slice caps. The existing defense named
# the CONSEQUENCE for one key family and never the CAUSE — an operator was told
# to "set agent.reviewer.backend", which that workspace HAD set, one directory
# away. This arm asserts the cause is named. WARN, never refuse: a refusal would
# also block a root layout nobody has needed yet.
wsk="$base/topics/straykv/delivery"
mkdir -p "$wsk/config"
# project.kv names a path that is NOT a git checkout, ON PURPOSE: the stray-kv
# WARNING is emitted at the project.kv gate, and the git-checkout refusal is the
# next door after it — so this fixture reaches everything the arms assert and
# stops one step later. Copying the VALID project.kv (what this fixture used to
# do) let the launch walk on into the backend onboarding probe, which spawns a
# REAL CLI session: measured 29s per suite run, and only when the workflow tree
# is CLEAN, because a dirty tree refuses at the preflight's uncommitted-changes
# door first. A maintainer's commit gate always runs dirty by construction — the
# tree is not committed yet — so that cost, and the real session behind it, were
# invisible in every pre-commit run and appeared only when the suite was run
# after committing. The deep launch path is the DRILLS' job, in a shadow tree
# with a mock backend (drill/lib.sh declares `backend=test`); no check should
# spawn a live backend.
mkdir -p "$base/notarepo"          # EXISTS but is not a git checkout, so the
                                   # refusal is the git-shaped one rather than
                                   # "is not a directory" — the door this
                                   # fixture means to stop at
printf 'repo=%s/notarepo\nbranch=main\ncommit.subject_regex=^(feat|fix|chore): [a-z]\n' "$base" > "$wsk/project.kv"
printf 'agent.reviewer.backend=claude\n' > "$wsk/topic.kv"
out=$(bash "$RS/launch.sh" launch "$wsk" 2>&1) || true
livelaunch="$livelaunch$out"
command grep -q "topic.kv" <<< "$out" \
  && command grep -qi "workspace ROOT\|config/topic.kv" <<< "$out" \
  && ok "preflight names the stray file AND where the topic layer is really read from" \
  || bad "stray root .kv passed unnamed: $(printf '%s' "$out" | command grep -i kv | head -2)"
# and the legal one must stay silent, or the warning is noise on every launch
rm -f "$wsk/topic.kv"
out=$(bash "$RS/launch.sh" launch "$wsk" 2>&1) || true
# The run must have SAID something before its silence about the root set can
# mean anything — a launch that crashed before the preflight would pass the
# arm below for free. The positive arm above pins the warning mechanism; this
# pins the run it is absent from.
precond "the clean-root launch ran and produced output (${#out} bytes)" \
  test -n "$out"
command grep -q "sits at the workspace ROOT" <<< "$out" \
  && bad "project.kv itself warned — the arm would fire on every launch" \
  || ok "project.kv alone draws no warning (the legal root set is exactly that one file)"
livelaunch="$livelaunch$out"

echo "-- a CONFIG key inside project.kv is NAMED at preflight; a legitimate cap key is not --"
# The misplaced-FILE arm above and this one are the same asymmetry one level in:
# a key the config schema defines LOOKS like it will resolve from the adapter
# and does not. Measured live: agent.implementer.effort=max sat in project.kv,
# the snapshot carried the default `high`, and an owner directive went silently
# unenforced across two slices. Predicate is derived (schema INTERSECT
# project.kv, minus caps), so this arm must pin BOTH directions or it would
# either be noise on every launch or blind to the next config family.
printf 'agent.implementer.effort=max\nagent.reviewer.backend=claude\ncap.commit_diff_lines=500\n' >> "$wsk/project.kv"
out=$(bash "$RS/launch.sh" launch "$wsk" 2>&1) || true
livelaunch="$livelaunch$out"
precond "the inert-key launch ran and produced output (${#out} bytes)" test -n "$out"
command grep -q "config key(s) nothing reads there" <<< "$out" \
  && command grep -q "agent.implementer.effort" <<< "$out" \
  && command grep -q "config/topic.kv" <<< "$out" \
  && ok "preflight names the inert config keys BY NAME and where that layer is really read from" \
  || bad "an inert config key in project.kv passed unnamed: $(printf '%s' "$out" | command grep -i 'config key' | head -1)"
# the cap key rode in the same file and must NOT be named: caps are the one
# family the adapter is genuinely read for (_gates_cap asks project_get first),
# so naming them would make this warning wrong on every real adapter.
command grep -q 'cap.commit_diff_lines' <<< "$out" \
  && bad "the cap key was named — caps are legitimately the adapter's and _gates_cap reads them from there" \
  || ok "a legitimate cap key in the same file draws no warning (the predicate subtracts the cap namespace)"
# and with the inert keys gone the warning must vanish, or it is unconditioned
# awk/grep, not python: the filter is line-shaped, and python3 was the
# suite's one unguarded interpreter (a python3-less box failed here rather
# than skipping). grep exits 1 when nothing survives — captured, since the
# empty file is still the move (the || true), never a failed edit.
{ command grep -v '^agent\.' "$wsk/project.kv" > "$wsk/project.kv.tmp" || true; }
mv "$wsk/project.kv.tmp" "$wsk/project.kv"
# `route=` rides in the SAME cleaned adapter, and it is the arm the routing
# verdict's second home rests on: the key carries an opaque lane verdict
# (config-and-adapters.md §3), has no schema.kv entry by design, and must
# therefore be invisible to a predicate that is exactly schema ∩ adapter. If
# anyone ever adds `route` to schema.kv, this warning would start telling every
# launcher their verdict is silently ignored — which would be false, and the
# only thing that would notice is this assertion.
printf 'route=planning+delivery — Q1 no: two designs live; Q2 yes; Q3 no: two repos\n' >> "$wsk/project.kv"
out=$(bash "$RS/launch.sh" launch "$wsk" 2>&1) || true
livelaunch="$livelaunch$out"
precond "the cleaned-adapter launch ran and produced output (${#out} bytes)" test -n "$out"
command grep -q "config key(s) nothing reads there" <<< "$out" \
  && bad "the warning fires with no inert key present — it is unconditioned" \
  || ok "an adapter carrying only its own keys plus caps plus route= is silent"
rv=$( . "$RS/lib/config.sh"; project_get "$wsk" route 2>/dev/null )
[ "$rv" = "planning+delivery — Q1 no: two designs live; Q2 yes; Q3 no: two repos" ] \
  && ok "…and project_get reads route= back whole (an unschema'd adapter key needs no vocabulary entry)" \
  || bad "project_get did not return the route verdict verbatim; got '$rv'"

echo "-- no live-tree launch fixture spawns a real backend session (cost + quota floor) --"
# This file holds the suite's ONLY launches against the LIVE workflow tree
# (every other launch runs in a drill's shadow tree on the mock backend). The
# fixtures declare no backend, so they inherit defaults.kv's `claude` — and any
# fixture that walks past the project.kv gate reaches the onboarding probe and
# spawns a REAL Claude Code session. Floored rather than left to fixture
# discipline because the failure is SILENT in the normal case: a maintainer's
# pre-commit run has a dirty tree, which refuses at the uncommitted-changes door
# long before the probe, so the cost only appears after committing — which is
# when nobody runs the gate. Measured when it regrew: +29s of suite wall and one
# live CLI invocation per run.
# FLOOR, and it is the arm's own trap: on a DIRTY tree every one of these
# launches refuses at the uncommitted-changes door, so "no probe ran" would be
# true for free — vacuous in exactly the condition a maintainer runs the gate
# in. So the precondition is that each launch reached a NAMED door rather than
# dying somewhere, and the verdict names WHICH door, so a reader of a dirty-tree
# run can see that the clean-tree path is not the one that was exercised.
precond "the live-tree launches produced output to judge (${#livelaunch} bytes)" \
  test -n "$livelaunch"
door=""
command grep -q "is not a git checkout" <<< "$livelaunch" && door="project.kv git-checkout gate (clean tree — the intended terminus)"
command grep -q "uncommitted changes under" <<< "$livelaunch" && door="${door:+$door + }preflight dirty-tree gate (the tree under test is dirty)"
precond "each live-tree launch stopped at a NAMED preflight door, not by dying${door:+ — $door}" \
  test -n "$door"
command grep -qE "probe: spawning|watchdog started" <<< "$livelaunch" \
  && bad "a live-tree launch fixture reached the backend probe or started a watchdog — it spawns a real session: $(printf '%s' "$livelaunch" | command grep -E "probe: spawning|watchdog started" | head -1)" \
  || ok "no live-tree launch fixture reaches the onboarding probe — stopped at: $door"

echo "-- a dirty workflow tree refuses at preflight (launch is the adoption door) --"
# The live tree cannot host this fixture (a maintainer's own edits would make
# every launch fixture red), so a SHADOW copy under a fixture git repo carries
# the controlled clean/dirty states — the same shape the pin fixtures use.
shroot=$(sc_tmpdir)
cp -a "$WF_ROOT" "$shroot/wf"
( cd "$shroot" && git init -q . \
  && git config user.email sc@example.invalid && git config user.name selfcheck \
  && echo sibling > outside.txt \
  && git add -A && git commit -qm "chore: fixture workflow tree" )
SHL="$shroot/wf/runtime-scripts/launch.sh"
shws="$shroot/topics/dirtytopic/delivery"
mkdir -p "$shws/config"                          # no project.kv: the clean
precond "shadow launch.sh exists" test -f "$SHL"  # path refuses THERE, later
out=$(bash "$SHL" launch "$shws" 2>&1); rc=$?
[ $rc -ne 0 ] && command grep -q "project.kv" <<< "$out" \
  && ok "CLEAN shadow tree passes the dirty gate and refuses later at project.kv (null control)" \
  || bad "clean-tree control broken: rc=$rc '$(printf '%s' "$out" | tail -1)'"
echo tampered >> "$shroot/wf/runtime-scripts/ferry.sh"
out=$(bash "$SHL" launch "$shws" 2>&1); rc=$?
[ $rc -ne 0 ] && command grep -q "commit or stash" <<< "$out" \
  && ok "a TRACKED edit inside the workflow subtree refuses, self-describing (pre-fix: silently adopted and pinned as 'the tree')" \
  || bad "dirty tree not refused: rc=$rc '$(printf '%s' "$out" | tail -1)'"
( cd "$shroot" && git checkout -q wf/runtime-scripts/ferry.sh )
echo brand-new > "$shroot/wf/runtime-scripts/new-half.sh"
out=$(bash "$SHL" launch "$shws" 2>&1); rc=$?
command grep -q "commit or stash" <<< "$out" \
  && ok "an UNTRACKED file inside the subtree refuses too (a brand-new script is exactly the edit that bites)" \
  || bad "untracked dirt not refused: '$(printf '%s' "$out" | tail -1)'"
rm -f "$shroot/wf/runtime-scripts/new-half.sh"
echo drift > "$shroot/outside.txt"
out=$(bash "$SHL" launch "$shws" 2>&1); rc=$?
command grep -q "project.kv" <<< "$out" \
  && ok "dirt OUTSIDE the workflow subtree does NOT refuse (scoped -- . like the pin; sibling changes are not this tree's)" \
  || bad "outside-subtree dirt tripped the gate: '$(printf '%s' "$out" | tail -1)'"

echo "-- stop on a topic with nothing running says what is true, and leaves no file behind --"
# Measured 2026-08-21, by a pilot trying to execute "stop the ferry, restart
# after the fixes land" and checking the verb first. The else branch said the
# request "will be honored (and cleared) at next launch". It is cleared —
# init_runtime removes stop-request before the ferry that would read it
# exists — and it is never honored. Both halves of one sentence, false.
# The predicate was wrong too: no WATCHDOG is not no runner. A watchdog can
# die while the ferry it started lives on, and that ferry reads the request at
# its next poll. The host lock is the truth about a live ferry, and it is one
# derivation (lib/state.sh), not a second copy of the store path.
stopws=$(mk_ws "$base" stoptopic "$repo" "$branch")
out=$("$LAUNCH" stop "$stopws" 2>&1); rc=$?
[ $rc -eq 0 ] && ok "stop returns 0 on an idle topic" || bad "rc=$rc: $out"
command grep -qi 'will be honored' <<< "$out" \
  && bad "stop still promises the request will be honored at next launch: '$out' — init_runtime deletes it first" \
  || ok "stop no longer promises a honouring that cannot happen"
[ -e "$stopws/.runtime/stop-request" ] \
  && bad "a stop-request file was written with nothing running to read it — the next launch deletes it silently" \
  || ok "no stop-request file is left behind when nothing can honour one"
command grep -qi 'nothing to stop\|already' <<< "$out" \
  && ok "and it says what IS true: the topic is not running" \
  || bad "the message does not state the actual state: '$out'"
# Good direction: a live runner still gets the file and the graceful promise.
printf '%s\n' "$$" > "$stopws/.runtime/watchdog.pid"
out=$("$LAUNCH" stop "$stopws" 2>&1); rc=$?
[ -e "$stopws/.runtime/stop-request" ] \
  && ok "with a live watchdog the request IS written (the path that works is untouched)" \
  || bad "no stop-request written while a live watchdog holds the topic: '$out'"
command grep -q 'park' <<< "$out" \
  && ok "and the message promises the graceful park it can actually deliver" \
  || bad "message: '$out'"
# …and it must say WHAT IS STILL RUNNING, because `stop` addresses the ferry and
# the stage is a separate session with its own lifetime. Measured 2026-09-03:
# the ferry parked, the stopped stage emitted its record 3m47s later with no
# ferry running, and the relaunch harvested it and advanced in the same second —
# harmless only because that stage was turnover. One stage earlier and a whole
# spec would have landed on the configuration the operator stopped to change.
# Both directions, because the silent half is what a fixture would otherwise
# ride: a RUNNING stage draws the warning, an idle one does not.
printf '%s\n' "$$" > "$stopws/.runtime/watchdog.pid"
( . "$RS/lib/state.sh"
  printf 'state=running\nslice=03\nstage=spec\nt=%s\n' "$(date +%s)" \
    | state_set "$stopws" stage ferry ) > /dev/null
out=$("$LAUNCH" stop "$stopws" 2>&1)
command grep -q 'STILL RUNNING' <<< "$out" \
  && ok "a stop over a RUNNING stage says the stage is not what was stopped" \
  || bad "stop said nothing about the live stage: '$out'"
command grep -q 'slice 03 stage spec' <<< "$out" \
  && ok "and it names which one (slice 03 stage spec) — the ferry already knew" \
  || bad "the warning does not name the live stage: '$out'"
command grep -qi 'HARVEST' <<< "$out" \
  && ok "and says the next launch will harvest its record — the half that voids an intervention silently" \
  || bad "the consequence is not stated: '$out'"
( . "$RS/lib/state.sh"
  printf 'state=done\nslice=03\nstage=spec\nt=%s\n' "$(date +%s)" \
    | state_set "$stopws" stage ferry ) > /dev/null
out=$("$LAUNCH" stop "$stopws" 2>&1)
command grep -q 'STILL RUNNING' <<< "$out" \
  && bad "a stop over a DONE stage still warned about a live one: '$out'" \
  || ok "and a stage that is not running draws no warning (the arm is not a constant)"
rm -f "$stopws/.runtime/watchdog.pid" "$stopws/.runtime/stop-request"
# …and "no watchdog" is NOT "no runner": a watchdog can die while the ferry it
# started lives on, and that ferry reads the request at its next poll. The host
# lock is the truth about a live ferry. Nothing exercised this branch until a
# mutation deleted it and the suite stayed green — so it is fabricated here,
# with no watchdog pid at all.
lockws=$(mk_ws "$base" stoplock "$repo" "$branch")
lockd=$( . "$RS/lib/state.sh"; state_host_lock_path "$lockws" )
mkdir -p "$lockd"
( . "$RS/backends/pty_tmux.sh"; printf 'pid=%s\nstart=%s\n' $$ "$(_pty_starttime $$)" ) > "$lockd/pid"
precond "the fabricated host lock reads as a LIVE holder (else the arm is vacuous)" \
  bash -c '. "$1/lib/state.sh"; . "$1/backends/pty_tmux.sh"; state_host_holder "$2" > /dev/null' _ "$RS" "$lockws"
[ -e "$lockws/.runtime/watchdog.pid" ] \
  && bad "the fixture left a watchdog pid — this arm must isolate the host-lock branch" \
  || ok "no watchdog pid stands for this workspace (the branch under test is the only honourer)"
out=$("$LAUNCH" stop "$lockws" 2>&1)
[ -e "$lockws/.runtime/stop-request" ] \
  && ok "a live FERRY with no watchdog still gets the stop-request written" \
  || bad "no request written though a live ferry holds the host lock: '$out'"
command grep -q 'ferry' <<< "$out" \
  && ok "and the message names the ferry as the thing that will park" \
  || bad "message names no honourer: '$out'"
rm -rf "$lockd" "$lockws/.runtime/stop-request"
out=$("$LAUNCH" stop "$lockws" 2>&1)
[ ! -e "$lockws/.runtime/stop-request" ] \
  && ok "and once that lock is gone it is back to nothing-to-stop (the branch reads the lock, not the workspace's history)" \
  || bad "a stale judgment: '$out'"

echo "-- the halt frame's pointer names a command that exists --"
# Two anchors, five slices apart, on two different park classes: the panel
# printed "full text N chars: launch.sh status <workspace> --once" and status
# has no --once. monitor.sh --once renders the same truncated frame, so
# neither command printed what the pointer promised; the only thing that did
# was reading <ws>/.runtime/state/halt, the store the operator is told to
# leave alone. The hint rides the halt FRAME, so every park reason inherits
# it, and it is read at the moment the full text is the thing needed.
# This arm takes the flag FROM the panel's own string and hands it to the
# verb, so the two cannot drift apart again.
hint=$(command grep -om1 'launch\.sh status <workspace> --[a-z-]*' "$RS/monitor.sh")
precond "the panel prints a status hint for the halt frame" test -n "$hint"
hflag=${hint##* }
hws=$(mk_ws "$base" haltptr "$repo" "$branch")
long=$(printf 'Q%.0s' $(seq 1 400))
( . "$RS/lib/state.sh"
  printf 'reason=class_u\nslice=07\nstage=spec\nround=1\nt=%s\nresolved=0\nnotified=1\ndetail=%s\n' \
    "$(date +%s)" "$long batched owner questions" | state_set "$hws" halt ferry ) > /dev/null
out=$("$LAUNCH" status "$hws" "$hflag" 2>&1); rc=$?
[ $rc -eq 0 ] \
  && ok "the flag the halt frame points at ('$hflag') is accepted by status (rc=0)" \
  || bad "the panel points at 'launch.sh status <ws> $hflag' and status refuses it: $(printf '%s' "$out" | head -1)"
command grep -q "$long" <<< "$out" \
  && ok "and it prints the detail UNTRUNCATED — the thing the pointer promises" \
  || bad "the full detail did not come out: $(printf '%s' "$out" | head -2 | tr '\n' ' ')"
command grep -q 'class_u' <<< "$out" \
  && ok "with the halt's own fields around it (reason named)" \
  || bad "no reason field in the output: $out"
hws2=$(mk_ws "$base" haltptr2 "$repo" "$branch")
out=$("$LAUNCH" status "$hws2" "$hflag" 2>&1); rc=$?
[ $rc -eq 0 ] && command grep -qi 'not parked\|no halt' <<< "$out" \
  && ok "on an unparked topic it says so rather than faulting" \
  || bad "rc=$rc on an unparked topic: $out"
# fault != absent, in this reader too. status_slices refuses a corrupt index
# rather than calling it "no slices yet", and the panel says "STORE FAULT in
# the halt surface — a park may be hidden". This verb is read at the moment a
# topic is parked; answering "not parked" over a corrupt surface is the worst
# available lie, and the first version of it did exactly that.
corrupt_surface "$hws" halt
out=$("$LAUNCH" status "$hws" "$hflag" 2>&1); rc=$?
[ $rc -ne 0 ] && command grep -q 'CORRUPT' <<< "$out" \
  && ok "a CORRUPT halt surface refuses as corrupt, never as 'not parked' (rc=$rc)" \
  || bad "rc=$rc over a corrupt halt surface: $out"
# The field list is the SURFACE's, not one this reader maintains: park() gains
# a field and it prints, with no second place to update. The first version
# carried a hand-written list that already named `next` — which park() has
# never written; the panel DERIVES that line from the reason.
hws3=$(mk_ws "$base" haltptr3 "$repo" "$branch")
( . "$RS/lib/state.sh"
  printf 'reason=blocked\ndetail=short one\nslice=03\nstage=impl\nt=%s\nresolved=0\nbrand_new_field=xyzzy\n' \
    "$(date +%s)" | state_set "$hws3" halt ferry ) > /dev/null
out=$("$LAUNCH" status "$hws3" "$hflag" 2>&1)
command grep -q 'brand_new_field .*xyzzy' <<< "$out" \
  && ok "a field this reader has never heard of still prints (the surface is the list)" \
  || bad "an unknown halt field was dropped: $out"
command grep -q '^next ' <<< "$out" \
  && bad "it prints a 'next' field — park() writes none; the panel derives that line from the reason" \
  || ok "no phantom fields: it prints what the surface holds and nothing it imagines"
# …and nothing it does not RECOGNISE is hidden either. A store hand-repaired
# out of band is a measured event in this tree, and a stray line is exactly
# what an operator following the panel's pointer needs to see.
hws4=$(mk_ws "$base" haltptr4 "$repo" "$branch")
( . "$RS/lib/state.sh"
  printf 'reason=blocked\nA STRAY LINE WITH NO KEY\nslice=07\ndetail=short\n' \
    | state_set "$hws4" halt ferry ) > /dev/null
out=$("$LAUNCH" status "$hws4" "$hflag" 2>&1)
command grep -q 'A STRAY LINE WITH NO KEY' <<< "$out" \
  && ok "a line that is not key=value is shown, not swallowed (marked, so it cannot read as a field)" \
  || bad "the reader dropped a line the surface holds: $out"
command grep -q 'reason.*blocked' <<< "$out" \
  && ok "and the real fields still render around it" || bad "$out"

echo "-- stop over a PAGING watchdog ends the paging; over a DRIVER it defers as before --"
# "class=parked + live pid" is the pager (watchdog.sh clears final-state when it
# starts driving), so stop ends that process now instead of writing a request it
# would read only at its next interval and the next launch would clear unread.
pws=$(mk_ws "$base" pagerstop "$repo" "$branch")
mkdir -p "$pws/.runtime"
sleep 60 & fake=$!
printf '%s\n' "$fake" > "$pws/.runtime/watchdog.pid"
printf 'class=parked detail=fixture t=1\n' > "$pws/.runtime/final-state"
# Captured first, never `cmd | grep -q`: under pipefail the pipeline reports the
# LEFT side's rc, and a panel over a bare workspace exits non-zero on purpose.
pout=$("$LAUNCH" status "$pws" 2>&1 || true)
command grep -q 'PAGING' <<< "$pout" \
  && ok "the panel names the state PAGING (a live pid beside class=parked is not 'alive', nothing is driving)" \
  || bad "the panel does not say PAGING over a paging watchdog: $(printf '%s\n' "$pout" | command grep -i watchdog | head -2 | tr '\n' ' ')"
assert_rc 0 "stop over a live pid beside class=parked (the pager) returns 0" -- "$LAUNCH" stop "$pws"
assert_out_has "re-paging stopped" "…and says it ended the paging, not that something parked"
kill -0 "$fake" 2>/dev/null && bad "the pager process is still alive after stop" || ok "the pager process was ended"
wait "$fake" 2>/dev/null
[ ! -e "$pws/.runtime/watchdog.pid" ] && ok "…its pidfile cleared" || bad "pidfile left behind"
[ ! -e "$pws/.runtime/stop-request" ] && ok "…and no stop-request was written (nothing would ever read it)" || bad "a stop-request was written for a pager"
sleep 60 & drv=$!
printf '%s\n' "$drv" > "$pws/.runtime/watchdog.pid"; rm -f "$pws/.runtime/final-state"
assert_rc 0 "stop over a live pid with NO final-state (a driver) writes the request as before" -- "$LAUNCH" stop "$pws"
assert_out_has "stop requested" "…deferring to the driver"
kill -0 "$drv" 2>/dev/null && ok "the driver was NOT killed (stop addresses the ferry; the pager is the only process it ends)" \
  || bad "stop killed a live driver"
kill "$drv" 2>/dev/null; wait "$drv" 2>/dev/null; rm -f "$pws/.runtime/watchdog.pid" "$pws/.runtime/stop-request"

echo "-- ack: the operator's receipt for a park, and status --halt reading the pager's record --"
# The ack is an AUDIT row keyed by halt_id (the halt surface keeps its single
# writer); the pager (watchdog.sh) and status --halt read that same row, so
# this arm drives the verb and then reads it back through status.
aws=$(mk_ws "$base" acktopic "$repo" "$branch")
assert_rc 2 "ack on an unparked topic refuses — nothing to acknowledge" -- "$LAUNCH" ack "$aws"
( . "$RS/lib/state.sh"
  printf 'reason=class_u\ndetail=q\nslice=02\nstage=spec\nround=1\nt=%s\nhalt_id=HA1\nnotified=1\nresolved=0\n' \
    "$(date +%s)" | state_set "$aws" halt ferry
  state_audit "$aws" watchdog "repage 1/6 halt_id=HA1 reason=class_u" ) > /dev/null
out=$("$LAUNCH" status "$aws" "$hflag" 2>&1)
command grep -q '^re-paged *1 time' <<< "$out" && command grep -q '^acked *no' <<< "$out" \
  && ok "status --halt reads the pager's record from the audit surface: 1 re-page, not acked" \
  || bad "status --halt does not show the pager's record: $(printf '%s' "$out" | command grep -E 're-paged|acked' | tr '\n' ' ')"
assert_rc 0 "ack over an unresolved halt writes the receipt (rc=0)" -- "$LAUNCH" ack "$aws"
( . "$RS/lib/state.sh"; state_get "$aws" audit | command grep -q 'by=operator msg=ack halt_id=HA1 reason=class_u' ) \
  && ok "the ack is an audit row keyed by halt_id — the row the pager and status both read" \
  || bad "no ack row on the audit surface"
out=$("$LAUNCH" status "$aws" "$hflag" 2>&1)
command grep -q '^acked *at t=[0-9]' <<< "$out" \
  && ok "status --halt now prints acked at t=<epoch> (re-paging paused, not stopped)" \
  || bad "status --halt does not show the ack: $(printf '%s' "$out" | command grep acked)"
# WHICH STATE HOLDS NOW, not what the mechanism does: an ack from this morning
# and one from a minute ago are opposite operational facts, and rendering the
# mechanism left `at t=` as the operator's only clue. The ack above is seconds
# old, so the window is open.
command grep -q 'is PAUSED now' <<< "$out" \
  && ok "…and a FRESH ack renders as paused-now, with the remainder of the window" \
  || bad "a seconds-old ack does not render as a live pause: $(printf '%s' "$out" | command grep acked)"
# the same row, one expired window later: the newest ack row is an ancient one.
( . "$RS/lib/state.sh"
  state_append "$aws" audit operator "v=1 t=$(( $(date +%s) - 99999 )) by=operator msg=ack halt_id=HA1 reason=class_u — long expired" ) > /dev/null
out=$("$LAUNCH" status "$aws" "$hflag" 2>&1)
command grep -q 'window CLOSED' <<< "$out" \
  && ok "…and an EXPIRED ack says the window closed and paging resumed (the state, not the mechanism)" \
  || bad "an expired ack still renders as a live pause: $(printf '%s' "$out" | command grep acked)"
( . "$RS/lib/state.sh"; state_put "$aws" halt ferry "resolved=1" ) > /dev/null
assert_rc 2 "ack over a RESOLVED halt refuses (nothing left to acknowledge)" -- "$LAUNCH" ack "$aws"
# fault != absent on the EVIDENCE surface too: with the halt surface valid and
# the audit surface corrupt, the reader must refuse rather than print
# "re-paged 0 time(s), acked no" — the second half actively directing the
# operator to re-acknowledge a park that may already be acknowledged.
corrupt_surface "$aws" audit
assert_rc 2 "status --halt over a CORRUPT audit surface refuses — re-page/ack evidence is not 'absent'" -- \
  "$LAUNCH" status "$aws" "$hflag"
assert_out_has "CORRUPT" "the refusal names the fault class"
corrupt_surface "$aws" halt
out=$("$LAUNCH" ack "$aws" 2>&1); rc=$?
[ $rc -ne 0 ] && command grep -q 'CORRUPT' <<< "$out" \
  && ok "a CORRUPT halt surface refuses as corrupt, never as 'nothing to acknowledge' (fault != absent)" \
  || bad "rc=$rc over a corrupt halt surface: $out"

echo "-- mode_src: every value the ferry can stamp is a value the report can name --"
# The spawn row's mode_src separates a DESIGNED cold (the reviewer's round-1
# independence, the spec's authority chain) from a DEGRADED one (a warm-capable
# stage whose reuse failed). Six values, produced in exactly one file, consumed
# by derive_cost's prose — so the only way they drift is a typo in one branch,
# and a typo would print as its own silent bucket rather than fail anything.
# The set is EXTRACTED from attempt.sh rather than restated, so a new branch is
# caught by this arm instead of being covered by it.
ms_vals=$(command grep -oE '\bmode_src=[a-z_]+' "$RS/lib/attempt.sh" | cut -d= -f2 | sort -u)
ms_n=$(printf '%s\n' "$ms_vals" | command grep -c .)
precond "attempt.sh assigns mode_src (saw $ms_n distinct values)" test "$ms_n" -ge 4
ms_bad=""
for v in $ms_vals; do
  case "$v" in designed|degraded|no_session|dead_session|backend_switch|reactivate_failed|warm) : ;;
    *) ms_bad="$ms_bad $v" ;;
  esac
done
[ -z "$ms_bad" ] \
  && ok "every mode_src the ferry stamps is in the declared set ($ms_n values, extracted not listed)" \
  || bad "mode_src values outside the declared set:$ms_bad — a typo here becomes a silent bucket in the cost report"
command grep -qx designed <<< "$ms_vals" \
  && command grep -qx warm <<< "$ms_vals" \
  && ok "…including both poles: a cold the contract asked for, and the warm that means no cold at all" \
  || bad "attempt.sh no longer stamps both 'designed' and 'warm' — the split has lost one of its two ends"
command grep -q 'mode_src=\$mode_src' "$RS/lib/attempt.sh" \
  && ok "and the value reaches the LEDGER row, where the cost report pairs on it" \
  || bad "mode_src is computed and never stamped on the spawn row — derive_cost would read every span 'unrecorded'"

echo "-- help prints the whole verb table (the closing line is part of it) --"
bash "$RS/launch.sh" --help 2>/dev/null | command grep -q "verb set" \
  && ok "help includes the verb-set closing line" \
  || bad "help truncates the header comment (sed range off by one)"


echo "-- rule --topic: a mechanism ruling rides every slice (scope=topic); the halt binding stays by slice --"
rws=$(mk_ws "$base" ruletopic "$repo" "$branch")
assert_rc 0 "rule --slice 03 --topic records (rc=0)" -- "$LAUNCH" rule "$rws" --slice 03 --topic --text "shape rule"
( . "$RS/lib/state.sh"; state_get "$rws" rulings | command grep -qE '(^| )slice=03 .*(^| )scope=topic( |$)' ) \
  && ok "the row keeps slice=03 (the halt it answers) and carries scope=topic (rides every slice)" \
  || bad "rulings row: $( . "$RS/lib/state.sh"; state_get "$rws" rulings)"
[ -f "$rws/slices/03/ruling.1.md" ] && ok "archived under the NAMED slice, not under 00" || bad "no slices/03/ruling.1.md"
assert_rc 0 "rule --topic alone files under 00 (rc=0)" -- "$LAUNCH" rule "$rws" --topic --text "another mechanism"
( . "$RS/lib/state.sh"; state_get "$rws" rulings | command grep -qE '(^| )slice=00 .*(^| )scope=topic( |$)' ) && [ -f "$rws/slices/00/ruling.1.md" ] \
  && ok "…row slice=00 scope=topic, archived at slices/00/ruling.1.md" || bad "topic-alone row/archive missing"
assert_rc 0 "rule --slice 03 without --topic records (rc=0)" -- "$LAUNCH" rule "$rws" --slice 03 --text "this slice's answer"
( . "$RS/lib/state.sh"; state_get "$rws" rulings | command grep -E '(^| )slice=03 .*(^| )n=2( |$)' | command grep -qv 'scope=' ) \
  && ok "a plain slice ruling carries NO scope token (known-bad: the flag is opt-in, never implied)" \
  || bad "scope leaked onto a plain ruling"
assert_rc 2 "rule with neither --slice nor --topic refuses" -- "$LAUNCH" rule "$rws" --text "unaddressed"
assert_out_has "--topic" "the refusal names both ways to address a ruling"

check_done
