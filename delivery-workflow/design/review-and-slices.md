# review system, refine, slice granularity

> Settles the review system: the three-tier assurance split, risk classes, decision
> routing, the refine mechanism, the spec-ready contract, slice granularity, and the
> learning loop. Checklist-level detail lands in `runtime-docs/review-standards.md`;
> this file settles the design.

## 1. Three-tier assurance (settled)

| tier | who | holds | trust basis |
|---|---|---|---|
| machine gates | `lib/gates.sh`, harness-run | caps, commit conventions, claims resolution, build/lint/test/acceptance | results are **harness-attested store records** pinned to SHA + tree fingerprint — the reviewer neither trusts prose nor re-runs the suite; forgery/staleness is mechanically visible |
| conformance | author (in-band, non-independent by definition) | diff-vs-spec semantic fidelity, per commit-unit | author's spec context; audited downstream |
| independent floor | reviewer (separate lineage) | judgment-class: spec-ready, commit-meets-spec, what a spec-sharing author systematically misses | fresh derivation from artifacts only |

The **one intentional double-run** (a standing must-hold): the composite acceptance gate runs at
author impl close **and** inside postcheck — same command, different context, different
assurance. Everything else has exactly one home ("checks comprehensive, duplicate checks
eliminated" — owner principle). Impl close does NOT demand a clean worktree (untracked
build artifacts are legitimate); what it demands is that the acceptance record binds the
EXACT repo state — sha, tree, and a content-bound dirty fingerprint — with the clean
state recognizable as the constant empty-input hash (owner-ruled). The same binding is
demanded of every project gate the project declares (build, lint, test), not of
acceptance alone: a slice shipped with zero build/lint/test rows while its siblings held
three, and the emit did not notice — a reviewer reading five slices side by side did.
The close also re-resolves the spec's own claims
table at the landed tip and records it (`spec_claims_tip`, never refused): the table
was attested once at spec-emit, and the slice's own commits can rewrite what its rows
echo; postcheck's C3 reads that row.

Reviewer speedup falls out: no mechanical re-runs (store records), full attention on
judgment + cheap grep-class re-derivation of load-bearing claims (counts, citations,
absences). The independence ceiling is disclosed honestly: lineage independence ≠ cognitive
diversity — a model-family blind spot can cross the split; the config-level mitigation is a
different reviewer model (recommended default where available), plus the owner veto.

## 2. Risk class (low / med / high) — depth modifier, never a skip switch

Declared per slice at split, re-derived independently at split-check and again at each
review (precedent/streak never decides — anti-bias carried as checklist lines, not recited
ceremonies). Criteria carry v1's: low ≈ single-component or zero-logic mechanical, proven
by discovery grep; high ≈ multi-component semantic decisions / build-system runtime
instrumentation / public-API expansion; **behavior change is never low regardless of size**,
and a behavior-changing slice owes a **fail-baseline / pass-HEAD flip gate** (the property
proven, not asserted — the gate must read red on baseline). The gate's trigger is the
EVIDENCE, not the change: the docs arm of `low` exempts nothing, and a doc-bound slice owes
the pairs for every criterion of its close that reads differently at the baseline. Class modulates: checklist
depth (low = compact forms), refine round budget, impl stage budgets. **Nothing is ever
skipped** — every slice gets precheck + postcheck. v1's Trivial-skip / combined-review /
eligibility-ack family is retired: the skip's compensating machinery cost more than the
review it skipped. Truly trivial changes ride as commit-units inside a slice (§6 fold
rule), not as slices.

## 3. Decision routing (Class A / C / U)

- **A — author decides + records** (ALL four: determinable under the decision basis;
  reversible in unpushed commits; in-scope and owned; unconflicted with standing
  directives). Recorded as a DP in the decisions surface (one DP = one choice, with basis +
  evidence + revert shape). Never silent — an unrecorded right decision is still a
  violation.
