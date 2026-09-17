#!/usr/bin/env bash
# 05-platform — lib/platform.sh answers every host question in the shape its
# callers parse, and the darwin-bin/ stand-ins keep the command semantics the
# tree relies on. Runs first: every later check stands on these answers, and a
# wrong one here reads downstream as a wedge, a false park or a silent pass.
#
# The stand-ins are driven BY PATH on every host, not only on macOS: they are
# plain perl, so a Linux run proves them too, and a change to one cannot wait
# for a macOS machine to go red.
#
# HONEST BOUNDARY: this proves shape and semantics on the host it runs on. That
# the OTHER host's branch is right is that host's run — the reason the CI
# matrix carries both.
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/fixtures/lib.sh"

BIN="$RS/lib/darwin-bin"
scr=$(sc_tmpdir)

echo "-- plat_* answers on this host ($PLATFORM) --"
st=$(plat_starttime $$); rc=$?
[ $rc -eq 0 ] && [[ "$st" =~ ^[0-9]+$ ]] \
  && ok "plat_starttime of a live pid is a digit token ($st)" \
  || bad "plat_starttime \$\$ rc=$rc value='$st'"
[ "$(plat_starttime $$)" = "$st" ] \
  && ok "…and stable across reads (it is an identity, not a clock)" \
  || bad "plat_starttime changed between two reads of the same process"
sleep 30 & kid=$!
kst=$(plat_starttime "$kid")
kill "$kid" 2>/dev/null; wait "$kid" 2>/dev/null
plat_starttime "$kid" > /dev/null 2>&1 \
  && bad "a reaped pid still reports a start identity" \
  || ok "a gone pid is rc 1 (dead, never a stale identity)"
[[ "$kst" =~ ^[0-9]+$ ]] && ok "a child's identity was readable while it lived" \
  || bad "no identity for a live child: '$kst'"
plat_starttime "not-a-pid" > /dev/null 2>&1 \
  && bad "a non-numeric pid produced an identity" \
  || ok "a non-numeric pid is refused"

table=$(plat_proc_table)
precond "plat_proc_table lists processes (saw $(printf '%s\n' "$table" | command grep -c .))" \
  test "$(printf '%s\n' "$table" | command grep -c .)" -ge 3
bad_rows=$(printf '%s\n' "$table" | awk 'NF != 3 || $1 !~ /^[0-9]+$/ || $2 !~ /^[0-9]+$/ || $3 !~ /^[0-9]+$/' | head -3)
[ -z "$bad_rows" ] && ok "every row is 'pid ppid ticks', all digits" \
  || bad "malformed plat_proc_table rows: $bad_rows"
printf '%s\n' "$table" | awk -v p=$$ '$1 == p { f = 1 } END { exit !f }' \
  && ok "this shell is in the table" || bad "this shell (pid $$) missing from plat_proc_table"
# The unit is what makes liveness.cpu_busy_pct mean the same thing on both
# hosts: ticks / plat_clk_tck must be the process's own CPU seconds. Compared
# against the child's OWN account (bash `times`), never against wall time — a
# loaded machine hands a busy child a fraction of a core, and a wall-clock
# bound would measure the load instead of the unit.
clk=$(plat_clk_tck)
[[ "$clk" =~ ^[0-9]+$ ]] && [ "$clk" -gt 0 ] && ok "plat_clk_tck is a positive integer ($clk)" \
  || bad "plat_clk_tck='$clk'"
stopf="$scr/cpu.stop"; timesf="$scr/cpu.times"
( while [ ! -e "$stopf" ]; do :; done; times > "$timesf" ) & busy=$!
bt=0
for _ in $(seq 1 100); do                  # until the child has real CPU on record
  bt=$(plat_proc_table | awk -v p="$busy" '$1 == p { print $3 }')
  [ "${bt:-0}" -ge $((clk / 5)) ] && break
  sleep 0.2
