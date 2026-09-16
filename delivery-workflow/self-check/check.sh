#!/usr/bin/env bash
# self-check/check.sh — the workflow-functional regression runner (dev-time,
# non-runtime; design/migration-and-acceptance.md §3). Runs when the workflow's
# own source changes, plus before any resume after a maintenance hold.
#
# Order is declared by filename prefix and is load-bearing:
#   1x store        — FIRST: everything else's fixtures stand on the store
#   2x config       — resolution + schema faults
#   3x closure      — cross-file referential integrity (stages/templates/schema/backends)
#   4x–8x mechanisms
#   9x drill        — end-to-end ferry scenarios against the mock CLI (tmux)
# A green MEANS: every selected check PASS, on a tree that did not move — a
# verdict about the checks, not about the schedule they ran under. The DEFAULT
# is `--jobs 12` — the gate, and the number both maintenance caps are
# calibrated on, so a bare invocation and the gate are the same run (by owner
# ruling; it was `--jobs 1` until 2026-09-02, which meant every bare run took
# ~6 minutes instead of 19s and produced per-check seconds no cap here is
# comparable against, while still being warned about). Serial is the same
# verdict measured one check at a time, asked for by name with `--jobs 1`, and
# kept for one use: diagnosing a red without concurrency in the room.
# Two maintenance quantities come off the per-check seconds: their SUM is
# the suite's tax (maintenance.suite_cap) and their MAX is the floor a parallel
# run cannot go under (maintenance.check_cap). Both are COLLECTED in either
# mode and COMPARED only under `--jobs > 1`, because both caps are calibrated
# on the parallel schedule — an earlier form of this line claimed they were
# "measured identically in both modes", which is false in the way that costs
# someone a day: serially a check runs about twice as long and the sum about
# half again, so the comparison reports the schedule rather than the suite. A
# serial run says so in a NOTE rather than going quiet, since a suppressed
# comparison must never read as a passed one.
# Isolation is already per-check — each owns its temp dirs, and every tmux user
# (each drill file and 80-pty) mktemps its own TMUX_TMPDIR — so what concurrency
# spends is timing margin, not safety. The runner MEASURES that rather than
# stating it: the workflow tree's hash set before the first check equals the
# set after the last (tree_snapshot / tree_verdict), and a difference voids
# the run.
#
# Exit: 0 all PASS (SKIPs allowed, each with a stated reason) · 1 any FAIL.
# rc 77 from a check = SKIP-with-notice (e.g. tmux absent).
#
# Operations doctrine: loadavg recorded at start and end — the loaded machine is
# the operating baseline; a red is diagnosed, never re-run-to-green.

set -uo pipefail
export LC_ALL=C
SC_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
export SELFCHECK_DIR="$SC_DIR"

usage() {
  echo "usage: check.sh [--list] [--only <name>] [--changed] [--jobs <n>] [--verbose]" >&2
  echo "  --jobs <n>  concurrent checks (default ${_SC_DEFAULT_JOBS:-12}; the maintenance caps are calibrated on it)" >&2
  echo "              --jobs 1 is the serial diagnosis form: same verdicts, no cap comparison" >&2
  echo "  names: $(list_names | tr '\n' ' ')" >&2
  exit 2
}

collect() { # -> "name<TAB>path" lines, declared order
  local f
  for f in "$SC_DIR"/checks/[0-9][0-9]-*.sh; do
    [ -e "$f" ] || continue
    printf '%s\t%s\n' "$(basename "$f" .sh | sed 's/^[0-9]*-//')" "$f"
  done
  # Every drill FILE, derived by glob rather than named: the drill split into a
  # ferry half and a probe half so the two can run concurrently under --jobs,
  # and a third would join by existing. drill/lib.sh and drill/mock-cli.sh do
  # not match, which is the point of the prefix.
  local d
  for d in "$SC_DIR"/drill/drill*.sh; do
    [ -e "$d" ] || continue
    printf '%s\t%s\n' "$(basename "$d" .sh)" "$d"
  done
}
list_names() { collect | cut -f1; }

