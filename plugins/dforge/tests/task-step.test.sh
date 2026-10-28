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
# sdd-workspace and task-step print the form git gives, which native jq.exe can
# open.
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
check "start: the plugin root is expanded to this plugin" "$(grep -c "$(cd "$P" && pwd)/scripts/context-size" "$D")" "1"
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
  "**Base:** $BASE1 **Head:** $C1 **Diff file:** $WS/review-$(short "$BASE1")..$(short "$C1").diff"
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
check "review: the Codex prompt names the diff file" "$(grep -c "^\*\*Diff file:\*\* $WS/review-" "$CP")" "1"
mkdir -p "$TMP/plain"
state1=$(cat "$WS/task-1-step.json")
step review docs/plan.md 1 --cwd "$TMP/plain"
check "review: a --cwd outside any git work tree exits 2" "$rc" "2"
check "review: and says the tracked files cannot be recorded" "$(grep -c 'cannot record the tracked files' "$TMP/err")" "1"
check "review: and leaves the state file alone" "$(cat "$WS/task-1-step.json")" "$state1"
git worktree add -q --detach "$TMP/wt" HEAD
step review docs/plan.md 1 --cwd "$TMP/wt"
check "review: --cwd names the runner's working directory" "$(grep -c -- "--kind task --tier light --cwd \"$TMP/wt\" --out" <<<"$out")" "1"
git worktree remove --force "$TMP/wt"
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
DIFF2="$WS/review-$(short "$C1")..$(short "$C2").diff"
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

# review: the judge writes its report where the prompt says, and a fresh
# review discards the last one; the Codex seat gets no report-file rule.
review_surface absent
printf 'stale\n' > "$WS/task-2-review-report.md"
step review docs/plan.md 2
RP2="$WS/task-2-review-prompt.md"
check "review report: exit 0" "$rc" "0"
check "review report: the prompt names the report file" \
  "$(grep -cF "Write your full report to $WS/task-2-review-report.md and write nothing else" "$RP2")" "1"
check "review report: the implementer's report keeps its own line" "$(grep -cF "Read the implementer's report: $WS/task-2-report.md" "$RP2")" "1"
check "review report: no placeholder is left" "$(placeholders "$RP2")" "0"
check "review report: a fresh review discards the last report" "$([ -e "$WS/task-2-review-report.md" ] && echo yes || echo no)" "no"
review_surface true
step review docs/plan.md 1
check "review report: the Codex prompt carries no report-file rule" \
  "$(grep -c 'review-report.md\|write nothing else' "$WS/task-1-review-codex-prompt.md")" "0"
check "review report: the Codex prompt keeps the implementer's report" \
  "$(grep -cF "Read the implementer's report: $WS/task-1-report.md" "$WS/task-1-review-codex-prompt.md")" "1"
review_surface absent

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

# The loop holds two rounds: a third rereview writes nothing and names the breaker.
rr_edit app.txt add4
rr_git add -A && rr_git commit -qm fix3
rr_fix 1 3 "- app.txt: still wrong"
cp "$RR_WS/task-1-step.json" "$RR_TMP/state1.2"
rr_run rereview docs/plan.md 1 --covered
check "rereview round 3: exits 7" "$rr_rc" "7"
check "rereview round 3: names the cap and the breaker" "$(grep -c 'task-step: fix round 3 is past the cap of 2; send the open findings to the breaker' <<<"$rr_err")" "1"
check "rereview round 3: writes no prompt" "$([ -f "$RR_WS/task-1-rereview-3-prompt.md" ] && echo yes || echo no)" "no"
check "rereview round 3: leaves the state alone" "$(cmp -s "$RR_WS/task-1-step.json" "$RR_TMP/state1.2" && echo same || echo changed)" "same"
check "rereview round 3: prints no digest" "$rr_out" ""
# A step state an older run left at round 4 of 5 goes to the breaker too.
jq '.round = 4' "$RR_TMP/state1.2" > "$RR_WS/task-1-step.json"
rr_fix 1 5 "- app.txt: still wrong"
rr_run rereview docs/plan.md 1 --covered
check "rereview after an older run's round 4: exits 7" "$rr_rc" "7"
check "rereview after an older run's round 4: names round 5" "$(grep -c 'fix round 5 is past the cap of 2' <<<"$rr_err")" "1"

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

# --- hold and review --group: grouped tasks reviewed together ---
# The fixture plan's lines carry a leading | so a plan that quotes this suite still lints.
GR_TMP=$TMP/gr
GR_REPO=$GR_TMP/repo
mkdir -p "$GR_TMP/home" "$GR_REPO/docs"
gr_run() { # gr_run <args...> — task-step in the group fixture repo; sets gr_out, gr_err, gr_rc
  gr_out=$(cd "$GR_REPO" && env HOME="$GR_TMP/home" DR_CODEX_SESSION_DIR="$GR_TMP/sessions" CLAUDE_CODE_SESSION_ID=gr-test \
    GIT_CONFIG_NOSYSTEM=1 DFORGE_NO_SETTINGS=1 MSYS_NO_PATHCONV=1 bash "$RR_S/task-step" "$@" 2>"$GR_TMP/err"); gr_rc=$?
  gr_err=$(cat "$GR_TMP/err")
}
gr_git() { git -C "$GR_REPO" "$@"; }
gr_commit() { # gr_commit <file> — append a line to a fixture file and commit it
  GR_N=$((GR_N + 1))
  printf 'line %s\n' "$GR_N" >> "$GR_REPO/$1"
  gr_git add -A && gr_git commit -qm "feat: change $1"
}
gr_short() { gr_git rev-parse --short "$1"; }
gr_state() { # gr_state <task> <jq filter>
  jq -r "$2" "$GR_WS/task-$1-step.json" | tr -d '\r'
}
gr_lines() { wc -l < "$GR_LEDGER" | tr -d ' '; }
gr_section() { # gr_section <package> <task> — the package's section for one task
  awk -v h="## Task $2" '{ sub(/\r$/, "") } $0 == h { on = 1; next } /^## / { on = 0 } on' "$1"
}

