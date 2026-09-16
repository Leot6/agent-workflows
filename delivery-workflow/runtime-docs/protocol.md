# protocol — the topic and slice flow

> reference (on-demand). how work moves: stages, records, routing, sessions.
> checklists and contracts: `review-standards.md`. operator matters: `operations.md`.
> the machine authority for stage → verdict → next and for owed/manifest columns is
> `config/stages.tsv`; this document narrates it and must never contradict it.

## 1. shape of a run

one **topic** = one plan driven to reviewed, committed code. a topic splits into
**slices** (cut by function; a slice may carry many commit-units). a slice advances
through **stages**. two agent roles do the work — author and reviewer, always in
separate lineages (the two-session property) — plus the implementer as an author
sub-agent. the **ferry** mediates every handoff: it selects the next stage by table
lookup, composes the stage prompt from a template + manifest, spawns or reuses a
session, waits for the completion record, and routes on the record's mechanical
fields only. no agent ever writes a prompt; at most one stage session is active per
slice at any moment.

the workspace is any directory carrying `project.kv` (kept at
`plans/topics/<topic>/delivery/` in the two-tree deployment): human/agent
artifacts at the top
(`project.kv`, `charters.md`, `slices/<nn>/…`, `closeout.md`), machine state under
`.runtime/` (store surfaces, rendered prompts, logs — regenerable, never hand-edited).

## 2. topic flow

```
launch → preflight (deps, disk, project.kv present, repo locks, test notification)
      → startup reconcile (fence stale delivery-* sessions; never blanket-wipe)
plan-validate → split → split-check → slices (sequential in v2.0) → close-out
```

- **checkouts.** a topic claims every checkout its adapter declares — the project
  repo and, when declared, `doc.repo` — in the fixed order code → doc, and
  releases both at COMPLETE. each slice binds to exactly ONE of them, declared
  per charter and cast at split (`id:risk:repo:title[:after=NN,..]`); the
  binding decides where its commit-units land and where all of its evidence is
  read (`review-standards.md` §6). a doc-bound slice runs no build/lint/test/
  acceptance gate — those record a structural SKIP — and obeys the same commit
  convention as the code repo.
- **delivery order.** slices run at the lowest pending id whose `after=` set is
  out of the way (done/cancelled/superseded satisfy; pending/active/missing
  block). the id order IS the delivery order — every after names a strictly
  earlier id, so the order graph is acyclic by construction — and a charter
  hard edge must ride the index as `after=` (prose is machine-invisible;
  `review-standards.md` §6). pendings that can never schedule park
  `stall_record` instead of walking to close-out.

- **pins.** split pins the plan hash; every slice start re-checks it — mismatch =
  `halt(plan_changed)`. topic start pins the workflow tree's git SHA; every spawn
  re-checks — mismatch = `halt(workflow_changed)`; a deliberate relaunch adopts the
  current tree and repins, freeze point audited (land workflow changes under the
  maintenance rule first: no live stage, self-check green). plan-validate also
  adjudicates the plan preamble's pinned SHA(s) once, at this boundary (the
  producer's consumer precondition): pin→HEAD drift classified benign/blocking;
  blocking → `not_ready`. after the boundary, shared-branch discipline (§9)
  governs — the pin is not re-chased per slice.
- **split-check is also the standing return path**: every later re-slice merge
  proposal routes through it before execution (§7).

## 3. slice flow and the transition table

```
spec → precheck → (revise → precheck)* → impl → postcheck → (fix → postcheck)* → turnover
```

next-stage selection is a lookup in `stages.tsv` over closed vocabularies — changing
the flow is editing data. per stage (mirror of the table; the table wins):

| stage | scope | session | owed (static ⊕ dynamic) | verdicts → next |
|---|---|---|---|---|
| plan-validate | topic | cold | validation_note; handoff | ready → split · not_ready → halt class_u |
| split | topic | warm-author | charters.md; slices index; handoff | done → split-check |
| split-check | topic | cold | split-check review; handoff | concur → slice loop · flag → split |
| spec | slice | cold | spec.md; handoff | drafted → precheck |
| precheck | slice | cold (rounds ≥2: warm-reviewer) | precheck review; handoff | ready → impl · issues → revise |
| revise | slice | warm-author | spec.md; handoff | drafted → precheck |
| impl | slice | warm-author | commit-units (@cu, from the spec); dispatch (as sent, ≥1); conformance.md; handoff | built → postcheck · blocked → halt blocked |
| postcheck | slice | cold (delta rounds: warm-reviewer) | postcheck review; handoff | conforms → turnover · findings → fix |
| fix | slice | warm-author | @cu; conformance.md; handoff | built → postcheck · blocked → halt blocked |
| turnover | slice | warm-author | turnover.md; handoff | done → next slice · reslice → split-check |
| close-out | topic | cold | closeout.md; handoff | done → COMPLETE |

