# Disposition ledger — `rounds/<n>/disposition.md`  (template; cap `DOC_CAP_TEMPLATE`)

One row per finding this round dispositions (carried findings included).
A finding leaves `open` **only** through a row here or a signed decision-log
row; relocation is not disposition (A§8).

**class** (single home of the definition): the completeness family a finding
belongs to, named by what would have to hold for the **whole** family to be
closed — the column that detects Campaign B's "one narrower instance per
round" shape, so it is what the `RECUR_MIN` closure-proof trigger counts.
`—` is legal **only** for a finding that is the first of its kind on this
topic; a finding that restates, narrows, or re-instances an earlier one
takes that finding's class, whatever round it came from.

| finding (lens-id, round) | layer | family (for recurrence tracking) | disposition | evidence | state |
|---|---|---|---|---|---|
| arch-1, r2 | implementation | <class or —> | fixed-in-v<k> (fix claim traced: producers/consumers/delta → `claims.md` stamp) · refuted (re-derivation cited) · escalated (brief <n> §<j>) · carried (why still open) | … | closed · open · owner-gated |

## Fix claims baked this round
| fix | keyed symbol(s) | producers (each, by symbol) | consumers of the new predicate | admits/rejects delta (input region) |
|---|---|---|---|---|

## Carry-forward out of this round
Every row left `open` above carries into the next round (A§8: relocation is
not disposition). The close-out's register is **the** canonical set and this
ledger's `state` column is its source — not a second copy to keep in sync.
