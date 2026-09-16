#!/usr/bin/env bash
# ferry.sh — the driver loop (architecture.md §5–6, state-and-liveness.md).
# Table-driven: next stage = stages.tsv (stage, verdict) → next, nothing else.
# The ferry never parses artifact prose — only store surfaces, stages.tsv, and
# record fields. Split per architecture §4.1 layout freedom to stay ≤800
# lines: lib/compose.sh (prompt composition + fingerprints), lib/watch.sh
# (the liveness wait loop), lib/resume.sh (the halt-resume gate),
# lib/locks.sh (the host + repo claims), lib/index.sh (the slices index +
# its scheduler), lib/admission.sh (may we spawn on this assignment, and
# in what session mode), lib/preflight.sh (is the world still the one this
# run started against — fence, store, run surface, the two pins) and
# lib/attempt.sh (may this assignment spend another attempt, and the spawn
# and wait that follow) are ferry halves; only ferry.sh sources them.
#
# Exit codes (watchdog classifies these, nothing else):
#   0 complete · 20 deliberate park/refuse · 30 store fault · other = crash.

set -uo pipefail
export LC_ALL=C
FERRY_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
WROOT=$(cd "$FERRY_DIR/.." && pwd)
. "$FERRY_DIR/lib/state.sh"
. "$FERRY_DIR/lib/config.sh"
. "$FERRY_DIR/lib/owed.sh"
. "$FERRY_DIR/lib/gates.sh"
. "$FERRY_DIR/lib/notify.sh"
. "$FERRY_DIR/lib/compose.sh"
. "$FERRY_DIR/lib/watch.sh"
. "$FERRY_DIR/lib/resume.sh"
. "$FERRY_DIR/lib/index.sh"
. "$FERRY_DIR/lib/locks.sh"
. "$FERRY_DIR/lib/admission.sh"
. "$FERRY_DIR/lib/preflight.sh"
. "$FERRY_DIR/lib/attempt.sh"
. "$FERRY_DIR/backends/pty_tmux.sh"

