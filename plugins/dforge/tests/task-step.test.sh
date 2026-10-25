#!/usr/bin/env bash
# task-step runs one phase of the delegated task loop in a single call. Each
# case runs against a throwaway repository and plan; no case starts Codex.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
P="$HERE/.."
STEP="$P/scripts/task-step"

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}

TMP=$(mktemp -d)
if command -v cygpath >/dev/null 2>&1; then TMP=$(cygpath -m "$TMP"); fi
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
mkdir -p "$HOME/.claude"
export MSYS_NO_PATHCONV=1 GIT_CONFIG_NOSYSTEM=1 DFORGE_NO_SETTINGS=1
unset DFORGE_BUDGET DR_SUPERPOWERS_BUDGET CLAUDE_CONFIG_DIR CODEX_HOME CLAUDE_CODE_SESSION_ID AR_SESSION CLAUDE_PROJECT_DIR

REPO="$TMP/repo"
git init -q "$REPO"
cd "$REPO" || exit 1
git config user.name Darkraise
git config user.email dark@example.invalid
mkdir docs

# Fixture lines carry a leading | so a plan that quotes this suite still lints.
sed 's/^|//' > docs/plan.md <<'PLAN'
|# Step Fixture Plan
|
|**Goal:** Fixture.
|
|**Execution:** subagent — `claude --model sonnet --effort high` — fixture
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
|2. second
|3. executor
|4. unscored
|5. batch low
|6. batch high
|
|### Task 1: plain
|
|**Implementer:** dforge:impl-sonnet-low
|**Evaluation:** files 0 - spec 0 - coupling 1 - risk 0 = 1
|
|Body one.
|
|### Task 2: second
|
|**Implementer:** `dforge:impl-sonnet-high`
|**Evaluation:** files 1 - spec 0 - coupling 1 - risk 1 = 3
|
|### Task 3: executor
|
|**Implementer:** dforge:impl-sonnet-high
|**Executor:** codex gpt-6.1-sol / high
|**Evaluation:** files 1 - spec 0 - coupling 1 - risk 1 = 3
|
|### Task 4: unscored
|
|**Evaluation:** files 1 - spec 0 - coupling 1 - risk 1 = 3
|
|### Task 5: batch low
|
|**Implementer:** dforge:impl-sonnet-low
|**Evaluation:** files 0 - spec 0 - coupling 0 - risk 0 = 0
|
|### Task 6: batch high
|
|**Implementer:** dforge:impl-opus-medium
|**Evaluation:** files 0 - spec 0 - coupling 0 - risk 0 = 0
PLAN
sed 's/^|//' > docs/codex-plan.md <<'PLAN'
|# Codex Fixture
|
|**Host:** codex
|
|### Task 1: only
|
|**Evaluation:** files 0 - spec 0 - coupling 0 - risk 0 = 0
PLAN
git add -A && git commit -qm "docs: add fixture plans"
BASE=$(git rev-parse HEAD)

WS=$(bash "$P/scripts/sdd-workspace" docs/plan.md)
LEDGER="$WS/progress.md"
rm -f "$WS"/*
step() { out=$(bash "$STEP" "$@" 2>"$TMP/err"); rc=$?; }
count_lines() { printf '%s\n' "$1" | grep -c .; }

# start: the assigned line, the dispatch file, the state and the digest.
step start docs/plan.md 1
check "start: exit 0" "$rc" "0"
check "start: the assigned line" "$(tail -n 1 "$LEDGER")" "Task 1: implementer impl-sonnet-low (assigned; base ${BASE:0:7})"
check "start: the ledger names the plan" "$(head -n 1 "$LEDGER")" "# SDD ledger — plan: docs/plan.md"
check "start: the brief exists" "$([ -f "$WS/task-1-brief.md" ] && echo yes || echo no)" "yes"
check "start: the digest is at most 15 lines" "$([ "$(count_lines "$out")" -le 15 ] && echo yes || echo no)" "yes"
check "start: the seat line" "$(grep '^seat:' <<<"$out")" "seat: dforge:impl-sonnet-low prompt: $WS/task-1-dispatch.md"
check "start: the state line precedes the budget line" "$(tail -n 2 <<<"$out" | head -n 1)" \
  "state: base ${BASE:0:7} review-head - round 0 t0 -"
check "start: the last line is the budget line" "$(tail -n 1 <<<"$out" | cut -c1-6)" "budget"
D="$WS/task-1-dispatch.md"
check "start: the brief path is expanded" "$(grep -c "Read your task brief first: $WS/task-1-brief.md" "$D")" "1"
check "start: the report path is expanded" "$(grep -c "Write your full report to $WS/task-1-report.md:" "$D")" "1"
check "start: no placeholder is left" "$(grep -cE '\[(BRIEF_FILE|REPORT_FILE|PLUGIN_ROOT|IMPLEMENTER)\]' "$D")" "0"
check "start: the task name is filled" "$(grep -c 'You are implementing Task 1: plain' "$D")" "1"
check "start: the working directory is filled" "$(grep -c "^Work from: $(git rev-parse --show-toplevel)\$" "$D")" "1"
check "start: the dispatch file is a bare prompt" "$(grep -c '^Subagent (' "$D")" "0"
check "start: the state file" \
  "$(jq -c '[.tasks, .base == "'"$BASE"'", .head, .reviewHead, .round, .t0, .wave]' "$WS/task-1-step.json" | tr -d '\r')" '[[1],true,null,null,0,null,null]'

# start: a backticked Implementer, a wave, a prefix-free ledger name.
step start docs/plan.md 2 --wave 3
check "start: a wave ends the assigned line" "$(tail -n 1 "$LEDGER")" "Task 2: implementer impl-sonnet-high (assigned; base ${BASE:0:7}; wave 3)"
check "start: the wave is recorded" "$(jq -r .wave "$WS/task-2-step.json" | tr -d '\r')" "3"
check "start: a wave names its worktree" "$(grep -c '^Work from: your worktree' "$WS/task-2-dispatch.md")" "1"

# start: an executor task writes no dispatch file and no assigned line.
before=$(wc -l < "$LEDGER")
step start docs/plan.md 3
check "start: executor line" "$(grep '^executor' <<<"$out")" "executor codex: follow executor-lane.md §Dispatch"
check "start: no dispatch file for an executor task" "$([ -e "$WS/task-3-dispatch.md" ] && echo yes || echo no)" "no"
check "start: no assigned line for an executor task" "$(wc -l < "$LEDGER" | tr -d ' ')" "$(echo "$before" | tr -d ' ')"
check "start: an executor task still records its state" "$([ -f "$WS/task-3-step.json" ] && echo yes || echo no)" "yes"

# start: a task without an Implementer line is scored at dispatch.
before=$(wc -l < "$LEDGER")
step start docs/plan.md 4
check "start: unscored seat line" "$(grep -c '^seat: unscored (no known \*\*Implementer:\*\* line' <<<"$out")" "1"
check "start: no assigned line when unscored" "$(wc -l < "$LEDGER" | tr -d ' ')" "$(echo "$before" | tr -d ' ')"
check "start: the dispatch file is still written" "$([ -f "$WS/task-4-dispatch.md" ] && echo yes || echo no)" "yes"

# start: a batch takes the highest tier, one assigned line per task and one brief.
step start docs/plan.md 5 6
check "start: batch seat" "$(grep '^seat:' <<<"$out")" "seat: dforge:impl-opus-medium prompt: $WS/task-5-dispatch.md"
check "start: batch assigned lines" "$(tail -n 2 "$LEDGER" | sed 's/base [0-9a-f]*/base B/' | tr '\n' ';')" \
  "Task 5: implementer impl-opus-medium (assigned; base B);Task 6: implementer impl-opus-medium (assigned; base B);"
