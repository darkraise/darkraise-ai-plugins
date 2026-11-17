#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$HERE/.."
pass=0 fail=0
check() { if [ "$2" = "$3" ]; then pass=$((pass + 1)); else printf 'FAIL - %s\n       got:  [%s]\n       want: [%s]\n' "$1" "$2" "$3"; fail=$((fail + 1)); fi; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" CLAUDE_PLUGIN_DATA="$TMP/data" CLAUDE_PLUGIN_ROOT="$ROOT"
export WORKFLOW_GUARD_CLAUDE_DIR="$TMP/claude" WORKFLOW_GUARD_MANAGED_DIR="$TMP/managed" WORKFLOW_GUARD_PROJECT_DIR="$TMP/project"
mkdir -p "$HOME" "$TMP/claude/plugins" "$TMP/managed" "$TMP/project/.claude"
git init -q "$TMP/project"
printf '{"version":2,"plugins":{"dagents@darkraise":[{"scope":"user","installPath":"/x","version":"1"}]}}' > "$TMP/claude/plugins/installed_plugins.json"
printf '{"enabledPlugins":{"dagents@darkraise":true}}' > "$TMP/claude/settings.json"
event() { printf '{"session_id":"s1","cwd":"%s","source":"%s","hook_event_name":"%s","transcript_path":"%s/t.jsonl","stop_hook_active":false}' "$TMP/project" "$1" "$2" "$TMP"; }

out=$(event startup SessionStart | (cd "$TMP/project" && bash "$ROOT/scripts/session-start.sh"))
check "conflict: JSON with a systemMessage" "$(printf '%s' "$out" | jq -r '.systemMessage | contains("dagents@darkraise")')" "true"
check "conflict: the model is told too" "$(printf '%s' "$out" | jq -r '.hookSpecificOutput.additionalContext | contains("claude plugin disable dagents@darkraise --scope local")')" "true"
check "conflict: no dforge injection" "$(printf '%s' "$out" | grep -c 'using-dforge')" "0"
check "conflict: marker written" "$( [ -e "$TMP/data/workflow-guard/s1" ] && echo yes)" "yes"
for hook in $(jq -r '.hooks | to_entries[] | select(.key != "SessionStart") | .value[].hooks[].command' "$ROOT/hooks/hooks.json" | sed -E 's#^bash "\$\{CLAUDE_PLUGIN_ROOT\}/##; s#"$##'); do
  silent=$(event startup Stop | (cd "$TMP/project" && bash "$ROOT/$hook" 2>&1)); code=$?
  check "conflict: $hook is silent" "$code:$silent" "0:"
done
check "conflict: no transcript record" "$(ls "$HOME/.claude/dforge/sessions/by-id" 2>/dev/null | wc -l | tr -d ' ')" "0"
printf '{"enabledPlugins":{"dagents@darkraise":false}}' > "$TMP/claude/settings.json"
event startup SessionStart | (cd "$TMP/project" && bash "$ROOT/scripts/session-start.sh") > /dev/null
check "clean start: marker removed" "$( [ -e "$TMP/data/workflow-guard/s1" ] && echo yes || echo no)" "no"
check "the guard's matcher includes fork" "$(jq -r '.hooks.SessionStart[0].matcher' "$ROOT/hooks/hooks.json")" "startup|resume|clear|compact|fork"
printf '%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
