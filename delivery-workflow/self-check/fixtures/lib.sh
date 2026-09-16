#!/usr/bin/env bash
# self-check/fixtures/lib.sh — shared fixture builders + assertion helpers.
# Sourced by every check and by the drill. Never touches the live tree or
# plans/: every fixture lives under a mktemp dir beneath ${TMPDIR:-/tmp},
# registered for cleanup on EXIT.

export LC_ALL=C

_SC_LIB_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SC_ROOT=$(cd "$_SC_LIB_DIR/.." && pwd)                    # self-check/
WF_ROOT=$(cd "$SC_ROOT/.." && pwd)                        # delivery-workflow/
RS="$WF_ROOT/runtime-scripts"
# Pin the workflow root for lib copies sourced from temp dirs (headless ferry).
# The drill overrides these to its shadow root before running the shadow ferry.
export CONFIG_WORKFLOW_ROOT="$WF_ROOT"
export OWED_WORKFLOW_ROOT="$WF_ROOT"

# ---------------------------------------------------------------- results ----
_SC_N=0; _SC_FAILS=0
ok()   { _SC_N=$((_SC_N + 1)); echo "  ok: $*"; }
bad()  { _SC_N=$((_SC_N + 1)); _SC_FAILS=$((_SC_FAILS + 1)); echo "  FAIL: $*"; }
note() { echo "  note: $*"; }
# Fixture precondition — a broken fixture must never read as a pass.
precond() { # description condition-command...
  local d=$1; shift
  if "$@"; then ok "precondition: $d"
  else bad "FIXTURE PRECONDITION BROKEN: $d — the check below would be vacuous"; fi
}
check_done() {
  echo "  ($_SC_N assertions, $_SC_FAILS failed)"
  # A check that asserted NOTHING is a pass about nothing — the per-check
  # form of the runner's collection floor (an early exit, or a refactor that
  # moved every assertion behind an untaken branch, must read as a red, not
  # as the safest check in the suite). _SC_SETUP_N marks where SHARED setup
  # assertions end (drill/lib.sh's two): the floor is on the check's OWN
  # arms — a drill whose body is entirely dead still rides the setup's
  # preconds, measured on a neutered drill-budget before this seam existed.
  # The two sweep-style checks (90-provenance-tags, 95-shell-idioms) do not
  # call this and carry their own per-pattern non-vacuity fixtures instead.
  if [ $(( _SC_N - ${_SC_SETUP_N:-0} )) -le 0 ]; then
    echo "  FAIL: the check asserted nothing of its own (beyond ${_SC_SETUP_N:-0} setup assertion(s)) — an empty assertion set is a verdict about nothing (early exit? every arm behind an untaken branch?)"
    return 1
  fi
  [ "$_SC_FAILS" -eq 0 ]
}
# assert_rc expected_rc description -- command...
assert_rc() {
  local want=$1 d=$2; shift 3
  local out rc
  out=$("$@" 2>&1); rc=$?
  if [ "$rc" -eq "$want" ]; then ok "$d (rc=$rc)"
  else bad "$d — want rc=$want got rc=$rc; output: $(printf '%s' "$out" | head -3 | tr '\n' ' ')"; fi
  SC_OUT=$out
}
# assert_out_has needle description  (checks $SC_OUT from the last assert_rc)
# Deliberately NOT a pipeline. `printf '%s\n' "$SC_OUT" | command grep -qF` returns
# 141 under pipefail whenever grep matches EARLY and printf is still writing: grep
# exits at the first hit, printf takes SIGPIPE, pipefail surfaces the producer's
# status. The caller then reads 141 as "no match", so a needle that IS present
# reads as absent — and the failure REQUIRES the needle, which is why the bad
# message prints it inside its own `got:` text. Measured on this box, 200 trials
# per size: 0/200 at 64 KiB (printf's whole output fits the pipe buffer and it is
# gone before grep can matter), then a RACY band of 1-2/200 from just above 64 KiB
# to 128 KiB, then 200/200 from 136-144 KiB up. The floor is the pipe buffer, not
# 128 KiB -- a haystack of a few hundred KiB fails every time, one of 80 KiB fails
# about once in a hundred runs, which is the harder shape to ever diagnose. A
# herestring is not a pipeline, so pipefail has nothing to combine; it appends the
# same trailing newline printf did. Do not restore the pipe.
#
# The rc is SPLIT and the failure evidence is BYTE-LEVEL, and both exist because
# of what nine investigations could not settle. The old failure line printed the
# haystack through `tr`, which is a RENDERING: an ANSI escape, a non-breaking
# space or different column padding renders identically to the needle, so
# "the needle is plainly present in its own got: line" was never a claim about
# bytes. `55-monitor`'s arm guarding this renderer against escape bytes in a
# non-TTY capture is in the same file as one of the firings. `cat -A` is what
# tells the two apart on the spot.
# So a tenth firing classifies itself: rc>=2 means the match did not complete and
# the class is settled; rc=1 means grep RAN and genuinely did not match, the
# needle was never there in bytes, and the defect is UPSTREAM in whatever
# produced SC_OUT.
# The `*)` wording follows `97-iterlog`'s ruling on the same split — "GNU grep
# returns 2 on error EVEN WITH matches found ... claiming 'never ran' there would
# be this arm's own defect turned on itself" — so it says the match did not
# COMPLETE, never that grep did not run.
assert_out_has() {
  local rc
  command grep -qF -- "$1" <<< "$SC_OUT"; rc=$?
  case $rc in
    0) ok "$2" ;;
    1) bad "$2 — output lacks '$1' (grep RAN and matched nothing, rc=1). needle bytes: $(printf '%s' "$1" | cat -A) | haystack head: $(printf '%s' "$SC_OUT" | head -c 300 | cat -A)" ;;
    *) bad "$2 — the match over '$1' did not complete (rc=$rc); this is not a clean verdict" ;;
  esac
}

