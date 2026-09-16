#!/usr/bin/env bash
# session/record.sh — the ONLY way a stage completes (state-and-liveness.md §2).
#   emit      — the agent's final action: schema + nonce + verdict validation,
#               owed-set refusal (same lib/owed.sh list the ferry checks),
#               emit-time mechanical gates, then the handoff record.
#   stop-gate — the profile Stop hook: blocks turn end (exit 2 + message)
#               until the CALLING session has delivered its own record — a
#               turn can never finish silently, and a session that already
#               emitted owes nothing (the caller travels as its session NAME,
#               baked per-session by the ferry; the name resolves to the live
#               nonce at gate time, so warm reuse never stales the identity).
#   progress  — impl/fix commit-unit ledger append (cu → SHA as it lands).
#   decision / learn / observe — the session's other write paths (cmd_* below).
# The mechanical halves of emit (owed set, gates, fix and leak evidence, the
# Class U question set) live in session/emit_checks.sh, sourced here.
# Writer class: session.
#
# Record-field requirements derived from stages.tsv (the table, not code):
# rows whose ROLE_CARD is cards/author.md owe refine.rounds; rows whose ROLE_CARD is
# cards/reviewer.md owe findings.substantive (the severity-trend predicate's
# mechanical input). The split row additionally owes --slices (the machine
# index the ferry writes to the slices surface on advance).

set -uo pipefail
export LC_ALL=C
_RECORD_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
. "$_RECORD_DIR/../lib/state.sh"
. "$_RECORD_DIR/../lib/config.sh"
. "$_RECORD_DIR/../lib/owed.sh"
. "$_RECORD_DIR/../lib/gates.sh"
. "$_RECORD_DIR/../lib/rulings.sh"
. "$_RECORD_DIR/emit_checks.sh"

refuse() { echo "refuse: $*" >&2; exit 2; }
fault() { echo "FAULT: $*" >&2; exit 3; }

_stage_role() { # stage -> author|reviewer (the one derivation: lib/owed.sh)
  owed_stage_role "$1" || exit 2
}

_stage_verdicts() { # stage -> pipe-separated closed vocabulary
  owed_stage_row "$1" | awk -F'\t' '{print $5}'
}

_active() { # workspace key -> value from stage surface (rc propagates)
  state_field "$1" stage "$2"
}

