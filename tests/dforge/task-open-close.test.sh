#!/usr/bin/env bash
# task-brief --open and task-close: the two calls that bracket a task the
# session implements. Each case runs against a throwaway repository and plan.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
P="$HERE/../../plugins/dforge"
BRIEF="$P/scripts/task-brief"
CLOSE="$P/scripts/task-close"
STEP="$P/scripts/task-step"

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
has() { check "$1" "$(grep -cF -- "$3" <<<"$2" | sed 's/^0$/no/; s/^[1-9][0-9]*$/yes/')" yes; }

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
|# Open Close Fixture
|
|**Goal:** Fixture.
|
|**Execution:** inline — `claude --model opus --effort high` — fixture
|
|**Task check:** `bash t.sh` — fast
|**Integration check:** `bash all.sh`
|**Early CI:** after task 2 — consented 2026-11-14
|
|## Global Constraints
|
|- Fixture constraint.
|
|## Contracts
|
|- Fixture contract.
|
|### Task 1: plain
|
|**Evaluation:** files 0 - spec 0 - coupling 1 - risk 0 = 1
|
|Body one.
|
|### Task 2: second
|
|**Evaluation:** files 0 - spec 0 - coupling 0 - risk 0 = 0
|
|### Task 3: risky
|
|**Evaluation:** files 1 - spec 1 - coupling 1 - risk 3 = 6
PLAN
sed 's/^\*\*Task check:\*\* .*/**Task check:** none — full suite every 3 tasks/' docs/plan.md > docs/none.md
sed 's/^|//' > docs/codex.md <<'PLAN'
|# Codex Fixture
|
|**Host:** codex
|
|### Task 1: only
|
|**Evaluation:** files=0, spec=0, coupling=0, risk=0; weighted routing score=0
PLAN
git add -A && git commit -qm "docs: fixtures"
BASE7=$(git rev-parse --short HEAD)

WS=$(bash "$P/scripts/sdd-workspace" docs/plan.md)
LEDGER="$WS/progress.md"
run() { out=$("$@" 2>"$TMP/err"); rc=$?; err=$(cat "$TMP/err"); }

# --- task-brief --open ---
run bash "$BRIEF" --open docs/plan.md 1
check "open: exit 0" "$rc" "0"
has "open: names the base" "$out" "task 1: opened, base $BASE7"
check "open: the ledger names the plan" "$(head -n 1 "$LEDGER")" "# SDD ledger — plan: docs/plan.md"
check "open: the assigned line" "$(tail -n 1 "$LEDGER")" "Task 1: implementer inline (assigned; base $BASE7)"
has "open: the task check line" "$out" "task check: bash t.sh"
check "open: the budget line is last" "$(tail -n 1 <<<"$out" | cut -c1-6)" "budget"
check "open: the first line names the brief file" "$(head -n 1 <<<"$out")" "wrote $WS/task-1-brief.md: $(wc -l < "$WS/task-1-brief.md" | tr -d ' ') lines"
check "open: prints the brief between its markers" \
  "$(sed -n '/^--- brief ---$/,/^--- end of brief ---$/p' <<<"$out" | sed '1d;$d')" "$(cat "$WS/task-1-brief.md")"
check "open: the brief holds no header excerpt" "$(grep -c '^## Plan header excerpt$' "$WS/task-1-brief.md")" "0"
check "open: the brief points at the header file" "$(grep -c "^Global Constraints and Contracts: $WS/plan-header.md " "$WS/task-1-brief.md")" "1"
check "open: the header file holds the constraints" "$(grep -c '^- Fixture constraint\.$' "$WS/plan-header.md")" "1"

git commit -q --allow-empty -m "feat: moved"
run bash "$BRIEF" --open docs/plan.md 1
has "open again: the task is already open at its first base" "$out" "task 1: already open, base $BASE7"
check "open again: no second assigned line" "$(grep -c '^Task 1: implementer' "$LEDGER")" "1"

