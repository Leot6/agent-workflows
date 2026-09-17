#!/usr/bin/env bash
# 61-gates-floor — the two SWEEPS that close the gate family: every `gates_*`
# function owes a red-proof (the decidable half of the retired gate-removal
# window, `maintenance.md` §1), and the impl prompt names an absolute path for
# every project gate. Both read the tree rather than the fixture workspace,
# which is what makes them the separable end of 60-gates.sh.
#
# Split out when 60-gates.sh reached cap.selftest_file=1000; owner-ruled
# 2026-09-09, split the file rather than raise the cap. The seam is CONTIGUOUS
# and at the end on purpose: the first attempt lifted the claims-gate family out
# by name, mirroring `lib/gates_claims.sh`, and broke both halves — this check
# is sequential fixture code, not function definitions, and `$art` is set in one
# block and read six blocks later. A check file's separable unit is a suffix
# that builds its own state, never a family.
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/fixtures/lib.sh"
. "$RS/lib/state.sh"
. "$RS/lib/gates.sh"

base=$(sc_tmpdir)
read -r repo branch < <(mk_repo "$base/repo")
ws=$(mk_ws "$base" gatetopic "$repo" "$branch")

echo "-- every gate function owes a red-proof (the retired removal window's decidable half) --"
# A gate reading zero FAILs over a topic is IDENTICAL for a dead gate and for a
# working floor, which is why the topic-counting removal window was retired
# (maintenance.md §1). The half that IS decidable — can this gate refuse
# anything at all? — is answered here, every run, off artifacts that already
# exist: a gates_* function with no `assert_rc 1 ... -- gates_<name>` anywhere
# under checks/ has never been SHOWN to fire, and its production zero means
# nothing. This is the unfloored-arm question aimed at the gates.
# BOUNDARY, stated because it is a rule and not an oversight: the corpus is
# `checks/` alone. A gate proved only inside a drill reads as UNPROVEN here, and
# that red is correct — a drill is an end-to-end scenario, and a gate's proof
# that it can REFUSE is a unit claim about the function. The runner already
# floors the two collections separately for the same reason. So the red says
# "write the unit proof", never "the drill does not count as testing".
gate_redproofs() { # <lib-dir> <checks-dir> -> violation lines; rc is the caller's
  local libd=$1 chd=$2 defs proofs g
  # gates_dirty_fp is exempt BY NAME: it returns a fingerprint string and has
  # no FAIL direction to prove. Named here so the carve-out is stated, never
  # discovered — and swept below so it can only shrink.
  local exempt_list="gates_dirty_fp"
  defs=$(command grep -rhoE '^gates_[a-z_]+\(\)' "$libd" 2>/dev/null | sed 's/()$//' | sort -u)
  # Continuations JOINED first. The red-proofs are written
  # `assert_rc 1 "..." -- \` + newline + `  gates_<name> ...`, so a per-line
  # grep sees a minority of them. Measured while writing this: the per-line
  # form found 16 proofs where the joined form finds 33, missed gates_structure
  # and gates_stamp_freshness ENTIRELY, and still reported "clean" — a count
  # standing in for the instances it never printed. The `--[[:space:]]+` is
  # load-bearing for the same reason: joining leaves two spaces, and a
  # single-space pattern silently drops every wrapped proof.
  proofs=$(cat "$chd"/*.sh 2>/dev/null \
    | sed -e ':a' -e '/\\$/{N;s/\\\n[[:space:]]*/ /;ba' -e '}' \
    | command grep -oE 'assert_rc 1 .*--[[:space:]]+gates_[a-z_]+' \
    | command grep -oE 'gates_[a-z_]+$' | sort -u)
  [ -n "$defs" ]   || { echo "sweep read NO gate definitions under $libd"; return 0; }
  [ -n "$proofs" ] || { echo "sweep extracted NO red-proofs from $chd"; return 0; }
  for g in $defs; do
    case " $exempt_list " in *" $g "*) continue ;; esac
    command grep -qx "$g" <<< "$proofs" \
      || echo "$g has no red-proof: nothing in the suite shows it can refuse anything"
  done
  for g in $exempt_list; do
    command grep -qx "$g" <<< "$defs" \
      || echo "exempt name '$g' is no longer a gate function (a stale carve-out passes its successor)"
  done
}
n_def=$(command grep -rhoE '^gates_[a-z_]+\(\)' "$WF_ROOT/runtime-scripts/lib" | sort -u | command grep -c . || true)
n_pr=$(cat "$SC_ROOT/checks"/*.sh | sed -e ':a' -e '/\\$/{N;s/\\\n[[:space:]]*/ /;ba' -e '}' \
  | command grep -cE 'assert_rc 1 .*--[[:space:]]+gates_[a-z_]+' || true)
