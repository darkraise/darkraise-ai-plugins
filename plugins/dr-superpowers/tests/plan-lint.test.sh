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
# The lane probe reads this session's Codex gate file. A fixed session id and a
# temporary directory keep the machine's real session state out of every case.
export DR_CODEX_SESSION_DIR="$TMP/sessions" CLAUDE_CODE_SESSION_ID=plan-lint-test
lane_surface() { # lane_surface <true|false>
  mkdir -p "$DR_CODEX_SESSION_DIR"
  printf '{"session_id":"plan-lint-test","usable":true,"review":false,"lane":%s}\n' "$1" \
    > "$DR_CODEX_SESSION_DIR/plan-lint-test.json"
}
lane_surface true
# Stub rosters for the lane probe. Every case uses one, so no case depends on
# whether Codex is installed on the machine running the suite.
cat > usable.sh <<EOF
printf 'called\n' >> "$TMP/probe-calls"
echo '[{"id":"codex","usable":true,"reason":null}]'
EOF
cat > unusable.sh <<EOF
printf 'called\n' >> "$TMP/probe-calls"
echo '[{"id":"codex","usable":false,"reason":"present but not authenticated; run codex login"}]'
EOF
export PLAN_LINT_ROSTER="$TMP/unusable.sh"
calls() { cat "$TMP/probe-calls" 2>/dev/null | grep -c called; }

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
has "clean Claude plan: summary" "$out" "plan-lint: 0 errors, 2 warnings"
has "a light plan on subagent warns" "$out" "WARN header: Execution line is subagent but only 0 of 2 tasks are heavy"
lacks "a plan with no heavy task gets no delegation note" "$out" "NOTE header"
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
has "inline at total 4 needs opus" "$out" "ERROR header: inline execution with a self-implemented task at total 4 needs --model opus"
lacks "inline at total 4 passes R5" "$out" "inline execution needs every task"
lacks "double-hyphen separators and bare command parse" "$out" "Execution line does not match"
variant v9b.md 's/^\*\*Execution:\*\* .*/**Execution:** inline — `claude --model opus --effort low` — Task 2 scores 4/'
lint v9b.md
lacks "inline at total 4 on opus is clean" "$out" "ERROR header: inline"
variant v9c.md 's/^\*\*Execution:\*\* .*/**Execution:** inline — `claude --model opus --effort low` — x/; s/files 0 - spec 1 - coupling 1 - risk 2 = 4/files 1 - spec 1 - coupling 1 - risk 2 = 5/; s/impl-opus-low$/impl-opus-medium/'
lint v9c.md
has "inline that delegates needs effort high" "$out" "ERROR header: inline execution needs --effort high or above (effort low)"
lacks "a heavy minority no longer breaks inline" "$out" "inline execution needs every task"
has "inline names the delegated task" "$out" "NOTE header: delegated: Task 2 (heavy)"
variant v9c2.md 's/^\*\*Execution:\*\* .*/**Execution:** inline — `claude --model sonnet --effort high` — x/; s/files 0 - spec 1 - coupling 1 - risk 2 = 4/files 1 - spec 1 - coupling 1 - risk 2 = 5/; s/impl-opus-low$/impl-opus-medium/'
lint v9c2.md
check "a heavy minority inline at effort high: exit 0" "$status" "0"
lacks "the model follows the tasks the session implements" "$out" "needs --model opus"
lacks "a heavy minority on inline does not warn" "$out" "Execution line is inline but"
variant v9d.md 's/^\*\*Execution:\*\* .*/**Execution:** inline — `claude --model opus --effort low` — x/; s/files 0 - spec 1 - coupling 1 - risk 2 = 4/files 0 - spec 0 - coupling 1 - risk 3 = 4/'
lint v9d.md
has "risk 3 is delegated" "$out" "NOTE header: delegated: Task 2 (heavy)"
has "risk 3 inline needs effort high" "$out" "ERROR header: inline execution needs --effort high or above (effort low)"
variant v9j.md 's/^\*\*Execution:\*\* .*/**Execution:** inline — `claude --model opus --effort high` — x/; s/^\*\*Implementer:\*\* dr-superpowers:impl-opus-low$/#### Part A: left half\n\n**Files:**\n- Modify: `a.txt`\n\n**Implementer:** dr-superpowers:impl-sonnet-low\n**Evaluation:** files 0 - spec 0 - coupling 1 - risk 0 = 1\n\n#### Part B: right half\n\n**Files:**\n- Modify: `b.txt`\n\n**Implementer:** dr-superpowers:impl-opus-medium\n**Evaluation:** files 1 - spec 0 - coupling 1 - risk 3 = 5/; /^\*\*Evaluation:\*\* files 0 - spec 1 - coupling 1 - risk 2 = 4$/d; /^\*\*Approach:\*\* inline - skip 2: follows the pattern$/d'
lint v9j.md
has "a split task is heavy when one part is" "$out" "NOTE header: delegated: Task 2 (heavy)"
check "a split task with a heavy part inline at effort high: exit 0" "$status" "0"
variant v9h.md 's/^\*\*Execution:\*\* .*/**Execution:** inline — `claude --model opus --effort high` — x/; s/files 0 - spec 0 - coupling 1 - risk 0 = 1/files 1 - spec 0 - coupling 1 - risk 3 = 5/; s/impl-sonnet-low$/impl-opus-medium/; s/files 0 - spec 1 - coupling 1 - risk 2 = 4/files 1 - spec 1 - coupling 1 - risk 2 = 5/; s/impl-opus-low$/impl-opus-medium/'
lint v9h.md
has "a heavy majority on inline warns" "$out" "WARN header: Execution line is inline but 2 of 2 tasks are heavy"
variant v9i.md 's/files 0 - spec 0 - coupling 1 - risk 0 = 1/files 1 - spec 0 - coupling 1 - risk 3 = 5/; s/impl-sonnet-low$/impl-opus-medium/; s/files 0 - spec 1 - coupling 1 - risk 2 = 4/files 1 - spec 1 - coupling 1 - risk 2 = 5/; s/impl-opus-low$/impl-opus-medium/'
lint v9i.md
lacks "a heavy majority on subagent does not warn" "$out" "Execution line is subagent but"
codex_plan | sed -E 's/^\*\*Execution:\*\* subagent/**Execution:** inline/; s/risk=0; weighted routing score=3/risk=3; weighted routing score=9/' > codex-inline.md
lint codex-inline.md
has "a Codex-host inline plan keeps the old eligibility error" "$out" "ERROR header: inline execution needs every task at total <= 4 and risk < 3; fails on Task 1"
lacks "a Codex-host plan gets no delegation note" "$out" "NOTE header"