[ $# -ge 1 ] || { echo "usage: ferry.sh <workspace>" >&2; exit 20; }
WS=$(cd "$1" 2>/dev/null && pwd) || { echo "refuse: workspace $1 not a directory" >&2; exit 20; }
TOPIC=$(basename "$(cd "$WS/.." && pwd)")
HOST_LOCK=$(state_host_lock_path "$WS")
OWN_LOCK=0

die_store() {
  echo "STORE FAULT: $*" >&2
  notify_fire "$WS" park store_fault "store fault: $* (workspace $WS)" || true
  exit 30
}

# A CONFIG fault is not a store fault, and the two must not share a sentence.
# die_store answered rc 3 from config_get with exit 30 under a `store_fault`
# banner — naming the checksummed store for an operator's typo, and spending
# the watchdog's relaunch budget on a config that cannot resolve. A workspace
# kv file is a workflow/topic INPUT, which is what template_error already
# names. The run-init reads precede any stage, so they have nothing to park on
# and nothing to resume into: those refuse instead (same rc class, own shape).
park_config() { # key
  park template_error "config fault resolving '$1' — config_get refused a file in the resolution chain (defaults.kv ⊂ operator config.kv ⊂ topic.kv ⊂ slice.<nn>.<agent>.kv); the CONFIG FAULT line on stderr names the offending key and the file it is in. this is a workflow/topic INPUT defect, not an agent failure and not store corruption: fix that input, then relaunch"
}
refuse_config() { # key
  echo "refuse: config fault resolving '$1' at run init — the CONFIG FAULT line above names the offending key and file; no stage exists yet to park on. fix that input under $WS/config/, then relaunch" >&2
  exit 20
}

ledger() { # message-kv...
  # An append failure the caller cannot see is how a whole cycle's event
  # ledger once vanished (silent-append-loss): name every lost event on
  # stderr; page store_fault ONCE per ferry process (not a pager storm —
  # the startup integrity gate is the hard stop at the next launch). Never
  # die here: ledger() runs inside park()/die paths, and losing an event
  # must not preempt the park that is being recorded.
  if ! state_append "$WS" ledger ferry "v=1 t=$(date +%s) $*" > /dev/null 2>&1; then
    echo "LEDGER APPEND FAILED (surface fault?) — event lost: $*" >&2
    if [ "${_LEDGER_FAULT_PAGED:-0}" -eq 0 ]; then
      _LEDGER_FAULT_PAGED=1
      notify_fire "$WS" park store_fault "ledger appends are FAILING on $WS — events are being lost; the next launch parks store_fault (verify the ledger surface, then reseal its header sum)" || true
    fi
  fi
}

sfield() { # surface key -> value (absent -> empty; fault -> die)
  local v rc
  v=$(state_field "$WS" "$1" "$2" 2>/dev/null); rc=$?
  [ $rc -eq 3 ] && die_store "surface $1 corrupt"
  [ $rc -eq 0 ] && printf '%s\n' "$v"
  return 0
}

sput() { # surface key=value...  (writer ferry; fault -> die)
  local s=$1; shift
  state_put "$WS" "$s" ferry "$@" > /dev/null || die_store "write to surface $s failed"
}

cfg() { # key [extra config_get args] -> value; rc 3 = config FAULT, absent = empty
  # A fault cannot stop the ferry from in here. Every caller reads cfg through
  # a command substitution, and dying inside one kills the SUBSHELL only — the
  # parent then carries on holding an empty string. Measured while building a
  # fixture: a resolver fault (a cross-key invariant violation in topic.kv)
  # became an empty budget, and the run parked `budget_wallclock` reporting
  # "1s working > s" — a park naming a cap it had never read. `fault ≠ absent`
  # is the store's rule and config is held to it too, so the fault travels as
  # a STATUS the caller must consume; every call site below answers it.
  local v rc
  v=$(config_get "$@" --topic-dir "$WS" 2>&1); rc=$?
  if [ $rc -eq 3 ]; then
    echo "CONFIG FAULT resolving '$1': $v" >&2
    return 3
  fi
  [ $rc -eq 0 ] && printf '%s\n' "$v"
  return 0
}

rec_field() { # record-line key
  printf '%s\n' "$1" | awk -v k="$2" '{for(i=1;i<=NF;i++) if($i ~ "^" k "="){sub("^" k "=","",$i); print $i; exit}}'
}
# detail is FREE TEXT (spaces), always the record's LAST field (record.sh
# appends it last) — field-splitting would keep only the first word and the
# owner's page would lose the question set. Take everything after " detail=".
rec_detail() { # record-line
  printf '%s\n' "$1" | awk '{i=index($0," detail="); if(i) print substr($0, i+8)}'
}

# ---------------------------------------------------------------- parks -----
park() { # reason detail [screen_file]
  local reason=$1 detail=$2 screen=${3:-}
  detail=$(printf '%s' "$detail" | tr '\n\t' '  ')
  {
    echo "reason=$reason"
    echo "detail=$detail"
    echo "slice=${G_SLICE:-}"
    echo "stage=${G_STAGE:-}"
    echo "round=${G_ROUND:-}"
    echo "t=$(date +%s)"
    # halt_id: rulings bind by IDENTITY (epoch seconds are too coarse; a
    # ruling for a previous halt must never answer a new one).
    echo "halt_id=$(date +%s%N).$$"
    echo "notified=0"
    echo "resolved=0"
    # Screen text travels as a SIDECAR file only — inlining free text after
    # the kv block let a captured 'resolved=1' (or any 'key=' line) override
    # the real fields in every last-match reader. The capture is copied to a
    # durable path (the caller's file may be tmp).
    if [ -n "$screen" ] && [ -f "$screen" ]; then
      mkdir -p "$WS/.runtime/logs"
      cp -f "$screen" "$WS/.runtime/logs/halt-screen.txt" 2>/dev/null \
        && echo "screen_file=$WS/.runtime/logs/halt-screen.txt" \
        || echo "screen_file=$screen"
    fi
  } | state_set "$WS" halt ferry || die_store "halt write failed while parking ($reason)"
  ledger "event=park reason=$reason slice=${G_SLICE:-} stage=${G_STAGE:-} detail=$detail"
  # At-least-once: the notified flag is set ONLY on rc 0 (the transport took
  # the page, or policy suppressed it). A refused send leaves 0, so a relaunch
  # re-sends. rc 0 is not a receipt — lib/notify.sh's rc contract states what
  # it does and does not prove.
  if notify_fire "$WS" park "$reason" "PARK $reason (topic $TOPIC slice ${G_SLICE:-} stage ${G_STAGE:-}): $detail"; then
    state_put "$WS" halt ferry "notified=1" > /dev/null 2>&1 || true
  fi
  echo "parked: $reason — $detail" >&2
  exit 20
}

on_term() { park operator_stop "SIGTERM received — graceful park; sessions kept for postmortem"; }
trap on_term TERM INT

# ------------------------------------------- sessions surface + EXIT trap ----
# What the startup section left behind when lib/preflight.sh took the fence, the
# store check, the run surface and the two pins: the sessions accessors, which
# are not preflight — every attempt reads and rewrites this surface.
# The two exclusivity locks (host, repo) are lib/locks.sh — one of the ferry's
# halves. Their EXIT trap is wired here, where the globals it reads are set.
trap release_lock EXIT

sessions_entry() { # role -> record line (empty if none)
  state_get "$WS" sessions 2>/dev/null | command grep -E "(^| )role=$1( |$)" | tail -1 || true
}
sessions_replace() { # role new-line ('' to remove)
  local body rc
  body=$(state_get "$WS" sessions 2>/dev/null); rc=$?
  [ $rc -eq 3 ] && die_store "sessions surface corrupt"
  # NB: `[ -z ] ||` not `[ -n ] &&` — on removal ('' entry) the latter would be
  # the group's exit status (1) and pipefail would read a successful write as
  # failure (drill-caught at slice teardown).
  { printf '%s\n' "$body" | command grep -vE "(^| )role=$1( |$)" | command grep -v '^$'
    [ -z "$2" ] || printf '%s\n' "$2"; } | state_set "$WS" sessions ferry \
    || die_store "sessions write failed"
}

# ------------------------------------------------------ table + position ----
stage_row_field() { owed_stage_row "$1" | awk -F'\t' -v n="$2" '{print $n}'; }
stage_scope() { stage_row_field "$1" 2; }
stage_session_mode() { stage_row_field "$1" 3; }
stage_next_for() { # stage verdict -> target
  # Universal halt path: a record may carry HALT_class_u / HALT_blocked from ANY
  # stage (record.sh --halt); the table's explicit spellings cover the common
  # routes only (design/state-and-liveness.md §2).
  case "$2" in HALT_class_u|HALT_blocked) printf '%s\n' "$2"; return 0 ;; esac
  local map
  map=$(stage_row_field "$1" 6)
  printf '%s\n' "$map" | tr ',' '\n' | awk -F: -v v="$2" '$1==v{print $2; exit}'
}
stage_role() { owed_stage_role "$1"; }

