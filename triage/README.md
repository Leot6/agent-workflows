# triage — which lane a piece of work takes

A deployment-layer document, per `../README.md`: it decides which **tree** a
piece of work enters, so it can live in neither of them. Both workflow trees are
forbidden to reference it and nothing here is required by either — a tree copied
out on its own still works, and still cannot see this file. The direction is
one-way throughout: a project's binding document points here, this file points
at the two trees' entry points, and neither tree points back.

**The rule in one sentence: governance scales DOWN only under evidence, never
under confidence.** All three questions below must read *yes, evidenced* before
work drops to the `direct` lane. Any **no** routes up — and so does any question
you cannot evidence, because an unevidenced criterion is a **no**, not an
unknown.

**Before you can use the card at all, find your project's binding document.**
All three questions are questions about a SPECIFIC project — which authority
documents rule, which fixtures exist, who owns which code, which size door
applies, where a task card goes — and this file deliberately holds none of that,
because it is read by whoever is deciding about whatever project they are
deciding for. The binding document is the project's, it points here for the
rule, and it is what makes each question answerable with evidence instead of
impression. If your project has none, that is the first thing to fix: without it
Q1 and Q3 cannot be evidenced, every question therefore reads **no**, and
everything routes up — which is the correct behaviour and an expensive way to
live.

## The card

Written in the **negative**, which is the shape the prior art converges on: the
useful thing to enumerate is the work that does NOT need a workflow. That list
is short, checkable, and stays honest as a project grows, while a list of what
DOES need one goes stale in silence. Both halves are quoted rather than
summarised, because the wording is the argument. Kubernetes' KEP process:
"SIGs may find it more helpful to enumerate what *does not* require a KEP, than
what does." Rust's RFC README lists the classes needing none in its own words —
"changing shape does not change meaning"; "additions that strictly improve
objective, numerical quality criteria"; "additions only likely to be *noticed
by* other developers-of-rust, invisible to users-of-rust". ITIL 4's *standard
change* is the same move one step further: the risk assessment and authorisation
happen once, when the procedure for the class is created or modified, and are
explicitly not repeated for each instance that matches it. The class is
pre-authorised; the instance is not re-argued.

| # | question | yes ⇒ | no ⇒ |
|---|---|---|---|
| 1 | **the shape is forced** — the authority documents plus the code as it stands admit one design, and you can name the nearest alternative **and the line that eliminates it** | no planning tree needed | `planning + delivery` |
| 2 | **writable and buildable** — a plan could state every interface at signature level, and **every** failure shape can be produced in a self-check fixture *and survives being run against the artifacts that already exist*. Multi-machine interaction, another system's behaviour, and timing all count as *cannot build* | review buys artifact consistency and test completeness | `delivery` — an independent cold reviewer is the only instrument that sees what no fixture can produce |
| 3 | **two-way door** — one repository, one seam; a single revert restores the whole; no logic owned by someone else; nothing waiting on a contract another party must confirm | it can be light | `delivery`, or `planning + delivery` where the door is one-way for a reason other than size |

**Size is an input to question 3, never a lane of its own.** Work inside the
project's own commit-size door is a candidate for `direct`; needing more than one
commit, or more than that door allows, needs at least a plan.

**The italic half of Q2 is the one clause here written from a measured miss, and
it is why "we have fixtures for that" is not evidence.** A fixture family carries
the failure shapes its author thought of. The artifacts a project has already
accumulated carry the ones nobody did — a field written empty by a version of
the writer that no longer exists, a value shape retired before the fixture was
conceived. Answering Q2 *yes* on a fixture family that has never met them is the
commonest way this question reads yes and is false. Run it against what exists,
or answer *no*, which routes up.

Two of these are borrowed arguments, and the source is given rather than
gestured at — a document meant to outlive its author owes a reader the ability
to check it. Named, not linked: the URL is the half that rots, while a title and
a quoted sentence stay findable.

- **Q1 is the design-document question.** Malte Ubl, *Design Docs at Google*:
  "If a doc basically says 'This is how we are going to implement it' without
  going into trade-offs, alternatives, and explaining decision making (or if the
  solution is so obvious as to mean there were no trade-offs), then it would
  probably have been a better idea to write the actual program right away." A
  design is worth converging when it is genuinely ambiguous, and naming the
  nearest alternative plus the line that kills it is the test for whether it is.
- **Q3 is the two-way-door question.** Jeff Bezos, 2016 shareholder letter: most
  decisions are reversible two-way doors that should be made quickly by people
  with good judgment, and the standing failure of an organisation as it grows is
  to run them through the heavyweight one-way-door process anyway — buying
  slowness and timidity with no reduction in risk.

## The three lanes

- **direct** — edit under lightweight review. Governance is whatever task card
  the project's binding document names, the project's own gate set, and one
  independent read of the diff if any shipped behaviour can move.
