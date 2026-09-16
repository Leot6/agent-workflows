#!/usr/bin/env bash
# 20-config — lib/config.sh: three-level precedence, fall-through, unknown-key
# fault naming the key, reviewer-effort floor, retired-slice-id fault,
# and the caps effective-value + source-layer naming (via lib/gates.sh _gates_cap).
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/fixtures/lib.sh"
. "$RS/lib/config.sh"

base=$(sc_tmpdir)
read -r repo branch < <(mk_repo "$base/repo")
ws=$(mk_ws "$base" cfgtopic "$repo" "$branch")

echo "-- three-level precedence (default -> topic -> slice) --"
assert_rc 0 "level 1: workflow default resolves with no topic files" -- \
  config_get slice.max_commits --topic-dir "$ws"
assert_out_has "8" "default value (defaults.kv slice.max_commits=8)"
echo "slice.max_commits=7" > "$ws/config/topic.kv"
assert_rc 0 "level 2: topic.kv overrides the default" -- \
  config_get slice.max_commits --topic-dir "$ws"
assert_out_has "7" "topic value wins over default"
mkdir -p "$ws/config"
echo "slice.max_commits=5" > "$ws/config/slice.01.author.kv"
assert_rc 0 "level 3: slice.<nn>.<agent>.kv wins over topic" -- \
  config_get slice.max_commits --topic-dir "$ws" --slice 01 --agent author
assert_out_has "5" "slice value most specific"
assert_rc 0 "--with-source names the winning layer" -- \
  config_get slice.max_commits --topic-dir "$ws" --slice 01 --agent author --with-source
assert_out_has "slice.01.author.kv" "source is the slice file"
assert_rc 0 "a different (slice,agent) address falls back to topic" -- \
  config_get slice.max_commits --topic-dir "$ws" --slice 02 --agent author
assert_out_has "7" "unaddressed slice sees the topic value"

echo "-- the operator layer (machine config, between defaults and topic) --"
# _CONFIG_USER_FILE is computed at config.sh SOURCE time from XDG_CONFIG_HOME,
# so the layer is exercised in a subprocess with its own XDG root — the same
# idiom the memo arm below uses for its scratch root. The layer's reason to
# exist: the machine's keys (the notify transport first of its class) outlive
# topics and must never be committed — measured, the first delivery topic's
# notify.cmd rode its topic.kv and died with the topic tree's cleanup, and the
# pilot topic never armed one because arming was per-topic toil.
ux="$base/uxdg"; mkdir -p "$ux/delivery-workflow"
printf 'slice.max_commits=6\n' > "$ux/delivery-workflow/config.kv"
# A workspace with NO topic layer yet: the only competition is default vs
# operator ($ws above already carries topic.kv slice.max_commits=7).
wsu=$(mk_ws "$base" cfguser "$repo" "$branch")
assert_rc 0 "operator config overrides the workflow default (8 → 6)" -- \
  env XDG_CONFIG_HOME="$ux" bash -c ". '$RS/lib/config.sh'; config_get slice.max_commits --topic-dir '$wsu'"
assert_out_has "6" "operator value beats the default with no topic layer"
assert_rc 0 "--with-source names the operator file (visible provenance)" -- \
  env XDG_CONFIG_HOME="$ux" bash -c ". '$RS/lib/config.sh'; config_get slice.max_commits --topic-dir '$wsu' --with-source"
assert_out_has "delivery-workflow/config.kv" "source is the operator layer's file"
echo "slice.max_commits=7" > "$wsu/config/topic.kv"
assert_rc 0 "topic.kv still overrides the operator layer (a topic may re-arm or silence itself)" -- \
  env XDG_CONFIG_HOME="$ux" bash -c ". '$RS/lib/config.sh'; config_get slice.max_commits --topic-dir '$wsu'"
assert_out_has "7" "topic value (7) beats operator (6)"
echo "slice.max_commits=5" > "$wsu/config/slice.01.author.kv"
assert_rc 0 "the slice layer still wins over all three" -- \
  env XDG_CONFIG_HOME="$ux" bash -c ". '$RS/lib/config.sh'; config_get slice.max_commits --topic-dir '$wsu' --slice 01 --agent author"
assert_out_has "5" "slice value (5) most specific, operator layer included"
printf 'slice.max_comits=6\n' > "$ux/delivery-workflow/config.kv"
assert_rc 3 "a typo'd key in the OPERATOR config FAULTS (the closed vocabulary binds the machine's file too)" -- \
  env XDG_CONFIG_HOME="$ux" bash -c ". '$RS/lib/config.sh'; config_get slice.max_commits --topic-dir '$wsu'"
assert_out_has "slice.max_comits" "the fault names the offending key"
assert_out_has "config.kv" "and the operator file it sits in"
printf 'agent.reviewer.effort=low\n' > "$ux/delivery-workflow/config.kv"
assert_rc 3 "rule.reviewer_effort_floor binds the operator layer (review depth is not reducible from the machine file)" -- \
  env XDG_CONFIG_HOME="$ux" bash -c ". '$RS/lib/config.sh'; config_get slice.max_commits --topic-dir '$wsu'"
assert_out_has "reviewer_effort_floor" "the cross-file rule faults, not a silent resolve"
printf 'slice.max_commits=6\n' > "$ux/delivery-workflow/config.kv"

echo "-- unset falls through; unset everywhere = rc 1, never an error --"
# Every scalar schema key carries a defaults.kv value by design (unset everywhere
# = workflow default); only wildcard-family keys can be truly unset.
assert_rc 1 "stage.* wildcard key unset everywhere is rc 1" -- \
  config_get stage.impl.timeout --topic-dir "$ws"
assert_rc 1 "second wildcard family (stage.*.budget_attempts) also rc 1" -- \
  config_get stage.spec.budget_attempts --topic-dir "$ws" --slice 01 --agent author
assert_rc 0 "an empty-valued default (notify.cmd=) resolves rc 0 empty, not an error" -- \
  config_get notify.cmd --topic-dir "$ws"

echo "-- unknown key faults, naming the key --"
assert_rc 2 "unknown key at get-time is refused, naming the vocabulary" -- \
  config_get totally.bogus.key --topic-dir "$ws"
assert_out_has "not in the closed vocabulary" "refusal points at schema.kv"
cp "$ws/config/topic.kv" "$ws/config/topic.kv.bak"
echo "slice.max_comits=9" >> "$ws/config/topic.kv"   # deliberate typo
assert_rc 3 "a typo'd key in a loaded file FAULTS (never silently defaults)" -- \
  config_get slice.max_commits --topic-dir "$ws"
assert_out_has "slice.max_comits" "the fault NAMES the offending key"
assert_out_has "topic.kv" "the fault names the offending file"
mv "$ws/config/topic.kv.bak" "$ws/config/topic.kv"
assert_rc 0 "clean file loads again (non-vacuity control)" -- \
  config_get slice.max_commits --topic-dir "$ws"
echo "-- type validation --"
d2=$(sc_tmpdir)
echo "liveness.poll=abc" > "$d2/bad.kv"
assert_rc 3 "int-typed key with non-int value faults" -- config_validate_file "$d2/bad.kv"
assert_out_has "liveness.poll" "type fault names the key"
echo "liveness.poll=30" > "$d2/good.kv"
assert_rc 0 "int-typed key with int value validates" -- config_validate_file "$d2/good.kv"
echo "agent.author.effort=extreme" > "$d2/bad2.kv"
assert_rc 3 "enum key outside its value set faults" -- config_validate_file "$d2/bad2.kv"

