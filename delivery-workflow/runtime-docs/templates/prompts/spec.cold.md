<!-- spec.cold.md — stage prompt template, rendered by the ferry.
     manifest values are ferry-filled absolute paths; optional entries may read
     "none (<reason>)". this prompt never states the session's spawn mode. -->


# stage: spec (slice, author)

## manifest (read in order)

1. role card — binding, read first: {ROLE_CARD}
2. charter (this slice): {CHARTER}
3. plan excerpt (optional — the plan's context, the work items your charter
   names, and its invariants, derived by the ferry; read it in full; when it
   reads none, read the plan in full instead): {PLAN_SLICE}
4. plan (full — the citation authority: every anchor resolves here; consult
   it by heading for anything the excerpt lacks, never read it end to end when
   the excerpt is present): {PLAN}
5. review standards — §4 is the spec-ready contract this spec is graded
   against, §4.8 the authority chain, §11 the decision-point classes; read
   those, not the whole file: {STANDARDS}
6. commit-message contract (`commit-messages.md`) — §1 the ids a subject may
   not carry, §2 the subject as a claim about a diff; the commit-unit subjects
   this spec prescribes are graded against both (§4 item 4): {COMMITMSG}
7. project context (caps, gates, conventions): {PROJECT}
8. resolved config snapshot (optional — effective caps/budgets with layers): {CONFIG}
9. previous slice's turnover (optional — the first slice has none): {TURNOVER_PREV}
10. ruling (optional): {RULING}

## goals

- this slice's binding spec on disk (`slices/{SLICE}/spec.md`), following
  `templates/spec.md` and satisfying the spec-ready contract
  (`review-standards.md` §4, current text) — self-contained, constraints
  front-loaded, scope proven by command, commit-units enumerated, gate plan with
  the flip gate wherever a criterion of the close reads differently at the
  baseline than at HEAD (§4.5 — the evidence test, not a behavior test; a
  doc-bound slice owes it through its own per-slice checks), claims table
  complete, logical baseline pinned.
- authority chain: the spec cites the plan; the turnover supplies pointers and
  deltas only — never a premise (`review-standards.md` §4.8).
- numbers derived from the tree, never hand-predicted; the probe window (worktree
  apply → measure → revert, disclosed) is available for derivation.
- run the refine loop and write the refine log section before emitting.
- record any Class A/C decisions taken while drafting as DPs in the decisions
  surface (`review-standards.md` §11).
- if the manifest carries a ruling, discharge it and record how.

## discipline

- rules live in the role card and the referenced documents — follow their current
  text; nothing in this prompt overrides them or restates them.

## final action (required — the turn cannot end without it)

with the spec on disk, emit the completion record:

    {RECORD_SH} emit {WORKSPACE} --stage {STAGE} \
      --nonce <nonce from the volatile header> \
      --verdict <drafted> --confidence <HIGH|MED|LOW> \
      --refine-rounds <n> \
      [--refine-terminated-on <clean|bound>]   # owed when <n> = refine.max_rounds; below it clean is derived
      [--ruling-ack <slice>.<n>,…]   # owed only when a ruling landed after your spawn; the emit refusal names it

a Class U question instead replaces the verdict with `--halt class_u` (questions
batched, recommendation attached).
