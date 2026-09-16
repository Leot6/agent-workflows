#!/usr/bin/env bash
# session/emit_checks.sh — the mechanical halves of `record.sh emit`, sourced by
# record.sh (never run directly): the Class U question-set door, the owed-set
# + emit-time gates pass, the fix-stage evidence join and the leak-evidence
# count. They share record.sh's refuse/fault and its libs; split out on the
# runtime-script cap (maintenance.md §1: split, never shave rules).

# A Class U halt's one owed artifact: the question set the owner rules from,
# slices/<nn>/halt.<n>.md, n = this slice's class_u halt count + 1 (derived
# from the handoff surface — never chosen, never reused), matching
# templates/halt.md's headings in order. The zero-context-ruler standard
# (review-standards §11) was prose only until this door: nothing named the file
# and nothing checked it. Sets _EMIT_CLASS_U_DOC to the workspace-relative path
# (the record's detail leads with it — the park message and the owner's page
# then carry it with no further plumbing).
_EMIT_CLASS_U_DOC=""
_emit_class_u_doc() { # ws slice -> _EMIT_CLASS_U_DOC
  local ws=$1 slice=$2 n doc tpl="$CONFIG_WORKFLOW_ROOT/runtime-docs/templates/halt.md"
  n=$(state_get "$ws" handoff 2>/dev/null \
    | command grep -E "(^| )slice=$slice( |$)" | command grep -cE '(^| )verdict=HALT_class_u( |$)' || true)
  n=$((${n:-0} + 1))
  doc="slices/$slice/halt.$n.md"
  [ -f "$ws/$doc" ] || refuse "a Class U halt owes its question set on disk: $ws/$doc (templates/halt.md — the owner rules from that text alone)"
  local gate_fail=0
  gates_caps "$ws" "$ws/$doc" || gate_fail=1
  gates_structure "$ws" "$ws/$doc" "$tpl" || gate_fail=1
  # The halt document is the ONE artifact with no reviewer between it and a
  # binding decision, and it used to be checked for heading structure and file
  # size and nothing else. Measured across one topic's two Class U halts: a
  # sentence attributed to "coding-rules §10's own words" that appears nowhere
  # in that file's 503 lines, and an option arithmetic that did not reconcile —
  # neither caught by a gate, a reviewer or a protocol step; both caught by one
  # person re-deriving before writing the ruling. templates/halt.md §7 now owes
  # a claims table, so this gate has a table to check rather than an exempt
  # artifact to record a bogus FAIL against (a measured shape; requiring the
  # table first is what keeps this off it).
  # The env sweep, on the same one-artifact-no-reviewer grounds: every
  # absolute path and every path:NN pin in the question set must resolve — the
  # measured halt cited `coding-rules §10` in prose, and a dead pin in an
  # option's evidence is the same class of defect the claims table catches for
  # echoes. The false-red risk was cleared for the claims half and holds here
  # by the same reading: `_gates_resolve_path` resolves into the workflow tree
  # (absolute · bound checkout · other checkout · workspace · workflow root),
  # so citing `runtime-docs/...` in a halt is legal, and a halt citing the
  # PLAN cites it relatively with no pin, which the sweep does not read.
  # This gate was pre-registered beside the claims one, as its second half.
  gates_env_sweep "$ws" "$ws/$doc" || gate_fail=1
  gates_claims "$ws" "$ws/$doc" || gate_fail=1
  [ $gate_fail -eq 0 ] || refuse "the question set $doc failed its emit gate (above) — fix the document, then emit again"
  _EMIT_CLASS_U_DOC=$doc
}