git init -q "$GR_REPO"
gr_git config user.name t
gr_git config user.email t@example.invalid
sed 's/^|//' > "$GR_REPO/docs/plan.md" <<'PLAN'
|# Group Fixture Plan
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
|1. Light one
|2. Light two
|3. Heavy
|4. Light three
|5. Unscored
|6. Wave six
|7. Wave seven
|
|### Task 1: Light one
|
|**Files:**
|- Modify: `one.txt`
|
|**Implementer:** dforge:impl-sonnet-low
|**Evaluation:** files 0 - spec 0 - coupling 1 - risk 0 = 1
|**Lenses:** lang-bash
|
|### Task 2: Light two
|
|**Files:**
|- Modify: `two.txt`
|
|**Implementer:** dforge:impl-sonnet-medium
|**Evaluation:** files 1 - spec 1 - coupling 1 - risk 1 = 4
|
|### Task 3: Heavy
|
|**Files:**
|- Modify: `three.txt`
|
|**Implementer:** dforge:impl-opus-high
|**Evaluation:** files 1 - spec 1 - coupling 1 - risk 2 = 5
|
|### Task 4: Light three
|
|**Files:**
|- Modify: `four.txt`
|
|**Implementer:** dforge:impl-sonnet-low
|**Evaluation:** files 0 - spec 1 - coupling 1 - risk 0 = 2
|
|### Task 5: Unscored
|
|**Implementer:** dforge:impl-sonnet-low
|
|Body.
|
|### Task 6: Wave six
|
|**Files:**
|- Modify: `six.txt`
|
|**Implementer:** dforge:impl-sonnet-low
|**Evaluation:** files 0 - spec 0 - coupling 1 - risk 0 = 1
|
|### Task 7: Wave seven
|
|**Files:**
|- Modify: `seven.txt`
|
|**Implementer:** dforge:impl-sonnet-low
|**Evaluation:** files 0 - spec 0 - coupling 1 - risk 0 = 1
PLAN
awk '{ print } /^\*\*Goal:\*\*/ { print ""; print "**Host:** codex" }' "$GR_REPO/docs/plan.md" > "$GR_REPO/docs/codex-plan.md"
for f in one two three four six seven; do printf 'base\n' > "$GR_REPO/$f.txt"; done
gr_git add -A && gr_git commit -qm base
GR_N=0
GR_MAIN=$(gr_git symbolic-ref --short HEAD)
GR_WS=$(winpath "$(cd "$GR_REPO" && env HOME="$GR_TMP/home" bash "$RR_S/sdd-workspace" docs/plan.md)")
GR_LEDGER=$GR_WS/progress.md

# hold: the preconditions, then the awaiting line and the held head.
gr_run hold docs/plan.md 1
check "hold: before start exits 6" "$gr_rc" "6"
gr_run start docs/plan.md 1
GR_B1=$(gr_git rev-parse HEAD)
gr_commit one.txt
GR_H1=$(gr_git rev-parse HEAD)
gr_run hold docs/plan.md 1
check "hold: exit 0" "$gr_rc" "0"
check "hold: the awaiting line" "$(tail -n 1 "$GR_LEDGER")" "Task 1: awaiting group review (commits $(gr_short "$GR_B1")..$(gr_short "$GR_H1"))"
check "hold: records the held head" "$(gr_state 1 .heldHead)" "$GR_H1"
check "hold: keeps the base" "$(gr_state 1 .base)" "$GR_B1"
check "hold: the digest's first line" "$(head -n 1 <<<"$gr_out")" "task 1: held for group review (commits $(gr_short "$GR_B1")..$(gr_short "$GR_H1"))"
check "hold: the digest is at most 15 lines" "$([ "$(count_lines "$gr_out")" -le 15 ] && echo yes || echo no)" "yes"
check "hold: the last line is the budget line" "$(tail -n 1 <<<"$gr_out" | cut -c1-6)" "budget"
before=$(gr_lines)
gr_run hold docs/plan.md 1
check "hold again: exit 0" "$gr_rc" "0"
check "hold again: no second awaiting line" "$(gr_lines)" "$before"

# hold refuses a task review-route reviews alone, and writes nothing for it.
gr_run start docs/plan.md 3
gr_commit three.txt
before=$(gr_lines)
gr_run hold docs/plan.md 3
check "hold: a review=task task exits 4" "$gr_rc" "4"
check "hold: says the task is reviewed alone" "$(grep -c 'review=task' <<<"$gr_err")" "1"
check "hold: a review=task task gets no awaiting line" "$(gr_lines)" "$before"
check "hold: a review=task task records no held head" "$(gr_state 3 '.heldHead // "none"')" "none"
gr_run hold docs/plan.md 5
check "hold: an unscored task is reviewed alone and exits 4" "$gr_rc" "4"
gr_run hold docs/plan.md 99
check "hold: no such task exits 3" "$gr_rc" "3"
gr_run hold docs/plan.md
check "hold: no task number exits 2" "$gr_rc" "2"
gr_run hold docs/plan.md 1 2
check "hold: two task numbers exit 2" "$gr_rc" "2"
gr_run hold docs/plan.md 1 --head
check "hold: --head without a value exits 2" "$gr_rc" "2"
gr_run hold docs/plan.md 1 --head nope
check "hold: a bad ref exits 2" "$gr_rc" "2"
gr_run hold docs/codex-plan.md 1
check "hold: a Host: codex plan exits 2" "$gr_rc" "2"

gr_run start docs/plan.md 2
GR_B2=$(gr_git rev-parse HEAD)
gr_commit two.txt
gr_run hold docs/plan.md 2
gr_run start docs/plan.md 4
gr_commit four.txt
GR_H4=$(gr_git rev-parse HEAD)
gr_run hold docs/plan.md 4
check "hold: a third grouped task" "$gr_rc" "0"

# review --group: every member must be held.
gr_run review --group docs/plan.md 1 3
check "review --group: a member that is not held exits 4" "$gr_rc" "4"
check "review --group: names the task that is not held" "$(grep -c 'Task 3' <<<"$gr_err")" "1"
check "review --group: a refused group writes no file" "$(ls "$GR_WS" | grep -c '^group-')" "0"
gr_run review --group docs/plan.md 1 5
check "review --group: a task with no ledger line exits 4" "$gr_rc" "4"
gr_run review --group docs/plan.md 1 99
check "review --group: no such task exits 3" "$gr_rc" "3"
gr_run review --group docs/plan.md
check "review --group: no task number exits 2" "$gr_rc" "2"
gr_run review --group docs/plan.md 1 2 --head HEAD
check "review --group: --head is not a group flag" "$gr_rc" "2"
gr_run review --group docs/codex-plan.md 1
check "review --group: a Host: codex plan exits 2" "$gr_rc" "2"

# review --group: the package, the prompt, the digest and the state. The review
# surface is open, and a group is still reviewed by a Claude judge alone.
mkdir -p "$GR_TMP/sessions"
printf '{"session_id":"gr-test","usable":true,"review":true,"lane":false}\n' > "$GR_TMP/sessions/gr-test.json"
gr_run review --group docs/plan.md 4 1 2
GL=1,2,4
GPKG=$GR_WS/group-$GL-review-package.md
GPR=$GR_WS/group-$GL-review-prompt.md
check "review --group: exit 0" "$gr_rc" "0"
check "review --group: the files are named after the sorted list" \
  "$([ -f "$GR_WS/group-$GL-step.json" ] && [ -f "$GPKG" ] && [ -f "$GPR" ] && echo yes || echo no)" "yes"
