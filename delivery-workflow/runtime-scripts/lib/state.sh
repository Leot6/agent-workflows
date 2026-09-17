#!/usr/bin/env bash
# lib/state.sh — the one atomic store (design/state-and-liveness.md §1).
#
# Surfaces live at <workspace>/.runtime/state/<surface>, one file each.
# Header line: #v=1 gen=<n> sum=<md5-of-body> writer=<class> t=<epoch>
# Atomicity: write to <workspace>/.runtime/tmp (same filesystem) + rename.
#
# rc contract — callers MUST distinguish (fault ≠ absent, the v1 wedge class):
#   0 ok · 1 absent (surface/key missing; normal before first write)
#   2 refused (writer-class mismatch, bad surface, bad args)
#   3 FAULT (corrupt header or checksum) — propagate, never read as zero.
#
# Writer-class registry: sole writer class per surface (a bug barrier, not a
# security barrier). Surfaces `observations`/`learnings` accept session+operator
# and `audit` accepts any, per the design's own surface list; `slices` accepts
# ferry+operator (ferry maintains the index, launch.sh cancel/restore edits
# status — recorded as a deviation in the implementation report).
# Append surfaces carry a line cap; on exceedance the surface is rotated to
# <surface>.<epoch>.rot beside it — named, never silent.

_STATE_LIB_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
. "$_STATE_LIB_DIR/platform.sh"

_state_root() { printf '%s/.runtime/state' "$1"; }
_state_tmpdir() { printf '%s/.runtime/tmp' "$1"; }

_state_writers() {
  case "$1" in
    run|stage|attempts|halt|sessions|ledger) echo "ferry" ;;
    heartbeat|handoff|progress|decisions|notify_events) echo "session" ;;
    rulings|notify) echo "operator" ;;
    observations|learnings) echo "session operator" ;;
    slices) echo "ferry operator" ;;
    gates) echo "gate" ;;
    audit) echo "any" ;;
    *) return 1 ;;
  esac
}

# Append surfaces only; empty output = set-surface (whole-body writes only).
_state_append_cap() {
  case "$1" in
    ledger) echo 8000 ;;
    audit) echo 16000 ;;
    handoff|progress|decisions|rulings|observations|learnings|gates|notify_events) echo 4000 ;;
    *) echo "" ;;
  esac
}

_state_writer_ok() { # surface writer
  local allowed
  allowed=$(_state_writers "$1") || {
    echo "refuse: unknown surface '$1' (no writer-class registry entry)" >&2
    return 2
  }
  [ "$allowed" = "any" ] && return 0
  local w
  for w in $allowed; do [ "$w" = "$2" ] && return 0; done
  echo "refuse: surface '$1' writer class '$2' not allowed (allowed: $allowed)" >&2
  return 2
}

# Public predicate over the same registry: "does the store hold a surface by
# this name". Callers that must VALIDATE a surface name a human typed (rather
# than write to one) ask here instead of reaching into _state_writers, so the
# registry stays the single enumeration and a surface added there is accepted
# everywhere the day it lands.
state_surface_known() { # surface -> rc 0 when registered
  _state_writers "$1" >/dev/null 2>&1
}

# One fork, not two. This is the hottest function in the store: every READ
# verifies the checksum and every WRITE computes it, so the `| awk '{print $1}'`
# that used to trim md5sum's output was a second process on a path measured at
# ~4,400 calls in a single 17-stage ferry walk. `md5sum` prints "<hash>  -", and
# the prefix strip is a builtin.
_state_body_sum() { local s; s=$(md5sum); printf '%s\n' "${s%% *}"; }

# The repo-claim lock lives in the checkout's GIT DIR, not the worktree: an
# untracked lock file at the repo root dirtied every legal checkout (worktree
# status noise, clean-tree contracts) and — worse — each relaunch rewrites the
# lock, so its mtime churned the content-bound dirty fingerprint and read a
# valid acceptance PASS as stale. --absolute-git-dir is per-WORKTREE (linked
# worktrees claim independently — matching "parallel topics need separate
# checkouts/worktrees"). rc 1 = not a git checkout (the pipeline is git-shaped;
# project_validate refuses those up front).
state_repo_lock_path() { # repo -> lock path
  local gd
  gd=$(git -C "$1" rev-parse --absolute-git-dir 2>/dev/null) || return 1
  printf '%s/delivery.lock\n' "$gd"
}