- **delivery** — a compact plan, then the delivery tree over it. The design is
  forced and single-seam; the work simply does not fit in one commit.
- **planning + delivery** — the planning tree converges a plan first, then
  delivery runs it. Design freedom, a cross-seam or contract change, an
  authority document to supersede, a new concept — or any question you could not
  evidence.

One verdict per **separable** requirement; an inseparable bundle takes the
highest lane among its members. A route stated by the owner binds unless your
evidence contradicts it — then surface the contradiction, never re-route
silently.

## The verdict is written down, or it did not happen

Saying it in an intake conversation is not a record. The grammar — one line,
which is exactly the line the delivery tree copies and prints:

```
route: <direct|delivery|planning+delivery, or the short code the project's binding document defines> — Q1 <yes/no + the authority passage, or the nearest alternative and what eliminates it>;
  Q2 <yes/no + the fixture family that builds every failure shape, or the shape it cannot build>;
  Q3 <yes/no + repositories · seams · logic owned elsewhere · external contract>;
  est <files · order of magnitude in lines · repositories>; risk <the one thing most likely wrong, and what evidence would raise the lane>
```

**One character to avoid in a verdict: `|`.** The verdict is copied verbatim into
a calibration table, where a pipe splits the row. If your Q2 evidence is a
command containing one — and the natural form of an occurrence count is
`grep -o … | wc -l` — name the command rather than inlining it, or expect the
row to move below the table.

**That block is a grammar, and copying it as a template records nothing.** A
`route:` inside a fenced block is skipped by the readers on purpose — this file
is exactly why the skip exists, since the rule is documented as a fenced sample
and pasting the sample into a preamble is the obvious move. Write the line
unfenced, in your own words, with your own answers.

Where it goes:

| home | written by | read by |
|---|---|---|
| the plan preamble, before the first section heading | whoever authors the plan | **printed** at close-out by the governance report (mechanical, and tested); **transcribed** into the plan-validate validation note by the author, per their role card (a duty, not a program) |
| the delivery adapter's `route=` key | whoever launches delivery | the same two, the same way |
| for the `direct` lane, the first line of the project's task card | the person doing the work | nothing mechanical — this lane never enters a tree |

**Those two readers are not the same kind of thing, and the difference decides
what you can rely on.** The close-out print is a program reading the plan and the
adapter directly: it happens or the report says why. The validation-note copy is
an instruction in an agent's role card — no program performs it, no gate refuses
its absence, and as of this writing no topic has ever run under it, which the
delivery tree carries as its own validation debt. Rely on the print; read the
note's copy as a transcription, with a transcription's failure modes.

The two machine-read homes are both optional, carry the same fact, and **neither
takes precedence**: whatever exists is copied with its source labelled, and two
that disagree are printed as a disagreement rather than resolved by a rule. A
home left present-but-blank is a third state and is reported in the words you
will see in the report — `declared, not filled` — because writing `route:` and
stopping is not the act of writing a verdict down, and neither is the same as a
file nobody could read. Undecided means leave the line out; a
blank one records the intention to record and nothing else. Put
it in the plan when the plan is being written; put it in the adapter when the
plan is already pinned, or when there is no plan author but you. The delivery
tree never parses the value — the vocabulary is this file's and the project's,
and a driver that interpreted it would own a rule it cannot keep current.

## Price: derive it, quote nothing

No figures are written here, deliberately. A number in a document that nothing
runs is stale the day after it is written, and there is no reader at this layer
who would notice. Two derivations, both over topics that actually ran:

```
delivery-workflow/runtime-scripts/derive_cost.sh <topic-dir>...
```

per-stage medians, totals and the cold/warm ratio across whatever topics you hand
it — one live workspace, or every archive you still have.

And the `routing outcome` block of any finished topic's close-out governance
report (`delivery-workflow/runtime-scripts/derive_report.sh <workspace>`), which
carries the split a lane choice actually turns on: the **topic-level ceremony**
against the **per-slice work**. Ceremony is the closest thing to a price of
admission, and it is **not one number**: it is one round each of the four
topic-scope stages plus however many times a flagged split-check sent the split
back to be redone, so a narrow contested topic can cost several times a wide
uncontested one. This section said the opposite until the block was run over
every finished topic on disk. Read it across SEVERAL of them, with the span
count beside each figure, and take the low end as the floor a fast lane for
single-slice work would have to beat — one topic's ceremony is that topic's, and
quoting it as the lane's price is the mistake this section exists to prevent.

**With no finished topic there is no price, and that is a real answer rather
than a failed command.** The first piece of work routed under this card is
priced by nothing — both derivations read topics that already ran. Route it on
the three questions alone, and let it become the first row of the ledger. Any
figure quoted from elsewhere in the meantime is somebody else's project, and the
one thing this section refuses to do is let a number stand in for a measurement
of your own.

