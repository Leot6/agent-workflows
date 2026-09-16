#!/usr/bin/env bash
# drill/mock-cli.sh — a scripted fake CLI run INSIDE a real tmux pane by the
# ferry, via the drill's `test` backend declaration (family pty_tmux). It
# paints the declared signatures (MOCK_WORKING / ❯ / …), reads the composed
# prompt exactly as a real CLI session would (bootstrap positional arg; warm
# re-activation lines through the injected pty), derives every path it needs
# from the prompt itself (record.sh line in the volatile header), and executes
# the scenario script in <workspace>/.mock/plan:
#     <stage>=<action>          default for every visit of the stage
#     <stage>:<k>=<action>      visit k (1-based) overrides the default
# actions: ready|done|concur|drafted|built|conforms|reslice (write artifacts,
# then record.sh emit with that verdict) · halt (emit --halt class_u) ·
# probe / probe-quiet / probe-nogate (onboarding-probe fixtures: gate blocked /
# gate allowed at turn end / gate never ran) ·
# direct (append a handoff record directly, NO artifacts — the first-miss owed-park fixture) ·
# die (exit: pane death) · stall (paint ❯ and wait).
# Unplanned stages default to die (bounded, deterministic).

set -u
export LC_ALL=C
WS=${1:?mock-cli: workspace arg missing}
BOOT=${2:?mock-cli: bootstrap arg missing}
MOCKD="$WS/.mock"
# Probe layout: the onboarding probe spawns us with the SCRATCH workspace
# (<topic-ws>/.runtime/probe/ws-<backend>), but the drill writes the scenario
# plan at the topic level — fall back three levels up so one plan file drives
# both normal stages and probe sessions.
if [ ! -f "$MOCKD/plan" ] && [ -f "$WS/../../../.mock/plan" ]; then
  MOCKD=$(cd "$WS/../../../.mock" && pwd)
fi
mkdir -p "$MOCKD"
LOG="$MOCKD/log"

logline() { echo "[$(date +%s)] $*" >> "$LOG"; }

visit_no() { # stage -> incremented visit counter
  local f="$MOCKD/visits.$1" n
  n=$(cat "$f" 2>/dev/null || echo 0)
  n=$((n + 1))
  printf '%s\n' "$n" > "$f"
  printf '%s\n' "$n"
}

plan_action() { # stage visit
  local a
  a=$(sed -n "s/^$1:$2=//p" "$MOCKD/plan" 2>/dev/null | head -1)
  [ -n "$a" ] || a=$(sed -n "s/^$1=//p" "$MOCKD/plan" 2>/dev/null | head -1)
  printf '%s\n' "${a:-die}"
}

claims_block() {
  # Extracted LIVE from the (shadow) spec template — the mock writes exactly
  # the heading a template-following agent writes; divergence is impossible.
  local tpl="$ROOT/../runtime-docs/templates/spec.md" hdr rows
  hdr=$(grep -m1 -E '^#+[[:space:]]+([0-9]+\.[[:space:]]+)?[Cc]laims([[:space:]]+table)?[[:space:]]*$' "$tpl")
  rows=$(awk -v h="$hdr" '$0==h{on=1; next} on && /^\|/{print; c++; if(c==2) exit}' "$tpl")
  if [ -z "$hdr" ] || [ -z "$rows" ]; then
    logline "MOCK BROKEN: claims extraction failed from $tpl"
    echo "MOCK BROKEN: claims section extraction failed"
    return 1
  fi
  printf '\n%s\n\n%s\n' "$hdr" "$rows"
  printf '| note | mock fixture artifact | - | - | - | - |\n'
}
plain_art() { { echo "# mock $2"; echo; echo "body."; } > "$1"; }
claims_art() { { echo "# mock $2"; echo; echo "body."; claims_block; } > "$1"; }
# The pane-side twin of fixtures/lib.sh's spec_reorder, local for the same
# self-containment reason as the claims_block above (this script runs inside a
# tmux pane and sources nothing); kept text-identical to its twin so the two
# cannot disagree about what a reordered spec is.
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

review_art() { # path stage slice round — matches templates/review.md structure
  cat > "$1" <<EOF
# review

- stage: $2 · slice $3 · round $4

## 1. provenance

mock provenance, round $4.

## 2. findings

none.

## 3. absorption

mock: round $4 — nothing to absorb.

## 4. claims

| type | claim | anchor | echo | range | command |
|---|---|---|---|---|---|
| note | mock review | - | - | - | - |

## 5. non-coverage

mock.

## 6. verdict

in the record.
EOF
}

