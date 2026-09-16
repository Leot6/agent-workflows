#!/usr/bin/env bash
# lib/owed.sh — the ONE owed-set derivation (design/architecture.md §1 move 1).
#
# Owed(stage, workspace) = stages.tsv static column ⊕ @cu expansion, where
# @cu = the spec's commit-unit list checked against the progress surface with
# every SHA resolved in the project repo's git log. record.sh's emit refusal,
# the ferry's advance check, and park-on-miss all call owed_check — a backstop
# can never share an item with the failure it catches (one list).
#
# Commit-unit list format in slices/<nn>/spec.md (the machine-read contract;
# the spec template's §3 table): one markdown row per unit,
#   | cu-<N> | <subject (project convention)> | <risk note> | <yes|no> |
# where the last cell is the relocation-only flag (read by the emit-time
# commit gate).
#
# rc: 0 all owed present · 1 missing (each item printed, self-describing)
#     · 2 bad args/unknown item · 3 store/git FAULT.

_OWED_LIB_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
. "$_OWED_LIB_DIR/state.sh"
. "$_OWED_LIB_DIR/config.sh"
OWED_WORKFLOW_ROOT=${OWED_WORKFLOW_ROOT:-$CONFIG_WORKFLOW_ROOT}

owed_stage_row() { # stage -> full tsv row
  local row
  row=$(awk -F'\t' -v s="$1" '$0 !~ /^#/ && $1==s {print; exit}' \
        "$OWED_WORKFLOW_ROOT/config/stages.tsv")
  [ -n "$row" ] || { echo "refuse: stage '$1' not in stages.tsv" >&2; return 2; }
  printf '%s\n' "$row"
}

# The ONE stage->role derivation (ferry spawn config and record.sh field
# requirements both key on it): the ROLE_CARD entry of the manifest_required
# column, deliberately scoped to that column — a reviewer card appearing in
# some row's OPTIONAL manifest must never flip the stage's role (two prior
# copies scanned different extents and would have diverged exactly there).
owed_stage_role() { # stage -> author|reviewer
  case "$(owed_stage_row "$1" | awk -F'\t' '{print $7}')" in
    *cards/reviewer.md*) echo reviewer ;;
    *) echo author ;;
  esac
}

owed_static_items() { # stage -> one item per line (incl. literal @cu)
  local row
  row=$(owed_stage_row "$1") || return 2
  printf '%s\n' "$row" | awk -F'\t' '{print $4}' | tr ';' '\n' | command grep -v '^$'
}

owed_spec_cus() { # workspace slice -> cu ids (N per line)
  # Source of truth: the spec template's commit-unit table rows  | cu-<N> | ...
  # Fenced blocks are quoted DATA (an example or citation), not this spec's
  # units — same lesson the emit gates paid for. _gates_strip_fences comes
  # from lib/gates.sh: both real callers (ferry.sh, record.sh) source gates
  # alongside owed, the dependency is deliberate (single fence-stripping
  # truth, no second home).
  local spec="$1/slices/$2/spec.md"
  [ -f "$spec" ] || return 0
  _gates_strip_fences "$spec" \
    | command grep -oE '^\| *cu-[0-9]+ *\|' | command grep -oE '[0-9]+'
}

owed_cu_total() { owed_spec_cus "$1" "$2" | command grep -c . || true; }

# The units that actually LANDED for this slice, read from the progress ledger.
# owed_spec_cus above is the SPEC's list, which is the right set for "what is
# owed" and the wrong set for "what must be attested": a fix round registers
# units the spec never listed, and the emit-time commit gate iterated the spec
# list, so those escaped per-commit attestation entirely. Anchored twice,
# eleven slices apart (slice 01 postcheck.2 and slice 12 postcheck.2) — both
# units were in the ledger BEFORE the emit's gate run, and both were covered
# only incidentally by the no-arg acceptance run whose HEAD~1..HEAD range
# happened to equal the fix commit at the tip.
# SCOPE, stated because the rows carry a `stage=` this deliberately ignores:
# the set is per SLICE, not per stage. A fix emit therefore re-attests the
# impl units too. That is the cheap direction and the correct one — the gate
# reads each unit at the CURRENT tip, and a fix round is exactly when history
# above a unit may have been rewritten — where a stage filter would attest
# each unit against whichever tip happened to stand when its own stage closed.
# First-registration order, deduplicated: a re-registered cu is gated once.
owed_ledger_cus() { # workspace slice -> cu ids (N per line)
  state_get "$1" progress 2>/dev/null \
    | awk -v s="$2" '$0 ~ ("(^| )slice=" s "( |$)") {
        for (i = 1; i <= NF; i++)
          if ($i ~ /^cu=/) { sub(/^cu=/, "", $i); if (!seen[$i]++) print $i }
      }'
}

