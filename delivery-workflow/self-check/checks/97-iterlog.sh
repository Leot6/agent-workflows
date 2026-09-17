#!/usr/bin/env bash
# 97-iterlog — the tree-root iteration-log is internally consistent. The entry
# file is the ONE home of every machine-read fact about a mechanism: each
# entries/<id>.md carries a ```entry head block (status · hook · anchors ·
# landing) and INDEX.md is GENERATED from those by gen-index.sh, so this check
# reads the blocks — status in its closed vocabulary, every field filled, the
# falsifiable-expectation field present on every entry still in play (the
# landfill guard — an entry without one is not an observation) — and then
# regenerates INDEX.md to a pipe and diffs: a hand-edited or stale INDEX reds.
# The narrative half (harvest notes, rulings, the harvest-completion ledger)
# lives in NOTES.md and is swept below.
#
# HONEST BOUNDARY: this checks STRUCTURE and the FIELDS' presence, never the
# expectation's quality — a vacuous "expectation: maybe" passes here; the
# two-anchor judgment (review-standards §14) stays human. It also cannot see
# mechanisms that never got an entry at all. That coverage is a maintainer
# duty, not a check's: `runtime-docs/maintenance.md` §1 binds the commit that
# lands a promoted mechanism to write its entry in the same commit, which is
# the only moment anything knows a mechanism landed.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/fixtures/lib.sh"

ITERLOG="$WF_ROOT/iteration-log"
GEN="$ITERLOG/gen-index.sh"

precond "INDEX.md exists" test -f "$ITERLOG/INDEX.md"
precond "NOTES.md exists (the narrative half)" test -f "$ITERLOG/NOTES.md"
precond "TEMPLATE.md exists" test -f "$ITERLOG/TEMPLATE.md"
precond "gen-index.sh exists and is executable" test -x "$GEN"

# The sweep, as a function over a root so the known-bad fixtures exercise the
# SAME code (never a re-typed copy).
iterlog_consistency() { # <root> -> prints defect lines; rc 0 clean / 1 defects
  local root=$1 d=0 f id st blk k n=0
  [ -d "$root/entries" ] || { echo "no entries/ under $root — the durable home is absent"; return 1; }
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    n=$((n + 1)); id=$(basename "$f" .md)
    blk=$(awk '/^```entry[[:space:]]*$/{b=1; next} b && /^```/{exit} b' "$f")
    [ -n "$blk" ] || { echo "entries/$id.md has no \`\`\`entry head block (status · hook · anchors · landing)"; d=1; continue; }
    st=$(printf '%s\n' "$blk" | awk '/^status:/{sub(/^status:[[:space:]]*/, ""); print; exit}')
    case "$st" in
      open|adopted|closed) : ;;
      *) echo "entries/$id.md: status '$st' is not open|adopted|closed"; d=1 ;;
    esac
    for k in hook anchors landing; do
      command grep -qE "^$k:[[:space:]]*[^[:space:]]" <<< "$blk" \
        || { echo "entries/$id.md: head block lacks '$k:' (an empty field is an unfilled one)"; d=1; }
    done
    # An entry still in play owes the field; a closed one migrated from a bare
    # INDEX row may predate it, and its file is kept for the record it is.
    if [ "$st" != "closed" ]; then
      command grep -qiE 'falsifiable expectation' "$f" 2>/dev/null \
        || { echo "entries/$id.md lacks a falsifiable-expectation field"; d=1; }
    fi
  done < <(find "$root/entries" -name '*.md' -type f 2>/dev/null | sort)
  [ "$n" -ge 1 ] || { echo "entries/ holds no files — the durable home is empty"; return 1; }
  # INDEX.md is DERIVED: a hand edit, or an entry edit without a regenerate, reads stale.
  if [ ! -f "$root/INDEX.md" ]; then
    echo "no INDEX.md under $root — run iteration-log/gen-index.sh"; d=1
  elif ! "$GEN" --stdout "$root" 2>/dev/null | cmp -s - "$root/INDEX.md"; then
    echo "INDEX.md is stale against entries/ — run iteration-log/gen-index.sh (never edit INDEX.md by hand)"; d=1
  fi
  return $d
}

# A FRESH LOG is a legitimate state — a deployment starts with no entries and
# grows them at its first harvest. It is NAMED rather than swept: the sweep's
# own floor (known-bad 5 below) still refuses an empty home as a clean sweep,
# and the one thing an empty home can still get wrong — an INDEX that is not
# its generator's output — is asserted here.
n_live=$(find "$ITERLOG/entries" -name '*.md' -type f 2>/dev/null | command grep -c .)
if [ "${n_live:-0}" -eq 0 ]; then
  "$GEN" --stdout "$ITERLOG" 2>/dev/null | cmp -s - "$ITERLOG/INDEX.md" \
    && ok "fresh iteration-log: INDEX.md is its generator's output over an empty entries/" \
    || bad "INDEX.md is stale against an empty entries/ — run iteration-log/gen-index.sh"
  note "fresh iteration-log: 0 entries — the live entry sweeps below have nothing to read (their fixtures still run)"
else
out=$(iterlog_consistency "$ITERLOG"); rc=$?
if [ $rc -eq 0 ]; then
  ok "live iteration-log consistent: $(find "$ITERLOG/entries" -name '*.md' | command grep -c .) entries ($(command grep -c '^| [a-z0-9-]* | open |' "$ITERLOG/INDEX.md") open · $(command grep -c '^| [a-z0-9-]* | adopted |' "$ITERLOG/INDEX.md") adopted · $(command grep -c '^| [a-z0-9-]* | closed |' "$ITERLOG/INDEX.md") closed), every head block complete, INDEX.md current"
else
  bad "live iteration-log defects:"$'\n'"$(printf '%s' "$out" | sed 's/^/    /')"
fi
fi

