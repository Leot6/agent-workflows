#!/usr/bin/env bash
# drill/drill-pager.sh — the pager over a REAL park: the mock author halts
# class_u, the ferry exits 20, the shadow watchdog re-pages through a recording
# transport to the cap and exits 0; then a second park with a long interval,
# where `launch.sh status --halt` reads the pager's record, `launch.sh stop`
# ends the paging watchdog (the takeover path launch shares), and `launch.sh
# ack` writes the receipt status reads back. Everything the unit fixtures in
# 85-watchdog / 35-verbs rehearse over hand-written halts, here over the halt
# the ferry itself writes (real halt_id, real notify policy, real config path).
# Rows: S4p pager round-trip.
# Skips (rc 77) without tmux.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
WATCHDOG="$SHADOW/runtime-scripts/watchdog.sh"
precond "shadow watchdog exists" test -x "$WATCHDOG"

tdir=$(sc_tmpdir)
PAGES="$tdir/pages.log"; : > "$PAGES"
rec="$tdir/transport.sh"
printf '#!/usr/bin/env bash\nprintf "%%s %%s\\n" "$1" "$2" >> "%s"\n' "$PAGES" > "$rec"; chmod +x "$rec"

echo "-- S4p: a real class_u park is re-paged to the cap through the transport --"
ws=$(mk_drill_ws drillS4p "notify.cmd=$rec
notify.repage_interval=1
notify.repage_max=2")
printf 'plan-validate:1=halt\n' > "$ws/.mock/plan"
log=$tdir/watchdog.log
shadow_env timeout 120 "$WATCHDOG" "$ws" >> "$log" 2>&1; rc=$?
[ $rc -eq 0 ] && ok "watchdog over a parking ferry exits 0 once the pager is done (rc=$rc)" \
  || bad "watchdog rc=$rc ($(tail -3 "$log" | tr '\n' ' '))"
[ "$(halt_kv "$ws" reason)" = "class_u" ] \
  && ok "the park is the ferry's own class_u halt (record-level --halt routed from the mock stage)" \
  || bad "halt reason='$(halt_kv "$ws" reason)'"
hid=$(halt_kv "$ws" halt_id)
precond "the real halt carries a halt_id (else the audit-keyed arms below are vacuous)" test -n "$hid"
[ "$(command grep -c 'RE-PAGE [0-9]/2 ' "$PAGES")" -eq 2 ] \
  && ok "exactly repage_max=2 re-pages reached the transport, numbered n/max" \
  || bad "re-pages in the transport log: $(command grep -c 'RE-PAGE' "$PAGES") — $(cat "$PAGES" | cut -c1-120 | tr '\n' ' ')"
command grep -q 'RE-PAGE stopped after 2' "$PAGES" \
  && ok "…and the cap message went out last" || bad "no cap message: $(tail -1 "$PAGES")"
[ "$(command grep -c . "$PAGES")" -ge 4 ] \
  && ok "the park's own page preceded them (≥ 4 lines: park, 2 re-pages, stop)" \
  || bad "transport log has $(command grep -c . "$PAGES") lines"
[ "$(state_get "$ws" audit 2>/dev/null | command grep -c "repage [0-9]/2 halt_id=$hid ")" -eq 2 ] \
  && ok "both re-pages are audited under the REAL halt_id ($hid)" \
  || bad "audit repage rows for $hid: $(state_get "$ws" audit 2>/dev/null | command grep -c 'repage ')"
[ ! -e "$ws/.runtime/watchdog.pid" ] && ok "pidfile cleared after the pager exited" || bad "pidfile left behind"
scen_end

echo "-- S4p-2: status reads the pager's record; stop ends the paging; ack is the receipt --"
: > "$PAGES"
ws2=$(mk_drill_ws drillS4p2 "notify.cmd=$rec
notify.repage_interval=60
notify.repage_max=2")
printf 'plan-validate:1=halt\n' > "$ws2/.mock/plan"
log2=$tdir/watchdog2.log
shadow_env "$WATCHDOG" "$ws2" >> "$log2" 2>&1 & wpid=$!
for _ in $(seq 1 240); do [ -f "$ws2/.runtime/final-state" ] && break; sleep 0.25; done
sleep 0.5
precond "the ferry parked and the watchdog is PAGING (final-state parked on disk, pid alive)" \
  bash -c 'command grep -q "^class=parked " "$1/.runtime/final-state" && kill -0 "$2"' _ "$ws2" "$wpid"
out=$(shadow_env "$LAUNCH" status "$ws2" --halt 2>&1); rc=$?
[ $rc -eq 0 ] && printf '%s\n' "$out" | command grep -q '^re-paged *0 time' && printf '%s\n' "$out" | command grep -q '^acked *no' \
  && ok "status --halt over the live park: 0 re-pages (interval pending), not acked" \
  || bad "status --halt: rc=$rc $(printf '%s' "$out" | command grep -E 're-paged|acked' | tr '\n' ' ')"
out=$(shadow_env "$LAUNCH" stop "$ws2" 2>&1); rc=$?
[ $rc -eq 0 ] && printf '%s\n' "$out" | command grep -q 're-paging stopped' \
  && ok "launch.sh stop over the paging watchdog: rc=0 and it says the paging was ended" \
  || bad "stop over a pager: rc=$rc $(printf '%s' "$out" | head -2 | tr '\n' ' ')"
for _ in $(seq 1 20); do kill -0 "$wpid" 2>/dev/null || break; sleep 0.1; done
kill -0 "$wpid" 2>/dev/null && { bad "the paging watchdog survived stop"; kill -9 "$wpid" 2>/dev/null; } \
  || ok "the paging watchdog is gone (SIGTERM reached it inside its 60 s wait)"
wait "$wpid" 2>/dev/null
[ ! -e "$ws2/.runtime/watchdog.pid" ] && ok "…pidfile cleared" || bad "pidfile left behind after stop"
[ ! -e "$ws2/.runtime/stop-request" ] && ok "…and no stop-request was written (nothing would read it)" || bad "a stop-request was written for a pager"
[ ! -s "$PAGES" ] || command grep -q 'RE-PAGE' "$PAGES" && bad "a re-page went out before the interval: $(cat "$PAGES")" || ok "no re-page was sent in the meantime (interval 60 s)"
shadow_env "$LAUNCH" ack "$ws2" > /dev/null 2>&1 && ok "launch.sh ack over the real halt: rc=0" || bad "ack refused over a real unresolved halt"
out=$(shadow_env "$LAUNCH" status "$ws2" --halt 2>&1)
printf '%s\n' "$out" | command grep -q '^acked *at t=[0-9]' \
  && ok "status --halt reads the receipt back: acked at t=<epoch>" \
  || bad "status --halt does not show the ack: $(printf '%s' "$out" | command grep acked)"
scen_end

check_done
