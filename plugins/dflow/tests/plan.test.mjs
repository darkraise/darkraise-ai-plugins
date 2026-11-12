import assert from 'node:assert/strict';
import test from 'node:test';
import { appendLog, blockedTasks, lintPlan, nextTask, parsePlan, setField, setVerify, taskStates, tickTask } from '../lib/plan.mjs';
import { matchesPath } from '../lib/util.mjs';
import { PLAN } from './helpers.mjs';

test('a plan parses to fields, acceptance, tasks, steps and verify commands', () => {
  const plan = parsePlan(PLAN.replace('- A1:', '- A2 UI visual: the meter turns red\n- A1:'));
  assert.equal(plan.title, 'Rate-limit meter');
  assert.equal(plan.fields.board, '1');
  assert.equal(plan.fields.branch, 'feat/x');
  assert.deepEqual(plan.docs, []);
  assert.deepEqual(plan.acceptance.map(line => [line.id, line.ui, line.visual, line.commands]), [['A2', true, true, []], ['A1', false, false, ['node check.mjs']]]);
  assert.deepEqual(plan.tasks.map(task => [task.number, task.title, task.files, task.after, task.verify]), [
    [1, 'Parse the header', ['src/limit.mjs', 'tests/'], [], ['node verify1.mjs']],
    [2, 'Draw the meter', ['src/meter.mjs'], [1], ['node verify2.mjs']],
  ]);
  assert.equal(plan.tasks[0].steps.length, 3);
});

test('fenced text is not read as tasks, steps or fields', () => {
  const plan = parsePlan(PLAN.replace('## Log', '```md\n### Task 9: fake\n- [ ] Verify: `rm -rf /`\n```\n\n## Log'));
  assert.deepEqual(plan.tasks.map(task => task.number), [1, 2]);
  assert.deepEqual(plan.tasks[1].verify, ['node verify2.mjs']);
});

test('lint names each missing part', () => {
  const broken = PLAN.replace('**Goal:** Show the remaining rate limit.', '**Goal:** …')
    .replace('- [ ] Verify: `node verify2.mjs`', '- [ ] check it by hand')
    .replace('**After:** 1', '**After:** 7')
    .replace('**Docs:** none — the fixture has no living docs', '**Docs:** none');
  const { errors } = lintPlan(parsePlan(broken));
  assert.deepEqual(errors, [
    'Goal is empty',
    'Docs is `none` without a reason: write `none — <reason>`',
    'Task 2 has no `Verify:` step with a command in backticks',
    'Task 2 comes after Task 7, which does not exist',
  ]);
  assert.deepEqual(lintPlan(parsePlan(PLAN)).errors, []);
});

test('a UI acceptance line requires a UI section', () => {
  const plan = parsePlan(PLAN.replace('- A1:', '- A2 UI: the meter turns red\n- A1:'));
  assert.ok(lintPlan(plan).errors.includes('a UI acceptance line needs a `## UI` section'));
});

test('task state follows ticks, the log and the dependency order', () => {
  let text = appendLog(PLAN, { date: '2026-11-12', task: 1, kind: 'B', message: 'no API key' });
  let tasks = taskStates(parsePlan(text), {});
  assert.deepEqual(tasks.map(task => task.state), ['blocked', 'todo']);
  assert.equal(nextTask(tasks), null);
  assert.equal(blockedTasks(parsePlan(text)).get(1), 'no API key');

  text = appendLog(text, { date: '2026-11-13', task: 1, kind: 'U', message: 'key issued' });
  tasks = taskStates(parsePlan(text), { tasks: { 1: { state: 'wip', attempts: 2 } } });
  assert.deepEqual(tasks.map(task => [task.state, task.ready]), [['wip', true], ['todo', false]]);

  tasks = taskStates(parsePlan(tickTask(text, 1)), {});
  assert.deepEqual(tasks.map(task => task.state), ['done', 'todo']);
  assert.equal(nextTask(tasks).number, 2);
});

test('edits change only their own lines', () => {
  const ticked = tickTask(PLAN, 2);
  assert.equal(ticked.split('\n').filter((line, index) => line !== PLAN.split('\n')[index]).length, 2);
  const approved = setField(PLAN, 'Approved', '2026-11-12');
  assert.equal(parsePlan(approved).fields.approved, '2026-11-12');
  assert.equal(parsePlan(setField(approved, 'Approved', '2026-11-13')).fields.approved, '2026-11-13');
  const amended = parsePlan(setVerify(PLAN, 1, ['node a.mjs', 'node b.mjs']));
  assert.deepEqual(amended.tasks[0].verify, ['node a.mjs', 'node b.mjs']);
  assert.deepEqual(amended.tasks[1].verify, ['node verify2.mjs']);
  const logged = parsePlan(appendLog(appendLog(PLAN, { date: '2026-11-12', task: null, kind: 'D', message: 'one' }), { date: '2026-11-12', task: 2, kind: 'G', message: 'two' }));
  assert.deepEqual(logged.log.map(entry => [entry.task, entry.kind, entry.text]), [[null, 'D', 'one'], [2, 'G', 'two']]);
});

test('file patterns match paths, directories and globs', () => {
  assert.ok(matchesPath('src/limit.mjs', 'src/limit.mjs'));
  assert.ok(matchesPath('tests/', 'tests/a/b.test.mjs'));
  assert.ok(matchesPath('src', 'src/a.mjs'));
  assert.ok(matchesPath('**/*.test.*', 'pkg/x/a.test.ts'));
  assert.ok(matchesPath('**/tests/', 'pkg/tests/a.py'));
  assert.ok(matchesPath('*.md', 'README.md'));
  assert.ok(!matchesPath('*.md', 'docs/README.md'));
  assert.ok(!matchesPath('src/limit.mjs', 'src/limit.mjs.bak'));
});

test('a heading at the task level that is not a task ends the task', () => {
  const plan = parsePlan(PLAN.replace('## Log', '### Rollout checklist\n- [ ] announce it\n**Files:** elsewhere\n\n## Log'));
  assert.equal(plan.tasks[1].steps.length, 2);
  assert.deepEqual(plan.tasks[1].files, ['src/meter.mjs']);
  assert.equal(tickTask(PLAN.replace('## Log', '### Rollout checklist\n- [ ] announce it\n\n## Log'), 2).includes('- [ ] announce it'), true);
});

test('a verify step can be added to a task that has none', () => {
  const bare = PLAN.replace('- [ ] Verify: `node verify2.mjs`\n', '');
  assert.deepEqual(parsePlan(setVerify(bare, 2, ['node v.mjs'])).tasks[1].verify, ['node v.mjs']);
  assert.deepEqual(parsePlan(setVerify(bare, 2, ['node v.mjs'])).tasks[0].verify, ['node verify1.mjs']);
});
