#!/usr/bin/env bash
# 15-locks — the two exclusivity locks (ferry.sh): host lock (one ferry per
# workspace) and repo lock (one topic per project checkout). The repo-lock
# fixture runs two REAL processes against one repo: a live holder must refuse
# the second topic; a dead holder's lock is reclaimed with an audit note.
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/fixtures/lib.sh"
. "$RS/lib/state.sh"

base=$(sc_tmpdir)
read -r repo branch < <(mk_repo "$base/repo")
wsA=$(mk_ws "$base" locktopica "$repo" "$branch")
wsB=$(mk_ws "$base" locktopicb "$repo" "$branch")
hf=$(mk_headless_ferry)
# The two REAL launch invocations below go through a SHADOW copy of the tree
# (clean by construction): preflight refuses a dirty workflow tree BEFORE the
# repo-claim advisory check, so running the real launch.sh from a maintainer's
# in-progress tree would red these fixtures on the dirt instead of exercising
# the claim refusal they exist to pin (measured: the pre-commit full-suite run
# — the one ops doctrine requires on a dirty tree — is exactly that state).
shroot="$base/shadow"
cp -a "$WF_ROOT" "$shroot"
( cd "$shroot" && git init -q . \
  && git config user.email sc@example.invalid && git config user.name selfcheck \
  && git add -A && git commit -qm "chore: fixture workflow tree" )
SHLAUNCH="$shroot/runtime-scripts/launch.sh"
precond "shadow launch.sh exists and its tree is clean" \
  bash -c 'test -f "$1" && [ -z "$(git -C "$2" status --porcelain)" ]' _ "$SHLAUNCH" "$shroot"

# holder script: source the headless ferry as topic A, take the repo lock,
# signal readiness, then hold until told to exit (pid stays live throughout).
holder="$base/holder.sh"
cat > "$holder" <<EOF
. "$hf" "$wsA" > /dev/null 2>&1
take_repo_lock "$repo" || exit 9
touch "$base/holder.ready"
for i in \$(seq 1 100); do [ -e "$base/holder.done" ] && exit 0; sleep 0.1; done
exit 8
EOF

echo "-- repo lock: a LIVE holder refuses the second topic --"
bash "$holder" &
holder_pid=$!
for i in $(seq 1 50); do [ -e "$base/holder.ready" ] && break; sleep 0.1; done
precond "holder took the lock (live process $holder_pid)" test -e "$base/holder.ready"
rlock=$(git -C "$repo" rev-parse --absolute-git-dir)/delivery.lock
lock_before=$(cat "$rlock")
assert_rc 20 "second topic on the SAME repo refuses while the holder lives" -- \
  bash -c ". '$hf' '$wsB' > /dev/null 2>&1; take_repo_lock '$repo'"
assert_out_has "claimed by another live topic" "refusal names the conflict"
lock_after=$(cat "$rlock")
[ "$lock_before" = "$lock_after" ] \
  && ok "the live holder's lock record was NOT overwritten" \
  || bad "second topic overwrote a live lock: '$lock_after'"
printf '%s\n' "$lock_after" | command grep -q "locktopica" \
  && ok "lock still names topic A's workspace" \
  || bad "lock no longer names topic A: '$lock_after'"

echo "-- preflight advisory check: a doomed launch refuses BEFORE spending a probe session --"
# The holder from above is still alive and owns the repo for topic A. A real
# launch.sh launch of topic B must refuse at preflight on the lock conflict —
# not proceed to instantiate profiles / spend a probe session and only be
# refused by the ferry after the watchdog detached. The backend is deliberately
# nonexistent so that even on the pre-fix path nothing can ever spawn.
printf 'agent.author.backend=nosuchcli\nagent.reviewer.backend=nosuchcli\n' \
  > "$wsB/config/topic.kv"
out=$(bash "$SHLAUNCH" launch "$wsB" 2>&1); rc=$?
[ $rc -eq 2 ] && ok "launch refuses (rc=2, preflight refusal — no watchdog, no ferry)" \
  || bad "launch rc=$rc, want a preflight refusal"
