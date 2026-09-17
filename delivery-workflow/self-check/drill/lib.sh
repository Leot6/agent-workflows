#!/usr/bin/env bash
# drill/lib.sh — the drill's shared ground: a private tmux server, a shadow
# workflow tree with the mock `test` backend declared, and the fixtures every
# scenario stands on. SOURCED once per drill FILE, so each file gets its own
# tmux server and its own shadow tree — two drill files can then run at the
# same time without seeing each other's mutations (S9c edits its shadow's
# declaration in place, which is exactly why the isolation has to be per file).
# `exit 77` below propagates into the sourcing file, which is the SKIP the
# runner wants when tmux is absent.
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/fixtures/lib.sh"
. "$RS/lib/state.sh"

command -v tmux > /dev/null || { echo "SKIP: tmux not installed on this machine"; exit 77; }

DRILL_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
TMUX_TMPDIR=$(mktemp -d /tmp/dwsc-tmux.XXXXXX) || exit 1   # short: socket path cap
export TMUX_TMPDIR
unset TMUX 2>/dev/null || true
cleanup_drill() { tmux kill-server 2>/dev/null; rm -rf "$TMUX_TMPDIR"; sc_cleanup; }
trap cleanup_drill EXIT

echo "-- shadow workflow tree (real code, private root, + test backend) --"
SHADOW=$(sc_tmpdir)
cp -r "$RS" "$SHADOW/runtime-scripts"
cp -r "$WF_ROOT/config" "$SHADOW/config"
cp -r "$WF_ROOT/runtime-docs" "$SHADOW/runtime-docs"
cat > "$SHADOW/config/backends/test.kv" <<EOF
family=pty_tmux
cmd.launch=bash $DRILL_DIR/mock-cli.sh {workspace} {bootstrap}
cmd.version=echo mock-cli-0.1
prompt_style=positional
profile=profiles/settings-hooks.json
cap=pty,subagent,stop_gate,heartbeat,heartbeat_covers_subagents,warm_resume,nudge,takeover
# The mock paints synchronously and then sits: a 0.4s frame-stability gap waits
# for a change that cannot arrive. Declared, because it is a property of THIS
# backend's rendering — the real TUIs keep their live-measured 0.4.
frame_settle=0.05
# The mock reacts in milliseconds (it paints, emits and exits synchronously),
# so the probe's "it never came" bound is 5s here, not the real CLIs' 30:
# measured, one refusal row spent 30 of its 38s waiting out that bound.
probe.latency=5
sig.working=MOCK_WORKING
sig.awaiting_input=^❯$
sig.error_retryable=MOCK_RETRYABLE
sig.quota_exhausted=MOCK_QUOTA
sig.backend_overloaded=MOCK_OVERLOAD
sig.modal.trust=^MOCK_TRUST$
act.modal.trust=Enter
nudge_text=continue
EOF
FERRY="$SHADOW/runtime-scripts/ferry.sh"
LAUNCH="$SHADOW/runtime-scripts/launch.sh"
precond "shadow ferry exists and is executable" test -x "$FERRY"
diff -q "$FERRY" "$RS/ferry.sh" > /dev/null \
  && ok "shadow runtime-scripts byte-identical to the tree under test" \
  || bad "shadow ferry diverged from the real ferry"
# End of the SHARED setup: from here, every assertion belongs to the sourcing
# drill's own arms. check_done's own-arms floor reads this baseline — a drill
# whose body is entirely dead must not ride the two lines above to a green.
_SC_SETUP_N=$_SC_N

shadow_env() { env CONFIG_WORKFLOW_ROOT="$SHADOW" OWED_WORKFLOW_ROOT="$SHADOW" "$@"; }
run_ferry() { # ws logfile -> rc
  shadow_env timeout 300 "$FERRY" "$1" >> "$2" 2>&1
}
# THE DRILL'S PATIENCE, one number for every waiter in this suite. These loops
# wait for a ferry to drive a mock CLI through several stages, which is a
# variable-length pipeline and not a fixed cost. 60s was enough on a quiet box
# and not on a loaded one: measured 2026-09-09, `drill-recovery` and
# `drill-recovery-respawn` both red with "never reached a live impl attempt" at
# loadavg 56-60 and both green on re-run. A larger bound costs nothing on the
# happy path — every loop breaks the moment its condition holds — and only
# lengthens a genuine wedge, which fails either way.
DRILL_PATIENCE_S=${DRILL_PATIENCE_S:-300}
drill_ticks() { echo $(( DRILL_PATIENCE_S * 2 )); }        # the loops sleep 0.5s
drill_load()  { plat_loadavg; }

