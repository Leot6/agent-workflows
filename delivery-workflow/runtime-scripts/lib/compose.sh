#!/usr/bin/env bash
# lib/compose.sh — prompt composition + attempt fingerprints. This is
# ferry.sh's compose half, split out under architecture §4.1's layout freedom
# to keep ferry.sh ≤800 lines; only ferry.sh sources it.
#
# The ferry composes EVERY prompt from runtime-docs/templates/prompts/
# <stage>.<cold|warm>.md + the stages.tsv manifest columns — agents write only
# artifacts (owner ruling, architecture §12: closes the premise-injection
# channel). Required manifest item missing → template_error park (rc 4 here);
# optional missing → the literal marker "none" (visible, never blank).
#
# The volatile header (nonce, timestamps, ids, emit command) sits between
# marker lines and is EXCLUDED from the fingerprint; the manifest and template
# body are included, so a changed manifest is novelty. {nonce} in a template
# body is deliberately NOT substituted (it would defeat the fingerprint) — the
# header carries the nonce.

_COMPOSE_LIB_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
. "$_COMPOSE_LIB_DIR/state.sh"
. "$_COMPOSE_LIB_DIR/owed.sh"
. "$_COMPOSE_LIB_DIR/plan_binds.sh"
. "$_COMPOSE_LIB_DIR/rulings.sh"

COMPOSE_VOLATILE_BEGIN='<!-- volatile-header-begin (excluded from attempt fingerprint) -->'
COMPOSE_VOLATILE_END='<!-- volatile-header-end -->'

_compose_prev_slice() { # workspace slice -> previous non-superseded slice id
  local body
  body=$(state_get "$1" slices 2>/dev/null) || return 1
  printf '%s\n' "$body" | awk -v cur="$2" '
    /(^| )id=/ {
      id=""; st=""
      for(i=1;i<=NF;i++){ if($i ~ /^id=/){id=substr($i,4)} if($i ~ /^status=/){st=substr($i,8)} }
      if(id != "" && id < cur && st != "superseded" && st != "cancelled") last=id
    } END{ if(last=="") exit 1; print last }'
}