split_index() { # the index this split declares: SPLIT_INDEX (a scenario's explicit
  # re-derivation) > `split.slices=` in the plan > one code-bound slice
  local sl=${SPLIT_INDEX:-}
  [ -n "$sl" ] || sl=$(sed -n 's/^split\.slices=//p' "$MOCKD/plan" 2>/dev/null | head -1)
  printf '%s\n' "${sl:-01:low:code:one}"
}

write_artifacts() { # stage slice round
  local s=$1 sl=$2 r=$3
  local d="$WS/slices/$sl"   # separate statement: `local a=$1 b=$a` expands args before assigning
  mkdir -p "$d"
  case "$s" in
    plan-validate) claims_art "$WS/slices/00/validation_note.md" "validation note" ;;
    split)
      # one `## slice NN` section per declared id (split emit asserts it)
      { echo "# mock charters"; echo; echo "body."
        split_index | tr ';' '\n' | cut -d: -f1 \
          | while IFS= read -r id; do printf '\n## slice %s\n\nmock charter.\n' "$id"; done
      } > "$WS/charters.md" ;;
    split-check)   review_art "$WS/slices/00/splitcheck.$r.md" split-check "$sl" "$r" ;;
    spec)
      # Headings extracted LIVE from templates/spec.md, the same way the halt
      # doc's are below and for the same reason: the spec is structure-gated at
      # emit, so a hardcoded mock would couple every drill to the template and
      # break on the next template edit. Generating them means a template change
      # can never break a drill, and the mock writes exactly what a
      # template-following agent writes — divergence is impossible.
      local spectpl="$ROOT/../runtime-docs/templates/spec.md"
      { grep -m1 -E '^# ' "$spectpl"
        echo
        echo "- topic: mock · slice: $sl"
        grep -E '^## ' "$spectpl" | while IFS= read -r h; do
          case "$h" in
            *commit-units*)
              printf '\n%s\n\n| id | subject (project convention) | risk note | relocation-only |\n|---|---|---|---|\n| cu-1 | feat: mock unit one | none | no |\n' "$h" ;;
            *claims*) : ;;   # claims_block writes this heading itself, below
            *) printf '\n%s\n\nmock.\n' "$h" ;;
          esac
        done
        claims_block
      } > "$d/spec.md"
      # The claims heading is written by claims_block, so it lands AFTER the
      # sections the template puts before it and BEFORE nothing — which would
      # put it out of template order. Re-emit in template order instead.
      spec_reorder "$d/spec.md" "$spectpl" "mock."
      ;;
    precheck)      review_art "$d/precheck.$r.md" precheck "$sl" "$r" ;;
    postcheck)     review_art "$d/postcheck.$r.md" postcheck "$sl" "$r" ;;
    impl|fix)
      local repo sha
      # the slice's BOUND checkout, taken from the prompt's volatile header —
      # the same channel a real author session has (the pane carries no cwd)
      repo=${BINDING_REPO:-$(sed -n 's/^repo=//p' "$WS/project.kv" | head -1)}
      echo "mock work $(date +%s%N)" >> "$repo/mockwork.txt"
      git -C "$repo" add -A >> "$LOG" 2>&1
      git -C "$repo" commit -qm "feat: mock landed unit one" >> "$LOG" 2>&1
      sha=$(git -C "$repo" rev-parse HEAD)
      "$RECORD" progress "$WS" --cu 1 --sha "$sha" >> "$LOG" 2>&1
      logline "progress cu-1 sha=$sha rc=$?"
      # the dispatch as sent, the way a real author writes it BEFORE dispatching
      { echo "dispatch: cu-1 · model=mock · effort=mock"; echo; echo "land unit one per the spec."; } > "$d/dispatch.1.md"
      plain_art "$d/conformance.md" conformance ;;
    turnover)      plain_art "$d/turnover.md" turnover ;;
    close-out)     plain_art "$WS/closeout.md" closeout ;;
  esac
}

emit_record() { # stage nonce verdict [slices-spec]
  local args=(--stage "$1" --nonce "$2" --verdict "$3" --confidence HIGH) sl
  case "$1" in
    split-check|precheck|postcheck)
      args+=(--findings-substantive 0 --findings-wording 0 --findings-new 0 --findings-repeat 0) ;;
    *) args+=(--refine-rounds 1) ;;
  esac
  if [ "$1" = "split" ]; then
    args+=(--slices "${4:-$(split_index)}")
  fi
  "$RECORD" emit "$WS" "${args[@]}" >> "$LOG" 2>&1
  logline "emit stage=$1 verdict=$3 rc=$?"
}

