#!/usr/bin/env bash
# 31-plan-binds — the DECLARED plan binding: `lib/plan_binds.sh`'s parser and
# resolver, and the excerpt `_compose_plan_slice` cuts from them. Its own file
# rather than more of 30-closure, which sits at `cap.selftest_file`.
#
# The mechanism replaces reverse-engineering a `**plan binding**` prose
# paragraph — a convention no template, card, gate or script ever defined, which
# is why it grew three unreadable dialects across seven charters.
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/fixtures/lib.sh"
. "$RS/lib/config.sh"
. "$RS/lib/owed.sh"
. "$RS/lib/compose.sh"

pws=$(sc_tmpdir)/ptopic/delivery
mkdir -p "$pws/.runtime/prompts" "$pws/slices"

echo "-- plan_slice arm 1: the charter DECLARES its binding and the excerpt cuts on it --"
# The W-<id> arm above keys on a planning-side convention 3 of the 10 plans on
# disk use; on the rest the composer gave up whole and every spec/precheck
# prompt fell back to reading the plan entire. A charter may instead DECLARE
# what its slice binds (lib/plan_binds.sh), and a declaration beats a
# convention: it is read as written, whatever shape the plan carries.
cat > "$pws/../plan.md" <<'EOF'
# fixture plan v5

HEAD-LINE: the title block, always kept.

## 1. background

BG-LINE: not bound by this slice.

## 2. decisions

DECISION-LINE: bound whole.

## 3. change spec

SPEC-PREAMBLE: the section's own words above its children.

### slice A: the first cut

CUT-A-BODY.

### slice B: the second cut

CUT-B-BODY.

## 4. `selfcheck` spec

SELFCHECK-PREAMBLE.

### new `src/foo_selfcheck.cc` (commit 1)

FOO-BODY.

### CMake

CMAKE-BODY.

## 5. history — v5 vs v4

HISTORY-LINE.
EOF
# The heading text is quoted with its whitespace and backticks free to differ:
# the charter wraps a quoted heading in backticks, which strips the inner ones.
# Measured on the one charter that quotes headings: 5 of 12 match byte-for-byte
# and 12 of 12 match once whitespace and backticks are ignored.
cat > "$pws/charters.md" <<'EOF'
# charters

## slice 02

plan-binds:
- §2
- §3 slice A: the first cut
- §4 new src/foo_selfcheck.cc (commit 1)

**intent** — prose, which ends the list.

## slice 03

plan-binds:
- §4
- §4 CMake

## slice 04

plan-binds:
- §77
- §88 no such thing

## slice 05

plan-binds:
- §2
- §99 declared but absent
EOF
xpath=$( . "$RS/lib/state.sh"; . "$RS/lib/compose.sh"; _compose_resolve "$pws" 02 1 plan_slice )
case "$xpath" in
  MISSING:*|NONE) bad "declared plan-binds did not resolve for slice 02: $xpath" ;;
  *)
    for want in HEAD-LINE DECISION-LINE CUT-A-BODY FOO-BODY; do
      command grep -q "$want" "$xpath" && ok "declared excerpt keeps $want" || bad "declared excerpt lost $want"
    done
    for drop in BG-LINE CUT-B-BODY CMAKE-BODY HISTORY-LINE; do
      command grep -q "$drop" "$xpath" && bad "declared excerpt still carries $drop" || ok "declared excerpt drops $drop"
    done
    # a subsection anchor rides with its parent heading AND that section's own
    # preamble — without them the excerpt carries a `###` under no `##` and the
    # reader cannot see which section the subsection belongs to
    command grep -q '^## 3\. change spec$' "$xpath" \
      && command grep -q 'SPEC-PREAMBLE' "$xpath" \
      && ok "a subsection anchor carries its parent section's heading and preamble" \
      || bad "subsection anchor orphaned: parent heading or preamble missing"
    command grep -q '^### slice A: the first cut$' "$xpath" \
      && ok "declared headings ride verbatim (an anchor derived from the excerpt resolves in the plan)" \
      || bad "a declared heading was altered in the excerpt"
    case "$xpath" in */.runtime/prompts/plan.02.md) ok "the declared excerpt is a slice-named derived file under .runtime/prompts" ;;
      *) bad "declared excerpt path '$xpath' is not .runtime/prompts/plan.<slice>.md" ;; esac ;;