echo "-- reviewer-effort floor --"
echo "agent.reviewer.effort=low" > "$ws/config/topic.kv"
assert_rc 3 "topic reviewer effort below the run base effort faults" -- \
  config_get slice.max_commits --topic-dir "$ws"
assert_out_has "reviewer_effort_floor" "fault names the rule"
printf 'agent.author.effort=medium\nagent.reviewer.effort=high\n' > "$ws/config/topic.kv"
assert_rc 0 "reviewer >= base passes (good direction)" -- \
  config_get agent.reviewer.effort --topic-dir "$ws"
assert_out_has "high" "resolved reviewer effort"
echo "agent.reviewer.effort=medium" > "$ws/config/slice.01.reviewer.kv"
assert_rc 3 "slice layer reducing reviewer effort below topic level faults" -- \
  config_get agent.reviewer.effort --topic-dir "$ws" --slice 01 --agent reviewer
assert_out_has "slice override may never reduce review depth" "floor fault self-describing"
echo "agent.reviewer.effort=max" > "$ws/config/slice.01.reviewer.kv"
assert_rc 0 "slice layer raising reviewer effort passes" -- \
  config_get agent.reviewer.effort --topic-dir "$ws" --slice 01 --agent reviewer
assert_out_has "max" "raised value resolves"

echo "-- the floor compares WITHIN a model; across models it says so by name --"
# Measured: the rule refused a legitimate slice-level
# move to a STRONGER model one notch below its own ceiling (sonnet max vs opus
# xhigh — ranks 5 vs 4 on a ladder that is one shared vocabulary), and
# symmetrically accepted the inverse in silence. No cross-model ordering exists
# in this tree to ground a comparison, so the honest fix is the observation's own
# refutation reading: refuse only within a model, and across models print a
# NOTE (rc 0) rather than pass silently — a suppressed comparison must never
# read as a passed one.
# The NOTE prints on a COLD rules derivation only (clean verdicts are
# memoized; faults re-derive always), so these arms run in subshells with their
# own scratch TMPDIR — the same idiom the XDG layer arms use — because the
# memo dir persists across check runs and a warm memo would read as a missing
# note. Determinism is the check's own requirement, not the rule's.
fx="$base/floorx"; mkdir -p "$fx"
printf 'agent.author.effort=max\nagent.reviewer.effort=max\nagent.author.model=sonnet[1m]\nagent.reviewer.model=sonnet[1m]\n' > "$ws/config/topic.kv"
printf 'agent.reviewer.model=opus\nagent.reviewer.effort=xhigh\n' > "$ws/config/slice.01.reviewer.kv"
assert_rc 0 "THE MEASURED INSTANCE resolves: a slice reviewer moved to a stronger model one notch below its own ceiling is no fault" -- \
  env TMPDIR="$fx" bash -c ". '$RS/lib/config.sh'; config_get agent.reviewer.effort --topic-dir '$ws' --slice 01 --agent reviewer"
assert_out_has "not comparable across models" "the NOTE names what the rule cannot ground, rather than passing in silence"
rm -rf "$fx"; mkdir -p "$fx"
printf 'agent.reviewer.model=weak-model\nagent.reviewer.effort=max\n' > "$ws/config/slice.01.reviewer.kv"
assert_rc 0 "…and the INVERSE is equally no fault — a weaker reviewer model at max passes only because the rule says nothing across models" -- \
  env TMPDIR="$fx" bash -c ". '$RS/lib/config.sh'; config_get agent.reviewer.effort --topic-dir '$ws' --slice 01 --agent reviewer"
assert_out_has "NOTE: rule.reviewer_effort_floor" "the inverse carries the SAME note: the blindness is named in the direction it protects, never silent"
printf 'agent.reviewer.effort=low\n' > "$ws/config/slice.01.reviewer.kv"
assert_rc 3 "a same-model slice reduction still faults — the within-model half is unchanged (faults re-derive, no scratch needed)" -- \
  config_get agent.reviewer.effort --topic-dir "$ws" --slice 01 --agent reviewer
assert_out_has "slice override may never reduce review depth" "the fault is the floor's own, unchanged"
rm -rf "$fx"; mkdir -p "$fx"
printf 'agent.author.effort=max\nagent.reviewer.effort=low\nagent.author.model=sonnet[1m]\nagent.reviewer.model=opus\n' > "$ws/config/topic.kv"
rm -f "$ws/config/slice.01.reviewer.kv"
assert_rc 0 "a cross-model TOPIC pairing (author sonnet max, reviewer opus low) is no fault either — the topic clause is within-model too" -- \
  env TMPDIR="$fx" bash -c ". '$RS/lib/config.sh'; config_get agent.reviewer.effort --topic-dir '$ws'"
assert_out_has "author model 'sonnet[1m]' and reviewer model 'opus' differ" "and its note names both models at the topic layer"

echo "-- retired-slice-id fault --"
( . "$RS/lib/state.sh"
  printf 'id=07 status=superseded risk=low title=old rederive=0\nid=08 status=pending risk=low title=new rederive=0\n' \
    | state_set "$ws" slices ferry ) > /dev/null
precond "slices index fixture holds a superseded id" \
  bash -c '. "$1/lib/state.sh"; state_get "$2" slices | command grep -q "id=07 status=superseded"' _ "$RS" "$ws"
echo "agent.author.model=other" > "$ws/config/slice.07.author.kv"
assert_rc 3 "override addressing a superseded slice id faults loudly" -- \
  config_get agent.author.model --topic-dir "$ws" --slice 07 --agent author
assert_out_has "retired_slice_id" "fault names the rule"
assert_out_has "slice 07" "fault names the retired id"
echo "agent.author.model=other" > "$ws/config/slice.08.author.kv"
assert_rc 0 "override addressing a live slice id resolves (good direction)" -- \
  config_get agent.author.model --topic-dir "$ws" --slice 08 --agent author
assert_out_has "other" "live-slice override effective"
# The rules are memoized per input content, and the slices INDEX is one of the
# inputs (rule.retired_slice_id reads it): a memo keyed on the kv files alone
# would serve this clean verdict after the index retired the id. Same files,
# changed index, must fault.
( . "$RS/lib/state.sh"
  printf 'id=07 status=superseded risk=low title=old rederive=0\nid=08 status=superseded risk=low title=new rederive=0\n' \
    | state_set "$ws" slices ferry ) > /dev/null
assert_rc 3 "the SAME override faults once the index retires its id (the rules memo is keyed on the index too)" -- \
  config_get agent.author.model --topic-dir "$ws" --slice 08 --agent author
assert_out_has "slice 08" "and names the newly retired id"

echo "-- caps: effective value + source layer (via gates helper) --"
. "$RS/lib/gates.sh"
assert_rc 0 "cap from workflow defaults names defaults.kv as source" -- \
  _gates_cap "$ws" cap.source_file
assert_out_has "800" "default cap value"
assert_out_has "defaults.kv" "source layer named"
echo "cap.source_file=850" > "$ws/config/topic.kv"
assert_rc 0 "topic override moves the effective cap" -- _gates_cap "$ws" cap.source_file
assert_out_has "850" "topic-level effective value"
assert_out_has "topic.kv" "topic source layer named"
echo "cap.source_file=10" >> "$ws/project.kv"
assert_rc 0 "project.kv same-named key overrides the config chain (either direction)" -- \
  _gates_cap "$ws" cap.source_file
assert_out_has "10" "project effective value (tightening allowed)"
assert_out_has "project.kv" "project source layer named"
printf '' > "$ws/config/topic.kv"

