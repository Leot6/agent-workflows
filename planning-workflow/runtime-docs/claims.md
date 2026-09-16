# planning-workflow — claims discipline

> One discipline over every load-bearing statement, whoever wrote it — author,
> reviewer, a design doc being quoted, an owner reply being transcribed
> (A§1 clause 2). A statement's **grammatical shape**, not the writer's sense of
> care, decides which mechanical precondition applies: the failure mode this
> treats is that "I've read enough" and "I've read enough to write this
> sentence" are subjectively identical (measured — `../design/rationale.md`).
> Checked at rung 2 (emit-time, self-administered) and re-derived at rung 3;
> the architecture lens spot-checks `SPOT_N` items' worth of stamps.
> Cap: `DOC_CAP_CLAIMS`.

## The shape table

Every row: the trigger is the **grammar of the sentence** — if the sentence has
the shape, the precondition applies, no judgment call. A claim that cannot meet
its precondition is not written.

| shape | trigger grammar | mechanical precondition | measured failure this treats |
|---|---|---|---|
| **count** | "N call sites / N readers / exactly N …" — and **any counting command written into an artifact as evidence** (`grep -c`, `wc -l`, a piped tally): a cardinality living inside a command is this shape in command form and owes the same printed-hits form | print every hit and classify each one; state the grep scope (paths + pattern) **and the unit counted — `hit-lines=N occurrences=M`, both, since a line carrying the match twice makes them differ**. `grep -c` and line spans count nothing you have seen. The command that produced the hits carries a **positive control** — the same command shape aimed at something known to be there — and a control that comes back empty convicts the command, never the tree | "readers: exactly 2" — was 3; the grep covered 4 named files, not the tree. And `git grep -F <pat> <SHA> -- $FILES` returned 0 without error under zsh, which does not word-split an unquoted expansion, so the whole list became one pathspec; the same query under bash returned 75. And two lenses reported one defect as **2** and as **4**, both correct and neither wrong — hit-lines vs occurrences (`:17` ×1, `:48` ×3); the reader merging them had to discover the unit difference unaided. And a bookkeeping command's `grep -c` returned **0** while the substance it recorded was true — the prose trigger never fired, because the cardinality lived inside the command, not in a sentence (measured on a live round) |
| **absence** | "no X / never / none / zero hits / nothing does Y" | state the full range read — construct start to end, file extent, or grep scope with hits printed. No range ⇒ the claim does not hold. A zero-hit result carries the positive control the count row requires: **a command that failed silently and a tree that genuinely has none are the same screen** | "zero assertions on that path" — the skipped message carried 4. And `grep -rn <pat> .` returned 0 hits on a doc tree that contained them — recursion from `.` reached nothing, and the run looked exactly like a clean absence |
| **invariant / equality** | "X always equals / never exceeds Y" | an invariant claim **is** an absence claim ("no path breaks it"): enumerate the writers/adjusters of **both sides** before calling it invariant | a doc-labelled "rigid chain" (`=`) whose code writers legitimately produced `<`; doc-internal consistency masked it |
| **today-behavior** | "currently the system does X / scenario S ends in Y" | trace the execution path entry → exit and cite each branch taken; inference from nearby code is not a trace — the artifact that already answers it is always findable | "conflicted pairs are silently mirrored today" — the in-line gate made them hard failures; a path trace hits the gate directly |
| **citation** | any `file:line` / `file#symbol` reference | opened **this session**; a citation carried from a prior round, another artifact, or memory is re-opened or dropped — never forwarded | a condition cited at the wrong file for two rounds because the reference rode along unopened |
| **family** | "the dependencies / members / cases of shape S" | on first sighting of the shape, enumerate the **whole** family in the same pass and ground each member; one-member-per-round discovery is a process failure | four same-shape external dependencies caught across four separate rounds — one each |
| **fix claim** | any fix, gate, or predicate about to be baked into a draft | trace by symbol before baking: (a) every **producer** of the symbol keyed on (a composite enumerates each contributor), (b) every **consumer** of the predicate added, (c) the **admits/rejects delta** as an input region. Also the plan's interface-delta field (A§4) | a guard keyed on a composite floor (a `max()` of four raisers) traced as one — it nullified a stability buffer on every raiser |
| **acceptance claim** | any gate, fixture, or command offered as proof a thing works | name each parameter and pin its **adversarial corner** (or a cross-product) — a hand-picked passing point is a masked region, not a proof; every plan command carries "passes when …" | a fixture pinned the passing lower half of a parameter while the upper half broke, masking a phase for a full round |
| **prescription** | any **imperative** the artifact hands an executor — "give X in the commit message", "put the README edit in this commit", "run it before Z" — as opposed to a sentence asserting something | open the rule that will judge the act — the target repo's gate, hook, or written convention — read to its terminator, and confirm it **admits** what is prescribed; cite it `file:line` opened this session. An imperative asserts nothing, so **no other row here fires on it**, and the collision surfaces where the executor meets the gate — after the plan is signed, where it costs a rewrite rather than an edit | a plan bullet ordering "give the case name, the selfcheck's before-and-after output and a gate summary in the commit message" against a `commit-msg` hook that refuses any body outright ("the commit is never created, so there is nothing to amend") — while the *assertion* the same section made about the same hook family was caught by the today-behavior row. Second anchor, same plan, different stage and lineage: an instruction to put a README edit inside a relocation commit whose governing whitelist enumerates what it covers and closes with "and nothing else" |
| **carried text** | any decision, ruling, table, or translation moved between artifacts | re-derive from the source, or check the copy against it token by token; state which. A gloss/translation is carried text — its checker is the next cold reviewer | a five-ingredient decision lost a conjunct in transcription; the plan shipped the weaker rule |
| **decision claim** | any owner statement about to be baked anywhere | re-derive **the premise first** (does the reality it asserts hold against code?), the landing site second; one rederivation record per reply (A§2). An owner reply is provenance-required, not self-certifying | a reply's central premise reversed observed code; only its landing site had been checked — six recommits of the same miss |

