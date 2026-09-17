# migration, self-check, acceptance map

> Settles the migration from v1 (document set, carry/retire ledger, runbook), the
> self-check suite, and the acceptance map. This file is self-contained (no references
> into `discussion/` — deletable region). NOTE: §3 (self-check discipline) and
> §6 (the behavior contract mapping every guaranteed behavior to its covering
> check/drill row) are LIVING references, not one-time migration material —
> a maintainer changing any mechanism starts at §6.

## 1. Document set (24 → 8)

Runtime docs, with v1's redundancy clusters folded:

| v2 doc | size class | absorbs (v1) |
|---|---|---|
| cards/pilot.md · author.md · reviewer.md | hot ≤300 each | MANAGER/SUPERVISOR/PILOT cards + OPERATOR_PROMPTS role fragments |
| protocol.md | ≤800 | LIFECYCLE + HANDOFF_PROTOCOL + ROLES boundaries |
| review-standards.md | ≤800 | REVIEW_PROTOCOL + REVIEW_INDEPENDENCE + DRAFT_CONVERGENCE + ANTI_BIAS + TIERING + DECISION_AUTONOMY essence |
| operations.md | ≤800 | AUTOMATION + RUNTIME + SESSION_RESTART operational content + HISTORY_CONSOLIDATION recipe |
| maintenance.md | ≤800 | maintenance rules — split out of operations.md §7 when that file reached the reference-doc cap `60-gates`' own-tree sweep holds these files to (NOT `cap.source_file`, which is a topic gate over a workspace's files); a §7 stub keeps the old citations resolving |
| templates/ (spec.md + review.md + prompts/) | per-file small | BRIEF_AUTHORING structure + OPERATOR_PROMPTS skeletons |
| README.md (entry) | ≤300 | README + QUICKSTART + GLOSSARY |

"Always-loaded" means: the role card is the first required item of every stage prompt
manifest — no other magic. Cold-anchor reads are bounded (required manifest entries ≤8
per stage; optional entries ride above that).

## 2. Carry / retire ledger

**Lifted (mechanism or rule, with source):** freshness nonce + Stop-gate completion ·
evidence-transcript discipline (as harness-attested gate records + claims tables) ·
exit-code watchdog classification · CPU-liveness extension + silent≠dead · tmux pitfalls
(-l / =-prefix / dual-pid) + trust-modal handling (as declared signatures) · Class A/C/U +
DP audit + veto · decomposition quality criteria + R0-concurrence (as split-check) ·
severity taxonomies (MF/NH → substantive/wording; R-Q) · anti-bias essence (3 checklist
lines + R-Q rule) · anchor-pair promotion + structural>script>prose · consolidation hard
invariants + cherry-pick recipe · salvage/retraction concepts (as launch verbs; salvage
deferred) · observation channel (as store surface) · known-bad-first + two-direction
non-vacuity · loaded-baseline doctrine + WARN-first landing + validation-debt row ·
derive-never-hand-predict + environment-reference sweep · state-conditional templates ·
batching co-pending U questions · "authority is the record, never the summary line".

**Rewritten from scratch:** the driver (3,089-line host → table-driven ferry ≤800/file) ·
state (26 families/6 writers → one store) · backend seam (11-function ABI + name switches →
declarations + one adapter) · notification policy (~22 inline sites → event vocabulary +
policy surface) · breaker (counters → novelty fingerprints + budgets) · prompts
(agent-authored → ferry-templated) · session model (persistent+warm-auth → slice-scoped
cold/warm static table).

**Retired, with the structural reason:** standing-watch machinery — 5 scripts, W-9/W-10,
arm markers, lockstep races (no simultaneously-live sessions to coordinate) ·
`transport_pending` + review-first/handback-last write-order discipline (ferry mediates;
records are atomic) · warm_ok authentication (no agent declares warmth) · Trivial-skip +
combined-review + all three ack file families (nothing is skipped; the eligibility
machinery cost more than the skipped review) · sibling-family review (slice granularity
removes the seven-sibling shape upstream) · M1–M9 ceremony + patch-artifact form + .patch
artifacts (commits are the truth; probe window survives) · per-sub-commit phase publishing
+ seven-witness session auth (stage-driven boundaries are structural) · sync-state monolith
(store + slices index) · W/G dual gate families (one gates.sh) · early-recovery probes
`completion_miss`/`artifact_complete` (the Stop-gate record contract makes their trigger
impossible; `dead_probe`/
`first_activity` fold into the liveness stack) · dual-numbered check families + 27
selftests (re-derived set, §4) · codex service containment stack (owner ruling).

**Migration runbook:** no mid-topic migration. v1 finishes its live topics and is then
frozen; new topics start on v2. The v1 tree stays untracked until frozen (then one
historical snapshot commit, owner-gated). Nothing in v2 writes into the v1 tree.

## 3. Self-check (`self-check/`, non-runtime)

