#!/usr/bin/env bash
# task-step verdict answers a reviewer's structured cannot-verify items itself:
# an answer that matches the item's expect is logged to the ledger, a mismatch
# becomes an Important finding in the fix file, and free text goes to the
# ruling seat.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
P="$HERE/.."
S="$P/scripts"
TRP="$P/skills/subagent-driven-development/references/task-reviewer-prompt.md"

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
export DR_CODEX_SESSION_DIR="$TMP/sessions" CLAUDE_CODE_SESSION_ID=task-step-settle-test
printf '%s\n' '#!/usr/bin/env bash' 'echo "codex-gate usable=true reason= review=true lane=false resets_at=- source=cache"' > "$TMP/gate-stub"
export TASK_STEP_CODEX_GATE="$TMP/gate-stub"

check "the reviewer prompt names the exists form" "$(grep -cF -- '- cannot-verify: exists <path|symbol> at <base|head>, expect <present|absent> — <why>' "$TRP")" "1"
check "the reviewer prompt names the baseline form" "$(grep -cF -- '- cannot-verify: baseline <command>, expect <pass|fail> — <why>' "$TRP")" "1"

REPO="$TMP/repo"
git init -q "$REPO"
g() { git -C "$REPO" "$@"; }
g config user.name t
g config user.email t@example.invalid
mkdir -p "$REPO/docs" "$REPO/lib"
sed 's/^|//' > "$REPO/docs/plan.md" <<'PLAN'
|# Settle Fixture Plan
|
|**Goal:** Fixture.
|
|**Execution:** subagent — `claude --model sonnet --effort high` — fixture
|
|## Task index
|
|1. One
|2. Two
|
|### Task 1: One
|
|**Files:**
|- Modify: `lib/new.sh`
|
|**Implementer:** dforge:impl-sonnet-low
|**Evaluation:** files 0 - spec 0 - coupling 1 - risk 0 = 1
|
|### Task 2: Two
|
|**Files:**
|- Modify: `lib/new.sh`
|
|**Implementer:** dforge:impl-sonnet-low
|**Evaluation:** files 0 - spec 0 - coupling 1 - risk 0 = 1
PLAN
printf '#!/usr/bin/env bash\necho old\n' > "$REPO/lib/old.sh"
printf '#!/usr/bin/env bash\necho "not ok 1 - alpha"\nexit 1\n' > "$REPO/check.sh"
g add -A && g commit -qm base

ts() { # ts <args...> — task-step in the fixture repo; sets out, err, rc
  out=$(cd "$REPO" && bash "$S/task-step" "$@" 2>"$TMP/err"); rc=$?
  err=$(cat "$TMP/err")
}
ledger_count() { grep -cxF -- "$1" "$LEDGER" 2>/dev/null || true; }
first_block() { awk '{ sub(/\r$/, "") } /^$/ { exit } { print }' "$1" | tr '\n' ';'; }

ts start docs/plan.md 1
check "start exits 0" "$rc" "0"
WS=$(winpath "$(cd "$REPO" && bash "$S/sdd-workspace" docs/plan.md)")
LEDGER="$WS/progress.md"
printf '#!/usr/bin/env bash\ncompute_total() {\n  echo 1\n}\n' > "$REPO/lib/new.sh"
g add -A && g commit -qm work
ts review docs/plan.md 1
check "review exits 0" "$rc" "0"

cat > "$WS/task-1-review-report.md" <<'REPORT'
## Verdict
spec: cannot-verify
quality: approved
scores: spec 15 / scope 17 / verification 12 / quality 16

## Strengths
Fine.

## Findings

## Cannot verify
- cannot-verify: exists lib/new.sh at head, expect present — the brief names this file
- cannot-verify: exists lib/old.sh at base, expect present — the brief says it predates the task
- cannot-verify: exists lib/gone.sh at head, expect absent — the brief says it is removed
- cannot-verify: exists compute_total at head, expect present — callers need the function
- cannot-verify: exists no_such_symbol at head, expect present — the brief names a helper
- cannot-verify: exists lib/old.sh at head, expect absent — the brief says the task removes it
- cannot-verify: baseline bash check.sh, expect fail — does the check fail before the task
- the caller passes the flag
- cannot-verify: exists two words at head, expect present — a malformed target
- cannot-verify: exists lib/new.sh at head — an item without expect

