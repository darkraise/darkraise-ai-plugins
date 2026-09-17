# dr-superpowers Execution and Review Cost Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: the skill the **Execution:** line names — dr-superpowers:subagent-driven-development for `subagent`, dr-superpowers:executing-plans for `inline`. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Cut dr-superpowers' weekly-limit spend with mixed-mode inline execution, Fable reserved for critical seats, capped plan-review rounds and a 350k controller budget.

**Architecture:** Scripts compute every decision so prose never re-derives it: `lib/plan.sh` gains score, ledger and mode helpers; `task-brief` marks delegated tasks; `plan-lint` checks the new Execution rule; `review-route` routes task reviews, plan rounds and the ruling seat; `context-size --plan` picks the budget. The per-task loop moves out of subagent-driven-development into `reference/delegated-task.md`, which both execution skills run, and the skill prose is rewritten to call the scripts.

**Tech Stack:** Bash (Git Bash on Windows), awk, jq, the repository's shell test suites, Node for the one extraction script, Markdown skills.

**Spec:** `docs/superpowers/specs/2026-09-17-dr-superpowers-execution-cost-design.md`

**Execution:** inline — `claude --model opus --effort low` — every task totals 4 or less with none at risk 3; the highest total is 4 (impl-opus-low)

**Program:** `docs/superpowers/specs/2026-09-11-dr-superpowers-fork-design.md` — sub-project 10 of 10 — last

**Plan review:** 2026-09-17 — dr-superpowers:judge-opus — executability 18 / coherence 18 / coverage 18 / assumptions 17 (round 2)

## Global Constraints

- Every path below is relative to the repository root `D:/Repositories/Personal/darkraise-ai-plugins`; `P` means `plugins/dr-superpowers`.
- Scope is Claude-host plans. A plan with a `Host: codex` line keeps today's behaviour in every script.
- Heavy task: highest Evaluation total 5 or more, or highest risk 3, across the task's parts.
- Budgets: 350000 for a session running a subagent-mode plan, 475000 otherwise; `DR_SUPERPOWERS_BUDGET` overrides both.
- Plugin version becomes `1.11.0` in both `P/.claude-plugin/plugin.json` and `P/.codex-plugin/plugin.json`.
- Seat names: `dr-superpowers:judge-sonnet-high`, `dr-superpowers:judge-opus`, `dr-superpowers:judge-fable`.
- Never commit `.superpowers/`; never touch the untracked `plugins/darkmem-resume/`.
- Bound every test and CLI run with a timeout; a single suite runs as `timeout 300 bash P/tests/<suite>.test.sh`.
- Keep existing comments; add one only for a non-obvious why.
- Commit messages: `<type>(superpowers): <subject>`, subject 50 characters or fewer.

## Contracts

- **C1 `P/scripts/lib/plan.sh`** (Task 1):
  - `plan_scores FILE` prints one `N<TAB>total<TAB>risk` line per task in file order: the highest total and highest risk among the task's Claude-host `**Evaluation:**` lines outside fences. `N<TAB>-<TAB>-` when the task has none; `N<TAB>?<TAB>?` when one does not parse.
  - `plan_heavy FILE` prints the heavy task numbers, one per line, ascending.
  - `plan_ledger PLAN` prints `<toplevel>/.superpowers/sdd/<plan basename minus .md>/progress.md` when that file exists and its identity line names PLAN; nothing otherwise.
  - `ledger_left_inline LEDGER` prints the task number of the last `Task N: escalated inline -> subagent` line when no `Task M: implementer inline (assigned` line follows it; nothing otherwise.
- **C2 `P/scripts/context-size [--plan PLAN_FILE]`** (Task 3): exit 0 ok, 5 handoff, 3 unknown, 2 usage. With `--plan`, the default budget is 350000 when the plan is not `Host: codex` and either its Execution line starts `subagent` or `ledger_left_inline` on `plan_ledger` prints a task; otherwise 475000. The budget line format is unchanged. `task-brief` and `review-package` call `context-size --plan "$plan"`.
- **C3 Dispatch lines** (Task 4): when a plan is not `Host: codex` and its Execution line starts `inline`, `task-brief PLAN N` inserts `**Dispatch:** delegated — total <t>, risk <r>` as line 2 of a heavy task's brief, and `task-brief --header PLAN` appends `**Dispatch:** delegated — Task <a>, Task <b>` as the last line of the header file when any task is heavy.
- **C4 `plan-lint` rule 5** (Task 5), Claude host: `NOTE header: delegated: Task <a>, Task <b>`; `WARN header: Execution line is inline but <h> of <n> tasks are heavy`; `WARN header: Execution line is subagent but only <h> of <n> tasks are heavy`; `ERROR header: inline execution with a task at total 4 needs --model opus (highest total <t>)`; `ERROR header: inline execution that delegates needs --effort high or above (effort <e>)`. A `NOTE` is neither an error nor a warning. Codex host keeps `ERROR header: inline execution needs every task at total <= 4 and risk < 3; fails on Task<list>`.
- **C5 `P/scripts/review-route`** (Tasks 6-8):
  - `--task ID [ID ...]` prints `review-seat task=<ids> primary=<seat> fallback=<seat|-> reason=<band|risk|executor|codex-off>`; band is total 0-3 `judge-sonnet-high`, 4 and above `judge-opus`; Fable only at risk 3.
  - `--plan-round R` prints `review-seat plan-round=R primary=<seat> fallback=<seat|-> reason=<round|codex-off|cap-critical> cap=<n>`; cap 1 for a highest total of 3 or less, 2 for 4-5, 3 for 6 or more; an intricate plan (any task at risk 3 or total 6) takes `judge-fable` in round 1's Claude slot, otherwise `judge-opus`; round `cap+1` is `judge-opus` with `reason=cap-critical`; a later round, or an unparseable Evaluation line, exits 2.
  - `--ruling KIND [ID ...]` prints `review-seat ruling=<kind> tasks=<ids|plan> primary=<seat> fallback=- reason=<merge-gate|risk|intricate|routine>`; KIND is one of `preflight plan-conflict cannot-verify breaker blocked-plan codex-empty-diff final-residual`; an ID is a task number with an optional part letter and routes on its task's highest risk.
  - `plan_shape` (a function inside `review-route`, Task 7; called by Task 8) takes no arguments, reads the plan in `$src`, sets the globals `cap` (as for `--plan-round`) and `intricate` (1 when any task is at risk 3 or total 6, else 0), and dies with exit 2 on an unparseable Evaluation line.
  - A `Host: codex` plan exits 2 for every form.
- **C6 `P/reference/delegated-task.md`** (Task 9): headings `## Contract`, `## Seats`, `## 1. Dispatch the implementer`, `## 2. Handle the report`, `## 3. Review the task`, `## 4. The fix loop`, `## 5. Complete the task`, `## Recovery`.
- **C7 `[CONFIRM_NOTE]`** placeholder in `P/skills/subagent-driven-development/references/ruling-prompt.md` (Task 12).
- **C8 re-review verdicts** `REJECTION UPHELD | REJECTION DISPUTED` in `P/skills/subagent-driven-development/references/re-review-prompt.md`; the one-list fix report lists rejections as `REJECTED: <finding>` (Task 14).

## Assumptions (evidence)

- `review-route --plan-round` reads no task today: `P/scripts/review-route:51-60` (read 2026-09-17).
- `context-size` rejects any argument: `P/scripts/context-size:9` (read 2026-09-17).
- `next-step`'s escalation test is an inline grep: `P/scripts/next-step:101-107` (read 2026-09-17).
- `plan-lint`'s clean Claude fixture is a subagent plan with no heavy task, so the new mismatch warning raises its summary to 2 warnings: `P/tests/plan-lint.test.sh:61,165` (read 2026-09-17).
- `judge-opus` has the same tool grant as `judge-fable` (`Read, Grep, Glob, WebFetch`), so distilling-docs' no-Bash claim holds when it cites `agents/judge-opus.md`: `P/agents/judge-opus.md:6`, `P/agents/judge-fable.md:6` (read 2026-09-17).
- `review-route.test.sh`'s fixture Task 9 has an unparseable Evaluation line: `P/tests/review-route.test.sh:109-112` (read 2026-09-17).
- `validate-repository.mjs` checks links only under `skills/`, so `reference/delegated-task.md`'s links need their own test: `scripts/validate-repository.mjs:56-78` (read 2026-09-17).
- `P/tests/codex-review.test.sh:321-326` pins Codex-seat prose in the subagent skill that moves to `delegated-task.md` (read 2026-09-17).
- `node scripts/test-all.mjs` has one pre-existing failure, `rg: command not found` in `tests/ui-discovery.test.mjs` (darkmem, verified 2026-09-11; still listed in the 2026-09-16 handoff).
- Git Bash's `awk` is gawk, which accepts the multi-byte `—` in a regex alternation, as `next-step`'s grep already does: unverified — Task 1 verifies it.
- The split task's `Dispatch` values are the highest total and highest risk across its parts, matching how `review-route --task` already routes a task without a part letter (`P/scripts/review-route:78-85`); the spec's "heaviest part's values" is read this way.
- Mixed-ledger `next-step` test lives in `next-step.test.sh`, and the Dispatch-line tests in `inline-mode.test.sh`, as the spec's §10 names; delegated-task link checks live in `inline-mode.test.sh` beside the final-review link checks.

## Task index

1. Score, ledger and mode helpers in lib/plan.sh
2. next-step reads the shared escalation helper
3. context-size picks the budget from the plan
4. task-brief marks delegated tasks
5. plan-lint rule 5 for mixed mode
6. review-route task seats reserve Fable for risk 3
7. review-route plan rounds carry a cap
8. review-route routes the ruling seat
9. Move the per-task loop into reference/delegated-task.md
10. Task review routing prose
11. Execution line and plan review prose
12. Ruling seat prose
13. executing-plans runs mixed mode
14. Final review with one findings list
15. Remaining Fable seats, budget reference and version

---

### Task 1: Score, ledger and mode helpers in lib/plan.sh

**Files:**
- Modify: `plugins/dr-superpowers/scripts/lib/plan.sh`
- Test: `plugins/dr-superpowers/tests/plan-lib.test.sh`

**Interfaces:**
- Consumes: nothing.
- Produces: C1.

**Implementer:** dr-superpowers:impl-sonnet-high
**Evaluation:** files 1 - spec 0 - coupling 2 - risk 0 = 3

- [ ] **Step 1: Write the failing tests**

In `plugins/dr-superpowers/tests/plan-lib.test.sh`, insert this block immediately before the final two lines (`printf '\n%d passed, %d failed\n' "$pass" "$fail"` and `[ "$fail" -eq 0 ]`). Fixture lines carry a leading `|` so a plan quoting this suite still lints:

```bash
# --- plan_scores and plan_heavy ---
sed 's/^|//' > "$TMP/scores.md" <<'EOF'
|# Scores
|
|### Task 1: light
|
|**Evaluation:** files 0 - spec 0 - coupling 1 - risk 0 = 1
|
|```text
|**Evaluation:** files 3 - spec 3 - coupling 3 - risk 3 = 12
|```
|
|### Task 2: total five
|
|**Evaluation:** files 1 — spec 1 — coupling 1 — risk 2 = 5
|
|### Task 3: split
|
|#### Part A: small
|
|**Evaluation:** files 0 - spec 0 - coupling 1 - risk 0 = 1
|
|#### Part B: risky
|
|**Evaluation:** files 0 - spec 0 - coupling 1 - risk 3 = 4
|
|### Task 4: no score
|
|Body.
|
|### Task 5: broken
|
|**Evaluation:** one plus one
EOF
check "plan_scores: highest total and risk per task, fences skipped" \
  "$(plan_scores "$TMP/scores.md" | tr '\t\n' ' |')" "1 1 0|2 5 2|3 4 3|4 - -|5 ? ?|"
check "plan_heavy: total 5 or risk 3 on any part" "$(plan_heavy "$TMP/scores.md" | tr '\n' ' ')" "2 3 "
sed 's/$/\r/' "$TMP/scores.md" > "$TMP/scores-crlf.md"
check "plan_scores: CRLF" "$(plan_scores "$TMP/scores-crlf.md" | tr '\t\n' ' |')" "1 1 0|2 5 2|3 4 3|4 - -|5 ? ?|"

# --- plan_ledger and ledger_left_inline ---
REPO="$TMP/repo"
git init -q "$REPO"
mkdir -p "$REPO/docs" "$REPO/.superpowers/sdd/demo"
printf '# Demo\n' > "$REPO/docs/demo.md"
L="$REPO/.superpowers/sdd/demo/progress.md"
check "plan_ledger: no ledger prints nothing" "$(plan_ledger "$REPO/docs/demo.md")" ""
printf '# SDD ledger — plan: docs/demo.md\n' > "$L"
check "plan_ledger: a relative identity line names the plan" "$(plan_ledger "$REPO/docs/demo.md")" \
  "$(git -C "$REPO" rev-parse --show-toplevel)/.superpowers/sdd/demo/progress.md"
printf '# SDD ledger — plan: docs/other.md\n' > "$L"
check "plan_ledger: another plan's ledger is ignored" "$(plan_ledger "$REPO/docs/demo.md")" ""
printf '# SDD ledger — plan: docs/demo.md\nTask 1: implementer inline (assigned; base a)\nTask 2: escalated inline -> subagent — still failing\n' > "$L"
check "ledger_left_inline: the escalated task" "$(ledger_left_inline "$L")" "2"
printf 'Task 3: implementer inline (assigned; base b)\n' >> "$L"
check "ledger_left_inline: a later inline assignment returns" "$(ledger_left_inline "$L")" ""
printf 'Task 3: minor (deferred): the grammar says Task 4: escalated inline -> subagent — x\n' >> "$L"
check "ledger_left_inline: a quoted marker is not a switch" "$(ledger_left_inline "$L")" ""
printf 'Task 5: escalated inline -> subagent\n' | sed 's/$/\r/' >> "$L"
check "ledger_left_inline: a bare CRLF marker counts" "$(ledger_left_inline "$L")" "5"
```

- [ ] **Step 2: Run the suite to verify it fails**

Run: `timeout 300 bash plugins/dr-superpowers/tests/plan-lib.test.sh`
Expected: FAIL lines for every new case (`plan_scores: command not found` and friends), exit 1.

- [ ] **Step 3: Implement the helpers**

In `plugins/dr-superpowers/scripts/lib/plan.sh`, insert this block immediately after the closing `}` of `plan_task_text` (before the `# plan_apply_amendments PLAN AMEND` comment):

```bash
# plan_scores FILE — one "N<TAB>total<TAB>risk" line per task: the highest total
# and the highest risk among the task's Claude-host **Evaluation:** lines outside
# fences (a split task has one per part). "N<TAB>-<TAB>-" when the task has no
# Evaluation line, "N<TAB>?<TAB>?" when one does not parse.
plan_scores() {
  local sep='( — | – | - | -- )' n _title evs ev tot risk bad
  while IFS=$'\t' read -r n _title; do
    [ -n "$n" ] || continue
    evs=$(plan_task_text "$1" "$n" | awk "$_PLAN_AWK"'in_fence($0) { next } /^\*\*Evaluation:\*\*/ { print }')
    if [ -z "$evs" ]; then printf '%s\t-\t-\n' "$n"; continue; fi
    tot=-1 risk=-1 bad=0
    while IFS= read -r ev; do
      if [[ "$ev" =~ ^\*\*Evaluation:\*\*\ files\ [0-9]+$sep"spec "[0-9]+$sep"coupling "[0-9]+$sep"risk "([0-9]+)\ =\ ([0-9]+) ]]; then
        [ "${BASH_REMATCH[4]}" -le "$risk" ] || risk=${BASH_REMATCH[4]}
        [ "${BASH_REMATCH[5]}" -le "$tot" ] || tot=${BASH_REMATCH[5]}
      else
        bad=1
      fi
    done <<<"$evs"
    if [ "$bad" -eq 1 ]; then printf '%s\t?\t?\n' "$n"; else printf '%s\t%s\t%s\n' "$n" "$tot" "$risk"; fi
  done < <(plan_tasks "$1")
}

# plan_heavy FILE — the task numbers mixed mode delegates: a highest total of 5
# or more, or a highest risk of 3. One per line, ascending.
plan_heavy() {
  plan_scores "$1" | awk -F'\t' '$2 != "-" && $2 != "?" && ($2 + 0 >= 5 || $3 + 0 == 3) { print $1 }'
}

# Git reports the top level in one form (C:/… under Git Bash) whichever way the
# path was spelled, so comparing <top level>/<prefix><name> is stable where pwd
# output is not: /tmp and /c/Users/…/Temp name the same directory.
_plan_canon() {
  local dir top prefix
  dir=$(dirname "$1")
  top=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null) || return 1
  prefix=$(git -C "$dir" rev-parse --show-prefix 2>/dev/null) || return 1
  printf '%s/%s%s\n' "$top" "$prefix" "$(basename "$1")"
}

# plan_ledger PLAN — the plan's ledger file when it exists and its identity line
# names PLAN; nothing otherwise. A stale ledger under the same slug is ignored.
plan_ledger() {
  local want top file named got
  want=$(_plan_canon "$1") || return 0
  top=$(git -C "$(dirname "$1")" rev-parse --show-toplevel 2>/dev/null) || return 0
  file="$top/.superpowers/sdd/$(basename "$1" .md)/progress.md"
  [ -f "$file" ] || return 0
  named=$(ledger_plan "$file")
  [ -n "$named" ] || return 0
  if command -v cygpath >/dev/null 2>&1; then
    named=$(cygpath -u "$named" 2>/dev/null || printf '%s' "$named")
  fi
  case $named in /*) ;; *) named="$top/$named" ;; esac
  got=$(_plan_canon "$named") || return 0
  [ "$got" != "$want" ] || printf '%s\n' "$file"
  return 0
}

# ledger_left_inline LEDGER — the task number where the plan left inline mode:
# the last "escalated inline -> subagent" line with no later inline assignment.
# Nothing when the plan is in inline mode. The marker is a whole ledger line,
# never a substring of another line.
ledger_left_inline() {
  tr -d '\r' < "$1" | awk '
    /^Task [0-9]+: escalated inline -> subagent[ \t]*(—|-|$)/ { n = $2; sub(/:$/, "", n); esc = n; next }
    /^Task [0-9]+: implementer inline \(assigned/ { esc = "" }
    END { if (esc != "") print esc }
  '
}
```

