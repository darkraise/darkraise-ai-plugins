#!/usr/bin/env bash
# The process roles (analyst, architecture critic, QA and review lenses) live
# in skill and reference text; each check pins one whole instruction.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
P="$HERE/.."

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
names() { # names <label> <file> <text>
  check "$1" "$(grep -qF -- "$3" "$2" 2>/dev/null && echo yes || echo no)" "yes"
}

QA="$P/reference/acceptance-qa.md"
names "qa: the seat" "$QA" 'dispatches `dr-forge:impl-sonnet-high`'
names "qa: never reads the plan" "$QA" 'You may not read the plan, the'
names "qa: expectations first" "$QA" 'the spec text alone, as literal values in the test'
names "qa: test names" "$QA" 'Each test name starts with `A<n>:`'
names "qa: never fixes the code" "$QA" 'An assertion failure is a finding, which you never fix'
names "qa: detached mutation worktree" "$QA" 'git worktree add --detach [WORKSPACE]/qa-mutation HEAD'
names "qa: report path" "$QA" '`[WORKSPACE]/acceptance-report.md`'
names "qa: ambiguous result" "$QA" '`cannot-test: ambiguous`'
names "qa: rerun mode" "$QA" '`rerun`: the acceptance file may already exist'

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
