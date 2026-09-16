#!/usr/bin/env bash
# derive_cost.sh — what the stages COST, DERIVED not registered. The cost
# counterpart to derive_report.sh: that one reads what the gates CAUGHT, and
# nothing read what the work took. The asymmetry was expensive — three
# learning-loop questions were cost questions (a hard-coded cold stage, an
# unbounded split loop, a check whose depth varied with tree dirt), each
# answered by hand from a raw ledger with a different method, and two of their
# headline numbers went stale without anyone noticing: a split loop measured at
# 47.7% of stage time read 6.0% on the next topic, and a "23+/-2-minute cold
# floor" was falsified by four readings spanning 14m35 to 41m08.
#
# NOT a close-out artifact and NOT a duty. It takes topics as ARGUMENTS and
# reads whatever it is given, so nothing downstream depends on an archive
# surviving: hand it one live workspace, or four archived ones, or none of the
# above. A gate-removal window that counted topics was retired
# precisely because its input had to outlive the trees; this instrument asks
# for its input at the call site instead.
#   AMENDED when `derive_report.sh` began calling it (--stage-totals, below):
#   the close-out report asks it for THIS topic and nothing else, so the
#   sentence above is now false as a statement about CALLERS and stays exactly
#   true as the stance it was written for. The stance is about INPUT — no
#   reading here may depend on a tree outliving its close-out — and a
#   single-workspace call at close-out depends on no archive at all. Written
#   out rather than quietly deleted, because the retired window's lesson is
#   what the sentence carries and a reader who finds a close-out caller needs
#   to know which half still binds.
#
# Usage: derive_cost.sh [--stage-totals] <workspace-or-topic-dir>...
#   Either form is accepted: <topic>/delivery, or <topic> (delivery/ is tried).
# Exit: 0 report produced · 2 usage, or not one readable ledger among the args.
#
# --stage-totals emits the SAME pairing as tab-separated rows instead of the
# human tables: `read`, `skipped`, `paired <ns> <kept> <dropped>`, and one
# `stage <name> <n> <seconds>` per stage. It exists so a second reader can have
# these spans without a second pairing — `derive_report.sh`'s routing-outcome
# block buckets them into topic-level ceremony vs per-slice work using
# `config/stages.tsv`'s own scope column. One pairing, two readers: every rule
# below (the park drop, the FILENAME topic key, the last-spawn-before-record
# rule) applies identically, so the two outputs can never disagree about what a
# span is. Seconds, not the hours the tables print — a fixed/slice ratio built
# from figures already rounded to 0.1h is a ratio of rounding.
#
# HONEST BOUNDARIES, in the header where the check reads them:
# (a) A stage's cost is its spawn->record span. The ferry runs one stage at a
#     time per topic, so these sum to topic work time -- but the span is WALL,
#     and a stage that sat parked measures the park. Parks are excluded by
#     DROPPING any span that contains one, never by subtracting.
#     THE REASON THIS ORIGINALLY GAVE WAS WRONG, and the correction is kept
#     because the wrong version is the more persuasive one. It said: "the store
#     records parked intervals per SLICE (attempts parked.<nn>), so there is no
#     honest per-stage subtraction". The first clause is true -- resume.sh
#     writes `parked.<slice>` as a running total and nothing there names a
#     stage -- and the conclusion does not follow, because that is not the only
#     record of a park. The LEDGER row carries `slice=` AND `stage=`, and the
#     resume is the next ferry_start. Measured over the four archived topics:
#     of 27 dropped spans, 21 contain only parks stamped with their OWN
#     (slice, stage) and are therefore attributable; 6 contain a foreign park
#     and are not. The 21 are also necessarily RE-ATTACHED rather than
#     re-spawned -- this pairing keeps the last spawn before the record, so a
#     re-spawn would have moved the span past its park -- which is what makes
#     span-minus-parked exactly the working time rather than an estimate.
#     So the drop STAYS the default, on a narrower and honest reason: applying
#     the correction would move every headline figure this script prints, and
#     that is an owner call. What changed is that the cost of dropping is now
#     PRINTED beside the count instead of being asserted away.
# (b) The cold/warm ratio is confounded for precheck and postcheck, and is NOT
#     confounded for the author stages. Rounds >=2 of a review stage are warm
#     AND are delta reviews, so two effects ride one number. split, revise,
#     impl, fix and turnover are warm-author at round 1 either way -- their
#     warm/cold difference is the held session and nothing else, which is why
#     the table marks them `clean` and marks the review stages `delta?`.
# (c) It reads only surfaces the workflow itself WRITES. Per-session tool-call
#     counts would sharpen (a) considerably and are deliberately absent: the
#     only place they exist is the vendor CLI's pane log, which is a tmux
#     screen capture of a third-party TUI -- lossy by construction (redraws
#     drop characters) and coupled to one CLI's rendering. Measured once by
#     hand, as evidence; never wired,
#     because a mechanism resting on someone else's screen output rots the day
#     they change it.
set -uo pipefail
export LC_ALL=C
DC_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
. "$DC_DIR/lib/state.sh"

