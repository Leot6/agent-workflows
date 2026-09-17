#!/usr/bin/env bash
# 30-closure — cross-file referential integrity: stages.tsv total over
# (stage, verdict); session-column/template closure incl. the modes the
# ferry can actually select (decide_mode); manifest placeholder closure; owed
# items resolve in lib/owed.sh; schema.kv covers every key the scripts read;
# backend declarations complete (backend-seam.md §3); the workflow's own harness
# contract identical across every profile that declares a hook event; template
# render against a fixture workspace (required-missing and optional-missing
# directions);
# claims-table format consistency
# between gates.sh (machine contract) and the agent-facing template/docs.
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/fixtures/lib.sh"
. "$RS/lib/config.sh"
. "$RS/lib/owed.sh"
. "$RS/lib/compose.sh"

TSV="$WF_ROOT/config/stages.tsv"
TPLDIR="$WF_ROOT/runtime-docs/templates/prompts"
rows() { command grep -v '^#' "$TSV" | command grep -v '^$'; }
col() { printf '%s\n' "$1" | awk -F'\t' -v n="$2" '{print $n}'; }
STAGES=$(rows | cut -f1)
precond "stages.tsv has data rows" test "$(printf '%s\n' "$STAGES" | command grep -c .)" -ge 8

echo "-- row shape + session column vocabulary --"
badrows=$(rows | awk -F'\t' 'NF!=8{print $1}')
[ -z "$badrows" ] && ok "every row has 8 tab-separated columns" \
  || bad "rows with wrong column count: $badrows"
while IFS= read -r r; do
  s=$(col "$r" 1); m=$(col "$r" 3)
  case "$m" in cold|warm-author|warm-reviewer) : ;;
    *) bad "stage $s session column '$m' outside cold|warm-author|warm-reviewer" ;;
  esac
done < <(rows)
ok "session column vocabulary closed (violations reported above if any)"
for s in precheck postcheck split-check; do
  m=$(rows | awk -F'\t' -v s="$s" '$1==s{print $3}')
  [ "$m" = "cold" ] && ok "review stage $s row is cold (round-1 independence)" \
    || bad "review stage $s session column is '$m', must be cold"
done

echo "-- transition-table totality --"
tsv_totality() { # rows on stdin -> violation lines on stdout
  local r s verdicts map v pair tgt
  while IFS= read -r r; do
    s=$(col "$r" 1); verdicts=$(col "$r" 5); map=$(col "$r" 6)
    for v in $(printf '%s' "$verdicts" | tr '|' ' '); do
      tgt=$(printf '%s' "$map" | tr ',' '\n' | awk -F: -v v="$v" '$1==v{print $2}')
      [ -n "$tgt" ] || echo "($s, $v) has no next-target in the map"
    done
    for pair in $(printf '%s' "$map" | tr ',' ' '); do
      v=${pair%%:*}; tgt=${pair#*:}
      printf '|%s|' "$verdicts" | command grep -qF "|$v|" \
        || echo "($s) maps verdict '$v' not in its closed vocabulary '$verdicts'"
      case "$tgt" in
        HALT_class_u|HALT_blocked|COMPLETE|slice_loop|next_slice) : ;;
        *) command grep -qxF "$tgt" <<< "$STAGES" \
             || echo "($s, $v) -> '$tgt' is neither a stage nor a terminal" ;;
      esac
    done
  done
}
viol=$(rows | tsv_totality)
[ -z "$viol" ] && ok "every (stage, verdict) maps; every target is a stage or terminal" \
  || bad "totality violations: $viol"
# non-vacuity: a fabricated broken row must be flagged in both directions
viol=$(printf 'ghost\tslice\tcold\tx;handoff\tgood|dangling\tgood:nowhere\tR=cards/author.md\t\n' | tsv_totality)
command grep -q "dangling" <<< "$viol" \
  && ok "validator catches an unmapped verdict (known-bad fires)" \
  || bad "validator MISSED an unmapped verdict — vacuous totality check"
command grep -q "nowhere" <<< "$viol" \
  && ok "validator catches a dangling target (known-bad fires)" \
  || bad "validator MISSED a dangling next-target"

echo "-- template files per session column (+ review warm variants) --"
while IFS= read -r r; do
  s=$(col "$r" 1); m=$(col "$r" 3)
  case "$m" in cold) w=cold ;; *) w=warm ;; esac
  [ -f "$TPLDIR/$s.$w.md" ] && ok "template $s.$w.md exists (session column $m)" \
    || bad "template $s.$w.md ABSENT for session column $m"
done < <(rows)
for s in precheck postcheck; do
  [ -f "$TPLDIR/$s.warm.md" ] && ok "$s.warm.md exists (rounds >= 2 reuse warm)" \
    || bad "$s.warm.md ABSENT but rounds >= 2 go warm"
done

echo "-- ferry decide_mode: every selectable template mode has a file --"
# Contract (architecture §7 + the manifest-render rule): spawn mode may degrade (all_cold, missing
# warm_resume, dead held session) but the TEMPLATE is always the stage's static
# variant — warm templates are written to work identically in cold-fallback.
base=$(sc_tmpdir)
read -r repo branch < <(mk_repo "$base/repo")
fws=$(mk_full_ws "$base" closuretopic "$repo" "$branch")
hf=$(mk_headless_ferry)
dm() { # ws stage round extra-topic-kv -> "spawn tpl"
  ( set +u
    printf '%s\n' "$4" > "$1/config/topic.kv"
    . "$hf" "$1" 2>/dev/null
    G_STAGE=$2; G_ROUND=$3; G_SLICE=01; G_ATTEMPT=0
    decide_mode author "$WF_ROOT/config/backends/claude.kv" )
}
t() { # desc stage round topickv want
  local got
  got=$(dm "$fws" "$2" "$3" "$4" | tail -1)
  [ "$got" = "$5" ] && ok "$1 -> '$got'" || bad "$1 — want '$5' got '$got'"
}
t "spec round 1"                       spec       1 "" "cold cold"
t "split (warm-author row)"            split      1 "" "warm-author warm-author"
t "precheck round 1 stays cold"        precheck   1 "" "cold cold"
t "precheck round 2 goes warm"         precheck   2 "" "warm-reviewer warm-reviewer"
t "postcheck round 2 goes warm"        postcheck  2 "" "warm-reviewer warm-reviewer"
t "split-check round 2 STAYS COLD (no split-check.warm.md exists)" \
                                       split-check 2 "" "cold cold"
t "all_cold forces cold SPAWN but keeps the static template" \
                                       split      1 "all_cold=true" "cold warm-author"