cmd_emit() {
  local ws=$1; shift
  local stage="" nonce="" verdict="" confidence="" rrounds="" rterm=""
  local fsub="" fword="0" fnew="" frep="" slices="" detail="" halt="" rack=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --stage) stage=$2; shift 2 ;;
      --nonce) nonce=$2; shift 2 ;;
      --verdict) verdict=$2; shift 2 ;;
      --confidence) confidence=$2; shift 2 ;;
      --ruling-ack) rack=$2; shift 2 ;;
      --refine-rounds) rrounds=$2; shift 2 ;;
      --refine-terminated-on) rterm=$2; shift 2 ;;
      --refine-last-severity) refuse "emit: --refine-last-severity is not accepted — the field was write-only (declared value set, no fill rule, no reader) and is retired. Report what the round found in the refine log, which the reviewer audits." ;;
      --findings-substantive) fsub=$2; shift 2 ;;
      --findings-wording) fword=$2; shift 2 ;;
      --findings-new) fnew=$2; shift 2 ;;
      --findings-repeat) frep=$2; shift 2 ;;
      --slices) slices=$2; shift 2 ;;
      --halt) halt=$2; shift 2 ;;
      --detail) detail=$2; shift 2 ;;
      *) refuse "emit: unknown arg '$1'" ;;
    esac
  done
  # Universal halt path (design/state-and-liveness.md §2): any stage may suspend
  # on class_u/blocked in place of a flow verdict; the table's HALT_* spellings
  # remain the common-case routes.
  if [ -n "$halt" ]; then
    case "$halt" in class_u|blocked) : ;;
      *) refuse "--halt must be class_u or blocked" ;;
    esac
    [ -n "$detail" ] || refuse "--halt owes --detail (the batched questions / the obstacle)"
    verdict="HALT_$halt"
  fi
  [ -n "$stage" ] && [ -n "$nonce" ] && [ -n "$verdict" ] && [ -n "$confidence" ] \
    || refuse "emit needs --stage --nonce --verdict --confidence (or --halt ... --detail ...)"
  # not_ready is the class_u mechanism's common-case spelling (protocol §4):
  # the ferry's park takes its owner-page message from the record's detail
  # field, so an empty detail ships an empty page — same mandate as --halt.
  [ "$verdict" = "not_ready" ] && [ -z "$detail" ] \
    && refuse "not_ready owes --detail (the batched questions for the owner — the park message is built from it)"

  local body rc
  body=$(state_get "$ws" stage 2>/dev/null); rc=$?
  [ $rc -eq 3 ] && fault "stage surface corrupt — do not retry; the ferry will park store_fault"
  [ $rc -eq 1 ] && refuse "no active stage (stage surface absent) — emit is only valid inside a ferry-spawned stage session"
  local a_stage a_slice a_state a_nonce a_attempt a_round
  a_stage=$(printf '%s\n' "$body" | awk -F= '$1=="stage"{v=$2} END{print v}')
  a_slice=$(printf '%s\n' "$body" | awk -F= '$1=="slice"{v=$2} END{print v}')
  a_state=$(printf '%s\n' "$body" | awk -F= '$1=="state"{v=$2} END{print v}')
  a_nonce=$(printf '%s\n' "$body" | awk -F= '$1=="nonce"{v=$2} END{print v}')
  a_attempt=$(printf '%s\n' "$body" | awk -F= '$1=="attempt"{v=$2} END{print v}')
  a_round=$(printf '%s\n' "$body" | awk -F= '$1=="round"{v=$2} END{print v}')
  [ "$a_state" = "running" ] || refuse "active attempt state is '$a_state', not running — nothing to complete"
  [ "$stage" = "$a_stage" ] || refuse "stage mismatch: you claim '$stage', the active stage is '$a_stage'"

  # nonce: fresh per attempt, injected in the volatile prompt header,
  # authenticated against the sessions surface, single-use.
  local sess
  sess=$(state_get "$ws" sessions 2>/dev/null); rc=$?
  [ $rc -eq 3 ] && fault "sessions surface corrupt"
  printf '%s\n' "$sess" | command grep -qE "(^| )nonce=$nonce( |$)" \
    || refuse "nonce '$nonce' not in the sessions surface — use the nonce from your prompt's volatile header"
  # Role binding — the nonce fences ORDERING, not authorization. The sessions
  # row carrying the presented nonce is the attempt that minted it; its role
  # must equal the stage's declared role, so a session pointed at the wrong
  # stage (the pre-fix stop-gate block message did exactly that) is refused by
  # the real mismatch instead of a stale-nonce message that reads as 'go find
  # the active nonce'. This binds record.sh callers; direct store writes are
  # outside the trust boundary (state.sh: writer classes are a bug barrier,
  # not a security barrier) — see self-check/validation-debt.md.
  local role emitter_role
  role=$(_stage_role "$stage")
  emitter_role=$(printf '%s\n' "$sess" | command grep -E "(^| )nonce=$nonce( |$)" | tail -1 \
    | awk '{for(i=1;i<=NF;i++) if($i ~ /^role=/){sub(/^role=/,"",$i); print $i; exit}}')
  [ "$emitter_role" = "$role" ] \
    || refuse "session role '${emitter_role:-unknown}' does not match stage '$stage' role '$role' — a stage's record is emitted only by its own session; emitting for another stage impersonates that session and consumes its single-use nonce"
  [ "$nonce" = "$a_nonce" ] || refuse "nonce '$nonce' is not the active attempt's nonce"
  local hoff
  hoff=$(state_get "$ws" handoff 2>/dev/null); rc=$?
  [ $rc -eq 3 ] && fault "handoff surface corrupt"
  printf '%s\n' "$hoff" | command grep -qE "(^| )nonce=$nonce( |$)" \
    && refuse "nonce '$nonce' already used — a nonce is single-use; a new attempt gets a new one"

  # Mid-flight door (protocol §6): a ruling addressed to this slice (or topic-
  # scoped) with t later than the attempt's spawn was not in its manifest, and
  # "rides every later manifest" would otherwise mean the next stage boundary —
  # a whole round for a two-line edit. The emit is refused until it names
  # EXACTLY that set by token (<slice>.<n>); the record then carries the tokens.
  # The halt path is inside the door: asking the owner what they just answered
  # is the costliest shape. lib/rulings.sh is the selector compose.sh shares.
  local a_spawn_t unseen want acked
  a_spawn_t=$(printf '%s\n' "$body" | awk -F= '$1=="spawn_t"{v=$2} END{print v}')
  unseen=$(rulings_addressed "$ws" "$a_slice" "$stage" "${a_spawn_t:-0}"); rc=$?
  [ $rc -eq 3 ] && fault "rulings surface corrupt"
  want=$(printf '%s\n' "$unseen" | rulings_tokens | awk 'NF{print $1}' | sort -u | paste -sd, -)
  acked=$(printf '%s' "$rack" | tr ',' '\n' | command grep . | sort -u | paste -sd, -)
  if [ "$want" != "$acked" ]; then
    [ -n "$want" ] || refuse "--ruling-ack $rack names a ruling, but no ruling landed after this attempt spawned (t=$a_spawn_t) — drop the flag"
    refuse "ruling(s) landed while this attempt ran and were NOT in your manifest:$(printf '%s\n' "$unseen" | rulings_tokens | awk 'NF{printf " [%s] %s", $1, $2}') — read each, apply it (or say in your artifact why not), then emit again with --ruling-ack $want"
  fi

  if [ -z "$halt" ]; then
    local vocab
    vocab=$(_stage_verdicts "$stage") || exit 2
    printf '|%s|' "$vocab" | command grep -qF "|$verdict|" \
      || refuse "verdict '$verdict' not in stage '$stage' closed vocabulary ($vocab)"
  fi
  case "$confidence" in HIGH|MED|LOW) : ;;
    *) refuse "confidence '$confidence' not in HIGH|MED|LOW" ;;
  esac

  if [ -n "$halt" ]; then
    : # a halted stage owes neither refine/findings fields nor its artifacts
  elif [ "$role" = "author" ]; then
    printf '%s\n' "$rrounds" | command grep -qE '^[0-9]+$' \
      || refuse "author stage '$stage' owes --refine-rounds <int> (the schema-forced self-loop, review-and-slices.md §4.2)"
    local rmax
    # fallback mirrors defaults.kv (config fault here must not block an emit —
    # the gate still bounds; drift risk accepted and noted)
    rmax=$(config_get refine.max_rounds --topic-dir "$ws" 2>/dev/null) || rmax=3
    [ "$rrounds" -ge 1 ] && [ "$rrounds" -le "$rmax" ] \
      || refuse "refine.rounds=$rrounds outside 1..refine.max_rounds=$rmax — the self-loop ran a bounded number of real rounds or the record lies (per-round log audited by the reviewer, review-standards.md §7 P9)"
    # Which criterion released the artifact (review-standards §3): below the cap
    # only clean is possible, so it is derived; AT the cap the author must say.
    case "$rterm" in clean|bound) : ;;
      "") [ "$rrounds" -lt "$rmax" ] && rterm=clean \
            || refuse "refine.rounds=$rrounds is AT refine.max_rounds=$rmax, so the record must say what released it: --refine-terminated-on clean (the last round found nothing substantive) | bound (the cap did, with substantive findings still open — legal, and the reviewer reads the artifact as unconverged)" ;;
      *) refuse "--refine-terminated-on '$rterm' not in clean|bound" ;;
    esac
    [ "$rterm" = clean ] || [ "$rrounds" -eq "$rmax" ] \
      || refuse "refine.terminated_on=bound at refine.rounds=$rrounds below refine.max_rounds=$rmax — the cap cannot have bound a loop that stopped before it; release by a clean round or run the rounds"
  else
    printf '%s\n' "$fsub" | command grep -qE '^[0-9]+$' \
      || refuse "reviewer stage '$stage' owes --findings-substantive <int> (severity-trend input)"
    printf '%s\n' "$fword" | command grep -qE '^[0-9]+$' \
      || refuse "--findings-wording must be an int"
    # The new/repeat split (review-standards §1, §10): a repeat continues a
    # previous round's finding — the one thing the predicate can act on. Owed
    # from round 2 when there is something to split; a clean round and round 1
    # derive new = all unless stated, and what is stated must hold.
    if [ -n "$fnew" ] || [ -n "$frep" ]; then
      printf '%s\n' "$fnew" | command grep -qE '^[0-9]+$' && printf '%s\n' "$frep" | command grep -qE '^[0-9]+$' \
        || refuse "--findings-new and --findings-repeat are a pair of ints (new + repeat = substantive)"
      [ $((fnew + frep)) -eq "$fsub" ] \
        || refuse "findings-new ($fnew) + findings-repeat ($frep) must equal findings-substantive ($fsub) — the split partitions the count, it does not add to it"
      [ "${a_round:-1}" -ge 2 ] || [ "$frep" -eq 0 ] \
        || refuse "round $a_round has no previous round to repeat: --findings-repeat must be 0"
    elif [ "$fsub" -gt 0 ] && [ "${a_round:-1}" -ge 2 ]; then
      refuse "reviewer stage '$stage' round $a_round owes --findings-new <int> --findings-repeat <int> (new + repeat = $fsub; a repeat continues a previous round's finding — rebutted, absorbed only in part, or re-introduced; everything else is new. review-standards.md §1)"
    else
      fnew=$fsub; frep=0
    fi
  fi
  local skip="handoff"
  if [ "$stage" = "split" ] && [ -z "$halt" ]; then
    [ -n "$slices" ] || refuse "split owes --slices 'id:risk:repo:title;...' — the machine index (slices surface) is built from it"
    # One admissibility rule for the declared index (grammar, one-id-one-slice,
    # immutable bindings) — the same derivation the ferry's ingest asks. Refused
    # HERE means the author fixes it in session; nothing parks.
    local bad brc
    bad=$(slices_admissible "$ws" "$slices"); brc=$?
    [ $brc -eq 3 ] && fault "the slices surface is unreadable — the standing index cannot be compared"
    [ $brc -eq 1 ] && refuse "--slices is not an admissible index: $(printf '%s' "$bad" | tr '\n' '; ')"
    skip="handoff,slices_index"
  fi

  if [ "$halt" = "class_u" ]; then
    # not a $(...): refuse must exit THIS shell, not a substitution's
    _emit_class_u_doc "$ws" "$a_slice"
    detail="question set: $_EMIT_CLASS_U_DOC — $detail"
  fi
  if [ -z "$halt" ]; then
    # a halted stage owes no artifacts (the halt IS the outcome); everything
    # below is the non-halt path, split into its two mechanical halves
    _emit_owed_and_gates "$ws" "$stage" "$a_slice" "$a_round" "$skip" \
      "$(printf '%s' "$slices" | tr ';' '\n' | cut -d: -f1 | tr '\n' ' ')"
    _emit_fix_evidence "$ws" "$stage" "$a_slice" "$a_round"
    _emit_leak_evidence "$ws" "$stage" "$a_slice" "$a_round" "$fsub"
  fi

  detail=$(printf '%s' "$detail" | tr '\n\t' '  ')
  local rec="v=1 t=$(date +%s) slice=$a_slice stage=$stage attempt=$a_attempt round=$a_round nonce=$nonce verdict=$verdict confidence=$confidence"
  [ -n "$rrounds" ] && rec="$rec refine.rounds=$rrounds refine.terminated_on=$rterm"
  [ -n "$fsub" ] && rec="$rec findings.substantive=$fsub findings.wording=$fword findings.substantive.new=$fnew findings.substantive.repeat=$frep"
  [ -n "$slices" ] && rec="$rec slices=$(printf '%s' "$slices" | tr ' ' '_')"
  [ -n "$want" ] && rec="$rec rulings.midflight=$want"
  [ -n "$detail" ] && rec="$rec detail=$detail"
  state_append "$ws" handoff session "$rec" || fault "handoff append failed"
  echo "recorded: $stage slice=$a_slice verdict=$verdict (the ferry advances from here)"
}

