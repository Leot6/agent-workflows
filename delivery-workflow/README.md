# delivery-workflow

Drives small-to-medium implementation work from a **ready plan** to **reviewed, committed
code** through an independent quality gate, **unattended by default** (full-auto). v2 —
the from-scratch redesign of the supervisor-manager-workflow (v1 — superseded,
read-only on the original deployment until its last topic freezes).

Scope: plan → impl → commit. Plans are produced upstream — by `planning-workflow`,
the sibling this tree ships beside when deployed as a pair (this tree also works
standalone against any plan). Inputs are required at run time (a `project.kv` project
context); the workflow ships no project assumptions.

## Status

- **Design**: settled — `design/` (6 documents, owner-reviewed). The design documents are
  the sole authority; superseded working material lives in `discussion/` (deletable,
  untracked).
- **Implementation**: complete and self-tested — `self-check/check.sh` (46 checks +
  drills) is the acceptance instrument; everything it pins is in the tree, and every
  tool it needs but a machine lacks SKIPs by name.

| design doc | settles |
|---|---|
| `architecture.md` | mission, roles, naming, layout, flows, session model, operator surface; **§12 = the one settled-rulings registry** |
| `backend-seam.md` | declarations vs the pty adapter, capabilities, probe, tmux mechanics, nudge |
| `state-and-liveness.md` | the store, records/nonce/stop gate, attempts, park vocabulary, liveness, watchdog |
| `review-and-slices.md` | three-tier assurance, risk classes, A/C/U routing, refine, spec contract, slice granularity |
| `config-and-adapters.md` | config levels, caps, project adapter, notification, monitor |
| `migration-and-acceptance.md` | acceptance discipline, self-check scope, **§6 = the living behavior contract** the suite pins |

## The tree

| region | nature |
|---|---|
| `design/` | settled design of the workflow itself (long-lived) |
| `discussion/` | ALL informal material — deletable as a unit, gitignored, never referenced by finalized docs |
| `runtime-docs/` | read by agents at run time: `cards/` (hot role cards) + protocol (the flow) / review-standards (contracts & checklists) / operations (the operator playbook) / maintenance (changing this tree) / commit-messages (what a subject may say) + `templates/` |
| `runtime-scripts/` | machine-run: `launch.sh` (the one operator entry) · `ferry.sh` `watchdog.sh` `monitor.sh` `probe.sh` (driver) · `derive_report.sh` `derive_cost.sh` (read-only derivations) · `session/` (hook-invoked inside agent sessions) · `lib/` (sourced) · `backends/` (pty adapter) · `transports/` (notify adapters) |
| `config/` | declarations, read-only at run time: `defaults.kv` `schema.kv` `stages.tsv` `notify-presets.kv` · `backends/*.kv` · `profiles/` |
| `self-check/` | workflow-functional regression (dev-time, non-runtime) |
| `iteration-log/` | the learning loop's durable home: one file per mechanism under `entries/`, `INDEX.md` generated, `NOTES.md` narrative — read by review-standards §14, maintenance §1 and the close-out card |
| `intro.html` | the visual introduction — flow, roles, halts and guarantees at a glance; narrates `stages.tsv` (the TSV wins, and 52-vocab pins them together) |
| `overview.html` | a dated evaluation snapshot of one maintenance round (2026-09-05) — history, not current state |

Per-topic runtime lives outside this tree — the two-tree deployment keeps it at
`plans/topics/<topic>/delivery/`, and any workspace directory carrying
`project.kv` works (artifacts in `slices/`, machine state in `.runtime/` — never
committed).

## Vocabulary (locked)

**Roles**: pilot (optional operator, routes — never decides substance) · ferry (mechanical
stage loop) · author (writes spec, drives impl) · reviewer (independent floor) ·
implementer (author sub-agent, executes spec).
**Units**: topic → slice (function-cut, may hold many commit-units) → stage
(`spec → precheck → (revise → precheck)* → impl → postcheck → (fix → postcheck)* → turnover`;
topic-level: `plan-validate → split → split-check → … → close-out`).
**Artifacts**: spec · precheck/postcheck reviews · conformance · turnover · charter ·
ruling · closeout; completion travels as a **record** (store, nonce-authenticated), never
prose.
**Risk class**: low/med/high — modulates review depth, never skips a checkpoint.

