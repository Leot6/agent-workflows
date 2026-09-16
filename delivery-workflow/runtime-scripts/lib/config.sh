#!/usr/bin/env bash
# lib/config.sh — four-level kv resolution (design/config-and-adapters.md §1).
#
#   config/defaults.kv
#     ⊂ ${XDG_CONFIG_HOME:-~/.config}/delivery-workflow/config.kv   # operator/machine
#       ⊂  <ws>/config/topic.kv
#         ⊂  <ws>/config/slice.<nn>.<agent>.kv
#
# Most-specific wins; unset falls through; unset everywhere = rc 1 (schema-legal
# key with no value — caller falls back; never an error).
# Every loaded file is validated against config/schema.kv on load: unknown key
# = FAULT naming the key and file (a typo must not silently fall through);
# wildcard schema keys ('*' segment) match [A-Za-z0-9_-]+.
# Validation rules (schema.kv trailing comments):
#   rule.reviewer_effort_floor — resolved reviewer effort >= the run's base
#     effort (topic-level author effort), and a slice layer may never reduce
#     reviewer effort below its topic-level value — WITHIN a model: effort is a
#     per-model knob and no cross-model ordering exists to ground a comparison,
#     so across models the rule prints a NOTE (rc 0) and compares nothing.
#   rule.retired_slice_id — a slice.<nn>.<agent>.kv addressing a slice whose
#     index status is 'superseded' faults loudly.
# rc: 0 ok · 1 no value · 2 bad args · 3 fault.
#
# project_get reads <ws>/project.kv — the project adapter (its own key
# contract, deliberately NOT schema.kv-validated; see design §3). The
# slice→repo binding primitives (binding_*) live here too: they read the
# project adapter's repo declarations through the slices index.

_CONFIG_LIB_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
CONFIG_WORKFLOW_ROOT=${CONFIG_WORKFLOW_ROOT:-$(cd "$_CONFIG_LIB_DIR/../.." && pwd)}
# The operator/machine layer's home. Why this path and not the workflow or
# topic trees: the keys that live here (the notify transport, and whatever
# else proves the machine's rather than the workflow's or a topic's) are
# operator-owned and OUTLIVE topics — measured, the first delivery topic's
# notify.cmd rode its topic.kv and died with the topic tree's cleanup, and
# the pilot topic never had one at all because arming it was per-topic toil.
# It is never-committed BY CONSTRUCTION (outside every git repo), which a
# transport that may embed a webhook URL requires: defaults.kv is committed
# and topic trees are ephemeral. Standard XDG location — git's
# system→global→local shape, one layer over. Computed at source time (like
# _CONFIG_MEMO_DIR below), so an exported XDG_CONFIG_HOME — which the
# self-check sets for hermeticity — governs every resolve in the process.
_CONFIG_USER_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/delivery-workflow/config.kv"
# The store is a real dependency of this file (rule.retired_slice_id and the
# binding primitives both read the slices surface) — sourced once here rather
# than re-sourced per call inside them.
# shellcheck source=state.sh
. "$_CONFIG_LIB_DIR/state.sh"

_config_effort_rank() {
  case "$1" in
    low) echo 1 ;; medium) echo 2 ;; high) echo 3 ;; xhigh) echo 4 ;; max) echo 5 ;;
    *) echo 0 ;;
  esac
}

# All non-comment key=value lines of a kv file (last occurrence wins later).
_config_lines() { # file
  [ -f "$1" ] || return 0
  command grep -E '^[A-Za-z0-9_.*-]+=' "$1" || true
}

_config_schema_file() { printf '%s/config/schema.kv' "$CONFIG_WORKFLOW_ROOT"; }
# Constants for the content-keyed memos (validation, rules): the user-scoped
# memo directory and this file's own content sum. Computed HERE, at source
# time, and nowhere else: config_get is almost always called inside a `$(...)`,
# and a lazily-set variable in a subshell is set once per subshell — i.e. once
# per call, two processes (`id -u`, `md5sum`) on every read's path. Measured
# in a nine-stage drill walk: 0.7s of exactly that.
_CONFIG_MEMO_DIR="${TMPDIR:-/tmp}/dw-cfgv-$(id -u)"
_CONFIG_IMPL_SUM=$(md5sum "$_CONFIG_LIB_DIR/config.sh" 2>/dev/null | cut -c1-32)
# The memo dir grows by one empty marker per distinct input content. Live
# topics have stable content; the self-check's fixtures do not — several
# write a `notify.cmd=` carrying a per-run tmp path into topic.kv, so every
# suite run leaves ~12 markers behind (measured), forever. Pruned by age, one
# `find` per call, by the one caller that causes the growth (check.sh, at
# suite start); a marker older than a day has earned nothing since.
config_memo_prune() {
  [ -d "$_CONFIG_MEMO_DIR" ] && find "$_CONFIG_MEMO_DIR" -type f -mtime +1 -delete 2>/dev/null
  return 0
}

