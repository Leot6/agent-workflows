#!/usr/bin/env bash
# transports/bark.sh — Bark (iOS push) adapter, the notify seam's first
# shipped transport. Contract (lib/notify.sh): invoked as
#     bark.sh <event> <message>
# with the event a closed-vocabulary token and the message payload; the
# adapter owns the platform and its secret, the workflow never sees either.
#
# Key resolution (one home, the operator's):
#   ${XDG_CONFIG_HOME:-~/.config}/delivery-workflow/bark.url
# The file holds the push base URL (e.g. https://api.day.app/<key>), chmod 600
# by the operator — a webhook key is a secret and lives in the operator's
# config area, never in a committed file. (An SMW-era fallback path lived here
# once, for one already-armed machine; it was this machine's coordinate in
# shipped code and read as noise to everyone else, and the arming moved.)
#
# Exit codes (HONEST, and load-bearing — notify_fire records rc 1 as
# "undelivered" and leaves the notified flag unset, so a relaunch re-sends;
# lying green here would defeat at-least-once):
#   0  Bark accepted the push (HTTP 200): it left the machine.
#   1  transport failure (curl failed, timeout, non-200 — e.g. a dead key).
#   2  no key file: nothing is configured to push to.
set -u
event="${1:-event}"
message="${2:-(no message)}"
base=""
f="${XDG_CONFIG_HOME:-$HOME/.config}/delivery-workflow/bark.url"
if [ -s "$f" ]; then base=$(head -1 "$f"); fi
[ -n "$base" ] || exit 2
base="${base%/}"
http="$(curl -s -m 8 -o /dev/null -w '%{http_code}' \
  "$base" \
  --data-urlencode "title=delivery-workflow · ${event}" \
  --data-urlencode "body=${message}" \
  --data-urlencode "group=delivery-workflow" \
  --data-urlencode "level=timeSensitive")" || exit 1
[ "$http" = "200" ] || exit 1
exit 0
