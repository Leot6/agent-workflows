#!/usr/bin/env bash
# 40-regions — the formal region carries no dates and no state-row ids
# (A§5.1). State rows prune at retro and observation rows retire, so a pointer
# from a permanent document into one is a dangling reference by construction;
# a date-stamp in a settled ruling discriminates nothing and ages into a false
# signal. The reverse pointer — a debt row naming the ruling that seeded it —
# is the load-bearing one and is untouched here.
#
# HONEST BOUNDARY: this catches the two TOKEN shapes, `YYYY-MM` and
# `VD-<n>`/`OBS-<n>`. Prose that encodes state without them ("as of this
# writing", "currently three of these are open") reads clean and is exactly
# what the owner caught by hand. Bare years in a citation (Klein 2007,
# arXiv 2310.01798) are deliberately not matched — a citation is evidence,
# not state.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/fixtures/lib.sh"

DATE_RE='20[0-9][0-9]-(0[1-9]|1[0-2])([^0-9]|$)'  # a month, so 2007-2009 is a citation range, not a stamp
STATE_RE='\b(VD|OBS)-[0-9]+'

n=0
while IFS= read -r doc; do
  [ -f "$doc" ] || continue
  rel=${doc#"$WF_ROOT"/}
  n=$((n + 1))
  hits=$(grep -nE "$DATE_RE" "$doc" || true)
  [ -z "$hits" ] || bad "$rel carries a date-stamp:"$'\n'"$(printf '%s' "$hits" | sed 's/^/        /')"
  hits=$(grep -nEo "$STATE_RE" "$doc" | sort -u || true)
  [ -z "$hits" ] || bad "$rel points at state rows: $(printf '%s' "$hits" | tr '\n' ' ')"
done < <(formal_docs)
precond "the sweep saw the whole formal region" test "$n" -ge 20
[ "$_FAIL" -eq 0 ] && ok "$n formal documents carry no date-stamp and no state-row id"

# The state file is where both legitimately live — a tree with neither has
# lost its self-iteration channel, so assert the reverse direction exists.
# The INDEX's three homes are asserted by their headings: a fresh deployment
# has no OBS/WQ rows yet, and that is a state, not a lost channel — it is
# named rather than failed. The debt ledger is never empty in a tree that
# carries mechanisms awaiting live evidence, so its rows stay required.
LOG_DIR="$WF_ROOT/iteration-log"
LOG="$LOG_DIR/INDEX.md"; VD="$LOG_DIR/validation-debt.md"
miss=""
for h in '## Open observations' '## Owner queue' '## Index'; do
  grep -q "^$h" "$LOG" || miss="$miss '$h'"
done
[ -z "$miss" ] && ok "the state file still carries its three homes (INDEX: open families, owner queue, index list)" \
  || bad "iteration-log/INDEX.md lost its section(s):$miss — the reverse pointer has nowhere to land"
grep -qE "^\| (OBS|WQ)-[0-9]+" "$LOG" \
  || note "fresh state file: INDEX.md carries no OBS/WQ rows yet"
grep -qE "^\| VD-[0-9]+" "$VD" && ok "the debt ledger still carries its rows" \
  || bad "iteration-log/validation-debt.md has no VD rows — the ledger is gone"
grep -q 'A§13' "$VD" "$LOG" && ok "debt rows still name the ruling that seeded them" \
  || bad "the iteration log no longer references A§13 — the back-pointer is gone"

# Non-vacuity: run the check's OWN patterns (not re-typed copies) over a
# fabricated document carrying both banned shapes.
probe_dir=$(sc_tmpdir)
printf 'ruling (2026-08-15, same standing), debt VD-14\nKlein, HBR 2007-2009 is a citation, not a stamp\n' > "$probe_dir/probe.md"
probe_is_clean() {
  ! grep -qE "$DATE_RE" "$probe_dir/probe.md" && ! grep -qE "$STATE_RE" "$probe_dir/probe.md"
}
known_bad "a date-stamp and a state-row id are both caught" probe_is_clean

check_done
