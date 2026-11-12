import assert from 'node:assert/strict';
import test from 'node:test';
import { parseBoard } from '../lib/board.mjs';
import { parsePlan } from '../lib/plan.mjs';
import { PLAN, PLAN_FILE, dflow, git, makeProject, read, write } from './helpers.mjs';

const UI_PLAN = PLAN.replace('- A1:', '- A2 UI: the meter turns red below 10%\n- A3 UI visual: the meter fills the bar\n- A1:')
  .replace('**Docs:** none — the fixture has no living docs', '**Docs:** project.md, decisions.md')
  .replace('## Tasks', '## UI\n\n- Meter: empty, loading, error and filled states.\n\n## Tasks');

function buildAll(root) {
  for (const name of ['verify1.mjs', 'verify2.mjs', 'check.mjs']) write(root, name, '\n');
  write(root, 'src/limit.mjs', 'export const a = 1;\n');
  git(root, 'add', 'src');
  assert.equal(dflow(root, ['done', '1', '-m', 'feat: parse']).status, 0);
  write(root, 'src/meter.mjs', 'export const b = 2;\n');
  git(root, 'add', 'src');
  assert.equal(dflow(root, ['done', '2', '-m', 'feat: draw']).status, 0);
}

test('ship --check names every unmet condition', t => {
  const root = makeProject(t, { plan: UI_PLAN, config: { gates: [{ name: 'test', cmd: 'node suite.mjs' }] } });
  let check = dflow(root, ['ship', '--check']);
  assert.equal(check.status, 1);
  assert.match(check.stdout, /not every task is done: Task 1, Task 2/);

  buildAll(root);
  check = dflow(root, ['ship', '--check']);
  assert.deepEqual(check.stdout.trim().split('\n'), [
    'Not done: 7 condition(s) of the definition of done are unmet.',
    '- the gates have not passed on this commit; run `dflow gate`',
    '- A1 has not passed on this commit',
    '- A2 (UI) has no proof; drive it in the running app and record it with `dflow proof A2`',
    '- A3 (UI) has no proof; drive it in the running app and record it with `dflow proof A3`',
    '- no review is recorded; this diff needs tier 0 (/dflow:review)',
    '- Docs names project.md, but this branch does not change it',
    '- Docs names decisions.md, but the plan log has no `D:` line to promote and the file is unchanged',
  ]);
});

test('a proof is of a commit, needs text unless visual, and goes stale when a UI file changes', t => {
  const root = makeProject(t, { plan: UI_PLAN });
  buildAll(root);
  write(root, 'shot.png', 'png');
  assert.match(dflow(root, ['proof', 'A1', '--shot', 'shot.png']).stderr, /A1 is not a UI line/);
  assert.match(dflow(root, ['proof', 'A2', '--shot', 'shot.png']).stderr, /proven on text/);
  assert.match(dflow(root, ['proof', 'A2', '--shot', 'none.png', '--text', 'x']).stderr, /no screenshot/);
  write(root, 'src/meter.mjs', 'export const b = 3;\n');
  assert.match(dflow(root, ['proof', 'A3', '--shot', 'shot.png']).stderr, /uncommitted changes/);
  git(root, 'commit', '-q', '-am', 'fix: meter');

  assert.match(dflow(root, ['proof', 'A2', '--shot', 'shot.png', '--text', 'meter has class "low"']).stdout, /^A2 proven at [0-9a-f]{7}: \.dflow\/proof\/2026-11-12-meter\/A2\.png/);
  assert.equal(dflow(root, ['proof', 'A3', '--shot', 'shot.png']).status, 0);
  assert.equal(dflow(root, ['proof', '--list']).status, 0);

  write(root, 'tests/meter.test.mjs', 'assert.ok(1);\n');
  git(root, 'add', '-A', 'tests');
  git(root, 'commit', '-q', '-m', 'test: meter');
  assert.equal(dflow(root, ['proof', '--list']).status, 0, 'a test-only commit leaves the proof valid');

  write(root, 'src/meter.mjs', 'export const b = 4;\n');
  git(root, 'commit', '-q', '-am', 'fix: meter again');
  const stale = dflow(root, ['proof', '--list']);
  assert.equal(stale.status, 1);
  assert.match(stale.stdout, /^A2 stale \(changed since: src\/meter\.mjs\)/m);
});

