<!-- turnover.warm.md — stage prompt template, rendered by the ferry.
     manifest values are ferry-filled absolute paths; optional entries may read
     "none (<reason>)". this prompt never states the session's spawn mode. -->


# stage: turnover (slice, author)

## manifest (read in order)

1. role card — binding, read first: {ROLE_CARD}
2. spec: {SPEC}
3. ledger (this slice's stage transitions): {LEDGER}
4. progress ledger (optional — the cu → SHA record of landed units): {PROGRESS}
5. plan (the remaining-plan inventory reads it, never memory): {PLAN}
6. review standards — §4.8 is the authority chain your turnover must not
   violate (pointers and deltas, never a premise): {STANDARDS}
7. protocol — §7 is concurrence-precedes-execution, which governs a re-slice
   proposal: {PROTOCOL}
8. project context: {PROJECT}
9. ruling (optional): {RULING}

## goals

- `slices/{SLICE}/turnover.md`: **pointers + deltas only** — where the landed
  work lives, what changed against the charter, what the next slice must know as
  pointers into authoritative artifacts. never restate premises: the next spec
  cites the plan, not this file (the telephone-game guard,
  `review-standards.md` §4.8).
- the standing re-slice step: inventory the remaining plan against what this
  slice learned. merge proposals → verdict `reslice` (routes to split-check for
  concurrence — concurrence precedes execution, `protocol.md` §7); finer splits →
  Class A DPs recorded; slice ids never reused.
- run the refine loop on the turnover before emitting.
- if the manifest carries a ruling, discharge it and record how.

## discipline

- rules live in the role card and the referenced documents — follow their current
  text; nothing in this prompt overrides them or restates them.

## final action (required — the turn cannot end without it)

with the turnover on disk, emit the completion record:

    {RECORD_SH} emit {WORKSPACE} --stage {STAGE} \
      --nonce <nonce from the volatile header> \
      --verdict <done|reslice> --confidence <HIGH|MED|LOW> \
      --refine-rounds <n> \
      [--refine-terminated-on <clean|bound>]   # owed when <n> = refine.max_rounds; below it clean is derived
      [--ruling-ack <slice>.<n>,…]   # owed only when a ruling landed after your spawn; the emit refusal names it

a Class U question instead uses `--halt class_u` (questions batched).
