import { readFileSync, existsSync, readdirSync, realpathSync } from 'node:fs';
import { resolve, relative, dirname, isAbsolute } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { renamePath } from './dagents-rename.mjs';
import { lintTree } from './lint-portability.mjs';

const maintained = ['dagents', 'darkraise-ui', 'darkraise-win32ui', 'dflow', 'dforge', 'dr-status'];
const NAMESPACED = ['dforge', 'dagents'];
// dagents is dforge 4.17.1 renamed, so it keeps dforge's rules and allowlists under its own paths.
const WORKFLOW = ['dforge', 'dagents'];
const withDagents = paths => new Set(paths.flatMap(path => [path, renamePath(path)]));
// dagents spells dforge only where it migrates or reads a dforge 4.x layout,
// lists its siblings, or names its origin.
export const DAGENTS_DFORGE_ALLOWED = new Set([
  'plugins/dagents/README.md',
  // These suites read this repository's own notes and plans under docs/dforge.
  'plugins/dagents/tests/lanes.test.sh',
  'plugins/dagents/tests/typed-seats-and-drafting.acceptance.sh',
  // dforge 4.x's docs/dforge is read as an older spelling of docs/dagents.
  'plugins/dagents/scripts/lib/roots.sh',
  'plugins/dagents/hooks/cockpit/lib.ts',
  'plugins/dagents/scripts/lib/darkmem-mirror.mjs',
  'plugins/dagents/scripts/lib/darkmem-sync.mjs',
  'plugins/dagents/scripts/lib/darkmem-reconcile.mjs',
  'plugins/dagents/tests/roots.test.sh',
  'plugins/dagents/tests/darkmem-sync/mirror.test.mjs',
  'plugins/dagents/tests/darkmem-sync/reconcile.test.mjs',
  'plugins/dagents/tests/darkmem-sync/restore.test.mjs',
  // Seeds another plugin's darkmem document and workstream that dagents must leave alone.
  'plugins/dagents/tests/darkmem-sync/push.test.mjs',
  // Migrate moves a dforge 4.x project's names to dagents' and says when one is found.
  'plugins/dagents/scripts/dagents-migrate',
  'plugins/dagents/scripts/lib/dagents-dir.sh',
  'plugins/dagents/scripts/repo-audit',
  'plugins/dagents/scripts/session-start.sh',
  'plugins/dagents/skills/migrate/SKILL.md',
  'plugins/dagents/tests/dagents-migrate.test.sh',
  // Migrate copies a dforge 4.x repository's settings and refuses its darkmem-held families.
  'plugins/dagents/scripts/lib/dagents-home-migrate.mjs',
  'plugins/dagents/tests/home/home-migrate.test.mjs',
  // The workflow guard names its siblings.
  'plugins/dagents/scripts/workflow-guard.mjs',
  'plugins/dagents/tests/stand-down.test.sh',
  'plugins/dagents/skills/using-dagents/references/codex-tools.md',
  'plugins/dagents/tests/cockpit.test.ts',
  // Proves dagents never touches or reads dforge's names, so it seeds them.
  'plugins/dagents/tests/isolation.acceptance.test.sh',
  // Builds dforge 4.x projects and homes to prove migrate and the guard's isolation.
  'plugins/dagents/tests/dagents-split.acceptance.test.sh',
  'plugins/dagents/tests/darkmem-sync/dagents-split.acceptance.test.mjs',
]);
const claudeOnly = ['dflow', 'dr-status'];
const contained = (root, path) => { const rel = relative(root, path); return rel !== '..' && !rel.startsWith(`..${process.platform === 'win32' ? '\\' : '/'}`) && !isAbsolute(rel); };
// A file's lines for the name sweeps, or null for a binary file (one holding a
// NUL character), whose bytes are not text to read names in. UTF-16 text holds
// NUL bytes, so a file opening with a UTF-16 byte-order mark is decoded first.
const textLines = path => {
  const bytes = readFileSync(path);
  const text = bytes[0] === 0xff && bytes[1] === 0xfe ? new TextDecoder('utf-16le').decode(bytes.subarray(2))
    : bytes[0] === 0xfe && bytes[1] === 0xff ? new TextDecoder('utf-16be').decode(bytes.subarray(2))
    : bytes.toString('utf8');
  return text.includes('\u0000') ? null : text.split('\n');
};

