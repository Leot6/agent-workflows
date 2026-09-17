#!/usr/bin/env bash
# lib/attempt.sh — ferry.sh's attempt half, split out under architecture §4.1's
# layout freedom to keep ferry.sh ≤800 lines; only ferry.sh sources it. Uses the
# ferry's own globals/helpers (WS, G_SLICE/G_STAGE/G_ROUND/G_ATTEMPT, park,
# park_config, cfg, sfield, sput, ledger, rec_field, sessions_entry,
# sessions_replace, stage_role, check_workflow_pin) — it is a half, not a
# library with its own contract.
#
# One question, asked once per turn of the loop: may this assignment spend
# another attempt, and what happens while it does? Budgets first (attempt count,
# then the two wall-clocks, both crediting parked time), then the spawn — cold
# or warm, composed prompt, injected — then the wait. It sits between the two
# halves that bound it: admission.sh decides whether a spawn is allowed at all
# and in which session mode, watch.sh owns the liveness stack this waits on.

check_budgets() {
  local n budget key="count.$G_SLICE.$G_STAGE.$G_ROUND" now started t0 wall
  n=$(sfield attempts "$key"); n=${n:-0}
  budget=$(cfg "stage.$G_STAGE.budget_attempts") || park_config "stage.$G_STAGE.budget_attempts"
  if [ -z "$budget" ]; then
    budget=$(cfg budget.stage_attempts) || park_config budget.stage_attempts
  fi
  if [ "$n" -ge "$budget" ]; then
    local lastfail reason
    lastfail=$(sfield attempts "lastfail.$G_SLICE.$G_STAGE")
    # Bounded respawn precedes every liveness park (design §4/§5): when the
    # budget was spent on one liveness class, the park NAMES that class —
    # park(idle)/park(dead) are the design's vocabulary for these ends.
    case "$lastfail" in
      idle) reason=idle ;;
      dead) reason=dead ;;
      *) reason=budget_attempts ;;
    esac
    park "$reason" "attempt budget exhausted for (slice=$G_SLICE stage=$G_STAGE round=$G_ROUND): $n/$budget attempts, last failure class '${lastfail:-none}'"
  fi
  # The wallclock budgets meter WORK: each cleared halt's parked interval is
  # credited by the resume gate (attempts parked.<slice> / run parked_total)
  # and subtracted here — an owner-level multi-hour park must not spend the
  # budget that exists to price thrash (a park is the one interval where no
  # thrash is possible). Absent keys read 0: pre-credit records compare
  # unchanged, no migration.
  local parked
  now=$(date +%s)
  # 00 is the TOPIC scope, not a slice — its stages are plan-validate, split and
  # split-check at the beginning and close-out at the very end, with the whole
  # delivery in between. `slice.00.started` is therefore the topic's own start,
  # and a slice cap applied to it prices the entire topic: measured at close-out
  # re-entry, 128394s of "working" whose every hour belonged to slices 09..15,
  # parking budget_wallclock on a stage that had just begun. The interval is not
  # left unpriced — the topic budget immediately below is the clock that owns it,
  # and these two would otherwise measure the same span under different caps.
  if [ "$G_SLICE" != "00" ]; then
    started=$(sfield attempts "slice.$G_SLICE.started"); started=${started:-$now}
    parked=$(sfield attempts "parked.$G_SLICE"); case "$parked" in ''|*[!0-9]*) parked=0 ;; esac
    wall=$(cfg budget.slice_wallclock) || park_config budget.slice_wallclock
    [ $((now - started - parked)) -gt "$wall" ] && park budget_wallclock "slice $G_SLICE wall-clock budget exceeded ($((now - started - parked))s working > ${wall}s; ${parked}s parked excluded)"
  fi
  t0=$(sfield run t_start); t0=${t0:-$now}
  parked=$(sfield run parked_total); case "$parked" in ''|*[!0-9]*) parked=0 ;; esac
  wall=$(cfg budget.topic_wallclock) || park_config budget.topic_wallclock
  [ $((now - t0 - parked)) -le "$wall" ] || park budget_wallclock "topic wall-clock budget exceeded ($((now - t0 - parked))s working > ${wall}s; ${parked}s parked excluded)"
}

