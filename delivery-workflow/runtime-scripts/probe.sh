#!/usr/bin/env bash
# probe.sh — the backend onboarding probe (backend-seam.md §2): declarations
# are promises; this scratch-session run makes them facts, or refuses the
# topic. Invoked by launch.sh preflight on first use of a backend and after
# any CLI version change; the drill runs it directly against the mock backend.
#
#   probe.sh <topic-workspace> <decl-file> <backend-name> <model> <effort>
#   probe.sh --verify   <topic-workspace> <decl-file> <backend-name>
#   probe.sh --identity <decl-file> <backend-name>
#
# The two flag forms are READ-ONLY halves of the same derivation: --verify
# answers "does a valid pass record stand for this exact promise" without
# spawning anything (ferry.sh asks it at every spawn, beside the capability
# check), and --identity prints what such a record is keyed to.
#
# What one real scratch session proves, and how:
#   heartbeat       the PreToolUse hook writes the probe store (agent runs a
#                   trivial command)
#   stop_gate       the Stop hook blocks a record-less turn end — the block
#                   line appears in the pane log, and the agent is shepherded
#                   by the block message itself to the valid finish
#   emit            the record lands through the full record.sh chain (nonce,
#                   owed refusal naming the validation note, gates)
#   awaiting_input  the declared empty-composer signature classifies the
#                   post-emit idle screen
#   inject          the single injection primitive reaches the live pane (log
#                   grows after a nudge)
#   dead_detect     dual-pid + starttime liveness reads the exited CLI as dead
#   working / modal best-effort: attested when observed, NAMED as unobserved
#                   otherwise (absence of observation is not proof)
#
# Verdict: any hard item missing at the end -> result=fail, rc 1 (launch
# refuses the topic). Result + CLI version land in
# <ws>/.runtime/probe/<backend>.kv; an unchanged version is a cached pass —
# no second session is spent.
# rc: 0 pass (incl. cached) · 1 fail (the DECLARATION is wrong) · 4 the backend
# is UNAVAILABLE (quota) — a different fact with a different remedy, so it is a
# different code: nothing about the declaration was disproved, and nothing may
# be cached as a pass. Without the split, a zero-quota window read as "the
# declaration or harness wiring is broken" after burning the full probe.timeout.
# · 2 usage.

set -uo pipefail
export LC_ALL=C
P_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
WROOT=${CONFIG_WORKFLOW_ROOT:-$(cd "$P_DIR/.." && pwd)}
. "$P_DIR/lib/state.sh"
. "$P_DIR/lib/config.sh"
. "$P_DIR/backends/pty_tmux.sh"

refuse() { echo "refuse: $*" >&2; exit 2; }

# Two READ-ONLY modes beside the real probe, so that a stored record's identity
# has exactly ONE derivation in this tree:
#   --verify <ws> <decl> <backend>   rc 0 iff a valid PASS record stands for
#       this declaration+profile+CLI+probe code. Never spawns, never writes.
#       ferry.sh asks it at the spawn, beside the capability check: the promise
#       and the fact are the same admission question (backend-seam.md §2), and
#       the door cannot see a backend written into the config after it.
#       Deliberately NOT subject to the quota bypass below — the bypass exists
#       to force a live re-probe at preflight, which a read-only mode cannot
#       do, and quota is availability while this answers capability.
#   --identity <decl> <backend>      print the identity block a record for this
#       backend would be keyed to (the answer to "why is my stored pass no
#       longer answering?"); self-check's drill uses it to fabricate the record
#       a launch would have left.
MODE=probe
case "${1:-}" in
  --verify)   MODE=verify;   shift ;;
  --identity) MODE=identity; shift ;;
