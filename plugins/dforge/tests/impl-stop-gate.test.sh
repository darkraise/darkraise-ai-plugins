#!/usr/bin/env bash
# scripts/impl-stop-gate: the SubagentStop hook that holds an implementer's
# DONE report until its report file has the required structure. The input is
# shaped as Claude Code 2.1.312 sends it (tests/fixtures/subagent-stop-input.json).
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATE="$HERE/../scripts/impl-stop-gate"
PATHS="$HERE/../scripts/dforge-path"
HOOKS="$HERE/../hooks/hooks.json"
FIXTURE="$HERE/fixtures/subagent-stop-input.json"

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME"
unset CLAUDE_CONFIG_DIR CLAUDE_CODE_SESSION_ID AR_SESSION DFORGE_BUDGET CLAUDE_PROJECT_DIR

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

good_report() { # good_report <file> — a report with every required section
  cat > "$1" <<'EOF'
# Report

## Summary
Did the work.

## Verified
- `bash plugins/dforge/tests/impl-stop-gate.test.sh` — pass: 30 passed, 0 failed
- `npm test -- one` — fail: 1 passed, 1 failed

## Discovered issues (not fixed)
None.

## Assumptions made
None.
EOF
}

R="$TMP/report.md"
good_report "$R"
DONE=$'**Status:** DONE\nReport: '"$R"

# --- the gate stands aside ---
gate "$(input dforge:judge-opus a-judge "$DONE")"
check "another agent type passes" "$CODE|$OUT|$ERR" "0||"
gate "$(input general-purpose a-gp $'**Status:** DONE\nReport: /nonexistent/report.md')"
check "a general-purpose agent with a missing report passes" "$CODE|$OUT|$ERR" "0||"
gate "$(input dforge:impl-sonnet-high a-b $'**Status:** BLOCKED\nReport: /nonexistent/report.md')"
check "BLOCKED passes" "$CODE|$OUT|$ERR" "0||"
gate "$(input dforge:impl-sonnet-high a-n $'**Status:** NEEDS_CONTEXT\nReport: /nonexistent/report.md')"
check "NEEDS_CONTEXT passes" "$CODE|$OUT|$ERR" "0||"
gate "$(input dforge:impl-sonnet-high a-free 'Fixed the typo in README.md and committed it.')"
check "a reply without the status contract passes" "$CODE|$OUT|$ERR" "0||"
gate '{"agent_type":"dforge:impl-haiku"'
check "malformed input passes" "$CODE|$OUT|$ERR" "0||"
gate "$(fjq -nc --arg m "$DONE" --arg c "$REPO" '{cwd:$c,agent_type:"dforge:impl-haiku",last_assistant_message:$m}')"
check "input with no agent_id passes" "$CODE|$OUT|$ERR" "0||"

# --- a complete report passes ---
gate "$(input dforge:impl-sonnet-high a-ok "$DONE")"
check "DONE with a complete report passes" "$CODE|$OUT|$ERR" "0||"
gate "$(input dforge:impl-sonnet-high a-ok $'**Status:** DONE_WITH_CONCERNS\nConcern: slow.\nReport: '"$R")"
check "DONE_WITH_CONCERNS with a complete report passes" "$CODE|$OUT|$ERR" "0||"
gate "$(input impl-opus-high a-ok "$DONE")"
check "an unprefixed agent type is checked too" "$CODE|$OUT|$ERR" "0||"
check "a passing stop writes no counter" "$([ -e "$STATE/impl-stop-gate/a-ok" ] && echo yes || echo no)" "no"
sed 's/$/\r/' "$R" > "$TMP/crlf.md"
gate "$(input dforge:impl-sonnet-high a-crlf $'**Status:** DONE\r\nReport: '"$TMP/crlf.md"$'\r')"
check "CRLF line endings pass" "$CODE|$OUT|$ERR" "0||"
gate "$(input dforge:impl-sonnet-high a-last "$(printf '**Status:** DONE\nReport: %s\nlater text\nReport: %s' "$TMP/missing.md" "$R")")"
check "the last Report line wins" "$CODE|$OUT|$ERR" "0||"

