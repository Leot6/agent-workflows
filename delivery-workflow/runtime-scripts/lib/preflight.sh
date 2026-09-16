#!/usr/bin/env bash
# lib/preflight.sh — ferry.sh's preflight half, split out under architecture
# §4.1's layout freedom to keep ferry.sh ≤800 lines; only ferry.sh sources it.
# Uses the ferry's own globals/helpers (WS, WROOT, TOPIC, park, die_store,
# sfield, sput, state_*, pty_*) — it is a half, not a library with its own
# contract.
#
# One question, asked before the ferry advances anything: is the world still the
# one this run was started against? The session fence is reconciled against what
# is actually alive, the store is verified at start (a fault is never read as
# absent), the run surface exists with its identity fields, and the two pins —
# the workflow subtree and plan.md — are compared to what was recorded. Every
# answer here is a park, never a repair: drift is surfaced, not absorbed.

reconcile_fence() {
  local s entry pp pps sp sps
  while IFS= read -r s; do
    [ -n "$s" ] || continue
    entry=$(state_get "$WS" sessions 2>/dev/null | command grep -E "(^| )name=$s( |$)" | tail -1 || true)
    if [ -n "$entry" ]; then
      pp=$(rec_field "$entry" pane_pid); pps=$(rec_field "$entry" pane_start)
      sp=$(rec_field "$entry" server_pid); sps=$(rec_field "$entry" server_start)
      if [ "$(pty_alive "$pp" "$pps" "$sp" "$sps")" = "running" ]; then
        state_audit "$WS" ferry "reconcile: adopted held session $s (witnesses match)"
        continue
      fi
      sessions_replace "$(rec_field "$entry" role)" ""
    fi
    # raw tmux (not pty_teardown): reconcile fences STALE sessions the store
    # no longer owns — fail-closed teardown semantics do not apply to them.
    tmux kill-session -t "=$s" 2>/dev/null || true
    ledger "event=fence session=$s"
    state_audit "$WS" ferry "reconcile: fenced stale session $s"
  done < <(pty_reconcile "delivery-$TOPIC-")
}

workflow_sha() {
  # What the pin must answer is "did the tree these sessions EXECUTE change?",
  # and that is the subtree object, not the repo's HEAD commit. `git -C` walks
  # to the toplevel, so a repo holding sibling workflows moved HEAD on every
  # neighbour commit and parked a live topic over work that could not reach it:
  # of ten measured workflow_changed parks on the dogfood topic, six compared
  # pin-to-pin identical delivery-workflow subtrees, and all six fell in the
  # window after a sibling tree began daily development. `HEAD:<prefix>` is the
  # tree object git already keeps for exactly this question — same identity
  # semantics, one directory narrower. The dirty term was already subtree-scoped
  # (`-- .`); this makes the committed term agree with it.
  #
  # Migration: a stored pin from before this change is a COMMIT sha and will not
  # equal the subtree sha, so the first resume of an old topic parks
  # workflow_changed once and the relaunch repins — the designed adoption path,
  # loud rather than silent.
  local sha dirty prefix
  prefix=$(git -C "$WROOT" rev-parse --show-prefix 2>/dev/null) || { echo no-git; return 0; }
  # An empty prefix means WROOT is itself the toplevel; `HEAD:` is then the root
  # tree, which is the same statement one level up.
  sha=$(git -C "$WROOT" rev-parse "HEAD:${prefix%/}" 2>/dev/null) || { echo no-git; return 0; }
  dirty=$(git -C "$WROOT" status --porcelain -- . 2>/dev/null)
  [ -n "$dirty" ] && sha="$sha-dirty:$(printf '%s' "$dirty" | md5sum | cut -c1-8)"
  printf '%s\n' "$sha"
}

# Startup integrity gate (the verify-at-open discipline): every headed
# surface's checksum is proven before the run touches the store — an append
# over a corrupt surface fails for the whole run, and the mid-run loudness
# above is a survivor's alarm, not a fix. die_store notifies and exits 30.
check_store_integrity() {
  local faults
  faults=$(state_verify_all "$WS") \
    || die_store "integrity check at start: $(printf '%s' "$faults" | tr '\n' ';' | sed 's/;$//')"
}

