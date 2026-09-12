#!/usr/bin/env bash
# plan-lint is the one mechanical checker for plan shape; each fixture below
# pins one finding class so a planner of any size gets the same verdict.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LINT="$HERE/../scripts/plan-lint"

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
  if grep -qF -- "$3" <<<"$2"; then printf 'FAIL - %s\n       unexpected: [%s]\n' "$1" "$3"; fail=$((fail + 1))
  else printf 'ok   - %s\n' "$1"; pass=$((pass + 1)); fi
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cd "$TMP"
mkdir -p docs
printf '# Spec\n' > docs/spec.md
printf '# Program\n' > docs/program.md

claude_plan() {
  cat <<'EOF'
# Demo Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: the skill the **Execution:** line names.

**Goal:** Demo.

**Spec:** `docs/spec.md`

**Execution:** subagent — `claude --model sonnet --effort high` — Task 2 scores 4

**Program:** `docs/program.md` — sub-project 1 of 2 — next: Second part

**Plan review:** 2026-09-12 — dr-superpowers:judge-fable — executability 18 / coherence 18 / coverage 18 / assumptions 18 (round 1)

## Global Constraints

- Bash only.

## Contracts

None

## Assumptions (evidence)

- None.

## Task index

1. First thing
2. Second thing

### Task 1: First thing

**Files:**
- Create: `a.txt`

**Implementer:** dr-superpowers:impl-sonnet-low
**Evaluation:** files 0 - spec 0 - coupling 1 - risk 0 = 1

- [ ] **Step 1: Write it**

```bash
# a fenced TODO is only a warning
echo hi
```

### Task 2: Second thing

**Files:**
- Modify: `a.txt`

**Implementer:** dr-superpowers:impl-opus-low
**Evaluation:** files 0 - spec 1 - coupling 1 - risk 2 = 4
**Approach:** inline - skip 2: follows the pattern

- [ ] **Step 1: Mark the `TODO` column**
EOF
}

codex_plan() {
  cat <<'EOF'
# Codex Demo Plan

Host: codex
Routing policy: codex-v2

**Goal:** Demo.

**Spec:** docs/spec.md

**Execution:** subagent — codex gpt-5.6-sol / high — native pair

**Plan review:** 2026-09-12 — codex gpt-6-astra / high — executability 18 / coherence 18 / coverage 18 / assumptions 18 (round 1)

## Global Constraints

- None.

## Contracts

None

## Assumptions (evidence)

- None.

## Task index

1. One

### Task 1: One

**Files:**
- Create: `b.txt`

**Implementer:** codex gpt-5.6-terra / medium
**Evaluation:** files=1, spec=1, coupling=1, risk=0; weighted routing score=3
**Assignment source:** rubric
EOF
}

lint() { # lint <file> [args...]; sets out and status
  out=$(bash "$LINT" "$@" 2>&1); status=$?
}
variant() { # variant <name> <sed expression> — the Claude plan with one edit
  claude_plan | sed -E "$2" > "$1"
}

# --- clean plans ---
claude_plan > clean.md
lint clean.md
check "clean Claude plan: exit 0" "$status" "0"
has "clean Claude plan: summary" "$out" "plan-lint: 0 errors, 1 warnings"
has "fenced TODO is a warning" "$out" "WARN Task 1: placeholder: # a fenced TODO is only a warning"
lacks "inline-code TODO is not a finding" "$out" "Mark the"
codex_plan > codex.md
lint codex.md
check "clean Codex plan: exit 0" "$status" "0"
check "clean Codex plan: summary" "$out" "plan-lint: 0 errors, 0 warnings"

# --- usage ---
lint nope.md
check "missing file: exit 2" "$status" "2"
lint clean.md --bogus x
check "bad flag: exit 2" "$status" "2"

