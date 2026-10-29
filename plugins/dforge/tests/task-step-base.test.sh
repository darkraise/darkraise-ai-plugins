#!/usr/bin/env bash
# task-step compares a red suite with the base commit's failures: verdict reuses
# a base row, then task-<N>-base-failures.txt, then runs the suite once at the
# base in a temporary worktree; rereview --covered skips only on a covered suite.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
P="$HERE/.."
S="$P/scripts"
DT="$P/reference/delegated-task.md"

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}

TMP=$(mktemp -d)
if command -v cygpath >/dev/null 2>&1; then TMP=$(cygpath -m "$TMP"); fi
winpath() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s\n' "$1"; fi; }
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" MSYS_NO_PATHCONV=1 GIT_CONFIG_NOSYSTEM=1 DFORGE_NO_SETTINGS=1
mkdir -p "$HOME/.claude"
unset DFORGE_BUDGET DR_SUPERPOWERS_BUDGET CLAUDE_CONFIG_DIR CODEX_HOME CLAUDE_CODE_SESSION_ID AR_SESSION CLAUDE_PROJECT_DIR
export DR_CODEX_SESSION_DIR="$TMP/sessions" CLAUDE_CODE_SESSION_ID=task-step-base-test
printf '%s\n' '#!/usr/bin/env bash' 'echo "codex-gate usable=true reason= review=true lane=false resets_at=- source=cache"' > "$TMP/gate-stub"
export TASK_STEP_CODEX_GATE="$TMP/gate-stub"
export SUITE_MARK="$TMP/marks"

# The helpers run before task-step's rereview dispatch, which exits before any
# later definition exists.
dispatch=$(grep -n '^if \[ "\${1:-}" = rereview \]; then$' "$S/task-step" | head -n 1 | cut -d: -f1)
for fn in suite_key suite_row suite_failing_lines suite_fail_set suite_unfinished suite_base_sha require_step_file suite_base_lines run_at_base suite_gap; do
  at=$(grep -n "^$fn() {" "$S/task-step" | head -n 1 | cut -d: -f1)
  check "$fn is defined before the rereview dispatch" "$([ -n "$at" ] && [ -n "$dispatch" ] && [ "$at" -lt "$dispatch" ] && echo yes || echo no)" "yes"
done