printf '%s' "$out" | command grep -q "claimed by another live topic" \
  && ok "the refusal names the repo-lock conflict at PREFLIGHT (same predicate the ferry's take uses)" \
  || bad "preflight never checked the repo lock — refusal was '$(printf '%s' "$out" | tail -1)' and a real backend would have spent a probe session first"
[ ! -d "$wsB/.runtime/probe" ] \
  && ok "no probe was attempted on the doomed launch" \
  || bad "probe directory exists — a session (or its attempt) was spent before the lock refusal"
touch "$base/holder.done"
wait "$holder_pid" 2>/dev/null
assert_rc 0 "after the holder dies, topic B reclaims the stale lock" -- \
  bash -c ". '$hf' '$wsB' > /dev/null 2>&1; take_repo_lock '$repo'"
command grep -q "locktopicb" "$rlock" \
  && ok "reclaimed lock names topic B" || bad "lock: $(cat "$rlock")"
[ -z "$(git -C "$repo" status --porcelain)" ] \
  && ok "taking the repo lock leaves the WORKTREE clean (the claim lives in the git dir — no status noise, no dirty-fingerprint churn on relaunch)" \
  || bad "repo lock dirties the checkout: $(git -C "$repo" status --porcelain | head -2 | tr '\n' ' ')"
state_get "$wsB" audit 2>/dev/null | command grep -q "reclaimed" \
  && ok "reclaim left an audit note" || bad "no audit note for the reclaim"

echo "-- repo lock: same topic relaunch refreshes its own lock --"
assert_rc 0 "topic B relaunching over its own lock succeeds" -- \
  bash -c ". '$hf' '$wsB' > /dev/null 2>&1; take_repo_lock '$repo'"

echo "-- stale-lock takeover is SERIALIZED (reclaim critical section; deterministic, no wall-clock race) --"
# Two candidates that both judged the old holder dead must not interleave the
# displacement (rm+recreate) and both "win" — git serializes gc.pid takeover
# under gc.pid.lock the same way. The fixture holds the reclaim flock and
# asserts a take on a STALE lock refuses instead of displacing; releasing the
# flock lets the same stale lock reclaim normally (both directions, no timing).
gd=$(git -C "$repo" rev-parse --absolute-git-dir)
printf 'topic=%s\npid=99999\nstart=0\n' "$wsA" > "$gd/delivery.lock"   # stale: starttime 0 never matches
exec 7> "$gd/delivery.lock.reclaim"
precond "fixture holds the repo reclaim flock" flock -n 7
assert_rc 20 "repo-lock take on a STALE claim refuses while another candidate holds the reclaim flock" -- \
  bash -c ". '$hf' '$wsB' > /dev/null 2>&1; take_repo_lock '$repo'"
assert_out_has "mid-reclaim" "refusal names the reclaim contention"
command grep -q "locktopica" "$gd/delivery.lock" \
  && ok "the contended stale claim was NOT displaced" \
  || bad "reclaim under contention displaced the lock: $(cat "$gd/delivery.lock" 2>/dev/null | tr '\n' ' ')"
exec 7>&-
assert_rc 0 "with the flock released, the same stale claim reclaims normally" -- \
  bash -c ". '$hf' '$wsB' > /dev/null 2>&1; take_repo_lock '$repo'"
command grep -q "locktopicb" "$gd/delivery.lock" \
  && ok "uncontended reclaim names topic B" || bad "lock: $(cat "$gd/delivery.lock")"

# FRESH take must be serialized too, not only reclaim: between a winner's
# mkdir and its pid write, a judge would read "no pid" as stale and displace
# the brand-new lock — so the take primitive is ALWAYS under the flock.
rm -rf "$wsA/.runtime/state/lock"
exec 5> "$wsA/.runtime/state/lock.reclaim"
precond "fixture holds the host take/reclaim flock (no lock exists)" flock -n 5
assert_rc 20 "a FRESH host-lock take (no lock present) refuses while the flock is held" -- \
  bash -c ". '$hf' '$wsA' > /dev/null 2>&1; take_host_lock"