echo "-- project adapter --"
assert_rc 0 "project_get reads project.kv" -- project_get "$ws" repo
assert_out_has "$repo" "repo path resolves"
assert_rc 2 "missing project.kv refuses self-describing" -- \
  project_get "$base" repo
assert_out_has "project adapter is required" "refusal explains the requirement"

echo "-- project adapter validation (preflight contract) --"
pv=$(sc_tmpdir); mkdir -p "$pv"
cat > "$pv/project.kv" <<EOF
repo=$repo
branch=$branch
commit.subject_regex=^(feat|fix): [a-z]
build=true
lint=true
test=true
acceptance=true
EOF
assert_rc 0 "a complete project.kv validates" -- project_validate "$pv"
sed -i '/^branch=/d' "$pv/project.kv"
assert_rc 2 "missing branch= refuses, naming the key (load-bearing: owed SHA ancestry)" -- \
  project_validate "$pv"
assert_out_has "branch" "the missing key is named"
cat > "$pv/project.kv" <<EOF
repo=$repo
branch=$branch
commit.subject_regex=^(feat|fix): [a-z]
EOF
assert_rc 0 "undeclared build/lint/test/acceptance still validates (honest downgrade)" -- \
  project_validate "$pv"
assert_out_has "acceptance" "the undeclared gates are NAMED at start, never silent"
# The main branch resolves at preflight EXACTLY like doc.branch: nothing in the
# workflow creates it, so an unresolvable name is a mid-topic death at the
# first ancestry read. Cold-reader review found the asymmetry (doc.branch
# refused, branch didn't); this arm pins the closed half of it.
sed -i 's|^branch=.*|branch=no-such-branch|' "$pv/project.kv"
assert_rc 2 "an unresolvable branch refuses (the workflow never creates it; owed SHA ancestry reads it from the first slice on)" -- \
  project_validate "$pv"
assert_out_has "no-such-branch" "the unresolvable branch names itself"
sed -i 's|^branch=.*|branch='"$branch"'|' "$pv/project.kv"
assert_rc 0 "…and the resolvable spelling validates again (the arm's own repair path)" -- \
  project_validate "$pv"
echo "-- a config FAULT stops the ferry; it never reads as an absent value --"
# `fault != absent` is the store's rule and config is held to it too, but the
# ferry reads every key through a command substitution — and a die inside one
# kills the SUBSHELL, leaving the parent holding "". Measured while building a
# drill fixture: a topic.kv violating the liveness-window invariant made
# budget.topic_wallclock resolve to nothing, and the run parked
# `budget_wallclock` reporting "1s working > s" — a park naming a cap it had
# never read, pointing at the wrong cause entirely.
hf_cfg=$(mk_headless_ferry)
wsc=$(mk_ws "$base" cfgfault "$repo" "$branch")
printf 'liveness.quiet_grace=2\nliveness.nudge_grace=180\nliveness.stage_timeout=60\n' \
  > "$wsc/config/topic.kv"
precond "the fixture config really faults (cross-key invariant violated)" \
  bash -c '. "$1/lib/config.sh"; ! config_get budget.topic_wallclock --topic-dir "$2" >/dev/null 2>&1' \
  _ "$RS" "$wsc"
assert_rc 20 "check_budgets on a faulted config stops (rc 20), never parks on an empty cap" -- \
  bash -c '. "$1" "$2" > /dev/null 2>&1; G_SLICE=01 G_STAGE=impl G_ROUND=1; check_budgets' _ "$hf_cfg" "$wsc"
out=$(bash -c '. "$1" "$2" > /dev/null 2>&1; G_SLICE=01 G_STAGE=impl G_ROUND=1; check_budgets' _ "$hf_cfg" "$wsc" 2>&1 || true)
printf '%s' "$out" | command grep -q "CONFIG FAULT" \
  && ok "and the failure NAMES the config fault (the resolver's own message reaches stderr)" \
  || bad "the stop did not name a config fault: $(printf '%s' "$out" | tail -2 | tr '\n' ' ')"
command grep -q "budget_wallclock" <<< "$out" \
  && bad "it still reported a wallclock verdict — a cap it never resolved" \
  || ok "no budget verdict was invented from an unresolved cap"
# ...and the stop is the INPUT-DEFECT class, not the store's. A topic/slice kv
# file is a workflow/topic input; the store is checksummed, so a fault THERE is
# corruption. Answering a typo with exit 30 under a store_fault banner named the
# wrong subsystem to whoever came next, paged store_fault, and spent the
# watchdog's relaunch budget re-running a config that cannot resolve.
[ "$( . "$RS/lib/state.sh"; state_field "$wsc" halt reason 2>/dev/null )" = "template_error" ] \
  && ok "the park reason is template_error (the input-defect class), never store_fault" \
  || bad "halt reason '$( . "$RS/lib/state.sh"; state_field "$wsc" halt reason 2>/dev/null )' — want template_error"
( . "$RS/lib/state.sh"; state_field "$wsc" halt detail 2>/dev/null ) | command grep -q "stage.impl.budget_attempts" \
  && ok "the halt detail names the KEY whose resolution faulted — the FIRST read that faulted, not a later one" \
  || bad "halt detail: $( . "$RS/lib/state.sh"; state_field "$wsc" halt detail 2>/dev/null )"
command grep -q "STORE FAULT" <<< "$out" \
  && bad "the store_fault banner still fires for a config typo — the misattribution is unchanged" \
  || ok "no STORE FAULT banner for a config input defect (each cause keeps its own sentence)"
# The run-init reads are the deliberate exception: they precede any stage, so
# there is nothing to park on and nothing to resume into. They REFUSE — the same
# rc 20 class, a different shape, and no halt surface is written.
wsr=$(mk_ws "$base" cfgfaultinit "$repo" "$branch")
printf 'liveness.quiet_grace=2\nliveness.nudge_grace=180\nliveness.stage_timeout=60\n' \
  > "$wsr/config/topic.kv"
precond "the run-init fixture's run surface is ABSENT (else ensure_run_surface returns early and the check is vacuous)" \
  bash -c '. "$1/lib/state.sh"; ! state_get "$2" run > /dev/null 2>&1' _ "$RS" "$wsr"
assert_rc 20 "a run-init config fault REFUSES (rc 20), never exit 30" -- \
  bash -c '. "$1" "$2" > /dev/null 2>&1; ensure_run_surface' _ "$hf_cfg" "$wsr"
assert_out_has "refuse:" "and it is a refusal, not a park — the pre-stage shape"
assert_out_has "agent.author.backend" "naming the key whose resolution faulted"
( . "$RS/lib/state.sh"; state_get "$wsr" halt > /dev/null 2>&1 ) \
  && bad "a halt surface was written before any stage existed — a park with nothing to resume into" \
  || ok "no halt surface written at run init (nothing to resume into, so nothing pretends there is)"

echo "-- the launch door probes the CONFIG-REACHABLE backend set, not just the two topic roles --"
# The spawn resolves per (role, slice) — run_attempt carries --slice on all
# three agent reads — while the probe covered the two topic-level values only.
# A backend named in a slice override was therefore spawned on having never
# been proven: the promise was checked, the fact never was.
hl=$(mk_headless_launch)
reach() { bash -c '. "$1" > /dev/null 2>&1; WS=$2; probe_reachable_set' _ "$hl" "$1"; }
wsp=$(mk_ws "$base" reachtopic "$repo" "$branch")
printf 'agent.author.backend=claude\nagent.reviewer.backend=claude\n' > "$wsp/config/topic.kv"
out=$(reach "$wsp"); rc=$?
[ "$rc" -eq 0 ] && [ "$(printf '%s\n' "$out" | command grep -c .)" -eq 1 ] \
  && ok "two topic roles on the SAME backend dedupe to one probe (a second is a wasted live session)" \
  || bad "topic-level set is '$(printf '%s' "$out" | tr '\n' ' ')' (rc=$rc)"