- [ ] **Step 4: Run the suite to verify it passes**

Run: `timeout 300 bash plugins/dr-superpowers/tests/plan-lib.test.sh`
Expected: every line `ok`, final line `0 failed`, exit 0. The `a bare CRLF marker counts` and `the escalated task` cases passing verifies the `—` regex assumption.

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-superpowers/scripts/lib/plan.sh plugins/dr-superpowers/tests/plan-lib.test.sh
git commit -m "feat(superpowers): add score and ledger helpers"
```

### Task 2: next-step reads the shared escalation helper

**Files:**
- Modify: `plugins/dr-superpowers/scripts/next-step:101-107`
- Test: `plugins/dr-superpowers/tests/next-step.test.sh`

**Interfaces:**
- Consumes: C1 `ledger_left_inline`.
- Produces: nothing new.

**Implementer:** dr-superpowers:impl-opus-low
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 2 = 4

- [ ] **Step 1: Write the failing test**

In `plugins/dr-superpowers/tests/next-step.test.sh`, insert this block immediately after the line `lacks "returned to inline: drops the escalation sentence" "$out" "This plan escalated to subagent mode"`:

```bash

# --- a mixed ledger: a delegated task mid-loop in an inline plan ---
# Mixed mode writes subagent grammar for a delegated task. An agent-named
# assignment is not a switch, and the plan stays in inline mode.
{
  echo "# SDD ledger — plan: docs/plans/2026-01-01-inline.md"
  echo "Task 1: implementer inline (assigned; base aaaaaaa)"
  echo "Task 1: complete (commits aaaaaaa..bbbbbbb, unreviewed) — done: x; verified: y → ok; remaining: none; discovered: none; assumptions: none"
  echo "Task 2: implementer dr-superpowers:impl-opus-medium (assigned; base bbbbbbb)"
  echo "Task 2: fix round 2/5 (1 addressed, 1 open — x; commits bbbbbbb..ccccccc; progress 9 -> 12; resumed)"
} > "$INL_LEDGER/progress.md"
run "$REPO" docs/plans/2026-01-01-inline.md
has "mixed ledger: keeps the inline pair" "$out" "claude --model sonnet --effort low"
lacks "mixed ledger: no mode switch" "$out" "This plan escalated to subagent mode"
has "mixed ledger: resumes the delegated task" "$out" "Resume at Task 2 (Second)."
```

- [ ] **Step 2: Run the suite**

Run: `timeout 300 bash plugins/dr-superpowers/tests/next-step.test.sh`
Expected: the three `mixed ledger` cases pass already (the old grep also ignores agent-named lines) and the suite exits 0. This pins the behaviour before the refactor; if any case fails, stop and report it — the refactor must not be the thing that makes it pass. The existing `escalated:` cases are the ones that fail against a wrong `ledger_left_inline`.

- [ ] **Step 3: Replace the inline grep with the helper**

In `plugins/dr-superpowers/scripts/next-step`, replace exactly these lines:

```bash
      esc=$(grep -nE '^Task [0-9]+: escalated inline -> subagent[ \t]*(—|-|$)' <<<"$ledger_text" | tail -n 1 | cut -d: -f1 || true)
      if [ -n "$esc" ]; then
        back=$(grep -nE '^Task [0-9]+: implementer inline \(assigned' <<<"$ledger_text" | tail -n 1 | cut -d: -f1 || true)
        if [ -z "$back" ] || [ "$back" -lt "$esc" ]; then
          escalated_at=$(sed -n "${esc}p" <<<"$ledger_text" | sed -E 's/^Task ([0-9]+):.*/\1/')
        fi
      fi
```

with:

```bash
      escalated_at=$(ledger_left_inline "$ledger_file")
```

Keep the three comment lines above it (`# A ledger outranks the Execution line …`).

- [ ] **Step 4: Run the suites to verify they pass**

Run: `timeout 300 bash plugins/dr-superpowers/tests/next-step.test.sh && timeout 300 bash plugins/dr-superpowers/tests/project-status.test.sh`
Expected: both end `0 failed`, exit 0; the `escalated:`, `returned to inline:`, quoted-marker and `mixed ledger:` cases all pass.

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-superpowers/scripts/next-step plugins/dr-superpowers/tests/next-step.test.sh
git commit -m "refactor(superpowers): share next-step's mode test"
```

### Task 3: context-size picks the budget from the plan

**Files:**
- Modify: `plugins/dr-superpowers/scripts/context-size`
- Modify: `plugins/dr-superpowers/scripts/lib/context.sh`
- Modify: `plugins/dr-superpowers/scripts/task-brief`
- Modify: `plugins/dr-superpowers/scripts/review-package`
- Test: `plugins/dr-superpowers/tests/context-size.test.sh`
- Test: `plugins/dr-superpowers/tests/budget-line.test.sh`

**Interfaces:**
- Consumes: C1 `plan_ledger`, `ledger_left_inline`.
- Produces: C2.

**Implementer:** dr-superpowers:impl-opus-low
**Evaluation:** files 2 - spec 0 - coupling 1 - risk 1 = 4

- [ ] **Step 1: Write the failing tests**

In `plugins/dr-superpowers/tests/context-size.test.sh`, insert this block immediately after the line `check "override: line" "$out" "budget: 285k of 300k (95%) — ok — source: record"`:

```bash

# --- the plan's execution mode picks the default budget ---
mkdir -p "$REPO/docs" "$REPO/.superpowers/sdd/inl"
printf '# P\n\n**Execution:** subagent — `claude --model sonnet --effort high` — x\n\n### Task 1: One\n' > "$REPO/docs/sub.md"
printf '# P\n\n**Execution:** inline — `claude --model opus --effort low` — x\n\n### Task 1: One\n' > "$REPO/docs/inl.md"
printf 'Host: codex\n\n**Execution:** subagent — codex gpt-5.6-sol / high — x\n\n### Task 1: One\n' > "$REPO/docs/cdx.md"
run --plan docs/sub.md
check "subagent plan: 350k" "$out" "budget: 285k of 350k (81%) — ok — source: record"
run --plan docs/inl.md
check "inline plan: 475k" "$out" "budget: 285k of 475k (60%) — ok — source: record"
run --plan docs/cdx.md
check "Codex-host plan: 475k" "$out" "budget: 285k of 475k (60%) — ok — source: record"
run --plan docs/nope.md
check "missing plan: 475k" "$out" "budget: 285k of 475k (60%) — ok — source: record"
printf '# SDD ledger — plan: docs/inl.md\nTask 1: implementer inline (assigned; base a)\nTask 1: escalated inline -> subagent — still failing\n' > "$REPO/.superpowers/sdd/inl/progress.md"
run --plan docs/inl.md
check "inline plan that left inline mode: 350k" "$out" "budget: 285k of 350k (81%) — ok — source: record"
printf 'Task 1: implementer inline (assigned; base b)\n' >> "$REPO/.superpowers/sdd/inl/progress.md"
run --plan docs/inl.md
check "inline plan back in inline mode: 475k" "$out" "budget: 285k of 475k (60%) — ok — source: record"
printf '# SDD ledger — plan: docs/other.md\nTask 1: escalated inline -> subagent — x\n' > "$REPO/.superpowers/sdd/inl/progress.md"
run --plan docs/inl.md
check "another plan's ledger is ignored: 475k" "$out" "budget: 285k of 475k (60%) — ok — source: record"
DR_SUPERPOWERS_BUDGET=300000 run --plan docs/sub.md
check "override beats the plan: 300k" "$out" "budget: 285k of 300k (95%) — ok — source: record"
run --plan
check "--plan without a file: exit 2" "$status" "2"
```

In `plugins/dr-superpowers/tests/budget-line.test.sh`, insert this block immediately after the two lines

```bash
check "task-brief: budget line says handoff" "$(tail -n 1 <<<"$out")" \
  "budget: 500k of 475k (105%) — handoff — source: record"
```

```bash

# --- a subagent-mode plan: the controller's 350k budget ---
printf '# Plan\n\n**Execution:** subagent — `claude --model sonnet --effort high` — x\n\n### Task 1: Only thing\n\nBody.\n' > docs/sub.md
out=$(bash "$P/scripts/task-brief" docs/sub.md 1 2>/dev/null)
check "task-brief: a subagent plan's budget is 350k" "$(tail -n 1 <<<"$out")" \
  "budget: 500k of 350k (142%) — handoff — source: record"
out=$(bash "$P/scripts/review-package" docs/sub.md "$BASE" HEAD 2>/dev/null)
check "review-package: a subagent plan's budget is 350k" "$(tail -n 1 <<<"$out")" \
  "budget: 500k of 350k (142%) — handoff — source: record"
```

- [ ] **Step 2: Run the suites to verify they fail**

Run: `timeout 300 bash plugins/dr-superpowers/tests/context-size.test.sh; timeout 300 bash plugins/dr-superpowers/tests/budget-line.test.sh`
Expected: the new cases FAIL (`--plan` is a usage error today, and the scripts print 475k), both suites exit 1.

- [ ] **Step 3: Implement the budget choice**

In `plugins/dr-superpowers/scripts/lib/context.sh`, replace the line `CTX_DEFAULT_BUDGET=475000` with:

```bash
CTX_DEFAULT_BUDGET=475000
CTX_CONTROLLER_BUDGET=350000
```

In the same file, replace the first line of `ctx_line`'s body and the fallback line below it:

```bash
  local budget=${DR_SUPERPOWERS_BUDGET:-$CTX_DEFAULT_BUDGET} tokens bk tk pct
  case $budget in ''|*[!0-9]*) budget=$CTX_DEFAULT_BUDGET ;; esac
  [ "$budget" -gt 0 ] || budget=$CTX_DEFAULT_BUDGET
```

with:

```bash
  local fallback=${CTX_BUDGET:-$CTX_DEFAULT_BUDGET} budget tokens bk tk pct
  budget=${DR_SUPERPOWERS_BUDGET:-$fallback}
  case $budget in ''|*[!0-9]*) budget=$fallback ;; esac
  [ "$budget" -gt 0 ] || budget=$fallback
```

Append this function to the end of `plugins/dr-superpowers/scripts/lib/context.sh`:

```bash

# ctx_plan_budget PLAN — the default budget for a session running PLAN: the
# controller budget when the plan runs in subagent mode, by its Execution line
# or by a ledger that left inline mode. Needs lib/plan.sh sourced.
ctx_plan_budget() {
  local plan=$1 ledger
  if [ ! -f "$plan" ] \
     || grep -qE '^(\*\*)?Host:(\*\*)?[ \t]+codex[ \t]*$' <<<"$(plan_header "$plan")"; then
    echo "$CTX_DEFAULT_BUDGET"; return 0
  fi
  if grep -qE '^\*\*Execution:\*\*[ \t]*`?subagent' <<<"$(plan_header_line "$plan" Execution)"; then
    echo "$CTX_CONTROLLER_BUDGET"; return 0
  fi
  ledger=$(plan_ledger "$plan")
  if [ -n "$ledger" ] && [ -n "$(ledger_left_inline "$ledger")" ]; then
    echo "$CTX_CONTROLLER_BUDGET"; return 0
  fi
  echo "$CTX_DEFAULT_BUDGET"
}
```

Replace the whole of `plugins/dr-superpowers/scripts/context-size` with:

```bash
#!/usr/bin/env bash
# Print the running session's context size against the handoff budget as one
# budget line (see reference/session-budget.md).
#
# Usage: context-size [--plan PLAN_FILE]
#   --plan  the plan this session runs; a subagent-mode plan's controller hands
#           off at the lower controller budget.
# Exit: 0 ok; 5 handoff due; 3 unknown; 2 usage.
set -uo pipefail

usage() { echo "usage: context-size [--plan PLAN_FILE]" >&2; exit 2; }
plan=""
case $# in
  0) ;;
  2) [ "$1" = --plan ] || usage; plan=$2 ;;
  *) usage ;;
esac
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib/context.sh"
if [ -n "$plan" ]; then
  . "$HERE/lib/plan.sh"
  CTX_BUDGET=$(ctx_plan_budget "$plan")
fi

ctx_line
status=$?
if [ "${CTX_SOURCE:-}" = guessed ]; then
  echo "context-size: no usable session record; measured the newest transcript for this directory — a guess" >&2
fi
exit "$status"
```

In `plugins/dr-superpowers/scripts/task-brief`, replace the line `"$HERE/context-size" 2>/dev/null || true` with:

```bash
"$HERE/context-size" --plan "$plan" 2>/dev/null || true
```

In `plugins/dr-superpowers/scripts/review-package`, replace the line `"$(cd "$(dirname "$0")" && pwd)/context-size" 2>/dev/null || true` with:

```bash
"$(cd "$(dirname "$0")" && pwd)/context-size" --plan "$plan" 2>/dev/null || true
```

- [ ] **Step 4: Run the suites to verify they pass**

Run: `timeout 300 bash plugins/dr-superpowers/tests/context-size.test.sh && timeout 300 bash plugins/dr-superpowers/tests/budget-line.test.sh && timeout 300 bash plugins/dr-superpowers/tests/repo-audit.test.sh && timeout 300 bash plugins/dr-superpowers/tests/snapshot.test.sh`
Expected: all four end `0 failed`, exit 0; `usage: exit 2` (`run extra`) still passes.

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-superpowers/scripts/context-size plugins/dr-superpowers/scripts/lib/context.sh plugins/dr-superpowers/scripts/task-brief plugins/dr-superpowers/scripts/review-package plugins/dr-superpowers/tests/context-size.test.sh plugins/dr-superpowers/tests/budget-line.test.sh
git commit -m "feat(superpowers): budget controllers at 350k"
```

### Task 4: task-brief marks delegated tasks

**Files:**
- Modify: `plugins/dr-superpowers/scripts/task-brief`
- Test: `plugins/dr-superpowers/tests/inline-mode.test.sh`

**Interfaces:**
- Consumes: C1 `plan_scores`, `plan_heavy`.
- Produces: C3.

**Implementer:** dr-superpowers:impl-sonnet-high
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 1 = 3

- [ ] **Step 1: Write the failing tests**

In `plugins/dr-superpowers/tests/inline-mode.test.sh`, insert this block immediately before the final two lines (`printf '\n%d passed, %d failed\n' "$pass" "$fail"` and `[ "$fail" -eq 0 ]`):

```bash
# --- the Dispatch line: mixed mode's delegation, computed by task-brief ---
DTMP=$(mktemp -d)
sed 's/^|//' > "$DTMP/plan.md" <<'EOF'
|# Mixed
|
|**Execution:** inline — `claude --model opus --effort high` — x
|
|### Task 1: light
|
|**Evaluation:** files 0 - spec 0 - coupling 1 - risk 0 = 1
|
|### Task 2: heavy
|
|**Evaluation:** files 1 - spec 1 - coupling 1 - risk 2 = 5
|
|### Task 3: split
|
|#### Part A: small
|
|**Evaluation:** files 0 - spec 0 - coupling 1 - risk 0 = 1
|
|#### Part B: risky
|
|**Evaluation:** files 0 - spec 0 - coupling 1 - risk 3 = 4
EOF
brief() { bash "$P/scripts/task-brief" "$@" >/dev/null 2>&1; }
brief "$DTMP/plan.md" 1 "$DTMP/b1.md"
check "a light task has no Dispatch line" "$(grep -c '^\*\*Dispatch:\*\*' "$DTMP/b1.md")" "0"
brief "$DTMP/plan.md" 2 "$DTMP/b2.md"
check "a heavy task's second line is the Dispatch line" "$(sed -n 2p "$DTMP/b2.md")" "**Dispatch:** delegated — total 5, risk 2"
brief "$DTMP/plan.md" 3 "$DTMP/b3.md"
check "a split task carries its highest total and risk" "$(sed -n 2p "$DTMP/b3.md")" "**Dispatch:** delegated — total 4, risk 3"
brief --header "$DTMP/plan.md" "$DTMP/h.md"
check "the header lists the delegated tasks" "$(tail -n 1 "$DTMP/h.md")" "**Dispatch:** delegated — Task 2, Task 3"
sed 's/^\*\*Evaluation:\*\* files 1 - spec 1 - coupling 1 - risk 2 = 5$/**Evaluation:** files 0 - spec 1 - coupling 1 - risk 2 = 4/; s/risk 3 = 4$/risk 0 = 1/' "$DTMP/plan.md" > "$DTMP/light.md"
brief --header "$DTMP/light.md" "$DTMP/hl.md"
check "a plan with no heavy task has no header Dispatch line" "$(grep -c '^\*\*Dispatch:\*\*' "$DTMP/hl.md")" "0"
sed 's/inline — `claude --model opus --effort high`/subagent — `claude --model sonnet --effort high`/' "$DTMP/plan.md" > "$DTMP/sub.md"
brief "$DTMP/sub.md" 2 "$DTMP/s2.md"
check "a subagent plan has no Dispatch line" "$(grep -c '^\*\*Dispatch:\*\*' "$DTMP/s2.md")" "0"
grep -v '^\*\*Execution:\*\*' "$DTMP/plan.md" > "$DTMP/old.md"
brief "$DTMP/old.md" 2 "$DTMP/o2.md"
check "a plan with no Execution line has no Dispatch line" "$(grep -c '^\*\*Dispatch:\*\*' "$DTMP/o2.md")" "0"
{ printf 'Host: codex\n\n'; cat "$DTMP/plan.md"; } > "$DTMP/cdx.md"
brief "$DTMP/cdx.md" 2 "$DTMP/c2.md"
check "a Codex-host plan has no Dispatch line" "$(grep -c '^\*\*Dispatch:\*\*' "$DTMP/c2.md")" "0"
rm -rf "$DTMP"
```

