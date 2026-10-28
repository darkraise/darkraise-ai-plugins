#!/usr/bin/env bash
# Acceptance tests for the faster-plans spec
# (docs/dforge/specs/2026-10-26-faster-plans-design.md), statements A1-A23.
# Each test is written from the statement's text and reaches the behaviour
# through the scripts and documents the spec names: plan-lint, plan-revise,
# review-route, task-step, wave, next-step, plan-amend, the cockpit's ledger
# reader, the agent definitions and the shipped skills, prompts and references.
# Usage:
#   bash faster-plans.acceptance.test.sh            run every test
#   bash faster-plans.acceptance.test.sh A5 A9      run the named tests only
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN="$(cd "$HERE/.." && pwd)"
REPO_ROOT="$(cd "$PLUGIN/../.." && pwd)"
S="$PLUGIN/scripts"
STEP="$S/task-step"
ROUTE="$S/review-route"
LINT="$S/plan-lint"
REVISE="$S/plan-revise"
WAVE="$S/wave"
NEXT="$S/next-step"
AMEND="$S/plan-amend"
FIXTURES="$HERE/fixtures"

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
winpath() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s\n' "$1"; fi; }
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME/.claude"
unset CLAUDE_CONFIG_DIR CODEX_HOME AR_SESSION DFORGE_BUDGET DR_SUPERPOWERS_BUDGET CLAUDE_PROJECT_DIR
unset GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 DFORGE_NO_SETTINGS=1 MSYS_NO_PATHCONV=1
export DR_CODEX_SESSION_DIR="$TMP/codex-sessions" CLAUDE_CODE_SESSION_ID=acceptance-session
printf '%s\n' '#!/usr/bin/env bash' 'echo "codex-gate usable=true reason= review=true lane=false resets_at=- source=cache"' > "$TMP/gate-stub"
export TASK_STEP_CODEX_GATE="$TMP/gate-stub"
# plan-lint's lane probe asks this roster; a fixed answer keeps the machine's
# own Codex install out of every case.
printf '%s\n' '#!/usr/bin/env bash' "echo '[{\"id\":\"codex\",\"usable\":true,\"reason\":null}]'" > "$TMP/roster-stub"
export PLAN_LINT_ROSTER="$TMP/roster-stub"

session() { # session <review true|false> <lane true|false> | absent — this session's Codex gate file
  rm -rf "$DR_CODEX_SESSION_DIR"
  [ "$1" != absent ] || return 0
  mkdir -p "$DR_CODEX_SESSION_DIR"
  printf '{"session_id":"%s","usable":true,"review":%s,"lane":%s}\n' "$CLAUDE_CODE_SESSION_ID" "$1" "$2" > "$DR_CODEX_SESSION_DIR/$CLAUDE_CODE_SESSION_ID.json"
}
session absent

doc() { tr -d '\r' < "$1" | tr '\n' ' ' | tr -s ' '; } # a file as one line, whitespace collapsed
lines_of() { printf '%s\n' "$1" | grep -c .; }

# --- fixtures: a task-loop repository --------------------------------------

short() { git -C "$R" rev-parse --short=7 "$1"; }
full() { git -C "$R" rev-parse "$1"; }
ts() { out=$(cd "$R" && timeout 120 bash "$STEP" "$@" 2>"$TMP/err"); rc=$?; err=$(cat "$TMP/err"); }
route() { out=$(cd "$R" && timeout 60 bash "$ROUTE" "$@" 2>"$TMP/err"); rc=$?; err=$(cat "$TMP/err"); }
commit_file() { # commit_file <file> <content> <message>
  printf '%s\n' "$2" > "$R/$1"
  git -C "$R" add "$1" && git -C "$R" commit -qm "$3"
}
ledger_text() { cat "$WS/progress.md" 2>/dev/null; }
ws_files() { ls -A "$WS" 2>/dev/null | sort | tr '\n' ' '; }

PLAN_TEXT='|# Faster Plans Acceptance Fixture
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
|1. grouped one
|2. risk three
|3. grouped two
|4. risk two
|5. total five
|6. grouped three
|7. grouped four
|8. unscored
|9. grouped five
|
|### Task 1: grouped one
|
|**Files:**
|- Modify: `app.txt`
|
|**Implementer:** dforge:impl-sonnet-low
|**Evaluation:** files 0 - spec 0 - coupling 1 - risk 0 = 1
|
|Body.
|
|### Task 2: risk three
|
|**Files:**
|- Modify: `app.txt`
|
|**Implementer:** dforge:impl-opus-high
|**Evaluation:** files 1 - spec 2 - coupling 1 - risk 3 = 7
|
|### Task 3: grouped two
|
|**Files:**
|- Modify: `other.txt`
|
|**Implementer:** dforge:impl-sonnet-medium
|**Evaluation:** files 1 - spec 1 - coupling 1 - risk 1 = 4
|
|### Task 4: risk two
|
|**Files:**
|- Modify: `app.txt`
|
|**Implementer:** dforge:impl-sonnet-medium
|**Evaluation:** files 0 - spec 0 - coupling 1 - risk 2 = 3
|
|### Task 5: total five
|
|**Files:**
|- Modify: `app.txt`
|
|**Implementer:** dforge:impl-sonnet-high
|**Evaluation:** files 2 - spec 2 - coupling 1 - risk 0 = 5
|
|### Task 6: grouped three
|
|**Files:**
|- Modify: `app.txt`
|
|**Implementer:** dforge:impl-sonnet-low
|**Evaluation:** files 0 - spec 0 - coupling 1 - risk 1 = 2
|
|### Task 7: grouped four
|
|**Files:**
|- Modify: `other.txt`
|
|**Implementer:** dforge:impl-sonnet-low
|**Evaluation:** files 0 - spec 1 - coupling 1 - risk 0 = 2
|
|### Task 8: unscored
|
|**Files:**
|- Modify: `other.txt`
|
|**Implementer:** dforge:impl-sonnet-low
|
|### Task 9: grouped five
|
|**Files:**
|- Modify: `other.txt`
|
|**Implementer:** dforge:impl-sonnet-medium
|**Evaluation:** files 1 - spec 1 - coupling 1 - risk 1 = 4'

CODEX_PLAN_TEXT='|# Codex Fixture
|
|**Host:** codex
|
|### Task 1: only
|
|**Evaluation:** files=0, spec=0, coupling=0, risk=0; weighted routing score=0'

new_repo() { # new_repo <name> — a throwaway repository with the fixture plans; sets R and WS
  R="$TMP/$1"
  git init -q -b main "$R"
  git -C "$R" config user.name Darkraise
  git -C "$R" config user.email dark@example.invalid
  mkdir -p "$R/docs"
  sed 's/^|//' <<<"$PLAN_TEXT" > "$R/docs/plan.md"
  sed 's/^|//' <<<"$CODEX_PLAN_TEXT" > "$R/docs/codex-plan.md"
  seq 1 10 | sed 's/^/line /' > "$R/app.txt"
  cp "$R/app.txt" "$R/other.txt"
  git -C "$R" add -A && git -C "$R" commit -qm "docs: add fixtures"
  WS=$(winpath "$(cd "$R" && bash "$S/sdd-workspace" docs/plan.md)")
  session absent
}

hold_task() { # hold_task <n> <file> — start task n, commit a file, hold it
  ts start docs/plan.md "$1"
  commit_file "$2" "work of task $1" "feat: task $1"
  ts hold docs/plan.md "$1"
}

# --- fixtures: plan-lint plans ---------------------------------------------

LINTDIR="$TMP/lint"
mkdir -p "$LINTDIR/docs"
printf '# Spec\n' > "$LINTDIR/docs/spec.md"

gen_plan() { # gen_plan <extra header line or empty> <"F S C R impl[~label line...]">... — a Claude plan
  local extra=$1 i=0 spec f s c r impl more
  shift
  printf '%s\n' '# Gen Plan' '' '**Goal:** Fixture.' '' '**Spec:** `docs/spec.md`' '' \
    '**Execution:** subagent — `claude --model sonnet --effort high` — fixture' ''
  [ -z "$extra" ] || printf '%s\n\n' "$extra"
  printf '%s\n' '**Plan review:** 2026-10-26 — dforge:judge-opus — executability 18 / coherence 18 / coverage 18 / assumptions 18 (round 1)' '' \
    '## Global Constraints' '' '- None.' '' '## Contracts' '' 'None' '' '## Assumptions (evidence)' '' '- None.' '' '## Task index' ''
  for spec in "$@"; do i=$((i + 1)); printf '%d. T%d\n' "$i" "$i"; done
  printf '\n'
  i=0
  for spec in "$@"; do
    i=$((i + 1))
    read -r f s c r impl more <<<"${spec//\~/ ~ }"
    printf '### Task %d: T%d\n\n**Files:**\n- Create: `f%d.txt`\n\n**Implementer:** dforge:%s\n**Evaluation:** files %d - spec %d - coupling %d - risk %d = %d\n' \
      "$i" "$i" "$i" "impl-$impl" "$f" "$s" "$c" "$r" $((f + s + c + r))
    if [ -n "${more:-}" ]; then
      tr '~' '\n' <<<"${more#~}" | sed 's/^ *//' | grep . || true
    fi
    printf '\nBody.\n\n'
  done
}

gen_codex_plan() { # gen_codex_plan <"F S C R pair">... — a Host: codex plan, pair as "model/effort"
  local i=0 spec f s c r pair model effort
  printf '%s\n' '# Gen Codex Plan' '' 'Host: codex' 'Routing policy: codex-v4' '' '**Goal:** Fixture.' '' '**Spec:** docs/spec.md' '' \
    '**Execution:** subagent — codex gpt-6.1-sol / high — native pair' '' \
    '**Plan review:** 2026-10-26 — codex gpt-6-astra / high — executability 18 / coherence 18 / coverage 18 / assumptions 18 (round 1)' '' \
    '## Global Constraints' '' '- None.' '' '## Contracts' '' 'None' '' '## Assumptions (evidence)' '' '- None.' '' '## Task index' ''
  for spec in "$@"; do i=$((i + 1)); printf '%d. T%d\n' "$i" "$i"; done
  printf '\n'
  i=0
  for spec in "$@"; do
    i=$((i + 1))
    read -r f s c r pair <<<"$spec"
    model=${pair%/*} effort=${pair#*/}
    printf '### Task %d: T%d\n\n**Files:**\n- Create: `f%d.txt`\n\n**Implementer:** codex %s / %s\n**Evaluation:** files=%d, spec=%d, coupling=%d, risk=%d; weighted routing score=%d\n**Assignment source:** rubric\n\nBody.\n\n' \
      "$i" "$i" "$i" "$model" "$effort" "$f" "$s" "$c" "$r" $((f + s + c + 2 * r))
  done
}