printf '%s\n' "$out" | command grep -q '^claude|' \
  && ok "and it is the declared one" || bad "set: $out"
# The discriminating fixture: a backend that appears NOWHERE at topic level.
precond "the slice-level backend differs from both topic-level ones (else its presence proves nothing)" \
  bash -c '! command grep -q "backend=codex" "$1/config/topic.kv"' _ "$wsp"
printf 'agent.author.backend=codex\n' > "$wsp/config/slice.05.author.kv"
out=$(reach "$wsp")
printf '%s\n' "$out" | command grep -q '^codex|' \
  && ok "a backend named ONLY in slice.05.author.kv is in the reachable set (it would otherwise be spawned on unproven)" \
  || bad "the slice-level backend is invisible to the door: $(printf '%s' "$out" | tr '\n' ' ')"
printf '%s\n' "$out" | command grep '^codex|' | command grep -q 'slice.05.author.kv' \
  && ok "and the row NAMES the file it came from (a refusal must point at the input)" \
  || bad "no provenance on the slice row: $(printf '%s\n' "$out" | command grep '^codex|')"
[ "$(printf '%s\n' "$out" | command grep -c .)" -eq 2 ] \
  && ok "the topic-level entry is not duplicated by the slice pass" \
  || bad "set has $(printf '%s\n' "$out" | command grep -c .) rows, want 2: $(printf '%s' "$out" | tr '\n' ' ')"
# A file whose <agent> segment is not a role can never be read by a spawn
# (run_attempt reads agent.<role>.* from slice.<nn>.<role>.kv), so probing on
# its say-so would spend a live session on a value nothing resolves.
printf 'agent.author.backend=nosuchcli\n' > "$wsp/config/slice.07.implementer.kv"
out=$(reach "$wsp")
# The set must still be the two known rows over this input, or the absence
# below reads as clean over a run that produced nothing worth reading.
[ "$(printf '%s\n' "$out" | command grep -c .)" -eq 2 ] \
  && ok "adding a non-role slice file leaves the set at two rows (the read ran; the implementer file is outside it)" \
  || bad "set changed to $(printf '%s\n' "$out" | command grep -c .) rows over a non-role file: $(printf '%s\n' "$out" | tr '\n' ' ')"
command grep -q 'nosuchcli' <<< "$out" \
  && bad "a slice.<nn>.implementer.kv contributed a backend — no spawn can ever read that file" \
  || ok "a non-role slice file contributes nothing (the set is what the ferry can READ, not what exists)"
rm -f "$wsp/config/slice.07.implementer.kv"
# fault != absent here too: a broken slice file must not silently shrink the set
printf 'no.such.key=1\n' > "$wsp/config/slice.06.reviewer.kv"
assert_rc 3 "an unknown key in a slice override FAULTS the derivation (never a silently smaller set)" -- \
  reach "$wsp"
rm -f "$wsp/config/slice.06.reviewer.kv"
# ...and the door ACTS on the whole set. A stub prober records who it was asked
# about, so this proves the slice-only backend is really sent to be probed —
# "it is in the set" is not the same claim.
stubd=$(sc_tmpdir)
probelog="$stubd/asked.txt"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$3" >> "%s"\nexit 0\n' "$probelog" > "$stubd/probe.sh"
chmod +x "$stubd/probe.sh"
door() { bash -c '. "$1" > /dev/null 2>&1; WS=$2; WROOT=$3; L_DIR=$4; probe_backends' _ "$hl" "$1" "$WF_ROOT" "$stubd"; }
assert_rc 0 "the door runs to completion when every declaration in the set resolves" -- door "$wsp"
precond "the stub prober was invoked at all (saw $(wc -l < "$probelog"))" \
  test "$(wc -l < "$probelog")" -ge 2
command grep -qx 'codex' "$probelog" \
  && ok "the slice-only backend is SENT to the probe, not merely enumerated (a record exists for it after a launch)" \
  || bad "the door never probed the slice-level backend: $(tr '\n' ' ' < "$probelog")"
command grep -qx 'claude' "$probelog" \
  && ok "and the topic-level one still is (the widening added, it did not replace)" \
  || bad "the topic-level backend stopped being probed: $(tr '\n' ' ' < "$probelog")"
: > "$probelog"
printf 'agent.author.backend=nosuchcli\n' > "$wsp/config/slice.09.author.kv"
assert_rc 2 "a slice override naming a backend with NO declaration REFUSES at the door" -- door "$wsp"
assert_out_has "backend declaration" "the refusal names the missing declaration"
assert_out_has "slice.09.author.kv" "and the file that asked for it — a refusal must point at the input"
[ "$(wc -l < "$probelog")" -eq 0 ] \
  && ok "and it refuses BEFORE any probe session is spent (the rule the repo-lock advisory check follows)" \
  || bad "a probe was spent before the doomed launch refused: $(tr '\n' ' ' < "$probelog")"
rm -f "$wsp/config/slice.09.author.kv"

echo "-- the topic scope is priced by the TOPIC clock, never by a slice cap --"
# 00 is the topic scope: plan-validate/split/split-check at the beginning,
# close-out at the very end, the whole delivery in between. Its `started` stamp
# is the topic's own start, so a slice cap applied there prices the entire
# topic. Measured at close-out re-entry: 128394s of "working" whose every hour
# belonged to slices 09..15, parking budget_wallclock on a stage that had just
# begun. The two checks would otherwise measure the same span under different
# caps — which is the tell that one of them is the wrong instrument.
wsb=$(mk_ws "$base" budscope "$repo" "$branch")
printf 'budget.slice_wallclock=60\nbudget.topic_wallclock=259200\n' > "$wsb/config/topic.kv"
( . "$RS/lib/state.sh"
  state_put "$wsb" attempts ferry "slice.00.started=1" "slice.01.started=1" > /dev/null
  state_put "$wsb" run ferry "t_start=$(date +%s)" > /dev/null )
assert_rc 20 "a real slice whose clock is long past the cap still parks (the guard is not deleted)" -- \
  bash -c '. "$1" "$2" > /dev/null 2>&1; G_SLICE=01 G_STAGE=impl G_ROUND=1; check_budgets' _ "$hf_cfg" "$wsb"
assert_rc 0 "the SAME ancient stamp under slice 00 does not park — the topic clock owns that span" -- \
  bash -c '. "$1" "$2" > /dev/null 2>&1; G_SLICE=00 G_STAGE=close-out G_ROUND=1; check_budgets' _ "$hf_cfg" "$wsb"
( . "$RS/lib/state.sh"; state_put "$wsb" run ferry "t_start=1" > /dev/null )
assert_rc 20 "and slice 00 DOES park once the TOPIC budget is the one exceeded (the interval stays priced)" -- \
  bash -c '. "$1" "$2" > /dev/null 2>&1; G_SLICE=00 G_STAGE=close-out G_ROUND=1; check_budgets' _ "$hf_cfg" "$wsb"