esac
# a charter naming a section AND one of its own subsections emits it ONCE
xpath=$( . "$RS/lib/state.sh"; . "$RS/lib/compose.sh"; _compose_resolve "$pws" 03 1 plan_slice )
case "$xpath" in
  MISSING:*|NONE) bad "overlapping anchors did not resolve: $xpath" ;;
  *) [ "$(command grep -c '^### CMake$' "$xpath")" = 1 ] \
       && ok "a section and its own subsection, both declared, emit that subsection once" \
       || bad "overlapping anchors duplicated: $(command grep -c '^### CMake$' "$xpath") CMake headings" ;;
esac
# THE FLOOR, and it points at the safe side: a declaration none of whose anchors
# resolve yields the WHOLE plan back, never a head-only stub (an unfloored arm reads vacuous)
xpath=$( . "$RS/lib/state.sh"; . "$RS/lib/compose.sh"; _compose_resolve "$pws" 04 1 plan_slice )
case "$xpath" in
  MISSING:*"§77"*"§88"*) ok "a declaration no anchor of which resolves is MISSING, naming every anchor (the author gets the full plan, not a stub)" ;;
  *) bad "an all-unresolvable declaration should be MISSING naming its anchors; got: $xpath" ;;
esac
# one bad anchor beside a good one is NAMED in the excerpt, never dropped quietly
xpath=$( . "$RS/lib/state.sh"; . "$RS/lib/compose.sh"; _compose_resolve "$pws" 05 1 plan_slice )
case "$xpath" in
  MISSING:*|NONE) bad "a partly-resolving declaration should still produce an excerpt; got: $xpath" ;;
  *) command grep -q 'DECLARED BUT NOT FOUND IN THE PLAN' "$xpath" \
       && command grep -q '99' "$xpath" \
       && ok "an anchor the plan lacks is NAMED in the excerpt header (never silently missing)" \
       || bad "the excerpt says nothing about the unresolvable anchor: $(head -1 "$xpath")"
     # The suite exports LC_ALL=C and a ferry inherits whatever the operator
     # has; bash printf renders a \uHHHH escape only in a UTF-8 locale and emits
     # the seven literal characters otherwise. Measured while writing this arm:
     # the header carried a literal escape under the suite's own locale and an
     # em-dash under an interactive one, so the first reading was clean and
     # wrong. Non-ASCII in a format string is written as the character.
     command grep -q '\\u[0-9a-fA-F]' "$xpath" \
       && bad "the excerpt header carries an unrendered \\uHHHH escape (locale-dependent printf)" \
       || ok "the excerpt header carries no unrendered \\uHHHH escape (it renders in every locale, not only UTF-8)" ;;
esac
# the declared arm WINS over the W-<id> arm, and the absence of a field falls through to it
cat > "$pws/../plan.md" <<'EOF'
# fixture plan v6

## 1. context

CTX-LINE.

# W-1: an item

W1-BODY.
EOF
printf '# charters\n\n## slice 02\n\nbinds W-1.\n\nplan-binds:\n- §1\n' > "$pws/charters.md"
xpath=$( . "$RS/lib/state.sh"; . "$RS/lib/compose.sh"; _compose_resolve "$pws" 02 1 plan_slice )
case "$xpath" in
  MISSING:*|NONE) bad "declared-beats-W did not resolve: $xpath" ;;
  *) command grep -q 'CTX-LINE' "$xpath" && ! command grep -q 'W1-BODY' "$xpath" \
       && ok "a charter that declares a binding is read as written, even where the W-<id> arm would also have fired" \
       || bad "the W-<id> arm won over an explicit declaration" ;;