load_position() {
  local body rc
  body=$(state_get "$WS" stage 2>/dev/null); rc=$?
  [ $rc -eq 3 ] && die_store "stage surface corrupt"
  if [ $rc -eq 1 ]; then G_STATE=none; return 0; fi
  G_SLICE=$(printf '%s\n' "$body" | awk -F= '$1=="slice"{v=$2} END{print v}')
  G_STAGE=$(printf '%s\n' "$body" | awk -F= '$1=="stage"{v=$2} END{print v}')
  G_ROUND=$(printf '%s\n' "$body" | awk -F= '$1=="round"{v=$2} END{print v}')
  G_ATTEMPT=$(printf '%s\n' "$body" | awk -F= '$1=="attempt"{v=$2} END{print v}')
  G_STATE=$(printf '%s\n' "$body" | awk -F= '$1=="state"{v=$2} END{print v}')
  G_NONCE=$(printf '%s\n' "$body" | awk -F= '$1=="nonce"{v=$2} END{print v}')
  G_SPAWN_T=$(printf '%s\n' "$body" | awk -F= '$1=="spawn_t"{v=$2} END{print v}')
}

enter_stage() { # slice stage
  local slice=$1 stage=$2 r
  [ "$(stage_scope "$stage")" = "topic" ] && slice=00
  if [ "$stage" = "spec" ]; then check_plan_pin; fi
  r=$(sfield attempts "round.$slice.$stage"); r=$(( ${r:-0} + 1 ))
  sput attempts "round.$slice.$stage=$r"
  [ -z "$(sfield attempts "slice.$slice.started")" ] && sput attempts "slice.$slice.started=$(date +%s)"
  local cu_total="" cbase="" fhbase=""
  case "$stage" in impl|fix) cu_total=$(owed_cu_total "$WS" "$slice") ;; esac
  # fix-round evidence anchors: emit refuses a zero-action fix (no commit new
  # since the HEAD baseline AND conformance unchanged vs its baseline).
  if [ "$stage" = "fix" ]; then
    cbase=$(md5sum "$WS/slices/$slice/conformance.md" 2>/dev/null | awk '{print $1}')
    # the baseline is the SLICE's repo: a doc-bound fix lands in the doc repo,
    # and a code-repo HEAD would call every doc commit "new work" (and vice versa)
    fhbase=$(git -C "$(binding_repo "$WS" "$slice" 2>/dev/null)" rev-parse HEAD 2>/dev/null || echo "")
  fi
  # IDENTITY AND LIVENESS ARE ONE WRITE HERE TOO. This establishes a NEW stage
  # identity, so the previous stage's `live_*` block must not survive it:
  # `_state_put_core` drops only the keys a write NAMES, and until this line
  # carried them, entering a stage left the dead session's heartbeat, idle and
  # elapsed on the surface. The panel suppresses liveness only when PARKED, and
  # an entered stage is not parked — so the window between here and the spawn
  # write drew the previous stage's numbers under the new stage's header. The
  # same six keys `run_attempt` clears; `55-monitor` derives the set from the
  # publisher and finds this site by the `nonce=` it names, so a new identity
  # write cannot be added without one.
  sput stage "slice=$slice" "stage=$stage" "round=$r" "attempt=0" "state=entered" \
    "nonce=-" "spawn_t=0" "cu_total=${cu_total:-}" "conformance_baseline=${cbase:-}" \
    "fix_head_baseline=${fhbase:-}" \
    "live_class=" "live_hb_age=" "live_age=" "live_idle=" "live_working=" "live_t="
  if [ "$slice" != "00" ]; then
    slices_set_status "$slice" active
    local rd
    rd=$(state_get "$WS" slices 2>/dev/null | command grep -E "(^| )id=$slice( |$)" | command grep -c 'rederive=1' || true)
    if [ "${rd:-0}" -gt 0 ] && [ "$stage" = "spec" ]; then
      state_audit "$WS" ferry "slice $slice was restored: premise must be re-derived from scratch (rederive flag)"
    fi
  fi
  ledger "event=enter slice=$slice stage=$stage round=$r"
  load_position
}


