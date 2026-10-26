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
# sdd-workspace prints the MSYS form on Git Bash; task-step prints the form git
# gives, which native jq.exe can open.
winpath() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s\n' "$1"; fi; }
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
mkdir -p "$HOME/.claude"
export MSYS_NO_PATHCONV=1 GIT_CONFIG_NOSYSTEM=1 DFORGE_NO_SETTINGS=1
unset DFORGE_BUDGET DR_SUPERPOWERS_BUDGET CLAUDE_CONFIG_DIR CODEX_HOME CLAUDE_CODE_SESSION_ID AR_SESSION CLAUDE_PROJECT_DIR

# review-route reads this session's gate file; the gate itself is a stub, so no
# case can reach a real Codex.
export DR_CODEX_SESSION_DIR="$TMP/sessions" CLAUDE_CODE_SESSION_ID=task-step-test
printf '%s\n' '#!/usr/bin/env bash' 'echo "codex-gate usable=true reason= review=true lane=false resets_at=- source=cache"' > "$TMP/gate-stub"
export TASK_STEP_CODEX_GATE="$TMP/gate-stub"
review_surface() { # review_surface <true|false|absent>
  rm -rf "$DR_CODEX_SESSION_DIR"
  [ "$1" != absent ] || return 0
  mkdir -p "$DR_CODEX_SESSION_DIR"
  printf '{"session_id":"task-step-test","usable":true,"review":%s,"lane":false}\n' "$1" > "$DR_CODEX_SESSION_DIR/task-step-test.json"
}

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
|7. risky
|8. unparseable
|9. bad lens
|
|### Task 1: plain
|
|**Implementer:** dforge:impl-sonnet-low
|**Evaluation:** files 0 - spec 0 - coupling 1 - risk 0 = 1
|**Lenses:** lang-bash
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
|
|### Task 7: risky
|
|**Implementer:** dforge:impl-opus-high
|**Evaluation:** files 1 - spec 1 - coupling 1 - risk 3 = 6
|
|### Task 8: unparseable
|
|**Implementer:** dforge:impl-sonnet-low
|**Evaluation:** one plus one
|
|### Task 9: bad lens
|
|**Implementer:** dforge:impl-sonnet-low
|**Evaluation:** files 0 - spec 0 - coupling 0 - risk 0 = 0
|**Lenses:** no-such-lens
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

WS_RAW=$(bash "$P/scripts/sdd-workspace" docs/plan.md)
WS=$(winpath "$WS_RAW")
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
check "start: the plugin root is expanded to this plugin" "$(grep -c "bash $(cd "$P" && pwd)/scripts/suite-run -- " "$D")" "1"
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
check "start: a wave reports inside its worktree" \
  "$(grep -c 'Write your full report to task-2-report.md in the directory sdd-workspace prints in your worktree (see the Parallel workspace section):' "$WS/task-2-dispatch.md")" "1"
check "start: a wave dispatch names no session workspace report path" "$(grep -c "$WS/task-2-report.md" "$WS/task-2-dispatch.md")" "0"

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
step start docs/plan.md 99
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
CWS=$(winpath "$(bash "$P/scripts/sdd-workspace" docs/codex-plan.md)")
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

# review: the preconditions.
PR=$(cd "$P" && pwd)
TOP=$(git rev-parse --show-toplevel)
short() { git rev-parse --short "$1"; }
placeholders() { grep -cE '\[[A-Z][A-Z_]*\]' "$1"; }
ws_count() { ls -A "$WS" | wc -l | tr -d ' '; }
state_of() { jq -r "$2" "$WS/task-$1-step.json" | tr -d '\r'; }
before=$(ws_count)
step review docs/plan.md 7
check "review: before start exits 6" "$rc" "6"
check "review: before start writes nothing" "$(ws_count)" "$before"
step review docs/codex-plan.md 1
check "review: a Host: codex plan exits 2" "$rc" "2"
check "review: a Host: codex plan writes nothing" "$([ -e "$CWS" ] && echo yes || echo no)" "no"
step review docs/plan.md 99
check "review: no such task exits 3" "$rc" "3"
step review docs/plan.md 1 --base
check "review: --base without a value exits 2" "$rc" "2"
step start docs/plan.md 1 --head HEAD
check "start: --head is a review flag only" "$rc" "2"
step start docs/plan.md 1 --cwd "$TMP"
check "start: --cwd is a review flag only" "$rc" "2"
step review docs/plan.md 1 --reset
check "review: --reset is a start flag only" "$rc" "2"
step review docs/plan.md 1 --cwd
check "review: --cwd without a value exits 2" "$rc" "2"
step start docs/plan.md 1 --reset
BASE1=$(git rev-parse HEAD)

