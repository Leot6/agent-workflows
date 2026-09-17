#!/usr/bin/env bash
# lib/gates.sh — tier-1 machine gates (design/review-and-slices.md §1, §4.1).
# Every result is a harness-attested store record (surface `gates`, writer
# class `gate`) pinned to the project repo's HEAD SHA + tree fingerprint —
# forgery/staleness is mechanically visible; the reviewer never re-runs these.
#
# The claims-table contract lives with the family that owns it, in
# lib/gates_claims.sh's header — one closed vocabulary, stated once, beside the
# code that parses it.
#
# rc: 0 PASS · 1 FAIL (every failure line self-describing) · 2 refused · 3 fault.

_GATES_LIB_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
. "$_GATES_LIB_DIR/state.sh"
. "$_GATES_LIB_DIR/config.sh"
. "$_GATES_LIB_DIR/md_span.sh"
. "$_GATES_LIB_DIR/plan_binds.sh"

# Two-layer binding resolution: none of the six gate functions — nor the
# reviewer's CLI form (`gates.sh project <ws> acceptance`) — carries a slice
# argument, so the ACTIVE slice comes from the stage surface and the binding
# primitive turns it into a checkout. Sound because every gate call happens
# inside the stage of the slice it gates (emit refuses a stage mismatch;
# postcheck's CLI run sits in its own stage). No stage surface — fixtures,
# ad-hoc runs — resolves to code, the pre-binding behavior.
# Named boundary: this reader treats only the ABSENT stage surface (fixtures,
# ad-hoc runs). A CORRUPT one is already fatal upstream of every gate call —
# cmd_emit faults on it before the first gate, the ferry die_stores on it — so
# there is no live path that reaches a gate over an unreadable stage surface.

# ------------ binding primitives: which repo, which slice, which record -----

_gates_slice() { state_field "$1" stage slice 2>/dev/null || true; }
_gates_kind() { binding_kind "$1" "$(_gates_slice "$1")"; }
_gates_repo() { binding_repo "$1" "$(_gates_slice "$1")"; }
# The topic's OTHER declared checkout, for path resolution only: a doc artifact
# legitimately cites a code path and back, and a two-repo topic must not turn
# every cross-repo citation into a dead link. Empty when only one is declared.
_gates_repo_other() { # workspace -> path or empty
  if [ "$(_gates_kind "$1")" = "doc" ]; then project_get "$1" repo 2>/dev/null
  else project_get "$1" doc.repo 2>/dev/null; fi
  return 0
}

# Worktree-state fingerprint: paths AND content. `status --porcelain` alone
# lists paths + status letters — the same path dirtied with DIFFERENT bytes
# hashed identically, so a stale acceptance PASS survived a content swap.
# Tracked content rides `diff HEAD`; untracked files contribute name+size+
# mtime (a bug barrier, honestly not an adversarial one — stated per §1).
gates_dirty_fp() { # repo -> 8-char fingerprint
  { git -C "$1" status --porcelain 2>/dev/null
    git -C "$1" diff HEAD 2>/dev/null
    # NUL-delimited: an awk field split truncated spaced names, the swallowed
    # stat dropped the file from the fingerprint entirely.
    git -C "$1" status --porcelain -z 2>/dev/null \
      | tr '\0' '\n' | awk 'sub(/^\?\? /,"")' \
      | while IFS= read -r uf; do plat_stat_nsm "$1/$uf"; done
  } | md5sum | cut -c1-8
}

_gates_record() { # workspace gate result detail
  local ws=$1 gate=$2 result=$3 detail=$4 repo slice sha=none tree=none dirty=none
  # The active slice rides every row: the surface is handed to postcheck
  # reviewers, and without it a topic's whole gate history is one unscopable
  # block (560 rows by slice 17, measured). none when no stage is active.
  slice=$(_gates_slice "$ws"); slice=${slice:-none}
  repo=$(_gates_repo "$ws" 2>/dev/null || true)
  if [ -n "$repo" ] && git -C "$repo" rev-parse HEAD > /dev/null 2>&1; then
    sha=$(git -C "$repo" rev-parse HEAD)
    tree=$(git -C "$repo" rev-parse 'HEAD^{tree}')
    dirty=$(gates_dirty_fp "$repo")
  fi
  state_append "$ws" gates gate \
    "v=1 t=$(date +%s) slice=$slice gate=$gate result=$result sha=$sha tree=$tree dirty=$dirty detail=$detail" \
    > /dev/null \
    || echo "WARN: gate attestation for '$gate' could NOT be appended to the gates surface — the reviewer's record is stale; inspect the store (gate verdict unchanged)" >&2
}

