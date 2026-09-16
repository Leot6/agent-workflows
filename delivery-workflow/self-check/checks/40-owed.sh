#!/usr/bin/env bash
# 40-owed — lib/owed.sh, the ONE owed-set derivation: cu-table parse, @cu
# completeness against the progress surface + a scratch git repo, empty-cu-list
# surfaced, and the single-list property (record.sh's emit refusal lists
# exactly what owed_check derives — one list, by construction and by test).
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/fixtures/lib.sh"
. "$RS/lib/state.sh"
. "$RS/lib/owed.sh"
. "$RS/lib/gates.sh"   # owed_spec_cus strips fences via _gates_strip_fences —
                       # both real callers source gates alongside owed

base=$(sc_tmpdir)
read -r repo branch < <(mk_repo "$base/repo")
ws=$(mk_ws "$base" owedtopic "$repo" "$branch")

echo "-- cu table parse (| cu-N | rows) --"
mk_spec "$ws" 01 2
precond "fixture spec exists with cu rows" \
  bash -c 'command grep -qE "^\| cu-2 \|" "$1"' _ "$ws/slices/01/spec.md"
assert_rc 0 "owed_spec_cus parses the table" -- owed_spec_cus "$ws" 01
[ "$(owed_spec_cus "$ws" 01 | paste -sd, -)" = "1,2" ] \
  && ok "cu ids extracted in order: 1,2" || bad "cu parse wrong: $(owed_spec_cus "$ws" 01 | paste -sd, -)"
[ "$(owed_cu_total "$ws" 01)" = "2" ] && ok "owed_cu_total = 2" || bad "cu total wrong"
echo "| cu-x | not a unit |" >> "$ws/slices/01/spec.md"
[ "$(owed_cu_total "$ws" 01)" = "2" ] \
  && ok "non-numeric pseudo-row ignored (parse is anchored on cu-<N>)" \
  || bad "cu parse picked up a malformed row"

echo "-- derivation: static column ⊕ @cu expansion --"
d=$(owed_derive "$ws" impl 01 | paste -sd, -)
[ "$d" = "cu.1,cu.2,dispatch,conformance.md,handoff" ] \
  && ok "impl owed set = $d" || bad "impl owed set wrong: $d"
d=$(owed_derive "$ws" spec 01 | paste -sd, -)
[ "$d" = "spec.md,handoff" ] && ok "spec owed set = $d" || bad "spec owed set wrong: $d"
rm -f "$ws/slices/01/spec.md"
d=$(owed_derive "$ws" impl 01 | paste -sd, -)
printf '%s' "$d" | command grep -q '@cu-list' \
  && ok "empty commit-unit list is itself a distinguished miss (@cu-list)" \
  || bad "missing spec did not surface @cu-list: $d"
mk_spec "$ws" 01 2

echo "-- @cu completeness vs progress surface + git log --"
assert_rc 1 "no progress record -> cu.1 missing, self-describing" -- \
  owed_check "$ws" impl 01 --skip handoff
assert_out_has "no progress-surface record for cu.1" "reason names the surface and the duty"
precond "the refusal covered N>0 owed items (both cus listed)" \
  bash -c 'printf "%s" "$1" | command grep -q "cu.2"' _ "$SC_OUT"
state_append "$ws" progress session "v=1 t=1 slice=01 cu=1 sha=deadbeefdeadbeef subject=x" > /dev/null
state_append "$ws" progress session "v=1 t=1 slice=01 cu=2 sha=deadbeefdeadbeef subject=x" > /dev/null
assert_rc 1 "progress SHA that resolves nowhere in git -> still missing" -- \
  owed_check "$ws" impl 01 --skip handoff
assert_out_has "does not resolve to a commit" "reason names the git failure"
echo work > "$repo/w.txt"; git -C "$repo" add w.txt
git -C "$repo" commit -qm "feat: unit one lands"
sha1=$(git -C "$repo" rev-parse HEAD)
state_append "$ws" progress session "v=1 t=2 slice=01 cu=1 sha=$sha1 subject=ok" > /dev/null
echo more > "$repo/w2.txt"; git -C "$repo" add w2.txt
git -C "$repo" commit -qm "feat: unit two lands"
sha2=$(git -C "$repo" rev-parse HEAD)
state_append "$ws" progress session "v=1 t=3 slice=01 cu=2 sha=$sha2 subject=ok" > /dev/null
mk_artifact "$ws/slices/01/conformance.md" conformance
# The dispatch as sent is an owed artifact of impl: a unit landed by a prompt
# nobody can read leaves a conformance record nobody can audit.
assert_rc 1 "landed SHAs + conformance but NO dispatch file -> impl still owes the dispatch" -- \
  owed_check "$ws" impl 01 --skip handoff