# Print the schema type spec for a key, honoring wildcard schema keys. rc 1 if
# the key is not in the closed vocabulary. One awk over the schema: an exact
# key wins outright; a wildcard key matches with each `*` standing for one
# [A-Za-z0-9_-]+ segment (the dots around it are literal).
_config_schema_type() { # key
  awk -F= -v k="$1" '
    /^[A-Za-z0-9_.*-]+=/ {
      if ($1 == k) { print substr($0, length($1) + 2); found = 1; exit }
      if (index($1, "*")) {
        re = $1; gsub(/\./, "\\.", re); gsub(/\*/, "[A-Za-z0-9_-]+", re)
        if (k ~ ("^" re "$")) { print substr($0, length($1) + 2); found = 1; exit }
      }
    }
    END { exit !found }' "$(_config_schema_file)"
}

_config_type_ok() { # value typespec
  local v=$1 t=$2
  case "$t" in
    int) printf '%s\n' "$v" | command grep -qE '^[0-9]+$' ;;
    bool) [ "$v" = "true" ] || [ "$v" = "false" ] ;;
    str|list) return 0 ;;
    "enum("*")")
      local vals=${t#enum(}; vals=${vals%)}
      printf ',%s,' "$vals" | command grep -qF ",$v," ;;
    *) return 1 ;;
  esac
}

