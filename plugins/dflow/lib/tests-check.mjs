import { git, matchesAny } from './util.mjs';

const ASSERTION = /\b(assert|expect|should)\w*/i;
const SKIP = /\b(it|test|describe)\.(skip|todo)\b|\bx(it|describe|test)\s*\(|@(skip|ignore|disabled)\b|\bt\.Skip\(|pytest\.mark\.skip|#\[ignore\]|\bskip:\s*true/i;

export function isTestFile(config, file) {
  return matchesAny(config.tests.patterns, file);
}

// Ways a diff makes existing tests prove less: a test file deleted, a skip
// marker added, or more assertion lines removed than added in one file. A
// file the diff adds had nothing to weaken.
export function weakenedTests(ctx, diffArgs) {
  const status = git(ctx.root, ['diff', ...diffArgs, '--name-status', '--no-renames']);
  const found = [];
  for (const line of status.stdout.split('\n').filter(Boolean)) {
    const [kind, file] = line.split('\t');
    if (kind === 'A' || !isTestFile(ctx.config, file)) continue;
    if (kind === 'D') {
      found.push(`${file}: test file deleted`);
      continue;
    }
    const patch = git(ctx.root, ['diff', ...diffArgs, '-U0', '--', file]).stdout.split('\n');
    const added = patch.filter(text => text.startsWith('+') && !text.startsWith('+++'));
    const removed = patch.filter(text => text.startsWith('-') && !text.startsWith('---'));
    if (added.some(text => SKIP.test(text))) found.push(`${file}: a skip marker was added`);
    const lost = removed.filter(text => ASSERTION.test(text)).length - added.filter(text => ASSERTION.test(text)).length;
    if (lost > 0) found.push(`${file}: ${lost} more assertion line(s) removed than added`);
  }
  return found;
}