esac
case "$MODE" in
  probe)    [ $# -eq 5 ] || refuse "usage: probe.sh <topic-workspace> <decl-file> <backend> <model> <effort>" ;;
  verify)   [ $# -eq 3 ] || refuse "usage: probe.sh --verify <topic-workspace> <decl-file> <backend>" ;;
  identity) [ $# -eq 2 ] || refuse "usage: probe.sh --identity <decl-file> <backend>" ;;
esac
if [ "$MODE" = "identity" ]; then
  DECL=$1; BACKEND=$2
else
  WS=$(cd "$1" 2>/dev/null && pwd) || refuse "workspace $1 is not a directory"
  DECL=$2; BACKEND=$3; MODEL=${4:-}; EFFORT=${5:-}
  TOPIC=$(basename "$(cd "$WS/.." && pwd)")
fi
[ -f "$DECL" ] || refuse "declaration $DECL absent"

# BOUNDED, and the bound is load-bearing since --verify runs at EVERY spawn,
# inside the ferry's own process: this exact command has hung past four minutes
# on a CLI's own self-update prompt (backend-seam.md §2), and an unbounded
# hang here would WEDGE the run silently — nothing above catches it, because the watchdog classifies exits
# only. Bounded, a hang becomes `unknown`, which fails the identity comparison
# and parks loudly: the honest answer when the CLI cannot be asked what it is.
# stdin is /dev/null for the same reason — a version query is non-interactive
# by nature, and giving it a terminal to ask questions on is what produced the
# measured hang.
# The version token, not head -1 and not the raw last line: a wrapper CLI
  # can front claude with an API-config module (the notice is the MODULE's,
  # upstream information, not pollution) that INTERMITTENTLY
  # (measured ~1/1340 invocations) prints its update notice ending in an
  # interactive "[Y/n]: " prompt that our /dev/null stdin leaves dangling,
  # with the wrapped claude version printed after it ON THE SAME LINE —
  # captured full-shape. head -1 read the notice's first line on a banner invocation and the version on a clean
  # one; the raw last line carries the "[Y/n]: " prefix on banner
  # invocations. Either way the identity flaps for an UNCHANGED CLI. The
  # extraction: last non-empty line, then from its first version-shaped
  # token ([0-9]+.[0-9]+), whole line as fallback — a clean claude read
  # identically to head -1 (token at line start), a banner line reads the
  # bare version, and codex's "codex-cli 0.148.0" shifts once to "0.148.0"
  # (a one-time identity migration: one cache miss, one re-probe, never a
  # park — the honest price of normalizing the banner away).
  version=$(timeout 10 bash -c "$(pty_decl_get "$DECL" cmd.version 2>/dev/null)" < /dev/null 2>/dev/null             | awk 'NF {v=$0} END {if (v != "" && match(v, /[0-9]+\.[0-9]+/)) print substr(v, RSTART); else print v}')
version=${version:-unknown}
# The cache answers only for the EXACT promise it proved: CLI version AND the
# declaration's content AND the profile template. A same-version edit to
# either is a new promise — "declarations are promises, the probe makes them
# facts" cannot survive a cached pass for content it never saw.
decl_hash=$(md5sum < "$DECL" | cut -c1-32)
profile_rel_c=$(pty_decl_get "$DECL" profile 2>/dev/null || true)
profile_hash=$(md5sum < "$WROOT/config/$profile_rel_c" 2>/dev/null | cut -c1-32 || echo none)
# The probe's own implementation is part of what a pass attests (a mutated
# adapter primitive must never coast on a pre-mutation pass). The question is
# "did the CODE that produced this pass change", so the key is that code's
# content — the probe itself plus what it sources and what its profile's hooks
# execute (lib, backends, session). Directory-scoped rather than a file list,
# which would go stale silently as the tree grows.
#
# It was the repo's HEAD commit, and that answered a much wider question, in
# both directions. Too wide: HEAD moves for every neighbour, so in a checkout
# holding sibling workflows the pass was keyed to their commits — measured, the
# dogfood topic's stored pass was pinned to a sibling's iteration-log edit, and
# six re-probes inside one 3h window each spent a real scratch session (a live
# CLI turn, up to probe.timeout) on a tree that had not changed at all. Too
# narrow: outside git the sha was the constant `no-git`, so in a copied or
# untracked tree — the drill's own shadow root is one — a MUTATED probe was
# served straight from the cache, which is exactly what this key exists to stop.
# Content hashing closes both, and is path-independent, so a shadow copy of the
# same code keys the same.
probe_impl=$( { cat "$P_DIR/probe.sh"
                find "$P_DIR/lib" "$P_DIR/backends" "$P_DIR/session" \
                     -type f -name '*.sh' -print0 | sort -z | xargs -0 cat
              } 2>/dev/null | md5sum | cut -c1-32)

# The identity block of a probe record: what a stored result is keyed to, in
# one place. Written into every record below, compared by probe_record_valid,
# and printed by --identity — three readers, one derivation.
probe_identity() {
  echo "backend=$BACKEND"
  echo "version=$version"
  echo "decl_hash=$decl_hash"
  echo "profile_hash=$profile_hash"
  echo "probe_impl=$probe_impl"
}
if [ "$MODE" = "identity" ]; then probe_identity; exit 0; fi

PK="$WS/.runtime/probe/$BACKEND.kv"
# Does the stored record answer for THIS identity, and is it a pass?
probe_record_valid() {
  [ -f "$PK" ] || return 1
  local line k
  while IFS= read -r line; do
    k=${line%%=*}
    [ "$(awk -F= -v kk="$k" '$1==kk{print substr($0,length(kk)+2)}' "$PK")" = "${line#*=}" ] \
      || return 1
  done < <(probe_identity)
  command grep -q '^result=pass' "$PK"
}
if [ "$MODE" = "verify" ]; then
  probe_record_valid && exit 0
  echo "probe --verify: no valid pass record for backend '$BACKEND' at $PK — the record is absent, is not a pass, or was keyed to a different CLI version / declaration / profile / probe implementation than the one standing now" >&2
  exit 1
fi

# Sub-phase waits (seconds) are the backend's REACTION LATENCY — how long
# this CLI may take to paint its idle composer after a turn ends, to echo an
# injected line, to exit after /exit — so they are declared per backend
# (`probe.latency`, backend-seam.md §3) the way frame_settle is, for the same
# reason: a property of the CLI, measured, not a constant this probe is
# entitled to assume for every one. Absent or non-numeric falls back to 30,
# the constant that stood here, and 30-closure refuses a value that is present
# but not a number. Every phase exits the moment its event arrives, so the
# bound is only ever spent proving "it never came" — and a backend that reacts
# in milliseconds (the self-check's mock declares 5) should not spend 30s per
# refusal row proving that. The one config-level literal stays probe.timeout,
# which bounds the whole agent phase. The poll step inside every phase is
# half a second: a PASS probe spends one step per phase waiting for an answer
# that is already there (measured: 2.74s, of which two whole 1s steps), and a
# real CLI's classification already costs its own settle per look, so the
# cadence against a live pane is bounded by that, not by this.
LATENCY=$(pty_decl_get "$DECL" probe.latency 2>/dev/null || true)
case "$LATENCY" in ''|*[!0-9]*) LATENCY=30 ;; esac
AWAIT_WAIT=$LATENCY; INJECT_WAIT=$LATENCY; DEAD_WAIT=$LATENCY
TIMEOUT=$(config_get probe.timeout --topic-dir "$WS") || TIMEOUT=300
# A cached pass answers a CAPABILITY question — can this declaration's promises
# be made facts by this CLI version — and quota is a property of no key in it,
# so widening the key would be answering the wrong question more expensively.
# The cache is instead BYPASSED on the workflow's own evidence that this backend
# was unusable: an unresolved backend_quota halt on this topic. Measured: a
# relaunch inside a zero-quota window printed "cached pass" and spawned sessions
# that were born dead. The halt is still unresolved at preflight (the resume
# gate clears it later, inside the ferry), so the evidence is there to read.
# BOTH availability halts bypass it, for one reason: the question the cache
# cannot answer is "is this backend able to serve right now", and a 529-class
# refusal makes it unable exactly the way an exhausted quota does. A relaunch
# into either window on a stored pass spawns sessions that are born dead —
# measured for quota and measured again for overload (
# two attempts and ~17 minutes, then a no_novelty park).
quota_bypass=0
_halt_reason=$(state_field "$WS" halt reason 2>/dev/null || true)
case "$_halt_reason" in backend_quota|backend_overloaded)
  if [ "$(state_field "$WS" halt resolved 2>/dev/null || true)" != "1" ]; then
    quota_bypass=1
    echo "probe: a $_halt_reason halt stands unresolved — re-proving '$BACKEND' live rather than trusting a stored result (it answers capability; this halt is about availability)"
  fi ;;