# Validate one kv file against the schema. rc 0 clean, rc 3 fault (named).
# Validation is an invariant of the file's CONTENT, not of the lookup: the
# result is memoized per content hash (marker files, user-scoped tmp), so a
# process/subshell never re-scans an unchanged file (34 keys x schema scan
# was ~77% of every config_get; watch_wait alone made 9 such calls per
# attempt). Any edit changes the hash and re-validates; only clean results
# are memoized.
config_validate_file() { # file
  local f=$1 line key val type bad=0 memo
  [ -f "$f" ] || return 0
  # Key = EVERY input this validator reads — schema, stages.tsv (the
  # stage-membership rule), the file — plus THIS FILE's content: a cached
  # verdict is a promise of the validator that produced it, and every input
  # it read is part of that promise (the probe cache and a pre-fix stage-rule
  # replay each paid for one unbound input). Adding a validator input? It
  # goes in this key. One md5sum over the three files, their sums joined: the
  # same promise as hashing the concatenation, one process instead of two.
  # `cut | paste` looks like two processes that a shell builtin could replace,
  # and it is not: MEASURED at 400 iterations on the real three files, this
  # form runs 0.53 ms and the builtin rewrites run 1.09 ms (a `read` loop over
  # a herestring, which allocates a temp file per call) and 1.94 ms (an
  # IFS-split into an array). Both were tried here and both were REVERTED.
  # Leave it alone: on strings this shape bash is slower than the two
  # short-lived processes, and the fork count is the wrong thing to count.
  memo="$_CONFIG_MEMO_DIR/$(md5sum "$(_config_schema_file)" "$CONFIG_WORKFLOW_ROOT/config/stages.tsv" "$f" 2>/dev/null | cut -c1-32 | paste -sd. -).$_CONFIG_IMPL_SUM"
  [ -f "$memo" ] && return 0
  while IFS= read -r line; do
    key=${line%%=*}; val=${line#*=}
    if ! type=$(_config_schema_type "$key"); then
      echo "FAULT: unknown config key '$key' in $f — not in $(_config_schema_file) (closed vocabulary; fix the typo or extend the schema)" >&2
      bad=1; continue
    fi
    # The wildcard segment of stage.* keys matches ANY word — a typo'd stage
    # name (stage.imp.timeout) would pass the schema yet never be read.
    # Membership against stages.tsv column 1 closes the hole.
    case "$key" in
      stage.*.*)
        local sname=${key#stage.}; sname=${sname%%.*}
        command grep -v '^#' "$CONFIG_WORKFLOW_ROOT/config/stages.tsv" 2>/dev/null \
          | cut -f1 | command grep -qxF "$sname" || {
          echo "FAULT: config key '$key' in $f names stage '$sname' which is not a stages.tsv stage — the override would never be read" >&2
          bad=1
        } ;;
    esac
    if [ -n "$val" ] && ! _config_type_ok "$val" "$type"; then
      echo "FAULT: config key '$key' in $f has value '$val' not matching type '$type'" >&2
      bad=1
    fi
  done < <(_config_lines "$f")
  [ $bad -eq 0 ] || return 3
  mkdir -m 700 -p "$_CONFIG_MEMO_DIR" 2>/dev/null
  : > "$memo" 2>/dev/null || true
}

# Last value of key in file; rc 1 if absent.
_config_file_value() { # file key
  [ -f "$1" ] || return 1
  awk -F= -v k="$2" '/^[A-Za-z0-9_.*-]+=/ && $1==k { v=substr($0,length(k)+2); f=1 } END { if(!f) exit 1; print v }' "$1"
}

# Resolve a key over an explicit file list (least→most specific): the last
# occurrence across the files in order wins, and its file is the source. One
# awk over the present files — this is the innermost read of every
# config_get, and it used to spawn a grep and an awk per file.
_config_resolve() { # key file... -> "value<TAB>source-file"
  local key=$1; shift
  local f present=()
  for f in "$@"; do [ -f "$f" ] && present+=("$f"); done
  [ ${#present[@]} -gt 0 ] || return 1
  awk -F= -v k="$key" '/^[A-Za-z0-9_.*-]+=/ && $1==k { v=substr($0,length(k)+2); src=FILENAME; f=1 }
                       END { if(!f) exit 1; print v "\t" src }' "${present[@]}"
}

# The cross-file rules below are an invariant of their INPUTS' content — the
# three kv files and, for rule.retired_slice_id, the slices index — so a clean
# verdict is memoized per content hash exactly as config_validate_file does
# (marker files, user-scoped tmp, this file's own content in the key). Measured
# before: every config_get re-derived all of them — six resolves, three file
# scans and a checksummed store read, about 25 processes — and a nine-stage
# drill walk spent a third of its time here. Faults are never memoized.
_config_rules() { # topic_dir slice agent slice_file
  local d=$1 slice=$2 agent=$3 sf=$4
  local defaults="$CONFIG_WORKFLOW_ROOT/config/defaults.kv" topic="$d/config/topic.kv"
  local memo idx=""
  # The index is an input only when a slice override is in play (the one rule
  # that reads it is scoped to that file), and an unreadable index is not an
  # input to memoize over — the rule itself treats it as absent.
  if [ -n "$sf" ] && [ -f "$sf" ] && [ -n "$slice" ]; then
    idx=$(state_get "$d" slices 2>/dev/null || true)
  fi
  memo="$_CONFIG_MEMO_DIR/rules.$( { cat "$defaults" "$_CONFIG_USER_FILE" "$topic" ${sf:+"$sf"} 2>/dev/null; printf '%s\n' "$slice" "$agent" "$idx"; } | md5sum | cut -c1-32).$_CONFIG_IMPL_SUM"
  [ -f "$memo" ] && return 0
  _config_rules_derive "$d" "$slice" "$agent" "$sf" || return $?
  mkdir -m 700 -p "$_CONFIG_MEMO_DIR" 2>/dev/null
  : > "$memo" 2>/dev/null || true
}

_config_rules_derive() { # topic_dir slice agent slice_file
  local d=$1 slice=$2 agent=$3 sf=$4
  local defaults="$CONFIG_WORKFLOW_ROOT/config/defaults.kv" topic="$d/config/topic.kv"
  local base rev out
  out=$(_config_resolve agent.author.effort "$defaults" "$_CONFIG_USER_FILE" "$topic") || out="	"
  base=${out%%	*}
  out=$(_config_resolve agent.reviewer.effort "$defaults" "$_CONFIG_USER_FILE" "$topic") || out="	"
  rev=${out%%	*}
  # Effort is a PER-MODEL knob and this rule has no cross-model ordering to
  # ground one (the ladder is one shared vocabulary; nothing in the tree
  # declares per-model ceilings, and inventing them would assert an ordering
  # no artifact carries). So the rule compares WITHIN a model and, across
  # models, says so by name instead of silently passing — the suppressed
  # comparison must never read as a passed one (measured: the rule refused a legitimate move to a stronger model one notch below its
  # own ceiling, and symmetrically accepted the inverse in silence — blind in
  # the very direction it exists to protect). NOTE, never FAULT: rc stays 0.
  local amod rmod xmodel=0
  amod=$(_config_resolve agent.author.model "$defaults" "$_CONFIG_USER_FILE" "$topic" 2>/dev/null | cut -f1) || amod=""
  rmod=$(_config_resolve agent.reviewer.model "$defaults" "$_CONFIG_USER_FILE" "$topic" 2>/dev/null | cut -f1) || rmod=""
  [ -n "$amod" ] && [ -n "$rmod" ] && [ "$amod" != "$rmod" ] && xmodel=1
  if [ $xmodel -eq 1 ]; then
    echo "NOTE: rule.reviewer_effort_floor — author model '$amod' and reviewer model '$rmod' differ; effort ranks are not comparable across models, so this rule checks within a model only and says nothing here" >&2
  elif [ -n "$base" ] && [ -n "$rev" ] &&
     [ "$(_config_effort_rank "$rev")" -lt "$(_config_effort_rank "$base")" ]; then
    echo "FAULT: rule.reviewer_effort_floor — agent.reviewer.effort='$rev' below the run's base effort '$base' (agent.author.effort at topic level); review depth is never reducible" >&2
    return 3
  fi
  if [ -n "$sf" ] && [ -f "$sf" ]; then
    local srev srmod
    if srev=$(_config_file_value "$sf" agent.reviewer.effort); then
      srmod=$(_config_file_value "$sf" agent.reviewer.model 2>/dev/null) || srmod="$rmod"
      if [ -n "$rmod" ] && [ "$srmod" != "$rmod" ]; then
        echo "NOTE: rule.reviewer_effort_floor — $sf moves the reviewer from model '$rmod' to '$srmod'; effort ranks are not comparable across models, so this rule checks within a model only and says nothing here" >&2
      elif [ "$(_config_effort_rank "$srev")" -lt "$(_config_effort_rank "$rev")" ]; then
        echo "FAULT: rule.reviewer_effort_floor — $sf sets agent.reviewer.effort='$srev' below topic-level '$rev'; a slice override may never reduce review depth" >&2
        return 3
      fi
    fi
    # rule.retired_slice_id — needs the slices index surface (skip when the
    # store has no index yet, i.e. before split).
    if [ -n "$slice" ]; then
      local body st
      if body=$(state_get "$d" slices 2>/dev/null); then
        st=$(printf '%s\n' "$body" | awk -v id="$slice" '$0 ~ ("(^| )id=" id "( |$)"){for(i=1;i<=NF;i++) if($i ~ /^status=/){sub(/^status=/,"",$i); print $i}}' | tail -1)
        if [ "$st" = "superseded" ]; then
          echo "FAULT: rule.retired_slice_id — $sf addresses slice $slice whose index status is 'superseded' (retired ids are never reused; delete or retarget the override)" >&2
          return 3
        fi
      fi
    fi
  fi
  # rule.liveness_window — cross-field: the nudge self-heal window
  # (quiet_grace + nudge_grace) must sit UNDER the effective stage timeout,
  # and the stage timeout under hard_ceiling (defaults.kv states this
  # constraint; an accepted violation deletes the self-heal window silently —
  # the timeout fires before a nudge is ever allowed).
  local qg ng st_ hc ov k v f2
  qg=$(_config_resolve liveness.quiet_grace "$defaults" "$_CONFIG_USER_FILE" "$topic" ${sf:+"$sf"} 2>/dev/null) && qg=${qg%%	*} || qg=""
  ng=$(_config_resolve liveness.nudge_grace "$defaults" "$_CONFIG_USER_FILE" "$topic" ${sf:+"$sf"} 2>/dev/null) && ng=${ng%%	*} || ng=""
  st_=$(_config_resolve liveness.stage_timeout "$defaults" "$_CONFIG_USER_FILE" "$topic" ${sf:+"$sf"} 2>/dev/null) && st_=${st_%%	*} || st_=""
  hc=$(_config_resolve liveness.hard_ceiling "$defaults" "$_CONFIG_USER_FILE" "$topic" ${sf:+"$sf"} 2>/dev/null) && hc=${hc%%	*} || hc=""
  if [ -n "$qg" ] && [ -n "$ng" ] && [ -n "$st_" ] && [ $((qg + ng)) -ge "$st_" ]; then
    echo "FAULT: rule.liveness_window — quiet_grace($qg) + nudge_grace($ng) >= stage_timeout($st_): the nudge self-heal window can never run before the timeout kills the stage" >&2
    return 3
  fi
  if [ -n "$st_" ] && [ -n "$hc" ] && [ "$st_" -gt "$hc" ]; then
    echo "FAULT: rule.liveness_window — stage_timeout($st_) > hard_ceiling($hc): the ceiling must stay the one absolute cap" >&2
    return 3
  fi
  if [ -n "$qg" ] && [ -n "$ng" ]; then
    for f2 in "$defaults" "$_CONFIG_USER_FILE" "$topic" ${sf:+"$sf"}; do
      while IFS= read -r ov; do
        k=${ov%%=*}; v=${ov#*=}
        case "$k" in
          stage.*.timeout)
            [ -n "$v" ] || continue
            if [ $((qg + ng)) -ge "$v" ]; then
              echo "FAULT: rule.liveness_window — $k=$v in $f2 sits under quiet_grace($qg)+nudge_grace($ng): the nudge window never runs for that stage" >&2
              return 3
            fi ;;
        esac
      done < <(_config_lines "$f2")
    done
  fi
  return 0
}

config_get() { # key [--topic-dir D --slice N --agent A --with-source]
  local key=$1; shift
  local d="" slice="" agent="" with_source=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --topic-dir) d=$2; shift 2 ;;
      --slice) slice=$2; shift 2 ;;
      --agent) agent=$2; shift 2 ;;
      --with-source) with_source=1; shift ;;
      *) echo "refuse: config_get unknown arg '$1'" >&2; return 2 ;;
    esac
  done
  if ! _config_schema_type "$key" > /dev/null; then
    echo "refuse: config key '$key' is not in the closed vocabulary ($(_config_schema_file))" >&2
    return 2
  fi
  local files=("$CONFIG_WORKFLOW_ROOT/config/defaults.kv" "$_CONFIG_USER_FILE") sf=""
  if [ -n "$d" ]; then
    files+=("$d/config/topic.kv")
    if [ -n "$slice" ] && [ -n "$agent" ]; then
      sf="$d/config/slice.$slice.$agent.kv"
      files+=("$sf")
    fi
  fi
  local f
  for f in "${files[@]}"; do config_validate_file "$f" || return 3; done
  if [ -n "$d" ]; then _config_rules "$d" "$slice" "$agent" "$sf" || return 3; fi
  local out
  out=$(_config_resolve "$key" "${files[@]}") || return 1
  if [ $with_source -eq 1 ]; then printf '%s\n' "$out"
  else printf '%s\n' "${out%%	*}"; fi
}

