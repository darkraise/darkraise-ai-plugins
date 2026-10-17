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
    ['darkraise-ui', 'darkraise-win32ui', 'dforge', 'dr-status']);
});
test('Codex root discovery offers only supported plugins', () => {
  assert.ok(existsSync(resolve(root, '.agents/plugins/marketplace.json')), 'dedicated Codex catalog is required');
  assert.deepEqual(json('.agents/plugins/marketplace.json').plugins.map(p => p.name).sort(),
    ['darkraise-ui', 'darkraise-win32ui', 'dforge']);
});
test('Codex explicitly suppresses inherited Claude hooks', () => {
  const path = 'plugins/dforge/.codex-plugin/plugin.json';
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
    ['client version mismatch', c => { c.version = '0.9.0'; }, /version mismatch/, 'plugins/dforge/.codex-plugin/plugin.json'],
    ['implicit Claude hooks', c => { delete c.hooks; }, /empty Codex hooks/, 'plugins/dforge/.codex-plugin/plugin.json'],
    ['missing bundled reference', (c, dir) => { rmSync(resolve(dir, 'plugins/dforge/reference/native-codex.md')); }, /missing bundled reference/],
    ['reintroduced dependency', c => { c.dependencies = [{ name: 'superpowers', marketplace: 'claude-plugins-official' }]; }, /must not declare dependencies/, 'plugins/dforge/.claude-plugin/plugin.json'],
    ['reintroduced allowlist', c => { c.allowCrossMarketplaceDependenciesOn = ['claude-plugins-official']; }, /allowlist/],
    ['legacy name reference', (c, dir) => { writeFileSync(resolve(dir, 'plugins/dforge/reference/stray.md'), 'superpowers:brainstorming\n'); }, /legacy plugin-name reference/],
    ['pre-2.0 plugin prefix', (c, dir) => { writeFileSync(resolve(dir, 'plugins/dforge/reference/stray.md'), 'see dr-superpowers:brainstorming\n'); }, /legacy plugin-name reference/],
    ['unresolved dforge reference', (c, dir) => { writeFileSync(resolve(dir, 'plugins/dforge/reference/stray.md'), 'see dforge:no-such-skill\n'); }, /unresolved dforge reference no-such-skill/],
    ['retired superpowers name', (c, dir) => { writeFileSync(resolve(dir, 'plugins/dforge/scripts/stray.sh'), 'mkdir -p .superpowers/sdd\n'); }, /plugins\/dforge\/scripts\/stray\.sh:1: retired superpowers name/],
    ['retired name in the Claude catalog entry', c => { c.plugins.find(p => p.name === 'dforge').keywords.push('superpowers'); }, /\.claude-plugin\/marketplace\.json: dforge entry: retired superpowers name/],
    ['retired name in the Codex catalog entry', c => { c.plugins.find(p => p.name === 'dforge').description = 'a superpowers fork'; }, /\.agents\/plugins\/marketplace\.json: dforge entry: retired superpowers name/, '.agents/plugins/marketplace.json'],
    ['retired name in any case', (c, dir) => { writeFileSync(resolve(dir, 'plugins/dforge/reference/stray.md'), 'a Superpowers worktree\n'); }, /plugins\/dforge\/reference\/stray\.md:1: retired superpowers name/],
    ['retired dr-forge name', (c, dir) => { writeFileSync(resolve(dir, 'plugins/dforge/scripts/stray.sh'), 'mkdir -p .forge/sdd\n'); }, /plugins\/dforge\/scripts\/stray\.sh:1: retired dr-forge name/],
    ['retired dr-forge variable', (c, dir) => { writeFileSync(resolve(dir, 'plugins/dforge/scripts/stray.sh'), 'echo "$DR_FORGE_BUDGET"\n'); }, /plugins\/dforge\/scripts\/stray\.sh:1: retired dr-forge name/],
    ['retired dr-forge docs root', (c, dir) => { writeFileSync(resolve(dir, 'plugins/dforge/scripts/stray.sh'), 'cat docs/forge/plans/p.md\n'); }, /plugins\/dforge\/scripts\/stray\.sh:1: retired dr-forge name/],
    ['retired dr-forge home', (c, dir) => { writeFileSync(resolve(dir, 'plugins/dforge/scripts/stray.sh'), 'ls ~/.dr-forge\n'); }, /plugins\/dforge\/scripts\/stray\.sh:1: retired dr-forge name/],
    ['retired forge_ code name', (c, dir) => { writeFileSync(resolve(dir, 'plugins/dforge/scripts/stray.sh'), 'forge_dir .\n'); }, /plugins\/dforge\/scripts\/stray\.sh:1: retired dr-forge name/],
    ['retired FORGE variable', (c, dir) => { writeFileSync(resolve(dir, 'plugins/dforge/scripts/stray.sh'), 'echo "$FORGE_HOME"\n'); }, /plugins\/dforge\/scripts\/stray\.sh:1: retired dr-forge name/],
    ['retired dcc- plugin name', (c, dir) => { writeFileSync(resolve(dir, 'plugins/dr-status/stray.md'), 'install dcc-darkraise-ui\n'); }, /plugins\/dr-status\/stray\.md:1: retired dcc- plugin name/],
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
    const file = resolve(dir, 'plugins/dforge/skills/selecting-approaches/fenced.md');
    writeFileSync(file, '````markdown\n```\n[inner](missing-inner.md)\n```\n[example](missing-example.md)\n````\n');
    assert.deepEqual(validateRepository(dir), []);
    writeFileSync(file, '````\n[example](missing-example.md)\n````\n[live](missing-live.md)\n');
    assert.deepEqual(validateRepository(dir), [`plugins${sep}dforge${sep}skills${sep}selecting-approaches${sep}fenced.md: missing bundled reference missing-live.md`]);
  } finally { rmSync(dir, { recursive: true, force: true }); }
});