run_attempt() {
  check_workflow_pin
  check_budgets
  local role backend decl model effort mode tplmode nonce prompt fp lastfail hist
  role=$(stage_role "$G_STAGE")
  backend=$(cfg "agent.$role.backend" --slice "$G_SLICE" --agent "$role") || park_config "agent.$role.backend"
  model=$(cfg "agent.$role.model" --slice "$G_SLICE" --agent "$role") || park_config "agent.$role.model"
  effort=$(cfg "agent.$role.effort" --slice "$G_SLICE" --agent "$role") || park_config "agent.$role.effort"
  decl="$WROOT/config/backends/$backend.kv"
  [ -f "$decl" ] || park template_error "backend declaration $decl absent (agent.$role.backend=$backend)"
  check_admission "$role" "$decl"
  check_backend_proven "$backend" "$decl" "$model" "$effort"
  local dm
  dm=$(decide_mode "$role" "$decl")
  mode=${dm%% *}; tplmode=${dm##* }
  nonce=$(printf '%s.%s.%s' "$(plat_now_ns)" $$ "$RANDOM" | md5sum | cut -c1-16)
  prompt="$WS/.runtime/prompts/$G_SLICE-$G_STAGE-r$G_ROUND-a$((G_ATTEMPT + 1)).md"
  local out
  out=$(compose_prompt "$WS" "$G_STAGE" "$G_SLICE" "$G_ROUND" $((G_ATTEMPT + 1)) "$nonce" "$tplmode" "$prompt") \
    || park template_error "$out"

  lastfail=$(sfield attempts "lastfail.$G_SLICE.$G_STAGE"); lastfail=${lastfail:-none}
  fp=$(compose_fingerprint "$WS" "$G_STAGE" "$G_SLICE" "$prompt" "$lastfail")
  hist=$(sfield attempts "fp.$G_SLICE.$G_STAGE")
  case ",$hist," in *",$fp,"*)
    park no_novelty "attempt fingerprint $fp matches the last-K history for (slice=$G_SLICE stage=$G_STAGE) — an identical retry is priced out, not worth its cost; change an owed artifact, the prompt, or rule" ;;
  esac
  hist=$(printf '%s,%s' "$fp" "$hist" | tr ',' '\n' | command grep -v '^$' | head -4 | paste -sd, -)
  sput attempts "fp.$G_SLICE.$G_STAGE=$hist" \
    "count.$G_SLICE.$G_STAGE.$G_ROUND=$(( $(sfield attempts "count.$G_SLICE.$G_STAGE.$G_ROUND" | command grep -E '^[0-9]+$' || echo 0) + 1 ))"

  # Pre-register the attempt BEFORE the agent can possibly run: record.sh
  # validates emits against the stage surface (state=running, active nonce)
  # and the sessions surface (nonce present) — a fast CLI can emit within
  # milliseconds of spawn/inject (the self-check drill's mock does), so both
  # surfaces must carry the attempt first. Session ids are completed after the
  # spawn returns them.
  local session pp pps sp sps socket ids spawned=cold entry now mode_src
  # WHY this attempt is cold, stamped on the spawn row beside WHAT it is.
  # `mode=cold` alone conflates two opposite things: a stage that is cold by
  # contract (the reviewer's independence, the spec's authority chain — a
  # price the design pays on purpose) and a warm-capable stage whose reuse
  # failed (a degradation, ~3x the cost for nothing). Measured over four
  # archived topics: **25** spawns where decide_mode wanted warm went cold —
  # 22 of the five warm-author stages plus 3 reviewer rounds >= 2 — of which
  # 22 carry a `cold-fallback (audited)` row and 3 carry nothing, the
  # no-held-session path writing no audit line. So the cost report could not
  # tell design from degradation, and reconstructing it needs BOTH surfaces
  # cross-referenced by hand: the audit message names the HELD session, never
  # the stage that failed to reuse it.
  # The value goes on the LEDGER rather than into a second audit line because
  # the cost instrument already pairs on ledger rows; an audit row would have
  # to be matched back by timestamp, and the audit message names the HELD
  # session, not the stage that failed to reuse it.
  if [ "$tplmode" = cold ]; then mode_src=designed          # cold by the stage contract
  elif [ "$mode" = cold ]; then mode_src=degraded           # decide_mode demoted it (all_cold / no warm_resume; audited there)
  else mode_src=no_session; fi                              # warm wanted and reachable — refined at each branch below
  now=$(date +%s)
  # Identity and LIVENESS are one atomic write. The six `live_*` keys have a
  # single writer, `_watch_stage_note`, and had no clear site anywhere in the
  # tree — so across a stage or attempt boundary the record carried a NEW
  # identity beside the PREVIOUS attempt's liveness until the new wait loop's
  # first tick. Measured 22s after a resume spawn: the panel showed a
  # zero-second-old stage as `busy · heartbeat 15s ago`, `idle 0s`, `elapsed
  # 24m / ceiling 3h00m` — all four the dead session's numbers.
  # Cleared rather than tested reader-side, and the reason is in `watch.sh`'s
  # clock-jump amnesty: line `spawn_t=$((spawn_t + gap))` shifts the LOCAL
  # parameter (`local … spawn_t=${12}`) and never writes back, so a reader
  # comparing `live_t` against the stored `spawn_t` would compare two values
  # the code deliberately allows to diverge. `_state_put_core` re-adds each
  # named key with the given value, so an empty value stores as empty and
  # every existing `[ -n … ]` guard in `monitor.sh` becomes correct with no
  # reader change at all — and `55-monitor` already asserts the resulting
  # contract (no `live_age` ⇒ no liveness row, `elapsed` falling back to
  # `spawn_t`), a state production could not reach after its first stage.
  sput stage "state=running" "nonce=$nonce" "attempt=$((G_ATTEMPT + 1))" "spawn_t=$now" "backend=$backend" \
    "live_class=" "live_hb_age=" "live_age=" "live_idle=" "live_working=" "live_t="
  G_ATTEMPT=$((G_ATTEMPT + 1))   # keep the global in step with the store — ledger/park lines report the live attempt
  if [ "$mode" != "cold" ]; then
    local wrole=${mode#warm-}
    entry=$(sessions_entry "$wrole")
    if [ -n "$entry" ]; then
      pp=$(rec_field "$entry" pane_pid); pps=$(rec_field "$entry" pane_start)
      sp=$(rec_field "$entry" server_pid); sps=$(rec_field "$entry" server_start)
      session=$(rec_field "$entry" name); socket=$(rec_field "$entry" socket)
      # Reuse needs TWO facts. Liveness says the pane is still there; it says
      # nothing about WHICH backend produced it, while :438 and the ledger both
      # stamp the newly resolved one — so a mid-run switch was recorded as
      # having happened and then silently defeated at every warm stage. The
      # loud case is a dead old backend; the quiet one is worse, the old
      # model's work delivered under the new model's name. `check_backend_proven` (lib/admission.sh)
      # advertises exactly this operation.
      # Two RESOLVED values compared, no backend NAME inspected
      # (lib/admission.sh's header). A row from before this field cannot prove a match,
      # so it cold-falls back: the safe direction, one warm reuse once.
      local held_backend
      held_backend=$(rec_field "$entry" backend)
      if [ "$(pty_alive "$pp" "$pps" "$sp" "$sps")" != "running" ]; then
        mode_src=dead_session
        state_audit "$WS" ferry "held session for $wrole dead: cold-fallback (audited)"
      elif [ "$held_backend" != "$backend" ]; then
        mode_src=backend_switch
        state_audit "$WS" ferry "held session for $wrole was produced by backend '${held_backend:-<unrecorded>}', this stage resolves backend '$backend': cold-fallback (audited)"
      else
        sessions_replace "$role" \
          "$(state_sessions_row "$role" "$session" "$pp" "$pps" "$sp" "$sps" "$socket" "$nonce" warm "$backend")"
        local irc=0 iout
        iout=$(pty_inject "$decl" "$session" "Read and execute $prompt" "$WS/.runtime" 2>/dev/null) || irc=$?
        if [ $irc -eq 0 ]; then
          spawned=warm; mode_src=warm
        elif [ $irc -eq 2 ]; then
          local sf; sf=$(_watch_save_screen "$WS" "$session")
          park operator_interference "warm re-activation refused: non-empty composer in $session (a human's half-typed text)" "$sf"
        else
          mode_src=reactivate_failed
          state_audit "$WS" ferry "warm re-activation failed (rc=$irc why=$(pty_inject_why "${iout:-}"), session $session): cold-fallback (audited)"
        fi
      fi
    fi
  fi
  if [ "$spawned" = "cold" ]; then
    session="delivery-$TOPIC-$G_SLICE-$G_STAGE"
    # A cold spawn DISPLACES the role's held session: tear it down before the
    # surface forgets its name, or it lives (invisible, unmonitored, holding
    # repo access) for the rest of the topic. Live entry -> fail-closed
    # teardown; dead entry -> drop with an audit note (reconcile fences tmux
    # leftovers at next start).
    entry=$(sessions_entry "$role")
    if [ -n "$entry" ] && [ "$(rec_field "$entry" name)" != "$session" ]; then
      local old_name
      old_name=$(rec_field "$entry" name)
      if [ "$(pty_alive "$(rec_field "$entry" pane_pid)" "$(rec_field "$entry" pane_start)" \
                        "$(rec_field "$entry" server_pid)" "$(rec_field "$entry" server_start)")" = "running" ]; then
        pty_teardown "$old_name" "$(rec_field "$entry" socket)" 2>/dev/null
        [ $? -eq 3 ] && park dead "teardown fail-closed: recorded tmux socket for $old_name is gone while the launcher generation lives — inspect manually; never started a replacement server"
        ledger "event=teardown role=$role session=$old_name displaced_by=$session"
      else
        state_audit "$WS" ferry "displaced held session $old_name already dead; dropped from the surface"
      fi
      sessions_replace "$role" ""
    fi
    if pty_reconcile "delivery-$TOPIC-" | command grep -qxF "$session"; then
      tmux kill-session -t "=$session" 2>/dev/null || true
      state_audit "$WS" ferry "fenced same-name stale session $session before cold spawn"
    fi
    local profile="$WS/.runtime/profile-$session.json" profile_src
    local log="$WS/.runtime/logs/$G_SLICE-$G_STAGE.log"
    # The profile is a pure function of THIS spawn's assignment: ONE
    # substitution from the template the RESOLVED declaration names, made at
    # the point where every input exists (role, slice, backend). It used to be
    # derived twice — launch.sh baked .runtime/profile.json from
    # agent.author.backend at TOPIC level and every spawn re-used that one file
    # — so the reviewer's declaration was never consulted and a slice override
    # never could be; it misfired invisibly only because two declarations
    # happen to name the same profile file. {SESSION_NAME} bakes the session
    # NAME into the hook command lines so the Stop gate can scope to its
    # caller; the name — not the nonce — survives warm reuse, so the baked
    # identity never goes stale and the gate resolves the live nonce by name.
    profile_src="$WROOT/config/$(pty_decl_get "$decl" profile)"
    sed -e "s|{WORKFLOW_ROOT}|$WROOT|g" -e "s|{WORKSPACE}|$WS|g" -e "s|{SESSION_NAME}|$session|g" \
        "$profile_src" > "$profile" \
      || park template_error "per-session profile render failed: $decl declares profile=$(pty_decl_get "$decl" profile 2>/dev/null || echo '<absent>'), which resolves to $profile_src"
    mkdir -p "$WS/.runtime/logs"
    sessions_replace "$role" \
      "$(state_sessions_row "$role" "$session" 0 0 0 0 pending "$nonce" cold "$backend")"
    if ! ids=$(pty_spawn_cold "$decl" "$session" "$model" "$effort" "$WS" "$profile" "$prompt" "$log"); then
      sessions_replace "$role" ""
      sput attempts "lastfail.$G_SLICE.$G_STAGE=spawn_failed"
      sput stage "state=failed"
      ledger "event=spawn_failed slice=$G_SLICE stage=$G_STAGE"
      return 0
    fi
    pp=$(rec_field "$ids" pane_pid); pps=$(rec_field "$ids" pane_start)
    sp=$(rec_field "$ids" server_pid); sps=$(rec_field "$ids" server_start)
    socket=$(rec_field "$ids" socket)
    sessions_replace "$role" \
      "$(state_sessions_row "$role" "$session" "$pp" "$pps" "$sp" "$sps" "$socket" "$nonce" cold "$backend")"
  fi
  # backend joins model and effort: it is the one resolved value nothing else
  # records, and the assignment is what PRODUCED this stage's evidence. No
  # slice-end field to match it — ledger() stamps every record and slice
  # completion is already `advance … verdict=done`; the end is a read, not a
  # write (config-and-adapters.md §6: the completion source is the ledger,
  # never the attempts surface).
  ledger "event=spawn slice=$G_SLICE stage=$G_STAGE round=$G_ROUND attempt=$G_ATTEMPT mode=$spawned mode_src=$mode_src session=$session backend=$backend model=$model effort=$effort"
  wait_attempt "$decl" "$session" "$pp" "$pps" "$sp" "$sps" "$nonce" "$now"
}

wait_attempt() { # decl session pp pps sp sps nonce spawn_t
  local out rc
  out=$(watch_wait "$WS" "$1" "$2" "$3" "$4" "$5" "$6" "$7" "$G_STAGE" "$G_SLICE" "$G_ATTEMPT" "$8"); rc=$?
  [ $rc -eq 3 ] && die_store "store fault inside wait loop"
  case "$out" in
    RECORD)
      sput stage "state=done"
      ledger "event=record slice=$G_SLICE stage=$G_STAGE nonce=$7" ;;
    "FAIL "*)
      local cls=${out#FAIL }
      sput attempts "lastfail.$G_SLICE.$G_STAGE=$cls"
      sput stage "state=failed"
      ledger "event=attempt_failed slice=$G_SLICE stage=$G_STAGE class=$cls" ;;
    "PARK "*)
      # Fields 2 and 3 are the protocol (reason, screen file); anything after
      # is the wait loop's own words for THIS park, and they ride into the halt
      # detail. A park whose remedy depends on a fact only the pane knows — a
      # backend's reset time, which differs per CLI and per plan — must carry
      # that fact where the operator and the notification both read, not only
      # in a screen file someone has to open.
      local reason screen wdetail
      reason=$(printf '%s\n' "$out" | awk '{print $2}')
      screen=$(printf '%s\n' "$out" | awk '{print $3}')
      wdetail=$(printf '%s\n' "$out" | cut -d' ' -f4- | tr '\n\t' '  ')
      [ "$wdetail" = "$out" ] && wdetail=""     # no tail present
      park "$reason" "liveness park at (slice=$G_SLICE stage=$G_STAGE attempt=$G_ATTEMPT); screen attached${wdetail:+ — $wdetail}" "$screen" ;;
    STOP)
      rm -f "$WS/.runtime/stop-request"
      park operator_stop "operator stop request — graceful park; sessions kept for postmortem" ;;
    *)
      park stall_record "wait loop returned unrecognized outcome '$out'" ;;
  esac
}
