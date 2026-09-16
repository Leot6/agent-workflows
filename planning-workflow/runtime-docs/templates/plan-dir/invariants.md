<!-- invariants.md — cross-item invariants and closing notes (the old plan's
     ## 闭合不变量-style tail). Items may reference these by heading. -->

# Invariants

<cross-item invariants, closing notes, release-notes constraints — anything
that spans items and must survive item-file edits. Reference from items as
`invariants.md#<heading>`.>

**A sentence here that cites a baseline-card row's STATE is a snapshot of that
state, and must be marked 「冻结时快照；当前状态以卡片为准」.** The version
freezes (protocol §4.4.4) *before* the verifier clearing `unverified` rows is
dispatched (§4.4.5), and a frozen
version is never edited — a correction is the next version index. So a row
this file calls `unverified` is, by that ordering, one the same round is about
to flip, and the bytes saying otherwise are permanent. Write the mark
into the sentence, naming the row and the check record that will carry the
verdict:

> I-<n>（**冻结时快照：<row> `unverified`；当前状态以卡片为准**,
> 见 `rounds/<n>/check_<k>.md`）……

Carried ruling text, gloss: *snapshot at freeze time; the card is authoritative
for the current state.* Unmarked, the sentence reads as a live claim that the
plan's own dispatch precondition is unmet, and a cold lens spends a question on
it — the reader cannot tell a stale assertion from a standing one, and the
plan's own bytes give no way to check.
