import assert from 'node:assert/strict';
import { readFileSync, existsSync, mkdtempSync, mkdirSync, cpSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { resolve, sep } from 'node:path';
import test from 'node:test';

const root = fileURLToPath(new URL('../', import.meta.url));
const json = path => JSON.parse(readFileSync(resolve(root, path), 'utf8'));
test('Claude offers four maintained plugins', () => {
  assert.deepEqual(json('.claude-plugin/marketplace.json').plugins.map(p => p.name).sort(),
    ['dcc-darkraise-ui', 'dcc-darkraise-win32ui', 'dr-forge', 'dr-status']);
});
test('Codex root discovery offers only supported plugins', () => {
  assert.ok(existsSync(resolve(root, '.agents/plugins/marketplace.json')), 'dedicated Codex catalog is required');
  assert.deepEqual(json('.agents/plugins/marketplace.json').plugins.map(p => p.name).sort(),
    ['dcc-darkraise-ui', 'dcc-darkraise-win32ui', 'dr-forge']);
});
test('Codex explicitly suppresses inherited Claude hooks', () => {
  const path = 'plugins/dr-forge/.codex-plugin/plugin.json';
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
    ['client version mismatch', c => { c.version = '0.9.0'; }, /version mismatch/, 'plugins/dr-forge/.codex-plugin/plugin.json'],
    ['implicit Claude hooks', c => { delete c.hooks; }, /empty Codex hooks/, 'plugins/dr-forge/.codex-plugin/plugin.json'],
    ['missing bundled reference', (c, dir) => { rmSync(resolve(dir, 'plugins/dr-forge/reference/native-codex.md')); }, /missing bundled reference/],
    ['reintroduced dependency', c => { c.dependencies = [{ name: 'superpowers', marketplace: 'claude-plugins-official' }]; }, /must not declare dependencies/, 'plugins/dr-forge/.claude-plugin/plugin.json'],
    ['reintroduced allowlist', c => { c.allowCrossMarketplaceDependenciesOn = ['claude-plugins-official']; }, /allowlist/],
    ['legacy name reference', (c, dir) => { writeFileSync(resolve(dir, 'plugins/dr-forge/reference/stray.md'), 'superpowers:brainstorming\n'); }, /legacy plugin-name reference/],
    ['pre-2.0 plugin prefix', (c, dir) => { writeFileSync(resolve(dir, 'plugins/dr-forge/reference/stray.md'), 'see dr-superpowers:brainstorming\n'); }, /legacy plugin-name reference/],
    ['unresolved dr-forge reference', (c, dir) => { writeFileSync(resolve(dir, 'plugins/dr-forge/reference/stray.md'), 'see dr-forge:no-such-skill\n'); }, /unresolved dr-forge reference no-such-skill/],
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
    const file = resolve(dir, 'plugins/dr-forge/skills/selecting-approaches/fenced.md');
    writeFileSync(file, '````markdown\n```\n[inner](missing-inner.md)\n```\n[example](missing-example.md)\n````\n');
    assert.deepEqual(validateRepository(dir), []);
    writeFileSync(file, '````\n[example](missing-example.md)\n````\n[live](missing-live.md)\n');
    assert.deepEqual(validateRepository(dir), [`plugins${sep}dr-forge${sep}skills${sep}selecting-approaches${sep}fenced.md: missing bundled reference missing-live.md`]);
  } finally { rmSync(dir, { recursive: true, force: true }); }
});

test('reference check skips template placeholders and resolves agents', async () => {
  const { validateRepository } = await import('../scripts/validate-repository.mjs');
  const dir = mkdtempSync(resolve(tmpdir(), 'dr-catalog-'));
  try {
    for (const path of ['.claude-plugin', '.agents/plugins', ...json('.claude-plugin/marketplace.json').plugins.map(p => p.source)]) {
      cpSync(resolve(root, path), resolve(dir, path), { recursive: true });
    }
    writeFileSync(resolve(dir, 'plugins/dr-forge/reference/placeholder.md'),
      'subagent_type: dr-forge:impl-<model>-<effort>\nagent dr-forge:judge-fable\nskill dr-forge:writing-plans\n');
    assert.deepEqual(validateRepository(dir), []);
  } finally { rmSync(dir, { recursive: true, force: true }); }
});
test('the settings schema is valid, and broken schemas are caught', async () => {
  const { validateSchema } = await import('../scripts/validate-repository.mjs');
  assert.deepEqual(await validateSchema(root), []);
  // Each case gets its own directory: Node caches a module by its URL, so a
  // rewritten file at one path would be imported once.
  const broken = async text => {
    const dir = mkdtempSync(resolve(tmpdir(), 'dr-schema-'));
    try {
      mkdirSync(resolve(dir, 'plugins/dr-forge/config'), { recursive: true });
      writeFileSync(resolve(dir, 'plugins/dr-forge/config/schema.mjs'), text);
      return (await validateSchema(dir)).join('\n');
    } finally { rmSync(dir, { recursive: true, force: true }); }
  };
  const real = readFileSync(resolve(root, 'plugins/dr-forge/config/schema.mjs'), 'utf8');
  assert.match(await broken(real.replace("default: 'auto'", "default: 'tiles'")), /schema layout: default does not fit its type/);
  assert.match(await broken("export default { darkmem: { type: 'string', default: '', group: 'Cockpit', title: 't', description: 'd', target: 'forge' } }\n"), /schema darkmem: the key is reserved/);
  assert.match(await broken('export default [];\n'), /must default-export an object/);
  assert.match(await broken("export default { n: { type: 'number', default: Infinity, group: 'Cockpit', title: 't', description: 'd', target: 'forge' } }\n"), /schema n: default does not fit its type/);
});
