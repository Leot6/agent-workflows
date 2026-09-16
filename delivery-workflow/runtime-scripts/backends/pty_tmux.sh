#!/usr/bin/env bash
# backends/pty_tmux.sh — the single structural adapter (backend-seam.md §4/§6).
# Contract: spawn_cold · alive · classify_screen · inject · teardown · reconcile.
# Capability 0: this file is a mechanical pipe — it carries zero cross-role
# reasoning and never frames or pre-judges agent output.
# The adapter reads a backend DECLARATION (config/backends/<name>.kv) and never
# branches on a backend name.
#
# tmux lessons carried from v1 (paid for): exact-match targets '=<name>' only;
# send-keys -l for text + a separate Enter; NEVER navigation keys; dual-pid +
# procfs starttime against pid reuse; fail-closed teardown (never start a
# replacement server to prove absence).

_PTY_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

pty_decl_get() { # decl_file key -> value (rc 1 absent)
  local v
  v=$(awk -F= -v k="$2" '$0 !~ /^#/ && $1==k {v=substr($0,length(k)+2)} END{if(v=="")exit 1; print v}' "$1") || return 1
  # Declarations write NBSP as \xC2\xA0; materialize escapes into real bytes
  # so grep -E matches them literally under LC_ALL=C.
  printf '%b\n' "$v"
}

pty_session_name_ok() { # name
  printf '%s\n' "$1" | command grep -qE '^[A-Za-z0-9_-]+$' || {
    echo "refuse: session name '$1' outside charset [A-Za-z0-9_-] (a ':' or glob can redirect tmux targets)" >&2
    return 2
  }
}

_pty_starttime() { # pid -> procfs starttime (field 22, after the comm paren)
  [ -r "/proc/$1/stat" ] || return 1
  awk '{ s=$0; sub(/^[^)]*\) /,"",s); split(s,f," "); print f[20] }' "/proc/$1/stat"
}