REPO="$TMP/repo"
git init -q "$REPO"
g() { git -C "$REPO" "$@"; }
g config user.name t
g config user.email t@example.invalid
mkdir -p "$REPO/docs"
sed 's/^|//' > "$REPO/docs/plan.md" <<'PLAN'
|# Base Run Fixture Plan
|
|**Goal:** Fixture.
|
|**Execution:** subagent — `claude --model sonnet --effort high` — fixture
|
|**Worktree setup:** `touch setup.done`
|
|## Task index
|
|1. One
|2. Two
|3. Three
|4. Four
|5. Five
|6. Six
|7. Seven
|8. Eight
|9. Nine
|10. Ten
|11. Eleven
|12. Twelve
|
|### Task 1: One
|
|**Files:**
|- Modify: `app.txt`
|
|**Implementer:** dforge:impl-sonnet-low
|**Evaluation:** files 0 - spec 0 - coupling 1 - risk 0 = 1
|
|### Task 2: Two
|
|**Files:**
|- Modify: `app.txt`
|
|**Implementer:** dforge:impl-sonnet-low
|**Evaluation:** files 0 - spec 0 - coupling 1 - risk 0 = 1
|
|### Task 3: Three
|
|**Files:**
|- Modify: `app.txt`
|
|**Implementer:** dforge:impl-sonnet-low
|**Evaluation:** files 0 - spec 0 - coupling 1 - risk 0 = 1
|
|### Task 4: Four
|
|**Files:**
|- Modify: `app.txt`
|
|**Implementer:** dforge:impl-sonnet-low
|**Evaluation:** files 0 - spec 0 - coupling 1 - risk 0 = 1
|
|### Task 5: Five
|
|**Files:**
|- Modify: `app.txt`
|
|**Implementer:** dforge:impl-sonnet-low
|**Evaluation:** files 0 - spec 0 - coupling 1 - risk 0 = 1
|
|### Task 6: Six
|
|**Files:**
|- Modify: `app.txt`
|
|**Implementer:** dforge:impl-sonnet-low
|**Evaluation:** files 0 - spec 0 - coupling 1 - risk 0 = 1
|
|### Task 7: Seven
|
|**Files:**
|- Modify: `app.txt`
|
|**Implementer:** dforge:impl-sonnet-low
|**Evaluation:** files 0 - spec 0 - coupling 1 - risk 0 = 1
|
|### Task 8: Eight
|
|**Files:**
|- Modify: `app.txt`
|
|**Implementer:** dforge:impl-sonnet-low
|**Evaluation:** files 0 - spec 0 - coupling 1 - risk 0 = 1
|
|### Task 9: Nine
|
|**Files:**
|- Modify: `app.txt`
|
|**Implementer:** dforge:impl-sonnet-low
|**Evaluation:** files 0 - spec 0 - coupling 1 - risk 0 = 1
|
|### Task 10: Ten
|
|**Files:**
|- Modify: `app.txt`
|
|**Implementer:** dforge:impl-sonnet-low
|**Evaluation:** files 0 - spec 0 - coupling 1 - risk 0 = 1
|
|### Task 11: Eleven
|
|**Files:**
|- Modify: `app.txt`
|
|**Implementer:** dforge:impl-sonnet-low
|**Evaluation:** files 0 - spec 0 - coupling 1 - risk 0 = 1
|
|### Task 12: Twelve
|
|**Files:**
|- Modify: `app.txt`
|
|**Implementer:** dforge:impl-sonnet-low
|**Evaluation:** files 0 - spec 0 - coupling 1 - risk 0 = 1
PLAN
cat > "$REPO/suite.sh" <<'SUITE'
#!/usr/bin/env bash
if [ -f setup.done ]; then echo setup >> "$SUITE_MARK"; else echo plain >> "$SUITE_MARK"; fi
if grep -q broken app.txt; then echo 'not ok 7 - app-broken'; fi
if [ -s failing.txt ]; then cat failing.txt; fi
if [ -f slow.txt ]; then sleep 20; fi
! { [ -s failing.txt ] || grep -q broken app.txt; }
SUITE
seq 1 10 | sed 's/^/line /' > "$REPO/app.txt"
printf 'not ok 1 - alpha\n' > "$REPO/failing.txt"
g add -A && g commit -qm base

ts() { # ts <args...> — task-step in the fixture repo; sets out, err, rc
  out=$(cd "$REPO" && bash "$S/task-step" "$@" 2>"$TMP/err"); rc=$?
  err=$(cat "$TMP/err")
}
sr() { (cd "$REPO" && bash "$S/suite-run" -- bash -c 'bash suite.sh' >/dev/null 2>&1); } # the controller's own suite run
sr_timeout() { (cd "$REPO" && SUITE_RUN_KILL_AFTER=1 bash "$S/suite-run" --timeout 1 -- bash -c 'bash suite.sh' >/dev/null 2>&1); } # a run that records exit 124
commit() { g add -A && g commit -qm "$1"; }
set_failing() { printf '%s' "$1" > "$REPO/failing.txt"; }
marks() { grep -c "^$1\$" "$SUITE_MARK" 2>/dev/null || true; }
clean_report() {
  cat > "$WS/task-$1-review-report.md" <<'REPORT'
## Verdict
spec: pass
quality: approved
scores: spec 17 / scope 17 / verification 16 / quality 16

## Strengths
Fine.

## Findings

## Cannot verify

## Assessment
Fine.
REPORT
}

ts start docs/plan.md 1 --suite 'bash suite.sh'
check "start --suite: exit 0" "$rc" "0"
WS=$(winpath "$(cd "$REPO" && bash "$S/sdd-workspace" docs/plan.md)")

