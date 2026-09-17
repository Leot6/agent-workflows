#!/usr/bin/env bash
# twin_diff.sh — deployment-layer twin-declaration consistency report.
#
# WHY THIS LIVES OUTSIDE BOTH TREES (the load-bearing constraint): each tree
# carries an owner ruling — planning A§13 "Zero inter-workflow dependency;
# each workflow fully usable standalone" and delivery architecture §1 the
# same — and planning A§9 bars "any runtime or normative reference to a
# sibling workflow's paths, files, or role vocabulary anywhere in this tree".
# A symlink, or a cross-tree check inside either self-check, would violate
# both. So the twin-diff sits at the deployment root: it references the two
# trees; neither tree references it or each other. Owner: the deployment
# owner (the human operating this checkout), not either tree's maintainer.
#
# WHAT IT CHECKS — the FACTUAL half only (the half "recalibrate the two
# together or neither" is about): the CLIs are the same physical binaries, so
# literals that describe those binaries must agree across the two declaration
# sets. It never rules on the semantic half (key sets differ by design —
# planning's launcher and delivery's driver want different things from the
# same CLI); each tree's own probe stays the authority for semantics.
#
# DEPLOYMENT-LAYER CONVENTION (recorded here, beside the one script both
# trees' declarations share): when the maintainer of EITHER tree harvests
# observations into that tree's iteration-log, grep the OTHER tree's
# iteration-log INDEX for the same mechanism before writing a new entry —
# cross-tree mechanism convergence is visible only from this layer, and both
# trees' self-iterations run independently by design.
#
# Usage: twin_diff.sh [root]   (root defaults to this script's directory)
# Exit: 0 consistent or differences-only-reported · 2 usage fault.
set -uo pipefail
export LC_ALL=C
ROOT=$(cd "${1:-$(dirname "${BASH_SOURCE[0]}")}" && pwd)
PLAN_KV="$ROOT/planning-workflow/runtime-scripts/backends"
DELIV_KV="$ROOT/delivery-workflow/config/backends"

[ -d "$PLAN_KV" ] && [ -d "$DELIV_KV" ] || {
  echo "twin_diff: backend declaration dirs not found under $ROOT" >&2
  exit 2
}

fails=0
for pkv in "$PLAN_KV"/*.kv; do
  name=$(basename "$pkv" .kv)
  dkv="$DELIV_KV/$name.kv"
  [ -f "$dkv" ] || continue   # not a twin (e.g. a delivery-only backend)
  echo "== twin: $name =="
  # 1. composer literal: planning 'composer=', delivery 'sig.composer_line='.
  #    Planning stores the bare prompt char; delivery anchors a regex around
  #    it. Compare the prompt CHARACTER each side actually keys on: pull the
  #    non-ASCII prompt char out of delivery's regex (❯/› are the only ones
  #    any twin declares). A fixed-string byte match, so no locale is needed.
  p_comp=$(sed -n 's/^composer=//p' "$pkv" | head -1)
  d_line=$(sed -n 's/^sig\.composer_line=//p' "$dkv" | head -1)
  d_comp=$(printf '%s' "$d_line" | grep -oF -e '❯' -e '›' | head -1)
  if [ -n "$p_comp" ] && [ -n "$d_comp" ]; then
    if [ "$p_comp" = "$d_comp" ]; then
      echo "  composer char agrees: '$p_comp'"
    else
      echo "  DIFF composer: planning keys on '$p_comp', delivery regex keys on '$d_comp' ($d_line)"
      fails=$((fails + 1))
    fi
  elif [ -n "$p_comp" ] || [ -n "$d_comp" ]; then
    echo "  DIFF composer: declared on one side only (planning='${p_comp:-}' delivery='${d_comp:-}')"
    fails=$((fails + 1))
  fi
  # 2. quota regex: planning 'quota=', delivery 'sig.quota_exhausted='.
  #    Compare as ERE alternation MEMBERS (order-insensitive, whitespace-trimmed)
  #    — a literal added on one side only is exactly the drift this exists for.
  p_q=$(sed -n 's/^quota=//p' "$pkv" | head -1)
  d_q=$(sed -n 's/^sig\.quota_exhausted=//p' "$dkv" | head -1)
  if [ -n "$p_q" ] && [ -n "$d_q" ]; then
    p_members=$(printf '%s' "$p_q" | tr '|' '\n' | sed 's/^ *//;s/ *$//' | sort)
    d_members=$(printf '%s' "$d_q" | tr '|' '\n' | sed 's/^ *//;s/ *$//' | sort)
    if [ "$p_members" = "$d_members" ]; then
      echo "  quota regex agrees ($(printf '%s' "$p_q" | tr '|' '\n' | grep -c .) alternations)"
    else
      echo "  DIFF quota regex members:"
      diff <(printf '%s\n' "$p_members") <(printf '%s\n' "$d_members") | sed 's/^/    /'
      fails=$((fails + 1))
    fi
  fi
  # 3. the {model} glob-quoting rule: BOTH launch lines must double-quote
  #    "{model}" at the flag site (a tier suffix like model[1M] is a glob
  #    class to the pane shell — measured on both trees' drivers).
  for side in "$pkv" "$dkv"; do
    launch=$(sed -n 's/^\(cmd\.launch\)=//p' "$side" | head -1)
    case "$launch" in
      *'"{model}"'*) : ;;
      *'{model}'*)
        echo "  DIFF $side: {model} unquoted in cmd.launch — glob-class tier suffix dies in the pane shell"
        fails=$((fails + 1)) ;;
      *) : ;;  # this declaration launches no model flag (neither twin must)
    esac
  done
done

echo "-----------------------------------------------"
if [ "$fails" -eq 0 ]; then
  echo "twin_diff: consistent (factual halves agree; report-only, no authority)"
else
  echo "twin_diff: $fails factual difference(s) — recalibrate the two together or neither"
fi
exit 0