echo "-- coding_rules: optional, but a DECLARED one must resolve --"
# The key existed and nothing read it: one topic ran to close-out pointing at a
# file with no commit conventions in it, and the conventions the keys cannot
# express (length, body policy, what may not appear at all) reached no session.
# Optional stays optional; a dead pointer is louder than none.
assert_rc 0 "no coding_rules= declared still validates (optional)" -- project_validate "$pv"
echo "coding_rules=docs/nope.md" >> "$pv/project.kv"
assert_rc 2 "a coding_rules= that resolves to nothing REFUSES, naming the path" -- \
  project_validate "$pv"
assert_out_has "coding_rules" "the refusal names the key and what reads it"
mkdir -p "$repo/docs"; printf '# rules\n' > "$repo/docs/nope.md"
assert_rc 0 "with the file present it validates (the check is resolution, not existence of a convention)" -- \
  project_validate "$pv"
sed -i '/^coding_rules=/d' "$pv/project.kv"

sed -i '/^commit.subject_regex=/d' "$pv/project.kv"
assert_rc 2 "missing commit.subject_regex refuses (the commit gate cannot run without it)" -- \
  project_validate "$pv"
nogit=$(sc_tmpdir)/plainrepo
mkdir -p "$nogit"
cat > "$pv/project.kv" <<EOF
repo=$nogit
branch=main
commit.subject_regex=^(feat|fix): [a-z]
EOF
assert_rc 2 "a NON-GIT repo dir refuses at validation (the pipeline is git-shaped: commit gates, SHA ancestry, the claim lock)" -- \
  project_validate "$pv"
assert_out_has "git" "the refusal names the git requirement"

echo "-- doc-repo declaration: the pair is all-or-nothing, git-shaped, resolvable --"
read -r drepo dbranch < <(mk_doc_repo "$base/docrepo")
cat > "$pv/project.kv" <<EOF
repo=$repo
branch=$branch
commit.subject_regex=^(feat|fix): [a-z]
doc.repo=$drepo
EOF
assert_rc 2 "doc.repo without doc.branch refuses (half a declaration binds doc slices to a phantom tip)" -- \
  project_validate "$pv"
assert_out_has "only one of doc.repo=/doc.branch=" \
  "the PAIR rule is what refused — not the branch resolution downstream of it"
sed -i 's|^doc.repo=.*|doc.branch='"$dbranch"'|' "$pv/project.kv"
assert_rc 2 "and the other half alone refuses too (doc.branch without doc.repo)" -- \
  project_validate "$pv"
assert_out_has "only one of doc.repo=/doc.branch=" "same rule, both directions"
sed -i 's|^doc.branch=.*|doc.repo='"$drepo"'|' "$pv/project.kv"
printf 'doc.branch=%s\n' "$dbranch" >> "$pv/project.kv"
assert_rc 0 "the complete pair validates (good direction)" -- project_validate "$pv"
sed -i 's|^doc.branch=.*|doc.branch=no-such-doc-branch|' "$pv/project.kv"
assert_rc 2 "an unresolvable doc.branch refuses (doc cu SHAs cannot be checked against a phantom tip)" -- \
  project_validate "$pv"
assert_out_has "doc.branch" "the unresolvable tip names itself"
sed -i -e 's|^doc.branch=.*|doc.branch='"$dbranch"'|' -e 's|^doc.repo=.*|doc.repo='"$nogit"'|' "$pv/project.kv"
assert_rc 2 "a NON-GIT doc.repo refuses (doc slices commit there; the pipeline is git-shaped)" -- \
  project_validate "$pv"
assert_out_has "is not a git checkout" \
  "the git-shape rule is what refused — not the branch lookup that follows it"

echo "-- R-1: a workspace living INSIDE the doc repo must be git-ignored there --"
# The delivery workspace normally sits under the doc repo's plans/ — safe only
# while the doc repo ignores it. Unignored, every store write dirties the doc
# tree and churns its content-bound gate/acceptance pins on every attempt
# (the mtime-churn lesson this tree's own lock incident recorded).
dws="$drepo/plans/topics/insidetopic/delivery"
mkdir -p "$dws/config"
cat > "$dws/project.kv" <<EOF
repo=$repo
branch=$branch
commit.subject_regex=^(feat|fix): [a-z]
doc.repo=$drepo
doc.branch=$dbranch
EOF
precond "the workspace really is inside the doc repo and NOT ignored yet" \
  bash -c 'git -C "$1" check-ignore -q "$2" && exit 1 || exit 0' _ "$drepo" "$dws"
assert_rc 2 "an unignored workspace inside doc.repo refuses (store writes would churn the doc tree's pins)" -- \
  project_validate "$dws"
assert_out_has "ignored" "the refusal names the ignore requirement"
printf 'plans/\n' > "$drepo/.gitignore"
git -C "$drepo" add .gitignore
git -C "$drepo" commit -qm "chore: ignore the plans working area"
assert_rc 0 "with plans/ ignored, the same workspace validates (the shipped layout)" -- \
  project_validate "$dws"
( . "$RS/lib/state.sh"; state_append "$dws" ledger ferry "v=1 t=1 event=fixture-write" ) > /dev/null
# The write must have LANDED before an empty porcelain can mean anything: a
# refused append would leave the doc repo clean for free, and the arm below
# would celebrate a premise that never ran.
_led=$( . "$RS/lib/state.sh"; state_get "$dws" ledger 2>/dev/null | command grep -c fixture-write || true)
precond "the fixture store write landed on the ledger surface (saw $_led row)" \
  test "$_led" = 1
[ -z "$(git -C "$drepo" status --porcelain)" ] \
  && ok "a store write under the ignored workspace leaves the doc repo porcelain EMPTY (the premise the guard protects)" \
  || bad "doc repo sees store churn: $(git -C "$drepo" status --porcelain | head -2 | tr '\n' ' ')"

echo "-- slice→repo binding primitives: index-carried, default code --"
wsbind=$(mk_ws "$base" bindtopic "$repo" "$branch")
printf 'doc.repo=%s\ndoc.branch=%s\n' "$drepo" "$dbranch" >> "$wsbind/project.kv"
[ "$(binding_kind "$wsbind" 01)" = "code" ] \
  && ok "no slices index yet -> binding reads code (fixtures and the topic-level 00 pseudo-slice)" \
  || bad "binding_kind without an index returned '$(binding_kind "$wsbind" 01)'"
( . "$RS/lib/state.sh"
  printf 'id=01 status=pending risk=low repo=code title=a rederive=0\nid=02 status=pending risk=low repo=doc title=b rederive=0\nid=03 status=pending risk=low title=old rederive=0\n' \
    | state_set "$wsbind" slices ferry ) > /dev/null
[ "$(binding_kind "$wsbind" 02)" = "doc" ] && ok "repo=doc row reads doc" || bad "row repo=doc read as $(binding_kind "$wsbind" 02)"
[ "$(binding_kind "$wsbind" 03)" = "code" ] \
  && ok "a row WITHOUT repo= reads code (pre-binding indexes keep working)" \
  || bad "defaulting broken: $(binding_kind "$wsbind" 03)"
[ "$(binding_repo "$wsbind" 02)" = "$drepo" ] && [ "$(binding_branch "$wsbind" 02)" = "$dbranch" ] \
  && ok "a doc-bound slice resolves to doc.repo/doc.branch" \
  || bad "doc binding resolved to '$(binding_repo "$wsbind" 02)' / '$(binding_branch "$wsbind" 02)'"
