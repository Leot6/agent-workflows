#!/usr/bin/env bash
# lib/locks.sh — ferry.sh's exclusivity half (the two claims of
# architecture.md §4.2: one ferry per workspace, one topic per checkout),
# split out under architecture §4.1's layout freedom to keep ferry.sh ≤800
# lines; only ferry.sh sources it. Uses the ferry's own globals/helpers
# (WS, HOST_LOCK, OWN_LOCK, state_audit) — it is a half, not a library with
# its own contract. The EXIT trap that releases the host lock is wired in
# ferry.sh's startup section, where the globals it reads are set.

# rc 0 = a live ferry holds HOST_LOCK. One truth, in lib/state.sh, shared with
# launch.sh — which needs the same answer for `stop` (see state_host_holder).
_host_holder_alive() {
  state_host_holder "$WS" > /dev/null
}

take_host_lock() {
  local mystart pid rc
  mystart=$(_pty_starttime $$)
  pid=$(awk -F= '$1=="pid"{print $2}' "$HOST_LOCK/pid" 2>/dev/null | awk '{print $1}')
  # The take primitive is ALWAYS under the flock — fresh take included: between
  # a winner's mkdir and its pid write, a judge would read "no pid" as stale
  # and displace the brand-new lock, so judgment, displacement AND creation are
  # one critical section (git serializes gc.pid takeover under gc.pid.lock the
  # same way). flock, not a lock file: kernel auto-release on death means the
  # section itself cannot go stale. The liveness re-check INSIDE closes the
  # judge-then-displace TOCTOU. (pid above is read pre-section, best-effort,
  # for refusal/audit text only — never for the decision.)
  (
    flock -n 9 || exit 21
    if mkdir "$HOST_LOCK" 2>/dev/null; then
      printf 'pid=%s\nstart=%s\n' $$ "$mystart" > "$HOST_LOCK/pid"
      exit 0
    fi
    _host_holder_alive && exit 22
    rm -rf "$HOST_LOCK"
    mkdir "$HOST_LOCK" || exit 23
    printf 'pid=%s\nstart=%s\n' $$ "$mystart" > "$HOST_LOCK/pid"
    exit 24
  ) 9> "$HOST_LOCK.reclaim"; rc=$?
  case $rc in
    0)  OWN_LOCK=1
        state_audit "$WS" ferry "host lock taken (pid $$)" ;;
    24) OWN_LOCK=1
        state_audit "$WS" ferry "stale host lock (pid ${pid:-?}) reclaimed"
        state_audit "$WS" ferry "host lock taken (pid $$)" ;;
    21) echo "refuse: another candidate is mid-reclaim (take serialized) on $HOST_LOCK — one wins; relaunch after it settles" >&2; exit 20 ;;
    22) echo "refuse: another ferry (pid ${pid:-?}) holds $HOST_LOCK — one driver per workspace" >&2; exit 20 ;;
    *)  echo "refuse: host lock take failed (rc=$rc)" >&2; exit 20 ;;
  esac
}
release_lock() { [ "$OWN_LOCK" -eq 1 ] && rm -rf "$HOST_LOCK"; }

take_repo_lock() { # repo — the claim primitive (one topic per checkout)
  local repo=$1 lock topic claim mystart
  [ -d "$repo" ] || { echo "refuse: repo $repo is not a directory" >&2; exit 20; }
  lock=$(state_repo_lock_path "$repo") || { echo "refuse: repo $repo is not a git checkout — the pipeline is git-shaped (commit gates, SHA ancestry, the claim lock)" >&2; exit 20; }
  mystart=$(_pty_starttime $$)
  # NB the claim's topic= key holds the WORKSPACE PATH (state_repo_claimed
  # compares it against $WS) — kept for record compatibility; read it as
  # "which workspace claims this checkout".
  topic=$(awk -F= '$1=="topic"{print $2}' "$lock" 2>/dev/null)
  # The take primitive is ALWAYS under the flock (same reasoning as the host
  # lock: fresh create, liveness judgment and displacement are one critical
  # section — a fresh set -C claim read between open and content write would
  # judge as stale and be displaced). One key per LINE inside the claim — the
  # awk -F= readers are line-based; a single-line record would parse only
  # 'topic' and read a live holder as stale. state_repo_claimed is the ONE
  # holder-liveness predicate, shared with the preflight's advisory check;
  # the take stays the authority. (topic above is pre-section, best-effort,
  # for audit text only.)
  local rc
  (
    flock -n 9 || exit 21
    if ( set -C; printf 'topic=%s\npid=%s\nstart=%s\n' "$WS" $$ "$mystart" > "$lock" ) 2>/dev/null; then
      exit 0
    fi
    state_repo_claimed "$repo" "$WS" > /dev/null && exit 22
    rm -f "$lock"
    ( set -C; printf 'topic=%s\npid=%s\nstart=%s\n' "$WS" $$ "$mystart" > "$lock" ) 2>/dev/null || exit 23
    exit 24
  ) 9> "$lock.reclaim"; rc=$?
  case $rc in
    0)  state_audit "$WS" ferry "repo lock taken ($repo)" ;;
    24) [ -n "$topic" ] && [ "$topic" != "$WS" ] \
          && state_audit "$WS" ferry "stale repo lock from other topic $topic reclaimed"
        state_audit "$WS" ferry "repo lock taken ($repo)" ;;
    21) echo "refuse: another candidate is mid-reclaim (take serialized) on $lock — one wins; relaunch after it settles" >&2; exit 20 ;;
    22) claim=$(state_repo_claimed "$repo" "$WS" || true)
        echo "refuse: repo $repo is claimed by another live topic ($claim) — parallel topics require separate checkouts/worktrees" >&2; exit 20 ;;
    *)  echo "refuse: repo lock take failed (rc=$rc)" >&2; exit 20 ;;
  esac
}

# Every declared repo claimed at topic start, in project_repos' fixed order
# (code → doc): a mixed topic holds both checkouts for its whole run, and the
# fixed global order is what makes two mixed topics unable to deadlock on them.
# A doc repo claimed by another live topic refuses exactly like the code repo —
# parallel topics need separate checkouts, whichever repo collides.
take_repo_locks() {
  local repo n=0
  while IFS= read -r repo; do
    [ -n "$repo" ] || continue
    n=$((n + 1))
    take_repo_lock "$repo"
  done < <(project_repos "$WS")
  [ "$n" -gt 0 ] \
    || { echo "refuse: project.kv missing or no repo= — the project adapter is required" >&2; exit 20; }
}

# Released at COMPLETE only (complete_topic): a park keeps every claim, so the
# topic resumes onto its own checkouts. Releasing one of two would strand the
# other for every later topic.
release_repo_locks() {
  local repo l
  while IFS= read -r repo; do
    [ -n "$repo" ] || continue
    l=$(state_repo_lock_path "$repo" 2>/dev/null) || continue
    rm -f "$l" "$l.reclaim"
  done < <(project_repos "$WS")
}
