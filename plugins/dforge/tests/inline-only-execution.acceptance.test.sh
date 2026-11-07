#!/usr/bin/env bash
# Acceptance tests for the inline-only-execution spec
# (docs/dforge/specs/2026-11-07-inline-only-execution-design.md), statements
# A1 to A19. Each test is written from the statement's text and reaches the
# behaviour through the scripts the spec names (plan-lint, task-brief,
# task-step, next-step, plan-revise, dforge-config, plan.sh's functions) or,
# for a statement about text, the text itself. The CI half of A13 needs a
# pushed commit and is not testable here.
# Usage:
#   bash inline-only-execution.acceptance.test.sh            run every test
#   bash inline-only-execution.acceptance.test.sh A3 A9      run the named tests only
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN="$(cd "$HERE/.." && pwd)"
REPO_ROOT="$(cd "$PLUGIN/../.." && pwd)"
S="$PLUGIN/scripts"
SKILLS="$PLUGIN/skills"
REFS="$PLUGIN/reference"
ONLY=" $* "
ORIG_HOME="${HOME:-}"

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
has() { # has <name> <haystack> <needle>
  if grep -qF -- "$3" <<<"$2"; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       missing: [%s]\n       in: [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
lacks() { # lacks <name> <haystack> <needle>
  if grep -qF -- "$3" <<<"$2"; then printf 'FAIL - %s\n       unexpected: [%s]\n       in: [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1))
  else printf 'ok   - %s\n' "$1"; pass=$((pass + 1)); fi
}
matches() { # matches <name> <haystack> <ERE>
  if grep -qE -- "$3" <<<"$2"; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       no match: [%s]\n       in: [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
unmatched() { # unmatched <name> <haystack> <ERE>
  if grep -qE -- "$3" <<<"$2"; then printf 'FAIL - %s\n       unexpected match: [%s]\n       in: [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1))
  else printf 'ok   - %s\n' "$1"; pass=$((pass + 1)); fi
}
selected() { [ "$ONLY" = "  " ] || [[ "$ONLY" == *" $1 "* ]]; }

TMP="$(mktemp -d)"
if command -v cygpath >/dev/null 2>&1; then TMP=$(cygpath -m "$TMP"); fi
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME/.claude"
unset CLAUDE_CONFIG_DIR CODEX_HOME AR_SESSION DFORGE_BUDGET DR_SUPERPOWERS_BUDGET CLAUDE_PROJECT_DIR XDG_STATE_HOME
unset GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 DFORGE_NO_SETTINGS=1 MSYS_NO_PATHCONV=1
export DR_CODEX_SESSION_DIR="$TMP/codex-sessions" CLAUDE_CODE_SESSION_ID=inline-only-execution-acceptance
printf '%s\n' '#!/usr/bin/env bash' 'echo "codex-gate usable=false reason=off review=false lane=false resets_at=- source=cache"' > "$TMP/gate-stub"
export TASK_STEP_CODEX_GATE="$TMP/gate-stub"
TIMEOUT_BIN=$(command -v timeout)

# ----------------------------------------------------------------- fixtures
REPO="$TMP/repo"
git init -q "$REPO"
git -C "$REPO" config user.name t
git -C "$REPO" config user.email t@example.invalid
mkdir -p "$REPO/docs/plans"
printf '# Spec\n' > "$REPO/docs/spec.md"
g() { git -C "$REPO" "$@"; }

hdr() { # hdr <execution text> [extra header line] — a Claude plan header through the Task index
  cat <<EOF
# Demo Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: the skill the **Execution:** line names.

**Goal:** Demo.

**Spec:** \`docs/spec.md\`

**Execution:** $1

${2:+$2

}**Task check:** \`bash quick.sh\` — gate 1 has Tier: task

**Integration check:** \`bash test.sh\`

**CI:** none

**Plan review:** 2026-09-12 — dforge:judge-fable — executability 18 / coherence 18 / coverage 18 / assumptions 18 (round 1)

## Global Constraints

- Bash only.

## Contracts

None

## Assumptions (evidence)

- None.

## Task index

EOF
}
agent_for() { # the assignment table, by total
  case $1 in
    0|1|2) echo dforge:impl-sonnet-low ;;
    3|4) echo dforge:impl-sonnet-medium ;;
    5) echo dforge:impl-sonnet-high ;;
    *) echo dforge:impl-opus-high ;;
  esac
}
# plan <execution text> <spec of each task: "files spec coupling risk[ executor]">... — writes the plan on stdout
plan() {
  local exec=$1; shift
  local par=""
  if [ "${1:-}" = "--parallelism" ]; then par=$2; shift 2; fi
  hdr "$exec" "$par"
  local i=1 t
  for t in "$@"; do printf '%d. Thing %d\n' "$i" "$i"; i=$((i + 1)); done
  i=1
  local f s c r ex total
  for t in "$@"; do
    read -r f s c r ex <<<"$t"
    total=$((f + s + c + r))
    printf '\n### Task %d: Thing %d\n\n**Files:**\n- Create: `f%d.txt`\n\n' "$i" "$i" "$i"
    printf '**Implementer:** %s\n' "$(agent_for "$total")"
    [ -z "$ex" ] || printf '**Executor:** %s\n' "$ex"
    printf '**Evaluation:** files %d - spec %d - coupling %d - risk %d = %d\n\n' "$f" "$s" "$c" "$r" "$total"
    printf -- '- [ ] **Step 1: Do it**\n\n```bash\necho hi\n```\n'
    i=$((i + 1))
  done
}
HEAVY6="1 2 1 2"   # total 6, risk 2
HEAVY8="2 1 2 3"   # total 8, risk 3
T5="1 1 1 2"       # total 5
T3R3="0 0 0 3"     # total 3, risk 3
T3R2="0 1 0 2"     # total 3, risk 2
T1="0 0 1 0"       # total 1

lint() { # lint <plan> — sets lout, lrc
  lout=$(cd "$REPO" && "$TIMEOUT_BIN" 120 bash "$S/plan-lint" "$1" --no-probe 2>&1); lrc=$?
  lout=${lout//$'\r'/}
}
delegated() { (cd "$REPO" && "$TIMEOUT_BIN" 60 bash -c '. "$1"; plan_delegated "$2"' _ "$S/lib/plan.sh" "$1") 2>&1 | tr -d '\r'; }
brief() { # brief <plan> <n> <out>
  (cd "$REPO" && "$TIMEOUT_BIN" 60 bash "$S/task-brief" "$1" "$2" "$3" >/dev/null 2>&1)
}
mk() { # mk <name> <plan args...> — writes $REPO/docs/plans/<name>.md and echoes its path
  local name=$1; shift
  plan "$@" > "$REPO/docs/plans/$name.md"
  printf '%s\n' "$REPO/docs/plans/$name.md"
}
nows() { tr -s ' \t' ' ' <<<"$1"; }

# ----------------------------------------------------------------------- A1
if selected A1; then
  P=$(mk a1 'inline — claude --model opus --effort high — every task is heavy' "$HEAVY6" "$HEAVY8" "1 1 1 3")
  lint "$P"
  check "A1: all-heavy plan on inline opus/high: exit 0" "$lrc" "0"
  unmatched "A1: no WARN or ERROR on any header line" "$lout" '^(WARN|ERROR) header'
  unmatched "A1: no WARN or ERROR anywhere" "$lout" '^(WARN|ERROR) '
fi

# ----------------------------------------------------------------------- A2
if selected A2; then
  P=$(mk a2 'inline — claude --model sonnet --effort high — x' "$HEAVY6" "$T1")
  lint "$P"
  check "A2: total 6 on inline sonnet/high: exit 1" "$lrc" "1"
  matches "A2: the model-floor ERROR names the model and opus" "$lout" '^ERROR header: .*model.*opus|^ERROR header: .*opus.*model'
  P=$(mk a2b 'inline — claude --model sonnet --effort high — x' "$T5" "$T1")
  lint "$P"
  unmatched "A2: highest total 5 on sonnet/high has no header ERROR" "$lout" '^ERROR header'
  P=$(mk a2c 'inline — claude --model opus --effort high — x' "$HEAVY6" "$T1")
  lint "$P"
  unmatched "A2: highest total 6 on opus/high has no header ERROR" "$lout" '^ERROR header'
fi

# ----------------------------------------------------------------------- A3
if selected A3; then
  DEPR='WARN header: subagent execution is deprecated; inline is the default'
  P=$(mk a3a 'subagent — claude --model sonnet --effort high — x' --parallelism '**Parallelism:** sequential — one task at a time' "$T1" "$T1" "$T1")
  lint "$P"
  check "A3: subagent plan with no heavy task: exit 0" "$lrc" "0"
  has "A3: the deprecation WARN" "$lout" "$DEPR"
  unmatched "A3: no majority-rule warning (no heavy task)" "$lout" 'heavy'
  unmatched "A3: no ERROR (no heavy task)" "$lout" '^ERROR'
  P=$(mk a3b 'subagent — claude --model sonnet --effort high — x' --parallelism '**Parallelism:** sequential — one task at a time' "$HEAVY6" "$T1")
  lint "$P"
  check "A3: subagent plan with a heavy minority: exit 0" "$lrc" "0"
  has "A3: the deprecation WARN (heavy minority)" "$lout" "$DEPR"
  unmatched "A3: no majority-rule warning (heavy minority)" "$lout" 'heavy'
  unmatched "A3: no ERROR (heavy minority)" "$lout" '^ERROR'
  P=$(mk a3c 'subagent — claude --model sonnet --effort high — x' --parallelism '**Parallelism:** sequential — one task at a time' "$HEAVY6" "$HEAVY8")
  lint "$P"
  check "A3: subagent plan with every task heavy: exit 0" "$lrc" "0"
  has "A3: the deprecation WARN (all heavy)" "$lout" "$DEPR"
  unmatched "A3: no majority-rule warning (all heavy)" "$lout" 'heavy'
  unmatched "A3: no ERROR (all heavy)" "$lout" '^ERROR'
fi

# ----------------------------------------------------------------------- A4
if selected A4; then
  P=$(mk a4 'inline — claude --model opus --effort high — x' "$HEAVY6" "$T1" "$T3R3" "$HEAVY8")
  check "A4: plan_delegated prints nothing for heavy tasks without Executor lines" "$(delegated "$P")" ""
  for n in 1 3 4; do
    brief "$P" "$n" "$TMP/a4-brief-$n.md"
    [ -s "$TMP/a4-brief-$n.md" ] || printf 'FAIL - A4: task-brief wrote no brief for task %s\n' "$n"
    unmatched "A4: task $n's brief has no Dispatch: delegated line" "$(cat "$TMP/a4-brief-$n.md" 2>/dev/null)" '^\*\*Dispatch:\*\* delegated'
  done
  (cd "$REPO" && "$TIMEOUT_BIN" 60 bash "$S/task-brief" --header "$P" "$TMP/a4-header.md" >/dev/null 2>&1)
  unmatched "A4: the header has no Dispatch: delegated line" "$(cat "$TMP/a4-header.md" 2>/dev/null)" '^\*\*Dispatch:\*\* delegated'
fi

# ----------------------------------------------------------------------- A5
if selected A5; then
  P=$(mk a5 'inline — claude --model opus --effort high — x' "$HEAVY6" "$T3R3" "0 1 1 3")
  brief "$P" 2 "$TMP/a5-2.md"
  check "A5: a risk-3 task's brief has the Review line second" "$(sed -n 2p "$TMP/a5-2.md" | tr -d '\r')" '**Review:** per-task — risk 3'
  brief "$P" 3 "$TMP/a5-3.md"
  check "A5: another risk-3 task's brief has the Review line second" "$(sed -n 2p "$TMP/a5-3.md" | tr -d '\r')" '**Review:** per-task — risk 3'
  brief "$P" 1 "$TMP/a5-1.md"
  [ -s "$TMP/a5-1.md" ] || printf 'FAIL - A5: task-brief wrote no brief for task 1\n'
  unmatched "A5: a total-6 risk-2 task's brief has no Review: per-task line" "$(cat "$TMP/a5-1.md" 2>/dev/null)" '^\*\*Review:\*\* per-task'
  unmatched "A5: a total-6 risk-2 task's second line is not a Review line" "$(sed -n 2p "$TMP/a5-1.md" 2>/dev/null)" '^\*\*Review:\*\*'
fi

# ----------------------------------------------------------------------- A6
if selected A6; then
  P=$(mk a6 'inline — claude --model opus --effort high — x' "$T1 codex" "$HEAVY6 codex" "$HEAVY8" "$T1")
  check "A6: plan_delegated prints each executor task, heavy or not" "$(delegated "$P")" "$(printf '1\texecutor\n2\texecutor')"
fi

# ----------------------------------------------------------------------- A7
if selected A7; then
  out=$(cd "$REPO" && "$TIMEOUT_BIN" 60 bash "$S/dforge-config" get executionStrategy 2>&1); rc=$?
  check "A7: get executionStrategy exits 0" "$rc" "0"
  check "A7: get executionStrategy prints sequential" "$out" "sequential"
  out=$(cd "$REPO" && "$TIMEOUT_BIN" 60 bash "$S/dforge-config" workflow 2>&1); rc=$?
  check "A7: workflow exits 0" "$rc" "0"
  check "A7: workflow prints nothing" "$out" ""
fi

# ----------------------------------------------------------------------- A8
if selected A8; then
  hits=$(grep -rlE 'drafter-sonnet|scout-sonnet' "$SKILLS" "$REFS" 2>/dev/null | sed "s#^$PLUGIN/##" | sort | tr '\n' ' ')
  check "A8: no skill or reference names a drafter or scout agent" "$hits" ""
  check "A8: agents/drafter-sonnet.md does not exist" "$([ -e "$PLUGIN/agents/drafter-sonnet.md" ] && echo exists || echo absent)" "absent"
  check "A8: agents/scout-sonnet.md does not exist" "$([ -e "$PLUGIN/agents/scout-sonnet.md" ] && echo exists || echo absent)" "absent"
fi

# ----------------------------------------------------------------------- A9
if selected A9; then
  rev() { (cd "$REPO" && "$TIMEOUT_BIN" 60 bash "$S/plan-revise" "$1" 2>&1) | tr -d '\r' | grep '^recommend' | tr -s ' '; }
  P=$(mk a9a 'inline — claude --model sonnet --effort high — x' "$HEAVY6" "$T3R2")
  check "A9: hardest task total 6, no executor: opus/high, nothing delegated" "$(rev "$P")" "recommend execution=inline model=opus effort=high delegated=0/2"
  P=$(mk a9b 'inline — claude --model sonnet --effort high — x' "$T5" "$T3R2" "$HEAVY8 codex")
  check "A9: an executor task is the only one counted as delegated and does not set the pair" "$(rev "$P")" "recommend execution=inline model=sonnet effort=high delegated=1/3"
  P=$(mk a9c 'inline — claude --model sonnet --effort medium — x' "$T3R3")
  check "A9: hardest task total 3 risk 3: effort high" "$(rev "$P")" "recommend execution=inline model=sonnet effort=high delegated=0/1"
fi

# ---------------------------------------------------------------------- A10
if selected A10; then
  desc=$(tr -d '\r' < "$SKILLS/subagent-driven-development/SKILL.md" | sed -n '/^---$/,/^---$/p' | sed -n 's/^description:[ ]*//p' | head -n 1)
  matches "A10: the subagent-driven-development description starts with Deprecated" "$desc" '^"?Deprecated'
  row=$(tr -d '\r' < "$SKILLS/using-dforge/SKILL.md" | grep -E '^\|[^|]*[Ee]xecut[^|]*plan[^|]*\|' | head -n 1)
  has "A10: using-dforge's executing-a-plan row names dforge:executing-plans" "$row" 'dforge:executing-plans'
  after=${row#*dforge:executing-plans}
  before=${row%%dforge:executing-plans*}
  unmatched "A10: the row does not name subagent-driven-development ahead of executing-plans" "$before" 'subagent-driven-development'
  has "A10: the row keeps subagent mode for a plan whose line says so" "$after" 'subagent'
fi

# ---------------------------------------------------------------------- A11
if selected A11; then
  hits=$( { grep -rlE 'escalated inline -> subagent' "$SKILLS" "$REFS"; grep -rliE 'Switching to subagent mode' "$SKILLS" "$REFS"; } 2>/dev/null \
    | sed "s#^$PLUGIN/##" | grep -vE '^skills/(executing-plans/references/recovery\.md|resume-execution/|subagent-driven-development/)' | sort -u | tr '\n' ' ')
  check "A11: nothing outside the allowlist names the escalation line or the switch" "$hits" ""
  printf '# SDD ledger — plan: docs/plans/p.md\nTask 1: implementer inline (assigned; base abc1234)\nTask 3: escalated inline -> subagent — three fix rounds at or above the assigned tier\n' > "$TMP/a11-ledger.md"
  got=$(bash -c '. "$1"; ledger_left_inline "$2"' _ "$S/lib/plan.sh" "$TMP/a11-ledger.md" 2>&1 | tr -d '\r')
  check "A11: ledger_left_inline returns the task number for the old escalation line" "$got" "3"
fi

# ---------------------------------------------------------------------- A12
if selected A12; then
  codex_plan() { # codex_plan <execution pair> — one heavy task (weighted 7: astra / medium) and one light
    cat <<EOF
# Codex Demo Plan

Host: codex
Routing policy: codex-v4

**Goal:** Demo.

**Spec:** docs/spec.md

**Execution:** inline — codex $1 — native pair

**Task check:** \`bash quick.sh\` — gate 1 has Tier: task

**Integration check:** \`bash test.sh\`

**CI:** none

**Plan review:** 2026-09-12 — codex gpt-6-astra / high — executability 18 / coherence 18 / coverage 18 / assumptions 18 (round 1)

## Global Constraints

- None.

## Contracts

None

## Assumptions (evidence)

- None.

## Task index

1. One
2. Two

### Task 1: One

**Files:**
- Create: \`b.txt\`

**Implementer:** codex gpt-6.1-sol / low
**Evaluation:** files=1, spec=1, coupling=1, risk=0; weighted routing score=3
**Assignment source:** rubric

### Task 2: Two

**Files:**
- Create: \`c.txt\`

**Implementer:** codex gpt-6-astra / medium
**Evaluation:** files=1, spec=1, coupling=1, risk=2; weighted routing score=7
**Assignment source:** rubric
EOF
  }
  codex_plan 'gpt-6-astra / medium' > "$REPO/docs/plans/a12a.md"
  lint "$REPO/docs/plans/a12a.md"
  check "A12: inline Codex plan, pair at the highest score: exit 0" "$lrc" "0"
  unmatched "A12: no ERROR (pair at the highest score)" "$lout" '^ERROR'
  codex_plan 'gpt-6-astra / high' > "$REPO/docs/plans/a12b.md"
  lint "$REPO/docs/plans/a12b.md"
  check "A12: inline Codex plan, pair above the highest score: exit 0" "$lrc" "0"
  unmatched "A12: no ERROR (pair above the highest score)" "$lout" '^ERROR'
fi

# ---------------------------------------------------------------------- A13
if selected A13; then
  CLAUDE_BIN=${CLAUDE_BIN:-/root/.local/bin/claude}
  if [ -n "${DR_TEST_ALL:-}" ]; then
    printf 'skip - A13: validate-repository, claude plugin validate and claude plugin test run as their own jobs under test-all\n'
  else
    out=$(cd "$REPO_ROOT" && "$TIMEOUT_BIN" 120 node scripts/validate-repository.mjs 2>&1); rc=$?
    check "A13: node scripts/validate-repository.mjs passes" "$rc" "0"
    if [ -x "$CLAUDE_BIN" ]; then
      out=$(cd "$REPO_ROOT" && HOME="$ORIG_HOME" "$TIMEOUT_BIN" 90 "$CLAUDE_BIN" plugin validate . 2>&1); rc=$?
      check "A13: claude plugin validate passes on the marketplace" "$rc" "0"
      for p in dforge dr-status darkraise-ui darkraise-win32ui; do
        out=$(cd "$REPO_ROOT" && HOME="$ORIG_HOME" "$TIMEOUT_BIN" 90 "$CLAUDE_BIN" plugin validate "plugins/$p" 2>&1); rc=$?
        check "A13: claude plugin validate passes on plugins/$p" "$rc" "0"
      done
      out=$(cd "$REPO_ROOT" && HOME="$ORIG_HOME" "$TIMEOUT_BIN" 300 "$CLAUDE_BIN" plugin test plugins/dforge 2>&1); rc=$?
      check "A13: claude plugin test plugins/dforge passes" "$rc" "0"
    else
      printf 'skip - A13: no claude CLI at %s\n' "$CLAUDE_BIN"
    fi
  fi
  printf 'skip - A13: CI run of Validate marketplace for the pushed commit needs a push; not testable here\n'
fi

# ---------------------------------------------------------------------- A14
if selected A14; then
  P=$(mk p 'inline — claude --model opus --effort high — x' "$T5" "$T3R3")
  g add -A && g commit -qm init
  start=$(cd "$REPO" && "$TIMEOUT_BIN" 120 bash "$S/task-step" start "$P" 2 --inline 2>&1); rc=$?
  start=${start//$'\r'/}
  check "A14: task-step start 2 --inline exits 0" "$rc" "0"
  step=$(find "$REPO/.dforge" -name 'task-2-step.json' 2>/dev/null | head -n 1)
  check "A14: step state task-2-step.json is written" "$([ -n "$step" ] && echo yes || echo no)" "yes"
  ws=$(dirname "${step:-$REPO/.dforge/none}")
  check "A14: no dispatch file is written" "$(find "$REPO/.dforge" -name '*dispatch*' 2>/dev/null | wc -l | tr -d ' ')" "0"
  unmatched "A14: the ledger has no agent-named line for task 2" "$(cat "$ws/progress.md" 2>/dev/null)" '^Task 2: implementer '
  printf 'x\n' > "$REPO/f2.txt"; g add -A && g commit -qm "task 2"
  rev=$(cd "$REPO" && "$TIMEOUT_BIN" 120 bash "$S/task-step" review "$P" 2 2>&1); rc=$?
  rev=${rev//$'\r'/}
  check "A14: task-step review 2 exits 0" "$rc" "0"
  matches "A14: task-step review routes a seat" "$rev" '^seat: [^ ]*judge[^ ]*'
  L="$ws/progress.md"
  base=$(g rev-parse --short=7 HEAD~1)
  head=$(g rev-parse --short=7 HEAD)
  {
    printf '# SDD ledger — plan: docs/plans/p.md\n'
    printf 'Task 1: implementer inline (assigned; base %s)\n' "$base"
    printf 'Task 1: complete (commits %s..%s, unreviewed) — done: x; verified: bash test.sh → pass; remaining: none; discovered: none; assumptions: none\n' "$base" "$head"
    printf 'Task 2: implementer inline (assigned; base %s)\n' "$base"
    printf 'Task 2: fix round 1/2 (1 addressed, 0 open — a one-liner; commits %s..%s; session)\n' "$base" "$head"
  } > "$L"
  nx=$(cd "$REPO" && "$TIMEOUT_BIN" 60 bash "$S/next-step" "$P" 2>&1 | tr -d '\r')
  has "A14: after the fix-round line task 2 is still open" "$nx" 'Resume at Task 2'
  printf 'Task 2: complete (commits %s..%s, review clean; scores spec 3 / scope 3 / verification 3 / quality 3, seat dforge:judge-opus) — done: x; verified: bash test.sh → pass; remaining: none; discovered: none; assumptions: none\n' "$base" "$head" >> "$L"
  nx=$(cd "$REPO" && "$TIMEOUT_BIN" 60 bash "$S/next-step" "$P" 2>&1 | tr -d '\r')
  has "A14: with the reviewed complete line next-step reads every task complete" "$nx" 'all 2 tasks complete'
  unmatched "A14: next-step no longer resumes task 2" "$nx" 'Resume at Task'
fi

# ---------------------------------------------------------------------- A15
if selected A15; then
  P=$(mk a15a 'inline — claude --model sonnet --effort medium — x' "$T3R3")
  lint "$P"
  check "A15: total 3 risk 3 at effort medium: exit 1" "$lrc" "1"
  matches "A15: the effort-floor ERROR names effort high" "$lout" '^ERROR header: .*--effort high'
  P=$(mk a15b 'inline — claude --model sonnet --effort high — x' "$T3R3")
  lint "$P"
  unmatched "A15: the same plan at effort high has no header ERROR" "$lout" '^ERROR header'
  P=$(mk a15c 'inline — claude --model sonnet --effort medium — x' "$T3R2")
  lint "$P"
  unmatched "A15: total 3 risk 2 at effort medium has no header ERROR" "$lout" '^ERROR header'
fi

# ---------------------------------------------------------------------- A16
if selected A16; then
  P=$(mk a16 'inline — claude --model opus --effort high — x' "$HEAVY6" "$T1" "$T3R3" "$T5")
  (cd "$REPO" && "$TIMEOUT_BIN" 60 bash "$S/task-brief" --header "$P" "$TMP/a16-header.md" >/dev/null 2>&1)
  last=$(tr -d '\r' < "$TMP/a16-header.md" | awk 'NF { l = $0 } END { print l }')
  matches "A16: the header ends with a Heavy line" "$last" '^\*\*Heavy:\*\* '
  has "A16: the Heavy line names the total-6 task with its score" "$last" 'Task 1 (total 6, risk 2)'
  has "A16: the Heavy line names the risk-3 task" "$last" 'Task 3 (total 3, risk 3)'
  has "A16: the Heavy line names the total-5 task" "$last" 'Task 4 (total 5, risk 2)'
  unmatched "A16: the Heavy line leaves out the light task" "$last" 'Task 2'
  setup=$(tr -d '\r' < "$SKILLS/executing-plans/references/setup.md")
  para=$(awk -v RS= '/preflight/ && /\*\*Heavy:\*\*/' <<<"$setup")
  check "A16: executing-plans' setup keys its preflight item on the Heavy line" "$([ -n "$para" ] && echo yes || echo no)" "yes"
fi

# ---------------------------------------------------------------------- A17
if selected A17; then
  para=$(cat "$SKILLS"/executing-plans/SKILL.md "$SKILLS"/executing-plans/references/*.md | tr -d '\r' | awk -v RS= '/fix round 3\/3/ && /`breaker`/')
  check "A17: executing-plans names the breaker ruling for a task at fix round 3/3" "$([ -n "$para" ] && echo yes || echo no)" "yes"
  hits=$(grep -rliE 'switch(ing)? (from inline )?to subagent mode|inline to subagent mode' "$SKILLS" "$REFS" 2>/dev/null | sed "s#^$PLUGIN/##" | grep -v '^skills/subagent-driven-development/' | sort | tr '\n' ' ')
  check "A17: no skill or reference outside the deprecated skill says to switch to subagent mode" "$hits" ""
fi

# ---------------------------------------------------------------------- A18
if selected A18; then
  for skill in brainstorming using-dforge; do
    text=$(cat "$SKILLS/$skill/SKILL.md" | tr -d '\r')
    has "A18: $skill states the Process line without a mode slot" "$text" 'Process: <spike|bounded|architectural>'
    unmatched "A18: $skill names no <inline|subagent> slot" "$(cat "$SKILLS/$skill"/SKILL.md "$SKILLS/$skill"/references/*.md 2>/dev/null)" '<(inline\|subagent|subagent\|inline)>'
    unmatched "A18: $skill's Process line carries no inline or subagent word in its template" "$(grep -oE 'Process: <[^>]*>[^`]*' <<<"$text")" 'inline|subagent'
  done
fi

# ---------------------------------------------------------------------- A19
if selected A19; then
  lane=$(tr -d '\r' < "$REFS/executor-lane.md")
  matches "A19: executor-lane.md has the unavailable-executor ledger line" "$lane" 'implementer inline \(assigned; [^)]*; executor <id> unavailable - <reason>\)'
  has "A19: executor-lane.md names the handback line" "$lane" 'HANDBACK to inline'
  unmatched "A19: the unavailable-executor line names no agent in the implementer slot" "$(grep -E 'executor <id> unavailable - <reason>' <<<"$lane")" 'implementer (dforge:|impl-)'
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