# Task 1: no base row, no file: the suite runs once at the base, after the setup.
set_failing $'not ok 1 - alpha\nnot ok 2 - beta\n'
commit "work 1"
sr
ts review docs/plan.md 1
check "task 1: review exits 0" "$rc" "0"
clean_report 1
ts verdict docs/plan.md 1
check "task 1: verdict exits 0" "$rc" "0"
check "task 1: only the new failure is red" "$(grep '^suite: ' <<<"$out")" "suite: red (1 failing, 1 baseline)"
check "task 1: the fix file names beta and not alpha" "$(grep -qF beta "$WS/task-1-fix-1.md" && echo yes || echo no) $(grep -qF alpha "$WS/task-1-fix-1.md" && echo yes || echo no)" "yes no"
check "task 1: the base failures are kept" "$(cat "$WS/task-1-base-failures.txt")" "not ok - alpha"
check "task 1: the base log is kept" "$(grep -c alpha "$WS/task-1-base.log")" "1"
check "task 1: the setup ran in the base worktree, once" "$(marks setup)" "1"
check "task 1: the temporary worktree is gone" "$(g worktree list | wc -l | tr -d ' ')" "1"
ts verdict docs/plan.md 1
check "task 1: a second verdict reuses the file" "$(marks setup) $(grep '^suite: ' <<<"$out")" "1 suite: red (1 failing, 1 baseline)"

# Task 2: a suite row at the base sha (task 1's head) answers without a run.
ts start docs/plan.md 2 --suite 'bash suite.sh'
set_failing $'not ok 1 - alpha\nnot ok 2 - beta\nnot ok 3 - gamma\n'
commit "work 2"
sr
ts review docs/plan.md 2
clean_report 2
ts verdict docs/plan.md 2
check "task 2: the base row answers" "$(grep '^suite: ' <<<"$out") $(marks setup) $([ -e "$WS/task-2-base-failures.txt" ] && echo file || echo nofile)" "suite: red (1 failing, 2 baseline) 1 nofile"
check "task 2: the fix file names gamma and not beta" "$(grep -qF gamma "$WS/task-2-fix-1.md" && echo yes || echo no) $(grep -qF beta "$WS/task-2-fix-1.md" && echo yes || echo no)" "yes no"

# Task 3: a passing base gives an empty file, and the new failure is not baseline.
set_failing ''
commit "green"
ts start docs/plan.md 3 --suite 'bash suite.sh'
set_failing $'not ok 1 - delta\n'
commit "work 3"
sr
ts review docs/plan.md 3
clean_report 3
ts verdict docs/plan.md 3
check "task 3: a passing base leaves nothing to excuse" "$(grep '^suite: ' <<<"$out")" "suite: red (1 failing, 0 baseline)"
check "task 3: the empty file is kept" "$([ -f "$WS/task-3-base-failures.txt" ] && [ ! -s "$WS/task-3-base-failures.txt" ] && echo empty || echo other)" "empty"
check "task 3: the base run used the setup" "$(marks setup)" "2"

# Task 4: rereview --covered skips only when the fix head's suite is covered.
set_failing $'not ok 1 - alpha\n'
commit "red again"
ts start docs/plan.md 4 --suite 'bash suite.sh'
printf 'impl\n' >> "$REPO/app.txt"
commit "work 4"
ts review docs/plan.md 4
R0=$(g rev-parse HEAD)
cp "$WS/task-4-step.json" "$TMP/state4.0"
rr_case() { # rr_case <name> <fix: mod|broken|green|slow> <run suite: yes|no|timeout> <want>
  g reset -q --hard "$R0"
  cp "$TMP/state4.0" "$WS/task-4-step.json"
  rm -f "$WS"/task-4-fix-*.md "$WS"/task-4-rereview-*-prompt.md
  case $2 in
    mod) awk 'NR == 2 { print "changed"; next } { print }' "$REPO/app.txt" > "$REPO/app.tmp" && mv "$REPO/app.tmp" "$REPO/app.txt" ;;
    broken) awk 'NR == 2 { print "broken"; next } { print }' "$REPO/app.txt" > "$REPO/app.tmp" && mv "$REPO/app.tmp" "$REPO/app.txt" ;;
    slow) awk 'NR == 2 { print "changed"; next } { print }' "$REPO/app.txt" > "$REPO/app.tmp" && mv "$REPO/app.tmp" "$REPO/app.txt"; : > "$REPO/slow.txt" ;;
    green) awk 'NR == 2 { print "changed"; next } { print }' "$REPO/app.txt" > "$REPO/app.tmp" && mv "$REPO/app.tmp" "$REPO/app.txt"; : > "$REPO/failing.txt" ;;
  esac
  commit fix
  printf -- '- app.txt: wrong value\n\nFixed.\n' > "$WS/task-4-fix-1.md"
  [ "$3" != yes ] || sr
  [ "$3" != timeout ] || sr_timeout
  ts rereview docs/plan.md 4 --covered
  check "rereview $1" "$rc $(grep '^re-review: ' <<<"$out") $([ -f "$WS/task-4-rereview-1-prompt.md" ] && echo prompt || echo none)" "$4"
}
rr_case "no suite row for the fix head: not skipped" mod no "0 re-review: not skipped (suite not run) prompt"
rr_case "a non-baseline failure at the fix head: not skipped" broken yes "0 re-review: not skipped (suite red) prompt"
rr_case "baseline failures only: skipped" mod yes "0 re-review: skipped (2 changed lines, 1 finding, app.txt) none"
rr_case "a suite that timed out with baseline lines only: not skipped" slow timeout "0 re-review: not skipped (suite red) prompt"
rr_case "a passing suite: skipped" green yes "0 re-review: skipped (3 changed lines, 1 finding, app.txt) none"
check "task 4: the base run happened once" "$(marks setup)" "3"

