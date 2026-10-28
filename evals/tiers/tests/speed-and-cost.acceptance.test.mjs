// Acceptance tests for the speed-and-cost spec
// (docs/dforge/specs/2026-10-27-speed-and-cost-design.md): A2's "no rule is
// lost by the split", and A12 and A13 for the eval pipeline. Each test is
// written from the statement's text and reaches the behaviour through the
// public surface: `run-grid.mjs --stage pipeline`, the files it writes, the
// commands it launches, and the skill files the split produced. The `claude`
// CLI is a recording wrapper around the harness's stub, so nothing is spent.
// A14 is a decision rule with no code behind it; it is recorded as
// cannot-test: no-surface in the acceptance report.
import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import { chmodSync, existsSync, mkdirSync, readFileSync, readdirSync, rmSync, writeFileSync } from 'node:fs';
import { join, relative, sep } from 'node:path';
import { after, test } from 'node:test';
import { fileURLToPath } from 'node:url';
import { PLAN, fixture, modes } from './fixture.mjs';

const REPO = fileURLToPath(new URL('../../../', import.meta.url));
const GRID = fileURLToPath(new URL('../run-grid.mjs', import.meta.url));
const BASE = process.env.SPEED_AND_COST_BASE ?? 'e6f88a653e365585ad446e3bbe505e4dc4155819';

const git = (cwd, ...args) => execFileSync('git', ['-c', 'user.name=acceptance', '-c', 'user.email=acceptance@example.invalid', ...args], { cwd, encoding: 'utf8' });
const baseKnown = () => spawnSync('git', ['cat-file', '-e', `${BASE}^{commit}`], { cwd: REPO }).status === 0;

// ---------------------------------------------------------------- A2
// Every sentence of a split skill's SKILL.md before the split is still in the
// skill or its references after it (link targets aside: a moved sentence's
// relative links change with its directory). One sentence was reworded on
// purpose to point at the reference that now holds the table it names.
const norm = s => s.replace(/\]\([^)]*\)/g, ']').replace(/\r/g, '').replace(/\s+/g, ' ').trim();
const REWORDED = ['escalated inline -> subagent` ledger line, and the Recovery table below says what to do with it.'];
// Sentences the main branch's "review light plans once" change removed or
// reworded in writing-plans after BASE; the split cannot have lost them.
const REMOVED = [
  '- **Once the plan is reviewed** (at depth light, once it is linted):',
  'Before each round `<r>`, copy the plan to `<workspace>/plan-round-<r>.md`.',
  "At depth light (step 1's line) skip `scripts/codex-gate`:",
  'no seat runs, so run only `scripts/review-route PLAN_FILE --plan-round 1`.',
  'Otherwise run `scripts/codex-gate` (say its line aloud when it ends `source=probe`), then `scripts/review-route PLAN_FILE --plan-round <r>`, and review with the seat it prints, using [plan-reviewer-prompt.md].',
  '- **`primary=none`** (`reason=depth-light`, round 1 of a light plan).',
  'dispatch no seat, skip step 3, and record the skip in step 4.',
  '1 at standard, so round 1 is the only round, and 0 at light, so none runs.',
  'At depth light no review ran:',
  'write `**Plan review:** <YYYY-MM-DD> — skipped (depth light)` in the same place, and `plan-lint` accepts it.',
];
const SPLIT = ['brainstorming', 'executing-plans', 'finishing-a-development-branch', 'subagent-driven-development', 'writing-plans', 'writing-skills'];

for (const skill of SPLIT) {
  test(`A2: no sentence of ${skill}/SKILL.md is lost by the split`, { skip: baseKnown() ? false : `base ${BASE} is not in this repository` }, () => {
    const dir = join(REPO, 'plugins/dforge/skills', skill);
    const old = git(REPO, 'show', `${BASE}:plugins/dforge/skills/${skill}/SKILL.md`);
    let now = readFileSync(join(dir, 'SKILL.md'), 'utf8');
    if (existsSync(join(dir, 'references'))) {
      for (const f of readdirSync(join(dir, 'references'), { recursive: true }).filter(f => f.endsWith('.md'))) now += '\n' + readFileSync(join(dir, 'references', f), 'utf8');
    }
    const hay = norm(now);
    const sentences = norm(old.replace(/\n\n/g, ' ¶ ')).split(/(?<=[.!?:]) |¶/).map(s => s.trim()).filter(s => s.length > 25);
    assert.ok(sentences.length > 100, `only ${sentences.length} sentences were read from the base skill`);
    const lost = sentences.filter(s => !hay.includes(s) && !REWORDED.includes(s) && !REMOVED.includes(s));
    assert.deepEqual(lost, []);
  });
}

// ---------------------------------------------------------------- A12, A13
const fx = fixture();
after(() => rmSync(fx.top, { recursive: true, force: true }));

