# Per-executor session state: one file per Claude Code session per executor,
# written by that executor's gate and marked off by a runner that hits a
# quota or a rate limit.
#
# The file is keyed by session id rather than kept in the project: a quota is
# account-wide, so the answer belongs to the session, not to any one project
# the session works in. Readers fail closed - any state that is not a positive
# answer for this session is off.
#
# Every function takes the executor id first. One shared file would mean one
# executor's mark-off closing another's surfaces, and review-route and
# plan-lint both read these files.
#
# Source this file; it defines functions only.

_EXECUTOR_SESSION_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# The helper's stderr is not swallowed: a malformed registry entry is an
# installation fault, and silencing it turns the lane off with no diagnostic.
_executor_session_field() { # _executor_session_field <id> <key>
  bash "$_EXECUTOR_SESSION_LIB_DIR/../executors" get "$1" "$2"
}

executor_session_id() { printf '%s' "${CLAUDE_CODE_SESSION_ID:-}"; }

# The override variable is named by the registry, so an executor keeps whatever
# name its callers already export - DR_CODEX_SESSION_DIR, for Codex.
executor_session_dir() { # executor_session_dir <id>
  local env_name override dir
  env_name=$(_executor_session_field "$1" session_dir_env)
  if [ -n "$env_name" ]; then
    override=${!env_name:-}
    [ -z "$override" ] || { printf '%s' "$override"; return 0; }
  fi
  dir=$(_executor_session_field "$1" session_dir)
  [ -n "$dir" ] || return 1
  printf '%s/.claude/dr-superpowers/%s' "$HOME" "$dir"
}

# executor_session_file <id> - this session's file; fails with no session id.
executor_session_file() {
  local sid dir; sid=$(executor_session_id)
  [ -n "$sid" ] || return 1
  dir=$(executor_session_dir "$1") || return 1
  printf '%s/%s.json' "$dir" "$sid"
}

# executor_session_on <id> <surface> - succeeds only when this session's gate
# said that surface may be used.
executor_session_on() {
  local f; f=$(executor_session_file "$1") || return 1
  [ "$(jq -r --arg s "$2" '.[$s] == true' "$f" 2>/dev/null | tr -d '\r')" = true ]
}

# executor_session_write <id> <json> - replace this session's file in one
# rename, so a concurrent reader never sees half a file, and prune week-old
# sessions for this executor only.
executor_session_write() {
  local f dir; f=$(executor_session_file "$1") || return 0
  dir=$(executor_session_dir "$1") || return 0
  mkdir -p "$dir" 2>/dev/null || return 0
  printf '%s\n' "$2" > "$f.tmp.$$" && mv -f "$f.tmp.$$" "$f"
  find "$dir" -maxdepth 1 -name '*.json' -mtime +7 -delete 2>/dev/null || true
}

# executor_session_mark_off <id> <reason> - this executor is unusable for the
# rest of the session: no reset time, so the gate's cache keeps the answer.
#
# Every surface the registry lists is cleared, and the metadata fields the
# gate reads back out of the cache are written: reason, checked_at, both
# resets_at fields, and whatever plugin_version the prior file carried.
executor_session_mark_off() {
  local f prior surfaces; f=$(executor_session_file "$1") || return 0
  # Parsed, not cat: an empty or torn file would make the jq below produce
  # nothing, and the empty file that writes reads back as a cache miss, so the
  # next gate call re-probes and can turn the executor on again.
  prior=$(jq -c . "$f" 2>/dev/null) || prior=''
  [ -n "$prior" ] || prior='{}'
  surfaces=$(_executor_session_field "$1" surfaces | jq -R . | jq -sc .)
  [ -n "$surfaces" ] || surfaces='[]'
  executor_session_write "$1" "$(jq -c \
    --arg sid "$(executor_session_id)" --arg r "$2" \
    --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --argjson surfaces "$surfaces" '
    {session_id: $sid, usable: false, reason: $r, checked_at: $at,
     resets_at: null, resets_at_epoch: null,
     plugin_version: (.plugin_version // null)}
    + (reduce $surfaces[] as $s ({}; . + {($s): false}))' <<<"$prior" 2>/dev/null)"
}
