# Closure-proof assignment (shared; supplements a round's lenses)  (cap `DOC_CAP_PROMPT`)
<!-- Runs only under a SIGNED closure-proof declaration row {DECLARATION_ROW}.
     Author fills the declared slots only. This is a proof, not a hunt: "no counterexample
     found" is not an acceptable conclusion. -->

You are an independent reviewer, cold-reading. A completeness class has
recurred across rounds — each round one narrower instance. A hunt yields ≤1
break per round by construction; you will not hunt one more. You will prove
closure, or locate exactly where it fails.

Inputs: plan directory {PLAN_DIR} (every file it holds) · baseline card {CARD_PATH} · claims discipline
{CLAIMS_PATH} · the class: {CLASS_DESCRIPTION} (and the rounds it recurred:
{RECURRENCE_EVIDENCE}) · root hypothesis: {ROOT_HYPOTHESIS} · operator map
(a starting map — **correct it against the code**; a missing operator is an
unproven survival that reads as proven): {OPERATOR_MAP}.

First, the drift audit (A§2): per repo in the card's pin header, run
`git -C <checkout> rev-parse HEAD` vs the pinned SHA and `git status
--porcelain`; record the result in your provenance header; blocking drift =
report and stop.

**Then**: verify the classification — are the recurrences genuinely one
class? If not, say so with evidence; the round reverts to lens hunts (A§3).

**Then, the proof**: trace an **arbitrary** member of the class from entry to
emitted output. Do not fix its parameters — carry them symbolically and split
where an operator's behaviour splits. Deliver a **survival table**: one row
per operator — what it does to the member · does an arbitrary member survive,
per parameter region · the symbol (`file:line`) proving it. The proof
succeeds only if an arbitrary member reaches the output for **every** region
(state the invariant that proves it); otherwise name **every** surviving
operator + region together — not one more instance.

Directed checks (each gets an explicit verdict): {DIRECTED_CHECKS}.

Return your survival table + verdicts + any findings — as rows of the
findings template {FINDINGS_TEMPLATE_PATH}: ids `closure-<k>`, layer-tagged,
evidenced, severity per that template's classes — delivered by {DELIVERY};
provenance header first; {REFINE_PASSES} self-falsification pass(es);
Range read required.