# The negative form, and it is a primitive rather than a `! grep` at the call
# site for one reason: an absence verdict has THREE outcomes, not two. rc 1 is
# the pass (the match ran and found nothing); rc >1 is a match that did not
# complete, which must never be read as absence. Written because two arms in
# `46-convergence` were spelled `assert_out_lacks` before this existed: they
# were command-not-found, counted nothing, and the check still read green —
# an unfloored arm, in the commit that was adding the arms.
assert_out_lacks() {
  local rc
  command grep -qF -- "$1" <<< "$SC_OUT"; rc=$?
  case $rc in
    1) ok "$2" ;;
    0) bad "$2 — output still carries '$1'. haystack head: $(printf '%s' "$SC_OUT" | head -c 300 | cat -A)" ;;
    *) bad "$2 — the match over '$1' did not complete (rc=$rc); absence is NOT established" ;;
  esac
}

# ------------------------------------------------------------------- temp ----
# One session root per check process; every sc_tmpdir lives inside it, so dirs
# created from command substitutions (subshells) are still removed by the
# owning process's EXIT trap — per-dir registration would lose them.
if [ -z "${SC_SESSION_TMP:-}" ]; then
  SC_SESSION_TMP=$(mktemp -d "${TMPDIR:-/tmp}/dwsc.XXXXXX") \
    || { echo "mktemp failed" >&2; exit 1; }
  export SC_SESSION_TMP
  _SC_OWN_ROOT=1
else
  _SC_OWN_ROOT=0
fi
sc_tmpdir() { # -> new temp dir under the session root
  mktemp -d "$SC_SESSION_TMP/t.XXXXXX"
}
sc_cleanup() {
  [ "${_SC_OWN_ROOT:-0}" -eq 1 ] && [[ "$SC_SESSION_TMP" == */dwsc.* ]] \
    && rm -rf "$SC_SESSION_TMP"
  return 0
}
trap sc_cleanup EXIT