# Task 5: a task started before --suite existed keeps today's rule.
ts start docs/plan.md 5
printf 'impl\n' >> "$REPO/app.txt"
commit "work 5"
ts review docs/plan.md 5
printf -- '- app.txt: wrong value\n\nFixed.\n' > "$WS/task-5-fix-1.md"
awk 'NR == 3 { print "changed"; next } { print }' "$REPO/app.txt" > "$REPO/app.tmp" && mv "$REPO/app.tmp" "$REPO/app.txt"
commit fix
ts rereview docs/plan.md 5 --covered
check "no recorded suite: today's skip rule" "$rc $(grep '^re-review: ' <<<"$out")" "0 re-review: skipped (2 changed lines, 1 finding, app.txt)"

# Task 6: a base run that cannot start leaves no file, and every failure is new.
sed 's/`touch setup.done`/`false`/' "$REPO/docs/plan.md" > "$REPO/docs/plan.tmp" && mv "$REPO/docs/plan.tmp" "$REPO/docs/plan.md"
commit "setup that fails"
ts start docs/plan.md 6 --suite 'bash suite.sh'
set_failing $'not ok 1 - alpha\nnot ok 2 - zeta\n'
commit "work 6"
sr
ts review docs/plan.md 6
clean_report 6
ts verdict docs/plan.md 6
check "task 6: no base run, no baseline" "$(grep '^suite: ' <<<"$out")" "suite: red (2 failing, 0 baseline)"
check "task 6: the stderr says why" "$(grep -c 'no base run' <<<"$err") $(grep -c 'worktree setup failed' <<<"$err")" "1 1"
check "task 6: the stderr names the setup log" "$(grep -cF "(log $WS/task-6-base.log.setup.log)" <<<"$err")" "1"
check "task 6: the setup log is kept" "$([ -f "$WS/task-6-base.log.setup.log" ] && echo yes || echo no)" "yes"
check "task 6: no file is kept, so the next verdict tries again" "$([ -e "$WS/task-6-base-failures.txt" ] && echo file || echo nofile)" "nofile"
check "task 6: the temporary worktree is gone" "$(g worktree list | wc -l | tr -d ' ')" "1"

sed 's/^\(\*\*Worktree setup:\*\* \).*$/\1`touch setup.done`/' "$REPO/docs/plan.md" > "$REPO/docs/plan.tmp" && mv "$REPO/docs/plan.tmp" "$REPO/docs/plan.md"
commit "setup that works"

