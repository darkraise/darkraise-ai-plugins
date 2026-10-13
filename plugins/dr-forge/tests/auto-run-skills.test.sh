#!/usr/bin/env bash
# Both execution skills carry the auto run where a plan run would otherwise
# stop for its human: each check is a whole instruction, not a keyword.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
P="$HERE/.."
unset CLAUDE_CONFIG_DIR CLAUDE_CODE_SESSION_ID DR_FORGE_BUDGET

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
names() { # names <label> <file> <text>
  check "$1" "$(grep -qF -- "$3" "$2" && echo yes || echo no)" "yes"
}

for skill in subagent-driven-development executing-plans; do
  F="$P/skills/$skill/SKILL.md"
  names "$skill: the section" "$F" '## Auto run'
  names "$skill: after a compaction" "$F" '`scripts/auto-run after-compact` before step 1 above'
  names "$skill: setup asks nothing" "$F" 'skip the finish-preference question; run `scripts/auto-run phase execute`'
  names "$skill: blocked goes to Fable" "$F" '`BLOCKED` goes on the pending list and one Fable batch runs at once'
  names "$skill: the deferred line" "$F" 'Task <N>: complete (deferred by the auto run)'
  names "$skill: dependents are deferred too" "$F" 'and every task that depends on it'
  names "$skill: never performed" "$F" 'irreversible, security-sensitive or outside-the-worktree action is never'
  case $skill in
    executing-plans) after='`scripts/auto-run task-complete`. After each task, run the Fable batch when' ;;
    *) after='`scripts/auto-run task-complete`. After each wave, or each task in' ;;
  esac
  names "$skill: each task resets the count" "$F" "$after"
  names "$skill: compact ends the turn" "$F" '`Auto run: compacting` as its last line'
  names "$skill: the step owns the clear" "$F" 'then run `scripts/auto-run clear` and end as auto-run.md §Clears says'
  names "$skill: a handoff line waits for the task in flight" "$F" 'On `handoff`, finish the task in'
  names "$skill: the finish is the one outside action" "$F" '(the finish action is the one exception)'
  names "$skill: final review" "$F" 'run `scripts/auto-run phase final`'
  names "$skill: the four stops give way" "$F" 'except in an auto run'
done
names "subagent-driven-development: a deferred task is not merged" "$P/skills/subagent-driven-development/SKILL.md" "a deferred task's branch is"

R="$P/reference/auto-run.md"
names "auto-run.md: an unwritten handoff stops the run" "$R" 'If `scripts/next-step` exits 4, do not run `scripts/auto-run clear`'
names "auto-run.md: Stopping lists it" "$R" '`scripts/next-step` exits 4 during a clear (see Clears).'
names "auto-run.md: a deferred task keeps the branch" "$R" 'also keeps the branch when the ledger holds a'
names "finishing: a deferred task keeps the branch" "$P/skills/finishing-a-development-branch/SKILL.md" '`merge` keeps when the ledger holds a'
printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
