#!/usr/bin/env bash
# rulings.sh — the ONE selector for "which rulings address this (slice, stage)",
# behind both manifest carriage (compose.sh `rulings.pending`) and the emit-time
# door (record.sh `--ruling-ack`), so the two cannot drift (protocol.md §6).
# A ruling row addresses slice S when it carries slice=S, or scope=topic
# (`launch.sh rule --topic`): a topic ruling rides every slice's manifest. A
# stage-addressed row (stage≠any) reaches only its stage when a stage is asked
# for. Tokens are read up to text= — free text, always last, never a binding.
# The caller sources state.sh.

rulings_addressed() { # ws slice [stage] [since_t] -> rows; rc 1 none, rc 3 store fault
  local ws=$1 slice=$2 stage=${3:-} since=${4:--1} body rc out
  body=$(state_get "$ws" rulings 2>/dev/null); rc=$?
  [ $rc -eq 3 ] && return 3
  [ $rc -eq 0 ] || return 1
  out=$(printf '%s\n' "$body" | awk -v s="$slice" -v st="$stage" -v since="$since" '
    { rs=""; rstage="any"; scope=""; ts=0
      for (i = 1; i <= NF; i++) {
        if ($i ~ /^text=/) break
        if ($i ~ /^slice=/) rs = substr($i, 7)
        if ($i ~ /^stage=/) rstage = substr($i, 7)
        if ($i ~ /^scope=/) scope = substr($i, 7)
        if ($i ~ /^t=/) ts = substr($i, 3)
      }
      if (rs != s && scope != "topic") next
      if (st != "" && rstage != "any" && rstage != st) next
      if (ts + 0 <= since + 0) next
      print
    }')
  [ -n "$out" ] || return 1
  printf '%s\n' "$out"
}

rulings_tokens() { # rows on stdin -> "<slice>.<n> <file>" per row: the ack token and where to read it
  awk '{ rs=""; n=""; f=""
    for (i = 1; i <= NF; i++) {
      if ($i ~ /^text=/) break
      if ($i ~ /^slice=/) rs = substr($i, 7)
      if ($i ~ /^n=/) n = substr($i, 3)
      if ($i ~ /^file=/) f = substr($i, 6)
    }
    if (rs != "" && n != "") print rs "." n " " f }'
}
