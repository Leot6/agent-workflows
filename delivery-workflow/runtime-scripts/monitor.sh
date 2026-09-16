#!/usr/bin/env bash
# monitor.sh — read-only terminal renderer (config-and-adapters.md §6).
# Reads the store ONLY: no capture-pane (cannot perturb), writes nothing, no
# control channel (the operator's control surface is launch.sh, by design).
# Pane text reaches humans via .runtime/logs/ and the halt surface's attached
# screen text. Loop 2s; --once for scripting.
#
# It is a PANEL, not a dump: the store's surfaces are kv soup, and a human
# scanning them wants four answers in a fixed place — do I need to act, where
# is it, how much runway, what just happened. So the frame is a glyph headline
# (the state that wants your eyes) over an aligned label column, sectioned by
# rules, with the ledger columnised. Every layout rule below is load-bearing:
#
#   FIXED WIDTH 74, never the terminal's. A captured --once must not vary with
#   who captured it (a fixture's bytes would depend on the capturing shell).
#   COLOR ONLY ON A TTY (and off under --no-color / NO_COLOR): `launch.sh
#   status` pipes this, and escape bytes in a pipe are noise, not emphasis.
#   MINUTE-COARSE durations and a minute-precision clock, so a quiet stage
#   renders the SAME BYTES between rollovers — which is what makes the
#   diff-gated repaint below able to leave the screen alone.
#   IN-PLACE REPAINT on change only (cursor-home + erase-to-EOL per line +
#   erase-below), never a blank-and-refill: a 2s clear-and-redraw flickers,
#   and a panel you flinch away from is a panel you stop reading.

set -uo pipefail
export LC_ALL=C
MON_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
. "$MON_DIR/lib/state.sh"
. "$MON_DIR/lib/config.sh"

usage() { echo "usage: monitor.sh <workspace> [--once] [--no-color]" >&2; exit 2; }
[ $# -ge 1 ] || usage
WS=$(cd "$1" 2>/dev/null && pwd) || { echo "monitor: workspace $1 not a directory" >&2; exit 2; }
shift
ONCE=0 NOCOLOR=0
while [ $# -gt 0 ]; do
  case "$1" in
    --once) ONCE=1; shift ;;
    --no-color) NOCOLOR=1; shift ;;
    *) usage ;;
  esac
done
WIDTH=74
USE_COLOR=1
{ [ "$NOCOLOR" -eq 1 ] || [ -n "${NO_COLOR:-}" ] || [ ! -t 1 ]; } && USE_COLOR=0

# ------------------------------------------------------------- primitives ---
paint() { # ansi text
  if [ "$USE_COLOR" -eq 1 ]; then printf '\033[%sm%s\033[0m' "$1" "$2"; else printf '%s' "$2"; fi
}
rule() { paint 2 "$(printf '%*s' "$WIDTH" '' | tr ' ' '-')"; printf '\n'; }
# section separator: a rule only when the section above DREW a row — so an
# absent section (no sessions over a park, a suppressed runway) never leaves a
# doubled rule. Reads render()'s `drew` via bash dynamic scope. Plain mode
# strips colour, so a captured frame gains only 74-dash lines (still bytes
# the fixtures grep for substrings, never line-count above them).
sep() { [ "${drew:-0}" -eq 1 ] && { rule; drew=0; } }
# label row: one aligned column so the eye reads down the values, not across.
# Values come from the store, where a field can end in blanks (a kv body's
# joined tail, an empty detail) — trimmed here, once, rather than at each site.
row() { # label value...
  local l=$1; shift
  # labels are muted chrome (mockup --label): the eye goes to the value, where
  # the category colour lives. Plain mode ignores the code, so the captured
  # frame's bytes never change.
  rtrim "$(printf '  %s %s' "$(paint 2 "$(printf '%-9s' "$l")")" "$*")"
}
# Display width: paint's escape bytes and a glyph's UTF-8 continuation bytes are
# both invisible on screen, and `${#s}` counts neither correctly under LC_ALL=C —
# so column arithmetic asks this, never the string length.
dwidth() { # text -> columns
  printf '%s' "$1" | sed 's/\x1b\[[0-9;]*m//g' \
    | awk '{ s=$0; n=gsub(/[\200-\277]/,"",s); w += length($0) - n } END { print w+0 }'
}
# left/right on one line. Each half arrives already painted. An empty right
# half prints no padding at all — trailing blanks are invisible on screen but
# not in a capture, and a frame is diffed byte-for-byte before it repaints.
lr() { # left right
  local pad
  [ -z "$2" ] && { printf '%s\n' "$1"; return 0; }
  pad=$((WIDTH - $(dwidth "$1") - $(dwidth "$2")))
  [ "$pad" -lt 1 ] && pad=1
  printf '%s%*s%s\n' "$1" "$pad" '' "$2"
}
# Trailing-blank trim, for the same reason (bash-only, no fork per row).
rtrim() { local s=$1; printf '%s\n' "${s%"${s##*[![:space:]]}"}"; }

surface() { # name -> body, or markers ABSENT / FAULT (fault ≠ absent, shown as such)
  local body rc
  body=$(state_get "$WS" "$1" 2>/dev/null); rc=$?
  case $rc in
    0) printf '%s\n' "$body" ;;
    1) echo "__ABSENT__" ;;
    3) echo "__FAULT__" ;;
  esac
}

