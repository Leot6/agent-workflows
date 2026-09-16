# Slot: a fast lane for single-slice topics (registered, not built)

> A designed-but-deferred slot per the admission discipline both trees carry
> (demonstrated need from a real run, (c)). Built only when the first topic that
> decomposes to ONE slice has actually run and its ledger shows the ceremony as
> the dominant line item. Until then this file is the criteria draft, so the
> eventual build starts from a written position instead of a mood — the same
> shape as `tier.md`, one layer over.

## The harm it would prevent

A topic pays its topic-level ceremony — plan-validate, split, split-check,
close-out — at least once, and the middle two again on every flagged
split-check. Measured across every finished topic on disk, that loop drives a
sixfold spread and slice count does not. The FLOOR is what this slot turns on:
one round of each, which is what a single-slice topic pays. And the ceremony is
not waste — it is what makes the decomposition reviewable and the record
complete, and amortised over several slices even the floor is a modest share.
Amortised over ONE slice it is the whole overhead, paid to decompose a thing
into itself.

The unpriced half used to be that nobody could see the share. That is no longer
true, and it is why this slot is registerable rather than speculative: the
close-out governance report now derives the topic-level ceremony against the
per-slice work for every topic that runs. The first single-slice topic will
print its own answer.

The readings that exist come from multi-slice topics, and they are an upper
bound on amortisation rather than evidence for this slot. None is restated
here: a deployment's own rows in `../triage/ledger.md` name the command that
re-derives them. Restating one would make this file the second home for a
number nothing re-derives — the measured failure of two headline figures going
stale in place, unnoticed for two topics. What such a reading does NOT
give you is the figure this slot turns on — the same ceremony beside a SINGLE
slice's work — and scaling the three-slice one to get it is exactly the error
registering this slot early is meant to prevent.

## The design (criteria draft — what could collapse, and what provably could not)

The proposal is to collapse STAGES, not to reduce depth. That is a stronger move
than `tier.md`'s and needs a stronger warrant, so the draft starts by separating
what is genuinely ceremony from what is load-bearing.

| candidate | what it would mean | the obstacle a build must clear |
|---|---|---|
| plan-validate doubles as split | one stage emits the validation note AND the charter, index row and plan-hash pin | the ARTIFACTS cannot go. The slice index is what every downstream resolution reads — the repo binding rides the split grammar into it, and one admissibility rule guards both doors into that index. So the saving is one stage TRANSITION and nothing else — **not a cold session**, which the pricing below shows: `split` already runs warm inside plan-validate's, so the cold start is paid once whether or not the two collapse |
| skip split-check | no independent re-derivation of a decomposition of one | with one slice there is no decomposition to check — but split-check also re-derives the RISK CLASS independently, and the class is what modulates every depth below it. Dropping the stage drops one of three independent re-derivations (split-check, precheck, postcheck). Whether two suffice is a question for data, not for reasoning |
| skip precheck or postcheck | — | **out of scope, and not by preference.** Every slice gets both; genuinely tiny changes ride as commit-units inside a slice, never as slices of their own. That is a settled ruling and moving it is the owner's |

Where the no-skip ruling actually lives is worth writing down, because it is
easy to cite from memory and get wrong. It is the delivery tree's
`runtime-docs/review-standards.md` §5 (restated in its `design/review-and-slices.md`
§2), whose subject is the risk class — *a depth
modifier, never a skip switch* — and whose no-skip clause is scoped to **per-slice
review**: every slice gets precheck and postcheck. It says nothing about
topic-level stages. So this slot is not forbidden by that ruling, and a build
must not claim it is permitted BY it either: the ruling simply does not reach
here. What blocks the build is admission (c) — no data — and the fact that
collapsing a stage changes the transition table, which is an owner call.

**The two candidates are not priced alike, and the difference is the whole
decision.** Written out because the first draft of this paragraph gave a true
premise, a true conclusion and no step between them — a reader could have
derived the opposite just as easily.

- **Collapsing plan-validate into split saves almost nothing.** `split` is
  already a warm-author stage: it reuses the session plan-validate opened, and
  its warm median is **5m40 over 15 readings** against a cold **15m29 over 5**.
  So the cold start is paid once either way, and what a collapse removes is one
  warm stage transition — the cheap end of everything this tree measures.
- **Dropping split-check is the expensive saving, and what it spends is not
  time.** It is contract-cold at a **21m00 median over 21 readings**, and it can
  never be warm, because the independence is precisely what the cold session
  buys.

Those three medians were measured on the originating deployment with
`delivery-workflow/runtime-scripts/derive_cost.sh` over its archived topics.
Re-run it over your own before building on them — two figures of exactly this
kind once went stale while being quoted. So the collapse that looks smaller on the transition table is the one
  that costs a whole independent re-derivation, and the one that looks larger
  costs a few minutes.

The generalisation behind both: this tree's own measurements say a stage's cost
tracks whether the session already held the ground, **not** how big the artifact
is — four cold round-1 readings spread 2.82× across a 1.06× band of artifact
size, which is size explaining essentially none of the variance. That figure
comes from the same `derive_cost.sh` readings, and it is named here because it
once travelled without a home until an independent read followed it. A
build that reasons about this slot from artifact size will reason
from the wrong variable.

## External anchor

ITIL's *standard change* is the closest shape: a class of change whose risk
assessment is done ONCE when the class is defined, so each instance that matches
is pre-authorised rather than re-argued. The mapping is exact — a single-slice
topic would be such a class, and the criteria table above would be the one-time
assessment. The precedent also carries the failure mode: a standard-change class
defined too widely becomes an exemption list, and the discipline that keeps it
honest is that membership is mechanical and the class is re-reviewed against
outcomes. Inside this repo, `tier.md` is the sibling registration and the
contrast is instructive — it scales depth and skips nothing, which is why it
needs no ruling; this one does.

## Why not built now

Zero single-slice topics have ever run, so every threshold above is a draft with
no data behind it. The demonstrated need is specific and cheap to recognise: the
first topic that decomposes to one slice, whose close-out block shows the
topic-level ceremony as the dominant line item against that slice's own work.
That block is derived at every close-out now, so the evidence arrives on its own
rather than needing someone to go looking.

And the change is not this maintainer's to make regardless: collapsing a stage
edits the stage transition table both trees' records are interpreted through, so
it lands as an owner-ruled change with a validation-debt row until a second
topic exercises it — not as a maintenance commit.
