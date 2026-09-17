#!/usr/bin/env bash
# launch.sh — the ONE operator entry (architecture.md §9). Verbs:
#   launch <ws> [--attach]       preflight + init + watchdog (detached); returns.
#                                --attach execs into the read-only monitor
#   rule <ws> --slice NN [--topic] [--stage S] --text '...'|--file F   (NN = 2-digit id)
#                                Class U return path → rulings surface +
#                                slices/<nn>/ruling.N.md archive (the one
#                                deliberate store→file double, one direction);
#                                --topic: the ruling rides every slice's manifest
#   stop <ws>                    graceful park; sessions kept for postmortem
#   ack <ws>                     acknowledge the current park: the watchdog PAUSES
#                                re-paging for notify.ack_timeout, then resumes
#                                while the park stands (nothing else changes;
#                                resume is still rule / relaunch)
#   slice <ws> <id> <cancelled|restored>
#                                guarded index status change (restore sets the
#                                premise-rederive flag; 'pending' accepted as
#                                the internal spelling)
#   status <ws> [--slices|--rounds|--halt]
#                                monitor --once, whose FIRST line is machine-
#                                readable for a poll: state=<NOT_STARTED|
#                                RUNNING|BETWEEN_STAGES|PARKED|COMPLETE|BROKEN|
#                                STORE_FAULT> [reason=…] gate_fails=<n|absent|
#                                fault> attestations=<n> — the closed state set
#                                a poll keys on without scraping painted text,
#                                and the running quality-gate FAIL count no
#                                other live surface carries (refusals are
#                                absorbed in-session by design, so parks and
#                                pages never see them); --slices prints the per-slice
#                                table instead (both clocks labelled, backend
#                                column naming the exception, not the norm);
#                                --rounds prints the per-stage per-round clock
#                                from the ledger (a round opens at enter, closes
#                                at advance; parks annotated with their gap);
#                                --halt prints the halt surface with its detail
#                                UNTRUNCATED (what the parked panel points at)
#   notify <ws> <preset|event=on|off>
#                                policy surface, hot-read by the ferry
#   observe <ws> --text '...'|--file F
#                                append a workflow-defect observation (the
#                                pilot's observation duty needs a write path;
#                                --file carries code fragments un-mangled)
#   peek <ws> [role] [--follow|--attach]
#                                one pane per session, READ-ONLY: capture-pane
#                                makes no client and cannot change geometry —
#                                the "look" half of look/type (attach is for
#                                typing, and keeps its friction). --follow
#                                repaints every 2s; --attach PRINTS the attach
#                                command instead of capturing
# Deferred verbs (built on demonstrated need, NOT here): salvage, wait.
# The pilot's action set is exactly this verb set — no private channel.

set -uo pipefail
export LC_ALL=C
L_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
WROOT=$(cd "$L_DIR/.." && pwd)
. "$L_DIR/lib/state.sh"
. "$L_DIR/lib/config.sh"
. "$L_DIR/lib/notify.sh"
. "$L_DIR/lib/readers.sh"
. "$L_DIR/backends/pty_tmux.sh"

refuse() { echo "refuse: $*" >&2; exit 2; }

need_ws() {
  [ -n "${1:-}" ] || refuse "missing <workspace> (the topic's delivery directory)"
  WS=$(cd "$1" 2>/dev/null && pwd) || refuse "workspace $1 is not a directory"
  TOPIC=$(basename "$(cd "$WS/.." && pwd)")
}

# --- onboarding probe (backend-seam.md §2, implemented in probe.sh): first
# use of a backend — and any CLI version change — runs a real scratch session
# proving heartbeat/stop-gate/emit/awaiting/inject/dead-detect. Probe failure
# = the declaration is wrong; the topic refuses to start on it. One probe per
# unique backend across the roles; an unchanged version is a cached pass.
# The CONFIG-REACHABLE set, not just the two topic-level roles: the spawn
# resolves per (role, slice) — run_attempt carries --slice on all three agent
# reads — so a backend named only in a slice override would be spawned on
# having never been proven. This is the door, and it probes everything the
# config can SEE; ferry.sh's spawn-side fact guard covers whatever is written
# after it. Pure (config reads only, no session spent), so a fault travels as a
# STATUS the caller answers — the same rule the ferry's own reader obeys.
# rc: 0 answered · 3 config fault.
probe_reachable_set() { # -> "<backend>|<model>|<where>" per line
  local role b model f nn ag seen=""
  for role in author reviewer; do
    b=$(config_get "agent.$role.backend" --topic-dir "$WS") || return 3
    model=$(config_get "agent.$role.model" --topic-dir "$WS") || return 3
    case " $seen " in *" $b "*) continue ;; esac
    seen="$seen $b"
    printf '%s|%s|%s\n' "$b" "$model" "agent.$role.backend (topic level)"
  done
  for f in "$WS"/config/slice.[0-9][0-9].*.kv; do
    [ -f "$f" ] || continue
    # slice.<nn>.<agent>.kv — the ferry reads agent.<role>.* from the file whose
    # <agent> IS that role, so that is the only key in it a spawn can ever read.
    nn=${f##*/slice.}; ag=${nn#*.}; ag=${ag%.kv}; nn=${nn%%.*}
    case "$ag" in author|reviewer) : ;; *) continue ;; esac
    b=$(config_get "agent.$ag.backend" --topic-dir "$WS" --slice "$nn" --agent "$ag") || return 3
    model=$(config_get "agent.$ag.model" --topic-dir "$WS" --slice "$nn" --agent "$ag") || return 3
    [ -n "$b" ] || continue
    case " $seen " in *" $b "*) continue ;; esac
    seen="$seen $b"
    printf '%s|%s|%s\n' "$b" "$model" "agent.$ag.backend in $(basename "$f")"
  done
}