# spawn_cold decl session model effort workspace profile prompt_file log_file
# stdout: name= pane_pid= pane_start= server_pid= server_start= socket=
pty_spawn_cold() {
  local decl=$1 session=$2 model=$3 effort=$4 ws=$5 profile=$6 prompt=$7 log=$8
  pty_session_name_ok "$session" || return 2
  [ -f "$prompt" ] || { echo "refuse: prompt file $prompt absent" >&2; return 2; }
  local tmpl cmd bootstrap
  tmpl=$(pty_decl_get "$decl" cmd.launch) || {
    echo "refuse: declaration $decl has no cmd.launch" >&2; return 2
  }
  # Bootstrap: constant-shape positional argument — prompt content never on
  # the command line, no post-boot injection window (architecture §7).
  bootstrap=$(printf '%q' "Read and execute $prompt")
  cmd=$tmpl
  cmd=${cmd//\{model\}/$model}
  cmd=${cmd//\{effort\}/$effort}
  cmd=${cmd//\{workspace\}/$ws}
  cmd=${cmd//\{profile\}/$profile}
  cmd=${cmd//\{bootstrap\}/$bootstrap}
  case "$cmd" in
    *'{'*'}'*) echo "refuse: cmd.launch has unresolved placeholder after fill: $cmd" >&2; return 2 ;;
  esac
  tmux new-session -d -s "$session" -x 220 -y 50 "$cmd" || {
    echo "spawn failed: tmux new-session -s $session" >&2; return 1
  }
  # The geometry is part of the declared contract the classifier reads, so it is
  # pinned rather than negotiated: with the global default (smallest) ANY attach
  # client — a read-only one included — rewrites the pane's size permanently
  # (no rebound), and wrapped lines at another width are a different screen to
  # every declared signature. A spawn that cannot pin its declared geometry
  # refuses rather than running unpinned — and leaves no session behind: every
  # earlier refusal point in this function precedes new-session, so this is the
  # one that must clean up after itself. The refusal names the version floor
  # (window-size arrived in tmux 2.9): on an older tmux every spawn would die
  # here, and "cannot pin" without the floor sends the operator hunting a
  # declaration defect that is not there.
  tmux set-option -w -t "=$session:" window-size manual || {
    # A LIVE session that cannot take the option is the version floor. A session
    # that is GONE is a different failure wearing this one's message: the pane's
    # command exited immediately (the absent-CLI shape — tmux starts the pane,
    # the shell cannot find the binary, the pane dies and takes the session with
    # it), and blaming the tmux version here read, measured on a cold machine,
    # "needs tmux >= 2.9; this machine: tmux 3.0a" — a self-contradiction that
    # sent the operator hunting a defect that was not there. Name the command:
    # it is the one thing the operator can actually check.
    if ! tmux has-session -t "=$session:" 2>/dev/null; then
      echo "spawn failed: the pane's command exited immediately (session $session is already gone) — the backend CLI is probably not installed or not on PATH; cmd was: $cmd" >&2
    else
      echo "spawn failed: cannot pin window-size manual on $session (window-size needs tmux >= 2.9; this machine: $(tmux -V 2>/dev/null || echo unknown))" >&2
      tmux kill-session -t "=$session" 2>/dev/null
    fi
    return 1
  }
  tmux pipe-pane -t "=$session:" -o "cat >> $(printf '%q' "$log")" || true
  local pane_pid server_pid socket pane_start server_start
  pane_pid=$(tmux display-message -p -t "=$session:" '#{pane_pid}')
  server_pid=$(tmux display-message -p -t "=$session:" '#{pid}')
  socket=$(tmux display-message -p -t "=$session:" '#{socket_path}')
  pane_start=$(_pty_starttime "$pane_pid" || echo 0)
  server_start=$(_pty_starttime "$server_pid" || echo 0)
  printf 'name=%s pane_pid=%s pane_start=%s server_pid=%s server_start=%s socket=%s\n' \
    "$session" "$pane_pid" "$pane_start" "$server_pid" "$server_start" "$socket"
}

# alive pane_pid pane_start server_pid server_start -> running|dead (rc 0/1)
pty_alive() {
  local pp=$1 ps=$2 sp=$3 ss=$4 s
  for pair in "$pp:$ps" "$sp:$ss"; do
    local pid=${pair%%:*} want=${pair#*:}
    s=$(_pty_starttime "$pid" 2>/dev/null) || { echo dead; return 1; }
    [ "$s" = "$want" ] || { echo dead; return 1; }  # pid reused: not our process
  done
  echo running
}

_pty_capture() { # session -> pane text (rc 1 on capture failure)
  tmux capture-pane -p -t "=$1:" 2>/dev/null
}

# The gap between the two frames of the stability test. It is a RENDERING
# property of the CLI — how long its output may pause mid-flight and still be
# flowing — so it belongs in the declaration beside sig.working rather than as
# a constant in this adapter. 0.4 is the live-measured value for the Claude
# Code TUIs and remains the default for any declaration that says nothing; a
# backend that paints synchronously declares less, and nothing then pays 0.4s
# per classification to watch a frame that cannot change. Non-numeric or
# absent falls back rather than failing: a settle time is a comfort, and a
# declaration typo must not stop a session from being classified at all.
_pty_settle() { # decl -> seconds
  local v
  v=$(pty_decl_get "$1" frame_settle 2>/dev/null) || v=""
  case "$v" in ''|*[!0-9.]*) v=0.4 ;; esac
  printf '%s\n' "$v"
}

# First n DISPLAY CELLS of a line. A UTF-8 continuation byte is not a cell; a
# wide char is counted as one, so the prefix comes out LONGER than the terminal
# drew — which can only ADD text to the emptiness test below, never remove it
# (the safe direction: a false "occupied" refuses an injection, a false "empty"
# would fuse one).
_pty_cells() { # n line
  LC_ALL=C awk -v n="$1" '
    { o = ""; c = 0; i = 1
      while (i <= length($0) && c < n) {
        ch = substr($0, i, 1)
        if (ch ~ /[\200-\277]/) { o = o ch; i++; continue }
        o = o ch; c++; i++
      }
      while (i <= length($0) && substr($0, i, 1) ~ /[\200-\277]/) { o = o substr($0, i, 1); i++ }
      print o }' <<< "$2"
}

# Is a HUMAN at this pane? tmux knows: a client attached to this session that
# is not read-only. `attach -r` (what operations.md tells inspectors to use)
# reports readonly=1 and is correctly not a human who can type.
_pty_human_attached() { # session -> 0 writable client attached · 1 no / cannot tell
  tmux list-clients -t "=$1:" -F '#{client_readonly}' 2>/dev/null | command grep -qx 0
}

# Is the composer EMPTY — the precondition every injection stands on.
#
# It is the CURSOR's question, not the text's. A TUI paints its placeholder or
# hint AFTER the cursor and a human's typing BEFORE it; a plain capture drops
# the attribute that separates them, so the line reads identically either way
# (live-measured: Claude Code 2.1.228 paints a dim `/exit` hint into an EMPTY
# box, which made every classification `unknown` and every injection a refusal
# — the topic could not be nudged at all). So the declared sig.awaiting_input
# is applied to the composer line TRUNCATED AT THE CURSOR: what the human typed
# is exactly what lies before it.
#
# When tmux cannot say where the cursor is, or it is not on a composer line
# (a fixture ending in a newline, a TUI that parks it elsewhere), the
# pre-cursor rule answers on the whole line — the previous behaviour, kept as
# the degradation rather than a refusal.
# rc: 0 empty · 1 occupied · 2 no composer on screen / undeclared (callers keep
# their own no-composer path).
_pty_composer_empty() { # decl session frame
  local decl=$1 session=$2 frame=$3 comp_re sig line cx="" cy=""
  sig=$(pty_decl_get "$decl" sig.awaiting_input 2>/dev/null) || return 2
  comp_re=$(pty_decl_get "$decl" sig.composer_line 2>/dev/null) || comp_re=""
  if [ -n "$comp_re" ]; then
    read -r cx cy < <(tmux display-message -p -t "=$session:" '#{cursor_x} #{cursor_y}' 2>/dev/null) || true
    case "$cx.$cy" in *[!0-9.]*) cx="" ;; esac
    if [ -n "$cx" ]; then
      line=$(printf '%s\n' "$frame" | sed -n "$((cy + 1))p")
      if printf '%s\n' "$line" | command grep -qE "$comp_re"; then
        printf '%s\n' "$(_pty_cells "$cx" "$line")" | command grep -qE "$sig" && return 0
        return 1
      fi
    fi
    line=$(printf '%s\n' "$frame" | command grep -E "$comp_re" | tail -1)
    [ -n "$line" ] || return 2
    printf '%s\n' "$line" | command grep -qE "$sig" && return 0
    return 1
  fi
  # No composer_line declared (the drill's minimal backend): the last non-empty
  # line is all the adapter has. It can answer EMPTY — the line IS the awaiting
  # signature — but never OCCUPIED: without a declared anchor there is no way to
  # tell a composer carrying text from any other screen, and the caller's
  # classify path answers instead. (This replaces a hardcoded `❯` test in
  # pty_inject, which was a declaration leak into the structural adapter.)
  line=$(printf '%s\n' "$frame" | sed -e 's/[[:space:]]*$//' | command grep -v '^$' | tail -1)
  printf '%s\n' "$line" | command grep -qE "$sig" && return 0
  return 2
}

# classify_screen decl session
# -> working|awaiting_input|error_retryable|quota_exhausted|backend_overloaded|modal.<name>|unknown
# Double capture; disagreeing frames = output still flowing = working.
# The classification DOMAIN is the live status region — from the LAST composer
# line (sig.composer_line) to the frame's end — never the whole transcript: a
# finished tool banner (a lingering `✻`) in scrollback history is history, not
# state, and the line BELOW the composer is a status footer, not the composer
# (both live-measured; whole-frame matching classified a real idle CLI as
# working, and last-line matching classified it as unknown).
# Precedence: modal (overlay dominates, whole frame) > working (in-region: the
# footer shows the live indicators while the CLI works) > error_retryable >
# awaiting_input (the composer LINE, NBSP-aware empty-composer regex) — which
# splits once more: an empty composer over a frame carrying
# sig.quota_exhausted is `quota_exhausted`, and one over a frame carrying
# sig.backend_overloaded is `backend_overloaded` — both because the line lands
# in the TRANSCRIPT above the composer and the status region alone can never
# see it, and quota is asked first because only quota names a reset time
# > unknown. A declaration without sig.composer_line keeps the legacy last-line
# domain. A dead CLI kills its pane (the launch command IS the pane command),
# so pid/starttime liveness is the dead-detection truth; a hypothetical
# pane-alive-CLI-dead state has no composer and parks unknown_screen, loudly.
# Frame-stability domain: with a composer on screen, compare TRANSCRIPT +
# COMPOSER only — the status footer below carries a live timer/token counter
# whose periodic repaint is bookkeeping, not output flowing (live-measured: a
# footer tick inside the double-capture window misread idle as working and
# made one-shot injection flaky).
_pty_frames_disagree() { # comp_re f1 f2 -> rc 0 if genuinely flowing
  local comp_re=$1 f1=$2 f2=$3 c1 c2
  if [ -n "$comp_re" ]; then
    c1=$(printf '%s\n' "$f1" | command grep -nE "$comp_re" | tail -1 | cut -d: -f1)
    c2=$(printf '%s\n' "$f2" | command grep -nE "$comp_re" | tail -1 | cut -d: -f1)
    if [ -n "$c1" ] && [ "$c1" = "$c2" ]; then
      [ "$(printf '%s\n' "$f1" | head -n "$c1")" != "$(printf '%s\n' "$f2" | head -n "$c2")" ]
      return
    fi
  fi
  [ "$f1" != "$f2" ]
}

pty_classify_screen() {
  local decl=$1 session=$2 f1 f2 last sig name comp_re comp_ln region
  f1=$(_pty_capture "$session") || { echo unknown; return 0; }
  sleep "$(_pty_settle "$decl")"
  f2=$(_pty_capture "$session") || { echo unknown; return 0; }
  comp_re=$(pty_decl_get "$decl" sig.composer_line 2>/dev/null) || comp_re=""
  if _pty_frames_disagree "$comp_re" "$f1" "$f2"; then echo working; return 0; fi
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    sig=$(pty_decl_get "$decl" "sig.modal.$name") || continue
    if printf '%s\n' "$f2" | command grep -qE "$sig"; then echo "modal.$name"; return 0; fi
  done < <(awk -F= '$0 !~ /^#/ && $1 ~ /^sig\.modal\./ {sub(/^sig\.modal\./,"",$1); print $1}' "$decl")
  comp_ln=""
  [ -n "$comp_re" ] && comp_ln=$(printf '%s\n' "$f2" | command grep -nE "$comp_re" | tail -1 | cut -d: -f1)
  if [ -n "$comp_ln" ]; then
    region=$(printf '%s\n' "$f2" | tail -n +"$comp_ln")
    sig=$(pty_decl_get "$decl" sig.working) || sig=""
    if [ -n "$sig" ] && printf '%s\n' "$region" | command grep -qE "$sig"; then
      echo working; return 0
    fi
    sig=$(pty_decl_get "$decl" sig.error_retryable) || sig=""
    if [ -n "$sig" ] && printf '%s\n' "$region" | command grep -qE "$sig"; then
      echo error_retryable; return 0
    fi
    if _pty_composer_empty "$decl" "$session" "$f2"; then
      # Quota is a REFINEMENT of idle, not a competitor to working: the CLI
      # prints its exhaustion line into the TRANSCRIPT (above the composer,
      # outside the status region) and then sits at an empty prompt. Read from
      # the region alone it would never be seen; read from the whole frame
      # while the composer is empty, it is exactly "idle, and the visible
      # reason is that the backend refuses". A session doing work classifies
      # working before reaching here, so a stale line cannot hijack a live one.
      sig=$(pty_decl_get "$decl" sig.quota_exhausted) || sig=""
      if [ -n "$sig" ] && printf '%s\n' "$f2" | command grep -qE "$sig"; then
        echo quota_exhausted; return 0
      fi
      # Overload is the SAME refinement with a shorter horizon, and it is read
      # AFTER quota deliberately: both mean "the backend is refusing", but only
      # quota names a reset time, so where a frame somehow carries both, the
      # statement that tells the operator WHEN wins. Read from the whole frame
      # for the same reason quota is: the CLI prints its 529 banner into the
      # transcript and then sits at an empty prompt, so the status region alone
      # would never see it. Measured: 163 banner instances over one
      # pane log, classified `awaiting_input` every time, nudged, and failed as
      # `idle` — the class did not exist.
      sig=$(pty_decl_get "$decl" sig.backend_overloaded) || sig=""
      if [ -n "$sig" ] && printf '%s\n' "$f2" | command grep -qE "$sig"; then
        echo backend_overloaded; return 0
      fi
      echo awaiting_input; return 0
    fi
    echo unknown; return 0
  fi
  sig=$(pty_decl_get "$decl" sig.working) || sig=""
  if [ -n "$sig" ] && printf '%s\n' "$f2" | command grep -qE "$sig"; then
    echo working; return 0
  fi
  sig=$(pty_decl_get "$decl" sig.error_retryable) || sig=""
  if [ -n "$sig" ] && printf '%s\n' "$f2" | command grep -qE "$sig"; then
    echo error_retryable; return 0
  fi
  last=$(printf '%s\n' "$f2" | sed -e 's/[[:space:]]*$//' | command grep -v '^$' | tail -1)
  sig=$(pty_decl_get "$decl" sig.awaiting_input) || sig=""
  if [ -n "$sig" ] && printf '%s\n' "$last" | command grep -qE "$sig"; then
    # Same refinement in the legacy last-line domain: idle, and the frame says
    # the backend is what is refusing.
    sig=$(pty_decl_get "$decl" sig.quota_exhausted) || sig=""
    if [ -n "$sig" ] && printf '%s\n' "$f2" | command grep -qE "$sig"; then
      echo quota_exhausted; return 0
    fi
    sig=$(pty_decl_get "$decl" sig.backend_overloaded) || sig=""
    if [ -n "$sig" ] && printf '%s\n' "$f2" | command grep -qE "$sig"; then
      echo backend_overloaded; return 0
    fi
    echo awaiting_input; return 0
  fi
  echo unknown
}

# inject decl session text — the single primitive (nudge AND warm
# re-activation share it; the caller's inject state machine keeps them
# mutually exclusive). Preconditions: two agreeing frames, awaiting_input,
# EMPTY composer — emptiness read from the CURSOR (_pty_composer_empty), never
# from the text alone. rc:
#   0 injected · 1 capture/session failure ·
#   2 operator_interference — text before the cursor AND a writable client
#     attached: a human is demonstrably there (screen on stderr) ·
#   3 refused without a human to name. THREE causes, each printing its own
#     token on stdout (warm caller cold-falls-back, nudge caller skips the
#     episode — neither reads the token, the RECORD does):
#       `frames_disagree`     the two captures differ: the pane is flowing
#       `composer_occupied`   text before the cursor, nobody attached — a hint
#                             or a ghost repaint
#       <the classified state> there is no composer at all; the CLASS is
#                             forwarded, so this token varies by declaration
#     This list said TWO for a while — the frames-disagree branch was
#     missing from the primitive's own contract while returning 3 in
#     production, and it printed `working`, colliding with the classified-state
#     token for a working screen. Both fixed: the enumeration is complete and
#     the three tokens are pairwise distinct, which is what makes a recorded
#     `inject_why=` worth recording.
# The safety invariant is unchanged and absolute: text is injected ONLY into an
# empty composer. rc 2 vs 3 decides what the refusal is CALLED, never whether
# it happens.
pty_inject() {
  local decl=$1 session=$2 text=$3 dumpdir=${4:-} f1 f2 cls comp_re
  comp_re=$(pty_decl_get "$decl" sig.composer_line 2>/dev/null) || comp_re=""
  f1=$(_pty_capture "$session") || return 1
  sleep "$(_pty_settle "$decl")"
  f2=$(_pty_capture "$session") || return 1
  if _pty_frames_disagree "$comp_re" "$f1" "$f2"; then
    # The two captures ARE the evidence, and until this dump they died with the
    # branch: the refusal token says the pane was flowing but never shows HOW,
    # so the two live cases (a pane still painting its own record emit; a pane
    # quiet for 741 s) could not be told apart after the fact — the discriminator
    # may be wrong rather than the wait short, and tuning either needs the frames
    # — dump them "before anyone tunes a settle window". notify-raw's shape: files
    # under the workspace's .runtime, capped, best-effort — a dump that could
    # fail the refusal it explains would be worse than none. LATEST pair wins,
    # same as notify-raw.unparsed.json. Callers without a workspace (probe)
    # pass no dir and get no dump: probe refusals have their own diagnostics.
    if [ -n "$dumpdir" ] && [ -d "$dumpdir" ]; then
      printf '%s' "$f1" | head -c 65536 > "$dumpdir/inject-frames.f1.txt" 2>/dev/null || true
      printf '%s' "$f2" | head -c 65536 > "$dumpdir/inject-frames.f2.txt" 2>/dev/null || true
    fi
    echo frames_disagree; return 3
  fi
  # The composer is the LAST sig.composer_line match — on the live TUI a
  # status footer renders BELOW it, so "last non-empty line" is never the
  # composer (live-measured; that idiom made injection unreachable).
  local ce
  _pty_composer_empty "$decl" "$session" "$f2"; ce=$?
  case $ce in
    0) : ;;                                  # empty: the one state we may inject into
    1)
      # rc 2 asserts a HUMAN, so it is claimed only when one is demonstrably
      # there. With nobody attached the same screen is a rendering artifact
      # (a hint, a ghost repaint) — refuse just as firmly, but as rc 3, which
      # the nudge caller retries past and the warm caller cold-falls-back
      # from, instead of parking the topic on an operator who is not present.
      if _pty_human_attached "$session"; then
        echo "operator_interference: composer line is not empty and a writable client is attached — a human's half-typed text; refusing to fuse input" >&2
        printf '%s\n' "$f2" >&2
        return 2
      fi
      echo composer_occupied
      echo "composer_occupied: text before the cursor with no writable client attached — a rendering artifact, not operator input; refusing this episode" >&2
      return 3 ;;
    *)
      cls=$(pty_classify_screen "$decl" "$session")
      echo "$cls"
      return 3 ;;
  esac
  tmux send-keys -t "=$session:" -l -- "$text" || return 1
  tmux send-keys -t "=$session:" Enter || return 1
  return 0
}

