#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$HERE/../../plugins/dforge"
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
# Without GNU timeout (macOS) the guard runs under the watchdog, and still reads the event.
mkdir -p "$TMP/no-timeout"; printf '#!/bin/sh\nexit 1\n' > "$TMP/no-timeout/timeout"; chmod +x "$TMP/no-timeout/timeout"
rm -f "$TMP/data/workflow-guard/s1"
event startup SessionStart | (cd "$TMP/project" && PATH="$TMP/no-timeout:$PATH" bash "$ROOT/scripts/session-start.sh") > /dev/null
check "conflict under the watchdog: marker written" "$( [ -e "$TMP/data/workflow-guard/s1" ] && echo yes)" "yes"
for hook in $(jq -r '.hooks | to_entries[] | select(.key != "SessionStart") | .value[].hooks[].command' "$ROOT/hooks/hooks.json" | sed -E 's#^bash "\$\{CLAUDE_PLUGIN_ROOT\}/##; s#"$##'); do
  silent=$(event startup Stop | (cd "$TMP/project" && bash "$ROOT/$hook" 2>&1)); code=$?
  check "conflict: $hook is silent" "$code:$silent" "0:"
  # It stops at its stand-down check: the marker test is its last command.
  trace=$(event startup Stop | (cd "$TMP/project" && bash -x "$ROOT/$hook" 2>&1 >/dev/null) | grep '^+' | tail -n 2 | tr '\n' '|')
  check "conflict: $hook exits at its stand-down check" "$trace" "+ '[' -e $TMP/data/workflow-guard/s1 ']'|+ exit 0|"
done
check "conflict: no transcript record" "$(ls "$HOME/.claude/dforge/sessions/by-id" 2>/dev/null | wc -l | tr -d ' ')" "0"
printf '{"enabledPlugins":{"dagents@darkraise":false}}' > "$TMP/claude/settings.json"
event startup SessionStart | (cd "$TMP/project" && bash "$ROOT/scripts/session-start.sh") > /dev/null
check "clean start: marker removed" "$( [ -e "$TMP/data/workflow-guard/s1" ] && echo yes || echo no)" "no"
mkdir -p "$TMP/hung"
printf '#!/usr/bin/env bash\ncase "$1" in *workflow-guard.mjs) exec sleep 60 ;; esac\nexec %q "$@"\n' "$(command -v node)" > "$TMP/hung/node"
chmod +x "$TMP/hung/node"
started=$SECONDS
out=$(event startup SessionStart | (cd "$TMP/project" && PATH="$TMP/hung:$PATH" DARKMEM_KILL_GRACE=1 bash "$ROOT/scripts/session-start.sh"))
check "a hung guard: the entry skill is still injected" "$(printf '%s' "$out" | grep -c 'using-dforge')" "1"
check "a hung guard: session start ends within its bound" "$(( SECONDS - started < 20 ))" "1"
check "the guard's matcher includes fork" "$(jq -r '.hooks.SessionStart[0].matcher' "$ROOT/hooks/hooks.json")" "startup|resume|clear|compact|fork"
printf '%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