esac
printf '# charters\n\n## slice 02\n\nbinds W-1.\n' > "$pws/charters.md"
xpath=$( . "$RS/lib/state.sh"; . "$RS/lib/compose.sh"; _compose_resolve "$pws" 02 1 plan_slice )
case "$xpath" in
  MISSING:*|NONE) bad "no declaration should fall through to the W-<id> arm; got: $xpath" ;;
  *) command grep -q 'W1-BODY' "$xpath" \
       && ok "a charter declaring nothing still reaches the W-<id> arm (the field is additive)" \
       || bad "the W-<id> arm stopped working when no plan-binds field is present" ;;
esac

# The field name lives in four places — parser, gate, split prompt, author card
# — this tree's most-measured drift shape. Read off the PARSER'S OWN opening
# pattern, not off the file at large: measured while writing this, the file-wide
# read survived renaming that pattern and agreed with itself over a dead one.
pbtok=$(command grep -E '^[[:space:]]*/\^' "$WF_ROOT/runtime-scripts/lib/plan_binds.sh" \
  | sed 's/\[\[:[a-z]*:\]\]//g' | command grep -oE '[a-z][a-z-]*:' | head -1)
[ -n "$pbtok" ] || bad "lib/plan_binds.sh field-opening pattern no longer carries a token"
for f in runtime-docs/templates/prompts/split.warm.md runtime-docs/cards/author.md; do
  command grep -q "$pbtok" "$WF_ROOT/$f" \
    && ok "$f names the field the parser opens on ($pbtok)" \
    || bad "$f does not name '$pbtok' — the prompt teaches a token nothing parses"
done


echo "-- a section's extent is decided by its NUMBER, not only its heading level --"
# Measured on a real plan, which writes `### 3.2` and its
# children `### 3.2.1/3.2.2/3.2.3` all at H3. A level-only rule ended §3.2 at
# its first child — 22 lines of the 100 a reader means — and RESOLVED, so the
# gate passed. Found by an independent reader; these arms are what it costs to
# never find it again.
cat > "$pws/../plan.md" <<'EOF'
# fixture plan v7

TITLE-BLOCK.

## 3. design

DESIGN-PREAMBLE.

### 3.2 the carrier

CARRIER-BODY.

### 3.2.1 the shape

SHAPE-BODY.

### 3.2.2 the counter-examples

COUNTER-BODY.

### 3.3 install points

INSTALL-BODY.

## 4. decisions

DECIDE-BODY.
EOF
printf '# charters\n\n## slice 01\n\nplan-binds:\n- §3.2\n\n## slice 02\n\nplan-binds:\n- §3.2.1\n\n## slice 03\n\nplan-binds:\n- §3\n' > "$pws/charters.md"
xp=$( . "$RS/lib/state.sh"; . "$RS/lib/compose.sh"; _compose_resolve "$pws" 01 1 plan_slice )
case "$xp" in MISSING:*|NONE) bad "§3.2 did not resolve: $xp" ;; *)
  command grep -q SHAPE-BODY "$xp" && command grep -q COUNTER-BODY "$xp" \
    && ok "a numbered anchor keeps its number-descendants, whatever heading level they are written at" \
    || bad "§3.2 lost its 3.2.x children (the level-only extent bug)"
  command grep -q INSTALL-BODY "$xp" && bad "§3.2 leaked its sibling §3.3" \
    || ok "a numbered anchor stops at its first non-descendant sibling" ;;
esac
# THE SPAN'S END LINE, pinned. Every content assertion above greps for BODY
# tokens, so a span that over-collects by exactly ONE line is invisible to them
# — an independent reader mutated `endof()` to `hline[j]` and the whole suite
# stayed green while the excerpt leaked the next section's heading.
xp=$( . "$RS/lib/state.sh"; . "$RS/lib/compose.sh"; _compose_resolve "$pws" 03 1 plan_slice )
case "$xp" in MISSING:*|NONE) bad "§3 did not resolve: $xp" ;; *)
  command grep -q '^## 4\. decisions$' "$xp" \
    && bad "the span leaked the FOLLOWING section's heading line — endof() is off by one" \
    || ok "a span ends before the next section's heading line (an off-by-one leaks it, and nothing else here would show that)"
  command grep -q 'INSTALL-BODY' "$xp" \
    && ok "and it keeps its own last line (the same off-by-one in the other direction truncates)" \
    || bad "the span dropped its own last block" ;;
