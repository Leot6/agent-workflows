# iteration-log entry template (one mechanism per file under entries/)

<!--
  Copy to entries/<slug>.md. The file is the ONE home of everything the loop
  records about a mechanism: the head block below is what the checks and
  `gen-index.sh` read (INDEX.md is generated from it — never edited), the body
  is the prose. A landing, a correction, a status change: edit THIS file, then
  run `iteration-log/gen-index.sh` (97-iterlog reds a stale INDEX).

  PUBLIC TREE (`runtime-docs/maintenance.md` §1): write the mechanism, never the
  project. A topic is a neutral alias (`topic-A`); no project, repository,
  module, path, host, tool or people names, and no commit SHAs of a delivered
  repository. The alias map and the evidence stay in the private archive.

  Head block — a fenced ```entry block right under the H1, one `key: value` per
  line, every value on ONE line (a `|` is fine; the generator escapes it):

    status    open | adopted (mechanism landed in-tree; landing carries the
              commit) | closed (evidence landed or refuted; the file STAYS —
              git history is not a home)
    hook      one line: what the workflow did or failed to do, and why it matters
    anchors   where seen, ENUMERATED: `topic-alias: t=` stamps (a stamp shared by two
              records is written `<stamp>(rec N)` — a stamp is not an identity),
              and it need not open with a number — most heads do not; the total
              is the body field's job,
              slice/stage, construct names (never file:line — the tree moves)
    landing   the landing commit(s) and notes for adopted; the closing evidence
              for closed; `-` while open

  Body fields (all required for open and adopted; "none" must be explicit — an
  empty field is indistinguishable from an unfilled one):

    observation              what was seen, as seen (no diagnosis yet)
    suspected mechanism      the one-line hypothesis of WHY
    falsifiable expectation  REQUIRED — what future event proves or disproves
                             it; an entry without one is a landfill
                             contribution, not an observation
    anchors                  the reading, and what the bar turns on: WHAT
                             happened twice and WHO saw each (review-standards §14). a
                             total is optional narrative — the bar is a threshold, not a
                             count, so an entry owes the two halves rather than
                             a number, and where a total is given it agrees with
                             the head's enumeration
    vehicle                  model/agent identity, if load-bearing
    landed                   what landed, where it is guarded, the expectation
                             restated for the landing, its VD row. NOT scoped to
                             `adopted`: a partial landing under an open head is
                             this tree's commonest shape, and the field is what
                             says which half of the entry is already in the tree

  THE BODY MAY NOT RESTATE A HEAD-BLOCK KEY. `status`, `hook` and `landing`
  live in the head block and nowhere else — `gen-index.sh` derives INDEX.md
  from the head and reads nothing below it, so a second copy in the prose is a
  second place every correction has to reach, and 97-iterlog refuses one in any
  emphasis (`- status:`, `- **status**:`, `- `status`:` alike). The copy rots
  at PROMOTION, which is the one transition this home exists to record: the
  measured shape is a head reading `adopted` over a body still reading `open`.
  No census is written here — a count of the corpus, kept inside the corpus, is
  stale by the commit that writes it (`maintenance.md` §2, first instrument).
  Nor is the pattern: it lives once, as `BODY_KEY_RE` in `97-iterlog`, and this
  paragraph names the check rather than restating its regex. It was restated in
  three places for one round and by the end of that round the copy here had
  already lost a `[[:space:]]*` and matched strictly less than the code, which
  is this rule's own defect one level up. To re-derive, run the check.
  Write what the body actually owes instead: `what stays open:` for the part a
  landing did not close, and the contracted `landed:` field above for the part
  it did — neither is a status word, so neither can disagree with one.

  `anchors` is the deliberate exception and stays a body field, because it
  carries the READING and not just the number. No arm sweeps it, and the reason
  is that its leading number is not machine-separable from the instance counts
  many entries open that field with (`3 in one topic, on three surfaces`), so a
  sweep would red correct material. The two are kept in agreement BY HAND, and
  the duty is the one stated in the field row above: the body field carries the
  reading and the two halves the bar turns on, and where it gives a total that
  total agrees with the head's enumeration. No running total is owed — the bar
  is a threshold, not a count.

  A second INDEPENDENT anchor is the promotion trigger, and §14 states it as a
  CONJUNCTION: the mechanism OCCURRED twice AND the two sightings were not made
  by the same observer. "different slice/topic" is the occurrence half only —
  two sightings of one event, or two sightings by one actor, are each ONE anchor. Prune nothing: closed entries keep
  their files; supersession is a `landing:` note naming the newer entry.
-->

# <title — the observation in one line>

```entry
status: open
hook: <one line: what happened and why it matters>
anchors: 1 — <topic-alias>: <t= stamp or construct>
landing: -
```

- observation: <what the workflow did/failed to do, as seen>
- suspected mechanism: <the one-line hypothesis>
- falsifiable expectation: <what future event proves/disproves it>
- anchors: 1 — <where seen>. **Single anchor: DEFER.**
- vehicle: <model/agent, or none>
