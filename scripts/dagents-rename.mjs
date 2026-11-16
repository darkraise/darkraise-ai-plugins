import { lstatSync, readdirSync, readFileSync, renameSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';

const KEPT_DR = /^DR_(TEST_BASH|TEST_ALL|FORGE_[A-Z0-9_]*|SUPERPOWERS_[A-Z0-9_]*)$/;
const DARKMEM_RENAMED = /\b(DARKMEM_KILL_GRACE|DARKMEM_SYNC_LOCK_WAIT_MS|DARKMEM_SYNC_TIMEOUT_MS)\b/g;

function renameIdentifiers(text) {
  return text
    .replace(/\bDFORGE_/g, 'DAGENTS_')
    .replace(/\bDR_[A-Z0-9_]+/g, name => KEPT_DR.test(name) ? name : `DAGENTS_${name.slice(3)}`)
    .replace(DARKMEM_RENAMED, 'DAGENTS_$1');
}

export function renameText(text) {
  return renameIdentifiers(text)
    .replace(/dforge(?! \d| v\d|-v\d)/g, 'dagents')
    .replace(/Dforge/g, 'Dagents')
    .replace(/DFORGE/g, 'DAGENTS');
}

export function renamePath(relPath) {
  return relPath.split('/').map(renameText).join('/');
}

function identifierSources(text) {
  const names = text.match(/\b(DFORGE_[A-Z0-9_]*|DR_[A-Z0-9_]+|DARKMEM_KILL_GRACE|DARKMEM_SYNC_LOCK_WAIT_MS|DARKMEM_SYNC_TIMEOUT_MS)\b/g) ?? [];
  return names.filter(name => renameIdentifiers(name) !== name);
}

function walk(dir, rel = '') {
  const entries = [];
  for (const name of readdirSync(join(dir, rel))) {
    if (name === '.git') continue;
    const path = rel ? `${rel}/${name}` : name;
    const stat = lstatSync(join(dir, path));
    entries.push({ path, dir: stat.isDirectory(), file: stat.isFile() });
    if (stat.isDirectory()) entries.push(...walk(dir, path));
  }
  return entries;
}

function collision(map) {
  const byTarget = new Map();
  for (const [source, target] of map) {
    const other = byTarget.get(target);
    if (other !== undefined && other !== source) return `dagents-rename: ${other} and ${source} both become ${target}`;
    byTarget.set(target, source);
  }
  return undefined;
}

export function renameTree(dir) {
  const entries = walk(dir);
  const texts = new Map();
  for (const { path, file } of entries) {
    if (!file) continue;
    const bytes = readFileSync(join(dir, path));
    if (!bytes.includes(0)) texts.set(path, bytes.toString('utf8'));
  }
  const names = new Map();
  for (const text of texts.values()) for (const name of identifierSources(text)) names.set(name, renameIdentifiers(name));
  const pathMap = new Map(entries.map(({ path }) => [path, renamePath(path)]));
  const problem = collision(names) ?? collision(pathMap);
  if (problem !== undefined) return problem;
  for (const [path, text] of texts) {
    const renamed = renameText(text);
    if (renamed !== text) writeFileSync(join(dir, path), renamed);
  }
  const depth = path => path.split('/').length;
  for (const { path } of [...entries].sort((a, b) => depth(b.path) - depth(a.path))) {
    const parts = path.split('/');
    const base = parts.pop();
    const renamed = renameText(base);
    if (renamed !== base) renameSync(join(dir, ...parts, base), join(dir, ...parts, renamed));
  }
  return undefined;
}

function main(args) {
  if (args[0] === 'tree' && args.length === 2) {
    const problem = renameTree(args[1]);
    if (problem === undefined) return 0;
    console.error(problem);
    return 1;
  }
  if (args[0] === 'patch' && args.length === 1) {
    process.stdout.write(readFileSync(0, 'utf8').split('\n').map(renameText).join('\n'));
    return 0;
  }
  console.error('usage: node scripts/dagents-rename.mjs tree <dir> | patch');
  return 2;
}

if (process.argv[1] && pathToFileURL(process.argv[1]).href === import.meta.url) process.exitCode = main(process.argv.slice(2));
