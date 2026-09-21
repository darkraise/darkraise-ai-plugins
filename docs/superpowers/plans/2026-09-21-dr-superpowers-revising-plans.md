# Revising Plans For The Executor Lane Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: the skill the **Execution:** line names — dr-superpowers:subagent-driven-development for `subagent`, dr-superpowers:executing-plans for `inline`. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give `dr-superpowers` one shared rule for reading `**Evaluation:**` lines, and a script and skill that bring a plan written before the external executor lane up to the current plan format.

**Architecture:** Four helpers in `scripts/lib/plan.sh` become the only way any script reads `**Evaluation:**`, `**Executor:**` and `#### Part <L>:` lines out of task text; `plan_scores`, `review-route` and `plan-lint` are converted to them, which fixes two shipped defects. A new read-only `scripts/plan-revise` reports per-unit gate verdicts and a computed execution recommendation, and a new `revising-plans` skill does the scoring and the edits.

**Tech Stack:** bash 5, awk (mawk-compatible — no `match(s, re, arr)`, no `gensub`), jq, git.

**Spec:** `docs/superpowers/specs/2026-09-21-dr-superpowers-revising-plans-design.md`

**Execution:** inline — `claude --model sonnet --effort high` — 1 of 7 tasks is heavy and 1 is four-band, so the majority is not heavy; the four-band task is within a third of the plan and five tasks carry an `**Executor:**` line, so every task is delegated and the controller only dispatches and reviews.

**Plan review:** 2026-09-21 — dr-superpowers:judge-opus — executability 18 / coherence 16 / coverage 18 / assumptions 19 (round 3)

> **External executors:** codex

## Global Constraints

- **Language:** English only in code, comments, docs, commits and tests.
- **Comments:** default to none. Add one only when the WHY is non-obvious — a hidden constraint, a subtle invariant, a workaround. Never explain WHAT the code does, and never reference this plan or a task number.
- **Commits:** `<type>(<scope>): <subject>`, type one of feat|fix|docs|style|refactor|test|chore|perf, subject ≤50 chars, imperative, no period. End every commit message with `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>`.
- **awk must run under mawk.** `match(string, regex, array)` and `gensub` are gawk extensions and are unavailable. Capture groups come from bash `[[ =~ ]]` and `BASH_REMATCH`, as `plan_scores` already does.
- **Every test suite is `bash tests/<name>.test.sh` and prints `<n> passed, <m> failed` as its last line.** Run suites with an explicit timeout: `timeout 300 bash tests/<name>.test.sh`.
- **`scripts/lib/plan.sh` is sourced, never executed.** It defines functions only and must not run anything at load time.
- **Do not change the shipped `reference/ladder.md` blocks.** The gate thresholds and assignment rungs are read from it at runtime, never copied into a script.
- The plugin root for every path below is `plugins/dr-superpowers/`. Paths in this plan are repository-relative from the repository root.

## Contracts

Names one task produces and another consumes. Use them exactly as written.

**Task 1 produces — four functions in `plugins/dr-superpowers/scripts/lib/plan.sh`.** Each reads task text on **stdin** and writes to stdout:

```bash
# plan_lines LABEL       — the `**LABEL:**` lines outside every fence, in order.
# plan_task_parts        — the part letters (`A`, `B`, …), in order, one per line.
# plan_part_text PART    — the text of one part, starting at its heading.
# plan_eval_lines        — the **Evaluation:** lines that score this text.
```

`plan_eval_lines` is the scoring rule: a line scores when it is outside every fence, and — when the text holds any `#### Part <L>:` heading outside a fence — at or after the first such heading. Callers: Task 1 (`plan_scores`), Task 2 (`review-route`), Task 3 (`plan-lint`), Task 4 (`plan-revise`).

**Task 4 produces — `plugins/dr-superpowers/scripts/plan-revise`**, with this exact output grammar:

```
header  execution=<inline|subagent|missing>  executors=<ids|missing>  sections=<ok|comma-list>
unit <id>  score=<total|?|->  risk=<r|?|->  rule_s=<ok|violated|unknown>  gate=<pass|fail:total|fail:risk|fail:rule_s|fail:override|fail:not_enabled|unknown>  executor=<id|none>  rungs=<id>:<model>/<effort>[,<id>:<model>/<effort>]
recommend  execution=<inline|subagent>  model=<sonnet|opus>  effort=<low|medium|high>  delegated=<n>/<tasks>
```

`<id>` on a `unit` row is a task number (`7`) or a task number and part letter (`7B`). Fields are separated by **two** spaces, so a value may contain single spaces. `rungs=` is empty when `gate` is not `pass`. Exit 0 reported, 1 nothing to revise, 2 usage or a missing path.

Task 4 also produces these shell functions and variables inside that file, which Task 5 reuses unchanged:

```bash
# LADDER                — the ladder path, overridable by DR_PLAN_REVISE_LADDER
# EXEC_IDS              — every registered executor id, one per line
# EXEC_TABLE            — "<id> <min_score> <max_risk>" per registered executor
#                         whose gate block is readable, one per line, read once.
#                         Task 5's survey reads it; keep it even though
#                         single-plan mode does not
# block NAME            — the body of the ```NAME fenced block in $LADDER
# exec_gate ID KEY      — that executor's gate threshold (min_score, max_risk)
# exec_rung ID TOTAL    — that executor's rung as "<model>/<effort>"
# axes                  — reads Evaluation lines on stdin; prints
#                         "files spec coupling risk total" taking the highest
#                         total and the highest risk INDEPENDENTLY, "?" when a
#                         line does not parse, "-" when there are none
# header_executors PLAN — the ids on the header's External executors line
# plan_units PLAN       — "id<TAB>text" per scoring unit, newlines as \v
```

**Task 5 produces — the `--survey DIR` mode**, with this exact row grammar:

```
plan  <basename>  tasks=<n>  scored=<n>  unparsed=<n>  eligible=<n|-|n+?>  exec=<inline|subagent|->  executors=<ids|->  live=<yes|no|unknown>  <evidence>
```

**Task 6 produces — `plugins/dr-superpowers/skills/revising-plans/SKILL.md`**, frontmatter `name: revising-plans`.

## Assumptions (evidence)

- `scripts/codex-gate` reports `lane=true` and `scripts/executors list` prints exactly `codex` — run 2026-09-21, output `codex-gate usable=true reason=ok review=true lane=true resets_at=- source=cache`. `docs/superpowers/distilled/constraints.md` §"The Codex executor lane is on" then ticks codex without asking, which is why the header carries the executors line.
- The lane gate is `min_score 2`, `max_risk 1`, `require_rule_s_clean true`, `require_external_enabled true` — `plugins/dr-superpowers/reference/ladder.md:193-197`.
- The codex assignment rungs are `2 gpt-5.5 medium`, `3 gpt-5.5 high`, `4 gpt-5.6-sol high` — `plugins/dr-superpowers/reference/ladder.md:214-218`.
- Rule S is `reducible = files + spec + coupling`, violated when `reducible >= 4` or `spec = 3` — `plugins/dr-superpowers/reference/ladder.md:37-40`.
- `plan_scores` currently reports `1 6 1` for a split task with a stale parent line scoring 6 over parts scoring 2 — reproduced 2026-09-21.
- `review-route --task 1` currently routes a task scoring 2 that holds a fenced risk-3 example to `codex:heavy+judge-fable reason=risk` — reproduced 2026-09-21.
- `plan-lint` currently reports no missing-Evaluation error for a task whose only `**Evaluation:**` line is inside a fence — reproduced 2026-09-21.
- `plan_ledger` resolves `<toplevel>/.superpowers/sdd/<basename without .md>/progress.md` and requires the ledger's identity line to name the plan — `plugins/dr-superpowers/scripts/lib/plan.sh:221-236`.
- `finishing-a-development-branch` writes the `via PR` line on the branch **before** the push, and Step 6 worktree cleanup does not run on that path — `plugins/dr-superpowers/skills/finishing-a-development-branch/SKILL.md:208-226`.
- Batching is decided at dispatch from the briefs of contiguous candidate tasks, and a batched task never runs on an external executor — `plugins/dr-superpowers/skills/subagent-driven-development/SKILL.md:420-428`. No plan-file marker for a batch exists, which is why `plan-revise` reports none.
- A second executor is available to tests: `plugins/dr-superpowers/tests/fixtures/executors/stub.json` declares the `stub` id with its own `stub-gate` and `stub-assignment` blocks in `plugins/dr-superpowers/tests/fixtures/stub-ladder.md`, reachable through `DR_EXECUTORS_DIR` and `DR_PLAN_REVISE_LADDER`. Task 4 uses it so the multi-executor path is exercised rather than assumed.
- `plan-lint` makes **any** `**Executor:**` line on a task carrying an `**Override:**` line a hard error, independent of Rule S: `plugins/dr-superpowers/scripts/plan-lint:301` reads `[ "$sev" = ERROR ] || say ERROR "$where" "an Executor line on an overridden task fails the lane gate"`, and `$sev` is WARN exactly when an Override line is present (`plan-lint:239`). An Override is also used for reserve tiers and assignment mismatches (`plan-lint:283,285`), so a Rule-S-clean unit can carry one. `plan-revise` therefore reports `gate=fail:override` for any overridden unit; without it the skill would write a line that its own verification step then rejects.
- `tests/review-route.test.sh` calls `review_surface false` at line 416 and never restores it, so tests appended after it must call `review_surface true` first or every seat routes to Claude with `reason=codex-off`.
- Skills are discovered from `./skills/`; neither manifest enumerates them — `plugins/dr-superpowers/.codex-plugin/plugin.json` has `"skills": "./skills/"` and the Claude manifest has no skills key.

## Task index

1. The shared reader in `lib/plan.sh`
2. `review-route` reads through the shared helpers
3. `plan-lint` reads through the shared helpers, and notes a stale parent score
4. `plan-revise`, single-plan mode
5. `plan-revise`, survey mode
6. The `revising-plans` skill
7. Register rows and the release

---

### Task 1: The shared reader in `lib/plan.sh`

**Files:**
- Modify: `plugins/dr-superpowers/scripts/lib/plan.sh` (add four functions after `plan_task_text`; change `plan_scores`)
- Test: `plugins/dr-superpowers/tests/plan-lib.test.sh` (append a section)

**Interfaces:**
- Consumes: nothing.
- Produces: the four functions in Contracts, Task 1 block.

**Implementer:** dr-superpowers:impl-opus-medium
**Evaluation:** files 1 - spec 0 - coupling 2 - risk 2 = 5

- [ ] **Step 1: Write the failing tests**

Append to `plugins/dr-superpowers/tests/plan-lib.test.sh`, at the end of the file but **before** any final summary `printf`. Find the last line of the file first with `tail -n 5 plugins/dr-superpowers/tests/plan-lib.test.sh`; the summary block looks like `printf '\n%d passed, %d failed\n' "$pass" "$fail"`. Insert this above it:

```bash
# --- the shared Evaluation reader ---
# Two shipped defects motivate these. A line left above `#### Part A` scores the
# task as it was before the split, which is the score that forced the split. And
# a plan that shows an example line inside a fence is documenting the format.
printf '# P\n\n### Task 1: Split\n\n**Evaluation:** files 2 - spec 1 - coupling 2 - risk 1 = 6\n\n#### Part A: a\n\n**Evaluation:** files 1 - spec 0 - coupling 1 - risk 0 = 2\n\n#### Part B: b\n\n**Evaluation:** files 1 - spec 0 - coupling 1 - risk 0 = 2\n' > "$TMP/split.md"
check "plan_eval_lines: a stale parent line does not score a split task" \
  "$(plan_task_text "$TMP/split.md" 1 | plan_eval_lines | grep -c .)" "2"