# Emit-time mechanical gates (cmd_emit's non-halt half #1): the owed-set
# refusal plus caps/claims/env-sweep/structure gates on the owed files, plus
# the impl/fix close gates (per-cu commit conventions + the acceptance PASS
# pinned to the CURRENT repo state). refuse/fault exit directly.
_emit_owed_and_gates() { # ws stage a_slice a_round skip [declared-ids]
  local ws=$1 stage=$2 a_slice=$3 a_round=$4 skip=$5 ids=${6:-}
  local missing rc
  missing=$(owed_check "$ws" "$stage" "$a_slice" --round "$a_round" --skip "$skip"); rc=$?
  [ $rc -eq 3 ] && fault "owed derivation hit a store/git fault: $missing"
  if [ $rc -ne 0 ]; then
    {
      echo "refuse: owed artifacts missing for stage '$stage' (slice $a_slice) — emission blocked until every owed item exists:"
      printf '%s\n' "$missing" | sed 's/^/  - /'
    } >&2
    exit 2
  fi

  # Emit-time mechanical gates (cheapest instrument; prevention): file caps on
  # the owed files; claims table + environment sweep on spec/review artifacts.
  local files="" item gate_fail=0
  while IFS= read -r item; do
    case "$item" in
      spec.md|conformance.md|turnover.md) files="$files $ws/slices/$a_slice/$item" ;;
      charters.md|closeout.md) files="$files $ws/$item" ;;
      validation_note) files="$files $ws/slices/00/validation_note.md" ;;
      splitcheck_review) files="$files $ws/slices/00/splitcheck.$a_round.md" ;;
      precheck_review|postcheck_review) files="$files $ws/slices/$a_slice/${item%_review}.$a_round.md" ;;
    esac
  done < <(owed_static_items "$stage")
  if [ -n "$files" ]; then
    # shellcheck disable=SC2086
    gates_caps "$ws" $files || gate_fail=1
    local f
    for f in $files; do
      case "$f" in
        */spec.md|*/precheck.*.md|*/postcheck.*.md|*/splitcheck.*.md)
          gates_claims "$ws" "$f" || gate_fail=1
          gates_env_sweep "$ws" "$f" || gate_fail=1 ;;
        # The three artifacts handed FORWARD to a later reader (charter → spec
        # author, turnover → next slice, close-out → owner): claims --optional
        # (their contract owes no table, but a table they carry is a set of
        # claims), and the env sweep — widened here only after the sweep's
        # absolute arm stopped reading a lone /word as a path (replayed over six
        # archived trees:
        # turnover FAIL 11/32 → 3/32, charters 3/6 → 1/6, close-out 2/6 → 0/6,
        # every survivor a real under-qualified citation or a dead absolute).
        */turnover.md|*/closeout.md|*/charters.md)
          gates_claims "$ws" "$f" --optional || gate_fail=1
          gates_env_sweep "$ws" "$f" || gate_fail=1 ;;
        # Every OTHER owed artifact (conformance, validation note), --optional
        # claims only. Measured over four archived topics: 336 rows lived here
        # unread, 160 of them in turnover.md — six of whose cite anchors were
        # line pins, which this gate refuses wherever it runs. The env sweep
        # stays off these two: conformance prose carries path FRAGMENTS
        # (/dependencies/<project>, 4 of 33 on the replay) and the
        # validation note cites the planning tree, which the archive move
        # kills — neither is a citation this door should refuse.
        *)
          gates_claims "$ws" "$f" --optional || gate_fail=1 ;;
      esac
      # The cite rows' SCOPE half, on every artifact the claims gate just read:
      # a `path#heading` anchor and its echo are verified independently over the
      # whole file, so a row can resolve one section away from its own evidence.
      # RECORDED, NEVER REFUSED, and the
      # shape is `spec_claims_tip`'s below: its own gate name, the same PASS/FAIL
      # the report buckets, read by the reviewer at §7 P4 and §9 C3. Every row
      # the archive sweep found is reading-correct with only the pointer off, and
      # refusing an emit over a pointer is a refusal the learning loop
      # already declined. Promotion is that call site's rule, unchanged: refusal
      # comes only if the FAIL rows prove real over live topics (VD-89).
      gates_claims_cite_scope "$ws" "$f" \
        || echo "cite anchors whose echo sits outside the anchored section: FAIL recorded (gate=claims_cite_scope; precheck P4 and postcheck C3 read it) — not refusing; re-anchor on the heading whose section holds the text" >&2
      case "$f" in
        # The spec was the ONE templated artifact with no structure gate, and
        # the cause was mechanical rather than a decision: gates_structure
        # compares template headings VERBATIM, and the spec template's H1 was
        # parameterised (`# spec — slice <nn>: <slice title>`) where review.md's
        # and halt.md's are constants, so it could never have matched. The H1 is
        # now a constant and the title rides the metadata block.
        # Audited before wiring, over every spec this workflow has shipped —
        # 26 across four archived topics: 25 already satisfy all eight template
        # section headings verbatim and in order. The one that does not inserted
        # a section and pushed `## 8. refine log` to `## 9`, which is exactly
        # what this gate is for: §7 P9's refine-log audit and every reader look
        # for that contract section where the template puts it. The check is
        # ADDITIVE-TOLERANT — extra headings between template ones pass — so a
        # spec is free to add `### 2.1` subsections, as shipped specs do.
        */spec.md)
          gates_structure "$ws" "$f" "$CONFIG_WORKFLOW_ROOT/runtime-docs/templates/spec.md" \
            || gate_fail=1 ;;
      esac
      case "$f" in
        */precheck.*.md|*/postcheck.*.md|*/splitcheck.*.md)
          # A review must match the review template's section structure — a
          # structure mismatch is a draft, not a verdict (mechanically checked).
          gates_structure "$ws" "$f" "$CONFIG_WORKFLOW_ROOT/runtime-docs/templates/review.md" \
            || gate_fail=1 ;;
      esac
      case "$f" in
        */charters.md)
          # Read by every later slice's spec author: a line pin here resolves
          # forever and means something else after the first edit above it.
          gates_line_pins "$ws" "$f" || gate_fail=1
          # …and hands each slice its own section: one `## slice NN` per
          # declared index id, or the author is handed everything or nothing.
          # shellcheck disable=SC2086
          [ -z "$ids" ] || gates_charter_sections "$ws" "$f" $ids || gate_fail=1
          # …and every anchor a section DECLARES in `plan-binds:` resolves to a
          # real heading in the plan the excerpt is cut from. Silent otherwise:
          # a charter that declares nothing is not that gate's business. The
          # plan sits beside the workspace, resolved the one way compose.sh
          # resolves it, so the two doors cannot drift on where it is.
          # shellcheck disable=SC2086
          [ -z "$ids" ] || gates_plan_binds "$ws" "$f" \
            "$(cd "$ws/.." 2>/dev/null && pwd)/plan.md" $ids || gate_fail=1 ;;
        */turnover.md)
          # The charter's read-life, one hand-over later: the spec stage's
          # manifest carries TURNOVER_PREV=slices/@prev/turnover.md, so this
          # file is read by the NEXT slice's author across a tree the previous
          # slice has just landed commits into — the exact window a pin rots
          # in. Measured over the six finished topics on disk:
          # 4 turnovers carried 13 pins, and one cited address
          # (`constraint_primitives.h:160`) held three unrelated constructs
          # across six commits of its own file, one transition landing INSIDE
          # the citing topic's own run. Reviews are deliberately NOT gated
          # here: a finding that reports pin rot must quote the pins.
          gates_line_pins "$ws" "$f" || gate_fail=1 ;;
      esac
      case "$f" in
        */conformance.md)
          # A conformance stamp identical to the spec's on a line the
          # baseline→HEAD diff displaced is a forwarded "re-read".
          gates_stamp_freshness "$ws" "$f" "$ws/slices/$a_slice/spec.md" \
            || gate_fail=1 ;;
      esac
    done
  fi

  # impl/fix close gates: completion evidence is the repo, attested in the
  # store (review-and-slices.md §1). Every landed cu re-passes the project's
  # commit conventions; the composite acceptance gate must hold a PASS record
  # pinned to the CURRENT tree (the author half of the one intentional
  # double-run) — or a named SKIP where the project declares none.
  if [ "$stage" = "impl" ] || [ "$stage" = "fix" ]; then
    local cu cu_sha reloc_flag
    while IFS= read -r cu; do
      [ -n "$cu" ] || continue
      cu_sha=$(state_get "$ws" progress 2>/dev/null \
        | awk -v s="$a_slice" -v c="$cu" '
            $0 ~ ("(^| )slice=" s "( |$)") && $0 ~ ("(^| )cu=" c "( |$)") {
              for(i=1;i<=NF;i++) if($i ~ /^sha=/){sub(/^sha=/,"",$i); v=$i}
            } END{print v}')
      [ -n "$cu_sha" ] || continue   # the owed check above already named it
      reloc_flag=""
      [ "$(owed_spec_cu_reloc "$ws" "$a_slice" "$cu")" = "yes" ] && reloc_flag="--relocation-only"
      # shellcheck disable=SC2086
      gates_commit "$ws" "$cu_sha" $reloc_flag || gate_fail=1
      # The LEDGER's unit set, not the spec's: a fix round registers units the
      # spec's commit-unit table never listed, and iterating that table let
      # them out of the per-commit attestation impl units get (owed.sh's
      # owed_ledger_cus carries the two measurements). Every unit reachable
      # from the spec list is reachable from here too — the sha lookup above
      # reads this same surface, so a spec cu with no progress row was already
      # skipped.
    done < <(owed_ledger_cus "$ws" "$a_slice")
    # EVERY project gate the project declares — build, lint, test, acceptance —
    # must hold a PASS record pinned to the CURRENT tree, not acceptance alone:
    # a slice shipped with zero build/lint/test rows while its siblings held
    # three, and only a reviewer reading five slices side by side noticed
    # Two ways to owe no pin: the project
    # declares no command for that gate, or the slice is doc-bound and has no
    # such concept at all (D-i); both record their SKIP through the one
    # decider, gates_project, so the surface says SKIP rather than nothing.
    local g gcmd repo_dir="" cur_sha cur_tree cur_dirty grec missing="" doc_bound
    doc_bound=$(binding_kind "$ws" "$a_slice")
    for g in build lint test acceptance; do
      gcmd=$(project_get "$ws" "$g" 2>/dev/null || true)
      if [ -z "$gcmd" ] || [ "$doc_bound" = "doc" ]; then
        gates_project "$ws" "$g" || true   # records the named SKIP
        continue
      fi
      if [ -z "$repo_dir" ]; then
        repo_dir=$(binding_repo "$ws" "$a_slice") || fault "project.kv lost its repo= mid-stage"
        # The record pins sha + tree + dirty fingerprint; the gate holds only if
        # ALL THREE still match — HEAD^{tree} alone cannot see uncommitted
        # edits, so a dirtied worktree would silently reuse a stale PASS.
        cur_sha=$(git -C "$repo_dir" rev-parse HEAD 2>/dev/null || echo none)
        cur_tree=$(git -C "$repo_dir" rev-parse 'HEAD^{tree}' 2>/dev/null || echo none)
        cur_dirty=$(gates_dirty_fp "$repo_dir")
      fi
      grec=$(state_get "$ws" gates 2>/dev/null | command grep -E "(^| )gate=$g( |$)" | tail -1 || true)
      if ! printf '%s\n' "$grec" | command grep -qE "(^| )result=PASS( |$)" \
         || ! printf '%s\n' "$grec" | command grep -qF " sha=$cur_sha " \
         || ! printf '%s\n' "$grec" | command grep -qF " tree=$cur_tree " \
         || ! printf '%s\n' "$grec" | command grep -qF " dirty=$cur_dirty "; then
        missing="$missing $g"
      fi
    done
    if [ -n "$missing" ]; then
      echo "project gate(s) with no PASS record pinned to the CURRENT repo state (sha=$cur_sha tree=$cur_tree dirty=$cur_dirty):$missing — never run, or the tree or worktree moved since the last run; run each at the reviewed tip first:" >&2
      for g in $missing; do echo "  $_RECORD_DIR/../lib/gates.sh project $ws $g" >&2; done
      gate_fail=1
    fi
    # The spec's own claims table, re-resolved at the LANDED tip and RECORDED
    # (gate=spec_claims_tip), never refused: the table was attested once at
    # spec-emit, and a slice's own commits can rewrite the text its behavior
    # rows echo. Landing the row here, at the
    # author's close, is what lets postcheck's C3 read it before reviewing.
    # Rows marked `baseline` in their range describe the tree BEFORE this slice
    # and are skipped. A trial with a VD row: refusal comes only if the FAIL
    # rows prove real over live topics.
    if [ -f "$ws/slices/$a_slice/spec.md" ]; then
      gates_claims "$ws" "$ws/slices/$a_slice/spec.md" --at-tip \
        || echo "spec claims at the landed tip: FAIL recorded (gate=spec_claims_tip; postcheck's C3 reads it) — not refusing; if the slice's own work invalidated a row, amend the spec before turnover" >&2
    fi
  fi
  [ $gate_fail -eq 0 ] || refuse "emit-time mechanical gates failed (see lines above; results attested in the gates surface) — fix and emit again"
}