# Effective cap value + source layer. Project.kv same-named key overrides the
# config chain in either direction (owner ruling, architecture §12).
_gates_cap() { # workspace capkey -> "value<TAB>source"
  local ws=$1 key=$2 v out
  if v=$(project_get "$ws" "$key" 2>/dev/null); then
    printf '%s\tproject.kv\n' "$v"; return 0
  fi
  out=$(config_get "$key" --topic-dir "$ws" --with-source) || return $?
  printf '%s\n' "$out"
}

_gates_cap_for_file() { # path -> capkey
  local base=${1##*/}
  # Topic artifacts first — their caps name what they are, and the generic
  # source/test classes below must never catch them.
  case "$1" in
    */spec.md) echo cap.spec_lines; return ;;
    */precheck.*.md|*/postcheck.*.md|*/splitcheck.*.md) echo cap.review_lines; return ;;
    # Topic artifacts that grow with slice count (charters/closeout) or round
    # count (turnover/conformance) must not fall into the source-file cap:
    # an 800-line refusal naming "source file" at slice N is a miscap.
    */charters.md|*/closeout.md|*/turnover.md|*/conformance.md|*/validation_note.md|*/halt.*.md) echo cap.artifact_lines; return ;;
  esac
  # The self-test cap keys on the FILE'S OWN NAME or its test DIRECTORY, never
  # on the path around it: this once read `*test*` over the whole path, so any
  # file deployed under a path merely CONTAINING test/Test/self-check (a
  # workspace under ~/projects/unittest/, a TMPDIR with "test" in it) silently
  # took the looser self-test cap instead of the source cap — found by an
  # independent review reproducing it through the suite's own scratch dir.
  # Both shapes below, because neither subsumes the other: a tests/ directory
  # names its family by location, a foo_test.cc by its own name. The directory
  # arm carries Test/, __tests__/ and testsuite/ beside tests/ and test/ — all
  # the same location-names-family shape. testsuite/ arrived last, unprompted
  # by any audit finding, as the one review noticed the class's own comment
  # had silently left the sibling shape out while naming Test/ and __tests__/.
  case "$1" in
    */self-check/*|*/selfcheck/*|*/tests/*|*/test/*|*/Test/*|*/__tests__/*|*/testsuite/*) echo cap.selftest_file; return ;;
  esac
  case "$base" in
    *test*|*Test*) echo cap.selftest_file; return ;;
  esac
  echo cap.source_file
}


# ----------------------------------------------------------------- caps -----

gates_caps() { # workspace file...
  local ws=$1; shift
  local f key out cap src lines fails="" tool
  for f in "$@"; do
    [ -f "$f" ] || { fails="$fails file=$f:absent"; echo "cap gate: file absent: $f" >&2; continue; }
    key=$(_gates_cap_for_file "$f")
    out=$(_gates_cap "$ws" "$key") || { echo "FAULT: cap '$key' unresolvable" >&2; return 3; }
    cap=${out%%	*}; src=${out#*	}
    lines=$(( $(wc -l < "$f") ))
    if [ "$lines" -gt "$cap" ]; then
      echo "cap_exceeded: file=$f lines=$lines cap=$key=$cap source=$src"
      fails="$fails $f:$lines>$key=$cap($src)"
    fi
  done
  tool=$(project_get "$ws" function_length_tool 2>/dev/null || true)
  local fncap
  fncap=$(_gates_cap "$ws" cap.function 2>/dev/null | cut -f1) || fncap=""
  if [ -n "$tool" ]; then
    echo "note: function-length enforcement delegated to project tool: $tool (effective cap.function=${fncap:-unset})"
  else
    echo "note: no function_length_tool declared — function-length (cap.function=${fncap:-unset}) is a reviewer checklist item, not a gate (honest downgrade)"
  fi
  if [ -n "$fails" ]; then
    _gates_record "$ws" caps FAIL "$fails"
    return 1
  fi
  _gates_record "$ws" caps PASS "files=$# fn_tool=${tool:-none}"
}

. "$_GATES_LIB_DIR/gates_commit.sh"   # the commit gate family (message, ids, amend advice, gates_commit)
. "$_GATES_LIB_DIR/gates_claims.sh"   # the claims gate family (table parser, per-type row checks, gates_claims)

# Resolve an artifact-cited path: absolute as-is, else relative to the slice's
# BOUND checkout, else the topic's other checkout (cross-repo citations stay
# live), else workspace-relative, else workflow-root-relative (reviews
# legitimately cite runtime-docs/*). Prints the resolved path; rc 1 unresolvable.
_gates_resolve_path() { # workspace path
  local ws=$1 p=$2 repo
  case "$p" in
    /*) [ -e "$p" ] && { printf '%s\n' "$p"; return 0; } ;;
    *)
      repo=$(_gates_repo "$ws" 2>/dev/null || true)
      [ -n "$repo" ] && [ -e "$repo/$p" ] && { printf '%s\n' "$repo/$p"; return 0; }
      repo=$(_gates_repo_other "$ws" 2>/dev/null || true)
      [ -n "$repo" ] && [ -e "$repo/$p" ] && { printf '%s\n' "$repo/$p"; return 0; }
      [ -e "$ws/$p" ] && { printf '%s\n' "$ws/$p"; return 0; }
      [ -e "$CONFIG_WORKFLOW_ROOT/$p" ] && { printf '%s\n' "$CONFIG_WORKFLOW_ROOT/$p"; return 0; } ;;
  esac
  return 1
}

# Fenced code is QUOTED DATA, not the document's own structure or claims: a
# heading, claims table, or path inside ``` fences is evidence being cited,
# never a section, a claim row, or a live citation (a fenced-only doc passed
# all three doc gates; a fenced transcript's dead /tmp path would false-kill).
_gates_strip_fences() { # file -> unfenced lines on stdout
  awk '/^[[:space:]]*(```|~~~)/{f=!f; next} !f' "$1"
}


# Environment sweep: every ABSOLUTE path and every path:NN pin in the
# artifact must resolve (design/review-and-slices.md §4.1 — that pair is the
# promise). A relative slash token WITHOUT a pin is prose, not a claim:
# closed vocabularies (A/B/C/wording, low/med/high, build/lint/test) and
# free-prose doc references are the reviewer's checklist, honestly not the
# gate's — sweeping them refused every template-following artifact.

# ----- path + fence primitives, shared by every family below AND by the -----
# two sourced ones (gates_claims.sh, gates_commit.sh) and by lib/owed.sh —
# which is why they are here and not in any one family.

gates_env_sweep() { # workspace artifact
  local ws=$1 art=$2
  [ -f "$art" ] || { echo "refuse: artifact $art absent" >&2; return 2; }
  local tok path nn file failed=0 n=0
  while IFS= read -r tok; do
    case "$tok" in
      *://*|*'{'*|*'*'*|*'@'*) continue ;;
    esac
    case "$tok" in
      /*) # absolute: a claim when it has a SECOND segment (/a/b) or a :NN pin.
          # A lone `/word` mid-sentence — a fraction, an option, a bare name —
          # is prose: measured 8 of 12 post-gate hits over six archived trees;
          # nothing a delivery cites lives at the filesystem root.
          printf '%s' "${tok#/}" | command grep -qE '/[A-Za-z0-9_.~-]|:[0-9]+$' || continue ;;
      *) printf '%s' "$tok" | command grep -qE ':[0-9]+$' || continue ;;  # relative without :NN pin: prose
    esac
    n=$((n + 1))
    nn=""
    if printf '%s' "$tok" | command grep -qE ':[0-9]+$'; then
      nn=${tok##*:}; path=${tok%:*}
    else
      path=$tok
    fi
    if ! file=$(_gates_resolve_path "$ws" "$path"); then
      local other; other=$(_gates_repo_other "$ws" 2>/dev/null || true)
      echo "env sweep: '$tok' does not resolve (tried absolute, $(_gates_repo "$ws" 2>/dev/null || echo '<no repo>'),${other:+ $other,} $ws, $CONFIG_WORKFLOW_ROOT)"
      failed=1
      continue
    fi
    if [ -n "$nn" ] && [ -f "$file" ] && [ "$nn" -gt "$(wc -l < "$file")" ]; then
      echo "env sweep: '$tok' pins line $nn but $file has $(( $(wc -l < "$file") )) lines"
      failed=1
    fi
  done < <(_gates_strip_fences "$art" \
           | command grep -oE '(/|[A-Za-z0-9_.~-]+/)[A-Za-z0-9_./-]+(:[0-9]+)?' \
           | sed 's/[.,;)]*$//' | sort -u)
  if [ $failed -eq 1 ]; then
    _gates_record "$ws" env_sweep FAIL "artifact=$art candidates=$n"
    return 1
  fi
  _gates_record "$ws" env_sweep PASS "artifact=$art candidates=$n"
}

# Durable citations only, for a prose artifact that carries no claims table.
# A `path:NN` keeps RESOLVING after the file grows above it — to whatever now
# occupies that line — so the env sweep's question ("does it resolve?") cannot
# see the rot, and the reader is handed a plausible wrong target rather than a
# dead link. Measured on a live charter, written once at split and read by
# every slice's spec author many commits later: 6 of 16 addresses re-pointed
# at a different construct, three of them instructions for slices still
# pending; the same round's harvest then reproduced it in this tree's own
# durable home (four of four addresses moved within the round). The claims
# resolver already refuses a line pin as an anchor; this is the same rule at
# the door of an artifact that has no table. What survives is what the tables
# use — `path::symbol`, `path#heading`, a comment's own first line — and a
# range stamp (`path:L<a>-L<b> @ <sha>`, process evidence) is not a pin.
# Fenced blocks are quoted data, as for every gate here; a URL's port is not a
# citation. Every hit is printed with its line, never only counted.

# -------------- citation gates (env sweep, line pins, charter sections) -----

gates_line_pins() { # workspace artifact
  local ws=$1 art=$2
  [ -f "$art" ] || { echo "refuse: artifact $art absent" >&2; return 2; }
  local hits n
  hits=$(awk '
    /^[[:space:]]*(```|~~~)/ { f = !f; next }
    !f {
      line = $0
      gsub(/[A-Za-z][A-Za-z0-9+.-]*:\/\/[^[:space:])>]*/, " ", line)   # URLs out first
      while (match(line, /((\/|[A-Za-z0-9_.~-]+\/)[A-Za-z0-9_.\/-]+|[A-Za-z0-9_~-]+\.[A-Za-z0-9]+):[0-9]+(-[0-9]+)?/)) {
        print NR ": " substr(line, RSTART, RLENGTH)
        line = substr(line, RSTART + RLENGTH)
      }
    }' "$art")
  n=$(printf '%s' "$hits" | command grep -c . || true)
  if [ "$n" -gt 0 ]; then
    echo "line pins: $n citation(s) by line number in $art — a pin keeps resolving after the file grows above it, to whatever sits there now; name the construct instead (path::symbol, path#heading, or the comment's own first line):"
    printf '%s\n' "$hits" | sed 's/^/  line /'
    _gates_record "$ws" line_pins FAIL "artifact=$art pins=$n"
    return 1
  fi
  _gates_record "$ws" line_pins PASS "artifact=$art pins=0"
}

