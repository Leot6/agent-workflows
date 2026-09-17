# operations — launch, parks, takeover, maintenance

> reference (on-demand), for the operator (owner or pilot). the flow is
> `protocol.md`; the pilot's quick table is `cards/pilot.md` — this file is the full
> playbook behind it.

## 1. launch and preflight

`launch.sh launch <workspace>` (any directory carrying `project.kv`; the
two-tree deployment keeps it at `plans/topics/<topic>/delivery/`) runs:

- dependency + disk-headroom checks; `project.kv` present and complete (absent →
  refuse, self-describing — the workflow ships no project assumptions).
- clean-workflow-tree check: uncommitted changes under the workflow subtree
  refuse the launch (commit or stash first) — launch is the adoption door
  (a fresh topic pins the tree here, a relaunch repins), and live sessions
  execute this tree by absolute hook paths; the run_attempt pin backstops
  drift that lands only AFTER a stage is live. Scoped to the subtree
  (sibling-directory changes in the same repo are not this tree's dirt); a
  non-git tree stays the named no-git degradation.
- repo locks, advisory check: exactly one claim (`<git-dir>/delivery.lock` — topic
  path + pid + starttime; never in the worktree) per declared checkout — the
  project repo and, when declared, `doc.repo` — walked in the fixed order
  code → doc that the ferry's own takes use. A second
  topic on either claimed checkout refuses
  HERE — before a probe session is spent — using the same holder-liveness
  predicate as the ferry's authoritative take (parallel topics need separate
  checkouts/worktrees). host lock in the store likewise — one ferry per
  workspace (taken by the ferry, audited). Both claims are released together at
  COMPLETE, never at a park.
- the preflight fires a test notification through the transport at every launch,
  BEFORE the probe can refuse (`notify.cmd` lives in config, not env — nothing
  to re-export, nothing to forget). The transport's home is the operator config
  (${XDG_CONFIG_HOME:-~/.config}/delivery-workflow/config.kv): `notify.transport=bark`
  picks a shipped adapter under runtime-scripts/transports/ (a platform secret like
  the Bark key lives beside it in bark.url), `notify.cmd=<command>` runs any command
  as `<event> <message`; topic.kv overrides either, per-topic. The test send is
  the transport's only live proof, and it has two halves — the preflight fires,
  and a device receives. Nothing re-checks arrival, so a transport that resolves
  and never arrives looks identical here to one that works. **the leg to a human
  is bounded by the pager instead**: after a park the watchdog stays alive and
  re-pages every `notify.repage_interval` (default 45 min) while the park is
  unresolved and unacknowledged, up to `notify.repage_max` (default 6), then
  says it stopped; `launch.sh ack <ws>` PAUSES it for `notify.ack_timeout`
  (default: one repage interval) rather than ending it — an ack is a claim of
  ownership, not proof of it, and the pilot is told to ack as its first move, so
  a test for "an ack row exists" is not a test for "a human has this park";
  a relaunch or `stop` ends it,
  a completion (push_gate) is never re-paged, and `notify.repage_max=0` turns
  re-paging off (said on the audit surface, never silent). basis: the armed parks' tail
  measured 2–6h against an unarmed p90 of 15h.
- backend onboarding probe (`runtime-scripts/probe.sh`): first use of a backend —
  and any CLI version change — runs one scratch session per unique backend in the
  **config-reachable set** (the two topic-level values PLUS every distinct
  `agent.<role>.backend` in a `slice.<nn>.<agent>.kv` on disk, because the spawn
  resolves per (role, slice); every declaration in that set must resolve before
  any session is spent) that proves the declarations are facts: the heartbeat hook writes the store, the
  Stop gate blocks a record-less turn end, the record chain emits, the idle
  screen classifies `awaiting_input`, injection reaches the pane, and liveness
  detection reads the exited CLI as dead. Soft items (`working`, `modal`) are
  attested when observed and NAMED as unobserved otherwise. Probe failure = the
  declaration is wrong; **the topic refuses to start on it** (evidence in
  `<ws>/.runtime/probe/<backend>.kv` + the probe pane log). An unchanged version
  is a cached pass — no session spent. The ferry re-reads that record at every
  spawn (`probe.sh --verify`, read-only, never a re-probe): a backend written
  into the config AFTER this door — which the door cannot see — parks
  `template_error` instead of running unproven. A record that is merely STALE —
  the CLI self-updated under a live topic — is re-proved INLINE at that spawn
  instead: the recovery is mechanical, and a full-auto topic with no pilot
  attached used to stop there and wait for a human to retype one command.