**inputs** are the manifest columns of the same row: required entries must resolve or
the ferry parks `template_error`; optional entries render as `none (<reason>)`. the
role card is always the first required item; a pending ruling joins the manifest of
the stage it suspends (§6).

**owed derivation** is one code path (`lib/owed.sh`): the `stages.tsv` owed column ⊕,
for impl/fix, the spec's commit-unit list resolved through the progress ledger. the
spec is a trusted source for the dynamic part because precheck reviews it.

## 4. handoff — the record is the only completion

a stage completes **only** through `session/record.sh emit` as its final action. the
emit validates the schema (stage, single-use nonce from the volatile prompt header,
verdict from the closed vocabulary, refine/severity fields where owed — a review's
substantive count split into new/repeat from round 2, `review-standards.md` §1 —
confidence HIGH/MED/LOW), derives the owed set, and refuses emission while any owed
artifact is missing. the profile's Stop hook runs the same check — a turn cannot end without a
valid record. the ferry's advance check and its park-on-miss read the same owed
derivation (the single-list invariant):

- DONE-shaped record with a missing owed item → `park(owed_miss)` on the **first**
  miss, naming exactly what is missing — never an identical respawn.
- malformed record → `park(stall_record)`; failed nonce/stage authentication →
  `park(stall_mismatch)`. never a silent advance.
- for impl/fix, the advance check resolves the progress ledger's cu → SHA entries
  against `git log` — completion evidence is the repo, not a private marker.

any stage may, instead of a stage verdict, emit a **halt**: `class_u` (owner decision
needed; batch every co-pending question into the one halt, written to
`slices/<nn>/halt.<n>.md` per `templates/halt.md` — the emit gate names the path
and checks its sections) or `blocked` (cannot proceed; evidence attached). the table's explicit spellings (plan-validate
`not_ready`, impl/fix `blocked`) are the common cases of the same mechanism — **with one
difference that matters to whoever has to read the park**: `--halt class_u` owes the
question-set document above and the emit is refused without it, while a VERDICT-routed
`not_ready` runs the ordinary owed path for its stage (`validation_note;handoff`), so it
writes no `halt.<n>.md` and its batched questions ride the record's `detail=` alone —
unstructured, ungated, and the thing the owner then rules from. `launch.sh status <ws>
--halt` prints the halt surface untruncated and so reads either shape;
`operations.md` §3's class_u row is the operator-facing form of this.
vocabulary note: **halt(x) and park(x) name the same event** — "halt" speaks
from the record/flow side (a stage suspended the flow), "park" from the
ferry/operator side (the run stopped with reason x, playbook in
`operations.md`); the reason vocabulary is one closed set.

## 5. artifact names

owed names in `stages.tsv` are symbolic; on disk:

| symbolic | file |
|---|---|
| validation_note | `slices/00/validation_note.md` |
| charters.md | `charters.md` (workspace root; machine index = slices store surface) |
| splitcheck_review | `slices/00/splitcheck.N.md` |
| spec.md / conformance.md / turnover.md | `slices/<nn>/<name>` |
| dispatch | `slices/<nn>/dispatch.N.md` — the implementer prompt as sent, headed `dispatch: cu-<N> · model=<m> · effort=<e>`; N counts up per slice across impl and fix. impl owes at least one; a fix that dispatches records its dispatches the same way |
| precheck_review / postcheck_review | `slices/<nn>/precheck.N.md` / `postcheck.N.md` (N = round; `*_latest` = highest N, `*.prev` = previous round) |
| halt (class_u) | `slices/<nn>/halt.N.md` — the question set (`templates/halt.md`); N = the slice's class_u halt count, derived at emit. Written by the **`--halt class_u` emit only**: a class_u reached by verdict routing (§4) writes no file and its question set is the record's `detail=` |
| ruling | rulings surface + archive `slices/<nn>/ruling.N.md` |
| closeout.md | `closeout.md` (workspace root) |
| handoff | store record (handoff surface), never a file |
| plan_slice | `.runtime/prompts/plan.<nn>.md` — the ferry's per-slice excerpt of `plan.md` (context + the items the charter's `## slice <nn>` section names + invariants; history dropped); `plan.md` itself stays the citation authority |
| progress / ledger / gates / decisions / observations / learnings / slices_index | store surface dumps, `.runtime/prompts/surface.<name>.txt` — the whole surface; `<name>@nn` (gates, ledger) = only the rows stamped `slice=<nn>` plus rows carrying no slice field, as `surface.<name>.<nn>.txt` |

