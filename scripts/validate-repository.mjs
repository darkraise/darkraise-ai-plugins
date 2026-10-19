import { readFileSync, existsSync, readdirSync, realpathSync } from 'node:fs';
import { resolve, relative, dirname, isAbsolute } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const names = ['darkraise-ui', 'darkraise-win32ui', 'dforge', 'dr-status'];
const claudeOnly = ['dr-status'];
const contained = (root, path) => { const rel = relative(root, path); return rel !== '..' && !rel.startsWith(`..${process.platform === 'win32' ? '\\' : '/'}`) && !isAbsolute(rel); };
// A file's lines for the name sweeps, or null for a binary file (one holding a
// NUL byte), whose bytes are not text to read names in.
const textLines = path => {
  const bytes = readFileSync(path);
  return bytes.includes(0) ? null : bytes.toString('utf8').split('\n');
};

export function validateRepository(root) {
  root = resolve(root);
  const errors = [];
  const read = path => {
    try { return JSON.parse(readFileSync(path, 'utf8')); }
    catch (error) { errors.push(`${relative(root, path)}: ${error.message}`); return null; }
  };
  const manifests = new Map();
  for (const [client, catalogPath, expected] of [
    ['claude', '.claude-plugin/marketplace.json', names],
    ['codex', '.agents/plugins/marketplace.json', names.filter(name => !claudeOnly.includes(name))],
  ]) {
    const catalog = read(resolve(root, catalogPath));
    if (!catalog) continue;
    if (catalog.name !== 'darkraise') errors.push(`${client}: marketplace name must be darkraise`);
    if (client === 'claude' && catalog.allowCrossMarketplaceDependenciesOn !== undefined) errors.push('claude: cross-marketplace dependency allowlist must be removed');
    if (!Array.isArray(catalog.plugins)) { errors.push(`${client}: plugins must be an array`); continue; }
    if (JSON.stringify(catalog.plugins.map(p => p.name).sort()) !== JSON.stringify(expected)) errors.push(`${client}: incorrect catalog membership`);
    const seen = new Set();
    for (const entry of catalog.plugins) {
      if (seen.has(entry.name)) errors.push(`${client}: duplicate name ${entry.name}`);
      seen.add(entry.name);
      const source = client === 'claude' ? entry.source : entry.source?.source === 'local' ? entry.source.path : null;
      if (source !== `./plugins/${entry.name}`) errors.push(`${client}: source/name mismatch for ${entry.name}`);
      if (typeof source !== 'string') continue;
      const pluginRoot = resolve(root, source);
      if (!contained(root, pluginRoot) || !existsSync(pluginRoot) || !contained(root, realpathSync(pluginRoot))) { errors.push(`${client}: invalid source ${source}`); continue; }
      const manifest = read(resolve(pluginRoot, `.${client}-plugin/plugin.json`));
      if (!manifest) continue;
      if (manifest.name !== entry.name) errors.push(`${client}: manifest name mismatch for ${entry.name}`);
      if (!/^\d+\.\d+\.\d+(?:[-+][\w.-]+)?$/.test(manifest.version ?? '')) errors.push(`${entry.name}: invalid version`);
      if (!manifest.description || typeof manifest.description !== 'string') errors.push(`${entry.name}: description is required`);
      if (entry.name === 'dforge' && /superpowers/i.test(JSON.stringify(entry))) errors.push(`${catalogPath}: dforge entry: retired superpowers name`);
      const previous = manifests.get(entry.name);
      if (previous && previous.version !== manifest.version) errors.push(`${entry.name}: client version mismatch`);
      manifests.set(entry.name, manifest);
      if (client === 'codex') {
        if (entry.policy?.installation !== 'AVAILABLE') errors.push(`${entry.name}: installation must be AVAILABLE`);
        if (manifest.skills !== './skills/' || !existsSync(resolve(pluginRoot, 'skills'))) errors.push(`${entry.name}: skills path missing`);
        if (entry.name === 'dforge' && (JSON.stringify(manifest.hooks) !== '{}')) errors.push(`${entry.name}: explicit empty Codex hooks required`);
      }
      if (client === 'claude' && entry.name === 'dforge' && manifest.dependencies?.length) {
        errors.push('dforge: standalone plugin must not declare dependencies');
      }
    }
  }
  const versionPath = resolve(root, 'plugins/dr-status/scripts/VERSION');
  if (!existsSync(versionPath) || readFileSync(versionPath, 'utf8').trim() !== manifests.get('dr-status')?.version) errors.push('dr-status: script version mismatch');
  for (const name of claudeOnly) {
    if (existsSync(resolve(root, `plugins/${name}/.codex-plugin/plugin.json`))) errors.push(`${name}: Claude-only plugin has a Codex manifest`);
  }
  for (const name of names) {
    const skillRoot = resolve(root, 'plugins', name, 'skills');
    if (!existsSync(skillRoot)) continue;
    const visit = dir => {
      for (const item of readdirSync(dir, { withFileTypes: true })) {
        const path = resolve(dir, item.name);
        if (item.isDirectory()) visit(path);
        else if (item.name.endsWith('.md')) {
          // Links inside fenced code blocks are illustrative examples, not bundled references.
          let fence = null;
          const prose = readFileSync(path, 'utf8').split('\n').filter(line => {
            const marker = line.match(/^ {0,3}(`{3,}|~{3,})/)?.[1];
            if (fence) {
              if (marker?.[0] === fence[0] && marker.length >= fence.length && line.trim() === marker) fence = null;
              return false;
            }
            if (marker) { fence = marker; return false; }
            return true;
          }).join('\n');
          for (const match of prose.matchAll(/\[[^\]]+\]\(([^\s)]+)\)/g)) {
            const link = match[1].split('#')[0];
            if (!link || /^[a-z]+:|^\//i.test(link) || link.includes('$')) continue;
            if (!existsSync(resolve(dirname(path), decodeURIComponent(link)))) errors.push(`${relative(root, path)}: missing bundled reference ${link}`);
          }
        }
      }
    };
    visit(skillRoot);
  }
  const legacyPattern = /(?:^|[^\w-])superpowers:|dr-superpowers:|dcc-superpower-companions:/;
  // dforge-migrate rewrites the older prefixes in active plans, so it and its
  // tests and the migrate skill must spell them.
  const legacyAllowed = new Set([
    'plugins/dforge/tests/cockpit.test.ts',
    'plugins/dforge/scripts/dforge-migrate',
    'plugins/dforge/tests/dforge-migrate.test.sh',
    'plugins/dforge/skills/migrate/SKILL.md',
  ]);
  // dforge 3.0 spells the retired name only where it translates historical
  // citations, migrates a pre-3.0 layout, cites this repository's historical
  // specs, or credits upstream.
  const superpowersAllowed = new Set([
    'plugins/dforge/README.md',
    'plugins/dforge/hooks/cockpit/lib.ts',
    'plugins/dforge/scripts/dforge-migrate',
    'plugins/dforge/scripts/lib/dforge-dir.sh',
    'plugins/dforge/scripts/lib/roots.sh',
    'plugins/dforge/reference/project-state.md',
    'plugins/dforge/skills/project-status/SKILL.md',
    'plugins/dforge/skills/finishing-a-development-branch/SKILL.md',
    'plugins/dforge/reference/auto-run.md',
    'plugins/dforge/reference/parallel-waves.md',
    'plugins/dforge/reference/session-budget.md',
    'plugins/dforge/skills/migrate/SKILL.md',
  ]);
  // Third-party licence texts and the test suites spell every retired name.
  const licensesOrTests = /^plugins\/dforge\/(?:LICENSES|tests)\//;
  const superpowersExempt = rel => superpowersAllowed.has(rel) ||
    licensesOrTests.test(rel) ||
    /^plugins\/dforge\/scripts\/lib\/(?:darkmem-(?:sync|mirror|reconcile)|dforge-home-migrate)\.mjs$/.test(rel);
  // dforge 4.0 spells the dr-forge names only where it migrates or translates
  // them. A dated plan or spec name (2026-10-12-dr-forge-settings) cites
  // history and is not a retired name.
  const retiredForge = /dr-forge|(?<!D)FORGE|(?<![A-Za-z0-9d])forge(?![a-z])/;
  const forgeAllowed = new Set([
    'plugins/dforge/README.md',
    'plugins/dforge/hooks/cockpit/lib.ts',
    'plugins/dforge/scripts/dforge-migrate',
    'plugins/dforge/scripts/lib/dforge-dir.sh',
    'plugins/dforge/scripts/lib/roots.sh',
    'plugins/dforge/scripts/lib/dforge-home-migrate.mjs',
    'plugins/dforge/scripts/lib/darkmem-mirror.mjs',
    'plugins/dforge/scripts/lib/darkmem-sync.mjs',
    'plugins/dforge/scripts/lib/darkmem-reconcile.mjs',
    'plugins/dforge/skills/migrate/SKILL.md',
  ]);
  const forgeExempt = rel => forgeAllowed.has(rel) || licensesOrTests.test(rel);
  for (const name of names) {
    const pluginRoot = resolve(root, 'plugins', name);
    if (!existsSync(pluginRoot)) continue;
    const visit = dir => {
      for (const item of readdirSync(dir, { withFileTypes: true })) {
        const path = resolve(dir, item.name);
        if (item.isDirectory()) { visit(path); continue; }
        const rel = relative(root, path).replaceAll('\\', '/');
        const checksSuperpowers = name === 'dforge' && !superpowersExempt(rel);
        const checksForge = name === 'dforge' && !forgeExempt(rel);
        const lines = textLines(path);
        if (!lines) continue;
        lines.forEach((line, index) => {
          if (checksSuperpowers && /superpowers/i.test(line)) errors.push(`${rel}:${index + 1}: retired superpowers name`);
          if (checksForge && retiredForge.test(line.replace(/\d{4}-\d{2}-\d{2}-dr-forge/g, ''))) errors.push(`${rel}:${index + 1}: retired dr-forge name`);
          if (legacyAllowed.has(rel)) return;
          if (legacyPattern.test(line)) errors.push(`${rel}:${index + 1}: legacy plugin-name reference`);
          for (const match of line.matchAll(/dforge:([a-z0-9-]+)/g)) {
            // A name followed by `<` is a template placeholder such as impl-<model>-<effort>.
            if (line[match.index + match[0].length] === '<') continue;
            const name = match[1];
            if (!existsSync(resolve(root, 'plugins/dforge/skills', name)) &&
                !existsSync(resolve(root, 'plugins/dforge/agents', `${name}.md`))) {
              errors.push(`${rel}:${index + 1}: unresolved dforge reference ${name}`);
            }
          }
        });
      }
    };
    visit(pluginRoot);
  }
  // The UI plugins dropped their dcc- prefix in 0.3.0; only the migration
  // notes and the historical plans and specs still spell it.
  const dccAllowed = new Set(['docs/migration.md', 'scripts/validate-repository.mjs', 'tests/repository-layout.test.mjs']);
  const unswept = new Set(['.git', '.claude', 'node_modules', '.worktrees', '.dforge', '.forge', '.superpowers']);
  const sweep = dir => {
    for (const item of readdirSync(dir, { withFileTypes: true })) {
      const path = resolve(dir, item.name);
      const rel = relative(root, path).replaceAll('\\', '/');
      if (item.isDirectory()) {
        if (!unswept.has(item.name) && rel !== 'docs/superpowers') sweep(path);
        continue;
      }
      if (!item.isFile() || dccAllowed.has(rel)) continue;
      (textLines(path) ?? []).forEach((line, index) => {
        if (line.includes('dcc-darkraise')) errors.push(`${rel}:${index + 1}: retired dcc- plugin name`);
      });
    }
  };
  sweep(root);
  return errors;
}

const GROUPS = ['Cockpit', 'Context', 'Workflow', 'Process', 'Finish', 'Notifications', 'darkmem'];
const UNITS = ['k', '%', 's', 'min'];
const ZEROS = ['auto', 'off', 'any', 'hidden', 'unset'];

export async function validateSchema(root) {
  const rel = 'plugins/dforge/config/schema.mjs';
  let schema;
  try { schema = (await import(pathToFileURL(resolve(root, rel)).href)).default; }
  catch (error) { return [`${rel}: ${error.message}`]; }
  if (!schema || typeof schema !== 'object' || Array.isArray(schema)) return [`${rel}: must default-export an object`];
  const errors = [];
  for (const [key, spec] of Object.entries(schema)) {
    const at = `schema ${key}`;
    if (key === 'darkmem') { errors.push(`${at}: the key is reserved for the darkmem mapping`); continue; }
    if (!['boolean', 'number', 'enum', 'string'].includes(spec?.type)) { errors.push(`${at}: type must be boolean, number, enum or string`); continue; }
    if (!GROUPS.includes(spec.group)) errors.push(`${at}: group must be one of ${GROUPS.join(', ')}`);
    if (typeof spec.title !== 'string' || !spec.title) errors.push(`${at}: title is required`);
    if (typeof spec.description !== 'string' || !spec.description) errors.push(`${at}: description is required`);
    if (!['dforge', 'claude'].includes(spec.target)) errors.push(`${at}: target must be dforge or claude`);
    if (spec.env !== undefined && !/^[A-Z][A-Z0-9_]*$/.test(spec.env)) errors.push(`${at}: env must name an environment variable`);
    if (spec.step !== undefined && !(typeof spec.step === 'number' && spec.step > 0)) errors.push(`${at}: step must be a positive number`);
    if (typeof spec.label !== 'string' || !spec.label || spec.label.length > 16) errors.push(`${at}: label is required, at most 16 characters`);
    if (spec.unit !== undefined && !(spec.type === 'number' && UNITS.includes(spec.unit))) errors.push(`${at}: unit must be one of ${UNITS.join(', ')}, on a number`);
    if (spec.zero !== undefined && !(spec.type === 'number' && ZEROS.includes(spec.zero))) errors.push(`${at}: zero must be one of ${ZEROS.join(', ')}, on a number`);
    if (spec.enforcedBy !== undefined && !['script', 'skill'].includes(spec.enforcedBy)) errors.push(`${at}: enforcedBy must be script or skill`);
    if (spec.keepDefault !== undefined && spec.keepDefault !== true) errors.push(`${at}: keepDefault must be true when present`);
    if (spec.floor !== undefined && !(spec.type === 'number' && spec.min === 0 && Number.isFinite(spec.floor) && spec.floor >= 1 && (spec.max === undefined || spec.floor <= spec.max))) errors.push(`${at}: floor must lie between 1 and max, on a number whose min is 0`);
    const fits = spec.type === 'boolean' ? typeof spec.default === 'boolean'
      : spec.type === 'number' ? Number.isFinite(spec.default) && (spec.min === undefined || (Number.isFinite(spec.min) && spec.default >= spec.min)) && (spec.max === undefined || (Number.isFinite(spec.max) && spec.default <= spec.max))
      : spec.type === 'enum' ? Array.isArray(spec.values) && spec.values.length > 0 && spec.values.includes(spec.default)
      : typeof spec.default === 'string';
    // A number setting is whole, and a floored one has no values between 0 and its floor.
    const whole = spec.type !== 'number' || (Number.isInteger(spec.default) && (spec.floor === undefined || spec.default === 0 || spec.default >= spec.floor));
    if (!fits || !whole) errors.push(`${at}: default does not fit its type`);
  }
  return errors;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const root = process.argv[2] ?? fileURLToPath(new URL('../', import.meta.url));
  const errors = [...validateRepository(root), ...await validateSchema(root)];
  if (errors.length) { console.error(errors.join('\n')); process.exitCode = 1; }
  else console.log('Repository catalogs, manifests, versions, bundled links and the settings schema are valid.');
}