# The SESSIONS record, in one place. Four writers exist — the ferry's warm
# reuse, its pre-spawn pending row, its completed cold row, and the probe's
# scratch seed — and each used to carry its own copy of this line. That is why
# the surface had no `backend` field for so long: adding one cost four edits
# and a reader's guess at the shape, and the missing field is exactly what let
# a mid-run backend switch be silently defeated at every warm stage. rec_field
# is the single reader; this is the single writer.
# `t` is stamped here because nothing reads it — checked over the full range:
# the surface is read by record.sh's `cmd_emit` and `_emit_fix_evidence`, by
# `sessions_entry` and `sessions_replace` (ferry.sh) and `reconcile_fence`
# (lib/preflight.sh), and by monitor.sh's own kv, and between them they ask for
# role, name, the two pid/starttime pairs, socket, nonce, mode and backend.
# Never t. It is a human
# breadcrumb, so "when the row was written" is the honest value.
# The row is whitespace-delimited, so no value may contain a space. That holds
# upstream, not here, and at two depths: ferry.sh's main() REFUSES a topic
# directory name outside [A-Za-z0-9_-] before it takes a lock (session names
# embed it), and pty_session_name_ok checks the same charset again before any
# session exists. `role` and `mode` are closed vocabularies, the pids are
# numeric, and a backend name that could not be a filename under
# config/backends/ never resolves a declaration. Stated because this is now the
# one place that would have to enforce it if those ever went away.
state_sessions_row() { # role name pane_pid pane_start server_pid server_start socket nonce mode backend
  printf 'role=%s name=%s pane_pid=%s pane_start=%s server_pid=%s server_start=%s socket=%s nonce=%s mode=%s backend=%s t=%s\n' \
    "$1" "$2" "$3" "$4" "$5" "$6" "$7" "$8" "$9" "${10}" "$(date +%s)"
}

# The HOST lock's path and holder-liveness, in the same shape and for the same
# reason as the repo pair below: the ferry's take (lib/locks.sh) is
# authoritative, and launch.sh needs the same truth advisorily — `stop` must
# know whether anything is running that could honour a stop request, and a
# dead watchdog does not mean a dead ferry. One derivation of the path, or the
# second copy of "$WS/.runtime/state/lock" rots the day the store layout moves.
state_host_lock_path() { # ws -> lock path
  printf '%s/.runtime/state/lock\n' "$1"
}
# rc 0 + "pid=<p>" when a LIVE ferry holds the lock; rc 1 otherwise (absent or
# stale). Starttime reading is _pty_starttime — the ONE starttime truth
# (backends/pty_tmux.sh, over lib/platform.sh); both callers source it before
# calling here.
state_host_holder() { # ws
  local lock pid start
  lock=$(state_host_lock_path "$1")
  pid=$(awk -F= '$1=="pid"{print $2}' "$lock/pid" 2>/dev/null | awk '{print $1}')
  start=$(command grep -o 'start=[0-9]*' "$lock/pid" 2>/dev/null | head -1 | cut -d= -f2)
  [ -n "$pid" ] && [ "$(_pty_starttime "$pid" 2>/dev/null || echo gone)" = "$start" ] || return 1
  printf 'pid=%s\n' "$pid"
}

# One holder-liveness truth for the repo lock, shared by the ferry's take
# (authoritative) and launch.sh preflight (advisory — refuse a doomed launch
# BEFORE a probe session is spent). rc 0 + "topic=<t> pid=<p>" when a LIVE
# holder OTHER than <ws> claims the repo; rc 1 otherwise (absent, ours, or
# stale). Starttime reading is _pty_starttime — the ONE procfs starttime
# truth (backends/pty_tmux.sh); both real callers (ferry, launch) source it
# before calling here.
state_repo_claimed() { # repo ws
  local lock topic pid start
  lock=$(state_repo_lock_path "$1") || return 1
  [ -f "$lock" ] || return 1
  topic=$(awk -F= '$1=="topic"{print $2}' "$lock" 2>/dev/null)
  pid=$(awk -F= '$1=="pid"{print $2}' "$lock" 2>/dev/null)
  start=$(awk -F= '$1=="start"{print $2}' "$lock" 2>/dev/null)
  [ "$topic" = "$2" ] && return 1
  [ -n "$pid" ] && [ "$(_pty_starttime "$pid" 2>/dev/null || echo gone)" = "$start" ] || return 1
  printf 'topic=%s pid=%s\n' "$topic" "$pid"
}