- [ ] **Step 2: Run the suite to verify it fails**

Run: `timeout 300 bash plugins/dr-superpowers/tests/inline-mode.test.sh`
Expected: FAIL on `a heavy task's second line is the Dispatch line`, `a split task carries its highest total and risk` and `the header lists the delegated tasks`; exit 1.

- [ ] **Step 3: Implement the Dispatch lines**

In `plugins/dr-superpowers/scripts/task-brief`, replace this block:

```bash
if [ "$header" -eq 1 ]; then
  plan_header "$src" > "$out"
else
  if ! plan_task_text "$src" "$n" > "$out"; then
    echo "task ${n} not found in ${plan} (no heading matching 'Task ${n}')" >&2
    exit 3
  fi
```

with:

```bash
# Mixed mode: an inline plan delegates its heavy tasks. The line is computed
# here so an executing session never re-scores a task.
dispatch=0
if ! grep -qE '^(\*\*)?Host:(\*\*)?[ \t]+codex[ \t]*$' <<<"$(plan_header "$src")" \
   && grep -qE '^\*\*Execution:\*\*[ \t]*`?inline' <<<"$(plan_header_line "$src" Execution)"; then
  dispatch=1
fi

if [ "$header" -eq 1 ]; then
  plan_header "$src" > "$out"
  if [ "$dispatch" -eq 1 ]; then
    heavy=$(plan_heavy "$src" | awk '{ printf "%sTask %s", (NR > 1 ? ", " : ""), $1 }')
    [ -z "$heavy" ] || printf '**Dispatch:** delegated — %s\n' "$heavy" >> "$out"
  fi
else
  if ! plan_task_text "$src" "$n" > "$out"; then
    echo "task ${n} not found in ${plan} (no heading matching 'Task ${n}')" >&2
    exit 3
  fi
  if [ "$dispatch" -eq 1 ]; then
    row=$(plan_scores "$src" | awk -F'\t' -v n="$n" '$1 == n')
    t=$(cut -f2 <<<"$row") r=$(cut -f3 <<<"$row")
    if [[ "$t" =~ ^[0-9]+$ ]] && { [ "$t" -ge 5 ] || [ "$r" -eq 3 ]; }; then
      awk -v d="**Dispatch:** delegated — total $t, risk $r" 'NR == 1 { print; print d; next } { print }' "$out" > "$out.tmp"
      mv "$out.tmp" "$out"
    fi
  fi
```

- [ ] **Step 4: Run the suites to verify they pass**

Run: `timeout 300 bash plugins/dr-superpowers/tests/inline-mode.test.sh && timeout 300 bash plugins/dr-superpowers/tests/budget-line.test.sh && timeout 300 bash plugins/dr-superpowers/tests/plan-amend.test.sh`
Expected: all three end `0 failed`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-superpowers/scripts/task-brief plugins/dr-superpowers/tests/inline-mode.test.sh
git commit -m "feat(superpowers): mark delegated tasks in briefs"
```

### Task 5: plan-lint rule 5 for mixed mode

**Files:**
- Modify: `plugins/dr-superpowers/scripts/plan-lint`
- Test: `plugins/dr-superpowers/tests/plan-lint.test.sh`

**Interfaces:**
- Consumes: nothing (plan-lint parses its own units).
- Produces: C4.

**Implementer:** dr-superpowers:impl-sonnet-high
**Evaluation:** files 1 - spec 0 - coupling 0 - risk 2 = 3

- [ ] **Step 1: Write the failing tests**

In `plugins/dr-superpowers/tests/plan-lint.test.sh`, replace the line

```bash
has "clean Claude plan: summary" "$out" "plan-lint: 0 errors, 1 warnings"
```

with:

```bash
has "clean Claude plan: summary" "$out" "plan-lint: 0 errors, 2 warnings"
has "a light plan on subagent warns" "$out" "WARN header: Execution line is subagent but only 0 of 2 tasks are heavy"
lacks "a plan with no heavy task gets no delegation note" "$out" "NOTE header"
```

In the same file, replace these six lines:

```bash
variant v9c.md 's/^\*\*Execution:\*\* .*/**Execution:** inline — `claude --model opus --effort low` — x/; s/files 0 - spec 1 - coupling 1 - risk 2 = 4/files 1 - spec 1 - coupling 1 - risk 2 = 5/; s/impl-opus-low$/impl-opus-medium/'
lint v9c.md
has "inline breaks R5 at total 5" "$out" "ERROR header: inline execution needs every task at total <= 4 and risk < 3; fails on Task 2"
variant v9d.md 's/^\*\*Execution:\*\* .*/**Execution:** inline — `claude --model opus --effort low` — x/; s/files 0 - spec 1 - coupling 1 - risk 2 = 4/files 0 - spec 0 - coupling 1 - risk 3 = 4/'
lint v9d.md
has "inline breaks R5 at risk 3" "$out" "ERROR header: inline execution needs every task at total <= 4 and risk < 3; fails on Task 2"
```

with:

```bash
variant v9c.md 's/^\*\*Execution:\*\* .*/**Execution:** inline — `claude --model opus --effort low` — x/; s/files 0 - spec 1 - coupling 1 - risk 2 = 4/files 1 - spec 1 - coupling 1 - risk 2 = 5/; s/impl-opus-low$/impl-opus-medium/'
lint v9c.md
has "inline that delegates needs effort high" "$out" "ERROR header: inline execution that delegates needs --effort high or above (effort low)"
lacks "a heavy minority no longer breaks inline" "$out" "inline execution needs every task"
has "inline names the delegated task" "$out" "NOTE header: delegated: Task 2"
variant v9c2.md 's/^\*\*Execution:\*\* .*/**Execution:** inline — `claude --model sonnet --effort high` — x/; s/files 0 - spec 1 - coupling 1 - risk 2 = 4/files 1 - spec 1 - coupling 1 - risk 2 = 5/; s/impl-opus-low$/impl-opus-medium/'
lint v9c2.md
check "a heavy minority inline at effort high: exit 0" "$status" "0"
lacks "the model follows the tasks the session implements" "$out" "needs --model opus"
lacks "a heavy minority on inline does not warn" "$out" "Execution line is inline but"
variant v9d.md 's/^\*\*Execution:\*\* .*/**Execution:** inline — `claude --model opus --effort low` — x/; s/files 0 - spec 1 - coupling 1 - risk 2 = 4/files 0 - spec 0 - coupling 1 - risk 3 = 4/'
lint v9d.md
has "risk 3 is delegated" "$out" "NOTE header: delegated: Task 2"
has "risk 3 inline needs effort high" "$out" "ERROR header: inline execution that delegates needs --effort high or above (effort low)"
variant v9j.md 's/^\*\*Execution:\*\* .*/**Execution:** inline — `claude --model opus --effort high` — x/; s/^\*\*Implementer:\*\* dr-superpowers:impl-opus-low$/#### Part A: left half\n\n**Files:**\n- Modify: `a.txt`\n\n**Implementer:** dr-superpowers:impl-sonnet-low\n**Evaluation:** files 0 - spec 0 - coupling 1 - risk 0 = 1\n\n#### Part B: right half\n\n**Files:**\n- Modify: `b.txt`\n\n**Implementer:** dr-superpowers:impl-opus-medium\n**Evaluation:** files 1 - spec 0 - coupling 1 - risk 3 = 5/; /^\*\*Evaluation:\*\* files 0 - spec 1 - coupling 1 - risk 2 = 4$/d; /^\*\*Approach:\*\* inline - skip 2: follows the pattern$/d'
lint v9j.md
has "a split task is heavy when one part is" "$out" "NOTE header: delegated: Task 2"
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
```

- [ ] **Step 2: Run the suite to verify it fails**

Run: `timeout 300 bash plugins/dr-superpowers/tests/plan-lint.test.sh`
Expected: FAIL on the summary, the subagent warning, both `effort high` cases, the three `NOTE` cases (including `a split task is heavy when one part is`), `a heavy minority inline at effort high: exit 0`, `a split task with a heavy part inline at effort high: exit 0` and `a heavy majority on inline warns`; exit 1.

- [ ] **Step 3: Implement rule 5**

In `plugins/dr-superpowers/scripts/plan-lint`:

1. In the header comment, replace `# Output: "ERROR|WARN <header|Task N>: <what>" lines, then a summary line.` with `# Output: "ERROR|WARN|NOTE <header|Task N>: <what>" lines, then a summary line.`
2. Replace `mode="" exec_model=""` with `mode="" exec_model="" exec_effort=""`.
3. Replace `    mode=${BASH_REMATCH[1]} exec_model=${BASH_REMATCH[3]}` with `    mode=${BASH_REMATCH[1]} exec_model=${BASH_REMATCH[3]} exec_effort=${BASH_REMATCH[4]}`.
4. Replace `r5_bad="" max_total=0 lane=""` with `r5_bad="" max_total=0 lane="" units=""`.
5. Replace the line `  [ $((a + b + c + d)) -le "$max_total" ] || max_total=$((a + b + c + d))` with:

```bash
  [ $((a + b + c + d)) -le "$max_total" ] || max_total=$((a + b + c + d))
  units="$units$n $((a + b + c + d)) $d"$'\n'
```

6. Replace this block:

```bash
# R5: inline eligibility, and the inline model follows the highest total —
# Sonnet for the Sonnet band (<= 3), Opus once a task reaches the Opus-low band.
if [ "$mode" = inline ]; then
  if [ -n "$r5_bad" ]; then
    say ERROR header "inline execution needs every task at total <= 4 and risk < 3; fails on Task${r5_bad}"
  elif [ "$codex" -eq 0 ] && [ "$max_total" -eq 4 ] && [ "$exec_model" != opus ]; then
    say ERROR header "inline execution with a task at total 4 needs --model opus (highest total $max_total)"
  fi
fi
```

with:

```bash
# R5: execution mode. A Codex-host plan keeps the all-or-nothing inline rule.
# On Claude a heavy task (total >= 5 or risk 3, on any part) is delegated under
# inline mode, whole-plan subagent mode needs a heavy majority, the inline model
# follows the tasks the session implements itself, and a session that delegates
# runs the review loop, so its effort is at least high.
if [ "$codex" -eq 1 ]; then
  if [ "$mode" = inline ] && [ -n "$r5_bad" ]; then
    say ERROR header "inline execution needs every task at total <= 4 and risk < 3; fails on Task${r5_bad}"
  fi
elif [ -n "$mode" ]; then
  heavy=$(awk 'NF == 3 && ($2 >= 5 || $3 == 3) { print $1 }' <<<"$units" | sort -un | tr '\n' ' ')
  heavy_count=$(wc -w <<<"$heavy" | tr -d ' ')
  task_count=$(grep -c . <<<"$nums" || true)
  light_max=$(awk -v h=" $heavy" 'NF == 3 && index(h, " " $1 " ") == 0 && $2 > m { m = $2 } END { print m + 0 }' <<<"$units")
  if [ "$mode" = inline ] && [ $((2 * heavy_count)) -gt "$task_count" ]; then
    say WARN header "Execution line is inline but $heavy_count of $task_count tasks are heavy"
  elif [ "$mode" = subagent ] && [ $((2 * heavy_count)) -le "$task_count" ]; then
    say WARN header "Execution line is subagent but only $heavy_count of $task_count tasks are heavy"
  fi
  if [ "$mode" = inline ]; then
    if [ "$heavy_count" -gt 0 ]; then
      say NOTE header "delegated: $(awk '{ for (i = 1; i <= NF; i++) printf "%sTask %s", (i > 1 ? ", " : ""), $i }' <<<"$heavy")"
      case $exec_effort in low|medium)
        say ERROR header "inline execution that delegates needs --effort high or above (effort $exec_effort)" ;;
      esac
    fi
    if [ "$light_max" -eq 4 ] && [ "$exec_model" != opus ]; then
      say ERROR header "inline execution with a task at total 4 needs --model opus (highest total $light_max)"
    fi
  fi
fi
```

- [ ] **Step 4: Run the suites to verify they pass**

Run: `timeout 300 bash plugins/dr-superpowers/tests/plan-lint.test.sh && timeout 300 bash plugins/dr-superpowers/tests/native-routing.test.sh`
Expected: both end `0 failed`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-superpowers/scripts/plan-lint plugins/dr-superpowers/tests/plan-lint.test.sh
git commit -m "feat(superpowers): lint mixed-mode Execution lines"
```

### Task 6: review-route task seats reserve Fable for risk 3

**Files:**
- Modify: `plugins/dr-superpowers/scripts/review-route`
- Test: `plugins/dr-superpowers/tests/review-route.test.sh`

**Interfaces:**
- Consumes: nothing.
- Produces: C5 `--task`.

**Implementer:** dr-superpowers:impl-sonnet-high
**Evaluation:** files 1 - spec 0 - coupling 0 - risk 2 = 3

- [ ] **Step 1: Write the failing tests**

In `plugins/dr-superpowers/tests/review-route.test.sh`:

1. In the fixture heredoc, replace `|10. band five` with:

```text
|10. band five
|11. executor risk three
```

and replace the fixture's last three lines

```text
|**Implementer:** dr-superpowers:impl-opus-medium
|**Evaluation:** files 2 - spec 2 - coupling 1 - risk 0 = 5
EOF
```

with:

```text
|**Implementer:** dr-superpowers:impl-opus-medium
|**Evaluation:** files 2 - spec 2 - coupling 1 - risk 0 = 5
|
|### Task 11: executor risk three
|
|**Implementer:** dr-superpowers:impl-opus-low
|**Executor:** codex gpt-5.5 / high
|**Evaluation:** files 0 - spec 0 - coupling 1 - risk 3 = 4
EOF
```

2. Replace every line from `route --task 1` (the first occurrence, right after `check "script exists" …`) up to, but not including, the first `route --plan-round 1` line with:

```bash
route --task 1
check "total 1: light Codex, Sonnet fallback" "$out" "review-seat task=1 primary=codex:light fallback=dr-superpowers:judge-sonnet-high reason=band"
check "a routed task exits 0" "$rc" "0"
route --task 2
check "total 3 with em dashes: light Codex, Sonnet fallback" "$out" "review-seat task=2 primary=codex:light fallback=dr-superpowers:judge-sonnet-high reason=band"
route --task 3
check "total 4 at risk 1: heavy Codex, Opus fallback" "$out" "review-seat task=3 primary=codex:heavy fallback=dr-superpowers:judge-opus reason=band"
route --task 4
check "risk 2 takes its band: heavy Codex, Opus fallback" "$out" "review-seat task=4 primary=codex:heavy fallback=dr-superpowers:judge-opus reason=band"
route --task 5
check "an Executor task is reviewed by its band judge, never Codex" "$out" "review-seat task=5 primary=dr-superpowers:judge-sonnet-high fallback=- reason=executor"
route --task 6
check "an Executor task at risk 2 takes its band" "$out" "review-seat task=6 primary=dr-superpowers:judge-sonnet-high fallback=- reason=executor"
route --task 11
check "an Executor task at risk 3 goes to Fable alone" "$out" "review-seat task=11 primary=dr-superpowers:judge-fable fallback=- reason=executor"
route --task 7A
check "a part routes on its own Evaluation" "$out" "review-seat task=7A primary=codex:light fallback=dr-superpowers:judge-sonnet-high reason=band"
route --task 7B
check "the risk-2 part takes heavy Codex" "$out" "review-seat task=7B primary=codex:heavy fallback=dr-superpowers:judge-opus reason=band"
route --task 7
check "a split task without a part routes on its heaviest part" "$out" "review-seat task=7 primary=codex:heavy fallback=dr-superpowers:judge-opus reason=band"
route --task 8
check "risk 3 goes to Astra then Fable" "$out" "review-seat task=8 primary=codex:heavy+judge-fable fallback=dr-superpowers:judge-fable reason=risk"
route --task 10
check "total 5 at risk 0: heavy Codex, Opus fallback" "$out" "review-seat task=10 primary=codex:heavy fallback=dr-superpowers:judge-opus reason=band"

route --task 1 2
check "a batch takes its highest total" "$out" "review-seat task=1,2 primary=codex:light fallback=dr-superpowers:judge-sonnet-high reason=band"
route --task 1 3
check "a batch crossing into the heavy band" "$out" "review-seat task=1,3 primary=codex:heavy fallback=dr-superpowers:judge-opus reason=band"
route --task 1 5
check "one Executor task makes the whole batch Claude-reviewed" "$out" "review-seat task=1,5 primary=dr-superpowers:judge-sonnet-high fallback=- reason=executor"