# ---------------------------------------------------------------------------
# The body may not restate a head-block key. `gen-index.sh` derives INDEX.md
# from the ```entry fence and reads nothing below it, so the head is the one
# home of every machine-read fact about a mechanism; a second copy in the prose
# is a second place each correction has to reach. That is this tree's most
# measured drift shape (a closed set stated in several places drifts), and it had
# already happened here: `status` had grown as a body bullet across most of the
# corpus with no TEMPLATE.md field contracting it, and the stale ones were all
# stale in the SAME direction — head `adopted` against a body still reading
# `open`. The copy rots at PROMOTION, the one transition this home exists to
# record. No census is written into this header: a count of the corpus kept
# inside the corpus is stale by the commit that writes it (`maintenance.md` §2,
# first instrument). The live verdict below prints the count it swept.
#
# THE DISCRIMINATOR IS THE `- ` LIST PREFIX. A head block writes `status: open`,
# a body bullet writes `- status: open`, and no head-block line in this corpus
# begins with `- ` (the head's contract is one `key: value` per line). An earlier
# form walked the head fence with awk before matching; it was removed rather than
# kept, because with `^- ` in the pattern no mutation could kill it — an unpinned
# property asserting itself. The `- `-anchor fixture below pins what actually
# discriminates.
#
# `anchors` is the named exception and is NOT swept: TEMPLATE.md contracts a body
# anchors field carrying the reading, and its leading number is an INSTANCE count
# in many entries rather than an anchor count, so a sweep would red correct
# material. That pair is kept in agreement by hand.

# ONE HOME for the pattern, and this is a repair rather than a style choice. It
# was written out three times — a header comment, the executable line, and
# TEMPLATE.md's re-derivation command — and by the time anyone compared all
# three, TEMPLATE's had already lost a `[[:space:]]*` and matched strictly less
# than the code, so a reader following the documented command would have read
# clean over a shape this check reds on. A regex quoted in prose is this arm's
# own defect one level up: the second home rots. It lives here, the failure
# message PRINTS it, and TEMPLATE.md names this check instead of restating it.
# WIDENED after a measured escape: the terminator is `[.:]`, not `:`, and it is
# reachable THROUGH the emphasis markers. `- **status.** open` puts the period
# inside the bold, so the old pattern — which required a colon after the closing
# markers — could not see it, and eleven of them stood in ten entries. One had
# already rotted: an entry closed with two body bullets still reading `open`,
# which is the exact shape TEMPLATE.md names ("a head reading `adopted` over a
# body still reading `open`") and the reason this arm exists. What is required
# is a SEPARATOR making the word a label; a bullet that merely begins with the
# word as prose ("- landing the fix required …") has none and is not a hit.
BODY_KEY_RE='^- [*_`]*[[:space:]]*(status|hook|landing)[*_`[:space:]]*[.:]'

# A seam, for the reason `lib/watch.sh` has `_wt_now`: the rc>=2 branch cannot be
# reached with a readable corpus, so without a seam it is unreachable code
# asserting itself — and it is the branch whose whole point is that a dead
# matcher must not read as a clean tree. The fixture overrides this to fail.
_iterlog_grep() { command grep "$@"; }

iterlog_body_restates_head() { # <root> -> prints offending lines; rc 0 clean / 1 found-or-broken
  local root=$1 hits rc n
  n=$(find "$root/entries" -name '*.md' -type f 2>/dev/null | command grep -c .)
  # Floor: an emptied or unreadable corpus sweeps nothing and would read clean.
  [ "${n:-0}" -ge 1 ] || { echo "no entries swept under $root — a clean verdict over nothing"; return 1; }
  hits=$(_iterlog_grep -rnE "$BODY_KEY_RE" --include='*.md' "$root/entries" 2>/dev/null)
  rc=$?
  # rc is split, not folded, for the reason iterlog_line_pins states below: 1 is
  # "nothing matches" (the clean verdict), 2+ is "the sweep did not complete",
  # and a `|| true` that folds them makes a dead matcher read as a clean tree.
  case $rc in
    # Both substitutions are ANCHORED. An earlier form used `s|^.*/entries/|`,
    # which is greedy: an offending line whose own text contained `/entries/`
    # lost its filename, its line number AND the words the known-bad greps for.
    0) printf '%s\n' "$hits" \
         | sed -e "s|^$root/entries/|entries/|" \
               -e 's|^\([^:]*\):\([0-9]*\):|\1:\2 body restates a head-block key: |'
       return 1 ;;
    1) return 0 ;;
    *) { [ -n "$hits" ] && printf '%s\n' "$hits"
         echo "grep could not sweep $root/entries (rc $rc) — the sweep did not complete; this is not a clean verdict"; }
       return 1 ;;
  esac
}

# TWO preconditions, not one, because they hold different properties and either
# alone is weaker than the pair. The equality alone cannot see a corpus shrunk to
# a third of itself with INDEX.md regenerated — it passes in silence — and the
# floor alone cannot see the sweep and the index describing different sets. They
# are a FUNCTION rather than two inline `test`s for the reason §13 step 3 gives:
# a precondition that only ever runs against a healthy corpus passes whatever it
# is comparing, so inline it asserts nothing and its threshold can be lowered in
# the same edit that breaks what it guards. Driven below against a corpus built
# to fail each way.
iterlog_corpus_floor() { # <root> <min> -> rc 0 ok / 1 not; prints why
  local root=$1 min=$2 n_ent n_row
  n_ent=$(find "$root/entries" -name '*.md' -type f 2>/dev/null | command grep -c .)
  n_row=$(command grep -cE '^\| [a-z0-9-]+ \| (open|adopted|closed) \|' "$root/INDEX.md" 2>/dev/null)
  [ "${n_ent:-0}" -ge "$min" ] \
    || { echo "corpus is $n_ent entries, under the floor of $min — a clean sweep over a fraction of the home is not a clean verdict"; return 1; }
  [ "${n_ent:-0}" -eq "${n_row:-0}" ] \
    || { echo "entry files $n_ent against INDEX rows $n_row — the sweep and the index describe different sets"; return 1; }
  return 0
}
# The live floor is the corpus the deployment has (>= 1 once anything was
# harvested); the fixture below drives the size half at 100 so it stays pinned.
n_ent=$n_live
if [ "${n_ent:-0}" -gt 0 ]; then
precond "the body sweep sees the whole corpus, one file per INDEX row (saw $n_ent files)" \
  iterlog_corpus_floor "$ITERLOG" 1
out=$(iterlog_body_restates_head "$ITERLOG"); rc=$?
if [ $rc -eq 0 ]; then
  ok "no entry body restates status/hook/landing — the head block is their one home ($n_ent entries swept)"
else
  bad "body restates a head-block key (write \`what stays open:\` / \`landed:\` instead):"$'\n'"$(printf '%s' "$out" | sed 's/^/    /')"
fi
fi

