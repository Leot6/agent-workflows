# delivery-workflow v2 — architecture

> Settles the target architecture: mission, roles, naming, file layout, topic and slice
> flow, the session model, the implementer spawn model, and the operator surface.
> Status: settled design, owner-reviewed; §12 records the settled rulings.
> v1 = the supervisor-manager-workflow tree this redesign replaced (kept read-only
> on the original deployment; not part of a standalone copy of this tree).

## 1. Mission and stance

Drive small-to-medium implementation work from a ready plan to reviewed, committed code,
through an independent quality gate, **unattended by default** (full-auto; the only human
gates are Class U decisions, implementer BLOCKED, genuine author↔reviewer disagreement, and
push). Two goals: structural elegance (small, modular, declared-not-coded) and elimination of
the v1 failure classes (stuck loops, circular retries, silent drops).

Four root moves organize the design; every recorded v1 failure cause traces to one:

1. **One declared contract per stage, one reader function.** Each stage type's owed-output
   set is declared in `config/stages.tsv`; the stage's completion gate, the ferry's advance
   check, and park-on-miss all call the same derivation (`lib/owed.sh`). A backstop can no
   longer share an item with the failure it catches, because there is only one list.
2. **One atomic store, one writer class per surface** (`lib/state.sh`, `.runtime/state/`):
   generation + checksum, fault ≠ absent, no dual-write, no projections — the v1
   state-drift class loses its habitat.
3. **Capabilities, never names.** A backend is a *declaration file* (command-map + screen
   signatures + capability list); the ferry switches on declared capabilities only —
   a renamed CLI can never silently change behavior. See `backend-seam.md`.
4. **Judgment flows to the cheapest instrument that can hold it.** Mechanical claims are
   gated at emit time; author-fixable defects close in the author's own refine loop; only
   judgment-class claims reach the independent reviewer. This is what makes the reviewer
   fast without weakening the floor. See `review-and-slices.md`.

**Admission discipline** (standing, applies to every mechanism in these documents and to all
future additions): a mechanism enters v2 only with (a) the harm it prevents named, (b) an
argument why v2's structure does not already absorb that harm, and (c) — for anything beyond
the v2.0 minimal core — demonstrated need from a real run. Ease of implementation is not a
reason to build. This makes "derive by harm, not by count" procedural; the
carry/retire ledger lives in `migration-and-acceptance.md`.

## 2. Roles

Locked names: **pilot, ferry, author, reviewer, implementer** — the roles a RUN
has. Every one of them exists inside a topic and the ferry composes for it, which
is what the lock is about; the two parties below are not in that set for the same
reason, and their absence from it is a statement rather than an omission.

| role | kind | owns | never does |
|---|---|---|---|
| pilot | optional LLM/human operator | routing halts, relaying owner rulings via `launch.sh rule`, relaunch, notify granularity | authoring, reviewing, deciding Class U / push / disagreement substance, reading review content |
| ferry | component (process) | stage selection (table-driven), prompt composition (template fill), spawn/wait/advance, parks, fingerprints, budgets, event emission | reasoning across roles; reading artifact content beyond mechanical fields |
| author | agent session (per slice) | plan-validate, split, spec, revise, impl (dispatches implementer), conformance, fix, turnover | writing any prompt; editing project source directly (probes excepted); deciding Class U |
| reviewer | agent session (per slice) | split-check, precheck, postcheck — the independent floor | editing source; dispatching implementers; writing config/memory |
| implementer | author sub-agent | executing spec commit-units, committing | pushing; scope beyond spec; bypassing gates; reading anything the dispatch did not name — reviews, plans, turnovers, the store (a gap is NEEDS_CONTEXT, never a wider read) |

**Two parties act OUTSIDE every run**, and until 2026-09-04 neither was declared
here — the party that changes this tree acted throughout `operations.md` and was
named nowhere in this file's role model. Nothing spawns either, `agent.<role>`
resolves for neither, and neither can be reached through a topic.

| party | kind | owns | never does |
|---|---|---|---|
| owner | the human | Class U (semantic tradeoffs, scope/direction, irreversible or outward actions incl. push, ownership-boundary crossings, anything flagged "ask me"); the exemption judgment behind every WARN threshold, which is why those are visibility and not gates | ruling from session history or from any file the halt did not name — the zero-context-ruler standard (`review-standards.md` §11) |
| maintainer | a **cold** session outside every run — no lineage from any session of the topic it harvests (§7, owner-ruled) | workflow-source edits under `maintenance.md` §1; the harvest, including judging every open validation-debt row from the store while the topic tree is still readable; raising the maintenance brief | deciding what the owner decides; editing while a ferry runs a live stage; routing tree work through a delivery topic — `maintenance.md` §1 records why the SHA pin makes that impossible rather than merely unwise |

That row's `cold` is an owner ruling; its single home is **this file's** §7, with
the rest of the session model, and restating the reasoning here would be a second
thing to drift. The row cites two different §7s — this file's and
`operations.md`'s — and names them apart for that reason.

The pilot is **optional middleware**: full-auto's mechanical recovery never depends on it;
parks page the owner directly through the notify transport, and a dead pilot degrades to
that baseline (no supervision regress). The pilot's action set is exactly the `launch.sh`
verb set — it holds no private channel.

**Two-session property**: at every moment, author-lineage and reviewer-lineage
are separate; the reviewer re-derives from on-disk artifacts only. v2.0 additionally needs
no *simultaneously live* pair: the ferry mediates every handoff, so at most one stage session
is active per slice — v1's standing-watch/poll machinery (5 helper scripts, 2 gates, arm
markers, lockstep-restart races) has no object and is retired whole.

## 3. Naming

Style genes (from the locked role names): lowercase, plain English words, no abbreviations,
no metaphor extension, the directory is the namespace.

