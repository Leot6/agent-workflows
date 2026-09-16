# planning-workflow — protocol

> The executable stage protocol — what a session actually does, stage by stage.
> Definitions, rationale, and everything locked live in
> `../design/architecture.md` (cited as A§n); this file holds **procedures,
> tables, and defaults** and restates no locked content. The kickoff line
> (README) points here. Cap: `DOC_CAP_PROTOCOL`.

## 0. Session start — find your position

0. **Which kind of session is this?** A line naming `maintainer session:`
   (§7's variant) is a **maintainer** session, not a topic one: steps 1–6
   below do not apply — there is no checkout to resolve and no card to drift-
   audit. Route by its `task`: *retro for topic at `<root>`* → §4.11 steps
   2–5 and 7, reading that topic's close-outs; *between-rounds edits* →
   §4.11.7's landing discipline; *release round* → §7's release-round
   procedure. Everything below is the topic session.
1. Resolve from the kickoff/restart line: the workflow tree path, the topic
   root path, the **code checkout path(s)**, and (at topic start) the owner's
   **topic statement** — one paragraph of rough intent; an `amend topic at`
   line (§7) carries a **cause paragraph** in that slot instead. All absolute.
2. If `<topic>/planning/` does not exist → **topic start**: create
   `planning/{briefs,rounds/0}`, record the topic statement verbatim at the
   top of `planning/design.md` (it is input, not yet a claim), then run
   `baseline` (§4.1).
3. Else if no close-out exists yet → **round 0 in progress**: re-anchor from
   the card's pin header, `grill_sheet.md`'s branch-closure section (if it
   exists), and `briefs/` (read every 裁决 line; unanswered sections are your
   park set); resume at the first unmet step **in order §4.1 → §4.2 → §4.3**
   (no card ⇒ §4.1; no clean check record ⇒ §4.2 — the mandatory check cannot
   be skipped by resumption).
4. Else → read the **latest close-out** in `planning/rounds/<highest n>/` (the
   highest k by NUMERIC value, unsuffixed = k=1 — never `ls | sort`, whose
   locale collation reorders them; §4.9 states the criterion): its
   settled-state table and open-findings register are your entry points (A§8);
   resume at the stage its Next section names — **that instruction wins
   whenever Next names a live stage** (an amend arc in progress resumes
   there, not at §4.8's entry). Only when Next names no live stage and the
   decision log carries a signed convergence or abandonment row is the
   topic terminal: the only entries are a **new** `amend` (§4.8) and
   `retro` (§4.11) — **the entry line names which**: an `amend topic at`
   line (§7) is the first; retro arrives as the maintainer variant and was
   already routed at step 0. Consult older artifacts per
   claim via pointers — never re-read the tree wholesale.
5. **Every cold start runs the drift audit** (§4.0) before any stage work.
6. **The workflow may have moved too.** At topic start there is no close-out
   and nothing to compare — round 0's records the first. Otherwise compare the
   latest close-out's recorded workflow SHA with `git -C <ABS workflow> rev-parse HEAD`; on a
   difference, read `git -C <ABS workflow> diff <recorded>..HEAD` before any
   stage work. **Template changes are work** — a template shapes artifacts
   already written, so an artifact emitted under the old one is re-adapted
   here; protocol and prompt changes need nothing, since this file is read
   live and prompts are instantiated fresh each round. A§11 bars tree edits
   on a live round: this step does not permit them, it makes a breach visible
   instead of silent.

## 1. §defaults — the single home of every tuning value
(exception: per-template assignment-criteria thresholds, delegated by A§5.3)

| constant | value | unit | governs |
|---|---|---|---|
| `ANCHOR_MIN` | 2 | independent anchors | prose-rule promotion (A§1) |
| `RECUR_MIN` | 2 | rounds | closure-proof declaration (A§3) |
| `ROUND_MAX` | 5 | rounds | scope-brief trigger (A§4; checked at §4.6.4) |
| `GRILL_MAX` | 4 | batches | scope-brief trigger (A§4; checked at §4.3.2) |
| `REFINE_MAX` | 3 | passes | rung-1 cap (A§7) |
| `REVIEWER_REFINE` | 1 | pass | reviewer self-falsification (A§3) |
| `REMOVAL_TOPICS` | 2 | topics | removal candidacy; sintering-candidate retirement (A§4, A§11) |
| `SPOT_N` | 3 | work items | architecture-lens spot-check (A§3) |
| `RESPAWN_MAX` | 2 | re-spawns | per instrument assignment; cap-out → owner brief item (§4.5.3) |
| `BRIEF_MAX_ITEMS` | 7 | sections per brief | one owner sitting (A§10); exceeding splits by settled prerequisites |
| `PLAN_HASH` | manifest sha256 | working version: sha256 of the sorted `relpath,sha256` lines **joined by `\n` with no trailing newline**, over the version directory; promoted `plan.md`: single-file sha256 of the concatenation | plan content hash (A§9) |
| `DOC_CAP_PROTOCOL` | 838 | lines | this file (800→804 the multi-checkout audit-target sentence; →820 the delivery-duty pair: dispatch-watch + restart-line hand-over; →827 the per-assignment delivery directory; →838 the owner-initiated ruling entry) |
| `DOC_CAP_CLAIMS` | 400 | lines | `claims.md` |
| `DOC_CAP_PROMPT` | 300 | lines | each file under `prompts/` |
| `DOC_CAP_TEMPLATE` | 200 | lines | each file under `templates/` |
| `DOC_CAP_ARCH` | 818 | lines | `design/architecture.md` (800→806 self-readings/class/ruler insertions; →810 the directory-form surgery's tree-map and concatenation-contract lines; →816 the landing-record write grant and the entry-line item slot, each with its ceiling row; →817 the dispatch-watch + restart-line-delivery ceiling row; →818 the owner-initiated-ruling-entry ceiling row) |
| `DOC_CAP_RATIONALE` | 300 | lines | `design/rationale.md` |
| `DOC_CAP_README` | 100 | lines | `README.md` |
| `COMMIT_CAP` | 500 | changed lines | one workflow-tree commit (single-purpose; bootstrap/import commits exempt, marked in the message) |

`iteration-log/` carries no line cap — the directory (INDEX + open/ +
owner-queue/ + debt ledger + model register) is bounded by the state-file rule
(A§11: closed entries prune to one-line index rows at harvest; git holds
history); `.gitignore` is configuration and `self-check/` and `runtime-scripts/` are
executable, not documents — no cap applies to any of them (a check's length is
set by the invariant it proves, a launcher's by the CLI it drives, and each
states its honest boundary in its own header rather than in a sibling `.md`).
Changing a value here is a workflow-source edit (A§11: between
rounds only; git is the rollback path). A budget reset granted by a signed
scope-out row (A§4) overrides `ROUND_MAX`/`GRILL_MAX` for that topic, from
the row; the row's budgets are counts of further rounds/batches for the
current arc, never absolute round indexes (A§4: budgets count per arc).

## 2. Cold/warm table — the single home (A§8 states the principle)

| actor / moment | temperature |
|---|---|
| round 0 start (baseline authoring) | **cold** |
| baseline-check and every verifier assignment | **cold** (always fresh) |
| design ⇄ grill loop, within | warm |
| every round's draft start | **cold** |
| every reviewer, every round | **cold** (always fresh) |
| within a round: dispatch → disposition → close-out | warm |
| event trigger: a finding shows a baked premise contradicts code | **immediate cold restart** |
| event trigger: scope / foundations pivot | **immediate cold restart**, paired with a cold re-read |
| retro (and editorial amend) | cold-capable — runs from artifacts alone |
| warm-eligible draft (construction-form previous round) | **warm** — the four preconditions at §4.6.4's discriminator all hold; any miss ⇒ cold |
| every other draft (derivation-form, round 0, foundations pivot, candidate) | **cold** (unchanged) |

## 3. Lens table — which reviewers run

Lens short ids (fixed; used in file names and finding ids): `arch` ·
`red` · `meta` · `exec` · `delta`; the closure-proof assignment's finding
ids use `closure`. `<instrument>` in file names = a lens id or `verifier` /
`closure`.

| round | lenses dispatched |
|---|---|
| 1 | arch · red · meta · exec |
| 2 … n, no `foundations` disposition in the previous round | arch · red |
| any round following a `foundations` disposition | + meta |
| a **convergence-candidate round** — declared in the previous close-out's Next section, allowed only when the open-findings register is empty (§4.6.4's declaration bar) | arch · red · meta · exec |
| any round with a signed closure-proof declaration | the lenses of whichever row above applies, **plus** the shared closure-proof assignment |
| a **delta round** — the previous round was construction-form (§4.6.4's discriminator: register fully landed, no pivot, not a candidate) | `delta` alone (the verify-delta instrument, `prompts/reviewer_delta`; a foundations disposition in the previous round disqualifies — full lenses instead) |

A lens skipped relative to this table is recorded, with the reason, in the
round's close-out. **A§3's invariant dispatches are outside that clause** —
meta at round 1, after any `foundations` disposition, and at the
convergence-candidate round; exec at round 1 and at the candidate round. An
invariant lens that does not return is **instrument failure** (§4.5.3):
re-spawn, and a cap-out is an owner brief item — never a recorded reason.

## 4. Stage procedures

### 4.0 Drift audit (every cold start; A§2)

At topic start (no card yet): for **each** repository the topic touches,
record `git -C <checkout> rev-parse HEAD` and `git status --porcelain` as the
**initial pin** rows of the card's pin-header table,
classifying any porcelain output benign/blocking exactly as below — blocking
⇒ a clean tree before pinning; the SHA-comparison arm applies from the second
cold start. Thereafter, per pin-header row: HEAD vs the
pinned SHA + porcelain for working-tree drift; record `clean` / `benign:
<files + why harmless>` / `blocking: <files>`. **The criterion** (not a
judgment call): drift is `benign` only when **no** listed file is an
evidence site of a card row, a site or fixture the plan names, or a file
this stage will read — otherwise `blocking`. **Build and test output this
round's own instruments produced** is a class of its own: recorded as
`instrument: <files>`, never weighed in the test above. A verifier is told to
dry-run commands where it can and a reviewer is told to audit the tree it
finds, so the workflow dirties the checkout it then convicts; scoring that as
drift makes the card look wrong for having been accurate when written. Before a card exists the test
has no data, which is why the initial-pin arm demands a clean tree
outright. **A pin-header row naming more than one checkout names its audit
target** — the audit, the criterion and every class above read that checkout
alone; the row's other checkouts record `note: <files>`, asserting the pinned
SHA is still an ancestor of each one's HEAD, and are never `benign`/`blocking`
(measured: the criterion and a card row gave opposite
verdicts on one drift because the row held two trees). **Blocking → halt the stage
until re-pin or a clean tree.** On re-pin: diff the SHAs; every card row whose
evidence sites the diff touches reverts to `unverified` (A§2); list the
reverted rows in the pin header.

### 4.1 `baseline` (round 0 opens; cold — §2)

1. **Start here in a fresh session** (§2: round 0's start is cold). Pin per
   §4.0 (initial-pin arm).
2. Author `planning/baseline.md` from `templates/baseline`: one row per
   load-bearing fact (claim · shape · evidence per `claims.md` ·
   falsification target, that site opened), reading outward from the topic
   statement; fill the **authorities inventory** (every design doc, prior
   decision record, or opposing document bearing on this topic — the
   meta-critic's `{PRIOR_OPPOSING_DOCS}` fills from it) and the staleness
   appendix.
3. Refine (§4.10) on the card.

### 4.2 `baseline-check`

1. Instantiate and spawn a **verifier** (§5) on `prompts/baseline_verifier`.
   The verifier **returns** the completed check record as text; the author
   persists it verbatim to `rounds/<n>/check_<k>.md` (`k` sequential per
   round) and may not edit it.
2. Flip row states **citing the record** — the citation is the flip, so a
   bare flip is not available. A `disputed` row stays `unverified` and
   blocks approval and dispatch like any other row in that state; run
   A§3's dispute path from here, each re-check a fresh verifier dispatch
   (§5).
3. On a clean record **the card freezes**: later additions enter `unverified`.

### 4.3 `design ⇄ grill` (the loop: 1→2→3→4, repeat until 5 holds)

1. Author/amend `planning/design.md` from `templates/design-doc` (scope
   section · shared-understanding claims with examples · sections with
   `depends-on` rows). After each answered batch, fold the answers in and
   re-extract — that is the "⇄".
2. Extract unresolved branches into `planning/grill_sheet.md` (template:
   `templates/grill-sheet`); batch by
   settled prerequisites; ≤`GRILL_MAX` batches, exceeding = scope brief
   (A§4). **One batch = one set of brief sections; one question = one section**
   (so one decision-log row per question); co-pending items share the
   brief file (A§10).
3. On every owner reply: re-derive premise-then-landing-site **before
   baking**; **one file per brief, one `## R'-<k>` section per reply** —
   greppable, countable, reconcilable against the reply count at close-out —
   round 0 appends to `planning/rederivations.md`, rounds ≥1 write
   `rounds/<n>/rederivation_<k>.md` (template: `templates/rederivation`).
4. Section approvals ride brief items and land as signed rows — the first
   design-approval brief presents the shared-understanding table as its own
   section, so every SU claim passes under the owner's veto; approval is
   blocked while a listed `depends-on` row is `unverified` — dispatch a
   verifier to clear the set first.
5. Exit only when every branch across all batches is terminal
   (grill sheet's branch-closure section).
6. Close round 0: write its close-out per §4.9 (`closeout.md`, or the
   next `closeout_<k>.md` when earlier round-0 stops already wrote one —
   never overwrite).

### 4.4 `draft` (round n ≥ 1; cold)

1. **Start this stage in a fresh session** (§2: every round's draft start is
   cold) — if you wrote the previous close-out in this session, stop and hand
   over its restart line instead. Then create `rounds/<n>/`; re-anchor per
   §0.4; drift audit per §4.0.
2. Write `planning/plan_v<k>/` (a **directory**) from `templates/plan-dir/`,
   k = one more than the highest existing version index (never overwrite a
   prior version; version indexes are a monotone counter, decoupled from
   round numbers): `00_context.md` (header, execution context, coverage),
   one `items/W-<id>.md` per work item with the full A§4 field set,
   `invariants.md`, `rederivation.md`, `delta.md`. The version's verifier
   record is a **pointer, never a status** — "the verifier record for this
   version is at `rounds/<n>/check_<k>.md`", never "not yet returned" or
   "returned clean": the plan freezes at step 4 and the verifier is
   dispatched at step 5, so a status written here is true for one hour of
   the version's life and false for the rest of it.
3. **Mechanical diff against `plan_v<k-1>/`** (per file set): every symbol,
   site or list item the prior version carried and this one does not is
   restored or given a recorded reason; **the diff IS `delta.md`** — changed
   file list, signed rows landed with their landing tables, and the
   same-section reading-consistency scan (readings cited from
   `rounds/<n>/plan_hash.md`, never inlined). Versions are archived so a
   rewrite can be checked against what it replaced, and nothing else asks
   anyone to look.
4. Emit-time claims check per `claims.md` — **run `runtime-scripts/emit_gate.sh
   <plan-version-dir> <checkout-root>` over the version and clear or justify
   every red before freezing** (the tree-owned red gate: currency counts carry
   their commands, sections agree with themselves, citations resolve — the
   printers-to-gates ruling; findings are refine input, not a hard stop); refine
   (§4.10) — residual findings at the cap ride to reviewers, flagged in the
   plan's own refine log (the artifact carries its residue; the prompts carry
   only their slots, §4.5.1).
   **A signed gate whose coverage is narrowed at execution time** (the
   literal run proves unworkable and the author runs a subset) does not count
   as run for that round: the narrowing goes to the owner as a brief item —
   even a retroactive one — and the round's metrics name the gate as narrowed
   (measured: the narrowed half of one ruling was exactly where the
   executor lens's findings later landed).
   **Then freeze**: record the version's **manifest hash** in
   `rounds/<n>/plan_hash.md` — §defaults' `PLAN_HASH` working form, to which
   this restatement defers (one file's edit
   moves the hash; an added file does too) — outside the plan, because a
   hash inside the file it hashes never re-verifies (A§9) — then **lock the
   directory** (`chmod -R a-w`; unlocking for the next version is the one
   deliberate friction the freeze deserves — measured: the discipline was a
   record, not a lock, and a post-freeze edit happened with nothing
   mechanical in the way). Make no further edit to this version. Every
   instrument dispatched from step 5 on reports the manifest hash it read,
   so two instruments reading different bytes under one version number
   becomes visible instead of being a number they both honestly agree on.
   A correction found after the freeze is the next version index, not an
   edit to this one (unlock ⇒ next k, re-lock).
5. Dispatch a verifier (§5) to (a) clear every `unverified` row the plan's
   `depends-on` fields list, (b) resolve every command the plan carries
   (A§2). **§4.5 may not begin while (a) leaves any listed row `unverified`**
   — the A§2 dispatch gate.

### 4.5 `review`

1. Prepare the round's inputs: write
   `rounds/<n>/register_stripped.md` (the open-findings register **with
   layer tags stripped**) and instantiate each prompt to
   `rounds/<n>/prompt_<instrument>.md` — **fill every `{SLOT}` the prompt
   declares**, nothing else; never edit mandate text; `{PRIOR_OPPOSING_DOCS}`
   fills from the card's authorities inventory.
2. Spawn one no-lineage reviewer per lens the table dispatches for this
   round (§3, §5). Under `{DELIVERY}`'s file form the dispatch is three acts
   rather than one — **launch** every lens, **collect** each, **copy** each
   deliverable into its named file — and launching returns before the
   instrument has begun, so the round's lenses run concurrently and no
   author-side timeout bounds a review turn. A launched session outlives the
   author: a restart mid-round collects what is there instead of re-spawning
   it, which the first form cannot offer. Whoever gives up on a lens
   **captures the attempt before tearing it down**, or §4.5.3 has nothing to
   persist. **Dispatch ends the session's forward work** — the §6 rule,
   applied here: the author's own turn ends at dispatch (author findings and
   any pre-disposition notes already on disk), a close-out is written with
   Next naming collection, and the session stops. The instruments keep
   running detached; a fresh session collects them (§7's topic line, stage `review`).
   Waiting inside the authoring session buys nothing — its context idles
   against a wall clock the instruments own — and costs the author-side
   context a later round would spend. **Setting a watch is part of
   dispatch**: before stopping, the dispatching party registers whatever
   this deployment offers that fires on a sentinel's appearance, and the
   close-out's Next carries the **wait condition**, not a polling
   instruction — the interval between the last sentinel and collect is then
   bounded by the next human interaction, not by whoever next happens to
   look (measured: three sentinels sat forty
   minutes unclaimed after the dispatching session stopped, until the owner
   asked — the rules ended the duty at dispatch, the effect needed a
   delivery). Reviewers
   return text only; the author persists each return **verbatim** to
   `rounds/<n>/findings_<instrument>.md` — a second assignment to the same
   instrument in one round (a delta review, §4.6.4) takes
   `findings_<instrument>_<k>.md`, **k = 2, 3, … — the unsuffixed file is
   the first**, as for close-outs (§4.9); **never overwrite a prior return** (closure-proof return →
   `rounds/<n>/closure_proof.md`).
3. Instrument failure (null / off-mandate / crash) → **persist the return
   verbatim first** to `rounds/<n>/findings_<instrument>_failed_<k>.md` —
   whatever the attempt produced: the returned text, the deliverable file if
   one was written without its completeness marker, or whatever record of the
   attempt the deployment can produce if neither exists
   (nothing an instrument returned is ever discarded — A§3's ban on
   re-rolling has no carrier if the text that would show a re-roll is
   deleted by the act), record it in the
   close-out's instrument-failures row, re-spawn fresh (≤`RESPAWN_MAX` per
   assignment; a re-spawn on failure is not a re-roll, A§3); cap-out → an
   owner brief item. A return that is on-mandate but merely **incomplete in
   form** (a missing Clean-categories or Range-read section) is not a
   failure: request nothing, persist it, and record the gap.

### 4.6 `disposition`

1. Tag-route per A§3: any `foundations` tag (stricter tag wins on
   disagreement) → a brief item; `implementation` findings → dispositions
   with evidence in `rounds/<n>/disposition.md` (template:
   `templates/disposition-ledger`), fix claims traced per
   `claims.md` before any fix is baked. Reviewer **R-Q** questions route into
   the round's brief alongside findings. The executor's two returns are
   transcribed **verbatim** (carried text) and go to different places,
   because they are different kinds of thing. Its **question inventory** is
   findings-like: each question enters the **open-findings register** at
   this step, like any other finding, and leaves it the same way any finding
   does — root-fixed, refuted, or answered by a row signed through **this
   round's own brief** (steps 2–3 below, which close before step 4 reads the
   register). Its **zero-context row** is a statement, not a question: it
   goes to the close-out, and at a convergence round to checklist E-2; it is
   never a register row, since A§8's three doors have nothing to do with it.
   A return of "empty" / "none" is recorded and creates no row either way.
   At a convergence round E-1 transcribes the inventory's rows and their
   dispositions — a **view** of the register, not a second destination —
   which is what lets A§9's gate read "question-inventory empty **or** every
   remaining question has a signed disposition". A
   register row so placed carries `layer: implementation`, or `foundations` where the
   question is about scope, premises, authority, or completeness of the
   model (A§3's classes) — the author is placing a non-reviewer row, not
   re-tagging a reviewer's.
2. Batch all owner items into one brief (§6). If a completeness class has
   recurred ≥`RECUR_MIN` rounds, author the **closure-proof declaration** as
   a brief item carrying: the class · the recurrence evidence · the root
   hypothesis · the operator map (a starting map, to be corrected against
   code) · the directed checks — the signed row's content fills the
   assignment's slots next round.
3. On replies: one re-derivation record per reply (§4.3.3), sign rows, then
   bake.
4. Close the round (§4.9). **LOOP/converge decision** per A§8's stop rule.
   Two overlays are evaluated **first**; the table then decides, top-down,
   first match winning.

   **The round-temperature discriminator — construction-form decidability**
   (defined HERE, the single home; §2's temperature column and §3's delta
   row both cite it, neither restates it). The previous round's final
   (highest-k) close-out register is **construction-form** when every row
   carries a landing instruction — the close-out register's landing column:
   item file + edit summary + evidence pointer, schema-checkable — and no
   pivot event intervened; it is **derivation-form** when any row lacks one.
   Construction-form ⇒ the next round's author side is **warm-eligible**
   (preconditions below); derivation-form ⇒ cold, as always.
   *Warm preconditions (all four, evidence carried into the delta
   reviewer's provenance check — any missing ⇒ the round reverts cold and
   an obs records why):* ① the close-out is complete and hash-recorded
   before warm continuation starts; ② every edit rides an archived script
   (old→new per script, the lineage hedge); ③ a cold delta review
   covers the plan (the instrument below); ④ the drift audit (§4.0) and
   workflow-SHA comparison (§0.6) re-run at the round boundary — the
   boundary's detection duty travels with the boundary. The anti-gaming
   row: warm eligibility falsified by the cold delta reviewer (the landing
   instructions did not actually cover the work) ⇒ the round reverts cold
   and records the observation. Candidate rounds and foundations pivots
   are unconditionally cold; reviewer instruments stay cold regardless.
   **Overlay 1 — the trend halt.** From the second lens-bearing round on,
   evaluate A§8's severity-trend rule over the **final** (highest-k)
   close-out metrics rows of the last two lens-bearing rounds, **summing only the
   instruments both rounds dispatched** — an instrument first sent this round
   joins neither side, since adding a sharper instrument raises the count and
   that is the workflow working, not the plan worsening. The per-instrument
   breakdown the metrics row carries is what makes this computable, and it is
   also what the diagnosis reads: a round whose structural lens returned zero
   is a different fact from one whose structural lens returned four: substantive
   count non-decreasing across the pair → halt and diagnose — never a blind
   further round. **Exempt only when both counts are zero *and* the register
   is empty** (A§8): that pair is convergence; zero production over an open
   register is a stuck loop, which is the case the halt exists for. Two arms (A§8): a **scope brief**, or — **once per arc** —
   a **workflow observation**, whose diagnosis goes in this close-out's
   observations table with what would falsify it (§4.11.1 ingests it at
   retro — one writer into the log, so one anchor per event). Once
   diagnosed, the table's outcome may be
   taken: the halt forbids proceeding *undiagnosed*, not proceeding.
   **A second consecutive halt in the same arc has only the scope-brief
   arm** — the previous diagnosis is thereby falsified, and the party whose
   loop is halted does not clear it twice. Round 0 runs no lenses; its
   metrics row is a baseline record, not a trend input.

   **Overlay 2 — the budget.** Rounds count from the arc's entry round
   inclusive (both recorded in every close-out); the budget is `ROUND_MAX`
   or the arc's signed scope-out row's, and a convergence-candidate round
   consumes it like any other — A§4's bound is unconditional. **Once the
   arc's budget is consumed, any outcome below that would spend another
   round becomes a scope brief instead** (A§4) — a LOOP, a candidate
   declaration, and a candidate round that re-opened `foundations` items
   alike; the signed scope-out row grants the budget the outcome needs.

   The candidate round's **delta rule** serves A§8's shipping invariant —
   nothing ships unread at the version it ships — so it scales with what the
   round actually changed, not with whether it changed anything. Classify the
   round's delta against A§4's work-item field set — **by complement, so
   this file keeps no second copy of that set**: **non-semantic** = an
   item's `id` or `title`, and text that is not the content of any other
   A§4 field; **semantic** = the content of any other A§4 field, the
   execution-context preamble, or a coverage row. There is no third
   category: a field's content is semantic *because* it is a field's
   content, whether it reads as prose or as a symbol. A field A§4 gains is
   semantic until A§4 says otherwise — the safe direction, since the arm
   this decides is the cheap one. Directory form makes the carrier
   mechanical: a delta confined to an item file's `# W-<id>:` title line or
   `00_context` metadata rows is non-semantic by file shape; any other edit
   is semantic — `delta.md`'s changed-file list is the classification's
   input, no judgment over prose needed.

   | this round | register after disposition | outcome |
   |---|---|---|
   | a declared candidate round | empty, no delta | **`converge`** → §4.7 |
   | a declared candidate round | empty, **non-semantic** delta only | **delta review**: one `arch` dispatch on the new version, mandate unmodified; clean → `converge` (§4.7), any finding → the register and the table is re-taken |
   | a declared candidate round | empty, **semantic** delta | the next round is a candidate **again**, full lens set — the interaction surface is the whole plan, and the executor's provenance must equal the version the convergence brief reviews (A§9) |
   | any round | empty (every finding through one of A§8's three doors) | the close-out's Next declares the next round a **candidate** |
   | any round | non-empty | **LOOP** → §4.4 |

   A delta review narrows **the round**, never the instrument: one lens
   instead of four, reading the whole plan under the unmodified mandate —
   which is why it needs no new prompt, slot or scope wording, all three of
   which §5.1 forbids. It consumes no arc round.

### 4.7 `converge` (the convergence-candidate round's disposition passed)

1. Verifier pass: remaining depends-on `unverified` rows cleared; every
   command resolved. Unreferenced `unverified` rows are then swept —
   **`verified` only through a check record** (a verifier's verdicts are
   `verified` / `disputed`, never `retired`), so **`retired` is the
   author's own claim**, and it is the cheap branch: its recorded reason
   names what would have depended on the row had the depends-on lists been
   wrong. A§14 makes this sweep the recall path for exactly that omission.
2. Fill the convergence checklist (`templates/convergence-checklist`):
   item-level and plan-level rows; **transcribe the executor's returned E-1 /
   E-2 rows verbatim** (carried text — the executor cannot write files).
3. Convergence brief (§6) with the checklist as appendix; owner signs.
   **A non-signing answer** enters each objection on the open-findings
   register as an owner-sourced finding (re-derivation per §4.3.3; layer
   `foundations` — narrowing it is a **re-tag**, which A§3 reserves to the
   owner as a signed row, so the author may not narrow the objection that
   withheld its own signature) and returns
   to §4.4 under the arc's budget rules; a deferral parks the topic
   (A§8). Only a signature proceeds.
4. **Post-signature**: produce the final plan version as the next
   `planning/plan_v<k>/` **directory** (monotone counter) — the signed version plus the brief's signed dispositions (diff in cell P-6b);
   confirm the executor's provenance against the version the brief reviewed
   on A§9's terms (equal, or differing by non-semantic delta only — checklist
   P-6); **dispatch a verifier (§5) on the final version to re-derive each
   incorporated disposition against its signed row** — the one content in
   the topic that no instrument has read, and carried text besides, so the
   check record is what discharges A§8's shipping invariant and is the
   attestation P-6b records; promote via A§9's `plan_concat.sh` (never a
   copy); record `PLAN_HASH` + pinned
   SHA(s) on the convergence row (the post-promotion attestation of
   checklist row P-6b).
5. Proceed to `retro` (§4.9 duties, then §4.11).

### 4.8 `amend` / `parked` / `abandoned` / split

- **amend**: entry is §7's amend line; §0.4's terminal test routes here.
  **Classify first**: the entry session reads `plan.md`, the decision log and
  the entry line's cause paragraph, and emits the amend brief — the round
  directory opens only on a signed `full` row, so an editorial amend never
  creates one. Classify per A§4 — the classification, its diff (§6) and the
  re-entry stage all ride the signed row. Full ⇒ open a new round
  directory, resume at the stage A§4's classification names, and record the
  arc and its entry round in that round's close-out (§4.6.4 reads them).
  Editorial ⇒ no round. Hash mismatch on entry: owner brief, dispositions
  per A§4.
- **parked**: close-out with the open set enumerated; stop. Resume re-runs
  §4.0; blocking drift → `baseline`. Retro may run while parked.
- **abandoned**: author proposes via brief (six fields + archive summary);
  owner signs; close-out; then §4.11.
- **split** (a scope-brief outcome — A§4: abandonment plus two new topics):
  the signed split row names both new topic roots **and carries one topic
  statement per child** (the brief's 附加字段). **Every open finding is
  disposed before the row is signed** — through one of A§8's three doors on
  the parent's ledger, or transcribed into the child whose scope covers it,
  landing in that child's round-0 close-out register. A split is not a
  fourth door: `abandoned` never passes A§9's gate, so nothing else would
  ever ask what was open, and the scope brief proposing the split lists the
  set so the owner signs knowing it. Then close this topic out as
  `abandoned` per the row. Create each new root's `planning/{briefs,rounds/0}`
  with the pin and a copy of the card **including its check records**,
  written into the child's `rounds/0/` as `check_<k>.md` with every card
  citation rewritten to the child's path (a dangling citation fails §0.3's
  "no clean check record" test) — the copied rows keep their states (§4.2 is
  discharged for them by the inherited records at the unchanged pin, not
  exempted; new rows and re-pins take the normal A§2 path). **The child then
  completes the card against its own topic statement** — §4.1 step 2 read
  outward from *that* statement: rows the parent never needed enter
  `unverified`, and the authorities inventory and staleness appendix are
  re-filled for the child's question (an inherited inventory aims the
  meta-critic's `{PRIOR_OPPOSING_DOCS}` at the parent's topic). Plus
  `planning/design.md` from
  `templates/design-doc`, its topic statement transcribed **verbatim from
  the signed row** (carried text). Each new topic enters `design ⇄ grill`
  (§4.3) with fresh budgets; its scope section draws from the split row.
  The parent's final close-out's Next section records one kickoff line per
  child (README's variant, quoting the row's statement); the fenced
  restart line stays the parent's own.

### 4.9 Close-out duties (every round, 0 included)

Write the round's close-out from `templates/close-out` —
`rounds/<n>/closeout.md`; when a round emits more than one (every
brief-driven stop writes one, §6 — round 0 routinely stops per grill batch),
the next is `closeout_<k>.md`, k = 2, 3, … sequential; the highest k is the
round's latest; **never overwrite a prior close-out** — its observations are
retro's input (§4.11.1). Before closing the round: print the actual
`## R'-` header set over the round's rederivation file(s) and reconcile it
against the round summary's owner-reply count — a missing number halts; the
close-out enumerates the headers it claims, **never an ellipsis range**
(measured, r6: two records existed only as an ellipsis). **The highest k is taken numerically, the unsuffixed
file counting as k=1** — `ls | sort` is not a discriminator: locale collation
ignores punctuation, so `closeout.md` sorts AFTER `closeout_5.md` and a cold
session following the sort lands on a superseded close-out (measured). Contents: round summary
(lenses run/skipped + reasons; **instrument failures/re-spawns**),
settled-state table, open-findings register, the round-metrics row
(mechanical counts by severity — the A§8 trend rule's input — plus a
**per-class breakdown** product/provenance/doc-sync/artifact carried from the
instrument-assigned class column: a readout of what the register is made of;
no gate reads it), required
observations ("none" explicit), required zero-context field, Next (resume stage; a
convergence-candidate declaration lands here), and the fenced restart line
as the file's final content. **And the session's final act is to hand that
line to the counterpart verbatim** — the file is the durable copy, the
conversation is the delivery; a close-out nobody hands over leaves the next
round waiting on the owner's own initiative (measured: three
consecutive close-outs carried the line while
the author said "next round, new session, cold" without once handing it
over, until the owner asked for the prompt — the rule ended at the file;
the next session needed the delivery).

### 4.10 Refine (any artifact, before it counts as emitted)

Run `prompts/refine_falsification` against the artifact, ≤`REFINE_MAX`
passes; applies to the five author-emitted artifacts (card, design doc,
grill sheet, briefs, plan), whose templates each carry a refine log; stop on
a clean pass; a dirty cap-out flags its residue for the next instrument.

### 4.11 `retro` (topic end; also runnable on a parked topic)

Actors (A§3's role table): steps 1 and 6 are the topic author's
(observation entries and retro ingestion are the author's explicit grant —
its one workflow-tree surface); steps 2–5 and 7 are the maintainer's —
workflow-tree edits and cross-topic acts, a fresh session, never this
topic's author (the topic's close-outs supply step 2's evidence
citations); a maintainer session enters via §7's maintainer variant,
**carried by the author in the final close-out's Next section** — the
handoff the split arm (§4.8) makes for its children, made here for the
maintainer half of this procedure.

1. Ingest every close-out's observations into the workflow tree's
   `iteration-log/` (INDEX + open/ files; staging file when non-empty), with
   anchors — **and reconcile the staging file**
   (A§11) into the tables, emptying it: staging is the maintainer's and the
   instruments' only inflow and this step is its only reader — and, on an abandoned topic, the signed
   abandonment row's archive summary with them (A§4: it spares a later topic
   re-deriving the same option, which it can only do from here once the topic
   tree is cleaned).
2. Check each open validation-debt row for exercise evidence — close with
   the citation, then **prune the closed row to its one-line index entry**
   (the state-file rule, A§11).
3. "Model changed since last retro?" — if yes, re-open every row of the
   model-dependency register for review.
4. Raise removal candidates (no catch across `REMOVAL_TOPICS` topics) to the
   owner; removal lands only as a signed ruling.
5. Retire sintering candidates that reached `REMOVAL_TOPICS` topics without
   a second anchor (one-line index entry, pointer kept). An **`adopted`**
   row whose mechanism has been in the tree long enough that the adopting
   observation needs no further anchor tracking takes the same exit — one-line
   index entry, pointer kept (its full text is in git; the state-file rule
   bounds the log, not the history).
6. Compute the topic's **escape count** (full-amend rows whose cause predates
   convergence) and record it with the round-metrics history **and the
   topic's cumulative owner-item count** in the final close-out, **dated** —
   the planning-DRE inputs for cross-topic comparison, and the one place the
   owner-item total is read: what a topic cost the scarcest instrument is
   comparable across topics in a way a single round's count is not (A§10).
   At the retro that follows promotion it is **0 by construction** (no amend
   can exist yet); that reading is a baseline, not a result. Every later
   retro — each full-amend arc routes back here via §4.7.5 — **recomputes
   and re-dates it**, and only a dated count with elapsed time behind it is
   comparable across topics.