test('the retired superpowers name is allowed only in the allowlisted files', async () => {
  const { validateRepository } = await import('../scripts/validate-repository.mjs');
  const dir = mkdtempSync(resolve(tmpdir(), 'dr-catalog-'));
  try {
    for (const path of ['.claude-plugin', '.agents/plugins', ...json('.claude-plugin/marketplace.json').plugins.map(p => p.source)]) {
      cpSync(resolve(root, path), resolve(dir, path), { recursive: true });
    }
    for (const path of ['plugins/dforge/tests/stray.test.sh', 'plugins/dforge/LICENSES/stray-LICENSE', 'plugins/dforge/scripts/lib/dforge-home-migrate.mjs', 'plugins/dr-status/stray.md']) {
      writeFileSync(resolve(dir, path), 'superpowers\n');
    }
    const retired = () => validateRepository(dir).filter(error => error.includes('retired superpowers name'));
    assert.deepEqual(retired(), []);
    writeFileSync(resolve(dir, 'plugins/dforge/scripts/lib/dforge-home-migrate.sh'), 'superpowers\n');
    assert.deepEqual(retired(), ['plugins/dforge/scripts/lib/dforge-home-migrate.sh:1: retired superpowers name']);
  } finally { rmSync(dir, { recursive: true, force: true }); }
});

