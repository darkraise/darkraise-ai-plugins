import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { dflow, makeProject, write } from './helpers.mjs';

const gateOf = (name, cmd, extra = {}) => ({ name, cmd, ...extra });

test('A21: a gate with green fails when the command exits 0 and its output does not match, naming the pattern', t => {
  const root = makeProject(t, { config: { gates: [gateOf('suite', 'node suite.mjs', { green: '^pass [1-9]' })] } });
  write(root, 'suite.mjs', 'console.log("tests 0\\npass 0\\nfail 0");\n');
  const result = dflow(root, ['gate', 'suite']);
  assert.equal(result.status, 1, result.stdout);
  assert.match(result.stdout, /^FAIL {2}suite:/m);
  assert.ok(result.stdout.includes('^pass [1-9]'), `the failure names the pattern:\n${result.stdout}`);
  assert.doesNotMatch(result.stdout, /^ok {4}suite/m);
});

test('A21: a gate with green passes when the output matches, the pattern read per line', t => {
  const root = makeProject(t, { config: { gates: [gateOf('suite', 'node suite.mjs', { green: '^pass [1-9]' })] } });
  write(root, 'suite.mjs', 'console.log("tests 3\\npass 3\\nfail 0");\n');
  const result = dflow(root, ['gate', 'suite']);
  assert.equal(result.status, 0, result.stdout);
  assert.match(result.stdout, /^ok {4}suite/m);
});

test('A21: a gate with green still fails when its command exits non-zero and the output matches', t => {
  const root = makeProject(t, { config: { gates: [gateOf('suite', 'node suite.mjs', { green: '^pass [1-9]' })] } });
  write(root, 'suite.mjs', 'console.log("pass 3"); process.exit(1);\n');
  const result = dflow(root, ['gate', 'suite']);
  assert.equal(result.status, 1, result.stdout);
  assert.match(result.stdout, /^FAIL {2}suite:/m);
});

test('A22: a gate without green passes and fails as before', t => {
  const root = makeProject(t, { config: { gates: [gateOf('quiet', 'node quiet.mjs'), gateOf('broken', 'node broken.mjs')] } });
  write(root, 'quiet.mjs', '');
  write(root, 'broken.mjs', 'console.error("meter is NaN"); process.exit(1);\n');
  const passed = dflow(root, ['gate', 'quiet']);
  assert.equal(passed.status, 0, passed.stdout);
  assert.match(passed.stdout, /^ok {4}quiet/m);
  const failed = dflow(root, ['gate', 'broken']);
  assert.equal(failed.status, 1, failed.stdout);
  assert.match(failed.stdout, /^FAIL {2}broken: `node broken\.mjs` exited 1/m);
  assert.match(failed.stdout, /meter is NaN/);
});

test('A22: a gate whose green is not a string or not a valid pattern fails without running its command', t => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'dflow-green-'));
  t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
  const ran = path.join(dir, 'ran.txt');
  const command = label => `node -e "require('fs').appendFileSync(process.argv[1], process.argv[2] + '\\n')" "${ran}" ${label}`;
  const bad = { number: 5, boolean: true, array: ['x'], object: {}, null: null, 'an unterminated group': '(', 'an unterminated class': '[' };
  const root = makeProject(t, { config: { gates: Object.entries(bad).map(([label, green]) => gateOf(label.replace(/\W+/g, '_'), command(label.replace(/\W+/g, '_')), { green })) } });
  for (const label of Object.keys(bad)) {
    const name = label.replace(/\W+/g, '_');
    const result = dflow(root, ['gate', name]);
    assert.equal(result.status, 1, `${label}:\n${result.stdout}`);
    assert.match(result.stdout, new RegExp(`^FAIL {2}${name}:`, 'm'), label);
  }
  assert.equal(fs.existsSync(ran), false, `a command ran: ${fs.existsSync(ran) ? fs.readFileSync(ran, 'utf8') : ''}`);
});

test('A22: control, a valid green lets its command run', t => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'dflow-green-'));
  t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
  const ran = path.join(dir, 'ran.txt');
  const root = makeProject(t, { config: { gates: [gateOf('ctl', `node -e "require('fs').writeFileSync(process.argv[1], 'x'); console.log('pass 1')" "${ran}"`, { green: '^pass 1$' })] } });
  const result = dflow(root, ['gate', 'ctl']);
  assert.equal(result.status, 0, result.stdout);
  assert.equal(fs.existsSync(ran), true);
});
