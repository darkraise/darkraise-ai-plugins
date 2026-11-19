import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
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
function jobsWithLimits(...args) { return list('--limits', ...args).map(line => { const [seconds, text] = line.split('\t'); return ['', text.split(' '), Number(seconds)]; }); }
const shell = (name, limit, ...part) => ['bash', [`tests/dforge/${name}`, ...part], limit];

test('Windows shards cover every discovered suite exactly once', () => {
  const workflow = readFileSync(new URL('../.github/workflows/validate.yml', import.meta.url), 'utf8');
  const count = Number(/--shard \$\{\{ matrix\.shard \}\}\/(\d+)/.exec(workflow)?.[1]);
  assert.ok(count > 0, 'validate.yml names the shard count');
  const all = list();
  const shards = Array.from({ length: count }, (_, i) => list('--shard', `${i + 1}/${count}`));
  assert.ok(shards.every(shard => shard.length > 0));
  assert.deepEqual(shards.flat().sort(), all.sort());
  assert.equal(new Set(shards.flat()).size, all.length);
  assert.deepEqual(list('--shard', `1/${count}`), shards[0]);
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
  const lint = ['bash', ['tests/dforge/plan-lint.test.sh'], 900];
  const first = ['bash', ['tests/dforge/faster-plans.acceptance.test.sh', 'a1'], 600];
  const second = ['bash', ['tests/dforge/faster-plans.acceptance.test.sh', 'a2'], 600];
  const jobs = [lint, first, second];
  assert.deepEqual(selectShard(jobs, '1/2'), [lint]);
  assert.deepEqual(selectShard(jobs, '2/2'), [first, second]);
});

test('each node --test job is scheduled by the weight of its first test file', () => {
  const heavy = ['node', ['--test', 'tests/heavy.test.mjs', 'tests/more.test.mjs'], 1200];
  const light = ['node', ['--test', 'tests/light.test.mjs'], 120];
  const suite = shell('a.test.sh', 600);
  const weights = { 'tests/heavy.test.mjs': 500, 'tests/light.test.mjs': 10, 'tests/dforge/a.test.sh': 400 };
  assert.deepEqual(selectShard([heavy, light, suite], '1/2', weights), [heavy]);
  assert.deepEqual(selectShard([heavy, light, suite], '2/2', weights), [light, suite]);
});

test('a suite with per-part weights schedules each part by its own weight', () => {
  const part = name => ['bash', ['tests/dforge/a.test.sh', name], 900];
  const jobs = ['start', 'verdict', 'x', 'y'].map(part);
  const weights = { 'tests/dforge/a.test.sh': { start: 700, verdict: 450, x: 100, y: 100 } };
  assert.deepEqual(selectShard(jobs, '1/2', weights), [jobs[0]]);
  assert.deepEqual(selectShard(jobs, '2/2', weights), jobs.slice(1));
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
    { name: 'exactly 80% passes', jobs: [shell('a.test.sh', 600)], weights: { 'tests/dforge/a.test.sh': 480 }, want: [] },
    { name: 'above 80%', jobs: [shell('a.test.sh', 600)], weights: { 'tests/dforge/a.test.sh': 481 }, want: [/a\.test\.sh: .*raise its suiteSeconds or split it/] },
    { name: 'a larger limit raises the bound', jobs: [shell('a.test.sh', 1200)], weights: { 'tests/dforge/a.test.sh': 900 }, want: [] },
    { name: 'parts split the weight', jobs: [shell('a.test.sh', 600, 'a1'), shell('a.test.sh', 600, 'a2')], weights: { 'tests/dforge/a.test.sh': 960 }, want: [] },
    { name: 'parts do not hide a heavy weight', jobs: [shell('a.test.sh', 600, 'a1'), shell('a.test.sh', 600, 'a2')], weights: { 'tests/dforge/a.test.sh': 962 }, want: [/raise its suiteSeconds or split it/] },
    { name: 'per-part weights within 80% pass', jobs: [shell('a.test.sh', 600, 'a1'), shell('a.test.sh', 600, 'a2')], weights: { 'tests/dforge/a.test.sh': { a1: 480, a2: 100 } }, want: [] },
    {
      name: 'per-part weights name a heavy or missing part',
      jobs: [shell('a.test.sh', 600, 'a1'), shell('a.test.sh', 600, 'a2')],
      weights: { 'tests/dforge/a.test.sh': { a1: 481 } },
      want: [/a\.test\.sh a1: weight 481 s .*raise its suiteSeconds or split it/, /a\.test\.sh a2: no weight for this part/],
    },
    {
      name: 'jobs that are not shell suites keep the default weight',
      jobs: [['node', ['scripts/validate-repository.mjs'], 60], ['claude', ['plugin', 'test', 'plugins/dforge'], 300], ['tsc', ['--noEmit', '-p', 'plugins/dforge'], 300]],
      weights: {},
      want: [],
    },
    {
      name: 'a node --test job needs a weight under its first test file',
      jobs: [['node', ['--test', 'tests/a.test.mjs', 'tests/b.test.mjs'], 120], ['node', ['--test', 'tests/c.test.mjs'], 100]],
      weights: { 'tests/c.test.mjs': 90 },
      want: [/^tests\/a\.test\.mjs: no weight in scripts\/test-shards\.mjs/, /^tests\/c\.test\.mjs: weight 90 s is above 80% of its 100 s limit/],
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
    const script = readFileSync(fileURLToPath(new URL(`../tests/dforge/${name}`, import.meta.url)), 'utf8');
    const declared = script.match(/^ALL="([^"]*)"\r?$/m);
    assert.ok(declared, `${name} declares its parts on an ALL="..." line`);
    const parts = jobs.filter(([, args]) => args[0] === `tests/dforge/${name}`);
    assert.ok(parts.length > 1, `${name} runs in parts`);
    assert.deepEqual(parts.flatMap(([, args]) => args.slice(1)).sort(), declared[1].split(' ').sort(), name);
  }
});

