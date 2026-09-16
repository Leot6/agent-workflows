#!/usr/bin/env bash
# 65-notify — lib/notify.sh policy: preset selection from the hot-read notify
# surface (runtime-changeable without relaunch), per-event overrides in
# both directions, mechanical predicate (event type only), and transport
# best-effort behavior (empty cmd is named, never fatal).
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/fixtures/lib.sh"
. "$RS/lib/state.sh"
. "$RS/lib/notify.sh"

base=$(sc_tmpdir)
read -r repo branch < <(mk_repo "$base/repo")
ws=$(mk_ws "$base" notifytopic "$repo" "$branch")

echo "-- preset selection (closed vocabulary, notify-presets.kv) --"
( . "$RS/lib/state.sh"; state_put "$ws" notify operator "preset=key-points" ) > /dev/null
assert_rc 0 "key-points: park.* fires" -- _notify_decide "$ws" park.owed_miss
assert_rc 0 "key-points: broken fires" -- _notify_decide "$ws" broken
assert_rc 0 "key-points: topic.done fires" -- _notify_decide "$ws" topic.done
assert_rc 1 "key-points: slice.done suppressed (bad direction)" -- \
  _notify_decide "$ws" slice.done
assert_rc 1 "key-points: commit.done suppressed" -- _notify_decide "$ws" commit.done
( . "$RS/lib/state.sh"; state_put "$ws" notify operator "preset=per-slice" ) > /dev/null
assert_rc 0 "HOT preset change to per-slice: slice.done now fires (no relaunch)" -- \
  _notify_decide "$ws" slice.done
assert_rc 1 "per-slice: commit.done still suppressed" -- _notify_decide "$ws" commit.done
( . "$RS/lib/state.sh"; state_put "$ws" notify operator "preset=all" ) > /dev/null
assert_rc 0 "preset all: everything fires" -- _notify_decide "$ws" commit.done

echo "-- per-event overrides beat the preset, both directions --"
( . "$RS/lib/state.sh"
  state_put "$ws" notify operator "preset=key-points" "event.park.owed_miss=off" \
    "event.commit.done=on" ) > /dev/null
assert_rc 1 "event=off suppresses a preset-included event" -- \
  _notify_decide "$ws" park.owed_miss
assert_rc 0 "other park reasons unaffected by the targeted override" -- \
  _notify_decide "$ws" park.no_novelty
assert_rc 0 "event=on admits a preset-excluded event" -- _notify_decide "$ws" commit.done
assert_rc 0 "notify.test always fires (the launch preflight's lifeline probe)" -- \
  _notify_decide "$ws" notify.test

echo "-- launch.sh notify verb writes the surface --"
"$WF_ROOT/runtime-scripts/launch.sh" notify "$ws" per-commit > /dev/null 2>&1 \
  && ok "launch.sh notify <preset> accepted" || bad "launch.sh notify preset failed"
[ "$(state_field "$ws" notify preset)" = "per-commit" ] \
  && ok "preset landed in the notify surface" || bad "preset not written"
assert_rc 2 "unknown preset refused, naming the file" -- \
  "$WF_ROOT/runtime-scripts/launch.sh" notify "$ws" no-such-preset
assert_rc 2 "event outside the closed vocabulary refused" -- \
  "$WF_ROOT/runtime-scripts/launch.sh" notify "$ws" "weird.event=on"
assert_rc 0 "closed-vocabulary event override accepted" -- \
  "$WF_ROOT/runtime-scripts/launch.sh" notify "$ws" "park.owed_miss=off"

echo "-- notify_fire transport (best-effort; type-only predicate) --"
# Full surface reset: the earlier sections left per-event overrides behind.
( . "$RS/lib/state.sh"
  printf 'preset=key-points\n' | state_set "$ws" notify operator ) > /dev/null
assert_rc 1 "empty notify.cmd: event named as transportless, rc 1 (undelivered — the caller must NOT set the notified flag)" -- \
  notify_fire "$ws" park owed_miss "message content is payload only"
assert_out_has "no transport" "empty transport is loud"
echo "notify.cmd=printf '%s|%s\\n' > $base/notified.txt" > "$ws/config/topic.kv"
assert_rc 0 "working transport delivers with rc 0 (caller may set the notified flag)" -- \
  notify_fire "$ws" park owed_miss "the payload"
precond "transport fixture wrote its file" test -s "$base/notified.txt"
command grep -q '^park.owed_miss|' "$base/notified.txt" \
  && ok "transport receives <event> <message>, event canonicalized park.<reason>" \
  || bad "transport got: $(cat "$base/notified.txt")"