[ ! -d "$wsA/.runtime/state/lock" ] \
  && ok "the contended fresh take created nothing" \
  || bad "fresh take bypassed the critical section: lock dir exists"
exec 5>&-
rm -f "$gd/delivery.lock"
exec 5> "$gd/delivery.lock.reclaim"
precond "fixture holds the repo take/reclaim flock (no claim exists)" flock -n 5
assert_rc 20 "a FRESH repo-lock take (no claim present) refuses while the flock is held" -- \
  bash -c ". '$hf' '$wsB' > /dev/null 2>&1; take_repo_lock '$repo'"
[ ! -f "$gd/delivery.lock" ] \
  && ok "the contended fresh repo take created nothing" \
  || bad "fresh repo take bypassed the critical section: claim exists"
exec 5>&-

rm -rf "$wsA/.runtime/state/lock"
mkdir -p "$wsA/.runtime/state/lock"
printf 'pid=99999 start=0\n' > "$wsA/.runtime/state/lock/pid"          # stale host holder
exec 6> "$wsA/.runtime/state/lock.reclaim"
precond "fixture holds the host reclaim flock" flock -n 6
assert_rc 20 "host-lock take on a STALE lock refuses while another candidate holds the reclaim flock" -- \
  bash -c ". '$hf' '$wsA' > /dev/null 2>&1; take_host_lock"
assert_out_has "mid-reclaim" "host refusal names the reclaim contention"
command grep -q "pid=99999" "$wsA/.runtime/state/lock/pid" \
  && ok "the contended stale host lock was NOT displaced" \
  || bad "host reclaim under contention displaced the lock: $(cat "$wsA/.runtime/state/lock/pid" 2>/dev/null)"
exec 6>&-
assert_rc 0 "with the flock released, the same stale host lock reclaims normally" -- \
  bash -c ". '$hf' '$wsA' > /dev/null 2>&1; take_host_lock"

echo "-- two-repo topic: EVERY declared repo is claimed at start, fixed order code -> doc --"
# A mixed topic (code slices + doc slices) holds both checkouts for its whole
# run; the order is fixed globally (project_repos) so two mixed topics can
# never deadlock on them (lock hierarchy, CERT LCK07-J).
read -r drepo dbranch < <(mk_doc_repo "$base/docrepo")
printf 'doc.repo=%s\ndoc.branch=%s\n' "$drepo" "$dbranch" >> "$wsB/project.kv"
dlock=$(git -C "$drepo" rev-parse --absolute-git-dir)/delivery.lock
rm -f "$gd/delivery.lock" "$dlock"
rm -f "$wsB/.runtime/state/audit"
assert_rc 0 "take_repo_locks claims both declared repos" -- \
  bash -c ". '$hf' '$wsB' > /dev/null 2>&1; take_repo_locks"
command grep -q "locktopicb" "$gd/delivery.lock" 2>/dev/null \
  && ok "the code repo is claimed" || bad "code claim: $(cat "$gd/delivery.lock" 2>/dev/null | tr '\n' ' ')"
command grep -q "locktopicb" "$dlock" 2>/dev/null \
  && ok "the DOC repo is claimed by the same workspace" \
  || bad "doc claim absent/anonymous: $(cat "$dlock" 2>/dev/null | tr '\n' ' ')"
order=$(state_get "$wsB" audit 2>/dev/null | command grep -n "repo lock taken" \
        | sed -e "s|.*repo lock taken ($repo).*|code|" -e "s|.*repo lock taken ($drepo).*|doc|" \
        | command grep -xE 'code|doc' | paste -sd, -)
[ "$order" = "code,doc" ] \
  && ok "the audit trail shows the fixed order code -> doc (a global order is what excludes deadlock)" \
  || bad "take order was '$order', want code,doc"
[ -z "$(git -C "$drepo" status --porcelain)" ] \
  && ok "claiming the doc repo leaves ITS worktree clean too (claim lives in the git dir)" \
  || bad "doc repo dirtied: $(git -C "$drepo" status --porcelain | head -2 | tr '\n' ' ')"