nowarm=$(sc_tmpdir)/decl.kv
command grep -v '^cap=' "$WF_ROOT/config/backends/claude.kv" > "$nowarm"
echo "cap=pty,subagent,stop_gate,heartbeat" >> "$nowarm"
got=$( ( set +u; . "$hf" "$fws" 2>/dev/null; G_STAGE=split; G_ROUND=1; G_SLICE=01
         decide_mode author "$nowarm" 2>/dev/null ) | tail -1 )
[ "$got" = "cold warm-author" ] \
  && ok "missing warm_resume degrades spawn to cold, template unchanged -> '$got'" \
  || bad "warm_resume degradation — want 'cold warm-author' got '$got'"
rm -f "$fws/config/topic.kv"
# closure: every tpl word decide_mode can emit resolves to an existing file
for pair in "spec cold" "split warm" "precheck cold" "precheck warm" \
            "postcheck cold" "postcheck warm" "split-check cold"; do
  s=${pair% *}; w=${pair#* }
  [ -f "$TPLDIR/$s.$w.md" ] && ok "reachable template $s.$w.md exists" \
    || bad "reachable template $s.$w.md ABSENT"
done

echo "-- manifest placeholder closure --"
GLOBALS="STAGE SLICE ROUND WORKSPACE RECORD_SH NONCE ATTEMPT IMPLEMENTER_MODEL IMPLEMENTER_EFFORT stage slice round workspace workflow_root nonce"
manifest_names() { # row -> names of col7;col8 entries
  { col "$1" 7; col "$1" 8; } | tr ';' '\n' | awk -F= 'NF>1{print $1}'
}
tpl_placeholders() { command grep -oE '\{[A-Za-z_]+\}' "$1" | tr -d '{}' | sort -u; }
check_manifest() { # row tplfile -> violations
  local names p _cm_rc
  names="$(manifest_names "$1") $GLOBALS"
  for p in $(tpl_placeholders "$2"); do
    # THE EXPERIMENT (work order 4 item 5, owner-ruled): distinguish grep's
    # "no match" (rc 1) from "the match did not complete" (rc >= 2). Until now `||`
    # read ANY non-zero as no-match, so an error became a VERDICT — and this is
    # the arm that has now falsely accused the tree three times, twice naming a
    # placeholder that `$GLOBALS`, a static string literal in this file, is
    # guaranteed to contain. A value that was never derived cannot have been
    # derived wrongly, so the matcher itself is what is left to suspect.
    # The lead is a measured learning-loop observation: GNU grep 3.4 returning
    # rc=2 under an exported LC_ALL=C, and both preconditions hold here (check.sh
    # and fixtures/lib.sh each export LC_ALL=C; this box runs grep 3.4). The
    # detail that does NOT fit is stated so nobody reads this as a conclusion:
    # that entry measured a pattern-parsing path, and this call uses -F, a fixed
    # string. The idiom occurs on 653 lines across 41 files under self-check/
    # (measured; the one further hit is a comment), so what this arm reads is a
    # class, not one site.
    #
    # rc=141 IS ITS OWN ARM, and getting that wrong was the first version's
    # defect: 141 does not mean the matcher failed, it means the matcher RAN,
    # MATCHED and exited first, and printf took SIGPIPE — pipefail then hands the
    # pipeline the producer's status. Reporting it as a matcher failure would
    # have inverted the truth on first contact. It was believed unreachable
    # here — $names is only 175-256 bytes — and then FIRED, three times in one
    # run: bash's printf writes once per argument, so an early match ends grep
    # while later arguments are still being written, whatever the total size.
    # The producer is therefore a here-string (written before grep starts), and
    # the arm stays for whoever turns it back into a pipe.
    command grep -qxF "$p" <<< "$(printf '%s\n' $names)"; _cm_rc=$?
    case $_cm_rc in
      0) : ;;
      1) echo "template $(basename "$2") placeholder {$p} has no manifest/global entry" ;;
      141) echo "SIGPIPE rc=141 testing {$p} against the manifest/global set of $(basename "$2") — this is NOT a verdict about the tree and NOT a matcher failure: grep MATCHED and exited early, printf took SIGPIPE, pipefail surfaced the producer. The needle IS present; this is a FALSE RED. Record it as an iteration-log observation (a matcher failure under load)." ;;
      *) echo "MATCHER ERROR rc=$_cm_rc testing {$p} against the manifest/global set of $(basename "$2") — this is NOT a verdict about the tree: the match DID NOT COMPLETE. Not 'grep never ran' — GNU grep returns 2 on error even with matches already delivered (97-iterlog's ruling on this same split). Record it as an iteration-log observation (a matcher failure under load); it is the reading that arm has been waiting for." ;;
    esac
  done
  local n
  for n in $(manifest_names "$1"); do
    command grep -qF "{$n}" "$2" \
      || echo "manifest item $n of stage $(col "$1" 1) never appears in $(basename "$2")"
  done
}
while IFS= read -r r; do
  s=$(col "$r" 1); m=$(col "$r" 3)
  case "$m" in cold) w=cold ;; *) w=warm ;; esac
  tpls="$TPLDIR/$s.$w.md"
  case "$s" in precheck|postcheck) tpls="$tpls $TPLDIR/$s.warm.md" ;; esac
  for tp in $tpls; do
    [ -f "$tp" ] || continue
    viol=$(check_manifest "$r" "$tp")
    [ -z "$viol" ] && ok "stage $s <-> $(basename "$tp") placeholders closed" \
      || bad "$viol"
  done
done < <(rows)
badtpl=$(sc_tmpdir)/x.md
printf '{ROLE_CARD} {BOGUS_ITEM}\n' > "$badtpl"
viol=$(check_manifest "$(rows | head -1)" "$badtpl")
command grep -q "BOGUS_ITEM" <<< "$viol" \
  && ok "validator catches an undeclared placeholder (known-bad fires)" \
  || bad "placeholder validator vacuous — {BOGUS_ITEM} not flagged"

