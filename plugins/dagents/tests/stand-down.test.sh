#!/usr/bin/env bash
# The guard's stand-down: a conflicted session start prints the block as JSON
# and every other hook stays silent; a fork runs the guard; a clean start
# leaves no marker.
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
printf '{"version":2,"plugins":{"dforge@darkraise":[{"scope":"user","installPath":"/x","version":"5"}]}}' > "$TMP/claude/plugins/installed_plugins.json"
printf '{"enabledPlugins":{"dforge@darkraise":true}}' > "$TMP/claude/settings.json"
event() { printf '{"session_id":"s1","cwd":"%s","source":"%s","hook_event_name":"%s","transcript_path":"%s/t.jsonl","stop_hook_active":false}' "$TMP/project" "$1" "$2" "$TMP"; }

out=$(event startup SessionStart | (cd "$TMP/project" && bash "$ROOT/scripts/session-start.sh"))
check "conflict: JSON with a systemMessage" "$(printf '%s' "$out" | jq -r '.systemMessage | contains("dforge@darkraise")')" "true"
check "conflict: the model is told too" "$(printf '%s' "$out" | jq -r '.hookSpecificOutput.additionalContext | contains("claude plugin disable dforge@darkraise --scope local")')" "true"
check "conflict: no dagents injection" "$(printf '%s' "$out" | grep -c 'using-dagents')" "0"
check "conflict: marker written" "$( [ -e "$TMP/data/workflow-guard/s1" ] && echo yes)" "yes"
for hook in $(jq -r '.hooks | to_entries[] | select(.key != "SessionStart") | .value[].hooks[].command' "$ROOT/hooks/hooks.json" | sed -E 's#^bash "\$\{CLAUDE_PLUGIN_ROOT\}/##; s#"$##'); do
  silent=$(event startup Stop | (cd "$TMP/project" && bash "$ROOT/$hook" 2>&1)); code=$?
  check "conflict: $hook is silent" "$code:$silent" "0:"
  # It stops at its stand-down check: the marker test is its last command.
  trace=$(event startup Stop | (cd "$TMP/project" && bash -x "$ROOT/$hook" 2>&1 >/dev/null) | grep '^+' | tail -n 2 | tr '\n' '|')
  check "conflict: $hook exits at its stand-down check" "$trace" "+ '[' -e $TMP/data/workflow-guard/s1 ']'|+ exit 0|"
done
check "conflict: no transcript record" "$(ls "$HOME/.claude/dagents/sessions/by-id" 2>/dev/null | wc -l | tr -d ' ')" "0"

printf '{"enabledPlugins":{"dforge@darkraise":false}}' > "$TMP/claude/settings.json"
event startup SessionStart | (cd "$TMP/project" && bash "$ROOT/scripts/session-start.sh") > /dev/null
check "clean start: marker removed" "$( [ -e "$TMP/data/workflow-guard/s1" ] && echo yes || echo no)" "no"
check "the guard's matcher includes fork" "$(jq -r '.hooks.SessionStart[0].matcher' "$ROOT/hooks/hooks.json")" "startup|resume|clear|compact|fork"

printf '{"enabledPlugins":{"dforge@darkraise":true}}' > "$TMP/claude/settings.json"
out=$(printf '{"session_id":"s2","cwd":"%s","source":"fork","hook_event_name":"SessionStart"}' "$TMP/project" | (cd "$TMP/project" && bash "$ROOT/scripts/session-start.sh"))
check "fork: guard runs" "$( [ -e "$TMP/data/workflow-guard/s2" ] && echo yes)" "yes"

printf '{"enabledPlugins":{"dforge@darkraise":false}}' > "$TMP/claude/settings.json"
mkdir -p "$TMP/nonode"
for tool in bash sh cat jq git sed awk tr mkdir rm date grep head tail sort uname mktemp dirname basename printf wc cut env ls find cp mv touch stat od; do
  where=$(command -v "$tool" 2>/dev/null) && [ "$where" != "$(command -v node 2>/dev/null)" ] && ln -sf "$where" "$TMP/nonode/$tool"
done
with_node=$(event resume SessionStart | (cd "$TMP/project" && bash "$ROOT/scripts/session-start.sh" 2>/dev/null))
no_node_out=$(event resume SessionStart | (cd "$TMP/project" && PATH="$TMP/nonode" bash "$ROOT/scripts/session-start.sh" 2>"$TMP/nonode.err"))
no_node_err=$(cat "$TMP/nonode.err")
check "node missing: no guard output on stderr" "$(printf '%s' "$no_node_err" | grep -c 'workflow-guard\|node: command not found')" "0"
check "node missing: the session start prints what it prints with node and no conflict" "$no_node_out" "$with_node"
check "node missing: the session start still injects the entry point" "$(printf '%s' "$no_node_out" | grep -c 'using-dagents')" "1"

printf '%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