# Tasks 7 and 8: a sequential group. Task 8 starts at Task 7's head, so a test
# Task 7 broke fails at Task 8's base too; the group is compared with the base
# of its first member.
set_failing ''
commit "green for the group"
ts start docs/plan.md 7 --suite 'bash suite.sh'
set_failing $'not ok 1 - regress\n'
commit "member 1 breaks a test"
ts start docs/plan.md 8 --suite 'bash suite.sh'
printf 'impl 8\n' >> "$REPO/app.txt"
commit "member 2"
sr
G_HEAD=$(g rev-parse HEAD)
jq -n --arg h "$G_HEAD" --arg c "$REPO" '{tasks: [7, 8], reviewHead: $h, t0: 0, reviewChecks: [{cwd: $c, head: $h, dirty: []}]}' > "$WS/group-7,8-step.json"
for t in 7 8; do
  jq --arg h "$G_HEAD" '.reviewHead = $h | .group = "7,8"' "$WS/task-$t-step.json" > "$TMP/s.json" && mv "$TMP/s.json" "$WS/task-$t-step.json"
done
{
  printf '## Verdict\n'
  for t in 7 8; do
    printf 'Task %s spec: pass\nTask %s quality: approved\nTask %s scores: spec 17 / scope 17 / verification 17 / quality 17\n' "$t" "$t" "$t"
  done
} > "$WS/group-7,8-review-report.md"
ts verdict docs/plan.md 7 8 --group
check "group: a regression made by an earlier member is not baseline" "$rc $(grep '^suite: ' <<<"$out")" "0 suite: red (1 failing, 0 baseline)"
check "group: the finding is in the last member's fix file" "$(grep '^fix: ' <<<"$out")" "fix: $WS/task-8-fix-1.md (1 finding)"
check "group: the fix file names the regression" "$(grep -cF regress "$WS/task-8-fix-1.md")" "2"

# A step file that cannot be read is not "no suite recorded".
cp "$WS/task-8-step.json" "$TMP/step8.bak"
rm -f "$WS/task-8-step.json"
ts verdict docs/plan.md 7 8 --group
check "group: a missing last member's step file exits 6" "$rc $(grep -cF "cannot read $WS/task-8-step.json" <<<"$err") $(grep -c 'suite: none recorded' <<<"$out")" "6 1 0"
printf '{not json\n' > "$WS/task-8-step.json"
ts verdict docs/plan.md 7 8 --group
check "group: an invalid last member's step file exits 6" "$rc $(grep -cF "cannot read $WS/task-8-step.json" <<<"$err") $(grep -c 'suite: none recorded' <<<"$out")" "6 1 0"
cp "$TMP/step8.bak" "$WS/task-8-step.json"

# rereview --base would move the group's comparison base, so a sequential
# member refuses it.
ts rereview docs/plan.md 8 --base "$(g rev-parse HEAD~1)"
check "group: rereview --base on a sequential member exits 2" "$rc $(grep -cF -- '--base does not apply to a group member; see delegated-task.md §3a' <<<"$err")" "2 1"
check "group: the refused rereview leaves the step file as it was" "$(cmp -s "$TMP/step8.bak" "$WS/task-8-step.json" && echo same || echo changed)" "same"

# Task 9: a red suite whose failing lines are all baseline lets the task complete.
set_failing $'not ok 1 - alpha\n'
commit "alpha fails at the base"
sr
ts start docs/plan.md 9 --suite 'bash suite.sh'
printf 'impl 9\n' >> "$REPO/app.txt"
commit "work 9"
sr
ts review docs/plan.md 9
clean_report 9
ts verdict docs/plan.md 9
check "task 9: all-baseline failures are no finding" "$rc $(grep '^suite: ' <<<"$out") $(grep '^findings: ' <<<"$out") $(grep '^fix: ' <<<"$out")" \
  "0 suite: red (0 failing, 1 baseline) findings: 0 Critical, 0 Important, 0 Minor fix: none"
check "task 9: no fix file is written" "$([ -e "$WS/task-9-fix-1.md" ] && echo file || echo nofile)" "nofile"

# Task 10: a base that fails with no recognisable test line is red, not green.
set_failing $'boom\n'
commit "a suite that fails without test lines"
sr
ts start docs/plan.md 10 --suite 'bash suite.sh'
printf 'impl 10\n' >> "$REPO/app.txt"
commit "work 10"
sr
ts review docs/plan.md 10
clean_report 10
ts verdict docs/plan.md 10
check "task 10: a red base row without test lines excuses the head" "$rc $(grep '^suite: ' <<<"$out")" "0 suite: red (0 failing, 1 baseline)"

