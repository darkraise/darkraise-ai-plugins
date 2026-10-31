# Test Tiers, Fewer Tests and CI Parity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: the skill the **Execution:** line names — dforge:subagent-driven-development for `subagent`, dforge:executing-plans for `inline`. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Run a fast task check per task and the full suite only at waves, the final review and finishing; plan fewer, broader tests and clean up redundant ones routinely; and make dforge read, mirror and wait for CI, with this repository's Windows pitfalls and shard limits checked before push.

**Architecture:** The plan header gains `**Task check:**`, a required-by-writing `**Integration check:**`, `**CI:**` and an optional `**Early CI:**` line; plan-lint checks their grammar, `task-step review` takes the suite schedule, and `suite-run` records duration. The skills (writing-plans, delegated-task, executing-plans, final review, finishing, running-gates, TDD, test-simplifier, closing-a-milestone) are rewritten to use them. A new `scripts/ci-mirror` runs the plan's local CI commands, and this repository gains a portability lint and a shard-weight check.

**Tech Stack:** Bash (plugin scripts and their `*.test.sh` suites), jq, git, gh; Node ESM (`scripts/*.mjs` and `tests/*.test.mjs` at the repository root); Markdown skills.

**Spec:** docs/dforge/specs/2026-10-31-test-tiers-and-ci-parity-design.md

**Execution:** subagent — `claude --model sonnet --effort high` — more than half the tasks are heavy

**Parallelism:** sequential — the spec's execution strategy: parts share writing-plans, delegated-task, final-review, finishing and plan-lint files

**Integration check:** `node scripts/test-all.mjs`

**Plan review:** 2026-10-31 — dforge:judge-opus — executability 12 / coherence 13 / coverage 15 / assumptions 13 (round 1)

## Global Constraints

- English only in code, comments, docs, commits and tests. Commit messages follow `<type>(<scope>): <subject>`, type one of feat|fix|docs|style|refactor|test|chore|perf, subject at most 50 characters, imperative, no period. No `Co-Authored-By:`, `Claude-Session:` or "Generated with" lines; commit as `Darkraise <quangtc94@gmail.com>`.
- Every script and test runs on Linux and on Windows Git Bash (CI runs 12 Windows shards). Follow these rules in every new or changed line: never pass a `$PWD`- or `$(pwd)`-built path to `git -C` without `dr_native_path` (`plugins/dforge/scripts/lib/native-path.sh`); never pass a regex with a backslash through `awk -v` (use `ENVIRON`); import an absolute path in Node only through `pathToFileURL`; feed `jq` a file on stdin, not as a path argument, in any file that exports `MSYS_NO_PATHCONV`; strip `\r` when reading files a Windows tool may have written (`tr -d '\r'`).
- Tests follow the spec's part 2: a new behaviour gets a new check; a variant of an existing check is added as a row or case of that check; a pin of skill wording this plan changes is updated in place, never duplicated. Prefer extending an existing suite over creating one.
- Every new `plugins/dforge/tests/*.test.sh` gets a `windowsSeconds` entry in `scripts/test-shards.mjs` (estimate 3x its Linux time) in the same commit.
- Bound every test, CLI and network command with a timeout (`timeout <s>` in shell, a `timeout` option in Node), and leave no process running after a test.
- Preserve existing `DCC_*` variables and statusline user storage paths. Do not edit historical plans or specs under `docs/dforge/plans` or `docs/dforge/specs`, other than this plan.
- Do not bump plugin versions; releases are separate commits.
- Text in skills and references: one fact per sentence, literal phrasing, no metaphor. Keep each changed skill's existing structure and headings.

## Contracts

**C1. `suites.tsv` row.** `suite-run` writes seven tab-separated columns: `<HEAD sha> <clean|dirty> <command> <exit> <log path> <epoch> <duration seconds>`. `<duration seconds>` is a non-negative integer, the wall time of the command. Every reader accepts six-column rows written before this change; a six-column row has unknown duration.

**C2. `task-step` suite schedule.**
- `task-step review PLAN_FILE N [M ...] [--base SHA] [--head REF] [--cwd DIR] [--suite COMMAND] [--suite-base SHA]` and `task-step review --group PLAN_FILE N M ... [--cwd DIR] [--suite COMMAND] [--suite-base SHA]`. `--suite` writes the step file's `suite` field and `--suite-base` its `suiteBase` field, on the step file `verdict` reads (the first id's for a single review, the last member's for `--group`), overriding what `start --suite` recorded.
- `suite_base_sha` returns `suiteBase` when the step file has one, else the group rule, else the task's own `base`.
- When the plan's `**Task check:**` line starts with `none` and the step file has no `suite`, `verdict` prints the digest line `suite: not scheduled (next at Task <N>)`, where `<N>` is the smallest task number greater than the current task that is a multiple of 3, or the plan's last task number when that is smaller; it does not exit 7, and the task may complete. A step file with no `suite` on any other plan keeps printing `suite: none recorded`.