lint() { # lint <file> [args...] — run from the lint directory; sets out and rc
  out=$(cd "$LINTDIR" && timeout 120 bash "$LINT" "$@" --no-probe 2>&1); rc=$?
}
lint_probe() { # lint_probe <file> — the same, with the lane probe on
  out=$(cd "$LINTDIR" && timeout 120 bash "$LINT" "$1" 2>&1); rc=$?
}

# --- A1 ----------------------------------------------------------------------

a1() {
  local skill drafter reviewer criteria
  skill=$(doc "$PLUGIN/skills/writing-plans/SKILL.md")
  drafter=$(doc "$PLUGIN/skills/writing-plans/references/drafter-prompt.md")
  reviewer=$(doc "$PLUGIN/skills/writing-plans/references/plan-reviewer-prompt.md")
  criteria=$(doc "$PLUGIN/criteria/plan-review.md")

  matches "A1: writing-plans says a task carries its interfaces" "$skill" 'A task carries its files, its interfaces'
  matches "A1: writing-plans says it carries the complete code of its tests" "$skill" 'the complete code of its tests'
  matches "A1: writing-plans says it carries the commands that verify it" "$skill" 'the commands that verify it'
  matches "A1: writing-plans limits implementation code to a configuration value" "$skill" 'Implementation code appears only where no test can pin the behaviour: a configuration value'
  matches "A1: writing-plans names generated-file or migration commands" "$skill" 'a generated-file or migration command'
  matches "A1: writing-plans names a fixed constant the spec names" "$skill" 'a fixed constant the spec names'
  matches "A1: writing-plans gives Step 3 no implementation code" "$skill" 'Step 3 describes the implementation; it carries no implementation code'

  matches "A1: the drafter prompt asks for each task's interfaces" "$drafter" 'names its exact files and its interfaces'
  matches "A1: the drafter prompt asks for the complete code of its tests" "$drafter" 'gives the complete code of its tests'
  matches "A1: the drafter prompt limits implementation code to the same three cases" "$drafter" 'implementation code appears only for a configuration value, a generated-file or migration command, or a fixed constant the spec names'
  matches "A1: the drafter prompt ends each task with its verify commands" "$drafter" 'ends with the commands that verify it'

  matches "A1: the plan-reviewer prompt expects interfaces, test code and verify commands in a code task" "$reviewer" 'a code task gives its interfaces, the complete code of its tests and its verify commands'
  matches "A1: the plan-reviewer prompt treats a missing or stub test as a finding" "$reviewer" 'a missing or stub test is'
  matches "A1: the plan-reviewer prompt sends the reviewer to the plan-review criteria" "$reviewer" 'criteria/plan-review.md'
  matches "A1: the plan-review criteria require interfaces and the complete code of the tests" "$criteria" 'every task gives its interfaces and the complete code of its tests'
  matches "A1: the plan-review criteria limit implementation code to the three cases" "$criteria" 'implementation code appears only for a configuration value, a generated-file or migration command, or a fixed constant the spec names'
}

# --- A2 ----------------------------------------------------------------------

a2() {
  local base="0 0 1 0 sonnet-low"
  gen_plan "" "$base" "2 2 1 0 sonnet-high" > "$LINTDIR/c5.md"
  lint c5.md
  check "A2: a Claude task with files+spec+coupling 5 passes plan-lint" "$rc" "0"
  absent "A2: and draws no Rule S finding" "$out" 'Rule S'
  absent "A2: and draws no error on its task" "$out" 'ERROR Task 2'

  gen_plan "" "$base" "2 2 2 0 opus-high" > "$LINTDIR/c6.md"
  lint c6.md
  check "A2: a Claude task with files+spec+coupling 6 fails plan-lint" "$rc" "1"
  matches "A2: and the error is Rule S on that task" "$out" 'ERROR Task 2: Rule S'

  gen_plan "" "$base" "1 2 2 1 opus-high" > "$LINTDIR/c5r.md"
  lint c5r.md
  absent "A2: a total of 6 whose files+spec+coupling is 5 draws no Rule S finding" "$out" 'Rule S'

  gen_plan "" "$base" "0 3 0 0 sonnet-medium" > "$LINTDIR/s3.md"
  lint s3.md
  check "A2: a spec 3 task without an override fails plan-lint" "$rc" "1"
  matches "A2: and the error is Rule S on that task" "$out" 'ERROR Task 2: Rule S'

  gen_plan "" "$base" "0 3 0 0 sonnet-medium~**Override:** the approach is kept as written" > "$LINTDIR/s3o.md"
  lint s3o.md
  check "A2: a spec 3 task with a human Override passes plan-lint" "$rc" "0"
  absent "A2: and draws no error on its task" "$out" 'ERROR Task 2'

  gen_codex_plan "1 1 1 0 gpt-6.1-sol/low" > "$LINTDIR/x3.md"
  lint x3.md
  check "A2: a Host: codex task with files+spec+coupling 3 passes plan-lint" "$rc" "0"
  absent "A2: and draws no Rule S finding" "$out" 'Rule S'

  gen_codex_plan "2 1 1 0 gpt-6.1-sol/medium" > "$LINTDIR/x4.md"
  lint x4.md
  check "A2: a Host: codex task with files+spec+coupling 4 still fails plan-lint" "$rc" "1"
  matches "A2: and the error is Rule S at 4" "$out" 'ERROR Task 1: Rule S: files\+spec\+coupling must be below 4'

  gen_codex_plan "1 2 1 0 gpt-6.1-sol/medium" > "$LINTDIR/x4b.md"
  lint x4b.md
  matches "A2: a Host: codex task of 1+2+1 also fails at 4" "$out" 'ERROR Task 1: Rule S'
}

# --- A3 ----------------------------------------------------------------------

a3() {
  local want="0:impl-sonnet-low 1:impl-sonnet-low 2:impl-sonnet-low 3:impl-sonnet-medium 4:impl-sonnet-medium 5:impl-sonnet-high 6:impl-opus-high 7:impl-opus-high 8:impl-opus-high"
  # One task per total 0-8, each with files+spec+coupling at most 5 and spec below 3.
  local axes=("0 0 0 0" "0 0 1 0" "0 1 1 0" "1 1 1 0" "1 1 1 1" "2 2 1 0" "2 2 1 1" "2 2 1 2" "2 2 1 3")
  local specs_right=() specs_wrong=() t agent
  for t in 0 1 2 3 4 5 6 7 8; do
    agent=$(tr ' ' '\n' <<<"$want" | grep "^$t:" | sed 's/^[0-9]*:impl-//')
    specs_right+=("${axes[$t]} $agent")
    specs_wrong+=("${axes[$t]} opus-low")
  done
  gen_plan "" "${specs_right[@]}" > "$LINTDIR/t-right.md"
  lint t-right.md
  absent "A3: a plan naming the table's agent for every total 0-8 draws no table mismatch" "$out" 'assignment table'
  absent "A3: and no error on any task" "$out" 'ERROR Task'

  gen_plan "" "${specs_wrong[@]}" > "$LINTDIR/t-wrong.md"
  lint t-wrong.md
  local got
  got=$(sed -n "s/^ERROR Task \([0-9]*\): Implementer impl-opus-low does not match the assignment table's \(impl-[a-z-]*\) for total \([0-9]*\)\$/\3:\2/p" <<<"$out" | sort -n | tr '\n' ' ' | sed 's/ $//')
  check "A3: totals 0-6 map as before and 7 and 8 map to impl-opus-high" "$got" "$want"
}

# --- A4 ----------------------------------------------------------------------

a4() {
  local ext='> **External executors:** codex' base="0 0 1 0 sonnet-low" t out_t
  gen_plan "$ext" "$base" "1 1 1 1 sonnet-medium~**Executor:** codex gpt-6.1-sol / high" > "$LINTDIR/l4.md"
  lint l4.md
  absent "A4: a total-4 task with an Executor line passes the lane gate" "$out" 'fails the lane gate'
  check "A4: and the plan lints clean" "$rc" "0"

  # A task over total 4 is refused the lane on every total above it.
  local specs=("2 2 1 0 sonnet-high" "2 2 1 1 opus-high" "2 2 1 2 opus-high" "2 2 1 3 opus-high")
  local tot=(5 6 7 8) i
  for i in 0 1 2 3; do
    gen_plan "$ext" "$base" "${specs[$i]}~**Executor:** codex gpt-6.1-sol / high" > "$LINTDIR/l-over.md"
    lint l-over.md
    matches "A4: a total-${tot[$i]} task with an Executor line fails the lane gate" "$out" "ERROR Task 2: total ${tot[$i]} / risk [0-9] fails the lane gate"
  done

  # plan-revise reports the same gate: totals 2-4 pass, 5 and 6 fail on the total.
  gen_plan "$ext" "0 1 1 0 sonnet-low" "1 1 1 0 sonnet-medium" "1 1 1 1 sonnet-medium" "2 2 1 0 sonnet-high" "2 2 1 1 opus-high" > "$LINTDIR/rv.md"
  out_t=$(cd "$LINTDIR" && timeout 60 bash "$REVISE" rv.md 2>&1)
  for t in 1 2 3; do
    matches "A4: plan-revise passes the lane gate for the unit of total $((t + 1))" "$out_t" "^unit $t  score=$((t + 1))  risk=[01]  rule_s=ok  gate=pass"
  done
  matches "A4: plan-revise fails the lane gate for the total-5 unit on its total" "$out_t" '^unit 4  score=5  risk=0  rule_s=ok  gate=fail:total'
  matches "A4: plan-revise fails the lane gate for the total-6 unit on its total" "$out_t" '^unit 5  score=6  risk=1  rule_s=ok  gate=fail:total'

  # The probe never offers the lane to a task above total 4.
  session false true
  gen_plan "" "1 1 1 0 sonnet-medium" "2 2 1 0 sonnet-high" "2 2 1 1 opus-high" > "$LINTDIR/probe.md"
  lint_probe probe.md
  has "A4: the lane probe offers a total-3 task with no Executor line" "$out" "WARN Task 1: lane-eligible with no **Executor:** line"
  lacks "A4: the lane probe never offers a total-5 task" "$out" "WARN Task 2: lane-eligible"
  lacks "A4: the lane probe never offers a total-6 task" "$out" "WARN Task 3: lane-eligible"
  session absent
}

