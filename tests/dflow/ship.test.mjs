import assert from 'node:assert/strict';
import test from 'node:test';
import { parseBoard } from '../../plugins/dflow/lib/board.mjs';
import { parsePlan } from '../../plugins/dflow/lib/plan.mjs';
import fs from 'node:fs';
import path from 'node:path';
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
    'Not done: 5 condition(s) of the definition of done are unmet.',
    '- A2 (UI) has no proof; drive it in the running app and record it with `dflow proof A2`',
    '- A3 (UI) has no proof; drive it in the running app and record it with `dflow proof A3`',
    '- no review is recorded; this diff needs tier 0 (/dflow:review)',
    '- Docs names project.md, but this branch does not change it',
    '- Docs names decisions.md, but the plan log has no `D:` line to promote and the file is unchanged',
    'Not yet run, `dflow ship` runs them: the gates: test; A1: `node check.mjs`',
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
  const check = dflow(root, ['ship', '--check']);
  assert.equal(check.status, 0);
  assert.match(check.stdout, /^Nothing is unmet at [0-9a-f]{7}\. `dflow ship` still has to run: the gates: test; A1: `node check\.mjs`/);
  shipped = dflow(root, ['ship']);
  assert.equal(shipped.status, 0, shipped.stdout + shipped.stderr);
  assert.match(shipped.stdout, /^Shipped docs\/dflow\/plans\/2026-11-12-meter\.md at [0-9a-f]{7}; promoted 1 decision\(s\) to decisions\.md and 1 gotcha\(s\) to gotchas\.md\. Board row 1 is done\./m);
  assert.match(shipped.stdout, /- a parser function, not a class/);
  assert.match(shipped.stdout, /open a pull request, or merge into main/);

  assert.match(read(root, 'docs/dflow/decisions.md'), /## D-2026-11-12-meter\/1 · 2026-11-12\n\na parser function, not a class, because there is one call site\n\nSource: plans\/2026-11-12-meter\.md, Task 1\n$/);
  assert.match(read(root, 'docs/dflow/gotchas.md'), /- the suite needs TZ=UTC or the date tests fail \(plans\/2026-11-12-meter\.md, 2026-11-12\)\n$/);
  assert.equal(parsePlan(read(root, PLAN_FILE)).fields.shipped, '2026-11-12');
  const row = parseBoard(read(root, 'docs/dflow/board.md')).rows[0];
  assert.deepEqual([row.state, row.note], ['done', 'shipped 2026-11-12']);
  assert.equal(git(root, 'log', '-1', '--format=%s'), 'docs(dflow): ship 2026-11-12-meter');
  assert.match(dflow(root, ['status']).stdout, /no active plan/);
});

test('an Acceptance line changed after approval stops ship until the owner\'s agreement is logged', t => {
  const root = makeProject(t);
  buildAll(root);
  write(root, PLAN_FILE, read(root, PLAN_FILE).replace('- A1: `node check.mjs` passes', '- A1: `true` passes'));
  git(root, 'commit', '-q', '-am', 'docs: loosen A1');
  dflow(root, ['review', 'record', '--tier', '0']);
  let check = dflow(root, ['ship', '--check']);
  assert.equal(check.status, 1);
  assert.match(check.stdout, /- Acceptance A1 changed after approval with no record of the owner agreeing \(was: `node check\.mjs` passes; now: `true` passes\)/);
  assert.match(dflow(root, ['status']).stdout, /^Check {3}Acceptance A1 changed after approval/m);
  assert.match(dflow(root, ['review', 'pack']).stdout, /Acceptance A1 changed after approval WITHOUT a record of the owner agreeing/);

  dflow(root, ['log', '-', 'A', 'A1: the owner agreed to drop the check script; it now runs `true`']);
  git(root, 'commit', '-q', '-am', 'docs: log the owner decision');
  check = dflow(root, ['ship', '--check']);
  assert.equal(check.status, 0, check.stdout);
});

test('an open blocking finding or a review below the needed tier stops ship', t => {
  const root = makeProject(t, { plan: PLAN.replace('**Risk:** none', '**Risk:** security') });
  buildAll(root);
  dflow(root, ['review', 'add', '--file', 'src/meter.mjs', '--line', '1', '--severity', 'blocking', '--claim', 'c', '--breaks', 'b', '--cmd', 'false']);
  const check = dflow(root, ['ship', '--check']);
  assert.match(check.stdout, /no review is recorded; this diff needs tier 2/);
  assert.match(check.stdout, /1 blocking finding\(s\) are open: F1/);
});

function readyToShip(t, options) {
  const root = makeProject(t, options);
  buildAll(root);
  dflow(root, ['review', 'record', '--tier', '0']);
  return root;
}