[ "$(binding_repo "$wsbind" 01)" = "$repo" ] && [ "$(binding_branch "$wsbind" 01)" = "$branch" ] \
  && ok "a code-bound slice resolves to repo/branch (unchanged for every existing topic)" \
  || bad "code binding resolved to '$(binding_repo "$wsbind" 01)'"
[ "$(project_repos "$wsbind" | paste -sd, -)" = "$repo,$drepo" ] \
  && ok "project_repos enumerates code first, doc second (the one lock-order truth)" \
  || bad "project_repos order: $(project_repos "$wsbind" | paste -sd, -)"
echo "-- index admissibility: the ONE rule both doors ask (emit refusal + ingest backstop) --"
( . "$RS/lib/state.sh"
  printf 'id=01 status=done risk=low repo=code title=a rederive=0\nid=02 status=pending risk=low title=norepo rederive=0\n' \
    | state_set "$wsbind" slices ferry ) > /dev/null
assert_rc 0 "re-listing ids with their standing bindings is admissible" -- \
  slices_admissible "$wsbind" "01:low:code:a;02:low:code:norepo"
assert_rc 1 "re-binding an existing id FIRES" -- slices_admissible "$wsbind" "01:low:doc:a"
assert_out_has "id 01 re-binds" "the offending id is named"
assert_out_has "standing=code" "with what it is actually bound to"
assert_out_has "NEW id" "and with the fix"
assert_rc 1 "a row without repo= stands bound to code, so declaring it doc IS a re-bind" -- \
  slices_admissible "$wsbind" "02:low:doc:norepo"
assert_rc 0 "an id with no standing row is a NEW slice, never a conflict" -- \
  slices_admissible "$wsbind" "09:low:doc:fresh"
assert_rc 0 "a risk change on a standing id is admissible (different field, different treatment)" -- \
  slices_admissible "$wsbind" "01:high:code:a"
( . "$RS/lib/state.sh"
  printf 'id=01 status=done risk=low repo=code title=a rederive=0\nid=02 status=pending risk=low title=norepo rederive=0\nid=05 status=superseded risk=low repo=code title=retired rederive=0\nid=06 status=cancelled risk=low repo=code title=off rederive=0\n' \
    | state_set "$wsbind" slices ferry ) > /dev/null
assert_rc 1 "re-listing a RETIRED (superseded) id FIRES — ids are never reused, and keeping its row silently means that work never runs" -- \
  slices_admissible "$wsbind" "05:low:code:retired"
assert_out_has "retired" "the reason names the id's state"
assert_rc 0 "a DONE id may be re-listed (history, not a retirement — the row simply holds)" -- \
  slices_admissible "$wsbind" "01:low:code:a"
assert_rc 0 "a CANCELLED id may be re-listed too (the operator can restore it; only superseded is terminal)" -- \
  slices_admissible "$wsbind" "06:low:code:off"
assert_rc 1 "a doubled id FIRES" -- slices_admissible "$wsbind" "09:low:code:a;09:low:doc:b"
assert_out_has "declared twice" "the duplicate is named"
assert_rc 1 "a malformed segment FIRES" -- slices_admissible "$wsbind" "9:low:code:a"
assert_rc 1 "id 00 FIRES — it is the topic scope's name, and a declared 00 would be scheduled into that namespace silently" -- \
  slices_admissible "$wsbind" "00:low:code:topic-collision"
assert_out_has "RESERVED" "the reason names the reservation and where ids start"
assert_rc 1 "an EMPTY segment FIRES (a malformed field, never something to skip past)" -- \
  slices_admissible "$wsbind" "09:low:code:a;;10:low:doc:b"
assert_out_has "stray ';'" "the empty segment is diagnosed as the stray separator it is"
out=$(slices_admissible "$wsbind" "01:low:doc:a;09:low:code:x;09:low:doc:y" || true)
[ "$(printf '%s\n' "$out" | command grep -c .)" = "2" ] \
  && ok "every reason is listed at once (one list, like the owed set — not first-miss-and-stop)" \
  || bad "reason list: $(printf '%s' "$out" | tr '\n' '|')"

echo "-- after=: delivery order rides the index — backward-only, resolvable, immutable --"
# The measured inversion: a re-split minted lower ids than their hard
# prerequisites and the lexicographic-min scheduler ran them inverted; the
# charter's order was prose, machine-invisible. after= makes it machine-read.
( . "$RS/lib/state.sh"
  printf 'id=01 status=done risk=low repo=code title=a rederive=0\nid=02 status=pending risk=low repo=code title=b rederive=0\nid=03 status=pending risk=low repo=code title=c rederive=0 after=01\n' \
    | state_set "$wsbind" slices ferry ) > /dev/null
assert_rc 0 "a well-formed after= naming a STANDING earlier id is admissible" -- \
  slices_admissible "$wsbind" "09:low:code:x:after=01"
assert_rc 0 "after may name an id declared earlier IN THE SAME FIELD" -- \
  slices_admissible "$wsbind" "09:low:code:x;10:low:code:y:after=09"
assert_rc 0 "multiple afters ride one segment" -- \
  slices_admissible "$wsbind" "09:low:code:x;10:low:code:y;11:low:code:z:after=09,10"
assert_rc 1 "a FORWARD reference fires — delivery order rides the id order (backward edges only: acyclic by construction, no cycle walk exists to need)" -- \
  slices_admissible "$wsbind" "09:low:code:x:after=10;10:low:code:y"
assert_out_has "EARLIER" "the reason names the backward-only rule"
assert_rc 1 "a SELF reference fires the same way" -- \
  slices_admissible "$wsbind" "09:low:code:x:after=09"
assert_rc 1 "an after naming a NONEXISTENT id fires (a typo must not silently satisfy or block forever)" -- \
  slices_admissible "$wsbind" "09:low:code:x:after=07"
assert_out_has "exists nowhere" "the reason says where it looked"
assert_rc 1 "a malformed after tail fires instead of folding into the title" -- \
  slices_admissible "$wsbind" "09:low:code:x:after=7"
assert_out_has "malformed after=" "the reason names the tail shape"
assert_rc 0 "re-listing a standing id WITHOUT after keeps its row (omission is not a declaration)" -- \
  slices_admissible "$wsbind" "03:low:code:c"
assert_rc 0 "re-declaring the SAME after set is admissible (nothing changes)" -- \
  slices_admissible "$wsbind" "03:low:code:c:after=01"
assert_rc 1 "re-declaring a DIFFERENT after set fires — the scheduler reads it, same class as the binding" -- \
  slices_admissible "$wsbind" "03:low:code:c:after=02"
assert_out_has "cast once" "the reason states the immutability rule and the fix"
assert_rc 1 "declaring after= on a standing id that had NONE fires too (the standing row would drop it silently)" -- \
  slices_admissible "$wsbind" "02:low:code:b:after=01"
( . "$RS/lib/state.sh"
  printf 'id=01 status=done risk=low repo=code title=a rederive=0\nid=02 status=pending risk=low title=norepo rederive=0\nid=05 status=superseded risk=low repo=code title=retired rederive=0\nid=06 status=cancelled risk=low repo=code title=off rederive=0\n' \
    | state_set "$wsbind" slices ferry ) > /dev/null

# fault != absent, on the surface that IS the binding's home: an unreadable
# index must never answer 'code' — that answer sends a doc slice's evidence,
# commits and gate pins to the wrong checkout, silently.
corrupt_surface "$wsbind" slices
assert_rc 3 "a CORRUPT slices surface faults instead of answering (fault != absent)" -- \
  binding_kind "$wsbind" 02