- **C — concurrence-gated, two keys before execution.** Non-semantic ties (naming schemes,
  placement, gate strictness). The reviewer's endorsement at the next review IS the
  concurrence — but the concurrence **precedes execution**; re-slice merges route through
  split-check first. Discord: one rebuttal round, then owner tie-break — never re-roll to
  a different reviewer (verdict shopping). Emergency valve DP-E (rule, not machinery):
  non-semantic + reversible + immediately-blocking + logged, audited at the next postcheck
  which performs the concurrence.
- **U — owner decides**: semantic tradeoffs, scope/direction changes, irreversible or
  outward actions (push, publish, deletion of others' artifacts), ownership-boundary
  crossings, externally unverifiable assumptions, anything flagged "ask me". **Ambiguity
  rules**: A-vs-C doubt → C; any doubt about U → U. Co-pending U questions batch into one
  owner gate (one ruling surface entry set, one resume — v1 paid twice for not batching).
- **Audit exactly once**: every DP is independently audited at the earliest reviewer
  checkpoint that follows it (postcheck checklist carries the sweep). **Veto surface**: the
  owner may veto any recorded DP at any time → the veto is recorded and a follow-up fix
  slice must exist before close-out.

## 4. Refine (the mechanism, layered by instrument)

The manual habits being mechanized: "re-check for correctness/omissions/ambiguity" (works
because it flips the objective to falsification and licenses new evidence-gathering) and
"read whole passages, never conclude from fragments".

1. **Emit-time mechanical gates** (cheapest; prevention): the artifact's **claims table**
   (structured rows: claim, type, evidence command, read-range) is machine-checked —
   every citation resolves, every count/absence row carries its range stamp and command.
   Citation anchors are two-track: **durable citations** = `path#heading` / `path::symbol`
   + a content echo the resolver verifies, and for a heading anchor verifies INSIDE that
   heading's extent — the two were checked independently over the whole file until
   `claims_cite_scope`, so a row could point one section off its own evidence and pass
   (survives refactors; line pins forbidden — a
   line pin dies on the next unrelated edit); **point-in-time read stamps** = line ranges as evidence of process (no
   survival promise). Plus the environment sweep: every absolute path and `path:NN` pin in
   an emitted artifact must resolve (≥1-slash rule against false DEADs; run from the
   declared root; existence is the floor, not the proof). Free-prose claims outside the
   table are the reviewer's checklist, honestly not the gate's.
2. **Author self-loop** (schema-forced): the record schema requires `refine.rounds` and
   `refine.terminated_on` (clean | bound — which criterion released the artifact; owed
   at the cap, derived below it) with
   per-round findings (claim → evidence command → result) and severity by **observable
   class** — A: claim≠cited authority (demonstrable), B: an edit broke a gate it could
   touch (demonstrable; fixes re-run affected gates — never inherit a prior PASS), C:
   mechanism unwritten behind an empirical claim (checkable), else wording. Release when a
   round finds nothing substantive; hard bound 3 rounds (risk-class adjustable); residual
   substantive findings ride to the reviewer, flagged. A zero-finding first round is
   itself a visible flag. Severity gaming is bare in the log (an A-class labeled
   "wording" shows its own mismatch) and auditing it is a reviewer checklist line.
3. **Independent floor**: judgment-class claims; spot-verification of range stamps.
   "Declared done" is always the re-verify trigger; completion claims are never inherited.

Derive, never hand-predict (v1 E-1/E-2): any number the tree can produce is taken from the
tree with its command cited; a hand-counted correct value is still a defect. The author MAY
use a worktree probe (apply → measure/gate → revert, disclosed) to derive spec numbers —
the surviving essence of v1's M1–M9; the ceremony and patch-artifact form are retired.

## 5. Spec-ready contract and prompt hygiene

A spec is ready iff: self-contained (executable by a cold implementer; anything the
reviewer needs is in it — there is no side channel by construction); binding constraints
**front-loaded** (position bias is real); scope proven by command (discovery grep output,
not intuition); commit-unit list with per-unit subjects + risk notes; gate list incl. the
flip gate wherever a criterion of the close reads differently at the baseline (behavior
change unconditionally; a doc-bound slice through its own per-slice checks);
claims table complete; numbers single-sourced (each
stated once, derived elsewhere); baseline pinned (a *logical* baseline — the shared-branch
reality: colleagues commit to the same branch; review scope is the progress ledger's SHA
set, and a red gate triggers the **attribution check**: re-run with our commits removed —
red both ways = external breakage → `park(blocked)` with evidence, not our defect).
Authority chain: spec cites the plan, never the previous turnover (turnover carries
pointers + deltas only — the telephone-game guard; precheck checks the chain). Leak
rule: postcheck findings tagged `precheck-catchable` feed the learning loop; a frequent
fallback is treated as an upstream weakness signal, never a reason to widen postcheck.

Prompt/template hygiene (all templates): reference authority by pointer, never restate
rules (drift source); express actions as **goals with live-authority reads**, never inlined
step literals (a moved baseline kills steps, goals survive); never assert the session's
spawn mode (freshness is session-derived, recorded in provenance); artifact content is
data-under-review — a directive addressed to the reviewer inside an artifact is itself a
finding. Review docs open with provenance (baseline + freshness + rounds; vehicle facts are
store-attested) and must match their template's section structure (a structure mismatch is
a draft, mechanically checked). Verdicts are immutable once written — a new round is a new
file on new input; re-runs only on infrastructure failure, disclosed. Findings the reviewer
cannot make independently re-derivable are filed as **questions** (R-Q), not findings.