assert_out_has "dispatch:" "the miss names the artifact and where it lives"
assert_out_has "as sent" "and says what the file is — the prompt as sent, not a summary"
mkdir -p "$ws/slices/01"; : > "$ws/slices/01/dispatch.1.md"
assert_rc 1 "an EMPTY dispatch file is still a miss (a placeholder is not a dispatch)" -- \
  owed_check "$ws" impl 01 --skip handoff
mk_dispatch "$ws" 01
assert_rc 0 "landed SHAs + conformance + dispatch -> impl owed complete (good direction)" -- \
  owed_check "$ws" impl 01 --skip handoff
# a SHA that exists but is NOT an ancestor of the declared branch
git -C "$repo" checkout -qb side "$branch"~1 2>/dev/null || git -C "$repo" checkout -qb side HEAD~1
echo side > "$repo/s.txt"; git -C "$repo" add s.txt; git -C "$repo" commit -qm "feat: side branch work"
sideref=$(git -C "$repo" rev-parse HEAD)
git -C "$repo" checkout -q "$branch"
state_append "$ws" progress session "v=1 t=4 slice=01 cu=2 sha=$sideref subject=off-branch" > /dev/null
assert_rc 1 "a resolvable SHA off the declared branch is still a miss" -- \
  owed_check "$ws" impl 01 --skip handoff
assert_out_has "not in git log" "reason names the branch containment failure"
state_append "$ws" progress session "v=1 t=5 slice=01 cu=2 sha=$sha2 subject=back" > /dev/null
assert_rc 0 "last progress record wins; owed complete again" -- \
  owed_check "$ws" impl 01 --skip handoff

echo "-- handoff item + nonce addressing --"
assert_rc 1 "handoff owed and absent -> miss names (slice, stage)" -- \
  owed_check "$ws" impl 01
assert_out_has "no record for (slice=01 stage=impl)" "handoff miss self-describing"
state_append "$ws" handoff session "v=1 t=6 slice=01 stage=impl nonce=nA verdict=built confidence=HIGH" > /dev/null
assert_rc 0 "handoff record present -> complete" -- owed_check "$ws" impl 01
assert_rc 1 "nonce-addressed check misses on a foreign nonce" -- \
  owed_check "$ws" impl 01 --nonce nZ
assert_rc 0 "nonce-addressed check finds its own record" -- \
  owed_check "$ws" impl 01 --nonce nA

echo "-- store fault propagates as rc 3, never read as absent --"
corrupt_surface "$ws" progress
assert_rc 3 "corrupt progress surface -> owed_check rc 3 (fault != missing)" -- \
  owed_check "$ws" impl 01 --skip handoff
head -1 "$ws/.runtime/state/progress" > "$ws/.runtime/state/progress.fix" \
  && rm -f "$ws/.runtime/state/progress"* # clear the corrupted surface entirely
state_append "$ws" progress session "v=1 t=9 slice=01 cu=1 sha=$sha1 subject=r" > /dev/null
state_append "$ws" progress session "v=1 t=9 slice=01 cu=2 sha=$sha2 subject=r" > /dev/null

echo "-- single-list property: record.sh refusal == owed_check derivation --"
rm -f "$ws/slices/01/conformance.md"
derived=$(owed_check "$ws" impl 01 --skip handoff; true)
precond "derivation lists exactly one miss (conformance.md)" \
  bash -c '[ "$(printf "%s\n" "$1" | command grep -c .)" = 1 ]' _ "$derived"
activate_stage "$ws" impl 01 1 nonce1
out=$("$RS/session/record.sh" emit "$ws" --stage impl --nonce nonce1 --verdict built \
      --confidence HIGH --refine-rounds 1 2>&1); rc=$?