# The commit gate is every check that can SEE the change — a rule with no
# judgment in it, so it is code rather than a habit. Prints the names to run,
# or NOTHING when the answer is "all of them".
#
# The test recognises the FORMAL DOC REGION and treats everything else as
# driver-side, rather than listing the driver's paths and treating the rest as
# safe. That direction is the whole point: an unrecognised path — a new
# top-level directory, a tool the drill learns to call, a file at the workflow
# root — must fall on the side that runs everything, not on the side that skips
# the drill. A list of dangers goes stale silently; a list of what is provably
# inert does not.
# Within the doc region only the checks that READ it can be affected, and that
# set is derived, never listed, so a new doc-reading check joins by existing. A
# check reaching those docs through an indirection instead of a literal path
# would still have to be added by hand.
#
# The judgment is pure — changed paths in, subset out — split from the git read
# below so it can be exercised on a fixed list rather than on whatever the tree
# happens to hold at the moment.
scope_for_files() { # <changed paths -> subset names, or empty for "run everything"
  local f n=0
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    n=$((n + 1))
    case "$f" in
      runtime-docs/templates/*) return 0 ;;    # parsed by drill + fixtures
      design/*|runtime-docs/*|discussion/*|README.md) : ;;
      *) return 0 ;;                           # anything else, known or new
    esac
  done
  [ "$n" -gt 0 ] || return 0        # nothing changed: stay conservative
  command grep -l 'design/\|runtime-docs/' "$SC_DIR"/checks/*.sh \
    | sed 's|.*/[0-9][0-9]-||; s|\.sh$||'
}
# The git read (arg for fixtures; the tree itself by default). UNTRACKED files
# count: a brand-new lib, check or declaration is exactly the change that most
# needs the whole suite, and `diff` alone cannot see one — it would be judged
# on its doc neighbours and gate on the subset.
# Not a git checkout / unreadable -> empty input -> all of them (fail-safe).
scope_for_changes() { # [repo-dir]
  local d=${1:-$SC_DIR/..}
  scope_for_files < <(
    git -C "$d" diff --name-only --relative HEAD 2>/dev/null
    git -C "$d" ls-files --others --exclude-standard 2>/dev/null
  )
}

# One way to RUN a check, shared by both modes, and it is bounded: a check
# still running at ten minutes is hung, not slow (the longest ever measured
# was 131s), and a hung check used to hang the whole suite — measured, when a
# fixture's virtual clock stopped advancing. `timeout` signals the check's
# process group, so its EXIT trap runs (a drill still kills its own tmux
# server) and the rc is 124, which the renderer names. The bound is a literal
# and deliberately not a config key: it is a property of this runner.
CHECK_TIMEOUT=600
run_check() { # path logfile -> rc
  timeout "$CHECK_TIMEOUT" bash "$1" > "$2" 2>&1
}
# Each check's last measured duration, the launch order's only input.
CHECK_DURATIONS_DIR="${TMPDIR:-/tmp}/dwsc-durations-$(id -u)"
record_duration() { # name secs
  mkdir -p "$CHECK_DURATIONS_DIR" 2>/dev/null && printf '%s\n' "$2" > "$CHECK_DURATIONS_DIR/$1" 2>/dev/null
  return 0
}
launch_order() { # <- "name" per line in declared order -> names, longest last-run first
  local name dur i=0
  while IFS= read -r name; do
    i=$((i + 1))
    dur=$(cat "$CHECK_DURATIONS_DIR/$name" 2>/dev/null); case "$dur" in ''|*[!0-9]*) dur=999999 ;; esac
    printf '%s\t%s\t%s\n' "$dur" "$i" "$name"
  done | sort -t$'\t' -k1,1nr -k2,2nr | cut -f3
}