# fix-round evidence (cmd_emit's non-halt half #2; owner-ruled): a fix may not
# report built on zero action. Evidence is EITHER a commit NEW since fix entry
# landed in THIS fix round, OR conformance.md changed since fix entry (a
# doc-only disposition is legal — but it must be visible). The ferry stamps
# conformance_baseline + fix_head_baseline at entry; a pre-existing commit
# re-registered into the progress ledger is bookkeeping, not evidence
# (ancestry-checked). No-op for every stage but fix.
_emit_fix_evidence() { # ws stage a_slice a_round
  local ws=$1 stage=$2 a_slice=$3 a_round=$4
  if [ "$stage" = "fix" ]; then
    local fix_ev=0 cb cur_cb fhb ev_sha fix_repo
    fhb=$(_active "$ws" fix_head_baseline 2>/dev/null || echo "")
    fix_repo=$(binding_repo "$ws" "$a_slice" 2>/dev/null || echo "")
    while IFS= read -r ev_sha; do
      [ -n "$ev_sha" ] || continue
      if [ -n "$fhb" ] && [ -n "$fix_repo" ] \
         && git -C "$fix_repo" merge-base --is-ancestor "$ev_sha" "$fhb" 2>/dev/null; then
        continue   # already contained in the fix-entry HEAD: not new work
      fi
      fix_ev=1; break
    done < <(state_get "$ws" progress 2>/dev/null \
       | command grep -E "(^| )slice=$a_slice( |$)" | command grep -E "(^| )stage=fix( |$)" \
       | command grep -E "(^| )round=$a_round( |$)" \
       | command grep -oE '(^| )sha=[^ ]+' | sed 's/^ *sha=//')
    if [ $fix_ev -eq 0 ]; then
      cb=$(_active "$ws" conformance_baseline 2>/dev/null || echo "")
      cur_cb=$(md5sum "$ws/slices/$a_slice/conformance.md" 2>/dev/null | awk '{print $1}')
      [ -n "$cb" ] && [ -n "$cur_cb" ] && [ "$cb" != "$cur_cb" ] && fix_ev=1
    fi
    [ $fix_ev -eq 1 ] || refuse "fix owes fix-round evidence: no progress record for (slice=$a_slice stage=fix round=$a_round) and conformance.md is unchanged since fix entry — a zero-action fix cannot report built (land commits via record.sh progress, or record the doc-only disposition in conformance.md)"
  fi
}