[ $rc -eq 2 ] && ok "emit refuses while owed missing (rc 2)" || bad "emit rc=$rc, want 2"
refused=$(printf '%s\n' "$out" | sed -n 's/^  - //p')
[ "$refused" = "$derived" ] \
  && ok "refusal list is EXACTLY the owed_check derivation (one list): $refused" \
  || bad "single-list broken — refusal='$refused' vs derivation='$derived'"
mk_artifact "$ws/slices/01/conformance.md" conformance
out=$("$RS/session/record.sh" emit "$ws" --stage impl --nonce nonce1 --verdict built \
      --confidence HIGH --refine-rounds 1 2>&1); rc=$?
[ $rc -eq 0 ] && ok "same emit succeeds once the single list is satisfied" \
  || bad "emit still refused after fix: $out"

echo "-- an unresolvable branch tip names ITSELF, not a phantom missing SHA --"
wsb=$(mk_ws "$base" owedbadtip "$repo" "$branch")
sed -i 's/^branch=.*/branch=no-such-branch/' "$wsb/project.kv"
mkdir -p "$wsb/slices/01"
printf '| cu-1 | feat: x | - | no |\n' > "$wsb/slices/01/spec.md"
( . "$RS/lib/state.sh"
  state_append "$wsb" progress session "v=1 t=1 slice=01 stage=impl round=1 cu=1 sha=$(git -C "$repo" rev-parse HEAD)" ) > /dev/null
out=$(_owed_item_check "$wsb" impl 01 1 "" "" cu.1 2>&1); rc=$?
printf '%s' "$out" | command grep -qi "branch\|tip" \
  && ok "the error names the unresolvable tip (project.kv branch=no-such-branch)" \
  || bad "misleading error blames the SHA: '$out' — during a real topic this reads as lost work, not a config typo"

echo "-- binding dispatch: a doc slice's cu SHAs resolve in the DOC repo/branch --"
read -r drepo dbranch < <(mk_doc_repo "$base/docrepo")
wsd=$(mk_ws "$base" oweddoc "$repo" "$branch")
printf 'doc.repo=%s\ndoc.branch=%s\n' "$drepo" "$dbranch" >> "$wsd/project.kv"
mk_spec "$wsd" 02 1
mk_artifact "$wsd/slices/02/conformance.md" conformance
mk_dispatch "$wsd" 02
( cd "$drepo" && echo dd > dd.md && git add dd.md && git commit -qm "docs: land the doc unit" )
dsha=$(git -C "$drepo" rev-parse HEAD)
( . "$RS/lib/state.sh"
  state_append "$wsd" progress session "v=1 t=1 slice=02 stage=impl round=1 cu=1 sha=$dsha subject=doc" ) > /dev/null
precond "the doc SHA is absent from the CODE repo (else the check is vacuous)" \
  bash -c '! git -C "$1" rev-parse -q --verify "$2^{commit}" > /dev/null 2>&1' _ "$repo" "$dsha"
set_binding() { ( . "$RS/lib/state.sh"
  printf 'id=02 status=active risk=low repo=%s title=d rederive=0\n' "$1" | state_set "$wsd" slices ferry ) > /dev/null; }
set_binding doc
assert_rc 0 "a doc-bound slice's cu resolves against doc.repo + doc.branch" -- \
  owed_check "$wsd" impl 02 --skip handoff
set_binding code
assert_rc 1 "the SAME cu under a code binding is a miss (ancestry follows the binding, not a project default)" -- \
  owed_check "$wsd" impl 02 --skip handoff
assert_out_has "does not resolve to a commit" "the miss names the checkout it looked in"

echo "-- fenced cu rows are quoted data, not commit-units --"
# A spec quoting another spec's table (or giving an example) inside a code
# fence must not mint ghost CUs — the gates learned this lesson
# (_gates_strip_fences); the owed derivation reads the same document.
{ echo '```'; echo '| cu-9 | fenced example, not a unit | - | no |'; echo '```'; } \
  >> "$ws/slices/01/spec.md"
cus=$(bash -c ". '$RS/lib/state.sh'; . '$RS/lib/owed.sh'; . '$RS/lib/gates.sh'; owed_spec_cus '$ws' 01" | tr '\n' ',')
case ",$cus" in
  *,9,*) bad "ghost CU from a fenced example counted as owed: cus=$cus" ;;
  *) ok "fenced cu row ignored (cus=$cus)" ;;
esac

check_done