```

3. Replace every line from `review_surface false` up to, but not including, the next `route --plan-round 1` line with:

```bash
review_surface false
route --task 1
check "codex off: total 1 goes to Sonnet alone" "$out" "review-seat task=1 primary=dr-superpowers:judge-sonnet-high fallback=- reason=codex-off"
check "codex off: a routed task still exits 0" "$rc" "0"
route --task 2
check "codex off: total 3 goes to Sonnet alone" "$out" "review-seat task=2 primary=dr-superpowers:judge-sonnet-high fallback=- reason=codex-off"
route --task 3
check "codex off: total 4 goes to Opus alone" "$out" "review-seat task=3 primary=dr-superpowers:judge-opus fallback=- reason=codex-off"
route --task 10
check "codex off: total 5 goes to Opus alone" "$out" "review-seat task=10 primary=dr-superpowers:judge-opus fallback=- reason=codex-off"
route --task 4
check "codex off: risk 2 at total 4 takes its band" "$out" "review-seat task=4 primary=dr-superpowers:judge-opus fallback=- reason=codex-off"
route --task 8
check "codex off: risk 3 goes to Fable alone" "$out" "review-seat task=8 primary=dr-superpowers:judge-fable fallback=- reason=codex-off"
route --task 7
check "codex off: a split task routes on its heaviest part" "$out" "review-seat task=7 primary=dr-superpowers:judge-opus fallback=- reason=codex-off"
route --task 1 2
check "codex off: a batch takes its highest total" "$out" "review-seat task=1,2 primary=dr-superpowers:judge-sonnet-high fallback=- reason=codex-off"
route --task 5
check "codex off: an Executor task is unchanged" "$out" "review-seat task=5 primary=dr-superpowers:judge-sonnet-high fallback=- reason=executor"
route --task 6
check "codex off: an Executor task at risk 2 is unchanged" "$out" "review-seat task=6 primary=dr-superpowers:judge-sonnet-high fallback=- reason=executor"
```

4. Replace `check "a CRLF plan routes" "$out" "review-seat task=4 primary=codex:heavy+judge-fable fallback=dr-superpowers:judge-fable reason=risk"` with `check "a CRLF plan routes" "$out" "review-seat task=4 primary=codex:heavy fallback=dr-superpowers:judge-opus reason=band"`.

- [ ] **Step 2: Run the suite to verify it fails**

Run: `timeout 300 bash plugins/dr-superpowers/tests/review-route.test.sh`
Expected: FAIL on the changed rows (task 2, 4, 5, 6, 7, 7B, 10 and the batches, on and off; task 11 already routes to Fable and passes); exit 1.

- [ ] **Step 3: Implement the new rows**

In `plugins/dr-superpowers/scripts/review-route`, replace this block:

```bash
band() { # band <total> - the Claude judge for a score band
  if [ "$1" -le 1 ]; then echo "$SONNET"
  elif [ "$1" -le 4 ]; then echo "$OPUS"
  else echo "$FABLE"
  fi
}

# Executor first: a task Codex implemented is never reviewed by Codex, whatever
# its risk. Totals 5 and 6 carry risk >= 2 under Rule S, so the risk row catches
# them before the band rows; the band rows still cover an overridden task.
if [ "$executor" -eq 1 ] && [ "$max_risk" -ge 2 ]; then
  primary=$FABLE fallback=- reason=executor
elif [ "$executor" -eq 1 ]; then
  primary=$(band "$max_total") fallback=- reason=executor
elif ! codex_session_on review; then
  # Codex is off for this session, so the Codex rows name their Claude seat
  # directly, and there is nothing left to fall back to. Risk stays with Fable.
  if [ "$max_risk" -ge 2 ]; then primary=$FABLE; else primary=$(band "$max_total"); fi
  fallback=- reason=codex-off
elif [ "$max_risk" -ge 2 ]; then
```

with:

```bash
band() { # band <total> - the Claude judge for a score band
  if [ "$1" -le 3 ]; then echo "$SONNET"
  else echo "$OPUS"
  fi
}

# Executor first: a task Codex implemented is never reviewed by Codex, whatever
# its risk. Fable is kept for risk 3 (security, data loss, migration,
# concurrency); every other task takes its band. The lane gate admits risk <= 1,
# so the executor risk-3 row is a guard.
if [ "$executor" -eq 1 ] && [ "$max_risk" -ge 3 ]; then
  primary=$FABLE fallback=- reason=executor
elif [ "$executor" -eq 1 ]; then
  primary=$(band "$max_total") fallback=- reason=executor
elif ! codex_session_on review; then
  # Codex is off for this session, so the Codex rows name their Claude seat
  # directly, and there is nothing left to fall back to. Risk 3 stays with Fable.
  if [ "$max_risk" -ge 3 ]; then primary=$FABLE; else primary=$(band "$max_total"); fi
  fallback=- reason=codex-off
elif [ "$max_risk" -ge 3 ]; then
```

- [ ] **Step 4: Run the suite to verify it passes**

Run: `timeout 300 bash plugins/dr-superpowers/tests/review-route.test.sh`
Expected: `0 failed`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-superpowers/scripts/review-route plugins/dr-superpowers/tests/review-route.test.sh
git commit -m "feat(superpowers): Fable reviews risk 3 tasks"
```

### Task 7: review-route plan rounds carry a cap

**Files:**
- Modify: `plugins/dr-superpowers/scripts/review-route`
- Test: `plugins/dr-superpowers/tests/review-route.test.sh`

**Interfaces:**
- Consumes: C1 `plan_scores`.
- Produces: C5 `--plan-round`, and the `plan_shape` function Task 8 calls.

**Implementer:** dr-superpowers:impl-opus-low
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 2 = 4

- [ ] **Step 1: Write the failing tests**

In `plugins/dr-superpowers/tests/review-route.test.sh`:

1. Immediately after the `route()` function (its closing `}` line), insert:

```bash
rround() { # rround <plan> <round>; sets out and rc
  out=$(bash "$ROUTE" "$1" --plan-round "$2" 2>"$TMP/err"); rc=$?
}
shape_plan() { # shape_plan <file> <evaluation line>... - one task per line
  local f=$1 i=0 ev; shift
  { printf '# Shape\n\n'
    for ev in "$@"; do i=$((i + 1)); printf '### Task %s: t\n\n%s\n\n' "$i" "$ev"; done
  } > "$f"
}
# Plan rounds parse every task, so they run on the fixture without Task 9.
awk '/^### Task 9:/ { skip = 1 } /^### Task 10:/ { skip = 0 } !skip' "$TMP/plan.md" | grep -v '^9\. broken$' > "$TMP/round.md"
shape_plan "$TMP/light.md" '**Evaluation:** files 0 - spec 0 - coupling 1 - risk 2 = 3' '**Evaluation:** files 0 - spec 0 - coupling 1 - risk 0 = 1'
shape_plan "$TMP/mid.md" '**Evaluation:** files 1 - spec 1 - coupling 1 - risk 2 = 5' '**Evaluation:** files 0 - spec 0 - coupling 1 - risk 0 = 1'
```

2. Replace these six lines:

```bash
route --plan-round 1
check "plan round 1 is Codex with a Fable fallback" "$out" "review-seat plan-round=1 primary=codex:plan fallback=dr-superpowers:judge-fable reason=round"
route --plan-round 2
check "plan round 2 is Opus" "$out" "review-seat plan-round=2 primary=dr-superpowers:judge-opus fallback=- reason=round"
route --plan-round 3
check "plan round 3 is Opus" "$out" "review-seat plan-round=3 primary=dr-superpowers:judge-opus fallback=- reason=round"
```

with:

```bash
rround "$TMP/round.md" 1
check "an intricate plan's round 1 is Codex with a Fable fallback, cap 3" "$out" "review-seat plan-round=1 primary=codex:plan fallback=dr-superpowers:judge-fable reason=round cap=3"
rround "$TMP/light.md" 1
check "a plain plan's round 1 falls back to Opus, cap 1" "$out" "review-seat plan-round=1 primary=codex:plan fallback=dr-superpowers:judge-opus reason=round cap=1"
rround "$TMP/light.md" 2
check "cap 1: round 2 is the cap-critical round" "$out" "review-seat plan-round=2 primary=dr-superpowers:judge-opus fallback=- reason=cap-critical cap=1"
rround "$TMP/light.md" 3
check "cap 1: round 3 exits 2" "$rc" "2"
rround "$TMP/mid.md" 2
check "highest total 5: round 2 is within cap 2" "$out" "review-seat plan-round=2 primary=dr-superpowers:judge-opus fallback=- reason=round cap=2"
rround "$TMP/mid.md" 3
check "cap 2: round 3 is cap-critical" "$out" "review-seat plan-round=3 primary=dr-superpowers:judge-opus fallback=- reason=cap-critical cap=2"
rround "$TMP/round.md" 3
check "cap 3: round 3 is a round" "$out" "review-seat plan-round=3 primary=dr-superpowers:judge-opus fallback=- reason=round cap=3"
rround "$TMP/round.md" 4
check "cap 3: round 4 is cap-critical" "$out" "review-seat plan-round=4 primary=dr-superpowers:judge-opus fallback=- reason=cap-critical cap=3"
rround "$TMP/round.md" 5
check "cap 3: round 5 exits 2" "$rc" "2"
rround "$TMP/plan.md" 1
check "an unparseable Evaluation line fails a plan round" "$rc" "2"
```

3. Replace these four lines:

```bash
route --plan-round 1
check "codex off: plan round 1 goes to Fable alone" "$out" "review-seat plan-round=1 primary=dr-superpowers:judge-fable fallback=- reason=codex-off"
route --plan-round 2
check "codex off: plan round 2 is unchanged" "$out" "review-seat plan-round=2 primary=dr-superpowers:judge-opus fallback=- reason=round"
```

with:

```bash
rround "$TMP/round.md" 1
check "codex off: an intricate plan's round 1 goes to Fable alone" "$out" "review-seat plan-round=1 primary=dr-superpowers:judge-fable fallback=- reason=codex-off cap=3"
rround "$TMP/light.md" 1
check "codex off: a plain plan's round 1 goes to Opus alone" "$out" "review-seat plan-round=1 primary=dr-superpowers:judge-opus fallback=- reason=codex-off cap=1"
rround "$TMP/round.md" 2
check "codex off: plan round 2 is unchanged" "$out" "review-seat plan-round=2 primary=dr-superpowers:judge-opus fallback=- reason=round cap=3"
```

4. Replace these two lines:

```bash
route --plan-round 1
check "no session file keeps plan round 1 off Codex" "$out" "review-seat plan-round=1 primary=dr-superpowers:judge-fable fallback=- reason=codex-off"
```

with:

```bash
rround "$TMP/round.md" 1
check "no session file keeps plan round 1 off Codex" "$out" "review-seat plan-round=1 primary=dr-superpowers:judge-fable fallback=- reason=codex-off cap=3"
```

- [ ] **Step 2: Run the suite to verify it fails**

Run: `timeout 300 bash plugins/dr-superpowers/tests/review-route.test.sh`
Expected: FAIL on every `rround` case (no `cap=` field, no exit 2); exit 1.

- [ ] **Step 3: Implement caps and intricacy**

In `plugins/dr-superpowers/scripts/review-route`:

1. Replace the usage comment lines

```bash
# Usage: review-route PLAN_FILE --task ID [ID ...]
#        review-route PLAN_FILE --plan-round R
```

with:

```bash
# Usage: review-route PLAN_FILE --task ID [ID ...]
#        review-route PLAN_FILE --plan-round R
#        review-route PLAN_FILE --ruling KIND [ID ...]
```

and replace `# Output: review-seat <scope> primary=<seat> fallback=<seat|-> reason=<why>` with:

```bash
# Output: review-seat <scope> primary=<seat> fallback=<seat|-> reason=<why>
#         (a plan round appends cap=<n>)
```

2. Replace the line `usage() { die "usage: review-route PLAN_FILE --task ID [ID ...] | --plan-round R"; }` with:

```bash
usage() { die "usage: review-route PLAN_FILE --task ID [ID ...] | --plan-round R | --ruling KIND [ID ...]"; }
```

3. Immediately before the line `case "$1" in`, insert:

```bash
# plan_shape — sets cap (plan-review rounds from the highest task total: 1 for
# <= 3, 2 for 4-5, 3 for 6) and intricate (1 when a task is at risk 3 or
# totals 6). A plan with no Evaluation line gets cap 1.
plan_shape() {
  local n t r max=-1
  cap=1 intricate=0
  while IFS=$'\t' read -r n t r; do
    [ -n "$n" ] || continue
    [ "$t" != "?" ] || die "Task $n: the Evaluation line does not parse"
    [ "$t" != "-" ] || continue
    [ "$t" -le "$max" ] || max=$t
    if [ "$r" -ge 3 ] || [ "$t" -ge 6 ]; then intricate=1; fi
  done < <(plan_scores "$src")
  if [ "$max" -ge 6 ]; then cap=3; elif [ "$max" -ge 4 ]; then cap=2; fi
}

```

4. Replace the whole `--plan-round)` branch:

```bash
  --plan-round)
    [ $# -eq 2 ] && [[ "$2" =~ ^[1-9][0-9]*$ ]] || usage
    if [ "$2" -eq 1 ] && codex_session_on review; then
      printf 'review-seat plan-round=1 primary=codex:plan fallback=%s reason=round\n' "$FABLE"
    elif [ "$2" -eq 1 ]; then
      printf 'review-seat plan-round=1 primary=%s fallback=- reason=codex-off\n' "$FABLE"
    else
      printf 'review-seat plan-round=%s primary=%s fallback=- reason=round\n' "$2" "$OPUS"
    fi
    exit 0 ;;
```

with:

```bash
  --plan-round)
    [ $# -eq 2 ] && [[ "$2" =~ ^[1-9][0-9]*$ ]] || usage
    plan_shape
    r=$2 claude=$OPUS
    [ "$intricate" -eq 0 ] || claude=$FABLE
    if [ "$r" -gt $((cap + 1)) ]; then
      die "plan round $r is past the cap ($cap) and its one cap-critical round"
    elif [ "$r" -eq 1 ] && codex_session_on review; then
      printf 'review-seat plan-round=1 primary=codex:plan fallback=%s reason=round cap=%s\n' "$claude" "$cap"
    elif [ "$r" -eq 1 ]; then
      printf 'review-seat plan-round=1 primary=%s fallback=- reason=codex-off cap=%s\n' "$claude" "$cap"
    elif [ "$r" -le "$cap" ]; then
      printf 'review-seat plan-round=%s primary=%s fallback=- reason=round cap=%s\n' "$r" "$OPUS" "$cap"
    else
      printf 'review-seat plan-round=%s primary=%s fallback=- reason=cap-critical cap=%s\n' "$r" "$OPUS" "$cap"
    fi
    exit 0 ;;
```

- [ ] **Step 4: Run the suite to verify it passes**

Run: `timeout 300 bash plugins/dr-superpowers/tests/review-route.test.sh`
Expected: `0 failed`, exit 0; `plan round 0 exits 2` still passes.

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-superpowers/scripts/review-route plugins/dr-superpowers/tests/review-route.test.sh
git commit -m "feat(superpowers): cap plan-review rounds by score"
```

### Task 8: review-route routes the ruling seat

**Files:**
- Modify: `plugins/dr-superpowers/scripts/review-route`
- Test: `plugins/dr-superpowers/tests/review-route.test.sh`

**Interfaces:**
- Consumes: C1 `plan_scores`; Task 7's `plan_shape`.
- Produces: C5 `--ruling`.

**Implementer:** dr-superpowers:impl-sonnet-high
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 1 = 3

- [ ] **Step 1: Write the failing tests**

In `plugins/dr-superpowers/tests/review-route.test.sh`, insert this block immediately before the line `# --- the review surface off ------------------------------------------------------`:

```bash
# --- the ruling seat -------------------------------------------------------------
# Fable rules only where a wrong verdict is expensive: the merge gate, a risk-3
# task, and an intricate plan's preflight.
rule() { out=$(bash "$ROUTE" "$@" 2>"$TMP/err"); rc=$?; }
rule "$TMP/light.md" --ruling final-residual
check "final-residual is the merge gate on Fable" "$out" "review-seat ruling=final-residual tasks=plan primary=dr-superpowers:judge-fable fallback=- reason=merge-gate"
rule "$TMP/round.md" --ruling plan-conflict 8
check "an item on a risk-3 task goes to Fable" "$out" "review-seat ruling=plan-conflict tasks=8 primary=dr-superpowers:judge-fable fallback=- reason=risk"
rule "$TMP/round.md" --ruling breaker 3 8
check "a batch routes on its heaviest item" "$out" "review-seat ruling=breaker tasks=3,8 primary=dr-superpowers:judge-fable fallback=- reason=risk"
rule "$TMP/round.md" --ruling cannot-verify 4
check "a routine item goes to Opus" "$out" "review-seat ruling=cannot-verify tasks=4 primary=dr-superpowers:judge-opus fallback=- reason=routine"
rule "$TMP/round.md" --ruling preflight
check "preflight on an intricate plan goes to Fable" "$out" "review-seat ruling=preflight tasks=plan primary=dr-superpowers:judge-fable fallback=- reason=intricate"
rule "$TMP/light.md" --ruling preflight
check "preflight on a plain plan goes to Opus" "$out" "review-seat ruling=preflight tasks=plan primary=dr-superpowers:judge-opus fallback=- reason=routine"
rule "$TMP/round.md" --ruling blocked-plan 7B
check "a part id routes on its task" "$out" "review-seat ruling=blocked-plan tasks=7B primary=dr-superpowers:judge-opus fallback=- reason=routine"
rule "$TMP/round.md" --ruling guess 1
check "an unknown kind exits 2" "$rc" "2"
rule "$TMP/round.md" --ruling breaker 99
check "an unknown task exits 2" "$rc" "2"
rule "$TMP/round.md" --ruling breaker x
check "a malformed ruling id exits 2" "$rc" "2"
{ printf 'Host: codex\n'; cat "$TMP/light.md"; } > "$TMP/cdx-light.md"
rule "$TMP/cdx-light.md" --ruling breaker 1
check "a Codex-host plan exits 2 for a ruling" "$rc" "2"

```