echo "-- workflow docs a prompt CITES are workflow docs its manifest HANDS OVER --"
# stages.tsv's header rule ("an artifact a stage's checklist names is an artifact
# its manifest owes"), for the one class checkable without reading prose. If a
# stage's prompt binds it to `review-standards.md` §4, that doc is an INPUT --
# not because reading it becomes likelier, but because compose_fingerprint
# hashes manifest-RESOLVED input content and nothing else, so left out, an owner
# edit to the contract the stage is graded against is invisible to its novelty
# check and a retry parks no_novelty.
# BOUNDARY: the corpus is runtime-docs/'s top-level *.md, enumerated from the
# directory so a new doc is covered the day it lands. Role cards are out of it
# deliberately -- ROLE_CARD already carries them, per role, in every row.
WFDOCS=$(cd "$WF_ROOT/runtime-docs" && ls *.md 2>/dev/null)
precond "runtime-docs has top-level docs to check" test -n "$WFDOCS"
manifest_values() { # row -> path-patterns of col7;col8 entries
  { col "$1" 7; col "$1" 8; } | tr ';' '\n' | awk -F= 'NF>1{print $2}'
}
check_docs() { # row tplfile -> violations
  local d
  for d in $WFDOCS; do   # cited as a backticked reference in the template body
    command grep -qE '`[^`]*'"$(printf '%s' "$d" | sed 's/\./\\./g')"'[^`]*`' "$2" || continue
    manifest_values "$1" | command grep -qxF "$d" \
      || echo "stage $(col "$1" 1): $(basename "$2") cites \`$d\` as binding but the manifest never hands it over (stages.tsv header rule; and its content stays out of compose_fingerprint)"
  done
}
while IFS= read -r r; do
  s=$(col "$r" 1); m=$(col "$r" 3)
  case "$m" in cold) w=cold ;; *) w=warm ;; esac
  tpls="$TPLDIR/$s.$w.md"
  case "$s" in precheck|postcheck) tpls="$tpls $TPLDIR/$s.warm.md" ;; esac
  for tp in $tpls; do
    [ -f "$tp" ] || continue
    viol=$(check_docs "$r" "$tp")
    [ -z "$viol" ] && ok "stage $s <-> $(basename "$tp") cited workflow docs all in the manifest" \
      || bad "$viol"
  done
done < <(rows)
# Known-bad, both halves: a template citing a doc the row omits must fire, and
# the SAME template must fall silent once the row carries it -- otherwise the
# arm could be passing because the citation regex matches nothing.
docbad=$(sc_tmpdir)/doc.md
printf 'goals: per `operations.md` §8.\n' > "$docbad"
onerow=$(rows | awk -F'\t' '$1=="spec"')
command grep -q 'operations.md' <<< "$(check_docs "$onerow" "$docbad")" \
  && ok "doc-citation validator fires on a cited-but-unhanded workflow doc (known-bad)" \
  || bad "doc-citation validator vacuous — a template citing \`operations.md\` against spec's row was not flagged"
fixedrow=$(printf '%s\n' "$onerow" | awk -F'\t' 'BEGIN{OFS="\t"} {$7=$7";OPS=operations.md"; print}')
[ -z "$(check_docs "$fixedrow" "$docbad")" ] \
  && ok "doc-citation validator falls silent once the row carries the entry (good direction)" \
  || bad "doc-citation validator still flags \`operations.md\` after the manifest gained it — it is not reading the manifest values"

echo "-- owed items all resolve in lib/owed.sh (functional, rc never 2/3) --"
n_items=0
while IFS= read -r s; do
  sl=01; [ "$(rows | awk -F'\t' -v s="$s" '$1==s{print $2}')" = "topic" ] && sl=00
  while IFS= read -r item; do
    [ -n "$item" ] || continue
    n_items=$((n_items + 1))
    out=$(_owed_item_check "$fws" "$s" "$sl" "" "" "" "$item" 2>&1); rc=$?
    case $rc in 0|1) : ;;
      *) bad "owed item '$item' (stage $s) hit rc $rc: $out" ;;
    esac
  done < <(owed_derive "$fws" "$s" "$sl")
done <<< "$STAGES"
precond "owed closure walked N>0 items (saw $n_items)" test "$n_items" -ge 15
ok "every derived owed item has a home mapping (violations above if any)"
assert_rc 2 "an unmapped owed item is rc 2 (known-bad fires)" -- \
  _owed_item_check "$fws" spec 01 "" "" "" bogus_item

echo "-- schema.kv covers every config key the scripts read (grep-derived) --"
keys=$(command grep -rhoE '(config_get|cfg) "?[A-Za-z0-9_.${}*-]+' "$RS" \
  | awk '{print $2}' | tr -d '"' \
  | sed -e 's/\${G_STAGE}/impl/g' -e 's/\$G_STAGE/impl/g' \
        -e 's/\${stage}/impl/g'   -e 's/\$stage/impl/g' \
        -e 's/\${st}/impl/g'      -e 's/\$st\b/impl/g' \
        -e 's/\${role}/author/g'  -e 's/\$role/author/g' \
  | command grep -v '\$' | command grep -E '^[a-z]' \
  | command grep -E '\.|^all_cold$' | sort -u)   # every real key is dotted except all_cold; drops prose hits ("config_get unknown arg")
keys="$keys $(command grep -rhoE 'cap\.[a-z_]+' "$RS" | sort -u)"
nk=0
for k in $keys; do
  nk=$((nk + 1))
  _config_schema_type "$k" > /dev/null \
    || bad "script-read config key '$k' is NOT in schema.kv (closed vocabulary broken)"
done
precond "grep derived N>=12 keys (saw $nk)" test "$nk" -ge 12
ok "all script-read keys covered by schema.kv (violations above if any)"
_config_schema_type "no.such.key" > /dev/null \
  && bad "schema lookup vacuous — accepted an unknown key" \
  || ok "schema lookup rejects an unknown key (known-bad fires)"

echo "-- project.kv keys the scripts read are declared in config-and-adapters §3 --"
# The project adapter is deliberately NOT schema.kv-validated (its contract is
# the project's), so §3 IS its documentation — a key the code reads but §3
# never shows is a key no project author can know to declare.
p3=$(sed -n '/^## 3\./,/^## 4\./p' "$WF_ROOT/design/config-and-adapters.md")
precond "config-and-adapters §3 extracted" test "$(printf '%s\n' "$p3" | command grep -c .)" -ge 10
pkeys=$(command grep -rhoE 'project_get "\$[A-Za-z_]+" [a-z][A-Za-z0-9_.]*' "$RS" \
  | awk '{print $3}' | sort -u)
npk=0
for k in $pkeys; do
  npk=$((npk + 1))
  command grep -qF "$k" <<< "$p3" \
    || bad "project.kv key '$k' is read by the scripts but never appears in config-and-adapters §3 (an undocumented adapter key)"
done
precond "grep derived N>=6 literal project.kv keys (saw $npk)" test "$npk" -ge 6
ok "every literal project.kv key the scripts read is documented in §3 (violations above if any)"
command grep -qF "no.such.project.key" <<< "$p3" \
  && bad "§3 closure vacuous — a fabricated key read as documented" \
  || ok "a fabricated key is absent from §3 (known-bad fires)"

