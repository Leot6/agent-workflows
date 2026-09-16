#!/usr/bin/env bash
# lib/index.sh — ferry.sh's slices-index half (the index's writers and its
# scheduler; design/review-and-slices.md §6), split out under architecture
# §4.1's layout freedom to keep ferry.sh <=800 lines; only ferry.sh sources
# it. Uses the ferry's own globals/helpers (WS, park, die_store, ledger,
# state_audit, rec_field, slices_admissible) — it is a half, not a library
# with its own contract.

# The statuses a HUMAN retirement writes: the operator's cancel
# (`launch.sh slice <id> cancelled`) and the owner's supersede (a re-split that
# omits an id). Mechanical progress must never overwrite one. This is NOT
# ingest_slices' preserve list, which also holds `done` — that one answers "what
# may a re-split not resurrect", and `done` is a mechanical terminal the ferry
# writes itself. Two sets, two questions; kept apart on purpose and each stated
# once.
SLICE_RETIRED_STATUSES='cancelled superseded'

slice_status() { # id [body] -> the index row's status ('' when there is no row)
  local body=${2:-}
  [ -n "$body" ] || body=$(state_get "$WS" slices 2>/dev/null || true)
  rec_field "$(printf '%s\n' "$body" | command grep -E "(^| )id=$1( |$)" | tail -1)" status
}

slice_is_retired() { # id [body] -> rc 0 when this row is a human retirement
  local st s; st=$(slice_status "$@")
  for s in $SLICE_RETIRED_STATUSES; do [ "$st" = "$s" ] && return 0; done
  return 1
}

slices_set_status() { # id status [extra-kv]
  local body rc
  body=$(state_get "$WS" slices 2>/dev/null); rc=$?
  [ $rc -eq 3 ] && die_store "slices surface corrupt (fault, not absent — a status update must never be dropped silently)"
  [ $rc -ne 0 ] && return 0
  # A hand retirement outranks mechanical progress. Measured before this guard
  # existed: the operator cancelled the ACTIVE slice,
  # enter_stage's unconditional `active` write put the row back one stage later,
  # and the slice boundary then marked it `done` — the cancel erased, with the
  # audit still saying it happened. Refusing here rather than at each call site
  # is the one-derivation-per-rule shape: every mechanical writer goes through
  # this door.
  case " $SLICE_RETIRED_STATUSES " in
    *" $2 "*) : ;;
    *) if slice_is_retired "$1" "$body"; then
         state_audit "$WS" ferry "slice $1 is retired by hand (status=$(slice_status "$1" "$body")) — refusing the mechanical write status=$2"
         return 4
       fi ;;
  esac
  printf '%s\n' "$body" | awk -v id="$1" -v st="$2" -v ex="${3:-}" '
    $0 ~ ("(^| )id=" id "( |$)") {
      gsub(/status=[A-Za-z0-9_-]+/, "status=" st)
      if (ex != "") $0 = $0 " " ex
    } { print }' | state_set "$WS" slices ferry || die_store "slices write failed"
}

reroute_if_slice_retired() { # rc 0 when it acted (the caller then re-loops)
  # The operator retired the slice this ferry is holding. Deliberately the same
  # shape as the stop request it sits beside in the main loop: a graceful turn
  # BETWEEN attempts, never a kill of a live one (that is `launch.sh stop`).
  # The reroute IS the slice boundary's own selection, so a cancel behaves
  # exactly like the slice having finished — except that nothing marks it done.
  # Without this the cancel was erased one stage later (measured:
  # enter_stage's unconditional `active` write, then `done` at the
  # boundary, with the operator's audit line still claiming the cancel took).
  [ -n "${G_SLICE:-}" ] && [ "${G_SLICE:-}" != "00" ] || return 1
  case "${G_STATE:-none}" in running|none) return 1 ;; esac
  local st; st=$(slice_status "$G_SLICE")
  slice_is_retired "$G_SLICE" || return 1
  state_audit "$WS" ferry "slice $G_SLICE was retired by hand while the ferry held it (status=$st) — tearing its sessions down and rerouting to the next schedulable slice"
  ledger "event=slice_retired slice=$G_SLICE stage=${G_STAGE:-} status=$st"
  teardown_slice_sessions
  schedule_next_slice
  return 0
}

schedule_next_slice() { # select and enter the next schedulable slice, else close out
  # ONE derivation, two doors: the slice boundary in do_advance, and the main
  # loop's reroute when the held slice is retired under the ferry's feet.
  local nxt
  nxt=$(next_pending_slice)
  if [ -n "$nxt" ]; then enter_stage "$nxt" spec; return 0; fi
  # Pending rows with no schedulable member must never walk silently to
  # close-out: every one waits on an after= that is pending/active/missing — a
  # wedged index, reachable only through hand-written rows.
  # here-string, not a pipe: under `pipefail` a SIGPIPE 141 from the producer
  # makes this `if` read FALSE, which skips the park and walks a wedged index
  # silently to close-out — precisely what the comment above forbids. The index
  # is far too small to reach the pipe buffer today, so this is R19's
  # convert-ON-TOUCH rule rather than a live defect: the line moved into this
  # function when the scheduler was extracted, and that is a touch (VD-76).
  if command grep -qE '(^| )status=pending( |$)' <<< "$(state_get "$WS" slices 2>/dev/null)"; then
    park stall_record "pending slices remain but none is schedulable — every pending id's after= waits on a pending/active/missing row; repair the index (launch.sh slice cancel/restore, or a deliberate re-split)"
  fi
  enter_stage 00 close-out
}

