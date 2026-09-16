#!/usr/bin/env bash
# lib/gates_claims.sh — the CLAIMS gate family, sourced by lib/gates.sh (never
# directly): the claims-table parser (`_gates_claims_rows`), the per-type row
# checks, and `gates_claims` itself. Split out of gates.sh under architecture
# §4.1's layout freedom to keep that file under cap.source_file — the same move
# that took gates_commit.sh out of it, and watch.sh out of ferry.sh. Every
# helper these call (_gates_record, _gates_repo, _gates_resolve_path,
# _gates_strip_fences, the binding primitives) lives in the sourcing file, and
# `_gates_strip_fences` in particular is shared with env_sweep, stamp_freshness,
# structure and lib/owed.sh — it is deliberately NOT part of this family.
#
# The contract this file owns, machine-read, and templates must emit it: a
# section opening with a line '## claims' holding a pipe table whose data rows
# are
#   | type | claim | anchor | echo | range | command |
# type ∈ cite|count|absence|behavior|process|note. cite rows carry durable
# anchors (path#heading or path::symbol — line pins forbidden) + a content echo
# the resolver verifies — and for a path#heading anchor, verified INSIDE that
# heading's extent, which `gates_claims_cite_scope` records at emit and never
# refuses. count/absence rows must carry a non-empty read-range
# stamp AND the evidence command. behavior rows ("this code/test already does
# X" — the class measured most often wrong with the least resistance) get the
# cite discipline AND the count discipline: a path::symbol anchor (a behavior
# lives in code, never under a heading) + verified echo + the rerun command.
# process rows carry a claim about an ACTION the writer took ("the sweep ran",
# "re-read in full", "the gates re-ran"): the extent, the command BY LABEL, and
# that label's OUTPUT on disk as an 'E<n>-out:' line. note rows are unchecked
# prose.

_gates_claims_rows() { # artifact -> data rows of the claims table
  # The section anchor accepts every shipped heading shape: '## claims',
  # '## 6. claims table' (spec template), '## 4. claims' (review template) —
  # a heading-level line whose text is claims, optionally numbered, optionally
  # suffixed 'table'. Any other heading closes the section.
  _gates_strip_fences "$1" \
    | awk '/^#+[[:space:]]+([0-9]+\.[[:space:]]+)?[Cc]laims([[:space:]]+table)?[[:space:]]*$/{on=1; next}
       /^#/{on=0}
       on && /^\|/' \
    | command grep -vE '^\|[ :-]*\|[ :|-]*$' \
    | tail -n +2
}

# A command cell may name its command instead of holding it. The reason is not
# style: a `|` inside a table cell splits that cell, in every renderer and in
# this gate's own `awk -F'|'` — measured, `` `$ grep -o a f \| wc -l` `` parses
# to NF=9 with the command truncated at the backslash, so the gate accepted a
# shell fragment as the evidence. Escaping only fixes the RENDERING: `\|` is a
# literal pipe to ERE and an escaped pipe to a shell, so a reader copying it
# runs something else, and §2 of review-standards itself prescribes
# `grep -o … | wc -l` for occurrence counts — the format forbade what the
# contract required. Markdown's own answer to a payload that does not belong
# inline is a reference plus a definition elsewhere; this is that shape.
_gates_claim_process_out() { # artifact row-n cmd -> rc 0 ok / 1 named failure
  # Boundary, stated because it decides what this buys: the gate checks the
  # command and its output are ON DISK and re-runnable. Whether the dispositions
  # account for every hit with NO REMAINDER is semantic and stays the reviewer's
  # — already owed, with no new rule: §7 P4 makes it run every claims-table
  # evidence command and compare the reading. That re-run is what settled this
  # when it was measured, and it is only possible against a printed output.
  local art=$1 n=$2 cmd=$3 bare label
  bare=$(printf '%s' "$cmd" | tr -d '`')
  label=$(printf '%s' "$bare" | command grep -oE '^E[0-9]+')
  if [ -z "$label" ]; then
    echo "claims row $n (process): the command must be an evidence LABEL (E<n>), never held inline — a sweep command carries pipes, and the row owes what it RETURNED as well as its text"
    return 1
  fi
  command grep -qE "^[[:space:]]*$label-out:[[:space:]]*[^[:space:]]" "$art" && return 0
  echo "claims row $n (process): '$label:' is present but '$label-out:' is not — print what the command returned, so a reader can re-run it and diff; a sweep that only asserts its range is the form measured to report itself complete while incomplete"
  return 1
}

