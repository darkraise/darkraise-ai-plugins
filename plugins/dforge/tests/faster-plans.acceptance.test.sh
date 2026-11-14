#!/usr/bin/env bash
# Acceptance tests for the faster-plans spec
# (docs/dforge/specs/2026-10-26-faster-plans-design.md), statements A2-A5,
# A11, A12 and A17-A23. Each test is written from the statement's text and reaches the
# behaviour through the scripts and documents the spec names: plan-lint,
# review-route, task-step, next-step, plan-amend, the
# cockpit's ledger reader, the agent definitions and the shipped prompts and
# references.
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
printf '%s\n' '#!/usr/bin/env bash' 'echo "codex-gate usable=true reason= review=true resets_at=- source=cache"' > "$TMP/gate-stub"
export TASK_STEP_CODEX_GATE="$TMP/gate-stub"

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

PLAN_TEXT='|# Faster Plans Acceptance Fixture
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
|1. light one
|2. risk three
|3. light two
|4. risk two
|5. total five
|6. light three
|7. light four
|8. unscored
|9. light five
|
|### Task 1: light one
|
|**Files:**
|- Modify: `app.txt`
|
|**Implementer:** dforge:impl-sonnet-high
|**Evaluation:** files 0 - spec 0 - coupling 1 - risk 0 = 1
|
|Body.
|
|### Task 2: risk three
|
|**Files:**
|- Modify: `app.txt`
|
|**Implementer:** dforge:impl-sonnet-high
|**Evaluation:** files 1 - spec 2 - coupling 1 - risk 3 = 7
|
|### Task 3: light two
|
|**Files:**
|- Modify: `other.txt`
|
|**Implementer:** dforge:impl-sonnet-high
|**Evaluation:** files 1 - spec 1 - coupling 1 - risk 1 = 4
|
|### Task 4: risk two
|
|**Files:**
|- Modify: `app.txt`
|
|**Implementer:** dforge:impl-sonnet-high
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
|### Task 6: light three
|
|**Files:**
|- Modify: `app.txt`
|
|**Implementer:** dforge:impl-sonnet-high
|**Evaluation:** files 0 - spec 0 - coupling 1 - risk 1 = 2
|
|### Task 7: light four
|
|**Files:**
|- Modify: `other.txt`
|
|**Implementer:** dforge:impl-sonnet-high
|**Evaluation:** files 0 - spec 1 - coupling 1 - risk 0 = 2
|
|### Task 8: unscored
|
|**Files:**
|- Modify: `other.txt`
|
|**Implementer:** dforge:impl-sonnet-high
|
|### Task 9: light five
|
|**Files:**
|- Modify: `other.txt`
|
|**Implementer:** dforge:impl-sonnet-high
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

# --- fixtures: plan-lint plans ---------------------------------------------

LINTDIR="$TMP/lint"
mkdir -p "$LINTDIR/docs"
printf '# Spec\n' > "$LINTDIR/docs/spec.md"

gen_plan() { # gen_plan <extra header line or empty> <"F S C R impl[~label line...]">... — a Claude plan
  local extra=$1 i=0 spec f s c r impl more
  shift
  printf '%s\n' '# Gen Plan' '' '**Goal:** Fixture.' '' '**Spec:** `docs/spec.md`' '' \
    '**Execution:** inline — `claude --model sonnet --effort high` — fixture' ''
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
    '**Execution:** inline — codex gpt-6.1-sol / high — native pair' '' \
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
  out=$(cd "$LINTDIR" && timeout 120 bash "$LINT" "$@" 2>&1); rc=$?
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
  local want="0:sonnet/low 1:sonnet/low 2:sonnet/low 3:sonnet/medium 4:sonnet/medium 5:sonnet/high 6:opus/high 7:opus/high 8:opus/high"
  local got
  got=$(awk '$0 == "```assignment" { f = 1; next } f && $0 == "```" { exit } f && NF { printf "%s%s:%s/%s", sep, $1, $2, $3; sep = " " }' "$PLUGIN/reference/ladder.md")
  check "A3: totals 0-5 floor on sonnet, 6-8 on opus" "$got" "$want"
}

# --- A4 ----------------------------------------------------------------------

a4() {
  local ext='> **External executors:** codex' base="0 0 1 0 sonnet-low" i
  # Any total the session's sonnet pair covers: the line is only obsolete.
  local specs=("1 1 1 1 sonnet-medium" "2 2 1 0 sonnet-high")
  for i in 0 1; do
    gen_plan "$ext" "$base" "${specs[$i]}~**Executor:** codex gpt-6.1-sol / high" > "$LINTDIR/l4.md"
    lint l4.md
    has "A4: an Executor line on a ${specs[$i]% *} task is a warning" "$out" \
      "WARN Task 2: the **Executor:** line is obsolete; the session implements this task"
    check "A4: and the plan lints without errors (${specs[$i]% *})" "$rc" "0"
  done
}

# --- A5 ----------------------------------------------------------------------

a5() {
  new_repo a5
  route docs/plan.md --task 8
  check "A5: a task with no Evaluation line exits 0" "$rc" "0"
  has "A5: and prints reason=unscored" "$out" "reason=unscored"

  # With several tasks the route keeps going by the highest total.
  route docs/plan.md --task 1 6
  check "A5: two light tasks route to the light judge" "$(sed -n 's/.*primary=\([^ ]*\).*/\1/p' <<<"$out")" "dforge:judge-sonnet-high"
  route docs/plan.md --task 1 5
  check "A5: a batch holding a total-5 task stays on the light judge" "$(sed -n 's/.*primary=\([^ ]*\).*/\1/p' <<<"$out")" "dforge:judge-sonnet-high"
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
}