# --- header ---
variant v1.md '/^## Contracts$/d'
lint v1.md
check "missing section: exit 1" "$status" "1"
has "missing section: named" "$out" "ERROR header: missing '## Contracts' section"
variant v2.md 's#`docs/spec.md`#`docs/nope.md`#'
lint v2.md
has "missing Spec path" "$out" "ERROR header: Spec path does not exist: docs/nope.md"
variant v3.md 's/^2\. Second thing$/2. Second/'
lint v3.md
has "index mismatch" "$out" "ERROR header: Task index does not match the task headings"
variant v4.md 's/^### Task 2: Second thing$/### Second thing (Task 2)/'
lint v4.md
has "malformed heading (Task N) suffix" "$out" "ERROR header: malformed task heading: ### Second thing (Task 2)"
variant v5.md 's/^### Task 2: Second thing$/### task 2: Second thing/'
lint v5.md
has "malformed heading lowercase" "$out" "ERROR header: malformed task heading: ### task 2: Second thing"
variant v6.md 's/^- \[ \] \*\*Step 1: Write it\*\*$/#### Step 1: Run Task 2 tests/'
lint v6.md
lacks "a step heading mentioning a task is not a finding" "$out" "malformed task heading"
variant v7.md 's/^### Task 2: Second thing$/### Task 3: Second thing/; s/^2\. Second thing$/3. Second thing/'
lint v7.md
has "non-contiguous numbers" "$out" "ERROR header: task numbers must run 1..N in order: found Task 3 at position 2"
variant v8.md 's/^\*\*Execution:\*\* .*/**Execution:** subagent — `claude --model gpt --effort high` — x/'
lint v8.md
has "Execution grammar" "$out" "ERROR header: Execution line does not match"
variant v9.md 's/^\*\*Execution:\*\* .*/**Execution:** inline -- claude --model sonnet --effort medium -- all small/'
lint v9.md
has "inline at total 4 needs opus" "$out" "ERROR header: inline execution with a task at total 4 needs --model opus (highest total 4)"
lacks "inline at total 4 passes R5" "$out" "inline execution needs every task"
lacks "double-hyphen separators and bare command parse" "$out" "Execution line does not match"
variant v9b.md 's/^\*\*Execution:\*\* .*/**Execution:** inline — `claude --model opus --effort low` — Task 2 scores 4/'
lint v9b.md
lacks "inline at total 4 on opus is clean" "$out" "ERROR header: inline"
variant v9c.md 's/^\*\*Execution:\*\* .*/**Execution:** inline — `claude --model opus --effort low` — x/; s/files 0 - spec 1 - coupling 1 - risk 2 = 4/files 1 - spec 1 - coupling 1 - risk 2 = 5/; s/impl-opus-low$/impl-opus-medium/'
lint v9c.md
has "inline breaks R5 at total 5" "$out" "ERROR header: inline execution needs every task at total <= 4 and risk < 3; fails on Task 2"
variant v9d.md 's/^\*\*Execution:\*\* .*/**Execution:** inline — `claude --model opus --effort low` — x/; s/files 0 - spec 1 - coupling 1 - risk 2 = 4/files 0 - spec 0 - coupling 1 - risk 3 = 4/'
lint v9d.md
has "inline breaks R5 at risk 3" "$out" "ERROR header: inline execution needs every task at total <= 4 and risk < 3; fails on Task 2"
variant v9e.md 's/^### Task 1: First thing$/### Task 1: -v flag/; s/^1\. First thing$/1. -v flag/'
lint v9e.md
lacks "leading punctuation in a title survives the index check" "$out" "Task index does not match"
variant v9f.md '/^## Contracts$/{N;N;s/.*/```text\n## Contracts\n```/}'
lint v9f.md
has "a fenced section heading does not count" "$out" "ERROR header: missing '## Contracts' section"
variant v9g.md 's/^\*\*Implementer:\*\* dr-superpowers:impl-opus-low$/#### Part A: left half\n\n**Files:**\n- Modify: `a.txt`\n\n**Implementer:** dr-superpowers:impl-sonnet-low\n**Evaluation:** files 0 - spec 0 - coupling 1 - risk 0 = 1\n\n#### Part B: right half\n\n**Files:**\n- Modify: `b.txt`\n\n**Implementer:** dr-superpowers:impl-sonnet-high/; /^\*\*Evaluation:\*\* files 0 - spec 1 - coupling 1 - risk 2 = 4$/d; /^\*\*Approach:\*\* inline - skip 2: follows the pattern$/d'
lint v9g.md
has "split parts: part B is missing its Evaluation" "$out" "ERROR Task 2 part B: missing **Evaluation:** line"
lacks "split parts: part A is clean" "$out" "Task 2 part A"
variant v10.md 's/^\*\*Program:\*\* .*/**Program:** `docs\/program.md` — sub-project 3 of 2 — last/'
lint v10.md
has "Program k > n" "$out" "ERROR header: Program line: sub-project 3 of 2"
variant v11.md 's/^- Bash only\.$/- Error handling is TBD./'
lint v11.md
has "prose TBD is an error" "$out" "ERROR header: placeholder: - Error handling is TBD."
variant v12.md 's/^- Bash only\.$/- Similar to Task 1./'
lint v12.md
has "similar to Task N" "$out" "ERROR header: placeholder: - Similar to Task 1."
variant v13.md 's/^- Bash only\.$/- Handle edge cases./'
lint v13.md
check "soft placeholder only warns: exit 0" "$status" "0"
has "soft placeholder" "$out" "WARN header: placeholder: - Handle edge cases."
variant v14.md '/^\*\*Plan review:\*\*/d'
lint v14.md
has "missing plan review warns" "$out" "WARN header: no **Plan review:** line yet"

