#!/usr/bin/env bash
# 80-pty — backends/pty_tmux.sh against a REAL tmux pane (private server):
# classify_screen over every declared claude.kv signature, inject refusal on a
# non-empty composer + the full inject rc contract, dual-pid + starttime
# liveness, charset validation, fail-closed teardown. Skips (rc 77) without tmux.
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/fixtures/lib.sh"

command -v tmux > /dev/null || { echo "SKIP: tmux not installed on this machine"; exit 77; }

. "$RS/backends/pty_tmux.sh"
REAL_DECL="$WF_ROOT/config/backends/claude.kv"
# The frames this check classifies are painted once and never change, so the
# stability test's settle (claude.kv's live-measured 0.4 between its two captures)
# buys nothing here and cost 0.4s per classification and per injection —
# measured, 12s of a 24s check. The static arms therefore use claude.kv's own
# signatures with ONLY frame_settle changed (asserted: the two files differ in
# that one line); the arm whose pane really flows keeps the real declaration,
# because there the settle must outlast the output cadence to see a change.
DECL="$(sc_tmpdir)/claude-static.kv"
sed 's/^frame_settle=.*/frame_settle=0.05/' "$REAL_DECL" > "$DECL"
_decl_diff_is_settle_only() { # diff exits 1 on a difference, which pipefail would read as the grep failing
  local d; d=$(diff "$REAL_DECL" "$DECL" || true)
  [ "$(printf '%s\n' "$d" | command grep -c '^[<>]')" -eq 2 ] && printf '%s\n' "$d" | command grep -q '^> frame_settle=0.05$'
}
precond "the static-arm declaration is claude.kv with only frame_settle changed (every signature under test is the real one)" _decl_diff_is_settle_only

# Private tmux server. Unix socket paths cap near 108 bytes, so this must be a
# SHORT dir directly under /tmp, not the (possibly deep) $TMPDIR scratch.
TMUX_TMPDIR=$(mktemp -d /tmp/dwsc-tmux.XXXXXX) || exit 1
export TMUX_TMPDIR
unset TMUX 2>/dev/null || true
cleanup_tmux() { tmux kill-server 2>/dev/null; rm -rf "$TMUX_TMPDIR"; sc_cleanup; }
# The trap is installed in the same breath as the mktemp, and this ordering is
# load-bearing: bash DOES run the EXIT trap on a SIGPIPE death (verified with a
# six-line repro), but only one installed — and a consumer that closes the pipe
# early (`bash this-check | head -3`, a shape every maintainer types) kills the
# script in the section below. Measured: with the trap thirty lines further
# down, that left an empty /tmp/dwsc-tmux.* dir behind per early-closed run.
trap cleanup_tmux EXIT

echo "-- frame_settle: a declared rendering property, with a fallback that cannot fail --"
# The gap between the two frames of the stability test moved out of this
# adapter and into the DECLARATION, because it is a property of the CLI's
# rendering and not a constant every CLI is entitled to. Both directions
# matter: a declaration that states it must be obeyed, and one that does not
# must still classify — a settle time is a comfort, and a typo in it must never
# stop a session being classified at all.
fsd=$(sc_tmpdir)
printf 'family=pty_tmux\ncap=pty\n' > "$fsd/silent.kv"
printf 'family=pty_tmux\ncap=pty\nframe_settle=0.05\n' > "$fsd/fast.kv"
printf 'family=pty_tmux\ncap=pty\nframe_settle=oops\n' > "$fsd/bad.kv"
[ "$(_pty_settle "$fsd/silent.kv")" = "0.4" ] \
  && ok "a declaration that says nothing gets the live-measured 0.4 (every shipped backend's behaviour is unchanged)" \
  || bad "silent declaration -> '$(_pty_settle "$fsd/silent.kv")', want 0.4"
[ "$(_pty_settle "$fsd/fast.kv")" = "0.05" ] \
  && ok "a declaration that states one is obeyed (0.05)" \
  || bad "declared 0.05 -> '$(_pty_settle "$fsd/fast.kv")'"
[ "$(_pty_settle "$fsd/bad.kv")" = "0.4" ] \
  && ok "a non-numeric value falls back rather than passing garbage to sleep" \
  || bad "frame_settle=oops -> '$(_pty_settle "$fsd/bad.kv")'"
[ "$(_pty_settle "$fsd/no-such-file.kv")" = "0.4" ] \
  && ok "an unreadable declaration falls back too" \
  || bad "absent file -> '$(_pty_settle "$fsd/no-such-file.kv")'"

