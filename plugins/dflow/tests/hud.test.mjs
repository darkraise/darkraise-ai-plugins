import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';
import { bandText, bar, isFreshReset, nextMode, paneRows } from '../hooks/hud/view.mjs';
import { PLUGIN, dflow, git, makeProject, read, write } from './helpers.mjs';

const hud = root => JSON.parse(read(root, '.dflow/hud.json'));

test('the CLI rewrites hud.json on every state change', t => {
  const root = makeProject(t);
  dflow(root, ['next']);
  let model = hud(root);
  assert.deepEqual([model.plan.title, model.plan.done, model.plan.total, model.plan.current.state], ['Rate-limit meter', 0, 2, 'wip']);
  assert.deepEqual([model.gates, model.review.recorded, model.board.row.state, model.sync.enabled], [null, null, 'planned', false]);

  write(root, 'verify1.mjs', 'process.exit(1)\n');
  write(root, 'src/limit.mjs', '1\n');
  git(root, 'add', 'src');
  dflow(root, ['done', '1', '-m', 'feat: parse']);
  assert.equal(hud(root).plan.current.attempts, 1);

  write(root, 'verify1.mjs', '\n');
  dflow(root, ['done', '1', '-m', 'feat: parse']);
  model = hud(root);
  assert.deepEqual([model.plan.done, model.plan.current.number, model.board.row.state], [1, 2, 'doing']);

  dflow(root, ['block', '2', 'waiting for the design']);
  assert.deepEqual(hud(root).plan.blocked, [{ number: 2, reason: 'waiting for the design' }]);
  dflow(root, ['review', 'add', '--file', 'src/limit.mjs', '--line', '1', '--severity', 'blocking', '--claim', 'c', '--breaks', 'b', '--cmd', 'false']);
  assert.deepEqual([hud(root).review.open, hud(root).review.blocking], [1, 1]);
});

test('done leaves a reset flag for the mod when the context passes the threshold', t => {
  const root = makeProject(t);
  write(root, 'verify1.mjs', '\n');
  write(root, 'src/limit.mjs', '1\n');
  git(root, 'add', 'src');
  write(root, '.dflow/context.json', JSON.stringify({ tokens: 200000, window: 1000000, at: new Date().toISOString() }));
  dflow(root, ['done', '1', '-m', 'feat: parse']);
  const flag = JSON.parse(read(root, '.dflow/reset.json'));
  assert.equal(flag.plan, '2026-11-12-meter');
  assert.ok(isFreshReset(flag, Date.now()));
  assert.ok(!isFreshReset(flag, Date.now() + 11 * 60 * 1000));
  assert.ok(!isFreshReset({}, Date.now()));
});

test('the band fits its width and the mode cycles', () => {
  const model = { branch: 'feat/x', next: 'n', plan: { title: 'A long plan title for the meter', done: 1, total: 4, current: { number: 2, state: 'wip', title: 't' }, blocked: [] }, context: { resetAt: 150000 } };
  assert.equal(bar(1, 4, 8), '██░░░░░░');
  assert.equal(bandText(model, { tokens: 90000, window: 1000000 }, 200), 'dflow ▸ A long plan title for the meter · ██░░░░░░ 1/4 · Task 2 wip · ctx 90k/150k');
  assert.equal(bandText(model, null, 30).length, 30);
  assert.deepEqual(['band', 'pane', 'off'].map(mode => nextMode(mode, '')), ['pane', 'off', 'band']);
  assert.deepEqual([nextMode('band', 'off'), nextMode('band', 'sideways')], ['off', null]);
  assert.deepEqual(paneRows({ branch: 'main', next: '/dflow:plan', plan: null }, null, 60).map(row => row[0]), ['', 'Next']);
  const sync = fields => paneRows({ ...model, gates: null, review: null, board: null, sync: { enabled: true, queued: 3, ...fields } }, null, 80).find(row => row[0] === 'darkmem')[1];
  assert.deepEqual([sync({}), sync({ error: 'x', offline: true }), sync({ error: 'x', offline: false }), sync({ refused: 1 })], ['3 queued', 'offline · 3 queued', 'refused: run dflow sync push · 3 queued', '1 refused: run dflow sync push · 3 queued']);
});

test('the mod is wired into hooks.json and the manifest names its state contract', () => {
  const hooks = JSON.parse(fs.readFileSync(path.join(PLUGIN, 'hooks/hooks.json'), 'utf8'));
  assert.deepEqual(hooks.modules, ['./hud/register.tsx']);
  assert.equal(JSON.parse(fs.readFileSync(path.join(PLUGIN, '.claude-plugin/plugin.json'), 'utf8')).types, './types/index.d.ts');
});
