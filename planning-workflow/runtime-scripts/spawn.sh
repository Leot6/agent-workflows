#!/usr/bin/env bash
# spawn.sh — launch one cold instrument, hand it a prompt path, take its
# deliverable off disk, kill the session. This is `{DELIVERY}`'s second form
# (protocol §5.1) made executable; the first form — an instrument that returns
# its deliverable as text — needs nothing here, which is why a sub-agent
# dispatch and a human forwarding a prompt by hand both work with this file
# absent. Unlike `self-check/`, which runs only between rounds on the tree
# itself, this runs DURING a topic.
#
# THE CONTRACT IT SATISFIES. An instrument is one-shot: handed one message
# naming a prompt file, it delivers once. It never resumes, is never
# interrupted, never needs to be spoken to mid-turn. That is what keeps this
# small — a driver for a long-running agent needs a closed set of screen
# signatures because it must know when it is safe to interrupt; this needs one
# signature, and only to know when it may begin.
#
# ADDING A CLI is adding `backends/<name>.kv` with six keys: cmd.launch,
# model, effort, composer, settle, modal_max. No code changes; nothing here
# branches on a backend's name. `composer` has no default on purpose — a CLI
# whose prompt this file guessed wrong would fail by hanging, and a missing
# key fails by refusing. `backends/lens-backends.map` binds each instrument to
# a declaration, optionally with a per-lens model/effort overriding the
# declaration's own; changing a line there changes that lens's CLI, model
# family, or model.
#
# THE CALLER OWNS THE DEADLINE. `collect` is stateless on purpose — it answers
# about now, never about how long — so whoever gives up must call `pane`,
# which is the only path that both records the attempt and tears the session
# down. Forgetting it leaks a session; measured, on this file's own first
# regression run.
#
# WHY A SENTINEL AND NOT SCREEN CLASSIFICATION. Driving a TUI normally costs a
# closed set of screen signatures (working / awaiting-input / error / modal /
# quota) because a long-running agent needs mid-turn intervention — you must
# know when it is safe to speak. A one-shot instrument never needs that: it is
# sent one message and read once. So completion is signalled by the instrument
# itself, and every failure — crash, quota, hang, a modal nobody declared —
# collapses into one path: the sentinel never appears. That is a strictly safer
# classifier than a screen regex, because it cannot mistake an idle prompt for
# a finished turn.
#
# TWO TARGET SYNTAXES, measured on tmux 3.0a: a PANE target needs the trailing
# colon ('=name:') and a SESSION target must not have it ('=name'). Without the
# colon send-keys fails with "can't find pane" and, on the first version of
# this file, left the session running because the error path did not tear down.
# Both halves are why teardown here is fail-closed on every exit.
#
# ORDER MATTERS: the instrument writes the deliverable, THEN the sentinel. The
# sentinel's existence is the atomicity marker; a half-written deliverable has
# none. A deliverable written without its sentinel times out — a false failure,
# which is the safe direction, and re-spawn already covers it.
set -uo pipefail

: "${SPAWN_BACKENDS:=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/backends}"
: "${SPAWN_TIMEOUT:=1800}"         # seconds before the attempt is called failed
: "${SPAWN_POLL:=5}"               # seconds between sentinel checks
: "${SPAWN_SETTLE:=6}"             # seconds to let the TUI paint before typing
: "${SPAWN_TOPIC:=}" ; : "${SPAWN_CHECKOUT:=}" ; : "${SPAWN_SCRATCH:=/tmp}"
: "${SPAWN_MODAL_MAX:=3}"           # bounded Enters for whatever stands in front of it

die() { printf 'spawn: %s\n' "$*" >&2; exit 2; }

# tmux targets are addressed '=<name>' everywhere: a ':' or a glob inside a
# name can redirect a target at kill time, which is how you kill the wrong
# session. Refuse the charset rather than quote around it.
name_ok() { case $1 in *[!A-Za-z0-9_-]*|'') return 1 ;; esac; }