# Hermeticity against the OPERATOR config layer (lib/config.sh
# _CONFIG_USER_FILE): config.sh resolves ${XDG_CONFIG_HOME:-~/.config}/
# delivery-workflow/config.kv between defaults and topic.kv. Pointed at this
# session's tmp root, that file does not exist, so every fixture resolves
# exactly what it writes — the suite stays green the day the operator arms a
# real transport, and no assertion ever depends on the machine's config.
# Sourced by every check AND by drill/lib.sh, so the shadow ferry is covered
# too (its launches would otherwise fire the operator's real channel).
# Placed after SC_SESSION_TMP exists; config.sh is never sourced before this
# file completes, and _CONFIG_USER_FILE is computed at ITS source time.
export XDG_CONFIG_HOME="$SC_SESSION_TMP/xdg"
mkdir -p "$XDG_CONFIG_HOME" 2>/dev/null || true

# Shared-setup baseline for check_done's own-arms floor: everything asserted
# from here to the end of THIS file's body is setup (none today — the count
# is taken so a future setup assertion joins the baseline by existing).
_SC_SETUP_N=$_SC_N

# --------------------------------------------------------------- builders ----
mk_repo() { # dir -> prints "repo_dir<TAB>branch"
  local d=$1
  mkdir -p "$d"
  git -C "$d" init -q
  git -C "$d" config user.email sc@example.invalid
  git -C "$d" config user.name selfcheck
  echo base > "$d/base.txt"
  git -C "$d" add base.txt
  git -C "$d" commit -qm "chore: fixture base commit"
  printf '%s\t%s\n' "$d" "$(git -C "$d" symbolic-ref --short HEAD)"
}

# A doc-repo fixture. Its branch is deliberately NOT the code fixture's default
# name: with both named the same, a binding that resolved the WRONG branch
# would still find a same-named branch in the other checkout, and no assertion
# could tell the two apart (measured — that vacuity hid the doc.branch dispatch
# from the whole suite).
mk_doc_repo() { # dir -> prints "repo_dir<TAB>branch"
  local d=$1
  mk_repo "$d" > /dev/null
  git -C "$d" branch -m docs-main
  printf '%s\t%s\n' "$d" docs-main
}

mk_ws() { # base_dir topic_name repo_dir branch -> prints workspace path
  local base=$1 topic=$2 repo=$3 branch=$4 ws
  ws="$base/topics/$topic/delivery"
  mkdir -p "$ws/config" "$ws/slices" "$ws/.runtime/state" "$ws/.runtime/tmp" \
           "$ws/.runtime/logs" "$ws/.runtime/prompts"
  cat > "$base/topics/$topic/plan.md" <<'EOF'
# fixture plan
one slice of mock work.
EOF
  cat > "$ws/project.kv" <<EOF
repo=$repo
branch=$branch
commit.subject_regex=^(feat|fix|refactor|chore|docs): [a-z]
EOF
  printf '%s\n' "$ws"
}

claims_block() { # a minimal claims table that PASSES gates_claims
  # Heading + column header are extracted LIVE from the shipped spec template,
  # so the fixture exercises exactly what a template-following agent writes —
  # a hand-copied heading here is the fixture-vs-template divergence class
  # (the very defect that let the template's own heading fail the gate).
  local tpl="$WF_ROOT/runtime-docs/templates/spec.md" hdr rows
  hdr=$(command grep -m1 -E '^#+[[:space:]]+([0-9]+\.[[:space:]]+)?[Cc]laims([[:space:]]+table)?[[:space:]]*$' "$tpl")
  rows=$(awk -v h="$hdr" '$0==h{on=1; next} on && /^\|/{print; c++; if(c==2) exit}' "$tpl")
  if [ -z "$hdr" ] || [ "$(printf '%s\n' "$rows" | command grep -c .)" -ne 2 ]; then
    echo "FIXTURE BROKEN: cannot extract the claims section from $tpl" >&2
    echo "FIXTURE BROKEN: claims section extraction failed"   # poisons the artifact loudly
    return 1
  fi
  printf '%s\n\n%s\n' "$hdr" "$rows"
  printf '| note | fixture artifact; no load-bearing claims | - | - | - | - |\n'
}

