import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import test from 'node:test';
import { selectShard } from '../scripts/test-shards.mjs';

const runner = fileURLToPath(new URL('../scripts/test-all.mjs', import.meta.url));
function list(...args) {
  const result = spawnSync(process.execPath, [runner, '--list', ...args], { encoding: 'utf8', timeout: 10000 });
  assert.ifError(result.error);
  assert.equal(result.status, 0, result.stderr);
  return result.stdout.trim().split('\n');
}

test('Windows shards cover every discovered suite exactly once', () => {
  const all = list();
  const shards = Array.from({ length: 6 }, (_, i) => list('--shard', `${i + 1}/6`));
  assert.ok(shards.every(shard => shard.length > 0));
  assert.deepEqual(shards.flat().sort(), all.sort());
  assert.equal(new Set(shards.flat()).size, all.length);
  assert.deepEqual(list('--shard', '1/6'), shards[0]);
});

test('new suites are included automatically and unsharded runs retain their order', () => {
  const jobs = ['plan-lint.test.sh', 'task-state.test.sh', 'new-suite.test.sh'].map(name => ['bash', [name], 600]);
  assert.deepEqual(selectShard(jobs), jobs);
  assert.deepEqual(selectShard(jobs, '1/1'), jobs);
  const selected = [selectShard(jobs, '1/2'), selectShard(jobs, '2/2')].flat();
  assert.equal(selected.length, jobs.length);
  for (const job of jobs) assert.ok(selected.includes(job));
});

test('invalid shard arguments fail instead of silently skipping tests', () => {
  const jobs = [['bash', ['a'], 10], ['bash', ['b'], 10]];
  for (const shard of ['', '0/2', '3/2', '1/0', '1/3', '1.5/2', '1', '1/2/3', '1/9007199254740992']) {
    assert.throws(() => selectShard(jobs, shard), /Shard/);
  }
  const result = spawnSync(process.execPath, [runner, '--shard', '0/4'], { encoding: 'utf8', timeout: 10000 });
  assert.ifError(result.error);
  assert.notEqual(result.status, 0);
  assert.doesNotMatch(result.stdout, /Running /);
});
