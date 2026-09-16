#!/usr/bin/env bash
# 10-store — the atomic store (lib/state.sh): rc contract absent(1) /
# refused(2) / FAULT(3), fault ≠ absent, gen monotonic, named append
# rotation. Every direction two-sided; fixture preconditions asserted.
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/fixtures/lib.sh"
. "$RS/lib/state.sh"

base=$(sc_tmpdir)
ws="$base/ws"; mkdir -p "$ws"

echo "-- absent vs written (good direction baseline) --"
assert_rc 1 "state_get on a never-written surface is ABSENT (rc 1, not fault)" -- \
  state_get "$ws" run
assert_rc 1 "state_field on absent surface is rc 1" -- state_field "$ws" run topic
printf 'topic=alpha\nmode=full-auto\n' | state_set "$ws" run ferry
assert_rc 0 "state_set then state_get round-trips" -- state_get "$ws" run
assert_out_has "topic=alpha" "body preserved byte-for-byte"
assert_rc 0 "state_field finds a written key" -- state_field "$ws" run mode
assert_out_has "full-auto" "field value correct"
assert_rc 1 "state_field for a missing key on a present surface is rc 1" -- \
  state_field "$ws" run nosuchkey

echo "-- writer-class registry (refuse = rc 2) --"
assert_rc 2 "wrong writer class refused (run is ferry's, session denied)" -- \
  bash -c '. "$1/lib/state.sh"; printf "x=1\n" | state_set "$2" run session' _ "$RS" "$ws"
assert_out_has "writer class 'session' not allowed" "refusal is self-describing"
assert_rc 2 "unknown surface refused" -- \
  bash -c '. "$1/lib/state.sh"; printf "x=1\n" | state_set "$2" bogus ferry' _ "$RS" "$ws"
assert_rc 0 "audit surface accepts any writer" -- \
  state_append "$ws" audit watchdog "v=1 t=1 by=watchdog msg=x"
assert_rc 0 "right writer still accepted after refusals (non-vacuity)" -- \
  bash -c '. "$1/lib/state.sh"; printf "x=1\n" | state_set "$2" run ferry' _ "$RS" "$ws"

echo "-- gen monotonic --"
gen1=$(head -1 "$ws/.runtime/state/run" | command grep -oE 'gen=[0-9]+' | cut -d= -f2)
printf 'topic=alpha\nmode=full-auto\nn=3\n' | state_set "$ws" run ferry
gen2=$(head -1 "$ws/.runtime/state/run" | command grep -oE 'gen=[0-9]+' | cut -d= -f2)
precond "two generations observed" test -n "$gen1" -a -n "$gen2"
if [ "$gen2" -gt "$gen1" ]; then ok "generation increments on rewrite ($gen1 -> $gen2)"
else bad "generation not monotonic ($gen1 -> $gen2)"; fi

echo "-- fault (corrupt) != absent --"
precond "surface file exists before tampering" test -f "$ws/.runtime/state/run"
corrupt_surface "$ws" run
assert_rc 3 "checksum tamper reads as FAULT rc 3, never as absent/zero" -- \
  state_get "$ws" run
assert_out_has "checksum mismatch" "fault names the mismatch"
assert_rc 3 "state_field propagates the fault (rc 3, not rc 1)" -- \
  state_field "$ws" run topic
assert_rc 3 "a write over a corrupt surface refuses to bump gen (fault propagates)" -- \
  bash -c '. "$1/lib/state.sh"; printf "x=1\n" | state_set "$2" run ferry' _ "$RS" "$ws"
# distinguishability: same call shape, different rc for the two conditions
rm -rf "$ws/.runtime/state/stage" 2>/dev/null
assert_rc 1 "control: an absent surface still reads rc 1 while the corrupt one reads rc 3" -- \
  state_get "$ws" stage
# corrupt HEADER (not just body) is also fault
printf 'garbage header\nbody\n' > "$ws/.runtime/state/heartbeat"
assert_rc 3 "corrupt header is FAULT rc 3" -- state_get "$ws" heartbeat
assert_out_has "corrupt header" "header fault self-describing"
rm -f "$ws/.runtime/state/run" "$ws/.runtime/state/heartbeat"

echo "-- append surfaces + named rotation --"
assert_rc 2 "append on a set-surface (run) refused" -- \
  state_append "$ws" run ferry "v=1"
assert_rc 0 "append on ledger accepted" -- \
  state_append "$ws" ledger ferry "v=1 t=1 event=a"
state_append "$ws" ledger ferry "v=1 t=2 event=b" > /dev/null
assert_rc 0 "appended lines accumulate" -- state_get "$ws" ledger
assert_out_has "event=b" "second line present"
n=$(state_get "$ws" ledger | command grep -c .)
[ "$n" -eq 2 ] && ok "exactly 2 lines after 2 appends" || bad "expected 2 lines, got $n"
# rotation: build a surface at cap via state_set, then one append rotates it.
cap=$(_state_append_cap handoff)
precond "handoff append cap declared (N>0 candidate lines possible)" test "${cap:-0}" -gt 0
seq 1 "$cap" | sed 's/^/v=1 line=/' | state_set "$ws" handoff session
lines_before=$(state_get "$ws" handoff | command grep -c .)
precond "fixture surface is at the cap ($cap)" test "$lines_before" -eq "$cap"
assert_rc 0 "append at cap succeeds (rotates, never refuses)" -- \
  state_append "$ws" handoff session "v=1 line=overflow"
