#!/usr/bin/env bash
# Acceptance tests for the task-loop steps spec
# (docs/dforge/specs/2026-10-26-task-loop-steps-design.md), statements
# A2, A3, A7, A8 and A11. Each test is written from the statement's text and
# reaches the behaviour through the scripts and documents the spec names. The
# cockpit statements (A12, A13) are in task-loop-steps.acceptance.test.ts.
# Usage:
#   bash task-loop-steps.acceptance.test.sh           run every test
#   bash task-loop-steps.acceptance.test.sh A7 A8     run the named tests only
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN="$(cd "$HERE/.." && pwd)"
S="$PLUGIN/scripts"
STEP="$S/task-step"
INFLIGHT="$S/in-flight"
ROUTE="$S/review-route"
LROUTE="$S/lens-route"
TURNEND="$S/turn-end.sh"
TURNSTART="$S/turn-start.sh"

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
has() { # has <name> <haystack> <needle>
  if grep -qF -- "$3" <<<"$2"; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       missing: [%s]\n       in: [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
lacks() { # lacks <name> <haystack> <needle>
  if grep -qF -- "$3" <<<"$2"; then printf 'FAIL - %s\n       unexpected: [%s]\n       in: [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1))
  else printf 'ok   - %s\n' "$1"; pass=$((pass + 1)); fi
}
matches() { # matches <name> <haystack> <ERE>
  if grep -qE -- "$3" <<<"$2"; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       no match: [%s]\n       in: [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
absent() { # absent <name> <haystack> <ERE>
  if grep -qE -- "$3" <<<"$2"; then printf 'FAIL - %s\n       unexpected match: [%s]\n       in: [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1))
  else printf 'ok   - %s\n' "$1"; pass=$((pass + 1)); fi
}

TMP="$(mktemp -d)"
# MSYS_NO_PATHCONV below hands git.exe this path untranslated, so it must be a
# Windows path or git initialises a repository somewhere else.
if command -v cygpath >/dev/null 2>&1; then TMP=$(cygpath -m "$TMP"); fi
export WORKFLOW_GUARD_CLAUDE_DIR="$TMP/workflow-guard" WORKFLOW_GUARD_MANAGED_DIR="$TMP/workflow-guard" WORKFLOW_GUARD_PROJECT_DIR="$TMP/workflow-guard"
# sdd-workspace and task-step print the form git gives, which native jq.exe can
# open.
winpath() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s\n' "$1"; fi; }
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME/.claude"
unset CLAUDE_CONFIG_DIR CODEX_HOME AR_SESSION DFORGE_BUDGET DR_SUPERPOWERS_BUDGET CLAUDE_PROJECT_DIR
unset GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 DFORGE_NO_SETTINGS=1 MSYS_NO_PATHCONV=1
export DR_CODEX_SESSION_DIR="$TMP/codex-sessions" CLAUDE_CODE_SESSION_ID=acceptance-session
printf '%s\n' '#!/usr/bin/env bash' 'echo "codex-gate usable=true reason=ok review=true resets_at=- source=cache"' > "$TMP/gate-stub"
printf '%s\n' '#!/usr/bin/env bash' 'echo "agy-gate usable=false reason=setting review=false resets_at=- claude=on claude_resets_at=- source=setting"' > "$TMP/agy-gate-stub"
export TASK_STEP_CODEX_GATE="$TMP/gate-stub" TASK_STEP_AGY_GATE="$TMP/agy-gate-stub"

review_surface() { # review_surface <true|false|absent> — what this session's Codex gate file says
  rm -rf "$DR_CODEX_SESSION_DIR"
  [ "$1" != absent ] || return 0
  mkdir -p "$DR_CODEX_SESSION_DIR"
  printf '{"session_id":"%s","usable":true,"review":%s,"lane":false}\n' "$CLAUDE_CODE_SESSION_ID" "$1" > "$DR_CODEX_SESSION_DIR/$CLAUDE_CODE_SESSION_ID.json"
}

CO="Co-Authored""-By"
CS="Claude""-Session"
GW="Generated"" with"

short() { git -C "$R" rev-parse --short=7 "$1"; }
full() { git -C "$R" rev-parse "$1"; }
ts() { out=$(cd "$R" && bash "$STEP" "$@" 2>"$TMP/err"); rc=$?; err=$(cat "$TMP/err"); }
open_t() { (cd "$R" && bash "$S/task-brief" --open docs/plan.md "$1" >/dev/null); }
count_lines() { printf '%s\n' "$1" | grep -c .; }
commit_file() { # commit_file <file> <content> <message>
  printf '%s\n' "$2" > "$R/$1"
  git -C "$R" add "$1" && git -C "$R" commit -qm "$3"
}
ws_files() { ls -A "$WS" 2>/dev/null | sort | tr '\n' ' '; }
prompt_path() { # prompt_path <file> — the first .diff path a prompt names
  grep -oE '[^ ]+\.diff' "$1" | head -n 1
}

PLAN_TEXT='|# Acceptance Fixture Plan
|
|**Goal:** Fixture.
|
|**Execution:** inline — `claude --model sonnet --effort high` — fixture
|
|## Global Constraints
|
|- Fixture constraint.
|
|## Contracts
|
|- Fixture contract.
|
|## Task index
|
|1. plain
|2. risky
|3. nolens
|
|### Task 1: plain
|
|**Files:**
|- Modify: `app.txt`
|
|**Implementer:** dforge:impl-sonnet-high
|**Evaluation:** files 0 - spec 0 - coupling 1 - risk 0 = 1
|**Lenses:** lang-bash
|
|Body one.
|
|### Task 2: risky
|
|**Files:**
|- Modify: `app.txt`
|
|**Implementer:** dforge:impl-sonnet-high
|**Evaluation:** files 1 - spec 1 - coupling 1 - risk 3 = 6
|
|### Task 3: nolens
|
|**Files:**
|- Modify: `other.txt`
|
|**Implementer:** dforge:impl-sonnet-high
|**Evaluation:** files 0 - spec 0 - coupling 1 - risk 1 = 2'

CODEX_PLAN_TEXT='|# Codex Fixture
|
|**Host:** codex
|
|### Task 1: only
|
|**Evaluation:** files 0 - spec 0 - coupling 0 - risk 0 = 0'

new_repo() { # new_repo <name> — a throwaway repository with the fixture plans; sets R and WS
  R="$TMP/$1"
  git init -q "$R"
  git -C "$R" config user.name Darkraise
  git -C "$R" config user.email dark@example.invalid
  mkdir -p "$R/docs"
  sed 's/^|//' <<<"$PLAN_TEXT" > "$R/docs/plan.md"
  sed 's/^|//' <<<"$CODEX_PLAN_TEXT" > "$R/docs/codex-plan.md"
  seq 1 10 | sed 's/^/line /' > "$R/app.txt"
  cp "$R/app.txt" "$R/other.txt"
  cp "$R/app.txt" "$R/test.txt"
  git -C "$R" add -A && git -C "$R" commit -qm "docs: add fixtures"
  WS=$(winpath "$(cd "$R" && bash "$S/sdd-workspace" docs/plan.md)")
  review_surface absent
}

# --- A2 ----------------------------------------------------------------------

a2() {
  new_repo a2
  open_t 1
  commit_file a.txt a "feat: add a"
  review_surface absent
  ts review docs/plan.md 1
  local JP="$WS/task-1-review-prompt.md"
  check "A2: review exits 0" "$rc" "0"
  check "A2: the judge prompt exists" "$([ -f "$JP" ] && echo yes || echo no)" "yes"
  absent "A2: the judge prompt has no unexpanded placeholder" "$(cat "$JP")" '\[[A-Z][A-Z_]+\]'
  local lens_paths route primary
  lens_paths=$(cd "$R" && bash "$LROUTE" docs/plan.md --task 1 | sed -n 's/^lens [^ ]* criteria=\(.*\)$/\1/p')
  check "A2: the fixture task has a lens" "$([ -n "$lens_paths" ] && echo yes || echo no)" "yes"
  local p
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    has "A2: the judge prompt names the lens criteria path $(basename "$p")" "$(cat "$JP")" "$p"
  done <<<"$lens_paths"
  route=$(cd "$R" && bash "$ROUTE" docs/plan.md --task 1)
  primary=$(sed -n 's/.*primary=\([^ ]*\).*/\1/p' <<<"$route")
  check "A2: review-route prints a Claude judge seat with Codex off" "$primary" "dforge:judge-sonnet-high"
  has "A2: the digest names the seat review-route prints" "$out" "$primary"
  local nchecks
  nchecks=$(grep -cE '^check [A-Za-z_-]+: ' <<<"$out")
  check "A2: the digest prints at least two check lines" "$([ "$nchecks" -ge 2 ] && echo yes || echo no)" "yes"
  absent "A2: no Second Pass section below risk 3" "$(cat "$JP")" 'Second Pass'

  # A task whose lens-route prints none has no lens section.
  open_t 3
  ts review docs/plan.md 3
  check "A2: lens-route prints no lens for task 3" "$(cd "$R" && bash "$LROUTE" docs/plan.md --task 3 | grep -c '^lens ')" "0"
  absent "A2: and the judge prompt has no lens section" "$(cat "$WS/task-3-review-prompt.md")" '[Ll]ens'
  absent "A2: and no unexpanded placeholder" "$(cat "$WS/task-3-review-prompt.md")" '\[[A-Z][A-Z_]+\]'

  # A panel seat: the reviewers' prompt and the panel command.
  review_surface true
  ts review docs/plan.md 1
  route=$(cd "$R" && bash "$ROUTE" docs/plan.md --task 1)
  primary=$(sed -n 's/.*primary=\([^ ]*\).*/\1/p' <<<"$route")
  has "A2: the open route's primary is a panel seat" "$primary" "panel:"
  has "A2: the digest names the panel seat" "$out" "$primary"
  local runner cprompt
  runner=$(grep 'run-review-panel' <<<"$out" | head -n 1)
  check "A2: the digest prints the panel command" "$([ -n "$runner" ] && echo yes || echo no)" "yes"
  cprompt=$(sed -n 's/.*--prompt "\{0,1\}\([^" ]*\)"\{0,1\}.*/\1/p' <<<"$runner")
  check "A2: the panel command names an existing reviewers' prompt" "$([ -n "$cprompt" ] && [ -f "$cprompt" ] && echo yes || echo no)" "yes"
  absent "A2: the reviewers' prompt has no unexpanded placeholder" "$(cat "$cprompt" 2>/dev/null)" '\[[A-Z][A-Z_]+\]'
  check "A2: the judge prompt is still written beside a panel seat" "$([ -f "$JP" ] && echo yes || echo no)" "yes"
  has "A2: and carries the Second Pass on every panel review" "$(cat "$JP")" 'Second Pass'

  # Risk 3: the judge prompt carries the Second Pass section.
  open_t 2
  commit_file b.txt b "feat: add b"
  ts review docs/plan.md 2
  has "A2: a risk-3 judge prompt carries the Second Pass section" "$(cat "$WS/task-2-review-prompt.md")" "Second Pass"
  absent "A2: the risk-3 judge prompt has no unexpanded placeholder" "$(cat "$WS/task-2-review-prompt.md")" '\[[A-Z][A-Z_]+\]'
  review_surface absent
}

# --- A3 ----------------------------------------------------------------------

a3() {
  new_repo a3
  local before
  before=$(ws_files)
  ts review docs/plan.md 1
  check "A3: review before the task is opened exits 6" "$rc" "6"
  check "A3: and writes nothing" "$(ws_files)" "$before"

  open_t 1
  printf '%s\n\nFixed.\n' '- app.txt: a finding' > "$WS/task-1-fix-1.md"
  before=$(ws_files)
  ts rereview docs/plan.md 1
  check "A3: rereview before review exits 6, with its fix message in place" "$rc" "6"
  check "A3: and writes nothing" "$(ws_files)" "$before"

  local CWS sub
  CWS=$(winpath "$(cd "$R" && bash "$S/sdd-workspace" docs/codex-plan.md)")
  rm -rf "$CWS"
  for sub in review rereview; do
    ts "$sub" docs/codex-plan.md 1
    check "A3: $sub on a Host: codex plan exits 2" "$rc" "2"
    check "A3: $sub on a Host: codex plan writes nothing" "$([ -d "$CWS" ] && ls -A "$CWS" | grep -c . || echo 0)" "0"
  done
}

# --- A7 ----------------------------------------------------------------------

a7() {
  new_repo a7
  local want got
  route_primary() { (cd "$R" && bash "$ROUTE" docs/plan.md --ruling "$@" 2>&1) | sed -n 's/.*primary=\([^ ]*\).*/\1/p'; }
  local SON=dforge:judge-sonnet-high OPU=dforge:judge-opus
  check "A7: cannot-verify, a risk-1 task" "$(route_primary cannot-verify 1)" "$SON"
  check "A7: cannot-verify over two risk-below-3 tasks" "$(route_primary cannot-verify 1 3)" "$SON"
  check "A7: cannot-verify, a risk-3 task" "$(route_primary cannot-verify 2)" "$OPU"
  check "A7: cannot-verify over a risk-1 and a risk-3 task" "$(route_primary cannot-verify 1 2)" "$OPU"
  local kind
  for kind in preflight plan-conflict breaker blocked-plan final-residual acceptance-ambiguous; do
    check "A7: $kind" "$(route_primary "$kind" 1)" "$OPU"
  done
  check "A7: a mixed list, Sonnet kind first" "$(route_primary cannot-verify,breaker 1)" "$OPU"
  check "A7: a mixed list, Opus kind first" "$(route_primary breaker,cannot-verify 1)" "$OPU"
}

# --- A8 ----------------------------------------------------------------------

# check_case <name> — start, run the offending commit by the caller, review, print check lines
a8_case() { # a8_case <name> <commit-fn> <expect clean|dirty>
  new_repo "a8-$1"
  open_t 1
  "$2"
  local sha7
  sha7=$(short HEAD)
  ts review docs/plan.md 1
  local checks bad
  checks=$(grep '^check ' <<<"$out")
  bad=$(grep -v ': clean$' <<<"$checks")
  if [ "$3" = clean ]; then
    check "A8: $1: review exits 0" "$rc" "0"
    check "A8: $1: no check reports a finding" "${bad:-none}" "none"
    check "A8: $1: at least two check lines print clean" "$([ "$(grep -c ': clean$' <<<"$checks")" -ge 2 ] && echo yes || echo no)" "yes"
  else
    check "A8: $1: a check reports a finding" "$([ -n "$bad" ] && echo yes || echo no)" "yes"
    has "A8: $1: it names the offending commit" "$bad" "$sha7"
    check "A8: $1: another check line still prints clean" "$([ "$(grep -c ': clean$' <<<"$checks")" -ge 1 ] && echo yes || echo no)" "yes"
  fi
}
c_clean() { commit_file a.txt a "feat: add a"; }
c_author() { printf 'a\n' > "$R/a.txt"; git -C "$R" add a.txt; git -C "$R" commit -q --author="Other <other@example.invalid>" -m "feat: add a"; }
c_committer() { printf 'a\n' > "$R/a.txt"; git -C "$R" add a.txt; GIT_COMMITTER_NAME=Other GIT_COMMITTER_EMAIL=other@example.invalid git -C "$R" commit -q -m "feat: add a"; }
c_email() { printf 'a\n' > "$R/a.txt"; git -C "$R" add a.txt; git -C "$R" commit -q --author="Darkraise <elsewhere@example.invalid>" -m "feat: add a"; }
c_coauthor() { printf 'a\n' > "$R/a.txt"; git -C "$R" add a.txt; git -C "$R" commit -q -m "feat: add a" -m "$CO: X <x@example.invalid>"; }
c_session() { printf 'a\n' > "$R/a.txt"; git -C "$R" add a.txt; git -C "$R" commit -q -m "feat: add a" -m "$CS: abc123"; }
c_generated() { printf 'a\n' > "$R/a.txt"; git -C "$R" add a.txt; git -C "$R" commit -q -m "feat: add a" -m "$GW a tool"; }

a8() {
  a8_case clean c_clean clean
  a8_case "a different author name" c_author dirty
  a8_case "a different committer" c_committer dirty
  a8_case "a different author email" c_email dirty
  a8_case "a co-author trailer" c_coauthor dirty
  a8_case "a session trailer" c_session dirty
  a8_case "a generated-with line" c_generated dirty
}

# --- A11 ---------------------------------------------------------------------

fjq() { MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' jq "$@"; }

a11() {
  local SID=s-flight TP="$TMP/s-flight.jsonl" ENV_SID
  ENV_SID=$CLAUDE_CODE_SESSION_ID
  export CLAUDE_CODE_SESSION_ID=$SID
  mkdir -p "$HOME/.claude/dforge/sessions/by-id" "$TMP/$SID/subagents"
  jq -n --arg tp "$TP" '{session_id:"s-flight",transcript_path:$tp}' > "$HOME/.claude/dforge/sessions/by-id/$SID.json"
  : > "$TP"
  use() { # use <tool_use_id> <description>
    fjq -nc --arg id "$1" --arg d "$2" '{type:"assistant",message:{role:"assistant",content:[{type:"tool_use",id:$id,name:"Agent",input:{description:$d}}]}}' >> "$TP"
  }
  result_at() { # result_at <tool_use_id> <iso timestamp> <text>
    fjq -nc --arg id "$1" --arg ts "$2" --arg t "$3" '{type:"user",timestamp:$ts,message:{role:"user",content:[{type:"tool_result",tool_use_id:$id,content:$t}]}}' >> "$TP"
  }
  ago() { touch -d "$1 minutes ago" "$2"; }

  # A shell: the file its result names.
  use toolu_sh 'Run the suite'
  result_at toolu_sh 2026-10-26T08:05:00.000Z "Command running in background with ID: b11. Output is being written to: $TMP/b11.output. You will be notified when it completes."
  : > "$TMP/b11.output"; ago 47 "$TMP/b11.output"
  # An agent whose result names an output_file.
  use toolu_a1 'Implement task 4'
  result_at toolu_a1 2026-10-26T09:30:00.000Z "$(printf 'Async agent launched successfully.\nagentId: a11 (internal ID)\noutput_file: %s/a11.output\nDo NOT Read or tail this file.' "$TMP")"
  : > "$TMP/a11.output"; ago 12 "$TMP/a11.output"
  # An agent with no output_file: its subagent transcript.
  use toolu_a2 'Review task 4'
  result_at toolu_a2 2026-10-26T10:15:00.000Z $'Async agent launched successfully.\nagentId: a12 (internal ID)'
  : > "$TMP/$SID/subagents/agent-a12.jsonl"; ago 9 "$TMP/$SID/subagents/agent-a12.jsonl"
  # An agent with neither.
  use toolu_a3 'Review task 5'
  result_at toolu_a3 2026-10-26T11:40:00.000Z $'Async agent launched successfully.\nagentId: a13 (internal ID)'

  local out code
  # Run outside the developer's checkout, whose session-state.log would gain this session's line.
  out=$(cd "$TMP" && TZ=UTC0 bash "$INFLIGHT"); code=$?
  check "A11: running launches: exit 1" "$code" "1"
  matches "A11: a shell: start time and idle minutes from the file its result names" "$out" '^- shell b11 08:05 idle (46|47|48)m Run the suite$'
  matches "A11: an agent: start time and idle minutes from its output_file" "$out" '^- agent a11 09:30 idle (11|12|13)m Implement task 4$'
  matches "A11: an agent with no output_file: idle minutes from its subagent transcript" "$out" '^- agent a12 10:15 idle (8|9|10)m Review task 4$'
  matches "A11: an agent with neither: idle -" "$out" '^- agent a13 11:40 idle - Review task 5$'

  # turn-end.sh still counts and names the launches.
  local REPO="$TMP/a11-repo" WS2
  git init -q "$REPO"
  WS2="$REPO/.dforge/sdd/2026-10-08-example"
  mkdir -p "$WS2"
  jq -n --arg sid s-turn --arg cwd "$REPO" '{hook_event_name:"UserPromptSubmit",session_id:$sid,cwd:$cwd,prompt:"go"}' | (cd "$REPO" && bash "$TURNSTART")
  sleep 1
  printf '# SDD ledger — plan: docs/superpowers/plans/2026-10-08-example.md\nTask 1: dispatched\n' > "$WS2/progress.md"
  local msg=$'Stopping here.\n\n## Next session\n\n**Status:** x' hold reason
  hold=$(jq -n --arg sid s-turn --arg cwd "$REPO" --arg msg "$msg" --arg tp "$TP" \
    '{hook_event_name:"Stop",session_id:$sid,cwd:$cwd,transcript_path:$tp,stop_hook_active:false,last_assistant_message:$msg}' | (cd "$REPO" && bash "$TURNEND"))
  reason=$(jq -r '.reason // ""' <<<"$hold")
  check "A11: turn-end.sh holds a next-step block over running launches" "$(jq -r '.decision // "none"' <<<"$hold")" "block"
  has "A11: turn-end.sh counts the launches" "$reason" "4 background launch"
  has "A11: turn-end.sh names the shell by id" "$reason" "b11"
  has "A11: turn-end.sh names the shell by description" "$reason" "Run the suite"
  has "A11: turn-end.sh names an agent by id" "$reason" "a11"
  has "A11: turn-end.sh names an agent by description" "$reason" "Implement task 4"

  # next-step still counts and names the launches, and prints no block over them.
  local ns
  ns=$(cd "$REPO" && bash "$PLUGIN/scripts/next-step" --adhoc --phase build --next "Commit the work" 2>/dev/null); code=$?
  check "A11: next-step over running launches: exit 5" "$code" "5"
  has "A11: next-step counts the launches" "$ns" "4 background launch"
  has "A11: next-step names the shell by id" "$ns" "shell b11 "
  has "A11: next-step names the shell by description" "$ns" "Run the suite"
  has "A11: next-step names an agent by id" "$ns" "agent a11 "
  has "A11: next-step names an agent by description" "$ns" "Implement task 4"
  lacks "A11: next-step prints no next-session block" "$ns" "## Next session"
  check "A11: next-step writes no latest.md" "$([ -e "$REPO/.dforge/handoff/latest.md" ] && echo written || echo none)" "none"
  export CLAUDE_CODE_SESSION_ID=$ENV_SID
}

ALL="a2 a3 a7 a8 a11"
if [ $# -gt 0 ]; then
  sel=""
  for n in "$@"; do sel="$sel $(tr 'A-Z' 'a-z' <<<"$n")"; done
else
  sel=$ALL
fi
for t in $sel; do "$t"; done

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