cmd_stop_gate() {
  local ws=$1 sname=${2:-} body rc a_state a_nonce a_stage
  # An unrendered template placeholder must not read as an identity: it would
  # resolve to "no such session" and open the gate for the ACTIVE session —
  # the silent finish the gate exists to prevent. Treat it as no name (the
  # legacy global check).
  [ "$sname" = "{SESSION_NAME}" ] && sname=""
  body=$(state_get "$ws" stage 2>/dev/null); rc=$?
  [ $rc -eq 1 ] && exit 0            # no active attempt — not a stage session
  [ $rc -eq 3 ] && { echo "store FAULT in stage surface — the ferry parks store_fault; turn may end" >&2; exit 0; }
  a_state=$(printf '%s\n' "$body" | awk -F= '$1=="state"{v=$2} END{print v}')
  [ "$a_state" = "running" ] || exit 0
  a_nonce=$(printf '%s\n' "$body" | awk -F= '$1=="nonce"{v=$2} END{print v}')
  a_stage=$(printf '%s\n' "$body" | awk -F= '$1=="stage"{v=$2} END{print v}')
  # Gate scope is the CALLING session (state-and-liveness.md §2: the nonce is
  # a fencing token — a session that delivered its own record owes nothing,
  # whichever attempt is active NOW). The caller's stable identity is its
  # session NAME (warm reuse changes the nonce but keeps the name), resolved
  # to its current nonce from the sessions surface AT GATE TIME. Without a
  # name (legacy profile) the gate enforces globally, as before.
  if [ -n "$sname" ]; then
    local sess srow my_nonce
    sess=$(state_get "$ws" sessions 2>/dev/null); rc=$?
    [ $rc -eq 3 ] && { echo "store FAULT in sessions surface — the ferry parks store_fault; turn may end" >&2; exit 0; }
    srow=$(printf '%s\n' "$sess" | command grep -E "(^| )name=$sname( |$)" | tail -1 || true)
    if [ -n "$srow" ]; then
      my_nonce=$(printf '%s\n' "$srow" | awk '{for(i=1;i<=NF;i++) if($i ~ /^nonce=/){sub(/^nonce=/,"",$i); print $i; exit}}')
      # A row holding a DIFFERENT nonce is a superseded/held session: its own
      # attempt was consumed or replaced; it owes nothing and must end freely.
      # An unreadable nonce falls through to the global check (fail closed).
      [ -n "$my_nonce" ] && [ "$my_nonce" != "$a_nonce" ] && exit 0
    else
      exit 0   # torn down / displaced: no live attempt is this session's
    fi
  fi
  if state_get "$ws" handoff 2>/dev/null | command grep -qE "(^| )nonce=$a_nonce( |$)"; then
    # The gate RULED, and on this path the ruling was otherwise invisible: it
    # opened, and nothing anywhere said it had run. That cost the onboarding
    # probe its `stop_gate` signal, which was written as a BEHAVIOURAL test —
    # the prompt asks the agent to end a turn record-less and probe.sh greps
    # the pane for `turn end BLOCKED`. An agent that reads the prompt, writes
    # its owed artifact first and emits before ending never trips it; measured
    # twice on two independent sessions, and the probe then refused a correct
    # backend with "declarations are promises, the probe makes them facts".
    # A row here lets the probe assert the property that actually matters —
    # the gate ran and ruled correctly — on both orderings.
    # Only THIS allow is a ruling about the attempt. The exits above (no
    # active stage, a stage not running, a row holding another nonce, a name
    # absent from the surface) are the gate declining jurisdiction, and they
    # stay silent: an attestation there would let the probe pass on a gate
    # that opened for the wrong reason.
    # The verb is `stop_gate_allow`, deliberately not a suffix of
    # `stop_gate_block`: the wait loop counts blocks by that literal
    # (liveness.stop_gate_blocks_max), and a session that ends cleanly every
    # turn must not accumulate toward its own wedge.
    state_audit "$ws" session "stop_gate_allow nonce=$a_nonce stage=$a_stage — turn end permitted, the attempt's record is present"
    exit 0
  fi
  # The gate blocking is normal once; blocking again and again is the session
  # reporting that it cannot finish — and the CLI's own block cap can override
  # the hook and force the turn to end anyway, leaving a pane that will never
  # speak again under a stage surface that still reads running (measured: 9
  # blocks, then a forced end, then hours of nothing). The ferry cannot see a
  # hook's exit code, so the count goes where it can: this attempt's own audit
  # trail, which the wait loop reads (liveness.stop_gate_blocks_max).
  state_audit "$ws" session "stop_gate_block nonce=$a_nonce stage=$a_stage — turn end refused, no record for the active attempt"
  {
    echo "turn end BLOCKED: no handoff record for the active attempt (stage=$a_stage)."
    echo "Your final action must be:"
    echo "  $_RECORD_DIR/record.sh emit $ws --stage $a_stage --nonce <nonce from your prompt header> --verdict <...> --confidence HIGH|MED|LOW [role fields]"
    echo "It will refuse while owed artifacts are missing and list exactly what is missing."
  } >&2
  exit 2
}