## Assessment
Fine.
REPORT
ts verdict docs/plan.md 1
check "verdict exits 0" "$rc" "0"
check "only free text, the malformed item and the item without expect reach the ruling seat" "$(grep '^cannot-verify: ' <<<"$out")" \
  "cannot-verify: the caller passes the flag
cannot-verify: exists two words at head, expect present — a malformed target
cannot-verify: exists lib/new.sh at head — an item without expect"
LINE="Task 1: Ruling: cannot-verify — settled by task-step check"
check "a present path" "$(ledger_count "$LINE exists — path present")" "2"
check "a path absent at head" "$(ledger_count "$LINE exists — path absent")" "1"
check "a symbol's first hit" "$(ledger_count "$LINE exists — lib/new.sh:2")" "1"
check "a missing symbol against expect present is not settled" "$(ledger_count "$LINE exists — absent")" "0"
check "a baseline command" "$(ledger_count "$LINE baseline — exit 1, log $WS/task-1-baseline-1.log")" "1"
check "the baseline log is kept" "$(grep -c alpha "$WS/task-1-baseline-1.log")" "1"
check "no temporary worktree is left" "$(g worktree list | wc -l | tr -d ' ')" "1"
check "two mismatches count as Important" "$(grep '^findings: ' <<<"$out")" "findings: 0 Critical, 2 Important, 0 Minor"
check "each mismatch is a finding line" "$(grep '^Important ' <<<"$out" | tr '\n' ';')" \
  "Important 1 cannot-verify:0 — exists no_such_symbol at head, expect present — got absent;Important 1 cannot-verify:0 — exists lib/old.sh at head, expect absent — got path present;"
check "a mismatch names the fix file" "$(grep '^fix: ' <<<"$out")" "fix: $WS/task-1-fix-1.md (2 findings)"
check "the fix file's bullets" "$(first_block "$WS/task-1-fix-1.md")" \
  "- cannot-verify: exists no_such_symbol at head, expect present — got absent;- cannot-verify: exists lib/old.sh at head, expect absent — got path present;"
ts verdict docs/plan.md 1
check "a second verdict logs nothing twice" "$(grep -c 'settled by task-step check' "$LEDGER")" "5"

# Free text alone goes to the seat as today, and nothing is run.
cat > "$WS/task-1-review-report.md" <<'REPORT'
## Verdict
spec: cannot-verify
quality: approved
scores: spec 15 / scope 17 / verification 12 / quality 16

## Strengths
Fine.

## Findings

## Cannot verify
- the caller passes the flag

## Assessment
Fine.
REPORT
before=$(grep -c . "$LEDGER")
ts verdict docs/plan.md 1
check "free text is printed" "$(grep '^cannot-verify: ' <<<"$out")" "cannot-verify: the caller passes the flag"
check "free text writes no ledger line" "$(grep -c . "$LEDGER")" "$before"

# Two baseline items write two logs.
ts start docs/plan.md 2
printf '#!/usr/bin/env bash\ncompute_total() {\n  echo 2\n}\n' > "$REPO/lib/new.sh"
g add -A && g commit -qm work2
ts review docs/plan.md 2
cat > "$WS/task-2-review-report.md" <<'REPORT'
## Verdict
spec: cannot-verify
quality: approved
scores: spec 15 / scope 17 / verification 12 / quality 16

## Strengths
Fine.

## Findings

## Cannot verify
- cannot-verify: baseline bash check.sh, expect pass — the brief says the check already passes
- cannot-verify: baseline bash check.sh, expect fail — does the check fail before the task

## Assessment
Fine.
REPORT
ts verdict docs/plan.md 2
check "two baseline items write two logs" "$([ -f "$WS/task-2-baseline-1.log" ] && [ -f "$WS/task-2-baseline-2.log" ] && echo both || echo missing)" "both"
check "a matching baseline item is settled with its own log" "$(ledger_count "Task 2: Ruling: cannot-verify — settled by task-step check baseline — exit 1, log $WS/task-2-baseline-2.log")" "1"
check "a baseline mismatch logs no settled line" "$(ledger_count "Task 2: Ruling: cannot-verify — settled by task-step check baseline — exit 1, log $WS/task-2-baseline-1.log")" "0"
check "a baseline mismatch is an Important finding" "$(grep '^Important ' <<<"$out")" "Important 2 cannot-verify:0 — baseline bash check.sh, expect pass — got exit 1, log $WS/task-2-baseline-1.log"
check "a baseline mismatch names the fix file" "$(grep '^fix: ' <<<"$out")" "fix: $WS/task-2-fix-1.md (1 finding)"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