test('a refused closing commit leaves the plan unshipped and every file as it was', t => {
  const root = readyToShip(t, { plan: PLAN.replace('**Docs:** none — the fixture has no living docs', '**Docs:** decisions.md') });
  dflow(root, ['log', '1', 'D', 'a function, not a class']);
  git(root, 'commit', '-q', '-am', 'docs: log');
  dflow(root, ['review', 'record', '--tier', '0']);
  write(root, '.git/hooks/pre-commit', '#!/bin/sh\necho refused by the hook >&2\nexit 1\n');
  fs.chmodSync(path.join(root, '.git/hooks/pre-commit'), 0o755);
  const before = [PLAN_FILE, 'docs/dflow/board.md', 'docs/dflow/decisions.md'].map(file => read(root, file));
  const shipped = dflow(root, ['ship']);
  assert.equal(shipped.status, 1);
  // Git for Windows warns about line endings before the hook's own output.
  assert.match(shipped.stdout, /closing commit failed, so the plan is not shipped and nothing was changed:\n(?:.*\n)*refused by the hook$/m);
  assert.deepEqual([PLAN_FILE, 'docs/dflow/board.md', 'docs/dflow/decisions.md'].map(file => read(root, file)), before);
  assert.equal(git(root, 'status', '--porcelain', '--untracked-files=no'), '');
  fs.rmSync(path.join(root, '.git/hooks/pre-commit'));
  assert.equal(dflow(root, ['ship']).status, 0);
});

test('ship commits only what it wrote, and a draft of other work does not block it', t => {
  const root = readyToShip(t);
  write(root, 'docs/dflow/plans/2026-11-13-draft.md', '# Draft\n\n**Branch:** feat/later\n**Goal:** …\n');
  write(root, 'docs/dflow/scratch.md', 'notes\n');
  const shipped = dflow(root, ['ship']);
  assert.equal(shipped.status, 0, shipped.stdout);
  assert.deepEqual(git(root, 'show', '--name-only', '--format=', 'HEAD').split('\n').sort(), ['docs/dflow/board.md', PLAN_FILE]);
  assert.match(git(root, 'status', '--porcelain'), /\?\? docs\/dflow\/plans\/2026-11-13-draft\.md/);
});

test('a task ticked by hand, never through dflow done, stops ship', t => {
  const root = makeProject(t);
  write(root, PLAN_FILE, read(root, PLAN_FILE).replaceAll('- [ ]', '- [x]'));
  git(root, 'commit', '-q', '-am', 'docs: tick by hand');
  dflow(root, ['review', 'record', '--tier', '0']);
  const status = JSON.parse(dflow(root, ['status', '--json']).stdout);
  assert.doesNotMatch(status.next, /^\/dflow:ship/);
  const shipped = dflow(root, ['ship']);
  assert.equal(shipped.status, 1, shipped.stdout);
  assert.match(shipped.stdout, /Task 1 is ticked without a recorded `dflow done`/);
  assert.match(shipped.stdout, /Task 2 is ticked without a recorded `dflow done`/);
});

test('an untracked file outside docs/dflow stops ship, and a gate pass beside it is dirty', t => {
  const root = readyToShip(t, { config: { gates: [{ name: 'test', cmd: 'node suite.mjs' }] } });
  write(root, 'suite.mjs', '\n');
  write(root, 'src/helper.mjs', 'export const h = 1;\n');
  assert.equal(dflow(root, ['gate']).status, 0);
  assert.equal(JSON.parse(dflow(root, ['status', '--json']).stdout).gates.stale, true);
  const check = dflow(root, ['ship', '--check']);
  assert.equal(check.status, 1);
  assert.match(check.stdout, /uncommitted changes: src\/helper\.mjs/);
});

test('code committed after the review, and a gate that passed on uncommitted changes, both stop ship', t => {
  const root = readyToShip(t, { config: { gates: [{ name: 'test', cmd: 'node suite.mjs' }] } });
  write(root, 'suite.mjs', '\n');
  write(root, 'src/meter.mjs', 'export const b = 99;\n');
  assert.equal(dflow(root, ['gate']).status, 0);
  git(root, 'checkout', '-q', '--', 'src/meter.mjs');
  assert.match(dflow(root, ['ship', '--check']).stdout, /still has to run: the gates: test/);

  write(root, 'src/meter.mjs', 'export const b = 3;\n');
  git(root, 'commit', '-q', '-am', 'fix: meter');
  const check = dflow(root, ['ship', '--check']);
  assert.equal(check.status, 1);
  assert.match(check.stdout, /1 file\(s\) changed after the recorded review \(src\/meter\.mjs\); review them and run `dflow review record` again/);
  dflow(root, ['review', 'record', '--tier', '0']);
  assert.equal(dflow(root, ['ship']).status, 0);
});
