import { readFileSync } from 'node:fs';
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

function main(args) {
  if (args[0] === 'patch' && args.length === 1) {
    process.stdout.write(readFileSync(0, 'utf8').split('\n').map(renameText).join('\n'));
    return 0;
  }
  console.error('usage: node scripts/dagents-rename.mjs patch < dforge.diff');
  return 2;
}

if (process.argv[1] && pathToFileURL(process.argv[1]).href === import.meta.url) process.exitCode = main(process.argv.slice(2));