export function validateRepository(root, { names = maintained } = {}) {
  root = resolve(root);
  const errors = [];
  const read = path => {
    try { return JSON.parse(readFileSync(path, 'utf8')); }
    catch (error) { errors.push(`${relative(root, path)}: ${error.message}`); return null; }
  };
  const manifests = new Map();
  for (const [client, catalogPath, expected] of [
    ['claude', '.claude-plugin/marketplace.json', maintained],
    ['codex', '.agents/plugins/marketplace.json', maintained.filter(name => !claudeOnly.includes(name))],
  ]) {
    const catalog = read(resolve(root, catalogPath));
    if (!catalog) continue;
    if (catalog.name !== 'darkraise') errors.push(`${client}: marketplace name must be darkraise`);
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
      if (WORKFLOW.includes(entry.name) && /superpowers/i.test(JSON.stringify(entry))) errors.push(`${catalogPath}: ${entry.name} entry: retired superpowers name`);
      const previous = manifests.get(entry.name);
      if (previous && previous.version !== manifest.version) errors.push(`${entry.name}: client version mismatch`);
      manifests.set(entry.name, manifest);
      if (client === 'codex') {
        if (entry.policy?.installation !== 'AVAILABLE') errors.push(`${entry.name}: installation must be AVAILABLE`);
        if (manifest.skills !== './skills/' || !existsSync(resolve(pluginRoot, 'skills'))) errors.push(`${entry.name}: skills path missing`);
        if (WORKFLOW.includes(entry.name) && (JSON.stringify(manifest.hooks) !== '{}')) errors.push(`${entry.name}: explicit empty Codex hooks required`);
      }
    }
  }
  const versionPath = resolve(root, 'plugins/dr-status/scripts/VERSION');
  if (!existsSync(versionPath) || readFileSync(versionPath, 'utf8').trim() !== manifests.get('dr-status')?.version) errors.push('dr-status: script version mismatch');
  for (const name of claudeOnly) {
    if (existsSync(resolve(root, `plugins/${name}/.codex-plugin/plugin.json`))) errors.push(`${name}: Claude-only plugin has a Codex manifest`);
  }
  const guardBase = 'plugins/dforge/scripts/workflow-guard.mjs';
  const guard = existsSync(resolve(root, guardBase)) ? readFileSync(resolve(root, guardBase)) : null;
  if (guard === null) errors.push(`${guardBase}: missing`);
  for (const name of ['dagents', 'dflow']) {
    const rel = `plugins/${name}/scripts/workflow-guard.mjs`;
    const copy = existsSync(resolve(root, rel)) ? readFileSync(resolve(root, rel)) : null;
    if (guard !== null && (copy === null || !copy.equals(guard))) errors.push(`${rel}: differs from ${guardBase}`);
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
  const legacyAllowed = withDagents([
    'plugins/dforge/tests/cockpit.test.ts',
    'plugins/dforge/scripts/dforge-migrate',
    'plugins/dforge/tests/dforge-migrate.test.sh',
    'plugins/dforge/skills/migrate/SKILL.md',
  ]);
  // dforge 3.0 spells the retired name only where it translates historical
  // citations, migrates a pre-3.0 layout, cites this repository's historical
  // specs, or credits upstream.
  const superpowersAllowed = withDagents([
    'plugins/dforge/README.md',
    'plugins/dforge/hooks/cockpit/lib.ts',
    'plugins/dforge/scripts/dforge-migrate',
    'plugins/dforge/scripts/lib/dforge-dir.sh',
    'plugins/dforge/scripts/lib/roots.sh',
    'plugins/dforge/reference/project-state.md',
    'plugins/dforge/skills/project-status/SKILL.md',
    'plugins/dforge/skills/finishing-a-development-branch/SKILL.md',
    'plugins/dforge/reference/auto-run.md',
    'plugins/dforge/reference/session-budget.md',
    'plugins/dforge/skills/migrate/SKILL.md',
    'plugins/dagents/reference/parallel-waves.md',
  ]);
  // Third-party licence texts and the test suites spell every retired name.
  const licensesOrTests = /^plugins\/(?:dforge|dagents)\/(?:LICENSES|tests)\//;
  const superpowersExempt = rel => superpowersAllowed.has(rel) ||
    licensesOrTests.test(rel) ||
    /^plugins\/(?:dforge|dagents)\/scripts\/lib\/(?:darkmem-(?:sync|mirror|reconcile)|(?:dforge|dagents)-home-migrate)\.mjs$/.test(rel);
  // dforge 4.0 spells the dr-forge names only where it migrates or translates
  // them. A dated plan or spec name (2026-10-12-dr-forge-settings) cites
  // history and is not a retired name.
  const retiredForge = /dr-forge|(?<!D)FORGE|(?<![A-Za-z0-9d])forge(?![a-z])/;
  const forgeAllowed = withDagents([
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
        const checksSuperpowers = WORKFLOW.includes(name) && !superpowersExempt(rel);
        const checksForge = WORKFLOW.includes(name) && !forgeExempt(rel);
        const lines = textLines(path);
        if (!lines) continue;
        lines.forEach((line, index) => {
          if (name === 'dagents') {
            if (!DAGENTS_DFORGE_ALLOWED.has(rel) && /dforge/i.test(line.replace(/dforge(?= \d| v\d|-v\d)/g, ''))) errors.push(`${rel}:${index + 1}: dforge name in dagents`);
            if ([...line.matchAll(/dagents (\d+)/g)].some(match => match[1] !== '1')) errors.push(`${rel}:${index + 1}: dagents version other than 1.x`);
          }
          if (checksSuperpowers && /superpowers/i.test(line)) errors.push(`${rel}:${index + 1}: retired superpowers name`);
          if (checksForge && retiredForge.test(line.replace(/\d{4}-\d{2}-\d{2}-dr-forge/g, ''))) errors.push(`${rel}:${index + 1}: retired dr-forge name`);
          if (legacyAllowed.has(rel)) return;
          if (legacyPattern.test(line)) errors.push(`${rel}:${index + 1}: legacy plugin-name reference`);
          if (!NAMESPACED.includes(name)) return;
          for (const match of line.matchAll(new RegExp(`${name}:([a-z0-9-]+)`, 'g'))) {
            // A name followed by `<` is a template placeholder such as impl-<model>-<effort>.
            if (line[match.index + match[0].length] === '<') continue;
            const ref = match[1];
            if (!existsSync(resolve(root, 'plugins', name, 'skills', ref)) &&
                !existsSync(resolve(root, 'plugins', name, 'agents', `${ref}.md`)) &&
                !existsSync(resolve(root, 'plugins', name, 'commands', `${ref}.md`))) {
              errors.push(`${rel}:${index + 1}: unresolved ${name} reference ${ref}`);
            }
          }
        });
      }
    };
    visit(pluginRoot);
  }
  // The UI plugins dropped their dcc- prefix in 0.3.0; only the migration
  // notes and the historical plans and specs still spell it.
  const dccAllowed = new Set(['docs/migration.md', 'scripts/validate-repository.mjs', 'tests/repository-layout.test.mjs', 'docs/dforge/plans/2026-11-17-dagents-split.md']);
  const unswept = new Set(['.git', '.claude', 'node_modules', '.worktrees', '.dforge', '.dagents', '.forge', '.superpowers']);
  const sweep = dir => {
    for (const item of readdirSync(dir, { withFileTypes: true })) {
      const path = resolve(dir, item.name);
      const rel = relative(root, path).replaceAll('\\', '/');
      if (item.isDirectory()) {
        if (!unswept.has(item.name)) sweep(path);
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

const GROUPS = ['Cockpit', 'Minimized', 'Context', 'Workflow', 'Process', 'Finish', 'Notifications', 'darkmem'];
const UNITS = ['k', '%', 's', 'min'];
const ZEROS = ['auto', 'off', 'any', 'hidden', 'unset'];

let schemaLoads = 0;
export async function validateSchema(root, plugin = 'dforge') {
  const rel = `plugins/${plugin}/config/schema.mjs`;
  let schema;
  // A query per load: import() caches by URL, and a schema file can change between calls.
  try { schema = (await import(`${pathToFileURL(resolve(root, rel)).href}?load=${++schemaLoads}`)).default; }
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
    if (![plugin, 'claude'].includes(spec.target)) errors.push(`${at}: target must be ${plugin} or claude`);
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
  const errors = [...validateRepository(root)];
  for (const name of maintained) if (existsSync(resolve(root, 'plugins', name, 'config/schema.mjs'))) errors.push(...await validateSchema(root, name));
  errors.push(...lintTree(root));
  if (errors.length) { console.error(errors.join('\n')); process.exitCode = 1; }
  else console.log('Repository catalogs, manifests, versions, bundled links and the settings schema are valid.');
}
