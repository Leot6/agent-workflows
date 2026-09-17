#!/usr/bin/env bash
# emit_gate.sh — the tree-owned red gate over an emitted plan version.
#
# OBS-86's ground truth: the author-side instruments were mostly PRINTERS —
# tools printed readings, the author transcribed and compared, and the author
# was the only comparator (obs-68's memory-connection failure mirrored on the
# instrument side). OBS-88 named the counter-example: landed_v*.py, four-for-
# four, "it catches even its own maintenance errors" — marker-vs-product
# mechanical comparison, exit 1 on mismatch. This script is that shape,
# tree-owned so the criteria's shape is frozen outside the authoring session
# (obs-74: a private harness measures its author).
#
# DEFAULT FORM IS THE RED GATE (owner-ruled): every check here
# exits 1 on mismatch. The printer form is allowed ONLY where a comparison
# cannot be mechanized, and such an arm must say so in its header comment.
#
# Three arms (minimal two classes + fence stripping, as ruled):
#   1. READING-CURRENCY — a sentence asserting a count at HEAD ("N 项/条/
#      hits/rows/lines ... at HEAD", Chinese or English) must carry the
#      command that produced it (inline `$ …` or a named E<n> block); a bare
#      currency-count with no command is refused (the second shape of the
#      stamp-forwarding lie, measured: "412 lines at HEAD" forwarded from an
#      earlier unit).
#   2. SAME-SECTION CONSISTENCY — two DIFFERENT bare numbers claimed for the
#      same construct within one file are refused (obs-84's fingerprint:
#      same-section divergent counts are the mark of an edited-but-not-
#      rederived neighborhood). The comparison is reading-vs-sentence,
#      mechanical: we do not re-run the commands here (the verifier's duty),
#      we catch two sentences disagreeing.
#   3. CITE RESOLUTION — every `path:line` pin in unfenced prose resolves
#      against the checkout and pins a line that exists. (Fenced blocks are
#      quoted data — the delivery tree's _gates_strip_fences precedent.)
#
# HONEST BOUNDARY: this gate never re-runs evidence commands (the verifier
# does that, and re-running builds here would be a second verifier with no
# lineage independence); it checks the SHAPE of the claim surface — currency
# claims carry commands, sections agree with themselves, citations resolve.
# A plan can pass this gate and still be wrong; it cannot pass it with the
# r11 escape classes.
#
# Usage: emit_gate.sh <plan-version-dir> <checkout-root>
# Exit: 0 clean · 1 findings (each self-describing) · 2 usage fault.
set -uo pipefail
# The gate scans UTF-8 documents; a C locale splits multibyte keys (live-caught
# by 98-emit-gate). The name of a UTF-8 locale differs by host — C.UTF-8 on
# Linux, en_US.UTF-8 on macOS — so the first one whose charmap really is UTF-8
# wins, and none at all is a refusal rather than a silent byte-mode scan.
for _loc in C.UTF-8 C.utf8 en_US.UTF-8; do
  [ "$(LC_ALL=$_loc locale charmap 2>/dev/null)" = UTF-8 ] && { export LC_ALL=$_loc; break; }
done
[ "$(locale charmap 2>/dev/null)" = UTF-8 ] \
  || { echo "refuse: no UTF-8 locale available (tried C.UTF-8, en_US.UTF-8)" >&2; exit 2; }
DIR=${1:?usage: emit_gate.sh <plan-version-dir> <checkout-root>}
ROOT=${2:?usage: emit_gate.sh <plan-version-dir> <checkout-root>}
[ -d "$DIR" ] || { echo "refuse: not a directory: $DIR" >&2; exit 2; }
[ -d "$ROOT" ] || { echo "refuse: not a checkout: $ROOT" >&2; exit 2; }

fails=0
strip_fences() { awk '/^[[:space:]]*(```|~~~)/{f=!f; next} !f' "$1"; }