# Charter sections: one `## slice NN` heading per declared index id. The
# section is the slice's unit of hand-over — the spec author reads it, and
# the plan excerpt (compose plan_slice) derives from the work items it
# names — so an id with no section is handed the whole charter, or nothing.
# A trailing title after the id is fine; the id is matched to its boundary
# (`## slice 021` is not slice 02's).
gates_charter_sections() { # workspace artifact ids...
  local ws=$1 art=$2; shift 2
  [ -f "$art" ] || { echo "refuse: artifact $art absent" >&2; return 2; }
  local id missing="" n=0
  for id in "$@"; do
    command grep -qE "^## slice $id( |$)" "$art" || { missing="$missing slice $id"; n=$((n + 1)); }
  done
  if [ "$n" -gt 0 ]; then
    echo "charter sections: $n declared id(s) with no \`## slice NN\` section in $art — every index id owes one (it is what the slice's spec author is handed):$missing"
    _gates_record "$ws" charter_sections FAIL "artifact=$art missing=$n"
    return 1
  fi
  _gates_record "$ws" charter_sections PASS "artifact=$art ids=$#"
}

# Declared plan binding: every anchor a charter states in `plan-binds:` resolves
# to a real heading in plan.md. This is the door the declared excerpt arm stands
# behind (lib/plan_binds.sh, compose.sh `_compose_plan_slice`): the composer
# cuts on exactly what the charter declares, so an anchor pointing at a section
# the plan does not carry silently costs that slice's author the material — and
# the cheapest place to learn it is here, at split emit, while the author is
# still holding both documents.
#
# SCOPE, and it is deliberately narrow on the half that is contested. This gate
# refuses a BROKEN declaration; it does NOT demand one. A charter that declares
# nothing is not this gate's business and gets no row — the excerpt falls back
# to the W-<id> arm or to `none (<reason>)`, exactly as before, and whether the
# card's instruction is enough to get the field written is a question only live
# traffic answers (validation-debt). The reason for that line rather than a
# stricter one is on the record: the learning loop left an emit-time
# namability refusal DEFER because refusing there would block the very
# substitution that rescued a topic, and a "declare or be refused" rule is that
# refusal wearing a different hat. What is uncontested is that an anchor
# resolving nowhere is wrong, so that is all this gate says.
#
# No WARN severity: the gates surface's result vocabulary is PASS/FAIL and
# `derive_report.sh` tallies on it (`r=="FAIL"`, and a per-slice table that
# buckets PASS and FAIL and nothing else), so a third value would vanish from
# the report rather than appear in it — a closed vocabulary, §2 step 2.
gates_plan_binds() { # workspace charters.md plan.md ids...
  local ws=$1 art=$2 plan=$3; shift 3
  [ -f "$art" ] || { echo "refuse: artifact $art absent" >&2; return 2; }
  local id toks spans bad_n=0 checked=0 detail="" un
  for id in "$@"; do
    toks=$(plan_binds_tokens "$art" "$id")
    [ -n "$toks" ] || continue
    checked=$((checked + 1))
    # A label that yielded no anchor, or two labels in one section, are refused
    # by NAME. Folded into the generic message they read as "no anchor
    # resolved", which is what a typo'd §N says too, and the author would go
    # hunting the plan for a section that was never the problem.
    case "$toks" in
      '!EMPTY')
        echo "plan-binds: slice $id has a plan-binds: label with no \`- §\` anchor under it — the list ends at the first line that is neither blank nor an anchor"
        _gates_record "$ws" plan_binds FAIL "artifact=$art slice=$id form=empty"
        return 1 ;;
      '!DUPLICATE')
        echo "plan-binds: slice $id opens plan-binds: twice — one list per slice; a second label would silently union into the first"
        _gates_record "$ws" plan_binds FAIL "artifact=$art slice=$id form=duplicate"
        return 1 ;;
    esac
    # A charter declaring anchors against a plan that is not there is a fault,
    # not a pass: the floor prints what it saw rather than reading absence as
    # nothing to check.
    if [ ! -f "$plan" ]; then
      echo "plan-binds: slice $id declares a binding but $plan is absent — the anchors cannot be resolved against anything"
      _gates_record "$ws" plan_binds FAIL "artifact=$art plan=absent slices=$checked"
      return 1
    fi
    spans=$(printf '%s\n' "$toks" | plan_binds_spans "$plan")
    un=$(printf '%s\n' "$spans" | command grep '^UNRESOLVED ' | sed 's/^UNRESOLVED /§/' | tr '\n' ' ')
    if [ -n "${un% }" ]; then
      bad_n=$((bad_n + 1))
      detail="$detail slice $id: ${un% }"
    fi
  done
  [ "$checked" -gt 0 ] || return 0
  if [ "$bad_n" -gt 0 ]; then
    echo "plan-binds: $bad_n slice(s) declare an anchor that resolves to no heading in $plan —$detail. \`§N\` binds a numbered section; \`§N <heading text>\` binds one subsection of it, matched with whitespace and backticks ignored."
    _gates_record "$ws" plan_binds FAIL "artifact=$art slices=$checked bad=$bad_n"
    return 1
  fi
  _gates_record "$ws" plan_binds PASS "artifact=$art slices=$checked"
}

