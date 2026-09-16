# Design doc — `planning/design.md`  (template; cap `DOC_CAP_TEMPLATE`)

## Topic statement (verbatim owner input — recorded, not a claim)
…

## Scope
Numbered bullets — each maps to ≥1 work item at the convergence gate (A§9
plan-level coverage row). A scope change after approval is a new brief item.

| bullet | scope statement | traces to (verbatim fragment of the topic statement above) |
|---|---|---|
| S-1 | … | "…" |
| S-2 | … | **author's inference — the statement carries no fragment for this** |

A bullet with no fragment is not forbidden; it is an author claim about what
the owner also wants, and marking it is what puts it under the same
line-by-line veto as the shared-understanding table (A§2). Unmarked, it is
indistinguishable from something the owner asked for.

**Scope approval**: decision-log row `<id>` (signed; a later scope change
supersedes this row).

## Shared understanding (vetoable claims)
The author's model of **reality and intent**, stated as claims the owner can
veto line by line — the mechanism that catches author-model errors no other
instrument sees (A§2 — the intent source's verification cell). Every claim carries a worked example; background
sentences are claims too (`claims.md` rule 1).

| id | claim (my model of how it is / what is wanted) | worked example | evidence (shape-keyed) | owner verdict |
|----|-----|----|----|----|
| SU-1 | … | … | … | — / vetoed: … |

## Design sections
One numbered section per design area. Required fields per section:

### DS-<k>: <title>
<!-- DS- prefix: design sections; D- is reserved for decision-log rows. -->
- **depends-on**: [baseline row ids] — approval blocked while any is
  `unverified` (A§2)
- **why the current system is insufficient**: traced execution path
  (today-behavior shape — entry → exit, cited), never an unbounded absence
- **the design**: …
- **approval**: decision-log row `<id>` (a signed row, not a mark — A§4)

## Refine log
| pass | findings (A/B/C/wording) | fixes (evidence cited) |
|---|---|---|
