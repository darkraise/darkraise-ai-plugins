#!/usr/bin/env bash
# The line forms and template placeholders the step scripts read from the
# delegated task loop's prompts and ledger grammar.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
P="$HERE/.."
IP="$P/reference/prompts/implementer-prompt.md"
. "$HERE/fixtures/sdd-text.sh"

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
names() { # names <label> <file> <text>
  check "$1" "$(grep -qF -- "$3" "$2" 2>/dev/null && echo yes || echo no)" "yes"
}

names "the reply ends with the Report line" "$IP" '`Report: <absolute path of the report file>`'
verified=$(grep -E '^ +- `<command>` — (pass|fail): <n> passed, <m> failed$' "$IP" | sed -E 's/^ +//; s/<command>/bash t.sh/; s/<n>/3/; s/<m>/0/')
check "the prompt shows both Verified bullet forms" "$(printf '%s\n' "$verified" | grep -c .)" "2"
check "each Verified bullet form matches the stop gate's grammar" "$(printf '%s\n' "$verified" | grep -cE '^- `[^`]+` — (pass|fail)(: .*)?$')" "2"

# --- the fix loop holds two rounds (faster-plans §3) ---
names "subagent mode: the fix-round grammar" "$SDD_LEDGER" 'Task <N>: fix round R/2 (X addressed, Y open — <one-liners>; commits a..b[; re-review skipped (<n> lines)]; resumed | fresh (<why>) | escalated <old> -> <new>)'

# --- the Task check and Integration check header lines (test tiers) ---
WPR="$P/skills/writing-plans/references/task-check-line.md"
TIERS="$P/reference/test-tiers.md"
check "task check: the reference exists" "$([ -s "$WPR" ] && echo yes || echo no)" "yes"
names "test-tiers: the reference exists" "$TIERS" '# Test tiers'

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