cmd_progress() {
  local ws=$1; shift
  local cu="" sha="" subject=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --cu) cu=$2; shift 2 ;;
      --sha) sha=$2; shift 2 ;;
      --subject) refuse "progress: --subject is not accepted — the subject is DERIVED from the sha at append time. The commit is the single source for what it says it did; a second, hand-written copy of the same fact is what produced a row with an empty subject and rows in two sha forms in one ledger." ;;
      *) refuse "progress: unknown arg '$1'" ;;
    esac
  done
  [ -n "$cu" ] && [ -n "$sha" ] || refuse "progress needs --cu <N> --sha <sha>"
  local repo slice pstage pround msgout
  # The active slice is read BEFORE the SHA is judged: this wall is the first
  # thing a doc-bound impl session meets, and judging its commit against the
  # code repo would refuse every landed doc unit long before owed sees it.
  slice=$(_active "$ws" slice 2>/dev/null || echo "")
  [ -n "$slice" ] || refuse "no active stage — progress records belong to a live impl/fix attempt"
  pstage=$(_active "$ws" stage 2>/dev/null || echo "")
  case "$pstage" in impl|fix) : ;;
    *) refuse "progress records belong to impl/fix (active stage is '$pstage') — the ledger is landing evidence, not general bookkeeping" ;;
  esac
  repo=$(binding_repo "$ws" "$slice") || exit 2
  # The verify already had to resolve the object; keep what it resolved TO. That
  # is the ledger's canonical form — one sha shape per surface, so a reader can
  # match rows against git output with one comparison. Measured: one topic's
  # seven rows carried two forms (40-char and 8-char) from three sessions,
  # because the form was whatever the author happened to type.
  local canon
  canon=$(git -C "$repo" rev-parse -q --verify "$sha^{commit}" 2>/dev/null) \
    || refuse "sha '$sha' is not a commit in $repo (slice $slice's bound checkout) — record only landed SHAs"
  sha=$canon
  # The registration wall is the FIRST door for the MESSAGE half of the commit
  # convention — the same derivation the emit gate uses (_gates_message_fails).
  # It is asked HERE because here the commit is usually still the tip, where the
  # whole convention costs one amend; at emit it is buried under every unit
  # landed since and rewording it means rewriting the branch above it.
  #
  # Which is exactly why the door BLOCKS only while the fix is local. A door may
  # ask only what the session can fix on the spot (config-and-adapters.md §3):
  # the diff cap stays at emit because its remedy is a rewrite of landed history
  # with no local move that clears it — and a buried message is that same shape.
  # Walling the ledger there would strand the record of a commit that really did
  # land, and the author who cannot pass the wall simply does not register,
  # which is worse than the defect: emit then reports a MISSING cu record and
  # hides the real cause. So a buried failure is recorded and named loudly, and
  # the emit gate — the attestation authority — still refuses the stage.
  msgout=$(_gates_message_fails "$ws" "$sha") || exit 2
  if [ -n "$msgout" ]; then
    local msgtext head_sha
    msgtext=$(printf '%s\n' "$msgout" | awk -F'\t' 'NF>1 {print "  " substr($0, index($0, "\t") + 1)}')
    head_sha=$(git -C "$repo" rev-parse -q --verify HEAD 2>/dev/null || echo none)
    if [ "$(git -C "$repo" rev-parse -q --verify "$sha^{commit}" 2>/dev/null)" = "$head_sha" ]; then
      refuse "commit $sha does not meet the project's commit-message convention — caught at registration, where it is still the tip and the fix is one amend:
$msgtext
Naming the unit is THIS record's job, not the message's."
    fi
    echo "WARNING: commit $sha does not meet the project's commit-message convention, and it is no longer the tip — so this is recorded rather than refused (the ledger's job is what LANDED):" >&2
    printf '%s\n' "$msgtext" >&2
    echo "The emit gate will refuse this stage until the message is fixed, and by now that means rewriting the branch above it — report it as an erratum for the author." >&2
  fi
  pround=$(_active "$ws" round 2>/dev/null || echo "")
  # DERIVED, never argued. git is the single source for what a commit says it
  # did; the row already carries `cu=` for the workflow's own label. An optional
  # argument is how one of seven rows shipped with an empty subject under a
  # prompt byte-identical to the six that did not.
  subject=$(git -C "$repo" log -1 --format=%s "$sha" 2>/dev/null | tr '\n\t' '  ')
  # Append-only means never destroy history, not write-once per key: a unit
  # re-registered at a new sha SUPERSEDES its earlier row and the row says so
  # (review-standards §11). Present on every row, empty on a first registration.
  local prev_sha
  prev_sha=$(state_get "$ws" progress 2>/dev/null \
    | awk -v s="$slice" -v c="$cu" '
        $0 ~ ("(^| )slice=" s "( |$)") && $0 ~ ("(^| )cu=" c "( |$)") {
          for(i=1;i<=NF;i++) if($i ~ /^sha=/){sub(/^sha=/,"",$i); v=$i}
        } END{print v}')
  [ "$prev_sha" != "$sha" ] \
    || refuse "cu $cu is already registered at $sha for slice $slice — a duplicate row is not a landing; to replace the unit register its NEW sha (the row will carry supersedes=$sha)"
  state_append "$ws" progress session \
    "v=1 t=$(date +%s) slice=$slice stage=$pstage round=${pround:-1} cu=$cu sha=$sha supersedes=${prev_sha:-} subject=$subject" \
    || fault "progress append failed"
  [ -z "$prev_sha" ] || echo "progress: cu.$cu re-registered — this row SUPERSEDES ${prev_sha:0:8} (the earlier registration is history; only this sha is in scope)"
  # AFTER the append, never before: the warning above is advice about a decision,
  # but this line is the durable record of an override, and an audit surface that
  # claims a write which then faulted is the one artifact nobody can correct
  # later. The stderr warning fires either way; only the durable claim waits.
  [ -n "$msgout" ] && state_audit "$ws" session \
    "progress recorded over a message-convention failure (sha=$sha cu=$cu slice=$slice) — buried past the tip, so the fix is no longer local; emit still refuses"
  echo "progress recorded: slice=$slice cu.$cu -> $sha (stage=$pstage)"
}

