# Convergence checklist — appendix of the convergence brief  (template; cap `DOC_CAP_TEMPLATE`)
<!-- Rows split by instrument (A§9). Placeholder token set (I-2 scans the
     whole plan file):
     TBD · TODO · FIXME · XXX · "???" · 待定 · 占位 · an angle-bracket span
     in prose naming what should be filled (`<name>`, `<path>`, `<TBD>`).
     Type syntax inside a code span is NOT a stub — `Vec<u8>`,
     `Promise<Response>`, `std::optional<T>` are required interface-delta
     content, and the interface delta is where real type syntax lives. -->

## Item-level rows (rung 2 — author at emit; spot-check: architecture lens, `SPOT_N` highest-risk items)
| row | check | result |
|---|---|---|
| I-1 | every work item carries the **full A§4 field set** (checked against A§4's list by pointer, all fields incl. id/title/sites/target repository; "none + reason" forms allowed where A§4 says so) | pass / fail: W-… |
| I-2 | no placeholder token (set above) anywhere in any file of the promoted concatenation (header fields filled at promotion are exempt; the scan runs per file over the version directory) | |
| I-3 | edges pass a topological sort (cycle list empty) | |
| I-4 | every `L` item split or carrying a signed bounded limit (row ids) | |
| I-5 | every acceptance command names its adversarial corner (acceptance-claim shape) | |

## Plan-level rows
| row | check | result |
|---|---|---|
| P-1 | preamble filled: repos+SHA · toolchain/setup with passes-when · fixtures · consumer precondition line | |
| P-2 | coverage, three directions: every signed row → ≥1 item or non-plan-bearing; every bullet of the **approved** scope section → ≥1 item (the scope-approval row is `signed`, id recorded — an approval still `proposed` fails this row); **every item → a scope bullet or signed row** | |
| P-2b | scope traces to the **request**, both ways: every bullet of the approved scope carries a verbatim topic-statement fragment, an "author's inference" mark, or a signed row; and every distinguishable ask in the recorded statement reaches ≥1 bullet or a signed row scoping it out. P-2's three directions all measure inside the approved scope — this is the one that reaches the ask the topic was started from | |
| P-3 | `unverified` rows nothing depends on: swept — `verified` or `retired` (reason recorded on the row) | |
| P-4 | every plan command resolved (check record `<ref>`) | |
| P-5 | open-findings register empty: every prior finding left it through one of A§8's three doors — root-fixed (independent re-derivation cited), refuted (re-derivation cited), or signed as a bounded limit (row ids) | |
| P-5b | **every finding refuted on this topic**, any round — id · the finding's own words · the re-derivation that refuted it · the round. Not a list of ids: a refutation is author-lineage and leaves the register before any reviewer sees it, so this row is the only out-of-family read it ever gets, and a one-line paraphrase is what the register's own source column exists to prevent. "none" explicit | |
| P-6 (pre-signature) | the dispositions the final version will incorporate are listed; executor provenance version == the version this brief reviews, or differs by **non-semantic delta only** — classify against A§4's field set and name the delta (A§9) | |
| P-6b (post-promotion attestation — recorded on the convergence row, not signed here) | promoted plan = signed version + only the signed dispositions (mechanical diff attached); **each incorporated disposition re-derived against its signed row by the promotion verifier** (check record `<ref>`) — the diff proves provenance, not that the rendering into plan prose kept the ruling whole (carried text, A§2), and this is the read that keeps the shipped version from being one no instrument saw; `PLAN_HASH` + SHA recorded | |

## Executor rows (rung 3 — content authored by the executor lens, transcribed verbatim by the author; never author-written)
| row | check | result |
|---|---|---|
| E-1 | question inventory: empty / every remaining question is listed for disposition in this brief (row ids filled post-signature) | |
| E-2 | "What would a zero-context executor miss from the plan alone" — 'none' explicit, or the misses listed | |

**Owner signature** rides the convergence brief containing this appendix; the
convergence row records hash + SHA.
