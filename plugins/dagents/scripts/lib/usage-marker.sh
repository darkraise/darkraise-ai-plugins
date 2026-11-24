# shellcheck shell=bash
# Task markers for usage reports: one row per task open and close in the
# primary checkout's <state>/sdd/usage-markers.tsv, which a usage report slices
# transcripts by. Sourced after context.sh. A mark never prints and never
# fails its caller: a budget line or a ledger write matters more than a marker.
#
# Row, tab-separated: time event plugin version root plan task session
# transcript bytes context caller range deferred.

UM_PLUGIN=dagents
UM_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)

# A tab or line break inside a value would shift every later column.
_um_field() { printf '%s' "$1" | tr '\t\r\n' '   '; }

# _um_plan_rel PLAN_FILE — the plan's path relative to the checkout's top
# level, the form the ledger's identity line uses.
_um_plan_rel() {
  local f=$1 top dir
  top=$(git rev-parse --show-toplevel 2>/dev/null) && top=$(cd "$top" 2>/dev/null && pwd -P) \
    && dir=$(cd "$(dirname "$f")" 2>/dev/null && pwd -P) || { printf '%s' "$f"; return 0; }
  case "$dir/" in
    "$top"/*) f="$dir/$(basename "$f")"; printf '%s' "${f#"$top"/}" ;;
    *) printf '%s' "$f" ;;
  esac
}

# _um_append FILE ROW — runs under the file's lock. An open is written once
# per session and never after the task's close; a close is written once.
_um_append() {
  if [ -f "$1" ] && awk -F'\t' '
      { sub(/\r$/, "") }
      $6 == ENVIRON["UM_PLAN"] && $7 == ENVIRON["UM_TASK"] \
        && ($2 == "close" || (ENVIRON["UM_EVENT"] == "open" && $2 == "open" && $8 == ENVIRON["UM_SID"])) { found = 1; exit }
      END { exit !found }' "$1"; then
    return 0
  fi
  printf '%s\n' "$2" >> "$1"
}

# um_mark EVENT PLAN_FILE N CONTEXT CALLER [RANGE DEFERRED]
um_mark() {
  (
    case ${1:-} in open|close) ;; *) exit 0 ;; esac
    [[ ${3:-} =~ ^[0-9]+$ ]] && [ -n "${2:-}" ] || exit 0
    primary=$(ctx_primary_root) || exit 0
    base="$(dagents_dir state "$primary")/sdd"
    mkdir -p "$base" || exit 0
    dagents_self_ignore "$base"
    transcript=${CTX_TRANSCRIPT:-}
    if [ -z "$transcript" ] && ctx_find_transcript; then transcript=$CTX_TRANSCRIPT; fi
    bytes=""
    [ -z "$transcript" ] || bytes=$(wc -c < "$transcript" | tr -d ' ')
    sid=${CLAUDE_CODE_SESSION_ID:-}
    [ -n "$sid" ] || [ -z "$transcript" ] || sid=$(basename "$transcript" .jsonl)
    version=$(ctx_jq -r '.version // empty' < "$UM_ROOT/.claude-plugin/plugin.json" | tr -d '\r')
    UM_EVENT=$1 UM_PLAN=$(_um_field "$(_um_plan_rel "$2")") UM_TASK=$3 UM_SID=$(_um_field "$sid")
    export UM_EVENT UM_PLAN UM_TASK UM_SID
    row="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    for v in "$1" "$UM_PLUGIN" "$version" "$UM_ROOT" "$UM_PLAN" "$3" "$UM_SID" "$transcript" "$bytes" \
      "${4:-}" "${5:-}"; do
      row+=$'\t'$(_um_field "$v")
    done
    if [ "$1" = close ]; then row+=$'\t'$(_um_field "${6:-}")$'\t'$(_um_field "${7:-}"); else row+=$'\t\t'; fi
    dr_locked "$base/usage-markers.tsv" _um_append "$base/usage-markers.tsv" "$row"
  ) >/dev/null 2>&1
  return 0
}

# um_mark_request CONTEXT — the marks a caller asked for in the environment:
# USAGE_MARK (open|close), USAGE_MARK_PLAN, USAGE_MARK_TASKS (space-separated),
# USAGE_MARK_CALLER, USAGE_MARK_RANGE, USAGE_MARK_DEFERRED.
um_mark_request() {
  [ -n "${USAGE_MARK:-}" ] || return 0
  local t
  for t in ${USAGE_MARK_TASKS:-}; do
    um_mark "$USAGE_MARK" "${USAGE_MARK_PLAN:-}" "$t" "${1:-}" "${USAGE_MARK_CALLER:-}" \
      "${USAGE_MARK_RANGE:-}" "${USAGE_MARK_DEFERRED:-}"
  done
  return 0
}
