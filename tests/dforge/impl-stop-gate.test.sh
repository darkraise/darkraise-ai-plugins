#!/usr/bin/env bash
# scripts/impl-stop-gate: the SubagentStop hook that holds an implementer
# seat's reply until the report its Report: line names exists and opens with
# ## Verdict (C11). The input is shaped as Claude Code 2.1.312 sends it
# (tests/fixtures/subagent-stop-input.json).
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATE="$HERE/../../plugins/dforge/scripts/impl-stop-gate"
PATHS="$HERE/../../plugins/dforge/scripts/dforge-path"
HOOKS="$HERE/../../plugins/dforge/hooks/hooks.json"
FIXTURE="$HERE/fixtures/subagent-stop-input.json"

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}

TMP="$(mktemp -d)"
export WORKFLOW_GUARD_CLAUDE_DIR="$TMP/workflow-guard" WORKFLOW_GUARD_MANAGED_DIR="$TMP/workflow-guard" WORKFLOW_GUARD_PROJECT_DIR="$TMP/workflow-guard"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME"
unset CLAUDE_CONFIG_DIR CLAUDE_CODE_SESSION_ID AR_SESSION DFORGE_BUDGET CLAUDE_PROJECT_DIR XDG_STATE_HOME

fjq() { MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' jq "$@"; }

REPO="$TMP/repo"
git init -q "$REPO"
STATE=$(cd "$REPO" && bash "$PATHS" state | tr -d '\r')

input() { # input <agent_type> <agent_id> <message> — the hook input, run from the repository
  fjq -nc --arg t "$1" --arg i "$2" --arg m "$3" --arg c "$REPO" \
    '{session_id:"s-1",cwd:$c,hook_event_name:"SubagentStop",stop_hook_active:false,agent_id:$i,agent_type:$t,last_assistant_message:$m}'
}
gate() { # gate <json> — sets CODE, OUT and ERR
  OUT=$(bash "$GATE" <<<"$1" 2>"$TMP/err"); CODE=$?
  ERR=$(tr -d '\r' < "$TMP/err")
}
has() { grep -cF -- "$2" <<<"$1"; }

R="$TMP/report.md"
printf '## Verdict\npass: 1\n' > "$R"
GOOD="QA done: 1 pass.
Report: $R"
MISSING="Report: $TMP/missing.md"

# --- the gate stands aside ---
gate "$(input dforge:judge-opus a-judge "QA done.
$MISSING")"
check "another agent type passes" "$CODE|$OUT|$ERR" "0||"
gate "$(input general-purpose a-gp 'Report: /nonexistent/report.md')"
check "a general-purpose agent with a missing report passes" "$CODE|$OUT|$ERR" "0||"
gate "$(input dagents:impl-sonnet-medium a-dagents "$MISSING")"
check "another plugin's implementer with a missing report passes" "$CODE|$OUT|$ERR" "0||"
gate '{"agent_type":"dforge:impl-sonnet-high"'
check "malformed input passes" "$CODE|$OUT|$ERR" "0||"
gate "$(fjq -nc --arg m "QA done.
$MISSING" --arg c "$REPO" '{cwd:$c,agent_type:"dforge:impl-sonnet-high",last_assistant_message:$m}')"
check "input with no agent_id passes" "$CODE|$OUT|$ERR" "0||"

# --- the QA reply contract (C11) ---
printf '## Verdict\npass: 1\n' > "$R"
gate "$(input dforge:impl-sonnet-high q-1 "QA done: 1 pass.
Report: $R")"
check "a QA report that opens with ## Verdict passes" "$CODE|$OUT|$ERR" "0||"
gate "$(input dforge:impl-sonnet-high q-2 "QA done.
Report: $TMP/missing.md")"
check "a missing QA report blocks" "$CODE:$(has "$ERR" 'does not exist')" "2:1"
printf '# Notes\n## Verdict\n' > "$R"
gate "$(input dforge:impl-sonnet-high q-3 "QA done.
Report: $R")"
check "a report that does not open with ## Verdict blocks" "$CODE:$(has "$ERR" '## Verdict')" "2:1"
gate "$(input dforge:impl-sonnet-high w-1 'Walkthrough done; screenshots saved.')"
check "a reply with no Report line passes" "$CODE|$OUT|$ERR" "0||"

printf '## Verdict\npass: 1\n' > "$R"
gate "$(input impl-sonnet-high a-ok "$GOOD")"
check "an unprefixed agent type is checked too" "$CODE|$OUT|$ERR" "0||"
gate "$(input impl-sonnet-high a-miss "QA done.
Report: $TMP/missing.md")"
check "an unprefixed agent type with a missing report blocks" "$CODE:$(has "$ERR" 'does not exist')" "2:1"
check "a passing stop writes no counter" "$([ -e "$STATE/impl-stop-gate/a-ok" ] && echo yes || echo no)" "no"
printf '\n  \n## Verdict \npass: 1\n' > "$TMP/blank-first.md"
gate "$(input dforge:impl-sonnet-high a-blank "Report: $TMP/blank-first.md")"
check "blank lines before ## Verdict pass" "$CODE|$OUT|$ERR" "0||"
sed 's/$/\r/' "$R" > "$TMP/crlf.md"
gate "$(input dforge:impl-sonnet-high a-crlf $'QA done.\r\nReport: '"$TMP/crlf.md"$'\r')"
check "CRLF line endings pass" "$CODE|$OUT|$ERR" "0||"
gate "$(input dforge:impl-sonnet-high a-last "$(printf 'Report: %s\nlater text\nReport: %s' "$TMP/missing.md" "$R")")"
check "the last Report line wins" "$CODE|$OUT|$ERR" "0||"
gate "$(input dforge:impl-sonnet-high a-1 "QA done.
$MISSING")"
check "missing file: one stderr line naming it" "$CODE|$OUT|$(wc -l <<<"$ERR" | tr -d ' ')|$(has "$ERR" "impl-stop-gate: the report file \`$TMP/missing.md\` does not exist. Fix it, then end your reply again with its Report: line.")" "2||1|1"
gate "$(input dforge:impl-sonnet-high a-2 'Report: reports/qa.md')"
check "relative Report path: exit 2 naming it" "$CODE|$(has "$ERR" 'is not absolute')" "2|1"
printf '# Task 4\n\n## Verdict\n' > "$TMP/bare.md"
gate "$(input dforge:impl-sonnet-high a-3 "Report: $TMP/bare.md")"
check "a report opening with another line: exit 2 naming it" "$CODE|$(has "$ERR" "the report \`$TMP/bare.md\` does not open with \`## Verdict\`")" "2|1"

# --- the block counter ---
C="$STATE/impl-stop-gate/agent-1"
M1="First attempt.
$MISSING"
M2="Second attempt.
$MISSING"
M3="Third attempt.
$MISSING"
M4="Fourth attempt.
$MISSING"
gate "$(input dforge:impl-sonnet-high agent-1 "$M1")"
check "first stop blocks" "$CODE" "2"
check "the counter holds count 1" "$(sed -n 1p "$C")" "1"
H1=$(sed -n 2p "$C")
check "the counter holds a sha256" "$(grep -cE '^[0-9a-f]{64}$' <<<"$H1")" "1"
gate "$(input dforge:impl-sonnet-high agent-1 "$M1")"
check "the same stop again blocks" "$CODE" "2"
check "the same stop again does not raise the count" "$(sed -n 1p "$C")" "1"
check "a different agent id has its own counter" "$(gate "$(input dforge:impl-sonnet-high agent-2 "$M1")"; echo "$CODE|$(sed -n 1p "$STATE/impl-stop-gate/agent-2")")" "2|1"
gate "$(input dforge:impl-sonnet-high agent-1 "$M2")"
check "a second distinct stop blocks" "$CODE" "2"
check "the count is 2" "$(sed -n 1p "$C")" "2"
gate "$(input dforge:impl-sonnet-high agent-1 "$M2")"
check "the second stop fired twice still blocks" "$CODE" "2"
check "and the count stays 2" "$(sed -n 1p "$C")" "2"
check "no log before the pass-through" "$([ -e "$STATE/impl-stop-gate.log" ] && echo yes || echo no)" "no"
gate "$(input dforge:impl-sonnet-high agent-1 "$M3")"
check "the third distinct stop passes" "$CODE|$OUT|$ERR" "0||"
LOG="$STATE/impl-stop-gate.log"
check "the pass-through is logged once" "$(wc -l < "$LOG" | tr -d ' ')" "1"
check "the log line carries epoch, id, type and the last reason" \
  "$(grep -cE "^[0-9]+ agent-1 dforge:impl-sonnet-high pass-through after 2 blocks — the report file \`$TMP/missing.md\` does not exist$" "$LOG")" "1"
gate "$(input dforge:impl-sonnet-high agent-1 "$M3")"
check "the pass-through stop fired twice passes" "$CODE|$OUT|$ERR" "0||"
gate "$(input dforge:impl-sonnet-high agent-1 "$M4")"
check "a later stop of the same agent passes" "$CODE|$OUT|$ERR" "0||"
check "and neither adds a log line" "$(wc -l < "$LOG" | tr -d ' ')" "1"
gate "$(input dforge:impl-sonnet-high agent-3 "$M1")"
gate "$(input dforge:impl-sonnet-high agent-3 "$GOOD")"
check "a block followed by a complete report passes" "$CODE|$OUT|$ERR" "0||"

# --- a retry that repeats its reply word for word cannot loop for ever ---
C6="$STATE/impl-stop-gate/agent-rep"
R6=$(for i in 1 2 3 4 5 6; do gate "$(input dforge:impl-sonnet-high agent-rep "$M1")"; printf '%s ' "$CODE"; done)
check "the same failing reply six times: five blocks, then a pass" "$R6" "2 2 2 2 2 0 "
check "the repeats never raised the block count" "$(sed -n 1p "$C6")" "1"
check "the fire count is the fourth counter line" "$(sed -n 4p "$C6")" "6"
check "the pass-through is logged once, naming the cap" "$(grep -c 'agent-rep dforge:impl-sonnet-high pass-through after 5 fires — ' "$LOG")" "1"
gate "$(input dforge:impl-sonnet-high agent-rep "$M1")"
check "and the agent passes from then on" "$CODE|$OUT|$ERR" "0||"

# --- a gate that cannot do its job says so in a log ---
FALLBACK="$HOME/.local/state/dforge/impl-stop-gate.log"
check "the malformed input of the first checks was logged" "$(grep -c 'input is not JSON' "$FALLBACK")" "1"
check "a stop that the gate has no reason to look at logs nothing" "$(wc -l < "$FALLBACK" | tr -d ' ')" "1"
gate '{"agent_type":"dforge:impl-sonnet-high"'
check "unparseable input passes and is logged" "$CODE|$OUT|$ERR|$(grep -c 'input is not JSON' "$FALLBACK")" "0|||2"
NOJQ="$TMP/nojq"; mkdir -p "$NOJQ"
printf '#!/bin/sh\nexec "%s" "$@"\n' "$(command -v dirname)" > "$NOJQ/dirname"
chmod +x "$NOJQ/dirname"
OUT=$(PATH="$NOJQ" "$BASH" "$GATE" <<<"$(input dforge:impl-sonnet-high a-nojq "$GOOD")" 2>&1); CODE=$?
check "without jq the gate passes and is logged" "$CODE|$OUT|$(grep -c 'jq is not installed' "$FALLBACK")" "0||1"
REPO2="$TMP/repo2"
git init -q "$REPO2"
STATE2=$(cd "$REPO2" && bash "$PATHS" state | tr -d '\r')
mkdir -p "$STATE2" && : > "$STATE2/impl-stop-gate"
gate "$(fjq -nc --arg c "$REPO2" --arg m "All done.
$MISSING" '{cwd:$c,agent_id:"a-nostate",agent_type:"dforge:impl-sonnet-high",last_assistant_message:$m}')"
check "a counter that cannot be kept lets the stop through and logs why" "$CODE|$OUT|$ERR|$(grep -c 'a-nostate .*cannot keep the block counter' "$FALLBACK")" "0|||1"
gate "$(fjq -nc --arg m "All done.
$MISSING" '{cwd:"/nonexistent/dir",agent_id:"a-nocwd",agent_type:"dforge:impl-sonnet-high",last_assistant_message:$m}')"
check "a missing working directory lets the stop through and logs why" "$CODE|$OUT|$ERR|$(grep -c 'a-nocwd .*cannot enter /nonexistent/dir' "$FALLBACK")" "0|||1"

LINES0=$(wc -l < "$FALLBACK" | tr -d ' ')
gate "$(fjq -nc --arg m "All done.
$MISSING" '{cwd:"/nonexistent/dir\nFAKE injected line\u001b[31m",agent_id:"a-nl",agent_type:"dforge:impl-sonnet-high",last_assistant_message:$m}')"
check "a value with a newline or an escape logs one clean line" "$CODE|$(($(wc -l < "$FALLBACK" | tr -d ' ') - LINES0))|$(grep -c '^FAKE' "$FALLBACK")|$(grep -c "$(printf '\033')" "$FALLBACK")" "0|1|0|0"

# A symlink planted where the log goes is not followed.
HOME2="$TMP/home2"; mkdir -p "$HOME2/.local/state/dforge"
ln -s "$TMP/victim" "$HOME2/.local/state/dforge/impl-stop-gate.log"
HOME="$HOME2" gate '{"agent_type":"dforge:impl-sonnet-high"'
check "a symlinked log file is not written through" "$CODE|$([ -e "$TMP/victim" ] && echo written || echo untouched)" "0|untouched"
HOME3="$TMP/home3"; mkdir -p "$HOME3/.local/state" "$TMP/victim-dir"
ln -s "$TMP/victim-dir" "$HOME3/.local/state/dforge"
HOME="$HOME3" gate '{"agent_type":"dforge:impl-sonnet-high"'
check "a symlinked log directory is not written through" "$CODE|$(ls "$TMP/victim-dir" | wc -l | tr -d ' ')" "0|0"

# --- a passing stop after a block clears awaiting ---
awaiting() { sed -n 3p "$STATE/impl-stop-gate/$1"; }
gate "$(input dforge:impl-sonnet-high agent-s1 "$M1")"
check "a block marks the counter awaiting" "$CODE|$(awaiting agent-s1)" "2|awaiting"
gate "$(input dforge:impl-sonnet-high agent-s1 'Gave up on the report.')"
check "a retry with no Report line passes and clears awaiting" "$CODE|$OUT|$ERR|$(awaiting agent-s1)" "0|||"
gate "$(input dforge:impl-sonnet-high agent-s2 "$M1")"
gate "$(input dforge:impl-sonnet-high agent-s2 "$GOOD")"
check "a retry with a complete report passes and clears awaiting" "$CODE|$OUT|$ERR|$(awaiting agent-s2)" "0|||"

# --- no test runner, no network ---
STUBS="$TMP/stubs"; mkdir -p "$STUBS"
CALLS="$TMP/calls.log"; : > "$CALLS"
for tool in npm npx pnpm yarn bun pytest jest vitest mocha cargo go make mvn gradle dotnet curl wget nc ssh gh; do
  printf '#!/usr/bin/env bash\necho "%s $*" >> "%s"\nexit 0\n' "$tool" "$CALLS" > "$STUBS/$tool"
  chmod +x "$STUBS/$tool"
done
{ cat "$R"; printf '\n## Notes\n'; for i in $(seq 1 1000); do printf 'line %s of the long report\n' "$i"; done; } > "$TMP/long.md"
OUT=$(PATH="$STUBS:$PATH" bash "$GATE" <<<"$(input dforge:impl-sonnet-high a-long "Report: $TMP/long.md")" 2>&1); CODE=$?
check "a 1,000-line report opening with ## Verdict passes" "$CODE|$OUT" "0|"
{ printf '# Notes\n'; cat "$TMP/long.md"; } > "$TMP/long-bad.md"
OUT=$(PATH="$STUBS:$PATH" bash "$GATE" <<<"$(input dforge:impl-sonnet-high a-long-bad "Report: $TMP/long-bad.md")" 2>&1); CODE=$?
check "a 1,000-line report opening with another line blocks" "$CODE" "2"
check "neither run invoked a test runner or a network tool" "$(wc -c < "$CALLS" | tr -d ' ')" "0"

# --- the observed SubagentStop input and the hooks.json wiring ---
check "the observed agent_type carries the plugin prefix" "$(jq -r .agent_type "$FIXTURE")" "dforge:impl-sonnet-high"
check "the observed event name" "$(jq -r .hook_event_name "$FIXTURE")" "SubagentStop"
check "the observed input has the fields the gate reads" \
  "$(jq -r '[has("agent_id"), has("agent_type"), has("last_assistant_message"), has("cwd")] | all' "$FIXTURE")" "true"
MATCHER=$(jq -r '.hooks.SubagentStop[0].matcher' "$HOOKS")
check "hooks.json registers SubagentStop with the QA seat matcher" "$MATCHER" '^(dforge:)?impl-sonnet-high$'
matches() { [[ $1 =~ ^($MATCHER)$ ]] && echo yes || echo no; }
check "the matcher selects the observed agent_type" "$(matches "$(jq -r .agent_type "$FIXTURE")")" "yes"
check "the matcher selects the unprefixed QA seat" "$(matches impl-sonnet-high)" "yes"
check "the matcher leaves another plugin's implementer alone" "$(matches dagents:impl-sonnet-high)" "no"
check "the matcher leaves a judge alone" "$(matches dforge:judge-opus)" "no"
check "hooks.json runs the gate" "$(jq -r '.hooks.SubagentStop[0].hooks[0].command' "$HOOKS")" 'bash "${CLAUDE_PLUGIN_ROOT}/scripts/impl-stop-gate"'
check "the gate hook is synchronous, bash, 30 s" \
  "$(jq -r '.hooks.SubagentStop[0].hooks[0] | [.type, .async, .shell, .timeout] | map(tostring) | join(",")' "$HOOKS")" "command,false,bash,30"
check "the description mentions the gate" "$(jq -r .description "$HOOKS" | grep -c "implementer subagent's stop")" "1"
gate "$(jq -c --arg c "$REPO" '.cwd = $c' "$FIXTURE")"
check "the observed input drives the gate: it acts and finds no report" "$CODE|$(has "$ERR" 'does not exist')" "2|1"

# --- ui_proof_exempt: a UI walkthrough's proof report carries no ## Verdict ---
printf '\n# UI proof: checkout flow\n\nScreenshots: a.png\n' > "$TMP/ui-proof.md"
gate "$(input dforge:impl-sonnet-high u-1 "Walkthrough done.
Report: $TMP/ui-proof.md")"
check "ui_proof_exempt: a report opening # UI proof: passes" "$CODE|$OUT|$ERR" "0||"
printf '# Notes\n\nScreenshots: a.png\n' > "$TMP/notes.md"
gate "$(input dforge:impl-sonnet-high u-2 "Walkthrough done.
Report: $TMP/notes.md")"
check "ui_proof_exempt: a report opening # Notes is still refused" "$CODE" "2"

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