# Leak-class evidence (cmd_emit's non-halt half #3; owner-promoted
# on two anchors): a postcheck with substantive findings may not emit until
# each finding's leak_class is ON THE LEARNINGS SURFACE — review-standards §9
# C9 — because that surface is the only input the two-anchor judgment (§14)
# reads, and a classification that lives only in the review file never
# reaches it. Measured: a slice whose postcheck read `findings, substantive 2`
# and classified both left the surface with zero rows for the slice; another
# slice's rows each say they were written a round late. One row per
# substantive finding, keyed to THIS (slice, stage, round) — a round-1 row
# does not discharge round 2's findings. Same shape as the fix round's
# evidence rule above. No-op for every stage but postcheck and for a clean
# postcheck.
_emit_leak_evidence() { # ws stage a_slice a_round findings_substantive
  local ws=$1 stage=$2 a_slice=$3 a_round=$4 fsub=${5:-0}
  [ "$stage" = "postcheck" ] && [ "${fsub:-0}" -gt 0 ] || return 0
  local rows
  rows=$(state_get "$ws" learnings 2>/dev/null \
         | command grep -E "(^| )slice=$a_slice( |$)" | command grep -E "(^| )stage=postcheck( |$)" \
         | command grep -cE "(^| )round=$a_round( |$)" || true)
  [ "${rows:-0}" -ge "$fsub" ] \
    || refuse "postcheck owes its leak classes on the learnings surface: $fsub substantive finding(s), ${rows:-0} learnings row(s) for (slice=$a_slice stage=postcheck round=$a_round) — record each finding's class first, then emit (review-standards.md §9 C9; the surface, not the review file, is what the learning loop reads):
  $_RECORD_DIR/record.sh learn $ws --leak-class precheck|conformance|gate|novel --text '<the finding, one row each>'"
}