# review: a judge seat below risk 3, Codex off for the session.
echo a > a.txt && git add a.txt && git commit -qm "feat: add a"
C1=$(git rev-parse HEAD)
review_surface absent
step review docs/plan.md 1
JP="$WS/task-1-review-prompt.md"
check "review: exit 0" "$rc" "0"
check "review: the digest is at most 15 lines" "$([ "$(count_lines "$out")" -le 15 ] && echo yes || echo no)" "yes"
check "review: the judge seat" "$(grep '^seat:' <<<"$out")" "seat: dforge:judge-sonnet-high prompt: $JP"
check "review: codex off shows the gate line" "$(grep -c '^gate: codex-gate usable=true' <<<"$out")" "1"
check "review: no runner lines for a judge seat" "$(grep -cE '^(codex|timeout):' <<<"$out")" "0"
check "review: no Codex prompt for a judge seat" "$([ -e "$WS/task-1-review-codex-prompt.md" ] && echo yes || echo no)" "no"
check "review: the judge prompt has no unexpanded placeholder" "$(placeholders "$JP")" "0"
check "review: base, head and diff file" "$(grep -E '^\*\*(Base|Head|Diff file):\*\*' "$JP" | tr '\n' ' ' | sed 's/ $//')" \
  "**Base:** $BASE1 **Head:** $C1 **Diff file:** $WS_RAW/review-$(short "$BASE1")..$(short "$C1").diff"
check "review: the diff file exists" "$([ -f "$WS/review-$(short "$BASE1")..$(short "$C1").diff" ] && echo yes || echo no)" "yes"
check "review: brief and report paths" "$(grep -cE "^(Read the task brief: $WS/task-1-brief.md|Read the implementer's report: $WS/task-1-report.md)\$" "$JP")" "2"
check "review: the criteria path is expanded" "$(grep -c "Read the criteria file at $PR/criteria/task-review.md and score" "$JP")" "1"
check "review: the lens path is named" "$(grep -c "^Read each lens file in $PR/criteria/lenses/lang-bash.md\. Lens criteria" "$JP")" "1"
check "review: no Second Pass section below risk 3" "$(grep -c 'Second Pass' "$JP")" "0"
check "review: identity check" "$(grep '^check identity' <<<"$out")" "check identity: clean"
check "review: attribution check" "$(grep '^check attribution' <<<"$out")" "check attribution: clean"
check "review: the state records the review head" "$(state_of 1 .reviewHead)" "$C1"
check "review: the state records t0" "$(state_of 1 '.t0 | type')" "number"
check "review: the state keeps the round" "$(state_of 1 .round)" "0"
check "review: the state line precedes the budget line" "$(tail -n 2 <<<"$out" | head -n 1)" \
  "state: base $(short "$BASE1") review-head $(short "$C1") round 0 t0 $(state_of 1 .t0)"
check "review: the last line is the budget line" "$(tail -n 1 <<<"$out" | cut -c1-6)" "budget"

step review docs/plan.md 2
check "review: a task with no lens drops the section" "$(grep -c 'Lens Criteria' "$WS/task-2-review-prompt.md")" "0"
check "review: and leaves no placeholder" "$(placeholders "$WS/task-2-review-prompt.md")" "0"

# review: a light Codex seat, with the judge prompt beside it as the fallback.
review_surface true
step review docs/plan.md 1
CP="$WS/task-1-review-codex-prompt.md"
check "review: the light seat" "$(grep '^seat:' <<<"$out")" "seat: codex:light prompt: $CP fallback: dforge:judge-sonnet-high prompt: $JP"
check "review: the runner command" "$(grep '^codex:' <<<"$out")" \
  "codex: bash \"$PR/scripts/run-codex-review.sh\" --kind task --tier light --cwd \"$TOP\" --out \"$WS/task-1-review-codex.json\" --prompt \"$CP\""
check "review: the light timeout" "$(grep '^timeout:' <<<"$out")" "timeout: 2520000"
check "review: no gate line while the surface is open" "$(grep -c '^gate:' <<<"$out")" "0"
check "review: the judge prompt is still written, with its lens" "$(grep -c 'Lens Criteria' "$JP")" "1"
check "review: the Codex prompt has no unexpanded placeholder" "$(placeholders "$CP")" "0"
check "review: the Codex prompt asks for one JSON object" "$(grep -c 'one JSON object' "$CP")" "1"
check "review: the Codex prompt carries the criteria" "$(grep -c '^#### Spec Compliance {#spec}$' "$CP")" "1"
check "review: the Codex prompt drops the markdown report" "$(grep -cE 'Verification Scores|Output Format|Lens Criteria|Second Pass' "$CP")" "0"
check "review: the Codex prompt names the diff file" "$(grep -c "^\*\*Diff file:\*\* $WS_RAW/review-" "$CP")" "1"
mkdir -p "$TMP/wt"
step review docs/plan.md 1 --cwd "$TMP/wt"
check "review: --cwd names the runner's working directory" "$(grep -c -- "--kind task --tier light --cwd \"$TMP/wt\" --out" <<<"$out")" "1"
step review docs/plan.md 1 --cwd "$TMP/no-such-dir"
check "review: a missing --cwd directory exits 2" "$rc" "2"