review files are append-only from the moment they carry a verdict; a new round is a
new file (`precheck.2.md`), never an edit of round 1.

## 6. rulings round-trip

`halt(class_u)` (or any park needing an owner decision) → notify pages the owner →
the owner rules → the pilot (or owner) relays it **verbatim**:
`launch.sh rule <ws> --slice <nn> [--topic] [--stage <stage>] --text "…"`. eight
rules govern the round-trip, each load-bearing:

- **verbatim relay** — the pilot never paraphrases a ruling.
- **resume gate** — the halt holds until a ruling **addressed to its slice**
  (and stage, when stage-addressed) exists; the stage cannot respawn without one.
- **manifest carriage** — the suspended stage re-enters with the ruling in its
  manifest (`RULING=rulings.pending`) and discharges it.
- **disagreement discharge** — a `disagreement` ruling instead discharges the
  severity-trend predicate for the ruled (slice, stage, round); the loop
  advances per the table.
- **one deliberate double** — rulings are the store→file exception: machine
  record + `slices/<nn>/ruling.N.md` audit archive; one direction, no
  reconciliation.
- **standing directives** — never re-litigate a ruling as a Class A choice
  later; because they stand, `rulings.pending` resolves to ALL of the slice's
  rulings, riding every later manifest of that slice.
- **topic scope** — a ruling that fixes a MECHANISM rather than one slice's
  question is relayed with `--topic`: it still answers the halt named by
  `--slice`, and it rides every slice's later manifests (one selector,
  `lib/rulings.sh`, serves carriage and the door below). Without it a ruled
  mechanism recurred one slice later at one owner round-trip per slice.
- **mid-flight door** — "rides every later manifest" is the next stage
  boundary; a ruling landing while a session runs was not in its manifest.
  `record.sh emit` refuses while a ruling addressed to the attempt's slice (or
  topic-scoped) carries `t` later than the attempt's spawn, until the emit
  names every such ruling by token (`--ruling-ack <slice>.<n>,…`); the record
  then carries `rulings.midflight=`. The ruling costs a re-read, not a round.

## 7. re-slice

turnover's standing step inventories the remaining plan against reality:

- **merge** proposals (slices that turned out coupled) → verdict `reslice` → the
  proposal routes to **split-check for concurrence first** (Class C — two keys
  before execution).
- **finer split** → Class A: record the DP, update charters + index at the next
  split-check-visible point.
- **slice ids are never reused or renumbered.** a merge mints a new id; superseded
  ids stay in the index as superseded; a config override addressing a retired id
  faults loudly, and a split that re-lists one is refused (its row would stay
  retired and the work would never be scheduled — mint a new id instead).

## 8. session model

two sessions per slice — one author, one reviewer — slice-scoped, both closed at
turnover. cold/warm is the static `session` column of `stages.tsv`, decided by the
ferry; **no agent ever declares or is told its own spawn mode** (prompts never
assert it; a reviewer records freshness it derives itself).

| spawn | mode | why |
|---|---|---|
| spec (slice start) | cold | context reset point; drift capped to one slice |
| revise / impl / fix / turnover | warm (author session) | authoring context is the value; capacity bounded by slice budgets |
| precheck round 1 | cold | the independent first pass — freshness is its definition |
| precheck rounds ≥2 | warm (reviewer session) | verify-absorption rounds are warm by design |
| postcheck round 1 | cold | fresh eyes on the landed commits — the floor's defining property |
| postcheck delta rounds | warm (reviewer session) | verify-only |
| after death/park | cold | idempotent re-entry from artifacts + store |
| operator `all_cold=true` | cold | debugging / suspected drift |

