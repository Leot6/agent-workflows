#!/usr/bin/env bash
# lib/watch.sh — ferry.sh's wait-loop half (the liveness stack of
# state-and-liveness.md §5), split out under architecture §4.1's layout
# freedom to keep ferry.sh ≤800 lines; only ferry.sh sources it.
#
# Signal stack, strongest semantics first: process (dual-pid + starttime) →
# heartbeat age → CPU delta of the pane's process subtree (busy though
# silent extends) → pane signature classification. One nudge per quiet
# episode; `working` has its own max age; every threshold is an independent
# config literal; clock jumps get amnesty via the ferry's own tick gap.
#
# watch_wait prints exactly one outcome line on stdout:
#   RECORD                     — handoff record with the active nonce landed
#   FAIL <class>               — dead|idle|timeout|working_overage|hard_ceiling
#                                |wedged|backend_retrying  (ferry re-enters the
#                                 attempt cycle: bounded respawn precedes every
#                                 liveness park)
#   PARK <reason> <screenfile> — unknown_screen|unknown_modal|operator_interference
#                                |backend_quota|backend_overloaded
#                                (screen saved; path rides in the outcome line —
#                                 watch_wait runs in a command substitution, so
#                                 a global would die with the subshell)
#   STOP                       — operator stop-request file seen
# Store faults inside the loop → rc 3 (ferry exits store_fault).

_WATCH_LIB_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
. "$_WATCH_LIB_DIR/state.sh"
. "$_WATCH_LIB_DIR/config.sh"
. "$_WATCH_LIB_DIR/notify.sh"
. "$_WATCH_LIB_DIR/../backends/pty_tmux.sh"

