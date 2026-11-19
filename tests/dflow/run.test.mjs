import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { runCommand } from '../../plugins/dflow/lib/run.mjs';

test('a failure behind a pipe fails under a POSIX shell too, and a passing pipe still passes', { skip: process.platform === 'win32' }, async t => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'dflow-run-'));
  t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
  const env = { ...process.env, DFLOW_SHELL: '/bin/sh' };
  const failed = await runCommand('false | cat', { cwd: dir, timeoutSeconds: 30, logFile: path.join(dir, 'log'), env });
  assert.equal(failed.ok, false);
  const passed = await runCommand('echo fine | cat', { cwd: dir, timeoutSeconds: 30, logFile: path.join(dir, 'log'), env });
  assert.deepEqual([passed.ok, passed.output.trim()], [true, 'fine']);
});

test('a background child a command leaves behind gets a SIGTERM and time to clean up', { skip: process.platform === 'win32' }, async t => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'dflow-run-'));
  t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
  const marker = path.join(dir, 'cleaned');
  fs.writeFileSync(path.join(dir, 'child.mjs'), `import fs from 'node:fs';
process.on('SIGTERM', () => { fs.writeFileSync(${JSON.stringify(marker)}, 'clean'); process.exit(0); });
setInterval(() => {}, 1000);
`);
  const result = await runCommand('node child.mjs & sleep 1', { cwd: dir, timeoutSeconds: 30, logFile: path.join(dir, 'log') });
  assert.equal(result.ok, true);
  assert.equal(fs.existsSync(marker), true);
});
