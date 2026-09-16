<!-- revise.warm.md — stage prompt template, rendered by the ferry.
     manifest values are ferry-filled absolute paths; optional entries may read
     "none (<reason>)". this prompt never states the session's spawn mode. -->


# stage: revise (slice, author)

## manifest (read in order)

1. role card — binding, read first: {ROLE_CARD}
2. spec: {SPEC}
3. latest precheck review: {REVIEW}
4. review standards — §1 (R-Q rows), §3 (the refine loop, re-run never
   inherited), §4 (the contract the revision must now satisfy) and §11 (DPs
   taken while revising); read those, not the whole file: {STANDARDS}
5. ruling (optional): {RULING}

## goals

- the review absorbed into the spec: each finding either fixed or rebutted with
  evidence (a rebuttal cites what the finding did not); reviewer questions
  (R-Q rows, `review-standards.md` §1) answered in the spec text itself — the
  spec stays self-contained.
- the refine loop re-run on every changed passage; gates any edit could touch
  re-run, never inherited (`review-standards.md` §3); the refine log and claims
  table updated; the spec still satisfies the spec-ready contract
  (`review-standards.md` §4).
- new decisions taken while revising recorded as DPs (`review-standards.md` §11).
- if the manifest carries a ruling, discharge it and record how.

## discipline

- rules live in the role card and the referenced documents — follow their current
  text; nothing in this prompt overrides them or restates them.

## final action (required — the turn cannot end without it)

with the revised spec on disk, emit the completion record:

    {RECORD_SH} emit {WORKSPACE} --stage {STAGE} \
      --nonce <nonce from the volatile header> \
      --verdict <drafted> --confidence <HIGH|MED|LOW> \
      --refine-rounds <n> \
      [--refine-terminated-on <clean|bound>]   # owed when <n> = refine.max_rounds; below it clean is derived
      [--ruling-ack <slice>.<n>,…]   # owed only when a ruling landed after your spawn; the emit refusal names it

a Class U question instead replaces the verdict with `--halt class_u` (questions
batched, recommendation attached).