echo "-- the commit gate's scope selection: which checks can SEE a given change --"
# check.sh --changed decides this mechanically (maintenance.md §1). Its judgment
# half is pure, so it is exercised on fixed file lists rather than on whatever
# the tree happens to hold. Empty output means "run everything".
# Standalone-runnable: the runner exports SELFCHECK_DIR, an ad-hoc
# `bash checks/30-closure.sh` has none, and the check used to die unbound at
# this line — a check that cannot run alone is a check whose reds cannot be
# chased in isolation (paid for while diagnosing a suite flake: the standalone
# death masqueraded as a second failure mode). Default = this check's
# directory's PARENT (self-check/), two dirnames up from this file.
. "${SELFCHECK_DIR:-$(cd "$(dirname "$(dirname "${BASH_SOURCE[0]}")")" && pwd)}/check.sh"      # sourceable: the runner lives behind a main() guard
for f in runtime-scripts/ferry.sh config/stages.tsv self-check/checks/10-store.sh \
         runtime-docs/templates/prompts/impl.warm.md; do
  [ -z "$(printf '%s\n' "$f" | scope_for_files)" ] \
    && ok "a change to $f runs EVERYTHING (it can reach the driver)" \
    || bad "$f selected a subset: $(printf '%s\n' "$f" | scope_for_files | tr '\n' ' ')"
done
sub=$(printf 'design/architecture.md\nruntime-docs/review-standards.md\n' | scope_for_files)
[ -n "$sub" ] \
  && ok "a formal-doc-only change selects a subset ($(printf '%s' "$sub" | tr '\n' ' '))" \
  || bad "doc-only change did not select a subset — the gate is all-or-nothing again"
for name in xref closure verbs gates provenance-tags; do
  command grep -qxF "$name" <<< "$sub" \
    && ok "  subset includes $name (it reads the formal doc region)" \
    || bad "  subset LACKS $name, which greps design/ or runtime-docs/"
done
n_all=$(list_names | command grep -c .)
n_sub=$(printf '%s\n' "$sub" | command grep -c .)
[ "$n_sub" -lt "$n_all" ] \
  && ok "the subset is a PROPER subset ($n_sub of $n_all) — otherwise the flag buys nothing" \
  || bad "subset ($n_sub) is not smaller than the full set ($n_all)"
[ -z "$(printf '' | scope_for_files)" ] \
  && ok "an empty change list runs everything (fail-safe: no git, no diff, no answer)" \
  || bad "an empty change list selected a subset — a broken git read would under-verify"
for f in tools/gen.sh newdir/thing.kv stray-at-the-root.txt .githooks/commit-msg; do
  [ -z "$(printf '%s\n' "$f" | scope_for_files)" ] \
    && ok "an UNRECOGNISED path ($f) runs everything — the test knows what is inert, not what is dangerous" \
    || bad "$f was assumed safe: $(printf '%s\n' "$f" | scope_for_files | tr '\n' ' ')"
done
mixed=$(printf 'design/architecture.md\nruntime-scripts/ferry.sh\n' | scope_for_files)
[ -z "$mixed" ] \
  && ok "one driver-side file among doc files still runs everything (one byte is enough)" \
  || bad "a mixed change selected a subset: $(printf '%s' "$mixed" | tr '\n' ' ')"
# and the git half, against a fixture repo: a NEW file is untracked, so `diff`
# alone cannot see it — yet adding a lib or a check is the change that most
# needs the whole suite.
sr=$(sc_tmpdir)/scoperepo
mkdir -p "$sr/design" "$sr/runtime-scripts/lib"
git init -q "$sr"
git -C "$sr" config user.email sc@example.invalid; git -C "$sr" config user.name selfcheck
echo base > "$sr/design/architecture.md"
git -C "$sr" add -A > /dev/null; git -C "$sr" commit -qm "chore: fixture base"
printf 'edit\n' >> "$sr/design/architecture.md"
[ -n "$(scope_for_changes "$sr")" ] \
  && ok "a tracked doc edit alone selects the subset (fixture control)" \
  || bad "doc-only fixture change ran everything — the control is broken, the next line proves nothing"
touch "$sr/runtime-scripts/lib/brand_new.sh"
[ -z "$(scope_for_changes "$sr")" ] \
  && ok "an UNTRACKED new driver file forces everything (git diff alone is blind to it)" \
  || bad "a brand-new lib was invisible: $(scope_for_changes "$sr" | tr '\n' ' ')"

echo "-- slice budgets: design text == shipped defaults (single authority) --"
for key in slice.max_diff_lines slice.max_commits slice.max_files; do
  dv=$(awk -F= -v k="$key" '$1==k{print $2}' "$WF_ROOT/config/defaults.kv")
  precond "defaults.kv declares $key (=$dv)" test -n "$dv"
  command grep -q "\`$key=$dv\`" "$WF_ROOT/design/review-and-slices.md" \
    && ok "design/review-and-slices.md states $key=$dv (matches config)" \
    || bad "design/review-and-slices.md does not state $key=$dv — design text and shipped default diverged (three-hand-copies drift)"
done
outd=$(sc_tmpdir)
while IFS= read -r r; do
  s=$(col "$r" 1); m=$(col "$r" 3)
  sl=01; [ "$(col "$r" 2)" = "topic" ] && sl=00
  out=$(compose_prompt "$fws" "$s" "$sl" 1 1 "n0nce$s" "$m" "$outd/$s.md" 2>&1); rc=$?
  if [ $rc -eq 0 ]; then ok "stage $s renders clean (rc 0, no unresolved placeholder)"
  else bad "stage $s render failed rc=$rc: $out"; fi
done < <(rows)
precond "rendered plan-validate prompt exists" test -s "$outd/plan-validate.md"
command grep -q "nonce=n0nceplan-validate" "$outd/plan-validate.md" \
  && ok "volatile header carries the live nonce" || bad "nonce missing from volatile header"
command grep -qE '^binding: kind=(code|doc) repo=/' "$outd/spec.md" \
  && ok "volatile header names the slice's bound checkout (the agent's only channel for it — cwd is not one)" \
  || bad "no binding line in the rendered header: $(command grep -m1 binding "$outd/spec.md")"
command grep -q "none (" "$outd/plan-validate.md" \
  && ok "optional-missing manifest item renders the literal 'none' marker (good direction)" \
  || bad "optional-missing item did not render 'none'"
if command grep -vE 'record.sh emit|--verdict' "$outd/plan-validate.md" | command grep -qE '\{[A-Z_]+\}'; then
  bad "unresolved {PLACEHOLDER} left in rendered prompt"
else ok "no unresolvable placeholder in the rendered prompt"; fi
mv "$fws/../plan.md" "$fws/../plan.hidden"
assert_rc 4 "required manifest item missing -> template_error (bad direction fires)" -- \
  compose_prompt "$fws" plan-validate 00 1 1 n2 cold "$outd/x.md"