- **topic → slice → stage.** *slice* replaces v1's *phase*: slices are cut by function
  (vertical slices), may merge/re-split (`re-slice`), and may one day run in parallel — all
  of which "phase" (a time word) contradicts; it also removes the phase/stage double
  time-word nesting. A slice advances through stages.
- **Stage vocabulary** (locked + derived): topic-level `plan-validate, split, split-check,
  close-out`; slice-level `spec, precheck, revise, impl, postcheck, fix, turnover`.
  (The locked name `impl` is kept — not "build", which collides with the project's build.)
- **Artifacts**: spec, review (precheck.N.md / postcheck.N.md), conformance, handoff
  (a store record, not a file), charter, turnover, ruling, closeout.
- **Runtime scripts**: unprefixed, path-invoked (`ferry.sh`, `state.sh`…). Prefixes return
  only where a shared namespace forces them: tmux session names
  `delivery-<topic>-<slice>-<stage>`; the repo-claim lock `delivery.lock` (in the
  checkout's git dir, a namespace shared with git's own files).
- **State surfaces** (`.runtime/state/`): `run, stage, ledger, heartbeat, attempts, halt,
  sessions, handoff, progress, slices, decisions, rulings, observations, learnings,
  gates, notify, audit, lock` — plain nouns; `attempts` (fingerprints + budgets)
  replaces v1's electrical "breaker".
- **nonce** is kept (precise cryptographic vocabulary).

## 4. File layout

### 4.1 The workflow's own tree (this template; committed except `discussion/`)

```
delivery-workflow/
├── README.md
├── design/            # settled design (6 docs)                [long-lived]
├── discussion/        # ALL informal material    [gitignored, deletable as a unit]
├── runtime-docs/      # agent-read at run time                 [long-lived]
│   ├── cards/         #   pilot|author|reviewer.md              (hot, ≤300 each)
│   ├── protocol.md  review-standards.md  operations.md         (on-demand, ≤800)
│   │   maintenance.md   # operations.md §7, split out at cap; §7 stub remains
│   └── templates/     #   spec.md + review.md + prompts/<stage>.<cold|warm>.md
├── runtime-scripts/   # machine-run                            [long-lived]
│   ├── launch.sh                    # the ONE operator entry (verbs: §9)
│   ├── ferry.sh  watchdog.sh  monitor.sh  probe.sh   # driver-side processes
│   ├── derive_report.sh  derive_cost.sh              # read-only derivations
│   ├── session/   record.sh heartbeat.sh notify_event.sh emit_checks.sh  # hook-invoked
│   ├── lib/       state config owed gates gates_claims gates_commit notify  # sourced,
│   │              compose watch resume locks index attempt admission rulings # never run;
│   │              preflight readers report_routing plan_binds md_span      # (ferry halves,
│   │              platform (+ darwin-bin/: macOS stand-ins)                #   see below)
│   ├── backends/  pty_tmux.sh                 # the single structural adapter
│   └── transports/ bark.sh                    # the notify seam's adapters
├── config/            # declarations — data, read-only at run time   [long-lived]
│   ├── defaults.kv  schema.kv  stages.tsv  notify-presets.kv
│   ├── backends/  claude.kv  codex.kv       # measured 2026-08-17 (0.147.0)
│   └── profiles/  settings-hooks.json  codex.hooks.json  # harness hook wiring (enforcement anchor)
└── self-check/        # workflow-functional regression (dev-time, non-runtime)
    ├── check.sh  checks/  drill/  fixtures/    # drill/ = lib.sh + one file per
    │                                           # scenario family, so the runner
    │                                           # can run them concurrently
```

Organizing principles: top level splits by **nature** (README's five regions + `config` as a
sixth — declarations are machine-read like scripts but are data, edited at development time,
read-only at run time). Inside `runtime-scripts/` the split answers **"who runs this"**:
one human entry point, three driver processes, session-side tools the profile hooks call by
absolute path, sourced libraries, structural adapters. The ferry halves (`compose.sh`,
`watch.sh`, `resume.sh`, `locks.sh`, `index.sh`, `admission.sh`, `preflight.sh`,
`attempt.sh`) are a sanctioned pattern: concern-coherent, line-relief splits of
the one driver, sharing its globals under an honest header — the ≤800 cap's target is the
unreviewable monolith, and a half that states what it is stays reviewable without paying
for a contract nothing needs. Each half answers ONE question, and being able to name it
is the test that it is concern-coherent rather than a slice of leftovers: may we spawn
here and in what session mode (`admission`), is the world still the one this run started
against (`preflight`), may this assignment spend another attempt and what happens while
it does (`attempt`). What stays in `ferry.sh` is the part that cannot be named apart from
the driver itself — the transition table, `do_advance`, and the loop.

### 4.2 The topic tree (runtime output; never committed by the workflow)

```
plans/topics/<topic>/
├── plan.md                  # boundary artifact: plan workflow's output, delivery's input
├── <plan workflow's own region>/            # sibling workflow; not designed here
└── delivery/                # ← the delivery-workflow's entire world for this topic
    ├── project.kv           #   required project adapter (refuse to start without it)
    ├── config/              #   topic overrides: topic.kv, slice.<nn>.<agent>.kv
    ├── charters.md          #   split output (prose; machine index lives in the store)
    ├── slices/<nn>/         #   spec.md, precheck.N.md, conformance.md, postcheck.N.md,
    │                        #   ruling.N.md, turnover.md   (~6 files vs v1's ~11)
    ├── closeout.md          #   topic settlement: ledger snapshot, consolidation record
    └── .runtime/            #   machine state: state/ prompts/ logs/ tmp/   [gitignored]
```

Principles: the **two worlds are physically separate** — human/agent artifacts above,
machine state under `.runtime/` (regenerable, deletable, never hand-edited); **one slice =
one directory** whose listing is the complete review dossier in round order; short file
names because the path carries the context (v1's 76-character artifact names dissolve);
inputs at the root, products under `slices/`, state under `.runtime/`. The workspace, as the
ferry sees it, is exactly `plans/topics/<topic>/delivery/`. Rulings are the one deliberate
store→file double (machine record in the store, per-slice `ruling.N.md` archive for the DP
audit trail; one direction, no reconciliation). The delivery layer exists because a topic
directory is shared between sibling workflows — the path answers "whose file is this".

The project WORKTREE receives zero workflow files: the exclusive claim (topic path +
pid + starttime) lives at `<git-dir>/delivery.lock` — inside the checkout's git dir,
where it can neither dirty the status nor churn the content-bound acceptance
fingerprint on relaunch; `--absolute-git-dir` is per-worktree, so linked worktrees
claim independently. Two topics pointing at one checkout → the second refuses to
start, self-describing (parallel topics require separate checkouts/worktrees).
A topic that also declares a doc repo (`config-and-adapters.md` §3) claims **both**
checkouts at start, in the fixed global order code → doc, and releases both at
COMPLETE: a collision on either refuses the whole topic, and a fixed order is what
keeps two mixed topics from deadlocking on the pair. When the workspace itself lives
inside the doc checkout (the usual layout), preflight demands that path be
git-ignored there — an unignored workspace would make every store write dirty the
doc tree and churn its content-bound pins.
Both claims (host, repo) are liveness-judged, never leased: a stuck-alive holder
keeps its claim until an operator intervenes — the deliberate availability cost of
keeping mutual exclusion independent of wall clocks (the clock-jump amnesty's
counterpart; a lease would reopen the paused-holder hazard that liveness judgment
closes). Stale-claim takeover is a serialized critical section (judgment and
displacement together), so two candidates can never both win.

## 5. Topic flow

```
launch → preflight (deps, disk, project.kv present, repo locks, test notification)
      → startup reconcile (fence stale delivery-* sessions; never blanket-wipe)
plan-validate (author): plan-ready? ambiguity → HALT to owner. Validation scope =
      the sections split will bind; claims carry read-range stamps (no whole-plan claims).
      Also adjudicates the plan preamble's pinned SHA(s) once, at this boundary:
      pin→HEAD drift benign/blocking, blocking → not_ready; after the boundary the
      shared-branch discipline governs (`review-and-slices.md` §5).
split (author): slice charters + machine index (slices surface) + terminal decomposition
      table + footprints + risk classes + per-slice repo binding + plan-hash pin.
split-check (reviewer, independent): plan-ready ruling, slice granularity (8 criteria),
      footprint/interference declarations, charter↔index consistency. Also the return path
      for every later re-slice merge proposal (concurrence precedes execution).
slices, sequential (v2.0; declared-disjoint parallel is a v2.1 slot)
close-out (author): ledger settlement → closeout.md; history consolidation proposal
      (Class C; hard invariants in review-and-slices.md §8); push stays Class U.
```

Plan drift: the plan hash is pinned at split (plan content also feeds the attempt
fingerprint, covering the pre-split window); each slice start re-checks → mismatch =
`halt(plan_changed)`; the ruled resume repins and re-enters plan-validate (the earliest
stage the plan binds), demoting the interrupted slice to re-derive its premise.
Workflow-source drift: the workflow tree's git object is pinned at topic start — the
**subtree** object (`HEAD:<prefix>`) plus the subtree's dirty fingerprint, never the
repo's HEAD commit, so a sibling workflow sharing the checkout cannot park a topic over
work that never reaches it; each spawn re-checks → mismatch = `halt(workflow_changed)`.
The pin's promise is loud, deliberate
adoption — a deliberate relaunch adopts the current tree and repins, with the freeze
point audited; it is not a boundary gate (a topic frozen mid-slice can never reach a
boundary without resuming, and the old tree no longer exists to resume on — artifacts +
store + idempotent cold re-entry are what make adoption safe). WHEN to land workflow
changes is the maintenance rule: no live stage, self-check green (maintenance.md §1).

## 6. Slice flow and the transition table

```
spec → precheck → (revise → precheck)* → impl → postcheck → (fix → postcheck)* → turnover
```

The ferry's next-stage decision is a **table lookup**: `stages.tsv` maps
`(stage, verdict) → next` over closed vocabularies. Changing the flow = editing data.
Self-check proves the table total (every reachable (stage, verdict) pair has a successor;
no dangling states). Convergence guards that are not the table's job: the severity-trend
predicate (two consecutive rounds of a review loop — precheck↔revise or postcheck↔fix —
with non-decreasing substantive-finding count → `halt(disagreement)`, options
continue/split/redesign; both loops need it: fix-round evidence keeps every fix attempt
fingerprint-fresh, so the fix loop has no other convergence signal) and the attempt
fingerprints (§3 of `state-and-liveness.md`).

Stage artifacts and owed sets are specified in `stages.tsv` (static part) ⊕ the spec's
commit-unit list (dynamic part; trusted because precheck reviews it — the two-source
derivation is `lib/owed.sh`'s single code path).

## 7. Session model (owner-ruled)

**Two sessions per slice, slice-scoped, both closed at turnover.** Warm within the slice,
cold at the boundaries and wherever freshness is load-bearing:

| spawn | mode | rationale |
|---|---|---|
| spec (slice start) | **cold** | context reset point; drift capped to one slice |
| revise / impl / fix / turnover | warm (author session) | authoring context is the value; capacity bounded by slice budgets |
| precheck round 1 | **cold** | the independent first pass — freshness is its definition |
| precheck rounds ≥2 | warm (reviewer session) | verify-absorption is warm by design (v1 R2 semantics) |
| postcheck round 1 | **cold** | fresh eyes on the landed commits — the floor's defining property |
| postcheck delta rounds | warm (reviewer session) | verify-only |
| after death/park | cold | idempotent re-entry from artifacts + store |
| operator `all_cold=true` | cold | debugging / suspected drift |

Cold/warm is a **static column in stages.tsv** decided by the ferry — no agent ever declares
it, so v1's `warm_ok` authentication machinery has nothing to authenticate and is not
carried. Guards: reuse requires session-alive + `awaiting_input` signature + empty composer,
else cold-fallback (audited); prompts never assert their own spawn mode (freshness is
recorded by the session in its provenance); warm re-activation carries a fresh nonce; a held
(inactive) session is exempt from liveness monitoring until reused. Cold bootstrap is a
constant-shape positional argument ("Read and execute <abs-path>/stage_prompt.md") — no
injection timing window, no quoting surface; warm injection shares the nudge primitive
(`backend-seam.md` §4).

**The maintainer session is COLD too — and it is the one freshness rule no ferry
can decide** (owner ruling, 2026-09-04). The table above is a SPAWN table:
`stages.tsv`'s session column, read by the ferry, for sessions inside a run. The
maintainer is outside every run (§2), so nothing spawns it and nothing can
enforce this — and it is where the principle above bites hardest, not least.
It judges what a topic's own sessions left behind (the open validation-debt
rows, the learnings, the close-out report) and then changes this tree in
response; a session that authored those artifacts reads them as it MEANT them
rather than as they are, which is the same reason precheck and postcheck round 1
are cold. Concretely: a maintainer session carries no lineage from any session
of the topic it harvests, and re-derives from the on-disk artifacts and the
store exactly as a reviewer stage does. The separation is not new — the
close-out card already forbids the topic's author from writing into the workflow
tree and hands that to the maintainer's harvest — but a duty boundary says who
may WRITE, not who may have been; the ruling adds the lineage half.
The ruling does one thing and defers another, both said plainly. It is not
checkable — no program spawns a maintainer, so this is a discipline of
`maintenance.md` §1's class, checked the way that section is checked. And it does
not decide WHO may perform the against-reality reading: cold at the START of a
change is not cold at the end of it, since by the time the maintainer reads its
own edit it is that edit's author. That question is settled by change class in
`maintenance.md` §1, with `review-standards.md` §12's independence ceiling as the
reason the heavier classes cannot answer it from the same session.

Economics (v1-informed): v1 measured manager cold-onboarding (~4-5×/dispatch) as the
dominant reducible cost and built phase-scoped persistence with seven-witness session
authentication — plus a self-documented unsound boundary (manager-discretionary phase
publish). v2 removes the cost at the root instead: no 110KB sync monolith to re-read
(bounded manifests), an order of magnitude fewer stages (impl carries a whole slice), and
3 cold spawns per slice with everything else warm. The stage-driven boundary is exactly the
"derive the boundary from the artifact" fix v1 deferred.

## 8. Implementer spawn model (decided)

**The implementer is an author sub-agent. Single flow; capability-gated.** The author role
requires the backend capability `subagent` (all roadmap CLIs have it — claude/codex);
a backend without it cannot host the author (self-describing refusal, never a silent
fallback); there is no second flow.

- The floor never rested on implementer lineage: conformance is the author's own check by
  definition; postcheck is the independent floor — both unchanged.
- Dispatch: author writes the sub-agent prompt from the spec (intent in place), one
  commit-unit (or a declared group) per dispatch; receives **report only** (diff summary +
  SHAs + notes + status DONE/DONE_WITH_CONCERNS/NEEDS_CONTEXT/BLOCKED + E-n errata),
  never the transcript. Bounded author context. The dispatch is also the sub-agent's
  whole world — the spec, the anchors it names, `project.kv`. That read boundary
  (§2) is **stated, not mediated**: the sub-agent runs under the
  author's own `--permission-mode dontAsk --add-dir {workspace}`, so every review,
  turnover and store file is readable to it, and a rule delivered to nobody checks
  nothing. It lived in a `cards/implementer.md` no manifest ever handed over, which
  is why that card was retired rather than repaired. If it ever needs to be a
  control it belongs in the environment layer (a sub-agent tool allowlist), not in
  prose — deferred there on zero measured instances; the trigger is the first one.
- The dispatch text is an ARTIFACT: written to `slices/<nn>/dispatch.<n>.md` before it
  is sent, headed by the unit and the model/effort requested; impl owes at least one.
  The report is a hint and the diff is the authority, but the dispatch is the only
  record of what the implementer was asked, and the request for a model is checkable
  only where it is written down.
- Completion evidence is the repo: landed SHAs in the **progress ledger** (store surface,
  written per commit-unit as it lands) + the conformance record. The ferry's advance check
  resolves ledger SHAs against `git log` — no ferry-private marker (v1's `flag.impl_done`
  hole closed). The ledger triples as crash-recovery anchor, `commit.done` event source,
  and monitor progress feed.
- Conformance re-derives **diff-vs-spec** (never diff-vs-dispatch-prompt); the report is a
  hint, the diff is the authority. Never commit over a red gate; never leave a dirty tree
  silently. On BLOCKED, never re-dispatch unchanged (fingerprint enforces structurally).
- Mid-impl discovery beyond spec scope → stop, surface erratum, re-enter revise at the
  re-derived risk class; never widen in place.

## 9. Operator surface

`launch.sh` is the single entry: `launch` (preflight + init + watchdog + ferry),
`rule --slice NN [--topic]` (Class U return path: ruling into the rulings surface → archived to
`slices/<nn>/ruling.N.md`; the resume gate holds a ruling-gated halt until a ruling
addressed to its slice exists, and the resumed stage's manifest then carries it — so it
cannot respawn without one; `--topic` scopes a mechanism ruling to every slice's
manifest, and a session running when any ruling lands is refused at emit until it
acknowledges it — protocol §6), `stop` (graceful: park current stage, keep sessions for
postmortem), `ack` (acknowledge the current park: the watchdog's pager PAUSES re-paging for `notify.ack_timeout` and then resumes
it and the audit surface records that it was seen; nothing else changes —
config-and-adapters.md §5), `slice <id> <status>` (guarded index edits: cancel/restore — cancelled slices
are unschedulable by status; a restored slice re-derives its premise from scratch),
`status [--slices|--rounds]` (monitor --once; `--slices` prints the per-slice table and
`--rounds` the per-stage per-round clock from the ledger's own t= fields — separate small
readers over surfaces that already exist, because seventeen slices is a dump
and the live panel's layout is pinned), `notify <preset|event=on|off>` (the notification policy
surface, hot-read at emit — config-and-adapters.md §5), `observe --text` (append a
workflow-defect observation — the pilot's observation duty needs an operator write
path), `peek [role] [--follow|--attach]` (one pane per session, read-only:
capture-pane makes no client and cannot change geometry — the "look" half of the
look/type split, attach being the deliberate typing path; `--attach` prints the
attach command instead of capturing). Deferred verbs (build on demonstrated
need): `salvage`, `wait`.
Takeover etiquette and the manual floor (a human can play the ferry: all state and
artifacts are plain files) are `operations.md` content.

## 10. Parallelism

v2.0: topics parallel (fully isolated: own workspace, own store, own repo checkout — the
repo lock enforces exclusivity); within a topic, slices sequential. Within-topic parallel
is a designed slot (declared-disjoint footprints intersected mechanically, per-slice
worktrees, per-worktree gate-census re-derivation matched by finding set, project-adapter
`worktree_layout` declaration incl. the mirrored-root remedy) — not built until a real run
demands it (the slot is documented; admission rule (c)).

## 11. Monitor

Read-only observer (writes nothing, no capture-pane, no control channel): reads the store,
renders stage/elapsed/timeline/headroom/what-needs-you/watchdog-liveness/commit-progress.
v2.0 ships the terminal renderer only; the web variant (static page + stdlib file server,
assessed thin) is deferred — the assessment and the read-only boundary live in
`config-and-adapters.md` §6.

## 12. Settled rulings

Owner decisions recorded during the design round; each is settled and binding:

- **Agents write only artifacts; the ferry composes every prompt** from templates +
  manifests. This closes the author→reviewer premise-injection channel while meeting the
  unattended-start intent more strongly than agent-written prompts would.
  (Scope: *stage* prompts. The implementer dispatch prompt of §8 is the author's own
  spec-scoped delegation inside its own trust domain — no independence boundary is
  crossed, so it stays with the author.)
- **The codex/service backend family is deleted, not deferred.** v2 has exactly one
  structural adapter (pty_tmux); a new CLI joins as a pty declaration when actually
  adopted.
- **Caps are workflow defaults, overridable in either direction.** Function 200 / source
  800 / self-test 1000 / commit 500; project_context may loosen or tighten any of them.
- **Topic artifact caps are calibrated from real topics** (spec ≤2000, review ≤1500, plan
  uncapped — a successful 1101-line spec and a 7390-line plan are the calibration data);
  workflow doc caps (300/800) stay hard.
- **The unit vocabulary is topic → slice → stage.** "Phase" is retired (see §3).
- **A slice carries many commit-units** (spec-listed) — never one commit per unit of work.
- **Slice budgets are 2500 diff lines / 8 commit-units / 30 files** (owner-approved,
  evidence-anchored; high-risk targets half; per-commit-unit cap 500).
  `config/defaults.kv` and `review-and-slices.md` §6 carry the same numbers;
  self-check pins them together.
- **v2.0 runs slices sequentially; within-topic parallelism is a designed, deferred
  slot** (§10). Sequential execution is a ruling, not an omission — any earlier
  parallel-execution requirement is superseded; the slot is built only on
  demonstrated need from a real run, per the admission discipline.
- **The loop-detector fingerprint includes manifest-resolved input content** (see
  `state-and-liveness.md` §3) — an owner hand-edit to an input reads as novelty;
  the design formula was amended to match, rather than the implementation reverted.
- **Cap exceedance is an emit-time refusal, not a park** — removed from the park
  vocabulary under this section's own self-heal-first rule.
- **A fix stage owes fix-round evidence** — a progress record landed in that round,
  or a conformance.md change since fix entry; a zero-action fix cannot report built
  (doc-only dispositions stay legal and visible).
- **stage_timeout is a continuous-inactivity deadline** (default 30 min; per-stage
  overridable), with the nudge self-heal window tightened to ~10 min
  (`quiet_grace=420` + `nudge_grace=180`) on the strength of the classified-pane +
  heartbeat + CPU signal stack; revisit both against a live topic's ledger data.

Later-round rulings (each already embodied in the amended design text where cited;
recorded here so the registry stays the one place that answers "is this settled"):

- **workflow_changed recovery is loud deliberate adoption, not a boundary gate**
  (§5): a mid-slice freeze can never reach a boundary without resuming, and the
  old tree no longer exists to resume on; the maintenance rule governs WHEN to
  land changes.
- **plan_changed ruled resume re-enters plan-validate** — repin + demote the
  interrupted active slice to pending+rederive (§5; the plan binds the whole
  decomposition chain, and next_pending_slice would skip an 'active' row forever).
- **The attempt budget is per-(slice,stage,round)** (state doc §3): an attempt is
  a retry of the same work unit; rounds are bounded by the trend predicate and
  wall-clock.
- **observations/learnings are close-out manifest inputs** — a write-only surface
  is a landfill, not a learning loop; close-out is the loop's minimal reader.
- **SPEC_DIFF is deleted until a producer exists** (admission rule (c); revise
  overwrites spec.md, and warm precheck is verify-absorption, not diff review).
- **Preflight makes an advisory repo-lock check via the shared holder predicate**
  — a launch doomed to the ferry's refusal must fail before a probe session is
  spent; the ferry's take stays the authority.
- **push_gate is a terminal marker, not a gate**: after COMPLETE a relaunch
  re-sends an undelivered page and exits 0 idempotently; there is no stage to
  resume into and no reopen path (new work = new topic).
- **Lock wiring is proven by durable traces, not race fixtures** (audited takes +
  drill assertions; wall-clock-racing fixtures are the proven flake class).
- **The unused-but-deliberate template substitutions stay** ({nonce}/{NONCE}/
  {ATTEMPT} neutralization + {ROUND}): documented defenses, not dead code.
- **The repo claim lives at `<git-dir>/delivery.lock`** (§4.2): the worktree
  receives zero workflow files; a root lock dirtied checkouts and its
  relaunch-rewrite churned the content-bound acceptance fingerprint. The project
  repo must BE a git checkout (validated up front — the pipeline is git-shaped).
- **sig.shell_prompt is deleted**: the launch command is the pane command, so a
  dead CLI has no pane — pid/starttime liveness is the whole dead-detection
  truth; a pane-alive-CLI-dead state has no composer and parks unknown_screen.
  A wrapper-style backend would reintroduce it as its own declaration concern.
- **Ferry halves are a sanctioned pattern** (§4.1): concern-coherent line-relief
  splits under an honest header; the ≤800 cap targets unreviewable monoliths.
- **`launch` returns once the watchdog is up** (operations §1; README quickstart);
  `--attach` opts into the monitor exec — scripts must be able to compose the
  entry verb.
- **Impl close does not demand a clean worktree** (review doc §1): the acceptance
  record binds the exact repo state (sha + tree + content-bound dirty
  fingerprint); clean is recognizable as the constant empty-input hash.

First-principles / prior-art round rulings (each already embodied in the amended
text where cited; registered here so this stays the one settled-list):

- **Stale-claim takeover is a serialized critical section** (§4.2): judgment and
  displacement under one reclaim flock, liveness re-judged inside — two
  candidates can never both win; proven by deterministic contention fixtures,
  never wall-clock races (the earlier lock ruling's discipline unchanged).
- **The severity-trend predicate covers both review loops** (§6; state doc §3):
  precheck↔revise AND postcheck↔fix — fix-round evidence keeps fix attempts
  fingerprint-fresh, so the fix loop otherwise had no convergence signal and its
  only stop misnamed the cause; discharge keys are stage-scoped (rounds number
  per (slice, stage)).
- **The predicate reads the reviewer's new/repeat split, and an all-new loop is
  bounded by rounds** (review doc §1, §10): a non-decreasing count parks only when
  the newer round carries a `repeat`; the reviewer already makes that
  determination while verifying absorption, so it travels as a record field
  rather than as prose the ferry cannot read. Records without the split read as
  all-repeat — pre-field records keep their reading. `review.max_rounds` bounds
  the loop the split would otherwise leave to wallclock.
- **The store's crash-semantics boundary is stated, not implied** (state doc §1):
  process-crash atomicity is the load-bearing guarantee; system-crash residue =
  loud fault or a silent one-generation rollback absorbed by at-least-once
  recovery; fsync deliberately not paid.
- **no_novelty is a budget argument, not a proof** (state doc §3): sessions are
  non-deterministic — an identical retry is priced out, never proven futile.
- **Workflow adoption review includes interpretation stability** (maintenance.md §1):
  a new tree that changes how existing artifacts/records are interpreted needs
  its migration note before relaunch — "only affects future stages" holds only
  while past interpretation stands.
- **The headless negative space is recorded** (backend-seam §7): why screen
  driving over `-p`/SDK — wrapper-CLI constraint + takeover value; the seam
  keeps the migration path.
- **The nonce is named as the fencing-token equivalent** (state doc §2): it is
  what excludes a superseded session's in-flight emission — liveness judgment
  alone cannot.

Two-repo rulings (the doc repo as a second delivery target; each embodied in
the amended text where cited):

- **A slice binds to exactly ONE checkout, immutably per id**
  (`review-and-slices.md` §6, which carries the reasoning and the precedent):
  the binding rides the split grammar `id:risk:repo:title` into the index, and
  re-binding means minting a new id; cross-tree work is two slices with an
  interference order. This is where the previously unwritten one-topic-one-repo
  constraint became written.
- **That binding rule is enforced, not emergent**: one admissibility rule over
  the declared index, asked by each door into it (emit refuses so the author
  renumbers in session, ingest parks for records that never passed emit) — a
  dropped declaration would otherwise land the slice's work in the wrong
  checkout in silence.
- **A re-declared risk class is audited, not refused**: the index's risk field
  has no machine reader, and every review re-derives the class independently —
  so the only defect worth fixing there was the silence.
- **The doc repo has no acceptance concept** (owner ruling D-i,
  `config-and-adapters.md` §3): no `doc.<gate>` keys exist; a doc-bound slice's
  build/lint/test/acceptance record a **structural named SKIP** and the
  project's command — which measures the code tree — is never run there. The
  mechanical floor for such a slice is its spec's own per-slice checks.
  `doc.acceptance` is registered as a deferred slot, not a mechanism.
- **Both checkouts are claimed at topic start in the fixed order code → doc**
  (D-iii, §4.2) and released together at COMPLETE — one order truth
  (`project_repos`), shared by the takes, the release and the preflight
  advisory check.
- **One commit convention for both checkouts** (D-iv): `commit.*` is the
  project's, not the repo's — a doc commit-unit re-passes the same subject
  regex and trailer policy, so the doc checkout wires whatever commit hook the
  project does.
- **Evidence resolves through the binding, never a project default**: owed
  cu→SHA ancestry, gate attestation pins, the fix baseline and the progress
  registration wall all read the ACTIVE slice's checkout (two-layer resolution
  inside `_gates_repo`, so no gate signature carries a slice); artifact-path
  resolution falls back across the pair so cross-repo citations stay live.
- **General multi-repo is out of scope** (owner scoping ruling): the visible
  future is code + doc, so the binding vocabulary is closed at two — an N-repo
  adapter block buys nothing this pair does not.

Live-topic maintenance rulings (defects measured on a real run; each embodied
in the amended text where cited):

- **The Stop gate asks the caller's own debt, not the active attempt's**
  (`state-and-liveness.md` §2): the session NAME is baked into the hook
  command line at spawn and resolved to that session's nonce at gate time,
  so a session that already delivered its record ends freely however far the
  ferry has advanced; nameless callers still enforce globally (fail closed).
  A global gate pinned every session that lost the race with the ferry's
  stage-surface overwrite — the measured cost was warm reuse failing 5 of 6
  (a wedged session never reaches `awaiting_input`), authoring context lost
  to a cold impl, and one wedged session generating 3.9M tokens — and its
  block message instructed the wedged reviewer to emit the NEXT stage's
  record; emit's role binding refuses that impersonation from the other side.
- **Append loss is loud, and store integrity is proven at ferry start**
  (`state-and-liveness.md` §1): a failed append names its lost record on
  stderr (ledger additionally pages store_fault once per process), and
  `state_verify_all` hard-stops a launch over any corrupt surface with the
  reseal recipe — the silent-append-loss class (whole-surface rewrites keep
  working, so the pipeline looks healthy while its event history vanishes)
  is closed at both ends. The verify-at-open precedent is the industry's.
- **Delivery order is machine-carried: `after=` rides the split grammar**
  (`review-and-slices.md` §6): the scheduler takes the lowest pending id
  whose after set is out of the way; every after names a strictly earlier id
  (id order = delivery order, backward edges only — acyclic by construction,
  the migration-numbering discipline), the set joins the admissibility rule
  at both index doors (backward + resolvable + immutable per id), and
  pendings that can never schedule park instead of walking to close-out.
  Charter hard edges in prose alone caused a measured scheduling inversion;
  prose is machine-invisible by design, so the edge moved into the index.
- **A dirty workflow tree refuses at launch preflight** (operations §1): the
  preflight is the adoption door — a fresh topic pins the tree there and a
  relaunch repins through the resume gate — so uncommitted edits refuse
  before any watchdog spawns (the cargo-publish shape: don't ship
  uncommitted state), subtree-scoped like the pin. Complementary, not
  redundant, with the dirty pin: the pin catches dirt landing DURING a run
  at the next attempt; the preflight catches it before the run exists.
- **The wallclock budgets meter working time, never calendar time**
  (`state-and-liveness.md` §3): the resume gate credits each cleared halt's
  parked interval once, from the halt's own stamp, into `parked.<slice>` /
  `parked_total`; the budget checks and the monitor's runway rows subtract
  the same credit (one number, two readers). A park is the interval where
  the thrash these budgets price cannot happen — the CI precedent: job
  timers meter execution, not the queue. Absent credit keys read 0, so old
  records compare unchanged.
- **`observe` carries files** (operations §2): `--file` joins `rule`'s —
  observations usefully carry code, and shell quoting through `--text` ate a
  backticked word while append reported success (a silently wrong record is
  the store's own worst class, reached through the front door).
- **Behavior claims join the machine-checked table** (`review-standards.md`
  §2): "this code/test already does X" is a `behavior` row — path::symbol
  anchor + verified echo + rerun command — never a `note`; the checked/
  unchecked split had every checked class verified and the one unchecked
  class false, twice, through HIGH-confidence reviews. The rerun command
  puts the row under precheck's existing run-every-command duty.
- **A conformance stamp is fresh or it is refused** (`review-standards.md`
  §2): at impl/fix emit, a conformance line stamp identical to the spec's on
  a line the spec-baseline→HEAD diff displaced is a forwarded "@ HEAD
  re-read" (gates_stamp_freshness; baseline = the spec's own claims
  attestation sha; shifted-but-restamped passes, no baseline is a named
  SKIP). Suite sets derive from unit targets and reviewer diversity stays
  pure config, named at run init when absent — the same round's two
  guardrails that needed no new mechanism.
- **Three guardrails the reviewer/author cards owe, from measured near-misses**
  (`review-standards.md` §1, `cards/author.md`): a broken evidence command is
  **C, not wording**, even when the claim is true — truth of the claim decides
  A, usability of the re-derivation decides C, and the same defect was graded
  both ways one slice apart. A conformance count asserting currency ("412
  lines at HEAD") owes the command that produced it — the stamp axis sees
  `path:NN` and never saw this second shape of the same forwarding. And a
  sub-agent dispatch that returns instantly is a FAILED dispatch, never an
  empty one: measured twice, unnoticed, after which the author absorbed the
  unit and the never-edit-source boundary silently stopped existing.
- **A claims cell names a piped command; it cannot hold one**
  (`review-standards.md` §2): a `|` inside a table cell splits the row — for
  every renderer and for the emit gate's own `awk -F'|'` — so the recorded
  command truncated at the pipe and the gate accepted a shell fragment as
  evidence, while a reviewer copying the cell ran something else. Escaping
  addresses the render alone: `\|` is a literal pipe to ERE and an escaped
  pipe to a shell, and §2's own occurrence rule prescribes `grep -o … | wc -l`
  — the format forbade what the contract required. Such a command moves to a
  fenced block as `E<n>: <command>` and the cell names it, the shape Markdown
  itself uses for payloads that do not belong inline; the gate refuses both a
  split row and a label that resolves nowhere. Pipe-free commands stay inline:
  the indirection is for what the format cannot carry, not a ceremony. Three
  measured anchors, each an evidence command nobody could re-run as written.
- **The topic scope is priced by the topic clock** (`state-and-liveness.md`
  §3): id 00 is exempt from the per-slice wall-clock budget, because its
  `started` stamp is the topic's own — its stages bracket the entire
  delivery — so the slice cap was pricing the whole topic. Measured at
  close-out re-entry: 128394s of "working" whose every hour belonged to
  slices 09..15, parking a stage that had just begun. Two clocks measuring
  one interval under different caps is the tell that one is the wrong
  instrument; the span stays priced by the one that owns it.
- **The CLI's own questions are declarable, and the scratch name is fenced**
  (`backend-seam.md` §2): the self-update prompt joins the modal allowlist
  (act = the prompt's own `[Y/n]` default) and the probe fences a leftover
  scratch session before spawning. Three anchors, one topic: a probe whose
  every capability missed while the refusal blamed the declaration, a stage
  parked `unknown_screen` over a question, and a launch hung past four
  minutes — plus the orphan the killed launch left behind on a fixed name.
  Nothing was broken in any of them; a question was unmodelled.
- **A config fault is not an absent key** (`config-and-adapters.md` §1): the
  store has held that line since v2.0; config had not, because the driver
  reads every key inside a command substitution and dying there kills the
  subshell while the parent keeps an empty string. The fault now travels as
  a status and all ten call sites answer it. Found while building an
  unrelated fixture, which is the honest provenance: a violated cross-key
  invariant produced an empty budget and a `budget_wallclock` park quoting
  "1s working > s" — the wrong cause, stated confidently.
- **Capability and availability are different questions** (`backend-seam.md`
  §2): the probe cache key stays what it was — it answers whether a
  declaration's promises can be made facts, and quota is a property of none
  of its keys — but the stored result steps aside while a `backend_quota`
  halt stands unresolved, and a live probe that meets a quota-dead pane
  refuses with its own exit code rather than burning its timeout and blaming
  the declaration. Reset times differ per CLI, so the workflow computes none:
  the pane's own line rides into the refusal, into the park detail, and into
  the notification built from it.
- **A wedged session is visible from three sides now** (`state-and-liveness.md`
  §5): the CPU extension gained a rate floor, repeated Stop-gate blocks fail the
  attempt, and a declared quota signature parks instead of respawning. One
  measured event chain cost ~6h and a day's backend quota, and each layer alone
  would have missed it: the idle CLI's few percent of a core read as work on
  every poll (so the inactivity clock, the nudge and the working episode were
  all reset, leaving only the 3h ceiling); the gate correctly blocked nine times
  before the CLI's own cap overrode it, and none of that could reach the ferry;
  and the backend had been out of quota since an earlier attempt drained it,
  which nothing in the workflow could see. The order matters as much as the
  three: while the CPU test answered yes forever the loop never reached
  classification at all, so the other two would have been unreachable.
- **The pin is the subtree object, not the repo's HEAD** (§5): `HEAD:<prefix>`
  answers the question the pin actually asks — did the tree these sessions
  EXECUTE change — while `git -C` walking to the toplevel had it answer a
  wider one. Measured on the dogfood topic: of ten `workflow_changed` parks,
  six compared pin-to-pin identical delivery-workflow subtrees, all six after
  a sibling workflow in the same checkout began daily development (111
  commits in one such day). The dirty term was already subtree-scoped; the
  committed term now agrees with it. A pin stored before this change is a
  commit sha and will not equal a subtree sha, so an old topic's first resume
  parks once and repins — the designed adoption path, loud not silent.
- **The workflow's own ids stop at the repo boundary**
  (`config-and-adapters.md` §3): a commit message naming `cu-N`, `DP-N`, a
  slice id or a path under the topic tree is refused at both doors the SHA
  passes — registration and emit. Ids the workflow does not mint but HANDS
  OVER (a plan's `R10-2`, its flip-gate labels) are judged by lookup, never
  by shape: an anchor-shaped token is only a candidate, and the verdict is
  whether this topic's own planning artifacts name it. Enumerating shapes is
  precisely what failed — the project's own gate listed `R1-` and `R6x-` and
  `R10-2` walked through the gap — so `SHA-1`, `UTF-8`, `RFC-2119` pass with
  no allowlist to maintain. Measured: 4 of 4 real instances caught, 0 hits
  across the project's 1045 non-merge messages. The delivered history outlives the
  workspace those ids live in, so there they point at nothing; the unit→SHA
  mapping is the workflow's own record and already kept there. The ruling
  that the checkout receives zero workflow FILES had left the message as the
  one door the bookkeeping still crossed, and the authoring session meets
  these ids in every prompt it is handed. Measured: four commits of one
  topic carried them, one in the subject line. Two precedents, one per
  half: the kernel's submitting-patches rule that a message must stand on
  its own years later without external resources (an id whose registry is
  a deleted workspace never can), and reproducible-builds' build-path
  class — the producing environment's private coordinates baked into the
  shipped artifact, invisible to the producer, unresolvable to everyone
  after, and fixed by stripping them AT the boundary rather than by asking
  builders to remember. Complementary to the
  project's own conventions, never a restatement: those stay in the
  project's `coding_rules=` file, now load-bearing — a declared path
  resolves or preflight refuses, and impl/fix are handed the file — because
  a driver that restates a project's prose rules owns rules it cannot keep
  current, and its gate silently becomes the project's only opinion.
