# planning-workflow — rationale
<!-- Cap: DOC_CAP_RATIONALE -->

> The evidence layer: the campaign autopsies every "(measured)" pointer in
> `architecture.md` and `../runtime-docs/claims.md` resolves to; the external anchors; the honest
> ceilings in full. **Self-contained**: campaigns are re-authored here
> anonymously (A, B, C, D); no path outside this tree is referenced or needed.

## 1. Campaign A — the framing leak (why independent review is structural)

One author wrote the plan, **all** the per-lens review prompts, and the findings
synthesis. Two lens reviewers were fed the plan's goal as a premise; both
validated inside that frame (GO 8.5; conditional GO 7). The third — deliberately
conversation-blind, pointed at the prior authority documents, tasked to attack
foundations — scored 3/10: the plan's central move **reversed a previously
owner-authorized decision, and no supersede had ever been recorded**. Escalated;
the owner adjudicated: part of the "reversal" was a legitimate gap-fill, part a
true supersession — authorized and signed, with a banner on the superseded doc.
The outlier was right about *where* and partly wrong about *what to do*.

**What this grounds**: the no-lineage reviewer vehicle and the fixed meta-critic
mandate (A§3); owner-only supersedes on an ADR-shaped log (A§4); escalate for
adjudication, never auto-accept the outlier's remedy; the honest ceiling that
the author writes the prompts, so "framing-blind" is approximated by fixing the
mandate text and by sourcing the authority list from the card's inventory
under a never-omit-a-known-opposing rule. That second half is the weaker
one — the audited party still fills the inventory, and a thin search omits
nothing "known" — which is why the inventory carries its own ceiling row
(A§14) rather than being claimed as fixed.

## 2. Campaign B — the onion and the fix-made bug (why hunts end and fixes are claims)

An 11+-round review loop. Rounds 8→11 each found **exactly one** narrower
instance of a single completeness class (an exact target passing through a
quantized pipeline). Root cause was method: a counterexample **hunt** stops at
the first break it finds, so it structurally yields ≤1 break per round — the
class sheds one corner per round indefinitely. Round 12 replaced the hunt with
a **pipeline closure proof** (enumerate every operator; prove an arbitrary
member survives each); the loop terminated only when the root mismatch was
removed **at source**.

Same campaign, the other direction: a round's *fix* keyed a guard on a
composite floor — a `max()` of **four** contributors — traced as if it were
one. The guard fired on every contributor, nullifying a stability buffer on
natural drift: **the review loop itself created a regression**, because
validating a finding does not validate the fix that answers it. And a rescue
fixture pinned a parameter's *passing* half while its other half broke —
non-vacuity masked a whole region for a round.

**What this grounds**: the closure-proof assignment and its declaration gate
(A§3); the fix claim and acceptance claim shapes (`claims.md`); the convergence
stop rule — root fix or signed bounded limit, never exhaustion, never silent
narrowing (A§8); **carry-forward and relocation-is-not-disposition** (the same
campaign's ledger repeatedly recorded a merely-relocated foundation finding as
closed while it re-fired for ~7 rounds); the family shape ("enumerate the whole family on first
sighting" — a sibling campaign spent four rounds catching four same-shape
dependencies one at a time, and six rounds re-committing a premise checked only
at its landing site).

## 3. Campaign C — baseline cognition (why extraction needs its own instruments)

A topic whose review loop was already disciplined still burned its most
expensive resource — owner corrections — on **author-side baseline errors**:

- A doc-labelled "invariant" (`X = Y`) was absorbed as ground truth while code
  read the same session showed legitimate writers of `X < Y`; doc-internal
  consistency masked it — and it was caught only when the owner read the
  author's **stated model** in an explanation brief (the live-run precedent of
  the shared-understanding section). → the evidence hierarchy (code > signed rows > docs)
  and the invariant shape (writers of both sides).
- "Today the system silently accepts this case" was **inferred** from nearby
  code; the actual path ended in a hard failure at an in-line gate. The
  artifact that answered it was one trace away. → the today-behavior shape.
