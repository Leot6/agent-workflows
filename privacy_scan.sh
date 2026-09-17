#!/usr/bin/env bash
# privacy_scan.sh — deployment-layer guard: nothing private reaches this repo.
#
# The two workflow trees are public and project-agnostic, and they learn from
# private work: every harvest, observation and measurement starts life inside a
# real project. This is the mechanical half of keeping the two apart (each
# tree's maintenance rules carry the writing half). Two pattern sources:
#
#   built-in   shapes that are private in ANY deployment — home-directory paths,
#              e-mail addresses, credentials, private network addresses. They
#              are committed below and run everywhere, CI included.
#   denylist   the words only YOU know are private — company, project, module,
#              repository, host, internal-tool and people names. One extended
#              regex per line (# comments), case-insensitive, read from
#                .privacy-denylist                               (repo root, gitignored)
#                ${XDG_CONFIG_HOME:-~/.config}/workflows/privacy-denylist
#              and never committed: a list of private names is itself private.
#
# A line carrying the marker `privacy-scan: allow` is exempt — for the rare
# fixture that must spell a shape. The marker is visible in review, which is
# the point: an exemption nobody can see is how a leak ships.
#
# usage:
#   privacy_scan.sh --staged           added lines and paths in the git index (pre-commit)
#   privacy_scan.sh --message <file>   a commit message (commit-msg)
#   privacy_scan.sh --all              every tracked and unignored file (CI, manual audit)
#   privacy_scan.sh --self-test        prove every built-in shape fires, and public ones do not
#   privacy_scan.sh <path>...          the given files
# exit: 0 clean · 1 findings (each printed as place: label: text) · 2 usage
set -uo pipefail
export LC_ALL=C

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SELF="privacy_scan.sh"
ALLOW_MARK='privacy-scan: allow'

# label<TAB>extended regex. Kept to shapes that are private wherever they
# appear, so the list needs no per-deployment tuning and CI can run it.
BUILTIN=$(cat <<'EOF'
home-path	/Users/[A-Za-z0-9._-]+/|/home/[A-Za-z0-9._-]{2,}/|[A-Za-z]:\\Users\\
email	[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}
private-key	-----BEGIN [A-Z ]*PRIVATE KEY-----
aws-key	AKIA[0-9A-Z]{16}
github-token	gh[pousr]_[A-Za-z0-9]{36}
slack-token	xox[abposr]-[A-Za-z0-9-]{10,}
api-key	sk-(ant-)?[A-Za-z0-9_-]{24,}
private-ip	(^|[^0-9.])(10\.[0-9]{1,3}|192\.168|172\.(1[6-9]|2[0-9]|3[01]))\.[0-9]{1,3}\.[0-9]{1,3}([^0-9.]|$)
EOF
)

# E-mail shapes that identify nobody: documentation domains, and the no-reply
# addresses git hosts and tools hand out for exactly this purpose.
email_is_public() { # address -> rc 0 when it identifies nobody
  case "$1" in
    *@example.com|*@example.org|*@example.net|*@*.example|*@example.invalid|*@*.invalid) return 0 ;;
    *@users.noreply.github.com|noreply@*|no-reply@*) return 0 ;;
  esac
  return 1
}

denylist() { # -> label<TAB>regex per denylist line
  local f
  for f in "$ROOT/.privacy-denylist" "${XDG_CONFIG_HOME:-$HOME/.config}/workflows/privacy-denylist"; do
    [ -r "$f" ] || continue
    command grep -vE '^[[:space:]]*(#|$)' "$f" | while IFS= read -r re; do
      printf 'denylist\t%s\n' "$re"
    done
  done
}

# Scan "place<TAB>text" lines on stdin; print findings; rc 1 if any. One grep
# per rule over the whole stream; only the lines that hit are looked at again.
scan_lines() {
  local tmp found=0 label re opt place text hit
  tmp=$(mktemp "${TMPDIR:-/tmp}/privacy_scan.XXXXXX") || return 2
  command grep -vF -- "$ALLOW_MARK" > "$tmp"
  while IFS=$'\t' read -r label re; do
    [ -n "$re" ] || continue
    opt=-E; [ "$label" = denylist ] && opt=-iE
    while IFS=$'\t' read -r place text; do
      if [ "$label" = email ]; then
        hit=$(command grep -o $opt -- "$re" <<< "$text" | while IFS= read -r a; do
                email_is_public "$a" || { printf '%s\n' "$a"; break; }
              done)
      else
        hit=$(command grep -o $opt -- "$re" <<< "$text" | head -1)
        [ "$label" = private-ip ] && hit=$(command grep -oE '[0-9.]+[0-9]' <<< "$hit" | head -1)
      fi
      [ -n "$hit" ] || continue
      printf '%s: %s: %s\n' "$place" "$label" "$hit"
      found=1
    done < <(command grep $opt -- "$re" "$tmp")
  done < <( { printf '%s\n' "$BUILTIN"; denylist; } )
  rm -f "$tmp"
  return $found
}