## `ledger.md` — the calibration table

One row per decided piece of work: the verdict, the answers it rested on, what
the run turned out to cost, and whether the prediction held. It is the only
thing that turns the card above from a set of opinions into thresholds someone
has checked.

**Who writes a row, and when.** The duty lives here because it can live nowhere
else — neither tree may reference this file, so neither tree's maintenance rules
can name it:

- **work that went through the delivery tree** — the maintainer, at harvest,
  while the topic tree is still readable. The close-out author has pasted the
  whole governance report into that topic's `closeout.md`; **copy from it, never
  recompute.** But the outcome column is not one block of that report, which
  this file claimed until the claim was checked against the table's own only
  row: the `routing outcome` block carries the cost split and the commit units a
  review drove, the **reviewer-coverage** section carries the review rounds and
  the precheck DRE, and the block deliberately refuses to classify a unit's
  files as test or production. That classification, and any escape the topic's
  own review records, are the maintainer's reading and belong in the cell as
  theirs.
- **work that took the `direct` lane** — whoever did it, by hand, when it is
  done. That lane never enters a tree, so nothing derives anything for it.

**That asymmetry is the table's main limit, and it is stated on the table
itself.** The rows that fill themselves are the ones that already went through a
workflow; the question this card is most often wrong about is whether something
needed to. A table of nothing but heavy lanes cannot answer that. The `direct`
rows are the expensive half to collect and the informative half to read.

A verdict reconstructed after the outcome was known is not a prediction and the
row must say so. It still earns its place — the cost columns are real — but its
"prediction held" cell can only ever read *not scoreable*.

## What this directory is, and is not

Documents. **There is no harness at this root.** The self-check suites live
inside the trees and cannot see this file, by the same boundary that stops the
trees referencing it, so nothing here is verified by anything: it is kept current
by the maintainer's harvest discipline, and a row nobody adds is simply missing.
**What that costs, concretely, so it is a known risk and not a vague one**: this
directory cites the delivery tree by name — the two derivation scripts
(`derive_cost.sh`, `derive_report.sh`) and the two report sections a ledger row
is copied from (`routing outcome`, `reviewer coverage`) — and a rename or
removal there rots every one of them in silence. No count is given, and that is
deliberate: the first version of this sentence carried one, and later edits in
the same round added citations without touching the number, which is exactly
the failure the delivery tree's own rename warning removed its count for. You
would notice by running one of the printed commands and finding nothing.

A checker IS structurally possible, and is registered rather than built. It would
live here and reach into the trees, which is exactly what `twin_diff.sh` already
does one directory up — the layout forbids a TREE reaching out, not the root
reaching in. It is unbuilt because no citation has rotted yet, and this directory
holds itself to the admission discipline it asks of everything else: demonstrated
need from a real event, not a plausible one. The delivery tree carries the other
half of the bargain as a note at the block itself, telling whoever renames it
that three files here need editing.

## Project binding

Who owns which files, which gate set applies, where the commit-size door lives,
where a task card goes, and any short codes a project prefers for the three lanes
— all of that belongs to the project's own binding document, which points here
for the rule. Nothing project-specific enters this directory: it is read by
whoever is deciding, about whatever project they are deciding for.

**What this card does NOT govern: work that maintains a WORKFLOW TREE itself.**
The lanes route work INTO a tree. Changing a tree is governed by that tree's own
maintenance rules — a maintainer acting outside every run, between rounds,
single-purpose, under that tree's admission discipline, with the owner signing
what only the owner may sign. Each tree states those rules for itself, and this
is the one governance question the front door hands back rather than answers.

For `delivery-workflow/` that is not a division of labour but a mechanical fact.
Its launcher refuses to start over a dirty workflow subtree, and every stage
re-pins that subtree's hash — so a topic whose commit units edit the tree it is
running on dirties its own pin at the first unit and parks itself. **There is no
lane to route such work into.** The asymmetry is the half worth carrying: the
pin is scoped to one directory, so work on the *other* tree, on this deployment
layer, or on the scripts beside it is an ordinary project a topic can run, and
it takes this card like anything else.

**What crosses the boundary is the questions, not the lanes.** Q1's *name the
nearest alternative and the line that eliminates it*, Q2's *fixtures and the
artifacts that already exist*, Q3's *blast radius* are worth asking of a tree
change too — asked there under the names that tree already uses, by whoever its
rules put in the chair. Applied honestly to one recent maintenance round this
card returns `planning + delivery` while the round ran `direct`, which is a real
argument about how much scrutiny tree work deserves and no argument at all about
which lane it enters. Borrowing the questions is not entering the lanes, and only
the second is what this card decides.
