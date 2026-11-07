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

# --- summary ---
printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