esac
if [ "$quota_bypass" -eq 0 ] && probe_record_valid; then
  echo "probe: cached pass for backend '$BACKEND' at version '$version' (re-probes on version, declaration, profile, or a change in the probe's own code)"
  exit 0
fi

# --- scratch workspace: own store, own instantiated profile ------------------
PWS="$WS/.runtime/probe/ws-$BACKEND"
rm -rf "$PWS"
mkdir -p "$PWS/.runtime/state" "$PWS/.runtime/tmp" "$PWS/.runtime/logs" \
         "$PWS/.runtime/prompts" "$PWS/slices/00"
profile_rel=$(pty_decl_get "$DECL" profile) || refuse "$DECL declares no profile="
SESSION="delivery-$TOPIC-probe-$BACKEND"
# The probe renders the FULL profile, session name included — the real CLI
# executes this profile's hooks, so the pass also attests the scoped Stop
# gate's plumbing ({SESSION_NAME} -> stop-gate resolves the nonce by name).
sed -e "s|{WORKFLOW_ROOT}|$WROOT|g" -e "s|{WORKSPACE}|$PWS|g" \
    -e "s|{SESSION_NAME}|$SESSION|g" \
  "$WROOT/config/$profile_rel" > "$PWS/.runtime/profile.json" \
  || refuse "profile instantiation failed"

