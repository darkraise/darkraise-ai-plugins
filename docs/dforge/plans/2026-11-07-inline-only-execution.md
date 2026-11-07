# Inline-only Execution Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: the skill the **Execution:** line names — dforge:subagent-driven-development for `subagent`, dforge:executing-plans for `inline`. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** dforge's session implements every plan task and writes every plan itself; subagent-driven development is deprecated but still runnable, and independent review seats stay.

**Architecture:** Delegation is computed in one place (`plan_delegated` in `scripts/lib/plan.sh`) and read by `plan-lint`, `task-brief`, `plan-revise` and the execution skills; narrowing it to executor rows and adding a risk-3 review marker and a `**Heavy:**` header line moves heavy tasks into the session. A `task-step start --inline` form gives the risk-3 review loop its step state without an implementer. Drafters and scouts are deleted; the prose of the planning, execution and routing skills follows.

**Tech Stack:** Bash scripts and suites, Node (`config/schema.mjs`, `scripts/test-all.mjs`), TypeScript cockpit hooks, Markdown skills.

**Spec:** `docs/dforge/specs/2026-11-07-inline-only-execution-design.md`

**Execution:** inline — `claude --model opus --effort high` — the spec removes implementer subagents; the session implements every task, the hardest at total 7

**Parallelism:** sequential — inline execution

**Task check:** `timeout 1500 node scripts/test-all.mjs` — the full suite last passed in 173 s

**Integration check:** `timeout 1500 node scripts/test-all.mjs`

**CI:** `.github/workflows/validate.yml .github/workflows/release.yml` — platforms: GNU Linux (self-hosted), uutils (ubuntu-latest), Windows Git Bash — local: `node scripts/validate-repository.mjs`; `node scripts/test-all.mjs`; `claude plugin validate .`; `claude plugin validate plugins/dforge`; `claude plugin test plugins/dforge` — uncovered: Windows Git Bash, uutils (ubuntu-latest)

**Plan review:** 2026-11-07 — dforge:judge-opus — executability 10 / coherence 11 / coverage 15 / assumptions 13 (round 1)

## Global Constraints

- English only; commits `<type>(<scope>): <subject>`, subject ≤ 50 chars, no AI attribution, author `Darkraise <quangtc94@gmail.com>`.
- Do not edit historical plans, specs, notes or registers other than this plan's own register.
- Preserve existing `DCC_*` variables and statusline user storage paths.
- Bound every test and CLI run with a timeout; call the Claude CLI as `/root/.local/bin/claude`; unset `CLAUDE_CONFIG_DIR` in suites that read budgets.
- Every new shell suite gets a weight in `scripts/test-shards.mjs` at most 80% of its limit (`tests/test-shards.test.mjs` enforces it).
- Windows Git Bash: a native program given a path built from `$PWD`, `$(pwd)` or `$TMPDIR` gets a POSIX form it cannot open — convert with `cygpath -m` (`dr_native_path`, `scripts/lib/native-path.sh`) and feed `jq` a file on stdin.
- Windows Git Bash: the same directory is `/c/Users/x` in the shell and `C:/Users/x` from a native tool — normalise both with `cygpath -m` or compare with `-ef`.
- Windows Git Bash: files a Windows tool wrote, and native program output, end lines with `\r` — pipe through `tr -d '\r'` before comparing or parsing.
- Windows Git Bash: `awk -v name=value` processes backslash escapes — pass the value in the environment and read `ENVIRON["NAME"]`.
- Windows Git Bash: Node's `import()` of an absolute `D:/x/y.mjs` fails — import with `import(pathToFileURL(path).href)`.
- uutils (ubuntu-latest): a lock built on `mkdir` failing does not exclude a second process — use `set -C` or `flock`.
- uutils (ubuntu-latest): `timeout` signals only the command it started — run it under `setsid` and signal the group.

## Contracts