# review: a heavy Codex seat on risk 3, then the judge with the Second Pass section.
step start docs/plan.md 7
echo b > b.txt && git add b.txt && git commit -qm "feat: add b"
C2=$(git rev-parse HEAD)
step review docs/plan.md 7
JP7="$WS/task-7-review-prompt.md"
check "review: the heavy seat" "$(grep '^seat:' <<<"$out")" \
  "seat: codex:heavy+judge-opus prompt: $WS/task-7-review-codex-prompt.md then: dforge:judge-opus prompt: $JP7"
check "review: the heavy timeout" "$(grep '^timeout:' <<<"$out")" "timeout: 5520000"
check "review: the runner command names the tier" "$(grep -c -- '--kind task --tier heavy --cwd' <<<"$out")" "1"
check "review: the judge prompt carries the Second Pass section" "$(grep -c '^## Second Pass: The Codex Review$' "$JP7")" "1"
check "review: the Second Pass names the Codex output file" "$(grep -c "^review of the same diff: $WS/task-7-review-codex.json\$" "$JP7")" "1"
check "review: the Codex prompt leaves the Second Pass out" "$(grep -c 'Second Pass' "$WS/task-7-review-codex-prompt.md")" "0"
check "review: the risk-3 judge prompt has no placeholder" "$(placeholders "$JP7")" "0"
review_surface false
step review docs/plan.md 7
check "review: risk 3 with Codex off is a judge-opus seat" "$(grep '^seat:' <<<"$out")" "seat: dforge:judge-opus prompt: $JP7"
check "review: and carries no Second Pass section" "$(grep -c 'Second Pass' "$JP7")" "0"
review_surface absent

# review: --head and --base.
git branch taskref "$C1"
step review docs/plan.md 1 --head taskref
check "review: --head records the ref" "$(state_of 1 .head)" "taskref"
check "review: --head records the ref's commit" "$(state_of 1 .reviewHead)" "$C1"
check "review: --head packages base..REF" "$(grep -c "^\*\*Head:\*\* $C1\$" "$JP")" "1"
step review docs/plan.md 1
check "review: a later review reuses the recorded ref" "$(state_of 1 .reviewHead)" "$C1"
step review docs/plan.md 2 --base "$C1"
DIFF2="$WS_RAW/review-$(short "$C1")..$(short "$C2").diff"
check "review: --base starts the package at SHA" "$(grep -c "^\*\*Diff file:\*\* $DIFF2\$" "$WS/task-2-review-prompt.md")" "1"
check "review: --base leaves the earlier commit out" "$(grep -c 'add a' "$DIFF2")" "0"
check "review: --base is recorded" "$(state_of 2 .base)" "$C1"
step review docs/plan.md 1 --head nope
check "review: a bad ref exits 2" "$rc" "2"
check "review: a bad ref leaves the state alone" "$(state_of 1 .head)" "taskref"
step review docs/plan.md 1 --base nope
check "review: a bad base exits 2" "$rc" "2"

# review: the mechanical checks.
CO="Co-Authored""-By"
CS="Claude""-Session"
PREV=$(git rev-parse HEAD)
git commit -q --allow-empty --author="Other <other@example.invalid>" -m "feat: written by another author"
step review docs/plan.md 2 --base "$PREV"
check "check identity: a different author" "$(grep '^check identity' <<<"$out")" \
  "check identity: $(short HEAD) author Other <other@example.invalid> (expected Darkraise <dark@example.invalid>)"
