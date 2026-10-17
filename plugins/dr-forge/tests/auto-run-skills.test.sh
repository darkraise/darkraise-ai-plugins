#!/usr/bin/env bash
# Both execution skills carry the auto run where a plan run would otherwise
# stop for its human: each check is a whole instruction, not a keyword.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
P="$HERE/.."
unset CLAUDE_CONFIG_DIR CLAUDE_CODE_SESSION_ID DR_FORGE_BUDGET CLAUDE_PROJECT_DIR

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
names "auto-run.md: the critic runs before Fable" "$R" 'After your own self-review round and the architecture critic'
names "auto-run.md: a late statement goes up the ladder" "$R" 'is never asked: it goes up the ladder under Rulings'
names "auto-run.md: an undecided critic Blocker" "$R" '--note "critic Blocker unresolved"'
names "auto-run.md: a statement is deferred, not guessed" "$R" '**An acceptance statement in the spec phase:** the statement is deferred, not'
names "auto-run.md: QA ambiguity is parked" "$R" '**A QA `acceptance-ambiguous` item:** PARK it'
names "auto-run.md: QA ambiguity batches at once" "$R" 'A batch runs at once for a blocked task and for a QA'
names "auto-run.md: a critic Blocker takes its own note" "$R" 'it leaves undecided or without a suggestion to the run'"'"'s register, except a'
names "auto-run.md: unverified acceptance keeps the branch" "$R" '`merge` also keeps the branch when the `Acceptance QA: complete` line reports a nonzero count of'
names "auto-run.md: failures keep the branch" "$R" '`fail`, `flaky` or `cannot-test`, or when the run added a deferred register row'
names "auto-run.md: a deferred statement or unresolved Blocker keeps the branch" "$R" 'whose Item begins `A<n>:` or whose Note is `critic Blocker unresolved`'
names "auto-run.md: the final message lists demos and lenses" "$R" 'every `demo` statement of the spec, every lens'
FIN="$P/skills/finishing-a-development-branch/SKILL.md"
names "finishing: unverified acceptance keeps the branch" "$FIN" '`merge` also keeps when the `Acceptance QA: complete` line reports a nonzero count of'
names "finishing: failures keep the branch" "$FIN" '`fail`, `flaky` or `cannot-test`, or when the run added a deferred register'
names "finishing: a deferred statement or unresolved Blocker keeps the branch" "$FIN" 'row whose Item begins `A<n>:` or whose Note is `critic Blocker unresolved`.'
names "finishing: the final message lists demos and lenses" "$FIN" 'every `demo` statement of the spec, every lens'
printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
