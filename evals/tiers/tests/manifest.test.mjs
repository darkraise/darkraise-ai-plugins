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
