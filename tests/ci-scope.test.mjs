import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import test from 'node:test';

const SCRIPT = fileURLToPath(new URL('../scripts/ci-scope.mjs', import.meta.url));

function scratch(t) {
  const dir = mkdtempSync(join(tmpdir(), 'ci-scope-'));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const repo = join(dir, 'repo');
  mkdirSync(repo);
  const git = (...args) => execFileSync('git', ['-c', 'user.name=t', '-c', 'user.email=t@example.invalid', ...args], { cwd: repo, encoding: 'utf8' }).trim();
  git('init', '-q', '-b', 'main');
  const commit = (file, subject) => {
    mkdirSync(dirname(join(repo, file)), { recursive: true });
    writeFileSync(join(repo, file), `${subject}\n`);
    git('add', '--', file);
    git('commit', '-q', '-m', subject);
    return git('rev-parse', 'HEAD');
  };
  let n = 0;
  const gh = (runs, fail = false) => {
    const file = join(dir, `gh-${++n}.cjs`);
    writeFileSync(file, fail
      ? 'process.stderr.write("HTTP 403: Resource not accessible\\n"); process.exit(1);'
      : `process.stdout.write(${JSON.stringify(JSON.stringify(runs))});`);
    return file;
  };
  const plan = env => {
    const out = join(dir, `out-${++n}`);
    writeFileSync(out, '');
    const result = spawnSync(process.execPath, [SCRIPT, 'plan'], { cwd: repo, encoding: 'utf8', env: { PATH: process.env.PATH, SYSTEMROOT: process.env.SYSTEMROOT ?? '', GITHUB_OUTPUT: out, REPOSITORY: 'o/r', REF: 'refs/heads/main', ...env } });
    const outputs = Object.fromEntries(readFileSync(out, 'utf8').split('\n').filter(Boolean).map(line => [line.slice(0, line.indexOf('=')), line.slice(line.indexOf('=') + 1)]));
    return { status: result.status, notice: result.stdout.split('\n').filter(line => line.startsWith('::notice::')), outputs };
  };
  return { commit, gh, plan };
}
const full = sha => ({ databaseId: 11, displayTitle: 'Validate marketplace (full)', headSha: sha });
const slice = sha => ({ databaseId: 12, displayTitle: 'Validate marketplace (slice)', headSha: sha });
const SHARDS = JSON.stringify(Array.from({ length: 16 }, (_, i) => i + 1));

test('a push and a pull request run the slice', t => {
  const { commit, plan } = scratch(t);
  const sha = commit('a.txt', 'feat: a');
  for (const EVENT of ['push', 'pull_request']) {
    const r = plan({ EVENT, SHA: sha });
    assert.equal(r.status, 0);
    assert.deepEqual(r.outputs, { scope: 'slice', run: 'true', windows: '["slice"]' }, EVENT);
    assert.equal(r.notice.length, 1);
  }
});

test('a dispatch is full unless it asks for the slice', t => {
  const { commit, gh, plan } = scratch(t);
  const sha = commit('a.txt', 'feat: a');
  assert.equal(plan({ EVENT: 'workflow_dispatch', SCOPE_INPUT: 'slice', SHA: sha }).outputs.scope, 'slice');
  const r = plan({ EVENT: 'workflow_dispatch', SCOPE_INPUT: '', SHA: sha, CI_SCOPE_GH: gh([full(sha)]) });
  assert.deepEqual(r.outputs, { scope: 'full', run: 'true', windows: SHARDS }, 'a full dispatch never skips');
});

test('a scheduled run skips a commit the last full run validated', t => {
  const { commit, gh, plan } = scratch(t);
  const sha = commit('a.txt', 'feat: a');
  const r = plan({ EVENT: 'schedule', SHA: sha, CI_SCOPE_GH: gh([slice('0'.repeat(40)), full(sha)]) });
  assert.equal(r.outputs.run, 'false');
  assert.match(r.notice[0], /11/);
});

test('a scheduled run skips when only release commits follow the last full run', t => {
  const { commit, gh, plan } = scratch(t);
  const base = commit('plugins/foo/lib.mjs', 'feat(foo): x');
  commit('plugins/foo/.claude-plugin/plugin.json', 'chore(foo): release 1.2.0');
  const head = commit('plugins/foo/.codex-plugin/plugin.json', 'chore(foo): release 1.2.1');
  assert.equal(plan({ EVENT: 'schedule', SHA: head, CI_SCOPE_GH: gh([full(base)]) }).outputs.run, 'false');
});

test('a scheduled run proceeds on a real change, no earlier run, an unknown commit or a failed lookup', t => {
  const { commit, gh, plan } = scratch(t);
  const base = commit('a.txt', 'feat: a');
  const sneaky = commit('plugins/foo/lib.mjs', 'chore(foo): release 9.9.9');
  const head = commit('b.txt', 'fix: b');
  for (const [name, file] of [['a real change', gh([full(base)])], ['a release subject touching code', gh([full(base)])], ['no earlier full run', gh([slice(base)])], ['an unknown commit', gh([full('f'.repeat(40))])]]) {
    const sha = name === 'a release subject touching code' ? sneaky : head;
    const r = plan({ EVENT: 'schedule', SHA: sha, CI_SCOPE_GH: file });
    assert.deepEqual(r.outputs, { scope: 'full', run: 'true', windows: SHARDS }, name);
  }
  const failed = plan({ EVENT: 'schedule', SHA: head, CI_SCOPE_GH: gh([], true) });
  assert.equal(failed.outputs.run, 'true');
  assert.match(failed.notice[0], /HTTP 403/);
});

test('plan without EVENT or GITHUB_OUTPUT is a usage error', () => {
  assert.equal(spawnSync(process.execPath, [SCRIPT, 'plan'], { encoding: 'utf8', env: { PATH: process.env.PATH } }).status, 2);
});

const JOBS = ['scope', 'homelab', 'validate', 'dagents-changes', 'validate-dagents', 'windows', 'windows-dagents'];
const needs = (over = {}, drop = []) => JSON.stringify(Object.fromEntries(JOBS.filter(job => !drop.includes(job)).map(job => [job, { result: over[job] ?? 'success', outputs: {} }])));
const release = env => spawnSync(process.execPath, [SCRIPT, 'release'], { encoding: 'utf8', env: { PATH: process.env.PATH, SCOPE: 'full', REF: 'refs/heads/main', ...env } });

test('release: a full run of main where every job passed releases', () => {
  assert.equal(release({ NEEDS: needs() }).status, 0);
  assert.equal(release({ NEEDS: needs({ homelab: 'skipped' }) }).status, 0, 'the hosted fallback skips homelab');
});

test('release: a slice, another ref, or any job not passing does not', () => {
  const cases = [
    ['slice', { SCOPE: 'slice', NEEDS: needs() }],
    ['a branch', { REF: 'refs/heads/feature', NEEDS: needs() }],
    ['validate failed', { NEEDS: needs({ validate: 'failure' }) }],
    ['a Windows shard cancelled', { NEEDS: needs({ windows: 'cancelled' }) }],
    ['dagents skipped', { NEEDS: needs({ 'validate-dagents': 'skipped' }) }],
    ['homelab failed', { NEEDS: needs({ homelab: 'failure' }) }],
    ['windows-dagents missing', { NEEDS: needs({}, ['windows-dagents']) }],
  ];
  for (const [name, env] of cases) {
    const r = release(env);
    assert.equal(r.status, 1, name);
    assert.ok(r.stdout.trim().length > 0, `${name}: says why`);
  }
  assert.equal(release({ NEEDS: 'not json' }).status, 2);
});
