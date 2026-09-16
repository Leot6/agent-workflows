# maintenance — the rules for changing the workflow source

what this file governs is the TREE, not a run: who may edit the workflow source,
under what conditions, what a maintenance commit owes, and how the deletion side
is raised. an operator running a topic wants `operations.md`; a maintainer
changing this tree wants this file.

**it is a MOVE, not a rewrite.** every line of §1 below is the line that was
`operations.md` §7, byte for byte. the split was triggered by `operations.md` reaching 794 against the 800 that
`60-gates`' own-tree sweep holds reference docs to (NOT `cap.source_file`,
which is a topic gate — §1 below). What DECIDED it was audience, and §7 was
the separable half by that test: it is the only large section of that file no stage prompt and no role
card cites, because maintenance is dev-time and no stage ever performs it.
`operations.md` keeps a §7 stub pointing here, so its numbering is unchanged and
every existing `operations.md §7` citation still resolves while it is re-pointed.

**§2 arrived the same way and for the same reason.** Every line of it is the line
that was `review-standards.md` §13, byte for byte. That file had reached 785 of
the same cap, and §13 was its separable half by the identical test: of its
fourteen sections it is one of only three that NO stage prompt and no role card
cites, and it is by far the largest of those three — because a closing
verification is performed on the TREE by whoever changed it, never on a slice by
a review stage, while eleven stages carry the whole file in their manifest.
`review-standards.md` keeps a §13 stub, so every existing citation of that number
still resolves; `25-xref` is what holds that true.

## 1. maintenance rules (workflow source)

