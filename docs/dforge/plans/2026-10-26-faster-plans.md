# Faster Plans Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: the skill the **Execution:** line names — dforge:subagent-driven-development for `subagent`, dforge:executing-plans for `inline`. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Plans carry contracts and tests instead of code, low-risk tasks are reviewed in groups, fix loops stop after two rounds, waves run the full check on a cadence, and judge seats reply in ten lines with their report in a file.

**Architecture:** Text changes to the dforge skills, references, agents and prompt templates, plus script changes in `plugins/dforge/scripts/` (`plan-lint`, `plan-revise`, `review-route`, `task-step`, `wave`, `next-step`, `plan-amend`) and the cockpit's ledger parser, each pinned by its existing test suite. Execution-side changes keep plans and ledgers written before this plan working unchanged.

**Tech Stack:** Bash (POSIX tools only; runs on Linux, macOS and Windows Git Bash), jq, Node 22 for `.mjs` evals, Bun/TypeScript for the cockpit, the `claude` CLI for plugin validation.

**Spec:** docs/dforge/specs/2026-10-26-faster-plans-design.md

**Execution:** subagent — `claude --model sonnet --effort high` — 12 of 13 tasks are heavy (total 5 or more)

**Parallelism:** sequential — the spec's execution strategy: the parts share `scripts/task-step`, `scripts/review-route` and `reference/delegated-task.md`.

**Plan review:** 2026-10-26 — dforge:judge-opus — executability 15 / coherence 12 / coverage 13 / assumptions 12 (round 1)

## Global Constraints

- This plan uses the contract-and-test task shape the spec introduces, approved by the owner for this plan on 2026-10-26 before `plan-lint` supports it: tasks give interfaces, complete test code and verify commands, and the implementer writes the implementation. Each task whose score the installed Rule S rejects carries an `**Override:**` line citing that approval.
- All paths below are relative to the repository root `/root/repositories/darkraise-ai-plugins` unless they start with `plugins/dforge/`, which is the plugin root.
- Plans and ledgers written before this plan must keep working: `docs/dforge/plans/*.md` in this repository and the fixture plans under `plugins/dforge/tests/fixtures/` must lint exactly as before, and every ledger grammar change accepts the old form on read.
- A `Host: codex` plan keeps its `codex-v4` protocol whole: Rule S at `reducible >= 4`, `review_cap: 5`, per-task review. Only the judge report contract (Task 9) reaches it.
- Scripts are Bash with `set -uo pipefail` like their neighbours, use `grep`/`sed`/`awk`/`jq` only (no `rg`, no GNU-only flags: CI runs uutils on ubuntu-latest and Git Bash on Windows; `mkdir` is not atomic there, no `flock`, `MSYS_NO_PATHCONV` breaks `jq.exe` paths).
- Test fixtures embedded in a test file prefix every plan line with `|` and strip it with `sed 's/^|//'`, so plan-lint's scans never read a quoted fixture as a task.
- Every test and CLI call is bounded (`timeout`), and a test leaves no process behind. A test needing a dead PID uses `sleep 0 & p=$!; wait $p`, never kills a fresh fork.
- Unset `CLAUDE_CONFIG_DIR` in any test that reads a budget, so the host's settings do not leak in.
- Commits are `<type>(<scope>): <subject>` (type feat|fix|docs|style|refactor|test|chore|perf; subject at most 50 characters, imperative, no period), made as `Darkraise <quangtc94@gmail.com>`, with no `Co-Authored-By`, `Claude-Session` or any AI attribution. `git add` names explicit files.
- Validation for a task touching a skill, agent or plugin manifest: `node scripts/validate-repository.mjs` and `timeout 120 /root/.local/bin/claude plugin validate plugins/dforge` (in Bash, `claude` is a shell function and exits 127; call the binary).
- English only. Inclusive terms (allowlist/blocklist, primary/replica, main branch).
- Do not edit historical plans or specs under `docs/` or `docs/superpowers/`; preserve existing `DCC_*` variables and statusline storage paths.

## Contracts

### Slice measurement

Produced by Task 1.

- `docs/dforge/notes/2026-10-26-slice-tasks.md` carries a `**Verdict:** KEEP | RULING` line. On `RULING` the task reports `DONE_WITH_CONCERNS` with the verdict as its first line, and the controller sends a `blocked-plan` item to the ruling seat before dispatching Task 2.

### Ladder

Produced by Task 2.

- `plugins/dforge/reference/ladder.md` `assignment` block gains `7 impl-opus-high` and `8 impl-opus-high`; rows 0-6 unchanged.
- Rule S for a Claude plan: split when `files + spec + coupling >= 6` or `spec = 3`. For a `Host: codex` plan: `files + spec + coupling >= 4` or `spec = 3`, as today.
- The `gate` block gains the line `max_score 4`; the lane gate admits no task whose total exceeds it.

### Plan review

Produced by Task 3.

- On a Claude plan, `scripts/review-route PLAN_FILE --plan-round R` prints `cap=2`, never `reason=cap-critical`, and exits 2 for R of 3 or more. A `Host: codex` plan's output is unchanged.

### Review tier

Produced by Task 4.

- `scripts/review-route PLAN_FILE --task N` adds the field `review=task` or `review=group` to its `review-seat …` line. `review=task` when the task's risk is 2 or more or its total is 5 or more; `review=group` otherwise. A task with no Evaluation line prints `review=task reason=unscored` and exits 0 instead of 2.
- With several task numbers (`--task N M …`) the line keeps routing by the highest total and carries no `review=` field.

### Group review

Produced by Task 5.

- `scripts/task-step hold PLAN_FILE N [--head REF] [--cwd DIR]` — records the task's head in `task-<N>-step.json` as `heldHead` and appends the ledger line `Task <N>: awaiting group review (commits <a7>..<b7>)`. Exit 0; exit 2 on usage, a bad ref or a `Host: codex` plan; exit 3 on no such task; exit 4 when `review-route --task N` says `review=task`; exit 6 when the task was never started.
- `scripts/task-step review --group PLAN_FILE N M … [--cwd DIR]` — every task must hold an `awaiting group review` line, else exit 4 naming it. `<list>` is the task numbers in ascending order joined by commas (`4,6,7`). Writes `<workspace>/group-<list>-step.json`, the package `<workspace>/group-<list>-review-package.md` (one section per task, headed `## Task <N>`, holding that task's brief path, report path and its `base..heldHead` diff), the prompt `<workspace>/group-<list>-review-prompt.md` from the group template, and records `group` (the list), `reviewHead`, `t0` and `round` in each member's `task-<N>-step.json`. `reviewHead` is the checkout's HEAD for a sequential member and the member's own `heldHead` for a wave member held with `--head`. A member's fix round re-reviews with `task-step rereview PLAN_FILE N` (no `--base`): the rereview reads the member's `group` and diffs from the group's current review head, which each member's rereview advances, so the second member fixed never sees the first member's fix as its own.
- Group template: `plugins/dforge/skills/subagent-driven-development/references/group-reviewer-prompt.md`, placeholders `[GROUP_LIST]`, `[PACKAGE_FILE]`, `[REPORT_FILE]`, `[PLUGIN_ROOT]`.
- Ledger: `Group <list>: review round R/2 (Task <N>: <k> open — <one-liners> | clean; …; commits <a7>..<b7> (Task <N>)[, <a7>..<b7> (Task <M>)])`, one range per fixed member. `<list>` is a comma list or an `a-b` range; the cockpit's `parseLedger` accepts both.

### Fix loop

Produced by Task 7.

- Ledger: `Task <N>: fix round R/2 (…)`, `Group <list>: review round R/2 (…)`, `Wave <k>: fix round R/2 (…)`. The `progress p -> q` field is removed. A line read with `R/5` maps to round R of 2: R = 1 resumes at round 2; R >= 2 goes to the breaker.
- `scripts/task-step rereview` refuses a third round: it writes nothing, names the breaker on stderr and exits 7.

### Waves

Produced by Task 8.

- Plan header line `**Wave check:** <command>` (optional; waves plans only).
- `scripts/wave check-due PLAN_FILE K` prints exactly one of `full`, `wave-check`, `none` and exits 0. `full` when K is a multiple of 3, when wave K holds a task with risk 3, or when K is the last wave in the Parallelism line; else `wave-check` when the header has a `**Wave check:**` line; else `none`. Exit 2 on a plan with no waves Parallelism line or K out of range; exit 4 when the waves line does not parse (as `scripts/wave` does today).
- Ledger: `Wave <k>: merged (head <sha7>; check at wave <m>)` and `Wave <k>: integrated (head <sha7>; <command> → pass[; baseline failures only])`. Every wave, one-task waves included, ends with one of them.
- `<workspace>/base-proof-failures.txt`: one failing-test line per line, as `scripts/suite-run` prints them in its digest, written by the base proof.

### Judge reports

Produced by Task 9.

- Each of `plugins/dforge/agents/judge-opus.md`, `judge-sonnet-high.md`, `judge-fable.md` lists `Write` in `tools:`.
- Every judge prompt template carries a `[REPORT_FILE]` placeholder and the instruction to write the full report there, write nothing else, and reply in at most 10 lines: verdict, scores, finding counts by severity, report path (a BLOCKED ruling adds the decision a human must make).
- Every report opens with `## Verdict`, holding `key: value` lines (`spec: pass|fail|cannot-verify`, `quality: approved|changes`, `scores: spec s / scope c / verification v / quality q` for task and group reviews; `Verdict:` and `Ruling:` lines for rulings). Findings follow under `## Findings` as `- [Critical|Important|Minor] <file>:<line> — <one-liner>`; a group report prefixes the file with `(Task <N>) `. Cannot-verify items go under `## Cannot verify` as `- <one-liner>`.
- `[REPORT_FILE]` now names the judge's own report. Where the task-reviewer and re-review templates used it for the implementer's report, that placeholder becomes `[IMPLEMENTER_REPORT_FILE]`, and `task-step` fills it under the new name.
- A finding line may be followed by two-space-indented detail lines; `<line>` is `0` when no line applies. In a group report, cannot-verify items also carry `(Task <N>) `. The architecture critic and the Fable spec review keep the Blocker / High / Medium / Nit scale in place of Critical / Important / Minor. A re-review's `## Verdict` uses `fix round: addressed|open` and `open: <k>`. A ruling report numbers its entries `## A<k> — Task <N>`, and each AMEND item carries an `Amendment: A<k>` line.
- Report files in the plan workspace: `task-<N>-review-report.md`, `task-<N>-rereview-<R>-report.md`, `group-<list>-review-report.md` (a member's fix round re-reviews alone and writes `task-<N>-rereview-<R>-report.md`), `rulings-<point>-<task>-report.md`.

### Verdict and amend

Produced by Task 10.

- `scripts/task-step verdict PLAN_FILE N [M …] [--group] [--rereview R] [--cwd DIR]` — reads the report file named above, checks the reviewed worktree's tracked files match what the review step recorded, prints a digest of at most 20 lines plus one line per Critical or Important finding (`<severity> <task> <file>:<line> — <one-liner>`), and writes the findings to the next fix file `task-<N>-fix-<R>.md` (one per task with findings). Exit 0 ok; exit 5 when the report file is missing or malformed; exit 6 when a tracked file changed (naming the files on stderr) or the review step was not run. The review and rereview steps record a `reviewCheck` field in the step file for the comparison. `verdict` writes the deferred-Minor ledger lines itself.
- `scripts/plan-amend PLAN_FILE --report <file> --id A<k>` — extracts the AMEND entry `## A<k>` through its New fence's closing line from a ruling report and applies it exactly as `plan-amend PLAN_FILE <entry-file>` does today.

## Assumptions (evidence)

- Rule S splits at `files + spec + coupling >= 4` and the assignment table stops at 6 today: `plugins/dforge/reference/ladder.md` §Rule S and §Assignment table, read 2026-10-26.
- Code-free tasks pass on the first attempt at every Sonnet and Opus tier at Rule-S size: `evals/tiers/results/results.tsv` rep 1, stripped stage, after the three owner-excluded case defects (rows marked `EXCLUDED … owner ruling 2026-10-02`), read 2026-10-26. Slice-sized tasks: unverified — Task 1 verifies it.
- Judge agents hold only Read, Grep, Glob and WebFetch: `plugins/dforge/agents/judge-*.md` `tools:` lines and `tests/fleet.test.sh` `ROLE_TOOLS`, read 2026-10-26.
- No separate scoring lane-gate script exists: `grep -rln min_score plugins/dforge/scripts` lists only `plan-lint` and `plan-revise` (2026-10-26); `scripts/codex-gate`, named by `reference/executors/codex.json` `"gate"`, checks session availability only.
- A live ledger in the old grammar exists and must keep resuming: `darkcloud/.worktrees/book-intelligence/.dforge/sdd/2026-10-26-book-intelligence/progress.md` (18 tasks complete, `fix round 1/5` lines), read 2026-10-26.
- Acceptance QA runs on `impl-sonnet-high`, not a judge (`plugins/dforge/reference/acceptance-qa.md:11`), so Task 12 leaves its template unchanged.
- No task writes the spec §7 acceptance suite: the final review's acceptance QA (`reference/final-review.md` step 0.5, `reference/acceptance-qa.md`) writes `plugins/dforge/tests/faster-plans.acceptance.test.sh` from the spec's A1-A23, as it did for the task-loop-steps spec. The controller's QA dispatch names the fixture ledger to cut from book-intel's (`fix round 1/5` lines, a `Wave … integrated` line) for A12 and A22, and A23's Codex five-round check.
- Plan review round 1 (2026-10-26) scored coherence 12, coverage 13 and assumptions 12 (borderline). Decision: every Important finding was fixed in the tasks or answered above; no Critical and no score of 8 or below, so no second round ran.
- `claude` is a shell function in Bash here and exits 127; validation calls `/root/.local/bin/claude` (2.1.310, checked 2026-10-26).
- The installed plugin (4.5.0) lints this plan with the old Rule S and table: every task whose `files + spec + coupling` is 4 or 5, or whose total is 7 or 8, carries an owner-approved `**Override:**` line, and `plan-lint` reports those as warnings.

## Task index

1. Measure slice-sized code-free tasks
2. Ladder, Rule S and the lane gate
3. Plan shape text and review rounds
4. Review tier in review-route
5. Group review state in task-step
6. Group review in the skill text, recovery and the cockpit
7. Cap the fix loop at two rounds
8. Run the wave check on a cadence
9. Judge agents and task-loop report files
10. task-step verdict and plan-amend --report
11. Plan and spec seats write report files
12. Final-review and standalone seats write report files
13. Describe the new plan shape and loop in the README

---


### Task 1: Measure slice-sized code-free tasks

**Files:**
- Modify: `evals/tiers/lib/cases.mjs` (new `SLICE_CAP`, `SLICES`, `scoreSlice`, `slices`, `sliceId`, `orderSlices`, `pickSlices`, `sliceBrief`; `golden` and `readManifest` learn slices)
- Modify: `evals/tiers/build-case.mjs` (`buildCase` for pool `slice`; `findCase` reads the slice manifest)
- Modify: `evals/tiers/build-manifest.mjs` (the `--slices` mode)
- Modify: `evals/tiers/run-grid.mjs` (the `slice` stage)
- Modify: `evals/tiers/lib/decide.mjs` (`SLICE_ASSIGNED`, `SLICE_PASS`, `decideSlices`)
- Modify: `evals/tiers/report.mjs` (the `## Slice cases` section)
- Modify: `evals/tiers/arms.json` (the `slice` arms)
- Modify: `evals/tiers/README.md` (Commands and Files tables)
- Modify: `evals/tiers/tests/fixture.mjs`, `evals/tiers/tests/stub-claude.mjs` (test helpers)
- Test: `evals/tiers/tests/cases.test.mjs`, `evals/tiers/tests/build.test.mjs`, `evals/tiers/tests/decide.test.mjs`, `evals/tiers/tests/manifest.test.mjs`, `evals/tiers/tests/grid.test.mjs`
- Create: `evals/tiers/cases/slices.tsv`, `evals/tiers/cases/slices-excluded.tsv` (written by Step 6's build)
- Modify: `evals/tiers/results/results.tsv` (rows Step 6's run appends)
- Create: `docs/dforge/notes/2026-10-26-slice-tasks.md`

**Interfaces:**
- Consumes: the tier harness as it stands — `candidates`, `golden`, `brief`, `planAt`, `slug` (`lib/cases.mjs`), `strip`, `addedLines`, `MARKER` (`lib/strip.mjs`), `taskBrief`, `tasks`, `taskText`, `filesBlock` (`lib/plan.mjs`), `snapshot`, `runCell`, `gradeImpl`. The §1 assignment for totals 5 to 8 (Contracts, Ladder (Task 2)) is fixed in `lib/decide.mjs` as a constant, because this task runs before Task 2 puts rows 7 and 8 in the ladder.
- Produces: `docs/dforge/notes/2026-10-26-slice-tasks.md`, whose `**Verdict:**` line keeps §1 or stops the plan for a ruling. No later task consumes code from this one.

**Items:** 2

**Implementer:** dforge:impl-sonnet-high
**Evaluation:** files 3 - spec 2 - coupling 0 - risk 0 = 5
**Override:** owner approved the contract-and-test task shape for this plan on 2026-10-26, before plan-lint's Rule S and assignment table allow it

- [ ] **Step 1: Write the failing tests**

In `evals/tiers/tests/fixture.mjs`, inside `fixture()`, directly below the line that writes `greet.patch`, add the patch a run that implements Tasks 1 and 2 together would leave:

```js
  writeFileSync(join(stub, 'slice.patch'), spawnSync('git', ['diff', planned, shout], { cwd: repo, encoding: 'utf8' }).stdout);
```

In the same function's `arms.json` object, between the `review:` and `grader:` keys, add:

```js
    slice: ['impl-sonnet-high', 'impl-opus-medium', 'impl-opus-high'],
```

In `evals/tiers/tests/stub-claude.mjs`, directly below the `if (mode === 'pass') …` line, add the mode that applies the slice patch:

```js
else if (mode === 'slice') { spawnSync('git', ['apply', join(dir, 'slice.patch')], { stdio: 'ignore' }); reply('**Status:** DONE'); }
```

In `evals/tiers/tests/cases.test.mjs`, replace the import line

```js
const { candidates, golden, plans, readManifest, select, slug, strippedRow } = await import('../lib/cases.mjs');
```

with

```js
const { candidates, golden, plans, readManifest, select, slug, strippedRow, slices, scoreSlice, orderSlices, pickSlices, sliceId, SLICE_CAP } = await import('../lib/cases.mjs');
```

and append at the end of the file:

```js
test('scoreSlice scores the merged task with spec 2 under the relaxed Rule S', () => {
  const m = (task, allowed, tests, axes) => ({ task, allowed, tests, axes: { files: 0, spec: 0, coupling: 0, risk: 0, ...axes } });
  assert.deepEqual(
    scoreSlice([m(1, ['a.sh', 't/a.test.sh'], ['t/a.test.sh'], { coupling: 1, risk: 2 }), m(2, ['b.sh', 't/a.test.sh'], ['t/a.test.sh'], { spec: 1, risk: 1 })]),
    { axes: { files: 1, spec: 2, coupling: 1, risk: 2, total: 6 }, allowed: ['a.sh', 't/a.test.sh', 'b.sh'], tests: ['t/a.test.sh'] },
  );
  const seven = ['a', 'b', 'c', 'd', 'e', 'f', 'g'].map(x => `${x}.sh`);
  assert.deepEqual(scoreSlice([m(1, seven.slice(0, 4), [], { coupling: 1 }), m(2, seven.slice(4), [], {})]), { reason: 'Rule S: files 3 + spec 2 + coupling 1 = 6' });
  assert.deepEqual(scoreSlice([m(1, seven.slice(0, 4), [], {}), m(2, seven.slice(2, 6), [], { risk: 1 })]).axes, { files: 2, spec: 2, coupling: 0, risk: 1, total: 5 });
  assert.deepEqual(scoreSlice([m(1, ['a.sh'], [], { coupling: 1 }), m(2, ['b.sh'], [], {})]), { reason: 'total 4: §1 assigns no slice arm' });
  assert.deepEqual(scoreSlice([m(5, ['a.sh'], [], { spec: 3 }), m(6, ['b.sh'], [], {})]), { reason: 'Task 5 scores spec 3' });
});

test('slices merges consecutive eligible tasks committed in task order', () => {
  const found = slices(all);
  assert.deepEqual(found.map(w => [w.plan, w.tasks, w.base, w.result, w.reason]), [[PLAN, [1, 2], fx.planned, fx.shout, undefined]]);
  assert.deepEqual(found[0].axes, { files: 2, spec: 2, coupling: 0, risk: 2, total: 6 });
  assert.deepEqual([found[0].allowed, found[0].tests], [['src/greet.sh', 'tests/greet.test.sh', 'src/shout.sh', 'tests/shout.test.sh'], ['tests/greet.test.sh', 'tests/shout.test.sh']]);
  assert.equal(sliceId(found[0]), 'l-fixture-t1-2');
  const swapped = slices(all.map(c => c.task === 1 ? { ...c, result: fx.shout } : c.task === 2 ? { ...c, base: fx.planned, result: fx.greet } : c));
  assert.equal(swapped[0].reason, 'the tasks were not committed in task order');
});

test('orderSlices goes round-robin across plans and pickSlices checks until the cap', async () => {
  const w = (plan, ...tasks) => ({ plan, tasks });
  const name = x => `${x.plan}${x.tasks.join('')}`;
  const ordered = orderSlices([w('b', 4, 5), w('a', 2, 3), w('a', 1, 2), w('b', 6, 7), w('a', 1, 2, 3)]);
  assert.deepEqual(ordered.map(name), ['a123', 'b45', 'a12', 'b67', 'a23']);
  const checked = [];
  const { picked, excluded } = await pickSlices(ordered, async x => {
    checked.push(name(x));
    return name(x) === 'b45' ? 'the tests already pass on the base commit' : null;
  }, 2);
  assert.deepEqual(picked.map(name), ['a123', 'b67']);
  assert.deepEqual(checked, ['a123', 'b45', 'b67']);
  assert.deepEqual(excluded.map(x => [name(x), x.reason]), [
    ['b45', 'the tests already pass on the base commit'],
    ['a12', 'overlaps a picked slice'],
    ['a23', 'not selected: 2 slices already picked'],
  ]);
  assert.equal(SLICE_CAP, 5);
});

test('golden checks a slice against its merged brief and its last commit', async () => {
  const [slice] = slices(all);
  assert.equal(await golden(slice), null);
  assert.equal(await golden({ ...slice, result: fx.greet }), 'tests/shout.test.sh fails on the result commit');
});

test('readManifest reads a slice row with its task list', () => {
  const file = join(fx.top, 'slices.tsv');
  writeFileSync(file, `# start ${fx.planned}\nid\tpool\trow\tplan\ttask\ttasks\tbase\tresult\nl-x-t2-3\tslice\t6\tp.md\t2\t2,3\tb\tr\n`);
  assert.deepEqual(readManifest(file), { start: fx.planned, cases: [{ id: 'l-x-t2-3', pool: 'slice', row: 6, plan: 'p.md', task: 2, tasks: [2, 3], base: 'b', result: 'r' }] });
});
```

Append to `evals/tiers/tests/build.test.mjs`:

```js
test('a slice case merges its tasks into one stripped brief', () => {
  const slice = { id: 'l-fixture-t1-2', pool: 'slice', row: 6, plan: PLAN, task: 1, tasks: [1, 2], base: fx.planned, result: fx.shout };
  const { info, prompt } = buildCase(slice, join(fx.work, 'slice'));
  const brief = readFileSync(join(info.work, '.superpowers/sdd/eval/task-1-brief.md'), 'utf8');
  assert.equal(brief.split(MARKER).length - 1, 2);
  assert.doesNotMatch(brief, /echo hello|echo HELLO|\*\*Evaluation:\*\*|\*\*Implementer:\*\*/);
  assert.match(brief, /^# Tasks 1-2: Greet; Shout\n/);
  assert.match(brief, /^## Part 1 \(Task 1\): Greet$[\s\S]*\[ "\$out" = "hello" \][\s\S]*^## Part 2 \(Task 2\): Shout$[\s\S]*\[ "\$out" = "HELLO" \]/m);
  assert.equal(brief.split('\n## Plan header excerpt\n').length - 1, 1);
  assert.deepEqual([existsSync(join(info.work, 'docs/superpowers')), existsSync(join(info.work, 'src/greet.sh'))], [false, false]);
  assert.match(prompt, /^You are implementing Tasks 1-2: Greet; Shout\n/);
  assert.match(prompt, /These are Tasks 1 and 2 of the plan 2026-09-20-fixture\.md, merged into one task: implement every part of the brief\./);
  assert.match(prompt, /write that code yourself\. The plan file is not available\./);
  assert.deepEqual([info.result, info.allowed, info.tests], [fx.shout, ['src/greet.sh', 'tests/greet.test.sh', 'src/shout.sh', 'tests/shout.test.sh'], ['tests/greet.test.sh', 'tests/shout.test.sh']]);
});
```

Append to `evals/tiers/tests/decide.test.mjs` (the dynamic import keeps the file's other tests running while the exports are missing):

```js
test('decideSlices keeps §1 on four passes on the assigned arm and asks for a ruling below', async () => {
  const { decideSlices, SLICE_PASS, SLICE_CASES } = await import('../lib/decide.mjs');
  const slice = (id, row) => ({ id, row, pool: 'slice' });
  const five = [slice('l1', 5), slice('l2', 6), slice('l3', 7), slice('l4', 8), slice('l5', 6)];
  const arms = ['impl-sonnet-high', 'impl-opus-medium', 'impl-opus-high'];
  const keep = decideSlices(arms, five, table({ 'impl-sonnet-high': { all: pass(1) }, 'impl-opus-medium': { all: fail(1) }, 'impl-opus-high': { all: pass(2), l4: fail(2) } }));
  assert.equal(keep.verdict, 'KEEP §1 - the assigned arm passed 4 of 5');
  assert.deepEqual(keep.rows[0], { id: 'l1', total: 5, assigned: 'impl-sonnet-high', outcomes: ['PASS', 'FAIL', 'PASS'] });
  assert.deepEqual(keep.rows.map(r => r.assigned), ['impl-sonnet-high', 'impl-opus-high', 'impl-opus-high', 'impl-opus-high', 'impl-opus-high']);
  const ruling = decideSlices(arms, five, table({ 'impl-sonnet-high': { all: fail(1) }, 'impl-opus-high': { all: pass(2), l4: fail(2) } }));
  assert.equal(ruling.verdict, 'RULING - the assigned arm passed 3 of 5; §1 needs 4 of 5');
  assert.deepEqual(ruling.rows[0].outcomes, ['FAIL', '-', 'PASS']);
  const allPass = table({ 'impl-sonnet-high': { all: pass(1) }, 'impl-opus-high': { all: pass(2) } });
  assert.equal(decideSlices(arms, five.slice(0, 4), allPass).verdict, 'RULING - the assigned arm passed 4 of 4; §1 needs 4 of 5');
  assert.equal(decideSlices(arms, five, table({ 'impl-opus-high': { all: pass(2) } })).verdict, 'INCOMPLETE - 1 assigned cells are not scored');
  assert.equal(decideSlices(arms, [], table({})).verdict, 'NOT MEASURED - no slice case');
  assert.deepEqual([SLICE_PASS, SLICE_CASES], [4, 5]);
});
```

Append to `evals/tiers/tests/manifest.test.mjs`:

```js
test('build-manifest --slices writes the slice cases and their exclusions', () => {
  const r = spawnSync(process.execPath, [fileURLToPath(new URL('../build-manifest.mjs', import.meta.url)), '--slices'], { cwd: fx.repo, encoding: 'utf8' });
  assert.equal(r.status, 0, r.stderr);
  assert.match(r.stdout, /build-manifest: 1 slices, 0 exclusions, start [0-9a-f]{40}/);
  const { cases } = readManifest(join(fx.data, 'cases/slices.tsv'));
  assert.deepEqual(cases.map(c => [c.id, c.pool, c.row, c.task, c.tasks, c.base, c.result]), [['l-fixture-t1-2', 'slice', 6, 1, [1, 2], fx.planned, fx.shout]]);
  assert.equal(readFileSync(join(fx.data, 'cases/slices-excluded.tsv'), 'utf8'), 'plan\ttasks\treason\n');
  assert.equal(spawnSync(process.execPath, [fileURLToPath(new URL('../build-manifest.mjs', import.meta.url)), '--bogus'], { cwd: fx.repo }).status, 2);
});

test('the real arms table holds the three slice arms', () => {
  const arms = JSON.parse(readFileSync(new URL('../arms.json', import.meta.url), 'utf8'));
  assert.deepEqual(arms.slice, ['impl-sonnet-high', 'impl-opus-medium', 'impl-opus-high']);
  for (const arm of arms.slice) assert.equal(existsSync(resolve(PLUGIN, 'agents', `${arm}.md`)), true, arm);
});
```

Append to `evals/tiers/tests/grid.test.mjs`, after its last test (the tests share one results file, so these run last):

```js
test('the slice stage needs its manifest', () => {
  const none = node('run-grid.mjs', ['--stage', 'slice']);
  assert.equal(none.status, 2);
  assert.match(none.stderr, /no slice manifest; run build-manifest\.mjs --slices/);
});

test('the slice stage runs every slice arm and the report states the slice verdict', () => {
  assert.equal(node('build-manifest.mjs', ['--slices']).status, 0);
  modes(fx.stub, 'slice', 'slice', 'blocked');
  const ran = node('run-grid.mjs', ['--stage', 'slice']);
  assert.equal(ran.status, 0, ran.stderr);
  assert.match(ran.stdout, /run-grid stage=slice rep=1 ran=3 remaining=0/);
  assert.deepEqual(rows('results.tsv').filter(r => r[1] === 'slice').map(r => r.slice(2, 7)), [
    ['l-fixture-t1-2', 'slice', '6', 'impl-sonnet-high', 'PASS'],
    ['l-fixture-t1-2', 'slice', '6', 'impl-opus-medium', 'PASS'],
    ['l-fixture-t1-2', 'slice', '6', 'impl-opus-high', 'BLOCKED'],
  ]);
  assert.match(node('report.mjs').stdout, /## Slice cases\n\n\| Case \| Total \| Assigned \| `impl-sonnet-high` \| `impl-opus-medium` \| `impl-opus-high` \|\n\|---\|---\|---\|---\|---\|---\|\n\| `l-fixture-t1-2` \| 6 \| `impl-opus-high` \| PASS \| PASS \| BLOCKED \|\n\nSlice verdict: RULING - the assigned arm passed 0 of 1; §1 needs 4 of 5\n/);
  assert.match(node('run-grid.mjs', ['--stage', 'slice']).stdout, /ran=0 remaining=0/);
});
```

- [ ] **Step 2: Run them to verify they fail**

Run: `timeout 600 node --test evals/tiers/tests/*.test.mjs`
Expected: FAIL — 11 of 79 tests: the five new `cases.test.mjs` tests (`scoreSlice`, `slices`, `orderSlices`/`pickSlices` are not functions; `readManifest` returns `tasks` as the string `'2,3'`), the slice `buildCase` test (no `MARKER`: pool `slice` is built as written), `decideSlices` (not exported), both `--slices` manifest tests (the flag is ignored and the normal manifest is built; `arms.slice` is undefined), and both grid tests (`--stage slice` is a usage error). The other 68 pass.

- [ ] **Step 3: Implement**

`evals/tiers/lib/cases.mjs`:

1. Export `SLICE_CAP = 5` and `SLICES = resolve(DATA, 'cases/slices.tsv')`.
2. `scoreSlice(members)` — `members` are candidate rows in task order, each with `task`, `axes`, `allowed`, `tests`. Return `{ reason }` for the first rule that fails, in this order: a member whose `axes.spec` is 3 gives `Task <n> scores spec 3`; with `allowed` and `tests` the members' lists joined in member order without duplicates, `files` is 0 for one path, 1 for two or three, 2 for four to six, 3 for seven or more; `spec` is 2; `coupling` and `risk` are the members' highest; `files + 2 + coupling >= 6` gives `Rule S: files <f> + spec 2 + coupling <c> = <sum>`; a total (`files + 2 + coupling + risk`) below 5 gives `total <t>: §1 assigns no slice arm`. Otherwise return `{ axes: { files, spec: 2, coupling, risk, total }, allowed, tests }`.
3. `slices(all)` — `all` is `candidates(start)`. For every plan and every task `n` without a `reason`, for size 3 and then size 2, when tasks `n` to `n + size - 1` of that plan all lack a `reason`, form one window `{ plan, tasks, task: n, base: <first member's base>, result: <last member's result> }`. A window whose consecutive members fail `git merge-base --is-ancestor <earlier result> <later base>` (run through `sh`, exit not 0) gets `reason: 'the tasks were not committed in task order'`; otherwise it takes `scoreSlice`'s `axes`, `allowed` and `tests`, or its `reason`. A clean window has no `reason` key. Return windows by plan, then first task, then larger size first.
4. `sliceId(w)` returns `` `l-${slug(w.plan)}-t${w.tasks[0]}-${w.tasks.at(-1)}` ``.
5. `orderSlices(windows)` — pure: group by plan in `localeCompare` order, sort each group by first task ascending and then size descending, and take one window per plan per pass, as `select` does, without a cap.
6. `async pickSlices(ordered, check, cap = SLICE_CAP)` — walk `ordered`: once `cap` windows are picked, every remaining window is excluded with `not selected: <cap> slices already picked`; a window sharing a task number with a picked window of the same plan is excluded with `overlaps a picked slice` and `check` is not called for it; otherwise `await check(w)`: `null` picks it, any other value excludes it with that value as `reason`. Return `{ picked, excluded }`, excluded windows as `{ ...w, reason }` in walk order.
7. `sliceBrief(c, dir)` — `c` has `plan`, `tasks`, `base`. Write the plan as it stood at `c.base` into `dir` with `planAt` (throw `${c.plan} is missing at ${c.base}` as `brief` does). For each task `n`, part `k` from 1, take `taskBrief(<plan file>, n, join(dir, \`t${n}\`))` and split it at the first `\n## Plan header excerpt\n`. In the part before it drop every line that starts with `**Implementer:**`, `**Evaluation:**` or `**Override:**`, and replace its first line (the task heading) with `## Part <k> (Task <n>): <title>`, the title from `tasks(<plan file>)`. Return, joined by blank lines: `# Tasks <first>-<last>: <titles joined by '; '>`, `One task made of <K> parts: implement every part, in order, as a single change.`, the parts, and then the first task's excerpt starting at its `\n## Plan header excerpt\n` when it has one, so the excerpt appears once.
8. `golden(c)` — when `c.tasks` is set, build the brief with `sliceBrief`, return `stripping removes no code` when `strip(<brief>, addedLines(c.base, c.result)).removed` is 0 (checked right after the brief builds), and take both snapshots with `['docs/superpowers']` dropped, so a slice whose tests read the plan directory fails here rather than in the run (the owner excluded three stripped cases for that on 2026-10-02). Every other step and message is unchanged; a case without `tasks` is checked exactly as today.
9. `readManifest(file)` — a row whose header has a `tasks` column gets `tasks` as an array of numbers split on `,`; a row without the column gets no `tasks` key.

`evals/tiers/build-case.mjs`:

10. `buildCase(c, dir)` — pool `slice` is stripped like pool `stripped` (same snapshot drop, same `strip`), with `sliceBrief` in place of `brief`. Its `allowed` and `tests` are the `filesBlock` lists of each task in `c.tasks`, joined in task order without duplicates. The brief and report files are named by `c.task` (`task-<first>-brief.md`, `task-<first>-report.md`). The prompt's `Task N: [task name]` becomes `Tasks <first>-<last>: <titles joined by '; '>`, and its scene-setting becomes `These are Tasks <list> of the plan <basename>, merged into one task: implement every part of the brief. The tasks before them are already in this repository; the tasks after them are not your concern.` followed by the stripped sentence pool `stripped` already appends; `<list>` is `1 and 2` for two tasks and `4, 5 and 6` for three. `case.json` is written as today.
11. `findCase(id)` searches the manifest, then `SLICES` when it exists, then the review cases.

`evals/tiers/build-manifest.mjs`:

12. With no argument, behaviour is unchanged. With `--slices`, after the same dirty-plugin check and start commit: `slices(candidates(start))`, then `pickSlices(orderSlices(<windows without a reason>), golden)`. Write `cases/slices.tsv`: `# start <sha>`, the header `id pool row plan task tasks base result` (tab-separated), and one row per picked window in pick order: `sliceId(w)`, `slice`, `w.axes.total`, `w.plan`, `w.tasks[0]`, `w.tasks.join(',')`, `w.base`, `w.result`. Write `cases/slices-excluded.tsv`: header `plan tasks reason` (tab-separated) and one row per window with a reason from `slices` or `pickSlices`, sorted by plan, then first task, then size descending, `tasks` joined by `,`. Print `build-manifest: <n> slices, <m> exclusions, start <sha>`. Any other argument prints `usage: build-manifest.mjs [--slices]` to stderr and exits 2 before anything is read. Update the usage comment at the top.

`evals/tiers/run-grid.mjs`:

13. Add `slice` to `STAGES` (the usage line lists it). For `--stage slice`, exit 2 with `run-grid: no slice manifest; run build-manifest.mjs --slices` on stderr when `SLICES` does not exist; otherwise read `readManifest(SLICES)`, and check the plugin against that manifest's start commit with the existing message. `cells()` returns, for the slice stage, every slice case on every arm of `arms.slice`, in manifest order and arm order. Every other stage is unchanged. Update the header comment.

`evals/tiers/lib/decide.mjs`:

14. Export `SLICE_ASSIGNED = { 5: 'impl-sonnet-high', 6: 'impl-opus-high', 7: 'impl-opus-high', 8: 'impl-opus-high' }` with a one-line comment saying these are the relaxed Rule S's assignment rows, fixed here because the harness measures them before the ladder carries them; `SLICE_PASS = 4`; and `SLICE_CASES = 5`.
15. `decideSlices(arms, cases, cell)` returns `{ verdict, pass, of, rows }`. `rows` holds one `{ id, total, assigned, outcomes }` per case, with `total` the case's `row`, `assigned` from `SLICE_ASSIGNED`, and `outcomes` each arm's `cell(id, arm)?.outcome`, or `-` when unscored. `pass` counts cases whose assigned arm's outcome is `PASS`; `of` is the case count. The verdict is `NOT MEASURED - no slice case` with no case; `INCOMPLETE - <k> assigned cells are not scored` while any assigned cell is unscored; `KEEP §1 - the assigned arm passed <pass> of <of>` when `of >= SLICE_CASES` and `pass >= SLICE_PASS`; else `RULING - the assigned arm passed <pass> of <of>; §1 needs 4 of 5`. Fewer than five cases, whether the build picked fewer or the owner excluded some, is therefore a `RULING`, never a `KEEP`.

`evals/tiers/report.mjs`:

16. When `SLICES` exists, add before the `Notional spend` line: `## Slice cases`, a blank line, the header `| Case | Total | Assigned | ` followed by each `arms.slice` arm in backticks and ` |`, the separator `|---|` repeated once per column, one row per slice case not excluded (`` | `<id>` | <total> | `<assigned>` | <outcome> | … | ``), a blank line, `Slice verdict: <verdict>`, then `- excluded <id>: <why>` for each excluded slice case. The `Excluded review case` loop skips slice case ids.

`evals/tiers/arms.json` and `evals/tiers/README.md`:

17. Add `"slice": ["impl-sonnet-high", "impl-opus-medium", "impl-opus-high"]` after `review`.
18. README: add a Commands row for `node evals/tiers/build-manifest.mjs --slices` (merges two or three consecutive tasks of one plan into slice cases scored with spec 2, golden-checks them in order until five pass, writes `cases/slices.tsv` and `cases/slices-excluded.tsv`); add `slice` to `run-grid.mjs`'s stage list; state that `run-grid.mjs` also exits 2 when the slice stage has no slice manifest; add Files rows for `cases/slices.tsv` (the slice cases; its first line pins its own start commit) and `cases/slices-excluded.tsv`.

- [ ] **Step 4: Run the suites**

Run: `timeout 600 node --test evals/tiers/tests/*.test.mjs`
Expected: PASS, 79 tests.

- [ ] **Step 5: Commit**

```bash
git add evals/tiers/lib/cases.mjs evals/tiers/build-case.mjs evals/tiers/build-manifest.mjs evals/tiers/run-grid.mjs evals/tiers/lib/decide.mjs evals/tiers/report.mjs evals/tiers/arms.json evals/tiers/README.md evals/tiers/tests/fixture.mjs evals/tiers/tests/stub-claude.mjs evals/tiers/tests/cases.test.mjs evals/tiers/tests/build.test.mjs evals/tiers/tests/decide.test.mjs evals/tiers/tests/manifest.test.mjs evals/tiers/tests/grid.test.mjs
git commit -m "feat(evals): add the slice case pool and stage"
```

- [ ] **Step 6: Run the slice stage and record it**

The run calls `claude -p` 15 times (five cases on three arms) and spends Claude subscription usage. Repetition 1 has spent 63.29 of its 250 cap; each run is capped at $5 and the costliest stripped run so far cost $0.67.

Every command here is a foreground Bash call bounded by `timeout 590`; start no background task.

1. Build the cases: `timeout 590 node evals/tiers/build-manifest.mjs --slices`. Expected: `build-manifest: <n> slices, <m> exclusions, start <sha>`, normally with `n` = 5. Read `evals/tiers/cases/slices.tsv`: every row's total is 5 to 8. Exit 124 (the golden checks outran the bound): stop and report BLOCKED with that line. When `n` is 0, skip items 2 and 3: the verdict is `NOT MEASURED - no slice case`. When `n` is 1 to 4, run the stage on those cases anyway: `decideSlices` then gives a `RULING` verdict with the count (`… passed <p> of <n>; §1 needs 4 of 5`), whatever passes.
2. Run the stage in slices, repeating this call until it exits 0: `TIER_EVAL_CLAUDE=/root/.local/bin/claude timeout 590 node evals/tiers/run-grid.mjs --stage slice --minutes 1` (in Bash, `claude` is a shell function; the variable names the binary). `--minutes 1` starts cells only in the call's first minute, so every cell it starts has about nine minutes to finish before the bound; the grid then exits 3 with `stop=time`, and the next call resumes at the first unscored cell. After each call read its last line (`run-grid stage=slice … ran=<r> remaining=<k> … stop=<s>`):
   - exit 0: the stage is complete; go on to item 3;
   - exit 3 with `stop=time`: call again;
   - exit 124 (the bound killed a cell still running; it wrote no row and runs again on the next call): call again, unless the previous call also exited 124 with no new row in `results.tsv` for the same cell, in which case stop and report BLOCKED naming that cell (a slice cell that needs more than about nine minutes cannot finish in a bounded call);
   - exit 1 (cells left after harness errors): call again once; a second exit 1 in a row is BLOCKED with the NOT_RUN rows' details;
   - exit 3 with `stop=limit` or `stop=cap`, or exit 2: stop and report BLOCKED with the last line and the count of cells remaining.
3. `timeout 120 node evals/tiers/report.mjs > <scratch dir>/slice-report.md` and read its `## Slice cases` section.
4. Write `docs/dforge/notes/2026-10-26-slice-tasks.md`:

```markdown
# Slice-sized code-free tasks — 2026-10-26

**Verdict:** <the report's `Slice verdict:` text after the colon, verbatim>
**Decision rule:** four of five pass on the arm §1 assigns keeps §1; fewer stops the plan for a ruling.

Subject: <n> slice cases from `evals/tiers/cases/slices.tsv` (start `<sha7>`), each two or three consecutive tasks of one plan from this repository's history merged into one brief with the implementation code stripped, scored under docs/dforge/specs/2026-10-26-faster-plans-design.md §1, and run on `impl-sonnet-high`, `impl-opus-medium` and `impl-opus-high` through `run-grid.mjs --stage slice` (repetition 1, run on <YYYY-MM-DD>).

## Cases

| Case | Plan | Tasks | Total | Arm §1 assigns |
|---|---|---|---|---|
<one row per slices.tsv row>

## Results

<the report's Slice cases table, verbatim>

<one line per non-PASS cell on the assigned arm: case, outcome, and the results.tsv detail>

## Spend

<sum of the cost column over the slice rows, in notional dollars, and the longest run in seconds>
```

- [ ] **Step 7: Commit**

```bash
git add evals/tiers/cases/slices.tsv evals/tiers/cases/slices-excluded.tsv evals/tiers/results/results.tsv docs/dforge/notes/2026-10-26-slice-tasks.md
git commit -m "docs(notes): record the slice-task measurement"
```

Report `DONE` when the verdict starts `KEEP`. When it starts `RULING` (fewer than four passes, or fewer than five slice cases) or `NOT MEASURED`, report `DONE_WITH_CONCERNS` with the verdict, and the slice count when it is below five, as the first line of the report: the plan stops for an owner ruling on the slice size before Task 2.

### Task 2: Ladder, Rule S and the lane gate

**Files:**
- Modify: `plugins/dforge/reference/ladder.md` (the intro, §Rule S - the split gate, §Plans written before 1.27.0, the `assignment` block, §What the range actually reaches, the `gate` block and its prose, §Codex judge rung)
- Modify: `plugins/dforge/scripts/plan-lint` (the per-task loop: Rule S, the Executor gate, the lane candidates; the `lane_gates` table)
- Modify: `plugins/dforge/scripts/plan-revise` (`EXEC_TABLE`, `survey`, the unit loop's `rules` and gate)
- Modify: `plugins/dforge/reference/executor-lane.md` (§Planning's gate conditions; the registry table's `blocks.gate` row)
- Modify: `plugins/dforge/README.md` ("A four-axis rubric that gates the plan"; "The gate floors at score 2")
- Modify: `plugins/dforge/agents/impl-opus-high.md` (description)
- Modify: `plugins/dforge/tests/fixtures/stub-ladder.md`
- Test: `plugins/dforge/tests/ladder.test.sh`, `plugins/dforge/tests/lanes.test.sh`, `plugins/dforge/tests/plan-lint.test.sh`, `plugins/dforge/tests/plan-revise.test.sh`

**Interfaces:**
- Consumes: the ladder's fenced-block format, read by `ladder_block` (`scripts/lib/plan.sh`) and by `plan-revise`'s `block`.
- Produces: Contracts, Ladder (Task 2): `assignment` rows `7 impl-opus-high` and `8 impl-opus-high`; Rule S at `files + spec + coupling >= 6` or `spec = 3` on a Claude plan and `>= 4` on a `Host: codex` plan; the `gate` line `max_score 4`.

**Items:** 2

**Implementer:** dforge:impl-opus-high
**Evaluation:** files 2 - spec 2 - coupling 1 - risk 2 = 7
**Override:** owner approved the contract-and-test task shape for this plan on 2026-10-26, before plan-lint's Rule S and assignment table allow it

- [ ] **Step 1: Write the failing tests**

In `plugins/dforge/tests/fixtures/stub-ladder.md`, add `max_score 4` to the `stub-gate` block directly below `min_score 2`.

In `plugins/dforge/tests/ladder.test.sh`, change `check "assignment table has 7 rows" … "7"` to:

```bash
check "assignment table has 9 rows" "$(printf '%s\n' "$assignment" | grep -c .)" "9"
```

and replace everything from `for s in 0 1 2 3 4 5 6; do` through the `check "assignment rows are the tier-eval table" …` command (its continuation line included) with:

```bash
for s in 0 1 2 3 4 5 6 7 8; do
  case " $seen_scores " in *" $s "*) ;; *) missing="$s" ;; esac
done
check "assignment covers every score 0 through 8" "$missing" "NONE"

# Rule S caps a compliant Claude total at 8: reducible <= 5 plus risk 3. A row
# above it would mean the split gate is bypassable by scoring, which is the
# defect the gate exists to remove.
above=$(printf '%s\n' "$assignment" | awk 'NF && $1 > 8 {print $1}' | tr '\n' ' ' | sed 's/ $//')
check "assignment has no row above score 8" "${above:-NONE}" "NONE"

# Rows 0-6 are the ones the 2026-10-02 tier evaluation set, so every plan
# written before the relaxed Rule S keeps its assignments; 7 and 8 are Opus.
check "assignment rows 0-6 are the tier-eval table and 7-8 name impl-opus-high" "$(printf '%s\n' "$assignment" | tr '\n' ',')" \
  "0 impl-sonnet-low,1 impl-sonnet-low,2 impl-sonnet-low,3 impl-sonnet-medium,4 impl-sonnet-medium,5 impl-sonnet-high,6 impl-opus-high,7 impl-opus-high,8 impl-opus-high,"

# Rule S is stated by host in the prose the planner reads. Each phrase sits on
# one line of ladder.md.
prose() { grep -cF -- "$1" "$LADDER"; }
check "Rule S splits a Claude task at reducible 6" "$(prose '**If `reducible >= 6`, or if `spec = 3`, the task must be split or re-designed.')" "1"
check "a Codex plan keeps Rule S at reducible 4" "$(prose 'A `Host: codex` plan keeps `reducible >= 4`')" "1"
check "the cap is derived from reducible 5" "$(prose 'Rule S caps a compliant Claude total: `reducible <= 5` and `spec <= 2`, so')" "1"
check "the old cap derivation is gone" "$(prose 'caps a compliant total: `reducible <= 3`')" "0"
check "a total of 9 means the gate was skipped" "$(prose 'A computed total of 9 or more means the gate was skipped')" "1"
check "Opus takes totals 6 to 8" "$(prose 'Sonnet takes totals 0 to 5; Opus takes 6 to 8')" "1"
check "a relaxed-gate plan fails an older plan-lint" "$(prose 'fails `plan-lint` on a plugin older than the relaxed gate')" "1"
check "the lane envelope no longer derives from reducible 3" "$(prose 'Rule S caps `reducible` at 3, so under')" "0"
check "the lane envelope names max_score" "$(prose '`max_score 4` keeps them on the Claude ladder')" "1"
check "the light Codex judge covers totals 0 to 8" "$(prose 'for tasks totalling 0 to 8 below')" "1"
check "impl-opus-high is dispatched for scores 6 to 8" "$(grep -cF 'Dispatched by dforge for scores 6 to 8' "$AGENTS/impl-opus-high.md")" "1"
```

In `plugins/dforge/tests/lanes.test.sh`, directly below `check "gate max_risk is 1" …`, add:

```bash
check "gate max_score is 4" "$(printf '%s\n' "$gate" | awk '$1=="max_score"{print $2}')" "4"
```

replace the comment `# Rule S caps reducible at 3, so under max_risk 1 no eligible total exceeds 4.` with:

```bash
# max_score 4 bounds the eligible totals, so no row may sit outside 2..4, and
# the highest row is the gate's ceiling.
```

and directly below `check "codex-assignment has no row outside 2..4" …` add:

```bash
check "the highest codex-assignment row is the gate's max_score" \
  "$(printf '%s\n' "$assignment" | awk 'NF && $1 > m { m = $1 } END { print m }')" \
  "$(printf '%s\n' "$gate" | awk '$1=="max_score"{print $2}')"
EL="$HERE/../reference/executor-lane.md"
check "executor-lane lists the max_score condition" "$(grep -cF -- '- `total <= max_score`,' "$EL")" "1"
check "the README no longer derives the lane from reducible 3" "$(grep -cF 'Rule S caps `reducible` at 3' "$HERE/../README.md")" "0"
```

In `plugins/dforge/tests/plan-lint.test.sh`, replace the three lines from `variant t2.md 's/files 0 - spec 1 - coupling 1 - risk 2 = 4/files 2 - spec 1 - coupling 1 - risk 0 = 4/'` through `has "Rule S" …` with:

```bash
variant t2.md 's/files 0 - spec 1 - coupling 1 - risk 2 = 4/files 2 - spec 2 - coupling 2 - risk 0 = 6/; s/impl-sonnet-medium$/impl-opus-high/'
lint t2.md
has "Rule S on a Claude plan rejects reducible 6" "$out" "ERROR Task 2: Rule S: files+spec+coupling must be below 6 and spec below 3"
variant t2b.md 's/files 0 - spec 1 - coupling 1 - risk 2 = 4/files 2 - spec 2 - coupling 1 - risk 2 = 7/; s/impl-sonnet-medium$/impl-opus-high/'
lint t2b.md
lacks "Rule S on a Claude plan accepts reducible 5" "$out" "Rule S"
lacks "total 7 is assigned impl-opus-high" "$out" "ERROR Task 2"
variant t2c.md 's/files 0 - spec 1 - coupling 1 - risk 2 = 4/files 2 - spec 2 - coupling 1 - risk 3 = 8/; s/impl-sonnet-medium$/impl-opus-high/'
lint t2c.md
lacks "total 8 is assigned impl-opus-high" "$out" "ERROR Task 2"
variant t2d.md 's/files 0 - spec 1 - coupling 1 - risk 2 = 4/files 2 - spec 2 - coupling 1 - risk 2 = 7/'
lint t2d.md
has "total 7 names impl-opus-high" "$out" "ERROR Task 2: Implementer impl-sonnet-medium does not match the assignment table's impl-opus-high for total 7"
variant t2e.md 's/files 0 - spec 1 - coupling 1 - risk 2 = 4/files 0 - spec 3 - coupling 0 - risk 0 = 3/'
lint t2e.md
has "spec 3 fails Rule S without an override" "$out" "ERROR Task 2: Rule S: files+spec+coupling must be below 6 and spec below 3"
variant t2f.md 's/files 0 - spec 1 - coupling 1 - risk 2 = 4/files 0 - spec 3 - coupling 0 - risk 0 = 3/; s/^(\*\*Approach:\*\* .*)$/\1\n**Override:** the owner keeps the approach open/'
lint t2f.md
has "an Override keeps a spec-3 task as a warning" "$out" "WARN Task 2: Rule S: files+spec+coupling must be below 6 and spec below 3"
```

change the `has "Executor below the gate" …` line to:

```bash
has "Executor below the gate" "$out" "ERROR Task 1: total 1 / risk 0 fails the lane gate (min_score 2, max_score 4, max_risk 1)"
```

directly above the line `variant t11.md 's/^(\*\*Approach:\*\* .*)$/\1\n**Override:** kept\n**Executor:** codex gpt-6.1-sol \/ high/'` add:

```bash
variant t10b.md 's/files 0 - spec 0 - coupling 1 - risk 0 = 1/files 1 - spec 2 - coupling 2 - risk 0 = 5/; s/impl-sonnet-low$/impl-sonnet-high/; s/^(\*\*Evaluation:\*\* files 1 - spec 2 - coupling 2 - risk 0 = 5)$/\1\n**Executor:** codex gpt-6.1-sol \/ high/; s/^(\*\*Program:\*\* .*)$/\1\n\n> **External executors:** codex/'
lint t10b.md
has "Executor above max_score fails the gate" "$out" "ERROR Task 1: total 5 / risk 0 fails the lane gate (min_score 2, max_score 4, max_risk 1)"
```

directly below the line `# --- per task, Codex ---` add:

```bash
codex_plan | sed 's/files=1, spec=1, coupling=1, risk=0; weighted routing score=3/files=2, spec=1, coupling=1, risk=0; weighted routing score=4/; s#gpt-6.1-sol / low#gpt-6.1-sol / medium#' > c0.md
lint c0.md
has "Rule S on a Codex plan still rejects reducible 4" "$out" "ERROR Task 1: Rule S: files+spec+coupling must be below 4 and spec below 3"
```

and directly below the `has "a missing gate block is an error, not an open gate" …` command (two lines), before `DR_LADDER="$TMP/stub-ladder.md"`, add:

```bash
DR_LADDER="$TMP/stub-ladder-noscore.md"
cat "$HERE/../reference/ladder.md" > "$DR_LADDER"
sed '/^max_score /d' "$HERE/fixtures/stub-ladder.md" >> "$DR_LADDER"
lint s1.md
has "a gate block without max_score cannot certify a task" "$out" \
  "ERROR Task 1: stub's gate block 'stub-gate' is missing from the ladder"
```

In `plugins/dforge/tests/plan-revise.test.sh`, change `mktask`'s `case` line to:

```bash
  case $5 in 3|4) agent=impl-sonnet-medium ;; 5) agent=impl-sonnet-high ;; 6|7|8) agent=impl-opus-high ;; esac
```

replace the line `check "reducible 4 fails Rule S below total 5" "$(field gate "$(unit1)")" "fail:rule_s"` with:

```bash
out=$(unit1)
check "reducible 4 passes Rule S on a Claude plan" "$(field rule_s "$out")" "ok"
check "reducible 4 at total 4 takes the high rung" "$(field rungs "$out")" "codex:gpt-6.1-sol/high"
plan "$(mktask 2 2 1 0 5)"
out=$(unit1)
check "reducible 5 passes Rule S" "$(field rule_s "$out")" "ok"
check "total 5 fails the max_score ceiling" "$(field gate "$out")" "fail:total"
check "a unit above max_score lists no rung" "$(field rungs "$out")" ""
plan "$(mktask 2 2 2 0 6)"
check "reducible 6 fails Rule S" "$(field gate "$(unit1)")" "fail:rule_s"
```

and directly below `rm -f "$SUR/docs/lettered.md"` add:

```bash
splan relaxed '**Evaluation:** files 1 - spec 1 - coupling 2 - risk 0 = 4'
splan wide '**Evaluation:** files 2 - spec 2 - coupling 1 - risk 0 = 5'
check "the survey counts a reducible-4 unit as eligible" "$(field eligible "$(row relaxed)")" "1"
check "the survey does not count a unit above max_score" "$(field eligible "$(row wide)")" "0"
rm -f "$SUR/docs/relaxed.md" "$SUR/docs/wide.md"
```

- [ ] **Step 2: Run them to verify they fail**

Run: `for t in ladder lanes plan-lint plan-revise; do timeout 300 bash plugins/dforge/tests/$t.test.sh | tail -1; done`
Expected: FAIL — `ladder`: 14 failed (7 rows, no rows 7-8, the old prose, the agent description); `lanes`: 4 failed (no `max_score`, executor-lane and README unchanged); `plan-lint`: 10 failed (Rule S at 4, no row 7 or 8, the gate ignores and does not print `max_score`); `plan-revise`: 5 failed (Rule S at 4, no ceiling). The Codex Rule S pin, `reducible 6 fails Rule S`, `a unit above max_score lists no rung` and the `wide` survey check already pass: they pin behaviour that must not change.

Before changing any script, record how the current plan-lint judges every plan in the repository (`plugins/dforge/tests/fixtures/` holds no plan file; the suites' fixture plans are embedded in them and are covered by Step 4's suites):

Run: `for f in docs/dforge/plans/*.md docs/superpowers/plans/*.md; do printf '%s %s\n' "$f" "$(timeout 60 bash plugins/dforge/scripts/plan-lint "$f" --no-probe 2>&1 | grep -c '^ERROR')"; done > <scratch dir>/lint-before.txt`
Expected: one `<path> <ERROR count>` line per plan; on 2026-10-26 the three dated plans in `docs/dforge/plans` had 0.

- [ ] **Step 3: Implement**

`plugins/dforge/reference/ladder.md` — each phrase the suite pins sits on one line, as wrapped below:

1. Intro: the first sentence becomes `The raw axis definitions are shared across hosts; Rule S's threshold is set by host below.`
2. §Rule S - the split gate: replace the bold paragraph `**If `reducible >= 4`, … Do not assign a larger model.**` with:

```markdown
**If `reducible >= 6`, or if `spec = 3`, the task must be split or re-designed.
Do not assign a larger model.** That is the gate on a Claude plan, whose code
tasks carry their tests and interfaces but not their implementation and so
score 2 on spec completeness.

A `Host: codex` plan keeps `reducible >= 4` as its gate:
[native-codex.md](native-codex.md) derives its weighted 0-9 score from
`reducible <= 3`, and `codex-routing.json` ranks stop at 9. `scripts/plan-lint`
applies the gate by host.
```

   and replace the paragraph starting `Rule S caps a compliant total:` with:

```markdown
Rule S caps a compliant Claude total: `reducible <= 5` and `spec <= 2`, so
`total <= 5 + risk(3) = 8`. **The assignment table's ceiling is a consequence
of Rule S, not a separate choice.**
A computed total of 9 or more means the gate was skipped, not that a higher
tier is needed.
```

3. §Plans written before 1.27.0: append this paragraph at the end of the section:

```markdown
The relaxed gate is one-way. A Claude plan with a task at `reducible` 4 or 5,
or a total of 7 or 8, fails `plan-lint` on a plugin older than the relaxed gate:
that checker splits at `reducible >= 4` and has no row above 6. A plan written
before the relaxed gate lints unchanged on this one, since rows 0-6 did not move.
```

4. The `assignment` block gains `7 impl-opus-high` and `8 impl-opus-high` after row 6; rows 0-6 do not change.
5. §What the range actually reaches: replace its first four sentences (`A plan written to dforge:writing-plans bans placeholders …` through `… and otherwise reached by escalation.`) with:

```markdown
A Claude plan written to dforge:writing-plans gives each code task its tests
and interfaces but not its implementation, so a code task scores 2 on spec
completeness and is drawn as a feature slice up to `reducible <= 5`.
Sonnet takes totals 0 to 5; Opus takes 6 to 8, and is otherwise reached by escalation.
A Codex plan still carries the code, so its tasks score 0 or 1 there.
```

   The rest of that paragraph (from `Total 0 moved from` on) and the next one stay.
6. §The lane gate: the `gate` block gains `max_score 4` directly below `min_score 2`. `All four conditions must hold.` becomes `All five conditions must hold.` Replace the paragraph starting `` `min_score 2` is not arbitrary. `` with:

```markdown
`min_score 2` and `max_score 4` bound the eligible totals to 2, 3 and 4, the
rows `codex-assignment` has. On a Claude plan Rule S admits `reducible` up to
5, so `max_risk 1` alone would admit a total of 5 or 6 at risk 0 or 1;
`max_score 4` keeps them on the Claude ladder. Without the floor the gate
would reduce to a risk test and capture nearly every task by count. It would
also offload where offload is worthless: a score-0 task displaces
`impl-sonnet-low`, which costs less to run than the wrapper costs to
orchestrate.
```

7. §Codex judge rung: `for tasks totalling 0 to 6 below` becomes `for tasks totalling 0 to 8 below` (review-route already gives every total below risk 3 the light row).

`plugins/dforge/scripts/plan-lint`:

8. Set the Rule S limit once, after the `codex` flag is known: 6 on a Claude plan, 4 when `codex=1`. The Rule S check at the end of the per-task loop uses it in its condition and prints `Rule S: files+spec+coupling must be below <limit> and spec below 3`, at `$sev` as today (WARN under an Override). The lane-candidate branch (`elif [ "$sev" = ERROR ] && …`) uses the same limit.
9. The `lane_gates` table carries `<id>\t<min_score>\t<max_risk>\t<max_score>`; an executor whose gate block lacks any of the three is skipped with the existing `gate block … is missing from the ladder` diagnostic. A lane candidate needs `t >= min_score`, `t <= max_score` and `d <= max_risk`.
10. An `**Executor:**` line reads `max_score` beside `min_score` and `max_risk`; when any is missing it reports the existing `<id>'s gate block '<block>' is missing from the ladder` error. The gate fails unless `t >= min_score`, `t <= max_score` and `d <= max_risk`, and then prints `total <t> / risk <d> fails the lane gate (min_score <a>, max_score <b>, max_risk <c>)`. Nothing else in plan-lint changes: the table lookup already indexes totals 7 and 8 once the rows exist.

`plugins/dforge/scripts/plan-revise` (it refuses a Codex-host plan, so its Rule S is the Claude one):

11. `rules=violated` when `f + s + c >= 6` or `s = 3`; `survey` skips a unit at `fl + sp + cp >= 6` or `sp = 3`.
12. `EXEC_TABLE` rows become `<id> <min_score> <max_risk> <max_score>`; an executor lacking any of them is left out, as today. The survey counts a unit eligible when some row has `min_score <= score <= max_score` and `risk <= max_risk`.
13. The unit loop reads `max_score` for each ticked executor beside `min_score` and `max_risk`; any missing gives the existing `no gate thresholds for ticked executor` diagnostic. After the `score < min_score` check, a score above `max_score` sets `asked=1` and `gate=${gate:-fail:total}` and moves to the next executor.

Text that restates the gate:

14. `plugins/dforge/reference/executor-lane.md` §Planning: `All four conditions must hold:` becomes `All five conditions must hold:`, and the list gains the line `` - `total <= max_score`, `` directly below `` - `total >= min_score`, ``. The registry table's `blocks.gate` row reads `The [ladder.md](ladder.md) block holding `min_score`, `max_score` and `max_risk``.
15. `plugins/dforge/README.md`: in "A four-axis rubric that gates the plan", `so Rule S sends a task scoring 4 or more across them back to be split rather than to a larger model. That cap is what makes the assignment table stop at 6.` becomes `so Rule S sends a task scoring 6 or more across them on a Claude plan, or 4 or more on a Codex plan, back to be split rather than to a larger model. That cap is what makes the assignment table stop at 8.` The paragraph starting `The gate floors at score 2 on purpose.` starts instead: `The gate floors at score 2 and stops at 4 on purpose: `codex-assignment` has rows for totals 2 to 4 only, and Rule S admits a Claude task up to `reducible` 5, so `max_score 4` keeps a total-5 or total-6 task at risk 1 or below on the Claude ladder. Without the floor the gate would reduce to `risk <= 1`` and keeps the rest of the paragraph from `and capture nearly every task by count`.
16. `plugins/dforge/agents/impl-opus-high.md`: the description reads `Task implementer running Opus 5.5 at high effort. Dispatched by dforge for scores 6 to 8: the top execution rung, above which a task is split rather than escalated.`

- [ ] **Step 4: Run the suites**

Run: `for t in ladder lanes plan-lint plan-revise fleet executors; do timeout 300 bash plugins/dforge/tests/$t.test.sh | tail -1; done`
Expected: PASS, `0 failed` on each.

Run: `for f in docs/dforge/plans/*.md docs/superpowers/plans/*.md; do printf '%s %s\n' "$f" "$(timeout 60 bash plugins/dforge/scripts/plan-lint "$f" --no-probe 2>&1 | grep -c '^ERROR')"; done > <scratch dir>/lint-after.txt && diff <scratch dir>/lint-before.txt <scratch dir>/lint-after.txt`
Expected: no output and exit 0: every plan has the same ERROR count as under the old plan-lint. A difference is a regression to fix in this task, not a plan to edit.

Run: `timeout 120 node scripts/validate-repository.mjs` and `timeout 120 /root/.local/bin/claude plugin validate plugins/dforge`
Expected: both pass.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/reference/ladder.md plugins/dforge/scripts/plan-lint plugins/dforge/scripts/plan-revise plugins/dforge/reference/executor-lane.md plugins/dforge/README.md plugins/dforge/agents/impl-opus-high.md plugins/dforge/tests/fixtures/stub-ladder.md plugins/dforge/tests/ladder.test.sh plugins/dforge/tests/lanes.test.sh plugins/dforge/tests/plan-lint.test.sh plugins/dforge/tests/plan-revise.test.sh
git commit -m "feat(dforge): relax Rule S for Claude plans"
```

### Task 3: Plan shape text and review rounds

**Files:**
- Modify: `plugins/dforge/skills/writing-plans/SKILL.md` (Overview, Task Right-Sizing, Bite-Sized Task Granularity removed, Task Structure's Step 3, Assign steps 1-2, No Placeholders, Lint and Review step 3)
- Modify: `plugins/dforge/skills/writing-plans/references/drafter-prompt.md`
- Modify: `plugins/dforge/skills/writing-plans/references/plan-reviewer-prompt.md` (both templates)
- Modify: `plugins/dforge/skills/writing-plans/references/assigning-implementers.md` (§Score the plan, not the imagined task; §Resist a bigger model)
- Modify: `plugins/dforge/criteria/plan-review.md` (Ground Truth Note, Executability)
- Modify: `plugins/dforge/scripts/review-route` (`--plan-round`, `plan_shape`)
- Modify: `plugins/dforge/skills/brainstorming/SKILL.md` (Auto by default step 4; Folded into Fable)
- Modify: `plugins/dforge/reference/auto-run.md` (§The spec)
- Modify: `plugins/dforge/README.md` (the plan-review sentence)
- Test: `plugins/dforge/tests/review-route.test.sh`, `plugins/dforge/tests/process-roles.test.sh`

**Interfaces:**
- Consumes: Contracts, Ladder (Task 2): Rule S at `>= 6` on a Claude plan and `>= 4` on a `Host: codex` plan.
- Produces: `review-route PLAN_FILE --plan-round R` on a Claude plan prints `cap=2` whatever the task totals, never `reason=cap-critical`, and exits 2 for R of 3 or more; a `Host: codex` plan's output is unchanged.

**Items:** 1, 2

**Implementer:** dforge:impl-opus-high
**Evaluation:** files 3 - spec 1 - coupling 1 - risk 1 = 6
**Override:** owner approved the contract-and-test task shape for this plan on 2026-10-26, before plan-lint's Rule S and assignment table allow it

- [ ] **Step 1: Write the failing tests**

In `plugins/dforge/tests/review-route.test.sh`, replace everything from the line `rround "$TMP/round.md" 1` that follows the batch checks through the line before `# --- the ruling seat` with:

```bash
rround "$TMP/round.md" 1
check "a Claude plan's round 1 is Codex with an Opus fallback, cap 2 whatever its totals" "$out" "review-seat plan-round=1 primary=codex:plan fallback=dforge:judge-opus reason=round cap=2"
rround "$TMP/light.md" 1
check "a light plan's round 1 is cap 2 too" "$out" "review-seat plan-round=1 primary=codex:plan fallback=dforge:judge-opus reason=round cap=2"
rround "$TMP/light.md" 2
check "a light plan's round 2 is a round within cap 2" "$out" "review-seat plan-round=2 primary=dforge:judge-opus fallback=- reason=round cap=2"
rround "$TMP/light.md" 3
check "a Claude plan has no round 3" "$rc" "2"
rround "$TMP/mid.md" 2
check "highest total 5: round 2 is within cap 2" "$out" "review-seat plan-round=2 primary=dforge:judge-opus fallback=- reason=round cap=2"
rround "$TMP/round.md" 3
check "an intricate Claude plan has no cap-critical round 3" "$rc" "2"
shape_plan "$TMP/slice.md" '**Evaluation:** files 2 - spec 2 - coupling 1 - risk 3 = 8'
rround "$TMP/slice.md" 2
check "a total-8 plan's round 2 is a round within cap 2" "$out" "review-seat plan-round=2 primary=dforge:judge-opus fallback=- reason=round cap=2"
rround "$TMP/slice.md" 3
check "a total-8 plan has no round 3" "$rc" "2"
rround "$TMP/plan.md" 1
check "a Claude plan round reads no Evaluation line" "$rc:$out" "0:review-seat plan-round=1 primary=codex:plan fallback=dforge:judge-opus reason=round cap=2"

```

In the codex-off section, change the expected `cap=` of these four checks to `cap=2`, leaving the rest of each line as it is: `codex off: an intricate plan's round 1 goes to Opus alone` (was `cap=3`), `codex off: a plain plan's round 1 goes to Opus alone` (was `cap=1`), `codex off: plan round 2 is unchanged` (was `cap=3`), `no session file keeps plan round 1 off Codex` (was `cap=3`). The native plan-round checks (`native --plan-round …`) do not change.

In the plan review prose section, replace the line `present "writing-plans gives a Critical at the cap one more round" "$WP" 'earns exactly one more'` with:

```bash
present "writing-plans gives a Codex plan's Critical at the cap one more round" "$WP" 'earns exactly one more'
present "writing-plans caps a Claude plan at two rounds" "$WP" 'On a Claude plan the cap is 2 whatever the task totals'
absent "writing-plans no longer derives a Claude cap from the totals" "$WP" 'printed: 1 when the plan'"'"'s highest'
```

and replace the line `present "README caps plan review" "$P/README.md" 'capped by the plan'"'"'s highest task total'` with:

```bash
present "README caps plan review at two rounds" "$P/README.md" 'at most two rounds on a Claude plan'
absent "README no longer caps plan review by task total" "$P/README.md" 'capped by the plan'"'"'s highest task total'
```

In `plugins/dforge/tests/process-roles.test.sh`, directly below `names "drafter prompt: the scratch worktree" …`, add:

```bash

# The contract-and-test plan shape (docs/dforge/specs/2026-10-26-faster-plans-design.md §1, §5).
# Matched with line breaks and runs of spaces folded, so a phrase may wrap.
flat() { tr '\n' ' ' < "$1" | tr -s ' '; }
says() { # says <label> <file> <text>
  check "$1" "$(flat "$2" | grep -qF -- "$3" && echo yes || echo no)" "yes"
}
lacks() { # lacks <label> <file> <text>
  check "$1" "$(flat "$2" | grep -qF -- "$3" && echo yes || echo no)" "no"
}
PRP="$P/skills/writing-plans/references/plan-reviewer-prompt.md"
AI="$P/skills/writing-plans/references/assigning-implementers.md"
PR="$P/criteria/plan-review.md"
ALLOWED='a configuration value, a generated-file or migration command, or a fixed constant the spec names'
says "shape: a task is a feature slice" "$WP" 'A task is a feature slice'
lacks "shape: bite-sized granularity is gone" "$WP" '## Bite-Sized Task Granularity'
lacks "shape: no bite-sized wording" "$WP" 'bite-sized'
says "shape: the task carries its interfaces, tests and verify commands" "$WP" 'its interfaces, the complete code of its tests, the decisions it embodies'
says "shape: implementation code only where no test pins it" "$WP" "$ALLOWED"
says "shape: Step 3 describes the implementation" "$WP" 'Step 3 describes the implementation; it carries no implementation code'
lacks "shape: Step 3 no longer carries the implementation" "$WP" 'Step 3 carries the whole implementation.'
says "shape: a Codex host keeps code-given tasks" "$WP" 'On a Codex host, tasks keep the code-given shape'
says "shape: tests that assert nothing are placeholders" "$WP" 'Tests that describe behaviour without asserting it'
lacks "shape: the old how-not-shown ban is reworded" "$WP" 'Steps that describe what to do without showing how'
says "shape: a Claude code task scores spec 2" "$WP" 'so it scores spec 2'
says "shape: Rule S at 6 on a Claude plan" "$WP" 'On a Claude plan, if `files + spec + coupling >= 6`'
says "shape: Rule S at 4 on a Codex plan" "$WP" 'on a `Host: codex` plan, if it is `>= 4`'
lacks "shape: no host-blind Rule S at 4" "$WP" 'If `files + spec + coupling >= 4`, split'
says "drafter prompt: tests and interfaces, not code" "$DPR" 'gives the complete code of its tests'
says "drafter prompt: implementation code only where no test pins it" "$DPR" "$ALLOWED"
says "drafter prompt: tests fail on the current tree" "$DPR" 'confirm each fails for the reason the task fixes'
lacks "drafter prompt: no complete code of every step" "$DPR" 'gives the complete code of every step'
lacks "drafter prompt: no prototyping" "$DPR" 'You may prototype'
says "plan reviewer: a missing implementation body is not a finding" "$PRP" 'a missing implementation body is not a finding'
says "plan reviewer: a stub or missing test is" "$PRP" 'a missing or stub test is'
says "plan review criteria: a precise description is not a gap" "$PR" 'a task that describes its implementation precisely without its code is not a gap'
says "plan review criteria: implementation code only where no test pins it" "$PR" "$ALLOWED"
lacks "plan review criteria: no host-blind complete-code rule" "$PR" 'exact file paths, every code step carries the complete code'
says "assigning: a Claude code task scores spec 2" "$AI" 'gives its tests and interfaces but not its implementation, so it scores 2'
says "assigning: the Claude cap is 8" "$AI" 'Rule S caps a compliant Claude total at 8'
lacks "assigning: no cap at 6" "$AI" 'Rule S also caps a compliant total at 6'
says "spec review: Fable's second round needs an open Blocker or High" "$BS" 'a second only when round 1 leaves a Blocker or High finding open'
says "spec review: the folded second round needs an open finding" "$BS" 'which runs only when a Blocker or High finding is still open'
lacks "spec review: no unconditional answer check" "$BS" 'which checks each Blocker and High answer'
says "auto-run.md: Fable's second round needs an open Blocker or High" "$P/reference/auto-run.md" 'A second runs only when round 1 leaves a Blocker or High finding open'
lacks "auto-run.md: no unconditional second round" "$P/reference/auto-run.md" 'At most two Fable rounds run (review, revise, re-review)'
```

- [ ] **Step 2: Run them to verify they fail**

Run: `for t in review-route process-roles; do timeout 300 bash plugins/dforge/tests/$t.test.sh | tail -1; done`
Expected: FAIL — `review-route`: 15 failed (the cap is still derived from the totals, round 3 is a cap-critical round, a plan round dies on Task 9's broken Evaluation line, and the writing-plans and README prose is unchanged); `process-roles`: 32 failed (none of the new text exists, every old phrase is still there). `a Claude plan has no round 3` and `highest total 5: round 2 is within cap 2` already pass.

- [ ] **Step 3: Implement**

Each quoted replacement is the exact text. The `process-roles` checks fold line breaks, so wrap as the file's neighbours do; the `review-route` prose checks match one line, so keep `earns exactly one more`, `On a Claude plan the cap is 2 whatever the task totals`, `below the `cap=` that `review-route` printed`, `Run the next round only when a round returned` and `at most two rounds on a Claude plan` each on one line.

`plugins/dforge/skills/writing-plans/SKILL.md`:

1. Overview, first paragraph: `which files to touch for each task, code, testing, docs they might need to check, how to test it. Give them the whole plan as bite-sized tasks.` becomes `which files to touch for each task, the interfaces it produces and consumes, the tests that pin it, docs they might need to check, how to verify it. Give them the whole plan as feature-slice tasks.`
2. Task Right-Sizing: keep its paragraph and append `A task is a feature slice: on a Claude plan its code task carries no implementation code and is scored with spec 2 (Assign an implementer, step 1).`
3. Delete the `## Bite-Sized Task Granularity` section, heading and bullets.
4. Task Structure template: replace everything from `- [ ] **Step 3: Write the implementation**` through `implementer will transcribe it literally.` with:

```markdown
- [ ] **Step 3: Implement**

1. [The function or section to change, named by its signature, a heading or
   a quoted anchor line, never by a line number alone.]
2. [Its inputs and outputs, the exact strings and exit codes Contracts names,
   the edge cases, and what must not change.]

A task carries its files, its interfaces, the complete code of its tests, the
decisions it embodies, and the commands that verify it. Step 3 describes the
implementation; it carries no implementation code. Implementation code
appears only where no test can pin the behaviour: a configuration value, a
generated-file or migration command, or a fixed constant the spec names. A
test that still passes with `return <constant>` or with the implementation
deleted is a plan failure: `plan-review.md` scores it LOW.

On a Codex host, tasks keep the code-given shape: Step 3 is **Write the
implementation** and carries every line of it, because
[native-codex.md](../../reference/native-codex.md) keeps Rule S at
`reducible >= 4`.
```

   Steps 1, 2, 4 and 5 of the template and the `Step 1's test sits at the lowest layer` paragraph stay as they are.
5. Assign an implementer, step 1: append `A Claude plan's code task carries its tests and interfaces but no implementation, so it scores spec 2.`
6. Step 2: `If `files + spec + coupling >= 4`, split the task where a reviewer could reject one half while approving the other, and re-score both halves.` becomes `On a Claude plan, if `files + spec + coupling >= 6`, split the task where a reviewer could reject one half while approving the other, and re-score both halves; on a `Host: codex` plan, if it is `>= 4`, do the same.` The rest of the step stays.
7. No Placeholders: the bullet `"Similar to Task N" (repeat the code — the engineer may be reading tasks out of order)` becomes `"Similar to Task N" (repeat the test code or the description — the engineer may be reading tasks out of order)`, and `Steps that describe what to do without showing how (code blocks required for code steps)` becomes `Tests that describe behaviour without asserting it (every test step carries its complete test code)`.
8. Lint and Review, step 3: replace the whole step with:

```markdown
3. **Fix and repeat.** Fix every Critical and Important finding and re-lint;
   Minor findings are advisory. Run the next round only when a round returned
   a Critical finding or any score of 8 or below, and only while the round is
   below the `cap=` that `review-route` printed.
   On a Claude plan the cap is 2 whatever the task totals: round 2 is the
   delta round, and there is no third. On a Codex-host plan the cap follows the
   highest raw task total, not the weighted routing score: 1 when it is 3 or
   less, 2 for 4 or 5, 3 for 6. At the cap a Critical finding
   earns exactly one more delta round (`reason=cap-critical`), scoped to its
   fix, which earns no other. A delta round replaces a fresh full review. Any
   Critical finding still open after the last round, and any score of 8 or
   below at the cap, go to your human partner. A borderline score (9-13) gets
   a one-line decision in the plan's Assumptions.
```

`plugins/dforge/skills/writing-plans/references/drafter-prompt.md` (inside the prompt body; keep its four-space indent):

9. `Each task names its exact files, gives the complete code of every step, and ends with a check that proves it.` becomes `Each task names its exact files and its interfaces, gives the complete code of its tests, and describes the implementation precisely without its code: implementation code appears only for a configuration value, a generated-file or migration command, or a fixed constant the spec names. Each task ends with the commands that verify it.`
10. The paragraph starting `Read the code your tasks change. You may prototype` becomes `Read the code your tasks change and the suite each task's tests join. Run your tests against the current tree in a scratch worktree of your own (`git worktree add --detach <scratch dir> HEAD`, removed before you finish), and confirm each fails for the reason the task fixes.` followed by its unchanged last sentence, `Write nothing in this checkout except [SLICE_PATH].`, kept on one line.

`plugins/dforge/skills/writing-plans/references/plan-reviewer-prompt.md`:

11. In the first template, directly after the paragraph ending `the task text plus the header's Global Constraints and Contracts, nothing else.`, and in the Later rounds template, directly after the paragraph ending `read the tasks that produce and consume it.`, add (four-space indent): `On a Claude plan a code task gives its interfaces, the complete code of its tests and its verify commands, not its implementation: a missing implementation body is not a finding, while a missing or stub test is. On a `Host: codex` plan every code step carries its complete code.`

`plugins/dforge/skills/writing-plans/references/assigning-implementers.md`:

12. §Score the plan, not the imagined task: after `that axis is 0 no matter how clever the code is.` add `A Claude plan's code task gives its tests and interfaces but not its implementation, so it scores 2.`
13. §Resist a bigger model: `Rule S also caps a compliant total at 6, which is why the assignment table stops there; see [ladder.md](../../../reference/ladder.md).` becomes `Rule S caps a compliant Claude total at 8 (`reducible <= 5` plus risk 3), which is why the assignment table stops there; a `Host: codex` plan keeps `reducible <= 3`. See [ladder.md](../../../reference/ladder.md).`

`plugins/dforge/criteria/plan-review.md`:

14. Ground Truth Note: `the exact paths, code, and commands in each task are.` becomes `the exact paths, interfaces, tests and commands in each task are.`
15. Executability: replace `Score HIGH when every step names exact file paths, every code step carries the complete code, every command is exact and states its expected output, and every test would fail against a stub: a test that still passes with `return <constant>` or with the implementation deleted is invalid. Score LOW when a step leaves a decision to the implementer, refers to` with `Score HIGH when every step names exact file paths, every task gives its interfaces and the complete code of its tests, every command is exact and states its expected output, and every test would fail against a stub: a test that still passes with `return <constant>` or with the implementation deleted is invalid. On a Claude plan implementation code appears only for a configuration value, a generated-file or migration command, or a fixed constant the spec names, and a task that describes its implementation precisely without its code is not a gap. On a `Host: codex` plan every code step carries the complete code. Score LOW when a step leaves a decision to the implementer, a test step lacks its complete test code, a step refers to`. The rest of the criterion stays. The criterion ids do not change (`tests/criteria.test.sh` pins them).

`plugins/dforge/scripts/review-route`:

16. `--plan-round R` on a Claude plan no longer calls `plan_shape` and reads no Evaluation line: `cap` is 2. R of 3 or more exits 2 with `review-route: plan round <R> is past the cap (2)`. Round 1 prints the same `codex:plan` or `codex-off` lines as today with `cap=2`; round 2 prints `review-seat plan-round=2 primary=dforge:judge-opus fallback=- reason=round cap=2`. No Claude round prints `reason=cap-critical`. The native branch (`native_shape`, its cap from raw totals, its one `cap-critical` round and its error message) is unchanged.
17. `plan_shape` keeps setting `intricate` for `--ruling` and no longer sets `cap`; its comment says so. `cap_for`'s comment says it serves the Codex-host cap only.

`plugins/dforge/skills/brainstorming/SKILL.md`:

18. Auto by default, step 4: `then `dforge:judge-fable` on the spec against its `## Decisions`, at most two rounds (review, revise, re-review); without a` becomes `then `dforge:judge-fable` on the spec against its `## Decisions`: one round, and a second only when round 1 leaves a Blocker or High finding open, its own or a folded critic's, checking only those answers; without a`, the rest of the step unchanged.
19. Architecture critic, Folded into Fable: `before Fable's second round, which checks each Blocker and High answer.` becomes `before Fable's second round, which runs only when a Blocker or High finding is still open and checks only those answers.` The process graph's `(at most two rounds)` labels stay: two is still the most.

`plugins/dforge/reference/auto-run.md`:

20. §The spec: `At most two Fable rounds run (review, revise, re-review); anything still open after the second is deferred the same way.` becomes `Fable runs one round. A second runs only when round 1 leaves a Blocker or High finding open, its own or a folded critic's, and checks only those answers; anything still open after the last round is deferred the same way.`

`plugins/dforge/README.md`:

21. The two lines `(`judge-opus` when Codex is off) and `judge-opus` for delta rounds,` and `capped by the plan's highest task total.` become `(`judge-opus` when Codex is off) and `judge-opus` for the delta round:` and `at most two rounds on a Claude plan.`

- [ ] **Step 4: Run the suites**

Run: `for t in review-route process-roles criteria auto-run-skills inline-mode settings-skills auto-default parallel-grouping; do timeout 300 bash plugins/dforge/tests/$t.test.sh | tail -1; done`
Expected: PASS, `0 failed` on each.

Run: `timeout 120 bash plugins/dforge/tests/typed-seats-and-drafting.acceptance.sh A7 | tail -1`
Expected: `7 passed, 0 failed` (A7 reads the drafter prompt's `one dispatch per slice of 2-3 consecutive tasks, every slice in one message`, which this task does not touch; the suite's A13 reads the host's worktrees and drafts directory, so it is not run here).

Run: `timeout 120 node scripts/validate-repository.mjs` and `timeout 120 /root/.local/bin/claude plugin validate plugins/dforge`
Expected: both pass.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/skills/writing-plans/SKILL.md plugins/dforge/skills/writing-plans/references/drafter-prompt.md plugins/dforge/skills/writing-plans/references/plan-reviewer-prompt.md plugins/dforge/skills/writing-plans/references/assigning-implementers.md plugins/dforge/criteria/plan-review.md plugins/dforge/scripts/review-route plugins/dforge/skills/brainstorming/SKILL.md plugins/dforge/reference/auto-run.md plugins/dforge/README.md plugins/dforge/tests/review-route.test.sh plugins/dforge/tests/process-roles.test.sh
git commit -m "feat(dforge): contract plans and two review rounds"
```

### Task 4: Review tier in review-route

**Files:**
- Modify: `plugins/dforge/scripts/review-route` (the `--task` branch: the Evaluation loop after `--task) shift`, and the closing `printf 'review-seat task=…'`; the header comment's Usage, Output and Exit lines)
- Test: `plugins/dforge/tests/review-route.test.sh`

**Interfaces:**
- Consumes: the existing `review-seat task=<ids> primary=<seat> fallback=<seat|-> reason=<why>` line, which `scripts/task-step`'s `route_field` reads key by key (`sed -n "s/.* $1=\([^ ]*\).*/\1/p"`), so a new field in the middle breaks no reader; `tests/working-directory.test.sh` greps the prefix `review-seat task=1 primary=`, so the new field never goes before `primary=`.
- Produces: Review tier (Task 4) — `review=task` or `review=group` on the single-task `review-seat` line, placed between `fallback=…` and `reason=…`; `review=task reason=unscored`, exit 0, for a task with no Evaluation line; no `review=` field on a several-task line.

**Items:** 1 review rounds, 2 execution time

**Implementer:** dforge:impl-opus-high
**Evaluation:** files 1 - spec 2 - coupling 2 - risk 1 = 6
**Override:** owner approved the contract-and-test task shape for this plan on 2026-10-26, before plan-lint's Rule S and assignment table allow it

- [ ] **Step 1: Write the failing tests**

Two edits to `plugins/dforge/tests/review-route.test.sh`.

(a) Every existing single-task expectation gains its tier. Replace each `check` line below with the line of the same check name (the last one is the second line of the two-line check "a real Executor line still routes to a Claude judge"; the `LIGHT=` line is the variable the Evaluation-reader section defines). Batch expectations (`task=1,2`, `task=1,3`, `task=1,5`) and every `--plan-round`, `--ruling`, `--final` and `--final-fix` expectation stay as they are.

```bash
check "total 1: light Codex, Sonnet fallback" "$out" "review-seat task=1 primary=codex:light fallback=dforge:judge-sonnet-high review=group reason=band"
check "total 3 with em dashes: light Codex, Sonnet fallback" "$out" "review-seat task=2 primary=codex:light fallback=dforge:judge-sonnet-high review=group reason=band"
check "total 4 at risk 1: light Codex, Opus fallback" "$out" "review-seat task=3 primary=codex:light fallback=dforge:judge-opus review=group reason=band"
check "risk 2 takes its band: light Codex, Opus fallback" "$out" "review-seat task=4 primary=codex:light fallback=dforge:judge-opus review=task reason=band"
check "an Executor task is reviewed by its band judge, never Codex" "$out" "review-seat task=5 primary=dforge:judge-sonnet-high fallback=- review=group reason=executor"
check "an Executor task at risk 2 takes its band" "$out" "review-seat task=6 primary=dforge:judge-sonnet-high fallback=- review=task reason=executor"
check "an Executor task at risk 3 goes to Opus alone" "$out" "review-seat task=11 primary=dforge:judge-opus fallback=- review=task reason=executor"
check "a part routes on its own Evaluation" "$out" "review-seat task=7A primary=codex:light fallback=dforge:judge-sonnet-high review=group reason=band"
check "the risk-2 part takes light Codex, Opus fallback" "$out" "review-seat task=7B primary=codex:light fallback=dforge:judge-opus review=task reason=band"
check "a split task without a part routes on its heaviest part" "$out" "review-seat task=7 primary=codex:light fallback=dforge:judge-opus review=task reason=band"
check "risk 3 goes to Astra then Opus" "$out" "review-seat task=8 primary=codex:heavy+judge-opus fallback=dforge:judge-opus review=task reason=risk"
check "total 5 at risk 0: light Codex, Opus fallback" "$out" "review-seat task=10 primary=codex:light fallback=dforge:judge-opus review=task reason=band"
check "codex off: total 1 goes to Sonnet alone" "$out" "review-seat task=1 primary=dforge:judge-sonnet-high fallback=- review=group reason=codex-off"
check "codex off: total 3 goes to Sonnet alone" "$out" "review-seat task=2 primary=dforge:judge-sonnet-high fallback=- review=group reason=codex-off"
check "codex off: total 4 goes to Opus alone" "$out" "review-seat task=3 primary=dforge:judge-opus fallback=- review=group reason=codex-off"
check "codex off: total 5 goes to Opus alone" "$out" "review-seat task=10 primary=dforge:judge-opus fallback=- review=task reason=codex-off"
check "codex off: risk 2 at total 4 takes its band" "$out" "review-seat task=4 primary=dforge:judge-opus fallback=- review=task reason=codex-off"
check "codex off: risk 3 goes to Opus alone" "$out" "review-seat task=8 primary=dforge:judge-opus fallback=- review=task reason=codex-off"
check "codex off: a split task routes on its heaviest part" "$out" "review-seat task=7 primary=dforge:judge-opus fallback=- review=task reason=codex-off"
check "codex off: an Executor task is unchanged" "$out" "review-seat task=5 primary=dforge:judge-sonnet-high fallback=- review=group reason=executor"
check "codex off: an Executor task at risk 2 is unchanged" "$out" "review-seat task=6 primary=dforge:judge-sonnet-high fallback=- review=task reason=executor"
check "no session file is off" "$out" "review-seat task=3 primary=dforge:judge-opus fallback=- review=group reason=codex-off"
check "a torn session file is off" "$out" "review-seat task=1 primary=dforge:judge-sonnet-high fallback=- review=group reason=codex-off"
check "no session id is off, whatever is on disk" "$out" "review-seat task=1 primary=dforge:judge-sonnet-high fallback=- review=group reason=codex-off"
check "an open review surface routes to Codex again" "$out" "review-seat task=1 primary=codex:light fallback=dforge:judge-sonnet-high review=group reason=band"
check "a CRLF plan routes" "$out" "review-seat task=4 primary=codex:light fallback=dforge:judge-opus review=task reason=band"
LIGHT="primary=codex:light fallback=dforge:judge-sonnet-high review=group reason=band"
check "a real Executor line still routes to a Claude judge" "$out" \
  "review-seat task=1 primary=dforge:judge-sonnet-high fallback=- review=group reason=executor"
```

(b) Append this section immediately before the final `printf '\n%d passed, %d failed\n' "$pass" "$fail"` line. It uses the suite's `route`, `seat`, `review_surface` and `check` helpers.

```bash
# --- the review tier ---
# A task is reviewed alone (review=task) at risk 2 or more or a total of 5 or
# more, and grouped (review=group) otherwise. A batch carries no tier, and a
# task with no Evaluation line is reviewed alone instead of failing the route.
review_surface true
tier_of() { sed -n 's/.* review=\([^ ]*\) reason=.*/\1/p' <<<"$out"; }
route --task 3
check "tier: total 4 at risk 1 is grouped" "$(tier_of)" "group"
route --task 4
check "tier: risk 2 at total 4 is reviewed alone" "$(tier_of)" "task"
route --task 10
check "tier: total 5 at risk 0 is reviewed alone" "$(tier_of)" "task"
route --task 7A
check "tier: a light part is grouped" "$(tier_of)" "group"
route --task 7
check "tier: a whole split task takes its heaviest part's tier" "$(tier_of)" "task"
route --task 1 3
check "tier: a batch carries no review field" "$(grep -c ' review=' <<<"$out")" "0"
review_surface false
route --task 2
check "tier: codex off keeps the tier" "$(tier_of)" "group"
review_surface true

printf '# P\n\n### Task 1: Unscored\n\n**Implementer:** dforge:impl-sonnet-low\n\nBody.\n\n### Task 2: Scored\n\n**Evaluation:** files 0 - spec 0 - coupling 1 - risk 0 = 1\n\n### Task 3: Split\n\n#### Part A: a\n\n**Evaluation:** files 0 - spec 0 - coupling 1 - risk 0 = 1\n\n#### Part B: b\n\nNo score.\n' > "$TMP/unscored.md"
seat "$TMP/unscored.md" 1
check "unscored: exits 0" "$rc" "0"
check "unscored: reviewed alone by Opus" "$out" "review-seat task=1 primary=dforge:judge-opus fallback=- review=task reason=unscored"
check "unscored: nothing on stderr" "$(cat "$TMP/err")" ""
seat "$TMP/unscored.md" 3B
check "unscored: a part with no Evaluation line is unscored too" "$out" "review-seat task=3B primary=dforge:judge-opus fallback=- review=task reason=unscored"
review_surface false
seat "$TMP/unscored.md" 1
check "unscored: codex off names the same seat" "$out" "review-seat task=1 primary=dforge:judge-opus fallback=- review=task reason=unscored"
review_surface true
out=$(bash "$ROUTE" "$TMP/unscored.md" --task 1 2 2>/dev/null); rc=$?
check "unscored: a batch holding an unscored task still exits 2" "$rc" "2"
seat "$TMP/unscored.md" 2
check "unscored: its scored neighbour routes as before" "$out" "review-seat task=2 primary=codex:light fallback=dforge:judge-sonnet-high review=group reason=band"
```

- [ ] **Step 2: Run them to verify they fail**

Run: `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/review-route.test.sh`
Expected: FAIL — `256 passed, 45 failed` on the current tree: the 33 rewritten expectations and the `tier:` and `unscored:` checks, because no line carries a `review=` field and a task with no Evaluation line exits 2. "a batch carries no review field" and "a batch holding an unscored task still exits 2" already pass.

- [ ] **Step 3: Implement**

In `plugins/dforge/scripts/review-route`, `--task` branch only:

1. In the loop over ids, where `evs=$(plan_eval_lines <<<"$text")` comes back empty (the task, or the named part, has no `**Evaluation:**` line): when exactly one id was given, print `review-seat task=<id> primary=dforge:judge-opus fallback=- review=task reason=unscored` and exit 0. This holds whatever the session's Codex gate says and whether or not the task has an `**Executor:**` line. With two or more ids, keep today's `die "Task $id has no **Evaluation:** line"` (exit 2).
2. An Evaluation line that does not parse still exits 2 with nothing on stdout (the existing `die`).
3. After the seat is chosen, when exactly one id was given, the tier is `task` when `max_risk >= 2` or `max_total >= 5`, else `group` (a whole split task uses its parts' maxima, as the seat already does). Print it as ` review=<tier>` between the `fallback=` and `reason=` fields: `review-seat task=4 primary=codex:light fallback=dforge:judge-opus review=task reason=band`. With several ids, print the line exactly as today, with no `review=` field.
4. Update the header comment: the Output line shows the `review=` field for a single `--task` id, and the Exit line says a lone task with no Evaluation line exits 0 with `reason=unscored`.
5. Nothing else changes: the seat and fallback choice, `--plan-round`, `--ruling`, `--final`, `--final-fix`, and the Codex-host exit 2.

- [ ] **Step 4: Run the suites**

Run: `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/review-route.test.sh`, then the suites that call `review-route` through `task-step` or grep its line: `tests/task-step.test.sh`, `tests/working-directory.test.sh`, `tests/task-loop-steps.acceptance.test.sh` (same prefix and timeout).
Expected: PASS — review-route `301 passed, 0 failed`; the other three `0 failed`.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/scripts/review-route plugins/dforge/tests/review-route.test.sh
git commit -m "feat(dforge): add a review tier to review-route"
```

### Task 5: Group review state in task-step

**Files:**
- Modify: `plugins/dforge/scripts/task-step` (the argument parser after `if [ "${1:-}" = rereview ]`, new `do_hold` and `do_group` beside `do_review`, the dispatch `case $sub in` at the end, and `cmd_rereview`'s fix-base choice and state update; the header comment and `usage`)
- Create: `plugins/dforge/skills/subagent-driven-development/references/group-reviewer-prompt.md`
- Test: `plugins/dforge/tests/task-step.test.sh`, `plugins/dforge/tests/task-step-text.test.sh`

**Interfaces:**
- Consumes: Review tier (Task 4) — the `review=` field of `review-route PLAN_FILE --task N`; the existing `review-package PLAN_FILE BASE HEAD OUTFILE`, `lens-route PLAN_FILE --task N`, `task-<N>-step.json` (`base`, `head`, `reviewHead`, `round`, `t0`) and `cmd_rereview`.
- Produces: Group review (Task 5) — `task-step hold` (exits 0, 2, 3, 4, 6), `task-step review --group` (refusing members not held or already in review rounds), `group-<list>-step.json`, `group-<list>-review-package.md`, `group-<list>-review-prompt.md`, the group template, and the per-member step-file fields (`heldHead`, `reviewHead`, `t0`, `round`, plus `group`) that let `task-step rereview PLAN_FILE N` re-review one member.

**Items:** 1 review rounds, 2 execution time

**Implementer:** dforge:impl-opus-high
**Evaluation:** files 1 - spec 2 - coupling 2 - risk 2 = 7
**Override:** owner approved the contract-and-test task shape for this plan on 2026-10-26, before plan-lint's Rule S and assignment table allow it

- [ ] **Step 1: Write the failing tests**

(a) Append this section to `plugins/dforge/tests/task-step.test.sh` immediately before its final `printf '\n%d passed, %d failed\n' "$pass" "$fail"` line, after the rereview section: it uses that section's `RR_S`, and the suite's `PR`, `winpath`, `count_lines`, `placeholders` and `check`.

```bash
# --- hold and review --group: grouped tasks reviewed together ---
# The fixture plan's lines carry a leading | so a plan that quotes this suite still lints.
GR_TMP=$TMP/gr
GR_REPO=$GR_TMP/repo
mkdir -p "$GR_TMP/home" "$GR_REPO/docs"
gr_run() { # gr_run <args...> — task-step in the group fixture repo; sets gr_out, gr_err, gr_rc
  gr_out=$(cd "$GR_REPO" && env HOME="$GR_TMP/home" DR_CODEX_SESSION_DIR="$GR_TMP/sessions" CLAUDE_CODE_SESSION_ID=gr-test \
    GIT_CONFIG_NOSYSTEM=1 DFORGE_NO_SETTINGS=1 MSYS_NO_PATHCONV=1 bash "$RR_S/task-step" "$@" 2>"$GR_TMP/err"); gr_rc=$?
  gr_err=$(cat "$GR_TMP/err")
}
gr_git() { git -C "$GR_REPO" "$@"; }
gr_commit() { # gr_commit <file> — append a line to a fixture file and commit it
  GR_N=$((GR_N + 1))
  printf 'line %s\n' "$GR_N" >> "$GR_REPO/$1"
  gr_git add -A && gr_git commit -qm "feat: change $1"
}
gr_short() { gr_git rev-parse --short "$1"; }
gr_state() { # gr_state <task> <jq filter>
  jq -r "$2" "$GR_WS/task-$1-step.json" | tr -d '\r'
}
gr_lines() { wc -l < "$GR_LEDGER" | tr -d ' '; }
gr_section() { # gr_section <package> <task> — the package's section for one task
  awk -v h="## Task $2" '{ sub(/\r$/, "") } $0 == h { on = 1; next } /^## / { on = 0 } on' "$1"
}

git init -q "$GR_REPO"
gr_git config user.name t
gr_git config user.email t@example.invalid
sed 's/^|//' > "$GR_REPO/docs/plan.md" <<'PLAN'
|# Group Fixture Plan
|
|**Goal:** Fixture.
|
|**Execution:** subagent — `claude --model sonnet --effort high` — fixture
|
|## Global Constraints
|
|- Fixture constraint.
|
|## Contracts
|
|- Fixture contract.
|
|## Task index
|
|1. Light one
|2. Light two
|3. Heavy
|4. Light three
|5. Unscored
|6. Wave six
|7. Wave seven
|
|### Task 1: Light one
|
|**Files:**
|- Modify: `one.txt`
|
|**Implementer:** dforge:impl-sonnet-low
|**Evaluation:** files 0 - spec 0 - coupling 1 - risk 0 = 1
|**Lenses:** lang-bash
|
|### Task 2: Light two
|
|**Files:**
|- Modify: `two.txt`
|
|**Implementer:** dforge:impl-sonnet-medium
|**Evaluation:** files 1 - spec 1 - coupling 1 - risk 1 = 4
|
|### Task 3: Heavy
|
|**Files:**
|- Modify: `three.txt`
|
|**Implementer:** dforge:impl-opus-high
|**Evaluation:** files 1 - spec 1 - coupling 1 - risk 2 = 5
|
|### Task 4: Light three
|
|**Files:**
|- Modify: `four.txt`
|
|**Implementer:** dforge:impl-sonnet-low
|**Evaluation:** files 0 - spec 1 - coupling 1 - risk 0 = 2
|
|### Task 5: Unscored
|
|**Implementer:** dforge:impl-sonnet-low
|
|Body.
|
|### Task 6: Wave six
|
|**Files:**
|- Modify: `six.txt`
|
|**Implementer:** dforge:impl-sonnet-low
|**Evaluation:** files 0 - spec 0 - coupling 1 - risk 0 = 1
|
|### Task 7: Wave seven
|
|**Files:**
|- Modify: `seven.txt`
|
|**Implementer:** dforge:impl-sonnet-low
|**Evaluation:** files 0 - spec 0 - coupling 1 - risk 0 = 1
PLAN
awk '{ print } /^\*\*Goal:\*\*/ { print ""; print "**Host:** codex" }' "$GR_REPO/docs/plan.md" > "$GR_REPO/docs/codex-plan.md"
for f in one two three four six seven; do printf 'base\n' > "$GR_REPO/$f.txt"; done
gr_git add -A && gr_git commit -qm base
GR_N=0
GR_MAIN=$(gr_git symbolic-ref --short HEAD)
GR_WS=$(winpath "$(cd "$GR_REPO" && env HOME="$GR_TMP/home" bash "$RR_S/sdd-workspace" docs/plan.md)")
GR_LEDGER=$GR_WS/progress.md

# hold: the preconditions, then the awaiting line and the held head.
gr_run hold docs/plan.md 1
check "hold: before start exits 6" "$gr_rc" "6"
gr_run start docs/plan.md 1
GR_B1=$(gr_git rev-parse HEAD)
gr_commit one.txt
GR_H1=$(gr_git rev-parse HEAD)
gr_run hold docs/plan.md 1
check "hold: exit 0" "$gr_rc" "0"
check "hold: the awaiting line" "$(tail -n 1 "$GR_LEDGER")" "Task 1: awaiting group review (commits $(gr_short "$GR_B1")..$(gr_short "$GR_H1"))"
check "hold: records the held head" "$(gr_state 1 .heldHead)" "$GR_H1"
check "hold: keeps the base" "$(gr_state 1 .base)" "$GR_B1"
check "hold: the digest's first line" "$(head -n 1 <<<"$gr_out")" "task 1: held for group review (commits $(gr_short "$GR_B1")..$(gr_short "$GR_H1"))"
check "hold: the digest is at most 15 lines" "$([ "$(count_lines "$gr_out")" -le 15 ] && echo yes || echo no)" "yes"
check "hold: the last line is the budget line" "$(tail -n 1 <<<"$gr_out" | cut -c1-6)" "budget"
before=$(gr_lines)
gr_run hold docs/plan.md 1
check "hold again: exit 0" "$gr_rc" "0"
check "hold again: no second awaiting line" "$(gr_lines)" "$before"

# hold refuses a task review-route reviews alone, and writes nothing for it.
gr_run start docs/plan.md 3
gr_commit three.txt
before=$(gr_lines)
gr_run hold docs/plan.md 3
check "hold: a review=task task exits 4" "$gr_rc" "4"
check "hold: says the task is reviewed alone" "$(grep -c 'review=task' <<<"$gr_err")" "1"
check "hold: a review=task task gets no awaiting line" "$(gr_lines)" "$before"
check "hold: a review=task task records no held head" "$(gr_state 3 '.heldHead // "none"')" "none"
gr_run hold docs/plan.md 5
check "hold: an unscored task is reviewed alone and exits 4" "$gr_rc" "4"
gr_run hold docs/plan.md 99
check "hold: no such task exits 3" "$gr_rc" "3"
gr_run hold docs/plan.md
check "hold: no task number exits 2" "$gr_rc" "2"
gr_run hold docs/plan.md 1 2
check "hold: two task numbers exit 2" "$gr_rc" "2"
gr_run hold docs/plan.md 1 --head
check "hold: --head without a value exits 2" "$gr_rc" "2"
gr_run hold docs/plan.md 1 --head nope
check "hold: a bad ref exits 2" "$gr_rc" "2"
gr_run hold docs/codex-plan.md 1
check "hold: a Host: codex plan exits 2" "$gr_rc" "2"

gr_run start docs/plan.md 2
GR_B2=$(gr_git rev-parse HEAD)
gr_commit two.txt
gr_run hold docs/plan.md 2
gr_run start docs/plan.md 4
gr_commit four.txt
GR_H4=$(gr_git rev-parse HEAD)
gr_run hold docs/plan.md 4
check "hold: a third grouped task" "$gr_rc" "0"

# review --group: every member must be held.
gr_run review --group docs/plan.md 1 3
check "review --group: a member that is not held exits 4" "$gr_rc" "4"
check "review --group: names the task that is not held" "$(grep -c 'Task 3' <<<"$gr_err")" "1"
check "review --group: a refused group writes no file" "$(ls "$GR_WS" | grep -c '^group-')" "0"
gr_run review --group docs/plan.md 1 5
check "review --group: a task with no ledger line exits 4" "$gr_rc" "4"
gr_run review --group docs/plan.md 1 99
check "review --group: no such task exits 3" "$gr_rc" "3"
gr_run review --group docs/plan.md
check "review --group: no task number exits 2" "$gr_rc" "2"
gr_run review --group docs/plan.md 1 2 --head HEAD
check "review --group: --head is not a group flag" "$gr_rc" "2"
gr_run review --group docs/codex-plan.md 1
check "review --group: a Host: codex plan exits 2" "$gr_rc" "2"

# review --group: the package, the prompt, the digest and the state. The review
# surface is open, and a group is still reviewed by a Claude judge alone.
mkdir -p "$GR_TMP/sessions"
printf '{"session_id":"gr-test","usable":true,"review":true,"lane":false}\n' > "$GR_TMP/sessions/gr-test.json"
gr_run review --group docs/plan.md 4 1 2
GL=1,2,4
GPKG=$GR_WS/group-$GL-review-package.md
GPR=$GR_WS/group-$GL-review-prompt.md
check "review --group: exit 0" "$gr_rc" "0"
check "review --group: the files are named after the sorted list" \
  "$([ -f "$GR_WS/group-$GL-step.json" ] && [ -f "$GPKG" ] && [ -f "$GPR" ] && echo yes || echo no)" "yes"
check "review --group: one section per task, in order" "$(grep '^## ' "$GPKG" | tr -d '\r' | tr '\n' ';')" "## Task 1;## Task 2;## Task 4;"
check "review --group: a section names its brief" "$(gr_section "$GPKG" 1 | grep -cxF "**Brief:** $GR_WS/task-1-brief.md")" "1"
check "review --group: a section names its report" "$(gr_section "$GPKG" 1 | grep -cxF "**Report:** $GR_WS/task-1-report.md")" "1"
check "review --group: a section names its range" "$(gr_section "$GPKG" 1 | grep -cxF "**Commits:** $(gr_short "$GR_B1")..$(gr_short "$GR_H1")")" "1"
check "review --group: a section holds its own diff" "$(gr_section "$GPKG" 1 | grep -c '^diff --git a/one.txt b/one.txt$')" "1"
check "review --group: a section holds no other task's diff" "$(gr_section "$GPKG" 1 | grep -cE '^diff --git a/(two|three|four)\.txt')" "0"
check "review --group: a later member's diff starts at its own base" "$(gr_section "$GPKG" 2 | grep -cE '^diff --git a/(one|three|four)\.txt')" "0"
check "review --group: the later member's diff" "$(gr_section "$GPKG" 2 | grep -c '^diff --git a/two.txt b/two.txt$')" "1"
check "review --group: the last member's diff" "$(gr_section "$GPKG" 4 | grep -c '^diff --git a/four.txt b/four.txt$')" "1"
check "review --group: a section names its lens files" "$(gr_section "$GPKG" 1 | grep -cxF "**Lenses:** $PR/criteria/lenses/lang-bash.md")" "1"
check "review --group: a task with no lens has no lens line" "$(gr_section "$GPKG" 2 | grep -c '^\*\*Lenses:\*\*')" "0"
check "review --group: the prompt has no unexpanded placeholder" "$(placeholders "$GPR")" "0"
check "review --group: the prompt names the package" "$([ "$(grep -cF "$GPKG" "$GPR")" -ge 1 ] && echo yes || echo no)" "yes"
check "review --group: the prompt names the report file" "$([ "$(grep -cF "$GR_WS/group-$GL-review-report.md" "$GPR")" -ge 1 ] && echo yes || echo no)" "yes"
check "review --group: the prompt names the criteria file" "$([ "$(grep -cF "$PR/criteria/task-review.md" "$GPR")" -ge 1 ] && echo yes || echo no)" "yes"
check "review --group: the prompt names the group" "$([ "$(grep -cF "$GL" "$GPR")" -ge 1 ] && echo yes || echo no)" "yes"
check "review --group: the seat is the route's Claude judge" "$(grep '^seat:' <<<"$gr_out")" "seat: dforge:judge-opus prompt: $GPR"
check "review --group: no Codex seat runs" "$(grep -cE '^(codex|timeout):' <<<"$gr_out")" "0"
check "review --group: no Codex prompt is written" "$(ls "$GR_WS" | grep -c 'codex')" "0"
check "review --group: the identity check" "$(grep '^check identity' <<<"$gr_out")" "check identity: clean"
check "review --group: the attribution check" "$(grep '^check attribution' <<<"$gr_out")" "check attribution: clean"
check "review --group: the digest is at most 15 lines" "$([ "$(count_lines "$gr_out")" -le 15 ] && echo yes || echo no)" "yes"
check "review --group: the last line is the budget line" "$(tail -n 1 <<<"$gr_out" | cut -c1-6)" "budget"
check "review --group: the group state names its tasks" "$(jq -c .tasks "$GR_WS/group-$GL-step.json" | tr -d '\r')" "[1,2,4]"
check "review --group: the group state records the group head" "$(jq -r .reviewHead "$GR_WS/group-$GL-step.json" | tr -d '\r')" "$GR_H4"
check "review --group: the group state records t0" "$(jq -r '.t0 | type' "$GR_WS/group-$GL-step.json" | tr -d '\r')" "number"
for n in 1 2 4; do
  check "review --group: Task $n records the group head" "$(gr_state "$n" .reviewHead)" "$GR_H4"
  check "review --group: Task $n records round 0" "$(gr_state "$n" .round)" "0"
  check "review --group: Task $n records t0" "$(gr_state "$n" '.t0 | type')" "number"
  check "review --group: Task $n names its group" "$(gr_state "$n" .group)" "$GL"
done
check "review --group: a member keeps its base" "$(gr_state 2 .base)" "$GR_B2"
check "review --group: a task outside the group is untouched" "$(gr_state 3 '.reviewHead // "none"')" "none"

# A member's fix round re-reviews alone. In one checkout the fixes run one at a
# time, so each member's fix diff starts where the group's last review ended.
gr_commit one.txt
GR_F1=$(gr_git rev-parse HEAD)
printf -- '- one.txt: wrong value\n\nFix it.\n' > "$GR_WS/task-1-fix-1.md"
gr_run rereview docs/plan.md 1
GRR1=$GR_WS/task-1-rereview-1-prompt.md
check "member rereview: exit 0" "$gr_rc" "0"
check "member rereview: the fix base is the group head" "$(grep -c "Fix base:\*\* $GR_H4 " "$GRR1")" "1"
check "member rereview: records the round" "$(gr_state 1 .round)" "1"
check "member rereview: records its review head" "$(gr_state 1 .reviewHead)" "$GR_F1"
check "member rereview: the group records the latest review head" "$(jq -r .reviewHead "$GR_WS/group-$GL-step.json" | tr -d '\r')" "$GR_F1"
gr_commit two.txt
printf -- '- two.txt: stale\n\nFix it.\n' > "$GR_WS/task-2-fix-1.md"
gr_run rereview docs/plan.md 2
GRR2=$GR_WS/task-2-rereview-1-prompt.md
GRD2=$(sed -n 's/^\*\*Diff file:\*\* //p' "$GRR2")
check "member rereview: the next member's fix base is the last fix head" "$(grep -c "Fix base:\*\* $GR_F1 " "$GRR2")" "1"
check "member rereview: the next member's fix diff holds its own fix" "$(grep -c '^diff --git a/two.txt b/two.txt$' "$GRD2")" "1"
check "member rereview: the next member's fix diff leaves the earlier fix out" "$(grep -c '^diff --git a/one.txt' "$GRD2")" "0"
gr_commit four.txt
printf -- '- four.txt: off by one\n\nFix it.\n' > "$GR_WS/task-4-fix-1.md"
gr_run rereview docs/plan.md 4 --base "$GR_H4"
check "member rereview: --base <group review head> works for a member" "$gr_rc $(grep -c "Fix base:\*\* $GR_H4 " "$GR_WS/task-4-rereview-1-prompt.md")" "0 1"

# A group with a review round line is in its fix rounds: reviewing it again
# would reset every member's round and lift the two-round cap.
printf '%s\n' 'Group 1,2,4: review round 1/2 (Task 1: clean; Task 2: clean; Task 4: 1 open — off by one; commits aaaaaaa..bbbbbbb (Task 1), bbbbbbb..ccccccc (Task 2), ccccccc..ddddddd (Task 4))' >> "$GR_LEDGER"
gr_run review --group docs/plan.md 1 2 4
check "review --group: a group in its fix rounds exits 4" "$gr_rc" "4"
check "review --group: names every member already in review rounds" "$(grep -c 'Task 1' <<<"$gr_err") $(grep -c 'Task 2' <<<"$gr_err") $(grep -c 'Task 4' <<<"$gr_err")" "1 1 1"
check "review --group: a refused group keeps each member's round" "$(gr_state 1 .round) $(gr_state 2 .round) $(gr_state 4 .round)" "1 1 1"

# A wave: each member is held at its task ref and re-reviewed from its own head.
GR_W=$(gr_git rev-parse HEAD)
gr_run start docs/plan.md 6
gr_run start docs/plan.md 7
gr_git branch t6 "$GR_W"
gr_git branch t7 "$GR_W"
gr_git checkout -q t6
gr_commit six.txt
GR_H6=$(gr_git rev-parse HEAD)
gr_git checkout -q t7
gr_commit seven.txt
GR_H7=$(gr_git rev-parse HEAD)
gr_git checkout -q "$GR_MAIN"
gr_git worktree add -q --detach "$GR_TMP/wt6" t6
gr_run hold docs/plan.md 6 --cwd "$GR_TMP/wt6"
check "hold --cwd: records that checkout's HEAD" "$(gr_state 6 .heldHead)" "$GR_H6"
before=$(gr_lines)
gr_run hold docs/plan.md 6 --head t6
check "hold --head: exit 0" "$gr_rc" "0"
check "hold --head: records the ref" "$(gr_state 6 .head)" "t6"
check "hold --head: the same range writes no second line" "$(gr_lines)" "$before"
gr_run hold docs/plan.md 7 --head t7
check "hold --head: records the ref's commit" "$(gr_state 7 .heldHead)" "$GR_H7"
gr_run review --group docs/plan.md 6 7 --cwd "$GR_TMP/wt6"
GPKG67=$GR_WS/group-6,7-review-package.md
check "wave group: exit 0" "$gr_rc" "0"
check "wave group: --cwd names the checkout whose HEAD is the group head" "$(jq -r .reviewHead "$GR_WS/group-6,7-step.json" | tr -d '\r')" "$GR_H6"
check "wave group: a member's review head is its own held head" "$(gr_state 6 .reviewHead) $(gr_state 7 .reviewHead)" "$GR_H6 $GR_H7"
check "wave group: each section holds its own task ref's diff" \
  "$(gr_section "$GPKG67" 6 | grep -c '^diff --git a/seven.txt') $(gr_section "$GPKG67" 7 | grep -c '^diff --git a/seven.txt b/seven.txt$')" "0 1"
gr_git checkout -q t6
gr_commit six.txt
GR_F6=$(gr_git rev-parse HEAD)
gr_git checkout -q "$GR_MAIN"
printf -- '- six.txt: wrong value\n\nFix it.\n' > "$GR_WS/task-6-fix-1.md"
gr_run rereview docs/plan.md 6
check "wave member rereview: the fix base is its own held head" "$(grep -c "Fix base:\*\* $GR_H6 " "$GR_WS/task-6-rereview-1-prompt.md")" "1"
check "wave member rereview: the head is its task ref" "$(grep -c "Head:\*\* $GR_F6\$" "$GR_WS/task-6-rereview-1-prompt.md")" "1"
printf '%s\n' 'Group 6-7: review round 1/2 (Task 6: 1 open — wrong value; Task 7: clean; commits aaaaaaa..bbbbbbb (Task 6))' >> "$GR_LEDGER"
gr_run review --group docs/plan.md 6 7
check "review --group: a range Group line also marks its members as in review rounds" "$gr_rc $(grep -c 'Task 7' <<<"$gr_err")" "4 1"
gr_git worktree remove --force "$GR_TMP/wt6"
```

(b) Append this section to `plugins/dforge/tests/task-step-text.test.sh` immediately before its final `printf '\n%d passed, %d failed\n' "$pass" "$fail"` line.

```bash
# --- the group reviewer template ---
GRP="$P/skills/subagent-driven-development/references/group-reviewer-prompt.md"
check "the group reviewer template exists" "$([ -f "$GRP" ] && echo yes || echo no)" "yes"
for ph in '[GROUP_LIST]' '[PACKAGE_FILE]' '[REPORT_FILE]' '[PLUGIN_ROOT]'; do
  names "the group template carries $ph" "$GRP" "$ph"
done
names "the group template is a fenced prompt task-step can fill" "$GRP" '  prompt: |'
names "the group package holds one section per task" "$GRP" 'one section per task, headed `## Task <N>`'
names "the group reviewer scores each task on its own" "$GRP" 'Score each task on its own'
names "the group report holds one block per task" "$GRP" 'one block per task, headed `### Task <N>`'
names "a group finding names its task" "$GRP" 'prefix its file with `(Task <N>) `'
names "a finding in one task never fails another" "$GRP" 'A finding in one task never fails another task'
names "the group reviewer reads a section's lens files" "$GRP" 'a `**Lenses:**` line'
lacks "the group template takes no single diff placeholder" "$GRP" '[DIFF_FILE]'
check "the group prompt holds no placeholder task-step does not fill" \
  "$(awk '/^  prompt: \|/ { on = 1; next } on && /^```/ { exit } on' "$GRP" 2>/dev/null | grep -oE '\[[A-Z][A-Z_]*\]' | sort -u | grep -cvxE '\[(GROUP_LIST|PACKAGE_FILE|REPORT_FILE|PLUGIN_ROOT)\]')" "0"
```

- [ ] **Step 2: Run them to verify they fail**

Run: `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/task-step.test.sh` and `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID -u CLAUDE_CONFIG_DIR timeout 120 bash plugins/dforge/tests/task-step-text.test.sh`
Expected: FAIL — task-step.test.sh reports `219 passed, 70 failed`: every `hold`, `review --group`, `member rereview`, `hold --cwd`, `hold --head`, `wave group` and `wave member rereview` check fails, because `hold` and `review --group` are unknown and exit 2; only the usage-error checks (those expecting exit 2) pass. In task-step-text.test.sh the group-template checks fail because the template does not exist; the two negative ones pass.

- [ ] **Step 3: Implement**

**Parsing.** `task-step hold PLAN_FILE N [--head REF] [--cwd DIR]` takes exactly one task number; `task-step review --group PLAN_FILE N M … [--cwd DIR]` takes `--group` directly after `review` and one or more numbers. `hold` accepts only `--head` and `--cwd`; `review --group` only `--cwd`; any other flag, a missing value, or a second number for `hold` exits 2 with the usage line. Both run the existing preamble unchanged: plan located, `Host: codex` exits 2, a task not in the plan exits 3, and an amendment that does not apply exits 4 as it does for every subcommand. `hold` therefore exits 0 held; 2 usage, a bad ref or `--cwd` directory, or `Host: codex`; 3 no such task; 4 `review-route` reviews the task alone; 6 no step state (before `start`). Update the header comment and `usage` with both forms, and the Exit line: `4` also means `hold` was refused because `review-route` reviews the task alone, or `review --group` was given a task with no `awaiting group review` line or one already in a group's review rounds.

**The terminal line.** A helper reads the ledger for one task: the last line beginning `Task <N>: `, stepping over `minor (deferred)`, `parked` and `Ruling:` lines (the Recovery rule of subagent-driven-development).

**`hold`.**
1. Run `review-route PLAN_FILE --task N`. The tier is its `review=` field when it exits 0; a non-zero exit or a missing field counts as `review=task` (a route that cannot score the task never groups it). On `review=task` print `task-step: Task <N> is reviewed alone (review-route: review=task); run task-step review` on stderr and exit 4, writing nothing.
2. No `task-<N>-step.json`: exit 6, as `review` does.
3. The held head is the commit of `--head REF` (a bad ref exits 2), else `git -C DIR rev-parse HEAD` for `--cwd DIR` (a missing directory exits 2), else the checkout's HEAD.
4. The ledger line is `Task <N>: awaiting group review (commits <base7>..<held7>)`, `base` from the step file. Append it unless the task's terminal line is already exactly that line. Create the ledger with its identity line first when it is missing, as `start` does.
5. Write `heldHead` (full SHA) into the step file, and `head` set to the REF string when `--head` was given. No other field changes.
6. Print `task <N>: held for group review (commits <base7>..<held7>)`, or `task <N>: already held for group review (commits …)` when no line was appended; then `state: base <base7> held-head <held7>`; then the budget line from `scripts/context-size` with `DFORGE_BUDGET_CALLER=task-step:hold`.

**`review --group`.**
1. Every task's terminal line must begin `Task <N>: awaiting group review (`; for the first that does not, print `task-step: Task <N> holds no awaiting group review line; hold it or review it alone` on stderr and exit 4, writing nothing. Because `hold` refuses a `review=task` task, this check is also what keeps one out of a group. Then refuse every task a `Group <list>: review round` line of the ledger names (a comma list names the tasks it lists, a range every task from its first number to its last): such a group is in its fix rounds, and reviewing it again would reset each member's `round` to 0 and lift the two-round cap. Print one stderr line, `task-step: already in group review rounds: Task <N>, Task <M>; re-review a member with task-step rereview`, naming each such task, and exit 4, writing nothing and leaving every step file alone.
2. `<list>` is the task numbers sorted ascending, duplicates dropped, joined by commas (`1,2,4`).
3. The group head is HEAD of the checkout, or of `--cwd DIR` (a missing directory exits 2).
4. For each member in ascending order: run `lens-route PLAN_FILE --task N` (a failure exits 2 and writes nothing, as in `review`); run `review-package PLAN_FILE <base> <heldHead> <temp file>`; append to the package:

   ```text
   ## Task <N>

   **Brief:** <workspace>/task-<N>-brief.md
   **Report:** <workspace>/task-<N>-report.md
   **Commits:** <base7>..<held7>
   **Lenses:** <every criteria= path lens-route printed, joined by ", ">

   <the review-package file without its first line, every line beginning "## " rewritten to begin "### ">
   ```

   The `**Lenses:**` line is present only when `lens-route` printed a path. The package opens with `# Group review package: Tasks <list>`; the `## Task <N>` lines are its only `## ` headings.
5. The seat: run `review-route PLAN_FILE --task <every member>`. The judge is its `fallback` when `primary` is `codex:light`, `dforge:judge-opus` when `primary` is any other `codex:` seat, else `primary`; a route failure gives `dforge:judge-opus` and the same ` (review-route exited <N>: <first stderr line>)` note `review` prints. No Codex prompt, runner command, timeout or gate line: a group is reviewed by one Claude judge.
6. The prompt: the group template's fenced `prompt: |` body (the existing `prompt_text`), filled with the existing `fill`: `[GROUP_LIST]` the list, `[PACKAGE_FILE]` the package path, `[REPORT_FILE]` `<workspace>/group-<list>-review-report.md`, `[PLUGIN_ROOT]` the plugin directory. A placeholder left unexpanded exits 2.
7. Checks: run `check_identity` and `check_attribution` over each member's `base..heldHead`. Print one `check identity:` and one `check attribution:` line: `clean` when every member is clean, else `check identity: Task <N>: <what that member's check printed after "check identity: ">` for the first member that found something (the same for attribution).
8. Write the package and the prompt to `<workspace>/group-<list>-review-package.md` and `<workspace>/group-<list>-review-prompt.md` only once steps 1-7 have succeeded. Write `<workspace>/group-<list>-step.json` as `{tasks: [<numbers>], reviewHead: <group head>, t0: <date +%s>}`. In each member's step file set `reviewHead` (the member's `heldHead` when its step file has a non-null `head`, a task held with `--head`; the group head otherwise), `t0`, `round` 0 and `group` "<list>"; leave `base`, `head` and `heldHead` alone.
9. Print at most 15 lines: `group <list>: packaged <k> task(s) at head <head7>, package <package path>`; `seat: <judge> prompt: <prompt path>[<note>]`; the two check lines; `state: group <list> review-head <head7> round 0 t0 <t0>`; the budget line (`DFORGE_BUDGET_CALLER=task-step:review-group`).

**`rereview` for a member.** In `cmd_rereview`, when the step file has `group` and no `head` and `<workspace>/group-<group>-step.json` exists, the fix base without `--base` is that file's `reviewHead`, and after the step file is updated the file's `reviewHead` becomes this round's head. In one checkout the members' fixes run one after another, so this is what keeps each member's fix diff to its own fix. An explicit `--base` still wins and is recorded as today. A member with a `head` (a wave task) keeps today's behaviour: its own `reviewHead`, which `review --group` set to its held head.

**The group template** `plugins/dforge/skills/subagent-driven-development/references/group-reviewer-prompt.md`, modelled on `task-reviewer-prompt.md`: a title and purpose line, then one fence holding `Subagent (the judge seat task-step review --group prints):`, a `description:` line and `  prompt: |` with a four-space-indented body, then a **Placeholders:** list for the four placeholders and a **Reviewer returns:** line. The body reuses the task reviewer's sections adapted to several tasks: what was requested and claimed (each task's brief and report, named in its package section), the package as the reviewer's one view of the change, read-only on the checkout, You Do Not Dispatch Subagents, Do Not Trust the Report, Tests, Part 1 Spec Compliance and Part 2 Code Quality per task, Calibration, and an Output Format of one block per task, each holding its spec verdict (✅/❌/⚠️), Issues by severity, `**Task quality:**` and `### Verification Scores` (spec, scope, verification, quality, 1-20 against `[PLUGIN_ROOT]/criteria/task-review.md`). Its last paragraph says the final message is the report itself and the controller keeps it at `[REPORT_FILE]`; Task 9 replaces that reply contract for every judge template. The body names only the four placeholders and holds no `[DIFF_FILE]`. It carries these six sentences verbatim, each whole on one line of the indented body (wrap the prose around them, never inside them: the text checks grep one line):

```text
Read the package at [PACKAGE_FILE]: one section per task, headed `## Task <N>`, each naming that task's brief, its report, its commit range and its diff.
Read the criteria file at [PLUGIN_ROOT]/criteria/task-review.md. Score each task on its own against it.
Where a task's section carries a `**Lenses:**` line, read each lens file it names and report each hit as an issue of that task tagged `[lens:<id>]`.
A finding in one task never fails another task: judge each task against its own brief.
Return one block per task, headed `### Task <N>`, in the package's order.
Every finding names its task: prefix its file with `(Task <N>) `, as in `(Task 4) src/a.ts:12`.
```

- [ ] **Step 4: Run the suites**

Run: `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/task-step.test.sh`, the same for `tests/task-step-text.test.sh` (timeout 120), `tests/review-route.test.sh` and `tests/task-loop-steps.acceptance.test.sh`; then `node scripts/validate-repository.mjs` and `timeout 120 /root/.local/bin/claude plugin validate plugins/dforge`.
Expected: PASS — `0 failed` in each suite (task-step.test.sh ran `285 passed` against a prototype of this step with Task 4 applied, before the four review-rounds refusal checks were added; it now holds 289 checks); validation clean.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/scripts/task-step plugins/dforge/skills/subagent-driven-development/references/group-reviewer-prompt.md plugins/dforge/tests/task-step.test.sh plugins/dforge/tests/task-step-text.test.sh
git commit -m "feat(dforge): add group review to task-step"
```

### Task 6: Group review in the skill text, recovery and the cockpit

Rule S would split this task as one unit (files 2 - spec 2 - coupling 2), so it carries two parts, dispatched in order.

#### Part A: The loop, the ledger and the waves

**Files:**
- Modify: `plugins/dforge/reference/delegated-task.md` (§2 Handle the report, a new `## 3a. Review a group` after §3, §5 Complete the task, the Recovery table)
- Modify: `plugins/dforge/skills/subagent-driven-development/SKILL.md` (After compaction step 2, Overview, The Process graph, The Ledger grammar, its bullets and Recovery table, The Task Loop)
- Modify: `plugins/dforge/reference/parallel-waves.md` (The ledger lines, §3 Review each task on its own, §4 Merge each task as it passes)
- Test: `plugins/dforge/tests/task-step-text.test.sh`

**Interfaces:**
- Consumes: Group review (Task 5) — `task-step hold`, `task-step review --group`, member `rereview`; Review tier (Task 4).
- Produces: Group review (Task 5) — the ledger lines `Task <N>: awaiting group review (commits <a7>..<b7>)` and `Group <list>: review round R/2 (Task <N>: <k> open — <one-liners> | clean; …; commits <a7>..<b7> (Task <N>)[, <a7>..<b7> (Task <M>)])` in the shared grammar, which Part B's readers parse.

**Items:** 1 review rounds, 2 execution time

**Implementer:** dforge:impl-opus-high
**Evaluation:** files 1 - spec 2 - coupling 1 - risk 2 = 6
**Override:** owner approved the contract-and-test task shape for this plan on 2026-10-26, before plan-lint's Rule S and assignment table allow it

- [ ] **Step 1: Write the failing tests**

Append this section to `plugins/dforge/tests/task-step-text.test.sh` immediately before its final `printf '\n%d passed, %d failed\n' "$pass" "$fail"` line (after Task 5's template section). It uses the suite's `DT`, `SDD`, `PW`, `names` and `lacks`.

```bash
# --- group reviews in the loop, the ledger and the waves ---
names "DONE holds a grouped task" "$DT" '`bash <plugin-root>/scripts/task-step hold PLAN_FILE N`'
names "exit 4 from hold means reviewed alone" "$DT" 'exit 4 means the task is reviewed alone'
names "the group review call" "$DT" '`bash <plugin-root>/scripts/task-step review --group PLAN_FILE N M …`'
names "the group trigger" "$DT" 'when 4 tasks are held, before you dispatch a task `review-route` reviews alone, and after the plan'"'"'s last task'
names "nothing is dispatched while a group is open" "$DT" 'no new task is dispatched until the group is clean'
names "group fixes run one task at a time" "$DT" 'fixes inside a group run one task at a time'
names "a concerned or blocked member leaves the group" "$DT" 'leaves the group and is reviewed alone'
names "a member re-reviews on the moving group head" "$DT" "each member's re-review moves that head on"
names "a group runs two fix rounds" "$DT" 'A group runs at most two fix rounds'
names "each member gets its own complete line" "$DT" 'each member gets its own `complete` line once the group is clean'
names "the loop's recovery reads a held task" "$DT" '| `awaiting group review (commits …)` |'
names "the ledger grammar holds the awaiting line" "$SDD" 'Task <N>: awaiting group review (commits <a7>..<b7>)'
names "the ledger grammar holds the group review line" "$SDD" 'Group <list>: review round R/2 (Task <N>: <k> open — <one-liners> | clean; …; commits <a7>..<b7> (Task <N>)[, <a7>..<b7> (Task <M>)])'
names "a group list is a comma list or a range" "$SDD" 'joined by commas (`Group 4,6,7`), or a contiguous range (`Group <a>-<b>`)'
names "a comma list covers the tasks it names" "$SDD" 'a comma list covers the tasks it names'
names "the recovery table reads a held task" "$SDD" '| `awaiting group review` | Reviewed by the next group dispatch'
names "the recovery table resumes a group's round 2" "$SDD" '| `review round 1/2` on a group review'"'"'s `Group` line |'
names "the recovery table sends a group's round 2 to the breaker" "$SDD" '| `review round 2/2` on a group review'"'"'s `Group` line |'
names "after compaction a held task waits for its group" "$SDD" '`awaiting group review` is reviewed by the next group dispatch'
names "the process graph names the group template" "$SDD" './references/group-reviewer-prompt.md'
lacks "the overview no longer reviews every task alone" "$SDD" 'a judge-scored task review after each task;'
names "waves hold a grouped task at its ref" "$PW" '`task-step hold PLAN_FILE N --head <TASK_REF>`'
names "waves review grouped tasks before any merges" "$PW" 'once every grouped task in the wave is held, before any of them merges'
names "a wave member's fix round stays in its worktree" "$PW" "a member's fix round goes to that task's implementer in its worktree"
names "a grouped wave task merges once its group is clean" "$PW" 'or, for a grouped task, its group is clean'
```

- [ ] **Step 2: Run them to verify they fail**

Run: `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID -u CLAUDE_CONFIG_DIR timeout 120 bash plugins/dforge/tests/task-step-text.test.sh`
Expected: FAIL — all 25 new checks: none of the phrases is in the three files yet, and the Overview still says `a judge-scored task review after each task;`.

- [ ] **Step 3: Implement**

Each file's block of phrases below is what the Step 1 checks grep. Write every phrase verbatim and whole on one line (wrap the prose around a phrase, never inside it), inside full sentences.

`plugins/dforge/reference/delegated-task.md`:
1. §2, **DONE:** in subagent mode, run the hold call (a wave task adds `--head <task ref>`). Exit 0 holds the task for its group review (§3a) and writes its `awaiting group review` line; exit 4 means the task is reviewed alone: review it (step 3). Inline mode delegates only tasks `review-route` reviews alone, so it goes straight to step 3. Keep the sentence about `task-step review` recording `t0`.
2. §2, after the four statuses: a grouped task that reports BLOCKED, NEEDS_CONTEXT, or DONE_WITH_CONCERNS with a correctness or scope concern leaves the group, even when it later reports DONE; the group reviews once its remaining members are held.
3. A new `## 3a. Review a group` between §3 and §4. In sequential mode held tasks accumulate, and the group review runs at the trigger phrase below (run `review-route PLAN_FILE --task <next>` to read the next task's tier before dispatching it). Once triggered, nothing new is dispatched until the group is clean, and its fixes run one at a time. The call names every held task; dispatch its `seat:` line as §3 says for a judge, with the prompt file; a group never gets a Codex seat. The report holds one block per task: apply §3's verdicts, score bands, ⚠️ route and plan-conflict route to each task on its own, and §4's Minor rule (`Task <N>: minor (deferred): …`). A member with findings enters §4's fix loop with the fix message `<workspace>/task-<N>-fix-<R>.md`, and is re-reviewed with `task-step rereview PLAN_FILE N` and no `--base`: `review --group` recorded the group head as its review head, and each member's re-review moves that head on, so a fix diff holds only that member's fix. After each round append the group line (subagent-driven-development §The Ledger): one clause per member, and in its `commits` clause one `<a7>..<b7> (Task <N>)` range per member fixed in that round, in sequential and wave mode alike. Findings still open after round 2 go to the breaker as §4 says. Members write no `Task <N>: fix round` lines: the `Group` line is their round record. A group with a round line is never reviewed again: `review --group` refuses its members (exit 4), and its later rounds are member re-reviews.
4. §5: a member's complete line takes its `commits` range from its `awaiting group review` line and ends its scores clause `, seat <judge> (group <list>)`.
5. The Recovery table gains the held-task row below, and two rows for a group review's `Group` line: `review round 1/2` runs round 2 for each member whose clause is open, a fresh dispatch after compaction; `review round 2/2` sends each member's open findings to the breaker.
6. Keep what `tests/task-step-text.test.sh` already pins before `## The steps by hand`: the `task-step start PLAN_FILE N`, `task-step review PLAN_FILE N` and `task-step rereview PLAN_FILE N` calls, no `scripts/review-package`, and exactly one `date +%s`.

```text
`bash <plugin-root>/scripts/task-step hold PLAN_FILE N`
exit 4 means the task is reviewed alone
`bash <plugin-root>/scripts/task-step review --group PLAN_FILE N M …`
when 4 tasks are held, before you dispatch a task `review-route` reviews alone, and after the plan's last task
no new task is dispatched until the group is clean
fixes inside a group run one task at a time
leaves the group and is reviewed alone
each member's re-review moves that head on
A group runs at most two fix rounds
each member gets its own `complete` line once the group is clean
| `awaiting group review (commits …)` | Held: never re-dispatch its implementer. It is reviewed by the next group dispatch (§3a), which the trigger above starts |
```

`plugins/dforge/skills/subagent-driven-development/SKILL.md`:
1. After compaction, step 2: add the held-task sentence below.
2. Overview: replace `a judge-scored task review after each task;` with `a judge-scored review of each task, alone or, for a low-risk task, in a group with others;`.
3. The Process graph: between "Implementer implements, tests, commits, self-reviews" and "Generate review package, dispatch judge (./references/task-reviewer-prompt.md)" add the diamond `"review-route: review=group?"`. Its `no` edge goes to "Generate review package…"; its `yes` edge goes to the box below, which goes to "Verdicts clean and no score 1-8?". Remove the direct edge from "Implementer implements…" to "Generate review package…".
4. The Ledger grammar block: after the `Group <a>-<b>: review round R/5` line, add the two grammar lines below, in that order.
5. Rewrite the batch bullet: every task gets its own assigned and complete line, including tasks reviewed as a batch or in a group review; batches are contiguous ranges named `Group <a>-<b>`; a group review's `<list>` is written as the phrase below says; its clause attributes every finding to its member, and its commits clause holds one `<a7>..<b7> (Task <N>)` range per member fixed in the round, in sequential and wave mode alike.
6. Recovery: after "any `Group` line covering N" add the covering phrase below. Add the three rows below before the batch `review round R/5` rows, and say a group review's `Group` line is the one whose clause starts `Task <N>:`.
7. The Task Loop: a `**Group reviews.**` paragraph: a task `review-route` grades `review=group` is held after DONE and reviewed with other held tasks in one judge dispatch, per delegated-task.md §3a.

```text
`awaiting group review` is reviewed by the next group dispatch, never re-dispatched.
"task-step hold; review the group at 4 held, before a review=task dispatch, and after the last task (./references/group-reviewer-prompt.md)"
Task <N>: awaiting group review (commits <a7>..<b7>)
Group <list>: review round R/2 (Task <N>: <k> open — <one-liners> | clean; …; commits <a7>..<b7> (Task <N>)[, <a7>..<b7> (Task <M>)])
the task numbers in ascending order joined by commas (`Group 4,6,7`), or a contiguous range (`Group <a>-<b>`)
(a range covers the tasks inside it; a comma list covers the tasks it names)
| `awaiting group review` | Reviewed by the next group dispatch ([delegated-task.md](../../reference/delegated-task.md) §3a); never re-dispatch its implementer |
| `review round 1/2` on a group review's `Group` line | Run round 2 for each member whose clause is open, one member at a time, a fresh dispatch after compaction |
| `review round 2/2` on a group review's `Group` line | Send each member's open findings to the breaker |
```

`plugins/dforge/reference/parallel-waves.md`:
1. The ledger lines block gains `Group <list>: review round R/2 (Task <N>: <k> open — <one-liners> | clean; …; commits <a7>..<b7> (Task <N>)[, <a7>..<b7> (Task <M>)])`.
2. §3: a `**Grouped tasks.**` paragraph: a wave task graded `review=group` is not reviewed on its own; when it reports DONE, run the hold call below; at the phrase below, run one `task-step review --group PLAN_FILE <their numbers>` and dispatch its seat (delegated-task.md §3a). Each member keeps its held head as its review head, so its fix round stays in its worktree, re-reviewed with `task-step rereview PLAN_FILE N --head <TASK_REF>`.
3. §4, first sentence: "When a task's review is clean, or every open finding is parked at the breaker" becomes "When a task's review is clean (or, for a grouped task, its group is clean), or every open finding is parked at the breaker".

```text
`task-step hold PLAN_FILE N --head <TASK_REF>`
once every grouped task in the wave is held, before any of them merges
a member's fix round goes to that task's implementer in its worktree
or, for a grouped task, its group is clean
```

What must not change: the Codex-host loop, inline mode's own text, the batch (`Group <a>-<b>`) rows and grammar line (Task 7 rewrites the `R/5` forms), and every phrase the suites listed in Step 4 pin.

- [ ] **Step 4: Run the suites**

Run, each as `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/<suite>`: `task-step-text.test.sh`, and the suites that pin these three files: `review-route.test.sh`, `inline-mode.test.sh`, `seats.test.sh`, `process-roles.test.sh`, `lanes.test.sh`, `final-phase.test.sh`, `auto-run-skills.test.sh`, `waiting-text.test.sh`, `codex-review.test.sh`, `executor-recovery.test.sh`, `project-status.test.sh`, `ui-ux-skill.test.sh`, `task-loop-steps.acceptance.test.sh`. Then `node scripts/validate-repository.mjs` and `timeout 120 /root/.local/bin/claude plugin validate plugins/dforge`.
Expected: PASS — `0 failed` in every suite; validation clean.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/reference/delegated-task.md plugins/dforge/skills/subagent-driven-development/SKILL.md plugins/dforge/reference/parallel-waves.md plugins/dforge/tests/task-step-text.test.sh
git commit -m "feat(dforge): run group reviews in the task loop"
```

#### Part B: The cockpit and next-step

**Files:**
- Modify: `plugins/dforge/hooks/cockpit/lib.ts` (`parseLedger`, the `^Group (\d+)-(\d+): review round` match; the `LedgerTask.round` doc comment)
- Modify: `plugins/dforge/scripts/next-step` (the task loop that sets `first_open` and the `next_line` choices after it)
- Test: `plugins/dforge/tests/cockpit.test.ts`, `plugins/dforge/tests/next-step.test.sh`

**Interfaces:**
- Consumes: Group review (Task 5) — the ledger lines `Task <N>: awaiting group review (commits <a7>..<b7>)` and `Group <list>: review round R/2 (Task <N>: <k> open — <one-liners> | clean; …; commits <a7>..<b7> (Task <N>)[, <a7>..<b7> (Task <M>)])`, `<list>` a comma list or an `a-b` range.
- Produces: `parseLedger` sets the round of every assigned task a `Group` line names, for a comma list and a range; `next-step` never names a held task as the next to start, and while a group is in its fix rounds names that group's next round as the next step.

**Items:** 1 review rounds, 2 execution time

**Implementer:** dforge:impl-opus-high
**Evaluation:** files 2 - spec 2 - coupling 1 - risk 1 = 6
**Override:** owner approved the contract-and-test task shape for this plan on 2026-10-26, before plan-lint's Rule S and assignment table allow it

- [ ] **Step 1: Write the failing tests**

(a) In `plugins/dforge/tests/cockpit.test.ts`, inside `describe('run card', …)`, insert immediately before `test('lists running, blocked and pending tasks before done ones', () => {` (it uses the describe block's `runFiles`, and the file's `world`, `signedIn`, `SIGNED_IN`, `START` and `PANE`):

```ts
  const GROUPED = [
    '# SDD ledger — plan: docs/plans/p.md',
    'Task 1: implementer dforge:impl-sonnet-low (assigned; base abc1234)',
    'Task 1: awaiting group review (commits abc1234..bcd2345)',
    'Task 2: implementer dforge:impl-sonnet-low (assigned; base bcd2345)',
    'Task 3: implementer dforge:impl-sonnet-low (assigned; base bcd2345)',
    'Task 3: awaiting group review (commits bcd2345..cde3456)',
    'Group 1,3: review round 1/2 (Task 1: 1 open — meter width; Task 3: clean; commits cde3456..def4567 (Task 1))',
  ].join('\n')

  test('reads a group review line with a comma list beside a range', () => {
    const ledger = parseLedger(`${GROUPED}\nTask 8: implementer dforge:impl-sonnet-low (assigned; base def4567)\nGroup 8-9: review round 2/5 (1 addressed, 0 open; commits def4567..efa5678; fresh)`)
    expect(ledger.tasks.map(task => [task.n, task.state, task.round])).toEqual([
      [1, 'assigned', '1/2'],
      [2, 'assigned', null],
      [3, 'assigned', '1/2'],
      [8, 'assigned', '2/5'],
      [9, 'assigned', '2/5'],
    ])
  })

  test('clears a group round when each member completes', () => {
    const ledger = parseLedger(`${GROUPED}\nTask 1: complete (commits abc1234..bcd2345, review clean) — done: x; verified: y; remaining: none; discovered: none; assumptions: none\nGroup 1,3: review round 2/2 (Task 1: clean; Task 3: clean; commits def4567..efa5678 (Task 1))`)
    expect(ledger.tasks.map(task => [task.n, task.state, task.round])).toEqual([
      [1, 'complete', null],
      [2, 'assigned', null],
      [3, 'assigned', '2/2'],
    ])
  })

  test('shows a group review round on the run card', async ($, on) => {
    const files = runFiles(GROUPED)
    world(on, { ...SIGNED_IN, files })
    signedIn(on, files)
    await $.tool.call({ tool: 'Skill', skill: 'dforge:subagent-driven-development' })
    await $.session.start(START)
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    expect(await ui.find({ type: 'Text', text: /round 1\/2 · impl-sonnet-low/ })).toBeDefined()
    expect(JSON.stringify(await ui.drawn())).not.toContain('round 2/5')
  })
```

(b) In `plugins/dforge/tests/next-step.test.sh`, insert immediately before the line `# --- a ledger ending on an assigned line warns, and still prints the block ---`:

```bash
# --- held tasks: a task awaiting its group review is not the next to start ---
ledger 'Task 1: complete (commits a..b, review clean)' \
       'Task 2: implementer dforge:impl-sonnet-low (assigned; base bbbbbbb)' \
       'Task 2: awaiting group review (commits bbbbbbb..ccccccc)' \
       'Task 2: minor (deferred): rename'
run "$REPO" "$PLAN_REL"
check "held: exits 0" "$status" "0"
has "held: a held task is not complete" "$out" "1 of 3 tasks complete"
has "held: resumes at the first task neither complete nor held" "$out" "**Next:** Resume at Task 3 (Third thing). Task 2 is held for group review."
has "held: the prompt carries the held task" "$out" "Resume \`$PLAN_REL\` with dforge:resume-execution. Resume at Task 3 (Third thing). Task 2 is held for group review."
ledger 'Task 1: implementer dforge:impl-sonnet-low (assigned; base aaaaaaa)' \
       'Task 1: awaiting group review (commits aaaaaaa..bbbbbbb)'
run "$REPO" "$PLAN_REL"
has "held: with nothing complete, starts at the first task not held" "$out" "**Next:** Start at Task 2 (Second thing). Task 1 is held for group review."
ledger 'Task 1: complete (commits a..b, review clean)' \
       'Task 2: awaiting group review (commits bbbbbbb..ccccccc)' \
       'Task 3: awaiting group review (commits ccccccc..ddddddd)'
run "$REPO" "$PLAN_REL"
has "held: every open task held means the group review is next" "$out" "**Next:** Review the held Tasks 2,3 as one group (\`task-step review --group\`), then write their complete lines."
lacks "held: no task is named to start" "$out" "Resume at Task"

# --- a group in its fix rounds blocks every new dispatch ---
ledger 'Task 1: awaiting group review (commits aaaaaaa..bbbbbbb)' \
       'Task 2: awaiting group review (commits bbbbbbb..ccccccc)' \
       'Group 1,2: review round 1/2 (Task 1: 1 open — x; Task 2: clean; commits ccccccc..ddddddd (Task 1))'
run "$REPO" "$PLAN_REL"
has "group round 1: round 2 for the open members is next" "$out" "**Next:** Run fix round 2 of Group 1,2 for Task 1, then write the members' complete lines."
lacks "group round 1: the next task is not started" "$out" "Start at Task 3"
lacks "group round 1: the group is not reviewed again" "$out" "Review the held Tasks"
ledger 'Task 1: complete (commits a..b, review clean)' \
       'Task 2: awaiting group review (commits bbbbbbb..ccccccc)' \
       'Task 3: awaiting group review (commits ccccccc..ddddddd)' \
       'Group 2,3: review round 1/2 (Task 2: 1 open — x; Task 3: 2 open — y, z; commits ddddddd..eeeeeee (Task 2), eeeeeee..fffffff (Task 3))' \
       'Group 2-3: review round 2/2 (Task 2: clean; Task 3: 1 open — z; commits fffffff..aaaaaaa (Task 3))'
run "$REPO" "$PLAN_REL"
has "group round 2: the open findings go to the breaker" "$out" "**Next:** Send the open findings of Group 2-3 (Task 3) to the breaker, then write the members' complete lines."
ledger 'Task 1: complete (commits a..b, review clean)' \
       'Task 2: awaiting group review (commits bbbbbbb..ccccccc)' \
       'Task 3: awaiting group review (commits ccccccc..ddddddd)' \
       'Group 2,3: review round 1/2 (Task 2: clean; Task 3: clean; commits ddddddd..eeeeeee (Task 2))'
run "$REPO" "$PLAN_REL"
has "group clean: the complete lines are next" "$out" "**Next:** Write the complete lines of Group 2,3's members: the group is clean."
ledger 'Task 1: complete (commits a..b, review clean)' \
       'Task 2: awaiting group review (commits bbbbbbb..ccccccc)' \
       'Task 2: complete (commits bbbbbbb..ccccccc, review clean)'
run "$REPO" "$PLAN_REL"
has "held: a held task that completed is not held" "$out" "**Next:** Resume at Task 3 (Third thing)."
lacks "held: and is not named as held" "$out" "held for group review"
```

- [ ] **Step 2: Run them to verify they fail**

Run: `env -u CLAUDE_CONFIG_DIR timeout 300 /root/.local/bin/claude plugin test plugins/dforge` and `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/next-step.test.sh`
Expected: FAIL — the plugin test reports `449 pass, 3 fail`: the three new run-card tests, because `Group 1,3:` matches no pattern and leaves the rounds null. next-step reports `197 passed, 8 failed`: it names the held task as the one to resume, and has neither a group-review nor a group-round next step.

- [ ] **Step 3: Implement**

`plugins/dforge/hooks/cockpit/lib.ts`, `parseLedger`:
1. Match `^Group (<list>): review round (\d+\/\d+)` where `<list>` is a comma list of task numbers (`\d+(?:,\d+)*`) or a range (`\d+-\d+`). A range names every task from its first number to its last; a comma list names exactly the tasks it lists. Each named task whose state is `assigned` takes the round; a `complete` or `blocked` task keeps its state and its null round, as today.
2. `Task <N>: awaiting group review` lines start no task and change nothing (they fall through, as Ruling lines do).
3. The `LedgerTask.round` comment reads "The fix or review round in flight, "2/5" or "1/2"". Nothing else in the file changes.

`plugins/dforge/scripts/next-step`, the branch that counts tasks (`first_open="" open_title="" done_count=0`):
1. With a ledger for this plan, a task is held when its last `Task <N>:` line, stepping over `minor (deferred)`, `parked` and `Ruling:` lines (as `ledger_blocked` in `scripts/lib/plan.sh` reads them), begins `Task <N>: awaiting group review`. `Group` lines do not change it.
2. `first_open` is the first task in plan order that is neither complete nor held. Held tasks join a comma list in plan order.
3. When `first_open` exists and tasks are held, the next line gains, after its sentence, ` Task <N> is held for group review.` (one) or ` Tasks <list> are held for group review.` (several), on both the `Start at …` and the `Resume at …` forms; the resume prompt carries it because it embeds the next line.
4. A group is in its fix rounds when a `Group <list>: review round R/<D>` line names a held task (a comma list names the tasks it lists, a range every task from its first number to its last); take the last such line in file order. Its open members are the `Task <N>: <k> open` clauses with `k` of 1 or more, in clause order, joined by commas (`Task 3`, or `Tasks 2,3`). Then, whatever task is open, the next line is:
   - no open member: `Write the complete lines of Group <list>'s members: the group is clean.`
   - `R` of 1: `Run fix round 2 of Group <list> for <Task N | Tasks N,M>, then write the members' complete lines.`
   - `R` of 2 or more: `Send the open findings of Group <list> (<Task N | Tasks N,M>) to the breaker, then write the members' complete lines.`
   `<list>` is written as the line spells it (`2,3` or `2-3`). Reading the open clauses must not abort the script when none matches (a `grep` with no match under `pipefail`).
5. Otherwise, when no task is open but some are held, the next line is ``Review the held Tasks <list> as one group (`task-step review --group`), then write their complete lines.``. Both 4 and 5 keep the usual `<k> of <total> tasks complete` status line and never fall through to the final-review line.
6. The BLOCKED branch keeps its precedence over 4 and 5, and nothing changes for a ledger with no held task.

- [ ] **Step 4: Run the suites**

Run: `env -u CLAUDE_CONFIG_DIR timeout 300 /root/.local/bin/claude plugin test plugins/dforge`, `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/next-step.test.sh`, and with the same prefix `tests/project-status.test.sh`, `tests/turn-end.test.sh`, `tests/in-flight.test.sh`, `tests/working-directory.test.sh`, `tests/task-loop-steps.acceptance.test.sh`; then `timeout 120 /root/.local/bin/claude plugin validate plugins/dforge`.
Expected: PASS — the plugin test `0 fail` (`452 pass` against a prototype of this step), next-step `205 passed, 0 failed`, the other suites `0 failed`; validation clean.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/hooks/cockpit/lib.ts plugins/dforge/scripts/next-step plugins/dforge/tests/cockpit.test.ts plugins/dforge/tests/next-step.test.sh
git commit -m "feat(dforge): read group review lines in readers"
```

### Task 7: Cap the fix loop at two rounds

**Files:**
- Modify: `plugins/dforge/scripts/task-step` (`cmd_rereview`, the header's Exit line)
- Modify: `plugins/dforge/reference/delegated-task.md` (§1 agent-identity bullet, §4 The fix loop, §Recovery)
- Modify: `plugins/dforge/skills/subagent-driven-development/references/escalation.md` (Where escalation applies, Recording an escalation, The top rung is SPLIT)
- Modify: `plugins/dforge/skills/subagent-driven-development/references/re-review-prompt.md` (the `### Progress` section, "Re-reviewer returns")
- Modify: `plugins/dforge/skills/subagent-driven-development/references/ruling-prompt.md` (the `breaker:` kind line)
- Modify: `plugins/dforge/reference/executor-lane.md` (Dispatch, Resuming an executor task, When the resume itself fails, Failure rows)
- Modify: `plugins/dforge/reference/ladder.md` (the prose under the `codex-successor` block only)
- Modify: `plugins/dforge/skills/subagent-driven-development/SKILL.md` (After compaction, The Process graph, The Ledger grammar and Recovery, The Ruling Seat kinds table, the example workflow)
- Modify: `plugins/dforge/skills/executing-plans/SKILL.md` (After compaction step 4, the delegated-task paragraph, the ledger note, Recovery row, ruling kinds table)
- Test: `plugins/dforge/tests/task-step.test.sh`
- Test: `plugins/dforge/tests/task-step-text.test.sh`

**Interfaces:**
- Consumes: Contracts "Fix loop (Task 7)"; the `Group <list>: review round R/2 (…)` line of Contracts "Group review (Task 5)"; `task-step rereview` and its step state (`round`, `reviewHead`) as they stand.
- Produces: Contracts "Fix loop (Task 7)": the `R/2` ledger forms, the `R/5` read mapping, and `task-step rereview`'s exit 7 at the two-round cap (it writes nothing and prints `task-step: fix round <R> is past the cap of 2; send the open findings to the breaker (reference/delegated-task.md §4)` on stderr).

**Items:** 1, 2

**Implementer:** dforge:impl-opus-high
**Evaluation:** files 2 - spec 2 - coupling 1 - risk 2 = 7
**Override:** owner approved the contract-and-test task shape for this plan on 2026-10-26, before plan-lint's Rule S and assignment table allow it

- [ ] **Step 1: Write the failing tests**

In `plugins/dforge/tests/task-step.test.sh`, insert directly after the line `check "rereview round 2: the state round is 2" "$(rr_state 1 .round)" "2"` (the end of the "Rounds chain" block; the next block starts with `rr_reset`, which restores the state):

```bash

# The loop holds two rounds: a third rereview writes nothing and names the breaker.
rr_edit app.txt add4
rr_git add -A && rr_git commit -qm fix3
rr_fix 1 3 "- app.txt: still wrong"
cp "$RR_WS/task-1-step.json" "$RR_TMP/state1.2"
rr_run rereview docs/plan.md 1 --covered
check "rereview round 3: exits 7" "$rr_rc" "7"
check "rereview round 3: names the cap and the breaker" "$(grep -c 'task-step: fix round 3 is past the cap of 2; send the open findings to the breaker' <<<"$rr_err")" "1"
check "rereview round 3: writes no prompt" "$([ -f "$RR_WS/task-1-rereview-3-prompt.md" ] && echo yes || echo no)" "no"
check "rereview round 3: leaves the state alone" "$(cmp -s "$RR_WS/task-1-step.json" "$RR_TMP/state1.2" && echo same || echo changed)" "same"
check "rereview round 3: prints no digest" "$rr_out" ""
# A step state an older run left at round 4 of 5 goes to the breaker too.
jq '.round = 4' "$RR_TMP/state1.2" > "$RR_WS/task-1-step.json"
rr_fix 1 5 "- app.txt: still wrong"
rr_run rereview docs/plan.md 1 --covered
check "rereview after an older run's round 4: exits 7" "$rr_rc" "7"
check "rereview after an older run's round 4: names round 5" "$(grep -c 'fix round 5 is past the cap of 2' <<<"$rr_err")" "1"
```

In `plugins/dforge/tests/task-step-text.test.sh`, insert above the final `printf '\n%d passed, %d failed\n' "$pass" "$fail"` line (after any block an earlier task added there):

```bash
# --- the fix loop holds two rounds (faster-plans §3) ---
ESC="$P/skills/subagent-driven-development/references/escalation.md"
RRP="$P/skills/subagent-driven-development/references/re-review-prompt.md"
RUL="$P/skills/subagent-driven-development/references/ruling-prompt.md"
EL="$P/reference/executor-lane.md"
LAD="$P/reference/ladder.md"
# only_older <label> <file> — every line naming an R/5 round is about an older run's ledger
only_older() { check "$1" "$(grep -E 'round (<R>|[0-9R])/5([^0-9]|$)' "$2" | grep -vc 'older')" "0"; }

names "the loop holds two rounds" "$DT" 'Two rounds at most per task:'
names "round 1 resumes or re-dispatches by cache state" "$DT" '**Round 1 — resume or re-dispatch by cache state.**'
names "round 2 is a fresh dispatch on the successor rung" "$DT" '**Round 2 — a fresh dispatch on the successor rung.**'
names "a SPLIT successor keeps the rung for round 2" "$DT" 'When the successor is `SPLIT`, round 2 is a fresh dispatch of the same rung'
names "a reserve-tier task takes its reserve successor" "$DT" 'A reserve-tier task takes its reserve successor'
names "the breaker trips after round 2" "$DT" "When round 2's re-review still leaves findings open"
names "the fix-round line counts to 2" "$DT" 'Task <N>: fix round <R>/2 ('
names "recovery: round 1 resumes at round 2" "$DT" '| `fix round 1/2`, or `fix round 1/5` from an older run | Resume the loop at round 2'
names "recovery: round 2 goes to the breaker" "$DT" '| `fix round 2/2`, or `fix round R/5` with R >= 2 from an older run | Go to the breaker (§4) |'
names "a Codex host keeps five rounds" "$DT" 'A Codex host keeps its five-round cap (`review_cap: 5`)'
for gone in '**Progress.**' 'progress <p> -> <q>' 'Rounds 4-5' 'Five rounds maximum' 'rounds 1-3 may resume it' \
            'The five-round cap is the same.' 'skip never triggers escalation' 'returns the progress reading'; do
  lacks "the delegated loop drops: $gone" "$DT" "$gone"
done
only_older "the delegated loop names R/5 only for older runs" "$DT"

names "escalation: round 2 climbs the ladder" "$ESC" '- **Fix round 2.** Dispatch a fresh implementer on the successor rung'
names "escalation: the recorded round is 2/2" "$ESC" 'Task <N>: fix round 2/2 (1 addressed, 1 open - <one-liner>; commits <a7>..<b7>; escalated <old-agent> -> <new-agent>)'
names "escalation: a split comes from the breaker" "$ESC" "a split is reached only through the breaker's AMEND"
names "escalation: the split ruling counts two rounds" "$ESC" 'impl-opus-high exhausted after 2 rounds'
for gone in 'Fix rounds 4 and 5' 'progress has stalled' 'after 5 rounds' 'fix round 4/5'; do
  lacks "escalation drops: $gone" "$ESC" "$gone"
done

for gone in '### Progress' '**Progress:**' 'a progress reading'; do
  lacks "the re-review prompt drops: $gone" "$RRP" "$gone"
done
names "the breaker item follows the second round" "$RUL" 'breaker: findings still open after the second fix round.'
lacks "the breaker item no longer waits five rounds" "$RUL" 'fifth fix round'

names "executor: round 1 resumes the session" "$EL" "Fix round 1 resumes that executor's own session"
names "executor: round 2 hands back" "$EL" '**Round 2 is `HANDBACK`.**'
names "executor: the failed-resume example is round 1 of 2" "$EL" 'Task <N>: fix round 1/2 (0 addressed, 2 open - codex quota exhausted'
for gone in 'Round 4 is' 'Fix rounds 1 to 3' 'five-round cap' 'stalled at round 3' 'rounds 4 and 5' 'two in a row' '§Rounds 1-3'; do
  lacks "executor-lane drops: $gone" "$EL" "$gone"
done
names "ladder: the lane resumes once, then hands back" "$LAD" 'resumes the same session on round 1 and hands back on round 2'
lacks "ladder: no fourth round on the lane" "$LAD" 'heading for at round 4'

names "subagent mode: the fix-round grammar" "$SDD" 'Task <N>: fix round R/2 (X addressed, Y open — <one-liners>; commits a..b[; re-review skipped (<n> lines)]; resumed | fresh (<why>) | escalated <old> -> <new> | HANDBACK to <agent>)'
names "subagent mode: the group round grammar" "$SDD" ': review round R/2 ('
names "subagent mode: a group's round 1 resumes at round 2" "$SDD" "| \`review round 1/2\` on a \`Group\` line, or \`review round 1/5\` from an older run | Resume the group's loop at round 2"
names "subagent mode: a group's round 2 goes to the breaker" "$SDD" '| `review round 2/2` on a `Group` line, or `review round R/5` with R >= 2 from an older run | Go to the breaker |'
names "subagent mode: the wave round grammar" "$SDD" 'Wave <k>: fix round R/2 (<same fields as a fix round>)'
names "subagent mode: older ledgers map R/5" "$SDD" 'A `Task`, `Group` or `Wave` round line written before the two-round cap reads `R/5`: R = 1 resumes at round 2, and R >= 2 goes to the breaker.'
names "subagent mode: compaction resumes round 1 at round 2" "$SDD" '`fix round 1/2` resumes at round 2 with a fresh dispatch'
names "subagent mode: the breaker row" "$SDD" '| `breaker` | Every finding still open after round 2/2 |'
names "subagent mode: the flowchart caps at 2" "$SDD" '"R = 2?"'
names "subagent mode: the example round has no progress field" "$SDD" '[Ledger: Task 2: fix round 1/2 (2 addressed, 0 open; commits d4e5f6a..b7c8d9e; resumed)]'
for gone in 'progress p -> q' 'stalled progress' 'round 1 of 5' 'Fix round R of 5' 'Progress: 18' '"R = 5?"'; do
  lacks "subagent mode drops: $gone" "$SDD" "$gone"
done
only_older "subagent mode names R/5 only for older runs" "$SDD"
names "inline mode: delegated fix rounds stop at 2" "$INLINE" 'fix rounds up to 2 and'
names "inline mode: the breaker row" "$INLINE" "| \`breaker\` | A delegated task's findings still open after round 2/2 |"
only_older "inline mode names R/5 only for older runs" "$INLINE"

```

- [ ] **Step 2: Run them to verify they fail**

Run: `timeout 600 bash plugins/dforge/tests/task-step.test.sh; timeout 120 bash plugins/dforge/tests/task-step-text.test.sh`
Expected: FAIL — in task-step.test.sh the 7 new checks (`rereview` has no cap: round 3 exits 0, writes `task-1-rereview-3-prompt.md`, advances the state and prints a digest; round 5 likewise); every other case passes. In task-step-text.test.sh the 64 new checks fail (seen on the current tree: the texts still say five rounds, the Progress section, `progress p -> q` and `R/5`); `subagent mode: the group round grammar` passes already if Task 5 has written its `R/2` Group line. The suite's existing checks pass.

- [ ] **Step 3: Implement**

Each quoted phrase in the tests is a constant: write it verbatim on a single physical line (a line may run past the usual wrap). Any line that still names a `round R/5` (or `1/5`, `5/5`, `<R>/5`) must carry the word `older` on that same line. Keep these phrases other suites pin: `come from the \`codex-v4\` selector` and `A task on an external executor resumes that executor's own session instead` (delegated-task.md), `confirmed and carried into a later task, with a ruling at the cap` (delegated-task.md), `Its fix rounds resume that executor's own session` (escalation.md, on one line), `A refused initial run never reads it` (ladder.md), `ranked strictly above both the task's \`**Implementer:**\` agent and the inline session's rung` (SDD SKILL.md), and only one `date +%s` before `## The steps by hand` in delegated-task.md. `parallel-waves.md` is Task 8's; leave it.

1. **`scripts/task-step`, `cmd_rereview`.** Right after `round` and `new_round` are read from the step state (after the "rereview before review" exit 6, before the fix-message check), when `new_round` is greater than 2: print `task-step: fix round <new_round> is past the cap of 2; send the open findings to the breaker (reference/delegated-task.md §4)` to stderr and exit 7, before packaging, prompting or touching the state file. Add `7 the fix loop is at its two-round cap;` to the header comment's Exit list. Nothing else changes; a Host: codex plan still exits 2 earlier, and a group member's rereview (Task 5) meets the same cap.

2. **`reference/delegated-task.md`.**
   - §1, the bullet "Record the implementer's agent identity …": `fix rounds 1-3 may resume it` becomes `fix round 1 may resume it`.
   - §4, from "Everything else enters the loop." through the end of the `**Progress.**` paragraph: "A fix round is one fix dispatch plus one scoped re-review. Two rounds at most per task:", then a paragraph headed `**Round 1 — resume or re-dispatch by cache state.**` holding today's cache rule unchanged (the resume conditions, `t0`/`t1`, the fresh copy and `fresh (<why>)`, the external-executor sentence), then a paragraph headed `**Round 2 — a fresh dispatch on the successor rung.**`: dispatch a fresh implementer on the successor rung of ladder.md's escalation table with the brief path, the report-file path, the open findings and today's "A prior implementer attempted this task [N] times; you own it now. Read the report file for what was tried." framing; `When the successor is \`SPLIT\`, round 2 is a fresh dispatch of the same rung` (`impl-opus-high`), and a split is reached only through the breaker's AMEND; `A reserve-tier task takes its reserve successor` from the reserve table, and `impl-fable-max`, whose successor is `BLOCKED`, writes `Task <N>: BLOCKED — impl-fable-max exhausted — <what a human must decide>` instead of a round 2; an external task's round 2 is a `HANDBACK` to its `**Implementer:**` agent (executor-lane.md). Delete the `**Progress.**` paragraph.
   - `**Split and reserve.**`: the split now follows a tripped breaker: a finding still open after round 2 on `impl-opus-high` goes to the breaker, whose AMEND may rewrite the body into `#### Part A` / `#### Part B` units, applied with `scripts/plan-amend` and dispatched in order, one part per dispatch. A task is split once: a part on `impl-opus-high` takes its reserve successor `impl-opus-xhigh` at round 2, said aloud. Both stay `Ruling:` lines. Keep the Codex-host sentence, and replace "The five-round cap is the same." with `A Codex host keeps its five-round cap (\`review_cap: 5\`) from [codex-routing.json](codex-routing.json).`
   - The scoped re-review paragraph: "flags new breakage in the fix diff only, and returns the progress reading." becomes "and flags new breakage in the fix diff only."
   - The skip rule: "write the fix-round line with `re-review skipped (<n> lines)` in place of the progress reading. A skip never triggers escalation." becomes "write the fix-round line with `re-review skipped (<n> lines)`. A skipped re-review still counts as its round."
   - "After each round" line: `Task <N>: fix round <R>/2 (<X> addressed, <Y> open — <finding one-liners>; commits <a7>..<b7>[; re-review skipped (<n> lines)]; resumed | fresh (<why>) | escalated <old> -> <new> | HANDBACK to <agent>)`.
   - The breaker: "When round 5's re-review still leaves findings open" becomes `When round 2's re-review still leaves findings open`; the verdicts (park, CONFIRMED-GAP, AMEND, BLOCKED) and "Send findings to the breaker only at the cap." stay.
   - §Recovery: replace the two `fix round` rows with `| \`fix round 1/2\`, or \`fix round 1/5\` from an older run | Resume the loop at round 2 — a fresh dispatch on the successor rung (§4) |` and `| \`fix round 2/2\`, or \`fix round R/5\` with R >= 2 from an older run | Go to the breaker (§4) |`.

3. **`escalation.md`.** "Where escalation applies": "Two points, and no others:" — `- **Fix round 2.** Dispatch a fresh implementer on the successor rung` (the same rung when that successor is `SPLIT`; a reserve-tier task takes its reserve successor) and the BLOCKED handler bullet unchanged; delete the round-3 stall bullet. The next paragraph: escalation does not apply to fix round 1, which resumes the original agent subject to the cache rule. The executor paragraph: "Neither applies to a task running on an external executor. Its fix rounds resume that executor's own session at round 1 only - the one its `**Executor:**` line names - and round 2 leaves the lane by `HANDBACK` instead of climbing a rung - see …". Recording: the example becomes `Task <N>: fix round 2/2 (1 addressed, 1 open - <one-liner>; commits <a7>..<b7>; escalated <old-agent> -> <new-agent>)`. "The top rung is SPLIT": round 2 of a task on `impl-opus-high` is a fresh dispatch of `impl-opus-high`; `a split is reached only through the breaker's AMEND` — the findings round 2 leaves open go to the breaker, and its AMEND rewrites Task N's body into ordered parts (keep the markdown example, the per-part procedure and "do not decide the decomposition yourself"). The split ruling reads `Ruling: split Task <N> at the top rung into parts A and B (amendment A<k>) - impl-opus-high exhausted after 2 rounds - if wrong, the parts review separately and merge back`. "A task may be split-escalated once": a part on `impl-opus-high` whose round 1 leaves findings open takes `impl-opus-xhigh` at round 2 (the split is spent), with the existing reserve-entry ruling line; `impl-fable-max` has no successor, so its round 1 leaving findings open writes the BLOCKED line. Leave Escalating out of inline mode, Reserve agents named in a plan and When a model is unavailable unchanged.

4. **`re-review-prompt.md`.** Delete the `### Progress` heading and its `**Progress:** <1-20> …` paragraph inside the prompt fence. "Re-reviewer returns" ends "…out-of-scope observations, and a round verdict." Nothing else changes.

5. **`ruling-prompt.md`.** The kinds line `- breaker: findings still open after the fifth fix round.` becomes `- breaker: findings still open after the second fix round.` Only that line.

6. **`executor-lane.md`.** Dispatch: "the five-round cap" becomes "the two-round cap". Dispatch step 3: "a compaction would turn round 2 into a fresh dispatch" becomes "fix round 1". Resuming an executor task: `Fix round 1 resumes that executor's own session`, as a Claude implementer's round 1 does; the cache-rule link reads `([delegated-task.md](delegated-task.md) §4, Round 1)`. The `**Round 4 is \`HANDBACK\`.**` paragraph becomes `**Round 2 is \`HANDBACK\`.**` to the task's `**Implementer:**` agent, with the stall sentence deleted, and "the capability change rounds 4 and 5 exist to buy" becomes "the capability change round 2 exists to buy"; add that a finding still open after round 2 goes to the breaker (delegated-task.md §4). When the resume itself fails: "where round 4 was taking it anyway" becomes "round 2"; "the five-round cap" becomes "the two-round cap"; the `status=BLOCKED` row reads `\`HANDBACK\` now, rather than at round 2: the Claude implementer takes this round`; the empty-diff paragraph drops "Two consecutive empty-diff rounds are a stalled loop - `HANDBACK`." for "Round 2 is the `HANDBACK` unless the seat's verdict closes the findings."; the example becomes `Task <N>: fix round 1/2 (0 addressed, 2 open - codex quota exhausted, retried once then handed back; commits a7f..a7f; HANDBACK to impl-sonnet-low)`. Failure rows: the empty-diff row ends "round 2 is the `HANDBACK`" in place of "two in a row is a stalled loop and a `HANDBACK`".

7. **`ladder.md`**, the prose under `codex-successor` only: "the fix loop resumes the same session on rounds 1 to 3 and hands back on round 4" becomes `the fix loop resumes the same session on round 1 and hands back on round 2`; "the exit it was already heading for at round 4" becomes "at round 2". Native Codex's `review_cap: 5` lives in `codex-routing.json` and does not change.

8. **subagent-driven-development `SKILL.md`.** After compaction step 2: `` `fix round 1/2` resumes at round 2 with a fresh dispatch``, and `fix round 2/2` goes to the breaker (an older run's `R/5` maps as §The Ledger's Recovery says); step 4 names `fix round R/2`. The Process graph: every "Fix round R of 5: …" node and edge becomes "Fix round R of 2: R=1 resume or fresh by cache state; R=2 successor rung, fresh", "Dispatch scoped re-review with progress (./references/re-review-prompt.md)" becomes "Dispatch scoped re-review (./references/re-review-prompt.md)", and `"R = 5?"` becomes `"R = 2?"` (node and edges). The Ledger grammar: the fix-round line is the pinned `Task <N>: fix round R/2 (…)` line; the Group line, in whatever list form Task 5 left it, reads `review round R/2 (`; `Wave <k>: fix round R/2 (<same fields as a fix round>)`. Recovery: the two same-shape batch rows (`review round R/5` on a `Group` line, R < 5, and `review round 5/5` on a `Group` line) are replaced by the two pinned `review round 1/2` / `review round 2/2` rows; the group-review rows Task 6 added stay as they are; the inline-escalation row's "fresh at round 1 of 5" becomes "fresh at round 1 of 2"; the two remaining `fix round R/5` cells become `fix round R/2`; after the table add the pinned sentence `A \`Task\`, \`Group\` or \`Wave\` round line written before the two-round cap reads \`R/5\`: R = 1 resumes at round 2, and R >= 2 goes to the breaker.`, followed by "A `Wave` fix-round line resumes the wave's fix loop ([parallel-waves.md](../../reference/parallel-waves.md) §5) by the same rule." The Ruling Seat kinds: `| \`breaker\` | Every finding still open after round 2/2 |`. Example workflow: "Re-reviewer: both ADDRESSED. New breakage: none." and `[Ledger: Task 2: fix round 1/2 (2 addressed, 0 open; commits d4e5f6a..b7c8d9e; resumed)]`.

9. **executing-plans `SKILL.md`.** After compaction step 4 and the delegated-task ledger note name `fix round R/2`; the delegated-task paragraph says "fix rounds up to 2 and a reviewed complete line"; the Recovery row "An agent-named `implementer <agent> (assigned …)` line, or `fix round R/2`"; the kinds row `| \`breaker\` | A delegated task's findings still open after round 2/2 |`. Inline mode's own `fix round R/3` lines and trigger stay as they are.

- [ ] **Step 4: Run the suites**

Run:
```bash
timeout 600 bash plugins/dforge/tests/task-step.test.sh
timeout 120 bash plugins/dforge/tests/task-step-text.test.sh
for t in inline-mode seats process-roles waiting-text final-phase auto-run-skills lanes ui-ux-skill review-route codex-review executor-recovery; do
  env -u CLAUDE_CONFIG_DIR timeout 600 bash "plugins/dforge/tests/$t.test.sh" | tail -n 1
done
env -u CLAUDE_CONFIG_DIR -u AR_SESSION -u CLAUDE_CODE_SESSION_ID timeout 900 bash plugins/dforge/tests/task-loop-steps.acceptance.test.sh | tail -n 1
node scripts/validate-repository.mjs
timeout 120 /root/.local/bin/claude plugin validate plugins/dforge
```
Expected: PASS — every suite ends `0 failed` (task-step.test.sh 200 checks on the tree this plan starts from, plus any an earlier task added); both validators pass.

- [ ] **Step 5: Commit**
```bash
git add plugins/dforge/scripts/task-step plugins/dforge/reference/delegated-task.md \
  plugins/dforge/skills/subagent-driven-development/references/escalation.md \
  plugins/dforge/skills/subagent-driven-development/references/re-review-prompt.md \
  plugins/dforge/skills/subagent-driven-development/references/ruling-prompt.md \
  plugins/dforge/reference/executor-lane.md plugins/dforge/reference/ladder.md \
  plugins/dforge/skills/subagent-driven-development/SKILL.md plugins/dforge/skills/executing-plans/SKILL.md \
  plugins/dforge/tests/task-step.test.sh plugins/dforge/tests/task-step-text.test.sh
git commit -m "feat(dforge): cap the fix loop at two rounds"
```

### Task 8: Run the wave check on a cadence

**Files:**
- Modify: `plugins/dforge/scripts/wave` (new `check-due` subcommand, the header's Usage, `usage()`)
- Modify: `plugins/dforge/scripts/plan-lint` (the `# --- parallel waves` block)
- Modify: `plugins/dforge/reference/parallel-waves.md` (The invariant, The ledger lines, §1 Open the wave, §4 the overlap bullet, §5 Integrate, Recovery, Common rationalizations, a new In-flight runs section)
- Modify: `plugins/dforge/skills/writing-plans/SKILL.md` (the header template, Parallel waves rule 7)
- Modify: `plugins/dforge/skills/subagent-driven-development/SKILL.md` (After compaction step 2, The Ledger grammar and its notes)
- Test: `plugins/dforge/tests/wave.test.sh`
- Test: `plugins/dforge/tests/plan-lint.test.sh`
- Test: `plugins/dforge/tests/next-step.test.sh`
- Test: `plugins/dforge/tests/task-step-text.test.sh`

**Interfaces:**
- Consumes: Contracts "Fix loop (Task 7)" (`Wave <k>: fix round R/2`, the `R/5` mapping, `task-step rereview` exit 7); `scripts/suite-run`'s digest; `plan_waves`, `plan_scores`, `plan_header`, `plan_apply_amendments` in `scripts/lib/plan.sh`.
- Produces: Contracts "Waves (Task 8)": the `**Wave check:**` header line, `scripts/wave check-due PLAN_FILE K`, the `merged` and `integrated` ledger lines, `<workspace>/base-proof-failures.txt`.

**Items:** 2

**Implementer:** dforge:impl-opus-high
**Evaluation:** files 2 - spec 2 - coupling 1 - risk 2 = 7
**Override:** owner approved the contract-and-test task shape for this plan on 2026-10-26, before plan-lint's Rule S and assignment table allow it

- [ ] **Step 1: Write the failing tests**

In `plugins/dforge/tests/wave.test.sh`, insert above the final `printf '\n%d passed, %d failed\n' "$pass" "$fail"` line (the checkout is in `$REPO` there, and `$TMP/seq.md` and `$TMP/bad.md` exist from the list cases):

```bash
# --- check-due: which check closes wave K ---
# Fixture lines carry a leading | so a plan that quotes this suite still lints.
sed 's/^|//' > docs/cadence.md <<'PLAN'
|# Cadence Plan
|
|**Execution:** subagent — `claude --model sonnet --effort high` — waves
|
|**Parallelism:** waves — 1 | 2-3 | 4 | 5 | 6-7 | 8 | 9
|
|**Integration check:** `bash full.sh`
|
|**Worktree setup:** none
|
|**Wave check:** `bash quick.sh`
|
|### Task 1: One
|**Evaluation:** files 0 - spec 0 - coupling 0 - risk 0 = 0
|### Task 2: Two
|**Evaluation:** files 0 - spec 0 - coupling 0 - risk 1 = 1
|### Task 3: Three
|**Evaluation:** files 0 - spec 0 - coupling 0 - risk 2 = 2
|### Task 4: Four
|**Evaluation:** files 0 - spec 0 - coupling 0 - risk 0 = 0
|### Task 5: Five
|**Evaluation:** files 0 - spec 0 - coupling 1 - risk 3 = 4
|### Task 6: Six
|**Evaluation:** files 0 - spec 0 - coupling 0 - risk 0 = 0
|### Task 7: Seven
|**Evaluation:** files 0 - spec 0 - coupling 0 - risk 0 = 0
|### Task 8: Eight
|**Evaluation:** files 0 - spec 0 - coupling 0 - risk 0 = 0
|### Task 9: Nine
|**Evaluation:** files 0 - spec 0 - coupling 0 - risk 0 = 0
PLAN
grep -v '^\*\*Wave check:\*\*' docs/cadence.md > docs/cadence-nocheck.md
git add docs/cadence.md docs/cadence-nocheck.md && git commit -qm "docs: cadence fixtures"
due() { out=$(HOME="$TMP/home" bash "$WAVE" check-due "$@" 2>&1); status=$?; }
got="" got_status=""
for k in 1 2 3 4 5 6 7; do due docs/cadence.md "$k"; got="$got$out "; got_status="$got_status$status"; done
check "check-due: every third wave, a risk-3 wave and the last run the full check" "$got" "wave-check wave-check full full wave-check full full "
check "check-due: exits 0 for every wave" "$got_status" "0000000"
got=""
for k in 1 2 3 4 5 6 7; do due docs/cadence-nocheck.md "$k"; got="$got$out "; done
check "check-due: without a Wave check line the other waves run none" "$got" "none none full full none full full "
due docs/cadence.md 8
check "check-due: a wave past the last exits 2" "$status" "2"
due docs/cadence.md 0
check "check-due: wave 0 exits 2" "$status" "2"
due docs/cadence.md two
check "check-due: a wave that is not a number exits 2" "$status" "2"
due docs/cadence.md
check "check-due: no wave exits 2" "$status" "2"
due docs/plan.md 1
check "check-due: a one-task first wave of two runs the wave check or none" "$out" "none"
due docs/plan.md 2
check "check-due: the last wave runs the full check" "$out" "full"
due "$TMP/seq.md" 1
check "check-due: a sequential plan exits 2" "$status" "2"
due "$TMP/bad.md" 1
check "check-due: waves that do not parse exit 4" "$status" "4"
# A Header amendment adds a Wave check line without editing the plan file.
WS_C=$(HOME="$TMP/home" bash "$HERE/../scripts/sdd-workspace" docs/cadence-nocheck.md | tr -d '\r')
printf '%s\n' '## A1 — Header' 'Reason: a faster check between full checks' 'Cost if wrong: one wave check' \
  '### Old' '````text' '**Worktree setup:** none' '````' \
  '### New' '````text' '**Worktree setup:** none' '' '**Wave check:** `bash quick.sh`' '````' > "$WS_C/amendments.md"
due docs/cadence-nocheck.md 1
check "check-due: reads a Wave check line an amendment adds" "$out" "wave-check"
check "check-due: the plan file itself is unchanged" "$(grep -c '^\*\*Wave check:\*\*' docs/cadence-nocheck.md)" "0"

```

In `plugins/dforge/tests/plan-lint.test.sh`, insert directly after the line `has "waves: the integration check is required" "$out" "ERROR header: a waves plan needs its **Integration check:** line"`:

```bash
# An optional **Wave check:** line runs between the full checks of a waves plan.
with_wave_check() { # with_wave_check <line> — stdin plan with <line> after the Worktree setup line
  awk -v l="$1" '{ print } /^\*\*Worktree setup:\*\*/ { print ""; print l }'
}
waves_plan 'waves — 1 | 2-3' | with_wave_check '**Wave check:** `bash quick.sh`' > waves-check.md
lint waves-check.md --no-probe
check "waves: a Wave check line is accepted" "$out" "plan-lint: 0 errors, 0 warnings"
waves_plan 'waves — 1 | 2-3' | with_wave_check '**Wave check:**' > waves-check-empty.md
lint waves-check-empty.md --no-probe
has "waves: a Wave check line needs a command" "$out" "ERROR header: the **Wave check:** line names no command"
waves_plan 'sequential — one chain' | with_wave_check '**Wave check:** `bash quick.sh`' > seq-check.md
lint seq-check.md --no-probe
has "sequential: a Wave check line is flagged" "$out" "WARN header: **Wave check:** runs only between the waves of a waves plan"
lacks "sequential: a Wave check line is not an error" "$out" "ERROR header: the **Wave check:**"
```

In `plugins/dforge/tests/next-step.test.sh`, insert directly after the line `lacks "inline assigned: no warning, the controller is the implementer" "$(cat "$TMP/stderr")" "warning"`:

```bash

# --- a waves ledger: the lines that close a wave are not task lines ---
ledger 'Wave 1: started (base aaaaaaa; Tasks 1-2; at most 2 at once)' \
       'Task 1: complete (commits a..b, review clean; merged bbbbbbb)' \
       'Task 2: complete (commits a..c, review clean; merged ccccccc)' \
       'Wave 1: merged (head ccccccc; check at wave 3)'
run "$REPO" "$PLAN_REL"
check "wave merged: exits 0" "$status" "0"
has "wave merged: counts the complete tasks" "$out" "2 of 3 tasks complete"
has "wave merged: resumes at the next wave's task" "$out" "**Next:** Resume at Task 3 (Third thing)."
lacks "wave merged: no warning" "$(cat "$TMP/stderr")" "warning"
ledger 'Task 1: complete (commits a..b, review clean)' \
       'Task 2: complete (commits b..c, review clean)' \
       'Wave 2: fix round 1/2 (1 addressed, 0 open — x; commits c..d; fresh (wave))' \
       'Wave 2: integrated (head ddddddd; bash full.sh → pass; baseline failures only)'
run "$REPO" "$PLAN_REL"
has "wave integrated on a red baseline: counts the complete tasks" "$out" "2 of 3 tasks complete"
lacks "wave integrated on a red baseline: no warning" "$(cat "$TMP/stderr")" "warning"
```

In `plugins/dforge/tests/task-step-text.test.sh`, insert above the final `printf '\n%d passed, %d failed\n' "$pass" "$fail"` line, after Task 7's block (it uses Task 7's `only_older`):

```bash
# --- the wave check cadence (faster-plans §4) ---
WP="$P/skills/writing-plans/SKILL.md"
names "waves ask check-due which check closes a wave" "$PW" '`bash <plugin-root>/scripts/wave check-due PLAN_FILE <k>`'
names "every wave closes" "$PW" 'Every wave closes with an `integrated` or a `merged` line, one-task and serialized waves included.'
names "the merged line" "$PW" 'Wave <k>: merged (head <sha7>; check at wave <m>)'
names "the integrated line may be baseline-only" "$PW" 'Wave <k>: integrated (head <sha7>; <command> → pass[; baseline failures only])'
names "a wave opens once every earlier wave is closed" "$PW" 'every earlier wave closed by its `integrated` or `merged` line'
names "an ancestor with no task commits between proves the base" "$PW" 'or an ancestor of `HEAD` with no task commits between'
names "a task commit outside any wave forces the fallback proof" "$PW" 'Only a task commit outside any wave forces the fallback proof'
names "the base proof records its failures" "$PW" '`<workspace>/base-proof-failures.txt`'
names "a new failure hands over every diff since the last pass" "$PW" 'every task diff since the last passing check'
names "no in-flight run is exempt" "$PW" 'None is exempt.'
names "an earlier cadence ruling is superseded" "$PW" 'is superseded by this cadence and the red-baseline rule'
names "an overlap round counts toward two rounds" "$PW" 'It counts toward the two rounds.'
names "recovery: a wave in flight has no closing line" "$PW" 'A `Wave <k>: started` line with no later `Wave <k>: integrated` or `Wave <k>: merged` line'
lacks "a one-task wave is no longer line-free" "$PW" 'with no Wave lines, no worktree and no merge'
lacks "waves no longer count five rounds" "$PW" 'It counts toward the five'
only_older "waves name R/5 only for older runs" "$PW"
names "writing-plans: the optional Wave check header line" "$WP" '**Wave check:** [waves only, optional:'
names "writing-plans: the waves rule names the Wave check" "$WP" '`**Wave check:**`, optional, names a faster command'
names "subagent mode: the merged grammar" "$SDD" 'Wave <k>: merged (head <sha7>; check at wave <m>)'
names "subagent mode: the integrated grammar" "$SDD" 'Wave <k>: integrated (head <sha7>; <command> → pass[; baseline failures only])'
names "subagent mode: compaction reads a merged line as closed" "$SDD" 'A `Wave <k>: started` line with no later `integrated` or `merged` line'
names "subagent mode: recovery reads merged as closed" "$SDD" '`Wave <k>: merged` closes the wave as `integrated` does'
lacks "subagent mode: the old integrated grammar is gone" "$SDD" 'Wave <k>: integrated (head <sha7>; <command> → pass)'

```

- [ ] **Step 2: Run them to verify they fail**

Run: `timeout 120 bash plugins/dforge/tests/wave.test.sh; timeout 600 bash plugins/dforge/tests/plan-lint.test.sh; timeout 300 bash plugins/dforge/tests/next-step.test.sh; timeout 120 bash plugins/dforge/tests/task-step-text.test.sh`
Expected: FAIL — wave.test.sh: 7 checks (`check-due` is not a subcommand, so every call prints the usage line and exits 2: the two cadence checks, the exit-0 check, the two plan.md checks, the amendment check, and "waves that do not parse exit 4"); the other exit-2 checks and "the plan file itself is unchanged" pass already. plan-lint.test.sh: 2 checks ("needs a command", "is flagged"); "is accepted" and "is not an error" pass already, since plan-lint ignores the line today. next-step.test.sh: all 6 new checks pass already — they pin that `next-step` reads `merged` and `integrated` lines as non-task lines, so it needs no change. task-step-text.test.sh: the 23 new checks fail. Seen on the tree this plan starts from.

- [ ] **Step 3: Implement**

Each quoted phrase in the tests is a constant: write it verbatim on a single physical line. A line naming a `round R/5` must carry `older` on the same line. `tests/task-step-text.test.sh` counts `scripts/suite-run -- bash -c` in parallel-waves.md and expects exactly 2: keep today's two (§1's base proof, §5's check) and say "through `suite-run` the same way" anywhere else. Keep the phrases `auto-run-skills.test.sh` pins in §4 (`` `; merged <sha7>`. In an auto run, run `scripts/auto-run task-complete` `` and "right after it, before any budget check or dispatch; the Fable batch runs"). Never start a prose line outside a fence with `**Wave check:**`: plan-lint reads label lines.

1. **`scripts/wave check-due PLAN_FILE K`.** Add the subcommand to the header's Usage block (`wave check-due PLAN_FILE K   which check closes wave K: full, wave-check or none`) and to `usage()`.
   - Exactly one argument after the plan, a number of at least 1; otherwise `usage` (exit 2).
   - Read the plan with its amendments applied: `plan_apply_amendments "$plan" "$(plan_amendments_file "$plan")"` into a temporary file removed on every exit; when an amendment does not apply, `die 2 "an amendment does not apply; run plan-lint"`.
   - On that copy: `plan_parallelism` `bad` exits 4 with the `list` message; `sequential` exits 2 (`the plan has no waves **Parallelism:** line`); `plan_waves` failing exits 4; K beyond the last wave exits 2 (`the plan has no wave K`).
   - Print `full` when K is a multiple of 3, when K is the last wave, or when any task of wave K has risk `3` in `plan_scores`; else `wave-check` when the copy's header (`plan_header`, lines outside fences) holds a line starting `**Wave check:**` with a non-blank command after it; else `none`. One word, exit 0.
   - The other subcommands do not change.

2. **`scripts/plan-lint`**, in the `# --- parallel waves` block: take the first line of `unfenced_header` starting `**Wave check:**` (the header only, never a task body). On a waves plan, when nothing but blanks follows the label, `say ERROR header "the **Wave check:** line names no command"`. On a sequential plan, any such line gives `say WARN header "**Wave check:** runs only between the waves of a waves plan; this plan is sequential"`. A waves plan with a command gets no finding. Nothing else changes.

3. **`reference/parallel-waves.md`.**
   - The invariant: "A wave of one task is an ordinary task: the task loop runs it in the checkout, with no `started` line, no worktree and no merge, and it closes by §5 like any wave." Add `Every wave closes with an \`integrated\` or a \`merged\` line, one-task and serialized waves included.` The serialize bullet "the integration check fails on the wave's base (§1)" becomes "the base proof fails on a failure the baseline does not hold (§1)". The closing paragraph ends "and the wave still closes by §5 once they are all complete."
   - The ledger lines: intro "gains these lines (`started` only for a wave of more than one task):"; the block holds `started`, `serialized`, `check failed`, `Wave <k>: fix round R/2 (<the fields of a task's fix round>)`, `Wave <k>: merged (head <sha7>; check at wave <m>)` and `Wave <k>: integrated (head <sha7>; <command> → pass[; baseline failures only])`. `<m>` is the next wave `wave check-due` prints `full` for; `merged` closes a wave as `integrated` does.
   - §1, the boundary: "At a wave boundary — every earlier task complete and every earlier wave closed by its `integrated` or `merged` line". A ledger written before this rule may hold earlier waves with no closing line: a wave whose tasks are all complete counts as closed, and the base proof below then finds task commits after the last closing line.
   - §1 step 2, **Prove the base.** The last `Wave <j>: integrated` or `Wave <j>: merged` line proves the base when its head is `HEAD`, or an ancestor of `HEAD` with no task commits between: `git merge-base --is-ancestor <sha7> HEAD` holds and every commit `git log --format='%h %s' <sha7>..HEAD` lists is your own bookkeeping (the ledger, amendments, a register or the roadmap; no path any task's `**Files:**` names). Then nothing reruns. `Only a task commit outside any wave forces the fallback proof`: the header's Wave check (amendments applied) when it has one, else the full Integration check, after the Worktree setup, through today's `bash <plugin-root>/scripts/suite-run -- bash -c '<the check>'`, in the background when it can outrun Bash's ten-minute cap. With no closing line yet (the first wave), the proof is the full check. A proof that ran the full check writes `<workspace>/base-proof-failures.txt` (`<workspace>` is what `scripts/sdd-workspace PLAN_FILE` prints): the digest's failing-test lines, one per line, exactly as `suite-run` prints them; when its `counts:` line names more than 20 failures, every matching line of the log it names, `grep -E '^[[:space:]]*(not ok|\(fail\)|FAIL)' <log> | cut -c1-200`; empty on a pass. A failing proof whose failures all appear in the file the previous proof wrote is the known red baseline: log a `Ruling:` naming the count and open the wave. Any other failure, including a digest that shows `last 30 lines of <log>:` (it names no test), serializes the wave as today, with the digest's summary in the Ruling.
   - §1 for a one-task wave: run step 2 only, then the task loop in the checkout.
   - §4, the overlap bullet: `Task <N>: fix round R/2 (rebased on <sha7>: overlap <files>; …; fresh (overlap))`, and `It counts toward the two rounds.` Past round 2 the overlap goes to the breaker like any open finding (`task-step rereview` exits 7 there).
   - §5, renamed "Close the wave": (1) multi-task waves only, `scripts/wave clean` as today; (2) run `bash <plugin-root>/scripts/wave check-due PLAN_FILE <k>`; (3) `full` runs the Worktree setup and Integration check through today's suite-run command, `wave-check` runs the header's Wave check through `suite-run` the same way, `none` runs nothing; (4) a pass logs `Wave <k>: integrated (head <sha7>; <command> → pass)` after a full check, and `Wave <k>: merged (head <sha7>; check at wave <m>)` after a Wave check or none; (5) red baseline: a failing check whose failing lines, taken as in §1, all appear in `base-proof-failures.txt` counts as passing — `…; baseline failures only])` on an integrated line, an ordinary merged line after a Wave check. Compare with TAP numbers removed on both sides (`sed -E 's/^([[:space:]]*not ok) [0-9]+/\1/'`); the failures are a subset when `grep -vxFf <baseline> <current>` prints nothing; (6) any other failure logs `Wave <k>: check failed — <command> → <summary>` and runs the wave's fix loop as today (delegated-task.md §4, by-hand re-review, the check rerun through `suite-run` after each round, `Wave <k>: fix round R/2 (…)`, at the cap a `breaker` item against the wave's last task), except that the fix dispatch gets every task diff since the last passing check — the last passing check is the last `Wave <j>: integrated` line: the diff `bash <plugin-root>/scripts/review-package PLAN_FILE <its head> HEAD` writes (the first wave's base when there is none) and the brief and report of every task merged since — and the implementer is the highest-ranked `**Implementer:**` agent among those tasks.
   - New section `## In-flight runs`, before Recovery: `None is exempt.` A run whose ledger holds an earlier cadence ruling (a full check only every tenth wave because the baseline was red, say) follows this cadence from its next wave boundary once the installed plugin carries it; the earlier ruling `is superseded by this cadence and the red-baseline rule`, and you log one `Ruling:` line saying so. A plan without a Wave check line runs the full check on this cadence and nothing between; a Header AMEND in `amendments.md` can add one without editing the plan file.
   - Recovery: `A \`Wave <k>: started\` line with no later \`Wave <k>: integrated\` or \`Wave <k>: merged\` line` is a wave in flight (a serialized wave included); a wave whose tasks are all complete and has no closing line continues at §5. Add: "An older run's `Wave <k>: fix round R/5` line: R = 1 resumes at round 2, R >= 2 goes to the breaker."
   - Common rationalizations, the "integration check is slow" row: the reality names `wave check-due` as the one that decides when the full check runs.

4. **writing-plans `SKILL.md`.** In the header template, after the Worktree setup line: `**Wave check:** [waves only, optional: a faster command — a build and the fast unit suite, say — run after the waves the full check skips; omit the line when there is none]`. Parallel waves rule 7 becomes "Write the header lines." and adds a sentence with `` `**Wave check:**`, optional, names a faster command `` run after the waves `scripts/wave check-due` does not give the full check — the full Integration check runs after every third wave, any wave holding a risk-3 task and the last wave; without a Wave check those waves rest on each task's own tests and a clean merge.

5. **subagent-driven-development `SKILL.md`.** After compaction step 2: `A \`Wave <k>: started\` line with no later \`integrated\` or \`merged\` line` is a parallel wave in flight. The Ledger grammar: replace the integrated line with `Wave <k>: integrated (head <sha7>; <command> → pass[; baseline failures only])` and add `Wave <k>: merged (head <sha7>; check at wave <m>)` after it. In the notes, the bullet on `Wave` lines adds `` `Wave <k>: merged` closes the wave as `integrated` does `` : the next wave starts on it, and its head proves that wave's base (parallel-waves.md §1).

6. **`scripts/next-step`** does not change: it reads no Wave line, and the new next-step cases pin that.

- [ ] **Step 4: Run the suites**

Run:
```bash
timeout 120 bash plugins/dforge/tests/wave.test.sh
timeout 600 bash plugins/dforge/tests/plan-lint.test.sh
timeout 300 bash plugins/dforge/tests/next-step.test.sh
timeout 120 bash plugins/dforge/tests/task-step-text.test.sh
for t in auto-run-skills parallel-grouping auto-default settings-skills process-roles inline-mode; do
  env -u CLAUDE_CONFIG_DIR timeout 300 bash "plugins/dforge/tests/$t.test.sh" | tail -n 1
done
node scripts/validate-repository.mjs
timeout 120 /root/.local/bin/claude plugin validate plugins/dforge
```
Expected: PASS — every suite ends `0 failed`; both validators pass.

- [ ] **Step 5: Commit**
```bash
git add plugins/dforge/scripts/wave plugins/dforge/scripts/plan-lint plugins/dforge/reference/parallel-waves.md \
  plugins/dforge/skills/writing-plans/SKILL.md plugins/dforge/skills/subagent-driven-development/SKILL.md \
  plugins/dforge/tests/wave.test.sh plugins/dforge/tests/plan-lint.test.sh \
  plugins/dforge/tests/next-step.test.sh plugins/dforge/tests/task-step-text.test.sh
git commit -m "feat(dforge): run the wave check on a cadence"
```

### Task 9: Judge agents and task-loop report files

**Files:**
- Modify: `plugins/dforge/agents/judge-opus.md`, `plugins/dforge/agents/judge-sonnet-high.md`, `plugins/dforge/agents/judge-fable.md` (frontmatter `tools:` and `description:`, the "You cannot modify files" paragraph)
- Modify: `plugins/dforge/skills/subagent-driven-development/references/task-reviewer-prompt.md` (The Implementer's report line, Part 1's cannot-verify sentence, Part 2's closing paragraph, `## Output Format`, `## Criteria`, `## Second Pass: The Codex Review`, Placeholders, Reviewer returns)
- Modify: `plugins/dforge/skills/subagent-driven-development/references/re-review-prompt.md` (The Fix, Scope, `## Output Format` to the end of the fence, Placeholders, Re-reviewer returns)
- Modify: `plugins/dforge/skills/subagent-driven-development/references/group-reviewer-prompt.md` (created by Task 5: its output instructions and Placeholders)
- Modify: `plugins/dforge/skills/subagent-driven-development/references/ruling-prompt.md` (the read-only sentence, `## Verdicts`, the AMEND bullet, the preflight kind, Placeholders, The seat returns)
- Modify: `plugins/dforge/reference/final-review.md` (§Fixing what it finds: the two sentences that fill the re-review's `[REPORT_FILE]`)
- Modify: `plugins/dforge/scripts/task-step` (`do_review`'s two `fill` calls, `cmd_rereview`'s `rr_render` and its leftover-placeholder check, the `review --group` fill Task 5 added)
- Test: `plugins/dforge/tests/fleet.test.sh`, `plugins/dforge/tests/seats.test.sh`, `plugins/dforge/tests/task-step.test.sh`

**Interfaces:**
- Consumes: Group review (Task 5) — `task-step hold`, `task-step review --group`, the group template and its `[REPORT_FILE]` placeholder
- Produces: Judge reports (Task 9) — the agents' `Write` tool, `[REPORT_FILE]` and the reply rule in the task-loop templates, the report grammar, the report files `task-<N>-review-report.md`, `task-<N>-rereview-<R>-report.md`, `group-<list>-review-report.md`, `rulings-<point>-<task>-report.md`

**Items:** 3

**Implementer:** dforge:impl-opus-high
**Evaluation:** files 2 - spec 2 - coupling 1 - risk 2 = 7
**Override:** owner approved the contract-and-test task shape for this plan on 2026-10-26, before plan-lint's Rule S and assignment table allow it

Decisions this task embodies:
- `[REPORT_FILE]` already means the implementer's report in the task-reviewer and re-review templates, and `task-step` fills it so. The Contract gives the name to the judge's own report, so the implementer's report becomes `[IMPLEMENTER_REPORT_FILE]`, and `task-step review` and `rereview` fill both in this task: a template change without the fill change would make `task-step` die on an unexpanded placeholder.
- The report-file rule lives inside each template's `## Output Format` section. `task-step review` drops that section from the Codex prompt, so a Codex seat (whose output is JSON through `--out`) never receives it.
- Example report skeletons inside a fenced template are indented four spaces deeper than the prompt body. `task-step`'s `drop_sections` treats any de-indented line starting `## ` as a section heading; an unindented `## Verdict` inside `## Output Format` would end the dropped section early and leak the skeleton into the Codex prompt.
- A ruling report numbers its AMEND entries within the report (`## A1 — Task 4`, `## A2 — Header`), and each AMEND item names its entry on an `Amendment: A<k>` line, so Task 10's `plan-amend --report --id A<k>` can find one. `plan-amend` still assigns the amendment's own number in `amendments.md`.
- A review step removes a report file left at the path its prompt names, so a seat that writes nothing is seen as missing (Task 10's exit 5), never as last round's report.
- The judges keep no `Edit`, `Bash` or `Agent`; the scout gains nothing.

- [ ] **Step 1: Write the failing tests**

In `plugins/dforge/tests/fleet.test.sh`, replace the header comment's sentence that begins `Four role agents - three judges and one scout - are` (through `are enforced rather than requested.`) with:

```bash
# already been spent. Four role agents - three judges and one scout - never
# carry Edit, NotebookEdit, Bash or Agent, so "reviewers do not spawn
# subagents" is enforced rather than requested. A judge carries Write for one
# file, the report its prompt names; task-step verdict checks that no tracked
# file changed during the review. The scout carries no Write at all.
```

replace the line `ROLE_TOOLS="Read, Grep, Glob, WebFetch"` with:

```bash
JUDGE_TOOLS="Read, Grep, Glob, WebFetch, Write"
SCOUT_TOOLS="Read, Grep, Glob, WebFetch"
```

and replace the whole `judge-*|scout-*)` case arm (through its `;;`) with:

```bash
    judge-*|scout-*)
      # The absent tools are the point: no Edit, no Bash, no Agent. A judge's
      # one Write is its report file; the scout writes nothing.
      case "$base" in
        judge-*)
          check "$base: carries the judge toolset" "$(fm "$f" tools)" "$JUDGE_TOOLS"
          check "$base: writes only the report file" "$(grep -c 'write only the report file' "$f")" "1"
          check "$base: no longer says it cannot modify files" "$(grep -c 'You cannot modify files' "$f")" "0"
          check "$base: its reply is not its whole verdict" "$(grep -c 'Your verdict is the whole of your output' "$f")" "0"
          check "$base: the description does not call it read-only" "$(fm "$f" description | grep -c 'Read-only')" "0"
          ;;
        *)
          check "$base: carries the read-only toolset" "$(fm "$f" tools)" "$SCOUT_TOOLS"
          ;;
      esac
      check "$base: effort is high or medium" \
        "$(case "$effort" in high|medium) echo ok ;; *) echo "invalid:$effort" ;; esac)" "ok"
      check "$base: preloads no skills" "$(grep -c '^skills:' "$f")" "0"
      ;;
```

`fleet.test.sh` must read nothing outside `agents/`: `typed-seats-and-drafting.acceptance.sh` A10 runs it on a copy holding only `agents/` and `tests/fleet.test.sh`. The template checks therefore go in `seats.test.sh`. Insert this block in `plugins/dforge/tests/seats.test.sh` directly before its final `printf '\n%d passed, %d failed\n'` line:

```bash
# Judge seats in the task loop write their full report to the file the prompt
# names and reply in at most ten lines. The report opens with a fixed
# `## Verdict` section and lists findings in one grammar, so task-step verdict
# can read it and the controller never has to.
lacks() { # lacks <label> <file> <text>
  check "$1" "$(grep -qF -- "$3" "$2" 2>/dev/null && echo yes || echo no)" "no"
}
TRP="$P/skills/subagent-driven-development/references/task-reviewer-prompt.md"
GRP="$P/skills/subagent-driven-development/references/group-reviewer-prompt.md"
RULP="$P/skills/subagent-driven-development/references/ruling-prompt.md"
FR="$P/reference/final-review.md"
for t in "$TRP" "$RRP" "$GRP" "$RULP"; do
  n=$(basename "$t" .md)
  names "$n: names the report file" "$t" 'Write your full report to [REPORT_FILE] and write nothing else'
  names "$n: the reply is at most 10 lines" "$t" 'Then reply in at most 10 lines'
  check "$n: the report opens with the Verdict section" "$(grep -qE '^ *## Verdict$' "$t" 2>/dev/null && echo yes || echo no)" "yes"
  names "$n: the report file is a placeholder" "$t" '`[REPORT_FILE]` — REQUIRED'
  lacks "$n: the final message is no longer the report" "$t" 'Your final message is the report itself'
  lacks "$n: the seat no longer says it cannot modify files" "$t" 'You cannot modify files'
done
for t in "$TRP" "$RRP"; do
  n=$(basename "$t" .md)
  names "$n: the finding grammar" "$t" '- [Critical|Important|Minor] <file>:<line> — <one-liner>'
  names "$n: the implementer's report has its own placeholder" "$t" '[IMPLEMENTER_REPORT_FILE]'
done
names "task reviewer: the spec verdict key" "$TRP" 'spec: pass | fail | cannot-verify'
names "task reviewer: the quality verdict key" "$TRP" 'quality: approved | changes'
names "task reviewer: the scores key" "$TRP" 'scores: spec <1-20> / scope <1-20> / verification <1-20> / quality <1-20>'
names "task reviewer: the cannot-verify section" "$TRP" '## Cannot verify'
check "task reviewer: the Codex findings are a report section" "$(grep -qE '^ *## Codex findings$' "$TRP" && echo yes || echo no)" "yes"
lacks "task reviewer: no Verification Scores block" "$TRP" '### Verification Scores'
names "re-review: the round verdict key" "$RRP" 'fix round: addressed | open'
names "re-review: the open count key" "$RRP" 'open: <k>'
names "re-review: the per-finding verdicts" "$RRP" '## Finding verdicts'
names "group reviewer: the per-task finding grammar" "$GRP" '- [Critical|Important|Minor] (Task <N>) <file>:<line> — <one-liner>'
names "group reviewer: per-task verdict keys" "$GRP" 'Task <N> spec: pass | fail | cannot-verify'
names "group reviewer: per-task scores" "$GRP" 'Task <N> scores: spec <1-20> / scope <1-20> / verification <1-20> / quality <1-20>'
names "ruling: the item verdict lines" "$RULP" 'Verdict: CONFIRMED-GAP | PARK | AMEND | REWORD | BLOCKED'
names "ruling: an AMEND names its entry" "$RULP" 'Amendment: A<k>'
names "ruling: entries are numbered in the report" "$RULP" '## A<k> — Task <N>'
names "ruling: a BLOCKED reply carries the decision" "$RULP" 'the decision a human must make'
names "ruling: the report file follows the items file" "$RULP" '`<workspace>/rulings-<point>-<task>-report.md`'
lacks "ruling: no unnumbered entry heading" "$RULP" '## A? — Task <N>'
names "final review: the fix wave's re-review names the fixer's report" "$FR" 'its `[IMPLEMENTER_REPORT_FILE]` being that file'
lacks "final review: the re-review's REPORT_FILE is not the fixer's" "$FR" 'its `[REPORT_FILE]` being that file'
```

In `plugins/dforge/tests/task-step.test.sh`, insert this block directly before the line `# --- rereview: the skip rule, the package and the state ---`:

```bash
# review: the judge writes its report where the prompt says, and a fresh
# review discards the last one; the Codex seat gets no report-file rule.
review_surface absent
printf 'stale\n' > "$WS/task-2-review-report.md"
step review docs/plan.md 2
RP2="$WS/task-2-review-prompt.md"
check "review report: exit 0" "$rc" "0"
check "review report: the prompt names the report file" \
  "$(grep -cF "Write your full report to $WS/task-2-review-report.md and write nothing else" "$RP2")" "1"
check "review report: the implementer's report keeps its own line" "$(grep -cF "Read the implementer's report: $WS/task-2-report.md" "$RP2")" "1"
check "review report: no placeholder is left" "$(placeholders "$RP2")" "0"
check "review report: a fresh review discards the last report" "$([ -e "$WS/task-2-review-report.md" ] && echo yes || echo no)" "no"
review_surface true
step review docs/plan.md 1
check "review report: the Codex prompt carries no report-file rule" \
  "$(grep -c 'review-report.md\|write nothing else' "$WS/task-1-review-codex-prompt.md")" "0"
check "review report: the Codex prompt keeps the implementer's report" \
  "$(grep -cF "Read the implementer's report: $WS/task-1-report.md" "$WS/task-1-review-codex-prompt.md")" "1"
review_surface absent
```

and this block directly before the suite's final `printf '\n%d passed, %d failed\n'` line:

```bash
# The re-review judge writes its report where the prompt says; a fresh round
# discards a stale one at that path.
rr_reset
rr_edit app.txt add4
rr_git add -A && rr_git commit -qm fix
rr_fix 1 1 "- app.txt: wrong value|- other.txt: stale"
printf 'stale\n' > "$RR_WS/task-1-rereview-1-report.md"
rr_run rereview docs/plan.md 1
RR_P=$RR_WS/task-1-rereview-1-prompt.md
check "rereview report: exit 0" "$rr_rc" "0"
check "rereview report: the prompt names the round's report file" \
  "$(grep -cF "Write your full report to $RR_WS/task-1-rereview-1-report.md and write nothing else" "$RR_P")" "1"
check "rereview report: the implementer's report is filled" "$(grep -cF "$RR_WS/task-1-report.md" "$RR_P")" "1"
check "rereview report: no implementer-report placeholder is left" "$(grep -c '\[IMPLEMENTER_REPORT_FILE\]' "$RR_P")" "0"
check "rereview report: a fresh round discards the stale report" "$([ -e "$RR_WS/task-1-rereview-1-report.md" ] && echo yes || echo no)" "no"

# A group review's judge writes one report for the group (Task 5's hold and
# review --group).
rr_reset
rr_run hold docs/plan.md 1
check "group report: hold 1" "$rr_rc" "0"
rr_run hold docs/plan.md 3
check "group report: hold 3" "$rr_rc" "0"
printf 'stale\n' > "$RR_WS/group-1,3-review-report.md"
rr_run review --group docs/plan.md 1 3
check "group report: review --group exits 0" "$rr_rc" "0"
check "group report: the prompt names the group report file" \
  "$(grep -cF "Write your full report to $RR_WS/group-1,3-review-report.md and write nothing else" "$RR_WS/group-1,3-review-prompt.md")" "1"
check "group report: a fresh group review discards the last report" "$([ -e "$RR_WS/group-1,3-review-report.md" ] && echo yes || echo no)" "no"
```

- [ ] **Step 2: Run them to verify they fail**

Run: `cd plugins/dforge && timeout 120 bash tests/fleet.test.sh; timeout 120 bash tests/seats.test.sh; timeout 600 bash tests/task-step.test.sh`
Expected: FAIL — fleet: 15 checks, five per judge (`carries the judge toolset`, `writes only the report file`, `no longer says it cannot modify files`, `its reply is not its whole verdict`, `the description does not call it read-only`). seats: every new template check except the keep checks (`ruling: the item verdict lines` and the `lacks` checks that already hold), since no template names a judge report file yet. task-step: `review report: the prompt names the report file`, `review report: a fresh review discards the last report`, `rereview report: the prompt names the round's report file`, `rereview report: a fresh round discards the stale report`, and the five `group report:` checks. On the plan's tree, where Task 5 has added `hold` and `review --group`, those five fail on the report-file lines; on a tree without Task 5 they fail earlier, at `hold`. The `rereview report: the implementer's report is filled` and `no implementer-report placeholder is left` checks already pass and guard the rename.

- [ ] **Step 3: Implement**

1. **Agents.** In each of the three judge agent files:
   - `tools:` becomes exactly `Read, Grep, Glob, WebFetch, Write`.
   - `description:`: judge-opus's `Read-only verifier, ruling seat and approach ranker running Opus 5.5 at medium effort.` becomes `Verifier, ruling seat and approach ranker running Opus 5.5 at medium effort; it writes only its report file.`; judge-fable's `Read-only verifier and ruling seat running Fable 5.1 at high effort.` becomes `Verifier and ruling seat running Fable 5.1 at high effort; it writes only its report file.`; judge-sonnet-high's `Read-only task reviewer running Sonnet 5.5 at high effort.` becomes `Task reviewer running Sonnet 5.5 at high effort; it writes only its report file.` The rest of each description stays byte for byte (`review-route.test.sh` pins `No dforge route names it`, `an auto run (reference/auto-run.md) dispatches it for the spec review and the batched rulings`, `totals 0 to 3`, `totals 4 to 6`).
   - Replace the paragraph `You cannot modify files and you cannot dispatch subagents. Both are deliberate. Your verdict is the whole of your output.` with this text, ASCII only (fleet.test.sh checks it), wrapped so that `write only the report file` stays on one line:

     ```text
     You write only the report file your dispatch prompt names, and you cannot
     dispatch subagents. Both are deliberate: a judge that edits the work it
     judges voids its review, and the controller checks after you return that
     no tracked file changed. The report file holds your full verdict; your
     final message is the short reply your prompt asks for.
     ```

2. **The wording every judge template carries.** Each phrase below must sit unbroken on one line of the file, because the tests grep for it: `Write your full report to [REPORT_FILE] and write nothing else`, `Then reply in at most 10 lines`, the finding grammar `- [Critical|Important|Minor] <file>:<line> — <one-liner>` (the em dash is U+2014), and each skeleton line shown below. Inside a fenced template the prompt body is indented four spaces; indent every report skeleton line eight.

3. **task-reviewer-prompt.md.**
   - `Read the implementer's report: [REPORT_FILE]` becomes `Read the implementer's report: [IMPLEMENTER_REPORT_FILE]` (task-step.test.sh pins the filled line `Read the implementer's report: <path>`).
   - Part 1: `report it as a ⚠️ item instead of broadening your search.` becomes `report it under Cannot verify instead of broadening your search.`
   - Part 2: delete the paragraph that begins `Your final message is the report itself: begin directly with the` (its content moves into Output Format). Keep `Your report should point at evidence: …`.
   - Replace the `## Output Format` section (from its heading up to, not including, `## Criteria`) with:

     ```text
         ## Output Format

         Write your full report to [REPORT_FILE] and write nothing else: it is
         the only file you may create or change. Then reply in at most 10 lines:
         the verdict, the scores, the count of findings by severity, and the
         report path. A script reads the report, so keep its grammar exactly.

         The report begins directly with its Verdict section; every line after
         it is a verdict, a finding with file:line, or a check you ran — no
         preamble, no process narration, no closing summary. Its shape, written
         without the indent:

             ## Verdict
             spec: pass | fail | cannot-verify
             quality: approved | changes
             scores: spec <1-20> / scope <1-20> / verification <1-20> / quality <1-20>

             ## Strengths
             <what is well done, specifically>

             ## Findings
             - [Critical|Important|Minor] <file>:<line> — <one-liner>
               <what is wrong, why it matters, how to fix it when not obvious>

             ## Cannot verify
             - <one-liner: the requirement, and what the controller should check>

             ## Assessment
             <one or two sentences of technical assessment>

         Give each verdict line one of the values shown. `spec: pass` means the
         diff meets the brief; `fail` that it misses, adds or misreads a
         requirement; `cannot-verify` that everything you could verify passes
         but a requirement lives in unchanged code or spans tasks. `quality:
         changes` means the task needs fixes before it can be trusted.

         Write one line per finding, most severe first, its detail on lines
         indented by two spaces below it. `<file>` is the repository path the
         fix belongs in and `<line>` the line, or 0 when no single line applies.
         Every missing, extra or misunderstood requirement is a finding at
         Critical or Important. A plan-mandated finding begins its one-liner
         with `plan-mandated: `. Leave a section with nothing in it empty under
         its heading.

         List at most three Minor issues, the ones most worth fixing, and end
         the section with `(<k> more Minor left out)` when you dropped any. Each
         Minor is carried to the final review's triage, which reads them all.
     ```

     (`process-roles.test.sh` pins `List at most three Minor issues, the ones most worth fixing` on one line.)
   - `## Criteria`: replace `Add this block to the end of your report, after the Assessment section:` and the `### Verification Scores` block of four `- <name>: <1-20>` lines with the one sentence `Put the four Verification Scores on the scores: line of your report's Verdict section.` Keep the rest of the section. Keep the Lens Criteria sentence `do not score them, and do not add them to Verification Scores` unchanged.
   - `## Second Pass: The Codex Review`: the paragraph becomes the text below. The line `review of the same diff: [CODEX_REVIEW_FILE]` must begin its own line (task-step.test.sh greps the filled line from its start), and `review raises a score, and nothing else you wrote before reading it changes.` stays on one line (review-route.test.sh):

     ```text
         Do this only after your Spec Compliance verdict, findings and
         Verification Scores are written in full. Then read the Codex
         review of the same diff: [CODEX_REVIEW_FILE]

         It is a JSON object; read its `findings` and `cannot_verify`. Append
         this section to your report file, as its last section:

             ## Codex findings
             - [CONFIRMED|REJECTED] <file:line> <the finding, one line> - <your evidence>
             - [CONFIRMED|REJECTED] cannot-verify: <the item, one line> - <your evidence>

         Write one line for every entry in `findings` and every entry in
         `cannot_verify`. CONFIRMED means the diff supports it. A CONFIRMED
         finding your Findings section missed is added there too, in the finding
         grammar, at your own severity and with `(from codex)` ending its
         one-liner; a CONFIRMED cannot-verify item is added under Cannot verify
         the same way. Either may lower a score you gave; nothing in the Codex
         review raises a score, and nothing else you wrote before reading it changes.
     ```
   - Placeholders: replace the `[REPORT_FILE]` entry with two entries: `` `[IMPLEMENTER_REPORT_FILE]` — REQUIRED: the file the implementer wrote its detailed report to `` and `` `[REPORT_FILE]` — REQUIRED: the file this judge writes its report to, `<workspace>/task-<N>-review-report.md`; `task-step review` fills both ``.
   - `**Reviewer returns:** …` becomes `**Reviewer writes** its report to [REPORT_FILE] — the Verdict section (spec, quality, scores), Strengths, Findings, Cannot verify and Assessment, with Codex findings last on a risk 3 task — **and returns** a reply of at most 10 lines.`

4. **re-review-prompt.md.**
   - The Fix: `Read the implementer's report (fix reports are appended at the end):` is followed by `[IMPLEMENTER_REPORT_FILE]` instead of `[REPORT_FILE]`.
   - Scope: `report it under Out-of-Scope Observations — it` becomes `report it as an out-of-scope Minor finding (Output Format) — it`. Keep `Your review is read-only on this checkout.` (seats.test.sh) and add no wording about falling back or a missing diff file (task-loop-steps A15 forbids it).
   - Replace everything from `## Output Format` to the closing fence of the prompt (this removes the old Finding Verdicts, New Breakage, Out-of-Scope Observations and Verdict subsections, and a Progress section if Task 7 left one) with:

     ```text
         ## Output Format

         Write your full report to [REPORT_FILE] and write nothing else: it is
         the only file you may create or change. Then reply in at most 10 lines:
         the verdict, the count of findings by severity, and the report path.
         A script reads the report, so keep its grammar exactly. Every line in
         it is a verdict, a finding with file:line, or a check you ran — no
         preamble, no process narration. Its shape, written without the indent:

             ## Verdict
             fix round: addressed | open
             open: <k>

             ## Finding verdicts
             - <finding one-liner> — ADDRESSED | NOT ADDRESSED — <file:line evidence>
             - <finding one-liner> — REJECTION UPHELD | REJECTION DISPUTED — <file:line evidence>

             ## Findings
             - [Critical|Important|Minor] <file>:<line> — <one-liner>

         `fix round: addressed` means every finding is addressed and the fix
         diff adds no Critical or Important breakage; otherwise it is `open`,
         and `open:` counts the findings still open.

         Write one Finding verdicts line for each finding in The Findings Under
         Verification, in order. "Attempted" is not addressed: the specific
         defect must no longer exist. Use the rejection form for a finding the
         fix report lists under `REJECTED:` (a final review with one findings
         list), and uphold only when the evidence shows the finding is wrong,
         not merely unfixed.
         An upheld rejection is closed; a disputed one is open.

         Under Findings, list every finding still open — each NOT ADDRESSED one
         and each disputed rejection, at the severity the fix message gives it
         — and anything the fix itself broke or introduced, at its own severity.
         An issue entirely outside the fix diff is a Minor finding whose
         one-liner begins `out of scope: `: the controller ledgers it for the
         final review and it never extends the loop. `<line>` is 0 when no
         single line applies. Leave a section with nothing in it empty under
         its heading.
     ```

     (`inline-mode.test.sh` pins `REJECTION UPHELD |` and `An upheld rejection is closed; a disputed one is open.` on one line each.)
   - Placeholders: `[FINDINGS]` becomes `the fix message's bullets, one per open finding; task-step rereview fills them in`; replace the `[REPORT_FILE]` entry with `` `[IMPLEMENTER_REPORT_FILE]` — the implementer's report file (fix reports appended) `` and `` `[REPORT_FILE]` — REQUIRED: the file this judge writes its report to, `<workspace>/task-<N>-rereview-<R>-report.md`; `task-step rereview` fills it, and the final review's fix wave names `<workspace>/final-rereview-report.md` ``.
   - `**Re-reviewer returns:** …` becomes `**Re-reviewer writes** the round verdict, a verdict per finding and every finding still open (new breakage included, out-of-scope issues as Minor) to [REPORT_FILE], **and returns** a reply of at most 10 lines.`

5. **group-reviewer-prompt.md** (Task 5 created it from the task-reviewer pattern; `task-step review --group` already fills its `[REPORT_FILE]` with `<workspace>/group-<list>-review-report.md`). Keep Task 5's six one-line sentences verbatim, since its task-step-text.test.sh checks grep them: `Read the package at [PACKAGE_FILE]: …`, `… Score each task on its own against it.`, the `**Lenses:**` sentence, `A finding in one task never fails another task: …`, `Return one block per task, headed ``### Task <N>``, in the package's order.` and `Every finding names its task: prefix its file with ``(Task <N>) ``, as in ``(Task 4) src/a.ts:12``.` Replace the rest of its Output Format (the per-task spec verdict, Issues, Task quality and `### Verification Scores` content, and the last paragraph saying the final message is the report) with the task reviewer's Output Format above, adapted as follows: the skeleton is the one below; the sentence before it says the three Verdict lines appear once for every task in `[GROUP_LIST]`, in that order, and that every finding and cannot-verify item begins with the `(Task <N>) ` of the task it is about; and the `### Task <N>` blocks Task 5's sentence asks for are the ones under `## Tasks`, each holding that task's strengths and assessment.

   ```text
           ## Verdict
           Task <N> spec: pass | fail | cannot-verify
           Task <N> quality: approved | changes
           Task <N> scores: spec <1-20> / scope <1-20> / verification <1-20> / quality <1-20>

           ## Findings
           - [Critical|Important|Minor] (Task <N>) <file>:<line> — <one-liner>
             <what is wrong, why it matters, how to fix it when not obvious>

           ## Cannot verify
           - (Task <N>) <one-liner: the requirement, and what the controller should check>

           ## Tasks

           ### Task <N>
           <what is well done, specifically; then one or two sentences of assessment>
   ```

   Its Placeholders entry becomes `` `[REPORT_FILE]` — REQUIRED: the file this judge writes its report to, `<workspace>/group-<list>-review-report.md`; `task-step review --group` fills it ``, and its **Reviewer returns** line says the judge writes the report there and returns a reply of at most 10 lines. The prompt may still name only `[GROUP_LIST]`, `[PACKAGE_FILE]`, `[REPORT_FILE]` and `[PLUGIN_ROOT]` (Task 5's check).

6. **ruling-prompt.md.**
   - `You cannot modify files or dispatch subagents.` becomes `You write only the report file and cannot dispatch subagents.`
   - Under `## Verdicts`, replace `Return exactly one block per item, in item order:` and the indented block after it with:

     ```text
         Write your full report to [REPORT_FILE] and write nothing else: it is
         the only file you may create or change. Then reply in at most 10 lines:
         the count of verdicts by kind and the report path; a BLOCKED verdict
         also puts the decision a human must make in your reply.

         The report opens with its Verdict section, exactly one block per item,
         in item order, written without the indent:

             ## Verdict

             ### Item <id>
             Verdict: CONFIRMED-GAP | PARK | AMEND | REWORD | BLOCKED
             Ruling: <what> — <why> — <cost if wrong>

         After the Verdict section come a preflight's table under
         `## Preflight table`, then every AMEND entry, in item order.
     ```
   - AMEND bullet: the sentence that begins `After the Ruling line, write one amendment entry, starting at column 0,` (through `for the header):`) becomes the text below, and the example entry's heading line becomes `## A<k> — Task <N>`. No `## A? — Task <N>` may remain. Keep the Old/New rules, REWORD (`REWORD: the spec statement is what is wrong` stays) and BLOCKED (`Decision needed:`) as they are.

     ```text
           After the Ruling line, write `Amendment: A<k>` at column 0,
           numbering this report's AMEND entries A1, A2 … in item order. Write
           the entry itself after the Verdict section, starting at column 0, in
           exactly this shape (heading `## A<k> — Task <N>`, or
           `## A<k> — Header` for the header):
     ```
   - preflight kind: `First return a table:` becomes `Write a table under ## Preflight table:`, and `Then one verdict block per row that found something, with id` becomes `Then one verdict block per row that found something, in the Verdict section, with id`.
   - Placeholders: add `` `[REPORT_FILE]` — REQUIRED: the items file's path with `.md` replaced by `-report.md`: `<workspace>/rulings-<point>-<task>-report.md`, or `<workspace>/rulings-<point>-<task>-confirm-report.md` for a Header amendment's confirmation ``. `[CONFIRM_NOTE]`'s text becomes: "Another seat's report on item <id> is named at the end of the items file: read that item's verdict block and its amendment entry there, then write your own verdict block for the item, with your own amendment entry when your verdict is AMEND."
   - `**The seat returns** …` (to the end of the file) becomes `**The seat writes** its report to [REPORT_FILE] — the Verdict section with one block per item, a preflight's table, then the AMEND entries ## A1 … — **and returns** a reply of at most 10 lines. The execution skill's The Ruling Seat section says how the controller reads the report and applies an AMEND entry by its Amendment: id.`

7. **final-review.md**, §Fixing what it finds, the two places that fill the re-review's report placeholder:

   ```text
   its `[REPORT_FILE]` being that file
   ```
   becomes
   ```text
   its `[IMPLEMENTER_REPORT_FILE]` being that file and its `[REPORT_FILE]`
   being `<workspace>/final-rereview-report.md`
   ```
   (its first line unbroken: seats.test.sh greps it), and the QA-only case's "with `<workspace>/acceptance-report.md` as `[REPORT_FILE]`" names `[IMPLEMENTER_REPORT_FILE]` instead.

8. **scripts/task-step.**
   - `do_review`: the judge prompt's `fill` call replaces the pair `'[REPORT_FILE]' "$report"` with `'[IMPLEMENTER_REPORT_FILE]' "$report" '[REPORT_FILE]' "$ws/task-$first-review-report.md"`; the Codex prompt's `fill` call replaces `'[REPORT_FILE]' "$report"` with `'[IMPLEMENTER_REPORT_FILE]' "$report"`. After the unexpanded-placeholder check passes and before the state update, `rm -f "$ws/task-$first-review-report.md"`.
   - `cmd_rereview`: `rr_render` fills `[IMPLEMENTER_REPORT_FILE]` from `RR_REPORT` (the implementer's report, as today) and `[REPORT_FILE]` from a new `RR_JUDGE_REPORT`, set to `$ws/task-$first-rereview-$new_round-report.md`. `[IMPLEMENTER_REPORT_FILE]` does not contain the substring `[REPORT_FILE]`, so the two replacements do not interfere. Add `IMPLEMENTER_REPORT_FILE` to the leftover-placeholder regex. When a prompt is written (not on a skip), `rm -f` the judge report path first.
   - The `review --group` code Task 5 added already fills `[REPORT_FILE]` with `$ws/group-<list>-review-report.md`; add the removal of that file just before it writes the prompt (its step 8).
   - Nothing else changes: the digests, their line counts, the state fields and every exit code stay as they are.

- [ ] **Step 4: Run the suites**

Run: `cd plugins/dforge && timeout 120 bash tests/fleet.test.sh && timeout 120 bash tests/seats.test.sh && timeout 600 bash tests/task-step.test.sh && timeout 300 bash tests/review-route.test.sh && timeout 120 bash tests/process-roles.test.sh && timeout 120 bash tests/inline-mode.test.sh && timeout 600 bash tests/task-loop-steps.acceptance.test.sh a15 && timeout 300 bash tests/typed-seats-and-drafting.acceptance.sh A10`, then from the repository root `node scripts/validate-repository.mjs` and `timeout 120 /root/.local/bin/claude plugin validate plugins/dforge`.
Expected: PASS, every suite `0 failed`; validation clean.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/agents/judge-opus.md plugins/dforge/agents/judge-sonnet-high.md plugins/dforge/agents/judge-fable.md \
  plugins/dforge/skills/subagent-driven-development/references/task-reviewer-prompt.md \
  plugins/dforge/skills/subagent-driven-development/references/re-review-prompt.md \
  plugins/dforge/skills/subagent-driven-development/references/group-reviewer-prompt.md \
  plugins/dforge/skills/subagent-driven-development/references/ruling-prompt.md \
  plugins/dforge/reference/final-review.md plugins/dforge/scripts/task-step \
  plugins/dforge/tests/fleet.test.sh plugins/dforge/tests/seats.test.sh plugins/dforge/tests/task-step.test.sh
git commit -m "feat(dforge): judges write their report to a file"
```

### Task 10: task-step verdict and plan-amend --report

**Files:**
- Modify: `plugins/dforge/scripts/task-step` (header comment and `usage`, the argument loop, `do_review`, `cmd_rereview`, Task 5's `hold` and `review --group` code, a new `do_verdict`)
- Modify: `plugins/dforge/scripts/plan-amend` (argument parsing and a report-extraction step before the existing validation)
- Modify: `plugins/dforge/reference/delegated-task.md` (§3 The seat, Scores are additive, Codex seats, Risk 3, the cannot-verify paragraph, §4's trigger, Minor and plan-mandated routes, The fix message, The re-review is scoped, a new "When `task-step verdict` fails" paragraph, The steps by hand)
- Modify: `plugins/dforge/reference/executor-lane.md` (§Codex task review seats, the sentence naming `### Verification Scores`)
- Modify: `plugins/dforge/skills/subagent-driven-development/SKILL.md` (The Ruling Seat: When table, How, AMEND, Header confirmation; the Example Workflow)
- Modify: `plugins/dforge/skills/executing-plans/SKILL.md` (its Ruling Seat: When table, How, AMEND)
- Test: `plugins/dforge/tests/task-step.test.sh`, `plugins/dforge/tests/plan-amend.test.sh`, `plugins/dforge/tests/task-step-text.test.sh`

**Interfaces:**
- Consumes: Judge reports (Task 9) — the report grammar and file names; Group review (Task 5) — `group-<list>-step.json` and each member's `task-<N>-step.json` `round`
- Produces: Verdict and amend (Task 10) — `task-step verdict PLAN_FILE N [M …] [--group] [--rereview R] [--cwd DIR]`, the `reviewCheck` field of a task's step file, `heldCwd` in a held member's step file, `reviewChecks` in `group-<list>-step.json`, `plan-amend PLAN_FILE --report <file> --id A<k>`; `--group` takes no `--rereview` (members re-review alone, so `group-<list>-rereview-<R>-report.md` is never read)

**Items:** 3

**Implementer:** dforge:impl-opus-high
**Evaluation:** files 2 - spec 2 - coupling 1 - risk 2 = 7
**Override:** owner approved the contract-and-test task shape for this plan on 2026-10-26, before plan-lint's Rule S and assignment table allow it

Decisions this task embodies:
- The tracked-file check compares content, not names: the review step records the checkout's HEAD and, for each path `git diff --name-only HEAD` lists, its `git hash-object` (or `deleted`). A file already dirty when the review ran passes until it changes again; an untracked file never counts.
- verdict checks the tracked files before it reads the report, so a seat that both edited a file and wrote nothing is restored first.
- Exit 5 covers a missing report and a malformed one alike: both are a seat that produced nothing usable, and both take the same Failures procedure. Exit 6 keeps its existing meaning ("a required earlier step has not run") for a verdict before any review, and the tracked-file failure shares it; stderr tells them apart.
- verdict writes Minor findings to the ledger as `Task <N>: minor (deferred): <file>:<line> — <one-liner>`, skipping a line already there, so the controller never reads the report to record them.
- A review recorded before this task (no `reviewCheck` in the state) still yields a verdict, with `check tracked: not recorded …`: in-flight runs keep working.
- A `codex:light` seat that reviewed returns JSON and no report file; verdict does not apply to it, and the controller reads the JSON as today.
- A wave group's members sit in several worktrees, so `hold` records each member's checkout (`heldCwd`) and `review --group` records one snapshot per distinct member checkout; verdict checks every one. A sequential group has one snapshot, of the checkout `review --group` ran in.
- A group member's fix round is re-reviewed alone (Task 5's member `rereview`), so its report is `task-<N>-rereview-<R>-report.md`, read with `verdict PLAN_FILE N --rereview R`; `verdict --group --rereview` is a usage error.
- A second failed dispatch of the same seat goes to the route's `fallback:` judge, or `dforge:judge-opus` when the seat line names none (a fresh one even when the failed seat was judge-opus); a third failure is BLOCKED, so the procedure terminates.

- [ ] **Step 1: Write the failing tests**

In `plugins/dforge/tests/task-step.test.sh`, insert this block directly before the suite's final `printf '\n%d passed, %d failed\n'` line, after Task 9's `group report:` block (its group cases read the group state that block leaves):

```bash
# --- verdict: the report digest, the fix files and the tracked-file check ---
vd_report() { sed 's/^|//' > "$1"; } # vd_report <file> — the report on stdin, its leading | stripped
first_block() { awk '{ sub(/\r$/, "") } /^$/ { exit } { print }' "$1" | tr '\n' ';'; }

# A group report: findings and fix files per member task, from the state the
# group block above left (Task 5's review --group).
vd_report "$RR_WS/group-1,3-review-report.md" <<'REPORT'
|## Verdict
|Task 1 spec: pass
|Task 1 quality: changes
|Task 1 scores: spec 16 / scope 17 / verification 15 / quality 12
|Task 3 spec: pass
|Task 3 quality: approved
|Task 3 scores: spec 18 / scope 18 / verification 17 / quality 17
|
|## Findings
|- [Important] (Task 1) app.txt:3 — off by one
|  The loop stops one line early.
|- [Minor] (Task 3) other.txt:1 — wording
|
|## Cannot verify
|- (Task 3) the caller passes the flag
REPORT
rr_run verdict docs/plan.md 1 3 --group
check "verdict --group: exit 0" "$rr_rc" "0"
check "verdict --group: the digest names the group report" "$(head -n 1 <<<"$rr_out")" "group 1,3: verdict from $RR_WS/group-1,3-review-report.md"
check "verdict --group: the per-task verdict lines" "$(grep -c '^Task [13] \(spec\|quality\|scores\): ' <<<"$rr_out")" "6"
check "verdict --group: the finding names its task" "$(grep -E '^(Critical|Important) ' <<<"$rr_out")" "Important 1 app.txt:3 — off by one"
R1=$(( $(rr_state 1 .round) + 1 ))
check "verdict --group: a fix file for the task with findings" "$(first_block "$RR_WS/task-1-fix-$R1.md")" "- app.txt:3: off by one;"
check "verdict --group: no fix file for a task without one" "$(ls "$RR_WS"/task-3-fix-*.md 2>/dev/null | wc -l | tr -d ' ')" "0"
check "verdict --group: the member's Minor goes to the ledger" "$(grep -c '^Task 3: minor (deferred): other.txt:1 — wording$' "$RR_WS/progress.md")" "1"
check "verdict --group: the cannot-verify item keeps its task" "$(grep '^cannot-verify: ' <<<"$rr_out")" "cannot-verify: (Task 3) the caller passes the flag"
vd_report "$RR_WS/group-1,3-review-report.md" <<'REPORT'
|## Verdict
|Task 1 spec: pass
|Task 1 quality: approved
|Task 1 scores: spec 16 / scope 17 / verification 15 / quality 16
|
|## Findings
REPORT
rr_run verdict docs/plan.md 1 3 --group
check "verdict --group: a report missing a member's verdict exits 5" "$rr_rc" "5"
check "verdict --group: the missing key is named" "$(grep -c 'Task 3 spec' <<<"$rr_err")" "1"
rr_run verdict docs/plan.md 1 3 --group --rereview 1
check "verdict --group: a group has no re-review report (members re-review alone)" "$rr_rc" "2"

# A wave group spread over two worktrees: one tracked snapshot per member
# checkout, and verdict checks each.
rr_reset
rr_git worktree add -q --detach "$RR_TMP/wt1" HEAD
rr_git worktree add -q --detach "$RR_TMP/wt3" HEAD
rr_run hold docs/plan.md 1 --cwd "$RR_TMP/wt1"
rr_run hold docs/plan.md 3 --cwd "$RR_TMP/wt3"
check "wave group: hold records the member's checkout" "$(rr_state 3 .heldCwd)" "$RR_TMP/wt3"
rr_run review --group docs/plan.md 1 3
check "wave group: one tracked snapshot per member checkout" \
  "$(jq -r '[.reviewChecks[].cwd] | sort | join(" ")' "$RR_WS/group-1,3-step.json" | tr -d '\r')" "$RR_TMP/wt1 $RR_TMP/wt3"
vd_report "$RR_WS/group-1,3-review-report.md" <<'REPORT'
|## Verdict
|Task 1 spec: pass
|Task 1 quality: approved
|Task 1 scores: spec 17 / scope 18 / verification 16 / quality 16
|Task 3 spec: pass
|Task 3 quality: approved
|Task 3 scores: spec 17 / scope 18 / verification 16 / quality 16
REPORT
rr_run verdict docs/plan.md 1 3 --group
check "wave group: clean member checkouts pass" "$rr_rc" "0"
printf 'judge edit\n' >> "$RR_TMP/wt3/app.txt"
rr_run verdict docs/plan.md 1 3 --group
check "wave group: a change in one member's checkout exits 6" "$rr_rc" "6"
check "wave group: the stderr names that checkout" "$(grep -cF "in $RR_TMP/wt3;" <<<"$rr_err")" "1"
check "wave group: and the file" "$(grep -cx 'app.txt' <<<"$rr_err")" "1"
rr_run verdict docs/plan.md 1 3 --group --cwd "$RR_TMP/wt1"
check "wave group: --cwd cannot stand for two checkouts" "$rr_rc" "2"
rr_git worktree remove --force "$RR_TMP/wt1"
rr_git worktree remove --force "$RR_TMP/wt3"

# A task review: the digest, the fix file, the deferred Minor lines.
rr_reset
vd_report "$RR_WS/task-1-review-report.md" <<'REPORT'
|## Verdict
|spec: fail
|quality: changes
|scores: spec 7 / scope 15 / verification 12 / quality 9
|
|## Strengths
|Small and focused.
|
|## Findings
|- [Critical] app.txt:2 — wrong value
|  The second line must read "line 2".
|- [Important] other.txt:4 — stale copy
|- [Minor] app.txt:5 — naming
|- [Minor] test.txt:0 — no edge case
|
|## Cannot verify
|- the caller passes the flag
|
|## Assessment
|Needs fixes.
REPORT
rr_run verdict docs/plan.md 1
VD=$rr_out
check "verdict: exit 0" "$rr_rc" "0"
check "verdict: the digest names the report" "$(head -n 1 <<<"$VD")" "task 1: verdict from $RR_WS/task-1-review-report.md"
check "verdict: the verdict lines" "$(grep -E '^(spec|quality|scores): ' <<<"$VD" | tr '\n' ';')" \
  "spec: fail;quality: changes;scores: spec 7 / scope 15 / verification 12 / quality 9;"
check "verdict: the counts by severity" "$(grep '^findings: ' <<<"$VD")" "findings: 1 Critical, 1 Important, 2 Minor"
check "verdict: one line per Critical or Important finding" "$(grep -E '^(Critical|Important) ' <<<"$VD" | tr '\n' ';')" \
  "Critical 1 app.txt:2 — wrong value;Important 1 other.txt:4 — stale copy;"
check "verdict: Minor findings are not listed" "$(grep -c '^Minor ' <<<"$VD")" "0"
check "verdict: the cannot-verify item" "$(grep '^cannot-verify: ' <<<"$VD")" "cannot-verify: the caller passes the flag"
check "verdict: the fix line" "$(grep '^fix: ' <<<"$VD")" "fix: $RR_WS/task-1-fix-1.md (2 findings)"
check "verdict: the minor line" "$(grep '^minor: ' <<<"$VD")" "minor: 2 logged as deferred"
check "verdict: the tracked check" "$(grep '^check tracked: ' <<<"$VD")" "check tracked: clean"
check "verdict: the last line is the budget line" "$(tail -n 1 <<<"$VD" | cut -c1-6)" "budget"
check "verdict: at most 20 lines besides the finding lines" "$([ "$(grep -cvE '^(Critical|Important) ' <<<"$VD")" -le 20 ] && echo yes || echo no)" "yes"
check "verdict: the fix file's bullets" "$(first_block "$RR_WS/task-1-fix-1.md")" "- app.txt:2: wrong value;- other.txt:4: stale copy;"
check "verdict: the fix file names the report" "$(grep -cF "$RR_WS/task-1-review-report.md" "$RR_WS/task-1-fix-1.md")" "1"
check "verdict: Minor findings go to the ledger as deferred" \
  "$(grep -cE '^Task 1: minor \(deferred\): (app\.txt:5 — naming|test\.txt:0 — no edge case)$' "$RR_WS/progress.md")" "2"
rr_run verdict docs/plan.md 1
check "verdict: a second run adds no ledger line" "$(grep -c '^Task 1: minor (deferred): app.txt:5 — naming$' "$RR_WS/progress.md")" "1"

# The fix file feeds the re-review, and the re-review's verdict writes the next round's.
rr_edit app.txt add4
rr_git add -A && rr_git commit -qm fix
rr_run rereview docs/plan.md 1
check "verdict then rereview: the fix file's findings reach the prompt" \
  "$(grep -cE '^- (app\.txt:2: wrong value|other\.txt:4: stale copy)$' "$RR_WS/task-1-rereview-1-prompt.md")" "2"
vd_report "$RR_WS/task-1-rereview-1-report.md" <<'REPORT'
|## Verdict
|fix round: open
|open: 1
|
|## Finding verdicts
|- app.txt:2: wrong value — ADDRESSED — app.txt:2 reads "line 2"
|- other.txt:4: stale copy — NOT ADDRESSED — other.txt:4 is unchanged
|
|## Findings
|- [Important] other.txt:4 — stale copy
|- [Minor] app.txt:9 — out of scope: trailing space
REPORT
rr_run verdict docs/plan.md 1 --rereview 1
check "verdict --rereview: passes against the state rereview recorded" "$rr_rc" "0"
check "verdict --rereview: reads the round's report" "$(head -n 1 <<<"$rr_out")" "task 1: verdict from $RR_WS/task-1-rereview-1-report.md"
check "verdict --rereview: the round lines" "$(grep -E '^(fix round|open): ' <<<"$rr_out" | tr '\n' ';')" "fix round: open;open: 1;"
check "verdict --rereview: writes the next round's fix file" "$(first_block "$RR_WS/task-1-fix-2.md")" "- other.txt:4: stale copy;"

# Failures: a missing or malformed report exits 5 and writes no fix file.
rr_run verdict docs/plan.md 1 --rereview 2
check "verdict: a missing report exits 5" "$rr_rc" "5"
check "verdict: a missing report is named" "$(grep -cF "$RR_WS/task-1-rereview-2-report.md" <<<"$rr_err")" "1"
check "verdict: a missing report writes no fix file" "$([ -e "$RR_WS/task-1-fix-3.md" ] && echo yes || echo no)" "no"
printf 'spec: pass\n' > "$RR_WS/task-1-review-report.md"
rr_run verdict docs/plan.md 1
check "verdict: a report that does not open with ## Verdict exits 5" "$rr_rc" "5"
vd_report "$RR_WS/task-1-review-report.md" <<'REPORT'
|## Verdict
|spec: pass
|scores: spec 17 / scope 18 / verification 16 / quality 16
REPORT
rr_run verdict docs/plan.md 1
check "verdict: a report missing a verdict key exits 5" "$rr_rc" "5"
check "verdict: the missing key is named" "$(grep -c 'quality' <<<"$rr_err")" "1"
vd_report "$RR_WS/task-1-review-report.md" <<'REPORT'
|## Verdict
|spec: ✅
|quality: approved
|scores: spec 17 / scope 18 / verification 16 / quality 16
REPORT
rr_run verdict docs/plan.md 1
check "verdict: a verdict value outside its set exits 5" "$rr_rc" "5"
vd_report "$RR_WS/task-1-review-report.md" <<'REPORT'
|## Verdict
|spec: fail
|quality: changes
|scores: spec 7 / scope 15 / verification 12 / quality 9
|
|## Findings
|- [Severe] app.txt:2 — wrong value
REPORT
rr_run verdict docs/plan.md 1
check "verdict: a finding line outside the grammar exits 5" "$rr_rc" "5"
check "verdict: the bad line is quoted" "$(grep -c 'Severe' <<<"$rr_err")" "1"
vd_report "$RR_WS/task-1-review-report.md" <<'REPORT'
|## Verdict
|spec: pass
|quality: approved
|scores: spec 17 / scope 18 / verification 16 / quality 16
|
|## Codex findings
|- [CONFIRMED] app.txt:2 wrong value - the diff shows it
|
|## Findings
REPORT
rr_run verdict docs/plan.md 1
check "verdict: Codex findings that are not the last section exit 5" "$rr_rc" "5"
vd_report "$RR_WS/task-1-review-report.md" <<'REPORT'
|## Verdict
|spec: pass
|quality: approved
|scores: spec 17 / scope 18 / verification 16 / quality 16
|
|## Findings
REPORT
rm -f "$RR_WS"/task-1-fix-*.md
rr_run verdict docs/plan.md 1
check "verdict: a clean report exits 0" "$rr_rc" "0"
check "verdict: a clean report writes no fix file" "$(grep '^fix: ' <<<"$rr_out")" "fix: none"
check "verdict: and leaves no fix file behind" "$(ls "$RR_WS"/task-1-fix-*.md 2>/dev/null | wc -l | tr -d ' ')" "0"

# Failures: a tracked file changed during the review exits 6 and names it.
printf 'judge edit\n' >> "$RR_REPO/app.txt"
rr_run verdict docs/plan.md 1
check "verdict: a tracked file changed during the review exits 6" "$rr_rc" "6"
check "verdict: the changed file is named on its own line" "$(grep -cx 'app.txt' <<<"$rr_err")" "1"
rr_git checkout -- app.txt
rr_run verdict docs/plan.md 1
check "verdict: restored files pass the check" "$rr_rc" "0"
printf 'new\n' > "$RR_REPO/untracked.txt"
rr_run verdict docs/plan.md 1
check "verdict: an untracked file is not a tracked change" "$rr_rc" "0"
rm -f "$RR_REPO/untracked.txt"
rr_git commit -q --allow-empty -m "moved"
rr_run verdict docs/plan.md 1
check "verdict: a HEAD that moved exits 6" "$rr_rc" "6"
check "verdict: a HEAD that moved is named" "$(grep -c 'HEAD moved' <<<"$rr_err")" "1"
rr_git reset -q --hard HEAD~1

# A file already changed when the review ran is compared by content.
rr_reset
printf 'dirty\n' >> "$RR_REPO/other.txt"
rr_run review docs/plan.md 1
vd_report "$RR_WS/task-1-review-report.md" <<'REPORT'
|## Verdict
|spec: pass
|quality: approved
|scores: spec 17 / scope 18 / verification 16 / quality 16
REPORT
rr_run verdict docs/plan.md 1
check "verdict: a file already changed at review time passes" "$rr_rc" "0"
printf 'more\n' >> "$RR_REPO/other.txt"
rr_run verdict docs/plan.md 1
check "verdict: a further change to it exits 6" "$rr_rc" "6"
check "verdict: and names it" "$(grep -cx 'other.txt' <<<"$rr_err")" "1"
rr_git checkout -- other.txt

# A state recorded before the check existed still reads its report; usage.
rr_reset
vd_report "$RR_WS/task-1-review-report.md" <<'REPORT'
|## Verdict
|spec: pass
|quality: approved
|scores: spec 17 / scope 18 / verification 16 / quality 16
REPORT
jq 'del(.reviewCheck)' "$RR_TMP/state1.0" > "$RR_WS/task-1-step.json"
rr_run verdict docs/plan.md 1
check "verdict: a state without a recorded check exits 0" "$rr_rc" "0"
check "verdict: and says the check was not recorded" "$(grep -c '^check tracked: not recorded' <<<"$rr_out")" "1"
rr_reset
rr_run verdict docs/plan.md 1 --cwd "$RR_TMP/no-such-dir"
check "verdict: a missing --cwd directory exits 2" "$rr_rc" "2"
jq '.reviewHead = null' "$RR_TMP/state2.0" > "$RR_WS/task-2-step.json"
rr_run verdict docs/plan.md 2
check "verdict: before review exits 6" "$rr_rc" "6"
cp "$RR_TMP/state2.0" "$RR_WS/task-2-step.json"
rr_run verdict docs/plan.md
check "verdict: no task number exits 2" "$rr_rc" "2"
rr_run verdict docs/plan.md 1 --rereview x
check "verdict: a non-numeric --rereview exits 2" "$rr_rc" "2"
rr_run verdict docs/plan.md 99
check "verdict: no such task exits 3" "$rr_rc" "3"
rr_run verdict docs/codex-plan.md 1
check "verdict: a Host: codex plan exits 2" "$rr_rc" "2"
```

In `plugins/dforge/tests/plan-amend.test.sh`, insert this block directly before the comment line `# A linked worktree session must not amend the primary checkout's plan: the`:

```bash
# --- --report: an AMEND entry taken from a ruling report, never hand-copied ---
# A ruling report numbers its entries A1, A2 … in the report; --id names one.
# Applied from the report, the entry lands exactly as the hand-copied block does.
entry "$TMP/rep-e1" '## A1 — Task 2' 'Print `hello NAME` twice.' 'Print `hello NAME` three times.'
entry "$TMP/rep-e2" '## A2 — Header' '- Bash only.' '- Bash 4 or later.'
{
  printf '## Verdict\n\n### Item 1\nVerdict: AMEND\nRuling: the count is wrong — say three times — one fix round\nAmendment: A1\n\n'
  printf '### Item 2\nVerdict: AMEND\nRuling: pin the shell — Bash 4 — one fix round\nAmendment: A2\n\n'
  cat "$TMP/rep-e1"; echo; cat "$TMP/rep-e2"
  printf '\n## Notes\n\nTrailing text that belongs to no entry.\n'
} > "$TMP/ruling-report.md"
for n in a b c d; do cp docs/plan.md "docs/rep-$n.md"; done
REP_A="$REPO/.dforge/sdd/rep-a/amendments.md" REP_B="$REPO/.dforge/sdd/rep-b/amendments.md"
run docs/rep-a.md b1.md
check "report: the hand-copied block applies" "$out" "amended: A1 Task 2"
run docs/rep-b.md --report "$TMP/ruling-report.md" --id A1
check "report: exit 0" "$status" "0"
check "report: the entry applies" "$out" "amended: A1 Task 2"
check "report: amendments.md matches the hand-copied block's byte for byte" "$(cmp -s "$REP_A" "$REP_B" && echo same || echo differs)" "same"
run docs/rep-b.md --report "$TMP/ruling-report.md" --id A2
check "report: a later entry applies" "$out" "amended: A2 Header"
check "report: nothing after the New fence is taken" "$(grep -c 'Trailing text\|^## Notes\|^Verdict:\|^Amendment:' "$REP_B")" "0"
run docs/rep-c.md --id A1 --report "$TMP/ruling-report.md"
check "report: the flags in either order" "$out" "amended: A1 Task 2"
sed 's/$/\r/' "$TMP/ruling-report.md" > "$TMP/ruling-report-crlf.md"
run docs/rep-d.md --report "$TMP/ruling-report-crlf.md" --id A1
check "report: a CRLF report" "$out" "amended: A1 Task 2"

cp "$REP_B" "$TMP/rep-snapshot"
run docs/rep-b.md --report "$TMP/ruling-report.md" --id A9
check "report: an id the report lacks: exit 1" "$status" "1"
has "report: an id the report lacks: named" "$out" "rejected: no entry A9 in $TMP/ruling-report.md"
check "report: an id the report lacks: amendments unchanged" "$(cmp -s "$REP_B" "$TMP/rep-snapshot" && echo same)" "same"
{ printf '## Verdict\n\n'; printf '## A1 — Task 1\nReason: r\nCost if wrong: c\n### Old\n````text\nPrint `hello NAME`.\n````\n### New\n````text\nPrint `hi NAME`.\n'; } > "$TMP/open-fence.md"
run docs/rep-b.md --report "$TMP/open-fence.md" --id A1
check "report: an entry whose New fence never closes: exit 1" "$status" "1"
has "report: an entry whose New fence never closes: named" "$out" "rejected: entry A1 in $TMP/open-fence.md has no closed New fence"
run docs/rep-b.md --report "$TMP/no-such-report.md" --id A1
check "report: a missing report file: exit 2" "$status" "2"
run docs/rep-b.md --report "$TMP/ruling-report.md" --id 1
check "report: an id that is not A<k>: exit 2" "$status" "2"
run docs/rep-b.md --report "$TMP/ruling-report.md"
check "report: --report without --id: exit 2" "$status" "2"
run docs/rep-b.md --id A1
check "report: --id without --report: exit 2" "$status" "2"
check "report: the refusals left amendments unchanged" "$(cmp -s "$REP_B" "$TMP/rep-snapshot" && echo same)" "same"
```

In `plugins/dforge/tests/task-step-text.test.sh`, insert this block directly before its final `printf '\n%d passed, %d failed\n'` line:

```bash
# The controller reads a review through task-step verdict and an AMEND through
# plan-amend --report; it never reads or copies a report's text.
check "the loop steps run task-step verdict" "$([ "$(loop_steps | grep -cF -- 'task-step verdict PLAN_FILE N')" -ge 1 ] && echo yes || echo no)" "yes"
names "the re-review is read through verdict --rereview" "$DT" '`bash <plugin-root>/scripts/task-step verdict PLAN_FILE N --rereview <R>`'
names "verdict writes the fix file's bullets" "$DT" '`task-step verdict` writes its bullets from the report'
names "the seat's report is never read" "$DT" 'Never Read the report file yourself'
names "a failed verdict restores the tracked files" "$DT" '`git -C <dir> checkout -- <files>`'
names "a failed verdict is a Ruling line" "$DT" 'restored the committed state and re-dispatched once'
names "a second failure takes the fallback judge" "$DT" 'A second failure dispatches the route'"'"'s fallback judge'
names "the risk-3 check reads the report's last section" "$DT" 'A report whose `## Codex findings` section is not its last'
lacks "the risk-3 check no longer reads the reply" "$DT" 'A reply whose `### Codex findings`'
for f in "$SDD" "$INLINE"; do
  s=$(basename "$(dirname "$f")")
  names "$s: an AMEND applies from the report" "$f" 'scripts/plan-amend PLAN_FILE --report <workspace>/rulings-<point>-<task>-report.md --id A<k>'
  lacks "$s: an AMEND is no longer copied by hand" "$f" 'copy the entry, from its `## A?` line'
  names "$s: the ruling report is read by its Verdict section" "$f" 'read only its `## Verdict` section'
done
names "the example workflow reads the verdict with task-step" "$SDD" '[task-step verdict PLAN_FILE 1:'
names "a header amendment's confirmation reads the first report" "$SDD" 'then the path of the first seat'"'"'s report'
names "by hand: the review prompt's two report placeholders" "$DT" '`[IMPLEMENTER_REPORT_FILE]` set to the implementer'"'"'s report and `[REPORT_FILE]` to `<workspace>/task-<N>-review-report.md`'
names "the lane's review prompt no longer names a Verification Scores section" "$P/reference/executor-lane.md" 'rather than a markdown report file'
```

- [ ] **Step 2: Run them to verify they fail**

Run: `cd plugins/dforge && timeout 600 bash tests/task-step.test.sh; timeout 300 bash tests/plan-amend.test.sh; timeout 120 bash tests/task-step-text.test.sh`
Expected: FAIL — task-step: every `verdict` case that expects exit 0, 3, 5 or 6 (the subcommand does not exist, so it exits 2), `verdict then rereview: the fix file's findings reach the prompt`, and the `wave group:` cases (on a tree without Task 5 they fail earlier, at `hold`); the usage cases that expect exit 2 already pass. plan-amend: every `report:` case except the hand-copied block and the exit-2 usage cases (`--report` is not an accepted argument shape yet). task-step-text: every new check (the controller text still reads replies and copies AMEND entries).

- [ ] **Step 3: Implement**

1. **task-step: recording what the check compares.** Add a helper `tracked_snapshot DIR` that prints one JSON object `{"cwd": DIR, "head": <git -C DIR rev-parse HEAD>, "dirty": [{"path": P, "hash": H}, …]}`: the paths are `git -C DIR -c core.quotepath=off diff --name-only --no-renames HEAD`, CR-stripped and sorted with `LC_ALL=C`; `H` is `git -C DIR hash-object -- P` when `DIR/P` is a file, else `deleted`. When `DIR` is not inside a git work tree it prints nothing (the existing `review --cwd "$TMP/wt"` case passes a plain directory and must still exit 0). Then:
   - `do_review` records `.reviewCheck = <tracked_snapshot "$top">` in the state's existing jq update (`$top` is `--cwd` or the checkout's top level); when the helper printed nothing, it deletes `.reviewCheck`.
   - `cmd_rereview` records `.reviewCheck` the same way, for the directory the state's `.reviewCheck.cwd` names, or the checkout's top level when the state has none, skip or not.
   - Task 5's `hold` writes `heldCwd` into the member's step file on every call (also when it appends no ledger line): the `--cwd DIR` it was given, else the checkout's top level.
   - Task 5's `review --group` records `.reviewChecks` in `group-<list>-step.json`: an array of `tracked_snapshot` objects, one per distinct directory among its members' `heldCwd` values, a member with none counting as the `--cwd` it was given or the top level, in the order the directories first appear in ascending member order. A directory the helper prints nothing for is left out.

2. **task-step: the `verdict` subcommand.** `task-step verdict PLAN_FILE N [M …] [--group] [--rereview R] [--cwd DIR]`, parsed with the other subcommands: `--group` and `--rereview` are verdict flags (`--rereview` takes `^[1-9][0-9]*$`), and the two together are usage; `--cwd` is accepted by review and verdict; everything else is usage (exit 2). Like `start` and `review`, it exits 2 on a `Host: codex` plan, 3 on a task not in the plan, 4 when an amendment does not apply. Then, in order:
   1. **State.** With `--group`, `<list>` is the task numbers ascending joined by commas and the state is `$ws/group-<list>-step.json`; without, `$ws/task-<first>-step.json`. A missing state file, or a task state whose `.reviewHead` is null, exits 6 with `task-step: run task-step review for task <first> first` (`review --group` for a group).
   2. **Report path.** `$ws/task-<first>-review-report.md`, or with `--rereview R` `$ws/task-<first>-rereview-<R>-report.md`; with `--group`, `$ws/group-<list>-review-report.md`.
   3. **Tracked check.** The recorded snapshots are the task state's `.reviewCheck`, or every entry of a group state's `.reviewChecks`. With none, the check line is `check tracked: not recorded (the review step predates this check)`. Otherwise check each snapshot in turn as follows and stop at the first that fails. `DIR` is the snapshot's `cwd`; `--cwd` replaces it when there is exactly one snapshot, and with several it exits 2 (`--cwd names one checkout; this group recorded <k>`); a missing directory exits 2 (`bad --cwd: <dir>`). If `git -C DIR rev-parse HEAD` differs from the recorded head, print to stderr `task-step: HEAD moved during the review in <dir> (<old7> -> <new7>); files changed since:` and then each path of `git -C DIR diff --name-only --no-renames <recorded head>`, one per line, and exit 6. Otherwise take a fresh `tracked_snapshot DIR` and compare its `dirty` list with the recorded one: a path in one list only, or with a different hash, has changed. Any changed path prints `task-step: tracked files changed during the review in <dir>; restore them with git -C <dir> checkout -- <files>:` and then each path on its own line, and exits 6. A clean check line is `check tracked: clean`.
   4. **Read the report.** Missing: exit 5, `task-step: no report at <path>: the seat wrote none`. Strip CRs. Every other refusal below exits 5 with `task-step: <path>: <reason>`:
      - the first non-blank line is not exactly `## Verdict` (`does not open with ## Verdict`);
      - a line starting `## ` begins a section. In `## Verdict`, each line matching `^[^:]+: .+$` is a key line; other lines there are ignored;
      - required keys, by mode — review: `spec` ∈ {pass, fail, cannot-verify}, `quality` ∈ {approved, changes}, `scores` matching `spec <n> / scope <n> / verification <n> / quality <n>` with each n from 1 to 20; re-review: `fix round` ∈ {addressed, open}, `open` a whole number. With `--group` (a group review) the three review keys are prefixed `Task <N> ` for each listed task. A missing key names it (`missing verdict line '<key>: …'`); a value outside its set quotes the line;
      - in `## Findings`, every line beginning `- ` must match `- [<Critical|Important|Minor>] <file>:<line> <—|-> <one-liner>`, `<file>` holding no space and `<line>` digits or a `<a>-<b>` range, or be `- none` in any case. With `--group` the `(Task <N>) ` prefix between the severity and the file is required and must name a listed task; without it, it is not allowed. A bad line is quoted (`line <k> is not a finding line: <line>`). Lines not beginning `- ` (detail lines, `(<k> more Minor left out)`, blanks) are ignored;
      - in `## Cannot verify`, each `- ` line is one item, its text after `- `; `- none` is skipped;
      - a `## Codex findings` section that is not the last `## ` section (`## Codex findings is not the report's last section`);
      - any other section is ignored.
   5. **Fix files.** Group the Critical and Important findings by task: the `(Task <N>)` prefix, else `<first>`. For each task with any, `R` is that task's `task-<N>-step.json` `.round` plus 1 (without `--group`, the state's `.round` plus 1). Write `$ws/task-<N>-fix-<R>.md`: one bullet per finding in report order, `- <file>:<line>: <one-liner>` (`- <file>: <one-liner>` when the line is 0), then a blank line, then `Severity and detail: <report path>`, then each finding as `- [<severity>] <file>:<line> — <one-liner>`. `task-step rereview` reads the bullets before the blank line, so this file is the next round's fix message as-is. With no Critical or Important finding, write no fix file and leave any existing one alone.
   6. **Ledger.** For each Minor finding append `Task <N>: minor (deferred): <file>:<line> — <one-liner>` to the ledger, unless the ledger already holds that exact line.
   7. **Digest**, on stdout, in this order:
      - `task <ids>: verdict from <report path>` (`<ids>` as the other digests print them), or `group <list>: verdict from <report path>`;
      - each `## Verdict` key line verbatim, at most 12 lines: with more, the first 11 and then `verdict: <k> more lines in the report`;
      - `findings: <c> Critical, <i> Important, <m> Minor`;
      - one line per Critical or Important finding, in report order: `<severity> <task> <file>:<line> — <one-liner>`;
      - one `cannot-verify: <item>` line per item, the group prefix kept, as many as fit so that every line except the finding lines totals at most 20; when some do not fit, the last of them becomes `cannot-verify: <k> more in the report`;
      - `fix: <path> (<n> finding)` or `(<n> findings)`, several joined by `; `, or `fix: none`;
      - `minor: <k> logged as deferred`;
      - the check line from step 3;
      - the budget line, as `cmd_rereview` prints it (`DFORGE_BUDGET_CALLER="task-step:verdict" bash "$HERE/context-size"`).
      Exit 0. verdict never changes a step file.
   8. Update the header comment and `usage`: add the verdict usage line; the exit list becomes `0 ok; 2 usage, or any subcommand on a Host: codex plan; 3 no such task; 4 an amendment does not apply; 5 (verdict) the seat wrote no report, or one outside the grammar; 6 a required earlier step has not run, or (verdict) a tracked file changed during the review`. The sentence `5 is context-size's handoff code and is never used here.` is removed.

3. **plan-amend `--report`.**
   - Usage is `plan-amend PLAN_FILE BLOCK_FILE` or `plan-amend PLAN_FILE --report FILE --id A<k>`, the two flags in either order. Any other shape, or an `--id` not matching `^A[0-9]+$`, prints the usage (both forms) and exits 2; a `--report` file that does not exist exits 2 with `no such report file: <file>`.
   - After the existing plan and workspace checks, with `--report`: CR-strip the report, find the first line matching `^## A<k> (—|-) (Task [0-9]+|Header)[[:space:]]*$` for exactly that `<k>` (so `A1` never matches `A10`), and copy from it through the closing line of the fence that opens after its `### New` line, tracking fences with `_PLAN_AWK`'s `close_marker` as the existing Old/New split does. No such heading: `reject "no entry A<k> in <file>"`. A line matching `^## A[0-9]+ ` outside a fence, or the end of the file, before that closing line: `reject "entry A<k> in <file> has no closed New fence"`. Rewrite the copied heading's `A<k>` to `A?` and write the result to `$TMP/block`.
   - From there the existing flow runs unchanged, so the appended entry is byte-identical to the one the hand-copied block produces.

4. **delegated-task.md.** Name locations by the quoted anchors; Task 7 has edited §4.
   - §3, the bullet that begins `**The seat:**`: after its first sentence (ending `read it first and follow it"`), add: "When a judge seat returns, run `bash <plugin-root>/scripts/task-step verdict PLAN_FILE N` with the review's task numbers, and act on its digest. Never Read the report file yourself: the digest carries the verdicts, the scores, one line per Critical or Important finding and the cannot-verify items, and verdict has already written the fix file and logged the Minor findings. A `codex:light` seat that reviewed writes no report: read its JSON as Codex seats below says." The phrase `Never Read the report file yourself` must stay on one line.
   - New paragraph directly after the paragraph that begins `**Mechanical checks.**`:

     ```text
     **When `task-step verdict` fails.** Exit 5 means the seat wrote no report,
     or one outside the grammar, and stderr says which; exit 6 means a tracked
     file in the reviewed checkout changed during the review, or HEAD moved, and
     stderr names the files and the checkout. The review saw the committed
     state, so on exit 6 restore it with `git -C <dir> checkout -- <files>`.
     Then, either way, log `Task <N>: Ruling: review seat <seat> <wrote no
     report | wrote a malformed report | changed <files>> —
     restored the committed state and re-dispatched once — none`, delete the
     report file, and re-dispatch the same seat once with the same prompt file.
     A second failure dispatches the route's fallback judge: the judge after
     `fallback:` on the `seat:` line when it names one, otherwise
     `dforge:judge-opus`, a fresh dispatch even when the failed seat was
     judge-opus; say so. A third failure is `Task <N>: BLOCKED — review seat —
     no usable report after three dispatches`. Exit 6 with
     `run task-step review … first` means the review step never ran: run it.
     ```

     Rewrap as you like, but keep `` `git -C <dir> checkout -- <files>` ``, `restored the committed state and re-dispatched once` and `A second failure dispatches the route's fallback judge` unbroken on one line each (task-step-text.test.sh greps them).
   - `**Scores are additive.**`: "The judge returns the spec and quality verdicts and four scores" becomes "The verdict digest carries the spec and quality verdicts and the four scores"; the closing clause "a judge that returns scores but drops the verdicts has produced an unusable review — re-dispatch it." becomes "a report that drops a verdict line is malformed: `task-step verdict` exits 5 on it (When `task-step verdict` fails)."
   - **Risk 3**: the sentence beginning "A reply whose `### Codex findings`" (through "re-dispatch it.") becomes the text below, its first line unbroken. The judge's findings and CONFIRMED items reach the digest through the report.

     ```text
     A report whose `## Codex findings` section is not its last formed its own
     review after reading Codex's; `task-step verdict` exits 5 on it.
     ```
   - The paragraph beginning "The task reviewer may report "⚠️ Cannot verify from diff" items" begins instead "The digest's `cannot-verify:` lines are requirements"; the rest of it stands.
   - §4: "The loop triggers when the review reports spec ❌, any Critical or Important finding, any score of 1-8, or a ⚠️ item" becomes "The loop triggers when the digest shows `spec: fail`, any Critical or Important finding line, any score of 1-8, or a cannot-verify item". The Minor bullet's "Record Minor findings in the progress ledger as you go" becomes "`task-step verdict` records Minor findings in the progress ledger", and its example line becomes `Task <N>: minor (deferred): <file>:<line> — <one-liner>`. The plan-mandated bullet adds: "(its digest line's one-liner begins `plan-mandated:`); delete its bullet from the fix file before the fix dispatch".
   - `**The fix message**`: leave the line holding "per open finding, `- <file>: <finding one-liner>`, then a blank line, then" exactly as it is (task-step-text.test.sh), and add after that sentence the text below, its first line unbroken:

     ```text
     `task-step verdict` writes its bullets from the report, each `<file>`
     carrying the finding's `:<line>`, with the severity lines after the blank
     line; append the ruling's smallest fix and the covering test files below
     them. Write the file yourself only for findings no report holds: a
     mechanical check's finding, a CONFIRMED-GAP from the ruling seat, or a
     Codex seat's JSON review.
     ```
   - `**The re-review is scoped.**`: replace the sentences that describe what the re-reviewer returns (from `The re-reviewer verdicts each finding` to the paragraph's end) with: "When the seat returns, run `bash <plugin-root>/scripts/task-step verdict PLAN_FILE N --rereview <R>`. Its `fix round:` line says whether the round closed; its finding lines are every finding still open, new breakage in the fix diff included, and it has written them to the next round's fix file. The re-reviewer's out-of-scope issues reach the ledger as deferred Minor findings and never extend the loop."
   - Reviewer inputs bullet: `the report file` becomes `the implementer's report file`.
   - The steps by hand, §3: after `[LENS_FILES]` …, add `` `[IMPLEMENTER_REPORT_FILE]` set to the implementer's report and `[REPORT_FILE]` to `<workspace>/task-<N>-review-report.md` ``, and: task-step verdict exits 2 on a `Host: codex` plan, so read the report's `## Verdict` section and its finding lines yourself and write the fix file from them. §4: the re-review's `[REPORT_FILE]` is `<workspace>/task-<N>-rereview-<R>-report.md`.

5. **executor-lane.md**, §Codex task review seats: the clause "and the final message is JSON rather than a markdown `### Verification Scores` section." becomes "and the final message is JSON rather than a markdown report file."

6. **subagent-driven-development SKILL.md**, The Ruling Seat:
   - When table, `cannot-verify` row: its decision point "Every "⚠️ Cannot verify from diff" item, before the task completes" becomes "Every `cannot-verify:` line of a `task-step verdict` digest, before the task completes".
   - How: after "expanding its placeholders.", add the text below; keep "read only its `## Verdict` section" unbroken:

     ```text
     Its `[REPORT_FILE]` is `<workspace>/rulings-<point>-<task>-report.md`. The
     seat writes its report there and replies in at most 10 lines;
     read only its `## Verdict` section
     (`awk '/^## / { on = ($0 == "## Verdict") } on' <report>`), never the rest.
     ```
   - AMEND: the sentence that begins "copy the entry, from its `## A?` line" (through "`scripts/plan-amend PLAN_FILE <workspace>/amend-<id>.md`.") becomes the text below, the command unbroken on one line; and "make one fresh seat dispatch carrying the entry and the rejection output" becomes "make one fresh seat dispatch carrying the report path, the entry's id and the rejection output".

     ```text
     run
     `scripts/plan-amend PLAN_FILE --report <workspace>/rulings-<point>-<task>-report.md --id A<k>`,
     `A<k>` being the item's `Amendment:` line; never copy the entry by hand.
     ```
   - Header confirmation: "the original item entry unchanged, then the first verdict block verbatim." becomes "the original item entry unchanged, then the path of the first seat's report and the item's id." The confirming seat's `[REPORT_FILE]` is `<workspace>/rulings-<point>-<task>-confirm-report.md`, and its AMEND is applied with `--report` on that file.
   - Example Workflow: replace each `Judge:` reply and its `Verification Scores:` line, and the `Re-reviewer:` reply, with a one-line reply (`Judge: report task-1-review-report.md — spec pass, quality approved, scores 17/18/16/16, 0 findings`) followed by a verdict line: `[task-step verdict PLAN_FILE 1: spec: pass, quality: approved, scores: spec 17 / scope 18 / verification 16 / quality 16, fix: none, check tracked: clean]`; for Task 2, `[task-step verdict PLAN_FILE 2: spec: fail; Important 2 src/progress.ts:0 — missing progress reporting; Important 2 src/index.ts:88 — magic number (100); fix: task-2-fix-1.md (2 findings)]`; for its re-review, `[task-step verdict PLAN_FILE 2 --rereview 1: fix round: addressed, open: 0, fix: none]`. Leave the Ledger lines as they are.

7. **executing-plans SKILL.md**, its Ruling Seat: the `cannot-verify` row's decision point becomes "A delegated task's `cannot-verify:` digest line"; the How paragraph gains the same `[REPORT_FILE]` and "read only its `## Verdict` section" text as item 6; its AMEND bullet's copy-and-run sentence becomes the same `scripts/plan-amend PLAN_FILE --report <workspace>/rulings-<point>-<task>-report.md --id A<k>` text as item 6. Every phrase task-step-text.test.sh greps, in this item and items 4 to 6, sits unbroken on one line.

- [ ] **Step 4: Run the suites**

Run: `cd plugins/dforge && timeout 600 bash tests/task-step.test.sh && timeout 300 bash tests/plan-amend.test.sh && timeout 120 bash tests/task-step-text.test.sh && timeout 300 bash tests/review-route.test.sh && timeout 120 bash tests/inline-mode.test.sh && timeout 120 bash tests/process-roles.test.sh && timeout 120 bash tests/seats.test.sh`, then from the repository root `node scripts/validate-repository.mjs` and `timeout 120 /root/.local/bin/claude plugin validate plugins/dforge`.
Expected: PASS, every suite `0 failed`; validation clean.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/scripts/task-step plugins/dforge/scripts/plan-amend \
  plugins/dforge/reference/delegated-task.md plugins/dforge/reference/executor-lane.md \
  plugins/dforge/skills/subagent-driven-development/SKILL.md plugins/dforge/skills/executing-plans/SKILL.md \
  plugins/dforge/tests/task-step.test.sh plugins/dforge/tests/plan-amend.test.sh plugins/dforge/tests/task-step-text.test.sh
git commit -m "feat(dforge): read reviews via task-step verdict"
```

### Task 11: Plan and spec seats write report files

**Files:**
- Modify: `plugins/dforge/skills/writing-plans/references/plan-reviewer-prompt.md` (both templates' read-only line and Output Format, Findings instructions, Round 1 on Codex change 3, Placeholders, Reviewer returns)
- Modify: `plugins/dforge/skills/writing-plans/SKILL.md` (§Lint and Review step 2: the four sentences that save a reply)
- Modify: `plugins/dforge/skills/brainstorming/references/architecture-critic-prompt.md` (`## Output`, Placeholders)
- Modify: `plugins/dforge/skills/brainstorming/SKILL.md` (Architecture critic, Folded into Fable, a new "The spec review's report" paragraph)
- Modify: `plugins/dforge/reference/auto-run.md` (§The spec, §Rulings 1 and 3)
- Test: `plugins/dforge/tests/seats.test.sh`

**Interfaces:**
- Consumes: Judge reports (Task 9)
- Produces: the report files `<workspace>/plan-review-round-<r>.md`, `<state>/critic-<spec name>-report.md`, `<state>/spec-review-<spec name>-<r>-report.md`, `<state>/rulings-preexec-<k>-report.md`, `<state>/rulings-fable-<k>-report.md`

**Items:** 3

**Implementer:** dforge:impl-sonnet-high
**Evaluation:** files 1 - spec 2 - coupling 1 - risk 1 = 5
**Override:** owner approved the contract-and-test task shape for this plan on 2026-10-26, before plan-lint's Rule S and assignment table allow it

Decisions this task embodies:
- Files scores 1 because the six files are three shapes: two judge templates given the same report section, three files of dispatch prose given the same report-file sentence, and one text-check suite.
- The plan review's report file is the file writing-plans already saves each reply to, `<workspace>/plan-review-round-<r>.md`, so the Later rounds template's `[PRIOR_FINDINGS_FILE]` keeps reading the same path. The judge writes it; the controller no longer does.
- Plan findings use the Contract's grammar with the plan file and line as `<file>:<line>`, the one-liner beginning `Task N:` or `header:`.
- The critic and the Fable spec review keep their own severity scale, Blocker / High / Medium / Nit, inside the same grammar: brainstorming's counts, auto-run's register notes and A17's second-round rule are all written in it.
- A native Codex judge gets change 3 of Round 1 on Codex; its replacement line must allow the report file, while a Codex CLI round (Output Format deleted, read-only sandbox) writes none.
- The seats here have no template file for the Fable and Opus dispatches; their dispatch prose names the report file and the reply rule.

- [ ] **Step 1: Write the failing tests**

In `plugins/dforge/tests/seats.test.sh`, insert this block directly before its final `printf '\n%d passed, %d failed\n'` line, after Task 9's block (it uses that block's `lacks`):

```bash
# The plan-review, critic, spec-review and pre-execution ruling seats follow
# the same report contract: the full report in a file, a reply of at most ten
# lines, a fixed `## Verdict` section.
PRP="$P/skills/writing-plans/references/plan-reviewer-prompt.md"
WP="$P/skills/writing-plans/SKILL.md"
CP="$P/skills/brainstorming/references/architecture-critic-prompt.md"
BS="$P/skills/brainstorming/SKILL.md"
AR="$P/reference/auto-run.md"
count_of() { grep -cF -- "$2" "$1" 2>/dev/null; } # count_of <file> <text> - lines holding text
check "plan reviewer: both templates name the report file" "$(count_of "$PRP" 'Write your full report to [REPORT_FILE] and write nothing else')" "2"
check "plan reviewer: both templates cap the reply" "$(count_of "$PRP" 'Then reply in at most 10 lines')" "2"
check "plan reviewer: both reports open with the Verdict section" "$(grep -cE '^ *## Verdict$' "$PRP")" "2"
check "plan reviewer: both carry the scores key" "$(count_of "$PRP" 'scores: executability <1-20> / coherence <1-20> / coverage <1-20> / assumptions <1-20>')" "2"
check "plan reviewer: both carry the finding grammar" "$(count_of "$PRP" '- [Critical|Important|Minor] <file>:<line> — <one-liner>')" "2"
check "plan reviewer: the prior findings section" "$(grep -cE '^ *## Prior findings$' "$PRP")" "1"
names "plan reviewer: the report file placeholder" "$PRP" '`[REPORT_FILE]` - REQUIRED: `<workspace>/plan-review-round-<r>.md`'
lacks "plan reviewer: no longer forbids modifying files" "$PRP" 'You cannot run commands, modify files, or dispatch subagents.'
check "plan reviewer: the seat writes only its report, and change 3 quotes that line" \
  "$(count_of "$PRP" 'You cannot run commands or dispatch subagents, and you write only the report file.')" "3"
lacks "writing-plans: the controller no longer saves the reply" "$WP" 'save its reply to'
lacks "writing-plans: nor saves each native reply" "$WP" 'saving each'
names "writing-plans: round 1 names the report file" "$WP" '`[REPORT_FILE]` set to `<workspace>/plan-review-round-1.md`'
names "writing-plans: later rounds name the report file" "$WP" '`[REPORT_FILE]` set to `<workspace>/plan-review-round-<r>.md`'
names "critic: names the report file" "$CP" 'Write your full report to [REPORT_FILE] and write nothing else'
names "critic: caps the reply" "$CP" 'Then reply in at most 10 lines'
check "critic: the report opens with the Verdict section" "$(grep -cE '^ *## Verdict$' "$CP")" "1"
names "critic: the counts key" "$CP" 'findings: <b> Blocker, <h> High, <m> Medium, <n> Nit'
names "critic: the finding grammar on its own scale" "$CP" '- [Blocker|High|Medium|Nit] <file>:<line> — <one-liner>'
names "critic: the report file" "$CP" '`<state>/critic-<spec name>-report.md`'
names "spec review: the report file" "$BS" '`<state>/spec-review-<spec name>-<r>-report.md`'
names "spec review: the reply rule" "$BS" 'write nothing else, and reply in at most 10 lines'
names "spec review: the open count decides a second round" "$BS" 'open: <b> Blocker, <h> High'
lacks "spec review: a folded critic's findings are in the report" "$BS" 'so its reply carries the'
names "auto run: the spec review's report file" "$AR" '`<state>/spec-review-<spec name>-<r>-report.md`'
names "auto run: the pre-execution ruling's report file" "$AR" '`<state>/rulings-preexec-<k>-report.md`'
names "auto run: the Fable batch's report file" "$AR" '`<state>/rulings-fable-<k>-report.md`'
check "auto run: every seat it dispatches caps its reply" "$(count_of "$AR" 'write nothing else, and reply in at most 10 lines')" "3"
```

- [ ] **Step 2: Run them to verify they fail**

Run: `cd plugins/dforge && timeout 120 bash tests/seats.test.sh`
Expected: FAIL — every check in the new block: no plan, critic, spec-review or auto-run seat names a report file yet, and `writing-plans` still says `save its reply to`.

- [ ] **Step 3: Implement**

The wording rules of Task 9 Step 3 item 2 apply: each grepped phrase sits on one line, and skeletons inside a fenced template are indented four spaces deeper than the prompt body. Task 3 has already edited plan-reviewer-prompt.md (a paragraph after each template's opening), writing-plans §Lint and Review (the round cap), brainstorming's Auto by default step 4 and its Folded into Fable sentence on the second round, and auto-run §The spec's round sentence; every anchor below is a sentence Task 3 leaves alone.

1. **plan-reviewer-prompt.md.**
   - In both templates, `You cannot run commands, modify files, or dispatch subagents.` becomes `You cannot run commands or dispatch subagents, and you write only the report file.`
   - The first template's `## Findings` instructions: "Locate each finding by `Task N` or `header`, and say what is wrong, why it matters for execution, and the fix." becomes "Locate each finding by the plan file and line, begin its one-liner with `Task N:` or `header:`, and say what is wrong, why it matters for execution, and the fix."
   - The first template's `## Output Format` section (heading up to `## Criteria`) becomes:

     ```text
         ## Output Format

         Write your full report to [REPORT_FILE] and write nothing else: it is
         the only file you may create or change. Then reply in at most 10 lines:
         the scores, the count of findings by severity, and the report path.
         The report, written without the indent:

             ## Verdict
             scores: executability <1-20> / coherence <1-20> / coverage <1-20> / assumptions <1-20>

             ## Findings
             - [Critical|Important|Minor] <file>:<line> — <one-liner>

         `<file>:<line>` is the plan file and the line the finding is about; the
         one-liner begins `Task N:` or `header:` and carries the issue, why it
         matters for execution, and the fix. Detail goes on lines indented by two
         spaces below its finding. Leave Findings empty when there are none.
     ```
   - The Later rounds template's `## Output Format` becomes the same text with this skeleton, and keeps its closing paragraph (`Write one Prior findings line for every Critical or Important finding of the last round, …`):

     ```text
             ## Verdict
             scores: executability <1-20> / coherence <1-20> / coverage <1-20> / assumptions <1-20>
             prior: <a> addressed, <n> not addressed

             ## Prior findings
             - [ADDRESSED|NOT ADDRESSED] <the finding, one line> — <evidence>

             ## Findings
             - [Critical|Important|Minor] <file>:<line> — <one-liner>
     ```
   - Round 1 on Codex, change 3: the quoted line becomes `You cannot run commands or dispatch subagents, and you write only the report file.` and its replacement becomes `You are running read-only. Read the files named above with your own tools. Do not modify any file other than a report file this prompt names, and do not dispatch subagents.` Keep `You are running read-only` and `In this template and the Later rounds one, make change 3 of` (review-route.test.sh).
   - Placeholders: add `` `[REPORT_FILE]` - REQUIRED: `<workspace>/plan-review-round-<r>.md`, `<r>` being this round's number `` to the first list (the Later rounds list says "as above"). Both `**Reviewer returns:**` lines become `**Reviewer writes** … to [REPORT_FILE] **and returns** a reply of at most 10 lines`, keeping what each lists.

2. **writing-plans SKILL.md**, §Lint and Review step 2 (Task 3 has edited step 3; these sentences are in step 2's bullets):
   - native: "saving each reply to `<workspace>/plan-review-round-<r>.md`." becomes "each with `[REPORT_FILE]` set to `<workspace>/plan-review-round-<r>.md`."
   - Codex fallback: "with the full-plan template, save its reply to `<workspace>/plan-review-round-1.md`, and say why." becomes "with the full-plan template and `[REPORT_FILE]` set to `<workspace>/plan-review-round-1.md`, and say why."
   - codex-off: the same change to "Dispatch it with the full-plan template, save its reply to `<workspace>/plan-review-round-1.md`, and say …".
   - later rounds: "and save its reply to `<workspace>/plan-review-round-<r>.md`." becomes "with `[REPORT_FILE]` set to `<workspace>/plan-review-round-<r>.md`." Each `[REPORT_FILE]` set to … phrase stays on one line (seats.test.sh greps the round-1 and round-`<r>` forms).
   - After the bullets, add: "The seat writes its report to that file and replies in at most 10 lines. Read the report's `## Verdict` section and its Critical and Important findings; the reply carries only counts."

3. **architecture-critic-prompt.md.** `## Output` becomes:

   ```text
       ## Output

       Write your full report to [REPORT_FILE] and write nothing else: it is
       the only file you may create or change. Then reply in at most 10 lines:
       the counts by severity, the one change, and the report path. The report,
       written without the indent:

           ## Verdict
           findings: <b> Blocker, <h> High, <m> Medium, <n> Nit
           one change: If I could change one thing, it would be ...

           ## Findings
           - [Blocker|High|Medium|Nit] <file>:<line> — <one-liner>

       Findings ranked Blocker / High / Medium / Nit, most severe first.
       `<file>:<line>` is the spec and the line of the section the finding is
       about. Below each, on lines indented by two spaces: what is wrong; why
       it matters, citing a file:line when the repository shows it; a concrete
       change to the spec. A Blocker is a design that cannot meet a stated
       requirement or loses data; a High finding will cost a rewrite later.
       With nothing to report, leave Findings empty; the one change line is
       still written.
   ```

   (process-roles.test.sh pins `Blocker / High / Medium / Nit` and `If I could change one thing, it would be`, each on one line; `do not score them 1-20` stays in the unchanged paragraph.) Placeholders gain: `` `[REPORT_FILE]` is `<state>/critic-<spec name>-report.md`, `<spec name>` the spec's file name without `.md` ``; keep the sentence holding ``or under `autoRun=on` the spec's`` (auto-default.test.sh).

4. **brainstorming SKILL.md.**
   - **Architecture critic:** after `and the repository root.` add: "Set `[REPORT_FILE]` to `<state>/critic-<spec name>-report.md`; read its `## Verdict` section and its Blocker and High findings."
   - **Folded into Fable.**: `so its reply carries the critic's ranked findings under their own heading beside its rulings` becomes `so its report carries the critic's ranked findings under their own heading, ## Critic findings, beside its rulings`.
   - Insert directly before the line `**User Review Gate:**` a paragraph beginning `**The spec review's report.**`: every Fable spec review round names a report file, `` `<state>/spec-review-<spec name>-<r>-report.md` ``, and tells the seat to write its full report there, write nothing else, and reply in at most 10 lines. The report opens with a `## Verdict` section of `rulings: <k>`, `undecided: <k>` and `open: <b> Blocker, <h> High` (the Blocker and High findings still unanswered after this round, its own and a folded critic's), then `## Rulings` (one `- <item> — <ruling>` line each), `## Undecided` (one `- <item> — <options, recommended first>` line each) and, when the critic is folded in, `## Critic findings` in the critic's grammar. Read the Verdict section, then the Rulings and Undecided lines; the `open:` line decides whether a second round runs. Keep `write nothing else, and reply in at most 10 lines` and `open: <b> Blocker, <h> High` on one line each.

5. **auto-run.md.**
   - §The spec: after "dispatch `dforge:judge-fable` on the spec against the approved design: the design sections as approved, verbatim, and the spec's path", add ", naming its report file as dforge:brainstorming's The spec review's report says (`<state>/spec-review-<spec name>-<r>-report.md`): it is told to write nothing else, and reply in at most 10 lines".
   - §Rulings 1: the Opus dispatch before execution adds "naming the report file `<state>/rulings-preexec-<k>-report.md` (`<k>` the next unused number) and telling it to write nothing else, and reply in at most 10 lines; the report opens with `## Verdict` holding `ruling: <choice> — <reason>` or `no ruling`".
   - §Rulings 3: the Fable batch adds "naming the report file `<state>/rulings-fable-<k>-report.md` and telling it to write nothing else, and reply in at most 10 lines; its `## Verdict` section holds one `### Item <id>` block per item with `ruling: <choice> — <reason>` or `no ruling`. Read only that section."
   - Each `write nothing else, and reply in at most 10 lines` sits on one line (the test counts three). Keep `each answer to a Blocker or High finding` and `which folds the critic into` (process-roles.test.sh).

- [ ] **Step 4: Run the suites**

Run: `cd plugins/dforge && timeout 120 bash tests/seats.test.sh && timeout 300 bash tests/review-route.test.sh && timeout 120 bash tests/process-roles.test.sh && timeout 120 bash tests/auto-default.test.sh && timeout 300 bash tests/auto-run-skills.test.sh`, then from the repository root `node scripts/validate-repository.mjs` and `timeout 120 /root/.local/bin/claude plugin validate plugins/dforge`.
Expected: PASS, every suite `0 failed`; validation clean.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/skills/writing-plans/references/plan-reviewer-prompt.md plugins/dforge/skills/writing-plans/SKILL.md \
  plugins/dforge/skills/brainstorming/references/architecture-critic-prompt.md plugins/dforge/skills/brainstorming/SKILL.md \
  plugins/dforge/reference/auto-run.md plugins/dforge/tests/seats.test.sh
git commit -m "feat(dforge): plan and spec seats write reports"
```

### Task 12: Final-review and standalone seats write report files

**Files:**
- Modify: `plugins/dforge/skills/requesting-code-review/references/code-reviewer.md` (Read-Only Review, Output Format, Placeholders, Reviewer returns, Example Output)
- Modify: `plugins/dforge/skills/requesting-code-review/SKILL.md` (step 2's diff-file block, the dispatch sentence, Placeholders, step 3, Example)
- Modify: `plugins/dforge/reference/final-review.md` (step 1's lens paragraph, lens prompt and reviewer sentence; step 3's dedupe; Fixing what it finds)
- Modify: `plugins/dforge/skills/closing-a-milestone/references/milestone-judge.md`, `plugins/dforge/skills/closing-a-milestone/SKILL.md` (steps 5 and 6)
- Modify: `plugins/dforge/skills/distilling-docs/references/distil-judge.md`, `plugins/dforge/skills/distilling-docs/SKILL.md` (What may be deleted, The judge reads the working tree, the dispatch)
- Modify: `plugins/dforge/skills/test-simplifier/references/simplify-judge.md` (Placeholders, both prompts)
- Modify: `plugins/dforge/skills/ui-ux/references/walkthrough.md` (§The judge)
- Modify: `plugins/dforge/skills/selecting-approaches/SKILL.md` (Rank, Run advisor)
- Modify: `plugins/dforge/README.md` (the role-agents paragraph)
- Modify: `evals/tiers/build-case.mjs` (`buildReview`: the `[REPORT_FILE]` fill and `info.report`), `evals/tiers/run-case.mjs` (`REVIEW`, the review branch of `runCell`), `evals/tiers/grade-review.mjs` (`gradeReview`: the file it grades)
- Test: `plugins/dforge/tests/seats.test.sh`, `plugins/dforge/tests/process-roles.test.sh`, `evals/tiers/tests/build.test.mjs`, `evals/tiers/tests/run.test.mjs`, `evals/tiers/tests/grade-review.test.mjs`, `evals/tiers/tests/stub-claude.mjs`

**Interfaces:**
- Consumes: Judge reports (Task 9); the plan-reviewer template's `[REPORT_FILE]` (Task 11)
- Produces: the tier harness's review report `<case>/work/.superpowers/sdd/eval/review-report.md`, named in `case.json` as `report`; the report files `<workspace>/final-review-report.md`, `<workspace>/lens-<id>.md`, `<workspace>/final-dedupe-report.md`, `<state>/review-<head7>-report.md`, `<state>/milestone-M<n>-audit-report.md`, `<state>/distil-<wave>-report.md`, `<state>/test-simplifier/<wave>/fault-report.md` and `ruling-report.md`, `<report name>.judge.md`, `<state>/approaches-<decision>-rank-report.md` and `-advisor-report.md`

**Items:** 3

**Implementer:** dforge:impl-opus-high
**Evaluation:** files 2 - spec 2 - coupling 1 - risk 1 = 6
**Override:** owner approved the contract-and-test task shape for this plan on 2026-10-26, before plan-lint's Rule S and assignment table allow it

Decisions this task embodies:
- Acceptance QA is not a judge seat: final-review.md dispatches it to `dforge:impl-sonnet-high`, and it already writes `<workspace>/acceptance-report.md`. It is left as it is.
- Every report outside a plan goes under `<state>`, which is gitignored, so the milestone, distillation and simplification judges still see a clean tree at the SHA they were given.
- The UI judge's file must still end with exactly `Verdict: ship <fingerprint>` or `Verdict: fix <fingerprint>`, because `scripts/ui-proof check` reads that last line. Its report opens with `## Verdict` and still ends with that line.
- code-reviewer.md must not contain a backticked or double-quoted `none` (typed-seats-and-drafting A5), so an empty section is described in words.
- The tier harness (`evals/tiers`) fills `code-reviewer.md` and `plan-reviewer-prompt.md` itself. It fills `[REPORT_FILE]` with `review-report.md` in the case's scratch directory, gives the review arm `Write`, keeps the 10-line reply as `reply.md`, and grades the report file `case.json` names; a review cell that wrote no report is `BLOCKED` (`cut=no-report`). A `case.json` without `report` (a cell run before this task) is still graded from its `review.md`. Between Task 11 and this task the harness's plan-review prompt carries an unfilled `[REPORT_FILE]`; no suite reads it and no eval runs mid-plan.

- [ ] **Step 1: Write the failing tests**

In `plugins/dforge/tests/seats.test.sh`, insert this block directly before its final `printf '\n%d passed, %d failed\n'` line, after Task 11's block (it uses `lacks`, `count_of`, `$CR`, `$RCR` and `$FR`):

```bash
# The final review's seats and the standalone verifiers follow the same report
# contract.
MJ="$P/skills/closing-a-milestone/references/milestone-judge.md"
CM="$P/skills/closing-a-milestone/SKILL.md"
DJ="$P/skills/distilling-docs/references/distil-judge.md"
DD="$P/skills/distilling-docs/SKILL.md"
SJ="$P/skills/test-simplifier/references/simplify-judge.md"
WT="$P/skills/ui-ux/references/walkthrough.md"
SA="$P/skills/selecting-approaches/SKILL.md"
RM="$P/README.md"
names "code reviewer: names the report file" "$CR" 'Write your full report to [REPORT_FILE] and write nothing else'
names "code reviewer: caps the reply" "$CR" 'Then reply in at most 10 lines'
check "code reviewer: the report opens with the Verdict section" "$(grep -qE '^ *## Verdict$' "$CR" && echo yes || echo no)" "yes"
names "code reviewer: the merge verdict key" "$CR" 'ready to merge: yes | no | with fixes'
names "code reviewer: the finding grammar" "$CR" '- [Critical|Important|Minor] <file>:<line> — <one-liner>'
names "code reviewer: the report file placeholder" "$CR" '`[REPORT_FILE]` — REQUIRED'
names "requesting review: the report file beside the diff" "$RCR" 'REPORT_FILE="$STATE_DIR/review-$(git rev-parse --short "$HEAD_SHA")-report.md"'
names "final review: the reviewer's report file" "$FR" '`[REPORT_FILE]` set to `<workspace>/final-review-report.md`'
names "final review: lens seats write their report" "$FR" 'each lens seat writes its report to `<workspace>/lens-<id>.md`'
names "final review: the lens finding grammar" "$FR" '- [Critical|Important|Minor] <file>:<line> — [lens:<id>] <one-liner>'
names "final review: the dedupe report file" "$FR" '`<workspace>/final-dedupe-report.md`'
check "final review: the lens and dedupe seats cap their reply" "$(count_of "$FR" 'write nothing else, and reply in at most 10 lines')" "2"
lacks "final review: the controller no longer saves lens replies" "$FR" 'save each reply to'
names "milestone judge: writes its report file" "$MJ" 'write nothing else'
names "milestone judge: caps the reply" "$MJ" 'reply in at most 10 lines'
check "milestone judge: the report opens with the Verdict section" "$(grep -qE '^ *## Verdict$' "$MJ" && echo yes || echo no)" "yes"
names "closing a milestone: the report file" "$CM" '`<state>/milestone-M<n>-audit-report.md`'
names "distil judge: names the report file" "$DJ" 'Write your full report to [REPORT_FILE] and write nothing else'
names "distil judge: caps the reply" "$DJ" 'Then reply in at most 10 lines'
check "distil judge: the report opens with the Verdict section" "$(grep -qE '^ *## Verdict$' "$DJ" && echo yes || echo no)" "yes"
names "distil judge: the per-source verdict line" "$DJ" '<source path>: CARRIED | MISSING | DISTORTED'
lacks "distilling: the judge's tools are stated as they are" "$DD" 'grants `Read, Grep, Glob, WebFetch` and'
check "simplify judge: both prompts name the report file" "$(count_of "$SJ" 'Write your full report to [REPORT_FILE] and write nothing else')" "2"
check "simplify judge: both prompts cap the reply" "$(count_of "$SJ" 'Then reply in at most 10 lines')" "2"
names "simplify judge: the ruling verdict key" "$SJ" 'verdict: KEPT | LOST | VIOLATED'
names "walkthrough judge: names the report file" "$WT" 'Write your full report to [REPORT_FILE] and write nothing else'
names "walkthrough judge: caps the reply" "$WT" 'Then reply in at most 10 lines'
names "walkthrough judge: the verdict key" "$WT" 'verdict: ship | fix [FINGERPRINT]'
lacks "walkthrough: the controller no longer saves the reply" "$WT" 'Save the reply verbatim'
check "approaches: the ranker and the advisor cap their reply" "$(count_of "$SA" 'write nothing else, and reply in at most 10 lines')" "2"
names "approaches: the ranking's report file" "$SA" '`<state>/approaches-<decision>-rank-report.md`'
lacks "README: the judges are no longer described as Write-free" "$RM" 'frontmatter omits `Edit`, `Write`, and `Agent`'
names "README: a judge writes only its report file" "$RM" 'a judge writes only its report file'
```

In `plugins/dforge/tests/process-roles.test.sh`, replace the line

```bash
names "final review: lens replies as files" "$FR" 'save each reply to `<workspace>/lens-<id>.md`'
```

with

```bash
names "final review: lens replies as files" "$FR" 'each lens seat writes its report to `<workspace>/lens-<id>.md`'
```

Apply this diff to the tier harness's tests (`stub-claude.mjs`'s `review` mode now writes the report file the way a judge does, and a new `noreport` mode replies without one):

```diff
diff --git a/evals/tiers/tests/build.test.mjs b/evals/tiers/tests/build.test.mjs
index 9bc512ce..7b9337e5 100644
--- a/evals/tiers/tests/build.test.mjs
+++ b/evals/tiers/tests/build.test.mjs
@@ -59,7 +59,10 @@ test('a code review case snapshots the head and hands over one diff file', () =>
   assert.match(prompt, /## What Was Implemented\n\nAdds the greet script\./);
   assert.match(prompt, new RegExp(`Read this file first: ${diffFile}`));
   assert.match(prompt, new RegExp(`for ${fx.planned.slice(0, 7)}\\.\\.${fx.greet.slice(0, 7)}`));
-  assert.doesNotMatch(prompt, /\[DESCRIPTION\]|\[PLAN_OR_REQUIREMENTS\]|\[DIFF_FILE\]|\[BASE_SHA\]|\[HEAD_SHA\]/);
+  assert.doesNotMatch(prompt, /\[DESCRIPTION\]|\[PLAN_OR_REQUIREMENTS\]|\[DIFF_FILE\]|\[BASE_SHA\]|\[HEAD_SHA\]|\[REPORT_FILE\]/);
+  assert.equal(info.report, join(info.work, '.superpowers/sdd/eval/review-report.md'));
+  assert.ok(prompt.includes(`Write your full report to ${info.report} and write nothing else`));
+  assert.deepEqual(JSON.parse(readFileSync(join(fx.work, 'codereview/case.json'), 'utf8')).report, info.report);
 });
 
 test('a plan review case hides the earlier verdict and supplies the criteria', () => {
@@ -69,6 +72,9 @@ test('a plan review case hides the earlier verdict and supplies the criteria', (
   const root = prompt.match(/Read the criteria file at (\S+)\/criteria\/plan-review\.md/)[1];
   assert.equal(existsSync(join(root, 'criteria/plan-review.md')), true);
   assert.match(readFileSync(prompt.match(/\*\*plan-lint output:\*\* (\S+)/)[1], 'utf8'), /was not run/);
+  assert.equal(info.report, join(info.work, '.superpowers/sdd/eval/review-report.md'));
+  assert.ok(prompt.includes(`Write your full report to ${info.report} and write nothing else`));
+  assert.doesNotMatch(prompt, /\[REPORT_FILE\]/);
   assert.throws(() => buildReview({ id: 'r-plan-bad', kind: 'plan', commit: fx.planned, plan: PLAN, spec: 'docs/none.md' }, join(fx.work, 'bad')), /docs\/none\.md is missing/);
 });
 
diff --git a/evals/tiers/tests/grade-review.test.mjs b/evals/tiers/tests/grade-review.test.mjs
index c3f3356a..b2796e36 100644
--- a/evals/tiers/tests/grade-review.test.mjs
+++ b/evals/tiers/tests/grade-review.test.mjs
@@ -53,6 +53,25 @@ test('gradeReview appends one grade per defect and returns the grading row', asy
   assert.match(call.prompt, /<rubric>\n# Rubric[\s\S]*<review>\nThe refusal search/);
 });
 
+test('gradeReview reads the report file case.json names, not the reply', async () => {
+  const dir = armDir(4, 'r-code-fixture', 'judge-opus@high');
+  mkdirSync(join(dir, 'work'), { recursive: true });
+  const report = join(dir, 'work', 'review-report.md');
+  writeFileSync(report, '## Verdict\nready to merge: no\n\n## Findings\n- [Important] src/greet.sh:1 — The refusal search is unanchored, so any line matches.\n');
+  writeFileSync(join(dir, 'case.json'), JSON.stringify({ id: 'r-code-fixture', kind: 'review', work: join(dir, 'work'), report }));
+  writeFileSync(join(dir, 'reply.md'), 'A ten-line digest that names no defect.');
+  reply([{ id: 'D1', found: true, severity: 'Important', quote: 'The refusal search is unanchored, so any line matches.' }]);
+  modes(fx.stub, 'grade');
+  const row = await gradeReview({ rep: '4', id: 'r-code-fixture', arm: 'judge-opus@high', pass: '1', grader });
+  assert.deepEqual([row.outcome, row.detail], ['GRADED', 'found=1/2']);
+  assert.match(lastCall().prompt, /<review>\n## Verdict\nready to merge: no/);
+  rmSync(report);
+  const calls = readFileSync(join(fx.stub, 'calls.log'), 'utf8');
+  const gone = await gradeReview({ rep: '4', id: 'r-code-fixture', arm: 'judge-opus@high', pass: '2', grader });
+  assert.deepEqual([gone.outcome, gone.detail], ['GRADED', 'found=0/2']);
+  assert.equal(readFileSync(join(fx.stub, 'calls.log'), 'utf8'), calls);
+});
+
 test('a grader reply without JSON, or a rate limit, is NOT_RUN and writes no grade', async () => {
   reviewed(2, 'judge-opus@high');
   modes(fx.stub, 'blocked');
diff --git a/evals/tiers/tests/run.test.mjs b/evals/tiers/tests/run.test.mjs
index c9604108..297053a3 100644
--- a/evals/tiers/tests/run.test.mjs
+++ b/evals/tiers/tests/run.test.mjs
@@ -78,14 +78,19 @@ test('a harness failure costs one NOT_RUN row, not the stage', async () => {
   assert.match(broken.detail, /^error: snapshot no-such-commit/);
 });
 
-test('a review cell runs read-only at the arm effort and keeps the review', async () => {
+test('a review cell writes only its report, at the arm effort, and keeps report and reply', async () => {
   writeFileSync(join(fx.stub, 'review.md'), '### Issues\nThe script greets in lower case only.\n');
   const row = await cell('review', 'judge-opus@medium', review);
   assert.deepEqual([row.outcome, row.pool, row.row], ['REVIEWED', 'review', '']);
   const call = lastCall();
-  assert.deepEqual([call.args[call.args.indexOf('--tools') + 1], call.args[call.args.indexOf('--effort') + 1]], ['Read,Grep,Glob', 'medium']);
+  assert.deepEqual([call.args[call.args.indexOf('--tools') + 1], call.args[call.args.indexOf('--effort') + 1]], ['Read,Grep,Glob,Write', 'medium']);
   assert.equal(existsSync(join(call.cwd, '.superpowers/sdd/eval/review.diff')), true);
-  assert.match(readFileSync(join(armDir(1, 'r-code-fixture', 'judge-opus@medium'), 'review.md'), 'utf8'), /lower case only/);
+  const dir = armDir(1, 'r-code-fixture', 'judge-opus@medium');
+  assert.match(readFileSync(JSON.parse(readFileSync(join(dir, 'case.json'), 'utf8')).report, 'utf8'), /lower case only/);
+  assert.match(readFileSync(join(dir, 'reply.md'), 'utf8'), /^Report: /);
+  assert.equal(existsSync(join(dir, 'review.md')), false);
+  const silent = await cell('noreport', 'judge-opus@medium', review);
+  assert.deepEqual([silent.outcome, silent.detail], ['BLOCKED', 'cut=no-report']);
   const cut = await cell('budget', 'judge-opus@medium', review);
   assert.deepEqual([cut.outcome, cut.detail], ['BLOCKED', 'cut=budget']);
 });
diff --git a/evals/tiers/tests/stub-claude.mjs b/evals/tiers/tests/stub-claude.mjs
index 18ee53fc..b03086f3 100644
--- a/evals/tiers/tests/stub-claude.mjs
+++ b/evals/tiers/tests/stub-claude.mjs
@@ -2,7 +2,7 @@
 // $STUB_DIR/modes, records its arguments in $STUB_DIR/calls.log, acts in its
 // working directory as that mode says, and prints the JSON a headless run
 // prints.
-import { appendFileSync, existsSync, readFileSync, writeFileSync } from 'node:fs';
+import { appendFileSync, existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
 import { join } from 'node:path';
 import { spawnSync } from 'node:child_process';
 
@@ -25,6 +25,7 @@ else if (mode === 'blocked') { reply('**Status:** BLOCKED - the brief is unclear
 else if (mode === 'budget') { apply(); reply('', { is_error: true, subtype: 'error_max_budget_usd' }); process.exitCode = 1; }
 else if (mode === 'limit') { reply("You've hit your usage limit", { is_error: true, total_cost_usd: 0 }); process.exitCode = 1; }
 else if (mode === 'crash') { console.error('boom'); process.exitCode = 2; }
-else if (mode === 'review') { reply(file('review.md')); }
+else if (mode === 'review') { mkdirSync('.superpowers/sdd/eval', { recursive: true }); writeFileSync('.superpowers/sdd/eval/review-report.md', file('review.md')); reply('Report: .superpowers/sdd/eval/review-report.md'); }
+else if (mode === 'noreport') { reply('A review with no report file.'); }
 else if (mode === 'grade') { reply(file('grade.json')); }
 else { console.error(`stub-claude: unknown mode ${mode}`); process.exitCode = 2; }
```

- [ ] **Step 2: Run them to verify they fail**

Run: `cd plugins/dforge && timeout 120 bash tests/seats.test.sh; timeout 120 bash tests/process-roles.test.sh`
Expected: FAIL — seats: every check in the new block (no final-review or standalone seat names a report file; `README.md` still says the judges omit `Write`; `distilling-docs` still lists the four-tool set). process-roles: `final review: lens replies as files`. Then `timeout 300 node --test evals/tiers/tests/*.test.mjs` from the repository root: FAIL — build: the code-review and plan-review cases (no `info.report`, no report sentence); run: the review cell (tools `Read,Grep,Glob`, the reply saved as `review.md`); grade-review: `reads the report file case.json names` (it grades `review.md`); grid: the three review-stage cases, because the stub now replies with a digest and writes the review to the report file, which today's run-case and grader never read: 7 fail, 62 pass. With Step 3 done the suite ran 69 of 69 passing in a prototype.

- [ ] **Step 3: Implement**

Task 9 Step 3 item 2's wording rules apply. Another task in this plan also edits `README.md` (the plan-shape and loop paragraphs); this task touches only the role-agents paragraph.

1. **code-reviewer.md.**
   - Read-Only Review: `and change nothing.` becomes `and change nothing in the repository: your one write is the report file.`
   - `## Output Format` (to `## Critical Rules`) becomes:

     ```text
         ## Output Format

         Write your full report to [REPORT_FILE] and write nothing else: it is
         the only file you may create or change. Then reply in at most 10 lines:
         the verdict, the count of findings by severity, and the report path.
         The report, written without the indent:

             ## Verdict
             ready to merge: yes | no | with fixes

             ## Strengths
             <what is well done, specifically>

             ## Findings
             - [Critical|Important|Minor] <file>:<line> — <one-liner>

             ## Recommendations
             <improvements for code quality, architecture, or process>

             ## Assessment
             <one or two sentences of technical assessment>

         One line per finding, most severe first: Critical for bugs, security
         issues, data loss risks and broken functionality; Important for
         architecture problems, missing features, poor error handling and test
         gaps; Minor for code style, optimization and documentation polish.
         `<line>` is 0 when no single line applies. Below each finding, on lines
         indented by two spaces: what is wrong, why it matters, and how to fix
         it when that is not obvious. Leave a section with nothing in it empty.
     ```
   - Placeholders gain `` `[REPORT_FILE]` — REQUIRED: the file the reviewer writes its report to: `<workspace>/final-review-report.md` in the final review, or the `$REPORT_FILE` requesting-code-review step 2 sets outside a plan ``; `**Reviewer returns:** …` becomes `**Reviewer writes** its report to [REPORT_FILE] and **returns** a reply of at most 10 lines.`
   - Example Output: the example becomes a report in the new shape (`## Verdict` / `ready to merge: with fixes`, `## Strengths`, `## Findings` with the same three issues as `- [Important] index-conversations:1 — …`, `- [Important] search.ts:25 — …`, `- [Minor] indexer.ts:130 — …` and their fixes on indented lines, `## Recommendations`, `## Assessment`).
   Keep `Subagent (dforge:judge-opus):`, `` `[DIFF_FILE]` — REQUIRED ``, and `would it fail if the code violated spec statement A<n>?`.

2. **requesting-code-review SKILL.md.**
   - In step 2's block, directly after the `DIFF_FILE=…` line, add the line `  REPORT_FILE="$STATE_DIR/review-$(git rev-parse --short "$HEAD_SHA")-report.md" &&`. Leave the other lines of the block as they are (seats.test.sh pins three of them).
   - "The judge is read-only and has no shell: the diff file is its view of the change." becomes "The judge has no shell and writes only its report file: the diff file is its view of the change, and its reply of at most 10 lines names the report." Keep "Dispatch `dforge:judge-opus` as `subagent_type`" on its line.
   - Placeholders gain `` `[REPORT_FILE]` - REQUIRED: the `$REPORT_FILE` path above ``. Step 3 begins `Read the report's ## Verdict and ## Findings sections, then:`. In the Example, add `REPORT_FILE: .dforge/review-3df7661-report.md` to the dispatch lines and replace `[Subagent returns]:` and its lines with `[Subagent replies]: ready to merge: with fixes — 1 Important, 1 Minor — .dforge/review-3df7661-report.md`.

3. **final-review.md.**
   - Step 1, Lenses: the sentence "Then save each reply to `<workspace>/lens-<id>.md`:" goes; the sentence before it ends instead "…; on a Codex host, a native judge at rank 8 or above, and each lens seat writes its report to `<workspace>/lens-<id>.md`:", continuing with "the Claude list for step 3 is …" as today. Keep "each lens seat writes its report to `<workspace>/lens-<id>.md`" unbroken on one line (process-roles.test.sh and seats.test.sh).
   - The lens prompt block becomes:

     ```text
     You are a specialist reviewer. Read the lens at <criteria path>: its
     criteria are defect patterns, not a rubric, so do not score them. Review
     the branch diff in <package path> against the spec <spec path> and the
     plan <plan path>. Write your full report to <workspace>/lens-<id>.md,
     write nothing else, and reply in at most 10 lines: the counts by
     severity and the report path. The report opens with `## Verdict` holding
     `findings: <c> Critical, <i> Important, <m> Minor`, then lists each hit
     under `## Findings`, most severe first, as
     `- [Critical|Important|Minor] <file>:<line> — [lens:<id>] <one-liner>`
     followed by at most three lines indented by two spaces: what fails and
     the fix. Report at most ten
     findings. [Report Critical and Important findings only; leave Minor ones
     out.] With none, leave Findings empty.
     ```

     (process-roles.test.sh pins `[Report Critical and Important findings only; leave Minor ones` on one line, and `write nothing else, and reply in at most 10 lines` is counted by seats.test.sh.)
   - The reviewer sentence: before "with `[DIFF_FILE]` set to the package path," add "`[REPORT_FILE]` set to `<workspace>/final-review-report.md`," (one line).
   - Step 3, Dedupe and verify: "dispatch a fresh `dforge:judge-opus` once, given both lists." becomes the text below, keeping `<workspace>/final-dedupe-report.md` and "write nothing else, and reply in at most 10 lines" unbroken on one line each:

     ```text
     dispatch a fresh `dforge:judge-opus` once, given both lists' report paths
     (the Claude review's and the lens reports, and the Codex round's JSON),
     with the report file `<workspace>/final-dedupe-report.md`: tell it to
     write its full report there, write nothing else, and reply in at most 10 lines.
     The report opens with `## Verdict` holding `confirmed: <k>` and
     `rejected: <k>`, and lists each merged finding under `## Findings` as
     `- [<severity>] <file>:<line> — [CONFIRMED|REJECTED] [claude|codex|both] <one-liner>`,
     its evidence on indented lines.
     ```
   - Fixing what it finds: after `fix them in ONE wave with the complete list`, add `, given as report paths (the dedupe report with two lists; the Claude review's and lens reports and the [qa] findings with one), never pasted`.

4. **milestone-judge.md.** The intro's `You can read the repository; you cannot run anything.` becomes `You can read the repository and write one file, the report file; you cannot run anything.` Inputs gain `- Report file: <state>/milestone-M<n>-audit-report.md.` `## Output` begins with `Write your full report to the report file named above and write nothing else. Then reply in at most 10 lines: the verdict, the GAP and UNVERIFIABLE counts, and the report path. The report:` and its fenced block becomes:

   ```text
   ## Verdict
   Milestone: M<n> <name> at <sha7>
   Verdict: CLOSE | KEEP OPEN
   GAPs: <count>
   UNVERIFIABLE: <count>

   ## Items

   | # | Source | Item | Ruling | Evidence or reason |
   |---|---|---|---|---|
   | 1 | registers/<file>.md #3 | <item> | MET | src/billing/refund.ts:42, tests/refund.test.ts "refunds a paid invoice" |
   ```

   (project-status.test.sh pins `Verdict: CLOSE | KEEP OPEN`; process-roles.test.sh pins the A<n> evidence sentence in Method, unchanged.)
   **closing-a-milestone SKILL.md**: step 5's dispatch adds `and the report file <state>/milestone-M<n>-audit-report.md, outside the tree so it stays clean` (`` `<state>/milestone-M<n>-audit-report.md` `` backticked, on one line); step 6 begins `Read the report's ## Verdict section and its GAP and UNVERIFIABLE rows.`

5. **distil-judge.md.** Placeholders gain `` `[REPORT_FILE]` — `<state>/distil-<wave>-report.md`, `<wave>` the wave's number ``. In the prompt, `You are read-only: do not edit any file.` becomes `You are read-only on the repository: do not edit any file there. Write your full report to [REPORT_FILE] and write nothing else: it is the only file you may create or change. Then reply in at most 10 lines: one verdict per source file and the report path.` (those two phrases on one line each; `read-only` stays). Its closing `Output: …` paragraph becomes: "The report opens with this section, then `## Enumeration`, `## Mapping` and `## Rewrites`, in the order the steps above produce them:" followed by the skeleton, indented four spaces:

   ```text
       ## Verdict
       commit: [COMMIT]
       <source path>: CARRIED | MISSING | DISTORTED
   ```

   with the line after it: `one verdict line per source file. Enumerate before you map: the Verdict section comes first in the file, never first in your work.` Keep `Name [COMMIT] in your report`, `one verdict per source file`, `numbered list`, `maps to`, `unedited since [COMMIT]` (distilling-docs.test.sh).
   **distilling-docs SKILL.md**: "a judge whose tools are `Read, Grep, Glob, WebFetch` cannot enumerate" becomes "a judge with no shell cannot enumerate"; "grants `Read, Grep, Glob, WebFetch` and **no Bash**" becomes "grants `Read, Grep, Glob, WebFetch, Write` (`Write` for its report file only) and **no Bash**"; the "Dispatch dforge:judge-opus with [distil-judge.md](…)" sentence adds ", its `[REPORT_FILE]` set to `<state>/distil-<wave>-report.md` (outside the tree)".

6. **simplify-judge.md.** Placeholders gain `` `[REPORT_FILE]` — `<state>/test-simplifier/<wave>/fault-report.md` for the fault prompt, `<state>/test-simplifier/<wave>/ruling-report.md` for the ruling prompt ``. In each prompt, after `You are read-only: do not edit any file.` add `Write your full report to [REPORT_FILE] and write nothing else: it is the only file you may create or change. Then reply in at most 10 lines: the verdict and the report path.` (on one line each phrase, as before). The fault prompt's `Output: one numbered list of faults per candidate, nothing else.` becomes `The report opens with ## Verdict holding faults: <n> for <k> candidates, then one numbered list of faults per candidate under ## Faults, nothing else.` The ruling prompt's `Output: …` paragraph becomes `The report opens with ## Verdict holding verdict: KEPT | LOST | VIOLATED and commit: [COMMIT], then the step 1 finding, the numbered assertion mapping, the evidence finding and the guard check, each under its own ## heading, nothing else.` with `verdict: KEPT | LOST | VIOLATED` on one line. Keep the `- KEPT -`, `- LOST -`, `- VIOLATED -` lines, `Map assertions before ruling`, `Any production file`, `the exact edit`, `[COMMIT] in your report` (test-simplifier.test.sh).

7. **walkthrough.md**, §The judge. In the prompt, after the `**Fingerprint:**` line add `**Report file:** [REPORT_FILE]`, and replace `Then answer as the criteria's Output section says, ending with exactly one line: "Verdict: ship [FINGERPRINT]" or "Verdict: fix [FINGERPRINT]".` with:

   ```text
       Write your full report to [REPORT_FILE] and write nothing else: it is
       the only file you may create or change. Then reply in at most 10 lines:
       the verdict, the scores, the count of disputed items, and the report
       path. The report opens with a Verdict section, written without the indent:

           ## Verdict
           verdict: ship | fix [FINGERPRINT]
           scores: <criterion> <1-20> / …

       then answers as the criteria's Output section says, and ends with
       exactly one line: "Verdict: ship [FINGERPRINT]" or "Verdict: fix [FINGERPRINT]".
   ```

   After the block, "Save the reply verbatim beside the report as `<report name>.judge.md`, then set the report header's" becomes "Its `[REPORT_FILE]` is `<report name>.judge.md` beside the report. When it returns, set the report header's". "A judge reply that does not end with the verdict line is re-dispatched once with that instruction repeated." becomes "A judge file that does not end with the verdict line is re-dispatched once with that instruction repeated."

8. **selecting-approaches SKILL.md.** **Rank.**: after "Dispatch one `dforge:judge-opus` to run the ring" (keep that phrase on one line, review-route.test.sh) add to the paragraph: "It writes its full report to `<state>/approaches-<decision>-rank-report.md` (`<decision>` a short slug of the decision): write nothing else, and reply in at most 10 lines. The report opens with `## Verdict` holding `winner: <candidate>` and `wins: A <a> / B <b> / C <c>`, then the three comparisons and the grafts." **Run advisor**: "dispatch one judge to score it" gains ", naming the report file `<state>/approaches-<decision>-advisor-report.md`: write nothing else, and reply in at most 10 lines; its `## Verdict` section holds `verdict: sound | wrong`". Each "write nothing else, and reply in at most 10 lines" sits on one line (the test counts two).

9. **README.md**, the role-agents sentences, from "Four" / "read-only role agents - the judges" through "request in a prompt.", become the text below; keep "a judge writes only its report file" unbroken on one line:

   ```text
   Four role agents - the judges `judge-opus`, `judge-sonnet-high` and
   `judge-fable` (an auto run's spec review and rulings, or a human override),
   and `scout-sonnet` - whose `tools:` frontmatter omits `Edit`, `Bash` and
   `Agent`, so a reviewer that cannot spawn subagents is a fact about the
   registry rather than a request in a prompt. The scout carries no `Write`
   either; a judge writes only its report file, whose path its prompt names,
   replies in at most ten lines, and `scripts/task-step verdict` checks that no
   tracked file changed during a task review.
   ```

10. **The tier harness.**
    - `build-case.mjs`, `buildReview`: `const report = join(scratch, 'review-report.md')`. Both fills (the code-reviewer one and the plan-reviewer one) add `'[REPORT_FILE]': report` (`lib/prompt.mjs`'s `fill` throws on a key the template lacks, which is why this lands after Task 11 and with this task's code-reviewer change); the code case's `mkdirSync(scratch, …)` already runs, and the plan case creates `scratch` through its `plugin/criteria` directory. `info` becomes `{ id: c.id, kind: 'review', work, report }`, so `case.json` names it.
    - `run-case.mjs`: `REVIEW.tools` becomes `['Read', 'Grep', 'Glob', 'Write']`. In `runCell`'s review branch, after the `inv.kind !== 'ok'` check, write `inv.text` to `join(dir, 'reply.md')` (no longer `review.md`); when `built.info.report` does not exist, return `{ ...row, outcome: 'BLOCKED', detail: 'cut=no-report' }`; otherwise `REVIEWED` as today.
    - `grade-review.mjs`, `gradeReview`: the file graded is `case.json`'s `report` when `join(dir, 'case.json')` exists and holds one, else `join(dir, 'review.md')` (cells run before this task). When that file is missing, every defect is missed with no grader call, as today for a missing `review.md`. Update the function's comment to name the report file.

- [ ] **Step 4: Run the suites**

Run: `timeout 300 node --test evals/tiers/tests/*.test.mjs` from the repository root, then `cd plugins/dforge && timeout 120 bash tests/seats.test.sh && timeout 120 bash tests/process-roles.test.sh && timeout 120 bash tests/inline-mode.test.sh && timeout 300 bash tests/review-route.test.sh && timeout 120 bash tests/distilling-docs.test.sh && timeout 120 bash tests/test-simplifier.test.sh && timeout 120 bash tests/project-status.test.sh && timeout 120 bash tests/ui-ux-skill.test.sh && timeout 300 bash tests/ui-proof.test.sh && timeout 300 bash tests/typed-seats-and-drafting.acceptance.sh A5 A6`, then from the repository root `node scripts/validate-repository.mjs` and `timeout 120 /root/.local/bin/claude plugin validate plugins/dforge`.
Expected: PASS, every suite `0 failed`; validation clean.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/skills/requesting-code-review/references/code-reviewer.md plugins/dforge/skills/requesting-code-review/SKILL.md \
  plugins/dforge/reference/final-review.md \
  plugins/dforge/skills/closing-a-milestone/references/milestone-judge.md plugins/dforge/skills/closing-a-milestone/SKILL.md \
  plugins/dforge/skills/distilling-docs/references/distil-judge.md plugins/dforge/skills/distilling-docs/SKILL.md \
  plugins/dforge/skills/test-simplifier/references/simplify-judge.md plugins/dforge/skills/ui-ux/references/walkthrough.md \
  plugins/dforge/skills/selecting-approaches/SKILL.md plugins/dforge/README.md \
  plugins/dforge/tests/seats.test.sh plugins/dforge/tests/process-roles.test.sh \
  evals/tiers/build-case.mjs evals/tiers/run-case.mjs evals/tiers/grade-review.mjs \
  evals/tiers/tests/build.test.mjs evals/tiers/tests/run.test.mjs evals/tiers/tests/grade-review.test.mjs evals/tiers/tests/stub-claude.mjs
git commit -m "feat(dforge): final-review seats write reports"
```

### Task 13: Describe the new plan shape and loop in the README

**Files:**
- Modify: `plugins/dforge/README.md` (the escalation-ladder paragraph, the inline-mode paragraph naming three fix rounds, "What a plan looks like", "Differences from upstream 6.3.0" items on cache-aware resumes and inline escalation)
- Test: `plugins/dforge/tests/settings-skills.test.sh`

**Interfaces:**
- Consumes: Contracts "Ladder", "Review tier", "Group review", "Fix loop", "Waves", "Judge reports" — the README restates them for a reader; it defines nothing.
- Produces: none

**Items:** 1, 2, 3

**Implementer:** dforge:impl-sonnet-low
**Evaluation:** files 0 - spec 1 - coupling 0 - risk 0 = 1

- [ ] **Step 1: Write the failing tests**

Insert above the final `printf '\n%d passed, %d failed\n'` line of `plugins/dforge/tests/settings-skills.test.sh`:

```bash
# The README describes the contract-and-test plan shape, review groups, the
# two-round fix loop, the wave check cadence and the judge report files.
names "README: tasks carry tests, not implementation code" "$P/README.md" 'carries its interfaces and the complete code of its tests'
names "README: low-risk tasks are reviewed in groups" "$P/README.md" 'reviewed in groups'
names "README: two fix rounds" "$P/README.md" 'at most two fix rounds'
names "README: the full check runs every third wave" "$P/README.md" 'every third wave'
names "README: judges write their report to a file" "$P/README.md" 'writes its full report to a file'
check "README: no five-round loop" "$(grep -cE 'fix rounds 4|rounds 1 to 3|and 5, at the BLOCKED' "$P/README.md")" "0"
```

- [ ] **Step 2: Run them to verify they fail**

Run: `timeout 120 bash plugins/dforge/tests/settings-skills.test.sh`
Expected: FAIL on the six new checks — the README still describes five fix rounds, per-task reviews only and code-carrying tasks.

- [ ] **Step 3: Implement**

Edit `plugins/dforge/README.md` only, keeping each paragraph's place and voice. Task 2 already rewrote the Rule S and lane-gate paragraphs, Task 3 the plan-review sentence and Task 12 the role-agents paragraph; leave those as they are.

1. The escalation-ladder paragraph ("Used at fix rounds 4 and 5, at the BLOCKED handler, and at round 3 when the re-review reports stalled progress."): the ladder is used at fix round 2 and at the BLOCKED handler; a task gets "at most two fix rounds", then the ruling seat. Drop the stalled-progress clause.
2. Add one paragraph after the escalation paragraph: a task at risk 0 or 1 with a total under 5 is "reviewed in groups" — one judge dispatch for up to four such tasks, or for a wave's such tasks before they merge — while riskier tasks keep their own review; waves run the plan's full integration check "every third wave", after any risk-3 wave and after the last, and a red baseline whose failures do not grow counts as a pass.
3. Add one sentence to the criteria-scored-reviews paragraph: every judge "writes its full report to a file" in the plan's workspace and replies in at most ten lines; `scripts/task-step verdict` prints the digest the session reads.
4. "What a plan looks like": say a task "carries its interfaces and the complete code of its tests", and gives implementation code only for configuration values, generated-file or migration commands and constants the spec names. Change the example's Evaluation line to `files 1 - spec 2 - coupling 1 - risk 1 = 5`.
5. "Differences from upstream 6.3.0", item 4 ("Fix rounds 1 to 3 resume the implementer…"): round 1 resumes the implementer while its cache is warm, otherwise a fresh copy on the same tier; round 2 goes to the successor rung. Leave the inline-mode sentences about escalating after three fix rounds unchanged: inline mode's own trigger did not change.

- [ ] **Step 4: Run the suites**

Run: `timeout 120 bash plugins/dforge/tests/settings-skills.test.sh` and `node scripts/validate-repository.mjs`
Expected: PASS, 0 failed.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/README.md plugins/dforge/tests/settings-skills.test.sh
git commit -m "docs(dforge): describe contract plans and review groups"
```