# ---- arm 1: currency counts must carry their command ------------------------
# "N <unit> ... at HEAD" / "HEAD ... N <unit>" / 「… N 条/项/行 … at HEAD」
while IFS=: read -r file line text; do
  [ -n "$text" ] || continue
  # currency phrase present?
  printf '%s' "$text" | grep -qE '[0-9]+[[:space:]]*(个|条|项|行|hits?|rows?|lines?|occurrences?|matches?|call sites?)([^a-z]|$)' || continue
  printf '%s' "$text" | grep -qiE 'at[[:space:]]+HEAD|HEAD[[:space:]]+(读数|reading|=)' || continue
  # command present? inline `$ …` or `E<n>` label or a fenced block follows within 3 lines
  if printf '%s' "$text" | grep -qE '\$ |`E[0-9]+`|`\$'; then continue; fi
  ctx=$(strip_fences "$file" | sed -n "$((line+1)),$((line+3))p")
  printf '%s' "$ctx" | grep -qE '^E[0-9]+: |\$ ' && continue
  echo "emit-gate[reading-currency] $file:$line — a count asserted at HEAD carries no command (inline \`\$ …\` or a named E<n> block): $(printf '%s' "$text" | cut -c1-90)"
  fails=$((fails + 1))
done < <(for f in $(find "$DIR" -name '*.md' -type f); do
           strip_fences "$f" | grep -nE '.' /dev/null "$f" 2>/dev/null || true
         done)

# ---- arm 2: same-construct divergent counts within one file ------------------
# obs-84's fingerprint: a construct claimed with two different counts in one
# file. The construct token is the nearest non-numeric word adjacent to the
# count phrase — on EITHER side (Chinese prose puts it before or after).
# Perl, not awk: the windows are CHARACTERS, and awk implementations disagree
# on that (gawk counts characters, mawk bytes, BSD awk refuses to split a
# multibyte sequence) — the same line keyed three ways on three hosts.
div=$(for f in $(find "$DIR" -name '*.md' -type f); do
  strip_fences "$f" | perl -CSD -Mutf8 -e '
    my $file = shift; my %seen;
    while (my $line = <STDIN>) {
      chomp $line;
      while ($line =~ /([0-9]+)\s*(?:处|条|个|项|行|hits?|rows?|lines?)/) {
        my ($ms, $me, $num) = ($-[0], $+[0], $1);
        # key window: 12 chars after the count phrase, minus digits and
        # whitespace; empty => the 12 chars before it, minus the link-words
        # that merely connect prose to the count. The construct may FOLLOW
        # ("N 处构造K") or PRECEDE ("构造K共 N 处") its count.
        my $win = substr($line, $me, 12);
        $win =~ s/[0-9\s]//g; $win =~ s/处|条|个|项|行//g;
        if ($win eq "") {
          $win = substr($line, $ms >= 12 ? $ms - 12 : 0, 12);
          $win =~ s/[0-9\s]//g; $win =~ s/处|条|个|项|行|共|亦|有|恰|计//g;
        }
        my $key = substr($win, 0, 16);
        if ($key ne "") {
          printf "emit-gate[same-section] %s — construct [%s] claimed as both %s and %s (obs84 fingerprint)\n",
            $file, $key, $seen{$key}, $num
            if defined $seen{$key} && $seen{$key} ne $num;
          $seen{$key} = $num;
        }
        $line = substr($line, $me);   # advance past this count
      }
    }' "$f"
done)
n_div=$(printf '%s' "$div" | grep -c 'emit-gate' || true)
[ "${n_div:-0}" -gt 0 ] && { printf '%s\n' "$div"; fails=$((fails + n_div)); }

# ---- arm 3: cite resolution (path:line pins in unfenced prose) --------------
while IFS= read -r pin; do
  path=${pin%:*}; nn=${pin##*:}
  [ -n "$path" ] && [ -n "$nn" ] || continue
  case "$path" in /*) f="$path" ;; *) f="$ROOT/$path" ;; esac
  if [ ! -f "$f" ]; then
    echo "emit-gate[cite] unresolved pin: $pin (tried $f)"
    fails=$((fails + 1))
    continue
  fi
  lines=$(( $(wc -l < "$f") ))
  if [ "$nn" -gt "$lines" ]; then
    echo "emit-gate[cite] $pin pins line $nn but $f has $lines lines"
    fails=$((fails + 1))
  fi
done < <(for f in $(find "$DIR" -name '*.md' -type f); do
           strip_fences "$f" | grep -oE '[A-Za-z0-9_./-]+\.(cc|h|cpp|hpp|py|sh|md|json|tsv):[0-9]+' || true
         done | sort -u)

echo "emit-gate: $fails finding(s) over $(( $(find "$DIR" -name '*.md' -type f | wc -l) )) files"
[ "$fails" -eq 0 ] || exit 1
exit 0