assert_out_has "template_error" "park reason class named"
assert_out_has "PLAN" "the missing item is NAMED"
mv "$fws/../plan.hidden" "$fws/../plan.md"
assert_rc 4 "unknown stage -> template_error rc 4" -- \
  compose_prompt "$fws" ghost 00 1 1 n3 cold "$outd/x.md"

echo "-- claims-table format: gates_claims.sh machine contract == agent-facing docs --"
# lib/gates_claims.sh parses data rows as | type | claim | anchor | echo | range |
# command | — the contract moved there with the family; this arm compares the
# agent-facing docs against that literal, so it catches DOC drift, not gate drift
# (the type vocabulary itself is cross-checked in 60-gates).
spec_hdr=$(awk '/^## 6\. claims table/{on=1; next} on && /^\|/{print; exit}' \
  "$WF_ROOT/runtime-docs/templates/spec.md" | tr -d ' ')
precond "spec.md template has a claims-table header row" test -n "$spec_hdr"
[ "$spec_hdr" = "|type|claim|anchor|echo|range|command|" ] \
  && ok "templates/spec.md claims header matches the gates_claims.sh machine contract" \
  || bad "templates/spec.md claims header is '$spec_hdr' but gates_claims.sh parses |type|claim|anchor|echo|range|command| — an author following the template fails the emit gate"
rs_cols=$(awk '/^## 2\./{on=1; next} /^## /{on=0} on && /^\|/{print}' \
  "$WF_ROOT/runtime-docs/review-standards.md" \
  | command grep -vE '^\|[ :-]*\|' | awk -F'|' '{gsub(/^ +| +$/,"",$2); print $2}' \
  | command grep -v '^column$' | paste -sd, -)
[ "$rs_cols" = "type,claim,anchor,echo,range,command" ] \
  && ok "review-standards.md §2 column set matches the machine contract" \
  || bad "review-standards.md §2 columns are '$rs_cols', machine contract is type,claim,anchor,echo,range,command"

echo "-- gates surface reaches its demanded reader (tier-1 evidence is not a dead end) --"
command grep -v '^#' "$WF_ROOT/config/stages.tsv" | awk -F'\t' '$1=="postcheck"' \
  | command grep -q 'GATES=gates@nn' \
  && ok "postcheck manifest carries GATES=gates@nn (the reviewer is told to read harness-attested gate records — the manifest hands over THIS slice's)" \
  || bad "postcheck manifest has no GATES=gates@nn entry: reviewer.md/review-standards/postcheck prompts demand reading gate records, and C1 scopes the review to one slice"
gws=$(sc_tmpdir)/gwstopic/delivery
mkdir -p "$gws/.runtime/state" "$gws/.runtime/tmp"
( . "$RS/lib/state.sh"
  state_append "$gws" gates gate "v=1 t=1 gate=acceptance result=PASS sha=x tree=y dirty=z detail=fixture" ) > /dev/null
gpath=$( . "$RS/lib/state.sh"; . "$RS/lib/compose.sh"; _compose_resolve "$gws" 01 1 gates )
case "$gpath" in
  MISSING:*|NONE) bad "_compose_resolve cannot hand over the gates surface: $gpath" ;;
  *) [ -f "$gpath" ] && command grep -q 'gate=acceptance' "$gpath" \
       && ok "_compose_resolve resolves 'gates' to a readable surface dump" \
       || bad "'gates' resolved to '$gpath' but the dump is unreadable/empty" ;;
esac

echo "-- <surface>@nn hands over ONE slice's rows; rows with no slice field ride along --"
# gates and ledger rows are stamped slice=NN; a slice-level stage's reviewer
# or author is scoped to one slice (review-standards §9 scope), so the dump is filtered. A row
# with NO slice= field (run-level ledger events; attestations written before
# the stamp existed) cannot be attributed and is handed over rather than
# silently dropped — filtering is by a field that says otherwise, never by
# the absence of one.
( . "$RS/lib/state.sh"
  state_append "$gws" gates gate "v=1 t=2 slice=01 gate=caps result=PASS sha=x tree=y dirty=z detail=mine" > /dev/null
  state_append "$gws" gates gate "v=1 t=3 slice=02 gate=caps result=FAIL sha=x tree=y dirty=z detail=theirs" > /dev/null
  state_append "$gws" ledger ferry "v=1 t=1 event=run_init topic=fixture" > /dev/null
  state_append "$gws" ledger ferry "v=1 t=2 event=enter slice=01 stage=spec round=1" > /dev/null
  state_append "$gws" ledger ferry "v=1 t=3 event=enter slice=02 stage=spec round=1" > /dev/null )
for surf in gates ledger; do
  spath=$( . "$RS/lib/state.sh"; . "$RS/lib/compose.sh"; _compose_resolve "$gws" 01 1 "$surf@nn" )
  case "$spath" in
    MISSING:*|NONE) bad "_compose_resolve cannot hand over $surf@nn: $spath"; continue ;;
  esac
  [ -f "$spath" ] || { bad "$surf@nn resolved to a non-file: $spath"; continue; }
  command grep -qE '(^| )slice=01( |$)' "$spath" \
    && ok "$surf@nn for slice 01 carries the slice-01 row" \
    || bad "$surf@nn dropped the slice's own row: $(cat "$spath")"
  command grep -qE '(^| )slice=02( |$)' "$spath" \
    && bad "$surf@nn for slice 01 still carries a slice-02 row (no scoping happened): $(cat "$spath")" \
    || ok "$surf@nn for slice 01 excludes the other slice's row"
  command grep -qE '(^| )t=1( |$)' "$spath" \
    && ok "$surf@nn keeps the row with no slice field (unattributable rows are handed over, never dropped)" \
    || bad "$surf@nn dropped the fieldless row: $(cat "$spath")"
  case "$spath" in */surface.$surf.01.txt) ok "$surf@nn writes a slice-named dump ($(basename "$spath")) — never the whole-surface file" ;;
    *) bad "$surf@nn wrote to '$spath': the whole-surface dump name would let a stale full dump pass as the slice view" ;; esac
done
command grep -E "^turnover[[:space:]]" "$WF_ROOT/config/stages.tsv" | command grep -q 'LEDGER=ledger@nn' \
  && ok "turnover manifest hands over ledger@nn (its prompt calls the item 'this slice's stage transitions')" \
  || bad "turnover manifest still hands over the whole ledger while its prompt promises this slice's"
command grep -E "^close-out[[:space:]]" "$WF_ROOT/config/stages.tsv" | command grep -q 'LEDGER=ledger;' \
  && ok "close-out keeps the WHOLE ledger (it settles every slice — scoping there would lose the topic)" \
  || bad "close-out's LEDGER is no longer the whole surface"
