#!/usr/bin/env bash
# Acceptance checks for docs/dforge/specs/2026-11-08-auto-run-worktree-setting-design.md:
# an auto run follows the worktree setting, guards its own branch and never
# commits the changes it carried into an in-place run.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
P="$(cd "$HERE/.." && pwd)"
S="$P/scripts"
AR="$S/auto-run"
TMP="$(mktemp -d)"
if command -v cygpath >/dev/null 2>&1; then TMP=$(cygpath -m "$TMP"); fi
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
mkdir -p "$HOME"
export LC_ALL=C MSYS_NO_PATHCONV=1 DFORGE_NO_SETTINGS=1 GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid \
  GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
unset DFORGE_BUDGET DFORGE_JQ DFORGE_FLOCK CLAUDE_CONFIG_DIR CODEX_HOME CLAUDE_CODE_SESSION_ID AR_SESSION CLAUDE_PROJECT_DIR
REPO="$TMP/repo"
STATE="$REPO/.dforge/sdd/auto-run.json"
SPEC=docs/dforge/specs/2026-11-08-widget-design.md

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
present() { # present <name> <file> <needle>
  if grep -qF -- "$3" "$2"; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       missing: [%s]\n       in: [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
absent() { # absent <name> <file> <needle>
  if grep -qF -- "$3" "$2"; then printf 'FAIL - %s\n       unexpected: [%s]\n       in: [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1))
  else printf 'ok   - %s\n' "$1"; pass=$((pass + 1)); fi
}
has() { # has <name> <haystack> <needle>
  if grep -qF -- "$3" <<<"$2"; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       missing: [%s]\n       in: [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
beat() { # beat <session>: the heartbeat a live cockpit writes
  local f
  f="$HOME/.claude/dforge/sessions/cockpit/$(printf '%s' "$1" | tr -c 'A-Za-z0-9' '-')"
  mkdir -p "$(dirname "$f")"
  printf '%s\n' "$(date +%s)" > "$f"
}
arun() { # arun <dir> <session> <args...>
  local dir=$1 s=$2
  shift 2
  beat "$s"
  (cd "$dir" && bash "$AR" --session "$s" "$@")
}
field() { jq -r --arg f "$1" '.[$f] | tostring' < "$STATE" | tr -d '\r'; }
fresh() { # a new repository on main with two tracked files and no run
  rm -rf "$REPO" "$TMP/side"
  git init -q -b main "$REPO"
  printf 'one\n' > "$REPO/a.txt"
  printf 'two\n' > "$REPO/b.txt"
  git -C "$REPO" add a.txt b.txt
  git -C "$REPO" commit -qm init
}
inplace() { # inplace <session>: an in-place run on its recorded branch auto/widget
  fresh
  arun "$REPO" "$1" start --spec "$SPEC" --register docs/r.md --isolation in-place >/dev/null
  git -C "$REPO" switch -q -c auto/widget
  arun "$REPO" "$1" setup-branch auto/widget >/dev/null
}

# --- Task 1 ---
fresh
arun "$REPO" t1 start --spec "$SPEC" --register docs/r.md --isolation in-place >/dev/null; status=$?
check "A1: start --isolation in-place exits 0" "$status" "0"
check "A1: the state records in-place" "$(field isolation)" "in-place"
has "A1: status prints the isolation" "$(arun "$REPO" t1 status)" "isolation in-place"
arun "$REPO" t1 start --spec "$SPEC" --register docs/r.md --force >/dev/null
has "A2: a start without --isolation reads as worktree" "$(arun "$REPO" t1 status)" "isolation worktree"
jq 'del(.isolation)' < "$STATE" > "$TMP/state.json" && mv "$TMP/state.json" "$STATE"
has "A2: a state file without the field reads as worktree" "$(arun "$REPO" t1 status)" "isolation worktree"
rm -f "$STATE"
out=$(arun "$REPO" t1 start --spec "$SPEC" --register docs/r.md --isolation elsewhere 2>&1); status=$?
check "A3: an unknown isolation exits 2" "$status" "2"
has "A3: and says which values it takes" "$out" "auto-run: --isolation must be worktree or in-place"
check "A3: and writes no state file" "$([ -e "$STATE" ] && echo yes || echo no)" "no"

fresh
arun "$REPO" t1 start --spec "$SPEC" --register docs/r.md --isolation in-place >/dev/null
arun "$REPO" t1 setup-branch main >/dev/null 2>&1; status=$?
check "A9: setup-branch refuses the base as the run's branch" "$status:$(field branch)" "4:null"
git -C "$REPO" switch -q -c auto/widget
arun "$REPO" t1 setup-branch auto/other >/dev/null 2>&1; status=$?
check "A9: setup-branch refuses a branch HEAD is not on" "$status:$(field branch)" "4:null"
printf 'mine\n' >> "$REPO/a.txt"
mv "$REPO/b.txt" "$REPO/c.txt"
git -C "$REPO" add -N c.txt
mkdir -p "$REPO/notes"
printf 'x\n' > "$REPO/notes/n1.md"
printf 'y\n' > "$REPO/notes/n2.md"
arun "$REPO" t1 setup-branch auto/widget >/dev/null; status=$?
check "A9: setup-branch on the run's branch exits 0" "$status" "0"
check "A9: it records the branch" "$(field branch)" "auto/widget"
check "A9: it records the branch's start commit" "$(field branchBase)" "$(git -C "$REPO" rev-parse HEAD)"
check "A9: carried holds each modified, worktree-renamed (both sides) and untracked file" \
  "$(arun "$REPO" t1 carried | tr -d '\r' | sort | tr '\n' ' ')" "a.txt b.txt c.txt notes/n1.md notes/n2.md "
has "A9: status names the branch" "$(arun "$REPO" t1 status)" "branch auto/widget"

fresh
arun "$REPO" t1 start --spec "$SPEC" --register docs/r.md --isolation in-place >/dev/null
git -C "$REPO" switch -q -c auto/widget
printf 'staged\n' >> "$REPO/a.txt"
git -C "$REPO" add a.txt
out=$(arun "$REPO" t1 setup-branch auto/widget 2>&1); status=$?
check "A21: staged changes: exit 4, nothing recorded" "$status:$(field branch):$(field carried)" "4:null:null"
has "A21: the refusal names the staged path" "$out" "auto-run: staged changes in the primary checkout: a.txt"

# --- Task 2 ---
fresh
arun "$REPO" t2 start --spec "$SPEC" --register docs/r.md --isolation in-place >/dev/null
out=$(arun "$REPO" t2 phase execute 2>&1); status=$?
check "A4: phase execute on the base in the primary checkout: exit 4, phase unchanged" "$status:$(field phase)" "4:spec"
has "A4: the refusal points at Step 0" "$out" "follow dforge:using-git-worktrees Step 0 for the run"
git -C "$REPO" worktree add -q -b side "$TMP/side"
arun "$TMP/side" t2 start --spec "$SPEC" --register docs/r.md --isolation worktree --force >/dev/null
check "A4: a run started in a linked worktree takes its branch as base" "$(field base)" "side"
arun "$TMP/side" t2 phase execute >/dev/null 2>&1; status=$?
check "A4: phase execute on the base in a linked worktree: exit 4" "$status:$(field phase)" "4:spec"
git -C "$TMP/side" switch -q -c auto/widget
arun "$TMP/side" t2 setup-branch auto/widget >/dev/null
arun "$TMP/side" t2 phase execute; status=$?
check "A12: a linked-worktree run reaches execute on its own branch" "$status:$(field phase)" "0:execute"

inplace t2
arun "$REPO" t2 phase execute; status=$?
check "A5: in place on the recorded branch: exit 0" "$status:$(field phase)" "0:execute"
git -C "$REPO" switch -q main
arun "$REPO" t2 phase execute >/dev/null 2>&1; status=$?
check "A6: phase execute on the base with a recorded branch: exit 4" "$status" "4"
git -C "$REPO" switch -q -c elsewhere
arun "$REPO" t2 phase execute >/dev/null 2>&1; status=$?
check "A6: phase execute off the recorded branch: exit 4" "$status" "4"
out=$(arun "$REPO" t2 task-complete 2>&1); status=$?
check "A6: task-complete off the recorded branch stops the run" "$status:$(field active)" "5:false"
has "A6: and says why" "$out" "a task was completed off the run's branch"
inplace t2
arun "$REPO" t2 phase execute >/dev/null
git -C "$REPO" switch -q main
out=$(arun "$REPO" t2 task-complete 2>&1); status=$?
check "A6: task-complete on the base with a recorded branch stops the run" "$status:$(field active)" "5:false"
has "A6: and names the base" "$out" "a task was completed on the run's base branch"

fresh
arun "$REPO" t2 start --spec "$SPEC" --register docs/r.md --isolation worktree >/dev/null
git -C "$REPO" switch -q -c feature
out=$(arun "$REPO" t2 phase execute 2>&1); status=$?
check "A7: a worktree run in the primary checkout: exit 4 off the base too" "$status:$(field phase)" "4:spec"
has "A7: with today's message" "$out" "create the execution worktree first (dforge:using-git-worktrees)"

fresh
git -C "$REPO" switch -q --detach
arun "$REPO" t2 start --spec "$SPEC" --register docs/r.md --isolation in-place >/dev/null
check "A8: a detached start has no base" "$(field base)" "null"
arun "$REPO" t2 phase execute >/dev/null 2>&1; status=$?
check "A8: detached in the primary checkout with no base: exit 4" "$status" "4"
git -C "$REPO" switch -q -c auto/widget
arun "$REPO" t2 setup-branch auto/widget >/dev/null
arun "$REPO" t2 phase execute; status=$?
check "A8: on the recorded branch: exit 0" "$status" "0"
fresh
git -C "$REPO" worktree add -q --detach "$TMP/side"
arun "$TMP/side" t2 start --spec "$SPEC" --register docs/r.md --isolation worktree >/dev/null
arun "$TMP/side" t2 phase execute >/dev/null 2>&1; status=$?
check "A8: detached in a linked worktree with no base: exit 4" "$status:$(field phase)" "4:spec"
git -C "$TMP/side" switch -q -c auto/widget
arun "$TMP/side" t2 setup-branch auto/widget >/dev/null
arun "$TMP/side" t2 phase execute; status=$?
check "A8: that worktree on the recorded branch: exit 0" "$status" "0"

fresh
printf 'mine\n' >> "$REPO/a.txt"
arun "$REPO" t2 start --spec "$SPEC" --register docs/r.md --isolation in-place >/dev/null
git -C "$REPO" switch -q -c auto/widget
arun "$REPO" t2 setup-branch auto/widget >/dev/null
arun "$REPO" t2 phase execute
printf 'task\n' > "$REPO/t.txt"
git -C "$REPO" add t.txt && git -C "$REPO" commit -qm task
arun "$REPO" t2 task-complete; status=$?
check "A10: a commit of other paths: task-complete exits 0" "$status:$(field active)" "0:true"
arun "$REPO" t2 phase final; status=$?
check "A20: phase final with no carried path committed: exit 0" "$status:$(field phase)" "0:final"
arun "$REPO" t2 phase finish; status=$?
check "A20: phase finish with no carried path committed: exit 0" "$status:$(field phase)" "0:finish"
arun "$REPO" t2 phase final >/dev/null
git -C "$REPO" add a.txt && git -C "$REPO" commit -qm carried
out=$(arun "$REPO" t2 phase finish 2>&1); status=$?
check "A20: phase finish after a carried path was committed: exit 4" "$status:$(field phase)" "4:final"
has "A20: names the path" "$out" "auto-run: carried path a.txt was committed; stop the run"
out=$(arun "$REPO" t2 task-complete 2>&1); status=$?
check "A10: task-complete after a carried path was committed stops the run" "$status:$(field active)" "5:false"
has "A10: the stop reason names the path" "$out" "carried path a.txt was committed"

fresh
printf 'mine\n' >> "$REPO/a.txt"
arun "$REPO" t2 start --spec "$SPEC" --register docs/r.md --isolation in-place >/dev/null
git -C "$REPO" switch -q -c auto/widget
arun "$REPO" t2 setup-branch auto/widget >/dev/null
arun "$REPO" t2 phase execute
git -C "$REPO" add a.txt && git -C "$REPO" commit -qm carried
out=$(arun "$REPO" t2 phase final 2>&1); status=$?
check "A20: phase final after a carried path was committed: exit 4" "$status:$(field phase)" "4:execute"

fresh
printf 'mine\n' >> "$REPO/a.txt"
printf 'draft\n' > "$REPO/draft.md"
before=$(cd "$REPO" && git hash-object a.txt draft.md | tr -d '\r' | tr '\n' ' ')
arun "$REPO" t2 start --spec "$SPEC" --register docs/r.md --isolation in-place >/dev/null
git -C "$REPO" switch -q -c auto/widget
arun "$REPO" t2 setup-branch auto/widget >/dev/null
arun "$REPO" t2 phase execute
printf 'task\n' > "$REPO/t.txt"
git -C "$REPO" add t.txt && git -C "$REPO" commit -qm task
arun "$REPO" t2 task-complete; status=$?
git -C "$REPO" switch -q main
git -C "$REPO" merge -q --no-edit auto/widget
git -C "$REPO" branch -q -d auto/widget
check "A11: the flow's task-complete passed" "$status" "0"
check "A11: carried files are byte for byte unchanged" "$(cd "$REPO" && git hash-object a.txt draft.md | tr -d '\r' | tr '\n' ' ')" "$before"
check "A11: and still uncommitted" "$(git -C "$REPO" status --porcelain | tr -d '\r' | sort | tr '\n' '|')" " M a.txt|?? draft.md|"
check "A11: the task's commit reached main" "$(git -C "$REPO" log -1 --format=%s -- t.txt)" "task"
check "A11: the run's branch is deleted" "$(git -C "$REPO" branch --list auto/widget)" ""

# --- Task 3 ---
G="$P/skills/using-git-worktrees/SKILL.md"
present "A13: Step 0 reads the run state" "$G" 'read the auto-run state (`scripts/auto-run status`), not the `worktree` setting'
present "A13: a recorded branch is switched back to" "$G" 'When the status names `branch <name>`, switch to that branch'
present "A13: a base or detached HEAD gets the run's branch" "$G" '`git switch -c auto/<plan slug>`'
present "A13: setup-branch records it" "$G" '`scripts/auto-run setup-branch <name>`'
present "A13: staged changes stop the run" "$G" 'staged changes in the primary checkout: <paths>'
present "A13: a worktree run in the primary checkout creates it unasked" "$G" 'Under `isolation worktree` in the primary checkout, create the worktree without asking'
check "A15: no skill says never creates the worktree in an auto run" \
  "$(grep -rlF -- '`worktree=never` creates' "$P/skills" "$P/reference" | wc -l | tr -d ' ')" "0"
R="$P/skills/resume-execution/SKILL.md"
present "A19: resume switches back to the run's branch" "$R" 'When HEAD is not on it, run `git switch <name>`'
present "A19: a gone branch stops the run" "$R" "the run's branch <name> is gone"
present "A19: no EnterWorktree into the primary checkout" "$R" 'Skip EnterWorktree when the recorded workspace is the primary checkout'
present "A19: auto-run.md lists the stop" "$P/reference/auto-run.md" "the run's branch is gone"
present "auto-run.md: the worktree consent is asked under ask" "$P/reference/auto-run.md" 'the worktree consent (asked at the spec review under `worktree=ask`)'
for f in "$P/skills/executing-plans/SKILL.md" "$P/skills/subagent-driven-development/SKILL.md" "$P/reference/auto-run.md"; do
  absent "$(basename "$(dirname "$f")")/$(basename "$f"): no execution worktree wording" "$f" 'from the execution worktree'
  present "$(basename "$(dirname "$f")")/$(basename "$f"): side effects outside the workspace" "$f" 'outside the execution workspace'
done
present "executing-plans: Setup runs from the workspace" "$P/skills/executing-plans/SKILL.md" 'from the execution workspace'
present "executing-plans: exit 4 points at Step 0" "$P/skills/executing-plans/SKILL.md" 'follow dforge:using-git-worktrees Step 0 for the run, then run the command again'
present "subagent-driven-development: exit 4 points at Step 0" "$P/skills/subagent-driven-development/SKILL.md" 'follow dforge:using-git-worktrees Step 0 for the run, then run the command again'
for f in "$P/skills/executing-plans/SKILL.md" "$P/skills/subagent-driven-development/SKILL.md"; do
  present "$(basename "$(dirname "$f")"): exit 5 names every stop" "$f" 'on the run base, off its branch or in the primary checkout, or a carried path was committed'
done
present "auto-run.md: the switch starts at Setup, workspace first" "$P/reference/auto-run.md" 'execution skill starts at its Setup, workspace first: `scripts/auto-run status`'

# --- Task 4 ---
X="$P/reference/executor-lane.md"
present "A16: the lane falls back in the primary checkout" "$X" 'executor <id> unavailable - no linked worktree'
present "A16: after the plain task-step start" "$X" 'run `task-step start` as the executor path does'
present "A16: users keep the primary checkout only in worktree runs" "$X" 'In a worktree run the user can continue in the primary checkout'
present "A16: the auto-run offer ticks nothing in place" "$P/skills/writing-plans/references/auto-run-plan.md" 'tick nothing when `scripts/auto-run status` prints `isolation in-place`'
present "A17: recovery leaves carried paths uncommitted" "$P/skills/executing-plans/references/recovery.md" 'commit anything uncommitted except the carried paths (`scripts/auto-run carried`)'
present "A17: QA cleanup never touches a carried path" "$P/reference/final-review.md" 'Never restore or delete a carried path (`scripts/auto-run carried`)'
present "A17: tasks stage by name" "$P/skills/executing-plans/references/setup.md" 'stage the paths it changed by name, never `git add -A` or `git add .`'
stray=$(cat "$P/skills/executing-plans/SKILL.md" "$P"/skills/executing-plans/references/*.md "$P/skills/subagent-driven-development/SKILL.md" \
  "$P/reference/auto-run.md" "$P/reference/delegated-task.md" "$P/skills/using-git-worktrees/SKILL.md" \
  | grep -E 'git add (-A|\.)([ `]|$)' | grep -vcF 'never `git add -A` or `git add .`')
check "A17: no auto-run setup or task-loop text stages everything" "$stray" "0"
present "executing-plans: a carried commit at phase final stops the run" "$P/skills/executing-plans/SKILL.md" 'is a carried path and was committed'
present "subagent-driven-development: a carried commit at phase final stops the run" "$P/skills/subagent-driven-development/SKILL.md" 'is a carried path and was committed'
F="$P/skills/finishing-a-development-branch/SKILL.md"
present "A18: the stop list names checkout, pull and merge" "$F" 'a refused checkout, pull or merge of the base'
present "A18: phase finish refusal stops the run" "$F" 'is a carried path and was committed'
present "A18: a red merged suite lists the carried paths" "$F" 'list the carried paths (`scripts/auto-run carried`) with the failure'
present "A18: pr and keep name the branch" "$F" 'This checkout is on `auto/<slug>`; your uncommitted changes are here'

# --- summary ---
printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
