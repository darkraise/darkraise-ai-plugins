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

names "executing-plans: compact ends the turn" "$P/skills/executing-plans/SKILL.md" '`Auto run: compacting` as its last line'
R="$P/reference/auto-run.md"
names "auto-run.md: the switching line" "$R" '- `Auto run: switching` after `scripts/auto-run switch` exits 0.'

# --- the ruling ladder starts at the API rungs ---
flat() { tr '\n' ' ' < "$1" | tr -s ' '; }
PLAN_REF="$P/skills/writing-plans/references/auto-run-plan.md"
check "A31: auto-run-plan.md does not name the Opus seat" "$(grep -c 'dforge:judge-opus' "$PLAN_REF")" "0"
check "A31: auto-run-plan.md sends a planning choice up the ladder from its first rung" \
  "$(flat "$PLAN_REF" | grep -cF 'goes up the ladder in auto-run.md §Rulings, from its first rung.')" "1"
rulings=$(awk '/^## Rulings/ { f = 1; next } f && /^## / { exit } f' "$R")
line_of() { printf '%s\n' "$rulings" | grep -nF -- "$1" | head -1 | cut -d: -f1; }
pending=$(line_of '**The pending list.**')
check "A31: the Rulings section has a pending-list rung" "$([ -n "$pending" ] && echo yes || echo no)" "yes"
for rung in 'scripts/decide ask' 'scripts/run-api-judge'; do
  at=$(line_of "$rung")
  check "A31: $rung comes before the pending list" "$([ -n "$at" ] && [ "$at" -lt "${pending:-0}" ] && echo yes || echo no)" "yes"
done

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
