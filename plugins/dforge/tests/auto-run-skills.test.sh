#!/usr/bin/env bash
# The Auto run sentinel lines turn-end.sh reads, as the execution skills and auto-run.md tell a session to write them.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
P="$HERE/.."
unset CLAUDE_CONFIG_DIR CLAUDE_CODE_SESSION_ID DFORGE_BUDGET CLAUDE_PROJECT_DIR

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
  names "$skill: compact ends the turn" "$F" '`Auto run: compacting` as its last line'
done
R="$P/reference/auto-run.md"
names "auto-run.md: the switching line" "$R" '- `Auto run: switching` after `scripts/auto-run switch` exits 0.'

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
