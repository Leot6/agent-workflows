#!/usr/bin/env bash
# lib/readers.sh — the status verb's table readers (--slices, --rounds, --halt),
# sourced by launch.sh. Each is a separate small reader over surfaces that
# already exist (the panel's layout is pinned; a dump is not a panel), with the
# reader discipline the tree holds everywhere: fault != absent, absent != empty,
# and nothing is derived from a surface other than the one named. This file
# exists because launch.sh crossed cap.source_file once the --rounds reader
# landed — the split is along the seam the caps pointed at.

# --- status --slices: the per-slice table (config-and-adapters.md §6).
# A SEPARATE small reader, deliberately not part of the live panel: seventeen
# slices is a dump, not a panel, and the panel's layout is pinned. Every
# quantity comes from a surface that already exists — attempts (`slice.<nn>.
# started`, `parked.<nn>`), the ledger (a slice ENDS at its `advance …
# stage=turnover verdict=done`, and its backend is the `spawn` event's own
# field) — so this adds no surface, no writer and no projection.
_st_kv() { printf '%s\n' "$1" | awk -F= -v k="$2" '$1==k{v=substr($0,length(k)+2)} END{print v}'; }
# 45s / 13m / 1h12m / 2d3h. A deliberate second copy of the monitor's fmt_dur,
# for the reason the monitor keeps its own copy of the adapter's cell walk: a
# reader must not depend on another renderer's internals to lay out a line.
_st_dur() { # seconds
  local s=$1
  case "$s" in ''|*[!0-9]*) printf '?'; return 0 ;; esac
  if   [ "$s" -lt 60 ];    then printf '%ds' "$s"
  elif [ "$s" -lt 3600 ];  then printf '%dm' "$((s / 60))"
  elif [ "$s" -lt 86400 ]; then printf '%dh%02dm' "$((s / 3600))" "$(((s % 3600) / 60))"
  else                          printf '%dd%dh' "$((s / 86400))" "$(((s % 86400) / 3600))"
  fi
}
status_slices() {
  local idx att led now tset row id st risk started parked endt work total bl b extra line rc ba br
  # fault != absent, here as everywhere: a corrupt index must not read as "no
  # slices yet", which is a perfectly ordinary pre-split state.
  idx=$(state_get "$WS" slices 2>/dev/null); rc=$?
  [ $rc -eq 3 ] && refuse "the slices surface is CORRUPT (checksum/parse) — not absent; inspect $WS/.runtime/state/slices before reading anything off it"
  [ $rc -eq 0 ] || refuse "no slices index yet — split has not run for this topic"
  # fault != absent holds for the SECONDARY surfaces too, not only the index: a
  # corrupt attempts surface collapsing to empty renders every clock as "-" (a
  # table quietly claiming no slice ever started), and a corrupt ledger
  # collapsing to empty drops every slice's turnover end (clocks run on to now)
  # and every off-assignment backend — a live-looking table over a broken
  # source, which is the shape the rc-3 refusal exists to prevent.
  att=$(state_get "$WS" attempts 2>/dev/null); rc=$?
  [ $rc -eq 3 ] && refuse "the attempts surface is CORRUPT (checksum/parse) — not absent; the clocks cannot be read over it; inspect $WS/.runtime/state/attempts before trusting any duration here"
  led=$(state_get "$WS" ledger 2>/dev/null); rc=$?
  [ $rc -eq 3 ] && refuse "the ledger surface is CORRUPT (checksum/parse) — not absent; slice ends and backends cannot be read over it; inspect $WS/.runtime/state/ledger before trusting any clock here"
  # A rotated ledger means turnover ends and spawn backends before the last
  # rotation are NOT in this segment: a done slice whose turnover row was
  # rotated away reads as still running (its total clock grows with the wall
  # clock). The glob, never `printf | grep -q` (the R19 SIGPIPE rule — a
  # rotated ledger is by definition near the 8000-row cap, ~600KB).
  if [[ $led == *event=rotated* ]]; then
    echo "NOTE: the ledger has rotated — turnover ends and backends before the last rotation are not in this segment; a done slice may read with a growing total. See the rotated_to= row on the ledger."
  fi
  now=$(date +%s)
  # The topic-level assignment is the NORM; the backend column names EXCEPTIONS
  # only, so a single-backend topic pays nothing for it.
  # Resolved into locals FIRST: read through a command substitution, a resolver
  # fault would collapse to the empty string and every backend would then render
  # as an exception — a table quietly claiming the whole run went off-assignment.
  ba=$(config_get agent.author.backend --topic-dir "$WS") \
    || refuse "config fault resolving agent.author.backend — this table cannot name the topic-level assignment, so it will not guess one (plain 'status' still works)"
  br=$(config_get agent.reviewer.backend --topic-dir "$WS") \
    || refuse "config fault resolving agent.reviewer.backend — see above"
  tset=" $ba $br "
  printf '%-6s %-11s %-5s %-26s %s\n' slice status risk 'clocks (work · total)' 'backend, where it differs'
  while IFS= read -r row; do
    id=$(printf '%s\n' "$row" | command grep -oE '(^| )id=[^ ]+' | head -1 | cut -d= -f2)
    [ -n "$id" ] || continue
    st=$(printf '%s\n' "$row" | command grep -oE '(^| )status=[^ ]+' | head -1 | cut -d= -f2)
    risk=$(printf '%s\n' "$row" | command grep -oE '(^| )risk=[^ ]+' | head -1 | cut -d= -f2)
    started=$(_st_kv "$att" "slice.$id.started")
    parked=$(_st_kv "$att" "parked.$id"); case "$parked" in ''|*[!0-9]*) parked=0 ;; esac
    # A slice ends at its turnover's advance — the ledger, never the attempts
    # surface, for the reason the monitor's stage bar reads the same source:
    # round.<s>.<st> means ENTERED, so a parked stage would read as finished.
    endt=$(printf '%s\n' "$led" \
      | command grep -E '(^| )event=advance( |$)' \
      | command grep -E "(^| )slice=$id( |$)" \
      | command grep -E '(^| )stage=turnover( |$)' \
      | command grep -E '(^| )verdict=done( |$)' \
      | tail -1 | command grep -oE '(^| )t=[0-9]+' | tail -1 | cut -d= -f2)
    case "$started" in
      ''|*[!0-9]*) work="-"; total="-" ;;
      *) case "$endt" in ''|*[!0-9]*) endt=$now ;; esac
         work=$(_st_dur "$(( endt - started - parked > 0 ? endt - started - parked : 0 ))")
         total=$(_st_dur "$(( endt - started > 0 ? endt - started : 0 ))") ;;
    esac
    bl=$(printf '%s\n' "$led" \
      | command grep -E '(^| )event=spawn( |$)' \
      | command grep -E "(^| )slice=$id( |$)" \
      | command grep -oE '(^| )backend=[^ ]+' | cut -d= -f2 | sort -u)
    extra=""
    while IFS= read -r b; do
      [ -n "$b" ] || continue
      case "$tset" in *" $b "*) : ;; *) extra="$extra${extra:+,}$b" ;; esac
    done <<< "$bl"
    # BOTH clocks, both LABELLED: working is what the budgets spend
    # (check_budgets subtracts credited park intervals), total is what a human
    # feels. Rendering either alone reproduces the elapsed-vs-timeout misread
    # §6 was written about.
    line=$(printf '%-6s %-11s %-5s %-26s %s' "$id" "${st:-?}" "${risk:-?}" "work $work · total $total" "$extra")
    printf '%s\n' "${line%"${line##*[![:space:]]}"}"   # rtrim: the column pad is invisible on screen, not in a capture
  done <<< "$(printf '%s\n' "$idx" | sort)"
  printf '\n  work excludes credited park intervals — it is the clock budget.slice_wallclock meters;\n'
  printf '  total is wall time since the slice started. backend is listed only for a slice that ran\n'
  printf '  on one the topic level does not name (%s), so one backend everywhere leaves it empty.\n' \
    "$(printf '%s\n' "$tset" | tr ' ' '\n' | command grep -v '^$' | sort -u | paste -sd+ - | sed 's/+/ + /g')"
}

