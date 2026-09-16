# triage calibration ledger

One row per decided piece of work. The rule the rows calibrate is `README.md`;
who writes a row and when is in that file's `ledger.md` section, and so is this
table's main limit, repeated here because a table is read without its README:

> **The rows that fill themselves are the ones that already went through a
> workflow.** Delivery rows are copied from a close-out's governance report at
> harvest — its `routing outcome` block for the cost, its reviewer-coverage
> section for the review, and the maintainer's own reading for what the block
> refuses to classify; `direct` rows are hand-written by whoever did the work,
> because that lane never enters a tree and nothing derives anything for it. The
> question this card is most often wrong about is whether something needed a
> workflow at all — and that question is answered by the hand-written half. A
> ledger of nothing but heavy lanes is a ledger that cannot fail its own rule.

> **This table's format has a known ceiling, registered here so the migration is
> a decision rather than a scramble.** Five prose columns are readable at a
> handful of rows and stop being readable well before twenty. When a row's cells
> no longer fit, the payload moves to a per-topic section below and the row
> NAMES it — the shape the delivery tree already prescribes for a cell that
> cannot hold its content, and the same reasoning: a format that forbids what
> the content requires gets worked around silently, so the move happens on
> purpose or it happens badly.

> **Every figure in an outcome cell is a POINT-IN-TIME reading, and the command
> that produced it is named here so a stale one can be told from a fresh one.**
> The outcome column is copied from that topic's close-out governance report —
> two of its sections, not one:
>
> ```
> delivery-workflow/runtime-scripts/derive_report.sh <topic>/delivery
> #   `## routing outcome`     — the cost split and the review-driven commit units
> #   `## reviewer coverage`   — the rounds per stage and the precheck DRE
> ```
>
> Every figure in it is PAIRED STAGE TIME — spawn->record spans with parks
> dropped — and never wall. A topic's clock brackets every hour between its
> first spawn and its last record, which this workflow measured once at 128394s
> of "working" against stages summing to a fraction of that, so the two words
> are not interchangeable in a table meant to price a lane. And a row's total is
> written as the SUM of the buckets the block prints, never as a third figure:
> one row's first draft carried a total that no derivation produces.
>
> Re-runnable only while that topic tree exists — trees are cleaned after
> close-out — which is exactly why the row is copied here rather than left
> there. This directory's own rule is *derive it, quote nothing*; a ledger has
> to quote, so it names the derivation instead. A figure that appears in another
> document should point at this row rather than restate it: two headline numbers
> went stale in place in this repository's own history because nothing re-derived
> them, and nobody noticed for two topics.

> **The last column grades the CARD, not the person who used it.** A calibration
> table that reads as a scorecard on the router changes what routers write —
> a hedged verdict is harder to falsify and therefore scores better, which is
> exactly the verdict worth least here. A prediction recorded plainly and then
> contradicted by the run is the most valuable row this table can hold: it is
> the only thing that can move a threshold. Rows are read in aggregate, across
> topics, to ask whether the three questions predict what they claim to.

> **A verdict carrying a `|` does not go in a cell.** The route column holds the
> verdict verbatim, and a pipe inside a markdown cell splits the row — for every
> renderer, and for any `awk -F'|'` that ever reads this file. It is not an
> exotic input: the evidence for "every failure shape builds in a fixture" is
> naturally a command, and the occurrence-count idiom the delivery tree
> prescribes is `grep -o … | wc -l`. When a verdict carries one, put the verdict
> BELOW the table under the topic's own heading and let the cell name it —
> the same resolution that tree reached for the identical shape in its claims
> tables, on the same reasoning: escaping fixes the render alone, so the payload
> moves to where the format can carry it. This is the migration the ceiling note
> above already describes, arriving one row early.

> **A verdict reconstructed after the outcome was known is not a prediction.**
> Such a row still earns its place — the cost columns are real — but its last
> cell can only read *not scoreable*, and it is marked `[reconstructed]` in the
> route column so nobody averages it in with the rest.

| topic | route | the three answers | outcome | prediction held? |
|---|---|---|---|---|