precond "the sweep sees the gate library and the proofs (${n_def} gate fns, ${n_pr} red-proof assertions)" \
  bash -c '[ "$1" -ge 8 ] && [ "$2" -ge 20 ]' _ "$n_def" "$n_pr"
viol=$(gate_redproofs "$WF_ROOT/runtime-scripts/lib" "$SC_ROOT/checks")
[ -z "$viol" ] \
  && ok "every gate function is proved able to refuse ($((n_def - 1)) gates + gates_dirty_fp exempt)" \
  || bad "gate red-proof gaps: $viol"
# Known-bads, both directions, on a fake pair of trees — the sweep must fire on
# an unproven gate and must NOT fire once its proof exists, or it is agreeing
# with itself over whatever it happened to extract.
frp=$(sc_tmpdir); mkdir -p "$frp/lib" "$frp/checks"
printf 'gates_dirty_fp() { :; }\ngates_zzz_proven() { :; }\ngates_zzz_unproven() { :; }\n' > "$frp/lib/gates.sh"
# The corpus carries a real red-proof for the SIBLING gate, so the extraction
# floor is satisfied and the only finding left is the per-gate gap — otherwise
# this known-bad would pass on the floor and prove nothing about the loop.
printf 'assert_rc 1 "sibling refuses" -- gates_zzz_proven "$ws"\n' > "$frp/checks/01-x.sh"
printf 'assert_rc 0 "it passes" -- gates_zzz_unproven "$ws"\n' >> "$frp/checks/01-x.sh"
command grep -q 'gates_zzz_unproven has no red-proof' <<< "$(gate_redproofs "$frp/lib" "$frp/checks")" \
  && ok "known-bad: a gate with only a PASS assertion is caught (passing is not proof of refusing)" \
  || bad "unproven gate slipped through: $(gate_redproofs "$frp/lib" "$frp/checks")"
printf 'assert_rc 1 "it refuses" -- \\\n  gates_zzz_unproven "$ws"\n' >> "$frp/checks/01-x.sh"
[ -z "$(gate_redproofs "$frp/lib" "$frp/checks")" ] \
  && ok "…and a WRAPPED red-proof satisfies it (the continuation join is exercised, not assumed)" \
  || bad "wrapped red-proof not seen: $(gate_redproofs "$frp/lib" "$frp/checks")"
printf 'gates_zzz_proven() { :; }\ngates_zzz_unproven() { :; }\n' > "$frp/lib/gates.sh"
command grep -q 'stale carve-out' <<< "$(gate_redproofs "$frp/lib" "$frp/checks")" \
  && ok "known-bad: an exemption for a name that is no longer a gate is caught" \
  || bad "stale exemption survived: $(gate_redproofs "$frp/lib" "$frp/checks")"
rm -f "$frp/checks/01-x.sh"
printf '%s' "$(gate_redproofs "$WF_ROOT/runtime-scripts/lib" "$frp/checks")" \
  | command grep -q 'extracted NO red-proofs' \
  && ok "known-bad: an empty checks/ reads as 'extracted nothing', never as clean" \
  || bad "empty corpus read as a pass"

# Lives HERE and not with the other template arms because its subject is
# `gates.sh project`'s DISCOVERABILITY, not the template's structure — and
# because 30-closure is at the own-tree line cap, which is the honest half of
# the reason and is said rather than hidden.
TPLDIR="$WF_ROOT/runtime-docs/templates/prompts"
echo "-- the impl prompt names the path for EVERY project gate, not only acceptance --"
# Measured 2026-09-03: two consecutive slices of one topic recorded differently —
# slice 01 attested build/lint/test on the gates surface, slice 02 left them as
# /tmp logs, all green and none citable. The path existed; the emit refusal names
# acceptance only, so everything else was author discretion. A prompt is where an
# author learns what the harness accepts, so the prompt is the rung — and this arm
# is here because prose is the one thing nothing else in this suite holds.
impl_t="$TPLDIR/impl.warm.md"
precond "the impl template exists" test -f "$impl_t"
command grep -q 'EVERY project gate' "$impl_t" \
  && ok "the impl prompt states the duty: EVERY gate the spec's plan names, not only the one the emit refusal mentions" \
  || bad "impl.warm.md does not state the every-gate duty — per-unit build/lint/test is back to author discretion"