# The one author artifact that CROSSES slices, and therefore the one that ages.
# stages.tsv hands every other author artifact to its own slice (@nn — the
# reader's own); only the spec's TURNOVER_PREV reaches back to an earlier
# slice's work. So a turnover is read after an interval in which colleagues
# keep moving the branch it describes. Measured on a live
# topic's slice 10: a turnover opening "tip 87705841 ... resolving as A -> B -> C -> D" was
# true when written; another writer then rebased and merged -s ours, and 6 of
# its 7 commit references were no longer on the branch WHILE the document sat
# in the live slice-11 spec manifest. Nothing went red, because the objects
# still resolved — a pointer followed naively yields the RIGHT CONTENT at the
# WRONG address, and the reader's model of the branch is silently wrong.
#
# We ANNOTATE at hand-over instead of refusing at emit, and the choice is
# load-bearing in both directions:
#   - an emit-time ancestry gate cannot deliver the property (no later manifest
#     carries false branch claims), because the rot happens AFTER emit: every
#     token in that turnover was true when it was written;
#   - and the same gate would have REFUSED that turnover, for two SHAs its
#     author deliberately and correctly named as superseded, with the backup
#     ref that retains them.
# An annotation cannot false-positive harmfully: a correctly flagged superseded
# SHA is information, and it corroborates the author's own sentence rather than
# contradicting it.
#
# The tip is the PREVIOUS slice's binding, never the reader's. A doc-bound
# slice reads a code-bound slice's turnover; testing code commits against the
# doc checkout would read every one of them as off-branch.
#
# Header, not body — the binding line's reasoning below applies identically and
# for a sharper reason: this value depends on AMBIENT repo state, so in the
# body it would be a novelty source the loop detector cannot tell from a real
# input change (a repo growing a commit whose abbreviation matches a hex word
# would manufacture novelty on its own).
#
# The line is printed for EVERY reading, clean included: "all N still on
# <branch>" and the UNCHECKED forms are verdicts a reader can act on, while a
# line that appeared only on trouble would be indistinguishable from a check
# that never ran. Judged tokens are only those that resolve to a COMMIT in that
# checkout — a hex word that resolves to nothing, or to a tree (the measured
# turnover carried one), is not a branch claim and is never flagged.
# A CANCELLED span carries no turnover, and `@prev` walking past it is silent.
# `_compose_prev_slice` skips cancelled and superseded ids, correctly — nobody
# ran those stages, so there is nothing truthful to render for them. What was
# missing is the SIGNAL. Measured on a live topic's slice 10: slices
# 02-09 were completed MANUALLY outside the workflow and marked cancelled (the
# right status), so the slice-10 author received slice 01's turnover — eight
# slices and ~35 landed commits stale — with no artifact saying anything had
# happened in between. It nearly shipped a spec resting on a fact the skipped
# span had falsified: a flag retired inside the span, which the pinned plan
# still described as live.
#
# CANCELLED only, not superseded, and the distinction is the whole point: a
# superseded id was replaced by a re-split and its work never happened under
# that id, so there is no outcome to go looking for. A cancelled one may have
# been done by hand, which is exactly the measured case.
#
# A signal, not a rule: it refuses nothing and blocks nothing. Scheduling is
# already correct — cancelled satisfies `after=` — and synthesising a turnover
# for stages nobody ran would be inventing content, which the entry rules out.
_compose_prev_span_line() { # workspace slice -> one header line, or nothing
  local ws=$1 cur=$2 prev ids
  prev=$(_compose_prev_slice "$ws" "$cur" 2>/dev/null) || prev=""
  ids=$(state_get "$ws" slices 2>/dev/null | awk -v cur="$cur" -v prev="$prev" '
    /(^| )id=/ {
      id=""; st=""
      for (i = 1; i <= NF; i++) {
        if ($i ~ /^id=/) id = substr($i, 4)
        if ($i ~ /^status=/) st = substr($i, 8)
      }
      if (id != "" && st == "cancelled" && id < cur && (prev == "" || id > prev)) print id
    }' | sort | tr '\n' ' ')
  ids=${ids% }
  [ -n "$ids" ] || return 0
  if [ -n "$prev" ]; then
    echo "prev-span: slice(s) $ids are CANCELLED and sit between slice $prev (whose turnover you were handed) and yours — no turnover describes them, because those stages were never run under this workflow. If work landed in that span it is in the repository, plan.md and charters.md, and NOWHERE in the artifacts this manifest carries. Re-derive against the tree before relying on any premise the plan states about it."
  else
    echo "prev-span: slice(s) $ids are CANCELLED and sit below yours, and no earlier slice has a turnover — you were handed NO prior context at all. Anything that landed in that span is in the repository, plan.md and charters.md only. Re-derive against the tree before relying on any premise the plan states about it."
  fi
}

_compose_prev_turnover_line() { # workspace slice -> one header line, or nothing
  local ws=$1 slice=$2 prev f repo tip tok n=0 stale=""
  prev=$(_compose_prev_slice "$ws" "$slice" 2>/dev/null) || return 0
  f="$ws/slices/$prev/turnover.md"
  [ -f "$f" ] || return 0
  repo=$(binding_repo "$ws" "$prev" 2>/dev/null) || repo=""
  tip=$(binding_branch "$ws" "$prev" 2>/dev/null) || tip=""
  [ -n "$tip" ] || tip=HEAD
  if [ -z "$repo" ] || [ ! -d "$repo" ]; then
    echo "prev-turnover: slice $prev — commit references UNCHECKED (slice $prev's bound checkout did not resolve); treat any branch state it asserts as unverified"
    return 0
  fi
  if ! git -C "$repo" rev-parse -q --verify "$tip^{commit}" > /dev/null 2>&1; then
    echo "prev-turnover: slice $prev — commit references UNCHECKED (tip '$tip' does not resolve in $repo); treat any branch state it asserts as unverified"
    return 0
  fi
  while IFS= read -r tok; do
    git -C "$repo" rev-parse -q --verify "$tok^{commit}" > /dev/null 2>&1 || continue
    n=$((n + 1))
    git -C "$repo" merge-base --is-ancestor "$tok" "$tip" 2>/dev/null && continue
    stale="$stale $tok"
  done < <(command grep -oE '\b[0-9a-f]{7,40}\b' "$f" | sort -u)
  if [ -n "$stale" ]; then
    echo "prev-turnover: slice $prev — WARNING, these commit references are NO LONGER on $tip:$stale (of $n checked). The branch moved after slice $prev wrote it; re-derive from the progress ledger and git log instead of reading its branch state."
  else
    echo "prev-turnover: slice $prev — $n commit reference(s), all still on $tip"
  fi
}

_compose_latest_review() { # dir kind -> highest-round file
  # sort on the FILENAME's round field — a dot anywhere in the directory path
  # would shift the key and pick the wrong round (10 must beat 2).
  ls "$1/$2."*.md 2>/dev/null | while IFS= read -r f; do
    printf '%s\t%s\n' "$(basename "$f" | cut -d. -f2)" "$f"
  done | sort -k1,1n | tail -1 | cut -f2
}

# The plan excerpt a slice's spec author reads first. A plan is handed whole
# to every cold spec session — measured 987 KB on one topic, the slice's own
# two items 34 KB of it, sitting mid-file where long-context recall is
# weakest — while the spec-ready contract needs the plan's context, the
# items the charter binds, and the plan-level invariants. The cut follows
# the planning side's concatenation contract (plan_concat.sh: context →
# items → invariants → rederivation → delta; item heading `# W-<id>:`;
# delta `# Delta` / `## Refine log`): everything before the first item
# heading, the item blocks the charter's `## slice NN` section names, and
# everything after the last item block up to the first history heading.
# Item headings are accepted at H1–H3 (a single-file plan predating the
# directory form carries them at H3). Headings ride verbatim, so an anchor
# derived from the excerpt resolves in the plan; the full plan stays in the
# manifest as the citation authority. Prints the path, or MISSING:<why>.
#
# TWO ARMS, and the DECLARED one is tried first. A charter that states
# `plan-binds:` has said what its slice binds, and a declaration beats a
# convention: it is read as written (lib/plan_binds.sh), whatever shape the
# plan carries. The W-<id> arm below is what a charter falls back to when it
# declares nothing — the planning-side convention 3 of the 10 plans on disk
# use, which is why the declared field exists at all.
_compose_plan_slice() { # workspace slice plan.md charters.md
  local ws=$1 slice=$2 plan=$3 charter=$4 section ids out
  section=$(awk -v s="$slice" '
    $0 ~ ("^## slice " s "( |$)") { on=1; next }
    on && /^## / { exit }
    on' "$charter")
  [ -n "$section" ] || { echo "MISSING:charters.md has no '## slice $slice' section (split emit asserts one per index id)"; return; }
  # ARM 1 — the DECLARED binding. Absent, $spans is empty and we fall through.
  local spans nres unres
  local toks
  toks=$(plan_binds_tokens "$charter" "$slice")
  # The two sentinels a broken field yields, named rather than folded into the
  # generic no-anchor message: both once parsed to nothing, and nothing is what
  # a section with NO field parses to, so the arm fell through in silence to the
  # behaviour it exists to end.
  case "$toks" in
    '!EMPTY') echo "MISSING:charters.md '## slice $slice' has a plan-binds: label with no \`- §\` anchor under it (a blank line does not end the list; a non-anchor line does)"; return ;;
    '!DUPLICATE') echo "MISSING:charters.md '## slice $slice' opens plan-binds: twice — one list per slice, or the second silently unions into the first"; return ;;
  esac
  spans=$(printf '%s\n' "$toks" | plan_binds_spans "$plan")
  if [ -n "$toks" ] && [ -n "$spans" ]; then
    nres=$(printf '%s\n' "$spans" | command grep -c '^RESOLVED ' || true)
    unres=$(printf '%s\n' "$spans" | command grep '^UNRESOLVED ' | sed 's/^UNRESOLVED /§/' | tr '\n' ' ')
    # The floor, and it points at the SAFE side: a declaration none of whose
    # anchors resolve yields the whole plan back, never a head-only stub. The
    # emit gate is what stops this reaching a live prompt; this is the door
    # behind it, for a charter written before that gate existed.
    if [ "$nres" -eq 0 ]; then
      echo "MISSING:charters.md '## slice $slice' declares plan-binds: but no anchor resolves in plan.md — ${unres% }"; return
    fi
    mkdir -p "$ws/.runtime/prompts"
    out="$ws/.runtime/prompts/plan.$slice.md"
    { printf '<!-- plan excerpt for slice %s, derived by the ferry from plan.md: its head, plus the %s anchor(s) the charter DECLARES in plan-binds.' "$slice" "$nres"
      [ -z "${unres% }" ] || printf ' DECLARED BUT NOT FOUND IN THE PLAN: %s — read the full plan for those.' "${unres% }"
      printf ' the full plan is the citation authority — anchors here resolve there. -->\n\n'
      plan_binds_head "$plan"
      # Line-union, so a charter naming both a section and one of its own
      # subsections emits that subsection ONCE, and every kept line rides in
      # plan order however the anchors were listed.
      printf '%s\n' "$spans" | command grep -E '^(RESOLVED|CONTEXT) ' \
        | awk -v planfile="$plan" '
            { for (i = $2; i <= $3; i++) keep[i] = 1 }
            END { n = 0; while ((getline line < planfile) > 0) { n++; if (n in keep) print line } }'
    } > "$out"
    echo "$out"; return
  fi
  # ARM 2 — the W-<id> convention.
  ids=$(printf '%s\n' "$section" | command grep -oE '(^|[^A-Za-z0-9_])W-[A-Za-z0-9_]+' | sed 's/^[^W]*//' | sort -u | tr '\n' ' ')
  [ -n "${ids% }" ] || { echo "MISSING:charters.md '## slice $slice' names no W-<id> work item"; return; }
  command grep -qE '^#(#(#)?)? W-[A-Za-z0-9_]+:' "$plan" \
    || { echo "MISSING:plan.md carries no '# W-<id>:' item heading to excerpt from"; return; }
  mkdir -p "$ws/.runtime/prompts"
  out="$ws/.runtime/prompts/plan.$slice.md"
  awk -v want=" $ids" -v slice="$slice" '
    function level(l) { match(l, /^#+/); return RLENGTH }
    BEGIN { n = split(want, w, " "); for (i = 1; i <= n; i++) if (w[i] != "") named[w[i]] = 1; phase = "head" }
    /^#(#(#)?)? W-[A-Za-z0-9_]+:/ {
      if (L == 0) L = level($0)
      if (level($0) == L) {
        id = $0; sub(/^#+ /, "", id); sub(/:.*/, "", id)
        phase = "item"; keep = (id in named); if (keep) found[id] = 1
      }
    }
    phase == "item" && !/^#(#(#)?)? W-[A-Za-z0-9_]+:/ && /^#+ / && level($0) <= L { phase = "tail" }
    phase == "tail" && /^#(#(#)?)? (Delta|Refine log)( |$)/ { phase = "history" }
    phase == "head" || phase == "tail" || (phase == "item" && keep) { body = body $0 "\n" }
    END {
      miss = ""
      for (i = 1; i <= n; i++) if (w[i] != "" && !(w[i] in found)) miss = miss " " w[i]
      printf "<!-- plan excerpt for slice %s, derived by the ferry from plan.md: the plan\x27s context, the work items the charter names (%s), and its invariants; history sections dropped. the full plan is the citation authority — anchors here resolve there.", slice, want
      if (miss != "") printf " NAMED BY THE CHARTER BUT NOT FOUND IN THE PLAN:%s — read the full plan for those.", miss
      printf " -->\n\n%s", body
    }' "$plan" > "$out"
  echo "$out"
}

# Resolve one manifest path-pattern. Prints the absolute path, or:
#   MISSING:<why>  — pattern resolves nowhere
#   NONE           — no referent by construction (e.g. @prev on the first slice)
_compose_resolve() { # workspace slice round pattern
  local ws=$1 slice=$2 round=$3 pat=$4 wroot=$OWED_WORKFLOW_ROOT p
  case "$pat" in
    cards/*|review-standards.md|protocol.md|operations.md|commit-messages.md)
      p="$wroot/runtime-docs/$pat"
      [ -f "$p" ] && { echo "$p"; return; }
      echo "MISSING:workflow doc $p absent"; return ;;
    plan.md)
      p="$(cd "$ws/.." 2>/dev/null && pwd)/plan.md"
      [ -f "$p" ] && { echo "$p"; return; }
      echo "MISSING:boundary artifact $p absent (the plan workflow's output is delivery's input)"; return ;;
    plan_slice)
      # derived view over the two boundary inputs above; resolves them through
      # their own arms so the plan path is hard-coded in exactly one place
      local plan charter
      plan=$(_compose_resolve "$ws" "$slice" "$round" plan.md)
      case "$plan" in MISSING:*) echo "$plan"; return ;; esac
      charter="$ws/charters.md"
      [ -f "$charter" ] || { echo "MISSING:$charter absent (split writes it)"; return; }
      _compose_plan_slice "$ws" "$slice" "$plan" "$charter"; return ;;
    slices_index|progress|ledger|decisions|gates|observations|learnings)
      local surf=$pat body
      [ "$pat" = "slices_index" ] && surf=slices
      body=$(state_get "$ws" "$surf" 2>/dev/null) || { echo "MISSING:store surface '$surf' absent"; return; }
      mkdir -p "$ws/.runtime/prompts"
      p="$ws/.runtime/prompts/surface.$surf.txt"
      printf '%s\n' "$body" > "$p"
      echo "$p"; return ;;
    gates@nn|ledger@nn|decisions@nn)
      # One slice's rows of a stream the whole topic appends to. A slice-level
      # stage is scoped to its slice (postcheck C1; turnover's "this slice's
      # stage transitions"; precheck P8's "each decisions-surface entry of this
      # slice"), so the dump is filtered to rows stamped slice=NN;
      # a row with NO slice field (run-level ledger events, attestations from
      # before the stamp) is handed over — filtering is by a field that says
      # otherwise, never by the absence of one. Slice-named file: a stale
      # whole-surface dump can never pass as the slice view.
      local surf=${pat%@nn} body
      body=$(state_get "$ws" "$surf" 2>/dev/null) || { echo "MISSING:store surface '$surf' absent"; return; }
      mkdir -p "$ws/.runtime/prompts"
      p="$ws/.runtime/prompts/surface.$surf.$slice.txt"
      printf '%s\n' "$body" | awk -v s="$slice" '
        { keep=1; for(i=1;i<=NF;i++) if($i ~ /^slice=/ && substr($i,7) != s) keep=0 }
        keep' > "$p"
      echo "$p"; return ;;
    coding_rules)
      # The project's OWN written conventions, resolved against the code repo:
      # commit.* keys hold what a regex can hold, and everything else the
      # project rules (message length, body policy, what may not appear in a
      # message at all) lives in this file. It is the project's for both
      # checkouts — the commit convention is the project's, not the repo's
      # (architecture §12, two-repo ruling D-iv) — so it resolves against
      # repo= whatever this slice is bound to. Undeclared is legal: NONE.
      local cr crepo
      cr=$(project_get "$ws" coding_rules 2>/dev/null) || cr=""
      [ -n "$cr" ] || { echo "NONE"; return; }
      crepo=$(project_get "$ws" repo 2>/dev/null) || crepo=""
      case "$cr" in /*) p=$cr ;; *) p="$crepo/$cr" ;; esac
      [ -f "$p" ] && { echo "$p"; return; }
      echo "MISSING:project.kv coding_rules=$cr does not resolve under repo=$crepo"; return ;;
    config.snapshot)
      p="$ws/.runtime/config.snapshot.kv"
      [ -f "$p" ] && { echo "$p"; return; }
      echo "MISSING:resolved config snapshot $p absent (launch/ensure_run_surface writes it)"; return ;;
    reslice.pending)
      # A pending re-slice merge proposal: the ferry stamped the proposing
      # slice at turnover(reslice); the proposal text is that slice's turnover.
      local from
      from=$(state_field "$ws" attempts reslice_from 2>/dev/null) || from=""
      [ -n "$from" ] || { echo "NONE"; return; }
      p="$ws/slices/$from/turnover.md"
      [ -f "$p" ] && { echo "$p"; return; }
      echo "MISSING:reslice proposal points at $p which is absent"; return ;;
    rulings.pending)
      local lines rc h
      # store fault ≠ absent (review-standards §13's contract list): a corrupt
      # rulings surface must never be narrated as "no referent by construction"
      # — that sentence claims the store was READ and holds nothing for this
      # slice. MISSING renders the fault visibly in the manifest (optional
      # item); the next launch parks store_fault on the checksum (state.sh's
      # startup sweep). Mid-run posture unchanged: loud, survivable (VD-17).
      # WHICH rulings address a slice is lib/rulings.sh's one selector (this
      # slice's rows plus every scope=topic row), shared with the emit door.
      lines=$(rulings_addressed "$ws" "$slice"); rc=$?
      [ "$rc" -eq 3 ] && { echo "MISSING:rulings surface FAULT (checksum/parse) — a corrupt store is not 'no rulings'"; return; }
      [ "$rc" -eq 0 ] || { echo "NONE"; return; }
      mkdir -p "$ws/.runtime/prompts"
      # Content-addressed: path identity ≡ content identity. A warm session
      # that recognises the path has by construction already read exactly
      # these bytes; a changed ruling set yields a path it has never seen
      # (a two-anchor defect: a ruling landing mid-park rewrote the same path a warm session had
      # already read). The hash input is the exact bytes written, so the path
      # self-verifies (md5sum < file). It feeds compose_fingerprint verbatim:
      # unchanged set → stable fingerprint (no_novelty stays armed); new
      # ruling → novel — 70-fingerprint pins both directions. Full-width md5:
      # a truncated hash colliding here silently reintroduces the defect, and
      # full width makes "no collision analysis needed" a property.
      h=$(printf '%s\n' "$lines" | md5sum | cut -c1-32)
      p="$ws/.runtime/prompts/rulings.$slice.$h.txt"
      printf '%s\n' "$lines" > "$p"
      echo "$p"; return ;;
    *_latest)
      local kind=${pat##*/}; kind=${kind%_latest}
      local dir="$ws/slices/$slice"
      p=$(_compose_latest_review "$dir" "$kind")
      [ -n "$p" ] && { echo "$p"; return; }
      echo "MISSING:no $dir/$kind.<round>.md exists yet"; return ;;
    *_review.prev|*.prev)
      local kind=${pat##*/}; kind=${kind%.prev}; kind=${kind%_review}
      local dir="$ws/slices/$slice"
      [ "$kind" = "splitcheck" ] && dir="$ws/slices/00"
      if [ "$round" -ge 2 ] && [ -f "$dir/$kind.$((round - 1)).md" ]; then
        echo "$dir/$kind.$((round - 1)).md"; return
      fi
      echo "NONE"; return ;;
    *@prev*)
      local prev
      prev=$(_compose_prev_slice "$ws" "$slice") || { echo "NONE"; return; }
      p="$ws/${pat//@prev/$prev}"
      [ -f "$p" ] && { echo "$p"; return; }
      echo "MISSING:$p absent (previous slice $prev owes it)"; return ;;
    *@nn*)
      p="$ws/${pat//@nn/$slice}"
      [ -f "$p" ] && { echo "$p"; return; }
      echo "MISSING:$p absent"; return ;;
    *)
      p="$ws/$pat"
      [ -f "$p" ] && { echo "$p"; return; }
      echo "MISSING:$p absent"; return ;;
  esac
}