assert_out_has "FAULT" "the fault names itself"
[ -z "$(binding_kind "$wsbind" 02 2>/dev/null)" ] \
  && ok "and prints no binding word at all (no caller can read a default out of it)" \
  || bad "binding_kind answered '$(binding_kind "$wsbind" 02 2>/dev/null)' over a corrupt index"
assert_rc 3 "binding_repo propagates the fault (evidence never resolves over a broken index)" -- \
  binding_repo "$wsbind" 02
assert_rc 3 "binding_branch propagates it too" -- binding_branch "$wsbind" 02
assert_rc 3 "and so does the admissibility rule (a doorman who cannot read the index refuses to judge)" -- \
  slices_admissible "$wsbind" "01:low:doc:a"

echo "-- cross-field liveness rule: the nudge window must fit under the stage timeout --"
wt=$(mk_ws "$base" cfgtiming "$repo" "$branch")
cat > "$wt/config/topic.kv" <<'EOF'
liveness.quiet_grace=4
liveness.nudge_grace=4
liveness.stage_timeout=2
EOF
assert_rc 3 "quiet_grace+nudge_grace >= stage_timeout FAULTS (defaults.kv states the constraint; an accepted violation deletes the self-heal window silently)" -- \
  config_get liveness.stage_timeout --topic-dir "$wt"
assert_out_has "nudge" "the fault names the violated window rule"
cat > "$wt/config/topic.kv" <<'EOF'
liveness.quiet_grace=1
liveness.nudge_grace=1
liveness.stage_timeout=4
liveness.hard_ceiling=10
EOF
assert_rc 0 "a legal timing set still resolves (good direction)" -- \
  config_get liveness.stage_timeout --topic-dir "$wt"
cat > "$wt/config/topic.kv" <<'EOF'
liveness.stage_timeout=99999
EOF
assert_rc 3 "stage_timeout above hard_ceiling FAULTS (the ceiling must stay the one absolute cap)" -- \
  config_get liveness.stage_timeout --topic-dir "$wt"
cat > "$wt/config/topic.kv" <<'EOF'
stage.impl.timeout=300
EOF
assert_rc 3 "a per-stage timeout override below the nudge window (defaults 420+180) FAULTS too" -- \
  config_get liveness.stage_timeout --topic-dir "$wt"

echo "-- validation memo is CONTENT-keyed: an edit always re-validates --"
wm=$(mk_ws "$base" cfgmemo "$repo" "$branch")
echo "slice.max_commits=7" > "$wm/config/topic.kv"
assert_rc 0 "a clean file validates (and its result is memoized by content hash)" -- \
  config_get slice.max_commits --topic-dir "$wm"
echo "no.such.key=1" >> "$wm/config/topic.kv"
assert_rc 3 "the EDITED file re-validates and FAULTS on the unknown key (new content = new hash; the memo can never serve a stale clean verdict)" -- \
  config_get slice.max_commits --topic-dir "$wm"
assert_out_has "no.such.key" "the fault names the typo key"
sed -i '/^no.such.key=/d' "$wm/config/topic.kv"
assert_rc 0 "restored content validates again (its clean hash is already memoized)" -- \
  config_get slice.max_commits --topic-dir "$wm"

echo "-- stage-dimension keys must name a REAL stage (a typo'd stage never reads back) --"
echo "stage.imp.timeout=900" >> "$wm/config/topic.kv"
assert_rc 3 "stage.imp.timeout (typo for impl) faults naming the unknown stage" -- \
  config_get slice.max_commits --topic-dir "$wm"
assert_out_has "imp" "the fault names the typo'd stage"
sed -i '/^stage.imp.timeout=/d' "$wm/config/topic.kv"
echo "stage.impl.timeout=900" >> "$wm/config/topic.kv"
assert_rc 0 "a real stage name passes" -- config_get slice.max_commits --topic-dir "$wm"
sed -i '/^stage.impl.timeout=/d' "$wm/config/topic.kv"

echo "-- the memo key binds EVERY validator input (stages.tsv included) --"
# The stage-membership rule made stages.tsv a validator input; a memo keyed
# only on schema+file+impl replays a clean verdict across a stage
# rename/removal (a workflow upgrade with schema and topic.kv unchanged) —
# false-clean in exactly the scenario the rule exists to catch.
xr="$base/xroot"
mkdir -p "$xr/config"
cp "$WF_ROOT/config/schema.kv" "$WF_ROOT/config/defaults.kv" \
   "$WF_ROOT/config/stages.tsv" "$xr/config/"
printf '# closure fixture %s\nstage.impl.timeout=900\n' "$$" > "$wm/config/topic.kv"
assert_rc 0 "a real stage key validates clean under a scratch root (memo written)" -- \
  env CONFIG_WORKFLOW_ROOT="$xr" bash -c ". '$RS/lib/config.sh'; config_get slice.max_commits --topic-dir '$wm'"
command grep -v $'^impl\t' "$xr/config/stages.tsv" > "$xr/config/stages.tsv.n" \
  && mv "$xr/config/stages.tsv.n" "$xr/config/stages.tsv"
assert_rc 3 "the SAME file re-validates and FAULTS once 'impl' leaves stages.tsv (the memo binds the tsv content, not only schema+file)" -- \
  env CONFIG_WORKFLOW_ROOT="$xr" bash -c ". '$RS/lib/config.sh'; config_get slice.max_commits --topic-dir '$wm'"

echo "-- the config snapshot says which layers it carries --"
# It is handed to every author and reviewer under a title that calls it the
# EFFECTIVE config, and it can only ever hold the two topic-wide layers: the
# third is per (slice, agent) and no one topic-wide file can carry it. The
# staleness this file was fixed for and this gap are the same failure — a
# label a reader has no reason to doubt — so the file states its own scope.
wsnap=$(mk_ws "$base" snaplayers "$repo" "$branch")
printf 'slice.max_commits=9\n' > "$wsnap/config/topic.kv"
snapf=$( . "$RS/lib/config.sh"; config_write_snapshot "$WF_ROOT" "$wsnap" )
precond "the snapshot was written" test -s "$snapf"
command grep -q '^slice.max_commits=9$' "$snapf" \
  && ok "the topic layer is in it (later wins, as config_get resolves)" \
  || bad "topic layer missing: $(command grep -c . "$snapf") lines"
command grep -qi 'LAYER ABSENT' "$snapf" && command grep -q 'slice\.<nn>\.<agent>\.kv' "$snapf" \
  && ok "and it NAMES the layer it cannot carry, in the artifact that travels" \
  || bad "the snapshot claims to be effective without saying which layers it has: $(head -3 "$snapf" | tr '\n' ' ')"
# Hermetic by construction here (fixtures/lib.sh points XDG_CONFIG_HOME at the
# session tmp), so this snapshot carries the ABSENT marker for the operator
# layer — "not in the body" and "empty file" must not read alike.
command grep -q 'operator config absent' "$snapf" \
  && ok "an absent operator layer is MARKED absent (a reader can tell it from an empty one)" \
  || bad "no absent-marker for the operator layer: $(head -6 "$snapf" | tr '\n' ' ')"
snapf2=$( env XDG_CONFIG_HOME="$ux" bash -c ". '$RS/lib/config.sh'; config_write_snapshot '$WF_ROOT' '$wsnap'" )
command grep -q '^slice.max_commits=6$' "$snapf2" \
  && ok "a present operator layer rides the snapshot the agents are handed" \
  || bad "operator layer missing from the snapshot: $(command grep -c . "$snapf2") lines"
