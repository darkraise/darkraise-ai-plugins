import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';
import { filesOverlap } from '../../plugins/dflow/lib/commands/parallel.mjs';
import { PLAN, dflow, git, makeProject, read, sh, write } from './helpers.mjs';

const WAVE_PLAN = `${PLAN.replace('## Log\n', '')}### Task 3: Colour the meter
**Files:** src/colour.mjs · **After:** 1 · **Run:** worker · **Size:** S
- [ ] Implement \`colour\`
- [ ] Verify: \`node verify3.mjs\`

### Task 4: Label the meter
**Files:** src/label.mjs · **After:** 1 · **Run:** worker · **Size:** M
- [ ] Implement \`label\`
- [ ] Verify: \`node verify4.mjs\`

### Task 5: Shade the meter
**Files:** src/colour.mjs, src/shade.mjs · **After:** 1 · **Run:** worker · **Size:** S
- [ ] Implement \`shade\`
- [ ] Verify: \`node verify5.mjs\`

## Log
`;

function ready(t) {
  const root = makeProject(t, { plan: WAVE_PLAN });
  for (const number of [1, 2, 3, 4, 5]) write(root, `verify${number}.mjs`, '\n');
  write(root, 'src/limit.mjs', '1\n');
  git(root, 'add', '-A');
  assert.equal(dflow(root, ['done', '1', '-m', 'feat: parse', '--extra', 'verify scripts']).status, 0);
  return root;
}

test('file sets overlap by path prefix', () => {
  assert.ok(filesOverlap(['src/a.mjs'], ['src/a.mjs']));
  assert.ok(filesOverlap(['src/'], ['src/a.mjs']));
  assert.ok(filesOverlap(['src/**/*.ts'], ['src/x/y.ts']));
  assert.ok(!filesOverlap(['src/a.mjs'], ['src/ab.mjs']));
  assert.ok(filesOverlap(['src/limit*.mjs'], ['src/limit.test.mjs']));
  assert.ok(filesOverlap(['*.md'], ['docs/a.md']));
  assert.ok(!filesOverlap(['lib/'], ['src/', 'tests/']));
});

test('a wave lists ready worker tasks with disjoint files, and needs two', t => {
  const fresh = makeProject(t, { plan: WAVE_PLAN });
  assert.match(dflow(fresh, ['wave']).stdout, /^No wave: 0 worker task\(s\)/);
  const root = ready(t);
  const wave = dflow(root, ['wave']);
  assert.match(wave.stdout, /A wave of 2 tasks can run at the same time/);
  assert.deepEqual(JSON.parse(dflow(root, ['wave', '--json']).stdout).map(task => task.number), [3, 4]);
});