paint() { # file-with-screen-content -> session name
  # NB: runs in command substitution (subshell) — the name must not rely on
  # shared state; nanoseconds make it unique.
  local s="dwsc-$(date +%s%N)" i=0
  tmux new-session -d -s "$s" -x 200 -y 50 "cat '$1'; exec sleep 300" || return 1
  # The painter is done when the pane's command has become the `sleep` it
  # exec'd into — a fact tmux reports, so it is polled (≈5ms) rather than
  # guessed with a fixed 0.3s that cost 8s of this check.
  while [ "$(tmux display-message -p -t "=$s:" '#{pane_current_command}' 2>/dev/null)" != "sleep" ] && [ $i -lt 200 ]; do
    sleep 0.01; i=$((i + 1))
  done
  printf '%s\n' "$s"
}
pane_shows() { # session needle -> rc 0 once the pane shows it (polled, bounded)
  local i=0
  while [ $i -lt 100 ]; do
    tmux capture-pane -p -t "=$1:" 2>/dev/null | command grep -qF -- "$2" && return 0
    sleep 0.02; i=$((i + 1))
  done
  return 1
}
scr=$(sc_tmpdir)

echo "-- classify_screen: each declared claude.kv signature paints and classifies --"
printf 'agent output flowing...\n(esc to interrupt)\n' > "$scr/working.txt"
s=$(paint "$scr/working.txt")
cls=$(pty_classify_screen "$DECL" "$s")
[ "$cls" = "working" ] && ok "sig.working -> working" || bad "working screen classified '$cls'"

printf 'some output\nAPI connection error\nRetrying in 3s\n' > "$scr/err.txt"
s=$(paint "$scr/err.txt")
cls=$(pty_classify_screen "$DECL" "$s")
[ "$cls" = "error_retryable" ] && ok "sig.error_retryable -> error_retryable" \
  || bad "retryable-error screen classified '$cls'"

# Live pane shape from the measured incident: the exhaustion line lands in the
# TRANSCRIPT and the CLI then sits at an empty composer. That is why quota is a
# refinement of IDLE rather than a sibling of error_retryable — the status
# region below the composer never contains it, so a region-only test would
# never fire on a real pane.
printf 'some output\nClaude usage limit reached. Your limit will reset at 3pm\n\xe2\x9d\xaf\n' > "$scr/quota.txt"
s=$(paint "$scr/quota.txt")
cls=$(pty_classify_screen "$DECL" "$s")
[ "$cls" = "quota_exhausted" ] && ok "exhaustion line in the transcript + empty composer -> quota_exhausted (the live pane text, verbatim)" \
  || bad "quota-dead screen classified '$cls' — a respawn into it spends attempts on calls that cannot succeed"
# The discriminator: the same line while the CLI is WORKING is history, not
# state. A frame-wide test with no idle precondition would park a live session.
printf 'Claude usage limit reached. Your limit will reset at 3pm\n\xe2\x9d\xaf\n(esc to interrupt)\n' > "$scr/quota2.txt"
s=$(paint "$scr/quota2.txt")
cls=$(pty_classify_screen "$DECL" "$s")
[ "$cls" = "working" ] && ok "the same line under a WORKING composer stays working — quota refines idle, it does not override work" \
  || bad "a working session with a stale quota line classified '$cls'"

# 529 Overloaded: the SAME shape as quota one arm up, and the reason it needed
# its own class is that it does not look like one. The banner lands in the
# TRANSCRIPT and the CLI then sits at an empty composer, so before this class
# existed the frame below classified `awaiting_input` — measured 2026-09-03,
# 163 banner instances over one pane log, nudged and failed as `idle` twice.
printf 'some output\nAPI Error: 529 Overloaded. This is a server-side issue, usually temporary\n\xe2\x9d\xaf\n' > "$scr/overload.txt"
s=$(paint "$scr/overload.txt")
cls=$(pty_classify_screen "$DECL" "$s")
[ "$cls" = "backend_overloaded" ] && ok "529 banner in the transcript + empty composer -> backend_overloaded (the measured pane text, verbatim)" \
  || bad "an overloaded backend classified '$cls' — a nudge into a mid-529 client cannot help and the attempt fails as idle"
# The WRAPPED half of the measurement: 34 of the 163 instances were broken
# across lines, which is why the signature is the short discriminator and not
# the whole banner. A pattern anchored on "API Error:" would miss these.
printf 'some output\nAPI Error:\n529 Overloaded. This is a server-side\nissue, usually temporary\n\xe2\x9d\xaf\n' > "$scr/overload_wrapped.txt"
s=$(paint "$scr/overload_wrapped.txt")
cls=$(pty_classify_screen "$DECL" "$s")
[ "$cls" = "backend_overloaded" ] && ok "a line-WRAPPED 529 banner still classifies (34 of the 163 measured instances were wrapped)" \
  || bad "a wrapped 529 banner classified '$cls' — the signature is too long to survive the CLI's own wrapping"
# Same discriminator as quota's: under a WORKING composer the banner is
# history, not state. Without it this arm would park live sessions that had
# merely survived a 529 earlier in the turn.
printf 'API Error: 529 Overloaded. This is a server-side issue\n\xe2\x9d\xaf\n(esc to interrupt)\n' > "$scr/overload2.txt"
s=$(paint "$scr/overload2.txt")
cls=$(pty_classify_screen "$DECL" "$s")
[ "$cls" = "working" ] && ok "the same banner under a WORKING composer stays working — overload refines idle, it does not override work" \
  || bad "a working session with a stale 529 banner classified '$cls'"