# known-bad, one per key and one per spelling the pattern claims to carry. The
# list is FLOORED: truncating it is the "truncate a reason list" mutation that a
# diff never shows, and without the floor four probes could be deleted and the
# check would stay green with a smaller number.
d=$(sc_tmpdir); mkdir -p "$d/entries"
_bre_entry() { # file body-bullet
  printf '# e\n\n```entry\nstatus: adopted\nhook: h\nanchors: 1 — t\nlanding: c\n```\n\n- falsifiable expectation: x\n%s\n' "$1" > "$d/entries/probe.md"
}
BRE_PROBES=(
  '- status: open'
  '- hook: something'
  '- landing: somewhere'
  '- **status**: open'
  '- `status`: open'
  '- _status_: open'
  '- status : open'
  '-  status: open'
  # the period-inside-the-emphasis spelling, which the pattern once could not
  # see: eleven stood in ten entries and one had already rotted
  '- **status.** open'
  '- **status.**'
  '- **landing.** the commit'
  '- `hook.` the thing it did'
)
precond "the known-bad probe list still carries N>=8 spellings (saw ${#BRE_PROBES[@]})" \
  test "${#BRE_PROBES[@]}" -ge 8
for probe in "${BRE_PROBES[@]}"; do
  _bre_entry "$probe"
  out=$(iterlog_body_restates_head "$d"); rc=$?
  [ $rc -eq 1 ] && command grep -q 'restates a head-block key' <<< "$out" \
    && ok "known-bad: a body \`$probe\` is caught by name" \
    || bad "known-bad \`$probe\` NOT caught (rc=$rc, out: $out)"
done
# …and the remedies the failure message prescribes must actually pass.
for good in '- what stays open: the residual field' '- landed: the emit-time door' \
            '- landing the fix required care' '- landings are recorded elsewhere'; do
  _bre_entry "$good"
  iterlog_body_restates_head "$d" >/dev/null 2>&1 \
    && ok "…\`${good%%:*}\` passes (a fix it demands, or prose merely starting with the word)" \
    || bad "the prescribed remedy \`$good\` is refused — the arm would forbid its own fix"
done
# The offender is NAMED, and named even when its own text carries the corpus
# path — the greedy-substitution defect this arm shipped once.
_bre_entry '- status: see /entries/other.md for the reading'
out=$(iterlog_body_restates_head "$d")
command grep -q '^entries/probe\.md:[0-9]* body restates a head-block key:' <<< "$out" \
  && ok "the offending file and line survive a hit whose own text contains the corpus path" \
  || bad "the report lost its file/line to a greedy substitution; got: $out"
# The sweep is scoped to markdown. entries/ holds only `.md` today, so dropping
# `--include` changes no verdict on the live corpus — which is exactly why it
# needs a fixture rather than a reader's confidence: an unpinned decision is
# unpinned whether or not it currently matters.
printf -- '- status: open\n' > "$d/entries/notes.txt"
_bre_entry '- falsifiable expectation: x'
iterlog_body_restates_head "$d" >/dev/null 2>&1 \
  && ok "a non-markdown file under entries/ is not swept (the sweep is scoped to *.md)" \
  || bad "the sweep left its extension scope and reported a non-markdown file"
rm -f "$d/entries/notes.txt"
# The `- ` anchor is what separates a head block from a body bullet: an entry
# that is ONLY a head block must read clean. A pattern that lost the anchor
# would match the head's own `status:` line and red here.
printf '# e\n\n```entry\nstatus: open\nhook: h\nanchors: 1 — t\nlanding: -\n```\n\n- falsifiable expectation: x\n' > "$d/entries/probe.md"
iterlog_body_restates_head "$d" >/dev/null 2>&1 \
  && ok "a head block's own status/hook/landing lines read clean (the \`- \` prefix is the discriminator)" \
  || bad "the arm reds on a head block — the pattern lost its \`- \` anchor and would refuse every entry"
# A DEAD MATCHER IS NOT A CLEAN TREE. Driven through the seam, because no
# readable corpus can make grep exit 2 and an unreachable branch asserts nothing.
_iterlog_grep() { return 2; }
out=$(iterlog_body_restates_head "$d"); rc=$?
[ $rc -eq 1 ] && command grep -q 'did not complete' <<< "$out" \
  && ok "known-bad: a sweep that exits rc>=2 is refused as incomplete, never read as clean" \
  || bad "a dead matcher read as a clean tree (rc=$rc, out: $out)"
_iterlog_grep() { command grep "$@"; }
# …and the seam restored must go back to agreeing with the live verdict.
iterlog_body_restates_head "$d" >/dev/null 2>&1 \
  && ok "…and the restored matcher reads the same clean entry as before (the seam is not a bypass)" \
  || bad "the restored matcher disagrees with itself — the seam changed the verdict"
