#!/usr/bin/env bash
# The UserPromptSubmit hook stamps each turn; the Stop hook blocks a stop once
# when that turn wrote a plan's ledger and the last message carries neither the
# finishing menu nor the next-step block. Everything else passes silently.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
START="$HERE/../../plugins/dagents/scripts/turn-start.sh"
END="$HERE/../../plugins/dagents/scripts/turn-end.sh"
HOOKS="$HERE/../../plugins/dagents/hooks/hooks.json"
# The plugin root as turn-end.sh shows it in a hold reason.
SHOWN="$(cd "$HERE/../../plugins/dagents" && pwd)"
if command -v cygpath >/dev/null 2>&1; then SHOWN=$(cygpath -m "$SHOWN"); fi

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}

TMP="$(mktemp -d)"
export WORKFLOW_GUARD_CLAUDE_DIR="$TMP/workflow-guard" WORKFLOW_GUARD_MANAGED_DIR="$TMP/workflow-guard" WORKFLOW_GUARD_PROJECT_DIR="$TMP/workflow-guard"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME"
unset CLAUDE_CONFIG_DIR CLAUDE_CODE_SESSION_ID AR_SESSION DAGENTS_BUDGET CLAUDE_PROJECT_DIR

REPO="$TMP/repo"
git init -q "$REPO"
WS="$REPO/.dagents/sdd/2026-10-08-example"
mkdir -p "$WS"
LEDGER="$WS/progress.md"

prompt() { # prompt <session> [cwd]
  jq -n --arg sid "$1" --arg cwd "${2:-$REPO}" '{hook_event_name:"UserPromptSubmit",session_id:$sid,cwd:$cwd,prompt:"go"}' | bash "$START"
}
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
LATEST="$REPO/.dagents/handoff/latest.md"
# latest.md as scripts/next-step writes it, after the turn's stamp: a block in
# the stop message releases a ledger turn only with that file's Next line.
wrote_next() { # wrote_next [Next text]
  sleep 1
  mkdir -p "${LATEST%/*}"
  printf '# Handoff\n\n## Next session\n\n**Status:** x\n**Next:** %s\n' "${1:-x}" > "$LATEST"
}

# --- turn-start ---
check "turn-start prints nothing" "$(prompt s-1)" ""
check "turn-start stamps the session" \
  "$([ -f "$HOME/.claude/dagents/sessions/turns/s-1" ] && echo yes || echo no)" "yes"
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
  "$(jq -r .reason <<<"$out" | grep -c 'scripts/next-step" docs/superpowers/plans/2026-10-08-example.md')" "1"