# PRECEDENCE, and it is a decision rather than an accident of order: both
# statements mean "the backend is refusing", and only QUOTA names a reset time.
# A frame carrying both must classify quota, or the operator loses the one fact
# they can act on.
printf 'API Error: 529 Overloaded. This is a server-side issue\nClaude usage limit reached. Your limit will reset at 3pm\n\xe2\x9d\xaf\n' > "$scr/both.txt"
s=$(paint "$scr/both.txt")
cls=$(pty_classify_screen "$DECL" "$s")
[ "$cls" = "quota_exhausted" ] && ok "a frame carrying BOTH statements classifies quota_exhausted (only quota names a reset time)" \
  || bad "both-statements frame classified '$cls' — the operator loses the reset time"

printf 'transcript above\n\n\xc2\xa0\xe2\x9d\xaf\n' > "$scr/await.txt"   # NBSP + ❯
s=$(paint "$scr/await.txt")
cls=$(pty_classify_screen "$DECL" "$s")
[ "$cls" = "awaiting_input" ] && ok "NBSP-prefixed empty composer -> awaiting_input" \
  || bad "NBSP composer classified '$cls'"
printf 'transcript\n\xe2\x9d\xaf \n' > "$scr/await2.txt"                  # plain ❯ + trailing space
s=$(paint "$scr/await2.txt")
cls=$(pty_classify_screen "$DECL" "$s")
[ "$cls" = "awaiting_input" ] && ok "plain empty composer (trailing space) -> awaiting_input" \
  || bad "plain composer classified '$cls'"
printf 'transcript\n\xe2\x9d\xaf\xc2\xa0\n' > "$scr/await3.txt"           # ❯ + NBSP SUFFIX (live-measured)
s=$(paint "$scr/await3.txt")
cls=$(pty_classify_screen "$DECL" "$s")
[ "$cls" = "awaiting_input" ] \
  && ok "NBSP-SUFFIXED empty composer -> awaiting_input (the live CLI paints the NBSP after the prompt char; C-locale trailing-space stripping cannot remove it)" \
  || bad "NBSP-suffixed composer classified '$cls' — the declared regex tolerates NBSP only as a prefix; a live probe fails awaiting_input/inject/dead_detect on this"

echo "-- REAL captured frames: history is history, the footer is not the composer --"
FR="$SC_ROOT/fixtures/frames"
s=$(paint "$FR/idle-history.txt")
cls=$(pty_classify_screen "$DECL" "$s")
[ "$cls" = "awaiting_input" ] \
  && ok "real idle frame (lingering ✻ in history + status footer below the composer) -> awaiting_input" \
  || bad "real idle frame classified '$cls' — a finished CLI is unreachable for nudge/advance (whole-frame working match or footer-as-last-line)"
assert_rc 0 "inject on the real idle frame reaches the composer (footer below it must not hide it)" -- \
  pty_inject "$DECL" "$s" "nudge-real-frame"
s=$(paint "$FR/leftover-composer.txt")
# This frame is consumed only by NEGATIVE arms (the unknown classification,
# the rc-3 refusal, and the busyfooter transform's insert at line 43), so an
# emptied or line-shifted file would classify `unknown` all the same and the
# block would read green over a fixture that stopped being its subject. The
# precond pins the subject line itself, byte-exact — truncation, deletion and
# line-count drift above 43 all break it.
precond "the leftover-composer frame still carries its composer line at 43 (prompt + NBSP + leftover text — the transform's insert point and these arms' subject)" \
  bash -c '[ "$(sed -n "43p" "$1")" = "$(printf "\xe2\x9d\xaf\xc2\xa0continue")" ]' _ "$FR/leftover-composer.txt"
cls=$(pty_classify_screen "$DECL" "$s")
[ "$cls" != "awaiting_input" ] && [ "$cls" != "working" ] \
  && ok "real frame with leftover composer text -> '$cls' (never awaiting, never working: unsafe to inject, loud to park)" \
  || bad "leftover-text composer classified '$cls' — injection would fuse with unsubmitted text"
out=$(pty_inject "$DECL" "$s" "nudge" 2>&1); rc=$?
# This fixture ends in a newline, so the cursor sits BELOW the composer and the
# pre-cursor rule answers — the degradation path, pinned here deliberately. It
# refuses either way; rc 3 rather than 2 because no client is attached.
[ $rc -eq 3 ] \
  && ok "inject on the leftover-text composer refuses (rc 3: refusal without a human to blame)" \
  || bad "inject on leftover composer rc=$rc, want 3"
awk 'NR==43{printf "\xe2\x9d\xaf\xc2\xa0\n"; next} {print} END{print "  esc to interrupt · working footer"}' \
  "$FR/leftover-composer.txt" > "$scr/busyfooter.txt"

