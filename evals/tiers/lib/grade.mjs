import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { git, run, sh } from './sh.mjs';

const TEST_SECONDS = 900;

// overlayTests DIR RESULT TESTS — write RESULT's version of each test file
// into DIR, so a run cannot pass by editing a test. False when RESULT lacks one.
export function overlayTests(dir, result, tests) {
  for (const test of tests) {
    const shown = sh('git', ['show', `${result}:${test}`]);
    if (shown.code !== 0) return false;
    mkdirSync(dirname(join(dir, test)), { recursive: true });
    writeFileSync(join(dir, test), shown.out);
  }
  return true;
}

export async function runTests(dir, tests) {
  for (const test of tests) {
    const [cmd, args] = test.endsWith('.mjs') ? [process.execPath, ['--test', test]] : ['bash', [test]];
    const r = await run(cmd, args, { cwd: dir, seconds: TEST_SECONDS });
    if (r.code !== 0 || r.timedOut) return { pass: false, failed: test };
  }
  return { pass: true, failed: null };
}

// changedFiles DIR SINCE — every path that differs from commit SINCE,
// committed or not, plus untracked files git does not ignore. The brief and
// the report live under .superpowers/ and are the harness's, not the run's.
export function changedFiles(dir, since) {
  const tracked = git(['diff', '--name-only', since], { cwd: dir });
  const untracked = git(['ls-files', '--others', '--exclude-standard'], { cwd: dir });
  return [...new Set((tracked + untracked).split('\n').filter(p => p && !p.startsWith('.superpowers/')))].sort();
}

export function statusWord(message) {
  return message.match(/\b(DONE_WITH_CONCERNS|NEEDS_CONTEXT|BLOCKED|DONE)\b/)?.[1] ?? null;
}

export function outcome({ testsPass, outside, status, cutShort }) {
  if (cutShort || status === null || status === 'BLOCKED' || status === 'NEEDS_CONTEXT') return 'BLOCKED';
  return testsPass && outside.length === 0 ? 'PASS' : 'FAIL';
}
