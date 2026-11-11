// Acceptance tests for the test-tiers-and-ci-parity spec
// (docs/dforge/specs/2026-10-31-test-tiers-and-ci-parity-design.md), A1-A27.
// Each test is written from the statement's text and reaches the behaviour
// through the public surface: plan-lint, task-step, suite-run, ci-mirror,
// lint-portability.mjs, validate-repository.mjs, test-all.mjs and
// tests/test-shards.test.mjs, run as commands against throwaway repositories
// and trees; and, where a statement is about what a skill or reference tells a
// session to do (no script reaches it), the text of the shipped file.
// A13, A18, A19 and A23 have no code behind them: a session carries them out
// by reading the skill, so they are pinned by the skill's text only.
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { cpSync, existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { after, test } from 'node:test';
import { fileURLToPath } from 'node:url';

const REPO = fileURLToPath(new URL('../../../', import.meta.url));
const PLUGIN = join(REPO, 'plugins/dforge');
const SCRIPTS = join(PLUGIN, 'scripts');
const PLAN_LINT = join(SCRIPTS, 'plan-lint');
const TASK_STEP = join(SCRIPTS, 'task-step');
const SUITE_RUN = join(SCRIPTS, 'suite-run');
const CI_MIRROR = join(SCRIPTS, 'ci-mirror');
const SDD_WORKSPACE = join(SCRIPTS, 'sdd-workspace');
const DFORGE_PATH = join(SCRIPTS, 'dforge-path');

const TMP = mkdtempSync(join(tmpdir(), 'tiers-ci-acceptance-'));
after(() => rmSync(TMP, { recursive: true, force: true }));

const ENV = { ...process.env };
// A nested node --test would otherwise report to this run instead of running on its own.
delete ENV.NODE_TEST_CONTEXT;
for (const key of ['CLAUDE_CONFIG_DIR', 'CODEX_HOME', 'AR_SESSION', 'DFORGE_BUDGET', 'DR_SUPERPOWERS_BUDGET', 'CLAUDE_PROJECT_DIR', 'GIT_AUTHOR_NAME', 'GIT_AUTHOR_EMAIL', 'GIT_COMMITTER_NAME', 'GIT_COMMITTER_EMAIL']) delete ENV[key];
Object.assign(ENV, {
  HOME: join(TMP, 'home'),
  GIT_CONFIG_GLOBAL: '/dev/null',
  GIT_CONFIG_NOSYSTEM: '1',
  DFORGE_NO_SETTINGS: '1',
  MSYS_NO_PATHCONV: '1',
  DR_CODEX_SESSION_DIR: join(TMP, 'codex-sessions'),
  CLAUDE_CODE_SESSION_ID: 'tiers-ci-acceptance',
});
mkdirSync(join(ENV.HOME, '.claude'), { recursive: true });

function sh(command, args, { cwd = TMP, env = {}, timeout = 240000 } = {}) {
  const result = spawnSync(command, args, { cwd, env: { ...ENV, ...env }, encoding: 'utf8', timeout, killSignal: 'SIGKILL' });
  if (result.error) throw result.error;
  return { status: result.status, out: (result.stdout ?? '').replace(/\r/g, ''), err: (result.stderr ?? '').replace(/\r/g, '') };
}
const bash = (script, args, options) => sh('bash', [script, ...args], options);
const git = (cwd, ...args) => sh('git', args, { cwd }).out.trim();

let counter = 0;
function scratch(name) {
  const dir = join(TMP, `${name}-${++counter}`);
  mkdirSync(dir, { recursive: true });
  return dir;
}
function write(dir, name, text) {
  const path = join(dir, name);
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, text);
  return path;
}
function makeRepo(name) {
  const dir = scratch(name);
  git(dir, 'init', '-q');
  git(dir, 'config', 'user.name', 'Darkraise');
  git(dir, 'config', 'user.email', 'dark@example.invalid');
  return dir;
}
function commit(dir, message) {
  git(dir, 'add', '-A');
  git(dir, 'commit', '-q', '-m', message);
  return git(dir, 'rev-parse', 'HEAD');
}