# Run a ferry in its own session and stop it at the FIRST ledger line matching
# the pattern — the kill/recovery drills' common shape: what the scenario
# needs is a ferry running UP TO an event (a spawn to kill at, an advance to
# stop a verification pass at), not its exit. The caller asserts on the store
# afterwards, which is exactly why a miss must be LOUD: this used to fall out
# of the loop silently, and every assertion after it then read a store that
# never reached the event — a vacuous pass wearing a downstream failure's
# clothes (an unfloored arm).
bg_ferry_until() { # ws logfile ledger-pattern
  local ws=$1 log=$2 pat=$3 fpid hit=0
  setsid env CONFIG_WORKFLOW_ROOT="$SHADOW" OWED_WORKFLOW_ROOT="$SHADOW" \
    "$FERRY" "$ws" >> "$log" 2>&1 &
  fpid=$!
  for _ in $(seq 1 "$(drill_ticks)"); do
    # here-string, not a pipe: a SIGPIPE 141 from state_get would read as
    # "no match yet" and spend the whole patience budget (R19 / VD-76).
    command grep -q "$pat" <<< "$(state_get "$ws" ledger 2>/dev/null)" && { hit=1; break; }
    sleep 0.5
  done
  kill -9 -- -"$fpid" 2>/dev/null
  [ "$hit" -eq 1 ] || bad "bg_ferry_until: the ledger never matched '$pat' in ${DRILL_PATIENCE_S}s (loadavg $(drill_load)) — every assertion after this reads a store that never reached the event; log tail: $(tail -3 "$log" 2>/dev/null)"
}
mk_drill_ws() { # topic [extra-topic-kv-lines] -> ws (repo path in $DR_REPO)
  local b t=$1 bk bn
  b=$(sc_tmpdir)
  read -r DR_REPO _branch < <(mk_repo "$b/repo")
  local ws
  ws=$(mk_ws "$b" "$t" "$DR_REPO" "$_branch")
  { echo "agent.author.backend=test";  echo "agent.author.model=m0";  echo "agent.author.effort=low"
    echo "agent.reviewer.backend=test"; echo "agent.reviewer.model=m0"; echo "agent.reviewer.effort=low"
    echo "liveness.poll=1"
    [ $# -ge 2 ] && printf '%s\n' "$2"
  } > "$ws/config/topic.kv"
  mkdir -p "$ws/.mock"
  # The drill runs the ferry DIRECTLY (FERRY=..., never through launch.sh), so
  # these workspaces have no onboarding probe record and ferry.sh's spawn-side
  # fact guard would park every scenario below. Fabricate the record a launch
  # would have left, for each mock backend the shadow declares. The identity
  # comes from probe.sh itself (--identity), so a change to the cache key can
  # never leave this fixture quietly disagreeing with the code it feeds.
  mkdir -p "$ws/.runtime/probe"
  for bk in "$SHADOW"/config/backends/test*.kv; do
    [ -f "$bk" ] || continue
    bn=$(basename "$bk" .kv)
    { shadow_env bash "$SHADOW/runtime-scripts/probe.sh" --identity "$bk" "$bn"
      echo "result=pass"; echo "t=$(date +%s)"
    } > "$ws/.runtime/probe/$bn.kv"
  done
  printf '%s\n' "$ws"
}
kv() { printf '%s\n' "$1" | awk -F= -v k="$2" '$1==k{v=substr($0,length(k)+2)} END{print v}'; }
halt_kv() { kv "$(state_get "$1" halt 2>/dev/null || true)" "$2"; }
ledger_count() { state_get "$1" ledger 2>/dev/null | command grep -c "$2" || true; }
scen_end() { tmux kill-server 2>/dev/null || true; }

