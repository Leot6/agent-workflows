# Grill sheet — `planning/grill_sheet.md`  (template; cap `DOC_CAP_TEMPLATE`)

Batches ≤ `GRILL_MAX`; exceeding = scope brief (A§4). One batch = one set of brief
sections (one question = one section = one decision-log row); co-pending
items may share the brief file (A§10). Questions batched by
settled prerequisites: a batch contains only questions whose inputs prior
batches (or the card) settled — and is **maximal under that test**: a
question whose input another question in the same batch would settle belongs
to a later batch. The unit is structural, not author-sized; one batch holding
every question is not a batch, and `GRILL_MAX` counts batches. Question / recommendation / answer columns in
Chinese (A§12); refine each batch before sending (ambiguity, missing branches,
missing recommendations).

## Batch <b> — sent <date>, answered <date>

| # | 问题 | 推荐答案（含理由一句） | owner 答复 | state | decision-log row | rederivation |
|---|------|--------------------------|-----------|-------|------------------|--------------|
| b.1 | … | … | … | decided · deferred · reality-gap | row `<id>` / — | `rederivations.md#<entry>` / `rounds/<n>/rederivation_<k>.md` |

State semantics (A§4): `decided` → signed row; `deferred` → signed deferral row
(exists only as an owner reply — signed by construction); `reality-gap` → new
`unverified` baseline-card row `<id>` (it was a question about reality, not
intent — route it to the card and the verifier).

## Refine log (per batch, before sending)
| batch | pass | findings (A/B/C/wording) | fixes |
|---|---|---|---|

## Branch closure
Grill exits only when every branch across all batches is in a terminal state.
Open branches: [list or "none"].