esac
# the ancestor chain: a dotted anchor is orphaned without it
xp=$( . "$RS/lib/state.sh"; . "$RS/lib/compose.sh"; _compose_resolve "$pws" 02 1 plan_slice )
case "$xp" in MISSING:*|NONE) bad "§3.2.1 did not resolve: $xp" ;; *)
  command grep -q '^## 3\. design$' "$xp" && command grep -q '^### 3\.2 the carrier$' "$xp" \
    && ok "a dotted anchor carries EVERY enclosing numbered ancestor's heading (never a ### under no ##)" \
    || bad "§3.2.1 was emitted without its ancestor chain"
  command grep -q 'COUNTER-BODY' "$xp" \
    && bad "§3.2.1 leaked its sibling §3.2.2" || ok "a dotted anchor does not leak its siblings" ;;
esac

echo "-- md_heading_span: the extent rule as the CLAIMS gate calls it (fragment, not number) --"
# The same scan and the same endof(), reached by a different door. plan_binds
# asks it for `§3.2`; the claims gate asks it for the text of a `path#heading`
# anchor and then checks the row's echo lands inside what comes back. These arms
# pin the fragment-facing half, so a change made for one door cannot quietly
# move the other.
mdf="$pws/../mdspan.md"
cat > "$mdf" <<'EOF'
# doc

## alpha

ALPHA-BODY

```
# not a heading
```

STILL-ALPHA

## beta

BETA-BODY

####### seven

SEVEN-BODY
EOF
mds() { ( . "$RS/lib/md_span.sh"; md_heading_span "$mdf" "$1" ); }
got=$(mds alpha)
[ "$got" = "3 12" ] \
  && ok "a heading's extent runs to the line before the next heading at or above its level (alpha = 3..12)" \
  || bad "md_heading_span alpha = '$got', want '3 12'"
gotb=$(mds beta)
[ "$gotb" = "13 19" ] \
  && ok "the last section runs to EOF, never to the last heading (beta = 13..19)" \
  || bad "md_heading_span beta = '$gotb', want '13 19'"
# The 18-row correction the archive sweep paid for: read raw, the fenced
# `# not a heading` ends alpha at line 7 and every echo below it reads OUTSIDE.
case "$got" in "3 12") ok "a fenced '# ' line does not truncate the section above it (the 32-vs-14 correction)" ;;
  *) bad "the fenced comment truncated alpha: '$got'" ;; esac
[ -z "$(mds 'no such heading')" ] \
  && ok "a fragment naming no heading returns NOTHING — the caller's 'moved target' case stays distinct from 'echo elsewhere'" \
  || bad "md_heading_span invented a span for an absent fragment: '$(mds 'no such heading')'"
[ -z "$(mds seven)" ] \
  && ok "a seventh '#' is not a heading — the gate's own at-most-six-hashes rule, preserved" \
  || bad "md_heading_span took a 7-hash line as a heading: '$(mds seven)'"
# Case-folded literal substring, exactly the gate's match: two headings can
# answer one fragment, and BOTH spans come back — today's pass-on-any behaviour,
# so an ambiguous anchor cannot become a new refusal.
gota=$(mds A)
[ "$(printf '%s\n' "$gota" | command grep -c .)" = "2" ] \
  && ok "a fragment matching two headings returns both spans (ambiguity stays permissive, never a new red)" \
  || bad "ambiguous fragment returned: '$gota'"
