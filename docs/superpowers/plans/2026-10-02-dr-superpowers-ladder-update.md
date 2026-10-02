# dr-superpowers Ladder Update Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: the skill the **Execution:** line names — dr-superpowers:subagent-driven-development for `subagent`, dr-superpowers:executing-plans for `inline`. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Apply the owner's tier-evaluation rulings: assign totals 2 to 5 one rung cheaper, describe the new ladder, run `judge-opus` at medium effort, and release 1.24.0.

**Architecture:** The `assignment` block in `reference/ladder.md` and the test expectations that read it change together (Task 1); the prose that states the old rows follows (Task 2); the `judge-opus` agent's effort changes on its own (Task 3); a release bumps both manifests (Task 4). Tasks 1 and 2 apply verified patches embedded in this plan, so the implementer extracts and applies them rather than retyping them.

**Tech Stack:** Bash scripts and their `*.test.sh` suites, Markdown references, skills and agent definitions, Node repository checks.

**Spec:** `docs/superpowers/specs/2026-10-02-dr-superpowers-ladder-update-design.md`

**Execution:** inline — `claude --model sonnet --effort high` — Task 1 is heavy (1 of 4) and delegated; the highest self-implemented total is 3

**Plan review:** 2026-10-02 — dr-superpowers:judge-opus — executability 16 / coherence 18 / coverage 18 / assumptions 15 (round 1)

## Global Constraints

- Run every command from the root of the execution checkout: the worktree dr-superpowers:executing-plans sets up, branched after the handoff commit that adds this plan. Paths below are relative to it.
- The `escalation` and `reserve` blocks of `plugins/dr-superpowers/reference/ladder.md` do not change, and neither does the heavy rule (total 5 or more, or risk 3).
- In `skills/writing-plans/SKILL.md`, `skills/executing-plans/SKILL.md`, `skills/using-superpowers/SKILL.md`, `README.md` and `reference/delegated-task.md` under `plugins/dr-superpowers/`, write "total 4", never "total-4": `tests/inline-mode.test.sh` asserts the hyphenated form is absent.
- Do not edit completed plans under `docs/superpowers/plans/` or specs under `docs/superpowers/specs/`, and do not touch the untracked `docs/superpowers/notes/2026-09-23-opus-5-5-effort-eval-design.md`.
- Keep the Claude and Codex manifest versions equal (`plugins/dr-superpowers/.claude-plugin/plugin.json`, `plugins/dr-superpowers/.codex-plugin/plugin.json`).
- Commits: `<type>(<scope>): <subject>`, subject ≤ 50 characters, imperative, no period. The commit commands end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`; when the model writing the commit is a different one, use the co-author line your harness gives for it instead.
- Bound every test and CLI run with `timeout`; leave no process running.
- English only.

## Contracts

- **Assignment table.** After Task 1, the `assignment` block in `plugins/dr-superpowers/reference/ladder.md` reads, in order: `0 impl-haiku`, `1 impl-sonnet-low`, `2 impl-sonnet-low`, `3 impl-sonnet-medium`, `4 impl-sonnet-medium`, `5 impl-sonnet-high`, `6 impl-opus-high`. `tests/ladder.test.sh` asserts exactly these rows. Task 2's prose states them.
- **Embedded patches.** Each patch sits in this plan file in a five-backtick fence whose info string is `diff <name>`: `t1-tests` and `t1-table` (Task 1), `t2-prose` (Task 2). It is extracted with `awk '$0 == "`````diff <name>" { f = 1; next } f && $0 == "`````" { exit } f' docs/superpowers/plans/2026-10-02-dr-superpowers-ladder-update.md` into `.superpowers/ladder-update/<name>.diff` (gitignored) and applied with `git apply`. `t2-prose` touches `reference/ladder.md` hunks outside the assignment block, so it applies on top of Task 1's commit.

## Assumptions (evidence)

- This plan and the register edit that assigns row 2 to it are committed before Task 1 (the handoff commit), so the patch extraction in Tasks 1 and 2 reads a tracked file in the execution checkout.
- Baseline on `2c76eff` (2026-10-02): all 32 `plugins/dr-superpowers/tests/*.test.sh` suites pass; `node --test tests/*.test.mjs` passes 22/0 with the `rg` wrapper of Task 4 Step 5; `claude plugin validate` passes on the marketplace and the four Claude plugins.
- Every patch was rehearsed on 2026-10-02 in a scratch copy of `2c76eff`. With `t1-tests` applied and the old table, `ladder.test.sh` reported 26 passed / 1 failed, `plan-lint.test.sh` 137 / 28 and `plan-revise.test.sh` 84 / 2; `plan-lib.test.sh` and `plan-amend.test.sh` passed, because their edits only keep fixtures consistent with the table. With `t1-table` also applied, all 32 suites passed. With `t2-prose` applied on top, all 32 suites passed. Tasks 3 and 4's command blocks were then run in the same copy: each printed its Expected output, Task 4 Step 2 failed on the two version pins, and after Step 3 all 32 suites passed. `git apply --check` accepted all three patches on `2c76eff`.
- The probe that found which assertions break: applying only the new table to `2c76eff` failed `plan-lint.test.sh` (24 failures) and `plan-revise.test.sh` (2); every other suite passed. `t1-tests` is the minimal fix for those failures plus the spec §3 additions (in `ladder.test.sh`, the tier-eval table check and a check that every assigned agent is an execution implementer; `t3b`, `t3c`, `r6b`, `r8b` in `plan-lint.test.sh`) and the fixture-consistency edits the spec names.
- `tests/review-route.test.sh` is not edited before Task 4: `scripts/review-route` never reads the assignment table, and its final-fix fixture pins `impl-opus-medium` at total 5 on purpose (spec §3). `tests/next-step.test.sh` and `tests/inline-mode.test.sh` have no pairing a table-reading script checks.
- `rg` on this machine is a shell function, not a binary (`type rg`, 2026-10-02): it runs `$CLAUDE_CODE_EXECPATH`, else `/root/.local/bin/claude`, which links to `/root/.local/share/claude/versions/2.1.287` (`ls -l`, 2026-10-02) and acts as ripgrep when invoked as `rg`. Without a binary `node --test tests/*.test.mjs` fails one test (register row 14 of `docs/superpowers/registers/2026-10-01-tier-reevaluation.md`); Task 4 Step 5's two-line wrapper runs the same binary under that name, and with it all 22 pass (2026-10-02 run).
- Departure from spec §4, which reports the `ui-discovery` failure rather than fixing it: the plan fixes nothing either, and the wrapper lives only for the length of Task 4 Step 5, as in the 1.23.0 release plan.
- Codex executor lane is off: `scripts/codex-gate` printed `usable=false reason=plugin-api review=false lane=false resets_at=- source=probe` on 2026-10-02, so no task carries an `**Executor:**` line.
- Scores use the installed 1.23.0 ladder, which `plan-lint` reads: Task 1 at total 5 is assigned `impl-opus-medium` and is heavy, so it is delegated.
- Departure from spec §4: its first commit (§1 with its tests) becomes Task 1 (table and tests) and Task 2 (prose), because a reviewer can reject the prose while approving the table, and each commit leaves every suite green.
- Shape counting: Task 1's test edits apply one decision (expectations follow the new table) across five suites and count as one file shape beside the table, per `reference/ladder.md` §Scoring rubric. Task 2's four agent descriptions are one shape.
- Adjacent change from plan review: `README.md`'s reason for never routing to `judge-fable` cites a 2026-09-23 replay run when `judge-opus` was at high effort; Task 3 adds "at high effort" so the sentence stays true once the seat runs at medium.

## Task index

1. Lower the assignment table
2. Describe the lowered ladder
3. Run judge-opus at medium effort
4. Release 1.24.0

---

### Task 1: Lower the assignment table

**Files:**
- Modify: `plugins/dr-superpowers/reference/ladder.md` (the `assignment` block)
- Test: `plugins/dr-superpowers/tests/ladder.test.sh`, `plugins/dr-superpowers/tests/plan-lint.test.sh`, `plugins/dr-superpowers/tests/plan-revise.test.sh`, `plugins/dr-superpowers/tests/plan-lib.test.sh`, `plugins/dr-superpowers/tests/plan-amend.test.sh`

**Interfaces:**
- Consumes: nothing.
- Produces: the Assignment table (Contracts).

**Items:** 2

**Implementer:** dr-superpowers:impl-opus-medium
**Evaluation:** files 1 - spec 0 - coupling 2 - risk 2 = 5

What the test patch does, so a reviewer can check it against spec §3: the `plan-lint` base fixture's Task 2 (total 4) names `impl-sonnet-medium` and every `sed` variant keyed on it follows; the `ev()` rows 2 to 5 name the new agents; total-5 fixtures name `impl-sonnet-high` (except `review-route`'s, untouched); v9, r6 and r8 now pass at `--effort medium` and r9 at `low`, with new r6b and r8b failing at `low`; t3 checks a total-4 `impl-sonnet-high` line, t3b a total-5 `impl-opus-medium` line (ERROR) and t3c the same with an Override (WARN); `plan-revise` expects `low` for one total-2 task and `medium` for self-implemented total 4; `ladder.test.sh` asserts the seven rows and that every agent they name is an execution implementer.

- [ ] **Step 1: Extract and apply the test patch**

```bash
mkdir -p .superpowers/ladder-update
awk '$0 == "`````diff t1-tests" { f = 1; next } f && $0 == "`````" { exit } f' docs/superpowers/plans/2026-10-02-dr-superpowers-ladder-update.md > .superpowers/ladder-update/t1-tests.diff
git apply --check .superpowers/ladder-update/t1-tests.diff && git apply .superpowers/ladder-update/t1-tests.diff
git diff --stat -- plugins/dr-superpowers/
```

Expected: the five test files, ending `5 files changed, 64 insertions(+), 41 deletions(-)`.

`````diff t1-tests
diff --git a/plugins/dr-superpowers/tests/ladder.test.sh b/plugins/dr-superpowers/tests/ladder.test.sh
index 5b3f9f4..a34514d 100644
--- a/plugins/dr-superpowers/tests/ladder.test.sh
+++ b/plugins/dr-superpowers/tests/ladder.test.sh
@@ -58,6 +58,16 @@ check "assignment covers every score 0 through 6" "$missing" "NONE"
 above=$(printf '%s\n' "$assignment" | awk 'NF && $1 > 6 {print $1}' | tr '\n' ' ' | sed 's/ $//')
 check "assignment has no row above score 6" "${above:-NONE}" "NONE"
 
+# The rows the 2026-10-02 tier evaluation set, in order.
+check "assignment rows are the tier-eval table" "$(printf '%s\n' "$assignment" | tr '\n' ',')" \
+  "0 impl-haiku,1 impl-sonnet-low,2 impl-sonnet-low,3 impl-sonnet-medium,4 impl-sonnet-medium,5 impl-sonnet-high,6 impl-opus-high,"
+
+not_impl=NONE
+while read -r _ agent; do
+  case " $IMPLEMENTERS " in *" $agent "*) ;; *) not_impl="$agent" ;; esac
+done <<< "$assignment"
+check "every assigned agent is an execution implementer" "$not_impl" "NONE"
+
 # --- escalation table -------------------------------------------------------
 escalation=$(block escalation)
 check "escalation table has 7 rows" "$(printf '%s\n' "$escalation" | grep -c .)" "7"
diff --git a/plugins/dr-superpowers/tests/plan-amend.test.sh b/plugins/dr-superpowers/tests/plan-amend.test.sh
index e69d5f9..274e0ec 100644
--- a/plugins/dr-superpowers/tests/plan-amend.test.sh
+++ b/plugins/dr-superpowers/tests/plan-amend.test.sh
@@ -67,7 +67,7 @@ Print `hello NAME`.
 **Files:**
 - Modify: `a.sh`
 
-**Implementer:** dr-superpowers:impl-sonnet-high
+**Implementer:** dr-superpowers:impl-sonnet-medium
 **Evaluation:** files 0 - spec 1 - coupling 1 - risk 2 = 4
 
 Print `hello NAME` twice.
@@ -111,7 +111,7 @@ entry b6.md '## Header' '**Execution:** subagent — `claude --model sonnet --ef
 run docs/plan.md b6.md
 has "protected line" "$out" "rejected: Old text touches a line that cannot be amended"
 
-entry b7.md '## Task 2' '**Implementer:** dr-superpowers:impl-sonnet-high' '**Implementer:** dr-superpowers:impl-opus-high'
+entry b7.md '## Task 2' '**Implementer:** dr-superpowers:impl-sonnet-medium' '**Implementer:** dr-superpowers:impl-opus-high'
 run docs/plan.md b7.md
 check "new lint error: exit 1" "$status" "1"
 has "new lint error: reason" "$out" "rejected: the amendment introduces lint errors:"
diff --git a/plugins/dr-superpowers/tests/plan-lib.test.sh b/plugins/dr-superpowers/tests/plan-lib.test.sh
index 33da35f..925d753 100755
--- a/plugins/dr-superpowers/tests/plan-lib.test.sh
+++ b/plugins/dr-superpowers/tests/plan-lib.test.sh
@@ -234,7 +234,7 @@ sed 's/^|//' > "$TMP/exec.md" <<'EOF'
 |
 |### Task 2: offloaded
 |
-|**Implementer:** dr-superpowers:impl-sonnet-medium
+|**Implementer:** dr-superpowers:impl-sonnet-low
 |**Executor:** codex gpt-6-sol / medium
 |**Evaluation:** files 0 - spec 1 - coupling 1 - risk 0 = 2
 |
@@ -251,7 +251,7 @@ sed 's/^|//' > "$TMP/exec.md" <<'EOF'
 |
 |#### Part A: cheap
 |
-|**Implementer:** dr-superpowers:impl-sonnet-medium
+|**Implementer:** dr-superpowers:impl-sonnet-low
 |**Executor:** codex gpt-6-sol / medium
 |**Evaluation:** files 0 - spec 1 - coupling 1 - risk 0 = 2
 |
@@ -283,7 +283,7 @@ check "heavy wins over executor on a split task" \
 # removed one-third rule, which would also have delegated Task 2 as total 4.
 { printf '# Offload Fixture\n\n'
   for i in 1 2; do
-    printf '### Task %s: four band\n\n**Implementer:** dr-superpowers:impl-sonnet-high\n' "$i"
+    printf '### Task %s: four band\n\n**Implementer:** dr-superpowers:impl-sonnet-medium\n' "$i"
     [ "$i" = 1 ] && printf '**Executor:** codex gpt-6-sol / high\n'
     printf '**Evaluation:** files 1 - spec 1 - coupling 1 - risk 1 = 4\n\n'
   done
diff --git a/plugins/dr-superpowers/tests/plan-lint.test.sh b/plugins/dr-superpowers/tests/plan-lint.test.sh
index 75e1ac7..d2daa4f 100644
--- a/plugins/dr-superpowers/tests/plan-lint.test.sh
+++ b/plugins/dr-superpowers/tests/plan-lint.test.sh
@@ -101,7 +101,7 @@ echo hi
 **Files:**
 - Modify: `a.txt`
 
-**Implementer:** dr-superpowers:impl-sonnet-high
+**Implementer:** dr-superpowers:impl-sonnet-medium
 **Evaluation:** files 0 - spec 1 - coupling 1 - risk 2 = 4
 **Approach:** inline - skip 2: follows the pattern
 
@@ -207,18 +207,18 @@ has "Execution grammar" "$out" "ERROR header: Execution line does not match"
 variant v9.md 's/^\*\*Execution:\*\* .*/**Execution:** inline -- claude --model sonnet --effort medium -- all small/'
 lint v9.md
 lacks "inline at total 4 needs no opus" "$out" "needs --model opus"
