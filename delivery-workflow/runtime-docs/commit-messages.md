# commit messages — what the subject may say, and what it must be true of

the commit message is the one artifact of a slice that outlives every other:
the plan, the spec, the reviews and the workspace are all cleaned, and
`git log` is what a reader has left. two rules govern it, and they fail in
opposite directions — §1 refuses a word the repository cannot resolve, §2
refuses a sentence the diff does not support.

each binds three parties — the author who writes the message, the reviewer who
checks the spec that prescribes it, the door that refuses it — so each is
stated once, here, and the other surfaces point at it rather than restating it.

## 1. identifier boundary

an identifier belongs in a commit message only if the **delivered repository can
resolve it**. ours never can: `cu-N`, `DP-N`, slice ids, round and finding
anchors, workspace paths. neither can the ids an upstream artifact hands over —
plan work-item ids, review-round anchors, decision points, flip-gate labels: the
plan is not in the repository being committed to. the history outlives the
artifacts those ids live in, and a later reader of it has nowhere to look any of
them up. say what the change does in words the repository itself carries; the
id→SHA mapping is the progress record's job, and it is already kept there.

both commit doors — registration (`record.sh progress`) and the gate at emit —
refuse them by **lookup, not by pattern**. the shape is only a candidate; the
verdict is whether this topic's own planning artifacts name the token. so a
shape nobody has coined yet is caught the day it is coined, and the project's
own words of the same shape (`SHA-1`, `UTF-8`, `RFC-2119`, `AVX-512`) pass with
no allowlist to maintain. enumerating shapes is exactly what has been measured
to fail.

**an upstream artifact that prescribes such a token is a conflict — raise it;
passing it through is not an option the door leaves open.** a plan or spec that
says to write one is not authority against the door: it is a finding, and the
spec-ready contract (`review-standards.md` §4) is where it is cheapest to catch
— at precheck, before any commit exists to rewrite. an author who meets the
conflict mid-impl stops and re-enters revise, the same as for any other spec
defect.

## 2. the subject is a claim about the diff, and it is checked as one

a subject is a proposition — *this is what this diff does*. §1 and the project
regex both read the subject as a SHAPE; nothing downstream of them asks whether
the proposition is TRUE. that question has exactly one home, postcheck C4, and
it is asked per commit-unit against the diff C2 has already derived.

two ways it goes wrong, and they are not symmetrical:

- **misdescribes** — the subject asserts something the diff does not do. the
  verbs that carry the most assertion are the structural ones: *hoist, move,
  extract, inline, rename, replace, unify* all claim a thing left one place and
  arrived in another, and each is falsified by the same reading — the departure
  site is not in the diff, or its content is unchanged. a duplication described
  as a hoist is the measured case, and the author's own added comment said
  "the same disjunction, and the same two messages" while the subject said
  the check had moved.
- **under-describes** — the diff carries a change no clause of the subject
  implies. not every unmentioned hunk matters; the test is whether the omitted
  change is **production-visible**, because that is what a reader greps `git log`
  for and will not find: a new public entry point in a shipped header, a new
  operational log tag, a new configuration key, a behaviour change behind an
  existing name. measured twice in one topic — a new `LOG(WARNING)` tag, and a
  new `[[nodiscard]]` function in `include/`.

the reviewer's finding is the subject, not the code: the diff may be entirely
correct and conform to its spec, and the message still be false of it. the
remedy is an amend, and it is cheap for exactly as long as the commit is **still
the tip** — not, as this said until its first live application, for as long as
the commit is unpushed. once work sits on top, an amend rewrites every descendant
and re-SHAs them, which in a shared checkout is a different decision from a
one-line reword and can orphan whatever already cites them. **that asymmetry is the
whole reason this is postcheck's question and not close-out's**: the same finding
costs a reword at postcheck and a history rewrite two stages later, so a late
finding is weighed against its remedy rather than applied automatically — and
the weighing is recorded, never left silent.

**a squash inherits the duty.** consolidation replaces n subjects with one, and
the byte-identity invariant (`operations.md` §8) cannot see the loss: the tree is
identical by construction, so the one thing squashing CAN break is the only
thing that check does not look at. the new subject covers the union of the diffs
it now owns, or names the union honestly and generically — never the first of
several landed changes as though it were all of them.
