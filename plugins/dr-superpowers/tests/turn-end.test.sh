#!/usr/bin/env bash
# The UserPromptSubmit hook stamps each turn; the Stop hook blocks a stop once
# when that turn wrote a plan's ledger and the last message carries neither the
# finishing menu nor the next-step block. Everything else passes silently.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
START="$HERE/../scripts/turn-start.sh"
END="$HERE/../scripts/turn-end.sh"
HOOKS="$HERE/../hooks/hooks.json"

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME"

REPO="$TMP/repo"
git init -q "$REPO"
WS="$REPO/.superpowers/sdd/2026-10-08-example"
mkdir -p "$WS"
LEDGER="$WS/progress.md"

prompt() { jq -n --arg sid "$1" '{hook_event_name:"UserPromptSubmit",session_id:$sid,prompt:"go"}' | bash "$START"; }
stop() { # stop <session> <last message> [stop_hook_active] [transcript]
  jq -n --arg sid "$1" --arg cwd "$REPO" --arg msg "$2" --argjson active "${3:-false}" --arg tp "${4:-}" \
    '{hook_event_name:"Stop",session_id:$sid,cwd:$cwd,transcript_path:$tp,stop_hook_active:$active}
     + (if $msg == "" then {} else {last_assistant_message:$msg} end)' | bash "$END"
}
decision() { jq -r '.decision // "none"' <<<"${1:-{\}}" 2>/dev/null || echo none; }
write_ledger() {
  sleep 1 # -newer compares whole seconds on some filesystems
  printf '# SDD ledger — plan: docs/superpowers/plans/2026-10-08-example.md\n%s\n' "$1" > "$LEDGER"
}

# --- turn-start ---
check "turn-start prints nothing" "$(prompt s-1)" ""
check "turn-start stamps the session" \
  "$([ -f "$HOME/.claude/dr-superpowers/sessions/turns/s-1" ] && echo yes || echo no)" "yes"
check "turn-start tolerates malformed stdin" "$(printf 'nope' | bash "$START"; echo "exit $?")" "exit 0"

# --- a turn that never touched the ledger ---
write_ledger 'Task 1: complete (commits a..b, review clean)'
sleep 1; prompt s-1
check "no ledger write this turn: passes" "$(stop s-1 'Here is the answer.')" ""

# --- mid-plan, summary without the block ---
write_ledger 'Task 1: complete (commits a..b, review clean)'
out=$(stop s-1 'Task 1 is done. Everything looks good.')
check "mid-plan summary: blocks" "$(decision "$out")" "block"
check "mid-plan summary: names next-step and the plan" \
  "$(jq -r .reason <<<"$out" | grep -c 'scripts/next-step docs/superpowers/plans/2026-10-08-example.md')" "1"
check "retry with stop_hook_active: passes" "$(stop s-1 'Task 1 is done.' true)" ""
check "next-step block: passes" "$(stop s-1 $'Stopping here.\n\n## Next session\n\n**Status:** x')" ""
check "finish-preference question: passes" "$(stop s-1 $'Before I start: when the implementation is done, the finish menu waits for\nyour answer. If it gets none within 30 minutes, what should I do?\n\nWhich option?')" ""

# --- final review clean, summary instead of finishing ---
write_ledger $'Task 1: complete (commits a..b, review clean)\nFinal review: clean (commits a1b2c3d..f0e1d2c)'
out=$(stop s-1 'All tasks complete and the final review is clean. Rulings I made: none.')
check "clean final review summary: blocks" "$(decision "$out")" "block"
check "clean final review summary: names finishing" \
  "$(jq -r .reason <<<"$out" | grep -c 'dr-superpowers:finishing-a-development-branch')" "1"
check "finishing menu: passes" "$(stop s-1 $'1. Merge back to main locally\n2. Push and create a Pull Request\n3. Keep the branch as-is\n\nWhich option?')" ""
check "finishing test failure: passes" "$(stop s-1 'Tests failing (2 failures). Must fix before completing:')" ""

# --- two ledgers written this turn: each needs its own ending ---
WS2="$REPO/.superpowers/sdd/2026-10-09-other"
mkdir -p "$WS2"
printf '# SDD ledger — plan: docs/superpowers/plans/2026-10-09-other.md\nTask 2: complete (commits c..d, review clean)\n' > "$WS2/progress.md"
out=$(stop s-1 $'1. Merge back to main locally\n\nWhich option?')
check "two ledgers, menu only: blocks" "$(decision "$out")" "block"
check "two ledgers, menu only: names the mid-plan ledger's next-step" \
  "$(jq -r .reason <<<"$out" | grep -c 'scripts/next-step docs/superpowers/plans/2026-10-09-other.md')" "1"