_gates_claim_cmd() { # artifact row-n type cmd -> rc 0 ok / 1 named failure
  local art=$1 n=$2 type=$3 cmd=$4 label
  if [ -z "$cmd" ] || [ "$cmd" = "-" ]; then
    case "$type" in
      behavior) echo "claims row $n (behavior): missing rerun command — a behavior asserted without the command that proves it is taken from memory, not the tree" ;;
      *) echo "claims row $n ($type): missing evidence command — any number the tree can produce is taken from the tree" ;;
    esac
    return 1
  fi
  # A label is `E` + digits and NOTHING after them. The grammar used to be a
  # -oE PREFIX match, so `E10b` matched `E10`: with an `E10:` line present the
  # row passed while pointing at E10's command, which is not that row's
  # evidence. Measured on two slices — slice 13's spec (E10b bound to the
  # kTable-census command while its claim was the registry count) and slice
  # 14's fix round (E6b would have bound to an existing unrelated E6) — and
  # both times the author's own re-run of the table caught it, never the gate.
  # The failure mode is what makes truncation unacceptable: an ABSENT label
  # fails loudly, a present-but-wrong one passed silently. So the SHAPE is
  # refused, and the refusal names the command it would have bound to.
  local bare tok
  bare=$(printf '%s' "$cmd" | tr -d '`')
  case "$bare" in
    E[0-9]*)
      # The rule is about TOKENS, not about which characters a suffix happens
      # to use. The label is the cell's FIRST WORD, and that word must be the
      # label exactly; a reading after it ("E1 → 7") is the normal cell shape
      # and stays legal. Enumerating suffix characters is what the old prefix
      # match effectively did — it caught nothing, and a first attempt at this
      # fix that compared the leading alphanumeric run still let `E10-b`,
      # `E10_b` and `E10.b` bind to E10.
      tok=${bare%%[[:space:]]*}
      label=$(printf '%s' "$bare" | command grep -oE '^E[0-9]+')
      if [ "$tok" != "$label" ]; then
        echo "claims row $n ($type): '$tok' is not an evidence label — a label is E followed by digits and nothing else, and it must be the whole first word of the cell. It would bind silently to '$label''s command, which is not this row's evidence; renumber it (the next free E<n>) or inline the command"
        return 1
      fi ;;
    *) return 0 ;;                       # an inline command; the row holds it
  esac
  command grep -qE "^[[:space:]]*$label:[[:space:]]+[^[:space:]]" "$art" && return 0
  echo "claims row $n ($type): command reference '$label' resolves nowhere — the artifact owes a fenced evidence block carrying a line '$label: <command>'"
  return 1
}