mdc() { ( . "$RS/lib/md_span.sh"; md_span_covers "$1" "$2" ); }
if mdc "3 12" "5"; then ok "md_span_covers: a line inside the span is covered"; else bad "md_span_covers missed an inside line"; fi
if mdc "3 12" "20"; then bad "md_span_covers claimed an outside line"; else ok "md_span_covers: a line outside every span is not covered"; fi
if mdc "3 12" ""; then bad "md_span_covers covered an EMPTY line set (vacuous pass)"; else ok "md_span_covers on no lines is not a pass (the vacuous direction)"; fi

echo "-- a label that yields no anchor must not look like no label at all --"
# Both forms below once parsed to nothing, and nothing is exactly what a section
# with NO field parses to — so both doors fell through in silence to the
# behaviour this mechanism exists to end. The bolded label is the likeliest
# author transcription: the PROSE convention it replaces was `**plan binding**`.
for form in '**plan-binds:**\n- §3\n' 'plan-binds:\n* §3\n' 'plan-binds:\n\n- §3\n'; do
  printf "# charters\n\n## slice 01\n\n$form" > "$pws/charters.md"
  xp=$( . "$RS/lib/state.sh"; . "$RS/lib/compose.sh"; _compose_resolve "$pws" 01 1 plan_slice )
  case "$xp" in MISSING:*|NONE) bad "a near-miss but unambiguous field form was not read: $form -> $xp" ;;
    *) command grep -q DESIGN-PREAMBLE "$xp" && ok "field form read: $(printf "$form" | head -1)" \
         || bad "field form read but bound nothing: $form" ;; esac
done
printf '# charters\n\n## slice 01\n\nplan-binds:\n\n**intent** — prose\n' > "$pws/charters.md"
xp=$( . "$RS/lib/state.sh"; . "$RS/lib/compose.sh"; _compose_resolve "$pws" 01 1 plan_slice )
case "$xp" in MISSING:*"no \`- §\` anchor"*) ok "a label with no anchor under it is MISSING by NAME (never silence, which reads as no field)" ;;
  *) bad "an empty declaration should name itself; got: $xp" ;; esac
printf '# charters\n\n## slice 01\n\nplan-binds:\n- §3\n\nprose\n\nplan-binds:\n- §4\n' > "$pws/charters.md"
xp=$( . "$RS/lib/state.sh"; . "$RS/lib/compose.sh"; _compose_resolve "$pws" 01 1 plan_slice )
case "$xp" in MISSING:*"twice"*) ok "a second label in one section is refused by name (it would silently union into the first)" ;;
  *) bad "a duplicated declaration should name itself; got: $xp" ;; esac
# quoted material is not a declaration
printf '# charters\n\n## slice 01\n\nplan-binds:\n- §3\n\nlike so:\n\n```\nplan-binds:\n- §77\n```\n\n    - §88\n' > "$pws/charters.md"
xp=$( . "$RS/lib/state.sh"; . "$RS/lib/compose.sh"; _compose_resolve "$pws" 01 1 plan_slice )
case "$xp" in MISSING:*|NONE) bad "a section quoting an example should still resolve its real anchor: $xp" ;;
  *) command grep -q 'DECLARED BUT NOT FOUND' "$xp" \
       && bad "anchors quoted in a fenced or indented block were collected as declared" \
       || ok "anchors shown as an EXAMPLE (fenced, or indented as code) are not collected as declared" ;; esac

echo "-- the head is everything above the first NUMBERED heading, fences respected --"
cat > "$pws/../plan.md" <<'EOF'
# fixture plan v8

HEAD-ONLY.

# 2. change spec

SPEC-BODY.

## 2.1 detail

```sh
# scope: a comment, not a heading
```

TAIL-INSIDE-2-1.

# 3. history