# The rc-3 discriminator, derived in ONE place because four doors need it.
# pty_inject returns 3 for three DIFFERENT refusals and names which one on
# STDOUT — `frames_disagree`, `composer_occupied`, or the
# classified state when there is no composer at all. Every caller discarded that
# line for as long as this primitive has existed, which is exactly why a live
# `inject_rc=3` could never be attributed to any of the three. rc 1 and rc 2 need no discriminator:
# each has one cause, and rc 2 additionally dumps the frame to stderr, which is
# why callers capture STDOUT only — a merged capture would put a whole pane in
# a store row. Output is one space-free token so it can ride a
# whitespace-delimited row, bounded, and never empty: an absent reason reads
# `-`, which is a reading rather than a gap.
pty_inject_why() { # captured-stdout -> one space-free token
  local w=${1:-}
  w=${w%%$'\n'*}
  w=${w//[[:space:]]/_}
  w=${w:0:40}
  printf '%s\n' "${w:--}"
}

# teardown session socket — exact-target kill; FAIL-CLOSED: if the recorded
# socket is gone we refuse rather than start a replacement server to probe.
pty_teardown() {
  local session=$1 socket=$2
  pty_session_name_ok "$session" || return 2
  if [ ! -S "$socket" ]; then
    echo "refuse: recorded tmux socket $socket is gone — fail-closed; will not start a server to prove absence. Inspect manually (tmux -S $socket ls)." >&2
    return 3
  fi
  if ! tmux -S "$socket" has-session -t "=$session" 2>/dev/null; then
    echo "teardown: session $session already gone" >&2
    return 0
  fi
  tmux -S "$socket" kill-session -t "=$session"
}

# reconcile prefix — list live sessions matching prefix (no server = none).
pty_reconcile() {
  tmux list-sessions -F '#{session_name}' 2>/dev/null | command grep -E "^$1" || true
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  set -uo pipefail
  export LC_ALL=C
  case "${1:-}" in
    spawn-cold) shift; pty_spawn_cold "$@" ;;
    alive) shift; pty_alive "$@" ;;
    classify) shift; pty_classify_screen "$@" ;;
    inject) shift; pty_inject "$@" ;;
    teardown) shift; pty_teardown "$@" ;;
    reconcile) shift; pty_reconcile "$@" ;;
    *) echo "usage: pty_tmux.sh spawn-cold <decl> <session> <model> <effort> <ws> <profile> <prompt> <log>" >&2
       echo "       pty_tmux.sh alive <pane_pid> <pane_start> <server_pid> <server_start>" >&2
       echo "       pty_tmux.sh classify <decl> <session>" >&2
       echo "       pty_tmux.sh inject <decl> <session> <text>" >&2
       echo "       pty_tmux.sh teardown <session> <socket>" >&2
       echo "       pty_tmux.sh reconcile <prefix>" >&2
       exit 2 ;;
  esac
fi
