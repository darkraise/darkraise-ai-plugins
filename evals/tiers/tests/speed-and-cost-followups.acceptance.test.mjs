// Acceptance tests for the speed-and-cost-followups spec
// (docs/dforge/specs/2026-10-28-speed-and-cost-followups-design.md): A17 and
// A18 for the eval harness. Each test is written from the statement's text and
// reaches the behaviour through the public surface: `run-grid.mjs --stage
// pipeline` and the environment the `claude` it launches sees (A17), and the
// exported `fixRounds` over a real git history (A18). The `claude` CLI is a
// recording wrapper around the harness's stub, so nothing is spent.
import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import { chmodSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, relative, sep } from 'node:path';
import { after, test } from 'node:test';
import { fileURLToPath } from 'node:url';
import { PLAN, fixture, modes } from './fixture.mjs';

const GRID = fileURLToPath(new URL('../run-grid.mjs', import.meta.url));
const git = (cwd, ...args) => execFileSync('git', ['-c', 'user.name=acceptance', '-c', 'user.email=acceptance@example.invalid', ...args], { cwd, encoding: 'utf8' }).trim();

const fx = fixture();
after(() => rmSync(fx.top, { recursive: true, force: true }));

// ---------------------------------------------------------------- A17
const hostTmp = mkdtempSync(join(tmpdir(), 'followups-host-tmp-'));
after(() => rmSync(hostTmp, { recursive: true, force: true }));
const hostHome = join(fx.top, 'host-home');
const hostConfig = join(fx.top, 'host-config');
for (const dir of [hostHome, hostConfig]) mkdirSync(dir, { recursive: true });

const rec = join(fx.top, 'recorded');
mkdirSync(rec);
const wrapper = join(fx.top, 'claude-recorder');
writeFileSync(wrapper, `#!/bin/sh\nd="${rec}/$$"\nmkdir -p "$d"\nenv > "$d/env"\nexec "${process.env.TIER_EVAL_CLAUDE}" "$@"\n`);
chmodSync(wrapper, 0o755);

const arms = JSON.parse(readFileSync(join(fx.data, 'arms.json'), 'utf8'));
writeFileSync(join(fx.data, 'arms.json'), JSON.stringify({ ...arms, pipeline: { baseline: fx.planned, candidate: fx.greet } }));
writeFileSync(join(fx.data, 'cases/pipeline.tsv'), `case\tplan\ttask\tbase\tfixRounds\np-followups-t1\t${PLAN}\t1\t${fx.planned}\t1\n`);

modes(fx.stub, 'loop');
const run = spawnSync(process.execPath, [GRID, '--stage', 'pipeline', '--rep', '1'], {
  cwd: fx.repo,
  encoding: 'utf8',
  env: {
    ...process.env,
    TIER_EVAL_JOBS: '1',
    TIER_EVAL_CLAUDE: wrapper,
    HOME: hostHome,
    CLAUDE_CONFIG_DIR: hostConfig,
    CLAUDE_CODE_USE_BEDROCK: '1',
    CLAUDE_CODE_USE_VERTEX: '1',
    TMP: hostTmp,
    TEMP: hostTmp,
    TMPDIR: hostTmp,
  },
});
const calls = readdirSync(rec).map(id => Object.fromEntries(readFileSync(join(rec, id, 'env'), 'utf8').split('\n')
  .filter(line => line.includes('=')).map(line => [line.slice(0, line.indexOf('=')), line.slice(line.indexOf('=') + 1)])));
const root = join(fx.work, 'pipeline');
const inside = path => { const rel = relative(root, path); return rel !== '' && !rel.startsWith('..') && !rel.split(sep).includes('..'); };

test('A17: the stage ran four sessions to completion, so the environments below are real', () => {
  assert.equal(run.status, 0, run.stderr);
  assert.equal(calls.length, 4);
});

test('A17: no run sees CLAUDE_CODE_USE_BEDROCK or CLAUDE_CODE_USE_VERTEX from the host', () => {
  for (const env of calls) {
    assert.equal(env.CLAUDE_CODE_USE_BEDROCK, undefined);
    assert.equal(env.CLAUDE_CODE_USE_VERTEX, undefined);
  }
});

test('A17: TMP, TEMP and TMPDIR of every run lie under the eval root, not at the host temp directory', () => {
  for (const env of calls) {
    for (const key of ['TMP', 'TEMP', 'TMPDIR']) {
      assert.ok(env[key], `${key} is unset`);
      assert.ok(inside(env[key]), `${key}=${env[key]} is outside ${root}`);
      assert.notEqual(env[key], hostTmp);
    }
  }
});

// ---------------------------------------------------------------- A18
test('A18: fixRounds counts a commit whose subject contains @@ as one commit', async () => {
  const { fixRounds } = await import('../lib/pipeline-manifest.mjs');
  const commit = (path, message) => {
    mkdirSync(dirname(join(fx.repo, path)), { recursive: true });
    writeFileSync(join(fx.repo, path), `${message}\n`);
    git(fx.repo, 'add', '-A');
    git(fx.repo, 'commit', '-q', '-m', message);
    return git(fx.repo, 'rev-parse', 'HEAD');
  };
  const result = commit('followups/task-a.sh', 'feat: followups task a');
  commit('followups/task-a.sh', 'fix: review round @@ one');
  const merge = commit('followups/task-b.sh', 'feat: followups task b');
  const own = new Set(['feat: followups task a', 'feat: followups task b']);
  assert.equal(fixRounds({ result, merge, allowed: ['followups/task-a.sh'], own }), 1);

  const result2 = commit('followups/task-c.sh', 'feat: followups task c');
  commit('followups/task-c.sh', '@@');
  commit('followups/task-c.sh', 'fix: x@@y@@z');
  const merge2 = commit('followups/task-d.sh', 'feat: followups task d');
  const own2 = new Set(['feat: followups task c', 'feat: followups task d']);
  assert.equal(fixRounds({ result: result2, merge: merge2, allowed: ['followups/task-c.sh'], own: own2 }), 2);
});
