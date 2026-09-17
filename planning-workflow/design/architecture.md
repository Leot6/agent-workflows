# planning-workflow — architecture
<!-- Cap: DOC_CAP_ARCH -->

> Settles the design: mission and generators (§1), the three sources of truth (§2),
> roles and instruments (§3), vocabulary (§4), file layout and the specification
> ledger (§5), topic flow (§6), the instrument ladder (§7), loop control (§8), the
> boundary contract (§9), the owner interface (§10), self-iteration (§11), the
> language rule (§12), the settled-rulings registry (§13), and the honest-ceiling
> index (§14). Measured evidence behind every "(measured)" pointer: `rationale.md`.
> Executable per-stage detail and every tuning value: `../runtime-docs/protocol.md`.

## 1. Mission, generators, admission

**Mission.** Drive a topic from rough intent to an **impl-ready plan** — the
boundary artifact `plan.md` at the topic root — with every claim surface verified
and every owner-gated decision (§4) actually signed. **Impl-ready** means: an
implementation phase can pick the plan up and execute it without coming back to
re-plan; §9's convergence gate is its operational definition. How the plan is then
executed is out of scope.

**Generators.** The map is **total over sections** — every section has exactly one
generating home, with exactly two additions declared here: clause 2 also
generates §2's claim shapes, and clause 3 also supplies §3's instrument
discipline (its cast is clause 1's); a new mechanism must land in one of these homes (and §5's specification
ledger names what each home deliberately delegates to a lower layer):

| home | sections it generates |
|---|---|
| clause 1 — three sources of truth (the **cell rule**: one extraction + one verification instrument per source) | §2, §3 |
| clause 2 — one claims discipline | the claim shapes in §2; `claims.md` |
| clause 3 — instrument ladder | §7 |
| clause 4 — stateless author | §8 |
| clause 5 — self-iteration | §11 |
| mission boundary | §5, §9 |
| §13 owner rulings | §10, §12 |
| governance of this document | §1, §4, §6, §13, §14 |

**Admission discipline** (standing; applies to every mechanism and all future
additions): a mechanism enters only with (a) the harm it prevents named, (b) an
argument why the existing structure does not already absorb it, (c) demonstrated
need from a real run, (d) a home in the map above, and (e) a row in §14's ceiling
index. Prose rules additionally need recurrence at ≥`ANCHOR_MIN` independent
anchors (different author/framing state). Exactly **two carve-outs** from (c): (i)
a **gate-class defect** — one a mechanical check could have caught — gets its
check at the *first* escape; (ii) an **owner-directed seed** — recorded in §13,
carrying validation debt until a live topic exercises it. Promotion preference:
**structural > schema > prose**.

## 2. The three sources of truth *(clause 1; shapes are clause 2)*

| source | extraction | verification |
|---|---|---|
| **reality** — code @ pinned baseline | **baseline card**: every load-bearing fact one row — claim · shape · evidence (shape-keyed fields) · falsification target ("if this is wrong, where would code prove it" — that site opened) | **baseline-check** (independent): a no-lineage verifier re-derives every `unverified` row and writes a check record the author may not edit; row-state flips cite it. Mandatory for every topic — no exemptions; the exemption judgment is itself the kind that fails silently |
| **intent** — the owner | **grill**: after the design sketch, the author interrogates the owner — numbered questions batched by settled prerequisites, each with a recommended answer — until every branch is `decided`, `deferred`, or reclassified `reality-gap` | **shared understanding** (owner-arbitrated): the author states its model of what is wanted as claims the owner vetoes line by line — the design doc's SU section standing from round 0, and every brief item's worked example (§10), the same test fired per decision. Only the owner can arbitrate whether the author understood the owner; no other instrument here has that standing |
| **the plan** | authoring under the claims discipline; every proposed change carries a **"why the current system is insufficient"** row — a traced execution path, never an unbounded absence claim | **review rounds** (independent): no-lineage reviewers on the locked lens set (§3), selection per protocol's lens table; the **closure-proof assignment** supplements a round when declared (§3) |

`claims.md` defines eleven claim **shapes**; three of them govern the plan
surface directly (checked at rung 2 and by reviewers): a **fix claim** (a fix is a new, unreviewed claim — producers /
consumers / admits-rejects delta, by symbol; also the plan's interface-delta
field, §4); an **acceptance claim** (a plan gate or fixture — the adversarial
corner of each named parameter, never a hand-picked passing point; every plan
acceptance command names the corner it probes); **carried text** (any decision,
ruling, or translation moved between artifacts — re-derived or checked against
its source, never forwarded; the English gloss of a Chinese ruling is carried
text, re-derived by the next cold reviewer).

**Evidence hierarchy** (binding on every claim): `code @ pinned baseline` >
`owner-signed decision rows (§4 — design-section approvals included)` >
`unapproved design text and all other documents` — the last is hypothesis to
verify: any doc claim the plan will bear weight on is re-derived against code
first. Observed **doc staleness** is recorded in the baseline card's staleness
appendix; a staleness-derived correction enters the plan **only through an owner
brief item — a scope brief** (scope is owner-gated in both directions; the
class's 附加字段 takes the corrected doc passage and the card's staleness row
in place of budgets, which a correction does not move). "Record only" is a
disposition of the appendix row, never of a correction the plan will bear
weight on. (Measured: a doc-labelled
"invariant" that code contradicted cost a full owner-correction round.) A
baseline delta contradicting an owner-signed row triggers a mandatory
**ruling-contradiction brief** — an answer-only brief class (§10) whose outcomes
are a **supersede** or **reaffirmation** row.

An owner reply is not exempt from this hierarchy: **reply re-derivation** —
premise first, landing site second, one record per reply — applies it to what
the owner says before it is baked (author-lineage; the code is the arbiter;
the next cold review re-checks every baked premise). It verifies the owner's
assertion about reality, not the author's transcription of the owner's intent,
which is why it is stated here and not in the intent cell above.

**Baseline pin discipline.** A pin is one commit SHA **per repository the topic touches** plus a **working-tree drift
audit at every cold start**, run by the party cold-starting; drift is classified
benign / blocking in the card's pin header — **blocking drift halts the stage
until re-pin or a clean tree**. Topics pinned to the same SHA may share a
checkout; different SHAs need separate checkouts/worktrees. **On re-pin, every
card row reverts to `unverified` except rows whose evidence sites are untouched
by the SHA diff**; the verifier clears the delta. Card rows added after the
freeze are `unverified`. Design sections and work items carry a required
**`depends-on: [baseline row ids]`** field — the data the gate runs on:
**nothing takes owner approval, and no draft dispatches to review, while a
depends-on row is `unverified`**; rows nothing depends on are swept at the
convergence gate (§9).

**Command resolution** (verifier duty): **every command the plan carries** —
acceptance, execution-context/setup, and executable rollback lines — is resolved
at the pinned baseline: exists, parses, dry-runs where possible, plus fixture
reachability. Failing is the expected pre-implementation result; *unresolvable*
is the defect — except a command whose missing artifact is **created by a named
work item in the same plan**, which is resolvable-by-construction. Every command
carries a **"passes when …"** field (its post-implementation criterion). An
unresolved command blocks convergence exactly as an `unverified` row blocks
approval.

