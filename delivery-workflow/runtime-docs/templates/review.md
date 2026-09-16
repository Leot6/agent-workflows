<!-- review artifact template — the section skeleton every review file
     (splitcheck.N.md / precheck.N.md / postcheck.N.md) must follow. The emit
     gate checks it mechanically (gates_structure: every heading below, in
     order); checklist CONTENT is review-standards.md §7/§9 — this file fixes
     only the shape. cap: cap.review_lines (default 1500). -->

# review

- stage: <split-check|precheck|postcheck> · slice <nn> · round <N>

## 1. provenance

<baseline (branch + the reviewed SHA set or artifact versions), freshness
(self-derived — prompts never told you your spawn mode), round number, and the
form used (full | compact, with the risk class that licenses it).>

## 2. findings

<one numbered finding per entry: severity class (A/B/C/wording — or R-Q for a
question), the claim, the re-derivation command a stranger could run, the
leak_class tag where this is a postcheck, and — from round 2 — `new` or `repeat`
(a repeat names the previous-round finding it continues; review-standards §1).
wording never blocks alone.>

## 3. absorption

<round 1: `first round — nothing to absorb`. from round 2: for EACH previous-round
finding, its disposition — absorbed (where, one line), rebutted (why), repeat (it
stands; its number in §2), or re-introduced — then ONE line the owner can rule
from if this round parks `disagreement`: is the loop narrowing (residuals strictly
fewer and smaller) or not, and which option you would take (continue / split /
redesign) and why. the ferry's park text points the owner here; write it for a
reader who has not seen either round.>

## 4. claims

<the machine-checked table (gates.sh contract): every load-bearing claim this
review itself makes — counts, citations, absences with their searched range, and
`process` rows for what this review DID (a sweep re-run, an extent read, a
command compared): extent + the command by label + its output as `E<n>-out:`,
which is what lets the next reader re-run and diff it rather than trust it.>

| type | claim | anchor | echo | range | command |
|---|---|---|---|---|---|
| note | <replace with this review's own load-bearing claims> | - | - | - | - |

<a command carrying a `|` goes in the block below as `E<n>: <command>` and its
cell names it — a pipe splits the row for every renderer and for the gate's own
parse, so the recorded command truncates at it and a reader copying the cell
runs a fragment. no heading: the block is conditional, and the structure gate
requires every heading this template declares. delete it if unused.>

```
E1: <command, exactly as run>
```

## 5. non-coverage

<what this review deliberately did not examine, stated so silence is never
read as clearance.>

## 6. verdict

<the closed-vocabulary verdict for this stage, severity counts (substantive /
wording — the record's mechanical fields; from round 2 substantive = new + repeat,
both counts in the record), and confidence HIGH|MED|LOW.>