# floor: an emptied corpus must not read clean.
rm -f "$d/entries"/*.md
iterlog_body_restates_head "$d" >/dev/null 2>&1 \
  && bad "known-bad: an emptied entries/ swept nothing and read CLEAN (vacuous arm)" \
  || ok "known-bad: an emptied entries/ refuses to call itself clean (the floor holds)"

# The corpus floor, driven both ways against a synthetic home — the fixture the
# inline form could not have, and the reason the pair is a function.
c=$(sc_tmpdir); mkdir -p "$c/entries"
{ echo '| id | status | hook | anchors (t=) | landing |'; echo '|---|---|---|---|---|'; } > "$c/INDEX.md"
i=1; while [ $i -le 100 ]; do
  printf '# e%s\n\n```entry\nstatus: open\nhook: h\nanchors: 1 — t\nlanding: -\n```\n\n- falsifiable expectation: x\n' "$i" > "$c/entries/e$i.md"
  echo "| e$i | open | h | t | - |" >> "$c/INDEX.md"
  i=$((i + 1))
done
iterlog_corpus_floor "$c" 100 >/dev/null 2>&1 \
  && ok "a full corpus whose files and INDEX rows agree passes the floor (100 and 100)" \
  || bad "the floor refuses a healthy corpus: $(iterlog_corpus_floor "$c" 100)"
rm -f "$c/entries/e100.md"
out=$(iterlog_corpus_floor "$c" 100); rc=$?
[ $rc -eq 1 ] && command grep -q 'fraction of the home' <<< "$out" \
  && ok "known-bad: a corpus one entry under the floor is refused BY SIZE (99 < 100)" \
  || bad "known-bad: a shrunken corpus passed the floor (rc=$rc, out: $out)"
printf '# e\n\n```entry\nstatus: open\nhook: h\nanchors: 1 — t\nlanding: -\n```\n\n- falsifiable expectation: x\n' > "$c/entries/e100.md"
command grep -v '^| e50 |' "$c/INDEX.md" > "$c/INDEX.tmp" && mv "$c/INDEX.tmp" "$c/INDEX.md"
out=$(iterlog_corpus_floor "$c" 100); rc=$?
[ $rc -eq 1 ] && command grep -q 'different sets' <<< "$out" \
  && ok "known-bad: files and INDEX rows disagreeing is refused BY SET (100 files, 99 rows)" \
  || bad "known-bad: a file/row mismatch passed the floor (rc=$rc, out: $out)"

# ---------------------------------------------------------------------------
# No bare `file:line` citation. This directory is the DURABLE home — it outlives
# the topic trees whose evidence it carries, and it cites a tree that keeps
# moving underneath it. Measured, and the reason this arm exists: a harvest
# transcribed four sites by line number, every pin exact against the tree it
# was measured on, and the same maintenance round's later commits moved all
# four. Nothing went red; the addresses still resolved, to other constructs.
# The rule is the entry's own discriminating test — strip the volatile part,
# does the sentence still locate the thing? A construct name does; `:118` does
# not — so cite the function, the key, the manifest item, the table row.
# HONEST BOUNDARY: the extension list is `sh|kv|tsv|md|py`, which is what this
# tree is written in — a citation into an extensionless file or a delivered
# project's `.cc`/`.h` is not seen, so an entry may quote such an address as the
# EVIDENCE it is. An in-tree address quoted as evidence does hit the arm, and
# should: write it out — "`owed.sh` line 118". A few words, and the rule stays a
# grammar rule rather than an exemption list that has to be kept current.
iterlog_line_pins() { # <root> -> prints offending citations; rc 0 clean / 1 found-or-broken
  local hits rc
  hits=$(command grep -rnoE '[A-Za-z0-9_/.-]+\.(sh|kv|tsv|md|py):[0-9]+(-[0-9]+)?' "$1" 2>/dev/null)
  rc=$?
  # rc is split, not folded: 1 is "nothing matches" (the clean verdict), 2+
  # is "the sweep did not complete" (unreadable file, recursion refused) —
  # a delivered repo's `|| true` lesson: a clean verdict and a dead matcher are
  # not the same silence. GNU grep returns 2 on error EVEN WITH matches
  # found, so the error line rides AFTER any hits it did deliver — claiming
  # "never ran" there would be this arm's own defect turned on itself.
  case $rc in
    0) printf '%s\n' "$hits"; return 1 ;;
    1) return 0 ;;
    *) { [ -n "$hits" ] && printf '%s\n' "$hits"
         echo "grep could not sweep $1 (rc $rc) — the sweep did not complete; this is not a clean verdict"; }
       return 1 ;;
  esac
}

out=$(iterlog_line_pins "$ITERLOG"); rc=$?
if [ $rc -eq 0 ]; then
  ok "iteration-log cites no bare file:line into a tree that moves (constructs, keys and row names instead)"
else
  bad "bare file:line citations in the durable home (name the construct instead):"$'\n'"$(printf '%s' "$out" | sed 's|^|    |')"
fi

# The same rule over the SOURCES — the second root, by owner ruling:
# comments under runtime-scripts/ rot exactly the way the durable home's prose
# does (five instances measured there, one rotted by a file split in the same
# session) — this arm holds the rewritten zero at commit time. The SAME function sweeps both roots
# (never a re-typed copy), and the root is floored per this suite's
# standing duty: an emptied root would sweep nothing and read clean.
n_src=$(find "$RS" -name '*.sh' -type f 2>/dev/null | command grep -c . || true)
precond "the source sweep sees N>=20 shell files under runtime-scripts/ (saw $n_src)" \
  test "${n_src:-0}" -ge 20
out2=$(iterlog_line_pins "$RS"); rc2=$?
if [ $rc2 -eq 0 ]; then
  ok "runtime-scripts/ carries no bare file:line citation either (construct names in comments too — the class cannot regrow silently)"
else
  bad "bare file:line citations in the sources (name the construct instead):"$'\n'"$(printf '%s' "$out2" | sed 's|^|    |')"
fi

# known-bad: the shape the arm exists for must fire.
d=$(sc_tmpdir); mkdir -p "$d/entries"
printf '# e\n## falsifiable expectation\nsee `lib/owed.sh:118` for the test\n' > "$d/entries/pin.md"
iterlog_line_pins "$d" >/dev/null 2>&1 && bad "known-bad: a bare owed.sh:118 pin read as clean" \
  || ok "known-bad: a bare \`owed.sh:118\` pin is caught"
# and a clean tree must PASS, or the arm is a permanent red
printf '# e\n## falsifiable expectation\nsee `_owed_cu_ok()` in `lib/owed.sh`\n' > "$d/entries/pin.md"
iterlog_line_pins "$d" >/dev/null 2>&1 \
  && ok "a construct-named citation passes (the arm asks for a fix it then accepts)" \
  || bad "construct-named citation rejected — the arm would forbid its own remedy"

# The head-block fixtures. Every known-bad below regenerates INDEX.md first, so
# the defect named is the one under test and never a stale INDEX beside it.
mk_entry() { # root id status [body]
  printf '# %s\n\n```entry\nstatus: %s\nhook: what happened and why it matters\nanchors: t: 1799000001\nlanding: -\n```\n\n%s\n' \
    "$2" "$3" "${4:-- falsifiable expectation: the next run shows x}" > "$1/entries/$2.md"
}

# Known-bad 1: an entry with no head block (the shape every pre-migration file had).
d=$(sc_tmpdir); mkdir -p "$d/entries"
printf '# e\n- falsifiable expectation: x\n' > "$d/entries/nohead.md"
"$GEN" "$d" > /dev/null
out=$(iterlog_consistency "$d"); rc=$?
[ $rc -ne 0 ] && command grep -q 'nohead.md has no ```entry head block' <<< "$out" \
  && ok "known-bad: an entry without a head block is caught by name" \
  || bad "known-bad 1 NOT caught (rc=$rc, out: $out)"

# Known-bad 2: a status outside the closed vocabulary.
d=$(sc_tmpdir); mkdir -p "$d/entries"
mk_entry "$d" badst pending
"$GEN" "$d" > /dev/null
out=$(iterlog_consistency "$d"); rc=$?
[ $rc -ne 0 ] && command grep -q "status 'pending' is not open|adopted|closed" <<< "$out" \
  && ok "known-bad: a status outside open|adopted|closed is caught" \
  || bad "known-bad 2 NOT caught (rc=$rc, out: $out)"

# Known-bad 3: a STALE INDEX — the entry moved, INDEX.md did not (the one-home
# property this layout exists for: the row is derived, never edited).
d=$(sc_tmpdir); mkdir -p "$d/entries"
mk_entry "$d" a open
"$GEN" "$d" > /dev/null
precond "the generated INDEX carries the entry's row (else the stale test is vacuous)" \
  bash -c 'command grep -q "^| a | open |" "$1/INDEX.md"' _ "$d"
plat_sed_i 's/^status: open$/status: adopted/' "$d/entries/a.md"
out=$(iterlog_consistency "$d"); rc=$?
[ $rc -ne 0 ] && command grep -q 'INDEX.md is stale against entries/' <<< "$out" \
  && ok "known-bad: an entry edit without a regenerate reads as a STALE INDEX" \
  || bad "known-bad 3 NOT caught (rc=$rc, out: $out)"
"$GEN" "$d" > /dev/null
[ -z "$(iterlog_consistency "$d")" ] \
  && ok "…and regenerating clears it (the arm accepts the remedy it demands)" \
  || bad "a regenerated INDEX still reads stale: $(iterlog_consistency "$d")"
printf '| a | open | hand-edited | t | - |\n' >> "$d/INDEX.md"
iterlog_consistency "$d" | command grep -q 'INDEX.md is stale' \
  && ok "known-bad: a hand-appended INDEX row is caught the same way (INDEX is derived, full stop)" \
  || bad "a hand-edited INDEX read as current"

# Known-bad 4: an OPEN entry with no expectation field; a CLOSED one without it
# passes (a row migrated from before the field was required keeps its file).
d=$(sc_tmpdir); mkdir -p "$d/entries"
mk_entry "$d" noexp open "no fields here"
"$GEN" "$d" > /dev/null
out=$(iterlog_consistency "$d"); rc=$?
[ $rc -ne 0 ] && command grep -q 'noexp.md lacks a falsifiable-expectation field' <<< "$out" \
  && ok "known-bad: an open entry without the expectation field is caught (the landfill guard)" \
  || bad "known-bad 4 NOT caught (rc=$rc, out: $out)"
rm "$d/entries/noexp.md"; mk_entry "$d" cl closed "migrated from a bare row"
"$GEN" "$d" > /dev/null
[ -z "$(iterlog_consistency "$d")" ] \
  && ok "a closed entry without the field passes (kept for the record it is, not as an observation)" \
  || bad "a closed migrated entry was refused: $(iterlog_consistency "$d")"

# Known-bad 5: an empty home is not a pass.
d=$(sc_tmpdir); mkdir -p "$d/entries"
"$GEN" "$d" > /dev/null
out=$(iterlog_consistency "$d"); rc=$?
[ $rc -ne 0 ] && command grep -q 'holds no files' <<< "$out" \
  && ok "known-bad: an empty entries/ is refused (the home wrote nothing)" \
  || bad "known-bad 5 NOT caught (rc=$rc, out: $out)"

# ---------------------------------------------------------------------------
# A shared `t=` stamp is disambiguated as `<stamp>(rec N)` (NOTES.md's harvest
# conventions): `t=` is NOT a record identity. Measured on a live topic — 46
# records over 39 distinct stamps — and two of those collisions each held the
# FIRST anchor of a separately promoted mechanism, so digesting a stamp once
# drops an anchor while a stamp-wise completion test stays clean. The
# convention was written down and then, at the very next harvest, not applied.
# Nothing caught it because nothing looked — this arm is that look.
#
# GRANDFATHERED, and the list can only SHRINK: a stamp written before the
# convention, whose ordinal can no longer be derived because its topic tree is
# cleaned. A stale entry FAILS too — one that no longer collides, or that has
# since gained its `(rec N)`, must be removed. Fail on unclassified AND fail on
# stale is the difference between an allow-list that holds and one that
# accumulates dead entries.
ITERLOG_GRANDFATHERED_STAMPS=""

iterlog_stamp_ids() { # <root> <grandfathered> -> prints defects; rc 0 clean / 1 defects
  awk -v grand="$2" '
    BEGIN { n=split(grand, g, / +/); for (i=1;i<=n;i++) if (g[i]!="") gr[g[i]]=1 }
    /^\| / {
      row=$0; sub(/^\| /,"",row); id=row; sub(/ *\|.*/,"",id)
      if (id=="id" || id ~ /^-+$/) next
      s=$0
      # `[0-9]+` with an exact-length test, not `[0-9]{10}`: mawk has no ERE
      # intervals at all, and this is also STRICTER — `{10}` matches the first
      # ten digits of an eleven-digit run and leaves the remainder as a
      # separate token, so a number that is not a stamp could read as one.
      while (match(s, /[0-9]+/)) {
        stamp=substr(s, RSTART, RLENGTH); rest=substr(s, RSTART+RLENGTH)
        if (length(stamp) == 10) {
          bare=(rest ~ /^\(rec /) ? 0 : 1
          if (!((stamp SUBSEP id) in seen)) {
            seen[stamp,id]=1; cnt[stamp]++; who[stamp]=who[stamp] " " id
          }
          if (bare) { barecnt[stamp]++; bareid[stamp]=bareid[stamp] " " id }
        }
        s=rest
      }
    }
    END {
      for (k in cnt) {
        if (cnt[k] < 2) continue
        collided[k]=1
        if (barecnt[k] > 0 && !(k in gr))
          printf "shared stamp %s is cited bare by%s (the stamp is carried by%s) — disambiguate as %s(rec N)\n", k, bareid[k], who[k], k
        if (k in gr && barecnt[k] == 0)
          printf "grandfathered stamp %s no longer has a bare citation — remove it from ITERLOG_GRANDFATHERED_STAMPS\n", k
      }
      for (k in gr) if (!(k in collided))
        printf "grandfathered stamp %s no longer collides across rows — remove it from ITERLOG_GRANDFATHERED_STAMPS\n", k
      exit 0
    }' "$1/INDEX.md"
}

