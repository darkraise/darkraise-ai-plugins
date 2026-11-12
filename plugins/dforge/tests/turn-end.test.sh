#!/usr/bin/env bash
# The UserPromptSubmit hook stamps each turn; the Stop hook blocks a stop once
# when that turn wrote a plan's ledger and the last message carries neither the
# finishing menu nor the next-step block. Everything else passes silently.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
START="$HERE/../scripts/turn-start.sh"
END="$HERE/../scripts/turn-end.sh"
HOOKS="$HERE/../hooks/hooks.json"
# The plugin root as turn-end.sh shows it in a hold reason.
SHOWN="$(cd "$HERE/.." && pwd)"
if command -v cygpath >/dev/null 2>&1; then SHOWN=$(cygpath -m "$SHOWN"); fi

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME"
unset CLAUDE_CONFIG_DIR CLAUDE_CODE_SESSION_ID AR_SESSION DFORGE_BUDGET CLAUDE_PROJECT_DIR

REPO="$TMP/repo"
git init -q "$REPO"
WS="$REPO/.dforge/sdd/2026-10-08-example"
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

# --- turn-start ---
check "turn-start prints nothing" "$(prompt s-1)" ""
check "turn-start stamps the session" \
  "$([ -f "$HOME/.claude/dforge/sessions/turns/s-1" ] && echo yes || echo no)" "yes"
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
check "mid-plan summary: tells the user why" "$(jq -r .systemMessage <<<"$out" | grep -c 'dforge held the stop')" "1"
check "mid-plan summary: the reason stays short" "$(r=$(jq -r .reason <<<"$out"); [ "${#r}" -lt 420 ] && echo short || echo "long: ${#r}")" "short"
check "retry with stop_hook_active: passes" "$(stop s-1 'Task 1 is done.' true)" ""
check "next-step block: passes" "$(stop s-1 $'Stopping here.\n\n## Next session\n\n**Status:** x')" ""
# Without last_assistant_message the transcript's last assistant entry is read,
# however far back it sits.
TR="$TMP/fallback.jsonl"
jq -nc '{type:"assistant",message:{content:[{type:"text",text:"Stopping here.\n\n## Next session\n\n**Status:** x"}]}}' > "$TR"
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
  "$(jq -r .reason <<<"$out" | grep -c 'dforge:finishing-a-development-branch')" "1"
check "finishing menu: passes" "$(stop s-1 $'1. Merge back to main locally\n2. Push and create a Pull Request\n3. Keep the branch as-is\n\nWhich option?')" ""
check "finishing test failure: passes" "$(stop s-1 'Tests failing (2 failures). Must fix before completing:')" ""

# --- two ledgers written this turn: each needs its own ending ---
WS2="$REPO/.dforge/sdd/2026-10-09-other"
mkdir -p "$WS2"
printf '# SDD ledger — plan: docs/superpowers/plans/2026-10-09-other.md\nTask 2: complete (commits c..d, review clean)\n' > "$WS2/progress.md"
out=$(stop s-1 $'1. Merge back to main locally\n\nWhich option?')
check "two ledgers, menu only: blocks" "$(decision "$out")" "block"
check "two ledgers, menu only: names the mid-plan ledger's next-step" \
  "$(jq -r .reason <<<"$out" | grep -c 'scripts/next-step" docs/superpowers/plans/2026-10-09-other.md')" "1"
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
printf '2026-10-11T08:00:00.000Z\n' > "$HOME/.claude/dforge/sessions/turns/s-1.since"
queue enqueue "$QN" 2026-10-10T08:00:00.000Z
check "a notification queued before the resume: blocks" "$(decision "$(stop s-1 'Waiting on the verdict.' false "$BG")")" "block"
rm -f "$HOME/.claude/dforge/sessions/turns/s-1.since"
queue dequeue

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
  | bash "$HERE/../scripts/session-start.sh" >/dev/null
check "session-start records the resume time" \
  "$([ -f "$HOME/.claude/dforge/sessions/turns/s-1.since" ] && echo yes || echo no)" "yes"
check "launch from before the resume: passes" "$(stop s-1 "$NEXT" false "$BG")" ""
jq -nc '{type:"user",timestamp:"2999-01-01T00:00:00.000Z",message:{role:"user",content:[{type:"tool_result",tool_use_id:"toolu_new",content:"Command running in background with ID: n1."}]}}' >> "$BG"
check "launch after the resume: holds" "$(decision "$(stop s-1 "$NEXT" false "$BG")")" "block"
before=$(cat "$HOME/.claude/dforge/sessions/turns/s-1.since")
sleep 1
jq -n --arg tp "$BG" --arg cwd "$REPO" '{session_id:"s-1",transcript_path:$tp,cwd:$cwd,source:"compact"}' \
  | bash "$HERE/../scripts/session-start.sh" >/dev/null
check "compaction keeps the running work's start time" \
  "$(cat "$HOME/.claude/dforge/sessions/turns/s-1.since")" "$before"
# A session running past the week-long prune keeps its resume time.
touch -d '10 days ago' "$HOME/.claude/dforge/sessions/turns/s-1.since"
prompt s-1
check "a live session's resume time survives the prune" \
  "$([ -f "$HOME/.claude/dforge/sessions/turns/s-1.since" ] && echo yes || echo no)" "yes"
rm -f "$HOME/.claude/dforge/sessions/turns/s-1.since"
H3="$TMP/home-no-record"
mkdir -p "$H3"
jq -n --arg cwd "$REPO" '{session_id:"s-6",cwd:$cwd,source:"startup"}' \
  | HOME="$H3" bash "$HERE/../scripts/session-start.sh" >/dev/null
check "session-start without a transcript writes no session record" \
  "$([ -e "$H3/.claude/dforge/sessions/by-id" ] && echo yes || echo no)" "no"
check "session-start makes the cockpit directory without a session record" \
  "$([ -d "$H3/.claude/dforge/sessions/cockpit" ] && echo yes || echo no)" "yes"
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
  | HOME= PATH="$SHIM:$PATH" bash "$HERE/../scripts/session-start.sh")
