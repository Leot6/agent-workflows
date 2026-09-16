# review standards — contracts, checklists, severity, decisions

> reference (on-demand). the substance of review: what a spec owes, what each check
> verifies, how severity and convergence work, how decisions route. the flow is
> `protocol.md`; role identities are the cards. topic artifact caps: spec ≤ 2000,
> review ≤ 1500 lines (config).

## 1. severity vocabulary

**substantive** findings, by observable class (the same classes the author's refine
loop uses — one vocabulary end to end):

- **A — claim vs authority**: a claim differs from the authority it cites
  (count, citation, enumeration, range). demonstrable by re-derivation.
- **B — edit broke a gate**: an edit broke a gate it could touch; the fix re-runs
  the affected gates — a prior PASS is never inherited. demonstrable by re-run.
- **C — mechanism unwritten**: an empirical claim ("this compiles", "byte-identical")
  whose enabling mechanism — or whose stated re-derivation — is not actually
  available to a cold reader. checkable by probing the mechanism.
  **a broken evidence command is C even when the claim is TRUE**: what failed is
  the reader's ability to re-derive it, and that is the entire job of the row.
  the same defect was graded `wording` at one slice and `C` at the next, which
  is what this line exists to settle — truth of the claim decides A, usability
  of the re-derivation decides C, and they are independent.

**wording**: everything else (clarity, consistency, style). never blocks alone.
grading a broken re-derivation as wording is the near miss this vocabulary
invites: the sentence reads fine, so the eye files it under style — but nothing
about it is style.

**R-Q — question**: anything the reviewer cannot make independently re-derivable is
filed as a question to the author/owner, not as a finding.

severity counts (substantive vs wording) travel in the completion record — they are
the mechanical inputs to the convergence predicate (§10). labeling an A-class as
wording is severity gaming; the refine log makes it visible and §7/§9 audit it.

**from round 2 of a review stage, every substantive finding is also `new` or
`repeat`**, both counts travelling in the record beside the total
(`findings.substantive.new` + `.repeat` = `findings.substantive`, enforced at emit).
a **repeat** continues a previous round's finding — rebutted and standing, absorbed
only in part, or re-introduced by the remediation; **new** is everything else,
including a defect the remediation created. the review's `## 3. absorption` section
(template-gated at emit) names the previous-round finding each repeat continues. the
classification is the reviewer's alone: the determination it already makes, written
where §10's predicate can read it.

## 2. claims tables and citation anchors

every emitted artifact carries a **claims table** for its load-bearing claims:

| column | content |
|---|---|
| type | `cite` · `count` · `absence` · `behavior` · `process` · `note` — the closed set the emit gate parses; a "this code/test already does X" assertion is a `behavior` row, never a `note` (measured: two HIGH-confidence prechecks verified every counted claim and missed the one behavior claim, because nothing obliged anyone to open the file); only judgment no command can settle stays `note` |
| claim | one claim per row, stated exactly |
| anchor | cite rows: durable anchor — `path#heading` or `path::symbol`; behavior rows: `path::symbol` only (the code that does X, never a heading about it) |
| echo | cite/behavior rows: short content echo the resolver verifies verbatim — and for a `path#heading` anchor, verified INSIDE that heading's extent (to the next heading at or above its level, headings taken fence-aware, a numbered descendant staying inside): an echo resolving elsewhere in the file points its reader one section off its own evidence. `lib/md_span.sh` decides the extent; `claims_cite_scope` records the reading at emit and never refuses — the reviewer's, at §7 P4 |
| range | count/absence rows: the read-range stamp — where you read *to* |
| command | count/absence rows: the command that re-derives the claim, with its expected reading; behavior rows: the rerun command that proves the behavior — which puts the row under precheck's run-every-command duty |

- **durable anchors** — either shape above, plus a content echo verified INSIDE
  the anchor's extent. these survive refactors; line pins do not, and are forbidden.
- **`baseline` in a spec row's range** — the row describes the tree BEFORE this
  slice's change (a fact the slice is meant to invalidate); the tip re-resolution
  at the author's close (`spec_claims_tip`) skips and counts it, everything else
  in the table must still hold at the landed tip.
- **range stamps** — `path:L<a>-L<b> @ <commit>`: point-in-time evidence of process
  ("I read this"), no survival promise.
- **absence rows** state the searched range/scope in the evidence command — a
  zero-hit grep proves nothing without it.