test('the retired dr-forge names are allowed only in the allowlisted files', async () => {
  const { validateRepository } = await import('../scripts/validate-repository.mjs');
  const dir = mkdtempSync(resolve(tmpdir(), 'dr-catalog-'));
  try {
    for (const path of ['.claude-plugin', '.agents/plugins', ...json('.claude-plugin/marketplace.json').plugins.map(p => p.source)]) {
      cpSync(resolve(root, path), resolve(dir, path), { recursive: true });
    }
    for (const path of ['plugins/dforge/tests/stray.test.sh', 'plugins/dforge/scripts/lib/roots.sh']) {
      writeFileSync(resolve(dir, path), 'mkdir -p .forge\n');
    }
    // A dated plan name cites history, and other words merely contain the letters.
    writeFileSync(resolve(dir, 'plugins/dforge/reference/dated.md'), 'see docs/dforge/plans/2026-10-12-dr-forge-settings.md; git forges forget\n');
    const retired = () => validateRepository(dir).filter(error => error.includes('retired dr-forge name'));
    assert.deepEqual(retired(), []);
    writeFileSync(resolve(dir, 'plugins/dforge/reference/stray.md'), 'run dr-forge:brainstorming\n');
    assert.deepEqual(retired(), ['plugins/dforge/reference/stray.md:1: retired dr-forge name']);
  } finally { rmSync(dir, { recursive: true, force: true }); }
});

test('reference check skips template placeholders and resolves agents', async () => {
  const { validateRepository } = await import('../scripts/validate-repository.mjs');
  const dir = mkdtempSync(resolve(tmpdir(), 'dr-catalog-'));
  try {
    for (const path of ['.claude-plugin', '.agents/plugins', ...json('.claude-plugin/marketplace.json').plugins.map(p => p.source)]) {
      cpSync(resolve(root, path), resolve(dir, path), { recursive: true });
    }
    writeFileSync(resolve(dir, 'plugins/dforge/reference/placeholder.md'),
      'subagent_type: dforge:impl-<model>-<effort>\nagent dforge:judge-fable\nskill dforge:writing-plans\n');
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
      mkdirSync(resolve(dir, 'plugins/dforge/config'), { recursive: true });
      writeFileSync(resolve(dir, 'plugins/dforge/config/schema.mjs'), text);
      return (await validateSchema(dir)).join('\n');
    } finally { rmSync(dir, { recursive: true, force: true }); }
  };
  const real = readFileSync(resolve(root, 'plugins/dforge/config/schema.mjs'), 'utf8');
  assert.match(await broken(real.replace("default: 'auto'", "default: 'tiles'")), /schema layout: default does not fit its type/);
  assert.match(await broken("export default { darkmem: { type: 'string', default: '', group: 'Cockpit', title: 't', description: 'd', target: 'dforge' } }\n"), /schema darkmem: the key is reserved/);
  assert.match(await broken('export default [];\n'), /must default-export an object/);
  assert.match(await broken("export default { n: { type: 'number', default: Infinity, group: 'Cockpit', title: 't', description: 'd', target: 'dforge' } }\n"), /schema n: default does not fit its type/);
  const entry = extra => `export default { n: { type: 'number', default: 0, min: 0, max: 10, group: 'Cockpit', label: 'N', title: 't', description: 'd', target: 'dforge', ${extra} } }\n`;
  assert.match(await broken(real.replace("label: 'Layout'", "label: 'A label that is far too long'")), /schema layout: label is required, at most 16 characters/);
  assert.match(await broken(real.replace("group: 'Finish'", "group: 'Elsewhere'")), /group must be one of Cockpit, Context, Workflow, Process, Finish, Notifications/);
  assert.match(await broken(entry("unit: 'parsecs'")), /schema n: unit must be one of k, %, s, min, on a number/);
  assert.match(await broken(entry("zero: 'nil'")), /schema n: zero must be one of auto, off, any, hidden, unset, on a number/);
  assert.match(await broken(entry('floor: 5').replace('default: 0', 'default: 3')), /schema n: default does not fit its type/);
  assert.match(await broken(entry('step: 1').replace('default: 0', 'default: 2.5')), /schema n: default does not fit its type/);
  assert.match(await broken(entry("enforcedBy: 'luck'")), /schema n: enforcedBy must be script or skill/);
  assert.match(await broken(entry('floor: 50')), /schema n: floor must lie between 1 and max, on a number whose min is 0/);
  assert.equal(await broken(entry('floor: 5')), '');
});