check "plan_scores: a split task scores from its parts" \
  "$(plan_scores "$TMP/split.md" | tr '\t\n' ' |')" "1 2 0|"
check "plan_heavy: a split task is not heavy on its stale parent score" \
  "$(plan_heavy "$TMP/split.md")" ""

printf '# P\n\n### Task 1: Fenced\n\n**Evaluation:** files 1 - spec 0 - coupling 1 - risk 0 = 2\n\n```markdown\n**Evaluation:** files 2 - spec 1 - coupling 2 - risk 3 = 6\n```\n' > "$TMP/fenced.md"
check "plan_eval_lines: a fenced example does not score" \
  "$(plan_task_text "$TMP/fenced.md" 1 | plan_eval_lines | grep -c .)" "1"
check "plan_scores: a fenced example does not score" \
  "$(plan_scores "$TMP/fenced.md" | tr '\t\n' ' |')" "1 2 0|"

printf '# P\n\n### Task 1: Fenced part\n\n**Evaluation:** files 1 - spec 0 - coupling 1 - risk 0 = 2\n\n```markdown\n#### Part A: example\n\n**Evaluation:** files 2 - spec 1 - coupling 2 - risk 3 = 6\n```\n' > "$TMP/fencedpart.md"
check "plan_task_parts: a fenced part heading is not a part" \
  "$(plan_task_text "$TMP/fencedpart.md" 1 | plan_task_parts)" ""
check "plan_scores: a fenced part heading does not suppress the real line" \
  "$(plan_scores "$TMP/fencedpart.md" | tr '\t\n' ' |')" "1 2 0|"

check "plan_task_parts: real parts, in order" \
  "$(plan_task_text "$TMP/split.md" 1 | plan_task_parts | tr '\n' ' ')" "A B "
check "plan_part_text: one part's text only" \
  "$(plan_task_text "$TMP/split.md" 1 | plan_part_text B | grep -c '^\*\*Evaluation')" "1"
check "plan_part_text: an absent part is empty" \
  "$(plan_task_text "$TMP/split.md" 1 | plan_part_text Z)" ""

printf '# P\n\n### Task 1: Executor\n\n**Executor:** codex gpt-5.5 / medium\n\n```markdown\n**Executor:** codex gpt-5.6-sol / high\n```\n' > "$TMP/exec.md"
check "plan_lines: a fenced label line is not a line" \
  "$(plan_task_text "$TMP/exec.md" 1 | plan_lines Executor | grep -c .)" "1"

# The four-band threshold moves in both directions, so both are pinned. With the
# stale line the plan delegates two of three tasks; without it, two of three are
# four-band, 3 x 2 > 3, and nothing is delegated.
printf '# P\n\n### Task 1: One\n\n**Evaluation:** files 2 - spec 1 - coupling 2 - risk 0 = 5\n\n#### Part A: a\n\n**Evaluation:** files 1 - spec 1 - coupling 2 - risk 0 = 4\n\n#### Part B: b\n\n**Evaluation:** files 1 - spec 0 - coupling 1 - risk 0 = 2\n\n### Task 2: Two\n\n**Evaluation:** files 1 - spec 1 - coupling 2 - risk 0 = 4\n\n### Task 3: Three\n\n**Evaluation:** files 1 - spec 0 - coupling 1 - risk 0 = 2\n' > "$TMP/fourband.md"
check "plan_delegated: the corrected score drops the plan below the four-band third" \
  "$(plan_delegated "$TMP/fourband.md" | tr '\t\n' ' |')" ""

printf '# P\n\n### Task 1: One\n\n**Evaluation:** files 2 - spec 1 - coupling 2 - risk 0 = 5\n\n### Task 2: Two\n\n**Evaluation:** files 1 - spec 1 - coupling 2 - risk 0 = 4\n\n### Task 3: Three\n\n**Evaluation:** files 1 - spec 0 - coupling 1 - risk 0 = 2\n' > "$TMP/unsplit.md"
check "plan_delegated: an unsplit plan is unchanged by the fix" \
  "$(plan_delegated "$TMP/unsplit.md" | tr '\t\n' ' |')" "1 heavy|2 total 4|"

check "plan_executors: unchanged by the fix" \
  "$(plan_executors "$TMP/exec.md" | tr '\t\n' ' |')" "1 codex|"
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `timeout 300 bash plugins/dr-superpowers/tests/plan-lib.test.sh 2>&1 | tail -20`

Expected: FAIL lines including `plan_eval_lines: a stale parent line does not score a split task` (command not found yields an empty count `0`, want `2`) and `plan_scores: a split task scores from its parts` (got `1 6 1|`, want `1 2 0|`).

- [ ] **Step 3: Add the four helpers**

In `plugins/dr-superpowers/scripts/lib/plan.sh`, find the end of `plan_task_text` — the function that begins at the `plan_task_text() {` line and ends with the `}` on its own line before the `# plan_scores FILE` comment. Insert these four functions between that `}` and the `# plan_scores FILE` comment:

```bash
# plan_lines LABEL — the `**LABEL:**` lines of the task text on stdin that lie
# outside every fenced block, in order. A plan that shows a line inside a fence
# is documenting the format, not annotating a task.
plan_lines() {
  awk -v lab="$1" "$_PLAN_AWK"'
    in_fence($0) { next }
    index($0, "**" lab ":**") == 1 { print }
  '
}

# plan_task_parts — the part letters of the task text on stdin, in order, one
# per line. A `#### Part <L>:` heading inside a fence is an example, not a part.
plan_task_parts() {
  awk "$_PLAN_AWK"'
    in_fence($0) { next }
    /^#### Part [A-Z]:/ { print substr($3, 1, 1) }
  '
}

# plan_part_text PART — the text of one part of the task text on stdin, from its
# heading to the next part heading. A fenced line belongs to the part that
# opened the fence, so a fenced part heading neither opens nor closes a part.
plan_part_text() {
  awk -v p="$1" "$_PLAN_AWK"'
    in_fence($0) { if (on) print; next }
    /^#### Part [A-Z]:/ { on = (substr($3, 1, 1) == p) }
    on { print }
  '
}

# plan_eval_lines — the **Evaluation:** lines that score the task text on stdin.
# Fenced lines never score. When the text holds any part heading, only the lines
# at or after the first one score: a line left above `#### Part A` scores the
# task as it stood before the split, which is the score that forced the split.
plan_eval_lines() {
  awk "$_PLAN_AWK"'
    in_fence($0) { next }
    /^#### Part [A-Z]:/ { parts = 1; next }
    /^\*\*Evaluation:\*\*/ { if (parts) print; else pre[++k] = $0 }
    END { if (!parts) for (i = 1; i <= k; i++) print pre[i] }
  '
}
```

- [ ] **Step 4: Convert `plan_scores` to the helper**

In the same file, inside `plan_scores`, replace this line:

```bash
    evs=$(plan_task_text "$1" "$n" | awk "$_PLAN_AWK"'in_fence($0) { next } /^\*\*Evaluation:\*\*/ { print }')
```

with:

```bash
    evs=$(plan_task_text "$1" "$n" | plan_eval_lines)
```

Then update the `plan_scores` comment block directly above the function. Replace the line reading:

```bash
# and the highest risk among the task's Claude-host **Evaluation:** lines outside
# fences (a split task has one per part). "N<TAB>-<TAB>-" when the task has no
```

with:

```bash
# and the highest risk among the task's Claude-host **Evaluation:** lines, as
# plan_eval_lines selects them. "N<TAB>-<TAB>-" when the task has no
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `timeout 300 bash plugins/dr-superpowers/tests/plan-lib.test.sh 2>&1 | tail -5`

Expected: PASS — the last line reads `<n> passed, 0 failed`.

- [ ] **Step 6: Run every suite that reads `plan_scores`**

Run:

```bash
cd plugins/dr-superpowers
for t in plan-lib plan-lint review-route inline-mode snapshot task-state; do
  printf '%s: ' "$t"; timeout 300 bash "tests/$t.test.sh" 2>&1 | tail -1
done
```

Expected: every line ends `0 failed`. `inline-mode` is the suite that drives `task-brief`; the plugin ships no `tests/task-brief.test.sh`. A failure in `review-route` or `plan-lint` is expected only if it names a fenced or split fixture — record the failing test names and fix them in Task 2 or Task 3, not here. Any other failure is a defect in this task.

- [ ] **Step 7: Commit**

The three call sites land in Tasks 1, 2 and 3 as consecutive commits rather than one. A task touching the helper, all three scripts and four suites scores `files 3`, which Rule S forbids; and the intermediate states are not a regression, because `review-route` and `plan-lint` already disagree with `plan_scores` today. Spec §11 records this.

```bash
git add plugins/dr-superpowers/scripts/lib/plan.sh plugins/dr-superpowers/tests/plan-lib.test.sh
git commit -m "fix(superpowers): score a task from its real Evaluation lines

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 2: `review-route` reads through the shared helpers

**Files:**
- Modify: `plugins/dr-superpowers/scripts/review-route` (the `--task` argument loop)
- Test: `plugins/dr-superpowers/tests/review-route.test.sh` (append a section)

**Interfaces:**
- Consumes: `plan_eval_lines`, `plan_part_text`, `plan_lines` — Contracts, Task 1 block.
- Produces: nothing other tasks consume.

**Implementer:** dr-superpowers:impl-opus-low
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 2 = 4

- [ ] **Step 1: Write the failing tests**

Append to `plugins/dr-superpowers/tests/review-route.test.sh`, immediately above its final summary `printf`. The suite already defines `check`, `$ROUTE` (the script), and `$TMP` (its scratch directory); this block uses those and adds only a local `seat` helper and a `LIGHT` constant. It writes each fixture as a one-line `printf` so that no heading or label inside a fixture begins a line of the suite file.

````bash
# --- the shared Evaluation reader ---
# Two shipped defects: a fenced example line escalated the seat to the risk-3
# rung, and a stale line above `#### Part A` routed a split task on the score
# that forced the split.
# The suite leaves the review surface closed, and a closed surface routes every
# seat to Claude with reason=codex-off, which is not what these cases are about.
review_surface true

seat() { # seat <file> <id>; sets out and rc
  out=$(bash "$ROUTE" "$1" --task "$2" 2>"$TMP/err"); rc=$?
}
LIGHT="primary=codex:light fallback=dr-superpowers:judge-sonnet-high reason=band"