# The gate is attached to the FORMAT, not to a list of artifacts. Two artifact
# classes exist and the difference is only what an ABSENT table means:
#   required (default) — spec, the three review files, the class_u halt doc:
#                        their contract owes a table, so no table is a FAIL.
#   --optional         — conformance, turnover, charters, closeout, the
#                        validation note: their contract does not require one,
#                        but authors write them anyway and every row in one is
#                        a claim. No table is a named SKIP; a table present is
#                        resolved exactly as anywhere else.
# Measured before this widened, over four archived topics: 336 claims rows lived
# in the --optional five with no resolver ever reading them — 160 of those in
# `turnover.md`, the artifact the NEXT slice's author reads, and SIX of its cite
# anchors were LINE PINS, the exact rot this gate refuses wherever it is
# routed. One turnover in the same corpus
# wrote the identical claim durably (`postcheck.1.md#5. verdict`), so the fix is
# not a new demand on authors — it is the rule they were already taught,
# enforced where it was silently unenforced.
# --at-tip re-resolves a spec's table at the LANDED tip (impl/fix emit) and
# records under its own gate name, spec_claims_tip, so the once-at-spec-emit
# attestation and the tip reading never overwrite each other on the surface. A
# row whose range cell carries the word `baseline` describes the tree BEFORE the
# slice's change — a fact the slice is meant to invalidate — and is skipped and
# counted. Everything else resolves exactly as at spec-emit.
gates_claims() { # workspace artifact [--optional] [--at-tip]
  local ws=$1 art=$2 optional=0 attip=0 gname=claims a
  for a in "${@:3}"; do
    case "$a" in --optional) optional=1 ;; --at-tip) attip=1; gname=spec_claims_tip ;; esac
  done
  [ -f "$art" ] || { echo "refuse: artifact $art absent" >&2; return 2; }
  local rows n=0 failed=0 skipped=0 line
  rows=$(_gates_claims_rows "$art")
  if [ -z "$rows" ]; then
    if [ "$optional" -eq 1 ]; then
      # Named, never silent — the store's own doctrine, and the shape
      # `gates_project` already uses for a structurally absent gate.
      echo "claims gate: $art carries no claims table — SKIP (named; this artifact's contract does not owe one, and a table present would be resolved)"
      _gates_record "$ws" "$gname" SKIP "artifact=$art no-table"
      return 0
    fi
    echo "claims gate: no '## claims' table with data rows in $art — the artifact owes one (emit-time mechanical gate, review-and-slices.md §4.1)"
    _gates_record "$ws" "$gname" FAIL "artifact=$art rows=0"
    return 1
  fi
  while IFS= read -r line; do
    n=$((n + 1))
    if [ "$attip" -eq 1 ] && printf '%s' "$line" | awk -F'|' '{print $6}' | command grep -qiw 'baseline'; then
      skipped=$((skipped + 1)); continue
    fi
    local type claim anchor echo_ range cmd nf
    # Six columns split to eight fields (the empty edges). More means a cell
    # carries a `|` — escaped or not, the split does not care — and every
    # field after it is the wrong one, so nothing below this can be trusted
    # for this row.
    nf=$(printf '%s' "$line" | awk -F'|' '{print NF}')
    if [ "$nf" -gt 8 ]; then
      echo "claims row $n: a '|' inside a cell splits the row (escaped or not — $nf fields, want 8), so this gate read a truncated command and a reader copying it gets a shell fragment; move the command into a fenced evidence block as 'E<n>: <command>' and put 'E<n>' in the cell"
      failed=1
      continue
    fi
    type=$(printf '%s' "$line" | awk -F'|' '{gsub(/^ +| +$/,"",$2); print $2}')
    claim=$(printf '%s' "$line" | awk -F'|' '{gsub(/^ +| +$/,"",$3); print $3}')
    anchor=$(printf '%s' "$line" | awk -F'|' '{gsub(/^ +| +$/,"",$4); print $4}')
    echo_=$(printf '%s' "$line" | awk -F'|' '{gsub(/^ +| +$/,"",$5); print $5}')
    range=$(printf '%s' "$line" | awk -F'|' '{gsub(/^ +| +$/,"",$6); print $6}')
    cmd=$(printf '%s' "$line" | awk -F'|' '{gsub(/^ +| +$/,"",$7); print $7}')
    case "$type" in
      note) : ;;
      cite)
        _gates_claim_cite "$ws" "$n" "$anchor" "$echo_" || failed=1 ;;
      count|absence)
        if [ -z "$range" ] || [ "$range" = "-" ]; then
          echo "claims row $n ($type): missing read-range stamp — state where you read TO, not where you noticed"
          failed=1
        fi
        _gates_claim_cmd "$art" "$n" "$type" "$cmd" || failed=1 ;;
      behavior)
        # "This code/test already does X" — twice a HIGH-confidence review
        # missed one because nothing obliged anyone to open the file: the
        # counted claims all verified, the behavior claim was the false one.
        # Anchor must be path::symbol (the code that does X, not a heading
        # about it), echo verified like a cite, and the rerun command present
        # — which puts the row under the reviewer's run-every-command duty.
        case "$anchor" in
          *::*) _gates_claim_cite "$ws" "$n" "$anchor" "$echo_" || failed=1 ;;
          *)
            echo "claims row $n (behavior): anchor '$anchor' must be path::symbol — a behavior claim binds the code that implements it, never a heading or nothing"
            failed=1 ;;
        esac
        _gates_claim_cmd "$art" "$n" behavior "$cmd" || failed=1 ;;
      process)
        # A claim about an ACTION the writer took, which is the one claim class
        # no reader checks by READING it. Measured across one slice pair: three
        # drafting forms of one rule, three outcomes. Forward-only prohibition
        # — the whole pre-existing backlog survived. Sweep as an INSTRUCTION
        # — found two instances the review had not named, left one, and
        # reported itself complete. Sweep as PRINTED EVIDENCE — the reviewer
        # re-ran the command over the extent the entry named, got its 29 hits
        # back in the same order with the same line numbers and matched text,
        # dispositions accounting for all 29 with no remainder, and issued
        # ready. Only the third gives a reader something to check, so the row
        # demands the third: extent, command, and what the command RETURNED.
        if [ -z "$range" ] || [ "$range" = "-" ]; then
          echo "claims row $n (process): missing extent — a process claim states what it COVERED (the range read, the tree swept), never merely that it happened"
          failed=1
        fi
        _gates_claim_cmd "$art" "$n" process "$cmd" || failed=1
        _gates_claim_process_out "$art" "$n" "$cmd" || failed=1 ;;
      *)
        echo "claims row $n: unknown type '$type' (closed set: cite|count|absence|behavior|process|note)"
        failed=1 ;;
    esac
  done <<< "$rows"
  local detail="artifact=$art rows=$n"
  [ "$attip" -eq 1 ] && detail="$detail skipped=$skipped"
  if [ $failed -eq 1 ]; then
    _gates_record "$ws" "$gname" FAIL "$detail"
    return 1
  fi
  _gates_record "$ws" "$gname" PASS "$detail"
}