NONCE=$(printf 'probe.%s.%s' "$(plat_now_ns)" $$ | md5sum | cut -c1-16)
RECORD="$P_DIR/session/record.sh"
# The probe plays the ferry for this scratch session: it seeds the stage and
# sessions surfaces exactly as run_attempt would (writer class ferry) — the
# stage's true role and the real session name, the fields the emit role
# binding and the scoped Stop gate read.
printf 'slice=00\nstage=plan-validate\nround=1\nattempt=1\nstate=running\nnonce=%s\nspawn_t=%s\n' \
  "$NONCE" "$(date +%s)" | state_set "$PWS" stage ferry || refuse "probe store seed failed"
state_sessions_row author "$SESSION" 0 0 0 0 pending "$NONCE" cold "$BACKEND" \
  | state_set "$PWS" sessions ferry || refuse "probe store seed failed"

PROMPT="$PWS/.runtime/prompts/probe.md"
cat > "$PROMPT" <<EOF
<!-- volatile-header-begin (probe) -->
nonce=$NONCE
stage=plan-validate slice=00 round=1 attempt=1 mode=probe
workspace=$PWS
Your FINAL action (the Stop gate blocks the turn until it succeeds):
  $RECORD emit $PWS --stage plan-validate --nonce $NONCE --verdict ready --confidence HIGH --refine-rounds 1
<!-- volatile-header-end -->
# onboarding probe (mechanical; not real work)