# Task 11: the same, when the suite has to run at the base.
printf 'more\n' >> "$REPO/app.txt"
commit "no suite row at this commit"
ts start docs/plan.md 11 --suite 'bash suite.sh'
printf 'impl 11\n' >> "$REPO/app.txt"
commit "work 11"
sr
ts review docs/plan.md 11
clean_report 11
ts verdict docs/plan.md 11
check "task 11: a red base run without test lines excuses the head" "$rc $(grep '^suite: ' <<<"$out")" "0 suite: red (0 failing, 1 baseline)"
check "task 11: the base failures hold the exit code" "$(cat "$WS/task-11-base-failures.txt")" "command exit 1"

# Task 12: a base run that times out is not paid again.
set_failing $'not ok 1 - alpha\n'
: > "$REPO/slow.txt"
commit "a base that is slow"
ts start docs/plan.md 12 --suite 'bash suite.sh'
g rm -q slow.txt
commit "work 12"
sr
ts review docs/plan.md 12
clean_report 12
runs0=$(marks setup)
export TASK_STEP_BASE_TIMEOUT=1 SUITE_RUN_KILL_AFTER=1
ts verdict docs/plan.md 12
check "task 12: a timed-out base excuses nothing" "$rc $(grep '^suite: ' <<<"$out")" "0 suite: red (1 failing, 0 baseline)"
check "task 12: the base ran once" "$(($(marks setup) - runs0))" "1"
check "task 12: the timeout is recorded" "$([ -e "$WS/task-12-base-timeout" ] && echo marker || echo none)" "marker"
check "task 12: no base failures file" "$([ -e "$WS/task-12-base-failures.txt" ] && echo file || echo nofile)" "nofile"
ts verdict docs/plan.md 12
unset TASK_STEP_BASE_TIMEOUT SUITE_RUN_KILL_AFTER
check "task 12: a second verdict does not run the base again" "$(($(marks setup) - runs0)) $(grep '^suite: ' <<<"$out")" "1 suite: red (1 failing, 0 baseline)"
check "task 12: the stderr says the base timed out" "$(grep -c 'timed out' <<<"$err")" "1"
check "task 12: the temporary worktree is gone" "$(g worktree list | wc -l | tr -d ' ')" "1"

# Tasks 13 to 18 join the fixture plan; Task 14 names the command its baseline item runs.
for n in 13 14 15 16 17 18; do
  printf '\n### Task %s: Task %s\n\n**Files:**\n- Modify: `app.txt`\n\n**Implementer:** dforge:impl-sonnet-low\n**Evaluation:** files 0 - spec 0 - coupling 1 - risk 0 = 1\n' "$n" "$n"
  [ "$n" != 14 ] || printf '\nRun: `bash suite.sh`\n'
done >> "$REPO/docs/plan.md"
set_setup() { # set_setup <command> — the plan header's Worktree setup
  awk -v s="$1" '/^\*\*Worktree setup:\*\*/ { print "**Worktree setup:** `" s "`"; next } { print }' "$REPO/docs/plan.md" > "$REPO/docs/plan.tmp" \
    && mv "$REPO/docs/plan.tmp" "$REPO/docs/plan.md"
}
setup_runs() { grep -c . "$SUITE_MARK.setup" 2>/dev/null || true; }