- Three counted/absence claims in one version were falsified by every cold
  reviewer at once (a reader count whose grep covered 4 files instead of the
  tree; a "zero assertions" claim over a message carrying four; a citation
  forwarded from a prior round, unopened). → printed hits, stated ranges,
  opened citations — as **schema columns**, because a prose rule had already
  failed. A "thorough" self-audit found zero of these; independent review
  found eight defects (first measured instance of the presence-vs-truth
  split).
- The owner's corrections arrived through detailed explanations with worked
  examples — the examples are what exposed the wrong model. They arrived
  *late*, after a full authored version. → owner briefs with the worked
  example load-bearing (A§10), and the grill moved **before** drafting.
- **Restart, live-run**: the campaign's one fresh-restart round measurably
  outperformed its compaction-carrying predecessors — a premise that had
  calcified into "already decided" across warm rounds stood out as a
  contradiction on the first cold re-anchor; this is the live-run evidence the
  stateless-author rule enters on (the blind-spot literature corroborates).
- A version overwrite nearly lost the prior plan text (restored only from a
  still-live context). → new file per version. An observer-borne, optional
  workflow-defect log went unwritten through ten rounds. → the author-borne,
  required observations section.

## 4. Campaign D — this workflow's own build (why the review unit matters)

The build of this very template ran the discipline on itself. Author
self-refine found 2 wording items; two no-lineage cold reads found ~50
substantive defects (with Campaign C's 0-vs-8 and a predecessor round's clean self-audit
overturned by review, the three measured instances of presence-vs-truth).
Three successive cold-review rounds on the two design files yielded ~50 → ~60
→ ~53 substantive findings — a **constant rate, not convergence** — because
each round's fixes added mechanism text that became the next round's finding
surface, and because the reviewed subset's delegated layers (protocol, claims,
templates) did not exist, so every delegated specification read as a hole. The
severity-trend rule fired; the fix was structural: the **specification
ledger** (A§5.3 — delegation made explicit and checkable) and **the complete
tree as the review unit**.

### 4b. Predecessor comparison — the monotonicity record

Why the rebuild cannot deliver worse plans than the predecessor, recorded so
the claim is auditable rather than asserted:

- **Carried is a superset of everything that ever caught.** Every predecessor
  mechanism with a live catch record survives: no-lineage review + the fixed
  meta-critic mandate (Campaign A), closure-proof + fix claims + adversarial
  corners + the stop rule (Campaign B), carry-forward/relocation (B),
  restart (C), owner-gated terminal states (A). Nothing that ever produced a
  disposition-changing catch was removed.
- **Each deletion has a safety argument.** Scores → layer-keyed routing is the
  successor of lever ④, which already owner-gated any foundation-layer finding
  "unconditionally, independent of spread" — so it is not a gain in
  sensitivity over the spread trigger, which was lever ②'s and caught
  foundation findings *averaged away* rather than disclosed. That channel had
  no input but the scores and closes by construction when they go: the
  deletion holds, and what it costs is a signal independent of the author's
  routing judgment. The manager role → the predecessor defined it as "a
  **non-author** party … Never the author" and, in the same tree, fused it
  into "**Author/Manager** (… the reviewed party)"; the rule was contradicted
  by its own text and unobserved in practice, so what was deleted was a rule
  nobody could follow, not a fiction nobody wrote. All-lenses-every-
  round → an exchange, not a strict gain: the deciding rounds run *more*
  instruments (four lenses incl. the executor at round 1 and the convergence
  candidate) and an ordinary round runs *fewer*, the one dropped being the
  lens the predecessor wrote as never tier-gated. Instrument cost bought;
  latency to an ordinary round's foundations defect sold.
- **Every addition sits in a predecessor blank.** The predecessor defined no
  plan content at all — impl-readiness was whatever the author wrote. The
  card/grill/executor/gate machinery addresses exactly the failure classes
  Campaign C paid for.