run bash "$BRIEF" --open docs/plan.md 3
check "open: a risk-3 brief keeps the header excerpt for its judge" "$(grep -c '^## Plan header excerpt$' "$WS/task-3-brief.md")" "1"
check "open: a risk-3 brief carries the review marker" "$(sed -n 2p "$WS/task-3-brief.md")" "**Review:** per-task — risk 3"
rm -f "$WS/plan-header.md"
run bash "$BRIEF" docs/plan.md 3
check "brief: a risk-3 brief still writes the header file" "$([ -f "$WS/plan-header.md" ] && echo yes || echo no)" "yes"
awk 'NR == 2 { print "```markdown"; print "**Host:** codex"; print "```" } { print }' docs/plan.md > "$TMP/fenced-host.md"
run bash "$BRIEF" "$TMP/fenced-host.md" 3 "$TMP/fenced-brief.md"
check "brief: a fenced Host: codex example keeps the risk-3 marker" "$rc|$(sed -n 2p "$TMP/fenced-brief.md")" "0|**Review:** per-task — risk 3"

run bash "$BRIEF" --open docs/plan.md 99
check "open: no such task exits 3" "$rc" "3"
run bash "$BRIEF" --open docs/plan.md
check "open: no task exits 2" "$rc" "2"
run bash "$BRIEF" --open docs/codex.md 1
check "open: a Host: codex plan opens" "$rc:$(grep -c '^Task 1: implementer inline (assigned; base ' "$(bash "$P/scripts/sdd-workspace" docs/codex.md)/progress.md")" "0:1"
check "open: a Codex brief carries no Claude-only lines" "$(grep -c '^\*\*Review:\*\*\|Plan header excerpt\|^## Plan header$' "$(bash "$P/scripts/sdd-workspace" docs/codex.md)/task-1-brief.md")" "0"

# A brief without --open writes no ledger line and still prints the check.
run bash "$BRIEF" docs/plan.md 2
check "plain brief: prints no brief body" "$(grep -c '^--- brief ---$' <<<"$out")" "0"
check "plain brief: no assigned line for task 2" "$(grep -c '^Task 2:' "$LEDGER")" "0"
has "plain brief: prints the task check" "$out" "task check: bash t.sh"

# The integration check is due on every third task and the last.
for t in 1 2 3; do
  run bash "$BRIEF" docs/none.md "$t"
  case $t in
    3) has "none: task 3 names the integration check" "$out" "task check: none; the integration check is due: bash all.sh" ;;
    *) has "none: task $t says it is not due" "$out" "task check: none; the integration check is not due" ;;
  esac
done
sed 's/^\*\*Integration check:\*\* .*/**Integration check:** bash all.sh/' docs/none.md > docs/bare.md
run bash "$BRIEF" docs/bare.md 3
has "none: a bare Integration check names its command" "$out" "task check: none; the integration check is due: bash all.sh"
sed '/^\*\*Task check:\*\*/d' docs/plan.md > docs/unset.md
run bash "$BRIEF" docs/unset.md 1
has "unset: no Task check line says to run the full suite" "$out" "task check: no **Task check:** line; run the full suite once before committing"

# --- task-step review needs no start after --open ---
rm -f "$WS/task-1-step.json"
echo a > a.txt && git add a.txt && git commit -qm "feat: add a"
run bash "$STEP" review docs/plan.md 1
check "review: an opened task reviews without a start" "$([ -f "$WS/task-1-step.json" ] && echo yes || echo no)" "yes"
check "review: the state records the opened base" "$(jq -r .base "$WS/task-1-step.json" | tr -d '\r' | cut -c1-7)" "$BASE7"
run bash "$STEP" review docs/plan.md 2
check "review: a task never opened still exits 6" "$rc" "6"

