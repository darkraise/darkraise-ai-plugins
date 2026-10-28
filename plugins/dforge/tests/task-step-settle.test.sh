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
|Run: `bash check.sh`
|
|### Task 2: Two
|
|**Files:**
|- Modify: `lib/new.sh`
|
|**Implementer:** dforge:impl-sonnet-low
|**Evaluation:** files 0 - spec 0 - coupling 1 - risk 0 = 1
|
|Run: `bash check.sh`
|Run: `no_such_command_zz`
PLAN
printf '#!/usr/bin/env bash\necho old\n' > "$REPO/lib/old.sh"
printf 'see gone.md\n' > "$REPO/notes.txt"
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
- cannot-verify: exists ./gone.md at head, expect absent — a root file another file mentions
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
check "a path absent at head" "$(ledger_count "$LINE exists — path absent")" "2"
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
check "a second verdict logs nothing twice" "$(grep -c 'settled by task-step check' "$LEDGER")" "6"

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

# A check that could not run is not an answer: a command that is not found,
# and a commit the repository does not have, reach the ruling seat.
cat > "$WS/task-2-review-report.md" <<'REPORT'
## Verdict
spec: cannot-verify
quality: approved
scores: spec 15 / scope 17 / verification 12 / quality 16

## Strengths
Fine.

## Findings

## Cannot verify
- cannot-verify: baseline no_such_command_zz, expect fail — the brief says the command fails
- cannot-verify: exists lib/old.sh at base, expect absent — the brief says it is new

## Assessment
Fine.
REPORT
jq '.base = "0123456789abcdef0123456789abcdef01234567"' "$WS/task-2-step.json" > "$TMP/s2.json" && mv "$TMP/s2.json" "$WS/task-2-step.json"
settled=$(grep -c 'settled by task-step check' "$LEDGER")
ts verdict docs/plan.md 2
check "an unrunnable baseline command and an unknown base commit are left for the seat" "$(grep '^cannot-verify: ' <<<"$out")" \
  "cannot-verify: baseline no_such_command_zz, expect fail — the brief says the command fails
cannot-verify: exists lib/old.sh at base, expect absent — the brief says it is new"
check "neither is settled or a finding" "$(grep -c 'settled by task-step check' "$LEDGER") $(grep '^findings: ' <<<"$out")" "$settled findings: 0 Critical, 0 Important, 0 Minor"

# A baseline command runs only when the plan names it for the task being
# settled; every marker file below is made by a command that ran.
MARK_DIR="$TMP/marks"
mkdir -p "$MARK_DIR" "$TMP/marks-sr"
export MARK_DIR
printf '#!/usr/bin/env bash\n: > "$MARK_DIR/$1"\nexit "${2:-0}"\n' > "$REPO/mark.sh"
sed 's/^|//' > "$REPO/docs/named.md" <<'PLAN'
|# Named Commands Fixture Plan
|
|**Goal:** Fixture.
|
|**Execution:** subagent — `claude --model sonnet --effort high` — fixture
|
|**Integration check:** `bash mark.sh integ 0`
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
|Run: `bash mark.sh run-first 0` and then `bash mark.sh second-span 0`
|- Run: `bash mark.sh run-list 0`
|Run: `bash mark.sh timed 124`
|Run: ``bash mark.sh dbl 0``
|Afterwards run: `bash mark.sh prose 0`
|**Check:** `bash mark.sh check 0` prints nothing.
|
|```bash
|bash mark.sh fenced 0
|Run: `bash mark.sh fenced-run 0`
|```
|
|### Task 2: Two
|
|**Files:**
|- Modify: `lib/new.sh`
|
|**Implementer:** dforge:impl-sonnet-low
|**Evaluation:** files 0 - spec 0 - coupling 1 - risk 0 = 1
|
|Run: `bash mark.sh task2-run 0`
PLAN
g add -A && g commit -qm "named commands fixture"
ts start docs/named.md 1 --suite 'bash mark.sh suite 0'
NWS=$(winpath "$(cd "$REPO" && bash "$S/sdd-workspace" docs/named.md)")
NLEDGER="$NWS/progress.md"
printf '#!/usr/bin/env bash\ncompute_total() {\n  echo 3\n}\n' > "$REPO/lib/new.sh"
g add -A && g commit -qm "named work"
(cd "$REPO" && MARK_DIR="$TMP/marks-sr" bash "$S/suite-run" -- bash -c 'bash mark.sh suite 0' >/dev/null 2>&1)
ts review docs/named.md 1
check "named: review exits 0" "$rc" "0"
cat > "$NWS/task-1-review-report.md" <<'REPORT'
## Verdict
spec: cannot-verify
quality: approved
scores: spec 15 / scope 17 / verification 12 / quality 16

