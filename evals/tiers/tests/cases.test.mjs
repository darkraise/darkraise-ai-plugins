import assert from 'node:assert/strict';
import { rmSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { after, test } from 'node:test';
import { spawnSync } from 'node:child_process';
import { PLAN, fixture } from './fixture.mjs';

const fx = fixture();
after(() => rmSync(fx.top, { recursive: true, force: true }));
const { candidates, golden, plans, readManifest, select, slug, strippedRow, slices, scoreSlice, orderSlices, pickSlices, sliceId, SLICE_CAP } = await import('../lib/cases.mjs');
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
  assert.deepEqual(
    [slug('docs/superpowers/plans/2026-09-15-dr-superpowers-review-routing.md'), slug('docs/dforge/plans/2026-11-01-dr-forge-settings.md'), slug('docs/dforge/plans/2026-11-02-dforge-cockpit.md'), slug(PLAN)],
    ['review-routing', 'settings', 'cockpit', 'fixture'],
  );
});

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