check "check attribution: clean beside a bad identity" "$(grep '^check attribution' <<<"$out")" "check attribution: clean"
PREV=$(git rev-parse HEAD)
GIT_COMMITTER_NAME=Other GIT_COMMITTER_EMAIL=other@example.invalid git commit -q --allow-empty -m "feat: committed by another"
step review docs/plan.md 2 --base "$PREV"
check "check identity: a different committer" "$(grep '^check identity' <<<"$out")" \
  "check identity: $(short HEAD) committer Other <other@example.invalid> (expected Darkraise <dark@example.invalid>)"
PREV=$(git rev-parse HEAD)
git -c user.name=Other -c user.email=other@example.invalid commit -q --allow-empty -m "feat: both differ"
step review docs/plan.md 2 --base "$PREV"
check "check identity: author and committer" "$(grep '^check identity' <<<"$out")" \
  "check identity: $(short HEAD) author Other <other@example.invalid>, committer Other <other@example.invalid> (expected Darkraise <dark@example.invalid>)"
PREV=$(git rev-parse HEAD)
git commit -q --allow-empty -m "feat: with a co-author" -m "$CO: X <x@example.invalid>"
step review docs/plan.md 2 --base "$PREV"
check "check attribution: a co-author trailer" "$(grep '^check attribution' <<<"$out")" \
  "check attribution: $(short HEAD) $CO: X <x@example.invalid>"
check "check identity: clean beside a bad attribution" "$(grep '^check identity' <<<"$out")" "check identity: clean"
PREV=$(git rev-parse HEAD)
git commit -q --allow-empty -m "feat: with a session" -m "$CS: abc123"
step review docs/plan.md 2 --base "$PREV"
check "check attribution: a session trailer" "$(grep '^check attribution' <<<"$out")" "check attribution: $(short HEAD) $CS: abc123"
PREV=$(git rev-parse HEAD)
git commit -q --allow-empty -m "feat: tool line" -m "Generated with a tool"
step review docs/plan.md 2 --base "$PREV"
check "check attribution: a generated-with line" "$(grep '^check attribution' <<<"$out")" "check attribution: $(short HEAD) Generated with a tool"
PREV=$(git rev-parse HEAD)
git commit -q --allow-empty -m "feat: emoji line" -m "🤖 Generated with a tool"
step review docs/plan.md 2 --base "$PREV"
check "check attribution: a symbol before generated-with still counts" "$(grep '^check attribution' <<<"$out")" "check attribution: $(short HEAD) 🤖 Generated with a tool"
PREV=$(git rev-parse HEAD)
git commit -q --allow-empty -m "feat: lowercase trailer" -m "co-authored-by: X <x@example.invalid>"
step review docs/plan.md 2 --base "$PREV"
check "check attribution: the trailer name is case-insensitive" "$(grep '^check attribution' <<<"$out")" "check attribution: $(short HEAD) co-authored-by: X <x@example.invalid>"
PREV=$(git rev-parse HEAD)
git commit -q --allow-empty -m "feat: mentions the words" -m "The table is generated with a script, and a co-authored-by: note is prose here."
step review docs/plan.md 2 --base "$PREV"
check "check attribution: the words inside a sentence are not a trailer" "$(grep '^check attribution' <<<"$out")" "check attribution: clean"
PREV=$(git rev-parse HEAD)
git commit -q --allow-empty -m "feat: clean one"
step review docs/plan.md 2 --base "$PREV"
check "checks: a clean commit passes both" "$(grep '^check' <<<"$out" | tr '\n' ';')" "check identity: clean;check attribution: clean;"
step review docs/plan.md 2 --base "$(git rev-parse HEAD~9)"
check "checks: several offenders name the first and count the rest" "$(grep '^check attribution' <<<"$out" | grep -c '; 4 more commit(s)$')" "1"