probe_backends() {
  local reach rc b model why decl prc
  reach=$(probe_reachable_set); rc=$?
  [ "$rc" -eq 3 ] && exit 3
  # Every declaration must resolve BEFORE any session is spent — the rule the
  # repo-lock advisory check already follows: a launch doomed to a refusal
  # fails here, not after a probe session has been paid for.
  while IFS='|' read -r b model why; do
    [ -n "$b" ] || continue
    decl="$WROOT/config/backends/$b.kv"
    [ -f "$decl" ] || refuse "backend declaration $decl absent ($why = $b)"
  done <<< "$reach"
  while IFS='|' read -r b model why; do
    [ -n "$b" ] || continue
    decl="$WROOT/config/backends/$b.kv"
    # Two ways to not start, and they must not share a sentence: a broken
    # promise sends you to the declaration, an absent backend sends you to the
    # clock. Naming the first for both is how a zero-quota window read as
    # "the declaration is wrong".
    "$L_DIR/probe.sh" "$WS" "$decl" "$b" "$model" low; prc=$?
    case $prc in
      0) : ;;
      4) refuse "backend '$b' is UNAVAILABLE (out of quota) — not a declaration defect; the probe printed the pane's own line with the reset time, and $WS/.runtime/probe/$b.kv holds it. relaunch after that reset" ;;
      *) refuse "onboarding probe FAILED for backend '$b' ($why) — declarations are promises, the probe makes them facts (backend-seam.md §2); see $WS/.runtime/probe/$b.kv and the probe log before relaunching" ;;
    esac
  done <<< "$reach"
}

