import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { acquireLock } from '../../plugins/dflow/lib/util.mjs';

function lockDir(t) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'dflow-lock-'));
  t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
  return dir;
}

function deadPid() {
  const result = spawnSync(process.execPath, ['-e', 'process.stdout.write(String(process.pid))'], { encoding: 'utf8' });
  return Number(result.stdout);
}

test('a lock whose holder is gone is taken at once, however new it is', t => {
  const file = path.join(lockDir(t), 'x.lock');
  fs.writeFileSync(file, String(deadPid()));
  const release = acquireLock(file, { waitMs: 0, staleMs: 120000 });
  assert.equal(typeof release, 'function');
  assert.equal(fs.readFileSync(file, 'utf8'), String(process.pid));
  release();
  assert.equal(fs.existsSync(file), false);
});

test('a lock whose holder is running is not taken, and its owner can still release it', t => {
  const file = path.join(lockDir(t), 'x.lock');
  const first = acquireLock(file, { waitMs: 0 });
  assert.equal(typeof first, 'function');
  assert.equal(acquireLock(file, { waitMs: 0 }), null);
  first();
  assert.equal(typeof acquireLock(file, { waitMs: 0 }), 'function');
});
