import assert from 'node:assert/strict';
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { after, test } from 'node:test';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { summarize } from '../lib/pipeline-report.mjs';
import { PIPELINE_COLUMNS } from '../lib/results.mjs';

const row = (arm, id, run, outcome, costUsd, seconds, rep = '1') => ({ rep, case: id, arm, run: String(run), outcome, costUsd: String(costUsd), seconds: String(seconds), dispatches: '3', fixRounds: '0', detail: '' });
const ROWS = [
  row('baseline', 'a', 1, 'PASS', 1, 100), row('baseline', 'a', 2, 'PASS', 2, 200),
  row('baseline', 'b', 1, 'PASS', 1.5, 150), row('baseline', 'b', 2, 'FAIL', 1.5, 300),
  row('candidate', 'a', 1, 'PASS', 0.5, 80), row('candidate', 'a', 2, 'PASS', 0.5, 90),
  row('candidate', 'b', 1, 'PASS', 0.5, 70), row('candidate', 'b', 2, 'ERROR', 0.5, 60),
];

test('summarize counts the cases that passed both runs, the cost and the median wall time per arm', () => {
  assert.deepEqual(summarize(ROWS), [
    { arm: 'baseline', cases: 2, pass2: 1, cost: 6, median: 175 },
    { arm: 'candidate', cases: 2, pass2: 1, cost: 2, median: 75 },
  ]);
});

test('a later row for the same case, arm and run replaces the earlier one', () => {
  const [baseline] = summarize([...ROWS, row('baseline', 'b', 2, 'PASS', 1.5, 120)]);
  assert.deepEqual(baseline, { arm: 'baseline', cases: 2, pass2: 2, cost: 6, median: 135 });
});

test('a case with one run recorded does not pass twice', () => {
  const [only] = summarize([row('baseline', 'a', 1, 'PASS', 1, 100)]);
  assert.deepEqual([only.cases, only.pass2], [1, 0]);
});

const top = mkdtempSync(join(tmpdir(), 'pipeline-report-test-'));
after(() => rmSync(top, { recursive: true, force: true }));

test('report --pipeline prints one line per arm for the repetition asked for', () => {
  const data = join(top, 'data');
  mkdirSync(join(data, 'results'), { recursive: true });
  const rows = [...ROWS, row('baseline', 'a', 1, 'PASS', 9, 999, '2')];
  writeFileSync(join(data, 'results/pipeline.tsv'), [PIPELINE_COLUMNS.join('\t'), ...rows.map(r => PIPELINE_COLUMNS.map(k => r[k]).join('\t'))].join('\n') + '\n');
  const run = args => spawnSync(process.execPath, [fileURLToPath(new URL('../report.mjs', import.meta.url)), ...args], { encoding: 'utf8', env: { ...process.env, TIER_EVAL_DATA: data } });
  const first = run(['--pipeline']);
  assert.equal(first.status, 0, first.stderr);
  assert.equal(first.stdout, [
    '# Pipeline eval - repetition 1', '',
    '- `baseline`: pass^2 1/2, cost $6.00, median 175s',
    '- `candidate`: pass^2 1/2, cost $2.00, median 75s', '',
  ].join('\n'));
  const second = run(['--pipeline', '--rep', '2']);
  assert.match(second.stdout, /- `baseline`: pass\^2 0\/1, cost \$9\.00, median 999s/);
  assert.match(run(['--pipeline', '--rep', '3']).stdout, /No pipeline runs recorded\./);
});