# Task 13: a Worktree setup that hangs is bounded, logged and not run again.
set_setup 'echo hanging; echo ran >> "$SUITE_MARK.setup"; exec sleep 20'
printf 'more\n' >> "$REPO/app.txt"
commit "a setup that hangs"
ts start docs/plan.md 13 --suite 'bash suite.sh'
printf 'impl 13\n' >> "$REPO/app.txt"
commit "work 13"
sr
ts review docs/plan.md 13
clean_report 13
plain0=$(marks plain)
export TASK_STEP_BASE_TIMEOUT=1 SUITE_RUN_KILL_AFTER=1
ts verdict docs/plan.md 13
check "task 13: a hung setup excuses nothing" "$rc $(grep '^suite: ' <<<"$out")" "0 suite: red (1 failing, 0 baseline)"
check "task 13: the timeout is recorded" "$([ -e "$WS/task-13-base-timeout" ] && echo marker || echo none)" "marker"
check "task 13: the setup ran once and the suite never ran at the base" "$(setup_runs) $(($(marks plain) - plain0))" "1 0"
check "task 13: the setup log holds its output" "$(cat "$WS/task-13-base.log.setup.log" 2>/dev/null)" "hanging"
check "task 13: the base log is the setup log" "$(cmp -s "$WS/task-13-base.log" "$WS/task-13-base.log.setup.log" && echo same || echo differ)" "same"
check "task 13: the stderr says the base timed out" "$(grep -c 'timed out' <<<"$err")" "1"
ts verdict docs/plan.md 13
unset TASK_STEP_BASE_TIMEOUT SUITE_RUN_KILL_AFTER
check "task 13: a second verdict does not run the setup again" "$(setup_runs) $(($(marks plain) - plain0))" "1 0"
check "task 13: the temporary worktree is gone" "$(g worktree list | wc -l | tr -d ' ')" "1"

# Task 14: a baseline item whose setup times out goes to the seat, with the setup log kept.
set_setup 'echo setup-124; echo ran >> "$SUITE_MARK.setup"; exit 124'
commit "a setup that reports a timeout"
ts start docs/plan.md 14
printf 'impl 14\n' >> "$REPO/app.txt"
commit "work 14"
ts review docs/plan.md 14
cat > "$WS/task-14-review-report.md" <<'REPORT'
## Verdict
spec: cannot-verify
quality: approved
scores: spec 15 / scope 17 / verification 12 / quality 16

## Strengths
Fine.

## Findings

## Cannot verify
- cannot-verify: baseline bash suite.sh, expect fail — does the suite fail before the task

## Assessment
Fine.
REPORT
setup0=$(setup_runs)
ts verdict docs/plan.md 14
check "task 14: the item stays for the seat, without the not-named label" "$rc $(grep '^cannot-verify: ' <<<"$out")" \
  "0 cannot-verify: baseline bash suite.sh, expect fail — does the suite fail before the task"
check "task 14: the setup ran once" "$(($(setup_runs) - setup0))" "1"
check "task 14: the setup log is kept beside the baseline log" "$(cat "$WS/task-14-baseline-1.log.setup.log" 2>/dev/null)" "setup-124"
check "task 14: nothing is settled and nothing is a finding" "$(grep -c 'Task 14: Ruling: cannot-verify' "$WS/progress.md") $(grep '^findings: ' <<<"$out")" "0 findings: 0 Critical, 0 Important, 0 Minor"
check "task 14: the temporary worktree is gone" "$(g worktree list | wc -l | tr -d ' ')" "1"

# Task 14 again: once the plan names no setup, no setup log from the earlier run stays.
cp "$WS/task-14-review-report.md" "$TMP/task-14-review-report.md"
set_setup none
commit "the plan names no setup"
ts review docs/plan.md 14
cp "$TMP/task-14-review-report.md" "$WS/task-14-review-report.md"
ts verdict docs/plan.md 14
check "task 14 without a setup: the earlier setup log is gone" "$rc $([ -e "$WS/task-14-baseline-1.log.setup.log" ] && echo kept || echo gone)" "0 gone"

# Task 15: a passing suites.tsv row at the base answers without a base run.
set_setup 'touch setup.done'
set_failing ''
commit "green base for task 15"
sr
ts start docs/plan.md 15 --suite 'bash suite.sh'
set_failing $'not ok 1 - delta\n'
commit "work 15"
sr
ts review docs/plan.md 15
clean_report 15
setups0=$(marks setup)
ts verdict docs/plan.md 15
check "task 15: a passing base row leaves no baseline" "$rc $(grep '^suite: ' <<<"$out")" "0 suite: red (1 failing, 0 baseline)"
check "task 15: no base run and no base failures file" "$(($(marks setup) - setups0)) $([ -e "$WS/task-15-base-failures.txt" ] && echo file || echo nofile)" "0 nofile"

