import assert from 'node:assert/strict';
import test from 'node:test';
import { PLAN, dflow, git, makeProject, read, write } from './helpers.mjs';

function build(root, { sourceLines = 30, testLines = 10 } = {}) {
  write(root, 'verify1.mjs', '\n');
  write(root, 'verify2.mjs', '\n');
  write(root, 'src/limit.mjs', `${Array.from({ length: sourceLines }, (_, index) => `export const a${index} = ${index};`).join('\n')}\n`);
  write(root, 'tests/limit.test.mjs', `${Array.from({ length: testLines }, (_, index) => `assert.equal(a${index}, ${index});`).join('\n')}\n`);
  git(root, 'add', 'src', 'tests');
  assert.equal(dflow(root, ['done', '1', '-m', 'feat: parse']).status, 0);
  write(root, 'src/meter.mjs', 'export const drawMeter = () => "";\n');
  git(root, 'add', 'src');
  assert.equal(dflow(root, ['done', '2', '-m', 'feat: draw']).status, 0);
}

const pack = (root, ...args) => JSON.parse(dflow(root, ['review', 'pack', '--json', ...args]).stdout);

test('the tier follows diff size and risk', t => {
  const small = makeProject(t);
  build(small, { sourceLines: 5, testLines: 2 });
  assert.equal(pack(small).tier, 0);

  const normal = makeProject(t);
  build(normal);
  assert.deepEqual([pack(normal).tier, pack(normal).lines], [1, 41]);

  const risky = makeProject(t, { plan: PLAN.replace('**Risk:** none', '**Risk:** security') });
  build(risky, { sourceLines: 5, testLines: 2 });
  assert.equal(pack(risky).tier, 2);
  assert.match(dflow(risky, ['review', 'record', '--tier', '1']).stderr, /needs a tier 2 review/);
});