out=$(iterlog_stamp_ids "$ITERLOG" "$ITERLOG_GRANDFATHERED_STAMPS")
if [ -z "$out" ]; then
  ok "every stamp shared across INDEX rows carries its (rec N), and the grandfathered list is current"
else
  bad "INDEX stamp-identity defects:"$'\n'"$(printf '%s' "$out" | sed 's/^/    /')"
fi

# known-bad: a NEW shared stamp written bare must fire (the measured shape).
d=$(sc_tmpdir)
printf '| a | open | h | topic: 1799000001 | entries/a.md |\n| b | open | h | topic: 1799000001 | entries/b.md |\n' > "$d/INDEX.md"
iterlog_stamp_ids "$d" "" | command grep -q '1799000001 is cited bare' \
  && ok "known-bad: a shared stamp written bare on two rows is caught" \
  || bad "known-bad: a bare shared stamp read as clean — the arm is vacuous"

# and the remedy the arm asks for must PASS, or it forbids its own fix.
printf '| a | open | h | topic: 1799000001(rec 3) | entries/a.md |\n| b | open | h | topic: 1799000001(rec 4) | entries/b.md |\n' > "$d/INDEX.md"
[ -z "$(iterlog_stamp_ids "$d" "")" ] \
  && ok "a disambiguated collision passes (the arm accepts the fix it demands)" \
  || bad "arm rejects (rec N) — it would forbid its own remedy"

