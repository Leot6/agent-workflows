# config, project adapter, notification, monitor

> Settles configuration (three-level kv fallback, caps), the required project adapter,
> workflow-source rollback, the notification policy, and the monitor.

## 1. Config: four-level fallback, kv format

Format: flat `key=value` (shell-parseable, zero dependencies; tabular data as TSV).
Readability-for-humans is a non-goal (owner ruling); per-concern files are the modularity.

Resolution (most-specific wins; unset falls through; unset everywhere = workflow default,
never an error):

```
config/defaults.kv                                            # workflow level — READ-ONLY at run time
  ⊂ ${XDG_CONFIG_HOME:-~/.config}/delivery-workflow/config.kv # operator/machine level
    ⊂ <topic>/delivery/config/topic.kv                        # topic level
      ⊂ <topic>/delivery/config/slice.<nn>.<agent>.kv         # per-(slice, agent)
```

`lib/config.sh get <key> [--topic-dir D --slice N --agent A]`. Lookup at spawn time; the
resolved snapshot for a stage is recorded in the run surface (auditability), and the
per-spawn resolution — **backend**, model, effort — rides the ledger's `spawn` event.
The assignment is the one thing there that no evidence rests on and that nevertheless
*produced* the evidence: a commit-unit's SHA, its ancestry and the project's gates are
identical whichever CLI wrote them, so the assignment is not a binding and does not
belong in the slices index (`review-and-slices.md` §6) — but a run that loses it has
nothing left to reconstruct the attribution from. Config because it is adjustable and
per-spawn resolved; ledger because it produced evidence nothing else attributes. It
binds **at spawn**, not at slice start: an edit to a running slice's own file takes
effect at that slice's next stage, warm sessions keep what their stage recorded, and
there is deliberately no per-slice snapshot — that would be a second source of truth
about what a slice's assignment is.

- **Parallel safety by construction**: defaults are workflow-tree files (dev-time
  edits only; a topic never writes them); topic/slice overrides live inside the topic's own
  `delivery/config/` — cross-topic pollution is impossible by path. Slice ids are unique
  and never reused (review-and-slices §6), so a (topic, slice, agent) address is unambiguous;
  an override addressing a retired slice id faults loudly.