## Five rules that follow from the table

1. **Background prose is claims too.** A framing sentence in a brief, a
   "why the current system is insufficient" row, a summary paragraph, a
   caveat — each has a shape and owes its precondition. Schemas that covered
   only the findings table produced verified tables under false summaries
   (measured, twice).
2. **A proxy is never the artifact.** A count instead of the hits, a
   downstream evidence file instead of the code, a remembered citation instead
   of the file, a filename instead of the file's contents, a remembered
   number instead of the command's printed hits — every measured
   citation/count error rode one of these. The precondition is always against
   the **primary** artifact at the pinned baseline.
3. **Read to the structural terminator.** Table: past the last row. Section:
   to the next heading. Function: to the closing brace. List: past the last
   item. The most common miss: the passage answers its own question two lines
   below where the reader stopped.
4. **A state table is not a parseable format.** The decision log, the baseline
   card and the close-outs are read by eye *and* by script, and their cells
   routinely carry `|` — code fragments, `supersede | reaffirm`, whole grep
   commands. Markdown's `\|` escape means something only to a renderer, so
   `awk -F'|'`, `cut -d'|'` and `split('|')` all mis-split. Two conditions,
   **both required**: split only at *unescaped* pipes, **and** take the field
   by value from its closed vocabulary — failing that, anchor it from the row's
   **end**, never by counting from the start. Measured three times, and each
   condition alone failed once with the other in place: an escaped `supersede
   \| reaffirm` turned a row into 13 columns, and an *unescaped* pipe inside
   backticks defeated escape-aware splitting on a row read for its severity.
   Where the field is neither end-anchored nor drawn from a closed vocabulary,
   no split is safe and the field belongs outside the table.
5. **A current-state claim about a live file is falsified by the next write
   to it — a count of this document is the narrowest case.** "Three
   rules", "ten shapes", "steps 1-6", "45 rows" — a cardinal describing the
   artifact it sits in stays true only until someone extends what it counts,
   and whoever reads the diff never sees the head where it was declared. So:
   grep the head for the cardinal **before** extending an enumerated
   construct, and print the **whole construct** and recount after — never the
   diff. Measured six times in one session, one of them inside a check written
   that day to catch this; twice more while editing this file. Prefer the form
   that cannot rot — a re-runnable command, or a check that counts the members
   and compares them against the declaration.
   The rule reaches past self-description: "the only row of shape S", "none
   of X", "all members are Y", a reading of the decision log or the card —
   each is falsified by the next write to that file, and **a ruling's
   signature is itself a write** (measured over two rounds: signing
   two rows staled two evidence cells that read the decision log in the same
   sitting — a deferral count 1→2 and a carrier count 0→2; an aggregate
   card-state assertion went false at the version boundary three generations
   running; a frozen pointer to a one-shot script died on arrival). The form
   that cannot rot is the **live-claim**: the re-runnable command stated, the
   reading taken at the moment of use — freeze readings re-taken at freeze,
   never transcribed from a prior round — and the positive control on the
   same basis as the claim it controls.

## Where the discipline is enforced

- **Rung 2 (emit-time, self-administered)**: the writer walks each
  load-bearing sentence against the shape table before an artifact leaves a
  stage; evidence fields (scope, hits, ranges, traces) are template columns,
  not prose — a row missing its evidence field is incomplete by schema.
- **Rung 3**: verifiers re-run evidence commands ("never trusted"); reviewers
  re-derive load-bearing claims and spot-check stamps; the executor lens
  re-reads the plan's claims as a consumer.
- **Ceiling** (A§14): rung 2 is self-administered — presence of a stamp is
  checkable by its writer, truth is not; that is what rung 3 exists for.
