#!/usr/bin/env bash
# 30-constants — `protocol.md §defaults` is the single home of every tuning
# value (A§5.3). Both directions: every constant referenced anywhere in the
# tree has a row, and every row is referenced by something. An orphan row is
# a value nothing obeys; an unrowed reference is a value with no home, which
# is the case A§5.3 declares a defect outright.
#
# HONEST BOUNDARY: this checks that a name is defined and used, never that the
# number is right. `ROUND_MAX = 5` and `ROUND_MAX = 500` pass identically —
# the value's justification lives in the debt ledger and the model-dependency
# register, and re-deriving it is a live topic's job, not a script's.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/fixtures/lib.sh"

defined=$(defaults_table | cut -f1 | sort -u)
# A constant reference is a backticked ALL-CAPS token, digits admitted (a
# `P95_*` or `T2_*` row would otherwise be outside the single-home discipline
# in both directions). `<PLANS_ROOT>` and the placeholder tokens (TBD/TODO/…)
# are not backticked ALL-CAPS and do not match.
#
# The §defaults ROWS THEMSELVES are excluded from the "used" set. Without this
# every row matches its own use-pattern, `defined ⊆ used` holds by
# construction, and the orphan direction — the half the header calls
# load-bearing — can never fire.
used=$(harvest_docs | xargs grep -hoE '`[A-Z][A-Z_0-9]{3,}`' 2>/dev/null \
       | tr -d '`' | sort -u)
used_outside_table=$(harvest_docs | xargs grep -hvE '^\| `[A-Z_0-9]+` \|' 2>/dev/null \
       | grep -oE '`[A-Z][A-Z_0-9]{3,}`' | tr -d '`' | sort -u)
# The harness consumes some constants programmatically rather than in prose
# (cap_for maps files to DOC_CAP_* names), so a name used only by a check is
# still obeyed by something. COMMENTS ARE STRIPPED FIRST: a check that merely
# mentions a constant — including one saying it does not verify it — must not
# rescue an orphan row. Measured: without this, `PHANTOM_CAP` plus a one-line
# comment passed the orphan direction green.
used_by_checks=$(find "$WF_ROOT/self-check" -name '*.sh' -exec sed 's/#.*//' {} + \
       | grep -oE '\b[A-Z][A-Z_0-9]{3,}\b' | sort -u)
used_real=$(printf '%s\n%s\n' "$used_outside_table" "$used_by_checks" | sort -u)

precond "§defaults yielded rows"   test "$(printf '%s\n' "$defined" | grep -c .)" -ge 15
precond "the tree yielded references" test "$(printf '%s\n' "$used" | grep -c .)" -ge 15

orphan=$(comm -23 <(printf '%s\n' "$defined") <(printf '%s\n' "$used_real"))
unhomed=$(comm -13 <(printf '%s\n' "$defined") <(printf '%s\n' "$used"))

[ -z "$orphan" ] \
  && ok "every §defaults row is obeyed by something outside its own row" \
  || bad "§defaults rows nothing references: $(echo "$orphan" | tr '\n' ' ')"
[ -z "$unhomed" ] \
  && ok "every referenced constant has a §defaults row" \
  || bad "constants used with no §defaults row: $(echo "$unhomed" | tr '\n' ' ')"

# Exactly one row per constant — a second row is a second home.
dupes=$(defaults_table | cut -f1 | sort | uniq -d)
[ -z "$dupes" ] && ok "no constant has two rows" || bad "duplicate §defaults rows: $dupes"

# Every row states a unit (the A§5.3 row says "with units").
missing_unit=$(awk -F'|' '/^\| `[A-Z_]+` \|/ { u=$4; gsub(/ /,"",u); if (u=="") { n=$2; gsub(/[` ]/,"",n); print n } }' \
  "$WF_ROOT/runtime-docs/protocol.md")
[ -z "$missing_unit" ] && ok "every row states its unit" || bad "rows with no unit: $missing_unit"

# Non-vacuity: run the SAME extraction the sweep uses over a fabricated doc
# carrying a constant with no §defaults row, and assert it comes back unhomed.
BT='`'
probe_dir=$(sc_tmpdir)
printf 'the %sNOT_A_REAL_CONSTANT%s value\n' "$BT" "$BT" > "$probe_dir/probe.md"
probe_is_clean() {
  local u
  u=$(grep -rhoE "${BT}[A-Z][A-Z_]{3,}${BT}" "$probe_dir" | tr -d "$BT" | sort -u)
  [ -z "$(comm -13 <(printf '%s\n' "$defined") <(printf '%s\n' "$u"))" ]
}
known_bad "an unhomed constant is caught" probe_is_clean

check_done