# Task 16: a base row that timed out is not an answer; the suite runs at the base.
set_failing $'not ok 1 - alpha\n'
commit "alpha fails at the base of task 16"
: > "$REPO/slow.txt"
sr_timeout
rm -f "$REPO/slow.txt"
ts start docs/plan.md 16 --suite 'bash suite.sh'
set_failing $'not ok 1 - alpha\nnot ok 2 - beta\n'
commit "work 16"
sr
ts review docs/plan.md 16
clean_report 16
setups0=$(marks setup)
ts verdict docs/plan.md 16
check "task 16: a timed-out base row falls through to a base run" "$rc $(grep '^suite: ' <<<"$out") $(($(marks setup) - setups0))" "0 suite: red (1 failing, 1 baseline) 1"
check "task 16: the base run's failures are kept" "$(cat "$WS/task-16-base-failures.txt" 2>/dev/null)" "not ok - alpha"
check "task 16: no timeout is recorded" "$([ -e "$WS/task-16-base-timeout" ] && echo marker || echo none)" "none"

# Task 17: verdict --cwd finds the base row in that checkout's state when the main checkout's has none.
set_failing $'not ok 1 - alpha\n'
commit "alpha fails at the base of task 17"
ts start docs/plan.md 17 --suite 'bash suite.sh'
WT=$TMP/wt17
g worktree add -q --detach "$WT" HEAD
(cd "$WT" && bash "$S/suite-run" -- bash -c 'bash suite.sh' >/dev/null 2>&1)
printf 'not ok 1 - alpha\nnot ok 2 - beta\n' > "$WT/failing.txt"
git -C "$WT" add -A && git -C "$WT" commit -qm "work 17"
W17=$(git -C "$WT" rev-parse HEAD | tr -d '\r')
(cd "$WT" && bash "$S/suite-run" -- bash -c 'bash suite.sh' >/dev/null 2>&1)
ts review docs/plan.md 17 --head "$W17" --cwd "$WT"
clean_report 17
setups0=$(marks setup)
ts verdict docs/plan.md 17 --cwd "$WT"
check "task 17: the base row in the --cwd checkout's state excuses alpha" "$rc $(grep '^suite: ' <<<"$out")" "0 suite: red (1 failing, 1 baseline)"
check "task 17: no base run and no base failures file" "$(($(marks setup) - setups0)) $([ -e "$WS/task-17-base-failures.txt" ] && echo file || echo nofile)" "0 nofile"
g worktree remove --force "$WT"

# Task 18: a wave task in a group, which carries a head ref, keeps rereview --base.
ts start docs/plan.md 18
printf 'impl 18\n' >> "$REPO/app.txt"
commit "work 18"
g branch t18-ref
ts review docs/plan.md 18 --head t18-ref
jq '.group = "18,19"' "$WS/task-18-step.json" > "$TMP/s18.json" && mv "$TMP/s18.json" "$WS/task-18-step.json"
printf -- '- app.txt: wrong value\n\nFixed.\n' > "$WS/task-18-fix-1.md"
printf 'fix 18\n' >> "$REPO/app.txt"
commit "fix 18"
g branch -f t18-ref HEAD
EARLIER=$(g rev-parse HEAD~2 | tr -d '\r')
ts rereview docs/plan.md 18 --base "$EARLIER"
check "task 18: rereview --base on a grouped wave task is accepted and recorded" "$rc $(jq -r '.base' "$WS/task-18-step.json" | tr -d '\r')" "0 $EARLIER"

# Row 29: the stale ten-minute figure for a red fix-head suite is gone.
dt=$(tr -d '\r' < "$DT" | tr '\n' ' ' | tr -s ' ')
check "the doc says a base run under rereview --covered takes up to an hour" "$(grep -cF 'which takes up to an hour (`TASK_STEP_BASE_TIMEOUT`)' <<<"$dt")" "1"
check "the doc no longer says it takes up to ten minutes" "$(grep -cF 'which takes up to ten minutes' <<<"$dt")" "0"
check "the doc gives a Worktree setup its own time limit, twice" "$(grep -oF 'as long again for a **Worktree setup:**' <<<"$dt" | wc -l | tr -d ' ')" "2"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