cmd_decision() { # ws --dp <slice>/DP-<n> --class A|C|E --text '...' [--amend]
  local ws=$1; shift
  local dp="" cls="" text="" amend=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --dp) dp=$2; shift 2 ;;
      --class) cls=$2; shift 2 ;;
      --text) text=$2; shift 2 ;;
      --amend) amend=1; shift ;;
      *) refuse "decision: unknown arg '$1'" ;;
    esac
  done
  [ -n "$dp" ] && [ -n "$text" ] || refuse "decision needs --dp <slice>/DP-<n> --class A|C|E --text '...'"
  case "$cls" in A|C|E) : ;;
    *) refuse "decision class '$cls' not in A|C|E (U is the owner's — emit --halt class_u instead)" ;;
  esac
  local slice
  slice=$(_active "$ws" slice 2>/dev/null || echo "")
  [ -n "$slice" ] || refuse "no active stage — DPs are recorded from inside a stage session"
  # The DP address is load-bearing: the reviewer's audit-exactly-once sweep
  # keys on it. Grammar + active-slice + uniqueness are checked here, not
  # trusted downstream.
  printf '%s\n' "$dp" | command grep -qE '^[0-9]{2}/DP-[1-9][0-9]*$' \
    || refuse "DP id '$dp' does not match <slice>/DP-<n> (2-digit slice, n >= 1)"
  [ "${dp%%/*}" = "$slice" ] \
    || refuse "DP id '$dp' addresses slice ${dp%%/*} but the active slice is $slice — a DP is recorded where it was decided"
  # One DP = one choice, so a second write to an id is refused — unless it is an
  # AMENDMENT (review-standards §11): the row carries `amends=<t of the row it
  # replaces>`, re-enters pending_audit, and the audit reads the LATEST per id.
  local prev_t
  prev_t=$(state_get "$ws" decisions 2>/dev/null | command grep -E "(^| )dp=$dp( |$)" | tail -1 \
    | awk '{for(i=1;i<=NF;i++) if($i ~ /^t=/){sub(/^t=/,"",$i); print $i; exit}}')
  if [ "$amend" -eq 1 ]; then
    [ -n "$prev_t" ] || refuse "--amend names DP '$dp', which has no row to amend — record it first (without --amend)"
  else
    [ -z "$prev_t" ] || refuse "DP id '$dp' already recorded — one DP = one choice; mint the next number, or re-record THIS id with --amend to supersede its row (the correction then lives on the surface, not in prose)"
  fi
  text=$(printf '%s' "$text" | tr '\n\t' '  ')
  state_append "$ws" decisions session \
    "v=1 t=$(date +%s) slice=$slice dp=$dp class=$cls status=pending_audit amends=${prev_t:-} text=$text" \
    || fault "decisions append failed"
  if [ "$amend" -eq 1 ]; then
    echo "DP amended: $dp (class $cls) supersedes its row at t=$prev_t — re-enters pending_audit; the audit reads the latest row per id"
  else
    echo "DP recorded: $dp (class $cls) — audited at the earliest reviewer checkpoint that follows"
  fi
}

