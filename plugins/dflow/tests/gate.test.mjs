import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
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

test('a commit or an edit made while the gates run is refused and nothing is recorded', t => {
  const root = makeProject(t, { config: CONFIG });
  write(root, 'lint.mjs', '\n');
  write(root, 'suite.mjs', 'import { execFileSync } from \'node:child_process\';\nexecFileSync(\'git\', [\'commit\', \'-q\', \'--allow-empty\', \'-m\', \'chore: during the gate\']);\n');
  const committed = dflow(root, ['gate']);
  assert.equal(committed.status, 1, committed.stdout);
  assert.match(committed.stdout, /the head commit moved while the gates ran; nothing was recorded/);
  assert.equal(JSON.parse(dflow(root, ['status', '--json']).stdout).gates, null);
  assert.equal(fs.existsSync(path.join(root, '.dflow/gate-history.jsonl')), false);

  write(root, 'suite.mjs', 'import fs from \'node:fs\';\nfs.writeFileSync(\'README.md\', \'# edited\\n\');\n');
  const edited = dflow(root, ['gate']);
  assert.equal(edited.status, 1, edited.stdout);
  assert.match(edited.stdout, /the working tree changed \(README\.md\) while the gates ran; nothing was recorded/);
  assert.equal(JSON.parse(dflow(root, ['status', '--json']).stdout).gates, null);
});

test('a piped gate fails when an earlier stage fails', t => {
  const root = makeProject(t, { config: { gates: [{ name: 'test', cmd: 'node suite.mjs 2>&1 | tail -1' }] } });
  write(root, 'suite.mjs', 'console.log("1 failed"); process.exit(1)\n');
  const failed = dflow(root, ['gate']);
  assert.equal(failed.status, 1, failed.stdout);
  assert.match(failed.stdout, /^FAIL  test: `node suite\.mjs 2>&1 \| tail -1` exited 1/m);
});