-has "inline at total 4 needs effort high" "$out" "ERROR header: inline execution needs --effort high or above (effort medium)"
+lacks "inline at total 4 runs at effort medium" "$out" "inline execution needs --effort"
 lacks "inline at total 4 passes R5" "$out" "inline execution needs every task"
 lacks "double-hyphen separators and bare command parse" "$out" "Execution line does not match"
 variant v9b.md 's/^\*\*Execution:\*\* .*/**Execution:** inline — `claude --model opus --effort high` — Task 2 scores 4/'
 lint v9b.md
 lacks "inline at total 4 on opus is clean" "$out" "ERROR header: inline"
-variant v9c.md 's/^\*\*Execution:\*\* .*/**Execution:** inline — `claude --model opus --effort low` — x/; s/files 0 - spec 1 - coupling 1 - risk 2 = 4/files 1 - spec 1 - coupling 1 - risk 2 = 5/; s/impl-sonnet-high$/impl-opus-medium/'
+variant v9c.md 's/^\*\*Execution:\*\* .*/**Execution:** inline — `claude --model opus --effort low` — x/; s/files 0 - spec 1 - coupling 1 - risk 2 = 4/files 1 - spec 1 - coupling 1 - risk 2 = 5/; s/impl-sonnet-medium$/impl-sonnet-high/'
 lint v9c.md
 has "inline that delegates needs effort high" "$out" "ERROR header: inline execution needs --effort high or above (effort low)"
 lacks "a heavy minority no longer breaks inline" "$out" "inline execution needs every task"
 has "inline names the delegated task" "$out" "NOTE header: delegated: Task 2 (heavy)"
-variant v9c2.md 's/^\*\*Execution:\*\* .*/**Execution:** inline — `claude --model sonnet --effort high` — x/; s/files 0 - spec 1 - coupling 1 - risk 2 = 4/files 1 - spec 1 - coupling 1 - risk 2 = 5/; s/impl-sonnet-high$/impl-opus-medium/'
+variant v9c2.md 's/^\*\*Execution:\*\* .*/**Execution:** inline — `claude --model sonnet --effort high` — x/; s/files 0 - spec 1 - coupling 1 - risk 2 = 4/files 1 - spec 1 - coupling 1 - risk 2 = 5/; s/impl-sonnet-medium$/impl-sonnet-high/'
 lint v9c2.md
 check "a heavy minority inline at effort high: exit 0" "$status" "0"
 lacks "the model follows the tasks the session implements" "$out" "needs --model opus"
@@ -227,14 +227,14 @@ variant v9d.md 's/^\*\*Execution:\*\* .*/**Execution:** inline — `claude --mod
 lint v9d.md
 has "risk 3 is delegated" "$out" "NOTE header: delegated: Task 2 (heavy)"
 has "risk 3 inline needs effort high" "$out" "ERROR header: inline execution needs --effort high or above (effort low)"