check "start: the digest names the batch" "$(head -n 1 <<<"$out" | cut -c1-12)" "task 5,6: br"
check "start: the batch brief holds both tasks" \
  "$(grep -cE '^### Task (5: batch low|6: batch high)$' "$WS/task-5-brief.md")" "2"
check "start: the batch brief carries the header excerpt once" "$(grep -c '^## Plan header excerpt$' "$WS/task-5-brief.md")" "1"
check "start: the batch brief ends with the header excerpt" "$(grep -v '^$' "$WS/task-5-brief.md" | tail -n 1)" "- Fixture contract."
check "start: the batch state names both tasks" "$(jq -c .tasks "$WS/task-5-step.json" | tr -d '\r')" "[5,6]"

# start: a second call keeps the recorded state and writes no second assigned
# line; --reset discards the state and starts over.
echo moved > moved.txt && git add moved.txt && git commit -qm "chore: move head"
MOVED=$(git rev-parse HEAD)
before=$(wc -l < "$LEDGER")
step start docs/plan.md 1
check "start again: exit 0" "$rc" "0"
check "start again: no second assigned line" "$(wc -l < "$LEDGER" | tr -d ' ')" "$(echo "$before" | tr -d ' ')"
check "start again: the recorded base is kept" "$(jq -r .base "$WS/task-1-step.json" | tr -d '\r')" "$BASE"
check "start again: the digest says the state is kept" "$(head -n 1 <<<"$out" | grep -c 'state kept')" "1"
check "start again: the state line shows the kept base" "$(tail -n 2 <<<"$out" | head -n 1)" \
  "state: base ${BASE:0:7} review-head - round 0 t0 -"
step start docs/plan.md 1 --reset
check "start --reset: the base is HEAD again" "$(jq -r .base "$WS/task-1-step.json" | tr -d '\r')" "$MOVED"
check "start --reset: a new assigned line" "$(tail -n 1 "$LEDGER")" "Task 1: implementer impl-sonnet-low (assigned; base ${MOVED:0:7})"
check "start --reset: the digest does not say kept" "$(head -n 1 <<<"$out" | grep -c 'state kept')" "0"

# Negative: usage, a missing task, a Codex host, an amendment that does not apply.
step start docs/plan.md 9
check "start: no such task exits 3" "$rc" "3"
step start docs/plan.md
check "start: no task number exits 2" "$rc" "2"
step start docs/plan.md x
check "start: a non-numeric task exits 2" "$rc" "2"
step start docs/plan.md 1 --nope
check "start: an unknown flag exits 2" "$rc" "2"
step start docs/plan.md 1 --wave
check "start: --wave without a value exits 2" "$rc" "2"
step bogus docs/plan.md 1
check "an unknown subcommand exits 2" "$rc" "2"
step start docs/missing.md 1
check "start: a missing plan exits 2" "$rc" "2"
CWS=$(bash "$P/scripts/sdd-workspace" docs/codex-plan.md)
rm -rf "$CWS"
step start docs/codex-plan.md 1
check "start: a Host: codex plan exits 2" "$rc" "2"
check "start: a Host: codex plan writes nothing" "$([ -e "$CWS" ] && ls -A "$CWS" | grep -c . || echo 0)" "0"
mkdir -p "$WS"
sed 's/^|//' > "$WS/amendments.md" <<'AMEND'
|## A1 — Task 1
|
|### Old
|````
|a line the task does not hold
|````
|
|### New
|````
|replacement
|````
AMEND
step start docs/plan.md 1
check "start: an amendment that does not apply exits 4" "$rc" "4"
rm -f "$WS/amendments.md"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