# --- A12 ---------------------------------------------------------------------

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

old_ledger() { # old_ledger <file> — the real pre-spec lines, under this plan's identity line
  { printf '# SDD ledger — plan: docs/plan.md\n'; cat "$FIXTURES/faster-plans/old-ledger.md"; } > "$1"
}

gen_old_plan() { # gen_old_plan <n> — a pre-spec sequential plan of n spec-0 tasks, totals 1 to 6
  local i f c r t agent
  printf '%s\n' '# Old Plan' '' '**Goal:** Fixture.' '' '**Spec:** `docs/spec.md`' '' \
    '**Execution:** inline — `claude --model opus --effort high` — fixture' '' \
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
    "reference/prompts/task-reviewer-prompt.md|yes" \
    "reference/prompts/re-review-prompt.md|yes"; do
    name=${t%%|*}; findings=${t##*|}
    text=$(cat "$PLUGIN/$name")
    matches "A18: $(basename "$name") names the report file" "$text" '\[REPORT_FILE\]|Report file:.*-report\.md'
    matches "A18: $(basename "$name") fixes the ## Verdict section" "$text" '^ *## Verdict'
    if [ "$findings" = yes ]; then
      matches "A18: $(basename "$name") fixes the finding-line grammar" "$text" '- \[[A-Za-z|]+\] (\(Task <N>\) )?<file>:<line> — <one-liner>'
    fi
  done
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
|**Execution:** inline — `claude --model sonnet --effort high` — Task 2 scores 4
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
|**Implementer:** dforge:impl-sonnet-high
|**Evaluation:** files 0 - spec 0 - coupling 1 - risk 0 = 1
|
|Print `hello NAME`.
|
|### Task 2: Second thing
|
|**Files:**
|- Modify: `a.sh`
|
|**Implementer:** dforge:impl-sonnet-high
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
  for plan in 2026-10-24-ui-ux-skill 2026-10-26-task-loop-steps; do
    sum_before=$(cksum < "$REPO_ROOT/docs/dforge/plans/$plan.md")
    out=$(cd "$REPO_ROOT" && timeout 120 bash "$LINT" "docs/dforge/plans/$plan.md" 2>&1); rc=$?
    check "A22: plan-lint passes the pre-spec plan $plan" "$rc" "0"
    matches "A22: and reports no error for $plan" "$out" 'plan-lint: 0 errors'
    check "A22: and leaves $plan as it was" "$(cksum < "$REPO_ROOT/docs/dforge/plans/$plan.md")" "$sum_before"
    check "A22: and git sees no edit to $plan" "$(git -C "$REPO_ROOT" status --porcelain -- "docs/dforge/plans/$plan.md" | grep -c .)" "0"
  done

  # An old plan with spec-0 tasks up to total 6, run through §2 and the task loop, plan file untouched.
  new_repo a22
  gen_old_plan 20 > "$R/docs/old-plan.md"
  printf '# Spec\n' > "$R/docs/spec.md"
  git -C "$R" add -A && git -C "$R" commit -qm "docs: add old plan"
  sum_before=$(cksum < "$R/docs/old-plan.md")
  out=$(cd "$R" && timeout 120 bash "$LINT" docs/old-plan.md 2>&1); rc=$?
  matches "A22: a pre-spec plan of spec-0 tasks lints clean" "$out" 'plan-lint: 0 errors'
  check "A22: and plan-lint exits 0 on it" "$rc" "0"
  local n tier ok=1
  for n in 1 2 3 4 5 6; do
    route docs/old-plan.md --task "$n"
    [ "$rc" -eq 0 ] && grep -qE ' primary=[^ ]+ ' <<<"$out" || ok=0
  done
  check "A22: review-route gives every old task a seat" "$ok" "1"
  WS=$(winpath "$(cd "$R" && bash "$S/sdd-workspace" docs/old-plan.md)")
  ts start docs/old-plan.md 1
  check "A22: task-step starts an old task" "$rc" "0"
  commit_file a.txt a "feat: a"
  ts review docs/old-plan.md 1
  check "A22: task-step reviews an old task" "$rc" "0"
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
  local sub
  for sub in "start docs/codex-plan.md 1" "review docs/codex-plan.md 1" "rereview docs/codex-plan.md 1"; do
    ts $sub
    check "A23: task-step $sub exits 2" "$rc" "2"
  done
  check "A23: no task-step subcommand wrote workspace state for the Codex plan" "$(ls -A "$R/.dforge" 2>/dev/null | sort | tr '\n' ' ')" "$before"

  # Five fix rounds.
  check "A23: the Codex routing policy keeps review_cap 5" "$(jq -r '.review_cap' < "$PLUGIN/reference/codex-routing.json" | tr -d '\r')" "5"
}

ALL="a2 a3 a4 a5 a11 a12 a17 a18 a19 a20 a21 a22 a23"
if [ $# -gt 0 ]; then
  sel=""
  for n in "$@"; do sel="$sel $(tr 'A-Z' 'a-z' <<<"$n")"; done
else
  sel=$ALL
fi
for t in $sel; do "$t"; done

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