# --- each missing piece blocks and is named ---
gate "$(input dforge:impl-sonnet-high a-1 $'**Status:** DONE\nAll done.')"
check "no Report line: exit 2" "$CODE|$OUT" "2|"
check "no Report line: one stderr line naming it" "$(wc -l <<<"$ERR" | tr -d ' ')|$(has "$ERR" 'impl-stop-gate: your reply has no `Report: <absolute path>` line')" "1|1"
gate "$(input dforge:impl-sonnet-high a-2 $'**Status:** DONE\nReport: reports/task-4.md')"
check "relative Report path: exit 2 naming it" "$CODE|$(has "$ERR" 'is not absolute')" "2|1"
gate "$(input dforge:impl-sonnet-high a-3 $'**Status:** DONE\nReport: '"$TMP/missing.md")"
check "missing file: exit 2 naming it" "$CODE|$(has "$ERR" "the report file \`$TMP/missing.md\` does not exist")" "2|1"
grep -v '^## Discovered issues' "$R" > "$TMP/no-discovered.md"
gate "$(input dforge:impl-sonnet-high a-4 $'**Status:** DONE\nReport: '"$TMP/no-discovered.md")"
check "no Discovered issues heading: exit 2 naming it" "$CODE|$(has "$ERR" 'the report lacks `## Discovered issues (not fixed)`')" "2|1"
grep -v '^## Assumptions made' "$R" > "$TMP/no-assumptions.md"
gate "$(input dforge:impl-sonnet-high a-5 $'**Status:** DONE\nReport: '"$TMP/no-assumptions.md")"
check "no Assumptions heading: exit 2 naming it" "$CODE|$(has "$ERR" 'the report lacks `## Assumptions made`')" "2|1"
grep -v '^## Verified' "$R" > "$TMP/no-verified.md"
gate "$(input dforge:impl-sonnet-high a-6 $'**Status:** DONE\nReport: '"$TMP/no-verified.md")"
check "no Verified heading: exit 2 naming it" "$CODE|$(has "$ERR" 'the report lacks `## Verified`')" "2|1"
sed 's/^- `\(.*\)` — .*/- ran \1/' "$R" > "$TMP/prose-verified.md"
gate "$(input dforge:impl-sonnet-high a-7 $'**Status:** DONE\nReport: '"$TMP/prose-verified.md")"
check "Verified without a grammar bullet: exit 2 naming it" "$CODE|$(has "$ERR" '`## Verified` holds no bullet like')" "2|1"
sed 's/ — pass: .*/ - pass/; s/ — fail: .*/ - fail/' "$R" > "$TMP/hyphen-verified.md"
gate "$(input dforge:impl-sonnet-high a-8 $'**Status:** DONE\nReport: '"$TMP/hyphen-verified.md")"
check "a hyphen instead of the em dash: exit 2" "$CODE|$(has "$ERR" '`## Verified` holds no bullet like')" "2|1"
{ printf '## Verified\nnothing\n\n## Summary\n- `make test` — pass: 3 passed, 0 failed\n\n## Discovered issues (not fixed)\nNone.\n\n## Assumptions made\nNone.\n'; } > "$TMP/elsewhere.md"
gate "$(input dforge:impl-sonnet-high a-9 $'**Status:** DONE\nReport: '"$TMP/elsewhere.md")"
check "a bullet outside ## Verified does not count" "$CODE|$(has "$ERR" '`## Verified` holds no bullet like')" "2|1"
printf '# Task 4\n' > "$TMP/bare.md"
gate "$(input dforge:impl-sonnet-high a-10 $'**Status:** DONE\nReport: '"$TMP/bare.md")"
check "several gaps are named together" "$CODE|$(has "$ERR" 'lacks `## Discovered issues (not fixed)`; the report lacks `## Assumptions made`; the report lacks `## Verified`')" "2|1"

# --- the block counter ---
C="$STATE/impl-stop-gate/agent-1"
M1=$'**Status:** DONE\nFirst attempt.'
M2=$'**Status:** DONE\nSecond attempt.'
M3=$'**Status:** DONE\nThird attempt.'
M4=$'**Status:** DONE\nFourth attempt.'
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
  "$(grep -cE '^[0-9]+ agent-1 dforge:impl-sonnet-high pass-through after 2 blocks — your reply has no `Report: <absolute path>` line$' "$LOG")" "1"