check "mid-plan summary: the plugin root is quoted" \
  "$(jq -r .reason <<<"$out" | grep -cF "\`bash \"$SHOWN/scripts/next-step\" docs/superpowers/plans/2026-10-08-example.md\`")" "1"
check "mid-plan summary: tells the user why" "$(jq -r .systemMessage <<<"$out" | grep -c 'dagents held the stop')" "1"
# The checkout path is the caller's, so only the hook's own words are capped.
check "mid-plan summary: the reason stays short" "$(r=$(jq -r .reason <<<"$out"); r=${r//"$SHOWN"/}; [ "${#r}" -lt 360 ] && echo short || echo "long: ${#r}")" "short"
# The ledger's plan line goes into a command the model runs: only a plain path.
sleep 1; prompt s-pp
sleep 1; printf '# SDD ledger — plan: docs/x.md; rm -rf ~ #.md\nTask 1: complete (commits a..b, review clean)\n' > "$LEDGER"
out=$(stop s-pp 'Task 1 is done.')
check "a ledger plan that is not a plain path is not repeated" "$(jq -r .reason <<<"$out" | grep -c 'rm -rf')" "0"
check "a ledger plan that is not a plain path: the placeholder stands" "$(jq -r .reason <<<"$out" | grep -c 'next-step" PLAN_FILE')" "1"
write_ledger 'Task 1: complete (commits a..b, review clean)'
check "retry with stop_hook_active: passes" "$(stop s-1 'Task 1 is done.' true)" ""
wrote_next
check "next-step block: passes" "$(stop s-1 $'Stopping here.\n\n## Next session\n\n**Status:** x\n**Next:** x')" ""
# Without last_assistant_message the transcript's last assistant entry is read,
# however far back it sits.
TR="$TMP/fallback.jsonl"
jq -nc '{type:"assistant",message:{content:[{type:"text",text:"Stopping here.\n\n## Next session\n\n**Status:** x\n**Next:** x"}]}}' > "$TR"
for i in $(seq 500); do printf '{"type":"progress","n":%s}\n' "$i"; done >> "$TR"
check "no message field, the block far back in the transcript: passes" "$(stop s-1 '' false "$TR")" ""
jq -nc '{type:"assistant",message:{content:[{type:"text",text:"Task 1 is done."}]}}' >> "$TR"
check "no message field, a later summary: blocks" "$(decision "$(stop s-1 '' false "$TR")")" "block"
check "finish-preference question: passes" "$(stop s-1 $'Before I start: when the implementation is done and its final review is\nclean, what should I do?\n\n1. Merge back to main locally\n2. Push and create a Pull Request\n3. Keep the branch as-is\n4. Ask me then: show the finish menu and wait for my answer\n\nWhich option?')" ""
check "finish-preference question on a detached HEAD: passes" "$(stop s-1 $'Before I start: when the implementation is done and its final review is\nclean, what should I do?\n\n1. Push as new branch and create a Pull Request\n2. Keep as-is\n3. Ask me then: show the finish menu and wait for my answer\n\nWhich option?')" ""
write_ledger 'Task 1: complete (commits a..b, review clean)'
out=$(stop s-1 $'Before I start: when the implementation is done, the finish menu waits for\nyour answer. If it gets none within 30 minutes, what should I do?\n\nWhich option?')
check "the retired finish-preference question: blocks" "$(decision "$out")" "block"

# --- final review clean, summary instead of finishing ---
write_ledger $'Task 1: complete (commits a..b, review clean)\nFinal review: clean (commits a1b2c3d..f0e1d2c)'
out=$(stop s-1 'All tasks complete and the final review is clean. Rulings I made: none.')
check "clean final review summary: blocks" "$(decision "$out")" "block"
check "clean final review summary: names finishing" \
  "$(jq -r .reason <<<"$out" | grep -c 'dagents:finishing-a-development-branch')" "1"
check "finishing menu: passes" "$(stop s-1 $'1. Merge back to main locally\n2. Push and create a Pull Request\n3. Keep the branch as-is\n\nWhich option?')" ""
check "finishing test failure: passes" "$(stop s-1 'Tests failing (2 failures). Must fix before completing:')" ""

# --- two ledgers written this turn: each needs its own ending ---
WS2="$REPO/.dagents/sdd/2026-10-09-other"
mkdir -p "$WS2"
printf '# SDD ledger — plan: docs/superpowers/plans/2026-10-09-other.md\nTask 2: complete (commits c..d, review clean)\n' > "$WS2/progress.md"
out=$(stop s-1 $'1. Merge back to main locally\n\nWhich option?')
check "two ledgers, menu only: blocks" "$(decision "$out")" "block"
check "two ledgers, menu only: names the mid-plan ledger's next-step" \
  "$(jq -r .reason <<<"$out" | grep -c 'scripts/next-step" docs/superpowers/plans/2026-10-09-other.md')" "1"
check "two ledgers, next-step block: passes" "$(stop s-1 $'Stopping here.\n\n## Next session\n\n**Status:** x\n**Next:** x')" ""
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
notify() { # notify <tool_use_id> <status> [task id]
  MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' jq -nc --arg id "$1" --arg st "$2" --arg task "${3:-x}" \
    '{type:"attachment",attachment:{type:"queued_command",prompt:("<task-notification>\n<task-id>" + $task + "</task-id>\n<tool-use-id>" + $id + "</tool-use-id>\n<output-file>/tmp/x.output</output-file>\n<status>" + $st + "</status>\n</task-notification>")}}' >> "$BG"
}
queue() { # queue <operation> [content] [timestamp]
  MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' jq -nc --arg op "$1" --arg c "${2:-}" --arg ts "${3:-}" \
    '{type:"queue-operation",operation:$op} + (if $c == "" then {} else {content:$c} end) + (if $ts == "" then {} else {timestamp:$ts} end)' >> "$BG"
}
: > "$BG"
jq -nc '{type:"assistant",message:{role:"assistant",content:[{type:"text",text:"Dispatched."}]}}' >> "$BG"
launch toolu_agent 'Async agent launched successfully. agentId: a1' array
launch toolu_bash 'Command running in background with ID: b1. Output is being written to: /tmp/b1.output.'
launch toolu_grep 'notes.md: Async agent launched successfully'
write_ledger 'Task 1: dispatched'
check "agent and command running: passes" "$(stop s-1 'Waiting on the reviewer.' false "$BG")" ""
out=$(stop s-1 $'Stopping here.\n\n## Next session\n\n**Status:** x\n**Next:** x' false "$BG")
check "next-step block over running work: blocks" "$(decision "$out")" "block"
check "the hold counts the running launches" "$(jq -r .reason <<<"$out" | grep -c '2 background launch')" "1"
check "finishing menu over running work: blocks" "$(decision "$(stop s-1 'Which option?' false "$BG")")" "block"
check "retry over running work: passes" "$(stop s-1 'Which option?' true "$BG")" ""
# Every stop after a hold is a retry, so the hold over running work counts once
# per turn, not once per stop: a block printed after another hold is held too.
stop s-1 'Waiting on the reviewer.' false "$BG" >/dev/null
check "a session-ending retry over running work after another hold: blocks" \
  "$(decision "$(stop s-1 $'## Next session\n\nx' true "$BG")")" "block"
check "a second retry over running work: passes" "$(stop s-1 $'## Next session\n\nx' true "$BG")" ""
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

# A finished launch whose notification is still queued starts the next turn as
# soon as this one ends, so the stop is not the end of the work.
QN=$'<task-notification>\n<task-id>q1</task-id>\n<status>completed</status>\n</task-notification>'
queue enqueue "$QN"
check "a queued notification: passes" "$(stop s-1 'Waiting on the verdict.' false "$BG")" ""
queue dequeue
check "a dequeued notification: blocks" "$(decision "$(stop s-1 'Waiting on the verdict.' false "$BG")")" "block"
queue enqueue "$QN"
queue remove "$QN"
check "a notification absorbed mid-turn: blocks" "$(decision "$(stop s-1 'Waiting on the verdict.' false "$BG")")" "block"
queue enqueue 'a typed prompt'
check "a queued prompt is not a notification: blocks" "$(decision "$(stop s-1 'Waiting on the verdict.' false "$BG")")" "block"
queue enqueue "$QN"
queue dequeue
check "dequeue takes the oldest entry: a notification behind a prompt passes" "$(stop s-1 'Waiting on the verdict.' false "$BG")" ""
queue dequeue
printf '2026-10-11T08:00:00.000Z\n' > "$HOME/.claude/dagents/sessions/turns/s-1.since"
queue enqueue "$QN" 2026-10-10T08:00:00.000Z
check "a notification queued before the resume: blocks" "$(decision "$(stop s-1 'Waiting on the verdict.' false "$BG")")" "block"
rm -f "$HOME/.claude/dagents/sessions/turns/s-1.since"
queue dequeue

# A launch stopped by TaskStop never sends a notification; it is not running.
# Neither is one whose ID only shows up later in some other tool's output.
: > "$BG"
launch toolu_timer 'Command running in background with ID: t1. Output is being written to: /tmp/t1.output.'
launch toolu_watch 'Command running in background with ID: w1. Output is being written to: /tmp/w1.output.'
launch toolu_grep2 'grep output: Successfully stopped task: w1 (sleep 900)'
NEXT=$'Stopping here.\n\n## Next session\n\n**Status:** x\n**Next:** x'
wrote_next
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
# An agent that reported but left work of its own running is still listed.
launch toolu_agent3 $'Async agent launched successfully.\nagentId: a8' array
MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' jq -nc '{type:"attachment",attachment:{type:"queued_command",prompt:"<task-notification>\n<task-id>a8</task-id>\n<tool-use-id>toolu_agent3</tool-use-id>\n<output-file>/tmp/a8.output</output-file>\n<status>completed</status>\n<summary>Agent \"x\" finished</summary>\n<note>This agent stopped with background work of its own still running. It may resume on its own when that work completes or reports.</note>\n</task-notification>"}}' >> "$BG"
out=$(stop s-1 "$NEXT" false "$BG")
check "a reported agent with work still running: holds" "$(decision "$out")" "block"
check "the hold names it" "$(jq -r .reason <<<"$out" | grep -c '^- agent a8 ')" "1"
check "the hold shows its start and idle age fields" "$(jq -r .reason <<<"$out" | grep -c '^- agent a8 - idle - ')" "1"
notify toolu_agent3 completed
check "its final notification: passes" "$(stop s-1 "$NEXT" false "$BG")" ""

# An agent resumed with SendMessage is running again, whatever it reported before.
launch toolu_agent5 $'Async agent launched successfully.\nagentId: a20' array
notify toolu_agent5 completed a20
check "a finished agent: a plain stop blocks" "$(decision "$(stop s-1 'Waiting.' false "$BG")")" "block"
launch toolu_send '{"success":true,"message":"Resuming agent a20","resumedAgentId":"a20","pin":{"id":"a20"}}' array
check "a resumed agent: a plain stop passes" "$(stop s-1 'Waiting for its report.' false "$BG")" ""
check "a resumed agent is counted once" "$(jq -r .reason <<<"$(stop s-1 "$NEXT" false "$BG")" | grep -c '1 background launch')" "1"
notify toolu_send completed a20
check "a resumed agent's final notification: blocks" "$(decision "$(stop s-1 'Waiting.' false "$BG")")" "block"
launch toolu_mon 'Monitor started (task m1, expires in 30m unless the source ends first; you get one notice at expiry). You will be notified on each event.'
check "a running Monitor: a plain stop passes" "$(stop s-1 'Watching the deploy.' false "$BG")" ""
notify toolu_mon completed m1
check "a finished Monitor: blocks" "$(decision "$(stop s-1 'Watching the deploy.' false "$BG")")" "block"

# Work launched before the session last started or resumed died with that
# process, so its missing notification does not count.
: > "$BG"
jq -nc '{type:"user",timestamp:"2026-10-10T08:00:00.000Z",message:{role:"user",content:[{type:"tool_result",tool_use_id:"toolu_old",content:"Command running in background with ID: o1."}]}}' >> "$BG"
check "launch with no restart since: holds" "$(decision "$(stop s-1 "$NEXT" false "$BG")")" "block"
jq -n --arg tp "$BG" --arg cwd "$REPO" '{session_id:"s-1",transcript_path:$tp,cwd:$cwd,source:"resume"}' \
  | bash "$HERE/../../plugins/dagents/scripts/session-start.sh" >/dev/null
check "session-start records the resume time" \
  "$([ -f "$HOME/.claude/dagents/sessions/turns/s-1.since" ] && echo yes || echo no)" "yes"
check "launch from before the resume: passes" "$(stop s-1 "$NEXT" false "$BG")" ""
jq -nc '{type:"user",timestamp:"2999-01-01T00:00:00.000Z",message:{role:"user",content:[{type:"tool_result",tool_use_id:"toolu_new",content:"Command running in background with ID: n1."}]}}' >> "$BG"
check "launch after the resume: holds" "$(decision "$(stop s-1 "$NEXT" false "$BG")")" "block"
before=$(cat "$HOME/.claude/dagents/sessions/turns/s-1.since")
sleep 1
jq -n --arg tp "$BG" --arg cwd "$REPO" '{session_id:"s-1",transcript_path:$tp,cwd:$cwd,source:"compact"}' \
  | bash "$HERE/../../plugins/dagents/scripts/session-start.sh" >/dev/null
check "compaction keeps the running work's start time" \
  "$(cat "$HOME/.claude/dagents/sessions/turns/s-1.since")" "$before"
# A session running past the week-long prune keeps its resume time.
touch -d '10 days ago' "$HOME/.claude/dagents/sessions/turns/s-1.since"
prompt s-1
check "a live session's resume time survives the prune" \
  "$([ -f "$HOME/.claude/dagents/sessions/turns/s-1.since" ] && echo yes || echo no)" "yes"
rm -f "$HOME/.claude/dagents/sessions/turns/s-1.since"
H3="$TMP/home-no-record"
mkdir -p "$H3"
jq -n --arg cwd "$REPO" '{session_id:"s-6",cwd:$cwd,source:"startup"}' \
  | HOME="$H3" bash "$HERE/../../plugins/dagents/scripts/session-start.sh" >/dev/null
check "session-start without a transcript writes no session record" \
  "$([ -e "$H3/.claude/dagents/sessions/by-id" ] && echo yes || echo no)" "no"
check "session-start makes the cockpit directory without a session record" \
  "$([ -d "$H3/.claude/dagents/sessions/cockpit" ] && echo yes || echo no)" "yes"
# An empty HOME persists nothing: no path under /.claude reaches mkdir or find.
# The shims log every argument and refuse such a path instead of running the
# tool, so the case holds as root and never writes /.claude on the host.
SHIM="$TMP/shim-bin"
mkdir -p "$SHIM"
for tool in mkdir find; do
  real=$(command -v "$tool")
  cat > "$SHIM/$tool" <<EOF
#!/bin/sh
printf '%s\n' "\$@" >> "$TMP/shim.log"
for a in "\$@"; do case "\$a" in /.claude*) exit 1 ;; esac; done
exec "$real" "\$@"
EOF
  chmod +x "$SHIM/$tool"
done
PATH="$SHIM:$PATH" mkdir -p "$TMP/shim-probe"
check "the mkdir shim logs its arguments" "$(grep -c "^$TMP/shim-probe\$" "$TMP/shim.log")" "1"
out=$(jq -n --arg tp "$BG" --arg cwd "$REPO" '{session_id:"s-7",transcript_path:$tp,cwd:$cwd,source:"startup"}' \
  | HOME= PATH="$SHIM:$PATH" bash "$HERE/../../plugins/dagents/scripts/session-start.sh")
check "session-start with an empty HOME touches nothing under /.claude" "$(grep -c '^/\.claude' "$TMP/shim.log")" "0"
check "session-start with an empty HOME still injects the entry point" \
  "$(jq -r '.hookSpecificOutput.additionalContext | contains("You have dagents.")' <<<"$out" 2>/dev/null)" "true"

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

# --- an auto run bound to the session ends its turns only on the sentinel ---
AR="$HERE/../../plugins/dagents/scripts/auto-run"
git -C "$REPO" -c user.name=t -c user.email=t@example.invalid commit -q --allow-empty -m init
mkdir -p "$HOME/.claude/dagents/sessions/cockpit"
date +%s > "$HOME/.claude/dagents/sessions/cockpit/s-1"
(cd "$REPO" && bash "$AR" --session s-1 start --spec docs/s.md --register docs/r.md >/dev/null)
STATE="$REPO/.dagents/sdd/auto-run.json"
pend() { jq --arg p "$1" '.pending = $p' "$STATE" > "$STATE.tmp" && mv "$STATE.tmp" "$STATE"; }
stop_in() { # stop_in <cwd> <session> <last message> [transcript]
  jq -n --arg cwd "$1" --arg sid "$2" --arg msg "$3" --arg tp "${4:-}" \
    '{hook_event_name:"Stop",session_id:$sid,cwd:$cwd,transcript_path:$tp,stop_hook_active:false,last_assistant_message:$msg}' | bash "$END"
}
sleep 1; prompt s-1
out=$(stop s-1 'Task 2 is done. Everything looks good.')
check "auto run: a summary is held" "$(decision "$out")" "block"
check "auto run: the reason names the sentinel" "$(jq -r .reason <<<"$out" | grep -c 'Auto run: compacting')" "1"
check "auto run: the hold tells the user" "$(jq -r .systemMessage <<<"$out" | grep -c 'auto run, hold 1 of 3')" "1"
check "auto run: the reason names the switching line" "$(jq -r .reason <<<"$out" | grep -c 'end with `Auto run: switching`')" "1"
check "auto run: the stop command quotes the plugin root" "$(jq -r .reason <<<"$out" | grep -cF "run \`bash \"$SHOWN/scripts/auto-run\" stop --reason")" "1"
check "auto run: the retry is held again" "$(decision "$(stop s-1 'Task 2 is done.' true)")" "block"
pend compact
check "auto run: the compacting line passes" "$(stop s-1 $'Task 2 is done.\n\nAuto run: compacting\n')" ""
check "auto run: the clearing line does not answer compact" "$(decision "$(stop s-1 $'Done.\n\nAuto run: clearing')")" "block"
check "auto run: the sentinel must be the last line" "$(decision "$(stop s-1 $'Auto run: compacting\n\nMore words.')")" "block"
pend clear
check "auto run: the clearing line passes a clear" "$(stop s-1 $'Handed off.\n\nAuto run: clearing')" ""
pend switch
check "auto run: the switching line passes a switch" "$(stop s-1 $'Plan saved.\n\nAuto run: switching')" ""
out=$(stop s-1 $'Plan saved.\n\nAuto run: compacting')
check "auto run: the compacting line does not answer a switch" "$(decision "$out")" "block"
check "auto run: the switch hold names the switching line" "$(jq -r .reason <<<"$out" | grep -c 'end your message with the line `Auto run: switching`')" "1"
check "auto run: the switch hold quotes the plugin root" "$(jq -r .reason <<<"$out" | grep -cF "run \`bash \"$SHOWN/scripts/auto-run\" stop --reason")" "1"
pend compact
check "auto run: the switching line does not answer compact" "$(decision "$(stop s-1 $'Done.\n\nAuto run: switching')")" "block"
pend after-compact
out=$(stop s-1 $'Task 3: complete.\n\nAuto run: compacting')
check "auto run: after a booked compaction the hold says to settle it" "$(jq -r .reason <<<"$out" | grep -c 'auto-run" after-compact')" "1"
check "auto run: the after-compact hold quotes the plugin root" "$(jq -r .reason <<<"$out" | grep -cF "run \`bash \"$SHOWN/scripts/auto-run\" after-compact\` now")" "1"
pend handoff
out=$(stop s-1 $'Task 3: complete.\n\nAuto run: compacting')
check "auto run: a pending handoff is held" "$(decision "$out")" "block"
check "auto run: the hold says to hand off and clear" "$(jq -r .reason <<<"$out" | grep -c 'run dagents:handoff')" "1"
check "auto run: the handoff hold quotes the plugin root" "$(jq -r .reason <<<"$out" | grep -cF "then \`bash \"$SHOWN/scripts/auto-run\" clear\`")" "1"
check "auto run: the clearing line does not answer a handoff" "$(decision "$(stop s-1 $'Handed off.\n\nAuto run: clearing')")" "block"
pend resume
check "auto run: a pending resume is held without a sentinel" "$(decision "$(stop s-1 'Resumed.')")" "block"
check "auto run: a pending resume does not pass the compacting line" "$(decision "$(stop s-1 $'Done.\n\nAuto run: compacting')")" "block"
sleep 1; prompt s-2
check "auto run: another session is not held" "$(stop s-2 'Here is the answer.')" ""
git -C "$REPO" worktree add -q -b wt "$TMP/wt"
pend compact
check "auto run: found from a worktree" "$(stop_in "$TMP/wt" s-1 $'Done.\n\nAuto run: compacting')" ""
check "auto run: held from a worktree" "$(decision "$(stop_in "$TMP/wt" s-1 'Done.')")" "block"
check "auto run: a first stop starts the count again" "$(stop s-1 'Done.' | jq -r .systemMessage | grep -c 'hold 1 of 3')" "1"
check "auto run: the second hold in a row" "$(stop s-1 'Done.' true | jq -r .systemMessage | grep -c 'hold 2 of 3')" "1"
check "auto run: the third hold in a row" "$(stop s-1 'Done.' true | jq -r .systemMessage | grep -c 'hold 3 of 3')" "1"
out=$(stop s-1 'Done.' true)
check "auto run: past the cap the run stops" "$(jq -r .active "$STATE")" "false"
check "auto run: the stop names its reason" "$(jq -r .stopped "$STATE" | grep -c 'without its sentinel')" "1"
check "auto run: past the cap, one hold asks for the attended ending" "$(jq -r .reason <<<"$out" | grep -c '§Stopping')" "1"
check "auto run: past the cap the user is told" "$(jq -r .systemMessage <<<"$out" | grep -c 'auto run stopped')" "1"
check "auto run: then the retry passes" "$(stop s-1 'Done.' true)" ""
check "a stopped run: back to the plain rules" "$(stop s-1 'Here is the answer.')" ""

# --- an auto run holds a session that has no turn stamp ---
date +%s > "$HOME/.claude/dagents/sessions/cockpit/s-5"
(cd "$REPO" && bash "$AR" --session s-5 start --spec docs/s.md --register docs/r.md --force >/dev/null)
check "no stamp and no run bound: passes" "$(stop s-other 'Done.')" ""
out=$(stop s-5 'Done.')
check "auto run without a turn stamp: held" "$(decision "$out")" "block"
check "auto run without a turn stamp: the count is kept" "$(cat "$HOME/.claude/dagents/sessions/turns/s-5.holds")" "1"
H2="$TMP/home-turns-is-a-file"
mkdir -p "$H2/.claude/dagents/sessions"
printf 'not a directory\n' > "$H2/.claude/dagents/sessions/turns"
out=$(HOME="$H2" stop s-5 'Done.' true)
check "a hold count that cannot be written: the run stops" "$(jq -r .active "$STATE"):$(jq -r .stopped "$STATE" | grep -c 'without its sentinel')" "false:1"
check "a hold count that cannot be written: one hold asks for the attended ending" "$(jq -r .reason <<<"$out" | grep -c '§Stopping')" "1"

# --- a clean line older than the code is not current ---
h7=$(git -C "$REPO" rev-parse --short HEAD)
printf 'x\n' > "$REPO/code.txt"
git -C "$REPO" add code.txt && git -C "$REPO" -c user.name=t -c user.email=t@example.invalid commit -qm "fix: later"
sleep 1; prompt s-stale
write_ledger "Final review: clean (commits 0000000..$h7)"
out=$(stop s-stale 'All done.')
check "a stale clean line: held" "$(decision "$out")" "block"
check "a stale clean line: not sent to the finishing menu" "$(jq -r .reason <<<"$out" | grep -c 'passed its final review')" "0"

# --- progress kept in darkmem: the mirror's ledgers are the ones read ---
. "$HERE/fixtures/darkmem-stores.sh"
M=$(stores_home "$HOME" "$REPO" proj local darkmem)
mkdir -p "$M/work/sdd/2026-10-10-mirror" "$REPO/.dagents/sdd/2026-10-10-mirror"
sleep 1; prompt s-2; sleep 1
printf '# SDD ledger — plan: docs/dagents/plans/2026-10-10-mirror.md\nTask 1: complete (commits a..b, review clean)\n' > "$M/work/sdd/2026-10-10-mirror/progress.md"
out=$(stop s-2 'Task 1 is done.')
check "darkmem progress: a mirror ledger blocks a bare summary" "$(decision "$out")" "block"
check "darkmem progress: names the plan" \
  "$(jq -r .reason <<<"$out" | grep -c 'scripts/next-step" docs/dagents/plans/2026-10-10-mirror.md')" "1"
mkdir -p "$M/work/sdd/2026-10-11-other"
sleep 1; prompt s-3; sleep 1
printf '# SDD ledger — plan: docs/dagents/plans/2026-10-11-other.md\nTask 1: complete (commits a..b, review clean)\n' > "$M/work/sdd/2026-10-11-other/progress.md"
check "darkmem progress: another worktree's ledger does not block" "$(stop s-3 'Task 1 is done.')" ""
rm -f "$HOME/.dagents/config.json" "$HOME/.dagents/stores.json"

# --- a branch moved without a plan's ledger is not held ---
commit_in() { git -C "$1" -c user.name=t -c user.email=t@example.invalid commit -q --allow-empty -m "$2"; }
UT="$TMP/unplanned.jsonl"
mkdir -p "$REPO/docs/dagents"
sleep 1; prompt s-4
jq -nc --arg t "$(date -u +%Y-%m-%dT%H:%M:%S.999Z)" \
  '{type:"assistant",timestamp:$t,message:{content:[{type:"tool_use",id:"toolu_s",name:"Skill",input:{skill:"dagents:test-driven-development"}}]}}' > "$UT"
check "turn-start records the branch heads" \
  "$([ -f "$HOME/.claude/dagents/sessions/turns/s-4.refs" ] && echo yes || echo no)" "yes"
commit_in "$REPO" adhoc
check "a dagents turn that committed without a plan: passes" "$(stop s-4 'Fixed and committed.' false "$UT")" ""
sleep 1; prompt s-4 "$outside"
check "a prompt outside git records no heads" \
  "$([ -f "$HOME/.claude/dagents/sessions/turns/s-4.refs" ] && echo yes || echo no)" "no"

# --- only the block next-step wrote this turn releases a ledger turn (rows 2, 8) ---
wrote_next 'Resume at Task 2.'
sleep 1; prompt s-nx
write_ledger 'Task 1: complete (commits a..b, review clean)'
HAND=$'Done.\n\n## Next session\n\n**Next:** Resume at Task 2.'
check "a hand-typed block does not release a ledger turn" "$(decision "$(stop s-nx "$HAND")")" "block"
wrote_next 'Resume at Task 2.'
check "a written block releases a ledger turn" "$(stop s-nx "$HAND")" ""
wrote_next 'Resume at Task 3.'
check "a block with another Next line does not release it" "$(decision "$(stop s-nx "$HAND")")" "block"
# next-step prints the block and writes nothing (exit 4) where latest.md cannot
# be written: there the heading alone stands. Root writes any file.
if [ "$(id -u)" = 0 ] && ! command -v cygpath >/dev/null 2>&1; then
  echo "skip - an unwritable latest.md accepts the heading (running as root)"
else
  chmod 444 "$LATEST"
  check "an unwritable latest.md accepts the heading" "$(stop s-nx "$HAND")" ""
  chmod 644 "$LATEST"
fi
. "$HERE/../../plugins/dagents/scripts/lib/next-ending.sh"
check "a writable latest.md: the heading alone is not enough" \
  "$(ending_released "$HAND" "$HOME/.claude/dagents/sessions/turns/s-nx" "$TMP/absent/handoff/latest.md" && echo released || echo held)" "held"
check "a line merely containing the heading is not the block" \
  "$(ending_released $'Done. ## Next session' "$HOME/.claude/dagents/sessions/turns/s-nx" "$TMP/absent/handoff/latest.md" && echo released || echo held)" "held"

# --- a turn that merges a plan or closes a milestone ends on next-step (rows 2, 7) ---
stop_at() { # stop_at <session> <cwd> <last message> [stop_hook_active]
  jq -n --arg sid "$1" --arg cwd "$2" --arg msg "$3" --argjson active "${4:-false}" \
    '{hook_event_name:"Stop",session_id:$sid,cwd:$cwd,transcript_path:"",stop_hook_active:$active,last_assistant_message:$msg}' | bash "$END"
}
commit_all() { git -C "$1" add -A && git -C "$1" -c user.name=t -c user.email=t@example.invalid commit -qm "$2"; }
TRP="$TMP/transitions"
git init -q "$TRP"
mkdir -p "$TRP/docs/dagents/plans"
printf '# Completed plans\n\n- 2026-11-01 `docs/dagents/plans/2026-11-01-old.md` — merged into `main`\n' > "$TRP/docs/dagents/plans/completed.md"
milestone() { printf '| %s | %s | it works | `docs/dagents/registers/%s.md` | %s | - |\n' "$1" "$2" "$1" "$3"; }
{ printf '# Roadmap\n\n| M | Name | Exit | Register | State | Note |\n|---|---|---|---|---|---|\n'; milestone M1 One open; milestone M2 Two open; } > "$TRP/docs/dagents/roadmap.md"
commit_all "$TRP" 'docs: roadmap'
git -C "$TRP" worktree add -q "$TMP/wt-p" -b feature
sleep 1; prompt s-tr1 "$TMP/wt-p"
sleep 1
printf -- '- 2026-11-16 `docs/dagents/plans/2026-11-16-p.md` — merged into `main`\n' >> "$TRP/docs/dagents/plans/completed.md"
commit_all "$TRP" 'docs: record p'
git -C "$TRP" worktree remove --force "$TMP/wt-p"
out=$(stop_at s-tr1 "$TMP/wt-p" 'Merged.')
check "a finishing turn in a removed worktree is held" "$(decision "$out")" "block"
check "a finishing turn in a removed worktree: names next-step --complete and the plan" \
  "$(jq -r .reason <<<"$out" | grep -c 'next-step" --complete docs/dagents/plans/2026-11-16-p.md')" "1"
sleep 1; prompt s-tr6 "$TRP"
sleep 1
printf -- '- 2026-11-16 `x.md; rm -rf ~` — merged\n' >> "$TRP/docs/dagents/plans/completed.md"
commit_all "$TRP" 'docs: a hostile entry'
out=$(stop_at s-tr6 "$TRP" 'Merged.')
check "a plan name that is not a plain path is not repeated" "$(jq -r .reason <<<"$out" | grep -c 'rm -rf')" "0"
check "a plan name that is not a plain path: the placeholder stands" "$(jq -r .reason <<<"$out" | grep -c -- '--complete PLAN_FILE')" "1"
sleep 1; prompt s-tr1 "$TMP/wt-p"
check "a later turn still finds the primary" "$(head -n 1 "$HOME/.claude/dagents/sessions/turns/s-tr1.refs")" \
  "$(git -C "$TRP" rev-parse --path-format=absolute --git-common-dir)"

sleep 1; prompt s-tr2 "$TRP"
sleep 1
sed 's/| M1 | One | \(.*\) | open |/| M1 | One | \1 | closed |/' "$TRP/docs/dagents/roadmap.md" > "$TMP/roadmap.md" && mv "$TMP/roadmap.md" "$TRP/docs/dagents/roadmap.md"
commit_all "$TRP" 'docs: close M1'
out=$(stop_at s-tr2 "$TRP" 'M1 closed.')
check "a turn that closes a milestone is held once" "$(decision "$out")" "block"
check "a turn that closes a milestone: names next-step --project" "$(jq -r .reason <<<"$out" | grep -c 'next-step" --project')" "1"
check "a turn that closes a milestone: the retry passes" "$(stop_at s-tr2 "$TRP" 'M1 closed.' true)" ""

SECOND="$TMP/transitions-2"
git clone -q "$TRP" "$SECOND"
sed 's/| M2 | Two | \(.*\) | open |/| M2 | Two | \1 | closed |/' "$SECOND/docs/dagents/roadmap.md" > "$TMP/roadmap.md" && mv "$TMP/roadmap.md" "$SECOND/docs/dagents/roadmap.md"
printf -- '- 2026-11-16 `docs/dagents/plans/2026-11-16-q.md` — merged into `main`\n' >> "$SECOND/docs/dagents/plans/completed.md"
commit_all "$SECOND" 'docs: close M2, record q'
sleep 1; prompt s-tr3 "$TRP"
sleep 1
git -C "$TRP" pull -q --ff-only "$SECOND" HEAD
check "a pull that moves the roadmap is not held" "$(stop_at s-tr3 "$TRP" 'Pulled.')" ""

sleep 1; prompt s-tr4 "$TRP"
sleep 1
milestone M3 Three open >> "$TRP/docs/dagents/roadmap.md"
commit_all "$TRP" 'docs: add M3'
check "a design turn that edits the roadmap is not held" "$(stop_at s-tr4 "$TRP" 'Added M3.')" ""
sleep 1; prompt s-tr1 "$TMP/wt-p"
sleep 1
milestone M4 Four open >> "$TRP/docs/dagents/roadmap.md"
commit_all "$TRP" 'docs: add M4'
check "a turn in a removed worktree that edits the roadmap is not held" "$(stop_at s-tr1 "$TMP/wt-p" 'Added M4.')" ""

sleep 1; prompt s-tr5 "$TRP"
check "nothing changed, nothing held" "$(stop_at s-tr5 "$TRP" 'Done.')" ""

# A transition turn is released by the block next-step wrote, by finishing's
# menu, and by nothing hand-typed; an uncommitted index edit counts as its own.
TRL="$TRP/.dagents/handoff/latest.md"
record() { printf -- '- 2026-11-16 `docs/dagents/plans/2026-11-16-%s.md` — merged into `main`\n' "$1" >> "$TRP/docs/dagents/plans/completed.md"; }
NB=$'Merged.\n\n## Next session\n\n**Next:** Nothing — no register holds an unresolved row.'
sleep 1; prompt s-tr7 "$TRP"
sleep 1; record r; commit_all "$TRP" 'docs: record r'
sleep 1; mkdir -p "${TRL%/*}"
printf '# Handoff\n\n## Next session\n\n**Status:** x\n**Next:** Nothing — no register holds an unresolved row.\n' > "$TRL"
check "a finishing turn ending on the block next-step wrote passes" "$(stop_at s-tr7 "$TRP" "$NB")" ""
sleep 1; prompt s-tr8 "$TRP"
sleep 1; record s; commit_all "$TRP" 'docs: record s'
check "a finishing turn ending on a hand-typed block is held" "$(decision "$(stop_at s-tr8 "$TRP" "$NB")")" "block"
sleep 1; prompt s-tr9 "$TRP"
sleep 1; record t
out=$(stop_at s-tr9 "$TRP" 'Recorded.')
check "an uncommitted completed.md entry this turn is held" "$(decision "$out")" "block"
check "an uncommitted completed.md entry names its plan" \
  "$(jq -r .reason <<<"$out" | grep -c 'next-step" --complete docs/dagents/plans/2026-11-16-t.md')" "1"
commit_all "$TRP" 'docs: record t'
sleep 1; prompt s-tr10 "$TRP"
sleep 1; record u
check "a transition turn ending on finishing's menu is not held" \
  "$(stop_at s-tr10 "$TRP" $'1. Merge back to main locally\n2. Keep as-is\n\nWhich option?')" ""
commit_all "$TRP" 'docs: record u'

# latest.md absent and its nearest existing parent unwritable: next-step can
# write nothing (exit 4), so the heading alone releases. Root writes any
# directory, and Windows ignores a directory's read-only attribute, so this
# runs only as a regular user on a POSIX host (Linux CI).
if command -v cygpath >/dev/null 2>&1; then
  echo "skip - an absent latest.md under an unwritable parent accepts the heading (Windows directory modes)"
elif [ "$(id -u)" = 0 ]; then
  echo "skip - an absent latest.md under an unwritable parent accepts the heading (running as root)"
else
  mkdir -p "$TMP/ro"
  chmod 555 "$TMP/ro"
  check "an absent latest.md under an unwritable parent accepts the heading" \
    "$(ending_released "$HAND" "$HOME/.claude/dagents/sessions/turns/s-nx" "$TMP/ro/state/handoff/latest.md" && echo released || echo held)" "released"
  chmod 755 "$TMP/ro"
fi

# --- per-worktree handoffs (spec A7, A16) ---
git -C "$REPO" -c user.name=t -c user.email=t@example.invalid commit -q --allow-empty -m base
WTD="$TMP/wt-hand"; git -C "$REPO" worktree add -q -b wt-hand "$WTD"
WT_LATEST="$WTD/.dagents/handoff/latest.md"; mkdir -p "${WT_LATEST%/*}"
wt_block() { sleep 1; printf '# Handoff\n\n## Next session\n\n**Status:** %s\n**Next:** %s\n' "$1" "$2" > "$WT_LATEST"; }
prompt s-wa; write_ledger 'Task 1: complete (commits a..b, review clean)'
check "A7: a held primary turn: held on a summary" "$(decision "$(stop s-wa 'Task 1 is done.')")" "block"
prompt s-wb; write_ledger 'Task 1: complete (commits a..b, review clean)'
wt_block 'wt status' 'Resume at Task 2 (Wt).'
check "A7: the worktree's block written this turn releases" "$(stop s-wb $'Stopping.\n\n## Next session\n\n**Status:** wt status\n**Next:** Resume at Task 2 (Wt).')" ""
prompt s-wc; write_ledger 'Task 1: complete (commits a..b, review clean)'
check "A7: a hand-typed block with no handoff written: held" "$(decision "$(stop s-wc $'## Next session\n\n**Status:** typed\n**Next:** typed.')")" "block"
prompt s-wd; write_ledger 'Task 1: complete (commits a..b, review clean)'
wrote_next 'Own next.'
wt_block 'other' 'Other next.'
check "A16: own block released after another worktree's later write" "$(stop s-wd $'## Next session\n\n**Status:** x\n**Next:** Own next.')" ""
prompt s-we; write_ledger 'Task 1: complete (commits a..b, review clean)'
wt_block 'other' 'Run dagents:finishing-a-development-branch.'
check "A16: another checkout's Next line alone does not release" "$(decision "$(stop s-we $'## Next session\n\n**Next:** Run dagents:finishing-a-development-branch.')")" "block"
prompt s-wf
mkdir -p "$REPO/docs/dagents/plans"; sleep 1
printf -- '- 2026-11-18 `docs/dagents/plans/2026-11-18-x.md` — merged into `main`\n' >> "$REPO/docs/dagents/plans/completed.md"
wt_block 'other' 'Other next.'
check "A16: a completed plan stays held after another worktree writes" "$(decision "$(stop s-wf 'All done.')")" "block"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
