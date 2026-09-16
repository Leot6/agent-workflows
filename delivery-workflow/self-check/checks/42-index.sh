#!/usr/bin/env bash
# 42-index — the slices index lifecycle (ferry.sh::ingest_slices /
# next_pending_slice + lib/owed.sh::slices_index): scheduling picks the LOWEST
# pending id; ingest supersedes omitted ids but preserves done/cancelled; an
# EMPTY index can never read as satisfied (a hand-broken split record must not
# walk the topic silently to close-out).
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/fixtures/lib.sh"
. "$RS/lib/state.sh"
. "$RS/lib/owed.sh"

base=$(sc_tmpdir)
read -r repo branch < <(mk_repo "$base/repo")
ws=$(mk_ws "$base" indextopic "$repo" "$branch")
hf=$(mk_headless_ferry)

echo "-- slices_index owed: an EMPTY surface is a miss, not a pass --"
( . "$RS/lib/state.sh"; printf '' | state_set "$ws" slices ferry ) > /dev/null
assert_rc 1 "empty slices surface -> slices_index owed item MISSING (rc 1)" -- \
  _owed_item_check "$ws" split 00 "" "" "" slices_index
assert_out_has "no id=" "the miss names the emptiness"
( . "$RS/lib/state.sh"
  printf 'id=01 status=pending risk=low title=a rederive=0\n' | state_set "$ws" slices ferry ) > /dev/null
assert_rc 0 "a populated index satisfies slices_index" -- \
  _owed_item_check "$ws" split 00 "" "" "" slices_index

echo "-- next_pending_slice picks the LOWEST pending id (risk-first ordering is split's; scheduling is stable) --"
( . "$RS/lib/state.sh"
  printf 'id=03 status=pending risk=low title=c rederive=0\nid=01 status=pending risk=low title=a rederive=0\nid=02 status=active risk=low title=b rederive=0\n' \
    | state_set "$ws" slices ferry ) > /dev/null
nxt=$( ( set +u; . "$hf" "$ws" 2>/dev/null; next_pending_slice ) )
[ "$nxt" = "01" ] && ok "next pending = 01 (lowest id, not newest/highest)" \
  || bad "next_pending_slice returned '$nxt', want 01"
( . "$RS/lib/state.sh"
  printf 'id=02 status=done risk=low title=b rederive=0\n' | state_set "$ws" slices ferry ) > /dev/null
nxt=$( ( set +u; . "$hf" "$ws" 2>/dev/null; next_pending_slice ) )
[ -z "$nxt" ] && ok "no pending slices -> empty (topic proceeds to close-out)" \
  || bad "expected empty, got '$nxt'"

echo "-- after= schedules delivery order: 09 -> 10 -> 03, whatever the id order says --"
# The measured inversion: a re-split minted lower ids than their hard
# prerequisites, and lexicographic-min ran the dependent slice first.
( . "$RS/lib/state.sh"
  printf 'id=03 status=pending risk=low repo=code title=late rederive=0 after=10\nid=09 status=pending risk=low repo=code title=first rederive=0\nid=10 status=pending risk=low repo=code title=second rederive=0 after=09\n' \
    | state_set "$ws" slices ferry ) > /dev/null
nxt=$( ( set +u; . "$hf" "$ws" 2>/dev/null; next_pending_slice ) )
[ "$nxt" = "09" ] \
  && ok "next = 09 (03 is blocked by after=10; pre-fix the scheduler took 03)" \
  || bad "next_pending_slice returned '$nxt', want 09"
( set +u; . "$hf" "$ws" > /dev/null 2>&1; slices_set_status 09 done )
nxt=$( ( set +u; . "$hf" "$ws" 2>/dev/null; next_pending_slice ) )
[ "$nxt" = "10" ] && ok "09 done -> next = 10 (its after is satisfied)" \
  || bad "got '$nxt', want 10"
( set +u; . "$hf" "$ws" > /dev/null 2>&1; slices_set_status 10 done )
nxt=$( ( set +u; . "$hf" "$ws" 2>/dev/null; next_pending_slice ) )
[ "$nxt" = "03" ] && ok "10 done -> next = 03 (the lower id waited its turn)" \
  || bad "got '$nxt', want 03"