kv() { printf '%s\n' "$1" | awk -F= -v k="$2" '$1==k{v=substr($0,length(k)+2)} END{print v}'; }

# Compact duration: 45s / 13m / 1h12m / 2d3h. Minute-coarse above a minute, so
# a stable stage holds a byte-identical frame between rollovers.
fmt_dur() { # seconds
  local s=$1
  case "$s" in ''|*[!0-9]*) printf '?'; return ;; esac
  if   [ "$s" -lt 60 ];    then printf '%ds' "$s"
  elif [ "$s" -lt 3600 ];  then printf '%dm' "$((s / 60))"
  elif [ "$s" -lt 86400 ]; then printf '%dh%02dm' "$((s / 3600))" "$(((s % 3600) / 60))"
  else                          printf '%dd%dh' "$((s / 86400))" "$(((s % 86400) / 3600))"
  fi
}

# Every "→ N left" on this panel must name a criterion that actually fires when
# it reaches zero — so the limit is named, not called "budget" generically.
headroom() { # elapsed limit [noun]
  local n=${3:-budget}
  if [ -z "$2" ]; then printf '%s (no %s)' "$(fmt_dur "$1")" "$n"
  else printf '%s / %s %s → %s left' "$(fmt_dur "$1")" "$n" "$(fmt_dur "$2")" \
         "$(fmt_dur $(($2 - $1 > 0 ? $2 - $1 : 0)))"; fi
}

# First n display cells of a line. Deliberately a second copy of the adapter's
# _pty_cells: the renderer must not depend on a backend to lay out a line.
cells() { # n line
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

# Ledger records are kv soup; the panel lifts the four fields every record
# shares into columns (time · event · slice/stage) and lets the rest follow
# verbatim, so a column of like things reads down. The schema version `v=` is
# elided — it addresses the parser, not the operator, and the raw record is one
# `state_get ledger` away. A record whose t= is missing or unusable is printed
# VERBATIM: a renderer must not drop the line it cannot read.
led_render() { # record -> "MM-DD HH:MM:SS  event  slice stage  rest"
  local -a toks rest=()
  local tok t="" ev="" sl="" st="" h
  read -ra toks <<< "$1"
  for tok in "${toks[@]}"; do
    case "$tok" in
      t=*)     if [ -z "$t" ];  then t=${tok#t=};      continue; fi ;;
      event=*) if [ -z "$ev" ]; then ev=${tok#event=}; continue; fi ;;
      slice=*) if [ -z "$sl" ]; then sl=${tok#slice=}; continue; fi ;;
      stage=*) if [ -z "$st" ]; then st=${tok#stage=}; continue; fi ;;
      v=*)     continue ;;
    esac
    rest+=("$tok")
  done
  case "$t" in ''|*[!0-9]*) printf '  %s\n' "$1"; return 0 ;; esac
  h=$(date -d "@$t" '+%m-%d %H:%M:%S' 2>/dev/null) || { printf '  %s\n' "$1"; return 0; }
  local out
  out=$(rtrim "$(printf '  %s  %-13s %-17s %s' "$h" "$ev" "$sl${st:+ $st}" "${rest[*]}")")
  if [ "$(dwidth "$out")" -gt "$WIDTH" ]; then
    printf '%s…\n' "$(cells $((WIDTH - 1)) "$out")"
  else
    printf '%s\n' "$out"
  fi
}