-variant v9j.md 's/^\*\*Execution:\*\* .*/**Execution:** inline — `claude --model opus --effort high` — x/; s/^\*\*Implementer:\*\* dr-superpowers:impl-sonnet-high$/#### Part A: left half\n\n**Files:**\n- Modify: `a.txt`\n\n**Implementer:** dr-superpowers:impl-sonnet-low\n**Evaluation:** files 0 - spec 0 - coupling 1 - risk 0 = 1\n\n#### Part B: right half\n\n**Files:**\n- Modify: `b.txt`\n\n**Implementer:** dr-superpowers:impl-opus-medium\n**Evaluation:** files 1 - spec 0 - coupling 1 - risk 3 = 5/; /^\*\*Evaluation:\*\* files 0 - spec 1 - coupling 1 - risk 2 = 4$/d; /^\*\*Approach:\*\* inline - skip 2: follows the pattern$/d'
+variant v9j.md 's/^\*\*Execution:\*\* .*/**Execution:** inline — `claude --model opus --effort high` — x/; s/^\*\*Implementer:\*\* dr-superpowers:impl-sonnet-medium$/#### Part A: left half\n\n**Files:**\n- Modify: `a.txt`\n\n**Implementer:** dr-superpowers:impl-sonnet-low\n**Evaluation:** files 0 - spec 0 - coupling 1 - risk 0 = 1\n\n#### Part B: right half\n\n**Files:**\n- Modify: `b.txt`\n\n**Implementer:** dr-superpowers:impl-sonnet-high\n**Evaluation:** files 1 - spec 0 - coupling 1 - risk 3 = 5/; /^\*\*Evaluation:\*\* files 0 - spec 1 - coupling 1 - risk 2 = 4$/d; /^\*\*Approach:\*\* inline - skip 2: follows the pattern$/d'
 lint v9j.md
 has "a split task is heavy when one part is" "$out" "NOTE header: delegated: Task 2 (heavy)"
 check "a split task with a heavy part inline at effort high: exit 0" "$status" "0"
-variant v9h.md 's/^\*\*Execution:\*\* .*/**Execution:** inline — `claude --model opus --effort high` — x/; s/files 0 - spec 0 - coupling 1 - risk 0 = 1/files 1 - spec 0 - coupling 1 - risk 3 = 5/; s/impl-sonnet-low$/impl-opus-medium/; s/files 0 - spec 1 - coupling 1 - risk 2 = 4/files 1 - spec 1 - coupling 1 - risk 2 = 5/; s/impl-sonnet-high$/impl-opus-medium/'
+variant v9h.md 's/^\*\*Execution:\*\* .*/**Execution:** inline — `claude --model opus --effort high` — x/; s/files 0 - spec 0 - coupling 1 - risk 0 = 1/files 1 - spec 0 - coupling 1 - risk 3 = 5/; s/impl-sonnet-low$/impl-sonnet-high/; s/files 0 - spec 1 - coupling 1 - risk 2 = 4/files 1 - spec 1 - coupling 1 - risk 2 = 5/; s/impl-sonnet-medium$/impl-sonnet-high/'
 lint v9h.md
 has "a heavy majority on inline warns" "$out" "WARN header: Execution line is inline but 2 of 2 tasks are heavy"
-variant v9i.md 's/files 0 - spec 0 - coupling 1 - risk 0 = 1/files 1 - spec 0 - coupling 1 - risk 3 = 5/; s/impl-sonnet-low$/impl-opus-medium/; s/files 0 - spec 1 - coupling 1 - risk 2 = 4/files 1 - spec 1 - coupling 1 - risk 2 = 5/; s/impl-sonnet-high$/impl-opus-medium/'
+variant v9i.md 's/files 0 - spec 0 - coupling 1 - risk 0 = 1/files 1 - spec 0 - coupling 1 - risk 3 = 5/; s/impl-sonnet-low$/impl-sonnet-high/; s/files 0 - spec 1 - coupling 1 - risk 2 = 4/files 1 - spec 1 - coupling 1 - risk 2 = 5/; s/impl-sonnet-medium$/impl-sonnet-high/'
 lint v9i.md
 lacks "a heavy majority on subagent does not warn" "$out" "Execution line is subagent but"
 codex_plan | sed -E 's/^\*\*Execution:\*\* subagent/**Execution:** inline/; s/risk=0; weighted routing score=3/risk=3; weighted routing score=9/' > codex-inline.md
@@ -262,10 +262,10 @@ ev() { # ev <total> — "<agent> <evaluation>" for a lint-clean task at that tot
   case $1 in
     0) echo 'impl-haiku files 0 - spec 0 - coupling 0 - risk 0 = 0' ;;
     1) echo 'impl-sonnet-low files 0 - spec 0 - coupling 1 - risk 0 = 1' ;;
