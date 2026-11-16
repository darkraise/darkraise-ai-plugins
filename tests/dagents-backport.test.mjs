import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import test from 'node:test';

const script = fileURLToPath(new URL('../scripts/dagents-backport.mjs', import.meta.url));
const env = { ...process.env, GIT_AUTHOR_NAME: 't', GIT_AUTHOR_EMAIL: 't@e', GIT_COMMITTER_NAME: 't', GIT_COMMITTER_EMAIL: 't@e' };

function fixture(t) {
  const dir = mkdtempSync(join(tmpdir(), 'backport-'));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const git = (...args) => spawnSync('git', args, { cwd: dir, encoding: 'utf8', env, timeout: 30000 }).stdout.trim();
  const put = (path, text) => { mkdirSync(join(dir, path, '..'), { recursive: true }); writeFileSync(join(dir, path), text); };
  const commit = (message, files) => { for (const [p, text] of Object.entries(files)) put(p, text); git('add', '-A'); git('commit', '-q', '-m', message); return git('rev-parse', '--short=7', 'HEAD'); };
  git('init', '-q', '-b', 'main');
  commit('init', { 'plugins/dforge/a.sh': 'a\n' });
  git('tag', 'dforge-v4.17.1');
  const c1 = commit('fix(dforge): fix a', { 'plugins/dforge/a.sh': 'a2\n' });
  const c2 = commit('feat(dforge): add b', { 'plugins/dforge/b.sh': 'b\n' });
  const c3 = commit('fix(dforge): fix b', { 'plugins/dforge/b.sh': 'b2\n', 'plugins/dforge/tests/b.test.sh': 't\n' });
  commit('docs: readme', { 'README.md': 'r\n' });
  const port = commit('fix(dagents): fix a', { 'plugins/dagents/a.sh': 'a2\n' });
  return { dir, c1, c2, c3, port };
}
const run = (dir, ...args) => spawnSync(process.execPath, [script, ...args], { cwd: dir, encoding: 'utf8', env, timeout: 30000 });
const register = (rows) => ['# r', '', '**Source:** t', '**Covers:** -', '', '| # | Item | Assigned | Acceptance | State | Note |', '|---|---|---|---|---|---|',
  ...rows.map(([id, item, state, note]) => `| ${id} | ${item} | - | - | ${state} | ${note} |`), ''].join('\n');

test('rows lists the commits touching plugins/dforge in source order', t => {
  const f = fixture(t);
  const out = run(f.dir, 'rows', 'dforge-v4.17.1', 'HEAD');
  assert.equal(out.status, 0, out.stderr);
  assert.deepEqual(out.stdout.trim().split('\n'), [`${f.c1} fix(dforge): fix a`, `${f.c2} feat(dforge): add b`, `${f.c3} fix(dforge): fix b`]);
});

test('five-only checks every non-test path against the tag', t => {
  const f = fixture(t);
  assert.equal(run(f.dir, 'five-only', f.c1).status, 1);
  assert.equal(run(f.dir, 'five-only', f.c2).status, 0);
  assert.equal(run(f.dir, 'five-only', f.c3).status, 0);
  const git = (...args) => spawnSync('git', args, { cwd: f.dir, encoding: 'utf8', env, timeout: 30000 }).stdout.trim();
  writeFileSync(join(f.dir, 'plugins/dforge/tests/a.test.sh'), 't\n');
  git('add', '-A');
  git('commit', '-q', '-m', 'fix(dforge): steady a test');
  assert.equal(run(f.dir, 'five-only', git('rev-parse', '--short=7', 'HEAD')).status, 1, 'a commit touching only tests is triaged by hand');
});

test('audit refuses a port commit that is not on the branch', t => {
  const f = fixture(t);
  const git = (...args) => spawnSync('git', args, { cwd: f.dir, encoding: 'utf8', env, timeout: 30000 }).stdout.trim();
  git('checkout', '-q', '-b', 'side');
  writeFileSync(join(f.dir, 'plugins/dagents/a.sh'), 'a3\n');
  git('commit', '-q', '-a', '-m', 'fix(dagents): fix a again');
  const side = git('rev-parse', '--short=7', 'HEAD');
  git('checkout', '-q', 'main');
  const file = join(f.dir, 'reg.md');
  writeFileSync(file, register([
    [1, `${f.c1} fix(dforge): fix a`, 'done', `port ${side}; fail@parent pass@port`],
    [2, `${f.c2} feat(dforge): add b`, 'n/a', 'feature: adds b.sh'],
    [3, `${f.c3} fix(dforge): fix b`, 'n/a', '5-only'],
  ]));
  assert.match(run(f.dir, 'audit', file, 'HEAD').stdout, new RegExp(`row 1: port ${side} is not on this branch`));
});

test('audit accepts a finished register and names each problem', t => {
  const f = fixture(t);
  const file = join(f.dir, 'reg.md');
  const good = [
    [1, `${f.c1} fix(dforge): fix a`, 'done', `port ${f.port}; fail@parent pass@port`],
    [2, `${f.c2} feat(dforge): add b`, 'n/a', 'feature: adds b.sh'],
    [3, `${f.c3} fix(dforge): fix b`, 'n/a', '5-only'],
  ];
  writeFileSync(file, register(good));
  assert.equal(run(f.dir, 'audit', file, 'HEAD').status, 0);

  writeFileSync(file, register(good.slice(0, 2)));
  const missing = run(f.dir, 'audit', file, 'HEAD');
  assert.equal(missing.status, 1);
  assert.match(missing.stdout, new RegExp(`${f.c3}.*not a row`));
  assert.equal(run(f.dir, 'audit', file, 'HEAD', '--through', '2').status, 0);

  writeFileSync(file, register([[1, `${f.c1} fix(dforge): fix a`, 'n/a', '5-only'], ...good.slice(1)]));
  assert.match(run(f.dir, 'audit', file, 'HEAD').stdout, /row 1: 5-only fails the path check/);

  writeFileSync(file, register([[1, `${f.c1} fix(dforge): fix a`, 'done', 'port 0000000; fail@parent pass@port'], ...good.slice(1)]));
  assert.match(run(f.dir, 'audit', file, 'HEAD').stdout, /row 1: port 0000000 is not a dagents commit/);

  writeFileSync(file, register([[1, `${f.c1} fix(dforge): fix a`, 'open', '-'], ...good.slice(1)]));
  assert.match(run(f.dir, 'audit', file, 'HEAD').stdout, /row 1: not finished/);

  writeFileSync(file, register([good[0], [2, `${f.c2} feat(dforge): add b`, 'n/a', 'feature'], good[2]]));
  assert.match(run(f.dir, 'audit', file, 'HEAD').stdout, /row 2: feature needs a reason/);
});