const hostHome = join(fx.top, 'host-home');
const hostConfig = join(fx.top, 'host-config');
const hostProject = join(fx.top, 'host-project');
for (const dir of [hostHome, hostConfig, hostProject, join(hostHome, '.claude')]) mkdirSync(dir, { recursive: true });
writeFileSync(join(hostConfig, '.credentials.json'), '{"login":true}');
writeFileSync(join(hostConfig, 'settings.json'), '{"model":"owner-choice"}');
writeFileSync(join(hostHome, '.claude', 'settings.json'), '{"owner":"settings"}');

const realStub = process.env.TIER_EVAL_CLAUDE;
const rec = join(fx.top, 'recorded');
mkdirSync(rec);
const wrapper = join(fx.top, 'claude-recorder');
writeFileSync(wrapper, `#!/bin/sh\nd="${rec}/$$"\nmkdir -p "$d"\npwd > "$d/cwd"\nprintf '%s\\n' "$@" > "$d/args"\nenv > "$d/env"\nexec "${realStub}" "$@"\n`);
chmodSync(wrapper, 0o755);

const arms = JSON.parse(readFileSync(join(fx.data, 'arms.json'), 'utf8'));
writeFileSync(join(fx.data, 'arms.json'), JSON.stringify({ ...arms, pipeline: { baseline: fx.planned, candidate: fx.greet } }));
writeFileSync(join(fx.data, 'cases/pipeline.tsv'), `case\tplan\ttask\tbase\tfixRounds\np-acceptance-t1\t${PLAN}\t1\t${fx.planned}\t1\n`);

const tree = dir => existsSync(dir) ? readdirSync(dir, { recursive: true }).sort() : [];
const grid = rep => spawnSync(process.execPath, [GRID, '--stage', 'pipeline', '--rep', String(rep)], {
  cwd: fx.repo,
  encoding: 'utf8',
  env: {
    ...process.env,
    TIER_EVAL_JOBS: '1',
    TIER_EVAL_CLAUDE: wrapper,
    HOME: hostHome,
    CLAUDE_CONFIG_DIR: hostConfig,
    CLAUDE_PROJECT_DIR: hostProject,
    DFORGE_BUDGET: '12345',
    DCC_SENTINEL: 'host-dcc',
    CLAUDE_CODE_SESSION_ID: 'host-session',
  },
});
const tsv = file => {
  const [header, ...lines] = readFileSync(file, 'utf8').split('\n').filter(Boolean);
  const keys = header.split('\t');
  return { header, rows: lines.map(line => Object.fromEntries(line.split('\t').map((v, i) => [keys[i], v]))) };
};
const calls = () => readdirSync(rec).sort().map(id => ({
  id,
  cwd: readFileSync(join(rec, id, 'cwd'), 'utf8').trim(),
  args: readFileSync(join(rec, id, 'args'), 'utf8').split('\n').filter(Boolean),
  env: Object.fromEntries(readFileSync(join(rec, id, 'env'), 'utf8').split('\n').filter(l => l.includes('=')).map(l => [l.slice(0, l.indexOf('=')), l.slice(l.indexOf('=') + 1)])),
}));
const flag = (call, name) => call.args[call.args.indexOf(name) + 1];

const reposBefore = { status: git(fx.repo, 'status', '--porcelain', '--untracked-files=all'), worktrees: git(fx.repo, 'worktree', 'list'), refs: git(fx.repo, 'for-each-ref') };
const homeBefore = tree(hostHome);
const configBefore = tree(hostConfig);
const projectBefore = tree(hostProject);

modes(fx.stub, 'loop');
const run1 = grid(1);
const first = calls();

test('A12: the pipeline stage replays one case end to end and exits 0', () => {
  assert.equal(run1.status, 0, run1.stderr);
  assert.match(run1.stdout, /run-grid stage=pipeline rep=1 ran=4 remaining=0/);
});

test('A12: results/pipeline.tsv has the pipeline columns and one row per arm and run', () => {
  const file = join(fx.data, 'results/pipeline.tsv');
  assert.ok(existsSync(file));
  const { header, rows } = tsv(file);
  assert.equal(header, 'rep\tcase\tarm\trun\toutcome\tcostUsd\tseconds\tdispatches\tfixRounds\tdetail');
  assert.deepEqual(rows.map(r => [r.case, r.arm.split('@')[0], r.run]), [
    ['p-acceptance-t1', 'baseline', '1'], ['p-acceptance-t1', 'baseline', '2'],
    ['p-acceptance-t1', 'candidate', '1'], ['p-acceptance-t1', 'candidate', '2'],
  ]);
  assert.deepEqual(rows.map(r => r.arm.split('@')[1]), [fx.planned, fx.planned, fx.greet, fx.greet].map(sha => sha.slice(0, 7)));
});

test('A12: each run records pass, costUsd, wall time, dispatch count and fix rounds', () => {
  const { rows } = tsv(join(fx.data, 'results/pipeline.tsv'));
  for (const r of rows) {
    assert.equal(r.outcome, 'PASS');
    assert.equal(r.costUsd, '0.5');
    assert.match(r.seconds, /^\d+$/);
    assert.equal(r.dispatches, '2');
    assert.equal(r.fixRounds, '1');
  }
});