# review: a batch, and a route that fails.
step review docs/plan.md 5 6
check "review: a batch names its tasks" "$(head -n 1 <<<"$out" | cut -c1-19)" "task 5,6: reviewed "
check "review: a batch state is named after its first task" "$(state_of 5 .reviewHead)" "$(git rev-parse HEAD)"
check "review: a batch prompt names the batch brief" "$(grep -c "^Read the task brief: $WS/task-5-brief.md\$" "$WS/task-5-review-prompt.md")" "1"
step start docs/plan.md 8
step review docs/plan.md 8
check "review: a failed route falls back to judge-opus and says why" \
  "$(grep -c "^seat: dforge:judge-opus prompt: $WS/task-8-review-prompt.md (review-route exited 2: review-route: Task 8: the Evaluation line does not parse" <<<"$out")" "1"

# review: a lens-route failure stops the step before it writes anything.
step start docs/plan.md 9
state9=$(cat "$WS/task-9-step.json")
step review docs/plan.md 9
check "review: a lens-route failure exits 2" "$rc" "2"
check "review: a lens-route failure says which lens" "$(grep -c 'unknown lens id: no-such-lens' "$TMP/err")" "1"
check "review: a lens-route failure writes no prompt file" "$([ -e "$WS/task-9-review-prompt.md" ] && echo yes || echo no)" "no"
check "review: a lens-route failure leaves the state file alone" "$(cat "$WS/task-9-step.json")" "$state9"

# --- rereview: the skip rule, the package and the state ---
# The fixture plan's lines carry a leading | so a plan that quotes this suite still lints.
RR_S="$HERE/../scripts"
RR_TMP=$TMP/rr
mkdir -p "$RR_TMP"
RR_REPO=$RR_TMP/repo
rr_run() { # rr_run <args...> — task-step in the fixture repo; sets rr_out, rr_err, rr_rc
  rr_out=$(cd "$RR_REPO" && env HOME="$RR_TMP/home" DR_CODEX_SESSION_DIR="$RR_TMP/sessions" CLAUDE_CODE_SESSION_ID=rr-test \
    GIT_CONFIG_NOSYSTEM=1 DFORGE_NO_SETTINGS=1 MSYS_NO_PATHCONV=1 bash "$RR_S/task-step" "$@" 2>"$RR_TMP/err"); rr_rc=$?
  rr_err=$(cat "$RR_TMP/err")
}
rr_git() { git -C "$RR_REPO" "$@"; }
rr_state() { # rr_state <task> <jq filter>
  jq -r "$2" "$RR_WS/task-$1-step.json" | tr -d '\r'
}
rr_edit() { # rr_edit <file> <mod|add1|add3|add4|bin> — change a fixture file
  local f=$RR_REPO/$1
  RR_N=$((RR_N + 1))
  case $2 in
    mod) awk -v n="$RR_N" 'NR == 2 { print "changed " n; next } { print }' "$f" > "$f.tmp" && mv "$f.tmp" "$f" ;;
    add1) printf 'a%s\n' "$RR_N" >> "$f" ;;
    add3) printf 'a%s\nb\nc\n' "$RR_N" >> "$f" ;;
    add4) printf 'a%s\nb\nc\nd\n' "$RR_N" >> "$f" ;;
    bin) printf 'x\000y%s' "$RR_N" >> "$f" ;;
  esac
}
rr_fix() { # rr_fix <task> <round> <bullets separated by |>
  { printf '%s\n' "$3" | tr '|' '\n'; printf '\nFixed.\n'; } > "$RR_WS/task-$1-fix-$2.md"
}
rr_reset() { # back to the reviewed head with the recorded states
  rr_git reset -q --hard "$RR_R0"
  rm -f "$RR_WS"/task-*-fix-*.md "$RR_WS"/task-*-rereview-*-prompt.md
  cp "$RR_TMP/state1.0" "$RR_WS/task-1-step.json"
  cp "$RR_TMP/state2.0" "$RR_WS/task-2-step.json"
}
rr_verdict() { # rr_verdict <task> <round> — the skip line, or "prompt", or "none"
  if grep -q '^re-review: ' <<<"$rr_out"; then grep '^re-review: ' <<<"$rr_out"
  elif [ -f "$RR_WS/task-$1-rereview-$2-prompt.md" ]; then echo prompt
  else echo none; fi
}
rr_case() { # rr_case <name> <task> <flags> <bullets> <edits> <want> — one fix, one rereview
  local e
  rr_reset
  for e in $5; do rr_edit "${e%%:*}" "${e#*:}"; done
  rr_git add -A && rr_git commit -qm fix
  rr_fix "$2" 1 "$4"
  # shellcheck disable=SC2086
  rr_run rereview docs/plan.md "$2" $3
  check "rereview $1" "$rr_rc $(rr_verdict "$2" 1)" "$6"
}

