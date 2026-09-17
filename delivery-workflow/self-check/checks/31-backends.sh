#!/usr/bin/env bash
# 31-backends — the BACKEND/ADAPTER declaration family, split verbatim out of
# 30-closure.sh: every declaration under config/backends/ is complete against
# backend-seam.md §3, the workflow's own harness contract is identical across
# every profile that declares a hook event, a declaration's placeholders are a
# subset of the adapter's substitution set, and §3's worked example is byte-for-
# byte the shipped claude.kv.
#
# WHY IT IS A FILE OF ITS OWN, so the split does not read as arbitrary later:
# 30-closure reached 998 against cap.selftest_file=1000 and two rounds running
# had to place new arms away from their natural home because of it (work order
# 3's ack sweep went to 85-watchdog with a line saying so). The precedent is
# 50-record.sh at 1013, whose closed-vocabulary sweeps moved verbatim into
# 52-vocab.sh "which they belonged in anyway" — and its reasoning applies here
# unchanged: a cap saying a file is full is not answered by removing what the
# file explains. So this is a MOVE, byte-for-byte, not a rewrite: every line
# below is the line that was in 30-closure, and the pair's combined content is
# unchanged. The family is coherent on its own terms — it reads config/backends/
# and design/backend-seam.md and nothing else, and it needed none of
# 30-closure's shared setup (no rows/col/STAGES/TSV/TPLDIR, no config.sh,
# owed.sh or compose.sh), which is what made the family separable at all.
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/fixtures/lib.sh"