Runs when the workflow's own source changes (dev-time), plus before any resume that
follows a maintenance hold. Order: **the platform layer first** (every later check stands on its
answers), then **store checks** (everything else's fixtures stand on it), then config closure, then mechanisms, then the drill.

- **Two-direction non-vacuity everywhere**: known-bad fires, known-good passes; every
  check asserts its fixture precondition (the gate saw N>0 candidates) so a broken fixture
  cannot read as a pass — the vacuous-gate hazard, mechanically excluded.
- **known-bad-first** for fixes: the regression fixture shows red on the defect before the
  fix greens it; new guards get a wrong-logic injection per asserted direction. Proving the
  defect was real is not proving the rule is pinned — a finished mechanism additionally owes
  the closing verification its class calls for (`review-standards.md` §13: consumer sweep,
  contract re-read, property×mutation, fixture discriminability, exhaustive injection).
- **Config closure**: stages.tsv total over (stage, verdict); owed columns reference
  declared artifacts; schema covers every key the scripts read; backend declarations
  complete per capability schema; postcheck row cold; template render against fixture
  context leaves no unresolved placeholder; manifest required-items exist per stage.
- **Drill** (`drill/` + mock-cli.sh): a scripted fake CLI paints declared signatures into
  a real tmux pane; the ferry runs against it through the behavior-contract rows (§6) —
  each row asserts the behavior AND its perturbation flips. v2.0 core rows:
  DONE-no-handoff → first-miss park with no identical respawn; fingerprint (interleaved
  success doesn't clear; owed-delta spawns freely); CPU-busy extends with independent
  timeout literals; liveness classification incl. composer-non-empty refusal,
  unknown-screen park, nonce reject, transition-table walk of one full slice, rulings
  round-trip.
- **Maintenance rules** (rule-level; the AUTHORITY is `maintenance.md` §1 and this
  is a pointer, not a second statement of it — moved verbatim out of
  `operations.md` §7): workflow-source ADOPTION only while
  no ferry runs a live stage — authoring is concurrent, since both terms of
  `workflow_sha` are scoped to `$WROOT` and a worktree on another branch moves
  neither, and the older phrasing "changes only while no ferry runs" cost a
  pilot a whole run of defects it thought it could not act on; full self-check green before resume; loadavg recorded, the
  loaded machine is the operating baseline, a red is diagnosed never re-run-to-green
  (campaigns span both conditions and say so); new FAIL-severity checks land as WARN while
  any ferry is live; fixes unexercised by live traffic get a validation-debt row
  (`self-check/validation-debt.md`) closed only on firing evidence.

## 4. The v2 check set, derived by harm (embedded; a fraction of v1's ~105)

| harm (must not happen) | v2 checks (home) |
|---|---|
| finish without handoff / silent drop | record schema + nonce + Stop hook; owed single-list at emit + advance + park (3) |
| lost work from false-kill of silent work | heartbeat, CPU extension, working-age ceiling, pane classification (4) |
| invisible loops / runaway retry | fingerprint history, owed-delta rule, attempt + wallclock budgets (3) |
| author blind spots surviving | independent precheck + postcheck, cold rows enforced, reviewer-effort floor (3) |
| auto-mode deciding the owner's core | class routing + halt set + rulings round-trip + DP audit sweep (2) |
| state drift / split-brain | store gen+checksum, writer classes, fault≠absent, lock + starttime (4) |
| two drivers on one workspace/repo | host lock, repo lock (2) |
| wrong session injected / fused input | exact-target + charset, composer-empty precondition, injection state machine (3) |
| bad prompts poisoning stages | manifest required-check, template render check, prompt from templates only (2) |
| stale decomposition / moved ground | plan-hash pin, workflow-SHA pin, baseline resolution + attribution check (3) |
| oversized artifacts / caps | effective-caps gate + named exceedance (1) |
| citation rot / fragment conclusions | resolver (durable anchors + echo), claims-table range stamps, env sweep (3) |
| notification lifeline dark | config'd cmd + preflight test notification + notified flag (2) |
| config typo silently changing behavior | schema closure + unknown-key fault + cross-file integrity (2) |

37 checks (as of the migration round; the runner's own summary is the current count). Each self-check tests both directions of one row; the drill exercises the
driver-visible subset end-to-end.

## 5. Deferred slots (admission rule (c): built only on demonstrated need)

Within-topic parallel slices (designed slot in architecture §10) · warm beyond the static
table (already minimal) · **web monitor** (owner-ruled deferred: the slot opens on the
first REAL two-topic parallel run — all seven delivery topics to date have strictly serial
ledger windows, measured — or on an explicit owner want, e.g. a reachable remote entry
point; when it opens, the first form is thinner than the full design: server + rail, the
depth stays CLI) · notify dedup window · `salvage`/`wait` verbs ·
codex declaration · pre-push guard · mirrored-root recipe · learning aggregation tooling ·
maintenance-window tooling (W-phase/W-final/W-now stay rules) · **plan-directory
direct-read** (the boundary stays the single concatenated `<topic>/plan.md — owner-ruled
2026-08-19: the planning side's working form goes directory-shaped and promotes by
deterministic concatenation, so this workflow's five consumer families stay byte-stable;
the slot opens only if the first boundary flight shows real pain — agent
navigation cost of a large single plan, or citation rot — at which point the five families
get an adapter key instead of the hard-coded `<ws>/../plan.md`. **navigation cost
measured** — a live topic's 987 KB plan handed whole to 25 cold
spec/turnover/split sessions, the slice's own items 3–4 % of it — and answered
INSIDE the boundary (owner-ruled): compose derives a per-slice excerpt
(`plan_slice`) by the planning side's concatenation contract, resolving the plan
through the same arm as every other consumer, so the slot still opens only on the
rename/directory pain).

## 6. Behavior contract

One row per guaranteed behavior: what is given → what must hold, and the self-check
check (`self-check/checks/`) or drill row (`self-check/drill/drill.sh`) that covers it.
Rows whose evidence can only come from live traffic cite their
`self-check/validation-debt.md` entry instead — the contract stays honest about what is
proven versus promised.

| behavior | given → must | covered by |
|---|---|---|
| no-identical-retry | a parked stage, unchanged prompt body + owed artifacts + manifest inputs + failure class → `park(no_novelty)`, never an identical respawn; an unrelated success clears nothing; machine-written observation streams (ledger/gates) never feed the fingerprint; a deliberate relaunch is a redrive — it clears the parked (slice,stage)'s count + fingerprint history (parks are deliberate exits the watchdog never restarts, so only a human can redrive) | 70-fingerprint; 45-halt (redrive); drill S3 |
| owed-delta-spawns-freely | owed-artifact content changed since the last attempt → the respawn is novel and allowed; incidental file churn counts as nothing | 70-fingerprint |
| idle-noise-is-not-work | a CPU delta below `cpu_busy_pct` of one core over the sampled span → NOT activity: the loop falls through to classification, so the nudge window and stage_timeout stay reachable; a delta at or above it still extends past stage_timeout to the ceiling, intermittently too | 75-watch (below-floor trickle ends before the ceiling; the two above-floor directions unchanged) |
| wedged-attempt-fails | `stop_gate_blocks_max` Stop-gate refusals recorded for the ACTIVE nonce → `FAIL wedged` (bounded respawn, not a park); blocks carrying another nonce never fail this attempt; each refusal appends its own nonce-scoped audit line | 50-record (the line lands, nonce-scoped); 75-watch (fires at the threshold, and the other-nonce control does not) |
| cli-questions-are-declared | the CLI's self-update prompt (either question-mark width) → `modal.self_update`, answered with its declared act instead of hanging a probe or parking a stage; a leftover scratch session under the probe's fixed name → fenced and NAMED before the spawn, never collided with; unmatched modals still park loudly | 80-pty (both widths classify, the act is declared); drill S9f (orphan fenced, probe still passes) |
| probe-answers-capability-only | a stored probe pass while an unresolved AVAILABILITY halt stands — `backend_quota` **or** `backend_overloaded`, the class and not one literal → the cache steps aside and the backend is re-proven live; a live probe meeting a quota-dead pane exits 4 (never 1) with `result=backend_quota` recorded (never `pass`, never `fail`) and the pane's own reset line forwarded verbatim; a live probe meeting a 529-overloaded pane does the same with `result=backend_overloaded` and *relaunch on judgment, not on a clock* instead of a reset time; a resolved halt returns the cache to service | drill S9d (quota probe: rc, wording, verbatim reset time, recorded result); S9d/1b (overload probe: the same four, and the advice that must differ); S9d/2 (bypass on both reasons, live re-pass, restore) |
| quota-dead-parks | an EMPTY composer over a frame matching the backend's declared `sig.quota_exhausted` → `park(backend_quota)`, never a respawn, with that pane line forwarded verbatim into the halt detail (reset times differ per CLI; none is computed or defaulted) and the screen attached; the same line while the CLI is working stays `working`; a declaration without the key classifies as before | 80-pty (live pane text classifies; the working control does not); 75-watch (the park); drill S9e (the reset time reaches the halt detail, one spawn only) |
| overloaded-backend-parks | an EMPTY composer over a frame matching the backend's declared `sig.backend_overloaded` → `park(backend_overloaded)`, never a respawn and never a nudge, with that pane line forwarded verbatim and the park text stating that NO reset time is published (the one thing that must differ from a quota park, since the two need opposite operator actions); read AFTER quota where a frame carries both, because only quota names a time; the same banner while the CLI is working stays `working`; the stop-gate counter consults it before `FAIL wedged`; a declaration without the key classifies as before | 80-pty (the measured banner unwrapped and line-wrapped, the working control, the both-statements precedence); 75-watch (the park, its verbatim line, its no-clock sentence, and the wedge-branch consult); 45-halt (the inline re-probe writes the matching park, both directions off the probe record); VD-50 (the live encounter and the signature's own wording) |
| retrying-backend-is-not-idle | a pane classified `error_retryable` → NOT nudged (injection into a mid-backoff client cannot help, and its rc then lands beside an unrelated failure) and NOT spending the idle budget: its own `liveness.retry_grace` bounds the episode, `stage_timeout` still bounds it from outside, and the failure names the cause (`FAIL backend_retrying`, never `idle`); any real activity — heartbeat, CPU delta, or a return to `working` — starts a fresh episode | 75-watch (the named failure, the unmoved nudge count, and the wait inside the grace); VD-51 (the live ladder and the grace's calibration) |
| busy-but-silent-extends | stage_timeout is a continuous-inactivity deadline: heartbeat/CPU activity resets it, intermittent pauses below it never kill, unbroken silence past it does; hard_ceiling alone caps total duration | 75-watch (three directions); validation-debt (live arms) |
| fix-round-evidence | a fix DONE record → a progress record landed in that fix round, or conformance.md changed since fix entry; a zero-action fix cannot report built | 50-record |
| config-fault-is-not-absent | a config resolver FAULT reached through the ferry's `cfg` → the ferry stops at every call site naming the fault, and no budget, backend, model, effort or mode is ever derived from the empty string a subshell death leaves behind. WHICH stop follows from where the read sits: inside a stage it is `park(template_error)` — a `topic.kv` / `slice.<nn>.<agent>.kv` defect is a workflow/topic INPUT defect, so the halt names the key, pages, and resumes on a relaunch after the fix; at run init (before any stage exists, so there is nothing to park on and nothing to resume into) it is a self-describing refusal, same rc 20, no halt written. `store_fault` keeps its own meaning and its own sentence: the store is checksummed, a fault there is corruption, and answering an operator's typo under that banner named the wrong subsystem and spent the watchdog's relaunch budget on a config that cannot resolve | 20-config (check_budgets on a faulted config: rc 20, halt reason `template_error`, the faulted key named in the detail, no `STORE FAULT` banner, no wallclock verdict invented; the run-init read refuses instead, writing no halt); drill S11 (a slice override with an unknown key parks before any spawn, end to end) |
| store-fault-is-not-absent | a corrupt store surface → readers take the fault path (distinct rc), never read it as zero/absent | 10-store |
| append-loss-is-loud | an append onto a corrupt surface → the lost record is named on stderr (`state_audit` stays best-effort for its caller; the ferry's ledger additionally pages `store_fault` once per process), and the next ferry start verifies EVERY headed surface before its first store write, dying `store_fault` with each broken surface + the reseal recipe (*.rot segments and the lock dir are not surfaces) | 10-store (sweep both directions, audit loudness); 45-halt (ledger loudness, one page, startup gate + wiring trace) |
| delivery-order-scheduled | a pending slice carrying `after=` → it never schedules while any named id is pending/active/missing; the scheduler takes the lowest UNBLOCKED pending; every after names a strictly earlier id that resolves (this declaration or the standing index) and is immutable per id — refused at emit, parked at ingest; pendings that can never schedule park `stall_record` instead of walking to close-out | 20-config (after grammar/direction/resolution/immutability, both directions); 42-index (scheduling order incl. superseded/cancelled-satisfy + missing-blocks, ingest carriage, both-door parks, advance-guard park); 50-record (emit refusal + record carriage) |
| preflight-clean-tree | uncommitted changes under the workflow subtree at launch → self-describing refusal before any watchdog spawns (commit or stash first); dirt OUTSIDE the subtree never refuses; a non-git tree stays the named no-git degradation; the run_attempt dirty pin backstops drift landing only after a stage is live | 35-verbs (shadow tree: tracked + untracked dirt refuse, clean + outside-subtree controls pass); 45-halt (the pin half, unchanged) |
| topic-scope-not-slice-capped | an active scope of 00 (the topic's own stages) → the per-slice wall-clock budget does not apply, however old `slice.00.started` is; a real slice with the same ancient stamp still parks, and 00 still parks once the TOPIC budget is the one exceeded | 20-config (all three directions on check_budgets) |
| wallclock-meters-work | a halt cleared at resume → its parked interval (halt's own t stamp) is credited ONCE to attempts `parked.<slice>` + run `parked_total` (push_gate credits nothing; a re-resume adds nothing); `check_budgets` and the monitor's slice/topic runway rows subtract the same credit; absent keys read 0 (no migration) | 45-halt (credit on mechanical + ruled resumes, no-double-count, push_gate null, budget subtraction both directions); 55-monitor (park-credited clocks, pre-credit rows byte-identical) |
| observe-carries-files | `launch.sh observe --file F` → the file's text lands in the observations surface byte-intact (backticks, `$()` un-mangled); an absent file refuses naming it | 35-verbs (both directions) |
| evidence-commands-rerunnable | a claims row whose cell carries a `\|` (escaped or not — the split does not care) → refused, naming the mechanism and the evidence block; a cell naming `E<n>` with no matching `E<n>: <command>` line → refused as a dangling reference; the same table passes once the block defines it, pipes and all | 60-gates (split row fires, dangling label fires, defined label passes) |
| behavior-claims-checked | a claims-table `behavior` row → path::symbol anchor resolves with a verified echo AND a rerun command is present, or the emit refuses; heading/absent anchors, missing echo, missing command and dead symbols all fire | 60-gates (five directions + the good row) |
| currency-claims-carry-their-command | a conformance line asserting a COUNT at HEAD ("N lines/hits/matches … at HEAD") with no inline `$ …` and no named `E<n>` → refused; the same sentence with either passes; prose claiming currency without a count, and a count that claims no currency, are both untouched (no false refusal) | 60-gates (fire + inline pass + named pass + two null controls) |
| conformance-stamps-fresh | an impl/fix emit whose conformance carries a spec-identical `path:NN` stamp on a line the spec-baseline→HEAD diff displaced → refused, naming the number an @HEAD re-read prints; restamped, above-shift and fenced stamps pass; no spec attestation → named SKIP | 60-gates (fire + three pass controls + SKIP + emit wiring trace) |
| workflow-ids-stay-out-of-history | a commit message naming `cu-N`, `DP-N`, `slice NN`/`slices/NN` or a path under the topic tree → refused at registration (`record.sh progress`) and again at the emit-time commit gate, naming each token; an anchor-shaped token (`R10-2`) → refused only when this topic's own planning artifacts (plan / charter / spec) name it too, so domain words of the same shape pass without an allowlist; a planning artifact the lookup cannot read NARROWS it, so the narrowing is named on stderr where it could change the verdict (candidates in hand, plan absent → one line saying what was judged without; no candidates → nothing said); project-side conventions are NOT restated here (a declared `coding_rules=` resolves under `repo=` or preflight refuses, and impl/fix are handed the file); the two axes are merged before the derivation returns, so the ONE sentence the refused reader gets names a class true of both — never one axis's name, which is how a refusal came to tell a plan-handed id it was "workflow-internal", resolvable "inside the topic workspace", and fixable through the cu→SHA mapping, three clauses false at once | 50-record (registration door, BOTH axes and both directions: a minted id and a plan-handed anchor each refused at the tip, the anchor's twin registering once the plan no longer names it); 60-gates (emit door: each minted shape fires, clean messages pass, and the SAME anchor message fires or passes by the plan alone); both doors assert the class name against the handed-over axis, which is what the wrong one survived the absence of; 20-config (coding_rules resolution both directions) |
| message-convention-asked-at-both-doors | the project's subject regex, its required and forbidden trailers and the workflow-id axis are ONE derivation (`_gates_message_fails`) asked at registration (`record.sh progress`) and again at the emit gate. Registration BLOCKS only while the fix is local: a non-conforming message on the TIP is refused before it enters the ledger (one amend clears it); the same failure on a commit already buried is RECORDED, named loudly on stderr and in the audit surface, and left to the emit gate — a wall there would strand the ledger record of a commit that really did land, and an unregistered unit makes emit report a missing cu record instead of the real cause. A conforming message registers untouched. The diff cap is asked at emit ONLY, for the same reason | 50-record (tip refused; buried recorded + warned + audited + the record present; subject regex and forbidden trailer at the tip; conforming control registers; over-cap commit still registers); 60-gates (emit door, both directions, unchanged) |
| fix-advice-matches-the-commit-position | any message-class failure of the commit gate (subject regex, missing or forbidden trailer, workflow id) → exactly ONE fix line, computed rather than assumed. An amend reaches only HEAD and only the DELIVERED branch ships, so the ref disagreements are answered first: HEAD detached (even AT the tip, where a sha comparison sees nothing) or the checkout sitting on another branch → that is the fix, with no claim about position. Otherwise position decides: the tip → amend + re-register; buried → named as the branch rewrite it really is, with the count of commits above it and the erratum route, never "amend"; unreachable → the branch carrying it is not the one checked out. The registration door prints the same computed line. A diff over cap carries no fix line (re-split, never reworded) | 60-gates (tip, buried, unreachable, detached-at-tip, other-branch, and the cap-only control); 50-record (registration door) |
| same-model-ceiling-named | a run whose reviewer backend+model equal the author's → one audit line at run init naming the ceiling; a diverse deployment audits nothing | 45-halt (both directions) |
| refine-owed-by-schema | an author-role stage record → `refine.rounds` with per-round findings is owed; offload to the reviewer is a flagged anti-pattern | 50-record |
| harness-contract-is-not-copied | the workflow's own hook commands (`PreToolUse → heartbeat.sh`, `Stop → record.sh stop-gate`) live in profile files that are the settings-JSON SHAPE, not a brand — `settings-hooks.json` is named for what it is and carries no backend-specific content, claude.kv points at it BY CONSTRUCTION, and codex.hooks.json carries the same commands verbatim in codex's own shape → every hook event declared by MORE THAN ONE profile must carry byte-identical commands; an event only one declares is a deliberate asymmetry (codex has no Notification hook) and is untouched. A split is licensed by a real divergence, named — never by copying | 30-closure (the real tree agrees across its 2 shared events; the Notification asymmetry control; a fabricated profile with a diverged `PreToolUse` command is flagged naming the event and both sides; preconditions on profile count, extracted commands and shared-event count so the comparison cannot go vacuous) |
| assignment-is-recorded | a spawn → the ledger's `spawn` event carries the RESOLVED `backend=` beside `model=` and `effort=`. It is the one resolved value nothing else records, and no evidence rests on it — which is exactly why losing it loses the attribution of the evidence it produced. No slice-end field to match it: `ledger()` stamps every record and slice completion is already `advance … verdict=done`, so the end is a read, not a write | drill S12 (a two-backend topic: the author spawn carries `backend=test`, the reviewer's own spawn carries `backend=test2` — per-stage attribution, never a topic-level guess) |
| per-slice-table-off-the-panel | `launch.sh status <workspace> --slices` → a per-slice table derived from surfaces that already exist (attempts for `started`/`parked`, the ledger for the turnover advance and the spawn backend), written by a separate small reader that touches none of the panel's four pinned layout rules. BOTH clocks are labelled and `work` excludes credited park intervals; the backend column names only a slice that ran on a backend the topic level does not name; an absent index refuses rather than printing an empty table | 35-verbs (both rows listed in id order; `work 30m · total 1h00m` on a 1h slice with 30m parked; a finished slice's clocks stop at its turnover advance; the exception rendered AND the norm stayed silent; unknown flag refuses; absent index refuses) |
| profile-follows-the-assignment | any stage spawning on any (role, slice) → the session's harness profile is rendered ONCE, from the template the RESOLVED declaration names, into `.runtime/profile-<session>.json`, with `{WORKFLOW_ROOT}`/`{WORKSPACE}`/`{SESSION_NAME}` substituted together. No topic-level profile artifact exists, so a reviewer — or a slice — bound to another backend can never inherit the author's harness; that defect was invisible only because two declarations named the same file. `launch.sh` validates the declaration and its template at the door and bakes nothing; `probe.sh` renders into its own per-backend scratch workspace and is untouched | drill S12 (two backends with DISTINCT templates: the reviewer session's rendered profile carries the reviewer-only marker, the author's does not and carries its own hooks, no placeholder survives, the reviewer's session name is baked in, and no topic-level `.runtime/profile.json` exists at all) |
| capability-admission | a (role → backend) assignment missing a required capability → self-describing refusal naming the capability, never a silent fallback; declarations probed at onboarding | 45-halt (admission refusal both directions); 30-closure (declaration completeness); drill S9/S9b (probe both directions) |
| promise-and-fact-at-one-line | the SAME spawn that checks the declared capability list (the promise) also checks that a valid probe record stands for the resolved backend (the fact): identity = CLI version ⊕ declaration ⊕ profile ⊕ the probe's own code ⊕ `result=pass`, read never re-probed, so it costs no session and the per-workspace cache carries a backend proven on any earlier launch. Absent or stale → `park(template_error)` naming the backend and the relaunch that clears it. The door widens to match: the preflight probes the **config-reachable** set — the topic-level values plus every distinct `agent.<role>.backend` in a `slice.<nn>.<agent>.kv` on disk — and every declaration in that set must resolve before ANY session is spent. A file whose `<agent>` segment is not a role contributes nothing (no spawn can read it), and a fault in one travels as a status, never as a silently smaller set | 45-halt (no record parks naming the backend and the fix; a valid pass admits; `result=fail` parks; a declaration edited after the record invalidates it; re-stamping admits again); 20-config (the reachable set: topic dedupe, a slice-only backend present with its file named, no duplicate, non-role file contributes nothing, unknown key → rc 3; and the door ACTS on it — a stub prober records who it was asked about, proving the slice-only backend is SENT to be probed and not merely enumerated, while a slice naming a declaration-less backend refuses at the door, names the file that asked for it, and spends no probe first); drill (every scenario stands on a record fabricated from `probe.sh --identity`, asserted valid against the guard itself). The query the guard runs is BOUNDED, and that bound is part of the contract: `--verify` asks the CLI its version once per spawn inside the ferry's own process, and this command has hung past four minutes on the CLI's own self-update prompt — an unbounded hang there wedges the run silently, because the watchdog classifies EXITS and a driver that never exits is one nothing catches; 45-halt additionally drives `--verify` against a declaration whose `cmd.version` never answers, asserting it returns at its own bound rather than at the fixture's outer guard |
| probe-refuses-broken-promise | a declaration whose promise the live scratch session cannot prove (or a same-version edit to a proven declaration/profile) → probe FAIL, topic refuses to start; unchanged version+content = cached pass | drill S9 (pass + cache), S9b (fail names the promise), S9c (cache is content-bound); a live green was recorded against a real Claude Code build |
| exclusivity-wired | any topic run → host + repo locks actually taken by the production entry (audited traces), and a live foreign holder refuses at preflight AND at the take | 15-locks (refusal both ends + preflight advisory); drill S2 (wiring traces + lock file present at a park) |
| first-miss-owed-park | a DONE record with missing owed items → emit refuses; if one lands anyway the ferry parks `owed_miss` on the FIRST miss, listing exactly what is missing | 40-owed; 50-record; drill S2 |
| no-silent-finish | a turn ending without a valid record → the Stop hook blocks it; nonces are single-use | 50-record |
| stop-gate-scoped-to-caller | a session that already delivered its own record → its turn ends freely however far the ferry has advanced (identity is the per-spawn session NAME, resolved to that session's nonce at gate time; a torn-down name owes nothing), while the ACTIVE record-less session is still blocked and a nameless or unrendered-placeholder call enforces globally (fail closed); the block message's move — emitting another stage's record — refuses on the role binding | 50-record (release, block, torn-down, placeholder, legacy-global, and the role-bound emit refusal) |
| durable-anchors-only | a claims-table citation → line pins refused; anchors resolve as path#heading / path::symbol with a verified content echo, and for a heading anchor that echo resolves INSIDE the heading's extent (recorded as `claims_cite_scope`, which never refuses an emit) | 60-gates |
| claims-rederivable | a load-bearing claim in an artifact → it carries its command + read range and re-derives; fixes re-run the gates they touched | 60-gates (resolver, env sweep) |
| independent-floor-cold | precheck/postcheck round 1 → separate reviewer lineage on a cold spawn, enforced as a static stages.tsv column | 30-closure (cold rows, session closure) |
| owner-core-halts | class_u / blocked / disagreement / plan_changed / push → halt to the owner; a ruling addressed to the halt's slice (and stage, when stage-addressed) is required; class_u/blocked/plan_changed re-enter the suspended stage with the ruling in the manifest, disagreement discharges the trend predicate for the ruled (slice, stage, round) and advances — the predicate covers both review loops (precheck↔revise, postcheck↔fix) | 45-halt (the halt routing and the ruling's address); 46-convergence (the trend discharge and both loops); 50-record; drill S4 |
| monitor-cannot-touch | the monitor running → it reads the store only; no capture-pane, no input channel | by construction (monitor.sh has no write path; control surface is launch.sh). `peek` is an OPERATOR verb, deliberately outside this contract: it captures a pane with zero clients and no geometry effect (measured, asserted in 80-pty) — the look half of look/type, attach being the typing path |
| named-cap-exceedance | any cap exceeded → the emit-time gate refusal names the cap, the value, and the source layer (author-fixable in-session; no park — self-heal-first); the workflow's own tree is swept against its declared caps by self-check | 60-gates (incl. own-tree sweep); 20-config |
| notify-hot-policy | a notify policy change mid-run → the next event obeys it without relaunch | 65-notify |
| notify-mechanical-predicate | a notification decision → inputs are event type + reason class only, both closed enums | 65-notify |
| workflow-source-rollback | a bad workflow-source change → deliberate guarded git restore; discussion, plans and .runtime never committed; project commit conventions via the vendored hook | dev-time procedure (config-and-adapters.md §4) |
| config-fallthrough | an unset key → falls through the three levels; unset everywhere = workflow default, never an error | 20-config |
| parallel-config-safety | two topics running → defaults are read-only, overrides live under each topic's own tree; an override addressing a retired slice id faults loudly | 20-config |
| project-adapter-required | a missing project.kv → refuse to start, self-describing | 20-config |
| parallel-slices-slot | within-topic parallel demand → a designed, deferred slot (declaration + census-by-finding-set specified) | design (architecture.md §10) |
| signature-classification | any declared screen signature painted → classified correctly; an unmatched screen parks with the captured text attached | 80-pty |
| protocol-idleness-primary | a FRESH CLI-side idle_prompt on the notify_events surface (age ≤ liveness.notify_fresh) + an unclassifiable pane → awaiting_input ladder, never `park(unknown_screen)`; a stale event, an absent surface (backends without the hook), or a permission_prompt-only surface → unknown_screen park unchanged; the reclassification is audited | 75-watch (fresh reclassifies; stale + absent + permission-only controls) |
| composer-guard | injection over a composer with text BEFORE THE CURSOR → refuse always; `park(operator_interference)` when a writable client is attached, `composer_occupied` (retry/cold-fallback) when nobody is | 80-pty |
| manifest-render | a required manifest item missing → `park(template_error)` before any spawn; an optional one renders the literal "none" | 30-closure; drill S1, S6 |
| transition-totality | any reachable (stage, verdict) pair → a defined successor; one full slice walks to COMPLETE | 30-closure; drill S5 |
| progress-recovery | the ferry killed mid-impl → relaunch re-attaches or resumes at the correct commit-unit, never re-landing finished ones | 40-owed (ledger derivation); validation-debt (kill-and-relaunch) |
| pin-is-the-subtree | a commit in the same checkout that leaves the workflow subtree byte-identical → the pin is unchanged and no topic parks; a commit or an uncommitted edit INSIDE the subtree still parks `workflow_changed`; a non-git tree stays the named no-git degradation | 45-halt (sibling commit passes, subtree commit parks, dirty halves unchanged) |
| moved-ground-halts | plan hash or workflow-tree SHA mismatch → `halt(plan_changed)` / `halt(workflow_changed)`; recovery: workflow_changed repins on deliberate relaunch, plan_changed resumes only on an owner ruling (both repin) | 45-halt (resume/repin); validation-debt (firing evidence pending) |
| notify-at-least-once | a park whose notification could not be delivered → the notified flag stays 0; the next relaunch re-sends before anything else | 65-notify; 45-halt |
| review-structure-gate | a review artifact at emit → matches `templates/review.md` section structure, or the emit refuses (a structure mismatch is a draft) | 50-record; 60-gates |
| impl-close-attested | an impl/fix DONE record → every landed cu re-passed the project commit gate; a PASS acceptance record pinned to the current tree exists (or a named SKIP where undeclared) | 50-record |
| sessions-bounded | a cold spawn displacing a held session, and topic COMPLETE → displaced/held sessions torn down and ledgered; zero `delivery-*` sessions at COMPLETE | drill S5 |
| reslice-two-key | a turnover `reslice` verdict → split-check's manifest carries the proposing turnover; `flag` applies via split (merge mints a new id; omitted ids superseded, preserved in the index) | drill S8; 42-index |
| attribution-check | a red gate on a shared branch → re-run with our commits removed; red both ways = `park(blocked)` with evidence, not our defect | documented procedure (review-and-slices.md §5); validation-debt |
| unknown-key-faults | an unknown config key → fault naming the key, never a silent fall-through | 20-config |
| slice-repo-binding | a project declaring `doc.repo`/`doc.branch` (paired, git-shaped, workspace ignored inside it) → every slice binds to exactly ONE checkout, cast at split by `id:risk:repo:title` and immutable per id — one admissibility rule over the declared index (grammar · one id one slice · retired ids never revived · immutable binding) is asked by each door into it, so every way an author's declaration could be DROPPED is refused at emit and parked at ingest instead of passing in silence; owed cu→SHA ancestry, gate attestation pins, the fix baseline and the progress registration wall all resolve through that binding; both checkouts are claimed at topic start in the fixed order code → doc and released together at COMPLETE | 20-config (pair rule + R-1 both ways + primitives + divergence rule incl. fault); 42-index (grammar, immutability, ingest park, risk audited not refused); 15-locks (both claims, audited order, release); 40-owed; 50-record (emit refusal + the new-id good direction); 60-gates; drill S10 |
| doc-gate-structural-skip | a doc-bound slice at any project gate → a structural named SKIP; the project's build/lint/test/acceptance command is never run against the doc tree; a code-bound slice in the same topic still owes its acceptance pin, and doc commit-units still re-pass the project's commit convention | 60-gates (tripwire both directions); 50-record; drill S10 (tripwire across a whole topic) |
| gates-rows-carry-slice | any gate attestation → its row carries `slice=<active slice>` (the stage surface's), `slice=none` with no active stage; the field precedes `gate=` so every existing reader parses unchanged | 60-gates (code-bound 01, doc-bound 02, no stage → none) |
| slice-scoped-handover | a manifest item `gates@nn` / `ledger@nn` → `surface.<name>.<nn>.txt` holding the rows stamped `slice=<nn>` plus every row with NO slice field (run-level events; attestations older than the stamp) — filtering is by a field that says otherwise, never by the absence of one; postcheck GATES and turnover LEDGER use it, close-out keeps the whole ledger; the fingerprint excludes the sliced dumps as it excludes the whole ones | 30-closure (own row kept, other dropped, fieldless kept, file name, the three manifest rows); 70-fingerprint |
| charter-sections-at-split | a split emit → `charters.md` carries one `## slice <id>` heading per id in `--slices` (trailing title allowed; the id matched to its boundary — a lone `## slice 021` is not 02's), or the emit refuses naming the ids | 60-gates (both directions, titled heading, boundary — mutation-checked); 50-record (the door) |
| plan-slice-excerpt | a spec stage → its manifest carries `plan_slice`: the plan's text before its first `# W-<id>:` item heading, the item blocks the charter's `## slice NN` section names, and the text after the last item up to the first `# Delta`/`## Refine log` heading (item headings accepted at H1–H3); headings verbatim so anchors resolve in the plan; ids the charter names but the plan lacks are named in the excerpt's header; no section / no named id / no item headings → `none (<reason>)` and the author reads the full plan, which stays a required manifest item | 30-closure (both plan shapes, kept and dropped lines, reasons, sidecar); live effect on spec quality: VD-33 |
| class-u-question-set | a `--halt class_u` emit → `slices/<nn>/halt.<n>.md` exists (n = the slice's class_u halt count + 1, derived from the handoff surface), within cap.artifact_lines, matching `templates/halt.md`'s `##` sections in order (question · why · blast radius · options with delta/for/against/after/cost · worked examples under every option · recommendation · evidence · refine log); absent or mis-structured → refused naming the path; the record's detail leads with the path so the park message and owner page carry it; `blocked` owes none (an obstacle is not a decision) | 50-record (absent, mis-structured, present, second halt → halt.2.md, blocked ungated); drill-ruling (the mock halts through the door) |
