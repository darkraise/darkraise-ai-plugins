import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import test from 'node:test';
import * as sched from '../scripts/test-shards.mjs';
import { selectShard } from '../scripts/test-shards.mjs';

const runner = fileURLToPath(new URL('../scripts/test-all.mjs', import.meta.url));
const root = fileURLToPath(new URL('../', import.meta.url));
const bash = process.env.DR_TEST_BASH ?? 'bash';
function list(...args) {
  const result = spawnSync(process.execPath, [runner, '--list', ...args], { encoding: 'utf8', timeout: 10000 });
  assert.ifError(result.error);
  assert.equal(result.status, 0, result.stderr);
  return result.stdout.trim().split('\n');
}
function jobsWithLimits() {
  return list('--limits').map(line => {
    const [seconds, text] = line.split('\t');
    return ['', text.split(' '), Number(seconds)];
  });
}
const shell = (name, limit, ...part) => ['bash', [`plugins/dforge/tests/${name}`, ...part], limit];

test('Windows shards cover every discovered suite exactly once', () => {
  const all = list();
  const shards = Array.from({ length: 12 }, (_, i) => list('--shard', `${i + 1}/12`));
  assert.ok(shards.every(shard => shard.length > 0));
  assert.deepEqual(shards.flat().sort(), all.sort());
  assert.equal(new Set(shards.flat()).size, all.length);
  assert.deepEqual(list('--shard', '1/12'), shards[0]);
});

test('a job without a weight is scheduled at the default weight and unsharded runs retain their order', () => {
  const jobs = ['plan-lint.test.sh', 'task-state.test.sh', 'new-suite.test.sh'].map(name => ['bash', [name], 600]);
  assert.deepEqual(selectShard(jobs), jobs);
  assert.deepEqual(selectShard(jobs, '1/1'), jobs);
  const selected = [selectShard(jobs, '1/2'), selectShard(jobs, '2/2')].flat();
  assert.equal(selected.length, jobs.length);
  for (const job of jobs) assert.ok(selected.includes(job));
});

test('a suite run in parts splits its weight among them', () => {
  const lint = ['bash', ['plugins/dforge/tests/plan-lint.test.sh'], 900];
  const first = ['bash', ['plugins/dforge/tests/faster-plans.acceptance.test.sh', 'a1'], 600];
  const second = ['bash', ['plugins/dforge/tests/faster-plans.acceptance.test.sh', 'a2'], 600];
  const jobs = [lint, first, second];
  assert.deepEqual(selectShard(jobs, '1/2'), [lint]);
  assert.deepEqual(selectShard(jobs, '2/2'), [first, second]);
});

test('invalid shard arguments fail instead of silently skipping tests', () => {
  const jobs = [['bash', ['a'], 10], ['bash', ['b'], 10]];
  for (const shard of ['', '0/2', '3/2', '1/0', '1/3', '1.5/2', '1', '1/2/3', '1/9007199254740992']) {
    assert.throws(() => selectShard(jobs, shard), /Shard/);
  }
  const result = spawnSync(process.execPath, [runner, '--shard', '0/4'], { encoding: 'utf8', timeout: 10000 });
  assert.ifError(result.error);
  assert.notEqual(result.status, 0);
  assert.doesNotMatch(result.stdout, /Running /);
});

test('a shell suite needs a weight of at most 80% of its limit', () => {
  const rows = [
    { name: 'no weight', jobs: [shell('new.test.sh', 600)], weights: {}, want: [/new\.test\.sh: no weight/] },
    { name: 'no weight for the dr-status suite', jobs: [['bash', ['plugins/dr-status/tests/run-all.sh'], 420]], weights: {}, want: [/run-all\.sh: no weight/] },
    { name: 'exactly 80% passes', jobs: [shell('a.test.sh', 600)], weights: { 'a.test.sh': 480 }, want: [] },
    { name: 'above 80%', jobs: [shell('a.test.sh', 600)], weights: { 'a.test.sh': 481 }, want: [/a\.test\.sh: .*raise its suiteSeconds or split it/] },
    { name: 'a larger limit raises the bound', jobs: [shell('a.test.sh', 1200)], weights: { 'a.test.sh': 900 }, want: [] },
    { name: 'parts split the weight', jobs: [shell('a.test.sh', 600, 'a1'), shell('a.test.sh', 600, 'a2')], weights: { 'a.test.sh': 960 }, want: [] },
    { name: 'parts do not hide a heavy weight', jobs: [shell('a.test.sh', 600, 'a1'), shell('a.test.sh', 600, 'a2')], weights: { 'a.test.sh': 962 }, want: [/raise its suiteSeconds or split it/] },
    {
      name: 'jobs that are not shell suites keep the default weight',
      jobs: [['node', ['scripts/validate-repository.mjs'], 60], ['node', ['--test', 'tests/a.test.mjs'], 120], ['claude', ['plugin', 'test', 'plugins/dforge'], 300], ['tsc', ['--noEmit', '-p', 'plugins/dforge'], 300]],
      weights: {},
      want: [],
    },
  ];
  for (const row of rows) {
    const got = sched.checkShellWeights(row.jobs, row.weights);
    assert.equal(got.length, row.want.length, `${row.name}: ${got.join(' | ')}`);
    row.want.forEach((pattern, i) => assert.match(got[i], pattern, row.name));
  }
});

test('every shell suite of the repository has a weight within 80% of its limit', () => {
  assert.deepEqual(sched.checkShellWeights(jobsWithLimits()), []);
});

test('a suite run in parts runs every part its script declares', () => {
  const jobs = jobsWithLimits();
  for (const name of ['task-step.test.sh', 'faster-plans.acceptance.test.sh']) {
    const script = readFileSync(fileURLToPath(new URL(`../plugins/dforge/tests/${name}`, import.meta.url)), 'utf8');
    const declared = script.match(/^ALL="([^"]*)"\r?$/m);
    assert.ok(declared, `${name} declares its parts on an ALL="..." line`);
    const parts = jobs.filter(([, args]) => args[0] === `plugins/dforge/tests/${name}`);
    assert.ok(parts.length > 1, `${name} runs in parts`);
    assert.deepEqual(parts.flatMap(([, args]) => args.slice(1)).sort(), declared[1].split(' ').sort(), name);
  }
});

test('task-step.test.sh refuses a part it does not declare before it runs anything', () => {
  const result = spawnSync(bash, ['plugins/dforge/tests/task-step.test.sh', 'no-such-part'], { cwd: root, encoding: 'utf8', timeout: 15000 });
  assert.ifError(result.error);
  assert.equal(result.status, 2);
  assert.match(result.stderr, /unknown part no-such-part/);
});

test('a suite past 75% of its limit is named in a GitHub warning that test-all prints', () => {
  const args = ['plugins/dforge/tests/slow.test.sh', 'a1'];
  assert.equal(sched.driftWarning(args, 449, 600), undefined);
  assert.equal(sched.driftWarning(args, 450, 600), undefined);
  const warning = sched.driftWarning(args, 450.5, 600);
  assert.match(warning, /^::warning::/);
  assert.ok(warning.includes('plugins/dforge/tests/slow.test.sh a1'), warning);
  assert.match(warning, /600/);
  const source = readFileSync(runner, 'utf8');
  assert.match(source, /import \{[^}]*driftWarning[^}]*\} from '\.\/test-shards\.mjs'/);
  assert.match(source, /driftWarning\(args, /);
});