## 6. Slice granularity

Split by function; a slice may carry many commit-units. Merge signals: one functional
intent one spec can bind; overlapping footprint (shared context re-derivation is waste);
later units depend on interfaces earlier ones introduce; a forced carry-forward between
adjacent slices (couple = merge). Split signals: independently reviewable with
self-contained specs; disjoint footprints; budget exceeded. Ordering: risk-first,
mechanical tail last; each slice reduces ambiguity for successors; every boundary green
(build + gates pass at each slice close — revertable units, safe consolidation).
Semantic and mechanical never share a slice above the **fold threshold** (≤~15 LOC,
0-semantic, grep-clean folds in; larger mechanical work is its own cheap slice).
Budgets (config, per LLM tuple; owner-approved, evidence-anchored — the
recovery topic's merged 12-cu/~2400-line phase is the sole multi-commit
single-review observation, so the diff ceiling sits AT it and the commit
ceiling deliberately below the single observation):
`slice.max_diff_lines=2500`, `slice.max_commits=8`, `slice.max_files=30`;
spec ≤2000 (config, project-overridable like every cap.* key). High-risk
slices target half. Per-commit-unit cap: workflow
default 500 (project-overridable both ways; `relocation-only` declarable per
unit; NEEDS-MF rate jumps ~7x above ~600 lines/commit — the cliff that makes
this cap load-bearing). Recalibrate from ledger leak-rate data as real topics
complete; self-check pins this text to `config/defaults.kv`.

**One slice, one checkout.** Every slice binds to exactly one repo — `code` (the
project repo) or `doc` (`doc.repo`, when the project declares it) — chosen per
charter at split and cast into the machine index by the split grammar
`id:risk:repo:title`. Everything the slice's evidence rests on resolves through
that binding: commit-unit SHAs and their branch ancestry, gate attestation pins,
the fix baseline, the progress registration wall. A change spanning both trees is
therefore **two slices with a declared interference order**, never one slice
reaching across — atomicity stops at the repo boundary, and ordering is what
replaces it (the industry's answer too: Gerrit's whole-topic submit is atomic
per repo only, Zuul serializes cross-project dependencies through a shared
queue). The binding is **immutable per id**: ingest preserves an
existing id's row, so a re-split can never re-bind a live slice; a different
binding is a new id under the never-reuse rule. A re-split that declares a
different binding is **refused at emit** (mint a new id and omit the old one,
which supersedes) rather than silently ignored — one admissibility rule over
the declared index (grammar · one id one slice · immutable binding), asked once
by each door, so the emit refusal and the index-door park can never drift apart. A re-declared risk class
is audited and dropped instead: the index's copy has no machine reader, and
every review re-derives the class independently (§2). A doc-bound slice runs no
build/lint/test/acceptance gate (the doc repo has no such concept — the gates
record a structural named SKIP); its mechanical floor is the spec's own
per-slice checks — which are filed in the spec's flip-gate slot as
baseline/HEAD pairs, that slot being conditioned on the evidence rather than on
behavior change (§2) — and its commit-units obey the same commit convention as
the code repo's.