printf '# P\n\n### Task 1: Fenced\n\n**Evaluation:** files 1 - spec 0 - coupling 1 - risk 0 = 2\n\n```markdown\n**Evaluation:** files 2 - spec 1 - coupling 2 - risk 3 = 6\n```\n' > "$TMP/ev-fenced.md"
seat "$TMP/ev-fenced.md" 1
check "a fenced example does not escalate the seat" "$out" "review-seat task=1 $LIGHT"
check "a fenced example exits 0" "$rc" "0"

printf '# P\n\n### Task 1: Split\n\n**Evaluation:** files 2 - spec 1 - coupling 2 - risk 1 = 6\n\n#### Part A: a\n\n**Evaluation:** files 1 - spec 0 - coupling 1 - risk 0 = 2\n\n#### Part B: b\n\n**Evaluation:** files 1 - spec 0 - coupling 1 - risk 0 = 2\n' > "$TMP/ev-split.md"
seat "$TMP/ev-split.md" 1
check "a whole-task id routes on its parts" "$out" "review-seat task=1 $LIGHT"
seat "$TMP/ev-split.md" 1A
check "a part id is unchanged" "$out" "review-seat task=1A $LIGHT"

# A part filter that does not skip fences reads an example inside the part.
printf '# P\n\n### Task 1: Split with an example\n\n#### Part A: a\n\n**Evaluation:** files 1 - spec 0 - coupling 1 - risk 0 = 2\n\n```markdown\n**Evaluation:** files 2 - spec 1 - coupling 2 - risk 3 = 6\n```\n\n#### Part B: b\n\n**Evaluation:** files 1 - spec 0 - coupling 1 - risk 0 = 2\n' > "$TMP/ev-partfence.md"
seat "$TMP/ev-partfence.md" 1A
check "a fenced example inside a part does not escalate it" "$out" "review-seat task=1A $LIGHT"
seat "$TMP/ev-partfence.md" 1
check "a fenced example inside a part does not escalate the whole task" "$out" "review-seat task=1 $LIGHT"

printf '# P\n\n### Task 1: Fenced executor\n\n**Evaluation:** files 1 - spec 0 - coupling 1 - risk 0 = 2\n\n```markdown\n**Executor:** codex gpt-5.5 / medium\n```\n' > "$TMP/ev-fexec.md"
seat "$TMP/ev-fexec.md" 1
check "a fenced Executor line does not claim the task is offloaded" "$out" "review-seat task=1 $LIGHT"

printf '# P\n\n### Task 1: Real executor\n\n**Evaluation:** files 1 - spec 0 - coupling 1 - risk 0 = 2\n**Executor:** codex gpt-5.5 / medium\n' > "$TMP/ev-rexec.md"
seat "$TMP/ev-rexec.md" 1
check "a real Executor line still routes to a Claude judge" "$out" \
  "review-seat task=1 primary=dr-superpowers:judge-sonnet-high fallback=- reason=executor"
````

`task-brief` reads its band through `plan_scores`, which Task 1 already pins, and the plugin ships no `tests/task-brief.test.sh`; no assertion is added for it here.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `timeout 300 bash plugins/dr-superpowers/tests/review-route.test.sh 2>&1 | grep -A2 FAIL | head -20`

Expected: FAIL on `a fenced example does not escalate the seat` — got `review-seat task=1 primary=codex:heavy+judge-fable fallback=dr-superpowers:judge-fable reason=risk`, want the light band.

- [ ] **Step 3: Convert the `--task` loop**

In `plugins/dr-superpowers/scripts/review-route`, find this block near the foot of the file:

```bash
  text=$(plan_task_text "$src" "$n") || die "no Task $n in the plan"
  if [ -n "$part" ]; then
    text=$(awk -v p="$part" '/^#### Part [A-Z]:/ { on = (substr($3, 1, 1) == p) } on' <<<"$text")
    [ -n "$text" ] || die "no part $part in Task $n"
  fi
  grep -qE '^\*\*Executor:\*\*' <<<"$text" && executor=1
  evs=$(grep -E '^\*\*Evaluation:\*\*' <<<"$text" || true)
  [ -n "$evs" ] || die "Task $id has no **Evaluation:** line"
```

Replace it with:

```bash
  text=$(plan_task_text "$src" "$n") || die "no Task $n in the plan"
  if [ -n "$part" ]; then
    text=$(plan_part_text "$part" <<<"$text")
    [ -n "$text" ] || die "no part $part in Task $n"
  fi
  [ -z "$(plan_lines Executor <<<"$text")" ] || executor=1
  evs=$(plan_eval_lines <<<"$text")
  [ -n "$evs" ] || die "Task $id has no **Evaluation:** line"
```

`grep -q … && executor=1` was also the last command of its line; the new form uses an explicit test so the script's exit status never depends on whether a task carries an Executor line.

- [ ] **Step 4: Run the tests to verify they pass**

Run:

```bash
printf 'review-route: '; timeout 300 bash plugins/dr-superpowers/tests/review-route.test.sh 2>&1 | tail -1
printf 'inline-mode: '; timeout 300 bash plugins/dr-superpowers/tests/inline-mode.test.sh 2>&1 | tail -1
```

Expected: both end `0 failed`. `inline-mode` drives `task-brief`, so it is the suite that would notice a band changing underneath it.

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-superpowers/scripts/review-route plugins/dr-superpowers/tests/review-route.test.sh
git commit -m "fix(superpowers): route on the task's real scores

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 3: `plan-lint` reads through the shared helpers, and notes a stale parent score

**Files:**
- Modify: `plugins/dr-superpowers/scripts/plan-lint` (the per-task assignment loop that begins `for n in $nums; do` and contains `parts=$(grep -oE '^#### Part [A-Z]:'`)
- Test: `plugins/dr-superpowers/tests/plan-lint.test.sh` (append a section)

**Interfaces:**
- Consumes: `plan_eval_lines`, `plan_lines`, `plan_part_text`, `plan_task_parts` — Contracts, Task 1 block.
- Produces: nothing other tasks consume.

**Implementer:** dr-superpowers:impl-sonnet-high
**Executor:** codex gpt-5.5 / high
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 1 = 3

- [ ] **Step 1: Write the failing tests**

Append to `plugins/dr-superpowers/tests/plan-lint.test.sh`, immediately above its final summary `printf`. The suite already defines `check`, `has`, `lacks`, `lint <file>` (which sets `$out` and `$status`), and has `cd`-ed into `$TMP` where `docs/spec.md` exists; this block adds one local fixture helper and uses those.

````bash
# --- the shared Evaluation reader ---
# A task whose only score sits inside a fence used to pass: the linter read the
# example as the task's line, so an unscored task reached execution unrouted.
lintplan() { # lintplan <file> <task body>
  { cat <<'HDR'
# Demo Implementation Plan

**Goal:** Demo.

**Spec:** `docs/spec.md`

**Execution:** inline — `claude --model sonnet --effort medium` — one light task

**Plan review:** 2026-09-21 — dr-superpowers:judge-opus — executability 18 / coherence 18 / coverage 18 / assumptions 18 (round 1)

## Global Constraints

- Bash only.

## Contracts

None

## Assumptions (evidence)

- None.

## Task index

1. One

---

HDR
    printf '%s\n' "$2"
  } > "$1"
}

lintplan fenced-only.md "$(printf '### Task 1: One\n\n**Files:**\n- Create: `x.txt`\n\n**Implementer:** dr-superpowers:impl-sonnet-medium\n\n```markdown\n**Evaluation:** files 1 - spec 0 - coupling 1 - risk 0 = 2\n```\n')"
lint fenced-only.md
has "a fenced-only score is a missing Evaluation line" "$out" "ERROR Task 1: missing **Evaluation:** line"

lintplan stale-parent.md "$(printf '### Task 1: One\n\n**Files:**\n- Create: `x.txt`\n\n**Evaluation:** files 2 - spec 1 - coupling 2 - risk 1 = 6\n\n#### Part A: a\n\n**Files:**\n- Create: `a.txt`\n\n**Implementer:** dr-superpowers:impl-sonnet-medium\n**Evaluation:** files 1 - spec 0 - coupling 1 - risk 0 = 2\n\n#### Part B: b\n\n**Files:**\n- Create: `b.txt`\n\n**Implementer:** dr-superpowers:impl-sonnet-medium\n**Evaluation:** files 1 - spec 0 - coupling 1 - risk 0 = 2\n')"
lint stale-parent.md
has "a stale parent score is a NOTE" "$out" \
  "NOTE Task 1: an **Evaluation:** line above the first part does not score the task"
lacks "a stale parent score is not an error" "$out" "ERROR Task 1"
check "the stale-parent fixture is otherwise clean" "$status" "0"

lintplan clean-split.md "$(printf '### Task 1: One\n\n**Files:**\n- Create: `x.txt`\n\n#### Part A: a\n\n**Files:**\n- Create: `a.txt`\n\n**Implementer:** dr-superpowers:impl-sonnet-medium\n**Evaluation:** files 1 - spec 0 - coupling 1 - risk 0 = 2\n\n#### Part B: b\n\n**Files:**\n- Create: `b.txt`\n\n**Implementer:** dr-superpowers:impl-sonnet-medium\n**Evaluation:** files 1 - spec 0 - coupling 1 - risk 0 = 2\n')"
lint clean-split.md
lacks "a clean split earns no NOTE" "$out" "above the first part"
check "the clean-split fixture lints clean" "$status" "0"

lintplan fenced-part.md "$(printf '### Task 1: One\n\n**Files:**\n- Create: `x.txt`\n\n**Implementer:** dr-superpowers:impl-sonnet-medium\n**Evaluation:** files 1 - spec 0 - coupling 1 - risk 0 = 2\n\n```markdown\n#### Part A: an example, not a part\n```\n')"
lint fenced-part.md
lacks "a fenced part heading does not create a part" "$out" "Task 1 part A"
````

- [ ] **Step 2: Run the tests to verify they fail**

Run: `timeout 300 bash plugins/dr-superpowers/tests/plan-lint.test.sh 2>&1 | grep -A2 FAIL | head -20`

Expected: FAIL on `a fenced-only score is a missing Evaluation line`, on `a stale parent score is a NOTE`, and on `a fenced part heading does not create a part`.

- [ ] **Step 3: Convert the loop and add the NOTE**

In `plugins/dr-superpowers/scripts/plan-lint`, find:

```bash
for n in $nums; do
  full=$(plan_task_text "$src" "$n")
  parts=$(grep -oE '^#### Part [A-Z]:' <<<"$full" | awk '{ print substr($3, 1, 1) }' || true)
  for part in ${parts:--}; do
  if [ "$part" = - ]; then
    where="Task $n" text=$full
  else
    where="Task $n part $part"
    text=$(awk -v p="$part" '/^#### Part [A-Z]:/ { on = (substr($3, 1, 1) == p) } on' <<<"$full")
  fi
  line() { grep -m 1 -E "^\*\*$1:\*\*" <<<"$text" || true; }
```

Replace those lines with:

