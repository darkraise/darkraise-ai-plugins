#!/usr/bin/env bash
# writing-plans sorts tasks into alone and parallel groups, orders waves by
# dependency depth, and an auto run's plan switches in place.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
W="$HERE/../skills/writing-plans/SKILL.md"

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
names() { # names <label> <text>
  check "$1" "$(grep -qF -- "$2" "$W" && echo yes || echo no)" "yes"
}

names "two groups" '1. **Draft the tasks as usual, then sort them into two groups.**'
names "the alone group" '**alone** — a task that cannot share a wave'
names "the parallel group" '**parallel** — every other task.'
names "depth decides the order" 'Dependencies decide only the order. A task'"'"'s depth is one more than the'
names "the worked example" 'Task 6 on Tasks 3-5 give `waves — 1-2 | 3-5 | 6`. Every dependency sits in'
names "one plan in an auto run" '**One plan.** An auto run writes one plan for the whole spec and amends it'
names "the finish line is recorded" 'holds a `Finish: <action>` line, `scripts/finish-choice set <action> --plan'
names "the switch ends the turn" '`scripts/auto-run switch` and end the turn with `Auto run: switching`'
names "the handoff note" 'an auto run the session switches in place instead; see Auto run'
names "parallel is the default" 'default is `parallel`), take that value and do not ask.'
names "no split under autoRun=on" 'Under `autoRun=on` the spec covers the whole request by design: write one plan for it, never suggest a split'
check "no clear --phase is left" "$(grep -c 'clear --phase' "$W")" "0"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
