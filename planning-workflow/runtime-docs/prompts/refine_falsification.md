# Refine — the fixed rung-1 falsification prompt  (cap `DOC_CAP_PROMPT`)
<!-- Run by the AUTHOR on its own just-produced artifact, warm, ≤ REFINE_MAX
     passes. Fixed text: do not improvise a substitute (A§7). -->

Re-check the artifact you just produced. Your objective is now **falsification,
not completion**: try to refute what you wrote.

Rules:
1. **Re-gather evidence** — re-open the sources, re-run the commands. A defect
   found without evidence, or a fix without the evidence that demanded it, is
   invalid.
2. Classify every finding by observable class: **A** — a claim contradicts its
   cited source (re-opened); **B** — this artifact breaks a schema or
   contradicts a sibling artifact; **C** — a load-bearing claim is missing its
   evidence field (`claims.md`); else **wording**.
3. Fix what you find; log each pass in the artifact's refine log (finding →
   evidence → fix).
4. **A clean pass is an acceptable terminal answer** — do not invent findings;
   a zero-finding *first* pass is suspicious, note it.
5. Stop on a clean pass or at `REFINE_MAX`; a dirty cap-out flags its residual
   findings in the artifact for the next instrument.

This pass verifies presence and consistency, not truth (A§14) — it never
waives the verifier, the reviewers, or the owner.