1. Run one trivial shell command: \`date\`.
2. Then END your reply — output the word done and stop.
   A gate runs at EVERY turn end here. If this attempt's record is not in yet,
   it blocks the turn and prints what it wants; that block is expected and
   harmless. Follow whatever it says.
3. The emit refuses once, listing the one file this probe owes — create it with
   a single line of content, then run the header's emit command verbatim.
Do nothing else.
EOF
# NB: step 2 states what the gate DOES; it does not ask for a mistake. The
# earlier wording ("your turn-end will be BLOCKED") was an instruction to end
# record-less, and it was also false for any agent that emitted first — which
# is what two live claude/sonnet sessions did. The probe measures the gate's
# ruling, not the ordering that produced it.

LOG="$PWS/.runtime/logs/probe.log"
teardown_probe() {
  pty_teardown "$SESSION" "${SOCKET:-none}" 2>/dev/null
  case $? in 3) tmux kill-session -t "=$SESSION" 2>/dev/null || true ;; esac
}

# The scratch session's name is fixed, so a launch that died (or was killed
# while its probe hung) leaves an orphan sitting on it and the next probe
# collides — measured, right after an operator killed a probe stuck on the
# CLI's self-update prompt. The ferry fences same-name sessions before every
# cold spawn; the probe carries no state in this pane by construction, so the
# fence is unconditional and loud rather than a reuse decision.
if pty_reconcile "delivery-$TOPIC-" 2>/dev/null | command grep -qxF "$SESSION"; then
  tmux kill-session -t "=$SESSION" 2>/dev/null || true
  echo "probe: fenced a leftover scratch session '$SESSION' before spawning (a killed launch leaves one under this fixed name)"
  state_audit "$WS" operator "probe fenced a leftover scratch session $SESSION before spawning"
fi

echo "probe: spawning scratch '$BACKEND' session (model=$MODEL effort=$EFFORT; one-time per CLI version)"
ids=$(pty_spawn_cold "$DECL" "$SESSION" "$MODEL" "$EFFORT" "$PWS" "$PWS/.runtime/profile.json" "$PROMPT" "$LOG") \
  || { echo "probe FAIL: cold spawn refused/failed for $BACKEND — record: $PK (result=fail); pane log (may be absent when the session died at spawn): $LOG" >&2
       # The record is owed on THIS branch too: the README promises the refusal
       # is "named, with the record and log paths", and a spawn refusal that
       # writes nothing left both promises pointing at files that did not exist
       # (measured on a cold machine — the absent-CLI path).
       mkdir -p "$(dirname "$PK")"
       { probe_identity
         echo "result=fail"
         echo "t=$(date +%s)"
         echo "spawn_refused=1"
       } > "$PK"
       state_audit "$WS" operator "onboarding probe $BACKEND: cold spawn refused (see $PK)"
       exit 1; }
PP=$(printf '%s\n' "$ids" | grep -o 'pane_pid=[0-9]*' | cut -d= -f2)
PPS=$(printf '%s\n' "$ids" | grep -o 'pane_start=[0-9]*' | cut -d= -f2)
SP=$(printf '%s\n' "$ids" | grep -o 'server_pid=[0-9]*' | cut -d= -f2)
SPS=$(printf '%s\n' "$ids" | grep -o 'server_start=[0-9]*' | cut -d= -f2)
SOCKET=$(printf '%s\n' "$ids" | sed -n 's/.*socket=//p')

hb=miss; gate=miss; emit=miss; awaiting=miss; inject=miss; dead=miss
working=unobserved; modal=untested; quota=no; overload=no; blocked=unobserved

# The `stop_gate` item asks whether the Stop gate's plumbing works: the hook
# fires, resolves this session's nonce, reads the handoff surface and rules.
# It used to be answered BEHAVIOURALLY — the prompt asks the agent to end a
# turn record-less and this searched the pane for `turn end BLOCKED` — so the
# answer depended on the agent misbehaving as instructed. Measured twice, two
# independent claude/sonnet sessions at effort low: both wrote the owed
# artifact first, emitted, and ended cleanly. No block, `stop_gate=miss`,
# `result=fail`, and a CORRECT backend was refused with "declarations are
# promises, the probe makes them facts" — `probe_backends`'s (launch.sh) own rule is that
# the ways to not start must not share a sentence, and this was a third way
# borrowing the first one's.
# The signal is now "the gate ran and ruled correctly", which both orderings
# produce. PRIMARY evidence is the gate's own audit rows in the scratch store
# (record.sh writes one per ruling about this attempt, block or allow); the
# pane string stays as the block observation it always was, and is reported
# SEPARATELY as `stop_gate_block=` so the two facts are never conflated.
gate_scan() { # updates $gate and $blocked from the store, the pane and the log
  # Scan until settled. Phase B calls this on every poll, and once both facts
  # are in there is nothing left to learn — without this it would re-read the
  # store and re-capture the full scrollback fifteen more times per probe.
  [ "$gate" = "ok" ] && [ "$blocked" = "ok" ] && return 0
  local rows
  rows=$(state_get "$PWS" audit 2>/dev/null \
         | command grep -E "stop_gate_(block|allow) nonce=$NONCE( |$)" || true)
  if [ -n "$rows" ]; then
    gate=ok
    printf '%s\n' "$rows" | command grep -q stop_gate_block && blocked=ok
  fi
  # Block detection reads the RENDERED frame (full scrollback): the raw
  # pipe-pane stream interleaves CSI cursor-positioning bytes INSIDE the words
  # (live-measured: 'turn' CSI 'end' CSI 'BLOCKED'), so a fixed-string grep on
  # $LOG missed a block that was plainly on screen. The raw grep stays as a
  # cheap second chance for plain-stream backends.
  if [ "$blocked" = "unobserved" ]; then
    if tmux capture-pane -p -S - -t "=$SESSION:" 2>/dev/null | grep -qF "turn end BLOCKED" \
       || grep -qF "turn end BLOCKED" "$LOG" 2>/dev/null; then
      blocked=ok; gate=ok
    fi
  fi
  return 0        # a scan that finds nothing is a reading, not a failure
}

# --- phase A: watch the agent to its record (bounded by probe.timeout) -------
t0=$(date +%s)
while :; do
  now=$(date +%s)
  [ $((now - t0)) -gt "$TIMEOUT" ] && break
  state_get "$PWS" heartbeat > /dev/null 2>&1 && hb=ok
  gate_scan
  if state_get "$PWS" handoff 2>/dev/null | grep -qE "(^| )nonce=$NONCE( |$)"; then
    emit=ok
  fi
  cls=$(pty_classify_screen "$DECL" "$SESSION" 2>/dev/null || echo unknown)
  case "$cls" in
    quota_exhausted) quota=ok; break ;;   # not a broken promise: an absent resource
    backend_overloaded) overload=ok; break ;;  # nor is a backend that is up and refusing
    working) working=ok ;;
    modal.*)
      act=$(pty_decl_get "$DECL" "act.$cls" 2>/dev/null || true)
      if [ -n "$act" ]; then
        # act.modal.* may carry multiple keys ("Y Enter"); a single-arg
        # send-keys types the literal string. Split into keys, send each.
        read -ra act_keys <<< "$act"
        tmux send-keys -t "=$SESSION:" "${act_keys[@]}" 2>/dev/null || true
        modal=ok
      fi ;;
  esac
  [ "$emit" = "ok" ] && break
  if [ "$(pty_alive "$PP" "$PPS" "$SP" "$SPS")" = "dead" ]; then
    break   # died before emitting — verdict will say what was missing
  fi
  sleep 0.5
done

# A quota-dead backend ends the probe HERE, before the remaining phases spend
# their waits proving nothing. The scratch session is torn down, the verdict is
# recorded as its own result (never `pass`, so no cache is poisoned, and never
# `fail`, so nobody goes hunting through a declaration that was never
# disproved), and the pane's own line — which carries the backend's reset time
# — is handed to the operator verbatim rather than paraphrased.
# One derivation for BOTH availability refusals — quota and 529-overload differ
# in the advice they carry and in nothing else, and a re-typed copy would drift
# from the CR-normalisation and the never-pass/never-fail reasoning above the
# first time either moved.
probe_refuse_availability() { # result sigkey audit-noun headline advice…
  local result=$1 sigkey=$2 noun=$3 headline=$4; shift 4
  # One line, no CR: this value is written into a line-per-key file, so the
  # capture is normalised here rather than trusted to be tidy.
  qline=$(tmux capture-pane -p -S - -t "=$SESSION:" 2>/dev/null \
          | command grep -E "$(pty_decl_get "$DECL" "$sigkey" 2>/dev/null || echo 'a^')" \
          | tail -1 | tr -d '\r' | tr '\n\t' '  ')
  teardown_probe
  mkdir -p "$(dirname "$PK")"
  { probe_identity
    echo "result=$result"; echo "t=$(date +%s)"
    echo "quota_line=$qline"
  } > "$PK"
  state_audit "$WS" operator "onboarding probe $BACKEND@$version: $result — $noun; nothing about the declaration was tested"
  { echo "probe REFUSES: $headline"
    echo "  the pane said: ${qline:-<matched $sigkey; line not captured>}"
    printf '  %s\n' "$@"
  } >&2
  exit 4
}

if [ "$quota" = "ok" ]; then
  probe_refuse_availability backend_quota sig.quota_exhausted \
    "the scratch session's pane reported exhausted quota" \
    "backend '$BACKEND' is out of quota — this is the BACKEND, not the declaration." \
    "relaunch after the reset it names. relaunching before then spawns sessions that are born dead" \
    "and spends the attempt budget on calls that cannot succeed."
fi

# The same refusal for a backend that is UP and refusing. Without this arm the
# probe waits out its whole timeout and then reports the items it could not
# reach as MISSING — i.e. "declarations are promises" against a declaration
# that is fine, which is exactly the failure the quota signature was added to
# stop, one layer up. It ends the probe here for the same reason quota does:
# the remaining phases would spend their waits proving nothing.
if [ "$overload" = "ok" ]; then
  probe_refuse_availability backend_overloaded sig.backend_overloaded \
    "the scratch session's pane reported an overloaded backend" \
    "backend '$BACKEND' is up and refusing (529-class) — this is the BACKEND, not the declaration." \
    "no reset time is published for this state, so relaunch on judgment rather than on a clock;" \
    "it is usually transient. relaunching into it spends the attempt budget on calls that cannot succeed."
fi

# --- phase B: post-emit idle screen must classify awaiting_input -------------
# The Stop gate rules at TURN END, which is after the record lands, so phase A's
# break on `emit=ok` can outrun it. That is the SAME event this phase already
# waits for — a composer that has gone idle is a turn that has ended, and the
# hook runs before the turn can end, because blocking it is the gate's whole
# mechanism. So the gate is scanned in THIS loop and settled once after it,
# rather than behind a timer of its own: waiting on the event instead of on a
# number, one phase and one constant shorter, and it stops charging a backend
# whose hook never fires a full timer it can only ever lose.
if [ "$emit" = "ok" ]; then
  t0=$(date +%s)
  while [ $(( $(date +%s) - t0 )) -le "$AWAIT_WAIT" ]; do
    gate_scan
    [ "$(pty_classify_screen "$DECL" "$SESSION" 2>/dev/null)" = "awaiting_input" ] \
      && { awaiting=ok; break; }
    sleep 0.5
  done
  gate_scan     # the turn has ended (or the wait is spent): settle the ruling
fi

# --- phase C: the injection primitive reaches the pane -----------------------
if [ "$awaiting" = "ok" ]; then
  size0=$(wc -c < "$LOG" 2>/dev/null || echo 0)
  nudge=$(pty_decl_get "$DECL" nudge_text 2>/dev/null || echo continue)
  # A transient repaint can defer one attempt (rc 3) — bounded retries; a
  # composer-occupied refusal (rc 2) is a verdict, never retried past.
  try=0
  iout=""
  while [ $try -lt 3 ]; do
    iout=$(pty_inject "$DECL" "$SESSION" "$nudge" 2>/dev/null); irc=$?
    [ $irc -eq 0 ] || [ $irc -eq 2 ] && break
    try=$((try + 1)); sleep 0.5
  done
  if [ "${irc:-1}" -eq 0 ]; then
    t0=$(date +%s)
    while [ $(( $(date +%s) - t0 )) -le "$INJECT_WAIT" ]; do
      [ "$(wc -c < "$LOG" 2>/dev/null || echo 0)" -gt "$size0" ] && { inject=ok; break; }
      sleep 0.5
    done
  fi
fi

# --- phase D: liveness detection reads the exited CLI as dead ----------------
if [ "$inject" = "ok" ]; then
  # The promise under test is DEAD DETECTION, not a second injection. The exit
  # command used to go in directly because a post-reply composer ghost made the
  # empty-composer precondition refuse forever (pre-b1033da). The cursor rule
  # may have closed that — so MEASURE it instead of assuming: attempt the exit
  # through pty_inject first. Non-destructive: rc 0 already sent /exit (the
  # ghost let it through — measured live); any refusal falls back to
  # the raw send-keys, and the death test proceeds either way. The rc is
  # telemetry in the result file, never part of the verdict.
  t0=$(date +%s)
  while [ $(( $(date +%s) - t0 )) -le "$AWAIT_WAIT" ]; do
    [ "$(pty_classify_screen "$DECL" "$SESSION" 2>/dev/null)" != "working" ] && break
    sleep 0.5
  done
  ghost_rc=""; ghost_out=""
  # STDOUT only: rc 2 dumps the whole frame to stderr, and a merged capture put
  # a pane into a variable nothing then read. This line CAPTURED the answer to
  # this row's own question since the day it was written and threw it away.
  ghost_out=$(pty_inject "$DECL" "$SESSION" "/exit" 2>/dev/null); ghost_rc=$?
  case "$ghost_rc" in
    0) : ;;   # the ghost let injection through under the cursor rule
    *) tmux send-keys -t "=$SESSION:" -l -- "/exit" 2>/dev/null || true
       tmux send-keys -t "=$SESSION:" Enter 2>/dev/null || true ;;
  esac
  t0=$(date +%s)
  while [ $(( $(date +%s) - t0 )) -le "$DEAD_WAIT" ]; do
    [ "$(pty_alive "$PP" "$PPS" "$SP" "$SPS")" = "dead" ] && { dead=ok; break; }
    sleep 0.5
  done
fi
teardown_probe

# --- verdict -----------------------------------------------------------------
result=pass
for item in "heartbeat=$hb" "stop_gate=$gate" "emit=$emit" \
            "awaiting_input=$awaiting" "inject=$inject" "dead_detect=$dead"; do
  case "$item" in *=ok) : ;; *) result=fail ;; esac
done
mkdir -p "$(dirname "$PK")"
{
  probe_identity
  echo "result=$result"
  echo "t=$(date +%s)"
  echo "heartbeat=$hb stop_gate=$gate emit=$emit awaiting_input=$awaiting inject=$inject dead_detect=$dead working=$working modal=$modal stop_gate_block=$blocked"
  echo "ghost_rc=${ghost_rc:-} ghost_why=$(pty_inject_why "${ghost_out:-}") inject_why=$(pty_inject_why "${iout:-}")"
} > "$PK"
state_audit "$WS" operator "onboarding probe $BACKEND@$version: $result (hb=$hb stop_gate=$gate emit=$emit awaiting=$awaiting inject=$inject dead=$dead working=$working modal=$modal stop_gate_block=$blocked)"

if [ "$result" = "pass" ]; then
  echo "probe: PASS for '$BACKEND' at version '$version' (working=$working modal=$modal — soft items named, never assumed)"
  exit 0
fi
# An all-early-miss result (no heartbeat, no stop-gate block, no emit) means
# the CLI never reached ready state — not that six declarations are each wrong.
# The pane log's last non-empty lines are the actual evidence (pipe-pane wrote
# it throughout; the pane itself is torn down by now).
{
  if [ "$hb" = miss ] && [ "$gate" = miss ] && [ "$emit" = miss ]; then
    echo "probe FAIL for backend '$BACKEND' at version '$version' — the CLI never reached ready state (not a declaration problem):"
    echo "  no heartbeat, no gate ruling, no emit — the session produced no tool call, no stop, no record."
  else
    echo "probe FAIL for backend '$BACKEND' at version '$version' — the declaration or harness wiring is broken:"
    echo "  heartbeat=$hb stop_gate=$gate emit=$emit awaiting_input=$awaiting inject=$inject dead_detect=$dead"
    [ "$gate" = miss ] && echo "  stop_gate=miss means the gate never RULED on this attempt (no stop_gate_block/stop_gate_allow row in $PWS/.runtime/state/audit) — the hook did not fire, not that the agent behaved well."
  fi
  echo "  evidence: $PK · pane log: $LOG · scratch store: $PWS/.runtime/state/"
  echo "  pane log (last non-empty lines):"
  grep -v '^[[:space:]]*$' "$LOG" 2>/dev/null | tail -5 | sed 's/^/    /' || echo "    (no pane log)"
} >&2
exit 1
