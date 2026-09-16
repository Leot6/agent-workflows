#!/usr/bin/env bash
# lib/admission.sh — ferry.sh's admission half (backend-seam.md §2), split out
# under architecture §4.1's layout freedom to keep ferry.sh <=800 lines; only
# ferry.sh sources it. Uses the ferry's own globals/helpers (WS, park,
# park_config, cfg, state_audit, stage_session_mode, G_STAGE, G_ROUND) — it is
# a half, not a library with its own contract.
#
# One question, asked at one line: given this stage's resolved (role, backend)
# assignment, may we spawn on it, and in what session mode? The declaration
# answers all of it — the ferry never branches on a backend NAME.

check_admission() { # role decl
  local need caps c
  caps=$(pty_decl_get "$2" cap 2>/dev/null || true)
  case "$1" in
    author) need="pty subagent stop_gate heartbeat" ;;
    *) need="pty stop_gate heartbeat" ;;
  esac
  for c in $need; do
    printf ',%s,' "$caps" | command grep -qF ",$c," \
      || park template_error "backend declaration $2 lacks capability '$c' required by role $1 (capability admission; no silent fallback)"
  done
  if [ "$1" = "author" ] && ! printf ',%s,' "$caps" | command grep -qF ",heartbeat_covers_subagents,"; then
    state_audit "$WS" ferry "backend $2: no heartbeat_covers_subagents — impl budgets/working-age are the only sub-agent guards (stated at start)"
  fi
}

check_backend_proven() { # backend decl model effort
  # backend-seam.md §2: "Declarations are promises; the onboarding probe makes
  # them facts." check_admission above reads the declared CAPABILITY LIST — the
  # promise. Nothing ever asked whether that promise had been proven, and the
  # probe runs at launch over a different, smaller set: a backend named only in
  # a slice override, or written into the config after the door, reached a real
  # session unproven. So the fact is checked at the same line as the promise.
  # --verify READS the stored record's own identity (CLI version ⊕ declaration
  # ⊕ profile ⊕ the probe's own code ⊕ result=pass) and spawns nothing — it is
  # the probe's derivation rather than a copy of it. The cache is per workspace
  # and survives launches, so a backend proven on any earlier launch of this
  # topic stays proven and switching back to it mid-run just works.
  "$FERRY_DIR/probe.sh" --verify "$WS" "$2" "$1" > /dev/null 2>&1 && return 0
  # An invalid record is usually a CLI that self-updated under a live topic, and
  # that recovery is MECHANICAL — run the probe. Measured twice, nine slices
  # apart, and both times only `version=` differed (decl/profile/probe_impl all
  # matched); the host shipped three versions in one day and each transition
  # cost a park. template_error's other members need an INPUT fixed first; this
  # one needed a human to retype one unchanged command, and the pilot is
  # optional middleware, so a full-auto topic simply stopped. So the ferry does
  # the mechanical thing itself, once — bounded by probe.timeout, in the
  # probe's own scratch session, exactly as the preflight would — and parks
  # only on what a human could have answered.
  # model/effort are REQUIRED, not defaulted: this path SPAWNS, and an empty
  # one fills cmd.launch with a hole the placeholder guard cannot see (it only
  # catches an unresolved `{...}`).
  if [ -z "${3:-}" ] || [ -z "${4:-}" ]; then
    park template_error "check_backend_proven was called without a model/effort for backend '$1' — the inline re-probe spawns a session and cannot invent them (caller bug, not a topic input)"
  fi
  mkdir -p "$WS/.runtime/logs"
  state_audit "$WS" ferry "backend '$1' has no valid probe record at spawn (usually a CLI self-update) — re-proving inline instead of parking for the same command to be retyped"
  # Timestamped like the gate logs: a park cites this path as its evidence, and
  # a second re-probe must not overwrite the first one's. Declared then
  # assigned: a command substitution inside `local` masks its own status.
  local plog prc=0
  plog="$WS/.runtime/logs/probe-inline-$1-$(date +%s).log"
  "$FERRY_DIR/probe.sh" "$WS" "$2" "$1" "$3" "$4" > "$plog" 2>&1 || prc=$?
  case $prc in
    0)
      # Re-asked, never assumed: the guard's question is the RECORD's identity,
      # and a probe that exits 0 without leaving one it accepts must still park
      # rather than admit the spawn on its own say-so.
      if "$FERRY_DIR/probe.sh" --verify "$WS" "$2" "$1" > /dev/null 2>&1; then
        state_audit "$WS" ferry "backend '$1' re-proved inline at spawn (probe pass; no operator action was needed)"
        return 0
      fi
      park template_error "backend '$1' was re-proved inline at spawn, the probe PASSED, and the record it left still does not verify — the probe and this guard disagree about what identifies a pass. evidence: $WS/.runtime/probe/$1.kv and $plog" ;;
    4)
      # Exit 4 is "the BACKEND refused", and there are now two of those. The
      # reason is read from the record the probe just wrote rather than assumed,
      # because the two need OPPOSITE operator actions: quota names a reset time
      # to wait for, overload names none and is usually transient. Parking the
      # wrong one sends the operator to wait out a clock that does not exist.
      case "$(sed -n 's/^result=//p' "$WS/.runtime/probe/$1.kv" 2>/dev/null | tail -1)" in
        backend_overloaded)
          park backend_overloaded "backend '$1' is up and refusing (529-class) — found by the inline re-probe at spawn, not by the declaration being wrong. the pane's own line is in $WS/.runtime/probe/$1.kv (quota_line=) and $plog. no reset time is published for this state: relaunch on judgment rather than on a clock, and it is usually transient" ;;
        *)
          park backend_quota "backend '$1' is out of quota — found by the inline re-probe at spawn, not by the declaration being wrong. the pane's own line and the reset time it names are in $WS/.runtime/probe/$1.kv (quota_line=) and $plog; relaunch after the reset" ;;
      esac ;;
    *)
      park template_error "backend '$1' has no valid onboarding probe record and the inline re-probe FAILED (rc=$prc) — declarations are promises, the onboarding probe makes them facts (backend-seam.md §2). so this is the promise, not the clock: the record is $WS/.runtime/probe/$1.kv and what the probe said is $plog. a relaunch will not clear it — the declaration or the harness wiring is what has to change" ;;
  esac
}

decide_mode() { # role decl -> "<spawn_mode> <template_mode>"
  # Template mode is the stage's static variant (+ precheck/postcheck rounds
  # >= 2 warm) and never degrades: warm templates are written to work
  # identically in a reused session and in a cold-fallback one. Spawn mode may
  # degrade to cold (all_cold, backend without warm_resume) — named, never
  # silent. split-check is NOT in the round>=2 warm set: it is always cold
  # (fresh eyes on the decomposition; no split-check.warm.md exists).
  local mode tpl
  mode=$(stage_session_mode "$G_STAGE")
  case "$G_STAGE" in precheck|postcheck)
    [ "$G_ROUND" -ge 2 ] && mode=warm-reviewer ;;
  esac
  tpl=$mode
  local allcold
  allcold=$(cfg all_cold) || park_config all_cold
  [ "$allcold" = "true" ] && mode=cold
  case "$mode" in
    warm-*)
      if ! pty_decl_get "$2" cap 2>/dev/null | command grep -qF warm_resume; then
        state_audit "$WS" ferry "backend lacks warm_resume: $G_STAGE forced cold (degradation named)"
        mode=cold
      fi ;;
  esac
  printf '%s %s\n' "$mode" "$tpl"
}