# One rendering of a result, so the two run modes cannot drift into reporting
# the same verdict differently. Updates the counters, so never call it in a
# subshell.
SC_FAILDIR=""
SC_FAILDIR_KEEP=${SC_FAILDIR_KEEP:-10}   # how many failing-run directories survive
_keep_failing_log() { # name logfile — put a FAILING check's output where a filtered terminal cannot lose it
  # render() already prints the whole failing log, so this is not about the
  # runner being quiet: it is about the READER. Three reds have now been lost
  # to a terminal that was tailed or grepped — the previous round's, the
  # handoff's undiagnosed drill-backend, and one on this very commit's suite
  # run. The remedy has to survive the filter that causes it, so the path is
  # announced in the SUMMARY: `tail` keeps the end of a run by construction.
  # Never inside the tree — check.sh asserts the tree is unchanged by a run.
  if [ -z "$SC_FAILDIR" ]; then
    SC_FAILDIR=$(mktemp -d "${TMPDIR:-/tmp}/dwsc-failed.XXXXXX") || { SC_FAILDIR=""; return 0; }
    # BOUNDED, because this directory is deliberately not cleaned up on exit —
    # outliving the run is its entire purpose — and an unbounded keep is a leak.
    # Measured the night it was written: 78 directories in one session, mostly
    # from mutation runs. Pruned at CREATE rather than on a timer, oldest first,
    # never the one just made; the `case` is a second gate on the path so a
    # surprising TMPDIR cannot turn this into a wider delete than it reads as.
    # The trailing slash makes the glob match DIRECTORIES only, so the bound
    # counts what it keeps: with a plain `dwsc-failed.*` a stray file sharing
    # the prefix takes a keep slot and one more directory dies than the number
    # says (measured — the arm in `98-report` found it at 9 where 10 was meant).
    ls -dt "${TMPDIR:-/tmp}"/dwsc-failed.*/ 2>/dev/null | tail -n +$((SC_FAILDIR_KEEP + 1)) \
    | while IFS= read -r _old; do
        _old=${_old%/}
        [ "$_old" = "$SC_FAILDIR" ] && continue
        case "$_old" in */dwsc-failed.??????) [ -d "$_old" ] && rm -rf -- "$_old" ;; esac
      done
  fi
  cp -f "$2" "$SC_FAILDIR/$1.log" 2>/dev/null || true
}

render() { # name rc seconds logfile
  # The per-check seconds are the two maintenance quantities' only source:
  # their SUM is the tax a serial run pays, their MAX is the floor a parallel
  # run cannot go under. Accumulated here so both modes measure identically.
  SUM_SECS=$((SUM_SECS + $3))
  [ "$3" -gt "$MAX_SECS" ] && { MAX_SECS=$3; MAX_NAME=$1; }
  case "$2" in
    0)
      PASS=$((PASS + 1))
      echo "PASS $1 (${3}s) $(tail -1 "$4" | sed 's/^ *//')"
      [ "$VERBOSE" -eq 1 ] && sed 's/^/    /' "$4" ;;
    77)
      SKIP=$((SKIP + 1))
      echo "SKIP $1 — $(command grep -m1 '^SKIP:' "$4" | sed 's/^SKIP: *//')"
      [ "$VERBOSE" -eq 1 ] && sed 's/^/    /' "$4" ;;
    124)
      FAIL=$((FAIL + 1)); FAILED_NAMES="$FAILED_NAMES $1"
      echo "FAIL $1 (rc=124, TIMED OUT at ${CHECK_TIMEOUT}s — a hung check, not a slow one) — output so far:"
      sed 's/^/    /' "$4"
      _keep_failing_log "$1" "$4" ;;
    *)
      FAIL=$((FAIL + 1)); FAILED_NAMES="$FAILED_NAMES $1"
      echo "FAIL $1 (rc=$2, ${3}s) — full output:"
      sed 's/^/    /' "$4"
      _keep_failing_log "$1" "$4" ;;
  esac
  return 0
}