7. **Live, for A§11's bar**: a round is live from its first signed row, first
   dispatched instrument or first emitted brief — whichever lands first —
   until its close-out is written; before any of the three it is not. What the
   bar protects is a template that has already shaped this round's artifacts,
   or is about to be read by an instrument already sent.
   Workflow-tree edits are the **maintainer's** (a fresh session, never this
   topic's author — A§3); template/prompt edits proposed by observations land at any between-rounds
   hold (retro is the default window), under A§1's admission discipline; before landing, check every
   touched file against its doc cap and the commit against `COMMIT_CAP`
   (single-purpose; bootstrap/import exempt, marked). **The landing commit
   writes the row.** A§11 grants the maintainer one field of the promoted
   tables — a family row's `landing`/status field in `iteration-log/` — and
   the grant is discharged in the landing commit itself, not deferred: name
   what landed and where, so `open/OBS-<n>.md` and the INDEX pointer stop
   describing a tree that has moved. **Observation text and anchor counts are
   still retro step 1's alone** (§4.11.1); a commit that is not a retro ingest
   and raises any family's anchor count is a rung-2 red — the harm the single
   writer exists to prevent is anchor inflation (§4.6.4), which is where the
   mechanical bar sits, since "only the status field moved" is not decidable
   by a script. A retro ingest declares itself with a `Retro-ingest:` trailer
   in the commit message; without it the anchor-count arm judges the commit as
   a maintainer edit. **A commit that
   admits a mechanism carries A§1(b) in its message** — the existing
   mechanism considered, and why it does not already absorb this one. It is
   the one admission criterion with no other carrier, and a mechanism whose
   (b) cannot be written is not admitted.