test('task-step.test.sh refuses a part it does not declare before it runs anything', () => {
  const result = spawnSync(bash, ['tests/dforge/task-step.test.sh', 'no-such-part'], { cwd: root, encoding: 'utf8', timeout: 15000 });
  assert.ifError(result.error);
  assert.equal(result.status, 2);
  assert.match(result.stderr, /unknown part no-such-part/);
});

test('a suite past 75% of its limit is named in a GitHub warning that test-all prints', () => {
  const args = ['tests/dforge/slow.test.sh', 'a1'];
  assert.equal(sched.driftWarning(args, 449, 600), undefined);
  assert.equal(sched.driftWarning(args, 450, 600), undefined);
  const warning = sched.driftWarning(args, 450.5, 600);
  assert.match(warning, /^::warning::/);
  assert.ok(warning.includes('tests/dforge/slow.test.sh a1'), warning);
  assert.match(warning, /600/);
  const source = readFileSync(runner, 'utf8');
  assert.match(source, /import \{[^}]*driftWarning[^}]*\} from '\.\/test-shards\.mjs'/);
  assert.match(source, /driftWarning\(args, /);
});

test('weights, limits and parts are keyed by repository path', () => {
  for (const table of [sched.windowsSeconds, sched.suiteSeconds, sched.suiteParts]) {
    for (const key of Object.keys(table)) assert.match(key, /^tests\/([a-z0-9-]+\/)?[^/]+$/, key);
  }
});

test('weights, limits and parts name only suites that exist', () => {
  for (const table of [sched.windowsSeconds, sched.suiteSeconds, sched.suiteParts]) {
    assert.deepEqual(Object.keys(table).filter(key => !existsSync(join(root, key))), []);
  }
});

test('two plugins may hold suites with one basename', () => {
  const jobs = [
    ['bash', ['tests/dforge/plan-lint.test.sh', 'one'], 1200],
    ['bash', ['tests/dagents/plan-lint.test.sh'], 600],
  ];
  const weights = { 'tests/dforge/plan-lint.test.sh': { one: 300 }, 'tests/dagents/plan-lint.test.sh': 100 };
  assert.deepEqual(sched.checkShellWeights(jobs, weights), []);
  assert.deepEqual(sched.checkShellWeights(jobs, { 'tests/dforge/plan-lint.test.sh': { one: 300 } }),
    ['tests/dagents/plan-lint.test.sh: no weight in scripts/test-shards.mjs; add it to windowsSeconds']);
});

test('the default run leaves dagents to its own run, and --plugin dagents runs only dagents', () => {
  assert.ok(list().every(line => !/(plugins|tests)\/dagents(\/|$| )/.test(line)));
  const dagents = list('--plugin', 'dagents');
  assert.ok(dagents.length > 0);
  assert.ok(dagents.every(line => /(plugins|tests)\/dagents(\/|$| )/.test(line)), dagents.join('\n'));
  const bad = spawnSync(process.execPath, [runner, '--list', '--plugin', 'nope'], { encoding: 'utf8', timeout: 10000 });
  assert.equal(bad.status, 2);
});

