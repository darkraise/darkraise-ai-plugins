#!/usr/bin/env bash
# lane-breaker reads a plan's ledger and says whether an executor has been
# handed back from twice, which turns that executor off for the rest of the
# plan. The ledger is the only memory a resumed controller has, so every
# answer comes from it.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
P="$HERE/.."
BREAKER="$P/scripts/lane-breaker"

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
present() { # present <name> <file> <needle>
  if grep -qF -- "$3" "$2" 2>/dev/null; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       missing: [%s] in %s\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
mkdir -p "$HOME"
unset CLAUDE_CONFIG_DIR

REPO="$TMP/repo"
git init -q "$REPO"
mkdir -p "$REPO/docs" "$REPO/.dforge/sdd/plan"
printf '# Breaker Fixture Plan\n\n### Task 1: One\n\n**Files:**\n- Create: `a.txt`\n' > "$REPO/docs/plan.md"
LEDGER="$REPO/.dforge/sdd/plan/progress.md"
PLAN="$REPO/docs/plan.md"

ledger() { printf '%s\n' '# SDD ledger — plan: docs/plan.md' "$@" > "$LEDGER"; }
breaker() { bash "$BREAKER" "$PLAN" "$1" 2>&1; }

AGY1='Task 1: implementer impl-sonnet-low (assigned; base aaaaaaa; executor agy gemini-3.8-flash/medium, thread t1)'
HB1='Task 1: fix round 1/2 (0 addressed, 2 open — x; commits aaaaaaa..aaaaaaa; HANDBACK to impl-sonnet-low)'
AGY4='Task 4: implementer impl-sonnet-low (assigned; base ddddddd; executor agy claude-sonnet-5-5/medium, thread t4)'
HB4='Task 4: fix round 2/2 (0 addressed, 1 open — y; commits ddddddd..ddddddd; HANDBACK to impl-sonnet-low)'
CODEX3='Task 3: implementer impl-sonnet-low (assigned; base ccccccc; executor codex gpt-6.1-sol/low, thread t3)'
HB3='Task 3: fix round 1/2 (0 addressed, 1 open — z; commits ccccccc..ccccccc; HANDBACK to impl-sonnet-low)'

check "the script exists" "$([ -f "$BREAKER" ] && echo yes || echo no)" "yes"

rm -f "$LEDGER"
check "no ledger: open with no handbacks" "$(breaker agy)" "lane-breaker agy state=open handbacks=0"

ledger "$AGY1" "$HB1" "$HB1" 'Task 2: implementer impl-sonnet-low (assigned; base bbbbbbb; executor agy claude-sonnet-5-5/medium, thread t2)' 'Task 2: complete (commits bbbbbbb..bbbbbbb, review clean) — done: x'
check "one handed-back agy task counts once, however many lines say HANDBACK" \
  "$(breaker agy)" "lane-breaker agy state=open handbacks=1"

ledger "$AGY1" "$HB1" "$CODEX3" "$HB3"
check "another executor's handback is not agy's" "$(breaker agy)" "lane-breaker agy state=open handbacks=1"
check "and is counted for its own id" "$(breaker codex)" "lane-breaker codex state=open handbacks=1"

ledger "$AGY1" "$HB1" "$CODEX3" "$HB3" "$AGY4" "$HB4"
check "two handed-back agy tasks trip the breaker" "$(breaker agy)" "lane-breaker agy state=tripped handbacks=2"
check "codex stays open at one" "$(breaker codex)" "lane-breaker codex state=open handbacks=1"

ledger 'Task 1: implementer impl-sonnet-low (assigned; base aaaaaaa; executor codex gpt-6.1-sol/low, thread t1)' \
  'Task 1: fix round 1/2 (0 addressed, 1 open — x; commits aaaaaaa..aaaaaaa; HANDBACK to impl-sonnet-low)' \
  'Task 10: implementer impl-sonnet-low (assigned; base bbbbbbb; executor agy claude-sonnet-5-5/medium, thread t10)'
check "Task 10 is not Task 1" "$(breaker agy)" "lane-breaker agy state=open handbacks=0"

ledger 'Task 5: implementer impl-sonnet-low (assigned; base eeeeeee; executor agy unavailable - off for this plan: unreliable (2 handbacks))' \
  'Task 5: complete (commits eeeeeee..eeeeeee, review clean) — done: x'
check "a task substituted onto its Implementer is not a handback" "$(breaker agy)" "lane-breaker agy state=open handbacks=0"

# A run that fails before review (refusal, a second failed run, a gate closed
# after --refresh, a preflight exit 2) hands back on the Implementer's assigned
# line, in its <substitution> slot. The breaker paragraph that Step 3 item 3
# adds to executor-lane.md states this form, so the breaker counts it exactly
# like a round-2 HANDBACK.
INIT6='Task 6: implementer impl-sonnet-low (assigned; base fffffff; executor agy claude-sonnet-5-5/medium, thread t6)'
HB6='Task 6: implementer impl-sonnet-low (assigned; base fffffff; executor agy HANDBACK - capability failed twice)'
ledger "$INIT6" "$HB6"
check "a handback before review counts" "$(breaker agy)" "lane-breaker agy state=open handbacks=1"
ledger "$INIT6" "$HB6" "$AGY4" "$HB4"
check "a handback before review and a round-2 handback trip the breaker" "$(breaker agy)" "lane-breaker agy state=tripped handbacks=2"
present "the lane reference records a handback before review where the breaker reads it" "$P/reference/executor-lane.md" \
  'Task <N>: implementer <agent> (assigned; base <sha7>; executor <id> HANDBACK - <reason>)'

ledger 'Plan: executor agy off - unreliable (2 handbacks)'
check "the Plan line trips the breaker whatever the count" "$(breaker agy)" "lane-breaker agy state=tripped handbacks=0"
ledger 'Plan: executor codex off - unreliable (2 handbacks)'
check "a Plan line for another executor does not trip agy" "$(breaker agy)" "lane-breaker agy state=open handbacks=0"

ledger "$AGY1" "$HB1" "$AGY4" "$HB4"
sed -i 's/$/\r/' "$LEDGER"
check "a CRLF ledger reads the same" "$(breaker agy)" "lane-breaker agy state=tripped handbacks=2"

bash "$BREAKER" >/dev/null 2>&1; check "no argument exits 2" "$?" "2"
bash "$BREAKER" "$PLAN" >/dev/null 2>&1; check "no executor id exits 2" "$?" "2"
bash "$BREAKER" "$PLAN" 'Agy!' >/dev/null 2>&1; check "a malformed executor id exits 2" "$?" "2"
bash "$BREAKER" "$PLAN" agy extra >/dev/null 2>&1; check "an extra argument exits 2" "$?" "2"
bash "$BREAKER" "$REPO/docs/missing.md" agy >/dev/null 2>&1; check "a missing plan exits 2" "$?" "2"

# --- the documents that tell a controller to run it ---
EL="$P/reference/executor-lane.md"
LG="$P/skills/subagent-driven-development/references/ledger.md"
SK="$P/skills/subagent-driven-development/SKILL.md"
DT="$P/reference/delegated-task.md"
present "dispatch runs the breaker before the gate" "$EL" 'bash "<plugin-root>/scripts/lane-breaker" PLAN_FILE agy'
present "dispatch writes the plan line" "$EL" 'Plan: executor agy off - unreliable (2 handbacks)'
present "a tripped breaker dispatches the Implementer agent" "$EL" 'executor agy unavailable - off for this plan: unreliable (2 handbacks)'
present "the ledger grammar holds the plan line" "$LG" 'Plan: executor <id> off - unreliable (<k> handbacks)'
present "recovery reads the plan line through the breaker" "$LG" 'scripts/lane-breaker'
present "after compaction the breaker keeps the lane off" "$SK" 'scripts/lane-breaker'
present "the delegated loop points at the breaker" "$DT" 'scripts/lane-breaker'

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
