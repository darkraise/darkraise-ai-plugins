#!/usr/bin/env bash
# The delegated task loop has the controller run the full suite beside the
# review, read it through task-step verdict and complete a task only after
# verdict passes. Codex hosts and inline mode keep their own suite rules.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
P="$HERE/.."
DT="$P/reference/delegated-task.md"
NC="$P/reference/native-codex.md"
INLINE="$P/skills/executing-plans/SKILL.md"

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
in_loop() { sed '/^## The steps by hand/,$d' "$DT" | grep -cF -- "$1"; } # in_loop <text> — matching lines in the loop steps
by_hand() { sed -n '/^## The steps by hand/,/^## Recovery/p' "$DT" | grep -cF -- "$1"; }
in_loop_flat() { sed '/^## The steps by hand/,$d' "$DT" | tr -d '\r' | tr '\n' ' ' | tr -s ' ' | grep -cF -- "$1"; } # in_loop_flat <text> — the loop steps as one line, so a wrapped sentence matches
has() { check "$1" "$([ "$("$2" "$3")" -ge 1 ] && echo yes || echo no)" "yes"; } # has <label> <in_loop|in_loop_flat|by_hand> <text>

has "the start call carries --suite" in_loop "every start adds"
has "the suite command comes from the header's Integration check" in_loop '`**Integration check:**` line'
has "else from the gates file" in_loop '`<docs>/gates.md` declares'
has "else from the manifest" in_loop "from the project's manifest"
has "the first start logs a suite ruling" in_loop 'Task <N>: Ruling: suite command — <command> — none'
has "the implementer runs only focused tests" in_loop 'runs only the focused tests that cover its change'

has "the controller starts suite-run in the background" in_loop "bash <plugin-root>/scripts/suite-run -- bash -c '<suite command>'\` as a"
has "a wave task runs it from its worktree" in_loop 'a wave task: from its'
has "the review is dispatched in the same turn" in_loop 'in the same turn run'
has "verdict waits for both notifications" in_loop "only once both the seat's report and the suite's"
has "a held task starts no suite" in_loop 'A held task starts'
has "a wave's grouped tasks get no suite" in_loop "wave's merged check is their suite"
has "a group's suite starts at the last held head" in_loop "last held member's head"
has "a Codex plan starts the suite by hand" in_loop '*The steps by hand* §2 starts'
has "a fix head gets its own suite run" in_loop 'has its own suite run beside its re-review'

has "verdict reads the suite line: pass" in_loop '`suite: pass (clean|dirty)`'
has "verdict reads the suite line: red" in_loop '`suite: red (<k> failing, <b> baseline)`'
has "verdict reads the suite line: not run" in_loop '`suite: not run (<command>)`'
has "verdict reads the suite line: none recorded" in_loop '`suite: none recorded`'
has "a new failure is an Important finding" in_loop '`suite: <failing line> fails at <head7>`'
has "the base failures are reused in order" in_loop 'task-<N>-base-failures.txt'
has "the base run is bounded" in_loop 'bounded at 3600 seconds'
has "a timed-out base run is recorded" in_loop 'task-<N>-base-timeout'
has "a group is compared with its first member's base" in_loop "group's first member's base"
has "verdict is always started in the background" in_loop 'Always start `verdict` as a'
has "a baseline command runs only when the plan names it" in_loop_flat 'A `baseline` command runs only when the plan names it'
has "a plan-named command still runs unsandboxed with your rights" in_loop_flat 'A plan-named command still runs on the controller host, unsandboxed and with your rights'
has "an unnamed command stays for the ruling seat with its label" in_loop_flat 'ending ` (command not named in the plan)`'
has "review seats write only their report files" in_loop_flat 'Review seats can write only their report files'
check "the seat's text is no longer described as run verbatim" "$(in_loop_flat 'a review seat has no shell')" "0"
has "exit 7 re-runs the suite and writes no ruling" in_loop 'Exit 7 is not a seat failure'
has "--covered waits for the fix head's suite" in_loop 'only after that run'"'"'s notification is'
has "a covered skip can be refused by the suite" in_loop '`re-review: not skipped (suite <red|not run>)`'
has "a structured item is settled by task-step" in_loop 'settled by task-step check <exists|baseline> — <evidence>'
has "a task completes only after verdict passes" in_loop 'A task is marked complete only after `task-step verdict` passes'

has "by hand: the controller runs suite-run itself on a DONE report" by_hand 'On a DONE report, run'
has "by hand: suite-run takes the suite command" by_hand 'scripts/suite-run -- <suite command>'
has "by hand: a non-baseline failure is §3's Important finding" by_hand "non-baseline failure as §3's"

check "the loop steps still run date +%s once, for the cache rule" "$(in_loop 'date +%s')" "1"
check "native-codex.md carries no suite-run call" "$(grep -cF 'suite-run' "$NC")" "0"
check "inline mode keeps its full-suite-before-commit rule" "$(grep -cF 'and the full suite once before committing' "$INLINE")" "1"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
