#!/usr/bin/env bash
# drill/drill-tworepo.sh — a doc-bound slice delivered into the DOC checkout
# with the code repo's acceptance command never run (owner ruling D-i), walked
# end to end. Split from drill-walk.sh so the three full-slice walks run
# concurrently under `check.sh --jobs`.
# Rows: S10 two-repo doc delivery.
# Skips (rc 77) without tmux.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

echo "-- S10 (two-repo): a doc-bound slice delivers into the DOC checkout; code acceptance never runs --"
ws=$(mk_drill_ws drillS10)
b10=$(cd "$ws/../../.." && pwd)
read -r drepo dbranch < <(mk_doc_repo "$b10/docrepo")
s10code=$(sed -n 's/^repo=//p' "$ws/project.kv" | head -1)
printf 'doc.repo=%s\ndoc.branch=%s\nacceptance=touch %s/ACCEPTANCE_RAN\n' \
  "$drepo" "$dbranch" "$b10" >> "$ws/project.kv"
cat > "$ws/.mock/plan" <<'EOF'
plan-validate=ready
split=done
split.slices=01:low:doc:shipped_docs
split-check=concur
spec=drafted
precheck=ready
impl=built
postcheck=conforms
turnover=done
close-out=done
EOF
log=$(sc_tmpdir)/ferry.log
run_ferry "$ws" "$log"; rc=$?
[ $rc -eq 0 ] && ok "ferry exits 0: a doc-bound topic walks the whole table to COMPLETE" \
  || bad "rc=$rc; halt=$(halt_kv "$ws" reason) $(halt_kv "$ws" detail); log tail: $(tail -5 "$log"); mock: $(tail -8 "$ws/.mock/log" 2>/dev/null)"
state_get "$ws" slices | command grep -q "repo=doc" \
  && ok "the index carries the doc binding cast at split" \
  || bad "index: $(state_get "$ws" slices)"
p10=$(ls "$ws/.runtime/prompts/01-impl-"*.md 2>/dev/null | head -1)
precond "the impl prompt exists" test -n "$p10"
command grep -q "^binding: kind=doc repo=$drepo" "$p10" \
  && ok "its volatile header named the doc checkout — the channel the session used to land there" \
  || bad "binding line: $(command grep -m1 '^binding:' "$p10" 2>/dev/null)"
sha=$(state_get "$ws" progress | command grep -oE 'sha=[0-9a-f]+' | head -1 | cut -d= -f2)
precond "the doc slice landed a commit-unit" test -n "$sha"
git -C "$drepo" rev-parse -q --verify "$sha^{commit}" > /dev/null \
  && ok "the landed SHA resolves in the DOC repo (delivery went to the bound checkout)" \
  || bad "SHA $sha does not resolve in the doc repo"
git -C "$s10code" rev-parse -q --verify "$sha^{commit}" > /dev/null 2>&1 \
  && bad "the same SHA also exists in the code repo — the fixture cannot tell the checkouts apart" \
  || ok "and NOT in the code repo (the assertion above is not vacuous)"
[ ! -e "$b10/ACCEPTANCE_RAN" ] \
  && ok "TRIPWIRE: the project's acceptance command never ran anywhere in a doc-bound topic" \
  || bad "the code repo's acceptance command RAN for a doc-bound slice (D-i broken end-to-end)"
state_get "$ws" gates | command grep 'gate=acceptance' | tail -1 | command grep -q 'result=SKIP' \
  && ok "the impl close attested the structural acceptance SKIP" \
  || bad "acceptance record: $(state_get "$ws" gates | command grep 'gate=acceptance' | tail -1)"
state_get "$ws" gates | command grep -q "gate=commit .*result=PASS" \
  && ok "the doc cu still passed the project's commit convention (one convention, both checkouts)" \
  || bad "no commit-gate PASS for the doc cu"
n=$(state_get "$ws" audit | command grep -c "repo lock taken" || true)
[ "${n:-0}" -ge 2 ] \
  && ok "the production entry claimed BOTH checkouts (wiring trace, $n takes)" \
  || bad "only ${n:-0} repo-lock take(s) audited — the doc claim is not wired into main()"
[ ! -f "$(git -C "$drepo" rev-parse --absolute-git-dir)/delivery.lock" ] \
  && [ ! -f "$(git -C "$s10code" rev-parse --absolute-git-dir)/delivery.lock" ] \
  && ok "both claims released at COMPLETE (releasing one would strand the other checkout)" \
  || bad "a claim survived COMPLETE"
scen_end

check_done