# known-bad: a stale grandfather entry (its stamp no longer collides) must fire.
iterlog_stamp_ids "$d" "1786000009" | command grep -q 'no longer collides' \
  && ok "known-bad: a stale grandfathered stamp is caught (the list can only shrink)" \
  || bad "known-bad: a stale grandfather entry read as clean — the list would rot"

# ---------------------------------------------------------------------------
# Harvest completeness — the count was DECLARED, not merely owed.
# NOTES.md's harvest conventions make one test mandatory at every harvest: the
# observations surface's record count must equal the records carried.
# Nothing checked that the test had been RUN. Measured: one harvest carried 2
# of 9 records and its block stated no count — and one uncarried record
# declared in its own text that it was the SECOND anchor of a mechanism whose
# first anchor was also uncarried, so the promotion trigger this directory
# exists to make visible was invisible in it.
# The fix is a FORMAT, not an instruction, and that is the whole point: a
# format requirement cannot be satisfied without doing the count, while an
# instruction can be nodded at.
# The line carries the STAMPS, not just counts, and the difference is the whole
# design. A count can be written without reading the surface — it is the proxy
# `review-standards.md` §2 refuses everywhere else in this tree. A stamp list
# cannot be, and every entry of it is checkable right here: each must resolve to
# an INDEX ROW (not to the file, which would resolve each declaration against
# its own declaration — measured on this arm's own known-bad before landing,
# the same self-reference shape as derive_report's mention probe reading its
# own pasted output).
#
# HONEST BOUNDARY, measured rather than asserted. Two mutations on the live
# ledger: a stamp changed to one no row carries REDS by name; a stamp silently
# DROPPED from the list passes, because `records=` still bounds it from above.
# So what is verified is the CARRIAGE — every stamp claimed was really carried
# — and what stays a maintainer's declaration is that the list is COMPLETE
# against the surface. That half cannot be mechanised here at all: the
# observations surface lives in a topic tree this suite has no access to, and
# that tree is cleaned or archived after close-out. It stays the maintainer's,
# at harvest time, while the surface is still readable.
iterlog_harvest_completion() { # <root> -> prints defect lines; rc 0 clean / 1 defects
  # idx/notes from $1, never from `root` — a name assigned earlier in the SAME
  # `local` is not yet visible to the ones after it (the sibling sweep above
  # already spells it this way for the same reason). The ledger — harvest
  # blocks and their completion lines — is narrative and lives in NOTES.md;
  # the rows its stamps must resolve against are INDEX.md's (generated).
  local root=$1 idx="$1/INDEX.md" notes="$1/NOTES.md" d=0 n line hdrs comps
  [ -f "$notes" ] || { echo "no NOTES.md under $root — the harvest ledger's home"; return 1; }
  [ -f "$idx" ] || { echo "no INDEX.md under $root"; return 1; }
  hdrs=$(command grep -E '^> \*{0,2}Harvest [0-9]+ \(' "$notes" \
         | sed -E 's/^> \*{0,2}Harvest ([0-9]+) \(.*/\1/' | sort -n -u)
  comps=$(command grep -E '^> harvest-completion: harvest=[0-9]+ ' "$notes" \
          | sed -E 's/^> harvest-completion: harvest=([0-9]+) .*/\1/' | sort -n -u)
  for n in $hdrs; do
    command grep -qx "$n" <<< "$comps" || {
      echo "harvest $n opens a block but writes no 'harvest-completion:' line — the record count the INDEX header makes mandatory was never declared"; d=1; }
  done
  for n in $comps; do
    command grep -qx "$n" <<< "$hdrs" || {
      echo "a harvest-completion line claims harvest $n, which opens no block"; d=1; }
  done
  local nstamp s hv
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    hv=$(printf '%s' "$line" | sed -E 's/.*harvest=([0-9]+).*/\1/')
    command grep -qE ' records=[1-9][0-9]* ' <<< "$line" \
      || { echo "harvest-completion lacks a positive records= : $line"; d=1; }
    command grep -qE ' rows=[1-9][0-9]* ' <<< "$line" \
      || { echo "harvest-completion lacks a positive rows= : $line"; d=1; }
    # The STAMPS are the printed instance set. A count can be written without
    # reading the surface; a stamp list cannot, and every entry of it is
    # resolvable right here against the rows.
    case "$line" in
      *' stamps='*) : ;;
      *) echo "harvest $hv declares no stamps= — a count is not a carriage record (review-standards §2: print the instances, never the number alone)"; d=1; continue ;;
    esac
    nstamp=0
    for s in $(printf '%s' "$line" | sed -E 's/.* stamps=//'); do
      case "$s" in
        [0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]*) nstamp=$((nstamp+1)) ;;
        *) echo "harvest $hv stamps= carries a non-stamp token '$s'"; d=1; continue ;;
      esac
      # Search the ROWS, never the whole file: the completion line itself lists
      # the stamp, so a whole-file grep resolves every declaration against its
      # own declaration. Measured on this arm's own known-bad before landing —
      # the same self-reference shape as derive_report's mention probe reading
      # its own pasted output.
      command grep -E '^\| ' "$idx" | command grep -qF "$s" \
        || { echo "harvest $hv claims stamp $s but no INDEX row carries it — the record was counted and not carried"; d=1; }
    done
    [ "$nstamp" -gt 0 ] \
      || { echo "harvest $hv declares an EMPTY stamps= (a vacuous carriage record)"; d=1; }
    local rec
    rec=$(printf '%s' "$line" | sed -E 's/.* records=([0-9]+).*/\1/')
    [ "${rec:-0}" -ge "$nstamp" ] \
      || { echo "harvest $hv declares records=$rec but lists $nstamp stamps — records is bounded below by the stamps carried"; d=1; }
  done <<< "$(command grep -E '^> harvest-completion:' "$notes")"
  return $d
}