## Strengths
Fine.

## Findings

## Cannot verify
- cannot-verify: baseline bash mark.sh run-first 0, expect pass — the first span of a Run line
- cannot-verify: baseline  bash mark.sh run-list 0 , expect pass — a listed Run line, padded with spaces
- cannot-verify: baseline bash mark.sh check 0, expect pass — a Check line
- cannot-verify: baseline bash mark.sh integ 0, expect pass — the Integration check
- cannot-verify: baseline bash mark.sh suite 0, expect pass — the recorded suite command
- cannot-verify: baseline bash mark.sh timed 124, expect pass — a plan-named command that exits 124
- cannot-verify: baseline bash mark.sh nowhere 0, expect pass — a command the plan never names
- cannot-verify: baseline bash mark.sh run-first 0; bash mark.sh appended 0, expect pass — a named command with more after it
- cannot-verify: baseline bash mark.sh fenced 0, expect pass — a line of a fenced block
- cannot-verify: baseline bash mark.sh fenced-run 0, expect pass — a Run line inside a fenced block
- cannot-verify: baseline bash mark.sh second-span 0, expect pass — the second span of a Run line
- cannot-verify: baseline bash mark.sh dbl 0, expect pass — a double-backtick span
- cannot-verify: baseline bash mark.sh prose 0, expect pass — a line that does not begin with Run:
- cannot-verify: baseline bash mark.sh task2-run 0, expect pass — a command only Task 2 names

## Assessment
Fine.
REPORT
ts verdict docs/named.md 1
check "named: verdict exits 0" "$rc" "0"
check "named: only plan-named commands ran" "$(ls "$MARK_DIR" | sort | tr '\n' ' ')" "check integ run-first run-list suite timed "
check "named: the five settled items are logged, the rest add no ledger line" "$(grep -c 'settled by task-step check baseline' "$NLEDGER")" "5"
check "named: the suite command's item is settled with its own log" "$(grep -cxF "Task 1: Ruling: cannot-verify — settled by task-step check baseline — exit 0, log $NWS/task-1-baseline-5.log" "$NLEDGER")" "1"
check "named: a command that is not plan-named is no finding" "$(grep '^findings: ' <<<"$out")" "findings: 0 Critical, 0 Important, 0 Minor"
check "named: unnamed commands carry the label, a named command that exits 124 does not" "$(grep '^cannot-verify: ' <<<"$out")" \
  "cannot-verify: baseline bash mark.sh timed 124, expect pass — a plan-named command that exits 124
cannot-verify: baseline bash mark.sh nowhere 0, expect pass — a command the plan never names (command not named in the plan)
cannot-verify: baseline bash mark.sh run-first 0; bash mark.sh appended 0, expect pass — a named command with more after it (command not named in the plan)
cannot-verify: baseline bash mark.sh fenced 0, expect pass — a line of a fenced block (command not named in the plan)
cannot-verify: baseline bash mark.sh fenced-run 0, expect pass — a Run line inside a fenced block (command not named in the plan)
cannot-verify: baseline bash mark.sh second-span 0, expect pass — the second span of a Run line (command not named in the plan)
cannot-verify: baseline bash mark.sh dbl 0, expect pass — a double-backtick span (command not named in the plan)
cannot-verify: baseline bash mark.sh prose 0, expect pass — a line that does not begin with Run: (command not named in the plan)
cannot-verify: baseline bash mark.sh task2-run 0, expect pass — a command only Task 2 names (command not named in the plan)"
check "named: no temporary worktree is left" "$(g worktree list | wc -l | tr -d ' ')" "1"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