warm reuse preconditions: session alive + `awaiting_input` signature + empty
composer; any miss → cold fallback, audited. warm re-activation carries a fresh
nonce. a held (inactive) session is exempt from liveness monitoring until reused.
round-≥2 review prompts are round-templates, not warmth-templates: they work
identically in a reused or a fallback-cold session, because they instruct from
artifacts on disk, never from remembered context.

## 9. shared branch — logical baseline and attribution

colleagues commit to the same branch; a fixed base SHA is a fiction. therefore:

- the spec pins a **logical baseline** (branch + the constructs it binds, with
  content echoes), not a frozen commit.
- **review scope = the progress ledger's SURVIVING SHA set.** postcheck reviews
  exactly the commits this slice landed, resolved against `git log` — not
  "everything since a hash". a unit re-registered at a new sha (an amend, a
  rebase) carries `supersedes=<old sha>` on its row; the earlier registration is
  history and out of scope, and may no longer resolve. **`supersedes=` means the
  old sha was REPLACED, and that is the whole of its licence.** A unit that lands
  as SEVERAL commits along a pre-declared seam registers each piece under its OWN
  cu id at impl time — never by re-registering the tip and superseding the first
  piece, which retires a commit that is still a live ANCESTOR of the surviving
  one: its diff leaves this scope and the emit-time commit gate's per-commit
  attestation while the code sits on the branch. Measured twice in one topic,
  496 and 395 lines.
  The shape is available: the commit gate iterates the LEDGER's unit set, so a
  seam piece under its own id is attested like any other.
- a red gate first gets the **attribution check**: re-run with our ledger commits
  removed (probe worktree). red both ways = external breakage → `halt(blocked)` with
  the evidence attached — not our defect, and never silently absorbed.

## 10. convergence and attempts

three guards, deliberately disjoint:

- **severity-trend predicate** (review-loop convergence; covers BOTH loops —
  precheck↔revise and postcheck↔fix): two consecutive rounds of the same review
  stage with non-decreasing substantive-finding counts (mechanical record fields),
  with at least one substantive finding in the newer round — a wording-only round
  (substantive=0) never trips it (wording never blocks alone) — **and at least one
  `repeat` in the newer round** (`findings.substantive.repeat`, the reviewer's own
  split of the count: a finding that survived the previous round; a record with
  no split reads as all-repeat) → `halt(disagreement)`. A loop whose rounds are
  all new is bounded by `review.max_rounds` per (slice, stage) instead, parking
  the same class with the bound named. The owner picks continue / split /
  redesign. A disagreement ruling discharges the ruled (slice, stage, round) for
  both — stage-scoped, because rounds are numbered per (slice, stage).
- **loop detector**: per (slice, stage), a fingerprint of prompt body (volatile
  header excluded) ⊕ owed-artifact hashes ⊕ manifest-resolved input content hashes
  ⊕ last failure class, matched against the last K=4 → `park(no_novelty)`.
  owed-artifact or manifest-input delta counts as novelty (an owner hand-edit to
  an input is a legitimate recovery move); incidental churn outside the manifest
  does not. history lives in the store and survives relaunches.
- **budgets**: per-(slice,stage,round) attempts, per-slice and per-topic
  wall-clock — economics, self-describing on trip (`budget_attempts` /
  `budget_wallclock`). A deliberate relaunch after any mechanical park is a
  redrive: the parked stage's count and fingerprint history clear, buying one
  fresh bounded set (parks are deliberate exits the watchdog never restarts).

## 11. what pages a human

full-auto halts only for: Class U · implementer BLOCKED · genuine author↔reviewer
disagreement · push. everything else self-heals (nudge → bounded respawn) or parks
with a self-describing reason; every reason's playbook is `operations.md` §parks.
a halt names what stops the automation, never who may answer it: the owner rules,
and a pilot may issue the ruling ITSELF only under the three conditions in
`cards/pilot.md` §when the ruling is yours to issue — forced by an opened primary
artifact, no design content, wrong-answer caught downstream — reporting it
immediately, since §6 makes a standing directive unwithdrawable.
