#!/usr/bin/env bash
# task-step records a task's suite command at start and reads the suite-run
# record at the review head in verdict. Each case runs against a throwaway
# repository; suite-run writes the records the verdict reads.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
P="$HERE/.."
STEP="$P/scripts/task-step"
SUITE="$P/scripts/suite-run"
DT="$P/reference/delegated-task.md"

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
mkdir docs sub

sed 's/^|//' > docs/plan.md <<'PLAN'
|# Suite Fixture Plan
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
|1. first
|2. second
|3. third
|
|### Task 1: first
|
|**Implementer:** dforge:impl-sonnet-low
|**Evaluation:** files 0 - spec 0 - coupling 0 - risk 0 = 0
|
|Body one.
|
|### Task 2: second
|
|**Implementer:** dforge:impl-sonnet-low
|**Evaluation:** files 0 - spec 0 - coupling 0 - risk 0 = 0
|
|Body two.
|
|### Task 3: third
|
|**Implementer:** dforge:impl-sonnet-low
|**Evaluation:** files 0 - spec 0 - coupling 0 - risk 0 = 0
|
|Body three.
PLAN
printf '%s\n' 'cat result.txt' "grep -qx green result.txt" > suite.sh
printf 'green\n' > result.txt
git add -A && git commit -qm "docs: add fixture"

