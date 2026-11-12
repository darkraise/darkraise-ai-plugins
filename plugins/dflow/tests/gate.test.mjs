import assert from 'node:assert/strict';
import test from 'node:test';
import { dflow, git, makeProject, write } from './helpers.mjs';

const CONFIG = { gates: [{ name: 'lint', cmd: 'node lint.mjs' }, { name: 'test', cmd: 'node suite.mjs' }] };

test('gate prints failures only and records a full run with the head commit', t => {
  const root = makeProject(t, { config: CONFIG });
  write(root, 'lint.mjs', 'console.log("lint noise")\n');
  write(root, 'suite.mjs', 'console.log("3 passed"); console.error("1 failed: meter is NaN"); process.exit(1)\n');
  const failed = dflow(root, ['gate']);
  assert.equal(failed.status, 1);
  assert.match(failed.stdout, /^ok    lint \(/m);
  assert.doesNotMatch(failed.stdout, /lint noise/);
  assert.match(failed.stdout, /^FAIL  test: `node suite\.mjs` exited 1/m);
  assert.match(failed.stdout, /1 failed: meter is NaN/);
  let gates = JSON.parse(dflow(root, ['status', '--json']).stdout).gates;
  assert.deepEqual([gates.ok, gates.failed, gates.stale], [false, ['test'], false]);

  write(root, 'suite.mjs', 'process.exit(0)\n');
  assert.equal(dflow(root, ['gate']).status, 0);
  gates = JSON.parse(dflow(root, ['status', '--json']).stdout).gates;
  assert.deepEqual([gates.ok, gates.sha], [true, git(root, 'rev-parse', 'HEAD')]);

  git(root, 'commit', '-q', '--allow-empty', '-m', 'chore: move the head');
  assert.equal(JSON.parse(dflow(root, ['status', '--json']).stdout).gates.stale, true);
});

test('a named subset runs but is not recorded, and an unknown name is refused', t => {
  const root = makeProject(t, { config: CONFIG });
  write(root, 'lint.mjs', '\n');
  assert.equal(dflow(root, ['gate', 'lint']).status, 0);
  assert.equal(JSON.parse(dflow(root, ['status', '--json']).stdout).gates, null);
  assert.match(dflow(root, ['gate', 'build']).stderr, /no gate named build; configured: lint, test/);
});