cmd_learn() { # ws --leak-class precheck|conformance|gate|novel --text '...' [--record <name>]
  local ws=$1; shift
  local lc="" text="" rec=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --leak-class) lc=$2; shift 2 ;;
      --text) text=$2; shift 2 ;;
      --record) rec=$2; shift 2 ;;
      *) refuse "learn: unknown arg '$1'" ;;
    esac
  done
  case "$lc" in precheck|conformance|gate|novel) : ;;
    *) refuse "leak class '$lc' not in precheck|conformance|gate|novel (review-standards.md §9 C9)" ;;
  esac
  [ -n "$text" ] || refuse "learn needs --text '...'"
  # §9's record-naming clause, as a FIELD rather than a sentence. The clause
  # ("a `gate` tag names the record its predicate would read") is the whole
  # discipline that keeps a free tag honest, and a prose duty next to a free
  # tag is the duty that gets skipped -- so it is asked for here, where it
  # cannot be nodded at, and the harvest gets the instrument's input surface
  # grouped instead of a pile of assertions.
  # It does NOT price the tag, and that distinction is the design: you cannot
  # answer C9's gate question YES without already knowing which record the
  # predicate reads, so naming it costs one word off a printed list and never
  # a judgment. The list is DERIVED, not enumerated here -- any registered
  # store surface, plus `git`, plus `artifact` for §9's fourth case (an
  # enumeration inside the reviewed artifact itself). A surface added to the
  # registry is accepted the day it lands.
  case "$lc" in
    gate)
      [ -n "$rec" ] || refuse "leak_class=gate needs --record <name>: the record an emit-time predicate would read (review-standards.md §9). one of: git | artifact | any store surface (progress, ledger, decisions, gates, slices, ...). if you cannot name one, the predicate is not yet a predicate — tag the finding conformance/precheck/novel instead"
      case "$rec" in
        git|artifact) : ;;
        *) state_surface_known "$rec" \
             || refuse "--record '$rec' is neither 'git', 'artifact', nor a registered store surface (lib/state.sh _state_writers) — name the record the predicate READS, not the defect it would catch" ;;
      esac ;;
    *)
      [ -z "$rec" ] || refuse "--record is meaningful only for leak_class=gate (review-standards.md §9); '$lc' names no predicate" ;;
  esac
  # Keyed to the attempt that records it — slice, stage AND round — so the
  # postcheck door (_emit_leak_evidence) can ask for this round's rows and
  # a round-1 classification cannot stand in for round 2's.
  local slice lstage lround
  slice=$(_active "$ws" slice 2>/dev/null || echo "")
  lstage=$(_active "$ws" stage 2>/dev/null || echo "")
  lround=$(_active "$ws" round 2>/dev/null || echo "")
  text=$(printf '%s' "$text" | tr '\n\t' '  ')
  # record= sits BEFORE text= so the value is a fixed field the harvest can cut
  # on; text is last because it is the only free-form one. Empty for the three
  # classes that name no predicate, so the field is present on every row and a
  # reader never has to distinguish "absent" from "not applicable".
  state_append "$ws" learnings session \
    "v=1 t=$(date +%s) slice=${slice:-} stage=${lstage:-} round=${lround:-} leak_class=$lc record=${rec:-} text=$text" \
    || fault "learnings append failed"
  # The confirmation states the promotion rule for THIS class, because the
  # generic sentence was wrong for one of the four: review-standards §9 lets the
  # harvest promote a `gate` tag on a single anchor (the tag itself calls the
  # leak machine-catchable, so the first escape is the proof), while §14's
  # two-anchor bar governs the judgment classes. A tool that tells a reviewer
  # its `gate` tag needs a second anchor is quietly pricing the tag.
  case "$lc" in
    gate) echo "learning recorded (leak_class=gate, record=$rec) — the tag costs you nothing; the harvest may promote it on this one anchor (review-standards §9)" ;;
    *)    echo "learning recorded (leak_class=$lc) — promotion needs a second independent anchor" ;;
  esac
}