# --- A5 ----------------------------------------------------------------------

a5() {
  new_repo a5
  local expect="1:group 2:task 3:group 4:task 5:task 6:group 7:group 9:group" pair n tier
  for pair in $expect; do
    n=${pair%%:*}
    route docs/plan.md --task "$n"
    check "A5: review-route --task $n exits 0" "$rc" "0"
    tier=$(sed -n 's/.* review=\([a-z]*\).*/\1/p' <<<"$out")
    check "A5: Task $n is review=${pair#*:}" "$tier" "${pair#*:}"
  done
  route docs/plan.md --task 8
  check "A5: a task with no Evaluation line exits 0" "$rc" "0"
  has "A5: and prints review=task reason=unscored" "$out" "review=task reason=unscored"
  route docs/plan.md --task 4
  check "A5: a risk-2 task of total 3 is reviewed alone" "$(sed -n 's/.* review=\([a-z]*\).*/\1/p' <<<"$out")" "task"
  route docs/plan.md --task 5
  check "A5: a total-5 task of risk 0 is reviewed alone" "$(sed -n 's/.* review=\([a-z]*\).*/\1/p' <<<"$out")" "task"
  route docs/plan.md --task 3
  check "A5: a total-4 task of risk 1 is grouped" "$(sed -n 's/.* review=\([a-z]*\).*/\1/p' <<<"$out")" "group"

  # The tier does not depend on whether the Codex review surface is open.
  session true false
  route docs/plan.md --task 1
  check "A5: with the Codex review surface open a plain task is still review=group" "$(sed -n 's/.* review=\([a-z]*\).*/\1/p' <<<"$out")" "group"
  route docs/plan.md --task 2
  check "A5: and a risk-3 task is still review=task" "$(sed -n 's/.* review=\([a-z]*\).*/\1/p' <<<"$out")" "task"
  session absent

  # With several tasks the route keeps going by the highest total.
  route docs/plan.md --task 1 6
  check "A5: two light tasks route to the light judge" "$(sed -n 's/.*primary=\([^ ]*\).*/\1/p' <<<"$out")" "dforge:judge-sonnet-high"
  route docs/plan.md --task 1 5
  check "A5: a batch holding a total-5 task routes to the heavy judge" "$(sed -n 's/.*primary=\([^ ]*\).*/\1/p' <<<"$out")" "dforge:judge-opus"
}

# --- A6 ----------------------------------------------------------------------

a6() {
  new_repo a6
  local n before
  hold_task 1 a.txt
  check "A6: a grouped task is held" "$rc" "0"

  for n in 2 4 5 8; do
    ts start docs/plan.md "$n"
    commit_file "t$n.txt" "work of task $n" "feat: task $n"
    before=$(ledger_text)
    ts hold docs/plan.md "$n"
    check "A6: hold on review=task Task $n exits 4" "$rc" "4"
    check "A6: and writes no awaiting line for Task $n" "$(ledger_text | grep -c "^Task $n: awaiting group review")" "0"
    check "A6: and leaves the ledger as it was for Task $n" "$(ledger_text)" "$before"
    check "A6: and records no held head for Task $n" "$(jq -r '.heldHead // "none"' "$WS/task-$n-step.json")" "none"
  done

  ts review --group docs/plan.md 1 4
  check "A6: a group naming a review=task member exits 4" "$rc" "4"
  check "A6: and writes no group package" "$([ -e "$WS/group-1,4-review-package.md" ] && echo yes || echo no)" "no"
  check "A6: and writes no group prompt" "$([ -e "$WS/group-1,4-review-prompt.md" ] && echo yes || echo no)" "no"
  ts review --group docs/plan.md 1 3
  check "A6: a group naming a task that never started exits 4" "$rc" "4"
  has "A6: and names that task" "$err" "Task 3"
  check "A6: and writes no group state" "$([ -e "$WS/group-1,3-step.json" ] && echo yes || echo no)" "no"

  hold_task 3 c.txt
  ts review --group docs/plan.md 1 3
  check "A6: a group of two held tasks packages" "$rc" "0"
  local pkg; pkg=$(cat "$WS/group-1,3-review-package.md")
  has "A6: the package holds Task 1" "$pkg" "## Task 1"
  has "A6: the package holds Task 3" "$pkg" "## Task 3"
  lacks "A6: the package holds no Task 4" "$pkg" "## Task 4"
  lacks "A6: the package holds no Task 2" "$pkg" "## Task 2"
}

# --- A7 ----------------------------------------------------------------------

a7() {
  new_repo a7
  ts start docs/plan.md 1
  local base7; base7=$(short HEAD)
  commit_file a.txt a "feat: add a"
  local head7; head7=$(short HEAD)
  ts hold docs/plan.md 1
  check "A7: hold exits 0" "$rc" "0"
  check "A7: the ledger's last line is the awaiting line with the task's commit range" "$(ledger_text | tail -n 1)" "Task 1: awaiting group review (commits $base7..$head7)"
  has "A7: the digest says the task is held" "$out" "task 1: held for group review"

  # After a compaction only the plan and the ledger remain.
  local done_lines i
  done_lines=""
  for i in 2 3 4 5 6 7 8 9; do done_lines="${done_lines}Task $i: complete (commits aaaaaaa..bbbbbbb, review clean)"$'\n'; done
  {
    printf '# SDD ledger — plan: docs/plan.md\n'
    printf 'Task 1: implementer dforge:impl-sonnet-low (assigned; base %s)\n' "$base7"
    printf 'Task 1: awaiting group review (commits %s..%s)\n' "$base7" "$head7"
    printf '%s' "$done_lines" | grep -v '^Task 3:'
    printf 'Task 3: implementer dforge:impl-sonnet-medium (assigned; base %s)\n' "$head7"
    printf 'Task 3: awaiting group review (commits %s..%s)\n' "$head7" "$head7"
  } > "$WS/progress.md"
  out=$(cd "$R" && env -u AR_SESSION timeout 60 bash "$NEXT" docs/plan.md 2>"$TMP/err"); rc=$?
  check "A7: next-step exits 0 on a ledger with held tasks" "$rc" "0"
  has "A7: recovery sends the held tasks to the next group dispatch" "$out" "Review the held Tasks 1,3 as one group"
  lacks "A7: and does not restart Task 1" "$out" "Start at Task 1"
  lacks "A7: nor resume Task 1" "$out" "Resume at Task 1"
  lacks "A7: nor resume Task 3" "$out" "Resume at Task 3"
  has "A7: and the prompt tells the next session to write the members' complete lines" "$out" "then write their complete lines"

  local sdd delegated
  sdd=$(doc "$PLUGIN/skills/subagent-driven-development/references/ledger.md")
  delegated=$(doc "$PLUGIN/reference/delegated-task.md")
  matches "A7: the skill's recovery table reads awaiting group review as the next group dispatch" "$sdd" 'awaiting group review. \| Reviewed by the next group dispatch .* never re-dispatch its implementer'
  matches "A7: delegated-task's recovery table says the same" "$delegated" 'awaiting group review \(commits …\). \| Held: never re-dispatch its implementer'
}

# --- A8 ----------------------------------------------------------------------

