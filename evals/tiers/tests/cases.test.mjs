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