check "review --group: one section per task, in order" "$(grep '^## ' "$GPKG" | tr -d '\r' | tr '\n' ';')" "## Task 1;## Task 2;## Task 4;"
check "review --group: a section names its brief" "$(gr_section "$GPKG" 1 | grep -cxF "**Brief:** $GR_WS/task-1-brief.md")" "1"
check "review --group: a section names its report" "$(gr_section "$GPKG" 1 | grep -cxF "**Report:** $GR_WS/task-1-report.md")" "1"
check "review --group: a section names its range" "$(gr_section "$GPKG" 1 | grep -cxF "**Commits:** $(gr_short "$GR_B1")..$(gr_short "$GR_H1")")" "1"
check "review --group: a section holds its own diff" "$(gr_section "$GPKG" 1 | grep -c '^diff --git a/one.txt b/one.txt$')" "1"
check "review --group: a section holds no other task's diff" "$(gr_section "$GPKG" 1 | grep -cE '^diff --git a/(two|three|four)\.txt')" "0"
check "review --group: a later member's diff starts at its own base" "$(gr_section "$GPKG" 2 | grep -cE '^diff --git a/(one|three|four)\.txt')" "0"
check "review --group: the later member's diff" "$(gr_section "$GPKG" 2 | grep -c '^diff --git a/two.txt b/two.txt$')" "1"
check "review --group: the last member's diff" "$(gr_section "$GPKG" 4 | grep -c '^diff --git a/four.txt b/four.txt$')" "1"
check "review --group: a section names its lens files" "$(gr_section "$GPKG" 1 | grep -cxF "**Lenses:** $PR/criteria/lenses/lang-bash.md")" "1"
check "review --group: a task with no lens has no lens line" "$(gr_section "$GPKG" 2 | grep -c '^\*\*Lenses:\*\*')" "0"
check "review --group: the prompt has no unexpanded placeholder" "$(placeholders "$GPR")" "0"
check "review --group: the prompt names the package" "$([ "$(grep -cF "$GPKG" "$GPR")" -ge 1 ] && echo yes || echo no)" "yes"
check "review --group: the prompt names the report file" "$([ "$(grep -cF "$GR_WS/group-$GL-review-report.md" "$GPR")" -ge 1 ] && echo yes || echo no)" "yes"
check "review --group: the prompt names the criteria file" "$([ "$(grep -cF "$PR/criteria/task-review.md" "$GPR")" -ge 1 ] && echo yes || echo no)" "yes"
check "review --group: the prompt names the group" "$([ "$(grep -cF "$GL" "$GPR")" -ge 1 ] && echo yes || echo no)" "yes"
check "review --group: the seat is the route's Claude judge" "$(grep '^seat:' <<<"$gr_out")" "seat: dforge:judge-opus prompt: $GPR"
check "review --group: no Codex seat runs" "$(grep -cE '^(codex|timeout):' <<<"$gr_out")" "0"
check "review --group: no Codex prompt is written" "$(ls "$GR_WS" | grep -c 'codex')" "0"
check "review --group: the identity check" "$(grep '^check identity' <<<"$gr_out")" "check identity: clean"
check "review --group: the attribution check" "$(grep '^check attribution' <<<"$gr_out")" "check attribution: clean"
check "review --group: the digest is at most 15 lines" "$([ "$(count_lines "$gr_out")" -le 15 ] && echo yes || echo no)" "yes"
check "review --group: the last line is the budget line" "$(tail -n 1 <<<"$gr_out" | cut -c1-6)" "budget"
check "review --group: the group state names its tasks" "$(jq -c .tasks "$GR_WS/group-$GL-step.json" | tr -d '\r')" "[1,2,4]"
check "review --group: the group state records the group head" "$(jq -r .reviewHead "$GR_WS/group-$GL-step.json" | tr -d '\r')" "$GR_H4"
check "review --group: the group state records t0" "$(jq -r '.t0 | type' "$GR_WS/group-$GL-step.json" | tr -d '\r')" "number"
for n in 1 2 4; do
  check "review --group: Task $n records the group head" "$(gr_state "$n" .reviewHead)" "$GR_H4"
  check "review --group: Task $n records round 0" "$(gr_state "$n" .round)" "0"
  check "review --group: Task $n records t0" "$(gr_state "$n" '.t0 | type')" "number"
  check "review --group: Task $n names its group" "$(gr_state "$n" .group)" "$GL"
done
check "review --group: a member keeps its base" "$(gr_state 2 .base)" "$GR_B2"
check "review --group: a task outside the group is untouched" "$(gr_state 3 '.reviewHead // "none"')" "none"

# A member's fix round re-reviews alone. In one checkout the fixes run one at a
# time, so each member's fix diff starts where the group's last review ended.
gr_commit one.txt
GR_F1=$(gr_git rev-parse HEAD)
printf -- '- one.txt: wrong value\n\nFix it.\n' > "$GR_WS/task-1-fix-1.md"
gr_run rereview docs/plan.md 1
GRR1=$GR_WS/task-1-rereview-1-prompt.md
check "member rereview: exit 0" "$gr_rc" "0"
check "member rereview: the fix base is the group head" "$(grep -c "Fix base:\*\* $GR_H4 " "$GRR1")" "1"
check "member rereview: records the round" "$(gr_state 1 .round)" "1"
check "member rereview: records its review head" "$(gr_state 1 .reviewHead)" "$GR_F1"
check "member rereview: the group records the latest review head" "$(jq -r .reviewHead "$GR_WS/group-$GL-step.json" | tr -d '\r')" "$GR_F1"
gr_commit two.txt
printf -- '- two.txt: stale\n\nFix it.\n' > "$GR_WS/task-2-fix-1.md"
gr_run rereview docs/plan.md 2
GRR2=$GR_WS/task-2-rereview-1-prompt.md
GRD2=$(sed -n 's/^\*\*Diff file:\*\* //p' "$GRR2")
check "member rereview: the next member's fix base is the last fix head" "$(grep -c "Fix base:\*\* $GR_F1 " "$GRR2")" "1"
check "member rereview: the next member's fix diff holds its own fix" "$(grep -c '^diff --git a/two.txt b/two.txt$' "$GRD2")" "1"
check "member rereview: the next member's fix diff leaves the earlier fix out" "$(grep -c '^diff --git a/one.txt' "$GRD2")" "0"
gr_commit four.txt
printf -- '- four.txt: off by one\n\nFix it.\n' > "$GR_WS/task-4-fix-1.md"
gr_run rereview docs/plan.md 4 --base "$GR_H4"
check "member rereview: --base <group review head> works for a member" "$gr_rc $(grep -c "Fix base:\*\* $GR_H4 " "$GR_WS/task-4-rereview-1-prompt.md")" "0 1"

