import assert from 'node:assert/strict';
import { readFileSync, existsSync, mkdtempSync, cpSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { resolve, sep } from 'node:path';
import test from 'node:test';

const root = fileURLToPath(new URL('../', import.meta.url));
const json = path => JSON.parse(readFileSync(resolve(root, path), 'utf8'));
test('Claude offers four maintained plugins without Telegram', () => {
  assert.deepEqual(json('.claude-plugin/marketplace.json').plugins.map(p => p.name).sort(),
    ['dcc-darkraise-ui', 'dcc-darkraise-win32ui', 'dr-status', 'dr-superpowers']);
});
test('Codex root discovery offers only supported plugins', () => {
  assert.ok(existsSync(resolve(root, '.agents/plugins/marketplace.json')), 'dedicated Codex catalog is required');
  assert.deepEqual(json('.agents/plugins/marketplace.json').plugins.map(p => p.name).sort(),
    ['dcc-darkraise-ui', 'dcc-darkraise-win32ui', 'dr-superpowers']);
});
test('Codex explicitly suppresses inherited Claude hooks', () => {
  const path = 'plugins/dr-superpowers/.codex-plugin/plugin.json';
  assert.ok(existsSync(resolve(root, path)), 'native manifest is required');
  assert.deepEqual(json(path).hooks, {});
});

test('repository validator rejects broken distribution contracts', async t => {
  assert.ok(existsSync(resolve(root, 'scripts/validate-repository.mjs')), 'repository validator is required');
  const { validateRepository } = await import('../scripts/validate-repository.mjs');
  assert.deepEqual(validateRepository(root), []);
  for (const [name, change, expected, target = '.claude-plugin/marketplace.json'] of [
    ['missing source', c => { c.plugins[0].source = './plugins/missing'; }, /source/],
    ['duplicate name', c => { c.plugins.push(c.plugins[0]); }, /duplicate/],
    ['name mismatch', c => { c.plugins[0].name = 'wrong'; }, /name|membership/],
    ['client version mismatch', c => { c.version = '0.9.0'; }, /version mismatch/, 'plugins/dr-superpowers/.codex-plugin/plugin.json'],
    ['implicit Claude hooks', c => { delete c.hooks; }, /empty Codex hooks/, 'plugins/dr-superpowers/.codex-plugin/plugin.json'],
    ['missing bundled reference', (c, dir) => { rmSync(resolve(dir, 'plugins/dr-superpowers/reference/native-codex.md')); }, /missing bundled reference/],
  ]) {
    await t.test(name, () => {
      const dir = mkdtempSync(resolve(tmpdir(), 'dr-catalog-'));
      try {
        for (const path of ['.claude-plugin', '.agents/plugins', ...json('.claude-plugin/marketplace.json').plugins.map(p => p.source)]) {
          cpSync(resolve(root, path), resolve(dir, path), { recursive: true });
        }
        const path = resolve(dir, target);
        const catalog = JSON.parse(readFileSync(path));
        change(catalog, dir);
        writeFileSync(path, JSON.stringify(catalog));
        assert.match(validateRepository(dir).join('\n'), expected);
      } finally { rmSync(dir, { recursive: true, force: true }); }
    });
  }
});

test('bundled-link check ignores links inside fenced code blocks', async () => {
  const { validateRepository } = await import('../scripts/validate-repository.mjs');
  const dir = mkdtempSync(resolve(tmpdir(), 'dr-catalog-'));
  try {
    for (const path of ['.claude-plugin', '.agents/plugins', ...json('.claude-plugin/marketplace.json').plugins.map(p => p.source)]) {
      cpSync(resolve(root, path), resolve(dir, path), { recursive: true });
    }
    const file = resolve(dir, 'plugins/dr-superpowers/skills/selecting-approaches/fenced.md');
    writeFileSync(file, '````markdown\n```\n[inner](missing-inner.md)\n```\n[example](missing-example.md)\n````\n');
    assert.deepEqual(validateRepository(dir), []);
    writeFileSync(file, '````\n[example](missing-example.md)\n````\n[live](missing-live.md)\n');
    assert.deepEqual(validateRepository(dir), [`plugins${sep}dr-superpowers${sep}skills${sep}selecting-approaches${sep}fenced.md: missing bundled reference missing-live.md`]);
  } finally { rmSync(dir, { recursive: true, force: true }); }
});