echo "-- superseded/cancelled satisfy an after (waiting on a retired id is a deadlock) --"
( . "$RS/lib/state.sh"
  printf 'id=04 status=superseded risk=low repo=code title=r rederive=0\nid=05 status=cancelled risk=low repo=code title=c rederive=0\nid=06 status=pending risk=low repo=code title=go rederive=0 after=04,05\n' \
    | state_set "$ws" slices ferry ) > /dev/null
nxt=$( ( set +u; . "$hf" "$ws" 2>/dev/null; next_pending_slice ) )
[ "$nxt" = "06" ] && ok "afters on superseded + cancelled rows read satisfied" \
  || bad "got '$nxt', want 06"

echo "-- an after naming an ACTIVE row blocks: a RUNNING dependency is not satisfied --"
# The three statuses that satisfy an after= are done/superseded/cancelled; the
# three that do not are pending, active and missing. `active` had no arm, and a
# mutation dropping it from the test survived the whole suite — while the
# ferry's own advance guard names the state it produces ("every one waits on an
# after= that is pending/active/missing — a wedged index") and resume.sh's
# plan_changed path demotes an interrupted ACTIVE slice precisely because
# next_pending_slice will not schedule around one.
( . "$RS/lib/state.sh"
  printf 'id=02 status=active risk=low repo=code title=running rederive=0\nid=08 status=pending risk=low repo=code title=waiter rederive=0 after=02\n' \
    | state_set "$ws" slices ferry ) > /dev/null
nxt=$( ( set +u; . "$hf" "$ws" 2>/dev/null; next_pending_slice ) )
[ -z "$nxt" ] \
  && ok "a pending row waiting on an ACTIVE dependency is not scheduled" \
  || bad "scheduled '$nxt' while its after= dependency is still running"

echo "-- an after naming a MISSING row blocks; the advance guard parks, never close-out --"
( . "$RS/lib/state.sh"
  printf 'id=07 status=pending risk=low repo=code title=orphan rederive=0 after=02\n' \
    | state_set "$ws" slices ferry ) > /dev/null
nxt=$( ( set +u; . "$hf" "$ws" 2>/dev/null; next_pending_slice ) )
[ -z "$nxt" ] \
  && ok "a hand-broken row waiting on a missing id is never scheduled out of order" \
  || bad "scheduled '$nxt' over a missing prerequisite row"
wsaw=$(mk_full_ws "$base" afterwedge "$repo" "$branch")
( . "$RS/lib/state.sh"
  printf 'id=01 status=active risk=low repo=code title=a rederive=0\nid=07 status=pending risk=low repo=code title=w rederive=0 after=02\n' \
    | state_set "$wsaw" slices ferry
  state_put "$wsaw" stage ferry "slice=01" "stage=turnover" "round=1" "attempt=1" \
    "state=done" "nonce=nAW" "spawn_t=1"
  state_append "$wsaw" handoff session \
    "v=1 t=10 slice=01 stage=turnover attempt=1 round=1 nonce=nAW verdict=done confidence=HIGH refine.rounds=1" ) > /dev/null
out=$(bash -c "set +u; . '$hf' '$wsaw' > /dev/null 2>&1; load_position; do_advance" 2>&1); rc=$?
[ $rc -eq 20 ] \
  && ok "advance parks (rc=20) instead of walking to close-out over a wedged pending" \
  || bad "rc=$rc, want 20 — a wedged index silently completed the topic"
[ "$( . "$RS/lib/state.sh"; state_field "$wsaw" halt reason 2>/dev/null)" = "stall_record" ] \
  && ok "park reason stall_record (index integrity, not a liveness class)" \
  || bad "reason: $( . "$RS/lib/state.sh"; state_field "$wsaw" halt reason 2>/dev/null)"
printf '%s' "$out" | command grep -q "schedulable" \
  && ok "the park says why nothing can run" || bad "detail: $out"

echo "-- ingest stores after=, and the emit-refused shapes park at this door too --"
( . "$RS/lib/state.sh"; printf 'id=99 status=done risk=low repo=code title=seed rederive=0\n' \
    | state_set "$ws" slices ferry ) > /dev/null