test('a dagents suite sharing a dforge basename keeps its own limit and parts', () => {
  const path = 'tests/dagents/plan-lint.test.sh';
  const lines = list('--limits', '--plugin', 'dagents').map(line => line.split('\t')).filter(([, text]) => text.startsWith(path));
  const expected = (sched.suiteParts[path] ?? [[]]).map(part => [path, ...part].join(' '));
  assert.deepEqual(lines.map(([, text]) => text), expected);
  for (const [seconds] of lines) assert.equal(Number(seconds), sched.suiteSeconds[path] ?? 600);
});

test('every dagents shell suite has a weight within 80% of its limit', () => {
  assert.deepEqual(sched.checkShellWeights(jobsWithLimits('--plugin', 'dagents')), []);
});

test('dagents Windows shards cover every dagents suite exactly once', () => {
  const workflow = readFileSync(new URL('../.github/workflows/validate.yml', import.meta.url), 'utf8');
  const count = Number(/--plugin dagents --shard \$\{\{ matrix\.shard \}\}\/(\d+)/.exec(workflow)?.[1]);
  assert.ok(count > 0, 'validate.yml names the dagents shard count');
  const all = list('--plugin', 'dagents');
  const shards = Array.from({ length: count }, (_, i) => list('--plugin', 'dagents', '--shard', `${i + 1}/${count}`));
  assert.ok(shards.every(shard => shard.length > 0));
  assert.deepEqual(shards.flat().sort(), all.sort());
});

test('dagents jobs run only when a change can reach them', () => {
  const workflow = readFileSync(new URL('../.github/workflows/validate.yml', import.meta.url), 'utf8');
  assert.match(workflow, /^ {2}dagents-changes:$/m);
  assert.ok(workflow.includes('^(plugins/dagents/|tests/dagents/|scripts/(test-all|test-shards|validate-repository|lint-portability|dagents-rename)\\.mjs$|\\.github/workflows/validate\\.yml$)'), 'the path filter');
  const dagentsJob = workflow.slice(workflow.indexOf('  validate-dagents:')).slice(0, 600);
  assert.match(dagentsJob, /needs\.dagents-changes\.outputs\.dagents == 'true'/, 'validate-dagents');
  const windowsDagents = workflow.slice(workflow.indexOf('  windows-dagents:')).slice(0, 900);
  assert.match(windowsDagents, /needs\.scope\.outputs\.scope == 'full'/, 'windows-dagents');
  assert.match(workflow, /\.name == "validate-dagents"/, 'the homelab wait job watches validate-dagents');
});

test('jobs run with the guard isolated from the host', () => {
  const env = sched.guardIsolation({ CLAUDE_CONFIG_DIR: '/host', KEEP: 'x' }, '/empty');
  assert.deepEqual([env.WORKFLOW_GUARD_CLAUDE_DIR, env.WORKFLOW_GUARD_MANAGED_DIR, env.WORKFLOW_GUARD_PROJECT_DIR, env.KEEP], ['/empty', '/empty', '/empty', 'x']);
  assert.equal(sched.guardIsolation({ WORKFLOW_GUARD_CLAUDE_DIR: '/set' }, '/empty').WORKFLOW_GUARD_CLAUDE_DIR, '/set');
});

test('the Windows slice names the seven suites with a portability fault, and each exists', async () => {
  const { windowsSlice } = await import(new URL('../scripts/test-shards.mjs', import.meta.url).href);
  assert.deepEqual([...windowsSlice].sort(), [
    'tests/dforge/darkmem-sync.test.sh', 'tests/dforge/dforge-migrate.test.sh', 'tests/dforge/dforge-state.test.sh',
    'tests/dforge/plan-amend.test.sh', 'tests/dforge/register.test.sh', 'tests/dforge/roadmap.test.sh',
    'tests/dforge/working-directory.test.sh',
  ]);
  for (const suite of windowsSlice) assert.ok(existsSync(new URL(`../${suite}`, import.meta.url)), `${suite} exists`);
});

test('--slice lists exactly the slice, and runs alone', async () => {
  const { windowsSlice } = await import(new URL('../scripts/test-shards.mjs', import.meta.url).href);
  const listed = list('--slice');
  assert.deepEqual(listed.map(line => line.split(' ')[0]).sort(), [...windowsSlice].sort());
  for (const other of [['--shard', '1/16'], ['--plugin', 'dagents']]) {
    const r = spawnSync(process.execPath, ['scripts/test-all.mjs', '--slice', ...other, '--list'], { cwd: root, encoding: 'utf8' });
    assert.equal(r.status, 2, other.join(' '));
    assert.match(r.stderr, /--slice runs alone/);
  }
});