a8() {
  local delegated sdd
  delegated=$(doc "$PLUGIN/reference/delegated-task.md")
  sdd=$(doc "$PLUGIN/skills/subagent-driven-development/references/process-graph.md")
  matches "A8: held tasks accumulate in sequential mode" "$delegated" 'In sequential mode held tasks accumulate'
  matches "A8: the group review runs when 4 tasks are held" "$delegated" 'runs when 4 tasks are held'
  matches "A8: and before a task review-route reviews alone is dispatched" "$delegated" 'before you dispatch a task .review-route. reviews alone'
  matches "A8: and after the plan's last task" "$delegated" 'and after the plan.s last task'
  matches "A8: once triggered no new task is dispatched until the group is clean" "$delegated" 'no new task is dispatched until the group is clean'
  matches "A8: fixes inside a group run one task at a time" "$delegated" 'fixes inside a group run one task at a time'
  matches "A8: each member gets its own complete line once the group is clean" "$delegated" 'each member gets its own .complete. line once the group is clean'
  matches "A8: the skill's flow reviews the group at 4 held, before a review=task dispatch and after the last task" "$sdd" 'review the group at 4 held, before a review=task dispatch, and after the last task'

  # Recovery: a group in its fix rounds blocks every new dispatch.
  new_repo a8
  local i
  {
    printf '# SDD ledger — plan: docs/plan.md\n'
    printf 'Task 1: awaiting group review (commits aaaaaaa..bbbbbbb)\n'
    printf 'Task 3: awaiting group review (commits bbbbbbb..ccccccc)\n'
    printf 'Group 1,3: review round 1/2 (Task 1: 1 open — x; Task 3: clean; commits ccccccc..ddddddd (Task 1))\n'
  } > "$WS/progress.md"
  out=$(cd "$R" && timeout 60 bash "$NEXT" docs/plan.md 2>"$TMP/err"); rc=$?
  has "A8: with a group in its fix rounds the next action is the group's round 2" "$out" "Run fix round 2 of Group 1,3 for Task 1"
  absent "A8: and no new task is started or resumed" "$out" '(Start|Resume) at Task'
  {
    printf '# SDD ledger — plan: docs/plan.md\n'
    printf 'Task 1: awaiting group review (commits aaaaaaa..bbbbbbb)\n'
    printf 'Task 3: awaiting group review (commits bbbbbbb..ccccccc)\n'
    printf 'Group 1,3: review round 1/2 (Task 1: clean; Task 3: clean; commits ccccccc..ddddddd (Task 1))\n'
  } > "$WS/progress.md"
  out=$(cd "$R" && timeout 60 bash "$NEXT" docs/plan.md 2>"$TMP/err"); rc=$?
  has "A8: a clean group's next action is each member's complete line" "$out" "Write the complete lines of Group 1,3's members: the group is clean."
  absent "A8: and no new task is started" "$out" '(Start|Resume) at Task'

  # Four held tasks, with more of the plan still open, take the group review before any new dispatch.
  # The next open task, Task 9, is review=group, so only the held count can send the group first.
  {
    printf '# SDD ledger — plan: docs/plan.md\n'
    for i in 1 3 6 7; do printf 'Task %s: awaiting group review (commits aaaaaaa..bbbbbbb)\n' "$i"; done
    for i in 2 4 5 8; do printf 'Task %s: complete (commits aaaaaaa..bbbbbbb, review clean)\n' "$i"; done
  } > "$WS/progress.md"
  out=$(cd "$R" && timeout 60 bash "$NEXT" docs/plan.md 2>"$TMP/err"); rc=$?
  has "A8: with 4 tasks held the next action is their group review" "$out" "Review the held Tasks 1,3,6,7 as one group"
  absent "A8: and Task 9 is not started before the group review" "$out" '(Start|Resume) at Task 9'

  # A review=task task is not dispatched while a group is held.
  {
    printf '# SDD ledger — plan: docs/plan.md\n'
    printf 'Task 1: awaiting group review (commits aaaaaaa..bbbbbbb)\n'
    printf 'Task 2: complete (commits aaaaaaa..bbbbbbb, review clean)\n'
    printf 'Task 3: complete (commits aaaaaaa..bbbbbbb, review clean)\n'
    printf 'Task 4: complete (commits aaaaaaa..bbbbbbb, review clean)\n'
  } > "$WS/progress.md"
  out=$(cd "$R" && timeout 60 bash "$NEXT" docs/plan.md 2>"$TMP/err"); rc=$?
  has "A8: with a task held and the next open task reviewed alone, the group review comes first" "$out" "Review the held Task 1"
}

# --- A9 ----------------------------------------------------------------------

section_of() { # section_of <package> <n> — the lines of "## Task <n>" up to the next "## Task"
  awk -v n="$2" '/^## Task [0-9]+( |$)/ { on = ($3 == n); next } on { print }' "$1"
}

a9() {
  new_repo a9
  hold_task 1 a.txt
  hold_task 3 c.txt
  ts review --group docs/plan.md 1 3
  check "A9: the group review exits 0" "$rc" "0"
  local pkg="$WS/group-1,3-review-package.md" s1 s3
  s1=$(section_of "$pkg" 1); s3=$(section_of "$pkg" 3)
  check "A9: the package has one section per task, labelled by number" "$(grep -c '^## Task [0-9]' "$pkg")" "2"
  has "A9: Task 1's section holds Task 1's file" "$s1" "a.txt"
  lacks "A9: Task 1's section holds no file of Task 3" "$s1" "c.txt"
  has "A9: Task 3's section holds Task 3's file" "$s3" "c.txt"
  lacks "A9: Task 3's section holds no file of Task 1, since its diff starts at its own base" "$s3" "a.txt"
  has "A9: Task 1's section names its own commit range" "$s1" "$(awk '/^Task 1: awaiting group review/ { sub(/^.*\(commits /, ""); sub(/\)$/, ""); print }' "$WS/progress.md")"

  # A wave: tasks held on their own refs, with HEAD still at the wave base.
  new_repo a9w
  local base; base=$(full HEAD)
  ts start docs/plan.md 6 --wave 1
  ts start docs/plan.md 7 --wave 1
  git -C "$R" checkout -q -b t6 "$base"; commit_file f6.txt six "feat: six"
  git -C "$R" checkout -q -b t7 "$base"; commit_file f7.txt seven "feat: seven"
  git -C "$R" checkout -q main
  ts hold docs/plan.md 6 --head t6
  check "A9: a wave task holds on its own ref" "$rc" "0"
  ts hold docs/plan.md 7 --head t7
  ts review --group docs/plan.md 6 7
  check "A9: the wave's group review exits 0 before any member merges" "$rc" "0"
  check "A9: and HEAD has not moved to any member" "$(full HEAD)" "$base"
  pkg="$WS/group-6,7-review-package.md"
  s1=$(section_of "$pkg" 6); s3=$(section_of "$pkg" 7)
  has "A9: Task 6's section holds its ref's file" "$s1" "f6.txt"
  lacks "A9: and not Task 7's" "$s1" "f7.txt"
  has "A9: Task 7's section holds its ref's file" "$s3" "f7.txt"
  lacks "A9: and not Task 6's" "$s3" "f6.txt"

  local waves
  waves=$(doc "$PLUGIN/reference/parallel-waves.md")
  matches "A9: parallel-waves dispatches the group once every grouped task in the wave is held" "$waves" 'once every grouped task in the wave is held, before any of them merges, run one .task-step review --group'
}

# --- A10 ---------------------------------------------------------------------

cockpit_rounds() { # cockpit_rounds <ledger text> — "<n>=<round>" per task the Run card tracks
  printf '%s\n' "$1" > "$TMP/cockpit-ledger.txt"
  cat > "$TMP/cockpit-check.mjs" <<EOF
import { readFileSync } from 'node:fs'
import { pathToFileURL } from 'node:url'
// The ESM loader takes a Windows drive path only as a file:// URL.
const { parseLedger } = await import(pathToFileURL('$(winpath "$PLUGIN")/hooks/cockpit/lib.ts').href)
const ledger = parseLedger(readFileSync('$(winpath "$TMP")/cockpit-ledger.txt', 'utf8'))
console.log(ledger.tasks.map(t => t.n + '=' + (t.round ?? '-')).join(' '))
EOF
  timeout 60 node --no-warnings "$TMP/cockpit-check.mjs" 2>&1
}

a10() {
  local sdd waves
  sdd=$(doc "$PLUGIN/skills/subagent-driven-development/references/ledger.md")
  waves=$(doc "$PLUGIN/reference/parallel-waves.md")
  matches "A10: the skill's ledger grammar attributes each finding clause to its task" "$sdd" 'Group <list>: review round R/2 \(Task <N>: <k> open — <one-liners> \| clean; …; commits <a7>\.\.<b7> \(Task <N>\)\[, <a7>\.\.<b7> \(Task <M>\)\]\)'
  matches "A10: parallel-waves shows the same attributed line" "$waves" 'Group <list>: review round R/2 \(Task <N>: <k> open — <one-liners> \| clean; …; commits <a7>\.\.<b7> \(Task <N>\)'
  matches "A10: the delegated-task reference puts one range per fixed member in the commits clause" "$(doc "$PLUGIN/reference/delegated-task.md")" 'one .<a7>\.\.<b7> \(Task <N>\). range per member fixed in that round'

  # next-step reads the per-task clauses: only the member with open findings is named.
  new_repo a10
  {
    printf '# SDD ledger — plan: docs/plan.md\n'
    printf 'Task 4: awaiting group review (commits aaaaaaa..bbbbbbb)\n'
    printf 'Task 6: awaiting group review (commits bbbbbbb..ccccccc)\n'
    printf 'Task 7: awaiting group review (commits ccccccc..ddddddd)\n'
    printf 'Group 4,6,7: review round 1/2 (Task 4: 1 open — meter width; Task 6: clean; Task 7: 2 open — x, y; commits ddddddd..eeeeeee (Task 4), eeeeeee..fffffff (Task 7))\n'
  } > "$WS/progress.md"
  out=$(cd "$R" && timeout 60 bash "$NEXT" docs/plan.md 2>"$TMP/err"); rc=$?
  has "A10: next-step names the open members of a comma-list Group line" "$out" "Run fix round 2 of Group 4,6,7 for Tasks 4,7"
  lacks "A10: and does not name the clean member" "$out" "Task 6,"

  # The cockpit's ledger reader gives each member its round, for a comma list and for a range.
  local got
  got=$(cockpit_rounds "$(printf '%s\n' \
    '# SDD ledger — plan: docs/plans/p.md' \
    'Task 1: implementer dforge:impl-sonnet-low (assigned; base abc1234)' \
    'Task 2: implementer dforge:impl-sonnet-low (assigned; base abc1234)' \
    'Task 3: implementer dforge:impl-sonnet-low (assigned; base abc1234)' \
    'Group 1,3: review round 1/2 (Task 1: 1 open — meter width; Task 3: clean; commits cde3456..def4567 (Task 1))')")
  check "A10: the Run card shows round 1/2 for the members of a comma-list Group line" "$got" "1=1/2 2=- 3=1/2"
  got=$(cockpit_rounds "$(printf '%s\n' \
    '# SDD ledger — plan: docs/plans/p.md' \
    'Task 4: implementer dforge:impl-sonnet-low (assigned; base abc1234)' \
    'Task 5: implementer dforge:impl-sonnet-low (assigned; base abc1234)' \
    'Task 6: implementer dforge:impl-sonnet-low (assigned; base abc1234)' \
    'Group 4-6: review round 2/2 (Task 4: clean; Task 5: 1 open — x; Task 6: clean; commits def4567..efa5678 (Task 5))')")
  check "A10: the Run card shows round 2/2 for every member of a range Group line" "$got" "4=2/2 5=2/2 6=2/2"
  got=$(cockpit_rounds "$(printf '%s\n' \
    '# SDD ledger — plan: docs/plans/p.md' \
    'Task 1: implementer dforge:impl-sonnet-low (assigned; base abc1234)' \
    'Task 3: implementer dforge:impl-sonnet-low (assigned; base abc1234)' \
    'Group 1,3: review round 1/2 (Task 1: clean; Task 3: clean; commits cde3456..def4567 (Task 1))' \
    'Task 1: complete (commits abc1234..bcd2345, review clean) — done: x; verified: y; remaining: none; discovered: none; assumptions: none')")
  check "A10: a member's complete line clears its round" "$got" "1=- 3=1/2"
}

