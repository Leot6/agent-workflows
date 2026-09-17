#!/usr/bin/env bash
# lib/platform.sh — the one home of every difference between the two hosts
# this tree runs on: Linux (procfs, GNU coreutils, util-linux) and macOS
# (no procfs, BSD userland). Sourced by lib/state.sh, lib/locks.sh and
# backends/pty_tmux.sh, which between them sit under every entry point, so no
# caller branches on the platform itself — a second `uname` test anywhere else
# is a second place this file's decisions have to be kept in step.
#
# Two kinds of thing live here:
#   plat_* functions — a question both hosts can answer, asked one way:
#     plat_starttime <pid>     a process's start identity (digits), rc 1 if gone
#     plat_proc_table          "pid ppid cpu_ticks" for every process
#     plat_clk_tck             cpu ticks per second, the unit of plat_proc_table
#     plat_now_ns              epoch nanoseconds (digits)
#     plat_epoch_fmt <t> <fmt> an epoch rendered in local time, strftime format
#     plat_stat_nsm <path>...  "path size mtime" per path, silent on a missing one
#     plat_loadavg             "1m 5m 15m", or "unavailable"
#     plat_tree_entries        one "type+mode path" line per entry under the cwd,
#                              .git excluded (a snapshot compared within one host)
#     plat_sed_i <sed args>    sed editing its file arguments in place
#     plat_pty_run <cmdline>   run a shell command line on a fresh pseudo-terminal
#                              (script(1): util-linux and BSD spell it differently).
#                              TERM is set for that pty: the caller's TERM describes
#                              the caller's terminal (often `dumb` under CI or ssh),
#                              and tmux refuses to attach to a terminal that
#                              "does not support clear". stdin is /dev/null: script
#                              reads its caller's stdin, and a parallel runner's
#                              dispatch pipe must never be consumed by a check.
#   command stand-ins — md5sum, timeout, flock, setsid in darwin-bin/, put
#     first on PATH on macOS only, so a Linux host runs the real binaries and
#     nothing here is on its path. Each covers the forms this tree uses and
#     refuses any other by name rather than guessing.

[ -n "${_PLATFORM_SH_LOADED:-}" ] && return 0
_PLATFORM_SH_LOADED=1

case "$(uname -s 2>/dev/null)" in
  Darwin) PLATFORM=darwin ;;
  *)      PLATFORM=linux ;;
esac

if [ "$PLATFORM" = linux ]; then

  # procfs field 22 (after the comm paren, which may itself hold spaces):
  # jiffies since boot — unique per pid for the life of the machine.
  plat_starttime() {
    [ -r "/proc/$1/stat" ] || return 1
    awk '{ s=$0; sub(/^[^)]*\) /,"",s); split(s,f," "); print f[20] }' "/proc/$1/stat"
  }

  # utime+stime (fields 14/15) in jiffies; ppid is field 4.
  plat_proc_table() {
    cat /proc/[0-9]*/stat 2>/dev/null | awk '
      { pid=$1; line=$0; sub(/^[^(]*\(/,"",line); sub(/^.*\) /,"",line)
        split(line,f," "); print pid, f[2], f[12]+f[13] }'
  }

  plat_clk_tck() {
    local c
    c=$(getconf CLK_TCK 2>/dev/null)
    case "$c" in ''|*[!0-9]*) c=100 ;; esac
    printf '%s\n' "$c"
  }

  plat_now_ns() { date +%s%N; }

  plat_epoch_fmt() { date -d "@$1" "+$2"; }

  plat_stat_nsm() {
    local p
    for p in "$@"; do stat -c '%n %s %Y' "$p" 2>/dev/null; done
    return 0
  }

  plat_loadavg() { cut -d' ' -f1-3 /proc/loadavg 2>/dev/null || echo unavailable; }

  plat_tree_entries() { find . -path ./.git -prune -o -printf '%y %m %p\n'; }

  plat_sed_i() { sed -i "$@"; }

  plat_pty_run() { TERM=xterm-256color script -qc "$1" /dev/null < /dev/null; }

else

  # ps's lstart is second-grained wall time; as epoch seconds it is a digit
  # token like procfs's, and a pid reused inside the same second is the one
  # identity it cannot tell apart — named, and far below the watch loop's grain.
  plat_starttime() {
    local s
    case "$1" in ''|*[!0-9]*) return 1 ;; esac
    s=$(LC_ALL=C ps -o lstart= -p "$1" 2>/dev/null) || return 1
    [ -n "$s" ] || return 1
    LC_ALL=C date -j -f '%a %b %e %T %Y' "$s" '+%s' 2>/dev/null
  }

  # ps reports cumulative cpu as [[dd-]hh:]mm:ss.cc; rendered here in
  # hundredths, which is what plat_clk_tck states the unit to be.
  plat_proc_table() {
    LC_ALL=C ps -A -o pid= -o ppid= -o time= 2>/dev/null | awk '
      { t=$3; d=0
        if (index(t, "-")) { split(t, dd, "-"); d=dd[1]; t=dd[2] }
        n=split(t, p, ":"); s=0
        for (i=1; i<=n; i++) s=s*60+p[i]
        printf "%s %s %d\n", $1, $2, (d*86400+s)*100 + 0.5 }'
  }

  plat_clk_tck() { printf '100\n'; }

  plat_now_ns() {
    perl -MTime::HiRes=gettimeofday -e 'my ($s,$u)=gettimeofday; printf "%d%06d000\n", $s, $u'
  }

  plat_epoch_fmt() { date -r "$1" "+$2"; }

  plat_stat_nsm() {
    local p
    for p in "$@"; do stat -f '%N %z %m' "$p" 2>/dev/null; done
    return 0
  }

  plat_loadavg() {
    local l
    l=$(sysctl -n vm.loadavg 2>/dev/null | tr -d '{}') || l=""
    set -- $l
    [ $# -ge 3 ] && printf '%s %s %s\n' "$1" "$2" "$3" || echo unavailable
  }

  plat_tree_entries() { # the same "%y %m %p" shape as GNU find's
    local t
    for t in d f l; do
      find . -path ./.git -prune -o -type "$t" -exec stat -f "$t %Lp %N" {} +
    done
  }

  plat_sed_i() { sed -i '' "$@"; }

  plat_pty_run() { TERM=xterm-256color script -q /dev/null bash -c "$1" < /dev/null; }

  # --- command stand-ins -----------------------------------------------------
  # md5sum, timeout, flock and setsid are executables in darwin-bin/, always
  # first on PATH here — whatever else a Mac has installed, these four behave
  # as 05-platform proves them, not as a mix of Homebrew versions happens to.
  # Executables rather than shell functions because callers reach them through
  # `xargs`, `env` and `bash -c`, and `setsid cmd &` must leave $! naming the
  # command itself.
  _plat_bin="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/darwin-bin"
  case ":$PATH:" in *":$_plat_bin:"*) ;; *) PATH="$_plat_bin:$PATH"; export PATH ;; esac

fi

export PLATFORM