# Parse+verify header of an existing surface file. Prints "gen" on stdout.
_state_verify() { # file surface
  local f=$1 s=$2 hdr
  IFS= read -r hdr < "$f" || hdr=""
  if ! [[ "$hdr" =~ ^#v=1\ gen=([0-9]+)\ sum=([0-9a-f]{32})\ writer=[a-z]+\ t=[0-9]+$ ]]; then
    echo "FAULT: surface '$s' corrupt header in $f — inspect the file; do not treat as absent" >&2
    return 3
  fi
  local gen=${BASH_REMATCH[1]} want=${BASH_REMATCH[2]} got
  got=$(tail -n +2 "$f" | _state_body_sum)
  if [ "$got" != "$want" ]; then
    echo "FAULT: surface '$s' checksum mismatch in $f (header=$want body=$got) — inspect; do not treat as absent" >&2
    return 3
  fi
  printf '%s\n' "$gen"
}

state_get() { # workspace surface  -> body on stdout
  # ONE fd for the whole read: existence check, header, checksum and body
  # must observe one snapshot. The previous shape opened the path up to four
  # times (existence, header read, body tail for the sum, body tail for the
  # caller) — a concurrent writer rename landing between them yields a FALSE
  # checksum mismatch over a healthy store (the rc=3 blips live sessions/
  # stage reads showed once on the live topic). The writer renames WHOLE
  # files, so a single fd observes exactly one version: mapfile consumes the
  # same descriptor the header line was read from. Measured: unthrottled
  # reader/writer loops produced 406 false rc=3 in 6s on the old shape; this
  # form produces zero (the same 6s, same loops) — verified in round 33.
  local ws=$1 s=$2 f hdr all gen want got
  f="$(_state_root "$ws")/$s"
  if [ ! -e "$f" ]; then
    echo "absent: surface '$s' ($f)" >&2; return 1
  fi
  { IFS= read -r hdr && mapfile -t all; } < "$f" || true
  if ! [[ "$hdr" =~ ^#v=1\ gen=([0-9]+)\ sum=([0-9a-f]{32})\ writer=[a-z]+\ t=[0-9]+$ ]]; then
    echo "FAULT: surface '$s' corrupt header in $f — inspect the file; do not treat as absent" >&2
    return 3
  fi
  want=${BASH_REMATCH[2]}
  # an empty body hashes as EMPTY (d41d8…), not as one blank line: a surface
  # written with no body carries no trailing newline after the header, and
  # "${all[@]}" with zero elements must not materialize one (the /dev/null
  # stdin shape — measured by the peek-empty fixture going red).
  if [ "${#all[@]}" -gt 0 ]; then
    got=$(printf '%s\n' "${all[@]}" | _state_body_sum)
  else
    got=$(printf '' | _state_body_sum)
  fi
  if [ "$got" != "$want" ]; then
    echo "FAULT: surface '$s' checksum mismatch in $f (header=$want body=$got) — inspect; do not treat as absent" >&2
    return 3
  fi
  # A reader that stops early (`| grep -q`, `| head`) is not a store fault. The
  # rc above is decided before a byte is written, and the write ignores
  # SIGPIPE: otherwise a pipeline under `pipefail` reads a matched surface as
  # rc 141 whenever the body outruns the pipe buffer (16K on macOS, 64K on
  # Linux) — a present record read as absent.
  if [ "${#all[@]}" -gt 0 ]; then
    ( trap '' PIPE; printf '%s\n' "${all[@]}" ) 2>/dev/null || :
  fi
}

# Last value of key= in a kv surface. rc 1 covers both absent-surface and
# absent-key; rc 3 fault propagates.
state_field() { # workspace surface key
  local body rc
  body=$(state_get "$1" "$2" 2>/dev/null); rc=$?
  [ $rc -eq 0 ] || return $rc
  local v
  v=$(printf '%s\n' "$body" | awk -F= -v k="$3" '$1==k{v=substr($0,length(k)+2)} END{if(v=="")exit 1; print v}') || return 1
  printf '%s\n' "$v"
}

_state_write() { # workspace surface writer gen body-file
  local ws=$1 s=$2 w=$3 gen=$4 bf=$5 root tmpd tmp sum
  root=$(_state_root "$ws"); tmpd=$(_state_tmpdir "$ws")
  [ -d "$root" ] && [ -d "$tmpd" ] \
    || mkdir -p "$root" "$tmpd" || { echo "FAULT: cannot create store dirs under $ws/.runtime" >&2; return 3; }
  sum=$(_state_body_sum < "$bf")
  tmp=$(mktemp "$tmpd/$s.XXXXXX") || { echo "FAULT: mktemp failed in $tmpd" >&2; return 3; }
  {
    printf '#v=1 gen=%s sum=%s writer=%s t=%s\n' "$gen" "$sum" "$w" "${EPOCHSECONDS:-$(date +%s)}"
    cat "$bf"
  } > "$tmp" || { rm -f "$tmp"; echo "FAULT: write failed for surface '$s'" >&2; return 3; }
  mv -f "$tmp" "$root/$s" || { rm -f "$tmp"; echo "FAULT: rename failed for surface '$s'" >&2; return 3; }
}

# Every mutation runs its read-modify-write under an exclusive per-surface
# flock — atomic rename alone stops half-writes, not lost updates between two
# concurrent writers (each would re-write the body it read). The lock file is
# a dotfile beside the surfaces; readers stay lock-free (rename is atomic, a
# reader sees a complete old or new file, never a torn one).
_state_with_lock() { # workspace surface cmd args...
  local ws=$1 s=$2; shift 2
  local root tmpd
  root=$(_state_root "$ws"); tmpd=$(_state_tmpdir "$ws")
  [ -d "$root" ] && [ -d "$tmpd" ] \
    || mkdir -p "$root" "$tmpd" \
    || { echo "FAULT: cannot create store dirs under $ws/.runtime" >&2; return 3; }
  (
    flock -w 30 9 || { echo "FAULT: surface '$s' write-lock timeout (30s) — a writer is stuck" >&2; exit 3; }
    "$@"
  ) 9> "$root/.$s.lock"
}

_state_set_core() { # workspace surface writer  (body on stdin)
  local ws=$1 s=$2 w=$3 f gen rc bf
  f="$(_state_root "$ws")/$s"
  gen=1
  if [ -e "$f" ]; then
    gen=$(_state_verify "$f" "$s") || return 3
    gen=$((gen + 1))
  fi
  bf=$(mktemp "${TMPDIR:-/tmp}/state-body.XXXXXX") || return 3
  # cat rc guarded: a writer dying mid-stream would otherwise hand a TRUNCATED
  # body to checksumming — internally consistent, silently wrong (the exact
  # error direction the store exists to exclude).
  cat > "$bf" || { rm -f "$bf"; return 3; }
  _state_write "$ws" "$s" "$w" "$gen" "$bf"; rc=$?
  rm -f "$bf"
  return $rc
}

state_set() { # workspace surface writer  (body on stdin)
  _state_writer_ok "$2" "$3" || return 2
  _state_with_lock "$1" "$2" _state_set_core "$1" "$2" "$3"
}

_state_put_core() { # workspace surface writer key=value...
  local ws=$1 s=$2 w=$3; shift 3
  local f body rc pair k
  f="$(_state_root "$ws")/$s"
  body=""
  if [ -e "$f" ]; then
    body=$(state_get "$ws" "$s"); rc=$?
    [ $rc -eq 0 ] || return $rc
  fi
  # Every pair's key is dropped from the body in ONE pass, then the pairs are
  # appended in the order given (a key named twice keeps its last value) — the
  # same result the per-pair loop produced with an awk and a subshell per key;
  # a stage note carries six.
  local keys=""
  for pair in "$@"; do
    case "$pair" in *=*) : ;; *)
      echo "refuse: state_put needs key=value, got '$pair'" >&2; return 2 ;;
    esac
    keys="$keys ${pair%%=*}"
  done
  { printf '%s\n' "$body" | awk -F= -v ks="$keys" 'BEGIN { n = split(ks, a, " "); for (i = 1; i <= n; i++) drop[a[i]] = 1 } $0 != "" && !($1 in drop)'
    printf '%s\n' "$@" | awk -F= '{ key[NR] = $1; line[NR] = $0; last[$1] = NR } END { for (i = 1; i <= NR; i++) if (last[key[i]] == i) print line[i] }'
  } | _state_set_core "$ws" "$s" "$w"
}

state_put() { # workspace surface writer key=value...  (kv upsert)
  local ws=$1 s=$2 w=$3; shift 3
  _state_writer_ok "$s" "$w" || return 2
  _state_with_lock "$ws" "$s" _state_put_core "$ws" "$s" "$w" "$@"
}

_state_append_core() { # workspace surface writer line
  local ws=$1 s=$2 w=$3 line=$4 cap f gen body lines rc
  cap=$(_state_append_cap "$s")
  # An empty line is the signature of the pipe mistake: state_append takes
  # the row as an ARGUMENT, and `... | state_append ws surf writer` — a shape
  # operations §5 authorizes by naming lib/state.sh as the manual floor —
  # lands stdin in the void and appends NOTHING, rc 0 (measured: a whole
  # test matrix "wrote" 800 rows this way before the trace showed
  # line=''). Refusing the empty row turns the silent no-op into a named
  # error; a genuine empty append is not a thing any caller wants.
  [ -n "$line" ] || { echo "refuse: state_append needs the row as an ARGUMENT (got an empty line — stdin is not read; the manual floor is lib/state.sh set|put|append with the row as the last argument)" >&2; return 2; }
  line=$(printf '%s' "$line" | tr '\n\t' '  ')
  f="$(_state_root "$ws")/$s"
  gen=1; body=""
  if [ -e "$f" ]; then
    # ONE fd for the snapshot (the R33 single-open rule, applied to the
    # read-modify-write path): the old `tail -n +2 "$f"` was a SECOND open,
    # and a writer rename between the verify and the tail pairs a new header
    # with an old body — a FALSE checksum mismatch (found by a review round).
    # Inline the read here rather than calling _state_verify: that function
    # would set _state_body in a subshell that does not reach this one.
    local vhdr vall vwant vgot
    { IFS= read -r vhdr && mapfile -t vall; } < "$f" || true
    if ! [[ "$vhdr" =~ ^#v=1\ gen=([0-9]+)\ sum=([0-9a-f]{32})\ writer=[a-z]+\ t=[0-9]+$ ]]; then
      echo "FAULT: surface '$s' corrupt header in $f — inspect the file; do not treat as absent" >&2; return 3
    fi
    vwant=${BASH_REMATCH[2]}
    if [ "${#vall[@]}" -gt 0 ]; then
      vgot=$(printf '%s\n' "${vall[@]}" | _state_body_sum)
    else
      vgot=$(printf '' | _state_body_sum)
    fi
    if [ "$vgot" != "$vwant" ]; then
      echo "FAULT: surface '$s' checksum mismatch in $f (header=$vwant body=$vgot) — inspect; do not treat as absent" >&2; return 3
    fi
    gen=${BASH_REMATCH[1]}
    body=$(printf '%s\n' "${vall[@]}")
    gen=$((gen + 1))
  fi
  lines=$(printf '%s\n' "$body" | { command grep -c . || true; })
  if [ "$lines" -ge "$cap" ]; then
    local rot="$f.$(date +%s).rot"
    mv -f "$f" "$rot" || { echo "FAULT: rotation rename failed for '$s'" >&2; return 3; }
    body="v=1 t=$(date +%s) event=rotated cap=$cap rotated_to=$(basename "$rot")"
  fi
  local bf
  bf=$(mktemp "${TMPDIR:-/tmp}/state-body.XXXXXX") || return 3
  if [ -n "$body" ]; then printf '%s\n%s\n' "$body" "$line" > "$bf"
  else printf '%s\n' "$line" > "$bf"; fi
  _state_write "$ws" "$s" "$w" "$gen" "$bf"; rc=$?
  rm -f "$bf"
  return $rc
}

state_append() { # workspace surface writer line
  local ws=$1 s=$2 w=$3 line=$4 cap
  _state_writer_ok "$s" "$w" || return 2
  cap=$(_state_append_cap "$s")
  [ -n "$cap" ] || { echo "refuse: surface '$s' is not an append surface" >&2; return 2; }
  _state_with_lock "$ws" "$s" _state_append_core "$ws" "$s" "$w" "$line"
}

# Best-effort audit note; never fails the caller — but never fails SILENTLY
# either: on a corrupt audit surface every note would otherwise vanish with no
# trace (the silent-append-loss class). stderr only, deliberately no notify
# from here: notify_fire audits through this function, so notifying on failure
# would recurse exactly when the audit surface is the one that is broken.
state_audit() { # workspace class message
  state_append "$1" audit "$2" "v=1 t=$(date +%s) by=$2 msg=$3" >/dev/null 2>&1 \
    || echo "audit append FAILED (surface fault? the next launch parks store_fault) — lost note [$2] $3" >&2
}

# Verify every headed surface in the store — the startup integrity gate's
# mechanism (the ferry dies store_fault on any hit; mid-run appends are loud
# but survivable, a whole run over a corrupt surface is not). A surface is
# exactly what the writer-class REGISTRY names — never "whatever sits in the
# dir": the host lock's flock file (lock.reclaim), rotated segments (*.rot)
# and any stray file are not surfaces and are not judged (a dir-listing guess
# here killed every launch the first time). One fault line per broken surface
# on stdout, naming the file + repair recipe. rc 0 all clean · 1 faults.
state_verify_all() { # workspace
  local ws=$1 root f s bad=0
  root=$(_state_root "$ws")
  [ -d "$root" ] || return 0
  for f in "$root"/*; do
    [ -f "$f" ] || continue          # lock dir; the unmatched-glob literal
    s=$(basename "$f")
    _state_writers "$s" > /dev/null 2>&1 || continue
    _state_verify "$f" "$s" > /dev/null 2>&1 && continue
    echo "surface '$s' FAULT: corrupt header or checksum in $f — verify the body, then reseal the header (sum= must equal: tail -n +2 $f | md5sum)"
    bad=1
  done
  [ "$bad" -eq 0 ] || return 1
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  set -uo pipefail
  export LC_ALL=C
  usage() {
    echo "usage: state.sh get <ws> <surface>" >&2
    echo "       state.sh field <ws> <surface> <key>" >&2
    echo "       state.sh set <ws> <surface> --writer <class>   (body on stdin)" >&2
    echo "       state.sh put <ws> <surface> --writer <class> key=value..." >&2
    echo "       state.sh append <ws> <surface> --writer <class> --line <record>" >&2
    exit 2
  }
  [ $# -ge 3 ] || usage
  cmd=$1 ws=$2 surface=$3; shift 3
  writer=""; line=""
  args=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --writer) writer=$2; shift 2 ;;
      --line) line=$2; shift 2 ;;
      *) args+=("$1"); shift ;;
    esac
  done
  case "$cmd" in
    get) state_get "$ws" "$surface" ;;
    field) [ ${#args[@]} -eq 1 ] || usage; state_field "$ws" "$surface" "${args[0]}" ;;
    set) [ -n "$writer" ] || usage; state_set "$ws" "$surface" "$writer" ;;
    put) [ -n "$writer" ] && [ ${#args[@]} -ge 1 ] || usage
         state_put "$ws" "$surface" "$writer" "${args[@]}" ;;
    append) [ -n "$writer" ] && [ -n "$line" ] || usage
            state_append "$ws" "$surface" "$writer" "$line" ;;
    *) usage ;;
  esac
fi
