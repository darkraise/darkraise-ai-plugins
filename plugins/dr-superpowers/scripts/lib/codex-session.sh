# Codex session state: one file per Claude Code session, written by
# scripts/codex-gate and marked off by a runner that hits the quota.
#
# The file is keyed by session id rather than kept in the project: skills run
# these scripts from the plugin root, which for an installed plugin is not the
# project, and a quota is account-wide anyway. Readers fail closed - any state
# that is not a positive answer for this session is off.
#
# Source this file; it defines functions only.

codex_session_id() { printf '%s' "${CLAUDE_CODE_SESSION_ID:-}"; }

codex_session_dir() { printf '%s' "${DR_CODEX_SESSION_DIR:-$HOME/.claude/dr-superpowers/codex-sessions}"; }

# codex_session_file - this session's file; fails when there is no session id.
codex_session_file() {
  local sid; sid=$(codex_session_id)
  [ -n "$sid" ] || return 1
  printf '%s/%s.json' "$(codex_session_dir)" "$sid"
}

# codex_session_on <review|lane> - succeeds only when this session's gate said
# that surface may use Codex.
codex_session_on() {
  local f; f=$(codex_session_file) || return 1
  [ "$(jq -r --arg s "$1" '.[$s] == true' "$f" 2>/dev/null | tr -d '\r')" = true ]
}

# codex_session_write <json> - replace this session's file in one rename, so a
# concurrent reader never sees half a file, and prune week-old sessions.
codex_session_write() {
  local f dir; f=$(codex_session_file) || return 0
  dir=$(codex_session_dir)
  mkdir -p "$dir" 2>/dev/null || return 0
  printf '%s\n' "$1" > "$f.tmp.$$" && mv -f "$f.tmp.$$" "$f"
  find "$dir" -maxdepth 1 -name '*.json' -mtime +7 -delete 2>/dev/null || true
}

# codex_session_mark_off <reason> - Codex is unusable for the rest of this
# session: no reset time, so the gate's cache keeps the answer.
codex_session_mark_off() {
  local f prior; f=$(codex_session_file) || return 0
  prior=$(cat "$f" 2>/dev/null) || prior='{}'
  codex_session_write "$(jq -c --arg sid "$(codex_session_id)" --arg r "$1" \
    --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{session_id: $sid, usable: false, review: false, lane: false, reason: $r, checked_at: $at,
      resets_at: null, resets_at_epoch: null, plugin_version: (.plugin_version // null)}' \
    <<<"$prior" 2>/dev/null)"
}