watch_subtree_cpu() { # root_pid -> summed utime+stime jiffies of the subtree
  cat /proc/[0-9]*/stat 2>/dev/null | awk -v root="$1" '
    { pid=$1; line=$0; sub(/^[^(]*\(/,"",line); sub(/^.*\) /,"",line)
      split(line,f," "); ppid[pid]=f[2]; cpu[pid]=f[12]+f[13] }
    END {
      total=0; queue[0]=root; head=0; tail=1; seen[root]=1
      while (head < tail) {
        p=queue[head++]; total+=cpu[p]
        for (c in ppid) if (ppid[c]==p && !seen[c]) { seen[c]=1; queue[tail++]=c }
      }
      print total }'
}

_watch_save_screen() { # ws session -> path
  local d="$1/.runtime/logs" f
  mkdir -p "$d"
  f="$d/screen-$(date +%s).txt"
  tmux capture-pane -p -t "=$2:" > "$f" 2>/dev/null || echo "(capture failed)" > "$f"
  printf '%s\n' "$f"
}

_watch_pane_history() { # session -> the pane's full scrollback (empty on failure)
  tmux capture-pane -p -S - -t "=$1:" 2>/dev/null
}

# What the backend itself has said about its quota, or rc 1 for "it has not
# said it". Two domains on purpose, matching pty_classify_screen's own split:
# the VISIBLE frame DECIDES — an exhaustion line that has scrolled out of view
# is what the backend said earlier, not what it is saying now, and reading the
# decision from the scrollback would turn every later wedge on the same pane
# into a quota park. The TEXT handed to the operator then comes from the full
# scrollback, where the sentence (which carries the reset time) is still whole.
# Parameterised by SIGNATURE KEY, defaulting to the quota one so every existing
# caller and every fixture override reads unchanged. One derivation, two
# signatures: `sig.backend_overloaded` needs the identical two-domain treatment
# (visible frame decides, scrollback supplies the text) and a re-typed copy
# would drift from the pipefail reasoning below the first time either moved.
_watch_quota_line() { # decl session [sigkey] -> the backend's own line (rc 1 = not said)
  local sig line key=${3:-sig.quota_exhausted}
  sig=$(pty_decl_get "$1" "$key" 2>/dev/null) || return 1
  [ -n "$sig" ] || return 1
  _pty_capture "$2" | command grep -qE "$sig" || return 1
  # DECIDED, above, on the visible frame. What follows only fetches the text,
  # and its status is deliberately not the function's: this runs under
  # `pipefail`, so a history read matching nothing would exit non-zero and
  # RETRACT a decision already made — putting the run back on `FAIL wedged`
  # with the quota line plainly on screen. The frame is captured twice and
  # scrollback can move between them, so that is a live race, not a
  # hypothetical. An empty line is a missing sentence; it is not a missing
  # fact, and the caller's fallback text says exactly that.
  line=$(_watch_pane_history "$2" | command grep -E "$sig" | tail -1 | tr -d '\r' | tr '\n\t' '  ')
  printf '%s\n' "$line"
}

# The park outcome for a backend that is out. The one fact the operator needs is
# WHEN it comes back, and that differs per CLI — a daily window, a rolling hour,
# a plan reset in another timezone. The workflow therefore never computes or
# assumes one: it forwards the backend's own line verbatim. Screen file too, for
# the surrounding context.
_watch_quota_park_line() { # ws session qline -> the PARK outcome line
  printf 'PARK backend_quota %s the backend said: %s\n' \
    "$(_watch_save_screen "$1" "$2")" \
    "${3:-<line matched sig.quota_exhausted but was not captured>}"
}

# The same outcome for a backend that is UP and refusing. It is a separate
# function, not a parameter, because the two differ in the one thing an
# operator acts on: quota forwards a RESET TIME and this one has none to
# forward. Saying so in the line is the point — the operator relaunches on
# judgment rather than on a printed clock, and a park text that implied a wait
# would be inventing the fact quota exists to carry.
_watch_overload_park_line() { # ws session oline -> the PARK outcome line
  printf 'PARK backend_overloaded %s the backend said: %s (no reset time is published for this state — relaunch on judgment, not on a clock)\n' \
    "$(_watch_save_screen "$1" "$2")" \
    "${3:-<line matched sig.backend_overloaded but was not captured>}"
}

# Best-effort monitor feed. `idle` and `working` are published because they are
# the quantities this loop actually COMPARES: stage_timeout is measured against
# continuous inactivity (line ~150) and working_max_age against the working
# episode — while `age` (now - spawn_t) is capped by the hard ceiling alone. A
# panel that renders age against stage_timeout shows a healthy stage draining
# toward a limit it can never reach; that misread happened to a live operator.
_watch_stage_note() { # ws class hb_age age idle working
  state_put "$1" stage ferry "live_class=$2" "live_hb_age=$3" "live_age=$4" \
    "live_idle=$5" "live_working=$6" "live_t=$(date +%s)" > /dev/null 2>&1 || true
}

# Protocol-derived idleness (state-and-liveness.md §5): the CLI's own Notification hook writes idle_prompt events to the
# notify_events surface (session/notify_event.sh, wired in the profile).
# The event is PRIMARY for the idle classification — the screen drops from
# gate to corroboration: a pane that cannot classify (rendering artifacts,
# ghost repaints — the measured unknown_screen park class) no longer parks
# when the CLI itself states it is idle. Scope, stated honestly: only
# type=idle_prompt is acted on (permission_prompt is recorded for audit but
# a permission modal under dontAsk is config drift, surfaced not
# auto-answered); only the unknown→awaiting_input decision changes — the
# nudge ladder's timing (quiet/nudge graces) is untouched this round, its
# recalibration against live-topic data being the standing defaults.kv note.
# Backends without the hook surface (codex today) never write events:
# absent surface reads as no evidence ⇒ behavior byte-identical, asserted
# by the absent-surface arm in 75-watch.
watch_proto_idle() { # ws session now fresh_secs -> event t (empty = none)
  # $1, not the ambient $ws. It read the ambient one for a while, which
  # made the documented first parameter dead: every caller happened to pass the
  # same value, so nothing was wrong in production and nothing could be — a
  # caller reaching for a different store would have silently been answered
  # from this one. Found by a check that passed its own fixture workspace and
  # got a false negative back; the fix is behaviour-identical at the only
  # production call site, which passes "$ws".
  local body ev t age
  body=$(state_get "$1" notify_events 2>/dev/null) || return 0
  [ -n "$body" ] || return 0
  ev=$(printf '%s\n' "$body" | command grep -E "(^| )session=$2( |$)" \
       | command grep -E '(^| )type=idle_prompt( |$)' | tail -1)
  [ -n "$ev" ] || return 0
  t=$(printf '%s\n' "$ev" | awk '{for(i=1;i<=NF;i++) if($i~/^t=/){sub(/^t=/,"",$i);print $i;exit}}')
  case "$t" in ''|*[!0-9]*) return 0 ;; esac
  age=$(( $3 - t ))
  [ "$age" -ge 0 ] && [ "$age" -le "$4" ] && echo "$t"
  return 0
}