# Project adapter accessor (<ws>/project.kv). rc 1 absent key, rc 2 no file.
# THOSE TWO RCS ARE LOAD-BEARING FOR EXACTLY ONE CALLER, named here because the
# invariant was documented only at the other end and this tree has paid for that
# before: `derive_report.sh`'s routing block switches on them, to tell "no
# project.kv at all" from "an adapter read and carrying no route=". Every other
# call site discards the status (`2>/dev/null || true`, `|| v=""`, or a boolean
# test), so collapsing the two into one rc would break nothing visible here and
# would silently put that report back to reporting a missing adapter as a silent
# one.
project_get() { # workspace key
  local f="$1/project.kv"
  if [ ! -f "$f" ]; then
    echo "refuse: $f missing — the project adapter is required; create it per design/config-and-adapters.md §3" >&2
    return 2
  fi
  _config_file_value "$f" "$2"
}

# Every repo the project adapter declares, in the FIXED global order
# code → doc. One order truth: the ferry's claims at topic start, their release
# at COMPLETE and the preflight's advisory check all iterate this — a fixed
# global order is what makes two mixed topics unable to deadlock on the pair.
project_repos() { # workspace -> one repo path per line
  local v
  v=$(project_get "$1" repo 2>/dev/null) && [ -n "$v" ] && printf '%s\n' "$v"
  v=$(project_get "$1" doc.repo 2>/dev/null) && [ -n "$v" ] && printf '%s\n' "$v"
  return 0
}