# --- task-close ---
CP='done: x; verified: bash t.sh → pass; remaining: none; discovered: none; assumptions: none'
HEAD7=$(git rev-parse --short HEAD)
mkdir -p "$TMP/node-shim"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "%s"\nexec "%s" "$@"\n' "$TMP/node.log" "$(command -v node)" > "$TMP/node-shim/node"
chmod +x "$TMP/node-shim/node"
PATH="$TMP/node-shim:$PATH" run bash "$CLOSE" docs/plan.md 1 "$CP"
check "close: exit 0" "$rc" "0"
check "close: a home without darkmem starts no darkmem push" "$(cat "$TMP/node.log" 2>/dev/null | grep -c 'darkmem-sync')" "0"
check "close: the complete line" "$(tail -n 1 "$LEDGER")" "Task 1: complete (commits $BASE7..$HEAD7, unreviewed) — $CP"
has "close: prints the line it wrote" "$out" "wrote: Task 1: complete"
run bash "$CLOSE" docs/plan.md 1 "$CP"
check "close again: exit 0" "$rc" "0"
has "close again: says it is already complete" "$out" "task 1: already complete"
check "close again: writes no second line" "$(grep -c '^Task 1: complete' "$LEDGER")" "1"
LEDGER_BEFORE=$(cat "$LEDGER")
for ((i = 0; i < 4000; i++)); do printf 'Task 2: note %04d — filler that takes the ledger past one pipe buffer\n' "$i"; done >> "$LEDGER"
run bash "$CLOSE" docs/plan.md 1 "$CP"
check "close again past 64 KiB: still finds the complete line" "$rc|$(grep -c '^Task 1: complete' "$LEDGER")" "0|1"
printf '%s\n' "$LEDGER_BEFORE" > "$LEDGER"

run bash "$BRIEF" --open docs/plan.md 2
run bash "$CLOSE" docs/plan.md 2 "$CP" --review "review clean; scores spec 17 / scope 18 / verification 15 / quality 16, seat dforge:judge-opus"
check "close: --review replaces unreviewed" "$(tail -n 1 "$LEDGER" | grep -c '^Task 2: complete (commits [0-9a-f]*\.\.[0-9a-f]*, review clean; scores ')" "1"
has "close: an Early CI naming the task is flagged" "$out" "early CI: due after this task"

run bash "$CLOSE" docs/none.md 1 "$CP"
check "close: a task never opened exits 3" "$rc" "3"
run bash "$CLOSE" docs/plan.md 99 "$CP"
check "close: no such task exits 3" "$rc" "3"
run bash "$CLOSE" docs/plan.md 1 "done: x"
check "close: a checkpoint missing fields exits 2" "$rc" "2"
run bash "$CLOSE" docs/plan.md 1 'undone: x; unverified: y; remaining: none; discovered: none; assumptions: none'
check "close: a checkpoint whose fields are only substrings exits 2" "$rc" "2"
run bash "$CLOSE" docs/plan.md 1
check "close: no checkpoint exits 2" "$rc" "2"

# The last close prints the final budget line.
run bash "$BRIEF" --open docs/plan.md 3
run bash "$CLOSE" docs/plan.md 3 "$CP"
check "close: the last task prints a budget line" "$(grep -c '^budget' <<<"$out")" "1"
check "close: a middle task prints none" "$(run bash "$CLOSE" docs/plan.md 2 "$CP"; grep -c '^budget' <<<"$out")" "0"
# The budget mode reads the plan's ledger, not the working directory's.
git init -q "$TMP/other"
out=$(cd "$TMP/other" && bash "$BRIEF" "$REPO/docs/plan.md" 3 "$TMP/other-brief.md" 2>/dev/null)
check "brief from another repository: the plan's ledger sets the budget mode" "$(tail -n 1 <<<"$out" | cut -d: -f1)" "budget (final)"

# --- every amendment consumer refuses a ledger citing a missing amendment (A4) ---
printf 'Task 1: Ruling: amendment A7 — x — y\n' >> "$LEDGER"
for argv in "task-brief|docs/plan.md|1" \
    "task-step|review|docs/plan.md|1" \
    "task-close|docs/plan.md|1|done: x; verified: y; remaining: none; discovered: none; assumptions: none" \
    "plan-lint|docs/plan.md" \
    "review-route|docs/plan.md|--task|1" \
    "lens-route|docs/plan.md|--task|1" \
    "depth-route|docs/plan.md"; do
  IFS='|' read -r -a a <<<"$argv"
  run bash "$P/scripts/${a[0]}" "${a[@]:1}"
  check "${a[0]}: a cited amendment missing exits 2" "$rc" "2"
  has "${a[0]}: the message names the script and the amendment" "$err" "${a[0]}: the ledger cites amendment A7"
