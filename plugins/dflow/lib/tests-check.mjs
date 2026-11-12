import { git, gitList, matchesAny } from './util.mjs';

const ASSERTION = /\b(assert|expect|should)\w*/i;
const SKIP = /\b(it|test|describe)\.(skip|todo)\b|\bx(it|describe|test)\s*\(|@(skip|ignore|disabled)\b|\bt\.Skip\(|pytest\.mark\.skip|#\[ignore\]|\bskip:\s*true/i;

export function isTestFile(config, file) {
  return matchesAny(config.tests.patterns, file);
}

// Ways a diff makes existing tests prove less: a test file deleted, a skip
// marker added, or more assertion lines removed than added in one file. A
// file the diff adds had nothing to weaken.
export function weakenedTests(ctx, diffArgs) {
  const fields = gitList(ctx.root, ['diff', ...diffArgs, '--name-status', '-M', '-z']);
  const found = [];
  for (let index = 0; index < fields.length;) {
    const kind = fields[index];
    const renamed = kind[0] === 'R' || kind[0] === 'C';
    const from = fields[index + 1];
    const file = renamed ? fields[index + 2] : from;
    index += renamed ? 3 : 2;
    const wasTest = isTestFile(ctx.config, from);
    const isTest = isTestFile(ctx.config, file);
    if (kind === 'A' || kind[0] === 'C' || !(wasTest || isTest)) continue;
    // A test renamed to a path no test pattern matches is no longer run: as
    // good as deleted, whatever its content.
    if (renamed && wasTest && !isTest) {
      found.push(`${from}: test file moved to ${file}, which no test pattern matches`);
      continue;
    }
    // A moved test with unchanged content proves what it did before.
    if (kind === 'R100') continue;
    if (kind === 'D') {
      found.push(`${file}: test file deleted`);
      continue;
    }
    const patch = git(ctx.root, ['diff', ...diffArgs, '-M', '-U0', '--', from, file]).stdout.split('\n');
    const added = patch.filter(text => text.startsWith('+') && !text.startsWith('+++'));
    const removed = patch.filter(text => text.startsWith('-') && !text.startsWith('---'));
    if (added.some(text => SKIP.test(text))) found.push(`${file}: a skip marker was added`);
    const lost = removed.filter(text => ASSERTION.test(text)).length - added.filter(text => ASSERTION.test(text)).length;
    if (lost > 0) found.push(`${file}: ${lost} more assertion line(s) removed than added`);
  }
  return found;
}