mkdir -p "$RR_TMP/home" "$RR_REPO/docs"
git init -q "$RR_REPO"
rr_git config user.name t
rr_git config user.email t@example.invalid
sed 's/^|//' > "$RR_REPO/docs/plan.md" <<'PLAN'
|# Rereview Fixture Plan
|
|**Goal:** Fixture.
|
|**Execution:** subagent — `claude --model sonnet --effort high` — fixture
|
|## Task index
|
|1. Small
|2. Risky
|3. Unreviewed
|
|### Task 1: Small
|
|**Files:**
|- Modify: `app.txt`
|
|**Implementer:** dforge:impl-sonnet-low
|**Evaluation:** files 0 - spec 0 - coupling 1 - risk 0 = 1
|
|### Task 2: Risky
|
|**Files:**
|- Modify: `app.txt`
|
|**Implementer:** dforge:impl-opus-high
|**Evaluation:** files 1 - spec 1 - coupling 1 - risk 3 = 6
|
|### Task 3: Unreviewed
|
|**Files:**
|- Modify: `other.txt`
|
|**Implementer:** dforge:impl-sonnet-low
|**Evaluation:** files 0 - spec 0 - coupling 1 - risk 0 = 1
PLAN
awk '{ print } /^\*\*Goal:\*\*/ { print ""; print "**Host:** codex" }' "$RR_REPO/docs/plan.md" > "$RR_REPO/docs/codex-plan.md"
seq 1 10 | sed 's/^/line /' > "$RR_REPO/app.txt"
cp "$RR_REPO/app.txt" "$RR_REPO/other.txt"
cp "$RR_REPO/app.txt" "$RR_REPO/test.txt"
printf 'a\000b' > "$RR_REPO/bin.dat"
rr_git add -A && rr_git commit -qm base
RR_N=0

rr_run start docs/plan.md 1
check "rereview fixture: start 1" "$rr_rc" "0"
rr_run start docs/plan.md 2
check "rereview fixture: start 2" "$rr_rc" "0"
rr_run start docs/plan.md 3
check "rereview fixture: start 3" "$rr_rc" "0"
rr_edit app.txt mod
rr_git add -A && rr_git commit -qm work
rr_run review docs/plan.md 1
check "rereview fixture: review 1" "$rr_rc" "0"
rr_run review docs/plan.md 2
check "rereview fixture: review 2" "$rr_rc" "0"
RR_WS=$(winpath "$(cd "$RR_REPO" && env HOME="$RR_TMP/home" bash "$RR_S/sdd-workspace" docs/plan.md)")
RR_R0=$(rr_git rev-parse HEAD)
cp "$RR_WS/task-1-step.json" "$RR_TMP/state1.0"
cp "$RR_WS/task-2-step.json" "$RR_TMP/state2.0"

# The skip rule: one open finding, at most 3 changed lines (test files
# included) touching the finding's file, a task below risk 3, and --covered.
rr_case "skips a one-line fix" 1 --covered "- app.txt: wrong value" "app.txt:mod" "0 re-review: skipped (2 changed lines, 1 finding, app.txt)"
rr_case "skips exactly 3 changed lines" 1 --covered "- app.txt: wrong value" "app.txt:add3" "0 re-review: skipped (3 changed lines, 1 finding, app.txt)"
rr_case "counts a test file edit toward the limit" 1 --covered "- app.txt: wrong value" "app.txt:mod test.txt:mod" "0 prompt"
rr_case "skips a small fix that also adds a test line" 1 --covered "- app.txt: wrong value" "app.txt:add1 test.txt:add1" "0 re-review: skipped (2 changed lines, 1 finding, app.txt)"
rr_case "does not skip 4 changed lines" 1 --covered "- app.txt: wrong value" "app.txt:add4" "0 prompt"
rr_case "does not skip without --covered" 1 "" "- app.txt: wrong value" "app.txt:mod" "0 prompt"
rr_case "does not skip with two open findings" 1 --covered "- app.txt: wrong value|- other.txt: stale" "app.txt:mod" "0 prompt"
rr_case "does not skip a fix that edits only another test file" 1 --covered "- app.txt: wrong value" "test.txt:mod" "0 prompt"
rr_case "does not skip a fix to another file than the finding's" 1 --covered "- app.txt: wrong value" "other.txt:mod" "0 prompt"
rr_case "does not skip a binary fix" 1 --covered "- bin.dat: wrong blob" "bin.dat:bin" "0 prompt"
rr_case "does not skip a risk 3 task" 2 --covered "- app.txt: wrong value" "app.txt:mod" "0 prompt"
rr_case "reads a backticked finding path with a line suffix" 1 --covered '- `app.txt:12`: wrong value' "app.txt:mod" "0 re-review: skipped (2 changed lines, 1 finding, app.txt)"