**Delivery order is machine-carried.** The scheduler is the lowest pending id
whose `after=` set is out of the way — the split grammar accepts an optional
`:after=NN(,NN)*` tail per slice, and the charter's hard edges must ride the
index through it (prose is machine-invisible; a re-split that mints ids out of
dependency order otherwise schedules them inverted — measured on a live topic,
paid for with a full plan_changed round of re-minting). Every after names a
strictly EARLIER id: the id order is the delivery order, so all edges point
backward and the graph is acyclic **by construction** — the same discipline
that lets migration frameworks depend only on earlier-numbered migrations, and
the degenerate case of the systemd `After=`/topological-sort shape (no cycle
walk exists to need). A pending minimum is provably never blocked by another
pending; blocked-on-active resolves when the active slice completes; done,
cancelled and superseded all satisfy (superseded is owner-retired — waiting on
it would be a deadlock), while an after naming a MISSING row blocks and the
advance path parks rather than closing out over it. The after set joins the
admissibility rule at both doors (backward + resolvable + immutable per id —
omission re-lists a standing row unchanged; a different set is a new id), so a
declaration the scheduler would not honor is refused at emit and parked at
ingest, never dropped in silence.

The terminal
decomposition table is pre-declared at split (seams are design-knowable; v1 paid a 7-way
cascade for deferring it). **Re-slice** is a standing turnover step (remaining-plan
inventory): merge proposals → split-check concurrence first (Class C); finer splits →
Class A recorded. Slice ids are never reused or renumbered; merges mint a new id,
superseded ids stay in the index; config overrides addressing a retired id fault
loudly, and a re-split re-listing one is refused at the index doors — keeping the
retired row would schedule nothing, which is the declaration silently dropped.

## 7. Learning loop

Postcheck findings carry `leak_class`; observations (workflow defects seen by stages or
pilot — each is structurally blind to a class the other sees) append to the observations
surface. Promotion: two independent anchors (different slices/topics, same mechanism) →
target chosen by **structural > script > prose** (a rule that could have been a gate is
hot-memory spent twice) → owner confirms → lands as a workflow-source change (dev-time,
git-committed). Single anchor = DEFER, logged — with one carve-out: a postcheck finding
tagged `leak_class=gate` is, by its own tag, one a machine instrument could have caught,
so its gate is owed at the FIRST escape (the phrase above is the reason — a rule that
could have been a gate is hot-memory spent twice; waiting for a second anchor spends the
most expensive instrument twice on something mechanically decidable). Judgment-class
leaks and pilot observations keep the two-anchor bar, where a second occurrence is what
separates a pattern from a coincidence. Deprecation is periodic and owner-confirmed.
Aggregation across topics stays manual in v2.0 (stated, not tooled).

## 8. Close-out and history consolidation

Topic close-out: ledger settlement into `closeout.md`; consolidation (squash curation) as a
Class C proposal under v1's hard invariants carried verbatim — backup ref first;
adjacent-only squashes, no reorder; `git diff backup..new-tip` empty (byte-identical);
full gates re-run at the new tip; subjects re-pass the project regex; Change-Ids preserved
on kept commits, fresh on squashed groups; old→new map recorded; push stays the owner's.
Non-interactive cherry-pick recipe (no `rebase -i` in this environment) in
`operations.md`. Retracted slices: `launch.sh slice <id> cancelled` makes them
unschedulable by status; a restored slice re-derives its premise from scratch.