# A backend is a six-key declaration, never a branch on its name: cmd.launch,
# model, effort, composer, settle, modal_max. The composer prompt is PER
# BACKEND — a different CLI draws a different one, and this is the whole of
# the screen reading, so hard-coding it would silently bind the launcher to
# one CLI. Adding a CLI is adding a file; this script never learns its name.
bk() { sed -n "s|^$2=||p" "$SPAWN_BACKENDS/$1.kv" | head -1; }
# subst <template> <model> <effort> — the model/effort placeholders resolve to
# the launch's resolved values (see resolve), the dir placeholders to the
# operator's env. Values are slugs by construction (kv keys, map columns), so
# no sed-metacharacter defense is owed here.
subst() { printf '%s' "$1" | sed -e "s|{model}|$2|g" -e "s|{effort}|$3|g" -e "s|{topic}|$SPAWN_TOPIC|g" -e "s|{checkout}|$SPAWN_CHECKOUT|g" -e "s|{scratch}|$SPAWN_SCRATCH|g"; }

# resolve <lens-or-backend> — a lens-backends.map hit binds the instrument to
# a declaration plus an optional per-lens model/effort; anything else must
# name a declaration directly (probes, ad-hoc dispatches) and takes that
# declaration's own model=/effort=. Address resolution only: what the CLI does
# still comes from the declaration file alone.
resolve() { # sets _R_BACKEND _R_MODEL _R_EFFORT; rc 1 names neither
  local line
  line=$(sed -n "s|^$1=||p" "$SPAWN_BACKENDS/lens-backends.map" 2>/dev/null | head -1)
  if [ -n "$line" ]; then
    set -- $line                 # <backend> [<model> [<effort>]]
    _R_BACKEND=$1; _R_MODEL=${2:-}; _R_EFFORT=${3:-}
  elif [ -f "$SPAWN_BACKENDS/$1.kv" ]; then
    _R_BACKEND=$1; _R_MODEL=; _R_EFFORT=
  else
    return 1
  fi
}