# ----------------------------------------------------------------- blocks ---
render() {
  local now run stage halt notifyb final wd sl st drew=0
  now=$(date +%s)
  run=$(surface run); stage=$(surface stage); halt=$(surface halt); notifyb=$(surface notify)
  # kv parsing must stop at a legacy inline-screen fence: free text after it
  # could otherwise override real fields in the last-match reader above.
  case "$halt" in __ABSENT__|__FAULT__) : ;; *)
    halt=$(printf '%s\n' "$halt" | awk '/^--- screen ---$/{exit} {print}') ;;
  esac
  final=$(cat "$WS/.runtime/final-state" 2>/dev/null || true)
  wd=$(cat "$WS/.runtime/watchdog.pid" 2>/dev/null || true)
  local wd_alive=0
  [ -n "$wd" ] && kill -0 "$wd" 2>/dev/null && wd_alive=1
  sl=""; st=""
  case "$stage" in __ABSENT__|__FAULT__) : ;; *) sl=$(kv "$stage" slice); st=$(kv "$stage" stage) ;; esac

  # ---- headline: the one state that wants the operator's eyes
  # The classification is computed ONCE, as a token, because two consumers need
  # it: the painted headline below, and the machine line --once prints for the
  # status poll (a second copy of the predicate would be the drift shape this
  # tree measures most often). Closed set, documented where the poll reads about
  # it (launch.sh's verb table): NOT_STARTED | RUNNING | BETWEEN_STAGES |
  # PARKED | COMPLETE | BROKEN | STORE_FAULT.
  local parked=0
  case "$halt" in
    __ABSENT__|__FAULT__) : ;;
    *) [ "$(kv "$halt" resolved)" = "1" ] || parked=1 ;;
  esac
  local stok="" sreason=""
  if [ "$parked" -eq 1 ]; then stok=PARKED; sreason=$(kv "$halt" reason)
  elif [ "$halt" = "__FAULT__" ]; then stok=STORE_FAULT
  else
    case "${final%% *}" in
      class=complete) stok=COMPLETE ;;
      class=broken)   stok=BROKEN ;;
      *)
        case "$run" in
          __ABSENT__) stok=NOT_STARTED ;;
          __FAULT__)  stok=STORE_FAULT ;;
          *)
            if [ "$(kv "$stage" state)" = "running" ]; then stok=RUNNING
            elif [ -n "$st" ]; then stok=BETWEEN_STAGES
            else stok=NOT_STARTED ; fi ;;
        esac ;;
    esac
  fi
  # The machine line, --once only: `launch.sh status` is this render, and a poll
  # keying on it must not scrape painted text. It also carries the one quality
  # number no live surface held (measured: 26 gate refusals over twelve hours while every operator-facing surface read
  # flawless — refusals are absorbed in-session by design, so the loop never
  # escalates and the panel is a LIVENESS instrument that cannot move on
  # quality). Absent gates surface is named, never zero: absent is not zero.
  if [ "$ONCE" -eq 1 ]; then
    local gfail=absent gtot=0 gsur grc
    gsur=$(state_get "$WS" gates 2>/dev/null); grc=$?
    if [ $grc -eq 0 ]; then
      # grep -c exits 1 on zero hits — captured, never chained: a && chain here
      # would read an empty-but-present surface as absent (pipefail's own trap).
      gtot=$(printf '%s\n' "$gsur" | command grep -c 'result=' || true)
      gfail=$(printf '%s\n' "$gsur" | command grep -c 'result=FAIL' || true)
    elif [ $grc -eq 3 ]; then
      gfail=fault
    fi
    printf 'state=%s%s gate_fails=%s attestations=%s\n' "$stok" \
      "${sreason:+ reason=$sreason}" "$gfail" "$gtot"
  fi

  # ---- header
  local topic
  case "$run" in __ABSENT__|__FAULT__) topic=$(basename "$(dirname "$WS")") ;; *) topic=$(kv "$run" topic) ;; esac
  local live=""; [ "$ONCE" -eq 0 ] && live="⟳2s · "
  lr "$(paint 1 "delivery · ${topic:-?}")" "$(paint 2 "read-only · ${live}$(date '+%m-%d %H:%M')")"
  local wsp=$WS
  [ -n "${HOME:-}" ] && wsp="${WS/#$HOME/~}"      # the path is the disambiguator when two panels are open; shorten, never drop
  printf '%s\n' "$(paint 2 "  $wsp")"
  rule
  drew=1   # the header block always draws; the headline below keeps it set


  if [ "$stok" = "PARKED" ]; then
    local hage="" ht
    # a hand-edited/absent t must not reach the arithmetic (the same numeric
    # guard led_render applies to a record's own timestamp)
    ht=$(kv "$halt" t)
    case "$ht" in ''|*[!0-9]*) : ;; *) hage="$(fmt_dur $((now - ht))) ago" ;; esac
    lr "$(paint '1;33' '⏸ PARKED — needs you')" "$(paint 2 "$hage")"
  elif [ "$stok" = "STORE_FAULT" ]; then
    # One token, two surfaces: the poll reads state=STORE_FAULT either way, but
    # the panel NAMES the surface that faulted — a corrupt run surface painted
    # with the halt-surface sentence names the wrong surface (the regression the
    # token refactor introduced and an independent audit caught; the pre-refactor
    # texts are restored verbatim, halt first because that is the branch order
    # that minted the token).
    if [ "$halt" = "__FAULT__" ]; then
      printf '%s\n' "$(paint '1;31' '✗ STORE FAULT in the halt surface — a park may be hidden')"
    else
      printf '%s\n' "$(paint '1;31' '✗ STORE FAULT — the run surface is corrupt; do not treat as absent')"
    fi
  else
    case "$stok" in
      COMPLETE)      printf '%s\n' "$(paint '1;32' '✓ COMPLETE — topic done')" ;;
      BROKEN)        printf '%s\n' "$(paint '1;31' '✗ CIRCUIT-BROKEN — needs you')" ;;
      NOT_STARTED)   if [ "$run" = "__ABSENT__" ]; then
                       printf '%s\n' "$(paint 2 '○ NOT STARTED — launch.sh launch <workspace>')"
                     else
                       printf '%s\n' "$(paint 2 '○ no stage yet')"
                     fi ;;
      RUNNING)       printf '%s\n' "$(paint '1;32' '▶ RUNNING')$(paint 2 " — slice ${sl:-?} · ${st:-?} · round $(kv "$stage" round) · attempt $(kv "$stage" attempt)")" ;;
      BETWEEN_STAGES) printf '%s\n' "$(paint '1;32' '▶ BETWEEN STAGES')$(paint 2 " — last: slice ${sl:-?} · ${st} ($(kv "$stage" state))")" ;;
      *)             printf '%s\n' "$(paint 2 '○ no stage yet')" ;;
    esac
  fi

  # ---- the park's own fields, directly under the headline it belongs to
  if [ "$parked" -eq 1 ]; then
    row reason "$(kv "$halt" reason) · slice $(kv "$halt" slice) · $(kv "$halt" stage)"
    # Detail density: a class_u dump can run 1000+ chars and bury the ledger.
    # Short details render in full; a long one shows its first ~2 panel lines
    # plus a pointer — the full text is one `launch.sh status --halt` away.
    # (It pointed at `status --once` for five slices: status has no such
    # argument, and monitor.sh --once renders this same truncated frame.)
    local dtl dcap
    dtl=$(kv "$halt" detail)
    dcap=$(( 2 * (WIDTH - 12) ))
    if [ "$(dwidth "$dtl")" -le "$dcap" ]; then
      row detail "$dtl"
    else
      local d1 d2
      d1=$(cells $((WIDTH - 12)) "$dtl")
      d2=$(cells $((WIDTH - 13)) "${dtl#"$d1"}")
      row detail "$d1"
      printf '  %-9s %s…\n' "" "$d2"
      printf '  %-9s %s\n' "" "$(paint 2 "▸ full text ${#dtl} chars: launch.sh status <workspace> --halt  (halt surface)")"
    fi
    local sfile
    sfile=$(kv "$halt" screen_file)
    if [ -n "$sfile" ] && [ -f "$sfile" ]; then
      local first=1
      while IFS= read -r sline; do
        if [ "$first" -eq 1 ]; then row screen "| $sline"; first=0
        else printf '  %-9s | %s\n' "" "$sline"; fi
      done < <(tail -6 "$sfile")
    fi
    case "$(kv "$halt" reason)" in
      class_u|blocked|disagreement) row next "launch.sh rule <workspace> --slice $(kv "$halt" slice) --text '...'" ;;
      push_gate) row next "review the ledger and push (the workflow never pushes)" ;;
      *) row next "fix the named cause, then: launch.sh launch <workspace>" ;;
    esac
  fi

  # ---- position: binding is shown in every state (which checkout is a fact
  # about the slice, not about whether it is currently running)
  if [ -n "$sl" ]; then
    local bk br bb
    if bk=$(binding_kind "$WS" "$sl" 2>/dev/null); then
      br=$(binding_repo "$WS" "$sl" 2>/dev/null); bb=$(binding_branch "$WS" "$sl" 2>/dev/null)
      row binding "$bk · ${br:-(unresolved)} @ ${bb:-(unresolved)}"
    else
      row binding "$(paint '1;31' 'STORE FAULT') — the slices index is unreadable; which checkout this slice belongs to cannot be resolved"
    fi
  fi
  sep
  # ---- topic geography: slice bar + the current position's stage bar.
  # The stage-bar "done" mark comes from the LEDGER's advance events, never
  # the attempts surface: round.<s>.<st> means ENTERED (a parked stage would
  # misrender as done), while do_advance writes `advance` only after every
  # park path has exited — advance strictly means "stage passed".
  local slicesb
  slicesb=$(surface slices)
  case "$slicesb" in
    __ABSENT__) : ;;   # pre-split: omit, like commits
    __FAULT__) row slices "$(paint '1;31' 'STORE FAULT') — the slices index is unreadable"; drew=1 ;;
    *)
      local sbar
      # id order for the eye (2-digit ids sort lexicographically); the store's
      # own order is ingest order, which scatters superseded rows
      sbar=$(printf '%s\n' "$slicesb" | sort | awk -v uc="$USE_COLOR" '
        function pc(code, text) { return (uc ? "\033[" code "m" text "\033[0m" : text) }
        {
          id=""; s=""
          for (i=1; i<=NF; i++) {
            if ($i ~ /^id=/) id=substr($i, 4)
            else if ($i ~ /^status=/) s=substr($i, 8)
          }
          if (id == "") next
          # the segment — id+glyph — carries the status hue (mockup: done green,
          # active cyan, pending/superseded muted, cancelled red).
          g="?"; seg=id g
          if (s=="done")            { g="✓"; done++; seg=pc("32", id g) }
          else if (s=="active")     { g="▶"; act++;  seg=pc("36", id g) }
          else if (s=="pending")    { g="○"; pend++; seg=pc("2",  id g) }
          else if (s=="cancelled")  { g="✗"; canc++; seg=pc("31", id g) }
          else if (s=="superseded") { g="‒"; sup++;  seg=pc("2",  id g) }
          out = out (out=="" ? "" : " ") seg
        }
        END {
          c=""
          if (done) c = c (c=="" ? "" : " · ") done " done"
          if (act)  c = c (c=="" ? "" : " · ") act " active"
          if (pend) c = c (c=="" ? "" : " · ") pend " pending"
          if (canc) c = c (c=="" ? "" : " · ") canc " cancelled"
          if (sup)  c = c (c=="" ? "" : " · ") sup " superseded"
          if (out != "") printf "%s  %s\n", out, pc("2", "(" c ")")
        }')
      [ -n "$sbar" ] && { row slices "$sbar"; drew=1; } ;;
  esac
  if [ -n "$st" ]; then
    local tsv="$CONFIG_WORKFLOW_ROOT/config/stages.tsv" scope bsl adv ledb stbar
    scope=$(awk -F'\t' -v s="$st" '$0 !~ /^#/ && $1==s {print $2; exit}' "$tsv" 2>/dev/null)
    if [ -n "$scope" ]; then
      bsl=$sl; [ "$scope" = "topic" ] && bsl=00
      adv=""
      ledb=$(surface ledger)
      case "$ledb" in __ABSENT__|__FAULT__) : ;; *)
        adv=$(printf '%s\n' "$ledb" | command grep -E '(^| )event=advance( |$)' \
              | command grep -E "(^| )slice=$bsl( |$)" \
              | command grep -oE '(^| )stage=[^ ]+' | sed 's/^ *stage=//' | sort -u) ;;
      esac
      stbar=$(awk -F'\t' -v scope="$scope" -v cur="$st" \
                  -v adv=" $(printf '%s' "$adv" | tr '\n' ' ') " -v uc="$USE_COLOR" '
        function pc(code, text) { return (uc ? "\033[" code "m" text "\033[0m" : text) }
        $0 ~ /^#/ { next }
        $2 == scope {
          seg=pc("2", $1 "○")
          if (index(adv, " " $1 " ")) seg=pc("32", $1 "✓")
          if ($1 == cur) seg=pc("36", $1 "▶")
          out = out (out=="" ? "" : " ") seg
        } END { print out }' "$tsv" 2>/dev/null)
      [ -n "$stbar" ] && { row stages "$stbar"; drew=1; }
    fi
  fi
  sep
  local sess srow snonce
  sess=$(surface sessions)
  srow=""; snonce=""
  case "$sess" in
    __ABSENT__|__FAULT__) sess="" ;;
    *)
      snonce=$(kv "$stage" nonce)
      # bound by NONCE, not by role: the active session is the one whose row
      # carries the stage surface's nonce; every other row is held (or dead)
      [ -n "$snonce" ] && srow=$(printf '%s\n' "$sess" | command grep -E "(^| )nonce=$snonce( |$)" | tail -1) ;;
  esac
  if [ -n "$srow" ] && [ -n "$st" ]; then
    drew=1   # the sessions block always names the agent row when it runs
    # One walk over the sessions surface builds the census and the attach
    # block. Held-row liveness is a cheap `kill -0` HINT (no starttime match,
    # so pid reuse can fool it; the ferry's pty_alive stays the authority) —
    # its one job is to withhold the attach command for a torn-down pane. The
    # dead claim needs positive evidence: a recorded pid that no longer runs.
    local -a A_MARK=() A_ID=() A_TAG=() A_CMD=()
    local n_work=0 n_held=0 n_dead=0 wid=0 wtag=0
    local line2 f2 rl nm md pp sock2 short mark tag cmd pfx="delivery-${topic:-}-"
    while IFS= read -r line2; do
      [ -n "$line2" ] || continue
      f2=$(printf '%s\n' "$line2" | tr ' ' '\n')
      rl=$(kv "$f2" role); nm=$(kv "$f2" name); md=$(kv "$f2" mode)
      pp=$(kv "$f2" pane_pid); sock2=$(kv "$f2" socket)
      short=${nm#"$pfx"}
      tag="($rl·$md)"
      # The ferry writes a PENDING row (socket=pending, pane_pid=0) before the
      # spawn returns; printing an attach command for it hands the operator a
      # line that cannot work. Exact-match target ('=name', quoted so zsh does
      # not take it for equals-expansion) — the tmux rule this tree paid for.
      case "$sock2" in
        /*) cmd="tmux -S $sock2 attach -r -t '=$nm'" ;;
        *)  cmd="(session still starting)" ;;
      esac
      if printf '%s\n' "$line2" | command grep -qE "(^| )nonce=$snonce( |$)"; then
        n_work=$((n_work + 1)); mark="▶"
      else
        mark=" "
        if [ -n "$pp" ] && [ "$pp" -gt 0 ] 2>/dev/null && ! kill -0 "$pp" 2>/dev/null; then
          n_dead=$((n_dead + 1)); tag="($rl·dead)"; cmd="(process gone — torn down)"
        else
          n_held=$((n_held + 1))
        fi
      fi
      A_MARK+=("$mark"); A_ID+=("$short"); A_TAG+=("$tag"); A_CMD+=("$cmd")
      [ "$(dwidth "$short")" -gt "$wid" ] && wid=$(dwidth "$short")
      [ "$(dwidth "$tag")" -gt "$wtag" ] && wtag=$(dwidth "$tag")
    done <<< "$(printf '%s\n' "$sess" | command grep -E "(^| )nonce=$snonce( |$)"
               printf '%s\n' "$sess" | command grep -vE "(^| )nonce=$snonce( |$)")"
    local sfields
    sfields=$(printf '%s\n' "$srow" | tr ' ' '\n')
    # the role the ferry RECORDED when it spawned this session — an observed
    # fact, not a re-derivation of stages.tsv. (The implementer is a subagent
    # the author dispatches inside its own pane; no signal in the store says
    # whether one is running right now, so the panel does not claim it.) The
    # census answers "how many"; ▶ vs blank in the block answers "which".
    local census="$(paint 36 " · $n_work working · $n_held held")"
    [ "$n_dead" -gt 0 ] && census="$census$(paint '1;31' " · $n_dead dead")"
    row agent "$(kv "$sfields" role) · $(kv "$stage" backend) · $(kv "$sfields" mode)$census"
    if [ "${#A_ID[@]}" -le 1 ]; then
      # only the active session exists (the common case): the plain attach row
      case "$(kv "$sfields" socket)" in
        /*) row attach "tmux -S $(kv "$sfields" socket) attach -r -t '=$(kv "$sfields" name)'" ;;
        *)  row attach "(session still starting)" ;;
      esac
    else
      # every live session, one copy-pasteable line each: the id + (role·mode)
      # sit LEFT of the command so the command is the copy target. The whole
      # block shares the active row's fixed-width-74 exemption (copy wins).
      local i first=1 val mk id tag cm
      for i in "${!A_ID[@]}"; do
        # the row's hue follows its state (mockup): active green, dead red,
        # held muted. Padding uses the RAW widths — dwidth strips colour.
        mk="${A_MARK[$i]}"; id="${A_ID[$i]}"; tag="${A_TAG[$i]}"; cm="${A_CMD[$i]}"
        if [ "$mk" = "▶" ]; then
          mk=$(paint 32 "▶"); id=$(paint '1;32' "$id"); tag=$(paint 32 "$tag")
        elif printf '%s' "$tag" | grep -q 'dead'; then
          id=$(paint '1;31' "$id"); tag=$(paint 31 "$tag"); cm=$(paint 2 "$cm")
        else
          tag=$(paint 2 "$tag")
        fi
        val=$(printf '%s %s%*s %s%*s %s' "$mk" \
          "$id" $((wid - $(dwidth "${A_ID[$i]}"))) "" \
          "$tag" $((wtag - $(dwidth "${A_TAG[$i]}"))) "" \
          "$cm")
        if [ "$first" -eq 1 ]; then row attach "$val"; first=0
        else printf '  %-9s %s\n' "" "$(rtrim "$val")"; fi
      done
    fi
  fi
  sep
  case "$stage" in __ABSENT__) row stage "(none yet)"; drew=1 ;; __FAULT__) row stage "$(paint '1;31' 'STORE FAULT')"; drew=1 ;; *)
    if [ "$parked" -eq 0 ]; then
      drew=1
      # the liveness fields are written as a set by the ferry's wait loop; before
      # its first tick there is no classification to show, and a row of "?" reads
      # as a broken panel rather than as "not yet observed".
      local lc
      lc=$(kv "$stage" live_class)
      [ -n "$lc" ] && row liveness "$(paint 32 "$lc") · heartbeat $(fmt_dur "$(kv "$stage" live_hb_age)") ago"
      # The two clocks that can actually end this stage, each against the limit
      # the wait loop compares it to (watch.sh): CONTINUOUS INACTIVITY against
      # stage_timeout, and total elapsed against the hard ceiling — the only
      # absolute cap. Rendering elapsed against stage_timeout (as this panel
      # once did) shows a healthy busy stage draining toward a limit it can
      # never reach; a live operator read it that way and asked whether the
      # agent would be stopped.
      local idle to sp hc wk wmax
      idle=$(kv "$stage" live_idle)
      to=$(config_get "stage.$st.timeout" --topic-dir "$WS" 2>/dev/null) \
        || to=$(config_get liveness.stage_timeout --topic-dir "$WS" 2>/dev/null || true)
      [ -n "$idle" ] && row idle "$(headroom "$idle" "$to" timeout)"
      # the loop publishes its OWN age (clock-jump amnesty shifts spawn_t in
      # watch.sh's local only, so now-spawn_t drifts from what the ceiling is
      # actually measured against); fall back before the first tick
      sp=$(kv "$stage" live_age)
      [ -n "$sp" ] || { sp=$(kv "$stage" spawn_t); [ -n "$sp" ] && [ "$sp" != "0" ] && sp=$((now - sp)) || sp=""; }
      hc=$(config_get liveness.hard_ceiling --topic-dir "$WS" 2>/dev/null || true)
      [ -n "$sp" ] && row elapsed "$(headroom "$sp" "$hc" ceiling)"
      if [ "$lc" = "working" ]; then
        wk=$(kv "$stage" live_working)
        wmax=$(config_get liveness.working_max_age --topic-dir "$WS" 2>/dev/null || true)
        [ -n "$wk" ] && row working "$(headroom "$wk" "$wmax" max)"
      fi
      # Runway rows — each "→ N left" names a criterion that actually fires:
      # the attempt count against the budget check_budgets parks on
      # (stage.<st>.budget_attempts, fallback budget.stage_attempts), and the
      # slice clock against budget.slice_wallclock. ABSENT attempts surface
      # (before the first count) omits the rows, like liveness; fault ≠ absent.
      local attb
      attb=$(surface attempts)
      case "$attb" in
        __ABSENT__) attb="" ;;
        __FAULT__)  row attempts "$(paint '1;31' 'STORE FAULT') — the attempts surface is unreadable"; attb="" ;;
      esac
      if [ -n "$attb" ]; then
        local rnd atn atbud slst wallb
        rnd=$(kv "$stage" round)
        atn=$(kv "$attb" "count.$sl.$st.$rnd")
        if [ -n "$atn" ]; then
          atbud=$(config_get "stage.$st.budget_attempts" --topic-dir "$WS" 2>/dev/null) \
            || atbud=$(config_get budget.stage_attempts --topic-dir "$WS" 2>/dev/null || true)
          case "$atbud" in ''|*[!0-9]*) : ;; *)
            row attempts "$atn/$atbud → $(( atbud - atn > 0 ? atbud - atn : 0 )) left" ;;
          esac
        fi
        # The clock check_budgets compares is WORKING time: parked intervals
        # (credited by the resume gate) are subtracted, or the row would show
        # a budget the real check never spends — the same misread class as
        # elapsed-vs-timeout. Absent credit keys read 0 (pre-credit records).
        # ...and only where it CAN fire. The topic scope (00) is exempt from
        # the slice budget — its `started` stamp is the topic's own, so the
        # cap there would price the whole delivery — and a row rendering an
        # exempt budget is the same misread as elapsed-vs-timeout, one row
        # lower. The topic row below is the clock that owns that span.
        if [ "$sl" != "00" ]; then
          local slpk
          slst=$(kv "$attb" "slice.$sl.started")
          slpk=$(kv "$attb" "parked.$sl"); case "$slpk" in ''|*[!0-9]*) slpk=0 ;; esac
          wallb=$(config_get budget.slice_wallclock --topic-dir "$WS" 2>/dev/null || true)
          case "$slst" in ''|*[!0-9]*) : ;; *)
            row slice "$(headroom $((now - slst - slpk)) "$wallb" wallclock)" ;;
          esac
        fi
      fi
      local cu total
      total=$(kv "$stage" cu_total)
      if [ -n "$total" ] && { [ "$st" = "impl" ] || [ "$st" = "fix" ]; }; then
        # distinct cu ids, not record lines — fix rounds re-register units
        cu=$(surface progress | command grep -E "(^| )slice=$sl( |$)" \
             | command grep -oE '(^| )cu=[^ ]+' | sort -u | command grep -c . || true)
        row commits "cu $cu/$total (progress surface)"
      fi
    fi ;;
  esac
  case "$run" in
    __ABSENT__|__FAULT__) : ;;
    *)
      local t0 tb tpk
      t0=$(kv "$run" t_start)
      tpk=$(kv "$run" parked_total); case "$tpk" in ''|*[!0-9]*) tpk=0 ;; esac
      tb=$(config_get budget.topic_wallclock --topic-dir "$WS" 2>/dev/null || true)
      case "$t0" in ''|*[!0-9]*) : ;; *)
        row topic "$(kv "$run" mode) · started $(date -d "@$t0" '+%m-%d %H:%M' 2>/dev/null) · $(headroom $((now - t0 - tpk)) "$tb")"; drew=1 ;;
      esac ;;
  esac
  sep

  # ---- what just happened
  local led
  led=$(surface ledger)
  case "$led" in
    __ABSENT__) printf '%s\n' "$(paint 2 'recent')  $(paint 2 '(ledger empty)')" ;;
    __FAULT__)  printf '%s\n' "$(paint 2 'recent')  $(paint '1;31' 'STORE FAULT in the ledger surface')" ;;
    *)
      printf '%s\n' "$(paint 2 'recent')  $(paint 2 '(ledger, last 8)')"
      printf '%s\n' "$led" | tail -8 | while IFS= read -r rec; do led_render "$rec"; done ;;
  esac
  rule

  # ---- the driver itself
  # A live watchdog beside a parked final-state is the PAGER (watchdog.sh clears
  # final-state when it drives): nothing is driving, and "alive" would say the
  # opposite of what the operator needs to know.
  if [ "$wd_alive" -eq 1 ] && printf '%s' "$final" | command grep -q '^class=parked '; then
    row watchdog "$(paint '1;33' 'PAGING') (pid $wd) — nothing is driving; the park is unresolved and re-pages; launch.sh ack pauses that for one window"
  elif [ "$wd_alive" -eq 1 ]; then row watchdog "$(paint 32 'alive') (pid $wd)"
  elif [ -n "$final" ]; then row watchdog "not running · $final"
  else row watchdog "$(paint '1;33' 'NOT RUNNING') — nothing is driving this topic"; fi
  case "$notifyb" in
    __ABSENT__) row notify "$(config_get notify.preset --topic-dir "$WS" 2>/dev/null || echo key-points) (default)" ;;
    __FAULT__)  row notify "$(paint '1;31' 'STORE FAULT')" ;;
    *) row notify "$(kv "$notifyb" preset) $(printf '%s\n' "$notifyb" | command grep '^event\.' | tr '\n' ' ')" ;;
  esac
  rule
  printf '%s\n' "$(paint 2 'reads the store only · writes nothing · control surface is launch.sh')"
}

# In-place repaint: cursor-home, erase each line to EOL as it is rewritten,
# erase below. Never \033[2J — a blank-and-refill flickers at every poll.
repaint() { # frame
  printf '\033[H'
  printf '%s\n' "$1" | while IFS= read -r l; do printf '%s\033[K\n' "$l"; done
  printf '\033[J'
}

if [ $ONCE -eq 1 ]; then render; exit 0; fi
[ "$USE_COLOR" -eq 1 ] && printf '\033[2J\033[H'      # cleared exactly once, at entry
LAST=""
while :; do
  FRAME=$(render)
  if [ "$FRAME" != "$LAST" ]; then
    if [ "$USE_COLOR" -eq 1 ]; then repaint "$FRAME"; else printf '%s\n' "$FRAME"; fi
    LAST=$FRAME
  fi
  sleep 2
done