ensure_run_surface() {
  local rc body snap
  # EVERY launch, deliberately outside the run-surface-absent branch below:
  # that branch is taken once per topic ever, so a live topic could never
  # refresh a file its own manifest title calls "effective" (lib/config.sh
  # carries the measurement). A launch is exactly as often as the two layers
  # can change without the workflow noticing — changing them is an
  # edit-then-relaunch operation.
  snap=$(config_write_snapshot "$WROOT" "$WS")
  body=$(state_get "$WS" run 2>/dev/null); rc=$?
  [ $rc -eq 3 ] && die_store "run surface corrupt"
  if [ $rc -eq 1 ]; then
    local sha ab rb av rv decl
    sha=$(workflow_sha)
    [ "$sha" = "no-git" ] && state_audit "$WS" ferry "workflow tree is not a git repo — workflow_changed pin DISABLED (named degradation)"
    ab=$(cfg agent.author.backend) || refuse_config agent.author.backend
    rb=$(cfg agent.reviewer.backend) || refuse_config agent.reviewer.backend
    # version TOKEN, probe.sh's extraction (a wrapper CLI's upstream
    # API-config module intermittently prints "[Y/n]: " + version SAME line)
    _verline() { awk 'NF {v=$0} END {if (match(v, /[0-9]+\.[0-9]+/)) print substr(v, RSTART); else print v}'; }
    av=$(pty_decl_get "$WROOT/config/backends/$ab.kv" cmd.version 2>/dev/null | _verline || true)
    av=$([ -n "$av" ] && bash -c "$av" 2>/dev/null | _verline || echo unknown)
    rv=$([ "$rb" = "$ab" ] && echo "$av" || { decl="$WROOT/config/backends/$rb.kv"; bash -c "$(pty_decl_get "$decl" cmd.version 2>/dev/null)" 2>/dev/null | _verline; })
    [ -n "$rv" ] || rv=unknown   # same spelling as the author-side miss — one vocabulary
    local pa pb am rm
    pa=$(awk -F= '$1=="result"{print $2}' "$WS/.runtime/probe/$ab.kv" 2>/dev/null); pa=${pa:-none}
    pb=$(awk -F= '$1=="result"{print $2}' "$WS/.runtime/probe/$rb.kv" 2>/dev/null); pb=${pb:-none}
    # Review-independence honesty at the one moment it is decided: a reviewer
    # on the author's own backend+model has the same-model ceiling
    # (review-standards §12 — lineage independence is not cognitive
    # diversity), and every verdict of the topic inherits it. Named once at
    # run init, where the deployment could still change it — the reviews
    # themselves already disclose it per-verdict.
    am=$(cfg agent.author.model) || refuse_config agent.author.model
    rm=$(cfg agent.reviewer.model) || refuse_config agent.reviewer.model
    [ "$ab/$am" = "$rb/$rm" ] && state_audit "$WS" ferry \
      "review independence: reviewer runs the author's own backend+model ($rb/$rm) — same-model ceiling applies to every verdict (set agent.reviewer.backend/model for diversity where available)"
    sput run "topic=$TOPIC" "workspace=$WS" "mode=full-auto" "t_start=$(date +%s)" \
      "workflow_sha=$sha" "plan_hash=" "config_snapshot=$snap" \
      "cli_version.$ab=$(printf '%s' "$av" | tr ' ' '_')" "cli_version.$rb=$(printf '%s' "$rv" | tr ' ' '_')" \
      "probe.$ab=$pa" "probe.$rb=$pb"
    ledger "event=run_init topic=$TOPIC workflow_sha=$sha"
  else
    # The field is derived-at-create, and a measured tree-wide migration left
    # it pointing at a dead path. Re-stamp on every
    # launch (the same write the init branch carries), so the field can no
    # longer be stale at any reader's moment — the move self-heals.
    sput run "workspace=$WS"
  fi
}

check_workflow_pin() {
  local pin cur
  pin=$(sfield run workflow_sha)
  [ -z "$pin" ] || [ "$pin" = "no-git" ] && return 0
  cur=$(workflow_sha)
  [ "$cur" = "$pin" ] || park workflow_changed "workflow tree SHA changed under a live topic (pinned $pin, now $cur) — a deliberate relaunch adopts the new tree and repins (land workflow changes under the maintenance rule: no live stage, self-check green)"
}

check_plan_pin() {
  local pin cur plan="$WS/../plan.md"
  pin=$(sfield run plan_hash)
  [ -n "$pin" ] || return 0
  cur=$(md5sum "$plan" 2>/dev/null | awk '{print $1}')
  [ "$cur" = "$pin" ] || park plan_changed "plan.md hash changed after split pinned it ($pin -> ${cur:-absent}) — decomposition premises are stale; re-run split deliberately"
}