for tpl in postcheck.cold.md postcheck.warm.md; do
  command grep -q '{GATES}' "$WF_ROOT/runtime-docs/templates/prompts/$tpl" \
    && ok "$tpl places the {GATES} manifest item" \
    || bad "$tpl never places {GATES} — the manifest entry would render nowhere"
done
# The {CONFORMANCE} ORDERING property (two anchors, owner-confirmed): the author's record must sit in the second-pass
# section, BELOW the ordered manifest — a reviewer reading the manifest in
# order must not have the author's verdicts in context before forming its
# own. The placeholder arm above is position-agnostic BY DESIGN (it asserts
# the entry renders), so the position itself is pinned here. COLD only,
# deliberate: both anchors are cold round-1 reviews, the warm template's
# goals carry no "formed before consulting" duty, and extending the rule to
# a delta round with zero anchors enforces an unpromoted pattern.
_pc="$WF_ROOT/runtime-docs/templates/prompts/postcheck.cold.md"
_sp=$(command grep -n '^## second pass' "$_pc" | head -1 | cut -d: -f1)
_cf=$(command grep -n '{CONFORMANCE}' "$_pc" | head -1 | cut -d: -f1)
[ -n "$_sp" ] && [ -n "$_cf" ] && [ "$_cf" -gt "$_sp" ] \
  && ok "postcheck.cold places {CONFORMANCE} below the second-pass heading (the ordered manifest carries no author verdicts)" \
  || bad "postcheck.cold's {CONFORMANCE} placement regressed: second-pass heading at line ${_sp:-absent}, the record at line ${_cf:-absent} — a reviewer reading the manifest in order would meet the author's verdicts first"

echo "-- plan_slice: the spec author is handed the plan's context + THIS slice's work items --"
# A plan is handed whole to every cold spec session (measured: 987 KB, the
# slice's own two items 34 KB of it, sitting mid-file where long-context
# recall is weakest). The excerpt is derived from the planning side's
# concatenation contract (context → items → invariants → rederivation →
# delta; item heading `# W-<id>:`, delta heading `# Delta`/`## Refine log`):
# everything before the first item, the items the charter's `## slice NN`
# section names, and everything after the last item up to the first history
# heading. Item headings at H1–H3 (a single-file plan predating the
# directory form carries them at H3). The full plan stays in the manifest as
# the citation authority; the excerpt is optional and says why when absent.
pws=$(sc_tmpdir)/ptopic/delivery
mkdir -p "$pws/.runtime/prompts" "$pws/slices"
cat > "$pws/../plan.md" <<'EOF'
# fixture plan v3

## Execution context

CONTEXT-LINE: gate rows everyone needs.

## Work items

### W-01: first item

W01-BODY: belongs to another slice.

### W-02: second item

W02-BODY: this slice's.

#### a sub-heading inside W-02

W02-SUB: still inside the block.

### W-03: third item

W03-BODY: this slice's too.

## Invariants

INVARIANT-LINE: plan-level, every slice reads it.

## Refine log — v2

HISTORY-LINE: provenance, never a spec input.

## Refine log — v3

MORE-HISTORY.
EOF
cat > "$pws/charters.md" <<'EOF'
# charters

## terminal decomposition table

W-01 is slice 01's; W-02 and W-03 are slice 02's.

## slice 01

binds W-01.

## slice 02

binds W-02 and W-03 (W-09 is named here but the plan has no such item).

## slice 03

binds nothing the plan names.
EOF
xpath=$( . "$RS/lib/state.sh"; . "$RS/lib/compose.sh"; _compose_resolve "$pws" 02 1 plan_slice )
case "$xpath" in
  MISSING:*|NONE) bad "plan_slice did not resolve for slice 02: $xpath" ;;
  *)
    [ -f "$xpath" ] || bad "plan_slice resolved to a non-file: $xpath"
    for want in CONTEXT-LINE W02-BODY W02-SUB W03-BODY INVARIANT-LINE; do
      command grep -q "$want" "$xpath" && ok "excerpt keeps $want" || bad "excerpt lost $want"
    done
    for drop in W01-BODY HISTORY-LINE MORE-HISTORY; do
      command grep -q "$drop" "$xpath" && bad "excerpt still carries $drop" || ok "excerpt drops $drop"
    done
    command grep -q '^### W-02: second item$' "$xpath" \
      && ok "item headings ride verbatim (a path#heading anchor derived from the excerpt resolves in the plan)" \
      || bad "the W-02 heading was altered in the excerpt"
    command grep -q 'W-09' "$xpath" \
      && ok "an id the charter names but the plan lacks is NAMED in the excerpt (never silently missing)" \
      || bad "the excerpt says nothing about W-09, which the charter named and the plan lacks"
    case "$xpath" in */.runtime/prompts/plan.02.md) ok "the excerpt is a slice-named derived file under .runtime/prompts" ;;
      *) bad "excerpt path '$xpath' is not .runtime/prompts/plan.<slice>.md" ;; esac ;;
esac
# the directory-contract shape: H1 items, `# Invariants`, `# Delta` tail
cat > "$pws/../plan.md" <<'EOF'
# fixture plan v4

## Execution context

CONTEXT-LINE.

# W-1: first item

W1-BODY.

## sites

W1-SITES.

# W-2: second item

W2-BODY.

# Invariants

INVARIANT-LINE.

# Rederivation ledger — v4

REDERIVATION-LINE.

# Delta — v4 vs v3

DELTA-LINE.

## Refine log (this version)

HISTORY-LINE.
EOF
printf '# charters\n\n## slice 02\n\nbinds W-2.\n' > "$pws/charters.md"
xpath=$( . "$RS/lib/state.sh"; . "$RS/lib/compose.sh"; _compose_resolve "$pws" 02 1 plan_slice )
case "$xpath" in
  MISSING:*|NONE) bad "plan_slice did not resolve for the H1-item plan: $xpath" ;;
  *)
    for want in CONTEXT-LINE W2-BODY INVARIANT-LINE REDERIVATION-LINE; do
      command grep -q "$want" "$xpath" && ok "H1 form: excerpt keeps $want" || bad "H1 form: excerpt lost $want"
    done
    for drop in W1-BODY W1-SITES DELTA-LINE HISTORY-LINE; do
      command grep -q "$drop" "$xpath" && bad "H1 form: excerpt still carries $drop" || ok "H1 form: excerpt drops $drop"
    done ;;