## 5. Spawn discipline (every verifier and reviewer)

1. Instantiate the prompt: copy the template from `prompts/` to
   `rounds/<n>/prompt_<instrument>.md` — a second assignment to the same
   instrument in one round takes `prompt_<instrument>_<k>.md`, **k = 2, 3,
   … — the unsuffixed file is the first**; **never overwrite a prior
   instantiation**, it is the only record of what an instrument was asked —
   filling **every** `{SLOT}` it
   declares — nothing else; never edit mandate text. **Every slot resolves
   by one of six rules.** *Topic-artifact paths* → the A§5.2 artifact of
   that name: `{CARD_PATH}` → `planning/baseline.md`, `{DESIGN_PATH}` →
   `planning/design.md`, `{DECISION_LOG_PATH}` → `planning/decision-log.md`,
   `{PLAN_DIR}` → the current plan version **directory** (`planning/plan_v<k>/`;
   instruments read the files it holds, and report the version's manifest
   hash), `{REGISTER_COPY_PATH}` → this
   round's `register_stripped.md`, `{PRIOR_OPPOSING_DOCS}` → the card's
   authorities inventory (its none-form when empty), `{PLAN_DIR_OR_NONE}` →
   `none` before a plan exists, `{ROW_IDS}` → the **`unverified`** rows the
   plan's `depends-on` fields list (§4.4.5a) — the empty set is the normal
   result and means (a)'s gate is already met, so write `none` and say so;
   never widen the assignment because it came out empty, and sampling
   already-`verified` rows is a separate dispatch with its own row list,
   `{SPOT_PRIOR}` → the work-item ids that prior rounds' `findings_arch*`
   name as spot-checked (its none-form at the arc's first lens-bearing
   round) — the slot the spot-check sample rotates on, so a selection rule
   keyed on fields that do not move between versions does not re-draw the
   same items every round.
   *Workflow-doc paths* → this tree: `{CLAIMS_PATH}` → `claims.md`. *Delta
   instrument* (the `delta` lens only): `{PLAN_DIR_PREV}` → the prior plan
   version directory, `{PREV_CLOSEOUT_HASH}` → the previous round's
   `plan_hash.md` path, `{EDIT_SCRIPTS_DIR}` → the round's archived-script
   directory (or its none-form), `{BOUNDARY_AUDIT}` → the boundary audit's
   record (or its none-form).
   *Declaration content* → the signed closure-proof row (§4.6.2), one slot
   per field it carries: `{CLASS_DESCRIPTION}`, `{RECURRENCE_EVIDENCE}`,
   `{ROOT_HYPOTHESIS}`, `{OPERATOR_MAP}`, `{DIRECTED_CHECKS}`, and
   `{DECLARATION_ROW}` → the row's id.
   *Template paths* resolve to `templates/`: `{CHECK_TEMPLATE_PATH}` → `check-record`,
   `{FINDINGS_TEMPLATE_PATH}` → `findings`, `{FIELD_SET_PATH}` →
   `plan-dir/items/_W-template` (the work-item field list).
   *Delivery* → `{DELIVERY}` names the shape the deliverable arrives in, and
   has exactly two forms: **returning it as your final text**, or **writing
   it to `<ABS path>`, then writing `<ABS path>.done`** — where that path is
   **outside the topic tree**, so §5.3's ban on instrument writes into it
   still holds, and the second file is what makes the first one's
   completeness observable: written after, it cannot mark a half-written
   deliverable. Which form applies is the deployment's choice, not the
   round's. **Default**: where `runtime-scripts/` is present the file form is
   the default and that launcher the means; a deployment without it falls back
   to the first. The choice is made before a round, never inside one — a lens
   delivering differently across rounds would make its failure records
   incomparable. The path is the deployment's to allocate and must be
   **unique per assignment**: a re-spawn after failure writes to a fresh one,
   since a launcher that would overwrite the previous attempt destroys what
   §4.5.3 exists to persist. **And an assignment's path is a directory the
   instrument owns**: its work files live inside it, so concurrent
   instruments sharing a scratchpad cannot collide on names — the
   uniqueness rule binds the deliverable, never the intermediates
   (measured: two instruments each wrote a
   same-named intersect script into one shared scratchpad and one ran the
   other's bytes, voiding the reading; per-assignment directories then
   measured zero name collisions with five instruments concurrent). This file names no vehicle and no dispatch
   mechanism; the contract above is what binds, and a deployment satisfying it
   another way owes this file nothing.
   **Constant slots** carry the §defaults
   value, **never the constant's name**: `{REFINE_PASSES}` ←
   `REVIEWER_REFINE`, `{SPOT_N}` ← `SPOT_N` — an instrument is onboarded
   from its prompt alone (A§3) and cannot resolve a symbol whose home it
   is not given. Instrument → prompt file under `prompts/`: `arch` →
   `reviewer_architecture` · `red` → `reviewer_redteam` · `meta` → `reviewer_metacritic` ·
   `exec` → `reviewer_executor` · `delta` → `reviewer_delta` ·
   `closure` → `reviewer_closure_proof` · `verifier` → `baseline_verifier`.
