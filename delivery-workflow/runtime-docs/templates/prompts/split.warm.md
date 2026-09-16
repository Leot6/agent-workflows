<!-- split.warm.md — stage prompt template, rendered by the ferry.
     manifest values are ferry-filled absolute paths; optional entries may read
     "none (<reason>)". this prompt never states the session's spawn mode. -->


# stage: split (topic, author)

## manifest (read in order)

1. role card — binding, read first: {ROLE_CARD}
2. plan: {PLAN}
3. review standards — §6 (the eight granularity criteria you cut against) and
   §5 (risk classes); read those, not the whole file: {STANDARDS}
4. validation note: {VALIDATION}
5. prior split-check review (optional — present when re-entering on a flag or
   an accepted re-slice; absorb its findings/concurrence before re-cutting): {REVIEW}
6. ruling (optional): {RULING}

## goals

- the topic cut into slices by function, satisfying the granularity criteria of
  `review-standards.md` §6 — read them there, current text, before cutting.
- on disk and in the store: `charters.md` (one charter per slice under a
  `## slice <nn>` heading — later specs anchor into it by that heading, so the
  convention is load-bearing; per charter: intent, footprint, risk class with
  basis, **checkout binding — `code` or `doc`, one slice never spans both
  (`review-standards.md` §6); the project context names the declared
  checkouts; re-cutting cannot re-bind a standing id, so a slice whose
  checkout changes is a NEW id and the old one is omitted**, interference
  declarations, **plan binding — see the block below**) + the machine slice index (slices surface)
  + the terminal decomposition table (seams are design-knowable — pre-declare
  them) + the plan-hash pin.
- **the plan binding is machine-carried too.** each `## slice <nn>` section says
  which of the plan it binds, and the ferry derives that slice's plan excerpt
  from it — an author handed no excerpt reads the whole plan instead, which is
  what the excerpt exists to prevent. Two forms, and the plan's own shape picks:
  - the plan carries `# W-<id>:` item headings → name those ids in the section,
    as the section prose already does.
  - it does not → declare the section anchors, in the slice's own section:

        plan-binds:
        - §2
        - §4 切片 A（commit 1，先行独立）：route brief 点检查上提

    `§N` binds that whole numbered section, its numbered sub-sections included;
    `§N <heading text>` binds ONE subsection of it. **Quote the heading IN FULL,
    exactly as the plan writes it** — matching ignores whitespace and backticks
    but is otherwise equality, so an abbreviated or `...`-elided heading
    resolves nowhere and the emit is refused. One anchor per line, no separator:
    both `·` and `§` occur inside real plan headings, so any delimiter would
    collide with the text it delimits. Blank lines do not end the list; the
    first line that is neither blank nor a `- §` item does. One list per slice.
  **Name every section that binds, the shared ones included.** *"shared sections
  as slice 01"* is prose, nothing can follow it, and those sections are then
  absent from that author's excerpt. The emit gate resolves every anchor and
  refuses one the plan does not carry — the cheapest moment to find it, while
  you hold both documents. A plan with neither items nor numbered sections binds
  neither way, and `none (<reason>)` is then the correct outcome.
- risk classes per `review-standards.md` §5; behavior change is never low.
- **delivery order is machine-carried**: the id order is the delivery order,
  and every hard edge a charter states rides the index as an `:after=<id>`
  tail on the LATER slice's entry (each after names a strictly earlier id) —
  prose alone is machine-invisible and the scheduler will not honor it
  (`review-standards.md` §6).
- run the refine loop on the charters before emitting.
- if the manifest carries a ruling, discharge it and record how.

## discipline

- rules live in the role card and the referenced documents — follow their current
  text; nothing in this prompt overrides them or restates them.

## final action (required — the turn cannot end without it)

with the owed artifacts on disk, emit the completion record:

    {RECORD_SH} emit {WORKSPACE} --stage {STAGE} \
      --nonce <nonce from the volatile header> \
      --verdict <done> --confidence <HIGH|MED|LOW> \
      --refine-rounds <n> \
      [--refine-terminated-on <clean|bound>]   # owed when <n> = refine.max_rounds; below it clean is derived
      [--ruling-ack <slice>.<n>,…]   # owed only when a ruling landed after your spawn; the emit refusal names it
      --slices '<NN:low|med|high:code|doc:title[:after=NN,..]>;...'  # the machine slice index, one entry per charter; after = earlier ids this slice waits on

a Class U question instead replaces the verdict with `--halt class_u` (questions
batched, recommendation attached).
