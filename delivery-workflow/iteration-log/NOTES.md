# delivery-workflow — iteration log: harvest notes and rulings (narrative)

> The narrative half of the durable home: harvest notes, corrections, owner
> rulings, governance reports and the `harvest-completion:` ledger — the things
> a reader needs in the order they happened. Every machine-read fact about a
> mechanism (status, hook, anchors, landing) lives in its `entries/<id>.md`
> head block, and `INDEX.md` is generated from those; nothing here is a second
> home for a row. `97-iterlog` reads this file for the harvest ledger (each
> `Harvest N` block owes its `harvest-completion:` line, whose stamps must
> resolve to INDEX rows) and reads INDEX for the rows. Blocks are appended
> below, oldest first.

> **Harvest conventions.** A harvest carries every record on the topic's
> observations surface into exactly one entry, and the completion test is the
> RECORD COUNT, never the stamp set — a `t=` stamp is not a record identity
> (two records filed in the same second share one, and they can belong to
> different mechanisms):
>
> ```
> grep -c '^v=1' <ws>/.runtime/state/observations   # must equal the records carried
> ```
>
> Where a stamp is shared, the anchors disambiguate it as `<stamp>(rec N)`, N
> being the record's ordinal on the surface. Each harvest opens a block
> `> **Harvest N (<date>, <topic>)** …` and closes it with one line:
>
> ```
> > harvest-completion: harvest=N topic=<topic> records=<n> rows=<n> stamps=<t> <t> …
> ```
>
> The stamps are the printed instance set: `97-iterlog` resolves each against
> the INDEX rows, so a record counted and not carried reds by name. Harvest
> while the topic tree still exists — the tree is cleaned after close-out, and
> what has not reached this directory by then is gone.
