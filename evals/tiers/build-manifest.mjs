#!/usr/bin/env node
// Enumerate every eligible task, run the free golden check on each, select the
// cases and write cases/manifest.tsv and cases/excluded.tsv.
// With --slices, merge two or three consecutive tasks of one plan into slice
// cases instead, golden-check them in order until five pass, and write
// cases/slices.tsv and cases/slices-excluded.tsv.
// Usage: node evals/tiers/build-manifest.mjs [--slices]
// Exit: 0 written; 2 usage, or the plugin has uncommitted changes.
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { DATA, git } from './lib/sh.mjs';
import { CAP, MANIFEST, SLICES, candidates, golden, orderSlices, pickSlices, select, sliceId, slices, slug, strippedRow } from './lib/cases.mjs';

const JOBS = 6;
const sliceMode = process.argv[2] === '--slices';
if (process.argv.length > 3 || (process.argv.length === 3 && !sliceMode)) {
  console.error('usage: build-manifest.mjs [--slices]');
  process.exit(2);
}
if (git(['status', '--porcelain', '--', 'plugins/dforge']).trim() !== '') {
  console.error('build-manifest: plugins/dforge has uncommitted changes');
  process.exit(2);
}
const start = git(['rev-parse', 'HEAD']).trim();
if (sliceMode) {
  const windows = slices(candidates(start));
  const { picked, excluded } = await pickSlices(orderSlices(windows.filter(w => !w.reason)), golden);
  const rows = [`# start ${start}`, ['id', 'pool', 'row', 'plan', 'task', 'tasks', 'base', 'result'].join('\t')];
  for (const w of picked) rows.push([sliceId(w), 'slice', w.axes.total, w.plan, w.tasks[0], w.tasks.join(','), w.base, w.result].join('\t'));
  const left = [...windows.filter(w => w.reason), ...excluded]
    .sort((a, b) => a.plan.localeCompare(b.plan) || a.tasks[0] - b.tasks[0] || b.tasks.length - a.tasks.length);
  mkdirSync(dirname(SLICES), { recursive: true });
  writeFileSync(SLICES, rows.join('\n') + '\n');
  writeFileSync(resolve(DATA, 'cases/slices-excluded.tsv'), ['plan\ttasks\treason', ...left.map(w => [w.plan, w.tasks.join(','), w.reason].join('\t'))].join('\n') + '\n');
  console.log(`build-manifest: ${picked.length} slices, ${left.length} exclusions, start ${start}`);
  process.exit(0);
}
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