preflight() {
  [ "${BASH_VERSINFO[0]:-0}" -ge 4 ] || refuse "bash >= 4 required, running $BASH_VERSION (macOS: brew install bash, ahead of /bin in PATH)"
  command -v tmux > /dev/null || refuse "tmux not installed (dependency: git, tmux, awk/sed/grep; Linux also coreutils + flock)"
  command -v git > /dev/null || refuse "git not installed"
  command -v flock > /dev/null || refuse "flock not installed (util-linux; the store serializes writers with it)"
  echo "preflight: $(tmux -V) · $(git --version)"
  case "$TOPIC" in *[!A-Za-z0-9_-]*)
    refuse "topic directory '$TOPIC' outside charset [A-Za-z0-9_-] (tmux session names embed it)" ;;
  esac
  # The FULL paths ride unquoted through profile hook command lines and
  # cmd.launch interpolation ({workspace}, {profile}) — whitespace anywhere
  # in them would split arguments deep inside the harness, far from here.
  case "$WS$L_DIR" in *[[:space:]]*)
    refuse "workspace or workflow path contains whitespace ('$WS') — hook/cmd.launch interpolation is not whitespace-safe; relocate the tree" ;;
  esac
  # A schema-legal .kv sitting at the workspace ROOT that is not project.kv is
  # read by NOTHING, and the launch that ignores it starts anyway. Measured: a
  # workspace prepared with topic.kv at <ws>/topic.kv resolved every value from
  # defaults.kv, because lib/config.sh reads the topic layer from
  # <ws>/config/topic.kv. Nothing refused and nothing looked wrong, because the
  # defaults happened to agree for the two agent families it could be checked
  # against — and it silently lost the reviewer's backend and model, all_cold,
  # and three slice caps. The asymmetry this closes: config.sh is built so a
  # misplaced KEY faults loudly by schema, while a misplaced FILE resolves to
  # nothing and starts.
  # WARN, not refuse, and the reason is what was actually missing. The existing
  # defense — the review-independence audit line — did fire, correctly, and
  # named the CONSEQUENCE for one key family while never naming the CAUSE, so
  # the operator was told to "set agent.reviewer.backend", which that workspace
  # HAD set, in a file one directory away. Naming the cause is the whole fix; a
  # refusal would also block a layout nobody has needed yet.
  for _kv in "$WS"/*.kv; do
    [ -e "$_kv" ] || continue
    case "${_kv##*/}" in
      project.kv) : ;;
      *) echo "preflight: WARNING — '${_kv##*/}' sits at the workspace ROOT, where nothing reads it. The topic layer is read from <ws>/config/topic.kv and the project adapter from <ws>/project.kv; a .kv here resolves to nothing and the launch still starts on defaults.kv. Move it or delete it." >&2 ;;
    esac
  done
  # The same asymmetry one level in: a misplaced kv FILE is named above; a
  # misplaced kv KEY is named here. `project.kv` is the project's own contract
  # and is deliberately NOT schema-validated (lib/config.sh), so an unknown key
  # there is legitimately the project's business. What is NOT its business is a
  # key the CONFIG schema defines: that one looks like it will resolve, and does
  # not — config_get's layers are defaults -> operator -> <ws>/config/topic.kv
  # -> slice.<nn>.<agent>.kv, and project.kv is in none of them.
  # Measured: a topic declared agent.implementer.effort=max here, the snapshot
  # carried the default `high`, the rendered impl prompt instructed `high`, and
  # the conformance disclosed `high` honestly — an owner directive silently
  # unenforced across two slices, with author and reviewer matching only because
  # the defaults happened to agree.
  # The predicate is DERIVED, never a shape list: schema.kv INTERSECT project.kv,
  # minus the cap namespace. Caps are the one family the adapter is genuinely
  # read for (`_gates_cap` asks project_get FIRST for whatever cap key it is
  # handed — design §2: the project may override caps in either direction), so
  # they are legitimate there and everything else in the intersection is inert.
  # Measured on every real adapter this workflow has run: 8 true positives (one
  # whole agent block), 0 false positives. A new config family is covered the
  # day it is added, with no list to maintain — an allow-list inversion,
  # available here because both sets already exist.
  # WARN, never refuse, for the reason the stray-FILE arm above gives.
  local _schema="$WROOT/config/schema.kv" _inert
  if [ -f "$_schema" ] && [ -f "$WS/project.kv" ]; then
    _inert=$(comm -12 \
      <(command grep -oE '^[a-z][a-z0-9._]*' "$WS/project.kv" | sort -u) \
      <(command grep -oE '^[a-z][a-z0-9._]*' "$_schema" | sort -u) \
      | command grep -vE '^cap\.' | tr '\n' ' ')
    [ -z "${_inert// /}" ] || echo "preflight: WARNING — project.kv declares config key(s) nothing reads there: ${_inert%% }. The project adapter is read for repo/branch/gate commands/commit conventions, the topic's route= verdict, and caps ONLY; every other layer resolves through <ws>/config/topic.kv (then slice.<nn>.<agent>.kv), so these values are silently ignored and the run uses defaults.kv. Move them to <ws>/config/topic.kv or delete them." >&2
  fi
  # A dirty workflow tree must not launch: this preflight is the ADOPTION door
  # (a fresh topic pins the tree here; a relaunch repins through the resume
  # gate), and a half-saved edit adopted as "the tree" is executed by live
  # sessions through absolute hook paths — the run_attempt pin only catches
  # drift AFTER a stage is live. The cargo-publish shape: refuse uncommitted
  # state at the door, don't ship it. Scoped `-- .` like workflow_sha (git -C
  # walks to the repo toplevel; sibling-dir changes are not this tree's dirt);
  # a non-git tree stays the named no-git degradation (its pin is off too).
  local wf_dirty
  if git -C "$WROOT" rev-parse --git-dir > /dev/null 2>&1; then
    wf_dirty=$(git -C "$WROOT" status --porcelain -- . 2>/dev/null | head -3 | tr '\n\t' '; ')
    [ -z "$wf_dirty" ] \
      || refuse "workflow tree has uncommitted changes under $WROOT ($wf_dirty..) — commit or stash before launching; launch adopts and pins this tree, and live sessions execute it by absolute hook paths"
  fi
  local avail
  avail=$(df -Pk "$WS" | awk 'NR==2{print $4}')
  [ "$avail" -ge 102400 ] \
    || refuse "disk headroom: only ${avail}KB free under $WS (floor: 102400KB) — the store must never die of a full disk mid-run"
  [ -f "$WS/project.kv" ] \
    || refuse "$WS/project.kv missing — the project adapter is REQUIRED; declare at least repo, branch and commit.subject_regex (every other key is optional; undeclared gates record a named SKIP) per design/config-and-adapters.md §3 (never baked-in assumptions)"
  project_validate "$WS" || exit 2
  # Advisory repo-lock check (same predicate as the ferry's authoritative
  # take), over EVERY declared repo in the same fixed order: a launch doomed to
  # the ferry's refusal must fail HERE, before a probe session is spent and a
  # watchdog detached.
  local claim repo
  while IFS= read -r repo; do
    [ -n "$repo" ] || continue
    if claim=$(state_repo_claimed "$repo" "$WS"); then
      refuse "repo $repo is claimed by another live topic ($claim) — parallel topics require separate checkouts/worktrees (refusing at preflight, before a probe session is spent; the ferry's take is the authority)"
    fi
  done < <(project_repos "$WS")
  config_validate_file "$WS/config/topic.kv" || exit 3

  # Validate at the door; do NOT bake. The profile the sessions actually run is
  # rendered per spawn by ferry.sh, from the declaration THAT spawn's own
  # (role, slice) resolution names — a topic-level bake here was a second
  # derivation of a per-(role, slice) fact, and it was the one that won.
  local backend decl profile_rel profile_src
  backend=$(config_get agent.author.backend --topic-dir "$WS") || exit 3
  decl="$WROOT/config/backends/$backend.kv"
  [ -f "$decl" ] || refuse "backend declaration $decl absent (agent.author.backend=$backend)"
  profile_rel=$(pty_decl_get "$decl" profile) || refuse "$decl declares no profile="
  profile_src="$WROOT/config/$profile_rel"
  [ -f "$profile_src" ] || refuse "profile template $profile_src absent"
  mkdir -p "$WS/.runtime"
  echo "preflight: $decl resolves its profile template -> $profile_src (rendered per spawn, per session)"
  # The paging lifeline is verified BEFORE the probe spends a real session:
  # a probe refusal must never be the reason the transport went untested.
  notify_fire "$WS" notify.test none "delivery-workflow test notification (topic $TOPIC, launch preflight)"
  echo "preflight: test notification fired (transport is best-effort; check it arrived)"
  probe_backends
}

init_runtime() {
  mkdir -p "$WS/.runtime/state" "$WS/.runtime/tmp" "$WS/.runtime/logs" "$WS/.runtime/prompts"
  rm -f "$WS/.runtime/stop-request"
  if ! state_get "$WS" notify > /dev/null 2>&1; then
    state_put "$WS" notify operator "preset=$(config_get notify.preset --topic-dir "$WS")" > /dev/null \
      || refuse "could not initialize notify surface"
  fi
}