# --- slice → repo binding (design/review-and-slices.md §6) -------------------
# A slice binds to exactly ONE repo, cast at split into the slices index
# (`repo=code|doc`): code = the project repo, doc = the doc.repo declaration.
# Everything that treats a repo as EVIDENCE resolves through these — the owed
# cu→SHA ancestry, the gate attestations' sha/tree/dirty pin, the fix baseline,
# the progress registration wall. Rows without `repo=` and the topic-level 00
# pseudo-slice read as code, so a one-repo topic is unchanged in every path.
# rc: 0 answered · 3 store FAULT. An ABSENT index (before split) and a row
# without repo= are the documented code default; an UNREADABLE index is not —
# answering 'code' over a corrupt surface would send a doc slice's commits,
# ancestry and gate pins to the wrong checkout silently, which is exactly the
# fault-read-as-absent class the store contract exists to exclude.
# The ONE interpretation of a row's binding — pure, so a caller holding the
# index (slices_admissible) judges its own snapshot instead of sending every id
# back to the store. An absent row and a row without repo= both read code.
_binding_of_row() { # index-row -> code|doc
  local v
  v=$(printf '%s\n' "$1" \
      | awk '{for(i=1;i<=NF;i++) if($i ~ /^repo=/){sub(/^repo=/,"",$i); v=$i}} END{print v}')
  case "$v" in doc) echo doc ;; *) echo code ;; esac
}

binding_kind() { # workspace slice -> code|doc
  local body rc
  [ -n "${2:-}" ] || { echo code; return 0; }
  body=$(state_get "$1" slices 2>/dev/null); rc=$?
  [ $rc -eq 3 ] && { echo "FAULT: slices surface unreadable in $1 — the slice→repo binding cannot be resolved; inspect the store (never read as the code default)" >&2; return 3; }
  [ $rc -eq 0 ] || { echo code; return 0; }
  _binding_of_row "$(printf '%s\n' "$body" | command grep -E "(^| )id=$2( |$)" | tail -1)"
}

binding_repo() { # workspace slice -> the checkout this slice's evidence lives in
  local kind
  kind=$(binding_kind "$1" "$2") || return 3
  case "$kind" in
    doc) project_get "$1" doc.repo ;;
    *) project_get "$1" repo ;;
  esac
}

binding_branch() { # workspace slice -> the tip its cu SHAs must be ancestors of
  local kind
  kind=$(binding_kind "$1" "$2") || return 3
  case "$kind" in
    doc) project_get "$1" doc.branch ;;
    *) project_get "$1" branch ;;
  esac
}