# A group with a review round line is in its fix rounds: reviewing it again
# would reset every member's round and lift the two-round cap.
printf '%s\n' 'Group 1,2,4: review round 1/2 (Task 1: clean; Task 2: clean; Task 4: 1 open — off by one; commits aaaaaaa..bbbbbbb (Task 1), bbbbbbb..ccccccc (Task 2), ccccccc..ddddddd (Task 4))' >> "$GR_LEDGER"
gr_run review --group docs/plan.md 1 2 4
check "review --group: a group in its fix rounds exits 4" "$gr_rc" "4"
check "review --group: names every member already in review rounds" "$(grep -c 'Task 1' <<<"$gr_err") $(grep -c 'Task 2' <<<"$gr_err") $(grep -c 'Task 4' <<<"$gr_err")" "1 1 1"
check "review --group: a refused group keeps each member's round" "$(gr_state 1 .round) $(gr_state 2 .round) $(gr_state 4 .round)" "1 1 1"

# A wave: each member is held at its task ref and re-reviewed from its own head.
GR_W=$(gr_git rev-parse HEAD)
gr_run start docs/plan.md 6
gr_run start docs/plan.md 7
gr_git branch t6 "$GR_W"
gr_git branch t7 "$GR_W"
gr_git checkout -q t6
gr_commit six.txt
GR_H6=$(gr_git rev-parse HEAD)
gr_git checkout -q t7
gr_commit seven.txt
GR_H7=$(gr_git rev-parse HEAD)
gr_git checkout -q "$GR_MAIN"
gr_git worktree add -q --detach "$GR_TMP/wt6" t6
gr_run hold docs/plan.md 6 --cwd "$GR_TMP/wt6"
check "hold --cwd: records that checkout's HEAD" "$(gr_state 6 .heldHead)" "$GR_H6"
before=$(gr_lines)
gr_run hold docs/plan.md 6 --head t6
check "hold --head: exit 0" "$gr_rc" "0"
check "hold --head: records the ref" "$(gr_state 6 .head)" "t6"
check "hold --head: the same range writes no second line" "$(gr_lines)" "$before"
gr_run hold docs/plan.md 7 --head t7
check "hold --head: records the ref's commit" "$(gr_state 7 .heldHead)" "$GR_H7"
gr_run review --group docs/plan.md 6 7 --cwd "$GR_TMP/wt6"
GPKG67=$GR_WS/group-6,7-review-package.md
check "wave group: exit 0" "$gr_rc" "0"
check "wave group: --cwd names the checkout whose HEAD is the group head" "$(jq -r .reviewHead "$GR_WS/group-6,7-step.json" | tr -d '\r')" "$GR_H6"
check "wave group: a member's review head is its own held head" "$(gr_state 6 .reviewHead) $(gr_state 7 .reviewHead)" "$GR_H6 $GR_H7"
check "wave group: each section holds its own task ref's diff" \
  "$(gr_section "$GPKG67" 6 | grep -c '^diff --git a/seven.txt') $(gr_section "$GPKG67" 7 | grep -c '^diff --git a/seven.txt b/seven.txt$')" "0 1"
gr_git checkout -q t6
gr_commit six.txt
GR_F6=$(gr_git rev-parse HEAD)
gr_git checkout -q "$GR_MAIN"
printf -- '- six.txt: wrong value\n\nFix it.\n' > "$GR_WS/task-6-fix-1.md"
gr_run rereview docs/plan.md 6
check "wave member rereview: the fix base is its own held head" "$(grep -c "Fix base:\*\* $GR_H6 " "$GR_WS/task-6-rereview-1-prompt.md")" "1"
check "wave member rereview: the head is its task ref" "$(grep -c "Head:\*\* $GR_F6\$" "$GR_WS/task-6-rereview-1-prompt.md")" "1"
printf '%s\n' 'Group 6-7: review round 1/2 (Task 6: 1 open — wrong value; Task 7: clean; commits aaaaaaa..bbbbbbb (Task 6))' >> "$GR_LEDGER"
gr_run review --group docs/plan.md 6 7
check "review --group: a range Group line also marks its members as in review rounds" "$gr_rc $(grep -c 'Task 7' <<<"$gr_err")" "4 1"
gr_git worktree remove --force "$GR_TMP/wt6"

# A group of five: every member's verdict keys reach the digest, one line per
# member, however many other Verdict lines and cannot-verify items the report holds.
GR_RH=$(gr_git rev-parse HEAD)
jq -n --arg rh "$GR_RH" --arg cwd "$GR_REPO" \
  '{tasks: [1,2,4,6,7], reviewHead: $rh, t0: 0, reviewChecks: [{cwd: $cwd, head: $rh, dirty: []}]}' > "$GR_WS/group-1,2,4,6,7-step.json"
{
  printf '## Verdict\n'
  for t in 1 2 4 6; do
    printf 'Task %s spec: pass\nTask %s quality: approved\nTask %s scores: spec 17 / scope 17 / verification 17 / quality 17\n' "$t" "$t" "$t"
  done
  printf 'Task 7 spec: fail\nTask 7 quality: changes\nTask 7 scores: spec 8 / scope 16 / verification 15 / quality 9\n'
  for i in 1 2 3 4 5 6 7 8; do printf 'note %s: an extra verdict line\n' "$i"; done
  printf '\n## Findings\n- [Important] (Task 7) seven.txt:1 — wrong value\n\n## Cannot verify\n'
  for i in 1 2 3 4 5 6 7 8 9 10 11 12; do printf -- '- (Task 6) item %s\n' "$i"; done
} > "$GR_WS/group-1,2,4,6,7-review-report.md"
gr_run verdict docs/plan.md 1 2 4 6 7 --group
check "verdict, five members: exit 0" "$gr_rc" "0"
check "verdict, five members: one verdict line per member" "$(grep -c '^Task [0-9]: spec ' <<<"$gr_out")" "5"
check "verdict, five members: the last member's failing verdict is shown" \
  "$(grep '^Task 7: ' <<<"$gr_out")" "Task 7: spec fail; quality changes; scores spec 8 / scope 16 / verification 15 / quality 9"
check "verdict, five members: the extra Verdict lines are cut" "$(grep -c '^note ' <<<"$gr_out") $(grep '^verdict: ' <<<"$gr_out")" "6 verdict: 2 more lines in the report"
check "verdict, five members: the cannot-verify list is cut" "$(grep -c '^cannot-verify: (Task 6)' <<<"$gr_out")" "0"
check "verdict, five members: and says how many it cut" "$(grep -c '^cannot-verify: 12 more in the report$' <<<"$gr_out")" "1"
check "verdict, five members: at most 20 lines besides the finding lines" "$(grep -cvE '^(Critical|Important) ' <<<"$gr_out")" "20"

