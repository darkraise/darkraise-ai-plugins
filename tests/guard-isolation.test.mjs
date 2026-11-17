import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import test from 'node:test';

const repoRoot = fileURLToPath(new URL('../', import.meta.url));

test('the hook suites pass, each run alone, under a host config that enables every sibling', t => {
  const dir = mkdtempSync(join(tmpdir(), 'host-'));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  mkdirSync(join(dir, 'plugins'), { recursive: true });
  const install = name => ({ [`${name}@darkraise`]: [{ scope: 'user', installPath: '/x', version: '1' }] });
  writeFileSync(join(dir, 'plugins/installed_plugins.json'), JSON.stringify({ version: 2, plugins: { ...install('dforge'), ...install('dagents'), ...install('dflow') } }));
  writeFileSync(join(dir, 'settings.json'), JSON.stringify({ enabledPlugins: { 'dforge@darkraise': true, 'dagents@darkraise': true, 'dflow@darkraise': true } }));
  const host = { ...process.env, CLAUDE_CONFIG_DIR: dir };
  // A nested `node --test` that inherits NODE_TEST_CONTEXT exits 0 whatever its tests do.
  for (const key of ['WORKFLOW_GUARD_CLAUDE_DIR', 'WORKFLOW_GUARD_MANAGED_DIR', 'WORKFLOW_GUARD_PROJECT_DIR', 'NODE_TEST_CONTEXT']) delete host[key];
  for (const suite of ['plugins/dagents/tests/hook.test.sh', 'plugins/dforge/tests/hook.test.sh']) {
    const r = spawnSync(process.env.DR_TEST_BASH ?? 'bash', [suite], { cwd: repoRoot, env: host, encoding: 'utf8', timeout: 600000 });
    assert.equal(r.status, 0, `${suite}\n${(r.stdout ?? '').slice(-2000)}`);
  }
  const d = spawnSync(process.execPath, ['--test', 'plugins/dflow/tests/hooks.test.mjs'], { cwd: repoRoot, env: host, encoding: 'utf8', timeout: 300000 });
  assert.equal(d.status, 0, (d.stdout ?? '').slice(-2000));
});