DC_TOTALS=0
[ "${1:-}" = "--stage-totals" ] && { DC_TOTALS=1; shift; }
[ "$#" -ge 1 ] || { echo "usage: derive_cost.sh [--stage-totals] <workspace-or-topic-dir>..." >&2; exit 2; }
# An option in any other position is REFUSED rather than read as a path. Every
# remaining argument is a directory, so a `--`-prefixed one is a mistake with a
# misleading fallback: it would reach the reader below, fail to hold a ledger,
# and be reported as a topic with no ledger — a wrong diagnosis stated
# confidently, which costs more than the typo did.
for a in "$@"; do
  case "$a" in
    --*) echo "refuse: unrecognised option '$a' — the only option is --stage-totals and it must come first; every other argument is a workspace or topic directory" >&2; exit 2 ;;
  esac
done

# Collect every readable ledger first, so the report can state its own range
# before it states a number -- and so one unreadable argument names itself
# instead of silently shrinking the sample.
dc_tmp=$(mktemp -d "${TMPDIR:-/tmp}/dcost.XXXXXX") || exit 2
trap 'rm -rf "$dc_tmp"' EXIT
n_ok=0 read_names="" skipped=""
for a in "$@"; do
  ws=$a
  [ -d "$ws/.runtime/state" ] || ws="$a/delivery"
  # The NAME comes from the ARGUMENT, never from the store probe. The old
  # form derived it from `cd "$ws/.."` AFTER the delivery/ fallback, so a
  # WORKSPACE-form argument with no store probed <arg>/delivery/delivery,
  # failed, and printed the basename of the argument itself -- `delivery`,
  # identically for every such topic: four store-less archive directories
  # were indistinguishable in one skip line, which is the naming contract
  # above defeated for exactly the form a mixed live+archive call hands over.
  # One trailing delivery component is stripped (both accepted forms name
  # their topic); the resolution is PHYSICAL when the directory exists -- a
  # symlinked workspace names its real topic, the same two-resolutions lesson
  # derive_report.sh paid for -- and falls back to the string when it does
  # not, because a topic that cannot be opened still deserves to be named.
  case "${a%/}" in
    */delivery) dc_arg_topic=$(dirname "${a%/}") ;;
    *)          dc_arg_topic="${a%/}" ;;
  esac
  if dc_td=$(cd -P "$dc_arg_topic" 2>/dev/null && pwd -P); then name=$(basename "$dc_td")
  else name=$(basename "$dc_arg_topic"); fi
  body=$(state_get "$ws" ledger 2>/dev/null); rc=$?
  case $rc in
    0) : ;;
    3) skipped="$skipped $name(store FAULT)"; continue ;;
    *) skipped="$skipped $name(no ledger)"; continue ;;
  esac
  [ -n "$body" ] || { skipped="$skipped $name(empty)"; continue; }
  n_ok=$((n_ok + 1)); read_names="$read_names $name"
  printf '%s\n' "$body" > "$dc_tmp/$n_ok.ledger"
done
if [ "$n_ok" -eq 0 ]; then
  echo "refuse: not one readable ledger among the arguments —$skipped" >&2; exit 2
fi