```bash
for n in $nums; do
  full=$(plan_task_text "$src" "$n")
  parts=$(plan_task_parts <<<"$full")
  if [ -n "$parts" ] \
     && [ "$(plan_lines Evaluation <<<"$full" | grep -c .)" \
          -gt "$(plan_eval_lines <<<"$full" | grep -c .)" ]; then
    say NOTE "Task $n" "an **Evaluation:** line above the first part does not score the task"
  fi
  for part in ${parts:--}; do
  if [ "$part" = - ]; then
    where="Task $n" text=$full
  else
    where="Task $n part $part"
    text=$(plan_part_text "$part" <<<"$full")
  fi
  line() { plan_lines "$1" <<<"$text" | head -n 1; }
```

`plan_task_parts` returns letters one per line, which `${parts:--}` word-splits exactly as the old `awk` output did.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `printf 'plan-lint: '; timeout 300 bash plugins/dr-superpowers/tests/plan-lint.test.sh 2>&1 | tail -1`

Expected: `<n> passed, 0 failed`.

- [ ] **Step 5: Lint this repository's own plans, which must stay clean**

Run:

```bash
timeout 300 bash plugins/dr-superpowers/scripts/plan-lint \
  docs/superpowers/plans/2026-09-21-dr-superpowers-revising-plans.md --no-probe | tail -3
```

Expected: the summary line reports `0 errors`. NOTE and WARN lines are acceptable.

- [ ] **Step 6: Commit**

```bash
git add plugins/dr-superpowers/scripts/plan-lint plugins/dr-superpowers/tests/plan-lint.test.sh
git commit -m "fix(superpowers): lint scores through the shared reader

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---
### Task 4: `plan-revise`, single-plan mode

**Files:**
- Create: `plugins/dr-superpowers/scripts/plan-revise`
- Test: `plugins/dr-superpowers/tests/plan-revise.test.sh`

**Interfaces:**
- Consumes: `plan_eval_lines`, `plan_part_text`, `plan_task_parts`, `plan_lines` — Contracts, Task 1 block.
- Produces: `plugins/dr-superpowers/scripts/plan-revise`, its single-plan output grammar, and the shell functions `block`, `axes`, `plan_units`, `header_executors` and the variables `EXEC_IDS`, `LADDER` — Contracts, Task 4 block. Task 5 adds `--survey` to this same file and reuses all of them.

**Implementer:** dr-superpowers:impl-sonnet-high
**Executor:** codex gpt-5.5 / high
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 1 = 3

- [ ] **Step 1: Write the failing test**

Create `plugins/dr-superpowers/tests/plan-revise.test.sh`:

````bash
#!/usr/bin/env bash
# plan-revise reports; it never writes. Every mechanical rule the revising-plans
# skill applies lives here, so a rule the skill must follow is one a test reaches.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/../scripts/plan-revise"

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
REPO="$TMP/repo"
mkdir -p "$REPO/docs"
git -C "$REPO" init -q
git -C "$REPO" config user.email t@t
git -C "$REPO" config user.name t

# Fields are separated by two spaces, so a value may contain single spaces; a
# naive [^ ]* capture truncates "Global Constraints,..." to "Global".
field() { # field <name> <row>
  printf '%s' "$2" | awk -v k="$1" '{
    n = split($0, a, "  ")
    for (i = 1; i <= n; i++) if (index(a[i], k "=") == 1) { print substr(a[i], length(k) + 2); exit }
  }'
}

hdr() { # hdr <executors line or empty> <body>
  cat > "$REPO/docs/p.md" <<HDR
# Demo Implementation Plan

**Goal:** demo

**Spec:** docs/spec.md

**Execution:** inline — \`claude --model sonnet --effort high\` — demo
$1
## Global Constraints

- none

## Contracts

None

## Assumptions (evidence)

- none

## Task index

1. One

---

$2
HDR
}
plan() { hdr '
> **External executors:** codex
' "$1"; }
bare() { hdr '' "$1"; }
run() { (cd "$REPO" && bash "$SCRIPT" docs/p.md); }
unit1() { run | grep -m 1 '^unit'; }

check "script exists" "$([ -f "$SCRIPT" ] && echo yes || echo no)" "yes"

mktask() { # mktask <files> <spec> <coupling> <risk> <total>
  printf '### Task 1: One\n\n**Files:**\n- Create: `x`\n\n**Implementer:** dr-superpowers:impl-sonnet-medium\n**Evaluation:** files %s - spec %s - coupling %s - risk %s = %s\n' "$@"
}

# --- the gate boundaries, read from the shipped ladder ---
plan "$(mktask 0 0 1 0 1)"
check "total 1 fails the floor" "$(field gate "$(unit1)")" "fail:total"
plan "$(mktask 1 0 1 0 2)"
out=$(unit1)
check "total 2 passes" "$(field gate "$out")" "pass"
check "total 2 takes the medium rung" "$(field rungs "$out")" "codex:gpt-5.5/medium"
plan "$(mktask 1 1 1 0 3)"
check "total 3 takes the high rung" "$(field rungs "$(unit1)")" "codex:gpt-5.5/high"
plan "$(mktask 1 0 1 2 4)"
check "risk 2 fails the ceiling" "$(field gate "$(unit1)")" "fail:risk"
# spec 3 alone, with reducible 3, so the case cannot pass by the reducible rule.
plan "$(mktask 0 3 0 0 3)"
check "spec 3 fails Rule S on its own" "$(field gate "$(unit1)")" "fail:rule_s"
plan "$(mktask 1 1 2 0 4)"
check "reducible 4 fails Rule S below total 5" "$(field gate "$(unit1)")" "fail:rule_s"
# An Override keeps a Rule S violation in the plan; it must still not be offloaded.
OVERRIDE='**Override:** kept by the owner'
plan "$(mktask 0 3 0 0 3)
$OVERRIDE"
check "an overridden Rule S violation is still not eligible" "$(field gate "$(unit1)")" "fail:rule_s"
# plan-lint makes ANY Executor line on an overridden task a hard error
# (scripts/plan-lint:301), independent of Rule S, so a clean score with an
# Override must not be offered either.
plan "$(mktask 1 0 1 0 2)
$OVERRIDE"
check "an override blocks a unit whose score passes" "$(field gate "$(unit1)")" "fail:override"

# --- require_external_enabled: scores are not enough ---
bare "$(mktask 1 0 1 0 2)"
out=$(unit1)
check "a passing score with no executor ticked does not pass" "$(field gate "$out")" "fail:not_enabled"
check "a unit that cannot be offloaded lists no rung" "$(field rungs "$out")" ""
check "the header reports a missing executors line" "$(field executors "$(run | grep '^header')")" "missing"

# --- a second registered executor ---
FIXREG="$HERE/fixtures/executors"
# The stub ladder holds only the stub's blocks, so codex's gate would vanish and
# the run would list stub alone. plan-lint.test.sh:584 concatenates for this
# reason; do the same.
STUBLADDER="$TMP/both-ladder.md"
cat "$HERE/../reference/ladder.md" "$HERE/fixtures/stub-ladder.md" > "$STUBLADDER"
hdr '
> **External executors:** codex stub
' "$(mktask 1 0 1 0 2)"
out=$( (cd "$REPO" && DR_EXECUTORS_DIR="$FIXREG" DR_PLAN_REVISE_LADDER="$STUBLADDER" bash "$SCRIPT" docs/p.md) | grep -m 1 '^unit')
check "every ticked executor that admits the unit is listed" \
  "$(field rungs "$out" | tr ',' '\n' | cut -d: -f1 | sort | tr '\n' ' ')" "codex stub "

# --- units, parts and the states a score can be in ---
plan "$(printf '### Task 1: One\n\n**Files:**\n- Create: `x`\n\n#### Part A: a\n\n**Files:**\n- Create: `a`\n\n**Implementer:** dr-superpowers:impl-sonnet-medium\n**Evaluation:** files 1 - spec 0 - coupling 1 - risk 0 = 2\n\n#### Part B: b\n\n**Files:**\n- Create: `b`\n\n**Implementer:** dr-superpowers:impl-sonnet-medium\n**Evaluation:** files 1 - spec 0 - coupling 1 - risk 0 = 2\n')"
check "a split task yields one unit per part" "$(run | grep -c '^unit')" "2"
check "a part unit is named with its letter" "$(run | sed -n 's/^unit \([0-9A-Z]*\).*/\1/p' | tr '\n' ' ')" "1A 1B "

plan '### Task 1: One

**Files:**
- Create: `x`

**Implementer:** dr-superpowers:impl-sonnet-medium
'
out=$(unit1)
check "no score reports a dash" "$(field score "$out")" "-"
check "no score gates unknown" "$(field gate "$out")" "unknown"

plan '### Task 1: One

**Files:**
- Create: `x`

**Evaluation:** spec completeness 1 (exact signatures given), coupling 0
'
out=$(unit1)
check "an unparseable score reports a question mark" "$(field score "$out")" "?"
check "an unparseable score gates unknown" "$(field gate "$out")" "unknown"

# axes must aggregate exactly as plan_scores does: the highest total and the
# highest risk independently, not the risk that happens to sit on the top line.
plan "$(printf '### Task 1: One\n\n**Files:**\n- Create: `x`\n\n**Implementer:** dr-superpowers:impl-sonnet-medium\n**Evaluation:** files 1 - spec 1 - coupling 1 - risk 0 = 3\n**Evaluation:** files 0 - spec 0 - coupling 0 - risk 2 = 2\n')"
out=$(unit1)
check "the highest total wins" "$(field score "$out")" "3"
check "the highest risk wins independently" "$(field risk "$out")" "2"
check "a disqualifying risk on a lower-total line still fails" "$(field gate "$out")" "fail:risk"

EXECLINE='**Executor:** codex gpt-5.5 / medium'
plan "$(mktask 1 0 1 0 2)
$EXECLINE"
check "an existing Executor line is reported" "$(field executor "$(unit1)")" "codex"
plan "$(mktask 1 0 1 0 2)"
check "no Executor line reports none" "$(field executor "$(unit1)")" "none"

# --- the header row ---
check "the header reports the execution mode" "$(field execution "$(run | grep '^header')")" "inline"
check "a complete header reports sections ok" "$(field sections "$(run | grep '^header')")" "ok"
check "a ticked executor is reported" "$(field executors "$(run | grep '^header')")" "codex"

# The selection is a header line. A fenced example in a task body is not it.
plan "$(printf '### Task 1: One\n\n**Files:**\n- Create: `x`\n\n**Implementer:** dr-superpowers:impl-sonnet-medium\n**Evaluation:** files 1 - spec 0 - coupling 1 - risk 0 = 2\n\n```markdown\n> **External executors:** stub\n```\n')"
check "a fenced executors line is not the selection" "$(field executors "$(run | grep '^header')")" "codex"

printf '# Bare Plan\n\n### Task 1: One\n\n**Files:**\n- Create: `x`\n\n**Evaluation:** files 1 - spec 0 - coupling 1 - risk 0 = 2\n' > "$REPO/docs/p.md"
out=$(run | grep '^header')
check "a legacy header reports its missing sections" \
  "$(field sections "$out")" "Global Constraints,Contracts,Assumptions (evidence),Task index"
check "a legacy header reports a missing execution line" "$(field execution "$out")" "missing"

# --- the recommendation, which is writing-plans' rule as arithmetic ---
plan "$(mktask 1 0 1 0 2)"
out=$(run | grep '^recommend')
check "one light task recommends inline" "$(field execution "$out")" "inline"
check "one light task recommends sonnet" "$(field model "$out")" "sonnet"
check "one light task delegates nothing" "$(field delegated "$out")" "0/1"
check "one light task takes the table's effort" "$(field effort "$out")" "medium"

three() { # three <eval 1> <eval 2> <eval 3>
  plan "$(printf '### Task 1: One\n\n**Files:**\n- Create: `x`\n\n%s\n\n### Task 2: Two\n\n**Files:**\n- Create: `y`\n\n%s\n\n### Task 3: Three\n\n**Files:**\n- Create: `z`\n\n%s\n' "$1" "$2" "$3")"
}
E5='**Evaluation:** files 2 - spec 1 - coupling 2 - risk 0 = 5'
E4='**Evaluation:** files 1 - spec 1 - coupling 2 - risk 0 = 4'
E2='**Evaluation:** files 1 - spec 0 - coupling 1 - risk 0 = 2'

three "$E5" "$E4" "$E2"
out=$(run | grep '^recommend')
check "one heavy of three stays inline" "$(field execution "$out")" "inline"
check "a four-band within the third is delegated" "$(field delegated "$out")" "2/3"

three "$E5" "$E5" "$E2"
check "a heavy majority recommends subagent" "$(field execution "$(run | grep '^recommend')")" "subagent"

three "$E4" "$E4" "$E2"
out=$(run | grep '^recommend')
check "four-band past the third is self-implemented" "$(field delegated "$out")" "0/3"
check "a self-implemented four-band needs opus" "$(field model "$out")" "opus"

# --- exits ---
plan "$(mktask 1 0 1 0 2)"
(cd "$REPO" && bash "$SCRIPT" docs/p.md >/dev/null 2>&1); check "a readable plan exits 0" "$?" "0"
printf '# No tasks\n' > "$REPO/docs/empty.md"
(cd "$REPO" && bash "$SCRIPT" docs/empty.md >/dev/null 2>&1); check "a plan with no tasks exits 1" "$?" "1"
(cd "$REPO" && bash "$SCRIPT" docs/missing.md >/dev/null 2>&1); check "a missing plan exits 2" "$?" "2"
(cd "$REPO" && bash "$SCRIPT" >/dev/null 2>&1); check "no argument exits 2" "$?" "2"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
````

- [ ] **Step 2: Run the test to verify it fails**

Run: `timeout 300 bash plugins/dr-superpowers/tests/plan-revise.test.sh 2>&1 | tail -5`

Expected: FAIL on `script exists` — got `no`, want `yes`.

- [ ] **Step 3: Write the script**

Create `plugins/dr-superpowers/scripts/plan-revise`:

````bash
#!/usr/bin/env bash
# Report what a plan written before the external executor lane is missing, and
# which of its scoring units the lane gate would admit, so
# dr-superpowers:revising-plans edits from a computed answer rather than from
# arithmetic done by hand across a long plan.
#
# This script writes nothing. Every mechanical rule lives here, where a test can
# reach it; every judgment — scoring a task, splitting one, choosing between
# eligible executors, and the edits themselves — stays with the skill.
#
# Usage: plan-revise PLAN_FILE
# Exit: 0 reported; 1 no task to revise; 2 usage or a missing path.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib/plan.sh"
# Tests point this at a fixture ladder; production reads the shipped blocks.
LADDER="${DR_PLAN_REVISE_LADDER:-$HERE/../reference/ladder.md}"

die() { printf 'plan-revise: %s\n' "$1" >&2; exit 2; }
usage() { die "usage: plan-revise PLAN_FILE"; }

# block NAME — the body of the ```NAME fenced block in the ladder, blank lines
# dropped. The ladder is the single source for thresholds and rungs; a constant
# copied into a script is a constant that drifts.
block() {
  awk -v want="$1" '
    $0 == "```" want { f = 1; next }
    f && $0 == "```" { exit }
    f && NF { print }
  ' "$LADDER"
}

