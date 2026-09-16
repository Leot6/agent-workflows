# Decision log — `planning/decision-log.md`  (template; cap `DOC_CAP_TEMPLATE`)
<!-- ALL owner-gated decisions (A§4 lists the types). ADR-shaped: immutable
     once signed; supersede, never edit. One row per brief section (A§10). -->

| id | type | brief ref | signed text (逐字，中文如原文) | English gloss (carried text — checked by the next cold reviewer) | class payload (the brief section's 附加字段, carried verbatim) | rejected alternatives | supersedes / reaffirms | state | date |
|----|------|-----------|-------------------------------|------------------|---|--------------------|------------------------|-------|------|
| D-1 | ruling · deferral · scope-out (+ new round and grill-batch budgets) · supersede · reaffirmation (+ delta survived) · bounded limit · design-section approval · re-tag · closure-proof declaration · amend disposition · split · abandonment · convergence | brief 3 §2 | … | … | … | … | — / D-<k> | proposed · signed | … |

**Convergence row extras**: content hash of the promoted plan (never inside
the plan file itself; the live hash = the latest signed row's) + pinned SHA
per repository.
**Editorial-amend row extras**: the new hash + the convergence row it names.
**Full-amend row extras**: cause dating — did the cause predate convergence?
(yes = an escaped planning defect; the topic's escape count feeds retro). Its
input is the amend entry line's cause paragraph (protocol §7), carried into
the brief: the party that hit the defect is the only one holding it.
**Split row extras**: the two new topic roots + one topic statement per
child (transcribed verbatim into each child's `design.md` — carried text).

A finding or branch may be treated as resolved **only** against a `signed` row
(A§10); `proposed` parks its dependents.