# The concurrent driver. What makes it sound is that isolation is per-check —
# every check owns its temp dirs, every tmux user mktemps its own server — and
# the runner measures that at both ends of every run (tree_snapshot). Measured
# on a 32-core box (2026-08-23, after two optimisation rounds): 20s at -j12,
# the wall being the slowest check, peak load ~5 of 32 — -j12 is the gate by
# the owner's choice, leaving the box usable; serial 360s.
#
# What concurrency spends is timing MARGIN, and the one measured loss is worth
# keeping because its diagnosis moved: a -j12 run had 75-watch's idle-noise arm
# report `FAIL timeout` where it wanted `FAIL idle`, and it was read as a
# concurrency effect — until the arm was measured directly (a driver that
# stretches each loop iteration): its ladder landed at about 6 + 1.6x the
# stretch against a stage_timeout of 6, so ANY ~2s stretch lost the race, and a
# serial run at loadavg 8.7 reproduced it. Concurrency was never the cause; a
# fixture whose deadlines sit seconds apart measures the machine. That arm now
# runs on the wait loop's virtual clock (watch.sh's _wt_now/_wt_sleep seams),
# which retires the class inside that check. So: a red under -j is diagnosed
# like any other, never re-run-to-green; the first question is still whether
# it is a timing arm measuring the machine, the second whether serial
# reproduces it — serial is the fallback MEASUREMENT, not a different truth.
#
# LAUNCH order is longest-first, from each check's MEASURED duration on its
# last run (longest-processing-time, the standard bounded-pool order): the
# declared order groups by concern, and which checks are long changes as the
# tree is tuned — the drills were the long tail once, then `halt` and `record`
# sat mid-order running past everyone after the drills were split, and the
# wall carried a 6s scheduling tail over the slowest check. A check with no
# recorded duration launches first (unknown reads as long), and with no
# records at all the order is the declared order reversed, which is what it
# always was. Durations are one small file per check name under a user-scoped
# tmp dir, written by both modes after each check. Results still RENDER in
# declared order, so the store's verdict is the first thing read.
# PURE: it runs the checks and PRINTS a results table. It does not render and
# does not touch the counters — because a driver that reports through shell
# state can be silently disarmed by calling it on the wrong side of a pipe, and
# the symptom of that is a GREEN SUMMARY OVER A RED CHECK. Rendering happens
# once, in main's own shell, for both modes. The caller owns the temp dir.
run_parallel() { # tmpdir <- "name<TAB>path" on stdin -> "name<TAB>rc<TAB>secs<TAB>log" in declared order
  local tmpd=$1 name path nm rc secs
  local -a ORDER=()
  while IFS=$'\t' read -r name path; do
    ORDER+=("$name"); printf '%s\n' "$path" > "$tmpd/$name.path"
  done
  while IFS= read -r nm; do
    while [ "$(jobs -rp | command grep -c .)" -ge "$JOBS" ]; do wait -n 2>/dev/null || break; done
    ( t1=$(date +%s)
      run_check "$(cat "$tmpd/$nm.path")" "$tmpd/$nm.log"; rc=$?; secs=$(( $(date +%s) - t1 ))
      record_duration "$nm" "$secs"
      printf '%s %s\n' "$rc" "$secs" > "$tmpd/$nm.rc" ) &
  done < <(printf '%s\n' "${ORDER[@]}" | launch_order)
  wait
  for nm in "${ORDER[@]}"; do
    # An absent rc file means the job never wrote one: report it as a failure
    # rather than skipping the row, or a lost check would read as no check.
    read -r rc secs < "$tmpd/$nm.rc" 2>/dev/null || { rc=1; secs=0; }
    printf '%s\t%s\t%s\t%s\n' "$nm" "${rc:-1}" "${secs:-0}" "$tmpd/$nm.log"
  done
}

# Isolation, measured. The suite must leave the workflow tree byte-identical:
# every entry under the workflow root is listed (kind, mode, path) and every
# regular file hashed, before the first check is dispatched and again after the
# last one returns, and a difference VOIDS the run — a check wrote into the
# tree, or the tree was edited while the gate ran; the two are one verdict,
# because a green over a tree that moved under it is a green about nothing.
# The assertion lives in the driver and not in a check because only the driver
# can take the "before": a check runs beside the others under --jobs and would
# measure a tree in motion. The entry count is printed and never asserted — it
# grows with the tree. 98-report proves both functions on a fixture directory;
# the wiring in main is exercised by every run (the `tree:` summary line).
tree_snapshot() { # root -> sorted "kind mode path" for every entry + "md5  path" for every regular file
  ( cd "$1" 2>/dev/null || exit 1
    find . -path ./.git -prune -o -printf '%y %m %p\n'
    find . -path ./.git -prune -o -type f -print0 | xargs -0 -r md5sum
  ) | sort
}
tree_verdict() { # before-file after-file -> the summary line(s); rc 1 when they differ
  local n
  n=$(command grep -c '^[a-z] ' "$1")
  if cmp -s "$1" "$2"; then
    echo "tree: unchanged ($n entries, before and after)"; return 0
  fi
  echo "tree: MUTATED while the suite ran — this run's verdict is VOID (a check wrote into the workflow tree, or it was edited during the gate):"
  diff "$1" "$2" | command grep '^[<>]' | sed 's/^< /    before: /; s/^> /    after:  /'
  return 1
}