**C3. Plan header lines.**
- `**Task check:** `<command>` — <why>` or `**Task check:** none — full suite every 3 tasks`.
- `**Integration check:** `<command>``, on every plan.
- `**CI:** none` or `` **CI:** `<workflow files>` — platforms: <list> — local: `<cmd>`; `<cmd>` — uncovered: <platforms or none> `` (one or more `local:` code spans separated by `; `). The `uncovered:` list names platforms by the Platform cells of C6's pitfalls table (`Windows Git Bash`, `macOS`, `uutils (ubuntu-latest)`), comma-separated, or `none`.
- `**Early CI:** after wave <k> — consented <YYYY-MM-DD>` or `**Early CI:** after task <n> — consented <YYYY-MM-DD>`, optional.
- plan-lint messages, exactly: WARN `no **Task check:** line yet`, WARN `no **Integration check:** line yet` (sequential plans only; a waves plan keeps today's error), WARN `no **CI:** line yet`; ERROR `**Task check:** must be one command code span or "none — full suite every 3 tasks"`; ERROR `**CI:** must be "none" or "<files> — platforms: … — local: … — uncovered: …"`; ERROR `**Early CI:** lacks "— consented <YYYY-MM-DD>"`; ERROR `**Early CI:** names a wave on a sequential plan`; ERROR `**Early CI:** names Task <n>, past the last task`.

**C4. Step 1 forms.** A task's first step heading is one of:
- `- [ ] **Step 1: Write the failing test**`
- `` - [ ] **Step 1: Extend the test `<file>::<name>`** ``
- `` - [ ] **Step 1: Covered by Task <N>'s test `<name>`** ``

plan-lint ERRORs, exactly: `Task <M>: Covered by Task <N> — no such task`, `Task <M>: Covered by Task <N> — Task <N> has no test step`, `Task <M>: Covered by Task <N> — Task <N> does not run before Task <M>`. A task has a test step when its Step 1 is the first or second form. "Runs before": in a sequential plan `<N>` < `<M>`; in a waves plan Task `<N>`'s wave comes before Task `<M>`'s.

**C5. `gates.md` fields.** `Tier:` takes `task`, `branch` or `sweep`; absent means `branch`. `Budget:` takes `<seconds>s` (for example `Budget: 900s`) and is read only on the gate whose `Command` equals the plan's `**Integration check:**` command. running-gates prints, for each `sweep` gate it skips: `gate <n> (<title>): skipped — Tier sweep runs in CI`.

**C6. Reference files.** `plugins/dforge/reference/test-tiers.md` defines the three tiers (Task check, Full suite, Sweep) and holds the impact-selection table under the heading `## Impact selection`. `plugins/dforge/reference/ci-parity.md` holds `## Finding the CI configuration`, `## Reading jobs, platforms and commands` and `## Pitfalls`, a table with columns `| Platform | Pitfall | Do instead |` whose Platform cells are exactly `Windows Git Bash`, `macOS` or `uutils (ubuntu-latest)`.

**C7. `scripts/ci-mirror PLAN_FILE`.** Reads the plan's `**CI:**` line and runs each `local:` command through `bash scripts/suite-run -- bash -c '<cmd>'` from the checkout's top level. Prints one line per command, `ci: <cmd> — <the suite-run verdict line without its "suite: " prefix>`, then `uncovered: <platforms or none>`. For `**CI:** none` it prints `ci: none` and exits 0. Exit 0 when every command passed or was reused, 1 when any command failed or could not launch (its line then reads `ci: <cmd> — FAIL (exit <code>)`), 2 on a usage error or a missing or malformed `**CI:**` line.

**C8. Ledger lines.** `Early CI: dispatched run <id> at <sha7>`, `Early CI: green run <id>`, `Early CI: red run <id> — <job>/<step>[, <job>/<step> ...]`, `Early CI: skipped — <reason>`, and finishing's `CI: <sha7> run <id> <green|red|still running at 90 min>`.

**C9. `scripts/lint-portability.mjs`** (repository root). Scans `plugins/*/scripts/**`, `plugins/*/tests/**` and `scripts/**`. Prints one line per hit, `<file>:<line> <rule> <message>`, rule ids `git-c-pwd`, `awk-v-backslash`, `import-path`, `jq-pwd-file`; exits 1 when there is any hit, else 0. A line ending `# portability: ok — <reason>` or `// portability: ok — <reason>` is exempt. Exports `lintText(path, text)` returning the hits for one file's text, as `{ line, rule, message }` objects, for tests.

**C10. Shard check message.** `tests/test-shards.test.mjs` fails a weight above 80% of its suite's limit with a message containing `raise its suiteSeconds or split it`.

## Assumptions (evidence)

- The full suite, `node scripts/test-all.mjs`, took about 1355 s on this host (`.dforge/suites/1793265964-2694701.log`, row epoch 1793267319, read 2026-10-31).
- plan-lint requires only Goal, Spec and Execution today and checks `**Integration check:**` only on a waves plan (`plugins/dforge/scripts/plan-lint:101-103`, `:560-562`; spec review report 2026-10-31).
- `suite_base_sha` is the single place a suite's base is chosen (`plugins/dforge/scripts/task-step:126-139`, read 2026-10-31).
- Every current `suites.tsv` reader tolerates a seventh column except the pin `plugins/dforge/tests/suite-run.test.sh:76` (spec review report 2026-10-31).
- `.github/workflows/validate.yml` declares `workflow_dispatch` (line 7, read 2026-10-31).
- No current line matches the `git-c-pwd` or `awk-v-backslash` rule (grep over `plugins/*/scripts plugins/*/tests scripts`, 2026-10-31). The `import-path` and `jq-pwd-file` rules are unverified — Task 14 runs the lint over the tree and fixes or exempts each hit.
- `plugins/dforge/tests/task-step.test.sh` has no part selection today (read 2026-10-31); Task 15 adds it so `suiteParts` can split it.
- Skill sizes against the 20,000-byte cap that `plugins/dforge/tests/skill-size.test.sh` enforces (`wc -c`, 2026-10-31): `skills/writing-plans/SKILL.md` 19189, `skills/executing-plans/SKILL.md` 19648, `skills/finishing-a-development-branch/SKILL.md` 19262, `skills/subagent-driven-development/SKILL.md` 17932, `skills/test-driven-development/SKILL.md` 9833. Every task that grows one of these runs `skill-size.test.sh` and moves text to a reference instead of passing the cap.
- 37 shell suites have no `windowsSeconds` weight today, each under 1.2 s on Linux; the part timings and check counts Task 15 gives for splitting `task-step.test.sh` and `faster-plans` come from a trial in a scratch clone by the plan's drafter (2026-10-31), unverified in this checkout — Task 15's Step 2 lists the unweighted suites and its Step 4 runs each part.
- `import-path` has exactly one hit today, `plugins/dforge/tests/dforge-config.test.sh:276` (the drafter's run of the rule in a scratch clone, 2026-10-31), unverified in this checkout — Task 14's Step 4 runs the lint over the tree.
- Hazard accepted from the spec: under C2, a scheduled task whose controller omits `--suite` still prints `not scheduled` and completes; the final review's integration check (Task 5) is the backstop that catches what that task's suite would have caught.
- Today's weights put `faster-plans.acceptance.test.sh` (1200 s over 2 parts), `task-step.test.sh` (1340 s), `next-step.test.sh` (500 s) and `auto-run.test.sh` (507 s) above 80% of their limits (`scripts/test-shards.mjs:11-59`, `scripts/test-all.mjs:54`; spec review report 2026-10-31).

- Borderline plan-review scores (round 1, 2026-10-31): executability 12, coherence 13 and assumptions 13 are accepted after the round's fixes. The Critical finding (writing-plans `SKILL.md` past its cap) moved Task 7's text to `references/test-step-forms.md`; the Important ones made the final review, the fix subagent and finishing run the integration check in one `bash -c` form (Task 5), and added the evidence above. The cap is one round at depth standard.
## Task index

1. Record suite duration in suites.tsv
2. Schedule the suite at review time in task-step
3. Lint the new plan header lines
4. Write the tier lines from writing-plans
5. Run the task check in the controller loops
6. Add Tier and Budget to gates
7. Lint and plan the three Step 1 forms
8. Rewrite the TDD, plan-review and lens test rules
9. Recommend scoped cleanup and scope test-simplifier
10. Describe CI parity and write the CI line
11. Mirror CI locally with ci-mirror
12. Run early CI from the controller
13. Wait for CI at finishing
14. Lint this repository for Git Bash pitfalls
15. Enforce shard weights and warn on suite drift

---

### Task 1: Record suite duration in suites.tsv

**Files:**
- Modify: `plugins/dforge/scripts/suite-run`
- Test: `plugins/dforge/tests/suite-run.test.sh`

**Interfaces:**
- Consumes: none.
- Produces: Contracts C1. Every row `suite-run` records has a seventh column, the command's wall time in whole seconds. Rows written before this change keep six columns.

**Items:** 1
**Implementer:** dforge:impl-opus-high
**Evaluation:** files 1 - spec 2 - coupling 2 - risk 2 = 7

- [ ] **Step 1: Extend the test `plugins/dforge/tests/suite-run.test.sh::the row has six fields`**

Make three edits in `plugins/dforge/tests/suite-run.test.sh`.

1. Replace the pin at line 76 in place. The old line is `check "the row has six fields" "$(last_row | awk -F'\t' '{print NF}')" "6"`. The new line is:

```bash
check "the row has seven fields" "$(last_row | awk -F'\t' '{print NF}')" "7"
```

2. Directly after the line `check "the row records the exit" "$(field 4)" "0"` (line 80), add:

```bash
check "the row records a whole-second duration" "$(field 7 | grep -cE '^[0-9]+$')" "1"
```

3. Directly after the line `check "a timeout is recorded" "$(field 4)" "124"` (line 188), add:

```bash
check "a timed-out run records its wall time" "$([ "$(field 7)" -ge 1 ] && [ "$(field 7)" -le 4 ] && echo yes || echo no)" "yes"
```

Then add this block before the final `printf '\n%d passed, %d failed\n'` line. It guards the reader: a six-column row written before the duration column existed is still reused.

```bash
# --- a six-column row from before the duration column is still reused ----------
commit six
HEAD6=$(git -C "$REPO" rev-parse HEAD)
legacy_log="$TMP/legacy.log"
: > "$legacy_log"
printf '%s\tclean\t%s\t0\t%s\t%s\n' "$HEAD6" "bash $TMP/probe.sh 0 $TMP/out-tap-pass" "$legacy_log" "$(date +%s)" >> "$REPO/.dforge/suites.tsv"
before=$(runs)
probe 0 "$TMP/out-tap-pass"
has "a six-column row is reused" "$out" "suite: reused pass at ${HEAD6:0:7} ("
check "reusing a six-column row does not run the command" "$(runs)" "$before"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 600 bash plugins/dforge/tests/suite-run.test.sh`
Expected: FAIL on "the row has seven fields" (got 6), "the row records a whole-second duration" (got 0) and "a timed-out run records its wall time". The six-column reuse rows pass before and after: they guard the reader and are not the red tests.

- [ ] **Step 3: Implement**

In `plugins/dforge/scripts/suite-run`:

1. After `wait "$pid"` returns and the exit code is settled (the `[ "$code" -ne 137 ] || code=124` line), read the clock once into a variable and compute the duration as that value minus `start`, the epoch already read before the command launched. Use the same variable for the epoch column, so the two columns agree.
2. Append the duration as the seventh tab-separated field of the row written to `suites.tsv`, after the epoch. The format string gains one `%s`.
3. Do not change the reuse check. It prints columns 5 and 6 of the matching row and ignores anything after them, so it accepts rows of six or seven columns. A reuse records no row and so has no duration.
4. Update the header comment: the row layout now ends `<epoch> <duration seconds>`, the duration is the command's wall time in whole seconds, and a row written by an earlier version has six columns and no duration.
5. Change nothing else. `scripts/task-step` already reads the row with `read -r _ kind _ code log _`, whose last variable absorbs the extra column, and cuts columns 4 and 5 with `cut`.

- [ ] **Step 4: Run test to verify it passes**

Run: `timeout 600 bash plugins/dforge/tests/suite-run.test.sh`
Expected: PASS, summary line `0 failed`.

Then run the two suites that read rows `suite-run` writes, to confirm every reader accepts the seventh column:

Run: `timeout 900 bash plugins/dforge/tests/task-step-suite.test.sh && timeout 900 bash plugins/dforge/tests/task-step-base.test.sh`
Expected: both end with `0 failed`.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/scripts/suite-run plugins/dforge/tests/suite-run.test.sh
git commit -m "feat(dforge): record suite run duration"
```

### Task 2: Schedule the suite at review time in task-step

**Files:**
- Modify: `plugins/dforge/scripts/task-step` (header comment and `usage`, `suite_base_sha`, the argument loop, `do_review`, `do_group`, `suite_check`)
- Test: `plugins/dforge/tests/task-step-suite.test.sh`
- Test: `plugins/dforge/tests/task-step-base.test.sh`

**Interfaces:**
- Consumes: Contracts C1 (rows with six or seven columns).
- Produces: Contracts C2. `task-step review PLAN_FILE N [M ...] [--suite COMMAND] [--suite-base SHA]` and `task-step review --group PLAN_FILE N M ... [--suite COMMAND] [--suite-base SHA]` write `suite` and `suiteBase` onto the step file `verdict` reads. `suite_base_sha` returns `suiteBase` first. `verdict` prints `suite: not scheduled (next at Task <N>)` on a plan whose `**Task check:**` starts with `none` when the step file has no `suite`.

**Items:** 1
**Implementer:** dforge:impl-opus-high
**Evaluation:** files 1 - spec 2 - coupling 2 - risk 2 = 7

- [ ] **Step 1: Write the failing test**

Part A: `plugins/dforge/tests/task-step-suite.test.sh`.

Replace the old pin that says review takes no `--suite`. These two lines, directly after the `start --suite without a command exits 2` check:

```bash
step review docs/plan.md 1 --suite x
check "review does not take --suite" "$rc" "2"
```

become:

```bash
step review docs/plan.md 1 --suite-base nope
check "review --suite-base: a ref that is no commit exits 2" "$rc $(grep -cF 'bad --suite-base: nope' <<<"$err")" "2 1"
step start docs/plan.md 1 --suite-base "$(git rev-parse HEAD)"
check "start does not take --suite-base" "$rc" "2"
```

Add this block directly before the `# --- the doc says so ---` comment, after `git worktree remove --force "$WT"`. The two plan copies are untracked, so the verdict's tracked-file check ignores them, and the block removes them at its end so later `suite-run` rows would stay clean.

```bash
# --- verdict: a none task check schedules the suite by task number ---
awk '{ print } /^\*\*Execution:\*\*/ { print ""; print "**Task check:** none — full suite every 3 tasks" }' docs/plan.md > docs/plan-none.md
printf '\n### Task 4: fourth\n\n**Implementer:** dforge:impl-sonnet-low\n**Evaluation:** files 0 - spec 0 - coupling 0 - risk 0 = 0\n\nBody four.\n' >> docs/plan-none.md
WS_MAIN=$WS
WS=$(winpath "$(bash "$P/scripts/sdd-workspace" docs/plan-none.md)")
rm -f "$WS"/*
HEAD_SHA=$(git rev-parse HEAD | tr -d '\r')
for t in 1 2 3 4; do
  step start docs/plan-none.md "$t"
  set_review "$t" "$HEAD_SHA" "$REPO"
  report "$WS/task-$t-review-report.md"
done
step verdict docs/plan-none.md 1
check "none task check, Task 1: not scheduled, never exit 7" "$rc $(grep '^suite: ' <<<"$out")" "0 suite: not scheduled (next at Task 3)"
check "none task check, Task 1: the task may complete" "$(grep '^fix: ' <<<"$out")" "fix: none"
step verdict docs/plan-none.md 2
check "none task check, Task 2: next at the multiple of 3" "$rc $(grep '^suite: ' <<<"$out")" "0 suite: not scheduled (next at Task 3)"
step verdict docs/plan-none.md 3
check "none task check, Task 3 of 4: the last task caps the next multiple" "$rc $(grep '^suite: ' <<<"$out")" "0 suite: not scheduled (next at Task 4)"
step start docs/plan-none.md 3 --suite "$CMD"
step verdict docs/plan-none.md 3
check "none task check: a recorded suite is still read, so no row exits 7" "$rc $(grep '^suite: ' <<<"$out")" "7 suite: not run ($CMD)"
sed 's/^\*\*Task check:\*\* none.*$/**Task check:** `bash suite.sh` — fixture/' docs/plan-none.md > docs/plan-cmd.md
WS=$(winpath "$(bash "$P/scripts/sdd-workspace" docs/plan-cmd.md)")
rm -f "$WS"/*
step start docs/plan-cmd.md 1
set_review 1 "$HEAD_SHA" "$REPO"
report "$WS/task-1-review-report.md"
step verdict docs/plan-cmd.md 1
check "a command task check with no suite recorded keeps none recorded" "$rc $(grep '^suite: ' <<<"$out")" "0 suite: none recorded"
WS=$WS_MAIN
rm -f docs/plan-none.md docs/plan-cmd.md
```

Part B: `plugins/dforge/tests/task-step-base.test.sh`. Add this block after the Task 18 block and before the `# Row 29:` comment. It uses real `review` and `review --group`, whose step-file writes are the behaviour under test. Every suite row it needs is recorded by `sr`, so no base run happens.

```bash
# Tasks 19 to 21 join the fixture plan: review takes the suite and its base.
for n in 19 20 21; do
  printf '\n### Task %s: Task %s\n\n**Files:**\n- Modify: `app.txt`\n\n**Implementer:** dforge:impl-sonnet-low\n**Evaluation:** files 0 - spec 0 - coupling 1 - risk 0 = 1\n' "$n" "$n"
done >> "$REPO/docs/plan.md"

# Task 19: a regression an earlier task made after the last full run is not
# baseline. Task 19's own base already fails, so only --suite-base finds it.
set_failing ''
commit "green at the last full run"
sr
LAST_FULL=$(g rev-parse HEAD | tr -d '\r')
set_failing $'not ok 1 - regress\n'
commit "an earlier task breaks a test"
sr
ts start docs/plan.md 19
printf 'impl 19\n' >> "$REPO/app.txt"
commit "work 19"
sr
ts review docs/plan.md 19 --suite 'bash suite.sh' --suite-base "$LAST_FULL"
check "task 19: review --suite --suite-base exits 0" "$rc" "0"
check "task 19: the step file holds the suite and its base" "$(jq -r '"\(.suite) \(.suiteBase)"' < "$WS/task-19-step.json" | tr -d '\r')" "bash suite.sh $LAST_FULL"
clean_report 19
ts verdict docs/plan.md 19
check "task 19: a failure that passes at the suite base is new" "$rc $(grep '^suite: ' <<<"$out")" "0 suite: red (1 failing, 0 baseline)"

# Tasks 20 and 21: review --group writes both onto the last member's step file.
set_failing ''
commit "green at the last full run before the group"
sr
G_FULL=$(g rev-parse HEAD | tr -d '\r')
set_failing $'not ok 1 - regress\n'
commit "an earlier task breaks a test before the group"
sr
ts start docs/plan.md 20
printf 'impl 20\n' >> "$REPO/app.txt"
commit "member 1"
ts start docs/plan.md 21
printf 'impl 21\n' >> "$REPO/app.txt"
commit "member 2"
sr
for t in 20 21; do
  printf 'Task %s: awaiting group review (commits aaaaaaa..bbbbbbb)\n' "$t" >> "$WS/progress.md"
  jq --arg h "$(g rev-parse HEAD | tr -d '\r')" '.heldHead = $h' < "$WS/task-$t-step.json" > "$TMP/s.json" && mv "$TMP/s.json" "$WS/task-$t-step.json"
done
ts review --group docs/plan.md 20 21 --suite 'bash suite.sh' --suite-base "$G_FULL"
check "group: review --group --suite --suite-base exits 0" "$rc" "0"
check "group: the last member's step file holds the suite and its base" "$(jq -r '"\(.suite) \(.suiteBase)"' < "$WS/task-21-step.json" | tr -d '\r')" "bash suite.sh $G_FULL"
check "group: the first member's step file holds neither" "$(jq -r '"\(.suite // "none") \(.suiteBase // "none")"' < "$WS/task-20-step.json" | tr -d '\r')" "none none"
{
  printf '## Verdict\n'
  for t in 20 21; do
    printf 'Task %s spec: pass\nTask %s quality: approved\nTask %s scores: spec 17 / scope 17 / verification 17 / quality 17\n' "$t" "$t" "$t"
  done
} > "$WS/group-20,21-review-report.md"
ts verdict docs/plan.md 20 21 --group
check "group: the suite base beats the group rule, so the regression is new" "$rc $(grep '^suite: ' <<<"$out")" "0 suite: red (1 failing, 0 baseline)"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 900 bash plugins/dforge/tests/task-step-suite.test.sh`
Expected: FAIL on "review --suite-base: a ref that is no commit exits 2" (the usage message appears, not `bad --suite-base`) and on the three `none task check` rows that read `suite: not scheduled` (the `fix: none` row already passes) (the digest says `suite: none recorded`).

Run: `timeout 900 bash plugins/dforge/tests/task-step-base.test.sh`
Expected: FAIL on "task 19: review --suite --suite-base exits 0" and the group review rows (task-step exits 2 on the unknown `--suite` flag).

- [ ] **Step 3: Implement**

All changes are in `plugins/dforge/scripts/task-step`.

1. Argument loop. `--suite COMMAND` is accepted for `start`, `review` and `review --group` (the loop's `$sub` is `start`, `review` or `group`), always with a non-empty value; any other subcommand still exits 2. Add `--suite-base SHA`, accepted for `review` and `group` only, into a new `suite_base_arg` variable. Both flags may appear alone.
2. Directly after the argument loop and the `ids` checks, when `suite_base_arg` is set, resolve it with `git rev-parse --verify --quiet "<value>^{commit}"`. On failure call `die "bad --suite-base: <value>"` (exit 2), before any state is written. Keep the resolved full sha in `suite_base_sha_arg` (a name that does not collide with the `suite_base_sha` function).
3. `do_review`: add both fields to the final `jq` update of `$state`, the one that already sets `reviewHead`, `t0` and `reviewCheck`. `suite` is set only when `--suite` was given, and `suiteBase` only when `--suite-base` was. A review without the flags leaves what `start` recorded. Write no Ruling line: that stays `start`'s.
4. `do_group`: after the loop that updates each member's step file, apply the same two fields with one more `jq` update to the last member's step file (`task-<last>-step.json`, the file `suite_check` reads for a group). The first members' files get neither field.
5. `suite_base_sha`: before the group rule, print the step file's `suiteBase` and return when it is non-empty. The group rule and the task's own `base` stay as they are. Every caller (`suite_base_lines`, `suite_gap`, `suite_check`) then follows the new base, so a base row is reused at that sha and a missing row costs one bounded base run through the existing path.
6. `suite_check`: where it returns early because the step file has no `suite`, read the plan header's `**Task check:**` line from the amended plan (`$src`) with `plan_header_line`. When the text after the label starts with `none` followed by the end of the line or a space, set `suite_line` to `suite: not scheduled (next at Task <N>)` and leave `suite_state` at `none`, so `verdict` still exits 0 and the task can complete. `<N>` is the smallest multiple of 3 greater than the current task (the last member for a group, as `target` is today), or the plan's last task number when that is smaller; take the last task number from `plan_tasks`. A plan with no `**Task check:**` line, or one that does not start with `none`, keeps `suite: none recorded`. A recorded `suite` is read exactly as before.
7. Update the `Usage:` comment block and the `usage()` text for `review` and `review --group`, and add `--suite` and `--suite-base` to them. The exit-code comment is unchanged.

- [ ] **Step 4: Run test to verify it passes**

Run: `timeout 900 bash plugins/dforge/tests/task-step-suite.test.sh && timeout 900 bash plugins/dforge/tests/task-step-base.test.sh`
Expected: both end with `0 failed`.

Run the broader suite that drives `review`, `hold` and `review --group`:

Run: `timeout 1800 bash plugins/dforge/tests/task-step.test.sh`
Expected: ends with `0 failed`.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/scripts/task-step plugins/dforge/tests/task-step-suite.test.sh plugins/dforge/tests/task-step-base.test.sh
git commit -m "feat(dforge): take suite and base at task review"
```

### Task 3: Lint the new plan header lines

**Files:**
- Modify: `plugins/dforge/scripts/plan-lint` (a new block after the parallel-waves section, before the UI/UX section)
- Test: `plugins/dforge/tests/plan-lint.test.sh`

**Interfaces:**
- Consumes: none.
- Produces: Contracts C3, the plan-lint rows. WARN `no **Task check:** line yet`, `no **Integration check:** line yet` (sequential plans only) and `no **CI:** line yet`; ERROR for a malformed `**Task check:**`, `**CI:**` or `**Early CI:**`, with the exact messages Contracts gives. This task adds two messages Contracts does not name, both in plan-lint only: ERROR `**Integration check:** names no command`, and ERROR `**Early CI:** must be "after wave <k>" or "after task <n>", then "— consented <YYYY-MM-DD>"`.

**Items:** 1
**Implementer:** dforge:impl-sonnet-high
**Evaluation:** files 1 - spec 2 - coupling 1 - risk 1 = 5

- [ ] **Step 1: Write the failing test**

All edits are in `plugins/dforge/tests/plan-lint.test.sh`. The suite is one of the slowest, so every case is a row of the existing `variant` / `lint` / `has` pattern, and independent malformations share a run where their messages differ.

Part A: give the three shared fixtures well-formed lines, so every existing pin, including the exact warning counts, keeps its meaning.

- In `claude_plan()`, directly after the `**Program:**` line and its blank line, add these three lines, each followed by a blank line:

```
**Task check:** `bash quick.sh` — gate 1 has Tier: task

**Integration check:** `bash test.sh`

**CI:** none
```

- In `codex_plan()`, add the same three lines after the `**Execution:**` line.
- In `waves_plan()` (an unquoted heredoc, so backticks are escaped), the `**Integration check:**` line already exists. Add these two lines, each followed by a blank line, directly after the `**Worktree setup:** none` line:

```
**Task check:** \`bash quick.sh\` — gate 1 has Tier: task

**CI:** none
```

Part B: in place, in the waves block, add one assertion after the existing row `has "waves: the integration check is required" ...`:

```bash
lacks "waves: the missing Integration check is an error, not a warning" "$out" "WARN header: no **Integration check:** line yet"
```

Part C: add this section after the row `lacks "sequential: a Wave check line is not an error" ...` and before the `# --- documents kept in darkmem` comment.

```bash
# --- test tier and CI header lines ---
# The fixtures carry well-formed lines, so each case edits one line. A missing
# line warns, as a missing Plan review line does; a malformed line fails.
variant hdr-missing.md '/^\*\*Task check:\*\*/d; /^\*\*Integration check:\*\*/d; /^\*\*CI:\*\*/d'
lint hdr-missing.md
check "missing tier and CI lines: warnings only, exit 0" "$status" "0"
has "a missing Task check warns" "$out" "WARN header: no **Task check:** line yet"
has "a missing Integration check warns on a sequential plan" "$out" "WARN header: no **Integration check:** line yet"
has "a missing CI line warns" "$out" "WARN header: no **CI:** line yet"
has "the three warnings add to the fixture's two" "$out" "plan-lint: 0 errors, 5 warnings"

for bad in 'run the quick tests' 'none' '`bash a.sh` `bash b.sh` — two commands'; do
  variant tc-bad.md "s#^\*\*Task check:\*\* .*#**Task check:** $bad#"
  lint tc-bad.md
  check "Task check '$bad': exit 1" "$status" "1"
  has "Task check '$bad': malformed" "$out" 'ERROR header: **Task check:** must be one command code span or "none — full suite every 3 tasks"'
done

variant ic-empty.md 's#^\*\*Integration check:\*\* .*#**Integration check:**#'
lint ic-empty.md
has "an Integration check with no command is an error" "$out" "ERROR header: **Integration check:** names no command"

CI_FULL='**CI:** `.github/workflows/validate.yml` — platforms: ubuntu-latest, windows-latest — local: `node scripts/test-all.mjs` — uncovered: Windows Git Bash'
variant tc-none.md "s#^\*\*Task check:\*\* .*#**Task check:** none — full suite every 3 tasks#; s#^\*\*CI:\*\* none\$#${CI_FULL}#"
lint tc-none.md
check "the none form and a full CI line: exit 0" "$status" "0"
has "the none form and a full CI line add no finding" "$out" "plan-lint: 0 errors, 2 warnings"

for bad in 'maybe' \
  '`ci.yml` — platforms: linux — uncovered: none' \
  '`ci.yml` — platforms: linux — local: make test — uncovered: none' \
  '`ci.yml` — platforms: linux — local: `make test`'; do
  variant ci-bad.md "s#^\*\*CI:\*\* none\$#**CI:** $bad#"
  lint ci-bad.md
  check "CI '$bad': exit 1" "$status" "1"
  has "CI '$bad': malformed" "$out" 'ERROR header: **CI:** must be "none" or "<files> — platforms: … — local: … — uncovered: …"'
done

early() { # early <Early CI value> — the plan with a full CI line and that Early CI line; sets out and status
  variant early.md "s#^\*\*CI:\*\* none\$#${CI_FULL}\n\n**Early CI:** $1#"
  lint early.md
}
early 'after task 2 — consented 2026-10-31'
check "Early CI after the last task, consented: exit 0" "$status" "0"
lacks "Early CI after the last task, consented: no finding" "$out" "Early CI"
early 'after task 2'
check "Early CI without consent: exit 1" "$status" "1"
has "Early CI without consent" "$out" 'ERROR header: **Early CI:** lacks "— consented <YYYY-MM-DD>"'
early 'after task 2 — consented tomorrow'
has "Early CI with a malformed date lacks consent" "$out" 'ERROR header: **Early CI:** lacks "— consented <YYYY-MM-DD>"'
early 'after wave 2'
has "Early CI naming a wave on a sequential plan" "$out" "ERROR header: **Early CI:** names a wave on a sequential plan"
has "Early CI naming a wave, unconsented, also lacks consent" "$out" 'ERROR header: **Early CI:** lacks "— consented <YYYY-MM-DD>"'
early 'after task 3 — consented 2026-10-31'
has "Early CI naming a task past the last" "$out" "ERROR header: **Early CI:** names Task 3, past the last task"
early 'whenever — consented 2026-10-31'
has "Early CI with no recognised point" "$out" 'ERROR header: **Early CI:** must be "after wave <k>" or "after task <n>", then "— consented <YYYY-MM-DD>"'

waves_plan 'waves — 1 | 2-3' | sed '/^\*\*Task check:\*\*/d' | sed "s#^\*\*CI:\*\* none\$#${CI_FULL}\n\n**Early CI:** after wave 2 — consented 2026-10-31#" > waves-early.md
lint waves-early.md --no-probe
check "waves: no Task check and a wave Early CI: exit 0" "$status" "0"
has "waves: a missing Task check warns" "$out" "WARN header: no **Task check:** line yet"
lacks "waves: a wave Early CI is accepted" "$out" "Early CI"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 1200 bash plugins/dforge/tests/plan-lint.test.sh`
Expected: FAIL on the missing-line warnings and the `5 warnings` summary, on every malformed-line row, on the Early CI rows, and on the waves Task check warning. The rows that expect exit 0 and no finding pass, and so do all pre-existing rows.

- [ ] **Step 3: Implement**

In `plugins/dforge/scripts/plan-lint`, add one block after the parallel-waves section (so `parallelism`, `nums` and the header helpers exist) and before the UI/UX section. Read each line from `unfenced_header` with `first_label`, as `**Wave check:**` is read, so a fenced example never counts. Strip the label and surrounding whitespace to get the value. Every finding is `say <SEV> header "<message>"` with the exact Contracts C3 text. Dashes between parts match the file's `SEP` pattern, so ` — `, ` – `, ` - ` and ` -- ` all read as the separator.

1. **Task check.** Absent: WARN `no **Task check:** line yet`. Present: valid when the value is one code span (a backtick, one or more non-backtick characters, a backtick) alone or followed by `SEP` and any text, or is `none` followed by `SEP` and exactly `full suite every 3 tasks`. Anything else, including a bare `none`, two code spans and plain prose: ERROR `**Task check:** must be one command code span or "none — full suite every 3 tasks"`.
2. **Integration check.** Absent on a sequential plan (`parallelism` is `sequential`): WARN `no **Integration check:** line yet`. Absent on a waves plan: no new finding, because the existing `a waves plan needs its **Integration check:** line` error stands. Present with an empty value, on either kind of plan: ERROR `**Integration check:** names no command`. Do not require backticks: plans written earlier give the command bare.
3. **CI.** Absent: WARN `no **CI:** line yet`. Present: valid when the value is `none`, or matches the shape `` `<files>` SEP platforms: <text> SEP local: `<cmd>`[; `<cmd>`]... SEP uncovered: <text> `` with at least one `local:` code span, the code spans separated by `; `. Anything else: ERROR `**CI:** must be "none" or "<files> — platforms: … — local: … — uncovered: …"`.
4. **Early CI.** Absent: nothing. Present: report each problem independently, in this order.
   - The point is not `after wave <k>` or `after task <n>` (a positive integer): ERROR `**Early CI:** must be "after wave <k>" or "after task <n>", then "— consented <YYYY-MM-DD>"`, and skip the two checks below.
   - The point is a wave and `parallelism` is `sequential`: ERROR `**Early CI:** names a wave on a sequential plan`. A wave on a waves plan is accepted.
   - The point is a task number above the plan's last task number (from `nums`): ERROR `**Early CI:** names Task <n>, past the last task`.
   - The value does not end with `SEP` followed by `consented ` and a date shaped `YYYY-MM-DD` (four, two and two digits): ERROR `**Early CI:** lacks "— consented <YYYY-MM-DD>"`.
5. Do not change the existing `Plan review` warning, the waves `Integration check` error or any other rule. The three new warnings use the same `WARN header:` form as `no **Plan review:** line yet`.

- [ ] **Step 4: Run test to verify it passes**

Run: `timeout 1200 bash plugins/dforge/tests/plan-lint.test.sh`
Expected: ends with `0 failed`.

Run the suite that lints amended plans, to confirm the extra warnings break nothing:

Run: `timeout 900 bash plugins/dforge/tests/plan-amend.test.sh`
Expected: ends with `0 failed`.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/scripts/plan-lint plugins/dforge/tests/plan-lint.test.sh
git commit -m "feat(dforge): lint test tier and CI header lines"
```

### Task 4: Write the tier lines from writing-plans

**Files:**
- Create: `plugins/dforge/reference/test-tiers.md`
- Create: `plugins/dforge/skills/writing-plans/references/task-check-line.md`
- Modify: `plugins/dforge/skills/writing-plans/SKILL.md` (the Plan Document Header template)
- Modify: `plugins/dforge/skills/test-simplifier/references/runners.md` (the impact-selection section)
- Test: `plugins/dforge/tests/task-step-text.test.sh`
- Test: `plugins/dforge/tests/skill-split-planning.test.sh`
- Test: `plugins/dforge/tests/test-simplifier.test.sh`

**Interfaces:**
- Consumes: Contracts C1 (seven-column rows; column 7 is the duration), C3 (header lines), C5 (`Tier: task` on a gate).
- Produces: Contracts C6 for `reference/test-tiers.md`: the three tiers and `## Impact selection`. The writing-plans header template carries `**Task check:**` and `**Integration check:**` on every plan, with the resolution rule in `skills/writing-plans/references/task-check-line.md`.

**Items:** 1
**Implementer:** dforge:impl-opus-high
**Evaluation:** files 2 - spec 2 - coupling 1 - risk 1 = 6

`skills/writing-plans/SKILL.md` is 19189 bytes and `tests/skill-split-planning.test.sh` caps it at 20000, and later tasks add to the same file. So the resolution rule goes in a reference file, and SKILL.md grows by at most 250 bytes net.

- [ ] **Step 1: Write the failing test**

Part A: `plugins/dforge/tests/task-step-text.test.sh`. Directly after the `WP="$P/skills/writing-plans/SKILL.md"` line (line 225) add two variables, and directly after the pin `names "writing-plans: the waves rule names the Wave check" ...` add the rows. The reference's prose wraps, so its rows use `names_flat`.

```bash
WPR="$P/skills/writing-plans/references/task-check-line.md"
TIERS="$P/reference/test-tiers.md"
```

```bash
# --- the Task check and Integration check header lines (test tiers) ---
names "writing-plans: the header template has a Task check line" "$WP" '**Task check:** [`<fast command>` — <why>, or `none — full suite every 3 tasks`]'
names "writing-plans: the Integration check line holds the full suite on every plan" "$WP" '**Integration check:** [`<command>`: the full suite, on every plan]'
lacks "writing-plans: the Integration check line is no longer waves only" "$WP" '**Integration check:** [waves only'
check "task check: the reference exists" "$([ -s "$WPR" ] && echo yes || echo no)" "yes"
names_flat "task check: the first source that applies wins" "$WPR" 'Choose the first that applies'
names_flat "task check: a gate with Tier: task comes first" "$WPR" 'a gate in `<docs>/gates.md` with `Tier: task`'
names_flat "task check: a fast full suite is its own task check" "$WPR" 'the full suite itself, when its last passing run in `suites.tsv` took 300 seconds or less'
names_flat "task check: impact selection comes from test-tiers.md" "$WPR" 'an impact-selection command for the runner the project uses, from [test-tiers.md](../../../reference/test-tiers.md)'
names_flat "task check: none is the last resort" "$WPR" '`none — full suite every 3 tasks`, when none of those applies'
names_flat "task check: a missing or six-column row is not fast" "$WPR" 'A row that is missing, or has six columns and so no duration, counts as not fast.'
names_flat "task check: only the checkout's own rows are read" "$WPR" 'Read only rows of the checkout you run in'
names_flat "task check: the row is found by suite-run's quoted key" "$WPR" 'the quoted key suite-run records for `bash -c <cmd>` run from the top level'
names_flat "task check: the duration is column 7" "$WPR" 'column 7'
names_flat "task check: the line ends with its reason" "$WPR" 'End the line with `— <why>`'
names_flat "integration check: on every plan, not only a waves plan" "$WPR" '`**Integration check:**` holds the full suite command on every plan, not only on a waves plan.'
names "test-tiers: the reference exists" "$TIERS" '# Test tiers'
names "test-tiers: the Task check tier" "$TIERS" '| Task check |'
names "test-tiers: the Full suite tier" "$TIERS" '| Full suite |'
names "test-tiers: the Sweep tier" "$TIERS" '| Sweep |'
names "test-tiers: the impact-selection heading" "$TIERS" '## Impact selection'
names "test-tiers: the impact-selection table" "$TIERS" '| pytest-testmon |'
```

Part B: `plugins/dforge/tests/skill-split-planning.test.sh`. In the `MOVED` list, add the line `writing-plans:task-check-line` after `writing-plans:register-rows`. The loop then checks that the reference exists, that SKILL.md has exactly one line matching `^Read \[task-check-line\.md\](references/task-check-line\.md) before you .*\.$`, that the reference has no broken link, and the existing 20000-byte cap.

Part C: `plugins/dforge/tests/test-simplifier.test.sh`.

1. Add the tiers reference next to the other file paths: `TIERS="$P/reference/test-tiers.md"`.
2. In the existence loop, add it: `for f in "$SKILL" "$JUDGE" "$RUNNERS" "$TIERS"; do`.
3. Directly after the existence loop add:

```bash
# The impact-selection table lives in the shared tiers reference.
present "runners points to the tiers reference" "$RUNNERS" '[test-tiers.md](../../../reference/test-tiers.md)'
check "runners keeps no copy of the impact table" "$(grep -c 'pytest-testmon' "$RUNNERS")" "0"
present "the tiers reference holds the impact table" "$TIERS" '| `jest --changedSince=<base>` / `--onlyChanged` |'
```

The existing pin `plans keep e2e for user journeys` (`only for a new user journey` in writing-plans/SKILL.md) stays untouched.

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 600 bash plugins/dforge/tests/task-step-text.test.sh`
Expected: FAIL on every new row (`reference/test-tiers.md` and `task-check-line.md` do not exist; the template still reads `waves only`).

Run: `timeout 600 bash plugins/dforge/tests/skill-split-planning.test.sh`
Expected: FAIL on `writing-plans: task-check-line.md exists` and `SKILL.md links task-check-line.md once`.

Run: `timeout 600 bash plugins/dforge/tests/test-simplifier.test.sh`
Expected: FAIL on `exists: reference/test-tiers.md`, `runners points to the tiers reference`, `runners keeps no copy of the impact table` and `the tiers reference holds the impact table`.

- [ ] **Step 3: Implement**

1. **Create `plugins/dforge/reference/test-tiers.md`** (Contracts C6). It opens with `# Test tiers` and a short paragraph saying the three tiers split one project's test cost between the controller's per-task loop, the full run and CI. A `## The three tiers` section holds this table, with each tier named in the first cell exactly as below:

   | Tier | Command source | Runs |
   |---|---|---|
   | Task check | the plan header's `**Task check:**` line | beside every task review, every fix round, and inline before every task commit |
   | Full suite | the plan header's `**Integration check:**` line | each wave's merged check, tasks whose number is a multiple of 3 (and the last task) when the task check is `none`, the final review, the fix wave, finishing |
   | Sweep | the project's CI | after the push |

   A `## Impact selection` section holds the impact-selection table moved verbatim from `runners.md` (the seven rows from `pytest-testmon` to the Gradle build cache; the Jest row keeps the exact first cell `` `jest --changedSince=<base>` / `--onlyChanged` ``), with its closing note reworded to the tier names: selection serves the Task check tier only, and the Full suite and Sweep tiers still run what they declare, which is what catches a dependency the selector missed.
2. **Edit `plugins/dforge/skills/test-simplifier/references/runners.md`.** Replace the section `## Impact selection for the inner loop` (heading, table and closing note) with a `## Impact selection` heading and one sentence linking to `[test-tiers.md](../../../reference/test-tiers.md)`, which now holds the table. Leave every other section unchanged, and keep the heading so the `runners.md` links in `skills/test-simplifier/SKILL.md` still land on a section about impact selection.
3. **Create `plugins/dforge/skills/writing-plans/references/task-check-line.md`**, the resolution rule. It states, in this order, with the phrases below verbatim (the tests pin them):
   - `**Integration check:**` holds the full suite command on every plan, not only on a waves plan. It is the Full suite tier's command.
   - Choose the first that applies for `**Task check:**`: (1) a gate in `<docs>/gates.md` with `Tier: task`, its `Command`; (2) the full suite itself, when its last passing run in `suites.tsv` took 300 seconds or less, because tiering a fast suite saves nothing; (3) an impact-selection command for the runner the project uses, from [test-tiers.md](../../../reference/test-tiers.md) (examples: `npx jest --changedSince=main`, `pytest --testmon`, `vitest --changed main`); (4) `none — full suite every 3 tasks`, when none of those applies.
   - How to read the duration: read only rows of the checkout you run in, from `<state>/suites.tsv` where `<state>` is `scripts/dforge-path state`. A row matches when column 3 equals the quoted key suite-run records for `bash -c <cmd>` run from the top level, which is the output of `printf '%q ' bash -c '<cmd>'` without its trailing space. Take the last matching row whose column 4 is `0`, and read its column 7, the duration in seconds. A row that is missing, or has six columns and so no duration, counts as not fast.
   - End the line with `— <why>` naming which of the four rules chose it, for example `— gate 2 has Tier: task` or `— the full suite last passed in 212 s`.
   - A short note that plan-lint warns on a missing line and fails a malformed one (Contracts C3), and that the command is written as one code span.
4. **Edit `plugins/dforge/skills/writing-plans/SKILL.md`.** In the Plan Document Header template, replace the line `**Integration check:** [waves only: the command that proves a merged wave works, normally the full suite]` with two lines (blank line between), keeping the rest of the template in order:

   `**Task check:** [`<fast command>` — <why>, or `none — full suite every 3 tasks`]`

   `**Integration check:** [`<command>`: the full suite, on every plan]`

   Directly after the template's closing code fence, before the paragraph that starts `Codex plans also carry`, add the single line `Read [task-check-line.md](references/task-check-line.md) before you write the header's Task check and Integration check lines.` Do not touch the phrase `only for a new user journey`, the Wave check pins, or the Parallel waves rule 7. Check the size: `wc -c` must stay at or below 19439 bytes (net growth of at most 250), and the file must stay under the 20000-byte cap.

- [ ] **Step 4: Run test to verify it passes**

Run: `timeout 600 bash plugins/dforge/tests/task-step-text.test.sh && timeout 600 bash plugins/dforge/tests/skill-split-planning.test.sh && timeout 600 bash plugins/dforge/tests/test-simplifier.test.sh`
Expected: each ends with `0 failed`.

Run the other suites that pin writing-plans text, and the repository validation that resolves bundled links:

Run: `timeout 600 bash plugins/dforge/tests/parallel-grouping.test.sh && timeout 600 bash plugins/dforge/tests/process-roles.test.sh && timeout 600 bash plugins/dforge/tests/settings-skills.test.sh && timeout 600 node scripts/validate-repository.mjs`
Expected: each suite ends with `0 failed`; `validate-repository.mjs` exits 0.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/reference/test-tiers.md plugins/dforge/skills/writing-plans/references/task-check-line.md plugins/dforge/skills/writing-plans/SKILL.md plugins/dforge/skills/test-simplifier/references/runners.md plugins/dforge/tests/task-step-text.test.sh plugins/dforge/tests/skill-split-planning.test.sh plugins/dforge/tests/test-simplifier.test.sh
git commit -m "feat(dforge): write tier lines in plan headers"
```

### Task 5: Run the task check in the controller loops

**Files:**
- Modify: `plugins/dforge/reference/delegated-task.md` (§1 "Suite command" bullet and the `every start adds` clause, `:53` and `:74-83`; §2 "The suite runs beside the review", `:168-187`; §3 suite-line list, `:345-380`; §3a first bullet, `:497-516`; §4 "Every round, either way", `:608-616`; §5 completion rule, `:694-697`; "The steps by hand" §2, `:764-770`)
- Modify: `plugins/dforge/skills/executing-plans/SKILL.md` (The Task Loop step 4, `:283-285`)
- Modify: `plugins/dforge/skills/subagent-driven-development/references/implementer-prompt.md` (the sentence naming the controller's run, `:51-56`)
- Modify: `plugins/dforge/reference/final-review.md` (step 1 "Claude review", step 3 "Wait for QA", and the `**Suites.**` paragraph)
- Modify: `plugins/dforge/skills/finishing-a-development-branch/SKILL.md` (Step 1, the `suite-run -- <test command>` sentence only; the file sits near the 20,000-byte cap)
- Test: `plugins/dforge/tests/delegated-suite.test.sh`, `plugins/dforge/tests/final-phase.test.sh`
- Test (pins of changed wording, updated in place): `plugins/dforge/tests/task-step-text.test.sh:79`, `plugins/dforge/tests/speed-and-cost.acceptance.test.sh` (the A18 block, `:498-510`)
- Regression only, not modified: `plugins/dforge/tests/inline-mode.test.sh`, `plugins/dforge/tests/process-roles.test.sh`

**Interfaces:**
- Consumes: C2 (`task-step review --suite/--suite-base`, the `suite: not scheduled (next at Task <N>)` line) and C3 (`**Task check:**` and `**Integration check:**` header lines). Task 2 already makes `task-step` honour C2; this task only writes what the controller does with it.
- Produces: the controller wording the later tasks and `plugins/dforge/tests/delegated-suite.test.sh` pin; no new names.

**Items:** 1
**Implementer:** dforge:impl-opus-high
**Evaluation:** files 2 - spec 2 - coupling 1 - risk 2 = 7

- [ ] **Step 1: Extend the test `plugins/dforge/tests/delegated-suite.test.sh::task check and integration check rows`**

Edit 1, `plugins/dforge/tests/delegated-suite.test.sh`. Add two helpers directly under the existing `by_hand()` definition:

```bash
by_hand_flat() { sed -n '/^## The steps by hand/,/^## Recovery/p' "$DT" | tr -d '\r' | tr '\n' ' ' | tr -s ' ' | grep -cF -- "$1"; }
inline_flat() { tr -d '\r' < "$INLINE" | tr '\n' ' ' | tr -s ' ' | grep -cF -- "$1"; }
```

Edit 2, same file. Delete the line `check "inline mode keeps its full-suite-before-commit rule" ...` (it pins the sentence this task rewrites; the rows below replace it). Insert this block directly above the line `has "verdict reads the suite line: pass" ...`:

```bash
has "no Task check line: runs as today" in_loop_flat 'A plan with no `**Task check:**` line runs as it does today'
has "a command task check goes to every start" in_loop_flat 'A command task check is the suite command: every `task-step start` passes it, never the Integration check'
has "none on a sequential plan: start passes no --suite" in_loop_flat 'With a task check of `none` on a sequential plan, `start` passes no `--suite`'
has "none: scheduled by task number" in_loop_flat 'the integration check runs on every task whose number is a multiple of 3 and on the last task'
has "none: decided at review time" in_loop_flat 'The controller decides at review time'
has "none: review and review --group take the suite and its base" in_loop_flat '`task-step review` and `task-step review --group` take `--suite <integration check>` and `--suite-base <sha>`'
has "none: the base is the last full run" in_loop_flat '`<sha>` is the head of the last full-suite run, or the plan base before the first run'
has "none: an earlier regression is not excused" in_loop_flat 'a regression made by an earlier task is not excused as a base failure'
has "none: a missing base row costs one run" in_loop_flat 'when `suites.tsv` has no row at `<sha>`, `verdict` runs the suite once there'
has "none: a group with a scheduled task runs it" in_loop_flat 'A group runs the integration check when it holds a scheduled task'
has "none: a fix round follows its review" in_loop_flat 'A fix round runs a suite only when the review of its task did'
has "none on a waves plan: no per-task suite" in_loop_flat 'With a task check of `none` on a waves plan, no task gets a per-task suite'
has "an unscheduled task starts no suite" in_loop_flat 'starts no suite and runs `task-step review` without `--suite`'
has "a group suite waits for a scheduled member" in_loop_flat 'Under a `none` task check, start the group suite only when the group holds a scheduled task'
has "a fix head's suite follows its review's" in_loop_flat 'under a `none` task check, only when the review of its task ran a suite'
has "verdict reads the suite line: not scheduled" in_loop '`suite: not scheduled (next at Task <N>)`'
has "not scheduled: the line says why" in_loop_flat 'no suite was scheduled for this task'
has "completion accepts not scheduled" in_loop_flat 'a `suite:` line that is `pass`, `red` with 0 failing, `not scheduled` or `none recorded`'
has "by hand: the task check, and the none schedule" by_hand_flat 'and under a `none` task check the integration check on the tasks §1 schedules'
has "by hand: a none task compares with the last full run" by_hand_flat 'compare with `<sha>` from §1, not with the task base commit'
has "inline mode runs the task check before committing" inline_flat 'Run the focused test while you work and the task check once before committing, in place of the full suite.'
has "inline mode: none runs the integration check on multiples of 3 and the last task" inline_flat 'With a task check of `none`, run the integration check instead on tasks numbered a multiple of 3 and on the last task'
has "inline mode: no Task check line keeps the full suite" inline_flat 'A plan with no `**Task check:**` line keeps the full suite once before committing'
```

Edit 3, `plugins/dforge/tests/final-phase.test.sh`. Add under the last `says "final review: every lens-skipped line reaches the ledger" ...` line (the `says` helper is defined above it):

```bash
says "final review: the integration check starts beside the reviewers" "$FR" '**Integration check.** In the same message as the Claude review'
says "final review: it runs through suite-run" "$FR" $'through `bash <plugin-root>/scripts/suite-run -- bash -c \'<integration check>\'`'
says "final review: in the background at the review head" "$FR" 'as a background command at the same HEAD the Claude review reads'
says "final review: a failure the merge base shares is no finding" "$FR" 'A failing line that does not also fail at MERGE_BASE is a finding'
says "final review: the suite finding enters the fix wave as confirmed" "$FR" 'A `[suite]` finding enters the fix wave as confirmed, as a `[qa]` finding does'
says "final review: the fix wave waits for the integration check" "$FR" 'The fix wave also waits for the integration check started in step 1'
says "final review: the fix subagent runs the integration check in the same form" "$FR" $'Tell the fix subagent to run the plan\'s `**Integration check:**` command the same way, `bash <plugin-root>/scripts/suite-run -- bash -c \'<integration check>\'`'
says "finishing: Step 1 runs the integration check in the form the final review recorded" "$FIN" $'`bash <plugin-root>/scripts/suite-run -- bash -c \'<integration check>\'`, the form the final review recorded, so its pass is reused'
```

Edit 4, `plugins/dforge/tests/task-step-text.test.sh:79`. Replace the line

`names "the controller runs the full suite beside the review" "$IP" 'The controller runs the full suite beside the review of your'`

with

```bash
names "the controller runs the task check beside the review" "$IP" 'The controller runs the task check beside the review of your'
```

Edit 5, `plugins/dforge/tests/speed-and-cost.acceptance.test.sh`, the A18 block. Replace the lines from `rule='Run the focused test while you work and the full suite once before committing.'` through the `has "A18: the whole inline step 4 paragraph is unchanged" "$now" "$wrap"` line (inclusive) with:

```bash
    old_rule='Run the focused test while you work and the full suite once before committing.'
    new_rule='Run the focused test while you work and the task check once before committing, in place of the full suite.'
    old=$(git -C "$REPO_ROOT" show "$BASE:plugins/dforge/skills/executing-plans/SKILL.md" | tr -d '\r' | tr '\n' ' ' | tr -s ' ')
    has "A18: (control) the base executing-plans inline rule is the sentence this plan replaced" "$old" "$old_rule"
    now=$({ doc "$PLUGIN/skills/executing-plans/SKILL.md"; for r in "$PLUGIN"/skills/executing-plans/references/*.md; do doc "$r"; done; })
    has "A18: executing-plans tells the inline session to run the task check once before committing" "$now" "$new_rule"
    lacks "A18: executing-plans no longer asks for the full suite before every commit" "$now" "$old_rule"
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `timeout 600 bash plugins/dforge/tests/delegated-suite.test.sh`
Expected: FAIL on every row added in Edit 2 (23 `FAIL` lines, the first being `no Task check line: runs as today`); the pre-existing rows still print `ok`.

Run: `timeout 600 bash plugins/dforge/tests/final-phase.test.sh`
Expected: FAIL on the six rows added in Edit 3.

Run: `timeout 600 bash plugins/dforge/tests/task-step-text.test.sh`
Expected: FAIL on `the controller runs the task check beside the review`.

Run: `timeout 900 bash plugins/dforge/tests/speed-and-cost.acceptance.test.sh A18`
Expected: FAIL on the two `A18: executing-plans ...` rows; the control row prints `ok`.

- [ ] **Step 3: Implement**

Every pinned phrase in Step 1 must appear in the file named, with exactly that wording (line breaks may fall anywhere inside it, except `suite: not scheduled (next at Task <N>)`, which sits on one line). Keep every sentence that an existing pin matches. In `delegated-task.md` those are the `every start adds` clause, the `**Integration check:**` / `<docs>/gates.md` / project-manifest resolution sentences, the `Ruling: suite command` ruling, `runs only the focused tests that cover its change`, and everything in §2 that `delegated-suite.test.sh` and `speed-and-cost.acceptance.test.sh` A4 pin.

1. `plugins/dforge/reference/delegated-task.md`, §1 "Open the task with one call". In the parenthetical list, keep the words `every start adds` and `--suite '<suite command>'` and append `, unless the Suite command bullet says start passes none`.
2. Same file, §1 bullet **Suite command.** Rewrite it as a lead sentence (read the plan header's `**Task check:**` line first, then resolve the suite command once) followed by four sub-bullets. Each sub-bullet opens with the pinned sentence, verbatim:
   - `A plan with no `**Task check:**` line runs as it does today.` Then the existing resolution (Integration check line, else the gates file's test command, else the manifest) and the existing sentences about `start` recording `suite`, the first-start `Ruling:` line and the implementer running only focused tests, unchanged.
   - `A command task check is the suite command: every `task-step start` passes it, never the Integration check.` Then: the rest of the loop is unchanged.
   - `With a task check of `none` on a sequential plan, `start` passes no `--suite`.` Then, in this order: `The schedule is by task number: the integration check runs on every task whose number is a multiple of 3 and on the last task.` (the integration check is the command resolved as in the first sub-bullet); `The controller decides at review time, in the same turn it starts the run, because `start` runs before anyone knows whether the task will be held or grouped.`; for a scheduled task, `` `task-step review` and `task-step review --group` take `--suite <integration check>` and `--suite-base <sha>` `` (a group's go on its last member); ``<sha>` is the head of the last full-suite run, or the plan base before the first run.`` Then define both: the last full-suite run is the last row of `<state>/suites.tsv` (`dforge-path state`) whose command column is the key `suite-run` records for `bash -c '<integration check>'`, whatever its exit, and the plan base is the `base` in the plan's first task's step file; `So a regression made by an earlier task is not excused as a base failure.`; normally `suites.tsv` already holds a row at `<sha>`, so the comparison costs nothing, but ``when `suites.tsv` has no row at `<sha>`, `verdict` runs the suite once there`` (for example after a fix round), bounded at 3600 seconds (`TASK_STEP_BASE_TIMEOUT`); `A group runs the integration check when it holds a scheduled task.`; `A fix round runs a suite only when the review of its task did.`.
   - `With a task check of `none` on a waves plan, no task gets a per-task suite`, because the merged wave check is the suite of the wave's grouped tasks (§2). A command task check on a waves plan still runs per task in its worktree, as today.
3. Same file, §2. After the paragraph that ends `*The steps by hand* §2 starts the suite.`, add a paragraph: under a `none` task check, a task that §1's schedule skips starts no suite and runs `task-step review` without `--suite`; the scheduled task starts the integration check as this section describes and passes `--suite` and `--suite-base` to `task-step review`. The sentence must contain the pinned words `starts no suite and runs `task-step review` without `--suite``.
4. Same file, §3a first bullet. After `a wave's group gets none.`, add the sentence `Under a `none` task check, start the group suite only when the group holds a scheduled task, and pass `--suite` and `--suite-base` to `review --group`.`
5. Same file, §3 "The suite line". Add a bullet before the `suite: none recorded` bullet that begins on one line with `` - `suite: not scheduled (next at Task <N>)`: `` and goes on to say the plan's task check is `none` and no suite was scheduled for this task; `verdict` exits 0 and the task may complete. Leave the `none recorded` bullet as it is.
6. Same file, §4 "Every round, either way". After `start it at the new head as §2 says`, insert the parenthetical `(under a `none` task check, only when the review of its task ran a suite)`, keeping `has its own suite run beside its re-review` intact.
7. Same file, §5. Change the completion rule to read ``a `suite:` line that is `pass`, `red` with 0 failing, `not scheduled` or `none recorded` ``. Keep the following sentence about `not run` and `red`.
8. Same file, "The steps by hand" §2. Keep the three existing sentences. Change the sentence about `<suite command>` to read ``<suite command>` is resolved as §1's Suite command says: the task check, and under a `none` task check the integration check on the tasks §1 schedules.`` Add the sentence ``Under a `none` task check, compare with `<sha>` from §1, not with the task base commit.``
9. `plugins/dforge/skills/executing-plans/SKILL.md`, step 4. Keep the sentence about `Expected: PASS`. Replace the focused-test sentence with `Run the focused test while you work and the task check once before committing, in place of the full suite.` Then add, verbatim: ``With a task check of `none`, run the integration check instead on tasks numbered a multiple of 3 and on the last task.`` and ``A plan with no `**Task check:**` line keeps the full suite once before committing.`` Also say the task check is the plan header's `**Task check:**` line, read with `scripts/task-brief --header PLAN_FILE`.
10. `plugins/dforge/skills/subagent-driven-development/references/implementer-prompt.md`. In the sentence `The controller runs the full suite beside the review of your final commit`, replace `the full suite` with `the task check`. Change nothing else in the paragraph: the implementer still runs focused tests only and never the whole suite.
11. `plugins/dforge/reference/final-review.md`, step 1. After the first paragraph (ends `instead of re-deriving the branch diff with git commands.`), add a paragraph that begins `**Integration check.** In the same message as the Claude review` and says: start the plan header's `**Integration check:**` command through `` `bash <plugin-root>/scripts/suite-run -- bash -c '<integration check>'` `` as a background command at the same HEAD the Claude review reads, from the checkout's top level, at every depth and in either execution mode. Then, verbatim: `A failing line that does not also fail at MERGE_BASE is a finding`, found by running the command once at MERGE_BASE in a temporary worktree and comparing the failing lines, as [parallel-waves.md](parallel-waves.md) §1 does, and written `[suite] <failing line>`; ``A `[suite]` finding enters the fix wave as confirmed, as a `[qa]` finding does.`` The fix subagent runs the command again after its last commit through `suite-run` (the Suites paragraph below already says so), and finishing reuses a pass at the same commit. Do not edit the step 0 and 0.5 text, and keep the `Run scripts/review-package` and `scripts/lens-route PLAN_FILE --final` lines in their current order (`process-roles.test.sh` pins it).
12. `plugins/dforge/reference/final-review.md`, the `**Suites.**` paragraph. Replace the sentence that tells the fix subagent to run the project's full suite with the pinned sentence (`Tell the fix subagent to run the plan's `**Integration check:**` command the same way, `bash <plugin-root>/scripts/suite-run -- bash -c '<integration check>'``), followed by the existing words about running it after its last commit on a clean tree. suites.tsv keys `bash -c '<cmd>'` and `<cmd>` differently, so every run that should be reused must use the same form. Keep the rest of the paragraph.
13. `plugins/dforge/skills/finishing-a-development-branch/SKILL.md`, Step 1. In the sentence that runs the project's full test suite through `bash <plugin-root>/scripts/suite-run -- <test command>`, say that a plan with an `**Integration check:**` line runs it as the pinned phrase (`bash <plugin-root>/scripts/suite-run -- bash -c '<integration check>'`, the form the final review recorded, so its pass is reused) and that a plan without one keeps `suite-run -- <test command>`. Change nothing else in the file. Run `skill-size.test.sh`: when the file is over 20,000 bytes, shorten only the words this step added; if it is still over, stop and report BLOCKED with the byte count.
12. Same file, step 3. Under `**Wait for QA.**`, add the sentence `The fix wave also waits for the integration check started in step 1: end the turn and resume on its notification.` Keep the heading text `3. **Wait for QA.**`.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `timeout 600 bash plugins/dforge/tests/delegated-suite.test.sh`
Expected: `0 failed`.

Run: `timeout 600 bash plugins/dforge/tests/final-phase.test.sh`
Expected: `0 failed`.

Run: `timeout 600 bash plugins/dforge/tests/task-step-text.test.sh`
Expected: `0 failed`.

Run: `timeout 900 bash plugins/dforge/tests/speed-and-cost.acceptance.test.sh A3 A4 A5 A18`
Expected: `0 failed`.

Run, as a regression sweep over every suite that reads a file this task changed (the loop prints a `FAILED` line for any suite that exits non-zero):

```bash
out=$(mktemp)
for t in $(grep -l 'delegated-task.md\|final-review.md\|executing-plans\|implementer-prompt' plugins/dforge/tests/*.test.sh); do
  timeout 900 bash "$t" > "$out" 2>&1 || echo "FAILED $t"
  tail -n 1 "$out"
done
rm -f "$out"
```

Expected: no `FAILED` line. A suite that fails on a pin of wording this task changed is updated in place, never duplicated.

Run: `timeout 300 bash plugins/dforge/tests/skill-size.test.sh`
Expected: `0 failed`.

Run: `timeout 600 node scripts/validate-repository.mjs`
Expected: exit 0.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/reference/delegated-task.md plugins/dforge/skills/executing-plans/SKILL.md plugins/dforge/skills/subagent-driven-development/references/implementer-prompt.md plugins/dforge/reference/final-review.md plugins/dforge/skills/finishing-a-development-branch/SKILL.md plugins/dforge/tests/delegated-suite.test.sh plugins/dforge/tests/final-phase.test.sh plugins/dforge/tests/task-step-text.test.sh plugins/dforge/tests/speed-and-cost.acceptance.test.sh
git commit -m "feat(dforge): run a task check in the task loops"
```

### Task 6: Add Tier and Budget to gates

**Files:**
- Modify: `plugins/dforge/skills/running-gates/SKILL.md` (the manifest format list `:26-46` and step 3 "Select the gates", `:98-101`)
- Modify: `plugins/dforge/skills/running-gates/references/gates-template.md` (the intro sentence and gates 1 to 3)
- Test: `plugins/dforge/tests/gates-manifest.test.sh` (extended in place, including the format check's awk field list)

**Interfaces:**
- Consumes: C5 (`Tier:` and `Budget:` fields, the exact skip line).
- Produces: the documented `Tier` and `Budget` fields that Task 4 (writing-plans reads a `Tier: task` gate), Task 9 (closing-a-milestone reads `Budget:`) and Task 11 (running-gates reuses a ci-mirror pass) rely on. The skip line is `gate <n> (<title>): skipped — Tier sweep runs in CI`.

**Items:** 1
**Implementer:** dforge:impl-sonnet-high
**Evaluation:** files 1 - spec 2 - coupling 1 - risk 1 = 5

- [ ] **Step 1: Extend the test `plugins/dforge/tests/gates-manifest.test.sh::optional fields and template format`**

Edit 1, `plugins/dforge/tests/gates-manifest.test.sh`. Add a folded-line helper under the existing `absent()` definition:

```bash
present_flat() { # present_flat <name> <file> <needle> — the file with line breaks folded
  if tr -d '\r' < "$2" | tr '\n' ' ' | tr -s ' ' | grep -qF -- "$3"; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       missing: [%s]\n       in: [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
```

Edit 2, same file. Change the comment `# Two required fields and seven optional ones.` to `# Two required fields and nine optional ones.`, then change the optional-field loop and the count pin to:

```bash
for f in Applies Evidence Repo Setup Teardown Known-flaky Why Tier Budget; do
  present "optional field $f" "$SKILL" "**\`$f\`**"
done
present "gates says nine optional fields" "$SKILL" 'Optional, nine of them'
```

(the old `present "gates says seven optional fields" ...` line is deleted).

Edit 3, same file. Add these rows under the `present "milestone closure runs every gate" ...` line:

```bash
present_flat "Tier takes task, branch or sweep" "$SKILL" '**`Tier`:** `task`, `branch` or `sweep`. Absent means `branch`'
present_flat "a manifest without Tier means what it meant before" "$SKILL" 'a manifest written before the field means what it meant before'
present_flat "task and branch gates run alike, in order" "$SKILL" 'this skill runs `task` and `branch` gates alike, in manifest order'
present_flat "a sweep gate is skipped with one line" "$SKILL" 'this skill skips it and prints `gate <n> (<title>): skipped — Tier sweep runs in CI`'
present_flat "step 3 skips a sweep gate" "$SKILL" 'A `sweep` gate is not selected'
present_flat "Budget takes seconds" "$SKILL" '**`Budget`:** `<seconds>s`, for example `Budget: 900s`'
present_flat "Budget is read on the integration-check gate only" "$SKILL" 'read only on the gate whose `Command` equals the `**Integration check:**` command of the plan'
```

Edit 4, same file, the template section. Change the awk `BEGIN` field list to include the two new names and validate their values. Replace `split("Command Green Applies Evidence Repo Setup Teardown Known-flaky Why", f, " ")` with `split("Command Green Applies Evidence Repo Setup Teardown Known-flaky Why Tier Budget", f, " ")`, change the comment above the awk (`a Field: line with one of the nine names`) to `eleven names`, and add these two blocks inside the `/^[A-Za-z-]+:/` rule, after the `Evidence` block:

```awk
    if (name == "Tier") {
      v = $0; sub(/^Tier:[ \t]*/, "", v); sub(/[ \t]+$/, "", v)
      if (v != "task" && v != "branch" && v != "sweep") print "bad tier: " v
    }
    if (name == "Budget") {
      v = $0; sub(/^Budget:[ \t]*/, "", v); sub(/[ \t]+$/, "", v)
      if (v !~ /^[0-9]+s$/) print "bad budget: " v
    }
```

Edit 5, same file. Add under `present "template carries a blank skeleton" "$TPL" ...`:

```bash
present "template says nine optional fields" "$TPL" 'the nine optional ones'
present "template shows a task-tier gate" "$TPL" 'Tier: task'
present "template shows a sweep gate" "$TPL" 'Tier: sweep'
present "template shows a budget" "$TPL" 'Budget: 900s'
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `timeout 300 bash plugins/dforge/tests/gates-manifest.test.sh`
Expected: FAIL on `optional field Tier`, `optional field Budget`, `gates says nine optional fields`, the seven `present_flat` rows and the four template rows; `template satisfies the documented format` still prints `ok`.

- [ ] **Step 3: Implement**

1. `plugins/dforge/skills/running-gates/SKILL.md`, manifest format. Change the optional bullet to `Optional, nine of them:` on the same line, extend its list with **`Tier`** and **`Budget`** (each in the `**\`Name\`**` form the loop matches), and keep every existing field description. Add two bullets after the `Setup`/`Teardown` bullet:
   - **`Tier`:** `task`, `branch` or `sweep`. Absent means `branch`, so a manifest written before the field means what it meant before. A `task` gate is the kind dforge:writing-plans offers as a plan's `**Task check:**`; this skill runs `task` and `branch` gates alike, in manifest order. A `sweep` gate belongs to CI: this skill skips it and prints `gate <n> (<title>): skipped — Tier sweep runs in CI`.
   - **`Budget`:** `<seconds>s`, for example `Budget: 900s`. It is read only on the gate whose `Command` equals the `**Integration check:**` command of the plan; this skill ignores it, and dforge:closing-a-milestone compares the full suite's duration with it.
2. Same file, Steps, item 3 "Select the gates". Add, starting with these exact words: `A `sweep` gate is not selected`; print the one line from the `Tier` bullet for it, so its absence is not a silent skip. A `task` or `branch` gate, or a gate with no `Tier`, is selected by `Applies` exactly as before.
3. `plugins/dforge/skills/running-gates/references/gates-template.md`. Change the intro to say `the nine optional ones are` and list `Tier` and `Budget` last (keep `the nine optional ones` on one line). Add `Tier: task` to gate 1 (Build), `Budget: 900s` to gate 2 (Layout suite) and `Tier: sweep` to gate 3 (Script-schema corpus sweep), one line each, in the field block of the gate. Leave gate 4 and the two fenced blocks without a `Tier` line.

- [ ] **Step 4: Run the test to verify it passes**

Run: `timeout 300 bash plugins/dforge/tests/gates-manifest.test.sh`
Expected: `0 failed`.

Run: `timeout 300 bash plugins/dforge/tests/process-roles.test.sh`
Expected: `0 failed` (it pins the template's `claude-security` example).

Run: `timeout 600 node scripts/validate-repository.mjs`
Expected: exit 0.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/skills/running-gates/SKILL.md plugins/dforge/skills/running-gates/references/gates-template.md plugins/dforge/tests/gates-manifest.test.sh
git commit -m "feat(dforge): add Tier and Budget to gates"
```

### Task 7: Lint and plan the three Step 1 forms

**Files:**
- Modify: `plugins/dforge/scripts/plan-lint` (a new `# --- Step 1 forms ---` section between the parallel-waves section and the `# --- UI/UX contract` section)
- Create: `plugins/dforge/skills/writing-plans/references/test-step-forms.md`
- Modify: `plugins/dforge/skills/writing-plans/SKILL.md` (inside the Task Structure template: the paragraph that starts `Step 1's test sits at the lowest layer`, `:327-331`; `SKILL.md` sits near the 20,000-byte cap, so the three forms live in the new reference and `SKILL.md` gains only one `Read` line)
- Test: `plugins/dforge/tests/plan-lint.test.sh` (rows built from the existing `claude_plan` and `waves_plan` fixtures)
- Test: `plugins/dforge/tests/process-roles.test.sh` (wording pins in the "contract-and-test plan shape" block, which defines `says` and `lacks`)
- Test: `plugins/dforge/tests/skill-split-planning.test.sh` (one row of its `MOVED` list)

**Interfaces:**
- Consumes: C4 (the three Step 1 headings, the three exact errors, "has a test step" and "runs before"). Reuses `$nums`, `$parallelism`, `plan_waves` and `$_PLAN_AWK` from `plan-lint` and `scripts/lib/plan.sh`.
- Produces: the three errors of C4, printed as `ERROR Task <M>: Covered by Task <N> — <reason>`, and the template text Task 8's plan-review rule and later plans rely on.

**Items:** 2
**Implementer:** dforge:impl-opus-high
**Evaluation:** files 2 - spec 2 - coupling 1 - risk 1 = 6

- [ ] **Step 1: Extend the test `plugins/dforge/tests/plan-lint.test.sh::Step 1 forms`**

Edit 1, `plugins/dforge/tests/plan-lint.test.sh`. Insert this block directly above the `# --- documents kept in darkmem: Spec paths resolve in the mirror ---` comment (after the waves rows, so `waves_plan` and `claude_plan` exist). It adds five lint runs and no new fixture file:

```bash
# --- Step 1 forms ---
step1() { # step1 <Task 1 heading text> <Task 2 heading text> — the Claude plan with both Step 1 headings replaced
  claude_plan | sed -E \
    -e "s#^- \[ \] \*\*Step 1: Write it\*\*\$#- [ ] **Step 1: $1**#" \
    -e "s#^- \[ \] \*\*Step 1: Mark the .+ column\*\*\$#- [ ] **Step 1: $2**#"
}
with_steps() { # with_steps <Task 1 heading> <Task 2 heading> <Task 3 heading> — a Step 1 line after each Evaluation line of the three-task plan on stdin
  S1=$1 S2=$2 S3=$3 awk '/^\*\*Evaluation:\*\*/ { n++; print; print ""; print "- [ ] **Step 1: " ENVIRON["S" n] "**"; next } { print }'
}
step1 'Write the failing test' $'Covered by Task 1\'s test `first`' > cov-ok.md
lint cov-ok.md
lacks "Step 1 forms: Write the failing test and a Covered by Task earlier in order are accepted" "$out" "Covered by Task"
step1 $'Covered by Task 2\'s test `second`' 'Extend the test `t/b.test.sh::second`' > cov-late.md
lint cov-late.md
has "Covered by a later task: it does not run before" "$out" "ERROR Task 1: Covered by Task 2 — Task 2 does not run before Task 1"
lacks "an Extend step counts as a test step" "$out" "Task 2 has no test step"
waves_plan 'sequential — one chain' | with_steps 'Write the failing test' $'Covered by Task 7\'s test `a`' $'Covered by Task 2\'s test `b`' > cov-seq.md
lint cov-seq.md --no-probe
has "Covered by a missing task" "$out" "ERROR Task 2: Covered by Task 7 — no such task"
has "Covered by a task with no test step" "$out" "ERROR Task 3: Covered by Task 2 — Task 2 has no test step"
lacks "a sequential plan: a lower task number runs before" "$out" "Task 3: Covered by Task 2 — Task 2 does not run before"
waves_plan 'waves — 1 | 2-3' | with_steps 'Write the failing test' 'Extend the test `t/b.test.sh::second`' $'Covered by Task 2\'s test `second`' > cov-wave.md
lint cov-wave.md --no-probe
has "a waves plan: Covered by a task in the same wave" "$out" "ERROR Task 3: Covered by Task 2 — Task 2 does not run before Task 3"
lacks "a waves plan: the covered task has a test step" "$out" "Task 2 has no test step"
waves_plan 'waves — 1 | 2 | 3' | with_steps 'Write the failing test' 'Extend the test `t/b.test.sh::second`' $'Covered by Task 2\'s test `second`' > cov-wave-ok.md
lint cov-wave-ok.md --no-probe
lacks "a waves plan: Covered by a task in an earlier wave is accepted" "$out" "Covered by Task"
```

Edit 2, `plugins/dforge/tests/process-roles.test.sh`. Add above the final `printf '\n%d passed, ...` line (the pins read the new reference file):

```bash
WPF="$P/skills/writing-plans/references/test-step-forms.md"
says "writing-plans forms: Step 1 takes one of three forms" "$WPF" 'Step 1 takes one of three forms'
says "writing-plans forms: the Extend form heading" "$WPF" '- [ ] **Step 1: Extend the test `<file>::<name>`**'
says "writing-plans forms: the Covered by form heading" "$WPF" $'- [ ] **Step 1: Covered by Task <N>\'s test `<name>`**'
says "writing-plans forms: Covered by is for behaviour-free tasks only" "$WPF" 'only for a task that adds no new observable behaviour'
says "writing-plans forms: a task adding behaviour uses Extend" "$WPF" 'A task that adds behaviour uses Extend'
says "writing-plans forms: a Covered by task names the fault" "$WPF" $'The step names the fault in this task\'s code that the test would catch'
says "writing-plans forms: a Covered by task writes no test of its own" "$WPF" 'The task has no step that writes its own failing test, and its verification runs the covering test'
says "writing-plans forms: tests are planned per behaviour" "$WPF" 'Plan tests per behaviour: one test per acceptance statement or behaviour, at the lowest layer that can fail for it, rather than one per task'
says "writing-plans forms: the Extend step must fail first" "$WPF" 'it must fail before the implementation, as a new test would'
```

Edit 3, `plugins/dforge/tests/skill-split-planning.test.sh`. In the `MOVED` list, add the line `writing-plans:test-step-forms` directly after `writing-plans:task-check-line` (Task 4's row). The loop then requires `references/test-step-forms.md`, exactly one line in `SKILL.md` matching `^Read \[test-step-forms\.md\](references/test-step-forms\.md) before you .*\.$`, no broken link in the new file, and `SKILL.md` at or under 20,000 bytes.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `timeout 1800 bash plugins/dforge/tests/plan-lint.test.sh`
Expected: FAIL on `Covered by a later task: it does not run before`, `Covered by a missing task`, `Covered by a task with no test step` and `a waves plan: Covered by a task in the same wave` (plan-lint prints none of the C4 errors yet); the five `lacks` rows, which only forbid a finding, print `ok`, as do all earlier rows.

Run: `timeout 300 bash plugins/dforge/tests/process-roles.test.sh`
Expected: FAIL on the nine `writing-plans forms:` rows added above (the reference does not exist yet).

Run: `timeout 300 bash plugins/dforge/tests/skill-split-planning.test.sh`
Expected: FAIL on the `writing-plans:test-step-forms` rows.

- [ ] **Step 3: Implement**

1. `plugins/dforge/scripts/plan-lint`, new section `# --- Step 1 forms ---` placed after the `elif [ -n "$wave_check" ]` block that ends the parallel-waves section and before `# --- UI/UX contract`. Keep it to one awk pass over `$src`, because this suite is already slow on Windows and every extra subprocess per task is paid there:
   - One awk pass over `"$src"` using `"$_PLAN_AWK"` (`in_fence` and `is_task`, as the placeholders section does). It prints `<task number><TAB><heading text>` for the first unfenced line of each task that matches `^- \[[ xX]\] \*\*Step 1: ` , where the heading text is what follows `Step 1: ` up to the closing `**`. A task with no such line prints nothing.
   - Classify each printed heading in bash. `write`: the text starts with `Write the failing test`. `extend`: it starts with ``Extend the test ` ``. `covered`: it matches ``Covered by Task <digits>'s test ` `` (capture the digits as the cited task `N`). Anything else is neither, and raises no finding: the existing fixtures use `Write it` and similar headings.
   - Only a `covered` task `M` can raise errors, in task order. For its cited `N`, with `say ERROR "Task $M" "<text>"` and the exact text from C4: `Covered by Task <N> — no such task` when `N` is not in `$nums` (then stop checking this task); `Covered by Task <N> — Task <N> has no test step` when Task `N`'s class is neither `write` nor `extend` (a task with no Step 1 line counts as neither); `Covered by Task <N> — Task <N> does not run before Task <M>` when `N` does not run before `M`. The last two are independent: both may print for one task.
   - "Runs before": when `$parallelism` is not `waves`, `N` runs before `M` only if `N` < `M`. When it is `waves`, call `plan_waves "$src"` once, find each task's wave with awk (`$2 <= n && n <= $3`), and require wave(`N`) < wave(`M`). When `plan_waves` fails, or a task has no wave, skip this check: the waves section already reported that defect.
   - A plan with no `Covered by` heading adds no output and runs no extra subprocess beyond the one awk pass.
2. Create `plugins/dforge/skills/writing-plans/references/test-step-forms.md`, opening with an H2 heading `## The three Step 1 forms`, holding, one fact per sentence:
   - `Step 1 takes one of three forms.` The first, `- [ ] **Step 1: Write the failing test**`, is for a behaviour no existing or planned test reaches.
   - The second, `- [ ] **Step 1: Extend the test `<file>::<name>`**`, is for a variant of a behaviour already tested, or new behaviour that belongs in an existing test. The step gives the added row, case or assertion in full, and it must fail before the implementation, as a new test would. Steps 2 and 4 run that test.
   - The third, ``- [ ] **Step 1: Covered by Task <N>'s test `<name>`**``, applies only for a task that adds no new observable behaviour: wiring, extraction or configuration whose result an earlier task's test exercises end to end. A task that adds behaviour uses Extend. The step names the fault in this task's code that the test would catch. The task has no step that writes its own failing test, and its verification runs the covering test. The plan reviewer judges such a task's Executability by the named fault. plan-lint fails a `Covered by Task <N>` when Task `<N>` does not exist, has no test step of its own, or does not run before the citing task.
   - `Plan tests per behaviour: one test per acceptance statement or behaviour, at the lowest layer that can fail for it, rather than one per task.` Keep the existing sentences that say to plan an end-to-end test only for a new user journey, never for an edge case a unit or integration test reaches (`test-simplifier.test.sh` pins `only for a new user journey`), and to add a variant of an existing test as a row in its table.
3. `plugins/dforge/skills/writing-plans/SKILL.md`, inside the Task Structure template (the `````markdown` fence). Keep the heading line `- [ ] **Step 1: Write the failing test**`, its code block and Steps 2 to 5. In the paragraph `Step 1's test sits at the lowest layer ... dforge:test-simplifier's job.`, keep the sentences that say to plan an end-to-end test only for a new user journey, never for an edge case a unit or integration test reaches (`test-simplifier.test.sh` pins `only for a new user journey`), and to add a variant of an existing test as a row in its table. Below that paragraph, outside the fence, add the one line `Read [test-step-forms.md](references/test-step-forms.md) before you write a task's Step 1.` The file must stay at or under 20,000 bytes; when it is over, shorten only text this task added, and if it is still over, stop and report BLOCKED with the byte count.
   Do not touch the header block, the Parallel waves section or any other task's anchors in this file.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `timeout 1800 bash plugins/dforge/tests/plan-lint.test.sh`
Expected: `0 failed`.

Run: `timeout 300 bash plugins/dforge/tests/process-roles.test.sh`
Expected: `0 failed`.

Run: `timeout 300 bash plugins/dforge/tests/test-simplifier.test.sh`
Expected: `0 failed`.

Run: `timeout 300 bash plugins/dforge/tests/skill-split-planning.test.sh` and `timeout 300 bash plugins/dforge/tests/skill-size.test.sh`
Expected: both `0 failed`.

Run: `timeout 300 bash plugins/dforge/scripts/plan-lint docs/dforge/plans/2026-10-31-test-tiers-and-ci-parity.md --no-probe`
Expected: no output line contains `Covered by Task`. A line that does is a defect in a task of this plan: fix that task's Step 1 citation.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/scripts/plan-lint plugins/dforge/skills/writing-plans/SKILL.md plugins/dforge/skills/writing-plans/references/test-step-forms.md plugins/dforge/tests/plan-lint.test.sh plugins/dforge/tests/process-roles.test.sh plugins/dforge/tests/skill-split-planning.test.sh
git commit -m "feat(dforge): lint and plan three Step 1 forms"
```

### Task 8: Rewrite the TDD, plan-review and lens test rules

**Files:**
- Modify: `plugins/dforge/skills/test-driven-development/SKILL.md` (the "Minimal" row of the `## Good Tests` table, `:208`; `### REFACTOR - Clean Up`, `:190-198`)
- Modify: `plugins/dforge/skills/test-driven-development/references/writing-good-tests.md` (Principle 1 and its Gate Function block, `:20-79`)
- Modify: `plugins/dforge/criteria/plan-review.md` (inside the Executability criterion; no new heading)
- Modify: `plugins/dforge/criteria/lenses/test-quality.md` (a fourth criterion, `{#redundant}`)
- Modify: `plugins/dforge/reference/final-review.md` (a paragraph in "Fixing what it finds")
- Test: `plugins/dforge/tests/process-roles.test.sh` (rows in the "contract-and-test plan shape" block)
- Regression only, not modified: `plugins/dforge/tests/criteria.test.sh`, `plugins/dforge/tests/test-simplifier.test.sh`, `plugins/dforge/tests/final-phase.test.sh`

**Interfaces:**
- Consumes: C4's `Covered by Task <N>'s test` form (Task 7 wrote it into writing-plans); the REFACTOR rule it cites.
- Produces: the plan-review "Redundant test" rule and the `{#redundant}` lens id that `reference/final-review.md` and the fix wave refer to. `criteria.test.sh` pins both criteria files: `plan-review.md` keeps exactly the four ids `assumptions coherence coverage executability` and four headings, so the new plan-review rule is a paragraph inside Executability, never a heading; `test-quality.md` may hold at most four criteria; both files stay ASCII only (plain hyphens, no em dash).

**Items:** 2, 3
**Implementer:** dforge:impl-sonnet-high
**Evaluation:** files 2 - spec 2 - coupling 0 - risk 1 = 5

- [ ] **Step 1: Extend the test `plugins/dforge/tests/process-roles.test.sh::plan-review, TDD and lens rules`**

Edit 1, `plugins/dforge/tests/process-roles.test.sh`. Add above the final `printf '\n%d passed, ...` line (the `says`, `lacks` helpers and the `PR`, `FR` variables are defined above it):

```bash
TDD="$P/skills/test-driven-development/SKILL.md"
WGT="$P/skills/test-driven-development/references/writing-good-tests.md"
LENS="$P/criteria/lenses/test-quality.md"
says "TDD: the Minimal row is replaced by the one-behaviour rule" "$TDD" '| **One behaviour** | Variants of one behaviour are rows of one parametrized or table-driven test; distinct behaviours get distinct tests. |'
lacks "TDD: the Minimal row is gone" "$TDD" '| **Minimal** |'
says "TDD REFACTOR: a branch test may go for a broader branch test" "$TDD" 'Delete a test written on this branch when a broader test written on this branch fails for every fault the narrower one catches'
says "TDD REFACTOR: the commit body names the faults" "$TDD" 'The commit body names those faults'
says "TDD REFACTOR: only tests absent at the merge base" "$TDD" $'covers only tests that do not exist at the branch\'s merge base'
says "TDD REFACTOR: never a regression test" "$TDD" 'never a regression test that names a fixed bug'
says "TDD REFACTOR: older tests go to test-simplifier" "$TDD" 'A test that predates the branch goes through dforge:test-simplifier'
says "good tests: find an existing test that fails for the change" "$WGT" 'After naming the change, find whether an existing test already fails for it. If one does, extend it, or write no test.'
says "good tests: the gate function asks the same" "$WGT" 'An existing test already fails for it'
says "plan review: Redundant test scores LOW under Executability" "$PR" 'Redundant test: score LOW when a planned test fails for no fault that an existing test or another planned test does not already catch'
says "plan review: the reviewer names the overlapping test" "$PR" 'name the overlapping test in the finding'
says "plan review: a Covered by task is judged by its named fault" "$PR" 'judge its Executability by the fault the step names'
check "plan review: Redundant test is no fifth criterion" "$(grep -c '^### ' "$PR")" "4"
names "lens: the redundant criterion" "$LENS" '### Redundant Tests {#redundant}'
says "lens: a redundant branch test names its cover" "$LENS" 'report one that fails for no fault that another branch test or an existing test does not also catch, and name the test that covers it'
says "final review: the fix wave deletes only branch tests" "$FR" 'The fix wave may delete only a test added on the branch, a test that does not exist at MERGE_BASE'
says "final review: never a regression test" "$FR" 'never a regression test that names a fixed bug'
says "final review: older tests are test-simplifier's" "$FR" 'a test that exists at MERGE_BASE is left for dforge:test-simplifier'
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `timeout 300 bash plugins/dforge/tests/process-roles.test.sh`
Expected: FAIL on every row added above except `plan review: Redundant test is no fifth criterion`, which prints `ok` before and after the change and guards the `criteria.test.sh` contract; the first failure is `TDD: the Minimal row is replaced by the one-behaviour rule`.

- [ ] **Step 3: Implement**

1. `plugins/dforge/skills/test-driven-development/SKILL.md`, `## Good Tests` table. Replace the `**Minimal**` row with a `**One behaviour**` row whose Good cell reads `Variants of one behaviour are rows of one parametrized or table-driven test; distinct behaviours get distinct tests.` and whose Bad cell keeps the existing `test('validates email and domain and whitespace')` example and adds `or copy-pasted tests that differ only in their input`. Keep the other three rows (`test-simplifier.test.sh` pins `**Lowest layer**`).
2. Same file, `### REFACTOR - Clean Up`. Keep the four existing bullets (the fold-into-the-sibling's-table bullet is pinned by `test-simplifier.test.sh`) and add a fifth bullet: `Delete a test written on this branch when a broader test written on this branch fails for every fault the narrower one catches`. After the list add a paragraph: `The commit body names those faults.` The rule covers only tests that do not exist at the branch's merge base (`git merge-base <default branch> HEAD`), and never a regression test that names a fixed bug. `A test that predates the branch goes through dforge:test-simplifier.` Write the pinned phrases exactly: `covers only tests that do not exist at the branch's merge base`, `never a regression test that names a fixed bug`.
3. `plugins/dforge/skills/test-driven-development/references/writing-good-tests.md`. In Principle 1, after the paragraph that begins `Before writing the test body` (it ends `or broken contract.`) and before `**Derive expectations independently.**`, add a paragraph: `After naming the change, find whether an existing test already fails for it. If one does, extend it, or write no test.` In the Gate Function block, directly under `Name the production change that would make this test fail.`, add the lines `Find whether an existing test already fails for that change.` and an indented outcome line whose text includes `An existing test already fails for it` and says to extend that test, or write none.
4. `plugins/dforge/criteria/plan-review.md`, inside the Executability criterion's paragraph, before `Ignore whether the spec is covered; Coverage owns that.` Add two sentences, ASCII only: `Redundant test: score LOW when a planned test fails for no fault that an existing test or another planned test does not already catch, as for a test that cannot fail, and name the overlapping test in the finding.` and `A task whose Step 1 reads "Covered by Task <N>'s test" has no test of its own: judge its Executability by the fault the step names, and score LOW when it names none or the cited test would not catch it.` Add no `###` heading and no `{#...}` id.
5. `plugins/dforge/criteria/lenses/test-quality.md`. After `### Missing Cases {#missing}`, add `### Redundant Tests {#redundant}` with one paragraph, ASCII only: among the tests added or changed on the branch, `report one that fails for no fault that another branch test or an existing test does not also catch, and name the test that covers it`; say the fix is to merge the tests into a row of a table or delete the redundant one; and ignore tests that cannot fail, which the first criterion owns.
6. `plugins/dforge/reference/final-review.md`, "Fixing what it finds". After the `**Acceptance tests.**` paragraph, add a paragraph that begins `**Redundant tests.**`: a `[lens:test-quality]` finding on a redundant test goes to the fix wave, which merges the tests into a row of one table or deletes the redundant one; `The fix wave may delete only a test added on the branch, a test that does not exist at MERGE_BASE`, under the REFACTOR rule in dforge:test-driven-development, and `never a regression test that names a fixed bug`; `a test that exists at MERGE_BASE is left for dforge:test-simplifier`; the commit body names the faults the covering test catches. Keep the `3. **Wait for QA.**`, `scripts/lens-route` and `Never one fixer per finding` text untouched.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `timeout 300 bash plugins/dforge/tests/process-roles.test.sh`
Expected: `0 failed`.

Run: `timeout 300 bash plugins/dforge/tests/criteria.test.sh`
Expected: `0 failed` (four plan-review ids, `test-quality` at four criteria with unique ids, both files ASCII).

Run: `timeout 300 bash plugins/dforge/tests/test-simplifier.test.sh`
Expected: `0 failed` (`into the sibling's table as a row` and `**Lowest layer**` still present).

Run: `timeout 600 bash plugins/dforge/tests/final-phase.test.sh`
Expected: `0 failed`.

Run: `timeout 300 bash plugins/dforge/tests/skill-size.test.sh`
Expected: `0 failed`.

Run: `timeout 600 node scripts/validate-repository.mjs`
Expected: exit 0.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/skills/test-driven-development/SKILL.md plugins/dforge/skills/test-driven-development/references/writing-good-tests.md plugins/dforge/criteria/plan-review.md plugins/dforge/criteria/lenses/test-quality.md plugins/dforge/reference/final-review.md plugins/dforge/tests/process-roles.test.sh
git commit -m "docs(dforge): add redundant-test rules"
```

### Task 9: Recommend scoped cleanup and scope test-simplifier

**Files:**
- Modify: `plugins/dforge/skills/closing-a-milestone/SKILL.md` (a new step "8. **Suite cost.**" between "7. **Owner sign-off.**" and the final step, which becomes "9. **Next.**")
- Modify: `plugins/dforge/skills/finishing-a-development-branch/references/execute-choice.md` ("Option 1: Merge Locally": the code block's last comment and command, and the prose under it). `SKILL.md` of that skill is at 19262 of 20000 bytes and stays untouched.
- Modify: `plugins/dforge/skills/test-simplifier/SKILL.md` (Phase 2's quarantine sentence, Phase 3, a new `## Scope` section, a new `## Division of labour` section, Phase 4's candidate list, the Red Flags row that names the full sweep)
- Test: `plugins/dforge/tests/project-status.test.sh` (closing-a-milestone and finishing pins)
- Test: `plugins/dforge/tests/test-simplifier.test.sh` (tier, scope, class 6 and division-of-labour pins)

**Interfaces:**
- Consumes: C1 (the seventh `suites.tsv` column is the duration in seconds; a six-column row has no duration), C3 (`**Integration check:**` is the full-suite command), C5 (`Budget: <seconds>s` on the gate whose `Command` equals the plan's Integration check; `Tier: task`), C6 (`plugins/dforge/reference/test-tiers.md` defines the tiers `Task check`, `Full suite` and `Sweep` and holds `## Impact selection`; an earlier task of this plan creates it).
- Produces: finishing's merged-result verification records one full-suite row per merge head in the main checkout, under the key `bash -c '<full suite command>'` (C1 column 3); closing-a-milestone's `Suite cost:` report lines; test-simplifier's `--modules <paths>` and `--since <ref>` scope, candidate class 6 "Subsumed scaffolding", and the tier names of C6 in Phase 3.

**Items:** 3, 4
**Implementer:** dforge:impl-opus-high
**Evaluation:** files 2 - spec 2 - coupling 1 - risk 1 = 6

- [ ] **Step 1: Write the failing test**

In `plugins/dforge/tests/project-status.test.sh`, add the block below immediately before the line `# --- finishing resolves register rows ---`. It adds one helper, `says`, which matches a phrase after folding line breaks, so a pin survives a re-wrap.

```bash
# --- the suite-cost audit and the merge rows it reads (test tiers plan, part 3) ---
FINREF="$P/skills/finishing-a-development-branch/references/execute-choice.md"
says() { # says <name> <file> <needle> — the file with line breaks folded
  if tr '\n' ' ' < "$2" | tr -s ' ' | grep -qF -- "$3"; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       missing: [%s]\n       in: [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
step_line() { awk -v p="$1" 'index($0, p) == 1 { print NR; exit }' "$CLOSE"; }
s7=$(step_line '7. **Owner sign-off.**'); s8=$(step_line '8. **Suite cost.**'); s9=$(step_line '9. **Next.**')
check "closing: the suite audit sits between sign-off and Next" \
  "$([ -n "$s7" ] && [ -n "$s8" ] && [ -n "$s9" ] && [ "$s7" -lt "$s8" ] && [ "$s8" -lt "$s9" ] && echo yes || echo no)" "yes"
says "closing: reads suites.tsv of the checkout it runs in" "$CLOSE" 'reads `suites.tsv` from the state directory of the checkout it runs in'
says "closing: names that checkout in the report" "$CLOSE" 'names that checkout in the report'
says "closing: a six-column row has no duration" "$CLOSE" 'A six-column row has no duration and is skipped'
says "closing: fewer than two rows recommends nothing" "$CLOSE" 'With fewer than two rows it says so and recommends nothing.'
says "closing: growth of 20% or more recommends the cleanup" "$CLOSE" 'grew by 20% or more'
says "closing: a passed budget recommends the cleanup" "$CLOSE" 'passes a declared `Budget:`'
says "closing: the budget sits on the integration-check gate" "$CLOSE" 'whose `Command` equals the plan'
says "closing: no such gate means the 20% rule only" "$CLOSE" 'When no such gate exists, the audit uses the 20% rule only.'
says "closing: the recommendation is scoped to the milestone's modules" "$CLOSE" 'dforge:test-simplifier --modules <paths>'
says "closing: it recommends and removes nothing" "$CLOSE" 'It recommends only and removes nothing.'
says "closing: the rows come from finishing's merge verification" "$CLOSE" 'leaves one full-suite row at each merge head'
says "finishing: the merged result runs through suite-run as bash -c" "$FINREF" "bash <plugin-root>/scripts/suite-run -- bash -c '<full suite command>'"
says "finishing: the command is the plan's Integration check" "$FINREF" 'is the `**Integration check:**` command of the plan being finished'
says "finishing: the suite runs whether or not gates are declared" "$FINREF" 'runs whether or not the project declares gates'
says "finishing: one full-suite row per merge head" "$FINREF" 'leaves one full-suite row for each merge head'
says "finishing: the milestone audit reads those rows" "$FINREF" 'dforge:closing-a-milestone reads these rows'
```

In `plugins/dforge/tests/test-simplifier.test.sh`, add the block below after the `# Routing and regrowth.` checks and before the line `# scripts/test-profile against fixture reports.`.

```bash
# Test tiers plan, part 4: the skill uses the tier names of reference/test-tiers.md,
# takes a scope, lists candidate class 6 and says who cleans up what.
says() { # says <name> <file> <needle> — the file with line breaks folded
  if tr '\n' ' ' < "$2" | tr -s ' ' | grep -qF -- "$3"; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       missing: [%s]\n       in: [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
gone() { # gone <name> <file> <needle> — absent, ignoring case
  if tr '\n' ' ' < "$2" | tr -s ' ' | grep -qiF -- "$3"; then printf 'FAIL - %s\n       unexpected: [%s]\n       in: [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1))
  else printf 'ok   - %s\n' "$1"; pass=$((pass + 1)); fi
}
for tier in 'Task check' 'Full suite' 'Sweep'; do
  present "phase 3 names the tier: $tier" "$SKILL" "| $tier |"
done
for old in 'Inner loop' 'Branch gate' 'full sweep'; do
  gone "the old tier name is gone: $old" "$SKILL" "$old"
done
present "phase 3 takes its tier sources from the shared reference" "$SKILL" '[test-tiers.md](../../reference/test-tiers.md)'
says "phase 3 proposes a gates.md diff" "$SKILL" 'as a diff to `<docs>/gates.md`'
says "phase 3 proposes a Tier: task gate" "$SKILL" 'a gate with `Tier: task`'
says "phase 3 proposes a Budget line" "$SKILL" 'a `Budget: <seconds>s` line on the gate whose `Command` equals'
says "scope: --modules" "$SKILL" '`--modules <paths>`'
says "scope: the closing-a-milestone recommendation passes the modules" "$SKILL" 'the dforge:closing-a-milestone recommendation passes the milestone'
says "scope: --since" "$SKILL" '`--since <ref>`'
says "scope: phase 1 still profiles the whole suite" "$SKILL" 'Phase 1 still profiles the whole suite'
says "scope: phase 4 waves stay inside the scope" "$SKILL" 'Phase 4 waves take candidates only from inside the scope'
present "candidate class 6" "$SKILL" '6. **Subsumed scaffolding.**'
says "class 6 uses the same evidence" "$SKILL" 'uses the same evidence as every other class'
present "division of labour heading" "$SKILL" '## Division of labour'
says "branch tests go to the REFACTOR step and the lens" "$SKILL" 'Tests added on the current branch are merged or removed by the REFACTOR step of dforge:test-driven-development and the `test-quality` lens of the final review'
says "this skill handles the default branch's tests" "$SKILL" 'This skill handles tests already on the default branch.'
```

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 300 bash plugins/dforge/tests/project-status.test.sh; timeout 300 bash plugins/dforge/tests/test-simplifier.test.sh`
Expected: FAIL lines for every pin added above (no suite-cost step, no `bash -c` merge command, old tier names still present, no scope, no class 6); every pin that existed before still prints `ok`. The `exists: reference/test-tiers.md` check passes once the earlier task that creates the file has run.

- [ ] **Step 3: Implement**

1. **`closing-a-milestone/SKILL.md`, after step 7.** Add `8. **Suite cost.**` and renumber the existing `8. **Next.**` to `9. **Next.**`; nothing else in the file changes (step 6's "go to step 7" stays). The new step says, in this order:
   1. It runs after `roadmap close`, in the checkout the skill runs in: the main checkout, which holds the rows because finishing's merged-result verification leaves one full-suite row at each merge head. A plan's own worktree rows are gone with the worktree.
   2. The audit reads `suites.tsv` from the state directory of the checkout it runs in (`bash <plugin-root>/scripts/dforge-path state`). The full-suite command is the `**Integration check:**` command of the plans the milestone merged, else the project's full test command. A row counts when column 2 is `clean`, column 4 is `0`, column 3 equals the key suite-run writes for `bash -c '<command>'` run from the top level (`printf '%q ' bash -c '<command>'` without the trailing space), and column 7 is a non-negative integer. A six-column row has no duration and is skipped.
   3. `<d1>` is the duration of the last counted row whose HEAD (column 1) is the milestone's head, the commit step 5 gave the judge, or one of its ancestors (`git merge-base --is-ancestor`). `<d0>` is the duration of the last counted row at or before the previous milestone's close: the sha7 in that milestone's `closed` note in `scripts/roadmap status`; with no previous milestone, the oldest counted row. With fewer than two counted rows, or when both resolve to the same row, the step prints `Suite cost: <state>/suites.tsv of <checkout top level> holds <n> full-suite row(s) with a duration; two are needed, so nothing is recommended.` and recommends nothing. The sentence "With fewer than two rows it says so and recommends nothing." appears in the step, and so does "This is the expected answer until two plans have merged under this version."
   4. Otherwise it prints `Suite cost: <state>/suites.tsv of <checkout top level>: <d0>s at <sha7> to <d1>s at <sha7> (<change>%).` The audit names that checkout in the report.
   5. It recommends the cleanup when the full suite grew by 20% or more (`<d1> * 100 >= <d0> * 120` and `<d1> > <d0>`) or passes a declared `Budget:`. The budget is the `Budget: <seconds>s` line of the gate in `<docs>/gates.md` whose `Command` equals the plan's `**Integration check:**`, byte for byte; passing it means `<d1>` is above the seconds. When no such gate exists, the audit uses the 20% rule only.
   6. The recommendation is the line `Next: dforge:test-simplifier --modules <paths>`, with `<paths>` the distinct directories of the files outside `<docs>` in `git diff --name-only <previous close sha7>..<milestone head>` (the root commit when there is no previous milestone). It recommends only and removes nothing.
   Keep the step to about 25 lines; the file must stay far below the 20,000-byte cap.
2. **`execute-choice.md`, Option 1.** In the code block, keep the line `# Verify the merged result: gates when the project declares a manifest` exactly as it is, and keep `PRE_MERGE=$(git rev-parse HEAD)` (`gates-manifest.test.sh` pins both). Rewrite the comment lines after it so they say: dforge:running-gates runs first when a manifest exists, with the sha printed above as its base; the full suite then runs through suite-run in every case. Replace the final command with `bash <plugin-root>/scripts/suite-run -- bash -c '<full suite command>'`. Under the code block add a paragraph saying: `<full suite command>` is the `**Integration check:**` command of the plan being finished, else the project's test command; `bash -c` keeps the row's key the one writing-plans, task-step and ci-mirror look up; the suite runs whether or not the project declares gates, and suite-run reuses a pass a gate already recorded at this HEAD; the run in the main checkout leaves one full-suite row for each merge head; and dforge:closing-a-milestone reads these rows. The failure paragraph ("If tests fail on the merged result: stop…") stays as it is.
3. **`test-simplifier/SKILL.md`.**
   1. Remove every use of the old tier names, in any case: Phase 2's "still runs in the full sweep" becomes "still runs in the Sweep tier"; its closing sentence "take the inner loop from hours to minutes" becomes "take the task check from hours to minutes"; Phase 3's table and prose are rewritten as items 2 and 3 say, including its sentence about moving a slow layer out of "the branch gate", which now says "the Full suite tier"; the Red Flags row's "Moving it to the full sweep keeps it" becomes "Moving it to the Sweep tier keeps it". After the edit none of "inner loop", "branch gate" or "full sweep" remains in the file.
   2. Phase 3 keeps its heading, "Nothing is deleted.", the sentence "apply them only on approval" and the sentence containing "deletion in disguise" (reworded to "A Sweep that no longer runs anywhere is a deletion in disguise"). Its table has the rows `| Task check |` (tests affected by the change set, or the fast layers: beside every task review and before each task commit), `| Full suite |` (everything the plan's Integration check names: wave checks, the final review, the fix wave, finishing) and `| Sweep |` (slow layers and quarantine included: in CI after push, or nightly). The opening sentence links `[test-tiers.md](../../reference/test-tiers.md)` as the source of the tier names and of the impact-selection table; the skill no longer points at `runners.md` for impact selection.
   3. Phase 3's proposal paragraph says: propose the tiers to your human partner as a diff to `<docs>/gates.md`: a gate with `Tier: task` and a `Why:` for the Task check, and a `Budget: <seconds>s` line on the gate whose `Command` equals the plan's `**Integration check:**`; add one line for `CLAUDE.md` or `AGENTS.md` naming the task-check command; apply them only on approval.
   4. Add `## Scope` before `## Phase 1. Measure`: the skill takes an optional scope. `--modules <paths>` limits the run to those paths (the dforge:closing-a-milestone recommendation passes the milestone's modules). `--since <ref>` limits it to tests added after the ref: the test files `git diff --diff-filter=A --name-only <ref>..HEAD` lists and the cases added to existing test files. With a scope, Phase 1 still profiles the whole suite, and Phase 4 waves take candidates only from inside the scope.
   5. Add `6. **Subsumed scaffolding.**` to the Candidates list: a narrow test whose every fault a broader test of the same behaviour also catches, typically written first to drive a unit and kept after a wider test landed. It uses the same evidence as every other class (mutation runs, or named faults applied as patches, plus the judge verdict) and the never-removed list applies unchanged.
   6. Add `## Division of labour` after `## Scope`: Tests added on the current branch are merged or removed by the REFACTOR step of dforge:test-driven-development and the `test-quality` lens of the final review. This skill handles tests already on the default branch.
   Every existing heading and every pin already in `test-simplifier.test.sh` stays satisfied.

- [ ] **Step 4: Run test to verify it passes**

Run, from the repository root:
- `timeout 300 bash plugins/dforge/tests/project-status.test.sh`
- `timeout 300 bash plugins/dforge/tests/test-simplifier.test.sh`
- `timeout 300 bash plugins/dforge/tests/gates-manifest.test.sh` (pins `PRE_MERGE=$(git rev-parse HEAD)` and "gates when the project declares a manifest" in the finishing view)
- `timeout 300 bash plugins/dforge/tests/task-step-text.test.sh`
- `timeout 300 bash plugins/dforge/tests/skill-size.test.sh`
- `timeout 120 node scripts/validate-repository.mjs`

Expected: PASS, `0 failed` in every suite.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/skills/closing-a-milestone/SKILL.md plugins/dforge/skills/finishing-a-development-branch/references/execute-choice.md plugins/dforge/tests/project-status.test.sh
git commit -m "feat(dforge): audit suite growth at milestone close"
git add plugins/dforge/skills/test-simplifier/SKILL.md plugins/dforge/tests/test-simplifier.test.sh
git commit -m "feat(dforge): tier and scope test-simplifier"
```

### Task 10: Describe CI parity and write the CI line

**Files:**
- Create: `plugins/dforge/reference/ci-parity.md`
- Create: `plugins/dforge/skills/writing-plans/references/ci-line.md` (`skills/writing-plans/SKILL.md` is at 19189 of 20000 bytes, so the CI rules live here and `SKILL.md` gains only the template line and one `Read` line)
- Modify: `plugins/dforge/skills/writing-plans/SKILL.md` (the header template, directly above its `**Worktree setup:**` line; one `Read [ci-line.md](references/ci-line.md) before you …` line under the Execution-line `Read` line)
- Modify: `plugins/dforge/skills/brainstorming/references/auto-by-default.md` (step 1 and step 5)
- Test: `plugins/dforge/tests/auto-default.test.sh`
- Test: `plugins/dforge/tests/skill-split-planning.test.sh` (one row of its `MOVED` list)

**Interfaces:**
- Consumes: C3 (`**CI:**` and `**Early CI:**` grammar, exactly as the Contracts give it), C6 (`ci-parity.md` headings and the `| Platform | Pitfall | Do instead |` table whose Platform cells are exactly `Windows Git Bash`, `macOS`, `uutils (ubuntu-latest)`), C8 (ledger lines are Task 12's; not written here).
- Produces: `reference/ci-parity.md` (C6); the writing-plans rule that fills the `**CI:**` line, copies each uncovered platform's Pitfalls rows into `## Global Constraints`, and writes `**Early CI:**` only with consent; the spec `## Decisions` line `Early CI: none` or `Early CI: <first|midway> — consented <YYYY-MM-DD>`, which writing-plans resolves into the header point (`first` is `after wave 1` on a waves plan and `after task 1` on a sequential plan; `midway` is `after wave <ceil(waves/2)>` or `after task <ceil(tasks/2)>`). `uncovered:` in the CI line lists names from the Platform column, comma-separated, or `none`.

**Items:** 5
**Implementer:** dforge:impl-opus-high
**Evaluation:** files 2 - spec 2 - coupling 1 - risk 1 = 6

- [ ] **Step 1: Write the failing test**

In `plugins/dforge/tests/auto-default.test.sh`, add the block below immediately before the line `# Docs pointers and test cleanups: pointers name the file that holds their target.`. It uses `names`, `says`, `check`, `P` and `W`, all defined above that line.

```bash
# CI parity (test tiers plan, part 5): the reference, the plan header's CI line,
# the early-CI offer and the spec review's question.
CIP="$P/reference/ci-parity.md"
CIL="$P/skills/writing-plans/references/ci-line.md"
ABD="$P/skills/brainstorming/references/auto-by-default.md"
check "ci-parity.md exists" "$([ -s "$CIP" ] && echo yes || echo no)" "yes"
for h in '## Finding the CI configuration' '## Reading jobs, platforms and commands' '## Pitfalls'; do
  names "ci-parity.md: $h" "$CIP" "$h"
done
says "ci-parity.md: the search order" "$CIP" '`.github/workflows/*.yml` first, then `.gitlab-ci.yml`, `azure-pipelines.yml`, `.circleci/config.yml`'
names "ci-parity.md: the table columns" "$CIP" '| Platform | Pitfall | Do instead |'
rows_for() { # rows_for <platform> — Pitfalls rows whose Platform cell is exactly <platform>
  awk -F'|' -v p="$1" '
    /^## / { on = ($0 == "## Pitfalls"); next }
    on && /^\|/ { c = $2; gsub(/^ +| +$/, "", c); if (c == p) n++ }
    END { print n + 0 }' "$CIP"
}
check "ci-parity.md: five Windows Git Bash rows" "$(rows_for 'Windows Git Bash')" "5"
check "ci-parity.md: three macOS rows" "$(rows_for macOS)" "3"
check "ci-parity.md: two uutils rows" "$(rows_for 'uutils (ubuntu-latest)')" "2"
check "ci-parity.md: the table holds those ten rows and no other" \
  "$(awk '/^## / { on = ($0 == "## Pitfalls"); next } on && /^\|/ { n++ } END { print n + 0 }' "$CIP")" "12"
pit=$(awk '/^## / { on = ($0 == "## Pitfalls"); next } on' "$CIP")
for needle in 'MSYS_NO_PATHCONV' 'dr_native_path' '/c/' 'C:/' "tr -d '\\r'" 'ENVIRON' 'pathToFileURL' \
              'sed -i' 'date -d' 'readlink -f' 'mkdir' 'timeout'; do
  case $pit in *"$needle"*) got=yes ;; *) got=no ;; esac
  check "ci-parity.md Pitfalls names $needle" "$got" "yes"
done
says "ci-parity.md: uncovered means the host is not that platform" "$CIP" 'A platform is uncovered when the host running dforge is not that platform.'
says "ci-parity.md: uutils is covered only by a uutils host" "$CIP" 'only when `cp --version` names uutils'
says "ci-parity.md: only workflow_dispatch workflows start early" "$CIP" '`workflow_dispatch`'

names "writing-plans: the header template has a CI line" "$W" '**CI:** '
says "writing-plans: the CI line grammar" "$CIL" '`<workflow files>` — platforms: <list> — local: `<cmd>`; `<cmd>` — uncovered: <platforms or none>'
says "writing-plans: none when no CI configuration is found" "$CIL" 'write `**CI:** none` when no CI configuration is found'
says "writing-plans: uncovered names come from the Platform column" "$CIL" '`uncovered:` lists names from the Platform column of the Pitfalls table'
says "writing-plans: uncovered platforms copy their pitfalls rows" "$CIL" "copy that platform's rows of the Pitfalls table in [ci-parity.md](../../../reference/ci-parity.md) into \`## Global Constraints\`"
says "writing-plans: the early-CI offer needs an uncovered platform" "$CIL" 'Offer the early CI run only when the CI line names an uncovered platform'
says "writing-plans: the owner's answer is the consent" "$CIL" "your human partner's answer is the consent"
says "writing-plans: the early-CI wave form" "$CIL" '**Early CI:** after wave <k> — consented <YYYY-MM-DD>'
says "writing-plans: the early-CI task form" "$CIL" '**Early CI:** after task <n> — consented <YYYY-MM-DD>'
says "writing-plans: an auto run copies the recorded decision" "$CIL" 'ask nothing and copy the `Early CI:` line of the spec'"'"'s `## Decisions`'
says "writing-plans: first and midway resolve to a point" "$CIL" '`first` is `after wave 1` on a waves plan and `after task 1` on a sequential plan'
says "writing-plans: no line without an uncovered platform" "$CIL" 'Write no `**Early CI:**` line when every platform is covered'

says "brainstorming: the spec phase reads the CI configuration" "$ABD" 'read the CI configuration as [ci-parity.md](../../../reference/ci-parity.md) says'
says "brainstorming: the early-CI question needs an uncovered platform" "$ABD" 'when the CI configuration has an uncovered platform, ask whether to run CI early on the pushed branch'
says "brainstorming: the no-run option is recommended" "$ABD" 'No early run (Recommended)'
says "brainstorming: the answer goes to Decisions" "$ABD" 'record the answer in `## Decisions` as `Early CI: none` or `Early CI: <first|midway> — consented <YYYY-MM-DD>`'
says "brainstorming: the answer is the consent for the push and dispatch" "$ABD" 'the answer is the consent for the push and the workflow dispatch'
```

In `plugins/dforge/tests/skill-split-planning.test.sh`, extend the `MOVED` list with the row `writing-plans:ci-line` (after `writing-plans:execution-handoff`). That row's three existing checks then require `references/ci-line.md`, one line `Read [ci-line.md](references/ci-line.md) before you …` in `SKILL.md`, no broken link in the new file, and `SKILL.md` at or under 20,000 bytes.

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 300 bash plugins/dforge/tests/auto-default.test.sh; timeout 300 bash plugins/dforge/tests/skill-split-planning.test.sh`
Expected: FAIL for `ci-parity.md exists`, every `ci-parity.md …` pin, every `writing-plans: …` CI pin, every `brainstorming: …` early-CI pin, and the three `writing-plans: ci-line exists / links / has no broken link` rows. All earlier checks print `ok`.

- [ ] **Step 3: Implement**

1. **`reference/ci-parity.md`.** Three `##` sections, in this order.
   1. `## Finding the CI configuration`: the sentence "`.github/workflows/*.yml` first, then `.gitlab-ci.yml`, `azure-pipelines.yml`, `.circleci/config.yml`." and what to do when none exists (the plan's CI line is `none`). Name the first configuration found as the project's CI; when several workflow files exist, read every one.
   2. `## Reading jobs, platforms and commands`: how to read each job's platform (GitHub `runs-on` with matrix values expanded, GitLab `image` or runner tags, Azure `pool.vmImage`, CircleCI executor), mapped to the Platform names of the table below: `windows-*` is `Windows Git Bash`, `macos-*` is `macOS`, `ubuntu-latest` is `uutils (ubuntu-latest)`; other images have no row. Local platform: `uname -s` reading `Linux` is a GNU Linux host, `Darwin` is macOS, `MINGW*`/`MSYS*` is Git Bash on Windows. The sentence "A platform is uncovered when the host running dforge is not that platform." The sentence "The host covers `uutils (ubuntu-latest)` only when `cp --version` names uutils." How to read the commands: from each job's `run:` or `script:` steps keep the lines that test, validate or build and that this host can run without secrets or services; drop checkout, setup, install, cache and upload steps; list a command once however many platforms run it; a multi-line block gives one command per test or validation line. Note whether the workflow's `on:` declares `workflow_dispatch`, because only such a workflow can be started early.
   3. `## Pitfalls`: one lead sentence, then the table `| Platform | Pitfall | Do instead |` with exactly ten rows: the Platform cell of each is exactly `Windows Git Bash` (5 rows), `macOS` (3) or `uutils (ubuntu-latest)` (2). Each row states one fact in a sentence and one remedy in a sentence:
      - Windows Git Bash, `MSYS_NO_PATHCONV` and native tools: a native program (`git.exe`, `jq.exe`) given a path built from `$PWD`, `$(pwd)` or `$TMPDIR` gets a POSIX form it cannot open, or has its argument rewritten when path conversion is on. Do instead: convert with `cygpath -m` before the call (dforge's `dr_native_path`, `plugins/dforge/scripts/lib/native-path.sh`), and feed `jq` a file on stdin in a script that exports `MSYS_NO_PATHCONV`.
      - Windows Git Bash, `/c/` against `C:/`: the same directory is `/c/Users/x` in the shell and `C:/Users/x` from a native tool, so a string comparison never matches. Do instead: normalise both sides with `cygpath -m`, or compare with `-ef`.
      - Windows Git Bash, CR stripping: files a Windows tool wrote, and native program output, end lines with `\r`, which `read`, `awk` and `[ = ]` keep. Do instead: pipe through `tr -d '\r'` before comparing or parsing.
      - Windows Git Bash, gawk `-v` escapes: `awk -v name=value` processes backslash escapes in the value, so a regex or Windows path changes. Do instead: pass the value in the environment and read `ENVIRON["NAME"]`.
      - Windows Git Bash, ESM drive-letter imports: Node's `import()` of an absolute `D:/x/y.mjs` reads `d:` as a URL scheme and fails. Do instead: `import(pathToFileURL(path).href)`.
      - macOS, BSD `sed -i`: it requires a suffix argument, so GNU's `sed -i 's/a/b/' file` fails. Do instead: write a temporary file and `mv` it.
      - macOS, BSD `date`: it has no `date -d`. Do instead: `date -r <epoch>` for epoch input, or compute the value in awk or Node.
      - macOS, `readlink -f`: BSD `readlink` lacks `-f` before macOS 12.3. Do instead: `cd "$(dirname "$p")" && pwd -P`.
      - uutils (ubuntu-latest), non-exclusive `mkdir`: a lock built on `mkdir` failing when the directory exists does not exclude a second process. Do instead: create the lock file with `set -C` (noclobber) or use `flock`.
      - uutils (ubuntu-latest), `timeout`: it signals only the command it started, so the command's children keep running. Do instead: run the command in its own process group (`setsid`) and signal the group.
2. **`writing-plans/references/ci-line.md`.** Its sections: the CI line, the Global Constraints copy, the Early CI line. It states:
   1. Read the CI configuration as ci-parity.md says, then fill the header line `**CI:**` on every plan: write `**CI:** none` when no CI configuration is found, else the C3 form, with the exact grammar text `` `<workflow files>` — platforms: <list> — local: `<cmd>`; `<cmd>` — uncovered: <platforms or none> ``. `uncovered:` lists names from the Platform column of the Pitfalls table, comma-separated, or `none`. The `local:` commands are the ones ci-parity.md says to keep, one code span each, separated by `; `.
   2. For every uncovered platform, copy that platform's rows of the Pitfalls table in `[ci-parity.md](../../../reference/ci-parity.md)` into `## Global Constraints`, one line per row, so every task brief carries them (the sentence in that exact form: "copy that platform's rows of the Pitfalls table in [ci-parity.md](../../../reference/ci-parity.md) into `## Global Constraints`").
   3. The Early CI line: "Offer the early CI run only when the CI line names an uncovered platform." Attended, ask with the multiple-choice prompt after the plan's task count and waves are known, with the options `No early run (Recommended)`, the first point and the midway point, each named as a concrete point (`after wave <k>` on a waves plan, `after task <n>` on a sequential plan), and say that an early run pushes the branch and starts the workflow but never opens a pull request; your human partner's answer is the consent. A point other than "No early run" is written as `**Early CI:** after wave <k> — consented <YYYY-MM-DD>` or `**Early CI:** after task <n> — consented <YYYY-MM-DD>`, with today's date. In an auto run (`scripts/auto-run status` exits 0) ask nothing and copy the `Early CI:` line of the spec's `## Decisions`: `Early CI: none` writes no line; `Early CI: <first|midway> — consented <date>` writes the header line with that date, where `first` is `after wave 1` on a waves plan and `after task 1` on a sequential plan, and `midway` is `after wave <ceil(waves/2)>` or `after task <ceil(tasks/2)>`. A spec with no such decision writes no line. Write no `**Early CI:**` line when every platform is covered.
3. **`writing-plans/SKILL.md`.** In the header template add a line directly above `**Worktree setup:**`: `**CI:** [none, or the line ci-line.md builds from the CI configuration]`. Under the existing `Read [execution-line.md](references/execution-line.md) before you write the header's Execution line.` add the paragraph `Read [ci-line.md](references/ci-line.md) before you write the header's CI line and its Early CI line.` The net growth stays under 250 bytes; run the two size checks in Step 4.
4. **`brainstorming/references/auto-by-default.md`.** Step 1 gains one sentence: while writing the spec, read the CI configuration as [ci-parity.md](../../../reference/ci-parity.md) says, so the spec review can tell whether a platform is uncovered. Step 5's bullet list gains one bullet, placed before the `Finish:` bullet: when the CI configuration has an uncovered platform, ask whether to run CI early on the pushed branch, with the options `No early run (Recommended)`, `After the first wave or task` and `Midway through the plan`; record the answer in `## Decisions` as `Early CI: none` or `Early CI: <first|midway> — consented <YYYY-MM-DD>`; the answer is the consent for the push and the workflow dispatch. Existing lines of the file are not re-wrapped (other pins read them).
5. **`skill-split-planning.test.sh`:** the `MOVED` row from Step 1.

- [ ] **Step 4: Run test to verify it passes**

Run, from the repository root:
- `timeout 300 bash plugins/dforge/tests/auto-default.test.sh`
- `timeout 300 bash plugins/dforge/tests/skill-split-planning.test.sh`
- `timeout 300 bash plugins/dforge/tests/skill-size.test.sh`
- `timeout 120 node scripts/validate-repository.mjs`

Expected: PASS, `0 failed` in each.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/reference/ci-parity.md plugins/dforge/skills/writing-plans/references/ci-line.md plugins/dforge/skills/writing-plans/SKILL.md plugins/dforge/skills/brainstorming/references/auto-by-default.md plugins/dforge/tests/auto-default.test.sh plugins/dforge/tests/skill-split-planning.test.sh
git commit -m "feat(dforge): describe CI parity and the CI line"
```

### Task 11: Mirror CI locally with ci-mirror

**Files:**
- Create: `plugins/dforge/scripts/ci-mirror` (executable)
- Create: `plugins/dforge/tests/ci-mirror.test.sh`
- Modify: `scripts/test-shards.mjs` (a `windowsSeconds` entry for the new suite)
- Modify: `plugins/dforge/reference/final-review.md` (step `0. **Gates.**`)
- Modify: `plugins/dforge/skills/running-gates/SKILL.md` (step 4)
- Test: `plugins/dforge/tests/gates-manifest.test.sh` (the final-review and running-gates pins)

**Interfaces:**
- Consumes: C1 (suite-run's `suites.tsv` rows), C3 (the `**CI:**` grammar), C7 (this task implements it), C8 (none written here). `plugins/dforge/scripts/suite-run` (usage `suite-run [--timeout SECONDS] -- COMMAND [ARG ...]`; its first output line starting `suite: ` is the verdict; it reuses a clean pass at the same HEAD for the same key) and `plan_header_line FILE NAME` from `plugins/dforge/scripts/lib/plan.sh`.
- Produces: `bash <plugin-root>/scripts/ci-mirror PLAN_FILE` exactly as C7 states (digest `ci: <cmd> — <verdict>`, then `uncovered: <platforms or none>`; `ci: none` for `none`; exit 0, 1 or 2); final-review step 0 runs it before the gates; running-gates reports a gate whose `Command` equals a ci-mirror command that passed at this HEAD as passed from that record.

**Items:** 5
**Implementer:** dforge:impl-opus-high
**Evaluation:** files 2 - spec 2 - coupling 1 - risk 1 = 6

- [ ] **Step 1: Write the failing test**

Create `plugins/dforge/tests/ci-mirror.test.sh`:

```bash
#!/usr/bin/env bash
# ci-mirror runs the local commands of a plan's **CI:** line through suite-run,
# prints one digest line per command and the uncovered platforms, and exits
# non-zero when a command fails or cannot launch. Every case works in a
# throwaway git repository; HOME points into the temporary directory.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MIRROR="$HERE/../scripts/ci-mirror"

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
has() { # has <name> <text> <needle>
  case $2 in
    *"$3"*) printf 'ok   - %s\n' "$1"; pass=$((pass + 1)) ;;
    *) printf 'FAIL - %s\n       missing: [%s]\n       in:      [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)) ;;
  esac
}

TMP=$(mktemp -d)
if command -v cygpath >/dev/null 2>&1; then TMP=$(cygpath -m "$TMP"); fi
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
mkdir -p "$HOME"
export MSYS_NO_PATHCONV=1

REPO="$TMP/repo"
git init -q -b main "$REPO"
git -C "$REPO" config user.name Tester
git -C "$REPO" config user.email tester@example.com
printf 'one\n' > "$REPO/a.txt"
git -C "$REPO" add a.txt
git -C "$REPO" commit -q -m one
commit() { printf '%s\n' "$1" >> "$REPO/a.txt"; git -C "$REPO" commit -q -am "$1"; }

export PROBE_RUNS="$TMP/runs"
runs() { if [ -f "$PROBE_RUNS" ]; then wc -l < "$PROBE_RUNS" | tr -d ' '; else echo 0; fi; }
mirror() { # mirror <plan file> — stdout in $out, stderr in $err, exit code in $rc
  out=$(cd "$REPO" && timeout 120 bash "$MIRROR" "$@" 2>"$TMP/err" < /dev/null); rc=$?
  err=$(cat "$TMP/err")
}
rows() { wc -l < "$REPO/.dforge/suites.tsv" | tr -d ' '; }
key_of() { sed -n "${1}p" "$REPO/.dforge/suites.tsv" | tr -d '\r' | cut -f3; }

# --- a plan whose CI line is none --------------------------------------------
printf '# P\n\n**Spec:** `s.md`\n\n**CI:** none\n\n### Task 1: One\n\nbody\n' > "$TMP/none.md"
mirror "$TMP/none.md"
check "none exits 0" "$rc" "0"
check "none prints ci: none and nothing else" "$out" "ci: none"
check "none runs nothing through suite-run" "$([ -e "$REPO/.dforge/suites.tsv" ] && echo yes || echo no)" "no"

# --- local commands run through suite-run ----------------------------------------
cat > "$TMP/ci.md" <<'EOF'
# P

**Spec:** `s.md`

**CI:** `.github/workflows/validate.yml` — platforms: ubuntu-latest, windows-latest — local: `echo ran >> "$PROBE_RUNS"`; `true` — uncovered: Windows Git Bash, macOS

## Global Constraints

- c

### Task 1: One

body
EOF
HEAD1=$(git -C "$REPO" rev-parse HEAD)
mirror "$TMP/ci.md"
check "a passing mirror exits 0" "$rc" "0"
check "one digest line per command, then the uncovered platforms" "$out" "$(printf '%s\n' \
  'ci: echo ran >> "$PROBE_RUNS" — pass (exit 0)' \
  'ci: true — pass (exit 0)' \
  'uncovered: Windows Git Bash, macOS')"
check "each command is one suite-run row" "$(rows)" "2"
want=$(printf '%q ' bash -c 'echo ran >> "$PROBE_RUNS"'); want=${want% }
check "the first row is keyed as bash -c of the command" "$(key_of 1)" "$want"
check "the second row is keyed as bash -c of the command" "$(key_of 2)" "bash -c true"
check "the first command ran once" "$(runs)" "1"

mirror "$TMP/ci.md"
check "a repeat at the same HEAD exits 0" "$rc" "0"
check "a repeat reuses both passes" "$(printf '%s\n' "$out" | grep -c "reused pass at ${HEAD1:0:7} (")" "2"
check "a reuse runs nothing" "$(runs)" "1"
check "a reuse records no row" "$(rows)" "2"

commit two
mirror "$TMP/ci.md"
check "a new HEAD runs the commands again" "$(runs)" "2"

# --- commands run from the top level, whatever the caller's directory ----------------
commit three
mkdir -p "$REPO/sub"
out=$(cd "$REPO/sub" && timeout 120 bash "$MIRROR" "$TMP/ci.md" 2>/dev/null); rc=$?
check "a run from a subdirectory passes" "$rc" "0"
check "a run from a subdirectory still runs the command" "$(runs)" "3"
check "no row names the subdirectory" "$(cut -f3 "$REPO/.dforge/suites.tsv" | tr -d '\r' | grep -c '^(sub)')" "0"

# --- a failing command, and a command that cannot launch ---------------------------------
cat > "$TMP/fail.md" <<'EOF'
# P

**Spec:** `s.md`

**CI:** `ci.yml` — platforms: ubuntu-latest — local: `true`; `exit 3`; `echo after >> "$PROBE_RUNS"` — uncovered: none

### Task 1: One

body
EOF
before=$(runs)
mirror "$TMP/fail.md"
check "a failing command exits 1" "$rc" "1"
check "the digest names the failing command and its exit code" "$(printf '%s\n' "$out" | grep -cF 'ci: exit 3 — FAIL (exit 3)')" "1"
check "a failure does not skip the later commands" "$(runs)" "$((before + 1))"
check "the uncovered line is still printed" "$(printf '%s\n' "$out" | tail -n 1)" "uncovered: none"
check "stdout holds only digest lines" "$(printf '%s\n' "$out" | grep -Evc '^(ci: |uncovered: )')" "0"
has "the failed command's suite-run digest goes to stderr" "$err" "suite: FAIL (exit 3)"
has "stderr names the log" "$err" "log: "

cat > "$TMP/nolaunch.md" <<'EOF'
# P

**Spec:** `s.md`

**CI:** `ci.yml` — platforms: ubuntu-latest — local: `no-such-command-here` — uncovered: none

### Task 1: One

body
EOF
mirror "$TMP/nolaunch.md"
check "a command that cannot launch exits 1" "$rc" "1"
check "its digest line names it" "$(printf '%s\n' "$out" | head -n 1)" "ci: no-such-command-here — FAIL (exit 127)"

# --- a plan written with CRLF line endings -----------------------------------------------------
awk '{ printf "%s\r\n", $0 }' "$TMP/ci.md" > "$TMP/ci-crlf.md"
mirror "$TMP/ci-crlf.md"
check "a CRLF plan exits 0" "$rc" "0"
check "a CRLF plan prints no carriage return" "$(printf '%s' "$out" | tr -cd '\r' | wc -c | tr -d ' ')" "0"
check "a CRLF plan prints the same uncovered line" "$(printf '%s\n' "$out" | tail -n 1)" "uncovered: Windows Git Bash, macOS"

# --- usage and malformed lines exit 2 ------------------------------------------------------------
mirror
check "no argument exits 2" "$rc" "2"
mirror "$TMP/missing.md"
check "a missing plan exits 2" "$rc" "2"
printf '# P\n\n**Spec:** `s.md`\n\n### Task 1: One\n\nbody\n' > "$TMP/noline.md"
mirror "$TMP/noline.md"
check "a plan with no CI line exits 2" "$rc" "2"
has "a plan with no CI line says so" "$err" "no **CI:** line"
printf '# P\n\n````markdown\n**CI:** none\n````\n\n### Task 1: One\n\nbody\n' > "$TMP/fenced.md"
mirror "$TMP/fenced.md"
check "a CI line inside a code fence is not read" "$rc" "2"
while IFS= read -r line; do
  printf '# P\n\n**Spec:** `s.md`\n\n%s\n\n### Task 1: One\n\nbody\n' "$line" > "$TMP/bad.md"
  mirror "$TMP/bad.md"
  check "a malformed CI line exits 2: $line" "$rc" "2"
  check "a malformed CI line prints no digest: $line" "$out" ""
done <<'EOF'
**CI:** nope
**CI:** none — no workflows
**CI:** `ci.yml` — platforms: ubuntu-latest — uncovered: none
**CI:** `ci.yml` — platforms: ubuntu-latest — local: make test — uncovered: none
**CI:** `ci.yml` — platforms: ubuntu-latest — local: `make test`
**CI:** `ci.yml` — platforms: ubuntu-latest — local: `make test` — uncovered:
EOF

mkdir "$TMP/plain"
out=$(cd "$TMP/plain" && timeout 120 bash "$MIRROR" "$TMP/ci.md" 2>&1); rc=$?
check "commands outside a git checkout exit 2" "$rc" "2"
has "commands outside a git checkout say so" "$out" "not in a git checkout"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
```

In `plugins/dforge/tests/gates-manifest.test.sh`, add the block below before the final `printf '\n%d passed, %d failed\n' …` line. It adds one helper, `says_flat`, which folds line breaks before matching.

```bash
# ci-mirror runs before the gates, and a gate whose command it already passed
# is reported from that record (test tiers plan, part 5).
says_flat() { # says_flat <name> <file> <needle>
  if tr '\n' ' ' < "$2" | tr -s ' ' | grep -qF -- "$3"; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       missing: [%s]\n       in: [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
FR="$P/reference/final-review.md"
says_flat "final review runs ci-mirror before the gates" "$FR" 'Before the gates, run `bash <plugin-root>/scripts/ci-mirror PLAN_FILE`'
says_flat "a ci-mirror failure is a final-review finding" "$FR" 'A `ci-mirror` failure is a final-review finding'
says_flat "a ci-mirror failure does not stop the review" "$FR" 'it does not stop the review'
says_flat "an older plan with no CI line goes on" "$FR" 'Exit 2 means the plan has no usable `**CI:**` line'
flat_fr=$(tr '\n' ' ' < "$FR" | tr -s ' ')
head_ci=${flat_fr%%scripts/ci-mirror*}
head_gates=${flat_fr%%dforge:running-gates before dispatching*}
check "ci-mirror comes before the gates in step 0" "$([ "${#head_ci}" -lt "${#head_gates}" ] && echo yes || echo no)" "yes"
says_flat "running-gates matches a gate to a CI-line command byte for byte" "$SKILL" 'whose `Command` equals, byte for byte, a command in the plan'"'"'s `**CI:**` line'
says_flat "running-gates runs such a gate through suite-run as bash -c" "$SKILL" 'bash <plugin-root>/scripts/suite-run -- bash -c'
says_flat "running-gates reports a reused pass as ci-mirror's" "$SKILL" 'passed from the ci-mirror record at <sha7>'
says_flat "running-gates names the log" "$SKILL" 'naming the `log:` line'
says_flat "running-gates excludes gates with Setup, Teardown or Repo" "$SKILL" 'no `Setup`, `Teardown` or `Repo` field'
says_flat "running-gates runs every other gate as before" "$SKILL" 'Every other gate runs as before.'
```

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 300 bash plugins/dforge/tests/ci-mirror.test.sh; timeout 300 bash plugins/dforge/tests/gates-manifest.test.sh`
Expected: `ci-mirror.test.sh` fails at its first check, because `plugins/dforge/scripts/ci-mirror` does not exist (every case fails, with exit codes 127 where the script is called); `gates-manifest.test.sh` prints FAIL for each new pin above and `ok` for every earlier one.

- [ ] **Step 3: Implement**

1. **`plugins/dforge/scripts/ci-mirror`** (bash, `#!/usr/bin/env bash`, `set -uo pipefail`, `chmod +x`). A header comment gives the usage, the output forms and the exit codes of C7. It takes exactly one argument, `PLAN_FILE`; any other count prints `usage: ci-mirror PLAN_FILE` to stderr and exits 2.
   1. `HERE` is the script's own directory; source `$HERE/lib/plan.sh`. A `PLAN_FILE` that cannot be read prints `ci-mirror: cannot read <file>` and exits 2.
   2. Read the line with `plan_header_line "$PLAN_FILE" CI` (it ignores fenced lines and strips `\r`); strip a trailing `\r` again anyway. No line prints `ci-mirror: no **CI:** line in <file>` and exits 2.
   3. Parse the text after `**CI:** `, trimmed. The text `none` and nothing else prints `ci: none` and exits 0, without touching git or suite-run. Otherwise the text must be, in order: one code span; ` — platforms: ` and a non-empty list; ` — local: ` and one or more non-empty code spans separated by `; `; ` — uncovered: ` and a non-empty remainder. Anything else prints `ci-mirror: malformed **CI:** line` and exits 2 with nothing on stdout. The commands are the local code spans, with their backticks removed and their text otherwise unchanged; `uncovered` is the remainder, trimmed.
   4. With commands to run, `cd` to `git rev-parse --show-toplevel` after the plan file has been read (a relative `PLAN_FILE` resolves first). Outside a git checkout print `ci-mirror: not in a git checkout` and exit 2.
   5. For each command in order, run `bash "$HERE/suite-run" -- bash -c "$cmd"` with stdout and stderr captured together and the exit code kept. The command is passed as the single argument of `bash -c`, never re-quoted. The verdict is the first captured line that starts `suite: `, without that prefix (`pass (exit 0)`, `reused pass at <sha7> (<age>)`, `FAIL (exit <code>)`). When no such line exists (suite-run itself failed before running, for example exit 2), the verdict is `FAIL (exit <code>)` with suite-run's exit code. A non-zero exit forces a verdict beginning `FAIL`. Print `ci: <cmd> — <verdict>` to stdout at once. For a non-zero exit also print the whole captured output to stderr, so the failing lines and the `log:` path are visible. A failure does not stop the remaining commands, and the exit status becomes 1.
   6. After the last command print `uncovered: <uncovered>` and exit with 0 when every command passed or was reused, else 1.
   7. Nothing else is written to stdout. The script starts no background process and leaves no temporary file.
2. **`scripts/test-shards.mjs`.** Add `'ci-mirror.test.sh': 60,` to `windowsSeconds`, in alphabetical position between `'budget-line.test.sh'` and `'codex-gate.test.sh'` (three times its Linux time, as Global Constraints require).
3. **`reference/final-review.md`, step `0. **Gates.**`.** Open the step with the ci-mirror paragraph, then continue with the existing gates sentences. It says: "Before the gates, run `bash <plugin-root>/scripts/ci-mirror PLAN_FILE`", in the background when it can outrun Bash's ten-minute cap. Exit 0 goes on. Exit 1 prints one `ci: <command> — FAIL (exit <code>)` line per failing command; each becomes a finding on the Claude list (step 1), written `[ci] <command> — FAIL (exit <code>)`. A `ci-mirror` failure is a final-review finding, and it does not stop the review; in an auto run it goes on the fix wave's list the same way. Exit 2 means the plan has no usable `**CI:**` line (an older plan): say so in one line and go on, with no finding. Run it again whenever the gates run again. Insert the text without re-wrapping any existing line of the step: `auto-run-skills.test.sh` pins several of them, and the depth table's `| 0 Gates |` row stays as it is.
4. **`running-gates/SKILL.md`, step 4.** After the existing step 4 text add an indented paragraph: when the caller names a plan file, read the local commands of its `**CI:**` line (the commands `scripts/ci-mirror` runs). A gate with no `Setup`, `Teardown` or `Repo` field whose `Command` equals, byte for byte, a command in the plan's `**CI:**` line is run as `bash <plugin-root>/scripts/suite-run -- bash -c` with the Command as that one argument, from the repository's top level. When suite-run prints `suite: reused pass at <sha7>`, the gate has passed at this HEAD from ci-mirror's record: report it as `passed from the ci-mirror record at <sha7>`, naming the `log:` line, and judge its `Evidence` against that log, which holds the command's output. Any other suite-run output is an ordinary run of the gate, judged as step 5 says. Every other gate runs as before. Step 7's report row for such a gate carries the log path.

- [ ] **Step 4: Run test to verify it passes**

Run, from the repository root:
- `chmod +x plugins/dforge/scripts/ci-mirror`
- `timeout 300 bash plugins/dforge/tests/ci-mirror.test.sh`
- `timeout 300 bash plugins/dforge/tests/gates-manifest.test.sh`
- `timeout 300 bash plugins/dforge/tests/auto-run-skills.test.sh`
- `timeout 300 bash plugins/dforge/tests/final-phase.test.sh`
- `timeout 300 bash plugins/dforge/tests/suite-run.test.sh`
- `timeout 120 node --test tests/test-shards.test.mjs`
- `grep -n "'ci-mirror.test.sh'" scripts/test-shards.mjs`
- `timeout 120 node scripts/validate-repository.mjs`

Expected: PASS, `0 failed` in each suite; the `grep` prints the one weight line; no process of these runs is left behind (`pgrep -f ci-mirror` prints nothing).

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/scripts/ci-mirror plugins/dforge/tests/ci-mirror.test.sh plugins/dforge/tests/gates-manifest.test.sh plugins/dforge/reference/final-review.md plugins/dforge/skills/running-gates/SKILL.md scripts/test-shards.mjs
git commit -m "feat(dforge): mirror CI locally with ci-mirror"
```

### Task 12: Run early CI from the controller

**Files:**
- Modify: `plugins/dforge/reference/delegated-task.md` (a new `## Early CI` section directly above `## The steps by hand`)
- Modify: `plugins/dforge/skills/subagent-driven-development/SKILL.md` (the `**Nothing stops for your human partner.**` bullet; one paragraph at the end of `## The Task Loop`)
- Modify: `plugins/dforge/skills/executing-plans/SKILL.md` (the same bullet; the end of step 7 of `## The Task Loop`)
- Modify: `plugins/dforge/skills/subagent-driven-development/references/ledger.md` (the grammar block and the bullet list below it)
- Modify: `plugins/dforge/reference/auto-run.md` (the last sentence of the `**Never performed in an auto run,**` paragraph)
- Test: `plugins/dforge/tests/auto-run-skills.test.sh`

**Interfaces:**
- Consumes: Contracts C3 (the plan header's `**CI:**` and `**Early CI:**` lines) and C8 (the five ledger line forms). Earlier tasks changed other parts of `delegated-task.md` and both execution skills: anchor every edit below on the heading or quoted line it names, never on a line number.
- Produces: the `## Early CI` section of `delegated-task.md`, whose background watch uses the timeout Task 13 writes into `execute-choice.md` §Wait for CI: (90 × 60 + 120) × 1000 ms.

**Items:** 5
**Implementer:** dforge:impl-opus-high
**Evaluation:** files 2 - spec 2 - coupling 1 - risk 2 = 7

- [ ] **Step 1: Write the failing test**

Edit `plugins/dforge/tests/auto-run-skills.test.sh` in three places.

Edit A: directly after the `names()` helper, add a helper that folds line breaks, so a pin survives re-wrapping of the prose it pins.

```bash
flat() { tr '\n' ' ' < "$1" | tr -s ' '; }
says() { # says <label> <file> <text> — the text, with line breaks folded
  check "$1" "$(flat "$2" | grep -qF -- "$3" && echo yes || echo no)" "yes"
}
```

Edit B: inside the `for skill in subagent-driven-development executing-plans` loop, replace the line
`names "$skill: the finish is the one outside action" "$F" '(the finish action is the one exception)'`
with this line (the pin is updated in place, because this task changes the sentence it pins):

```bash
  says "$skill: the finish and the consented early CI are the outside actions" "$F" '(the finish action and the consented Early CI push and dispatch are the exceptions)'
```

Edit C: directly above the final `printf '\n%d passed, %d failed\n'` line, add:

```bash
# Early CI: the controller step, the ledger grammar and the auto-run exception
# (docs/dforge/specs/2026-10-31-test-tiers-and-ci-parity-design.md, part 5).
D="$P/reference/delegated-task.md"
SDDF="$P/skills/subagent-driven-development/SKILL.md"
LEDGER_MD="$P/skills/subagent-driven-development/references/ledger.md"
says "auto-run.md: the early CI push and dispatch are the second exception" "$R" 'The finish action is the first exception. The second is the `**Early CI:**` push and workflow dispatch, performed only when the header line carries `— consented <YYYY-MM-DD>`.'
names "delegated-task.md: the Early CI section" "$D" '## Early CI'
says "delegated-task.md: without the line nothing pushes" "$D" 'With no `**Early CI:**` line in the plan header, nothing in this loop pushes the branch or starts CI before finishing.'
says "delegated-task.md: consent gates the push" "$D" 'Push only when the line carries `— consented <YYYY-MM-DD>`.'
says "delegated-task.md: the task point" "$D" 'For `after task <n>`, run these steps right after the `Task <n>: complete` line.'
says "delegated-task.md: the wave point" "$D" 'For `after wave <k>`, run them right after the `Wave <k>: integrated` or `Wave <k>: merged` line.'
says "delegated-task.md: the push" "$D" 'Push the branch with `git push -u origin <branch>`.'
says "delegated-task.md: dispatch only with workflow_dispatch" "$D" 'Start CI with `gh workflow run <workflow> --ref <branch>` only when the workflow file declares `workflow_dispatch`; otherwise print one line saying so and skip the early run.'
says "delegated-task.md: the workflow is the first dispatchable one" "$D" '`<workflow>` is the first workflow file the plan'"'"'s `**CI:**` line names that declares `workflow_dispatch`.'
says "delegated-task.md: never a pull request" "$D" 'Never open a pull request to start CI.'
says "delegated-task.md: run discovery" "$D" 'Find the run with `gh run list --workflow <file> --branch <branch> --limit 1 --json databaseId,headSha`, retrying for up to 60 seconds until `headSha` is the pushed commit.'
says "delegated-task.md: the dispatched line" "$D" 'Write `Early CI: dispatched run <id> at <sha7>` once the run is found.'
says "delegated-task.md: the background watch" "$D" 'Run `gh run watch <id>` as a background Bash command, with the call'"'"'s `timeout` set to (90 × 60 + 120) × 1000 ms, and keep working.'
says "delegated-task.md: the outcome lines" "$D" 'When the watch ends, read `gh run view <id> --json conclusion,jobs` and write `Early CI: green run <id>`, or `Early CI: red run <id> — <job>/<step>[, <job>/<step> ...]` naming each failed job and its failed step.'
says "delegated-task.md: a git or gh failure is a skip" "$D" 'Any failure of `git push` or `gh` prints one line, writes `Early CI: skipped — <reason>`, and never stops the run.'
says "delegated-task.md: a red run is a fix bullet" "$D" 'A red run is a bullet you write into the next task'"'"'s fix file, as §4 does for a mechanical check'"'"'s finding.'
says "delegated-task.md: a red run with no task left" "$D" 'With no task left, a red run is a final-review finding, debugged with dforge:systematic-debugging.'
says "delegated-task.md: recovery" "$D" 'On recovery, a `dispatched` line with no `green` or `red` line after it gets `gh run view <id> --json status,conclusion` once, and a new background watch when the run is still going.'
for line in 'Early CI: dispatched run <id> at <sha7>' 'Early CI: green run <id>' 'Early CI: red run <id> — <job>/<step>[, <job>/<step> ...]' 'Early CI: skipped — <reason>' 'CI: <sha7> run <id> <green|red|still running at 90 min>'; do
  names "ledger.md: the grammar holds $line" "$LEDGER_MD" "$line"
done
says "subagent-driven-development: Early CI runs at the point the line names" "$SDDF" 'When the plan header has an `**Early CI:**` line, run [delegated-task.md](../../reference/delegated-task.md) §Early CI at the point the line names.'
says "executing-plans: step 7 runs Early CI" "$EPF" 'run [delegated-task.md](../../reference/delegated-task.md) §Early CI when the header'"'"'s `**Early CI:**` line names this task.'
# With no Early CI line no step may push or start CI, so these commands appear
# nowhere in the controller text outside the Early CI section.
outside() { awk '/^## / { skip = ($0 == "## Early CI") } !skip' "$1"; }
check "delegated-task.md: no step outside Early CI pushes the branch or starts CI" "$(outside "$D" | grep -cE 'git push|gh workflow run|gh run ')" "0"
check "subagent-driven-development: nothing in the skill pushes the branch or starts CI" "$(grep -cE 'git push|gh workflow run|gh run ' "$SDDF")" "0"
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `timeout 300 bash plugins/dforge/tests/auto-run-skills.test.sh | grep -c '^FAIL'`
Expected: a count above 0: `## Early CI` does not exist, the two skills still say `the one exception`, and the ledger grammar lacks the five lines. The two `check` lines about text outside the Early CI section pass already and must keep passing.

- [ ] **Step 3: Implement**

Write each sentence that a `says` or `names` line above quotes verbatim; the tests pin those sentences. Everything else is free wording, one fact per sentence, in the file's existing voice.

1. `delegated-task.md`, new `## Early CI` section directly above `## The steps by hand`:
   - Open with what the line is: an `**Early CI:**` header line names one point, `after task <n>` or `after wave <k>`, and the owner's consent. State the no-line sentence, the consent sentence, and the two point sentences (task: right after the task's `complete` line; wave: right after its `integrated` or `merged` line).
   - Then four steps in order: push; start CI (the dispatch sentence, the sentence naming which workflow, and the never-a-pull-request sentence); find the run (the discovery sentence, then the `dispatched` ledger sentence); watch it in the background (the watch sentence). The watch's `timeout` is (90 × 60 + 120) × 1000 ms, the value `execute-choice.md` §Wait for CI also uses (Task 13).
   - Then the outcome sentence (green and red lines), the failure sentence (one line and a `skipped` ledger line for any `git push` or `gh` failure, and for a workflow with no `workflow_dispatch`; never a stop), the red-run sentences (a bullet for the next task's fix file, as §4 already does for a mechanical check; a final-review finding when no task is left) and the recovery sentence.
   - Write no `git push`, `gh workflow run` or `gh run` anywhere else in the file: the last two tests of Edit C count them.
2. `subagent-driven-development/SKILL.md`:
   - In the `**Nothing stops for your human partner.**` bullet, replace `(the finish action is the one exception)` with `(the finish action and the consented Early CI push and dispatch are the exceptions)`.
   - At the end of `## The Task Loop`, add a paragraph starting `**Early CI.**` that holds the pinned sentence (`When the plan header has an `**Early CI:**` line, run [delegated-task.md](../../reference/delegated-task.md) §Early CI at the point the line names.`) and one sentence saying that without the line nothing in this loop pushes the branch or starts CI. Use neither `git push` nor `gh` in it.
3. `executing-plans/SKILL.md`: make the same parenthetical replacement, and end step 7 (`**Close the task.**`) with the pinned sentence. The file is close to the 20,000-byte cap that `skill-size.test.sh` enforces and earlier tasks may have added to it: run that test and, if the file is over, shorten the sentences you added (not other text); if it is still over, stop and report BLOCKED with the byte count.
4. `ledger.md`: add the five lines to the grammar block after the `Final review: clean …` line, exactly as the test's `for` loop lists them, and one bullet below the block saying that `delegated-task.md` §Early CI writes the four `Early CI:` lines, finishing writes the `CI:` line, and no Recovery row reads them because Recovery keys on `Task` and `Group` lines.
5. `auto-run.md`: in the `**Never performed in an auto run,**` paragraph replace the last sentence (`The finish action is the one exception.`) with the pinned two sentences. Leave the rest of the paragraph as it is.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `timeout 300 bash plugins/dforge/tests/auto-run-skills.test.sh | tail -1`, `timeout 300 bash plugins/dforge/tests/skill-size.test.sh | tail -1`, `timeout 300 bash plugins/dforge/tests/sdd-references.test.sh | tail -1`, `timeout 300 bash plugins/dforge/tests/delegated-suite.test.sh | tail -1`, `timeout 60 node scripts/validate-repository.mjs`
Expected: every suite ends `N passed, 0 failed`, and validate-repository prints its valid line.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/reference/delegated-task.md plugins/dforge/reference/auto-run.md plugins/dforge/skills/subagent-driven-development/SKILL.md plugins/dforge/skills/subagent-driven-development/references/ledger.md plugins/dforge/skills/executing-plans/SKILL.md plugins/dforge/tests/auto-run-skills.test.sh
git commit -m "feat(dforge): run early CI from the controller"
```

### Task 13: Wait for CI at finishing

**Files:**
- Modify: `plugins/dforge/skills/finishing-a-development-branch/references/execute-choice.md` (Options 1, 2 and 3, and a new `### Wait for CI` section)
- Modify: `plugins/dforge/skills/finishing-a-development-branch/SKILL.md` (one sentence in Step 7)
- Test: `plugins/dforge/tests/final-phase.test.sh`

**Interfaces:**
- Consumes: Contracts C3 (the `**CI:**` and `**Early CI:**` header lines) and C8 (the `CI:` and `Early CI: dispatched` ledger lines).
- Produces: the `### Wait for CI` section of `execute-choice.md`, which Task 12's `## Early CI` section points to for its watch timeout.

**Items:** 5
**Implementer:** dforge:impl-sonnet-high
**Evaluation:** files 1 - spec 2 - coupling 1 - risk 1 = 5

- [ ] **Step 1: Write the failing test**

Append to `plugins/dforge/tests/final-phase.test.sh`, directly above its final `printf '\n%d passed, %d failed\n'` line (the `says` helper is defined earlier in that file):

```bash
# Waiting for CI (docs/dforge/specs/2026-10-31-test-tiers-and-ci-parity-design.md, part 5).
ER="$P/skills/finishing-a-development-branch/references/execute-choice.md"
names "execute-choice: the wait section" "$ER" '### Wait for CI'
says "execute-choice: wait only when finishing pushed" "$ER" 'Finishing waits for CI only when it pushed: Option 2, or an Early CI push whose head is the final head.'
says "execute-choice: the run is found by commit" "$ER" 'Run `gh run list --commit <sha>`, then `gh run watch <id>` as a background Bash command.'
says "execute-choice: the Bash timeout" "$ER" 'Set the call'"'"'s `timeout` to (90 × 60 + 120) × 1000 ms, because a background call otherwise stops at 30 minutes.'
says "execute-choice: an auto run ends the turn" "$ER" 'In an auto run, end the turn and resume on the notification.'
says "execute-choice: no run appears" "$ER" 'When no run for the commit appears within 60 seconds, print one line saying so and skip the wait; never call the branch CI-green.'
says "execute-choice: the CI ledger line" "$ER" 'Record `CI: <sha7> run <id> <green|red|still running at 90 min>` on the ledger.'
says "execute-choice: green completes the branch" "$ER" 'Green completes the branch.'
says "execute-choice: red reopens through debugging" "$ER" 'Red reopens the branch through dforge:systematic-debugging, naming each failed job and step; push the fix and wait again.'
says "execute-choice: a run still going is not done" "$ER" 'A run still going after 90 minutes is reported as not done, never as done.'
says "execute-choice: an auto run stops on a run still going" "$ER" 'In an auto run, a run still going after 90 minutes runs `scripts/auto-run stop --reason "CI run <id> still running at 90 min"` before the final message.'
says "execute-choice: the skips print one line" "$ER" 'With keep, no `gh` (`command -v gh` fails), `gh` not logged in (`gh auth status` exits non-zero), or a CI line of `none`, print why in one line and skip the wait; never call the branch CI-green.'
says "execute-choice: a local merge waits for nothing" "$ER" 'After a local merge, nothing was pushed, so do not wait: print `gh run list --commit <merge sha>` and `gh run watch <id>` for your human partner to run after pushing, and never call the branch CI-green.'
says "execute-choice: a merge deletes the early remote branch" "$ER" 'On a plan with an `**Early CI:**` line, run `git push origin --delete <feature-branch>` after the local merge.'
says "execute-choice: keep names the remote branch" "$ER" 'With keep on such a plan, say that the remote branch `origin/<feature-branch>` exists.'
says "finishing: the final message quotes the CI line" "$FIN" 'When the ledger holds a `CI:` line, the final message quotes it.'
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `timeout 300 bash plugins/dforge/tests/final-phase.test.sh | grep -c '^FAIL'`
Expected: a count above 0: `### Wait for CI` does not exist.

- [ ] **Step 3: Implement**

Write each sentence that a `says` or `names` line above quotes verbatim; the tests pin those sentences. Everything else is free wording, one fact per sentence, in the file's existing voice.

1. `execute-choice.md`:
   - Option 1: after the `git branch -d <feature-branch>` block add the local-merge paragraph (the pinned `After a local merge, nothing was pushed …` sentence) and the `git push origin --delete <feature-branch>` sentence. State that the delete applies only when `git ls-remote --exit-code --heads origin <feature-branch>` finds the branch, and that a delete that fails prints one line and does not stop finishing.
   - Option 2: after `Keep the worktree …`, one sentence sending the reader to `### Wait for CI`, with `sha` being `git rev-parse HEAD` at the push.
   - Option 3: add the pinned keep sentence, applying only when `git ls-remote --exit-code --heads origin <feature-branch>` finds the branch, so a failed early push says nothing false.
   - New `### Wait for CI`, between Option 3 and `### If your human partner asks to discard the work`, holding in this order: the push condition sentence (an Early CI push whose head is the final head means the ledger's last `Early CI: dispatched run <id> at <sha7>` line names `git rev-parse --short HEAD`; its run id is the one to watch); the `gh run list` / `gh run watch` sentence; the timeout sentence; the auto-run turn sentence; the no-run sentence; the `CI:` ledger sentence; green; red; still running (both the not-done sentence and the auto-run stop sentence); the skip sentence. The CI line it names is the plan's `**CI:**` header line, read from the plan file finishing was given; a plan with no such line counts as `none`.
2. `finishing-a-development-branch/SKILL.md`, Step 7: add the pinned `When the ledger holds a `CI:` line, the final message quotes it.` sentence after the paragraph about the `## Next session` block. Change nothing else in the file, which sits near its 20,000-byte cap.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `timeout 300 bash plugins/dforge/tests/final-phase.test.sh | tail -1`, `timeout 300 bash plugins/dforge/tests/skill-size.test.sh | tail -1`, `timeout 60 node scripts/validate-repository.mjs`
Expected: both suites end `N passed, 0 failed`, and validate-repository prints its valid line (it checks that `dforge:systematic-debugging` and every bundled link resolve).

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/skills/finishing-a-development-branch/SKILL.md plugins/dforge/skills/finishing-a-development-branch/references/execute-choice.md plugins/dforge/tests/final-phase.test.sh
git commit -m "feat(dforge): wait for CI at finishing"
```

### Task 14: Lint this repository for Git Bash pitfalls

**Files:**
- Create: `scripts/lint-portability.mjs`
- Create: `tests/lint-portability.test.mjs`
- Modify: `scripts/validate-repository.mjs` (the `import` block and the `process.argv[1]` block at the end)
- Modify: `plugins/dforge/tests/dforge-config.test.sh` (the `capped=$(DFORGE_CONFIG_MJS=…` block, the only hit the lint finds today)

**Interfaces:**
- Consumes: `dr_native_path` in `plugins/dforge/scripts/lib/native-path.sh`, which the `git-c-pwd` rule names in its message.
- Produces: Contract C9 — `lintText(path, text)` returning `{ line, rule, message }` objects, the command `node scripts/lint-portability.mjs [root]`, and the rule ids `git-c-pwd`, `awk-v-backslash`, `import-path`, `jq-pwd-file`. This task also exports `lintTree(root)`, returning one `<file>:<line> <rule> <message>` string per hit, with `<file>` relative to `root` and written with `/`; `validate-repository.mjs` and the tests call it.

**Items:** 5
**Implementer:** dforge:impl-opus-high
**Evaluation:** files 2 - spec 2 - coupling 1 - risk 1 = 6

- [ ] **Step 1: Write the failing test**

Create `tests/lint-portability.test.mjs`:

```js
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import test from 'node:test';
import { lintText, lintTree } from '../scripts/lint-portability.mjs';

const root = fileURLToPath(new URL('../', import.meta.url));
const MSYS = 'export MSYS_NO_PATHCONV=1';
const found = (file, lines) => lintText(file, lines.join('\n')).map(({ line, rule }) => ({ line, rule }));
const marked = (file, lines, at) => lines.map((line, index) => index === at ? `${line}  ${file.endsWith('.mjs') ? '//' : '#'} portability: ok — the fixture runs on Linux` : line);

// [rule, file, the file's lines, the 0-based index of the line that hits]
const hitRows = [
  ['git-c-pwd', 'a.sh', ['git -C "$PWD" status'], 0],
  ['git-c-pwd', 'a.sh', ['echo start', '  top=$(git -C "$(pwd)" rev-parse --show-toplevel)'], 1],
  ['git-c-pwd', 'a.sh', ['git -C $PWD log'], 0],
  ['awk-v-backslash', 'a.sh', [String.raw`awk -v re='a\.b' '$0 ~ re' file`], 0],
  ['awk-v-backslash', 'a.sh', [String.raw`awk -F'\t' -v pat="^\\[x\\]" '$0 ~ pat' file`], 0],
  ['import-path', 'a.mjs', ['const mod = await import(modulePath);'], 0],
  ['import-path', 'a.mjs', ["const mod = await import(resolve(root, 'lib/x.mjs'));"], 0],
  ['import-path', 'a.mjs', ['const mod = await import(`${dir}/x.mjs`);'], 0],
  ['import-path', 'a.mjs', ['const a = 1;', 'const mod = await import(', "  path.join(root, 'x.mjs')", ');'], 1],
  ['jq-pwd-file', 'a.sh', [MSYS, 'jq -r .name "$PWD/package.json"'], 1],
  ['jq-pwd-file', 'a.sh', [MSYS, 'jq -r .name "$(pwd)/package.json"'], 1],
  ['jq-pwd-file', 'a.sh', [MSYS, 'name=$(jq -r .name "$TMPDIR/package.json")'], 1],
  ['jq-pwd-file', 'a.sh', [MSYS, "cat x | jq '.a | .b' \"$PWD/p.json\""], 1],
];

test('each rule flags its fixture line, and a reasoned exemption on that line clears it', () => {
  for (const [rule, file, lines, at] of hitRows) {
    assert.deepEqual(found(file, lines), [{ line: at + 1, rule }], `${rule}: ${lines.join(' / ')}`);
    assert.deepEqual(found(file, marked(file, lines, at)), [], `${rule} exempt: ${lines.join(' / ')}`);
  }
});

test('a line that follows the safe form is not flagged', () => {
  const safe = [
    ['a.sh', ['git -C "$(dr_native_path "$PWD")" status']],
    ['a.sh', ['git -C "$REPO" status']],
    ['a.sh', ['awk -v n="$N" \'{ print n }\' file']],
    ['a.sh', ['RE=\'a\\.b\' awk \'$0 ~ ENVIRON["RE"]\' file']],
    ['a.sh', [String.raw`awk -F'\t' '{ print $1 }' file`]],
    ['a.sh', [String.raw`awk -v h="$(printf 'x' | tr -d '\r')" '{ print h }' file`]],
    ['a.sh', [String.raw`awk '/\./ { print }' file`]],
    ['a.mjs', ['const mod = await import(pathToFileURL(file).href);']],
    ['a.mjs', ["const fs = await import('node:fs');"]],
    ['a.mjs', ['const mod = await import("./local.mjs");']],
    ['a.mjs', ['const mod = await import(`./${name}.mjs`);']],
    ['a.mjs', ['const mod = await import(', '  pathToFileURL(path.join(root, "x.mjs")).href', ');']],
    ['a.sh', ['jq -r .name "$PWD/package.json"']],
    ['a.sh', [MSYS, 'jq -r .name < "$PWD/package.json"']],
    ['a.sh', [MSYS, 'jq -n --arg d "$PWD" \'$d\'']],
    ['a.sh', [MSYS, 'cat "$PWD/a.json" | jq -r .name']],
    ['a.sh', [MSYS, 'jq -r .name "$REPO/package.json"']],
  ];
  for (const [file, lines] of safe) assert.deepEqual(found(file, lines), [], lines.join(' / '));
});

test('an exemption needs its reason and covers only its own line', () => {
  assert.deepEqual(found('a.sh', ['git -C "$PWD" status  # portability: ok']), [{ line: 1, rule: 'git-c-pwd' }]);
  assert.deepEqual(found('a.sh', ['git -C "$PWD" status  # portability: ok —']), [{ line: 1, rule: 'git-c-pwd' }]);
  assert.deepEqual(found('a.sh', ['# portability: ok — reason', 'git -C "$PWD" status']), [{ line: 2, rule: 'git-c-pwd' }]);
  assert.deepEqual(lintText('a.sh', 'echo ok\r\ngit -C "$PWD" status\r\n').map(({ line }) => line), [2]);
  assert.deepEqual(lintText('a.sh', 'git -C "$PWD" status  # portability: ok — reason\r\n'), []);
});

function fixtureTree(files) {
  const dir = mkdtempSync(join(tmpdir(), 'lint-portability-'));
  for (const [path, text] of Object.entries(files)) {
    mkdirSync(dirname(join(dir, path)), { recursive: true });
    writeFileSync(join(dir, path), text);
  }
  return dir;
}

test('the tree scan reads plugin scripts and tests and the repository scripts only', () => {
  const dir = fixtureTree({
    'plugins/p/scripts/x.sh': 'git -C "$PWD" status\n',
    'plugins/p/tests/y.test.sh': 'git -C "$PWD" status  # portability: ok — fixture\nawk -v a=\'\\.\' x\n',
    'scripts/z.mjs': 'await import(file);\n',
    'tests/v.test.mjs': 'await import(file);\n',
    'plugins/p/skills/s.sh': 'git -C "$PWD" status\n',
  });
  try {
    assert.deepEqual(lintTree(dir).map(line => line.split(' ').slice(0, 2).join(' ')).sort(), [
      'plugins/p/scripts/x.sh:1 git-c-pwd',
      'plugins/p/tests/y.test.sh:2 awk-v-backslash',
      'scripts/z.mjs:1 import-path',
    ]);
  } finally { rmSync(dir, { recursive: true, force: true }); }
});

test('the repository has no portability hit', () => {
  assert.deepEqual(lintTree(root), []);
});

test('the command prints a hit as file:line rule message and exits 1, and validate-repository fails on it', () => {
  const dir = fixtureTree({ 'plugins/p/scripts/x.sh': 'git -C "$PWD" status\n' });
  try {
    const lint = spawnSync(process.execPath, ['scripts/lint-portability.mjs', dir], { cwd: root, encoding: 'utf8', timeout: 20000 });
    assert.ifError(lint.error);
    assert.equal(lint.status, 1);
    assert.match(lint.stdout, /^plugins\/p\/scripts\/x\.sh:1 git-c-pwd \S/m);
    const validate = spawnSync(process.execPath, ['scripts/validate-repository.mjs', dir], { cwd: root, encoding: 'utf8', timeout: 20000 });
    assert.ifError(validate.error);
    assert.equal(validate.status, 1);
    assert.match(validate.stderr, /^plugins\/p\/scripts\/x\.sh:1 git-c-pwd \S/m);
  } finally { rmSync(dir, { recursive: true, force: true }); }
  const clean = fixtureTree({ 'plugins/p/scripts/x.sh': 'git -C "$PWD" status  # portability: ok — fixture\n' });
  try {
    const lint = spawnSync(process.execPath, ['scripts/lint-portability.mjs', clean], { cwd: root, encoding: 'utf8', timeout: 20000 });
    assert.ifError(lint.error);
    assert.equal(lint.status, 0);
    assert.equal(lint.stdout, '');
  } finally { rmSync(clean, { recursive: true, force: true }); }
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `timeout 120 node --test tests/lint-portability.test.mjs`
Expected: FAIL at load with `Cannot find module` for `scripts/lint-portability.mjs`.

- [ ] **Step 3: Implement**

1. `scripts/lint-portability.mjs` is an ES module exporting `lintText(path, text)` and `lintTree(root)`. `lintText` splits `text` on `\n`, strips a trailing `\r` from each line, and returns hits as `{ line, rule, message }`, with `line` 1-based and the list sorted by `line`. The `path` argument names the file for the caller; the rules read only the text. A line is exempt when it matches `(#|//) portability: ok — <reason>` at its end, where `<reason>` is at least one non-space character; an exemption covers its own line only. For the multi-line `import-path` rule the exemption sits on the line holding `import(`.
2. The four rules, each testing one line unless stated:
   - `git-c-pwd`: the line holds `git -C` followed by `$PWD`, `"$PWD"`, `"${PWD}"`, `$(pwd)` or `"$(pwd)"`, and does not contain `dr_native_path`.
   - `awk-v-backslash`: from the `awk` word to the end of the line, first replace every `$(…)` command substitution (allow one level of nested parentheses) with `$()`. Then each `-v NAME=VALUE` option, VALUE being a double-quoted string, a single-quoted string or a bare word, hits when VALUE contains a backslash. A backslash inside a command substitution, or in an option that is not `-v` (`-F'\t'`), does not hit. Report one hit per line.
   - `jq-pwd-file`: applies only when the whole text has a line starting `export` and naming `MSYS_NO_PATHCONV`. For a line containing the word `jq`, take the text from `jq` on, replace `$(pwd)` with `$PWD`, blank out single-quoted strings, cut at the first `||`, `&&`, `|`, `;` or `)`, delete input redirections (`< file`, `<<< word`) and the value pairs of `--arg` and `--argjson`; it hits when what is left holds `$PWD`, `${PWD}`, `$TMPDIR` or `${TMPDIR}`.
   - `import-path`: scans the whole text, not lines, because a call may span lines. For each `import(`, read the argument up to the matching `)`. It hits unless the argument is empty, starts with a quote, starts with a template literal that begins `./` or `../`, or contains `pathToFileURL`.
3. Hit messages: `git-c-pwd` says git.exe cannot open a POSIX `$PWD` and names `dr_native_path`; `awk-v-backslash` says `awk -v` expands a backslash and to pass the value through `ENVIRON`; `jq-pwd-file` says jq.exe cannot open a POSIX path built from `$PWD` or `$TMPDIR` and to feed the file on stdin; `import-path` says a dynamic import of a path must go through `pathToFileURL`. This file is itself under `scripts/**`, so no message or comment may contain the text `import(` or a `git -C` followed by `$PWD`; write the `import-path` message as shown.
4. `lintTree(root)` resolves `root`, visits every file under `plugins/<name>/scripts`, `plugins/<name>/tests` (for each directory under `plugins`) and `scripts`, skips directories named `node_modules` and any file whose text holds a NUL character, and returns `<relative path with />:<line> <rule> <message>` strings in file-then-line order. A missing directory is not an error. When the file is run directly (the same `process.argv[1]` check `validate-repository.mjs` ends with), it lints `process.argv[2]` or the repository root, prints the lines to stdout, and sets `process.exitCode = 1` when there is any hit.
5. `scripts/validate-repository.mjs`: import `lintTree` and, in the block that runs when the file is the entry point, append `...lintTree(root)` to the `errors` array. Do not call it from `validateRepository(root)`: that function is tested on fixture roots. Leave the success message unchanged.
6. Run the lint over the tree: `timeout 60 node scripts/lint-portability.mjs`. On 2026-10-31 it finds one hit, `plugins/dforge/tests/dforge-config.test.sh:276 import-path`, in the node block of the `capped=$(DFORGE_CONFIG_MJS=…` assignment. Fix it rather than exempt it: in that block add `import { pathToFileURL } from "node:url";` beside the existing `import fs` line and change the dynamic import to `await import(pathToFileURL(process.env.DFORGE_CONFIG_MJS).href)`. Under Git Bash an environment variable holding a path reaches node as a Windows path, which an ESM `import()` refuses unless it is a file URL. If the run prints any other hit, fix it the same way when the line is wrong, or end the line with `# portability: ok — <reason>` (`// portability: ok — <reason>` in a `.mjs` file) when the line is deliberate, and state the reason in the comment.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `timeout 120 node --test tests/lint-portability.test.mjs tests/repository-layout.test.mjs`
Run: `timeout 60 node scripts/lint-portability.mjs; echo "lint exit $?"`
Run: `timeout 60 node scripts/validate-repository.mjs`
Run: `timeout 300 bash plugins/dforge/tests/dforge-config.test.sh | tail -1`
Expected: both node suites pass; the lint prints nothing and `lint exit 0`; validate-repository prints its valid line; the dforge-config suite ends `0 failed`.

- [ ] **Step 5: Commit**

```bash
git add scripts/lint-portability.mjs scripts/validate-repository.mjs tests/lint-portability.test.mjs plugins/dforge/tests/dforge-config.test.sh
git commit -m "feat(ci): lint Git Bash pitfalls in validation"
```

### Task 15: Enforce shard weights and warn on suite drift

**Files:**
- Modify: `scripts/test-shards.mjs` (the header comment, `windowsSeconds`, two new exports)
- Modify: `scripts/test-all.mjs` (`parseArgs`, `run()`, the listing loop, `suiteSeconds`, `suiteParts` and their comments)
- Modify: `plugins/dforge/tests/task-step.test.sh` (part selection; `plugins/dforge/tests/faster-plans.acceptance.test.sh` is the pattern and is not changed)
- Modify: `tests/test-shards.test.mjs`
- Modify: `CONTRIBUTING.md` (the paragraph that begins `CI runs the same checks on Ubuntu`)

**Interfaces:**
- Consumes: Contract C10 (the message `raise its suiteSeconds or split it`). `.github/workflows/validate.yml` is read for its 25-minute Windows step and is not changed.
- Produces: from `scripts/test-shards.mjs`, `windowsSeconds` (now exported), `checkShellWeights(jobs, weights = windowsSeconds)` returning an array of problem strings, and `driftWarning(args, seconds, limit)` returning a `::warning::` string or `undefined`. `node scripts/test-all.mjs --list --limits` prints `<limit seconds><TAB><args joined by spaces>` per job. `plugins/dforge/tests/task-step.test.sh` takes the parts `start`, `rereview`, `group`, `verdict` and declares them on an `ALL="…"` line.

**Items:** 5
**Implementer:** dforge:impl-opus-high
**Evaluation:** files 2 - spec 2 - coupling 1 - risk 2 = 7

- [ ] **Step 1: Write the failing test**

Replace `tests/test-shards.test.mjs` with this file. Its first four tests are the current tests; the second one's title changes (it describes new suites as weighted by default, which the shell-suite rule ends), and the module is also imported as a namespace so a missing export fails one test, not the whole file.

```js
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import test from 'node:test';
import * as sched from '../scripts/test-shards.mjs';
import { selectShard } from '../scripts/test-shards.mjs';

const runner = fileURLToPath(new URL('../scripts/test-all.mjs', import.meta.url));
const root = fileURLToPath(new URL('../', import.meta.url));
const bash = process.env.DR_TEST_BASH ?? 'bash';
function list(...args) {
  const result = spawnSync(process.execPath, [runner, '--list', ...args], { encoding: 'utf8', timeout: 10000 });
  assert.ifError(result.error);
  assert.equal(result.status, 0, result.stderr);
  return result.stdout.trim().split('\n');
}
function jobsWithLimits() {
  return list('--limits').map(line => {
    const [seconds, text] = line.split('\t');
    return ['', text.split(' '), Number(seconds)];
  });
}
const shell = (name, limit, ...part) => ['bash', [`plugins/dforge/tests/${name}`, ...part], limit];

test('Windows shards cover every discovered suite exactly once', () => {
  const all = list();
  const shards = Array.from({ length: 12 }, (_, i) => list('--shard', `${i + 1}/12`));
  assert.ok(shards.every(shard => shard.length > 0));
  assert.deepEqual(shards.flat().sort(), all.sort());
  assert.equal(new Set(shards.flat()).size, all.length);
  assert.deepEqual(list('--shard', '1/12'), shards[0]);
});

test('a job without a weight is scheduled at the default weight and unsharded runs retain their order', () => {
  const jobs = ['plan-lint.test.sh', 'task-state.test.sh', 'new-suite.test.sh'].map(name => ['bash', [name], 600]);
  assert.deepEqual(selectShard(jobs), jobs);
  assert.deepEqual(selectShard(jobs, '1/1'), jobs);
  const selected = [selectShard(jobs, '1/2'), selectShard(jobs, '2/2')].flat();
  assert.equal(selected.length, jobs.length);
  for (const job of jobs) assert.ok(selected.includes(job));
});

test('a suite run in parts splits its weight among them', () => {
  const lint = ['bash', ['plugins/dforge/tests/plan-lint.test.sh'], 900];
  const first = ['bash', ['plugins/dforge/tests/faster-plans.acceptance.test.sh', 'a1'], 600];
  const second = ['bash', ['plugins/dforge/tests/faster-plans.acceptance.test.sh', 'a2'], 600];
  const jobs = [lint, first, second];
  assert.deepEqual(selectShard(jobs, '1/2'), [lint]);
  assert.deepEqual(selectShard(jobs, '2/2'), [first, second]);
});

test('invalid shard arguments fail instead of silently skipping tests', () => {
  const jobs = [['bash', ['a'], 10], ['bash', ['b'], 10]];
  for (const shard of ['', '0/2', '3/2', '1/0', '1/3', '1.5/2', '1', '1/2/3', '1/9007199254740992']) {
    assert.throws(() => selectShard(jobs, shard), /Shard/);
  }
  const result = spawnSync(process.execPath, [runner, '--shard', '0/4'], { encoding: 'utf8', timeout: 10000 });
  assert.ifError(result.error);
  assert.notEqual(result.status, 0);
  assert.doesNotMatch(result.stdout, /Running /);
});

test('a shell suite needs a weight of at most 80% of its limit', () => {
  const rows = [
    { name: 'no weight', jobs: [shell('new.test.sh', 600)], weights: {}, want: [/new\.test\.sh: no weight/] },
    { name: 'no weight for the dr-status suite', jobs: [['bash', ['plugins/dr-status/tests/run-all.sh'], 420]], weights: {}, want: [/run-all\.sh: no weight/] },
    { name: 'exactly 80% passes', jobs: [shell('a.test.sh', 600)], weights: { 'a.test.sh': 480 }, want: [] },
    { name: 'above 80%', jobs: [shell('a.test.sh', 600)], weights: { 'a.test.sh': 481 }, want: [/a\.test\.sh: .*raise its suiteSeconds or split it/] },
    { name: 'a larger limit raises the bound', jobs: [shell('a.test.sh', 1200)], weights: { 'a.test.sh': 900 }, want: [] },
    { name: 'parts split the weight', jobs: [shell('a.test.sh', 600, 'a1'), shell('a.test.sh', 600, 'a2')], weights: { 'a.test.sh': 960 }, want: [] },
    { name: 'parts do not hide a heavy weight', jobs: [shell('a.test.sh', 600, 'a1'), shell('a.test.sh', 600, 'a2')], weights: { 'a.test.sh': 962 }, want: [/raise its suiteSeconds or split it/] },
    {
      name: 'jobs that are not shell suites keep the default weight',
      jobs: [['node', ['scripts/validate-repository.mjs'], 60], ['node', ['--test', 'tests/a.test.mjs'], 120], ['claude', ['plugin', 'test', 'plugins/dforge'], 300], ['tsc', ['--noEmit', '-p', 'plugins/dforge'], 300]],
      weights: {},
      want: [],
    },
  ];
  for (const row of rows) {
    const got = sched.checkShellWeights(row.jobs, row.weights);
    assert.equal(got.length, row.want.length, `${row.name}: ${got.join(' | ')}`);
    row.want.forEach((pattern, i) => assert.match(got[i], pattern, row.name));
  }
});

test('every shell suite of the repository has a weight within 80% of its limit', () => {
  assert.deepEqual(sched.checkShellWeights(jobsWithLimits()), []);
});

test('a suite run in parts runs every part its script declares', () => {
  const jobs = jobsWithLimits();
  for (const name of ['task-step.test.sh', 'faster-plans.acceptance.test.sh']) {
    const script = readFileSync(fileURLToPath(new URL(`../plugins/dforge/tests/${name}`, import.meta.url)), 'utf8');
    const declared = script.match(/^ALL="([^"]*)"\r?$/m);
    assert.ok(declared, `${name} declares its parts on an ALL="..." line`);
    const parts = jobs.filter(([, args]) => args[0] === `plugins/dforge/tests/${name}`);
    assert.ok(parts.length > 1, `${name} runs in parts`);
    assert.deepEqual(parts.flatMap(([, args]) => args.slice(1)).sort(), declared[1].split(' ').sort(), name);
  }
});

test('task-step.test.sh refuses a part it does not declare before it runs anything', () => {
  const result = spawnSync(bash, ['plugins/dforge/tests/task-step.test.sh', 'no-such-part'], { cwd: root, encoding: 'utf8', timeout: 15000 });
  assert.ifError(result.error);
  assert.equal(result.status, 2);
  assert.match(result.stderr, /unknown part no-such-part/);
});

test('a suite past 75% of its limit is named in a GitHub warning that test-all prints', () => {
  const args = ['plugins/dforge/tests/slow.test.sh', 'a1'];
  assert.equal(sched.driftWarning(args, 449, 600), undefined);
  assert.equal(sched.driftWarning(args, 450, 600), undefined);
  const warning = sched.driftWarning(args, 450.5, 600);
  assert.match(warning, /^::warning::/);
  assert.ok(warning.includes('plugins/dforge/tests/slow.test.sh a1'), warning);
  assert.match(warning, /600/);
  const source = readFileSync(runner, 'utf8');
  assert.match(source, /import \{[^}]*driftWarning[^}]*\} from '\.\/test-shards\.mjs'/);
  assert.match(source, /driftWarning\(args, /);
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `timeout 120 node --test tests/test-shards.test.mjs`
Expected: the first four tests pass and the other five fail: `sched.checkShellWeights is not a function`, `Unknown option '--limits'` (twice), a 15-second `ETIMEDOUT` from the `task-step.test.sh` run that ignores its argument (this one red run may leave the killed suite's children and temporary directory behind: after it, find them with `pgrep -f task-step.test.sh` and kill only those PIDs; it is the one exception to the no-leftover-process constraint), and `sched.driftWarning is not a function`. After sub-steps 1 and 2 of Step 3 the repository test fails for its real reason, and its message names every suite that lacks a weight or is over 80%.

- [ ] **Step 3: Implement**

1. `scripts/test-shards.mjs`:
   - Replace the last two lines of the header comment (`These are scheduling weights, not timeouts; newly discovered suites receive the default weight. A suite test-all runs in parts splits its weight evenly among them.`) with a comment saying: these are scheduling weights, not timeouts; the jobs that are not shell suites (`validate-repository.mjs`, the `--test` jobs, `claude plugin test`, `tsc`) take the default weight of 10; every shell suite needs an entry here, which `tests/test-shards.test.mjs` enforces together with a weight of at most 80% of the suite's limit; a suite run in parts splits its weight evenly among them.
   - Change `const windowsSeconds` to `export const windowsSeconds`. Keep `?? 10` in `selectShard`, which the non-shell jobs rely on.
   - Add an entry with value `10` for each of these 37 suites, in the object's alphabetical order. They have no weight today and all finish in under 1.2 s on Linux (measured 2026-10-31), so 10, the default they already run at, is three times their Linux time or more: `auto-default`, `auto-run-skills`, `codex-client`, `criteria`, `delegated-suite`, `dforge-dir`, `dforge-state`, `distilling-docs`, `executor-session`, `executors`, `final-phase`, `fleet`, `gates-manifest`, `impl-clauses`, `ladder`, `lanes`, `lock`, `migrate-skill`, `native-routing`, `parallel-grouping`, `polluter`, `process-roles`, `project-status`, `readme-unattended`, `run-codex-task`, `sdd-references`, `seats`, `settings-skills`, `skill-size`, `skill-split-planning`, `snapshot`, `task-step-text`, `test-simplifier`, `ui-lint`, `ui-ux-skill`, `waiting-text`, `worktree-instructions`, each with the `.test.sh` suffix. The failing test's output is the authority: when it names a suite not in this list that an earlier task added, give it three times its Linux seconds, at least 10.
   - Leave every existing weight unchanged.
   - Add `export function checkShellWeights(jobs, weights = windowsSeconds)`. A job is `[executable, args, limitSeconds]`. A shell suite is a job whose `args[0]` is `plugins/dr-status/tests/run-all.sh` or matches `plugins/dforge/tests/<name>.test.sh`; every other job is ignored. A suite's name is the last path segment of `args[0]`, and a suite run in parts counts as one suite whose part count is the number of its jobs. For each suite, once: with no entry in `weights`, report `<name>: no weight in scripts/test-shards.mjs; add it to windowsSeconds`; otherwise take `weights[name]` divided by the part count and, when that is above 0.8 times the job's limit, report `<name>: weight <each> s is above 80% of its <limit> s limit: raise its suiteSeconds or split it`. Return the reports as an array.
   - Add `export function driftWarning(args, seconds, limit)`: it returns `undefined` unless `seconds` is above 0.75 times `limit`, and then `::warning::<args joined by spaces, at most the first 120 characters> took <seconds rounded>s of its <limit>s limit`.
2. `scripts/test-all.mjs`:
   - Import `driftWarning` beside `selectShard`; add `limits: { type: 'boolean' }` to the `parseArgs` options.
   - In `run()`'s `exit` handler compute the elapsed seconds once, keep the `Finished …` line as it is, then print `driftWarning(args, elapsed, seconds)` with `console.log` when it is not `undefined`.
   - In the listing loop, print `${seconds}\t${args.join(' ')}` when `options.limits` is set and `args.join(' ')` otherwise.
   - Replace the two configuration objects with these values (the comments above them change to match: `faster-plans` now runs as three parts, `task-step` as four, and the 700 s limits keep `next-step` and `auto-run`, about 500 s on a Windows runner, under 80% of their limit; `task-step`'s limit applies to each part):

```js
const suiteSeconds = { 'plan-lint.test.sh': 1200, 'speed-and-cost-followups.acceptance.test.sh': 1200, 'task-loop-steps.acceptance.test.sh': 1200, 'task-step-base.test.sh': 900, 'task-step.test.sh': 900, 'next-step.test.sh': 700, 'auto-run.test.sh': 700 };
```

   and in `suiteParts`, replace the `faster-plans` entry with these two entries (the `speed-and-cost-followups` entry stays):

```js
  'faster-plans.acceptance.test.sh': [Array.from({ length: 8 }, (_, i) => `a${i + 1}`), Array.from({ length: 8 }, (_, i) => `a${i + 9}`), Array.from({ length: 7 }, (_, i) => `a${i + 17}`)],
  'task-step.test.sh': [['start'], ['rereview'], ['group'], ['verdict']],
```

   The `task-step` limit drops from 1450 s for the whole suite to 900 s per part: measured on 2026-10-31 the four parts take 24, 16, 13 and 15 s on Linux against 67 s whole, so the largest part is about 36% of the suite, about 480 s of the 1340-second Windows weight. The `faster-plans` thirds split `a1`-`a8`, `a9`-`a16` and `a17`-`a23`, which took 14, 12 and about 16 s on Linux. Neither weight changes (1340 over four parts is 335 s, 1200 over three is 400 s, both under 480).
3. `plugins/dforge/tests/task-step.test.sh`: add part selection that follows `faster-plans.acceptance.test.sh` (a `Usage:` comment, an `ALL` list, parts given as arguments, no argument runs all). Right after `set -uo pipefail` add: a `Usage:` comment (`bash task-step.test.sh` runs every part, `bash task-step.test.sh verdict` the named parts only); the line `ALL="start rereview group verdict"` exactly; a loop that lowercases each argument into `sel` and, for an argument not in `ALL`, prints `task-step.test.sh: unknown part <name> (parts: start rereview group verdict)` to stderr and exits 2 before any fixture work; `sel=$ALL` when no argument was given; and `want() { case " $sel " in *" $1 "*) return 0 ;; esac; return 1; }`. Then:
   - Move these definitions out of the sections they sit in, to just before the comment `# start: the assigned line, the dispatch file, the state and the digest.`, so every part has them: the six lines from `PR=$(cd "$P" && pwd)` through the `state_of() { … }` helper (under `# review: the preconditions.`), and the line `RR_S="$HERE/../scripts"` (under `# --- rereview: …`). `before=$(ws_count)` and everything else under `# review: the preconditions.` stays where it is.
   - Wrap five stretches in `if … fi`, each from the line named to the line before the next boundary: `if want start; then` from `# start: the assigned line, …` to before `# --- rereview: the skip rule, the package and the state ---`; `if want rereview || want verdict; then` from that `# --- rereview` comment through `cp "$RR_WS/task-2-step.json" "$RR_TMP/state2.0"` (the rereview fixture: its helpers, its repository and its five `rereview fixture:` checks); `if want rereview; then` from `# The skip rule: one open finding` to before `# --- hold and review --group: grouped tasks reviewed together ---`; `if want group; then` from that comment to before `# The re-review judge writes its report where the prompt says`; `if want verdict; then` from that comment to before the final `printf '\n%d passed, %d failed\n'`. Leave that `printf` and the `[ "$fail" -eq 0 ]` line outside every guard.
   - On 2026-10-31 a trial split like this printed `147`, `64`, `104` and `102 passed` for the four parts and `412 passed` for the whole file, 5 more than the whole because the `verdict` and `rereview` parts both run the five fixture checks. Keep those counts when you split it.
4. `tests/test-shards.test.mjs` is already the file of Step 1.
5. `CONTRIBUTING.md`: in the paragraph beginning `CI runs the same checks on Ubuntu`, change `six shards (--shard 1/6 through --shard 6/6; …)` to `twelve shards (--shard 1/12 through --shard 12/12; …)` and replace `New suites are discovered automatically, and scripts/test-shards.mjs holds the approximate timings used to balance the shards.` with sentences saying that a new shell suite is discovered automatically but needs a weight in `scripts/test-shards.mjs`, which `tests/test-shards.test.mjs` requires, and that a weight above 80% of the suite's limit (its `suiteSeconds` in `scripts/test-all.mjs`, else 600 s) fails the same test until the limit is raised or the suite is split.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `timeout 300 node --test tests/*.test.mjs`
Run: `for part in start rereview group verdict; do timeout 600 bash plugins/dforge/tests/task-step.test.sh "$part" | tail -n 1; done`
Run: `timeout 600 bash plugins/dforge/tests/task-step.test.sh | tail -n 1`
Run: `for part in "a1 a2 a3 a4 a5 a6 a7 a8" "a9 a10 a11 a12 a13 a14 a15 a16" "a17 a18 a19 a20 a21 a22 a23"; do timeout 600 bash plugins/dforge/tests/faster-plans.acceptance.test.sh $part | tail -n 1; done`
Run: `timeout 60 node scripts/test-all.mjs --list --limits | grep -E 'task-step.test.sh|faster-plans|next-step|auto-run.test'`
Run: `timeout 60 node -e "import('./scripts/test-shards.mjs').then(async m => { const { execFileSync } = await import('node:child_process'); const jobs = execFileSync(process.execPath, ['scripts/test-all.mjs', '--list'], { encoding: 'utf8' }).trim().split('\n').map(a => ['', a.split(' '), 600]); const name = j => j[1][0].split('/').at(-1); const parts = new Map(); for (const j of jobs) parts.set(name(j), (parts.get(name(j)) ?? 0) + 1); console.log(Array.from({ length: 12 }, (_, i) => Math.round(m.selectShard(jobs, (i + 1) + '/12').reduce((s, j) => s + (m.windowsSeconds[name(j)] ?? 10) / parts.get(name(j)), 0))).join(' ')); })"`
Expected: every node test passes. The four parts print `147`, `64`, `104` and `102 passed, 0 failed` and the whole file `412 passed, 0 failed`. The three `faster-plans` parts print `0 failed`. The listing shows `900` for four `task-step.test.sh` lines, `700` for `next-step` and `auto-run`, and `600` for three `faster-plans` lines. The last command prints twelve shard totals between 1100 and 1250 on 2026-10-31 (1174 to 1180 in the trial); any total above 1400 means a weight was entered wrongly, since a Windows shard has a 25-minute step.

- [ ] **Step 5: Commit**

```bash
git add scripts/test-shards.mjs scripts/test-all.mjs plugins/dforge/tests/task-step.test.sh tests/test-shards.test.mjs CONTRIBUTING.md
git commit -m "feat(ci): check shard weights and warn on drift"
```