# And the PATH must reach the stage, which is the half a source-file grep cannot
# see: a stage has no cwd and no template can know one (compose.sh says so in
# its own words), so a relative path in a prompt reads fine and cannot resolve.
# The first form of this arm asserted a relative path in the template and passed.
# So: render a real prompt and require an ABSOLUTE, EXISTING gates path in it.
gws=$(mk_full_ws "$base" gatestopic "$repo" "$branch")
gout=$(sc_tmpdir)
. "$RS/lib/compose.sh"
if compose_prompt "$gws" impl 01 1 1 n0nceG warm "$gout/impl.md" > /dev/null 2>&1 \
   && [ -s "$gout/impl.md" ]; then
  g_line=$(command grep -oE '/[^ ]*gates\.sh project ' "$gout/impl.md" | head -1)
  g_bin=${g_line%% project }
  [ -n "$g_bin" ] && [ -f "$g_bin" ] \
    && ok "the rendered impl prompt carries an ABSOLUTE gates path that EXISTS ($(basename "$g_bin"))" \
    || bad "the rendered prompt carries no resolvable gates path (found '${g_line:-<none>}') — a stage has no cwd, so a relative one reads fine and cannot run"
  command grep -qE '^  /[^ ]*gates\.sh project [^ ]+ <build\|lint\|test\|acceptance>$' "$gout/impl.md" \
    && ok "and it is a runnable invocation with the workspace already filled in" \
    || bad "the gates line is not runnable as printed: $(command grep -m1 'gates.sh' "$gout/impl.md")"
  # It rides the VOLATILE header, like every other tool path — so it is excluded
  # from the attempt fingerprint and cannot become a novelty source.
  awk '/volatile-header-begin/{h=1} /volatile-header-end/{h=0} h && /gates\.sh project/{f=1} END{exit !f}' "$gout/impl.md" \
    && ok "and it rides the volatile header (fingerprint-excluded, like record.sh)" \
    || bad "the gates path is in the prompt BODY — it would become a fingerprint input"
else
  bad "no impl prompt rendered — the path arm swept nothing, which is not a clean verdict"
fi

echo "-- every dispatcher arm is documented, and every documented arm exists --"
# `emit_checks.sh` prints this CLI form to an agent as the advice for a gate with
# no PASS record, so an arm nobody can discover is an arm nobody runs — the
# unfloored-arm question aimed at the usage text rather than at a
# check. Measured on the day it was written: the dispatcher accepted ten arms
# and printed nine, the tenth being `plan-binds`, added with the gate and not
# with its usage line. Read off the dispatcher itself so a rename cannot leave
# the two agreeing about a name neither uses.
gsrc="$RS/lib/gates.sh"
arms=$(sed -n '/^  case "${1:-}" in$/,/^    \*)/p' "$gsrc" | command grep -oE '^    [a-z][a-z-]*\)' | tr -d ' )' | sort -u)
docd=$(sed -n '/usage: gates\.sh/,/exit 2 ;;/p' "$gsrc" | command grep -oE 'gates\.sh [a-z][a-z-]*' | awk '{print $2}' | sort -u)
precond "the sweep reads both lists (arms $(printf '%s' "$arms" | command grep -c .), documented $(printf '%s' "$docd" | command grep -c .))" \
  bash -c '[ "$(printf "%s" "$1" | grep -c .)" -ge 8 ] && [ "$(printf "%s" "$2" | grep -c .)" -ge 8 ]' _ "$arms" "$docd"
undocumented=$(comm -23 <(printf '%s\n' "$arms") <(printf '%s\n' "$docd") | tr '\n' ' ')
[ -z "${undocumented% }" ] \
  && ok "every dispatcher arm appears in the usage text" \
  || bad "dispatcher arm(s) with no usage line: ${undocumented% } — emit_checks.sh hands this CLI to an agent"
phantom=$(comm -13 <(printf '%s\n' "$arms") <(printf '%s\n' "$docd") | tr '\n' ' ')
[ -z "${phantom% }" ] \
  && ok "every documented arm is one the dispatcher accepts" \
  || bad "usage text names arm(s) the dispatcher rejects: ${phantom% }"

check_done