# ------------------------------------------------------------- advance ------
check_severity_trend() { # current-record-line  (covers BOTH review loops:
  # precheck↔revise and postcheck↔fix — fix-round evidence keeps every fix
  # fingerprint fresh and the attempt budget resets per round, so without this
  # the fix loop's only bound is wallclock, and that park misnames the cause)
  local cur prev
  cur=$(rec_field "$1" findings.substantive)
  [ -n "$cur" ] && [ "$G_ROUND" -ge 2 ] || return 0
  # A hand-corrupted count must not silently disarm the predicate: numeric
  # comparison on garbage returns test-error, which `|| return 0` would read
  # as convergence.
  printf '%s\n' "$cur" | command grep -qE '^[0-9]+$' \
    || park stall_record "review record carries non-numeric findings.substantive='$cur' — the convergence predicate cannot read it"
  # Wording-only rounds (substantive=0) never signal disagreement — wording
  # never blocks alone (review-standards §1); 0>=0 is convergence, not discord.
  [ "$cur" -ge 1 ] || return 0
  # An owner ruling on a prior disagreement park discharged this
  # (slice, stage, round) — stage-scoped: rounds are numbered per
  # (slice, stage), so an unscoped key would let a precheck ruling
  # discharge the postcheck loop at the same numbers.
  [ "$(sfield attempts "trend_ok.$G_SLICE.$G_STAGE.$G_ROUND")" = "1" ] && return 0
  # The reviewer's own split of the count (review-standards §1): a REPEAT is a
  # finding that continues a previous round's, so a non-decreasing count parks
  # only when the newer round carries one — an all-new round is the loop
  # converging on the material it was given, not author↔reviewer discord. A
  # record with no split predates the field and reads as all-repeat, so its
  # interpretation is unchanged.
  local rep new
  rep=$(rec_field "$1" findings.substantive.repeat)
  new=$(rec_field "$1" findings.substantive.new)
  [ -n "$rep" ] || { rep=$cur; new="unfielded"; }
  printf '%s\n' "$rep" | command grep -qE '^[0-9]+$' \
    || park stall_record "review record carries non-numeric findings.substantive.repeat='$rep' — the convergence predicate cannot read it"
  prev=$(state_get "$WS" handoff 2>/dev/null \
    | command grep -E "(^| )slice=$G_SLICE( |$)" | command grep -E "(^| )stage=$G_STAGE( |$)" \
    | command grep -E "(^| )round=$((G_ROUND - 1))( |$)" | tail -1)
  prev=$(rec_field "$prev" findings.substantive)
  if [ -n "$prev" ] && [ "$cur" -ge "$prev" ] && [ "$rep" -ge 1 ]; then
    # The owner rules from the reviewer's own absorption section, so the park
    # names both review files and points at it — the one thing the ferry holds
    # that the reviewer does not is the count.
    park disagreement "severity-trend: $G_STAGE round $((G_ROUND - 1))→$G_ROUND substantive findings $prev→$cur (non-decreasing), of which repeat=$rep new=$new — at least one finding survived the previous round's remediation (rebutted, absorbed in part, or re-introduced). reviews: slices/$G_SLICE/${G_STAGE//-/}.$((G_ROUND - 1)).md → slices/$G_SLICE/${G_STAGE//-/}.$G_ROUND.md; the later one's '## 3. absorption' names which findings survived and whether the loop is narrowing — rule from it. owner options: continue / split / redesign (launch.sh rule)"
  fi
  # The bound the split removes and this restores: a loop whose every round finds
  # NEW material never carries a repeat, so without a round cap its only stop
  # would be wallclock — a park that misnames the cause. Same halt class, same
  # discharge; the text says which predicate fired.
  local rmax
  rmax=$(cfg review.max_rounds) || park_config review.max_rounds
  printf '%s\n' "$rmax" | command grep -qE '^[0-9]+$' && [ "$rmax" -ge 2 ] \
    || park_config review.max_rounds
  if [ "$G_ROUND" -ge "$rmax" ]; then
    park disagreement "review round bound: $G_STAGE round $G_ROUND has reached review.max_rounds=$rmax with substantive findings still open (this round: substantive=$cur new=$new repeat=$rep). the loop is not converging by rounds, whatever each round's split says — read slices/$G_SLICE/${G_STAGE//-/}.$((G_ROUND - 1)).md and slices/$G_SLICE/${G_STAGE//-/}.$G_ROUND.md (the later one's '## 3. absorption' first) before ruling; owner options: continue / split / redesign (launch.sh rule)"
  fi
}

