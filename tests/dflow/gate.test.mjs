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

test('a draft under docs/dflow leaves a gate pass clean, whatever its name', t => {
  const root = makeProject(t, { config: CONFIG });
  write(root, 'lint.mjs', '\n');
  write(root, 'suite.mjs', '\n');
  write(root, 'docs/dflow/my notes ü.md', 'draft\n');
  assert.equal(dflow(root, ['gate']).status, 0);
  assert.equal(JSON.parse(dflow(root, ['status', '--json']).stdout).gates.stale, false);
});

test('an untracked file under docs/dflow that is not a document leaves the pass dirty', t => {
  const root = makeProject(t, { config: CONFIG });
  write(root, 'lint.mjs', '\n');
  write(root, 'suite.mjs', '\n');
  write(root, 'docs/dflow/drafts/helper.sh', 'exit 0\n');
  assert.equal(dflow(root, ['gate']).status, 0);
  assert.equal(JSON.parse(dflow(root, ['status', '--json']).stdout).gates.stale, true);
});

test('a piped gate fails when an earlier stage fails', t => {
  const root = makeProject(t, { config: { gates: [{ name: 'test', cmd: 'node suite.mjs 2>&1 | tail -1' }] } });
  write(root, 'suite.mjs', 'console.log("1 failed"); process.exit(1)\n');
  const failed = dflow(root, ['gate']);
  assert.equal(failed.status, 1, failed.stdout);
  assert.match(failed.stdout, /^FAIL  test: `node suite\.mjs 2>&1 \| tail -1` exited 1/m);
});

test('a gate with green passes only when its output matches', t => {
  const root = makeProject(t, { config: { gates: [
    { name: 'matches', cmd: `node -e "console.log('pass 3')"`, green: '^pass [1-9]' },
    { name: 'empty', cmd: `node -e "console.log('pass 0')"`, green: '^pass [1-9]' },
  ] } });
  const r = dflow(root, ['gate']);
  assert.equal(r.status, 1);
  assert.match(r.stdout, /^ok {4}matches/m);
  assert.match(r.stdout, /^FAIL {2}empty: output does not match green \/\^pass \[1-9\]\//m);
});

test('a gate without green is unchanged, and a bad green fails without running', t => {
  const root = makeProject(t, { config: { gates: [
    { name: 'plain', cmd: `node -e "process.exit(0)"` },
    { name: 'bad', cmd: `node -e "require('fs').writeFileSync('ran', '')"`, green: '(' },
    { name: 'typed', cmd: `node -e "process.exit(0)"`, green: 5 },
  ] } });
  const r = dflow(root, ['gate']);
  assert.equal(r.status, 1);
  assert.match(r.stdout, /^ok {4}plain/m);
  assert.match(r.stdout, /^FAIL {2}bad: green is not a valid pattern/m);
  assert.match(r.stdout, /^FAIL {2}typed: green is not a valid pattern/m);
  assert.equal(fs.existsSync(path.join(root, 'ran')), false, 'a bad pattern does not run its command');
});

test('green matches any line of the output, not only the first', t => {
  const root = makeProject(t, { config: { gates: [
    { name: 'summary', cmd: `node -e "console.log('header'); console.log('pass 3')"`, green: '^pass [1-9]' },
  ] } });
  const r = dflow(root, ['gate']);
  assert.equal(r.status, 0);
  assert.match(r.stdout, /^ok {4}summary/m);
});