launch() { # <lens-or-backend> <session-name> <ABS prompt path> <ABS out path> — returns as soon as the message is sent
  local arg=$1 name=$2 prompt=$3 out=$4 backend model effort cli composer settle modal_max raw
  resolve "$arg" || die "'$arg' is neither an instrument in lens-backends.map nor a backend declaration"
  backend=$_R_BACKEND
  [ -f "$SPAWN_BACKENDS/$backend.kv" ] || die "no backend declaration: $backend.kv"
  raw=$(bk "$backend" cmd.launch);             [ -n "$raw" ]   || die "$backend.kv has no cmd.launch"
  # model/effort precedence: the map line's per-lens values, else the
  # declaration's own keys. A placeholder that resolves to nothing on either
  # side REFUSES — an empty --model hands the vehicle back to the CLI's
  # default-of-the-week, the exact outcome the explicit-model rule exists to
  # stop, and sed would otherwise substitute that emptiness silently.
  model=${_R_MODEL:-$(bk "$backend" model)}
  effort=${_R_EFFORT:-$(bk "$backend" effort)}
  case $raw in *'{model}'*)  [ -n "$model" ]  || die "$backend.kv's {model} resolves nowhere — no map value, no model= key";; esac
  case $raw in *'{effort}'*) [ -n "$effort" ] || die "$backend.kv's {effort} resolves nowhere — no map value, no effort= key";; esac
  cli=$(subst "$raw" "$model" "$effort")
  composer=$(bk "$backend" composer);          [ -n "$composer" ] || die "$backend.kv has no composer"
  settle=$(bk "$backend" settle); settle=${settle:-6}
  modal_max=$(bk "$backend" modal_max); modal_max=${modal_max:-3}
  name_ok "$name"        || die "session name '$name' outside [A-Za-z0-9_-]"
  [ -f "$prompt" ]       || die "prompt not found: $prompt"
  [ -e "$out" ]          && die "refusing to overwrite an existing deliverable: $out"
  rm -f "$out.done" "$out.pane"

  local msg="Read $prompt, execute it fully. Do not summarize back."

  # ONE argument, never a word-split list. Measured on tmux 3.0a: a
  # multi-word launch is passed to the pane as VERBATIM argv — no shell ever
  # parses it — so quoting written in a declaration (claude.kv's
  # --model "{model}", where a [1M] tier suffix is a glob class the pane's
  # shell must not glob) arrived at the CLI as literal quote characters. As a
  # single string the pane's shell parses the line and a declaration's
  # quoting means what it says — the same semantics delivery's adapter runs
  # the twin declarations under, which their cross-references promise.
  tmux new-session -d -s "$name" -x 220 -y 50 "$cli" 2>/dev/null \
    || die "tmux launch failed for '$name'"

  # WAIT UNTIL IT CAN BE TYPED INTO, rather than typing blind. Blind input is
  # order-dependent: measured on a faithful mock, one Enter too many submitted
  # an empty turn BEFORE the message was typed, and the message then arrived
  # after the reader had moved on. So one signature — the composer prompt —
  # read only at launch, with bounded Enters for whatever stands in front of
  # it (trust dialog, self-update notice; both take Enter for their default).
  # This is the whole of the screen reading: a long-running agent needs a
  # closed signature SET because it must know when it is safe to interrupt; a
  # one-shot instrument only needs to know when it may begin.
  sleep "$settle"
  local tries=0 pane=""
  while [ "$tries" -lt "$modal_max" ]; do
    # Search the WHOLE frame, not its last line. Measured on the real CLIs: the
    # bottom of the pane is a status footer (context meter, mode line), and the
    # composer sits ABOVE it — a tail-based probe reads the footer and every
    # launch fails its own readiness check. A mock whose composer happens to be
    # last hides this exactly.
    pane=$(tmux capture-pane -p -t "=$name:" 2>/dev/null)
    printf '%s' "$pane" | grep -qF "$composer" && break
    tmux send-keys -t "=$name:" Enter 2>/dev/null
    tries=$((tries + 1)); sleep "$settle"
  done
  printf '%s' "$pane" | grep -qF "$composer" \
    || { tmux capture-pane -p -S - -t "=$name:" > "$out.pane" 2>/dev/null
         tmux kill-session -t "=$name" 2>/dev/null
         die "no composer after $tries clears; pane in $out.pane"; }

  # -l is literal (no key-name interpretation) and -- ends option parsing, so a
  # message beginning with '-' cannot become a flag. Text and Enter are sent
  # separately: a trailing newline inside -l is not a submit in every build.
  tmux send-keys -t "=$name:" -l -- "$msg" 2>/dev/null \
    || { tmux kill-session -t "=$name" 2>/dev/null; die "send failed for '$name'"; }
  sleep 1
  tmux send-keys -t "=$name:" Enter 2>/dev/null

  printf 'launched %s -> %s\n' "$name" "$out"
  return 0
}

# collect <session-name> <ABS out path> — non-blocking, safe to call repeatedly.
#   0 = deliverable ready · 10 = still running · 1 = failed (pane/partial kept)
# Split from launch because the caller's own command timeout is far shorter
# than a review turn, and because a detached session outlives the author: an
# author restart mid-round loses nothing, which a sub-agent dispatch cannot
# say. Parallel dispatch falls out of the same split — launch every lens, then
# collect them.
collect() {
  local name=$1 out=$2
  if [ -f "$out.done" ]; then
    tmux kill-session -t "=$name" 2>/dev/null; return 0
  fi
  if tmux has-session -t "=$name" 2>/dev/null; then
    return 10
  fi
  # Gone without a sentinel: keep whatever it did leave — a partial deliverable
  # if there is one, the pane if the session is still capturable, nothing if
  # neither. §4.5.3 persists whichever exists; nothing an instrument produced
  # is discarded by this step.
  printf 'collect: %s ended without its sentinel\n' "$name" >&2
  return 1
}