-    2) echo 'impl-sonnet-medium files 0 - spec 1 - coupling 1 - risk 0 = 2' ;;
-    3) echo 'impl-sonnet-high files 1 - spec 1 - coupling 1 - risk 0 = 3' ;;
-    4) echo 'impl-sonnet-high files 0 - spec 1 - coupling 1 - risk 2 = 4' ;;
-    5) echo 'impl-opus-medium files 1 - spec 1 - coupling 1 - risk 2 = 5' ;;
+    2) echo 'impl-sonnet-low files 0 - spec 1 - coupling 1 - risk 0 = 2' ;;
+    3) echo 'impl-sonnet-medium files 1 - spec 1 - coupling 1 - risk 0 = 3' ;;
+    4) echo 'impl-sonnet-medium files 0 - spec 1 - coupling 1 - risk 2 = 4' ;;
+    5) echo 'impl-sonnet-high files 1 - spec 1 - coupling 1 - risk 2 = 5' ;;
   esac
 }
 tplan() { # tplan <file> <mode> <model> <effort> <total ...> — one clean task per total
@@ -303,16 +303,22 @@ has "only the heavy task is delegated" "$out" "NOTE header: delegated: Task 1 (h
 lacks "total 4 is no delegation reason" "$out" "(total 4)"
 tplan r6.md inline sonnet medium 1 4 1 1 1 1
 lint r6.md
-has "a self-implemented total 4 needs effort high" "$out" "ERROR header: inline execution needs --effort high or above (effort medium)"
+check "a self-implemented total 4 runs at effort medium: exit 0" "$status" "0"
+tplan r6b.md inline sonnet low 1 4 1 1 1 1
+lint r6b.md
+has "a self-implemented total 4 needs effort medium" "$out" "ERROR header: inline execution needs --effort medium or above (effort low)"
 tplan r7.md inline sonnet max 1 4 1 1 1 1
 lint r7.md
 check "an effort above the required one: exit 0" "$status" "0"
 tplan r8.md inline sonnet medium 3 1 1 1 1 1
 lint r8.md
-has "a self-implemented total 3 needs effort high" "$out" "ERROR header: inline execution needs --effort high or above (effort medium)"
+check "a self-implemented total 3 runs at effort medium: exit 0" "$status" "0"
+tplan r8b.md inline sonnet low 3 1 1 1 1 1
+lint r8b.md
+has "a self-implemented total 3 needs effort medium" "$out" "ERROR header: inline execution needs --effort medium or above (effort low)"
 tplan r9.md inline sonnet low 2 1 1 1 1 1
 lint r9.md
-has "a self-implemented total 2 needs effort medium" "$out" "ERROR header: inline execution needs --effort medium or above (effort low)"
+check "a self-implemented total 2 runs at effort low: exit 0" "$status" "0"
 tplan r10.md inline sonnet low 0 0 0 0 0 0
 lint r10.md
 check "impl-haiku counts as low: exit 0" "$status" "0"
@@ -348,7 +354,7 @@ lacks "leading punctuation in a title survives the index check" "$out" "Task ind
 variant v9f.md '/^## Contracts$/{N;N;s/.*/```text\n## Contracts\n```/}'
 lint v9f.md
 has "a fenced section heading does not count" "$out" "ERROR header: missing '## Contracts' section"
-variant v9g.md 's/^\*\*Implementer:\*\* dr-superpowers:impl-sonnet-high$/#### Part A: left half\n\n**Files:**\n- Modify: `a.txt`\n\n**Implementer:** dr-superpowers:impl-sonnet-low\n**Evaluation:** files 0 - spec 0 - coupling 1 - risk 0 = 1\n\n#### Part B: right half\n\n**Files:**\n- Modify: `b.txt`\n\n**Implementer:** dr-superpowers:impl-sonnet-high/; /^\*\*Evaluation:\*\* files 0 - spec 1 - coupling 1 - risk 2 = 4$/d; /^\*\*Approach:\*\* inline - skip 2: follows the pattern$/d'
+variant v9g.md 's/^\*\*Implementer:\*\* dr-superpowers:impl-sonnet-medium$/#### Part A: left half\n\n**Files:**\n- Modify: `a.txt`\n\n**Implementer:** dr-superpowers:impl-sonnet-low\n**Evaluation:** files 0 - spec 0 - coupling 1 - risk 0 = 1\n\n#### Part B: right half\n\n**Files:**\n- Modify: `b.txt`\n\n**Implementer:** dr-superpowers:impl-sonnet-medium/; /^\*\*Evaluation:\*\* files 0 - spec 1 - coupling 1 - risk 2 = 4$/d; /^\*\*Approach:\*\* inline - skip 2: follows the pattern$/d'
 lint v9g.md
 has "split parts: part B is missing its Evaluation" "$out" "ERROR Task 2 part B: missing **Evaluation:** line"
 lacks "split parts: part A is clean" "$out" "Task 2 part A"
@@ -376,17 +382,24 @@ has "sum mismatch" "$out" "ERROR Task 2: scores sum to 4, not 5"
 variant t2.md 's/files 0 - spec 1 - coupling 1 - risk 2 = 4/files 2 - spec 1 - coupling 1 - risk 0 = 4/'
 lint t2.md
 has "Rule S" "$out" "ERROR Task 2: Rule S: files+spec+coupling must be below 4 and spec below 3"
-variant t3.md 's/impl-sonnet-high$/impl-opus-medium/'
+variant t3.md 's/impl-sonnet-medium$/impl-sonnet-high/'
 lint t3.md
-has "wrong agent" "$out" "ERROR Task 2: Implementer impl-opus-medium does not match the assignment table's impl-sonnet-high for total 4"
-variant t4.md 's/impl-sonnet-high$/impl-fable-high/'
+has "wrong agent" "$out" "ERROR Task 2: Implementer impl-sonnet-high does not match the assignment table's impl-sonnet-medium for total 4"
+variant t3b.md 's/files 0 - spec 1 - coupling 1 - risk 2 = 4/files 1 - spec 1 - coupling 1 - risk 2 = 5/; s/impl-sonnet-medium$/impl-opus-medium/'
+lint t3b.md
+has "a 1.23.0 total-5 agent is an error" "$out" "ERROR Task 2: Implementer impl-opus-medium does not match the assignment table's impl-sonnet-high for total 5"
+variant t3c.md 's/files 0 - spec 1 - coupling 1 - risk 2 = 4/files 1 - spec 1 - coupling 1 - risk 2 = 5/; s/impl-sonnet-medium$/impl-opus-medium/; s/^(\*\*Approach:\*\* .*)$/\1\n**Override:** owner kept Opus here/'
+lint t3c.md
+check "an Override keeps a 1.23.0 agent: exit 0" "$status" "0"
+has "an Override keeps a 1.23.0 agent as a warning" "$out" "WARN Task 2: Implementer impl-opus-medium does not match the assignment table's impl-sonnet-high for total 5"
+variant t4.md 's/impl-sonnet-medium$/impl-fable-high/'
 lint t4.md
 has "reserve name" "$out" "ERROR Task 2: impl-fable-high is a reserve tier; it needs a human **Override:**"
-variant t5.md 's/impl-sonnet-high$/impl-fable-high/; s/^(\*\*Approach:\*\* .*)$/\1\n**Override:** owner wants Fable here/'
+variant t5.md 's/impl-sonnet-medium$/impl-fable-high/; s/^(\*\*Approach:\*\* .*)$/\1\n**Override:** owner wants Fable here/'
 lint t5.md
 check "Override downgrades: exit 0" "$status" "0"
 has "Override downgrades to WARN" "$out" "WARN Task 2: impl-fable-high is a reserve tier"
-variant t6.md 's/files 0 - spec 1 - coupling 1 - risk 2 = 4/files 1 - spec 1 - coupling 1 - risk 3 = 6/; s/impl-sonnet-high$/impl-opus-high/'
+variant t6.md 's/files 0 - spec 1 - coupling 1 - risk 2 = 4/files 1 - spec 1 - coupling 1 - risk 3 = 6/; s/impl-sonnet-medium$/impl-opus-high/'
 lint t6.md
 lacks "impl-opus-high at total 6 is not a reserve finding" "$out" "reserve tier"
 lacks "impl-opus-high at total 6 matches" "$out" "does not match the assignment"
@@ -444,7 +457,7 @@ has "a fenced Routing policy line does not count" "$out" "ERROR header: Routing
 
 # --- the lazy lane probe ---
 # p1 makes Task 1 lane-eligible: total 2, risk 0, no Executor, no Override.
-variant p1.md 's/files 0 - spec 0 - coupling 1 - risk 0 = 1/files 0 - spec 1 - coupling 1 - risk 0 = 2/; s/impl-sonnet-low$/impl-sonnet-medium/'
+variant p1.md 's/files 0 - spec 0 - coupling 1 - risk 0 = 1/files 0 - spec 1 - coupling 1 - risk 0 = 2/'
 export PLAN_LINT_ROSTER="$TMP/usable.sh"
 rm -f probe-calls; lint p1.md
 has "usable codex: an eligible task without Executor warns" "$out" "WARN Task 1: lane-eligible with no **Executor:** line (codex gpt-6-sol / low)"
@@ -469,7 +482,7 @@ rm -f probe-calls; lint p1.md
 lacks "unusable codex: no lane warning" "$out" "lane-eligible"
 check "unusable codex: the probe still ran once" "$(calls)" "1"
 export PLAN_LINT_ROSTER="$TMP/usable.sh"
-variant p2.md 's/files 0 - spec 0 - coupling 1 - risk 0 = 1/files 0 - spec 1 - coupling 1 - risk 0 = 2/; s/impl-sonnet-low$/impl-sonnet-medium/; s/^(\*\*Evaluation:\*\* files 0 - spec 1 - coupling 1 - risk 0 = 2)$/\1\n**Executor:** codex gpt-6-sol \/ low/; s/^(\*\*Program:\*\* .*)$/\1\n\n> **External executors:** codex/'
+variant p2.md 's/files 0 - spec 0 - coupling 1 - risk 0 = 1/files 0 - spec 1 - coupling 1 - risk 0 = 2/; s/^(\*\*Evaluation:\*\* files 0 - spec 1 - coupling 1 - risk 0 = 2)$/\1\n**Executor:** codex gpt-6-sol \/ low/; s/^(\*\*Program:\*\* .*)$/\1\n\n> **External executors:** codex/'
 rm -f probe-calls; lint p2.md
 lacks "an Executor line clears the candidate" "$out" "lane-eligible"
 lacks "the Executor fixture is otherwise clean" "$out" "ERROR Task 1"
@@ -477,7 +490,7 @@ check "a plan whose only candidate has an Executor never probes" "$(calls)" "0"
 variant p3.md 's/files 0 - spec 0 - coupling 1 - risk 0 = 1/files 0 - spec 1 - coupling 1 - risk 0 = 2/; s/impl-sonnet-low$/impl-sonnet-high/; s/^(\*\*Evaluation:\*\* files 0 - spec 1 - coupling 1 - risk 0 = 2)$/\1\n**Override:** owner kept the Sonnet-high tier/'
 rm -f probe-calls; lint p3.md
 lacks "an overridden task is not a candidate" "$out" "lane-eligible"
-variant p4.md 's/files 0 - spec 0 - coupling 1 - risk 0 = 1/files 0 - spec 1 - coupling 1 - risk 0 = 2/; s/impl-sonnet-low$/impl-sonnet-medium/; s/^\*\*Execution:\*\* .*/**Execution:** inline — `claude --model opus --effort low` — x/'
+variant p4.md 's/files 0 - spec 0 - coupling 1 - risk 0 = 1/files 0 - spec 1 - coupling 1 - risk 0 = 2/; s/^\*\*Execution:\*\* .*/**Execution:** inline — `claude --model opus --effort low` — x/'
 rm -f probe-calls; lint p4.md
 lacks "an inline plan gets no lane warning" "$out" "lane-eligible"
 check "an inline plan never probes" "$(calls)" "0"
@@ -492,7 +505,7 @@ Reason: the plan picked the wrong tier
 Cost if wrong: one re-dispatch
 ### Old
 ````text
-**Implementer:** dr-superpowers:impl-sonnet-high
+**Implementer:** dr-superpowers:impl-sonnet-medium
 ````
 ### New
 ````text
@@ -501,7 +514,7 @@ Cost if wrong: one re-dispatch
 EOF
 lint clean.md --amendments am.md
 has "amendments applied before checks" "$out" "ERROR Task 2: Implementer impl-opus-medium does not match"
-sed 's/impl-sonnet-high$/impl-haiku/' am.md > am-bad.md
+sed 's/impl-sonnet-medium$/impl-haiku/' am.md > am-bad.md
 lint clean.md --amendments am-bad.md
 has "non-applying amendment" "$out" "ERROR header: amendment A1 does not apply"
 
@@ -616,7 +629,7 @@ cat "$HERE/../reference/ladder.md" "$HERE/fixtures/stub-ladder.md" > "$DR_LADDER
 
 # A stub Executor line validates against the stub's own blocks. The fixture
 # ladder supplies them, so the shipped ladder is untouched.
-variant s1.md 's/files 0 - spec 0 - coupling 1 - risk 0 = 1/files 0 - spec 1 - coupling 1 - risk 0 = 2/; s/impl-sonnet-low$/impl-sonnet-medium/; s/^(\*\*Evaluation:\*\* files 0 - spec 1 - coupling 1 - risk 0 = 2)$/\1\n**Executor:** stub stub-model \/ medium/; s/^(\*\*Program:\*\* .*)$/\1\n\n> **External executors:** stub/'
+variant s1.md 's/files 0 - spec 0 - coupling 1 - risk 0 = 1/files 0 - spec 1 - coupling 1 - risk 0 = 2/; s/^(\*\*Evaluation:\*\* files 0 - spec 1 - coupling 1 - risk 0 = 2)$/\1\n**Executor:** stub stub-model \/ medium/; s/^(\*\*Program:\*\* .*)$/\1\n\n> **External executors:** stub/'
 lint s1.md
 lacks "a stub Executor line is accepted" "$out" "ERROR Task 1"
 
@@ -632,12 +645,12 @@ has "a missing gate block is an error, not an open gate" "$out" \
 DR_LADDER="$TMP/stub-ladder.md"
 
 # An id with no registry entry is rejected, naming the registry.
-variant s2.md 's/files 0 - spec 0 - coupling 1 - risk 0 = 1/files 0 - spec 1 - coupling 1 - risk 0 = 2/; s/impl-sonnet-low$/impl-sonnet-medium/; s/^(\*\*Evaluation:\*\* files 0 - spec 1 - coupling 1 - risk 0 = 2)$/\1\n**Executor:** nosuch m \/ medium/; s/^(\*\*Program:\*\* .*)$/\1\n\n> **External executors:** nosuch/'
+variant s2.md 's/files 0 - spec 0 - coupling 1 - risk 0 = 1/files 0 - spec 1 - coupling 1 - risk 0 = 2/; s/^(\*\*Evaluation:\*\* files 0 - spec 1 - coupling 1 - risk 0 = 2)$/\1\n**Executor:** nosuch m \/ medium/; s/^(\*\*Program:\*\* .*)$/\1\n\n> **External executors:** nosuch/'
 lint s2.md
 has "an unregistered Executor id is an error" "$out" "ERROR Task 1: Executor names no registered executor: nosuch (run 'executors list')"
 
 # The header must name the line's own id, not merely some executor.
-variant s3.md 's/files 0 - spec 0 - coupling 1 - risk 0 = 1/files 0 - spec 1 - coupling 1 - risk 0 = 2/; s/impl-sonnet-low$/impl-sonnet-medium/; s/^(\*\*Evaluation:\*\* files 0 - spec 1 - coupling 1 - risk 0 = 2)$/\1\n**Executor:** stub stub-model \/ medium/; s/^(\*\*Program:\*\* .*)$/\1\n\n> **External executors:** codex/'
+variant s3.md 's/files 0 - spec 0 - coupling 1 - risk 0 = 1/files 0 - spec 1 - coupling 1 - risk 0 = 2/; s/^(\*\*Evaluation:\*\* files 0 - spec 1 - coupling 1 - risk 0 = 2)$/\1\n**Executor:** stub stub-model \/ medium/; s/^(\*\*Program:\*\* .*)$/\1\n\n> **External executors:** codex/'
 lint s3.md
 has "the header must name the line's executor" "$out" "ERROR Task 1: Executor used but the header's '> **External executors:**' line does not name stub"
 
@@ -712,7 +725,7 @@ inline_plan() { # inline_plan <file> <execution line>
 |
 |### Task 1: offloaded four band
 |
-|**Implementer:** dr-superpowers:impl-sonnet-high
+|**Implementer:** dr-superpowers:impl-sonnet-medium
 |**Executor:** codex gpt-6-sol / high
 |**Evaluation:** files 1 - spec 1 - coupling 1 - risk 1 = 4
 |
@@ -774,27 +787,27 @@ HDR
   } > "$1"
 }
 
