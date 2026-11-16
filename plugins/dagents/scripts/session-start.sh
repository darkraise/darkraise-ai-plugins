#!/usr/bin/env bash
# SessionStart hook: inject the using-dforge entry point, persist the
# session's transcript path for the budget tooling, and on the compact source
# append the compaction snapshot (scripts/lib/snapshot.sh). Injection must
# survive a missing jq or malformed stdin; persistence and the snapshot's
# transcript sections are allowed to degrade.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/lib/roots.sh"

stdin_json="$(cat 2>/dev/null || true)"
transcript_path="" cwd=""

if command -v jq >/dev/null 2>&1 && [ -n "$stdin_json" ] \
   && jq -e . >/dev/null 2>&1 <<<"$stdin_json"; then
  session_id=$(jq -r '.session_id // empty' <<<"$stdin_json")
  transcript_path=$(jq -r '.transcript_path // empty' <<<"$stdin_json")
  cwd=$(jq -r '.cwd // empty' <<<"$stdin_json")
  source_event=$(jq -r '.source // empty' <<<"$stdin_json")
  # Every record below lives under $HOME; with HOME empty its paths would start
  # at /.claude, so nothing is persisted.
  if [ -n "${HOME:-}" ] && [ -n "$transcript_path" ] && [ -n "$cwd" ]; then
    sessions_dir="${HOME:-}/.claude/dforge/sessions"
    key=$(printf '%s' "$cwd" | tr -c 'A-Za-z0-9' '-')
    # Git Bash rewrites POSIX-looking values passed as native-binary arguments;
    # every --arg here is opaque data, so suppress the conversion.
    record=$(MSYS_NO_PATHCONV=1 jq -n --arg sid "$session_id" --arg tp "$transcript_path" \
            --arg cwd "$cwd" --arg src "$source_event" \
            --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
            '{session_id:$sid,transcript_path:$tp,cwd:$cwd,source:$src,timestamp:$ts}' 2>/dev/null)
    # Two sessions in one checkout share the cwd record, last writer wins, so
    # each session also gets a record of its own under by-id/, which
    # scripts/lib/context.sh prefers. The cwd record stays as the fallback.
    if [ -n "$record" ] && mkdir -p "$sessions_dir" 2>/dev/null; then
      printf '%s\n' "$record" > "${sessions_dir}/${key}.json" 2>/dev/null || true
      if [ -n "$session_id" ] && mkdir -p "$sessions_dir/by-id" 2>/dev/null; then
        printf '%s\n' "$record" \
          > "$sessions_dir/by-id/$(printf '%s' "$session_id" | tr -c 'A-Za-z0-9' '-').json" 2>/dev/null || true
      fi
      # Every session start rewrites its own records, so one untouched for a
      # month belongs to a session or a checkout that is gone.
      find "$sessions_dir" "$sessions_dir/by-id" -maxdepth 1 -type f -name '*.json' -mtime +30 -delete 2>/dev/null || true
    fi
  fi
  # The cockpit writes its heartbeat here (scripts/lib/auto-run.sh
  # ar_beat_file) with $.fs.write, which need not create a directory, so a
  # start that records no session makes it too.
  if [ -n "${HOME:-}" ]; then
    cockpit_dir="$HOME/.claude/dforge/sessions/cockpit"
    mkdir -p "$cockpit_dir" 2>/dev/null || true
    find "$cockpit_dir" -maxdepth 1 -type f -mtime +30 -delete 2>/dev/null || true
  fi
  # Background work dies with the process, so a launch made before a startup or
  # resume never sends its notification. scripts/turn-end.sh counts only the
  # launches after this time as running.
  case "$source_event" in
    startup | resume)
      if [ -n "${HOME:-}" ] && [ -n "$session_id" ] && mkdir -p "${HOME:-}/.claude/dforge/sessions/turns" 2>/dev/null; then
        date -u +%Y-%m-%dT%H:%M:%S.000Z \
          > "${HOME:-}/.claude/dforge/sessions/turns/$(printf '%s' "$session_id" | tr -c 'A-Za-z0-9' '-').since" 2>/dev/null || true
      fi
      ;;
  esac
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

# A greenfield project's position: one line computed from its roadmap, so a
# fresh or compacted session never has to remember which milestone it is in or
# which epic is still open. Anything that fails here injects nothing extra.
roadmap_line=""
roadmap_root=$(git -C "${cwd:-$PWD}" rev-parse --show-toplevel 2>/dev/null || true)
[ -z "$roadmap_root" ] || dforge_state_ignore "$roadmap_root"
if [ -n "$roadmap_root" ] && [ -f "$(dforge_docs_root "$roadmap_root")/roadmap.md" ]; then
  roadmap_line=$(bash "${SCRIPT_DIR}/roadmap" status --root "$roadmap_root" --line 2>/dev/null \
    | head -n 1 | tr -d '\001-\010\013\014\016-\037' || true)
  if [ -n "$roadmap_line" ]; then
    context="${context}\n\n$(escape_for_json "$roadmap_line")"
  fi
fi

# The workflow settings that differ from their defaults, as one line the skills
# read where they would otherwise ask (scripts/dforge-config workflow). Without
# Node, or with a settings file that cannot be read, nothing is added.
settings_line=$(bash "${SCRIPT_DIR}/dforge-config" workflow 2>/dev/null \
  | head -n 1 | tr -d '\001-\010\013\014\016-\037\r' || true)
if [ -n "$settings_line" ]; then
  context="${context}\n\n$(escape_for_json "$settings_line")"
fi

# dforge reads none of the older names, so a repository that still has them
# would split its work between the old directories and the new ones unnoticed.
legacy_line=""
if [ -n "$roadmap_root" ]; then
  legacy=$(dforge_legacy_layout "$roadmap_root" | paste -sd, - | sed 's/,/, /g' | tr -d '\001-\037')
  if [ -n "$legacy" ]; then
    legacy_line="dforge: this repository still uses an older layout ($legacy); run the dforge:migrate skill (/dforge:migrate)"
    context="${context}\n\n$(escape_for_json "$legacy_line")"
  fi
fi

# darkmem's reconcile and pull (darkmem store options spec §5), on every
# source: a line per moved or refused family and the pull's result, fitted to
# the room the hook's 10,000-character cap leaves the entry point. A
# compaction's snapshot gets what remains after them. Under 100 characters of
# room the closing line alone would not fit, so the sync still runs but prints
# nothing. The sync gets what is left of the hook's 300-second timeout less 30
# seconds for the snapshot and the reply, since a killed hook injects nothing.
darkmem_lines=""
if . "${SCRIPT_DIR}/lib/darkmem-hook.sh" 2>/dev/null; then
  room=$(( 9500 - ${#content} - 400 - ${#roadmap_line} - ${#settings_line} - ${#legacy_line} ))
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

# The compact source is detected without jq, so a machine without jq still
# gets the handoff and ledger sections. Hook output over 10,000 characters is
# replaced by a file reference, so the snapshot gets only the room the entry
# point leaves, with headroom for the wrapper text.
if grep -qE '"source"[[:space:]]*:[[:space:]]*"compact"' <<<"$stdin_json" \
   && . "${SCRIPT_DIR}/lib/snapshot.sh" 2>/dev/null; then
  cap=$(( 9500 - ${#content} - 400 - ${#roadmap_line} - ${#settings_line} - ${#legacy_line} - ${#darkmem_lines} ))
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