check_decomposition_fixpoint() { # current-record-line  (the TOPIC loop's bound)
  # split↔split-check is the only review loop with no convergence predicate, and
  # it cannot borrow the severity-trend one — not because of a case arm, but
  # because of what the two loops iterate over. §6's eight criteria are all
  # properties of the DECOMPOSITION, and §6 says so mechanically: "a hard edge
  # that exists only as prose is a substantive finding (the scheduler cannot
  # read prose)". The decomposition is the slices index. What split-check's
  # findings LAND on is charters.md, whose attestation prose grows every round by
  # construction — a round that absorbs a finding adds the sentence describing
  # the absorption. A monotone, unbounded claim surface has no last element, so
  # counting findings over it cannot be made to terminate; measured, one topic
  # ran 13 rounds and 21 substantive findings, none of which moved a boundary,
  # id, binding or risk class, against an index that emitted 13 times with ONE
  # distinct value.
  # So convergence is computed on the decided artifact instead: N identical
  # emits mean the author was asked to re-cut and produced the same cut. This
  # counts no findings at all, which is why it cannot inherit the count-only
  # blindness that makes a floor unsafe for check_severity_trend.
  local verdict n rows distinct
  verdict=$(rec_field "$1" verdict)
  [ "$verdict" = "flag" ] || return 0        # concur advances; only a re-cut loops
  [ "$(sfield attempts "trend_ok.$G_SLICE.$G_STAGE.$G_ROUND")" = "1" ] && return 0
  n=$(cfg split.fixpoint_emits) || park_config split.fixpoint_emits
  printf '%s\n' "$n" | command grep -qE '^[0-9]+$' && [ "$n" -ge 2 ] \
    || park_config split.fixpoint_emits
  rows=$(state_get "$WS" ledger 2>/dev/null | command grep -F 'event=slices_index' | tail -n "$n")
  # The fixpoint is tried FIRST and falls THROUGH to the bound below rather than
  # returning: "the index is not frozen" is the thrash shape, which is exactly
  # what the bound exists for, so an early return here would make the bound
  # unreachable for the only case it covers. Measured: it did, and the fixture
  # that drives a changed index at the cap is what said so.
  if [ "$(printf '%s\n' "$rows" | command grep -c .)" -ge "$n" ]; then
    # Identity is the INDEX's bytes and nothing else. Stripped by KNOWN PREFIX,
    # never by field extraction: a title may contain spaces (46-convergence
    # drives one), so `rec_field ... slices` truncates at the first space and
    # collapses two different cuts that share a prefix — measured, it made a
    # CHANGED index read as a fixpoint and park. The third sed is a no-op on
    # rows written before `decisions=` existed, which is what keeps old ledgers
    # comparing exactly as they did.
    local dfirst dlast dnote=""
    distinct=$(printf '%s\n' "$rows" \
      | sed -e 's/^v=1 t=[0-9]* //' -e 's/^event=slices_index //' -e 's/^decisions=[0-9]* //' \
      | sort -u | command grep -c .)
    dfirst=$(rec_field "$(printf '%s\n' "$rows" | head -1)" decisions)
    dlast=$(rec_field "$(printf '%s\n' "$rows" | tail -1)" decisions)
    if [ -z "$dfirst" ] || [ -z "$dlast" ]; then
      dnote="These emits predate the decisions= field, so the count is unavailable and you must read the surface yourself."
    elif [ "$dfirst" != "$dlast" ]; then
      dnote="AND THE ROUNDS WERE NOT EMPTY: class=A decisions went $dfirst -> $dlast across these emits, so the author re-bound something the index cannot express. Read those rows first."
    else
      dnote="class=A decisions did not move across these emits ($dfirst), which is the only reading that supports 'nothing was decided'."
    fi
    [ "$distinct" -eq 1 ] && park disagreement "decomposition fixpoint: the slices index is byte-identical across the last $n split emits. That bounds the CUT, not the round — commit units and case-to-slice bindings live in the charter's prose and on the DECISIONS surface, one level below anything the index's id:risk:repo:title:after can encode, and a re-split that only re-binds those is invisible here (measured: a 64-minute round that left the index identical and produced 00/DP-2). $dnote Read slices/00/decisions and the review before ruling; a finding that moves no boundary, id, binding or risk class is not a re-cut, but a class=A re-binding is. owner options: continue / split / redesign (launch.sh rule)"
  fi
  # The shape the fixpoint cannot see, and the reason this is a second arm and
  # not a wider first one: a decomposition that THRASHES emits a different index
  # every round, so control reaches here only when the cut kept moving. Slice 00
  # is exempt from the slice wallclock (attempt.sh), so without this the loop's
  # only stop is the three-day topic budget parking on a cause it never
  # diagnosed. Same halt class, same ruled discharge, own text.
  local rmax
  rmax=$(cfg split.max_rounds) || park_config split.max_rounds
  printf '%s\n' "$rmax" | command grep -qE '^[0-9]+$' && [ "$rmax" -ge 2 ] \
    || park_config split.max_rounds
  if [ "$G_ROUND" -ge "$rmax" ]; then
    park disagreement "split round bound: split-check round $G_ROUND has reached split.max_rounds=$rmax with the decomposition still flagged. the index CHANGED between emits every round — a frozen one would have parked as a fixpoint before reaching here — so the cut is thrashing rather than settled, and the only bound left is the topic wallclock, which parks on a cause it cannot state. read slices/$G_SLICE/${G_STAGE//-/}.$((G_ROUND - 1)).md and slices/$G_SLICE/${G_STAGE//-/}.$G_ROUND.md before ruling: a cut that moves every round is a plan question, not a review one. owner options: continue / split / redesign (launch.sh rule)"
  fi
}