# --- A11 ---------------------------------------------------------------------

a11() {
  new_repo a11
  ts start docs/plan.md 1
  commit_file a.txt a "feat: add a"
  ts review docs/plan.md 1
  check "A11: the first review exits 0" "$rc" "0"
  printf '%s\n\nFixed.\n' '- app.txt: a finding' > "$WS/task-1-fix-1.md"
  ts rereview docs/plan.md 1
  check "A11: fix round 1 runs" "$rc" "0"
  has "A11: and reports round 1" "$out" "re-review round 1"
  commit_file b.txt b "fix: round one"
  printf '%s\n\nFixed.\n' '- app.txt: a finding' > "$WS/task-1-fix-2.md"
  ts rereview docs/plan.md 1
  check "A11: fix round 2 runs" "$rc" "0"
  has "A11: and reports round 2" "$out" "re-review round 2"
  commit_file c.txt c "fix: round two"
  printf '%s\n\nFixed.\n' '- app.txt: a finding' > "$WS/task-1-fix-3.md"
  ts rereview docs/plan.md 1
  check "A11: a third round is refused with exit 7" "$rc" "7"
  has "A11: and the refusal names the cap of 2" "$err" "past the cap of 2"
  matches "A11: and sends the findings to the breaker" "$err" 'breaker'

  local esc delegated exec_doc
  esc=$(doc "$PLUGIN/skills/subagent-driven-development/references/escalation.md")
  delegated=$(doc "$PLUGIN/reference/delegated-task.md")
  exec_doc=$(doc "$PLUGIN/reference/executor-lane.md")
  matches "A11: round 2 is a fresh dispatch on the successor rung" "$esc" 'Fix round 2\.\*\* Dispatch a fresh implementer on the successor rung'
  matches "A11: the same rung when the successor is SPLIT" "$esc" 'the same rung when that successor is .SPLIT.'
  matches "A11: a split is reached only through the breaker's AMEND" "$esc" 'a split is reached only through the breaker.s AMEND'
  matches "A11: an executor task's round 2 leaves the lane by HANDBACK" "$esc" 'round 2 leaves the lane by .HANDBACK. instead of climbing a rung'
  matches "A11: executor-lane.md hands round 2 back to the task's Implementer" "$exec_doc" 'HANDBACK'
  matches "A11: a finding still open after round 2 goes to the breaker" "$delegated" 'A finding still open after round 2 goes to the breaker|still open after (fix )?round 2 (goes|go) to the breaker|round 2 .{0,80}(goes|go) to the breaker'
  matches "A11: the ledger's fix-round line is R/2" "$(doc "$PLUGIN/skills/subagent-driven-development/references/ledger.md")" 'Task <N>: fix round R/2'
  absent "A11: the re-review prompt no longer carries a Progress section" "$(cat "$PLUGIN/skills/subagent-driven-development/references/re-review-prompt.md")" '\*\*Progress:\*\*'
  absent "A11: nor the stall rule's progress field in the fix-round grammar" "$(doc "$PLUGIN/skills/subagent-driven-development/references/ledger.md")" 'progress [a-z-]+ -> '
}

# --- A12 ---------------------------------------------------------------------

old_ledger() { # old_ledger <file> — the real pre-spec lines, under this plan's identity line
  { printf '# SDD ledger — plan: docs/plan.md\n'; cat "$FIXTURES/faster-plans/old-ledger.md"; } > "$1"
}

gen_old_plan() { # gen_old_plan <n> — a pre-spec sequential plan of n spec-0 tasks, totals 1 to 6, no Wave check
  local i f c r t agent
  printf '%s\n' '# Old Plan' '' '**Goal:** Fixture.' '' '**Spec:** `docs/spec.md`' '' \
    '**Execution:** subagent — `claude --model sonnet --effort high` — fixture' '' \
    '**Parallelism:** sequential' '' \
    '**Plan review:** 2026-10-02 — dforge:judge-opus — executability 18 / coherence 18 / coverage 18 / assumptions 18 (round 1)' '' \
    '## Global Constraints' '' '- None.' '' '## Contracts' '' 'None' '' '## Assumptions (evidence)' '' '- None.' '' '## Task index' ''
  for i in $(seq 1 "$1"); do printf '%d. T%d\n' "$i" "$i"; done
  printf '\n'
  for i in $(seq 1 "$1"); do
    case $((i % 7)) in
      0) f=0 c=1 r=0 agent=impl-sonnet-low ;;
      1) f=1 c=1 r=0 agent=impl-sonnet-low ;;
      2) f=1 c=2 r=0 agent=impl-sonnet-medium ;;
      3) f=1 c=2 r=1 agent=impl-sonnet-medium ;;
      4) f=2 c=1 r=2 agent=impl-sonnet-high ;;
      5) f=1 c=2 r=3 agent=impl-opus-high ;;
      *) f=0 c=1 r=1 agent=impl-sonnet-low ;;
    esac
    t=$((f + c + r))
    printf '### Task %d: T%d\n\n**Files:**\n- Modify: `app.txt`\n\n**Implementer:** dforge:%s\n**Evaluation:** files %d - spec 0 - coupling %d - risk %d = %d\n\nBody.\n\n' \
      "$i" "$i" "$agent" "$f" "$c" "$r" "$t"
  done
}

a12() {
  # The cockpit still reads the older lines from a real run.
  old_ledger "$TMP/old-ledger.md"
  local got
  got=$(cockpit_rounds "$(cat "$TMP/old-ledger.md")")
  has "A12: the cockpit reads a real Task fix round 1/5 line (Task 9)" "$got" "9=1/5"
  has "A12: and another (Task 18)" "$got" "18=1/5"
  absent "A12: and a task with a complete line shows no round (Task 7)" "$got" '(^| )7=[0-9]'
  got=$(cockpit_rounds "$(printf '%s\n' \
    '# SDD ledger — plan: docs/plans/p.md' \
    'Task 4: implementer dforge:impl-sonnet-low (assigned; base abc1234)' \
    'Task 5: implementer dforge:impl-sonnet-low (assigned; base abc1234)' \
    'Group 4-5: review round 1/5 (1 addressed, 1 open — meter width; commits def4567..efa5678; resumed)')")
  check "A12: and a Group range line of an older run keeps its R/5" "$got" "4=1/5 5=1/5"

  # Task and Wave lines are read by the controller from the recovery tables.
  local sdd delegated waves
  sdd=$(doc "$PLUGIN/skills/subagent-driven-development/references/ledger.md")
  delegated=$(doc "$PLUGIN/reference/delegated-task.md")
  waves=$(doc "$PLUGIN/reference/parallel-waves.md")
  matches "A12: the skill maps R/5 on a Task, Group or Wave line: R = 1 resumes at round 2, R >= 2 goes to the breaker" "$sdd" 'A .Task., .Group. or .Wave. round line written before the two-round cap reads .R/5.: R = 1 resumes at round 2, and R >= 2 goes to the breaker'
  matches "A12: the Task recovery table resumes fix round 1/5 at round 2" "$delegated" 'fix round 1/2., or .fix round 1/5. from an older run \| Resume the loop at round 2'
  matches "A12: and sends fix round R/5 with R >= 2 to the breaker" "$delegated" 'fix round 2/2., or .fix round R/5. with R >= 2 from an older run \| Go to the breaker'
  matches "A12: the Group recovery row maps review round 1/5 to round 2" "$sdd" 'review round 1/5. from an older run \| Resume the group.s loop at round 2'
  matches "A12: and review round R/5 with R >= 2 to the breaker" "$sdd" 'review round R/5. with R >= 2 from an older run \| Go to the breaker'
  matches "A12: a Wave R/5 line follows the same rule in parallel-waves" "$waves" 'Wave <k>: fix round R/5. line: R = 1 resumes at round 2, R >= 2 goes to the breaker'
}

# --- A13 ---------------------------------------------------------------------

wave_plan() { # wave_plan <ranges> <task count> <risk-3 task or 0> <wave check line or empty>
  local i n=$2 r3=$3 risk total
  printf '%s\n' '# Wave Plan' '' '**Goal:** Fixture.' '' '**Spec:** `docs/spec.md`' '' \
    '**Execution:** subagent — `claude --model sonnet --effort high` — fixture' '' \
    "**Parallelism:** waves — $1" '' '**Integration check:** `true`' '**Worktree setup:** none'
  [ -z "$4" ] || printf '%s\n' "$4"
  printf '\n%s\n' '## Task index' ''
  for i in $(seq 1 "$n"); do printf '%d. T%d\n' "$i" "$i"; done
  printf '\n'
  for i in $(seq 1 "$n"); do
    risk=0; [ "$i" -ne "$r3" ] || risk=3
    total=$((1 + risk))
    printf '### Task %d: T%d\n\n**Files:**\n- Create: `f%d.txt`\n\n**Depends on:** none\n**Implementer:** dforge:impl-sonnet-low\n**Evaluation:** files 0 - spec 0 - coupling 1 - risk %d = %d\n\nBody.\n\n' \
      "$i" "$i" "$i" "$risk" "$total"
  done
}

due_all() { # due_all <plan> <first wave> <last wave> — "<k>:<answer>" for each wave, space separated
  local k res=""
  for k in $(seq "$2" "$3"); do
    out=$(timeout 60 bash "$WAVE" check-due "$1" "$k" 2>&1); rc=$?
    res="$res$k:$out "
  done
  printf '%s' "${res% }"
}