test('A12: a session that never finishes the task is recorded as a failure, not a pass', () => {
  modes(fx.stub, 'loopstop');
  const run2 = grid(2);
  assert.equal(run2.status, 0, run2.stderr);
  const { rows } = tsv(join(fx.data, 'results/pipeline.tsv'));
  const second = rows.filter(r => r.rep === '2');
  assert.equal(second.length, 4);
  for (const r of second) {
    assert.equal(r.outcome, 'FAIL');
    assert.equal(r.fixRounds, '0');
    assert.equal(r.dispatches, '2');
  }
  assert.equal(rows.filter(r => r.rep === '1' && r.outcome === 'PASS').length, 4);
});

test('A12: each arm runs under its own plugin directory, one session per run', () => {
  assert.equal(first.length, 4);
  const dirs = first.map(c => flag(c, '--plugin-dir'));
  const refs = [fx.planned, fx.planned, fx.greet, fx.greet].map(sha => sha.slice(0, 7));
  dirs.forEach((dir, i) => {
    assert.ok(dir.endsWith(`${sep}arms${sep}${refs[i]}${sep}plugins${sep}dforge`) || dir.endsWith(`/arms/${refs[i]}/plugins/dforge`), dir);
    assert.ok(existsSync(join(dir, 'marker.txt')), `${dir} holds the plugin of its ref`);
  });
  assert.notEqual(dirs[0], dirs[2]);
  assert.match(readFileSync(join(rec, first[0].id, 'args'), 'utf8'), /^-p$/m);
});

test('A12: the existing results file is not written by the pipeline stage', () => {
  assert.equal(existsSync(join(fx.data, 'results/results.tsv')), false);
});

// A13: nothing outside the eval's own temporary root.
const root = join(fx.work, 'pipeline');
const inside = path => { const rel = relative(root, path); return rel !== '' && !rel.startsWith('..') && !rel.split(sep).includes('..'); };

test('A13: every run works in a directory under the eval root', () => {
  assert.equal(first.length, 4);
  for (const c of first) assert.ok(inside(c.cwd), `cwd ${c.cwd} is outside ${root}`);
  assert.ok(first.every(c => c.cwd !== fx.repo && c.cwd !== hostProject));
});

test('A13: every run loads its plugin from a directory under the eval root', () => {
  for (const c of first) assert.ok(inside(flag(c, '--plugin-dir')), `plugin ${flag(c, '--plugin-dir')} is outside ${root}`);
});

test('A13: every run has its own HOME, XDG, config and temp directories under the eval root', () => {
  for (const c of first) {
    for (const key of ['HOME', 'XDG_CONFIG_HOME', 'XDG_CACHE_HOME', 'XDG_DATA_HOME', 'XDG_STATE_HOME', 'CLAUDE_CONFIG_DIR', 'TMPDIR']) {
      assert.ok(c.env[key], `${key} is unset`);
      assert.ok(inside(c.env[key]), `${key}=${c.env[key]} is outside ${root}`);
    }
    assert.notEqual(c.env.HOME, hostHome);
  }
  assert.equal(new Set(first.map(c => c.env.HOME)).size, 4, 'two runs share a HOME');
});

test('A13: nothing of the host session leaks into a run', () => {
  for (const c of first) {
    assert.equal(c.env.CLAUDE_PROJECT_DIR, undefined);
    assert.equal(c.env.DFORGE_BUDGET, undefined);
    assert.equal(c.env.DCC_SENTINEL, undefined);
    assert.notEqual(c.env.CLAUDE_CODE_SESSION_ID, 'host-session');
    for (const [key, value] of Object.entries(c.env)) {
      if (key === 'PATH') continue;
      assert.ok(!value.includes(hostHome) && !value.includes(hostConfig) && !value.includes(hostProject), `${key}=${value} names a host directory`);
    }
  }
});

test('A13: the owner credentials are copied in and the owner settings are not', () => {
  const dirs = new Set(first.map(c => c.env.CLAUDE_CONFIG_DIR));
  assert.equal(dirs.size, 4);
  for (const dir of dirs) {
    assert.ok(existsSync(join(dir, '.credentials.json')));
    assert.equal(existsSync(join(dir, 'settings.json')), false);
  }
});

test('A13: the run leaves the host home, config, project and source repository untouched', () => {
  assert.deepEqual(tree(hostHome), homeBefore);
  assert.deepEqual(tree(hostConfig), configBefore);
  assert.deepEqual(tree(hostProject), projectBefore);
  assert.equal(git(fx.repo, 'status', '--porcelain', '--untracked-files=all'), reposBefore.status);
  assert.equal(git(fx.repo, 'worktree', 'list'), reposBefore.worktrees);
  assert.equal(git(fx.repo, 'for-each-ref'), reposBefore.refs);
});
