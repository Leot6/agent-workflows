<!-- impl.warm.md — stage prompt template, rendered by the ferry.
     manifest values are ferry-filled absolute paths; optional entries may read
     "none (<reason>)". this prompt never states the session's spawn mode. -->


# stage: impl (slice, author)

## manifest (read in order)

1. role card — binding, read first: {ROLE_CARD}
2. spec (the authority for everything landed): {SPEC}
3. review standards — §8 is the conformance record's shape; read that, not the
   whole file: {STANDARDS}
4. commit-message contract (`commit-messages.md`) — §1 the ids your message may
   not carry, §2 your subject must be true of your diff: {COMMITMSG}
5. protocol — §9 is the shared-branch rule your commits land under: {PROTOCOL}
6. project context: {PROJECT}
7. the project's own written rules (optional): {RULES}
8. ruling (optional): {RULING}

## goals

- every commit-unit of the spec landed **in this slice's bound checkout** — the
  volatile header's `binding:` line names it (a slice never spans two repos;
  work belonging to the other one is a separate slice, declared at split) —
  through implementer dispatches under the
  dispatch discipline of the role card (report only; conformance is
  diff-vs-spec-text; never commit over a red gate; BLOCKED is never re-dispatched
  unchanged). request model {IMPLEMENTER_MODEL} / effort {IMPLEMENTER_EFFORT}
  on each dispatch (the resolved implementer parameters for this slice).
- every dispatch on disk BEFORE it is sent — `slices/{SLICE}/dispatch.N.md`,
  verbatim, headed `dispatch: cu-<N> · model=<m> · effort=<e>` (role card,
  dispatch discipline). the emit refuses without at least one: the dispatch is
  the only record of what the implementer was asked.
- the progress ledger current: cu → SHA appended as each unit lands — the ledger
  is the completion evidence the ferry resolves against `git log`.
- `slices/{SLICE}/conformance.md` per `review-standards.md` §8: per-unit
  diff-vs-spec verdicts, gate readings, errata E-n with dispositions, probes
  disclosed.
- the slice-close composite acceptance gate run green (the author half of the one
  intentional double-run); gate results land as harness-attested records. a
  doc-bound slice has no acceptance concept: the gate records a structural SKIP
  and the spec's own per-slice checks are the mechanical floor.
- EVERY project gate your spec's gate plan names gets its harness-attested
  record, not only acceptance. One invocation per gate; the absolute path is in
  your volatile header, beside the record tool. It runs the adapter's own
  command in the project repo and lands a row pinned to the emitting tree, and
  an undeclared command records a named SKIP rather than nothing. The emit
  refuses on ANY declared gate with no PASS pinned to the emitting tree, and
  names each one — the asymmetry that made this a door was
  measured: consecutive slices of one topic recorded differently, one attesting
  build/lint/test on the gates surface and the next leaving them as `/tmp`
  logs, all green and none citable.
- a red gate on the shared branch gets the attribution check before anything else
  (`protocol.md` §9).
- mid-impl discovery beyond spec scope: stop, erratum, halt — revise at the
  re-derived risk class; never widen in place.
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

`blocked` carries the evidence (implementer BLOCKED report, or attribution-check
result); a Class U question uses `--halt class_u` (questions batched).