# A live watchdog over a PARKED final-state is the pager, not a driver: the
# watchdog clears final-state when it starts driving and writes it at exit
# (watchdog.sh), so the pair "class=parked + live pid" has one meaning. Both
# `launch` (takeover) and `stop` (end the paging) use this one decider.
# rc 0: a pager was ended · 1: no live watchdog · 2: a live DRIVER, untouched ·
# 3: the pager ignored SIGTERM (its pid stays in the pidfile for inspection).
pager_stop() {
  local wd i
  wd=$(cat "$WS/.runtime/watchdog.pid" 2>/dev/null || true)
  { [ -n "$wd" ] && kill -0 "$wd" 2>/dev/null; } || return 1
  command grep -q '^class=parked ' "$WS/.runtime/final-state" 2>/dev/null || return 2
  kill "$wd" 2>/dev/null
  for i in 1 2 3 4 5 6 7 8 9 10; do kill -0 "$wd" 2>/dev/null || break; sleep 0.2; done
  kill -0 "$wd" 2>/dev/null && return 3
  rm -f "$WS/.runtime/watchdog.pid"
  return 0
}

verb_launch() {
  local attach=0
  need_ws "${1:-}"
  [ "${2:-}" = "--attach" ] && attach=1
  preflight
  init_runtime
  local wd
  # A live watchdog that is PAGING yields to a relaunch — that is what it waits
  # for; a live DRIVER is the one-driver-per-workspace refusal.
  pager_stop; case $? in
    0) echo "launch: the paging watchdog was ended — this launch takes the park over" ;;
    2) refuse "watchdog already running (pid $(cat "$WS/.runtime/watchdog.pid" 2>/dev/null)) — one driver per workspace; use 'launch.sh status' or 'launch.sh stop'" ;;
    3) refuse "the paging watchdog (pid $(cat "$WS/.runtime/watchdog.pid" 2>/dev/null)) did not exit on SIGTERM — inspect it before relaunching" ;;
  esac
  nohup "$L_DIR/watchdog.sh" "$WS" >> "$WS/.runtime/logs/watchdog.log" 2>&1 &
  disown
  # launch's job ends when the watchdog is up (architecture §9: preflight +
  # init + watchdog + ferry): it returns, so scripts can compose it. The
  # monitor is a separate read-only observer — attach on request only.
  echo "watchdog started (pid $!) — watch with: $L_DIR/monitor.sh $WS"
  if [ $attach -eq 1 ]; then
    sleep 1
    exec "$L_DIR/monitor.sh" "$WS"
  fi
}

verb_rule() {
  need_ws "${1:-}"; shift
  local slice="" stage="" text="" file="" scope=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --slice) slice=$2; shift 2 ;;
      --stage) stage=$2; shift 2 ;;
      --text) text=$2; shift 2 ;;
      --file) file=$2; shift 2 ;;
      --topic) scope=topic; shift ;;
      *) refuse "rule: unknown arg '$1'" ;;
    esac
  done
  # --topic: the ruling fixes a MECHANISM, not one slice's question — it rides
  # every slice's manifest (lib/rulings.sh), while --slice still names the halt
  # it answers (the resume gate binds by slice). Alone, it files under 00.
  [ -n "$slice" ] || [ -z "$scope" ] || slice=00
  [ -n "$slice" ] || refuse "rule needs --slice N (2-digit id; 00 = topic-level) and/or --topic (rides every slice)"
  printf '%s\n' "$slice" | command grep -qE '^[0-9]{2}$' || refuse "slice id must be 2 digits (got '$slice')"
  if [ -n "$file" ]; then
    [ -f "$file" ] || refuse "ruling file $file absent"
    text=$(cat "$file")
  fi
  [ -n "$text" ] || refuse "rule needs --text '...' or --file F"
  local n dir hid=""
  # Bind the ruling to the pending halt's identity: the resume gate matches by
  # halt_id (same-second rulings resolve; a ruling for a previous halt never
  # answers a new one). No unresolved halt -> no id: the ruling still rides
  # the next stage's manifest (RULING=rulings.pending).
  if [ "$(state_field "$WS" halt resolved 2>/dev/null)" = "0" ]; then
    hid=$(state_field "$WS" halt halt_id 2>/dev/null || true)
  fi
  dir="$WS/slices/$slice"
  mkdir -p "$dir"
  # max+1, never count+1: with a gap (ruling.1 + ruling.3), a count would
  # OVERWRITE ruling.3 — the DP audit archive must be append-only.
  n=$(( $(ls "$dir"/ruling.*.md 2>/dev/null \
          | sed 's/.*ruling\.\([0-9]*\)\.md/\1/' | sort -n | tail -1 || true) + 1 ))
  printf '%s\n' "$text" > "$dir/ruling.$n.md"
  state_append "$WS" rulings operator \
    "v=1 t=$(date +%s) slice=$slice stage=${stage:-any}${hid:+ halt_id=$hid}${scope:+ scope=$scope} n=$n file=slices/$slice/ruling.$n.md text=$(printf '%s' "$text" | tr '\n\t' '  ')" \
    || refuse "rulings surface append failed"
  echo "ruling $n recorded for slice $slice${scope:+ (topic scope: rides the manifest of every slice)} (archived: $dir/ruling.$n.md) — relaunch resumes the suspended stage with it; a session already running is refused at emit until it acknowledges it"
}