# --- R5 delegation: heavy tasks, and total-4 tasks while a third or fewer ---
ev() { # ev <total> — "<agent> <evaluation>" for a lint-clean task at that total
  case $1 in
    0) echo 'impl-haiku files 0 - spec 0 - coupling 0 - risk 0 = 0' ;;
    1) echo 'impl-sonnet-low files 0 - spec 0 - coupling 1 - risk 0 = 1' ;;
    2) echo 'impl-sonnet-medium files 0 - spec 1 - coupling 1 - risk 0 = 2' ;;
    3) echo 'impl-sonnet-high files 1 - spec 1 - coupling 1 - risk 0 = 3' ;;
    4) echo 'impl-opus-low files 0 - spec 1 - coupling 1 - risk 2 = 4' ;;
    5) echo 'impl-opus-medium files 1 - spec 1 - coupling 1 - risk 2 = 5' ;;
  esac
}
tplan() { # tplan <file> <mode> <model> <effort> <total ...> — one clean task per total
  local f=$1 mode=$2 model=$3 effort=$4 i=0 t e; shift 4
  {
    printf '# Mode Plan\n\n**Goal:** Demo.\n\n**Spec:** `docs/spec.md`\n\n'
    printf '**Execution:** %s — `claude --model %s --effort %s` — x\n\n' "$mode" "$model" "$effort"
    printf '**Plan review:** 2026-09-17 — dr-superpowers:judge-opus — executability 18 / coherence 18 / coverage 18 / assumptions 18 (round 1)\n\n'
    printf '## Global Constraints\n\n- Bash only.\n\n## Contracts\n\nNone\n\n## Assumptions (evidence)\n\n- None.\n\n## Task index\n\n'
    for t in "$@"; do i=$((i + 1)); printf '%s. Step %s\n' "$i" "$i"; done
    i=0
    for t in "$@"; do
      i=$((i + 1)); e=$(ev "$t")
      printf '\n### Task %s: Step %s\n\n**Files:**\n- Modify: `f%s.txt`\n\n**Implementer:** dr-superpowers:%s\n**Evaluation:** %s\n' \
        "$i" "$i" "$i" "${e%% *}" "${e#* }"
    done
  } > "$f"
}
tplan r1.md inline sonnet high 1 4 1 1 1 1
lint r1.md
check "one total-4 task in six on sonnet high: exit 0" "$status" "0"
has "one total-4 task in six is delegated" "$out" "NOTE header: delegated: Task 2 (total 4)"
lacks "a delegated total-4 task needs no Opus session" "$out" "needs --model opus"
tplan r2.md inline sonnet high 4 1 4 1 1 1
lint r2.md
check "two total-4 tasks in six on sonnet high: exit 0" "$status" "0"
has "two total-4 tasks in six are delegated" "$out" "NOTE header: delegated: Task 1 (total 4), Task 3 (total 4)"
tplan r3.md inline sonnet high 4 4 4 1 1 1
lint r3.md
lacks "three total-4 tasks in six are not delegated" "$out" "NOTE header"
has "a self-implemented total 4 needs Opus" "$out" "ERROR header: inline execution with a self-implemented task at total 4 needs --model opus"
tplan r4.md inline opus low 4 4 4 1 1 1
lint r4.md
check "three total-4 tasks in six on opus low: exit 0" "$status" "0"
tplan r5.md inline sonnet high 5 4 1 1 1 1
lint r5.md
check "a heavy and a total-4 task on sonnet high: exit 0" "$status" "0"
has "heavy and total-4 reasons together" "$out" "NOTE header: delegated: Task 1 (heavy), Task 2 (total 4)"
tplan r6.md inline sonnet medium 1 4 1 1 1 1
lint r6.md
has "delegating a total-4 task raises the effort to high" "$out" "ERROR header: inline execution needs --effort high or above (effort medium)"
tplan r7.md inline sonnet max 1 4 1 1 1 1
lint r7.md
check "an effort above the required one: exit 0" "$status" "0"
tplan r8.md inline sonnet medium 3 1 1 1 1 1
lint r8.md
has "a self-implemented total 3 needs effort high" "$out" "ERROR header: inline execution needs --effort high or above (effort medium)"
tplan r9.md inline sonnet low 2 1 1 1 1 1
lint r9.md
has "a self-implemented total 2 needs effort medium" "$out" "ERROR header: inline execution needs --effort medium or above (effort low)"
tplan r10.md inline sonnet low 0 0 0 0 0 0
lint r10.md
check "impl-haiku counts as low: exit 0" "$status" "0"
tplan r11.md inline haiku low 1 1
lint r11.md
has "inline on haiku is a model error" "$out" "ERROR header: inline execution needs --model sonnet or opus (model haiku)"
tplan r12.md inline fable high 1 1
lint r12.md
has "inline on fable is a model error" "$out" "ERROR header: inline execution needs --model sonnet or opus (model fable)"
tplan r13.md inline claude-opus-5 low 4 4 4 1 1 1
lint r13.md
lacks "a claude-opus model id counts as opus" "$out" "needs --model"
tplan r14.md inline claude-haiku-4-5 low 1 1
lint r14.md
has "a model id naming neither family is a model error" "$out" "ERROR header: inline execution needs --model sonnet or opus (model claude-haiku-4-5)"
tplan r15.md subagent opus high 5 5 5 5 1 1
lint r15.md
has "a subagent line at opus warns" "$out" "WARN header: subagent Execution line should be claude --model sonnet --effort high"
lacks "a heavy majority on subagent is not disputed" "$out" "Execution line is subagent but"
tplan r16.md subagent sonnet high 5 5 5 5 1 1
lint r16.md
lacks "a subagent line at sonnet high does not warn" "$out" "subagent Execution line should be"
tplan r17.md inline opus low 1 1 1 1 1 1
lint r17.md
check "opus where sonnet would do: exit 0" "$status" "0"
tplan r18.md subagent sonnet high 1 4 4 1 1 1
lint r18.md
has "total-4 tasks never count toward subagent mode" "$out" "WARN header: Execution line is subagent but only 0 of 6 tasks are heavy"

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

