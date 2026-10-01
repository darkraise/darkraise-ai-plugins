// A throwaway repository with one plan and the commits that carried it out,
// plus a stub `claude`, so every harness test runs without a model call.
import { chmodSync, mkdirSync, mkdtempSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';

export const PLAN = 'docs/superpowers/plans/2026-09-20-fixture.md';
const FENCE = '```';

function task(n, title, files, evaluation, test, code, message) {
  return [
    `### Task ${n}: ${title}`, '', '**Files:**', ...files, '',
    '**Implementer:** dr-superpowers:impl-sonnet-low', `**Evaluation:** ${evaluation}`, '',
    '- [ ] **Step 1: Write the test**', '', `${FENCE}bash`, ...test, FENCE, '',
    '- [ ] **Step 2: Implement**', '', `${FENCE}bash`, ...code, FENCE, '',
    '- [ ] **Step 3: Commit**', '', `${FENCE}bash`, `git commit -m "${message}"`, FENCE, '',
  ];
}

const GREET_TEST = ['set -e', 'out=$(bash src/greet.sh)', '[ "$out" = "hello" ]'];
const GREET = ['# greets', 'echo hello'];
const SHOUT_TEST = ['set -e', 'out=$(bash src/shout.sh)', '[ "$out" = "HELLO" ]'];
const SHOUT = ['# shouts', 'echo HELLO'];

const PLAN_TEXT = [
  '# Fixture Plan', '', '**Goal:** a fixture', '', '**Plan review:** 2026-09-20 - an earlier verdict', '', '## Global Constraints', '', 'None.', '', '## Contracts', '', 'None.', '', '---', '',
  ...task(1, 'Greet', ['- Create: `src/greet.sh`', '- Test: `tests/greet.test.sh`'], 'files 1 - spec 0 - coupling 0 - risk 0 = 1', GREET_TEST, GREET, 'feat: add greet'),
  ...task(2, 'Shout', ['- Create: `src/shout.sh`', '- Modify: `tests/shout.test.sh`'], 'files 1 - spec 0 - coupling 0 - risk 2 = 3', SHOUT_TEST, SHOUT, 'feat: add shout'),
  ...task(3, 'Notes', ['- Create: `notes.md`'], 'files 0 - spec 0 - coupling 0 - risk 0 = 0', ['true'], ['notes'], 'docs: add notes'),
  ...task(4, 'Already green', ['- Create: `src/idle.sh`', '- Test: `tests/idle.test.sh`'], 'files 1 - spec 0 - coupling 0 - risk 0 = 1', ['true'], ['# idle'], 'feat: add idle'),
].join('\n');

function git(dir, ...args) {
  const r = spawnSync('git', ['-c', 'user.name=fixture', '-c', 'user.email=fixture@example.invalid', ...args], { cwd: dir, encoding: 'utf8' });
  if (r.status !== 0) throw new Error(`git ${args.join(' ')}: ${r.stderr}`);
  return r.stdout.trim();
}

function commit(dir, files, message) {
  for (const [path, lines] of Object.entries(files)) {
    mkdirSync(dirname(join(dir, path)), { recursive: true });
    writeFileSync(join(dir, path), lines.join('\n') + '\n');
  }
  git(dir, 'add', '-A');
  git(dir, 'commit', '-q', '-m', message);
  return git(dir, 'rev-parse', 'HEAD');
}

// fixture — builds the repository, a data directory, a work directory and the
// stub, points the TIER_EVAL_* variables at them, and returns their paths and
// commits. Call it before importing any harness module.
export function fixture() {
  const top = mkdtempSync(join(tmpdir(), 'tier-eval-test-'));
  const repo = join(top, 'repo'), data = join(top, 'data'), work = join(top, 'work'), stub = join(top, 'stub');
  for (const dir of [repo, join(data, 'cases/reviews'), work, stub]) mkdirSync(dir, { recursive: true });
  git(repo, 'init', '-q', '-b', 'main');
  const planned = commit(repo, { [PLAN]: [PLAN_TEXT], 'plugins/dr-superpowers/marker.txt': ['fixture'], '.gitignore': ['node_modules/'] }, 'docs: plan the fixture');
  const greet = commit(repo, { 'src/greet.sh': GREET, 'tests/greet.test.sh': GREET_TEST }, 'feat: add greet');
  const shout = commit(repo, { 'src/shout.sh': SHOUT, 'tests/shout.test.sh': SHOUT_TEST }, 'feat: add shout');
  commit(repo, { 'notes.md': ['notes'] }, 'docs: add notes');
  commit(repo, { 'src/idle.sh': ['# idle'], 'tests/idle.test.sh': ['true'] }, 'feat: add idle');
  writeFileSync(join(stub, 'greet.patch'), spawnSync('git', ['diff', planned, greet], { cwd: repo, encoding: 'utf8' }).stdout);
  writeFileSync(join(stub, 'claude'), `#!/bin/sh\nexec "${process.execPath}" "${fileURLToPath(new URL('./stub-claude.mjs', import.meta.url))}" "$@"\n`);
  chmodSync(join(stub, 'claude'), 0o755);
  writeFileSync(join(data, 'arms.json'), JSON.stringify({
    rows: { 1: ['impl-sonnet-low', 'impl-haiku'], 5: ['impl-opus-medium', 'impl-sonnet-high'] },
    review: ['judge-opus@high', 'judge-sonnet-high'],
    grader: { model: 'opus', effort: 'low' },
  }));
  writeFileSync(join(data, 'cases/reviews/cases.json'), JSON.stringify([
    { id: 'r-code-fixture', kind: 'code', base: planned, head: greet, plan: PLAN, description: 'Adds the greet script.' },
  ]));
  writeFileSync(join(data, 'cases/reviews/r-code-fixture.md'), '# Rubric\n\n## D1: greets in lower case\n\n## D2: no usage text\n');
  Object.assign(process.env, { TIER_EVAL_ROOT: repo, TIER_EVAL_DATA: data, TIER_EVAL_WORK: work, TIER_EVAL_CLAUDE: join(stub, 'claude'), STUB_DIR: stub });
  return { top, repo, data, work, stub, planned, greet, shout };
}

// modes — the stub's replies, one mode per call; the last mode repeats.
export function modes(stub, ...list) {
  writeFileSync(join(stub, 'modes'), list.join('\n') + '\n');
}
