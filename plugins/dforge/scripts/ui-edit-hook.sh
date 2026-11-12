#!/usr/bin/env bash
# PostToolUse hook (Edit, Write, MultiEdit): when the edited file is a UI file
# (scripts/ui-proof paths), return scripts/ui-lint's findings as additional
# context, and on the first UI edit of a session that has not loaded
# dforge:ui-ux, name the skill once. It never blocks: it prints nothing or one
# hookSpecificOutput object, and always exits 0.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
command -v jq >/dev/null 2>&1 || exit 0
stdin_json="$(cat 2>/dev/null || true)"
jq -e . >/dev/null 2>&1 <<<"$stdin_json" || exit 0
file=$(jq -r '.tool_input.file_path // empty' <<<"$stdin_json")
session_id=$(jq -r '.session_id // empty' <<<"$stdin_json")
transcript_path=$(jq -r '.transcript_path // empty' <<<"$stdin_json")
cwd=$(jq -r '.cwd // empty' <<<"$stdin_json")
[ -n "$file" ] || exit 0
file=${file//\\//}
case $file in /*|[A-Za-z]:/*) ;; *) file="${cwd:-$PWD}/$file" ;; esac
[ -f "$file" ] || exit 0
dir=$(dirname "$file")
root=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null) || exit 0
# Not ${file#"$root"/}: git prints its top level resolved (C:/ on Windows,
# symlinks followed), so it need not spell the start of $file.
prefix=$(git -C "$dir" rev-parse --show-prefix 2>/dev/null) || exit 0
. "$SCRIPT_DIR/lib/ui-ux.sh"
rel="$prefix$(basename "$file")"
uiux_is_ui "$rel" "$(uiux_globs "$root")" || exit 0

lint=$(cd "$root" && bash "$SCRIPT_DIR/ui-lint" "$rel" 2>/dev/null)
lint_status=$?
remind=""
if [ -n "$session_id" ]; then
  marker="${HOME:-}/.claude/dforge/sessions/turns/$(printf '%s' "$session_id" | tr -c 'A-Za-z0-9' '-').ui-ux"
  if [ ! -f "$marker" ]; then
    { mkdir -p "$(dirname "$marker")" && : > "$marker"; } 2>/dev/null
    uiux_ran_skill "$transcript_path" ||
      remind="This edit changes a UI file (${rel}). Load dforge:ui-ux with the Skill tool: it owns UI/UX work, and the work is not done until it is proven in the running UI."
  fi
fi

text=""
if [ -n "$lint" ]; then
  text="dforge ui-lint, $(grep -c . <<<"$lint") finding(s) in ${rel}:
$(sed 's/^/- /' <<<"$lint")"
fi
if [ "$lint_status" -eq 2 ]; then text="dforge ui-lint could not run on ${rel}; its findings are unknown, so lint it by hand."; fi
if [ -n "$remind" ]; then text="${text:+$text

}$remind"; fi
[ -n "$text" ] || exit 0
jq -n --arg t "$text" '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $t}}'
exit 0