- **the pin constrains ADOPTING a change, not AUTHORING one, and this bullet
  used to say the opposite.** It opened "change workflow source only while no
  ferry runs a live stage", which reads as *a workflow defect found mid-topic
  waits for close-out* — and a pilot read it exactly that way for a whole run,
  recording defects it could not act on. The pin's own terms say otherwise, and the
  reason is mechanical rather than a permission granted here. Read
  `workflow_sha` to its closing brace: BOTH terms are `git -C "$WROOT"` — the
  committed one is `rev-parse "HEAD:<prefix>"`, the subtree object on the branch
  `$WROOT` has checked out, and the dirty one is `status --porcelain -- .`,
  dirt in `$WROOT`'s own directory. A linked git worktree is a different
  directory on a different branch, so a maintainer committing there moves
  NEITHER term. This is the same asymmetry the next bullet already relies on for
  sibling trees, applied one step further in.
  So: **authoring is fully concurrent with a live topic** when it happens in a
  worktree or any checkout that is not `$WROOT`. What must wait for no live
  stage is **adoption** — merging into the branch `$WROOT` has checked out, or
  editing `$WROOT` directly — because that is what the pin sees. The
  workflow-SHA pin makes any drift a loud park, and the deliberate relaunch
  adopts + repins with the freeze point audited (`operations.md` §3,
  workflow_changed — this section was moved out of that file, so its own
  section references point back there, not at this document's headings).
- **and there is no lane to route such a change into: a delivery topic cannot
  host a change to THIS tree.** the reason is mechanical rather than a
  preference. `launch.sh` refuses a dirty workflow subtree at the door
  (`status --porcelain -- .` under `$WROOT`), and every stage re-derives
  `workflow_sha` = `HEAD:<prefix>` plus that same dirt — so a topic whose
  commit-units edit `delivery-workflow/` dirties its own pin at the first unit
  and parks itself `workflow_changed`. THE ASYMMETRY IS THE USEFUL HALF: both
  terms are scoped `-- .`, so a sibling tree, the deployment root and its
  scripts are explicitly NOT this tree's dirt, and work on those is an ordinary
  project a delivery topic can run. What changes this tree is a maintainer
  session under the rules in this section.
- before adopting over a frozen topic, ask: **does the new tree change how
  EXISTING artifacts or records are interpreted** (template parsing, record
  schema, owed derivation)? "a new tree only affects future stages" holds only
  while interpretation of the past stays stable; an interpretation change needs
  its migration note landed before the relaunch.
- **what governs the SIZE of this tree's own documents.** Not
  `cap.source_file=800` — that is a TOPIC gate, `gates_caps` over a workspace's
  files. The real enforcement is `60-gates`' own-tree caps sweep, which carries
  its own hardcoded numbers: cards <=300, `runtime-docs/*.md` <=800,
  `runtime-scripts/` <=800, `self-check/` <=1000. The three places that record
  the `operations.md` §7 and `review-standards.md` §13 splits cite
  `cap.source_file` as what forced them; they name the wrong mechanism, and are
  corrected to name this sweep.
  **The 800 on reference docs is not a number to raise, and the reason is
  specific to what these files are FOR.** All eleven rows of `stages.tsv` carry
  `STANDARDS=review-standards.md`, so that file rides every stage prompt: its
  size has a per-prompt cost `maintenance.md`, which no manifest carries, does
  not have. A cap on the one doc every agent reads is doing its job precisely
  where it should, and loosening it buys headroom by making eleven prompts
  bigger. The sweep gives `self-check/` 1000 for the opposite reason — test
  files grow with coverage and nobody reads them at runtime.
  **Nor is splitting automatic.** A section leaves when its AUDIENCE differs —
  that is what actually decided §7 and §13, both maintainer content leaving
  files the review stages perform. Where no such audience exists the split is
  bookkeeping: moving §2 (claims tables, the largest section) out of
  `review-standards.md` would mean adding the new file back to all eleven
  manifests — the same text, two files, a new manifest key, nobody's reading
  reduced. When neither test is available, the addition earns its lines or does
  not land.
- **workflow source is changed by a COLD maintainer session** — no lineage from
  any session of the topic it harvests, re-deriving from the artifacts and the
  store as a reviewer stage does. owner-ruled; the reasoning and the ceiling
  live once, in `design/architecture.md` §7 with the rest of the session model.
- full `self-check/check.sh` green before any resume that follows a maintenance
  hold — and green **before each commit**, as a step of its own: a commit
  issued in the same breath as the wait is a commit that lands on red. green
  means every check PASS and the summary's `tree: unchanged` line — a verdict
  about the checks, not about the schedule they ran under (owner, 2026-08-22).
  **READ THE WHOLE VERDICT. Never `tail` it, and never pipe it through a
  filter.** This cost three rounds a red nobody could diagnose: one maintainer
  tailed the output; the next — holding that warning — piped it through
  `grep -E 'summary|^FAIL|…'`, which ate the `FAIL:` line while matching an
  `ok:` line that happened to contain a check name; and the third, holding BOTH,
  tailed a whole-suite run on 2026-09-09 and lost a `watchdog` red at loadavg
  32. The letter said "never tail" and a filter is not a tail, which is how a
  rule that needs you to recognise the moment fails three times. So the rule is
  the SHAPE: the runner's stdout goes to the terminal unmodified, and anything
  you want to search you search in the copy you already have.

  **And since 2026-09-09 there is a copy, because a rule that has failed three
  times to the same reader-side habit needed a remedy that survives the habit.**
  `render` always printed the whole failing log — the runner was never the
  quiet one — but the loop then deleted it (`rm -f "$log"` serial,
  `rm -rf "$ptmp"` parallel), so a filtered terminal really was the last copy.
  Now a FAILING check's log is copied to a `dwsc-failed.*` directory under
  `TMPDIR` and the path is printed in the SUMMARY — chosen there deliberately,
  because the end of a run is the one part a `tail` keeps by construction. A
  green run creates nothing, the directory is never inside the tree (a run must
  still read `tree: unchanged`), and the keep is BOUNDED — `SC_FAILDIR_KEEP`
  (10), pruned oldest-first at creation, because a copy that outlives the run on
  purpose is a leak without a ceiling: 78 directories accumulated in the session
  that wrote the mechanism. `98-report` pins all of it, including the
  announcement's guard and what the prune must NOT touch. This does not soften the rule above: a kept log tells
  you what failed, and the terminal you did not filter tells you what else was
  happening at the time.
  `--jobs 12` is the gate, calibrated on a 32-core machine — owner's choice, so the
  machine stays usable for everything else while it runs (peak loadavg ~5;
  measured after the 2026-08-22/23 optimisation rounds: 20s, the wall being
  the slowest single check since checks launch longest-first; serial 360s,
  measured once), **and since 2026-09-02 it is also the DEFAULT** — this
  paragraph called it the gate while a bare `check.sh` quietly ran the other
  one, which is how a maintainer spent a session reading serial seconds as the
  gate's. serial is the same verdict one
  check at a time, kept for one use — reproducing a red without concurrency in
  the room — and asked for by name, `--jobs 1`. the two maintenance quantities
  are COLLECTED from the per-check seconds in either mode — one renderer, both
  paths — and are COMPARED only under `--jobs > 1`, because both caps are
  calibrated on that schedule and a serial run costs ~2x per check: their sum
  is the tax (`maintenance.suite_cap`) and their max the floor
  (`maintenance.check_cap`). a serial run says so in a NOTE rather than going
  quiet, since a suppressed comparison must never read as a passed one. the
  row count behind `maintenance.vd_open_cap` is mode-free and always compared.
  the serial WALL is not the tax: the same checks summed 544s serial against
  ~350s at `-j12`, because one busy core on this box's powersave governor runs
  ~3 GHz while twelve boost past 5 — a serial wall measures power management as
  much as work. both modes label their output. isolation is per check — each
  owns its temp dirs, and every tmux user mktemps its own server — so what
  concurrency spends is timing margin, not safety; and the runner measures that
  rather than stating it: `tree_snapshot`/`tree_verdict` in `check.sh` hash
  every entry of the workflow tree before the first check and after the last,
  and a difference voids the run (exit 1, the paths named in the summary's
  `tree:` line) — which is also what makes "do not edit the tree while the gate
  runs" a mechanical rule rather than a habit. that margin has been seen to run
  out, and the case is worth carrying because the diagnosis moved: a `-j12` run
  had 75-watch's idle-noise arm report `FAIL timeout` instead of `FAIL idle`,
  and it was read as a concurrency effect because the serial suite had passed
  the same arm at a HIGHER loadavg. the arm was then measured directly (a driver
  that stretches each loop iteration by a fixed amount): its intended exit, the
  nudge ladder, lands at about 6 + 1.6x the stretch, against a fixture
  `stage_timeout` of 6 — so a stretch of ~2s is enough to lose the race, from
  any cause, and a serial run at loadavg 8.7 reproduced it. the wait loop now
  reads time through two seams (`_wt_now`/`_wt_sleep` in `lib/watch.sh`) and
  75-watch runs on a virtual clock, so that class is retired inside that check;
  the LESSON stands for every other: a fixture whose deadlines sit seconds apart
  measures the machine, and concurrency is one of several ways to move the
  machine. a red under `--jobs` is diagnosed like any other, and the first
  question to ask of one is still whether it is a timing arm that thin — the
  second is whether serial reproduces it under load, because if it does,
  concurrency was never the cause. serial is the diagnosis form, never a
  re-run-to-green; on a small machine it is simply what `--jobs` degrades to,
  with the same verdict.
- the commit gate is **every check that can SEE the change** — `check.sh
  --changed` decides it, so the decision is code and not a habit. it recognises
  the **formal doc region** (`design/`, `runtime-docs/` outside `templates/`,
  `README.md`, `discussion/`) and treats every other path — including one it has
  never seen — as driver-side, because a list of what is provably inert stays
  honest as the tree grows while a list of dangers goes stale in silence. a
  doc-region change gates on the checks that READ that region (derived, not
  listed: `grep -l 'design/\|runtime-docs/' self-check/checks/*.sh`) — ~10s
  against the full suite's ~20s at `-j12` (360s serial), of which
  the drills are the floor (real tmux, real panes; split per chain, and
  skipped only when blind to the change). anything else — a runtime
  script, a config value, a check, a parsed template, a brand-new file
  untracked by git, an unfamiliar directory — owes the whole suite.
- a workflow-source change that adds or extends a mechanism owes the closing
  verification of its class (`review-standards.md` §13) before it is called
  done: here the "fast subset" is every check except the drill, and a mutation
  surviving that subset is confirmed against the drill rather than declared
  uncovered. the exhaustive pass runs once, on the finished mechanism.
  **its review unit is the COMPLETE TREE, never the diff, and the suite is a
  PRECONDITION rather than the review** — a green suite catches a broken
  reference and never a wrong idea, and a tree whose printed claim is false is
  exactly what a green suite looks like. so what decides that such a change is
  done is §13's second instrument, the reading that samples USE: run it over the
  artifacts that already exist, walk the loop on a concrete topic, re-derive its
  own figures from the store, or ask what no longer earns its cost.
  **WHO performs that reading follows the same table, by row.** the two lightest
  rows — text/docs only, a fix inside one existing mechanism — are the
  maintainer's own to read. the two heavier rows, and the row that cuts across
  them, owe a reader carrying no lineage from the maintainer session: a
  mechanism gaining a dimension, a rule or a door; a new mechanism or one whose
  shape changed; anything that writes a number or reads artifacts that already
  exist. that is not a chosen boundary, it is where this tree's own defects
  landed — a printed boundary that was false, a rule written and broken inside
  one change, an enumeration that went short.
  what is ENFORCED is the disclosure, never the reader: no program can see who
  read, so the record carries THE CLASS CLAIMED, WHICH READING discharged it,
  and whether that reading was self-performed — beside the `loadavg` line below,
  in the same breath and for the same reason. three things that record must
  survive, because with a self-assigned class the cheap branch is always
  available: writing the class down is what makes a wrong one LEGIBLE rather
  than invisible; the class is of the change to the MECHANISM, assessed when it
  is called done, never of each commit that builds it — otherwise a heavy change
  becomes four light ones and owes nothing, and §13 already scopes its
  exhaustive pass the same way; and a line that says "reviewed" names no reading
  and discharges nothing. a self-performed reading is a real reading and is
  often the only one available; what it may never do is read as an independent
  one, and "none was available" is an excuse rather than a fact — the record
  says self-performed and stops. **a quiet reading is evidence about the reading
  run, never about the tree.**
- record `loadavg` with every self-check run; **the loaded machine is the operating
  baseline** — a check that only passes idle is not green. a red is **diagnosed,
  never re-run until it happens to pass**; a re-run campaign spans both load
  conditions and says so.
- new FAIL-severity checks land as **WARN first** while any ferry is live; they
  harden to FAIL at the next quiet window. the rule's letter says "checks" and
  its reason covers more: a new ARM inside an existing FAIL-severity check
  carries the same live-ferry risk (a red is a red to whoever gates on it), and
  is owed the same WARN-first thinking when it is not provably deterministic.
- a fix unexercised by live traffic gets a row in `self-check/validation-debt.md`,
  closed only on firing evidence (the fixture fired red before the fix, or the
  guard fired in a real run).
- a commit that lands or adopts a **promoted mechanism** writes or updates its
  `iteration-log/entries/<id>.md` **in the same commit** — the head block
  (status · hook · anchors · landing) and the landing note — and regenerates
  `INDEX.md` with `iteration-log/gen-index.sh` (the INDEX is derived, never
  edited; `97-iterlog` reds a stale one). The early path; harvest (close-out
  hands the owner the naming, the maintainer moves entries) still does the
  bulk. Same reasoning as registering a commit-unit while it is still the tip:
  the entry costs a few lines while the evidence is in hand, and the topic tree
  that holds the evidence is cleaned after its close-out — what has not reached
  `iteration-log/` by then is gone. A landed mechanism with no entry is
  invisible to the two-anchor judgment (`review-standards.md` §14), and
  `97-iterlog` cannot see it: that check reads the entries against INDEX, never
  against what the tree actually grew. A closed entry keeps its file (git
  history is not a home); the narrative — harvest notes, rulings, the
  `harvest-completion:` ledger — is `iteration-log/NOTES.md`.
- **a count in a maintenance message or a durable-home entry carries the command
  that re-derives it, and that command has been RUN.** This is the same trade
  `review-standards.md` §14's harvest rule makes and for the same reason: a
  FORMAT cannot be satisfied without doing the work, an instruction can be nodded
  at. `maintenance.md` §2's first instrument already says *state the range and
  the command instead, and let the reader count* — this is that sentence made
  into a shape rather than left as advice, because it was quoted in the very
  messages that violated it.
  Two shapes, both measured on this tree's own maintenance rounds rather than
  imagined. **A number gets its command beside it**: five independent reads over
  one round returned false figures every time, including a census of the corpus
  written into that corpus, and a total that had been true two commits earlier.
  **A sweep gets its command AND its output**: a commit claimed *"swept the
  class, four hits, none left"* and printed a `grep` that returns zero hits as
  written — plain grep is BRE, its `|` are literal — and that could not have
  reached two of the four entries it fixed. Printing the output is what makes
  running it unavoidable.
  The generalisation this refuses by construction is the one that recurs:
  **checking a sample and writing the conclusion for the whole.** Measured twice
  in one commit — five entries of twenty-five, four entries of a hundred
  forty-four — the second of them inside the paragraph criticising the first.
  No check enforces this and none can: a commit message is not in the tree, and
  the maintenance action has no workflow entry point (the bullet below). The
  defense is the format, and it holds only as far as the maintainer types it.
  **What the rule does NOT reach, named because otherwise this section
  contradicts itself.** The bullet above REQUIRES `loadavg` with every
  self-check run, and no command re-derives a loadavg: the run is over. The same
  is true of the per-check seconds. The two are different things and the rule
  means only the first. **A COUNT is of a durable artifact** — someone can open
  the thing and get the same number, so a wrong one is a false claim about
  something that exists, and the command is what makes doing the work
  unavoidable. **A READING is of a transient event** — nobody can reproduce it,
  including the person who took it, a second later. Demanding a re-deriving
  command of a reading asks for what no one can supply; an independent reader
  hit exactly this and marked every `loadavg` line UNCHECKABLE, correctly. So a
  reading carries what was measured and when, and owes no command. What keeps it
  honest is that it is written at all, and that a maintainer who fabricates one
  can only misdescribe the suite's cost: the WARNs fire at run time from the
  runner's own arithmetic, never from the message.
  **Keeping it is settled by the corpus, not by taste** (owner-ruled
  2026-09-09). `check.sh` writes nothing outside its temp dirs, so the
  repository holds no run log and the commit messages ARE the record:

      $ for h in $(git log --reverse --format=%h -- <workflow>/); do
      >   git log -1 --format=%B $h | command grep -oE 'checks sum [0-9]+s' | head -1
      > done
      59 commits carried one — the corpus this settled on is the pre-reset
      history (this repository's log restarted at a single init commit,
      2026-09-14); the reading method, not the corpus, is what the rule keeps.
      Median per day, the one `--jobs 1` run excluded by
      its own line: 2026-09-04  232s (n=21, 219-244) · 2026-09-08  294s
      (n=19, 289-301) · 2026-09-09  296s (n=14, 291-305).

  A +27% step between the 4th and the 8th, tight on both sides of it, against
  `maintenance.suite_cap=360`: 64% of that budget spent then, 82% now. That is
  the reading the cap exists to produce and it exists only because the figure
  was printed. Dropping it would not make the tax verifiable — it would delete
  the measurement.

- **a maintenance commit introduces no token that only the working material
  resolves.** Test, and it is the whole rule: *remove the tag — does the
  sentence still stand?* `standing-watch machinery — 5 scripts, W-9/W-10` does;
  `a cap that names the wrong thing (r5 M3)` does not, because the sentence had
  already said it and the tag adds only a pointer into a deleted session. Write
  what the decision WAS, not where it was made (the kernel's submitting-patches
  rule, which `design/architecture.md` §12 already applies to delivered commit
  messages — it binds this tree's own comments identically). `discussion/` is
  deletable as a unit and `README.md` §the tree says finalized docs never
  reference it; `90-provenance-tags` catches the shapes it can, and a shape it
  shares with a live in-tree namespace it can never catch — measured, so this
  rule is the defense, not the sweep.
- **a source comment carries the contract and a pointer, never the chronology.**
  under `runtime-scripts/` and `config/` a comment states what must hold and why
  it holds, then names the entry that carries the evidence (`see iteration-log:
  <entry-id>`); the date it was measured, the topic it was measured on and the
  number of rows read live beside that entry, where the harvest re-derives them
  and where one correction reaches every reader. the mechanical tell is a date
  token in a comment line, and `96-comment-chronology` refuses it. why a rule
  and not taste: the same fact written in a code comment, a design doc, an INDEX
  row and a VD row is four places a correction must hit, which is the drift
  shape this tree has measured most often; and comment history is what fills a file to its cap
  — three reference files reached theirs in one round on some sixty lines of
  rule text, with 40% of runtime-scripts' non-empty lines being comment. moving
  a narrative out is a MOVE: a comment is sometimes the only home a measurement
  has (measured on `derive_report.sh`: four of its header's narratives resolved
  nowhere in `iteration-log/`), so the fact lands in an entry before the
  comment shrinks to its pointer. The standing duty is the comment SHARE, not
  only the dated lines: `96-comment-chronology` sees a date, never a narrative
  written without one.
- **the maintenance brief** (the deletion side's channel): when a self-check
  summary prints a maintenance WARN — the SUM of per-check seconds over
  `maintenance.suite_cap` (never the wall, which -j12 makes a schedule reading),
  the slowest single check over `maintenance.check_cap`, or open VD rows over
  `maintenance.vd_open_cap` — the maintainer raises ONE brief
  to the owner: split/slow the suite, or calibrate the caps. WARN thresholds are
  visibility, never gates — no forced trade; the owner's judgment is the
  exemption mechanism (a static exemption list would be a second home for the
  judgment and would rot).
- **a gate is retired by a person noticing its defect class is gone, never by a
  window counting zero FAILs.** A third channel used to sit beside the two
  above: gates reading zero FAILs across N topics fed a removal brief. It was
  retired 2026-08-31 with its config key, and the reasoning is the load-bearing
  part, because the shape recurs. **A zero-FAIL reading is identical for a dead
  gate and for a working floor** — a gate nobody violates because the rule
  reached the authors reads exactly like a gate that cannot fire — so the window
  never decided anything: three decision points (2026-08-24, 08-29, 08-31), three
  identical answers, zero gates retired, and the 08-29 ruling's per-gate
  reasoning falsified two days later by `stamp_freshness` firing three times.
  The half of the question that IS mechanical — *can this gate fire at all?* —
  is answered by the suite, for free, at every run: **every `gates_*` function
  owes at least one red-proving assertion** (`assert_rc 1 … -- gates_<name>`),
  floored in `60-gates`. A gate with a red-proof and no live FAIL is a floor and
  stays; a gate nobody has shown can fail is the only mechanical finding there
  ever was. What this deliberately does NOT cover is a gate that can fire whose
  defect class has gone extinct — unmeasurable from attestation counts, and left
  to a human noticing, which is what actually happened all three times.
- **the harvest counts its records, and the count is a FORMAT.** the tree-root
  INDEX has always made the test mandatory — `grep -c '^v=1'` on the topic's
  observations surface must equal the records carried into rows — and nothing
  checked that it had been RUN, so one harvest carried 2 of 9 and stated no
  count, hiding a two-anchor promotion trigger inside the five it dropped. each
  harvest now writes a `harvest-completion:` line (harvest, topic, records,
  rows, stamps) into the harvest ledger in `iteration-log/NOTES.md`, and
  `97-iterlog` sweeps it both ways against the generated INDEX's rows.
  the check proves the count was DECLARED, never that it is TRUE — the surface
  is in a topic tree the suite cannot reach — so truth stays the maintainer's,
  at harvest time, while the tree still exists. that is the whole division: a
  format cannot be satisfied without doing the count, an instruction can.
- rollback of workflow source is deliberate `git restore`/`checkout`, guarded —
  never over uncommitted workflow edits without an explicit stash/force. runtime
  never MUTATES the workflow's repo: it reads it and nothing more — the subtree
  pin (`workflow_sha`, `rev-parse HEAD:<prefix>` + `status --porcelain -- .`),
  the launch preflight's dirty-subtree refusal, the probe's provenance stamp.
  every commit, checkout and reset in this tree is a human's.
- **a checkout with other writers makes maintenance additive.** the workflow
  source can sit beside its siblings in one repo, developed in parallel (on the
  originating deployment one day landed ~200 commits, nearly all of them a
  sibling's — the number moves by the hour). so: stage
  by subtree (`git add -A <workflow>/`), land a fresh commit each time, and never
  `--amend`, `reset --hard` or rebase a branch someone else is landing on.
  `--amend` rewrites whatever HEAD **is** at that instant — not the commit you
  had in mind. measured once, here: HEAD had moved between the commit and the
  amend, and a sibling's message was replaced by ours (their content survived in
  the tree; recovery was `git reset --soft <their sha>`, then a fresh commit of
  our own). `git log -1` before and after catches it, but only as reliably as the
  eye; when a rewrite is genuinely owed, make it a compare-and-swap — capture
  `old=$(git rev-parse <branch>)`, build the new tip, land it with `git update-ref
  refs/heads/<branch> <new> <old>`, which refuses outright if the branch moved
  (the local form of `push --force-with-lease`).
  this rule is prose and not a gate for a reason worth stating exactly, because
  the tempting reason is wrong: it is NOT that the runtime keeps away from this
  repo (it reads it — bullet above). it is that **the maintenance action has no
  workflow entry point at all**. the actor is a shell session; no workflow code
  runs between the edit and the commit, so any mechanism would have to be one the
  maintainer volunteers to route through — the same voluntary compliance as the
  rule, with more machinery to keep current. the one thing a machine does enforce
  here is downstream: an uncommitted maintenance edit refuses the next launch
  (preflight, `operations.md` §1). where a driver already stands the invariant IS
  mechanical —
  `_gates_amend_advice` computes it for commits in the project repo, where
  amending a buried commit is the identical mistake.

- **the parallel maintenance lane: an A-class fix does not queue behind the topic
  that found it.** topics surface workflow defects mid-run, and every one of them
  used to wait for close-out — which makes the evidence colder without making any
  reader colder (the COLD ruling above binds lineage, not timing; evidence on disk
  decays — logs get rotated, topic trees get cleaned at close-out — and the same
  lineage-free reading done while the evidence is still there is strictly better).
  what splits the queue is what a fix DEPENDS on, not when it was found:
  - **A-class — self-sufficient**: grounded in artifacts already on disk (a crash,
    a wrong number, a missing guard, a characterised misread). makeable now;
    waiting only decays the evidence.
  - **B-class — outcome-dependent**: needs the topic's own close-out report,
    learning harvest, live-traffic VD closures or threshold calibration. not
    makeable — the evidence does not exist yet; that is not inefficiency.
  the orthogonal axis that decides LANDING is the adoption test above ("does the
  new tree change how EXISTING artifacts or records are interpreted?"):
  **ADOPT-SAFE** (additive or doc-only; nothing on disk is re-read differently)
  merges at the next qualifying park; **ADOPT-BLOCKED** (record schema, template
  parsing, owed derivation) owes its migration note first and does not merge while
  the topic runs. an item can be makeable now and blocked to land — the two axes
  are independent, and classing it on one axis alone is how a schema change ends
  up scheduled for a park it must not land in.
- **making a lane change is concurrent by construction; adopting it is a separate
  act.** the lane is a `git worktree` on its own branch (`wf-<name>`): the pin's
  two terms (`HEAD:<prefix>` and `status --porcelain -- .`) both evaluate inside
  `$WROOT`, and a linked worktree is a different directory on a different branch
  (git refuses two worktrees on one branch), so maintainer commits there are
  invisible to a live topic — which keeps executing the frozen tree under `$WROOT`
  by absolute hook paths. a branch switch would move the live checkout's working
  tree (instant `workflow_changed` park) and a `cp -r` copy abandons VCS; the
  worktree is the one shape that is both isolated and mergeable. **commit early in
  the worktree — the branch is the durable queue** (`git log master..<branch>` is
  the outstanding list), the worktree directory is a consumable. one check after
  the first commit: `core.hooksPath=.githooks` is a RELATIVE path and resolves
  inside each linked worktree, so confirm the commit carries a Change-Id — a
  silently skipped `commit-msg` hook in a linked worktree is a known trap here,
  and a batch of Change-Id-less commits only surfaces at merge time.
- **every owner park is a landing window, but not every park qualifies.** the
  watchdog never restarts a park, so nothing pulls the topic back up mid-landing;
  the interruption the window lives on is already paid for. the classes are a
  RULE, not a list to grow stale: **disqualified** are the parks where landing
  would interleave a second variable into an open investigation or a refused
  adoption — `broken` (postmortem first — the tree itself may be the cause),
  `store_fault` (verify → reseal, without a second variable interleaved),
  `stall_mismatch` (integrity, not liveness); and `backend_quota` plus the other
  parks whose adopting relaunch is refused or blocked until an external
  condition clears (`backend_overloaded`; template/config faults; an unanswered
  ruling) share one shape — **merge is fine, adoption defers**. the owner-decision
  parks (`class_u` / `blocked` / `disagreement` / `plan_changed` / `no_novelty` /
  `budget_*` / `operator_stop` / `push_gate`) are full windows. the fault-class
  parks — `dead` / `idle` / `stall_record` / `owed_miss` / `unknown_modal` /
  `unknown_screen` / `operator_interference` — sit on broken's side of the rule
  unless their diagnosis is already closed: each is an open investigation (a
  screen the declared signatures could not classify — whose subject may be the
  very tree about to be landed; a record/schema question; a human typing in a
  live pane), which is exactly the "second variable into an open investigation"
  the disqualified class exists to keep out. `workflow_changed` is the adoption
  door itself: one open means a merge already awaits its relaunch — finish that
  adoption before landing anything else into it.
  landing sequence: `launch.sh ack` → merge to master → rerun the suite **green on
  the landing tip** (not only the worktree tip) → relaunch → the `workflow_changed`
  park that follows is the designed adoption door, not a fault → relaunch again to
  adopt and repin. on a ruling-gated park the sequence stalls before the pin check
  (`resume_halt_gate` runs first and exits on an unanswered ruling), so: merge and
  green now, adopt at the first relaunch after the ruling. maintenance stays
  additive per the bullet above — never rebase a lane branch someone else may land
  on.
- **the lane's three measured pits, carried from the round that walked it.** ① the
  per-commit suite runs BESIDE a live topic's agents, and a maintainer's tree is
  dirty by construction — a red under load is diagnosed with `--jobs 1` per the
  bullet above (serial is the diagnosis form, never a re-run to green), and the
  first question for any red is still whether it is a timing arm that thin. ②
  `15-locks` has fixtures that launch against the tree under test, and a dirty
  tree reds them on the dirt instead of exercising the refusals they pin (measured,
  in that check's own header) — they already run against a committed shadow tree,
  and any change touching that shape of check must keep them there. ③ the lane's
  checks and the live topic cannot collide on locks: the host lock is
  per-workspace (`state_host_lock_path` — the name says host, the path says
  workspace), and every drill uses its own scratch workspace. the whole round in
  one line: observe in the topic (the pilot's observation duty), make in the
  lane, land at the window.

## 2. closing verification (a change that adds or extends a mechanism)

the checks written while fixing prove the defect was real. they do not prove the
rule is **pinned** — that a later edit breaking it would be caught. the five
steps below each produce a mechanical output, not a judgment: 1–2 ask whether
the code is right, 3–5 whether anything would notice if it were not.

**what a change owes** (cost rises steeply; pay it where it buys something):

| the change | owes | typical cost |
|---|---|---|
| text/docs only | nothing here — the doc gates and the §-reference sweep cover it — UNLESS it carries a figure, which the last row covers | — |
| a fix inside one existing mechanism | 1 + 2 | minutes of grep and reading |
| a mechanism gains a dimension, a rule, or a door | 1–4 | one injection per claimed property |
| a new mechanism, or one whose shape changed | 1–5 | one check-subset run per decision |
| CUTS ACROSS THE ROWS ABOVE: it writes a number, or it reads artifacts that already exist | the two instruments below, after whatever its own row owes | one re-derivation; one pass over the real artifacts |

step 5 is the only expensive one: run the **fast subset** of the project's
checks per injection, then confirm any survivor against the slow end-to-end
ones separately (wiring often lives only there), and run the whole sweep once,
at the end — never per commit.

1. **consumer sweep.** a mechanism gaining a dimension (a second repo, class,
   writer, verdict) is swept against every existing consumer of the first one:
   grep the old dimension, print the hits, tick each one. "the places I thought
   of" is not the list.
2. **contract re-read.** for every invariant the tree already states — store
   fault ≠ absent · one derivation per rule, called by each door · ids never
   reused · closed vocabularies — check the new code against that text, not
   against memory. new code breaking an old invariant is the commonest late
   defect.
3. **property × mutation.** list the properties the change claims, then break
   each one at its source and confirm a **named** check goes red. a property no
   mutation can kill is unpinned, whatever the assertion count says. mutate the
   checks' own claims too (truncate a reason list, weaken an assertion to rc
   only): a missing coverage never appears in a diff.
4. **fixture discriminability.** for every pair the checks must tell apart — two
   repos, two branches, two tips, two states — assert the fixture makes them
   observably different. this is stronger than the fixture-precondition rule: a
   fixture can see N>0 candidates and still be blind to the thing under test,
   and then **both** directions of a broken rule pass.
5. **exhaustive injection, last.** one mutation per decision the finished
   mechanism makes. the harness restores each file from a copy it made itself —
   never a VCS checkout, which silently discards uncommitted work — and reports
   an injection that did not apply as NOT-APPLIED, never as a survivor. run it
   against code believed final: run it early and most of what it mutates does
   not exist yet.

**two more, and they are deliberately NOT steps 6 and 7.** steps 1-5 are done to
the CHANGE; these two are done to the finished mechanism against REALITY, and
they apply only when it has a reality to meet — numbers it wrote, or artifacts
that already existed before it did. measured over one round's review campaign:
these two outyielded every pass invented by
looking again, and the second falsified a claim the mechanism was printing.

1. **re-derive every number the change wrote, from the primary source.** not
   from the count, not from a downstream evidence file, not from an earlier
   message — from the thing itself. a figure that travelled between documents is
   the cheapest thing to write and the most expensive to check, and it arrives
   internally consistent, because internal consistency is what a wrong citation
   preserves best. measured: a total a minute wrong in three files, carrying a
   word its source forbids. the special case worth a rule of its own,
   because no amount of care catches it: **a count of the work in progress,
   written into that work, is stale by the commit that writes it.** state the
   range and the command instead, and let the reader count. that sentence is
   scoped to a CENSUS — a count kept inside the corpus it counts — and the scope
   is load-bearing: a cross-file count (one file's number about another's
   contents) is not stale on writing and rots on a schedule nobody can predict.
   measured, because it was got wrong in both directions: `19 of the 58 open
   entries`, written into `validation-debt.md` about `iteration-log/`, was
   exactly TRUE for eight consecutive commits and its numerator survived twenty.
   the command belongs on both, and for the same reason — not because either
   goes stale at a knowable moment.
2. **run it over every real artifact on disk, not one plus fixtures.** fixtures
   carry the shapes their author thought of; a store written months ago carries
   the ones nobody did. measured over six finished topics:
   a value shape no fixture had, and a printed
   boundary falsified sixfold. one topic plus fixtures is not a trial.

**what it does not catch, and where that lives.** timing and interleaving
(deterministic contention fixtures, never wall-clock races) · anything only live
traffic can show (record it as validation debt; never claim it) · whether the
next reader can follow the new prompt or doc (a cold-reader pass, not a
mutation) · artifacts written by the old code meeting the new — the adoption
interpretation question (`operations.md`), which the second instrument above
ANSWERS rather than merely asks, whenever such artifacts exist to run over.
running these five and calling the change verified is the failure this section
most invites.