teardown_slice_sessions() {
  local role entry rc
  for role in author reviewer; do
    entry=$(sessions_entry "$role")
    [ -n "$entry" ] || continue
    pty_teardown "$(rec_field "$entry" name)" "$(rec_field "$entry" socket)" 2>/dev/null; rc=$?
    if [ $rc -eq 3 ]; then
      park dead "teardown fail-closed: recorded tmux socket for $(rec_field "$entry" name) is gone while the launcher generation lives — inspect manually; never started a replacement server"
    fi
    sessions_replace "$role" ""
    ledger "event=teardown role=$role session=$(rec_field "$entry" name)"
  done
}

complete_topic() {
  teardown_slice_sessions   # two sessions per slice, BOTH closed (incl. the close-out session)
  # park()'s write->notify->flag order: an undelivered completion page keeps
  # notified=0 and re-sends at the next relaunch, never lost.
  {
    echo "reason=push_gate"; echo "detail=close-out done — review the ledger and push (Class U; the workflow never pushes)"
    echo "slice=00"; echo "stage=close-out"; echo "t=$(date +%s)"
    echo "halt_id=$(date +%s%N).$$"; echo "notified=0"; echo "resolved=0"
  } | state_set "$WS" halt ferry || true
  if notify_fire "$WS" topic.done none "topic $TOPIC complete: close-out done; push is the owner's (Class U)"; then
    state_put "$WS" halt ferry "notified=1" > /dev/null 2>&1 || true
  fi
  ledger "event=complete topic=$TOPIC"
  release_repo_locks
  rm -f "$HOST_LOCK.reclaim"
  echo "topic $TOPIC COMPLETE — push_gate is yours" >&2
  exit 0
}