gate "$(input dforge:impl-sonnet-high agent-1 "$M3")"
check "the pass-through stop fired twice passes" "$CODE|$OUT|$ERR" "0||"
gate "$(input dforge:impl-sonnet-high agent-1 "$M4")"
check "a later stop of the same agent passes" "$CODE|$OUT|$ERR" "0||"
check "and neither adds a log line" "$(wc -l < "$LOG" | tr -d ' ')" "1"
gate "$(input dforge:impl-sonnet-high agent-3 "$M1")"
gate "$(input dforge:impl-sonnet-high agent-3 "$DONE")"
check "a block followed by a complete report passes" "$CODE|$OUT|$ERR" "0||"

# --- no test runner, no network ---
STUBS="$TMP/stubs"; mkdir -p "$STUBS"
CALLS="$TMP/calls.log"; : > "$CALLS"
for tool in npm npx pnpm yarn bun pytest jest vitest mocha cargo go make mvn gradle dotnet curl wget nc ssh gh; do
  printf '#!/usr/bin/env bash\necho "%s $*" >> "%s"\nexit 0\n' "$tool" "$CALLS" > "$STUBS/$tool"
  chmod +x "$STUBS/$tool"
done
{ cat "$R"; printf '\n## Notes\n'; for i in $(seq 1 1000); do printf 'line %s of the long report\n' "$i"; done; } > "$TMP/long.md"
OUT=$(PATH="$STUBS:$PATH" bash "$GATE" <<<"$(input dforge:impl-sonnet-high a-long $'**Status:** DONE\nReport: '"$TMP/long.md")" 2>&1); CODE=$?
check "a 1,000-line complete report passes" "$CODE|$OUT" "0|"
grep -v '^## Assumptions made' "$TMP/long.md" > "$TMP/long-bad.md"
OUT=$(PATH="$STUBS:$PATH" bash "$GATE" <<<"$(input dforge:impl-sonnet-high a-long-bad $'**Status:** DONE\nReport: '"$TMP/long-bad.md")" 2>&1); CODE=$?
check "a 1,000-line incomplete report blocks" "$CODE" "2"
check "neither run invoked a test runner or a network tool" "$(wc -c < "$CALLS" | tr -d ' ')" "0"

# --- the observed SubagentStop input and the hooks.json wiring ---
check "the observed agent_type carries the plugin prefix" "$(jq -r .agent_type "$FIXTURE")" "dforge:impl-haiku"
check "the observed event name" "$(jq -r .hook_event_name "$FIXTURE")" "SubagentStop"
check "the observed input has the fields the gate reads" \
  "$(jq -r '[has("agent_id"), has("agent_type"), has("last_assistant_message"), has("cwd")] | all' "$FIXTURE")" "true"
MATCHER=$(jq -r '.hooks.SubagentStop[0].matcher' "$HOOKS")
check "hooks.json registers SubagentStop with the implementer matcher" "$MATCHER" '(dforge:)?impl-.*'
matches() { [[ $1 =~ ^($MATCHER)$ ]] && echo yes || echo no; }
check "the matcher selects the observed agent_type" "$(matches "$(jq -r .agent_type "$FIXTURE")")" "yes"
check "the matcher selects an unprefixed implementer" "$(matches impl-opus-high)" "yes"
check "the matcher leaves a judge alone" "$(matches dforge:judge-opus)" "no"
check "hooks.json runs the gate" "$(jq -r '.hooks.SubagentStop[0].hooks[0].command' "$HOOKS")" 'bash "${CLAUDE_PLUGIN_ROOT}/scripts/impl-stop-gate"'
check "the gate hook is synchronous, bash, 30 s" \
  "$(jq -r '.hooks.SubagentStop[0].hooks[0] | [.type, .async, .shell, .timeout] | map(tostring) | join(",")' "$HOOKS")" "command,false,bash,30"
check "the description mentions the gate" "$(jq -r .description "$HOOKS" | grep -c "implementer subagent's stop")" "1"
gate "$(jq -c --arg c "$REPO" '.cwd = $c' "$FIXTURE")"
check "the observed input drives the gate: it acts and finds no report" "$CODE|$(has "$ERR" 'does not exist')" "2|1"

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