# The re-review judge writes its report where the prompt says; a fresh round
# discards a stale one at that path.
rr_reset
rr_edit app.txt add4
rr_git add -A && rr_git commit -qm fix
rr_fix 1 1 "- app.txt: wrong value|- other.txt: stale"
printf 'stale\n' > "$RR_WS/task-1-rereview-1-report.md"
rr_run rereview docs/plan.md 1
RR_P=$RR_WS/task-1-rereview-1-prompt.md
check "rereview report: exit 0" "$rr_rc" "0"
check "rereview report: the prompt names the round's report file" \
  "$(grep -cF "Write your full report to $RR_WS/task-1-rereview-1-report.md and write nothing else" "$RR_P")" "1"
check "rereview report: the implementer's report is filled" "$(grep -cF "$RR_WS/task-1-report.md" "$RR_P")" "1"
check "rereview report: no implementer-report placeholder is left" "$(grep -c '\[IMPLEMENTER_REPORT_FILE\]' "$RR_P")" "0"
check "rereview report: a fresh round discards the stale report" "$([ -e "$RR_WS/task-1-rereview-1-report.md" ] && echo yes || echo no)" "no"

# A group review's judge writes one report for the group (Task 5's hold and
# review --group).
rr_reset
rr_run hold docs/plan.md 1
check "group report: hold 1" "$rr_rc" "0"
rr_run hold docs/plan.md 3
check "group report: hold 3" "$rr_rc" "0"
printf 'stale\n' > "$RR_WS/group-1,3-review-report.md"
rr_run review --group docs/plan.md 1 3
check "group report: review --group exits 0" "$rr_rc" "0"
check "group report: the prompt names the group report file" \
  "$(grep -cF "Write your full report to $RR_WS/group-1,3-review-report.md and write nothing else" "$RR_WS/group-1,3-review-prompt.md")" "1"
check "group report: a fresh group review discards the last report" "$([ -e "$RR_WS/group-1,3-review-report.md" ] && echo yes || echo no)" "no"
# --- verdict: the report digest, the fix files and the tracked-file check ---
vd_report() { sed 's/^|//' > "$1"; } # vd_report <file> — the report on stdin, its leading | stripped
first_block() { awk '{ sub(/\r$/, "") } /^$/ { exit } { print }' "$1" | tr '\n' ';'; }

# A group report: findings and fix files per member task, from the state the
# group block above left (Task 5's review --group).
vd_report "$RR_WS/group-1,3-review-report.md" <<'REPORT'
|## Verdict
|Task 1 spec: pass
|Task 1 quality: changes
|Task 1 scores: spec 16 / scope 17 / verification 15 / quality 12
|Task 3 spec: pass
|Task 3 quality: approved
|Task 3 scores: spec 18 / scope 18 / verification 17 / quality 17
|
|## Findings
|- [Important] (Task 1) app.txt:3 — off by one
|  The loop stops one line early.
|- [Minor] (Task 3) other.txt:1 — wording
|
|## Cannot verify
|- (Task 3) the caller passes the flag
REPORT
rr_run verdict docs/plan.md 1 3 --group
check "verdict --group: exit 0" "$rr_rc" "0"
check "verdict --group: the digest names the group report" "$(head -n 1 <<<"$rr_out")" "group 1,3: verdict from $RR_WS/group-1,3-review-report.md"
check "verdict --group: one verdict line per member" "$(grep '^Task [13]: spec ' <<<"$rr_out" | tr '\n' ';')" \
  "Task 1: spec pass; quality changes; scores spec 16 / scope 17 / verification 15 / quality 12;Task 3: spec pass; quality approved; scores spec 18 / scope 18 / verification 17 / quality 17;"
check "verdict --group: the finding names its task" "$(grep -E '^(Critical|Important) ' <<<"$rr_out")" "Important 1 app.txt:3 — off by one"
R1=$(( $(rr_state 1 .round) + 1 ))
check "verdict --group: a fix file for the task with findings" "$(first_block "$RR_WS/task-1-fix-$R1.md")" "- app.txt:3: off by one;"
check "verdict --group: no fix file for a task without one" "$(ls "$RR_WS"/task-3-fix-*.md 2>/dev/null | wc -l | tr -d ' ')" "0"
check "verdict --group: the member's Minor goes to the ledger" "$(grep -c '^Task 3: minor (deferred): other.txt:1 — wording$' "$RR_WS/progress.md")" "1"
check "verdict --group: the cannot-verify item keeps its task" "$(grep '^cannot-verify: ' <<<"$rr_out")" "cannot-verify: (Task 3) the caller passes the flag"
vd_report "$RR_WS/group-1,3-review-report.md" <<'REPORT'
|## Verdict
|Task 1 spec: pass
|Task 1 quality: approved
|Task 1 scores: spec 16 / scope 17 / verification 15 / quality 16
|
|## Findings
REPORT
rr_run verdict docs/plan.md 1 3 --group
check "verdict --group: a report missing a member's verdict exits 5" "$rr_rc" "5"
check "verdict --group: the missing key is named" "$(grep -c 'Task 3 spec' <<<"$rr_err")" "1"
rr_run verdict docs/plan.md 1 3 --group --rereview 1
check "verdict --group: a group has no re-review report (members re-review alone)" "$rr_rc" "2"