# A CONTRACT THIS MODE OWES ITS CONSUMER, stated here because the person who can
# break it is editing THIS file: in --stage-totals mode the success path writes
# NOTHING to stderr. `derive_report.sh` captures this mode with the streams
# merged and lets the exit status decide, which is what lets it forward a refusal
# in these words instead of inventing its own — and any stderr written on a
# successful run would arrive there as data rows. If a future reading here needs
# to warn, give it a `warn<TAB>...` row on stdout rather than a stderr line.
if [ "$DC_TOTALS" -eq 1 ]; then
  printf 'read\t%d\t%s\n' "$n_ok" "${read_names# }"
  [ -n "$skipped" ] && printf 'skipped\t%s\n' "${skipped# }"
else
  echo "# cost report — $n_ok topic(s) ($(date '+%F %T'))"
  echo "  read:$read_names"
  [ -n "$skipped" ] && echo "  NOT read:$skipped  (an unreadable ledger is named, never dropped silently)"
fi

# The ledgers are passed as ARGUMENTS, never piped through `cat`. Under a pipe
# awk sets FILENAME to "-" for EVERY row, and this program keys both of its
# per-topic structures on FILENAME: the park set (a park in one topic would
# drop spans in another) and the open-spawn table (a spawn whose record never
# arrived would pair with the NEXT topic's record for the same slice+stage,
# producing a span of days). The comment below already said topic identity was
# the file a row came from; the pipe silently made it one file.
# HONEST ON THE DELTA: fixed, and on the four archived topics it
# changes NOTHING — 302 paired / 275 kept / 27 dropped, byte-identical before
# and after, because no park of one topic happened to fall inside another's
# span and every spawn in the corpus paired inside its own file. So this is a
# latent defect closed, not a number corrected, and it is written that way
# because the first draft of this comment asserted a measured delta that the
# re-run did not produce. `98-report` pins the property directly instead, on a
# two-topic fixture built to straddle.
awk '
  # Pass 1 is the same pass: parks are stamped, spans are held, and the
  # exclusion is decided in END when both sets are complete. A span is dropped
  # if ANY park stamp of the same topic falls inside it. Topic identity is the
  # file the row came from; the ledgers are concatenated, so a spawn whose
  # record never arrived (a topic that stopped mid-stage) simply never pairs.
  function fmt(s) { return sprintf("%dm%02d", int(s/60), s%60) }
  # A SECOND formatter, and the reason it is separate rather than a smarter fmt:
  # stage spans are all tens of minutes and read best that way, while a park wait
  # runs to a day and a half and reads as nonsense in minutes (2205m44). Widening
  # fmt itself would silently restyle the two tables above the day a stage span
  # crossed two hours, which is a change to those tables made for this one.
  function fmtw(s) { if (s < 3600) return sprintf("%dm%02d", int(s/60), s%60)
                     return sprintf("%dh%02dm", int(s/3600), int((s%3600)/60)) }
  # Conventional median: the mean of the two middles on an even sample. Not a
  # detail — the first form of this took the lower middle, and on n=4 and n=2
  # that alone moved two ratios by 1.6x and 2.8x against a hand-rolled reading
  # that took the upper one. A convention that changes the answer on small
  # samples has to be the standard one AND the sample size has to be printed
  # beside it, which is why `n` sits next to every median below.
  function med(arr, n,   i, j, t, tmp, c) {
    c = 0; for (i = 1; i <= n; i++) tmp[++c] = arr[i]
    for (i = 1; i <= c; i++) for (j = i + 1; j <= c; j++)
      if (tmp[j] < tmp[i]) { t = tmp[i]; tmp[i] = tmp[j]; tmp[j] = t }
    if (c % 2) return tmp[(c + 1) / 2]
    return (tmp[c / 2] + tmp[c / 2 + 1]) / 2
  }
  { ev=""; st=""; sl=""; md=""; ms=""; tt=""; rs=""
    for (i = 1; i <= NF; i++) {
      if ($i ~ /^event=/) ev = substr($i, 7)
      else if ($i ~ /^stage=/) st = substr($i, 7)
      else if ($i ~ /^slice=/) sl = substr($i, 7)
      else if ($i ~ /^reason=/) rs = substr($i, 8)
      else if ($i ~ /^mode_src=/) ms = substr($i, 10)
      else if ($i ~ /^mode=/)  md = substr($i, 6)
      else if ($i ~ /^t=/)     tt = substr($i, 3) + 0
    } }
  # A park ends when a ferry starts again on the SAME topic. There is no
  # `resume` event to pair with -- checked against the whole ledger
  # vocabulary -- and `ferry_start` is the honest stand-in: it is the first
  # thing that happens after a human comes back. It bounds the wait from above
  # (the human may have returned earlier and read before relaunching), which is
  # the safe direction for sizing an interval meant to CAP that wait.
  ev == "ferry_start" {
    # ONE rule, because this one ends with `next` and a second ev=="ferry_start"
    # rule below it is dead code -- which it silently was, until an independent
    # hand count of the recoverable parked time (2.2h) disagreed with what the
    # instrument printed (0.0h) and the disagreement was the only thing that
    # showed it. Both consumers of the event are served here.
    fs++; fsf[fs] = FILENAME; fst[fs] = tt
    for (j = 1; j <= pk; j++)
      if (!pkdone[j] && pkf[j] == FILENAME && pkt[j] < tt) { pkw[++pw] = tt - pkt[j]; pwr[pw] = pkr[j]; pkdone[j] = 1 }
    next }
  # Parks are held twice: once to EXCLUDE the spans they contaminate, and once
  # as a subject of their own. The reason for the second is that this script
  # already knew where every park was and reported only how many spans it threw
  # away because of them — the wait itself, which is the only interval in the
  # whole run measured in a HUMAN response rather than an agent one, went
  # unread. sizing a re-page interval needs this distribution, and that sizing
  # had been waiting on a live topic while 50 episodes sat in the archives.
  ev == "park" { park[FILENAME, ++np[FILENAME]] = tt
                 parkslice[FILENAME, np[FILENAME]] = sl; parkstage[FILENAME, np[FILENAME]] = st
                 pk++; pkf[pk] = FILENAME; pkt[pk] = tt; pkr[pk] = rs; next }
  ev == "spawn" && st != "" { k = FILENAME SUBSEP sl SUBSEP st; ot[k] = tt; om[k] = md; oq[k] = ms; next }
  ev == "record" && st != "" {
    k = FILENAME SUBSEP sl SUBSEP st
    if (!(k in ot)) next
    ns++; sf[ns] = FILENAME; ss[ns] = st; sm[ns] = (om[k] == "" ? "?" : om[k])
    sq[ns] = (oq[k] == "" ? "unrecorded" : oq[k])
    s0[ns] = ot[k]; s1[ns] = tt; ssl[ns] = sl; delete ot[k]
  }
  END {
    for (i = 1; i <= ns; i++) {
      drop = 0; foreign = 0; parkedin = 0
      for (p = 1; p <= np[sf[i]]; p++) {
        if (park[sf[i], p] < s0[i] || park[sf[i], p] > s1[i]) continue
        drop = 1
        if (parkslice[sf[i], p] != ssl[i] || parkstage[sf[i], p] != ss[i]) { foreign = 1; continue }
        nxt = 0
        for (q = 1; q <= fs; q++)
          if (fsf[q] == sf[i] && fst[q] > park[sf[i], p] && (nxt == 0 || fst[q] < nxt)) nxt = fst[q]
        if (nxt > 0 && nxt <= s1[i]) parkedin += nxt - park[sf[i], p]
      }
      if (drop) { dropped++
        if (foreign) recno++
        else { recn++; recraw += s1[i] - s0[i]; recpark += parkedin }
        continue }
      d = s1[i] - s0[i]; if (d < 0) continue
      key = ss[i] SUBSEP sm[i]
      n[key]++; dur[key, n[key]] = d; sum[key] += d; total += d
      stages[ss[i]] = 1; per[ss[i]] += d; pern[ss[i]]++
      if (index(sm[i], "cold") == 1) { srcn[sq[i]]++; srcs[sq[i]] += d; srck[sq[i]] = 1; coldt += d }
      kept++
    }
    # --stage-totals: the same pairing, emitted for a machine. Placed BEFORE
    # every human line so a consumer never has to skip prose, and it exits
    # here rather than duplicating the tables in a second shape.
    if (totals) {
      printf "paired\t%d\t%d\t%d\n", ns+0, kept+0, dropped+0
      no2 = 0; for (s in stages) tord[++no2] = s
      for (i = 1; i <= no2; i++) for (j = i + 1; j <= no2; j++)
        if (tord[j] < tord[i]) { tsw = tord[i]; tord[i] = tord[j]; tord[j] = tsw }
      for (i = 1; i <= no2; i++)
        printf "stage\t%s\t%d\t%d\n", tord[i], pern[tord[i]]+0, per[tord[i]]+0
      exit
    }
    printf "  paired %d spawn->record spans; kept %d, dropped %d for containing a park\n", ns, kept, dropped
    # WHAT THE DROP COSTS, and it is printed because boundary (a) above used to
    # assert that no honest per-stage subtraction exists. That was true of the
    # surface it named -- attempts parked.<nn> is a per-SLICE running total --
    # and false of the one it did not: the ledger park row carries slice AND
    # stage, and the resume is the next ferry_start. A dropped span whose parks
    # are all its OWN is therefore correctable, and it is necessarily one that
    # was RE-ATTACHED rather than re-spawned: this pairing keeps the last spawn
    # before the record, so a re-spawn would have moved the span past the park.
    # Reported, not applied: folding these in would move every headline figure
    # here, which is the owner call this measurement exists to inform.
    if (dropped > 0)
      printf "    of those %d: %d carry only their OWN stage parks -- %.1fh raw, %.1fh parked, %.1fh of work currently discarded and honestly recoverable; %d carry a foreign park and are not\n",
        dropped, recn, recraw/3600, recpark/3600, (recraw - recpark)/3600, recno
    print ""
    print "## stage cost (spawn->record, parks excluded)"
    printf "   %-14s %-6s %4s %9s %9s %8s\n", "stage", "mode", "n", "median", "total", "share"
    # stages ordered by their own total, descending — a stable order that says
    # what to look at first rather than what sorts first
    for (s in stages) {
      best = ""; bv = -1
      for (t in stages) if (!seen[t] && per[t] > bv) { bv = per[t]; best = t }
      seen[best] = 1; order[++no] = best
    }
    for (o = 1; o <= no; o++) {
      s = order[o]
      for (m = 1; m <= 2; m++) {
        mode = (m == 1 ? "cold" : "warm")
        c = 0
        for (mm in n) { split(mm, kk, SUBSEP); if (kk[1] == s && index(kk[2], mode) == 1) { c = n[mm]; key = mm } }
        if (c == 0) continue
        for (i = 1; i <= c; i++) a[i] = dur[key, i]
        printf "   %-14s %-6s %4d %9s %8.1fh %7.1f%%\n", s, mode, c, fmt(med(a, c)), sum[key]/3600, 100*sum[key]/total
      }
    }
    printf "   %-14s %-6s %4d %9s %8.1fh %7.1f%%\n", "TOTAL", "", kept, "-", total/3600, 100
    print ""
    print "## the cold tax (same stage, same round-1 work, different session)"
    print "   `clean` = warm-author at round 1 either way, so the only difference is the held"
    print "   session. `delta?` = a review stage whose warm rounds are also SECOND passes;"
    print "   two effects ride one number there and it is not a clean reading."
    printf "   %-14s %6s %9s %6s %9s %8s  %s\n", "stage", "cold_n", "cold_med", "warm_n", "warm_med", "ratio", "reading"
    for (o = 1; o <= no; o++) {
      s = order[o]; cn = 0; wn = 0
      for (mm in n) { split(mm, kk, SUBSEP)
        if (kk[1] != s) continue
        if (index(kk[2], "cold") == 1) { cn = n[mm]; ck = mm } else { wn = n[mm]; wk = mm } }
      if (cn == 0 || wn == 0) continue
      for (i = 1; i <= cn; i++) a[i] = dur[ck, i]; cm = med(a, cn)
      for (i = 1; i <= wn; i++) b[i] = dur[wk, i]; wm = med(b, wn)
      tag = (s == "precheck" || s == "postcheck" || s == "split-check") ? "delta?" : "clean"
      # A `clean` reading on three cold spans corroborates; it does not prove.
      # Said on the row, because a ratio printed bare is read as a finding.
      if (cn < 8 || wn < 8) tag = tag " · small-n"
      # A median of ZERO is a real reading, not a missing one: durations are
      # integer seconds, so a stage whose warm spans all finish inside one
      # second medians to 0. Dividing by it KILLED the whole report — a
      # division by zero is FATAL in awk, so the run died right here and every
      # section below it never printed. Found by running this instrument on the
      # drill workspace of the suite itself, where a mock agent answers in
      # under a second; every fixture in 98-report uses 600s/200s spans and
      # could not have seen it. The ratio is UNDEFINED at this resolution
      # rather than absent, and the row says so instead of vanishing — a
      # dropped row would read as "this stage has no cold/warm pair", the
      # opposite of what happened.
      # NOTE for editors: this whole awk program is a single-quoted shell
      # string, so a comment here may contain no apostrophe. The first draft of
      # this one wrote a possessive and closed the string.
      if (wm == 0) {
        printf "   %-14s %6d %9s %6d %9s %8s  %s\n", s, cn, fmt(cm), wn, fmt(wm), "n/a", tag " · sub-second warm median: ratio undefined at 1s resolution"
      } else {
        printf "   %-14s %6d %9s %6d %9s %7.2fx  %s\n", s, cn, fmt(cm), wn, fmt(wm), cm/wm, tag
      }
    }
    if (pk > 0) {
      print ""
      print "## parks — how long a parked topic waited for a human"
      print "   The one interval here measured in a PERSON response, not an agent one. A park"
      print "   pages the owner unconditionally (ferry.sh park -> notify_fire), so this is the"
      print "   discovery latency a re-page interval would cap. Bounded ABOVE: it ends at the"
      print "   next ferry_start, and the owner may have read it earlier."
      nw = 0
      for (i = 1; i <= pw; i++) { nw++; sw[nw] = pkw[i] }
      for (i = 1; i <= nw; i++) for (j = i + 1; j <= nw; j++) if (sw[j] < sw[i]) { tmpv = sw[i]; sw[i] = sw[j]; sw[j] = tmpv }
      over = 0
      for (i = 1; i <= nw; i++) if (sw[i] >= 21600) over++
      longest = ""; lv = -1
      for (i = 1; i <= pw; i++) if (pkw[i] > lv) { lv = pkw[i]; longest = pwr[i] }
      printf "   parks %d · resumed %d · never resumed %d\n", pk, nw, pk - nw
      if (nw > 0) {
        printf "   median %s · p90 %s · max %s (%s) · over 6h: %d of %d\n",
          fmtw(med(sw, nw)), fmtw(sw[int(nw * 0.9) + 1 > nw ? nw : int(nw * 0.9) + 1]),
          fmtw(lv), longest, over, nw
      }
    }
    if (coldt > 0) {
      print ""
      print "## cold, by WHY (the split the cold tax is worth nothing without)"
      print "   `designed` is cold by the stage contract -- the reviewer round-1 independence,"
      print "   the spec authority chain -- and is a price the design pays on purpose. Every"
      print "   other row is a warm-capable stage that ran cold anyway, at the tax above and"
      print "   for nothing. `unrecorded` is a spawn row written before mode_src existed."
      printf "   %-20s %4s %9s %s\n", "why", "n", "total", "share of cold"
      for (r in srck) {
        best = ""; bv = -1
        for (t in srck) if (!sseen[t] && srcs[t] > bv) { bv = srcs[t]; best = t }
        sseen[best] = 1; sorder[++nso] = best
      }
      for (o = 1; o <= nso; o++) {
        r = sorder[o]
        printf "   %-20s %4d %8.1fh %12.1f%%\n", r, srcn[r], srcs[r]/3600, 100*srcs[r]/coldt
      }
    }
  }
' totals="$DC_TOTALS" "$dc_tmp"/*.ledger