const read = relative => readFileSync(join(REPO, relative), 'utf8').replace(/\r/g, '');
const flat = relative => read(relative).replace(/\s+/g, ' ');
const flatText = text => text.replace(/\s+/g, ' ');
// The body of the markdown section whose heading line matches `heading`, up to
// the next heading of the same or a higher level.
function section(text, heading) {
  const lines = text.split('\n');
  let fenced = false;
  const headings = lines.map(line => {
    if (/^```/.test(line)) fenced = !fenced;
    return !fenced && /^#+ /.test(line) ? line.match(/^#+/)[0].length : 0;
  });
  const start = lines.findIndex((line, i) => headings[i] > 0 && heading.test(line));
  assert.ok(start >= 0, `no heading matching ${heading}`);
  const end = headings.findIndex((level, i) => i > start && level > 0 && level <= headings[start]);
  return lines.slice(start, end < 0 ? undefined : end).join('\n');
}
const P = relative => `plugins/dforge/${relative}`;

// ---------------------------------------------------------------- plan fixtures
const REVIEW_LINE = '**Plan review:** 2026-10-10 — dforge:judge-opus — executability 18 / coherence 18 / coverage 18 / assumptions 18 (round 1)';
const TASK_CHECK = '**Task check:** `bash quick.sh` — gate 1 has Tier: task';
const INTEGRATION = '**Integration check:** `bash test.sh`';
const FULL_CI = '**CI:** `.github/workflows/validate.yml` — platforms: ubuntu-latest, windows-latest — local: `node scripts/test-all.mjs` — uncovered: Windows Git Bash';

// A plan of `tasks` tasks. `lines` are the header lines after Execution;
// `waves` (a Parallelism value) makes it a waves plan; `steps[i]` is the Step 1
// heading text of Task i + 1, or nothing for no step.
function plan({ lines = [TASK_CHECK, INTEGRATION, '**CI:** none', REVIEW_LINE], tasks = 3, waves, steps = [] } = {}) {
  const head = [
    '# Demo Implementation Plan',
    '',
    '**Goal:** Demo.',
    '',
    '**Spec:** `docs/spec.md`',
    '',
    waves ? '**Execution:** subagent — `claude --model sonnet --effort high` — parallel waves' : '**Execution:** inline — `claude --model sonnet --effort low` — fixture',
    '',
  ];
  if (waves) head.push(`**Parallelism:** ${waves}`, '', '**Worktree setup:** none', '');
  for (const line of lines) head.push(line, '');
  head.push('## Global Constraints', '', '- Bash only.', '', '## Contracts', '', 'None', '', '## Assumptions (evidence)', '', '- None.', '', '## Task index', '');
  for (let n = 1; n <= tasks; n++) head.push(`${n}. Thing ${n}`);
  head.push('');
  for (let n = 1; n <= tasks; n++) {
    head.push(`### Task ${n}: Thing ${n}`, '', '**Files:**', `- Create: \`f${n}.txt\``, '');
    if (waves) head.push(`**Depends on:** ${n === 1 ? 'none' : 'Task 1'}`, '');
    head.push('**Implementer:** dforge:impl-sonnet-low', '**Evaluation:** files 0 - spec 0 - coupling 1 - risk 0 = 1', '');
    if (steps[n - 1]) head.push(`- [ ] **Step 1: ${steps[n - 1]}**`, '');
  }
  return head.join('\n');
}

const lintDir = scratch('lint');
write(lintDir, 'docs/spec.md', '# Spec\n');
let planCount = 0;
function lint(text) {
  const path = write(lintDir, `plan-${++planCount}.md`, text);
  const result = bash(PLAN_LINT, [path, '--no-probe'], { cwd: lintDir });
  return { status: result.status, out: result.out };
}
const without = (...labels) => (text) => text.split('\n').filter(line => !labels.some(label => line.startsWith(`**${label}:**`))).join('\n');

// ---------------------------------------------------------------- A1
test('A1: plan-lint warns on a plan with neither tier line and exits 0', () => {
  const { status, out } = lint(plan({ lines: ['**CI:** none', REVIEW_LINE] }));
  assert.equal(status, 0, out);
  assert.match(out, /^WARN header: .*Task check/m);
  assert.match(out, /^WARN header: .*Integration check/m);
  assert.doesNotMatch(out, /^ERROR/m);
});

test('A1: plan-lint warns on each tier line missing alone', () => {
  const noTask = lint(plan({ lines: [INTEGRATION, '**CI:** none', REVIEW_LINE] }));
  assert.equal(noTask.status, 0, noTask.out);
  assert.match(noTask.out, /^WARN header: .*Task check/m);
  assert.doesNotMatch(noTask.out, /Integration check/);
  const noIntegration = lint(plan({ lines: [TASK_CHECK, '**CI:** none', REVIEW_LINE] }));
  assert.equal(noIntegration.status, 0, noIntegration.out);
  assert.match(noIntegration.out, /^WARN header: .*Integration check/m);
  assert.doesNotMatch(noIntegration.out, /Task check/);
});

test('A1: plan-lint fails a malformed Task check or Integration check', () => {
  for (const bad of ['**Task check:** run the quick tests', '**Task check:** `bash a.sh` `bash b.sh` — two commands', '**Task check:** none', '**Task check:**']) {
    const { status, out } = lint(plan({ lines: [bad, INTEGRATION, '**CI:** none', REVIEW_LINE] }));
    assert.equal(status, 1, `${bad}\n${out}`);
    assert.match(out, /^ERROR header: .*Task check/m, bad);
  }
  for (const bad of ['**Integration check:**']) {
    const { status, out } = lint(plan({ lines: [TASK_CHECK, bad, '**CI:** none', REVIEW_LINE] }));
    assert.equal(status, 1, `${bad}\n${out}`);
    assert.match(out, /^ERROR header: .*Integration check/m, bad);
  }
});

test('A1: plan-lint passes a plan with both lines well formed, the none form included', () => {
  for (const taskCheck of [TASK_CHECK, '**Task check:** none — full suite every 3 tasks']) {
    const { status, out } = lint(plan({ lines: [taskCheck, INTEGRATION, '**CI:** none', REVIEW_LINE] }));
    assert.equal(status, 0, out);
    assert.match(out, /plan-lint: 0 errors, 0 warnings/);
  }
});

test('A1: plan-lint still fails a waves plan without an Integration check, and passes it with one', () => {
  const waves = 'waves — 1 | 2-3';
  const missing = lint(plan({ waves, lines: [TASK_CHECK, '**CI:** none', REVIEW_LINE] }));
  assert.equal(missing.status, 1, missing.out);
  assert.match(missing.out, /^ERROR header: .*Integration check/m);
  const present = lint(plan({ waves, lines: [TASK_CHECK, INTEGRATION, '**CI:** none', REVIEW_LINE] }));
  assert.equal(present.status, 0, present.out);
});

// ---------------------------------------------------------------- task-step fixtures
const STEP_SUITE = 'while read -r l; do echo "not ok 1 - $l"; done < failing.txt\n[ ! -s failing.txt ]\n';
function stepPlan(taskCheck, tasks) {
  const body = ['# Step Fixture Plan', '', '**Goal:** Fixture.', '', '**Execution:** subagent — `claude --model sonnet --effort high` — fixture', ''];
  if (taskCheck) body.push(`**Task check:** ${taskCheck}`, '');
  body.push('**Integration check:** `bash suite.sh`', '', '## Global Constraints', '', '- Fixture constraint.', '', '## Contracts', '', '- Fixture contract.', '', '## Task index', '');
  for (let n = 1; n <= tasks; n++) body.push(`${n}. Thing ${n}`);
  body.push('');
  for (let n = 1; n <= tasks; n++) body.push(`### Task ${n}: Thing ${n}`, '', '**Implementer:** dforge:impl-sonnet-low', '**Evaluation:** files 0 - spec 0 - coupling 0 - risk 0 = 0', '', `Body ${n}.`, '');
  return body.join('\n');
}
// A repository holding docs/plan.md, a suite.sh that fails once per line of
// failing.txt, and one commit.
function stepRepo(name, { taskCheck = 'none — full suite every 3 tasks', tasks = 4, failing = '' } = {}) {
  const dir = makeRepo(name);
  write(dir, 'docs/plan.md', stepPlan(taskCheck, tasks));
  write(dir, 'suite.sh', STEP_SUITE);
  write(dir, 'failing.txt', failing);
  const base = commit(dir, 'docs: add fixture');
  const ws = bash(SDD_WORKSPACE, ['docs/plan.md'], { cwd: dir }).out.trim();
  return { dir, base, ws };
}
const step = (repo, ...args) => bash(TASK_STEP, args, { cwd: repo.dir });
const suite = (repo, ...args) => bash(SUITE_RUN, ['--', ...args], { cwd: repo.dir });
const SUITE_CMD = 'bash suite.sh';
const stepFile = (repo, n) => JSON.parse(readFileSync(join(repo.ws, `task-${n}-step.json`), 'utf8'));
function passReport(repo, n) {
  write(repo.ws, `task-${n}-review-report.md`, '## Verdict\nspec: pass\nquality: approved\nscores: spec 17 / scope 18 / verification 16 / quality 16\n');
}
let workCount = 0;
function work(repo) {
  write(repo.dir, `work-${++workCount}.txt`, 'x\n');
  return commit(repo.dir, `work ${workCount}`);
}

// ---------------------------------------------------------------- A2
test('A2: delegated-task.md has the controller pass a command task check, never the integration check, to every start', () => {
  const text = flat(P('reference/delegated-task.md'));
  assert.match(text, /A command task check is the suite command: every `task-step start` passes it, never the Integration check/);
  assert.match(read(P('tests/delegated-suite.test.sh')), /never the Integration check/);
});

test('A2: task-step start --suite records exactly the task check, not the integration check, on the step file', () => {
  const repo = stepRepo('a2', { taskCheck: '`bash quick.sh` — gate 1 has Tier: task', tasks: 2 });
  for (const n of [1, 2]) {
    const result = step(repo, 'start', 'docs/plan.md', String(n), '--suite', 'bash quick.sh');
    assert.equal(result.status, 0, result.err);
    assert.equal(stepFile(repo, n).suite, 'bash quick.sh');
    assert.notEqual(stepFile(repo, n).suite, SUITE_CMD);
  }
});

// ---------------------------------------------------------------- A3
test('A3: review --suite and --suite-base write both onto the step file, and verdict excuses only failures that also fail at that sha', () => {
  const repo = stepRepo('a3', { failing: 'old failure\n' });
  const s = repo.base;
  assert.equal(suite(repo, 'bash', '-c', SUITE_CMD).status, 1);
  write(repo.dir, 'failing.txt', 'old failure\nregression by earlier task\n');
  commit(repo.dir, 'earlier task regresses');
  assert.equal(step(repo, 'start', 'docs/plan.md', '3').status, 0);
  work(repo);
  const review = step(repo, 'review', 'docs/plan.md', '3', '--suite', SUITE_CMD, '--suite-base', s);
  assert.equal(review.status, 0, review.err);
  const recorded = stepFile(repo, 3);
  assert.equal(recorded.suite, SUITE_CMD);
  assert.equal(recorded.suiteBase, s);
  assert.equal(suite(repo, 'bash', '-c', SUITE_CMD).status, 1);
  passReport(repo, 3);
  const verdict = step(repo, 'verdict', 'docs/plan.md', '3');
  assert.equal(verdict.status, 0, verdict.err + verdict.out);
  assert.match(verdict.out, /^findings: 0 Critical, 1 Important, 0 Minor$/m);
  assert.match(verdict.out, /^Important 3 .*regression by earlier task/m);
  assert.doesNotMatch(verdict.out, /^Important .*old failure/m);
  assert.match(verdict.out, /^suite: red \(1 failing, 1 baseline\)$/m);
});

test('A3: without --suite-base the same regression is excused as a base failure', () => {
  const repo = stepRepo('a3-control', { failing: 'old failure\n' });
  write(repo.dir, 'failing.txt', 'old failure\nregression by earlier task\n');
  commit(repo.dir, 'earlier task regresses');
  assert.equal(step(repo, 'start', 'docs/plan.md', '3', '--suite', SUITE_CMD).status, 0);
  work(repo);
  assert.equal(step(repo, 'review', 'docs/plan.md', '3').status, 0);
  assert.equal(suite(repo, 'bash', '-c', SUITE_CMD).status, 1);
  passReport(repo, 3);
  const verdict = step(repo, 'verdict', 'docs/plan.md', '3');
  assert.equal(verdict.status, 0, verdict.err + verdict.out);
  assert.match(verdict.out, /^findings: 0 Critical, 0 Important, 0 Minor$/m);
  assert.match(verdict.out, /^suite: red \(0 failing, 2 baseline\)$/m);
});

test('A3: review --group writes suite and suiteBase onto the last member and verdict --group reads them', () => {
  const repo = stepRepo('a3-group', { failing: 'old failure\n' });
  const s = repo.base;
  assert.equal(suite(repo, 'bash', '-c', SUITE_CMD).status, 1);
  write(repo.dir, 'failing.txt', 'old failure\nregression by earlier task\n');
  commit(repo.dir, 'earlier task regresses');
  for (const n of [1, 2]) assert.equal(step(repo, 'start', 'docs/plan.md', String(n)).status, 0);
  work(repo);
  assert.equal(step(repo, 'hold', 'docs/plan.md', '1').status, 0);
  work(repo);
  assert.equal(step(repo, 'hold', 'docs/plan.md', '2').status, 0);
  const review = step(repo, 'review', '--group', 'docs/plan.md', '1', '2', '--suite', SUITE_CMD, '--suite-base', s);
  assert.equal(review.status, 0, review.err);
  assert.equal(stepFile(repo, 2).suite, SUITE_CMD);
  assert.equal(stepFile(repo, 2).suiteBase, s);
  assert.equal(stepFile(repo, 1).suite, undefined);
  assert.equal(suite(repo, 'bash', '-c', SUITE_CMD).status, 1);
  const member = n => `Task ${n} spec: pass\nTask ${n} quality: approved\nTask ${n} scores: spec 17 / scope 18 / verification 16 / quality 16\n`;
  write(repo.ws, 'group-1,2-review-report.md', `## Verdict\n${member(1)}${member(2)}`);
  const verdict = step(repo, 'verdict', 'docs/plan.md', '1', '2', '--group');
  assert.equal(verdict.status, 0, verdict.err + verdict.out);
  assert.match(verdict.out, /^Important .*regression by earlier task/m);
  assert.doesNotMatch(verdict.out, /^Important .*old failure/m);
  assert.match(verdict.out, /^suite: red \(1 failing, 1 baseline\)$/m);
});

// ---------------------------------------------------------------- A4
test('A4: on a sequential plan with a none task check, an unscheduled task runs no suite and can complete', () => {
  const repo = stepRepo('a4', { tasks: 5 });
  // Tasks 1, 2 and 4 are neither a multiple of 3 nor the last of 5; their next scheduled task is 3, 3 and 5.
  for (const [n, next] of [[1, 3], [2, 3], [4, 5]]) {
    assert.equal(step(repo, 'start', 'docs/plan.md', String(n)).status, 0);
    work(repo);
    assert.equal(step(repo, 'review', 'docs/plan.md', String(n)).status, 0);
    passReport(repo, n);
    const verdict = step(repo, 'verdict', 'docs/plan.md', String(n));
    assert.equal(verdict.status, 0, `task ${n}: ${verdict.err}${verdict.out}`);
    assert.match(verdict.out, new RegExp(`^suite: not scheduled \\(next at Task ${next}\\)$`, 'm'), `task ${n}`);
    assert.doesNotMatch(verdict.out, /suite: not run/, `task ${n}`);
    assert.match(verdict.out, /^fix: none$/m, `task ${n}`);
    assert.equal(existsSync(join(repo.dir, '.dforge/suites.tsv')), false, 'no suite ran');
  }
});

// ---------------------------------------------------------------- A5
function suiteRows(repo) {
  const state = bash(DFORGE_PATH, ['state'], { cwd: repo.dir }).out.trim();
  return readFileSync(join(state, 'suites.tsv'), 'utf8').split('\n').filter(Boolean).map(line => line.split('\t'));
}
function suitesFile(repo) {
  return join(bash(DFORGE_PATH, ['state'], { cwd: repo.dir }).out.trim(), 'suites.tsv');
}

test('A5: suite-run writes a seventh column holding the duration in whole seconds', () => {
  const repo = stepRepo('a5');
  const result = suite(repo, 'bash', '-c', 'sleep 2');
  assert.equal(result.status, 0, result.out + result.err);
  assert.match(result.out, /^suite: pass \(exit 0\)$/m);
  const rows = suiteRows(repo);
  assert.equal(rows.length, 1);
  assert.equal(rows[0].length, 7);
  assert.equal(rows[0][0], repo.base);
  assert.equal(rows[0][1], 'clean');
  assert.equal(rows[0][3], '0');
  assert.match(rows[0][5], /^\d+$/);
  assert.match(rows[0][6], /^\d+$/);
  assert.ok(Number(rows[0][6]) >= 2 && Number(rows[0][6]) <= 30, `duration ${rows[0][6]}`);
});

test('A5: a six-column row still reuses a pass in suite-run', () => {
  const repo = stepRepo('a5-reuse');
  const marker = join(repo.dir, '..', `a5-runs-${counter}`);
  assert.equal(suite(repo, 'bash', '-c', `echo run >> '${marker}'`).status, 0);
  const file = suitesFile(repo);
  const six = suiteRows(repo).map(row => row.slice(0, 6).join('\t')).join('\n') + '\n';
  writeFileSync(file, six);
  const again = suite(repo, 'bash', '-c', `echo run >> '${marker}'`);
  assert.equal(again.status, 0, again.out + again.err);
  assert.match(again.out, /^suite: reused pass at [0-9a-f]{7} /m);
  assert.equal(readFileSync(marker, 'utf8'), 'run\n', 'the command ran only once');
});

test('A5: task-step verdict reads a six-column row as it reads a seven-column one', () => {
  const repo = stepRepo('a5-verdict', { failing: 'only failure\n' });
  assert.equal(step(repo, 'start', 'docs/plan.md', '1', '--suite', SUITE_CMD).status, 0);
  write(repo.dir, 'failing.txt', '');
  commit(repo.dir, 'fix');
  assert.equal(step(repo, 'review', 'docs/plan.md', '1').status, 0);
  assert.equal(suite(repo, 'bash', '-c', SUITE_CMD).status, 0);
  passReport(repo, 1);
  const seven = step(repo, 'verdict', 'docs/plan.md', '1');
  assert.equal(seven.status, 0, seven.out + seven.err);
  assert.match(seven.out, /^suite: pass \(clean\)$/m);
  const file = suitesFile(repo);
  writeFileSync(file, suiteRows(repo).map(row => row.slice(0, 6).join('\t')).join('\n') + '\n');
  const six = step(repo, 'verdict', 'docs/plan.md', '1');
  assert.equal(six.status, 0, six.out + six.err);
  assert.match(six.out, /^suite: pass \(clean\)$/m);
});

test('A5: task-step verdict reads a six-column failing row and its failing lines', () => {
  const repo = stepRepo('a5-red');
  assert.equal(step(repo, 'start', 'docs/plan.md', '1', '--suite', SUITE_CMD).status, 0);
  write(repo.dir, 'failing.txt', 'new breakage\n');
  commit(repo.dir, 'break');
  assert.equal(step(repo, 'review', 'docs/plan.md', '1').status, 0);
  assert.equal(suite(repo, 'bash', '-c', SUITE_CMD).status, 1);
  writeFileSync(suitesFile(repo), suiteRows(repo).map(row => row.slice(0, 6).join('\t')).join('\n') + '\n');
  passReport(repo, 1);
  const verdict = step(repo, 'verdict', 'docs/plan.md', '1');
  assert.equal(verdict.status, 0, verdict.out + verdict.err);
  assert.match(verdict.out, /^suite: red \(1 failing, 0 baseline\)$/m);
  assert.match(verdict.out, /^Important 1 .*new breakage/m);
});

// ---------------------------------------------------------------- A6
test('A6: the final review starts the integration check at the branch head through suite-run, and finishing reuses the pass', () => {
  const review = flat(P('reference/final-review.md'));
  assert.match(review, /start the plan header's `\*\*Integration check:\*\*` command through `bash <plugin-root>\/scripts\/suite-run -- bash -c '<integration check>'` as a background command at the same HEAD the Claude review reads/);
  assert.match(review, /finishing reuses a pass at the same commit/);
  const finishing = flat(P('skills/finishing-a-development-branch/SKILL.md'));
  assert.match(finishing, /A plan with an `\*\*Integration check:\*\*` line runs that command instead, as `bash <plugin-root>\/scripts\/suite-run -- bash -c '<integration check>'`/);
  assert.match(finishing, /reuses a recorded pass \(`suite: reused pass at <sha7>`\) only at the same HEAD, with a clean tree then and now, for the same command/);
});

test('A6: suite-run reuses a pass at the same commit on a clean tree, and runs again on a dirty one', () => {
  const repo = stepRepo('a6');
  const marker = join(repo.dir, '..', `a6-runs-${counter}`);
  const command = `echo run >> '${marker}'`;
  assert.match(suite(repo, 'bash', '-c', command).out, /^suite: pass \(exit 0\)$/m);
  const again = suite(repo, 'bash', '-c', command);
  assert.equal(again.status, 0);
  assert.match(again.out, /^suite: reused pass at [0-9a-f]{7} /m);
  assert.equal(readFileSync(marker, 'utf8'), 'run\n');
  write(repo.dir, 'dirty.txt', 'x\n');
  const dirty = suite(repo, 'bash', '-c', command);
  assert.match(dirty.out, /^suite: pass \(exit 0\)$/m);
  assert.equal(readFileSync(marker, 'utf8'), 'run\nrun\n');
  commit(repo.dir, 'next commit');
  assert.match(suite(repo, 'bash', '-c', command).out, /^suite: pass \(exit 0\)$/m);
  assert.equal(readFileSync(marker, 'utf8'), 'run\nrun\nrun\n');
});

// ---------------------------------------------------------------- A7
test('A7: writing-plans picks the full suite as the task check when its last passing run took 300 seconds or less', () => {
  assert.match(read(P('skills/writing-plans/SKILL.md')), /references\/task-check-line\.md/);
  const text = flat(P('skills/writing-plans/references/task-check-line.md'));
  assert.match(text, /the full suite itself, when its last passing run in `suites\.tsv` took 300 seconds or less/);
  assert.match(text, /Take the last matching row whose column 4 is `0`, and read its column 7, the duration in seconds/);
});

test('A7: writing-plans treats a missing duration as not fast', () => {
  const text = flat(P('skills/writing-plans/references/task-check-line.md'));
  assert.match(text, /A row that is missing, or has six columns and so no duration, counts as not fast/);
});

// ---------------------------------------------------------------- A8
const FAILING = 'Write the failing test';
const EXTEND = 'Extend the test `t/a.test.sh::first`';
const covered = n => `Covered by Task ${n}'s test \`first\``;

test('A8: plan-lint accepts the three Step 1 forms', () => {
  const { status, out } = lint(plan({ steps: [FAILING, EXTEND, covered(1)] }));
  assert.equal(status, 0, out);
  assert.match(out, /plan-lint: 0 errors, 0 warnings/);
});

test('A8: plan-lint fails a Covered by Task naming a missing task', () => {
  const { status, out } = lint(plan({ steps: [FAILING, EXTEND, covered(9)] }));
  assert.equal(status, 1, out);
  assert.match(out, /^ERROR Task 3: .*Covered by Task 9/m);
});

test('A8: plan-lint fails a Covered by Task naming a task with no test step of its own', () => {
  const noStep = lint(plan({ steps: [FAILING, undefined, covered(2)] }));
  assert.equal(noStep.status, 1, noStep.out);
  assert.match(noStep.out, /^ERROR Task 3: .*Covered by Task 2/m);
  const itself = lint(plan({ steps: [FAILING, covered(1), covered(2)] }));
  assert.equal(itself.status, 1, itself.out);
  assert.match(itself.out, /^ERROR Task 3: .*Covered by Task 2/m);
});

test('A8: plan-lint fails a Covered by Task naming a task that does not run before it in a sequential plan', () => {
  const later = lint(plan({ steps: [covered(2), FAILING, FAILING] }));
  assert.equal(later.status, 1, later.out);
  assert.match(later.out, /^ERROR Task 1: .*Covered by Task 2/m);
  const itself = lint(plan({ steps: [FAILING, covered(2), FAILING] }));
  assert.equal(itself.status, 1, itself.out);
  assert.match(itself.out, /^ERROR Task 2: .*Covered by Task 2/m);
});

test('A8: in a waves plan, a Covered by Task needs a task in an earlier wave', () => {
  const lines = [TASK_CHECK, INTEGRATION, '**CI:** none', REVIEW_LINE];
  const sameWave = lint(plan({ lines, waves: 'waves — 1 | 2-3', steps: [FAILING, EXTEND, covered(2)] }));
  assert.equal(sameWave.status, 1, sameWave.out);
  assert.match(sameWave.out, /^ERROR Task 3: .*Covered by Task 2/m);
  const earlier = lint(plan({ lines, waves: 'waves — 1 | 2 | 3', steps: [FAILING, EXTEND, covered(2)] }));
  assert.equal(earlier.status, 0, earlier.out);
  const firstWave = lint(plan({ lines, waves: 'waves — 1 | 2-3', steps: [FAILING, EXTEND, covered(1)] }));
  assert.equal(firstWave.status, 0, firstWave.out);
});

// ---------------------------------------------------------------- A9
test('A9: plan-review.md carries the Redundant test criterion under Executability, scored LOW, naming the overlapping test', () => {
  const executability = flatText(section(read(P('criteria/plan-review.md')), /^### Executability/));
  assert.match(executability, /Redundant test: score LOW when a planned test fails for no fault that an existing test or another planned test does not already catch/);
  assert.match(executability, /name the overlapping test/);
  const coherence = flatText(section(read(P('criteria/plan-review.md')), /^### Coherence/));
  assert.doesNotMatch(coherence, /Redundant test/);
});

// ---------------------------------------------------------------- A10
test('A10: the TDD skill replaces the Minimal row with the one-behaviour rule', () => {
  const skill = read(P('skills/test-driven-development/SKILL.md'));
  const table = section(skill, /^## Good Tests/);
  assert.doesNotMatch(table, /\*\*Minimal\*\*/);
  assert.match(flatText(table), /\*\*One behaviour\*\* \| Variants of one behaviour are rows of one parametrized or table-driven test; distinct behaviours get distinct tests\./);
});

test('A10: writing-good-tests.md asks whether an existing test already fails for the change', () => {
  const text = read(P('skills/test-driven-development/references/writing-good-tests.md'));
  const principle = flatText(section(text, /^## Principle 1/));
  const named = principle.indexOf('what production change should make this test fail');
  const asked = principle.indexOf('find whether an existing test already fails for it');
  assert.ok(named >= 0 && asked > named, 'the question follows the naming of the production change');
  assert.match(principle, /If one does, extend it, or write no test/);
});

// ---------------------------------------------------------------- A11
test('A11: the REFACTOR rule deletes only branch-added tests and never a regression test naming a fixed bug', () => {
  const refactor = flatText(section(read(P('skills/test-driven-development/SKILL.md')), /^### REFACTOR/));
  assert.match(refactor, /Delete a test written on this branch when a broader test written on this branch fails for every fault the narrower one catches/);
  assert.match(refactor, /The commit body names those faults/);
  assert.match(refactor, /covers only tests that do not exist at the branch's merge base/);
  assert.match(refactor, /never a regression test that names a fixed bug/);
  assert.match(refactor, /A test that predates the branch goes through dforge:test-simplifier/);
});

test('A11: the final-review fix wave deletes only branch-added tests and never a regression test naming a fixed bug', () => {
  const redundant = flatText(read(P('reference/final-review.md')).split('\n\n').find(block => block.startsWith('**Redundant tests.**')));
  assert.match(redundant, /The fix wave may delete only a test added on the branch, a test that does not exist at MERGE_BASE/);
  assert.match(redundant, /never a regression test that names a fixed bug/);
  assert.match(redundant, /a test that exists at MERGE_BASE is left for dforge:test-simplifier/);
});

// ---------------------------------------------------------------- A12
test('A12: the test-quality lens carries a {#redundant} criterion that names the covering test', () => {
  const lens = read(P('criteria/lenses/test-quality.md'));
  assert.match(lens, /^### .*\{#redundant\}$/m);
});

// ---------------------------------------------------------------- A13
test('A13: closing-a-milestone recommends a scoped test-simplifier run on 20% growth or a passed Budget', () => {
  const text = flat(P('skills/closing-a-milestone/SKILL.md'));
  const cost = text.slice(text.indexOf('8. **Suite cost.**'), text.indexOf('9. **Next.**'));
  assert.ok(cost.length > 0, 'step 8 is the suite cost audit');
  assert.match(cost, /grew by 20% or more/);
  assert.match(cost, /or passes a declared `Budget:`/);
  assert.match(cost, /`Budget: <seconds>s` line of the gate in `<docs>\/gates\.md` whose `Command` equals the plan's `\*\*Integration check:\*\*`/);
  assert.match(cost, /When no such gate exists, the audit uses the 20% rule only/);
  assert.match(cost, /`Next: dforge:test-simplifier --modules <paths>`/);
  assert.match(cost, /It recommends only and removes nothing/);
});

test('A13: closing-a-milestone names the checkout whose rows it read and recommends nothing with fewer than two rows', () => {
  const text = flat(P('skills/closing-a-milestone/SKILL.md'));
  const cost = text.slice(text.indexOf('8. **Suite cost.**'), text.indexOf('9. **Next.**'));
  assert.match(cost, /reads `suites\.tsv` from the state directory of the checkout it runs in/);
  assert.match(cost, /The audit names that checkout in the report/);
  assert.match(cost, /With fewer than two rows it says so and recommends nothing/);
  assert.match(cost, /Suite cost: <state>\/suites\.tsv of <checkout top level> holds <n> full-suite row\(s\) with a duration; two are needed, so nothing is recommended\./);
});

// ---------------------------------------------------------------- A14
test('A14: test-simplifier Phase 3 uses the tier names of reference/test-tiers.md', () => {
  const tiers = read(P('reference/test-tiers.md'));
  for (const name of ['Task check', 'Full suite', 'Sweep']) assert.match(tiers, new RegExp(`^\\| ${name} \\|`, 'm'));
  const phase3 = flatText(section(read(P('skills/test-simplifier/SKILL.md')), /^## Phase 3/));
  assert.match(phase3, /The tier names and the impact-selection table come from \[test-tiers\.md\]\(\.\.\/\.\.\/reference\/test-tiers\.md\)/);
  for (const name of ['Task check', 'Full suite', 'Sweep']) assert.match(phase3, new RegExp(`\\| ${name} \\|`));
  assert.match(phase3, /`Tier: task` and a `Why:`/);
  assert.match(phase3, /`Budget: <seconds>s` line/);
  const runners = read(P('skills/test-simplifier/references/runners.md'));
  assert.match(runners, /test-tiers\.md/);
});

test('A14: test-simplifier accepts --modules and --since scopes, lists Subsumed scaffolding and states the division of labour', () => {
  const skill = flat(P('skills/test-simplifier/SKILL.md'));
  assert.match(skill, /`--modules <paths>` limits the run to those paths/);
  assert.match(skill, /`--since <ref>` limits it to tests added after the ref/);
  assert.match(skill, /With a scope, Phase 1 still profiles the whole suite, and Phase 4 waves take candidates only from inside the scope/);
  assert.match(skill, /6\. \*\*Subsumed scaffolding\.\*\* A narrow test whose every fault a broader test of the same behaviour also catches/);
  assert.match(skill, /Tests added on the current branch are merged or removed by the REFACTOR step of dforge:test-driven-development and the `test-quality` lens of the final review\. This skill handles tests already on the default branch\./);
});

// ---------------------------------------------------------------- A15, A24
test('A15: plan-lint warns on a plan without a CI line and passes none', () => {
  const missing = lint(plan({ lines: [TASK_CHECK, INTEGRATION, REVIEW_LINE] }));
  assert.equal(missing.status, 0, missing.out);
  assert.match(missing.out, /^WARN header: .*CI/m);
  assert.doesNotMatch(missing.out, /^ERROR/m);
  const none = lint(plan({ lines: [TASK_CHECK, INTEGRATION, '**CI:** none', REVIEW_LINE] }));
  assert.equal(none.status, 0, none.out);
  assert.match(none.out, /plan-lint: 0 errors, 0 warnings/);
});

test('A15: plan-lint passes a well formed CI line and fails a malformed one', () => {
  const full = lint(plan({ lines: [TASK_CHECK, INTEGRATION, FULL_CI, REVIEW_LINE] }));
  assert.equal(full.status, 0, full.out);
  assert.match(full.out, /plan-lint: 0 errors, 0 warnings/);
  for (const bad of [
    'maybe',
    '`ci.yml` — platforms: linux — uncovered: none',
    '`ci.yml` — platforms: linux — local: `make test`',
    '`ci.yml` — platforms: linux — local: make test — uncovered: none',
    '`ci.yml` — local: `make test` — uncovered: none',
  ]) {
    const result = lint(plan({ lines: [TASK_CHECK, INTEGRATION, `**CI:** ${bad}`, REVIEW_LINE] }));
    assert.equal(result.status, 1, `${bad}\n${result.out}`);
    assert.match(result.out, /^ERROR header: .*CI/m, bad);
  }
});

const early = (point, options = {}) => lint(plan({ lines: [TASK_CHECK, INTEGRATION, FULL_CI, `**Early CI:** ${point}`, REVIEW_LINE], ...options }));

test('A24: plan-lint accepts a consented Early CI point on a sequential plan and on a waves plan', () => {
  const sequential = early('after task 2 — consented 2026-10-31');
  assert.equal(sequential.status, 0, sequential.out);
  assert.doesNotMatch(sequential.out, /Early CI/);
  const last = early('after task 3 — consented 2026-10-31');
  assert.equal(last.status, 0, last.out);
  const waves = early('after wave 2 — consented 2026-10-31', { waves: 'waves — 1 | 2-3' });
  assert.equal(waves.status, 0, waves.out);
  assert.doesNotMatch(waves.out, /Early CI/);
});

test('A24: plan-lint fails an Early CI line without a consented date', () => {
  for (const point of ['after task 2', 'after task 2 — consented', 'after task 2 — consented yesterday', 'after task 2 — consented 2026-13']) {
    const result = early(point);
    assert.equal(result.status, 1, `${point}\n${result.out}`);
    assert.match(result.out, /^ERROR header: .*Early CI/m, point);
  }
});

test('A24: plan-lint fails an Early CI line naming a wave on a sequential plan', () => {
  const result = early('after wave 1 — consented 2026-10-31');
  assert.equal(result.status, 1, result.out);
  assert.match(result.out, /^ERROR header: .*Early CI.*wave/m);
});

test('A24: plan-lint fails an Early CI line naming a task past the last', () => {
  const result = early('after task 4 — consented 2026-10-31');
  assert.equal(result.status, 1, result.out);
  assert.match(result.out, /^ERROR header: .*Early CI/m);
  assert.match(result.out, /Task 4/);
});

// ---------------------------------------------------------------- ci-mirror
function mirrorRepo(name, ciLine) {
  const dir = makeRepo(name);
  write(dir, 'a.sh', 'echo a >> "$RUNS"\n');
  write(dir, 'b.sh', 'echo b >> "$RUNS"\n');
  write(dir, 'bad.sh', 'echo bad >> "$RUNS"\nexit 3\n');
  write(dir, 'docs/plan.md', plan({ lines: [TASK_CHECK, INTEGRATION, ciLine, REVIEW_LINE] }));
  commit(dir, 'docs: add fixture');
  return dir;
}
const mirror = (dir, env = {}) => bash(CI_MIRROR, ['docs/plan.md'], { cwd: dir, env });
const ciLine = (locals, uncovered) => `**CI:** \`.github/workflows/x.yml\` — platforms: ubuntu-latest, windows-latest — local: ${locals.map(c => `\`${c}\``).join('; ')} — uncovered: ${uncovered}`;

test('A16: ci-mirror runs every local command through suite-run and prints uncovered', () => {
  const dir = mirrorRepo('a16', ciLine(['bash a.sh', 'bash b.sh'], 'Windows Git Bash, macOS'));
  const runs = join(dir, '..', `a16-runs-${counter}`);
  const result = mirror(dir, { RUNS: runs });
  assert.equal(result.status, 0, result.out + result.err);
  assert.equal(readFileSync(runs, 'utf8'), 'a\nb\n');
  const lines = result.out.trim().split('\n');
  assert.equal(lines.length, 3, result.out);
  assert.match(lines[0], /bash a\.sh/);
  assert.match(lines[1], /bash b\.sh/);
  assert.equal(lines[2], 'uncovered: Windows Git Bash, macOS');
  const rows = suiteRows({ dir });
  assert.deepEqual(rows.map(row => row[2]).sort(), ['bash -c bash\\ a.sh', 'bash -c bash\\ b.sh']);
  assert.ok(rows.every(row => row[3] === '0' && row[1] === 'clean'));
  const again = mirror(dir, { RUNS: runs });
  assert.equal(again.status, 0, again.out + again.err);
  assert.match(again.out, /reused pass/);
  assert.equal(readFileSync(runs, 'utf8'), 'a\nb\n', 'a pass at the same commit is not run again');
});

test('A16: ci-mirror exits non-zero when one command fails, naming it, and still runs the others', () => {
  const dir = mirrorRepo('a16-fail', ciLine(['bash a.sh', 'bash bad.sh', 'bash b.sh'], 'none'));
  const runs = join(dir, '..', `a16-fail-runs-${counter}`);
  const result = mirror(dir, { RUNS: runs });
  assert.notEqual(result.status, 0, result.out);
  const failing = result.out.split('\n').filter(line => /bash bad\.sh/.test(line));
  assert.equal(failing.length, 1, result.out);
  assert.match(failing[0], /FAIL/);
  assert.equal(readFileSync(runs, 'utf8'), 'a\nbad\nb\n');
  assert.match(result.out, /^uncovered: none$/m);
});

test('A16: ci-mirror prints ci: none and exits 0 for a none CI line', () => {
  const dir = mirrorRepo('a16-none', '**CI:** none');
  const result = mirror(dir);
  assert.equal(result.status, 0, result.out + result.err);
  assert.equal(result.out.trim(), 'ci: none');
  assert.equal(existsSync(join(dir, '.dforge/suites.tsv')), false);
});

// ---------------------------------------------------------------- A26
test('A26: ci-mirror prints the digest line naming a command that cannot launch and exits non-zero', () => {
  const dir = mirrorRepo('a26', ciLine(['/nonexistent/launcher --flag'], 'none'));
  const result = mirror(dir);
  assert.notEqual(result.status, 0, result.out);
  const naming = result.out.split('\n').filter(line => line.includes('/nonexistent/launcher --flag'));
  assert.equal(naming.length, 1, result.out);
  assert.match(naming[0], /FAIL/);
});

test('A26: finishing prints one line and skips the wait when gh is absent or not logged in, never calling the branch done', () => {
  const text = flat(P('skills/finishing-a-development-branch/references/execute-choice.md'));
  assert.match(text, /With keep, no `gh` \(`command -v gh` fails\), `gh` not logged in \(`gh auth status` exits non-zero\), or a CI line of `none`, print why in one line and skip the wait; never call the branch CI-green/);
  const wait = section(read(P('skills/finishing-a-development-branch/references/execute-choice.md')), /^### Wait for CI/);
  assert.ok(wait.includes('skip the wait'), 'the skip lives in the Wait for CI section');
});

// ---------------------------------------------------------------- A17
test('A17: with no Early CI line nothing in the controller pushes the branch or starts CI before finishing', () => {
  const delegated = read(P('reference/delegated-task.md'));
  const early = flatText(section(delegated, /^## Early CI/));
  assert.match(early, /With no `\*\*Early CI:\*\*` line in the plan header, nothing in this loop pushes the branch or starts CI before finishing/);
  assert.match(early, /Push only when the line carries `— consented <YYYY-MM-DD>`/);
  const controllerFiles = [
    'reference/delegated-task.md', 'reference/parallel-waves.md', 'reference/final-review.md', 'reference/executor-lane.md',
    'skills/subagent-driven-development/SKILL.md', 'skills/executing-plans/SKILL.md', 'skills/resume-execution/SKILL.md',
    ...readdirSync(join(PLUGIN, 'skills/subagent-driven-development/references')).map(name => `skills/subagent-driven-development/references/${name}`),
  ];
  for (const file of controllerFiles) {
    const text = read(P(file));
    const outside = file === 'reference/delegated-task.md' ? text.replace(section(text, /^## Early CI/), '') : text;
    const pushes = outside.split('\n').filter(line => /git push|gh workflow run/.test(line) && !/never|do not|don't/i.test(line));
    assert.deepEqual(pushes, [], `${file} pushes or starts CI outside the Early CI section`);
  }
});

test('A17: with an Early CI line the controller never opens a pull request to start CI', () => {
  const early = flatText(section(read(P('reference/delegated-task.md')), /^## Early CI/));
  assert.match(early, /Never open a pull request to start CI/);
  assert.doesNotMatch(early, /gh pr create/);
});

test('A17: auto-run.md names the consented early-CI push and dispatch as the second exception to its never-performed list', () => {
  const autoRun = read(P('reference/auto-run.md'));
  const paragraph = flatText(autoRun.split('\n\n').find(block => block.startsWith('**Never performed in an auto run,**')));
  assert.match(paragraph, /The finish action is the first exception\. The second is the `\*\*Early CI:\*\*` push and workflow dispatch, performed only when the header line carries `— consented <YYYY-MM-DD>`/);
});

// ---------------------------------------------------------------- A18
test('A18: finishing waits for the CI run of the pushed commit, bounded at 90 minutes, and records the CI ledger line', () => {
  const choice = read(P('skills/finishing-a-development-branch/references/execute-choice.md'));
  const pr = flatText(section(choice, /^### Option 2/));
  assert.match(pr, /Then wait for CI as `### Wait for CI` says, with `sha` being `git rev-parse HEAD` at the push/);
  const wait = flatText(section(choice, /^### Wait for CI/));
  assert.match(wait, /Finishing waits for CI only when it pushed: Option 2, or an Early CI push whose head is the final head/);
  assert.match(wait, /Run `gh run list --commit <sha>`, then `gh run watch <id>` as a background Bash command/);
  assert.match(wait, /Set the call's `timeout` to \(90 × 60 \+ 120\) × 1000 ms/);
  assert.match(wait, /Record `CI: <sha7> run <id> <green\|red\|still running at 90 min>` on the ledger/);
  assert.match(flat(P('skills/finishing-a-development-branch/SKILL.md')), /When the ledger holds a `CI:` line, the final message quotes it/);
});

test('A18: finishing never reports the branch done while the CI run is red or still running', () => {
  const wait = flatText(section(read(P('skills/finishing-a-development-branch/references/execute-choice.md')), /^### Wait for CI/));
  assert.match(wait, /Green completes the branch/);
  assert.match(wait, /Red reopens the branch through dforge:systematic-debugging, naming each failed job and step; push the fix and wait again/);
  assert.match(wait, /A run still going after 90 minutes is reported as not done, never as done/);
});

// ---------------------------------------------------------------- A19
test('A19: writing-plans copies the pitfalls-table rows of each uncovered platform into Global Constraints', () => {
  assert.match(read(P('skills/writing-plans/SKILL.md')), /references\/ci-line\.md/);
  const text = flat(P('skills/writing-plans/references/ci-line.md'));
  assert.match(text, /For every uncovered platform, copy that platform's rows of the Pitfalls table in \[ci-parity\.md\]\(\.\.\/\.\.\/\.\.\/reference\/ci-parity\.md\) into `## Global Constraints`, one line per row, so every task brief carries them/);
  const pitfalls = section(read(P('reference/ci-parity.md')), /^## Pitfalls/);
  const platforms = new Set(pitfalls.split('\n').filter(line => line.startsWith('| ') && !line.startsWith('| Platform') && !line.startsWith('|---')).map(line => line.split('|')[1].trim()));
  assert.deepEqual([...platforms].sort(), ['Windows Git Bash', 'macOS', 'uutils (ubuntu-latest)'].sort());
});

// ---------------------------------------------------------------- A20
const lintRoot = scratch('portability');
function portabilityFixture(name, files) {
  const root = join(lintRoot, name);
  for (const [path, text] of Object.entries(files)) write(root, path, text);
  return root;
}
const portability = root => sh(process.execPath, [join(REPO, 'scripts/lint-portability.mjs'), root]);
const EX_SH = ' # portability: ok — fixture reason';
const EX_JS = ' // portability: ok — fixture reason';
const RULES = [
  { name: 'git -C with $PWD or $(pwd)', path: 'scripts/git-c.sh', exempt: EX_SH, lines: ['git -C "$PWD" status', 'git -C "$(pwd)" log'], clean: ['git -C "$(dr_native_path "$PWD")" status'] },
  { name: 'awk -v with a backslash', path: 'plugins/p/scripts/awk-v.sh', exempt: EX_SH, lines: ["awk -v pat='a\\.b' '$0 ~ pat' file"], clean: ["awk -v n=3 '{ print n }' file", "awk '$0 ~ ENVIRON[\"PAT\"]' file"] },
  { name: 'a dynamic import() of a path variable', path: 'plugins/p/tests/import.mjs', exempt: EX_JS, lines: ['const mod = await import(file);'], clean: ['const mod = await import(pathToFileURL(file).href);'] },
  { name: 'jq given a $PWD file under MSYS_NO_PATHCONV', path: 'plugins/p/scripts/jq.sh', exempt: EX_SH, prefix: ['export MSYS_NO_PATHCONV=1'], lines: ['jq . "$PWD/data.json"', 'jq -r .name "$TMPDIR/x.json"'], clean: ['jq . < "$PWD/data.json"'] },
];

test('A20: lint-portability.mjs flags each of its four rules on a fixture line as file:line rule message', () => {
  for (const rule of RULES) {
    const prefix = rule.prefix ?? [];
    const root = portabilityFixture(`flag-${counter++}`, { [rule.path]: [...prefix, ...rule.lines].join('\n') + '\n' });
    const result = portability(root);
    assert.equal(result.status, 1, `${rule.name}\n${result.out}${result.err}`);
    const hits = result.out.trim().split('\n');
    assert.equal(hits.length, rule.lines.length, `${rule.name}\n${result.out}`);
    hits.forEach((hit, i) => assert.match(hit, new RegExp(`^${rule.path.replace(/\./g, '\\.')}:${prefix.length + i + 1} \\S+ \\S`), `${rule.name}: ${hit}`));
  }
});

test('A20: lint-portability.mjs passes the same lines when they carry the exemption comment', () => {
  for (const rule of RULES) {
    const prefix = rule.prefix ?? [];
    const root = portabilityFixture(`exempt-${counter++}`, { [rule.path]: [...prefix, ...rule.lines.map(line => line + rule.exempt)].join('\n') + '\n' });
    const result = portability(root);
    assert.equal(result.status, 0, `${rule.name}\n${result.out}${result.err}`);
    assert.equal(result.out.trim(), '', rule.name);
  }
});

test('A20: lint-portability.mjs passes the safe forms of each rule', () => {
  for (const rule of RULES) {
    const prefix = rule.prefix ?? [];
    const root = portabilityFixture(`clean-${counter++}`, { [rule.path]: [...prefix, ...rule.clean].join('\n') + '\n' });
    const result = portability(root);
    assert.equal(result.status, 0, `${rule.name}\n${result.out}${result.err}`);
  }
});

test('A20: validate-repository.mjs runs the lint and fails on a hit', () => {
  const dirty = portabilityFixture(`validate-${counter++}`, { 'plugins/p/tests/x.sh': 'git -C "$PWD" status\n' });
  const hit = sh(process.execPath, [join(REPO, 'scripts/validate-repository.mjs'), dirty]);
  assert.notEqual(hit.status, 0);
  assert.match(hit.out + hit.err, /^plugins\/p\/tests\/x\.sh:1 \S+ /m);
  const exempt = portabilityFixture(`validate-${counter++}`, { 'plugins/p/tests/x.sh': `git -C "$PWD" status${EX_SH}\n` });
  const clean = sh(process.execPath, [join(REPO, 'scripts/validate-repository.mjs'), exempt]);
  assert.doesNotMatch(clean.out + clean.err, /plugins\/p\/tests\/x\.sh:1 /);
});

test('A20: the repository itself passes its portability lint over plugins and scripts', () => {
  const result = sh(process.execPath, [join(REPO, 'scripts/lint-portability.mjs'), REPO]);
  assert.equal(result.status, 0, result.out);
  assert.equal(result.out.trim(), '');
});

// ---------------------------------------------------------------- A21
function shardTree() {
  const root = scratch('shards');
  for (const dir of ['scripts', 'tests', 'plugins/dforge/tests', 'plugins/dr-status/tests', 'evals/tiers/tests', 'evals/controller/tests']) {
    cpSync(join(REPO, dir), join(root, dir), { recursive: true });
  }
  return root;
}
const shardTest = root => sh(process.execPath, ['--test', 'tests/test-shards.test.mjs'], { cwd: root, timeout: 180000 });

test('A21: test-shards.test.mjs passes on the repository weights', () => {
  const result = shardTest(REPO);
  assert.equal(result.status, 0, result.out + result.err);
});

test('A21: test-shards.test.mjs fails for a shell suite with no weight, naming it, and not for the other jobs', () => {
  const root = shardTree();
  write(root, 'plugins/dforge/tests/zz-unweighted.test.sh', 'exit 0\n');
  const result = shardTest(root);
  assert.notEqual(result.status, 0, result.out);
  const output = result.out + result.err;
  assert.match(output, /zz-unweighted\.test\.sh/);
  for (const other of ['validate-repository', 'tsc', 'claude', 'tests/', 'evals/']) {
    const complaint = output.split('\n').filter(line => /no weight|80%|suiteSeconds/.test(line) && line.includes(other));
    assert.deepEqual(complaint, [], `${other} is flagged`);
  }
});

test('A21: test-shards.test.mjs fails for a weight above 80% of its limit', () => {
  const root = shardTree();
  const file = join(root, 'scripts/test-shards.mjs');
  const source = readFileSync(file, 'utf8');
  const changed = source.replace(/'suite-run\.test\.sh': \d+/, "'suite-run.test.sh': 5000");
  assert.notEqual(changed, source, 'the fixture changes a weight');
  writeFileSync(file, changed);
  const result = shardTest(root);
  assert.notEqual(result.status, 0, result.out);
  const output = result.out + result.err;
  assert.match(output, /suite-run\.test\.sh/);
  assert.match(output, /raise its suiteSeconds or split it/);
});

// ---------------------------------------------------------------- A22
test('A22: test-all.mjs prints a ::warning:: naming a suite whose duration passes 75% of its limit', () => {
  const root = scratch('drift');
  cpSync(join(REPO, 'scripts/test-all.mjs'), join(root, 'scripts/test-all.mjs'));
  cpSync(join(REPO, 'scripts/test-shards.mjs'), join(root, 'scripts/test-shards.mjs'));
  // validate-repository.mjs is the job with the shortest limit (60 s); the stub
  // takes 46 s, past 75% of it, while every other job finishes at once.
  write(root, 'scripts/validate-repository.mjs', 'await new Promise(resolve => setTimeout(resolve, 46000));\n');
  write(root, 'tests/quick.test.mjs', "import test from 'node:test';\ntest('quick', () => {});\n");
  write(root, 'evals/tiers/tests/quick.test.mjs', "import test from 'node:test';\ntest('quick', () => {});\n");
  write(root, 'evals/controller/tests/quick.test.mjs', "import test from 'node:test';\ntest('quick', () => {});\n");
  write(root, 'plugins/dr-status/tests/run-all.sh', 'exit 0\n');
  write(root, 'plugins/dforge/tests/quick.test.sh', 'exit 0\n');
  const path = `${dirname(process.execPath)}:/usr/bin:/bin`;
  const result = sh(process.execPath, ['scripts/test-all.mjs'], { cwd: root, env: { PATH: path }, timeout: 200000 });
  assert.equal(result.status, 0, result.out + result.err);
  const warnings = result.out.split('\n').filter(line => line.includes('::warning::'));
  assert.equal(warnings.length, 1, result.out);
  assert.match(warnings[0], /^::warning::/);
  assert.ok(warnings[0].includes('scripts/validate-repository.mjs'), warnings[0]);
  assert.ok(warnings[0].includes('60'), warnings[0]);
});

// ---------------------------------------------------------------- A23, A25
test('A23: a gates.md with no Tier field runs exactly the gates it ran before', () => {
  const skill = read(P('skills/running-gates/SKILL.md'));
  const text = flatText(skill);
  assert.match(text, /Required: \*\*`Command`\*\* and \*\*`Green`\*\* \(what output or observation proves it\)\./);
  assert.match(text, /\*\*`Tier`:\*\* `task`, `branch` or `sweep`\. Absent means `branch`, so a manifest written before the field means what it meant before/);
  assert.match(text, /this skill runs `task` and `branch` gates alike, in manifest order/);
  assert.match(text, /A `task` or `branch` gate, or a gate with no `Tier`, is selected by `Applies` exactly as before/);
  assert.doesNotMatch(text, /Required: [^.]*Tier/);
});

test('A25: running-gates prints one line per skipped sweep gate naming it as CI\'s and still runs task and branch gates', () => {
  const skill = flatText(read(P('skills/running-gates/SKILL.md')));
  assert.match(skill, /A `sweep` gate belongs to CI: this skill skips it and prints `gate <n> \(<title>\): skipped — Tier sweep runs in CI`/);
  assert.match(skill, /A `sweep` gate is not selected; print the one line from the `Tier` bullet for it, so its absence is not a silent skip/);
  assert.match(skill, /this skill runs `task` and `branch` gates alike/);
});

// ---------------------------------------------------------------- A27
test('A27: after a local merge finishing prints the gh run list and gh run watch lines and never calls the branch CI-green', () => {
  const choice = read(P('skills/finishing-a-development-branch/references/execute-choice.md'));
  const merge = flatText(section(choice, /^### Option 1/));
  assert.match(merge, /After a local merge, nothing was pushed, so do not wait: print `gh run list --commit <merge sha>` and `gh run watch <id>` for your human partner to run after pushing, and never call the branch CI-green/);
  assert.doesNotMatch(merge, /wait for CI as/i);
});