owed_spec_cu_reloc() { # workspace slice cu -> yes|no (relocation-only column)
  local spec="$1/slices/$2/spec.md"
  [ -f "$spec" ] || { echo no; return 0; }
  awk -F'|' -v cu="cu-$3" '
    $2 ~ ("^ *" cu " *$") { gsub(/ /,"",$5); print tolower($5); found=1; exit }
    END { if (!found) print "no" }' "$spec"
}

# Full derived owed list: static items with @cu expanded to cu.<N> entries.
owed_derive() { # workspace stage slice
  local ws=$1 stage=$2 slice=$3 item
  while IFS= read -r item; do
    if [ "$item" = "@cu" ]; then
      owed_spec_cus "$ws" "$slice" | sed 's/^/cu./'
      # An empty commit-unit list is itself a miss (the spec owes the list);
      # surface it as a distinguished item.
      [ -n "$(owed_spec_cus "$ws" "$slice")" ] || echo "@cu-list"
    else
      printf '%s\n' "$item"
    fi
  done < <(owed_static_items "$stage")
}

# Verify one cu id has a progress record whose SHA resolves in git log. The LAST
# row per cu is the unit: a re-registration supersedes its predecessor and says
# so on its row (record.sh progress, `supersedes=`), so an earlier sha that no
# longer resolves is history, never a miss.
_owed_cu_ok() { # workspace slice cu_id -> 0 ok / 1 missing (reason on stdout)
  local ws=$1 slice=$2 cu=$3 body rc sha repo branch
  body=$(state_get "$ws" progress 2>/dev/null); rc=$?
  if [ $rc -eq 3 ]; then echo "progress surface FAULT"; return 3; fi
  sha=$(printf '%s\n' "$body" 2>/dev/null \
        | awk -v s="$slice" -v c="$cu" '
            $0 ~ ("(^| )slice=" s "( |$)") && $0 ~ ("(^| )cu=" c "( |$)") {
              for(i=1;i<=NF;i++) if($i ~ /^sha=/){sub(/^sha=/,"",$i); v=$i}
            } END{print v}')
  if [ -z "$sha" ]; then
    echo "no progress-surface record for cu.$cu (author records each landed unit via record.sh progress)"
    return 1
  fi
  # The SLICE's binding decides the checkout and the tip: a doc-bound slice's
  # units live in the doc repo, and checking them against the code repo would
  # read every landed doc commit as lost work.
  repo=$(binding_repo "$ws" "$slice") || { echo "project.kv missing/no repo= for slice $slice's binding"; return 3; }
  if ! git -C "$repo" rev-parse -q --verify "$sha^{commit}" > /dev/null 2>&1; then
    echo "cu.$cu progress SHA $sha does not resolve to a commit in $repo"
    return 1
  fi
  branch=$(binding_branch "$ws" "$slice" 2>/dev/null || true)
  local tip=${branch:-HEAD}
  # A tip that does not resolve is a project.kv defect, not lost work — the
  # two failures must not share an error face.
  if ! git -C "$repo" rev-parse -q --verify "$tip^{commit}" > /dev/null 2>&1; then
    echo "the declared tip '$tip' does not resolve in $repo — fix project.kv (branch= for code slices, doc.branch= for doc-bound ones; the cu SHAs cannot be checked against a phantom tip)"
    return 1
  fi
  if ! git -C "$repo" merge-base --is-ancestor "$sha" "$tip" 2>/dev/null; then
    echo "cu.$cu progress SHA $sha is not in git log of $tip in $repo"
    return 1
  fi
  return 0
}

# Map a static owed item to its on-disk / in-store home and test presence.
# Prints a reason line when missing. rc 0 present / 1 missing / 2 unknown / 3 fault.
_owed_item_check() { # workspace stage slice round nonce skip_csv item
  local ws=$1 stage=$2 slice=$3 round=$4 nonce=$5 skip=$6 item=$7
  case ",$skip," in *",$item,"*) return 0 ;; esac
  case "$item" in
    handoff)
      local body rc
      body=$(state_get "$ws" handoff 2>/dev/null); rc=$?
      [ $rc -eq 3 ] && { echo "handoff surface FAULT"; return 3; }
      local pat="(^| )slice=$slice( |$)"
      if [ -n "$nonce" ]; then pat="(^| )nonce=$nonce( |$)"; fi
      if ! printf '%s\n' "$body" | command grep -qE "$pat" 2>/dev/null \
         || ! printf '%s\n' "$body" | command grep -E "$pat" | command grep -qE "(^| )stage=$stage( |$)"; then
        echo "handoff: no record for (slice=$slice stage=$stage${nonce:+ nonce=$nonce}) in the handoff surface"
        return 1
      fi ;;
    slices_index)
      local rc body
      body=$(state_get "$ws" slices 2>/dev/null); rc=$?
      [ $rc -eq 3 ] && { echo "slices surface FAULT"; return 3; }
      if [ $rc -ne 0 ]; then
        echo "slices_index: slices surface absent (split's record must carry --slices; the ferry writes the index on advance)"
        return 1
      fi
      if ! printf '%s\n' "$body" | command grep -qE '(^| )id='; then
        echo "slices_index: slices surface holds no id= rows — an empty index is a miss, not a pass (a zero-slice topic would walk silently to close-out)"
        return 1
      fi ;;
    cu.*)
      local out rc
      out=$(_owed_cu_ok "$ws" "$slice" "${item#cu.}"); rc=$?
      [ $rc -ne 0 ] && echo "$item: $out"
      return $rc ;;
    @cu-list)
      echo "@cu-list: slices/$slice/spec.md declares no commit-unit table rows '| cu-<N> | <subject> | <risk note> | <yes|no> |' (spec template §3 — the spec owes the list)"
      return 1 ;;
    validation_note)
      _owed_file "$ws/slices/00/validation_note.md" "$item" || return 1 ;;
    splitcheck_review|precheck_review|postcheck_review)
      local kind=${item%_review} dir="$ws/slices/$slice" f
      [ "$item" = "splitcheck_review" ] && dir="$ws/slices/00"
      if [ -n "$round" ]; then
        f="$dir/$kind.$round.md"
        _owed_file "$f" "$item" || return 1
      else
        if ! ls "$dir/$kind."*.md > /dev/null 2>&1; then
          echo "$item: no $dir/$kind.<round>.md exists"
          return 1
        fi
      fi ;;
    charters.md|closeout.md)
      _owed_file "$ws/$item" "$item" || return 1 ;;
    spec.md|conformance.md|turnover.md)
      _owed_file "$ws/slices/$slice/$item" "$item" || return 1 ;;
    dispatch)
      # The implementer prompt AS SENT, one file per dispatch: the author card's
      # dispatch discipline owes it before the send, and impl's emit owes at
      # least one. A unit landed by a prompt nobody can read leaves a
      # conformance record nobody can audit.
      local df dok=0
      for df in "$ws/slices/$slice"/dispatch.*.md; do
        [ -s "$df" ] && { dok=1; break; }
      done
      if [ "$dok" -eq 0 ]; then
        echo "dispatch: no non-empty slices/$slice/dispatch.<n>.md — every implementer dispatch is written to disk as sent (cards/author.md, dispatch discipline), and impl owes at least one"
        return 1
      fi ;;
    *)
      echo "refuse: owed item '$item' has no home mapping (stages.tsv drift — extend lib/owed.sh)" >&2
      return 2 ;;
  esac
  return 0
}