# A green needs a denominator, PER COLLECTION SOURCE. Measured before this
# floor existed, on trial trees: emptying checks/ left the drills to carry a
# green "11 passed, 0 failed" over 21 checks that never ran, and emptying both
# globs read green at "0 passed, 0 failed, 0 skipped". Each half of collect()
# floors at one file — an emptied or renamed glob is a broken collection, not
# a scoped run: --only/--changed filter AFTER collection and say so in the
# header, so they are unaffected by construction. Both directions proved in
# 98-report against this real function; the wiring in main is exercised by
# every run (a healthy run's counts are its summary line).
collection_floor() { # n_checks n_drills -> FAIL line(s) + rc 1 when a source went empty
  local rc=0
  if [ "$1" -lt 1 ]; then
    echo "FAIL: the checks/ collection matched nothing — self-check/checks/[0-9][0-9]-*.sh is empty (emptied or renamed?); ${2} drill file(s) would carry a green verdict over checks that never ran"
    rc=1
  fi
  if [ "$2" -lt 1 ]; then
    echo "FAIL: the drill collection matched nothing — self-check/drill/drill*.sh is empty (emptied or renamed?); the end-to-end scenarios never ran"
    rc=1
  fi
  return "$rc"
}

# The DEFAULT schedule, and it is 12 rather than 1 (owner ruling, 2026-09-02).
# Both maintenance caps are calibrated on this number, so a bare run and the
# gate are now the same run: a bare `check.sh` used to be `--jobs 1`, take ~6
# minutes against 19 seconds, and produce per-check seconds that no cap in the
# tree is comparable against — which is exactly how a maintainer spent a
# session chasing two WARNs that did not exist.
# WHY IT COSTS NO CORRECTNESS, which was the ruling's condition. Structurally:
# both modes share ONE renderer, `run_parallel` is pure (it returns a table and
# touches no shell state, so a red cannot hide behind a green summary), rows
# come back in DECLARED order carrying real exit codes, and both paths bound a
# check through one `run_check` — all four proven in 98-report against this
# code. By isolation: every check owns its temp dirs and every tmux user
# mktemps its own TMUX_TMPDIR, so concurrency spends timing margin, not safety.
# And measured, over this tree in one session: 14 full parallel runs with zero
# failures against 7 serial runs with one (a `drill-reslice` flake) — the only
# observed flake was in the mode being replaced.
# A fixed literal rather than nproc, deliberately: a per-machine job count
# would make the caps incomparable between runs, which is the defect this
# ruling exists to close. On a smaller box pass `--jobs <n>` explicitly and
# read the caps as not applying.
_SC_DEFAULT_JOBS=12
main() {
  ONLY="" LIST=0 VERBOSE=${VERBOSE:-0} SUBSET="" JOBS=$_SC_DEFAULT_JOBS
  while [ $# -gt 0 ]; do
    case "$1" in
      --list) LIST=1; shift ;;
      --only) ONLY=${2:?--only needs a name}; shift 2 ;;
      --changed) SUBSET=$(scope_for_changes); shift ;;
      --jobs) JOBS=${2:?--jobs needs a count}; shift 2
              case "$JOBS" in ''|*[!0-9]*) echo "--jobs takes a number" >&2; exit 2 ;; esac ;;
      --verbose) VERBOSE=1; shift ;;
      *) usage ;;
    esac
  done
  if [ "$LIST" -eq 1 ]; then list_names; exit 0; fi
  if [ -n "$ONLY" ] && ! list_names | command grep -qxF "$ONLY"; then
    echo "unknown check '$ONLY'" >&2; usage
  fi
  # Count the collection BEFORE running anything: a broken glob fails fast
  # instead of spending the suite's wall on a verdict that is already void.
  # The loops mirror collect()'s own guards so the two cannot disagree on
  # what counts as present.
  local f n_checks=0 n_drills=0
  for f in "$SC_DIR"/checks/[0-9][0-9]-*.sh; do [ -e "$f" ] && n_checks=$((n_checks + 1)); done
  for f in "$SC_DIR"/drill/drill*.sh; do [ -e "$f" ] && n_drills=$((n_drills + 1)); done
  if ! collection_floor "$n_checks" "$n_drills"; then
    FAIL=1; FAILED_NAMES=" suite-collection"
    echo "-----------------------------------------------"
    echo "summary: 0 passed, $FAIL failed, 0 skipped"
    echo "failed:$FAILED_NAMES"
    exit 1
  fi

  echo "== delivery-workflow self-check =="
  echo "workflow root: $(cd "$SC_DIR/.." && pwd)"
  [ -n "$SUBSET" ] && echo "scope: changed files touch the formal doc region only -> $(printf '%s' "$SUBSET" | tr '\n' ' ')"
  LOAD_START=$(cat /proc/loadavg 2>/dev/null || echo unavailable)
  echo "loadavg start: $LOAD_START"
  T0=$(date +%s)

  PASS=0; FAIL=0; SKIP=0; FAILED_NAMES=""; SUM_SECS=0; MAX_SECS=0; MAX_NAME=""; SC_FAILDIR=""
  # The fixtures below are what grows lib/config.sh's memo dir (per-run tmp
  # paths in kv content), so this is where it is pruned — once, before the
  # first check, in a subshell so the runner's own shell sources nothing.
  ( . "$SC_DIR/../runtime-scripts/lib/config.sh" && config_memo_prune )
  local snap_before snap_after
  snap_before=$(mktemp "${TMPDIR:-/tmp}/dwsc-tree.XXXXXX") || { echo "cannot make a temp file" >&2; exit 3; }
  snap_after=$(mktemp "${TMPDIR:-/tmp}/dwsc-tree.XXXXXX")  || { echo "cannot make a temp file" >&2; exit 3; }
  tree_snapshot "$SC_DIR/.." > "$snap_before"
  # Filter ONCE, so the two run modes agree on the set by construction.
  selected() {
    local name path
    while IFS=$'\t' read -r name path; do
      [ -n "$ONLY" ] && [ "$name" != "$ONLY" ] && continue
      [ -n "$SUBSET" ] && ! printf '%s\n' "$SUBSET" | command grep -qxF "$name" && continue
      printf '%s\t%s\n' "$name" "$path"
    done < <(collect)
  }
  if [ "$JOBS" -gt 1 ]; then
    echo "mode: PARALLEL -j$JOBS (the gate; serial is for diagnosing a red without concurrency)"
    local ptmp name rc dt log
    ptmp=$(mktemp -d "${TMPDIR:-/tmp}/dwsc-par.XXXXXX") || { echo "cannot make a temp dir" >&2; exit 3; }
    # `< <(...)`, never a pipe: render must run in THIS shell or its counters
    # are lost and a red check would ride under a green summary.
    while IFS=$'\t' read -r name rc dt log; do
      render "$name" "$rc" "$dt" "$log"
    done < <(selected | run_parallel "$ptmp")
    rm -rf "$ptmp"
  else
    local name path log t1 rc dt
    while IFS=$'\t' read -r name path; do
      log=$(mktemp "${TMPDIR:-/tmp}/dwsc-log.XXXXXX")
      t1=$(date +%s)
      run_check "$path" "$log"
      rc=$?
      dt=$(( $(date +%s) - t1 ))
      record_duration "$name" "$dt"
      render "$name" "$rc" "$dt" "$log"
      rm -f "$log"
    done < <(selected)
  fi
  tree_snapshot "$SC_DIR/.." > "$snap_after"

  echo "-----------------------------------------------"
  echo "summary: $PASS passed, $FAIL failed, $SKIP skipped"
  [ -n "$FAILED_NAMES" ] && echo "failed:$FAILED_NAMES"
  [ -n "$SC_FAILDIR" ] && echo "failing output kept: $SC_FAILDIR — the terminal is no longer the only copy, so a run that was tailed or grepped still has the assertion"
  local tree_ok=1
  tree_verdict "$snap_before" "$snap_after" || tree_ok=0
  rm -f "$snap_before" "$snap_after"
  LOAD_END=$(cat /proc/loadavg 2>/dev/null || echo unavailable)
  echo "loadavg start: $LOAD_START"
  echo "loadavg end:   $LOAD_END"
  WALL=$(( $(date +%s) - T0 ))
  echo "wall: ${WALL}s (checks sum ${SUM_SECS}s; slowest ${MAX_NAME:-none} ${MAX_SECS}s)"
  # BOTH time caps are calibrated on the PARALLEL schedule and neither is
  # comparable against a serial run. suite_cap always knew this — a serial sum
  # reads ~50% higher for the same work (one busy core on a powersave governor:
  # measured, 360s against 227–247s). check_cap did NOT, and the asymmetry was
  # a live defect: its own calibration note says 30 was set to clear the -j12
  # band of 18–20s, and a serial run pays roughly double PER CHECK, so it fired
  # on healthy checks. Measured on one tree, same commit, both modes: `record`
  # 18s parallel / 44s serial, `drill-reslice` 19s parallel / 36s serial —
  # two WARNs, both false, and a maintainer spent a session chasing them.
  # AND THE SUPPRESSION IS NOW SPOKEN. Silently dropping the comparison made a
  # serial run's silence indistinguishable from passing, which is the
  # absent-is-not-zero rule this tree applies everywhere else (derive_cost
  # names an unreadable ledger; derive_report prints the closed set with its
  # zeros). The NOTE below is the same duty: say that the caps were not read.
  # The vd_open_cap is NOT gated — it counts rows in a file, which no schedule
  # changes.
  # ONE predicate — "are the time caps comparable against this run?" — and one
  # suppression path that must speak. Two conditions make them incomparable and
  # they are the same question one step apart: did this run get the schedule the
  # caps were calibrated on?
  load_end_1m=$(printf '%s' "${LOAD_END:-}" | awk '{printf "%d", $1}')
  if caps_comparable "$JOBS" "${load_end_1m:-0}"; then
    maintenance_warns "$SUM_SECS" "" "$MAX_SECS" "$MAX_NAME"
  else
    maintenance_warns "" "" "" ""
    if [ "$JOBS" -le 1 ]; then
      echo "NOTE: serial run (--jobs 1) — the two TIME caps were not compared. Both are calibrated on the -j12 schedule this runner calls the gate; serially a check costs ~2x and the sum ~50% more, so a comparison here reports the schedule, not the suite. Slowest this run: ${MAX_NAME:-none} ${MAX_SECS}s (sum ${SUM_SECS}s) — for the gate's numbers, rerun with --jobs 12."
    else
      echo "NOTE: loaded run (loadavg end ${LOAD_END%% *} >= --jobs $JOBS) — the two TIME caps were not compared. Both are calibrated on a QUIET box, so a machine carrying more than this suite reports its own schedule, not the suite's cost. This run: ${MAX_NAME:-none} ${MAX_SECS}s (sum ${SUM_SECS}s) — for the gate's numbers, rerun when the box is quiet."
    fi
  fi
  [ "$FAIL" -eq 0 ] && [ "$tree_ok" -eq 1 ]
}