# The loop's clock, behind two one-line seams. Production is the real thing:
# `_wt_now` is `date +%s`, `_wt_sleep` is `sleep`. 75-watch shadows both with a
# virtual clock — the sixth primitive it overrides beside pty_alive /
# pty_classify_screen / pty_inject / _pty_capture / watch_subtree_cpu — so an
# arm's outcome is arithmetic on the loop's literals and not a race against
# the machine (the fixture-margin class: a stretched iteration carrying an arm
# past a deadline it was written to beat; measured, twice). Nothing below
# reads the clock any other way; the helper stamps `_watch_stage_note` writes
# (`live_t`) and `_watch_save_screen` names (`screen-<epoch>`) are provenance
# of real events and stay real. CONSTRAINT on any shadow: `now` is compared
# against other writers' real-epoch stamps (heartbeat `t`, notify_events `t=`)
# and written into the ledger as `t=$now` — a virtual clock must be seeded
# from the real epoch and run monotonically ahead of it, never from zero.
_wt_now()   { date +%s; }
_wt_sleep() { sleep "$1"; }
# The wait between polls. The record is the one event worth waking for inside
# a poll: everything else the loop reads — heartbeat age, CPU delta, the pane
# — is a liveness question whose answer needs the pane to have settled, and
# the poll interval IS that settling time; the handoff surface needs nothing
# of the kind. So the wait looks for the record twice a second and returns the
# moment it lands — a stage's completion is seen within half a second, not
# within a poll (liveness.poll=15 in production: up to 14s at every stage end,
# and a third of a nine-stage drill walk, measured). Two checksummed reads a
# second is the whole cost. 75-watch shadows this as a plain virtual sleep
# (none of its arms ever lands a record); the drill meets the real one.
# The check comes BEFORE the first sleep, and that ordering is the whole of it.
# A record that landed while the loop was doing its liveness work is already on
# the surface when this is entered, and the earlier sleep-then-look form paid a
# full half-second to discover it — every stage end, unconditionally. Nothing
# is traded for it: the settling argument above is about the PANE, and this
# reads the handoff surface, which by that same paragraph "needs nothing of the
# kind"; an early return leaves the loop rather than shortening any liveness
# cadence; and the sleep COUNT is unchanged at n, so a poll with no record
# still costs its full interval. Measured on a traced drill walk, where the
# mock CLI records within milliseconds of the spawn: `_wt_sleep` was 9.52s of a
# 38.1s ferry run, one 0.5s sleep per stage that had nothing to wait for.
# The step SUBDIVIDES the poll and is therefore a fraction of it, not a
# constant. It used to be a hard 0.5s with the count derived as `poll * 2`,
# which is the same thing only while poll is the default: at
# `liveness.poll=15` this wakes 30 times, 0.5s apart, exactly as before —
# production is bit-identical. What it fixes is every OTHER poll value. The
# drill declares `liveness.poll=1` in its own topic.kv, meaning "this is a
# test, look often", and the hard 0.5s ignored it: measured on a traced walk,
# `_wt_sleep` was 9.52s of a 38.1s ferry run, exactly 19 sleeps of 0.5s — one
# per stage, each one a full quantum spent discovering a record that had
# arrived milliseconds in. At poll=1 the step is now 0.033s and the declared
# intent finally reaches the wait.
# Fork-free: integer milliseconds and a printf builtin, because this runs
# WAKES_PER_POLL times per stage and an awk here would cost more than it saves.
# The floor stops a small or zero poll from becoming a busy spin.
_WT_WAKES_PER_POLL=30
_wt_wait() { # ws nonce poll-seconds
  local ws=$1 nonce=$2 poll=$3 i=0 ms step
  ms=$(( poll * 1000 / _WT_WAKES_PER_POLL )); [ "$ms" -lt 10 ] && ms=10
  printf -v step '%d.%03d' $(( ms / 1000 )) $(( ms % 1000 ))
  while :; do
    state_get "$ws" handoff 2>/dev/null | command grep -qE "(^| )nonce=$nonce( |$)" && return 0
    [ $i -lt $_WT_WAKES_PER_POLL ] || return 0
    _wt_sleep "$step"; i=$((i + 1))
  done
}