files_to_lines() { # files... -> "path:line<TAB>text"
  local f
  for f in "$@"; do
    [ "${f#./}" = "$SELF" ] && continue
    [ -f "$f" ] || continue
    command grep -Iq . "$f" 2>/dev/null || continue          # binary or empty
    printf '%s:0\t%s\n' "${f#./}" "${f#./}"                   # the path itself
    awk -v p="${f#./}" '{ printf "%s:%d\t%s\n", p, NR, $0 }' "$f"
  done
}

staged_lines() { # added lines and added paths of the index
  git -C "$ROOT" diff --cached --name-only --diff-filter=AMR | while IFS= read -r f; do
    [ "$f" = "$SELF" ] && continue
    printf '%s:0\t%s\n' "$f" "$f"
  done
  git -C "$ROOT" diff --cached -U0 --no-color --diff-filter=AMR -- . ":(exclude)$SELF" | awk '
    /^\+\+\+ b\// { file = substr($0, 7); next }
    /^@@/ { split($3, a, ","); line = substr(a[1], 2) + 0; next }
    /^\+/ { printf "%s:%d\t%s\n", file, line, substr($0, 2); line++ }'
}

# Non-vacuity: each built-in label must fire on its own known-bad line, and
# the public shapes beside them must not — a pattern that stopped matching, or
# started matching everything, is caught here rather than in a leak.
self_test() {
  local t out label fails=0 pub
  t=$(mktemp -d "${TMPDIR:-/tmp}/privacy_scan.XXXXXX") || return 2
  {
    printf '%s\n' 'log in /Users/someone/project'
    printf '%s\n' 'contact person@company.test'
    printf '%s\n' '-----BEGIN OPENSSH PRIVATE KEY-----'
    printf '%s\n' 'id AKIA0123456789ABCDEF'
    printf 'token gh%s_%s\n' p 012345678901234567890123456789abcdef
    printf 'hook xox%s-0123456789-abcdef\n' b
    printf 'key sk-%s\n' abcdefghijklmnopqrstuvwxyz0123
    printf '%s\n' 'db at 192.168.10.20:5432'
  } > "$t/bad"
  {
    printf '%s\n' 'fixture home /home/x/file and /tmp/dw-run/ws'
    printf '%s\n' 'ci@example.invalid 123+u@users.noreply.github.com noreply@vendor.test'
    printf '%s\n' 'version 1.10.2.3 and build 2026.10.1'
    printf '%s\n' 'real /Users/someone/x  privacy-scan: allow'
  } > "$t/good"
  out=$(files_to_lines "$t/bad" | scan_lines)
  for label in home-path email private-key aws-key github-token slack-token api-key private-ip; do
    command grep -q ": $label: " <<< "$out" && echo "ok   $label fires" \
      || { echo "FAIL $label did not fire on its known-bad line"; fails=1; }
  done
  pub=$(files_to_lines "$t/good" | scan_lines)
  [ -z "$pub" ] && echo "ok   public shapes and the allow marker pass" \
    || { echo "FAIL public shapes were flagged:"; printf '%s\n' "$pub" | sed 's/^/     /'; fails=1; }
  rm -rf "$t"
  return $fails
}

case "${1:-}" in
  --self-test)
    self_test; exit $? ;;
  --staged)
    git -C "$ROOT" rev-parse --git-dir > /dev/null 2>&1 || { echo "privacy_scan: not a git repository" >&2; exit 2; }
    out=$(staged_lines | scan_lines) ;;
  --message)
    [ -r "${2:-}" ] || { echo "privacy_scan: --message needs a readable file" >&2; exit 2; }
    out=$(command grep -v '^#' "$2" | awk '{ printf "commit message:%d\t%s\n", NR, $0 }' | scan_lines) ;;
  --all)
    cd "$ROOT" || exit 2
    out=$( { git ls-files; git ls-files -o --exclude-standard; } | sort -u \
             | while IFS= read -r f; do files_to_lines "$f"; done | scan_lines) ;;
  -h|--help|'')
    sed -n '2,29p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    [ -n "${1:-}" ] && exit 0 || exit 2 ;;
  -*)
    echo "privacy_scan: unknown option '$1'" >&2; exit 2 ;;
  *)
    out=$(files_to_lines "$@" | scan_lines) ;;
esac

if [ -n "$out" ]; then
  printf '%s\n' "$out"
  echo "privacy_scan: $(printf '%s\n' "$out" | command grep -c .) finding(s) — rewrite them in mechanism terms (a topic alias, a neutral path), or mark a deliberate fixture line with '$ALLOW_MARK'." >&2
  exit 1
fi
exit 0
