<!-- spec artifact template — copy to slices/<nn>/spec.md and fill.
     contract: review-standards.md §4 (spec-ready). cap: cap.spec_lines (default 2000).
     single-source numbers rule, stated once and binding throughout: every number
     lives in exactly ONE place in this document, paired with the command that
     derives it; every other mention references that place. a gate may restate a
     literal where executability requires it; nothing else repeats a count. -->

# spec

<the H1 is a CONSTANT, like `templates/review.md`'s and `templates/halt.md`'s,
and for the same reason: the emit-time structure gate compares template headings
VERBATIM, so a parameterised H1 fails on every document that fills it in. The
slice and its title live in the metadata below, where the rest of the metadata
already is.>

- topic: <topic>
- slice: <nn> (charter: charters.md § slice <nn>)
- title: <one line — what this slice does; the H1 used to carry this>
- risk class: <low|med|high> — <one-line basis; behavior change ⇒ never low>
- spec version: <1|2|…> (a revise round increments; verdict history is in the store)

## 1. binding constraints (front-loaded — read before anything else)

<the non-negotiables of this slice, first because position bias is real. every
constraint the implementer and reviewer must not violate: invariants preserved,
interfaces frozen, files out of bounds, orderings required, caps in force
(effective values, with source layer: workflow default vs project.kv override).>

- <constraint 1>
- <constraint 2>

## 2. scope, proven by command

<the slice boundary is a discovery grep's output, not intuition. one block per
scope claim: the command, its reading, and what that binds.>

```
$ <discovery command run from <root>>
<decisive output lines>
```

- in scope: <files/constructs, exactly the proven set>
- out of scope: <adjacent things deliberately untouched, so no one "helpfully" widens>

<the out-of-scope half is proven the same way, and it is the half that is wrong.
for every construct this slice SHARES with code it does not touch — a state key,
a ref, a helper, a vocabulary — run the readers sweep and read it here; the
result is a claims-table `count` row, so its range stamp and rerun command are
gate-enforced like any other number. "the other readers are X and Y" from memory
is the shape that produced six defects in one day of this workflow's own
maintenance. sharing nothing is a legitimate answer — record the empty sweep.>

```
$ <readers sweep for each shared construct, e.g. git grep -n '<key>' -- <scope>>
<every hit, classified: edited by this slice / left untouched deliberately>
```

## 3. commit-units

<one row per unit; the dynamic half of the owed set — the progress ledger and
postcheck review exactly these. subjects follow project.kv conventions verbatim.>

| id | subject (project convention) | risk note | relocation-only |
|---|---|---|---|
| cu-1 | <type>: <imperative summary> | <what could go wrong / why safe> | no |
| cu-2 | … | … | no |

per-unit content: <for each cu, the edits — byte-exact where bytes matter, intent
where judgment is delegated — with anchors into the current tree (durable anchors +
content echo; line pins only as read stamps).>

## 4. interface deltas

<every public/cross-module surface this slice adds, changes, or retires: signatures
before → after, headers moved, symbols renamed (old → new), ABI/API notes. "none"
is a valid entry and is itself a claim — back it in the claims table.>

## 5. test and gate plan

<per commit-unit: which gates run before its commit (build / lint / test /
acceptance from project.kv), plus slice-close gates. gates are run exactly as
written here — no narrowing, no substitution. the suite set DERIVES from the
unit's target files' ownership — every suite that owns an edited surface runs;
a target outside every listed suite is a plan defect, and a unit whose edits
cross OUTSIDE the acceptance surface forces the FULL acceptance composite into
the slice close, never a hand-picked subset (review-standards.md §4.5 —
precheck re-derives this from the targets).>

- cu-1: <gates, with the target→suite derivation stated>
- slice close: <composite acceptance gate — the author-side run of the one
  intentional double-run. the emit joins this plan to the gates surface: every
  project gate project.kv declares must hold a PASS row pinned to the emitting
  tree (or its named SKIP) before impl/fix emits>