test('a worktree starts from the head, and merge stages the worker\'s commits for done', t => {
  const root = ready(t);
  const added = dflow(root, ['worktree', 'add', '3']);
  assert.equal(added.status, 0, added.stderr);
  const brief = /^Read (.*) and do the task it describes\.$/m.exec(added.stdout)[1];
  const directory = brief.replace(/\.brief\.md$/, '');
  assert.match(read(root, path.relative(root, brief)), /### Task 3: Colour the meter[\s\S]*Rules for this task/);
  assert.equal(git(directory, 'rev-parse', 'HEAD'), git(root, 'rev-parse', 'HEAD'));
  assert.ok(fs.existsSync(path.join(directory, 'src/limit.mjs')), 'the worker sees the plan\'s earlier commits');
  assert.deepEqual(JSON.parse(dflow(root, ['wave', '--json']).stdout).map(task => task.number), [4, 5]);
  assert.match(dflow(root, ['worktree', 'merge', '3']).stderr, /made no commit/);

  write(directory, 'src/colour.mjs', 'export const colour = () => "red";\n');
  git(directory, 'add', '-A');
  git(directory, 'commit', '-q', '-m', 'feat: colour');
  const merged = dflow(root, ['worktree', 'merge', '3']);
  assert.equal(merged.status, 0, merged.stderr);
  assert.match(merged.stdout, /Task 3's 1 commit\(s\) .* are staged on the plan branch\. Now: dflow done 3/);
  assert.ok(!fs.existsSync(directory));
  assert.equal(sh(root, 'git', ['rev-parse', '--verify', '-q', 'dflow/2026-11-12-meter-t3']).status, 1);
  const done = dflow(root, ['done', '3', '-m', 'feat(meter): colour']);
  assert.equal(done.status, 0, done.stderr);
  assert.deepEqual(git(root, 'show', '--name-only', '--format=', 'HEAD').split('\n').sort(), ['docs/dflow/plans/2026-11-12-meter.md', 'src/colour.mjs']);
});

test('a worker whose commits do not apply keeps its worktree; drop removes it', t => {
  const root = ready(t);
  const directory = /^Read (.*)\.brief\.md/m.exec(dflow(root, ['worktree', 'add', '3']).stdout)[1];
  write(directory, 'src/limit.mjs', 'worker\n');
  git(directory, 'commit', '-q', '-am', 'feat: clash');
  write(root, 'src/limit.mjs', 'session\n');
  git(root, 'commit', '-q', '-am', 'fix: session edit');
  const merged = dflow(root, ['worktree', 'merge', '3']);
  assert.equal(merged.status, 1);
  assert.match(merged.stderr, /do not apply onto the plan branch/);
  assert.equal(git(root, 'status', '--porcelain', '--untracked-files=no'), '');
  assert.ok(!fs.existsSync(path.join(root, '.git/sequencer')), 'no cherry-pick is left in progress');
  assert.ok(fs.existsSync(directory));
  assert.equal(dflow(root, ['worktree', 'drop', '3']).status, 0);
  assert.ok(!fs.existsSync(directory));
});

test('plans --conflicts reports two open plans with overlapping files', t => {
  const root = ready(t);
  const other = `${root}-second`;
  t.after(() => fs.rmSync(other, { recursive: true, force: true }));
  git(root, 'worktree', 'add', '-q', '-b', 'feat/y', other, 'main');
  write(other, 'docs/dflow/plans/2026-11-12-gauge.md', PLAN.replace('# Rate-limit meter', '# Gauge').replace('feat/x', 'feat/y'));
  let listed = dflow(root, ['plans', '--conflicts']);
  assert.equal(listed.status, 1);
  assert.match(listed.stdout, /2026-11-12-meter\.md · feat\/x · 1\/5/);
  assert.match(listed.stdout, /CONFLICT: 2026-11-12-meter\.md and 2026-11-12-gauge\.md both have unfinished tasks/);

  write(other, 'docs/dflow/plans/2026-11-12-gauge.md', read(other, 'docs/dflow/plans/2026-11-12-gauge.md').replaceAll('src/', 'gauge/').replace('tests/', 'gauge-tests/'));
  listed = dflow(root, ['plans', '--conflicts']);
  assert.equal(listed.status, 0, listed.stdout);
  assert.match(listed.stdout, /No two open plans touch the same files/);
});

test('session prints the background command for a board row', t => {
  const root = ready(t);
  assert.match(dflow(root, ['session', '1']).stdout, /claude --bg '\/dflow:build docs\/dflow\/plans\/2026-11-12-meter\.md'/);
  // A board item is other people's text: it must not reach the shell live.
  write(root, 'docs/dflow/board.md', `${read(root, 'docs/dflow/board.md')}| 2 | Fix $(touch pwned) and it's \`id\` | - | Passes | open | - |\n`);
  const printed = dflow(root, ['session', '2']).stdout.split('\n')[1].trim();
  assert.equal(sh(root, 'sh', ['-c', printed.replace(/^claude --bg/, 'printf %s')]).stdout, "/dflow:plan board row 2: Fix $(touch pwned) and it's `id`");
  assert.ok(!fs.existsSync(path.join(root, 'pwned')));
  assert.equal(dflow(root, ['session', '9']).status, 1);
});