## Prerequisites (a fresh machine)

Linux (liveness reads procfs) · bash ≥ 4.3 (`wait -n`, the self-check
runner's parallel job control — the runtime itself needs ≥ 4 for `mapfile`) ·
git · GNU coreutils (`stat` `date` `timeout`) · tmux ≥ 2.9 · `flock`
(util-linux) · awk/sed/grep. Then, in order:

1. **A CLI agent installed and authenticated.** The shipped declarations are
   `claude`, `codex` (`config/backends/`); at least one must be on PATH.
   The shipped *defaults* name `claude` + `opus`. To use another CLI or model,
   point the roles at it in
   `${XDG_CONFIG_HOME:-~/.config}/delivery-workflow/config.kv` (machine layer,
   optional file) or `<ws>/config/topic.kv` (per topic):
   `agent.author.backend=claude` · `agent.reviewer.backend=claude` (+ `.model`
   / `.effort` as needed). An absent CLI refuses at the onboarding probe,
   named, with the record and log paths — never a crash.
2. **Verify the install:** `self-check/check.sh` — every check PASS. Arms whose
   tools are absent (tmux, shellcheck, mawk) SKIP by name; that is clean.
3. **Arm notify if you run unattended.** Without `notify.transport` or
   `notify.cmd` configured, a parked topic pages nobody — every park then waits
   on somebody noticing.
4. **The workspace.** `<topic>/plan.md` must exist before launch (its absence
   is only caught at the first stage spawn, after the watchdog has detached)
   beside `<topic>/delivery/project.kv` — `repo`, `branch` and
   `commit.subject_regex` are the only required keys
   (`design/config-and-adapters.md` §3); build/lint/test/acceptance commands,
   commit conventions, cap overrides, the `doc.repo`/`doc.branch` pair and
   `route=` are optional — undeclared gates record a named SKIP, and `route=`
   is carried, never parsed. Topic names stick to `[A-Za-z0-9_-]`;
   no whitespace anywhere in the workspace path.

## Quickstart

```
runtime-scripts/launch.sh <workspace>            # workspace = the topic's delivery directory
#   (workspace contract: Prerequisites #4 — project.kv beside a plan.md;
#    refuses to start without it)
runtime-scripts/launch.sh rule <workspace> --slice NN [--topic] --text "…"  # answer a Class-U halt (NN = 2-digit slice id; 00 = topic-level; --topic rides every slice)
runtime-scripts/launch.sh stop <workspace>       # also: slice <ws> <id> cancelled|restored (guarded index edit) | ack (pause a park's re-paging for one window) | status (--slices | --rounds | --halt) | notify <preset> | observe --text "…" | peek [role] [--follow\|--attach] (read-only pane view; --attach prints the typing path's command)
runtime-scripts/monitor.sh <workspace>           # read-only panel, 2s (--once | --no-color; launch --attach execs into it)
```

Full-auto halts only for: Class U decisions · implementer BLOCKED · genuine
author↔reviewer disagreement · push. Every park names itself; the playbook per reason is
`runtime-docs/operations.md`.

## Rules for changing this workflow

Git is the rollback path (this repo; deliberate `git restore`, never automatic). ADOPT a
workflow-source change only while no ferry runs a live stage — authoring it is concurrent,
because a worktree on another branch moves neither term of the `workflow_sha` pin, and
the older wording here read as "wait for close-out" to a pilot who then spent a whole run
recording defects it thought it could not act on. `self-check/check.sh` green before
resume; new FAIL-severity checks land as WARN while any run is live. Every mechanism
addition passes the admission discipline (`design/architecture.md` §1): harm named,
non-absorption argued, need demonstrated by a real run. The full maintenance
rules are `runtime-docs/maintenance.md` §1; the self-check discipline is
`design/migration-and-acceptance.md` §3.
