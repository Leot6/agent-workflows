# state, handoff, liveness

> Settles the state model (the atomic store and its surfaces), stage handoff and
> completion, retry novelty and budgets, and liveness classification with auto-resume.

## 1. The store

`lib/state.sh` over `<workspace>/.runtime/state/` — one file per surface, atomic
tmp+rename (tmp under `.runtime/tmp/`, same filesystem), header
`#v=1 gen=<n> sum=<md5-of-body> writer=<class> t=<epoch>`.

- **Sole writer class per surface** (registry inside state.sh; the caller declares its
  class, mismatch = refuse + fault). This is a **bug barrier, not a security barrier**
  (agents hold repo write access anyway — stated honestly, not gated theatrically).
- **Fault ≠ absent**: a missing surface on first write is normal (gen=1); a checksum/parse
  failure is a **fault** — readers must propagate it (distinct rc), never read it as
  zero/absent (v1's wedge class). A store fault during a run → attempt notify (transport
  needs no store) → exit with the dedicated code → watchdog's bounded relaunch → on
  exhaustion CIRCUIT-BROKEN + notify. Launch preflight checks disk headroom.
- **Append loss is loud; integrity is proven at start** (the verify-at-open
  discipline). A failed append names its lost record on stderr and — for the
  ledger — pages `store_fault` once per ferry process; `state_audit` stays
  best-effort for its caller but never fails silently (and never notifies from
  inside itself: the notify path audits, which would recurse exactly when the
  audit surface is the broken one). Before its first store write the ferry
  verifies EVERY headed surface (`state_verify_all`) and dies `store_fault`
  naming each broken surface plus the reseal recipe — a run over a corrupt
  append surface loses its whole event history invisibly, because
  whole-surface rewrites keep working and the pipeline looks healthy.
- **Crash-semantics boundary (stated)**: tmp+rename makes every surface write —
  append surfaces included; they are read-modify-write-rename, never O_APPEND —
  atomic against **process** crashes, the recovery path this design leans on
  (kill the ferry anywhere; cold re-entry reads a consistent store). Against
  **system** crashes (power loss / kernel panic) the store is not fsync-hardened:
  integrity damage surfaces as the loud fault above, and an un-persisted rename
  can silently roll a surface back one generation — absorbed by the at-least-once
  semantics elsewhere in this design (progress reconciles against `git log`,
  completion re-sends, halts re-page). The fsync cost is deliberately not paid;
  revisit only if power-loss enters the threat model.
- **Writer classes**: `ferry`, `session` (harness hooks + record emit), `operator`
  (launch.sh verbs), `gate` (harness-run gate results), `watchdog` (see below).
- **Watchdog exception (declared)**: on death/stop paths the watchdog writes the minimal
  final-state file **directly, bypassing the store** — when the store itself may be the
  casualty, someone must still render a last state. The one documented exemption.
- Append surfaces (`ledger, audit, observations, learnings, handoff, progress,
  decisions, rulings, gates`) declare rotation caps (exceedance named, never
  silent; the caps sit far above any real topic's volume — note honestly that a
  handoff rotation would age out cross-round history, so the cap is sized to
  never trip mid-topic). Timestamps are epoch seconds. Records carry `v=` (schema
  version); readers accept a declared version set, unknown = fault not guess.

