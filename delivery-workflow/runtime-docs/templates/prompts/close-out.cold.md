<!-- close-out.cold.md — stage prompt template, rendered by the ferry.
     manifest values are ferry-filled absolute paths; optional entries may read
     "none (<reason>)". this prompt never states the session's spawn mode. -->


# stage: close-out (topic, author)

## manifest (read in order)

1. role card — binding, read first: {ROLE_CARD}
2. ledger (the whole topic's stage transitions): {LEDGER}
3. progress ledger (optional — the cu → SHA record; landed SHAs enumerate from HERE, the ledger holds counts only): {PROGRESS}
4. charters: {CHARTERS}
5. slice index AS FIRST DECLARED — the dispositions to reconcile. These are
   the standing store rows: a slice's human-facing fields (risk, title) stay
   as the FIRST split wrote them by design, and the drop is audited — so
   after any re-declaration round this render disagrees with the charter on
   exactly the re-declared field. The charter is authoritative for risk and
   title; read this for id / repo / after / order, and the audit surface for
   what changed:
   {INDEX_AS_FIRST_DECLARED}
6. review standards — §11 (an open veto blocks this stage) and §14 (the
   learning loop's promotion bar, logged never enforced); read those, not the
   whole file: {STANDARDS}
7. operations — §8 holds the hard invariants your history-consolidation
   proposal must satisfy: {OPERATIONS}
8. decisions surface (optional — open vetoes block close-out): {DECISIONS}
9. observations surface (optional — workflow defects to leave tidy): {OBSERVATIONS}
10. learnings surface (optional — unpromoted/DEFER entries to leave tidy): {LEARNINGS}
11. ruling (optional): {RULING}

## goals

- `closeout.md`: the ledger settled — every slice's disposition (done, superseded,
  cancelled) reconciled against the charters and the index; landed SHAs
  enumerated from the progress ledger ({PROGRESS}); open vetoes confirmed closed
  (a vetoed DP without its fix slice blocks close-out, `review-standards.md` §11).
- the history consolidation proposal (Class C — two keys before execution): the
  old → new map preview under the hard invariants of `operations.md` §8;
  execution only after concurrence. push stays Class U — the workflow never
  pushes.
- unpromoted observations and DEFER entries left tidy for the learning loop
  (`review-standards.md` §14) — logged, never enforced.
- run the refine loop on the closeout before emitting.
- if the manifest carries a ruling, discharge it and record how.

## discipline

- rules live in the role card and the referenced documents — follow their current
  text; nothing in this prompt overrides them or restates them.

## final action (required — the turn cannot end without it)

with `closeout.md` on disk, emit the completion record:

    {RECORD_SH} emit {WORKSPACE} --stage {STAGE} \
      --nonce <nonce from the volatile header> \
      --verdict <done> --confidence <HIGH|MED|LOW> \
      --refine-rounds <n> \
      [--refine-terminated-on <clean|bound>]   # owed when <n> = refine.max_rounds; below it clean is derived
      [--ruling-ack <slice>.<n>,…]   # owed only when a ruling landed after your spawn; the emit refusal names it

a Class U question instead uses `--halt class_u` (questions batched).
