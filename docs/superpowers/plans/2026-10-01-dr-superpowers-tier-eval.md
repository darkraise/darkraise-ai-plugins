# dr-superpowers Tier Evaluation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: the skill the **Execution:** line names — dr-superpowers:subagent-driven-development for `subagent`, dr-superpowers:executing-plans for `inline`. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a harness that replays this repository's past plan tasks and reviews on cheaper agents, run one repetition of it, and report which assignment rows and review seats the results allow to move.

**Architecture:** Node scripts under `evals/tiers/` read the plan history through the plugin's own plan reader, snapshot a task's base commit into a scratch repository, run one headless `claude -p` call per case and arm, and grade the result with the task's historical tests. A resumable grid runs the stages, a pure module applies the spec's decision rules, and every harness test runs against a stub `claude` on a throwaway fixture repository. Tasks 1 to 16 build and pin the harness and its cases with no model call; Tasks 17 to 21 are the paid run and its report, and belong to a fresh session.

**Tech Stack:** Node 20 or later (ESM, `node:test`, no dependencies), `git`, `bash`, `tar`; the Claude Code CLI for the paid stages only.

**Spec:** docs/superpowers/specs/2026-10-01-dr-superpowers-tier-eval-design.md

**Execution:** inline — `claude --model sonnet --effort high` — no task totals 5 or more and none is at risk 3, so no task is delegated; the highest self-implemented total is 4

**Plan review:** 2026-10-01 — dr-superpowers:judge-opus — executability 16 / coherence 17 / coverage 18 / assumptions 15 (round 2)

## Global Constraints

- Task 1 starts from a tree with no harness in it: `git status --short -- evals scripts/test-all.mjs` prints nothing. If it prints anything, stop and report; do not overwrite or reuse what is there.
- Every path the harness owns is under `evals/tiers/`. The only files touched outside it are `scripts/test-all.mjs` (Task 13), the results note and the register (Task 21).
- Never change anything under `plugins/dr-superpowers/` while this plan runs: the manifest pins a start commit and `run-grid.mjs` refuses to run when the plugin differs from it.
- Node ESM (`.mjs`), no dependencies, POSIX only. Run every command from the repository root.
- No harness test may call a model. Tests reach the CLI only through `TIER_EVAL_CLAUDE`, which the fixture points at the stub.
- Give every test and CLI command a timeout: `timeout 300 node --test evals/tiers/tests/<name>.test.mjs` for one test file.
- Comments explain why, never what, and never mention this plan or a task.
- Commit messages: `<type>(<scope>): <subject>`, subject at most 50 characters, imperative, no period. English only.
- Constants the spec fixes: at most 8 cases per row and pool; fewer than 4 stripped cases makes a move an owner ruling; timeouts of 1800 seconds for an implementation run, 1200 for a review run and 600 for a grading; concurrency 2; `--max-budget-usd 5` per run; a repetition stops at 250 notional dollars.
- Tasks 17 to 20 call a model and draw on the owner's subscription limits. Run them only in a fresh session, only after the owner says to start, and never raise a cap, the concurrency or a timeout to get a stage through.
- Outcome words are exactly `PASS`, `FAIL`, `BLOCKED`, `NOT_RUN`, `EXCLUDED`, `REVIEWED` and `GRADED`.

## Contracts

**Environment.** `TIER_EVAL_ROOT` (repository whose history holds the cases; default the repository holding the harness), `TIER_EVAL_DATA` (directory holding `arms.json`, `cases/` and `results/`; default `evals/tiers`), `TIER_EVAL_WORK` (snapshots and transcripts; default `~/.cache/dr-tier-eval`), `TIER_EVAL_CLAUDE` (the CLI to run; default `claude`). Test-only: `TIER_EVAL_JOBS`, `TIER_EVAL_CAP_USD`, `STUB_DIR`.

**`lib/sh.mjs`** (Task 2)
- `ROOT`, `DATA`, `WORK`, `PLUGIN` — absolute paths; `PLUGIN` is always `plugins/dr-superpowers` beside the harness.
- `sh(cmd, args, opts?)` → `{ code, out, err }`, synchronous, `cwd` defaults to `ROOT`.
- `git(args, opts?)` → stdout string; throws `git <args>: <stderr>` on a non-zero exit.
- `run(cmd, args, { cwd, seconds, input, env }?)` → `Promise<{ code, out, err, timedOut }>`; kills the child's process group at the timeout and whenever the harness process exits; on `SIGINT` or `SIGTERM` the harness exits 130.

**`lib/plan.mjs`** (Task 2)
- `tasks(planFile)` → `[{ n, title }]`; `taskText(planFile, n)` → string or `null`.
- `evaluation(text)` → `{ files, spec, coupling, risk, total }` or `null` unless exactly one Evaluation line parses.
- `commitMessages(text)` → distinct first `-m` messages; `filesBlock(text)` → `{ allowed, tests }`.
- `taskBrief(planFile, n, dir)` → the brief text; throws on a non-zero `task-brief` exit.

**`lib/prompt.mjs`** (Task 3): `template(file)` → prompt body string; `fill(body, values)` → string, throws `the template has no <key>`.

**`lib/strip.mjs`** (Task 3): `MARKER` (string); `isTestPath(path)`; `addedLines(base, result)` → `Set<string>`; `strip(brief, added)` → `{ text, removed }`.

**`lib/snapshot.mjs`** (Task 4): `snapshot(commit, dir, drop = [])` → the snapshot's one commit sha.

**`lib/grade.mjs`** (Task 4)
- `overlayTests(dir, result, tests)` → boolean; `runTests(dir, tests)` → `Promise<{ pass, failed }>`.
- `changedFiles(dir, since)` → sorted paths, never under `.superpowers/`.
- `statusWord(message)` → `DONE_WITH_CONCERNS`, `NEEDS_CONTEXT`, `BLOCKED`, `DONE` or `null`.
- `outcome({ testsPass, outside, status, cutShort })` → `PASS`, `FAIL` or `BLOCKED`.

**`lib/cases.mjs`** (Task 5)
- `CAP` (8), `MANIFEST` (path of `cases/manifest.tsv` under `DATA`).
- `plans(start)`, `planAt(commit, plan, dir)` → path or `null`.
- `candidates(start)` → `[{ plan, task, title, reason }]` or, when eligible, `[{ plan, task, title, base, result, axes, allowed, tests }]`.
- `golden(c)` → `Promise<null | reason>`, the reason `the brief does not build` included; `brief(c, dir)` → brief text; `strippedRow(c)` → row number or `null`.
- `slug(plan)`; `select(cases)` → at most `CAP` cases; `readManifest(file = MANIFEST)` → `{ start, cases }` with `row` and `task` as numbers.

**`lib/claude.mjs`** (Task 7)
- `agent(arm)` → `{ model, effort, body }`; an arm is `<agent>` or `<agent>@<effort>`.
- `invoke({ model, effort, body, prompt, cwd, tools, seconds, dir })` → `Promise<{ kind, text, cost, seconds, turns, model }>`, `kind` one of `ok`, `timeout`, `budget`, `cut` (an error after the run spent something), `limit`, `error` (an error at zero cost); writes `agent.md`, `prompt.txt`, `output.json` and `stderr.txt` into `dir`.
- `classify({ out, err, code, timedOut }, elapsedSeconds)` → the same shape.

**`lib/results.mjs`** (Task 9)
- `RESULTS`, `GRADES` (paths under `DATA/results/`).
- `RESULT_COLUMNS` = `rep stage case pool row arm outcome model cost seconds turns detail`; `GRADE_COLUMNS` = `rep case arm pass defect found severity quote`.
- `armDir(rep, id, arm)` → `WORK/rep<rep>/<id>/<arm with @ written -at->`.
- `readTsv(file)` → row objects (`[]` when the file is missing); `appendTsv(file, columns, row)`; `scored(rows, rep, id, arm)` → the last row that is not `NOT_RUN`, or `undefined`.

**`lib/decide.mjs`** (Task 11): `MIN_STRIPPED` (4); `decideRow(arms, cases, cell, thin = true)` → `{ verdict, notes, stats }`; `decideReview(arms, grades)` → `[{ arm, found, of, underGraded, verdict, missedCritical }]`; `graderDisagreements(grades, pass = 1)` → `{ repeated, disagreements }`, comparing pass `pass + 1` with `pass`.

**Scripts**
- `build-manifest.mjs` (Task 6): writes `cases/manifest.tsv` and `cases/excluded.tsv`; exit 0, or 2 when the plugin has uncommitted changes.
- `build-case.mjs` (Task 8): `reviewCases()`, `buildCase(c, dir)` and `buildReview(c, dir)` → `{ info, prompt }`, `findCase(id)`; `info` is `{ id, kind, work, initial, result, allowed, tests }` for an implementation case and `{ id, kind, work }` for a review case.
- `grade-case.mjs` (Task 8): `gradeImpl(info, inv)` → `Promise<{ outcome, detail }>`.
- `run-case.mjs` (Task 9): `runCell({ rep, stage, c, arm })` → `Promise<row>` with the `RESULT_COLUMNS` keys; it never rejects, a harness exception is a `NOT_RUN` row whose detail starts `error: `. `run-case.mjs CASE ARM --exclude REASON` appends an `EXCLUDED` row and runs nothing.
- `grade-review.mjs` (Task 10): `defects(rubric)`, `graderPrompt(rubric, review)`, `readGrades(ids, review, reply)`, `gradeReview({ rep, id, arm, pass, grader })` → `Promise<row>`; a cell with no `review.md` gets a `0` grade for every defect and no grader call.
- `run-grid.mjs` (Task 12): `--stage smoke|written|stripped|review [--rep N] [--minutes M] [--pass P]`; an `EXCLUDED` row on any arm takes its case out of the repetition for every arm, here and in `report.mjs`; last output line `run-grid stage=<s> rep=<n> ran=<k> remaining=<m> spent=<dollars> stop=<cap|limit|time|->`; exit 0 complete, 1 cells remain, 2 usage or drift, 3 stopped.
- `report.mjs` (Task 12): `[--rep N] [--pass P]`, Markdown on stdout.

**Files**
- `arms.json`: `{ "rows": { "<row>": [current, ...cheaper] }, "review": [current, ...cheaper], "grader": { "model", "effort" } }`.
- `cases/manifest.tsv`: line 1 `# start <40-hex commit>`, line 2 the header `id pool row plan task base result`, tab-separated; ids are `w-<slug>-t<task>` and `s-<slug>-t<task>`.
- `cases/reviews/cases.json`: an array of `{ id, kind: "code", base, head, fix, plan, description }` and `{ id, kind: "plan", commit, plan, spec }`.
- `cases/reviews/<id>.md`: a rubric; each defect is one `## D<n>: <name>` heading.
- A run directory `armDir(...)` holds `work/` (the snapshot), `case.json`, `agent.md`, `prompt.txt`, `output.json`, `stderr.txt`, and for a review `review.md` and `grade<pass>/`.

**Test fixture** (Task 1, `tests/fixture.mjs`)
- `PLAN` = `docs/superpowers/plans/2026-09-20-fixture.md`.
- `fixture()` → `{ top, repo, data, work, stub, planned, greet, shout }` and sets the `TIER_EVAL_*` variables and `STUB_DIR`; call it before importing a harness module. Commits in order: `planned`, `greet` (Task 1 of the fixture plan), `shout` (Task 2), then Tasks 3 and 4.
- `modes(stub, ...list)` — the stub's replies in order; the last repeats. Modes: `pass`, `concerns`, `failtest`, `cheat`, `outside`, `blocked`, `budget`, `limit`, `crash`, `review`, `grade`.

## Assumptions (evidence)

- The harness these tasks build was prototyped while this plan was written, and every code block below was generated from that prototype after its 67 tests passed. The prototype was then moved out of the working tree and `scripts/test-all.mjs` restored, so Task 1 starts clean: `git status --short -- evals scripts/test-all.mjs` printed nothing, 2026-10-01.
- The plugin's plan reader has the three functions `lib/plan.mjs` calls: `plugins/dr-superpowers/scripts/lib/plan.sh:36` (`plan_tasks`, one `n<TAB>title` line per task), `:117` (`plan_task_text`, exit 3 when the task is absent, `:122`), `:160` (`plan_eval_lines`, reads the task text on stdin).
- `scripts/task-brief` exits 3 for a task the plan lacks and appends `## Plan header excerpt`: `plugins/dr-superpowers/scripts/task-brief:68` and `:80`.
- The implementer template holds the five strings `build-case.mjs` fills: `plugins/dr-superpowers/skills/subagent-driven-development/references/implementer-prompt.md:9` (`Task N: [task name]`), `:13` (`[BRIEF_FILE]`), `:20` (`[Scene-setting: where this fits, dependencies, architectural context]`), `:40` (`[directory]`), `:142` (`[REPORT_FILE]`).
- The code-reviewer template holds `[DESCRIPTION]`, `[PLAN_OR_REQUIREMENTS]`, `[DIFF_FILE]`, `[BASE_SHA]` and `[HEAD_SHA]`: `plugins/dr-superpowers/skills/requesting-code-review/references/code-reviewer.md:17`, `:21`, `:25`, `:27`.
- The plan-reviewer template holds `[PLAN_FILE]`, `[SPEC_FILE]`, `[LINT_FILE]` and `[PLUGIN_ROOT]`: `plugins/dr-superpowers/skills/writing-plans/references/plan-reviewer-prompt.md:19`, `:20`, `:21`, `:60`.
- `impl-haiku` sets no effort: `grep -c '^effort:' plugins/dr-superpowers/agents/impl-haiku.md` printed `0`, 2026-10-01.
- `scripts/register` takes `set FILE ID STATE [--note TEXT]` and `check FILE`: `plugins/dr-superpowers/scripts/register:9-17`; `register set … 1 planned --assigned … --acceptance …` and `register check` both ran clean on this plan's register, 2026-10-01.
- The calibration record has the sections Task 16 reads: `docs/superpowers/notes/2026-09-20-review-routing-calibration.md:82` ("The findings are substantive, not padding"), `:209` ("Known defects (Step 5) — performed for the first time"), `:229` ("One Critical verified against shipped code").
- The headings Task 17's probe looks for exist: `## The Rule` and `## Routing` at `plugins/dr-superpowers/skills/using-superpowers/SKILL.md:10` and `:20`, which the session-start hook injects; `## Process hygiene` at line 35 of the owner's global `CLAUDE.md`.
- `scripts/test-all.mjs:44` on `main` is the line Task 13 inserts above: `  [bash, ['plugins/dr-status/tests/run-all.sh'], 420],`.
- `scripts/task-brief` builds a brief from a plan file outside the repository: `bash plugins/dr-superpowers/scripts/task-brief <tmp>/plan.md 12 <tmp>/brief.md` exited 0 with 186 lines, 2026-10-01.
- The eligibility rules and the golden check leave 52 selected cases: `node evals/tiers/build-manifest.mjs` printed `build-manifest: 52 cases, 161 exclusions`, 2026-10-01; per pool and row 7, 8, 8, 8, 8, 1 written on rows 1 to 6 and 3, 6, 2, 1 stripped on rows 3 to 6.
- Every review case of Task 13 builds: `node evals/tiers/build-case.mjs <id> <dir>` exited 0 for all ten ids, 2026-10-01.
- The CLI has every flag `lib/claude.mjs` passes: `claude --help`, Claude Code 2.1.286, 2026-10-01.
- The CLI is on a subscription login with no API key in the environment: `claude auth status`, 2026-10-01.
- No external executor is offered: `codex-gate usable=false reason=plugin-api review=false lane=false resets_at=- source=probe`, 2026-10-01.
- `tests/ui-discovery.test.mjs` fails on this host before this plan, because it shells out to an `rg` binary the host lacks: it fails identically on a `git archive` of `main`, 2026-10-01. Task 13 therefore does not run it.
- The three review-case plans `judge-seats`, `inline-mode` and `small-model` were never amended after the case commit (`git log <commit>..main -- <plan>` is empty for each, 2026-10-01), so their rubrics come from defects their execution exposed. Whether each has two verifiable defects is unverified — Task 16 verifies it and drops a case that has fewer.
- `--model` and `--effort` take effect alongside `--append-system-prompt-file`: unverified — Task 17 verifies it.
- `--setting-sources project` keeps the session-start hook and the owner's global instructions out of a run: unverified — Task 17 verifies it.
- `--allowedTools` with `--permission-mode acceptEdits` lets a headless run edit files and run shell commands without a prompt: unverified — Task 17 verifies it.
- The CLI's JSON output carries `result`, `total_cost_usd`, `num_turns`, `modelUsage` and `is_error`: unverified — Task 17 verifies it.
- A budget stop sets `is_error` with a `subtype` containing `budget`: unverified — Task 17 verifies it with a probe under a tenth of a cent, runs `classify` on the real output, and stops unless the kind is `budget` or `cut`. `classify` reads the budget subtype before the limit pattern, and any other error that arrives after the run spent something is `cut`; both settle the cell as `BLOCKED`.
- The usage-limit message matches `classify`'s limit pattern: unverified — Task 18 verifies it at the first limit it meets, because nothing reproduces a limit on demand. A limit the pattern misses shows as `NOT_RUN` rows whose detail starts `error: ` at zero cost and exit 1, never as a score; the exit table of Task 18 Step 1 says what to do.

## Task index

1. Test fixture and stub CLI
2. Process helpers and the plan reader
3. Prompt templates and stripping
4. Snapshots and grading primitives
5. Case enumeration and selection
6. Manifest builder
7. Headless CLI call
8. Case building and the implementation grader
9. Results file and running one cell
10. Review grader
11. Decision rules
12. Grid runner and report
13. Review cases, README and test runner hook
14. Pin the case manifest
15. Code-review rubrics
16. Plan-review rubrics
17. Smoke stage
18. As-written stage
19. Stripped stage
20. Review stage
21. Results note and register

---

### Task 1: Test fixture and stub CLI

**Files:**
- Create: `evals/tiers/tests/fixture.mjs`
- Create: `evals/tiers/tests/stub-claude.mjs`
- Test: `evals/tiers/tests/fixture.test.mjs`

**Interfaces:**
- Consumes: nothing.
- Produces: `PLAN`, `fixture()`, `modes()` and the stub modes — Contracts, Test fixture. Every later test uses them.

**Items:** 1
**Implementer:** dr-superpowers:impl-sonnet-high
**Evaluation:** files 1 - spec 0 - coupling 2 - risk 0 = 3

- [ ] **Step 1: Write the failing test**

Create `evals/tiers/tests/fixture.test.mjs`:

```js
import assert from 'node:assert/strict';
import { existsSync, readFileSync, rmSync } from 'node:fs';
import { join } from 'node:path';
import { after, test } from 'node:test';
import { spawnSync } from 'node:child_process';
import { PLAN, fixture, modes } from './fixture.mjs';

const fx = fixture();
after(() => rmSync(fx.top, { recursive: true, force: true }));
const git = (...args) => spawnSync('git', args, { cwd: fx.repo, encoding: 'utf8' }).stdout.trim();

test('the fixture holds one plan and the commits that carried it out', () => {
  assert.deepEqual(git('log', '--reverse', '--format=%s').split('\n'), ['docs: plan the fixture', 'feat: add greet', 'feat: add shout', 'docs: add notes', 'feat: add idle']);
  assert.deepEqual([git('rev-parse', 'HEAD~4'), git('rev-parse', 'HEAD~3'), git('rev-parse', 'HEAD~2')], [fx.planned, fx.greet, fx.shout]);
  assert.equal(git('show', `${fx.planned}:${PLAN}`).match(/^### Task \d+:/gm).length, 4);
  assert.equal(process.env.TIER_EVAL_ROOT, fx.repo);
});

test('the stub acts as its mode says, records the call and moves down the mode list', () => {
  const clone = join(fx.top, 'clone');
  spawnSync('git', ['clone', '-q', fx.repo, clone]);
  spawnSync('git', ['checkout', '-q', fx.planned], { cwd: clone });
  modes(fx.stub, 'pass', 'blocked');
  const call = () => spawnSync(process.env.TIER_EVAL_CLAUDE, ['-p', '--model', 'sonnet'], { cwd: clone, input: 'the prompt', encoding: 'utf8' });
  const first = JSON.parse(call().stdout);
  assert.deepEqual([first.result, first.is_error, first.total_cost_usd, first.num_turns], ['**Status:** DONE', false, 0.5, 3]);
  assert.equal(existsSync(join(clone, 'src/greet.sh')), true);
  assert.match(JSON.parse(call().stdout).result, /BLOCKED/);
  assert.match(JSON.parse(call().stdout).result, /BLOCKED/);
  const calls = readFileSync(join(fx.stub, 'calls.log'), 'utf8').trim().split('\n').map(l => JSON.parse(l));
  assert.deepEqual(calls.map(c => c.mode), ['pass', 'blocked', 'blocked']);
  assert.deepEqual([calls[0].prompt, calls[0].args, calls[0].cwd], ['the prompt', ['-p', '--model', 'sonnet'], clone]);
  modes(fx.stub, 'limit');
  const limited = call();
  assert.deepEqual([limited.status, JSON.parse(limited.stdout).is_error], [1, true]);
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `timeout 300 node --test evals/tiers/tests/fixture.test.mjs`
Expected: FAIL — `ERR_MODULE_NOT_FOUND` naming `tests/fixture.mjs`

- [ ] **Step 3: Write the fixture and the stub**

Create `evals/tiers/tests/fixture.mjs`:

````js
// A throwaway repository with one plan and the commits that carried it out,
// plus a stub `claude`, so every harness test runs without a model call.
import { chmodSync, mkdirSync, mkdtempSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';

export const PLAN = 'docs/superpowers/plans/2026-09-20-fixture.md';
const FENCE = '```';

function task(n, title, files, evaluation, test, code, message) {
  return [
    `### Task ${n}: ${title}`, '', '**Files:**', ...files, '',
    '**Implementer:** dr-superpowers:impl-sonnet-low', `**Evaluation:** ${evaluation}`, '',
    '- [ ] **Step 1: Write the test**', '', `${FENCE}bash`, ...test, FENCE, '',
    '- [ ] **Step 2: Implement**', '', `${FENCE}bash`, ...code, FENCE, '',
    '- [ ] **Step 3: Commit**', '', `${FENCE}bash`, `git commit -m "${message}"`, FENCE, '',
  ];
}

const GREET_TEST = ['set -e', 'out=$(bash src/greet.sh)', '[ "$out" = "hello" ]'];
const GREET = ['# greets', 'echo hello'];
const SHOUT_TEST = ['set -e', 'out=$(bash src/shout.sh)', '[ "$out" = "HELLO" ]'];
const SHOUT = ['# shouts', 'echo HELLO'];

const PLAN_TEXT = [
  '# Fixture Plan', '', '**Goal:** a fixture', '', '**Plan review:** 2026-09-20 - an earlier verdict', '', '## Global Constraints', '', 'None.', '', '## Contracts', '', 'None.', '', '---', '',
  ...task(1, 'Greet', ['- Create: `src/greet.sh`', '- Test: `tests/greet.test.sh`'], 'files 1 - spec 0 - coupling 0 - risk 0 = 1', GREET_TEST, GREET, 'feat: add greet'),
  ...task(2, 'Shout', ['- Create: `src/shout.sh`', '- Modify: `tests/shout.test.sh`'], 'files 1 - spec 0 - coupling 0 - risk 2 = 3', SHOUT_TEST, SHOUT, 'feat: add shout'),
  ...task(3, 'Notes', ['- Create: `notes.md`'], 'files 0 - spec 0 - coupling 0 - risk 0 = 0', ['true'], ['notes'], 'docs: add notes'),
  ...task(4, 'Already green', ['- Create: `src/idle.sh`', '- Test: `tests/idle.test.sh`'], 'files 1 - spec 0 - coupling 0 - risk 0 = 1', ['true'], ['# idle'], 'feat: add idle'),
].join('\n');

function git(dir, ...args) {
  const r = spawnSync('git', ['-c', 'user.name=fixture', '-c', 'user.email=fixture@example.invalid', ...args], { cwd: dir, encoding: 'utf8' });
  if (r.status !== 0) throw new Error(`git ${args.join(' ')}: ${r.stderr}`);
  return r.stdout.trim();
}

function commit(dir, files, message) {
  for (const [path, lines] of Object.entries(files)) {
    mkdirSync(dirname(join(dir, path)), { recursive: true });
    writeFileSync(join(dir, path), lines.join('\n') + '\n');
  }
  git(dir, 'add', '-A');
  git(dir, 'commit', '-q', '-m', message);
  return git(dir, 'rev-parse', 'HEAD');
}

// fixture — builds the repository, a data directory, a work directory and the
// stub, points the TIER_EVAL_* variables at them, and returns their paths and
// commits. Call it before importing any harness module.
export function fixture() {
  const top = mkdtempSync(join(tmpdir(), 'tier-eval-test-'));
  const repo = join(top, 'repo'), data = join(top, 'data'), work = join(top, 'work'), stub = join(top, 'stub');
  for (const dir of [repo, join(data, 'cases/reviews'), work, stub]) mkdirSync(dir, { recursive: true });
  git(repo, 'init', '-q', '-b', 'main');
  const planned = commit(repo, { [PLAN]: [PLAN_TEXT], 'plugins/dr-superpowers/marker.txt': ['fixture'], '.gitignore': ['node_modules/'] }, 'docs: plan the fixture');
  const greet = commit(repo, { 'src/greet.sh': GREET, 'tests/greet.test.sh': GREET_TEST }, 'feat: add greet');
  const shout = commit(repo, { 'src/shout.sh': SHOUT, 'tests/shout.test.sh': SHOUT_TEST }, 'feat: add shout');
  commit(repo, { 'notes.md': ['notes'] }, 'docs: add notes');
  commit(repo, { 'src/idle.sh': ['# idle'], 'tests/idle.test.sh': ['true'] }, 'feat: add idle');
  writeFileSync(join(stub, 'greet.patch'), spawnSync('git', ['diff', planned, greet], { cwd: repo, encoding: 'utf8' }).stdout);
  writeFileSync(join(stub, 'claude'), `#!/bin/sh\nexec "${process.execPath}" "${fileURLToPath(new URL('./stub-claude.mjs', import.meta.url))}" "$@"\n`);
  chmodSync(join(stub, 'claude'), 0o755);
  writeFileSync(join(data, 'arms.json'), JSON.stringify({
    rows: { 1: ['impl-sonnet-low', 'impl-haiku'], 5: ['impl-opus-medium', 'impl-sonnet-high'] },
    review: ['judge-opus@high', 'judge-sonnet-high'],
    grader: { model: 'opus', effort: 'low' },
  }));
  writeFileSync(join(data, 'cases/reviews/cases.json'), JSON.stringify([
    { id: 'r-code-fixture', kind: 'code', base: planned, head: greet, plan: PLAN, description: 'Adds the greet script.' },
  ]));
  writeFileSync(join(data, 'cases/reviews/r-code-fixture.md'), '# Rubric\n\n## D1: greets in lower case\n\n## D2: no usage text\n');
  Object.assign(process.env, { TIER_EVAL_ROOT: repo, TIER_EVAL_DATA: data, TIER_EVAL_WORK: work, TIER_EVAL_CLAUDE: join(stub, 'claude'), STUB_DIR: stub });
  return { top, repo, data, work, stub, planned, greet, shout };
}