-lintplan fenced-only.md "$(printf '### Task 1: One\n\n**Files:**\n- Create: `x.txt`\n\n**Implementer:** dr-superpowers:impl-sonnet-medium\n\n```markdown\n**Evaluation:** files 1 - spec 0 - coupling 1 - risk 0 = 2\n```\n')"
+lintplan fenced-only.md "$(printf '### Task 1: One\n\n**Files:**\n- Create: `x.txt`\n\n**Implementer:** dr-superpowers:impl-sonnet-low\n\n```markdown\n**Evaluation:** files 1 - spec 0 - coupling 1 - risk 0 = 2\n```\n')"
 lint fenced-only.md
 has "a fenced-only score is a missing Evaluation line" "$out" "ERROR Task 1: missing **Evaluation:** line"
 
-lintplan stale-parent.md "$(printf '### Task 1: One\n\n**Files:**\n- Create: `x.txt`\n\n**Evaluation:** files 2 - spec 1 - coupling 2 - risk 1 = 6\n\n#### Part A: a\n\n**Files:**\n- Create: `a.txt`\n\n**Implementer:** dr-superpowers:impl-sonnet-medium\n**Evaluation:** files 1 - spec 0 - coupling 1 - risk 0 = 2\n\n#### Part B: b\n\n**Files:**\n- Create: `b.txt`\n\n**Implementer:** dr-superpowers:impl-sonnet-medium\n**Evaluation:** files 1 - spec 0 - coupling 1 - risk 0 = 2\n')"
+lintplan stale-parent.md "$(printf '### Task 1: One\n\n**Files:**\n- Create: `x.txt`\n\n**Evaluation:** files 2 - spec 1 - coupling 2 - risk 1 = 6\n\n#### Part A: a\n\n**Files:**\n- Create: `a.txt`\n\n**Implementer:** dr-superpowers:impl-sonnet-low\n**Evaluation:** files 1 - spec 0 - coupling 1 - risk 0 = 2\n\n#### Part B: b\n\n**Files:**\n- Create: `b.txt`\n\n**Implementer:** dr-superpowers:impl-sonnet-low\n**Evaluation:** files 1 - spec 0 - coupling 1 - risk 0 = 2\n')"
 lint stale-parent.md
 has "a stale parent score is a NOTE" "$out" \
   "NOTE Task 1: an **Evaluation:** line above the first part does not score the task"
 lacks "a stale parent score is not an error" "$out" "ERROR Task 1"
 check "the stale-parent fixture is otherwise clean" "$status" "0"
 
-lintplan clean-split.md "$(printf '### Task 1: One\n\n**Files:**\n- Create: `x.txt`\n\n#### Part A: a\n\n**Files:**\n- Create: `a.txt`\n\n**Implementer:** dr-superpowers:impl-sonnet-medium\n**Evaluation:** files 1 - spec 0 - coupling 1 - risk 0 = 2\n\n#### Part B: b\n\n**Files:**\n- Create: `b.txt`\n\n**Implementer:** dr-superpowers:impl-sonnet-medium\n**Evaluation:** files 1 - spec 0 - coupling 1 - risk 0 = 2\n')"
+lintplan clean-split.md "$(printf '### Task 1: One\n\n**Files:**\n- Create: `x.txt`\n\n#### Part A: a\n\n**Files:**\n- Create: `a.txt`\n\n**Implementer:** dr-superpowers:impl-sonnet-low\n**Evaluation:** files 1 - spec 0 - coupling 1 - risk 0 = 2\n\n#### Part B: b\n\n**Files:**\n- Create: `b.txt`\n\n**Implementer:** dr-superpowers:impl-sonnet-low\n**Evaluation:** files 1 - spec 0 - coupling 1 - risk 0 = 2\n')"
 lint clean-split.md
 lacks "a clean split earns no NOTE" "$out" "above the first part"
 check "the clean-split fixture lints clean" "$status" "0"
 
-lintplan fenced-part.md "$(printf '### Task 1: One\n\n**Files:**\n- Create: `x.txt`\n\n**Implementer:** dr-superpowers:impl-sonnet-medium\n**Evaluation:** files 1 - spec 0 - coupling 1 - risk 0 = 2\n\n```markdown\n#### Part A: an example, not a part\n```\n')"
+lintplan fenced-part.md "$(printf '### Task 1: One\n\n**Files:**\n- Create: `x.txt`\n\n**Implementer:** dr-superpowers:impl-sonnet-low\n**Evaluation:** files 1 - spec 0 - coupling 1 - risk 0 = 2\n\n```markdown\n#### Part A: an example, not a part\n```\n')"
 lint fenced-part.md
 lacks "a fenced part heading does not create a part" "$out" "Task 1 part A"
 
-lintplan fenced-files.md "$(printf '### Task 1: One\n\n**Implementer:** dr-superpowers:impl-sonnet-medium\n**Evaluation:** files 1 - spec 0 - coupling 1 - risk 0 = 2\n\n```markdown\n**Files:**\n- Create: `x.txt`\n```\n')"
+lintplan fenced-files.md "$(printf '### Task 1: One\n\n**Implementer:** dr-superpowers:impl-sonnet-low\n**Evaluation:** files 1 - spec 0 - coupling 1 - risk 0 = 2\n\n```markdown\n**Files:**\n- Create: `x.txt`\n```\n')"
 lint fenced-files.md
 has "a fenced-only Files block is a missing Files block" "$out" "ERROR Task 1: missing **Files:** block"
 
