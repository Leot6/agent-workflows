<!-- plan-dir/00_context.md — plan template, directory form (P-6).
     One plan version = one directory plan_v<N>/ with these files; items/ holds
     one file per work item, named by item id. Self-descriptive readings live
     in rounds/<n>/plan_hash.md, NEVER here (A§9, WQ-1 甲). Cap: DOC_CAP_TEMPLATE
     per file. -->

# <topic> — implementation plan v<N>
- **Pinned SHA(s)** (per repo): <sha> · **Convergence row**: <id>
  (the content hash lives on the decision log — the latest signed row; a
  working version carries a manifest hash of its file set, a promoted plan.md
  carries the single-file sha256 of the concatenation)

## Execution context (preamble — plan-level gate rows, A§9)
- **Repositories**: <name → abs path/url, SHA>
- **Toolchain & setup**: one command per line, id'd `C-<k>`, each with
  `passes when: …` (acceptance and rollback commands continue the C-<k> sequence)
- **Fixture data**: <what + how obtained>
- **Consumer precondition**: before executing, re-run the drift audit against
  the pinned SHA; blocking drift ⇒ this plan re-enters `amend`, do not execute.
  Anything else you find wrong in this plan also enters `amend` — raise it.
  Planning states this duty and cannot enforce it, and it is the only channel
  by which a planning defect that escaped the gate is ever counted. Entry line
  (authority: protocol §7; copied verbatim):

      read <ABS workflow>/runtime-docs/protocol.md — amend topic at <ABS topic root>, checkout(s) <ABS path[; ABS path…]>: <what in the plan is wrong and how it was found>; do not summarize; stop at the first owner touchpoint

## Coverage (plan-level gate rows, A§9)
| scope bullet (design.md) | realized by items |
|---|---|
| S-1 | W-1, W-3 |

| work item | maps to (scope bullet or signed row — an unmapped item is scope creep or over-engineering) |
|---|---|
| W-1 | S-1 |

| signed decision row | referenced by items / non-plan-bearing (why) |
|---|---|
| D-4 | W-2 / non-plan-bearing: <why> |

Every `none` in any file of this version is an **absence claim** (`claims.md`)
— state the full range read. **自述读数不入本目录**（A§9 自指规则的推广，
WQ-1 甲）：描述本计划自身的基数 / 枚举 / scope 读数不写正文——正文只写
**重导命令 + 判据**，读数本身住 `rounds/<n>/plan_hash.md`。