echo "-- a frames_disagree refusal leaves its two captures on disk --"
# The learning loop pre-registered this dump "before anyone tunes a settle
# window": the refusal token says the pane was flowing but
# never shows HOW, and the two live cases could not be told apart after the
# fact. The pane below repaints every 20 ms against the static decl's 0.05
# settle, so the double-capture is guaranteed to disagree — the dump's f1/f2
# must land under the dir the caller names, capped and best-effort, and the
# TOKEN on stdout must stay exactly the token the record reads.
fl="dwsc-flow-$(date +%s%N)"
tmux new-session -d -s "$fl" -x 200 -y 50 \
  'while :; do printf "tick %s\n" "$(date +%s%N)"; sleep 0.02; done' || { bad "no flowing pane"; }
dumpd=$(sc_tmpdir)
out=$(pty_inject "$DECL" "$fl" "nudge" "$dumpd" 2>/dev/null); rc=$?
[ $rc -eq 3 ] && [ "$out" = "frames_disagree" ] \
  && ok "the flowing pane refuses rc 3 with the frames_disagree token (stdout unchanged by the dump)" \
  || bad "flowing pane: rc=$rc out='$out'"
[ -s "$dumpd/inject-frames.f1.txt" ] && [ -s "$dumpd/inject-frames.f2.txt" ] \
  && ok "both captures land under the caller's dir, non-empty" \
  || bad "dump files missing or empty under $dumpd"
[ "$(cat "$dumpd/inject-frames.f1.txt")" != "$(cat "$dumpd/inject-frames.f2.txt")" ] \
  && ok "and they DISAGREE — the dump is the evidence the token only names" \
  || bad "the two dumped captures are identical (the pane did not flow, or the dump captured one frame twice)"
command grep -q 'tick' "$dumpd/inject-frames.f2.txt" \
  && ok "the capture is the pane's own content (readable, not an error string)" \
  || bad "f2 does not carry the pane's text: $(head -2 "$dumpd/inject-frames.f2.txt")"
# the no-dir call stays exactly what it was: rc 3, token, and NOTHING written —
# probe's callers pass no dir and must not grow files.
cleand=$(sc_tmpdir)
out=$(pty_inject "$DECL" "$fl" "nudge" 2>/dev/null); rc=$?
[ $rc -eq 3 ] && [ "$out" = "frames_disagree" ] && [ -z "$(ls -A "$cleand")" ] \
  && ok "a caller passing no dumpdir gets the same refusal and no files (the 3-arg call is unchanged)" \
  || bad "no-dir call changed: rc=$rc out='$out' dir='$(ls -A "$cleand")'"
s=$(paint "$scr/busyfooter.txt")
cls=$(pty_classify_screen "$DECL" "$s")
[ "$cls" = "working" ] \
  && ok "live working indicator BELOW the composer -> working (in-region working outranks the empty composer)" \
  || bad "busy footer classified '$cls' — an active CLI would be nudged mid-work"

printf 'Do you trust the files in this folder?\n' > "$scr/modal.txt"
s=$(paint "$scr/modal.txt")
cls=$(pty_classify_screen "$DECL" "$s")
[ "$cls" = "modal.trust" ] && ok "declared modal -> modal.trust (exact allowlist)" \
  || bad "trust modal classified '$cls'"

# The NEWER CLI's trust dialog (live-captured shape): different wording, and
# a preselected choice line that even matches the composer regex — pre-fix
# it rode past the modal allowlist and parked a live topic unknown_screen.
{ printf ' Accessing workspace:\n\n /some/project/checkout\n\n'
  printf ' Quick safety check: Is this a project you created or one you trust?\n\n'
  printf ' \xe2\x9d\xaf 1. Yes, I trust this folder\n   2. No, exit\n\n'
  printf ' Enter to confirm - Esc to cancel\n'; } > "$scr/modal2.txt"
s=$(paint "$scr/modal2.txt")
cls=$(pty_classify_screen "$DECL" "$s")
[ "$cls" = "modal.trust" ] \
  && ok "the newer trust-dialog wording -> modal.trust (one signature, both generations)" \
  || bad "new trust dialog classified '$cls' — it parks unknown_screen on a live topic (wording rot)"
# Null control: the broadened signature must not swallow ordinary screens —
# the real idle frame (composer + footer) must still classify awaiting_input.
s=$(paint "$FR/idle-history.txt")
cls=$(pty_classify_screen "$DECL" "$s")
[ "$cls" = "awaiting_input" ] \
  && ok "the broadened trust signature leaves the real idle frame untouched (null control)" \
  || bad "idle frame now classifies '$cls' — the modal regex overmatches"

printf 'CLI exited\nuser@host:~/dir$ \n' > "$scr/shell.txt"
s=$(paint "$scr/shell.txt")
cls=$(pty_classify_screen "$DECL" "$s")
[ "$cls" = "unknown" ] \
  && ok "bare shell prompt -> unknown (no composer, no declared state: parks unknown_screen LOUDLY; dead CLIs are pid-detected — the launch command is the pane command, so a dead CLI has no pane)" \
  || bad "shell-prompt screen classified '$cls' — an undeclared state must return unknown, never a guess"