2. Spawn with the fixed message — nothing else: *"Read `<absolute
   instantiated prompt path>`, execute it fully. Do not summarize back."*
   Where the deliverable goes is the prompt's to say (`{DELIVERY}`), not this
   message's: a message that named one shape would bind every deployment to
   it. No authoring framing, no
   conclusions, no expected verdict (A§3 no-lineage).
3. The deliverable arrives in whichever shape `{DELIVERY}` named — returned
   text, or a file the author copies in **byte-for-byte**, a copy and never a
   re-typing (the transcription step is the one `claims.md`'s carried-text row
   measures a lost conjunct on). Either way the author persists it verbatim to
   its named file. Instruments write nothing into the topic tree themselves.

## 6. Owner briefs (format: A§10; template: `templates/owner-brief`)

One brief file per touchpoint, `planning/briefs/brief_<n>.md`, one section
per item, **≤`BRIEF_MAX_ITEMS` sections**, six Chinese fields per section;
refine before sending (§4.10). Over the cap, the remainder becomes the next
brief, split by settled prerequisites. A **second brief within the same
round** opens only with a named dependency: its header states which answered
section produced each new item (mechanically checkable; a second brief with
no dependency claim is a violation — hard batching would park answerable
questions to batch-mates that have not been asked yet). A grill batch may therefore span two
briefs — that is still **one batch** against `GRILL_MAX`, which counts
batches (§4.3.2), not files; the two constants bound different things and
neither relaxes the other.
One decision-log row drafted per section in `planning/decision-log.md`
(template: `templates/decision-log`), `proposed`. **Emitting a brief
ends the session's forward work on the dependent path**: write a close-out
(round 0 included — the grill sheet's open-branch list is its input, not a
substitute) naming the awaited sections, and stop — its restart line is the
re-entry.
**On resumption, read the brief's 裁决 lines first**; an "ok" signs that
section's recommendation text as written; unanswered sections stay
`proposed` and keep their dependents parked. Answer-only classes:
ruling-contradiction (supersede or reaffirm). **An owner-initiated
ruling** — the owner adjudicating unprompted, in conversation — enters
the same ledger: the author lands a row in the round it arrived, `state`
`signed`, the owner's words verbatim in the signed-text field, and the
close-out's observations record the form deviation. The six fields are
the author's re-derivation to fill, never a shape the owner's words are
forced into — taxing the aside would suppress it (measured four times in
one topic: its first ten rulings arrived conversation-form
ahead of any brief, regularized only by a later one; a standing
authorization that reshaped the topic's decision-cost structure, arrived
with no brief and no section — the rows exist because the author chose to
land them; the protocol named no duty for that choice).

## 7. The restart handoff (a close-out's final content)

One fenced block, nothing else in it:

    read <ABS workflow>/runtime-docs/protocol.md — resume topic at <ABS topic root>, checkout(s) <ABS path[; ABS path…]>, stage <stage>; do not summarize; do not stop for confirmation before the first owner touchpoint

Absolute paths always — a fresh session has no working directory. The
kickoff variant (README) starts a topic instead of resuming one: it names
the topic root, begins at the first stage, and carries the topic
statement. The
forcing clause stops at the first owner touchpoint, never past one.

The **maintainer variant** enters a fresh maintainer session (A§3) for
workflow-tree work — retro steps 2–5 and 7, between-rounds edits, release
rounds:

    read <ABS workflow>/runtime-docs/protocol.md — maintainer session: workflow tree <ABS workflow>, task <retro for topic at ABS topic root | between-rounds edits | release round>[; item(s): <what to land + ABS pointer to the signed authority>]; do not summarize; stop at the first owner touchpoint

A **post-convergence amend** is topic authoring, not maintainer work (A§3),
and it is not a resumption — the arc it opens does not exist until someone
finds the plan wrong. Its entry line is therefore kickoff-shaped, and carries
the cause, which is the input the amend row's cause dating needs and which
only the party that hit the defect holds:

    read <ABS workflow>/runtime-docs/protocol.md — amend topic at <ABS topic root>, checkout(s) <ABS path[; ABS path…]>: <what in the plan is wrong and how it was found>; do not summarize; stop at the first owner touchpoint

The plan's execution-context preamble carries this line verbatim (A§9's
consumer precondition row): the party who needs it is reading `plan.md`, not
this protocol.

**Why the task value is not enough.** `task` is a closed set: `retro for topic
at <ABS>` already carries its pointer, `between-rounds edits` carried none, so
a dispatcher naming a ruling had nowhere to put it and a maintainer onboarded
from this line alone (A§3) could not learn it existed — an asymmetry that lost
a signed ruling for a round (owner-directed seed, A§13). One absolute pointer
per item, to the artifact carrying the signature, never a restatement of it.

A **terminal close-out** — the topic converged or was abandoned — has no
stage to resume, so its fence carries the **maintainer variant** above
rather than the topic line: retro steps 2–5 and 7 are the work that actually
follows, and §0.4's terminal test reads Next, which says so. The fence is
still the file's last content; only which line it holds changes.

A **release round** on the tree takes the complete tree as its review
unit (A§11): no-lineage cold reads; maintainer re-verification of every
finding against the primary files; fixes landed as single-purpose commits
≤ `COMMIT_CAP`. **Two lens classes, both required** — a round running only
the first is not a release round:
- **conformance** — **`self-check/check.sh` first**: it settles caps,
  section references, constants, the A§5.1 region boundary, prompt slots,
  closed vocabularies, registries and verbatim copies, and a red is fixed
  before a cold read is spawned — spending rung 3 on what rung 2 already
  decides is the waste this class exists to avoid. The cold read then takes
  what no script can: the protocol dry-run, two-way fulfillment of
  architecture's commitments, and whether a reference that *resolves* points
  at the right thing. Reads text against text.
- **adversarial** — at least one of: the *executor* probe (walk the
  protocol on a concrete topic; every point you would have to ask);
  *premortem* (it ran and shipped a bad plan — write the postmortem);
  *compliance-gaming* (a lazy-literal author taking every cheap branch:
  which drifts does A§14's last row claim to have removed?); *deletion*
  (what does not earn its cost — A§13 rulings and `rationale.md`-evidenced
  mechanisms excepted). Reads text against incentives and use.

Conformance findings fall as a tree matures; adversarial ones do not,
because they sample a different space (measured: `../design/rationale.md`
§4c). A plateau in one class is not evidence about the other.

It ends in a **release report** to the owner — the review unit and the
ranges read · the lens classes run · every finding with its re-verification
verdict (confirmed or rejected, with the reason) · the fixes landed, by
commit · the clean categories affirmatively, with their ranges (A§8's
release principle: never the absence of complaints) · **every open
validation-debt row with its topics elapsed** (retro steps 2–5 depend on a
maintainer session nobody is required to convene; this is where a tree whose
evidence basis is going stale becomes visible to the owner) · and the call,
release or another round. This
report is the external check A§14 names on the maintainer surface; without
it the surface is unchecked.
