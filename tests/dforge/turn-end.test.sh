#!/usr/bin/env bash
# The UserPromptSubmit hook stamps each turn; the Stop hook blocks a stop once
# when that turn wrote a plan's ledger and the last message carries neither the
# finishing menu nor the next-step block. Everything else passes silently.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
START="$HERE/../../plugins/dforge/scripts/turn-start.sh"
END="$HERE/../../plugins/dforge/scripts/turn-end.sh"
HOOKS="$HERE/../../plugins/dforge/hooks/hooks.json"
# The plugin root as turn-end.sh shows it in a hold reason.
SHOWN="$(cd "$HERE/../../plugins/dforge" && pwd)"
if command -v cygpath >/dev/null 2>&1; then SHOWN=$(cygpath -m "$SHOWN"); fi

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}

TMP="$(mktemp -d)"
export WORKFLOW_GUARD_CLAUDE_DIR="$TMP/workflow-guard" WORKFLOW_GUARD_MANAGED_DIR="$TMP/workflow-guard" WORKFLOW_GUARD_PROJECT_DIR="$TMP/workflow-guard"
trap 'cd / && rm -rf "$TMP"' EXIT
# The session-state readers log under the checkout of the working directory:
# run from TMP so the hooks never write this repository's .dforge/.
cd "$TMP" || exit 1
export HOME="$TMP/home"; mkdir -p "$HOME"
. "$HERE/fixtures/cockpit-ack.sh"
cockpit_ack_start "$HOME"
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
LATEST="$REPO/.dforge/handoff/stored.md"
# A handoff as scripts/next-step writes it, after the turn's stamp: a block in
# the stop message releases a ledger turn only with that file's Next line.
wrote_next() { # wrote_next [Next text]
  sleep 1
  mkdir -p "${LATEST%/*}"
  printf '# Handoff\n\n## Next session\n\n**Status:** x\n**Next:** %s\n' "${1:-x}" > "$LATEST"
}
# The turn record next-step writes for a session (C13): the Status and Next
# lines of the block it printed, written or not.
turn_rec() { # turn_rec <session> <Status> <Next>
  local f
  f="$HOME/.claude/dforge/sessions/turns/$(printf '%s' "$1" | tr -c 'A-Za-z0-9' '-').next"
  sleep 1; mkdir -p "${f%/*}"; printf 'status=%s\nnext=%s\n' "$2" "$3" > "$f"
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
# The scan reads the whole transcript, so a stop nothing could hold skips it.
SHIM="$TMP/shim"; mkdir -p "$SHIM"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "%s"\nexec "%s" "$@"\n' "$TMP/jq.log" "$(command -v jq)" > "$SHIM/jq"
chmod +x "$SHIM/jq"
TR0="$TMP/plain.jsonl"
jq -nc '{type:"assistant",message:{content:[{type:"text",text:"Here is the answer."}]}}' > "$TR0"
scans() { : > "$TMP/jq.log"; PATH="$SHIM:$PATH" stop "$@" >/dev/null; grep -c -- '--arg since' "$TMP/jq.log"; }
check "no ledger write this turn: the transcript is not scanned" "$(scans s-1 'Here is the answer.' false "$TR0")" "0"

# --- mid-plan, summary without the block ---
write_ledger 'Task 1: complete (commits a..b, review clean)'
out=$(stop s-1 'Task 1 is done. Everything looks good.')
check "mid-plan summary: blocks" "$(decision "$out")" "block"
check "mid-plan summary: the transcript is scanned" "$([ "$(scans s-1 'Task 1 is done.' false "$TR0")" -gt 0 ] && echo yes || echo no)" "yes"
check "mid-plan summary: names next-step and the plan" \
  "$(jq -r .reason <<<"$out" | grep -c 'scripts/next-step" docs/superpowers/plans/2026-10-08-example.md')" "1"
check "mid-plan summary: the plugin root is quoted" \
  "$(jq -r .reason <<<"$out" | grep -cF "\`bash \"$SHOWN/scripts/next-step\" docs/superpowers/plans/2026-10-08-example.md\`")" "1"
check "mid-plan summary: tells the user why" "$(jq -r .systemMessage <<<"$out" | grep -c 'dforge held the stop')" "1"
# The checkout path is the caller's, so only the hook's own words are capped.
check "mid-plan summary: the reason stays short" "$(r=$(jq -r .reason <<<"$out"); r=${r//"$SHOWN"/}; [ "${#r}" -lt 360 ] && echo short || echo "long: ${#r}")" "short"
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
check "mid-plan summary: names the waiting line for a question" "$(jq -r .reason <<<"$out" | grep -c 'scripts/ask')" "1"

# --- one of the stops that asks the human, mid-plan ---
# The session is not over: the answer arrives as the next prompt.
write_ledger $'Task 16: implementer inline (assigned; base abc1234)\nTask 16: waiting — run the paid model generation (about $7, cap $20)?'
check "a waiting line ends the ledger: the question passes" "$(stop s-1 'Should I run the model generation?')" ""
write_ledger $'Task 16: waiting — run the paid model generation?\nTask 16: fix round 1/3 (a test; passing)'
check "a waiting line the work moved past: a summary blocks" "$(decision "$(stop s-1 'Task 16 is done.')")" "block"

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
  | bash "$HERE/../../plugins/dforge/scripts/session-start.sh" >/dev/null
check "session-start records the resume time" \
  "$([ -f "$HOME/.claude/dforge/sessions/turns/s-1.since" ] && echo yes || echo no)" "yes"
check "launch from before the resume: passes" "$(stop s-1 "$NEXT" false "$BG")" ""
jq -nc '{type:"user",timestamp:"2999-01-01T00:00:00.000Z",message:{role:"user",content:[{type:"tool_result",tool_use_id:"toolu_new",content:"Command running in background with ID: n1."}]}}' >> "$BG"
check "launch after the resume: holds" "$(decision "$(stop s-1 "$NEXT" false "$BG")")" "block"
before=$(cat "$HOME/.claude/dforge/sessions/turns/s-1.since")
sleep 1
jq -n --arg tp "$BG" --arg cwd "$REPO" '{session_id:"s-1",transcript_path:$tp,cwd:$cwd,source:"compact"}' \
  | bash "$HERE/../../plugins/dforge/scripts/session-start.sh" >/dev/null
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
  | HOME="$H3" bash "$HERE/../../plugins/dforge/scripts/session-start.sh" >/dev/null
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
  | HOME= PATH="$SHIM:$PATH" bash "$HERE/../../plugins/dforge/scripts/session-start.sh")
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
check "hooks.json: the turn-start hook is bounded at 30 s" \
  "$(jq -r '.hooks.UserPromptSubmit[0].hooks[0].timeout' "$HOOKS")" "30"

# --- an auto run bound to the session ends its turns only on the sentinel ---
AR="$HERE/../../plugins/dforge/scripts/auto-run"
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

# --- hold_books_total ---
date +%s > "$HOME/.claude/dforge/sessions/cockpit/s-6"
(cd "$REPO" && bash "$AR" --session s-6 start --spec docs/s.md --register docs/r.md --force >/dev/null)
check "hold_books_total: a new run starts with no holds" "$(jq -r .totals.holds "$STATE")" "0"
stop s-6 'Done.' >/dev/null
check "hold_books_total: a Stop hold adds one" "$(jq -r .totals.holds "$STATE")" "1"
stop s-6 'Done.' true >/dev/null
check "hold_books_total: a held retry adds another" "$(jq -r .totals.holds "$STATE")" "2"
pend compact
stop s-6 $'Done.\n\nAuto run: compacting' >/dev/null
check "hold_books_total: a sentinel ending books nothing" "$(jq -r .totals.holds "$STATE")" "2"
stop s-other 'Done.' >/dev/null
check "hold_books_total: another session's stop books nothing" "$(jq -r .totals.holds "$STATE")" "2"

# --- progress kept in darkmem: the mirror's ledgers are the ones read ---
# --- a running service does not pass a plain stop (row 12) ---
SVC="$TMP/service.jsonl"
jq -nc '{type:"assistant",message:{role:"assistant",content:[{type:"tool_use",id:"toolu_dev",name:"Bash",input:{description:"Dev server",command:"npm run dev",run_in_background:true}}]}}' > "$SVC"
jq -nc '{type:"user",message:{role:"user",content:[{type:"tool_result",tool_use_id:"toolu_dev",content:"Command running in background with ID: d1. Output is being written to: /tmp/d1.output."}]}}' >> "$SVC"
sleep 1; prompt s-svc
write_ledger 'Task 1: complete (commits a..b, review clean)'
check "a service alone: a mid-plan summary stop is held" "$(decision "$(stop s-svc 'Task 1 is done.' false "$SVC")")" "block"
wrote_next
check "a service alone: the next-step block passes" "$(stop s-svc $'## Next session\n\n**Status:** x\n**Next:** x' false "$SVC")" ""

# --- a clean line older than the code is not current (row 3) ---
h7=$(git -C "$REPO" rev-parse --short HEAD)
printf 'x\n' > "$REPO/code.txt"
git -C "$REPO" add code.txt && git -C "$REPO" -c user.name=t -c user.email=t@example.invalid commit -qm "fix: later"
sleep 1; prompt s-stale
write_ledger "Final review: clean (commits 0000000..$h7)"
out=$(stop s-stale 'All done.')
check "a stale clean line: held" "$(decision "$out")" "block"
check "a stale clean line: not sent to the finishing menu" "$(jq -r .reason <<<"$out" | grep -c 'passed its final review')" "0"

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

# --- only the block next-step wrote this turn releases a ledger turn (rows 2, 8) ---
wrote_next 'Resume at Task 2.'
sleep 1; prompt s-nx
write_ledger 'Task 1: complete (commits a..b, review clean)'
HAND=$'Done.\n\n## Next session\n\n**Next:** Resume at Task 2.'
check "a hand-typed block does not release a ledger turn" "$(decision "$(stop s-nx "$HAND")")" "block"
turn_rec s-nx 'Plan p: 1 of 3 tasks complete.' 'Resume at Task 2.'
check "the session's turn record releases a ledger turn on its Next line" "$(stop s-nx "$HAND")" ""
turn_rec s-nx 'Plan p: 1 of 3 tasks complete.' 'Resume at Task 3.'
check "a record with another Next line does not release it" "$(decision "$(stop s-nx "$HAND")")" "block"
. "$HERE/../../plugins/dforge/scripts/lib/next-ending.sh"
check "no session id: no turn record" "$(ending_turn_record '')" ""
check "the turn record sits beside the stamp" "$(ending_turn_record 's/1')" "$HOME/.claude/dforge/sessions/turns/s-1.next"

# --- a turn that merges a plan or closes a milestone ends on next-step (rows 2, 7) ---
stop_at() { # stop_at <session> <cwd> <last message> [stop_hook_active]
  jq -n --arg sid "$1" --arg cwd "$2" --arg msg "$3" --argjson active "${4:-false}" \
    '{hook_event_name:"Stop",session_id:$sid,cwd:$cwd,transcript_path:"",stop_hook_active:$active,last_assistant_message:$msg}' | bash "$END"
}
commit_all() { git -C "$1" add -A && git -C "$1" -c user.name=t -c user.email=t@example.invalid commit -qm "$2"; }
TRP="$TMP/transitions"
git init -q "$TRP"
mkdir -p "$TRP/docs/dforge/plans"
printf '# Completed plans\n\n- 2026-11-01 `docs/dforge/plans/2026-11-01-old.md` — merged into `main`\n' > "$TRP/docs/dforge/plans/completed.md"
milestone() { printf '| %s | %s | it works | `docs/dforge/registers/%s.md` | %s | - |\n' "$1" "$2" "$1" "$3"; }
{ printf '# Roadmap\n\n| M | Name | Exit | Register | State | Note |\n|---|---|---|---|---|---|\n'; milestone M1 One open; milestone M2 Two open; } > "$TRP/docs/dforge/roadmap.md"
commit_all "$TRP" 'docs: roadmap'
git -C "$TRP" worktree add -q "$TMP/wt-p" -b feature
sleep 1; prompt s-tr1 "$TMP/wt-p"
sleep 1
printf -- '- 2026-11-16 `docs/dforge/plans/2026-11-16-p.md` — merged into `main`\n' >> "$TRP/docs/dforge/plans/completed.md"
commit_all "$TRP" 'docs: record p'
git -C "$TRP" worktree remove --force "$TMP/wt-p"
out=$(stop_at s-tr1 "$TMP/wt-p" 'Merged.')
check "a finishing turn in a removed worktree is held" "$(decision "$out")" "block"
check "a finishing turn in a removed worktree: names next-step --complete and the plan" \
  "$(jq -r .reason <<<"$out" | grep -c 'next-step" --complete docs/dforge/plans/2026-11-16-p.md')" "1"
sleep 1; prompt s-tr6 "$TRP"
sleep 1
printf -- '- 2026-11-16 `x.md; rm -rf ~` — merged\n' >> "$TRP/docs/dforge/plans/completed.md"
commit_all "$TRP" 'docs: a hostile entry'
out=$(stop_at s-tr6 "$TRP" 'Merged.')
check "a plan name that is not a plain path is not repeated" "$(jq -r .reason <<<"$out" | grep -c 'rm -rf')" "0"
check "a plan name that is not a plain path: the placeholder stands" "$(jq -r .reason <<<"$out" | grep -c -- '--complete PLAN_FILE')" "1"
sleep 1; prompt s-tr1 "$TMP/wt-p"
check "a later turn still finds the primary" "$(head -n 1 "$HOME/.claude/dforge/sessions/turns/s-tr1.refs")" \
  "$(git -C "$TRP" rev-parse --path-format=absolute --git-common-dir)"

sleep 1; prompt s-tr2 "$TRP"
sleep 1
sed 's/| M1 | One | \(.*\) | open |/| M1 | One | \1 | closed |/' "$TRP/docs/dforge/roadmap.md" > "$TMP/roadmap.md" && mv "$TMP/roadmap.md" "$TRP/docs/dforge/roadmap.md"
commit_all "$TRP" 'docs: close M1'
out=$(stop_at s-tr2 "$TRP" 'M1 closed.')
check "a turn that closes a milestone is held once" "$(decision "$out")" "block"
check "a turn that closes a milestone: names next-step --project" "$(jq -r .reason <<<"$out" | grep -c 'next-step" --project')" "1"
check "a turn that closes a milestone: the retry passes" "$(stop_at s-tr2 "$TRP" 'M1 closed.' true)" ""

SECOND="$TMP/transitions-2"
git clone -q "$TRP" "$SECOND"
sed 's/| M2 | Two | \(.*\) | open |/| M2 | Two | \1 | closed |/' "$SECOND/docs/dforge/roadmap.md" > "$TMP/roadmap.md" && mv "$TMP/roadmap.md" "$SECOND/docs/dforge/roadmap.md"
printf -- '- 2026-11-16 `docs/dforge/plans/2026-11-16-q.md` — merged into `main`\n' >> "$SECOND/docs/dforge/plans/completed.md"
commit_all "$SECOND" 'docs: close M2, record q'
sleep 1; prompt s-tr3 "$TRP"
sleep 1
git -C "$TRP" pull -q --ff-only "$SECOND" HEAD
check "a pull that moves the roadmap is not held" "$(stop_at s-tr3 "$TRP" 'Pulled.')" ""

sleep 1; prompt s-tr4 "$TRP"
sleep 1
milestone M3 Three open >> "$TRP/docs/dforge/roadmap.md"
commit_all "$TRP" 'docs: add M3'
check "a design turn that edits the roadmap is not held" "$(stop_at s-tr4 "$TRP" 'Added M3.')" ""
sleep 1; prompt s-tr1 "$TMP/wt-p"
sleep 1
milestone M4 Four open >> "$TRP/docs/dforge/roadmap.md"
commit_all "$TRP" 'docs: add M4'
check "a turn in a removed worktree that edits the roadmap is not held" "$(stop_at s-tr1 "$TMP/wt-p" 'Added M4.')" ""

sleep 1; prompt s-tr5 "$TRP"
check "nothing changed, nothing held" "$(stop_at s-tr5 "$TRP" 'Done.')" ""

# --- darkmem documents: the roadmap lives in the mirror, outside git ---
. "$HERE/fixtures/darkmem-stores.sh"
DMR="$TMP/dm-roadmap"; git init -q "$DMR"
DMM=$(stores_home "$HOME" "$DMR" proj9 darkmem local)
mkdir -p "$DMM/dforge"
{ printf '# Roadmap\n\n| M | Name | Exit | Register | State | Note |\n|---|---|---|---|---|---|\n'; milestone M1 One open; milestone M2 Two open; } > "$DMM/dforge/roadmap.md"
sleep 1; prompt s-dm "$DMR"
stop_at s-dm "$DMR" 'Done.' >/dev/null
sleep 1; prompt s-dm "$DMR"
sleep 1
milestone M3 Three open >> "$DMM/dforge/roadmap.md"
check "darkmem documents: a roadmap edit that closes nothing passes" "$(stop_at s-dm "$DMR" 'Added M3.')" ""
sleep 1; prompt s-dm "$DMR"
sleep 1
sed 's/| M1 | One | \(.*\) | open |/| M1 | One | \1 | closed |/' "$DMM/dforge/roadmap.md" > "$TMP/roadmap.md" && mv "$TMP/roadmap.md" "$DMM/dforge/roadmap.md"
out=$(stop_at s-dm "$DMR" 'M1 closed.')
check "darkmem documents: a milestone closed since the last stop is held once" \
  "$(decision "$out")|$(jq -r .reason <<<"$out" | grep -c 'next-step" --project')" "block|1"
rm -f "$HOME/.dforge/config.json" "$HOME/.dforge/stores.json"

# A transition turn is released by the block next-step wrote, by finishing's
# menu, and by nothing hand-typed; an uncommitted index edit counts as its own.
TRL="$TRP/.dforge/handoff/stored.md"
record() { printf -- '- 2026-11-16 `docs/dforge/plans/2026-11-16-%s.md` — merged into `main`\n' "$1" >> "$TRP/docs/dforge/plans/completed.md"; }
NB=$'Merged.\n\n## Next session\n\n**Next:** Nothing — no register holds an unresolved row.'
sleep 1; prompt s-tr7 "$TRP"
sleep 1; record r; commit_all "$TRP" 'docs: record r'
turn_rec s-tr7 'Plan p is complete.' 'Nothing — no register holds an unresolved row.'
check "terminal_complete_released: a finishing turn ending on its printed, unwritten terminal block passes" "$(stop_at s-tr7 "$TRP" "$NB")" ""
check "terminal_complete_released: no handoff was written" "$([ -e "$TRL" ] && echo yes || echo no)" "no"
sleep 1; prompt s-tr8 "$TRP"
sleep 1; record s; commit_all "$TRP" 'docs: record s'
check "a finishing turn ending on a hand-typed block is held" "$(decision "$(stop_at s-tr8 "$TRP" "$NB")")" "block"
sleep 1; prompt s-tr9 "$TRP"
sleep 1; record t
out=$(stop_at s-tr9 "$TRP" 'Recorded.')
check "an uncommitted completed.md entry this turn is held" "$(decision "$out")" "block"
check "an uncommitted completed.md entry names its plan" \
  "$(jq -r .reason <<<"$out" | grep -c 'next-step" --complete docs/dforge/plans/2026-11-16-t.md')" "1"
commit_all "$TRP" 'docs: record t'
sleep 1; prompt s-tr10 "$TRP"
sleep 1; record u
sleep 1; prompt s-tr11 "$TRP"
sleep 1; record w; commit_all "$TRP" 'docs: record w'
turn_rec s-tr11 'Plan w is complete.' 'Nothing — no register holds an unresolved row.'
check "terminal_complete_released: next-step run after the record is not held by the transition test" "$(stop_at s-tr11 "$TRP" 'All merged.')" ""
check "a transition turn ending on finishing's menu is not held" \
  "$(stop_at s-tr10 "$TRP" $'1. Merge back to main locally\n2. Keep as-is\n\nWhich option?')" ""
commit_all "$TRP" 'docs: record u'

# --- per-worktree handoffs (spec A7, A16) ---
git -C "$REPO" -c user.name=t -c user.email=t@example.invalid commit -q --allow-empty -m base
WTD="$TMP/wt-hand"; git -C "$REPO" worktree add -q -b wt-hand "$WTD"
WT_LATEST="$WTD/.dforge/handoff/stored.md"; mkdir -p "${WT_LATEST%/*}"
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
turn_rec s-wd 'Own status' 'Own next.'
wt_block 'other' 'Other next.'
check "released_on_own_record_after_other_write: S1's block is released after S2's later write" "$(stop s-wd $'## Next session\n\n**Next:** Own next.')" ""
prompt s-wj; write_ledger 'Task 1: complete (commits a..b, review clean)'
turn_rec s-wk 'S2 status' 'S2 next.'
check "hand_typed_other_next_held: S1 carrying only S2's Next line is held" "$(decision "$(stop s-wj $'## Next session\n\n**Next:** S2 next.')")" "block"
prompt s-wl; write_ledger 'Task 1: complete (commits a..b, review clean)'
wt_block 'codex status' 'Codex next.'
check "released_by_other_handoff_without_record: no record, another handoff's Status and Next this turn" \
  "$(stop s-wl $'## Next session\n\n**Status:** codex status\n**Next:** Codex next.')" ""
prompt s-we; write_ledger 'Task 1: complete (commits a..b, review clean)'
wt_block 'other' 'Run dforge:finishing-a-development-branch.'
check "A16: another checkout's Next line alone does not release" "$(decision "$(stop s-we $'## Next session\n\n**Next:** Run dforge:finishing-a-development-branch.')")" "block"
wt_block 'stale wt' 'Resume at Task 3 (Stale).'
sleep 1; prompt s-wi; write_ledger 'Task 1: complete (commits a..b, review clean)'
STALE=$'## Next session\n\n**Status:** stale wt\n**Next:** Resume at Task 3 (Stale).'
check "A16: another checkout's block written before the turn does not release" "$(decision "$(stop s-wi "$STALE")")" "block"
wt_block 'stale wt' 'Resume at Task 3 (Stale).'
check "A16: the same block rewritten this turn releases" "$(stop s-wi "$STALE")" ""
prompt s-wf
mkdir -p "$REPO/docs/dforge/plans"; sleep 1
printf -- '- 2026-11-18 `docs/dforge/plans/2026-11-18-x.md` — merged into `main`\n' >> "$REPO/docs/dforge/plans/completed.md"
wt_block 'other' 'Other next.'
check "A16: a completed plan stays held after another worktree writes" "$(decision "$(stop s-wf 'All done.')")" "block"
. "$HERE/fixtures/darkmem-stores.sh"
MIRROR=$(stores_home "$HOME" "$REPO" demo local darkmem)
mkdir -p "$MIRROR/work/sdd/2026-10-12-dm" "$REPO/.dforge/sdd/2026-10-12-dm"
dm_ledger() { sleep 1; printf '# SDD ledger — plan: docs/dforge/plans/2026-10-12-dm.md\nTask 1: complete (commits a..b, review clean)\n' > "$MIRROR/work/sdd/2026-10-12-dm/progress.md"; }
prompt s-wg; dm_ledger
check "A7: darkmem: a mirror ledger holds the primary turn" "$(decision "$(stop s-wg 'Task 1 is done.')")" "block"
prompt s-wh; dm_ledger
wt_block 'dm wt' 'Resume at Task 2 (Dm).'
check "A7: darkmem: a linked worktree's local block releases" "$(stop s-wh $'## Next session\n\n**Status:** dm wt\n**Next:** Resume at Task 2 (Dm).')" ""
prompt s-wi; dm_ledger
sleep 1; printf '# Handoff\n\n## Next session\n\n**Status:** mirror status\n**Next:** Mirror next.\n' > "$MIRROR/work/handoff/2026-10-12-dm.md"
check "A7: darkmem: the mirror's block written this turn releases" "$(stop s-wi $'## Next session\n\n**Status:** mirror status\n**Next:** Mirror next.')" ""
rm -rf "$REPO/.dforge/sdd/2026-10-12-dm"
rm -f "$HOME/.dforge/config.json" "$HOME/.dforge/stores.json"

# --- binding: the session's run lives in RB; the hook runs in RA ---
RA="$TMP/ra" RB="$TMP/rb" NOGIT="$TMP/nogit"
for r in "$RA" "$RB"; do
  git init -q "$r"
  git -C "$r" -c user.name=t -c user.email=t@example.invalid commit -q --allow-empty -m init
done
mkdir -p "$NOGIT"
date +%s > "$HOME/.claude/dforge/sessions/cockpit/s-h"
(cd "$RB" && bash "$AR" --session s-h start --spec docs/s.md --register docs/r.md >/dev/null)
BSTATE="$RB/.dforge/sdd/auto-run.json" ASTATE="$RA/.dforge/sdd/auto-run.json"
BIND="$HOME/.claude/dforge/sessions/run/s-h.json" BYID="$HOME/.claude/dforge/sessions/by-id/s-h.json"
setj() { jq "$2" "$1" > "$1.tmp" && mv "$1.tmp" "$1"; }
has_reason() { jq -r --arg t "$2" '(.reason // "") | contains($t)' <<<"${1:-{\}}" 2>/dev/null; }
setj "$BSTATE" '.pending = "compact"'
o=$(stop_in "$RA" s-h 'Done.')
check "binding: holds a turn without its sentinel (A1)" "$(decision "$o"):$(has_reason "$o" 'pending: compact')" "block:true"
check "binding: books the hold in B" "$(jq -r '.totals.holds' "$BSTATE")" "1"
o=$(stop_in "$RA" s-h $'Done.\n\nAuto run: compacting'); status=$?
check "binding: passes a turn that ends on its sentinel (A1)" "$status:$o" "0:"
o=$(stop_in "$NOGIT" s-h 'Done.')
check "binding: holds from outside any repository (A1)" "$(decision "$o"):$(has_reason "$o" 'pending: compact')" "block:true"

no_binding() { mv "$BIND" "$BIND.away"; stop_in "$RA" s-h 'Done.'; mv "$BIND.away" "$BIND"; }
setj "$BSTATE" '.active = false'
check "binding: a stopped run changes nothing (A1)" "$(stop_in "$RA" s-h 'Done.')" "$(no_binding)"
setj "$BSTATE" '.active = true | .session = "s-other"'
check "binding: a run bound to another session changes nothing" "$(stop_in "$RA" s-h 'Done.')" "$(no_binding)"
setj "$BSTATE" '.session = "s-h"'

mkdir -p "${BYID%/*}"
jq -n --arg c "$RA" '{cwd: $c}' > "$BYID"
o1=$(stop_in "$RA" s-h 'Done.')
jq -n --arg c "$RB" '{cwd: $c}' > "$BYID"
o2=$(stop_in "$RA" s-h 'Done.')
check "binding: the hold message names the checkout (A44)" "$(has_reason "$o1" "cd '$RB' &&"):$(has_reason "$o2" "cd '")" "true:false"
rm -f "$BYID"

(cd "$RA" && bash "$AR" --session s-h start --spec docs/a.md --register docs/r.md >/dev/null)
setj "$ASTATE" '.pending = "clear"'
jq -n --arg p "$RB" '{primary: $p, nonce: "n", at: 0}' > "$BIND"
cp "$BSTATE" "$TMP/b.before"
o=$(stop_in "$RA" s-h 'Done.')
check "binding: a local run of the session wins" \
  "$(has_reason "$o" 'pending: clear'):$(jq -r '.totals.holds' "$ASTATE"):$(cmp -s "$BSTATE" "$TMP/b.before" && echo same)" "true:1:same"

# --- a budget note said handoff: the turn ends on next-step's block, plan or not ---
# The cockpit writes `due` beside the turn stamp when it tells the model to hand
# off, and empties the file when the note no longer stands.
HO="$TMP/handoff-repo"
git init -q "$HO"
handoff_due() { # handoff_due <session> <content>
  mkdir -p "$HOME/.claude/dforge/sessions/turns"
  printf '%s' "$2" > "$HOME/.claude/dforge/sessions/turns/$1.handoff"
}
stop_ho() { # stop_ho <session> <last message> [stop_hook_active] [transcript]
  jq -n --arg sid "$1" --arg cwd "$HO" --arg msg "$2" --argjson active "${3:-false}" --arg tp "${4:-}" \
    '{hook_event_name:"Stop",session_id:$sid,cwd:$cwd,transcript_path:$tp,stop_hook_active:$active,last_assistant_message:$msg}' | bash "$END"
}
POINTER='Done. Start a fresh session to continue the fixes.'
sleep 1; prompt s-ho "$HO"
check "no handoff marker: a no-plan ending passes silently" "$(stop_ho s-ho "$POINTER" 2>&1)" ""
handoff_due s-ho ''
check "an emptied handoff marker: a no-plan ending passes" "$(stop_ho s-ho "$POINTER")" ""
handoff_due s-ho due
out=$(stop_ho s-ho "$POINTER")
check "handoff due: a no-plan ending without the block is held" "$(decision "$out")" "block"
check "handoff due: names the handoff skill, next-step and ask" \
  "$(r=$(jq -r .reason <<<"$out"); for w in 'dforge:handoff' 'next-step' 'scripts/ask'; do grep -qF -- "$w" <<<"$r" && printf y || printf n; done)" "yyy"
check "handoff due: tells the user why" "$(jq -r .systemMessage <<<"$out" | grep -c 'a budget note said handoff')" "1"
check "handoff due: the retry passes" "$(stop_ho s-ho "$POINTER" true)" ""
HO_BLOCK=$'Done.\n\n## Next session\n\n**Status:** Unplanned work.\n**Next:** Continue the fixes.'
check "handoff due: a hand-typed block is held" "$(decision "$(stop_ho s-ho "$HO_BLOCK")")" "block"
turn_rec s-ho 'Unplanned work.' 'Continue the fixes.'
check "handoff due: the block next-step wrote this turn passes" "$(stop_ho s-ho "$HO_BLOCK")" ""
sleep 1; prompt s-ho "$HO"
check "handoff due: still held on the next turn" "$(decision "$(stop_ho s-ho "$POINTER")")" "block"
sleep 1; : > "$HOME/.claude/dforge/sessions/turns/s-ho.asked"
check "handoff due: a question asked through scripts/ask passes" "$(stop_ho s-ho 'Should I hand off now?')" ""
sleep 1; prompt s-ho "$HO"
HO_BG="$TMP/handoff-bg.jsonl"
jq -nc '{type:"user",message:{role:"user",content:[{type:"tool_result",tool_use_id:"toolu_hb",content:"Command running in background with ID: hb1. Output is being written to: /tmp/hb1.output."}]}}' > "$HO_BG"
check "handoff due: a plain stop over running work passes" "$(stop_ho s-ho 'Waiting on the build.' false "$HO_BG")" ""
check "handoff due: the finishing menu passes" "$(stop_ho s-ho 'Which option?')" ""
sleep 1; prompt s-hp
handoff_due s-hp due
write_ledger 'Task 1: complete (commits a..b, review clean)'
out=$(stop s-hp 'Task 1 is done.')
check "handoff due, a plan advanced: the plan's own reason stands" \
  "$(jq -r .reason <<<"$out" | grep -c 'advanced without a next step'):$(jq -r .reason <<<"$out" | grep -c 'budget note')" "1:0"

# --- a native jq ends its output lines with CR (Git Bash): the hooks strip it ---
CRJQ="$TMP/crjq"; mkdir -p "$CRJQ"
cat > "$CRJQ/jq" <<CRJQ_EOF
#!/usr/bin/env bash
"$(command -v jq)" "\$@" | sed 's/\$/\r/'
exit "\${PIPESTATUS[0]}"
CRJQ_EOF
chmod +x "$CRJQ/jq"
sleep 1; PATH="$CRJQ:$PATH" prompt s-cr
check "a jq that ends lines with CR: turn-start stamps the clean id" \
  "$([ -f "$HOME/.claude/dforge/sessions/turns/s-cr" ] && echo yes || echo no)" "yes"
write_ledger 'Task 1: complete (commits a..b, review clean)'
out=$(PATH="$CRJQ:$PATH" stop s-cr 'Task 1 is done.')
check "a jq that ends lines with CR: a mid-plan summary is still held" "$(decision "$(tr -d '\r' <<<"$out")")" "block"


printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
