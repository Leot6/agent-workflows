# Check record — `rounds/<n>/check_<k>.md`  (template; cap `DOC_CAP_TEMPLATE`)
<!-- Written by the VERIFIER (returned as text; the author persists it
     verbatim and may not edit it, then cites it to flip row states). -->

- **Assignment**: verify rows [<ids>] · resolve commands [<ids or "all in plan_v<N>/">]
- **Vehicle**: <model/agent identity> · **Pinned SHA(s)** (per repo): <sha> · **Drift audit**: <result>
- **Plan manifest hash** (when the assignment names a plan version): <`PLAN_HASH` of the version directory as you read it>

## Rows
Evidence commands are **re-run, never trusted**.

| row id | claim (quoted) | evidence command re-run (verbatim) | observed result | verdict |
|--------|----------------|------------------------------------|-----------------|---------|
| B-1 | … | … | … | verified · disputed: <what disagrees, with my own evidence> |

## Commands (plan commands: acceptance · setup · executable rollback — A§2)

| command (verbatim) | exists / parses / dry-run result | fixture reachable? | resolvable-by-construction? (creating work item id) | "passes when" stated? | verdict |
|---|---|---|---|---|---|
| … | … | y/n/n-a | — / W-<id> | y/n | resolved · unresolved: <why> |

## Range read
State exactly what was read/run and to where (files to their ends, greps with
scope + printed hits) — absence verdicts are invalid without this
(`claims.md`).