echo "-- backend declarations complete (backend-seam.md §3) --"
validate_decl() { # file -> violations
  local f=$1 k caps sig m ln
  # frame_settle is OPTIONAL (pty_tmux.sh defaults to the measured 0.4), but a
  # declaration that states it must state a number — a typo there would silently
  # restore the default and nobody would know which value was in force.
  local fs; fs=$(pty_decl_get "$f" frame_settle 2>/dev/null || true)
  [ -z "$fs" ] || case "$fs" in ''|*[!0-9.]*) echo "$(basename "$f"): frame_settle='$fs' is not a number" ;; esac
  # probe.latency likewise OPTIONAL (probe.sh defaults to 30), and a stated
  # value must be a whole number of seconds, or the default is silently in force.
  local pl; pl=$(pty_decl_get "$f" probe.latency 2>/dev/null || true)
  [ -z "$pl" ] || case "$pl" in ''|*[!0-9]*) echo "$(basename "$f"): probe.latency='$pl' is not a whole number of seconds" ;; esac
  for k in family cmd.launch cmd.version prompt_style profile nudge_text; do
    pty_decl_get "$f" "$k" > /dev/null 2>&1 || echo "$(basename "$f"): missing $k="
  done
  [ "$(pty_decl_get "$f" family 2>/dev/null)" = "pty_tmux" ] \
    || echo "$(basename "$f"): family is not pty_tmux (the only structural family)"
  # {model} is double-quoted in cmd.launch — the launch string is parsed by
  # the pane's shell (tmux default-shell), where a bracketed tier suffix
  # (model[1M]) is a glob class: unquoted, zsh kills the pane on "no
  # matches found" and bash rewrites the slug on a filename match (both
  # measured 2026-08, tmux 3.0a). Blanket and value-independent — quoting a
  # glob-free slug changes nothing.
  ln=$(pty_decl_get "$f" cmd.launch 2>/dev/null || true)
  case "$(printf '%s' "$ln" | sed 's/"{model}"//g')" in
    *'{model}'*) echo "$(basename "$f"): unquoted {model} in cmd.launch — a tier suffix would be globbed by the pane's shell" ;;
  esac
  caps=$(pty_decl_get "$f" cap 2>/dev/null || true)
  for k in pty stop_gate heartbeat; do
    printf ',%s,' "$caps" | command grep -qF ",$k," \
      || echo "$(basename "$f"): cap list lacks '$k'"
  done
  for k in working awaiting_input error_retryable; do
    pty_decl_get "$f" "sig.$k" > /dev/null 2>&1 \
      || echo "$(basename "$f"): missing sig.$k="
  done
  for m in $(awk -F= '$1 ~ /^sig\.modal\./{sub(/^sig\.modal\./,"",$1); print $1}' "$f"); do
    pty_decl_get "$f" "act.modal.$m" > /dev/null 2>&1 \
      || echo "$(basename "$f"): sig.modal.$m has no act.modal.$m (allowlist incomplete)"
  done
  for m in $(awk -F= '$1 ~ /^act\.modal\./{sub(/^act\.modal\./,"",$1); print $1}' "$f"); do
    pty_decl_get "$f" "sig.modal.$m" > /dev/null 2>&1 \
      || echo "$(basename "$f"): act.modal.$m has no sig.modal.$m"
  done
}
. "$RS/backends/pty_tmux.sh"
nb=0
for f in "$WF_ROOT"/config/backends/*.kv; do
  nb=$((nb + 1))
  viol=$(validate_decl "$f")
  [ -z "$viol" ] && ok "backend declaration complete: $(basename "$f")" || bad "$viol"
done
precond "N>0 backend declarations checked (saw $nb)" test "$nb" -ge 2
baddecl=$(sc_tmpdir)/broken.kv
printf 'family=pty_tmux\ncmd.launch=x\n' > "$baddecl"
viol=$(validate_decl "$baddecl")
command grep -q "nudge_text" <<< "$viol" \
  && ok "validator flags an incomplete declaration (known-bad fires)" \
  || bad "backend validator vacuous — missing nudge_text not flagged"
badq=$(sc_tmpdir)/unquoted-model.kv
printf 'cmd.launch=x --model {model}\n' > "$badq"
viol=$(validate_decl "$badq")
command grep -q "unquoted {model}" <<< "$viol" \
  && ok "validator flags an unquoted {model} in cmd.launch (known-bad fires)" \
  || bad "quoting invariant vacuous — unquoted {model} not flagged"
badlat=$(sc_tmpdir)/latency.kv
printf 'probe.latency=fast\n' > "$badlat"
viol=$(validate_decl "$badlat")
command grep -q "probe.latency='fast'" <<< "$viol" \
  && ok "validator flags a non-numeric probe.latency (the probe would silently run on its 30s default)" \
  || bad "a non-numeric probe.latency was not flagged — the default is in force and nobody knows"
printf 'probe.latency=5\n' > "$badlat"
viol=$(validate_decl "$badlat")
command grep -q "probe.latency" <<< "$viol" \
  && bad "a numeric probe.latency was flagged: $viol" \
  || ok "a whole-number probe.latency passes (the mock's 5 is this shape)"

echo "-- the workflow's OWN harness contract agrees across every profile declaring it --"
# A profile file is the settings-JSON SHAPE, not a brand: settings-hooks.json
# and codex.hooks.json already carried the same two hook commands verbatim
# (PreToolUse -> heartbeat.sh, Stop -> record.sh stop-gate) with NOTHING
# comparing them — the declaration checks above pin KEYS and PLACEHOLDERS, never
# profile CONTENT. A silent divergence loses the heartbeat or the stop gate on
# one backend with no error anywhere. Split only when a divergence EXISTS, with
# the divergence as the reason; never by copying a file that has no
# backend-specific content in it.
profile_hooks() { # file -> "<event>\t<command>" lines
  awk '
    /"hooks"[[:space:]]*:[[:space:]]*\{/ { inh=1; next }
    inh && match($0, /"[A-Za-z]+"[[:space:]]*:[[:space:]]*\[/) {
      e=substr($0, RSTART+1); sub(/".*/, "", e)
      if (e != "hooks") ev=e          # the per-matcher inner array is not an event
      next
    }
    ev != "" && match($0, /"command"[[:space:]]*:[[:space:]]*"/) {
      c=substr($0, RSTART); sub(/^"command"[[:space:]]*:[[:space:]]*"/, "", c)
      sub(/"[[:space:]]*,?[[:space:]]*$/, "", c)
      print ev "\t" c
    }' "$1" | sort -u
}
hooks_diverge() { # dir -> violation lines
  local d=$1 f ev n ref refc c evs files
  evs=$( for f in "$d"/*.json; do [ -f "$f" ] || continue; profile_hooks "$f" | cut -f1; done | sort -u )
  for ev in $evs; do
    files=""; n=0
    for f in "$d"/*.json; do
      [ -f "$f" ] || continue
      if profile_hooks "$f" | awk -F'\t' -v e="$ev" '$1==e{k++} END{exit k?0:1}'; then
        files="$files $f"; n=$((n + 1))
      fi
    done
    [ "$n" -ge 2 ] || continue
    ref=""; refc=""
    for f in $files; do
      c=$(profile_hooks "$f" | awk -F'\t' -v e="$ev" '$1==e{print $2}' | sort | paste -sd'~' -)
      if [ -z "$ref" ]; then ref=$f; refc=$c
      elif [ "$c" != "$refc" ]; then
        echo "$ev DIVERGES: $(basename "$ref") has '$refc' but $(basename "$f") has '$c'"
      fi
    done
  done
}
shared_events() { # dir -> count of events declared by >= 2 profiles
  local d=$1 f ev n evs c=0
  evs=$( for f in "$d"/*.json; do [ -f "$f" ] || continue; profile_hooks "$f" | cut -f1; done | sort -u )
  for ev in $evs; do
    n=0
    for f in "$d"/*.json; do
      [ -f "$f" ] || continue
      profile_hooks "$f" | awk -F'\t' -v e="$ev" '$1==e{k++} END{exit k?0:1}' && n=$((n + 1))
    done
    [ "$n" -ge 2 ] && c=$((c + 1))
  done
  printf '%s\n' "$c"
}
PROFD="$WF_ROOT/config/profiles"
np=$(ls "$PROFD"/*.json 2>/dev/null | command grep -c .)
precond "N>=2 profile files to compare (saw $np)" test "$np" -ge 2
nh=$(profile_hooks "$PROFD/settings-hooks.json" | command grep -c .)
precond "the extractor reads N>=3 hook commands out of the shared profile (saw $nh)" test "$nh" -ge 3
ns=$(shared_events "$PROFD")
precond "N>=2 hook events are declared by more than one profile (saw $ns) — otherwise this compares nothing" \
  test "$ns" -ge 2
viol=$(hooks_diverge "$PROFD")
[ -z "$viol" ] \
  && ok "every hook event declared by more than one profile carries byte-identical workflow commands ($ns shared)" \
  || bad "the workflow's own harness contract has diverged between profiles: $viol"
# An event only ONE profile declares is a deliberate asymmetry, not a divergence
# (codex has no Notification hook by design, backend-seam.md §8) — the rule must
# not fire on it.
profile_hooks "$PROFD/settings-hooks.json" | command grep -q '^Notification' \
  && ! profile_hooks "$PROFD/codex.hooks.json" | command grep -q '^Notification' \
  && ok "a hook event only ONE profile declares is untouched (codex's absent Notification stays a named asymmetry)" \
  || bad "the Notification asymmetry the rule must tolerate is not present in the fixture — this control proves nothing"
fakep=$(sc_tmpdir)/profiles
mkdir -p "$fakep"
cp "$PROFD/settings-hooks.json" "$fakep/a.json"
sed 's|session/heartbeat.sh|session/heartbeat-DIVERGED.sh|' "$PROFD/settings-hooks.json" > "$fakep/b.json"
precond "the known-bad fixture really differs from its twin" \
  bash -c '! diff -q "$1/a.json" "$1/b.json" > /dev/null' _ "$fakep"
command grep -q 'PreToolUse DIVERGES' <<< "$(hooks_diverge "$fakep")" \
  && ok "a profile with a diverged hook command is FLAGGED (known-bad fires, naming the event and both sides)" \
  || bad "hook-agreement rule vacuous — a diverged PreToolUse command passed"

echo "-- declaration placeholders ⊆ the adapter's substitution set --"
ADAPTER_TOKENS="model effort workspace profile bootstrap"
decl_tokens() { # file -> {tokens} in cmd.launch
  pty_decl_get "$1" cmd.launch 2>/dev/null | command grep -oE '\{[a-z_]+\}' | tr -d '{}' | sort -u
}
for f in "$WF_ROOT"/config/backends/*.kv; do
  viol=""
  for t in $(decl_tokens "$f"); do
    command grep -qxF "$t" <<< "$(printf '%s\n' $ADAPTER_TOKENS)" || viol="$viol {$t}"
  done
  [ -z "$viol" ] \
    && ok "$(basename "$f") cmd.launch placeholders all substitutable" \
    || bad "$(basename "$f") uses placeholders the adapter never fills:$viol (first spawn would refuse)"
done
badpl=$(sc_tmpdir)/badpl.kv
printf 'cmd.launch=x --file {prompt_file_arg}\n' > "$badpl"
viol=""
for t in $(decl_tokens "$badpl"); do
  command grep -qxF "$t" <<< "$(printf '%s\n' $ADAPTER_TOKENS)" || viol="$viol {$t}"
done
[ -n "$viol" ] && ok "an unsubstitutable placeholder is flagged (known-bad fires)" \
  || bad "placeholder-set validator vacuous"

echo "-- backend-seam §3's worked declaration IS the shipped one --"
# §3 prints claude.kv as a worked example and says "values are verbatim from the
# shipped declaration". It had stopped being true: the file had grown
# sig.quota_exhausted and the self-update modal pair, and its trust signature
# had been WIDENED, while the doc still showed the narrow one — so a backend
# author copying the example got a signature that no longer matches what ships.
# A claim of verbatim is checkable, so it is checked; a maintainer who wants an
# abbreviated example changes the sentence and this arm together.
dblk=$(awk '/^```$/{n++; next} n==1 && /^[a-z]/' "$WF_ROOT/design/backend-seam.md" | head -40)
decls=$(command grep -vE '^\s*#|^\s*$' "$WF_ROOT/config/backends/claude.kv")
precond "§3 carries a fenced declaration block" test -n "$dblk"
miss=""
while IFS= read -r line; do
  [ -n "$line" ] || continue
  command grep -qxF "$line" <<< "$decls" || miss="$miss"$'\n'"    doc has, claude.kv does not: $line"
done <<< "$dblk"
while IFS= read -r line; do
  [ -n "$line" ] || continue
  k=${line%%=*}
  command grep -q "^$k=" <<< "$dblk" || miss="$miss"$'\n'"    claude.kv has, doc does not show: $k="
done <<< "$decls"
[ -z "$miss" ] \
  && ok "every line of §3's example is in claude.kv and every key of claude.kv is in §3 ($(printf '%s\n' "$decls" | command grep -c .) keys)" \
  || bad "§3 says its values are verbatim from the shipped declaration; they are not:$miss"

check_done