HIST-BODY.
EOF
printf '# charters\n\n## slice 01\n\nplan-binds:\n- §2\n' > "$pws/charters.md"
xp=$( . "$RS/lib/state.sh"; . "$RS/lib/compose.sh"; _compose_resolve "$pws" 01 1 plan_slice )
case "$xp" in MISSING:*|NONE) bad "H1-sectioned plan did not resolve: $xp" ;; *)
  [ "$(command grep -c '^SPEC-BODY\.$' "$xp")" = 1 ] \
    && ok "an H1-sectioned plan emits each bound line ONCE (a '^## ' head rule swallows the whole plan, then repeats the spans)" \
    || bad "bound content emitted $(command grep -c '^SPEC-BODY\.$' "$xp") times — head and spans overlap"
  command grep -q 'HIST-BODY' "$xp" && bad "the head rule swallowed an unbound section" || ok "the head stops at the first numbered heading"
  command grep -q 'TAIL-INSIDE-2-1' "$xp" \
    && [ "$(command grep -c '^```' "$xp")" = 2 ] \
    && ok "a fenced '# ' line is not a heading: the section keeps its tail and the fence closes" \
    || bad "a fenced comment truncated the section (fences in excerpt: $(command grep -c '^```' "$xp"))" ;;
esac


echo "-- the declared excerpt reaches a REAL rendered prompt, not just the resolver --"
# Everything above calls `_compose_resolve` directly. The W-<id> arm has an
# end-to-end render in 30-closure and the declared arm had none, so the manifest
# and fingerprint path was unexercised for it: an excerpt the resolver produces
# and the renderer never places is an excerpt no author sees. Named by the
# independent reader as a gap it did not close.
base=$(sc_tmpdir)
read -r repo branch < <(mk_repo "$base/repo")
outd=$(sc_tmpdir)
cat > "$pws/../plan.md" <<'EOF'
# fixture plan v9

TITLE-ONLY.

## 1. background

BG-BODY.

## 2. change spec

DECLARED-SPEC-BODY.
EOF
printf '# charters\n\n## slice 02\n\nplan-binds:\n- §2\n' > "$pws/charters.md"
printf 'repo=%s\nbranch=%s\n' "$repo" "$branch" > "$pws/project.kv"
( . "$RS/lib/state.sh"; printf 'id=02 status=active risk=low title=two rederive=0\n' | state_set "$pws" slices ferry ) > /dev/null
compose_prompt "$pws" spec 02 1 1 nPB cold "$outd/dspec.md" > /dev/null 2>&1 \
  && ok "a spec prompt renders with a DECLARED excerpt (rc 0)" \
  || bad "spec render with a declared excerpt failed"
command grep -q 'plan.02.md' "$outd/dspec.md.inputs" \
  && ok "the declared excerpt is a manifest-resolved input (so the fingerprint hashes it and a changed binding is novelty)" \
  || bad "declared excerpt missing from the inputs sidecar: $(cat "$outd/dspec.md.inputs" 2>/dev/null)"
# The manifest places the excerpt as a PATH the author opens, not as inlined
# text — so assert the path is named and the FILE behind it is the cut. Written
# first as a grep for the section body in the prompt, which failed honestly; its
# sibling ("an unbound section stays out") PASSED at the same time and would
# have passed on any prompt at all, since the body carries neither. A vacuous
# assertion beside a failing one is how a whole arm reads green.
dspath=$(command grep -oE '[^ ]*/\.runtime/prompts/plan\.02\.md' "$outd/dspec.md" | head -1)
[ -n "$dspath" ] \
  && ok "the rendered prompt NAMES the declared excerpt's path (the manifest item the author opens)" \
  || bad "no excerpt path in the rendered prompt: $(command grep -n 'plan excerpt' "$outd/dspec.md" | head -1)"
if [ -n "$dspath" ] && [ -f "$dspath" ]; then
  command grep -q 'DECLARED-SPEC-BODY' "$dspath" \
    && ok "and the file at that path carries the bound section" \
    || bad "the excerpt the prompt points at lost the bound section"
  command grep -q 'BG-BODY' "$dspath" \
    && bad "the excerpt the prompt points at carries an UNBOUND section" \
    || ok "and not the unbound one — the cut is what the author actually opens"