( set +u; . "$hf" "$ws" > /dev/null 2>&1; ingest_slices "09:low:code:first;10:med:doc:second:after=09" )
idx=$(state_get "$ws" slices)
printf '%s\n' "$idx" | command grep -E "(^| )id=10( |$)" | command grep -q "after=09" \
  && ok "the ingested row carries after=09 (the scheduler's input)" \
  || bad "id=10 row: $(printf '%s\n' "$idx" | command grep 'id=10')"
printf '%s\n' "$idx" | command grep -E "(^| )id=10( |$)" | command grep -q "repo=doc" \
  && ok "the after tail did not disturb the 4-field parse (repo=doc intact)" \
  || bad "id=10 row: $(printf '%s\n' "$idx" | command grep 'id=10')"
assert_rc 20 "a forward after parks at ingest (both doors, one derivation)" -- \
  bash -c "set +u; . '$hf' '$ws' > /dev/null 2>&1; ingest_slices '11:low:code:x:after=12;12:low:code:y'"
assert_rc 20 "a malformed after tail parks at ingest instead of folding into the title" -- \
  bash -c "set +u; . '$hf' '$ws' > /dev/null 2>&1; ingest_slices '11:low:code:x:after=9'"

echo "-- split grammar id:risk:repo:title — the slice's repo binding is cast at ingest --"
( . "$RS/lib/state.sh"; printf '' | state_set "$ws" slices ferry ) > /dev/null
( set +u; . "$hf" "$ws" > /dev/null 2>&1; ingest_slices "01:low:code:a;02:med:doc:b" )
idx=$(state_get "$ws" slices)
printf '%s\n' "$idx" | command grep -E "(^| )id=01( |$)" | command grep -q "repo=code" \
  && ok "a code-bound slice lands with repo=code" || bad "id=01: $(printf '%s\n' "$idx" | command grep 'id=01')"
printf '%s\n' "$idx" | command grep -E "(^| )id=02( |$)" | command grep -q "repo=doc" \
  && ok "a doc-bound slice lands with repo=doc (the index is the binding's home)" \
  || bad "id=02: $(printf '%s\n' "$idx" | command grep 'id=02')"
assert_rc 20 "a THREE-field segment parks stall_record (the old grammar is not a compatibility path)" -- \
  bash -c "set +u; . '$hf' '$ws' > /dev/null 2>&1; ingest_slices '03:low:c'"
assert_out_has "id:risk:repo:title" "the park names the grammar"
assert_rc 20 "a repo word outside {code,doc} parks (closed vocabulary)" -- \
  bash -c "set +u; . '$hf' '$ws' > /dev/null 2>&1; ingest_slices '03:low:wiki:c'"
echo "-- both doors judge the SAME declaration the same way (one derivation, no drift) --"
# The emit regex anchors the whole field, so it refuses an empty segment; a
# per-segment loop that skips empties would accept the same string. Two
# hand-written expressions of one grammar drift exactly here.
assert_rc 20 "a field with an empty segment parks at ingest, as it refuses at emit" -- \
  bash -c "set +u; . '$hf' '$ws' > /dev/null 2>&1; ingest_slices '08:low:code:a;;07:low:doc:b'"
[ "$(state_get "$ws" slices | command grep -cE '(^| )id=08( |$)')" = "0" ] \
  && ok "and nothing from that record reached the index" \
  || bad "a segment of the rejected record landed: $(state_get "$ws" slices | command grep 'id=08')"

echo "-- one id is one slice: a doubled id parks instead of writing two rows --"
# Two rows for one id is not just a dirty index: readers take the LAST match,
# so the second declaration silently decides the slice's checkout — the same
# harm the re-binding refusal exists to stop, reached through another door.
assert_rc 20 "a record declaring the same id twice parks stall_record" -- \
  bash -c "set +u; . '$hf' '$ws' > /dev/null 2>&1; ingest_slices '07:low:code:a;07:low:doc:b'"