mk_review() { # path stage slice round — a review matching templates/review.md
  mkdir -p "$(dirname "$1")"
  cat > "$1" <<EOF
# review

- stage: $2 · slice $3 · round $4

## 1. provenance

fixture provenance: baseline fixture, freshness self-derived, round $4, compact form.

## 2. findings

none.

## 3. absorption

fixture: round $4 — nothing to absorb.

## 4. claims

| type | claim | anchor | echo | range | command |
|---|---|---|---|---|---|
| note | fixture review; no load-bearing claims | - | - | - | - |

## 5. non-coverage

fixture: everything (mechanical fixture artifact).

## 6. verdict

fixture verdict; counts travel in the record.
EOF
}

mk_dispatch() { # ws slice [n]  — the implementer prompt as sent (owed by impl)
  local n=${3:-1}
  mkdir -p "$1/slices/$2"
  { echo "dispatch: cu-$n · model=fixture · effort=fixture"; echo
    echo "land commit-unit cu-$n per slices/$2/spec.md; report only."; } > "$1/slices/$2/dispatch.$n.md"
}

mk_artifact() { # path title [claims]  — non-empty file; optional claims table
  mkdir -p "$(dirname "$1")"
  { echo "# $2"; echo; echo "fixture body."; [ "${3:-}" = "claims" ] && claims_block; } > "$1"
}

mk_charter() { # path ids...  — a charter with one `## slice NN` section per id
  local path=$1; shift
  mkdir -p "$(dirname "$path")"
  { echo "# charters"; echo; echo "fixture preamble."
    local id; for id in "$@"; do printf '\n## slice %s\n\nfixture charter for slice %s.\n' "$id" "$id"; done
  } > "$path"
}

mk_halt() { # ws slice n — a Class U question set matching templates/halt.md
  local ws=$1 slice=$2 n=$3 tpl="$WF_ROOT/runtime-docs/templates/halt.md"
  mkdir -p "$ws/slices/$slice"
  { echo "# halt — Class U"; echo; echo "- stage: fixture · slice $slice · question set $n"; echo
    command grep -E '^## ' "$tpl" | while IFS= read -r h; do
      case "$h" in
        *claims*) printf '%s\n\n| type | claim | anchor | echo | range | command |\n|---|---|---|---|---|---|\n| note | fixture halt, no load-bearing number | - | - | - | - |\n\n' "$h" ;;
        *) printf '%s\n\nfixture.\n\n' "$h" ;;
      esac
    done
  } > "$ws/slices/$slice/halt.$n.md"
}