verb_stop() {
  need_ws "${1:-}"
  mkdir -p "$WS/.runtime"
  # A watchdog that is PAGING drives nothing: stop ends the paging now rather
  # than deferring a request it would read only at its next interval — and
  # which the next launch would clear, unread, anyway.
  pager_stop; case $? in
    0) echo "re-paging stopped (the paging watchdog was ended). Nothing was running; the park itself is unchanged: launch.sh status $WS --halt"
       return 0 ;;
    3) refuse "the paging watchdog (pid $(cat "$WS/.runtime/watchdog.pid" 2>/dev/null)) did not exit on SIGTERM — inspect it" ;;
  esac
  # Who could actually honour a stop request? Not "is there a watchdog" — a
  # watchdog can die while the ferry it started lives on, and THAT ferry reads
  # the request at its next poll (lib/watch.sh) or between attempts
  # (ferry.sh's main loop). The host lock is the truth about a live ferry, and
  # lib/state.sh holds the one derivation of it.
  local wd hp honourer=""
  wd=$(cat "$WS/.runtime/watchdog.pid" 2>/dev/null || true)
  if [ -n "$wd" ] && kill -0 "$wd" 2>/dev/null; then
    honourer="the watchdog (pid $wd)"
  elif hp=$(state_host_holder "$WS" 2>/dev/null); then
    honourer="the ferry ($hp)"
  fi
  if [ -n "$honourer" ]; then
    printf 't=%s by=operator\n' "$(date +%s)" > "$WS/.runtime/stop-request"
    echo "stop requested — $honourer parks gracefully at its next poll (sessions kept for postmortem)"
    # WHAT IS STILL RUNNING, because `stop` addresses the FERRY and the stage is
    # a separate tmux session with its own lifetime. Measured: the
    # ferry parked at 10:55:35, the stopped stage emitted its completion record
    # 3m47s LATER with no ferry running, and the relaunch harvested it and
    # advanced in the same second. It was harmless only because the stage that
    # kept running was turnover — one stage earlier and a whole spec would have
    # landed on the configuration the operator stopped in order to change, with
    # the intervention silently void, a green run and no park to show for it.
    # The ferry already knows all of this; nothing printed it.
    local st_state st_slice st_stage st_sess
    st_state=$(state_field "$WS" stage state 2>/dev/null || true)
    if [ "$st_state" = "running" ]; then
      st_slice=$(state_field "$WS" stage slice 2>/dev/null || true)
      st_stage=$(state_field "$WS" stage stage 2>/dev/null || true)
      # Looked up only when BOTH parts are known: `${x:-??}` inside an ERE
      # makes `-??-??`, where `?` is a quantifier, not a wildcard — it would
      # match almost any session name and print a fabricated one.
      st_sess=""
      if [ -n "$st_slice" ] && [ -n "$st_stage" ]; then
        st_sess=$(state_get "$WS" sessions 2>/dev/null \
                  | command grep -oE "name=delivery-[^ ]*-$st_slice-$st_stage( |\$)" \
                  | tail -1 | sed 's/^name=//; s/ *$//')
      fi
      echo "  STILL RUNNING, and the stop does not reach it: slice ${st_slice:-?} stage ${st_stage:-?}${st_sess:+ (session $st_sess)}."
      echo "  That session keeps working and can still emit its record; the next launch will HARVEST it and advance."
      echo "  So if you are stopping in order to CHANGE something that stage depends on — backend, model, effort,"
      echo "  workflow source, the plan — either wait for it to park, or expect its output to land on the old"
      echo "  configuration. \`launch.sh status\` shows when it is gone."
    fi
    return 0
  fi
  # Nothing is running, so there is nothing to defer the request TO — and a
  # stop-request does not survive a launch either: init_runtime removes it
  # before the ferry that would read it exists. The old message here said the
  # request "will be honored (and cleared) at next launch"; it is cleared, and
  # it is never honored. Both halves of one sentence, false, and read by an
  # operator deciding whether the topic is safe to leave.
  # So: write nothing, and say the true thing.
  echo "nothing to stop: no watchdog and no live ferry hold this workspace — the topic is already not running."
  echo "  no stop-request was written: it would not survive the next launch (init_runtime clears it before the ferry starts),"
  echo "  so it could neither park anything now nor later. To keep the topic stopped, simply do not relaunch."
  [ -e "$WS/.runtime/stop-request" ] && \
    echo "  note: an earlier stop-request is still on disk; it will be cleared, unread, by the next launch."
  echo "  where it stands: launch.sh status $WS"
  return 0
}

verb_slice() {
  need_ws "${1:-}"; shift
  local id=${1:-} status=${2:-} body cur
  [ -n "$id" ] && [ -n "$status" ] || refuse "usage: slice <ws> <id> <cancelled|restored>"
  [ "$status" = "restored" ] && status=pending   # docs' word; pending is the index spelling
  case "$status" in cancelled|pending) : ;;
    *) refuse "operator may set only cancelled|restored (done/superseded/active are the ferry's)" ;;
  esac
  body=$(state_get "$WS" slices) || refuse "no slices index yet (split has not run) or store fault"
  cur=$(printf '%s\n' "$body" | command grep -E "(^| )id=$id( |$)" | tail -1)
  [ -n "$cur" ] || refuse "slice id '$id' not in the index"
  case "$cur" in *"status=superseded"*) refuse "slice $id is superseded (retired ids are never revived; merges minted a new id)" ;; esac
  local extra=""
  if [ "$status" = "pending" ]; then
    case "$cur" in *"status=cancelled"*) : ;; *) refuse "only a cancelled slice can be restored to pending (current: $cur)" ;; esac
    extra="rederive-set"
  else
    case "$cur" in *"status=done"*) refuse "slice $id is done — nothing to cancel" ;; esac
  fi
  printf '%s\n' "$body" | awk -v id="$id" -v st="$status" -v ex="$extra" '
    $0 ~ ("(^| )id=" id "( |$)") {
      gsub(/status=[A-Za-z0-9_-]+/, "status=" st)
      if (ex != "") gsub(/rederive=[0-9]+/, "rederive=1")
    } { print }' | state_set "$WS" slices operator || refuse "slices index write failed"
  state_audit "$WS" operator "slice $id -> $status${extra:+ (premise re-derivation flagged)}"
  echo "slice $id -> $status${extra:+ (restored: premise will be re-derived from scratch)}"
  # Cancelling the slice the ferry is HOLDING is legal and takes effect, but not
  # instantly: the ferry acts on it at its next turn between attempts. Saying so
  # here is the whole of the operator's side of that contract — the erasure this
  # replaced was silent in both directions.
  if [ "$status" = "cancelled" ] \
     && [ "$(state_field "$WS" stage slice 2>/dev/null || true)" = "$id" ]; then
    echo "  note: $id is the slice the ferry currently holds. It tears $id's sessions down and reroutes to the next schedulable slice at its next turn BETWEEN attempts — a live attempt is not killed (that is 'launch.sh stop'), and nothing will mark $id done."
  fi
}


