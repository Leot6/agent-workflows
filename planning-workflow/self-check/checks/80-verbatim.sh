#!/usr/bin/env bash
# 80-verbatim — text the tree declares authoritative in one home and
# instantiates in another must be byte-identical. A§5.3 makes protocol §7 the
# authority for the restart line and the close-out template its verbatim
# instantiation site; a fresh session pastes whichever copy it meets, so a
# divergence is a session that resumes with the wrong instruction.
#
# HONEST BOUNDARY: byte equality between two copies proves they agree, never
# that what they agree on is right. Both copies naming a stage that does not
# exist passes here and fails 20-xref only if the stage is a §-reference.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/fixtures/lib.sh"

PROTO="$WF_ROOT/runtime-docs/protocol.md"
CLOSE="$WF_ROOT/runtime-docs/templates/close-out.md"

# The authority: protocol §7's first fenced/indented block line.
auth=$(grep -m1 '^ *read <ABS workflow>.*resume topic at' "$PROTO" | sed 's/^ *//')
inst=$(grep -m1 '^ *read <ABS workflow>.*resume topic at' "$CLOSE" | sed 's/^ *//')

precond "the authority copy was found"     test -n "$auth"
precond "the instantiation copy was found" test -n "$inst"

[ "$auth" = "$inst" ] \
  && ok "the restart line is byte-identical in protocol §7 and the close-out template" \
  || bad "restart line divergence:"$'\n'"        authority:  $auth"$'\n'"        close-out:  $inst"

# The amend entry line: protocol §7 is the authority, the plan template the
# instantiation site. Measured on a trial tree — a one-word divergence between
# the two copies left all nine checks green, which is what this assertion is
# for. The implementer is reading `plan.md`, not this protocol, so its copy is
# the only one that reaches the party who needs the line.
a_auth=$(grep -m1 'amend topic at <ABS topic root>' "$PROTO" | sed 's/^ *//')
a_inst=$(grep -m1 'amend topic at <ABS topic root>' "$WF_ROOT/runtime-docs/templates/plan-dir/00_context.md" | sed 's/^ *//')
precond "the amend authority copy was found"     test -n "$a_auth"
precond "the amend instantiation copy was found" test -n "$a_inst"
[ "$a_auth" = "$a_inst" ] \
  && ok "the amend entry line is byte-identical in protocol §7 and the plan template" \
  || bad "amend entry line divergence:"$'\n'"        authority: $a_auth"$'\n'"        plan:      $a_inst"

# The spawn message: protocol §5.2 is the authority, the launcher the
# instantiation. Compared on the invariant tail — everything after the prompt
# path — because the authority writes a placeholder where the launcher writes
# a variable, and normalising one into the other is where a check starts
# proving its own rewrite rather than the tree's agreement.
TAIL=', execute it fully. Do not summarize back.'
LAUNCHER="$WF_ROOT/runtime-scripts/spawn.sh"
if [ -f "$LAUNCHER" ]; then
  auth_n=$(command grep -cF "$TAIL" "$PROTO")
  inst_n=$(command grep -cF "$TAIL" "$LAUNCHER")
  precond "the spawn message was found in protocol §5.2" test "$auth_n" -ge 1
  [ "$inst_n" -ge 1 ] \
    && ok "the launcher sends protocol §5.2's message, tail-identical" \
    || bad "runtime-scripts/spawn.sh does not send protocol §5.2's fixed message — the one text A§3 forbids adding framing to"
fi

# The maintainer variant has one home only — it must NOT have been copied into
# a template, where it would become a second thing to keep in sync.
copies=$(( $(harvest_docs | xargs grep -o 'maintainer session: workflow tree' 2>/dev/null | wc -l) ))
[ "$copies" -eq 1 ] \
  && ok "the maintainer entry line has exactly one home" \
  || bad "the maintainer entry line appears $copies times — it has one home (protocol §7); a second copy in the same file is as much to keep in sync as one in another"

# The restart line must end the close-out template: A§4 makes it the file's
# last content, and anything after it is content a resuming session never reads.
last=$(grep -v '^\s*$' "$CLOSE" | tail -1)
printf '%s' "$last" | command grep -q '^```$' \
  && ok "the close-out template ends with the fenced restart block" \
  || bad "the close-out template's last content is not the restart fence: $last"

# Non-vacuity: run the check's OWN extraction and comparison over a mutated
# copy of the real close-out template. A guard that merely proves `[` can
# compare strings would still fire with the assertion above deleted.
probe_dir=$(sc_tmpdir)
sed 's/first owner touchpoint/first owner touchpoin/' "$CLOSE" > "$probe_dir/close.md"
probe_matches() {
  local a b
  a=$(grep -m1 '^ *read <ABS workflow>.*resume topic at' "$PROTO" | sed 's/^ *//')
  b=$(grep -m1 '^ *read <ABS workflow>.*resume topic at' "$probe_dir/close.md" | sed 's/^ *//')
  [ -n "$a" ] && [ -n "$b" ] && [ "$a" = "$b" ]
}
known_bad "a one-character divergence in the real line is caught" probe_matches

check_done