printf 'SOME COMPLETELY UNDECLARED SCREEN STATE\n' > "$scr/unknown.txt"
s=$(paint "$scr/unknown.txt")
cls=$(pty_classify_screen "$DECL" "$s")
[ "$cls" = "unknown" ] && ok "undeclared state -> unknown (returned, never guessed; ferry parks it)" \
  || bad "undeclared screen classified '$cls' — misclassification is the silent-rot hazard"

s="dwsc-flow-$(date +%s%N)"
tmux new-session -d -s "$s" -x 200 -y 50 \
  'i=0; while :; do echo "output line $i"; i=$((i+1)); sleep 0.1; done' || true
sleep 0.3
cls=$(pty_classify_screen "$REAL_DECL" "$s")   # the REAL settle: it must outlast the 0.1s output cadence to see the frames differ
[ "$cls" = "working" ] && ok "disagreeing double-capture frames -> working (output still flowing)" \
  || bad "flowing output classified '$cls'"
tmux kill-session -t "=$s" 2>/dev/null

echo "-- the composer's EMPTINESS is the cursor's question, not the text's --"
# A TUI paints its placeholder/hint AFTER the cursor and a human's typing
# BEFORE it. A plain capture renders the two identically (SGR is dropped), so
# the text alone cannot answer "is the box empty" — measured on Claude Code
# 2.1.228, which paints a dim hint into an EMPTY composer and thereby made
# every classification `unknown` and every injection a refusal.
# Fixtures place the cursor EXPLICITLY (\033[<col>G): a fixture that ends with
# a newline leaves the cursor on the line BELOW the composer, which silently
# exercises the pre-cursor fallback instead — measured, and it is how this
# whole path would pass while testing nothing.
printf 'transcript\n\xe2\x9d\xaf\xc2\xa0\033[2m/exit\033[0m\033[3G' > "$scr/hint.txt"
s=$(paint "$scr/hint.txt")
cls=$(pty_classify_screen "$DECL" "$s")
[ "$cls" = "awaiting_input" ] \
  && ok "hint text with the cursor at the input origin -> awaiting_input (the box is empty; the text is chrome)" \
  || bad "hinted empty composer classified '$cls' — an idle CLI is unreachable: the ferry parks unknown_screen on the first quiet poll"
assert_rc 0 "inject into a hinted-but-empty composer succeeds" -- pty_inject "$DECL" "$s" "hint-inject-token"
pane_shows "$s" "hint-inject-token" \
  && ok "the nudge actually reached the pane" || bad "nudge not visible in pane"

printf 'transcript\n\xe2\x9d\xaf\xc2\xa0half-typed operator text' > "$scr/typed.txt"
s=$(paint "$scr/typed.txt")
cls=$(pty_classify_screen "$DECL" "$s")
[ "$cls" != "awaiting_input" ] \
  && ok "text BEFORE the cursor -> not awaiting ('$cls'): the one thing that must never be injected into" \
  || bad "typed text classified awaiting_input — injection would fuse with unsubmitted input"

echo "-- inject: the single primitive's rc contract --"
# The safety invariant is unchanged and absolute: injection happens ONLY into
# an empty composer. What changed is the NAME of the refusal — rc 2 asserts a
# HUMAN, so it is claimed only when tmux reports a writable client attached;
# with nobody there the same screen is a rendering artifact (rc 3), which the
# nudge caller retries past and the warm caller cold-falls-back from, instead
# of parking the topic on an operator who is not present.
s=$(paint "$scr/typed.txt")
out=$(pty_inject "$DECL" "$s" "nudge" 2>&1); rc=$?
[ $rc -eq 3 ] \
  && ok "occupied composer with NO client attached -> rc 3 (artifact, not an accusation)" \
  || bad "inject on an unattended occupied composer rc=$rc, want 3"
command grep -q "operator_interference" <<< "$out" \
  && bad "an absent operator was still named — the guard asserts what it cannot see" \
  || ok "the refusal does not name an operator who is not attached"
if command -v script > /dev/null; then
  s=$(paint "$scr/typed.txt")
  ( script -qc "tmux attach -t $s" /dev/null > /dev/null 2>&1 & ) ; sleep 1
  tmux list-clients -t "=$s:" -F '#{client_readonly}' 2>/dev/null | command grep -qx 0 \
    && ok "precondition: a WRITABLE client is attached to the fixture session" \
    || bad "FIXTURE PRECONDITION BROKEN: no writable client attached — the rc-2 case below is vacuous"
  out=$(pty_inject "$DECL" "$s" "nudge" 2>&1); rc=$?
  [ $rc -eq 2 ] \
    && ok "occupied composer WITH a writable client -> rc 2 refuse (operator_interference)" \
    || bad "inject with a human attached rc=$rc, want 2"
  printf '%s' "$out" | command grep -q "operator_interference" \
    && ok "refusal names operator_interference" || bad "refusal not self-describing: $out"
  printf '%s' "$out" | command grep -q "half-typed operator text" \
    && ok "the screen (with the human's text) is attached to the refusal" \
    || bad "screen not attached to refusal"
  # rc 2 puts the sentence AND the whole frame on stderr. Every caller now
  # captures stdout alone, and this is the contract that makes that safe: if
  # rc 2 ever printed to stdout, a 40-character slice of a pane frame would
  # start landing in store rows as an injection reason.
  sout=$(pty_inject "$DECL" "$s" "nudge" 2>/dev/null)
  [ -z "$sout" ] \
    && ok "and rc 2 writes NOTHING to stdout — what lets callers capture stdout alone and never record a pane frame" \
    || bad "rc 2 printed '$sout' on stdout: a stdout-only capture would record it"
  tmux kill-session -t "=$s" 2>/dev/null
