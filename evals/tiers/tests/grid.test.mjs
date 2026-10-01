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
