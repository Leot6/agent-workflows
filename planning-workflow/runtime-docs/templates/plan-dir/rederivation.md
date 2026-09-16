<!-- rederivation.md — the (A) ledger: per-version groups recording what each
     version landed and where (the old §delta 台账 + (A-prev) ledger, live form
     only). Historical groups stay in their own version directories — pointer
     lines only here, never inlined copies (single-home rule). -->

# Rederivation ledger — v<N>

| # | landed item | where it landed | evidence command |
|---|---|---|---|
| 1 | <rule/fix id> | items/W-<id>.md::<field> | `<command>` |

<!-- Prior versions: one pointer line per version — "v<N-1>: <round>/<note>"
     — the full groups live in planning/plan_v<N-1>/rederivation.md. -->