Surfaces: `run` (topic identity, mode, plan hash, workflow-tree SHA, CLI versions, config
snapshot pointer — writer ferry) · `stage` (current slice/stage/attempt/state — ferry) ·
`ledger` (append: every transition with timing — ferry) · `heartbeat` (last tool-use epoch —
session) · `attempts` (fingerprint history K=4 per (slice,stage); attempt counts per
(slice,stage,round); budgets — ferry) · `halt` (current park: reason class, detail, screen text when relevant, notified
flag — ferry) · `sessions` (held sessions per role: tmux name, pane/server pid+starttime,
spawn nonce, mode — ferry) · `handoff` (stage completion records — session via record.sh) ·
`progress` (impl cu→SHA ledger — session) · `slices` (the machine slice index: id, order,
risk class, footprint, status incl. cancelled/superseded — ferry; written from split's
output) · `decisions` (Class A/C DPs + veto status — session) · `rulings` (owner rulings,
addressed to (slice,stage) — operator) · `observations` (workflow-defect entries, stage +
pilot contributors — session/operator) · `learnings` (leak-tagged postcheck findings
awaiting anchor-pair promotion — session) · `gates` (harness-attested gate results,
pinned to repo sha + tree + dirty fingerprint, stamped with the active slice — gate) · `notify_events` (append: the CLI's
own Notification events — idle_prompt/permission_prompt, one row per firing — session via
notify_event.sh) · `notify` (policy:
preset + per-event overrides + dedup config — operator) · `audit` (append: everything —
any class) · `lock` (host mutex, mkdir-atomic + pid/starttime).

## 2. Records, nonce, stop gate

A stage completes **only** through `session/record.sh emit`: validates schema (stage, nonce,
verdict from the closed vocabulary, refine fields where owed, confidence HIGH/MED/LOW),
checks the nonce against the sessions surface (fresh per attempt, injected in the volatile
prompt header, single-use), derives the owed set via `lib/owed.sh` and refuses emission
while any owed artifact is missing. The nonce is this design's fencing token (the
single-machine analogue of an epoch number): liveness judgment alone cannot exclude the
in-flight effects of a superseded session — one that outlived its takeover — but its
emission fails the nonce check no matter when it arrives. Any stage may emit a **halt field** (`class_u` with the
batched questions, or `blocked` with the obstacle) in place of a flow verdict — the
transition table spells out only the common halt routes; the record-level field is the
universal path (the halt set is stage-independent). The profile's Stop hook calls the same
check — a turn cannot end without a valid record (the structural half of
never-finish-silently). That gate asks the **caller's own** debt, never the globally active
attempt's: each cold spawn bakes the calling session's NAME into the hook command line (a
per-session profile render — the name survives warm reuse, the nonce does not), the gate
resolves that name to the session's current nonce on the sessions surface at gate time, and
a caller holding a different nonce, or no row at all, owes nothing and ends freely. No name
(legacy profile, unrendered placeholder) enforces globally — fail closed. Judging the global
surface instead was a measured defect: once the ferry advanced and overwrote it, the previous
stage's still-open turn could never end (superseded sessions pinned in `working`, so warm
reuse could not meet its precondition) and the block message named the NEXT stage's nonce —
the impersonation that emit's role binding refuses from the other side. The ferry's advance check and
park-on-miss call the same `owed.sh` derivation (the single-list invariant): a DONE record
with missing owed items → `park(owed_miss)` on **first** miss, listing exactly what is
missing — never an identical respawn (closed at both ends: emit refuses, advance parks).
Malformed handoff → `park(stall_record)`, never advance.

Owed derivation = `stages.tsv` static column ⊕ spec commit-unit list (impl/fix stages);
the spec is a trusted source because precheck reviews it — spec-vs-plan completeness is
precheck's, commit-vs-spec is conformance/postcheck's.

## 3. Attempts: novelty detection + budgets (the breaker, re-founded)

A retry is justified only by expected difference. Two orthogonal mechanisms, zero shared
criteria — a backstop must never share a criterion with the failure it catches:

