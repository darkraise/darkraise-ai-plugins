# Per-executor session state: one file per Claude Code session per executor,
# written by that executor's gate and marked off by a runner that hits a
# quota or a rate limit.
#
# The file is keyed by session id rather than kept in the project: a quota
# belongs to the account, not to any one project, so the answer belongs to the
# session. For agy, Claude and Gemini models are limited separately, which is
# why the file carries a separate `fallback` mark. Readers fail closed - any
# state that is not a positive answer for this session is off.
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
  printf '%s/.claude/dforge/%s' "$HOME" "$dir"
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

# _executor_session_prior <file> - the file's one JSON object, compact, or {}.
# An empty, torn or multi-object file reads as {}: echoed as is, it would make
# the caller's jq produce nothing or several records, and an empty file reads
# back as a cache miss, so the next gate call re-probes and can turn the
# executor on again.
_executor_session_prior() {
  local prior
  prior=$(jq -cs 'if length == 1 and (.[0] | type) == "object" then .[0] else {} end' 2>/dev/null < "$1") \
    || prior='{}'
  [ -n "$prior" ] || prior='{}'
  printf '%s' "$prior"
}

# executor_session_write <id> <json> - replace this session's file in one
# rename, so a concurrent reader never sees half a file, and prune week-old
# sessions for this executor only.
#
# A <json> without a `fallback` key carries the prior file's fallback object
# over, so a gate or lane write never clears a fallback mark; `"fallback": null`
# drops it. A <json> that does not parse is written as given.
#
# Without a session id there is nothing to write, which succeeds; any other
# write that leaves no file fails, so a runner never reports a mark it lost.
executor_session_write() {
  local f dir prior json
  [ -n "$(executor_session_id)" ] || return 0
  f=$(executor_session_file "$1") || return 1
  dir=$(executor_session_dir "$1") || return 1
  mkdir -p "$dir" 2>/dev/null || return 1
  prior=$(_executor_session_prior "$f")
  json=$(jq -c --argjson prior "$prior" '
    if type != "object" then .
    elif has("fallback") then (if .fallback == null then del(.fallback) else . end)
    elif ($prior.fallback | type) == "object" then . + {fallback: $prior.fallback}
    else . end' <<<"$2" 2>/dev/null) || json=$2
  [ -n "$json" ] || json=$2
  printf '%s\n' "$json" > "$f.tmp.$$" && mv -f "$f.tmp.$$" "$f" \
    || { rm -f "$f.tmp.$$" 2>/dev/null; return 1; }
  find "$dir" -maxdepth 1 -name '*.json' -mtime +7 -delete 2>/dev/null || true
}

# executor_session_iso <epoch> - the epoch in ISO 8601 UTC; prints nothing
# when neither GNU nor BSD date can convert it.
executor_session_iso() {
  { date -u -d "@$1" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
    || date -u -r "$1" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null; } | tr -d '\r'
}

# executor_session_mark_off <id> <reason> [<epoch>] - this executor is
# unusable until <epoch>, the reset time the caller read from the error. The
# reset is the caller's to supply: without one the mark lasts the session,
# because the gate's cache keeps the answer.
#
# Every surface the registry lists is cleared, and the metadata fields the
# gate reads back out of the cache are written: reason, checked_at, both
# resets_at fields, plugin_version (null when the prior file had none), and
# every other `*_version` field the prior file carried, such as agy_version.
# An <epoch> of more than 18 digits is no reset: the gate could not compare it.
#
# Both mark functions fail when the mark was not written, and succeed without
# writing when there is no session id, as executor_session_write does.
executor_session_mark_off() {
  local f prior surfaces record epoch=${3:-} iso=''
  [ -n "$(executor_session_id)" ] || return 0
  f=$(executor_session_file "$1") || return 1
  if [[ $epoch =~ ^[0-9]{1,18}$ ]]; then iso=$(executor_session_iso "$epoch"); else epoch=''; fi
  prior=$(_executor_session_prior "$f")
  surfaces=$(_executor_session_field "$1" surfaces | jq -R . | jq -sc .)
  [ -n "$surfaces" ] || surfaces='[]'
  record=$(jq -c \
    --arg sid "$(executor_session_id)" --arg r "$2" \
    --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --argjson surfaces "$surfaces" \
    --arg epoch "$epoch" --arg iso "$iso" '
    {session_id: $sid, usable: false, reason: $r, checked_at: $at,
     resets_at: (if $iso == "" then null else $iso end),
     resets_at_epoch: (if $epoch == "" then null else ($epoch | tonumber) end),
     plugin_version: (.plugin_version // null)}
    + with_entries(select(.key | endswith("_version")))
    + (reduce $surfaces[] as $s ({}; . + {($s): false}))' <<<"$prior" 2>/dev/null) || return 1
  [ -n "$record" ] || return 1
  executor_session_write "$1" "$record"
}

# executor_session_mark_fallback_off <id> [<epoch>] - only the Claude fallback
# is out of quota, until <epoch> or, without one, for the session. It marks the
# fallback alone and leaves usable, lane and reason as the gate wrote them.
executor_session_mark_fallback_off() {
  local f prior record epoch=${2:-} iso=''
  [ -n "$(executor_session_id)" ] || return 0
  f=$(executor_session_file "$1") || return 1
  if [[ $epoch =~ ^[0-9]{1,18}$ ]]; then iso=$(executor_session_iso "$epoch"); else epoch=''; fi
  prior=$(_executor_session_prior "$f")
  record=$(jq -c \
    --arg sid "$(executor_session_id)" --arg epoch "$epoch" --arg iso "$iso" '
    . + {session_id: $sid,
         fallback: {usable: false, reason: "quota",
                    resets_at: (if $iso == "" then null else $iso end),
                    resets_at_epoch: (if $epoch == "" then null else ($epoch | tonumber) end)}}' \
    <<<"$prior" 2>/dev/null) || return 1
  [ -n "$record" ] || return 1
  executor_session_write "$1" "$record"
}