# --- status --rounds: the per-stage per-round clock (a pure reader over the
# ledger's own t= fields) ---
# Nothing reads the run's timestamps mid-run: --slices gives two numbers per
# slice, and the per-round breakdown that answers "where did the time go" had
# no reader — the pilot who needed one hand-rolled it over the ledger, and the
# hand-rolled instrument silently dropped events for ninety minutes (the exact
# failure shape a first-party reader exists to retire: every pilot builds
# their own, each gets their own version wrong, and none of them is covered by
# self-check). A round OPENS at `enter` and CLOSES at the next `advance` for
# the same (slice, stage); a park inside the round is annotated with its
# reason and the gap it held, so a round whose wall is mostly park reads as
# parked, not as slow work. Ledger fields only: no attempts surface, no credit
# arithmetic — the table says exactly what the ledger can say. A park gap
# closes at the FIRST of: a later park row (the halt was superseded), the
# first ferry_start after it, or the stage's next event — see the rule comment
# in the program below for the measured cases that rule carries. A park whose
# row has no open round behind it (no stage on the row, or the stage has no
# open round) rides the OUT-OF-ROUND lane: reported in the tail line with the
# stage named when it has one, closed by a later park, a ferry_start, or any
# enter — a bare record or spawn does not discharge a halt.
#
# An open round (enter, no advance) renders RUNNING only when it IS the
# frontier round — the round the last KEYED event attributed to, or the
# round the park/ferry_start pairing restored (the machine is stated in the
# program below: attribution, the pairing, the enter-retire, the guard).
# Behind the frontier it renders OPEN: the ledger cannot claim a round is
# running when later events belong to other stages. And a ledger whose final event is `complete` (every
# archived delivery topic ends with exactly that row) is FINISHED: its open
# rounds close at the completion timestamp, so an archived reading is frozen
# and reproducible rather than growing with the wall clock.
#
# Reconciliation against the ferry's own books (parked_total / audit credit
# rows), measured from raw timestamps over every real store: the five modern
# archives agree to seconds (exact over a single park; +3s over 14 parks;
# +2s over 9; +4s over 11; one trivially, with 0 parks; the live topic's
# closed parks
# reconcile against its audit rows to the second, re-derived from raw
# timestamps at each reading — the count is the live topic's own clock, not
# this comment's, so it is not written here). The OLDEST store reads 174573s
# parked against a parked_total of 20296:
# the difference is concentrated in three ruling-gated parks (an 18.4h class_u,
# a 15.4h blocked, an 8.3h class_u) whose credit that era's resume gate never
# wrote — the current one books ruling-cleared parks (lib/resume.sh, the
# _resume_credit_park call in the ruling-cleared branch). The reader's census
# is the honest park-time; parked_total is budget credit, and the two are the
# same number only where the ferry booked every park. A park still open at
# read time renders PARKED and its gap grows with the watch — liveness, not
# divergence.
status_rounds() {
  local led rc now
  led=$(state_get "$WS" ledger 2>/dev/null); rc=$?
  # fault != absent, in this reader too: a corrupt ledger refused here is what
  # keeps this table from quietly omitting the rounds a corruption happened in.
  [ $rc -eq 3 ] && refuse "the ledger surface is CORRUPT (checksum/parse) — not absent; inspect $WS/.runtime/state/ledger before reading anything off it"
  [ $rc -eq 0 ] || refuse "no ledger on record for topic $TOPIC — the topic has never run"
  # The EMPTY test is "no parseable event rows", the parser's OWN predicate —
  # never a version prefix: the awk below keys on event=/t= and would happily
  # read a future row spelling, so gating the empty message on '^v=1 ' would
  # call a v-next ledger EMPTY over rows the parser would have rendered (guard
  # stricter than parser, lying in between). A valid-checksum ledger with no
  # event rows cannot come from the writer, so "no event=" is the honest empty.
  # The test is a shell glob, never `printf | grep -q`: under set -o pipefail
  # (launch.sh sets it), grep -q exits at its FIRST match and printf keeps
  # writing — on a ledger past the ~64KB pipe buffer that is SIGPIPE (141),
  # which the `if !` read as EMPTY. Measured: a 2001-row ledger rendered "the
  # ledger is EMPTY" through exactly this pipe (round 19; ~900 rows is the
  # threshold — a long topic's ledger crosses it).
  if [[ $led != *event=* ]]; then
    echo "the ledger is EMPTY — the topic has recorded no events yet"
    return 0
  fi
  now=$(date +%s)
  printf '%s\n' "$led" | awk -v now="$now" '
    function kv(line, key,  i, n, f, v) {
      n = split(line, f, " ")
      for (i = 1; i <= n; i++)
        if (substr(f[i], 1, length(key) + 1) == key "=") {
          v = substr(f[i], length(key) + 2)
          # One sanitation point for every field this reader renders: the
          # awk-to-shell handoff below uses \037 as its record separator, so a
          # field carrying that byte shifts every later field of its line one
          # left — a SILENT misrendering (the spawn count walked into the
          # verdict column; the park reason truncated), and silence is the
          # worst answer by the standing rule of this tree. The writers emit
          # a closed vocabulary with no control bytes, so the live entrance
          # is an authorized manual state_append (operations §5) or a future
          # writer; either way, what reaches the output carries no separator
          # bytes.
          gsub(/\037/, "", v)
          return v }
      return "" }
    {
      ev = kv($0, "event"); t = kv($0, "t")
      if (ev == "" || t !~ /^[0-9]+$/) { dropped++; next }
      # A rotation row says: everything before it lives in an archive beside
      # the surface, and this segment is the tail. The census covers the
      # segment it is handed — the rounds before the rotation are real time
      # the table cannot see, and the honest answer is to SAY so, never to
      # render the tail as if it were the run (cap 8000 rows; a long topic
      # can cross it).
      if (ev == "rotated") { rotated++; rotfile = kv($0, "rotated_to") }
      if (ev == "complete") compt = t
      glast = t
      sl = kv($0, "slice"); st = kv($0, "stage")
      key = (sl == "" || st == "") ? "" : sl "|" st
      # The frontier round — the round the last KEYED event attributed to.
      # Keyless rows (ferry_start, teardown, slices_index, plan_pinned,
      # run_init — 145+64+28+7+7 across the seven real ledgers) trail every
      # warm resume and never touch it, so they cannot demote a resumed round
      # (measured on a copy of the live ledger: the Phase-3 relaunch
      # ferry_start alone flipped turnover r1 out of its true state). A keyed
      # event that attributes to NO round (a stray record after its round
      # advanced, a stage-named park with no open round) clears it — that is
      # activity the ledger sits at, and every open round is behind it. One
      # scalar answers the question an earlier form needed two shapes for (a
      # per-round last-event array AND the last keyed timestamp): at a
      # timestamp TIE — a park on one stage and an enter on another in the
      # same second — the time form answered RUNNING for BOTH rounds; the
      # round form names the one the ledger actually sits at.
      # THE PAIRING: a keyless park suspends the frontier (below), and the
      # ferry_start that answers it restores it — park says stopped,
      # ferry_start says resuming, and the two are one lifecycle measured on
      # real ledgers (one archive carries the exact sequence three
      # times: park(operator_stop, in-round) -> park(workflow_changed,
      # keyless) -> ferry_start, where the resumed round IS the truth in the
      # gap before its record lands). Without the restore, the clear that the
      # keyless park owes left the frontier empty until the next keyed row —
      # and a warm resume writes none before its record, so the whole resume
      # gap read OPEN (the mirror image of the false RUNNING the clear
      # itself fixed: two defects, opposite directions, same line).
      if (ev == "ferry_start" && glastround == "" && suspended != "") {
        glastround = suspended; suspended = ""
      }
      if (key != "") glastround = ""
      # Open-park closing rule. IN-ROUND park (its stage has an open round):
      # closes at a later park row (the halt was superseded — measured on a
      # real ledger: park(operator_stop) then park(workflow_changed)
      # with no resume between), the first ferry_start after it, or the next
      # event of its own stage. The ferry_start half is easy to miss and
      # expensive to miss: a WARM resume does no spawn, so the stage next
      # event is the resumed work own record — closing there would swallow
      # the resumed WORK into the park gap (measured: 57m of work read as
      # park against the ferry own 70s credit). OUT-OF-ROUND park (no stage
      # on the row, or the stage has no open round): real park time the ferry
      # credits — rides the tail line, closed by a later park, a ferry_start,
      # or any ENTER (a bare record or spawn does not discharge a halt).
      if (opark != "") {
        if (ev == "park" || ev == "ferry_start" || key == oparkkey || (opark == "@" && ev == "enter")) {
          if (opark == "@") { wgap += t - oparkt; wn++ }
          else {
            parked[opark] += t - oparkt
            # A keyless park arriving over an OPEN IN-ROUND park suspends THAT
            # round — the ferry was parked on it, and the pairing restore
            # below must resurrect the round the halt actually stopped. The
            # frontier alone cannot be trusted here: a keyed row between the
            # two parks for a DIFFERENT slice than the parked one (the prw
            # shape: park blocked slice=03, never advanced — the era wrote no
            # resume rows — then the ferry own work for slice 09 lands 44180s
            # later) clears the
            # frontier while the in-round park still holds the round, and the
            # keyless park would then suspend nothing — the resumed round
            # reading OPEN over a ferry that is up, the P1 failure surface
            # again. With ONE round open the two agree (the in-round park
            # itself set the frontier); with TWO rounds open at once (the
            # plan_changed ruling path can produce it — prw carries park
            # plan_changed -> enter elsewhere) the later assignment below
            # wins and takes the frontier round, the ferry current subject —
            # measured by the seventh cold reader: correct, not coincidental.
            if (ev == "park" && key == "") suspended = opark
          }
          opark = ""
        }
      }
      if (ev == "park") {
        if (key == "" || curround[key] == "") {
          # sentinel key: an out-of-round park closes at park/ferry_start/
          # enter ONLY. Without it the stale (or empty) oparkkey lets a bare
          # keyed record — or any keyless row, key "" == the unset "" — close
          # the park early (measured: a teardown 100s after a workflow_
          # changed park capped its gap at 1m).
          # A park is a HALT, so it also suspends the frontier: the round of
          # the last keyed event is suspended, and a ledger ending here has
          # NOTHING running (the ferry exited — the workflow_changed/
          # plan_changed shapes ARE this ending, and the relaunch that
          # answers them has not happened yet). The suspend is CONDITIONAL:
          # a second keyless park (plan_changed on the heels of
          # workflow_changed — a real pair in the oldest archive) must not
          # overwrite what the first suspended with the now-empty frontier —
          # the ferry_start that answers the pair restores the round the
          # FIRST halt stopped. The enter branch retires a suspension: a new
          # round claiming the frontier moots whatever was suspended.
          if (glastround != "") { suspended = glastround; glastround = "" }
          opark = "@"; oparkt = t; oparkkey = "\001"; wnopen++
          od = (key == "" ? "" : sl "·" st " ")
          wwhy = wwhy (wnopen > 1 ? ", " : "") od kv($0, "reason")
        } else {
          cur = curround[key]
          parkn[cur]++
          parkwhy[cur] = parkwhy[cur] (parkn[cur] > 1 ? ", " : "") kv($0, "reason")
          # the park row BELONGS to its round: a round whose own park is its
          # last keyed event is the resumed-and-running shape, not OPEN
          glastround = cur
          opark = cur; oparkt = t; oparkkey = key
        }
        next
      }
      if (key == "") next
      if (!(key in seen)) { seen[key] = 1; korder[++nk] = key }
      cur = curround[key]
      if (ev == "enter") {
        if (cur != "") {   # defensive: an enter over an unclosed round closes it
          if (endt[cur] == "") { endt[cur] = t; outcome[cur] = "(superseded)" }
        }
        r = kv($0, "round"); r = (r == "" ? "?" : r)
        cur = key "#" r; curround[key] = cur
        # A duplicate (slice, stage, round) enter would append the SAME round
        # id twice and render it twice — doubling the stage subtotal for a
        # reader whose whole point is "where did the time go". The writers
        # cannot produce it (the round counter on the attempts surface is
        # monotonic and durable), but a hand-repaired or rolled-back surface
        # is a measured event in this tree, and the fuzzer found the double
        # count in 1 of 1000 ledgers. The re-entered round restarts (the
        # fields reset below); it is listed once.
        if (!(cur in rseen)) { rseen[cur] = 1; rorder[key] = rorder[key] " " cur }
        # a new round claiming the frontier retires any suspension: the
        # ferry_start that follows cannot resurrect the round this enter
        # superseded (the oldest archive pair parks workflow_changed
        # then plan_changed, and the enter between them and the ferry_start
        # is the new frontier own claim)
        suspended = ""
        startt[cur] = t; endt[cur] = ""; outcome[cur] = ""; glastround = cur
        parked[cur] = 0; parkn[cur] = 0; parkwhy[cur] = ""; spawnn[cur] = 0
        next
      }
      if (cur == "") next
      glastround = cur
      if (ev == "spawn") { spawnn[cur]++; next }
      if (ev == "advance") {
        endt[cur] = t
        outcome[cur] = kv($0, "verdict") " -> " kv($0, "target")
        curround[key] = ""; next }
    }
    END {
      # A completed ledger is frozen: its open rounds close at the completion
      # row, so an archived reading is reproducible instead of growing with
      # the wall clock (every archived delivery topic ends with exactly that
      # row). The freeze claims the ledger ENDS in complete — so it applies
      # only when no parsed event is later (a stray post-complete row leaves
      # the live clock, never a now earlier than the round own start:
      # measured, that rendered a negative wall as '?' beside a fabricated
      # RUNNING).
      # A live ledger has none and keeps the real clock.
      frozen = (compt > 0 && glast <= compt)
      if (frozen) now = compt
      # EOF close for a park still open — the topic is parked RIGHT NOW, and
      # the question this reader exists to answer is "why is this taking so
      # long". The ongoing gap counts as parked; the round says PARKED <reason>.
      if (opark == "@") { wgap += now - oparkt; wn++ }
      else if (opark != "") { parked[opark] += now - oparkt; if (outcome[opark] == "") outcome[opark] = "PARKED " parkwhy[opark] }
      for (k = 1; k <= nk; k++) {
        key = korder[k]
        split(key, p, "|")
        n = split(rorder[key], rounds, " ")
        printf "S\037%s\037%s\037%d\n", p[1], p[2], n
        wall = 0; parksum = 0
        for (i = 1; i <= n; i++) {
          cur = rounds[i]
          if (cur == "") continue
          # An open round is RUNNING only when it IS the frontier round —
          # the round the last KEYED event attributed to (keyless rows do
          # not move the frontier); behind that frontier, or on a frozen
          # ledger, the ledger cannot claim liveness, so it says OPEN.
          if (endt[cur] == "" && outcome[cur] == "")
            outcome[cur] = (frozen || cur != glastround ? "OPEN" : "RUNNING")
          e = (endt[cur] == "" ? now : endt[cur] + 0)
          w = e - startt[cur]
          wall += w; parksum += parked[cur]
          printf "R\037%s\037%s\037%s\037%d\037%d\037%d\037%d\037%s\037%d\037%s\n", \
            p[1], p[2], substr(cur, index(cur, "#") + 1), startt[cur], w, \
            parked[cur], parkn[cur], parkwhy[cur], spawnn[cur], outcome[cur]
        }
        printf "T\037%s\037%s\037%d\037%d\n", p[1], p[2], wall, parksum
      }
      if (wn > 0) printf "W\037%d\037%d\037%s\n", wn, wgap, wwhy
      # Rows the parser cannot read are COUNTED and SAID, never silently
      # dropped: the empty-surface gate above already holds the rule "the
      # gate may not be stricter than the parser", and this is its row-level
      # twin — a well-formed checksummed ledger row with a future row
      # spelling (v=2) or a non-numeric t= is invisible to the checksum, so
      # the only honest answers are to count it and name it (peek does the
      # same for sessions rows: "a row that silently vanishes here would hide
      # a session existence"). Without the count, an advance and a park both
      # unreadable rendered their round RUNNING — silence as a verdict.
      if (dropped > 0) printf "D\037%d\n", dropped
      if (rotated > 0) printf "V\037%d\037%s\n", rotated, rotfile
    }' | while IFS=$'\037' read -r tag a b c d e f g h i j; do
      case "$tag" in
        S) printf 'slice %s · %s — %s round(s)\n' "$a" "$b" "$c" ;;
        T) printf '  = wall %s, of which parked %s\n' "$(_st_dur "$c")" "$(_st_dur "$d")" ;;
        W) printf '  + %s park(s) outside any round (%s) — %s held while no round was open\n' "$a" "$c" "$(_st_dur "$b")" ;;
        D) printf '  (%s row(s) on the ledger carry no parseable event=/t= — not counted in any wall; inspect %s/.runtime/state/ledger)\n' "$a" "$WS" ;;
        V) printf '  (the ledger has rotated %s time(s) — rounds before the last rotation live in %s/.runtime/state/%s; this table covers the current segment only)\n' "$a" "$WS" "$b" ;;
        R) clk=$(plat_epoch_fmt "$d" '%m-%d %H:%M' 2>/dev/null || printf '@%s' "$d")
           notes=""
           if [ "${g:-0}" -gt 0 ] 2>/dev/null; then notes="parked ${g}x ${h:-} $(_st_dur "$f")"; fi
           if [ "${i:-0}" -gt 1 ] 2>/dev/null; then notes="${notes:+$notes · }${i} spawns"; fi
           printf '  r%-3s %-11s %-8s %s%s\n' "$c" "$clk" "$(_st_dur "$e")" "${j:-RUNNING}" "${notes:+ · $notes}" ;;
      esac
    done
}