- **Loop detector**: before each spawn, fingerprint = hash(prompt body [volatile header —
  nonce, timestamps, session ids, the slice's binding line, and the previous slice's
  turnover commit-reference reading — excluded] ⊕ owed-artifact content hashes ⊕
  manifest-resolved workspace-input content hashes ⊕ last failure class). Match against
  the stored last-K=4 history for this (slice,stage) → `park(no_novelty)` — a budget
  argument, not a proof: sessions are non-deterministic, so an identical retry is never
  PROVEN futile — it is priced out (its marginal success odds do not buy its cost), and
  any real input change restores novelty; K=4 catches period-2 oscillation. History
  lives in the store → survives ferry restarts (v1's "bounded per launch, unbounded
  across launches" closed). The input-content term is admitted deliberately (owner-ruled):
  the prompt body carries input *paths*, not content, so without it an owner hand-edit
  to a plan/charter before relaunch would be invisible and the standard recovery move
  would park `no_novelty`; over-inclusion is bounded by the attempt budget. Incidental
  file churn outside the manifest still counts as nothing (owed delta = checkpointing,
  spawn freely; zero delta = count). Template upgrades refresh fingerprints, but the
  workflow-SHA pin makes any upgrade a loud, deliberate adoption (architecture §5)
  and the maintenance rule keeps edits off live stages — benign interaction, noted.
  The header's two DERIVED lines are excluded for the same reason from opposite
  ends: the binding is immutable per slice id, so including it would buy nothing,
  while the previous slice's turnover reading depends on AMBIENT repo state — a
  colleague's rebase, or a repo growing a commit whose abbreviation matches a hex
  word — and in the body it would manufacture novelty indistinguishable from a
  real input change, handing a fresh bounded set to a retry nothing about the
  attempt had changed.
  Two boundary rules keep the detector honest: machine-written observation
  streams (ledger, gates) are excluded from the input term — the attempt itself
  appends to them, so hashing them would make every retry read as novel and the
  detector could never fire for the stages that carry them (session work
  products — progress, decisions, observations, learnings — stay in: their
  change is genuine novelty). And a deliberate relaunch after a mechanical park
  is a **redrive**: it clears the parked (slice, stage)'s attempt count and
  fingerprint history — parks are deliberate exits the watchdog never restarts,
  so automation cannot loop through this; the human's relaunch buys exactly one
  fresh bounded set.
- **Budgets** (economics, self-describing on trip): per-(slice,stage,round) attempt
  budget — an attempt is a retry of the SAME work unit; a new review round is new
  content and gets a fresh count, with rounds themselves bounded by the severity-trend
  predicate and the wall-clock budgets — plus per-slice and per-topic wall-clock
  budgets. Wall-clock and attempt counts only — token spend is not uniformly
  observable at the CLI seam and is not pretended. The wall-clock budgets meter
  **working** time, not calendar time: the resume gate credits each cleared
  halt's parked interval (attempts `parked.<slice>`, run `parked_total` —
  stamped from the halt's own `t`, once, at resolution) and the budget checks
  subtract them — a park is the one interval where the thrash these budgets
  price cannot happen (a measured owner-level 18h park otherwise spent a slice
  budget twice on zero attempts; the CI shape: the job timer meters execution,
  never the queue). Absent credit keys read 0 — old records compare unchanged,
  no migration. The slice clock is a SLICE's, so the topic scope (id 00) is
  exempt from it: 00's stages are plan-validate/split/split-check at the
  beginning and close-out at the end, with the whole delivery in between, so
  its `started` stamp is the topic's own and a slice cap there prices the
  entire topic — measured at close-out re-entry, 128394s of "working" whose
  every hour belonged to slices 09..15. That span is the topic budget's to
  price; two clocks over one interval under different caps meant one of them
  was the wrong instrument, not that the interval needed two.
- Convergence of the review loops (revise↔precheck AND fix↔postcheck) is neither of
  these: the **severity-trend predicate** (counts by severity class from the review
  records — mechanical fields, no content) → two consecutive rounds of the same
  review stage with non-decreasing substantive findings, the newer round carrying
  at least one `repeat` (the reviewer's own split of its count into findings that
  survived the previous round and findings that are new — a record without the
  split reads as all-repeat) = `halt(disagreement)` to the owner (continue / split
  / redesign); a loop whose rounds are all new is bounded by `review.max_rounds`
  instead, parking the same class. The fix loop needs it as much as the
  revise loop: fix-round evidence keeps every fix attempt fingerprint-fresh, so
  without the predicate its only bound is wallclock — a park that misnames the cause.

## 4. Park vocabulary (closed; every entry passes the self-heal-first audit)

`dead, idle, stall_record, stall_mismatch, owed_miss, no_novelty, budget_attempts,
budget_wallclock, template_error, plan_changed, workflow_changed,
unknown_modal, unknown_screen, operator_interference, operator_stop, store_fault,
backend_quota, backend_overloaded, class_u, blocked, disagreement, push_gate` +
terminal `broken`
(watchdog budget exhausted). `backend_quota` and `backend_overloaded` are the
liveness-adjacent entries
that deliberately skip the bounded respawn this section otherwise demands: the
session is alive and correct and the BACKEND is out, so a respawn spends attempts
on calls that cannot succeed until a reset time the backend itself names on the
pane (measured: two attempts born dead into a zero-quota window, and a third
whose stage clock ran there). Self-heal has no path when the resource is gone.
`backend_overloaded` is the same statement with NO reset time to wait on — a
529-class refusal from a backend that is up — so its park text says there is no
clock and the operator relaunches on judgment (measured 2026-09-03: before the
class existed the exhausted retry ladder left an empty composer, the pane read
`awaiting_input`, and two attempts and ~17 minutes went to a backend that could
not answer, ending in a `no_novelty` park on an identical fingerprint).
`operator_stop` is the graceful park written by `launch.sh stop` and
SIGTERM/SIGINT. `dead`/`idle` are also the reason classes named when the attempt
budget is exhausted by that class (bounded respawn precedes every liveness park;
the budget end NAMES what it was spent on). Cap exceedance is deliberately NOT a
park reason (owner-ruled): it surfaces as an emit-time gate refusal to the author,
who fixes and re-emits in-session — the self-heal-first rule this section imposes
on every park candidate, applied to itself.

Design rule (v1 RUNTIME #7): the stop set's size is a cost; before adding a park, show the
condition cannot self-heal (nudge → bounded respawn precede every liveness park; only
then a human). Every reason is documented in `operations.md` with the pilot response
**before** it ships — a ceiling names itself when it trips, and an undocumented
park reason is an unshippable one.

## 5. Liveness classification (the signal stack)

Timer semantics (owner-ruled): `stage_timeout` is a **continuous-inactivity
deadline** — every activity observation (fresh heartbeat, CPU delta) resets it;
only unbroken silence past the limit kills. `hard_ceiling` alone bounds total
duration; `working_max_age` bounds a screen that *claims* work while CPU burns;
the nudge window (`quiet_grace` + `nudge_grace`) sits below `stage_timeout` so
recoverable idles self-heal before any timeout. The same shape as the standard
pairing of no-output timeouts with total job caps in CI systems, and of
consecutive-failure liveness probes.

For the active stage session, strongest-semantics first:

1. **Process**: pane pid + server pid + starttime match (pid-reuse defense) → else `dead`.
2. **Stop-gate blocks**: `stop_gate_blocks_max` refusals recorded for THIS attempt →
   `FAIL wedged`. High in the stack deliberately — it is the session's own STATEMENT
   that it cannot finish, not an inference from activity, and every branch below can
   `continue` past a wedge (a tool-calling loop keeps the heartbeat fresh, a spinning
   CLI clears the CPU floor, a pane can classify working). That is the shape that hid
   the measured one. The gate is doing its job at each refusal; what follows is the
   CLI's own block cap overriding it and force-ending the turn, leaving a pane that
   will never speak again under a stage surface that still reads running. The hook's
   exit code cannot reach the ferry, so the count travels through the attempt's own
   audit trail. The default is calibrated between two measured points: a normal turn
   blocks once by design (up to ~3 while an agent iterates toward a refused emit), the
   wedged one blocked nine times before the CLI gave up.
3. **Heartbeat**: hook writes epoch per tool call (covers sub-agent calls where declared).
   Fresh heartbeat → `busy`.
4. **CPU**: process-subtree CPU **rate** — a delta at or above `cpu_busy_pct` of one core
   over the real span since the last sample means busy though silent → extend, up to the
   hard-stall ceiling. The floor is the load-bearing half: "any increase at all" is the
   idle CLI's own baseline, so the test answered yes forever and reset the inactivity
   clock, the nudge and the working episode with it — a wedged session was
   indistinguishable from a busy one and only the ceiling could end it. Scaling by the
   real span keeps a heartbeat-fresh gap from accumulating into a false burst. What is
   measured here is silent AND unheartbeated work — a build or test run, near or above a
   full core — so a floor well above idle noise costs nothing.
5. **Pane signatures** (declaration's closed regex set; double-capture agreement):
   `working` (respect max-age ceiling) · `awaiting_input` → soft-pause → nudge (one per
   quiet episode, then bounded respawn → park(idle)) · `quota_exhausted` →
   `park(backend_quota)`, deliberately skipping the bounded respawn because the
   resource, not the session, is what failed (§4) · `backend_overloaded` →
   `park(backend_overloaded)`, the SAME reasoning with a shorter horizon and no
   reset time to wait on, so the park text says there is no clock and the
   operator relaunches on judgment (read AFTER quota where a frame carries
   both, since only quota names a time) · `error_retryable` → the CLI's own
   retry ladder is running, so it is NOT nudged and does NOT spend the idle
   budget: its own `liveness.retry_grace` bounds the episode and the failure
   names the cause (`FAIL backend_retrying`), because `FAIL idle` on a retrying
   backend sends a postmortem to look at a session that was fine ·
   `modal.*` → exact-allowlist action ·
   no match → **protocol-derived idleness first**: a fresh
   CLI-side `idle_prompt` event on the `notify_events` surface (younger than
   `liveness.notify_fresh`; `watch_proto_idle` in lib/watch.sh) reclassifies the
   unknown pane as `awaiting_input` — the CLI's own statement is primary, the screen
   corroborates by not contradicting (a `working` pane still wins its arm); the
   reclassification is audited. `permission_prompt` events are recorded but never
   acted on (a permission modal under dontAsk is config drift, surfaced not
   auto-answered). Backends without the hook surface (codex today) read no events
   and behave exactly as before. No fresh event →
   `park(unknown_screen)` + captured text, as always.

Held (warm, inactive) sessions are exempt until reuse (then: alive + awaiting_input +
empty composer, else cold-fallback). Clock-jump amnesty: the ferry tracks its own tick;
a gap ≫ poll interval (suspend/NTP) resets stage timers with an audit note instead of
parking. All thresholds are independent config literals — no derived defaults (a derived
threshold would move silently with its base).

## 6. Watchdog

Exit-code classification: complete → stop; a park → stop DRIVING and hand over to the
pager (config-and-adapters §5 / operations §1: the same process re-pages the unresolved
halt every `notify.repage_interval` up to `notify.repage_max`, reading the
halt, audit and notify-policy surfaces and the topic's config — the only workspace content
it reads, all of it for paging; a relaunch or `stop` ends it, `launch.sh ack` HOLDS it for
`notify.ack_timeout` and it then resumes — an ack is a claim of ownership, not a receipt —
`notify.repage_max=0` turns it off); crash →
bounded relaunch budget → CIRCUIT-BROKEN + notify. The final-state file is written only
when driving stops and cleared when driving starts, so "class=parked beside a live pid"
has one meaning: the pager. The relaunch
budget is an absolute count, not a rate window (supervision precedent meters restarts
per time window): the wall-clock budgets and hard_ceiling already bound the lifetime
the count is spent across, so a window would add a knob without adding a distinction. Its own death is
visible (monitor shows watchdog liveness; operations.md documents the optional systemd
user-service wrapper). Startup reconcile (ferry, not watchdog): enumerate `delivery-<topic>-*`
tmux sessions, compare with the sessions surface; in the all-cold baseline every survivor
is stale → fence + audit (adoption logic arrives only with warm, which records enough
witnesses to authenticate a held session).

## 7. Notification delivery

Transport preserved verbatim (`<notifier-cmd> <event> <message>`, best-effort;
the launch preflight fires a test notification at every launch); the notifier
command lives in **config**, not env (v1's un-re-exported-env disarm hazard removed). Policy layer: `config-and-adapters.md` §5.
Delivery is at-least-once: halt written → notify → `notified` flag; relaunch finding
halt-without-flag re-sends (a duplicate page beats a lost one).
