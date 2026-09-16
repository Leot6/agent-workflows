# planning-workflow
<!-- Cap: DOC_CAP_README -->

A workflow template that takes a software topic from rough intent to an
**impl-ready plan** (`plan.md` at the topic root). **All locked content lives in
`design/architecture.md`** — §1 mission and generators, §4 locked vocabulary,
§5.3 the specification ledger, §13 settled rulings. This file is a map; the one
piece of operative text it owns is the kickoff line below (its home per §5.1).

## Status

Exercised on two live topics (the evidence landings and their dates live in
`iteration-log/` — INDEX and the debt ledger, one home each); the predecessor
is retired. Live state keeps its single homes there: restating any of it
here would be a staleness trigger with no update trigger and no checker, in
the file a newcomer opens first — the tree's own Status text once carried a
"never exercised" claim that had silently gone false, which is the
demonstration.

## The tree

| region | nature |
|---|---|
| `design/` | settled design: `architecture.md` (the authority) · `rationale.md` (autopsies, external anchors, honest ceilings in full) |
| `runtime-docs/` | agent-read at run time: `protocol.md` (stage protocol; cold/warm + lens tables; `§defaults` = single home of every tuning value) · `claims.md` · `prompts/` · `templates/` |
| `discussion/` | ALL informal material — gitignored, deletable as a unit, never referenced by finalized docs (by path or codename) |
| `self-check/` | the conformance harness — `check.sh` runs the tree's mechanical invariants (dev-time only; nothing here runs during a topic) |
| `iteration-log/` | state region: INDEX (one line per mechanism) · `open/` (one file per family) · owner-queue · debt ledger · model register · staging |

**Formal region** = this file + `design/` + `runtime-docs/`; **state region** =
`iteration-log/`. The formal region points at files, never at state rows,
and carries no dates — state rows prune, so the pointer would dangle, and
chronology is git's (`architecture.md` §5.1).

Per-topic runtime lives at `<PLANS_ROOT>/topics/<topic>/planning/`; the converged
`plan.md` sits at the topic root (`architecture.md` §5.2).

## Quickstart

```
# start a topic (fresh agent session; ALL paths absolute):
read <ABS>/workflows/planning-workflow/runtime-docs/protocol.md — start topic
<name>: topic root <ABS PLANS_ROOT>/topics/<name>/, checkout(s) <ABS repo path[; …]>,
topic statement: "<one paragraph of rough intent>"; begin at the first stage;
do not summarize; do not stop for confirmation before the first owner
touchpoint
```

The protocol carries the stage-by-stage duties; every round thereafter starts
from the close-out's fenced restart line. Owner touchpoints arrive batched as
Chinese briefs under `planning/briefs/` (`architecture.md` §10).

## Changing this workflow

Follow `architecture.md` §1 (admission discipline) and §11 (self-iteration;
template-edit timing; rollback path).