- **process rows — a sentence stating what the PROCESS did**: "the sweep ran",
  "§8 re-read in full, every line this session", "the gates re-ran", "every hit
  classified". It is the one claim class no reader checks by READING it, so it
  is filed as a row and not left in prose: the extent it covered, the command by
  LABEL, and that command's OUTPUT beside it as an `E<n>-out:` line. §7 P4 then
  re-runs it like any other evidence command, and the reviewer's check is
  mechanical — same command, same extent, same hits, dispositions accounting for
  all of them with no remainder.
  **Scope by CLAIM SHAPE, never by document** (a prohibition scoped to "the
  refine log" was escaped twice in the conformance record), and **printing beats
  promising**: a format requirement cannot be satisfied without doing the work,
  an instruction can be nodded at.
  A **version-pinned** count is not the target — "v3's claims table holds 30
  rows" names what it describes; "this log, seven rounds" falsifies itself on the
  next entry.
- **occurrence vs line counts**: an occurrence claim is generated with
  `grep -o … | wc -l`; a `grep -c` result is labeled "lines". the two agree just
  often enough to hide the mismatch.
- **a command carrying a `|` is NAMED in the table, never held in it.** a pipe
  inside a cell splits the row — in every renderer, and in the emit gate's own
  parse — so the gate reads a command truncated at the pipe and a reviewer
  copying the cell runs a shell fragment. escaping only fixes the RENDER: `\|`
  is a literal pipe to ERE and an escaped pipe to a shell, and the occurrence
  rule one line above prescribes a pipe, so the format forbade what the
  contract required. put such a command in a fenced evidence block under the
  claims table, one per line as `E<n>: <command>`, and write `E<n>` in the
  cell; the emit gate refuses an unresolvable label. pipe-free commands stay
  inline — the indirection exists for what the format cannot carry, not as a
  ceremony for every row. three anchors, each an evidence command nobody could
  re-run as written:

  ```
  E1: grep -oE 'ResolvePath\(' src/planner/*.cc | wc -l
  E2: rg -n 'kMaxSlots' include/ | wc -l
  ```
- **single-source numbers**: each number lives in exactly one place (the claims
  table or the section that derives it); everywhere else references it. a gate may
  restate a literal where executability requires; nothing else repeats a count.

**emit-time gates** (mechanical, before the record can emit) — the machine
contract at a glance:

- **claims** — every citation resolves; no cell carries a `|` (the row would
  split and the command truncate); a named command (`E<n>`) resolves to its
  evidence-block line; every count/absence row carries
  command + range; every behavior row carries a resolving `path::symbol`
  anchor + verified echo + its rerun command. accepted claims headings:
  `## claims` · `## 6. claims table` (spec) · `## 4. claims` (review) — all
  shipped shapes parsed.
- **stamp freshness** (conformance at impl/fix emit) — a conformance
  line stamp IDENTICAL to the spec's, on a file whose numbering the
  spec-baseline→HEAD diff displaced at that line, is a forwarded "@ HEAD
  re-read" and is refused (a shifted-but-restamped pin passes; baseline =
  the spec's own claims-attestation sha; no baseline → named SKIP).
- **env sweep** — every absolute path with a second segment (`/a/b…`; a lone
  `/word` mid-sentence is prose — measured 8 of 12 post-gate hits) and every
  `path:NN` pin resolves. swept at emit on spec, the reviews, the halt doc,
  and the three artifacts handed forward — charters, turnover, close-out;
  not on conformance or the validation note. roots: absolute · project repo ·
  the other checkout · workspace · workflow root (citing `runtime-docs/...`
  is legal).
- **structure** — spec and review artifacts match their templates' order.
- **line pins** (charters at split emit; turnover at slice close — the two
  artifacts handed FORWARD to a later author) — no `path:NN` citation outside a
  fence. a pin keeps resolving after the file grows above it, to whatever sits
  there now (measured); the env sweep's "does it
  resolve" cannot see that. cite `path::symbol`, `path#heading`, or the comment's own
  first line — the same anchors the tables use; a range stamp is not a pin.
- **charter sections** (charters, at split emit) — one `## slice NN` heading
  per declared index id. the section is the slice's unit of hand-over: its
  spec author reads it, and the plan excerpt the ferry derives for that
  author comes from the work items the section names — an id without one is
  handed the whole charter, or nothing.

free-prose claims outside the table are the reviewer's checklist, honestly not
the gate's.

## 3. refine protocol (author self-loop; the record's `refine` fields)

1. **emit-time mechanical gates** (§2) prevent the resolvable subset outright.
2. **self-loop**: re-derive every load-bearing prose item against its cited
   authority (grep the symbol/range, never memory); after any correction, re-run
   the gates the edit could touch; probe the mechanism behind every core empirical
   claim. log per round: finding → evidence command → result → severity class.
   release when a round finds nothing substantive; hard bound `refine.max_rounds`
   (default 3, risk-class adjustable); residual substantive findings ride to the
   reviewer, flagged. a zero-finding first round is itself a flag. **the record
   says which criterion released the artifact** — `refine.terminated_on=clean`
   (a round found nothing) or `bound` (the cap did, findings still open): derived
   below the cap, stated by the author at it, refused if absent there. `bound` is
   legal — a loop hitting its cap is the METHOD not converging, never a case for
   a bigger cap — and the reviewer reads such an artifact as released unconverged
   whatever its confidence says.
   - **named sweep class — PROSE numbers and line pins.** every count, size and
     `file:line` in the spec's prose, OUTSIDE the claims table, is re-derived
     from the tree each round and discharged as a §2 `process` row — the command
     and what it returned, not a note that it ran — at the same standing as
     the §4.3 readers sweep and the §4.5 flip gate: a class the round runs, not
     an item the author picks. claims rows carry rerun commands and behavior
     rows echoes; prose carries neither, so a prose number is memory unless
     this class runs. **a fence is not an exemption**: the class is scoped by
     the claims table and by nothing else, a count inside a fenced block is
     still a count with no command behind it, and what a fence exempts is the
     row's own evidence block — the `E<n>` definitions and their `-out:` lines.
     **and CITING a claims-table row is not a re-derivation**: a prose count
     sourced from a row is re-derived by re-running that row's own command, not
     by pointing at it. the scoping above assumes the ROWS are right, which is
     sound about a row and unsound about a sweep that defers to one instead of
     running it — measured, a round-2 sweep that wrote it had re-derived the
     census counts "by reference to their single sources in §6" and carried
     three false readings, each off by exactly the one line the classification
     missed, all three surviving three refine rounds and the emit gates.
     other measured instances: pins forwarded from an older tree, a 74/74 census
     at 73, an author narrowing the extent field to "outside fences".
     **and a claim ABOUT THIS ARTIFACT is about CLASSES, never COUNTS.** a count
     over an artifact is proved only at its last edit, so a spec carrying a
     census of its own text has no fixed point: every later edit invalidates it,
     the edit recording the proof included. no amount of care escapes it —
     measured, ten precheck rounds and 17 substantive findings, 15 citing no
     authority outside the artifact. two
     forms are legal and no third: state it as a CLASS ("every token the sweep
     returned is dispositioned"), which edits cannot falsify, or carry the
     number as a claims row with its rerun command, which this class already
     exempts. two companions kill the class rather than an instance — the
     instrument's metadata is ROUND-NEUTRAL ("the instrument's run on this
     text"), nothing to forget to bump; and the rule covers the refine log's own
     FIX NARRATIVES, not only its disposition paragraphs, which the reviewer
     reads as spec prose.
   - **named sweep class — the spec-ready contract, clause by clause.** round 1
     of a spec's or revise's self-loop walks §4's nine clauses in order and logs
     each as met or not, with the evidence (the command, the section, the row).
     this is precheck's P3 run first by the author: a clause the author could
     have read should never cost a precheck round — a cold spawn that reads
     the whole manifest again — and the literature is unambiguous that a
     self-loop improves only where it re-derives against something outside
     itself, which a checklist is. a round-1 log that does not walk the nine
     is a P9 finding.
3. **independent floor**: judgment-class claims belong to the reviewer; offloading
   author-self-fixable checks to the reviewer is the flagged anti-pattern
   (duplication + slowness), and "declared done" always triggers re-verification —
   completion claims are never inherited.

## 4. spec-ready contract

a spec is ready iff **all** of:

1. **self-contained** — executable by a cold implementer; everything the reviewer
   needs is in it (there is no side channel by construction).
2. **binding constraints front-loaded** — the constraints section is first; position
   bias is real.
3. **scope proven by command — BOTH halves** — discovery grep output, not
   intuition; the commit-unit partition covers exactly that scope. The
   OUT-of-scope half owes the same instrument, because it is the half that is
   wrong: for every construct this slice shares with code it does not touch — a
   state key, a ref, a helper, a vocabulary — the readers sweep is run and its
   result lands as a claims row (`count`, so the range stamp and the rerun
   command are already gate-enforced). "the other readers are X and Y" answered
   from memory is the most productive defect shape measured on this workflow's
   own source: six in one day, each a change that walked its own function and
   not the system around it — a clock amnesty that shifted every timer but one,
   a panel still rendering a budget the driver had stopped pricing, an advice
   line measuring HEAD where the owed derivation measures the declared branch, a
   cache keyed to a question its neighbour had already stopped asking. A slice
   that shares nothing records the sweep's empty result; that is a claim like
   any other, and cheaper than the assumption it replaces.
4. **commit-unit list** — per unit: id, subject (project convention), risk note,
   `relocation-only` flag where owed; per-unit diff cap respected (effective value:
   workflow default, project may override either way). the subject **and any
   message text this spec prescribes** — a remark, a trailer, a required line —
   satisfy the commit message boundary (`commit-messages.md` §1): a token the spec
   hands the author that the delivered repository cannot resolve is a finding here,
   where it costs an edit, not at the commit door, where it costs a rewrite. the
   subject the spec prescribes is also a claim about a diff that does not exist
   yet (`commit-messages.md` §2) — prescribing one that will be false of the unit
   as scoped is the same finding, caught at the same cheap moment.
5. **gate plan** — the gates each unit owes, incl. the **flip gate**: a named
   check that reads red on the baseline and green at HEAD (the property proven,
   not asserted). **the trigger is a property of the EVIDENCE, not of the
   change** — the gate is owed for every criterion the slice's close rests on
   that CAN read differently at the two states. a behavior change makes it
   unconditional; the absence of one exempts nothing, because an assertion
   reading identically before and after proves nothing about what this slice
   did, which is the whole of what the gate is for. so a doc-bound slice
   reaches the slot by the front door: its four project gates SKIP and its
   mechanical floor is its own per-slice checks (§9 C3) — those checks ARE its
   flip gate, filed in the slot as baseline/HEAD pairs rather than reinvented
   beside it under a local name. "none owed" stays honest only for a reading
   that is genuinely state-invariant, and it is named with that reason.
   measured on all three doc-bound slices this workflow has run: every one
   argued out of the older behavior-worded condition and none reached the slot
   — the condition, not the author, was what
   the slot was losing.
   **name only invocations the harness can
   actually make**: a project gate is `project.kv`'s own command string, run
   verbatim with no arguments, so the range it covers is whatever that string
   covers by default — for the composite acceptance gate, structurally HEAD-only.
   a gate plan that promises a `<base>..HEAD` audit the command shape cannot
   deliver is a finding HERE, where it costs an edit — measured four times across
   four slices, each conformance then describing a run no attested artifact
   shows. either declare the range form in `project.kv` so the
   harness runs it, or name the bare command and say HEAD-ONLY. **the plan is joined
   to the surface at the author's close**: the impl/fix emit refuses unless every
   project gate `project.kv` declares — build, lint, test, acceptance — holds a PASS
   row pinned to the emitting tree (or its named SKIP), not acceptance alone.
   the suite set DERIVES from the unit's
   target ownership: every suite that owns an edited surface runs, and a unit
   whose edits cross outside the acceptance surface forces the FULL acceptance
   composite into the slice close — a fixed suite list that the targets outgrew
   let the eighth broken site ride to a near-GREEN close (measured).
6. **claims table complete** (§2), numbers single-sourced.
7. **baseline pinned — logically**: branch + bound constructs with content echoes
   (shared-branch reality, `protocol.md` §9), not a frozen commit fiction.
8. **authority chain** — the spec cites the plan, never the previous turnover
   (turnover carries pointers + deltas only); precheck checks the chain.
9. **refine log present** — rounds, findings, severities, release reason.

## 5. risk class (low / med / high) — a depth modifier, never a skip switch

declared per slice at split; **re-derived independently** at split-check and again at
every review — precedent and streaks never decide.

- **low** — single-component, or zero-logic mechanical (rename / strip / format /
  docs / path-string), scope proven by discovery grep; or structure pre-decided by
  an accepted charter/ruling so the slice only executes it.
- **high** — any of: multi-component semantic decisions; build-system runtime
  instrumentation; public-API surface expansion.
- **med** — the remainder.
- **behavior change is never low, regardless of size**, and a behavior-changing
  slice owes the flip gate unconditionally (§4.5). the converse does not follow,
  and this is the sentence a doc-slice author has read as if it did: §4.5
  conditions the gate on the EVIDENCE, so the docs arm of `low` above exempts a
  slice from nothing — it still owes the pairs for every criterion of its close
  that reads differently at the baseline.

class modulates: checklist depth (low = compact forms), refine round budget, impl
stage budgets. **nothing is ever skipped** — every slice gets precheck + postcheck;
genuinely tiny changes ride as commit-units inside a slice (§6 fold rule), never as
slices.

**escape hatch**: mid-impl discovery beyond spec scope → stop, disclose an erratum,
re-enter revise at the **re-derived** class; never widen in place, never finish at
the old class "because it was almost done".
**and "re-enter revise" names the outcome, not a transition** — `stages.tsv` gives
impl and fix `next=built:postcheck,blocked:HALT_blocked` and no impl→revise edge,
so the author halts BLOCKED and the RULING is the channel: it authorises the
widening, `lib/resume.sh` resets the suspended stage so impl re-enters carrying
`rulings.pending`, and §11 lists owner rulings among the decision bases — so the
widening is recorded, rides the manifest and is reviewable, which is the whole
point of banning the silent kind. an erratum that forces the SPEC to change is
the case this does not cover, and it has none yet.

## 6. slice granularity (split-check re-derives these eight)

1. **one reviewable story** — spec + diff holdable in one reviewer pass; per-unit
   commit cap respected inside it. **a contingency discharges a risk only up to
   its own capacity.** a charter that answers the cap question by naming a
   pressure valve — sites it authorises moving to a follow-up commit — owes the
   valve's CAPACITY beside it: which sites, and how many lines they carry. an
   unsized valve defers the arithmetic instead of bounding it, which is the
   same "no artifact at split time can settle it" premise one level down,
   applied to a number that IS enumerable at split time (measured both ways: an unsized 83-line valve against a 137-line
   deficit cost two Class U halts; the one sized valve settled the cap at spec
   time, first try).
2. **independently gateable** — the slice's gate plan proves this slice alone,
   never "covered by a later slice's tests".
3. **green at every boundary** — build + gates pass at each slice close (revertable
   units; safe consolidation).
4. **dependency-ordered, vertical where possible** — interfaces before consumers;
   one behavior end-to-end beats a horizontal layer. hard edges ride the index
   as `after=` (see checkout binding below) — never as prose alone.
5. **semantic and mechanical never share a slice above the fold threshold** —
   ≤ ~15 LOC, zero-semantic, grep-clean folds in; larger mechanical work is its own
   cheap slice.
6. **scope proven by command** — a slice boundary is a discovery grep's output.
7. **risk first, mechanical tail last** — the design-uncertain slice cannot be
   allowed to invalidate landed mechanical work; each slice reduces ambiguity for
   its successors.
8. **no carry-forward** — a slice never leaves an inconsistency a later slice must
   reconcile; a forced carry-forward between adjacent slices is a merge signal.

merge signals: one functional intent one spec can bind; overlapping footprints;
later units depend on interfaces earlier ones introduce; forced carry-forward.
split signals: independently reviewable self-contained specs; disjoint footprints;
budget exceeded (`slice.max_diff_lines` / `max_commits` / `max_files`). the
terminal decomposition table is pre-declared at split — seams are design-knowable.
re-slice bookkeeping: `protocol.md` §7 (ids never reused; merges via split-check).

**checkout binding** (projects declaring a doc repo): each charter declares its
slice's repo — `code` or `doc` — and split carries it in the index grammar
`id:risk:repo:title[:after=NN,..]`. one slice never spans both trees: work in
the other one is its own slice, ordered by an interference declaration.
split-check re-derives the declaration against where the footprint actually
lives — a mis-declared binding sends every commit-unit of that slice to the
wrong tree, and the binding cannot be edited later: re-declaring an existing id
with a different repo is refused at emit — mint a new id and omit the old one
(it supersedes).

**delivery order is machine-carried.** the scheduler takes the lowest pending
id whose `after=` set is out of the way (done, cancelled or superseded) — the
charter's hard edges must therefore ride the index as `after=`, because prose
is machine-invisible and a re-split that mints ids out of dependency order
otherwise schedules them inverted (measured live). every after names a
strictly EARLIER id: id order is the delivery order, backward edges only, so
the graph is acyclic by construction. like the binding, the after set is
immutable per id — omit it to re-list a standing row unchanged; a different
set is a new id. split-check verifies the order MECHANICALLY, not from the
charter's prose alone: for every hard edge a charter states, the earlier
slice's id is lower or the later slice's entry carries the `after=` — a hard
edge that exists only as prose is a substantive finding (the scheduler cannot
read prose).

**sizing by risk.** the budgets are ceilings for low/med slices. a **high**-risk
slice targets **half** of them (≤1250 diff lines / ≤4 commit-units): postcheck
runs after the whole slice lands, so an error that survives the per-unit gates
has a blast radius proportional to what landed after it — pay the smaller-slice
cost exactly where that radius is expensive. measured basis: per-commit-unit
review failure rates jump sharply above ~600 diff lines (hence the 500 unit
cap), while a well-split ~2400-line multi-unit slice reviews cleanly — size
per-unit discipline protects depth; the slice ceiling protects the session.

## 7. precheck

**full form** (med/high, and any round that finds a substantive issue):

- P1 provenance + structure: header (baseline, freshness self-determined, round);
  the review matches its section structure — a mismatch is a draft; every manifest-carried ruling is accounted for — applied, or why not.
- P2 risk class re-derived from scratch; endorse or pivot with evidence; behavior
  change present → not low, flip gate owed.
- P3 spec-ready contract, clause by clause (§4).
- P4 claims: re-derive every load-bearing claim (counts, citations, absences —
  grep-class); **run each claims-table evidence command and compare its reading**
  (the emit gate checks parseability, never truth — a fabricated `false -> 999`
  row is yours to catch); **behavior rows first-hand**: open the anchored symbol
  and rerun the command yourself — a behavior assertion is never forwarded from
  the spec's own text (the class that cleared two HIGH prechecks unopened);
  spot-verify range stamps; absence claims carry their searched range; **every
  cite echo sits inside the section its anchor names** (`claims_cite_scope`);
  **the marker set reconciles** — the set of rows whose claim describes the tree
  BEFORE this slice's change must equal the set carrying `baseline`, and any
  prose counting either set agrees with both. This one is grep-class and it is
  the only claims defect re-derivation cannot reach: at precheck a ground-state
  claim is still TRUE, so running its command passes, and the emit gate reads a
  marker's parseability and never its truth. A missing marker therefore survives
  to the impl-emit tip resolution and costs a post-emit amendment cycle —
  measured on two slices of one topic, the second spec written after the first
  slice's diagnosis and reproducing the shape anyway. State the CLASS and check it;
  never restate the count in prose, where it re-stales on the next edit.
- P5 scope: re-run the discovery greps; commit-unit partition covers the proven
  scope; per-unit and slice budgets respected; **every unit's target files are
  committable in this slice's bound checkout** — inside that repo and not
  ignored there (`git -C <bound repo> check-ignore` / `ls-files`): a target the
  slice cannot stage is an impl-time halt discovered at review time instead.
- P6 gate-plan sanity: runnable as written (portable, correct exit-code capture);
  flip gate present where owed, with red-baseline evidence — **"owed" is §4.5's
  evidence test, never a behavior test**: a slice whose close rests on readings
  of the tree owes the pairs, a doc-bound slice included, and a `none owed`
  paragraph that then states baseline-vs-HEAD readings under another name is a
  finding here; gates read effective
  cap values; red readings are compared as **finding sets**, never counts;
  **suite set re-derived from the unit targets' ownership** — an edited surface
  outside every listed suite is a finding, and edits crossing the acceptance
  surface force the full composite into the slice close (§4.5).
- P7 authority chain: cites the plan (hash-pinned); no premise inherited from
  turnover prose.
- P8 DP audit: for each decisions-surface entry of this slice — Class A: re-derive;
  a pivot is a substantive finding. Class C: your re-derivation IS the concurrence
  (endorse authorizes; pivot withholds — one author rebuttal, then owner
  tie-break). a mis-classed U is a substantive finding.
- P9 refine-log audit: rounds present; severities match observable classes
  (gaming check); zero-finding first round flagged; residuals dispositioned; round
  1 walked the **spec-ready contract clause by clause** (§3.2) with evidence per
  clause; the
  §3.2 **prose numbers and line pins** sweep ran and its commands are in the log
  (a class the round owes, so its ABSENCE from the log is the finding).
- P10 verdict: ready | issues, severity counts (→ record), confidence, per-finding
  re-derivation commands, explicit non-coverage.

**compact form** (low risk only): P1 provenance/structure · P2 class re-derived
(one line per criterion) · P3 claims + discovery greps re-run in full (cheap at this
size) · P4 gate plan + caps + targets committable in the bound checkout ·
P5 verdict/counts/non-coverage. the moment a
substantive finding or a class pivot appears, the compact premise is broken: stop
and complete the full form.

## 8. conformance (author, in-band, per commit-unit)

after each implementer report: derive the expected shape **from the spec text**
(never from the dispatch prompt or the report); read the landed diff; the report is
a hint, the diff is the authority. per unit record in `conformance.md`: unit id ·
SHA · diff-vs-spec verdict · gate readings (or record references) · errata E-n with
dispositions · **if** this slice wired an instrument for a `gate`-tagged leak, which
one (§9 leaves that to the harvest, so nothing is owed here when it did not) ·
probes disclosed (worktree apply → measure → revert; tree clean).
**gate readings CITE the attestation, never narrate an invocation.** the gates
surface carries each run's result, the slice it ran under, its HEAD/tree/dirty pins, its log path, and
a fingerprint of the command that produced it; the command itself is the first
line of that log, verbatim. quote them. a sentence describing a composite or
range acceptance close that no attested record shows is the measured failure
here (four slices, each corroborated only by
a reviewer's own re-run) — an unattested claim in the artifact whose job is
attestation.
**the close owes a CENSUS SWEEP, and its extent is recorded rather than
inferred.** at impl/fix close, re-derive every `count` and `absence` row of this
slice's claims table whose command reads the tree, against the LANDED tip, and
amend the whole set — not the subset a gate FAIL named. the reason is structural:
the claims gate reads those rows for a range stamp and a well-formed command
LABEL and never executes them, so the rows whose truth the landing CHANGED are
precisely the class the gate is silent about, and silence reads as PASS. a
gate-driven repair otherwise fixes the gate's sight radius: measured on two
slices of one topic, one left two false census rows after its amendment and the
next left TWELVE, each verified false at the tip by the reviewer.
the general form is
worth carrying: **wherever a gate checks a proper subset of a class for truth,
the close owes that class its own sweep** — and the sweep's extent belongs in
the artifact, because a reader cannot otherwise tell a swept set from a lucky
one.
never commit over a red gate; a red gate gets the attribution check first
(`protocol.md` §9). the composite acceptance gate runs at impl close — the author
half of the one intentional double-run. conformance is honest about its limits: it
shares the spec author's blind spots; that is what postcheck exists for.

## 9. postcheck

**full form**:

- C0 process sweep: provenance headers across the slice's review chain; **DP audit
  sweep** — verify every DP audited at precheck was; **perform** the audit for
  DP-E entries (all four valve conditions held; your audit is the concurrence),
  any DP that missed one, and any DP whose latest row carries `amends=` (an
  amended decision is audited afresh — the earlier row is history, §11); refine-log audit incl. severity gaming; every erratum
  dispositioned; every ruling discharged; progress ledger complete vs the spec's
  commit-unit list; where the slice added or extended a mechanism, the closing
  verification its class owes (§13) has run and its output rides in the record —
  an unpinned new rule is a finding, not a style note.
- C1 scope: the progress ledger's SURVIVING SHA set (the last row per commit
  unit; `supersedes=<sha>` retires an earlier registration, which may no longer
  resolve), each resolved in `git log` — this and only this is under review.
  **`supersedes=` asserts the old sha was REPLACED.** A retired sha that still
  resolves as an ancestor of the surviving one is the multi-commit-unit shape,
  not an amend: the ancestor's diff has silently left this scope while its code
  is on the branch, and a reviewer meeting one reports it (`protocol.md` §9;
  measured twice).
- C2 conformance re-derived: diff-vs-spec per commit-unit, formed independently
  before consulting the author's `conformance.md`; then reconcile — divergence is
  itself a finding.
- C3 gates: read the harness-attested gate records (pin must match the reviewed
  tree — for a doc-bound slice that pin is the doc checkout's) — do not re-run
  them; **run the one you own**: the composite acceptance gate, fresh shell, at
  the reviewed tip. a doc-bound slice has no acceptance concept: the gate
  records a structural SKIP and there is nothing to run — read the record, and
  hold the slice to its spec's own per-slice checks instead. read
  `gate=spec_claims_tip` too: the spec's own claims table re-resolved at the
  landed tip at the author's close, recorded and never refused — a FAIL row
  there names a spec row the slice's own commits invalidated, and it is a
  finding to write, not to re-derive.
- C4 caps + metadata: per-unit diff caps (relocation-only declared where used),
  subject regex, trailer policy (owed AND banned trailers are both gated now —
  read the attestation, spot-check the rest) — from records plus spot-check.
  then the one metadata question no record answers: **is each subject TRUE of its
  own diff** (`commit-messages.md` §2) — misdescribes (a structural verb whose
  departure site is not in the diff) and under-describes (a production-visible
  addition no clause implies). read from the diff C2 already derived, so it costs
  a sentence per unit and never a second reading; **it is owed in the compact
  form too** — all three measured escapes rode a `conforms` verdict, and the
  gates cannot see this one at all.
- C5 cross-reference sweep: old paths/symbols the spec retires read zero — with the
  searched range stated.
- C6 flip evidence: red on baseline, green at HEAD, for every criterion the
  slice's close rests on that reads differently at the two states (§4.5 — the
  evidence test, not a behavior test; a doc-bound slice discharges it through
  its own per-slice checks); red baselines compared as finding sets.
- C7 adversarial pass: assumptions the spec silently relied on — 2-3 (low/med),
  5-7 (high) — each verified.
- C8 anti-bias residue, three lines (reviewer card).
- C9 verdict: conforms | findings; every finding carries severity, re-derivation
  command, and **`leak_class`** — `precheck` (precheck-catchable) · `conformance` ·
  `gate` (an emit-time predicate over records the harness ALREADY HOLDS could
  have refused it — a statement about what is possible, never an accusation that
  something is broken, and it obligates the tagging slice to nothing) · `novel`.
  counts + confidence +
  explicit non-coverage. **the class is recorded on the learnings surface, one
  `record.sh learn` per finding, before the record emits** — the surface, not
  the review file, is what the learning loop (§14) reads, and the emit gate
  refuses a postcheck whose substantive count exceeds its rows for this
  (slice, round) — a measured gap.

**compact form** (low risk only): C0 compact (provenance + DP sweep + errata) ·
C1 ledger scope · C2 per-unit conformance spot-check with recorded non-coverage ·
C3 acceptance re-run · C4 metadata/caps · C9 verdict with leak_class. same
escalation rule: any substantive finding breaks the compact premise — complete the
full form.

**either form: the `gate` tag is FREE, and the instrument is the harvest's.**
Classifying is a question of fact a reviewer can answer at the moment it
re-derives the finding — *could an emit-time predicate over records the harness
already holds have refused this?* — so it costs the classifier nothing but the
sentence. Deciding to BUILD the instrument is a promotion, and promotions have
exactly one home in this workflow: §14's learning loop, read at harvest off the
learnings surface, which C9 already routes every tag to.

**A `gate` tag names the record its predicate would read** — `git`, the progress
ledger, the gates or decisions surface, an enumeration inside the artifact
itself. That one clause is the whole discipline: it keeps a free tag honest, it
is the same "carry your evidence" rule every other claim here obeys, and it
hands the harvest a buildable thing instead of an accusation. **It is a FIELD,
not a sentence**: `record.sh learn --leak-class gate` refuses without
`--record <name>`, valid names being `git`, `artifact` (the fourth case above),
or any registered store surface. Asking for it costs nothing a correct
classification did not already contain — you cannot answer C9's gate question
YES without knowing which record the predicate reads — and being a field it
cannot be nodded at, which a sentence beside a free tag can. The three other
classes name no predicate and the flag is refused for them.

**Single anchor still applies, to the HARVEST rather than to the slice**: §14's
two-anchor bar covers judgment-class leaks, and for one the tag itself calls
machine-catchable the first escape is the proof — so the maintainer may promote
a `gate` tag on one instance, up the ladder (**structural > script > prose**,
§14). The tagging slice owes nothing; if it happens to wire the instrument
anyway, §8 says where that is recorded.

*measured basis: 0 of 65 rows ever tagged
`gate` while 24 were machine-catchable; a classification that charges the
classifier is a classification that does not happen.*

## 10. convergence

the ferry computes the **severity-trend predicate** from the review records of
either loop (precheck↔revise and postcheck↔fix alike): two consecutive rounds of
the same review stage with non-decreasing substantive counts, the newer round
holding at least one substantive finding (a wording-only round is convergence,
not discord) **and at least one `repeat`** (§1 — a finding that survived the
previous round's remediation) → `halt(disagreement)`. an all-new non-decreasing
round is the loop converging on new material, not discord, and does not park; a
record with no split predates the field and reads as all-repeat (unchanged).
a loop that never carries a repeat is bounded by rounds instead: at
`review.max_rounds` (config, per (slice, stage)) with substantive findings still
open the ferry parks `halt(disagreement)` naming the bound — without it the split
would leave such a loop with wallclock as its only stop.
the owner's options: **continue** (evidence: strictly narrowing findings) ·
**split** (the slice does too much — re-slice) · **redesign** (the premise is
wrong — back to the plan/charter). neither author nor reviewer escalates by
feeling; the predicate is the trigger, the owner is the judge. a ruled continuation
discharges the ruled (slice, stage, round) for both predicates at once. verdict
immutability and the no-verdict-shopping rule (reviewer card) apply throughout.
the park text names both review files and points at the later round's
`## 3. absorption`: that section is the owner's question set for this halt class —
written by the reviewer with both rounds in hand, template-gated at emit — and the
ferry composes no document of its own, because the only thing it holds that the
reviewer does not is the count.

the **topic** loop (split↔split-check) gets a different predicate, and the
difference is not an oversight — it is what the two loops iterate over. a slice
loop reviews a spec against a tree, and its findings shrink as the spec is
corrected. split-check re-derives §6's eight criteria, which are all properties
of the DECOMPOSITION, but the findings land on `charters.md` — whose attestation
prose grows every round by construction, because a round that absorbs a finding
adds the sentence describing the absorption. counting findings over a claim
surface that only grows has no terminating condition (measured:
13 rounds against an index with one distinct
value).
so the topic loop's convergence is computed on the **decided artifact**: when the
slices index is byte-identical across the last `split.fixpoint_emits` (default 2)
split emits and split-check still returns `flag`, the ferry parks
`halt(disagreement)` naming the fixpoint — the cut is settled and what remains is
prose about the cut. the same three owner options apply, and the same discharge:
a ruled continuation clears that (slice, stage, round) once. **the predicate
counts no findings**, which is deliberate — it is why it cannot inherit the
count-only blindness the severity-trend one has.
the fixpoint bounds a cut that FROZE and cannot see its opposite — a cut that
THRASHES, a different index every round — so the topic loop carries the same
round bound the slice loops do: at `split.max_rounds` with split-check still
flagging, `halt(disagreement)` names the **split round bound**. it is the topic
loop's only other stop, because split runs at slice 00 and the slice wallclock
does not price 00; without it the fall-back was the topic budget parking on a
cause it never diagnosed. the two are ordered, not alternative: a frozen index
parks as the fixpoint before the bound is read, so the owner is handed the
specific cause, and a thrashing one falls through to the bound — where the
question is whether the PLAN can be cut as written, not whether the review is
right.

## 11. decisions — Class A / C / U

**decision basis** (what makes a choice derivable): the project's coding rules and
architecture invariants; the workflow's standing disciplines; owner rulings and
standing directives; repo evidence re-derivable on demand. a choice that cannot be
derived from these is not Class A.

- **Class A — author decides + records.** ALL four: determinable under the basis;
  reversible in unpushed commits; in-scope and owned; unconflicted with standing
  directives. typical: naming, placement, internal shape of an owned module, gate
  strengthening, test structure, a finer re-slice of in-scope work.
- **Class C — concurrence-gated, two keys before execution.** non-semantic ties the
  basis cannot rank (naming schemes, placement taste, gate strictness). the
  reviewer's re-derivation at the next review is the concurrence and **precedes
  execution**; re-slice merges route through split-check first. discord: one
  rebuttal round, then owner tie-break — never a different reviewer.
- **Class U — owner decides.** semantic tradeoffs; scope/direction changes;
  irreversible or outward actions (push, publish, deleting others' artifacts);
  ownership-boundary crossings; externally unverifiable assumptions; anything
  flagged "ask me". an endorsement can validate a recommendation's quality; only
  the owner decides. co-pending U questions batch into one halt.
  **the halt owes its question set on disk, `slices/<nn>/halt.<n>.md`, per
  `templates/halt.md`** — the zero-context-ruler standard made structural:
  the owner rules from that text alone, no session history, no other file.
  the emit gate derives `n` (this slice's class_u halt count + 1), names the
  path, and checks the template's sections in order: the question · why it
  needs a ruling (evidence, the boundary crossed) · blast radius (artifacts,
  index rows, files and their readers, what is irreversible) · options,
  keep-as-is included, each with delta / for / against / what becomes
  required or impossible after / cost · worked examples — a concrete scenario
  traced under EVERY option, a second wherever the options diverge on a
  different input · recommendation with its reason and fallback · evidence ·
  refine log. depth scales — a binary confirm still owes the why, both
  deltas, and one example. options that all reach the same outcome are not a
  decision point: do not spend an owner slot on one — record the disposition
  instead. the record's `detail` leads with the path; the park message and
  the owner's page carry it.
- **ambiguity: A-vs-C doubt → C; any doubt about U → U.**

**DP record** (decisions surface; one DP = one choice):

```
dp=<slice>/DP-<n>          class=A|C|E
choice=<taken> over <alternatives>
basis=<principle/rule + why it determines>
evidence=<re-derivable citations/commands>
revert=<the follow-up shape if pivoted>
status=pending_audit
amends=<t of the row this one supersedes, empty on a first record>
```

**a recorded DP is corrected on the surface, never only in prose**: re-record the
same id with `record.sh decision --amend`; both rows stay (history is never
destroyed), the new one carries `amends=<t>` and re-enters `pending_audit`, and
every reader — the compose dump, P8, C0 — takes the LATEST row per id. the same
rule binds the progress ledger: a unit re-registered at a new sha carries
`supersedes=<old sha>`, and review scope is the surviving set (§9 C1).

the status field carries one value because one value is written; the audit's
OUTCOME — endorsed, pivoted, vetoed — lives in the review prose of the checkpoint
that performed it, and a format may declare no value no writer produces
(30-closure refuses it; a status vocabulary once carried a value no writer produced).

**DP-E valve** (class=E; the only no-prior-concurrence Class C path): non-semantic
+ reversible + immediately blocking + logged; audited at the next postcheck, which
performs the concurrence. a mid-impl choice that is not immediately blocking is not
an emergency — halt and get concurrence.

**audit exactly once**: every DP is audited at the earliest reviewer checkpoint
that follows it (precheck normally; postcheck C0 for DP-E and strays). **veto**:
the owner may veto any DP at any time; the veto is recorded and a fix slice must
exist before close-out. deciding silently, bundling choices into one DP, deciding
U "because the owner is away", or re-litigating an owner ruling as Class A are all
violations.

## 12. anti-bias and the independence ceiling

three checklist lines (reviewer card §anti-bias) are the entire carried residue —
no recited ceremonies. the ceiling stated honestly: lineage independence is not
cognitive diversity; a family blind spot can cross the split. mitigations: a
different reviewer model where available (recommended default), the owner veto, and
Class U staying with the owner no matter how confident both agents are.

## 13. closing verification (a change that adds or extends a mechanism)

moved whole to `maintenance.md` §2 — what a change that adds or extends a
mechanism owes before it is called done: the cost table by change class, the
five steps, and the two instruments that are run against reality rather than
against the change. this file is what the REVIEW STAGES perform on a slice and
that section is what a MAINTAINER performs on the tree, which is the whole
reason it moved — `60-gates`' own-tree cap raised the question and the
audience test answered it, the same way it did for `operations.md` §7. the number is kept so every citation of
`review-standards.md` §13 still resolves.

## 14. learning loop

- postcheck findings carry `leak_class` (§9 C9); workflow-defect observations
  (from stages or pilot — each structurally blind to what the other sees) append
  to the observations surface.
- **promotion**: two independent anchors — different slices or topics, same
  mechanism — promote; target chosen **structural > script > prose** (a rule that
  could have been a gate is hot-memory spent twice); the owner confirms; the change
  lands as a dev-time workflow-source commit. The durable home for promoted and
  open observations alike is the tree-root `iteration-log/` (INDEX + one file
  per open entry) — the two-anchor judgment reads the INDEX, and anything that
  has not reached it when its topic tree is cleaned is gone.
- **what "two independent anchors" requires — a CONJUNCTION, not a unit.** The
  mechanism OCCURRED twice, AND the two sightings were not made by the same
  observer. Neither half implies the other, and each fails in its own direction.
  One occurrence described twice is ONE anchor however many actors wrote it down
  — the author at a halt and the pilot tracing the same chain at close-out, or
  two sessions reading one measurement. Two occurrences seen by ONE observer is
  one anchor however far apart they were — two parks on slices 00 and 01 with
  one pilot spanning the topic. **"different slices or
  topics" above is the OCCURRENCE half said concretely**, never a third thing.
  An entry argues the conjunct that is CONTESTED and may leave the other silent
  ONLY where the tree settles it. It settles it in two places and no others: two
  different SLICES, and two different COLD stages. A cold spawn mints
  `delivery-<topic>-<slice>-<stage>`; a WARM one reuses the held session's own
  name, and `stages.tsv` marks five of eleven stages `warm-author` — so within
  one slice `spec → revise → impl → fix → turnover` is ONE session, and review
  rounds ≥2 are one with round 1's reviewer (`decide_mode`). Two different stage
  LABELS are therefore not two sessions, and an entry whose two sightings share a
  slice must name the observers rather than assume the stage names do it. What may never be left silent is a bar argued on one half while
  the other is in doubt — one actor seeing the same thing twice, or two actors
  describing one event.
  It is a BAR and not a total: two is the threshold, and a larger tally in an
  entry is narrative rather than what this bar reads. Both halves are facts the
  entry's author holds at writing time; no store records either, and none needs
  to.
  **§12's ceiling is not closed by this**: two observers can share a blind spot —
  same plan, repository, backend and model family — which is why promotion ends
  at *the owner confirms* rather than at the count.
- single anchor = **DEFER**, logged; never enforce an unpromoted pattern — the
  one carve-out is a `gate`-tagged postcheck leak, whose instrument is owed at
  the first escape (§9 C9); observations and judgment-class leaks keep the
  two-anchor bar.
- deprecation is periodic and owner-confirmed; cross-topic aggregation stays manual
  in v2.0.