test('ship runs gates and acceptance, promotes the log, closes the plan and the board row', t => {
  const root = makeProject(t, { config: { gates: [{ name: 'test', cmd: 'node suite.mjs' }] }, plan: PLAN.replace('**Docs:** none — the fixture has no living docs', '**Docs:** decisions.md, gotchas.md') });
  buildAll(root);
  dflow(root, ['log', '1', 'D', 'a parser function, not a class, because there is one call site']);
  dflow(root, ['log', '-', 'G', 'the suite needs TZ=UTC or the date tests fail']);
  git(root, 'commit', '-q', '-am', 'docs: log decisions');
  dflow(root, ['review', 'record', '--tier', '0']);

  write(root, 'suite.mjs', 'process.exit(1)\n');
  write(root, 'check.mjs', 'process.exit(1)\n');
  let shipped = dflow(root, ['ship']);
  assert.equal(shipped.status, 1);
  assert.match(shipped.stdout, /- a gate fails/);
  assert.match(shipped.stdout, /- A1 fails: `node check\.mjs` exited 1/);
  assert.equal(parsePlan(read(root, PLAN_FILE)).fields.shipped, undefined);

  write(root, 'suite.mjs', '\n');
  write(root, 'check.mjs', '\n');
  assert.match(dflow(root, ['ship', '--check']).stdout, /gates have not passed/);
  shipped = dflow(root, ['ship']);
  assert.equal(shipped.status, 0, shipped.stdout + shipped.stderr);
  assert.match(shipped.stdout, /^Shipped docs\/dflow\/plans\/2026-11-12-meter\.md at [0-9a-f]{7}; promoted 1 decision\(s\) to decisions\.md and 1 gotcha\(s\) to gotchas\.md\. Board row 1 is done\./m);
  assert.match(shipped.stdout, /- a parser function, not a class/);
  assert.match(shipped.stdout, /open a pull request, or merge into main/);

  assert.match(read(root, 'docs/dflow/decisions.md'), /## D-0001 · 2026-11-12\n\na parser function, not a class, because there is one call site\n\nSource: plans\/2026-11-12-meter\.md, Task 1\n$/);
  assert.match(read(root, 'docs/dflow/gotchas.md'), /- the suite needs TZ=UTC or the date tests fail \(plans\/2026-11-12-meter\.md, 2026-11-12\)\n$/);
  assert.equal(parsePlan(read(root, PLAN_FILE)).fields.shipped, '2026-11-12');
  const row = parseBoard(read(root, 'docs/dflow/board.md')).rows[0];
  assert.deepEqual([row.state, row.note], ['done', 'shipped 2026-11-12']);
  assert.equal(git(root, 'log', '-1', '--format=%s'), 'docs(dflow): ship 2026-11-12-meter');
  assert.match(dflow(root, ['status']).stdout, /no active plan/);
});

test('an open blocking finding or a review below the needed tier stops ship', t => {
  const root = makeProject(t, { plan: PLAN.replace('**Risk:** none', '**Risk:** security') });
  buildAll(root);
  dflow(root, ['review', 'add', '--file', 'src/meter.mjs', '--line', '1', '--severity', 'blocking', '--claim', 'c', '--breaks', 'b', '--cmd', 'false']);
  const check = dflow(root, ['ship', '--check']);
  assert.match(check.stdout, /no review is recorded; this diff needs tier 2/);
  assert.match(check.stdout, /1 blocking finding\(s\) are open: F1/);
});