next_pending_slice() {
  # Min pending id whose after set is fully out of the way (the systemd
  # After=/topological-order shape, degenerate because every edge points
  # backward in the id order). Blocking states are pending/active; done,
  # cancelled and superseded all satisfy (superseded is an owner-retired id —
  # waiting on it would be a deadlock). An after naming a MISSING row blocks:
  # a vanished row silently satisfying would reintroduce the very inversion
  # after= exists to prevent (the advance path parks when pendings exist but
  # none is schedulable — only reachable through hand-written rows, since an
  # admissible index always has a schedulable minimum).
  state_get "$WS" slices 2>/dev/null | awk '
    { id=""; st=""; af=""
      for(i=1;i<=NF;i++){
        if($i ~ /^id=/) id=substr($i,4)
        else if($i ~ /^status=/) st=substr($i,8)
        else if($i ~ /^after=/) af=substr($i,7)
      }
      if(id != ""){ S[id]=st; A[id]=af }
    }
    END{
      best=""
      for(id in S){
        if(S[id] != "pending") continue
        ok=1; n=split(A[id], d, ",")
        for(j=1;j<=n;j++){
          if(d[j]=="") continue
          if(!(d[j] in S) || S[d[j]]=="pending" || S[d[j]]=="active"){ ok=0; break }
        }
        if(ok && (best=="" || id < best)) best=id
      }
      if(best != "") print best }'
}

ingest_slices() { # slices-field (id:risk:repo:title[:after=NN,..];... titles underscored)
  local new=$1 body line seg id risk repo title out="" bad brc delta aft core
  [ -n "$new" ] || park stall_record "split record carries an empty slices= field — refusing to write an empty index (a zero-slice topic would complete silently); the record tooling or a hand-written record is broken"
  body=$(state_get "$WS" slices 2>/dev/null || true)
  # The index door's admissibility check — the SAME derivation record.sh's emit
  # refuses on (the owed pattern: one list, one door each). A record can reach
  # this door without ever having passed emit (hand-written, or a store
  # rollback), so the field is proven HERE; the loops below read a field this
  # call has already validated, and keep their own cheap guards only so they
  # stay correct if anyone ever reorders them.
  bad=$(slices_admissible "$WS" "$new"); brc=$?
  [ $brc -eq 3 ] && die_store "slices surface unreadable while ingesting the index"
  [ $brc -eq 1 ] && park stall_record "split record carries an inadmissible index: $(printf '%s' "$bad" | tr '\n' '; ') — emit refuses these, so this record reached the index without passing it"
  while IFS= read -r seg; do
    [ -n "$seg" ] || continue
    # after= is a TAIL segment, split off before the 4-field parse — else it
    # folds into the free-text title (admissibility above already proved its
    # shape, backward direction and resolvability).
    aft=$(printf '%s' "$seg" | command grep -oE ':after=[0-9]{2}(,[0-9]{2})*$' || true)
    core=${seg%"$aft"}; aft=${aft#:after=}
    id=${core%%:*}; risk=${core#*:}; risk=${risk%%:*}
    repo=${core#*:*:}; repo=${repo%%:*}; title=${core#*:*:*:}
    line=$(printf '%s\n' "$body" | command grep -E "(^| )id=$id( |$)" | tail -1)
    # An existing id keeps its whole row — which is what makes the binding
    # IMMUTABLE per id by construction: a re-split cannot re-bind a live slice,
    # a different binding is a different id (ids are never reused). The
    # declared fields split there: id, repo and after steer the machine, so
    # dropping a re-declaration of any is REFUSED before we get here
    # (slices_admissible); risk and title are human-facing copies with no
    # machine reader, so their drop changes nothing mechanically and only the
    # silence needs fixing.
    if [ -n "$line" ]; then
      delta=""
      [ "$(rec_field "$line" risk)" = "$risk" ] || delta="$delta risk=$(rec_field "$line" risk)->$risk"
      [ "$(rec_field "$line" title)" = "$title" ] || delta="$delta title=$(rec_field "$line" title)->$title"
      [ -z "$delta" ] \
        || state_audit "$WS" ferry "re-split re-declared slice $id ($delta ) — the standing row holds; these fields are human-facing copies (risk is re-derived independently at every review)"
      out="$out$line"$'\n'
    else out="${out}id=$id status=pending risk=$risk repo=$repo title=$title rederive=0${aft:+ after=$aft}"$'\n'; fi
  done < <(printf '%s\n' "$new" | tr ';' '\n')
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    id=$(rec_field "$line" id)
    if ! printf '%s' "$new" | command grep -qE "(^|;)$id:"; then
      case "$line" in *status=done*|*status=cancelled*|*status=superseded*) out="$out$line"$'\n' ;;
        *) out="$out$(printf '%s\n' "$line" | sed 's/status=[A-Za-z0-9_-]*/status=superseded/')"$'\n' ;;
      esac
    fi
  done <<< "$body"
  printf '%s' "$out" | state_set "$WS" slices ferry || die_store "slices ingest failed"
  # `decisions=` rides BEFORE `slices=` on purpose: the fixpoint's identity is
  # the index's bytes and nothing else, so this field must never enter the
  # comparison — it is read, not compared. What it buys: two emits with the same
  # index and different counts say the round produced a class=A re-binding the
  # index cannot express (commit units, case-to-slice assignment). Measured on a
  # live topic: a 64-minute round left the index byte-identical and produced
  # `00/DP-2`.
  local dcount
  dcount=$(state_get "$WS" decisions 2>/dev/null | command grep -cE '(^| )class=A( |$)') || dcount=0
  ledger "event=slices_index decisions=${dcount:-0} slices=$new"
}