assert_out_has "twice" "the park names the repeated id"
[ "$(state_get "$ws" slices | command grep -cE '(^| )id=07( |$)')" = "0" ] \
  && ok "and nothing was written for it (no duplicate row reached the index)" \
  || bad "duplicate rows landed: $(state_get "$ws" slices | command grep 'id=07' | tr '\n' ' ')"

echo "-- the binding is IMMUTABLE per id, and a re-binding attempt is never SILENT --"
# The standing row wins by construction; emit refuses this case in-session, so
# a record reaching THIS door bypassed emit (hand-written, or a store rollback
# — the drill's `direct` path proves that door is real). Same rule, one home.
assert_rc 20 "a record re-binding an existing id parks stall_record at ingest" -- \
  bash -c "set +u; . '$hf' '$ws' > /dev/null 2>&1; ingest_slices '01:low:doc:a;02:med:doc:b'"
assert_out_has "re-binds" "the park names what the record tried to do"
state_get "$ws" slices | command grep -E "(^| )id=01( |$)" | command grep -q "repo=code" \
  && ok "and the standing binding is untouched (a different binding needs a NEW id)" \
  || bad "binding mutated on re-split: $(state_get "$ws" slices | command grep 'id=01')"
echo "-- re-listing a RETIRED id parks: keeping its row silently means that work never runs --"
( . "$RS/lib/state.sh"
  printf 'id=01 status=active risk=low repo=code title=a rederive=0\nid=05 status=superseded risk=low repo=code title=retired rederive=0\n' \
    | state_set "$ws" slices ferry ) > /dev/null
assert_rc 20 "a record re-listing a superseded id parks stall_record" -- \
  bash -c "set +u; . '$hf' '$ws' > /dev/null 2>&1; ingest_slices '01:low:code:a;05:low:code:retired'"
assert_out_has "retired" "the park names why the id cannot come back"
assert_rc 20 "a record breaking TWO rules parks once" -- \
  bash -c "set +u; . '$hf' '$ws' > /dev/null 2>&1; ingest_slices '05:low:code:retired;07:low:code:x;07:low:doc:y'"
assert_out_has "retired" "…and the park carries the retired reason…"
assert_out_has "declared twice" "…AND the duplicate one (the door hands over the whole list, never just the first)"
state_get "$ws" slices | command grep -E "(^| )id=05( |$)" | command grep -q "status=superseded" \
  && ok "the retired row is untouched (a new id is the only way back into the schedule)" \
  || bad "id=05: $(state_get "$ws" slices | command grep 'id=05')"

echo "-- the row's HUMAN-FACING fields (risk, title) are audited, not parked --"
# The declared row has four fields and they split cleanly: id and repo steer
# the machine (dropping a re-declaration of those is refused above), while risk
# and title are human-facing copies with no machine reader — dropping those
# changes nothing mechanically, so the only defect is the silence.
( . "$RS/lib/state.sh"
  printf 'id=01 status=active risk=low repo=code title=a rederive=0\nid=02 status=pending risk=med repo=doc title=b rederive=0\n' \
    | state_set "$ws" slices ferry ) > /dev/null
rm -f "$ws/.runtime/state/audit"
( set +u; . "$hf" "$ws" > /dev/null 2>&1; ingest_slices "01:high:code:a;02:med:doc:renamed" )
state_get "$ws" slices | command grep -E "(^| )id=01( |$)" | command grep -q "risk=low" \
  && ok "the standing risk holds (re-listed rows are never rewritten)" \
  || bad "risk mutated: $(state_get "$ws" slices | command grep 'id=01')"
state_get "$ws" audit 2>/dev/null | command grep -q "risk=low->high" \
  && ok "a dropped RISK re-declaration is visible in the audit surface, not silent" \
  || bad "risk re-declaration vanished without a trace"
state_get "$ws" audit 2>/dev/null | command grep -q "title=b->renamed" \
  && ok "a dropped TITLE re-declaration is too (same class, same treatment — the family is closed)" \
  || bad "title re-declaration vanished without a trace: $(state_get "$ws" audit 2>/dev/null | command grep 're-declared' | tr '\n' ' ')"
n=$(state_get "$ws" audit 2>/dev/null | command grep -c "re-declared slice" || true)
[ "${n:-0}" = "2" ] \
  && ok "one audit line per re-declared slice, naming only the fields that actually changed" \
  || bad "expected 2 audit lines (one per slice), saw ${n:-0}"