# maintenance WARN thresholds (owner-ruled — WARN only: visibility, never a
# gate; over-cap ⇒ maintenance brief, the owner decides). Data lives in
# dev-time (this tree), not the topic store — which is why the WARN rides THIS
# summary and not derive_report. Three quantities, each against its own cap:
# the sum of per-check seconds (the tax), the slowest single check (the floor),
# the open validation-debt rows.
# THE TWO TIME QUANTITIES ARE COLLECTED IDENTICALLY IN BOTH MODES AND ARE NOT
# COMPARABLE ACROSS THEM, and the difference is the one this comment used to
# get wrong. It said the sum was "the same number in both modes" — with the
# measurement that disproves it in the same parenthesis (a serial run pays
# ~190s more for the same work: 544s serial against 346–358s at -j12, one busy
# core at ~3.1 GHz against twelve boosting to 5.4). What IS mode-independent is
# the ACCUMULATION — one `render` path, both modes — and what is not is the
# value. Both caps are calibrated on the parallel schedule, so main() passes
# both quantities only under `--jobs > 1` and says so otherwise. The vd count
# is mode-free: it counts rows in a file.
# An empty argument means "not measured this run" and compares against nothing.
# A function so 98-report proves both directions of each against the real code,
# and its call site so 98-report can prove the mode gating too — every arm here
# drives this function with explicit arguments and none of them can see what
# main() actually passes, which is how the gating stayed wrong.
# Are the two TIME caps comparable against THIS run? A named predicate rather
# than an inline condition, because it is the one thing here a fixture can drive
# in every direction without owning a machine: `98-report` calls it with the
# combinations, where a behavioural test would depend on the ambient loadavg —
# a fixture measuring the machine, the shape this suite refuses everywhere else.
#
# Both caps are calibrated on -j12 AND on a quiet box (`defaults.kv` states the
# method: "OUT of its measured noise band with ~20% margin", band measured over
# six quiet runs). So both terms are one question: did this run get the schedule
# the caps were calibrated on? Serially a check costs ~2x; on a loaded box the
# suite reports the machine. Measured over seven runs of one afternoon, split by
# each run's OWN end loadavg: quiet 294 · 296 · 300 · 305s, all inside the band;
# loaded 337 · 361 · 387s, two over cap and neither of them growth. The load
# threshold is $JOBS rather than a fitted number — the suite is GIVEN that many
# jobs, so a machine carrying more than that was carrying more than the suite.
caps_comparable() { # jobs load-1m -> rc 0 when the time caps may be compared
  [ "${1:-0}" -gt 1 ] && [ "${2:-0}" -lt "${1:-0}" ]
}