done
sed -i '/amendment A7/d' "$LEDGER"

# --- a ledger that names another plan with the same basename is refused (rows 2, 52) ---
mkdir -p other && cp docs/plan.md other/plan.md
LEDGER_BEFORE=$(cat "$LEDGER")
run bash "$BRIEF" --open other/plan.md 2
check "open: a same-basename plan's ledger exits 2" "$rc" "2"
check "open: it writes nothing" "$(cat "$LEDGER")" "$LEDGER_BEFORE"
run bash "$CLOSE" other/plan.md 1 'done: x; verified: y; remaining: none; discovered: none; assumptions: none'
check "close: a same-basename plan's ledger exits 2" "$rc" "2"
run bash "$CLOSE" docs/plan.md 1 $'done: x\nTask 9: complete; verified: y; remaining: none; discovered: none; assumptions: none'
check "close: a checkpoint with a newline exits 2" "$rc" "2"
LEDGER_BEFORE=$(cat "$LEDGER")
run bash "$CLOSE" docs/plan.md 1 'done: x; verified: y; remaining: none; discovered: none; assumptions: none' --review $'review clean\nFinal review: clean (commits a..b)'
check "close: a review text with a newline exits 2 and writes nothing" "$rc|$(cat "$LEDGER")" "2|$LEDGER_BEFORE"
rm -rf other

# --- --open refuses another checkout's plan and a task number it cannot read ---
git worktree add -q --detach "$TMP/wt-open" HEAD
LEDGER_BEFORE=$(cat "$LEDGER")
out=$(cd "$TMP/wt-open" && bash "$BRIEF" --open "$REPO/docs/plan.md" 2 2>"$TMP/err"); rc=$?
check "open: a worktree session given the primary's plan exits 2" "$rc|$(cat "$LEDGER")" "2|$LEDGER_BEFORE"
git worktree remove --force "$TMP/wt-open"
run bash "$BRIEF" --open docs/plan.md 1x
check "open: a non-numeric task number exits 2" "$rc|$(grep -c '^Task 1x:' "$LEDGER")" "2|0"
run bash "$BRIEF" --open docs/plan.md 01
check "open: 01 opens Task 1" "$(grep -c '^Task 01:' "$LEDGER")|$(grep -c 'task 1: already open' <<<"$out")" "0|1"

# --- auto: one budget line, task-close's own ---
. "$HERE/fixtures/cockpit-ack.sh"
cockpit_ack_start "$HOME"
sed '/^### Task 2/,$d' docs/plan.md > docs/auto-plan.md
git add docs/auto-plan.md && git commit -qm "docs: auto fixture"
mkdir -p "$HOME/.claude/dforge/sessions/cockpit"
date +%s > "$HOME/.claude/dforge/sessions/cockpit/s-tc"
bash "$P/scripts/auto-run" --session s-tc start --spec docs/spec.md --isolation in-place >/dev/null 2>&1
git checkout -q -b auto/tc
AST="$(git rev-parse --show-toplevel)/.dforge/sdd/auto-run.json"
jq '.phase = "execute" | .branch = "auto/tc"' "$AST" > "$AST.tmp" && mv "$AST.tmp" "$AST"
run bash "$BRIEF" --open docs/auto-plan.md 1
CLAUDE_CODE_SESSION_ID=s-tc run bash "$CLOSE" docs/auto-plan.md 1 "$CP"
check "auto: task-close prints one budget line (A13)" \
  "$rc|$(grep -c '^budget' <<<"$out")|$(tail -n 1 <<<"$out" | cut -c1-12)" "0|1|budget (auto"
bash "$P/scripts/auto-run" --session s-tc stop >/dev/null 2>&1
git checkout -q -

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
