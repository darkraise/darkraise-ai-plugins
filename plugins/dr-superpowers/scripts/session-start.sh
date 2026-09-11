#!/usr/bin/env bash
# SessionStart hook: inject the using-superpowers entry point, persist the
# session's transcript path for the budget tooling, and on the compact source
# append the compaction snapshot (scripts/lib/snapshot.sh). Injection must
# survive a missing jq or malformed stdin; persistence and the snapshot's
# transcript sections are allowed to degrade.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

stdin_json="$(cat 2>/dev/null || true)"
transcript_path="" cwd=""

if command -v jq >/dev/null 2>&1 && [ -n "$stdin_json" ] \
   && jq -e . >/dev/null 2>&1 <<<"$stdin_json"; then
  session_id=$(jq -r '.session_id // empty' <<<"$stdin_json")
  transcript_path=$(jq -r '.transcript_path // empty' <<<"$stdin_json")
  cwd=$(jq -r '.cwd // empty' <<<"$stdin_json")
  source_event=$(jq -r '.source // empty' <<<"$stdin_json")
  if [ -n "$transcript_path" ] && [ -n "$cwd" ]; then
    sessions_dir="${HOME:-}/.claude/dr-superpowers/sessions"
    key=$(printf '%s' "$cwd" | tr -c 'A-Za-z0-9' '-')
    # Git Bash rewrites POSIX-looking values passed as native-binary arguments;
    # every --arg here is opaque data, so suppress the conversion.
    mkdir -p "$sessions_dir" 2>/dev/null \
      && MSYS_NO_PATHCONV=1 jq -n --arg sid "$session_id" --arg tp "$transcript_path" \
            --arg cwd "$cwd" --arg src "$source_event" \
            --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
            '{session_id:$sid,transcript_path:$tp,cwd:$cwd,source:$src,timestamp:$ts}' \
            > "${sessions_dir}/${key}.json" 2>/dev/null || true
  fi
fi

content="$(cat "${PLUGIN_ROOT}/skills/using-superpowers/SKILL.md" 2>/dev/null || true)"
[ -n "$content" ] || exit 0

# Escape for JSON embedding with bash parameter substitution (single C-level
# pass per character class; no jq dependency on the injection path).
escape_for_json() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\t'/\\t}"
  printf '%s' "$s"
}

escaped=$(escape_for_json "$content")
context="<EXTREMELY_IMPORTANT>\nYou have dr-superpowers.\n\n**Below is the full content of your 'dr-superpowers:using-superpowers' skill - your introduction to using skills. For all other skills, use the 'Skill' tool:**\n\n${escaped}\n</EXTREMELY_IMPORTANT>"

# The compact source is detected without jq, so a machine without jq still
# gets the handoff and ledger sections. Hook output over 10,000 characters is
# replaced by a file reference, so the snapshot gets only the room the entry
# point leaves, with headroom for the wrapper text.
if grep -qE '"source"[[:space:]]*:[[:space:]]*"compact"' <<<"$stdin_json" \
   && . "${SCRIPT_DIR}/lib/snapshot.sh" 2>/dev/null; then
  cap=$(( 9500 - ${#content} - 400 ))
  [ "$cap" -le "$SNAPSHOT_CAP" ] || cap=$SNAPSHOT_CAP
  if [ "$cap" -gt 1000 ]; then
    # Transcript text can carry raw C0 controls (pasted terminal output with
    # ANSI codes); JSON forbids them unescaped and escape_for_json only covers
    # the newline, carriage return and tab it re-encodes.
    snapshot=$(snapshot_build "$transcript_path" "${cwd:-$PWD}" "$cap" 2>/dev/null \
      | tr -d '\001-\010\013\014\016-\037' || true)
    if [ -n "$snapshot" ]; then
      context="${context}\n\n$(escape_for_json "$snapshot")"
    fi
  fi
fi

printf '{\n  "hookSpecificOutput": {\n    "hookEventName": "SessionStart",\n    "additionalContext": "%s"\n  }\n}\n' "$context"
exit 0
