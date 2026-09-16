#!/usr/bin/env bash
# lib/resume.sh — ferry.sh's halt-resume half (state-and-liveness.md §4, the
# ruling return path), split out under architecture §4.1's layout freedom to
# keep ferry.sh <=800 lines; only ferry.sh sources it. Uses the ferry's own
# globals/helpers (WS, TOPIC, sput, sfield, die_store, enter_stage,
# workflow_sha) — it is a half, not a library with its own contract.

# Credit a cleared halt's parked interval to the wallclock accounts — the
# budgets meter WORK, and a park is the one interval where no work can happen
# (the ferry is dead; a measured 18h owner-level park burned 2x a slice budget
# on zero attempts). Called exactly once per halt, at the moment it resolves:
# halt.t is the park's own stamp, so repeated failed relaunches never
# double-count (the halt stays unresolved and this is never reached), and the
# resolved=1 early-return above guards the resumed path. The GitHub-Actions
# shape: the job timer meters execution, never the queue.
_resume_credit_park() { # halt-t halt-slice
  local ht=$1 hs=$2 now dur pk pt
  case "$ht" in ''|*[!0-9]*) return 0 ;; esac   # legacy/hand-written halt: no stamp, no credit
  now=$(date +%s); dur=$((now - ht))
  [ "$dur" -gt 0 ] || return 0
  pk=$(sfield attempts "parked.$hs"); case "$pk" in ''|*[!0-9]*) pk=0 ;; esac
  pt=$(sfield run parked_total); case "$pt" in ''|*[!0-9]*) pt=0 ;; esac
  sput attempts "parked.$hs=$((pk + dur))"
  sput run "parked_total=$((pt + dur))"
  state_audit "$WS" ferry "park credit: ${dur}s parked (slice=$hs) excluded from the wallclock budgets"
}

