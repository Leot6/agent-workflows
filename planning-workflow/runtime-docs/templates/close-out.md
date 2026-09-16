# Close-out — `rounds/<n>/closeout.md`  (template; cap `DOC_CAP_TEMPLATE`)
<!-- A later close-out in the SAME round is closeout_<k>.md, k sequential —
     never overwrite a prior one (protocol §4.9). -->

## Round summary
Round <n> (<stage span>) · **arc**: initial / full-amend from row `<id>`,
entry round `<n>` — the budget counter's origin, the input §4.6.4's
scope-brief branch reads; a stateless author cannot re-derive it, so it is
recorded, not inferred · plan version dir: <v> / — (round 0) · pinned SHA(s): <per repo> ·
**workflow SHA**: <`git -C <ABS workflow> rev-parse HEAD`> — the card pins the
code this topic reasons about; this pins the rules it obeys. Prompts
self-record by instantiation, so a reviewer's mandate is recoverable from its
persisted file; `protocol.md` and `architecture.md` are read live and record
nothing, which is why a resuming session cannot otherwise tell they moved
under it · lenses run /
skipped (+reason, per protocol §3): … · instrument failures / re-spawns
(what, why, recorded per protocol §4.5.3): … / none ·
**delta review** (candidate rounds only — the single `arch` dispatch that
discharges A§8's shipping invariant for a non-semantic delta; a cold reader
cannot otherwise tell this arm from "no delta"): n-a / dispatched on
`plan_v<k>`, returned clean / dispatched, returned <n> findings ·
**trend-halt observation arm** (A§8, once per arc): available / spent at
round <n> — a later halt in this arc has only the scope-brief arm

## Settled-state table (the cold author's entry point, A§8)
| settled fact (one line) | pointer (row / record / section) |
|---|---|

## Open-findings register (the canonical open set; layer stripped in the reviewer-facing copy)
Ids are round-qualified (`arch-1@r2`): lens ids repeat every round, and A§8
walks the canon **by pointer through this table**, so the source column is
what makes the verbatim finding reachable from a one-line paraphrase.

| id (`<lens>-<n>@r<k>`) | one-line statement | layer | class (`product`/`provenance`/`doc-sync`/`artifact` — instrument-assigned, no author downgrade) | family (for recurrence tracking) | **landing** (item file + edit summary + evidence pointer — the discriminator's construction-form test reads THIS column, §4.6.4; "—" = no landing instruction yet) | source (verbatim text) | why still open |
|----|--------------------|-------|-------|-------|-------|----|----------------|
| arch-1@r2 | … | … | … | … | … | `rounds/2/findings_arch.md` | … |

## Round metrics (REQUIRED — mechanical counts, not scores)
**Cumulative for the whole round**, every stop included — not this
close-out's slice; §4.6.4 reads the highest-k row as the round's total.
**Substantive count** (the trend rule's input) **= new structural + new
rule** from every instrument the round dispatched — the lenses **and the
closure-proof assignment**, whose findings are the most diagnostic evidence
a loop is stuck and so cannot be outside the number that decides whether to
halt; severity definitions live in `findings.md`.
Carried findings, wording, R-Q rows and owner-sourced findings carry their
own fields below and are **not** trend input.

new findings **per instrument** — one line each, for every instrument the
round dispatched; the trend rule sums only those both rounds ran, so an
unattributed total cannot be its input, and a finding from no instrument
(owner-prompted, author self-check) has no line here and is not trend input:
  <instrument>: structural <n> · rule <n> · wording <n> · **mandate
  coverage <m>/<M> classes run** — dispatched mandate classes vs actually
  executed; a return that halted at the drift audit or died null ran 0. A
  dead dispatch and a quiet round differ in this field, not in the finding
  counts, and the halt diagnosis reads this field to tell them apart
  (measured: five instruments at zero
  coverage produced 6 findings and read as "3→4, worsening" while a whole
  review round was wasted; the same round's re-dispatch at full coverage
  produced 12)
totals: structural <n> · rule <n> · wording <n> | **per class**:
  product <n> · provenance <n> · doc-sync <n> · artifact <n> (owner 裁定:仪器赋值的 class 列,决策信号,门不读它) | carried: <n> |
register delta: +<n>/-<n> | `foundations` items: <n> |
owner items emitted: <n> this round / <n> cumulative (A§10 — the queue into
the scarcest instrument, reported so it can be managed) | recurring classes
(family column, ≥`RECUR_MIN` rounds): <n> — nonzero meets the closure-proof
declaration trigger (A§3)
Final close-out (retro) additionally: escape count <n> (full-amend rows whose
cause predates convergence — A§11) · metrics history: <one line per round>

## Workflow observations (REQUIRED — "none" explicit; A§11)
A trend-halt diagnosis lands here (A§8) and needs the last two columns: the
expectation is what makes it falsifiable, and the verdict is where the next
round answers it — otherwise "falsifiable" is a word with no carrier.

| obs | what the workflow did / failed to do | suspected mechanism | falsifiable expectation (halt diagnoses; else n-a) | verdict on the prior round's expectation (held / did not hold / n-a) |
|---|---|---|---|---|
| … / none | | | | |

## Zero-context field (REQUIRED)
What would a zero-context author miss resuming from these artifacts alone;
"none" explicit: …

## Next
Resume stage: <stage> / **none — terminal** (`converge` | `abandoned`, row
`<id>`; §0.4's terminal test reads this field, so a terminal topic must say
so here — the entries then are a new `amend` or `retro`) · waiting on:
[brief sections / verifier / nothing] ·
convergence-candidate declaration for round <n+1>: yes/no (allowed only when
the register above is empty)
Split close-out only: one kickoff line per child (README's kickoff variant,
quoting the signed split row's statement — protocol §4.8) / n-a
Final close-out only: retro steps 2–5 and 7 are the maintainer's (the
author's 1 and 6 are done here) — the handoff is the fence below, which on a
terminal close-out carries §7's maintainer variant. Stated once, there.

<!-- The fenced line below is the file's LAST content — it IS the restart
     handoff (A§4); nothing may follow it. On a TERMINAL close-out (Next says
     "none — terminal") this fence carries protocol §7's maintainer variant
     instead of the topic line below: there is no stage to resume, and retro
     steps 2–5 and 7 are what follows. -->
```
read <ABS workflow>/runtime-docs/protocol.md — resume topic at <ABS topic root>, checkout(s) <ABS path[; ABS path…]>, stage <stage>; do not summarize; do not stop for confirmation before the first owner touchpoint
```