else
  note "SKIP the attached-client case: no script(1) to make a pty"
fi

echo "-- a declaration WITHOUT sig.composer_line still injects (the drill's minimal backend) --"
# The cursor rule needs a declared composer anchor. A backend that declares
# none (the drill's test.kv) must keep the last-non-empty-line behaviour, or
# every injection silently stops happening — measured: this exact regression
# turned 7 drill assertions red while 80-pty stayed green.
MIN="$scr/minimal.kv"
printf 'family=pty_tmux\nsig.working=MOCK_WORKING\nsig.awaiting_input=^\xe2\x9d\xaf$\n' > "$MIN"
printf 'ready\n\xe2\x9d\xaf\n' > "$scr/minclean.txt"
s=$(paint "$scr/minclean.txt")
assert_rc 0 "no composer_line declared + empty composer -> inject succeeds" -- \
  pty_inject "$MIN" "$s" "minimal-inject-token"
s=$(paint "$scr/working.txt")
out=$(pty_inject "$MIN" "$s" "nudge" 2>&1); rc=$?
# The class this frame carries under the MINIMAL signatures is `unknown` —
# its text matches the real claude.kv signatures, not MOCK_WORKING — so that is
# what the refusal prints, and that is what gets asserted. The old text said
# "working screen" and asserted only rc; the class was never checked.
[ $rc -eq 3 ] && printf '%s' "$out" | command grep -q "unknown" \
  && ok "no composer_line + a screen matching no declared signature -> rc 3 with the class printed (unknown)" \
  || bad "minimal-declaration inject rc=$rc (want 3) or class not printed: $out"

printf 'ready\n\xe2\x9d\xaf\n' > "$scr/clean.txt"
s=$(paint "$scr/clean.txt")
assert_rc 0 "empty composer -> inject succeeds" -- pty_inject "$DECL" "$s" "hello-inject-token"
pane_shows "$s" "hello-inject-token" \
  && ok "injected text actually arrived in the pane" || bad "injected text not visible in pane"

s=$(paint "$scr/working.txt")
out=$(pty_inject "$DECL" "$s" "nudge" 2>&1); rc=$?
[ $rc -eq 3 ] && ok "not-awaiting screen -> rc 3 (caller cold-falls-back / skips)" \
  || bad "inject on working screen rc=$rc, want 3"
printf '%s' "$out" | command grep -q "working" \
  && ok "the classified state is printed for the caller" || bad "state not printed: $out"
assert_rc 1 "vanished session -> rc 1 (capture failure)" -- \
  pty_inject "$DECL" "no-such-session" "x"

echo "-- the rc-3 discriminator: three causes share one rc and must be TOLD APART --"
# pty_inject returns 3 for frames-disagree, composer_occupied, and "no composer
# at all". Every production caller discarded the stdout line naming which, so a
# live inject_rc=3 was unreadable after the fact; the callers now record it. The
# property that makes recording worth anything is DISTINCTNESS — asserting each
# token on its own would still pass if two of them collapsed, which is exactly
# what was wrong: the frames-disagree branch printed `working`, the same word
# the no-composer branch forwards for a working screen.
s=$(paint "$FR/leftover-composer.txt")
why_occ=$(pty_inject_why "$(pty_inject "$DECL" "$s" "nudge" 2>/dev/null)")
s=$(paint "$scr/working.txt")
why_cls=$(pty_inject_why "$(pty_inject "$DECL" "$s" "nudge" 2>/dev/null)")
why_min=$(pty_inject_why "$(pty_inject "$MIN" "$s" "nudge" 2>/dev/null)")
[ "$why_occ" = composer_occupied ] \
  && ok "rc 3 on an occupied composer names itself ($why_occ)" \
  || bad "occupied-composer refusal named '$why_occ', want composer_occupied"
[ "$why_cls" = working ] \
  && ok "rc 3 with no composer forwards the CLASS ($why_cls under the full declaration)" \
  || bad "no-composer refusal named '$why_cls', want working"
[ "$why_min" = unknown ] \
  && ok "and the same branch under a MINIMAL declaration forwards a different class ($why_min) — it forwards, never a constant" \
  || bad "no-composer refusal under the minimal declaration named '$why_min', want unknown"
[ "$why_occ" != "$why_cls" ] \
  && ok "the two fixture-reachable causes are DISTINCT — one rc, two readings" \
  || bad "two rc-3 causes collapsed to the same token: [$why_occ] [$why_cls]"