# Floor FIRST: an extractor that stops matching must red, never pass on zero.
nh=$(command grep -cE '^> \*{0,2}Harvest [0-9]+ \(' "$ITERLOG/NOTES.md" || true)
# The extractor's floor lives on the fixtures below (a declared block with no
# line must red); a live ledger with no block yet is a fresh log, named.
[ "${nh:-0}" -gt 0 ] || note "fresh harvest ledger: NOTES.md opens no harvest block yet"

out=$(iterlog_harvest_completion "$ITERLOG"); rc=$?
if [ $rc -eq 0 ]; then
  ok "every harvest block declares its carriage: $nh blocks, each with a well-formed harvest-completion line"
else
  bad "harvest-completion defects:"$'\n'"$(printf '%s' "$out" | sed 's/^/    /')"
fi

# Fixtures: the ledger goes to NOTES.md, the rows to INDEX.md — the two homes
# the live check reads.
hv_fixture() { # root notes-text rows-text
  printf '%b' "$2" > "$1/NOTES.md"; printf '%b' "$3" > "$1/INDEX.md"
}

# known-bad: a harvest block with no completion line — the measured shape.
d=$(sc_tmpdir)
hv_fixture "$d" '> **Harvest 9 (2099-01-01, some_topic).** Prose with no count.\n' '| id | status |\n'
iterlog_harvest_completion "$d" | command grep -q 'harvest 9 opens a block but writes no' \
  && ok "known-bad: a harvest block that declares no carriage is caught (the measured shape)" \
  || bad "known-bad: an undeclared harvest read as clean — the arm is vacuous"

# and the remedy must PASS, or the arm forbids its own fix.
hv_fixture "$d" '> **Harvest 9 (2099-01-01, some_topic).** Prose.\n> harvest-completion: harvest=9 topic=some_topic records=4 rows=3 stamps=1799000001 1799000002 1799000003\n' \
  '| a | open | h | t: 1799000001 1799000002 1799000003 | x |\n'
[ -z "$(iterlog_harvest_completion "$d")" ] \
  && ok "a declared carriage passes (the arm accepts the fix it demands)" \
  || bad "arm rejects a well-formed harvest-completion line — it would forbid its own remedy"

# known-bad: a COUNT with no stamps is the proxy this ledger exists to refuse.
hv_fixture "$d" '> **Harvest 9 (2099-01-01, t).** P.\n> harvest-completion: harvest=9 topic=t records=4 rows=3\n' ''
iterlog_harvest_completion "$d" | command grep -q 'declares no stamps=' \
  && ok "known-bad: a count with no stamp list is refused (print the instances, never the number alone)" \
  || bad "known-bad: a bare count read as a carriage record — the ledger is back to a proxy"

# known-bad, THE ONE THAT MATTERS: a stamp counted but carried by no row — the
# measured failure at instance grain rather than at block grain.
hv_fixture "$d" '> **Harvest 9 (2099-01-01, t).** P.\n> harvest-completion: harvest=9 topic=t records=3 rows=2 stamps=1799000001 1799000009\n' \
  '| a | open | h | t: 1799000001 | x |\n'
iterlog_harvest_completion "$d" | command grep -q 'claims stamp 1799000009 but no INDEX row carries it' \
  && ok "known-bad: a stamp counted and not carried is caught by name (the measured defect, at instance grain)" \
  || bad "known-bad: an uncarried stamp read as clean — the stamp list would be decoration"

# known-bad: records= below the stamps listed.
hv_fixture "$d" '> **Harvest 9 (2099-01-01, t).** P.\n> harvest-completion: harvest=9 topic=t records=1 rows=1 stamps=1799000001 1799000002\n' \
  '| a | open | h | t: 1799000001 1799000002 | x |\n'
iterlog_harvest_completion "$d" | command grep -q 'records is bounded below by the stamps carried' \
  && ok "known-bad: records= under the stamp count is refused" \
  || bad "known-bad: records= under its own stamp list read as clean"

# known-bad: a zero count is not a declaration, it is an empty one.
hv_fixture "$d" '> **Harvest 9 (2099-01-01, t).** P.\n> harvest-completion: harvest=9 topic=t records=0 rows=0 stamps=1799000001\n' \
  '| a | open | h | t: 1799000001 | x |\n'
iterlog_harvest_completion "$d" | command grep -q 'lacks a positive records=' \
  && ok "known-bad: records=0 is refused (a harvest that carried nothing still counted nothing)" \
  || bad "known-bad: records=0 read as a declaration"

# known-bad: a completion line for a harvest that opens no block (the reverse
# direction — a line left behind by a renumbering can only be caught this way).
hv_fixture "$d" '> harvest-completion: harvest=9 topic=t records=4 rows=3\n' ''
iterlog_harvest_completion "$d" | command grep -q 'claims harvest 9, which opens no block' \
  && ok "known-bad: an orphan completion line is caught (the sweep runs both ways)" \
  || bad "known-bad: an orphan completion line read as clean"

# ---------------------------------------------------------------------------
# Every commit the durable home CITES is one a reader can still open.
# `iteration-log/cite-check.sh` is the sweep; this arm proves it works, over a
# git repository built here rather than over the delivered one — self-check is
# hermetic and this tree is repo-agnostic on purpose (no workflow file names a
# delivered repository; the topic's `project.kv repo=` does), so the tool takes
# the repo as an argument and the LIVE sweep is the maintainer's to run: after
# any history consolidation, and before deleting a backup ref.
# Measured over three topics and three consolidations: 20 cited commits off
# the delivered branch, SIX on no ref at all — three of them one closed
# validation-debt row's entire evidence, 26 days into a 30-day reflog expiry.
echo "-- cited commits resolve: the durable home's SHAs outlive the rewrites --"
CC="$ITERLOG/cite-check.sh"
precond "cite-check.sh exists and is executable" test -x "$CC"