# Re-emit a generated spec in the TEMPLATE's heading order: the claims table
# is appended by its own builder and the structure gate checks ORDER, so a
# section landing last must be re-seated where the template puts it. awk, not
# python: every fixture that builds a spec rides this, and python3 was the
# suite's one unguarded interpreter — a python3-less box FAILED here instead
# of skipping. The 1-6-hash heading test is a length check on the match,
# never an ERE interval (mawk parses none). Faithful to the python it
# replaced: duplicate headings merge; a section the template names but the
# doc lacks gets the filler; a section the doc carries but the template does
# not is dropped (the doc's own H1 among them — order's first heading is
# re-emitted from the template, where the parameterised title lives).
spec_reorder() { # doc template filler — writes the doc in place
  local doc=$1 tpl=$2 filler=$3 tmp
  tmp=$(mktemp "${TMPDIR:-/tmp}/specreorder.XXXXXX")
  awk -v doc="$doc" -v tpl="$tpl" -v filler="$filler" '
    function ishead(l) { return match(l, /^#+ /) && RLENGTH - 1 <= 6 }
    BEGIN {
      n = 0
      while ((getline line < tpl) > 0) { sub(/\r$/, "", line); if (ishead(line)) order[++n] = line }
      close(tpl)
      cur = ""; nh = 0
      while ((getline line < doc) > 0) {
        sub(/\r$/, "", line)
        if (ishead(line)) { cur = line; if (!(cur in has)) { has[cur] = 1; nb[cur] = 0 }; continue }
        if (cur == "") head[++nh] = line; else blk[cur, ++nb[cur]] = line
      }
      close(doc)
      print order[1]
      for (i = 1; i <= nh; i++) print head[i]
      for (k = 2; k <= n; k++) {
        print order[k]
        if (order[k] in has) for (j = 1; j <= nb[order[k]]; j++) print blk[order[k], j]
        else print "\n" filler "\n"
      }
    }' < /dev/null > "$tmp"
  mv "$tmp" "$doc"
}

mk_spec() { # ws slice n_cus  — spec with cu table + passing claims table
  # Every heading is extracted LIVE from the shipped spec template, the way
  # claims_block already extracts its own. The spec is structure-gated at emit,
  # so a hardcoded fixture would couple every check that emits a spec to the
  # template's exact section list and red on the next template edit; generating
  # them means a template change can never break a fixture, and the fixture
  # writes exactly what a template-following author writes.
  local ws=$1 slice=$2 n=${3:-1} i tpl="$WF_ROOT/runtime-docs/templates/spec.md"
  mkdir -p "$ws/slices/$slice"
  { command grep -m1 -E '^# ' "$tpl"
    echo
    echo "- topic: fixture · slice: $slice"
    command grep -E '^## ' "$tpl" | while IFS= read -r h; do
      case "$h" in
        *commit-units*)
          printf '\n%s\n\n| id | subject (project convention) | risk note | relocation-only |\n|---|---|---|---|\n' "$h"
          for i in $(seq 1 "$n"); do printf '| cu-%s | feat: fixture unit %s | none | no |\n' "$i" "$i"; done ;;
        *claims*) : ;;   # claims_block writes this heading itself
        *) printf '\n%s\n\nfixture.\n' "$h" ;;
      esac
    done
  } > "$ws/slices/$slice/spec.md"
  # claims_block emits its own heading, so append it and then re-order the whole
  # document into the template's heading order — the gate checks ORDER, and a
  # section appended last would sit after the ones the template puts after it.
  claims_block >> "$ws/slices/$slice/spec.md"
  spec_reorder "$ws/slices/$slice/spec.md" "$tpl" "fixture."
}

# A workspace populated with every artifact the templates/manifests reference.
mk_full_ws() { # base topic repo branch -> ws (via stdout)
  local ws
  ws=$(mk_ws "$@")
  mk_artifact "$ws/slices/00/validation_note.md" "validation note"
  mk_charter "$ws/charters.md" 01
  mk_artifact "$ws/slices/00/splitcheck.1.md" "split-check review" claims
  mk_spec "$ws" 01 1
  mk_artifact "$ws/slices/01/precheck.1.md" "precheck round 1" claims
  mk_artifact "$ws/slices/01/conformance.md" "conformance"
  mk_artifact "$ws/slices/01/postcheck.1.md" "postcheck round 1" claims
  mk_artifact "$ws/slices/01/turnover.md" "turnover"
  mk_artifact "$ws/closeout.md" "closeout"
  ( . "$RS/lib/state.sh"
    printf 'id=01 status=active risk=low title=one rederive=0\n' \
      | state_set "$ws" slices ferry
    state_append "$ws" ledger ferry "v=1 t=$(date +%s) event=fixture"
    state_append "$ws" progress session \
      "v=1 t=$(date +%s) slice=01 cu=1 sha=fixture0 subject=fixture" ) > /dev/null
  printf '%s\n' "$ws"
}