do_advance() {
  local rec verdict target missing rc
  rec=$(state_get "$WS" handoff 2>/dev/null | command grep -E "(^| )nonce=$G_NONCE( |$)" | tail -1 || true)
  [ -n "$rec" ] || park stall_record "stage marked done but no handoff record for nonce $G_NONCE — record vanished or store rolled back"
  [ "$(rec_field "$rec" stage)" = "$G_STAGE" ] \
    || park stall_mismatch "handoff record stage '$(rec_field "$rec" stage)' != active stage '$G_STAGE'"
  verdict=$(rec_field "$rec" verdict)
  [ -n "$verdict" ] || park stall_record "handoff record missing verdict field: $rec"
  target=$(stage_next_for "$G_STAGE" "$verdict")
  [ -n "$target" ] || park stall_record "no stages.tsv transition for ($G_STAGE, $verdict) — table drift"

  # HALT_* routes BEFORE the owed re-check: a halted stage owes no artifacts
  # (the halt IS the outcome, record.sh --halt bypasses owed by design) — an
  # owed check here would misfile every class_u/blocked halt as owed_miss.
  case "$target" in
    HALT_class_u) park class_u "stage $G_STAGE verdict '$verdict' routes to the owner (Class U): $(rec_detail "$rec") — answer with launch.sh rule" ;;
    HALT_blocked) park blocked "stage $G_STAGE reported blocked: $(rec_detail "$rec") — see slices/$G_SLICE artifacts; answer with launch.sh rule" ;;
  esac

  [ "$G_STAGE" = "split" ] && ingest_slices "$(rec_field "$rec" slices)"
  # A completed split-check discharges any pending re-slice proposal pointer
  # (concur = the index stands; flag = split re-derives and applies). On
  # concur the DECLINED proposer must close: its turnover already completed
  # (verdict reslice, not done — only next_slice marks done), and without an
  # explicit disposition it strands active forever (next_pending_slice
  # schedules only pending; close-out would meet an undisposed active row).
  # Under flag, ingest_slices disposes it (kept or superseded) instead.
  if [ "$G_STAGE" = "split-check" ]; then
    local rfrom
    rfrom=$(sfield attempts reslice_from)
    if [ -n "$rfrom" ] && [ "$verdict" = "concur" ]; then
      slices_set_status "$rfrom" done
      ledger "event=reslice_declined slice=$rfrom"
      notify_fire "$WS" slice.done none "slice $rfrom done (re-slice proposal declined; standing index holds)" || true
    fi
    sput attempts "reslice_from="
  fi
  missing=$(owed_check "$WS" "$G_STAGE" "$G_SLICE" --round "$G_ROUND" --nonce "$G_NONCE"); rc=$?
  [ $rc -eq 3 ] && die_store "owed check fault: $missing"
  [ $rc -ne 0 ] && park owed_miss "DONE record with missing owed items for (slice=$G_SLICE stage=$G_STAGE): $(printf '%s' "$missing" | tr '\n' '; ') — first miss parks, never an identical respawn"
  case "$G_STAGE" in
    precheck|postcheck) check_severity_trend "$rec" ;;
    split-check)        check_decomposition_fixpoint "$rec" ;;
  esac

  if [ "$G_STAGE" = "split" ] && [ -z "$(sfield run plan_hash)" ]; then
    sput run "plan_hash=$(md5sum "$WS/../plan.md" 2>/dev/null | awk '{print $1}')"
    ledger "event=plan_pinned"
  fi
  case "$G_STAGE:$verdict" in
    spec:drafted) notify_fire "$WS" spec.ready none "spec ready: slice $G_SLICE" ;;
    turnover:done) notify_fire "$WS" slice.done none "slice $G_SLICE done" ;;
  esac
  ledger "event=advance slice=$G_SLICE stage=$G_STAGE verdict=$verdict target=$target"

  case "$target" in
    COMPLETE) complete_topic ;;
    slice_loop|next_slice)
      if [ "$target" = "next_slice" ]; then
        teardown_slice_sessions
        slices_set_status "$G_SLICE" done
      fi
      schedule_next_slice ;;
    *)
      if [ "$G_STAGE" = "turnover" ] && [ "$verdict" = "reslice" ]; then
        # The proposal is this slice's turnover.md: stamp the pointer so
        # split-check's manifest (PROPOSAL=reslice.pending) can hand it over —
        # concurrence must SEE the proposal (Class C, two keys).
        sput attempts "reslice_from=$G_SLICE"
        teardown_slice_sessions   # re-slice routes through split-check; slice sessions close
      fi
      enter_stage "$G_SLICE" "$target" ;;
  esac
}