_owed_file() { # path item
  if [ ! -s "$1" ]; then
    echo "$2: expected non-empty file $1"
    return 1
  fi
}

# The single check used by record.sh emit, ferry advance, and park-on-miss.
owed_check() { # workspace stage slice [--round R] [--nonce N] [--skip a,b]
  local ws=$1 stage=$2 slice=$3; shift 3
  local round="" nonce="" skip=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --round) round=$2; shift 2 ;;
      --nonce) nonce=$2; shift 2 ;;
      --skip) skip=$2; shift 2 ;;
      *) echo "refuse: owed_check unknown arg '$1'" >&2; return 2 ;;
    esac
  done
  local item rc worst=0 items
  items=$(owed_derive "$ws" "$stage" "$slice") || return 2
  while IFS= read -r item; do
    [ -n "$item" ] || continue
    _owed_item_check "$ws" "$stage" "$slice" "$round" "$nonce" "$skip" "$item"
    rc=$?
    [ $rc -gt $worst ] && worst=$rc
  done <<< "$items"
  return $worst
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  set -uo pipefail
  export LC_ALL=C
  case "${1:-}" in
    derive) shift; owed_derive "$@" ;;
    check) shift; owed_check "$@" ;;
    cu-total) shift; owed_cu_total "$@" ;;
    *) echo "usage: owed.sh derive <ws> <stage> <slice>" >&2
       echo "       owed.sh check <ws> <stage> <slice> [--round R] [--nonce N] [--skip a,b]" >&2
       echo "       owed.sh cu-total <ws> <slice>" >&2
       exit 2 ;;
  esac
fi