# Named rather than silently skipped: the third cause cannot be reached from a
# painted pane, because two captures of a static pane never disagree. What IS
# pinned about it is that its token no longer collides with the class the
# no-composer branch forwards for a working screen.
command grep -q 'echo frames_disagree; return 3' "$RS/backends/pty_tmux.sh" \
  && ok "the frames-disagree cause carries its own token, not the '$why_cls' the class branch forwards (unreachable from a static pane; asserted structurally, and said so)" \
  || bad "the frames-disagree branch does not carry a distinct token"
[ "$(pty_inject_why "")" = "-" ] \
  && ok "an absent reason reads '-' — a reading, never an empty field in a store row" \
  || bad "empty stdout produced an empty token"
[ "$(pty_inject_why "two words  here")" = "two_words__here" ] \
  && ok "whitespace collapses so the token can ride a whitespace-delimited row" \
  || bad "the token is not space-free: [$(pty_inject_why "two words  here")]"

echo "-- alive: dual-pid + procfs starttime (pid-reuse defense) --"
s=$(paint "$scr/clean.txt")
pp=$(tmux display-message -p -t "=$s:" '#{pane_pid}')
sp=$(tmux display-message -p -t "=$s:" '#{pid}')
pps=$(_pty_starttime "$pp"); sps=$(_pty_starttime "$sp")
precond "collected pane/server pids + starttimes" test -n "$pp" -a -n "$pps" -a -n "$sps"
[ "$(pty_alive "$pp" "$pps" "$sp" "$sps")" = "running" ] \
  && ok "live session -> running" || bad "live session read as dead"
[ "$(pty_alive "$pp" "999999" "$sp" "$sps")" = "dead" ] \
  && ok "starttime mismatch -> dead (a reused pid is not our process)" \
  || bad "pid-reuse defense inert"
tmux kill-session -t "=$s"
sleep 0.2
[ "$(pty_alive "$pp" "$pps" "$sp" "$sps" || true)" = "dead" ] \
  && ok "killed session -> dead" || bad "killed session still reads running"

echo "-- charset + spawn validation --"
assert_rc 0 "session name in [A-Za-z0-9_-] accepted" -- pty_session_name_ok "delivery-t-01-spec"
assert_rc 2 "':' in a session name refused (tmux target redirection)" -- \
  pty_session_name_ok "bad:name"
assert_rc 2 "glob char in a session name refused" -- pty_session_name_ok "bad*glob"
assert_rc 2 "empty session name refused" -- pty_session_name_ok ""
assert_rc 2 "spawn_cold refuses an absent prompt file" -- \
  pty_spawn_cold "$DECL" goodname m e "$scr" p "$scr/nonexistent-prompt.md" "$scr/log"

echo "-- window-size manual: the spawn's declared geometry is pinned, never renegotiated --"
# 220x50 is part of the declared contract the screen signatures read. With the
# global default (smallest) ANY attach client — a read-only one included —
# rewrites the pane's size permanently (no rebound), and wrapped lines at
# another width are a different screen to the classifier. The pin must be
# asserted on the REAL spawn path: a hand-built fixture session never touches
# the new line, so this arm spawns through pty_spawn_cold on a benign
# declaration (no CLI behind it, no cost), and an unpinned CONTROL session
# proves the attach perturbation is real rather than assumed.
wdecl="$scr/benign.kv"
printf 'family=pty_tmux\ncap=pty\ncmd.launch=exec sleep 300\n' > "$wdecl"
printf 'benign prompt\n' > "$scr/prompt.md"
wname="dwsc-wsm-$$"
assert_rc 0 "spawn_cold spawns a session on a benign declaration (rc=0)" -- \
  pty_spawn_cold "$wdecl" "$wname" m e "$scr" p "$scr/prompt.md" "$scr/wsm.log"
[ "$(tmux show-options -w -t "=$wname:" window-size 2>/dev/null)" = "window-size manual" ] \
  && ok "the spawn pins window-size manual on its window (show-options -w reads it back)" \
  || bad "window-size is not manual after spawn: '$(tmux show-options -w -t "=$wname:" window-size 2>/dev/null || echo unset)'"