echo "-- ingest_slices: supersede omitted, preserve done/cancelled, keep re-listed --"
( . "$RS/lib/state.sh"
  printf 'id=01 status=active risk=low repo=code title=a rederive=0\nid=02 status=done risk=low repo=code title=b rederive=0\nid=03 status=cancelled risk=low repo=code title=c rederive=0\n' \
    | state_set "$ws" slices ferry ) > /dev/null
( set +u; . "$hf" "$ws" > /dev/null 2>&1; ingest_slices "01:low:code:a;04:high:code:merged" )
idx=$(state_get "$ws" slices)
printf '%s\n' "$idx" | command grep "id=01" | command grep -q "status=active" \
  && ok "re-listed id keeps its existing row (status preserved)" \
  || bad "id=01 row mangled: $(printf '%s\n' "$idx" | command grep 'id=01')"
printf '%s\n' "$idx" | command grep "id=02" | command grep -q "status=done" \
  && ok "done id omitted from the new list stays done (history preserved)" \
  || bad "id=02: $(printf '%s\n' "$idx" | command grep 'id=02')"
printf '%s\n' "$idx" | command grep "id=03" | command grep -q "status=cancelled" \
  && ok "cancelled id stays cancelled" \
  || bad "id=03: $(printf '%s\n' "$idx" | command grep 'id=03')"
printf '%s\n' "$idx" | command grep "id=04" | command grep -q "status=pending" \
  && ok "newly minted id enters pending" \
  || bad "id=04 missing: $idx"
( . "$RS/lib/state.sh"
  printf 'id=05 status=active risk=low repo=code title=e rederive=0\n' | state_set "$ws" slices ferry ) > /dev/null
( set +u; . "$hf" "$ws" > /dev/null 2>&1; ingest_slices "06:low:code:f" )
state_get "$ws" slices | command grep "id=05" | command grep -q "status=superseded" \
  && ok "an active id omitted from the new list is superseded (never silently dropped)" \
  || bad "id=05 not superseded: $(state_get "$ws" slices | command grep 'id=05')"

echo "-- ingest_slices: an empty slices field parks instead of writing an empty index --"
assert_rc 20 "ingest of an empty slices field parks stall_record (silent no-op topic excluded)" -- \
  bash -c "set +u; . '$hf' '$ws' > /dev/null 2>&1; ingest_slices ''"

echo "-- reslice declined (split-check concur): the proposing slice closes, never strands --"
# turnover(reslice) leaves the proposer ACTIVE (only next_slice marks done);
# split-check concur = proposal declined, standing index holds. Without an
# explicit disposition the proposer is stranded: next_pending_slice schedules
# only pending, and close-out meets an undisposed active row.
wsr=$(mk_full_ws "$base" reslicedecl "$repo" "$branch")
( . "$RS/lib/state.sh"
  printf 'id=01 status=active risk=low title=a rederive=0\n' | state_set "$wsr" slices ferry
  state_put "$wsr" attempts ferry "reslice_from=01"
  state_put "$wsr" stage ferry "slice=00" "stage=split-check" "round=1" "attempt=1" \
    "state=done" "nonce=nRC" "spawn_t=1"
  state_append "$wsr" handoff session \
    "v=1 t=10 slice=00 stage=split-check attempt=1 round=1 nonce=nRC verdict=concur confidence=HIGH findings.substantive=0 findings.wording=0" ) > /dev/null
mk_artifact "$wsr/slices/00/splitcheck.1.md" "split-check review" claims
bash -c "set +u; . '$hf' '$wsr' > /dev/null 2>&1; load_position; do_advance" > /dev/null 2>&1
state_get "$wsr" slices 2>/dev/null | command grep -E "(^| )id=01( |$)" | command grep -q "status=done" \
  && ok "declined proposer marked done (its turnover completed; declining closes it)" \
  || bad "proposer slice stranded: $(state_get "$wsr" slices 2>/dev/null | command grep 'id=01')"