check "two ledgers, next-step block: passes" "$(stop s-1 $'Stopping here.\n\n## Next session\n\n**Status:** x')" ""
rm -rf "$WS2"

# --- the transcript stands in when the message field is absent ---
TP="$TMP/transcript.jsonl"
jq -nc '{type:"user",message:{role:"user",content:"go"}}' > "$TP"
jq -nc '{type:"assistant",message:{role:"assistant",content:[{type:"text",text:"Which option?"}]}}' >> "$TP"
check "transcript fallback: menu passes" "$(stop s-1 '' false "$TP")" ""
jq -nc '{type:"assistant",message:{role:"assistant",content:[{type:"text",text:"Done."}]}}' >> "$TP"
check "transcript fallback: summary blocks" "$(decision "$(stop s-1 '' false "$TP")")" "block"

# --- background work still running ---
# Shaped as Claude Code records them: the launch's tool result, then a queued
# task notification naming the launch's tool_use id and its status.
BG="$TMP/background.jsonl"
launch() { # launch <tool_use_id> <result text> [as_array]
  if [ "${3:-}" = array ]; then
    jq -nc --arg id "$1" --arg t "$2" '{type:"user",message:{role:"user",content:[{type:"tool_result",tool_use_id:$id,content:[{type:"text",text:$t}]}]}}'
  else
    jq -nc --arg id "$1" --arg t "$2" '{type:"user",message:{role:"user",content:[{type:"tool_result",tool_use_id:$id,content:$t}]}}'
  fi >> "$BG"
}
notify() { # notify <tool_use_id> <status>
  jq -nc --arg id "$1" --arg st "$2" \
    '{type:"attachment",attachment:{type:"queued_command",prompt:("<task-notification>\n<task-id>x</task-id>\n<tool-use-id>" + $id + "</tool-use-id>\n<output-file>/tmp/x.output</output-file>\n<status>" + $st + "</status>\n</task-notification>")}}' >> "$BG"
}
: > "$BG"
jq -nc '{type:"assistant",message:{role:"assistant",content:[{type:"text",text:"Dispatched."}]}}' >> "$BG"
launch toolu_agent 'Async agent launched successfully. agentId: a1' array
launch toolu_bash 'Command running in background with ID: b1. Output is being written to: /tmp/b1.output.'
launch toolu_grep 'notes.md: Async agent launched successfully'
write_ledger 'Task 1: dispatched'
check "agent and command running: passes" "$(stop s-1 'Waiting on the reviewer.' false "$BG")" ""
out=$(stop s-1 $'Stopping here.\n\n## Next session\n\n**Status:** x' false "$BG")
check "next-step block over running work: blocks" "$(decision "$out")" "block"
check "the hold counts the running launches" "$(jq -r .reason <<<"$out" | grep -c '2 background launch')" "1"
check "finishing menu over running work: blocks" "$(decision "$(stop s-1 'Which option?' false "$BG")")" "block"
check "retry over running work: passes" "$(stop s-1 'Which option?' true "$BG")" ""
sleep 1; prompt s-1
check "next-step block over running work, no ledger write: blocks" \
  "$(decision "$(stop s-1 $'## Next session\n\nx' false "$BG")")" "block"
check "plain stop over running work, no ledger write: passes" "$(stop s-1 'Waiting.' false "$BG")" ""
write_ledger 'Task 1: dispatched'
notify toolu_agent completed
check "command still running: passes" "$(stop s-1 'Waiting on the reviewer.' false "$BG")" ""
# A launch inside a subagent's own transcript lines is not the controller's.
jq -nc '{type:"user",isSidechain:true,message:{role:"user",content:[{type:"tool_result",tool_use_id:"toolu_side",content:"Command running in background with ID: s1."}]}}' >> "$BG"
notify toolu_bash killed
check "all background work finished: blocks" "$(decision "$(stop s-1 'Waiting on the reviewer.' false "$BG")")" "block"
check "the block says to wait without the next-step block" \
  "$(jq -r .reason <<<"$(stop s-1 'Done.' false "$BG")" | grep -c 'end the turn without the block')" "1"