l_def=$(command grep -n '^slice.max_commits=8$' "$snapf2" | head -1 | cut -d: -f1)
l_op=$(command grep -n '^slice.max_commits=6$' "$snapf2" | head -1 | cut -d: -f1)
l_top=$(command grep -n '^slice.max_commits=9$' "$snapf2" | head -1 | cut -d: -f1)
[ -n "$l_def" ] && [ -n "$l_op" ] && [ -n "$l_top" ] && [ "$l_def" -lt "$l_op" ] && [ "$l_op" -lt "$l_top" ] \
  && ok "concatenation order IS resolution order (defaults 8 < operator 6 < topic 9 — later wins in the artifact itself)" \
  || bad "layer order wrong in the snapshot: defaults@$l_def operator@$l_op topic@$l_top"
# The header must not become a value: config_get never reads this file, but a
# reader that greps it should see comments, not keys.
command grep -vE '^#|^$' "$snapf" | command grep -qE '^[A-Za-z][A-Za-z0-9._*-]*=' \
  && ok "every non-comment line is still a plain key=value (the header is comments)" \
  || bad "the snapshot's body is no longer kv: $(command grep -vE '^#|^$' "$snapf" | head -2 | tr '\n' ' ')"

echo "-- the operator CLI's exit status (the wrapper, not the library) --"
# The one path a HUMAN uses to ask "is this config legal before I launch it",
# and the only path in this tree that runs these functions as a program. Every
# arm above sources the library and calls the functions, so none of them
# exercises the wrapper at all — which is exactly why the wrapper returned 0 on
# every fault class for as long as it did (measured 2026-09-03 before a launch:
# `FAULT: rule.reviewer_effort_floor …` on stderr with rc=0, against rc=3 from
# the sourced call; the operator read that as a pass, and the config would have
# exit-3'd the next preflight). The cause was structural, not a typo: the CLI
# dispatch block is not at the end of the file, a function definition follows
# it, and a function definition succeeds.
#
# So these arms MUST run it as a program, in a subshell, and must never call
# the sourced function — a wrapper arm that asserts on the library proves the
# half that was never broken. The hermetic env is passed explicitly for the
# same reason `config_write_snapshot`'s arms do it.
cliws=$(sc_tmpdir); mkdir -p "$cliws/config"
cli_rc() { # <args...> -> prints the wrapper's rc, discards its output
  env XDG_CONFIG_HOME="$XDG_CONFIG_HOME" CONFIG_WORKFLOW_ROOT="$WF_ROOT" \
    bash "$RS/lib/config.sh" "$@" > /dev/null 2>&1
  echo $?
}
# Floor FIRST: a happy path must still exit 0 AND still print its value, or
# these arms would pass over a wrapper that exits nonzero on everything.
cli_v=$(env XDG_CONFIG_HOME="$XDG_CONFIG_HOME" CONFIG_WORKFLOW_ROOT="$WF_ROOT" \
          bash "$RS/lib/config.sh" get slice.max_commits 2>/dev/null)
[ "$(cli_rc get slice.max_commits)" = 0 ] && [ "$cli_v" = 8 ] \
  && ok "CLI happy path still exits 0 and still prints its value ($cli_v)" \
  || bad "CLI happy path broken: rc=$(cli_rc get slice.max_commits) value='$cli_v'"

# THE MEASURED DEFECT: a rule fault, the class the operator was reading.
printf 'agent.author.effort=max\nagent.reviewer.effort=high\n' > "$cliws/config/topic.kv"
[ "$(cli_rc get agent.reviewer.backend --topic-dir "$cliws")" = 3 ] \
  && ok "CLI returns 3 on a rule FAULT (the pre-launch question, answered honestly)" \
  || bad "CLI returns $(cli_rc get agent.reviewer.backend --topic-dir "$cliws") on a rule fault — a FAULT reading as a pass is the measured defect"
# And the stderr the operator sees is still the rule's own sentence: an rc with
# no reason is half an instrument.
# The stderr is CAPTURED, never piped, and that is not a style choice — this
# file runs under `set -o pipefail`, so `config.sh … | grep -q` takes the
# pipeline's status from the LEFT side, which is now correctly 3. Written as a
# pipe, this arm reds on a healthy tree: the very rc the fix restores would
# break the probe for it. Measured while writing it.
cli_err=$(env XDG_CONFIG_HOME="$XDG_CONFIG_HOME" CONFIG_WORKFLOW_ROOT="$WF_ROOT" \
            bash "$RS/lib/config.sh" get agent.reviewer.backend --topic-dir "$cliws" 2>&1 >/dev/null)
case "$cli_err" in
  *"FAULT: rule.reviewer_effort_floor"*)
    ok "the nonzero rc rides the rule's own FAULT sentence (rc and reason together)" ;;
  *) bad "rc without the reason — the operator gets a number and no cause: '$cli_err'" ;;
esac

# The other two fault classes through the same wrapper.
[ "$(cli_rc get nosuch.key)" = 2 ] \
  && ok "CLI returns 2 on a key outside the closed vocabulary" \
  || bad "CLI returns $(cli_rc get nosuch.key) on an unknown key"
# The DOCUMENTED-SPELLING class: an unknown arg prints a refusal and must not
# read as an empty-but-successful value to `$(...)`. design/config-and-adapters.md
# advertised `--topic` where the parser takes `--topic-dir`, and both halves of
# that were silent.
[ "$(cli_rc get slice.max_commits --topic "$cliws")" = 2 ] \
  && ok "CLI returns 2 on an unknown arg (an empty stdout is not a success)" \
  || bad "CLI returns $(cli_rc get slice.max_commits --topic "$cliws") on an unknown arg"
# The usage branch was ALWAYS right (it carries its own `exit 2`) — kept as the
# discriminator: if these arms pass only because everything exits 2, this one
# proves nothing and the happy-path floor above catches it.
[ "$(cli_rc bogus-verb)" = 2 ] \
  && ok "CLI returns 2 on an unknown verb (the one branch that was always correct)" \
  || bad "CLI returns $(cli_rc bogus-verb) on an unknown verb"

# The DOC and the parser agree — the second fault class had no instrument at
# all, and a wrong flag spelling in the doc is silent twice over (refusal on
# stderr, exit 0, empty stdout). Grammar rule, not a spelling list: every
# `lib/config.sh get` invocation printed in the design docs must use a flag the
# parser accepts.
# Floor and verdict are ONE decision, not a red beside a vacuous green: a sweep
# that matched nothing must produce exactly one red, never "swept nothing" plus
# "every flag is fine ()". Measured on this arm's own known-bad before landing.
doc_flags=$(command grep -rhoE 'lib/config\.sh get <key> \[[^]]*\]' "$WF_ROOT/design" 2>/dev/null)
doc_names=$(printf '%s\n' "$doc_flags" | command grep -oE '\-\-[a-z-]+' | sort -u)
if [ -z "$doc_names" ]; then
  bad "no documented \`config.sh get\` invocation found under design/ — the arm swept nothing, which is not a clean verdict"
else
  bad_flag=$(printf '%s\n' "$doc_names" | while IFS= read -r fl; do
               command grep -qF -- "      $fl)" "$RS/lib/config.sh" || echo "$fl"
             done)
  [ -z "$bad_flag" ] \
    && ok "every flag the design docs print for \`config.sh get\` is one the parser accepts ($(printf '%s' "$doc_names" | tr '\n' ' '))" \
    || bad "design docs advertise flags config_get refuses:$(printf ' %s' $bad_flag) — the refusal is silent and exits 0 for whoever follows the doc"
fi

check_done