[ -z "$(state_field "$wsr" attempts reslice_from 2>/dev/null)" ] \
  && ok "reslice pointer discharged" || bad "reslice_from still set"

echo "-- the slices_index ledger row carries the class=A decision count, ahead of slices= --"
# Measured: a 64-minute round left the index
# byte-identical and produced 00/DP-2 — a re-binding of which cases land in
# which slice's first commit, one level below what id:risk:repo:title:after can
# encode. The count is what lets a later reader tell that round from an empty
# one. It is written BEFORE slices= because the fixpoint strips a known PREFIX
# to get the index bytes; behind slices= it would enter the identity comparison
# and silently disarm the fixpoint (measured: that mutation survives every arm
# in 46-convergence, whose ledger rows are hand-built and never go through here).
wsd=$(mk_full_ws "$base" ingestdec "$repo" "$branch")
IDXD='01:low:code:relocate the substrate;02:med:code:release-set guard'
( . "$RS/lib/state.sh"
  state_append "$wsd" decisions session "v=1 t=1 slice=00 dp=00/DP-1 class=A status=pending_audit text=first" ) > /dev/null
bash -c "set +u; . '$hf' '$wsd' > /dev/null 2>&1; ingest_slices '$IDXD'" > /dev/null 2>&1
row=$(state_get "$wsd" ledger 2>/dev/null | command grep -F 'event=slices_index' | tail -1)
case "$row" in
  *"decisions=1 slices="*) ok "the emit records decisions=1 (the class=A rows on the surface), immediately before slices=" ;;
  *) bad "row does not carry decisions= ahead of slices=: $row" ;;
esac
# the count must TRACK the surface, not be a constant.
( . "$RS/lib/state.sh"
  state_append "$wsd" decisions session "v=1 t=2 slice=00 dp=00/DP-2 class=A status=pending_audit text=second"
  state_append "$wsd" decisions session "v=1 t=3 slice=00 dp=00/DP-3 class=U status=pending_audit text=not counted" ) > /dev/null
bash -c "set +u; . '$hf' '$wsd' > /dev/null 2>&1; ingest_slices '$IDXD'" > /dev/null 2>&1
row=$(state_get "$wsd" ledger 2>/dev/null | command grep -F 'event=slices_index' | tail -1)
case "$row" in
  *"decisions=2 slices="*) ok "…and it tracks the surface and counts class=A only (a class=U row does not move it)" ;;
  *) bad "count did not track the decisions surface (want 2, class=U excluded): $row" ;;
esac
# THE COMPOSITION, which is the whole reason for the field order: two emits of
# the SAME cut with DIFFERENT counts must still read as a fixpoint. If the
# count ever entered the comparison, the guard against a 13-round prose loop
# would quietly stop firing and nothing else in the suite would notice.
rows=$(state_get "$wsd" ledger 2>/dev/null | command grep -F 'event=slices_index' | tail -2)
d=$(printf '%s\n' "$rows" | sed -e 's/^v=1 t=[0-9]* //' -e 's/^event=slices_index //' -e 's/^decisions=[0-9]* //' | sort -u | command grep -c .)
[ "$d" = "1" ] \
  && ok "two emits of the same cut with counts 1 and 2 are still ONE distinct index (the field is read, never compared)" \
  || bad "the decisions count entered the identity comparison — the fixpoint is disarmed ($d distinct from 2 identical cuts)"


echo "-- a HAND retirement outranks mechanical progress (cancel of the active slice) --"
# Measured before the guard existed: the operator cancelled the ACTIVE slice,
# enter_stage's unconditional `active` write put the row back one stage later,
# and the slice boundary then marked it `done`. The cancel was erased and the
# operator's own audit line still said it happened.
wsc=$(mk_full_ws "$base" cancelactive "$repo" "$branch")
( . "$RS/lib/state.sh"
  printf 'id=01 status=done risk=low repo=code title=a rederive=0\nid=02 status=active risk=low repo=code title=b rederive=0\nid=03 status=pending risk=low repo=code title=c rederive=0\n' \
    | state_set "$wsc" slices ferry ) > /dev/null