if command -v script > /dev/null; then
  _wsm_wait_client() { # session -> 0 once a client is attached (bounded poll)
    local i
    for i in 1 2 3 4 5 6 7 8 9 10; do
      [ -n "$(tmux list-clients -t "=$1:" 2>/dev/null)" ] && return 0
      sleep 0.2
    done
    return 1
  }
  ( script -qc "stty rows 24 cols 80; exec tmux attach -r -t \"=$wname\"" /dev/null > /dev/null 2>&1 & )
  _wsm_wait_client "$wname" || bad "FIXTURE PRECONDITION BROKEN: no client ever attached to the pinned session"
  sleep 0.5
  cgeom=$(tmux display-message -p -t "=$wname:" '#{window_width}x#{window_height}')
  [ "$cgeom" = "220x50" ] \
    && ok "a smaller read-only client attached and the geometry HELD 220x50 (the pin refuses renegotiation)" \
    || bad "geometry moved under an attached client: $cgeom"
  rname="dwsc-wsmctl-$$"
  tmux new-session -d -s "$rname" -x 220 -y 50 "exec sleep 300"
  ( script -qc "stty rows 24 cols 80; exec tmux attach -r -t \"=$rname\"" /dev/null > /dev/null 2>&1 & )
  _wsm_wait_client "$rname" || bad "FIXTURE PRECONDITION BROKEN: no client ever attached to the control session"
  sleep 0.5
  rgeom=$(tmux display-message -p -t "=$rname:" '#{window_width}x#{window_height}')
  [ "$rgeom" != "220x50" ] \
    && ok "the CONTROL (hand-built, unpinned) session shrank to $rgeom under the same client — the arm is not vacuous" \
    || bad "the unpinned control did not shrink: the attach perturbation this arm depends on did not happen"
  tmux kill-session -t "=$rname" 2>/dev/null
  tmux kill-session -t "=$wname" 2>/dev/null
else
  note "SKIP the attached-client arms: no script(1) to make a pty (the pin itself is asserted above)"
  tmux kill-session -t "=$wname" 2>/dev/null
fi

echo "-- peek: the operator's read-only look, over a real pane --"
# launch.sh peek's full path runs once here against a real session: the
# sessions face (fabricated with THIS private server's socket) -> name/socket
# -> capture-pane (the adapter's own =name: window form) -> stdout. The verb
# must print the pane's content, and the capture must leave the session with
# zero clients — the structural property that makes looking free of the harm
# attach carries.
printf 'PEEKMARKER the pane says this\n' > "$scr/pk-frame.txt"
pks=$(paint "$scr/pk-frame.txt")
pksock=$(tmux display-message -p -t "=$pks:" '#{socket_path}')
pkws=$(sc_tmpdir)/peekws
mkdir -p "$pkws/.runtime/state"
( . "$RS/lib/state.sh"
  printf 'role=author name=%s pane_pid=1 pane_start=1 server_pid=1 server_start=1 socket=%s nonce=n1 mode=cold backend=claude t=1\n' \
    "$pks" "$pksock" | state_set "$pkws" sessions ferry ) > /dev/null
pkout=$(bash "$RS/launch.sh" peek "$pkws" 2>&1); pkrc=$?
[ $pkrc -eq 0 ] && printf '%s\n' "$pkout" | command grep -q 'PEEKMARKER the pane says this' \
  && ok "peek prints the live pane's content (face -> socket -> capture -> stdout)" \
  || bad "rc=$pkrc, the pane text did not come through: $(printf '%s\n' "$pkout" | head -3 | tr '\n' ' ')"
[ -z "$(tmux list-clients -t "=$pks:" 2>/dev/null)" ] \
  && ok "and the capture left ZERO clients on the session (looking cannot perturb)" \
  || bad "peek left a client attached: $(tmux list-clients -t "=$pks:" 2>/dev/null)"
# --attach over a LIVE session prints the runnable command (exact-match target)
# — the arm 36-verbs cannot hold, because its fixtures have no live tmux; here
# the has-session check --attach now runs resolves TRUE, so the command prints.
pkout=$(bash "$RS/launch.sh" peek "$pkws" --attach 2>&1); pkrc=$?
[ $pkrc -eq 0 ] && printf '%s\n' "$pkout" | command grep -qF "tmux -S $pksock attach -r -t '=$pks'   (author)" \
  && ok "--attach over a LIVE session prints the read-only attach command, exactly (socket, exact-match target, role)" \
  || bad "--attach over a live session: $(printf '%s\n' "$pkout" | head -3 | tr '\n' ' ')"
tmux kill-session -t "=$pks" 2>/dev/null

echo "-- teardown: fail-closed --"
out=$(pty_teardown "somename" "$scr/no-such-socket" 2>&1); rc=$?
[ $rc -eq 3 ] && ok "gone socket -> rc 3 refuse (never starts a replacement server)" \
  || bad "teardown on gone socket rc=$rc, want 3"
printf '%s' "$out" | command grep -q "fail-closed" \
  && ok "refusal names the fail-closed rule" || bad "teardown refusal not self-describing"
s=$(paint "$scr/clean.txt")
sock=$(tmux display-message -p -t "=$s:" '#{socket_path}')
assert_rc 0 "teardown with the live socket kills the session" -- pty_teardown "$s" "$sock"
tmux has-session -t "=$s" 2>/dev/null \
  && bad "session survived teardown" || ok "session gone after teardown"
assert_rc 0 "teardown of an already-gone session is idempotent" -- pty_teardown "$s" "$sock"

echo "-- reconcile --"
s=$(paint "$scr/clean.txt")
pty_reconcile "dwsc-" | command grep -qxF "$s" \
  && ok "reconcile lists live prefixed sessions" || bad "reconcile lists nothing"
command grep -q . <<< "$(pty_reconcile "no-such-prefix-")" \
  && bad "reconcile matched a foreign prefix" || ok "foreign prefix matches nothing"

check_done