- **The empirical A/B.** Baseline (predecessor, recorded): a 10+-round topic
  that never converged under review, three falsified counted claims in a
  single plan version, repeated late owner corrections. Metric for the
  comparison: per-round round-metrics plus the topic's escape count /
  planning-DRE (§5). Two constraints: the first live topic is calibration,
  not verdict (the `ANCHOR_MIN` rule applied to ourselves), and comparison
  uses per-round rates, not totals, to control for topic difficulty.

### 4c. The release loop — lens class, not defect density

Eight full-tree release rounds on this tree. Rounds 1–7 ran one lens class —
**conformance**: references, constants, closed vocabularies, a protocol
dry-run, two-way registry fulfillment — and substantive counts ran
15 → 6 → 9 → 6 → 4 → 4 → 6. The rule fires on three pairs of that series —
(6,9), (4,4) and (4,6) — and the last two were consecutive, which is the
case the arm rule now bounds; each was discharged by the maintainer's own
diagnosis, and the flattening read as convergence and produced a release
recommendation.

Round 8 ran four **adversarial** lenses instead — the executor probe turned
on the workflow itself, a premortem, a compliance-gaming read, and a
deletion read — against the *same* files, and raised 41 findings (37
substantive), among them reviewer prompts citing constants no reviewer could
resolve, an unapproved-scope hole in the convergence gate, and a coverage-row
gap that made the scope-creep gate editable without review.

**What this grounds**: `protocol.md` §7's two required lens classes, and
A§14's release-round ceiling row. Conformance yield falls as a tree matures
because text-against-text defects are consumed; adversarial yield does not,
because it samples incentives and use, a space the first class cannot reach.
A quiet round is evidence about the classes run, never about the tree — and
the same relativity A§14 already concedes for a topic's lens set applies one
level up, to the instrument reviewing the workflow.

## 5. External anchors (verified against primary sources during the design round)

- **Self-correction**: LLMs do not reliably self-correct reasoning without
  external feedback, and exhibit a *self-correction blind spot* — errors in
  their own output that they fix when the same text arrives as external input
  (arXiv 2310.01798 and successors). Grounds: refine's mandatory
  re-evidence-gathering; the cold restart and no-lineage instruments as
  blind-spot crossings (A§7/§8).
- **Premortem / prospective hindsight**: framing a plan as *already failed*
  measurably improves failure identification (~30%; Mitchell/Russo/Pennington
  1989; Klein, HBR 2007). Grounds: the red-team lens mandate.
- **Interrogation ergonomics**: a written plan interrogated branch-by-branch,
  each question with a recommended answer, branches ending
  decided/deferred/knowledge-gap (here: `reality-gap`) (the "grill" pattern in practitioner skills);
  one-topic-at-a-time dialogue, section-by-section approval, and a hard
  no-implementation-before-approval gate (practitioner brainstorming skills);
  the zero-context-reader standard and the no-placeholder rule (practitioner
  plan-writing skills); constitution-vs-artifact separation and checklists as
  "unit tests for specs" (spec-driven development toolkits). Grounds: grill,
  design approval flow, executor onboarding, the plan template.
- **Considered and not adopted — capture-recapture defect estimation**
  (Eick 1992; Wohlin's decade review): estimates remaining defects from the
  overlap of independent reviewers' finding sets, but its models assume
  homogeneous, independent detectors — reviewer *specialization* is a named
  assumption violation, and our lens set is deliberately specialized (PBR
  diversity minimizes overlap to maximize class coverage). Adopting it would
  trade catch breadth for estimability; rejected.
- **Software-inspection science**: Perspective-Based Reading (Basili et al.,
  validated at NASA/Goddard) — reviewers reading from assigned perspectives
  outperform single-viewpoint reading with less overlap; grounds the lens
  architecture. Fagan inspection's *reader* role (describe the artifact to
  the team) is the executor lens's forty-year-old ancestor; its *moderator*
  is played structurally here by schemas + protocol. Capers Jones's defect
  removal efficiency: escaped defects are the true quality metric and
  pre-test inspection is what pushes DRE past ~95% — grounds the escape
  count and the workflow's existence.