**flip gate slot** <owed for every criterion this slice's close rests on that CAN
read differently at the baseline than at HEAD — review-standards.md §4.5. the test
is the EVIDENCE, not the change: a behavior change owes it unconditionally, and a
doc-bound slice owes it too — the per-slice checks that are its mechanical floor
ARE this slot's content, filed here as pairs and not rebuilt beside it under
another name. name each check that reads RED on the baseline and GREEN at HEAD;
include the red-baseline transcript (derived via the probe window, disclosed).
"none owed" is honest only for a reading that is genuinely state-invariant, and
says which reading and why.>

```
$ <flip gate command>            # baseline: <red reading>   HEAD: <green reading>
```

## 6. claims table

<format: review-standards.md §2 — the machine contract lib/gates.sh checks at
emit time. every load-bearing claim: counts, citations, absences (with searched
range), and BEHAVIOR ("this code/test already does X" — never a `note`: the
class measured most often wrong with the least resistance). type ∈
cite|count|absence|behavior|process|note. cite rows carry a durable anchor
(path#heading or path::symbol — line pins forbidden) + a content echo the
resolver verifies; count/absence rows carry the read-range stamp AND the
evidence command; behavior rows carry a path::symbol anchor (the code that
does X) + echo + the rerun command — which puts them under the reviewer's
run-every-command duty. PROCESS rows carry a sentence stating what the process
DID ("the sweep ran", "re-read in full", "the gates re-ran") — the extent, the
command by label, and what that command RETURNED as an `E<n>-out:` line: an
asserted sweep is the form measured to report itself complete while incomplete.
only judgment that no command can settle stays `note`. this table is re-resolved
at the LANDED tip when impl/fix emits (recorded as `spec_claims_tip`, read by
postcheck): a row that describes the tree BEFORE this slice's change — a fact
the slice will invalidate — writes `baseline` in its range cell so the tip
re-check skips it; every other row must still hold after your own commits.>

| type | claim | anchor | echo | range | command |
|---|---|---|---|---|---|
| cite | <…> | <path::symbol> | <short verbatim echo> | - | - |
| count | <…> | - | - | <path:La-Lb @ commit> | `$ <pipe-free cmd>` → <reading> |
| count | <…> | - | - | <path:La-Lb @ commit> | `E1` → <reading> |
| absence | <…> | - | - | <searched scope, stated fully> | `E2` → 0 hits |
| behavior | <this test already activates X before seeding> | <path::symbol> | <short verbatim echo> | - | `$ <rerun cmd>` → <reading> |
| process | <§8 swept for self-tallies; every hit dispositioned> | - | - | <the extent swept, stated fully> | `E3` |

<a command carrying a `|` is NAMED here and defined below. a pipe inside a cell
splits the row — for every renderer AND for the emit gate's own parse — so the
recorded command truncates at it and anyone copying the cell runs a shell
fragment; escaping fixes only the render. pipe-free commands stay inline.>

```
E1: <command, exactly as run — pipes and all>
E2: <command over the searched range>
E3: <the sweep's command, exactly as run>
E3-out: <what E3 RETURNED — the hit list, so a reader re-runs and diffs it>
```

## 7. baseline pin (logical)

<shared-branch reality — protocol.md §9. pin the branch and the constructs this
spec binds, each with a content echo the resolver can verify; do not pin a frozen
commit as if the branch were yours alone. note anything colleagues are likely to
touch concurrently and what the attribution check would look like here.>

- branch: <name>
- bound constructs: <path::symbol — "echo"> …

## 8. refine log

<review-standards.md §3. per round: finding → evidence command → result → severity
(A/B/C/wording). release reason: a round with nothing substantive, or the round
bound with residuals flagged. a zero-finding first round is itself a flag.>

- round 1: <the spec-ready walk, §4.1–4.9 each met/not met with evidence; then findings…>
- round 2: <findings…>
- release: <clean round | bound reached; residuals: <list or none>>