maintenance_warns() { # [checks-sum-seconds] [vd-open-count] [slowest-secs] [slowest-name] — prints WARN lines when over cap
  local sum=${1:-} vd_open=${2:-} slow=${3:-} slow_name=${4:-}
  local cap
  cap=$(sed -n 's/^maintenance\.suite_cap=//p' "$SC_DIR/../config/defaults.kv" | head -1)
  if [ -n "$cap" ] && [ -n "$sum" ] && [ "$sum" -gt "$cap" ]; then
    echo "WARN: checks sum ${sum}s > maintenance.suite_cap=${cap}s — the verification tax grew; ⇒ maintenance brief (owner decides: split/slow the suite, or accept)"
  fi
  cap=$(sed -n 's/^maintenance\.check_cap=//p' "$SC_DIR/../config/defaults.kv" | head -1)
  if [ -n "$cap" ] && [ -n "$slow" ] && [ "$slow" -gt "$cap" ]; then
    echo "WARN: slowest check ${slow_name} ${slow}s > maintenance.check_cap=${cap}s — the gate's floor is one check's length; ⇒ maintenance brief (owner decides: split that file's scenarios, or accept)"
  fi
  cap=$(sed -n 's/^maintenance\.vd_open_cap=//p' "$SC_DIR/../config/defaults.kv" | head -1)
  if [ -n "$cap" ]; then
    [ -z "$vd_open" ] && vd_open=$(awk '/^## (closed|standing)/{done=1} !done && /^\| VD-[0-9]+ \|/' "$SC_DIR/validation-debt.md" 2>/dev/null | grep -c . || true)
    [ "${vd_open:-0}" -gt "$cap" ] && \
      echo "WARN: open validation-debt rows ${vd_open} > maintenance.vd_open_cap=${cap} — mechanisms accumulating faster than live evidence closes them; ⇒ maintenance brief"
  fi
  return 0
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && main "$@"