diff --git a/plugins/dr-superpowers/tests/plan-revise.test.sh b/plugins/dr-superpowers/tests/plan-revise.test.sh
index ea056a6..aae8a9e 100644
--- a/plugins/dr-superpowers/tests/plan-revise.test.sh
+++ b/plugins/dr-superpowers/tests/plan-revise.test.sh
@@ -185,7 +185,7 @@ out=$(run | grep '^recommend')
 check "one light task recommends inline" "$(field execution "$out")" "inline"
 check "one light task recommends sonnet" "$(field model "$out")" "sonnet"
 check "one light task delegates nothing" "$(field delegated "$out")" "0/1"
-check "one light task takes the table's effort" "$(field effort "$out")" "medium"
+check "one light task takes the table's effort" "$(field effort "$out")" "low"
 
 three() { # three <eval 1> <eval 2> <eval 3>
   plan "$(printf '### Task 1: One\n\n**Files:**\n- Create: `x`\n\n%s\n\n### Task 2: Two\n\n**Files:**\n- Create: `y`\n\n%s\n\n### Task 3: Three\n\n**Files:**\n- Create: `z`\n\n%s\n' "$1" "$2" "$3")"
@@ -206,7 +206,7 @@ three "$E4" "$E4" "$E2"
 out=$(run | grep '^recommend')
 check "total-4 tasks are self-implemented" "$(field delegated "$out")" "0/3"
 check "a self-implemented total 4 stays on sonnet" "$(field model "$out")" "sonnet"
-check "a self-implemented total 4 needs effort high" "$(field effort "$out")" "high"
+check "a self-implemented total 4 needs effort medium" "$(field effort "$out")" "medium"
 
 # --- exits ---
 plan "$(mktask 1 0 1 0 2)"
`````

- [ ] **Step 2: Run the tests to verify they fail**

Run: `for t in ladder plan-lint plan-revise plan-lib plan-amend; do echo "$t: $(timeout 300 bash plugins/dr-superpowers/tests/$t.test.sh 2>&1 | tail -1)"; done`
Expected:

```
ladder: 26 passed, 1 failed
plan-lint: 137 passed, 28 failed
plan-revise: 84 passed, 2 failed
plan-lib: 74 passed, 0 failed
plan-amend: 22 passed, 0 failed
```

- [ ] **Step 3: Extract and apply the table patch**

```bash
awk '$0 == "`````diff t1-table" { f = 1; next } f && $0 == "`````" { exit } f' docs/superpowers/plans/2026-10-02-dr-superpowers-ladder-update.md > .superpowers/ladder-update/t1-table.diff
git apply --check .superpowers/ladder-update/t1-table.diff && git apply .superpowers/ladder-update/t1-table.diff
sed -n '/^```assignment$/,/^```$/p' plugins/dr-superpowers/reference/ladder.md
```

Expected: the block lists the seven rows of the Assignment table contract.

`````diff t1-table
diff --git a/plugins/dr-superpowers/reference/ladder.md b/plugins/dr-superpowers/reference/ladder.md
index 7396e98..c07f0ce 100644
--- a/plugins/dr-superpowers/reference/ladder.md
+++ b/plugins/dr-superpowers/reference/ladder.md
@@ -73,10 +73,10 @@ always reach the same agent.
 ```assignment
 0 impl-haiku
 1 impl-sonnet-low
-2 impl-sonnet-medium
-3 impl-sonnet-high
-4 impl-sonnet-high
-5 impl-opus-medium
+2 impl-sonnet-low
+3 impl-sonnet-medium
+4 impl-sonnet-medium
+5 impl-sonnet-high
 6 impl-opus-high
 ```
 
`````

- [ ] **Step 4: Run the tests to verify they pass**

Run: `for t in ladder plan-lint plan-revise plan-lib plan-amend; do echo "$t: $(timeout 300 bash plugins/dr-superpowers/tests/$t.test.sh 2>&1 | tail -1)"; done`
Expected:

```
ladder: 27 passed, 0 failed
plan-lint: 165 passed, 0 failed
plan-revise: 86 passed, 0 failed
plan-lib: 74 passed, 0 failed
plan-amend: 22 passed, 0 failed
```

- [ ] **Step 5: Run every plugin suite**

Run: `for t in plugins/dr-superpowers/tests/*.test.sh; do timeout 300 bash "$t" >/dev/null 2>&1 || echo "FAIL $t"; done; echo suites-done`
Expected: only `suites-done`.

- [ ] **Step 6: Commit**

```bash
git add plugins/dr-superpowers/reference/ladder.md plugins/dr-superpowers/tests/ladder.test.sh plugins/dr-superpowers/tests/plan-lint.test.sh plugins/dr-superpowers/tests/plan-revise.test.sh plugins/dr-superpowers/tests/plan-lib.test.sh plugins/dr-superpowers/tests/plan-amend.test.sh
git commit -m "feat(superpowers): lower the ladder per tier eval" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 2: Describe the lowered ladder

**Files:**
- Modify: `plugins/dr-superpowers/reference/ladder.md` (§Plans written before 1.23.0, §What the range actually reaches)
- Modify: `plugins/dr-superpowers/agents/impl-sonnet-low.md`, `plugins/dr-superpowers/agents/impl-sonnet-medium.md`, `plugins/dr-superpowers/agents/impl-sonnet-high.md`, `plugins/dr-superpowers/agents/impl-opus-medium.md` (`description:`)
- Modify: `plugins/dr-superpowers/README.md`, `plugins/dr-superpowers/skills/writing-plans/SKILL.md`, `plugins/dr-superpowers/reference/executor-lane.md`

**Interfaces:**
- Consumes: the Assignment table (Contracts), committed by Task 1.
- Produces: nothing.

**Items:** 2

**Implementer:** dr-superpowers:impl-sonnet-high
**Evaluation:** files 2 - spec 0 - coupling 1 - risk 0 = 3

What the patch does: `ladder.md` §Plans written before 1.23.0 becomes §Plans written before 1.24.0 and names both table changes and both fixes; §What the range actually reaches says Haiku takes 0, Sonnet 1 to 5 and Opus only 6, and names the tier evaluation and its limits; the four agent descriptions state their new scores (`impl-opus-medium` becomes an escalation rung); the README roster sentence names both unassigned Opus agents; the README and `writing-plans` total-5 examples name `impl-sonnet-high`; `writing-plans` §Choosing the Execution line no longer says every total below 5 goes to Haiku or Sonnet; `executor-lane.md`'s four `impl-sonnet-medium` lines (a total-2 example) name `impl-sonnet-low`.

- [ ] **Step 1: Confirm the old prose is in place**

```bash
P=plugins/dr-superpowers
chk() { if grep -qF -- "$2" "$P/$1"; then echo "has   $1: $2"; else echo "lacks $1: $2"; fi; }
chk agents/impl-sonnet-low.md 'for scores 1 and 2:'
chk agents/impl-sonnet-medium.md 'for scores 3 and 4:'
chk agents/impl-sonnet-high.md 'for score 5:'
chk agents/impl-opus-medium.md 'no score assigns it'
chk README.md 'or `impl-opus-medium`; both are reached only by'
chk reference/ladder.md '### Plans written before 1.24.0'
chk reference/ladder.md 'Sonnet totals 1 to 5'
chk skills/writing-plans/SKILL.md '(total 4 or less, risk below 3)'
grep -c 'impl-sonnet-medium' $P/reference/executor-lane.md
```

Expected: eight `lacks` lines, then `4`.

- [ ] **Step 2: Extract and apply the prose patch**

```bash
mkdir -p .superpowers/ladder-update
awk '$0 == "`````diff t2-prose" { f = 1; next } f && $0 == "`````" { exit } f' docs/superpowers/plans/2026-10-02-dr-superpowers-ladder-update.md > .superpowers/ladder-update/t2-prose.diff
git apply --check .superpowers/ladder-update/t2-prose.diff && git apply .superpowers/ladder-update/t2-prose.diff
git diff --stat -- plugins/dr-superpowers/
```

Expected: ending `8 files changed, 36 insertions(+), 26 deletions(-)`.

`````diff t2-prose
diff --git a/plugins/dr-superpowers/README.md b/plugins/dr-superpowers/README.md
index 118e68a..936f3ba 100644
--- a/plugins/dr-superpowers/README.md
+++ b/plugins/dr-superpowers/README.md
@@ -53,7 +53,8 @@ read time per [legacy-names.md](reference/legacy-names.md).
 **Twenty agents in three classes.** Seven execution implementers - Sonnet 5.5
 and Opus 5.5 at `low`, `medium`, and `high`, plus one Haiku 4.5 agent - are
 everything the assignment table and the escalation ladder can reach; no score
-assigns `impl-opus-low`, which is reached only by escalation. Nine reserve
+assigns `impl-opus-low` or `impl-opus-medium`; both are reached only by
+escalation. Nine reserve
 implementers - the `xhigh` and `max` efforts, and every Fable 5.1 tier - are
 reachable only by a human override, or by a task that has already been split
 once and still exhausted `impl-opus-high`. Four read-only role agents - the
@@ -356,7 +357,7 @@ your explicit instruction overrides it. Each task then reads:
 - Consumes: `formatRow(row: Row): string` from Task 2
 - Produces: `runExport(cfg: Config): Promise<Report>`
 
-**Implementer:** dr-superpowers:impl-opus-medium
+**Implementer:** dr-superpowers:impl-sonnet-high
 **Evaluation:** files 0 - spec 1 - coupling 2 - risk 2 = 5
 **Approach:** inline - skip 2: follows the existing exporter pattern
 ```
diff --git a/plugins/dr-superpowers/agents/impl-opus-medium.md b/plugins/dr-superpowers/agents/impl-opus-medium.md
index 802f37b..8515820 100644
--- a/plugins/dr-superpowers/agents/impl-opus-medium.md
+++ b/plugins/dr-superpowers/agents/impl-opus-medium.md
@@ -1,6 +1,6 @@
 ---
 name: impl-opus-medium
-description: "Task implementer running Opus 5.5 at medium effort. Dispatched by dr-superpowers for score 5: coupled work carrying a shared-path or data-shape risk."
+description: "Task implementer running Opus 5.5 at medium effort. Escalation rung for impl-sonnet-medium and impl-opus-low in dr-superpowers: no score assigns it."
 model: opus
 effort: medium
 skills:
diff --git a/plugins/dr-superpowers/agents/impl-sonnet-high.md b/plugins/dr-superpowers/agents/impl-sonnet-high.md
index 9cd6e9c..11fe81c 100644
--- a/plugins/dr-superpowers/agents/impl-sonnet-high.md
+++ b/plugins/dr-superpowers/agents/impl-sonnet-high.md
@@ -1,6 +1,6 @@
 ---
 name: impl-sonnet-high
-description: "Task implementer running Sonnet 5.5 at high effort. Dispatched by dr-superpowers for scores 3 and 4: ordinary multi-file work with exact signatures supplied, and work whose reducible axes are exhausted and whose risk is real."
+description: "Task implementer running Sonnet 5.5 at high effort. Dispatched by dr-superpowers for score 5: coupled work carrying a shared-path or data-shape risk."
 model: sonnet
 effort: high
 skills:
diff --git a/plugins/dr-superpowers/agents/impl-sonnet-low.md b/plugins/dr-superpowers/agents/impl-sonnet-low.md
index a908f05..44ba839 100644
--- a/plugins/dr-superpowers/agents/impl-sonnet-low.md
+++ b/plugins/dr-superpowers/agents/impl-sonnet-low.md
@@ -1,6 +1,6 @@
 ---
 name: impl-sonnet-low
-description: "Task implementer running Sonnet 5.5 at low effort. Dispatched by dr-superpowers for score 1: two or three files with near-complete code supplied."
+description: "Task implementer running Sonnet 5.5 at low effort. Dispatched by dr-superpowers for scores 1 and 2: small, well-specified changes with near-complete code supplied."
 model: sonnet
 effort: low
 skills:
diff --git a/plugins/dr-superpowers/agents/impl-sonnet-medium.md b/plugins/dr-superpowers/agents/impl-sonnet-medium.md
index f2926af..b2f26fb 100644
--- a/plugins/dr-superpowers/agents/impl-sonnet-medium.md
+++ b/plugins/dr-superpowers/agents/impl-sonnet-medium.md
@@ -1,6 +1,6 @@
 ---
 name: impl-sonnet-medium
-description: "Task implementer running Sonnet 5.5 at medium effort. Dispatched by dr-superpowers for score 2: small well-specified changes with light coupling."
+description: "Task implementer running Sonnet 5.5 at medium effort. Dispatched by dr-superpowers for scores 3 and 4: ordinary multi-file work with exact signatures supplied, and work whose reducible axes are exhausted and whose risk is real."
 model: sonnet
 effort: medium
 skills:
diff --git a/plugins/dr-superpowers/reference/executor-lane.md b/plugins/dr-superpowers/reference/executor-lane.md
index c82471b..cf05b12 100644
--- a/plugins/dr-superpowers/reference/executor-lane.md
+++ b/plugins/dr-superpowers/reference/executor-lane.md
@@ -70,7 +70,7 @@ and gains nothing.
 executor is an override on a second line, never a replacement on the first:
 
 ```markdown
-**Implementer:** dr-superpowers:impl-sonnet-medium
+**Implementer:** dr-superpowers:impl-sonnet-low
 **Executor:** <id> <model> / <effort>
 **Evaluation:** files 0 - spec 1 - coupling 1 - risk 0 = 2
 ```
@@ -130,7 +130,7 @@ for ownership, artifacts, approved write sets, and recovery operations.
    entry's `reason` field:
 
    ```
-   Task <N>: implementer impl-sonnet-medium (assigned; base <sha7>; executor <id> unavailable - <reason>)
+   Task <N>: implementer impl-sonnet-low (assigned; base <sha7>; executor <id> unavailable - <reason>)
    ```
 
    Never fall back silently. A silent fallback makes the whole lane invisible.
@@ -164,7 +164,7 @@ for ownership, artifacts, approved write sets, and recovery operations.
    thread id from its `thread=` field:
 
    ```
-   Task <N>: implementer impl-sonnet-medium (assigned; base <sha7>; executor <id> <model>/<effort>, thread 01a0...)
+   Task <N>: implementer impl-sonnet-low (assigned; base <sha7>; executor <id> <model>/<effort>, thread 01a0...)
    ```
 
    The thread id must reach the ledger. It also lands in the report file. If it
@@ -348,7 +348,7 @@ Record any of this inside the fix-round line the loop is already writing, never
 as a line of its own:
 
 ```
-Task <N>: fix round 2/5 (0 addressed, 2 open - codex quota exhausted, retried once then handed back; commits a7f..a7f; HANDBACK to impl-sonnet-medium)
+Task <N>: fix round 2/5 (0 addressed, 2 open - codex quota exhausted, retried once then handed back; commits a7f..a7f; HANDBACK to impl-sonnet-low)
 ```
 
 A handback from a failed resume is still a handback: say it aloud, and let the
diff --git a/plugins/dr-superpowers/reference/ladder.md b/plugins/dr-superpowers/reference/ladder.md
index c07f0ce..f753e1d 100644
--- a/plugins/dr-superpowers/reference/ladder.md
+++ b/plugins/dr-superpowers/reference/ladder.md
@@ -56,14 +56,17 @@ skipped, not that a higher tier is needed.
 applies only when a human overrides Rule S and keeps an undecided-approach task
 as written. It raises; it never lowers.
 
-### Plans written before 1.23.0
-
-Until 1.23.0 the assignment table sent total 4 to `impl-opus-low`. A plan
-written then names that agent for a total-4 task, and `plan-lint` reports the
-line as a table mismatch. Change it to `impl-sonnet-high`, or keep Opus with a
-human `**Override:**` line below the Evaluation line, which turns the finding
-into a warning. An inline Execution line on `opus low` must also rise to
-`--effort high`, which the effort check requires for a total-4 task.
+### Plans written before 1.24.0
+
+The assignment table has changed twice. Until 1.23.0 it sent total 4 to
+`impl-opus-low`. Until 1.24.0 it sent total 2 to `impl-sonnet-medium`, totals 3
+and 4 to `impl-sonnet-high`, and total 5 to `impl-opus-medium`. A plan written
+before either change names the old agent, and `plan-lint` reports the line as a
+table mismatch. Change it to the agent the table below names, or keep the old
+agent with a human `**Override:**` line below the Evaluation line, which turns
+the finding into a warning. An inline Execution line must still meet the effort
+check, which reads the current table: an `opus low` line with a self-implemented
+total 4 task must rise to `--effort medium`.
 
 ## Assignment table
 
@@ -184,11 +187,16 @@ A plan written to dr-superpowers:writing-plans bans placeholders and requires th
 real code in every code step, so a compliant task scores 0 or 1 on spec
 completeness almost by construction. Combined with Rule S, initial assignments
 cluster in the 0 to 3 band. Scores of 4 to 6 are reached almost entirely
-through the Risk axis, which is the one axis splitting cannot reduce. Haiku and
-Sonnet take totals 0 to 4; Opus is assigned from 5 up, and otherwise reached by
-escalation. Total 4 went to Opus until Sonnet 5.5, which matches Opus 5.5 on
-well-scoped agentic coding (Terminal-Bench, CursorBench) at half the price and
-trails it on FrontierCode's open-ended work.
+through the Risk axis, which is the one axis splitting cannot reduce. Haiku
+takes total 0 and Sonnet totals 1 to 5; Opus is assigned only at 6, and
+otherwise reached by escalation. Total 4 went to Opus until Sonnet 5.5, which
+matches Opus 5.5 on well-scoped agentic coding (Terminal-Bench, CursorBench) at
+half the price and trails it on FrontierCode's open-ended work. Totals 2 to 5
+moved one rung cheaper in 1.24.0 on a replay of this plugin's own plan history
+(the 2026-10-02 tier evaluation, `evals/tiers/` in the plugin's repository):
+the cheaper agent passed every case the old one passed, at a lower cost per
+pass. That was one repetition, mostly of tasks whose plan supplied the code, so
+the escalation table stays the backstop.
 
 That is the intended outcome. Do not inflate an axis to land on a tier that feels
 right; if a task feels harder than its score, the plan text is probably hiding
diff --git a/plugins/dr-superpowers/skills/writing-plans/SKILL.md b/plugins/dr-superpowers/skills/writing-plans/SKILL.md
index 878f909..6b6b8fc 100644
--- a/plugins/dr-superpowers/skills/writing-plans/SKILL.md
+++ b/plugins/dr-superpowers/skills/writing-plans/SKILL.md
@@ -131,8 +131,9 @@ per-task review. The tasks not delegated are the **self-implemented** tasks.
 - `subagent` when more than half the tasks are heavy:
   `claude --model sonnet --effort high`. The controller owns no judgment calls
   — the ruling seat does — so it needs no stronger model.
-- Otherwise `inline`, the default, on `sonnet`: the assignment table sends
-  every total below 5 to Haiku or Sonnet, and heavy tasks are delegated. `<e>`
+- Otherwise `inline`, the default, on `sonnet`: every self-implemented task
+  (total 4 or less, risk below 3) is assigned to Haiku or Sonnet, and heavy
+  tasks are delegated. `<e>`
   is the assignment-table effort of the highest self-implemented total
   (`impl-haiku` counts as `low`), raised to `high` when any task is delegated:
   `claude --model sonnet --effort <e>`. When every task is heavy
@@ -250,7 +251,7 @@ user's inline or delegation preference on either host.
      `inline` reason cites a skip condition by number
 
    ```markdown
-   **Implementer:** dr-superpowers:impl-opus-medium
+   **Implementer:** dr-superpowers:impl-sonnet-high
    **Evaluation:** files 1 - spec 0 - coupling 2 - risk 2 = 5
    **Approach:** inline - skip 2: follows the existing exporter pattern
    ```
`````

- [ ] **Step 3: Confirm the new prose**

Run the Step 1 block again.
Expected: eight `has` lines, then `0`.

- [ ] **Step 4: Run every plugin suite**

Run: `for t in plugins/dr-superpowers/tests/*.test.sh; do timeout 300 bash "$t" >/dev/null 2>&1 || echo "FAIL $t"; done; echo suites-done`
Expected: only `suites-done`.

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-superpowers/reference/ladder.md plugins/dr-superpowers/agents/impl-sonnet-low.md plugins/dr-superpowers/agents/impl-sonnet-medium.md plugins/dr-superpowers/agents/impl-sonnet-high.md plugins/dr-superpowers/agents/impl-opus-medium.md plugins/dr-superpowers/README.md plugins/dr-superpowers/skills/writing-plans/SKILL.md plugins/dr-superpowers/reference/executor-lane.md
git commit -m "docs(superpowers): describe the lowered ladder" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 3: Run judge-opus at medium effort

**Files:**
- Modify: `plugins/dr-superpowers/agents/judge-opus.md:3` (`description:`), `:5` (`effort:`), `:14` (the "You run on" line)
- Modify: `plugins/dr-superpowers/README.md` (the sentence citing the 2026-09-23 Opus-versus-Fable replay)
- Test: `plugins/dr-superpowers/tests/fleet.test.sh` (unchanged; lines 90 to 91 accept `high` or `medium` for a judge)

**Interfaces:**
- Consumes: nothing.
- Produces: nothing.

**Items:** 2

**Implementer:** dr-superpowers:impl-sonnet-medium
**Evaluation:** files 1 - spec 0 - coupling 0 - risk 1 = 2

- [ ] **Step 1: Confirm the current effort**

Run: `grep -n 'high effort\|^effort:' plugins/dr-superpowers/agents/judge-opus.md`
Expected:

```
3:description: "Read-only verifier, ruling seat and approach ranker running Opus 5.5 at high effort. Dispatched by dr-superpowers as the task reviewer for totals 4 to 6 when Codex is not the reviewer, for every plan-review round Codex does not take, for every ruling including Header-amendment confirmations, every final whole-branch review and its two-list dedupe, risk-3 task reviews, approach ranking and distillation checks."
5:effort: high
14:You run on Opus 5.5 at high effort.
```

- [ ] **Step 2: Change the three lines and the README sentence**

```bash
python3 - <<'EOF'
p = 'plugins/dr-superpowers/agents/judge-opus.md'
s = open(p).read()
for old, new in (
    ('approach ranker running Opus 5.5 at high effort.', 'approach ranker running Opus 5.5 at medium effort.'),
    ('\neffort: high\n', '\neffort: medium\n'),
    ('\nYou run on Opus 5.5 at high effort.\n', '\nYou run on Opus 5.5 at medium effort.\n'),
):
    assert s.count(old) == 1, old
    s = s.replace(old, new)
open(p, 'w').write(s)
p = 'plugins/dr-superpowers/README.md'
s = open(p).read()
old = 'on 2026-09-23 Opus 5.5 matched or beat Fable 5.1'
assert s.count(old) == 1, old
s = s.replace(old, 'on 2026-09-23 Opus 5.5 at high effort matched or beat Fable 5.1')
open(p, 'w').write(s)
EOF
grep -n 'medium effort\|^effort:' plugins/dr-superpowers/agents/judge-opus.md
grep -c 'Opus 5.5 at high effort matched or beat' plugins/dr-superpowers/README.md
```

Expected: line 3 ends its first sentence with `at medium effort.`, line 5 reads `effort: medium`, line 14 reads `You run on Opus 5.5 at medium effort.`; then `1`.

- [ ] **Step 3: Run the fleet suite and every plugin suite**

Run: `timeout 300 bash plugins/dr-superpowers/tests/fleet.test.sh | grep 'judge-opus'; for t in plugins/dr-superpowers/tests/*.test.sh; do timeout 300 bash "$t" >/dev/null 2>&1 || echo "FAIL $t"; done; echo suites-done`
Expected: every `judge-opus` line starts with `ok`, including `ok   - judge-opus.md: effort is high or medium`; then only `suites-done`.

- [ ] **Step 4: Commit**

```bash
git add plugins/dr-superpowers/agents/judge-opus.md plugins/dr-superpowers/README.md
git commit -m "feat(superpowers): run judge-opus at medium effort" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 4: Release 1.24.0

**Files:**
- Modify: `plugins/dr-superpowers/.claude-plugin/plugin.json`, `plugins/dr-superpowers/.codex-plugin/plugin.json` (`"version"`)
- Test: `plugins/dr-superpowers/tests/review-route.test.sh:583-584`

**Interfaces:**
- Consumes: Tasks 1–3 committed.
- Produces: nothing.

**Items:** 2

**Implementer:** dr-superpowers:impl-sonnet-low
**Evaluation:** files 1 - spec 0 - coupling 0 - risk 0 = 1

- [ ] **Step 1: Pin the new version in the test**

```bash
python3 - <<'EOF'
p = 'plugins/dr-superpowers/tests/review-route.test.sh'
s = open(p).read()
for client in ('Claude', 'Codex'):
    old = f'present "the {client} manifest is 1.23.0"'
    assert s.count(old) == 1, old
    line = next(l for l in s.split('\n') if l.startswith(old))
    s = s.replace(line, line.replace('1.23.0', '1.24.0'))
open(p, 'w').write(s)
EOF
sed -n 583,584p plugins/dr-superpowers/tests/review-route.test.sh
```

Expected output:

```
present "the Claude manifest is 1.24.0" "$P/.claude-plugin/plugin.json" '"version": "1.24.0"'
present "the Codex manifest is 1.24.0" "$P/.codex-plugin/plugin.json" '"version": "1.24.0"'
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `timeout 300 bash plugins/dr-superpowers/tests/review-route.test.sh | grep '^FAIL'`
Expected: `FAIL - the Claude manifest is 1.24.0` and `FAIL - the Codex manifest is 1.24.0`.

- [ ] **Step 3: Bump both manifests**

```bash
sed -i 's/"version": "1.23.0"/"version": "1.24.0"/' plugins/dr-superpowers/.claude-plugin/plugin.json plugins/dr-superpowers/.codex-plugin/plugin.json
grep -n '"version"' plugins/dr-superpowers/.claude-plugin/plugin.json plugins/dr-superpowers/.codex-plugin/plugin.json
```

Expected: both files show `"version": "1.24.0"`.

- [ ] **Step 4: Run the plugin suites**

Run: `for t in plugins/dr-superpowers/tests/*.test.sh; do timeout 300 bash "$t" >/dev/null 2>&1 || echo "FAIL $t"; done; echo suites-done`
Expected: only `suites-done`.

- [ ] **Step 5: Run the repository checks**

```bash
RGBIN=$(mktemp -d)
printf '#!/usr/bin/env bash\nexec -a rg /root/.local/bin/claude "$@"\n' > "$RGBIN/rg" && chmod +x "$RGBIN/rg"
timeout 120 node scripts/validate-repository.mjs
PATH="$RGBIN:$PATH" timeout 300 node --test tests/*.test.mjs 2>&1 | grep -E '^ℹ (pass|fail)'
for p in . plugins/dr-status plugins/dr-superpowers plugins/dcc-darkraise-ui plugins/dcc-darkraise-win32ui; do timeout 120 claude plugin validate "$p" 2>&1 | tail -1; done
rm -rf "$RGBIN"
```

Expected: `Repository catalogs, manifests, versions, and bundled links are valid.`, `ℹ pass 22`, `ℹ fail 0`, and five `✔ Validation passed` lines. The `rg` wrapper exists because `rg` is a shell function on this machine (see Assumptions).

- [ ] **Step 6: Commit**

```bash
git add plugins/dr-superpowers/.claude-plugin/plugin.json plugins/dr-superpowers/.codex-plugin/plugin.json plugins/dr-superpowers/tests/review-route.test.sh
git commit -m "chore(superpowers): release 1.24.0" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```
