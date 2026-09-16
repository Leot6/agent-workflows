<!-- items/<id>.md — one work item per file, filename = item id (ids stay
     opaque, A§4). Risk/magnitude criteria live here once, shared by all items. -->

# W-<id>: <title>
- **sites**: `<path::symbol>` … + read ranges the executor is onboarded with
- **target repository**: <name>
- **risk**: low|medium|high · **magnitude**: S|M|L
  (risk: `low` = no behavior change, mechanical, grep-provable · `medium` =
  behavior change within one component · `high` = multi-component semantics,
  persisted/cross-process shapes, or public-API change; **a behavior change is
  never `low`**. magnitude: `S` = single-site, ≤~a day · `M` = multi-site ·
  `L` = crosses component boundaries or exceeds ~3 days — must be split or
  carry a signed bounded limit)
- **abort/rollback**: <command or procedure> — `passes when: …` / "none —
  <reason + the range read that establishes it>" (unconditional field;
  executable lines join verifier resolution)
- **edges**: `after W-x (authoring)` · `after W-y (runtime)` / "none — <the
  range read: the items whose sites or interface deltas were checked against
  this one's>"
- **depends-on**: [baseline rows]
- **interface delta**: by symbol — producers / consumers / admits-rejects
  delta / "none — internal only: <the range read — the consumer grep's scope
  and its printed, classified hits>"
- **migration/compat**: <persisted or cross-process shape changes: migration
  step, compat window, flag> / "none — <the range read: the persisted and
  cross-process shapes this item's sites touch>"
- **why current is insufficient**: traced path (today-behavior shape, cited)
- **acceptance**: `<command>` — `passes when: …` (adversarial corner named —
  acceptance-claim shape)
- **prescriptions**: every imperative this item hands the executor beyond the
  fields above — commit-message content, file placement, ordering, naming — each
  with the rule that judges it (`file:line`, gate/hook/convention, opened this
  session) and the words by which it admits what is prescribed (**prescription
  shape**) / "none — <the range read: this item's prose scanned for imperatives>"
- **decisions touching this item**: row `<id>` → executor fallback: … /
  "none — <the range read: the decision-log rows scanned>"