# Finding attribution: a group finding names a member, a task finding names none.
vd_group() { # vd_group <findings lines...> — a clean group 1,3 report with these Findings lines
  {
    printf '## Verdict\n'
    printf 'Task %s spec: pass\nTask %s quality: approved\nTask %s scores: spec 17 / scope 17 / verification 17 / quality 17\n' 1 1 1 3 3 3
    printf '\n## Findings\n'
    printf '%s\n' "$@"
  } > "$RR_WS/group-1,3-review-report.md"
}
vd_group '- [Minor] app.txt:3 — no task named'
rr_run verdict docs/plan.md 1 3 --group
check "verdict --group: a finding without its (Task N) exits 5" "$rr_rc $(grep -c 'no task named' <<<"$rr_err")" "5 1"
vd_group '- [Minor] (Task 2) app.txt:3 — outside the group'
rr_run verdict docs/plan.md 1 3 --group
check "verdict --group: a finding naming a task outside the group exits 5" "$rr_rc $(grep -c 'outside the group' <<<"$rr_err")" "5 1"
vd_group '- [Minor] (Task 3) other.txt:1 — wording'
sed -i.bak 's/^Task 3 quality: approved$/Task 3 quality: changes/' "$RR_WS/group-1,3-review-report.md" && rm -f "$RR_WS/group-1,3-review-report.md.bak"
rr_run verdict docs/plan.md 1 3 --group
check "verdict --group: quality changes with only a Minor for that task exits 5" "$rr_rc $(grep -c 'Task 3: spec: fail or quality: changes' <<<"$rr_err")" "5 1"
vd_group '* [Important] (Task 1) app.txt:3 — a star bullet'
rr_run verdict docs/plan.md 1 3 --group
check "verdict --group: a line under Findings that is not a bullet exits 5" "$rr_rc $(grep -c 'star bullet' <<<"$rr_err")" "5 1"
vd_group '- None' '' '## Cannot verify' '- None.'
rr_run verdict docs/plan.md 1 3 --group
check "verdict --group: - None under both sections exits 0" "$rr_rc" "0"
check "verdict --group: and the digest lists nothing" "$(grep -cE '^(Critical|Important|cannot-verify): ' <<<"$rr_out") $(grep '^findings: ' <<<"$rr_out")" \
  "0 findings: 0 Critical, 0 Important, 0 Minor"

# A wave group spread over two worktrees: one tracked snapshot per member
# checkout, and verdict checks each.
rr_reset
rr_git worktree add -q --detach "$RR_TMP/wt1" HEAD
rr_git worktree add -q --detach "$RR_TMP/wt3" HEAD
rr_run hold docs/plan.md 1 --cwd "$RR_TMP/wt1"
rr_run hold docs/plan.md 3 --cwd "$RR_TMP/wt3"
check "wave group: hold records the member's checkout" "$(rr_state 3 .heldCwd)" "$RR_TMP/wt3"
rr_run review --group docs/plan.md 1 3
check "wave group: one tracked snapshot per member checkout" \
  "$(jq -r '[.reviewChecks[].cwd] | sort | join(" ")' "$RR_WS/group-1,3-step.json" | tr -d '\r')" "$RR_TMP/wt1 $RR_TMP/wt3"
vd_report "$RR_WS/group-1,3-review-report.md" <<'REPORT'
|## Verdict
|Task 1 spec: pass
|Task 1 quality: approved
|Task 1 scores: spec 17 / scope 18 / verification 16 / quality 16
|Task 3 spec: pass
|Task 3 quality: approved
|Task 3 scores: spec 17 / scope 18 / verification 16 / quality 16
REPORT
rr_run verdict docs/plan.md 1 3 --group
check "wave group: clean member checkouts pass" "$rr_rc" "0"
cp "$RR_WS/group-1,3-step.json" "$RR_TMP/group-1,3.keep"
jq 'del(.reviewChecks)' "$RR_TMP/group-1,3.keep" > "$RR_WS/group-1,3-step.json"
rr_run verdict docs/plan.md 1 3 --group
check "wave group: a group state without its tracked check exits 6" "$rr_rc $(grep -c 'recorded no tracked-file check' <<<"$rr_err")" "6 1"
cp "$RR_TMP/group-1,3.keep" "$RR_WS/group-1,3-step.json"
printf 'judge edit\n' >> "$RR_TMP/wt3/app.txt"
rr_run verdict docs/plan.md 1 3 --group
check "wave group: a change in one member's checkout exits 6" "$rr_rc" "6"
check "wave group: the stderr names that checkout" "$(grep -cF "in $RR_TMP/wt3;" <<<"$rr_err")" "1"
check "wave group: and the file" "$(grep -cx 'app.txt' <<<"$rr_err")" "1"
rr_run verdict docs/plan.md 1 3 --group --cwd "$RR_TMP/wt1"
check "wave group: --cwd cannot stand for two checkouts" "$rr_rc" "2"
printf -- '- app.txt: judge edit\n' > "$RR_WS/task-3-fix-1.md"
rr_run rereview docs/plan.md 3
check "wave group: a member's re-review snapshots its own checkout" "$rr_rc $(rr_state 3 .reviewCheck.cwd)" "0 $RR_TMP/wt3"
printf 'member edit\n' >> "$RR_TMP/wt3/app.txt"
rr_run verdict docs/plan.md 3 --rereview 1
check "wave group: a member's re-review verdict checks its own checkout" "$rr_rc $(grep -cF "in $RR_TMP/wt3;" <<<"$rr_err")" "6 1"
rr_git worktree remove --force "$RR_TMP/wt1"
rr_git worktree remove --force "$RR_TMP/wt3"

# A task review: the digest, the fix file, the deferred Minor lines.
rr_reset
vd_report "$RR_WS/task-1-review-report.md" <<'REPORT'
|## Verdict
|spec: fail
|quality: changes
|scores: spec 7 / scope 15 / verification 12 / quality 9
|
|## Strengths
|Small and focused.
|
|## Findings
|- [Critical] app.txt:2 — wrong value
|  The second line must read "line 2".
|- [Important] other.txt:4 — stale copy
|- [Minor] app.txt:5 — naming
|- [Minor] test.txt:0 — no edge case
|
|## Cannot verify
|- the caller passes the flag
|
|## Assessment
|Needs fixes.
REPORT
rr_run verdict docs/plan.md 1
VD=$rr_out
check "verdict: exit 0" "$rr_rc" "0"
check "verdict: the digest names the report" "$(head -n 1 <<<"$VD")" "task 1: verdict from $RR_WS/task-1-review-report.md"
check "verdict: the verdict lines" "$(grep -E '^(spec|quality|scores): ' <<<"$VD" | tr '\n' ';')" \
  "spec: fail;quality: changes;scores: spec 7 / scope 15 / verification 12 / quality 9;"
check "verdict: the counts by severity" "$(grep '^findings: ' <<<"$VD")" "findings: 1 Critical, 1 Important, 2 Minor"
check "verdict: one line per Critical or Important finding" "$(grep -E '^(Critical|Important) ' <<<"$VD" | tr '\n' ';')" \
  "Critical 1 app.txt:2 — wrong value;Important 1 other.txt:4 — stale copy;"