echo "-- a live foreign holder of the DOC repo refuses the whole topic --"
dholder="$base/dholder.sh"
cat > "$dholder" <<EOF
. "$hf" "$wsA" > /dev/null 2>&1
take_repo_lock "$drepo" || exit 9
touch "$base/dholder.ready"
for i in \$(seq 1 100); do [ -e "$base/dholder.done" ] && exit 0; sleep 0.1; done
exit 8
EOF
rm -f "$gd/delivery.lock" "$dlock"
bash "$dholder" &
dpid=$!
for i in $(seq 1 50); do [ -e "$base/dholder.ready" ] && break; sleep 0.1; done
precond "topic A holds the DOC repo (live process $dpid)" test -e "$base/dholder.ready"
assert_rc 20 "topic B refuses: its doc repo is claimed, even though the code repo is free" -- \
  bash -c ". '$hf' '$wsB' > /dev/null 2>&1; take_repo_locks"
assert_out_has "claimed by another live topic" "the doc-repo conflict is named like any other"
# …and the preflight must refuse it too, for the same reason the code repo's
# advisory check exists: a launch doomed to the ferry's take must fail
# BEFORE a probe session is spent and a watchdog detached. Same fixture shape
# as the code-repo case above — a nonexistent backend, so nothing can spawn
# even if the refusal were missing.
out=$(bash "$SHLAUNCH" launch "$wsB" 2>&1); rc=$?
[ $rc -eq 2 ] && ok "launch refuses at preflight while the DOC repo is held (rc=2)" \
  || bad "launch rc=$rc with the doc repo held — want a preflight refusal"
printf '%s' "$out" | command grep -q "claimed by another live topic" \
  && printf '%s' "$out" | command grep -qF "$drepo" \
  && ok "the preflight refusal names the DOC checkout (every declared repo is walked, not just the first)" \
  || bad "preflight did not refuse on the doc repo: $(printf '%s' "$out" | tail -1)"
[ ! -d "$wsB/.runtime/probe" ] \
  && ok "no probe was spent on the doomed launch" \
  || bad "a probe session (or its attempt) was spent before the doc-repo refusal"
touch "$base/dholder.done"
wait "$dpid" 2>/dev/null

echo "-- release_repo_locks (COMPLETE) drops every claim, none left behind --"
rm -f "$gd/delivery.lock" "$dlock"
bash -c ". '$hf' '$wsB' > /dev/null 2>&1; take_repo_locks; release_repo_locks" > /dev/null 2>&1
[ ! -f "$gd/delivery.lock" ] && [ ! -f "$dlock" ] \
  && ok "both claims released (a one-repo release would strand the doc checkout for every later topic)" \
  || bad "left behind: code=$([ -f "$gd/delivery.lock" ] && echo yes || echo no) doc=$([ -f "$dlock" ] && echo yes || echo no)"
sed -i '/^doc\./d' "$wsB/project.kv"

echo "-- host lock: one ferry per workspace --"
rm -rf "$wsA/.runtime/state/lock"
holder2="$base/holder2.sh"
cat > "$holder2" <<EOF
. "$hf" "$wsA" > /dev/null 2>&1
take_host_lock || exit 9
OWN_LOCK=0   # keep the lock alive past this process's EXIT trap
touch "$base/holder2.ready"
for i in \$(seq 1 100); do [ -e "$base/holder2.done" ] && exit 0; sleep 0.1; done
exit 8
EOF
bash "$holder2" &
h2=$!
for i in $(seq 1 50); do [ -e "$base/holder2.ready" ] && break; sleep 0.1; done
precond "holder2 took the host lock" test -e "$base/holder2.ready"
assert_rc 20 "a second ferry on the SAME workspace refuses (host lock held, pid live)" -- \
  bash -c ". '$hf' '$wsA' > /dev/null 2>&1; take_host_lock"
assert_out_has "one driver per workspace" "refusal self-describing"
touch "$base/holder2.done"
wait "$h2" 2>/dev/null
assert_rc 0 "after the holder dies, the stale host lock is reclaimed" -- \
  bash -c ". '$hf' '$wsA' > /dev/null 2>&1; take_host_lock"

check_done
