import assert from 'node:assert/strict';
import { chmodSync, existsSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { join, relative, sep } from 'node:path';
import { after, test } from 'node:test';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { PLAN, fixture, modes } from './fixture.mjs';

const fx = fixture();
after(() => rmSync(fx.top, { recursive: true, force: true }));
const { runPipelineCase } = await import('../lib/pipeline.mjs');
const { PIPELINE_COLUMNS, PIPELINE_RESULTS, readTsv } = await import('../lib/results.mjs');

const root = join(fx.top, 'eval-root');
const hostConfig = join(fx.top, 'host-config');
mkdirSync(hostConfig);
writeFileSync(join(hostConfig, '.credentials.json'), '{"login":true}');
writeFileSync(join(hostConfig, 'settings.json'), '{"model":"owner-choice"}');
process.env.CLAUDE_CONFIG_DIR = hostConfig;
const row = { case: 'p-fixture-t1', plan: PLAN, task: '1', base: fx.planned, fixRounds: '1' };
const calls = () => readFileSync(join(fx.stub, 'calls.log'), 'utf8').trim().split('\n').map(line => JSON.parse(line));
const inside = path => !relative(root, path).startsWith('..') && !relative(root, path).split(sep).includes('..');
const grid = (args = [], env = {}) => spawnSync(process.execPath, [fileURLToPath(new URL('../run-grid.mjs', import.meta.url)), '--stage', 'pipeline', ...args], { cwd: fx.repo, encoding: 'utf8', env: { ...process.env, TIER_EVAL_JOBS: '1', ...env } });

test('the results file has the pipeline columns', () => {
  assert.deepEqual(PIPELINE_COLUMNS, ['rep', 'case', 'arm', 'run', 'outcome', 'costUsd', 'seconds', 'dispatches', 'fixRounds', 'detail']);
  assert.equal(PIPELINE_RESULTS, join(fx.data, 'results/pipeline.tsv'));
});

test('a replayed case passes and reports cost, dispatches and fix rounds', async () => {
  modes(fx.stub, 'loop');
  const result = await runPipelineCase({ c: row, arm: 'baseline@1111111', ref: fx.planned, run: 1, root });
  assert.deepEqual(result, { outcome: 'PASS', costUsd: 0.5, seconds: result.seconds, dispatches: 2, fixRounds: 1, detail: '' });
});

test('a session that stops before the ledger shows the task complete fails', async () => {
  modes(fx.stub, 'loopstop');
  const result = await runPipelineCase({ c: row, arm: 'baseline@1111111', ref: fx.planned, run: 2, root });
  assert.deepEqual([result.outcome, result.detail, result.dispatches, result.fixRounds], ['FAIL', 'no-complete-line', 2, 0]);
});

test('a run that changes nothing fails the hidden tests', async () => {
  modes(fx.stub, 'blocked');
  const result = await runPipelineCase({ c: row, arm: 'baseline@1111111', ref: fx.planned, run: 3, root });
  assert.deepEqual([result.outcome, result.detail], ['FAIL', 'no-complete-line failed=tests/greet.test.sh']);
});

test('a rate limit is an ERROR row, not a failure', async () => {
  modes(fx.stub, 'limit');
  const result = await runPipelineCase({ c: row, arm: 'baseline@1111111', ref: fx.planned, run: 4, root });
  assert.equal(result.outcome, 'ERROR');
  assert.match(result.detail, /^limit: /);
});

test('every run works inside the eval root, under the plugin of its arm', () => {
  const made = calls().filter(call => call.args.includes('--plugin-dir'));
  assert.ok(made.length >= 4);
  for (const call of made) {
    const flag = name => call.args[call.args.indexOf(name) + 1];
    assert.ok(inside(call.cwd), call.cwd);
    assert.ok(inside(flag('--plugin-dir')), flag('--plugin-dir'));
    assert.match(flag('--plugin-dir'), /arms[\\/][0-9a-f]{7}[\\/]plugins[\\/]dforge$/);
    for (const value of Object.values(call.env)) assert.ok(inside(value), value);
    assert.equal(call.claudeMds, '1');
    assert.deepEqual(call.config, ['.claude.json', '.credentials.json']);
    assert.match(call.prompt, /^Use the dforge:subagent-driven-development skill to carry out Task 1 of docs\/superpowers\/plans\/2026-09-20-fixture\.md, and only that task\./);
  }
  assert.ok(existsSync(join(root, 'arms', fx.planned.slice(0, 7), 'plugins/dforge/marker.txt')));
});

test('the pipeline stage runs every missing cell and reuses a baseline measured at the same ref', () => {
  const arms = JSON.parse(readFileSync(join(fx.data, 'arms.json'), 'utf8'));
  writeFileSync(join(fx.data, 'arms.json'), JSON.stringify({ ...arms, pipeline: { baseline: fx.planned, candidate: fx.greet } }));
  writeFileSync(join(fx.data, 'cases/pipeline.tsv'), `case\tplan\ttask\tbase\tfixRounds\n${[row.case, row.plan, row.task, row.base, row.fixRounds].join('\t')}\n`);
  modes(fx.stub, 'loop');
  const first = grid();
  assert.equal(first.status, 0, first.stderr);
  assert.match(first.stdout, /run-grid stage=pipeline rep=1 ran=4 remaining=0 spent=2\.00 stop=-/);
  const rows = readTsv(PIPELINE_RESULTS);
  assert.deepEqual(rows.map(r => [r.arm, r.run, r.outcome, r.dispatches, r.fixRounds]), [
    [`baseline@${fx.planned.slice(0, 7)}`, '1', 'PASS', '2', '1'],
    [`baseline@${fx.planned.slice(0, 7)}`, '2', 'PASS', '2', '1'],
    [`candidate@${fx.greet.slice(0, 7)}`, '1', 'PASS', '2', '1'],
    [`candidate@${fx.greet.slice(0, 7)}`, '2', 'PASS', '2', '1'],
  ]);
  assert.match(readFileSync(PIPELINE_RESULTS, 'utf8').split('\n')[0], /^rep\tcase\tarm\trun\toutcome\tcostUsd\tseconds\tdispatches\tfixRounds\tdetail$/);

  writeFileSync(join(fx.data, 'arms.json'), JSON.stringify({ ...arms, pipeline: { baseline: fx.planned, candidate: fx.shout } }));
  const second = grid();
  assert.match(second.stdout, /ran=2 remaining=0 spent=3\.00/);
  assert.equal(readTsv(PIPELINE_RESULTS).length, 6);
  assert.match(grid().stdout, /ran=0 remaining=0/);
});

test('the pipeline stage stops at the spend cap and refuses a missing manifest', () => {
  assert.match(grid(['--rep', '2'], { TIER_EVAL_CAP_USD: '0' }).stdout, /ran=0 remaining=4 spent=0\.00 stop=cap/);
  rmSync(join(fx.data, 'cases/pipeline.tsv'));
  const none = grid(['--rep', '3']);
  assert.equal(none.status, 2);
  assert.match(none.stderr, /no pipeline manifest/);
});

test('a test file absent at the result commit stops the case before any session', async () => {
  const g = (...args) => { const r = spawnSync('git', ['-c', 'user.name=fixture', '-c', 'user.email=fixture@example.invalid', ...args], { cwd: fx.repo, encoding: 'utf8' }); assert.equal(r.status, 0, r.stderr); return r.stdout.trim(); };
  const plan = 'docs/gap-plan.md';
  writeFileSync(join(fx.repo, plan), ['# Gap Plan', '', '**Goal:** a gap', '', '---', '', '### Task 1: Gap', '', '**Files:**', '- Create: `src/gap.sh`', '- Test: `tests/gap.test.sh`', '', '- [ ] **Step 1: Commit**', '', '```bash', 'git commit -m "feat: add gap"', '```', ''].join('\n'));
  g('add', '-A'); g('commit', '-q', '-m', 'docs: plan the gap');
  const base = g('rev-parse', 'HEAD');
  writeFileSync(join(fx.repo, 'src/gap.sh'), 'echo gap\n');
  g('add', '-A'); g('commit', '-q', '-m', 'feat: add gap');
  modes(fx.stub, 'loop');
  const before = calls().length;
  const result = await runPipelineCase({ c: { case: 'p-gap', plan, task: '1', base, fixRounds: '0' }, arm: 'baseline@1111111', ref: fx.planned, run: 1, root });
  assert.deepEqual([result.outcome, result.costUsd], ['ERROR', 0]);
  assert.match(result.detail, /tests\/gap\.test\.sh is missing at [0-9a-f]{40}/);
  assert.equal(calls().length, before);
});

test('a harness error after the session ran keeps the session cost', async () => {
  const script = join(fx.top, 'claude-breaks-git');
  writeFileSync(script, `#!/bin/sh\ncat >/dev/null\nrm -rf .git\nprintf '%s' '{"type":"result","total_cost_usd":0.5,"is_error":false,"result":"done"}'\n`);
  chmodSync(script, 0o755);
  const saved = process.env.TIER_EVAL_CLAUDE;
  process.env.TIER_EVAL_CLAUDE = script;
  try {
    const result = await runPipelineCase({ c: row, arm: 'baseline@1111111', ref: fx.planned, run: 5, root });
    assert.deepEqual([result.outcome, result.costUsd], ['ERROR', 0.5]);
    assert.match(result.detail, /^error: sdd-workspace exited 2: .*not inside a git repository/);
  } finally {
    process.env.TIER_EVAL_CLAUDE = saved;
  }
});

test('a ledger that cannot be read is an ERROR that keeps the session cost, not a failed product', async () => {
  const script = join(fx.top, 'claude-removes-plan');
  writeFileSync(script, `#!/bin/sh\ncat >/dev/null\nrm -f "${PLAN}"\nprintf '%s' '{"type":"result","total_cost_usd":0.5,"is_error":false,"result":"done"}'\n`);
  chmodSync(script, 0o755);
  const saved = process.env.TIER_EVAL_CLAUDE;
  process.env.TIER_EVAL_CLAUDE = script;
  try {
    const result = await runPipelineCase({ c: row, arm: 'baseline@1111111', ref: fx.planned, run: 6, root });
    assert.deepEqual([result.outcome, result.costUsd], ['ERROR', 0.5]);
    assert.match(result.detail, /^error: sdd-workspace exited [1-9]/);
  } finally {
    process.env.TIER_EVAL_CLAUDE = saved;
  }
});

test('the child sees the allowlisted host variables and the API credentials, and nothing else', async () => {
  const secrets = { GH_TOKEN: 'gh-secret', AWS_SECRET_ACCESS_KEY: 'aws-secret', NPM_TOKEN: 'npm-secret', SSH_AUTH_SOCK: '/tmp/agent.sock', SOME_REGISTRY_PASSWORD: 'pw' };
  const savedKey = process.env.ANTHROPIC_API_KEY;
  Object.assign(process.env, secrets, { ANTHROPIC_API_KEY: 'sk-ant-test-key-0123456789abcdef' });
  try {
    modes(fx.stub, 'loop');
    const before = calls().length;
    await runPipelineCase({ c: row, arm: 'baseline@1111111', ref: fx.planned, run: 7, root });
    const keys = calls()[before].envKeys;
    for (const key of Object.keys(secrets)) assert.ok(!keys.includes(key), `${key} reached the child`);
    for (const key of ['PATH', 'HOME', 'XDG_CONFIG_HOME', 'XDG_CACHE_HOME', 'XDG_DATA_HOME', 'XDG_STATE_HOME', 'CLAUDE_CONFIG_DIR', 'TMPDIR', 'ANTHROPIC_API_KEY']) assert.ok(keys.includes(key), `${key} is missing`);
  } finally {
    for (const key of Object.keys(secrets)) delete process.env[key];
    if (savedKey === undefined) delete process.env.ANTHROPIC_API_KEY; else process.env.ANTHROPIC_API_KEY = savedKey;
  }
});