- [ ] **Step 2: Run the suite to verify it fails**

Run: `timeout 300 bash plugins/dr-superpowers/tests/review-route.test.sh`
Expected: FAIL on the seven routed `--ruling` cases (usage error today); exit 1.

- [ ] **Step 3: Implement `--ruling`**

In `plugins/dr-superpowers/scripts/review-route`, replace the two lines

```bash
  --task) shift ;;
  *) usage ;;
```

with:

```bash
  --ruling)
    shift
    [ $# -ge 1 ] || usage
    kind=$1; shift
    case $kind in
      preflight|plan-conflict|cannot-verify|breaker|blocked-plan|codex-empty-diff|final-residual) ;;
      *) die "not a ruling kind: $kind" ;;
    esac
    plan_shape
    scores=$(plan_scores "$src")
    ids="" risky=0
    for id in "$@"; do
      [[ "$id" =~ ^([0-9]+)([A-Z]?)$ ]] || die "not a task id: $id"
      row=$(awk -F'\t' -v n="${BASH_REMATCH[1]}" '$1 == n' <<<"$scores")
      [ -n "$row" ] || die "no Task ${BASH_REMATCH[1]} in the plan"
      [ "$(cut -f3 <<<"$row")" != 3 ] || risky=1
      ids="${ids:+$ids,}$id"
    done
    if [ "$kind" = final-residual ]; then primary=$FABLE reason=merge-gate
    elif [ "$risky" -eq 1 ]; then primary=$FABLE reason=risk
    elif [ "$kind" = preflight ] && [ "$intricate" -eq 1 ]; then primary=$FABLE reason=intricate
    else primary=$OPUS reason=routine
    fi
    printf 'review-seat ruling=%s tasks=%s primary=%s fallback=- reason=%s\n' "$kind" "${ids:-plan}" "$primary" "$reason"
    exit 0 ;;
  --task) shift ;;
  *) usage ;;
```

- [ ] **Step 4: Run the suite to verify it passes**

Run: `timeout 300 bash plugins/dr-superpowers/tests/review-route.test.sh`
Expected: `0 failed`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-superpowers/scripts/review-route plugins/dr-superpowers/tests/review-route.test.sh
git commit -m "feat(superpowers): route the ruling seat by stakes"
```

### Task 9: Move the per-task loop into reference/delegated-task.md

**Files:**
- Create: `plugins/dr-superpowers/reference/delegated-task.md`
- Modify: `plugins/dr-superpowers/skills/subagent-driven-development/SKILL.md` (Seats, Recovery, The Task Loop)
- Test: `plugins/dr-superpowers/tests/inline-mode.test.sh`, `plugins/dr-superpowers/tests/review-route.test.sh`, `plugins/dr-superpowers/tests/codex-review.test.sh`

**Interfaces:**
- Consumes: nothing.
- Produces: C6.

**Implementer:** dr-superpowers:impl-opus-low
**Evaluation:** files 1 - spec 0 - coupling 2 - risk 1 = 4

The move is mechanical and behaviour-preserving: a Node script cuts the text out of the skill so nothing is retyped. Do not edit the moved prose in this task beyond what the script does; Tasks 10, 12 and 13 change its meaning.

- [ ] **Step 1: Write the failing tests**

In `plugins/dr-superpowers/tests/inline-mode.test.sh`, insert this block immediately before the `# --- the Dispatch line` block that Task 4 added:

```bash
# --- the delegated loop: one copy, shared by both execution skills ---
DT="$P/reference/delegated-task.md"
check "exists: reference/delegated-task.md" "$([ -f "$DT" ] && echo yes || echo no)" "yes"
for h in '## Contract' '## Seats' '## 1. Dispatch the implementer' '## 2. Handle the report' \
         '## 3. Review the task' '## 4. The fix loop' '## 5. Complete the task' '## Recovery'; do
  check "delegated loop heading: $h" "$(grep -cxF -- "$h" "$DT")" "1"
done
for h in '### 1. Dispatch the implementer' '### 2. Handle the report' '### 3. Review the task' \
         '### 4. The fix loop' '### 5. Complete the task'; do
  check "subagent mode no longer holds: $h" "$(grep -cxF -- "$h" "$SDD")" "0"
done
present "subagent mode links the delegated loop" "$SDD" "../../reference/delegated-task.md"
present "subagent mode defers per-task recovery" "$SDD" 'Apply [delegated-task.md](../../reference/delegated-task.md) §Recovery'
# validate-repository.mjs checks links only under skills/, so this suite pins
# the reference file's links.
for link in $(grep -oE '\]\([^)#]+\.md' "$DT" | sed 's/^](//' | sort -u); do
  check "delegated loop link resolves: $link" "$([ -f "$P/reference/$link" ] && echo yes || echo no)" "yes"
done

```

In `plugins/dr-superpowers/tests/review-route.test.sh`, replace the task review prose block — from the line `SDD="$P/skills/subagent-driven-development/SKILL.md"` through the line `present "SDD records a codex-off seat" "$SDD" '` (codex off — <reason>)` when `review-route` printed `reason=codex-off`'` — with:

```bash
SDD="$P/skills/subagent-driven-development/SKILL.md"
DT="$P/reference/delegated-task.md"
TRP="$P/skills/subagent-driven-development/references/task-reviewer-prompt.md"
present "the Seats table routes the task reviewer" "$DT" '| Task reviewer | The seat `scripts/review-route PLAN_FILE --task <N>` prints'
present "the delegated loop runs the light tier for codex:light" "$DT" '`codex:light` is `--tier light`'
present "the delegated loop has the risk section" "$DT" '**Risk 2 and above.**'
absent "SDD no longer averages three seats" "$SDD" 'average each criterion'
absent "the delegated loop does not average three seats" "$DT" 'average each criterion'
absent "SDD no longer writes K=3" "$SDD" 'K=3'
absent "the delegated loop does not write K=3" "$DT" 'K=3'
present "the delegated loop writes the seat clause" "$DT" ', seat <seat>'
present "the delegated loop keeps the runner name" "$DT" 'run-codex-review.sh'
present "the delegated loop keeps the FAILED deferral" "$DT" 'TIMEOUT or FAILED'
present "the delegated loop keeps the no-redispatch rule" "$DT" 'never re-dispatch the Codex seat'
present "the delegated loop runs the gate before routing" "$DT" '- **The seat:** run `scripts/codex-gate` (say its line aloud when it ends'
present "the delegated loop names a codex-off route" "$DT" 'On `reason=codex-off` the review surface is off for'
present "the delegated loop records a codex-off seat" "$DT" '` (codex off — <reason>)` when `review-route` printed `reason=codex-off`'
```

In `plugins/dr-superpowers/tests/codex-review.test.sh`, replace the line `SDD="$HERE/../skills/subagent-driven-development/SKILL.md"` with `SDD="$HERE/../reference/delegated-task.md"`.

- [ ] **Step 2: Run the suites to verify they fail**

Run: `timeout 300 bash plugins/dr-superpowers/tests/inline-mode.test.sh; timeout 300 bash plugins/dr-superpowers/tests/review-route.test.sh; timeout 300 bash plugins/dr-superpowers/tests/codex-review.test.sh`
Expected: each exits 1, failing on the missing `delegated-task.md`.

- [ ] **Step 3: Write and run the extraction script**

Write this file with the Write tool to a path outside the repository — the scratchpad directory your session's system prompt names, or else the directory `mktemp -d` prints — named `extract-delegated.mjs`, then run `timeout 60 node <that path>` from the repository root. It prints `moved` and changes exactly the two files.