# --- the lazy lane probe ---
# p1 makes Task 1 lane-eligible: total 2, risk 0, no Executor, no Override.
variant p1.md 's/files 0 - spec 0 - coupling 1 - risk 0 = 1/files 0 - spec 1 - coupling 1 - risk 0 = 2/; s/impl-sonnet-low$/impl-sonnet-medium/'
export PLAN_LINT_ROSTER="$TMP/usable.sh"
rm -f probe-calls; lint p1.md
has "usable codex: an eligible task without Executor warns" "$out" "WARN Task 1: lane-eligible with no **Executor:** line (codex gpt-5.5 / medium)"
check "usable codex: the warning does not fail the lint" "$status" "0"
lacks "usable codex: a risk-2 task is not named" "$out" "WARN Task 2: lane-eligible"
check "usable codex: the probe runs once" "$(calls)" "1"
rm -f probe-calls; lint p1.md --no-probe
lacks "--no-probe: no lane warning" "$out" "lane-eligible"
check "--no-probe: the roster never runs" "$(calls)" "0"
rm -f probe-calls; lint clean.md
check "no candidate: the roster never runs" "$(calls)" "0"
lane_surface false
rm -f probe-calls; lint p1.md
lacks "lane surface off: no lane warning" "$out" "lane-eligible"
check "lane surface off: the roster never runs" "$(calls)" "0"
rm -rf "$DR_CODEX_SESSION_DIR"
rm -f probe-calls; lint p1.md
check "no session file: the roster never runs" "$(calls)" "0"
lane_surface true
export PLAN_LINT_ROSTER="$TMP/unusable.sh"
rm -f probe-calls; lint p1.md
lacks "unusable codex: no lane warning" "$out" "lane-eligible"
check "unusable codex: the probe still ran once" "$(calls)" "1"
export PLAN_LINT_ROSTER="$TMP/usable.sh"
variant p2.md 's/files 0 - spec 0 - coupling 1 - risk 0 = 1/files 0 - spec 1 - coupling 1 - risk 0 = 2/; s/impl-sonnet-low$/impl-sonnet-medium/; s/^(\*\*Evaluation:\*\* files 0 - spec 1 - coupling 1 - risk 0 = 2)$/\1\n**Executor:** codex gpt-5.5 \/ medium/; s/^(\*\*Program:\*\* .*)$/\1\n\n> **External executors:** codex/'
rm -f probe-calls; lint p2.md
lacks "an Executor line clears the candidate" "$out" "lane-eligible"
lacks "the Executor fixture is otherwise clean" "$out" "ERROR Task 1"
check "a plan whose only candidate has an Executor never probes" "$(calls)" "0"
variant p3.md 's/files 0 - spec 0 - coupling 1 - risk 0 = 1/files 0 - spec 1 - coupling 1 - risk 0 = 2/; s/impl-sonnet-low$/impl-sonnet-high/; s/^(\*\*Evaluation:\*\* files 0 - spec 1 - coupling 1 - risk 0 = 2)$/\1\n**Override:** owner kept the Sonnet-high tier/'
rm -f probe-calls; lint p3.md
lacks "an overridden task is not a candidate" "$out" "lane-eligible"
variant p4.md 's/files 0 - spec 0 - coupling 1 - risk 0 = 1/files 0 - spec 1 - coupling 1 - risk 0 = 2/; s/impl-sonnet-low$/impl-sonnet-medium/; s/^\*\*Execution:\*\* .*/**Execution:** inline — `claude --model opus --effort low` — x/'
rm -f probe-calls; lint p4.md
lacks "an inline plan gets no lane warning" "$out" "lane-eligible"
check "an inline plan never probes" "$(calls)" "0"
lint p1.md --no-probe --amendments am-none.md
check "flags parse in any order" "$status" "0"
export PLAN_LINT_ROSTER="$TMP/unusable.sh"
check "plan-amend never probes" "$(grep -c -- '--no-probe' "$HERE/../scripts/plan-amend")" "2"
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