"$RS/launch.sh" slice "$wsc" 02 cancelled > /dev/null 2>&1
( set +u; . "$hf" "$wsc" > /dev/null 2>&1; slices_set_status 02 active ) > /dev/null 2>&1
st=$(state_get "$wsc" slices 2>/dev/null | command grep -E "(^| )id=02( |$)")
case "$st" in *status=cancelled*) ok "the ferry's \`active\` write cannot resurrect a cancelled slice" ;;
  *) bad "cancel ERASED by a mechanical write: $st" ;; esac
( set +u; . "$hf" "$wsc" > /dev/null 2>&1; slices_set_status 02 done ) > /dev/null 2>&1
st=$(state_get "$wsc" slices 2>/dev/null | command grep -E "(^| )id=02( |$)")
case "$st" in *status=cancelled*) ok "nor can the slice boundary mark it done (a cancelled slice is not completed work)" ;;
  *) bad "cancelled slice marked done: $st" ;; esac
state_get "$wsc" audit 2>/dev/null | command grep -q "retired by hand" \
  && ok "the refusal is audited by name, so a silent no-op is distinguishable from a write" \
  || bad "the refusal wrote nothing to the audit surface"
# the floor: the guard must not swallow the writes it exists to allow.
( set +u; . "$hf" "$wsc" > /dev/null 2>&1; slices_set_status 03 active ) > /dev/null 2>&1
state_get "$wsc" slices 2>/dev/null | command grep -E "(^| )id=03( |$)" | command grep -q 'status=active' \
  && ok "a NON-retired row still takes the mechanical write (the guard is not a blanket refusal)" \
  || bad "the guard blocked a legitimate write on a pending row"

echo "-- the two status SETS answer different questions and must not be unified --"
# ingest_slices preserves done|cancelled|superseded ("what may a re-split not
# resurrect"); the retired pair is cancelled|superseded ("what may mechanical
# progress not overwrite"). `done` is the discriminator: the ferry writes it
# itself, so folding the sets together would make the slice boundary unable to
# close a slice. The same lesson as two drifting filter predicates, one level up.
rset=$( ( set +u; . "$hf" "$wsc" > /dev/null 2>&1; printf '%s' "$SLICE_RETIRED_STATUSES" ) )
[ "$rset" = "cancelled superseded" ] \
  && ok "SLICE_RETIRED_STATUSES is exactly cancelled+superseded (done is NOT retired)" \
  || bad "the retired set drifted to '$rset' — if done joined it, no slice can ever be closed"
command grep -q 'status=done\*|\*status=cancelled\*|\*status=superseded\*' "$RS/lib/index.sh" \
  && ok "ingest's own preserve list still names all three (the sets are stated apart, on purpose)" \
  || bad "ingest_slices' preserve list changed shape — re-read whether it still preserves done"

echo "-- the held slice retired under the ferry's feet: reroute, never erase --"
wsr2=$(mk_full_ws "$base" rerouteheld "$repo" "$branch")
( . "$RS/lib/state.sh"
  printf 'id=02 status=cancelled risk=low repo=code title=b rederive=0\nid=03 status=pending risk=low repo=code title=c rederive=0\n' \
    | state_set "$wsr2" slices ferry
  state_put "$wsr2" stage ferry "slice=02" "stage=impl" "round=1" "attempt=1" "state=failed" "nonce=n1" "spawn_t=1" ) > /dev/null
out=$(bash -c "set +u; . '$hf' '$wsr2' > /dev/null 2>&1; load_position; reroute_if_slice_retired; echo rc=\$?" 2>&1 | tail -1)
[ "$out" = "rc=0" ] && ok "a held slice that is cancelled triggers the reroute (rc 0 = it acted)" \
  || bad "the reroute did not fire on a cancelled held slice: $out"
[ "$(state_field "$wsr2" stage slice 2>/dev/null)" = "03" ] \
  && ok "…and the pointer lands on the next schedulable slice, not on the cancelled one" \
  || bad "pointer is '$(state_field "$wsr2" stage slice 2>/dev/null)', want 03"
state_get "$wsr2" slices 2>/dev/null | command grep -E "(^| )id=02( |$)" | command grep -q 'status=cancelled' \
  && ok "…and the cancelled slice is still cancelled (the reroute marks nothing done)" \
  || bad "the reroute disposed the cancelled slice: $(state_get "$wsr2" slices | command grep 'id=02')"