a13() {
  mkdir -p "$TMP/a13"
  # Ten one-task waves; Task 5 is risk 3.
  wave_plan "1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10" 10 5 '**Wave check:** `npm run build && npm run test:unit`' > "$TMP/a13/with.md"
  check "A13: every third wave, a risk-3 wave and the last run the full check; the rest the wave check" \
    "$(due_all "$TMP/a13/with.md" 1 10)" \
    "1:wave-check 2:wave-check 3:full 4:wave-check 5:full 6:full 7:wave-check 8:wave-check 9:full 10:full"
  wave_plan "1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10" 10 5 '' > "$TMP/a13/without.md"
  check "A13: without a Wave check line the other waves run none" \
    "$(due_all "$TMP/a13/without.md" 1 10)" \
    "1:none 2:none 3:full 4:none 5:full 6:full 7:none 8:none 9:full 10:full"
  # Waves are counted, not tasks: seven waves of three tasks, and the last has one.
  wave_plan "1-3 | 4-6 | 7-9 | 10-12 | 13-15 | 16-18 | 19" 19 0 '**Wave check:** `make quick`' > "$TMP/a13/wide.md"
  check "A13: waves of several tasks count by wave" \
    "$(due_all "$TMP/a13/wide.md" 1 7)" \
    "1:wave-check 2:wave-check 3:full 4:wave-check 5:wave-check 6:full 7:full"
  # A risk-3 task inside a wider wave also makes its wave full.
  wave_plan "1-2 | 3-4 | 5-6 | 7-8" 8 4 '**Wave check:** `make quick`' > "$TMP/a13/risk.md"
  check "A13: a wave holding a risk-3 task runs the full check (wave 2 holds Task 4)" \
    "$(due_all "$TMP/a13/risk.md" 1 4)" \
    "1:wave-check 2:full 3:full 4:full"
  # An older plan that adds the line through a Header amendment is read the same.
  local plan_before
  plan_before=$(cksum < "$TMP/a13/without.md")
  check "A13: check-due leaves the plan file alone" "$(cksum < "$TMP/a13/without.md")" "$plan_before"
  out=$(timeout 60 bash "$WAVE" check-due "$TMP/a13/with.md" 11 2>&1); rc=$?
  check "A13: a wave the plan lacks exits 2" "$rc" "2"
}

# --- A14 ---------------------------------------------------------------------

a14() {
  local waves sdd
  waves=$(doc "$PLUGIN/reference/parallel-waves.md")
  sdd=$(doc "$PLUGIN/skills/subagent-driven-development/references/ledger.md")
  matches "A14: a wave of one task closes like any wave" "$waves" 'A wave of one task is an ordinary task: .* and it closes by §5 like any wave'
  matches "A14: every wave closes with an integrated or a merged line, one-task and serialized waves included" "$waves" 'Every wave closes with an .integrated. or a .merged. line, one-task and serialized waves included'
  matches "A14: the ledger grammar has the merged line" "$waves" 'Wave <k>: merged \(head <sha7>; check at wave <m>\)'
  matches "A14: merged closes a wave as integrated does" "$waves" '.merged. closes a wave as .integrated. does'
  matches "A14: the skill's ledger grammar has the merged line" "$sdd" 'Wave <k>: merged \(head <sha7>; check at wave <m>\)'
  matches "A14: a merged line whose head is HEAD proves the next wave's base with nothing rerun" "$waves" 'proves the base when its head is .HEAD., or an ancestor of .HEAD. with no task commits between'
  matches "A14: and then nothing reruns" "$waves" 'Then nothing reruns'
  matches "A14: a wave of one task runs the base proof only, then the task loop" "$waves" 'For a wave of one task, run step 2 only, then the task loop in the checkout'
  matches "A14: the next wave starts on a closing line" "$waves" 'every earlier wave closed by its .integrated. or .merged. line'
}

# --- A15 ---------------------------------------------------------------------

a15() {
  local waves
  waves=$(doc "$PLUGIN/reference/parallel-waves.md")
  matches "A15: the base proof writes its failing test names to base-proof-failures.txt" "$waves" 'writes .<workspace>/base-proof-failures.txt.'
  matches "A15: a failing check whose lines all appear in the file counts as passing" "$waves" 'A failing check whose failing lines, taken as in §1, all appear in .<workspace>/base-proof-failures.txt. counts as passing'
  matches "A15: a full check is then logged integrated with baseline failures only" "$waves" 'Wave <k>: integrated \(head <sha7>; <command> → pass; baseline failures only\)'
  matches "A15: the comparison is a subset test" "$waves" 'the failures are a subset when'
  matches "A15: a new failure logs check failed and runs the fix loop" "$waves" 'any other failure logs .Wave <k>: check failed'
  matches "A15: the fix dispatch gets every task diff since the last passing check" "$waves" 'The fix dispatch gets every task diff since the last passing check, the last .Wave <j>: integrated. line'
  matches "A15: the diff runs from that line's head to HEAD through review-package" "$waves" 'review-package PLAN_FILE <its head> HEAD'
  matches "A15: from the first wave's base when there is no passing check" "$waves" 'from the first wave.s base when there is none'
  matches "A15: the skill's ledger grammar has the baseline clause" "$(doc "$PLUGIN/skills/subagent-driven-development/references/ledger.md")" 'Wave <k>: integrated \(head <sha7>; <command> → pass\[; baseline failures only\]\)'
}

# --- A16 ---------------------------------------------------------------------

a16() {
  local waves
  waves=$(doc "$PLUGIN/reference/parallel-waves.md")
  matches "A16: a merged or integrated line proves the base when its sha is an ancestor of HEAD" "$waves" 'git merge-base --is-ancestor <sha7> HEAD. holds'
  matches "A16: with only bookkeeping commits between" "$waves" 'every commit .git log --format=.%h %s. --name-only <sha7>\.\.HEAD. lists is your own bookkeeping'
  matches "A16: bookkeeping is the ledger, amendments, a register or the roadmap" "$waves" 'bookkeeping \(the ledger, amendments, a register or the roadmap; no path any task.s .\*\*Files:\*\*. names\)'
  matches "A16: and then nothing reruns" "$waves" 'Then nothing reruns'
  matches "A16: only a task commit outside any wave forces the fallback proof" "$waves" 'Only a task commit outside any wave forces the fallback proof'
  matches "A16: the fallback is the Wave check, else the full Integration check" "$waves" 'the header.s Wave check \(amendments applied\) when it has one, else the full Integration check'
  matches "A16: a ledger with no closing line yet proves its base with the full check" "$waves" 'With no closing line yet \(the first wave\), the proof is the full check'
}

# --- A17 ---------------------------------------------------------------------

a17() {
  gen_plan "" "0 0 1 0 sonnet-low" "2 2 1 3 opus-high" > "$LINTDIR/pr.md"
  out=$(cd "$LINTDIR" && timeout 60 bash "$ROUTE" pr.md --plan-round 1 2>&1); rc=$?
  check "A17: plan review round 1 routes" "$rc" "0"
  has "A17: and prints a cap of 2 though a task totals 8" "$out" "cap=2"
  out=$(cd "$LINTDIR" && timeout 60 bash "$ROUTE" pr.md --plan-round 2 2>&1); rc=$?
  check "A17: plan review round 2 routes" "$rc" "0"
  has "A17: and prints a cap of 2" "$out" "cap=2"
  out=$(cd "$LINTDIR" && timeout 60 bash "$ROUTE" pr.md --plan-round 3 2>&1); rc=$?
  check "A17: plan review round 3 is refused" "$rc" "2"
  has "A17: and the refusal names the cap" "$out" "past the cap (2)"
  gen_plan "" "0 0 1 0 sonnet-low" > "$LINTDIR/pr-light.md"
  out=$(cd "$LINTDIR" && timeout 60 bash "$ROUTE" pr-light.md --plan-round 3 2>&1); rc=$?
  check "A17: a plan of light tasks is capped at 2 as well" "$rc" "2"

  local wp bs ar
  wp=$(doc "$PLUGIN/skills/writing-plans/SKILL.md")
  bs=$(doc "$PLUGIN/skills/brainstorming/SKILL.md")
  ar=$(doc "$PLUGIN/reference/auto-run.md")
  matches "A17: the next plan-review round runs only on a Critical finding or a score of 8 or below" "$wp" 'Run the next round only when a round returned a Critical finding or any score of 8 or below'
  matches "A17: on a Claude plan the cap is 2 and there is no third" "$wp" 'On a Claude plan the cap is 2 whatever the task totals: round 2 is the delta round, and there is no third'
  matches "A17: the Fable spec review runs one round" "$ar" 'Fable runs one round'
  matches "A17: a second only when round 1 leaves a Blocker or High finding open" "$ar" 'A second runs only when round 1 leaves a Blocker or High finding open'
  matches "A17: and checks only those answers" "$ar" 'checks only those answers'
  matches "A17: brainstorming caps the Fable spec review at two rounds" "$bs" 'Fable spec review.{0,10}\(at most two rounds\)|at most two rounds'
  matches "A17: brainstorming runs the second round only for a Blocker or High left open" "$bs" 'Blocker or High'
}

# --- A18 ---------------------------------------------------------------------