resume_halt_gate() {
  local body rc reason ht hslice hstage hround rulings
  body=$(state_get "$WS" halt 2>/dev/null); rc=$?
  [ $rc -eq 3 ] && die_store "halt surface corrupt"
  [ $rc -eq 1 ] && return 0
  # Belt for legacy/hand-written halts that still inline screen text: kv
  # parsing stops at the fence so free text can never override a field.
  body=$(printf '%s\n' "$body" | awk '/^--- screen ---$/{exit} {print}')
  [ "$(printf '%s\n' "$body" | awk -F= '$1=="resolved"{v=$2} END{print v}')" = "1" ] && return 0
  reason=$(printf '%s\n' "$body" | awk -F= '$1=="reason"{v=$2} END{print v}')
  ht=$(printf '%s\n' "$body" | awk -F= '$1=="t"{v=$2} END{print v}')
  hslice=$(printf '%s\n' "$body" | awk -F= '$1=="slice"{v=$2} END{print v}')
  hstage=$(printf '%s\n' "$body" | awk -F= '$1=="stage"{v=$2} END{print v}')
  hround=$(printf '%s\n' "$body" | awk -F= '$1=="round"{v=$2} END{print v}')
  [ -n "$hslice" ] || hslice=00   # pre-stage parks (startup pins) are topic-scope
  if [ "$(printf '%s\n' "$body" | awk -F= '$1=="notified"{v=$2} END{print v}')" != "1" ]; then
    # push_gate's original page is a COMPLETION (topic.done); a resend must
    # keep the event type or the policy filter misclassifies it as a park.
    if [ "$reason" = "push_gate" ]; then
      notify_fire "$WS" topic.done none "RESEND (completion page was undelivered): topic complete — push is the owner's" \
        && sput halt "notified=1"
    elif notify_fire "$WS" park "$reason" "RESEND (halt found without notified flag): $reason"; then
      sput halt "notified=1"
    fi
  fi
  local hid
  hid=$(printf '%s\n' "$body" | awk -F= '$1=="halt_id"{v=$2} END{print v}')
  case "$reason" in
    class_u|blocked|disagreement|plan_changed)
      # A ruling answers ONE halt: slice (and stage when addressed) must match,
      # AND it must bind to THIS halt — by halt_id when it carries one
      # (launch.sh rule stamps it), else strictly newer (manual floor).
      rulings=$(state_get "$WS" rulings 2>/dev/null | awk \
        -v t="${ht:-0}" -v hs="$hslice" -v hstage="${hstage:-}" -v hid="${hid:-}" '
        {
          ts=0; rs=""; rstage="any"; rhid=""
          for(i=1;i<=NF;i++) {
            if($i ~ /^text=/) break   # text= is FREE TEXT and always last —
                                      # its tokens must never override bindings
            if($i ~ /^t=/){ts=substr($i,3)}
            if($i ~ /^slice=/){rs=substr($i,7)}
            if($i ~ /^stage=/){rstage=substr($i,7)}
            if($i ~ /^halt_id=/){rhid=substr($i,9)}
          }
          if (rs != hs) next
          if (rstage != "any" && hstage != "" && rstage != hstage) next
          if (rhid != "") { if (hid != "" && rhid == hid) print; next }
          if (ts+0 > t+0) print
        }' || true)
      if [ -z "$rulings" ]; then
        echo "still parked: $reason — an owner ruling addressed to slice $hslice is required to resume (launch.sh rule <ws> --slice $hslice --text '...')" >&2
        exit 20
      fi
      sput halt "resolved=1"
      _resume_credit_park "$ht" "$hslice"
      case "$reason" in
        class_u|blocked)
          # Ruling round-trip: the suspended stage must RE-ENTER so its next
          # attempt's manifest carries the ruling (rulings.pending). A done
          # state would re-advance the same HALT_* record into the same park
          # forever; the ruling also makes the new fingerprint novel.
          if [ "$(state_field "$WS" stage state 2>/dev/null)" = "done" ]; then
            sput stage "state=failed"
            state_audit "$WS" ferry "halt $reason: suspended stage reset to re-enter with the ruling in its manifest"
          fi ;;
        disagreement)
          # The owner's ruled continuation must BUY an advance: the same
          # records will re-feed whichever predicate parked — severity-trend on
          # a slice loop, the decomposition fixpoint on split-check — so the
          # ruled (slice, stage, round) is discharged once and the next
          # do_advance routes normally, with the ruling on the next manifest.
          # The key is shared on purpose: both predicates park `disagreement`,
          # and a stage is in exactly one of the two loops.
          sput attempts "trend_ok.$hslice.${hstage:-precheck}.${hround:-0}=1"
          state_audit "$WS" ferry "disagreement ruling: the loop's convergence predicate is discharged for (slice=$hslice stage=${hstage:-precheck} round=${hround:-?})" ;;
        plan_changed)
          # Repin, then re-enter the EARLIEST stage the plan binds
          # (plan-validate; split re-derives, ingest keeps done slices). The
          # interrupted ACTIVE slice demotes to pending+rederive — else
          # next_pending_slice would skip an 'active' row forever.
          local newhash sbody
          newhash=$(md5sum "$WS/../plan.md" 2>/dev/null | awk '{print $1}')
          sput run "plan_hash=$newhash"
          state_audit "$WS" ferry "plan_changed ruling: plan hash repinned to ${newhash:-absent} (decomposition premises re-derive from here)"
          sbody=$(state_get "$WS" slices 2>/dev/null) || sbody=""
          if printf '%s\n' "$sbody" | command grep -qE '(^| )status=active( |$)'; then
            printf '%s\n' "$sbody" | awk '
              /(^| )status=active( |$)/ { gsub(/status=active/,"status=pending"); gsub(/rederive=[0-9]+/,"rederive=1") }
              { print }' | state_set "$WS" slices ferry || die_store "slices demote failed"
            state_audit "$WS" ferry "plan_changed ruling: interrupted active slice demoted to pending+rederive (premise re-derives from the new plan)"
          fi
          enter_stage 00 plan-validate ;;
      esac
      state_audit "$WS" ferry "halt $reason cleared by ruling; resuming" ;;
    push_gate)
      # Terminal marker, not a gate: no stage exists to resume into — push is
      # the owner's action outside the workflow. The RESEND block above
      # already re-sent an undelivered page; the rest is idempotent.
      echo "topic $TOPIC COMPLETE — push is the owner's (Class U); nothing to resume (relaunch is idempotent)" >&2
      exit 0 ;;
    workflow_changed)
      # The deliberate relaunch IS the adoption: repin loudly, freeze point
      # audited (WHEN to land changes is the maintenance rule).
      sput halt "resolved=1"
      _resume_credit_park "$ht" "$hslice"
      sput run "workflow_sha=$(workflow_sha)"
      state_audit "$WS" ferry "workflow_changed: relaunch adopted the upgrade; workflow SHA repinned to $(workflow_sha); topic froze at (slice=${hslice:-} stage=${hstage:-})" ;;
    *)
      sput halt "resolved=1"
      _resume_credit_park "$ht" "$hslice"
      # Redrive: a deliberate relaunch buys ONE fresh bounded attempt set.
      # Parks are deliberate exits the watchdog never restarts, so automation
      # cannot loop through this — the relaunch is a human act (the CI
      # precedent: a redrive resets retry counters). Clearing the fingerprint
      # history matters as much as the count: without it the first respawn
      # fingerprint-matches the parked attempt and re-parks no_novelty with
      # zero fresh attempts — the doc's 'relaunch retries' would be a lie.
      if [ -n "${hstage:-}" ]; then
        sput attempts "count.$hslice.$hstage.${hround:-1}=0" "fp.$hslice.$hstage="
        state_audit "$WS" ferry "redrive: attempt budget + fingerprint history cleared for (slice=$hslice stage=$hstage round=${hround:-?})"
      fi
      state_audit "$WS" ferry "mechanical halt $reason cleared by relaunch" ;;
  esac
}