rm -f "$base/notified.txt"
assert_rc 0 "policy-suppressed event is rc 0 (deliberate silence — the notified flag MAY be set; no resend owed)" -- \
  notify_fire "$ws" slice.done none "suppressed by key-points"
[ ! -e "$base/notified.txt" ] \
  && ok "policy-suppressed event never reaches the transport (bad direction)" \
  || bad "suppressed event fired anyway"
echo "notify.cmd=/bin/false" > "$ws/config/topic.kv"
assert_rc 1 "failing transport is audited + rc 1, never fatal to the caller (at-least-once: flag stays unset, relaunch re-sends)" -- \
  notify_fire "$ws" park owed_miss "x"
assert_out_has "transport failed" "failure is named"

echo "-- pluggable transports: notify.transport names an adapter, notify.cmd overrides --"
# The seam's shape is the backend seam's: a NAME resolved against a directory.
# A platform is a dropped-in script plus one config line — the workflow bakes
# in none. Hermetic proof: a PATH-stub curl records what the adapter would
# send (no network), and the key rides the operator config area, which
# fixtures/lib.sh points at the session tmp for exactly this.
tbin="$base/bin"; mkdir -p "$tbin"
cat > "$tbin/curl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$CURL_RECORD"
echo "${CURL_HTTP:-200}"
exit "${CURL_RC:-0}"
EOF
chmod +x "$tbin/curl"
export CURL_RECORD="$base/curl-args.txt"
export PATH="$tbin:$PATH"
opcfg="$XDG_CONFIG_HOME/delivery-workflow"; mkdir -p "$opcfg"
printf 'https://bark.test/t0ken\n' > "$opcfg/bark.url"
rm -f "$ws/config/topic.kv"
echo "notify.transport=bark" > "$ws/config/topic.kv"
rm -f "$CURL_RECORD"
assert_rc 0 "notify.transport=bark fires the shipped adapter (rc 0 = delivered)" -- \
  notify_fire "$ws" park owed_miss "pluggable body"
precond "the adapter reached curl" test -s "$CURL_RECORD"
command grep -q 'https://bark.test/t0ken' "$CURL_RECORD" \
  && ok "the adapter picked its key from the operator config area (bark.url)" \
  || bad "key pickup wrong: $(head -1 "$CURL_RECORD")"
command grep -q 'delivery-workflow · park.owed_miss' "$CURL_RECORD" \
  && ok "the push carries the event in its title (adapter contract: <event> <message>)" \
  || bad "title missing the event: $(tr '\n' ' ' < "$CURL_RECORD" | cut -c1-160)"
CURL_HTTP=500 assert_rc 1 "a non-200 push is rc 1 — an adapter must not lie green (at-least-once re-sends)" -- \
  notify_fire "$ws" park owed_miss "x"
assert_out_has "transport failed" "the endpoint failure is named, not swallowed"
echo "notify.transport=no-such" > "$ws/config/topic.kv"
assert_rc 1 "an unknown transport name is loud, naming the adapter directory" -- \
  notify_fire "$ws" park owed_miss "x"
assert_out_has "transports/" "the refusal points where an adapter would go"
assert_out_has "bark" "and names what IS shipped (discoverability)"
echo 'notify.transport=../evil' > "$ws/config/topic.kv"
assert_rc 1 "a transport name carrying a path is refused (names resolve against the directory, not the filesystem)" -- \
  notify_fire "$ws" park owed_miss "x"
echo "notify.transport=bark" > "$ws/config/topic.kv"
printf 'notify.transport=bark\nnotify.cmd=printf "%%s|%%s\\\\n" > %s/cmd-wins.txt\n' "$base" > "$ws/config/topic.kv"
rm -f "$CURL_RECORD" "$base/cmd-wins.txt"
assert_rc 0 "notify.cmd overrides notify.transport when both are set (the explicit escape hatch)" -- \
  notify_fire "$ws" park owed_miss "y"
precond "cmd ran" test -s "$base/cmd-wins.txt"
[ ! -e "$CURL_RECORD" ] \
  && ok "the adapter was NOT invoked while notify.cmd stood" \
  || bad "adapter fired despite notify.cmd override"
# Adapter contract, direct: honest exit codes without notify_fire in the way.
rm -f "$opcfg/bark.url"
assert_rc 2 "bark.sh with no key anywhere exits 2 (unconfigured ≠ failed — nothing is lying green)" -- \
  env HOME="$base/nohome" XDG_CONFIG_HOME="$base/nohome-xdg" bash "$RS/transports/bark.sh" park.owed_miss "x"
export PATH="${PATH#"$tbin":}"

check_done