# Stamp freshness (conformance vs its spec): a conformance line-number stamp
# IDENTICAL to the spec's, on a file whose numbering the baseline→HEAD diff
# has shifted at that line, is a forwarded stamp — the record claims an @HEAD
# re-read that its own numbers contradict (measured: +8 net lines shifted
# every stamp below them, and the "re-read" carried the spec's numbers
# verbatim). Baseline = the sha pinned by the spec's own claims-gate
# attestation (the gates row written when the spec emitted). No attestation,
# a none sha, or an out-of-repo path → named SKIP, never a guess. Shift at
# line NN = sum of (new_len - old_len) over diff hunks ENTIRELY above NN; a
# hunk spanning NN edits the line in place, and a shifted-but-updated stamp
# passes — only identical-and-displaced fails.
gates_stamp_freshness() { # workspace conformance spec
  local ws=$1 conf=$2 spec=$3
  [ -f "$conf" ] || { echo "refuse: conformance $conf absent" >&2; return 2; }
  [ -f "$spec" ] || { echo "refuse: spec $spec absent — stamp freshness needs its baseline document" >&2; return 2; }
  local base repo failed=0 checked=0 tok path nn file rel delta
  base=$(state_get "$ws" gates 2>/dev/null | command grep -E '(^| )gate=claims( |$)' \
    | command grep -F "artifact=$spec" | tail -1 \
    | command grep -oE '(^| )sha=[^ ]+' | tr -d ' ' | cut -d= -f2)
  if [ -z "$base" ] || [ "$base" = "none" ]; then
    echo "stamp-freshness: no spec claims attestation with a sha pin — SKIP (named; the spec predates the gate or the slice is doc-bound)"
    _gates_record "$ws" stamp_freshness SKIP "no-baseline conf=$conf"
    return 0
  fi
  repo=$(_gates_repo "$ws" 2>/dev/null || true)
  if [ -z "$repo" ] || ! git -C "$repo" rev-parse -q --verify "$base^{commit}" > /dev/null 2>&1; then
    echo "stamp-freshness: baseline $base does not resolve in ${repo:-<no repo>} — SKIP (named)"
    _gates_record "$ws" stamp_freshness SKIP "baseline-unresolvable conf=$conf"
    return 0
  fi
  local esc
  while IFS= read -r tok; do
    nn=${tok##*:}; path=${tok%:*}
    # only SHARED stamps: the same path:NN, unfenced, in the spec too — as a
    # MAXIMAL token, never a substring (a fixed-string test read the spec's
    # mod.c:154 as sharing mod.c:15 and false-refused the conformance's own
    # fresh stamp; measured). Boundary: no path character before, no digit
    # after — a longer path or a longer line number is a different stamp.
    esc=$(printf '%s' "$tok" | sed 's/[.[\*^$()+?{}|\\/]/\\&/g')
    _gates_strip_fences "$spec" \
      | command grep -qE "(^|[^A-Za-z0-9_./~-])$esc([^0-9]|$)" || continue
    file=$(_gates_resolve_path "$ws" "$path" 2>/dev/null) || continue
    case "$file" in "$repo"/*) rel=${file#"$repo"/} ;; *) continue ;; esac
    checked=$((checked + 1))
    delta=$(git -C "$repo" diff -U0 "$base" HEAD -- "$rel" 2>/dev/null | awk -v nn="$nn" '
      /^@@/ {
        s=$0; sub(/^@@ -/,"",s); split(s, a, " ")
        split(a[1], o, ","); ol=o[1]+0; on=(o[2]=="" ? 1 : o[2]+0)
        split(a[2], w, ","); sub(/^\+/,"",w[1]); nl=(w[2]=="" ? 1 : w[2]+0)
        if (ol + (on > 0 ? on : 1) - 1 < nn) d += nl - on
      } END { print d+0 }')
    if [ "${delta:-0}" -ne 0 ]; then
      echo "stamp-freshness: $tok is the SPEC's stamp forwarded — the baseline→HEAD diff shifts that line by $delta (an @HEAD re-read would print $path:$((nn + delta))); re-read at HEAD and restamp"
      failed=1
    fi
  done < <(_gates_strip_fences "$conf" \
           | command grep -oE '(/|[A-Za-z0-9_.~-]+/)[A-Za-z0-9_./-]+:[0-9]+' \
           | sed 's/[.,;)]*$//' | sort -u)
  # Same gate, second shape of the same lie. A line-number stamp is one way to
  # claim currency; a COUNT in prose is the other — "412 lines at HEAD" — and
  # the measured instance forwarded exactly that from an earlier commit-unit's
  # measurement into an at-HEAD sentence, where the stamp axis above could not
  # see it. The gate deliberately does not parse what the number MEANS (a total
  # or a delta, a file or a range): that way lies a fragile prose reader and
  # false refusals on a live pipeline. It asks the one question that needs no
  # interpretation — if you assert a measurement is current, show what produced
  # it. An inline `$ …` or a named `E<n>` from the evidence block both answer.
  local pline pn=0
  while IFS= read -r pline; do
    printf '%s' "$pline" | command grep -qE '`\$ |`E[0-9]+`|\$\(' && continue
    pn=$((pn + 1))
    echo "stamp-freshness: a count asserted at HEAD carries no command on its line — \"$(printf '%s' "$pline" | cut -c1-100)\". a number that claims to be current is a measurement: give the command that produced it (inline \`\$ …\` or a named \`E<n>\` from the evidence block), or drop the currency claim."
    failed=1
  done < <(_gates_strip_fences "$conf" \
           | command grep -nE '[0-9]+ +(lines|hits|occurrences|matches|call sites)' \
           | command grep -E '(@|at) HEAD' || true)
  checked=$((checked + pn))
  if [ $failed -eq 1 ]; then
    _gates_record "$ws" stamp_freshness FAIL "conf=$conf baseline=$base checked=$checked"
    return 1
  fi
  _gates_record "$ws" stamp_freshness PASS "conf=$conf baseline=$base checked=$checked"
}

# Review-doc structure: every template heading present in the doc, in order —
# matched against the doc's own HEADING LINES only (a heading quoted inside
# prose is not a section; an unanchored substring search accepted a doc with
# zero real headings).

# -------------------------- document gates (structure, stamp freshness) -----

gates_structure() { # workspace doc template
  local ws=$1 doc=$2 tpl=$3
  [ -f "$doc" ] || { echo "refuse: doc $doc absent" >&2; return 2; }
  [ -f "$tpl" ] || { echo "refuse: template $tpl absent — structure check needs its authority" >&2; return 2; }
  local h pos=0 found failed=0 nh=0 doc_headings
  doc_headings=$(_gates_strip_fences "$doc" | command grep -nE '^#{1,6} ')
  while IFS= read -r h; do
    nh=$((nh + 1))
    found=$(printf '%s\n' "$doc_headings" | awk -F: -v p="$pos" -v h="$h" \
      '{ line=$0; sub(/^[0-9]+:/,"",line); if ($1+0 > p && line == h) { print $1; exit } }')
    if [ -z "$found" ]; then
      echo "structure: heading '$h' missing or out of order in $doc (template $tpl) — a structure mismatch is a draft"
      failed=1
    else
      pos=$found
    fi
  done < <(command grep -E '^#{1,6} ' "$tpl")
  if [ $nh -eq 0 ]; then
    echo "refuse: template $tpl declares no headings — vacuous structure check refused" >&2
    return 2
  fi
  if [ $failed -eq 1 ]; then
    _gates_record "$ws" structure FAIL "doc=$doc template=$tpl"
    return 1
  fi
  _gates_record "$ws" structure PASS "doc=$doc template=$tpl headings=$nh"
}

# Project-declared gate (build|lint|test|acceptance): run verbatim in the
# project repo, attest the result. The composite acceptance gate is the one
# intentional double-run (author impl close + inside postcheck).

# --------- project gates (the adapter's own build/lint/test/acceptance) -----

gates_project() { # workspace name
  local ws=$1 name=$2 cmd repo log rc
  case "$name" in build|lint|test|acceptance) : ;;
    *) echo "refuse: unknown project gate '$name' (build|lint|test|acceptance)" >&2; return 2 ;;
  esac
  # Owner ruling D-i (config-and-adapters.md §3): the doc repo has no
  # build/lint/test/acceptance concept. A doc-bound slice records a STRUCTURAL
  # named SKIP and the project's command — which belongs to the code repo and
  # would be measuring the wrong tree — is never run. This is the ONE place
  # that decides it, so the author's close and the reviewer's CLI run agree.
  if [ "$(_gates_kind "$ws")" = "doc" ]; then
    echo "project gate '$name': the active slice is doc-bound — the doc repo has no $name concept (structural SKIP by design; the mechanical floor is the spec's own per-slice checks)"
    _gates_record "$ws" "$name" SKIP "doc-bound by design"
    return 0
  fi
  cmd=$(project_get "$ws" "$name" 2>/dev/null || true)
  if [ -z "$cmd" ]; then
    echo "project gate '$name': not declared in project.kv — recorded as SKIP (named, never silent)"
    _gates_record "$ws" "$name" SKIP "not-declared"
    return 0
  fi
  repo=$(_gates_repo "$ws") || return 2
  mkdir -p "$ws/.runtime/logs"
  log="$ws/.runtime/logs/gate-$name-$(date +%s).log"
  # WHAT WAS INVOKED is recorded, because four conformance records across four
  # slices described a composite `<base>..HEAD` close while every attested
  # record was a no-arg run — and a reader checking that claim had nothing on
  # the surface but a log PATH. The workflow runs project.kv's string verbatim
  # and passes no arguments, so the invocation is the fact that settles it.
  #
  # It is recorded in TWO places, and the split is the point:
  #   - the gate LOG's first line carries the command VERBATIM. A log is free
  #     text by nature, it is the file this row already names, and it is what a
  #     reader opens anyway — it just never said what produced it.
  #   - the ROW carries a fingerprint. project.kv's string is not ours; the
  #     gates surface is whitespace-delimited key=value scanned field-by-field
  #     (derive_report.sh tallies by `gate=`/`result=`), and this tree has
  #     already paid for inlining foreign free text into such a record once:
  #     park() moved screen capture to a SIDECAR after a captured `resolved=1`
  #     overrode the real field in every last-match reader. A fingerprint is
  #     fixed-width, cannot forge a field, and answers the question a machine
  #     asks — "same declaration as the other rows, or did project.kv change
  #     mid-topic?" — while the human question is answered by the log.
  # Same idiom as `dirty=` above, and for the same reason.
  local cmd_fp
  cmd_fp=$(printf '%s' "$cmd" | md5sum | cut -c1-8)
  # A GATE MUST NOT CHANGE WHAT IT MEASURES. Every entry point of this workflow
  # exports LC_ALL=C for its own text processing — collation, sort order, byte
  # semantics in its own greps — and an export is ambient: it reaches every
  # child, including a foreign command this workflow only runs and does not own.
  # Measured, and it is not hypothetical: a delivered repo's hygiene gate matched
  # CJK with a PCRE \x{} escape above U+00FF, which is a COMPILE error outside a
  # UTF-8 locale. Under the inherited LC_ALL=C its grep exited 2, the axis's own
  # `|| true` absorbed it, and the gate reported 0 FINDINGS while its summary
  # still listed that axis as scanned — a green this workflow CAUSED. The same
  # tree under the developer's own locale reported the finding, which is why it
  # survived: by hand it always looked fine.
  # So the workflow drops its internal LC_ALL for the foreign command and lets
  # the operator's locale through, and the log's header says which one ran —
  # the invocation is already recorded here, and the environment is part of it.
  # What this does NOT do, stated because the boundary is real: nothing here can
  # see an instrument failure a project's own script swallows. That fix belongs
  # in the project (it landed there too); this one stops us supplying the cause.
  { printf '$ %s\n' "$cmd"
    printf -- '--- env: LC_ALL unset for the project command (the workflow does not impose its own collation), LANG=%s ---\n' "${LANG:-unset}"
    printf -- '--- output follows (the workflow passes no arguments) ---\n'
    ( cd "$repo" && env -u LC_ALL bash -c "$cmd" ) 2>&1
  } > "$log"; rc=$?          # the group's status IS the subshell's: it is last
  if [ $rc -ne 0 ]; then
    echo "project gate '$name' FAILED (rc=$rc) — log: $log"
    _gates_record "$ws" "$name" FAIL "rc=$rc log=$log cmd_fp=$cmd_fp"
    return 1
  fi
  _gates_record "$ws" "$name" PASS "log=$log cmd_fp=$cmd_fp"
}


# --------------------------------------------------------- the CLI face -----
# One verb per gate family; the families themselves are above and in the two
# sourced halves. A verb that is not here is not a gate.

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  set -uo pipefail
  export LC_ALL=C
  case "${1:-}" in
    caps) shift; gates_caps "$@" ;;
    commit) shift; gates_commit "$@" ;;
    claims) shift; gates_claims "$@" ;;
    claims-cite-scope) shift; gates_claims_cite_scope "$@" ;;
    env-sweep) shift; gates_env_sweep "$@" ;;
    line-pins) shift; gates_line_pins "$@" ;;
    charter-sections) shift; gates_charter_sections "$@" ;;
    plan-binds) shift; gates_plan_binds "$@" ;;
    structure) shift; gates_structure "$@" ;;
    stamp-freshness) shift; gates_stamp_freshness "$@" ;;
    project) shift; gates_project "$@" ;;
    *) echo "usage: gates.sh caps <ws> <file>..." >&2
       echo "       gates.sh commit <ws> <sha> [--relocation-only]" >&2
       echo "       gates.sh claims <ws> <artifact> [--optional] [--at-tip]   (--at-tip: records as spec_claims_tip, skips rows marked baseline)" >&2
       echo "       gates.sh claims-cite-scope <ws> <artifact>   (records gate=claims_cite_scope; never refuses an emit)" >&2
       echo "       gates.sh env-sweep <ws> <artifact>" >&2
       echo "       gates.sh line-pins <ws> <artifact>" >&2
       echo "       gates.sh charter-sections <ws> <charters.md> <id>..." >&2
       echo "       gates.sh plan-binds <ws> <charters.md> <plan.md> <id>..." >&2
       echo "       gates.sh structure <ws> <doc> <template>" >&2
       echo "       gates.sh stamp-freshness <ws> <conformance> <spec>" >&2
       echo "       gates.sh project <ws> <build|lint|test|acceptance>" >&2
       exit 2 ;;
  esac
fi