esac
# absent section / no named items: optional item, reason stated
xpath=$( . "$RS/lib/state.sh"; . "$RS/lib/compose.sh"; _compose_resolve "$pws" 07 1 plan_slice )
case "$xpath" in
  MISSING:*"## slice 07"*) ok "no charter section for the slice -> MISSING naming the section (renders as none (<reason>))" ;;
  *) bad "no charter section should be MISSING with the section named; got: $xpath" ;;
esac
printf '# charters\n\n## slice 02\n\nbinds nothing by id.\n' > "$pws/charters.md"
xpath=$( . "$RS/lib/state.sh"; . "$RS/lib/compose.sh"; _compose_resolve "$pws" 02 1 plan_slice )
case "$xpath" in
  MISSING:*W-*) ok "a section naming no W-<id> -> MISSING saying so" ;;
  *) bad "a section with no item ids should be MISSING naming W-<id>; got: $xpath" ;;
esac
command grep -E "^spec[[:space:]]" "$WF_ROOT/config/stages.tsv" | command grep -q 'PLAN_SLICE=plan_slice' \
  && ok "spec manifest carries PLAN_SLICE=plan_slice" \
  || bad "spec manifest has no PLAN_SLICE item"
command grep -E "^spec[[:space:]]" "$WF_ROOT/config/stages.tsv" | awk -F'\t' '{print $7}' | command grep -q 'PLAN=plan.md' \
  && ok "spec keeps the FULL plan as a required item (the citation authority never leaves the manifest)" \
  || bad "spec's required manifest lost PLAN=plan.md"
command grep -q '{PLAN_SLICE}' "$WF_ROOT/runtime-docs/templates/prompts/spec.cold.md" \
  && ok "spec.cold.md places {PLAN_SLICE}" || bad "spec.cold.md never places {PLAN_SLICE}"
# the rendered spec prompt for the plain fixture (charter section names no
# items) carries the reason, and a real excerpt rides the fingerprint sidecar
command grep -q 'none (.*W-' "$outd/spec.md" \
  && ok "the rendered spec prompt says WHY the excerpt is none (the author reads the full plan, knowingly)" \
  || bad "rendered spec prompt's PLAN_SLICE line: $(command grep -n 'plan' "$outd/spec.md" | head -3)"
printf '# charters\n\n## slice 02\n\nbinds W-2.\n' > "$pws/charters.md"
printf 'repo=%s\nbranch=%s\n' "$repo" "$branch" > "$pws/project.kv"
( . "$RS/lib/state.sh"; printf 'id=02 status=active risk=low title=two rederive=0\n' | state_set "$pws" slices ferry ) > /dev/null
compose_prompt "$pws" spec 02 1 1 nPS cold "$outd/pspec.md" > /dev/null 2>&1 \
  && ok "spec renders with a real excerpt (rc 0)" || bad "spec render with an excerpt failed"
command grep -q 'plan.02.md' "$outd/pspec.md.inputs" \
  && ok "the excerpt is a manifest-resolved input (the fingerprint hashes it)" \
  || bad "excerpt missing from the inputs sidecar: $(cat "$outd/pspec.md.inputs")"

echo "-- the learning loop has its reader: close-out receives observations + learnings --"
corow=$(command grep -v '^#' "$WF_ROOT/config/stages.tsv" | awk -F'\t' '$1=="close-out"')
command grep -q 'OBSERVATIONS=observations' <<< "$corow" \
  && command grep -q 'LEARNINGS=learnings' <<< "$corow" \
  && ok "close-out manifest hands over observations + learnings (its prompt owes tidying them — a write-only surface is a landfill, not a loop)" \
  || bad "close-out manifest lacks observations/learnings: the stage is ordered to tidy material it never receives"
( . "$RS/lib/state.sh"
  state_append "$gws" observations session "v=1 t=1 by=session text=fixture-observation" ) > /dev/null
opath=$( . "$RS/lib/state.sh"; . "$RS/lib/compose.sh"; _compose_resolve "$gws" 00 1 observations )
case "$opath" in
  MISSING:*|NONE) bad "_compose_resolve cannot hand over the observations surface: $opath" ;;
  *) [ -f "$opath" ] && command grep -q 'fixture-observation' "$opath" \
       && ok "_compose_resolve resolves 'observations' to a readable dump" \
       || bad "'observations' resolved to '$opath' but unreadable" ;;
esac
command grep -q '{OBSERVATIONS}' "$WF_ROOT/runtime-docs/templates/prompts/close-out.cold.md" \
  && command grep -q '{LEARNINGS}' "$WF_ROOT/runtime-docs/templates/prompts/close-out.cold.md" \
  && ok "close-out.cold.md places {OBSERVATIONS} and {LEARNINGS}" \
  || bad "close-out.cold.md never places the learning-loop inputs"

echo "-- state surfaces: the registry and the design enumeration agree --"
# [a-z_|]: surface names may carry underscores (notify_events is the first);
# the previous [a-z|] silently dropped its whole arm — 4 surfaces — and the
# floor precondition caught the drop rather than the vocabulary.
reg=$(sed -n '/_state_writers()/,/^}/p' "$RS/lib/state.sh" \
  | command grep -oE '^\s+[a-z_|]+\)' | tr -d ' )' | tr '|' '\n' | command grep -v '^\*$')
nreg=$(printf '%s\n' "$reg" | command grep -c .)
precond "registry extraction sees N>=15 surfaces (saw $nreg)" test "$nreg" -ge 15
s1=$(sed -n '/^## 1\./,/^## 2\./p' "$WF_ROOT/design/state-and-liveness.md")
missing_s=""
for s in $reg; do
  command grep -q "\`$s\`" <<< "$s1" || missing_s="$missing_s $s"
done
[ -z "$missing_s" ] \
  && ok "every registry surface is enumerated in state-and-liveness §1 (the authority names what the machine holds)" \
  || bad "surfaces in the registry but absent from state-and-liveness §1:$missing_s"

echo "-- no dead manifest slot: every store-surface pattern the TSV names must resolve --"
command grep -q 'SPEC_DIFF' <<< "$(command grep -v '^#' "$WF_ROOT/config/stages.tsv")" \
  && bad "SPEC_DIFF still in stages.tsv: a permanently-NONE slot with no producer anywhere in the tree (admission rule (c): deleted until a producer exists)" \
  || ok "no permanently-dead SPEC_DIFF slot in the manifests"

echo "-- landed SHAs are reachable from the close-out/turnover reading set --"
# Their goals enumerate landed work, but the ledger surface holds transition
# events with commit COUNTS only — cu→SHA lives in the progress surface, so
# the manifests must carry it or the goal is unreachable from the reading set.
command grep -E "^close-out[[:space:]]" "$WF_ROOT/config/stages.tsv" | command grep -q "PROGRESS=progress" \
  && ok "close-out manifest carries PROGRESS (cu→SHA source)" \
  || bad "close-out goals ask for landed SHAs but its manifest has no progress surface"
