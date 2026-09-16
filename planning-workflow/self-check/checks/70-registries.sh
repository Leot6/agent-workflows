#!/usr/bin/env bash
# 70-registries — A§5.1's file map matches the disk, both directions, and the
# instrument→prompt map in protocol §5.1 resolves. A map that has drifted from
# the tree it describes is worse than no map: a cold instrument is onboarded
# from names, and a name that does not resolve stops the round.
#
# HONEST BOUNDARY: this matches FILENAMES, never content. A prompt file named
# `reviewer_redteam.md` that contains the architecture mandate passes every
# assertion here. The two lens classes read for that (protocol §7).
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/fixtures/lib.sh"

ARCH="$WF_ROOT/design/architecture.md"
PROTO="$WF_ROOT/runtime-docs/protocol.md"

# The §5.1 tree block: names appear inside it as bare stems.
block=$(awk '/^### 5\.1/{f=1} f&&/^### 5\.2/{exit} f' "$ARCH")
precond "the §5.1 tree block was found" test "$(printf '%s' "$block" | wc -l)" -ge 15

# --- prompts: disk vs map --------------------------------------------------
n=0
for f in "$WF_ROOT"/runtime-docs/prompts/*.md; do
  b=$(basename "$f" .md); n=$((n + 1))
  printf '%s' "$block" | command grep -qE "(^|[^a-z0-9_-])$b([^a-z0-9_-]|$)" \
    || bad "prompts/$b.md is on disk and absent from A§5.1's map"
done
precond "prompts were found on disk" test "$n" -ge 5
[ "$_FAIL" -eq 0 ] && ok "all $n prompt files appear in A§5.1's map"

# --- templates: disk vs map ------------------------------------------------
m=0
for f in "$WF_ROOT"/runtime-docs/templates/*.md; do
  b=$(basename "$f" .md); m=$((m + 1))
  printf '%s' "$block" | command grep -qE "(^|[^a-z0-9_-])$b([^a-z0-9_-]|$)" \
    || bad "templates/$b.md is on disk and absent from A§5.1's map"
done
precond "templates were found on disk" test "$m" -ge 10
[ "$_FAIL" -eq 0 ] && ok "all $m template files appear in A§5.1's map"

# --- map → disk: the direction that produces the stated harm ---------------
# "a cold instrument is onboarded from names, and a name that does not resolve
# stops the round" — that harm comes from a NAMED file being absent, which the
# disk sweeps above cannot see. Names are read out of the map's two comment
# segments and each must resolve.
# The segment ends at the next tree entry (a line drawing "──"), not at a named
# marker: adding an entry between two others must not silently extend a scan.
map_names() { # <start-marker> -> stems, one per line
  printf '%s' "$block" \
    | awk -v a="$1" '
        !f && index($0, a)  { f = 1; sub(/.*#/, ""); print; next }
        f && index($0, "──") { exit }
        f && index($0, "#")  { sub(/.*#/, ""); print; next }
        f { exit }' \
    | tr '·' '\n' | tr -d ' │├└─' | grep -E '^[a-z][a-z0-9_-]+$'
}
p=0
while IFS= read -r stem; do
  [ -n "$stem" ] || continue
  p=$((p + 1))
  [ -f "$WF_ROOT/runtime-docs/prompts/$stem.md" ] \
    || bad "A§5.1's map names prompts/$stem.md, which is not on disk"
done < <(map_names 'prompts/')
precond "the map named prompts" test "$p" -ge 5

t=0
while IFS= read -r stem; do
  [ -n "$stem" ] || continue
  t=$((t + 1))
  [ -f "$WF_ROOT/runtime-docs/templates/$stem.md" ] \
    || bad "A§5.1's map names templates/$stem.md, which is not on disk"
done < <(map_names 'templates/')
precond "the map named templates" test "$t" -ge 10

# The map also names files by full name (README.md, claims.md, rationale.md,
# protocol.md, architecture.md, iteration-log/). Those were unchecked, and
# they are the ones every instrument is onboarded with — {CLAIMS_PATH} is in
# six of the seven prompts, so a rename leaves the harness green while every
# spawn dangles.
d=0
while IFS= read -r name; do
  [ -n "$name" ] || continue
  d=$((d + 1))
  find "$WF_ROOT" -name "$name" -not -path '*/discussion/*' | grep -q . \
    || bad "A§5.1's map names $name, which is nowhere on disk"
done < <(printf '%s' "$block" | grep -oE '[a-z][a-z._-]*\.md' | sort -u)
precond "the map named whole files" test "$d" -ge 5
[ "$_FAIL" -eq 0 ] && ok "all $p mapped prompts, $t mapped templates and $d named files resolve on disk"

# --- instrument → prompt map (protocol §5.1) resolves on disk --------------
spawn=$(awk '/^## 5\./{f=1} f&&/^## 6\./{exit} f' "$PROTO")
k=0
while IFS= read -r p; do
  [ -n "$p" ] || continue
  k=$((k + 1))
  [ -f "$WF_ROOT/runtime-docs/prompts/$p.md" ] \
    || bad "protocol §5.1 maps an instrument to prompts/$p.md, which does not exist"
done < <(printf '%s' "$spawn" | grep -oE '`(reviewer_[a-z0-9_]+|baseline_verifier)`' | tr -d '`' | sort -u)
precond "the instrument map yielded entries" test "$k" -ge 5
[ "$_FAIL" -eq 0 ] && ok "all $k mapped instrument prompts exist on disk"

# --- every instrument has a backend binding, and every binding a declaration
# `runtime-scripts/` is optional as a whole (the returned-text delivery form
# needs no launcher), but a tree that ships one must ship it complete: a lens
# with no binding stalls the round it is dispatched in. spawn.sh resolves the
# map at launch and refuses a binding that names no declaration; this sweep is
# the between-rounds half — the binding that is absent outright, which a
# launch that never happens leaves no trace of.
MAP="$WF_ROOT/runtime-scripts/backends/lens-backends.map"
if [ -f "$MAP" ]; then
  b=0
  while IFS= read -r inst; do
    [ -n "$inst" ] || continue
    b=$((b + 1))
    be=$(sed -n "s/^$inst=//p" "$MAP" | head -1)
    be=${be%%[[:space:]]*}  # first word only — a map line may carry per-lens model/effort after the backend
    [ -n "$be" ] || { bad "instrument '$inst' is dispatched by protocol §5.1 and has no backend binding"; continue; }
    [ -f "$WF_ROOT/runtime-scripts/backends/$be.kv" ] \
      || bad "instrument '$inst' is bound to backend '$be', which has no declaration file"
  done < <(printf '%s' "$spawn" | grep -oE '`(arch|red|meta|exec|delta|closure|verifier)`' | tr -d '`' | sort -u)
  precond "instruments were found to bind" test "$b" -ge 5
  # Every declaration passes its model EXPLICITLY. Owner standing rule, and the
  # reason is not tidiness: a launch line without --model inherits whatever the
  # CLI defaults to that week, so the vehicle a findings header records is set
  # by someone else's release note. Measured: a wrapper CLI with no --model came
  # up on the author's own family, which is the one thing binding an instrument
  # to another CLI is for. `{model}`/`{effort}` satisfy this as placeholders —
  # the vehicle is then whatever model= or the map line says, still the tree's
  # own decision.
  for kv in "$WF_ROOT"/runtime-scripts/backends/*.kv; do
    [ -e "$kv" ] || continue
    command grep -q '^cmd\.launch=.*--model ' "$kv" \
      || bad "$(basename "$kv") launches without an explicit --model — the vehicle would be whatever the CLI defaults to"
    # A declaration's model=/effort= keys are its DEFAULTS: the map may
    # override them per lens but can never stand in for them, because a bare
    # backend dispatch (probe, ad-hoc) resolves from the keys alone. A kv
    # keeping the placeholder with no key refuses at launch — the one failure
    # a round would otherwise pay for; catch it here, where it costs nothing.
    command grep -q '^cmd\.launch=.*{model}' "$kv" && ! command grep -q '^model=' "$kv" \
      && bad "$(basename "$kv") launches with {model} but carries no model= default — a bare-backend dispatch of it refuses at launch"
    # Every {model} occurrence in the launch line is double-quoted. The line
    # is parsed by the pane's shell at launch, and a slug can carry a
    # bracketed tier suffix (e.g. model[1M]) that is a glob class
    # there: unquoted, zsh kills the pane on "no matches found" and bash
    # silently rewrites the slug where a matching filename exists (both
    # measured on tmux 3.0a). Blanket, not value-dependent — quoting a
    # glob-free slug changes nothing, and a future model= bump to a tiered
    # slug must not depend on someone remembering the launch line too.
    launchln=$(sed -n 's/^cmd\.launch=//p' "$kv" | head -1)
    case "$(printf '%s' "$launchln" | sed 's/"{model}"//g')" in
      *'{model}'*) bad "$(basename "$kv") carries an unquoted {model} in cmd.launch — a bracketed tier suffix would be globbed by the pane's shell (zsh kills the pane; bash rewrites the slug on a filename match)" ;;
    esac
    command grep -q '^cmd\.launch=.*{effort}' "$kv" && ! command grep -q '^effort=' "$kv" \
      && bad "$(basename "$kv") launches with {effort} but carries no effort= default — a bare-backend dispatch of it refuses at launch"
  done
  [ "$_FAIL" -eq 0 ] && ok "all $b dispatched instruments bind to a declared backend, every declaration self-sufficient in model/effort with {model} shell-quoted in cmd.launch"
fi

# --- A§5.3's ledger covers every entry-line form that exists ---------------
# The ledger's closing sentence makes its completeness load-bearing: a term in
# neither this file nor a ledger row "is a defect". Measured: the amend entry
# line was added to §7 and the ledger kept three rows for four forms, so the
# one form a maintainer would look up was the one missing. "spawn-message
# wording" is a wording row and not a line form; the `line wording` filter is
# what separates them, and both counts are printed on failure so a mismatch
# says which side moved.
forms=$(( $(command grep -c '^    read <ABS workflow>/runtime-docs/protocol.md —' "$PROTO") \
        + $(command grep -c '^read <ABS>/workflows/planning-workflow/runtime-docs/protocol.md —' "$WF_ROOT/README.md") ))
rows=$(awk '/^\| specification \| home \|/{f=1} f&&/^An undefined term/{exit} f' "$ARCH" | command grep -c 'line wording')
precond "entry-line forms were found" test "$forms" -ge 3
precond "ledger wording rows were found" test "$rows" -ge 3
[ "$forms" -eq "$rows" ] \
  && ok "A§5.3 carries a wording row for each of the $forms entry-line forms" \
  || bad "$forms entry-line forms exist (protocol §7 + README) and A§5.3 carries $rows wording rows — a form was added without its delegation row, or a row outlived its form"

# --- every template is a named artifact (A§4's artifact list) --------------
artifacts=$(awk '/^\*\*Artifacts\*\*/{f=1} f&&/^\*\*Canon\*\*/{exit} f' "$ARCH")
precond "A§4's artifact list was found" test "$(printf '%s' "$artifacts" | wc -c)" -ge 100
# The list names artifacts in prose and wraps across lines, so the mapping is
# declared here rather than guessed from the filename — a guess produced three
# false positives (close-out→"close out", rederivation→"re-derivation record").
artifact_phrase() {
  case $1 in
    baseline)              echo 'baseline card' ;;
    design-doc)            echo 'design doc' ;;
    grill-sheet)           echo 'grill' ;;      # "grill\nsheet" wraps
    rederivation)          echo 're-derivation record' ;;
    check-record)          echo 'check record' ;;
    owner-brief)           echo 'owner brief' ;;
    plan)                  echo 'plan' ;;
    findings)              echo 'findings' ;;
    disposition-ledger)    echo 'disposition ledger' ;;
    decision-log)          echo 'decision log' ;;
    close-out)             echo 'close-out' ;;
    convergence-checklist) echo 'convergence checklist' ;;
    *)                     echo '' ;;
  esac
}
flat=$(printf '%s' "$artifacts" | tr '\n' ' ')
for f in "$WF_ROOT"/runtime-docs/templates/*.md; do
  b=$(basename "$f" .md)
  probe=$(artifact_phrase "$b")
  if [ -z "$probe" ]; then
    bad "templates/$b.md is not in this check's artifact map — a new template needs its A§4 artifact named"
    continue
  fi
  printf '%s' "$flat" | command grep -qiF "$probe" \
    || bad "templates/$b.md maps to A§4 artifact '$probe', which A§4's list does not name"
done
[ "$_FAIL" -eq 0 ] && ok "every template corresponds to an A§4 artifact"

# --- the state region's own pointers resolve, both directions --------------
# A§5.1's map draws `iteration-log/` as ONE entry and cannot enumerate what is
# inside it: the formal region "points at files, never at state rows" (A§5.1),
# and the log's rows are exactly what grows — one `open/OBS-<n>.md` per family,
# one `owner-queue/WQ-<n>.md` per queued item. So the pointers that multiply
# were the ones no sweep read, while the named files above were covered from
# the start. Measured escape: INDEX.md cited `owner-queue/WQ-3.md` and the file
# on disk was `**WQ-3**.md` — the P-1 migration (7dadf50) split a state-file
# heading into a file and carried the heading's bold markers into the filename.
# What the maintainer owes the owner (A§13's owner-queue class) was unreachable
# from the only index that names it, for the whole life of the directory form.
# A§11 makes this log the durable home precisely because topic trees are not.
LOG="$WF_ROOT/iteration-log"
# `command grep` is a builtin and cannot be a find -exec: the first cut of this
# arm swept an empty set that way, and the precond below is what said so.
log_ptrs() {
  local f
  while IFS= read -r f; do
    command grep -ohE '(open|owner-queue)/[A-Za-z0-9_.*-]+\.md' "$f"
  done < <(find "$LOG" -name '*.md')
}
if [ -d "$LOG" ]; then
  # index → disk: the direction that produces the stated harm.
  c=0
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    c=$((c + 1))
    [ -f "$LOG/$rel" ] \
      || bad "the iteration log cites $rel, which is not on disk under iteration-log/"
  done < <(log_ptrs | sort -u)
  # A fresh log has no family files and so no pointers; that is named rather
  # than floored — the known-bad below still proves the resolver is live.
  [ "$c" -gt 0 ] || note "fresh state file: the log carries no open/ or owner-queue/ pointers yet"
  # disk → index: an entry file no row names is unreachable the other way, and
  # INDEX.md's own header makes reachability the invariant ("every ingested
  # observation id is reachable from this file").
  e=0
  for f in "$LOG"/open/*.md "$LOG"/owner-queue/*.md; do
    [ -e "$f" ] || continue
    e=$((e + 1))
    command grep -qF "$(basename "$f")" "$LOG/INDEX.md" \
      || bad "iteration-log/$(basename "$(dirname "$f")")/$(basename "$f") is on disk and named by no INDEX row"
  done
  [ "$e" -gt 0 ] || note "fresh state file: no open/ or owner-queue/ entry files yet"
  [ "$_FAIL" -eq 0 ] && ok "all $c log pointers resolve on disk, and all $e log entry files are named by an INDEX row"
fi

# --- a state-row id names exactly one mechanism ----------------------------
# A§11 prunes a closed entry to a "one-line index row (grep-fodder for anchor
# matching)": the line outlives the entry so that a later anchor match on the
# id still resolves to what it meant. Reuse the id and that is precisely what
# breaks -- the pruned line's only job is to answer `grep <id>`, and now two
# mechanisms answer. Measured escape: df0ef20 allocated VD-21 to the
# prescription shape while INDEX.md's closed list had carried VD-21 (delivery
# by marked file) since the first harvest; the collision sat in the state
# region with every other check green, because no check read ids as a registry.
IDX="$LOG/INDEX.md"
DEBT="$LOG/validation-debt.md"
# The detector, taking its two sets as arguments so the known-bad below can
# route a fabricated collision through this exact code path.
id_collisions() { # <closed-ids> <live-ids> -> prints shared ids, rc 1 if none
  comm -12 <(printf '%s\n' "$1" | sort -u) <(printf '%s\n' "$2" | sort -u) | command grep .
}
ids_disjoint() { ! id_collisions "$1" "$2" >/dev/null 2>&1; }
if [ -f "$IDX" ] && [ -f "$DEBT" ]; then
  # Closed/retired ids: the index list's own lines. Case-sensitive on purpose --
  # `obs-44` (a topic round's observation) and `OBS-17` (a family) are different
  # namespaces, and folding them would invent collisions.
  closed=$(awk '/^## Index/{f=1} f' "$IDX" | command grep -oE '^- (OBS|VD|WQ)-[0-9]+' | sed 's/^- //')
  # Live ids: the INDEX's two tables, plus the debt ledger's own rows.
  live=$( { command grep -oE '^\| (OBS|WQ)-[0-9]+' "$IDX"; command grep -oE '^\| VD-[0-9]+' "$DEBT"; } | sed 's/^| //')
  [ -n "$closed" ] || note "fresh state file: the index list carries no closed ids yet"
  precond "live row ids were found" test "$(printf '%s\n' "$live" | command grep -c .)" -ge 5
  hits=$(id_collisions "$closed" "$live" | tr '\n' ' ')
  [ -z "$hits" ] \
    || bad "id(s) naming both a live row and a closed index entry: ${hits}-- a later anchor match on one resolves to two mechanisms (A§11)"
  # Within the ledger, too: the same id twice is the same ambiguity.
  dups=$(command grep -oE '^\| VD-[0-9]+' "$DEBT" | sed 's/^| //' | sort | uniq -d | tr '\n' ' ')
  [ -z "$dups" ] || bad "the debt ledger carries a duplicate row id: ${dups}"
  [ "$_FAIL" -eq 0 ] && ok "all $(printf '%s\n' "$live" | command grep -c .) live row ids are disjoint from the $(printf '%s\n' "$closed" | command grep -c .) closed index ids"
fi

# Non-vacuity: route a name the map does not carry through the check's OWN
# membership test against the real §5.1 block.
probe_map_has() { printf '%s' "$block" | command grep -qE "(^|[^a-z0-9_-])$1([^a-z0-9_-]|$)"; }
known_bad "a template absent from the map is caught" probe_map_has "reviewer_nonexistent"
probe_log_ptr() { [ -f "$LOG/$1" ]; }
known_bad "a log pointer that resolves to nothing is caught" probe_log_ptr "open/OBS-nonexistent.md"
known_bad "an id that is both a live row and a closed index entry is caught" \
  ids_disjoint "VD-9" "VD-9"

check_done
