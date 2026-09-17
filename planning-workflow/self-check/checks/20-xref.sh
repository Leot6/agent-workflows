#!/usr/bin/env bash
# 20-xref — every numbered section reference resolves to a heading that exists.
# A stale number is the worst kind of wrong pointer: it looks authoritative and
# lands somewhere plausible.
#
# Five reference forms, which is every form the tree uses:
#   A§n[.m]                       → design/architecture.md
#   `architecture.md` §n[.m]      → design/architecture.md
#   protocol[.md] §n[.m]          → runtime-docs/protocol.md
#   bare §n[.m] in those two files → that same file
#   bare §n[.m] in any other DOC → EITHER authority; it resolves if either
#                                   carries it. The referent really is
#                                   contextual — README's mean architecture,
#                                   close-out's mean protocol, rationale's
#                                   "Campaign D §4" means itself — so demanding
#                                   one target would red correct text. A number
#                                   in neither file is still caught, which is
#                                   the failure this form exists for. "brief 3
#                                   §2" is a brief section, not a document one,
#                                   and is excluded by the pattern.
# self-check/*.sh joins the two explicit forms (A§n, protocol §n) because A§5.3
# delegates specification content to it, so its headers are spec — and they are
# the surface most likely to go stale, since a renumbering commit never touches
# them. Its BARE §n are not harvested: in a shell comment the referent is
# ambiguous, and the tree's checks cite protocol steps that way.
#
# HONEST BOUNDARY, three parts. (1) DANGLING numbers only — a §N that exists
# and discusses the wrong thing is semantic staleness no script can see; that
# is the conformance lens's job (protocol §7). (2) A sub-reference `n.m`
# resolves as a `### n.m` heading OR as a numbered step `m.` inside section n,
# because §5.1 and §0.3 are steps rather than headings; a third component
# (§4.6.4) is checked to its `n.m` only. (3) `discussion/` is out of scope: it
# is gitignored and deletes as a unit (A§13), so scratch notes must neither red
# this check nor feed its preconditions.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/fixtures/lib.sh"

ARCH="$WF_ROOT/design/architecture.md"
PROTO="$WF_ROOT/runtime-docs/protocol.md"
precond "both targets exist" test -f "$ARCH" -a -f "$PROTO"

heading_exists() { # <file> <n[.m]> -> rc
  local f=$1 ref=$2 top=${2%%.*} sub=${2#*.}
  command grep -qE "^## ${top}[. ]" "$f" || return 1
  case "$ref" in
    *.*)
      command grep -qE "^### ${ref}[. ]" "$f" && return 0
      awk -v t="$top" '
        !f && $0 ~ ("^## " t "[. ]") { f = 1; next }
        f && /^## / { exit }
        f' "$f" | command grep -qE "^ *${sub}\. " || return 1
      ;;
  esac
  return 0
}

checked=0
resolve() { # <file> <ref> <label>
  checked=$((checked + 1))
  heading_exists "$1" "$2" || bad "$3 does not resolve in ${1#"$WF_ROOT"/}"
}
# Sets FORM_N; never echoes — a `bad` inside a command substitution would be
# captured into the count instead of printed.
run_form() { # <target> <label-prefix>  — refs on stdin
  local tgt=$1 pfx=$2 ref
  FORM_N=0
  while IFS= read -r ref; do
    [ -n "$ref" ] || continue
    FORM_N=$((FORM_N + 1))
    resolve "$tgt" "$(printf '%s' "$ref" | cut -d. -f1,2)" "$pfx §$ref"
  done
}
spec_docs() { harvest_docs; find "$WF_ROOT/self-check" -name '*.sh'; }

run_form "$ARCH" "A" < <(spec_docs | xargs grep -hoE 'A§[0-9]+(\.[0-9]+)*' 2>/dev/null \
      | sed 's/A§//' | sort -u); n_a=$FORM_N
run_form "$ARCH" "architecture.md" < <(spec_docs | xargs grep -hoE 'architecture\.md`? §[0-9]+(\.[0-9]+)*' 2>/dev/null \
      | sed 's/.*§//' | sort -u); n_arch=$FORM_N
run_form "$PROTO" "protocol" < <(spec_docs | xargs grep -hoE 'protocol(\.md)?`? §[0-9]+(\.[0-9]+)*' 2>/dev/null \
      | sed 's/.*§//' | sort -u); n_pro=$FORM_N

# Lookbehinds need PCRE, which BSD grep lacks; perl carries the same engine on
# both hosts (Debian/Ubuntu ship perl-base as essential, macOS ships perl).
pcre_matches() { # <pattern> <file>... -> every match, one per line
  PAT=$1 perl -ne 'while (/$ENV{PAT}/g) { print "$&\n" }' "${@:2}"
}
BARE='(?<!A)(?<!architecture\.md)(?<!architecture\.md`)(?<!protocol)(?<!protocol\.md)(?<!protocol\.md`) §[0-9]+(\.[0-9]+)*'
n_self=0
for f in "$ARCH" "$PROTO"; do
  run_form "$f" "$(basename "$f") self" < <(pcre_matches "$BARE" "$f" 2>/dev/null \
      | sed 's/.*§//' | sort -u)
  n_self=$((n_self + FORM_N))
done
# Bare §n in every other DOC — resolves against either authority.
resolve_either() { # <ref> <label>
  local probe; probe=$(printf '%s' "$1" | cut -d. -f1,2)
  checked=$((checked + 1))
  heading_exists "$ARCH" "$probe" || heading_exists "$PROTO" "$probe" \
    || bad "$2 resolves in neither design/architecture.md nor runtime-docs/protocol.md"
}
n_oth=0
while IFS= read -r ref; do
  [ -n "$ref" ] || continue
  n_oth=$((n_oth + 1))
  resolve_either "$ref" "bare (other doc) §$ref"
done < <(harvest_docs | grep -v -e "^$ARCH$" -e "^$PROTO$" \
      | { mapfile -t _docs; pcre_matches '(?<!brief \d)'"$BARE" "${_docs[@]}"; } 2>/dev/null | sed 's/.*§//' | sort -u)

# Per-form floors, not one aggregate: the smallest form is a twentieth of the
# total, so a single aggregate floor cannot notice a form going dark.
precond "form A§n harvested"                   test "$n_a"    -ge 10
precond "form architecture.md §n harvested"    test "$n_arch" -ge 3
precond "form protocol §n harvested"           test "$n_pro"  -ge 10
precond "form bare self-§n harvested"          test "$n_self" -ge 20
precond "form bare §n elsewhere harvested"     test "$n_oth"  -ge 3
[ "$_FAIL" -eq 0 ] && ok "all $checked numbered section references resolve ($n_a A§ · $n_arch arch · $n_pro protocol · $n_self self · $n_oth other)"

known_bad "a fabricated §99 is caught" heading_exists "$ARCH" 99

check_done
