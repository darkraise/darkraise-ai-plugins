#!/usr/bin/env bash
# The delegated task loop, the waves, the final review and finishing call the
# step and suite scripts instead of describing their mechanics. Each call is a
# whole instruction a session follows, so each is pinned by the text that
# carries it.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
P="$HERE/.."
IP="$P/skills/subagent-driven-development/references/implementer-prompt.md"
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

# --- the group reviewer template ---
GRP="$P/skills/subagent-driven-development/references/group-reviewer-prompt.md"
check "the group reviewer template exists" "$([ -f "$GRP" ] && echo yes || echo no)" "yes"
for ph in '[GROUP_LIST]' '[PACKAGE_FILE]' '[REPORT_FILE]' '[PLUGIN_ROOT]'; do
  names "the group template carries $ph" "$GRP" "$ph"
done
names "the group template is a fenced prompt task-step can fill" "$GRP" '  prompt: |'
check "the group prompt holds no placeholder task-step does not fill" \
  "$(awk '/^  prompt: \|/ { on = 1; next } on && /^```/ { exit } on' "$GRP" 2>/dev/null | grep -oE '\[[A-Z][A-Z_]*\]' | sort -u | grep -cvxE '\[(GROUP_LIST|PACKAGE_FILE|REPORT_FILE|PLUGIN_ROOT)\]')" "0"

# --- group reviews in the loop, the ledger and the waves ---
names "the ledger grammar holds the awaiting line" "$SDD_LEDGER" 'Task <N>: awaiting group review (commits <a7>..<b7>)'
names "the ledger grammar holds the group review line" "$SDD_LEDGER" 'Group <list>: review round R/2 (Task <N>: <k> open — <one-liners> | clean; …; commits <a7>..<b7> (Task <N>)[, <a7>..<b7> (Task <M>)])'

# --- the fix loop holds two rounds (faster-plans §3) ---
names "subagent mode: the fix-round grammar" "$SDD_LEDGER" 'Task <N>: fix round R/2 (X addressed, Y open — <one-liners>; commits a..b[; re-review skipped (<n> lines)]; resumed | fresh (<why>) | escalated <old> -> <new> | HANDBACK to <agent>)'

# --- the wave check cadence (faster-plans §4) ---
WPR="$P/skills/writing-plans/references/task-check-line.md"
TIERS="$P/reference/test-tiers.md"

# --- the Task check and Integration check header lines (test tiers) ---
check "task check: the reference exists" "$([ -s "$WPR" ] && echo yes || echo no)" "yes"
names "test-tiers: the reference exists" "$TIERS" '# Test tiers'

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
