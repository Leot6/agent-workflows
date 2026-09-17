#!/usr/bin/env bash
# iteration-log/cite-check.sh — every commit this tree CITES is a commit a
# reader can still open.
#
# The durable home outlives the topic trees whose evidence it carries, and it
# cites a repository that keeps moving underneath it: a close-out consolidation
# rewrites a range, the old SHAs leave the branch, and the entry that rests its
# whole argument on one now points at nothing. Nothing red at the time it
# happened. Measured 2026-09-08 over three topics and three consolidations —
# twenty cited commits off the delivered branch, six of them on NO REF AT ALL, reachable
# only while a reflog entry survived (default gc.reflogExpireUnreachable: 30
# days; three of the six were 26 days old when this was written). Three of those
# six were the whole evidentiary basis of one closed validation-debt row.
#
# WHY THIS IS A TOOL AND NOT A CHECK ARM. self-check is hermetic and this tree
# is deliberately repo-agnostic — no workflow file names a delivered repository,
# because the topic's own `project.kv repo=` does. So the sweep cannot resolve
# anything on its own; it takes the repo as an argument. self-check drives it
# against a temp git fixture (97-iterlog), which proves the mechanism; the
# maintainer runs it against the real repo at the moments that break citations:
# after any history consolidation, and BEFORE deleting a backup ref.
#
# usage:  iteration-log/cite-check.sh <repo-path> [tree-root]
# exit:   0 every cited commit resolves to at least one ref
#         1 at least one cites a commit no ref reaches (or the sweep is vacuous)
#         2 usage / unusable repo
set -u

repo=${1:-}
root=${2:-}
case "$repo" in
  ''|-h|--help) echo "usage: $0 <repo-path> [tree-root]" >&2; exit 2 ;;
esac
[ -d "$repo" ] || { echo "cite-check: '$repo' is not a directory" >&2; exit 2; }
git -C "$repo" rev-parse --git-dir >/dev/null 2>&1 \
  || { echo "cite-check: '$repo' is not a git repository" >&2; exit 2; }

if [ -z "$root" ]; then
  root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
fi

# The corpus is every surface that carries durable evidence, ENUMERATED rather
# than hand-listed where a directory will do. validation-debt.md is in it by
# measurement, not by theory: the close-out audit that prompted this scoped
# itself to entries/ + NOTES.md and missed five citations, four of them
# unreferenced, three of them one closed row's entire evidence.
corpus=""
[ -d "$root/iteration-log" ] && corpus="$corpus $(find "$root/iteration-log" -name '*.md' -type f 2>/dev/null)"
[ -f "$root/self-check/validation-debt.md" ] && corpus="$corpus $root/self-check/validation-debt.md"
# shellcheck disable=SC2086
set -- $corpus
[ $# -ge 1 ] || { echo "cite-check: corpus is empty under $root — the sweep did not run" >&2; exit 1; }

tokens=$(command grep -rhoE '\b[0-9a-f]{7,40}\b' "$@" 2>/dev/null | sort -u)
# A corpus that cites no commit at all has nothing to resolve — a fresh log.
# Distinct from the floor below: there, hex tokens exist and none resolves.
if [ -z "$tokens" ]; then
  echo "cite-check: the corpus cites no commit — nothing to resolve"
  exit 0
fi

n_commit=0; n_bad=0; bad_list=""; n_sole=0; sole_list=""
for t in $tokens; do
  [ "$(git -C "$repo" cat-file -t "$t" 2>/dev/null)" = commit ] || continue
  n_commit=$((n_commit + 1))
  refs=$(git -C "$repo" for-each-ref --contains "$t" --format='%(refname:short)' 2>/dev/null)
  if [ -z "$refs" ]; then
    n_bad=$((n_bad + 1))
    bad_list="$bad_list$t $(git -C "$repo" log -1 --format='%s' "$t" 2>/dev/null)"$'\n'
    # name every citing file, so the fix has an address
    for f in "$@"; do
      command grep -q "$t" "$f" 2>/dev/null && bad_list="$bad_list    cited by ${f#"$root"/}"$'\n'
    done
  elif [ "$(printf '%s\n' "$refs" | command grep -c .)" -eq 1 ]; then
    # ONE ref between this citation and unresolvable. Not a failure — the
    # citation resolves today — but it is the whole content of §8's deletion
    # rule, and a maintainer about to delete a backup ref needs it BEFORE the
    # deletion rather than as a red afterwards.
    n_sole=$((n_sole + 1))
    sole_list="$sole_list  $t  sole home: $refs"$'\n'
  fi
done

# A sweep that resolved nothing is not a clean verdict — it is the wrong repo,
# or a corpus that lost its citations. The tree's standing rule for every
# floored family.
if [ "$n_commit" -eq 0 ]; then
  echo "cite-check: 0 of the $(printf '%s\n' "$tokens" | command grep -c .) hex tokens resolve to a commit in $repo" >&2
  echo "cite-check: this is not a clean verdict — wrong repository, or the corpus lost its citations" >&2
  exit 1
fi

cc_sole_report() {
  [ "$n_sole" -eq 0 ] && return 0
  echo "cite-check: $n_sole of them hang on a SINGLE ref — deleting it orphans the citation:"
  printf '%s' "$sole_list"
  echo "  (operations.md §8: pin with iterlog-anchor/<sha8>, or keep the ref)"
}
if [ "$n_bad" -eq 0 ]; then
  echo "cite-check: $n_commit cited commits, every one reachable from a ref in $repo"
  cc_sole_report
  exit 0
fi
echo "cite-check: $n_bad of $n_commit cited commits are on NO REF and die at the next gc:"
printf '%s' "$bad_list"
echo "fix: pin each (git -C $repo tag -a iterlog-anchor/<sha8> <sha> -m 'cited by …'),"
echo "     or re-point the citation at a commit the branch still carries."
cc_sole_report
exit 1