- config load: schema closure (unknown key = fault), reviewer-effort floor
  (reviewer effort ≥ run base), stages.tsv referential integrity.
- startup reconcile: enumerate `delivery-<topic>-*` tmux sessions, compare with the
  sessions surface, fence stale survivors with an audit note — never blanket-wipe.

then: watchdog + ferry start and `launch` RETURNS (scripts can compose it); watch
with `monitor.sh <workspace>` (read-only), or pass `--attach` to exec into it.

## 2. verb reference (`launch.sh` — the one operator entry)

| verb | semantics |
|---|---|
| `launch <workspace>` | preflight + init + watchdog + ferry (§1) |
| `rule <workspace> --slice <nn> [--topic] [--stage <stage>] --text "…"\|\|--file <path>` | write an owner ruling into the rulings surface; archived to `slices/<nn>/ruling.N.md`. `--file` carries a long ruling from a file (the store quotes shell quoting through `--text`; a backticked word was once eaten silently — the same reason `observe` takes one). The resume gate holds a ruling-gated halt until a ruling addressed to its slice (and stage, when stage-addressed) exists; the resumed stage's manifest then carries it (`RULING=rulings.pending`). `--topic` marks a ruling that fixes a mechanism: it rides every slice's manifest, not only `<nn>`'s. A session already running when a ruling lands is refused at emit until it acknowledges it (protocol §6) |
| `stop <workspace>` | graceful: park the current stage, keep sessions alive for postmortem attach. On a topic that is only PAGING (parked, watchdog re-paging) it ends the paging and says nothing was running |
| `ack <workspace>` | acknowledge the current park: the watchdog PAUSES re-paging for `notify.ack_timeout` (§1), then resumes while the park stands; the audit surface records that the park was acknowledged and when — never by whom, since any operator-class actor may run this. the park itself is unchanged — resume is still `rule` or a relaunch |
| `slice <workspace> <id> cancelled` | guarded index edit: the slice becomes unschedulable by status; artifacts remain |
| `slice <workspace> <id> restored` | re-schedulable; the slice re-derives its premise from scratch (its old spec is not presumed current) |
| `status <workspace>` | one monitor snapshot (`monitor.sh --once`), whose FIRST line is machine-readable for a poll: `state=<NOT_STARTED\|RUNNING\|BETWEEN_STAGES\|PARKED\|COMPLETE\|BROKEN\|STORE_FAULT> [reason=…] gate_fails=<n\|absent\|fault> attestations=<n>` — the closed state set a poll keys on without scraping the painted panel, and the running gate-FAIL count no other live surface carried |
| `status <workspace> --slices` | the per-slice table instead of the panel: id · status · risk · **both clocks, labelled** (`work` excludes credited park intervals — the clock `budget.slice_wallclock` meters; `total` is wall time since the slice started) · the backend **only for a slice that ran on one the topic level does not name**. A separate small reader over existing surfaces (attempts for the clocks, the ledger for the end and the backend); it writes nothing and touches no pinned panel layout |
| `status <workspace> --halt` | the halt surface with its `detail` **untruncated**. the panel renders a bounded frame and points here; this is where a parked run's batched question set is read in full — and for a `class_u` reached by verdict routing it is the ONLY place, because that spelling writes no halt document (§3) |
| `status <workspace> --rounds` | the per-stage per-round clock, a pure reader over the ledger's own `t=` fields: a round opens at `enter` and closes at the next `advance` for the same (slice, stage); a park inside the round is annotated with its reason and the gap it held — the gap closes at the FIRST of a later park row, the first `ferry_start`, or the stage's next event (a warm resume does no spawn, so the stage's next event alone would swallow the resumed work into the park gap); a park with no round behind it rides a tail line naming its stage. a round whose wall is mostly park reads as parked, not as slow work; the stage subtotal separates wall from parked. the reader that answers "where did the time go" — every pilot who needed one hand-rolled it, and the hand-rolled instrument silently dropped events for ninety minutes |
| `notify <workspace> <preset\|event=on\|off>` | notification policy, hot-read at emit — changes apply without relaunch (the TRANSPORT is config-file, deliberately not hot: it is the machine's, arming it is an operator act with a test notification to confirm) |
| `observe <workspace> --text "…"` / `observe <workspace> --file F` | append a workflow-defect observation to the observations surface (`--file` carries code fragments — backticks, `$()` — un-mangled by shell quoting) |
| `peek <workspace> [role] [--follow\|--attach]` | one pane per session, READ-ONLY — the "look" verb: capture-pane creates no client and cannot change geometry, so looking is free of the harm attach carries. The 220-col pane output simply wraps in a narrower terminal (the CLI folds its own body to ~100 cols). `--follow` repaints every 2s; `--attach` PRINTS the read-only attach command per session — executing it stays the deliberate typing path. Reader discipline as everywhere: a corrupt sessions surface refuses as CORRUPT; a present-but-empty surface says sessions were cleared at close-out; a row whose session is gone points at the pane log it left |

deferred (built on demonstrated need): `salvage`, `wait`.

## 3. park playbook

every park writes the halt surface (reason class, detail, screen text where
relevant) and pages per the notify policy — with one exception: `store_fault` on
the store itself exits without touching the possibly-corrupt store (the watchdog
bypass; the monitor renders the fault). the notified flag is set only when the
transport ACCEPTED the page (or policy deliberately suppressed it), and accepted
means the page LEFT THE MACHINE — the last thing this tree can observe, and not
a receipt: whether a human read it is unobservable from here
(`transports/bark.sh` states that boundary in its own exit codes, and is the one
site that always has). a page the transport refused re-sends at the next
relaunch; a page it accepted and nobody saw does not, and the recovery of that
park waits on somebody noticing. per reason — meaning / inspect / resume:

- **dead** — session or CLI process gone (pid/starttime mismatch — the launch
  command is the pane command, so pid liveness is the whole dead-detection
  truth). inspect: `.runtime/logs/<stage>.log` tail; halt surface. resume:
  relaunch — cold re-entry is idempotent (artifacts + store are the state),
  and the relaunch is a redrive: the parked stage's attempt budget and
  fingerprint history are cleared, so it genuinely retries.
- **idle** — the attempt budget was spent on awaiting-input episodes (nudge +
  bounded respawn preceded every one; the budget end names the class). inspect: log
  tail; attach read-only if needed. resume: relaunch; a repeat of the same idle is
  an owner question (the stage may need a different input, not more patience).
  a park does not by itself force a cold re-entry — a park whose session
  SURVIVED re-enters warm, measured — so if you want the author's context
  cleared, `all_cold=true` is the lever and it is yours to set
  (`protocol.md` §spawn table).
- **stall_record** — the emitted record failed schema validation. inspect: the
  record (handoff surface), audit tail. resume: one-off corruption → relaunch;
  repeated → owner + maintainer (template or record tooling defect).
- **stall_mismatch** — record failed nonce/stage authentication: something emitted
  a completion it did not own. integrity, not liveness. inspect: audit, sessions
  surface, `tmux ls` for unexpected survivors. resume: only after you can explain
  the mismatch; surface to the owner — never a blind relaunch.
- **owed_miss** — DONE-shaped record, but a named owed artifact is missing (parked
  on the first miss, listing exactly what is absent). inspect: the named item's
  path; the stage log. resume: relaunch once (the respawned stage sees the same
  owed list); a second miss on the same item → owner.
- **no_novelty** — the attempt fingerprint matches one of the last K attempts: an
  identical retry is priced out (non-deterministic sessions make it unproven,
  not free). inspect: the prompt file and manifest inputs under
  `.runtime/prompts/` (the attempts surface holds hashes and counts, not
  diffs). resume: change something real — a ruling, a config value, an input
  artifact — then relaunch; a no-change relaunch is a redrive that explicitly
  buys one fresh bounded set (your call, your loop); nothing changeable → owner.
  **a relaunch here can re-enter the SAME session it just failed in** — measured
  on a `no_novelty` park whose session survived: attempt 3 ran warm in the
  session that failed 1 and 2, `mode_src=warm`. If "change something real" was
  meant to include the author's context, say so with `all_cold=true`; relaunch
  alone does not.
- **budget_attempts** / **budget_wallclock** — a declared budget spent;
  self-describing. the wallclock budgets meter WORKING time: parked intervals
  are credited at each resume and excluded, so a long owner-level park never
  spends them (the park message states both numbers). inspect: ledger
  timeline — real advances or thrash? resume: advances → raise the budget
  (config) and relaunch; thrash → owner.
- (cap exceedance is NOT a park reason — owner-ruled. it surfaces as an emit-time
  gate refusal to the author, naming the cap, the value, and the source layer;
  the author fixes and re-emits in-session. if an author repeatedly cannot
  comply, the run ends in `budget_attempts` and the owner changes the effective
  cap in `project.kv`, or rules.)
- **template_error** — a manifest-required item is missing, a template rendered
  with unresolved placeholders, or an admission input is absent (a backend
  declaration lacking a required capability, a missing declaration/profile
  file also park under this reason — self-describing refusals of the same
  input-defect class). a **config fault** joins that class: an unknown key, a
  bad type or a violated cross-key rule in `topic.kv` or a
  `slice.<nn>.<agent>.kv` (`config_get` validates every file in the resolution
  chain on every read, and the `CONFIG FAULT` line on stderr names the key and
  the file it is in). so does a backend whose **onboarding probe record** is
  absent or no longer matches its declaration — an admission input that is
  absent. that member no longer parks on its own: the spawn re-proves the
  backend INLINE (one probe session, bounded by `probe.timeout`) and parks only
  if the probe itself refuses, so the park you see here means the promise was
  DISPROVED and a relaunch will not clear it. an out-of-quota backend found
  that way parks `backend_quota` instead — availability, not a broken promise.
  measured before the change: a CLI shipping three versions in one day parked a
  topic three times, each recovery being a human typing the same command with
  no argument changed. do not
  confuse it with `store_fault` — the store is checksummed, so a fault THERE is
  corruption, while a kv file an operator typed is an input; the run-init reads
  are the one place a config fault answers with a plain refusal instead of a
  park, because they precede any stage and there is nothing to resume into.
  this is a workflow/topic input defect, not an agent
  failure. resume: create/fix the missing input, or escalate to the maintainer;
  relaunching before that reproduces the park.
- **plan_changed** — plan hash differs from the split-time pin. the ground moved.
  resume: owner rules (`launch.sh rule <workspace> --slice 00 --text "…"`); the
  ruled resume repins and
  re-enters plan-validate — the decomposition chain re-derives from the new plan
  (done slices stand; the interrupted slice re-derives its premise). never resume
  a slice on a silently moved plan.
- **workflow_changed** — the workflow tree's SHA differs from the topic-start pin.
  resume: relaunch — the relaunch adopts the current tree and repins, with the
  freeze point audited. land workflow changes under the maintenance rule first
  (§7: no live stage, `self-check/check.sh` green — including §7's
  interpretation-stability question before adopting over a frozen topic).
- **backend_quota** — the pane matched the backend's declared
  `sig.quota_exhausted`: model calls are failing for want of quota, not for want
  of work. the session is alive and correct; the resource is gone. the captured
  screen carries the backend's own reset time — read it there, do not guess.
  resume: relaunch AFTER the reset it names — the halt detail carries that line
  verbatim, and the time differs per CLI, so never assume a midnight rollover.
  relaunching before it spawns sessions that are born dead and spends the
  attempt budget on calls that cannot succeed (measured: two such attempts,
  plus a third whose stage clock ran inside the dead window). while this halt
  stands, the launch probe stops trusting its stored pass for that backend and
  re-proves it live, so a too-early relaunch is refused at preflight (exit 4,
  naming the backend rather than the declaration) instead of spawning.
- **backend_overloaded** — the pane matched the backend's declared
  `sig.backend_overloaded` (measured literal: the CLI's `API Error: 529
  Overloaded` banner): the backend is UP and refusing, which is the quota
  situation minus a reset time. the session is alive and correct.
  resume: relaunch on JUDGMENT, not on a clock — nothing publishes a time for
  this state, and the park text says so rather than implying a wait. give it
  minutes, not the hours a quota window needs; the condition is usually
  transient. measured on the episode this halt exists for: before the class
  existed the pane classified `awaiting_input` once the CLI's own retry ladder
  exhausted, so the ferry nudged a client that could not answer and failed the
  attempt as `idle` — twice, ~17 minutes and two attempts of the round's
  budget, ending in a `no_novelty` park on an identical fingerprint. a
  postmortem reading that ledger diagnoses a stalled reviewer and looks at the
  session; the session was fine.
  and the reading BESIDE this one: `FAIL backend_retrying` is the same
  condition caught while the ladder is still running — the loop waited out
  `liveness.retry_grace` and the ladder never cleared. same action.
- **unknown_modal** / **unknown_screen** — the pane shows a modal or state no
  declared signature matches; captured text attached (screen_file in the halt).
  signature rot is loud by design. resume: handle the modal manually via
  takeover (§5) to unstick the session; the durable fix is a
  backend-declaration update (`config/backends/<name>.kv`, maintainer,
  dev-time). never teach the ferry to guess.
- **operator_interference** — injection found text BEFORE the cursor while a
  writable client was attached: a human's half-typed text that must not be fused
  with an injected prompt. resume: attach, deliberately clear or submit your text,
  detach, relaunch. (the same screen with nobody attached is a rendering artifact,
  not a park: it is refused as `composer_occupied` and the caller retries or
  cold-falls-back — a guard may only name what it can see.)
- **operator_stop** — the graceful park written by `launch.sh stop` (or
  SIGTERM/SIGINT to the ferry): the current stage parked between attempts,
  sessions kept for postmortem. inspect: nothing owed — this is the deliberate
  stop you asked for. resume: relaunch when ready (mechanical halt; no ruling
  needed).
- **store_fault** — a store surface failed checksum/parse. fault ≠ absent: nothing
  read it as zero. the ferry also proves every surface's checksum at start
  (`state_verify_all`) and dies here naming each broken surface with its repair
  recipe — a surface corrupted while parked is caught before the run loses
  appends to it. inspect: the named surface files, disk space. repair: verify
  the body is the intended one, then reseal the header (`sum=` must equal
  `tail -n +2 <file> | md5sum`) — and re-derive over ALL surfaces, not only
  the ones that blocked you (a missed append surface keeps losing records,
  loudly, until the next start hard-stops). resume: relaunch; persistent →
  owner + maintainer with the surface file preserved.
- **class_u** — an owner decision is owed. inspect: the question set — and **it
  lives in one of two places, which the reason class does not tell you.** a
  stage that emitted `--halt class_u` owes `slices/<nn>/halt.<n>.md`
  (`templates/halt.md`: why, blast radius, options with for/against, worked
  examples, recommendation — written to be ruled on from its own text, and
  claims-gated at emit); a stage that reached the same park through its own
  VERDICT — `plan-validate` `not_ready`, the `HALT_class_u` routing declared in
  `stages.tsv` — writes no such file, because its owed set is
  `validation_note;handoff`, and its questions ride the record's `detail=`
  instead. so `status <workspace> --halt` (§2) is the first move and reads both
  shapes; the document is the second, when there is one. measured once, live:
  the batched set rode `detail=` complete and rulable, and its completeness was
  the author's choice with nothing checking it. resume: exactly one path —
  `launch.sh rule …`; the stage cannot respawn without the ruling.
- **blocked** — implementer BLOCKED, or external breakage proven by the attribution
  check (red with our commits removed too). inspect: the attached evidence.
  resume: after the blocking fact changes (a ruling, an upstream fix, a spec
  revision) — a relaunch with nothing changed will trip `no_novelty` by design.
  **the §5 case resumes by RULING, not by a revise edge** — `stages.tsv` has no
  impl→revise transition and never did. `rule` writes the authorisation and
  `lib/resume.sh` resets the suspended stage `done`→`failed`, so IMPL re-enters
  carrying `rulings.pending`: the widening is recorded and reviewable, which is
  what §5's ban on SILENT absorption exists to secure. an erratum that forces a
  SPEC change is a different case with no route yet (impl's owed set derives from
  the spec's commit-unit list); zero instances — build it when one appears.
- **disagreement** — a review loop is not converging, by one of FOUR predicates
  the park text names: the severity-trend predicate (two consecutive rounds of
  the same review stage — precheck↔revise or postcheck↔fix — with non-decreasing
  substantive counts AND at least one `repeat` in the newer round, a finding that
  survived the previous round's remediation), the **review round bound**
  (`review.max_rounds` reached with substantive findings still open — the shape
  where every round finds new material), the **decomposition fixpoint** (the
  slices index byte-identical across the last `split.fixpoint_emits` split emits
  while split-check still returns `flag` — the CUT is settled and what is left is
  prose about the cut; `review-standards.md` §10), or the **split round bound**
  (`split.max_rounds` reached while split-check still flags and the index kept
  MOVING — the opposite shape to the fixpoint: a cut that thrashes rather than
  one that froze. it is the topic loop's only other stop, because split runs at
  slice 00 and the slice wallclock does not price 00). inspect: **by predicate,
  and the split is not cosmetic.** for the first two, the park detail names both
  review files and carries the round's new/repeat split; read the later
  review's `## 3. absorption` first — it names which finding each repeat
  continues and the reviewer's own narrowing call. for the FIXPOINT that same
  reading argues the opposite way: the predicate counts no findings at all, so a
  falling count is not convergence to it — read whether the slices INDEX moved,
  and whether the outstanding findings move a boundary, id, binding or risk
  class. for the SPLIT ROUND BOUND the index reading argues yet a third way: the
  cut moved every round, so neither a frozen index nor a falling count is the
  question — ask whether the PLAN can be cut at all as written, because a
  decomposition that will not settle is a plan finding wearing a review's
  clothes. measured: rounds 1→2 went 3→1 substantive with repeat=0, and a pilot
  reading the trend reported a CONVERGING loop under a park raised because the
  cut had frozen. resume: the owner rules continue / split /
  redesign (`review-standards.md` §10) via `rule` — continue discharges every
  predicate for the ruled (slice, stage, round) and the loop advances; split
  routes through the re-slice path (turnover `reslice` → split-check, or
  `launch.sh slice` for a cancel); redesign is a plan change (owner edits the
  plan → the pin trips → plan_changed re-derives the decomposition).
- **push_gate** — landed work awaits push; the topic is COMPLETE. the workflow
  never pushes. this is a terminal marker, not a gate: the owner pushes and is
  done — no relaunch needed. a relaunch is harmless and idempotent (it re-sends
  an undelivered completion page, reports COMPLETE, and exits clean).
- **broken** (terminal) — the watchdog's relaunch budget is exhausted: the ferry
  itself kept dying. full postmortem before anything else: watchdog log, audit
  tail, store integrity. owner + maintainer; relaunch only after diagnosis.

## 4. manual floor — a human as the ferry

all state and artifacts are plain files; the ferry is replaceable by hand:

1. read the stage surface (current slice/stage) — or derive the next stage from the
   last handoff record's verdict via the `stages.tsv` verdicts→next column.
2. compose the prompt: `runtime-docs/templates/prompts/<stage>.<mode>.md` (mode = the
   row's session column minus any `-author`/`-reviewer` suffix — the template
   files are `.cold`/`.warm`; round ≥ 2 reviews use the `.warm.md` round
   template regardless of how you run the session), fill the volatile header (mint a fresh
   nonce — any unique string — and record it in the sessions surface), fill each
   manifest placeholder with the absolute path per the row's manifest columns,
   render absent optional entries as `none (<reason>)`. one header line the ferry
   derives is worth reproducing by hand when the manifest carries a previous
   slice's turnover: re-resolve that document's commit references against the
   PREVIOUS slice's bound branch (`git merge-base --is-ancestor <sha> <branch>`,
   its binding, not the reader's) and say which are no longer on it. a turnover
   is the only artifact handed to a LATER slice, so it is the only one whose
   branch claims can have gone false since it was written — silently, because
   the objects still resolve.
3. run the backend CLI yourself in a terminal with the standard bootstrap
   ("Read and execute <abs-path>/stage_prompt.md") — or paste the prompt into a
   session you opened.
4. wait; then verify the handoff record exists and the owed set is complete
   (`lib/owed.sh`, or by hand: the row's owed column ⊕ the spec's commit-units for
   impl/fix, resolved via the progress ledger against `git log`).
5. route per verdicts→next; halts go to the owner exactly as in §3. write store
   surfaces only through the tools — `record.sh`, `launch.sh`, and (for surfaces
   those verbs do not cover, e.g. the sessions entry of step 2)
   `lib/state.sh set|put|append <ws> <surface> --writer <class>`: the CLI keeps
   the writer-class bug barrier and the checksummed header intact; a hand-edited
   file reads as a store FAULT.

## 5. takeover etiquette

sessions are real tmux panes; takeover is a feature, parks leave sessions alive for
it. rules:

- attach read-only freely (`tmux attach -t "=delivery-<topic>-<slice>-<stage>" -r`);
  capture, never type. sessions spawned since the window-size pin hold their 220x50
  against any client; a session spawned BEFORE the pin still shrinks to the smallest
  attached client with no rebound — restore the declared geometry with the full
  recipe (`tmux set-option -w -t "=<name>:" window-size manual` +
  `resize-window -t "=<name>:" -x 220 -y 50`; the option alone leaves the window at
  the wrong size — measured, on tmux 3.0a, including with a client still attached:
  detaching first is NOT required, and the geometry holds after the client
  leaves).
- if you must drive a session: take it over, do what is needed, and then EITHER let
  the stage run to its own record emit, OR `launch.sh stop` and relaunch cold.
  never hand a driven session silently back to the ferry mid-turn.
- **never leave half-typed text in a composer** — injection checks for an empty
  composer and parks `operator_interference` on anything else; your leftover text
  is what that park exists to protect.
- never type navigation keys into a CLI pane you did not open (`Left`/`Escape` are
  destructive on measured TUIs); plain text + Enter only.

## 6. watchdog honesty, and the optional systemd wrapper

the watchdog classifies ferry exit codes only: deliberate exits (parks, complete)
stop; crashes relaunch within `budget.watchdog_relaunches`, then terminal `broken`
+ notify. **root honesty: nothing supervises the watchdog.** its own death is
visible (the monitor shows watchdog liveness) but not self-healing. if you need
that last layer, wrap it as a systemd user service (sketch — adapt paths):

```
# ~/.config/systemd/user/delivery-<topic>.service
[Unit]
Description=delivery-workflow watchdog (<topic>)
[Service]
ExecStart=<abs>/runtime-scripts/watchdog.sh <workspace>
Restart=on-failure          # crash-only: deliberate exits are clean, not restarted
[Install]
WantedBy=default.target
```

`systemctl --user daemon-reload && systemctl --user enable --now
delivery-<topic>.service`. `Restart=on-failure` mirrors the crash-only contract:
parks exit clean and stay parked.

## 7. maintenance rules (workflow source)

moved whole to `maintenance.md` §1 — the rules for changing the workflow
source: who may edit it and when, what a maintenance commit owes, the
maintenance brief, the harvest's counting format, and the parallel lane.
this file is the OPERATOR's reference and that section is the MAINTAINER's,
and THAT is why it moved: `60-gates`' own-tree cap on reference docs raised
the question and the audience test answered it (`maintenance.md` §1; the cap
is that sweep's own number, not `cap.source_file`). the number is kept so every citation of
`operations.md` §7 still resolves.

## 8. history consolidation (topic close-out; Class C, two keys; push stays the owner's)

proposed by the author at close-out with an old→new map preview; executed only
after concurrence. hard invariants, never violated:

1. backup ref first: `git branch backup/pre-<label> <tip>` — the revert path.
2. adjacent-only squashes, no reorder.
3. `git diff backup/pre-<label> <new-tip>` **empty** — byte-identical content.
4. full gates re-run at the new tip, and **the reading records the SHA it was
   taken at**; subjects re-pass the project regex. a gate verdict is about a
   history, not about a branch name — measured: "full gates re-run at the new
   tip, invariant discharged" was written of a history that a shared-branch
   rewrite had replaced minutes later, and nothing downstream could tell.
5. the trailers `project.kv` declares (`commit.trailers`) preserved on kept
   commits; squashed groups get fresh ones the way the project generates them
   (its commit hook); no trailers beyond what `project.kv` declares.
6. old→new map recorded in `closeout.md`; push stays the owner's.
7. **each new subject covers the union of the diffs it now owns.** invariants
   1-6 are all SHAPE checks, and the byte-identity of 3 cannot see this one:
   the tree is identical by construction, so what a squash can break is only
   ever the message. name the union, or name it generically — never the first
   of several landed changes as though it were all of them
   (`review-standards.md` §9 C4, `commit-messages.md` §2). measured: a squash
   proposed by a close-out named one of the three landed changes its nine
   files carried, and the second squashed subject had no representative at all.
8. **citations the rewrite invalidates are re-pointed in the same session that
   invalidates them.** run `iteration-log/cite-check.sh <repo>` after the tip is
   rebuilt: an entry or validation-debt row anchored on a SHA this rewrite took
   off the branch is now an argument nobody can open. measured over three
   topics and three consolidations — twenty cited commits off the delivered branch, six on
   no ref at all, none of it red at the time.

non-interactive recipe (no interactive rebase in this environment), commits
`C1..Cn` on base `B`, replayed in original order:

```sh
git branch backup/pre-<label> <tip>
git checkout <branch> && git reset --hard B
git cherry-pick <B>..<lastKeptOfRun>          # keep a run of distinct commits
git cherry-pick -n <groupStart>^..<groupEnd>  # squash a cohesive group…
git commit -m "<type>: <one-line story of the group>"
# repeat until the tip is rebuilt, then run invariants 3-5
```

reversal: `git reset --hard backup/pre-<label>`; keep the backup ref until the
owner has pushed and is satisfied.

**and do not delete it on that cue alone.** a `backup/pre-*` ref is often the
LAST resolvable home of commits this tree's durable evidence cites — measured,
thirteen of them across three such refs, none reachable from `origin`. deleting
one after a push reads as routine cleanup and is the single cheapest way to
destroy the basis of an open entry or a closed validation-debt row. run
`iteration-log/cite-check.sh <repo>` BEFORE deleting: beneath its verdict it lists
every cited commit that hangs on a single ref and names that ref. if the one you
are about to delete appears there, pin those commits first
(`git tag -a iterlog-anchor/<sha8> <sha> -m 'cited by …'`) and delete after —
the order is the whole point, since afterwards there is nothing left to pin.

## 9. environment assumptions (Linux and macOS, stated)

every host difference is answered in ONE file, `runtime-scripts/lib/platform.sh`,
and nothing else branches on the platform:

- **process identity and CPU** — a pid's start identity (pid-reuse defense) and
  the process-subtree CPU the watch loop reads. Linux: procfs
  (`/proc/<pid>/stat`), in jiffies. macOS: `ps` (`lstart`, `time`), in
  hundredths of a second — `plat_clk_tck` names the unit, so
  `liveness.cpu_busy_pct` means the same share of a core on both. the macOS
  start identity is second-grained: a pid reused within the same second is the
  one reuse it cannot tell apart.
- **commands BSD userland lacks** — `flock` (fd form), `timeout`, `md5sum`,
  `setsid`: `runtime-scripts/lib/darwin-bin/` holds small perl stand-ins, put
  first on `PATH` on macOS, each covering the forms this tree uses and refusing
  any other by name — so a Mac's behaviour does not depend on what else it has
  installed.
- **formats that differ** — nanosecond clock, epoch → local time, `stat` fields,
  load average, in-place `sed`, a pty for `script(1)`: one `plat_*` function each.

and on both hosts: bash ≥ 4 · tmux with `pipe-pane` (the window-size pin needs
≥ 2.9 — backend-seam.md §4) · same-filesystem atomic rename for the store
(`.runtime/tmp` and `.runtime/state` on one fs) · mkdir-atomic locks ·
epoch-second timestamps. a third host is a third branch in `platform.sh` and a
green `self-check/check.sh` on it — never an assumption.

## 10. logs and store rotation

- `.runtime/logs/<stage>.log` (pipe-pane) grows unbounded within a topic — rotate
  or archive at slice boundaries if disk headroom warns; never mid-stage.
- append store surfaces (ledger, audit, observations) declare rotation caps;
  exceedance is named, never silent. rotation preserves the tail the monitor and
  recovery need.
- `.runtime/` is regenerable machine state: deletable **after** close-out; while a
  topic is live, deleting it destroys attempts history and liveness state — the
  run degrades to cold re-entry everywhere.
- preflight checks disk headroom precisely because a full disk turns store writes
  into faults.