# status [<scratch dir>] — what a human needs to see: is this moving, and if
# not, why. Deliberately not a classifier — it prints the pane's own last line
# and lets the reader judge, because the failure worth catching (a declaration
# whose composer moved under a CLI update) looks like a timeout to any rule and
# like an untouched prompt to a person. Recovery is not this file's job: the
# returned-text delivery form needs no launcher at all, so a stale declaration
# costs one manual dispatch, not a round.
status() {
  local scratch=${1:-}
  # A WINDOW, not a line. The bottom of a TUI frame is a mode footer whose text
  # never changes, so `tail -1` reports the same string whether the instrument
  # is working, finished, or was never typed into — measured, and the second
  # time this file made the single-line mistake. The last few lines carry what
  # a person actually reads: the context meter (it grows only if the instrument
  # worked), the composer, and any interrupt hint.
  local n c age frame pat q
  tmux ls -F '#{session_name} #{session_created}' 2>/dev/null | while read -r n c; do
    age=$(( $(date +%s) - c ))
    printf '%s  (%dm%02ds)\n' "$n" $((age/60)) $((age%60))
    frame=$(tmux capture-pane -p -t "=$n:" 2>/dev/null)
    # The one state a reader cannot see: an exhausted quota leaves the composer
    # looking idle, identical to a message that never went in — and the two want
    # opposite responses (wait for a reset vs fix a declaration and re-dispatch).
    # Every declared pattern is tried against every pane: which backend a
    # session used is not recorded anywhere, and the literals are distinctive
    # enough that a cross-match is cheaper than the state file avoiding it.
    for q in "$SPAWN_BACKENDS"/*.kv; do
      [ -e "$q" ] || continue
      pat=$(sed -n 's|^quota=||p' "$q" | head -1)
      [ -n "$pat" ] || continue
      printf '%s' "$frame" | grep -qE "$pat" && {
        printf '    ! QUOTA — this pane reports exhausted quota; waiting is the only cure, re-spawning is not\n'
        break
      }
    done
    printf '%s' "$frame" | grep -v '^[[:space:]]*$' \
      | tail -"${SPAWN_STATUS_LINES:-4}" | cut -c1-76 | sed 's/^/    │ /'
  done
  [ -n "$scratch" ] && [ -d "$scratch" ] && {
    printf '\n%-42s %8s  %s\n' 'FILE (scratch)' SIZE MARKED
    find "$scratch" -maxdepth 2 -name '*.md' 2>/dev/null | while read -r f; do
      printf '%-42s %8s  %s\n' "${f#"$scratch"/}" "$(wc -c < "$f")" \
        "$([ -f "$f.done" ] && echo yes || echo '—')"
    done
  }
  return 0
}

# pane <session-name> <ABS out path> — capture for the failure record while the
# session is still alive. Call before teardown on a timeout decision.
pane() {
  tmux capture-pane -p -S - -t "=$1:" > "$2.pane" 2>/dev/null
  tmux kill-session -t "=$1" 2>/dev/null
}

case "${1:-}" in
  launch)  shift; [ $# -eq 4 ] || die "usage: spawn.sh launch <lens-or-backend> <name> <ABS prompt> <ABS out>"; launch "$@" ;;
  collect) shift; [ $# -eq 2 ] || die "usage: spawn.sh collect <name> <ABS out>"; collect "$@" ;;
  pane)    shift; [ $# -eq 2 ] || die "usage: spawn.sh pane <name> <ABS out>"; pane "$@" ;;
  status)  shift; status "${1:-}" ;;
  *)       die "usage: spawn.sh {launch|collect|pane|status} ..." ;;
esac