- **ADR practice**: decision records immutable once accepted, superseded by
  new records that name the old and why, rejected alternatives preserved.
  The decision log independently converged on this shape; conformance was
  checked against the practice, not copied from it.

## 6. Honest ceilings — full statements

The one-line index is A§14; rows needing more than one line:

- **Refine verifies presence, not truth.** Three measured instances (C, D, and
  a predecessor round): self-review reliably catches omission, contradiction,
  and schema gaps; it found near-zero of the claim-vs-source defects that
  independent re-derivation then found in double digits. Refine's value is
  making the *cheap* class never reach the expensive instruments; treating a
  clean refine as clearance is the exact failure the ladder forbids.
- **Independence here is lineage, not cognition.** Every instrument shares a
  model family; a family-level blind spot survives a perfect framing split.
  The owner is the only out-of-family check **on judgment** — which is why
  every terminal state routes there, and why an absent owner parks rather
  than terminates. The conformance harness is out of family in the same
  sense and cannot substitute: a script has no model to share a blind spot
  with, and none of what it settles depends on cognition.
- **The floor cost is real and priced in.** Every topic pays pin + card +
  check + design/grill + per-round lenses regardless of size — by explicit
  owner ruling (no exemptions), because the exemption judgment is itself the
  judgment that fails silently (measured: the skipped-observation channel of
  Campaign C). The sanctioned reductions are depth scaling within fixed
  fields, and the editorial amend.
- **The workflow cannot outrun a rubber stamp.** Signatures, re-tags, budget
  resets, and bounded limits all assume the owner actually adjudicates; the
  brief format (worked example + strongest counter-argument) is designed to
  make adjudication cheap, not optional.

## 7. Measured-evidence registry (every "(measured)" pointer resolves here)

| pointer (file) | campaign | fact |
|---|---|---|
| self-correction blind spot (A§7, A§8) | literature + C/D | errors unfixable in own output, fixable as external input |
| "read enough" ≡ "enough to write this sentence" (claims header) | C | the four misses (three counted/absence + the invariant) shared this mechanism |
| verified tables under false summaries (claims rule 1) | C-era, twice | schema covered the table; the summary escaped it |
| carried-text conjunct loss (claims: carried text) | C-era | a five-ingredient decision transcribed minus one conjunct |
| doc-labelled invariant cost an owner round (A§2, claims) | C | the `=` vs `<` chain |
| version near-loss (A§5.2) | C | overwrite recovered from live context |
| observer-borne log unwritten (A§11) | C | ten rounds, zero entries |
| zero-defect self-audit vs double-digit haul (A§14) | C, D, predecessor round | 0-vs-8; 2-vs-~50; a predecessor clean self-audit overturned by review |
| "a proxy is never the artifact" (claims rule 2) | C-era | every measured citation/count error rode a proxy |
| composite guard nullified a buffer (claims: fix claim) | B | `max()` of four, traced as one |
| fixture's passing half masked a region (claims: acceptance) | B | lower/upper half |
| one-instance-per-round; 4 deps in 4 rounds; 6 recommits (claims: family, decision) | B-era | the hunt and landing-site failures |
| prose-only ordering edge → scheduling inversion (grounds A§4's typed-edge field) | predecessor-era, historical | edges made machine-carried after a measured inversion |
| refine convergence 2–3 passes (grounds `REFINE_MAX`'s value) | predecessor-era, historical; owner-observed | the manual "复核一下" habit |
| commit-size cap (A§11 `COMMIT_CAP`) | predecessor-era, historical | defect-flag rate jumped ~7x above ~600 changed lines per commit |
| constant finding rate across subset reviews (grounds A§5.3; Campaign D §4) | D | ~50/~60/~53, halt, ledger |
| each lens added found a class the prior set missed (A§14 reviews row) | D | lens-set relativity: successive lens additions during the build each opened a finding class the prior set had not surfaced |
| conformance plateaus, adversarial does not (grounds `protocol.md` §7's two lens classes; §4c) | D | seven conformance rounds 15→6→9→6→4→4→6, read as convergence; four adversarial lenses on the same files then raised 41 (37 substantive) |