state_get "$wsr2" ledger 2>/dev/null | command grep -q 'event=slice_retired' \
  && ok "the reroute is on the ledger, so a run's history shows why the slice changed" \
  || bad "the reroute left no ledger row"

# BOTH floors: the guard must not fire on a healthy run, nor mid-attempt.
wsr3=$(mk_full_ws "$base" rerouteneg "$repo" "$branch")
( . "$RS/lib/state.sh"
  printf 'id=02 status=active risk=low repo=code title=b rederive=0\nid=03 status=pending risk=low repo=code title=c rederive=0\n' \
    | state_set "$wsr3" slices ferry
  state_put "$wsr3" stage ferry "slice=02" "stage=impl" "round=1" "attempt=1" "state=failed" "nonce=n1" "spawn_t=1" ) > /dev/null
out=$(bash -c "set +u; . '$hf' '$wsr3' > /dev/null 2>&1; load_position; reroute_if_slice_retired; echo rc=\$?" 2>&1 | tail -1)
[ "$out" = "rc=1" ] && ok "known-bad floor: an ACTIVE held slice does not trigger it (rc 1 = it declined)" \
  || bad "the reroute fired on a healthy active slice: $out"
( . "$RS/lib/state.sh"
  printf 'id=02 status=cancelled risk=low repo=code title=b rederive=0\nid=03 status=pending risk=low repo=code title=c rederive=0\n' \
    | state_set "$wsr3" slices ferry
  state_put "$wsr3" stage ferry "state=running" ) > /dev/null
out=$(bash -c "set +u; . '$hf' '$wsr3' > /dev/null 2>&1; load_position; reroute_if_slice_retired; echo rc=\$?" 2>&1 | tail -1)
[ "$out" = "rc=1" ] && ok "known-bad floor: a cancelled slice mid-ATTEMPT does not trigger it either (a live attempt is 'launch.sh stop', never this)" \
  || bad "the reroute killed a live attempt: $out"

echo "-- the operator is told what cancelling the HELD slice will do --"
out=$("$RS/launch.sh" slice "$wsr3" 03 cancelled 2>&1)
# glob, not `printf | grep -q`: this arm reads GREEN on failure, and a SIGPIPE
# 141 from the producer would report the regression absent (R19 / VD-76).
case "$out" in
  *"note:"*) bad "the note fired for a slice the ferry is NOT holding (pointer is 02): $out" ;;
  *) ok "no note when the cancelled slice is not the held one (the note is not boilerplate)" ;;
esac
( . "$RS/lib/state.sh"; state_put "$wsr3" stage ferry "slice=03" ) > /dev/null
( . "$RS/lib/state.sh"
  printf 'id=02 status=cancelled risk=low repo=code title=b rederive=0\nid=03 status=pending risk=low repo=code title=c rederive=0\n' \
    | state_set "$wsr3" slices ferry ) > /dev/null
out=$("$RS/launch.sh" slice "$wsr3" 03 cancelled 2>&1)
case "$out" in
  *"BETWEEN attempts"*) ok "cancelling the HELD slice says when it takes effect and that a live attempt is not killed" ;;
  *) bad "no note on cancelling the held slice: $out" ;;
esac


echo "-- slices_set_status: a CORRUPT index is a store fault, never a silent drop --"
( . "$RS/lib/state.sh"
  printf 'id=01 status=active risk=low title=a rederive=0\n' | state_set "$ws" slices ferry ) > /dev/null
corrupt_surface "$ws" slices
out=$(bash -c "set +u; . '$hf' '$ws' > /dev/null 2>&1; slices_set_status 01 done" 2>&1); rc=$?
[ $rc -eq 30 ] && ok "corrupt slices surface faults (rc=30, the ferry's store-fault exit), status update not dropped" \
  || bad "rc=$rc — a corrupt index silently swallowed the status update (fault read as absent)"
printf '%s' "$out" | command grep -qi "fault\|corrupt" \
  && ok "the fault names itself" || bad "silent: '$out'"

check_done