check "session-start with an empty HOME touches nothing under /.claude" "$(grep -c '^/\.claude' "$TMP/shim.log")" "0"
check "session-start with an empty HOME still injects the entry point" \
  "$(jq -r '.hookSpecificOutput.additionalContext | contains("You have dforge.")' <<<"$out" 2>/dev/null)" "true"

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
AR="$HERE/../scripts/auto-run"
git -C "$REPO" -c user.name=t -c user.email=t@example.invalid commit -q --allow-empty -m init
mkdir -p "$HOME/.claude/dforge/sessions/cockpit"
date +%s > "$HOME/.claude/dforge/sessions/cockpit/s-1"
(cd "$REPO" && bash "$AR" --session s-1 start --spec docs/s.md --register docs/r.md >/dev/null)
STATE="$REPO/.dforge/sdd/auto-run.json"
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
check "auto run: the hold says to hand off and clear" "$(jq -r .reason <<<"$out" | grep -c 'run dforge:handoff')" "1"
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
date +%s > "$HOME/.claude/dforge/sessions/cockpit/s-5"
(cd "$REPO" && bash "$AR" --session s-5 start --spec docs/s.md --register docs/r.md --force >/dev/null)
check "no stamp and no run bound: passes" "$(stop s-other 'Done.')" ""
out=$(stop s-5 'Done.')
check "auto run without a turn stamp: held" "$(decision "$out")" "block"
check "auto run without a turn stamp: the count is kept" "$(cat "$HOME/.claude/dforge/sessions/turns/s-5.holds")" "1"
H2="$TMP/home-turns-is-a-file"
mkdir -p "$H2/.claude/dforge/sessions"
printf 'not a directory\n' > "$H2/.claude/dforge/sessions/turns"
out=$(HOME="$H2" stop s-5 'Done.' true)
check "a hold count that cannot be written: the run stops" "$(jq -r .active "$STATE"):$(jq -r .stopped "$STATE" | grep -c 'without its sentinel')" "false:1"
check "a hold count that cannot be written: one hold asks for the attended ending" "$(jq -r .reason <<<"$out" | grep -c '§Stopping')" "1"

# --- progress kept in darkmem: the mirror's ledgers are the ones read ---
. "$HERE/fixtures/darkmem-stores.sh"
M=$(stores_home "$HOME" "$REPO" proj local darkmem)
mkdir -p "$M/work/sdd/2026-10-10-mirror" "$REPO/.dforge/sdd/2026-10-10-mirror"
sleep 1; prompt s-2; sleep 1
printf '# SDD ledger — plan: docs/dforge/plans/2026-10-10-mirror.md\nTask 1: complete (commits a..b, review clean)\n' > "$M/work/sdd/2026-10-10-mirror/progress.md"
out=$(stop s-2 'Task 1 is done.')
check "darkmem progress: a mirror ledger blocks a bare summary" "$(decision "$out")" "block"
check "darkmem progress: names the plan" \
  "$(jq -r .reason <<<"$out" | grep -c 'scripts/next-step" docs/dforge/plans/2026-10-10-mirror.md')" "1"
mkdir -p "$M/work/sdd/2026-10-11-other"
sleep 1; prompt s-3; sleep 1
printf '# SDD ledger — plan: docs/dforge/plans/2026-10-11-other.md\nTask 1: complete (commits a..b, review clean)\n' > "$M/work/sdd/2026-10-11-other/progress.md"
check "darkmem progress: another worktree's ledger does not block" "$(stop s-3 'Task 1 is done.')" ""
rm -f "$HOME/.dforge/config.json" "$HOME/.dforge/stores.json"

# --- a branch moved without a plan's ledger is not held ---
commit_in() { git -C "$1" -c user.name=t -c user.email=t@example.invalid commit -q --allow-empty -m "$2"; }
UT="$TMP/unplanned.jsonl"
mkdir -p "$REPO/docs/dforge"
sleep 1; prompt s-4
jq -nc --arg t "$(date -u +%Y-%m-%dT%H:%M:%S.999Z)" \
  '{type:"assistant",timestamp:$t,message:{content:[{type:"tool_use",id:"toolu_s",name:"Skill",input:{skill:"dforge:test-driven-development"}}]}}' > "$UT"
check "turn-start records the branch heads" \
  "$([ -f "$HOME/.claude/dforge/sessions/turns/s-4.refs" ] && echo yes || echo no)" "yes"
commit_in "$REPO" adhoc
check "a dforge turn that committed without a plan: passes" "$(stop s-4 'Fixed and committed.' false "$UT")" ""
sleep 1; prompt s-4 "$outside"
check "a prompt outside git records no heads" \
  "$([ -f "$HOME/.claude/dforge/sessions/turns/s-4.refs" ] && echo yes || echo no)" "no"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