verb_status() {
  need_ws "${1:-}"; shift
  local slices=0 halt=0 rounds=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --slices) slices=1; shift ;;
      --halt) halt=1; shift ;;
      --rounds) rounds=1; shift ;;
      *) refuse "status: unknown arg '$1' (usage: status <workspace> [--slices|--rounds|--halt])" ;;
    esac
  done
  # The three flags are three different renderers — taking one silently is a
  # behaviour an operator has to interpret; the refusal says what clashed
  # (same policy as peek's --follow/--attach).
  local nsel=$(( slices + halt + rounds ))
  [ "$nsel" -gt 1 ] && refuse "status: --slices, --rounds and --halt are alternatives — pick one"
  [ "$halt" -eq 1 ] && { status_halt; return 0; }
  [ "$rounds" -eq 1 ] && { status_rounds; return 0; }
  [ "$slices" -eq 0 ] && exec "$L_DIR/monitor.sh" "$WS" --once
  status_slices
}

# peek: the "look" half of the look/type split. capture-pane creates no client
# and cannot change geometry (measured), so
# looking is structurally free of the harm attach carries (an attach client —
# read-only included — rewrites pane geometry). The reader's discipline is the
# same as every other reader here: a corrupt sessions surface refuses as
# CORRUPT, never as "nothing to look at"; present-empty is not absent (close-out
# clears the surface); a row whose session is gone points at the pane log the
# spawn armed, rather than printing nothing. The capture target is the adapter's
# own window form (=name:), not the bare session name — capture-pane refuses the
# bare form while has-session accepts it, which is a worse failure than a clean
# one because it looks like the session is missing.
# One field off one sessions-surface row — the extraction every peek consumer
# shares (written ONCE: it had four copies, and the tree's own measured bug
# class is duplicated predicates drifting apart). First whitespace-delimited
# <key>= token wins, like the kv() of the rounds reader.
_peek_kv() { # line key -> value on stdout ("" absent)
  awk -v k="$2" '{for(i=1;i<=NF;i++) if($i ~ "^"k"="){sub("^"k"=","",$i); print $i; exit}}' <<< "$1"
}

# The roles the surface holds right now — for the message a filtered peek owes
# when nothing matches: "no author session" alone cannot be told apart from a
# cleared surface, and naming what IS there lets the operator see their filter
# was the wrong one (a stage switch removes the author row mid-topic).
_peek_roles_held() {
  printf '%s\n' "$PEEK_BODY" | command grep '^role=' \
    | while IFS= read -r _prl; do _peek_kv "$_prl" role; done \
    | sort -u | paste -sd' ' -
}