CMD='bash suite.sh'
KEY='bash -c bash\ suite.sh'
winpath() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s\n' "$1"; fi; }
WS=$(winpath "$(bash "$P/scripts/sdd-workspace" docs/plan.md)")
LEDGER="$WS/progress.md"
rm -f "$WS"/*
n=0
step() { out=$(bash "$STEP" "$@" 2>"$TMP/err"); rc=$?; err=$(cat "$TMP/err"); }
commit_result() { # commit_result <result.txt lines...> — a new commit; sets HEAD_SHA
  n=$((n + 1))
  printf '%s\n' "$@" > result.txt
  git add result.txt && git commit -qm "result $n"
  HEAD_SHA=$(git rev-parse HEAD | tr -d '\r')
}
set_review() { # set_review <task> <head> <checkout> — the state the review step leaves
  jq --arg h "$2" --arg c "$3" '.reviewHead = $h | .reviewCheck = {cwd: $c, head: $h, dirty: []}' "$WS/task-$1-step.json" > "$TMP/s.json" \
    && mv "$TMP/s.json" "$WS/task-$1-step.json"
}
report() { # report <file> — a passing task report
  printf '%s\n' '## Verdict' 'spec: pass' 'quality: approved' 'scores: spec 17 / scope 18 / verification 16 / quality 16' > "$1"
}
run_suite() { bash "$SUITE" -- bash -c "$CMD" >/dev/null 2>&1; true; }
first_block() { awk '{ sub(/\r$/, "") } /^$/ { exit } { print }' "$1" | tr '\n' ';'; }

# --- start --suite ---
step start docs/plan.md 1 --suite "$CMD"
check "start --suite: exit 0" "$rc" "0"
check "start --suite: the command is the step file's suite field" "$(jq -r '.suite' "$WS/task-1-step.json" | tr -d '\r')" "$CMD"
check "start --suite: the first start logs the ruling" "$(grep -cxF "Task 1: Ruling: suite command — $CMD — none" "$LEDGER")" "1"
step start docs/plan.md 2 --suite "$CMD"
check "start --suite: a second start adds no ruling" "$(grep -c 'Ruling: suite command' "$LEDGER")" "1"
step start docs/plan.md 3
check "start without --suite: no suite field" "$(jq -r '.suite // "absent"' "$WS/task-3-step.json" | tr -d '\r')" "absent"
step start docs/plan.md 3 --suite
check "start --suite without a command exits 2" "$rc" "2"
step review docs/plan.md 1 --suite x
check "review does not take --suite" "$rc" "2"

# --- verdict: no suite recorded ---
HEAD_SHA=$(git rev-parse HEAD | tr -d '\r')
set_review 3 "$HEAD_SHA" "$REPO"
report "$WS/task-3-review-report.md"
step verdict docs/plan.md 3
check "verdict, no suite field: exit 0" "$rc" "0"
check "verdict, no suite field: says none recorded" "$(grep '^suite: ' <<<"$out")" "suite: none recorded"

# --- verdict: no row at the review head ---
set_review 1 "$HEAD_SHA" "$REPO"
report "$WS/task-1-review-report.md"
step verdict docs/plan.md 1
check "verdict, no row: exit 7" "$rc" "7"
check "verdict, no row: names the command" "$(grep '^suite: ' <<<"$out")" "suite: not run ($CMD)"
check "verdict, no row: writes no fix file" "$(ls "$WS"/task-1-fix-*.md 2>/dev/null | wc -l | tr -d ' ')" "0"

# --- verdict: a passing row ---
run_suite
check "suite-run records the key verdict matches" "$(awk -F'\t' -v h="$HEAD_SHA" '$1 == h { print $3 }' .dforge/suites.tsv | tail -n 1)" "$KEY"
step verdict docs/plan.md 1
check "verdict, passing row: exit 0" "$rc" "0"
check "verdict, passing row: the suite line" "$(grep '^suite: ' <<<"$out")" "suite: pass (clean)"
check "verdict, passing row: no fix file" "$(grep '^fix: ' <<<"$out")" "fix: none"

# --- verdict: a dirty passing row counts ---
commit_result green green
set_review 1 "$HEAD_SHA" "$REPO"
printf 'x\n' > untracked.txt
run_suite
rm -f untracked.txt
step verdict docs/plan.md 1
check "verdict, dirty passing row: counts as a pass" "$rc $(grep '^suite: ' <<<"$out")" "0 suite: pass (dirty)"

# --- verdict: a failing row becomes findings ---
commit_result 'not ok 1 - alpha' 'not ok 2 - beta'
H7=${HEAD_SHA:0:7}
set_review 1 "$HEAD_SHA" "$REPO"
run_suite
step verdict docs/plan.md 1
check "verdict, failing row: exit 0" "$rc" "0"
check "verdict, failing row: the suite line" "$(grep '^suite: red' <<<"$out")" "suite: red (2 failing, 0 baseline)"
check "verdict, failing row: the findings line counts them" "$(grep '^findings: ' <<<"$out")" "findings: 0 Critical, 2 Important, 0 Minor"
check "verdict, failing row: one finding line per failing test" "$(grep '^Important ' <<<"$out" | tr '\n' ';')" \
  "Important 1 suite:0 — suite: not ok - alpha fails at $H7;Important 1 suite:0 — suite: not ok - beta fails at $H7;"
check "verdict, failing row: the fix line names the file" "$(grep '^fix: ' <<<"$out")" "fix: $WS/task-1-fix-1.md (2 findings)"
check "verdict, failing row: the fix file's bullets" "$(first_block "$WS/task-1-fix-1.md")" \
  "- suite: suite: not ok - alpha fails at $H7;- suite: suite: not ok - beta fails at $H7;"
check "verdict, failing row: exactly one suite line" "$(grep -c '^suite: ' <<<"$out")" "1"

# --- verdict: a failing run with no failing test line still fails the task ---
commit_result broken
H7=${HEAD_SHA:0:7}
set_review 1 "$HEAD_SHA" "$REPO"
rm -f "$WS"/task-1-fix-*.md
run_suite
step verdict docs/plan.md 1
check "verdict, failing run without test lines: one failing line" "$(grep '^suite: red' <<<"$out")" "suite: red (1 failing, 0 baseline)"
check "verdict, failing run without test lines: the finding names the exit code" "$(grep '^Important ' <<<"$out")" "Important 1 suite:0 — suite: command exit 1 fails at $H7"

# --- verdict: every new failing line reaches the fix file, the digest shows the first 20 ---
failing=()
for i in $(seq 1 25); do failing+=("$(printf 'not ok %d - case-%02d' "$i" "$i")"); done
commit_result "${failing[@]}"
H7=${HEAD_SHA:0:7}
set_review 1 "$HEAD_SHA" "$REPO"
rm -f "$WS"/task-1-fix-*.md
run_suite
step verdict docs/plan.md 1
check "verdict, 25 failing lines: the suite line counts them all" "$rc $(grep '^suite: red' <<<"$out")" "0 suite: red (25 failing, 0 baseline)"
check "verdict, 25 failing lines: the findings line counts 25 Important" "$(grep '^findings: ' <<<"$out")" "findings: 0 Critical, 25 Important, 0 Minor"
check "verdict, 25 failing lines: the fix file holds all 25" "$(grep -c '^- suite: suite: not ok - case-' "$WS/task-1-fix-1.md")" "25"
check "verdict, 25 failing lines: the digest prints 20 finding lines" "$(grep -c '^Important ' <<<"$out")" "20"
check "verdict, 25 failing lines: the digest counts the rest and names the fix file" "$(grep '^suite: ' <<<"$out" | tr '\n' ';')" \
  "suite: 5 more failing lines in $WS/task-1-fix-1.md;suite: red (25 failing, 0 baseline);"
check "verdict, 25 failing lines: the fix line counts 25" "$(grep '^fix: ' <<<"$out")" "fix: $WS/task-1-fix-1.md (25 findings)"

# --- verdict: a run cut short is red even when its partial log shows only baseline lines ---
printf '%s\n' 'echo "not ok 1 - alpha"' 'sleep 20' > slow.sh
git add slow.sh && git commit -qm "slow suite"
HEAD_SHA=$(git rev-parse HEAD | tr -d '\r')
H7=${HEAD_SHA:0:7}
step start docs/plan.md 3 --suite 'bash slow.sh'
set_review 3 "$HEAD_SHA" "$REPO"
(SUITE_RUN_KILL_AFTER=1 bash "$SUITE" --timeout 1 -- bash -c 'bash slow.sh' >/dev/null 2>&1; true)
check "suite-run records exit 124 for the slow suite" "$(awk -F'\t' -v h="$HEAD_SHA" '$1 == h { print $4 }' .dforge/suites.tsv | tail -n 1)" "124"
printf 'not ok - alpha\n' > "$WS/task-3-base-failures.txt"
report "$WS/task-3-review-report.md"
step verdict docs/plan.md 3
check "verdict, timed-out run: the baseline line is excused, the cut-short run is not" "$rc $(grep '^suite: ' <<<"$out")" "0 suite: red (1 failing, 1 baseline)"
check "verdict, timed-out run: the finding says the suite did not finish" "$(grep '^Important ' <<<"$out")" "Important 3 suite:0 — suite: suite did not finish (exit 124) at $H7"

# --- verdict: a row at another head or from a subdirectory does not match ---
commit_result green green green
set_review 1 "$HEAD_SHA" "$REPO"
(cd sub && bash "$SUITE" -- bash -c "$CMD" >/dev/null 2>&1; true)
step verdict docs/plan.md 1
check "verdict, row run from a subdirectory: not run, exit 7" "$rc $(grep '^suite: ' <<<"$out")" "7 suite: not run ($CMD)"
run_suite
commit_result green green green green
set_review 1 "$HEAD_SHA" "$REPO"
step verdict docs/plan.md 1
check "verdict, row at an earlier head: not run, exit 7" "$rc" "7"

# --- verdict: exits 5 and 6 come before 7 ---
set_review 1 "$HEAD_SHA" "$REPO"
rm -f "$WS/task-1-review-report.md"
step verdict docs/plan.md 1
check "verdict, no report and no row: exit 5" "$rc" "5"
report "$WS/task-1-review-report.md"
printf 'dirty\n' >> docs/plan.md
step verdict docs/plan.md 1
git checkout -q -- docs/plan.md
check "verdict, tracked file changed and no row: exit 6" "$rc" "6"

# --- verdict --cwd reads the state of that checkout ---
git worktree add -q --detach "$TMP/wt" HEAD
WT=$TMP/wt
git -C "$WT" -c user.name=Darkraise -c user.email=dark@example.invalid commit -q --allow-empty -m "wave work"
WT_SHA=$(git -C "$WT" rev-parse HEAD | tr -d '\r')
set_review 2 "$WT_SHA" "$WT"
report "$WS/task-2-review-report.md"
(cd "$WT" && bash "$SUITE" -- bash -c "$CMD" >/dev/null 2>&1; true)
step verdict docs/plan.md 2 --cwd "$WT"
check "verdict --cwd: the row in that checkout's state counts" "$rc $(grep '^suite: ' <<<"$out")" "0 suite: pass (clean)"
step verdict docs/plan.md 2
check "verdict without --cwd: the checkout's own state has no such row" "$rc" "7"

# --- verdict --group takes the suite of the last member ---
run_suite
G_HEAD=$HEAD_SHA
jq -n --arg h "$G_HEAD" --arg c "$REPO" '{tasks: [1, 2], reviewHead: $h, t0: 0, reviewChecks: [{cwd: $c, head: $h, dirty: []}]}' > "$WS/group-1,2-step.json"
{
  printf '## Verdict\n'
  for t in 1 2; do
    printf 'Task %s spec: pass\nTask %s quality: approved\nTask %s scores: spec 17 / scope 17 / verification 17 / quality 17\n' "$t" "$t" "$t"
  done
} > "$WS/group-1,2-review-report.md"
step verdict docs/plan.md 1 2 --group
check "verdict --group: the last member's suite is checked" "$rc $(grep '^suite: ' <<<"$out")" "0 suite: pass (clean)"
jq '.wave = 1' "$WS/task-2-step.json" > "$TMP/w.json" && mv "$TMP/w.json" "$WS/task-2-step.json"
rm -f .dforge/suites.tsv
step verdict docs/plan.md 1 2 --group
check "verdict --group: a wave group has no per-group suite" "$rc $(grep '^suite: ' <<<"$out")" "0 suite: none recorded"

git worktree remove --force "$WT"

# --- the doc says so ---
dt=$(tr -d '\r' < "$DT" | tr '\n' ' ' | tr -s ' ')
check "the doc: every failing line is in the fix file and the digest shows 20" \
  "$(grep -cF 'is in the fix file, however many; the digest shows the first 20 and then `suite: <k> more failing lines in <fix file>`.' <<<"$dt")" "1"
check "the doc: the last Verified section is the current evidence" \
  "$(grep -cF 'The last `## Verified` section of the report is the current evidence' <<<"$dt")" "1"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