EXEC_IDS=$(bash "$HERE/executors" list 2>/dev/null)
[ -n "$EXEC_IDS" ] || die "no executor is registered"

# Each executor's thresholds and rungs come from its own registry entry, so a
# second registered executor needs no change here.
exec_gate() { # exec_gate <id> <key>
  local b; b=$(bash "$HERE/executors" get "$1" blocks.gate 2>/dev/null)
  [ -n "$b" ] || return 1
  block "$b" | awk -v k="$2" '$1 == k { print $2; exit }'
}
exec_rung() { # exec_rung <id> <total>
  local b; b=$(bash "$HERE/executors" get "$1" blocks.assignment 2>/dev/null)
  [ -n "$b" ] || return 1
  block "$b" | awk -v t="$2" '$1 == t { print $2 "/" $3; exit }'
}

# EXEC_TABLE — "<id> <min_score> <max_risk>" per registered executor, read once.
# Every exec_gate call is three subprocesses, and the survey would otherwise pay
# them once per executor per unit across a whole directory of plans.
EXEC_TABLE=$(for _eid in $EXEC_IDS; do
  _mn=$(exec_gate "$_eid" min_score) || true
  _mx=$(exec_gate "$_eid" max_risk) || true
  [ -n "$_mn" ] && [ -n "$_mx" ] && printf '%s %s %s\n' "$_eid" "$_mn" "$_mx"
done)

# effort_of TOTAL — the assignment table's effort for a total, which is the
# suffix of the agent name. impl-haiku carries no suffix and counts as low.
effort_of() {
  case "$(block assignment | awk -v t="$1" '$1 == t { print $2; exit }')" in
    impl-haiku|*-low) printf 'low\n' ;;
    *-medium) printf 'medium\n' ;;
    *) printf 'high\n' ;;
  esac
}

# axes — reads Evaluation lines on stdin; prints "files spec coupling risk total"
# taking the highest total and the highest risk INDEPENDENTLY, exactly as
# plan_scores does, so a disqualifying risk on a lower-total line is not lost.
# Prints "?" when any line does not parse and "-" when there are none.
axes() {
  local sep='( — | – | - | -- )' line any=0
  local bt=-1 br=-1 bf=0 bs=0 bc=0
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    any=1
    if [[ "$line" =~ ^\*\*Evaluation:\*\*\ files\ ([0-9]+)$sep"spec "([0-9]+)$sep"coupling "([0-9]+)$sep"risk "([0-9]+)\ =\ ([0-9]+) ]]; then
      [ "${BASH_REMATCH[7]}" -le "$br" ] || br=${BASH_REMATCH[7]}
      if [ "${BASH_REMATCH[8]}" -gt "$bt" ]; then
        bt=${BASH_REMATCH[8]}
        bf=${BASH_REMATCH[1]} bs=${BASH_REMATCH[3]} bc=${BASH_REMATCH[5]}
      fi
    else
      printf '?\n'; return 0
    fi
  done
  [ "$any" -eq 1 ] || { printf -- '-\n'; return 0; }
  printf '%s %s %s %s %s\n' "$bf" "$bs" "$bc" "$br" "$bt"
}

# header_executors PLAN — the ids on the header's External executors line,
# space separated. Read from the header only and outside fences, so a fenced
# example in a task body is never mistaken for the plan's selection.
header_executors() {
  plan_header "$1" | awk "$_PLAN_AWK"'
    in_fence($0) { next }
    index($0, "> **External executors:**") == 1 {
      sub(/^> \*\*External executors:\*\*[ \t]*/, "")
      print; exit
    }
  '
}

# plan_units PLAN — "id<TAB>text" per scoring unit: one row per part when the
# task has parts, otherwise one row for the task. Newlines travel as \v so one
# unit stays one line.
plan_units() {
  local n _title text parts part
  while IFS=$'\t' read -r n _title; do
    [ -n "$n" ] || continue
    text=$(plan_task_text "$1" "$n")
    parts=$(plan_task_parts <<<"$text")
    if [ -z "$parts" ]; then
      printf '%s\t%s\n' "$n" "$(printf '%s' "$text" | tr '\n' '\v')"
    else
      while IFS= read -r part; do
        [ -n "$part" ] || continue
        printf '%s%s\t%s\n' "$n" "$part" \
          "$(plan_part_text "$part" <<<"$text" | tr '\n' '\v')"
      done <<<"$parts"
    fi
  done < <(plan_tasks "$1")
}

[ $# -eq 1 ] || usage
plan=$1
[ -f "$plan" ] || die "no such plan file: $plan"

# --- header ---
case "$(plan_header_line "$plan" Execution)" in
  *subagent*) exec_mode=subagent ;;
  *inline*) exec_mode=inline ;;
  *) exec_mode=missing ;;
esac

ticked=$(header_executors "$plan")
if [ -n "$ticked" ]; then execs=$(tr -s ' ' ',' <<<"$ticked" | sed 's/,$//'); else execs=missing; fi

header_headings=$(plan_header "$plan" | awk "$_PLAN_AWK"'in_fence($0) { next } /^## / { print }')
missing_sections=""
for section in "Global Constraints" "Contracts" "Assumptions (evidence)" "Task index"; do
  grep -qxF "## $section" <<<"$header_headings" \
    || missing_sections="${missing_sections:+$missing_sections,}$section"
done
printf 'header  execution=%s  executors=%s  sections=%s\n' \
  "$exec_mode" "$execs" "${missing_sections:-ok}"

# --- units ---
units=$(plan_units "$plan")
[ -n "$units" ] || { printf 'plan-revise: no task in %s\n' "$plan" >&2; exit 1; }