# A launch stopped by TaskStop never sends a notification; it is not running.
# Neither is one whose ID only shows up later in some other tool's output.
: > "$BG"
launch toolu_timer 'Command running in background with ID: t1. Output is being written to: /tmp/t1.output.'
launch toolu_watch 'Command running in background with ID: w1. Output is being written to: /tmp/w1.output.'
launch toolu_grep2 'grep output: Successfully stopped task: w1 (sleep 900)'
NEXT=$'Stopping here.\n\n## Next session\n\n**Status:** x'
check "unstopped commands: next-step block holds" "$(decision "$(stop s-1 "$NEXT" false "$BG")")" "block"
launch toolu_stop '{"message":"Successfully stopped task: t1 (sleep 900)","task_id":"t1","task_type":"local_bash"}'
out=$(stop s-1 "$NEXT" false "$BG")
check "one stopped, one running: still holds" "$(decision "$out")" "block"
check "the stopped command is not counted" "$(jq -r .reason <<<"$out" | grep -c '1 background launch')" "1"
launch toolu_stop2 'Successfully stopped task: w1 (sleep 900)'
check "every launch stopped: next-step block passes" "$(stop s-1 "$NEXT" false "$BG")" ""
launch toolu_agent2 $'Async agent launched successfully.\nagentId: a7 (internal ID)' array
check "a running agent still holds" "$(decision "$(stop s-1 "$NEXT" false "$BG")")" "block"
launch toolu_stop3 '{"message":"Successfully stopped task: a7","task_id":"a7"}'
check "a stopped agent passes" "$(stop s-1 "$NEXT" false "$BG")" ""

# Work launched before the session last started or resumed died with that
# process, so its missing notification does not count.
: > "$BG"
jq -nc '{type:"user",timestamp:"2026-10-10T08:00:00.000Z",message:{role:"user",content:[{type:"tool_result",tool_use_id:"toolu_old",content:"Command running in background with ID: o1."}]}}' >> "$BG"
check "launch with no restart since: holds" "$(decision "$(stop s-1 "$NEXT" false "$BG")")" "block"
jq -n --arg tp "$BG" --arg cwd "$REPO" '{session_id:"s-1",transcript_path:$tp,cwd:$cwd,source:"resume"}' \
  | bash "$HERE/../scripts/session-start.sh" >/dev/null
check "session-start records the resume time" \
  "$([ -f "$HOME/.claude/dr-superpowers/sessions/turns/s-1.since" ] && echo yes || echo no)" "yes"
check "launch from before the resume: passes" "$(stop s-1 "$NEXT" false "$BG")" ""
jq -nc '{type:"user",timestamp:"2999-01-01T00:00:00.000Z",message:{role:"user",content:[{type:"tool_result",tool_use_id:"toolu_new",content:"Command running in background with ID: n1."}]}}' >> "$BG"
check "launch after the resume: holds" "$(decision "$(stop s-1 "$NEXT" false "$BG")")" "block"
before=$(cat "$HOME/.claude/dr-superpowers/sessions/turns/s-1.since")
sleep 1
jq -n --arg tp "$BG" --arg cwd "$REPO" '{session_id:"s-1",transcript_path:$tp,cwd:$cwd,source:"compact"}' \
  | bash "$HERE/../scripts/session-start.sh" >/dev/null
check "compaction keeps the running work's start time" \
  "$(cat "$HOME/.claude/dr-superpowers/sessions/turns/s-1.since")" "$before"
rm -f "$HOME/.claude/dr-superpowers/sessions/turns/s-1.since"

# --- another session, or no stamp ---
check "unstamped session: passes" "$(stop s-other 'Done.')" ""
check "malformed stdin: passes" "$(printf 'nope' | bash "$END"; echo "exit $?")" "exit 0"
outside="$TMP/outside"; mkdir -p "$outside"
check "outside a repository: passes" \
  "$(jq -n --arg cwd "$outside" '{session_id:"s-1",cwd:$cwd,last_assistant_message:"Done."}' | bash "$END")" ""

# --- wiring ---
check "hooks.json registers UserPromptSubmit" \
  "$(jq -r '.hooks.UserPromptSubmit[0].hooks[0].command' "$HOOKS")" 'bash "${CLAUDE_PLUGIN_ROOT}/scripts/turn-start.sh"'
check "hooks.json registers Stop" \
  "$(jq -r '.hooks.Stop[0].hooks[0].command' "$HOOKS")" 'bash "${CLAUDE_PLUGIN_ROOT}/scripts/turn-end.sh"'
check "both hooks force bash" \
  "$(jq -r '[.hooks.UserPromptSubmit[0].hooks[0].shell, .hooks.Stop[0].hooks[0].shell] | join(",")' "$HOOKS")" "bash,bash"

# --- the execution skills hand off by a Skill tool call ---
for s in subagent-driven-development executing-plans; do
  check "$s: finishing is a Skill tool call in the same turn" \
    "$(grep -c 'Finishing is a Skill tool call in this same turn' "$HERE/../skills/$s/SKILL.md")" "1"
done

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
