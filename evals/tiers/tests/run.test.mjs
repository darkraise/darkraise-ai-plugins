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
