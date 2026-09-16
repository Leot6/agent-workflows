<!-- Class U question set — the document a stage writes before it emits
     `--halt class_u`. Path: slices/<nn>/halt.<n>.md (n = this slice's halt
     count; the emit gate names the expected path, checks every heading below
     in order, AND runs the claims gate on §7 — the numbers and citations an
     owner rules from are machine-checked, not narrated). The owner rules from THIS text alone — no session
     history, no other file (review-standards.md §11). Several co-pending
     questions batch into ONE document: keep the `##` sections, and inside
     each put one `### Q<k>` subsection per question. cap: cap.artifact_lines.
     Prior art for the shape: Nygard's ADR (context / decision / consequences,
     the negative ones included) and the Rust RFC template (motivation,
     drawbacks as "what becomes impossible later", rationale and alternatives). -->

# halt — Class U

- stage: <stage> · slice <nn> · question set <n>
- blocked: <the artifact or step that cannot proceed until the ruling — one line>

## 1. the question

<one sentence per question, answerable by choosing an option from §4. a reader who
stops here knows what is being asked.>

## 2. why this needs a ruling

<the evidence that raised it, cited (commands, read ranges, the plan/charter/spec
passages in tension); the boundary the author does not own — which Class U trigger
applies (semantic tradeoff, scope/direction, irreversible/outward, ownership
crossing, unverifiable assumption, "ask me"). if a Class A/C disposition was
considered and rejected, say why here.>

## 3. blast radius

<what the ruling touches, enumerated: artifacts (plan passages, charter rows, this
spec, later slices' charters), index rows (bindings and `after=` are immutable per
id — say if a new id must be minted), repository files and their readers, landed
commits, the topic's remaining schedule. name what is irreversible under any
option, and what stays reversible. derived by command where the tree can answer.>

## 4. options

<every viable option, keep-as-is included where viable; one block each, the
five lines always present (an option whose "against" is empty has not been
examined). the structure gate pins only this file's `##` headings, so the
option blocks are bold labels, not headings — `### Q<k>` subsections are free
for batched questions:>

**A. <name>**
- delta: <what changes where — files, passages, index rows, commits>
- for: <the case for it, in the problem's own terms>
- against: <the case against it — costs, risks, what it forecloses>
- after: <what becomes required or impossible once it is taken; who must act>
- cost: <effort and time, derived where possible>

**B. <name>**
- delta: · for: · against: · after: · cost: <same five lines>

## 5. worked examples

<at least one concrete scenario — real inputs, real state — traced under EVERY
option of §4 so the difference shows in outcomes, not adjectives; a second
scenario wherever the options diverge on a different input than the first. detail
is the point: the owner should be able to predict the system's behaviour from
the example alone.>

## 6. recommendation

<the option, one line of reason, and the fallback if the owner declines it.
options that all reach the same outcome are not a decision point — record a
disposition, do not spend an owner slot.>

## 7. claims

<the machine-checked table (`review-standards.md` §2, the contract `lib/gates.sh`
parses at emit): every NUMBER and every CITATION the options in §4 rest on. this
document is the one an owner rules from with no reviewer between it and a binding
decision, so its load-bearing facts are checked by the gate rather than read.
measured, both from one topic's two halts: a sentence attributed to
"coding-rules §10's own words" that appears nowhere in that file's 503 lines — a
`cite` row's content echo resolves that mechanically — and an option arithmetic
that did not reconcile (~34 trimmed, stated as landing at two different totals) —
a `count` row carries the command that re-derives it. free prose in §8 cannot
catch either; that is the whole reason this section exists.>

| type | claim | anchor | echo | range | command |
|---|---|---|---|---|---|
| cite | <the rule/passage an option leans on> | <path#heading or path::symbol> | <short verbatim echo> | - | - |
| count | <the number an option's delta rests on> | - | - | <read range @ commit> | `$ <cmd>` → <reading> |

## 8. evidence

<the read-stamp block for everything the table does not carry: every command as
run with its reading; constructs read to their closing brace; plan/charter
passages read to their section end.>

## 9. refine log

<review-standards.md §3: per round, finding → evidence command → result → severity.
the halt path owes no refine fields at emit; this log is the document's own
history, audited in the post-ruling round.>