cmd_observe() { # ws --text '...'
  local ws=$1; shift
  local text=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --text) text=$2; shift 2 ;;
      *) refuse "observe: unknown arg '$1'" ;;
    esac
  done
  [ -n "$text" ] || refuse "observe needs --text '...' (one WORKFLOW defect/friction per entry)"
  text=$(printf '%s' "$text" | tr '\n\t' '  ')
  state_append "$ws" observations session \
    "v=1 t=$(date +%s) by=session text=$text" \
    || fault "observations append failed"
  echo "observation recorded"
}

case "${1:-}" in
  emit) shift; [ $# -ge 1 ] || refuse "emit needs <workspace>"; cmd_emit "$@" ;;
  stop-gate) shift; [ $# -ge 1 ] || refuse "stop-gate needs <workspace> [session-name]"; cmd_stop_gate "$@" ;;
  progress) shift; [ $# -ge 1 ] || refuse "progress needs <workspace>"; cmd_progress "$@" ;;
  decision) shift; [ $# -ge 1 ] || refuse "decision needs <workspace>"; cmd_decision "$@" ;;
  learn) shift; [ $# -ge 1 ] || refuse "learn needs <workspace>"; cmd_learn "$@" ;;
  observe) shift; [ $# -ge 1 ] || refuse "observe needs <workspace>"; cmd_observe "$@" ;;
  *)
    echo "usage: record.sh emit <workspace> --stage S --nonce N --verdict V --confidence HIGH|MED|LOW \\" >&2
    echo "         [--refine-rounds N]   (author stages)" >&2
    echo "         [--refine-terminated-on clean|bound]   (author stages, owed when N = refine.max_rounds; below it clean is derived)" >&2
    echo "         [--findings-substantive N --findings-wording N]                 (reviewer stages)" >&2
    echo "         [--findings-new N --findings-repeat N]   (reviewer stages, round >= 2: new + repeat = substantive)" >&2
    echo "         [--ruling-ack <slice>.<n>,...]   (owed only when a ruling landed after this attempt spawned; the refusal names the tokens)" >&2
    echo "         [--slices 'id:risk:repo:title[:after=NN,..];...']  repo in code|doc; after = earlier ids this slice waits on  (split)" >&2
    echo "         [--detail '...']" >&2
    echo "       record.sh stop-gate <workspace> [session-name]" >&2
    echo "       record.sh progress <workspace> --cu N --sha SHA   (subject derived from the sha; a re-registration at a new sha carries supersedes=<old>)" >&2
    echo "       record.sh decision <workspace> --dp <slice>/DP-<n> --class A|C|E --text '...' [--amend]   (--amend re-records an existing id; the row carries amends=<t>)" >&2
    echo "       record.sh learn <workspace> --leak-class precheck|conformance|gate|novel --text '...' \\" >&2
    echo "         [--record git|artifact|<store surface>]   REQUIRED for gate, refused otherwise: the record its predicate would read" >&2
    echo "       record.sh observe <workspace> --text '...'" >&2
    exit 2 ;;
esac