check "verdict: Minor findings are not listed" "$(grep -c '^Minor ' <<<"$VD")" "0"
check "verdict: the cannot-verify item" "$(grep '^cannot-verify: ' <<<"$VD")" "cannot-verify: the caller passes the flag"
check "verdict: the fix line" "$(grep '^fix: ' <<<"$VD")" "fix: $RR_WS/task-1-fix-1.md (2 findings)"
check "verdict: the minor line" "$(grep '^minor: ' <<<"$VD")" "minor: 2 logged as deferred"
check "verdict: the tracked check" "$(grep '^check tracked: ' <<<"$VD")" "check tracked: clean"
check "verdict: the last line is the budget line" "$(tail -n 1 <<<"$VD" | cut -c1-6)" "budget"
check "verdict: at most 20 lines besides the finding lines" "$([ "$(grep -cvE '^(Critical|Important) ' <<<"$VD")" -le 20 ] && echo yes || echo no)" "yes"
check "verdict: the fix file's bullets" "$(first_block "$RR_WS/task-1-fix-1.md")" "- app.txt:2: wrong value;- other.txt:4: stale copy;"
check "verdict: the fix file names the report" "$(grep -cF "$RR_WS/task-1-review-report.md" "$RR_WS/task-1-fix-1.md")" "1"
check "verdict: Minor findings go to the ledger as deferred" \
  "$(grep -cE '^Task 1: minor \(deferred\): (app\.txt:5 — naming|test\.txt:0 — no edge case)$' "$RR_WS/progress.md")" "2"
rr_run verdict docs/plan.md 1
check "verdict: a second run adds no ledger line" "$(grep -c '^Task 1: minor (deferred): app.txt:5 — naming$' "$RR_WS/progress.md")" "1"
# A ledger past the pipe buffer: the Minor line near its top is still found.
cp "$RR_WS/progress.md" "$RR_TMP/progress.keep"
awk 'BEGIN { for (i = 0; i < 4000; i++) printf "# filler line %04d of a long ledger, padded to sixty characters\n", i }' >> "$RR_WS/progress.md"
rr_run verdict docs/plan.md 1
check "verdict: a long ledger adds no second Minor line" "$(grep -c '^Task 1: minor (deferred): app.txt:5 — naming$' "$RR_WS/progress.md")" "1"
cp "$RR_TMP/progress.keep" "$RR_WS/progress.md"

# The fix file feeds the re-review, and the re-review's verdict writes the next round's.
rr_edit app.txt add4
rr_git add -A && rr_git commit -qm fix
rr_run rereview docs/plan.md 1
check "verdict then rereview: the fix file's findings reach the prompt" \
  "$(grep -cE '^- (app\.txt:2: wrong value|other\.txt:4: stale copy)$' "$RR_WS/task-1-rereview-1-prompt.md")" "2"
vd_report "$RR_WS/task-1-rereview-1-report.md" <<'REPORT'
|## Verdict
|fix round: open
|open: 1
|
|## Finding verdicts
|- app.txt:2: wrong value — ADDRESSED — app.txt:2 reads "line 2"
|- other.txt:4: stale copy — NOT ADDRESSED — other.txt:4 is unchanged
|
|## Findings
|- [Important] other.txt:4 — stale copy
|- [Minor] app.txt:9 — out of scope: trailing space
REPORT
rr_run verdict docs/plan.md 1 --rereview 1
check "verdict --rereview: passes against the state rereview recorded" "$rr_rc" "0"
check "verdict --rereview: reads the round's report" "$(head -n 1 <<<"$rr_out")" "task 1: verdict from $RR_WS/task-1-rereview-1-report.md"
check "verdict --rereview: the round lines" "$(grep -E '^(fix round|open): ' <<<"$rr_out" | tr '\n' ';')" "fix round: open;open: 1;"
check "verdict --rereview: writes the next round's fix file" "$(first_block "$RR_WS/task-1-fix-2.md")" "- other.txt:4: stale copy;"
# Round 2 is the cap: what is still open goes to the breaker, not a third fix file.
jq '.round = 2' "$RR_WS/task-1-step.json" > "$RR_WS/task-1-step.json.tmp" && mv "$RR_WS/task-1-step.json.tmp" "$RR_WS/task-1-step.json"
cp "$RR_WS/task-1-rereview-1-report.md" "$RR_WS/task-1-rereview-2-report.md"
rr_run verdict docs/plan.md 1 --rereview 2
check "verdict --rereview 2: exit 0" "$rr_rc" "0"
check "verdict --rereview 2: the fix line names the breaker" "$(grep '^fix: ' <<<"$rr_out")" "fix: breaker (round 2 of 2; 1 finding)"
check "verdict --rereview 2: no third fix file" "$([ -e "$RR_WS/task-1-fix-3.md" ] && echo yes || echo no)" "no"
rm -f "$RR_WS/task-1-rereview-2-report.md"
jq '.round = 1' "$RR_WS/task-1-step.json" > "$RR_WS/task-1-step.json.tmp" && mv "$RR_WS/task-1-step.json.tmp" "$RR_WS/task-1-step.json"

