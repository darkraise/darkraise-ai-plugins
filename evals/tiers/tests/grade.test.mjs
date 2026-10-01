import assert from 'node:assert/strict';
import { existsSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { after, test } from 'node:test';
import { fixture } from './fixture.mjs';

const fx = fixture();
after(() => rmSync(fx.top, { recursive: true, force: true }));
const { git } = await import('../lib/sh.mjs');
const { snapshot } = await import('../lib/snapshot.mjs');
const { changedFiles, outcome, overlayTests, runTests, statusWord } = await import('../lib/grade.mjs');

test('snapshot is a one-commit repository of that tree, without the dropped paths', () => {
  const dir = join(fx.top, 'snap');
  const initial = snapshot(fx.greet, dir, ['docs/superpowers']);
  assert.equal(git(['rev-list', '--count', 'HEAD'], { cwd: dir }).trim(), '1');
  assert.equal(git(['rev-parse', 'HEAD'], { cwd: dir }).trim(), initial);
  assert.deepEqual([existsSync(join(dir, 'src/greet.sh')), existsSync(join(dir, 'src/shout.sh')), existsSync(join(dir, 'docs/superpowers'))], [true, false, false]);
  assert.throws(() => snapshot('no-such-commit', join(fx.top, 'bad')), /snapshot no-such-commit/);
});

test('changedFiles sees committed, uncommitted and untracked changes but not the scratch directory', () => {
  const dir = join(fx.top, 'changed');
  const initial = snapshot(fx.greet, dir);
  writeFileSync(join(dir, 'src/greet.sh'), 'echo changed\n');
  git(['-c', 'user.name=t', '-c', 'user.email=t@example.invalid', 'commit', '-q', '-am', 'edit'], { cwd: dir });
  writeFileSync(join(dir, 'tests/greet.test.sh'), 'true\n');
  writeFileSync(join(dir, 'new.txt'), 'x\n');
  mkdirSync(join(dir, '.superpowers/sdd/eval'), { recursive: true });
  writeFileSync(join(dir, '.superpowers/sdd/eval/brief.md'), 'x\n');
  assert.deepEqual(changedFiles(dir, initial), ['new.txt', 'src/greet.sh', 'tests/greet.test.sh']);
});

test('overlayTests restores the historical test and runTests reports the first failure', async () => {
  const dir = join(fx.top, 'overlay');
  snapshot(fx.greet, dir);
  writeFileSync(join(dir, 'tests/greet.test.sh'), 'true\n');
  assert.equal(overlayTests(dir, fx.greet, ['tests/greet.test.sh']), true);
  assert.match(readFileSync(join(dir, 'tests/greet.test.sh'), 'utf8'), /"hello"/);
  assert.equal(overlayTests(dir, fx.planned, ['tests/greet.test.sh']), false);
  assert.deepEqual(await runTests(dir, ['tests/greet.test.sh']), { pass: true, failed: null });
  writeFileSync(join(dir, 'src/greet.sh'), 'echo nope\n');
  assert.deepEqual(await runTests(dir, ['tests/greet.test.sh']), { pass: false, failed: 'tests/greet.test.sh' });
});

test('outcome follows the grading table', () => {
  const ok = { testsPass: true, outside: [], status: 'DONE', cutShort: false };
  assert.equal(outcome(ok), 'PASS');
  assert.equal(outcome({ ...ok, status: 'DONE_WITH_CONCERNS' }), 'PASS');
  assert.equal(outcome({ ...ok, testsPass: false }), 'FAIL');
  assert.equal(outcome({ ...ok, outside: ['x'] }), 'FAIL');
  assert.equal(outcome({ ...ok, status: 'BLOCKED' }), 'BLOCKED');
  assert.equal(outcome({ ...ok, status: 'NEEDS_CONTEXT' }), 'BLOCKED');
  assert.equal(outcome({ ...ok, status: null }), 'BLOCKED');
  assert.equal(outcome({ ...ok, cutShort: true }), 'BLOCKED');
  assert.equal(statusWord('- **Status:** DONE_WITH_CONCERNS\nnot BLOCKED'), 'DONE_WITH_CONCERNS');
  assert.equal(statusWord('all finished'), null);
});