# the suite's own builder, never a re-typed git init: it also fixes the branch
# name, which differs by git version (2.25 has no `init -b`).
cc_repo=$(sc_tmpdir)/repo
cc_branch=$(mk_repo "$cc_repo" | cut -f2)
cc_commit() { # <msg> -> prints full sha
  echo "$1" >> "$cc_repo/f.txt"
  git -C "$cc_repo" add f.txt
  git -C "$cc_repo" commit -q -m "$1"
  git -C "$cc_repo" rev-parse HEAD
}
live_sha=$(cc_commit "kept on the branch")
# the orphan: committed on a side branch that is then deleted, which is exactly
# what a consolidation does to the range it replaces.
git -C "$cc_repo" checkout -q -b doomed
dead_sha=$(cc_commit "rewritten away by a consolidation")
git -C "$cc_repo" checkout -q "$cc_branch"
git -C "$cc_repo" branch -q -D doomed
# BOTH halves, because the first alone passes when git is broken: an errored
# for-each-ref prints nothing and "no ref contains it" reads the same as "the
# command did not run". Measured here — this precond passed green against a
# fixture whose `git init` had failed outright.
precond "the fixture's orphan resolves as a commit AND is on no ref" \
  bash -c '[ "$(git -C "$1" cat-file -t "$2" 2>/dev/null)" = commit ] &&
           [ -z "$(git -C "$1" for-each-ref --contains "$2" --format="%(refname)" 2>/dev/null)" ]' _ "$cc_repo" "$dead_sha"

cc_root=$(sc_tmpdir)/tree
mkdir -p "$cc_root/iteration-log/entries" "$cc_root/self-check"
printf 'anchors: the live one %s\n' "${live_sha:0:8}" > "$cc_root/iteration-log/entries/live.md"

cc_clean=$("$CC" "$cc_repo" "$cc_root" 2>&1) \
  && ok "a home citing only reachable commits reads clean" \
  || bad "cite-check red on a corpus whose every citation resolves — the clean path is broken"
# the sole-home tier: a citation that resolves TODAY but hangs on one ref is what
# operations.md §8's deletion rule is about, and it must be named on the CLEAN
# path — a warning that only prints beside a failure is a warning nobody reads
# at the moment it matters, which is before the ref is deleted.
command grep -q 'sole home' <<< "$cc_clean" \
  && ok "the clean verdict still names the citations hanging on a SINGLE ref (§8's pre-deletion cue)" \
  || bad "cite-check reported clean without naming sole-ref citations — §8's deletion rule has no input"

# the arm's whole purpose: an orphaned citation must be NAMED, not merely counted.
printf 'this entry rests on %s\n' "${dead_sha:0:8}" > "$cc_root/self-check/validation-debt.md"
cc_out=$("$CC" "$cc_repo" "$cc_root" 2>&1); cc_rc=$?
[ $cc_rc -eq 1 ] \
  && ok "known-bad: a citation to a commit on no ref FAILS (rc 1)" \
  || bad "known-bad: an orphaned citation read as clean (rc $cc_rc)"
command grep -q "${dead_sha:0:8}" <<< "$cc_out" \
  && ok "the orphaned sha is named, not just counted" \
  || bad "cite-check counted an orphan without naming it — the fix would have no address"
command grep -q 'validation-debt.md' <<< "$cc_out" \
  && ok "the CITING FILE is named too (validation-debt.md is in the corpus by measurement — the audit that missed it scoped to entries/ + NOTES.md)" \
  || bad "cite-check named an orphan but not the file citing it"

# pinning the orphan is the documented fix; it must actually clear the red.
git -C "$cc_repo" tag -a "iterlog-anchor/${dead_sha:0:8}" "$dead_sha" -m 'pinned by the arm' 2>/dev/null
"$CC" "$cc_repo" "$cc_root" >/dev/null 2>&1 \
  && ok "pinning the orphan with a tag clears it (the fix the tool prints actually works)" \
  || bad "cite-check still red after the orphan was pinned — the printed fix does not fix"

# a sweep that resolved NOTHING is not a clean verdict (the floor every other
# family in this suite carries).
cc_empty=$(sc_tmpdir)/empty
mkdir -p "$cc_empty/iteration-log/entries"
printf 'no shas here, just prose about deadbeef cafe\n' > "$cc_empty/iteration-log/entries/e.md"
"$CC" "$cc_repo" "$cc_empty" >/dev/null 2>&1 \
  && bad "known-bad: a corpus resolving ZERO commits read as a clean pass (vacuous sweep)" \
  || ok "known-bad: a sweep that resolves no commit at all refuses to call itself clean"
# …but a corpus that cites no commit at all is a fresh log, not a wrong repo:
# no hex token means nothing to resolve, and that is said rather than refused.
cc_fresh=$(sc_tmpdir)/fresh
mkdir -p "$cc_fresh/iteration-log/entries"
printf 'prose with no commit citation\n' > "$cc_fresh/iteration-log/entries/e.md"
cc_fout=$("$CC" "$cc_repo" "$cc_fresh" 2>&1) \
  && command grep -q 'cites no commit' <<< "$cc_fout" \
  && ok "a corpus with no commit citation reads clean BY NAME (a fresh log is not a wrong repository)" \
  || bad "a citation-free corpus was refused or passed silently: $cc_fout"

# gen-index.sh prints "N rows from M entries" about the file it just wrote — a
# tool counting its own output, which is the shape this tree keeps being bitten
# by. It counted with '^| [a-z]', matching the table HEADER too (id column: the
# literal word "id"), so N was over by one forever. The two numbers are only
# worth printing if they can DISAGREE, and the off-by-one masked the one
# disagreement that matters: a status outside the vocabulary renders no row.
gi=$(sc_tmpdir); mkdir -p "$gi/entries"
mk_entry "$gi" ga open
mk_entry "$gi" gb adopted
mk_entry "$gi" gc closed
gout=$("$GEN" "$gi")
[ "$gout" = "INDEX.md regenerated: 3 rows from 3 entries" ] \
  && ok "the generator's own summary counts its DATA rows, not its table header (3 entries -> '3 rows from 3 entries')" \
  || bad "generator summary miscounts its own output: $gout"
# the positive pin for that equality: it must be able to come out UNEQUAL, or
# the arm above passes on any file whose header happens to cancel a lost row.
mk_entry "$gi" gd retired
gout2=$("$GEN" "$gi")
[ "$gout2" = "INDEX.md regenerated: 3 rows from 4 entries" ] \
  && ok "an entry whose status is outside the vocabulary renders NO row and the summary SAYS so (3 rows from 4 entries)" \
  || bad "rows-vs-entries cannot disagree, so their equality proves nothing: $gout2"


check_done