process() { # prompt_path
  local p=$1 stage slice round nonce visit action
  echo "MOCK_WORKING"
  nonce=$(sed -n 's/^nonce=//p' "$p" | head -1)
  stage=$(sed -n 's/^stage=\([a-z-]*\) .*/\1/p' "$p" | head -1)
  slice=$(sed -n 's/^stage=.* slice=\([0-9]*\) .*/\1/p' "$p" | head -1)
  round=$(sed -n 's/^stage=.* round=\([0-9]*\) .*/\1/p' "$p" | head -1)
  RECORD=$(awk '/record\.sh emit/{print $1; exit}' "$p")
  ROOT=${RECORD%/session/record.sh}
  BINDING_REPO=$(sed -n 's/^binding: kind=[a-z]* repo=\([^ ]*\).*/\1/p' "$p" | head -1)
  visit=$(visit_no "$stage")
  action=$(plan_action "$stage" "$visit")
  case "$action" in
    *-nohb) logline "heartbeat SKIPPED (bad-direction probe fixture)" ;;
    *) "$ROOT/session/heartbeat.sh" "$WS" >> "$LOG" 2>&1 ;;
  esac
  logline "process stage=$stage slice=$slice round=$round visit=$visit action=$action prompt=$p"
  case "$action" in
    die)
      logline "dying deliberately"
      exit 1 ;;
    scribble)
      # Novel-then-die: an owed-artifact delta each attempt keeps the
      # fingerprint novel, so death exhausts the ATTEMPT BUDGET (park dead),
      # never the loop detector.
      mkdir -p "$WS/slices/00"
      date +%s%N >> "$WS/slices/00/validation_note.md"
      logline "scribbled owed artifact; dying"
      exit 1 ;;
    apply)
      # Re-slice application: split re-derives the index, minting the merged
      # slice and omitting the superseded one.
      SPLIT_INDEX="02:low:code:merged" write_artifacts split "$slice" "$round"
      emit_record split "$nonce" done "02:low:code:merged" ;;
    probe|probe-nohb)
      # Onboarding-probe fixture: behave like a real harness session — the
      # stop-gate block line is painted (a real CLI surfaces the hook's
      # stderr in the transcript), the owed artifact lands, the record emits.
      echo "turn end BLOCKED: no handoff record for the active attempt (stage=$stage)."
      claims_art "$WS/slices/00/validation_note.md" "probe validation note"
      emit_record "$stage" "$nonce" ready ;;
    probe-quiet)
      # The WELL-BEHAVED agent, which is what two independent live
      # claude/sonnet sessions actually did: read the prompt, see both designed
      # failure points, write the owed artifact FIRST, emit once, then end. No
      # record-less turn end is ever attempted, so the gate never blocks and no
      # `turn end BLOCKED` string ever reaches the pane.
      # The mock runs no hooks, so it calls the gate itself — the same script a
      # real CLI's Stop hook invokes, at the same moment (turn end, after the
      # record). Legacy no-name form: the mock does not know its session name.
      claims_art "$WS/slices/00/validation_note.md" "probe validation note"
      emit_record "$stage" "$nonce" ready
      "$RECORD" stop-gate "$WS" >> "$LOG" 2>&1
      logline "stop-gate ran at turn end rc=$?" ;;
    probe-nogate)
      # Bad direction for the widened signal: the harness wiring is BROKEN —
      # the Stop hook never runs at all. Artifact and record land, the pane
      # stays quiet, and nothing ever rules. `stop_gate` must still be a miss,
      # or the widening would have made the item unfailable.
      claims_art "$WS/slices/00/validation_note.md" "probe validation note"
      emit_record "$stage" "$nonce" ready ;;
    quota)
      # Backend out of quota: the CLI answers nothing, paints its exhaustion
      # line into the TRANSCRIPT and sits at an empty composer — the live shape,
      # which is why the classifier reads quota as a refinement of idle. Nothing
      # about the declaration is disproved, and that distinction is the point of
      # the fixture: pre-fix this window burned the whole probe.timeout and then
      # blamed the declaration. Painted here, so the trailing repaint is skipped.
      printf '\x1b[2J\x1b[HMOCK_QUOTA allowance used up, resets 19:45 Asia/Shanghai\n\xe2\x9d\xaf\n'
      no_repaint=1
      logline "painted quota exhaustion above an empty composer; idling" ;;
    overload)
      # Backend UP and refusing (the 529 class): the CLI's own retry ladder has
      # exhausted, so it paints the error banner into the TRANSCRIPT and sits at
      # an empty composer — byte-for-byte the same SHAPE as the quota case above
      # and a different fact, which is exactly why the two needed separate
      # classes. Unlike quota there is no reset time to forward, and the
      # refusal must say so rather than let an operator wait out a clock that
      # nothing publishes.
      printf '\x1b[2J\x1b[HMOCK_OVERLOAD API Error: 529 Overloaded. This is a server-side issue, usually temporary\n\xe2\x9d\xaf\n'
      no_repaint=1
      logline "painted a 529 overload banner above an empty composer; idling" ;;
    stall|stall[0-9]*s)
      # A bounded stall: sleep N seconds (plain stall = 45), then fall through
      # to the visit's normal completion (write artifacts, emit the DEFAULT
      # action for the stage). The kill-and-relaunch drill
      # (drill-recovery.sh) needs an attempt that is genuinely LIVE — running,
      # heartbeating, not yet emitted — long enough to be killed inside, and
      # that still COMPLETES afterwards: an unbounded stall made the
      # re-attached wait immortal (the ferry waited on an attempt whose mock
      # would never emit; timeout SIGTERMed it into operator_stop — measured).
      local secs
      secs=$(printf '%s' "$action" | sed 's/^stall//; s/s$//')
      case "$secs" in ''|*[!0-9]*) secs=45 ;; esac
      logline "stalling ${secs}s before completing"
      sleep "$secs"
      # the default action for the stage, from the plan's <stage>= line
      local dflt
      dflt=$(sed -n "s/^$stage=//p" "$MOCKD/plan" 2>/dev/null | head -1)
      case "$dflt" in ''|stall*) dflt=built ;; esac
      write_artifacts "$stage" "$slice" "$round"
      emit_record "$stage" "$nonce" "$dflt" ;;
    stall)
      : ;;
    halt)
      # the question set the door asks for: slices/<nn>/halt.<n>.md, n = this
      # slice's class_u halt count + 1, headings per templates/halt.md
      local n
      n=$("$ROOT/lib/state.sh" get "$WS" handoff 2>/dev/null \
        | grep -E "(^| )slice=$slice( |$)" | grep -cE '(^| )verdict=HALT_class_u( |$)' || true)
      mkdir -p "$WS/slices/$slice"
      { echo "# halt — Class U"; echo; echo "- stage: $stage · slice $slice · question set $((n + 1))"; echo
        grep -E '^## ' "$ROOT/../runtime-docs/templates/halt.md" \
          | while IFS= read -r h; do
              case "$h" in
                *claims*) printf '%s\n\n| type | claim | anchor | echo | range | command |\n|---|---|---|---|---|---|\n| note | mock halt, no load-bearing number | - | - | - | - |\n\n' "$h" ;;
                *) printf '%s\n\nmock.\n\n' "$h" ;;
              esac
            done
      } > "$WS/slices/$slice/halt.$((n + 1)).md"
      "$RECORD" emit "$WS" --stage "$stage" --nonce "$nonce" --halt class_u \
        --detail "MOCK-Q1: which option?; MOCK-Q2: second question (batched)" \
        --confidence HIGH >> "$LOG" 2>&1
      logline "halt emit rc=$?" ;;
    direct)
      # The first-miss owed-park fixture: a DONE-shaped record lands with NO artifacts written —
      # bypassing record.sh's owed refusal the way a store rollback / hand-write
      # would. The ferry's advance check must park owed_miss on the FIRST miss.
      "$ROOT/lib/state.sh" append "$WS" handoff --writer session --line \
        "v=1 t=$(date +%s) slice=$slice stage=$stage attempt=1 round=$round nonce=$nonce verdict=ready confidence=HIGH" \
        >> "$LOG" 2>&1
      logline "direct handoff append rc=$?" ;;
    *)
      write_artifacts "$stage" "$slice" "$round"
      emit_record "$stage" "$nonce" "$action" ;;
  esac
  # Clear then paint ❯ alone. NB: whether the REAL CLI's rendered idle frame
  # clears its working banner is UNMEASURED (a live byte-stream capture shows
  # no full-screen clear before the idle composer) — the live probe's
  # awaiting_input phase arbitrates this against the real TUI. Without the
  # clear here, whole-frame working-signature matching would classify the
  # idle mock as working forever.
  [ "${no_repaint:-0}" -eq 1 ] \
    || printf '\x1b[2J\x1b[H\xe2\x9d\xaf\n'   # ❯ — empty composer: awaiting_input / warm-injectable
}

case "$BOOT" in
  *"Read and execute "*) process "${BOOT##*execute }" ;;
  *) logline "unrecognized bootstrap: $BOOT"; exit 1 ;;
esac

while IFS= read -r line; do
  case "$line" in
    *"Read and execute "*) process "${line##*execute }" ;;
    continue)
      logline "nudge received, repainting"
      [ -n "${ROOT:-}" ] && "$ROOT/session/heartbeat.sh" "$WS" >> "$LOG" 2>&1
      printf '\x1b[2J\x1b[H\xe2\x9d\xaf\n' ;;
    /exit) logline "exit requested"; exit 0 ;;
    *) logline "ignored input: $line" ;;
  esac
done
logline "stdin closed; exiting"
