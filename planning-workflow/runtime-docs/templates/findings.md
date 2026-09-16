# Findings — `rounds/<n>/findings_<instrument>.md`  (template; cap `DOC_CAP_TEMPLATE`)
<!-- Returned as text by the reviewer; persisted VERBATIM by the author. -->

Plan version reviewed: plan_v<N>
Plan manifest hash: <`PLAN_HASH` of the version directory as you read it>
Code baseline: <sha per repo>
Drift audit: <per repo — clean / benign: <files + why> / blocking>
Vehicle: <model/agent identity>

<!-- The five lines above are the provenance header: first, verbatim,
     un-fenced (A§3). The version names the file; only the hash names the
     bytes, and two instruments can honestly report the same version having
     read different ones. -->

## Findings
<!-- severity (single home of the definitions; the trend rule counts
     structural+rule as substantive): structural = a walk or mechanism breaks
     (missing producer/consumer/exit/data, unsatisfiable gate) · rule = a
     stated behavior contradicts another statement or lacks its required
     carrier · wording = meaning recoverable, text misleads -->
| id | layer | class (`product`/`provenance`/`doc-sync`/`artifact` — instrument-assigned; orthogonal to layer) | claim under attack (quoted from the artifact) | defect | evidence (shape-keyed per claims.md — scope + printed hits **with the unit: `hit-lines=N occurrences=M`, both** / range / trace / symbols) | severity |
|----|-------|----|----|----|----|
| <lens>-1 | foundations · implementation | … | … | … | … |

## R-Q (questions the reviewer cannot make independently re-derivable —
routed by the author into the round's brief)
| id | question | what would make it re-derivable |
|----|----------|--------------------------------|
| RQ-1 | … | … |

## Clean categories (REQUIRED when any mandate category yields no findings)
One line per clean category — affirmative, with its range read to its end;
a clean category counts only through a line here, never through silence
(A§8's release principle).

| mandate category | checked against | range read |
|---|---|---|

## Self-falsification pass (as many as your prompt's `{REFINE_PASSES}` names)
What I tried to refute in my own findings above and what changed: … / "clean".

## Range read (required — absence claims invalid without it)
Files read to their ends (line counts confirmed); greps with scope and printed,
classified hits.