# A skipped round still packages the fix and advances the state.
rr_reset
rr_edit app.txt mod
rr_git add -A && rr_git commit -qm fix
rr_fix 1 1 "- app.txt: wrong value"
jq '.t0 = 1' "$RR_WS/task-1-step.json" > "$RR_TMP/t0.tmp" && cp "$RR_TMP/t0.tmp" "$RR_WS/task-1-step.json"
rr_run rereview docs/plan.md 1 --covered
check "rereview skip: records the head as the review head" "$(rr_state 1 .reviewHead)" "$(rr_git rev-parse HEAD)"
check "rereview skip: increments the round" "$(rr_state 1 .round)" "1"
check "rereview skip: replaces t0 with the time of the re-review" "$([ "$(rr_state 1 .t0)" -gt 1000000000 ] && echo yes || echo no)" "yes"
check "rereview skip: the digest shows the recorded t0" "$(sed -n 's/^state: .* t0 //p' <<<"$rr_out")" "$(rr_state 1 .t0)"
check "rereview skip: the digest fits 15 lines" "$([ "$(wc -l <<<"$rr_out")" -le 15 ] && echo yes || echo no)" "yes"
check "rereview skip: the digest names the state" "$(grep -c "^state: base .* review-head $(rr_git rev-parse --short HEAD) round 1 t0 " <<<"$rr_out")" "1"
check "rereview skip: the digest ends with the budget line" "$(tail -n 1 <<<"$rr_out" | cut -c1-7)" "budget:"
check "rereview skip: no prompt is written" "$(ls "$RR_WS"/task-1-rereview-*-prompt.md 2>/dev/null | wc -l | tr -d ' ')" "0"

# A written prompt: the judge seat, no unexpanded placeholder, the open
# findings, the fix base and the diff file.
rr_reset
rr_edit app.txt add4
rr_git add -A && rr_git commit -qm fix
rr_fix 1 1 "- app.txt: wrong value|- other.txt: stale"
rr_run rereview docs/plan.md 1 --covered
RR_P=$RR_WS/task-1-rereview-1-prompt.md
check "rereview prompt: the digest names the seat and the file" "$(grep -c "^seat: dforge:judge-sonnet-high prompt: $RR_P\$" <<<"$rr_out")" "1"
check "rereview prompt: no placeholder is left" "$(grep -cE '\[(BRIEF_FILE|FINDINGS|REPORT_FILE|FIX_BASE_SHA|HEAD_SHA|DIFF_FILE|MODEL)\]' "$RR_P")" "0"
check "rereview prompt: the open findings are listed" "$(grep -c '^- app.txt: wrong value$\|^- other.txt: stale$' "$RR_P")" "2"
check "rereview prompt: the fix base is the recorded review head" "$(grep -c "Fix base:\*\* $RR_R0 " "$RR_P")" "1"
check "rereview prompt: the head is HEAD" "$(grep -c "Head:\*\* $(rr_git rev-parse HEAD)\$" "$RR_P")" "1"
RR_DIFF=$(sed -n 's/^\*\*Diff file:\*\* //p' "$RR_P")
check "rereview prompt: the diff file exists" "$([ -s "$RR_DIFF" ] && echo yes || echo no)" "yes"
check "rereview prompt: the report and brief paths" "$(grep -c "$RR_WS/task-1-report.md\|$RR_WS/task-1-brief.md" "$RR_P")" "2"
check "rereview prompt: the fence and indent are removed" "$(grep -c '^```\|^    You are re-reviewing' "$RR_P")" "0"

# Rounds chain: the next round's base is the last round's head.
RR_H1=$(rr_git rev-parse HEAD)
rr_edit app.txt add4
rr_git add -A && rr_git commit -qm fix2
rr_fix 1 2 "- app.txt: still wrong"
rr_run rereview docs/plan.md 1 --covered
check "rereview round 2: writes the round 2 prompt" "$([ -f "$RR_WS/task-1-rereview-2-prompt.md" ] && echo yes || echo no)" "yes"
check "rereview round 2: the fix base is round 1's head" "$(grep -c "Fix base:\*\* $RR_H1 " "$RR_WS/task-1-rereview-2-prompt.md")" "1"
check "rereview round 2: the state round is 2" "$(rr_state 1 .round)" "2"