- **C1 `plan_delegated FILE`** (scripts/lib/plan.sh): prints one `N<TAB>executor` line per task carrying an `**Executor:**` line, ascending; never a `heavy` row. `plan_heavy` is unchanged.
- **C2 risk-3 brief marker:** `task-brief PLAN N OUT` on a Claude-host inline plan writes `**Review:** per-task — risk 3` as line 2 of OUT when task N's highest risk is 3 and it carries no `**Executor:**` line. An executor task keeps `**Dispatch:** delegated — total <t>, risk <r>` as line 2 instead.
- **C3 heavy header line:** `task-brief --header PLAN OUT` on a Claude-host inline plan ends OUT with `**Heavy:** Task <n> (total <t>, risk <r>)[, Task <m> (total <t>, risk <r>)…]` for every task `plan_heavy` names, and with `**Dispatch:** delegated — Task <a> (executor)[, …]` before it when executor tasks exist. No `**Heavy:**` line when `plan_heavy` is empty.
- **C4 plan-lint messages (Claude host):** `WARN header: subagent execution is deprecated; inline is the default`; `ERROR header: inline execution needs --model opus (model <m>)` when the assignment row of the highest self-implemented total names an opus agent and the line names sonnet; the existing `ERROR header: inline execution needs --effort <e> or above (effort <x>)` with `<e>` the row's effort, raised to `high` when a self-implemented task has risk 3 or when any task carries an `**Executor:**` line. Self-implemented = scored and no `**Executor:**` line. The two majority-rule warnings are gone. On a Codex host the `inline execution needs every task at total <= 4 and risk < 3` ERROR is gone.
- **C5 plan-revise recommendation:** `recommend  execution=inline  model=<m>  effort=<e>  delegated=<k>/<n>`, where `<m>`/`<e>` is C4's floor and `<k>` counts executor tasks only.
- **C6 `task-step start PLAN N --inline`:** writes `task-<N>-step.json` (as `start` does), writes the ledger's identity line `# SDD ledger — plan: <plan>` when the ledger does not exist yet, writes no `task-<N>-dispatch.md` and no task line, prints `task <N>: briefed <brief>, base <sha7>; inline, no dispatch file written` then `seat: inline`. `--inline` with `--wave`, or on a task carrying an `**Executor:**` line, is a usage error (exit 2). An executor task whose executor is unavailable or hands back starts with plain `task-step start` (which already writes state and no assigned line for an executor task) and joins the session review loop at its review step.
- **C7 ledger grammar:** `Task <N>: implementer inline (assigned; base <sha7>)`; executor fallback `Task <N>: implementer inline (assigned; base <sha7>; executor <id> unavailable - <reason>)`; fix-round last slot `session`; handback slot `HANDBACK to inline`; a task at its cap goes to the `breaker` ruling kind.
- **C8 settings:** `dforge-config get executionStrategy` prints `sequential` with no settings.
- **C9 acceptance suite:** `plugins/dforge/tests/inline-only.acceptance.test.sh`, created by Task 1 with helpers `check NAME GOT WANT`, `present NAME FILE NEEDLE`, `absent NAME FILE NEEDLE`, `has NAME HAYSTACK NEEDLE`, `lacks NAME HAYSTACK NEEDLE`, `io_plan EXECUTION "f s c r" "f s c r" [EXECUTOR]` (a two-task Claude plan on stdout; EXECUTOR, when given, is Task 2's `**Executor:**` value), `impl_for TOTAL` (the assignment table's agent), `lint FILE` (runs plan-lint, sets `out` and `status`), variables `P` (plugin root), `S` (`$P/scripts`), `TMP` (the suite's git repository and cwd), `INLINE_OPUS` (an inline opus/high Execution value). Each later task appends one block headed `# --- Task <N> ---` above the final summary block, which stays last.
- **C10 Process line text:** brainstorming and using-dforge state `Process: <spike|bounded|architectural> — <trigger | no trigger>` and `Process: architectural, depth <d> — <triggers>`.
- **C11 deprecation text:** subagent-driven-development's `description:` starts `Deprecated — use only when a plan's Execution line names subagent or your human partner asks for subagent mode`.

## Assumptions (evidence)

- Heavy tasks in this plan are implemented by the session, as the spec requires; the installed dforge 4.12.0 still marks them delegated, so the executing session writes `Task <N>: implementer inline (assigned; base <sha7>)` for each and logs `Ruling: heavy task self-implemented — owner's spec — none` once. The Execution line therefore disputes the installed majority rule; plan-lint's WARN about it is expected (installed `scripts/plan-lint` R5, read 2026-11-07).
- The branch was rebased onto origin/main on 2026-11-07, whose dforge is 4.12.0 (`git show origin/main:plugins/dforge/.claude-plugin/plugin.json`, origin/main committed 2026-11-05) and already contains fast mode (PR #42); the release bump is therefore 4.13.0.
- The full suite passes in about 173 s locally (`.dforge/suites.tsv`, last row for `bash -c node\ scripts/test-all.mjs`, exit 0).
- `validate-repository.mjs` errors on any `dforge:<name>` reference with no skill or agent file (scripts/validate-repository.mjs:165-171), so deleting the drafter and scout agents fails validation until every reference is gone; Task 5 and Task 6 each remove their references in the same commit.
- `task-step review` exits 6 without step state (scripts/task-step:838) and fills the reviewer prompt with `<workspace>/task-<N>-report.md` (scripts/task-step:889); C6 supplies the state and the session writes the report.
- The heavy-task budget margin stays at `CTX_TASK_MARGIN=140000` (spec Decisions); Task 1's Step 3 takes the before/after `scripts/context-size` reading.
- Plan review round 1 scored executability 10, coherence 11 and assumptions 13 (borderline): its 1 Critical and 9 Important findings were fixed in the plan (byte-safe prefix checks, a ledger identity line, pin updates moved to the task that breaks them, non-vacuous needles, the executor-fallback entry, `clear --phase` kept for old ledgers, the measurement step, the 4.13.0 bump); depth standard caps review at one round, so no second round runs.
- unverified — Task 3 verifies it: `task-step review` routes a seat on a fixture plan with the codex gate file set to `review:false` and no further environment.

## Task index

1. Delegate executor tasks only
2. Lint and revise the inline floor
3. Start a session review loop
4. Default the strategy to sequential
5. Remove plan drafters
6. Remove approach scouts
7. Rewrite the execution skills
8. Rewrite the executor and handoff prose
9. Rewrite the planning prose
10. Deprecate subagent mode in routing
11. Update descriptions and release

---

### Task 1: Delegate executor tasks only

**Files:**
- Modify: `plugins/dforge/scripts/lib/plan.sh` (`plan_delegated`, and its comment block)
- Modify: `plugins/dforge/scripts/task-brief` (the mixed-mode block that computes `delegated`, the `--header` branch, the per-task second-line insertion)
- Create: `plugins/dforge/tests/inline-only.acceptance.test.sh`
- Modify: `plugins/dforge/tests/plan-lib.test.sh`, `plugins/dforge/tests/inline-mode.test.sh`, `plugins/dforge/tests/plan-lint.test.sh`, `plugins/dforge/tests/plan-revise.test.sh` (pins that `plan_delegated` alone breaks)
- Modify: `scripts/test-shards.mjs` (weight entry)

**Interfaces:**
- Consumes: none
- Produces: C1, C2, C3, C9

**Implementer:** dforge:impl-opus-high
**Evaluation:** files 1 - spec 2 - coupling 2 - risk 2 = 7

- [ ] **Step 1: Write the failing test**

Create `plugins/dforge/tests/inline-only.acceptance.test.sh`:

```bash
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
io_plan "$INLINE_OPUS" "0 2 1 3" "1 2 2 1" > risk3.md
bash "$S/task-brief" risk3.md 1 "$TMP/r1.md" > /dev/null 2>&1
check "A5: a risk-3 brief's second line is the review marker" "$(sed -n 2p "$TMP/r1.md")" "**Review:** per-task — risk 3"
bash "$S/task-brief" risk3.md 2 "$TMP/r2.md" > /dev/null 2>&1
check "A5: a total-6 risk-1 brief has no review marker" "$(grep -c '^\*\*Review:\*\*' "$TMP/r2.md")" "0"
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
```

Add `'inline-only.acceptance.test.sh': 30,` to `windowsSeconds` in `scripts/test-shards.mjs`, in sorted position.

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 300 bash plugins/dforge/tests/inline-only.acceptance.test.sh`
Expected: FAIL on "A4: a heavy task is not delegated" (got `1	heavy`), the A5 marker check, the A6 exec.md check (got `1 heavy|2 executor|`) and the A16 Heavy line.

- [ ] **Step 3: Implement**

0. Before the first edit, run `bash <plugin-root>/scripts/context-size` and note the number; after Step 4 passes, run it again. Put both readings in this task's complete line as `discovered: heavy-task context cost <before>k -> <after>k (margin 140k)`. This is the spec's riskiest-assumption measurement.
1. `plan_delegated` (scripts/lib/plan.sh): drop the heavy rule; print only `N<TAB>executor` rows for tasks `plan_executors` names, skipping unscored tasks as today. Rewrite its comment to C1. Keep `plan_heavy` as is.
2. `scripts/task-brief`: the mixed-mode block stays gated on a Claude-host inline plan. Per task: when the task is in `plan_delegated`, insert `**Dispatch:** delegated — total <t>, risk <r>` as line 2 (unchanged); otherwise, when the task's highest risk is 3, insert `**Review:** per-task — risk 3` as line 2. `--header`: append the `**Dispatch:** delegated — …` line for executor rows as today, then, when `plan_heavy` is non-empty, `**Heavy:** Task <n> (total <t>, risk <r>), …` from `plan_scores` (highest total and risk per task, parts folded as `plan_scores` already does). Update the mixed-mode comment.
3. Update existing pins that assert heavy delegation: `tests/plan-lib.test.sh` (the `plan_delegated` cases expecting `heavy` rows — "heavy tasks beside a total-4 task", "the scores fixture", the executor-kind case asserting `heavy` for Task 4 — now expect no heavy rows; rename the section comment to "executor tasks only"); `tests/inline-mode.test.sh` (the brief cases "a heavy task's second line is the Dispatch line", "a split task carries its highest total and risk", "the header lists the delegated tasks with reasons" — a heavy task's brief now has no Dispatch line, a risk-3 split task's line 2 is the review marker, the header ends with the `**Heavy:**` line). Keep every executor-row assertion. Also update the pins that `plan_delegated` alone breaks in `tests/plan-lint.test.sh` ("inline names the delegated task", "risk 3 is delegated", "a split task is heavy when one part is" now expect no `(heavy)` NOTE; "a heavy majority on inline warns" now `lacks` that WARN, since `heavy_count` reads `plan_delegated`) and in `tests/plan-revise.test.sh` (delegated counts now count executor tasks only). Leave every other plan-lint and plan-revise pin to Task 2.

- [ ] **Step 4: Run test to verify it passes**

Run: `timeout 300 bash plugins/dforge/tests/inline-only.acceptance.test.sh && timeout 300 bash plugins/dforge/tests/plan-lib.test.sh && timeout 600 bash plugins/dforge/tests/inline-mode.test.sh && timeout 1200 bash plugins/dforge/tests/plan-lint.test.sh one && timeout 1200 bash plugins/dforge/tests/plan-lint.test.sh two && timeout 900 bash plugins/dforge/tests/plan-revise.test.sh && timeout 120 node --test tests/test-shards.test.mjs`
Expected: PASS, `0 failed` in each.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/scripts/lib/plan.sh plugins/dforge/scripts/task-brief plugins/dforge/tests scripts/test-shards.mjs
git commit -m "feat(dforge): delegate only executor tasks"
```

### Task 2: Lint and revise the inline floor

**Files:**
- Modify: `plugins/dforge/scripts/plan-lint` (the R5 execution-mode block)
- Modify: `plugins/dforge/scripts/plan-revise` (the `recommend` computation)
- Modify: `plugins/dforge/tests/plan-lint.test.sh`, `plugins/dforge/tests/plan-revise.test.sh`, `plugins/dforge/tests/inline-only.acceptance.test.sh`

**Interfaces:**
- Consumes: C1, C9
- Produces: C4, C5

**Implementer:** dforge:impl-opus-high
**Evaluation:** files 1 - spec 2 - coupling 1 - risk 2 = 6

- [ ] **Step 1: Write the failing test**

Append above `# --- summary ---` in `inline-only.acceptance.test.sh`:

```bash
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
```

Codex-host A12 lives in `plan-lint.test.sh` next to the existing Codex-inline case, which uses its `codex_plan` fixture: replace the assertion "a Codex-host inline plan keeps the old eligibility error" with

```bash
lacks "A12: a Codex-host inline plan with a heavy task has no eligibility error" "$out" "inline execution needs every task"
```

and add, after the existing "a Codex inline pair below the highest score errors" case:

```bash
codex_plan | sed -E 's#^\*\*Execution:\*\* subagent — codex gpt-6.1-sol / high#**Execution:** inline — codex gpt-6-astra / xhigh#; s/risk=0; weighted routing score=3/risk=3; weighted routing score=9/' > codex-inline-heavy-fit.md
lint codex-inline-heavy-fit.md
lacks "A12: a heavy Codex inline plan at its rank lints without error" "$out" "ERROR header: inline"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 300 bash plugins/dforge/tests/inline-only.acceptance.test.sh; timeout 1200 bash plugins/dforge/tests/plan-lint.test.sh one`
Expected: FAIL on A2, A3, A15, A9 and A12. A1 already passes after Task 1 (no heavy rows reach `heavy_count`); it stays as a regression pin.

- [ ] **Step 3: Implement**

1. plan-lint R5, Claude branch: delete both majority-rule warnings (`Execution line is inline but …` and `Execution line is subagent but only …`) and the `heavy_count` they used. On a subagent line, keep the `sonnet / high` WARN and add C4's deprecation WARN. On an inline line: `self_max` is the highest total among scored tasks not in `plan_delegated` (now executor-only, so heavy tasks count); look up its assignment row; the model floor is `opus` when the row's agent is `impl-opus-*`, else `sonnet`; the effort floor is the row's effort, raised to `high` when any self-implemented task has risk 3 (from `plan_scores`), and to `high` when `plan_delegated` is non-empty (executor review loop, unchanged rule). Emit C4's model ERROR when the floor is opus and the family is sonnet; keep the existing family ERROR for any other model; keep the effort ERROR text. Keep the `NOTE header: delegated:` line for executor rows. Rewrite the R5 comment.
2. plan-lint R5, Codex branch: delete the `r5_bad` ERROR (`inline execution needs every task at total <= 4 and risk < 3`) and whatever computes `r5_bad` if nothing else reads it. Keep the rank checks.
3. plan-revise: compute the recommendation with the same floor as step 1 (model from the assignment row of the highest self-implemented total, effort raised for risk 3 or executor rows), `execution=inline` always on a Claude plan, `delegated=` the executor-row count over the task count. Replace the hardcoded `rec_model=sonnet`.
4. Update the remaining pins in `plan-lint.test.sh` and `plan-revise.test.sh` that assert the removed warnings, the old Codex ERROR or the old floors: "a light plan on subagent warns" now expects the deprecation WARN; "total-4 tasks never count toward subagent mode" and "sequential: the majority rule still warns" become `lacks` of the removed text; the clean-plan summary count changes by the deprecation WARN replacing the majority WARN (still `0 errors, 2 warnings`). Run the suites and fix every remaining pin that asserted heavy delegation, keeping the case and changing its expectation.

- [ ] **Step 4: Run test to verify it passes**

Run: `timeout 300 bash plugins/dforge/tests/inline-only.acceptance.test.sh && timeout 1200 bash plugins/dforge/tests/plan-lint.test.sh one && timeout 1200 bash plugins/dforge/tests/plan-lint.test.sh two && timeout 900 bash plugins/dforge/tests/plan-revise.test.sh`
Expected: PASS, `0 failed` in each.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/scripts/plan-lint plugins/dforge/scripts/plan-revise plugins/dforge/tests/plan-lint.test.sh plugins/dforge/tests/plan-revise.test.sh plugins/dforge/tests/inline-only.acceptance.test.sh
git commit -m "feat(dforge): lint inline plans by their hardest task"
```

### Task 3: Start a session review loop

**Files:**
- Modify: `plugins/dforge/scripts/task-step` (`usage`, the option parser, `do_start`, the header comment)
- Modify: `plugins/dforge/tests/inline-only.acceptance.test.sh`

**Interfaces:**
- Consumes: C2, C9
- Produces: C6

**Implementer:** dforge:impl-opus-high
**Evaluation:** files 0 - spec 2 - coupling 2 - risk 2 = 6

- [ ] **Step 1: Write the failing test**

Append above `# --- summary ---`:

```bash
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 300 bash plugins/dforge/tests/inline-only.acceptance.test.sh`
Expected: FAIL on "A14: start --inline exits 0" (usage error, exit 2).

- [ ] **Step 3: Implement**

1. Parser: accept `--inline` for `start` only (any other subcommand is a usage error), set `inline=1`; `--inline` together with `--wave` is a usage error. Add it to `usage` and the header comment's Usage line.
2. `do_start` with `inline=1`: compute base, brief and state exactly as today; call `ledger_init` (identity line only); write no agent-named assigned line, no dispatch file; print `task <N>: briefed <brief>, base <sha7>; inline, no dispatch file written`, then `seat: inline`, then the state line and budget line as today. An executor task given `--inline` is a usage error (the executor path owns it).
3. If the Step 1 review case fails for environment reasons (a missing gate file or suite record), mirror the setup `tests/task-step.test.sh` uses for its review cases inside this block and record the difference in the ledger's `discovered:` field; do not change `do_review`.

- [ ] **Step 4: Run test to verify it passes**

Run: `timeout 300 bash plugins/dforge/tests/inline-only.acceptance.test.sh && timeout 900 bash plugins/dforge/tests/task-step.test.sh`
Expected: PASS, `0 failed`.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/scripts/task-step plugins/dforge/tests/inline-only.acceptance.test.sh
git commit -m "feat(dforge): start a task review without a dispatch"
```

### Task 4: Default the strategy to sequential

**Files:**
- Modify: `plugins/dforge/config/schema.mjs` (`executionStrategy`, `executionMode`)
- Modify: `plugins/dforge/hooks/cockpit/lib.ts` (the seat nudge that names the `**Implementer:**` agent for implementation)
- Modify: `plugins/dforge/tests/inline-only.acceptance.test.sh`, and whichever of `plugins/dforge/tests/dforge-config.test.sh` / `plugins/dforge/tests/cockpit.test.ts` pin the old default or nudge text

**Interfaces:**
- Consumes: C9
- Produces: C8

**Implementer:** dforge:impl-sonnet-high
**Evaluation:** files 1 - spec 2 - coupling 1 - risk 1 = 5

- [ ] **Step 1: Write the failing test**

Append above `# --- summary ---`:

```bash
# --- Task 4 ---
check "A7: executionStrategy defaults to sequential" "$(bash "$S/dforge-config" get executionStrategy | tr -d '\r')" "sequential"
check "A7: the workflow line is empty at defaults" "$(bash "$S/dforge-config" workflow | tr -d '\r')" ""
present "A7: the schema says parallel needs subagent mode" "$P/config/schema.mjs" "only with a subagent Execution line"
absent "cockpit nudge: no Implementer agent for implementation" "$P/hooks/cockpit/lib.ts" "for implementation"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 300 bash plugins/dforge/tests/inline-only.acceptance.test.sh`
Expected: FAIL on "A7: executionStrategy defaults to sequential" (got `parallel`).

- [ ] **Step 3: Implement**

1. `executionStrategy`: `default: 'sequential'`; description: "How a plan executes. sequential, the default, runs one task at a time. parallel and ask take effect only with a subagent Execution line (executionMode=subagent, deprecated); an inline plan is always sequential."  — the string must contain `only with a subagent Execution line`.
2. `executionMode`: description "Who implements plan tasks. auto and inline: the session implements every task, executor tasks excepted. subagent (deprecated) dispatches an implementer per task."
3. `hooks/cockpit/lib.ts`: reword the seat nudge so it names the judge seats and the plan's Execution line, not the task's `**Implementer:**` agent "for implementation". Update the matching expectation in `tests/cockpit.test.ts` if one pins the old text.
4. Update any `dforge-config.test.sh` pin of the `parallel` default.

- [ ] **Step 4: Run test to verify it passes**

Run: `timeout 300 bash plugins/dforge/tests/inline-only.acceptance.test.sh && timeout 600 bash plugins/dforge/tests/dforge-config.test.sh && { ! command -v tsc >/dev/null || timeout 300 tsc --noEmit -p plugins/dforge; }`
Expected: PASS; tsc, when on PATH, prints nothing (test-all skips it otherwise).

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/config/schema.mjs plugins/dforge/hooks/cockpit/lib.ts plugins/dforge/tests
git commit -m "feat(dforge): default execution to sequential"
```

### Task 5: Remove plan drafters

**Files:**
- Delete: `plugins/dforge/agents/drafter-sonnet.md`, `plugins/dforge/scripts/draft-pack`, `plugins/dforge/tests/draft-pack.test.sh`, `plugins/dforge/skills/writing-plans/references/drafter-prompt.md`
- Modify: `plugins/dforge/skills/writing-plans/SKILL.md` (§Drafting the tasks)
- Modify: `scripts/test-shards.mjs` (drop the `draft-pack.test.sh` weight)
- Modify: `plugins/dforge/tests/fleet.test.sh`, `plugins/dforge/tests/process-roles.test.sh`, `plugins/dforge/tests/typed-seats-and-drafting.acceptance.sh`, `plugins/dforge/tests/typed-seats-and-drafting.acceptance.test.ts`, `plugins/dforge/tests/faster-plans.acceptance.test.sh`, `plugins/dforge/tests/inline-only.acceptance.test.sh`

**Interfaces:**
- Consumes: C9
- Produces: none

**Implementer:** dforge:impl-sonnet-high
**Evaluation:** files 2 - spec 2 - coupling 1 - risk 0 = 5

- [ ] **Step 1: Write the failing test**

Append above `# --- summary ---`:

```bash
# --- Task 5 ---
check "A8: no drafter agent" "$([ -e "$P/agents/drafter-sonnet.md" ] && echo yes || echo no)" "no"
check "A8: no draft-pack" "$([ -e "$S/draft-pack" ] && echo yes || echo no)" "no"
check "A8: no skill or reference names the drafter" \
  "$(grep -rlF 'drafter-sonnet' "$P/skills" "$P/reference" | wc -l | tr -d ' ')" "0"
present "writing-plans drafts every task in the session" "$P/skills/writing-plans/SKILL.md" "Draft every task in the session, at any plan size."
```

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 300 bash plugins/dforge/tests/inline-only.acceptance.test.sh`
Expected: FAIL on the three A8 checks and the writing-plans sentence.

- [ ] **Step 3: Implement**

1. Replace §Drafting the tasks in writing-plans with: "Draft every task in the session, at any plan size. You have already read the code the plan changes; a drafter would read it again from nothing." Remove the drafter bullets (Contracts settle what slices share, Join without reading, Codex host).
2. Delete the four files. Remove `'draft-pack.test.sh'` from `windowsSeconds`.
3. Remove drafter cases from the suites: `fleet.test.sh` (`drafter-sonnet` from `EXPECTED`, `DRAFTER_TOOLS`, the `drafter-*)` branch, the class list text and the header comment's drafter sentence); `process-roles.test.sh` (the `DPR` variable and every drafter-prompt and drafting check); `typed-seats-and-drafting.acceptance.sh` and `.test.ts` (the drafting checks; keep the typed-seat checks); `faster-plans.acceptance.test.sh` (drafter and draft-pack checks). Search `rg -n 'drafter|draft-pack|drafts/' plugins/dforge scripts` and clear every hit outside historical docs.

- [ ] **Step 4: Run test to verify it passes**

Run: `timeout 300 bash plugins/dforge/tests/inline-only.acceptance.test.sh && timeout 300 bash plugins/dforge/tests/fleet.test.sh && timeout 300 bash plugins/dforge/tests/process-roles.test.sh && timeout 600 bash plugins/dforge/tests/typed-seats-and-drafting.acceptance.sh && timeout 600 bash plugins/dforge/tests/faster-plans.acceptance.test.sh && timeout 120 node scripts/validate-repository.mjs && timeout 120 node --test tests/test-shards.test.mjs && timeout 240 /root/.local/bin/claude plugin test plugins/dforge`
Expected: PASS; validate-repository reports no unresolved `dforge:` reference; `claude plugin test` runs the edited `.test.ts`.

- [ ] **Step 5: Commit**

```bash
git add -A plugins/dforge scripts/test-shards.mjs
git commit -m "refactor(dforge): remove plan drafters"
```

### Task 6: Remove approach scouts

**Files:**
- Delete: `plugins/dforge/agents/scout-sonnet.md`
- Modify: `plugins/dforge/skills/selecting-approaches/SKILL.md` (and its `references/` where best-of-3 appears)
- Modify: `plugins/dforge/scripts/select-native-tier.sh` (the `scout` role), `plugins/dforge/reference/codex-routing.json` (`role_floors.scout`), `plugins/dforge/reference/native-codex.md` (scout clauses), `plugins/dforge/reference/ladder.md` (scout mention)
- Modify: `plugins/dforge/tests/fleet.test.sh`, `plugins/dforge/tests/native-routing.test.sh`, `plugins/dforge/tests/ladder.test.sh`, `plugins/dforge/tests/speed-and-cost.acceptance.test.sh`, `plugins/dforge/tests/speed-and-cost-followups.acceptance.test.sh`, `plugins/dforge/tests/inline-only.acceptance.test.sh`

**Interfaces:**
- Consumes: C9
- Produces: none

**Implementer:** dforge:impl-sonnet-high
**Evaluation:** files 2 - spec 2 - coupling 1 - risk 0 = 5

- [ ] **Step 1: Write the failing test**

Append above `# --- summary ---`:

```bash
# --- Task 6 ---
check "A8: no scout agent" "$([ -e "$P/agents/scout-sonnet.md" ] && echo yes || echo no)" "no"
check "A8: no skill or reference names the scout" \
  "$(grep -rlF 'scout-sonnet' "$P/skills" "$P/reference" | wc -l | tr -d ' ')" "0"
present "selecting-approaches has two modes" "$P/skills/selecting-approaches/SKILL.md" "Two modes: \`inline\` and \`advisor\`."
check "codex routing has no scout floor" "$(jq -r '.role_floors.scout // "none"' < "$P/reference/codex-routing.json" | tr -d '\r')" "none"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 300 bash plugins/dforge/tests/inline-only.acceptance.test.sh`
Expected: FAIL on the Task 6 checks.

- [ ] **Step 3: Implement**

1. selecting-approaches: the gate table keeps `inline` (0 calls) and `advisor` (one judge scoring your approach); state "Two modes: `inline` and `advisor`." in its overview. Every condition that chose `best-of-3` chooses `advisor`. Remove the Draft/Rank procedure and every scout dispatch. Keep the `**Approach:**` grammar note that an existing `best-of-3` line is a record of a past decision (plan-lint's `inline|advisor|best-of-3` grammar stays).
2. Delete `agents/scout-sonnet.md`; drop the `scout` role from `select-native-tier.sh`, `role_floors.scout` from codex-routing.json, and native-codex.md's scout clauses (the drafting role list, the scout floor, the best-of-3 dispatch text).
3. Update suites: `fleet.test.sh` (`scout-sonnet` from `EXPECTED`, `SCOUT_TOOLS` and the scout branch; judges keep their branch); `native-routing.test.sh` (the scout case); `ladder.test.sh` (keep the off-ladder checks, matching `judge-` only); the speed-and-cost acceptance suites' best-of-3 pins. Clear every `rg -n 'scout' plugins/dforge` hit outside historical docs.

- [ ] **Step 4: Run test to verify it passes**

Run: `timeout 300 bash plugins/dforge/tests/inline-only.acceptance.test.sh && timeout 300 bash plugins/dforge/tests/fleet.test.sh && timeout 600 bash plugins/dforge/tests/native-routing.test.sh && timeout 300 bash plugins/dforge/tests/ladder.test.sh && timeout 600 bash plugins/dforge/tests/speed-and-cost.acceptance.test.sh && timeout 1200 bash plugins/dforge/tests/speed-and-cost-followups.acceptance.test.sh && timeout 120 node scripts/validate-repository.mjs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A plugins/dforge
git commit -m "refactor(dforge): remove approach scouts"
```

### Task 7: Rewrite the execution skills

**Files:**
- Modify: `plugins/dforge/skills/executing-plans/SKILL.md` (Overview "Why this mode", "Delegated tasks", "Why no per-task review", the fix-cap text, §Switching to subagent mode)
- Delete: `plugins/dforge/skills/executing-plans/references/switching.md`
- Modify: `plugins/dforge/skills/executing-plans/references/recovery.md`, `references/ruling-seat.md`, `references/setup.md`
- Modify: `plugins/dforge/reference/delegated-task.md` (new section for the session loop)
- Modify: `plugins/dforge/reference/auto-run.md` (the inline-to-subagent switch bullet), `plugins/dforge/scripts/auto-run` (the `clear --phase` usage comment)
- Modify: `plugins/dforge/tests/inline-mode.test.sh`, `plugins/dforge/tests/auto-run-skills.test.sh`, `plugins/dforge/tests/inline-only.acceptance.test.sh`

**Interfaces:**
- Consumes: C2, C3, C6, C7, C9
- Produces: C7 (documented)

**Implementer:** dforge:impl-opus-high
**Evaluation:** files 1 - spec 2 - coupling 2 - risk 2 = 7

- [ ] **Step 1: Write the failing test**

Append above `# --- summary ---`:

```bash
# --- Task 7 ---
SKILL_VIEW_DIR="$TMP/views"; . "$P/tests/skill-view.sh"
EP=$(skill_view executing-plans)
DT="$P/reference/delegated-task.md"
present "A17: a task at fix round 3/3 goes to the breaker" "$EP" 'After `fix round 3/3`, the task goes to the ruling seat as a `breaker` item.'
absent "A17: no switch to subagent mode" "$EP" "Switching to subagent mode"
check "A17: switching.md is gone" "$([ -e "$P/skills/executing-plans/references/switching.md" ] && echo yes || echo no)" "no"
present "the session implements heavy tasks" "$EP" "You implement every task that carries no \`**Executor:**\` line, heavy tasks included."
present "risk-3 tasks run the session loop" "$EP" '`**Review:** per-task — risk 3`'
present "setup keys preflight on the Heavy line" "$P/skills/executing-plans/references/setup.md" 'The `preflight` item runs when `plan-header.md` ends with a `**Heavy:**` line.'
present "delegated-task documents the session loop" "$DT" "## The session review loop"
present "the session loop starts inline" "$DT" "task-step start PLAN_FILE <N> --inline"
present "the session loop's fix slot" "$DT" '; session)'
present "recovery resumes the session loop" "$P/skills/executing-plans/references/recovery.md" 'after an `implementer inline` assigned line'
present "the breaker row covers any task at its cap" "$P/skills/executing-plans/references/ruling-seat.md" "A task's findings or verifications still open at its cap"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 300 bash plugins/dforge/tests/inline-only.acceptance.test.sh`
Expected: FAIL on every Task 7 check.

- [ ] **Step 3: Implement**

1. executing-plans SKILL.md: "Why this mode" becomes: every plan runs inline; the Execution line's pair covers the hardest task; "You implement every task that carries no `**Executor:**` line, heavy tasks included." "Delegated tasks" covers executor tasks only. Add a paragraph for a brief whose line 2 is `**Review:** per-task — risk 3`: run delegated-task.md §The session review loop. "Why no per-task review" names risk 3 as the exception. The fix cap of 3 ends with the exact sentence "After `fix round 3/3`, the task goes to the ruling seat as a `breaker` item." (in an auto run, the pending list). Remove §Switching to subagent mode and every pointer to it; delete `references/switching.md`.
2. setup.md: key the `preflight` item on the header's `**Heavy:**` line (C3) instead of a `(heavy)` Dispatch entry, with the exact sentence "The `preflight` item runs when `plan-header.md` ends with a `**Heavy:**` line." 
3. recovery.md: add the row "`fix round R/2` after an `implementer inline` assigned line → resume the session loop at round R+1; `2/2` → the breaker"; keep the rows that read `escalated inline -> subagent` for old ledgers.
4. ruling-seat.md: the `breaker` row reads "A task's findings or verifications still open at its cap".
5. delegated-task.md: add `## The session review loop` with the five steps of the spec's §2 (start with `task-step start PLAN_FILE <N> --inline`, the session writes `Task <N>: implementer inline (assigned; base <sha7>)`, writes `<workspace>/task-<N>-report.md` in the implementer report shape, `task-step review`, up to 2 fix rounds whose line ends `; session)`, the reviewed complete line or the breaker at `2/2`), the executor-fallback entry (an executor task whose executor is unavailable or hands back starts with plain `task-step start` and joins the loop at `task-step review`), and the Codex-host form (§The steps by hand with a native judge at Astra high or above). Scope "fresh dispatch on the successor rung" and "no controller fixes" to dispatched implementers.
6. `scripts/auto-run clear --phase` stays only for a ledger already holding `escalated inline -> subagent` (a run started before this change): reword auto-run.md's bullet that way and the usage comment in `scripts/auto-run`; update `auto-run-skills.test.sh`'s pins of that bullet and of switching.md (they pin `clear --phase` as the mode switch) to the new wording, keeping its one-`clear --phase` count.
7. Update `inline-mode.test.sh` pins of the removed text (the switching section, heavy delegation wording, "names both delegation reasons" now names only the executor reason) so each case asserts the new text.

- [ ] **Step 4: Run test to verify it passes**

Run: `timeout 300 bash plugins/dforge/tests/inline-only.acceptance.test.sh && timeout 600 bash plugins/dforge/tests/inline-mode.test.sh && timeout 700 bash plugins/dforge/tests/next-step.test.sh && timeout 600 bash plugins/dforge/tests/auto-run-skills.test.sh && timeout 700 bash plugins/dforge/tests/auto-run.test.sh`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A plugins/dforge
git commit -m "docs(dforge): implement every plan task in session"
```

### Task 8: Rewrite the executor and handoff prose

**Files:**
- Modify: `plugins/dforge/reference/executor-lane.md` (unavailable-executor fallback, handback, troubleshooting rows)
- Modify: `plugins/dforge/skills/handoff/SKILL.md` (the inline-to-subagent hard stop), `plugins/dforge/reference/session-budget.md` (the hard-stop row), `plugins/dforge/skills/resume-execution/SKILL.md`
- Modify: `plugins/dforge/tests/inline-only.acceptance.test.sh`, `plugins/dforge/tests/inline-mode.test.sh`, and the suites that pin the removed lines (`tests/executor-recovery.test.sh`, `tests/lanes.test.sh`, `tests/final-phase.test.sh` as `rg` finds them)

**Interfaces:**
- Consumes: C7, C9
- Produces: none

**Implementer:** dforge:impl-sonnet-high
**Evaluation:** files 1 - spec 2 - coupling 1 - risk 1 = 5

- [ ] **Step 1: Write the failing test**

Append above `# --- summary ---`:

```bash
# --- Task 8 ---
EL="$P/reference/executor-lane.md"
present "A19: the unavailable line names the session" "$EL" 'implementer inline (assigned; base <sha7>; executor <id> unavailable - <reason>)'
present "A19: a handback goes to the session" "$EL" 'HANDBACK to inline'
absent "A19: no handback to an implementer agent" "$EL" 'HANDBACK to impl-'
absent "handoff has no subagent-mode stop" "$P/skills/handoff/SKILL.md" "inline to subagent mode"
absent "session-budget has no subagent-mode stop" "$P/reference/session-budget.md" "switches from inline to subagent mode"
allow="$P/skills/executing-plans/references/recovery.md|$P/skills/resume-execution/SKILL.md|$P/reference/auto-run.md|$P/skills/subagent-driven-development/"
check "A11: only the allowlist names the escalation line" \
  "$(grep -rlF 'escalated inline -> subagent' "$P/skills" "$P/reference" | grep -vE "^($allow)" | wc -l | tr -d ' ')" "0"
check "A11: no reference names switching to subagent mode" \
  "$(grep -rliF 'switching to subagent mode' "$P/skills" "$P/reference" | grep -v "$P/skills/subagent-driven-development/" | wc -l | tr -d ' ')" "0"
. "$S/lib/plan.sh"
printf 'Task 1: escalated inline -> subagent — fix cap\n' > "$TMP/old-ledger.md"
check "A11: an old escalation line still parses" "$(ledger_left_inline "$TMP/old-ledger.md")" "1"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 300 bash plugins/dforge/tests/inline-only.acceptance.test.sh`
Expected: FAIL on the A19 checks, the two stop checks and the A11 allowlist check.

- [ ] **Step 3: Implement**

1. executor-lane.md: when an executor is unavailable, refused, or past its lane breaker, the session implements the task; the ledger line is C7's `implementer inline (assigned; base <sha7>; executor <id> unavailable - <reason>)`; a mid-loop handback writes `HANDBACK to inline` and the session finishes the task under delegated-task.md §The session review loop, entering it at `task-step review` after the plain `task-step start` the executor path already ran (never `--inline`, which refuses an executor task). Replace every `impl-sonnet-low` example in fallback lines and the troubleshooting rows that say "Dispatch the `**Implementer:**` agent" with the session. Keep "Never fall back silently".
2. handoff SKILL.md: remove "or a switch from inline to subagent mode" from the description and the hard-stop list and its explanatory sentences. session-budget.md: remove the "a plan switches from inline to subagent mode" hard stop.
3. resume-execution: keep reading an `escalated inline -> subagent` line for an old ledger; state that new ledgers never write it.
4. Remove every other mention of the escalation line or "switching to subagent mode" outside the allowlist (the escalation grammar line in executing-plans' ledger section included), and update suites that pinned the old fallback lines or that grammar line (`inline-mode.test.sh`).

- [ ] **Step 4: Run test to verify it passes**

Run: `timeout 300 bash plugins/dforge/tests/inline-only.acceptance.test.sh && timeout 600 bash plugins/dforge/tests/executor-recovery.test.sh && timeout 600 bash plugins/dforge/tests/lanes.test.sh && timeout 600 bash plugins/dforge/tests/final-phase.test.sh && timeout 600 bash plugins/dforge/tests/inline-mode.test.sh`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A plugins/dforge
git commit -m "docs(dforge): hand executor fallbacks to the session"
```

### Task 9: Rewrite the planning prose

**Files:**
- Modify: `plugins/dforge/skills/writing-plans/SKILL.md` (header template's Execution line, §Task Right-Sizing's fixed-cost sentence, §Parallel waves "Ask first" and rule 8, §Assign an implementer's closing paragraph)
- Modify: `plugins/dforge/skills/writing-plans/references/execution-line.md`, `references/auto-run-plan.md`, `references/assigning-implementers.md`, `references/assignment-procedure.md`
- Modify: `plugins/dforge/reference/native-codex.md` (the inline all-or-nothing rule), `plugins/dforge/reference/auto-run.md` (subagent-mode execution wording)
- Modify: `plugins/dforge/tests/review-route.test.sh` (the heavy-majority pin), `plugins/dforge/tests/auto-run-skills.test.sh`, `plugins/dforge/tests/inline-only.acceptance.test.sh`

**Interfaces:**
- Consumes: C4, C8, C9
- Produces: none

**Implementer:** dforge:impl-sonnet-high
**Evaluation:** files 1 - spec 2 - coupling 1 - risk 1 = 5

- [ ] **Step 1: Write the failing test**

Append above `# --- summary ---`:

```bash
# --- Task 9 ---
SKILL_VIEW_DIR="$TMP/views"; . "$P/tests/skill-view.sh"
WP=$(skill_view writing-plans)
present "execution line is always inline" "$P/skills/writing-plans/references/execution-line.md" 'Write `inline` on every plan.'
absent "no heavy-majority rule" "$WP" "more than half the tasks are heavy"
present "parallel needs an explicit subagent line" "$WP" "Parallel waves apply only when the Execution line is \`subagent\`"
absent "Codex has no all-or-nothing inline rule" "$P/reference/native-codex.md" "all-or-nothing inline rule"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 300 bash plugins/dforge/tests/inline-only.acceptance.test.sh`
Expected: FAIL on the Task 9 checks.

- [ ] **Step 3: Implement**

1. execution-line.md: "Write `inline` on every plan." The pair is C4's floor (assignment row of the highest self-implemented total; effort `high` at risk 3 or with executor tasks). `subagent` only when `executionMode=subagent` or your human partner asks, and plan-lint warns it is deprecated. Remove the majority rule and "heavy tasks are delegated".
2. writing-plans SKILL.md: the template's Execution line reads `**Execution:** inline — \`claude --model <model> --effort <effort>\` — [why]`; the fixed-cost sentence in §Task Right-Sizing names the session's own implementation and review, not an implementer dispatch; §Parallel waves opens "Parallel waves apply only when the Execution line is `subagent` (deprecated): otherwise write `**Parallelism:** sequential — inline execution` and ask nothing." and rule 8 says the same; the closing note of §Assign an implementer says the lines are kept for the deprecated subagent mode and for executor fallback scoring.
3. auto-run-plan.md's strategy bullet: take the spec's line; with none, `sequential` unless the Execution line is subagent. assigning-implementers.md and assignment-procedure.md: the `**Implementer:**` line is read only by the deprecated subagent mode; under inline mode the session implements the task.
4. native-codex.md: remove the inline all-or-nothing rule; an inline Codex plan's pair ranks at or above its highest score, and a risk-3 task's review runs by hand with a native judge. auto-run.md: wording that assumes subagent execution of heavy tasks now describes inline execution, keeping the subagent-mode wave text for the deprecated path.
5. Update `review-route.test.sh` "writing-plans states the heavy-majority rule" to assert `Write \`inline\` on every plan.`, and any auto-run-skills pin of the old strategy text.

- [ ] **Step 4: Run test to verify it passes**

Run: `timeout 300 bash plugins/dforge/tests/inline-only.acceptance.test.sh && timeout 600 bash plugins/dforge/tests/review-route.test.sh && timeout 600 bash plugins/dforge/tests/auto-run-skills.test.sh && timeout 600 bash plugins/dforge/tests/native-routing.test.sh`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A plugins/dforge
git commit -m "docs(dforge): plan every task for inline execution"
```

### Task 10: Deprecate subagent mode in routing

**Files:**
- Modify: `plugins/dforge/skills/subagent-driven-development/SKILL.md` (frontmatter `description:`, opening note)
- Modify: `plugins/dforge/skills/using-dforge/SKILL.md` (routing table row, §Process Depth), `plugins/dforge/skills/using-dforge/references/codex-tools.md`
- Modify: `plugins/dforge/skills/brainstorming/SKILL.md` (§Three Paths Process line, checklist step 5, Settings `executionStrategy` bullet), `references/design-phase.md` (Choosing the execution strategy), `references/auto-by-default.md`, `references/process-flow.md`
- Modify: `plugins/dforge/tests/auto-default.test.sh`, `plugins/dforge/tests/inline-only.acceptance.test.sh`, and suites pinning the old Process line or routing row

**Interfaces:**
- Consumes: C9
- Produces: C10, C11

**Implementer:** dforge:impl-sonnet-high
**Evaluation:** files 1 - spec 2 - coupling 1 - risk 1 = 5

- [ ] **Step 1: Write the failing test**

Append above `# --- summary ---`:

```bash
# --- Task 10 ---
SDD="$P/skills/subagent-driven-development/SKILL.md"
check "A10: the subagent skill is deprecated" \
  "$(case "$(sed -n 's/^description: //p' "$SDD")" in "Deprecated —"*) echo yes ;; *) echo no ;; esac)" "yes"
present "A10: routing names executing-plans" "$P/skills/using-dforge/SKILL.md" "| Executing a plan | dforge:executing-plans"
for f in "$P/skills/brainstorming/SKILL.md" "$P/skills/using-dforge/SKILL.md"; do
  present "A18: $(basename "$(dirname "$f")") states the Process line" "$f" 'Process: <spike|bounded|architectural> — <trigger | no trigger>'
  absent "A18: $(basename "$(dirname "$f")") has no mode slot" "$f" '<inline|subagent>'
done
absent "brainstorming asks no strategy question" "$P/skills/brainstorming/SKILL.md" "**Ask the execution strategy**"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 300 bash plugins/dforge/tests/inline-only.acceptance.test.sh`
Expected: FAIL on the Task 10 checks.

- [ ] **Step 3: Implement**

1. subagent-driven-development: `description: Deprecated — use only when a plan's Execution line names subagent or your human partner asks for subagent mode`; below the title, two lines: deprecated, executing-plans is the replacement, deletion follows in a later release.
2. using-dforge: routing row `| Executing a plan | dforge:executing-plans; dforge:subagent-driven-development only for a plan whose Execution line names subagent |`; §Process Depth: the Process line is C10's two forms; drop "Execute inline by default when the plan allows it (at most half the tasks heavy…)" and say every plan executes inline, the session implementing every task but executor tasks. codex-tools.md: same rule for Codex.
3. brainstorming: Process line grammar per C10 in §Three Paths (both forms) and the Red Flags/checklist text; remove checklist step 5 and renumber; the `executionStrategy` Settings bullet says the setting is honoured only with a subagent Execution line and that the spec records `**Execution strategy:** sequential — inline execution`; design-phase.md's "Choosing the execution strategy" becomes that one rule; auto-by-default.md and process-flow.md drop the strategy question.
4. Update `auto-default.test.sh` and any suite pinning the old Process line, the routing row or the strategy question.

- [ ] **Step 4: Run test to verify it passes**

Run: `timeout 300 bash plugins/dforge/tests/inline-only.acceptance.test.sh && timeout 300 bash plugins/dforge/tests/auto-default.test.sh && timeout 600 bash plugins/dforge/tests/auto-run-skills.test.sh && timeout 600 bash plugins/dforge/tests/seats.test.sh && timeout 600 bash plugins/dforge/tests/review-depth.acceptance.test.sh`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A plugins/dforge
git commit -m "docs(dforge): deprecate subagent-driven development"
```

### Task 11: Update descriptions and release

**Files:**
- Modify: `plugins/dforge/README.md`, `plugins/dforge/.claude-plugin/plugin.json`, `plugins/dforge/.codex-plugin/plugin.json`, `.claude-plugin/marketplace.json`, `.agents/plugins/marketplace.json` (descriptions; version where the files carry dforge's)
- Modify: `plugins/dforge/tests/inline-only.acceptance.test.sh`

**Interfaces:**
- Consumes: C9
- Produces: none

**Implementer:** dforge:impl-sonnet-medium
**Evaluation:** files 1 - spec 2 - coupling 0 - risk 1 = 4

- [ ] **Step 1: Write the failing test**

Append above `# --- summary ---`:

```bash
# --- Task 11 ---
for f in "$P/.claude-plugin/plugin.json" "$P/.codex-plugin/plugin.json" "$P/../../.claude-plugin/marketplace.json" "$P/../../.agents/plugins/marketplace.json"; do
  absent "no tiered implementers in $f" "$f" "tiered implementers"
done
check "marketplace keyword swapped" "$(jq -r '.plugins[] | select(.name == "dforge") | .keywords | index("spec-driven") != null and index("subagents") == null' < "$P/../../.claude-plugin/marketplace.json" | tr -d '\r')" "true"
for needle in "delegates its heavy" "drafter-sonnet" "scout-sonnet" "Best-of-3"; do
  absent "README drops: $needle" "$P/README.md" "$needle"
done
check "version bumped to 4.13.0" "$(jq -r .version < "$P/.claude-plugin/plugin.json" | tr -d '\r')" "4.13.0"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 300 bash plugins/dforge/tests/inline-only.acceptance.test.sh`
Expected: FAIL on the Task 11 checks.

- [ ] **Step 3: Implement**

1. Descriptions: replace "tiered implementers" with "in-session execution" in both plugin manifests and both marketplace catalogs; drop the `subagents` keyword in favour of `spec-driven`.
2. README: rewrite the execution sections — every plan runs inline, heavy tasks in the session, risk-3 tasks get a per-task judge review, executor tasks still go to Codex or Antigravity, subagent mode deprecated; drop drafter and scout text (the drafting, best-of-3 and agent-roster passages) and the "An inline plan delegates its heavy …" sentence.
3. Version: `4.13.0` in both plugin manifests (and wherever `validate-repository.mjs` requires the versions to agree), following `chore(dforge): release 4.12.0` (f2cf510f) for which files a release touches.
4. Reweigh `inline-only.acceptance.test.sh` in `scripts/test-shards.mjs`: three times its measured local seconds, at most 80% of its 600 s limit.
5. Run the whole validation: `timeout 120 node scripts/validate-repository.mjs`, `timeout 1500 node scripts/test-all.mjs`, `timeout 60 /root/.local/bin/claude plugin validate .`, `timeout 60 /root/.local/bin/claude plugin validate plugins/dforge` and each other plugin, `timeout 240 /root/.local/bin/claude plugin test plugins/dforge`. Fix what fails.

- [ ] **Step 4: Run test to verify it passes**

Run: `timeout 300 bash plugins/dforge/tests/inline-only.acceptance.test.sh && timeout 120 node scripts/validate-repository.mjs && timeout 1500 node scripts/test-all.mjs`
Expected: PASS (A13's local half; CI's half runs at finishing).

- [ ] **Step 5: Commit**

```bash
git add -A plugins/dforge .claude-plugin .agents scripts/test-shards.mjs
git commit -m "chore(dforge): release 4.13.0"
```