# Write stage + sessions surfaces as the ferry would for a running attempt.
# The row carries the stage's TRUE role (the ferry writes role=stage_role at
# every spawn/reuse; emit's role binding reads it) — a fixture row must model
# that invariant or every emit would refuse on the fixture's own dishonesty.
activate_stage() { # ws stage slice round nonce [attempt] [name]
  local ws=$1 stage=$2 slice=$3 round=$4 nonce=$5 attempt=${6:-1} name=${7:-fixture-$2}
  local role
  role=$( . "$RS/lib/owed.sh"; owed_stage_role "$stage" 2>/dev/null ) || role=author
  ( . "$RS/lib/state.sh"
    state_put "$ws" stage ferry "slice=$slice" "stage=$stage" "round=$round" \
      "attempt=$attempt" "state=running" "nonce=$nonce" "spawn_t=$(date +%s)" > /dev/null
    { state_get "$ws" sessions 2>/dev/null || true
      printf 'role=%s name=%s pane_pid=0 pane_start=0 server_pid=0 server_start=0 socket=none nonce=%s mode=cold t=%s\n' \
        "$role" "$name" "$nonce" "$(date +%s)"
    } | command grep -v '^$' | state_set "$ws" sessions ferry )
}

# Headless ferry: a copy with the trailing `main` call stripped, sourceable for
# unit tests of its pure functions (stage_next_for, decide_mode, resume_halt_gate).
mk_headless_ferry() { # -> prints path of sourceable copy
  local d last
  d=$(sc_tmpdir)
  ln -sn "$RS/lib" "$d/lib"          # -n: never create INSIDE an existing link target
  ln -sn "$RS/backends" "$d/backends"
  # the spawn-side fact guard resolves probe.sh through FERRY_DIR (--verify),
  # so a headless copy without it would refuse for the wrong reason
  ln -s "$RS/probe.sh" "$d/probe.sh"
  last=$(tail -1 "$RS/ferry.sh")
  if [ "$last" != "main" ]; then
    echo "FIXTURE BROKEN: ferry.sh no longer ends with a bare 'main' line (got '$last')" >&2
    return 1
  fi
  sed '$d' "$RS/ferry.sh" > "$d/ferry-headless.sh"
  printf '%s\n' "$d/ferry-headless.sh"
}

# Headless launch: the same trick for launch.sh, whose tail is a verb dispatch
# rather than a call — sourceable for unit tests of its pure preflight halves
# (probe_reachable_set), which must be exercisable without spending a probe
# session or detaching a watchdog.
mk_headless_launch() { # -> prints path of sourceable copy
  local d last
  d=$(sc_tmpdir)
  ln -sn "$RS/lib" "$d/lib"
  ln -sn "$RS/backends" "$d/backends"
  last=$(tail -1 "$RS/launch.sh")
  if [ "$last" != "esac" ]; then
    echo "FIXTURE BROKEN: launch.sh no longer ends with the verb-dispatch 'esac' (got '$last')" >&2
    return 1
  fi
  sed '/^case "\${1:-}" in$/,$d' "$RS/launch.sh" > "$d/launch-headless.sh"
  if command grep -q '^case "\${1:-}" in$' "$d/launch-headless.sh"; then
    echo "FIXTURE BROKEN: the verb dispatch survived the strip" >&2
    return 1
  fi
  printf '%s\n' "$d/launch-headless.sh"
}

# Corrupt-surface writer: tamper the body under an unchanged header, so the
# checksum can no longer match (the fixture for fault ≠ absent).
corrupt_surface() { # ws surface
  local f="$1/.runtime/state/$2"
  [ -f "$f" ] || { echo "corrupt_surface: $f absent" >&2; return 1; }
  echo "TAMPERED-BY-SELF-CHECK" >> "$f"
}
