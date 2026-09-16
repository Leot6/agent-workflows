#!/usr/bin/env bash
# 98-emit-gate — the tree-owned red gate proves its three arms in both
# directions. The gate's own header carries the honest boundary; this
# check's job is narrower: the KNOWN-BAD direction of each arm must fire and
# the clean direction must pass, over fixture plan directories — a gate that
# cannot fire is a printer, which is exactly the class it exists to retire
# (obs-86).
#
# HONEST BOUNDARY: fixtures are minimal; real prose will hit shapes the
# key-window heuristic mis-keys on (a false negative — two claims keyed
# differently — or a false positive on coincidental windows). The gate's
# findings feed the author's refine loop, not a hard stop: protocol §4.4 runs
# it at emit and the author clears or justifies each red before freeze. Its
# false-positive rate is a Phase V measurement, not a claim.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/fixtures/lib.sh"

GATE="$WF_ROOT/runtime-scripts/emit_gate.sh"
precond "emit_gate.sh exists and parses" bash -n "$GATE"

mk() { local d=$1; mkdir -p "$d/items"; printf '# ctx\n' > "$d/00_context.md"; echo "$d"; }

# --- arm 1: currency counts ---------------------------------------------------
d=$(sc_tmpdir)/cur; mk "$d"; printf '# W-1\n`$ wc -l f` → 5 lines at HEAD\n' > "$d/items/W-1.md"
out=$("$GATE" "$d" "$d" 2>&1); rc=$?
[ $rc -eq 0 ] && ok "arm1 clean: a count at HEAD WITH its inline command passes" \
  || bad "arm1 false positive on a carried command: $out"
printf '# W-1\n412 lines at HEAD with no command anywhere near\n' > "$d/items/W-1.md"
out=$("$GATE" "$d" "$d" 2>&1); rc=$?
[ $rc -eq 1 ] && printf '%s' "$out" | grep -q 'reading-currency' \
  && ok "arm1 known-bad: a bare currency count fires (the 412-lines escape)" \
  || bad "arm1 did not fire on a bare currency count (rc=$rc): $out"

# --- arm 2: same-construct divergence ------------------------------------------
d=$(sc_tmpdir)/div; mk "$d"
printf '# W-1\n恰 5 处构造 K\n构造 K 共 7 处\n' > "$d/items/W-1.md"
out=$("$GATE" "$d" "$d" 2>&1); rc=$?
[ $rc -eq 1 ] && printf '%s' "$out" | grep -q 'same-section' \
  && ok "arm2 known-bad: same construct claimed 5 and 7 fires (obs-84 fingerprint)" \
  || bad "arm2 did not fire on divergent counts (rc=$rc): $out"
printf '# W-1\n恰 5 处构造 K\n构造 K 亦 5 处\n' > "$d/items/W-1.md"
out=$("$GATE" "$d" "$d" 2>&1); rc=$?
[ $rc -eq 0 ] && ok "arm2 clean: agreeing counts pass" \
  || bad "arm2 false positive on agreeing counts: $out"

# --- arm 3: cite resolution -----------------------------------------------------
d=$(sc_tmpdir)/cite; mk "$d"
mkdir -p "$d/src"; printf 'x\ny\nz\n' > "$d/src/a.cc"
printf '# W-1\nsee src/a.cc:1\n' > "$d/items/W-1.md"
out=$("$GATE" "$d" "$d" 2>&1); rc=$?
[ $rc -eq 0 ] && ok "arm3 clean: a resolving pin passes" \
  || bad "arm3 false positive on a good pin: $out"
printf '# W-1\nsee src/a.cc:99\n' > "$d/items/W-1.md"
out=$("$GATE" "$d" "$d" 2>&1); rc=$?
[ $rc -eq 1 ] && printf '%s' "$out" | grep -q 'cite' \
  && ok "arm3 known-bad: a pin beyond EOF fires" \
  || bad "arm3 did not fire on an out-of-range pin (rc=$rc): $out"
printf '# W-1\nsee src/ghost.cc:1\n' > "$d/items/W-1.md"
out=$("$GATE" "$d" "$d" 2>&1); rc=$?
[ $rc -eq 1 ] && printf '%s' "$out" | grep -q 'unresolved' \
  && ok "arm3 known-bad: an unresolved path fires" \
  || bad "arm3 did not fire on an unresolved path (rc=$rc): $out"

# fenced pins are QUOTED DATA, not live citations (strip_fences)
printf '# W-1\n```\nsrc/fenced.cc:1\n```\n' > "$d/items/W-1.md"
out=$("$GATE" "$d" "$d" 2>&1); rc=$?
[ $rc -eq 0 ] && ok "arm3 fences: a pin inside a fence is data, not a claim (not checked)" \
  || bad "arm3 fired on a fenced pin — strip_fences broke: $out"

check_done