// modes — the stub's replies, one mode per call; the last mode repeats.
export function modes(stub, ...list) {
  writeFileSync(join(stub, 'modes'), list.join('\n') + '\n');
}
````

Create `evals/tiers/tests/stub-claude.mjs`:

```js
// Stands in for the `claude` CLI. Each call takes the next mode from
// $STUB_DIR/modes, records its arguments in $STUB_DIR/calls.log, acts in its
// working directory as that mode says, and prints the JSON a headless run
// prints.
import { appendFileSync, existsSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';

const dir = process.env.STUB_DIR;
const list = readFileSync(join(dir, 'modes'), 'utf8').split('\n').filter(Boolean);
const mode = list[0];
if (list.length > 1) writeFileSync(join(dir, 'modes'), list.slice(1).join('\n') + '\n');
appendFileSync(join(dir, 'calls.log'), JSON.stringify({ mode, cwd: process.cwd(), args: process.argv.slice(2), prompt: readFileSync(0, 'utf8') }) + '\n');

const reply = (result, extra = {}) => console.log(JSON.stringify({ type: 'result', is_error: false, result, total_cost_usd: 0.5, num_turns: 3, modelUsage: { 'stub-model': {} }, ...extra }));
const apply = () => spawnSync('git', ['apply', join(dir, 'greet.patch')], { stdio: 'ignore' });
const file = name => existsSync(join(dir, name)) ? readFileSync(join(dir, name), 'utf8') : '';

if (mode === 'pass') { apply(); reply('**Status:** DONE'); }
else if (mode === 'concerns') { apply(); reply('**Status:** DONE_WITH_CONCERNS'); }
else if (mode === 'failtest') { apply(); writeFileSync('src/greet.sh', 'echo nope\n'); reply('**Status:** DONE'); }
else if (mode === 'cheat') { apply(); writeFileSync('src/greet.sh', 'echo nope\n'); writeFileSync('tests/greet.test.sh', 'true\n'); reply('**Status:** DONE'); }
else if (mode === 'outside') { apply(); writeFileSync('extra.txt', 'x\n'); reply('**Status:** DONE'); }
else if (mode === 'blocked') { reply('**Status:** BLOCKED - the brief is unclear'); }
else if (mode === 'budget') { apply(); reply('', { is_error: true, subtype: 'error_max_budget_usd' }); process.exitCode = 1; }
else if (mode === 'limit') { reply("You've hit your usage limit", { is_error: true, total_cost_usd: 0 }); process.exitCode = 1; }
else if (mode === 'crash') { console.error('boom'); process.exitCode = 2; }
else if (mode === 'review') { reply(file('review.md')); }
else if (mode === 'grade') { reply(file('grade.json')); }
else { console.error(`stub-claude: unknown mode ${mode}`); process.exitCode = 2; }
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `timeout 300 node --test evals/tiers/tests/fixture.test.mjs`
Expected: PASS — `pass 2`, `fail 0`

- [ ] **Step 5: Commit**

```bash
git add evals/tiers/tests/fixture.mjs evals/tiers/tests/stub-claude.mjs evals/tiers/tests/fixture.test.mjs
git commit -m "test(evals): add the tier-eval fixture and stub"
```

### Task 2: Process helpers and the plan reader

**Files:**
- Create: `evals/tiers/lib/sh.mjs`
- Create: `evals/tiers/lib/plan.mjs`
- Test: `evals/tiers/tests/plan.test.mjs`

**Interfaces:**
- Consumes: `fixture()` and `PLAN` — Contracts, Test fixture; the plugin's `scripts/lib/plan.sh` and `scripts/task-brief`, which already exist.
- Produces: everything under `lib/sh.mjs` and `lib/plan.mjs` in Contracts.

**Items:** 1
**Implementer:** dr-superpowers:impl-sonnet-high
**Evaluation:** files 1 - spec 0 - coupling 2 - risk 0 = 3

- [ ] **Step 1: Write the failing test**

Create `evals/tiers/tests/plan.test.mjs`:

```js
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { existsSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { after, test } from 'node:test';
import { PLAN, fixture } from './fixture.mjs';

const fx = fixture();
after(() => rmSync(fx.top, { recursive: true, force: true }));
const { git, run, sh } = await import('../lib/sh.mjs');
const { commitMessages, evaluation, filesBlock, taskBrief, taskText, tasks } = await import('../lib/plan.mjs');
const plan = join(fx.top, 'plan.md');
writeFileSync(plan, git(['show', `${fx.planned}:${PLAN}`]));

test('git reads the fixture repository and throws on a failing command', () => {
  assert.equal(git(['rev-parse', 'HEAD~3']).trim(), fx.greet);
  assert.throws(() => git(['rev-parse', 'no-such-ref']), /git rev-parse no-such-ref/);
  assert.equal(sh('bash', ['-c', 'exit 3']).code, 3);
});

test('run returns the output and kills the whole tree at the timeout', async () => {
  assert.deepEqual(await run('bash', ['-c', 'cat; echo err >&2'], { input: 'in' }), { code: 0, out: 'in', err: 'err\n', timedOut: false });
  const started = Date.now();
  const slow = await run('bash', ['-c', 'sleep 30 & wait'], { seconds: 1 });
  assert.equal(slow.timedOut, true);
  assert.ok(Date.now() - started < 10000);
  assert.equal((await run('no-such-binary-xyz', [])).code, 127);
});

test('a signal that stops the harness kills what run started', async () => {
  const pidFile = join(fx.top, 'child.pid');
  const code = `import(${JSON.stringify(new URL('../lib/sh.mjs', import.meta.url).href)}).then(m => m.run('bash', ['-c', 'echo $$ > "$0"; sleep 30', ${JSON.stringify(pidFile)}]))`;
  const harness = spawn(process.execPath, ['-e', code], { stdio: 'ignore' });
  while (!existsSync(pidFile) || readFileSync(pidFile, 'utf8').trim() === '') await new Promise(r => setTimeout(r, 50));
  const pid = Number(readFileSync(pidFile, 'utf8'));
  harness.kill('SIGTERM');
  const exit = await new Promise(r => harness.on('exit', r));
  await new Promise(r => setTimeout(r, 200));
  assert.equal(exit, 130);
  assert.throws(() => process.kill(pid, 0), /ESRCH/);
});

test('the plan reader lists tasks, their text and their scores', () => {
  assert.deepEqual(tasks(plan), [{ n: 1, title: 'Greet' }, { n: 2, title: 'Shout' }, { n: 3, title: 'Notes' }, { n: 4, title: 'Already green' }]);
  assert.match(taskText(plan, 2), /^### Task 2: Shout\n[\s\S]*feat: add shout/);
  assert.doesNotMatch(taskText(plan, 2), /Task 3/);
  assert.equal(taskText(plan, 9), null);
  assert.deepEqual(evaluation(taskText(plan, 2)), { files: 1, spec: 0, coupling: 0, risk: 2, total: 3 });
  assert.equal(evaluation('no score here'), null);
  assert.equal(evaluation('**Evaluation:** files 1 - spec 0 - coupling 0 - risk 0 = 1\n**Evaluation:** files 1 - spec 0 - coupling 0 - risk 0 = 1'), null);
});

test('filesBlock reads labels, line suffixes and test files listed under Modify', () => {
  const text = ['**Files:**', '- Create: `src/a.sh` (new)', '- Modify: `tests/a.test.sh:10-20`', '- Modify: `lib/b.mjs`, `lib/c.mjs` (add `--flag`)', '- Test: tests/d.test.mjs,', '', '**Interfaces:**', '- Create: `not/in/block.sh`'].join('\n');
  assert.deepEqual(filesBlock(text), {
    allowed: ['src/a.sh', 'tests/a.test.sh', 'lib/b.mjs', 'lib/c.mjs', 'tests/d.test.mjs'],
    tests: ['tests/a.test.sh', 'tests/d.test.mjs'],
  });
});

test('commitMessages takes the first -m of each commit command', () => {
  assert.deepEqual(commitMessages('git add a\ngit commit -m "feat: one" -m "body"\ngit commit -q -m \'fix: two\'\ngit commit -m "feat: one"'), ['feat: one', 'fix: two']);
});

test('taskBrief is the task text followed by the header excerpt', () => {
  const brief = taskBrief(plan, 1, join(fx.top, 'brief'));
  assert.match(brief, /^### Task 1: Greet\n/);
  assert.match(brief, /## Plan header excerpt\n\n## Global Constraints\n\nNone\.\n\n## Contracts/);
  assert.doesNotMatch(brief, /Task 2/);
  assert.throws(() => taskBrief(plan, 9, join(fx.top, 'brief')), /task-brief .* 9: exit 3/);
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `timeout 300 node --test evals/tiers/tests/plan.test.mjs`
Expected: FAIL — `ERR_MODULE_NOT_FOUND` naming `lib/sh.mjs`

- [ ] **Step 3: Write the implementation**

Create `evals/tiers/lib/sh.mjs`:

```js
import { spawn, spawnSync } from 'node:child_process';
import { homedir } from 'node:os';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const REPO = fileURLToPath(new URL('../../../', import.meta.url));

// ROOT is the repository whose history holds the cases, DATA holds the
// manifest and the results, WORK holds snapshots and transcripts. The tests
// point all three at a fixture; PLUGIN is always the plugin beside the harness.
export const ROOT = process.env.TIER_EVAL_ROOT ?? REPO;
export const DATA = process.env.TIER_EVAL_DATA ?? resolve(REPO, 'evals/tiers');
export const WORK = process.env.TIER_EVAL_WORK ?? resolve(homedir(), '.cache/dr-tier-eval');
export const PLUGIN = resolve(REPO, 'plugins/dr-superpowers');

export function sh(cmd, args, opts = {}) {
  const r = spawnSync(cmd, args, { cwd: ROOT, encoding: 'utf8', maxBuffer: 256 * 1024 * 1024, ...opts });
  return { code: r.status ?? 1, out: r.stdout ?? '', err: r.stderr ?? '' };
}

export function git(args, opts = {}) {
  const r = sh('git', args, opts);
  if (r.code !== 0) throw new Error(`git ${args.join(' ')}: ${r.err.trim()}`);
  return r.out;
}

// Every process group run() has started and not yet reaped. Whatever ends the
// harness - a signal or an uncaught error - kills them all, so a stopped grid
// leaves no agent behind.
const live = new Set();
process.on('exit', () => {
  for (const pid of live) { try { process.kill(-pid, 'SIGKILL'); } catch {} }
});
for (const signal of ['SIGINT', 'SIGTERM']) process.on(signal, () => process.exit(130));

// run CMD ARGS { cwd, seconds, input, env } — resolves { code, out, err,
// timedOut }. The child leads its own process group, so a timeout kills the
// whole tree and nothing it started outlives the call.
export function run(cmd, args, { cwd, seconds, input, env } = {}) {
  return new Promise(resolveRun => {
    const child = spawn(cmd, args, { cwd, env: env ?? process.env, detached: true, stdio: ['pipe', 'pipe', 'pipe'] });
    live.add(child.pid);
    let out = '', err = '', timedOut = false;
    const kill = signal => { try { process.kill(-child.pid, signal); } catch {} };
    const timer = seconds ? setTimeout(() => { timedOut = true; kill('SIGTERM'); setTimeout(() => kill('SIGKILL'), 5000).unref(); }, seconds * 1000) : null;
    child.stdout.on('data', d => { out += d; });
    child.stderr.on('data', d => { err += d; });
    child.on('error', error => { clearTimeout(timer); live.delete(child.pid); resolveRun({ code: 127, out, err: String(error), timedOut }); });
    child.on('close', code => { clearTimeout(timer); kill('SIGKILL'); live.delete(child.pid); resolveRun({ code: code ?? 1, out, err, timedOut }); });
    child.stdin.on('error', () => {});
    child.stdin.end(input ?? '');
  });
}
```

Create `evals/tiers/lib/plan.mjs`:

```js
import { mkdirSync, readFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { PLUGIN, sh } from './sh.mjs';

const LIB = resolve(PLUGIN, 'scripts/lib/plan.sh');
const TEST_FILE = /\.test\.(sh|mjs)$/;

// The plugin's own plan reader does the parsing, so the harness and
// scripts/task-brief agree on what a task is.
function planLib(fn, args, input) {
  return sh('bash', ['-c', '. "$0"; "$@"', LIB, fn, ...args], { input });
}

export function tasks(planFile) {
  return planLib('plan_tasks', [planFile]).out.split('\n').filter(Boolean).map(line => {
    const [n, title] = line.split('\t');
    return { n: Number(n), title };
  });
}

export function taskText(planFile, n) {
  const r = planLib('plan_task_text', [planFile, String(n)]);
  return r.code === 0 ? r.out : null;
}

// evaluation TEXT — the four axes and the total, or null unless the task has
// exactly one Evaluation line and it parses.
export function evaluation(text) {
  const lines = planLib('plan_eval_lines', [], text).out.split('\n').filter(Boolean);
  if (lines.length !== 1) return null;
  const m = lines[0].match(/files (\d+)\D+spec (\d+)\D+coupling (\d+)\D+risk (\d+) = (\d+)/);
  if (!m) return null;
  const [files, spec, coupling, risk, total] = m.slice(1).map(Number);
  return { files, spec, coupling, risk, total };
}

export function commitMessages(text) {
  const found = new Set();
  for (const m of text.matchAll(/git commit\b[^\n]*?-m\s+(["'])(.+?)\1/g)) found.add(m[2]);
  return [...found];
}

// filesBlock TEXT — the paths the task's **Files:** block names. A path is a
// test when its line is labelled Test or its name is a runnable test file:
// plans list an existing test file under Modify.
export function filesBlock(text) {
  const allowed = new Set(), tests = new Set();
  let on = false;
  for (const line of text.split('\n')) {
    if (line.startsWith('**Files:**')) { on = true; continue; }
    const m = on && line.match(/^- (Create|Modify|Test):\s*(.+)$/);
    if (!m) { if (on && line.trim() !== '') on = false; continue; }
    const quoted = [...m[2].matchAll(/`([^`]+)`/g)].map(q => q[1]);
    const names = quoted.length > 0 ? quoted : [m[2].split(/\s/)[0]];
    for (const name of names) {
      const path = name.replace(/:[0-9][0-9,-]*$/, '').replace(/,$/, '');
      if (!/[\/.]/.test(path) || /\s/.test(path)) continue;
      allowed.add(path);
      if (m[1] === 'Test' || TEST_FILE.test(path)) tests.add(path);
    }
  }
  return { allowed: [...allowed], tests: [...tests] };
}

// taskBrief PLAN_FILE N DIR — the brief scripts/task-brief writes for task N:
// the task text plus the header's Global Constraints and Contracts.
export function taskBrief(planFile, n, dir) {
  mkdirSync(dir, { recursive: true });
  const out = join(dir, 'brief.md');
  const r = sh('bash', [resolve(PLUGIN, 'scripts/task-brief'), planFile, String(n), out], { cwd: dir });
  if (r.code !== 0) throw new Error(`task-brief ${planFile} ${n}: exit ${r.code} ${r.err.trim()}`);
  return readFileSync(out, 'utf8');
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `timeout 300 node --test evals/tiers/tests/plan.test.mjs`
Expected: PASS — `pass 7`, `fail 0`

- [ ] **Step 5: Commit**

```bash
git add evals/tiers/lib/sh.mjs evals/tiers/lib/plan.mjs evals/tiers/tests/plan.test.mjs
git commit -m "feat(evals): add process helpers and plan reader"
```

### Task 3: Prompt templates and stripping

**Files:**
- Create: `evals/tiers/lib/prompt.mjs`
- Create: `evals/tiers/lib/strip.mjs`
- Test: `evals/tiers/tests/text.test.mjs`

**Interfaces:**
- Consumes: `git` and `PLUGIN` — Contracts, `lib/sh.mjs`; `fixture()` — Contracts, Test fixture.
- Produces: `template`, `fill`, `MARKER`, `isTestPath`, `addedLines`, `strip` — Contracts, `lib/prompt.mjs` and `lib/strip.mjs`.

**Items:** 1
**Implementer:** dr-superpowers:impl-sonnet-high
**Evaluation:** files 1 - spec 0 - coupling 2 - risk 0 = 3

- [ ] **Step 1: Write the failing test**

Create `evals/tiers/tests/text.test.mjs`:

`````js
import assert from 'node:assert/strict';
import { rmSync } from 'node:fs';
import { resolve } from 'node:path';
import { after, test } from 'node:test';
import { fixture } from './fixture.mjs';

const fx = fixture();
after(() => rmSync(fx.top, { recursive: true, force: true }));
const { PLUGIN } = await import('../lib/sh.mjs');
const { fill, template } = await import('../lib/prompt.mjs');
const { MARKER, addedLines, isTestPath, strip } = await import('../lib/strip.mjs');

test('the three production templates yield a prompt body', () => {
  const body = template(resolve(PLUGIN, 'skills/subagent-driven-development/references/implementer-prompt.md'));
  assert.match(body, /^You are implementing Task N: \[task name\]/);
  assert.doesNotMatch(body, /^Subagent|prompt: \|/m);
  assert.match(template(resolve(PLUGIN, 'skills/requesting-code-review/references/code-reviewer.md')), /\[DIFF_FILE\][\s\S]*```bash[\s\S]*## Critical Rules/);
  assert.match(template(resolve(PLUGIN, 'skills/writing-plans/references/plan-reviewer-prompt.md')), /\[PLAN_FILE\][\s\S]*\[PLUGIN_ROOT\]/);
  assert.throws(() => template(resolve(PLUGIN, 'README.md')), /no "prompt: \|" block/);
});

test('fill replaces every occurrence and refuses a key the template lacks', () => {
  assert.equal(fill('a [X] b [X]', { '[X]': 'y' }), 'a y b y');
  assert.throws(() => fill('a', { '[X]': 'y' }), /no \[X\]/);
});

test('addedLines holds what a commit added outside tests/', () => {
  assert.deepEqual([...addedLines(fx.planned, fx.greet)].sort(), ['# greets', 'echo hello']);
  assert.deepEqual([isTestPath('tests/a.sh'), isTestPath('x/tests/fixtures/a'), isTestPath('src/tests.sh')], [true, true, false]);
});

test('strip removes a block only when more than half of it was added', () => {
  const added = new Set(['echo hello', '# greets']);
  const brief = ['Test:', '```bash', 'set -e', '[ "$out" = "hello" ]', '```', 'Code:', '````bash', '# greets', '```', 'echo hello', '````', 'Half:', '```', 'echo hello', 'other', '```'].join('\n');
  const { text, removed } = strip(brief, added);
  assert.equal(removed, 1);
  assert.equal(text, ['Test:', '```bash', 'set -e', '[ "$out" = "hello" ]', '```', 'Code:', MARKER, 'Half:', '```', 'echo hello', 'other', '```'].join('\n'));
  assert.deepEqual(strip('no fence', added), { text: 'no fence', removed: 0 });
});
`````

- [ ] **Step 2: Run the test to verify it fails**

Run: `timeout 300 node --test evals/tiers/tests/text.test.mjs`
Expected: FAIL — `ERR_MODULE_NOT_FOUND` naming `lib/prompt.mjs`

- [ ] **Step 3: Write the implementation**

Create `evals/tiers/lib/prompt.mjs`:

````js
import { readFileSync } from 'node:fs';

// template FILE — the prompt body of a dispatch template: the lines after
// `prompt: |` inside the file's first top-level fence, with the four-space
// YAML indent removed. Nested fences are indented, so only a fence at column
// 0 opens or closes the block.
export function template(file) {
  const lines = readFileSync(file, 'utf8').split('\n');
  const open = lines.findIndex(l => /^```\s*$/.test(l));
  const close = lines.findIndex((l, i) => i > open && /^```\s*$/.test(l));
  const at = lines.findIndex((l, i) => i > open && i < close && /^\s*prompt: \|\s*$/.test(l));
  if (open < 0 || close < 0 || at < 0) throw new Error(`${file}: no "prompt: |" block in its first fence`);
  return lines.slice(at + 1, close).map(l => l.replace(/^ {4}/, '')).join('\n');
}

// fill BODY VALUES — BODY with every key of VALUES replaced by its value. A
// key the body lacks is an error: the template changed under the harness.
export function fill(body, values) {
  let out = body;
  for (const [key, value] of Object.entries(values)) {
    if (!out.includes(key)) throw new Error(`the template has no ${key}`);
    out = out.replaceAll(key, value);
  }
  return out;
}
````

Create `evals/tiers/lib/strip.mjs`:

```js
import { git } from './sh.mjs';

export const MARKER = '[implementation removed: write this code yourself so that the tests in this brief pass]';

export const isTestPath = path => /(^|\/)tests\//.test(path);

// addedLines BASE RESULT — the trimmed, non-blank lines RESULT adds to files
// outside every tests/ directory.
export function addedLines(base, result) {
  const files = git(['diff', '--name-only', base, result]).split('\n').filter(p => p && !isTestPath(p));
  if (files.length === 0) return new Set();
  const diff = git(['diff', '-U0', base, result, '--', ...files]);
  return new Set(diff.split('\n').filter(l => l.startsWith('+') && !l.startsWith('+++')).map(l => l.slice(1).trim()).filter(Boolean));
}

// strip BRIEF ADDED — BRIEF with every fenced block replaced by MARKER when more
// than half of its non-blank lines are in ADDED. An outer fence owns the
// fences nested inside it, as in the plan reader. Returns { text, removed }.
export function strip(brief, added) {
  const out = [];
  let open = null, block = [], removed = 0;
  for (const line of brief.split('\n')) {
    if (open === null) {
      const m = line.match(/^ {0,3}(`{3,}|~{3,})/);
      if (m) { open = m[1]; block = [line]; } else out.push(line);
      continue;
    }
    block.push(line);
    const t = line.trim();
    if (!(t.length >= open.length && t === open[0].repeat(t.length))) continue;
    const body = block.slice(1, -1).map(l => l.trim()).filter(Boolean);
    const hits = body.filter(l => added.has(l)).length;
    if (body.length > 0 && hits * 2 > body.length) { out.push(MARKER); removed += 1; } else out.push(...block);
    open = null;
  }
  if (open !== null) out.push(...block);
  return { text: out.join('\n'), removed };
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `timeout 300 node --test evals/tiers/tests/text.test.mjs`
Expected: PASS — `pass 4`, `fail 0`

- [ ] **Step 5: Commit**

```bash
git add evals/tiers/lib/prompt.mjs evals/tiers/lib/strip.mjs evals/tiers/tests/text.test.mjs
git commit -m "feat(evals): add prompt templates and stripping"
```

### Task 4: Snapshots and grading primitives

**Files:**
- Create: `evals/tiers/lib/snapshot.mjs`
- Create: `evals/tiers/lib/grade.mjs`
- Test: `evals/tiers/tests/grade.test.mjs`

**Interfaces:**
- Consumes: `sh`, `git`, `run` — Contracts, `lib/sh.mjs`; `fixture()` — Contracts, Test fixture.
- Produces: `snapshot` and everything under `lib/grade.mjs` in Contracts.

**Items:** 1
**Implementer:** dr-superpowers:impl-sonnet-high
**Evaluation:** files 1 - spec 0 - coupling 2 - risk 0 = 3

- [ ] **Step 1: Write the failing test**

Create `evals/tiers/tests/grade.test.mjs`:

```js
import assert from 'node:assert/strict';
import { existsSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { after, test } from 'node:test';
import { fixture } from './fixture.mjs';

const fx = fixture();
after(() => rmSync(fx.top, { recursive: true, force: true }));
const { git } = await import('../lib/sh.mjs');
const { snapshot } = await import('../lib/snapshot.mjs');
const { changedFiles, outcome, overlayTests, runTests, statusWord } = await import('../lib/grade.mjs');

test('snapshot is a one-commit repository of that tree, without the dropped paths', () => {
  const dir = join(fx.top, 'snap');
  const initial = snapshot(fx.greet, dir, ['docs/superpowers']);
  assert.equal(git(['rev-list', '--count', 'HEAD'], { cwd: dir }).trim(), '1');
  assert.equal(git(['rev-parse', 'HEAD'], { cwd: dir }).trim(), initial);
  assert.deepEqual([existsSync(join(dir, 'src/greet.sh')), existsSync(join(dir, 'src/shout.sh')), existsSync(join(dir, 'docs/superpowers'))], [true, false, false]);
  assert.throws(() => snapshot('no-such-commit', join(fx.top, 'bad')), /snapshot no-such-commit/);
});

test('changedFiles sees committed, uncommitted and untracked changes but not the scratch directory', () => {
  const dir = join(fx.top, 'changed');
  const initial = snapshot(fx.greet, dir);
  writeFileSync(join(dir, 'src/greet.sh'), 'echo changed\n');
  git(['-c', 'user.name=t', '-c', 'user.email=t@example.invalid', 'commit', '-q', '-am', 'edit'], { cwd: dir });
  writeFileSync(join(dir, 'tests/greet.test.sh'), 'true\n');
  writeFileSync(join(dir, 'new.txt'), 'x\n');
  mkdirSync(join(dir, '.superpowers/sdd/eval'), { recursive: true });
  writeFileSync(join(dir, '.superpowers/sdd/eval/brief.md'), 'x\n');
  assert.deepEqual(changedFiles(dir, initial), ['new.txt', 'src/greet.sh', 'tests/greet.test.sh']);
});

test('overlayTests restores the historical test and runTests reports the first failure', async () => {
  const dir = join(fx.top, 'overlay');
  snapshot(fx.greet, dir);
  writeFileSync(join(dir, 'tests/greet.test.sh'), 'true\n');
  assert.equal(overlayTests(dir, fx.greet, ['tests/greet.test.sh']), true);
  assert.match(readFileSync(join(dir, 'tests/greet.test.sh'), 'utf8'), /"hello"/);
  assert.equal(overlayTests(dir, fx.planned, ['tests/greet.test.sh']), false);
  assert.deepEqual(await runTests(dir, ['tests/greet.test.sh']), { pass: true, failed: null });
  writeFileSync(join(dir, 'src/greet.sh'), 'echo nope\n');
  assert.deepEqual(await runTests(dir, ['tests/greet.test.sh']), { pass: false, failed: 'tests/greet.test.sh' });
});

test('outcome follows the grading table', () => {
  const ok = { testsPass: true, outside: [], status: 'DONE', cutShort: false };
  assert.equal(outcome(ok), 'PASS');
  assert.equal(outcome({ ...ok, status: 'DONE_WITH_CONCERNS' }), 'PASS');
  assert.equal(outcome({ ...ok, testsPass: false }), 'FAIL');
  assert.equal(outcome({ ...ok, outside: ['x'] }), 'FAIL');
  assert.equal(outcome({ ...ok, status: 'BLOCKED' }), 'BLOCKED');
  assert.equal(outcome({ ...ok, status: 'NEEDS_CONTEXT' }), 'BLOCKED');
  assert.equal(outcome({ ...ok, status: null }), 'BLOCKED');
  assert.equal(outcome({ ...ok, cutShort: true }), 'BLOCKED');
  assert.equal(statusWord('- **Status:** DONE_WITH_CONCERNS\nnot BLOCKED'), 'DONE_WITH_CONCERNS');
  assert.equal(statusWord('all finished'), null);
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `timeout 300 node --test evals/tiers/tests/grade.test.mjs`
Expected: FAIL — `ERR_MODULE_NOT_FOUND` naming `lib/snapshot.mjs`

- [ ] **Step 3: Write the implementation**

Create `evals/tiers/lib/snapshot.mjs`:

```js
import { mkdirSync, rmSync } from 'node:fs';
import { join } from 'node:path';
import { sh, git } from './sh.mjs';

const IDENT = ['-c', 'user.name=tier-eval', '-c', 'user.email=tier-eval@example.invalid'];

// snapshot COMMIT DIR [DROP] — the tree of COMMIT as a fresh one-commit
// repository in DIR, without the paths in DROP, so nothing later than COMMIT
// is reachable from it. Returns that one commit.
export function snapshot(commit, dir, drop = []) {
  rmSync(dir, { recursive: true, force: true });
  mkdirSync(dir, { recursive: true });
  const r = sh('bash', ['-c', 'set -o pipefail; git archive "$0" | tar -x -C "$1"', commit, dir]);
  if (r.code !== 0) throw new Error(`snapshot ${commit}: ${r.err.trim()}`);
  for (const path of drop) rmSync(join(dir, path), { recursive: true, force: true });
  git(['init', '-q', '-b', 'main'], { cwd: dir });
  git(['add', '-A'], { cwd: dir });
  git([...IDENT, 'commit', '-q', '-m', 'snapshot'], { cwd: dir });
  return git(['rev-parse', 'HEAD'], { cwd: dir }).trim();
}
```

Create `evals/tiers/lib/grade.mjs`:

```js
import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { git, run, sh } from './sh.mjs';

const TEST_SECONDS = 900;

// overlayTests DIR RESULT TESTS — write RESULT's version of each test file
// into DIR, so a run cannot pass by editing a test. False when RESULT lacks one.
export function overlayTests(dir, result, tests) {
  for (const test of tests) {
    const shown = sh('git', ['show', `${result}:${test}`]);
    if (shown.code !== 0) return false;
    mkdirSync(dirname(join(dir, test)), { recursive: true });
    writeFileSync(join(dir, test), shown.out);
  }
  return true;
}

export async function runTests(dir, tests) {
  for (const test of tests) {
    const [cmd, args] = test.endsWith('.mjs') ? [process.execPath, ['--test', test]] : ['bash', [test]];
    const r = await run(cmd, args, { cwd: dir, seconds: TEST_SECONDS });
    if (r.code !== 0 || r.timedOut) return { pass: false, failed: test };
  }
  return { pass: true, failed: null };
}

// changedFiles DIR SINCE — every path that differs from commit SINCE,
// committed or not, plus untracked files git does not ignore. The brief and
// the report live under .superpowers/ and are the harness's, not the run's.
export function changedFiles(dir, since) {
  const tracked = git(['diff', '--name-only', since], { cwd: dir });
  const untracked = git(['ls-files', '--others', '--exclude-standard'], { cwd: dir });
  return [...new Set((tracked + untracked).split('\n').filter(p => p && !p.startsWith('.superpowers/')))].sort();
}

export function statusWord(message) {
  return message.match(/\b(DONE_WITH_CONCERNS|NEEDS_CONTEXT|BLOCKED|DONE)\b/)?.[1] ?? null;
}

export function outcome({ testsPass, outside, status, cutShort }) {
  if (cutShort || status === null || status === 'BLOCKED' || status === 'NEEDS_CONTEXT') return 'BLOCKED';
  return testsPass && outside.length === 0 ? 'PASS' : 'FAIL';
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `timeout 300 node --test evals/tiers/tests/grade.test.mjs`
Expected: PASS — `pass 4`, `fail 0`

- [ ] **Step 5: Commit**

```bash
git add evals/tiers/lib/snapshot.mjs evals/tiers/lib/grade.mjs evals/tiers/tests/grade.test.mjs
git commit -m "feat(evals): add snapshots and grading primitives"
```

### Task 5: Case enumeration and selection

**Files:**
- Create: `evals/tiers/lib/cases.mjs`
- Test: `evals/tiers/tests/cases.test.mjs`

**Interfaces:**
- Consumes: `lib/sh.mjs`, `lib/plan.mjs`, `snapshot`, `overlayTests`, `runTests`, `addedLines`, `strip` — Contracts.
- Produces: everything under `lib/cases.mjs` in Contracts, and the manifest format under Files.

**Items:** 1
**Implementer:** dr-superpowers:impl-sonnet-high
**Evaluation:** files 1 - spec 0 - coupling 2 - risk 0 = 3

- [ ] **Step 1: Write the failing test**

Create `evals/tiers/tests/cases.test.mjs`:

```js
import assert from 'node:assert/strict';
import { rmSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { after, test } from 'node:test';
import { spawnSync } from 'node:child_process';
import { PLAN, fixture } from './fixture.mjs';

const fx = fixture();
after(() => rmSync(fx.top, { recursive: true, force: true }));
const { candidates, golden, plans, readManifest, select, slug, strippedRow } = await import('../lib/cases.mjs');
const all = candidates(fx.shout);
const byTask = n => all.find(c => c.task === n);

test('candidates maps a task to its commit and reads it at the base commit', () => {
  const c = byTask(1);
  assert.deepEqual([c.plan, c.title, c.base, c.result], [PLAN, 'Greet', fx.planned, fx.greet]);
  assert.deepEqual(c.axes, { files: 1, spec: 0, coupling: 0, risk: 0, total: 1 });
  assert.deepEqual([c.allowed, c.tests], [['src/greet.sh', 'tests/greet.test.sh'], ['tests/greet.test.sh']]);
  assert.deepEqual(byTask(2).tests, ['tests/shout.test.sh']);
});

test('plans keeps the dated plans inside the eval window', () => {
  const names = ['2026-09-10-early.md', '2026-10-01-late.md', 'completed.md'];
  for (const name of names) writeFileSync(join(fx.repo, 'docs/superpowers/plans', name), 'x\n');
  spawnSync('git', ['add', '-A'], { cwd: fx.repo });
  spawnSync('git', ['-c', 'user.name=t', '-c', 'user.email=t@example.invalid', 'commit', '-q', '-m', 'docs: add other plans'], { cwd: fx.repo });
  assert.deepEqual(plans('HEAD'), [PLAN]);
});

test('candidates gives the reason a task is ineligible', () => {
  assert.equal(byTask(3).reason, '0 commits match the commit message');
  assert.equal(candidates('HEAD').find(c => c.task === 3).reason, 'no test file in the Files block');
});

test('golden accepts a case that discriminates and names why another does not', async () => {
  assert.equal(await golden(byTask(1)), null);
  const idle = candidates('HEAD').find(c => c.task === 4);
  assert.equal(await golden(idle), 'the tests already pass on the base commit');
  assert.equal(await golden({ ...byTask(1), allowed: ['src/greet.sh'] }), 'the result commit changes tests/greet.test.sh, outside the Files block');
  assert.equal(await golden({ ...byTask(1), task: 9 }), 'the brief does not build');
});

test('strippedRow re-scores a stripped task and refuses one that breaks Rule S', () => {
  assert.equal(strippedRow(byTask(2)), 5);
  assert.equal(strippedRow({ ...byTask(2), axes: { ...byTask(2).axes, coupling: 1 } }), null);
  assert.equal(strippedRow({ ...byTask(2), axes: { ...byTask(2).axes, spec: 2 } }), null);
});

test('select takes round-robin across plans up to the cap', () => {
  const cases = [];
  for (const plan of ['b', 'a']) for (let task = 6; task >= 1; task--) cases.push({ plan, task });
  assert.deepEqual(select(cases).map(c => `${c.plan}${c.task}`), ['a1', 'b1', 'a2', 'b2', 'a3', 'b3', 'a4', 'b4']);
  assert.equal(select(cases.slice(0, 3)).length, 3);
});

test('readManifest reads the start commit and typed rows, and refuses a file without one', () => {
  const file = join(fx.top, 'manifest.tsv');
  writeFileSync(file, `# start ${fx.planned}\nid\tpool\trow\tplan\ttask\tbase\tresult\nw-x-t2\twritten\t3\tp.md\t2\tb\tr\n`);
  assert.deepEqual(readManifest(file), { start: fx.planned, cases: [{ id: 'w-x-t2', pool: 'written', row: 3, plan: 'p.md', task: 2, base: 'b', result: 'r' }] });
  writeFileSync(file, 'id\tpool\n');
  assert.throws(() => readManifest(file), /the first line must be "# start <commit>"/);
});

test('slug drops the date and the plugin prefix', () => {
  assert.deepEqual([slug('docs/superpowers/plans/2026-09-15-dr-superpowers-review-routing.md'), slug(PLAN)], ['review-routing', 'fixture']);
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `timeout 300 node --test evals/tiers/tests/cases.test.mjs`
Expected: FAIL — `ERR_MODULE_NOT_FOUND` naming `lib/cases.mjs`

- [ ] **Step 3: Write the implementation**

Create `evals/tiers/lib/cases.mjs`:

```js
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { basename, join, resolve } from 'node:path';
import { DATA, git, sh } from './sh.mjs';
import { tasks, taskText, evaluation, commitMessages, filesBlock, taskBrief } from './plan.mjs';
import { snapshot } from './snapshot.mjs';
import { overlayTests, runTests } from './grade.mjs';
import { addedLines, strip } from './strip.mjs';

const PLAN_DIR = 'docs/superpowers/plans';
const FIRST_PLAN_DATE = '2026-09-11';
const LAST_PLAN_DATE = '2026-09-30';
const RUNNABLE = /\.test\.(sh|mjs)$/;
export const CAP = 8;
export const MANIFEST = resolve(DATA, 'cases/manifest.tsv');

// plans START — the dated plan files at START from FIRST_PLAN_DATE, the day
// dr-superpowers became the plugin these plans build, to LAST_PLAN_DATE, the
// last plan written before this eval: its own plan is not one of its cases.
export function plans(start) {
  return git(['ls-tree', '--name-only', `${start}:${PLAN_DIR}`]).split('\n')
    .filter(name => /^\d{4}-\d{2}-\d{2}-.+\.md$/.test(name) && name.slice(0, 10) >= FIRST_PLAN_DATE && name.slice(0, 10) <= LAST_PLAN_DATE)
    .sort().map(name => `${PLAN_DIR}/${name}`);
}

// planAt COMMIT PLAN DIR — PLAN as it stood at COMMIT, written into DIR, or
// null when COMMIT has no such file.
export function planAt(commit, plan, dir) {
  const shown = sh('git', ['show', `${commit}:${plan}`]);
  if (shown.code !== 0) return null;
  mkdirSync(dir, { recursive: true });
  const file = join(dir, 'plan.md');
  writeFileSync(file, shown.out);
  return file;
}

// candidates START — every task of every plan as { plan, task, title } plus
// either { reason } when it is ineligible or the fields a case needs. The
// task is found in the plan at START and then read as it stood at its base
// commit, which is the text its implementer saw.
export function candidates(start) {
  const subjects = new Map();
  for (const line of git(['log', '--format=%H%x09%s', start]).split('\n').filter(Boolean)) {
    const [sha, subject] = line.split('\t');
    subjects.set(subject, [...(subjects.get(subject) ?? []), sha]);
  }
  const tmp = mkdtempSync(join(tmpdir(), 'tier-eval-plan-'));
  const out = [];
  try {
    for (const plan of plans(start)) {
      const head = planAt(start, plan, tmp);
      for (const { n, title } of tasks(head)) {
        out.push({ plan, task: n, title, ...candidate(plan, n, taskText(head, n), subjects, tmp) });
      }
    }
  } finally {
    rmSync(tmp, { recursive: true, force: true });
  }
  return out;
}

function candidate(plan, task, headText, subjects, tmp) {
  const messages = commitMessages(headText);
  if (messages.length !== 1) return { reason: `${messages.length} commit messages in the task` };
  const shas = subjects.get(messages[0]) ?? [];
  if (shas.length !== 1) return { reason: `${shas.length} commits match the commit message` };
  const result = shas[0];
  const base = git(['rev-parse', `${result}^`]).trim();
  const at = planAt(base, plan, tmp);
  if (at === null) return { reason: 'no plan at the base commit' };
  const text = taskText(at, task);
  if (text === null) return { reason: 'no such task at the base commit' };
  const axes = evaluation(text);
  if (!axes) return { reason: 'not exactly one Evaluation line' };
  const { allowed, tests } = filesBlock(text);
  if (tests.length === 0) return { reason: 'no test file in the Files block' };
  if (!tests.every(t => RUNNABLE.test(t))) return { reason: 'a Test file has no runner' };
  return { base, result, axes, allowed, tests };
}

// golden CASE — null when the brief builds, the grader passes on the result
// commit and it fails on the base commit; else the reason the case is unusable.
export async function golden(c) {
  const touched = git(['diff', '--name-only', c.base, c.result]).split('\n').filter(Boolean);
  const outside = touched.filter(p => !c.allowed.includes(p));
  if (outside.length > 0) return `the result commit changes ${outside[0]}, outside the Files block`;
  const tmp = mkdtempSync(join(tmpdir(), 'tier-eval-golden-'));
  try {
    try { brief(c, join(tmp, 'brief')); } catch { return 'the brief does not build'; }
    snapshot(c.result, join(tmp, 'result'));
    const good = await runTests(join(tmp, 'result'), c.tests);
    if (!good.pass) return `${good.failed} fails on the result commit`;
    snapshot(c.base, join(tmp, 'base'));
    if (!overlayTests(join(tmp, 'base'), c.result, c.tests)) return 'a test file is missing at the result commit';
    const bad = await runTests(join(tmp, 'base'), c.tests);
    return bad.pass ? 'the tests already pass on the base commit' : null;
  } finally {
    rmSync(tmp, { recursive: true, force: true });
  }
}

// brief CASE DIR — the as-written brief of CASE, built from the plan at its
// base commit.
export function brief(c, dir) {
  const plan = planAt(c.base, c.plan, dir);
  if (plan === null) throw new Error(`${c.plan} is missing at ${c.base}`);
  return taskBrief(plan, c.task, dir);
}

// strippedRow CASE — the row a stripped CASE files under, or null when
// stripping it would break Rule S or removes nothing. Stripping raises spec
// completeness to 2, so the total is files + 2 + coupling + risk.
export function strippedRow(c) {
  const { files, spec, coupling, risk } = c.axes;
  if (spec > 1 || files + coupling > 1) return null;
  const tmp = mkdtempSync(join(tmpdir(), 'tier-eval-strip-'));
  try {
    return strip(brief(c, tmp), addedLines(c.base, c.result)).removed > 0 ? files + 2 + coupling + risk : null;
  } finally {
    rmSync(tmp, { recursive: true, force: true });
  }
}

export function slug(plan) {
  return basename(plan, '.md').replace(/^\d{4}-\d{2}-\d{2}-/, '').replace(/^dr-superpowers-/, '');
}

// select CASES — at most CAP of CASES, taken round-robin across plans in plan
// order and, inside a plan, in task order.
export function select(cases) {
  const byPlan = new Map();
  for (const c of [...cases].sort((a, b) => a.plan.localeCompare(b.plan) || a.task - b.task)) {
    byPlan.set(c.plan, [...(byPlan.get(c.plan) ?? []), c]);
  }
  const picked = [];
  while (picked.length < CAP && [...byPlan.values()].some(list => list.length > 0)) {
    for (const list of byPlan.values()) {
      if (list.length > 0 && picked.length < CAP) picked.push(list.shift());
    }
  }
  return picked;
}

export function readManifest(file = MANIFEST) {
  const lines = readFileSync(file, 'utf8').split('\n').filter(Boolean);
  const start = lines[0].match(/^# start ([0-9a-f]{40})$/)?.[1];
  if (!start) throw new Error(`${file}: the first line must be "# start <commit>"`);
  const keys = lines[1].split('\t');
  const cases = lines.slice(2).map(line => Object.fromEntries(line.split('\t').map((v, i) => [keys[i], v])));
  return { start, cases: cases.map(c => ({ ...c, row: Number(c.row), task: Number(c.task) })) };
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `timeout 300 node --test evals/tiers/tests/cases.test.mjs`
Expected: PASS — `pass 8`, `fail 0`

- [ ] **Step 5: Commit**

```bash
git add evals/tiers/lib/cases.mjs evals/tiers/tests/cases.test.mjs
git commit -m "feat(evals): enumerate and select eval cases"
```

### Task 6: Manifest builder

**Files:**
- Create: `evals/tiers/build-manifest.mjs`
- Create: `evals/tiers/arms.json`
- Test: `evals/tiers/tests/manifest.test.mjs`

**Interfaces:**
- Consumes: `candidates`, `golden`, `select`, `slug`, `strippedRow`, `CAP`, `MANIFEST`, `readManifest` — Contracts, `lib/cases.mjs`; `DATA`, `git`, `PLUGIN` — `lib/sh.mjs`.
- Produces: `build-manifest.mjs` and `arms.json` — Contracts, Scripts and Files.

**Items:** 1
**Implementer:** dr-superpowers:impl-sonnet-high
**Evaluation:** files 1 - spec 0 - coupling 2 - risk 0 = 3

- [ ] **Step 1: Write the failing test**

Create `evals/tiers/tests/manifest.test.mjs`:

```js
import assert from 'node:assert/strict';
import { existsSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { after, test } from 'node:test';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { PLAN, fixture } from './fixture.mjs';

const fx = fixture();
after(() => rmSync(fx.top, { recursive: true, force: true }));
const { PLUGIN } = await import('../lib/sh.mjs');
const { readManifest } = await import('../lib/cases.mjs');
const build = () => spawnSync(process.execPath, [fileURLToPath(new URL('../build-manifest.mjs', import.meta.url))], { cwd: fx.repo, encoding: 'utf8' });

test('build-manifest writes the selected cases and every exclusion', () => {
  const r = build();
  assert.equal(r.status, 0, r.stderr);
  assert.match(r.stdout, /build-manifest: 2 cases, 4 exclusions, start [0-9a-f]{40}/);
  const { start, cases } = readManifest(join(fx.data, 'cases/manifest.tsv'));
  assert.match(start, /^[0-9a-f]{40}$/);
  assert.deepEqual(cases.map(c => [c.id, c.pool, c.row, c.task, c.base, c.result]), [
    ['s-fixture-t2', 'stripped', 5, 2, fx.greet, fx.shout],
    ['w-fixture-t1', 'written', 1, 1, fx.planned, fx.greet],
  ]);
  assert.equal(readFileSync(join(fx.data, 'cases/excluded.tsv'), 'utf8'), [
    'plan\ttask\tpool\treason',
    `${PLAN}\t1\tstripped\trow 3 has no arms`,
    `${PLAN}\t2\twritten\trow 3 has no arms`,
    `${PLAN}\t3\t-\tno test file in the Files block`,
    `${PLAN}\t4\t-\tthe tests already pass on the base commit`,
    '',
  ].join('\n'));
});

test('build-manifest refuses to pin a start commit while the plugin is dirty', () => {
  writeFileSync(join(fx.repo, 'plugins/dr-superpowers/marker.txt'), 'changed\n');
  const r = build();
  writeFileSync(join(fx.repo, 'plugins/dr-superpowers/marker.txt'), 'fixture\n');
  assert.equal(r.status, 2);
  assert.match(r.stderr, /plugins\/dr-superpowers has uncommitted changes/);
});

test('every arm of the real arms table names an agent the plugin ships', () => {
  const arms = JSON.parse(readFileSync(new URL('../arms.json', import.meta.url), 'utf8'));
  assert.deepEqual(Object.keys(arms.rows), ['1', '2', '3', '4', '5', '6']);
  for (const arm of [...Object.values(arms.rows).flat(), ...arms.review]) {
    assert.equal(existsSync(resolve(PLUGIN, 'agents', `${arm.split('@')[0]}.md`)), true, arm);
  }
  assert.deepEqual(arms.grader, { model: 'opus', effort: 'low' });
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `timeout 300 node --test evals/tiers/tests/manifest.test.mjs`
Expected: FAIL — three failing tests: `build-manifest.mjs` does not exist, so its exit status is 1, and `arms.json` is `ENOENT`

- [ ] **Step 3: Write the implementation**

Create `evals/tiers/build-manifest.mjs`:

```js
#!/usr/bin/env node
// Enumerate every eligible task, run the free golden check on each, select the
// cases and write cases/manifest.tsv and cases/excluded.tsv.
// Usage: node evals/tiers/build-manifest.mjs
// Exit: 0 written; 2 the plugin has uncommitted changes.
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { DATA, git } from './lib/sh.mjs';
import { CAP, MANIFEST, candidates, golden, select, slug, strippedRow } from './lib/cases.mjs';

const JOBS = 6;
if (git(['status', '--porcelain', '--', 'plugins/dr-superpowers']).trim() !== '') {
  console.error('build-manifest: plugins/dr-superpowers has uncommitted changes');
  process.exit(2);
}
const start = git(['rev-parse', 'HEAD']).trim();
const arms = JSON.parse(readFileSync(resolve(DATA, 'arms.json'), 'utf8'));
const all = candidates(start);
const queue = all.filter(c => !c.reason);
await Promise.all(Array.from({ length: JOBS }, async () => {
  for (let c = queue.shift(); c; c = queue.shift()) {
    const why = await golden(c);
    if (why) c.reason = why;
  }
}));

const pools = new Map();
const excluded = all.filter(c => c.reason).map(c => [c.plan, c.task, '-', c.reason]);
function file(pool, row, c) {
  if (!arms.rows[row]) { excluded.push([c.plan, c.task, pool, `row ${row} has no arms`]); return; }
  const key = `${pool}\t${row}`;
  pools.set(key, [...(pools.get(key) ?? []), c]);
}
for (const c of all.filter(c => !c.reason)) {
  file('written', c.axes.total, c);
  const row = strippedRow(c);
  if (row !== null) file('stripped', row, c);
}

const lines = [`# start ${start}`, ['id', 'pool', 'row', 'plan', 'task', 'base', 'result'].join('\t')];
for (const key of [...pools.keys()].sort()) {
  const [pool, row] = key.split('\t');
  const picked = select(pools.get(key));
  for (const c of picked) lines.push([`${pool[0]}-${slug(c.plan)}-t${c.task}`, pool, row, c.plan, c.task, c.base, c.result].join('\t'));
  for (const c of pools.get(key).filter(c => !picked.includes(c))) excluded.push([c.plan, c.task, pool, `not selected: row ${row} already has ${CAP} cases`]);
}
excluded.sort((a, b) => a[0].localeCompare(b[0]) || a[1] - b[1] || a[2].localeCompare(b[2]));
mkdirSync(dirname(MANIFEST), { recursive: true });
writeFileSync(MANIFEST, lines.join('\n') + '\n');
writeFileSync(resolve(DATA, 'cases/excluded.tsv'), ['plan\ttask\tpool\treason', ...excluded.map(e => e.join('\t'))].join('\n') + '\n');
console.log(`build-manifest: ${lines.length - 2} cases, ${excluded.length} exclusions, start ${start}`);
```

Create `evals/tiers/arms.json`:

```json
{
  "rows": {
    "1": ["impl-sonnet-low", "impl-haiku"],
    "2": ["impl-sonnet-medium", "impl-sonnet-low"],
    "3": ["impl-sonnet-high", "impl-sonnet-medium"],
    "4": ["impl-sonnet-high", "impl-sonnet-medium"],
    "5": ["impl-opus-medium", "impl-opus-low", "impl-sonnet-high"],
    "6": ["impl-opus-high", "impl-opus-medium"]
  },
  "review": ["judge-opus@high", "judge-opus@medium", "judge-sonnet-high"],
  "grader": { "model": "opus", "effort": "low" }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `timeout 300 node --test evals/tiers/tests/manifest.test.mjs`
Expected: PASS — `pass 3`, `fail 0`

- [ ] **Step 5: Commit**

```bash
git add evals/tiers/build-manifest.mjs evals/tiers/arms.json evals/tiers/tests/manifest.test.mjs
git commit -m "feat(evals): build the case manifest"
```

### Task 7: Headless CLI call

**Files:**
- Create: `evals/tiers/lib/claude.mjs`
- Test: `evals/tiers/tests/claude.test.mjs`

**Interfaces:**
- Consumes: `PLUGIN`, `run` — Contracts, `lib/sh.mjs`; `fixture()`, `modes()` — Test fixture; the agent files under `plugins/dr-superpowers/agents/`, which already exist.
- Produces: `agent`, `invoke`, `classify` — Contracts, `lib/claude.mjs`.

**Items:** 1
**Implementer:** dr-superpowers:impl-sonnet-high
**Evaluation:** files 1 - spec 0 - coupling 2 - risk 0 = 3

- [ ] **Step 1: Write the failing test**

Create `evals/tiers/tests/claude.test.mjs`:

```js
import assert from 'node:assert/strict';
import { readFileSync, rmSync } from 'node:fs';
import { join } from 'node:path';
import { after, test } from 'node:test';
import { fixture, modes } from './fixture.mjs';

const fx = fixture();
after(() => rmSync(fx.top, { recursive: true, force: true }));
const { agent, classify, invoke } = await import('../lib/claude.mjs');
const lastCall = () => JSON.parse(readFileSync(join(fx.stub, 'calls.log'), 'utf8').trim().split('\n').at(-1));

test('agent reads the model, the effort and the body, and an arm can override the effort', () => {
  const high = agent('impl-sonnet-high');
  assert.deepEqual([high.model, high.effort], ['sonnet', 'high']);
  assert.match(high.body, /^You are a task implementer\./);
  assert.doesNotMatch(high.body, /^---|^model:/m);
  assert.deepEqual([agent('judge-opus@medium').model, agent('judge-opus@medium').effort], ['opus', 'medium']);
  assert.deepEqual([agent('impl-haiku').model, agent('impl-haiku').effort], ['haiku', null]);
});

test('classify tells a limit, a budget stop, an error and a timeout apart', () => {
  const run = (out, extra = {}) => classify({ out, err: '', code: 0, timedOut: false, ...extra }, 2);
  assert.equal(run(JSON.stringify({ result: 'hi', total_cost_usd: 0.25, num_turns: 2, modelUsage: { m: {} } })).kind, 'ok');
  assert.deepEqual(run(JSON.stringify([{ type: 'system' }, { type: 'result', result: 'hi', total_cost_usd: 0.25, num_turns: 2, modelUsage: { b: {}, a: {} } }])),
    { kind: 'ok', text: 'hi', cost: 0.25, seconds: 2, turns: 2, model: 'a+b' });
  assert.equal(run(JSON.stringify({ is_error: true, result: "You've hit your usage limit" }), { code: 1 }).kind, 'limit');
  assert.equal(run(JSON.stringify({ is_error: true, subtype: 'error_max_budget_usd' }), { code: 1 }).kind, 'budget');
  assert.equal(run(JSON.stringify({ is_error: true, subtype: 'error_max_budget_usd', result: 'Reached the budget: usage limit of $5', total_cost_usd: 5.1 }), { code: 1 }).kind, 'budget');
  assert.equal(run(JSON.stringify({ is_error: true, result: 'Budget limit reached', total_cost_usd: 5.1 }), { code: 1 }).kind, 'cut');
  assert.equal(run(JSON.stringify({ is_error: true, result: 'bad flag' }), { code: 1 }).kind, 'error');
  assert.equal(run(JSON.stringify({ is_error: true, subtype: 'error_during_execution', total_cost_usd: 1.5 }), { code: 1 }).kind, 'cut');
  assert.equal(run(JSON.stringify({ is_error: true, result: 'API Error: overloaded', total_cost_usd: 1.5 }), { code: 1 }).kind, 'limit');
  assert.equal(run('not json', { code: 1 }).kind, 'error');
  assert.equal(run('API Error: 429 rate limit', { code: 1 }).kind, 'limit');
  assert.equal(run('', { timedOut: true }).kind, 'timeout');
});

test('invoke passes the arm and the isolation flags, and keeps the raw output', async () => {
  modes(fx.stub, 'blocked');
  const dir = join(fx.work, 'call');
  const inv = await invoke({ ...agent('impl-sonnet-low'), prompt: 'do it', cwd: fx.repo, tools: ['Bash', 'Read'], seconds: 60, dir });
  assert.deepEqual([inv.kind, inv.cost, inv.turns, inv.model], ['ok', 0.5, 3, 'stub-model']);
  assert.match(inv.text, /BLOCKED/);
  const call = lastCall();
  assert.deepEqual(call.args, ['-p', '--model', 'sonnet', '--effort', 'low', '--append-system-prompt-file', join(dir, 'agent.md'),
    '--setting-sources', 'project', '--tools', 'Bash,Read', '--allowedTools', 'Bash,Read', '--permission-mode', 'acceptEdits',
    '--output-format', 'json', '--no-session-persistence', '--max-budget-usd', '5']);
  assert.deepEqual([call.prompt, call.cwd], ['do it', fx.repo]);
  assert.match(readFileSync(join(dir, 'agent.md'), 'utf8'), /^You are a task implementer\./);
  assert.match(readFileSync(join(dir, 'output.json'), 'utf8'), /"result"/);
});

test('invoke omits the effort, the body and the permission flags when there are none', async () => {
  modes(fx.stub, 'limit');
  const inv = await invoke({ model: 'opus', effort: null, body: null, prompt: 'grade', cwd: fx.repo, tools: [], seconds: 60, dir: join(fx.work, 'bare') });
  assert.equal(inv.kind, 'limit');
  assert.deepEqual(lastCall().args, ['-p', '--model', 'opus', '--setting-sources', 'project', '--tools', '', '--output-format', 'json', '--no-session-persistence', '--max-budget-usd', '5']);
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `timeout 300 node --test evals/tiers/tests/claude.test.mjs`
Expected: FAIL — `ERR_MODULE_NOT_FOUND` naming `lib/claude.mjs`

- [ ] **Step 3: Write the implementation**

Create `evals/tiers/lib/claude.mjs`:

```js
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { PLUGIN, run } from './sh.mjs';

const LIMIT = /usage limit|rate limit|rate_limit|\b429\b|overloaded/i;
const BUDGET_USD = '5';

// agent ARM — an arm is an agent name, or `name@effort` to run that agent's
// body at another effort. The model and the default effort come from the
// agent's frontmatter; the body is everything after it.
export function agent(arm) {
  const [name, override] = arm.split('@');
  const text = readFileSync(resolve(PLUGIN, 'agents', `${name}.md`), 'utf8');
  const m = text.match(/^---\n([\s\S]*?)\n---\n([\s\S]*)$/);
  if (!m) throw new Error(`${name}: no frontmatter`);
  const field = key => m[1].match(new RegExp(`^${key}:\\s*(\\S+)\\s*$`, 'm'))?.[1] ?? null;
  return { model: field('model'), effort: override ?? field('effort'), body: m[2].trim() + '\n' };
}

// invoke { model, effort, body, prompt, cwd, tools, seconds, dir } — one
// headless run. Resolves { kind, text, cost, seconds, turns, model } where
// kind is ok, timeout, budget, cut, limit or error. Raw output is kept in DIR.
export async function invoke({ model, effort, body, prompt, cwd, tools, seconds, dir }) {
  mkdirSync(dir, { recursive: true });
  const args = ['-p', '--model', model];
  if (effort) args.push('--effort', effort);
  if (body) {
    writeFileSync(join(dir, 'agent.md'), body);
    args.push('--append-system-prompt-file', join(dir, 'agent.md'));
  }
  args.push('--setting-sources', 'project', '--tools', tools.join(','));
  if (tools.length > 0) args.push('--allowedTools', tools.join(','), '--permission-mode', 'acceptEdits');
  args.push('--output-format', 'json', '--no-session-persistence', '--max-budget-usd', BUDGET_USD);
  writeFileSync(join(dir, 'prompt.txt'), prompt);
  const started = Date.now();
  const r = await run(process.env.TIER_EVAL_CLAUDE ?? 'claude', args, { cwd, seconds, input: prompt });
  writeFileSync(join(dir, 'output.json'), r.out);
  writeFileSync(join(dir, 'stderr.txt'), r.err);
  return classify(r, (Date.now() - started) / 1000);
}

export function classify(r, elapsed) {
  const base = { text: '', cost: 0, seconds: Math.round(elapsed), turns: 0, model: '' };
  if (r.timedOut) return { ...base, kind: 'timeout' };
  let json = null;
  try {
    const parsed = JSON.parse(r.out);
    json = Array.isArray(parsed) ? parsed.findLast(e => e.type === 'result') : parsed;
  } catch {}
  if (!json) return { ...base, kind: LIMIT.test(r.out + r.err) ? 'limit' : 'error', text: (r.out + r.err).slice(-500) };
  const found = {
    text: json.result ?? '',
    cost: Number(json.total_cost_usd ?? 0),
    seconds: Math.round(elapsed),
    turns: Number(json.num_turns ?? 0),
    model: Object.keys(json.modelUsage ?? {}).sort().join('+'),
  };
  if (!json.is_error && r.code === 0) return { ...found, kind: 'ok' };
  // The budget stop is read first: its message may speak of a limit, and read
  // as a usage limit it would be retried at full price on every invocation.
  if (/budget/.test(json.subtype ?? '')) return { ...found, kind: 'budget' };
  if (LIMIT.test(`${json.result ?? ''} ${json.api_error_status ?? ''} ${r.err}`)) return { ...found, kind: 'limit' };
  // An error that arrives after the run spent something would be retried at
  // full price on every invocation, so it settles the cell as cut short.
  return { ...found, kind: found.cost > 0 ? 'cut' : 'error' };
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `timeout 300 node --test evals/tiers/tests/claude.test.mjs`
Expected: PASS — `pass 4`, `fail 0`

- [ ] **Step 5: Commit**

```bash
git add evals/tiers/lib/claude.mjs evals/tiers/tests/claude.test.mjs
git commit -m "feat(evals): call the headless CLI"
```

### Task 8: Case building and the implementation grader

**Files:**
- Create: `evals/tiers/build-case.mjs`
- Create: `evals/tiers/grade-case.mjs`
- Test: `evals/tiers/tests/build.test.mjs`

**Interfaces:**
- Consumes: `lib/sh.mjs`, `lib/cases.mjs`, `lib/plan.mjs`, `lib/prompt.mjs`, `lib/snapshot.mjs`, `lib/strip.mjs`, `lib/grade.mjs`, `classify` — Contracts; the three prompt templates under `plugins/dr-superpowers/skills/`, which already exist.
- Produces: `build-case.mjs` and `grade-case.mjs` — Contracts, Scripts; the run directory layout under Files.

**Items:** 1
**Implementer:** dr-superpowers:impl-sonnet-high
**Evaluation:** files 1 - spec 0 - coupling 2 - risk 0 = 3

- [ ] **Step 1: Write the failing test**

Create `evals/tiers/tests/build.test.mjs`:

```js
import assert from 'node:assert/strict';
import { existsSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { after, test } from 'node:test';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { PLAN, fixture } from './fixture.mjs';

const fx = fixture();
after(() => rmSync(fx.top, { recursive: true, force: true }));
const { buildCase, buildReview } = await import('../build-case.mjs');
const { gradeImpl } = await import('../grade-case.mjs');
const { MARKER } = await import('../lib/strip.mjs');

const greet = { id: 'w-fixture-t1', pool: 'written', row: 1, plan: PLAN, task: 1, base: fx.planned, result: fx.greet };
const shout = { id: 's-fixture-t2', pool: 'stripped', row: 5, plan: PLAN, task: 2, base: fx.greet, result: fx.shout };
const done = { kind: 'ok', text: '**Status:** DONE' };
const script = name => fileURLToPath(new URL(`../${name}`, import.meta.url));

// built — a fresh greet case with the historical change applied, as a run
// that implemented the task would leave it.
function built(name) {
  const { info } = buildCase(greet, join(fx.work, name));
  spawnSync('git', ['apply', join(fx.stub, 'greet.patch')], { cwd: info.work });
  return info;
}

test('an as-written case is the base snapshot with the brief where production puts it', () => {
  const dir = join(fx.work, 'written');
  const { info, prompt } = buildCase(greet, dir);
  assert.deepEqual([info.id, info.kind, info.work, info.result, info.allowed, info.tests], ['w-fixture-t1', 'impl', join(dir, 'work'), fx.greet, ['src/greet.sh', 'tests/greet.test.sh'], ['tests/greet.test.sh']]);
  assert.deepEqual(JSON.parse(readFileSync(join(dir, 'case.json'), 'utf8')), info);
  assert.equal(existsSync(join(info.work, 'src/greet.sh')), false);
  assert.match(readFileSync(join(info.work, '.superpowers/sdd/eval/task-1-brief.md'), 'utf8'), /echo hello/);
  assert.match(prompt, /^You are implementing Task 1: Greet\n/);
  assert.match(prompt, new RegExp(`Read your task brief first: ${join(info.work, '.superpowers/sdd/eval/task-1-brief.md')}`));
  assert.match(prompt, /This is Task 1 of the plan 2026-09-20-fixture\.md\./);
  assert.match(prompt, new RegExp(`Work from: ${info.work}`));
  assert.doesNotMatch(prompt, /\[BRIEF_FILE\]|\[REPORT_FILE\]|\[directory\]|\[task name\]|write that code yourself/);
});

test('a stripped case hides the implementation and the plan', () => {
  const { info, prompt } = buildCase(shout, join(fx.work, 'stripped'));
  const brief = readFileSync(join(info.work, '.superpowers/sdd/eval/task-2-brief.md'), 'utf8');
  assert.equal(brief.split(MARKER).length - 1, 1);
  assert.doesNotMatch(brief, /echo HELLO/);
  assert.match(brief, /\[ "\$out" = "HELLO" \]/);
  assert.equal(existsSync(join(info.work, 'docs/superpowers')), false);
  assert.equal(existsSync(join(info.work, 'src/greet.sh')), true);
  assert.match(prompt, /write that code yourself\. The plan file is not available\./);
  assert.deepEqual([info.allowed, info.tests], [['src/shout.sh', 'tests/shout.test.sh'], ['tests/shout.test.sh']]);
});

test('a code review case snapshots the head and hands over one diff file', () => {
  const { info, prompt } = buildReview({ id: 'r-code-fixture', kind: 'code', base: fx.planned, head: fx.greet, plan: PLAN, description: 'Adds the greet script.' }, join(fx.work, 'codereview'));
  const diffFile = join(info.work, '.superpowers/sdd/eval/review.diff');
  assert.match(readFileSync(diffFile, 'utf8'), /feat: add greet[\s\S]*2 files changed[\s\S]*\+echo hello/);
  assert.deepEqual([existsSync(join(info.work, 'src/greet.sh')), existsSync(join(info.work, 'src/shout.sh'))], [true, false]);
  assert.match(prompt, /## What Was Implemented\n\nAdds the greet script\./);
  assert.match(prompt, new RegExp(`Read this file first: ${diffFile}`));
  assert.match(prompt, new RegExp(`for ${fx.planned.slice(0, 7)}\\.\\.${fx.greet.slice(0, 7)}`));
  assert.doesNotMatch(prompt, /\[DESCRIPTION\]|\[PLAN_OR_REQUIREMENTS\]|\[DIFF_FILE\]|\[BASE_SHA\]|\[HEAD_SHA\]/);
});

test('a plan review case hides the earlier verdict and supplies the criteria', () => {
  const { info, prompt } = buildReview({ id: 'r-plan-fixture', kind: 'plan', commit: fx.planned, plan: PLAN, spec: PLAN }, join(fx.work, 'planreview'));
  assert.doesNotMatch(readFileSync(join(info.work, PLAN), 'utf8'), /Plan review:/);
  assert.match(prompt, /\*\*Plan:\*\* .*2026-09-20-fixture\.md/);
  const root = prompt.match(/Read the criteria file at (\S+)\/criteria\/plan-review\.md/)[1];
  assert.equal(existsSync(join(root, 'criteria/plan-review.md')), true);
  assert.match(readFileSync(prompt.match(/\*\*plan-lint output:\*\* (\S+)/)[1], 'utf8'), /was not run/);
  assert.throws(() => buildReview({ id: 'r-plan-bad', kind: 'plan', commit: fx.planned, plan: PLAN, spec: 'docs/none.md' }, join(fx.work, 'bad')), /docs\/none\.md is missing/);
});

test('gradeImpl passes the historical change and fails a wrong, cheating or stray one', async () => {
  assert.deepEqual(await gradeImpl(built('g-pass'), done), { outcome: 'PASS', detail: 'status=DONE' });
  const wrong = built('g-wrong');
  writeFileSync(join(wrong.work, 'src/greet.sh'), 'echo nope\n');
  assert.deepEqual(await gradeImpl(wrong, done), { outcome: 'FAIL', detail: 'status=DONE failed=tests/greet.test.sh' });
  const cheat = built('g-cheat');
  writeFileSync(join(cheat.work, 'src/greet.sh'), 'echo nope\n');
  writeFileSync(join(cheat.work, 'tests/greet.test.sh'), 'true\n');
  assert.equal((await gradeImpl(cheat, done)).outcome, 'FAIL');
  const stray = built('g-stray');
  writeFileSync(join(stray.work, 'extra.txt'), 'x\n');
  assert.deepEqual(await gradeImpl(stray, done), { outcome: 'FAIL', detail: 'status=DONE outside=extra.txt' });
});

test('gradeImpl grades a blocked or cut-short run as BLOCKED', async () => {
  assert.equal((await gradeImpl(built('g-blocked'), { kind: 'ok', text: 'Status: BLOCKED' })).outcome, 'BLOCKED');
  assert.deepEqual(await gradeImpl(built('g-timeout'), { kind: 'timeout', text: '' }), { outcome: 'BLOCKED', detail: 'status=none cut=timeout' });
});

test('the two command lines build a manifest case and re-grade a finished run', () => {
  const reviewDir = join(fx.work, 'cli-review');
  assert.equal(spawnSync(process.execPath, [script('build-case.mjs'), 'r-code-fixture', reviewDir]).status, 0);
  assert.match(readFileSync(join(reviewDir, 'prompt.txt'), 'utf8'), /Adds the greet script\./);
  mkdirSync(join(fx.data, 'cases'), { recursive: true });
  writeFileSync(join(fx.data, 'cases/manifest.tsv'), `# start ${fx.planned}\nid\tpool\trow\tplan\ttask\tbase\tresult\nw-fixture-t1\twritten\t1\t${PLAN}\t1\t${fx.planned}\t${fx.greet}\n`);
  const dir = join(fx.work, 'cli');
  const builtCli = spawnSync(process.execPath, [script('build-case.mjs'), 'w-fixture-t1', dir], { encoding: 'utf8' });
  assert.equal(builtCli.status, 0, builtCli.stderr);
  assert.match(readFileSync(join(dir, 'prompt.txt'), 'utf8'), /^You are implementing Task 1: Greet/);
  assert.equal(spawnSync(process.execPath, [script('build-case.mjs'), 'no-such-case', dir]).status, 2);
  spawnSync('git', ['apply', join(fx.stub, 'greet.patch')], { cwd: join(dir, 'work') });
  writeFileSync(join(dir, 'output.json'), JSON.stringify({ result: '**Status:** DONE' }));
  const graded = spawnSync(process.execPath, [script('grade-case.mjs'), dir], { encoding: 'utf8' });
  assert.deepEqual([graded.status, graded.stdout], [0, 'w-fixture-t1\tPASS\tstatus=DONE\n']);
  assert.equal(spawnSync(process.execPath, [script('grade-case.mjs'), join(fx.work, 'nowhere')]).status, 2);
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `timeout 300 node --test evals/tiers/tests/build.test.mjs`
Expected: FAIL — `ERR_MODULE_NOT_FOUND` naming `build-case.mjs`

- [ ] **Step 3: Write the implementation**

Create `evals/tiers/build-case.mjs`:

```js
#!/usr/bin/env node
// Build the snapshot, the brief and the prompt for one case.
// Usage: node evals/tiers/build-case.mjs CASE_ID DIR
// Exit: 0 built; 2 usage or no such case.
import { copyFileSync, existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { basename, dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { DATA, PLUGIN, git } from './lib/sh.mjs';
import { MANIFEST, brief, readManifest } from './lib/cases.mjs';
import { filesBlock, tasks, taskText } from './lib/plan.mjs';
import { fill, template } from './lib/prompt.mjs';
import { snapshot } from './lib/snapshot.mjs';
import { MARKER, addedLines, strip } from './lib/strip.mjs';

const IMPLEMENTER = resolve(PLUGIN, 'skills/subagent-driven-development/references/implementer-prompt.md');
const CODE_REVIEWER = resolve(PLUGIN, 'skills/requesting-code-review/references/code-reviewer.md');
const PLAN_REVIEWER = resolve(PLUGIN, 'skills/writing-plans/references/plan-reviewer-prompt.md');
const SCRATCH = '.superpowers/sdd/eval';

export function reviewCases() {
  const file = resolve(DATA, 'cases/reviews/cases.json');
  return existsSync(file) ? JSON.parse(readFileSync(file, 'utf8')) : [];
}

// buildCase CASE DIR — an implementation case: DIR/work is the base commit's
// snapshot, holding the brief where production puts it. A stripped case loses
// docs/superpowers, so the plan's code cannot be read from disk.
export function buildCase(c, dir) {
  const stripped = c.pool === 'stripped';
  const work = join(dir, 'work');
  const initial = snapshot(c.base, work, stripped ? ['docs/superpowers'] : []);
  const planDir = join(dir, 'plan');
  let text = brief(c, planDir);
  if (stripped) text = strip(text, addedLines(c.base, c.result)).text;
  const planFile = join(planDir, 'plan.md');
  const { allowed, tests } = filesBlock(taskText(planFile, c.task));
  const title = tasks(planFile).find(t => t.n === c.task).title;
  mkdirSync(join(work, SCRATCH), { recursive: true });
  const briefFile = join(work, SCRATCH, `task-${c.task}-brief.md`);
  writeFileSync(briefFile, text);
  let context = `This is Task ${c.task} of the plan ${basename(c.plan)}. The tasks before it are already in this repository; the tasks after it are not your concern.`;
  if (stripped) context += ` This brief gives the prose, the signatures and the tests, but not the implementation code: wherever it shows "${MARKER}", write that code yourself. The plan file is not available.`;
  const prompt = fill(template(IMPLEMENTER), {
    'Task N: [task name]': `Task ${c.task}: ${title}`,
    '[BRIEF_FILE]': briefFile,
    '[Scene-setting: where this fits, dependencies, architectural context]': context,
    '[directory]': work,
    '[REPORT_FILE]': join(work, SCRATCH, `task-${c.task}-report.md`),
  });
  const info = { id: c.id, kind: 'impl', work, initial, result: c.result, allowed, tests };
  writeFileSync(join(dir, 'case.json'), JSON.stringify(info, null, 2) + '\n');
  return { info, prompt };
}

// buildReview CASE DIR — a review case. A code case snapshots the head commit
// and hands the reviewer one diff file for base..head. A plan case snapshots
// the plan's commit and strips the plan's first Plan review line, so the
// reviewer does not see an earlier verdict.
export function buildReview(c, dir) {
  const work = join(dir, 'work');
  const scratch = join(work, SCRATCH);
  let prompt;
  if (c.kind === 'code') {
    snapshot(c.head, work);
    mkdirSync(scratch, { recursive: true });
    const diffFile = join(scratch, 'review.diff');
    writeFileSync(diffFile, [
      git(['log', '--oneline', `${c.base}..${c.head}`]),
      git(['diff', '--stat', c.base, c.head]),
      git(['diff', c.base, c.head]),
    ].join('\n'));
    prompt = fill(template(CODE_REVIEWER), {
      '[DESCRIPTION]': c.description,
      '[PLAN_OR_REQUIREMENTS]': `The plan this branch implements: ${join(work, c.plan)}`,
      '[DIFF_FILE]': diffFile,
      '[BASE_SHA]': c.base.slice(0, 7),
      '[HEAD_SHA]': c.head.slice(0, 7),
    });
  } else {
    snapshot(c.commit, work);
    mkdirSync(join(scratch, 'plugin/criteria'), { recursive: true });
    const planFile = join(work, c.plan);
    const lines = readFileSync(planFile, 'utf8').split('\n');
    const reviewed = lines.findIndex(l => l.startsWith('**Plan review:**'));
    if (reviewed >= 0) lines.splice(reviewed, 1);
    writeFileSync(planFile, lines.join('\n'));
    if (!existsSync(join(work, c.spec))) throw new Error(`${c.id}: ${c.spec} is missing at ${c.commit}`);
    copyFileSync(resolve(PLUGIN, 'criteria/plan-review.md'), join(scratch, 'plugin/criteria/plan-review.md'));
    const lintFile = join(scratch, 'plan-lint.txt');
    writeFileSync(lintFile, 'plan-lint was not run for this replay.\n');
    prompt = fill(template(PLAN_REVIEWER), {
      '[PLAN_FILE]': planFile,
      '[SPEC_FILE]': join(work, c.spec),
      '[LINT_FILE]': lintFile,
      '[PLUGIN_ROOT]': join(scratch, 'plugin'),
    });
  }
  const info = { id: c.id, kind: 'review', work };
  writeFileSync(join(dir, 'case.json'), JSON.stringify(info, null, 2) + '\n');
  return { info, prompt };
}

// findCase ID — the manifest row or the review case with that id.
export function findCase(id) {
  const cases = existsSync(MANIFEST) ? readManifest().cases : [];
  return cases.find(c => c.id === id) ?? reviewCases().find(c => c.id === id) ?? null;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const [id, dir] = process.argv.slice(2);
  const c = id && dir ? findCase(id) : null;
  if (!c) { console.error('usage: build-case.mjs CASE_ID DIR (CASE_ID from the manifest or cases/reviews/cases.json)'); process.exit(2); }
  const built = c.pool ? buildCase(c, resolve(dir)) : buildReview(c, resolve(dir));
  writeFileSync(join(resolve(dir), 'prompt.txt'), built.prompt);
  console.log(`build-case: ${id} in ${dirname(built.info.work)}`);
}
```

Create `evals/tiers/grade-case.mjs`:

```js
#!/usr/bin/env node
// Grade one implementation run with no model call.
// Usage: node evals/tiers/grade-case.mjs RUN_DIR   (re-grades a finished run)
// Exit: 0 graded; 2 usage.
import { existsSync, readFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { classify } from './lib/claude.mjs';
import { changedFiles, outcome, overlayTests, runTests, statusWord } from './lib/grade.mjs';

// gradeImpl INFO INVOCATION — the outcome of §3 of the spec: the scope check
// reads the tree before the historical tests are laid over it.
export async function gradeImpl(info, inv) {
  const outside = changedFiles(info.work, info.initial).filter(p => !info.allowed.includes(p));
  if (!overlayTests(info.work, info.result, info.tests)) throw new Error(`${info.id}: a test file is missing at ${info.result}`);
  const tested = await runTests(info.work, info.tests);
  const status = statusWord(inv.text);
  const cutShort = inv.kind !== 'ok';
  const detail = [
    `status=${status ?? 'none'}`,
    cutShort ? `cut=${inv.kind}` : '',
    tested.pass ? '' : `failed=${tested.failed}`,
    outside.length > 0 ? `outside=${outside.join(',')}` : '',
  ].filter(Boolean).join(' ');
  return { outcome: outcome({ testsPass: tested.pass, outside, status, cutShort }), detail };
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const dir = process.argv[2] ? resolve(process.argv[2]) : null;
  if (!dir || !existsSync(join(dir, 'case.json'))) { console.error('usage: grade-case.mjs RUN_DIR'); process.exit(2); }
  const info = JSON.parse(readFileSync(join(dir, 'case.json'), 'utf8'));
  const inv = classify({ out: readFileSync(join(dir, 'output.json'), 'utf8'), err: '', code: 0, timedOut: false }, 0);
  const graded = await gradeImpl(info, inv);
  console.log(`${info.id}\t${graded.outcome}\t${graded.detail}`);
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `timeout 300 node --test evals/tiers/tests/build.test.mjs`
Expected: PASS — `pass 7`, `fail 0`

- [ ] **Step 5: Commit**

```bash
git add evals/tiers/build-case.mjs evals/tiers/grade-case.mjs evals/tiers/tests/build.test.mjs
git commit -m "feat(evals): build cases and grade a run"
```

### Task 9: Results file and running one cell

**Files:**
- Create: `evals/tiers/lib/results.mjs`
- Create: `evals/tiers/run-case.mjs`
- Test: `evals/tiers/tests/run.test.mjs`

**Interfaces:**
- Consumes: `buildCase`, `buildReview`, `findCase`, `gradeImpl`, `agent`, `invoke` — Contracts; `DATA`, `WORK` — `lib/sh.mjs`.
- Produces: everything under `lib/results.mjs` in Contracts, and `runCell`.

**Items:** 1
**Implementer:** dr-superpowers:impl-sonnet-high
**Evaluation:** files 1 - spec 0 - coupling 2 - risk 0 = 3

- [ ] **Step 1: Write the failing test**

Create `evals/tiers/tests/run.test.mjs`:

```js
import assert from 'node:assert/strict';
import { existsSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { after, test } from 'node:test';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { PLAN, fixture, modes } from './fixture.mjs';

const fx = fixture();
after(() => rmSync(fx.top, { recursive: true, force: true }));
const { runCell } = await import('../run-case.mjs');
const { RESULTS, RESULT_COLUMNS, appendTsv, armDir, readTsv, scored } = await import('../lib/results.mjs');

const greet = { id: 'w-fixture-t1', pool: 'written', row: 1, plan: PLAN, task: 1, base: fx.planned, result: fx.greet };
const review = { id: 'r-code-fixture', kind: 'code', base: fx.planned, head: fx.greet, plan: PLAN, description: 'Adds the greet script.' };
const lastCall = () => JSON.parse(readFileSync(join(fx.stub, 'calls.log'), 'utf8').trim().split('\n').at(-1));

async function cell(mode, arm = 'impl-sonnet-low', c = greet) {
  modes(fx.stub, mode);
  return runCell({ rep: '1', stage: 'test', c, arm });
}

test('the results file keeps one line per run and the last scored line settles a cell', () => {
  const file = join(fx.top, 'r.tsv');
  assert.deepEqual(readTsv(file), []);
  appendTsv(file, ['rep', 'case', 'arm', 'outcome', 'detail'], { rep: 1, case: 'c', arm: 'a', outcome: 'NOT_RUN', detail: 'limit:\tx\ny' });
  appendTsv(file, ['rep', 'case', 'arm', 'outcome', 'detail'], { rep: 1, case: 'c', arm: 'a', outcome: 'FAIL' });
  appendTsv(file, ['rep', 'case', 'arm', 'outcome', 'detail'], { rep: 1, case: 'c', arm: 'a', outcome: 'NOT_RUN' });
  assert.equal(readFileSync(file, 'utf8'), 'rep\tcase\tarm\toutcome\tdetail\n1\tc\ta\tNOT_RUN\tlimit: x y\n1\tc\ta\tFAIL\t\n1\tc\ta\tNOT_RUN\t\n');
  assert.equal(scored(readTsv(file), 1, 'c', 'a').outcome, 'FAIL');
  assert.equal(scored(readTsv(file), 2, 'c', 'a'), undefined);
  assert.equal(armDir(3, 'c', 'judge-opus@medium'), join(fx.work, 'rep3/c/judge-opus-at-medium'));
});

test('a run that implements the task passes and records what the CLI reported', async () => {
  const row = await cell('pass');
  assert.deepEqual([row.outcome, row.detail, row.model, row.cost, row.turns, row.pool, row.row, row.stage], ['PASS', 'status=DONE', 'stub-model', '0.5000', 3, 'written', 1, 'test']);
  assert.equal((await cell('concerns')).outcome, 'PASS');
});

test('the arm sets the model, the effort and the tools, and the run works in the snapshot', async () => {
  await cell('pass');
  const call = lastCall();
  const flag = name => call.args[call.args.indexOf(name) + 1];
  assert.deepEqual([flag('--model'), flag('--effort'), flag('--tools')], ['sonnet', 'low', 'Bash,Edit,Write,Read,Grep,Glob']);
  assert.equal(call.cwd, join(fx.work, 'rep1/w-fixture-t1/impl-sonnet-low/work'));
  assert.match(call.prompt, /^You are implementing Task 1: Greet\n/);
  await cell('pass', 'impl-haiku');
  assert.deepEqual([lastCall().args.includes('--effort'), lastCall().args[lastCall().args.indexOf('--model') + 1]], [false, 'haiku']);
});

test('a wrong implementation fails, even when the run rewrote the test', async () => {
  const failed = await cell('failtest');
  assert.deepEqual([failed.outcome, failed.detail], ['FAIL', 'status=DONE failed=tests/greet.test.sh']);
  assert.equal((await cell('cheat')).outcome, 'FAIL');
  const stray = await cell('outside');
  assert.deepEqual([stray.outcome, stray.detail], ['FAIL', 'status=DONE outside=extra.txt']);
});

test('a blocked report and a budget stop are BLOCKED', async () => {
  assert.equal((await cell('blocked')).outcome, 'BLOCKED');
  const row = await cell('budget');
  assert.deepEqual([row.outcome, row.detail], ['BLOCKED', 'status=none cut=budget']);
});

test('a rate limit and a crash are NOT_RUN, told apart by the detail', async () => {
  const limited = await cell('limit');
  assert.equal(limited.outcome, 'NOT_RUN');
  assert.match(limited.detail, /^limit: /);
  const crashed = await cell('crash');
  assert.equal(crashed.outcome, 'NOT_RUN');
  assert.match(crashed.detail, /^error: /);
});

test('a harness failure costs one NOT_RUN row, not the stage', async () => {
  const broken = await cell('pass', 'impl-sonnet-low', { ...greet, base: 'no-such-commit' });
  assert.deepEqual([broken.outcome, broken.cost, broken.case], ['NOT_RUN', '0.0000', 'w-fixture-t1']);
  assert.match(broken.detail, /^error: snapshot no-such-commit/);
});

test('a review cell runs read-only at the arm effort and keeps the review', async () => {
  writeFileSync(join(fx.stub, 'review.md'), '### Issues\nThe script greets in lower case only.\n');
  const row = await cell('review', 'judge-opus@medium', review);
  assert.deepEqual([row.outcome, row.pool, row.row], ['REVIEWED', 'review', '']);
  const call = lastCall();
  assert.deepEqual([call.args[call.args.indexOf('--tools') + 1], call.args[call.args.indexOf('--effort') + 1]], ['Read,Grep,Glob', 'medium']);
  assert.equal(existsSync(join(call.cwd, '.superpowers/sdd/eval/review.diff')), true);
  assert.match(readFileSync(join(armDir(1, 'r-code-fixture', 'judge-opus@medium'), 'review.md'), 'utf8'), /lower case only/);
  const cut = await cell('budget', 'judge-opus@medium', review);
  assert.deepEqual([cut.outcome, cut.detail], ['BLOCKED', 'cut=budget']);
});

test('the command line runs one manifest cell and appends its row', () => {
  mkdirSync(join(fx.data, 'cases'), { recursive: true });
  writeFileSync(join(fx.data, 'cases/manifest.tsv'), `# start ${fx.planned}\nid\tpool\trow\tplan\ttask\tbase\tresult\nw-fixture-t1\twritten\t1\t${PLAN}\t1\t${fx.planned}\t${fx.greet}\n`);
  const cli = (...args) => spawnSync(process.execPath, [fileURLToPath(new URL('../run-case.mjs', import.meta.url)), ...args], { encoding: 'utf8' });
  modes(fx.stub, 'pass', 'limit');
  const ok = cli('w-fixture-t1', 'impl-sonnet-low', '--rep', '7', '--stage', 'manual');
  assert.equal(ok.status, 0, ok.stderr);
  assert.equal(cli('w-fixture-t1', 'impl-sonnet-low', '--rep', '7').status, 1);
  assert.equal(cli('no-such-case', 'impl-sonnet-low').status, 2);
  assert.equal(cli('w-fixture-t1', 'impl-haiku', '--rep', '7', '--exclude', 'its test needs a tool this host lacks').status, 0);
  assert.deepEqual(readTsv(RESULTS).map(r => RESULT_COLUMNS.slice(0, 7).map(k => r[k]).join(' ')), ['7 manual w-fixture-t1 written 1 impl-sonnet-low PASS', '7 manual w-fixture-t1 written 1 impl-sonnet-low NOT_RUN', '7 manual w-fixture-t1 written 1 impl-haiku EXCLUDED']);
  assert.equal(readTsv(RESULTS).at(-1).detail, 'its test needs a tool this host lacks');
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `timeout 300 node --test evals/tiers/tests/run.test.mjs`
Expected: FAIL — `ERR_MODULE_NOT_FOUND` naming `run-case.mjs`

- [ ] **Step 3: Write the implementation**

Create `evals/tiers/lib/results.mjs`:

```js
import { appendFileSync, existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { DATA, WORK } from './sh.mjs';

export const RESULTS = resolve(DATA, 'results/results.tsv');
export const GRADES = resolve(DATA, 'results/review-grades.tsv');
export const RESULT_COLUMNS = ['rep', 'stage', 'case', 'pool', 'row', 'arm', 'outcome', 'model', 'cost', 'seconds', 'turns', 'detail'];
export const GRADE_COLUMNS = ['rep', 'case', 'arm', 'pass', 'defect', 'found', 'severity', 'quote'];

// armDir REP CASE ARM — where one cell keeps its snapshot and transcripts.
export const armDir = (rep, id, arm) => join(WORK, `rep${rep}`, id, arm.replace('@', '-at-'));

export function readTsv(file) {
  if (!existsSync(file)) return [];
  const [header, ...lines] = readFileSync(file, 'utf8').split('\n').filter(Boolean);
  const keys = header.split('\t');
  return lines.map(line => Object.fromEntries(line.split('\t').map((v, i) => [keys[i], v])));
}

export function appendTsv(file, columns, row) {
  mkdirSync(dirname(file), { recursive: true });
  if (!existsSync(file)) writeFileSync(file, columns.join('\t') + '\n');
  appendFileSync(file, columns.map(k => String(row[k] ?? '').replace(/[\t\n\r]+/g, ' ')).join('\t') + '\n');
}

// scored ROWS REP CASE ARM — the result that settles a cell: its last row that
// is not NOT_RUN, or undefined while the cell still has to run.
export function scored(rows, rep, id, arm) {
  return rows.findLast(r => r.rep === String(rep) && r.case === id && r.arm === arm && r.outcome !== 'NOT_RUN');
}
```

Create `evals/tiers/run-case.mjs`:

```js
#!/usr/bin/env node
// Run one case on one arm and grade it: one row of results.tsv.
// Usage: node evals/tiers/run-case.mjs CASE_ID ARM [--rep N] [--stage NAME]
//        node evals/tiers/run-case.mjs CASE_ID ARM [--rep N] --exclude REASON
// --exclude runs nothing: it records the cell as EXCLUDED, for a case whose
// run cannot start for a harness reason.
// Exit: 0 scored or excluded; 1 NOT_RUN; 2 usage.
import { rmSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { parseArgs } from 'node:util';
import { buildCase, buildReview, findCase } from './build-case.mjs';
import { gradeImpl } from './grade-case.mjs';
import { agent, invoke } from './lib/claude.mjs';
import { RESULTS, RESULT_COLUMNS, appendTsv, armDir } from './lib/results.mjs';

const IMPL = { tools: ['Bash', 'Edit', 'Write', 'Read', 'Grep', 'Glob'], seconds: 1800 };
const REVIEW = { tools: ['Read', 'Grep', 'Glob'], seconds: 1200 };

// runCell { rep, stage, c, arm } — C is a manifest row (it has a pool) or a
// review case. A rate limit or a harness error is NOT_RUN and its detail
// starts with the kind, so the grid can tell a limit from an error. A harness
// exception is such an error: it must cost the grid one row, not the stage.
export async function runCell({ rep, stage, c, arm }) {
  const review = !c.pool;
  const row = { rep, stage, case: c.id, pool: c.pool ?? 'review', row: c.row ?? '', arm, model: '', cost: '0.0000', seconds: 0, turns: 0 };
  try {
    const dir = armDir(rep, c.id, arm);
    rmSync(dir, { recursive: true, force: true });
    const built = review ? buildReview(c, dir) : buildCase(c, dir);
    const inv = await invoke({ ...agent(arm), prompt: built.prompt, cwd: built.info.work, ...(review ? REVIEW : IMPL), dir });
    Object.assign(row, { model: inv.model, cost: inv.cost.toFixed(4), seconds: inv.seconds, turns: inv.turns });
    if (inv.kind === 'limit' || inv.kind === 'error') return { ...row, outcome: 'NOT_RUN', detail: `${inv.kind}: ${inv.text.slice(0, 200)}` };
    if (!review) return { ...row, ...(await gradeImpl(built.info, inv)) };
    if (inv.kind !== 'ok') return { ...row, outcome: 'BLOCKED', detail: `cut=${inv.kind}` };
    writeFileSync(join(dir, 'review.md'), inv.text);
    return { ...row, outcome: 'REVIEWED', detail: '' };
  } catch (error) {
    return { ...row, outcome: 'NOT_RUN', detail: `error: ${error.message.slice(0, 200)}` };
  }
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const { values, positionals } = parseArgs({ allowPositionals: true, options: { rep: { type: 'string', default: '1' }, stage: { type: 'string', default: 'manual' }, exclude: { type: 'string' } } });
  const [id, arm] = positionals;
  const c = id && arm ? findCase(id) : null;
  if (!c) { console.error('usage: run-case.mjs CASE_ID ARM [--rep N] [--stage NAME | --exclude REASON]'); process.exit(2); }
  const row = values.exclude === undefined
    ? await runCell({ rep: values.rep, stage: values.stage, c, arm })
    : { rep: values.rep, stage: 'manual', case: c.id, pool: c.pool ?? 'review', row: c.row ?? '', arm, outcome: 'EXCLUDED', model: '', cost: '0.0000', seconds: 0, turns: 0, detail: values.exclude };
  appendTsv(RESULTS, RESULT_COLUMNS, row);
  console.log(RESULT_COLUMNS.map(k => row[k] ?? '').join('\t'));
  process.exit(row.outcome === 'NOT_RUN' ? 1 : 0);
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `timeout 300 node --test evals/tiers/tests/run.test.mjs`
Expected: PASS — `pass 9`, `fail 0`

- [ ] **Step 5: Commit**

```bash
git add evals/tiers/lib/results.mjs evals/tiers/run-case.mjs evals/tiers/tests/run.test.mjs
git commit -m "feat(evals): run one cell and record it"
```

### Task 10: Review grader

**Files:**
- Create: `evals/tiers/grade-review.mjs`
- Test: `evals/tiers/tests/grade-review.test.mjs`

**Interfaces:**
- Consumes: `invoke` — Contracts, `lib/claude.mjs`; `GRADES`, `GRADE_COLUMNS`, `RESULTS`, `RESULT_COLUMNS`, `appendTsv`, `armDir` — `lib/results.mjs`; the rubric format under Files.
- Produces: `defects`, `graderPrompt`, `readGrades`, `gradeReview` — Contracts, Scripts.

**Items:** 1
**Implementer:** dr-superpowers:impl-sonnet-high
**Evaluation:** files 1 - spec 0 - coupling 2 - risk 0 = 3

- [ ] **Step 1: Write the failing test**

Create `evals/tiers/tests/grade-review.test.mjs`:

```js
import assert from 'node:assert/strict';
import { mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { after, test } from 'node:test';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { fixture, modes } from './fixture.mjs';

const fx = fixture();
after(() => rmSync(fx.top, { recursive: true, force: true }));
const { defects, gradeReview, graderPrompt, readGrades } = await import('../grade-review.mjs');
const { GRADES, RESULTS, armDir, readTsv } = await import('../lib/results.mjs');

const REVIEW = 'The refusal search is unanchored,\n  so any line matches. Also a typo.';
const grader = { model: 'opus', effort: 'low' };
const reply = defectList => writeFileSync(join(fx.stub, 'grade.json'), JSON.stringify({ defects: defectList }));
const lastCall = () => JSON.parse(readFileSync(join(fx.stub, 'calls.log'), 'utf8').trim().split('\n').at(-1));

function reviewed(rep, arm) {
  mkdirSync(armDir(rep, 'r-code-fixture', arm), { recursive: true });
  writeFileSync(join(armDir(rep, 'r-code-fixture', arm), 'review.md'), REVIEW);
}

test('a rubric declares its defects and the grader sees the rubric and the review', () => {
  assert.deepEqual(defects('# R\n\n## D1: a\n\n## D2: b\n\ntext ## D9: not a heading\n## D3: c\n'), ['D1', 'D2', 'D3']);
  assert.match(graderPrompt('RUBRIC TEXT', 'REVIEW TEXT'), /one JSON object and nothing else[\s\S]*<rubric>\nRUBRIC TEXT\n<\/rubric>\n\n<review>\nREVIEW TEXT\n<\/review>/);
});

test('readGrades counts a defect only when the quote is in the review', () => {
  const text = 'Here: {"defects": [{"id": "D1", "found": true, "severity": "Critical", "quote": "The refusal search is unanchored, so any line matches."}, {"id": "D2", "found": true, "severity": "Minor", "quote": "The stub never emits JSON at all."}]}';
  assert.deepEqual(readGrades(['D1', 'D2', 'D3'], REVIEW, text), [
    { defect: 'D1', found: '1', severity: 'Critical', quote: 'The refusal search is unanchored, so any line matches.' },
    { defect: 'D2', found: '0', severity: '', quote: '' },
    { defect: 'D3', found: '0', severity: '', quote: '' },
  ]);
  assert.equal(readGrades(['D1'], REVIEW, 'no json here'), null);
  assert.equal(readGrades(['D1'], REVIEW, '{"other": 1}'), null);
  assert.equal(readGrades(['D1'], REVIEW, '{"defects": [{"id": "D1", "found": true, "severity": "Minor", "quote": "Also"}]}')[0].found, '0');
});

test('gradeReview appends one grade per defect and returns the grading row', async () => {
  reviewed(1, 'judge-opus@high');
  reply([{ id: 'D1', found: true, severity: 'Important', quote: 'The refusal search is unanchored' }]);
  modes(fx.stub, 'grade');
  const row = await gradeReview({ rep: '1', id: 'r-code-fixture', arm: 'judge-opus@high', pass: '1', grader });
  assert.deepEqual([row.stage, row.case, row.arm, row.outcome, row.detail, row.cost], ['grade', 'r-code-fixture', 'grade1:judge-opus@high', 'GRADED', 'found=1/2', '0.5000']);
  assert.deepEqual(readTsv(GRADES).map(g => [g.rep, g.case, g.arm, g.pass, g.defect, g.found, g.severity].join(' ')), [
    '1 r-code-fixture judge-opus@high 1 D1 1 Important', '1 r-code-fixture judge-opus@high 1 D2 0 ',
  ]);
  const call = lastCall();
  assert.deepEqual(call.args.slice(0, 5), ['-p', '--model', 'opus', '--effort', 'low']);
  assert.equal(call.args.includes('--append-system-prompt-file'), false);
  assert.match(call.prompt, /<rubric>\n# Rubric[\s\S]*<review>\nThe refusal search/);
});

test('a grader reply without JSON, or a rate limit, is NOT_RUN and writes no grade', async () => {
  reviewed(2, 'judge-opus@high');
  modes(fx.stub, 'blocked');
  const bad = await gradeReview({ rep: '2', id: 'r-code-fixture', arm: 'judge-opus@high', pass: '1', grader });
  assert.deepEqual([bad.outcome, bad.detail], ['NOT_RUN', 'error: the grader reply holds no JSON object']);
  modes(fx.stub, 'limit');
  const limited = await gradeReview({ rep: '2', id: 'r-code-fixture', arm: 'judge-opus@high', pass: '1', grader });
  assert.equal(limited.outcome, 'NOT_RUN');
  assert.match(limited.detail, /^limit: /);
  assert.equal(readTsv(GRADES).filter(g => g.rep === '2').length, 0);
});

test('a cell that produced no review misses every defect without a grader call', async () => {
  const calls = readFileSync(join(fx.stub, 'calls.log'), 'utf8');
  const row = await gradeReview({ rep: '5', id: 'r-code-fixture', arm: 'judge-opus@high', pass: '1', grader });
  assert.deepEqual([row.outcome, row.detail, row.cost], ['GRADED', 'found=0/2', '0.0000']);
  assert.deepEqual(readTsv(GRADES).filter(g => g.rep === '5').map(g => [g.defect, g.found]), [['D1', '0'], ['D2', '0']]);
  assert.equal(readFileSync(join(fx.stub, 'calls.log'), 'utf8'), calls);
  const missing = await gradeReview({ rep: '5', id: 'r-no-rubric', arm: 'judge-opus@high', pass: '1', grader });
  assert.equal(missing.outcome, 'NOT_RUN');
  assert.match(missing.detail, /^error: ENOENT/);
});

test('the command line grades one review and appends the grading row', () => {
  reviewed(3, 'judge-sonnet-high');
  reply([{ id: 'D2', found: true, severity: 'Minor', quote: 'so any line matches.' }]);
  modes(fx.stub, 'grade');
  const cli = (...args) => spawnSync(process.execPath, [fileURLToPath(new URL('../grade-review.mjs', import.meta.url)), ...args], { encoding: 'utf8' });
  const ok = cli('r-code-fixture', 'judge-sonnet-high', '--rep', '3', '--pass', '2');
  assert.equal(ok.status, 0, ok.stderr);
  assert.equal(cli('r-code-fixture').status, 2);
  assert.deepEqual(readTsv(RESULTS).filter(r => r.rep === '3').map(r => [r.arm, r.outcome, r.detail]), [['grade2:judge-sonnet-high', 'GRADED', 'found=1/2']]);
  assert.deepEqual(readTsv(GRADES).filter(g => g.rep === '3').map(g => [g.pass, g.defect, g.found]), [['2', 'D1', '0'], ['2', 'D2', '1']]);
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `timeout 300 node --test evals/tiers/tests/grade-review.test.mjs`
Expected: FAIL — `ERR_MODULE_NOT_FOUND` naming `grade-review.mjs`

- [ ] **Step 3: Write the implementation**

Create `evals/tiers/grade-review.mjs`:

```js
#!/usr/bin/env node
// Grade one review against its case rubric with a model call.
// Usage: node evals/tiers/grade-review.mjs CASE_ID ARM [--rep N] [--pass P]
// Exit: 0 graded; 1 the grader produced nothing usable; 2 usage.
import { existsSync, readFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { parseArgs } from 'node:util';
import { DATA } from './lib/sh.mjs';
import { invoke } from './lib/claude.mjs';
import { GRADES, GRADE_COLUMNS, RESULTS, RESULT_COLUMNS, appendTsv, armDir } from './lib/results.mjs';

const SECONDS = 600;
const squash = s => s.replace(/\s+/g, ' ').trim();

// defects RUBRIC — the defect ids a rubric declares, one `## D<n>:` heading each.
export function defects(rubric) {
  return [...rubric.matchAll(/^## (D\d+):/gm)].map(m => m[1]);
}

export function graderPrompt(rubric, review) {
  return `You are grading a review against a list of known defects. Use only the two documents below.

For each defect in the rubric, decide whether the review reports it. A defect counts as found when the review names the same faulty behaviour or mechanism, even in other words or at another line. A finding about the same file that describes a different problem does not count. When it is found, quote one sentence of the review, verbatim, that reports it, and give the severity the review assigned it: Critical, Important or Minor.

Reply with one JSON object and nothing else:
{"defects": [{"id": "D1", "found": true, "severity": "Important", "quote": "..."}, {"id": "D2", "found": false, "severity": null, "quote": null}]}

<rubric>
${rubric}
</rubric>

<review>
${review}
</review>
`;
}

// readGrades IDS REVIEW REPLY — one grade per rubric defect, or null when the
// reply holds no JSON object. A defect is found only when the grader's quote
// is really in the review: a quote it invented is a miss.
export function readGrades(ids, review, reply) {
  let parsed;
  try { parsed = JSON.parse(reply.slice(reply.indexOf('{'), reply.lastIndexOf('}') + 1)); } catch { return null; }
  if (!Array.isArray(parsed.defects)) return null;
  const text = squash(review);
  return ids.map(id => {
    const g = parsed.defects.find(d => d.id === id) ?? {};
    const quote = typeof g.quote === 'string' ? squash(g.quote) : '';
    const found = g.found === true && quote.length >= 12 && text.includes(quote);
    return { defect: id, found: found ? '1' : '0', severity: found ? String(g.severity ?? '') : '', quote: found ? quote : '' };
  });
}

// gradeReview { rep, id, arm, pass, grader } — grades DIR/review.md, appends
// one row per defect to review-grades.tsv, and returns the results row. A cell
// with no review.md was cut short before it reported anything: it misses
// every defect, with no grader call, so the arm still has a full set of grades.
export async function gradeReview({ rep, id, arm, pass, grader }) {
  const row = { rep, stage: 'grade', case: id, pool: 'review', row: '', arm: `grade${pass}:${arm}`, model: '', cost: '0.0000', seconds: 0, turns: 0 };
  try {
    const dir = armDir(rep, id, arm);
    const ids = defects(readFileSync(resolve(DATA, 'cases/reviews', `${id}.md`), 'utf8'));
    let grades;
    if (existsSync(join(dir, 'review.md'))) {
      const review = readFileSync(join(dir, 'review.md'), 'utf8');
      const rubric = readFileSync(resolve(DATA, 'cases/reviews', `${id}.md`), 'utf8');
      const inv = await invoke({ ...grader, body: null, prompt: graderPrompt(rubric, review), cwd: dir, tools: [], seconds: SECONDS, dir: join(dir, `grade${pass}`) });
      Object.assign(row, { model: inv.model, cost: inv.cost.toFixed(4), seconds: inv.seconds, turns: inv.turns });
      grades = inv.kind === 'ok' ? readGrades(ids, review, inv.text) : null;
      if (grades === null) return { ...row, outcome: 'NOT_RUN', detail: inv.kind === 'ok' ? 'error: the grader reply holds no JSON object' : `${inv.kind}: ${inv.text.slice(0, 200)}` };
    } else {
      grades = ids.map(defect => ({ defect, found: '0', severity: '', quote: '' }));
    }
    for (const g of grades) appendTsv(GRADES, GRADE_COLUMNS, { rep, case: id, arm, pass, ...g });
    return { ...row, outcome: 'GRADED', detail: `found=${grades.filter(g => g.found === '1').length}/${grades.length}` };
  } catch (error) {
    return { ...row, outcome: 'NOT_RUN', detail: `error: ${error.message.slice(0, 200)}` };
  }
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const { values, positionals } = parseArgs({ allowPositionals: true, options: { rep: { type: 'string', default: '1' }, pass: { type: 'string', default: '1' } } });
  const [id, arm] = positionals;
  if (!id || !arm) { console.error('usage: grade-review.mjs CASE_ID ARM [--rep N] [--pass P]'); process.exit(2); }
  const { grader } = JSON.parse(readFileSync(resolve(DATA, 'arms.json'), 'utf8'));
  const row = await gradeReview({ rep: values.rep, id, arm, pass: values.pass, grader });
  appendTsv(RESULTS, RESULT_COLUMNS, row);
  console.log(RESULT_COLUMNS.map(k => row[k] ?? '').join('\t'));
  process.exit(row.outcome === 'GRADED' ? 0 : 1);
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `timeout 300 node --test evals/tiers/tests/grade-review.test.mjs`
Expected: PASS — `pass 6`, `fail 0`

- [ ] **Step 5: Commit**

```bash
git add evals/tiers/grade-review.mjs evals/tiers/tests/grade-review.test.mjs
git commit -m "feat(evals): grade a review against its rubric"
```

### Task 11: Decision rules

**Files:**
- Create: `evals/tiers/lib/decide.mjs`
- Test: `evals/tiers/tests/decide.test.mjs`

**Interfaces:**
- Consumes: nothing: pure functions.
- Produces: `MIN_STRIPPED`, `decideRow`, `decideReview`, `graderDisagreements` — Contracts, `lib/decide.mjs`.

**Items:** 1
**Implementer:** dr-superpowers:impl-sonnet-high
**Evaluation:** files 1 - spec 0 - coupling 2 - risk 0 = 3

- [ ] **Step 1: Write the failing test**

Create `evals/tiers/tests/decide.test.mjs`:

```js
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { decideReview, decideRow, graderDisagreements } from '../lib/decide.mjs';

const cases = n => Array.from({ length: n }, (_, i) => ({ id: `c${i}`, pool: i < 4 ? 'stripped' : 'written' }));
const table = spec => (id, arm) => spec[arm]?.[id] ?? spec[arm]?.all;
const pass = cost => ({ outcome: 'PASS', cost }), fail = cost => ({ outcome: 'FAIL', cost });

test('decideRow moves to the cheapest arm with no regression', () => {
  const d = decideRow(['cur', 'mid', 'low'], cases(8), table({ cur: { all: pass(4) }, mid: { all: pass(2) }, low: { all: pass(1) } }));
  assert.equal(d.verdict, 'MOVE to low');
  assert.match(d.notes[0], /^8 paired trials \(4 stripped\); zero regressions is consistent with a true regression rate up to 38%$/);
  assert.deepEqual(d.stats.map(s => [s.arm, s.pass, s.of, s.perPass, s.regressions.length]), [['cur', 8, 8, 4, 0], ['mid', 8, 8, 2, 0], ['low', 8, 8, 1, 0]]);
  const skip = decideRow(['cur', 'mid', 'low'], cases(8), table({ cur: { all: pass(4) }, mid: { all: pass(2) }, low: { all: pass(1), c5: fail(1) } }));
  assert.equal(skip.verdict, 'MOVE to mid');
  assert.equal(skip.notes[1], 'low regresses on c5');
});

test('decideRow holds a row on regressions and flags thin evidence', () => {
  assert.equal(decideRow(['cur', 'low'], cases(8), table({ cur: { all: pass(4) }, low: { all: pass(1), c0: fail(1) } })).verdict, 'INCONCLUSIVE');
  assert.equal(decideRow(['cur', 'low'], cases(8), table({ cur: { all: pass(4) }, low: { all: pass(1), c0: fail(1), c1: fail(1) } })).verdict, 'UNCHANGED');
  assert.equal(decideRow(['cur', 'low'], cases(8), table({ cur: { all: pass(1) }, low: { all: pass(4) } })).verdict, 'UNCHANGED');
  assert.equal(decideRow(['cur', 'low'], cases(3), table({ cur: { all: pass(4) }, low: { all: pass(1) } })).verdict, 'MOVE to low - owner ruling, only 3 stripped cases');
  assert.equal(decideRow(['cur', 'low'], cases(3), table({ cur: { all: pass(4) }, low: { all: pass(1) } }), false).verdict, 'MOVE to low');
  assert.equal(decideRow(['cur', 'low'], cases(8), table({ cur: { all: pass(4) } })).verdict, 'INCOMPLETE');
  assert.equal(decideRow(['cur', 'low'], [], table({})).verdict, 'NOT MEASURED');
  const flagged = decideRow(['cur', 'low'], cases(8), table({ cur: { all: pass(4), c0: fail(4), c1: fail(4) }, low: { all: pass(1) } }));
  assert.equal(flagged.notes.at(-1), 'cur does not pass 2 cases: second repetition with the next agent up');
});

const grade = (arm, defect, found, severity = 'Important', pass = '1') => ({ case: 'r', arm, pass, defect, found, severity });

test('decideReview needs equal recall and no missed Critical', () => {
  const cur = [grade('cur', 'D1', '1', 'Critical'), grade('cur', 'D2', '1'), grade('cur', 'D3', '0')];
  const verdict = rows => decideReview(['cur', 'low'], [...cur, ...rows])[1];
  assert.deepEqual(decideReview(['cur', 'low'], cur)[0], { arm: 'cur', found: 2, of: 3, underGraded: 0, verdict: 'current', missedCritical: [] });
  assert.equal(verdict([grade('low', 'D1', '1', 'Minor'), grade('low', 'D2', '1', 'null'), grade('low', 'D3', '0', 'Minor')]).underGraded, 2);
  assert.equal(verdict([grade('low', 'D1', '1'), grade('low', 'D2', '1'), grade('low', 'D3', '0')]).verdict, 'SUPPORTED');
  assert.equal(verdict([grade('low', 'D1', '1'), grade('low', 'D2', '0'), grade('low', 'D3', '0')]).verdict, 'NOT SUPPORTED');
  const missed = verdict([grade('low', 'D1', '0'), grade('low', 'D2', '1'), grade('low', 'D3', '1')]);
  assert.deepEqual([missed.verdict, missed.missedCritical], ['NOT SUPPORTED', ['r/D1']]);
  assert.equal(verdict([grade('low', 'D1', '1')]).verdict, 'INCOMPLETE');
});

test('graderDisagreements counts second-pass changes', () => {
  const rows = [grade('a', 'D1', '1'), grade('a', 'D2', '0'), grade('a', 'D1', '1', 'Important', '2'), grade('a', 'D2', '1', 'Important', '2')];
  assert.deepEqual(graderDisagreements(rows), { repeated: 2, disagreements: 1 });
  assert.deepEqual(graderDisagreements(rows, 3), { repeated: 0, disagreements: 0 });
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `timeout 300 node --test evals/tiers/tests/decide.test.mjs`
Expected: FAIL — `ERR_MODULE_NOT_FOUND` naming `lib/decide.mjs`

- [ ] **Step 3: Write the implementation**

Create `evals/tiers/lib/decide.mjs`:

```js
// The decision rules of spec §4, as pure functions over scored results.

export const MIN_STRIPPED = 4;

// decideRow ARMS CASES CELL [THIN] — ARMS lists the current agent first, CASES
// are the row's manifest cases from both pools, and CELL(id, arm) returns
// { outcome, cost } or undefined while the cell is unscored. A regression is
// a case the current agent passes and a candidate does not. THIN is false for
// row 1, which cannot hold a stripped case: a stripped task totals at least 2.
export function decideRow(arms, cases, cell, thin = true) {
  const [current, ...candidates] = arms;
  if (cases.length === 0) return { verdict: 'NOT MEASURED', notes: ['no case on this row'], stats: [] };
  const missing = arms.flatMap(arm => cases.filter(c => !cell(c.id, arm)).map(c => `${c.id}/${arm}`));
  if (missing.length > 0) return { verdict: 'INCOMPLETE', notes: [`${missing.length} cells are not scored`], stats: [] };
  const stat = arm => {
    const runs = cases.map(c => cell(c.id, arm));
    const pass = runs.filter(r => r.outcome === 'PASS').length;
    const cost = runs.reduce((sum, r) => sum + r.cost, 0);
    const regressions = arm === current ? [] : cases.filter(c => cell(c.id, current).outcome === 'PASS' && cell(c.id, arm).outcome !== 'PASS').map(c => c.id);
    return { arm, pass, of: runs.length, perPass: pass > 0 ? cost / pass : Infinity, regressions };
  };
  const stats = arms.map(stat);
  const [cur, ...cands] = stats;
  const eligible = cands.filter(s => s.regressions.length === 0 && s.perPass < cur.perPass).sort((a, b) => a.perPass - b.perPass);
  const stripped = cases.filter(c => c.pool === 'stripped').length;
  const notes = [`${cases.length} paired trials (${stripped} stripped); zero regressions is consistent with a true regression rate up to ${Math.round(Math.min(1, 3 / cases.length) * 100)}%`];
  for (const s of cands.filter(s => s.regressions.length > 0)) notes.push(`${s.arm} regresses on ${s.regressions.join(', ')}`);
  let verdict = 'UNCHANGED';
  if (eligible.length > 0) {
    verdict = `MOVE to ${eligible[0].arm}`;
    if (thin && stripped < MIN_STRIPPED) verdict += ` - owner ruling, only ${stripped} stripped cases`;
  } else if (cands.some(s => s.regressions.length === 1)) {
    verdict = 'INCONCLUSIVE';
  }
  if (cur.of - cur.pass >= 2) notes.push(`${current} does not pass ${cur.of - cur.pass} cases: second repetition with the next agent up`);
  return { verdict, notes, stats };
}

// decideReview ARMS GRADES — ARMS lists the current judge first; GRADES are
// the pass-1 rows of review-grades.tsv. A cheaper judge is supported when its
// pooled recall is at least the current judge's and it misses no defect the
// current judge found and graded Critical. Every rubric defect was fixed by a
// later commit, so one found but graded below Important is under-graded.
export function decideReview(arms, grades) {
  const [current, ...candidates] = arms;
  const key = g => `${g.case}\t${g.defect}`;
  const of = arm => new Map(grades.filter(g => g.arm === arm).map(g => [key(g), g]));
  const cur = of(current);
  const recall = map => {
    const found = [...map.values()].filter(g => g.found === '1');
    return { found: found.length, of: map.size, underGraded: found.filter(g => g.severity !== 'Critical' && g.severity !== 'Important').length };
  };
  return [{ arm: current, ...recall(cur), verdict: 'current', missedCritical: [] }, ...candidates.map(arm => {
    const mine = of(arm);
    const r = recall(mine);
    if (cur.size === 0 || mine.size !== cur.size) return { arm, ...r, verdict: 'INCOMPLETE', missedCritical: [] };
    const missedCritical = [...cur.values()].filter(g => g.found === '1' && g.severity === 'Critical' && mine.get(key(g))?.found !== '1').map(g => `${g.case}/${g.defect}`);
    const supported = r.found >= recall(cur).found && missedCritical.length === 0;
    return { arm, ...r, verdict: supported ? 'SUPPORTED' : 'NOT SUPPORTED', missedCritical };
  })];
}

// graderDisagreements GRADES PASS — how many defects the repeat grading, pass
// PASS + 1, judged differently from pass PASS. More than one means the grader
// is not usable.
export function graderDisagreements(grades, pass = 1) {
  const first = new Map(grades.filter(g => g.pass === String(pass)).map(g => [`${g.case}\t${g.arm}\t${g.defect}`, g.found]));
  const second = grades.filter(g => g.pass === String(pass + 1));
  return { repeated: second.length, disagreements: second.filter(g => first.get(`${g.case}\t${g.arm}\t${g.defect}`) !== g.found).length };
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `timeout 300 node --test evals/tiers/tests/decide.test.mjs`
Expected: PASS — `pass 4`, `fail 0`

- [ ] **Step 5: Commit**

```bash
git add evals/tiers/lib/decide.mjs evals/tiers/tests/decide.test.mjs
git commit -m "feat(evals): add the decision rules"
```

### Task 12: Grid runner and report

**Files:**
- Create: `evals/tiers/run-grid.mjs`
- Create: `evals/tiers/report.mjs`
- Test: `evals/tiers/tests/grid.test.mjs`

**Interfaces:**
- Consumes: `reviewCases`, `runCell`, `gradeReview`, `readManifest`, `decideRow`, `decideReview`, `graderDisagreements`, `lib/results.mjs`, `build-manifest.mjs`, `arms.json` — Contracts.
- Produces: `run-grid.mjs` and `report.mjs` — Contracts, Scripts. Tasks 17 to 21 run them.

**Items:** 1
**Implementer:** dr-superpowers:impl-sonnet-high
**Evaluation:** files 1 - spec 0 - coupling 2 - risk 0 = 3

- [ ] **Step 1: Write the failing test**

Create `evals/tiers/tests/grid.test.mjs`:

```js
import assert from 'node:assert/strict';
import { readFileSync, rmSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { after, test } from 'node:test';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { fixture, modes } from './fixture.mjs';

const fx = fixture();
after(() => rmSync(fx.top, { recursive: true, force: true }));
const script = name => fileURLToPath(new URL(`../${name}`, import.meta.url));
const node = (name, args = [], env = {}) => spawnSync(process.execPath, [script(name), ...args], { cwd: fx.repo, encoding: 'utf8', env: { ...process.env, TIER_EVAL_JOBS: '1', ...env } });
const rows = file => readFileSync(join(fx.data, 'results', file), 'utf8').trim().split('\n').slice(1).map(l => l.split('\t'));
assert.equal(node('build-manifest.mjs').status, 0);

test('the grid stops at a rate limit and resumes at the first unscored cell', () => {
  modes(fx.stub, 'pass', 'limit');
  const stopped = node('run-grid.mjs', ['--stage', 'written']);
  assert.equal(stopped.status, 3, stopped.stderr);
  assert.match(stopped.stdout, /run-grid stage=written rep=1 ran=2 remaining=1 spent=0\.50 stop=limit/);
  assert.deepEqual(rows('results.tsv').map(r => [r[2], r[5], r[6]]), [['w-fixture-t1', 'impl-sonnet-low', 'PASS'], ['w-fixture-t1', 'impl-haiku', 'NOT_RUN']]);
  modes(fx.stub, 'pass');
  const resumed = node('run-grid.mjs', ['--stage', 'written']);
  assert.equal(resumed.status, 0, resumed.stderr);
  assert.match(resumed.stdout, /ran=1 remaining=0 spent=1\.00 stop=-/);
  assert.equal(node('run-grid.mjs', ['--stage', 'written']).stdout.includes('ran=0 remaining=0'), true);
});

test('the grid stops at the spend cap before starting a cell', () => {
  modes(fx.stub, 'pass');
  const capped = node('run-grid.mjs', ['--stage', 'stripped'], { TIER_EVAL_CAP_USD: '1' });
  assert.equal(capped.status, 3);
  assert.match(capped.stdout, /ran=0 remaining=2 spent=1\.00 stop=cap/);
});

test('the grid stops starting cells once its minutes are spent', () => {
  modes(fx.stub, 'pass');
  const timed = node('run-grid.mjs', ['--stage', 'stripped', '--minutes', '0']);
  assert.equal(timed.status, 3);
  assert.match(timed.stdout, /ran=0 remaining=2 spent=1\.00 stop=time/);
  assert.equal(node('run-grid.mjs', ['--stage', 'stripped', '--minutes', 'soon']).status, 2);
});

test('the grid refuses to run when the plugin drifted from the start commit', () => {
  writeFileSync(join(fx.repo, 'plugins/dr-superpowers/marker.txt'), 'changed\n');
  const drifted = node('run-grid.mjs', ['--stage', 'written']);
  writeFileSync(join(fx.repo, 'plugins/dr-superpowers/marker.txt'), 'fixture\n');
  assert.equal(drifted.status, 2);
  assert.match(drifted.stderr, /differs from the manifest's start commit/);
  assert.equal(node('run-grid.mjs', ['--stage', 'nope']).status, 2);
});

test('the review stage grades every review, repeats the grading and scores a cut-short review as all missed', () => {
  writeFileSync(join(fx.stub, 'review.md'), '### Issues\nThe script greets in lower case only.\n');
  writeFileSync(join(fx.stub, 'grade.json'), JSON.stringify({ defects: [
    { id: 'D1', found: true, severity: 'Important', quote: 'The script greets in lower case only.' },
    { id: 'D2', found: true, severity: 'Minor', quote: 'A sentence the review never wrote.' },
  ] }));
  modes(fx.stub, 'review', 'budget', 'grade');
  const done = node('run-grid.mjs', ['--stage', 'review']);
  assert.equal(done.status, 0, done.stderr);
  assert.match(done.stdout, /ran=5 remaining=0/);
  assert.deepEqual(rows('results.tsv').filter(r => r[4] === '' && r[1] !== 'grade').map(r => [r[5], r[6]]), [['judge-opus@high', 'REVIEWED'], ['judge-sonnet-high', 'BLOCKED']]);
  assert.deepEqual(rows('review-grades.tsv').map(r => r.slice(1, 6).join(' ')), [
    'r-code-fixture judge-opus@high 1 D1 1', 'r-code-fixture judge-opus@high 1 D2 0',
    'r-code-fixture judge-sonnet-high 1 D1 0', 'r-code-fixture judge-sonnet-high 1 D2 0',
    'r-code-fixture judge-opus@high 2 D1 1', 'r-code-fixture judge-opus@high 2 D2 0',
  ]);
  const grading = JSON.parse(readFileSync(join(fx.stub, 'calls.log'), 'utf8').trim().split('\n').at(-1));
  assert.deepEqual([grading.args[grading.args.indexOf('--tools') + 1], grading.args.includes('--append-system-prompt-file')], ['', false]);
  assert.match(grading.prompt, /<rubric>\n# Rubric[\s\S]*<review>\n### Issues/);
});

test('a later grading pass grades every review again beside the earlier grades', () => {
  modes(fx.stub, 'grade');
  const again = node('run-grid.mjs', ['--stage', 'review', '--pass', '3']);
  assert.equal(again.status, 0, again.stderr);
  assert.match(again.stdout, /ran=3 remaining=0/);
  assert.deepEqual(rows('review-grades.tsv').slice(6).map(r => r.slice(2, 6).join(' ')), [
    'judge-opus@high 3 D1 1', 'judge-opus@high 3 D2 0', 'judge-sonnet-high 3 D1 0', 'judge-sonnet-high 3 D2 0', 'judge-opus@high 4 D1 1', 'judge-opus@high 4 D2 0',
  ]);
  assert.match(node('report.mjs', ['--pass', '3']).stdout, /Grader consistency: 0 disagreements on 2 repeated gradings - usable\./);
  assert.equal(node('run-grid.mjs', ['--stage', 'review', '--pass', '0']).status, 2);
});

test('the smoke stage runs one cell per kind and one grading', () => {
  modes(fx.stub, 'pass', 'review', 'review', 'grade');
  const smoke = node('run-grid.mjs', ['--stage', 'smoke', '--rep', '2']);
  assert.equal(smoke.status, 0, smoke.stderr);
  assert.deepEqual(rows('results.tsv').filter(r => r[0] === '2').map(r => [r[2], r[5], r[6]]), [
    ['w-fixture-t1', 'impl-haiku', 'PASS'],
    ['r-code-fixture', 'judge-sonnet-high', 'REVIEWED'],
    ['r-code-fixture', 'judge-opus@medium', 'REVIEWED'],
    ['r-code-fixture', 'grade1:judge-opus@medium', 'GRADED'],
  ]);
});

test('the report states a verdict per row and per review seat', () => {
  const report = node('report.mjs').stdout;
  assert.match(report, /### Row 1: UNCHANGED\n\n\| Arm \| PASS \| Of \| Cost per PASS \| Regressions \|\n\|---\|---\|---\|---\|---\|\n\| `impl-sonnet-low` \| 1 \| 1 \| \$0\.50 \| 0 \|\n\| `impl-haiku` \| 1 \| 1 \| \$0\.50 \| 0 \|/);
  assert.match(report, /- 1 paired trials \(0 stripped\); zero regressions is consistent with a true regression rate up to 100%/);
  assert.match(report, /### Row 5: INCOMPLETE\n\n- 2 cells are not scored/);
  assert.match(report, /\| `judge-opus@high` \| 1 \| 2 \| 0 \| current \| - \|\n\| `judge-sonnet-high` \| 0 \| 2 \| 0 \| NOT SUPPORTED \| - \|/);
  assert.match(report, /Grader consistency: 0 disagreements on 2 repeated gradings - usable\./);
  assert.match(report, /Notional spend: \$[0-9]+\.[0-9]{2} over [0-9]+ runs\./);
});

test('an excluded case leaves the grid and the report', () => {
  const excl = node('run-case.mjs', ['s-fixture-t2', 'impl-opus-medium', '--exclude', 'its snapshot cannot be built']);
  assert.equal(excl.status, 0, excl.stderr);
  assert.match(node('run-grid.mjs', ['--stage', 'stripped']).stdout, /ran=0 remaining=0/);
  assert.match(node('report.mjs').stdout, /### Row 5: NOT MEASURED\n\n- no case on this row\n- excluded s-fixture-t2: its snapshot cannot be built/);
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `timeout 300 node --test evals/tiers/tests/grid.test.mjs`
Expected: FAIL — all nine tests fail: `run-grid.mjs` and `report.mjs` do not exist, so their exit status is 1

- [ ] **Step 3: Write the implementation**

Create `evals/tiers/run-grid.mjs`:

```js
#!/usr/bin/env node
// Run every cell of one stage that has no scored result yet, two at a time.
// Usage: node evals/tiers/run-grid.mjs --stage smoke|written|stripped|review [--rep N] [--minutes M] [--pass P]
// --minutes stops starting cells after M minutes, so a long stage can run in
// slices; cells already running finish. --pass numbers the grading passes P
// and P + 1 (default 1 and 2), so every review can be graded again after a
// grader fix without touching the earlier grades.
// Exit: 0 the stage is complete; 1 cells remain after harness errors; 2 usage,
// or the plugin differs from the manifest's start commit; 3 stopped at the
// spend cap, at a rate limit or at --minutes.
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { parseArgs } from 'node:util';
import { reviewCases } from './build-case.mjs';
import { gradeReview } from './grade-review.mjs';
import { runCell } from './run-case.mjs';
import { readManifest } from './lib/cases.mjs';
import { RESULTS, RESULT_COLUMNS, appendTsv, readTsv, scored } from './lib/results.mjs';
import { DATA, sh } from './lib/sh.mjs';

// The two limits of the spec; the tests lower them through the environment.
const JOBS = Number(process.env.TIER_EVAL_JOBS ?? 2);
const CAP_USD = Number(process.env.TIER_EVAL_CAP_USD ?? 250);
const REPEAT_GRADINGS = 6;
const STAGES = ['smoke', 'written', 'stripped', 'review'];

const { values } = parseArgs({ options: { stage: { type: 'string' }, rep: { type: 'string', default: '1' }, minutes: { type: 'string' }, pass: { type: 'string', default: '1' } } });
const { stage, rep } = values;
const deadline = values.minutes === undefined ? Infinity : Date.now() + Number(values.minutes) * 60000;
const pass = Number(values.pass);
if (!STAGES.includes(stage) || Number.isNaN(deadline) || !Number.isInteger(pass) || pass < 1) { console.error(`usage: run-grid.mjs --stage ${STAGES.join('|')} [--rep N] [--minutes M] [--pass P]`); process.exit(2); }
const { start, cases } = readManifest();
if (sh('git', ['diff', '--quiet', start, '--', 'plugins/dr-superpowers']).code !== 0) {
  console.error(`run-grid: plugins/dr-superpowers differs from the manifest's start commit ${start}`);
  process.exit(2);
}
const arms = JSON.parse(readFileSync(resolve(DATA, 'arms.json'), 'utf8'));
const reviews = reviewCases();

function cells() {
  if (stage === 'review') return reviews.flatMap(c => arms.review.map(arm => ({ c, arm })));
  if (stage !== 'smoke') return cases.filter(c => c.pool === stage).flatMap(c => arms.rows[c.row].map(arm => ({ c, arm })));
  const first = row => cases.find(c => c.pool === 'written' && c.row === row);
  return [
    { c: first(1), arm: 'impl-haiku' },
    { c: first(3), arm: 'impl-sonnet-medium' },
    { c: first(5), arm: 'impl-opus-low' },
    { c: reviews[0], arm: 'judge-sonnet-high' },
    { c: reviews[0], arm: 'judge-opus@medium' },
  ].filter(cell => cell.c);
}

// excluded — the cases a person took out of this repetition with
// `run-case.mjs --exclude`: one EXCLUDED row removes the case for every arm.
const excluded = () => new Set(readTsv(RESULTS).filter(r => r.rep === rep && r.outcome === 'EXCLUDED').map(r => r.case));

// gradings — the first pass for every settled review cell of this repetition
// (one only in the smoke stage), then a repeat pass on the first
// REPEAT_GRADINGS reviews. A BLOCKED cell wrote no review; gradeReview grades
// it as missing every defect, so each arm ends with a grade per defect.
function gradings() {
  if (stage !== 'smoke' && stage !== 'review') return [];
  const out = excluded();
  const settled = readTsv(RESULTS).filter(r => r.rep === rep && r.pool === 'review' && !out.has(r.case) && (r.outcome === 'REVIEWED' || r.outcome === 'BLOCKED'))
    .sort((a, b) => a.case.localeCompare(b.case) || a.arm.localeCompare(b.arm));
  const reviewed = settled.filter(r => r.outcome === 'REVIEWED');
  const first = (stage === 'smoke' ? reviewed.slice(0, 1) : settled).map(r => ({ id: r.case, arm: r.arm, pass: String(pass) }));
  const second = stage === 'review' ? reviewed.slice(0, REPEAT_GRADINGS).map(r => ({ id: r.case, arm: r.arm, pass: String(pass + 1) })) : [];
  return [...first, ...second];
}

const spent = () => readTsv(RESULTS).filter(r => r.rep === rep).reduce((sum, r) => sum + Number(r.cost), 0);
let stop = null, ran = 0;

async function drain(queue, work) {
  await Promise.all(Array.from({ length: JOBS }, async () => {
    while (stop === null && queue.length > 0) {
      if (spent() >= CAP_USD) { stop = 'cap'; break; }
      if (Date.now() >= deadline) { stop = 'time'; break; }
      const row = await work(queue.shift());
      appendTsv(RESULTS, RESULT_COLUMNS, row);
      ran += 1;
      console.log(RESULT_COLUMNS.map(k => row[k] ?? '').join('\t'));
      if (row.outcome === 'NOT_RUN' && row.detail.startsWith('limit')) stop = 'limit';
    }
  }));
}

const pendingCells = () => cells().filter(({ c, arm }) => !excluded().has(c.id) && !scored(readTsv(RESULTS), rep, c.id, arm));
const pendingGradings = () => gradings().filter(g => !scored(readTsv(RESULTS), rep, g.id, `grade${g.pass}:${g.arm}`));
await drain(pendingCells(), ({ c, arm }) => runCell({ rep, stage, c, arm }));
await drain(pendingGradings(), g => gradeReview({ rep, ...g, grader: arms.grader }));
const remaining = pendingCells().length + pendingGradings().length;
console.log(`run-grid stage=${stage} rep=${rep} ran=${ran} remaining=${remaining} spent=${spent().toFixed(2)} stop=${stop ?? '-'}`);
process.exit(stop ? 3 : remaining > 0 ? 1 : 0);
```

Create `evals/tiers/report.mjs`:

```js
#!/usr/bin/env node
// Print the per-row decision table and the review-seat table as Markdown.
// Usage: node evals/tiers/report.mjs [--rep N] [--pass P]
// --pass reads the review grades of pass P and its repeat P + 1 (default 1).
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { parseArgs } from 'node:util';
import { readManifest } from './lib/cases.mjs';
import { decideReview, decideRow, graderDisagreements } from './lib/decide.mjs';
import { GRADES, RESULTS, readTsv, scored } from './lib/results.mjs';
import { DATA } from './lib/sh.mjs';

const { values } = parseArgs({ options: { rep: { type: 'string', default: '1' }, pass: { type: 'string', default: '1' } } });
const rep = values.rep;
const pass = Number(values.pass);
const arms = JSON.parse(readFileSync(resolve(DATA, 'arms.json'), 'utf8'));
const { start, cases } = readManifest();
const results = readTsv(RESULTS);
const cell = (id, arm) => {
  const r = scored(results, rep, id, arm);
  return r ? { outcome: r.outcome, cost: Number(r.cost) } : undefined;
};
const money = n => Number.isFinite(n) ? `$${n.toFixed(2)}` : '-';
const excluded = new Map(results.filter(r => r.rep === rep && r.outcome === 'EXCLUDED').map(r => [r.case, r.detail]));
const out = [`# Tier eval - repetition ${rep}`, '', `Start commit: \`${start}\``, '', '## Implementer rows', ''];
for (const [row, rowArms] of Object.entries(arms.rows)) {
  const onRow = cases.filter(c => c.row === Number(row));
  const mine = onRow.filter(c => !excluded.has(c.id));
  const d = decideRow(rowArms, mine, cell, Number(row) >= 2);
  for (const c of onRow.filter(c => excluded.has(c.id))) d.notes.push(`excluded ${c.id}: ${excluded.get(c.id)}`);
  out.push(`### Row ${row}: ${d.verdict}`, '');
  if (d.stats.length > 0) {
    out.push('| Arm | PASS | Of | Cost per PASS | Regressions |', '|---|---|---|---|---|');
    for (const s of d.stats) out.push(`| \`${s.arm}\` | ${s.pass} | ${s.of} | ${money(s.perPass)} | ${s.regressions.length} |`);
    out.push('');
  }
  for (const note of d.notes) out.push(`- ${note}`);
  out.push('');
}
const grades = readTsv(GRADES).filter(g => g.rep === rep && !excluded.has(g.case));
out.push('## Review seats', '', '| Arm | Found | Of | Under-graded | Verdict | Missed Critical |', '|---|---|---|---|---|---|');
for (const s of decideReview(arms.review, grades.filter(g => g.pass === String(pass)))) {
  out.push(`| \`${s.arm}\` | ${s.found} | ${s.of} | ${s.underGraded} | ${s.verdict} | ${s.missedCritical.join(', ') || '-'} |`);
}
for (const [id, why] of excluded) if (!cases.some(c => c.id === id)) out.push('', `Excluded review case ${id}: ${why}`);
const g = graderDisagreements(grades, pass);
out.push('', `Grader consistency: ${g.disagreements} disagreements on ${g.repeated} repeated gradings - ${g.disagreements > 1 ? 'INCONSISTENT: fix the grader prompt and re-grade before reading the table above' : 'usable'}.`);
const spent = results.filter(r => r.rep === rep).reduce((sum, r) => sum + Number(r.cost), 0);
out.push('', `Notional spend: ${money(spent)} over ${results.filter(r => r.rep === rep).length} runs.`);
console.log(out.join('\n'));
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `timeout 300 node --test evals/tiers/tests/grid.test.mjs`
Expected: PASS — `pass 9`, `fail 0`

- [ ] **Step 5: Commit**

```bash
git add evals/tiers/run-grid.mjs evals/tiers/report.mjs evals/tiers/tests/grid.test.mjs
git commit -m "feat(evals): add the grid runner and the report"
```

### Task 13: Review cases, README and test runner hook

**Files:**
- Create: `evals/tiers/cases/reviews/cases.json`
- Create: `evals/tiers/README.md`
- Modify: `scripts/test-all.mjs:44`

**Interfaces:**
- Consumes: `build-case.mjs` — Contracts, Scripts; the `cases.json` shape under Files.
- Produces: the ten review case ids, which Tasks 15, 16 and 20 use: `r-code-judge-seats`, `r-code-executor-interface`, `r-code-executor-interface-residual`, `r-code-item-registers`, `r-code-execution-cost`, `r-code-review-fixes`, `r-plan-project-state`, `r-plan-judge-seats`, `r-plan-inline-mode`, `r-plan-small-model`.

**Items:** 1
**Implementer:** dr-superpowers:impl-sonnet-high
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 1 = 3

- [ ] **Step 1: Write the review case list**

Create `evals/tiers/cases/reviews/cases.json`:

```json
[
  {
    "id": "r-code-judge-seats",
    "kind": "code",
    "base": "01f5a2ae278656643a85eaa090af6c4e6484e94f",
    "head": "f88429bfbdf876595946f99d71b26849bda60fd7",
    "fix": [
      "fb05b23f21546bbb8430e65dbe70e841a22cc3e2",
      "6d54b1e268c893649436a6cba3613483fcddcdcf"
    ],
    "plan": "docs/superpowers/plans/2026-09-14-dr-superpowers-judge-seats.md",
    "description": "Move both Claude-hosted Codex review seats to `gpt-6-astra / high` with a declared fallback, and make selection, the run bound and the outcome policy executable in one script instead of prose."
  },
  {
    "id": "r-code-executor-interface",
    "kind": "code",
    "base": "b41a726d780dc52bb4e7e719f611439283c84b82",
    "head": "1f13cc8584ef788731bd701c7b2c6a7a86f5a349",
    "fix": [
      "58885f995a79ed594548d771d05f186c424d8bd7"
    ],
    "plan": "docs/superpowers/plans/2026-09-21-dr-superpowers-executor-interface.md",
    "description": "Separate \"external executor\" from \"Codex\" inside dr-superpowers, so a second executor becomes a registry entry, a wrapper and a ladder block rather than a rewrite of eight files."
  },
  {
    "id": "r-code-executor-interface-residual",
    "kind": "code",
    "base": "b41a726d780dc52bb4e7e719f611439283c84b82",
    "head": "58885f995a79ed594548d771d05f186c424d8bd7",
    "fix": [
      "16752f6d91ebe77f435f353da27ba63afb9178a2"
    ],
    "plan": "docs/superpowers/plans/2026-09-21-dr-superpowers-executor-interface.md",
    "description": "Separate \"external executor\" from \"Codex\" inside dr-superpowers, so a second executor becomes a registry entry, a wrapper and a ladder block rather than a rewrite of eight files."
  },
  {
    "id": "r-code-item-registers",
    "kind": "code",
    "base": "58de434ffbc06e91850c9fa333f2378cfc6e4b16",
    "head": "800e834f5cb44304e42f297d292231d272f47f82",
    "fix": [
      "ddb5ed44325453ae14d203e953233ab19b515277"
    ],
    "plan": "docs/superpowers/plans/2026-09-20-dr-superpowers-item-registers.md",
    "description": "Give dr-superpowers a first-class item register, so no surface can claim a body of work complete while a source item is unresolved."
  },
  {
    "id": "r-code-execution-cost",
    "kind": "code",
    "base": "71dacfa17a0e1d599987e512b477b40ede4fe0cd",
    "head": "be03aeb13e8aaba1c1a0209737c300430438b784",
    "fix": [
      "d17b1f0100a0eb94049e6cf2dde756b1d0081e41"
    ],
    "plan": "docs/superpowers/plans/2026-09-17-dr-superpowers-execution-cost.md",
    "description": "Cut dr-superpowers' weekly-limit spend with mixed-mode inline execution, Fable reserved for critical seats, capped plan-review rounds and a 350k controller budget."
  },
  {
    "id": "r-code-review-fixes",
    "kind": "code",
    "base": "93fb70295892c871da58020b9354b3ff0a8bf862",
    "head": "3955c8055aa916f01e127427a2e7bb89582e82ae",
    "fix": [
      "dea77c5b986dac3add237e16efc2a3532cbd83fd"
    ],
    "plan": "docs/superpowers/plans/2026-09-17-dr-superpowers-review-fixes.md",
    "description": "Ship dr-superpowers 1.12.0: a working-directory contract with a same-repository check, delegation of total-4 tasks up to a third of a plan, named final-review seats, and escalation out of inline mode above both rungs."
  },
  {
    "id": "r-plan-project-state",
    "kind": "plan",
    "commit": "d6c288c2279f2dbabf2dd05d64e2454ca1e4a22c",
    "plan": "docs/superpowers/plans/2026-09-14-dr-superpowers-project-state.md",
    "spec": "docs/superpowers/specs/2026-09-14-dr-superpowers-project-state-design.md"
  },
  {
    "id": "r-plan-judge-seats",
    "kind": "plan",
    "commit": "01f5a2ae278656643a85eaa090af6c4e6484e94f",
    "plan": "docs/superpowers/plans/2026-09-14-dr-superpowers-judge-seats.md",
    "spec": "docs/superpowers/specs/2026-09-14-dr-superpowers-judge-seats-design.md"
  },
  {
    "id": "r-plan-inline-mode",
    "kind": "plan",
    "commit": "69c6b485813f44f27f5b940ad75ab6d370d4ff1f",
    "plan": "docs/superpowers/plans/2026-09-12-dr-superpowers-inline-mode.md",
    "spec": "docs/superpowers/specs/2026-09-12-dr-superpowers-inline-mode-design.md"
  },
  {
    "id": "r-plan-small-model",
    "kind": "plan",
    "commit": "5e96f14f5f8188af155a65c3abfdf6f5cb290f04",
    "plan": "docs/superpowers/plans/2026-09-12-dr-superpowers-small-model-planning.md",
    "spec": "docs/superpowers/specs/2026-09-12-dr-superpowers-small-model-planning-design.md"
  }
]
```

- [ ] **Step 2: Verify every review case builds**

```bash
dir=$(mktemp -d)
for id in r-code-judge-seats r-code-executor-interface r-code-executor-interface-residual r-code-item-registers r-code-execution-cost r-code-review-fixes r-plan-project-state r-plan-judge-seats r-plan-inline-mode r-plan-small-model; do
  timeout 120 node evals/tiers/build-case.mjs "$id" "$dir/$id" | cut -c1-60
done
rm -rf "$dir"
```

Expected: ten lines, each starting `build-case: r-`, and no error. A line `usage: build-case.mjs` means an id in the file is misspelled.

- [ ] **Step 3: Write the README**

Create `evals/tiers/README.md`:

```markdown
# Tier evaluation harness

Measures whether a dr-superpowers assignment row or review seat can move to a
cheaper agent, by replaying this repository's own plan history. The design,
the grading and the decision rules are in
`docs/superpowers/specs/2026-10-01-dr-superpowers-tier-eval-design.md`.

Only `run-grid.mjs`, `run-case.mjs` and `grade-review.mjs` call a model. They
run `claude -p`, which draws on the Claude subscription's usage limits.
Everything else, including the tests, is free. POSIX only.

## Commands

Run them from the repository root.

| Command | What it does |
|---|---|
| `node evals/tiers/build-manifest.mjs` | Enumerates eligible tasks, golden-checks each, writes `cases/manifest.tsv` and `cases/excluded.tsv` |
| `node evals/tiers/build-case.mjs CASE_ID DIR` | Builds one case's snapshot, brief and prompt, for inspection |
| `node evals/tiers/run-grid.mjs --stage STAGE [--rep N] [--minutes M] [--pass P]` | Runs the unscored cells of `smoke`, `written`, `stripped` or `review`, two at a time; `--minutes` stops starting cells after M minutes; `--pass` grades every review again as passes P and P + 1 |
| `node evals/tiers/run-case.mjs CASE_ID ARM [--rep N]` | Runs and grades one cell |
| `node evals/tiers/run-case.mjs CASE_ID ARM [--rep N] --exclude REASON` | Runs nothing: takes the case out of the repetition for every arm, with the reason |
| `node evals/tiers/grade-case.mjs RUN_DIR` | Re-grades a finished implementation run |
| `node evals/tiers/grade-review.mjs CASE_ID ARM [--rep N] [--pass P]` | Grades one review against its rubric |
| `node evals/tiers/report.mjs [--rep N] [--pass P]` | Prints the decision table, reading review grades of pass P |
| `node --test evals/tiers/tests/*.test.mjs` | The harness tests, against a stub `claude` |

`run-grid.mjs` exits 0 when the stage is complete, 3 when it stopped at a
rate limit, at the spend cap or at `--minutes`, 1 when cells remain after harness errors, and
2 when `plugins/dr-superpowers` differs from the manifest's start commit.
Run the same command again to resume: a cell with a scored row is skipped.

## Files

| Path | Holds |
|---|---|
| `arms.json` | The agents each row and the review seat are compared on, current agent first |
| `cases/manifest.tsv` | The implementation cases; its first line pins the start commit |
| `cases/excluded.tsv` | Every task left out, with the reason |
| `cases/reviews/cases.json` | The ten review cases |
| `cases/reviews/<case>.md` | The known defects of one review case, one `## D<n>:` heading each |
| `results/results.tsv` | One line per run |
| `results/review-grades.tsv` | One line per rubric defect per graded review |

Snapshots and transcripts go to `~/.cache/dr-tier-eval`, outside the
repository, under `rep<N>/<case>/<arm>/`.
```

- [ ] **Step 4: Run the harness tests from the repository test runner**

In `scripts/test-all.mjs`, find this line of the `jobs` array:

```js
  [bash, ['plugins/dr-status/tests/run-all.sh'], 420],
```

and insert these three lines directly above it:

```js
  // The tier-eval harness kills process groups and shells out to tar, so its
  // tests run on POSIX only.
  ...(process.platform === 'win32' ? [] : [[process.execPath, ['--test', ...readdirSync(resolve(root, 'evals/tiers/tests')).filter(name => name.endsWith('.test.mjs')).map(name => `evals/tiers/tests/${name}`)], 300]]),
```

- [ ] **Step 5: Verify the hook, the whole harness suite and the repository checks**

Run: `timeout 60 node scripts/test-all.mjs --list | grep -c 'evals/tiers/tests/grid.test.mjs'`
Expected: `1`

Run: `timeout 600 node --test evals/tiers/tests/*.test.mjs 2>&1 | grep -E '^ℹ (pass|fail)'`
Expected: `ℹ pass 67` and `ℹ fail 0`

Run: `timeout 120 node scripts/validate-repository.mjs && timeout 120 node --test tests/repository-layout.test.mjs tests/test-shards.test.mjs 2>&1 | grep -E '^ℹ fail'`
Expected: `Repository catalogs, manifests, versions, and bundled links are valid.` and `ℹ fail 0`

- [ ] **Step 6: Commit**

```bash
git add evals/tiers/cases/reviews/cases.json evals/tiers/README.md scripts/test-all.mjs
git commit -m "chore(evals): wire the harness into the repo"
```

### Task 14: Pin the case manifest

**Files:**
- Create: `evals/tiers/cases/manifest.tsv`
- Create: `evals/tiers/cases/excluded.tsv`

**Interfaces:**
- Consumes: `build-manifest.mjs` — Contracts, Scripts; `arms.json`.
- Produces: the committed manifest. Its first line pins the start commit that `run-grid.mjs` checks the plugin against in Tasks 17 to 20.

**Items:** 1
**Implementer:** dr-superpowers:impl-sonnet-medium
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 0 = 2

- [ ] **Step 1: Confirm the plugin is clean**

Run: `git status --porcelain -- plugins/dr-superpowers`
Expected: no output. If there is output, stop and report it: the manifest must not pin a dirty plugin.

- [ ] **Step 2: Build the manifest**

Run: `timeout 580 node evals/tiers/build-manifest.mjs`
Expected: one line, `build-manifest: 52 cases, 161 exclusions, start <40-hex commit>`. It takes about three minutes: it runs the historical tests of every eligible task twice.

- [ ] **Step 3: Build it again and confirm the result is the same**

```bash
cp evals/tiers/cases/manifest.tsv /tmp/tier-eval-manifest-first.tsv
timeout 580 node evals/tiers/build-manifest.mjs
diff /tmp/tier-eval-manifest-first.tsv evals/tiers/cases/manifest.tsv && echo SAME
rm /tmp/tier-eval-manifest-first.tsv
```

Expected: `SAME`. A difference means a historical test is not deterministic: report the differing case ids as `DONE_WITH_CONCERNS` and do not commit.

- [ ] **Step 4: Check the pool sizes against the spec**

Run: `sed 1,2d evals/tiers/cases/manifest.tsv | cut -f2,3 | sort | uniq -c`

Expected, exactly:

```
      3 stripped	3
      6 stripped	4
      2 stripped	5
      1 stripped	6
      7 written	1
      8 written	2
      8 written	3
      8 written	4
      8 written	5
      1 written	6
```

These are the counts of the table in spec §1. If they differ, stop and report the difference: the spec's table and its run counts must change with them, and that is the owner's call.

- [ ] **Step 5: Commit**

```bash
git add evals/tiers/cases/manifest.tsv evals/tiers/cases/excluded.tsv
git commit -m "chore(evals): pin the case manifest"
```

### Task 15: Code-review rubrics

**Files:**
- Create: `evals/tiers/cases/reviews/r-code-judge-seats.md`
- Create: `evals/tiers/cases/reviews/r-code-executor-interface.md`
- Create: `evals/tiers/cases/reviews/r-code-executor-interface-residual.md`
- Create: `evals/tiers/cases/reviews/r-code-item-registers.md`
- Create: `evals/tiers/cases/reviews/r-code-execution-cost.md`
- Create: `evals/tiers/cases/reviews/r-code-review-fixes.md`

**Interfaces:**
- Consumes: `evals/tiers/cases/reviews/cases.json` (Task 13): each code case's `base`, `head` and `fix` commits; the rubric format — Contracts, Files.
- Produces: the six rubrics `grade-review.mjs` reads in Task 20.

**Items:** 1
**Implementer:** dr-superpowers:impl-sonnet-high
**Evaluation:** files 0 - spec 2 - coupling 1 - risk 1 = 4

A rubric is the answer key of one review case: the defects that were really in the branch at its `head` commit and that the `fix` commits later closed. A reviewer is scored on how many of them it reports, so a defect that was not in the head commit, or two entries for one defect, corrupts the score.

- [ ] **Step 1: Read each case's fix commits**

For each of the six `kind: "code"` entries of `cases.json`, run `git show <sha>` for every sha in its `fix` array and read the whole diff and the commit message.

- [ ] **Step 2: Write one rubric per case in this format**

```markdown
# <case id>

Source: <where the defects come from, with the commit shas>

## D1: <the defect in one line>

- Where: `<path>`, <function, section or task>
- Defect: <what is wrong at the reviewed commit, in one or two sentences>
- Evidence: `<short sha>` <what that commit changed to fix it>
- Minimum severity: Important

## D2: <the next defect>
```

Rules:

- One defect per distinct fault the fix commits corrected, not one per hunk. A test the fix adds belongs to the defect it pins. A change to a skill or reference file that corrects an instruction is a defect; a pure rewording that changes no behaviour is not, and is left out.
- `Defect` describes the fault as a reviewer of the head commit could see it, in the repository's own terms. Do not describe the fix.
- `Minimum severity` is `Important` for every defect, because a later commit fixed it. Write `Critical` only when the fault made a script fail, lose data or accept input it must refuse.
- Number the defects `D1`, `D2`, … with no gap. The heading must match `## D<n>: `.
- `r-code-executor-interface-residual` lists only what `16752f6` fixed; `r-code-executor-interface` lists only what `58885f9` fixed.
- `r-code-judge-seats` covers both `fb05b23` and `6d54b1e`.

- [ ] **Step 3: Verify every defect was present at the head commit**

For each defect, run `git show <head>:<path>` for the path its `Where` names and confirm the faulty text or the missing behaviour is there. A defect you cannot find at the head commit is removed. Note in your report which defects you removed and why.

- [ ] **Step 4: Verify the rubrics parse**

```bash
node --input-type=module -e "
import { readFileSync } from 'node:fs';
import { defects } from './evals/tiers/grade-review.mjs';
const cases = JSON.parse(readFileSync('evals/tiers/cases/reviews/cases.json', 'utf8')).filter(c => c.kind === 'code');
for (const c of cases) {
  const ids = defects(readFileSync('evals/tiers/cases/reviews/' + c.id + '.md', 'utf8'));
  const ok = ids.length > 0 && ids.every((id, i) => id === 'D' + (i + 1));
  console.log(c.id, ids.length, ok ? 'ok' : 'BAD NUMBERING');
}
"
```

Expected: six lines, each ending `ok`, each with a count of at least 1.

- [ ] **Step 5: Commit**

```bash
git add evals/tiers/cases/reviews/r-code-*.md
git commit -m "docs(evals): write the code-review rubrics"
```

### Task 16: Plan-review rubrics

**Files:**
- Create: `evals/tiers/cases/reviews/r-plan-project-state.md`
- Create: `evals/tiers/cases/reviews/r-plan-judge-seats.md`
- Create: `evals/tiers/cases/reviews/r-plan-inline-mode.md`
- Create: `evals/tiers/cases/reviews/r-plan-small-model.md`
- Modify: `evals/tiers/cases/reviews/cases.json` (only to drop a case, Step 4)

**Interfaces:**
- Consumes: `evals/tiers/cases/reviews/cases.json` (Task 13): each plan case's `commit` and `plan`; the rubric format — Contracts, Files.
- Produces: the plan-review rubrics `grade-review.mjs` reads in Task 20.

**Items:** 1
**Implementer:** dr-superpowers:impl-sonnet-high
**Evaluation:** files 0 - spec 2 - coupling 1 - risk 1 = 4

A plan-review rubric lists defects that were in the plan file at the case's `commit` and that are known to be real because something later proved them. These plans carry their code verbatim, so a defect a later commit had to fix in the implementation was a defect of the plan when the plan's own code contains it.

- [ ] **Step 1: Write the `project-state` rubric from the calibration record**

Read `docs/superpowers/notes/2026-09-20-review-routing-calibration.md`, sections "Known defects (Step 5) — performed for the first time" and "One Critical verified against shipped code". They name three defects of the plan at `d6c288c`: the cross-task helper `absent` defined in Task 3 and used only by Task 11; the vacuous needles (`"CLAUDE.md"`, `"optional"`, `'seven'`, `'exit 0'`, and the Task 5 `squash` assertion); and Task 2 telling the skill to run `repo-audit` from the plugin root although `scripts/repo-audit` derives the repository from the working directory. Confirm each in the plan with `git show d6c288c:docs/superpowers/plans/2026-09-14-dr-superpowers-project-state.md` and write them as `D1` to `D3`.

- [ ] **Step 2: Find the defects of the other three plans**

For each of `judge-seats` (`01f5a2a`), `inline-mode` (`69c6b48`) and `small-model` (`5e96f14`):

1. List the commits of the plan's branch: `git log --reverse --format='%h %s' <commit>..main | head -40`, and stop at the commit that plans the next sub-project (a subject starting `docs(superpowers): plan` or `docs(plans): plan`).
2. In that range, read every commit whose subject starts `fix(` or `test(` and every commit that says it resolves a review.
3. A change in such a commit is a rubric defect when the faulty code or text it replaces is present in the plan file at the case's `commit`. Check with `git show <commit>:<plan> | grep -n -F '<a distinctive faulty line>'`.
4. For `judge-seats`, also use the finding the calibration record quotes under "The findings are substantive, not padding": Contracts weakens risk-3 validation to the presence of three keys, and Task 4 accepts its own invalid fixture. Confirm it in the plan at `01f5a2a`.

- [ ] **Step 3: Write the rubrics in this format**

```markdown
# <case id>

Source: <where the defects come from, with the commit shas>

## D1: <the defect in one line>

- Where: `<path>`, <function, section or task>
- Defect: <what is wrong at the reviewed commit, in one or two sentences>
- Evidence: `<short sha>` <what that commit changed to fix it>
- Minimum severity: Important

## D2: <the next defect>
```

`Where` names the plan's task or header section. `Evidence` names the commit that fixed the defect, or the calibration record's section for a defect taken from it. The other rules are those of the code-review rubrics: one entry per distinct fault, `Minimum severity: Important` unless the fault made the plan impossible to execute as written (`Critical`), and `D1`, `D2`, … with no gap.

- [ ] **Step 4: Drop a case with fewer than two verified defects**

A rubric with fewer than two defects cannot separate one reviewer from another. If a case ends with fewer than two, delete its rubric file, remove its entry from `evals/tiers/cases/reviews/cases.json`, and say so in your report with what you searched. Do not pad a rubric to reach two.

- [ ] **Step 5: Verify the rubrics parse and the remaining cases still build**

```bash
node --input-type=module -e "
import { readFileSync } from 'node:fs';
import { defects } from './evals/tiers/grade-review.mjs';
const cases = JSON.parse(readFileSync('evals/tiers/cases/reviews/cases.json', 'utf8'));
for (const c of cases) {
  const ids = defects(readFileSync('evals/tiers/cases/reviews/' + c.id + '.md', 'utf8'));
  const ok = ids.every((id, i) => id === 'D' + (i + 1)) && ids.length >= (c.kind === 'plan' ? 2 : 1);
  console.log(c.id, ids.length, ok ? 'ok' : 'BAD');
}
"
```

Expected: one line per case left in `cases.json`, each ending `ok`.

Run: `timeout 300 node --test evals/tiers/tests/*.test.mjs 2>&1 | grep -E '^ℹ fail'`
Expected: `ℹ fail 0`

- [ ] **Step 6: Commit**

```bash
git add evals/tiers/cases/reviews
git commit -m "docs(evals): write the plan-review rubrics"
```

### Task 17: Smoke stage

**Files:**
- Create: `evals/tiers/results/results.tsv`
- Create: `evals/tiers/results/review-grades.tsv`
- Create: `evals/tiers/results/log.md`

**Interfaces:**
- Consumes: `run-grid.mjs` — Contracts, Scripts; the manifest (Task 14); the rubrics (Tasks 15 and 16).
- Produces: the first scored rows, and `evals/tiers/results/log.md`, which Tasks 18 to 21 append to and read.

**Items:** 1
**Implementer:** dr-superpowers:impl-sonnet-high
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 1 = 3

This task makes the first model calls: five runs, one grading and two probes. Global Constraints: fresh session, owner's go-ahead, no cap raised. It exists to prove three assumptions before the larger stages spend anything; if one fails, stop, fix the harness under `evals/tiers/` in its own commit, and run this task again.

- [ ] **Step 1: Ask the owner for the usage reading**

Ask the owner to run `/usage` and give you the 5-hour and the weekly percentages. Write them down; Step 7 needs them.

- [ ] **Step 2: Probe the isolation flag**

```bash
probe=~/.cache/dr-tier-eval/probe
rm -rf "$probe" && mkdir -p "$probe"
(cd "$probe" && git init -q && printf '%s\n' 'List every Markdown heading that starts with "## " and appears anywhere in your instructions or context outside this message, one per line. If there is none, reply NONE.' \
  | timeout 180 claude -p --model haiku --setting-sources project --tools "" --output-format json --no-session-persistence --max-budget-usd 1 > out.json; \
  node -e 'const j = JSON.parse(require("fs").readFileSync("out.json", "utf8")); const r = Array.isArray(j) ? j.findLast(e => e.type === "result") : j; console.log(Object.keys(r).sort().join(" ")); console.log(r.result)')
```

The probe runs under `~/.cache/dr-tier-eval`, where every real run works, so it sees the instruction files a real run would see.

Expected: a first line of JSON keys that includes `is_error`, `modelUsage`, `num_turns`, `result` and `total_cost_usd`, and then a reply that contains none of `Process hygiene`, `The Rule` and `Routing`. `Process hygiene` is a heading of the owner's global instructions; `The Rule` and `Routing` are headings the dr-superpowers session-start hook injects. If any of the three appears, `--setting-sources project` does not isolate the run: stop and report. If a key is missing, `lib/claude.mjs` reads the wrong field: stop and report.

- [ ] **Step 3: Probe what a budget stop looks like**

```bash
probe=~/.cache/dr-tier-eval/probe
(cd "$probe" && printf '%s\n' 'Write a 900-word essay about rivers.' \
  | timeout 180 claude -p --model haiku --setting-sources project --tools "" --output-format json --no-session-persistence --max-budget-usd 0.001 > budget.json; echo "exit=$?"; \
  node -e 'const j = JSON.parse(require("fs").readFileSync("budget.json", "utf8")); const r = Array.isArray(j) ? j.findLast(e => e.type === "result") : j; console.log("is_error=" + r.is_error, "subtype=" + r.subtype, "cost=" + r.total_cost_usd)')
node --input-type=module -e "
import { readFileSync } from 'node:fs';
import { classify } from './evals/tiers/lib/claude.mjs';
console.log('kind=' + classify({ out: readFileSync(process.env.HOME + '/.cache/dr-tier-eval/probe/budget.json', 'utf8'), err: '', code: 1, timedOut: false }, 0).kind);
"
rm -rf "$probe"
```

Write the two printed lines down for the log. Then:

- `is_error=true` and `kind=budget` or `kind=cut`: `classify` settles a budget stop as `BLOCKED`. Continue, and record the real `subtype`.
- `is_error=false`: the CLI did not stop the call at this budget, so this probe shows nothing about a budget stop. Continue, and record that the budget stop is unobserved.
- Anything else — `kind=limit`, `kind=error`, a rejected flag, or output that is not JSON: stop and report. A budget stop read as a limit or as an error would be retried at full price on every invocation.

- [ ] **Step 4: Run the smoke stage**

Run, as a background command: `timeout --kill-after=30s 7100s node evals/tiers/run-grid.mjs --stage smoke`
Expected last line: `run-grid stage=smoke rep=1 ran=6 remaining=0 spent=<dollars> stop=-`, exit 0. For exit 3 or 1, follow the table in Task 18 Step 1.

- [ ] **Step 5: Check the model, the effort and the permissions**

Run: `cut -f3,6,7,8,9,10,11,12 evals/tiers/results/results.tsv`

Expected:

- The `impl-haiku` row names a Haiku model, the `impl-sonnet-medium` and `judge-sonnet-high` rows a Sonnet 5.5 model, and the `impl-opus-low` and `judge-opus@medium` rows an Opus 5.5 model. A row may name a second, smaller model beside it. A row whose main model is wrong means `--model` did not take effect: stop and report.
- The three implementation rows are `PASS`, `FAIL` or `BLOCKED` with more than 3 turns. A row with `status=none` and 1 or 2 turns means the run could not use its tools: read `~/.cache/dr-tier-eval/rep1/<case>/<arm>/output.json`, stop and report.
- The two review rows are `REVIEWED` and the grading row is `GRADED`.

Run: `grep -l -i effort ~/.cache/dr-tier-eval/rep1/*/*/output.json | head -3`

If the output JSON names the effort, confirm it matches each arm. If it does not, the effort cannot be confirmed from the output: record that sentence in the log, and compare the cost of the two review rows instead — `judge-opus@medium` and `judge-sonnet-high` reviewed the same case, and the record is what was observed, not a pass or a fail.

- [ ] **Step 6: Check one implementation run by hand**

Pick the `impl-sonnet-medium` row. In `~/.cache/dr-tier-eval/rep1/<its case>/impl-sonnet-medium/work`, run `git status --short` and `git log --oneline | head -3`. Expected: the files the task's brief names are changed or committed, which shows the run edited files and ran commands without a permission prompt.

- [ ] **Step 7: Ask the owner for the usage reading again and log the stage**

Ask the owner for `/usage` again. Create `evals/tiers/results/log.md`:

```markdown
# Tier eval log

## Smoke stage

- Date: <YYYY-MM-DD>
- Usage before: <5-hour %> / <weekly %>. Usage after: <5-hour %> / <weekly %>.
- Share of the weekly limit per run, as an upper bound: <(weekly after - weekly before) / 5; the grading and the two probes are charged to the five runs>.
- Projected upper bound for the rest of the repetition: <that figure times 139, the runs still to make>.
- Isolation probe: <the reply of Step 2>.
- Budget probe: <the line of Step 3>.
- Models reported: <one line per arm>.
- Effort: <named in the output and matching | not named in the output; costs of the two review rows>.
- Fixes made: <one line each, or None>.
```

Tell the owner the projected share and ask whether to start Task 18.

- [ ] **Step 8: Commit**

```bash
git add evals/tiers/results
git commit -m "chore(evals): record the smoke stage"
```

### Task 18: As-written stage

**Files:**
- Modify: `evals/tiers/results/results.tsv`
- Modify: `evals/tiers/results/log.md`

**Interfaces:**
- Consumes: `run-grid.mjs`, `report.mjs` — Contracts, Scripts; the manifest (Task 14); `evals/tiers/results/log.md` (Task 17).
- Produces: the scored rows of the `written` stage in `results.tsv`, which Task 21 reports.

**Items:** 1
**Implementer:** dr-superpowers:impl-sonnet-high
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 1 = 3

This task calls a model up to 88 times; cells the smoke stage already scored are skipped. Global Constraints: fresh session, owner's go-ahead, no cap raised.

- [ ] **Step 1: Run the stage in slices until it is complete**

Run this as a background command with a two-hour limit. It stops starting cells after 100 minutes, so the cells in flight finish before the limit:

```bash
timeout --kill-after=30s 7100s node evals/tiers/run-grid.mjs --stage written --minutes 100
```

Read its last line, `run-grid stage=written rep=1 ran=<k> remaining=<m> spent=<dollars> stop=<reason>`, and its exit status:

| Exit | `stop=` | Do |
|---|---|---|
| 0 | `-` | The stage is complete. Go to the next step. |
| 3 | `time` | Run the same command again. |
| 3 | `limit` | A usage limit was reached. Tell the owner, wait for the limit to reset, then run the same command again. Do not retry in a loop. |
| 3 | `cap` | The repetition reached 250 notional dollars. Stop and report to the owner; do not raise the cap. |
| 1 | `-` | Cells are `NOT_RUN` after errors. Read the `detail` column of the last `NOT_RUN` rows of `evals/tiers/results/results.tsv`. If the detail quotes a usage-limit message, the limit pattern missed it: treat it as `limit` above, and add the message's wording to `LIMIT` in `evals/tiers/lib/claude.mjs` with a test, in its own commit. If it names a harness fault, fix it under `evals/tiers/` in its own commit. If one case can never run, take it out with `node evals/tiers/run-case.mjs <case> <any arm> --exclude "<reason>"` and note it in the log. A grading row whose detail starts `cut:`, `budget:` or `timeout:` is retried by the next invocation; if the same grading fails that way twice, stop and report. Then run the same command again. |
| 2 | | The plugin differs from the manifest's start commit. Stop and report; do not rebuild the manifest. |

- [ ] **Step 2: Confirm every cell is scored**

Run: `node evals/tiers/run-grid.mjs --stage written --minutes 0 | tail -1`
Expected: `run-grid stage=written rep=1 ran=0 remaining=0 spent=<dollars> stop=-`

- [ ] **Step 3: Log the stage and report to the owner**

Run: `awk -F'\t' '$1 == 1 && $2 == "written" { n[$7]++; cost += $9 } END { for (o in n) printf "%s %d\n", o, n[o]; printf "cost %.2f\n", cost }' evals/tiers/results/results.tsv`

Append to `evals/tiers/results/log.md` a section `## As-written stage` holding the date, that command's output, and one line for anything that had to be fixed or re-run. Then tell the owner the counts and the spend, and ask before starting the next stage.

- [ ] **Step 4: Commit**

```bash
git add evals/tiers/results
git commit -m "chore(evals): record the as-written stage"
```

### Task 19: Stripped stage

**Files:**
- Modify: `evals/tiers/results/results.tsv`
- Modify: `evals/tiers/results/log.md`

**Interfaces:**
- Consumes: `run-grid.mjs`, `report.mjs` — Contracts, Scripts; the manifest (Task 14); `evals/tiers/results/log.md` (Task 17).
- Produces: the scored rows of the `stripped` stage in `results.tsv`, which Task 21 reports.

**Items:** 1
**Implementer:** dr-superpowers:impl-sonnet-high
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 1 = 3

This task calls a model up to 26 times; cells the smoke stage already scored are skipped. Global Constraints: fresh session, owner's go-ahead, no cap raised.

- [ ] **Step 1: Run the stage in slices until it is complete**

Run this as a background command with a two-hour limit. It stops starting cells after 100 minutes, so the cells in flight finish before the limit:

```bash
timeout --kill-after=30s 7100s node evals/tiers/run-grid.mjs --stage stripped --minutes 100
```

Read its last line, `run-grid stage=stripped rep=1 ran=<k> remaining=<m> spent=<dollars> stop=<reason>`, and its exit status:

| Exit | `stop=` | Do |
|---|---|---|
| 0 | `-` | The stage is complete. Go to the next step. |
| 3 | `time` | Run the same command again. |
| 3 | `limit` | A usage limit was reached. Tell the owner, wait for the limit to reset, then run the same command again. Do not retry in a loop. |
| 3 | `cap` | The repetition reached 250 notional dollars. Stop and report to the owner; do not raise the cap. |
| 1 | `-` | Cells are `NOT_RUN` after errors. Read the `detail` column of the last `NOT_RUN` rows of `evals/tiers/results/results.tsv`. If the detail quotes a usage-limit message, the limit pattern missed it: treat it as `limit` above, and add the message's wording to `LIMIT` in `evals/tiers/lib/claude.mjs` with a test, in its own commit. If it names a harness fault, fix it under `evals/tiers/` in its own commit. If one case can never run, take it out with `node evals/tiers/run-case.mjs <case> <any arm> --exclude "<reason>"` and note it in the log. A grading row whose detail starts `cut:`, `budget:` or `timeout:` is retried by the next invocation; if the same grading fails that way twice, stop and report. Then run the same command again. |
| 2 | | The plugin differs from the manifest's start commit. Stop and report; do not rebuild the manifest. |

- [ ] **Step 2: Confirm every cell is scored**

Run: `node evals/tiers/run-grid.mjs --stage stripped --minutes 0 | tail -1`
Expected: `run-grid stage=stripped rep=1 ran=0 remaining=0 spent=<dollars> stop=-`

- [ ] **Step 3: Log the stage and report to the owner**

Run: `awk -F'\t' '$1 == 1 && $2 == "stripped" { n[$7]++; cost += $9 } END { for (o in n) printf "%s %d\n", o, n[o]; printf "cost %.2f\n", cost }' evals/tiers/results/results.tsv`

Append to `evals/tiers/results/log.md` a section `## Stripped stage` holding the date, that command's output, and one line for anything that had to be fixed or re-run. Then tell the owner the counts and the spend, and ask before starting the next stage.

- [ ] **Step 4: Commit**

```bash
git add evals/tiers/results
git commit -m "chore(evals): record the stripped stage"
```

### Task 20: Review stage

**Files:**
- Modify: `evals/tiers/results/results.tsv`
- Modify: `evals/tiers/results/review-grades.tsv`
- Modify: `evals/tiers/results/log.md`

**Interfaces:**
- Consumes: `run-grid.mjs`, `report.mjs` — Contracts, Scripts; the manifest (Task 14); `evals/tiers/results/log.md` (Task 17).
- Produces: the scored rows of the `review` stage in `results.tsv`, which Task 21 reports.

**Items:** 1
**Implementer:** dr-superpowers:impl-sonnet-high
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 1 = 3

This task calls a model up to 30 times for the reviews and up to 36 times for the gradings; cells the smoke stage already scored are skipped. Global Constraints: fresh session, owner's go-ahead, no cap raised.

- [ ] **Step 1: Run the stage in slices until it is complete**

Run this as a background command with a two-hour limit. It stops starting cells after 100 minutes, so the cells in flight finish before the limit:

```bash
timeout --kill-after=30s 7100s node evals/tiers/run-grid.mjs --stage review --minutes 100
```

Read its last line, `run-grid stage=review rep=1 ran=<k> remaining=<m> spent=<dollars> stop=<reason>`, and its exit status:

| Exit | `stop=` | Do |
|---|---|---|
| 0 | `-` | The stage is complete. Go to the next step. |
| 3 | `time` | Run the same command again. |
| 3 | `limit` | A usage limit was reached. Tell the owner, wait for the limit to reset, then run the same command again. Do not retry in a loop. |
| 3 | `cap` | The repetition reached 250 notional dollars. Stop and report to the owner; do not raise the cap. |
| 1 | `-` | Cells are `NOT_RUN` after errors. Read the `detail` column of the last `NOT_RUN` rows of `evals/tiers/results/results.tsv`. If the detail quotes a usage-limit message, the limit pattern missed it: treat it as `limit` above, and add the message's wording to `LIMIT` in `evals/tiers/lib/claude.mjs` with a test, in its own commit. If it names a harness fault, fix it under `evals/tiers/` in its own commit. If one case can never run, take it out with `node evals/tiers/run-case.mjs <case> <any arm> --exclude "<reason>"` and note it in the log. A grading row whose detail starts `cut:`, `budget:` or `timeout:` is retried by the next invocation; if the same grading fails that way twice, stop and report. Then run the same command again. |
| 2 | | The plugin differs from the manifest's start commit. Stop and report; do not rebuild the manifest. |

- [ ] **Step 2: Confirm every cell is scored**

Run: `node evals/tiers/run-grid.mjs --stage review --minutes 0 | tail -1`
Expected: `run-grid stage=review rep=1 ran=0 remaining=0 spent=<dollars> stop=-`

Run: `node evals/tiers/report.mjs | grep '^Grader consistency'`
Expected: a line ending `- usable.` If it ends `INCONSISTENT: …`, stop and report to the owner with the disagreeing rows of `evals/tiers/results/review-grades.tsv`; do not edit the grader prompt on your own. Once the owner has approved a change to `graderPrompt` in `evals/tiers/grade-review.mjs` and it is committed with its test, grade every review again with `node evals/tiers/run-grid.mjs --stage review --pass 3`, then run `node evals/tiers/report.mjs --pass 3 | grep '^Grader consistency'`. Expected: a line ending `- usable.` If it is still inconsistent, stop and report to the owner again. Read every later report with `--pass 3`, and say in the log which pass the results note uses.

Run: `awk -F'\t' '$1 == 1 && $4 == "review" && $7 == "BLOCKED" { print $3, $6, $12 }' evals/tiers/results/results.tsv`

Each line is a review cell that was cut short and wrote no review: the grid graded it as missing every defect. Paste the output into the log section of Step 3, or write `None`.

- [ ] **Step 3: Log the stage and report to the owner**

Run: `awk -F'\t' '$1 == 1 && $2 == "review" { n[$7]++; cost += $9 } END { for (o in n) printf "%s %d\n", o, n[o]; printf "cost %.2f\n", cost }' evals/tiers/results/results.tsv`

Append to `evals/tiers/results/log.md` a section `## Review stage` holding the date, that command's output, and one line for anything that had to be fixed or re-run. Then tell the owner the counts and the spend, and ask before starting the next stage.

- [ ] **Step 4: Commit**

```bash
git add evals/tiers/results
git commit -m "chore(evals): record the review stage"
```

### Task 21: Results note and register

**Files:**
- Create: `docs/superpowers/notes/YYYY-MM-DD-tier-eval-results.md` (the date this task runs)
- Modify: `docs/superpowers/registers/2026-10-01-tier-reevaluation.md`

**Interfaces:**
- Consumes: `report.mjs` — Contracts, Scripts; `evals/tiers/results/results.tsv`, `evals/tiers/results/review-grades.tsv`, `evals/tiers/results/log.md` (Tasks 17 to 20).
- Produces: the results note the owner rules from, and the register state.

**Items:** 1
**Implementer:** dr-superpowers:impl-sonnet-high
**Evaluation:** files 1 - spec 1 - coupling 1 - risk 0 = 3

- [ ] **Step 1: Generate the report**

Run: `node evals/tiers/report.mjs > /tmp/tier-eval-report.md && grep -c '^### Row' /tmp/tier-eval-report.md`
Expected: `6`. No row and no review seat may read `INCOMPLETE`: `grep -c INCOMPLETE /tmp/tier-eval-report.md` prints `0`. If one does, a stage of Tasks 18 to 20 is unfinished: run that stage's `run-grid.mjs` command again and read its last line. If a grader pass above 1 was used in Task 20, add `--pass <that pass>` to the `report.mjs` command here.

- [ ] **Step 2: Write the results note**

Create `docs/superpowers/notes/<today>-tier-eval-results.md` with these sections, in this order:

```markdown
# Tier evaluation results, repetition 1

Spec: `docs/superpowers/specs/2026-10-01-dr-superpowers-tier-eval-design.md`. Harness and data: `evals/tiers/`. Run: <first date> to <last date>.

## What the rules produce

| Row or seat | Current | Verdict | Evidence |
|---|---|---|---|
<one line per row 1 to 6, the verdict copied from the report, the evidence as "<n> trials, <k> regressions">
<one line per review candidate, the evidence as "<found> of <of> defects, <k> Critical missed", and the verdict mapped from the report:
 `judge-opus@medium` SUPPORTED is "move: judge-opus effort high to medium"; `judge-sonnet-high` SUPPORTED is "owner ruling: indirect evidence for raising the task-review band"; NOT SUPPORTED is "unchanged" for either>

## Rulings left to the owner

<one bullet per verdict that says "owner ruling", per row marked INCONCLUSIVE, and these three always:
- Row 0 has no case; say what `impl-haiku` did on row 1.
- Row 6 rests on two cases.
- Whether `judge-sonnet-high` may review above total 3 rests on whole-branch and plan reviews, not on task reviews.>

## Proposed second repetition

<the rows marked INCONCLUSIVE, the rows the report flags for the next agent up, and `impl-sonnet-xhigh` on row 5 if `impl-sonnet-high` regressed there; or "None">

## The report

<the whole of /tmp/tier-eval-report.md, pasted>

## Every regression

<one bullet per regression: case id, arm, outcome, and the `detail` column of its row in results.tsv>

## Limits of this evidence

- One repetition. Each row's note states the true regression rate its trial count still allows.
- As-written cases carry the plan's code, so they measure transcription, verification and cost, not problem-solving. Only the stripped cases measure the second, and rows 2, 3, 5 and 6 have fewer than four of them.
- A run could read the installed plugin or this repository on the same machine and find the historical answer. Nothing prevented it and no transcript was kept to check it.
- Cost is the CLI's notional API price, not a bill.
- <anything the log records: a stage re-run, a harness fix, a dropped case>
```

Fill every `<…>` from the report, `results.tsv` and the log. Change no verdict and add no recommendation the rules do not produce: where the rules say owner ruling, say what the evidence shows and stop.

- [ ] **Step 3: Update the register**

Run:

```bash
bash plugins/dr-superpowers/scripts/register set docs/superpowers/registers/2026-10-01-tier-reevaluation.md 1 verify --note "results note committed; the owner rules on the moves"
bash plugins/dr-superpowers/scripts/register check docs/superpowers/registers/2026-10-01-tier-reevaluation.md
```

Expected: `register: 0 errors`. Row 2 stays `deferred`: the mapping table update gets its own spec from this note.

- [ ] **Step 4: Commit**

```bash
git add docs/superpowers/notes/*-tier-eval-results.md docs/superpowers/registers/2026-10-01-tier-reevaluation.md
git commit -m "docs(superpowers): report the tier evaluation"
rm /tmp/tier-eval-report.md
```