# The gone-session statement both modes share: a dead socket owes a pointer at
# the pane log, never an attach command for it (running one against a dead
# socket fails confusingly — "looks like the session is missing" is the failure
# shape this file already guards the capture target against).
_peek_gone_line() { # name -> one parenthesised statement on stdout
  local logn=${1#"delivery-$TOPIC-"}
  if [ -f "$WS/.runtime/logs/$logn.log" ]; then
    printf '(session is gone — the pane log it left: %s)' "$WS/.runtime/logs/$logn.log"
  else
    printf '(session is gone — no pane log either: pipe-pane is best-effort at spawn)'
  fi
}

# One render pass over whatever the sessions surface holds RIGHT NOW — the
# decision tree both the follow loop and the one-shot call walk, written ONCE.
# Two copies of this tree drifted once already (the guard outside decided on a
# different predicate than the printer inside, and a surface whose rows lacked
# name= passed every guard printing nothing); a second copy would be a third
# chance at the same bug. watch=1 appends the watching note — follow re-derives
# this pass every tick, a one-shot has nothing to watch.
_peek_tick() { # [watch] -> text on stdout; never silent
  # The two presence tests use HERE-STRINGS, not `printf | grep -q`: under
  # set -o pipefail, grep -q exits at its first match and a printf still
  # writing a surface past the ~64KB pipe buffer dies of SIGPIPE (141),
  # which reads as "the test failed" — the EMPTY gate of status --rounds
  # read a 2001-row ledger as EMPTY through exactly this pipe (round 19).
  if [ "$PEEK_RC" -eq 3 ]; then
    echo "the sessions surface is CORRUPT — not absent; inspect $WS/.runtime/state/sessions"
  elif [ "$PEEK_RC" -ne 0 ]; then
    echo "no sessions surface — the topic has never started${1:+ (watching for it)}"
  elif ! command grep -q '^role=' <<< "$PEEK_BODY"; then
    echo "the sessions surface is EMPTY — sessions were cleared at close-out; pane logs remain at $WS/.runtime/logs/"
  elif [ -n "$PEEK_ROLE" ] && ! command grep -qE "^role=$PEEK_ROLE( |$)" <<< "$PEEK_BODY"; then
    echo "no $PEEK_ROLE session right now — the surface holds: $(_peek_roles_held)"
  else
    _peek_once
  fi
}

_peek_once() {
  local line role name sock shown=0 skipped=0
  while IFS= read -r line; do
    # The roster is fed via a heredoc, and an empty roster still hands the
    # loop ONE blank line — which would count as a nameless row below and
    # report "1 row(s) ... have no name=" over a surface holding zero (found
    # by mutation: deadening the tick's EMPTY branch let the empty surface
    # fall through to here, and the counter lied about what the surface held).
    [ -n "$line" ] || continue
    role=$(_peek_kv "$line" role)
    name=$(_peek_kv "$line" name)
    sock=$(_peek_kv "$line" socket)
    # A row without name= is skipped, but SKIPPING IS COUNTED, and only within
    # the filter the operator asked for (counting before the filter reports
    # nameless rows of roles the operator did not ask about — noise that
    # points attention away). A hand-repaired or truncated surface is a
    # measured event in this tree (status_halt keeps its unknown lines for
    # exactly that reason); the count is said below.
    if [ -n "$PEEK_ROLE" ] && [ "$role" != "$PEEK_ROLE" ]; then continue; fi
    [ -n "$name" ] || { skipped=$((skipped + 1)); continue; }
    shown=$((shown + 1))
    # A pending socket (no leading /) owes a statement, not a command — the
    # monitor's own rule for its attach block: printing an unrunnable line an
    # operator will copy is worse than printing nothing, and --attach is exactly
    # the mode whose output gets copied. A GONE session owes the same in either
    # mode: the capture path already checks has-session and points at the pane
    # log; --attach used to print the dead socket's command unguarded — found
    # by the peek property fuzzer (a /nonexistent socket rendered a copyable
    # command that cannot but fail).
    if [ "$PEEK_ATTACH" -eq 1 ]; then
      case "$sock" in
        /*) if tmux -S "$sock" has-session -t "=$name" 2>/dev/null; then
              echo "tmux -S $sock attach -r -t '=$name'   ($role)"
            else
              echo "$(_peek_gone_line "$name")   ($role)"
            fi ;;
        *)  echo "(session still starting — no attach command yet)   ($role)" ;;
      esac
      continue
    fi
    echo "──── $role · $name ────"
    case "$sock" in
      /*) ;;
      *) echo "  (session still starting — no socket yet)"; continue ;;
    esac
    if ! tmux -S "$sock" has-session -t "=$name" 2>/dev/null; then
      echo "  $(_peek_gone_line "$name")"
      continue
    fi
    tmux -S "$sock" capture-pane -p -t "=$name:"
    echo
  done <<< "$(printf '%s\n' "$PEEK_BODY" | command grep '^role=')"
  # Silence is the one answer this verb must never give, and the guard outside
  # decides on a DIFFERENT predicate than the printer inside (role presence vs
  # a printable name=) — measured: a surface whose rows lack name= passed every
  # guard and printed nothing, rc=0. The counters below are the belt under
  # whatever predicates future edits drift apart.
  [ "$skipped" -gt 0 ] && echo "  ($skipped row(s) on the sessions surface have no name= — not shown; inspect $WS/.runtime/state/sessions)"
  if [ "$shown" -eq 0 ]; then
    echo "  (nothing was shown — the surface holds $(printf '%s\n' "$PEEK_BODY" | command grep -c '^role=') row(s); none matched the filter or none were printable)"
  fi
}

verb_peek() {
  need_ws "${1:-}"; shift
  PEEK_ROLE=""; PEEK_ATTACH=0; PEEK_FOLLOW=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --follow) PEEK_FOLLOW=1; shift ;;
      --attach) PEEK_ATTACH=1; shift ;;
      author|reviewer|implementer)
        [ -n "$PEEK_ROLE" ] && refuse "peek: one role only (already have '$PEEK_ROLE', got '$1')"
        PEEK_ROLE=$1; shift ;;
      *) refuse "peek: unknown arg '$1' (usage: peek <workspace> [role] [--follow|--attach])" ;;
    esac
  done
  # --follow refreshes pane CONTENT; --attach prints static commands — the
  # combination has nothing to refresh, so it is refused rather than allowed to
  # repaint the same line every 2s (an explicit refusal beats an odd behavior
  # an operator has to interpret).
  [ "$PEEK_FOLLOW" -eq 1 ] && [ "$PEEK_ATTACH" -eq 1 ] && refuse "peek: --follow refreshes pane content, --attach prints static attach lines — pick one"
  PEEK_BODY=$(state_get "$WS" sessions 2>/dev/null); PEEK_RC=$?
  # fault != absent, in this reader too: peek is run at the exact moment an
  # operator wants to look, so answering "nothing there" over an unreadable
  # surface is the worst available lie (the panel says the same its own way).
  # It decides BEFORE the implementer explanation below — a fault must refuse
  # for every role, including the one whose answer is a sentence.
  [ "$PEEK_RC" -eq 3 ] && refuse "the sessions surface is CORRUPT (checksum/parse) — not absent; inspect $WS/.runtime/state/sessions before reading anything off it"
  # The implementer is a sub-agent the author dispatches INSIDE its own pane —
  # no signal in the store says whether one is running, and today no
  # sessions-surface row carries role=implementer (the surface is keyed by
  # owed-stage role, author|reviewer only). Answering the question the operator
  # actually asked beats an empty screen that is indistinguishable from "not
  # running". The explanation fires only when the surface REALLY holds no
  # implementer row — checked, not assumed: the day the surface's keying grows
  # an implementer row, this filter must show it, not explain it away (a
  # pre-read branch here would have hidden real rows behind the explanation —
  # silent-hide is the one thing this tree never tolerates, including from its
  # own convenience answers). An absent surface decides the same way: it holds
  # no rows of any role, so the explanation is true over it too.
  if [ "$PEEK_ROLE" = "implementer" ] \
     && ! command grep -q '^role=implementer' <<< "$PEEK_BODY"; then
    echo "peek: the implementer is a sub-agent the author dispatches inside its own pane — there is no implementer session; peek <ws> author shows the pane it runs in"
    return 0
  fi
  if [ "${PEEK_FOLLOW:-0}" -eq 1 ]; then
    # The roster is re-read EVERY tick, not frozen at loop start: a stage
    # transition mid-watch swaps sessions, and a follow that keeps showing the
    # departed session (or never shows the new one) is watching a memory of the
    # topic. Absent/empty/corrupt are likewise re-derived each tick and SAID —
    # a watch that goes quiet over a closed-out or corrupting surface renders a
    # confident empty screen, which is the one thing a watcher must never see.
    # (Starting a watch on an absent/empty surface is allowed for the same
    # reason: the operator may be watching for a topic to come up.)
    while :; do
      PEEK_BODY=$(state_get "$WS" sessions 2>/dev/null); PEEK_RC=$?
      clear
      echo "peek $TOPIC $(date '+%H:%M:%S') — Ctrl-C to stop"
      _peek_tick watch
      sleep 2
    done
  fi
  _peek_tick
}

verb_ack() {
  need_ws "${1:-}"
  local body rc hid reason
  body=$(state_get "$WS" halt 2>/dev/null); rc=$?
  [ $rc -eq 3 ] && refuse "the halt surface is CORRUPT (checksum/parse) — nothing can be acknowledged over it; inspect $WS/.runtime/state/halt"
  [ $rc -eq 0 ] || refuse "no halt on record for topic $TOPIC — nothing to acknowledge"
  body=$(printf '%s\n' "$body" | awk '/^--- screen ---$/{exit} {print}')
  [ "$(printf '%s\n' "$body" | awk -F= '$1=="resolved"{v=$2} END{print v}')" = "1" ] \
    && refuse "the current halt is already resolved — nothing to acknowledge"
  hid=$(printf '%s\n' "$body" | awk -F= '$1=="halt_id"{v=$2} END{print v}')
  reason=$(printf '%s\n' "$body" | awk -F= '$1=="reason"{v=$2} END{print v}')
  # The ack is an audit row keyed by halt_id, so the pager and `status --halt`
  # read it from the surface the watchdog already writes to, and the halt
  # surface keeps its single writer.
  state_audit "$WS" operator "ack halt_id=$hid reason=$reason — paging pauses for one interval and resumes while the park stands"
  echo "acknowledged: $reason (halt $hid) — re-paging PAUSES for one notify.ack_timeout window and then resumes while the park stands; ack again to buy another. The park itself is unchanged: resume with launch.sh rule (a ruling-gated halt) or a relaunch."
}

verb_notify() {
  need_ws "${1:-}"; shift
  local arg=${1:-}
  [ -n "$arg" ] || refuse "usage: notify <ws> <preset|event=on|off>"
  if printf '%s\n' "$arg" | command grep -qE '^[a-z._-]+=(on|off)$'; then
    local ev=${arg%%=*}
    printf '%s\n' "$ev" | command grep -qE '^(park\.[a-z_]+|broken|topic\.done|slice\.done|spec\.ready|commit\.done)$' \
      || refuse "event '$ev' not in the closed vocabulary (park.<reason>|broken|topic.done|slice.done|spec.ready|commit.done)"
    state_put "$WS" notify operator "event.$arg" || refuse "notify surface write failed"
    echo "notify override: event.$arg (hot — the ferry reads it at next emit)"
  else
    command grep -qE "^preset\.$arg=" "$WROOT/config/notify-presets.kv" \
      || refuse "preset '$arg' not in config/notify-presets.kv"
    state_put "$WS" notify operator "preset=$arg" || refuse "notify surface write failed"
    echo "notify preset -> $arg (hot, no relaunch needed)"
  fi
}

verb_observe() {
  need_ws "${1:-}"; shift
  local text="" file=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --text) text=$2; shift 2 ;;
      --file) file=$2; shift 2 ;;
      *) refuse "observe: unknown arg '$1'" ;;
    esac
  done
  # --file exists for the same reason rule's does: useful observations carry
  # code — regexes, shell fragments, backticks — and a shell-quoted --text is
  # where a live entry lost a backticked word to command substitution while
  # append reported success (the record was silently wrong, found on re-read).
  if [ -n "$file" ]; then
    [ -f "$file" ] || refuse "observation file $file absent"
    text=$(cat "$file")
  fi
  [ -n "$text" ] || refuse "usage: observe <ws> --text '...'|--file F (one WORKFLOW defect/friction per entry, as observed)"
  text=$(printf '%s' "$text" | tr '\n\t' '  ')
  state_append "$WS" observations operator "v=1 t=$(date +%s) by=operator text=$text" \
    || refuse "observations surface append failed"
  echo "observation recorded (promotion needs two independent anchors of the same mechanism)"
}

case "${1:-}" in
  rule) shift; verb_rule "$@" ;;
  stop) shift; verb_stop "$@" ;;
  ack) shift; verb_ack "$@" ;;
  slice) shift; verb_slice "$@" ;;
  status) shift; verb_status "$@" ;;
  notify) shift; verb_notify "$@" ;;
  observe) shift; verb_observe "$@" ;;
  peek) shift; verb_peek "$@" ;;
  launch) shift; verb_launch "$@" ;;
  -h|--help|"")
    # The header block delimited by its own SHAPE, not by a pinned line range.
    # It was `sed -n '2,24p'`, and every edit to the verb table above moved the
    # end — adding the status flags truncated the closing line, which 35-verbs
    # caught. Print from line 2 to the first non-comment line.
    awk 'NR==1{next} /^#/{sub(/^# ?/,""); print; next} {exit}' "$0"
    exit 0 ;;
  *) verb_launch "$@" ;;   # default verb: launch <workspace>
esac