a18() {
  local agent text
  for agent in judge-opus judge-sonnet-high judge-fable; do
    text=$(sed -n 's/^tools: //p' "$PLUGIN/agents/$agent.md" | tr -d '\r')
    matches "A18: agents/$agent.md lists Write" "$text" '(^|, )Write(,|$)'
  done

  local t name text1 findings
  # template path | findings in its report (yes/no)
  for t in \
    "skills/subagent-driven-development/references/task-reviewer-prompt.md|yes" \
    "skills/subagent-driven-development/references/group-reviewer-prompt.md|yes" \
    "skills/subagent-driven-development/references/re-review-prompt.md|yes" \
    "skills/subagent-driven-development/references/ruling-prompt.md|no" \
    "skills/writing-plans/references/plan-reviewer-prompt.md|yes" \
    "skills/brainstorming/references/architecture-critic-prompt.md|yes" \
    "skills/requesting-code-review/references/code-reviewer.md|yes" \
    "skills/closing-a-milestone/references/milestone-judge.md|no" \
    "skills/distilling-docs/references/distil-judge.md|no"; do
    name=${t%%|*}; findings=${t##*|}
    text=$(cat "$PLUGIN/$name")
    matches "A18: $(basename "$name") names the report file" "$text" '\[REPORT_FILE\]|Report file:.*-report\.md'
    matches "A18: $(basename "$name") fixes the ## Verdict section" "$text" '^ *## Verdict'
    matches "A18: $(basename "$name") limits the final message to 10 lines" "$(doc "$PLUGIN/$name")" 'at most 10 lines'
    if [ "$findings" = yes ]; then
      matches "A18: $(basename "$name") fixes the finding-line grammar" "$text" '- \[[A-Za-z|]+\] (\(Task <N>\) )?<file>:<line> — <one-liner>'
    fi
  done

  # The final review and its dedupe are dispatched from final-review.md.
  text=$(doc "$PLUGIN/reference/final-review.md")
  matches "A18: final-review.md names the final review's report file" "$text" '\[REPORT_FILE\]. set to .<workspace>/final-review-report.md'
  matches "A18: and the dedupe's report file" "$text" 'final-dedupe-report.md'
  matches "A18: and limits both to 10 lines" "$text" 'write nothing else, and reply in at most 10 lines'

  # The spec lists acceptance QA among the judge prompt templates.
  text=$(cat "$PLUGIN/reference/acceptance-qa.md")
  matches "A18: acceptance-qa.md names a report file" "$text" '\[REPORT_FILE\]|acceptance-report\.md'
  matches "A18: acceptance-qa.md fixes a ## Verdict section" "$text" '^ *## Verdict'
  matches "A18: acceptance-qa.md limits the final message to 10 lines" "$(doc "$PLUGIN/reference/acceptance-qa.md")" 'at most 10 lines'
}

# --- A19 / A20 ---------------------------------------------------------------

REPORT_HEAD='## Verdict
spec: fail
quality: changes
scores: spec 9 / scope 15 / verification 11 / quality 10

## Strengths
The tests are focused.

## Findings
- [Critical] app.txt:3 — the first finding about the paging
  detail of the first finding
- [Important] other.txt:7 — the second finding about the filter
- [Important] test.txt:0 — the third finding has no single line
- [Minor] app.txt:9 — a minor note kept out of the fix loop

## Cannot verify'

write_report() { # write_report <file> <cannot-verify count>
  { printf '%s\n' "$REPORT_HEAD"; local i; for i in $(seq 1 "$2"); do printf -- '- cannot-verify item number %s, to be checked by the controller\n' "$i"; done; printf '\n## Assessment\nNeeds fixes.\n'; } > "$1"
}

review_ready() { # review_ready <repo name> — a repo with Task 1 started, committed and reviewed
  new_repo "$1"
  ts start docs/plan.md 1
  commit_file a.txt a "feat: add a"
  ts review docs/plan.md 1
}

a19() {
  review_ready a19
  check "A19: the review step ran" "$rc" "0"
  write_report "$WS/task-1-review-report.md" 30
  ts verdict docs/plan.md 1
  check "A19: verdict exits 0 on a well-formed report" "$rc" "0"
  local n
  n=$(lines_of "$out")
  check "A19: the digest is at most 20 lines plus one per Critical or Important finding (3 here)" "$([ "$n" -le 23 ] && echo yes || echo no)" "yes"
  matches "A19: the digest counts the findings by severity" "$out" '^findings: 1 Critical, 2 Important, 1 Minor'
  has "A19: it prints the Critical finding with its file and line" "$out" "Critical 1 app.txt:3 — the first finding about the paging"
  has "A19: it prints the first Important finding" "$out" "Important 1 other.txt:7 — the second finding about the filter"
  has "A19: it prints the Important finding with no single line" "$out" "Important 1 test.txt:0 — the third finding has no single line"
  lacks "A19: it prints no line for the Minor finding" "$(grep -E '^(Critical|Important|Minor) ' <<<"$out")" "a minor note"
  has "A19: it reads the verdict lines from the report" "$out" "spec: fail"
  has "A19: and the scores" "$out" "scores: spec 9 / scope 15 / verification 11 / quality 10"
  has "A19: it cuts the cannot-verify list instead of printing all 30" "$out" "more in the report"
  local fix="$WS/task-1-fix-1.md"
  check "A19: it writes the next fix file" "$([ -f "$fix" ] && echo yes || echo no)" "yes"
  has "A19: the digest names the fix file" "$out" "$fix"
  local fixtext; fixtext=$(cat "$fix" 2>/dev/null)
  has "A19: the fix file carries the Critical finding" "$fixtext" "the first finding about the paging"
  has "A19: and the first Important finding" "$fixtext" "the second finding about the filter"
  has "A19: and the second Important finding" "$fixtext" "the third finding has no single line"
  lacks "A19: and not the Minor finding" "$fixtext" "a minor note"
  matches "A19: the fix file begins with one bullet per finding, each naming its file" "$(head -n 3 "$fix" 2>/dev/null)" '^- (app\.txt:3|other\.txt:7|test\.txt): '
}

a20() {
  review_ready a20
  # The report is missing.
  ts verdict docs/plan.md 1
  check "A20: a missing report exits non-zero" "$([ "$rc" -ne 0 ] && echo yes || echo no)" "yes"
  has "A20: and names the report file" "$err" "task-1-review-report.md"
  check "A20: and writes no fix file" "$([ -e "$WS/task-1-fix-1.md" ] && echo yes || echo no)" "no"

  write_report "$WS/task-1-review-report.md" 2
  ts verdict docs/plan.md 1
  check "A20: with the report written and nothing changed, verdict exits 0" "$rc" "0"
  has "A20: and the check line says the tracked files are clean" "$out" "check tracked: clean"

  # A judge edits a tracked file during the review.
  review_ready a20b
  write_report "$WS/task-1-review-report.md" 2
  printf 'judge edit\n' >> "$R/app.txt"
  ts verdict docs/plan.md 1
  check "A20: a tracked file changed during the review exits non-zero" "$([ "$rc" -ne 0 ] && echo yes || echo no)" "yes"
  has "A20: and the message names the changed file" "$err" "app.txt"
  check "A20: and writes no fix file" "$([ -e "$WS/task-1-fix-1.md" ] && echo yes || echo no)" "no"
  git -C "$R" checkout -- app.txt
  ts verdict docs/plan.md 1
  check "A20: once the file is restored verdict goes through" "$rc" "0"

  # A tracked file that was already modified when the review began is not a change.
  new_repo a20c
  ts start docs/plan.md 1
  commit_file a.txt a "feat: add a"
  printf 'dirty before the review\n' >> "$R/other.txt"
  ts review docs/plan.md 1
  write_report "$WS/task-1-review-report.md" 2
  ts verdict docs/plan.md 1
  check "A20: an edit made before the review began is not flagged" "$rc" "0"
  printf 'and again during\n' >> "$R/other.txt"
  ts verdict docs/plan.md 1
  check "A20: a further edit of that file during the review is flagged" "$([ "$rc" -ne 0 ] && echo yes || echo no)" "yes"
  has "A20: and names it" "$err" "other.txt"

  # A new commit during the review also counts.
  review_ready a20d
  write_report "$WS/task-1-review-report.md" 2
  commit_file sneaky.txt x "feat: judge commit"
  ts verdict docs/plan.md 1
  check "A20: a commit made during the review exits non-zero" "$([ "$rc" -ne 0 ] && echo yes || echo no)" "yes"
  has "A20: and names the file it changed" "$err" "sneaky.txt"
}

# --- A21 ---------------------------------------------------------------------

AMEND_PLAN='|# Demo Implementation Plan
|
|**Goal:** Demo.
|
|**Spec:** `docs/spec.md`
|
|**Execution:** subagent — `claude --model sonnet --effort high` — Task 2 scores 4
|
|## Global Constraints
|
|- Bash only.
|
|## Contracts
|
|- `greet NAME` prints `hello NAME`.
|
|## Assumptions (evidence)
|
|- None.
|
|## Task index
|
|1. First thing
|2. Second thing
|
|### Task 1: First thing
|
|**Files:**
|- Create: `a.sh`
|
|**Implementer:** dforge:impl-sonnet-low
|**Evaluation:** files 0 - spec 0 - coupling 1 - risk 0 = 1
|
|Print `hello NAME`.
|
|### Task 2: Second thing
|
|**Files:**
|- Modify: `a.sh`
|
|**Implementer:** dforge:impl-sonnet-medium
|**Evaluation:** files 0 - spec 1 - coupling 1 - risk 2 = 4
|
|Print `hello NAME` twice.'

amend_repo() { # amend_repo <name> — a repository with the demo plan; sets R and AWS
  R="$TMP/$1"
  git init -q -b main "$R"
  git -C "$R" config user.name Darkraise
  git -C "$R" config user.email dark@example.invalid
  mkdir -p "$R/docs"
  printf '# Spec\n' > "$R/docs/spec.md"
  sed 's/^|//' <<<"$AMEND_PLAN" > "$R/docs/plan.md"
  git -C "$R" add -A && git -C "$R" commit -qm init
  AWS=$(winpath "$(cd "$R" && bash "$S/sdd-workspace" docs/plan.md)")
}

amend() { out=$(cd "$R" && timeout 60 bash "$AMEND" "$@" 2>&1); rc=$?; }

a21() {
  local hand="$TMP/a21-hand.md" report="$TMP/a21-report.md"
  printf '%s\n' '## A? — Task 2' 'Reason: the plan says the wrong thing' 'Cost if wrong: one fix round' \
    '### Old' '````text' 'Print `hello NAME` twice.' '````' '### New' '````text' 'Print `hello NAME` three times.' '````' > "$hand"
  {
    printf '%s\n' '## Verdict' 'Verdict: AMEND' 'Ruling: the plan is wrong about the count' '' \
      '## A1 — Task 2' 'Reason: the plan says the wrong thing' 'Cost if wrong: one fix round' \
      '### Old' '````text' 'Print `hello NAME` twice.' '````' '### New' '````text' 'Print `hello NAME` three times.' '````' '' \
      'Trailing text that is not part of the entry.' '' \
      '## A2 — Header' 'Reason: another one' 'Cost if wrong: none' \
      '### Old' '````text' '- Bash only.' '````' '### New' '````text' '- Bash 4 or later.' '````' '' '## Notes' 'Nothing else.'
  } > "$report"

  amend_repo a21a
  amend docs/plan.md "$hand"
  local hand_out=$out hand_rc=$rc hand_ledger
  hand_ledger=$(cat "$AWS/amendments.md" 2>/dev/null)
  check "A21: the hand-copied block applies" "$hand_rc" "0"
  check "A21: and prints the amended line" "$hand_out" "amended: A1 Task 2"

  amend_repo a21b
  amend docs/plan.md --report "$report" --id A1
  check "A21: the report's entry applies" "$rc" "0"
  check "A21: and prints the same amended line" "$out" "$hand_out"
  check "A21: and amendments.md matches the hand-copied one byte for byte" "$(cat "$AWS/amendments.md" 2>/dev/null)" "$hand_ledger"
  absent "A21: nothing after the New fence is taken" "$(cat "$AWS/amendments.md")" 'Trailing text|^## Notes|^Verdict:|^Ruling:|another one'

  amend docs/plan.md --id A2 --report "$report"
  check "A21: a later entry of the same report applies with the flags in either order" "$out" "amended: A2 Header"
  has "A21: and carries its own text" "$(cat "$AWS/amendments.md")" "Bash 4 or later."
  amend docs/plan.md --report "$report" --id A9
  check "A21: an id the report lacks is rejected" "$rc" "1"
  amend docs/plan.md --report "$TMP/no-such-report.md" --id A1
  check "A21: a report file that does not exist exits 2" "$rc" "2"
}

# --- A22 ---------------------------------------------------------------------

a22() {
  local plan sum_before sum_after
  # The real plans written before this spec lint clean, unedited.
  for plan in 2026-10-24-ui-ux-skill 2026-10-25-typed-seats-and-drafting 2026-10-26-task-loop-steps; do
    sum_before=$(cksum < "$REPO_ROOT/docs/dforge/plans/$plan.md")
    out=$(cd "$REPO_ROOT" && timeout 120 bash "$LINT" "docs/dforge/plans/$plan.md" --no-probe 2>&1); rc=$?
    check "A22: plan-lint passes the pre-spec plan $plan" "$rc" "0"
    matches "A22: and reports no error for $plan" "$out" 'plan-lint: 0 errors'
    check "A22: and leaves $plan as it was" "$(cksum < "$REPO_ROOT/docs/dforge/plans/$plan.md")" "$sum_before"
    check "A22: and git sees no edit to $plan" "$(git -C "$REPO_ROOT" status --porcelain -- "docs/dforge/plans/$plan.md" | grep -c .)" "0"
  done

  # An old waves plan (no Wave check line) under the new cadence.
  local old="$REPO_ROOT/docs/dforge/plans/2026-10-25-typed-seats-and-drafting.md"
  absent "A22: the old waves plan carries no Wave check line" "$(cat "$old")" '^\*\*Wave check:\*\*'
  check "A22: its waves run the full check on the cadence and nothing between" \
    "$(due_all "$old" 1 3)" "1:none 2:none 3:full"

  # An old plan with spec-0 tasks up to total 6, run through §2 and the task loop, plan file untouched.
  new_repo a22
  gen_old_plan 20 > "$R/docs/old-plan.md"
  printf '# Spec\n' > "$R/docs/spec.md"
  git -C "$R" add -A && git -C "$R" commit -qm "docs: add old plan"
  sum_before=$(cksum < "$R/docs/old-plan.md")
  out=$(cd "$R" && timeout 120 bash "$LINT" docs/old-plan.md --no-probe 2>&1); rc=$?
  matches "A22: a pre-spec plan of spec-0 tasks lints clean" "$out" 'plan-lint: 0 errors'
  check "A22: and plan-lint exits 0 on it" "$rc" "0"
  local n tier ok=1
  for n in 1 2 3 4 5 6; do
    route docs/old-plan.md --task "$n"
    [ "$rc" -eq 0 ] && grep -qE ' review=(task|group) ' <<<"$out" || ok=0
  done
  check "A22: review-route gives every old task a tier" "$ok" "1"
  WS=$(winpath "$(cd "$R" && bash "$S/sdd-workspace" docs/old-plan.md)")
  ts start docs/old-plan.md 1
  check "A22: task-step starts an old task" "$rc" "0"
  commit_file a.txt a "feat: a"
  ts hold docs/old-plan.md 1
  check "A22: task-step holds an old grouped task" "$rc" "0"
  ts start docs/old-plan.md 2
  commit_file b.txt b "feat: b"
  ts hold docs/old-plan.md 2
  ts review --group docs/old-plan.md 1 2
  check "A22: task-step reviews two old tasks as a group" "$rc" "0"
  ts start docs/old-plan.md 4
  commit_file c.txt c "feat: c"
  ts hold docs/old-plan.md 4
  check "A22: and reviews an old risk-2 task alone" "$rc" "4"
  # The ledger of an older run, cut from a real one, reads under the new rules.
  old_ledger "$WS/progress.md"
  out=$(cd "$R" && timeout 60 bash "$NEXT" docs/old-plan.md 2>"$TMP/err"); rc=$?
  check "A22: next-step reads an older ledger with fix round R/5 lines" "$rc" "0"
  has "A22: and names its next action" "$out" "**Next:**"
  check "A22: no step edited the plan file" "$(cksum < "$R/docs/old-plan.md")" "$sum_before"
  check "A22: and git sees the plan unmodified" "$(git -C "$R" status --porcelain -- docs/old-plan.md | grep -c .)" "0"
  check "A22: the old ledger keeps its R/5 lines" "$(grep -c 'fix round 1/5' "$WS/progress.md")" "$(grep -c 'fix round 1/5' "$FIXTURES/faster-plans/old-ledger.md")"
}

# --- A23 ---------------------------------------------------------------------

a23() {
  gen_codex_plan "1 1 1 0 gpt-6.1-sol/low" "2 1 1 0 gpt-6.1-sol/medium" > "$LINTDIR/x-two.md"
  lint x-two.md
  check "A23: a Host: codex plan with a task at files+spec+coupling 4 fails plan-lint" "$rc" "1"
  matches "A23: Rule S is at 4, on Task 2 and not Task 1" "$out" 'ERROR Task 2: Rule S: files\+spec\+coupling must be below 4'
  absent "A23: and Task 1 at 3 draws none" "$out" 'ERROR Task 1: Rule S'

  # Per-task review: review-route and task-step do not take a Codex-host plan.
  new_repo a23
  local before
  before=$(ls -A "$R/.dforge" 2>/dev/null | sort | tr '\n' ' ')
  route docs/codex-plan.md --task 1
  check "A23: review-route --task on a Host: codex plan exits 2" "$rc" "2"
  has "A23: and sends the review to the native Codex reference" "$err" "native-codex.md"
  lacks "A23: and prints no group tier" "$out" "review=group"
  local sub
  for sub in "start docs/codex-plan.md 1" "review docs/codex-plan.md 1" "hold docs/codex-plan.md 1" "review --group docs/codex-plan.md 1 2" "rereview docs/codex-plan.md 1"; do
    ts $sub
    check "A23: task-step $sub exits 2" "$rc" "2"
  done
  check "A23: no task-step subcommand wrote workspace state for the Codex plan" "$(ls -A "$R/.dforge" 2>/dev/null | sort | tr '\n' ' ')" "$before"

  # Five fix rounds.
  check "A23: the Codex routing policy keeps review_cap 5" "$(jq -r '.review_cap' < "$PLUGIN/reference/codex-routing.json" | tr -d '\r')" "5"
  local nc delegated sdd lad
  nc=$(doc "$PLUGIN/reference/native-codex.md")
  delegated=$(doc "$PLUGIN/reference/delegated-task.md")
  sdd=$(doc "$PLUGIN/skills/subagent-driven-development/references/ledger.md")
  lad=$(doc "$PLUGIN/reference/ladder.md")
  matches "A23: native-codex.md preserves the five-round review cap" "$nc" 'the five-round review cap'
  matches "A23: delegated-task.md keeps five rounds on a Host: codex plan" "$delegated" 'On a .Host: codex. plan the loop keeps five rounds'
  matches "A23: and the Codex ledger line is fix round R/5" "$delegated" 'Task <N>: fix round <R>/5'
  matches "A23: the Codex recovery row reads fix round R/5 as live" "$delegated" '.fix round R/5. on a .Host: codex. plan \| Codex: R < 5 resumes the loop at round R\+1'
  matches "A23: the skill reads a Codex R/5 line as live, not older" "$sdd" 'On a .Host: codex. plan a .Task. or .Wave. round line reading .R/5. is live, not older'
  matches "A23: native-codex.md keeps Rule S at 4 for the Codex score" "$nc" 'Apply Rule S first: files \+ spec \+ coupling must be'
  matches "A23: the ladder keeps the Codex carve-out at reducible >= 4" "$lad" 'Host: codex. plan keeps .reducible >= 4.|keeps .reducible >= 4.'
  matches "A23: writing-plans keeps code-given tasks on a Codex host" "$(doc "$PLUGIN/skills/writing-plans/SKILL.md")" 'On a Codex host, tasks keep the code-given shape'
}

ALL="a1 a2 a3 a4 a5 a6 a7 a8 a9 a10 a11 a12 a13 a14 a15 a16 a17 a18 a19 a20 a21 a22 a23"
if [ $# -gt 0 ]; then
  sel=""
  for n in "$@"; do sel="$sel $(tr 'A-Z' 'a-z' <<<"$n")"; done
else
  sel=$ALL
fi
for t in $sel; do "$t"; done

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