rot=$(ls "$ws/.runtime/state/handoff."*.rot 2>/dev/null | head -1)
if [ -n "$rot" ]; then ok "rotation file exists beside the surface: $(basename "$rot")"
else bad "no <surface>.<epoch>.rot file after cap exceedance"; fi
assert_rc 0 "post-rotation surface readable" -- state_get "$ws" handoff
assert_out_has "event=rotated" "rotation is NAMED in the new surface (never silent)"
assert_out_has "rotated_to=" "rotation record points at the rotated file"
assert_out_has "line=overflow" "the appended line survived the rotation"

echo "-- state_put upsert --"
state_put "$ws" stage ferry "slice=01" "stage=spec" > /dev/null
state_put "$ws" stage ferry "stage=precheck" > /dev/null
assert_rc 0 "put twice, read back" -- state_field "$ws" stage stage
assert_out_has "precheck" "last put wins"
assert_rc 0 "untouched key survives the upsert" -- state_field "$ws" stage slice
assert_rc 2 "state_put without key=value refused" -- \
  state_put "$ws" stage ferry "noequalsign"

echo "-- concurrent writers: appends are serialized, none lost --"
cws="$base/cws"; mkdir -p "$cws"
for i in $(seq 1 40); do
  bash "$RS/lib/state.sh" append "$cws" audit --writer ferry --line "v=1 i=$i" > /dev/null 2>&1 &
done
wait
stored=$(state_get "$cws" audit | command grep -c .)
[ "$stored" -eq 40 ] \
  && ok "40 concurrent appends -> 40 stored records (no lost update)" \
  || bad "40 concurrent appends -> only $stored stored — read-modify-write raced (lost update)"
gen=$(head -1 "$cws/.runtime/state/audit" | command grep -oE 'gen=[0-9]+' | cut -d= -f2)
[ "${gen:-0}" -eq 40 ] \
  && ok "generation counted every write (gen=40)" \
  || bad "generation is $gen after 40 appends — writes vanished"
bash "$RS/lib/state.sh" put "$cws" stage --writer ferry "a=1" > /dev/null 2>&1 &
bash "$RS/lib/state.sh" put "$cws" stage --writer ferry "b=2" > /dev/null 2>&1 &
wait
if state_field "$cws" stage a > /dev/null && state_field "$cws" stage b > /dev/null; then
  ok "two concurrent puts of different keys both survive"
else
  bad "a concurrent put lost the other's key: $(state_get "$cws" stage | tr '\n' ' ')"
fi

echo "-- reader surface markers (monitor renders fault as fault) --"
printf 'topic=beta\nmode=full-auto\nt_start=1\n' | state_set "$ws" run ferry
corrupt_surface "$ws" run
assert_rc 0 "monitor --once runs on a corrupt store" -- "$RS/monitor.sh" "$ws" --once
assert_out_has "STORE FAULT" "monitor shows FAULT, not 'not started' (fault != absent)"

echo "-- state_verify_all: the startup integrity sweep names every broken surface --"
vws="$base/vws"; mkdir -p "$vws"
assert_rc 0 "an absent store verifies clean" -- state_verify_all "$vws"
printf 'topic=v\n' | state_set "$vws" run ferry
state_append "$vws" ledger ferry "v=1 t=1 event=a" > /dev/null
assert_rc 0 "a clean store verifies clean (null control)" -- state_verify_all "$vws"
mkdir -p "$vws/.runtime/state/lock"                    # host-lock DIRECTORY
echo not-a-surface > "$vws/.runtime/state/ledger.111.rot"   # rotated segment
: > "$vws/.runtime/state/lock.reclaim"                 # the host lock's flock file
echo stray > "$vws/.runtime/state/notes.txt"           # unregistered stray
assert_rc 0 "only REGISTRY surfaces are judged — lock dir, lock.reclaim, *.rot and strays all skip (a dir-listing guess here killed every launch once)" -- \
  state_verify_all "$vws"
corrupt_surface "$vws" ledger
assert_rc 1 "a tampered surface fails the sweep (rc 1)" -- state_verify_all "$vws"
assert_out_has "surface 'ledger' FAULT" "the fault names the surface"
assert_out_has "tail -n +2" "and carries the repair recipe (reseal the header sum)"
corrupt_surface "$vws" run
n=$(state_verify_all "$vws" | command grep -c FAULT || true)
[ "$n" = "2" ] \
  && ok "every broken surface is named (2 tampered -> 2 fault lines), not first-hit-stop" \
  || bad "sweep reported $n fault line(s) for 2 tampered surfaces"

echo "-- state_audit: an append failure is LOUD on stderr, and still never fails the caller --"
# Pre-fix, '>/dev/null 2>&1 || true' swallowed everything: a corrupt audit
# surface ate every note with zero trace (the silent-append-loss class).
aws="$base/aws"; mkdir -p "$aws"
state_append "$aws" audit tester "v=1 t=1 by=t msg=seed" > /dev/null
corrupt_surface "$aws" audit
out=$(state_audit "$aws" tester "note that must not vanish" 2>&1); rc=$?
[ $rc -eq 0 ] && ok "state_audit still returns 0 (best-effort contract kept — callers never die on it)" \
  || bad "state_audit rc=$rc on a corrupt surface"
printf '%s' "$out" | command grep -q "audit append FAILED" \
  && ok "the loss is named on stderr (pre-fix: fully swallowed)" \
  || bad "audit append loss is still silent: '$out'"
printf '%s' "$out" | command grep -q "note that must not vanish" \
  && ok "the lost note text rides in the stderr line (recoverable from the log)" \
  || bad "lost note text absent from the failure line"

check_done
