<!-- fix.warm.md — stage prompt template, rendered by the ferry.
     manifest values are ferry-filled absolute paths; optional entries may read
     "none (<reason>)". this prompt never states the session's spawn mode. -->


# stage: fix (slice, author)

## manifest (read in order)

1. role card — binding, read first: {ROLE_CARD}
2. spec: {SPEC}
3. latest postcheck review (the findings to resolve): {REVIEW}
4. review standards — §1 (severity classes, incl. class B) and §8 (the
   conformance record and its errata); read those, not the whole file: {STANDARDS}
5. commit-message contract (`commit-messages.md`) — §1 and §2 bind the fix round's
   commits exactly as they bind impl's: {COMMITMSG}
6. the project's own written rules (optional): {RULES}
7. ruling (optional): {RULING}

## goals

- every finding of the review resolved through implementer dispatches (same
  dispatch discipline as impl — role card; model {IMPLEMENTER_MODEL} / effort
  {IMPLEMENTER_EFFORT} per dispatch), or rebutted with evidence in the
  conformance record; the landed commits stay within the spec's scope — a fix
  that needs new scope is an erratum + halt, not a widening.
- a fix re-runs every gate it could touch — never inherit a prior PASS
  (`review-standards.md` §1, class B); every declared project gate — build, lint,
  test, acceptance — re-attested PASS at the new tip, the emit refuses otherwise
  and names each missing one (a doc-bound slice records its structural
  SKIP instead — see the volatile header's `binding:` line for this slice's
  checkout; every fix commit lands there).
- the progress ledger appended (cu → SHA for fix commits);
  `slices/{SLICE}/conformance.md` updated per `review-standards.md` §8, errata
  dispositioned; every dispatch this round sends is on disk first as
  `slices/{SLICE}/dispatch.N.md` (n continues from impl's), headed
  `dispatch: cu-<N> · model=<m> · effort=<e>`.
- if the manifest carries a ruling, discharge it and record how.

## discipline

- rules live in the role card and the referenced documents — follow their current
  text; nothing in this prompt overrides them or restates them.

## final action (required — the turn cannot end without it)

with the owed artifacts on disk and the ledger resolving, emit the completion
record:

    {RECORD_SH} emit {WORKSPACE} --stage {STAGE} \
      --nonce <nonce from the volatile header> \
      --verdict <built|blocked> --confidence <HIGH|MED|LOW> \
      --refine-rounds <n> \
      [--refine-terminated-on <clean|bound>]   # owed when <n> = refine.max_rounds; below it clean is derived
      [--ruling-ack <slice>.<n>,…]   # owed only when a ruling landed after your spawn; the emit refusal names it

`blocked` carries the evidence; a Class U question uses `--halt class_u`
(questions batched).