watch_wait() { # ws decl session pane_pid pane_start server_pid server_start nonce stage slice attempt spawn_t
  local ws=$1 decl=$2 session=$3 pp=$4 pps=$5 sp=$6 sps=$7 nonce=$8 stage=$9
  local slice=${10} attempt=${11} spawn_t=${12}
  local poll hb_fresh quiet_grace nudge_grace working_max hard_ceiling stage_to notify_fresh
  poll=$(config_get liveness.poll --topic-dir "$ws") || return 3
  hb_fresh=$(config_get liveness.heartbeat_fresh --topic-dir "$ws") || return 3
  quiet_grace=$(config_get liveness.quiet_grace --topic-dir "$ws") || return 3
  nudge_grace=$(config_get liveness.nudge_grace --topic-dir "$ws") || return 3
  working_max=$(config_get liveness.working_max_age --topic-dir "$ws") || return 3
  hard_ceiling=$(config_get liveness.hard_ceiling --topic-dir "$ws") || return 3
  stage_to=$(config_get "stage.$stage.timeout" --topic-dir "$ws" 2>/dev/null) \
    || stage_to=$(config_get liveness.stage_timeout --topic-dir "$ws") || return 3
  local modal_max cpu_pct sg_max clk
  modal_max=$(config_get liveness.modal_acts_max --topic-dir "$ws") || return 3
  cpu_pct=$(config_get liveness.cpu_busy_pct --topic-dir "$ws") || return 3
  sg_max=$(config_get liveness.stop_gate_blocks_max --topic-dir "$ws") || return 3
  notify_fresh=$(config_get liveness.notify_fresh --topic-dir "$ws") || return 3
  local retry_grace
  retry_grace=$(config_get liveness.retry_grace --topic-dir "$ws") || return 3
  # Jiffies per second per core, for turning the percent into a comparable
  # delta. Non-Linux or a broken getconf falls back to the near-universal 100.
  clk=$(getconf CLK_TCK 2>/dev/null); case "$clk" in ''|*[!0-9]*) clk=100 ;; esac
  local nudge_text
  nudge_text=$(pty_decl_get "$decl" nudge_text 2>/dev/null || echo continue)

  # The retry episode's own clock, deliberately separate from `nudged`/`nudge_t`
  # (a human-waiting session's ladder) and from `working_since` (a working
  # episode's). It is reset wherever real activity resumes, so a ladder that
  # clears and later returns starts a fresh episode rather than inheriting an
  # old one's elapsed time.
  local retry_since=0
  local now last_tick nudged=0 nudge_t=0 working_since=0 cpu_prev=-1 cpu_t=0
  local progress_seen modal_acts=0 hb hb_age cls rc
  # stage_timeout is a CONTINUOUS-INACTIVITY deadline: any activity evidence
  # (fresh heartbeat, CPU delta) resets last_activity; only unbroken silence
  # past the limit kills. Total duration is hard_ceiling's job alone.
  local last_activity=$spawn_t
  last_tick=$(_wt_now)
  progress_seen=$(state_get "$ws" progress 2>/dev/null | command grep -cE "(^| )slice=$slice( |$)" || true)

  while :; do
    _wt_wait "$ws" "$nonce" "$poll"
    now=$(_wt_now)
    # Clock-jump amnesty: a gap far beyond the poll interval means suspend/NTP,
    # not stalling — shift timers, audit, never park on it.
    # EVERY episode clock this loop compares against `now` is shifted here, and
    # the list is enumerated by hand, which makes it exactly the shape that goes
    # short a member: `retry_since` was added for the backend-retry arm and was
    # NOT added here, so a suspend during a backoff would have counted the
    # suspended interval toward the retry grace and failed the attempt on a
    # clock that never ran. `75-watch` now holds the RULE rather than the list —
    # any `now - <clock>` in this function must be shifted here or named
    # exempt — so the next one added cannot be omitted silently.
    if [ $((now - last_tick)) -gt $((poll * 10)) ]; then
      local gap=$((now - last_tick - poll))
      spawn_t=$((spawn_t + gap)); [ "$working_since" -gt 0 ] && working_since=$((working_since + gap))
      [ "$nudge_t" -gt 0 ] && nudge_t=$((nudge_t + gap))
      last_activity=$((last_activity + gap))
      # The CPU sample stamp rides the amnesty too, or the next delta would be
      # divided by a span that includes the suspended interval — during which
      # no jiffies could accrue — and a genuinely busy subtree would read as
      # below the floor for one poll.
      [ "$cpu_t" -gt 0 ] && cpu_t=$((cpu_t + gap))
      [ "$retry_since" -gt 0 ] && retry_since=$((retry_since + gap))
      state_audit "$ws" ferry "clock-jump amnesty: gap=${gap}s, stage timers shifted (stage=$stage attempt=$attempt)"
    fi
    last_tick=$now

    [ -e "$ws/.runtime/stop-request" ] && { echo STOP; return 0; }

    local hoff
    hoff=$(state_get "$ws" handoff 2>/dev/null); rc=$?
    [ $rc -eq 3 ] && return 3
    if printf '%s\n' "$hoff" | command grep -qE "(^| )nonce=$nonce( |$)"; then
      echo RECORD; return 0
    fi

    if [ "$stage" = "impl" ] || [ "$stage" = "fix" ]; then
      local pnow
      pnow=$(state_get "$ws" progress 2>/dev/null | command grep -cE "(^| )slice=$slice( |$)" || true)
      if [ "$pnow" -gt "$progress_seen" ]; then
        state_get "$ws" progress 2>/dev/null | command grep -E "(^| )slice=$slice( |$)" \
          | tail -n $((pnow - progress_seen)) | while IFS= read -r line; do
              notify_fire "$ws" commit.done none "commit landed: $line"
            done
        state_append "$ws" ledger ferry \
          "v=1 t=$now event=commit.done slice=$slice stage=$stage count=$pnow" > /dev/null || true
        progress_seen=$pnow
      fi
    fi

    # Order is load-bearing (state-and-liveness.md §5): the hard ceiling is the
    # ONLY absolute cap; heartbeat/CPU activity precede the stage timeout so a
    # busy-though-silent stage EXTENDS past stage_timeout (up to the ceiling).
    # A timeout-first order would make the CPU extension unreachable.
    if [ $((now - spawn_t)) -gt "$hard_ceiling" ]; then
      echo "FAIL hard_ceiling"; return 0
    fi

    if [ "$(pty_alive "$pp" "$pps" "$sp" "$sps")" = "dead" ]; then
      echo "FAIL dead"; return 0
    fi

    # A session that keeps hitting the Stop gate is TELLING us it cannot
    # finish, and that belongs HIGH in this stack: it is the session's own
    # statement, not an inference from activity. Every branch below can
    # `continue` past a wedge — a fresh heartbeat from a tool-calling loop, a
    # CPU delta over the floor, a pane that classifies working — which is
    # exactly the shape that hid the measured one. The gate is doing its job
    # each time; what follows is the CLI's own block cap overriding it and
    # force-ending the turn, leaving a stage surface that reads running
    # against a pane that will never speak again. Counted from the gate's own
    # audit trail, scoped to this attempt's nonce.
    local sg_n
    sg_n=$(state_get "$ws" audit 2>/dev/null \
           | command grep -cE "stop_gate_block nonce=$nonce( |$)" || true)
    case "$sg_n" in ''|*[!0-9]*) sg_n=0 ;; esac
    if [ "$sg_n" -ge "$sg_max" ]; then
      # A backend with nothing left to spend cannot finish a turn either, and
      # it arrives at this counter FIRST: a session born into a zero-quota
      # window re-ends its turn about once a second (measured: 9
      # blocks in 9s, then 9 in 6s, two attempts), so sg_max is spent long
      # before the screen is ever classified and the `quota_exhausted` arm
      # below could never fire for the condition it was written for. `wedged`
      # is a FAIL — the ferry respawns into the same dead window — where the
      # quota statement is a PARK; and probe.sh's cache bypass keys on
      # `halt reason == backend_quota`, so the misclassification silently
      # disarmed that guard too (the halt read `no_novelty`).
      # The counter keeps its place in the stack for its own stated reason
      # (above); what changes is only that the STRONGER of the two statements
      # is asked first — "I have nothing left to spend" outranks "I cannot
      # finish this turn", and it is the backend's own words either way.
      local qline
      if qline=$(_watch_quota_line "$decl" "$session"); then
        _watch_quota_park_line "$ws" "$session" "$qline"; return 0
      fi
      # And the same question for the other statement that outranks "I cannot
      # finish this turn": a backend returning 529 cannot finish one either,
      # and a respawn spends attempts on calls that cannot succeed. Asked
      # second because quota is the stronger statement of the two.
      if qline=$(_watch_quota_line "$decl" "$session" sig.backend_overloaded); then
        _watch_overload_park_line "$ws" "$session" "$qline"; return 0
      fi
      echo "FAIL wedged"; return 0
    fi

    hb=$(state_field "$ws" heartbeat t 2>/dev/null || echo 0)
    hb_age=$((now - hb))
    if [ "$hb_age" -lt "$hb_fresh" ]; then
      nudged=0; working_since=0; modal_acts=0; retry_since=0
      last_activity=$now
      _watch_stage_note "$ws" busy "$hb_age" $((now - spawn_t)) 0 0
      continue
    fi

    # The CPU extension is a RATE test, not a change test. "Any increase at
    # all" made an idle CLI's few percent of a core read as work on every
    # poll, and each such poll reset the inactivity clock, the nudge and the
    # working episode — so a wedged session was indistinguishable from a busy
    # one and only the 3h ceiling could end it (measured: ~6h and a day's
    # quota). The floor is scaled by the REAL span since the last sample, so
    # the heartbeat-fresh branch above skipping this test cannot let a long
    # gap's accumulated jiffies read as a burst.
    local cpu span floor
    cpu=$(watch_subtree_cpu "$pp")
    case "$cpu" in ''|*[!0-9]*) cpu=$cpu_prev ;; esac
    span=$((now - cpu_t)); [ "$span" -lt 1 ] && span=1
    floor=$((span * clk * cpu_pct / 100)); [ "$floor" -lt 1 ] && floor=1
    if [ "$cpu_prev" -ge 0 ] && [ $((cpu - cpu_prev)) -ge "$floor" ]; then
      cpu_prev=$cpu; cpu_t=$now
      nudged=0; working_since=0; retry_since=0
      last_activity=$now
      _watch_stage_note "$ws" busy_cpu "$hb_age" $((now - spawn_t)) 0 0
      continue
    fi
    cpu_prev=$cpu; cpu_t=$now

    if [ $((now - last_activity)) -gt "$stage_to" ]; then
      echo "FAIL timeout"; return 0
    fi

    cls=$(pty_classify_screen "$decl" "$session")
    # Protocol signal primary over an unclassifiable pane: a fresh CLI-side
    # idle_prompt reclassifies unknown as awaiting_input (screen corroborates
    # by not contradicting — a working pane still wins its own arm below).
    # Audited, so a wrong call is visible in the postmortem trail.
    if [ "$cls" = "unknown" ]; then
      local proto_t
      proto_t=$(watch_proto_idle "$ws" "$session" "$now" "$notify_fresh")
      if [ -n "$proto_t" ]; then
        state_audit "$ws" ferry "protocol idleness: fresh idle_prompt (t=$proto_t, age=$((now - proto_t))s) primary over unknown screen — classifying awaiting_input (stage=$stage attempt=$attempt)"
        cls=awaiting_input
      fi
    fi
    local wsec=0
    [ "$working_since" -gt 0 ] && wsec=$((now - working_since))
    _watch_stage_note "$ws" "$cls" "$hb_age" $((now - spawn_t)) $((now - last_activity)) "$wsec"
    case "$cls" in
      working)
        retry_since=0
        [ "$working_since" -eq 0 ] && working_since=$now
        if [ $((now - working_since)) -gt "$working_max" ]; then
          echo "FAIL working_overage"; return 0
        fi ;;
      quota_exhausted)
        # Not a liveness failure: the session is alive and correct, the backend
        # is out. Respawning would spend attempts on calls that cannot succeed
        # (measured: two attempts born dead into a zero-quota window), so this
        # parks instead of failing. This is the arm the screen reaches on its
        # own; the wedge branch above reaches the same park through the same
        # two helpers when the stop-gate counter got here first. The park is
        # unconditional here — the classification already read the frame — so a
        # line that moved between the two reads still parks, on the fallback
        # text.
        local qline
        qline=$(_watch_quota_line "$decl" "$session") || qline=""
        _watch_quota_park_line "$ws" "$session" "$qline"
        return 0 ;;
      backend_overloaded)
        # Same economics as quota_exhausted above, one arm up, minus a reset
        # time: the session is alive and correct, the backend is UP and
        # refusing. Respawning spends attempts on calls that cannot succeed —
        # measured, two attempts and ~17 minutes into a 529 window,
        # then a no_novelty park on an identical fingerprint, because this
        # class did not exist and the pane read `awaiting_input`.
        # Unconditional here, like quota: the classification already read the
        # frame, so a banner that scrolled between the two reads still parks on
        # the fallback text.
        local oline
        oline=$(_watch_quota_line "$decl" "$session" sig.backend_overloaded) || oline=""
        _watch_overload_park_line "$ws" "$session" "$oline"
        return 0 ;;
      error_retryable)
        # THE THIRD BEHAVIOUR, and the reason it is not the arm below: the CLI
        # is running its OWN retry ladder, which is neither a human-waiting
        # prompt nor a liveness failure. Three things follow, each measured on
        # the episode that produced this arm (a live postcheck round).
        #  - DO NOT NUDGE. Injecting "continue" into a client mid-backoff
        #    cannot help, and the ledger then records `inject_rc=0` beside a
        #    failure the injection had nothing to do with — which is precisely
        #    what made that episode read as a stall.
        #  - DO NOT SPEND THE IDLE BUDGET on it. The nudge ladder's grace is
        #    sized for a quiet human-waiting session; a backoff ladder reaching
        #    "attempt 9/10" is a different clock, so it gets its own.
        #  - NAME THE CAUSE. `FAIL idle` on a retrying backend is a
        #    misattribution the ledger preserves: a postmortem reading it
        #    diagnoses a stalled reviewer and looks at the session, and the
        #    session was fine.
        # The stage timeout still bounds this from outside — retry_grace is an
        # inner limit that fails with the right word, never an extension.
        working_since=0
        [ "$retry_since" -eq 0 ] && retry_since=$now
        if [ $((now - retry_since)) -gt "$retry_grace" ]; then
          echo "FAIL backend_retrying"; return 0
        fi
        continue ;;
      awaiting_input)
        working_since=0
        [ "$hb_age" -lt "$quiet_grace" ] && continue
        if [ $nudged -eq 0 ]; then
          # One nudge per quiet episode, through the single primitive.
          # STDOUT is kept, not discarded: it carries which of the three rc-3
          # refusals this was, and without it the ledger's inject_rc=3 is
          # unreadable after the fact — measured on the one live instance.
          local inj
          inj=$(pty_inject "$decl" "$session" "$nudge_text" "$ws/.runtime" 2>/dev/null); rc=$?
          if [ $rc -eq 2 ]; then
            echo "PARK operator_interference $(_watch_save_screen "$ws" "$session")"; return 0
          fi
          nudged=1; nudge_t=$now
          state_append "$ws" ledger ferry \
            "v=1 t=$now event=nudge slice=$slice stage=$stage attempt=$attempt inject_rc=$rc inject_why=$(pty_inject_why "$inj")" > /dev/null || true
        elif [ $((now - nudge_t)) -gt "$nudge_grace" ]; then
          echo "FAIL idle"; return 0
        fi ;;
      modal.*)
        working_since=0
        local act
        act=$(pty_decl_get "$decl" "act.$cls" 2>/dev/null || true)
        if [ -z "$act" ] || [ "$modal_acts" -ge "$modal_max" ]; then
          echo "PARK unknown_modal $(_watch_save_screen "$ws" "$session")"; return 0   # not in the allowlist (or recurring): loud, never auto-answered
        fi
        # act.modal.* may carry multiple keys ("Y Enter"); a single-arg
        # send-keys types the literal string. Split into keys, send each.
        local -a act_keys
        read -ra act_keys <<< "$act"
        tmux send-keys -t "=$session:" "${act_keys[@]}" 2>/dev/null || true
        modal_acts=$((modal_acts + 1))
        state_append "$ws" ledger ferry \
          "v=1 t=$now event=modal_action slice=$slice stage=$stage modal=$cls act=$act" > /dev/null || true ;;
      unknown)
        echo "PARK unknown_screen $(_watch_save_screen "$ws" "$session")"; return 0 ;;
    esac
  done
}
