# Baseline card — `planning/baseline.md`  (template; cap `DOC_CAP_TEMPLATE`)

## Pin header (one row per repository the topic touches)
| repo | checkout (abs — the row's audit target when more than one is named; the others record as `note`, §4.0) | pinned SHA | drift audits (append per cold start: date · match? · clean/benign/blocking/instrument/note + files — §4.0) | re-pins (old→new · rows reverted) |
|---|---|---|---|---|

## Rows
One row per load-bearing fact. Evidence fields are **required columns** — a row
missing one is incomplete by schema (`claims.md`).

| id | claim | shape | evidence (shape-keyed: scope + printed hits / range read / path trace / writers of both sides) | falsification target (the site that would prove this wrong — opened) | state | check record |
|----|-------|-------|----------|----------|-------|--------------|
| B-1 | … | count / absence / invariant / today-behavior / citation / family | … | `file:line` (opened) | unverified · verified · retired (reason) | `rounds/<n>/check_<k>.md` |

State flips **only** with a check-record citation (A§2). Rows added after the
freeze enter as `unverified`.

## Authorities inventory
Every design doc, prior decision record, or opposing document bearing on this
topic (the meta-critic's `{PRIOR_OPPOSING_DOCS}` fills from here; never omit a
known opposing one):

Paths **absolute and openable** — the meta-critic is cold, has no working
directory (protocol §7), and is told to check each "passage by passage"; a
title-shaped cell fills the slot and cannot be read. An empty inventory is
recorded as `none — <the range read that establishes it>`, never left blank:
blank is indistinguishable from unfilled, and the slot is mandatory.

| doc (absolute path) | bears on | opposing? |
|---|---|---|

## Staleness appendix
Doc passages the pinned code contradicts (recorded here; enters the plan only
through an owner brief item — A§2):

| doc passage (cited, opened) | what code shows (`file:line`) | correction proposed? (brief ref or "record only") |
|---|---|---|

## Refine log (`prompts/refine_falsification`, ≤ `REFINE_MAX`)
| pass | findings (class: A claim≠source · B schema/consistency break · C missing evidence field · wording) | fixes (each citing the evidence that demanded it) |
|---|---|---|
| 1 | … / "clean" | … |
