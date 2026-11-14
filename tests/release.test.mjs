import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { cpSync, mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import test from 'node:test';

const script = resolve(dirname(fileURLToPath(import.meta.url)), '../scripts/release.mjs');

function repo(t) {
  const dir = mkdtempSync(resolve(tmpdir(), 'release-'));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const git = (...args) => execFileSync('git', args, { cwd: dir, encoding: 'utf8' }).trim();
  git('init', '-q', '-b', 'main');
  git('config', 'user.email', 'a@b.c');
  git('config', 'user.name', 'a');
  mkdirSync(resolve(dir, '.claude-plugin'), { recursive: true });
  mkdirSync(resolve(dir, 'plugins/foo/.claude-plugin'), { recursive: true });
  mkdirSync(resolve(dir, 'scripts'), { recursive: true });
  cpSync(script, resolve(dir, 'scripts/release.mjs'));
  writeFileSync(resolve(dir, '.claude-plugin/marketplace.json'), JSON.stringify({ plugins: [{ name: 'foo' }] }));
  const commit = (file, subject) => {
    writeFileSync(resolve(dir, 'plugins/foo', file), subject);
    git('add', '-A');
    git('commit', '-q', '-m', subject);
    return git('rev-parse', 'HEAD');
  };
  const dryRun = () => execFileSync(process.execPath, ['scripts/release.mjs', '--dry-run'], { cwd: dir, encoding: 'utf8' });
  return { git, commit, dryRun, dir };
}

test('the first release of a plugin with no tag is its current version at HEAD, not its first commit', t => {
  const { git, commit, dryRun } = repo(t);
  commit('.claude-plugin/plugin.json', '{"version":"1.0.0"}');
  commit('lib.mjs', 'feat(foo): the rest');
  const head = git('rev-parse', '--short=7', 'HEAD');
  const out = dryRun();
  assert.match(out, new RegExp(`^tag foo-v1\\.0\\.0 at ${head}$`, 'm'));
  assert.doesNotMatch(out, /^release foo/m);
});

test('commits after that first tag make the next release, and none leaves nothing to do', t => {
  const { git, commit, dryRun } = repo(t);
  commit('.claude-plugin/plugin.json', '{"version":"1.0.0"}');
  commit('lib.mjs', 'feat(foo): the rest');
  git('tag', '-a', 'foo-v1.0.0', '-m', 'first');
  assert.match(dryRun(), /^Nothing to tag or release\.$/m);
  commit('more.mjs', 'fix(foo): one more');
  const out = dryRun();
  assert.match(out, /^release foo 1\.0\.0 -> 1\.0\.1$/m);
  assert.doesNotMatch(out, /the rest/);
});