test('the pack lists the mechanical facts', t => {
  const root = makeProject(t);
  write(root, 'verify1.mjs', '\n');
  write(root, 'verify2.mjs', '\n');
  write(root, 'src/limit.mjs', 'export const a = 1; // TODO tidy\n');
  write(root, 'tests/limit.test.mjs', `${Array.from({ length: 9 }, () => 'assert.ok(true);').join('\n')}\n`);
  write(root, 'config.mjs', 'export default {};\n');
  git(root, 'add', 'src', 'tests', 'config.mjs');
  dflow(root, ['done', '1', '-m', 'feat: parse', '--extra', 'the parser reads it']);
  dflow(root, ['amend', '2', '--verify', 'node verify2.mjs --all', '--reason', 'the flag is required']);
  write(root, 'src/meter.mjs', '1\n');
  write(root, 'tests/limit.test.mjs', 'assert.ok(true);\n');
  git(root, 'add', 'src', 'tests');
  dflow(root, ['done', '2', '-m', 'feat: draw', '--extra', 'test trimmed', '--weaken', 'eight duplicates removed']);

  const { facts } = pack(root);
  assert.deepEqual(facts.outsidePlan, ['config.mjs']);
  assert.deepEqual(facts.amendedVerify.map(entry => [entry.task, entry.logged]), [[2, true]]);
  assert.equal(facts.todos, 1);
  assert.deepEqual(facts.deviations.map(entry => entry.kind), ['X', 'V', 'X', 'W']);
  assert.deepEqual([facts.tests.testLines, facts.tests.sourceLines, facts.tests.newTestFiles, facts.tests.overBudget], [1, 3, 1, false]);

  const printed = dflow(root, ['review', 'pack']);
  assert.match(printed.stdout, /Changed outside every task's Files: config\.mjs/);
  assert.match(printed.stdout, /Pack: \.dflow\/review\/2026-11-12-meter\/pack\.md/);
  const written = read(root, '.dflow/review/2026-11-12-meter/pack.md');
  assert.match(written, /## Design\n- D1: a parser function/);
  assert.match(written, /- A1: `node check\.mjs` passes/);

  const taskPack = pack(root, '--task', '1');
  assert.deepEqual(taskPack.files.map(entry => entry.file).sort(), ['config.mjs', 'src/limit.mjs', 'tests/limit.test.mjs']);
});

test('more test lines than twice the source is reported as over budget', t => {
  const root = makeProject(t);
  build(root, { sourceLines: 4, testLines: 30 });
  assert.equal(pack(root).facts.tests.overBudget, true);
  assert.match(dflow(root, ['review', 'pack']).stdout, /OVER the test budget/);
});

test('add validates a finding and a quote must be in the file', t => {
  const root = makeProject(t);
  build(root);
  const base = ['review', 'add', '--file', 'src/meter.mjs', '--line', '1', '--severity', 'blocking', '--claim', 'drawMeter ignores its input', '--breaks', 'the meter is always empty'];
  assert.match(dflow(root, base).stderr, /exactly one piece of evidence/);
  assert.match(dflow(root, [...base, '--quote', 'not in the file']).stderr, /quoted text is not within five lines/);
  assert.match(dflow(root, [...base.slice(0, 3), 'src/none.mjs', ...base.slice(4), '--cmd', 'false']).stderr, /does not exist/);
  assert.match(dflow(root, [...base, '--quote', 'drawMeter = () => ""']).stdout, /^F1 recorded \(blocking, quote evidence\)/);
  assert.match(dflow(root, [...base, '--cmd', 'node probe.mjs']).stdout, /^F2 recorded/);
  const status = JSON.parse(dflow(root, ['status', '--json']).stdout);
  assert.deepEqual([status.review.open, status.review.blocking], [2, 2]);
  assert.match(status.next, /fix 2 blocking finding/);
});

test('verify proves a command finding while it fails and marks it fixed once it passes', t => {
  const root = makeProject(t);
  build(root);
  const add = (...evidence) => dflow(root, ['review', 'add', '--file', 'src/meter.mjs', '--line', '1', '--severity', 'blocking', '--claim', 'c', '--breaks', 'b', ...evidence]);
  write(root, 'probe.mjs', 'process.exit(1)\n');
  add('--cmd', 'node probe.mjs');
  add('--cmd', 'node -e 0');
  add('--quote', 'drawMeter = () => ""');

  let verified = dflow(root, ['review', 'verify']);
  assert.match(verified.stdout, /^F1 blocking reproduced/m);
  assert.match(verified.stdout, /^F2 blocking unproven/m);
  assert.match(verified.stdout, /^F3 blocking reproduced/m);
  assert.match(verified.stdout, /2 open \(2 blocking\); fix the 2 with reproduced evidence/);

  write(root, 'probe.mjs', 'process.exit(0)\n');
  write(root, 'src/meter.mjs', 'export const drawMeter = value => String(value);\n');
  verified = dflow(root, ['review', 'verify']);
  assert.match(verified.stdout, /^F1 blocking fixed/m);
  assert.match(verified.stdout, /1 open \(1 blocking\)/);
  assert.match(dflow(root, ['review', 'list']).stdout, /quoted text is no longer at that place/);
  assert.match(dflow(root, ['review', 'resolve', 'F3', 'declined']).stderr, /needs a note/);
  assert.equal(dflow(root, ['review', 'resolve', 'F3', 'fixed']).status, 0);
  assert.match(dflow(root, ['review', 'list']).stdout, /No open findings/);
  assert.equal(dflow(root, ['review', 'list', '--all']).stdout.match(/^F\d/gm).length, 3);
});

test('judge refutes a finding and record stores the review at the head', t => {
  const root = makeProject(t);
  build(root);
  dflow(root, ['review', 'add', '--file', 'src/meter.mjs', '--line', '1', '--severity', 'should', '--claim', 'c', '--breaks', 'b', '--cmd', 'false', '--lens', 'correctness']);
  assert.equal(dflow(root, ['review', 'judge', 'F1', 'refuted', 'the caller never passes a value']).status, 0);
  assert.equal(dflow(root, ['review', 'record', '--tier', '1']).status, 0);
  const status = JSON.parse(dflow(root, ['status', '--json']).stdout);
  assert.deepEqual([status.review.recorded.tier, status.review.recorded.sha, status.review.open], [1, git(root, 'rev-parse', 'HEAD'), 0]);
});

test('a task with a risk waits in review until its own review is recorded', t => {
  const root = makeProject(t, { plan: PLAN.replace('**Run:** inline · **Size:** S\n- [ ] Test', '**Run:** inline · **Size:** S · **Risk:** migration\n- [ ] Test') });
  write(root, 'verify1.mjs', '\n');
  write(root, 'src/limit.mjs', '1\n');
  git(root, 'add', 'src');
  const done = dflow(root, ['done', '1', '-m', 'feat: parse']);
  assert.match(done.stdout, /Task 1 carries risk "migration": review its commit now \(dflow review pack --task 1\)/);
  const states = () => JSON.parse(dflow(root, ['status', '--json']).stdout).plan.tasks.map(task => task.state);
  assert.deepEqual(states(), ['review', 'wip']);
  assert.equal(dflow(root, ['review', 'record', '--tier', '1', '--task', '1']).status, 0);
  assert.deepEqual(states(), ['done', 'wip']);
});
