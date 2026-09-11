import { readFileSync, existsSync, readdirSync, realpathSync } from 'node:fs';
import { resolve, relative, dirname, isAbsolute } from 'node:path';
import { fileURLToPath } from 'node:url';

const names = ['dcc-darkraise-ui', 'dcc-darkraise-win32ui', 'dr-status', 'dr-superpowers'];
const contained = (root, path) => { const rel = relative(root, path); return rel !== '..' && !rel.startsWith(`..${process.platform === 'win32' ? '\\' : '/'}`) && !isAbsolute(rel); };

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
    ['codex', '.agents/plugins/marketplace.json', names.filter(name => name !== 'dr-status')],
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
      const previous = manifests.get(entry.name);
      if (previous && previous.version !== manifest.version) errors.push(`${entry.name}: client version mismatch`);
      manifests.set(entry.name, manifest);
      if (client === 'codex') {
        if (entry.policy?.installation !== 'AVAILABLE') errors.push(`${entry.name}: installation must be AVAILABLE`);
        if (manifest.skills !== './skills/' || !existsSync(resolve(pluginRoot, 'skills'))) errors.push(`${entry.name}: skills path missing`);
        if (entry.name === 'dr-superpowers' && (JSON.stringify(manifest.hooks) !== '{}')) errors.push(`${entry.name}: explicit empty Codex hooks required`);
      }
      if (client === 'claude' && entry.name === 'dr-superpowers' && manifest.dependencies?.length) {
        errors.push('dr-superpowers: standalone plugin must not declare dependencies');
      }
    }
  }
  const versionPath = resolve(root, 'plugins/dr-status/scripts/VERSION');
  if (!existsSync(versionPath) || readFileSync(versionPath, 'utf8').trim() !== manifests.get('dr-status')?.version) errors.push('dr-status: script version mismatch');
  if (existsSync(resolve(root, 'plugins/dr-status/.codex-plugin/plugin.json'))) errors.push('dr-status: Claude-only plugin has a Codex manifest');
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
  return errors;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const errors = validateRepository(process.argv[2] ?? fileURLToPath(new URL('../', import.meta.url)));
  if (errors.length) { console.error(errors.join('\n')); process.exitCode = 1; }
  else console.log('Repository catalogs, manifests, versions, and bundled links are valid.');
}