done
: > "$stopf"; wait "$busy" 2>/dev/null
# `times` prints the shell's own user and system time first: "0m1.234s 0m0.010s"
own=$(head -1 "$timesf" 2>/dev/null | awk -v c="$clk" '
  function secs(t,  m) { m = t; sub(/m.*/, "", m); sub(/^[0-9]+m/, "", t); sub(/s$/, "", t); return m * 60 + t }
  { printf "%d\n", (secs($1) + secs($2)) * c }')
[ "${bt:-0}" -ge $((clk / 5)) ] && [ -n "$own" ] && [ "$bt" -le $((own + clk / 20)) ] && [ "$bt" -ge $((own / 2)) ] \
  && ok "a busy child's table ticks ($bt) agree with its own account ($own) at $clk/s — the unit holds" \
  || bad "busy child: table ticks '${bt}' against its own account '${own}' at clk=$clk — the cpu unit is wrong, and cpu_busy_pct with it"

ns=$(plat_now_ns); ns2=$(plat_now_ns)
[[ "$ns" =~ ^[0-9]{19}$ ]] && [ "$ns2" -ge "$ns" ] \
  && ok "plat_now_ns is 19 digits and monotone across two reads" \
  || bad "plat_now_ns '$ns' then '$ns2'"
[ $(( ns / 1000000000 - $(date +%s) )) -le 1 ] && [ $(( $(date +%s) - ns / 1000000000 )) -le 1 ] \
  && ok "…and agrees with date +%s" || bad "plat_now_ns is not epoch-based: $ns"

[ "$(TZ=UTC plat_epoch_fmt 0 '%Y-%m-%d %H:%M:%S')" = "1970-01-01 00:00:00" ] \
  && ok "plat_epoch_fmt renders an epoch with a strftime format" \
  || bad "plat_epoch_fmt 0 gave '$(TZ=UTC plat_epoch_fmt 0 '%Y-%m-%d %H:%M:%S')'"

printf 'abc' > "$scr/f"
[ "$(plat_stat_nsm "$scr/f" "$scr/missing")" = "$scr/f 3 $(date -r "$scr/f" +%s 2>/dev/null || stat -c %Y "$scr/f")" ] \
  && ok "plat_stat_nsm prints 'path size mtime' and skips a missing path silently" \
  || bad "plat_stat_nsm gave '$(plat_stat_nsm "$scr/f" "$scr/missing")'"

la=$(plat_loadavg)
[[ "$la" =~ ^[0-9.]+\ [0-9.]+\ [0-9.]+$ ]] && ok "plat_loadavg is three numbers ($la)" \
  || bad "plat_loadavg='$la'"

mkdir -p "$scr/tree/sub"; printf 'x\n' > "$scr/tree/sub/file"; ln -s sub "$scr/tree/link"
te=$(cd "$scr/tree" && plat_tree_entries | sort)
command grep -qE '^d [0-7]{3,4} \./sub$' <<< "$te" \
  && command grep -qE '^f [0-7]{3,4} \./sub/file$' <<< "$te" \
  && command grep -qE '^l [0-7]{3,4} \./link$' <<< "$te" \
  && ok "plat_tree_entries prints 'type mode path' for dirs, files and links" \
  || bad "plat_tree_entries shape: $(printf '%s' "$te" | tr '\n' '|')"

printf 'one\n' > "$scr/sedf"
plat_sed_i 's/one/two/' "$scr/sedf"
[ "$(cat "$scr/sedf")" = two ] && [ ! -e "$scr/sedf''" ] \
  && ok "plat_sed_i edits in place and leaves no backup file" \
  || bad "plat_sed_i result '$(cat "$scr/sedf")'"

# Contained, not equal: the terminal echoes what the pty sees (a BSD script
# reading /dev/null echoes the EOF as ^D), and that framing is not the claim.
pty=$(plat_pty_run '[ -t 0 ] && [ -t 1 ] && echo on-a-tty' 2>/dev/null | tr -d '\r')
command grep -q on-a-tty <<< "$pty" && ok "plat_pty_run gives the command a terminal" \
  || bad "plat_pty_run output '$pty' (script(1) spelling wrong for this host?)"
# …and a usable one whatever TERM the caller carries: CI and ssh sessions run
# with TERM=dumb, where tmux refuses to attach ("terminal does not support
# clear") and every attached-client arm in 80-pty would go vacuous.
dumb=$(TERM=dumb plat_pty_run 'tput clear > /dev/null 2>&1 && echo can-clear' 2>/dev/null | tr -d '\r')
command grep -q can-clear <<< "$dumb" && ok "plat_pty_run's terminal can clear even when the caller's TERM is dumb" \
  || bad "plat_pty_run under TERM=dumb gave a terminal tmux would refuse: '$dumb'"
nopty=$(bash -c '[ -t 0 ] && [ -t 1 ] && echo on-a-tty' < /dev/null 2>/dev/null | cat)
command grep -q on-a-tty <<< "$nopty" \
  && bad "the tty probe reports a terminal without one — the arm above proves nothing" \
  || ok "…and the same probe without a pty reports none (the arm discriminates)"

echo "-- darwin-bin stand-ins keep the semantics the tree uses (driven by path) --"
precond "the four stand-ins exist and are executable" \
  bash -c 'for c in md5sum timeout flock setsid; do [ -x "$1/$c" ] || exit 1; done' _ "$BIN"

[ "$(printf abc | "$BIN/md5sum")" = "900150983cd24fb0d6963f7d28e17f72  -" ] \
  && ok "md5sum: stdin prints '<hash>  -'" || bad "md5sum stdin: $(printf abc | "$BIN/md5sum")"
[ "$("$BIN/md5sum" "$scr/f")" = "900150983cd24fb0d6963f7d28e17f72  $scr/f" ] \
  && ok "md5sum: a file prints '<hash>  <name>'" || bad "md5sum file: $("$BIN/md5sum" "$scr/f")"
"$BIN/md5sum" "$scr/f" "$scr/missing" > "$scr/md5out" 2>/dev/null; rc=$?
[ $rc -eq 1 ] && [ "$(wc -l < "$scr/md5out")" -eq 1 ] \
  && ok "md5sum: a missing file is rc 1 and the readable one is still hashed" \
  || bad "md5sum missing-file rc=$rc"

"$BIN/timeout" 0.3 sleep 5; rc=$?
[ $rc -eq 124 ] && ok "timeout: the limit firing is rc 124" || bad "timeout fired rc=$rc"
"$BIN/timeout" 5 bash -c 'exit 7'; rc=$?
[ $rc -eq 7 ] && ok "timeout: the command's own rc passes through" || bad "timeout passthrough rc=$rc"
"$BIN/timeout" 1s true; rc=$?
[ $rc -eq 0 ] && ok "timeout: a unit suffix is accepted" || bad "timeout 1s rc=$rc"
"$BIN/timeout" 0.5 bash -c 'sleep 5 & sleep 5' ; rc=$?
[ $rc -eq 124 ] && ok "timeout: a command with children is ended as a group" || bad "timeout group rc=$rc"
"$BIN/timeout" 5 bash -c 'kill -TERM $$'; rc=$?
[ $rc -eq 143 ] && ok "timeout: death by signal N is 128+N" || bad "timeout signal rc=$rc"
"$BIN/timeout" -k 1 2 true 2>/dev/null; rc=$?
[ $rc -eq 125 ] && ok "timeout: an unsupported option is refused (125), never guessed" \
  || bad "timeout accepted an option it does not implement (rc=$rc)"

lk="$scr/lock"
( "$BIN/flock" -n 9 || exit 9; sleep 1.5 ) 9> "$lk" & holder=$!
sleep 0.5
( "$BIN/flock" -n 9 ) 9> "$lk"; rc=$?
[ $rc -eq 1 ] && ok "flock: -n on a held lock fails at once (and the holder's lock outlived its flock process)" \
  || bad "flock -n on a held lock rc=$rc"
t0=$(plat_now_ns)
( "$BIN/flock" -w 0.3 9 ) 9> "$lk"; rc=$?
dt=$(( ($(plat_now_ns) - t0) / 1000000 ))
[ $rc -eq 1 ] && [ "$dt" -ge 250 ] \
  && ok "flock: -w gives up after its wait (${dt}ms)" || bad "flock -w rc=$rc after ${dt}ms"
( "$BIN/flock" -w 5 9 ) 9> "$lk"; rc=$?
wait "$holder"; hrc=$?
[ $rc -eq 0 ] && [ $hrc -eq 0 ] && ok "flock: -w acquires once the holder's descriptor closes" \
  || bad "flock -w after release rc=$rc (holder rc=$hrc)"
"$BIN/flock" "$lk" true 2>/dev/null; rc=$?
[ $rc -eq 64 ] && ok "flock: the file/command form is refused by name (only the fd form is supported)" \
  || bad "flock file form rc=$rc"

"$BIN/setsid" sleep 2 & sp=$!
sleep 0.3
sid_line=$(ps -o pid= -o pgid= -p "$sp" 2>/dev/null)
kill "$sp" 2>/dev/null; wait "$sp" 2>/dev/null
set -- $sid_line
[ "${1:-}" = "$sp" ] && [ "${2:-}" = "$sp" ] \
  && ok "setsid: \$! names the command itself, and it leads its own group" \
  || bad "setsid: pid/pgid '$sid_line' for \$!=$sp"

echo "-- nothing outside platform.sh branches on the host --"
uses=$(cd "$WF_ROOT" && command grep -rnE '\buname\b|OSTYPE|\$PLATFORM\b' runtime-scripts self-check \
         --include='*.sh' 2>/dev/null \
       | command grep -v -e '^runtime-scripts/lib/platform.sh:' -e '^self-check/checks/05-platform.sh:')
[ -z "$uses" ] && ok "the host is decided in one file (lib/platform.sh)" \
  || bad "a second platform branch outside lib/platform.sh:"$'\n'"$(printf '%s\n' "$uses" | sed 's/^/    /')"
printf 'if [ "$(uname -s)" = Darwin ]; then :; fi\n' > "$scr/branchy.sh"
command grep -qE '\buname\b|OSTYPE|\$PLATFORM\b' "$scr/branchy.sh" \
  && ok "known-bad: the sweep's pattern sees a uname branch" \
  || bad "the one-home sweep's pattern is blind"

check_done
