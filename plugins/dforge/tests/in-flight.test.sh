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
mkdir -p "$HOME/.claude/dforge/sessions/by-id"
jq -n --arg tp "$TP" '{session_id:"s-flight",transcript_path:$tp}' > "$HOME/.claude/dforge/sessions/by-id/$SID.json"

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
check "it is named with its id and description" "$(grep -c '^- agent a3 - idle - Implement task 3$' <<<"$out")" "1"

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
check "the shell is named" "$(grep -c '^- shell b9 - idle - Run the suite$' <<<"$out")" "1"

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

# A long session's tool calls outgrow what one environment string can carry.
fjq -nc 'range(2000) | {type:"assistant",message:{role:"assistant",content:[{type:"tool_use",id:("toolu_bulk_" + tostring),name:"Bash",input:{description:("routine step " + tostring + " " + ("x" * 60))}}]}}' >> "$TP"
use toolu_late 'Watch the build'
result toolu_late 'Command running in background with ID: b10. Output is being written to: /tmp/b10.output.'
out=$(bash "$INFLIGHT"); code=$?
check "a long transcript: still exit 1" "$code" "1"
check "a long transcript: the launch is named" "$(grep -c '^- shell b10 - idle - Watch the build$' <<<"$out")" "1"
result toolu_stop2 '{"message":"Successfully stopped task: b10 (Watch the build)","task_id":"b10"}'

# --- start time and idle age ---
result_at() { # result_at <tool_use_id> <iso timestamp> <text>
  fjq -nc --arg id "$1" --arg ts "$2" --arg t "$3" '{type:"user",timestamp:$ts,message:{role:"user",content:[{type:"tool_result",tool_use_id:$id,content:$t}]}}' >> "$TP"
}
ago() { touch -d "$1 minutes ago" "$2"; } # ago <minutes> <file>
: > "$TP"
mkdir -p "$TMP/$SID/subagents"

use toolu_s11 'Run the suite'
result_at toolu_s11 2026-10-26T08:05:00.000Z "Command running in background with ID: b11. Output is being written to: $TMP/b11.output. You will be notified when it completes."
: > "$TMP/b11.output"; ago 47 "$TMP/b11.output"
out=$(TZ=UTC0 bash "$INFLIGHT")
check "a shell: its start time and the idle age of the file its result names" \
  "$(grep -c '^- shell b11 08:05 idle 47m Run the suite$' <<<"$out")" "1"

use toolu_a11 'Implement task 4'
result toolu_a11 "$(printf 'Async agent launched successfully.\nagentId: a11 (internal ID)\noutput_file: %s/a11.output\nDo NOT Read or tail this file.' "$TMP")"
: > "$TMP/a11.output"; ago 12 "$TMP/a11.output"
out=$(bash "$INFLIGHT")
check "an agent: the idle age of its output_file" "$(grep -c '^- agent a11 - idle 12m Implement task 4$' <<<"$out")" "1"

use toolu_a12 'Review task 4'
result toolu_a12 $'Async agent launched successfully.\nagentId: a12 (internal ID)'
: > "$TMP/$SID/subagents/agent-a12.jsonl"; ago 9 "$TMP/$SID/subagents/agent-a12.jsonl"
out=$(bash "$INFLIGHT")
check "an agent with no output_file: the idle age of its own transcript" "$(grep -c '^- agent a12 - idle 9m Review task 4$' <<<"$out")" "1"

use toolu_a13 'Review task 5'
result toolu_a13 "$(printf 'Async agent launched successfully.\nagentId: a13 (internal ID)\noutput_file: %s/gone.output' "$TMP")"
: > "$TMP/$SID/subagents/agent-a13.jsonl"; ago 5 "$TMP/$SID/subagents/agent-a13.jsonl"
out=$(bash "$INFLIGHT")
check "an agent whose named file is gone: its transcript instead" "$(grep -c '^- agent a13 - idle 5m Review task 5$' <<<"$out")" "1"

use toolu_a14 'Review task 6'
result toolu_a14 $'Async agent launched successfully.\nagentId: a14 (internal ID)'
out=$(bash "$INFLIGHT")
check "an agent with neither file: idle -" "$(grep -c '^- agent a14 - idle - Review task 6$' <<<"$out")" "1"

use toolu_a15 'Review task 7'
: > "$TMP/a15-transcript.jsonl"; ago 33 "$TMP/a15-transcript.jsonl"
if ln -s "$TMP/a15-transcript.jsonl" "$TMP/a15.output" 2>/dev/null && [ -L "$TMP/a15.output" ]; then
  result toolu_a15 "$(printf 'Async agent launched successfully.\nagentId: a15 (internal ID)\noutput_file: %s/a15.output' "$TMP")"
  out=$(bash "$INFLIGHT")
  check "an output file that is a link: the age of what it points at" "$(grep -c '^- agent a15 - idle 33m Review task 7$' <<<"$out")" "1"
fi

# --- a shell moved to the background by its foreground timeout ---
use toolu_t16 'Run the long suite'
result toolu_t16 "Command did not complete within its 120s timeout and was moved to the background (ID: b16). Output is being written to: $TMP/b16.output. You will be notified when it completes. To check interim output, use Read on that file path."
: > "$TMP/b16.output"; ago 3 "$TMP/b16.output"
out=$(bash "$INFLIGHT")
check "a shell moved to the background by its timeout is listed with its output file" \
  "$(grep -c '^- shell b16 - idle 3m Run the long suite$' <<<"$out")" "1"
notify toolu_t16 completed
out=$(bash "$INFLIGHT")
check "its notification ends it" "$(grep -c '^- shell b16 ' <<<"$out")" "0"

# --- no transcript for this session ---
rm -f "$HOME/.claude/dforge/sessions/by-id/$SID.json"
check "no session record: exit 3" "$(cd "$REPO" && bash "$INFLIGHT" >/dev/null; echo $?)" "3"
check "no session record: next-step still prints" \
  "$(cd "$REPO" && bash "$NEXT" docs/superpowers/plans/2026-10-10-example.md 2>/dev/null | grep -c '## Next session')" "1"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
