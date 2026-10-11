#!/usr/bin/env bash
# scripts/in-flight lists the background work this session started that is
# still running, and scripts/next-step prints no block while anything is
# listed. Transcript lines are shaped as Claude Code records them.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFLIGHT="$HERE/../scripts/in-flight"
NEXT="$HERE/../scripts/next-step"

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME"
SID=s-flight
export CLAUDE_CODE_SESSION_ID=$SID
TP="$TMP/$SID.jsonl"
mkdir -p "$HOME/.claude/dr-superpowers/sessions/by-id"
jq -n --arg tp "$TP" '{session_id:"s-flight",transcript_path:$tp}' > "$HOME/.claude/dr-superpowers/sessions/by-id/$SID.json"

# Git Bash rewrites arguments that look like POSIX paths, and a jq filter full
# of </tag> text does; the fixtures are opaque data, so suppress the conversion.
fjq() { MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' jq "$@"; }
use() { # use <tool_use_id> <description> — the controller's tool call
  fjq -nc --arg id "$1" --arg d "$2" '{type:"assistant",message:{role:"assistant",content:[{type:"tool_use",id:$id,name:"Agent",input:{description:$d}}]}}' >> "$TP"
}
result() { # result <tool_use_id> <text>
  fjq -nc --arg id "$1" --arg t "$2" '{type:"user",message:{role:"user",content:[{type:"tool_result",tool_use_id:$id,content:$t}]}}' >> "$TP"
}
notify() { # notify <tool_use_id> <status> [note]
  fjq -nc --arg id "$1" --arg st "$2" --arg note "${3:-}" \
    '{type:"attachment",attachment:{type:"queued_command",prompt:("<task-notification>\n<task-id>x</task-id>\n<tool-use-id>" + $id + "</tool-use-id>\n<output-file>/tmp/x.output</output-file>\n<status>" + $st + "</status>\n<summary>Agent \"x\" finished</summary>\n" + (if $note == "" then "" else "<note>" + $note + "</note>\n" end) + "</task-notification>")}}' >> "$TP"
}
LINGER='This agent stopped with background work of its own still running. It may resume on its own when that work completes or reports, and the same task-id notifies again if it does; the result below may be interim.'

: > "$TP"
out=$(bash "$INFLIGHT"); code=$?
check "nothing launched: exit 0" "$code" "0"

use toolu_impl 'Implement task 3'
result toolu_impl $'Async agent launched successfully.\nagentId: a3 (internal ID)'
out=$(bash "$INFLIGHT"); code=$?
check "an agent with no notification: exit 1" "$code" "1"
check "it is named with its id and description" "$(grep -c '^- agent a3 Implement task 3$' <<<"$out")" "1"

notify toolu_impl completed "$LINGER"
out=$(bash "$INFLIGHT"); code=$?
check "an agent that reported but left work running: exit 1" "$code" "1"
check "the reported agent is still listed" "$(grep -c '^- agent a3 ' <<<"$out")" "1"

# A tool's output that quotes a notification is not one.
result toolu_grep '<task-notification><tool-use-id>toolu_impl</tool-use-id><status>completed</status></task-notification>'
check "a quoted notification changes nothing" "$(bash "$INFLIGHT" >/dev/null; echo $?)" "1"

# Once its own work ends, the agent's final notification names only its task
# id, and says nothing about work still running.
fjq -nc '{type:"attachment",attachment:{type:"queued_command",prompt:"<task-notification>\n<task-id>a3</task-id>\n<output-file>/tmp/a3.output</output-file>\n<status>completed</status>\n<summary>Agent \"x\" finished</summary>\n<note>A task-notification fires each time this agent stops with no live background children of its own.</note>\n</task-notification>"}}' >> "$TP"
check "its final notification by task id alone: exit 0" "$(bash "$INFLIGHT" >/dev/null; echo $?)" "0"

use toolu_sh 'Run the suite'
result toolu_sh 'Command running in background with ID: b9. Output is being written to: /tmp/b9.output.'
out=$(bash "$INFLIGHT"); code=$?
check "a running shell: exit 1" "$code" "1"
check "the shell is named" "$(grep -c '^- shell b9 Run the suite$' <<<"$out")" "1"

# --- next-step prints no block over running work ---
REPO="$TMP/repo"
git init -q "$REPO"
mkdir -p "$REPO/docs/superpowers/plans"
printf '# Example\n\n### Task 1: Do it\n\nSteps.\n' > "$REPO/docs/superpowers/plans/2026-10-10-example.md"
out=$(cd "$REPO" && bash "$NEXT" docs/superpowers/plans/2026-10-10-example.md 2>/dev/null); code=$?
check "next-step over running work: exit 5" "$code" "5"
check "next-step over running work: no block" "$(grep -c '## Next session' <<<"$out")" "0"
check "next-step over running work: lists it" "$(grep -c '^- shell b9 ' <<<"$out")" "1"
check "next-step over running work: latest.md untouched" \
  "$([ -f "$REPO/.superpowers/handoff/latest.md" ] && echo written || echo absent)" "absent"

result toolu_stop '{"message":"Successfully stopped task: b9 (Run the suite)","task_id":"b9"}'
out=$(cd "$REPO" && bash "$NEXT" docs/superpowers/plans/2026-10-10-example.md 2>/dev/null); code=$?
check "everything stopped or finished: next-step exit 0" "$code" "0"
check "everything stopped or finished: the block prints" "$(grep -c '## Next session' <<<"$out")" "1"

# --- no transcript for this session ---
rm -f "$HOME/.claude/dr-superpowers/sessions/by-id/$SID.json"
check "no session record: exit 3" "$(cd "$REPO" && bash "$INFLIGHT" >/dev/null; echo $?)" "3"
check "no session record: next-step still prints" \
  "$(cd "$REPO" && bash "$NEXT" docs/superpowers/plans/2026-10-10-example.md 2>/dev/null | grep -c '## Next session')" "1"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