## 3. Roles and instruments *(clause 1 cast; clause 3 discipline)*

| role | kind | owns | never does |
|---|---|---|---|
| **author** | agent session, stateless per round (§8) | baseline card, design doc, grill sheet, re-derivation records, owner briefs, plan versions and `plan.md` promotion, prompt instantiation, dispositions, close-outs, decision-log rows (drafting; signing is the owner's), observation entries, retro ingestion | signing any owner-gated decision; editing findings or check records; re-rolling reviewers (rejecting a **valid** return) |
| **verifier** | no-lineage agent, per assignment | re-deriving `unverified` rows and resolving the plan's commands (§2), each assignment writing a **check record** the author may not edit | design opinions; plan content beyond the rows and commands assigned |
| **reviewer** | no-lineage agent, one per selected lens | findings on one lens — layer-tagged, `REVIEWER_REFINE` self-falsification pass(es) before return, provenance header first (plan version · baseline · drift audit · vehicle) | editing the plan; seeing another reviewer's findings mid-round; inheriting a verdict |
| **maintainer** | a fresh session, never a topic's author (the workflow's own stateless-author rule applied to itself) | workflow-tree edits between rounds (admission discipline, doc caps, `COMMIT_CAP`), cross-topic retro acts, release rounds on the tree itself | topic authoring; signing promotions or removals (the owner's) |
| **owner** | the human — the only out-of-family check **on judgment**; the conformance harness (§7 rung 2) is out of family too and settles only what a script can decide | per brief item: answer, defer (where the class allows), or re-tag; signing every owner-gated decision | leaving a brief item silently unanswered (unanswered = row stays `proposed`, dependent work parks) |

**No-lineage** (locked): a vehicle carrying none of the author's running
conversation — onboarded solely from its prompt file plus the artifacts it
names; the spawn message contains no authoring framing, no conclusions, no
expected verdict. **Instrument failure** (null return, off-mandate output,
crash) is a named failure class: the author re-spawns fresh with the failure
recorded — a re-spawn on failure is not a re-roll.

**Lens set** (locked): `architecture` (does the plan's structure hold against
the baseline card; **also runs the rung-2 spot-check**: the full field set of the
`SPOT_N` highest-risk items plus every preamble command) · `red-team` (premortem
framing: assume the plan shipped and failed — write the postmortem; mitigations
land in a named plan field: a rollback line, a migration/compat field, an
edge, or a new item) · `meta-critic` (cold-read the plan **and
design doc** against the baseline card, decision log, and named prior
authorities; attack scope and foundations; mandate text template-fixed — the
author fills slots only, never edits it, never omits a known opposing authority)
· `executor` (the impl-ready probe: onboarded from the current plan version and
the sites/read-ranges it states, attempt execution by reading, return every
point where it would have to ask a question). **Lens selection per round is
protocol's lens table**; its invariants: meta-critic at round 1, after any
`foundations` disposition, and at the convergence-candidate round; **executor at round 1 and at the convergence-candidate round** (declared in
the prior close-out's Next section when the register is empty). A skipped
lens is recorded in the close-out — **but not these**: an invariant dispatch
that does not return is instrument failure, not a recorded reason (protocol
§3).

**Closure-proof assignment** (locked term): when the author documents a class
recurring across ≥`RECUR_MIN` rounds, the next round adds the shared
closure-proof assignment — enumerate every operator between input and output and
prove an arbitrary member survives each, or name where it dies. The declaration
is an owner-gated decision row (it narrows the round's scope); reviewers verify
the classification first — a rejected classification reverts to lens hunts; the
round's mandatory lenses run **alongside** the assignment. Its onboarding is
deliberately narrow: the plan, the card, the claims discipline, and the
declaration row's content — no register, no decision log.

**Escalation is layer-keyed and mechanical — no scoring arithmetic.** Every
finding carries a `layer` tag from a closed set: `foundations` (scope, premises,
authority, completeness of the model) or `implementation`. Any finding any
reviewer tags `foundations` is owner-gated unconditionally — author synthesis
cannot close it; disagreement takes the stricter tag; the owner may re-tag
downward ("re-tagged `implementation` — returned to author", a signed row), and
the author may raise a brief item proposing `foundations` treatment for an
`implementation`-tagged finding (the upward path).

**Disputes.** Verifier-vs-author over a row: the author restates the row and its
evidence in the card; a **fresh** verifier re-derives; continued disagreement
becomes an owner brief item, whose signed answer disposes the row — `retired`
citing the row, or rewritten per the ruling and re-checked fresh (a check
record remains the only path to `verified`). Reviewer-vs-author: the finding rides its layer
tag; a `foundations` disagreement is the owner's by construction.

## 4. Vocabulary (locked — the single home; other files point here)

**Stages**:
`baseline → baseline-check → design ⇄ grill → draft → review → disposition → (loop ≤ ROUND_MAX) → converge | abandoned → retro`.
**Round**: one `draft → review → disposition` cycle, numbered from 1; **round
0** is the pre-draft arc (`baseline` through `design ⇄ grill`) with the same
close-out, observations, and restart duties. Exceeding `ROUND_MAX` or
`GRILL_MAX` is itself a finding — raised as a **scope brief** whose outcomes are
an owner scope-out (whose signed row **carries the new round and grill-batch
budgets**), a
**topic split** (= abandonment plus two new topics inheriting the pin and a
copied card), or abandonment.
**Arc**: the span of rounds a budget is counted over. A topic has exactly two
kinds — the **initial arc** (round 0 through the first terminal outcome) and
one **amend arc** per full amend (its entry round through that arc's fresh
signature). Nothing else starts one: re-entering `baseline` on a re-pin or
blocking drift continues the arc it is in, since no signed row opened a new
one. Each close-out records its arc and entry round; the arc scopes
`ROUND_MAX`, the trend halt's observation arm, and "second consecutive halt".
**Amend** (post-convergence): **full amend** — any change touching a work item,
an edge, a command, the execution-context preamble, **a coverage row**, the
pin, or a signed decision; re-enters at `baseline` when the pin has moved,
else at `draft`; full round discipline to a fresh signature and hash. **editorial amend** — touches
none of those; author claim + owner signature, no review round; **its own
signed row** naming the convergence row and carrying the new hash. Round
budgets count **per arc**: a full-amend arc starts a fresh `ROUND_MAX` count
from its entry (change-control practice: a change request is evaluated on
its own budget, not the exhausted baseline's).
**Topic outcomes**: `converge` (impl-ready plan, owner-signed) · `abandoned`
(author-proposed as a brief with the six fields plus an archive summary;
owner-signed; the archive spares later re-derivation of the same option —
which only holds if it outlives the topic, so retro ingests it into the state
file beside that topic's observations, on the same deadline and for the same
reason).
**`parked`** is a non-terminal hold (§8).
**Owner-gated decisions** (each = a signed decision-log row): rulings ·
deferrals · scope-outs · supersedes · reaffirmations (naming the row reaffirmed
and the delta survived) · bounded limits · **design-section approvals** ·
**re-tags** · **closure-proof declarations** · **amend dispositions**
(the full-vs-editorial classification, with cause dating on full;
hash-mismatch: adopt-as-new-version or restore-signed-copy; editorial amends) ·
**splits** · abandonment · convergence.
**Decision-log row states**: `proposed → signed` (immutable once signed; a later
change is a new row superseding the old, naming it and why; rejected
alternatives noted). The row carries the signed ruling text **verbatim**
(Chinese where the brief was Chinese) plus an English gloss (carried text, §2).
Immutability protects that ruling text; the single write that may still land
on a signed row is a **post-promotion attestation cell** — `PLAN_HASH` +
pinned SHA(s) on a convergence row (a full amend's included), which §9
requires filled after promotion because a hash cannot exist before the file
it hashes, and which records no decision.
**Baseline-card row states**: `unverified → verified → retired` (`retired`
has two producers, each with a recorded reason: the convergence gate's
sweep, and a signed answer disposing a verifier dispute (§3); flips cite a
check record; re-pin reverts per §2; a `disputed` verdict leaves a row
`unverified`).
**Grill branch states**: `decided` (→ signed row) · `deferred` (→ signed
deferral row — a deferral only exists as an owner reply, signed by
construction) · `reality-gap` (→ `unverified` card row).
**Work item** (the plan's item-level unit; §9 keys its item rows to this set):
id (opaque; ordering proven by a checked topological sort, not id order) ·
title · **sites** (paths + symbols + the read ranges the executor is onboarded
with) · target repository · risk label (closed set `low | medium | high`;
assignment criteria in the plan template) · **abort/rollback line,
unconditional** ("none — reason" explicit; executable rollback lines are
commands and join resolution, §2) · magnitude bucket (closed set `S | M | L`;
an `L` item is split or carries a signed bounded limit saying why not) ·
ordering edges (typed: `authoring` = must be implemented before · `runtime` =
must take effect / deploy before) · `depends-on` baseline rows · **interface
delta, unconditional** (by symbol, or "none — internal only" explicit) ·
**migration/compatibility field** ("none" explicit; required content when the
interface delta touches persisted or cross-process shapes) · command(s) with
"passes when …" · a "why the current system is insufficient" trace (the A§2
obligation, carried per item) · references to any signed deferral or bounded
limit touching the item, with the executor's fallback.
**Vehicle**: the model/agent identity a thing ran on or was measured on —
spawned instruments record it in provenance headers; measured model
behaviours record it in the model-dependency register's vehicle column
(§11). **`<PLANS_ROOT>`**: the deployment-chosen directory holding topic
roots; every kickoff/restart line carries it absolutely (§5.2). **R-Q**: a
reviewer question that cannot be made independently re-derivable — filed in
the findings file and routed into the round's brief alongside findings.
**Sintering candidate**: an ingested observation awaiting its second
independent anchor before promotion (§11); retired to the index after
`REMOVAL_TOPICS` topics without one. An owner-directed adoption (§1
carve-out ii) enters without the wait, as a seed carrying validation
debt.
**Artifacts**: baseline card · design doc (scope section ·
shared-understanding section · approval citations naming their signed rows) · grill
sheet · re-derivation record · check record · owner brief · plan (versioned,
never overwritten) · findings · disposition ledger · decision log · close-out
(its last line **is** the fenced restart handoff — no separate restart-prompt
artifact) · iteration log. The convergence checklist is an appendix of the
convergence brief.
**Canon**: §8. **No-lineage, layer, lens set, closure-proof assignment,
instrument failure**: §3.

## 5. File layout and the specification ledger *(mission boundary)*

### 5.1 The workflow tree (committed except `discussion/`)

```
workflows/planning-workflow/
├── README.md            # map + quickstart (the kickoff line's home)
├── design/
│   ├── architecture.md  #   this file; §13 = settled-rulings registry
│   └── rationale.md     #   campaign autopsies, external anchors, ceilings in full
├── runtime-docs/
│   ├── protocol.md      #   stage protocol; cold/warm + lens tables; §defaults =
│   │                    #   single home of every tuning value (with units)
│   ├── claims.md        #   claim shapes → mechanical preconditions
│   ├── prompts/         #   baseline_verifier · reviewer_architecture ·
│   │                    #   reviewer_redteam · reviewer_metacritic ·
│   │                    #   reviewer_executor · reviewer_delta ·
│   │                    #   reviewer_closure_proof · refine_falsification
│   └── templates/       #   baseline · design-doc · grill-sheet · rederivation ·
│                        #   check-record · owner-brief · plan-dir/ (directory
│                        #   template) · findings · disposition-ledger ·
│                        #   decision-log · close-out · convergence-checklist
├── self-check/          # the conformance harness (§7 rung 2's executable
│                        # form): check.sh + checks/ + fixtures/. Dev-time
│                        # only — nothing here runs during a topic
├── runtime-scripts/     # spawn.sh + backends/ — `{DELIVERY}`'s second form
│                        # made executable (protocol §5.1). The opposite of
│                        # self-check/: this DOES run during a topic, and
│                        # nothing requires the LAUNCHER; the gate +
│                        # concatenation live here and every topic needs them
├── .gitignore           # ignores discussion/
├── discussion/          # informal material — gitignored, deletable as a unit;
│                        # never referenced by finalized docs, by path or codename
└── iteration-log/       # the STATE region (§11), directory form: INDEX.md ·
                         # open/ · owner-queue/ · validation-debt.md ·
                         # model-register.md · staging.md · TEMPLATE.md
```

**The formal region is `README.md` + `design/` + `runtime-docs/`; the state
region is `iteration-log/`.** One invariant governs the boundary, tree-wide:
**the formal region points at files, never at state rows, and carries no
dates.** State rows prune at retro (§11) and observation rows retire, so a
pointer from a permanent document into one is a dangling reference by
construction; the reverse pointer is the load-bearing one, and it already
exists — every debt row names the ruling that seeded it. Chronology is git's.
The same reasoning that makes the state file a state file makes this
direction the only stable one.

### 5.2 The topic tree (runtime output)

Topic root: `<PLANS_ROOT>/topics/<topic>/`; every kickoff and restart line
carries absolute paths for both trees.

```
<topic>/
├── plan.md              # boundary artifact (§9: final version, hash + SHA on
│                        # the convergence row; preamble carries the consumer
│                        # precondition line)
├── planning/
│   ├── baseline.md      #   pin header (SHA + drift audits) · rows · authorities
│   │                    #   inventory (meta-critic source, §3) · staleness appendix
│   ├── design.md        #   scope section · shared-understanding claims ·
│   │                    #   sections with depends-on + approval-row citations
│   ├── grill_sheet.md   #   question · recommendation · answer · state ·
│   │                    #   decision-log row id · re-derivation pointer
│   ├── rederivations.md #   round-0 re-derivation records (later ones in rounds/)
│   ├── decision-log.md  #   ALL owner-gated decisions (§4) + hashes
│   ├── briefs/          #   owner briefs, sequential ids
│   ├── plan_v<N>/       #   version archives — a directory per version
│   │                    #   (00_context · items · invariants · rederivation
│   │                    #   · delta), never overwritten
│   └── rounds/<n>/      #   n=0 = pre-draft arc; prompt_<instrument>[_<k>] ·
│                        #   register_stripped · findings_<instrument>[_<k>] ·
│                        #   findings_<instrument>_failed_<k> (a return
│                        #   judged instrument failure — kept, never
│                        #   discarded) · closure_proof (when declared) ·
│                        #   check records · rederivation records ·
│                        #   disposition ledger · close-out
└── <sibling regions>/   # other workflows' worlds (§9 reserves plan.md +
                         # planning/ at this root); not designed here
```

### 5.3 Specification ledger — what this file deliberately delegates

| specification | home |
|---|---|
| every tuning value, with units (`ANCHOR_MIN`, `RECUR_MIN`, `ROUND_MAX`, `GRILL_MAX`, `REFINE_MAX`, `REVIEWER_REFINE`, `REMOVAL_TOPICS`, `SPOT_N`, `RESPAWN_MAX`, `BRIEF_MAX_ITEMS`, `PLAN_HASH`, `COMMIT_CAP`, doc caps — architecture/rationale/README included) | `protocol.md §defaults` |
| cold/warm static table; per-round lens table; per-stage duties; retro checklist | `protocol.md` |
| claim-shape mechanical preconditions in full | `claims.md` |
| **every template's field schema** (incl. risk/magnitude criteria and their thresholds, placeholder token set, "passes when" format, preamble schema, per-class brief 附加字段) | `templates/` |
| reviewer mandate texts; the refine falsification text | `prompts/` |
| kickoff line wording | `README.md` |
| restart-line wording | `protocol.md` §7 — authoritative; the close-out template carries its verbatim instantiation site |
| spawn-message wording | `protocol.md` §5 (content constraints: §3's no-lineage rule) |
| maintainer entry-line wording + release-round shape | `protocol.md` §7 |
| amend entry-line wording | `protocol.md` §7 — authoritative; the plan's execution-context preamble carries its verbatim instantiation site |
| the mechanical invariants themselves — which are checkable, how, and each check's honest boundary | `self-check/` (one file per invariant; §7 rung 2) |
| a launcher for `{DELIVERY}`'s file form, and each backend's measured screen signature | `runtime-scripts/` (one declaration per CLI; nothing here is required — the returned-text form needs no launcher) |
| the emit-time red gate over an emitted plan version (currency/same-section/cite arms); the promotion concatenation (fixed order, deterministic) | `runtime-scripts/emit_gate.sh` · `runtime-scripts/plan_concat.sh` |

An undefined term in this file whose row appears above is **delegated, not
missing**; a term in neither place is a defect.

## 6. Topic flow *(governance; mechanisms cited by home)*

The stage sequence is locked in §4. **Per-stage duties are delegated**
(§5.3 → `protocol.md` §4), so this section routes rather than restates: each
stage to the home that generates what it does.

| stage | generating home(s) | executable duties |
|---|---|---|
| `baseline` (round 0 opens) | §2 (pin discipline, card) | protocol §4.1 |
| `baseline-check` | §2 (verification cell), §3 (verifier) | protocol §4.2 |
| `design ⇄ grill` | §2 (grill, shared understanding, reply re-derivation), §4 (approvals as signed rows), §10 (briefs) | protocol §4.3 |
| `draft` | §8 (canon, cold restart), §7 (rungs 1–2) | protocol §4.4 |
| `review` | §3 (lens set, no-lineage) | protocol §4.5 |
| `disposition` | §3 (layer-keyed escalation), §10 (owner gate) | protocol §4.6 |
| `converge` \| `abandoned` | §9 (the gate) · §4 (outcomes) | protocol §4.7 · protocol §4.8 |
| `amend` · `parked` · split | §4 (outcomes), §8 (parked) | protocol §4.8 |
| `retro` | §11 (self-iteration) | protocol §4.11 |

One property of the flow has no other home and is stated here:

- At `review`, every instrument receives the open-findings register **with
  layer tags stripped** (facts under re-examination, not verdicts) —
  *except* the executor and the closure-proof assignment, whose onboarding
  is deliberately narrower (§3).

## 7. The instrument ladder *(clause 3)*

Judgment flows to the cheapest instrument that can hold it; each rung has a
named catch-class and blind spot — **no rung substitutes for a higher one**:

1. **refine** (author self-loop, warm; fixed prompt =
   `prompts/refine_falsification`): falsification objective + **mandatory
   re-evidence-gathering**; a fix without the evidence that demanded it is
   invalid; a clean round is an acceptable terminal answer. Stop at fixed
   point; hard cap `REFINE_MAX`; a dirty cap-out flags the residue up the
   ladder. Catches internal-class defects. Blind: external truth (the
   **self-correction blind spot** — measured + literature, `rationale.md`).
2. **mechanical claims check** (emit-time, self-administered — no CI): shape
   preconditions per `claims.md`; workflow-file edits also check doc caps
   here. For edits to **this tree** the rung has an executable form —
   `self-check/check.sh`, which runs the invariants a script can settle
   (caps, section references, constants, the §5.1 region boundary, prompt
   slots, closed vocabularies, registries, verbatim copies). Still
   self-administered, but its administration is a command rather than a
   habit. Blind: whether the right claims were made — and, for the harness,
   anything that is a wrong idea rather than a broken reference. Backstop:
   the architecture lens's stated spot-check (§3), not an unbounded promise.
3. **independent re-derivation** (verifier / reviewers, cold): the only rung
   that verifies correctness rather than presence — a fresh read receives the
   author's output as external input, crossing the blind spot. Blind: shared
   model-family blind spots.
4. **owner**: brief answers and signatures — the scarcest instrument;
   everything above exists to spend it only on judgment.

## 8. Loop control — the stateless author *(clause 4)*

**Restart is architecture, not hygiene.** State lives in artifacts; each
round's author is a fresh context re-anchored from the **canon**: baseline card
· design doc · grill sheet · decision log (rows carry signed text verbatim) ·
current plan version (an artifact to audit, not to trust) · the **latest
close-out**, whose **settled-state table** (settled facts, one line each, with
row/record pointers) and **open-findings register** (id · one-line statement ·
layer · **class** — instrument-assigned `product | provenance | doc-sync |
artifact`, orthogonal to layer (where it bites vs what it is about) · why
open) are the entry points — older rounds' artifacts enter the
canon **by pointer through those tables**, consulted per claim, never re-read
wholesale. What restart buys is structural: the "already-decided" shortcut
cannot survive a discarded conversation, and the externalization pressure is
what makes verifiers, reviewers, owner audit, and handoff possible at all. The
context budget corroborates in practice; the load-bearing
reason is the blind-spot crossing — the rule does not decay as context windows
grow.

**Cold/warm is a static declaration** — single home: `protocol.md`'s table;
this file states the principle. Warm where continuity is the value (within a
round; design⇄grill). Cold where freshness is load-bearing (round 0 start;
every draft start; every verifier and reviewer). Two **event-triggered
immediate restarts**, defined by artifact facts, never self-judgment: a finding
establishes a baked premise contradicts code, or scope/foundations pivot
(paired with a cold re-read). Honest bound: restart sheds cross-round
calcification only — same-session absorption is the claims discipline's catch.

**Before any restart**: the close-out's required zero-context field ("what
would a zero-context author miss resuming from these artifacts alone; 'none'
explicit") is filled; the close-out's final line is the fenced restart handoff
(absolute paths + forcing clause stopping at the first owner touchpoint).

**Parked.** When every next step waits on the owner, the topic parks: the
close-out enumerates the open set; nothing loops; retro may run (§6). **Resume
always re-runs the drift audit**; blocking drift returns the topic to
`baseline`. Parking is a recorded hold, not an outcome.

**Carry-forward**: findings carry across rounds until a recorded disposition
or a signed row; **relocation is not disposition**. **Convergence stop rule**:
a finding leaves the register by exactly one of three doors — a **root fix**
(the class removed at source, confirmed by independent re-derivation; the
closure-proof assignment where one is declared), a **refutation** (the
finding was wrong: its re-derivation cited, and the refutation **listed for
the owner at the gate** — a finding that merely disappears is silent
narrowing; no instrument's input set contains the disposition ledger, so the
gate is the only place a refutation meets an out-of-family reader), or a
**signed bounded limit**; never exhaustion, never silent narrowing. (Refine's fixed-point
release is not exhaustion: it stops on a clean round; a dirty cap-out flags
the residue up the ladder.)
**The shipping invariant**, which the gate and the loop are both mechanisms
of: *every word of the promoted plan has been read by an independent
instrument at the version it ships, or is a rendering of an owner-signed row
that a fresh instrument re-derived against that row at promotion.* The second
arm says "rendering", not "verbatim", because §12 puts the plan body in
English while a signed row carries its text verbatim plus a gloss — so what
promotion inserts is carried text (§2), and carried text's checker is a cold
read that, at promotion, nothing else would ever run. The candidate round's delta rule (`protocol.md` §4.6.4)
and promotion's mechanical diff (§9) implement this one sentence; where they
seem to disagree, it governs. The
close-out's **round-metrics row** (mechanical counts by severity — never
scores, which would re-open the averaging channel §3 closed) is the
convergence telemetry; the **severity-trend rule**, whose input is the substantive sum over the
instruments **both** rounds dispatched — one first sent this round has no
prior and joins neither side of the pair: two consecutive rounds
with non-decreasing substantive counts → halt and diagnose the process,
never a blind further LOOP — **unless both counts are zero and the
open-findings register is empty**, which is the convergence path rather than
a plateau. Zero production with findings still open is the opposite: it is
the state a topic sits in when it is stuck behind something it can neither
fix nor close, which is when a diagnosis is worth most. Two arms — a **scope brief** (the owner's), or
a **workflow observation**: self-discharged, but **once per arc**, carrying
a falsifiable expectation ("if this diagnosis holds, the next round's
substantive count falls / class X stops recurring") in the close-out's
required observations table — which §11's retro then ingests, as the single
writer into the log. A **second consecutive
halt** is evidence the first diagnosis did not hold: the observation arm is
spent and the scope brief is the only arm left. The party whose loop is
halted may diagnose it once; it may not clear itself twice.
**Metric hierarchy**: the escape count (§11) is the *metric of record* —
outcome-keyed and process-independent, the only number comparable across
topics and workflow versions; round counts are *telemetry* — process-coupled,
never compared across versions. The pair polices itself: gaming the
telemetry (a lenient round) raises the record metric (escapes). And the
release principle both levels share: **convergence is affirmative evidence
or an owner signature, never the absence of complaints** — a clean round
counts only when its clean categories are reported affirmatively, with
ranges.

## 9. The boundary contract *(mission boundary)*

**Zero dependency**: no runtime or normative reference to a sibling workflow's
paths, files, or role vocabulary anywhere in this tree — **marked historical
citations are evidence, permitted anywhere**. Planning reserves exactly two
names at the topic root: `plan.md` and `planning/`. The contract, in this
workflow's own vocabulary:

- **Promotion.** At convergence the author produces the **final plan
  version**: the signed plan version plus **only** the convergence brief's
  signed dispositions (the executor's answered questions, convergence-round
  bounded limits) — no other content may change, checked as a mechanical
  diff. `plan.md` is the deterministic concatenation of the promoted version
directory (`plan_concat.sh`: context → items → invariants → rederivation →
delta — order is part of this contract); the content hash lives on signed
  decision-log rows, never inside the hashed file (self-referential, it
  would never re-verify) — **and likewise every self-descriptive reading**:
  commands and pass criteria in the plan, the readings themselves in
  `rounds/<n>/plan_hash.md`; the **live** hash is the latest signed row's —
  the convergence row's until an amend row supersedes it; the plan header
  carries the pinned SHA(s) and the row id. A later change enters
  **amend** (§4); a hash mismatch is an amend disposition (§4). The
  executor's provenance version must equal the version the convergence brief
  reviewed, **or differ from it by non-semantic delta only** (the §4 field-set
  classification `protocol.md` §4.6.4 uses; attested in the gate row). What
  this protects is the executor's verdict, which a semantic change stales and
  a title fix does not — the shipping invariant again, not version equality
  for its own sake.
- **Convergence gate** — three criterion classes; the filled checklist is an
  appendix of the convergence brief; the owner signs the brief. A withheld
  signature returns the topic to the loop with the objections entered as
  owner-sourced findings (a deferral parks it, §8); only the signature
  converges.
  *Item-level rows* (rung 2 at emit; spot-checked per §3): every work item
  carries the §4 field set — sites, unconditional interface delta and
  rollback line ("none + reason" explicit), migration/compat field,
  commands with "passes when", typed edges, depends-on, deferral/limit
  references with fallbacks; no placeholder token (set enumerated in the
  checklist template); edges pass a topological-sort check.
  *Plan-level rows*: the execution-context preamble is filled (repos + SHA,
  toolchain and setup commands, fixture data) **and its consumer
  precondition line present** (re-run the drift audit against the pinned SHA
  before executing; blocking drift ⇒ amend); **coverage, four directions** —
  every signed decision row is referenced by ≥1 work item or marked
  non-plan-bearing; every bullet of the approved scope section maps to ≥1
  work item; and every work item maps to a scope bullet or a signed row
  (an unmapped item is scope creep or over-engineering, mechanically
  visible); and **every bullet of the approved scope traces to the recorded
  topic statement or to a signed row** — the direction that leaves this
  workflow's own vocabulary and reaches the ask it was started from, without
  which the three above prove only that the plan covers a scope nobody
  checked against the request; **the open-findings register is empty** — every prior finding
  out through one of §8's three doors, with refutations additionally listed
  for the owner (the §8 stop rule wired into the gate: a topic never
  converges over a silently carried finding, and a refutation is the one
  door no independent instrument would otherwise see); `unverified` card rows nothing depends on are swept —
  verified or explicitly retired; **every command resolved** by the verifier
  (§2). *Executor rows* (rung 3): the executor's question-inventory is empty
  or every remaining question has a signed disposition; the checklist's
  zero-context field ("what would a zero-context executor miss from the plan
  alone; 'none' explicit") is authored by the executor and transcribed
  verbatim by the author (carried text), never author-written.
- The decision log and baseline card **are never mutated or withdrawn by this
  workflow after convergence** — unconditional, whoever consumes them. Their
  **retention** is the deployment's and not this promise: a topic tree is
  cleaned once its retro has run, so a consumer that will need a signed row
  after that takes its own copy. What planning owes is that the copy it took
  is still the truth, which immutability is exactly what buys.
- Pulled out alone, this workflow still produces the same signed,
  gate-passing plan; the gate is the standalone definition of done.

## 10. The owner interface *(§13 rulings: briefs, language; state machine per §4)*

**Briefs are the single owner channel** — grill batches, **design-section
approvals**, layer-routed findings, R-Q questions, scope briefs,
ruling-contradictions, closure-proof declarations, verifier disputes,
instrument-failure cap-outs, upward re-tag proposals, bounded-limit proposals,
amend dispositions, abandonment proposals, and convergence all arrive as brief items. Every item carries six required fields (owner ruling; the worked example
is the load-bearing one): 来龙去脉 · 为什么会有 · 推荐怎么做 · 收益 · **完整形象
示例** · **代价与最强反方**. An example is an executable test of shared
understanding (wrong models produce visibly wrong examples), chosen to expose
the mechanism's branch points rather than showcase the recommendation. Every
item meets the **zero-context-ruler standard** — the owner rules from the
section's own text alone (options with deltas, in-section evidence pointers,
converging sets spending no owner slot; the template carries it in full). The
counter-argument field keeps the brief from
becoming a persuasion document (the author writes it — a framing surface;
brief background sentences are claims under the discipline). Fields constant,
depth scales. Archived at `planning/briefs/brief_<n>.md`.

A **workflow-tree item** is the one class with no topic: six fields inline on
its own state-region row (§5.1 bars the formal region from holding its dates
or state references), never a `planning/briefs/` file and never `discussion/`.

**Batching and answers**: co-pending items batch into one brief file, one
section per item — **one decision-log row per section**, never merged —
**≤`BRIEF_MAX_ITEMS` sections per brief**, the rest splitting into the next
brief by settled prerequisites exactly as grill batches do. This bounds the
*sitting*, not the topic (detection degrades with batch size and session
length, `rationale.md` §5; the owner is the constraint every other rung
exists to spend sparingly, §7). Total owner
volume across a topic stays unbounded by design — §14 carries that ceiling.
Every close-out's metrics row reports owner items emitted this round and
cumulative for the topic: an unmeasured queue cannot be managed. A partial
answer signs the answered sections; unanswered sections stay `proposed` and
park dependent work. An "ok" against a section signs that section's
recommendation text as written; the row carries it verbatim plus the English
gloss. Reply types (answer · defer · re-tag) are per-item **defaults — a brief
class may narrow them**; the narrowed: ruling-contradiction (answer-only:
supersede or reaffirm); layer-routed findings (answer or re-tag — a
`foundations` finding cannot be deferred; its bounded-limit
answer is the stop rule's signed path).

## 11. Self-iteration *(clause 5)*

Every close-out (round 0 included) carries a **required** `workflow
observations` section — "none" explicit, so a skip is visible (measured
predecessor history: an observer-borne optional log went unwritten through a
ten-round topic; author-borne + structural is the fix — `rationale.md`). At
**retro** (§6) the author ingests observations with anchors; promotion follows
§1. Two parties that see workflow defects reach no close-out — the maintainer,
whose release rounds run no retro, and the instruments, whose prompts hold no
field for one — so the log carries an append-only **staging** section all three
write as observed, each entry bearing a falsifiable expectation; retro step 1
remains its only reader and the only writer into the promoted tables
(protocol §4.11) — **except a family row's landing/status field, which is the
maintainer's; observation text and anchor counts stay retro's, and a non-retro
anchor increase is a rung-2 red (protocol §4.6.4)**. **Validation-debt closure is a retro act**: a row closes only on cited
exercise evidence (a disposition-changing catch, or demonstrably shaping an
artifact). Debt rows carry a **model-dependency flag** where the mechanism's
justification cites a measured model behaviour; the persistent
**model-dependency register** (a vehicle column records what each behaviour
was measured on) re-opens flagged rules at any retro where the model has
changed — the register outlives debt closure for exactly this check. The log
is a **state file, not a history file**: entries closed or retired at retro
prune to one-line index rows (grep-fodder for anchor matching), and **this
tree's own git holds what was pruned** — that, not a line cap, is what bounds
it. The full text is carried here and not merely pointed at, because a topic
tree is not durable: it is cleaned, and everything the workflow needs to
iterate on itself has to survive that. A topic tree is cleaned **after** its
retro, which is what keeps that survivable: retro is the last reader of a
topic's own artifacts, and its step 1 is the ingestion deadline rather than a
formality. Cleaning one before its retro takes its observations with it, and
nothing downstream can tell that it did. A mechanism with no catch across `REMOVAL_TOPICS` topics is a removal
candidate; removal is a signed ruling. Retro computes the **escape count**
(full-amend rows whose cause predates convergence) into the final
close-out's metrics history — §8's metric of record; its cross-topic rate
form is **planning-DRE** (defect removal efficiency applied to planning —
anchor: `rationale.md` §5). Template edits land only between rounds,
never on a live one (protocol §4.11 decides which is which), as **single-purpose commits ≤ `COMMIT_CAP` changed lines**
(a measured defect-rate cliff sits above small commits — predecessor-era
evidence, `rationale.md`); **git is the rollback path** for this tree; doc-cap
conformance is a rung-2 emit row for workflow-file edits (§7). Release
rounds on this tree take the **complete tree** as the review unit
(measured: subset reviews yield a constant finding rate — `rationale.md` §4).
**This tree is public and project-agnostic**: retro ingests the mechanism,
never the project — topics by neutral alias, no project, repository, path,
host, tool or people names, no delivered-repository SHAs, no pasted artifacts.

## 12. Language rule *(§13)*

English body everywhere; Chinese on owner-facing surfaces: owner briefs and
the grill sheet's question / recommendation / answer columns. Signed Chinese
ruling text rides decision-log rows verbatim with an English gloss (carried
text, §2). The language follows the reader.

## 13. Settled rulings (registry)

**Membership**: owner rulings about this workflow — the registry keeps the
**ruling text**; the generated sections (§10, §12) and locked-by-construction
or boundary content (§2, §4, §8, §9) keep the **mechanisms** and are not
re-stated here. Marked historical names are evidence, exempt from §9.

**Stable names, no state.** Each ruling is identified by a stable name and
carries its text only — the formal region's invariant (§5.1) applied here,
and the reason the name exists at all: it is what the state file references
a ruling by, in place of a date.

Each ruling below is settled and binding; order carries no meaning:

- **Name `planning-workflow`; mission fixed: "output an impl-ready plan."**
- **Fresh build; predecessor retirement** *(transitional plan — historical
  record of an owner ruling, not a runtime dependency; done)*: the
  predecessor template (`plan-design-review-workflow` — historical name)
  finishes its one in-flight topic round; its case evidence is re-authored
  self-contained into `rationale.md` (two predecessor campaigns + the
  then-current one = the three predecessor autopsies A–C; the build added
  its own, Campaign D); the predecessor directory is deleted; subsequent
  rounds run here.
- **baseline-check mandatory for every topic; no exemptions, no size
  threshold.**
- **Zero inter-workflow dependency; each workflow fully usable standalone.**
- **English body; Chinese owner-facing surfaces.**
- **Owner briefs: six fields, the worked example load-bearing; archived as
  md.**
- **Seeds — extraction and review instruments** (§1 carve-out ii): grill,
  baseline card + baseline-check, refine loops, cold/warm table,
  layer-keyed escalation, owner briefs, and the executor lens carry
  validation debt until a live topic exercises them; mechanisms carried
  from the predecessor with live-run evidence (closure-proof, fix claims,
  carry-forward, restart) enter with evidence cited in `rationale.md`.
  `ANCHOR_MIN` applies to all future observation-path promotions
  (owner-directed seeds enter per carve-out ii).
- **Seeds — self-iteration and metrics** (§1 carve-out ii): the
  iteration-log state file, the round-metrics row, the third coverage
  direction (item → scope/row), and the escape count / planning-DRE.
- **Seeds — loop control** (§1 carve-out ii): the delta-scaled candidate
  re-review, refutation as a named door of the stop rule, the trend halt's
  two arms, and `BRIEF_MAX_ITEMS`. Their mechanisms are §8's and
  `protocol.md` §4.6.4's,
  per this registry's membership rule.
- **Conformance harness** (§1 carve-out ii): the tree's mechanical
  invariants are executable (`self-check/`), run as rung 2 for
  workflow-tree edits and as the conformance class's first act in a release
  round. Each check states its own honest boundary, fails when its input set
  is empty, and proves it can fail. A green run is a precondition for a
  release round, never a substitute.
- **Seeds — validation and the boundary's return path** (§1 carve-out ii):
  the intent source's verification cell is owner-arbitrated — shared
  understanding, the design doc's table and every brief item's worked
  example; the convergence gate's fourth coverage direction, approved scope
  back to the recorded topic statement; and the post-convergence amend's own
  entry line, carrying its cause. Their mechanisms are §2's, §9's and
  `protocol.md` §7's, per this registry's membership rule.
- **Instrument ladder ordered by independence distance** *(signed; landing
  sequenced — pending, in order)*: the ladder's ordering axis is independence
  distance rather than cost, and which rung a judgment may stop at is decided
  by the judgment's grammar — text-only conclusions may stop low, a
  conclusion about whether something outside the text is true may not.
  Landing waits on the first live topic: what the change does is route
  judgments differently, and A§1(c)'s demonstrated need for that is only
  observable in a run. Rung numbering and its citations are unaffected either
  way.
- **Delivery shape is the deployment's** (§1 carve-out ii): a deliverable
  reaches the author either as returned text or as a file at a stated path
  outside the topic tree, marked complete by a second file written after it.
  The tree names no vehicle and no dispatch mechanism; which shape applies is
  a deployment choice, and the author's duty to persist it verbatim is the
  same under both.
- **Maintainer owner-queue**: what the maintainer owes the owner is a brief
  class of its own, held in the state region beside the iteration log — never
  in `discussion/`, whose deletion is meant to lose nothing.
- **Maintainer entry-line item slot**: `between-rounds edits` may carry an item
  pointer, as the retro form carries its topic root (owner-directed seed, §1(ii)).
- **Discussion isolation**: finalized docs
  reference no `discussion/` content — by path or by local codename; the
  directory deletes as a unit with no loss of meaning anywhere in the tree.

## 14. Honest-ceiling index *(§1(e); one row per mechanism; longer statements in `rationale.md` §6 where a row needs them)*

| mechanism | ceiling |
|---|---|
| baseline card | covers only facts the author thought to write; the falsification-target column and the grill's reality-gap arm are the recall paths |
| baseline-check / check records | verifies rows, not the card's completeness; shares the model family |
| pin + drift audit | catches working-tree divergence, not the pin's own staleness against the world; re-pin row reversion trusts the SHA diff to name evidence sites |
| unverified / depends-on gate | only as complete as the depends-on lists; an omitted dependency is invisible until the convergence sweep |
| grill | extracts known unknowns only; unknown unknowns arrive via the shared-understanding section, reviewers, and the owner reading briefs |
| reply re-derivation | author-lineage; code is the arbiter; backstop = next cold review |
| refine (rung 1) | verifies presence, not truth (measured three times: zero-or-two self-found vs double digits independent) |
| claims check (rung 2) | self-administered; backstop is the stated spot-check, itself a sample |
| prescription shape (`claims.md`) | reaches only the rules the writer thinks to open. A governing rule nobody names — an unwritten house convention, or a gate in a repository the plan does not declare — is invisible to it, and the executor is still the first to meet that one. It also cannot rank two rules that both apply and disagree: it reports the collision, and the disagreement is an owner decision |
| launcher + backend declarations (`runtime-scripts/`) | each declaration's screen signature is measured against **one version** of one CLI and moves silently when that CLI updates; nothing re-probes it, and the failure presents as a launch that never reaches its composer — a timeout to any rule, an untouched prompt to a person. What bounds it is not prevention but **recovery**: the returned-text delivery form needs no launcher, so a stale declaration costs one manual dispatch rather than a round, and `status` shows a human which of the two it is. The launcher is a convenience over a channel that works without it, and is priced as one |
| deliverable transfer (returned text, or a marked file) | the marker proves the instrument finished writing, never that what it wrote is complete or on-mandate — an instrument that stops early and marks it looks identical to one that finished; and where a deployment cannot produce a record of an unwritten attempt, the failure file is empty and the ban on discarding a return has nothing to carry |
| carried text / gloss | checker is the next cold reviewer — a gloss error survives until one runs |
| authorities inventory (meta-critic's `{PRIOR_OPPOSING_DOCS}`) | the audited party names the documents it will be audited against; "never omit a known opposing one" is unfalsifiable against one never listed, and the cold reviewer cannot know what is missing — Campaign A's catch depended on this list being right |
| architecture-lens spot-check sample | the sample is chosen by `risk`, `magnitude` and edge count — all author-authored fields of the artifact under audit, so the audited party selects its own sample; `SPOT_N` bounds the size, nothing bounds the choice. The tie-break rotates off items a prior round already opened (`{SPOT_PRIOR}`), because those three fields barely move between versions and a fixed rule re-drew the same three items on two consecutive rounds — four rounds' cumulative coverage was three items, not twelve. Rotation moves the sample **within** the highest-risk band only: a lower-risk item can still reach the gate with no independent read of its field set, and the row that would catch that (checklist I-1) is author-filled |
| design doc / design-section approval | signed at round 0, when no rung-3 instrument has read it — the meta-critic's first pass comes a round later, against a row the evidence hierarchy now ranks above design text |
| per-round lens dispatch (delta-keyed table) | an ordinary round's lens set holds no lens mandated to hunt foundations — any lens may tag it, none is sent to look; earliest compelled catch is the round after a `foundations` disposition, or the candidate round |
| reviews (rung 3) | lineage independence ≠ cognitive diversity; shared model-family blind spots survive — and a clean verdict is relative to the lens set: a new perspective can open a stratum the current set cannot see (measured: each lens added during the build found a class the prior set missed) |
| R-Q channel | carries only questions reviewers think to ask; the owner's answer closes the item without independent re-derivation — its checker is the next cold round |
| executor lens | reads the plan, does not run it; a plausible-but-wrong command that resolves still passes |
| command resolution (verifier) | exists/parses/dry-run proves reachability, not that it is the *right* command — that judgment stays with reviewers and the "passes when" field |
| layer-keyed escalation | an under-tagged `foundations` finding bypasses the gate unless one reviewer sees it; the upward challenge path depends on the author choosing to use it |
| closure-proof assignment | only as complete as its operator enumeration — and the enumeration is the cheap half: measured on one live member set (owner-signed bounded limit), the mechanizable arms covered 1/11 members (carried-set recheck) and 2/11 (verifier-side) while 8/11 slipped between them — the emit gate never re-runs an evidence command, the per-round arm's literal is exists/parses/dry-run so a zero-hit command counts as resolved, and `path::Symbol` locators sit outside the cite check's regex; what actually stands between a wrong-sourced value and the executor is rung-3 discretionary reading, which is exactly what the signed bounded limit accepts |
| fix / acceptance claims | a trace can be done-but-wrong; corners cover only named axes |
| coverage rows | prove reference, not realization — an item can cite a ruling and still implement it wrongly |
| restart / cold-warm | sheds cross-round calcification only; same-session absorption is claims' catch |
| amend | editorial-vs-full classification is an author claim under an owner signature; a mis-classed edit ships unreviewed |
| scope brief / split | budget resets and splits are owner judgment; a rubber-stamped reset re-opens the loop it bounded |
| disputes / instrument failure | a fresh verifier or re-spawn shares the model family; repeated failure has no third instrument short of the owner |
| convergence gate + hash | item/plan rows are author-filled except the executor's and verifier's; the hash detects edits to `plan.md`, not movement of the code — the consumer precondition line states the duty, planning cannot enforce it |
| recorded workflow SHA (close-out) | proves which tree version the round ran under, never that the resuming session applied the delta — and it is written by the same session whose compliance it would evidence; a round that records nothing is invisible to the check, exactly like the rounds before the field existed |
| plan-version archive (new file per version) | preserves text, not intent — an overwrite becomes impossible but a wrong edit in a new version is not; the promotion diff (P-6b) catches only the final version |
| owner briefs / signatures | rest on the owner actually adjudicating; a rubber stamp is laundering; an absent owner parks the topic — honest, but stopped |
| owner queue volume | `BRIEF_MAX_ITEMS` bounds one sitting; **nothing bounds a topic's total** — one question is one section is one row, `foundations` items cannot be deferred, and briefs serialize the session, so volume scales with reviewer count and topic size. The design's own cheap adaptation is the one-word "ok" it makes first-class, which is why the count is now reported rather than assumed away |
| carry-forward / stop rules | root-fix vs micro-corner is a judgment; mis-classification launders a class into a signed limit |
| refutation (a door of the stop rule) | author-lineage and the cheapest door: refuting costs a re-derivation, root-fixing costs a re-review. Its only out-of-family read is P-5b at the gate, on a topic the owner is already signing off — nothing catches a wrong refutation in the round that makes it |
| candidate-round delta rule | the classification is made by the author about the author's own edit, and it decides whether the next round costs one lens or four; the complement form bounds what can be called non-semantic but not who calls it |
| trend halt (arms, once-per-arc) | the observation arm is discharged by the halted party writing prose, and the arc it is counted over is recorded by that same party; the second-halt escalation is what bounds it, not the first diagnosis being right |
| topic floor cost (no-exemption rulings) | floor cost is real: every topic pays pin + card + check + design/grill + per-round lenses regardless of size — priced in deliberately by the no-exemption rulings |
| self-iteration (observations → retro → promotion; iteration log; model-dependency register) | ingests only what authors record, and anchor matching is only as good as the one-line index; the register re-opens rules only when the model-changed question is answered honestly |
| maintainer / workflow-source edits | a fresh session sharing the model family, self-administering its own constraints (doc caps, `COMMIT_CAP`, between-rounds timing); git rollback is manual; the external check is the owner reading release reports |
| shared-understanding section | two ceilings, the second being the one the reality cell states twice: it catches only what the owner actually reads closely — a skimmed brief passes a wrong model — **and only what the author thought to put in the table**, so the audited party selects what gets audited, exactly as the authorities inventory does. Its live-run instance is Campaign C's invariant catch, which was a *reality* claim; the intent half is the one carrying debt (`rationale.md`) |
| round metrics / escape count | counts measure finding production and detected escapes, not remaining defects — a clean round can mean tired instruments (mitigated by always-fresh reviewers), and escape attribution is an owner-signed judgment; the mandate-coverage field is author-filled — a round that misreports its coverage reads as deep rather than dead |
| specification ledger / full-tree review unit | proves delegation, not delivery quality — a wrongly-drawn delegation boundary reads as discharged until a full-tree review walks it |
| release-round lens classes (`protocol.md` §7) | the same relativity as the topic lens set, one level up: the two classes bound what a release round can see, and a third class not yet invented is invisible to both — a quiet release round is evidence about the classes run, never about the tree |
| admission / generator map | constrains where mechanisms live and that ceilings exist, not that the mechanisms are good — that is the reviewers' and the owner's judgment |
| conformance harness (`self-check/`) | every check catches a broken **reference**, never a wrong **idea** — a §N that resolves and misleads, a constant whose value is badly chosen, a vocabulary that matches on both sides and is wrong on both, all pass green. It covers only invariants someone thought to encode, and a green run is a *precondition* for a release round, never a substitute for one |
| maintainer entry-line item slot | the slot carries what the dispatcher thought to name: a ruling nobody routes is still lost, and the line cannot say whether the pointer it carries is the whole of what is owed — the close-out that named the item is not read by the session that receives it |
| landing-record write grant (a family row's `landing`/status field) | the field boundary is prose: the rung-2 arm checks anchor **counts** — the harm the single-writer rule names — never that *only* that field moved, so a maintainer who rewrites observation text while leaving anchors untouched passes green, and the next retro is the first reader who could notice |
| frozen-version snapshot marks (`plan-dir/invariants.md`) | the mark is applied by the author at freeze time, so it reaches only the sentences the author recognises as citing mutable state — the same recognition failure it exists to fix, one level up; nothing checks that a sentence citing card state carries one |
| dispatch watch + restart-line delivery | both are prose duties with no receipt: a watch registered in the authoring session dies with it, and nothing checks it was set; whether the line was handed over is carried only by the counterpart's next move — the same session writes the close-out and reports its own delivery |
| owner-initiated ruling entry | the entry is author-timed: an owner aside the author does not recognize as a ruling goes unrecorded — the recognition failure the snapshot marks name, one door over; and the row's six fields are the author's re-derivation, so a lazy one launders a casual remark into a signed ruling |
| whole workflow | the mechanical invariants have a harness (`self-check/`); above them enforcement is schemas + independent instruments + the round structure actually being followed — by an author running it honestly: verbatim persistence and metric counts are clerical duties with no independent check, so the design removes cheap drifts, never deliberate fraud; a determined-to-game author with a rubber-stamp owner defeats everything (the predecessor conceded the same) |