# The halt frame's own escape hatch. The panel truncates a long detail and
# points the operator at the full text; that pointer named `status --once`,
# which status does not accept, and `monitor.sh --once` renders the same
# truncated frame — so neither command printed what the pointer promised. The
# only thing that did was reading <ws>/.runtime/state/halt directly, the store
# the operator is told to leave alone. Measured twice, five slices apart, and
# on two different park classes: the hint rides the halt FRAME, so every park
# reason inherits it, and it is met at the moment the full text is the thing
# needed. Reader, never a writer: the resolved/notified fields are shown, not
# touched.
status_halt() {
  local body rc dtl
  body=$(state_get "$WS" halt 2>/dev/null); rc=$?
  # fault != absent, here as everywhere: this verb is read at the moment a
  # topic is parked, so answering "not parked" over an unreadable surface is
  # the worst available lie. The panel says the same thing in its own way
  # ("STORE FAULT in the halt surface — a park may be hidden").
  [ $rc -eq 3 ] && refuse "the halt surface is CORRUPT (checksum/parse) — not absent; a park may be hidden behind it. Inspect $WS/.runtime/state/halt"
  [ $rc -eq 0 ] || { echo "no halt on record for topic $TOPIC — it has never parked"; return 0; }
  # The pager's record (watchdog.sh): re-pages sent since the park, and whether
  # the owner acknowledged it — both from the audit surface, never assumed.
  # fault != absent on the EVIDENCE surface too, and checked BEFORE any output
  # (the detail is this verb's reason for existing — refusing half-way through
  # would truncate it): a corrupt audit surface collapsing to empty would print
  # "re-paged 0 time(s)" and "acked no" — the second actively directing the
  # operator to re-acknowledge a park they may already have acknowledged, over
  # a fault read as absence. An ABSENT audit surface is not a fault: it is the
  # pre-first-repage state of a fresh park, and reads as zero/absent below.
  local hid npg ackt aud
  hid=$(printf '%s\n' "$body" | awk -F= '$1=="halt_id"{v=$2} END{print v}')
  aud=$(state_get "$WS" audit 2>/dev/null); rc=$?
  [ $rc -eq 3 ] && refuse "the audit surface is CORRUPT (checksum/parse) — not absent; the re-page and ack evidence cannot be read over it. Inspect $WS/.runtime/state/audit (the halt surface itself is intact; re-read it directly if the detail is needed before the repair)"
  # The field list is the SURFACE's own, in its own order — not a list this
  # reader maintains and park() has to remember to update. state_put replaces
  # a key rather than appending, so each key appears once.
  # Every line, including one that is not key=value. This verb exists to show
  # what the surface actually holds, so a line it does not recognise is the
  # LAST thing it may hide — an out-of-band hand-repair of a store is a
  # measured event in this tree, not a hypothetical.
  printf '%s\n' "$body" | awk -F= '
    $1 == "detail" { next }
    NF > 1 { printf "%-11s %s\n", $1, substr($0, length($1) + 2); next }
    { printf "%-11s %s\n", "(no key)", $0 }'
  npg=$(printf '%s\n' "$aud" | command grep -cE "msg=repage [0-9]+/[0-9]+ halt_id=$hid( |$)" || true)
  ackt=$(printf '%s\n' "$aud" | command grep -F "msg=ack halt_id=$hid " | tail -1 \
         | awk '{for(i=1;i<=NF;i++) if($i ~ /^t=/){sub(/^t=/,"",$i); print $i; exit}}')
  if [ "$(printf '%s\n' "$body" | awk -F= '$1=="reason"{v=$2} END{print v}')" = "push_gate" ]; then
    printf '%-11s %s\n' "re-paged" "never — a completion is not an alarm (push_gate is never re-paged)"
  else
    printf '%-11s %s\n' "re-paged" "${npg:-0} time(s) by the watchdog since the park"
    if [ -n "$ackt" ]; then
      # WHICH STATE HOLDS NOW, not what the mechanism does in general: an ack
      # from this morning and one from a minute ago are opposite operational
      # facts, and rendering the mechanism made `at t=` the only clue.
      ackto=$(config_get notify.ack_timeout --topic-dir "$WS" 2>/dev/null) || ackto=""
      case "$ackto" in ''|*[!0-9]*) ackto=$(config_get notify.repage_interval --topic-dir "$WS" 2>/dev/null || echo 2700) ;; esac
      case "$ackto" in ''|*[!0-9]*) ackto=2700 ;; esac
      ackage=$(( $(date +%s) - ackt ))
      if [ "$ackto" -eq 0 ]; then
        printf '%-11s at t=%s — holds are OFF (notify.ack_timeout=0); paging is unaffected by it\n' "acked" "$ackt"
      elif [ "$ackage" -lt "$ackto" ]; then
        printf '%-11s at t=%s — re-paging is PAUSED now, %ss of the %ss window left\n' "acked" "$ackt" "$((ackto - ackage))" "$ackto"
      else
        printf '%-11s at t=%s — that window CLOSED %ss ago; re-paging has resumed\n' "acked" "$ackt" "$((ackage - ackto))"
      fi
    else printf '%-11s no — launch.sh ack %s pauses the re-paging for one interval\n' "acked" "$WS"; fi
  fi
  # detail last and whole: it is the free-text tail, and the only reason this
  # verb exists (the panel truncates it and points here).
  dtl=$(printf '%s\n' "$body" | awk -F= '$1=="detail"{v=substr($0,8)} END{print v}')
  if [ -n "$dtl" ]; then
    printf '%-11s %s chars, untruncated:\n%s\n' detail "${#dtl}" "$dtl"
  else
    printf '%-11s (none)\n' detail
  fi
  [ "$(printf '%s\n' "$body" | awk -F= '$1=="resolved"{v=$2} END{print v}')" = "1" ] \
    && echo "(resolved=1 — this halt has been discharged; the topic is not parked on it any more)"
  return 0
}