- **The operator layer is machine-scoped, and that is its point**: what lives there is the
  machine's, not a topic's (the notify transport, first of its class) — it serves every topic
  on the machine and OUTLIVES them, which neither a topic tree (cleaned at close-out — the
  first delivery topic's notify.cmd died with its tree, and the pilot topic never armed one)
  nor the committed defaults.kv (which must never hold a webhook key) can. Outside every git
  repo by construction; topic.kv still overrides it, so a topic can be silenced or re-armed
  deliberately. Same key vocabulary and validation as every other layer (a typo'd
  operator key faults at the door, not silently); the config snapshot names it as a layer and
  marks its absence, so an agent reading "effective config" knows which machine it ran on.
- **Closed key vocabulary**: `schema.kv` enumerates every legal key + type. Unknown key =
  fault, not ignore (a typo must not silently fall through to a default). Stage-dimension keys by name (`stage.impl.timeout=`), agent-dimension
  likewise (`agent.reviewer.model=`).
- **Writers**: operator/pilot only. Agent sessions never write config (no
  self-provisioning loop); a charter may *recommend* an override, a human applies it.
- **Validation rules** (config.sh load): reviewer effort ≥ run base effort (a review's
  depth is never reducible per-slice — v1's supervisor-no-override guard, generalized);
  postcheck stages.tsv row must be cold; referential integrity across
  stages.tsv/schema/backends (self-check enforces the same closure).

Key families (descriptive; `schema.kv` is the enumeration of record): `agent.<role>.
backend|model|effort` (implementer: model|effort — it is a sub-agent, never spawned
directly; reviewer diversity is pure config — bind a different backend/model where
available, and a same-backend+model deployment is named in the audit surface at run
init: the same-model ceiling is deliberate there, never silent) · `stage.<stage>.timeout|budget_attempts` (cold/warm is a stages.tsv column,
never a config key) · `slice.max_*` · caps (§2) · `refine.max_rounds` · `liveness.*`
(poll, heartbeat fresh, quiet/nudge grace, stage timeout, working max age, hard
ceiling, modal acts max — each an independent literal, cross-checked by
rule.liveness_window) · `probe.timeout` · `budget.*` (stage attempts, slice/topic
wall-clock, watchdog relaunches) · `notify.cmd|preset` · `all_cold`.

**A resolver fault is not an absent key** — the store's rule, applied to config.
The distinction needs saying because the mechanics work against it: the driver
reads every key through a command substitution, and a die inside one kills the
subshell while the parent carries on holding an empty string. So the fault
travels as a STATUS and each call site answers it, rather than as an exit the
caller never sees. Measured: a topic.kv violating `rule.liveness_window` made
`budget.topic_wallclock` resolve to nothing, and the run parked
`budget_wallclock` reporting "1s working > s" — a verdict invented from a cap it
had never read, naming the wrong cause to whoever came next. Preflight validates
the file at the door, but config is read live, so the door is not the whole
answer.

**And the answer names the right subsystem.** A faulted read inside a stage
parks `template_error`: these files are the topic's own inputs, which is what
that reason already means (`operations.md`), and the resume is the same — fix
the key, relaunch. The run-init reads precede any stage, so they refuse instead
(no `(slice, stage)` to park on, nothing to resume into). `store_fault` stays
what it is: the store is checksummed and a fault there is corruption. Answering
an operator's typo with the store's exit code named the wrong subsystem to
whoever came next, paged `store_fault`, and spent the watchdog's relaunch budget
re-running a config that could not resolve — the vocabulary rule (§4 of
`state-and-liveness.md`) prices a new reason instead, and none was needed.

## 2. Caps (owner-ruled: workflow defaults, project may override in either direction)

| cap | workflow default | override |
|---|---|---|
| function length | 200 | `project.kv` same-named key, looser or tighter |
| generated source file | 800 | 〃 |
| self-test source file | 1000 | 〃 |
| per-commit diff lines | 500 (`relocation-only` declarable per unit) | 〃 |

The gate always runs and reads the **effective** value; exceedance refuses the emit,
naming the cap, the value, and the source layer (default vs project) — an author-fixable
in-session refusal, deliberately not a park (self-heal-first). File caps are line counts
(language-neutral, mechanical). Function-length enforcement is delegated to the project's
declared tool (e.g. clang-tidy `readability-function-size`); a project declaring none gets
an honest downgrade note at topic start (reviewer checklist item, not a fake gate).
Workflow-internal doc caps (hot card ≤300, reference ≤800) are hard and not
project-facing; topic artifact caps (spec ≤2000, review ≤1500, other topic
artifacts — charters/closeout/turnover/conformance/validation note, which grow
with slice or round count — ≤2000 via `cap.artifact_lines`, plan uncapped)
are config.
Slice budgets (`slice.max_*`) are reviewer-checklist quantities (review-standards §7),
not emit gates — they reach the reviewer through the config snapshot; stated here to
keep the gate/checklist boundary honest.

## 3. Project adapter: `<topic>/delivery/project.kv` (required)

```
repo=/absolute/path/to/your/project/checkout   # REQUIRED
branch=work/my-topic                             # REQUIRED
build=cmake --build build -j
lint=./scripts/lint.sh
test=./scripts/test.sh
acceptance=./scripts/acceptance.sh        # the composite gate (the one double-run)
coding_rules=docs/coding_rules.md
public_api=include/
commit.subject_regex=^(feat|fix|refactor|chore|docs|test): [a-z]   # REQUIRED
commit.trailers=Change-Id                  # e.g. a project whose commit-msg hook adds one
commit.forbid_trailers=Co-Authored-By      # trailers the project bans (comma list)
function_length_tool=clang-tidy:readability-function-size
cap.function=200
cap.commit_diff_lines=500
doc.repo=/absolute/path/to/your/docs/tree         # optional, PAIRED with doc.branch
doc.branch=master
route=planning+delivery — Q1 no: …; Q2 yes: …; Q3 no: …   # optional, opaque, never parsed here
```

Absent file → refuse to start, self-describing (never baked-in assumptions).
Required exactly: `repo`, `branch`, `commit.subject_regex` — the only keys whose
absence refuses (repo lock, owed SHA ancestry, commit gate); every other key is
optional, and an undeclared gate (`build`/`lint`/`test`/`acceptance`) records a
named SKIP at emit rather than faking a pass. The workflow
follows the project's build/lint/test/acceptance and commit conventions verbatim, and holds
none of its own: every convention a topic obeys arrives through this file. The
commit gate reads the convention in both directions: `commit.trailers` are owed,
`commit.forbid_trailers` are banned (case-insensitively — a prohibition an authoring
session can evade by changing case is not one; agent sessions are precisely who add
the trailers a project bans). Shared-branch fields feed the attribution check (`review-and-slices.md` §5).

**`route=` is CARRIED, never read for meaning.** Which lane a piece of work was
routed into — straight to an editor, through this tree, through a planning tree
first — is a decision taken before this tree is launched, and the workflow's whole
interest in it is that it be paired with what the run then cost. It is written in
either of two places, both optional and both the same fact: the plan preamble
(everything before the first section heading — a `## ` line in any indented or
quoted form, or a setext underline — the first line there whose first non-quote
token is `route:`, fenced and indented code blocks skipped, because a pasted
grammar example is not a verdict) and this key. Two readers take whichever it finds, label each with
the source it came from, and NAME a disagreement when both exist and differ
rather than picking one — and they are different KINDS of reader, which is worth
the sentence because only one of them is a program. Close-out's governance report
READS both homes itself, mechanically, and is pinned by `99-routing`.
Plan-validate's copy into the validation note is a duty in the author's role
card: no code performs it, no gate refuses its absence, and it is carried as
validation debt until a live topic exercises it. There is no
precedence to remember and therefore none to drift. It never parses the value:
the vocabulary of lanes is defined outside this tree, by whatever routing rule
the project follows, and a driver that interpreted it would own a rule it cannot
keep current — the `coding_rules=` reasoning below, one level up. The key needs
no `schema.kv` entry (the adapter's vocabulary is its own, and the preflight's
inert-key warning fires on `schema.kv` ∩ `project.kv`, so an unschema'd key
cannot be mistaken for a misplaced config one). Why a second home when the plan
already has one: split pins the plan hash, so a line added to the preamble after
that reads as `plan_changed` and re-enters plan-validate — the adapter is the
home still writable by the person who launches, which is the person who made the
call. **A home has three states, not two**, and the readers keep them apart because
absent-is-not-zero applies to a declaration as much as to a surface: the line or
key is ABSENT; or it is there and its value is EMPTY, reported as `declared, not
filled`, which is a half-done copy and not the same act as never writing one; or
the file is there and could not be READ, which is a fault and is reported as
one rather than as a plan carrying no verdict. Trailing whitespace belongs to
none of them — two trailing spaces are a Markdown line break, so both homes are
trimmed before they are compared, or two identical verdicts would print as a
disagreement. Absent from both homes is a validation-note finding, named like an
absent pin row; none of the three is ever a refusal, because this tree does not
adjudicate routing.

Two rules bound what the adapter can carry, and they point in opposite directions.
**Downward**: the keys hold only what a key can hold — a first-line regex and a
trailer policy. A project's length, body and content conventions live in its own
`coding_rules=` file, which is therefore load-bearing rather than decorative: a
declared path must resolve under `repo=` (preflight refuses a dead pointer) and the
impl/fix manifests hand the file itself to the session that writes the commits. The
alternative — restating a project's prose rules as more adapter keys — makes the
driver the owner of rules it cannot keep current, and the project's own gate the
second opinion rather than the first (the commitlint/gitlint shape: the config
lives in the repo and the runner reads it). **Upward**: no rule the project must declare
covers the driver's own leakage, so the commit gate carries one axis of its own —
a commit message may not name a workflow id (`cu-N`, `DP-N`, a slice id, a path
under the topic tree). Those resolve inside the topic workspace and nowhere else;
the history outlives the workspace, so in the delivered repo they are pointers to
nothing. The same holds for ids the workflow does not mint but hands over through
the manifest — a plan's review-round anchors and flip-gate labels — and there the
rule is deliberately not a shape list: an anchor-shaped token is a candidate, and
the verdict is whether this topic's own planning artifacts name it. A shape list
is what the project's own gate had, and a round number one digit longer than any
it had seen walked through.

**Both doors ask the message, one of them asks the shape.** The whole message
half — the project's subject regex, its required and forbidden trailers, and the
driver's own id axis above — is one derivation (`_gates_message_fails`) asked at
both doors a SHA passes: `record.sh progress` at registration and `gates_commit`
at emit. It has to be asked twice because the doors differ in the price of the
identical defect: `git commit --amend` reaches only the TIP, so at registration
the fix is one amend, while at emit the message is buried under every unit
landed since and rewording it means rewriting the branch above it (which is why
neither door prescribes an amend — both print the fix true for that commit's
position, `_gates_amend_advice`). What a door may ask follows from that: **only
what the session can fix on the spot.** The diff cap therefore stays at emit
alone. Its remedy is re-splitting the unit — a spec-level decision and a rewrite
of landed history — so a registration wall over it would strand the ledger
record of a commit that really did land, with no local move that clears it. The
emit gate can fail the stage over the same defect without losing that record.

The same rule then bounds the message half's own wall, and it took a second
reading to see it: **registration BLOCKS only while the commit is the tip.** A
buried message has the cap's exact shape — the remedy is a rewrite of landed
history, no local move clears it — so past the tip the door records the unit,
names the failure loudly on stderr and in the audit surface, and leaves the
verdict to the emit gate. Walling there would cost twice: the ledger loses a
commit the repo already carries, and an author who cannot pass the wall simply
stops registering, after which emit reports a MISSING cu record and the real
cause is hidden behind it. Blocking is for the moment the fix is one amend;
after that the instrument is a loud record, not a closed door.
Deferred declarations (documented slots, built on demand): `worktree_layout=mirrored-root`,
pre-push guard hook, `doc.acceptance` (docs-as-code link/style gates are industry-standard;
this project's mechanical floor is the spec's per-slice checks, so the slot stays a slot
until a demonstrated need — admission rule (c)).

**The doc repo** (`doc.repo` + `doc.branch`, optional but paired — half a declaration binds
doc slices to a phantom): the second checkout a topic may deliver into, for slices whose
product is shipped documentation. Both keys are validated at preflight exactly like
`repo`/`branch` (a git checkout, a resolvable tip); the pair is what makes `repo=doc`
available as a slice binding (`review-and-slices.md` §6). Deliberately flat and closed at
two: the visible future is code + doc, and a general N-repo adapter block buys nothing this
pair does not (owner ruling).

- **One commit convention for both** (`commit.*` is the project's, not the repo's): a doc
  commit-unit re-passes the same subject regex and trailer policy — so the doc checkout
  needs whatever commit hook the project wires.
- **No gate keys for the doc repo.** The doc repo has no build/lint/test/acceptance
  concept: for a doc-bound slice those four gates record a **structural named SKIP**
  (`doc-bound by design`) and the project's acceptance command is never run there — its
  mechanical floor is the spec's own per-slice checks (owner ruling).
- **Workspace containment**: when the workspace lives inside `doc.repo` (the usual layout —
  `plans/` is the working area), preflight refuses unless that path is git-ignored there.
  An unignored workspace makes every store write dirty the doc tree, and the content-bound
  acceptance/gate pins would churn on every attempt.

## 4. Git rollback (workflow's own source)

The design-doc repo is git (prerequisite landed: whitelist `.gitignore` —
`discussion/` and `plans/` and `**/.runtime/` never committed; the live v1 tree untracked).
Commit granularity: per-feature + a checkpoint at every self-check-green boundary.
Rollback = deliberate `git restore`/`checkout`; guarded (refuse over uncommitted workflow
edits without explicit stash/force). **Runtime never MUTATES the design-doc repo** — it
reads it and nothing else (the subtree pin `workflow_sha`, the launch preflight's
dirty-subtree refusal, the probe's provenance stamp), so every commit, checkout and reset
in this tree is a human's: topic artifacts are runtime output; only dev-time
workflow-source changes commit. Pairs with self-check (detect) — rollback (recover).

## 5. Notification policy

Preserved transport + config'd command, a test notification fired by every launch
preflight, at-least-once delivery with the `notified` flag (state doc §7).

**Pluggable transports (the backend seam's shape, one size smaller)**: the workflow
bakes in NO platform. `notify.transport=<name>` resolves against
`runtime-scripts/transports/<name>.sh` — today `bark`; a new platform is a dropped-in
script plus one config line, never a workflow-source change — and `notify.cmd=<command>`
overrides it outright for adapters the tree does not ship. The adapter contract is
`<adapter> <event> <message>` with honest exit codes (0 delivered · 1 failed — the
caller leaves the notified flag unset and a relaunch re-sends · 2 unconfigured); the
adapter owns its platform and its secret, which lives in the operator config area
(`bark.url` beside the operator config.kv), never in a committed file. The transport's
config home is the operator layer (§1): the channel is the machine's, not a topic's.

**Event vocabulary (closed)**: the 20 park reasons + terminal broken (state doc §4) + positive
`commit.done` (from the progress ledger), `slice.done`, `topic.done`, `spec.ready`.
**Policy** = the `notify` store surface: a preset (`key-points` = parks + broken +
topic.done · `per-slice` = + slice.done + spec.ready · `per-commit` = + commit.done ·
`all`) plus per-event overrides. Hot-read at emit → **runtime-changeable without
relaunch**; adjusted via `launch.sh notify <preset|event=on|off>` — a pilot-legitimate
action (what surfaces to the human is routing-level; steering is not). **Mechanical
predicate**: the decision input is the event type + reason class only — both closed enums; the
message is payload. An event that would need content to classify is a vocabulary bug, fixed
in the vocabulary. Dedup (deferred; slot): collapse same (type, topic, slice, stage) within
a window.

**The last leg has a pager, not a receipt.** rc 0 from the transport proves the page left
the machine and nothing more; the store records when a parked topic was picked up, never
how it was discovered. So the watchdog does not exit on a park: it re-pages every
`notify.repage_interval` while the halt stays unresolved, up to
`notify.repage_max`, then sends one message saying it stopped. `launch.sh ack` writes an
ack row on the audit surface keyed by the halt id (the halt surface keeps its single
writer), which the pager and `status --halt` both read; the pager tests that row's
FRESHNESS, so an ack HOLDS the ladder for `notify.ack_timeout` and it then resumes —
the predicate is "a human has this park", which "an ack row exists" is not, since the
pilot card makes acking a pilot's first move; a relaunch takes the paging
watchdog over and `stop` ends it (the watchdog clears its final-state when it starts
driving and writes it at exit, so "class=parked beside a live pid" means the pager and
nothing else); a completion (push_gate) is never re-paged. The interval sits inside the
measured armed tail of 2–6h and the cap keeps an unattended weekend from becoming noise —
the PagerDuty shape in full: escalate until acknowledged, re-trigger on acknowledgement
timeout. The timeout half was deferred on zero measured instances and is now built — the
instance arrived (a pilot acked 71s after a park; the owner reached it 8h09m35s later,
with six pages suppressed in between).

## 6. Monitor

Read-only observer: reads the store only; writes nothing; **no capture-pane** (cannot
perturb; pane text reaches humans via `.runtime/logs/` and the halt surface's attached
screen text); no input channel — a control surface would be a separate design (the
operator's control surface is `launch.sh`, deliberately CLI not web).

v2.0 ships the **terminal renderer** (`monitor.sh`, poll 2s, `--once` for scripting):
topic/slice/stage, the active slice's **repo binding** (kind/repo/branch — after the
two-repo split, which checkout a slice's commits, gates and ancestry belong to is a
first-class fact, and an unreadable index renders FAULT rather than the code default),
the **slice and stage bars** (one-glance topic geography: the slice bar from the slices
index in id order; the stage bar's set follows the current stage's scope, and its "done"
mark comes from the **ledger's `advance` events, never the attempts surface** —
`round.<s>.<st>` means *entered*, and a parked stage would misrender as done under it,
while `do_advance` writes `advance` only after every park path has exited), **who is
working + what's held + a command for each**: the `agent` row carries the active
session's role·backend·mode plus a census (`· N working · M held`, `· K dead` only when
present), and the attach block lists **every live session** — `▶` marks the active one
(picked by the stage's nonce), each line a **read-only attach command**; a held row whose
recorded pid no longer runs (cheap `kill -0` hint — the ferry's `pty_alive` stays the
authority) is tagged dead and gets a statement instead of a command; recent ledger
timeline (each record's epoch rendered as local clock time — one screen, one time format;
rows truncated to the frame; a long park detail summarizes to ~2 lines in the headline
block with a pointer naming its length and the halt surface — the full text is one
`launch.sh status --once` away), liveness classification, commit progress (cu k/n,
distinct cu ids from the **progress** surface), pending Class-U / halt ("what needs
you"), watchdog liveness, notify policy in effect.

**Every "→ N left" names a criterion that actually fires at zero.** The wait loop compares
CONTINUOUS INACTIVITY to `stage_timeout` and total elapsed to `hard_ceiling` alone, so the
panel renders `idle / timeout` and `elapsed / ceiling` (and `working / max` while the class
is `working`) — never elapsed against the timeout, which a busy stage can never reach.
`watch.sh` publishes `live_idle` / `live_working` for exactly this reason: the quantity the
loop compares is not derivable from the age or the heartbeat age. Rendering the wrong one
was measured twice, the second time misread by a live operator as "this agent will be
stopped in 13 minutes". The same rule covers the runway rows: `attempts N/M → K left` runs
against the budget `check_budgets` parks on (`stage.<st>.budget_attempts`, fallback
`budget.stage_attempts`), and `slice` wallclock against `budget.slice_wallclock`; both
rows are omitted while the attempts surface is absent (absent ≠ zero, fault ≠ absent).
The wallclock rows (slice and topic alike) show **working** time — parked intervals
credited by the resume gate (`parked.<slice>`, `parked_total`) are subtracted, the
same subtraction `check_budgets` makes; a panel billing calendar time would show a
budget the real check never spends, the elapsed-vs-timeout misread one row lower.

It is a **panel, not a dump**: a glyph headline carries the one state that wants the
operator's eyes (`▶ RUNNING` / `⏸ PARKED — needs you` / `✓ COMPLETE` / `✗ CIRCUIT-BROKEN`
/ `○ NOT STARTED`), the park's own rows — reason, detail, the captured screen's tail, and
the command that answers THIS park — sit directly under it, fields align in one label
column, and the ledger is columnised (time · event · slice stage · the record's remaining
fields verbatim; the `v=` schema version is elided as addressed to the parser, not the
operator). Four layout rules are load-bearing rather than cosmetic, each pinned by
`self-check/checks/55-monitor.sh`: **fixed width 74**, never the terminal's, so a captured
`--once` does not vary with who captured it (the one exemption is the whole **attach
block** — every line of it stays copy-pasteable, the id + `(role·mode)` tag sitting LEFT
of the command so the command is the copy target); **color only on a TTY** (and off under
`--no-color` / `NO_COLOR`), because `launch.sh status` pipes this; **minute-coarse
durations and clock**, so a quiet stage renders the same bytes between rollovers; and an
**in-place diff-gated repaint** on change only — a 2s blank-and-refill flickers, and a
panel you flinch away from is a panel you stop reading.

**The per-slice table is not on the panel** (`launch.sh status <workspace> --slices`).
Seventeen slices is a dump, not a panel, so it is a separate small reader over surfaces
that already exist — `slice.<nn>.started` and `parked.<nn>` from attempts, the slice's end
from the ledger's `advance … stage=turnover verdict=done`, its backend from the ledger's
`spawn` event — writing nothing and touching none of the four pinned layout rules. Two of
its rendering rules are load-bearing for the same reason the panel's are. **Both clocks,
both labelled** (`work 2h14m · total 3h02m`): working is what the budget spends
(`check_budgets` subtracts credited park intervals), total is what a human feels, and
rendering either alone reproduces the elapsed-vs-timeout misread one row over. And the
**backend column names the exception, not the norm** — rendered only where a slice ran on a
backend the topic level does not name, so a one-backend topic pays nothing for it. That
column is load-bearing rather than decorative because most-specific-wins has a live
footgun: *changing `topic.kv` does not move a slice that carries its own backend override*.
Slice files should therefore say "this slice belongs on this backend" (a doc-sync slice on
a cheap one), never "tonight, these slices" — anything temporal belongs in `topic.kv` — and
this column is how an operator sees which slices did not move.

**Web assessment** (the deciding input, recorded): a thin variant is genuinely small —
a static HTML page fetching store files client-side over `python3 -m http.server` bound to
localhost (remote = SSH tunnel; auth = none by design), zero server code, zero writes.
Deferred anyway under the minimal-core rule (the only python dependency in the system;
aesthetics don't gate operation). The slot: `monitor-web/` beside `monitor.sh`, deletable
as a unit, reading the same store — no other module may ever reference it. Owner-ruled
deferred with reopen conditions (2026-09-06): the slot opens on the first REAL two-topic
parallel run — every delivery topic to date has strictly serial ledger windows, measured —
or on an explicit owner want; the multi-topic overview is the page's only remaining
unique driver once `peek` carries the look and `status --rounds` the depth, and the first
form when it opens is thinner than any full design: server + rail, depth stays CLI.