# compose_prompt ws stage slice round attempt nonce mode out_file
# rc 0 composed · 4 template_error (reason on stdout — self-describing park).
compose_prompt() {
  local ws=$1 stage=$2 slice=$3 round=$4 attempt=$5 nonce=$6 mode=$7 out=$8
  local row req opt modeword tpl wroot=$OWED_WORKFLOW_ROOT
  row=$(owed_stage_row "$stage") || { echo "template_error: stage '$stage' not in stages.tsv"; return 4; }
  req=$(printf '%s\n' "$row" | awk -F'\t' '{print $7}')
  opt=$(printf '%s\n' "$row" | awk -F'\t' '{print $8}')
  case "$mode" in warm*) modeword=warm ;; *) modeword=cold ;; esac
  tpl="$wroot/runtime-docs/templates/prompts/$stage.$modeword.md"
  if [ ! -f "$tpl" ]; then
    echo "template_error: prompt template $tpl absent — look at runtime-docs/templates/prompts/"
    return 4
  fi
  # Named substitution: each manifest entry fills its {NAME} placeholder inline
  # (templates place items at semantically meaningful positions). Required
  # missing => template_error park; optional/none => a literal "none" marker.
  local body record_sh="$wroot/runtime-scripts/session/record.sh"
  local gates_sh="$wroot/runtime-scripts/lib/gates.sh"
  body=$(cat "$tpl")
  # Manifest-resolved input paths are collected into a sidecar ($out.inputs):
  # compose_fingerprint hashes their CONTENT, so an input outside $ws (the
  # plan.md boundary artifact above the workspace) is novelty too — the
  # settled formula is manifest-RESOLVED input content, not $ws-prefixed
  # tokens (a plan hand-edit must never park no_novelty).
  local e name pat p inputs=""
  while IFS= read -r e; do
    [ -n "$e" ] || continue
    name=${e%%=*}; pat=${e#*=}
    p=$(_compose_resolve "$ws" "$slice" "$round" "$pat")
    case "$p" in
      MISSING:*)
        echo "template_error: required manifest item $name=$pat for stage $stage — ${p#MISSING:}"
        return 4 ;;
      NONE) body=${body//\{$name\}/none (no referent by construction)} ;;
      *) body=${body//\{$name\}/$p}; inputs="$inputs$p"$'\n' ;;
    esac
  done < <(printf '%s\n' "$req" | tr ';' '\n')
  while IFS= read -r e; do
    [ -n "$e" ] || continue
    name=${e%%=*}; pat=${e#*=}
    p=$(_compose_resolve "$ws" "$slice" "$round" "$pat")
    case "$p" in
      MISSING:*) body=${body//\{$name\}/none (${p#MISSING:})} ;;
      NONE) body=${body//\{$name\}/none (no referent by construction)} ;;
      *) body=${body//\{$name\}/$p}; inputs="$inputs$p"$'\n' ;;
    esac
  done < <(printf '%s\n' "$opt" | tr ';' '\n')
  body=${body//\{STAGE\}/$stage}
  body=${body//\{SLICE\}/$slice}
  body=${body//\{ROUND\}/$round}
  body=${body//\{WORKSPACE\}/$ws}
  body=${body//\{RECORD_SH\}/$record_sh}
  case "$stage" in impl|fix)
    # The implementer's model/effort are first-class per-agent parameters
    # (backend-seam.md §3), resolved default -> topic -> (slice, implementer)
    # and handed to the author, who requests them on each sub-agent dispatch.
    local im ie
    im=$(config_get agent.implementer.model --topic-dir "$ws" --slice "$slice" --agent implementer 2>/dev/null) || im="(backend default)"
    ie=$(config_get agent.implementer.effort --topic-dir "$ws" --slice "$slice" --agent implementer 2>/dev/null) || ie="(backend default)"
    body=${body//\{IMPLEMENTER_MODEL\}/$im}
    body=${body//\{IMPLEMENTER_EFFORT\}/$ie}
  esac
  # The live nonce exists ONLY in the volatile header (a nonce in the body would
  # make every attempt's fingerprint novel — blinding the loop detector).
  body=${body//\{nonce\}/(copy from the volatile header)}
  body=${body//\{NONCE\}/(copy from the volatile header)}
  body=${body//\{ATTEMPT\}/(see the volatile header)}
  local leftover
  leftover=$(printf '%s\n' "$body" | command grep -oE '\{[A-Za-z_]+\}' | sort -u | tr '\n' ' ')
  if [ -n "${leftover% }" ]; then
    echo "template_error: unresolved placeholder(s) $leftover in $tpl"
    return 4
  fi
  mkdir -p "$(dirname "$out")"
  {
    echo "$COMPOSE_VOLATILE_BEGIN"
    echo "nonce=$nonce"
    # No spawn mode here. Every prompt template states "this prompt never
    # states the session's spawn mode; freshness in your provenance header is
    # yours to derive", and the header contradicted it for eleven slices. The
    # field was not merely redundant: its value is decide_mode's INTENDED mode,
    # resolved before the spawn, and a warm intent cold-falls back whenever the
    # held session is dead, refuses injection, or was produced by another
    # backend — so a reviewer could read `mode=warm-author` off a session that
    # was spawned cold. What the mode is actually recorded on: the template
    # this prompt rendered from (warm vs cold body, chosen from $mode above),
    # and the ledger's own `mode=`, which is written after the spawn and says
    # what happened rather than what was meant.
    echo "stage=$stage slice=$slice round=$round attempt=$attempt"
    echo "workspace=$ws"
    # The slice's bound checkout — the agent's ONLY channel for it (the pty
    # spawn carries no cwd, and no template can know it). Header, not body:
    # excluded from the fingerprint, and the binding is immutable per slice id
    # by construction, so it can never be a hidden novelty source either.
    echo "binding: kind=$(binding_kind "$ws" "$slice") repo=$(binding_repo "$ws" "$slice" 2>/dev/null) branch=$(binding_branch "$ws" "$slice" 2>/dev/null)"
    # The previous slice's turnover is the only input that ages between writing
    # and reading; its commit references are re-resolved HERE, at hand-over.
    _compose_prev_turnover_line "$ws" "$slice"
    # …and the span it walked past, if any: the turnover that DID arrive says
    # nothing about the slices between, and neither did anything else.
    _compose_prev_span_line "$ws" "$slice"
    echo "composed_t=$(date +%s)"
    echo "Your FINAL action (the Stop gate blocks the turn until it succeeds):"
    echo "  $record_sh emit $ws --stage $stage --nonce $nonce --verdict <verdict> --confidence HIGH|MED|LOW [role fields per its usage]"
    echo "Record landed commit-units as they land (impl/fix):"
    echo "  $record_sh progress $ws --cu <N> --sha <sha>"
    echo "Other write paths on the same tool: 'decision' (DPs), 'learn' (leak-tagged findings), 'observe' (workflow defects) — see its usage."
    # The project-gate attestation path, here for the same reason record.sh is:
    # a stage has no cwd and no template can know one, so an absolute path built
    # from the workflow root is the ONLY channel. It was not here, the emit
    # refusal names acceptance alone, and per-unit build/lint/test was therefore
    # author discretion — measured, two consecutive slices of one
    # topic recorded differently, one attesting on the gates surface and the
    # next leaving /tmp logs, all green and none citable.
    echo "Attest EVERY project gate your spec's gate plan names, not only acceptance (impl/fix):"
    echo "  $gates_sh project $ws <build|lint|test|acceptance>"
    echo "$COMPOSE_VOLATILE_END"
    printf '%s\n' "$body"
  } > "$out"
  printf '%s' "$inputs" | sort -u > "$out.inputs"
  return 0
}

# Fingerprint = hash(prompt body minus volatile header ⊕ owed-artifact content
# hashes ⊕ manifest-resolved input content hashes ⊕ last failure class) —
# the settled formula (architecture.md §12): an owner hand-edit to any
# resolved input (plan, charter, config snapshot) reads as novelty; incidental
# file churn outside the manifest counts as nothing.
compose_fingerprint() { # ws stage slice prompt_file lastfail
  local ws=$1 stage=$2 slice=$3 prompt=$4 lastfail=$5
  {
    awk -v b="$COMPOSE_VOLATILE_BEGIN" -v e="$COMPOSE_VOLATILE_END" \
        '$0==b{skip=1} !skip{print} $0==e{skip=0}' "$prompt"
    # Input sensitivity: hash every manifest-RESOLVED input (the sidecar the
    # compose step wrote — covers boundary inputs above $ws like plan.md), so
    # an input changed outside the normal flow (an owner hand-edit before
    # relaunch) reads as novelty instead of a wrong no_novelty park. The
    # sidecar IS the complete input set: prompt bodies carry no other
    # workspace paths (templates interpolate only manifest values — measured
    # across all 11 stages).
    local ref
    while IFS= read -r ref; do
      # Machine-written observation streams are excluded: the attempt ITSELF
      # appends to ledger (spawn events) and gates (gate runs), so hashing
      # their dumps would make every retry read as novel and no_novelty could
      # never fire for the stages that carry them. Session work products
      # (progress/decisions/observations/learnings) stay in — their change is
      # genuine novelty.
      case "$ref" in */surface.ledger.txt|*/surface.gates.txt|*/surface.ledger.[0-9]*.txt|*/surface.gates.[0-9]*.txt) continue ;; esac
      [ -f "$ref" ] && { printf 'input %s ' "$ref"; md5sum < "$ref"; }
    done < <(sort -u "$prompt.inputs" 2>/dev/null)
    local item f
    while IFS= read -r item; do
      [ -n "$item" ] || continue
      case "$item" in
        handoff|slices_index|@cu-list) continue ;;
        cu.*)
          state_get "$ws" progress 2>/dev/null \
            | command grep -E "(^| )slice=$slice( |$)" \
            | command grep -E "(^| )cu=${item#cu.}( |$)" || true
          continue ;;
        spec.md|conformance.md|turnover.md) f="$ws/slices/$slice/$item" ;;
        charters.md|closeout.md) f="$ws/$item" ;;
        validation_note) f="$ws/slices/00/validation_note.md" ;;
        splitcheck_review) f=$(_compose_latest_review "$ws/slices/00" splitcheck) ;;
        precheck_review) f=$(_compose_latest_review "$ws/slices/$slice" precheck) ;;
        postcheck_review) f=$(_compose_latest_review "$ws/slices/$slice" postcheck) ;;
        *) continue ;;
      esac
      [ -n "$f" ] && [ -f "$f" ] && { printf '%s ' "$item"; md5sum < "$f"; }
    done < <(owed_derive "$ws" "$stage" "$slice" 2>/dev/null)
    printf 'lastfail=%s\n' "$lastfail"
  } | md5sum | awk '{print $1}'
}
