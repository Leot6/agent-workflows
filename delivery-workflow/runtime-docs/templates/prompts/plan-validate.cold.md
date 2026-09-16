<!-- plan-validate.cold.md — stage prompt template, rendered by the ferry.
     manifest values are ferry-filled absolute paths; optional entries may read
     "none (<reason>)". this prompt never states the session's spawn mode. -->


# stage: plan-validate (topic, author)

## manifest (read in order)

1. role card — binding, read first: {ROLE_CARD}
2. plan under validation: {PLAN}
3. review standards — §2 (the note's own claims discipline) and §3 (the refine
   loop) are what this stage is held to; read those, not the whole file: {STANDARDS}
4. protocol — §2 is where this stage sits in the flow: {PROTOCOL}
5. project context: {PROJECT}
6. ruling (optional): {RULING}

## goals

- a verdict on whether the plan is plan-ready — complete, unambiguous, free of
  anything needing owner adjudication — for exactly the sections split will bind
  (validation scope per the role card §per-stage duties; `protocol.md` §2).
- the validation note on disk (`slices/00/validation_note.md`): what was read
  (every claim carries a read-range stamp — no whole-plan claims), what binds,
  what is ambiguous or missing, with a claims table per
  `review-standards.md` §2.
- run the refine loop on the note before emitting (`review-standards.md` §3).
- if the manifest carries a ruling, discharge it and record how.

## discipline

- rules live in the role card and the referenced documents — follow their current
  text; nothing in this prompt overrides them or restates them.

## final action (required — the turn cannot end without it)

with the owed artifacts on disk, emit the completion record:

    {RECORD_SH} emit {WORKSPACE} --stage {STAGE} \
      --nonce <nonce from the volatile header> \
      --verdict <ready|not_ready> --confidence <HIGH|MED|LOW> \
      --refine-rounds <n> \
      [--refine-terminated-on <clean|bound>]   # owed when <n> = refine.max_rounds; below it clean is derived
      [--ruling-ack <slice>.<n>,…]   # owed only when a ruling landed after your spawn; the emit refusal names it
      [--detail "<the batched questions — required with not_ready>"]

`not_ready` routes to the owner with your question set attached — batch every
co-pending question into `--detail` (the owner's page is built from it; the
emit refuses a not_ready without it).