# --- per task, Claude ---
variant t1.md 's/risk 2 = 4/risk 2 = 5/'
lint t1.md
has "sum mismatch" "$out" "ERROR Task 2: scores sum to 4, not 5"
variant t2.md 's/files 0 - spec 1 - coupling 1 - risk 2 = 4/files 2 - spec 1 - coupling 1 - risk 0 = 4/'
lint t2.md
has "Rule S" "$out" "ERROR Task 2: Rule S: files+spec+coupling must be below 4 and spec below 3"
variant t3.md 's/impl-opus-low$/impl-opus-medium/'
lint t3.md
has "wrong agent" "$out" "ERROR Task 2: Implementer impl-opus-medium does not match the assignment table's impl-opus-low for total 4"
variant t4.md 's/impl-opus-low$/impl-fable-high/'
lint t4.md
has "reserve name" "$out" "ERROR Task 2: impl-fable-high is a reserve tier; it needs a human **Override:**"
variant t5.md 's/impl-opus-low$/impl-fable-high/; s/^(\*\*Approach:\*\* .*)$/\1\n**Override:** owner wants Fable here/'
lint t5.md
check "Override downgrades: exit 0" "$status" "0"
has "Override downgrades to WARN" "$out" "WARN Task 2: impl-fable-high is a reserve tier"
variant t6.md 's/files 0 - spec 1 - coupling 1 - risk 2 = 4/files 1 - spec 1 - coupling 1 - risk 3 = 6/; s/impl-opus-low$/impl-opus-high/'
lint t6.md
lacks "impl-opus-high at total 6 is not a reserve finding" "$out" "reserve tier"
lacks "impl-opus-high at total 6 matches" "$out" "does not match the assignment"
variant t7.md "s/^(\*\*Implementer:\*\*) dr-superpowers:impl-sonnet-low$/\1 old-$(printf 'plug'):impl-sonnet-low/"
lint t7.md
has "legacy prefix warns" "$out" "WARN Task 1: legacy prefix 'old-plug:'"
variant t8.md 's/^\*\*Approach:\*\* .*/**Approach:** inline - follows the pattern/'
lint t8.md
has "inline Approach needs skip" "$out" "ERROR Task 2: an inline Approach must cite 'skip <n>'"
variant t9.md 's/^\*\*Approach:\*\* .*/**Approach:** gut feeling/'
lint t9.md
has "Approach grammar" "$out" "ERROR Task 2: Approach does not match"
variant t10.md 's/^(\*\*Evaluation:\*\* files 0 - spec 0 - coupling 1 - risk 0 = 1)$/\1\n**Executor:** codex gpt-5.5 \/ medium/'
lint t10.md
has "Executor below the gate" "$out" "ERROR Task 1: total 1 / risk 0 fails the lane gate (min_score 2, max_risk 1)"
has "Executor without header line" "$out" "ERROR Task 1: Executor used but the header's '> **External executors:**' line does not name codex"
variant t11.md 's/^(\*\*Approach:\*\* .*)$/\1\n**Override:** kept\n**Executor:** codex gpt-5.6-sol \/ high/'
lint t11.md
has "Executor on an overridden task" "$out" "ERROR Task 2: an Executor line on an overridden task fails the lane gate"
variant t13.md 's/files 0 - spec 1 - coupling 1 - risk 2 = 4/files 0 - spec 0 - coupling 0 - risk 4 = 4/'
lint t13.md
has "axis out of range" "$out" "ERROR Task 2: each axis must be 0-3"
variant t12.md '/^- Modify: `a.txt`$/d; s/^\*\*Files:\*\*$/Files:/'
lint t12.md
has "missing Files" "$out" "ERROR Task 2: missing **Files:** block"

# --- per task, Codex ---
codex_plan | sed 's/weighted routing score=3/weighted routing score=4/' > c1.md
lint c1.md
has "weighted score mismatch" "$out" "ERROR Task 1: weighted routing score 4 is not files+spec+coupling+2*risk = 3"
codex_plan | sed 's#gpt-5.6-terra / medium#gpt-5.6-terra / low#' > c2.md
lint c2.md
has "rank below score" "$out" "ERROR Task 1: Implementer rank 2 is below routing score 3"
codex_plan | sed 's#gpt-5.6-terra / medium#gpt-5.6-terra / high#' > c3.md
lint c3.md
check "promotion: exit 0" "$status" "0"
has "promotion warns" "$out" "WARN Task 1: Implementer rank 4 is above routing score 3 (promotion)"

# --- amendments ---
cat > am.md <<'EOF'
## A1 — Task 2
Reason: the plan picked the wrong tier
Cost if wrong: one re-dispatch
### Old
````text
**Implementer:** dr-superpowers:impl-opus-low
````
### New
````text
**Implementer:** dr-superpowers:impl-opus-medium
````
EOF
lint clean.md --amendments am.md
has "amendments applied before checks" "$out" "ERROR Task 2: Implementer impl-opus-medium does not match"
sed 's/impl-opus-low$/impl-haiku/' am.md > am-bad.md
lint clean.md --amendments am-bad.md
has "non-applying amendment" "$out" "ERROR header: amendment A1 does not apply"

# --- nested fences and CRLF ---
{ claude_plan; printf '\n````markdown\n```bash\necho x\n```\n### Task 9: inside a fixture\n````\n'; } > nested.md
lint nested.md
check "nested fence holds no task: exit 0" "$status" "0"
sed 's/$/\r/' clean.md > crlf.md
lint crlf.md
check "CRLF plan: exit 0" "$status" "0"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