# Failures: a missing or malformed report exits 5 and writes no fix file.
rr_run verdict docs/plan.md 1 --rereview 2
check "verdict: a missing report exits 5" "$rr_rc" "5"
check "verdict: a missing report is named" "$(grep -cF "$RR_WS/task-1-rereview-2-report.md" <<<"$rr_err")" "1"
check "verdict: a missing report writes no fix file" "$([ -e "$RR_WS/task-1-fix-3.md" ] && echo yes || echo no)" "no"
printf 'spec: pass\n' > "$RR_WS/task-1-review-report.md"
rr_run verdict docs/plan.md 1
check "verdict: a report that does not open with ## Verdict exits 5" "$rr_rc" "5"
vd_report "$RR_WS/task-1-review-report.md" <<'REPORT'
|## Verdict
|spec: pass
|scores: spec 17 / scope 18 / verification 16 / quality 16
REPORT
rr_run verdict docs/plan.md 1
check "verdict: a report missing a verdict key exits 5" "$rr_rc" "5"
check "verdict: the missing key is named" "$(grep -c 'quality' <<<"$rr_err")" "1"
vd_report "$RR_WS/task-1-review-report.md" <<'REPORT'
|## Verdict
|spec: ✅
|quality: approved
|scores: spec 17 / scope 18 / verification 16 / quality 16
REPORT
rr_run verdict docs/plan.md 1
check "verdict: a verdict value outside its set exits 5" "$rr_rc" "5"
vd_report "$RR_WS/task-1-review-report.md" <<'REPORT'
|## Verdict
|spec: fail
|quality: changes
|scores: spec 7 / scope 15 / verification 12 / quality 9
|
|## Findings
|- [Severe] app.txt:2 — wrong value
REPORT
rr_run verdict docs/plan.md 1
check "verdict: a finding line outside the grammar exits 5" "$rr_rc" "5"
check "verdict: the bad line is quoted" "$(grep -c 'Severe' <<<"$rr_err")" "1"
vd_report "$RR_WS/task-1-review-report.md" <<'REPORT'
|## Verdict
|spec: fail
|quality: changes
|scores: spec 7 / scope 15 / verification 12 / quality 9
|
|## Findings
|- [Important] (Task 1) app.txt:2 — a task prefix outside a group
REPORT
rr_run verdict docs/plan.md 1
check "verdict: a task finding with a (Task N) prefix exits 5" "$rr_rc $(grep -c 'prefix outside a group' <<<"$rr_err")" "5 1"
vd_report "$RR_WS/task-1-review-report.md" <<'REPORT'
|## Verdict
|spec: fail
|quality: changes
|scores: spec 7 / scope 15 / verification 12 / quality 9
|
|## Issues
|- [Important] app.txt:2 — filed under the wrong heading
|
|## Findings
|- [Minor] app.txt:5 — naming
REPORT
rr_run verdict docs/plan.md 1
check "verdict: spec fail with no Critical or Important finding exits 5" "$rr_rc $(grep -c 'no Critical or Important finding' <<<"$rr_err")" "5 1"
vd_report "$RR_WS/task-1-review-report.md" <<'REPORT'
|## Verdict
|spec: fail
|quality: changes
|scores: spec 7 / scope 15 / verification 12 / quality 9
|
|## Findings
|### Critical
|- [Critical] app.txt:2 — wrong value
REPORT
rr_run verdict docs/plan.md 1
check "verdict: a sub-heading under Findings exits 5" "$rr_rc $(grep -c '### Critical' <<<"$rr_err")" "5 1"
vd_report "$RR_WS/task-1-rereview-1-report.md" <<'REPORT'
|## Verdict
|fix round: maybe
|open: 1
|
|## Findings
|- [Important] other.txt:4 — stale copy
REPORT
rr_run verdict docs/plan.md 1 --rereview 1
check "verdict --rereview: a fix round value outside its set exits 5" "$rr_rc $(grep -c 'fix round: maybe' <<<"$rr_err")" "5 1"
vd_report "$RR_WS/task-1-rereview-1-report.md" <<'REPORT'
|## Verdict
|fix round: open
|open: 1
|
|## Findings
REPORT
rr_run verdict docs/plan.md 1 --rereview 1
check "verdict --rereview: an open round with no open finding exits 5" "$rr_rc $(grep -c 'fix round: open with no Critical or Important finding' <<<"$rr_err")" "5 1"
vd_report "$RR_WS/task-1-review-report.md" <<'REPORT'
|## Verdict
|spec: pass
|quality: approved
|scores: spec 17 / scope 18 / verification 16 / quality 16
|
|## Codex findings
|- [CONFIRMED] app.txt:2 wrong value - the diff shows it
|
|## Findings
REPORT
rr_run verdict docs/plan.md 1
check "verdict: Codex findings that are not the last section exit 5" "$rr_rc" "5"
vd_report "$RR_WS/task-1-review-report.md" <<'REPORT'
|## Verdict
|spec: pass
|quality: approved
|scores: spec 17 / scope 18 / verification 16 / quality 16
|
|## Findings
REPORT
rm -f "$RR_WS"/task-1-fix-*.md
rr_run verdict docs/plan.md 1
check "verdict: a clean report exits 0" "$rr_rc" "0"
check "verdict: a clean report writes no fix file" "$(grep '^fix: ' <<<"$rr_out")" "fix: none"
check "verdict: and leaves no fix file behind" "$(ls "$RR_WS"/task-1-fix-*.md 2>/dev/null | wc -l | tr -d ' ')" "0"

# Failures: a tracked file changed during the review exits 6 and names it.
printf 'judge edit\n' >> "$RR_REPO/app.txt"
rr_run verdict docs/plan.md 1
check "verdict: a tracked file changed during the review exits 6" "$rr_rc" "6"
check "verdict: the changed file is named on its own line" "$(grep -cx 'app.txt' <<<"$rr_err")" "1"
rr_git checkout -- app.txt
rr_run verdict docs/plan.md 1
check "verdict: restored files pass the check" "$rr_rc" "0"
printf 'new\n' > "$RR_REPO/untracked.txt"
rr_run verdict docs/plan.md 1
check "verdict: an untracked file is not a tracked change" "$rr_rc" "0"
rm -f "$RR_REPO/untracked.txt"
rr_git commit -q --allow-empty -m "moved"
rr_run verdict docs/plan.md 1
check "verdict: a HEAD that moved exits 6" "$rr_rc" "6"
check "verdict: a HEAD that moved is named" "$(grep -c 'HEAD moved' <<<"$rr_err")" "1"
rr_git reset -q --hard HEAD~1

# A file already changed when the review ran is compared by content.
rr_reset
printf 'dirty\n' >> "$RR_REPO/other.txt"
rr_run review docs/plan.md 1
vd_report "$RR_WS/task-1-review-report.md" <<'REPORT'
|## Verdict
|spec: pass
|quality: approved
|scores: spec 17 / scope 18 / verification 16 / quality 16
REPORT
rr_run verdict docs/plan.md 1
check "verdict: a file already changed at review time passes" "$rr_rc" "0"
printf 'more\n' >> "$RR_REPO/other.txt"
rr_run verdict docs/plan.md 1
check "verdict: a further change to it exits 6" "$rr_rc" "6"
check "verdict: and names it" "$(grep -cx 'other.txt' <<<"$rr_err")" "1"
rr_git checkout -- other.txt

# A state recorded before the check existed still reads its report; usage.
rr_reset
vd_report "$RR_WS/task-1-review-report.md" <<'REPORT'
|## Verdict
|spec: pass
|quality: approved
|scores: spec 17 / scope 18 / verification 16 / quality 16
REPORT
jq 'del(.reviewCheck)' "$RR_TMP/state1.0" > "$RR_WS/task-1-step.json"
rr_run verdict docs/plan.md 1
check "verdict: a state without a recorded check exits 0" "$rr_rc" "0"
check "verdict: and says the check was not recorded" "$(grep -c '^check tracked: not recorded' <<<"$rr_out")" "1"
rr_reset
rr_run verdict docs/plan.md 1 --cwd "$RR_TMP/no-such-dir"
check "verdict: a missing --cwd directory exits 2" "$rr_rc" "2"
jq '.reviewHead = null' "$RR_TMP/state2.0" > "$RR_WS/task-2-step.json"
rr_run verdict docs/plan.md 2
check "verdict: before review exits 6" "$rr_rc" "6"
cp "$RR_TMP/state2.0" "$RR_WS/task-2-step.json"
rr_run verdict docs/plan.md
check "verdict: no task number exits 2" "$rr_rc" "2"
rr_run verdict docs/plan.md 1 --rereview x
check "verdict: a non-numeric --rereview exits 2" "$rr_rc" "2"
rr_run verdict docs/plan.md 99
check "verdict: no such task exits 3" "$rr_rc" "3"
rr_run verdict docs/codex-plan.md 1
check "verdict: a Host: codex plan exits 2" "$rr_rc" "2"
printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