```js
import { readFileSync, writeFileSync } from 'node:fs';

const P = 'plugins/dr-superpowers';
const sddPath = `${P}/skills/subagent-driven-development/SKILL.md`;
const raw = readFileSync(sddPath, 'utf8');
const eol = raw.includes('\r\n') ? '\r\n' : '\n';
const lines = raw.split(/\r?\n/);

const at = (pred, what) => {
  const i = lines.findIndex(pred);
  if (i < 0) throw new Error(`not found: ${what}`);
  return i;
};
const exact = s => at(l => l === s, s);
const starts = s => at(l => l.startsWith(s), s);

const step1 = exact('### 1. Dispatch the implementer');
const finalReview = exact('## Final Review');
const seatRows = ['| Implementer |', '| External implementer |', '| Task reviewer |', '| Scoped re-review |'].map(starts);
const fleet = starts('**Fleet agents take no `model` argument.**');
const general = starts('**General-purpose seats always take an explicit model.**');
const turn = starts('**Turn count beats token price.**');
const ledger = exact('## The Ledger');
const oldRows = [
  '| `fix round R/5` or `review round R/5`, R < 5 | Resume the loop at round R+1 — after compaction the agent id is gone, so the cache rule makes it a fresh dispatch |',
  '| `fix round 5/5` or `review round 5/5` | Go to the breaker |',
  '| `implementer … (assigned …)` | If the report file has a status and `git log <base>..HEAD` is non-empty, review it; otherwise dispatch the same agent fresh |',
].map(exact);
if (!(fleet < general && general < turn && turn < ledger && ledger < step1 && step1 < finalReview)) throw new Error('unexpected section order');

const relink = text => text
  .replaceAll('](../../reference/', '](')
  .replaceAll('](../../criteria/', '](../criteria/')
  .replaceAll('](references/', '](../skills/subagent-driven-development/references/')
  .replaceAll('(§3 Review the task)', '(§3)')
  .replaceAll('(see Session Budget)', "(see the caller's Session Budget section)")
  .replaceAll(`(see${eol}The Ruling Seat)`, `(see${eol}the caller's The Ruling Seat section)`)
  .replace(/^### ([1-5])\. /gm, '## $1. ');

const moved = [
  '# The delegated task loop',
  '',
  "One task's dispatch, review, fix loop and complete line.",
  'dr-superpowers:subagent-driven-development runs it for every task, and',
  'dr-superpowers:executing-plans runs it for each task whose brief carries',
  '`**Dispatch:** delegated`.',
  '',
  '## Contract',
  '',
  '- **The caller holds** the plan workspace, the ledger, a brief file from',
  "  `scripts/task-brief` (one task's, or in subagent mode a batch's), and a ruling",
  '  seat it can dispatch, per its own The Ruling Seat section.',
  "- **The loop writes** only lines of the shared ledger grammar",
  '  ([subagent-driven-development](../skills/subagent-driven-development/SKILL.md)',
  '  §The Ledger).',
  "- **The loop returns** on the task's `complete` line, on a `BLOCKED` line, or on",
  '  a budget `handoff` acted on at the next ledger write, which §Recovery resumes.',
  '',
  '## Seats',
  '',
  '| Seat | Agent | Model argument |',
  '|---|---|---|',
  ...seatRows.map(i => lines[i]),
  '',
  ...lines.slice(fleet, general),
  'General-purpose seats always take an explicit model:',
  '[subagent-driven-development](../skills/subagent-driven-development/SKILL.md) §Seats.',
  '',
  ...lines.slice(turn, ledger),
  ...lines.slice(step1, finalReview),
  '## Recovery',
  '',
  "For a task whose last ledger line, read by the caller's Recovery rule, is:",
  '',
  '| Last line | Action |',
  '|---|---|',
  '| `implementer <agent> (assigned …)`, the agent not `inline` | If the report file has a status and `git log <base>..HEAD` is non-empty, review it (§3); otherwise dispatch the same agent fresh (§1) |',
  '| `fix round R/5`, R < 5 | Resume the loop at round R+1 — after compaction the agent id is gone, so the cache rule makes it a fresh dispatch |',
  '| `fix round 5/5` | Go to the breaker (§4) |',
  '',
].join(eol);
writeFileSync(`${P}/reference/delegated-task.md`, relink(moved));

const out = [...lines];
out[oldRows[0]] = '| `review round R/5` on a `Group` line, R < 5 | Resume the batch\'s loop at round R+1 — after compaction the agent id is gone, so the cache rule makes it a fresh dispatch |';
out[oldRows[1]] = '| `review round 5/5` on a `Group` line | Go to the breaker |';
out[oldRows[2]] = '| `implementer <agent> (assigned …)` or `fix round R/5` | Apply [delegated-task.md](../../reference/delegated-task.md) §Recovery |';
out.splice(step1, finalReview - step1,
  'For each task, or batch, run [delegated-task.md](../../reference/delegated-task.md):',
  'dispatch the implementer, handle the report, review the task, the fix loop and',
  'the complete line. Its contract names what the loop needs from you.',
  '');
out.splice(turn, ledger - turn);
out.splice(fleet, general - fleet,
  'The implementer, external implementer, task reviewer and scoped re-review seats,',
  'and the rule that fleet agents take no `model` argument, are in',
  '[delegated-task.md](../../reference/delegated-task.md) §Seats.',
  '');
for (const i of [...seatRows].sort((a, b) => b - a)) out.splice(i, 1);
writeFileSync(sddPath, out.join(eol));
console.log('moved');
```

The splices run from the bottom of the file up, so earlier indexes stay valid: the Task Loop range, then the turn paragraph, then the fleet paragraph, then the four table rows. The three recovery rows are replaced in place before any splice.

- [ ] **Step 4: Check the result by eye and by grep**

Run: `grep -n "§3 Review the task\|(see Session Budget)\|](references/\|](../../" plugins/dr-superpowers/reference/delegated-task.md`
Expected: no output.

Run: `grep -n "^## \|^### " plugins/dr-superpowers/skills/subagent-driven-development/SKILL.md`
Expected: `## Seats`, `## The Ledger`, `## The Ruling Seat`, `## Session Budget`, `## The Task Loop`, `## Final Review` still present in that order, and no `### 1.` to `### 5.` headings.

Read `plugins/dr-superpowers/skills/subagent-driven-development/SKILL.md` from `## Seats` to `## The Ledger`: the table keeps only the Ruling seat and Final review rows, followed by the pointer paragraph and the `**General-purpose seats always take an explicit model.**` paragraph.

- [ ] **Step 5: Run the suites to verify they pass**

Run: `timeout 300 bash plugins/dr-superpowers/tests/inline-mode.test.sh && timeout 300 bash plugins/dr-superpowers/tests/review-route.test.sh && timeout 300 bash plugins/dr-superpowers/tests/codex-review.test.sh && timeout 120 node scripts/validate-repository.mjs`
Expected: three suites end `0 failed`; the validator prints `Repository catalogs, manifests, versions, and bundled links are valid.`

- [ ] **Step 6: Commit**

```bash
git add plugins/dr-superpowers/reference/delegated-task.md plugins/dr-superpowers/skills/subagent-driven-development/SKILL.md plugins/dr-superpowers/tests/inline-mode.test.sh plugins/dr-superpowers/tests/review-route.test.sh plugins/dr-superpowers/tests/codex-review.test.sh
git commit -m "refactor(superpowers): share the per-task loop"
```

### Task 10: Task review routing prose

**Files:**
- Modify: `plugins/dr-superpowers/reference/delegated-task.md`
- Modify: `plugins/dr-superpowers/reference/external-executor.md`
- Modify: `plugins/dr-superpowers/README.md`
- Modify: `plugins/dr-superpowers/skills/subagent-driven-development/references/task-reviewer-prompt.md`
- Test: `plugins/dr-superpowers/tests/review-route.test.sh`

**Interfaces:**
- Consumes: C5 `--task` (Task 6), C6 (Task 9).
- Produces: nothing.

**Implementer:** dr-superpowers:impl-sonnet-high
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 1 = 3

- [ ] **Step 1: Update the pins first**

In `plugins/dr-superpowers/tests/review-route.test.sh`, replace `present "the delegated loop has the risk section" "$DT" '**Risk 2 and above.**'` with:

```bash
present "the delegated loop has the risk 3 section" "$DT" '**Risk 3.** On `primary=codex:heavy+judge-fable`'
absent "the delegated loop drops the risk 2 section" "$DT" '**Risk 2 and above.**'
present "the delegated loop falls back to Opus on exit 2" "$DT" 'review with `dr-superpowers:judge-opus` and say why, quoting its message.'
present "the task seats reserve Fable for risk 3" "$P/reference/external-executor.md" 'and `codex:heavy+judge-fable` at risk 3.'
present "the second pass points at the delegated loop" "$P/reference/external-executor.md" 'per [delegated-task.md](delegated-task.md) §3 Review the task.'
absent "README drops risk 2 Fable reviews" "$P/README.md" 'at risk 2 or above'
present "the second pass runs at risk 3 only" "$P/skills/subagent-driven-development/references/task-reviewer-prompt.md" '[Include this section only on a risk 3 task whose Codex seat'
```

Run: `timeout 300 bash plugins/dr-superpowers/tests/review-route.test.sh`
Expected: FAIL on those seven; exit 1.

- [ ] **Step 2: Edit `reference/delegated-task.md`**

Replace `**Risk 2 and above.** On `primary=codex:heavy+judge-fable`, run the Codex seat` with `**Risk 3.** On `primary=codex:heavy+judge-fable`, run the Codex seat`.

Replace the line `  review with `dr-superpowers:judge-fable` and say why, quoting its message.` with `  review with `dr-superpowers:judge-opus` and say why, quoting its message.`

- [ ] **Step 3: Edit `reference/external-executor.md`**

Replace:

```text
without an `**Executor:**` line: `codex:light` for totals 0 to 3, `codex:heavy`
for 4 to 6, and `codex:heavy+judge-fable` at risk 2 or above. A task carrying
```

with:

```text
without an `**Executor:**` line: `codex:light` for totals 0 to 3 and
`codex:heavy` for 4 to 6 at any risk up to 2, and `codex:heavy+judge-fable`
at risk 3. A task carrying
```

Replace:

```text
**At risk 2 or above** this review is the first of two steps: the controller
then dispatches `judge-fable` with the Second Pass section naming this seat's
`--out` path, per
[subagent-driven-development](../skills/subagent-driven-development/SKILL.md)
§3 Review the task. Fable's verdicts and scores are the task's.
```

with:

```text
**At risk 3** this review is the first of two steps: the controller then
dispatches `judge-fable` with the Second Pass section naming this seat's
`--out` path, per [delegated-task.md](delegated-task.md) §3 Review the task.
Fable's verdicts and scores are the task's.
```

- [ ] **Step 4: Edit `README.md`**

Replace:

```text
verdicts. Tasks at risk 2 or above are reviewed by Codex `gpt-6-astra` and then
by `judge-fable`, which rules CONFIRMED or REJECTED on every Codex finding in the
same pass.
```

with:

```text
verdicts. Tasks at risk 3 are reviewed by Codex `gpt-6-astra` and then by
`judge-fable`, which rules CONFIRMED or REJECTED on every Codex finding in the
same pass.
```

Replace:

```text
`judge-fable` at risk 2 or above. A task the executor lane implemented is always
reviewed by a Claude judge, so Codex never reviews its own work there; when a
Codex seat produces nothing, `judge-sonnet-high`, `judge-opus` or `judge-fable`
takes it by score band.
```

with:

```text
`judge-fable` at risk 3. A task the executor lane implemented is always
reviewed by a Claude judge, so Codex never reviews its own work there; when a
Codex seat produces nothing, `judge-sonnet-high` takes totals 0 to 3 and
`judge-opus` 4 to 6, with `judge-fable` only at risk 3.
```

- [ ] **Step 4b: Edit `task-reviewer-prompt.md`**

In `plugins/dr-superpowers/skills/subagent-driven-development/references/task-reviewer-prompt.md`, replace `    [Include this section only on a risk 2 or above task whose Codex seat` with `    [Include this section only on a risk 3 task whose Codex seat`.

- [ ] **Step 5: Run the suites to verify they pass**

Run: `timeout 300 bash plugins/dr-superpowers/tests/review-route.test.sh && timeout 300 bash plugins/dr-superpowers/tests/inline-mode.test.sh && timeout 300 bash plugins/dr-superpowers/tests/codex-review.test.sh`
Expected: all end `0 failed`, exit 0.

- [ ] **Step 6: Commit**

```bash
git add plugins/dr-superpowers/reference/delegated-task.md plugins/dr-superpowers/reference/external-executor.md plugins/dr-superpowers/README.md plugins/dr-superpowers/skills/subagent-driven-development/references/task-reviewer-prompt.md plugins/dr-superpowers/tests/review-route.test.sh
git commit -m "docs(superpowers): route task reviews by risk 3"
```

### Task 11: Execution line and plan review prose

**Files:**
- Modify: `plugins/dr-superpowers/skills/writing-plans/SKILL.md`
- Modify: `plugins/dr-superpowers/skills/writing-plans/references/plan-reviewer-prompt.md`
- Modify: `plugins/dr-superpowers/skills/using-superpowers/SKILL.md`
- Modify: `plugins/dr-superpowers/README.md`
- Test: `plugins/dr-superpowers/tests/review-route.test.sh`

**Interfaces:**
- Consumes: C4 (Task 5), C5 `--plan-round` (Task 7), C6 (Task 9).
- Produces: nothing.

**Implementer:** dr-superpowers:impl-opus-low
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 2 = 4

- [ ] **Step 1: Update the pins first**

In `plugins/dr-superpowers/tests/review-route.test.sh`:

Replace `present "writing-plans keeps the round cap" "$WP" 'replaces a fresh full review; rounds are not cut.'` with:

```bash
present "writing-plans caps rounds by score" "$WP" 'below the `cap=` that `review-route` printed'
present "writing-plans re-rounds only on Critical or a low score" "$WP" 'Run the next round only when a round returned'
present "writing-plans gives a Critical at the cap one more round" "$WP" 'earns exactly one more'
present "writing-plans states the heavy-majority rule" "$WP" '`subagent` when more than half the tasks are heavy'
present "writing-plans raises a delegating inline effort" "$WP" 'raised to `high` when any task is'
present "writing-plans falls back to Opus on exit 2" "$WP" 'On any other exit 2, review with `dr-superpowers:judge-opus`'
present "the plan reviewer prompt names both round-1 Claude seats" "$PRP" 'round produced nothing (`dr-superpowers:judge-fable` for an intricate plan,'
present "using-superpowers states the mixed-mode rule" "$P/skills/using-superpowers/SKILL.md" 'an inline plan delegates those'
present "README states mixed mode" "$P/README.md" '`--effort high` once it delegates'
present "README caps plan review" "$P/README.md" 'capped by the plan'"'"'s highest task total'
```

Replace `present "writing-plans sends a codex-off round 1 to Fable" "$WP" '**`primary=dr-superpowers:judge-fable` with `reason=codex-off`**'` with:

```bash
present "writing-plans routes a codex-off round 1 by intricacy" "$WP" '**`reason=codex-off`** (round 1 while the gate has not opened the review'
```

Run: `timeout 300 bash plugins/dr-superpowers/tests/review-route.test.sh`
Expected: FAIL on the new pins; exit 1.

- [ ] **Step 2: Edit `skills/writing-plans/SKILL.md` — the Execution line**

Replace:

```text
- `inline` when every task's total is 4 or less and no task is at risk 3 —
  the default then. The model follows the highest total: `sonnet` when every
  task is 3 or less, `opus` when any task scores 4 (the Opus-low band).
  `<e>` is the effort of the highest-scoring task's assigned tier
  (`impl-haiku` counts as `low`): `claude --model <sonnet|opus> --effort <e>`.
- Otherwise `subagent`: `claude --model sonnet --effort high`. The controller
  owns no judgment calls — the ruling seat does — so it needs no stronger
  model.
- Your human partner may override the line; `plan-lint` checks its grammar and
  the inline rule.
```

with:

```text
A task is **heavy** when its total is 5 or more or its risk is 3, on any part.
An inline plan delegates its heavy tasks: each runs through
[delegated-task.md](../../reference/delegated-task.md) with an implementer
subagent and the full per-task review.

- `subagent` when more than half the tasks are heavy:
  `claude --model sonnet --effort high`. The controller owns no judgment calls
  — the ruling seat does — so it needs no stronger model.
- Otherwise `inline`, the default. The model follows the highest total among
  the tasks that are not heavy: `sonnet` when every one is 3 or less, `opus`
  when one scores 4 (the Opus-low band). `<e>` is that task's assigned tier's
  effort (`impl-haiku` counts as `low`), raised to `high` when any task is
  heavy: `claude --model <sonnet|opus> --effort <e>`. When every task is heavy
  and your human partner overrides the line to inline, it is
  `claude --model opus --effort high`.
- Your human partner may override the line; `plan-lint` checks its grammar,
  warns when it disputes the majority rule, and lists the delegated tasks.
```

- [ ] **Step 3: Edit `skills/writing-plans/SKILL.md` — Lint and Review**

Replace:

```text
   describes. On any other exit 2, review with `dr-superpowers:judge-fable`
   and say why, quoting its message.
```

with:

```text
   describes. On any other exit 2, review with `dr-superpowers:judge-opus`
   and say why, quoting its message.
```

Replace:

```text
     no review: dispatch the printed `fallback`, `dr-superpowers:judge-fable`
     (`dr-superpowers:judge-opus` when Fable is unavailable or declined), with
     the full-plan template, save its reply to
```

with:

```text
     no review: dispatch the printed `fallback` (`dr-superpowers:judge-fable`
     for an intricate plan, `dr-superpowers:judge-opus` otherwise, and
     `judge-opus` when Fable is unavailable or declined), with
     the full-plan template, save its reply to
```

Replace:

```text
   - **`primary=dr-superpowers:judge-fable` with `reason=codex-off`** (round 1
     while the gate has not opened the review surface). No Codex seat runs.
     Dispatch it (`dr-superpowers:judge-opus` when Fable is unavailable or
     declined) with the full-plan template, save its reply to
```

with:

```text
   - **`reason=codex-off`** (round 1 while the gate has not opened the review
     surface). No Codex seat runs. The `primary` is
     `dr-superpowers:judge-fable` for an intricate plan (a task at risk 3 or
     totalling 6) and `dr-superpowers:judge-opus` otherwise. Dispatch it
     (`dr-superpowers:judge-opus` when Fable is unavailable or
     declined) with the full-plan template, save its reply to
```

Replace `   - **`primary=dr-superpowers:judge-opus`** (rounds 2 and 3). Write` with `   - **`primary=dr-superpowers:judge-opus`** (every later round). Write`.

Replace:

```text
3. **Fix and repeat.** Any score of 8 or below, or any Critical or Important
   finding: fix the plan, re-lint, and run the next round. A delta round
   replaces a fresh full review; rounds are not cut. At most 3 review rounds;
   after the third, show the remaining findings to your human partner. A
   borderline score (9-13) gets a one-line decision in the plan's Assumptions.
```

with:

```text
3. **Fix and repeat.** Fix every Critical and Important finding and re-lint;
   Minor findings are advisory. Run the next round only when a round returned
   a Critical finding or any score of 8 or below, and only while the round is
   below the `cap=` that `review-route` printed: 1 when the plan's highest
   task total is 3 or less, 2 for 4 or 5, 3 for 6. A delta round replaces a
   fresh full review. At the cap, a Critical finding earns exactly one more
   delta round (`reason=cap-critical`), scoped to its fix, which earns no
   other. Any Critical finding still open after it, and any score of 8 or
   below at the cap, go to your human partner. A borderline score (9-13) gets
   a one-line decision in the plan's Assumptions.
```

- [ ] **Step 4: Edit the plan reviewer prompt, using-superpowers and README**

In `plugins/dr-superpowers/skills/writing-plans/references/plan-reviewer-prompt.md`, replace:

```text
- `[JUDGE]` - the `fallback` that `scripts/review-route PLAN_FILE --plan-round 1`
  prints when the Codex round produced nothing: `dr-superpowers:judge-fable`,
  or `dr-superpowers:judge-opus` when Fable is unavailable or declined (say the
  substitution aloud); no `model`
```

with:

```text
- `[JUDGE]` - the seat that `scripts/review-route PLAN_FILE --plan-round 1`
  prints: its `primary` when Codex is off, or its `fallback` when the Codex
  round produced nothing (`dr-superpowers:judge-fable` for an intricate plan,
  `dr-superpowers:judge-opus` otherwise), and `dr-superpowers:judge-opus` when
  Fable is unavailable or declined (say the substitution aloud); no `model`
```

In `plugins/dr-superpowers/skills/using-superpowers/SKILL.md`, replace `Execute inline by default when the plan allows it (every task scores 4 or less, none at risk 3).` with `Execute inline by default when the plan allows it (at most half the tasks are heavy: total 5 or more, or risk 3; an inline plan delegates those).`

In `plugins/dr-superpowers/README.md`, replace:

```text
task itself. Inline mode is available only when every task scores 4 or less
with none at risk 3 - `plan-lint` refuses the line otherwise, and requires
`--model opus` once any task scores 4 - and it trades
per-task review for one whole-branch review at the end, which both modes now
share. A task that will not converge after three fix rounds escalates to
```

with:

```text
task itself. Inline mode is the default unless more than half the tasks are
heavy (total 5 or more, or risk 3). An inline plan delegates its heavy tasks
to an implementer subagent with the full per-task review loop, shared with
subagent mode in `reference/delegated-task.md`, and implements the rest
itself, trading their per-task review for one whole-branch review at the end,
which both modes share. `plan-lint` requires `--model opus` once a task it
implements scores 4, and `--effort high` once it delegates. A task that will
not converge after three fix rounds escalates to
```

and replace:

```text
Plan review takes Astra for round 1 and `judge-opus` for
delta rounds 2 and 3.
```

with:

```text
Plan review takes Astra for round 1 (`judge-fable` for an intricate plan when
Codex is off, `judge-opus` otherwise) and `judge-opus` for delta rounds,
capped by the plan's highest task total.
```

- [ ] **Step 5: Run the suites to verify they pass**

Run: `timeout 300 bash plugins/dr-superpowers/tests/review-route.test.sh && timeout 300 bash plugins/dr-superpowers/tests/hook.test.sh && timeout 120 node scripts/validate-repository.mjs`
Expected: both suites end `0 failed`; the validator prints its valid line.

- [ ] **Step 6: Commit**

```bash
git add plugins/dr-superpowers/skills/writing-plans plugins/dr-superpowers/skills/using-superpowers/SKILL.md plugins/dr-superpowers/README.md plugins/dr-superpowers/tests/review-route.test.sh
git commit -m "docs(superpowers): plan mixed mode, capped reviews"
```

### Task 12: Ruling seat prose

**Files:**
- Modify: `plugins/dr-superpowers/skills/subagent-driven-development/SKILL.md` (Seats row, The Ruling Seat)
- Modify: `plugins/dr-superpowers/skills/subagent-driven-development/references/ruling-prompt.md`
- Modify: `plugins/dr-superpowers/agents/judge-fable.md`, `plugins/dr-superpowers/agents/judge-opus.md`, `plugins/dr-superpowers/agents/judge-sonnet-high.md`
- Test: `plugins/dr-superpowers/tests/review-route.test.sh`

**Interfaces:**
- Consumes: C5 `--ruling` (Task 8).
- Produces: C7.

**Implementer:** dr-superpowers:impl-opus-low
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 2 = 4

- [ ] **Step 1: Write the pins first**

In `plugins/dr-superpowers/tests/review-route.test.sh`, insert this block immediately before the line `# --- risk3-spread is retired -----------------------------------------------------`:

```bash
# --- ruling seat prose -----------------------------------------------------------
RULP="$P/skills/subagent-driven-development/references/ruling-prompt.md"
present "SDD routes the ruling seat" "$SDD" '`scripts/review-route PLAN_FILE --ruling <kind> [<task> ...]`'
absent "SDD no longer pins the ruling seat to Fable" "$SDD" '`dr-superpowers:judge-fable` (`judge-opus` under the Fable-unavailable rule,'
present "SDD confirms an Opus header amendment on Fable" "$SDD" '**A Header amendment from `judge-opus` is confirmed first.**'
present "SDD never hands the confirmation to Opus" "$SDD" 'never hand it'
present "the ruling prompt has the confirmation note" "$RULP" '[CONFIRM_NOTE]'
present "the ruling prompt routes its judge" "$RULP" 'the `primary` that `scripts/review-route PLAN_FILE --ruling <kind>'
present "judge-fable serves critical seats only" "$P/agents/judge-fable.md" 'critical seats only'
present "judge-sonnet-high reviews totals 0 to 3" "$P/agents/judge-sonnet-high.md" 'totals 0 to 3'
present "judge-opus reviews totals 4 to 6" "$P/agents/judge-opus.md" 'totals 4 to 6'

```

Run: `timeout 300 bash plugins/dr-superpowers/tests/review-route.test.sh`
Expected: FAIL on those pins; exit 1.

- [ ] **Step 2: Edit `skills/subagent-driven-development/SKILL.md`**

Replace the Seats row `| Ruling seat | `dr-superpowers:judge-fable`; `dr-superpowers:judge-opus` under the same rule | None |` with:

```text
| Ruling seat | The seat `scripts/review-route PLAN_FILE --ruling <kind> [<task> ...]` prints (The Ruling Seat); `dr-superpowers:judge-opus` in place of `judge-fable` when Fable is unavailable or your human partner declined it, said aloud | None |
```

In The Ruling Seat, replace:

```text
packages — with the findings copied verbatim. Dispatch
`dr-superpowers:judge-fable` (`judge-opus` under the Fable-unavailable rule,
said aloud) with [ruling-prompt.md](references/ruling-prompt.md), expanding
its placeholders. Codex hosts use a native judge at Astra high or above
([native-codex.md](../../reference/native-codex.md)).
```

with:

```text
packages — with the findings copied verbatim. Run
`scripts/review-route PLAN_FILE --ruling <kind> [<task> ...]` for the point's
kind and the tasks its items concern, and dispatch the `primary` it prints
(`judge-opus` in place of `judge-fable` when Fable is unavailable or your human
partner declined it, said aloud) with
[ruling-prompt.md](references/ruling-prompt.md), expanding its placeholders.
Items of different kinds at one point take `judge-fable` if any kind's route
prints it. On any exit 2, dispatch `dr-superpowers:judge-opus` and say why,
quoting its message. Codex hosts, where `review-route` exits 2, use a native
judge at Astra high or above ([native-codex.md](../../reference/native-codex.md)).
```

Replace:

```text
  `rejected: …`, make one fresh seat dispatch carrying the entry and the
  rejection output; a second rejection is BLOCKED.
```

with:

```text
  `rejected: …`, make one fresh seat dispatch carrying the entry and the
  rejection output; a second rejection is BLOCKED.

  **A Header amendment from `judge-opus` is confirmed first.** Before
  `plan-amend`, write `<workspace>/rulings-<point>-<task>-confirm.md`: the
  original item entry unchanged, then the Opus verdict block verbatim. Dispatch
  `dr-superpowers:judge-fable` directly, not through `review-route`, with the
  same template and `[CONFIRM_NOTE]` filled. Fable's verdict replaces the Opus
  verdict and is carried out like any verdict; the one fresh dispatch after a
  `rejected:` goes to `judge-fable` too. Log `Ruling: header amendment A<k>
  confirmed by judge-fable — <Fable's verdict> — if wrong, the plan's Global
  Constraints or Contracts carry a bad rule into every later task`. When Fable
  is unavailable or declined, skip the confirmation and never hand it to Opus:
  apply the Opus verdict and log `Ruling: header amendment A<k> unconfirmed —
  Fable unavailable — if wrong, the plan's Global Constraints or Contracts carry
  a bad rule into every later task`.
```

- [ ] **Step 3: Edit `references/ruling-prompt.md`**

Replace:

```text
    [PROVISIONAL_NOTE]

    Where the plan and the spec disagree, the spec wins. Where neither
```

with:

```text
    [PROVISIONAL_NOTE]

    [CONFIRM_NOTE]

    Where the plan and the spec disagree, the spec wins. Where neither
```

Replace:

```text
- `[JUDGE]` — `dr-superpowers:judge-fable`, or `dr-superpowers:judge-opus` when
  Fable is unavailable or declined (say the substitution aloud); no `model`
  argument. On Codex, a native judge at Astra high or above.
```

with:

```text
- `[JUDGE]` — the `primary` that `scripts/review-route PLAN_FILE --ruling <kind>
  [<task> ...]` prints, or `dr-superpowers:judge-fable` for a Header
  amendment's confirmation; `dr-superpowers:judge-opus` in place of
  `judge-fable` when Fable is unavailable or declined (say the substitution
  aloud); no `model` argument. On Codex, a native judge at Astra high or above.
```

Replace:

```text
- `[PROVISIONAL_NOTE]` — when the plan's Spec path is unreachable, "The spec is
  unreachable. Mark every Ruling (provisional)."; otherwise delete the line.
```

with:

```text
- `[PROVISIONAL_NOTE]` — when the plan's Spec path is unreachable, "The spec is
  unreachable. Mark every Ruling (provisional)."; otherwise delete the line.
- `[CONFIRM_NOTE]` — only for a Header amendment's confirmation: "Another seat
  returned the verdict at the end of the items file for item <id>. Return your
  own verdict block for that item."; otherwise delete the line.
```

- [ ] **Step 4: Edit the judge agent descriptions**

In `plugins/dr-superpowers/agents/judge-fable.md`, replace the `description:` line with:

```text
description: "Read-only verifier and ruling seat running Fable 5 at high effort. Dispatched by dr-superpowers for critical seats only: risk-3 task reviews, the final review's two-list dedupe, plan-review round 1 of an intricate plan when Codex is unavailable, and rulings on final-review residuals, risk-3 tasks, an intricate plan's preflight and Header amendments."
```

In `plugins/dr-superpowers/agents/judge-opus.md`, replace the `description:` line with:

```text
description: "Read-only verifier, ruling seat and approach ranker running Opus 5 at high effort. Dispatched by dr-superpowers as the task reviewer for totals 4 to 6 when Codex is not the reviewer, for plan-review rounds after the first and round 1 of a plain plan when Codex is unavailable, for routine rulings, approach ranking and distillation checks, and in place of judge-fable when Fable is unavailable or declined."
```

In `plugins/dr-superpowers/agents/judge-sonnet-high.md`, replace `task reviewer for totals 0 and 1 when Codex is not the reviewer.` with `task reviewer for totals 0 to 3 when Codex is not the reviewer.`

Run: `grep -n "judge-fable\|totals" plugins/dr-superpowers/agents/judge-*.md`
Expected: only the three description lines and any body lines that do not state a score band or seat list; if a body line restates the old bands, report it as a deferred minor.

- [ ] **Step 5: Run the suites to verify they pass**

Run: `timeout 300 bash plugins/dr-superpowers/tests/review-route.test.sh && timeout 300 bash plugins/dr-superpowers/tests/fleet.test.sh && timeout 300 bash plugins/dr-superpowers/tests/inline-mode.test.sh && timeout 120 node scripts/validate-repository.mjs`
Expected: three suites end `0 failed`; the validator prints its valid line.

- [ ] **Step 6: Commit**

```bash
git add plugins/dr-superpowers/skills/subagent-driven-development plugins/dr-superpowers/agents/judge-fable.md plugins/dr-superpowers/agents/judge-opus.md plugins/dr-superpowers/agents/judge-sonnet-high.md plugins/dr-superpowers/tests/review-route.test.sh
git commit -m "docs(superpowers): route the ruling seat by stakes"
```

### Task 13: executing-plans runs mixed mode

**Files:**
- Modify: `plugins/dr-superpowers/skills/executing-plans/SKILL.md`
- Modify: `plugins/dr-superpowers/skills/subagent-driven-development/SKILL.md` (After compaction)
- Test: `plugins/dr-superpowers/tests/inline-mode.test.sh`, `plugins/dr-superpowers/tests/review-route.test.sh`

**Interfaces:**
- Consumes: C2, C3, C5 `--ruling`, C6.
- Produces: nothing.

**Implementer:** dr-superpowers:impl-opus-low
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 2 = 4

- [ ] **Step 1: Update the pins first**

In `plugins/dr-superpowers/tests/inline-mode.test.sh`, replace `present "names the kinds it does not run" "$INLINE" "no task reviewer"` with:

```bash
present "names the one kind it never runs" "$INLINE" 'Only `codex-empty-diff` belongs to a seat this mode never runs'
for k in preflight cannot-verify breaker; do
  present "claims the $k kind for delegated work" "$INLINE" "\`$k\`"
done
present "reads the Dispatch line" "$INLINE" '`**Dispatch:** delegated'
present "links the delegated loop" "$INLINE" "../../reference/delegated-task.md"
present "passes the plan to context-size" "$INLINE" 'context-size --plan PLAN_FILE'
present "subagent mode passes the plan to context-size" "$SDD" 'context-size --plan PLAN_FILE'
present "a delegated task hands off at the next ledger write" "$INLINE" 'In a delegated task, act at the next ledger write'
present "a delegating plan gets a preflight" "$INLINE" 'send one `preflight` item'
present "inline routes the ruling seat" "$INLINE" '`scripts/review-route PLAN_FILE --ruling <kind> [<task> ...]`'
present "inline confirms a Header amendment" "$INLINE" 'A Header amendment from `judge-opus` is confirmed by `judge-fable`'
absent "inline drops the no-preflight sentence" "$INLINE" 'There is no pre-flight scan.'
absent "inline no longer names judge-fable as the ruling seat" "$INLINE" '`dr-superpowers:judge-fable` (`dr-superpowers:judge-opus` when Fable is'
present "inline translates a delegated task's agent" "$INLINE" "translate a delegated task's \`**Implementer:**\` agent before dispatching it"
absent "inline drops the all-inert legacy sentence" "$INLINE" 'no task is dispatched, so their names need no translation'
present "a return to inline starts at a task that is not delegated" "$INLINE" 'The return takes effect at the first remaining task that is not delegated'
```

In `plugins/dr-superpowers/tests/review-route.test.sh`, replace `present "inline mode lists four kinds it does not run" "$P/skills/executing-plans/SKILL.md" 'The other four kinds belong to seats this mode does not run'` with `present "inline mode names the one kind it never runs" "$P/skills/executing-plans/SKILL.md" 'Only `codex-empty-diff` belongs to a seat this mode never runs'`.

Run: `timeout 300 bash plugins/dr-superpowers/tests/inline-mode.test.sh; timeout 300 bash plugins/dr-superpowers/tests/review-route.test.sh`
Expected: both exit 1 on the new pins.

- [ ] **Step 2: Edit `skills/executing-plans/SKILL.md` — top sections**

Replace:

```text
3. Run `scripts/context-size`. On exit 5, invoke dr-superpowers:handoff.
4. Re-read this skill in full before the next task.
```

with:

```text
3. Run `scripts/context-size --plan PLAN_FILE`. On exit 5, invoke
   dr-superpowers:handoff.
4. Re-read this skill in full before the next task. If a task's last ledger
   line is an agent-named assigned line or `fix round R/5`, also re-read
   [delegated-task.md](../../reference/delegated-task.md) before continuing.
```

Replace `dispatches nothing but the ruling seat and the final review.` with `dispatches nothing but the ruling seat, delegated tasks and the final review.`

Replace:

```text
**Why this mode.** The plan's `**Execution:**` line chose it because every task
scores 4 or less with none at risk 3: each is a small change whose text carries
the code, and a subagent per task would cost more in context rebuild than the
task itself. The line's model follows the highest score: Sonnet when every
task is 3 or less, Opus when any task scores 4. Subagent availability has
nothing to do with it - the line decides, and only your human partner
overrides it.

**Why no per-task review.** The eligibility bar is the gate, applied before
execution starts. A task too large, too vague or too risky for this mode never
reaches it: the plan would have said `subagent`. What catches the rest is the
plan's own verification steps, your self-review of each diff, and one broad
review of the whole branch at the end.
```

with:

```text
**Why this mode.** The plan's `**Execution:**` line chose it because at most
half the tasks are heavy (total 5 or more, or risk 3). The rest are small
changes whose text carries the code, and a subagent per task would cost more in
context rebuild than the task itself. The line's model follows the highest
score among the tasks you implement: Sonnet when every one is 3 or less, Opus
when one scores 4; its effort is at least high when the plan delegates.
Subagent availability has nothing to do with it - the line decides, and only
your human partner overrides it.

**Delegated tasks.** A heavy task is not yours to implement. Its brief's second
line is `**Dispatch:** delegated — total <t>, risk <r>`, and `plan-header.md`
ends with `**Dispatch:** delegated — Task <a>, Task <b>`. Run
[delegated-task.md](../../reference/delegated-task.md) for it: an implementer
subagent, the review seat `scripts/review-route` prints, fix rounds up to 5 and
a reviewed complete line. Read that file the first time a delegated task comes
up, not before. Delegated tasks are never batched.

**Why no per-task review of your own tasks.** The eligibility bar is the gate,
applied when the plan was written. A task too large or too risky to implement
here is delegated and reviewed; what catches the rest is the plan's own
verification steps, your self-review of each diff, and one broad review of the
whole branch at the end.
```

Replace:

```text
There is no pre-flight scan. It is one whole-plan judge dispatch, and a plan
eligible for this mode is low-coupling by construction. A plan defect that
surfaces while you work goes to the seat as a `blocked-plan` item.
```

with:

```text
**Preflight.** When `plan-header.md` ends with a `**Dispatch:** delegated`
line, send one `preflight` item to the ruling seat before Task 1 and carry out
its verdicts. A plan with no delegated task has no pre-flight scan: it is one
whole-plan judge dispatch, and a plan of small tasks is low-coupling by
construction. A plan defect that surfaces while you work goes to the seat as a
`blocked-plan` item.
```

Replace:

```text
none` per distinct name. `**Implementer:**` and `**Executor:**` lines are inert
in this mode: no task is dispatched, so their names need no translation.
```

with:

```text
none` per distinct name. `**Executor:**` lines are inert in this mode: nothing
goes to an external executor. `**Implementer:**` lines are inert for the tasks
you implement; translate a delegated task's `**Implementer:**` agent before dispatching it.
```

Replace:

```text
Your human partner may also move a plan the other way, from subagent mode to
this one. Only their explicit instruction does that, and only at the same kind
of boundary.
```

with:

```text
Your human partner may also move a plan the other way, from subagent mode to
this one. Only their explicit instruction does that, and only at the same kind
of boundary. The return takes effect at the first remaining task that is not delegated:
only its `implementer inline (assigned` line records the return, so delegated
tasks before it still run under subagent mode.
```

- [ ] **Step 3: Edit `skills/executing-plans/SKILL.md` — ledger and budget**

Replace `- The fix cap is 3, not subagent mode's 5.` with `- The fix cap is 3 for a task you implement, not subagent mode's 5; a delegated task keeps 5.`

Replace:

```text
- Write each line in the same message as your other bookkeeping, never later.

**Recovery.**
```

with:

```text
- Write each line in the same message as your other bookkeeping, never later.
- A delegated task writes subagent mode's per-task lines instead:
  the agent-named assigned line, `fix round R/5`, `HANDBACK`, `parked`,
  dispatch `Ruling:` lines, `BLOCKED — <agent> exhausted`, and the complete line
  with `review clean` or `K parked` and its scores clause
  (dr-superpowers:subagent-driven-development §The Ledger).

**Recovery.**
```

Insert this row immediately before the row `| none | Not started |` of the Recovery table:

```text
| An agent-named `implementer <agent> (assigned …)` line, or `fix round R/5` | A delegated task: apply [delegated-task.md](../../reference/delegated-task.md) §Recovery |
```

Replace:

```text
- `handoff`: finish the task in flight, write its ledger line, then invoke
  dr-superpowers:handoff. Never hand off mid-task.

Run `scripts/context-size` after each `Task <N>: complete` line and act on its
exit 5 the same way.
```

with:

```text
- `handoff`: finish the task in flight, write its ledger line, then invoke
  dr-superpowers:handoff. Never hand off in the middle of a task you
  implement. In a delegated task, act at the next ledger write, as subagent
  mode does: let the dispatched agent return, write its line, then hand off.

Run `scripts/context-size --plan PLAN_FILE` after each `Task <N>: complete`
line and act on its exit 5 the same way.
```

- [ ] **Step 4: Edit `skills/executing-plans/SKILL.md` — task loop and ruling seat**

Replace:

```text
   budget line. You never read task text any other way: reading the plan file
   directly skips the amendments.
```

with:

```text
   budget line. You never read task text any other way: reading the plan file
   directly skips the amendments. If the brief's second line is
   `**Dispatch:** delegated`, run
   [delegated-task.md](../../reference/delegated-task.md) for this task instead
   of steps 2 to 7, then go to step 8.
```

Replace `8. **Check the budget.** Run `scripts/context-size`.` with `8. **Check the budget.** Run `scripts/context-size --plan PLAN_FILE`.`

Replace:

```text
`amendments.md` and the ledger; you read the header and one brief at a time. It
is the only thing this mode dispatches before the final review.
```

with:

```text
`amendments.md` and the ledger; you read the header and one brief at a time. It
and delegated tasks are all this mode dispatches before the final review.
```

Replace:

```text
**When.** Three points arise in this mode:

| Kind | Decision point |
|---|---|
| `blocked-plan` | The plan is wrong and no path forward is a mechanical choice |
| `plan-conflict` | A final-review finding that conflicts with what the plan's text requires, or is labelled plan-mandated |
| `final-residual` | Findings still open after the final review's one fix wave |

The other four kinds belong to seats this mode does not run: `preflight` (there
is no pre-flight scan), `cannot-verify` (no task reviewer), `breaker` (no
five-round review loop), and `codex-empty-diff` (no external executor).
```

with:

```text
**When.** These points arise in this mode:

| Kind | Decision point |
|---|---|
| `preflight` | Once, before Task 1, when the plan delegates any task (Setup) |
| `blocked-plan` | The plan is wrong and no path forward is a mechanical choice |
| `plan-conflict` | A final-review finding, or a delegated task's review finding, that conflicts with what the plan's text requires, or is labelled plan-mandated |
| `cannot-verify` | A delegated task's "⚠️ Cannot verify from diff" item |
| `breaker` | A delegated task's findings still open after round 5/5 |
| `final-residual` | Findings still open after the final review's one fix wave |

Only `codex-empty-diff` belongs to a seat this mode never runs (no external
executor), and `preflight` arises only for a plan with a delegated task.
```

Replace:

```text
its task, and the paths it needs, with the findings copied verbatim. Dispatch
`dr-superpowers:judge-fable` (`dr-superpowers:judge-opus` when Fable is
unavailable or your human partner declined it - say the substitution aloud)
with
[ruling-prompt.md](../subagent-driven-development/references/ruling-prompt.md),
expanding its placeholders.
```

with:

```text
its task, and the paths it needs, with the findings copied verbatim. Run
`scripts/review-route PLAN_FILE --ruling <kind> [<task> ...]` and dispatch the
`primary` it prints (`dr-superpowers:judge-opus` in place of
`dr-superpowers:judge-fable` when Fable is unavailable or your human partner
declined it - say the substitution aloud) with
[ruling-prompt.md](../subagent-driven-development/references/ruling-prompt.md),
expanding its placeholders. On any exit 2, dispatch
`dr-superpowers:judge-opus` and say why, quoting its message.
```

Replace:

```text
  dispatch carrying the entry and the rejection output; a second rejection is
  BLOCKED.
```

with:

```text
  dispatch carrying the entry and the rejection output; a second rejection is
  BLOCKED. A Header amendment from `judge-opus` is confirmed by `judge-fable`
  before `plan-amend` runs, exactly as
  dr-superpowers:subagent-driven-development §The Ruling Seat describes,
  including its ledger line when Fable is unavailable.
```

- [ ] **Step 5: Edit the subagent skill's After compaction block**

In `plugins/dr-superpowers/skills/subagent-driven-development/SKILL.md`, replace:

```text
3. Run `scripts/context-size`. On exit 5, invoke dr-superpowers:handoff.
4. Re-read this skill in full before the next dispatch.
```

with:

```text
3. Run `scripts/context-size --plan PLAN_FILE`. On exit 5, invoke
   dr-superpowers:handoff.
4. Re-read this skill in full before the next dispatch, and
   [delegated-task.md](../../reference/delegated-task.md) when a task is
   mid-loop (an agent-named assigned line or `fix round R/5`).
```

- [ ] **Step 6: Run the suites to verify they pass**

Run: `timeout 300 bash plugins/dr-superpowers/tests/inline-mode.test.sh && timeout 300 bash plugins/dr-superpowers/tests/review-route.test.sh && timeout 300 bash plugins/dr-superpowers/tests/project-status.test.sh && timeout 120 node scripts/validate-repository.mjs`
Expected: three suites end `0 failed`; the validator prints its valid line.

- [ ] **Step 7: Commit**

```bash
git add plugins/dr-superpowers/skills/executing-plans/SKILL.md plugins/dr-superpowers/skills/subagent-driven-development/SKILL.md plugins/dr-superpowers/tests/inline-mode.test.sh plugins/dr-superpowers/tests/review-route.test.sh
git commit -m "docs(superpowers): run delegated tasks inline"
```

### Task 14: Final review with one findings list

**Files:**
- Modify: `plugins/dr-superpowers/reference/final-review.md`
- Modify: `plugins/dr-superpowers/skills/subagent-driven-development/references/re-review-prompt.md`
- Modify: `plugins/dr-superpowers/reference/external-executor.md`
- Modify: `plugins/dr-superpowers/README.md`
- Test: `plugins/dr-superpowers/tests/inline-mode.test.sh`

**Interfaces:**
- Consumes: nothing.
- Produces: C8.

**Implementer:** dr-superpowers:impl-sonnet-high
**Evaluation:** files 1 - spec 0 - coupling 0 - risk 2 = 3

- [ ] **Step 1: Write the pins first**

In `plugins/dr-superpowers/tests/inline-mode.test.sh`, insert immediately after the line `present "a red gate stops the review" "$FINAL" 'A red gate stops'`:

```bash

# The dedupe seat runs only over two lists; one list goes to the fixer's triage
# and the re-review rules on every rejection.
RRP="$P/skills/subagent-driven-development/references/re-review-prompt.md"
present "final review dedupes only two lists" "$FINAL" '**Dedupe and verify, only with two lists.**'
present "final review names the one-list case" "$FINAL" '**With one list**'
present "the fixer records rejections" "$FINAL" 'under `REJECTED: <finding>`'
present "disputed rejections go to the ruling seat" "$FINAL" '`REJECTION DISPUTED` in the'
present "the re-review rules on rejections" "$RRP" 'REJECTION UPHELD |'
present "an upheld rejection closes" "$RRP" 'An upheld rejection is closed; a disputed one is open.'
present "the Codex round rationale covers one list" "$P/reference/external-executor.md" 'with one list the'
absent "README drops the always-third-seat claim" "$P/README.md" 'which is why every finding goes through a third seat'
```

Run: `timeout 300 bash plugins/dr-superpowers/tests/inline-mode.test.sh`
Expected: FAIL on the new pins; exit 1.

- [ ] **Step 2: Edit `reference/final-review.md`**

Replace:

```text
3. **Dedupe and verify** in one dispatch of `dr-superpowers:judge-fable`
   (`dr-superpowers:judge-opus` when Fable is unavailable or your human partner
   declined it — say the substitution aloud) given both reviewers' lists. It
   merges findings that name the same defect in the same place (not merely the
   same file), tags each `claude`, `codex`, or `both`, and returns `CONFIRMED` or
   `REJECTED` with evidence for each. The verifier is a third seat, so neither
   reviewer grades its own work.
4. **Report** confirmed findings ranked most severe first, then the rejected ones
   with the reason each was rejected. A finding both reviewers raised and the
   judge confirmed is the strongest signal available in this loop; say so.
```

with:

```text
3. **Dedupe and verify, only with two lists.** When the Claude review and the
   Codex round each produced at least one finding, dispatch
   `dr-superpowers:judge-fable` once (`dr-superpowers:judge-opus` when Fable is
   unavailable or your human partner declined it — say the substitution aloud)
   given both lists. It merges findings that name the same defect in the same
   place (not merely the same file), tags each `claude`, `codex`, or `both`, and
   returns `CONFIRMED` or `REJECTED` with evidence for each. The verifier is a
   third seat, so neither reviewer grades its own work.

   **With one list** — Codex off, `TIMEOUT`, `FAILED`, or either reviewer
   returning no findings — there is no step-3 seat. Every finding in the list
   enters the fix wave unverified, and the fixer triages it (Fixing what it
   finds).
4. **Report.** With two lists: confirmed findings ranked most severe first, then
   the rejected ones with the reason each was rejected; a finding both reviewers
   raised and the judge confirmed is the strongest signal available in this
   loop, so say so. With one list: the findings ranked most severe first, then,
   after the fix wave, which were fixed and which the fixer rejected, with the
   re-review's verdict on each rejection.
```

Replace:

```text
A confirmed finding gates the handoff whichever reviewer raised it; a rejected
one never does.
```

with:

```text
A confirmed finding gates the handoff whichever reviewer raised it; a rejected
one never does. With one list, every finding gates the handoff until the fixer
fixes it or rejects it with evidence the re-review upholds.
```

Replace:

```text
Whoever fixes writes `<workspace>/final-fix-report.md`: what changed per
finding, the covering tests, the command and its output. In subagent mode the
```

with:

```text
Whoever fixes writes `<workspace>/final-fix-report.md`: what changed per
finding, the covering tests, the command and its output. With one list the
fixer first checks each finding against the code under
dr-superpowers:receiving-code-review, fixes the real ones, and records each one
it rejects under `REJECTED: <finding>` with its evidence. In subagent mode the
```

Replace:

```text
Send any residual findings to the ruling seat as `final-residual` items and carry
out its verdicts.
```

with:

```text
Send any residual findings — `NOT ADDRESSED`, and `REJECTION DISPUTED` in the
one-list case — to the ruling seat as `final-residual` items and carry out its
verdicts. The scoped re-review is a Claude seat that wrote none of the code, so
a list from Codex alone, which may cover Codex's own executor-lane commits,
still gets an independent reader.
```

- [ ] **Step 3: Edit `references/re-review-prompt.md`**

Replace:

```text
    - **[finding one-liner]** — ADDRESSED | NOT ADDRESSED, with file:line
      evidence. "Attempted" is not addressed: the specific defect must no
      longer exist.
```

with:

```text
    - **[finding one-liner]** — ADDRESSED | NOT ADDRESSED, with file:line
      evidence. "Attempted" is not addressed: the specific defect must no
      longer exist.
    - For a finding the fix report lists under `REJECTED:` (a final review
      with one findings list): **[finding one-liner]** — REJECTION UPHELD |
      REJECTION DISPUTED, with file:line evidence. Uphold only when the
      evidence shows the finding is wrong, not merely unfixed.
```

Replace:

```text
    **Fix round:** [All findings addressed, no new Critical/Important
    breakage | Findings remain open] — list the open ones.
```

with:

```text
    **Fix round:** [All findings addressed, no new Critical/Important
    breakage | Findings remain open] — list the open ones. An upheld rejection is closed; a disputed one is open.
```

- [ ] **Step 4: Edit `reference/external-executor.md` and `README.md`**

In `plugins/dr-superpowers/reference/external-executor.md`, replace:

```text
own commits. That is why every finding - whichever reviewer raised it - is then
verified by a judge that wrote none of the code.
```

with:

```text
own commits. That is why a finding is never acted on unchecked: with two lists a
judge that wrote none of the code verifies every finding, and with one list the
fixer triages each against the code and a Claude re-review that wrote none of it
rules on every rejection ([final-review.md](final-review.md)).
```

In `plugins/dr-superpowers/README.md`, replace:

```text
The final whole-branch review gains a Codex round whose
findings are deduped with the Claude reviewer's and then verified by
`judge-fable` - or `judge-opus` when Fable is unavailable. That round is not
self-review-free, because the branch contains whatever the executor lane
produced, which is why every finding goes through a third seat.
```

with:

```text
The final whole-branch review gains a Codex round. When both
reviewers return findings, `judge-fable` - or `judge-opus` when Fable is
unavailable - dedupes and verifies them. With one list there is no third seat:
the fixer triages each finding against the code and the scoped re-review rules
on every rejection. The Codex round is not self-review-free, because the branch
contains whatever the executor lane produced, which is why no finding is acted
on unchecked.
```

If that README text is split differently after Task 11's edit, match on its sentences, not its line breaks, and keep the replacement's wording.

- [ ] **Step 5: Run the suites to verify they pass**

Run: `timeout 300 bash plugins/dr-superpowers/tests/inline-mode.test.sh && timeout 300 bash plugins/dr-superpowers/tests/review-route.test.sh`
Expected: both end `0 failed`, exit 0.

- [ ] **Step 6: Commit**

```bash
git add plugins/dr-superpowers/reference/final-review.md plugins/dr-superpowers/skills/subagent-driven-development/references/re-review-prompt.md plugins/dr-superpowers/reference/external-executor.md plugins/dr-superpowers/README.md plugins/dr-superpowers/tests/inline-mode.test.sh
git commit -m "docs(superpowers): one list skips dedupe seat"
```

### Task 15: Remaining Fable seats, budget reference and version

**Files:**
- Modify: `plugins/dr-superpowers/skills/selecting-approaches/SKILL.md`
- Modify: `plugins/dr-superpowers/skills/distilling-docs/SKILL.md`
- Modify: `plugins/dr-superpowers/reference/session-budget.md`
- Modify: `plugins/dr-superpowers/.claude-plugin/plugin.json`, `plugins/dr-superpowers/.codex-plugin/plugin.json`
- Test: `plugins/dr-superpowers/tests/distilling-docs.test.sh`, `plugins/dr-superpowers/tests/review-route.test.sh`

**Interfaces:**
- Consumes: C2.
- Produces: nothing.

**Implementer:** dr-superpowers:impl-sonnet-medium
**Evaluation:** files 1 - spec 0 - coupling 0 - risk 1 = 2

- [ ] **Step 1: Update the pins first**

In `plugins/dr-superpowers/tests/distilling-docs.test.sh`, replace these two lines:

```bash
present "dispatches judge-fable" "$SKILL" 'dr-superpowers:judge-fable'
present "names judge-opus as the substitute" "$SKILL" 'dr-superpowers:judge-opus'
```

with:

```bash
present "dispatches judge-opus" "$SKILL" 'Dispatch dr-superpowers:judge-opus with'
```

In `plugins/dr-superpowers/tests/review-route.test.sh`, replace the two lines

```bash
present "the Claude manifest is 1.10.0" "$P/.claude-plugin/plugin.json" '"version": "1.10.0"'
present "the Codex manifest is 1.10.0" "$P/.codex-plugin/plugin.json" '"version": "1.10.0"'
```

with:

```bash
present "the Claude manifest is 1.11.0" "$P/.claude-plugin/plugin.json" '"version": "1.11.0"'
present "the Codex manifest is 1.11.0" "$P/.codex-plugin/plugin.json" '"version": "1.11.0"'
present "the program design names sub-project 10" "$P/../../docs/superpowers/specs/2026-09-11-dr-superpowers-fork-design.md" '**Amendment 2026-09-17 (sub-project 10 spec).**'
present "approach ranking runs on Opus" "$P/skills/selecting-approaches/SKILL.md" 'Dispatch one `dr-superpowers:judge-opus` to run the ring'
present "the budget reference names the controller budget" "$P/reference/session-budget.md" '| Controller budget | 350,000 tokens'
present "the budget checkpoints pass the plan" "$P/reference/session-budget.md" '`context-size --plan PLAN_FILE` after each `Task N: complete` line'
```

Run: `timeout 300 bash plugins/dr-superpowers/tests/distilling-docs.test.sh; timeout 300 bash plugins/dr-superpowers/tests/review-route.test.sh`
Expected: both exit 1 on the changed pins (the program-design pin already passes).

- [ ] **Step 2: Edit the two skills**

In `plugins/dr-superpowers/skills/selecting-approaches/SKILL.md`, replace `**Rank.** Dispatch one `dr-superpowers:judge-fable` to run the ring` with `**Rank.** Dispatch one `dr-superpowers:judge-opus` to run the ring`, and delete these two lines together with the blank line that follows them:

```text
**If Fable is unavailable or your human partner has declined it, dispatch
`judge-opus` instead and say so.** Never substitute silently.
```

In `plugins/dr-superpowers/skills/distilling-docs/SKILL.md`, replace `**The judge reads the working tree, not the commit.** `agents/judge-fable.md`` with `**The judge reads the working tree, not the commit.** `agents/judge-opus.md``, and replace:

```text
Dispatch dr-superpowers:judge-fable (dr-superpowers:judge-opus when Fable is
unavailable or your human partner declined it — say the substitution aloud) with
[distil-judge.md](references/distil-judge.md). It must work in one order:
```

with:

```text
Dispatch dr-superpowers:judge-opus with
[distil-judge.md](references/distil-judge.md). It must work in one order:
```

Run: `grep -rn "judge-fable\|Fable" plugins/dr-superpowers/skills/selecting-approaches plugins/dr-superpowers/skills/distilling-docs`
Expected: no output.

- [ ] **Step 3: Edit `reference/session-budget.md`**

Replace:

```text
| Handoff budget | 475,000 tokens; `DR_SUPERPOWERS_BUDGET` overrides | Owner ruling, 2026-09-11 |
```

with:

```text
| Handoff budget | 475,000 tokens for every session not controlling a subagent-mode plan; `DR_SUPERPOWERS_BUDGET` overrides | Owner ruling, 2026-09-11 |
| Controller budget | 350,000 tokens for a session running a subagent-mode plan, by its Execution line or a ledger that left inline mode; `DR_SUPERPOWERS_BUDGET` overrides | Owner ruling, 2026-09-17: a controller adds about 9.7k per task against inline's 19.1k |
```

Replace `650,000 window compaction lands near 605-625k, so 475k leaves that margin.` with `650,000 window compaction lands near 605-625k, so 475k leaves that margin and 350k leaves more.`

Replace:

```text
`scripts/task-brief` and `scripts/review-package` print it as their last line,
so checking before every task and every review costs no extra request.
`scripts/context-size` prints it on demand (exit 0 ok, 5 handoff, 3 unknown);
```

with:

```text
`scripts/task-brief` and `scripts/review-package` print it as their last line,
measured against their plan's budget, so checking before every task and every
review costs no extra request. `scripts/context-size --plan PLAN_FILE` prints it
on demand (exit 0 ok, 5 handoff, 3 unknown); without `--plan` the budget is
475k;
```

Replace:

```text
- **executing-plans:** the budget line on every `task-brief`, and
  `context-size` after each `Task N: complete` line.
```

with:

```text
- **executing-plans:** the budget line on every `task-brief`, and
  `context-size --plan PLAN_FILE` after each `Task N: complete` line.
```

- [ ] **Step 4: Bump the version**

In `plugins/dr-superpowers/.claude-plugin/plugin.json` and `plugins/dr-superpowers/.codex-plugin/plugin.json`, replace `"version": "1.10.0"` with `"version": "1.11.0"`.

- [ ] **Step 5: Run the whole verification**

Run each, in order, and read every result:

```bash
timeout 300 bash plugins/dr-superpowers/tests/distilling-docs.test.sh
timeout 300 bash plugins/dr-superpowers/tests/review-route.test.sh
timeout 120 node scripts/validate-repository.mjs
timeout 1800 node scripts/test-all.mjs
timeout 120 claude plugin validate .
timeout 120 claude plugin validate plugins/dr-superpowers
timeout 120 claude plugin validate plugins/dr-status
timeout 120 claude plugin validate plugins/dcc-darkraise-ui
timeout 120 claude plugin validate plugins/dcc-darkraise-win32ui
```

Expected: the two suites end `0 failed`; the validator prints its valid line; `test-all.mjs` fails only `tests/ui-discovery.test.mjs` with `rg: command not found`; every `claude plugin validate` passes. Any other failure is a finding: fix it in this task if it is a pin this plan moved, otherwise report it.

Confirm nothing this run started is still running: `ps -ef | grep -E "node|claude" | grep -v grep` lists no process started by the commands above.

- [ ] **Step 6: Commit**

```bash
git add plugins/dr-superpowers/skills/selecting-approaches/SKILL.md plugins/dr-superpowers/skills/distilling-docs/SKILL.md plugins/dr-superpowers/reference/session-budget.md plugins/dr-superpowers/.claude-plugin/plugin.json plugins/dr-superpowers/.codex-plugin/plugin.json plugins/dr-superpowers/tests/distilling-docs.test.sh plugins/dr-superpowers/tests/review-route.test.sh
git commit -m "chore(superpowers): release 1.11.0"
```