# Is this declared index a legal successor of the standing one? ONE derivation
# for every way the answer can be no, asked once by each door into the index:
# record.sh's split emit (refuses — the author renumbers in session) and the
# ferry's ingest (parks — for the hand-written or rolled-back record that never
# passed emit). Same shape as owed_check, and for the same reason: a rule
# written twice drifts, and these rules decide which checkout a slice's work
# lands in — and, since after=, in which ORDER it runs. Rules, in the order a
# reader meets them:
#   grammar  — id:risk:repo:title[:after=NN(,NN)*] over closed vocabularies; an
#              EMPTY segment fails it like any other (a stray ';'), never
#              skipped past; a malformed after= tail is refused, never folded
#              into the free-text title
#   one id one slice — a doubled id writes two rows and every last-match reader
#              (binding_kind included) silently takes the second one
#   ids never revived — a superseded row stays superseded, so re-listing a
#              retired id schedules nothing at all
#   immutable binding — a standing id keeps its row, so a changed binding would
#              be dropped in silence; a row without repo= stands bound to code
#   after= backward + resolvable + immutable — every after names a STRICTLY
#              EARLIER id (id order is delivery order; backward edges only, so
#              the graph is acyclic BY CONSTRUCTION — the migration-numbering
#              discipline, no cycle walk needed) that exists in this
#              declaration or in the standing index (a typo would otherwise
#              silently satisfy, or block forever); a standing id keeps its
#              after set — OMITTING it re-lists the row unchanged (omission is
#              not a declaration), declaring a DIFFERENT set is refused (the
#              scheduler reads it; a dropped re-declaration would reorder work
#              in silence)
# Each rule is a way an author's declaration would be DROPPED rather than
# executed, and the declared fields split on exactly that: `id`, `repo` and
# `after` steer the machine, so dropping a re-declaration of any is refused
# here; `risk` and `title` are human-facing copies with no machine reader, so
# their drop is merely audited where it happens (the ferry's ingest).
# An id with no standing row is a NEW slice: nothing to conflict with.
# rc: 0 admissible · 1 not (one reason line each) · 3 store fault.
slices_admissible() { # workspace slices-field
  local ws=$1 body rc seg id decl row seen="" out="" declared="" core aft a sa
  body=$(state_get "$ws" slices 2>/dev/null); rc=$?
  [ $rc -eq 3 ] && { echo "FAULT: slices surface unreadable in $ws — the standing index cannot be compared" >&2; return 3; }
  [ $rc -eq 0 ] || body=""           # no index yet: every id is new
  while IFS= read -r seg; do        # pre-pass: an after may name an id declared LATER in the field
    [ -n "$seg" ] && declared="$declared ${seg%%:*}"
  done < <(printf '%s\n' "$2" | tr ';' '\n')
  while IFS= read -r seg; do
    aft=$(printf '%s' "$seg" | command grep -oE ':after=[0-9]{2}(,[0-9]{2})*$' || true)
    core=${seg%"$aft"}; aft=${aft#:after=}
    if [ -z "$aft" ] && printf '%s' "$seg" | command grep -q ':after='; then
      out="${out}segment '$seg' carries a malformed after= tail (shape :after=NN(,NN)* at the END, ids 2 digits) — it would otherwise fold into the title and the order would silently not exist"$'\n'
      continue
    fi
    if ! printf '%s\n' "$core" | command grep -qE '^[0-9]{2}:(low|med|high):(code|doc):.+$'; then
      out="${out}segment '$seg' is not id:risk:repo:title[:after=NN,..] (id 2 digits, risk low|med|high, repo code|doc; an EMPTY one means a stray ';')"$'\n'
      continue
    fi
    id=${core%%:*}; decl=${core#*:*:}; decl=${decl%%:*}
    # 00 is the TOPIC scope's name, not a slice id: topic stages book under
    # slice 00 (attempts round.00.*, park credits, slices/00/ artifacts), so
    # a declared 00 would be scheduled as a slice and collide with that
    # namespace in silence — its spec would even land beside the validation
    # note. Slice ids start at 01.
    if [ "$id" = "00" ]; then
      out="${out}id 00 is RESERVED for the topic scope (its stages book attempts keys and slices/00/ artifacts there) — a declared 00 would collide with that namespace silently; slice ids start at 01"$'\n'
      continue
    fi
    case " $seen " in
      *" $id "*) out="${out}id $id declared twice — one id is one slice, and the LAST row would silently decide its checkout"$'\n'
                 continue ;;
    esac
    seen="$seen $id"
    while IFS= read -r a; do
      [ -n "$a" ] || continue
      if [ "$((10#$a))" -ge "$((10#$id))" ]; then
        out="${out}id $id: after=$a is not an EARLIER id — delivery order rides the id order (backward edges only: acyclic by construction), so a forward or self reference could never resolve"$'\n'
      elif ! printf '%s\n' $declared | command grep -qxF "$a" \
           && ! printf '%s\n' "$body" | command grep -qE "(^| )id=$a( |$)"; then
        out="${out}id $id: after=$a names an id that exists nowhere (not in this declaration, not standing) — a typo here would silently satisfy, or block forever"$'\n'
      fi
    done < <(printf '%s\n' "$aft" | tr ',' '\n')
    row=$(printf '%s\n' "$body" | command grep -E "(^| )id=$id( |$)" | tail -1)
    [ -n "$row" ] || continue        # no standing row: a NEW slice
    if printf '%s\n' "$row" | command grep -qE '(^| )status=superseded( |$)'; then
      out="${out}id $id is retired (superseded) — retired ids are never revived, so re-listing one keeps the retired row and that work silently never runs; mint a new id"$'\n'
      continue
    fi
    [ "$(_binding_of_row "$row")" = "$decl" ] \
      || out="${out}id $id re-binds a standing slice (declared=$decl standing=$(_binding_of_row "$row")) — a binding is cast once per id; give the re-bound work a NEW id and omit this one (it supersedes)"$'\n'
    if [ -n "$aft" ]; then
      sa=$(printf '%s\n' "$row" | awk '{for(i=1;i<=NF;i++) if($i ~ /^after=/){sub(/^after=/,"",$i); v=$i}} END{print v}')
      [ "$aft" = "$sa" ] \
        || out="${out}id $id re-declares its after= (declared=$aft standing=${sa:-none}) — the scheduling constraint is cast once per id; omit after= to re-list the standing row unchanged, or mint a new id"$'\n'
    fi
  done < <(printf '%s\n' "$2" | tr ';' '\n')
  [ -n "$out" ] || return 0
  printf '%s' "$out"
  return 1
}

# Preflight validation of the project adapter. Load-bearing keys (repo, branch,
# commit.subject_regex) refuse when absent — the machine gates cannot run
# without them. Undeclared build/lint/test/acceptance are LEGAL (the gate
# records a named SKIP) but are named at start, never silent.
project_validate() { # workspace -> rc 0 ok / 2 refuse (self-describing)
  local ws=$1 k v bad=0 missing=""
  for k in repo branch commit.subject_regex; do
    v=$(project_get "$ws" "$k" 2>/dev/null) || v=""
    if [ -z "$v" ]; then
      echo "refuse: project.kv declares no $k= — load-bearing (repo lock / owed SHA ancestry / commit gate); declare it per design/config-and-adapters.md §3" >&2
      bad=1
    fi
  done
  [ $bad -eq 0 ] || return 2
  v=$(project_get "$ws" repo)
  [ -d "$v" ] || { echo "refuse: project.kv repo=$v is not a directory" >&2; return 2; }
  git -C "$v" rev-parse --git-dir > /dev/null 2>&1 \
    || { echo "refuse: project.kv repo=$v is not a git checkout — the pipeline is git-shaped (commit gates, SHA ancestry, the claim lock live in git)" >&2; return 2; }
  # The main branch is resolved HERE, exactly like doc.branch below, and for
  # the same reason: nothing in the workflow ever creates it (the shared-branch
  # contract — protocol §9 — is a branch that already exists, colleagues commit
  # onto it), so a typo'd name passed preflight and died mid-topic at the first
  # ancestry read, where the remedy (a relaunch with the adapter fixed) is the
  # same but the discovery costs a probe session and a watchdog. Found by a
  # cold-reader review noticing the asymmetry: doc.branch refused, branch didn't.
  local mb
  mb=$(project_get "$ws" branch)
  git -C "$v" rev-parse -q --verify "$mb^{commit}" > /dev/null 2>&1 \
    || { echo "refuse: project.kv branch='$mb' does not resolve in $v — the workflow never creates the branch; check the spelling or cut it first (owed SHA ancestry and the commit gate read it from the first slice on)" >&2; return 2; }
  # doc.repo/doc.branch are optional but PAIRED: half a declaration binds every
  # doc slice to a phantom. The doc repo is held to the same requirements as the
  # code repo — a git checkout with a resolvable tip (doc slices commit there).
  local dr db
  dr=$(project_get "$ws" doc.repo 2>/dev/null) || dr=""
  db=$(project_get "$ws" doc.branch 2>/dev/null) || db=""
  if [ -n "$dr" ] || [ -n "$db" ]; then
    [ -n "$dr" ] && [ -n "$db" ] \
      || { echo "refuse: project.kv declares only one of doc.repo=/doc.branch= — the pair IS the doc-repo declaration (design/config-and-adapters.md §3)" >&2; return 2; }
    [ -d "$dr" ] || { echo "refuse: project.kv doc.repo=$dr is not a directory" >&2; return 2; }
    git -C "$dr" rev-parse --git-dir > /dev/null 2>&1 \
      || { echo "refuse: project.kv doc.repo=$dr is not a git checkout — doc-bound slices commit there (the pipeline is git-shaped)" >&2; return 2; }
    git -C "$dr" rev-parse -q --verify "$db^{commit}" > /dev/null 2>&1 \
      || { echo "refuse: project.kv doc.branch='$db' does not resolve in $dr — doc cu SHAs cannot be checked against a phantom tip" >&2; return 2; }
    # The workspace normally LIVES inside the doc repo (plans/ is the working
    # area) — safe only while the doc repo ignores it. Unignored, every store
    # write dirties the doc tree and churns its content-bound gate/acceptance
    # pins on every attempt (the mtime-churn lesson this tree's own lock incident recorded).
    case "$ws/" in
      "$dr"/*)
        git -C "$dr" check-ignore -q "$ws" \
          || { echo "refuse: workspace $ws sits inside doc.repo=$dr but is not ignored there — every store write would dirty the doc tree and churn its content-bound pins; git-ignore the workspace's area in the doc repo" >&2; return 2; } ;;
    esac
  fi
  # coding_rules is optional, but a declared one must RESOLVE: it is the only
  # channel for the conventions no adapter key can hold. commit.subject_regex
  # carries what a regex can say about a first line; the project's length,
  # body and content rules live in that file, and the impl/fix manifests hand
  # it to the session that writes the commits. A dead pointer here is silent
  # for a whole topic — nothing else ever opens it.
  local cr crp
  cr=$(project_get "$ws" coding_rules 2>/dev/null) || cr=""
  if [ -n "$cr" ]; then
    case "$cr" in /*) crp=$cr ;; *) crp="$v/$cr" ;; esac
    [ -f "$crp" ] \
      || { echo "refuse: project.kv coding_rules=$cr does not resolve to a file under repo=$v — it is what the impl/fix sessions are handed for the conventions the machine gates cannot express; a pointer nothing can open is worse than none" >&2; return 2; }
  fi
  for k in build lint test acceptance; do
    project_get "$ws" "$k" > /dev/null 2>&1 || missing="$missing $k"
  done
  if [ -n "$missing" ]; then
    echo "project.kv: undeclared gate commands:$missing — each will record a named SKIP (honest downgrade, never silent; the independent floor loses that gate)"
  fi
  return 0
}

# The OPERATOR's entry point, and the only path in this tree that runs these
# functions as a program rather than sourcing them. Everything in
# runtime-scripts/ sources the library and calls the functions, which return
# correctly — so nothing in the machine depended on this block being right, and
# it was not.
#
# `exit $?` is LOAD-BEARING and is not decoration. This block is not at the end
# of the file: function definitions follow it (config_write_snapshot is the
# last), and a function definition SUCCEEDS — so without an explicit exit the
# script's status is that definition's 0 and every fault class read as a pass.
# Measured on a live pre-launch check: the same rule fault printed
# `FAULT: rule.reviewer_effort_floor …` on stderr and returned rc=0 here while
# the sourced `config_get` returned 3, and the operator read the silence plus
# exit 0 as "this config is legal" for a config the next preflight would have
# exit-3'd. `20-config`'s wrapper-rc arms hold every branch of this from
# outside, in a subshell, because no other check exercises the wrapper at all.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  set -uo pipefail
  export LC_ALL=C
  case "${1:-}" in
    get) shift; config_get "$@" ;;
    project) shift; project_get "$@" ;;
    validate) shift; config_validate_file "$@" ;;
    *) echo "usage: config.sh get <key> [--topic-dir D --slice N --agent A --with-source]" >&2
       echo "       config.sh project <workspace> <key>" >&2
       echo "       config.sh validate <file>" >&2
       exit 2 ;;
  esac
  exit $?
fi

# The snapshot handed to every author and reviewer through the spec/precheck
# manifests, titled "resolved config snapshot — effective caps/budgets with
# layers": the SAME two layers resolved above, in the same order, materialised
# as one file. It lives here so the concatenation cannot drift from the
# resolution rule it claims to show. (The slice layer is deliberately absent —
# it is per-slice, and the snapshot is one file for the whole topic.)
#
# The CALLER decides when. It must be every launch: this used to be written
# inside ferry.sh's run-surface-absent branch, taken once per topic ever, and
# a live topic could then never refresh it. Measured on a
# live topic — one `run_init` row against four relaunches, eight
# lines false against the config they claim to resolve.
config_write_snapshot() { # workflow-root ws -> path on stdout
  local snap="$2/.runtime/config.snapshot.kv"
  # Self-sufficient: the one caller happens to mkdir the runtime tree first,
  # and a helper that returns a path is not entitled to assume its caller did.
  mkdir -p "$(dirname "$snap")" 2>/dev/null || true
  # The file SAYS which layers it carries. Its manifest title calls it the
  # "effective" config, and it can only ever hold the three TOPIC-wide layers —
  # the fourth is per (slice, agent) and there is no single file for it. A
  # reader who needs a slice override has to be told that here, in the artifact
  # that travels, rather than trusting a title. Same failure the staleness had:
  # a label a reader has no reason to doubt. The operator layer's presence is
  # marked either way — "not in the body" and "empty file" must not read alike.
  { echo "# resolved config snapshot — written at every launch, by the ferry."
    echo "# LAYERS PRESENT: config/defaults.kv, then the operator config"
    echo "#                 ${_CONFIG_USER_FILE} (if present), then"
    echo "#                 <ws>/config/topic.kv (if present). Later wins."
    echo "# LAYER ABSENT:   <ws>/config/slice.<nn>.<agent>.kv — per slice and agent,"
    echo "#                 so no one topic-wide file can carry it. If a slice"
    echo "#                 override exists, the value below is not yours."
    cat "$1/config/defaults.kv"; echo
    if [ -f "$_CONFIG_USER_FILE" ]; then
      cat "$_CONFIG_USER_FILE"; echo
    else
      echo "# (operator config absent: $_CONFIG_USER_FILE)"
    fi
    [ -f "$2/config/topic.kv" ] && cat "$2/config/topic.kv"
  } > "$snap" 2>/dev/null || true
  printf '%s\n' "$snap"
}
