#!/usr/bin/env bash
# SessionStart hook: inject the using-dforge entry point, record the session
# of this checkout for darkmem's push, and run darkmem's reconcile and pull.
# Injection must survive a missing jq or malformed stdin; the record is allowed
# to degrade.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/lib/roots.sh"

stdin_json="$(cat 2>/dev/null || true)"
cwd=""

if command -v jq >/dev/null 2>&1 && [ -n "$stdin_json" ] \
   && jq -e . >/dev/null 2>&1 <<<"$stdin_json"; then
  session_id=$(jq -r '.session_id // empty' <<<"$stdin_json")
  transcript_path=$(jq -r '.transcript_path // empty' <<<"$stdin_json")
  cwd=$(jq -r '.cwd // empty' <<<"$stdin_json")
  source_event=$(jq -r '.source // empty' <<<"$stdin_json")
  # The record lives under $HOME; with HOME empty its path would start at
  # /.claude, so nothing is persisted.
  if [ -n "${HOME:-}" ] && [ -n "$transcript_path" ] && [ -n "$cwd" ]; then
    sessions_dir="${HOME:-}/.claude/dforge/sessions"
    key=$(printf '%s' "$cwd" | tr -c 'A-Za-z0-9' '-')
    # Git Bash rewrites POSIX-looking values passed as native-binary arguments;
    # every --arg here is opaque data, so suppress the conversion.
    record=$(MSYS_NO_PATHCONV=1 jq -n --arg sid "$session_id" --arg tp "$transcript_path" \
            --arg cwd "$cwd" --arg src "$source_event" \
            --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
            '{session_id:$sid,transcript_path:$tp,cwd:$cwd,source:$src,timestamp:$ts}' 2>/dev/null)
    if [ -n "$record" ] && mkdir -p "$sessions_dir" 2>/dev/null; then
      printf '%s\n' "$record" > "${sessions_dir}/${key}.json" 2>/dev/null || true
      # Every session start rewrites its own record, so one untouched for a
      # month belongs to a checkout that is gone. The sweep reaches one level
      # down, where earlier versions kept per-session files.
      find "$sessions_dir" -maxdepth 2 -type f -mtime +30 -delete 2>/dev/null || true
    fi
  fi
fi

content="$(cat "${PLUGIN_ROOT}/skills/using-dforge/SKILL.md" 2>/dev/null || true)"
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
# Skills call scripts by the plugin-root path with the working directory inside
# the project; this line is where the root is named.
plugin_root_shown=$PLUGIN_ROOT
if command -v cygpath >/dev/null 2>&1; then plugin_root_shown=$(cygpath -m "$PLUGIN_ROOT" 2>/dev/null || printf '%s' "$PLUGIN_ROOT"); fi
context="<EXTREMELY_IMPORTANT>\nYou have dforge.\n\n**Below is the full content of your 'dforge:using-dforge' skill - your introduction to using skills. For all other skills, use the 'Skill' tool:**\n\n${escaped}\n\nPlugin root: $(escape_for_json "$plugin_root_shown") — call scripts by this path, with the working directory inside the project\n</EXTREMELY_IMPORTANT>"

repo_root=$(git -C "${cwd:-$PWD}" rev-parse --show-toplevel 2>/dev/null || true)
[ -z "$repo_root" ] || dforge_state_ignore "$repo_root"

# dforge reads none of the older names, so a repository that still has them
# would split its work between the old directories and the new ones unnoticed.
legacy_line=""
if [ -n "$repo_root" ]; then
  legacy=$(dforge_legacy_layout "$repo_root" | paste -sd, - | sed 's/,/, /g' | tr -d '\001-\037')
  if [ -n "$legacy" ]; then
    legacy_line="dforge: this repository still uses an older layout ($legacy); run the dforge:migrate skill (/dforge:migrate)"
    context="${context}\n\n$(escape_for_json "$legacy_line")"
  fi
fi

# darkmem's reconcile and pull (darkmem store options spec §5), on every
# source: a line per moved or refused family and the pull's result, fitted to
# the room the hook's 10,000-character cap leaves the entry point. Under 100
# characters of room the closing line alone would not fit, so the sync still
# runs but prints nothing. The sync gets what is left of the hook's 300-second
# timeout less 30 seconds for the reply, since a killed hook injects nothing.
darkmem_lines=""
if . "${SCRIPT_DIR}/lib/darkmem-hook.sh" 2>/dev/null; then
  room=$(( 9500 - ${#content} - 400 - ${#legacy_line} ))
  if [ "$room" -ge 100 ]; then
    darkmem_lines=$(darkmem_session_lines "${cwd:-$PWD}" "${session_id:-}" "$room" $(( 270 - SECONDS )) \
      | tr -d '\001-\010\013\014\016-\037')
  else
    darkmem_session_lines "${cwd:-$PWD}" "${session_id:-}" 0 $(( 270 - SECONDS )) >/dev/null
  fi
  if [ -n "$darkmem_lines" ]; then
    context="${context}\n\n$(escape_for_json "$darkmem_lines")"
  fi
fi

printf '{\n  "hookSpecificOutput": {\n    "hookEventName": "SessionStart",\n    "additionalContext": "%s"\n  }\n}\n' "$context"
exit 0