else
  bad "the path the prompt names does not exist on disk: '$dspath'"
fi
# and the MISSING direction reaches the prompt as a stated reason, not a blank
printf '# charters\n\n## slice 02\n\n**plan-binds:**\n\nintent — prose\n' > "$pws/charters.md"
compose_prompt "$pws" spec 02 1 1 nPB cold "$outd/dspec2.md" > /dev/null 2>&1 \
  && command grep -qE 'none \(.*plan-binds' "$outd/dspec2.md" \
  && ok "a malformed declaration renders as none (<reason>) naming the form, so the author is told why they got the whole plan" \
  || bad "the rendered prompt does not state the reason: $(command grep -n 'plan excerpt' "$outd/dspec2.md" | head -2)"


echo "-- the excerpt path is awk-PORTABLE: gawk and mawk must agree, byte for byte --"
# mawk 1.3.4 does not support ERE intervals AT ALL — `/^#{1,6} /` simply never
# matches — and on Debian/Ubuntu mawk is the DEFAULT awk. Both excerpt arms used
# intervals, so on such a box they did not fail: they returned a WRONG CUT,
# silently. Measured before the fix: the W-arm kept the other slice's item and
# the history sections it exists to drop; the declared arm returned UNRESOLVED
# for an anchor that resolves. This arm is what stops the dependency coming back
# — it compares the two implementations rather than trusting either.
mawkbin=$(command -v mawk 2>/dev/null || true)
if [ -z "$mawkbin" ]; then
  ok "SKIP (named): no mawk on this machine, so the portability comparison cannot run — the arm is not silently absent"
else
  pbdir=$(sc_tmpdir); mkdir -p "$pbdir/bin"; ln -sf "$mawkbin" "$pbdir/bin/awk"
  cat > "$pbdir/plan.md" <<'EOF'
# portability fixture

## 3. design

DESIGN-PREAMBLE.

### 3.2 the carrier

CARRIER.

### 3.2.1 the shape

SHAPE.

### 3.3 elsewhere

ELSEWHERE.
EOF
  g_out=$(printf '3.2\n' | ( . "$RS/lib/plan_binds.sh"; plan_binds_spans "$pbdir/plan.md" ) 2>&1)
  m_out=$(printf '3.2\n' | PATH="$pbdir/bin:$PATH" bash -c ". '$RS/lib/plan_binds.sh'; plan_binds_spans '$pbdir/plan.md'" 2>&1)
  [ -n "$g_out" ] && [ "$g_out" = "$m_out" ] \
    && ok "plan_binds_spans returns the same spans under mawk as under the default awk" \
    || bad "awk implementations DISAGREE — default: [$g_out] mawk: [$m_out]"
  # and the W-<id> arm, whose intervals predate this mechanism
  g_h=$(( . "$RS/lib/plan_binds.sh"; plan_binds_head "$pbdir/plan.md" ) 2>&1)
  m_h=$(PATH="$pbdir/bin:$PATH" bash -c ". '$RS/lib/plan_binds.sh'; plan_binds_head '$pbdir/plan.md'" 2>&1)
  [ "$g_h" = "$m_h" ] \
    && ok "plan_binds_head agrees across awk implementations too" \
    || bad "plan_binds_head DISAGREES — default: [$g_h] mawk: [$m_h]"
  # the construct that caused it, pinned by name so a reintroduction is loud
  command grep -nE '\{[0-9]+,[0-9]*\}' "$RS/lib/plan_binds.sh" "$RS/lib/compose.sh" "$RS/lib/md_span.sh" \
    | command grep -vE 'grep -[a-zA-Z]*E' > "$pbdir/intervals.txt" 2>/dev/null || true
  [ ! -s "$pbdir/intervals.txt" ] \
    && ok "no ERE interval remains in the excerpt libraries (the construct mawk cannot parse)" \
    || bad "ERE interval(s) back in an awk program: $(cat "$pbdir/intervals.txt")"
fi

check_done
