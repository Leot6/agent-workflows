# workflows

A modular home for agent workflow trees. Each workflow is a **pluggable,
standalone module**: copy its directory out and it works alone — its rules,
templates, checks, and scratch space all live inside it, and it carries no
runtime or normative reference to any sibling (planning A§13; delivery
architecture §1). Nothing at this root is required by either tree.

## The workflows

| workflow | phase | entry |
|---|---|---|
| `planning-workflow/` | rough intent → impl-ready `plan.md` | `planning-workflow/README.md` |
| `delivery-workflow/` | ready plan → reviewed, committed code | `delivery-workflow/README.md` |

The boundary between them is a single artifact: `<topic>/plan.md`, produced
by planning, consumed by delivery. Each workflow's own README is its map.

**Hosts**: Linux (Ubuntu/Debian) and macOS, both first-class — bash ≥ 4 and
tmux on either (macOS: `brew install bash tmux`); every other host difference
lives in `delivery-workflow/runtime-scripts/lib/platform.sh`. Both trees'
self-checks run on both hosts in CI (`.github/workflows/self-check.yml`).

## The deployment layer (this root)

Five items live outside both trees **on purpose** — anything inside a tree
that referenced a sibling would break that tree's standalone promise, so the
cross-tree machinery sits here, referencing both trees while neither tree
references back:

- `triage/` — the rule that decides which tree a piece of work enters at all
  (three questions, three lanes: direct · delivery · planning + delivery),
  plus `triage/ledger.md`, the calibration table where a verdict is set beside
  what the run then cost. **Its rows are appended by the maintainer at harvest**,
  from the finished topic's close-out report — and that duty is stated HERE
  because it cannot be stated where it would be most convenient: a tree may not
  reference this root, so no maintenance rule inside either tree is allowed to
  name the ledger. The front door is the only place the two meet. It sits here for the same reason as everything else
  in this list, and one more: a rule that chooses BETWEEN the trees cannot be
  owned by either. The verdict line is carried without being interpreted, but
  the two halves of that are not the same kind of carrying: delivery copies it
  at plan-validate and prints it at close-out, by card duty and by a tested
  reader; the planning tree carries it only incidentally — its plan
  concatenator emits the context file verbatim, and nothing in that tree knows
  the line exists, so a verdict that starts in a planning-side plan reaches
  delivery only if the plan's author carries it across that tree's version
  rounds. Documents only; there is no harness at this root, which
  `triage/README.md` says of itself.
- `twin_diff.sh` — the two trees declare the same CLI backends as "twin"
  declarations (planning `runtime-scripts/backends/` and delivery
  `config/backends/`), promising "recalibrate together or neither". This
  script is that promise's mechanical carrier: it diffs the twins' factual
  halves (composer literal, quota regex, glob-quoting rule) and reports —
  each tree's own probe stays the semantic authority.
- `privacy_scan.sh` — the guard that keeps this repository public. Both trees
  learn from private work, so nothing a real project teaches may enter them in
  that project's words: see *Public and project-agnostic* below.
- `collect_watch.sh` — planning's park-on-dispatch rule (protocol §4.5)
  parks the author after instruments are launched; this watcher polls for
  spawn.sh's `.done` sentinels and notifies (or auto-collects), so a parked
  round gets collected without a human watching. Deployment convenience,
  never workflow machinery: it never edits, spawns, or tears down.
- `slots/` — designed-but-deferred slots: each is a criteria draft, registered
  so the eventual build starts from a written position instead of a mood, and
  built only when a real topic demonstrates the need (admission discipline,
  both trees' §1). `tier.md` is risk-tiered planning depth — it scales depth
  and skips nothing, so it needs no ruling. `single-slice.md` is a fast lane
  for a topic that decomposes to one slice — it would collapse a stage, so it
  is owner-ruled, and it waits on the first such topic's own ceremony reading.
  A slot names the tree that would eventually build it; it is registered here
  rather than inside that tree so a standalone tree carries only mechanisms it
  actually has.

## Scratch space (the three `discussion/` directories)

All are gitignored and deletable as a unit — finalized docs never reference
their content; they are created on demand, so a fresh clone carries at most
the `.gitkeep`:

- `<workflow>/discussion/` — a session's scratch **inside that workflow's
  module** (travels with the tree when copied out);
- `workflows/discussion/` — scratch for **cross-tree** work (the overhaul
  review rounds, architecture discussions, signing notes that span both).

## Public and project-agnostic

The trees are maintained in public and are used against private projects, so
every lesson crosses a boundary on its way in. What may cross is the
**mechanism** — what the workflow did, why, and what now guards it. What may
not is the **project**: company, project, repository, branch, module, path,
host, internal-tool and people names; commit SHAs of a delivered repository;
pasted artifact text; machine paths and accounts. A topic is named by a
neutral alias (`topic-A`); the alias → topic map, and the evidence itself,
stay in the deployment's own private archive. The same holds for
dependencies: a tree reads a project only through that topic's `project.kv`,
never through a convention written into the tree.

Two halves enforce it:

- **writing** — each tree's maintenance rules (delivery `maintenance.md` §1,
  planning A§11) and its iteration-log templates;
- **mechanics** — `privacy_scan.sh`: built-in shapes that are private anywhere
  (home paths, e-mail addresses, credentials, private network addresses),
  plus the words only you know are private, one regex per line, in
  `.privacy-denylist` (gitignored) or
  `${XDG_CONFIG_HOME:-~/.config}/workflows/privacy-denylist`. It runs on
  staged changes (pre-commit), on every commit message (commit-msg), and over
  the whole tree in CI (built-in shapes only — CI never sees your denylist).
  Before a harvest, add the topic's own names to your denylist first.

## Repo conventions

- **Enable the hooks once per clone**: `git config core.hooksPath .githooks`
  (`pre-commit` and `commit-msg` both run `privacy_scan.sh`).
- **Commit messages**: a subject of at most 72 characters; an optional body,
  after a blank line, of at most 8 lines of at most 72 characters — what
  changed and why, the detail stays in the tree. No attribution trailers
  (`Co-Authored-By`, session links, `Signed-off-by`): the author field is the
  attribution. `commit-msg` enforces it, and CI checks every commit. If you received
  these trees as plain files, make them a repository first (`git init`, then
  commit the tree). The delivery workflow's rollback discipline assumes a
  repo — the export alone has none.
- Commits to either tree follow that tree's maintenance rules (planning
  A§11; delivery `maintenance.md` §1): single-purpose, self-check green, no
  edits while a live stage runs.