tasks=$(plan_tasks "$plan" | grep -c .)
while IFS=$'\t' read -r id text; do
  [ -n "$id" ] || continue
  body=$(printf '%s' "$text" | tr '\v' '\n')
  a=$(plan_eval_lines <<<"$body" | axes)
  ex=$(plan_lines Executor <<<"$body" | head -n 1 | sed 's/^\*\*Executor:\*\*[[:space:]]*//' | awk '{ print $1 }')
  [ -n "$ex" ] || ex=none
  rungs=""
  case "$a" in
    '?') score='?' risk='?' rules=unknown gate=unknown ;;
    '-') score='-' risk='-' rules=unknown gate=unknown ;;
    *)
      set -- $a
      f=$1 s=$2 c=$3 risk=$4 score=$5
      if [ $((f + s + c)) -ge 4 ] || [ "$s" -eq 3 ]; then rules=violated; else rules=ok; fi
      if [ "$rules" = violated ]; then gate=fail:rule_s
      elif [ -n "$(plan_lines Override <<<"$body")" ]; then
        # plan-lint makes any Executor line on an overridden task a hard error,
        # whatever the scores say, so this unit can never carry one.
        gate=fail:override
      else
        # Each ticked executor is asked on its own thresholds; a unit no ticked
        # executor admits has not passed, whatever its score.
        gate="" asked=0
        for eid in $ticked; do
          mn=$(exec_gate "$eid" min_score) || true
          mx=$(exec_gate "$eid" max_risk) || true
          # A ticked id this installation does not register, or whose registry
          # entry names an absent ladder block, yields no thresholds. Saying
          # "fail:total" there would contradict the scores on screen.
          if [ -z "$mn" ] || [ -z "$mx" ]; then
            printf 'plan-revise: %s: no gate thresholds for ticked executor %s\n' "$id" "$eid" >&2
            continue
          fi
          if [ "$score" -lt "$mn" ]; then asked=1 gate=${gate:-fail:total}; continue; fi
          if [ "$risk" -gt "$mx" ]; then asked=1 gate=fail:risk; continue; fi
          r=$(exec_rung "$eid" "$score") || true
          # A missing rung is an incomplete table, not a judgment about the
          # unit, so it leaves asked alone exactly as unreadable thresholds do.
          [ -n "$r" ] || { printf 'plan-revise: %s: %s states no rung for total %s\n' "$id" "$eid" "$score" >&2; continue; }
          asked=1
          rungs="${rungs:+$rungs,}$eid:$r"
        done
        # No threshold could be read from anything ticked, so the lane is shut
        # for this plan whatever the scores are. No floor is written here: the
        # thresholds live in the ladder.
        if [ -n "$rungs" ]; then gate=pass
        elif [ "$asked" -eq 0 ]; then gate=fail:not_enabled
        else gate=${gate:-fail:total}; fi
      fi ;;
  esac
  if [ -n "$rungs" ]; then
    printf 'unit %s  score=%s  risk=%s  rule_s=%s  gate=%s  executor=%s  rungs=%s\n' \
      "$id" "$score" "$risk" "$rules" "$gate" "$ex" "$rungs"
  else
    printf 'unit %s  score=%s  risk=%s  rule_s=%s  gate=%s  executor=%s  rungs=\n' \
      "$id" "$score" "$risk" "$rules" "$gate" "$ex"
  fi
done <<<"$units"

# --- the recommendation ---
# It counts tasks, not units. plan_delegated already reduces a split task to its
# highest band and applies the four-band third threshold, so reading it here is
# what keeps this report and the execution skills agreeing.
heavy=$(plan_heavy "$plan" | grep -c . || true)
deleg_ids=$(plan_delegated "$plan" | cut -f1 | tr '\n' ' ')
delegated=$(printf '%s' "$deleg_ids" | wc -w | tr -d ' ')
any_four_self=0 max_self=-1
while IFS=$'\t' read -r tn total trisk; do
  [ -n "$tn" ] || continue
  case "$total" in '-'|'?') continue ;; esac
  case " $deleg_ids " in *" $tn "*) continue ;; esac
  [ "$total" -eq 4 ] && any_four_self=1
  [ "$total" -gt "$max_self" ] && max_self=$total
done <<<"$(plan_scores "$plan")"

if [ $((heavy * 2)) -gt "$tasks" ]; then
  rec_mode=subagent rec_model=sonnet rec_effort=high
else
  rec_mode=inline
  if [ "$any_four_self" -eq 1 ]; then rec_model=opus; else rec_model=sonnet; fi
  if [ "$delegated" -gt 0 ] || [ "$max_self" -lt 0 ]; then
    rec_effort=high
  else
    rec_effort=$(effort_of "$max_self")
  fi
fi
printf 'recommend  execution=%s  model=%s  effort=%s  delegated=%s/%s\n' \
  "$rec_mode" "$rec_model" "$rec_effort" "$delegated" "$tasks"
exit 0
````

Make it executable:

```bash
chmod +x plugins/dr-superpowers/scripts/plan-revise
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `printf 'plan-revise: '; timeout 300 bash plugins/dr-superpowers/tests/plan-revise.test.sh 2>&1 | tail -1`

Expected: `<n> passed, 0 failed`.

- [ ] **Step 5: Run it against a real legacy plan**

Run:

```bash
timeout 300 bash plugins/dr-superpowers/scripts/plan-revise \
  ~/repositories/darkmem/docs/superpowers/plans/2026-09-03-artifacts-frame-and-tree.md | head -8
```

Expected: a `header` row, five `unit` rows each with `score=?` and `gate=unknown`, and a `recommend` row. This is the plan whose lines use the older prose form; the point of the check is that it reports rather than crashes.

- [ ] **Step 6: Commit**

```bash
git add plugins/dr-superpowers/scripts/plan-revise plugins/dr-superpowers/tests/plan-revise.test.sh
git commit -m "feat(superpowers): add plan-revise single-plan report

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 5: `plan-revise`, survey mode

**Files:**
- Modify: `plugins/dr-superpowers/scripts/plan-revise` (add `--survey`)
- Test: `plugins/dr-superpowers/tests/plan-revise.test.sh` (append a section)

**Interfaces:**
- Consumes: `block`, `axes`, `plan_units`, `header_executors`, `EXEC_TABLE`, `LADDER` — Contracts, Task 4 block; `ledger_plan` and `plan_header_line` from `lib/plan.sh`. It does not call `plan_ledger`: that helper resolves only the plan's own worktree, which is the defect `ledger_for` exists to avoid. It does not call `plan_ledger`: that helper resolves only the plan's own worktree, which is the defect `ledger_for` exists to avoid.
- Produces: the `--survey` row grammar — Contracts, Task 5 block. Task 6's skill runs it.

**Implementer:** dr-superpowers:impl-sonnet-high
**Executor:** codex gpt-5.5 / high
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 1 = 3

- [ ] **Step 1: Write the failing test**

Append to `plugins/dr-superpowers/tests/plan-revise.test.sh`, above its final summary `printf`:

````bash
# --- survey mode ---
SUR="$TMP/sur"
mkdir -p "$SUR/docs"
git -C "$SUR" init -q
git -C "$SUR" config user.email t@t
git -C "$SUR" config user.name t
survey() { (cd "$SUR" && bash "$SCRIPT" --survey docs); }
row() { survey | grep -m 1 "^plan  $1"; }
splan() { # splan <name> <body>
  printf '# P\n\n**Execution:** inline — `claude --model sonnet --effort high` — x\n\n### Task 1: One\n\n**Files:**\n- Create: `x`\n\n%s\n' "$2" > "$SUR/docs/$1.md"
}

splan scored '**Evaluation:** files 1 - spec 0 - coupling 1 - risk 0 = 2'
splan unscored ''
printf '# P\n\n### Task 1: One\n\n**Files:**\n- Create: `x`\n\n**Evaluation:** spec completeness 1 (exact signatures given), coupling 0\n\n### Task 2: Two\n\n**Files:**\n- Create: `y`\n\n**Evaluation:** files 1 - spec 0 - coupling 1 - risk 0 = 2\n' > "$SUR/docs/mixed.md"
printf 'not a plan\n' > "$SUR/docs/completed.md"

check "a scored plan counts its eligible units" "$(field eligible "$(row scored)")" "1"
check "an unscored plan reports a dash" "$(field eligible "$(row unscored)")" "-"
check "a mixed plan reports the known count and an unknown" "$(field eligible "$(row mixed)")" "1+?"
check "a file with no task is skipped" "$(survey | grep -c 'completed')" "0"
check "the survey counts tasks" "$(field tasks "$(row mixed)")" "2"
check "the survey counts unparsed units" "$(field unparsed "$(row mixed)")" "1"
# The survey answers "how much could be delegated", so it ignores selection.
check "the survey counts eligibility without a ticked executor" "$(field eligible "$(row scored)")" "1"

# --- liveness precedence ---
check "no ledger and no completed entry is unknown" "$(field live "$(row scored)")" "unknown"

mkdir -p "$SUR/.superpowers/sdd/scored"
printf '# SDD ledger — plan: docs/scored.md\nTask 1: complete (x)\n' \
  > "$SUR/.superpowers/sdd/scored/progress.md"
check "a ledger naming the plan is live" "$(field live "$(row scored)")" "yes"

printf '# SDD ledger — plan: docs/other.md\n' > "$SUR/.superpowers/sdd/scored/progress.md"
check "a ledger naming another plan is not this plan's" "$(field live "$(row scored)")" "unknown"
rm -rf "$SUR/.superpowers"

# completed.md names the plan by its recorded path, so a shorter basename that
# is a substring of a longer one must not match it.
printf -- '- 2026-09-21 `docs/unscored.md` — merged into `main` at abc1234\n' > "$SUR/docs/completed.md"
check "a substring of another plan's entry does not match" "$(field live "$(row scored)")" "unknown"
printf -- '- 2026-09-21 `docs/scored.md` — merged into `main` at abc1234\n' > "$SUR/docs/completed.md"
check "a merged entry is not live" "$(field live "$(row scored)")" "no"
printf -- '- 2026-09-21 `docs/scored.md` — via PR\n' > "$SUR/docs/completed.md"
check "a via-PR entry is unknown, not done" "$(field live "$(row scored)")" "unknown"
# merged outranks a later via-PR line for the same plan.
printf -- '- 2026-09-20 `docs/scored.md` — merged into `main` at abc1234\n- 2026-09-21 `docs/scored.md` — via PR\n' > "$SUR/docs/completed.md"
check "merged outranks a later via-PR entry" "$(field live "$(row scored)")" "no"

mkdir -p "$SUR/.superpowers/sdd/scored"
printf '# SDD ledger — plan: docs/scored.md\n' > "$SUR/.superpowers/sdd/scored/progress.md"
check "a ledger outranks a completed entry" "$(field live "$(row scored)")" "yes"
rm -rf "$SUR/.superpowers"
rm -f "$SUR/docs/completed.md"

# A ledger may live in a linked worktree while the plan is read from the primary
# checkout. Each worktree holds its own copy of the plan at the same repo path,
# so the identity check must resolve the plan inside the worktree it searches.
git -C "$SUR" add -A >/dev/null 2>&1
git -C "$SUR" commit -qm base >/dev/null 2>&1
git -C "$SUR" worktree add -q "$TMP/wt" -b feature >/dev/null 2>&1
mkdir -p "$TMP/wt/.superpowers/sdd/scored"
printf '# SDD ledger — plan: docs/scored.md\n' > "$TMP/wt/.superpowers/sdd/scored/progress.md"
check "a ledger in a linked worktree is found" "$(field live "$(row scored)")" "yes"
check "the evidence names the worktree that holds it" \
  "$(row scored | grep -c "$TMP/wt")" "1"
git -C "$SUR" worktree remove --force "$TMP/wt" >/dev/null 2>&1

(cd "$SUR" && bash "$SCRIPT" --survey docs >/dev/null 2>&1); check "a directory with plans exits 0" "$?" "0"
mkdir -p "$SUR/none"
(cd "$SUR" && bash "$SCRIPT" --survey none >/dev/null 2>&1); check "a directory with no plans exits 1" "$?" "1"
(cd "$SUR" && bash "$SCRIPT" --survey missing >/dev/null 2>&1); check "a missing directory exits 2" "$?" "2"
````

