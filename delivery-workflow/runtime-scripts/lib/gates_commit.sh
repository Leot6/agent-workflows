#!/usr/bin/env bash
# lib/gates_commit.sh — the COMMIT gate family, sourced by lib/gates.sh (never
# directly): the message half of the project's commit convention
# (`_gates_message_fails`, asked at both doors a SHA passes — registration in
# record.sh progress and the gate at emit), the workspace/handed-over id
# lookup behind `commit-messages.md` §1, the amend advice that is true for THIS
# commit, and `gates_commit` itself (message + diff cap, attested). Split out
# of gates.sh under architecture §4.1's layout freedom to keep that file under
# cap.source_file — the same move that took watch.sh out of ferry.sh; every
# helper these call (_gates_repo, _gates_slice, _gates_cap, _gates_record,
# the binding primitives) lives in the sourcing file.

# The ids the workflow mints for its own bookkeeping — cu-N, DP-N, slice ids,
# the topic tree's own paths — resolve only inside the topic workspace. In the
# delivered repo they are dangling pointers: the history outlives the workspace,
# and a later reader of that history has nowhere to look any of them up. §12
# already rules that the checkout receives zero workflow files; the commit
# MESSAGE was the one door the bookkeeping still crossed — and the authoring
# session meets these ids in every prompt it is handed, so it reaches for them
# naturally. Measured on one topic: four commits carried `cu-2`, `DP-2`,
# `slice 14` and a plan review anchor, one of them in the subject line where
# `git log --oneline` shows it forever.
#
# Deliberately narrow: it matches what THIS workflow mints, never what a project
# may additionally forbid. Project message conventions stay with the project's
# own tools through the lint/test/acceptance seam — a driver that restates them
# owns rules it cannot keep current, which is the failure mode this gate is a
# reaction to (the same topic's project HAD a message-hygiene gate; its
# hand-enumerated token list simply did not know this driver's vocabulary).
# The second class: ids this workflow does not MINT but does HAND OVER. A plan's
# review-round anchors (`R10-2`), its decision points, its flip-gate labels reach
# the authoring session through the manifest — PLAN, CHARTER, SPEC — so it reaches
# for them as naturally as for ours, and in the delivered repo they resolve no
# better. Enumerating their shapes is exactly the blocklist that failed: the
# project's own gate held `R1-` and `R6x-` and let `R10-2` through the gap, and
# every new round number opens that gap again. So the shape is only a CANDIDATE
# filter and the verdict is a LOOKUP — a candidate that also occurs in this
# topic's own planning artifacts is an id we handed over; one that occurs nowhere
# in them is the project's own word, and `SHA-1`, `UTF-8`, `RFC-2119`, `AVX-512`
# pass untouched without anyone having to list them. Reads cost nothing in the
# common case: the message carries no candidate at all, so no artifact is opened.
_gates_plan_anchors() { # workspace message -> handed-over ids the message names
  local ws=$1 msg=$2 cand tok f
  cand=$(printf '%s\n' "$msg" | command grep -oE '\b[A-Z]{1,8}[0-9]*-[0-9]+\b' | sort -u)
  [ -n "$cand" ] || return 0
  # Planning INPUTS only (plan / charter / spec). Reviews and conformance are
  # outputs — they quote what landed, so a token could enter through the very
  # message being judged.
  local arts=() plan="$ws/../plan.md"
  # `<ws>/charters.md` is where split writes the charter (stages.tsv's owed
  # column; owed.sh, compose.sh and record.sh resolve it there). This read
  # looked under slices/00/ for it and so never opened one — an id only the
  # charter hands over passed as a domain word; measured, fixture-first.
  for f in "$plan" "$ws/charters.md" "$ws"/slices/*/spec.md; do
    [ -f "$f" ] && arts+=("$f")
  done
  # A lookup is only as wide as the artifacts it can read, and this one narrows
  # SILENTLY: a token that resolves only in the plan passes as a domain word,
  # verdict clean, nothing said. PLAN is a required manifest item for five
  # stages, so its absence here is not the early-topic state — it is the
  # boundary artifact renamed or moved, which the hard-coded path cannot follow
  # (no adapter key; logged DEFER). Named, never silent — the doctrine this tree
  # applies to the no-git pin, the forced-cold spawn and the undeclared gate.
  # Said only when it could change the verdict: candidates are already in hand.
  [ -f "$plan" ] \
    || echo "commit gate: judging $(printf '%s\n' "$cand" | command grep -c .) anchor-shaped token(s) WITHOUT $plan (absent) — a handed-over id that resolves ONLY in the plan cannot be caught here" >&2
  [ "${#arts[@]}" -gt 0 ] \
    || { echo "commit gate: no planning artifact readable (plan / charters / spec) — the handed-over-id axis judged nothing at all" >&2; return 0; }
  while IFS= read -r tok; do
    [ -n "$tok" ] || continue
    command grep -qwF -- "$tok" "${arts[@]}" 2>/dev/null && printf '%s\n' "$tok"
  done <<< "$cand"
  return 0
}

_gates_ws_ids() { # workspace message -> offending tokens, one per line; rc ALWAYS 0
  local ws=$1 msg=$2 topicdir
  topicdir=$(cd "$ws/.." 2>/dev/null && pwd) || topicdir=""
  # NB stderr is NOT suppressed here on purpose: _gates_plan_anchors names its
  # own degradation on it, and a block-wide 2>/dev/null swallowed that notice
  # whole (measured while adding it — the guard was belt-and-braces, since the
  # greps inside cannot fail on a fixed pattern and the one that could is
  # already redirected at its own call site). stdout stays the token channel.
  { printf '%s\n' "$msg" \
      | command grep -oE '\b(cu-[0-9]+|DP-[0-9]+|slices?/[0-9]{2}|slice [0-9]{2})\b'
    [ -n "$topicdir" ] && printf '%s\n' "$msg" | command grep -oF "$topicdir"
    _gates_plan_anchors "$ws" "$msg"
  } | sort -u
  # Emptiness is the ANSWER here, not an error: a no-match grep under pipefail
  # would otherwise hand callers rc 1 for the clean case, and the first caller
  # to write `if _gates_ws_ids …` or to run under `set -e` would read a passing
  # message as a failure. The tokens on stdout are the whole verdict.
  return 0
}

# `git commit --amend` rewrites THE TIP — never the commit you name. So "amend
# the message" is a true instruction only while the commit still IS the tip, and
# which one it is costs a single rev-parse. The emit door judges EVERY landed cu
# of the slice, so at most one of the commits it fails can take that advice;
# every other one gets an instruction that, followed literally, rewrites a
# commit nobody complained about and leaves the complaint standing. Measured
# twice: a close-out subject sweep on this workflow's own topic ended in a hand
# rewrite of the branch, and a maintainer who amended against a HEAD that had
# moved under him replaced another writer's message (recovered with `reset
# --soft`). An instruction that is false in the common case is worse than
# silence — silence sends you to read; a wrong instruction gets followed.
_gates_amend_advice() { # ws repo sha -> the one fix path that is true for THIS commit
  local ws=$1 repo=$2 sha=$3 branch hb head obj n
  head=$(git -C "$repo" rev-parse -q --verify HEAD 2>/dev/null) \
    || { echo "fix: the checkout has no commits (unborn HEAD) — nothing to rewrite."; return 0; }
  # An amend rewrites whatever HEAD is; what gets DELIVERED is the slice's
  # declared branch, and that is what every registered sha is checked against
  # (`_owed_cu_ok`). When the two are not the same ref, no statement about this
  # commit's position is the useful one: the amend would land somewhere the
  # branch never carries, so say THAT first. Comparing shas is not enough — a
  # HEAD detached AT the branch tip reads identical and is exactly the case
  # where the amend silently leaves the branch behind.
  branch=$(binding_branch "$ws" "$(_gates_slice "$ws")" 2>/dev/null || true)
  hb=$(git -C "$repo" symbolic-ref -q --short HEAD 2>/dev/null || true)
  obj=$(git -C "$repo" rev-parse -q --verify "$sha^{commit}" 2>/dev/null || echo none)
  if [ -z "$hb" ]; then
    echo "fix: HEAD is detached at ${head:0:7} — an amend moves HEAD alone, so ${branch:-the delivered branch} would never carry the result, and every registered sha is checked against ${branch:-it}. Check the branch out first."
  elif [ -n "$branch" ] && [ "$hb" != "$branch" ]; then
    echo "fix: the checkout is on '$hb' but this slice delivers '$branch' — an amend here rewrites a commit '$branch' does not carry. Check '$branch' out first."
  elif [ "$obj" = "$head" ]; then
    echo "fix: this commit IS the tip — git commit --amend, then register the new sha (record.sh progress)."
  elif git -C "$repo" merge-base --is-ancestor "$obj" "$head" 2>/dev/null; then
    n=$(git -C "$repo" rev-list --count "$obj..$head" 2>/dev/null || echo "?")
    echo "fix: this commit sits $n commit(s) BELOW the tip — git commit --amend would rewrite the tip instead, leaving this message untouched. Rewriting it renumbers those $n, and every registered sha with them: that is a branch rewrite, not a stage action — report it (erratum) and let the author decide. Recipe and invariants: runtime-docs/operations.md §8."
  else
    echo "fix: this commit is not on '$hb' (tip ${head:0:7}) — the branch carrying it is not the one checked out, so nothing here rewrites it in place."
  fi
  return 0
}

# The MESSAGE half of the commit convention — one derivation, asked at both
# doors a SHA passes (registration in `record.sh progress`, the gate at emit),
# so the two can never drift apart in verdict or in wording.
#
# Which axes a door may ask is decided by what the session can fix ON THE SPOT.
# A message is fixable while its commit is the tip, and registration is exactly
# where it still is one — so asking there costs one amend, while asking only at
# emit costs a branch rewrite (see _gates_amend_advice). The diff cap is
# deliberately NOT in this half: its remedy is re-splitting the unit, which is a
# spec-level decision AND a rewrite of landed history, so refusing the LEDGER
# over it would strand the record of a commit that really did land — with no
# local move that clears the wall. That axis stays at the emit gate, which is
# the attestation authority and can fail the stage without losing the record.
#
# Output is one `<token>\t<text>` line per failure (the caller shows the text
# and records the token), plus a trailing `fix\t…` line whenever any failure
# fired: every message-class failure shares one remedy — rewrite THIS message —
# and one precondition, which is whether the commit can still be reached from
# here. rc 2 = the convention itself is unreadable (self-describing on stderr).
_gates_message_fails() { # ws sha -> "<token>\t<text>" per failure; rc 2 refuse
  local ws=$1 sha=$2 repo regex subject trailers forbidden t body wsids n=0
  repo=$(_gates_repo "$ws") || return 2
  regex=$(project_get "$ws" commit.subject_regex) || {
    echo "refuse: project.kv declares no commit.subject_regex — the commit convention is the project's, never assumed" >&2
    return 2
  }
  git -C "$repo" rev-parse -q --verify "$sha^{commit}" > /dev/null || {
    echo "refuse: $sha is not a commit in $repo" >&2; return 2
  }
  subject=$(git -C "$repo" log -1 --format=%s "$sha")
  body=$(git -C "$repo" log -1 --format=%B "$sha")
  if ! printf '%s\n' "$subject" | command grep -qE "$regex"; then
    printf 'subject_regex\tsubject '\''%s'\'' fails project regex '\''%s'\'' (%s)\n' "$subject" "$regex" "$sha"
    n=1
  fi
  trailers=$(project_get "$ws" commit.trailers 2>/dev/null || true)
  while IFS= read -r t; do
    [ -n "$t" ] || continue
    if ! printf '%s\n' "$body" | command grep -q "^$t:"; then
      printf 'trailer:%s\tmissing trailer '\''%s:'\'' (%s) — project.kv commit.trailers\n' "$t" "$t" "$sha"
      n=1
    fi
  done < <(printf '%s\n' "$trailers" | tr ',' '\n')
  # The same convention's other direction: a trailer the project FORBIDS must
  # not appear. Matched case-insensitively — git trailers are, and a
  # prohibition an authoring session can evade by changing case is not one.
  forbidden=$(project_get "$ws" commit.forbid_trailers 2>/dev/null || true)
  while IFS= read -r t; do
    [ -n "$t" ] || continue
    if printf '%s\n' "$body" | command grep -qi "^$t:"; then
      printf 'forbidden:%s\tforbidden trailer '\''%s:'\'' present (%s) — project.kv commit.forbid_trailers\n' "$t" "$t" "$sha"
      n=1
    fi
  done < <(printf '%s\n' "$forbidden" | tr ',' '\n')
  wsids=$(_gates_ws_ids "$ws" "$body")
  if [ -n "$wsids" ]; then
    printf 'ws_ids\tmessage names id(s) that resolve only in this topic'\''s own planning and workspace artifacts, which the delivered repository does not carry [%s] (%s) — some of these ids this workflow mints (cu-N, DP-N, slice ids, workspace paths), some this topic'\''s own plan or spec hands over (work-item ids, review-round anchors, decision points, flip-gate labels); either way the history outlives the artifacts they live in, so a later reader of it has nowhere to look them up. Say what the change does in words the repository itself resolves; the id→SHA mapping is the workflow'\''s own record (progress/ledger/conformance), never the repo'\''s history. An upstream artifact that PRESCRIBES such a token is a conflict to raise, not to pass through.\n' \
      "$(printf '%s' "$wsids" | tr '\n' ' ')" "$sha"
    n=1
  fi
  [ "$n" -eq 1 ] && printf 'fix\t%s\n' "$(_gates_amend_advice "$ws" "$repo" "$sha")"
  return 0
}

gates_commit() { # workspace sha [--relocation-only]
  local ws=$1 sha=$2 reloc=0
  [ "${3:-}" = "--relocation-only" ] && reloc=1
  local repo fails="" msgout tok txt out cap src diff
  repo=$(_gates_repo "$ws") || return 2
  msgout=$(_gates_message_fails "$ws" "$sha") || return 2
  while IFS=$'\t' read -r tok txt; do
    [ -n "$tok" ] || continue
    echo "commit gate: $txt"
    [ "$tok" = fix ] || fails="$fails $tok"
  done <<< "$msgout"
  out=$(_gates_cap "$ws" cap.commit_diff_lines) || return 3
  cap=${out%%	*}; src=${out#*	}
  diff=$(git -C "$repo" show --format= --numstat "$sha" \
         | awk '{a+=($1=="-"?0:$1); d+=($2=="-"?0:$2)} END{print a+d}')
  if [ "${diff:-0}" -gt "$cap" ]; then
    if [ $reloc -eq 1 ]; then
      echo "commit gate: diff=$diff lines over cap.commit_diff_lines=$cap ($src) — exempt: unit declared relocation-only (named, not silent)"
    else
      echo "cap_exceeded: commit=$sha diff_lines=$diff cap=cap.commit_diff_lines=$cap source=$src"
      fails="$fails diff:$diff>$cap"
    fi
  fi
  if [ -n "$fails" ]; then
    _gates_record "$ws" commit FAIL "sha=$sha$fails"
    return 1
  fi
  _gates_record "$ws" commit PASS "sha=$sha diff=$diff reloc=$reloc"
}