_gates_claim_cite() { # workspace rownum anchor echo
  local ws=$1 n=$2 anchor=$3 echo_=$4 path frag file kind
  if printf '%s' "$anchor" | command grep -qE ':[0-9]+$'; then
    echo "claims row $n (cite): line-pin anchor '$anchor' forbidden — durable anchors are path#heading or path::symbol (a line pin dies on the next unrelated edit)"
    return 1
  fi
  case "$anchor" in
    *::*) path=${anchor%%::*}; frag=${anchor#*::}; kind=symbol ;;
    *"#"*) path=${anchor%%#*}; frag=${anchor#*#}; kind=heading ;;
    *) echo "claims row $n (cite): anchor '$anchor' is neither path#heading nor path::symbol"; return 1 ;;
  esac
  file=$(_gates_resolve_path "$ws" "$path") || {
    echo "claims row $n (cite): anchor path '$path' resolves nowhere (tried absolute, repo, workspace)"
    return 1
  }
  if [ "$kind" = "heading" ]; then
    if ! command grep -qiE "^#{1,6}[[:space:]].*$(printf '%s' "$frag" | sed 's/[.[\*^$()+?{}|\\/]/\\&/g')" "$file"; then
      echo "claims row $n (cite): heading '$frag' not found in $file (moved target = loud failure, not silent rot)"
      return 1
    fi
  else
    local esc
    esc=$(printf '%s' "$frag" | sed 's/[.[\*^$()+?{}|\\/]/\\&/g')
    if ! command grep -qE "(^|[^A-Za-z0-9_])$esc([^A-Za-z0-9_]|$)" "$file"; then
      echo "claims row $n (cite): symbol '$frag' not found in $file"
      return 1
    fi
  fi
  if [ -n "$echo_" ] && [ "$echo_" != "-" ]; then
    if ! command grep -qF -- "$echo_" "$file"; then
      echo "claims row $n (cite): content echo '$echo_' not found in $file — the cited text moved or never said that"
      return 1
    fi
  else
    echo "claims row $n (cite): missing content echo — the resolver verifies an echo, not just existence"
    return 1
  fi
  return 0
}