- [ ] **Step 2: Run the test to verify it fails**

Run: `timeout 300 bash plugins/dr-superpowers/tests/plan-revise.test.sh 2>&1 | grep -A2 FAIL | head -20`

Expected: FAIL on `a scored plan counts its eligible units` — the script rejects `--survey` as a usage error, so the row is empty.

- [ ] **Step 3: Add survey mode**

In `plugins/dr-superpowers/scripts/plan-revise`, change the usage comment at the top to read:

```bash
# Usage: plan-revise PLAN_FILE
#        plan-revise --survey DIR
# Exit: 0 reported; 1 nothing to revise; 2 usage or a missing path.
```

and change the `usage` function to:

```bash
usage() { die "usage: plan-revise PLAN_FILE | plan-revise --survey DIR"; }
```

Then insert these functions directly above the `[ $# -eq 1 ] || usage` line:

````bash
# ledger_for PLAN — the ledger whose identity line names PLAN, searched across
# every worktree of the plan's repository, because execution may run in a linked
# worktree while the plan is read from the primary checkout. Each worktree holds
# its own copy of the plan at the same repository-relative path, so the identity
# is compared inside the worktree being searched — plan_repo_canon embeds the
# worktree root, and comparing across roots never matches.
ledger_for() {
  local slug rel wt f named
  slug=$(basename "$1" .md)
  rel=$(git -C "$(dirname "$1")" rev-parse --show-prefix 2>/dev/null)$(basename "$1")
  [ -n "$rel" ] || return 0
  local roots root best
  roots=$(git -C "$(dirname "$1")" worktree list --porcelain 2>/dev/null | sed -n 's/^worktree //p')
  while IFS= read -r wt; do
    [ -n "$wt" ] || continue
    f="$wt/.superpowers/sdd/$slug/progress.md"
    [ -f "$f" ] || continue
    named=$(ledger_plan "$f")
    [ -n "$named" ] || continue
    # An absolute path may name any worktree's root, not just this one, so
    # every root is stripped rather than only the one being searched.
    case $named in /*)
      # A worktree created inside the primary checkout has the primary root as
      # a prefix of its own, so the longest matching root is the right one.
      best=""
      while IFS= read -r root; do
        [ -n "$root" ] || continue
        case $named in "$root"/*)
          [ "${#root}" -gt "${#best}" ] && best=$root ;;
        esac
      done <<<"$roots"
      [ -n "$best" ] && named=${named#"$best"/} ;;
    esac
    [ "$named" = "$rel" ] || continue
    printf '%s\t%s\n' "$wt" "$f"
    return 0
  done <<<"$roots"
}

# completed_form PLAN — "merged", "pr" or nothing, from the completed.md beside
# the plan. The entry is matched on the plan's recorded repository-relative
# path, not a basename substring: "docs/scored.md" is a substring of
# "docs/unscored.md" and would otherwise claim another plan's outcome. Merged
# outranks via PR whatever their order, because finishing-a-development-branch
# writes the via-PR line before the push and the merged line after the merge.
completed_form() {
  local f rel hits
  f="$(cd "$(dirname "$1")" && pwd)/completed.md"
  [ -f "$f" ] || return 0
  rel=$(git -C "$(dirname "$1")" rev-parse --show-prefix 2>/dev/null)$(basename "$1")
  hits=$(grep -F "\`$rel\`" "$f" 2>/dev/null) || return 0
  [ -n "$hits" ] || return 0
  if grep -qF 'merged into' <<<"$hits"; then printf 'merged\n'
  elif grep -qF 'via PR' <<<"$hits"; then printf 'pr\n'
  fi
}

# steps PLAN — "<checked> <unchecked>" step counts outside fences. Evidence
# only: a subagent-mode plan records its progress in the ledger, not the file.
steps() {
  awk "$_PLAN_AWK"'
    in_fence($0) { next }
    /^- \[x\]/ { d++ }
    /^- \[ \]/ { o++ }
    END { printf "%d %d\n", d + 0, o + 0 }
  ' "$1"
}

survey() {
  local dir=$1 f rows=0 a score risk fl sp cp
  local tasks scored unparsed eligible live evidence lf form execution exec_mode ok
  for f in "$dir"/*.md; do
    [ -f "$f" ] || continue
    tasks=$(plan_tasks "$f" | grep -c .)
    [ "$tasks" -gt 0 ] || continue
    rows=$((rows + 1))
    scored=0 unparsed=0 eligible=0
    while IFS=$'\t' read -r _id text; do
      [ -n "$_id" ] || continue
      a=$(plan_eval_lines <<<"$(printf '%s' "$text" | tr '\v' '\n')" | axes)
      case "$a" in '?'|'-') unparsed=$((unparsed + 1)); continue ;; esac
      scored=$((scored + 1))
      set -- $a
      fl=$1 sp=$2 cp=$3 risk=$4 score=$5
      [ $((fl + sp + cp)) -ge 4 ] && continue
      [ "$sp" -eq 3 ] && continue
      # Potential eligibility: any registered executor, ticked or not, because
      # the survey answers how much COULD be delegated.
      ok=$(awk -v t="$score" -v r="$risk" 'NF && $2 <= t && r <= $3 { print 1; exit }' <<<"$EXEC_TABLE")
      [ -n "$ok" ] && eligible=$((eligible + 1))
    done <<<"$(plan_units "$f")"

    if [ "$scored" -eq 0 ]; then eligible=-
    elif [ "$unparsed" -gt 0 ]; then eligible="$eligible+?"
    fi

    lf=$(ledger_for "$f")
    form=$(completed_form "$f")
    if [ -n "$lf" ]; then
      live=yes evidence="ledger in $(cut -f1 <<<"$lf")"
    elif [ "$form" = merged ]; then
      live=no evidence="completed.md merged"
    elif [ "$form" = pr ]; then
      live=unknown evidence="completed.md via PR, no ledger"
    else
      live=unknown evidence="steps $(steps "$f") (done open), no ledger"
    fi

    case "$(plan_header_line "$f" Execution)" in
      *subagent*) exec_mode=subagent ;;
      *inline*) exec_mode=inline ;;
      *) exec_mode=- ;;
    esac
    execution=$(header_executors "$f")
    [ -n "$execution" ] && execution=$(tr -s ' ' ',' <<<"$execution" | sed 's/,$//') || execution=-

    printf 'plan  %s  tasks=%s  scored=%s  unparsed=%s  eligible=%s  exec=%s  executors=%s  live=%s  %s\n' \
      "$(basename "$f")" "$tasks" "$scored" "$unparsed" "$eligible" \
      "$exec_mode" "$execution" "$live" "$evidence"
  done
  [ "$rows" -gt 0 ] || return 1
  printf 'surveyed  plans=%s\n' "$rows"
  return 0
}

if [ "${1:-}" = --survey ]; then
  [ $# -eq 2 ] || usage
  [ -d "$2" ] || die "no such directory: $2"
  survey "$2"
  exit $?
fi
````

- [ ] **Step 4: Run the test to verify it passes**

Run: `printf 'plan-revise: '; timeout 300 bash plugins/dr-superpowers/tests/plan-revise.test.sh 2>&1 | tail -1`

Expected: `<n> passed, 0 failed`.

- [ ] **Step 5: Survey both real backlogs**

Run:

```bash
for r in darkmem darkcloud; do
  printf '=== %s\n' "$r"
  timeout 600 bash plugins/dr-superpowers/scripts/plan-revise \
    --survey ~/repositories/$r/docs/superpowers/plans | tail -3
done
```

Expected: rows for each plan and a final `surveyed  plans=<n>` line, with `n` at least 100 for darkmem and at least 40 for darkcloud. This is a smoke check that the survey completes over the real corpus.

- [ ] **Step 6: Commit**

```bash
git add plugins/dr-superpowers/scripts/plan-revise plugins/dr-superpowers/tests/plan-revise.test.sh
git commit -m "feat(superpowers): add the plan-revise survey

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 6: The `revising-plans` skill

**Files:**
- Create: `plugins/dr-superpowers/skills/revising-plans/SKILL.md`
- Modify: `plugins/dr-superpowers/skills/using-superpowers/SKILL.md` (the Routing table)
- Modify: `plugins/dr-superpowers/README.md` (the skill inventory prose)
- Test: `plugins/dr-superpowers/tests/plan-revise.test.sh` (append a prose section)

**Interfaces:**
- Consumes: `plan-revise` and both output grammars — Contracts, Task 4 and Task 5 blocks.
- Produces: `skills/revising-plans/SKILL.md` — Contracts, Task 6 block.

**Implementer:** dr-superpowers:impl-sonnet-high
**Executor:** codex gpt-5.5 / high
**Evaluation:** files 2 - spec 0 - coupling 1 - risk 0 = 3

- [ ] **Step 1: Write the failing prose test**

Append to `plugins/dr-superpowers/tests/plan-revise.test.sh`, above its final summary `printf`. Every needle below is a single line of the skill file, and `present` counts at least one occurrence rather than exactly one, so a phrase that legitimately appears twice does not fail:

````bash
# --- the skill's prose, pinned where a rule would otherwise rot ---
SK="$HERE/../skills/revising-plans/SKILL.md"
present() { # present <name> <file> <needle>
  local n; n=$(grep -cF -- "$3" "$2" 2>/dev/null); [ -n "$n" ] || n=0
  check "$1" "$([ "$n" -ge 1 ] && echo yes || echo no)" "yes"
}
check "the skill exists" "$([ -f "$SK" ] && echo yes || echo no)" "yes"
present "the skill is named" "$SK" "name: revising-plans"
present "the skill refuses a live plan" "$SK" "Never edit a plan whose ledger names it"
present "the skill runs each gate rather than printing its path" "$SK" 'bash "$(bash <plugin-root>/scripts/executors path <id> gate)"'
present "the skill names the amend script, not a skill" "$SK" "bash <plugin-root>/scripts/plan-amend"
present "the skill scores before offering an executor" "$SK" "Scoring precedes the executor question"
present "the skill ticks only an executor the roster reports usable" "$SK" "and the roster reports it"
present "the skill filters the roster by the gate" "$SK" "ignore every row whose gate did not print"
present "the skill re-runs the report before settling execution" "$SK" "Re-run plan-revise after writing the Executor"
present "the skill reconciles an existing Executor line" "$SK" "replace it with the printed rung"
present "the skill leaves a thin task unscored" "$SK" "A guessed score is worse than a visible gap"
present "the skill allows the split Rule S requires" "$SK" "Splitting a task Rule S rejects is part of this skill"
present "the routing table lists the skill" "$HERE/../skills/using-superpowers/SKILL.md" "dr-superpowers:revising-plans"
````

- [ ] **Step 2: Run the test to verify it fails**

Run: `timeout 300 bash plugins/dr-superpowers/tests/plan-revise.test.sh 2>&1 | grep -A2 FAIL | head`

Expected: FAIL on `the skill exists` — got `no`, want `yes`.

- [ ] **Step 3: Write the skill**

Create `plugins/dr-superpowers/skills/revising-plans/SKILL.md`:

`````markdown
---
name: revising-plans
description: Use when a plan written before the external executor lane needs bringing up to the current format - scores what is unscored, ticks the executors the live roster offers, and writes the Executor and Execution lines
---

# Revising Plans

A plan written before the external executor lane names no executor, so every
task runs on the Claude lane whether or not the lane would admit it. This skill
revises one named plan into an ordinary current-format plan.

**Announce at start:** "I'm using the revising-plans skill to revise `<plan>`."

`scripts/plan-revise` computes; this skill decides and edits. Call it as
`bash <plugin-root>/scripts/plan-revise <PLAN_FILE>`, with the working directory
inside the plan's repository.

## Survey first, when you do not know which plan

`bash <plugin-root>/scripts/plan-revise --survey docs/superpowers/plans` prints
one row per plan: its task count, how many units score, how many are eligible,
and its liveness evidence. It writes nothing. Report the rows and stop — which
plan is worth revising is your human partner's call, not yours.

`eligible=-` means the plan has no parseable score yet, so its eligibility is
unknown rather than zero. `eligible=<n>+?` means `n` units are known eligible
and the rest cannot be judged until they are scored. The survey counts what
*could* be delegated and ignores which executors are ticked; single-plan mode
applies the tick.

## The checklist

Create a todo per item and work them in order. The order matters: the gate reads
the scores, so scoring cannot follow the executor question.

1. **Refuse a plan that may be running.** Run `plan-revise --survey` on the
   plan's directory and read its `live=` field. Stop on `live=yes` and on
   `live=unknown`, quoting the evidence, and name
   `bash <plugin-root>/scripts/plan-amend` as the route for a plan under
   execution — it is a script, not a skill, and it appends to the plan's
   workspace instead of editing the file.
   Never edit a plan whose ledger names it: during execution the file is
   immutable and the ledger is keyed to it.
2. **Repair the header.** `plan-revise`'s `header` row lists the sections the
   plan lacks. Add them from the plan's own content: Global Constraints from its
   stated rules, Contracts from the names tasks already exchange, Assumptions
   from claims the plan relies on, and a Task index matching its headings. Invent
   no requirement that is not already in the plan.
3. **Score every unit that needs one.** A `unit` row reporting `score=-` has no
   `**Evaluation:**` line; one reporting `score=?` has a line that does not
   parse, usually in an older prose form. Both are repaired here, as is a unit
   with a score but no `**Implementer:**` line. Score on the four axes in
   `reference/ladder.md`, then apply Rule S: a unit whose
   `files + spec + coupling` reaches 4, or whose spec scores 3, is split or
   redesigned rather than handed a larger model.
   Splitting a task Rule S rejects is part of this skill, and it is the one
   change to a task's body this skill makes: the task's steps are rewritten only
   as far as the split requires. A task needing more than that needs re-planning,
   not revision — say so and stop.
   Scoring precedes the executor question.
4. **Read the project's constraints.** `docs/superpowers/distilled/constraints.md`
   when the project has one. An absent file is not an error.
5. **Gate each executor, then run the roster.** Enumerate with
   `bash <plugin-root>/scripts/executors list`. For each id, run its gate:

   ```bash
   bash "$(bash <plugin-root>/scripts/executors path <id> gate)"
   ```

   That is a script to execute, not a path to print. Say its line aloud when it
   ends `source=probe`. If no gate printed `lane=true`, skip to step 7 and write
   no executor lines.
   Otherwise run `bash <plugin-root>/scripts/detect-executors.sh` once. It takes
   no id argument and probes every registered executor, so read its output and
   ignore every row whose gate did not print `lane=true`. An executor is
   offerable only when its gate printed `lane=true` and the roster reports it
   `usable`. A constraint that declares an executor's lane on ticks it without
   asking, on the same two conditions: a constraint cannot tick an executor that
   is not there.
6. **Offer the rest.** Render the remaining offerable executors as a
   multi-select question, and name every other detected executor with its reason
   in prose. If none is offerable, ask nothing and say so in one line. Record
   the tick as one appended blockquote line in the header:

   ```markdown
   > **External executors:** <id>
   ```

7. **Write the Executor lines.** Re-run `plan-revise`, which now sees the tick.
   Every unit row reading `gate=pass` takes an `**Executor:**` line naming one
   of the executors in its `rungs=` field, at that executor's rung, written
   below the unit's `**Implementer:**` line and above its `**Evaluation:**`
   line. Where `rungs=` lists several, you choose one; a unit carries at most
   one `**Executor:**` line.
   A unit that already reads `executor=<id>` is reconciled, not preserved: if
   its id is absent from `rungs=`, or its rung differs from the one printed for
   that id, replace it with the printed rung; if the unit no longer reads
   `gate=pass`, delete the line. A stale assignment survives otherwise and fails
   at verification with nothing to explain it.
   `gate=fail:not_enabled` means the scores pass but no ticked executor admits
   the unit — revisit step 6 rather than writing a line.
   Batching is decided at dispatch, not here, so no unit is exempted for it.
8. **Settle the Execution line.** Re-run plan-revise after writing the Executor
   lines, and copy the mode, model and effort from that run's `recommend` row.
   Do not reuse an earlier run's row and do not recompute it by hand: writing
   an Executor line changes what is delegated, which changes the recommended
   effort.
9. **Verify.** `bash <plugin-root>/scripts/plan-lint <PLAN_FILE>` reports
   `0 errors`, and a final `plan-revise` run shows every unit either `gate=fail`
   or `executor=<id>` matching its `rungs=`, with the header's `execution`
   matching the `recommend` row.

## When a task cannot be scored honestly

A task whose description is too thin to score gets no invented number. Leave it
unscored, say which task it is and what is missing, and let `plan-lint` report
the plan as incomplete. A guessed score is worse than a visible gap: it routes a
task to a seat nobody chose.

## What this skill never does

- It never edits a plan under execution. Corrections there go through
  `bash <plugin-root>/scripts/plan-amend`, which appends to the workspace rather
  than editing the file.
- It never decides which plans to revise. The survey reports; your human partner
  picks.
- It never rewrites a task's steps beyond the split Rule S requires. A plan
  whose content is wrong needs re-planning, not revision.
`````

- [ ] **Step 4: Add the routing row**

In `plugins/dr-superpowers/skills/using-superpowers/SKILL.md`, find the Routing table row:

```markdown
| A spec is approved | dr-superpowers:writing-plans |
```

Insert this row directly below it:

```markdown
| A plan predates the executor lane | dr-superpowers:revising-plans |
```

- [ ] **Step 5: Add the README line**

In `plugins/dr-superpowers/README.md`, find the first paragraph that names
`writing-plans` (search with `grep -n 'writing-plans' plugins/dr-superpowers/README.md`).
Add this sentence to the end of that paragraph:

```markdown
`revising-plans` brings a plan written before the external executor lane up to the current format, scoring what is unscored and writing the `**Executor:**` and `**Execution:**` lines from `scripts/plan-revise`.
```

- [ ] **Step 6: Run the tests to verify they pass**

Run:

```bash
printf 'plan-revise: '; timeout 300 bash plugins/dr-superpowers/tests/plan-revise.test.sh 2>&1 | tail -1
printf 'criteria: '; timeout 300 bash plugins/dr-superpowers/tests/criteria.test.sh 2>&1 | tail -1
```

Expected: both end `0 failed`.

- [ ] **Step 7: Validate the plugin manifest still passes**

Run: `timeout 180 claude plugin validate plugins/dr-superpowers 2>&1 | tail -2`

Expected: `✔ Validation passed`.

- [ ] **Step 8: Commit**

```bash
git add plugins/dr-superpowers/skills/revising-plans/SKILL.md plugins/dr-superpowers/skills/using-superpowers/SKILL.md plugins/dr-superpowers/README.md plugins/dr-superpowers/tests/plan-revise.test.sh
git commit -m "feat(superpowers): add the revising-plans skill

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 7: Register rows and the release

**Files:**
- Modify: `docs/superpowers/registers/2026-09-20-review-fixes-deferrals.md` (via `scripts/register`)
- Modify: `plugins/dr-superpowers/.claude-plugin/plugin.json` (version)
- Modify: `plugins/dr-superpowers/.codex-plugin/plugin.json` (version)
- Modify: `plugins/dr-superpowers/tests/review-route.test.sh` (the two version assertions)

**Interfaces:**
- Consumes: nothing.
- Produces: nothing other tasks consume.

**Implementer:** dr-superpowers:impl-sonnet-medium
**Executor:** codex gpt-5.5 / medium
**Evaluation:** files 2 - spec 0 - coupling 0 - risk 0 = 2

- [ ] **Step 1: Close the split-task row and record the fence defect**

Run, from the repository root:

```bash
bash plugins/dr-superpowers/scripts/register set \
  docs/superpowers/registers/2026-09-20-review-fixes-deferrals.md 1 done \
  --note "Fixed by plan_eval_lines in scripts/lib/plan.sh: a split task scores from its part bodies only, and plan_scores, review-route and plan-lint all read through it"

bash plugins/dr-superpowers/scripts/register add \
  docs/superpowers/registers/2026-09-20-review-fixes-deferrals.md \
  "review-route read **Evaluation:** and **Executor:** lines without skipping fenced blocks, so a fenced example escalated the seat" \
  --acceptance "A task holding a fenced example line routes on its real score" \
  --state done \
  --note "Found by the 2026-09-21 astra review of the revising-plans design; fixed with the split-task rule in the same shared helper"
```

- [ ] **Step 2: Verify the register is well formed**

Run: `bash plugins/dr-superpowers/scripts/register check docs/superpowers/registers/2026-09-20-review-fixes-deferrals.md`

Expected: exit 0 and no error lines.

- [ ] **Step 3: Bump both manifests and the version assertions**

Run:

```bash
sed -i 's/"version": "1.16.1"/"version": "1.17.0"/' \
  plugins/dr-superpowers/.claude-plugin/plugin.json \
  plugins/dr-superpowers/.codex-plugin/plugin.json
sed -i 's/1\.16\.1/1.17.0/g' plugins/dr-superpowers/tests/review-route.test.sh
```

This is a minor bump, not a patch: a new skill and a new script are added, and routing behaviour changes.

- [ ] **Step 4: Run the whole suite and the repository validation**

Run:

```bash
cd plugins/dr-superpowers
p=0; f=0
for t in tests/*.test.sh; do
  r=$(timeout 300 bash "$t" 2>&1 | tail -1)
  case "$r" in *"0 failed"*) p=$((p+1)) ;; *) f=$((f+1)); printf 'FAILED %s: %s\n' "$(basename "$t")" "$r" ;; esac
done
printf 'suites passed=%s failed=%s\n' "$p" "$f"
cd ../..
timeout 300 node scripts/validate-repository.mjs
timeout 180 claude plugin validate .claude-plugin/marketplace.json
```

Expected: `failed=0`, `Repository catalogs, manifests, versions, and bundled links are valid.`, and `✔ Validation passed`.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "chore(superpowers): release 1.17.0

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```