# --base moves the package start, and the skip rule counts from it.
rr_reset
rr_edit app.txt mod
rr_git add -A && rr_git commit -qm fix-a
rr_edit app.txt add3
rr_git add -A && rr_git commit -qm fix-b
rr_fix 1 1 "- app.txt: wrong value"
rr_run rereview docs/plan.md 1 --covered
check "rereview without --base counts from the recorded review head" "$(rr_verdict 1 1)" "prompt"
rr_reset
rr_edit app.txt mod
rr_git add -A && rr_git commit -qm fix-a
RR_A=$(rr_git rev-parse HEAD)
rr_edit app.txt add3
rr_git add -A && rr_git commit -qm fix-b
rr_fix 1 1 "- app.txt: wrong value"
rr_run rereview docs/plan.md 1 --covered --base "$RR_A"
check "rereview --base counts from the given base" "$(rr_verdict 1 1)" "re-review: skipped (3 changed lines, 1 finding, app.txt)"
rr_reset
rr_edit app.txt mod
rr_git add -A && rr_git commit -qm fix-a
RR_A=$(rr_git rev-parse HEAD)
rr_edit app.txt add3
rr_git add -A && rr_git commit -qm fix-b
rr_fix 1 1 "- app.txt: wrong value"
rr_run rereview docs/plan.md 1 --base "$RR_A"
check "rereview --base: the prompt's fix base is the given base" "$(grep -c "Fix base:\*\* $RR_A " "$RR_WS/task-1-rereview-1-prompt.md")" "1"
check "rereview --base: the diff file starts at the given base" "$(sed -n 's/^\*\*Diff file:\*\* //p' "$RR_WS/task-1-rereview-1-prompt.md" | xargs basename | grep -c "^review-$(rr_git rev-parse --short "$RR_A")\.\.")" "1"
check "rereview --base: the state records it as the base" "$(rr_state 1 .base)" "$RR_A"
check "rereview --base: the state line shows it" "$(grep -c "^state: base $(rr_git rev-parse --short "$RR_A") " <<<"$rr_out")" "1"

# --head packages up to the task ref and leaves later commits out.
rr_reset
rr_edit app.txt mod
rr_git add -A && rr_git commit -qm fix-a
rr_git branch -f rr-task-ref
rr_edit app.txt add4
rr_git add -A && rr_git commit -qm later
rr_fix 1 1 "- app.txt: wrong value"
rr_run rereview docs/plan.md 1 --covered --head rr-task-ref
check "rereview --head: skips on the ref's diff alone" "$(rr_verdict 1 1)" "re-review: skipped (2 changed lines, 1 finding, app.txt)"
check "rereview --head: records the ref's commit as the review head" "$(rr_state 1 .reviewHead)" "$(rr_git rev-parse rr-task-ref)"
check "rereview --head: records the ref" "$(rr_state 1 .head)" "rr-task-ref"

# A zero-padded task number names the same task.
rr_reset
rr_edit app.txt mod
rr_git add -A && rr_git commit -qm fix
rr_fix 1 1 "- app.txt: wrong value"
rr_run rereview docs/plan.md 01 --covered
check "rereview names Task 1 as 01" "$rr_rc $(rr_verdict 1 1)" "0 re-review: skipped (2 changed lines, 1 finding, app.txt)"

# Refusals write nothing.
rr_reset
rr_run rereview docs/plan.md 3
check "rereview before review exits 6" "$rr_rc" "6"
rr_reset
rr_run rereview docs/plan.md 1 --covered
check "rereview with no fix message exits 6" "$rr_rc" "6"
check "rereview with no fix message leaves the state alone" "$(cmp -s "$RR_WS/task-1-step.json" "$RR_TMP/state1.0" && echo same || echo changed)" "same"
printf 'No bullets here.\n' > "$RR_WS/task-1-fix-1.md"
rr_run rereview docs/plan.md 1
check "rereview with a fix message that has no bullets exits 2" "$rr_rc" "2"
rr_reset
rr_run rereview docs/plan.md 99
check "rereview of a task not in the plan exits 3" "$rr_rc" "3"
rr_run rereview docs/codex-plan.md 1
check "rereview on a Host: codex plan exits 2" "$rr_rc" "2"
check "rereview on a Host: codex plan writes nothing" "$(ls -A "$(dirname "$RR_WS")/codex-plan" 2>/dev/null | wc -l | tr -d ' ')" "0"
rr_run rereview docs/plan.md 1 --bogus
check "rereview with an unknown flag exits 2" "$rr_rc" "2"
rr_run rereview docs/plan.md 1 --base ""
check "rereview with an empty --base exits 2" "$rr_rc" "2"
rr_run rereview docs/plan.md 1 --head ""
check "rereview with an empty --head exits 2" "$rr_rc" "2"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