# The cite row's SCOPE half — RECORDED, never a refusal.
#
# `_gates_claim_cite` above proves two things independently: a heading matching
# the anchor's fragment exists somewhere in the file, and the echo exists
# somewhere in the file. Their conjunction READS as "this text is under this
# heading" without being it, so a row can point its reader one section away from
# its own evidence and pass. The archive says the shape recurs rather than being one author's slip.
#
# WHY THIS RECORDS INSTEAD OF REFUSING, since a gate that cannot say no looks
# like half a gate. Every one of the rows the sweep found is READING-CORRECT:
# the sentence is in the file and says what the row claims, and only the pointer
# is off. Refusing an emit over a pointer is the refusal the learning loop
# already declined on its own class —
# "refusing there would block the very substitution that rescued this topic".
# The channel that stays open is the one `spec_claims_tip` already uses at
# `session/emit_checks.sh`: a gate of its own NAME, the same closed PASS/FAIL
# vocabulary `derive_report.sh` buckets, recorded at emit and read by the
# reviewer — with that call site's own note on how it is promoted, "refusal
# comes only if the FAIL rows prove real over live topics". So this gate leaves
# the record a reviewer reads at §7 P4 and §9 C3, and a rate the owner can weigh
# before anyone is blocked.
#
# THE DETAIL LINE CARRIES `judged=`, which is this gate's floor. A row is judged
# only when its path resolves, its fragment names a heading, and its echo is in
# the file — every other row is the cite gate's business, not this one's. A PASS
# over zero judged rows is a vacuous PASS, and naming the count is what makes it
# visible in the report instead of indistinguishable from a real one.
gates_claims_cite_scope() { # ws artifact -> rc 0 PASS / 1 FAIL / 2 refused
  local ws=$1 art=$2 rows line n=0 judged=0 out=0 offenders=""
  [ -f "$art" ] || { echo "refuse: artifact $art absent" >&2; return 2; }
  rows=$(_gates_claims_rows "$art")
  if [ -z "$rows" ]; then
    _gates_record "$ws" claims_cite_scope SKIP "artifact=$art no-table"
    return 0
  fi
  while IFS= read -r line; do
    n=$((n + 1))
    local type anchor echo_ nf path frag file spans elines
    nf=$(printf '%s' "$line" | awk -F'|' '{print NF}')
    # A split row is already named by the claims gate; re-naming it here would
    # be a second red for one defect.
    if [ "$nf" -gt 8 ]; then continue; fi
    type=$(printf '%s' "$line" | awk -F'|' '{gsub(/^ +| +$/,"",$2); print $2}')
    if [ "$type" != "cite" ]; then continue; fi
    anchor=$(printf '%s' "$line" | awk -F'|' '{gsub(/^ +| +$/,"",$4); print $4}')
    echo_=$(printf '%s' "$line" | awk -F'|' '{gsub(/^ +| +$/,"",$5); print $5}')
    # Symbol anchors are out of scope on purpose: a heading's extent is decided
    # by the document's own syntax, a symbol's would need a parser per language.
    case "$anchor" in
      *::*) continue ;;
      *"#"*) path=${anchor%%#*}; frag=${anchor#*#} ;;
      *) continue ;;
    esac
    if [ -z "$echo_" ] || [ "$echo_" = "-" ]; then continue; fi
    file=$(_gates_resolve_path "$ws" "$path") || continue
    spans=$(md_heading_span "$file" "$frag") || continue
    if [ -z "$spans" ]; then continue; fi
    elines=$(md_literal_lines "$file" "$echo_") || continue
    if [ -z "$elines" ]; then continue; fi
    judged=$((judged + 1))
    if md_span_covers "$spans" "$elines"; then continue; fi
    out=$((out + 1))
    offenders="$offenders
claims row $n (cite): echo '$echo_' is in $file but OUTSIDE '$frag' — that heading's extent is $(printf '%s' "$spans" | tr '\n' ';') and the echo is at line(s) $(printf '%s' "$elines" | tr '\n' ',') ; anchor the heading whose section holds the text"
  done <<< "$rows"
  local detail="artifact=$art rows=$n judged=$judged out=$out"
  if [ "$out" -gt 0 ]; then
    printf '%s\n' "${offenders#
}"
    _gates_record "$ws" claims_cite_scope FAIL "$detail"
    return 1
  fi
  _gates_record "$ws" claims_cite_scope PASS "$detail"
  return 0
}
