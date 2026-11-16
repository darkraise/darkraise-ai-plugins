import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';

const TAG = 'dforge-v4.17.1';
const SHA = '[0-9a-f]{7,40}';

const git = (...args) => execFileSync('git', args, { encoding: 'utf8', timeout: 60000, stdio: ['ignore', 'pipe', 'pipe'] });

function gitOk(...args) {
  try {
    git(...args);
    return true;
  } catch {
    return false;
  }
}

const changedPaths = (sha, prefix) => git('diff-tree', '--root', '--no-commit-id', '-r', '--name-only', '-z', sha, '--', prefix).split('\0').filter(Boolean);

export function rows(from, to) {
  return git('log', '--no-merges', '--reverse', '--abbrev=7', '--format=%h %s', `${from}..${to}`, '--', 'plugins/dforge').split('\n').filter(Boolean);
}

let tagPaths;

export function fiveOnly(sha) {
  tagPaths ??= new Set(git('ls-tree', '-r', '--name-only', '-z', TAG, '--', 'plugins/dforge').split('\0'));
  const paths = changedPaths(sha, 'plugins/dforge').filter(path => !path.includes('/tests/'));
  return paths.length > 0 && paths.every(path => !tagPaths.has(path));
}

function registerRows(text) {
  const lines = text.split('\n');
  const start = lines.findIndex(line => /^\|\s*#\s*\|\s*Item\s*\|/.test(line));
  if (start < 0) return [];
  const found = [];
  for (const line of lines.slice(start + 2)) {
    if (!line.startsWith('|')) break;
    const cells = line.replace(/\\\|/g, '\u0001').split('|').slice(1, -1).map(cell => cell.trim().replace(/\u0001/g, '|'));
    found.push({ id: cells[0], item: cells[1] ?? '', state: cells[4] ?? '', note: cells[5] ?? '' });
  }
  return found;
}

function portProblem(sha) {
  if (!gitOk('rev-parse', '--verify', '--quiet', `${sha}^{commit}`) || changedPaths(sha, 'plugins/dagents').length === 0) return `port ${sha} is not a dagents commit`;
  if (!gitOk('merge-base', '--is-ancestor', sha, 'HEAD')) return `port ${sha} is not on this branch`;
  return undefined;
}

function rowProblem(row) {
  if (row.state === 'done') {
    const port = new RegExp(`^port (${SHA}); (fail@parent pass@port|text-only \\S.*)$`).exec(row.note);
    if (!port) return 'done needs port <sha7>; fail@parent pass@port or port <sha7>; text-only <path>';
    return portProblem(port[1]);
  }
  if (row.state !== 'n/a') return 'not finished';
  if (row.note === '5-only') {
    const sha = new RegExp(`^(${SHA}) `).exec(row.item)?.[1];
    let passes = false;
    try {
      passes = sha !== undefined && fiveOnly(sha);
    } catch {}
    return passes ? undefined : '5-only fails the path check';
  }
  const reason = new RegExp(`^(5-only|feature|test-only|docs-only|superseded by ${SHA})(?:: (.*))?$`).exec(row.note);
  if (!reason) return 'n/a needs 5-only, feature, test-only, docs-only or superseded by <sha7>';
  if (!reason[2]?.trim()) return `${reason[1]} needs a reason`;
  return undefined;
}

export function audit(file, to, through) {
  const all = registerRows(readFileSync(file, 'utf8'));
  const problems = [];
  for (const row of all) {
    if (through !== undefined && !(Number(row.id) <= through)) continue;
    const problem = rowProblem(row);
    if (problem !== undefined) problems.push(`row ${row.id}: ${problem}`);
  }
  if (through === undefined) {
    const shas = all.map(row => /^\S+/.exec(row.item)?.[0] ?? '');
    for (const line of rows(TAG, to)) {
      const sha = line.split(' ')[0];
      if (!shas.some(other => other.length >= 7 && (other.startsWith(sha) || sha.startsWith(other)))) problems.push(`${line}: not a row`);
    }
  }
  return problems;
}

function usage() {
  console.error('usage: node scripts/dagents-backport.mjs rows <from> <to> | five-only <sha> | audit <register> <to> [--through <id>]');
  return 2;
}

function main(args) {
  const [command, ...rest] = args;
  if (command === 'rows' && rest.length === 2) {
    for (const line of rows(rest[0], rest[1])) console.log(line);
    return 0;
  }
  if (command === 'five-only' && rest.length === 1) return fiveOnly(rest[0]) ? 0 : 1;
  if (command === 'audit' && (rest.length === 2 || (rest.length === 4 && rest[2] === '--through' && /^\d+$/.test(rest[3])))) {
    const problems = audit(rest[0], rest[1], rest.length === 4 ? Number(rest[3]) : undefined);
    for (const problem of problems) console.log(problem);
    return problems.length === 0 ? 0 : 1;
  }
  return usage();
}

if (process.argv[1] && pathToFileURL(process.argv[1]).href === import.meta.url) {
  try {
    process.exitCode = main(process.argv.slice(2));
  } catch (error) {
    console.error(`dagents-backport: ${(error.stderr || error.message || String(error)).toString().trim()}`);
    process.exitCode = 2;
  }
}