# --- item registers ---
LREPO="$TMP/lint-registers"
git init -q -b main "$LREPO"
mkdir -p "$LREPO/docs/superpowers/plans" "$LREPO/docs/superpowers/specs" "$LREPO/docs/superpowers/registers"
: > "$LREPO/docs/superpowers/specs/s-design.md"
cat > "$LREPO/docs/superpowers/registers/r.md" <<'REG'
# R — item register

**Source:** review 2026-09-20
**Covers:** docs/superpowers/specs/s-design.md

| # | Item | Assigned | Acceptance | State | Note |
|---|---|---|---|---|---|
| 1 | Covered | docs/superpowers/plans/p.md | - | planned | - |
| 2 | Someone else's | C2 | - | planned | - |
REG

write_plan() { # write_plan <program-suffix> <items-line>
  cat > "$LREPO/docs/superpowers/plans/p.md" <<PLAN
# P Implementation Plan

**Goal:** g
**Spec:** docs/superpowers/specs/s-design.md
**Execution:** inline — \`claude --model sonnet --effort low\` — small
**Program:** \`docs/superpowers/specs/s-design.md\` — sub-project 1 of 2 — $1

## Global Constraints

None.

## Contracts

None.

## Assumptions (evidence)

- none

## Task index

1. One

---

### Task 1: One

**Files:**
- Create: \`a.txt\`

**Interfaces:**
- Consumes: nothing
- Produces: nothing
$2
**Implementer:** dr-superpowers:impl-haiku
**Evaluation:** files 0 - spec 0 - coupling 0 - risk 0 = 0

- [ ] **Step 1: Do it**

\`\`\`bash
echo hi > a.txt
\`\`\`
PLAN
}

write_plan "next: Two" "**Items:** 1"
OUT=$(cd "$LREPO" && bash "$LINT" docs/superpowers/plans/p.md --no-probe 2>&1)
lacks "plan-lint: a cited row is covered" "$OUT" "register row #1"

write_plan "next: Two" ""
OUT=$(cd "$LREPO" && bash "$LINT" docs/superpowers/plans/p.md --no-probe 2>&1)
has "plan-lint: an uncited assigned row is an error" "$OUT" \
  "ERROR header: register row #1 is assigned to this plan but no task cites it"
has "plan-lint: a plan with no Items line warns" "$OUT" \
  "WARN header: a register covers this plan's spec but no task carries an **Items:** line"

write_plan "next: Two" "**Items:** 1, 9"
OUT=$(cd "$LREPO" && bash "$LINT" docs/superpowers/plans/p.md --no-probe 2>&1)
has "plan-lint: a dangling citation is an error" "$OUT" \
  "ERROR header: **Items:** cites #9, which no covering register holds"

write_plan "last" "**Items:** 1"
OUT=$(cd "$LREPO" && bash "$LINT" docs/superpowers/plans/p.md --no-probe 2>&1)
has "plan-lint: 'last' with another sub-project's open row is an error" "$OUT" \
  "ERROR header: Program line says 'last' while register rows are open: #2"

# A plan with no covering register lints exactly as it did before.
rm "$LREPO/docs/superpowers/registers/r.md"
write_plan "last" ""
OUT=$(cd "$LREPO" && bash "$LINT" docs/superpowers/plans/p.md --no-probe 2>&1)
lacks "plan-lint: no register means no register findings" "$OUT" "register row"
lacks "plan-lint: no register means no premature-last finding" "$OUT" "register rows are open"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
