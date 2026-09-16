#!/usr/bin/env bash
# 96-comment-chronology — a source comment carries the contract and a pointer,
# never the chronology (maintenance.md §1). The mechanical tell is a date token
# (YYYY-MM) inside a comment line under runtime-scripts/ or config/: a date
# marks a measurement, and a measurement's home is iteration-log/, where one
# correction reaches every reader and the harvest re-derives it. The rule is a
# grammar rule, deliberately: a list of narrative shapes would rot the way every
# shape list in this tree has. What it cannot see is a narrative with no date in
# it — that half stays a writing duty (maintenance.md §1).
set -uo pipefail
export LC_ALL=C
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/fixtures/lib.sh"

# One extractor for the live tree and the known-bads, so the fixtures drive the
# same code. Comment lines only: a date inside a kv VALUE, a signature literal or
# a string is data and is not swept (`^[[:space:]]*#` anchors it).
chrono_sweep() { # <root> -> "path:line: text" per dated comment line; rc 0 clean / 1 hits / 2 broken
  local out rc
  out=$(cd "$1" && command grep -rnE '^[[:space:]]*#.*20[0-9]{2}-[0-9]{2}' \
          runtime-scripts config --include='*.sh' --include='*.kv' --include='*.tsv' 2>/dev/null)
  rc=$?
  case $rc in
    0) printf '%s\n' "$out"; return 1 ;;
    1) return 0 ;;
    *) echo "grep could not sweep $1 (rc $rc)"; return 2 ;;
  esac
}

echo "-- the live tree: no dated comment under runtime-scripts/ or config/ --"
n_src=$(find "$WF_ROOT/runtime-scripts" "$WF_ROOT/config" -type f \( -name '*.sh' -o -name '*.kv' -o -name '*.tsv' \) | command grep -c . || true)
precond "the sweep sees N>=25 source files under runtime-scripts/ + config/ (saw $n_src) — an emptied root would read clean" \
  test "${n_src:-0}" -ge 25
hits=$(chrono_sweep "$WF_ROOT"); rc=$?
case $rc in
  0) ok "no comment line under runtime-scripts/ or config/ carries a date token ($n_src files swept)" ;;
  1) bad "dated comment lines — move the measurement to its iteration-log entry and leave the pointer:"$'\n'"$(printf '%s\n' "$hits" | sed 's/^/    /')" ;;
  *) bad "the sweep did not complete: $hits" ;;
esac

echo "-- known-bads: the shape fires; data and pointers do not --"
kb=$(sc_tmpdir); mkdir -p "$kb/runtime-scripts/lib" "$kb/config"
printf '#!/usr/bin/env bash\n# measured 2026-09-01 on one topic: nine rows\nx=1\n' > "$kb/runtime-scripts/lib/dated.sh"
out=$(chrono_sweep "$kb"); rc=$?
[ $rc -eq 1 ] && printf '%s\n' "$out" | command grep -q 'dated.sh:2:' \
  && ok "known-bad: a dated comment in a runtime script fires, naming file and line" \
  || bad "known-bad did not fire (rc=$rc): $out"
printf '# calibrated on the drill: see iteration-log: some-entry\nkey=2026-09-01\n' > "$kb/config/values.kv"
rm -f "$kb/runtime-scripts/lib/dated.sh"
chrono_sweep "$kb" > /dev/null; rc=$?
[ $rc -eq 0 ] \
  && ok "a date in a kv VALUE and a comment carrying only a pointer are not hits (data and pointers are the intended shapes)" \
  || bad "a value line or a pointer comment fired (rc=$rc) — the arm would refuse its own remedy"
printf '# --- caps (2026-09-01 calibration) ---\nk=1\n' > "$kb/config/dated.kv"
out=$(chrono_sweep "$kb"); rc=$?
[ $rc -eq 1 ] && printf '%s\n' "$out" | command grep -q 'dated.kv:1:' \
  && ok "known-bad: a dated comment in a config file fires too (config/ is in scope)" \
  || bad "a dated config comment did not fire (rc=$rc): $out"
rm -rf "$kb/runtime-scripts" "$kb/config"; mkdir -p "$kb/runtime-scripts" "$kb/config"
out=$(chrono_sweep "$kb"); rc=$?
[ $rc -eq 0 ] \
  && ok "two EMPTY directories read clean from the sweep itself — which is why the live arm is floored on the file count above" \
  || bad "an empty root did not read clean (rc=$rc): $out"
rm -rf "$kb/config"
out=$(chrono_sweep "$kb"); rc=$?
[ $rc -eq 2 ] \
  && ok "…and a MISSING directory is a broken sweep (rc 2), never a clean verdict — grep's error status is not folded into 'nothing matched'" \
  || bad "a missing config/ read as rc=$rc, want 2 (broken): $out"

check_done