recover_running() {
  local role entry backend decl
  role=$(stage_role "$G_STAGE")
  entry=$(sessions_entry "$role")
  backend=$(sfield stage backend)
  if [ -z "$backend" ]; then
    backend=$(cfg "agent.$role.backend") || park_config "agent.$role.backend"
  fi
  decl="$WROOT/config/backends/$backend.kv"
  if [ -n "$entry" ] && [ "$(rec_field "$entry" nonce)" = "$G_NONCE" ]; then
    local pp pps sp sps
    pp=$(rec_field "$entry" pane_pid); pps=$(rec_field "$entry" pane_start)
    sp=$(rec_field "$entry" server_pid); sps=$(rec_field "$entry" server_start)
    if [ "$(pty_alive "$pp" "$pps" "$sp" "$sps")" = "running" ]; then
      state_audit "$WS" ferry "ferry restart: re-attached wait on live attempt (stage=$G_STAGE nonce=$G_NONCE)"
      wait_attempt "$decl" "$(rec_field "$entry" name)" "$pp" "$pps" "$sp" "$sps" "$G_NONCE" "${G_SPAWN_T:-$(date +%s)}"
      return 0
    fi
  fi
  # The record may have landed while we were down.
  if state_get "$WS" handoff 2>/dev/null | command grep -qE "(^| )nonce=$G_NONCE( |$)"; then
    sput stage "state=done"
  else
    sput attempts "lastfail.$G_SLICE.$G_STAGE=dead"
    sput stage "state=failed"
    state_audit "$WS" ferry "ferry restart: attempt session dead, marked failed(dead)"
  fi
}

# ---------------------------------------------------------------- main ------
main() {
  mkdir -p "$WS/.runtime/state" "$WS/.runtime/tmp" "$WS/.runtime/logs" "$WS/.runtime/prompts"
  case "$TOPIC" in *[!A-Za-z0-9_-]*)
    echo "refuse: topic directory name '$TOPIC' outside [A-Za-z0-9_-] — tmux session names embed it" >&2
    exit 20 ;;
  esac
  take_host_lock
  take_repo_locks
  check_store_integrity
  ensure_run_surface
  # Resume BEFORE the pin checks: a workflow_changed/plan_changed halt can only
  # be answered here (repin / ruling); pins-first would re-park the same halt
  # forever and no relaunch could ever resume it.
  resume_halt_gate
  check_workflow_pin
  check_plan_pin
  reconcile_fence
  ledger "event=ferry_start pid=$$"
  while :; do
    load_position
    if [ -e "$WS/.runtime/stop-request" ] && [ "${G_STATE:-none}" != "running" ]; then
      rm -f "$WS/.runtime/stop-request"
      park operator_stop "operator stop request — graceful park between attempts"
    fi
    reroute_if_slice_retired && continue
    case "${G_STATE:-none}" in
      none) enter_stage 00 plan-validate ;;
      entered|failed) run_attempt ;;
      running) recover_running ;;
      done) do_advance ;;
      *) park stall_record "stage surface state '${G_STATE:-}' unrecognized" ;;
    esac
  done
}

main
