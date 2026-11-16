#!/usr/bin/env bash
# Acceptance checks for docs/dforge/specs/2026-11-07-inline-only-execution-design.md:
# the session implements every task, executor tasks still go out, and the
# subagent path is deprecated but intact.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
P="$(cd "$HERE/.." && pwd)"
S="$P/scripts"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" CODEX_HOME="$TMP/no-codex-home" DFORGE_NO_SETTINGS=1
export DR_CODEX_SESSION_DIR="$TMP/sessions" CLAUDE_CODE_SESSION_ID=inline-only-test
unset AR_SESSION CLAUDE_CONFIG_DIR
mkdir -p "$HOME" "$DR_CODEX_SESSION_DIR"
printf '{"session_id":"inline-only-test","usable":false,"review":false,"lane":false}\n' \
  > "$DR_CODEX_SESSION_DIR/inline-only-test.json"
printf 'echo %s\n' "'[{\"id\":\"codex\",\"usable\":false,\"reason\":\"test\"}]'" > "$TMP/roster.sh"
export PLAN_LINT_ROSTER="$TMP/roster.sh"
cd "$TMP"
git init -q . && git config user.email t@t && git config user.name t
mkdir -p docs && printf '# Spec\n' > docs/spec.md
git add -A && git commit -qm init

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
present() { # present <name> <file> <needle>
  if grep -qF -- "$3" "$2"; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       missing: [%s]\n       in: [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
absent() { # absent <name> <file> <needle>
  if grep -qF -- "$3" "$2"; then printf 'FAIL - %s\n       unexpected: [%s]\n       in: [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1))
  else printf 'ok   - %s\n' "$1"; pass=$((pass + 1)); fi
}
has() { # has <name> <haystack> <needle>
  if grep -qF -- "$3" <<<"$2"; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       missing: [%s]\n       in: [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
lacks() { # lacks <name> <haystack> <needle>
  if grep -qF -- "$3" <<<"$2"; then printf 'FAIL - %s\n       unexpected: [%s]\n' "$1" "$3"; fail=$((fail + 1))
  else printf 'ok   - %s\n' "$1"; pass=$((pass + 1)); fi
}
impl_for() { # impl_for <total> — the assignment table's agent
  case $1 in 0|1|2) echo impl-sonnet-low ;; 3|4) echo impl-sonnet-medium ;; 5) echo impl-sonnet-high ;; *) echo impl-opus-high ;; esac
}
io_plan() { # io_plan <execution> "<f s c r>" "<f s c r>" [<executor for Task 2>]
  local exec=$1 e1=$2 e2=$3 x=${4:-} i=0 f s c r t
  cat <<EOF
# Demo Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: the skill the **Execution:** line names.

**Goal:** Demo.

**Spec:** \`docs/spec.md\`

**Execution:** $exec

**Task check:** \`bash quick.sh\` — gate 1 has Tier: task

**Integration check:** \`bash test.sh\`

**CI:** none

**Plan review:** 2026-11-07 — dforge:judge-opus — executability 18 / coherence 18 / coverage 18 / assumptions 18 (round 1)

## Global Constraints

- Bash only.

## Contracts

None

## Assumptions (evidence)

- None.

## Task index

1. First thing
2. Second thing
EOF
  for ev in "$e1" "$e2"; do
    i=$((i + 1)); read -r f s c r <<<"$ev"; t=$((f + s + c + r))
    printf '\n### Task %s: %s thing\n\n**Files:**\n- Modify: `a%s.txt`\n\n' "$i" "$([ $i = 1 ] && echo First || echo Second)" "$i"
    printf '**Implementer:** dforge:%s\n' "$(impl_for "$t")"
    [ "$i" = 2 ] && [ -n "$x" ] && printf '**Executor:** %s\n' "$x"
    printf '**Evaluation:** files %s - spec %s - coupling %s - risk %s = %s\n\n- [ ] **Step 1: Do it**\n' "$f" "$s" "$c" "$r" "$t"
  done
}
INLINE_OPUS='inline — `claude --model opus --effort high` — x'
lint() { out=$(bash "$S/plan-lint" "$@" 2>&1); status=$?; }

# --- Task 1 ---
. "$S/lib/plan.sh"
io_plan "$INLINE_OPUS" "1 2 2 2" "0 1 1 1" > heavy.md
check "A4: a heavy task is not delegated" "$(plan_delegated heavy.md)" ""
bash "$S/task-brief" heavy.md 1 "$TMP/b1.md" > /dev/null 2>&1
absent "A4: a heavy brief carries no Dispatch line" "$TMP/b1.md" "**Dispatch:** delegated"
io_plan "$INLINE_OPUS" "0 2 1 3" "1 2 1 2" > risk3.md
bash "$S/task-brief" risk3.md 1 "$TMP/r1.md" > /dev/null 2>&1
check "A5: a risk-3 brief's second line is the review marker" "$(sed -n 2p "$TMP/r1.md")" "**Review:** per-task — risk 3"
bash "$S/task-brief" risk3.md 2 "$TMP/r2.md" > /dev/null 2>&1
check "A5: a total-6 risk-2 brief has no review marker" "$(grep -c '^\*\*Review:\*\*' "$TMP/r2.md")" "0"
io_plan "$INLINE_OPUS" "1 2 2 2" "0 1 1 0" "codex gpt-6.1-sol / low" > exec.md
check "A6: an executor task is still delegated" "$(plan_delegated exec.md | tr '\t\n' ' |')" "2 executor|"
io_plan "$INLINE_OPUS" "1 2 2 2" "1 2 2 2" "codex gpt-6.1-sol / high" > exec-heavy.md
check "A6: a heavy executor task is delegated as executor" "$(plan_delegated exec-heavy.md | tr '\t\n' ' |')" "2 executor|"
bash "$S/task-brief" --header heavy.md "$TMP/h.md" > /dev/null 2>&1
check "A16: the header names the heavy task" "$(tail -n 1 "$TMP/h.md")" "**Heavy:** Task 1 (total 7, risk 2)"
io_plan "$INLINE_OPUS" "0 1 1 0" "0 1 1 1" > light.md
bash "$S/task-brief" --header light.md "$TMP/hl.md" > /dev/null 2>&1
absent "A16: no Heavy line without a heavy task" "$TMP/hl.md" "**Heavy:**"
grep -v '^\*\*Execution:\*\*' heavy.md > noexec.md
bash "$S/task-brief" --header noexec.md "$TMP/hn.md" > /dev/null 2>&1
check "A16: a plan with no Execution line names its heavy task" "$(tail -n 1 "$TMP/hn.md")" "**Heavy:** Task 1 (total 7, risk 2)"
grep -v '^\*\*Execution:\*\*' risk3.md > noexec-r3.md
bash "$S/task-brief" noexec-r3.md 1 "$TMP/rn.md" > /dev/null 2>&1
check "A5: a plan with no Execution line marks its risk-3 task" "$(sed -n 2p "$TMP/rn.md")" "**Review:** per-task — risk 3"

# --- Task 2 ---
io_plan "$INLINE_OPUS" "1 2 2 2" "1 2 1 2" > allheavy.md
lint allheavy.md
lacks "A1: no Execution warning on an all-heavy inline plan" "$out" "WARN header: Execution"
lacks "A1: no inline error on an all-heavy inline plan" "$out" "ERROR header: inline"
io_plan 'inline — `claude --model sonnet --effort high` — x' "1 2 1 2" "0 1 1 0" > sonnet6.md
lint sonnet6.md
has "A2: total 6 on sonnet is the model-floor error" "$out" "ERROR header: inline execution needs --model opus (model sonnet)"
io_plan 'subagent — `claude --model sonnet --effort high` — x' "0 1 1 0" "0 1 1 1" > sub.md
lint sub.md
has "A3: a subagent line is deprecated" "$out" "WARN header: subagent execution is deprecated; inline is the default"
lacks "A3: no majority-rule warning" "$out" "tasks are heavy"
lacks "A3: no mode error" "$out" "ERROR header: subagent"
io_plan 'inline — `claude --model sonnet --effort medium` — x' "0 0 0 3" "0 1 1 0" > risk3m.md
lint risk3m.md
has "A15: risk 3 raises the effort floor to high" "$out" "ERROR header: inline execution needs --effort high or above (effort medium)"
io_plan 'inline — `claude --model sonnet --effort high` — x' "1 2 2 2" "0 1 1 0" > old.md
rev=$(bash "$S/plan-revise" old.md 2>&1)
has "A9: plan-revise recommends the covering pair" "$rev" "recommend  execution=inline  model=opus  effort=high  delegated=0/2"
# --- Task 3 ---
io_plan "$INLINE_OPUS" "0 2 1 3" "0 1 1 0" > loop.md
git add -A && git commit -qm plans
ws=$(bash "$S/sdd-workspace" loop.md | tail -n 1)
start_out=$(bash "$S/task-step" start loop.md 1 --inline 2>&1); start_rc=$?
check "A14: start --inline exits 0" "$start_rc" "0"
has "A14: start --inline says no dispatch file" "$start_out" "; inline, no dispatch file written"
has "A14: start --inline names the inline seat" "$start_out" "seat: inline"
check "A14: step state written" "$([ -f "$ws/task-1-step.json" ] && echo yes)" "yes"
check "A14: no dispatch file" "$([ -e "$ws/task-1-dispatch.md" ] && echo yes || echo no)" "no"
check "A14: only the identity line is written" "$(case "$(head -n 1 "$ws/progress.md")" in "# SDD ledger — plan: "*) echo yes ;; *) echo no ;; esac)" "yes"
check "A14: no task line written" "$(grep -c '^Task ' "$ws/progress.md" || true)" "0"
printf 'Task 1: implementer inline (assigned; base %s)\n' "$(git rev-parse --short=7 HEAD)" >> "$ws/progress.md"
printf 'x\n' > a1.txt && git add a1.txt && git commit -qm "task 1"
printf '# Task 1 report\n\n**Status:** DONE\n' > "$ws/task-1-report.md"
review_out=$(bash "$S/task-step" review loop.md 1 2>&1); review_rc=$?
check "A14: review routes after an inline start" "$review_rc" "0"
has "A14: review prints a seat" "$review_out" "seat: "
h7=$(git rev-parse --short=7 HEAD)
printf 'Task 1: fix round 1/2 (1 addressed, 0 open; commits %s..%s; session)\n' "$h7" "$h7" >> "$ws/progress.md"
printf 'Task 1: complete (commits %s..%s, review clean; scores spec 17 / scope 18 / verification 15 / quality 16, seat dforge:judge-opus) — done: x; verified: x; remaining: none; discovered: none; assumptions: none\n' "$h7" "$h7" >> "$ws/progress.md"
check "A14: next-step reads the session walk as complete" \
  "$(bash "$S/next-step" loop.md 2>/dev/null | grep '^\*\*Next:\*\*' | grep -c 'Task 2')" "1"
wave_out=$(bash "$S/task-step" start loop.md 2 --inline --wave 1 2>&1); wave_rc=$?
check "A14: --inline with --wave is a usage error" "$wave_rc" "2"
# --- Task 4 ---
check "A7: executionStrategy defaults to sequential" "$(bash "$S/dforge-config" get executionStrategy | tr -d '\r')" "sequential"
check "A7: the workflow line is empty at defaults" "$(bash "$S/dforge-config" workflow | tr -d '\r')" ""
present "A7: the schema says parallel needs subagent mode" "$P/config/schema.mjs" "only with a subagent Execution line"
absent "cockpit nudge: no Implementer agent for implementation" "$P/hooks/cockpit/lib.ts" "for implementation"
# --- Task 5 ---
check "A8: no drafter agent" "$([ -e "$P/agents/drafter-sonnet.md" ] && echo yes || echo no)" "no"
check "A8: no draft-pack" "$([ -e "$S/draft-pack" ] && echo yes || echo no)" "no"
# --- Task 6 ---
check "A8: no scout agent" "$([ -e "$P/agents/scout-sonnet.md" ] && echo yes || echo no)" "no"
check "codex routing has no scout floor" "$(jq -r '.role_floors.scout // "none"' < "$P/reference/codex-routing.json" | tr -d '\r')" "none"
# --- Task 7 ---
check "A17: switching.md is gone" "$([ -e "$P/skills/executing-plans/references/switching.md" ] && echo yes || echo no)" "no"
# --- Task 8 ---
EL="$P/reference/executor-lane.md"
present "A19: a handback goes to the session" "$EL" 'HANDBACK to inline'
. "$S/lib/plan.sh"
printf 'Task 1: escalated inline -> subagent — fix cap\n' > "$TMP/old-ledger.md"
check "A11: an old escalation line still parses" "$(ledger_left_inline "$TMP/old-ledger.md")" "1"
# --- Task 11 ---
for f in "$P/.claude-plugin/plugin.json" "$P/.codex-plugin/plugin.json" "$P/../../.claude-plugin/marketplace.json"; do
  absent "no tiered implementers in $f" "$f" "tiered implementers"
done
check "marketplace keyword swapped" "$(jq -r '.plugins[] | select(.name == "dforge") | .keywords | index("spec-driven") != null and index("subagents") == null' < "$P/../../.claude-plugin/marketplace.json" | tr -d '\r')" "true"
check "plugin keyword swapped" "$(jq -r '.keywords | index("spec-driven") != null and index("subagents") == null' < "$P/.claude-plugin/plugin.json" | tr -d '\r')" "true"
v=$(jq -r .version < "$P/.claude-plugin/plugin.json" | tr -d '\r')
check "version is 4.13.0 or later" "$(printf '4.13.0\n%s\n' "$v" | sort -V | head -n 1)" "4.13.0"
# --- summary ---
printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