command grep -E "^turnover[[:space:]]" "$WF_ROOT/config/stages.tsv" | command grep -q "PROGRESS=progress" \
  && ok "turnover manifest carries PROGRESS" \
  || bad "turnover labels its ledger 'landed units' but carries no cu→SHA source"

echo "-- latest-review selection survives double-digit rounds and dotted paths --"
lrd=$(sc_tmpdir)/slices.d/01           # a dot IN the path — the sort field trap
mkdir -p "$lrd"
echo r2 > "$lrd/precheck.2.md"
echo r10 > "$lrd/precheck.10.md"
got=$(_compose_latest_review "$lrd" precheck)
[ "$(basename "$got")" = "precheck.10.md" ] \
  && ok "round 10 beats round 2 (numeric on the FILENAME field, not the path)" \
  || bad "latest-review picked '$got' — path-dependent sort feeds the wrong review to the prompt"

echo "-- the sessions record has ONE writer (a format with N copies grows no fields) --"
# The surface went without a `backend` field until a mid-run backend switch was
# measured being silently defeated at every warm stage — and the reason it went
# without one is that adding a field cost an edit at every write site plus a
# guess at the shape. rec_field is the single reader; state_sessions_row is the
# single writer. Fixtures are exempt on purpose: they fabricate rows, including
# deliberately legacy-shaped ones, to test what a reader does with them.
# Both directions in one test, and no exemption list to go stale: the field
# sequence must appear in exactly ONE runtime file, and that file must be the
# one holding the constructor.
lit=$(command grep -rl 'role=[^ ]* name=[^ ]* pane_pid=' "$RS" 2>/dev/null || true)
[ "$lit" = "$RS/lib/state.sh" ] \
  && ok "the sessions record's field sequence appears in exactly one runtime file, the constructor's own" \
  || bad "want only $RS/lib/state.sh to spell the sessions record; got:"$'\n'"$(printf '%s' "$lit" | sed 's/^/    /')"
# …and the constructor's own output still matches what rec_field reads.
row=$( . "$RS/lib/state.sh"; state_sessions_row author sess-x 11 22 33 44 /tmp/s nonceX warm claude )
for k in role name pane_pid pane_start server_pid server_start socket nonce mode backend t; do
  command grep -qE "(^| )$k=[^ ]+( |$)" <<< "$row" \
    || bad "the constructor drops '$k' — a reader asking for it gets nothing"
done
command grep -qE '(^| )backend=claude( |$)' <<< "$row" \
  && ok "every field a reader asks for is present, backend included ($(printf '%s' "$row" | wc -w) fields)" \
  || bad "constructor output: $row"

echo "-- every NAMED SWEEP CLASS the standard declares reaches the card that runs it --"
# A sweep class is a duty the ROUND owes, not an item the author picks — that
# distinction is the whole reason the phrase exists. It only holds if the hot
# card the author actually reads names the class too: review-standards is the
# reference, the card is what is in the session.
# Measured on the class that made this necessary: prose-side counts and line
# pins were nobody's named duty, so two slices shipped wrong ones through two
# refine rounds and two precheck rounds each — a spec forwarding classification
# pins from an older tree while neighbouring pins WERE corrected, and a
# cu-boundary count of 74/74 at a state whose census is 73, its own
# parenthetical naming 73.
# Both documents must declare the SAME SET of classes, extracted the same way.
# The first version of this arm grepped the card for the class's SUBJECT, which
# is present whether or not the card frames it as a class — so renaming the
# card's "named sweep class" to "a habit worth keeping" left the check green
# while deleting the only thing that makes it a duty. Mutation caught it.
sweep_subjects() { # file -> one lowercase subject per line
  command grep -oE '\*\*named sweep class[^*]*\*\*' "$1" 2>/dev/null \
    | sed 's/\*//g; s/^named sweep class[^A-Za-z]*//; s/\.$//' \
    | tr '[:upper:]' '[:lower:]' | command grep -v '^$' | sort -u
}
std_sweeps=$(sweep_subjects "$WF_ROOT/runtime-docs/review-standards.md")
card_sweeps=$(sweep_subjects "$WF_ROOT/runtime-docs/cards/author.md")
precond "review-standards declares at least one named sweep class" test -n "$std_sweeps"
if [ "$std_sweeps" = "$card_sweeps" ]; then
  ok "the standard and the author card name the same sweep classes ($(printf '%s\n' "$std_sweeps" | command grep -c .)): $(printf '%s' "$std_sweeps" | tr '\n' ';')"
else
  bad "the sweep-class sets differ — a duty the round owes cannot be a duty nobody is told about, and the card must not invent one either."$'\n'"    review-standards: $(printf '%s' "$std_sweeps" | tr '\n' ';')"$'\n'"    author card:      $(printf '%s' "$card_sweeps" | tr '\n' ';')"
fi

echo "-- a record format declares no value no writer can produce --"
# The decisions surface's status vocabulary was dead. review-standards §11's
# DP record declared `status=pending_audit | endorsed | pivoted | vetoed(→ …)`
# and the only writer (record.sh's decision verb) hardcodes pending_audit;
# grepping the whole runtime-scripts tree for the other three returns nothing.
# Measured across four slices of one topic: all 21 DP records read
# pending_audit — including DP 11/DP-2, which that slice's postcheck records
# as PIVOTED. A cold reader of the surface gets a wrong status for it, and the
# format is what told them the field means something.
# Anchored twice (slice 12 postcheck C0, slice 13 postcheck C0). The audit
# lives in review prose by design — §11's own "audited exactly once at the
# earliest reviewer checkpoint that follows" — so the fix is the format, and
# this arm keeps the vocabulary from growing back past its writers.
dpstatus=$(awk '/^dp=<slice>\/DP-/{on=1} on && /^status=/{print; exit}' \
           "$WF_ROOT/runtime-docs/review-standards.md")
precond "§11's DP record declares a status line (saw: ${dpstatus:-<none>})" test -n "$dpstatus"
unwritten=""
for v in $(printf '%s\n' "${dpstatus#status=}" | tr '|' '\n' \
           | sed 's/(.*//; s/[[:space:]]//g' | command grep -v '^$'); do
  command grep -rqF "status=$v" "$RS"/*.sh "$RS"/*/*.sh 2>/dev/null || unwritten="$unwritten $v"
done
[ -z "$unwritten" ] \
  && ok "every status the DP record declares has a writer in runtime-scripts ($dpstatus)" \
  || bad "declared but written by nothing:$unwritten — the decisions surface would carry a vocabulary that only ever reads as its default, and a reader trusts the format"

check_done
