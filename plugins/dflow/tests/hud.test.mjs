import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';
import { bandText, bar, isFreshReset, isResetFor, nextMode } from '../hooks/hud/view.mjs';
import { bar as meterBar, cellWidth, duration, isAtLeast, kTokens, limitForecast, limitLabel, rampColor, runsCut, sparkline, stackedRuns, track, trackRuns, windowElapsed } from '../hooks/hud/meter.mjs';
import { SECTIONS, boardCard, checksCard, collapsedFrom, nextRow, nowRow, planCard, taskWindow, workersCard } from '../hooks/hud/view.mjs';
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
  write(root, '.dflow/context/sess-a.json', JSON.stringify({ session: 'sess-a', tokens: 200000, window: 1000000, at: new Date().toISOString() }));
  dflow(root, ['done', '1', '-m', 'feat: parse'], { env: { CLAUDE_CODE_SESSION_ID: 'sess-a' } });
  const flag = JSON.parse(read(root, '.dflow/reset.json'));
  assert.deepEqual([flag.plan, flag.session], ['2026-11-12-meter', 'sess-a']);
  assert.ok(isResetFor(flag, Date.now(), 'sess-a'));
  assert.ok(!isResetFor(flag, Date.now(), 'sess-b'), 'another session leaves the flag alone');
  assert.ok(isResetFor({ ...flag, session: null }, Date.now(), 'sess-b'), 'a flag from outside a session is anyone\'s');
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
});

test('the mod is wired into hooks.json and the manifest names its state contract', () => {
  const hooks = JSON.parse(fs.readFileSync(path.join(PLUGIN, 'hooks/hooks.json'), 'utf8'));
  assert.deepEqual(hooks.modules, ['./hud/register.tsx']);
  assert.equal(JSON.parse(fs.readFileSync(path.join(PLUGIN, '.claude-plugin/plugin.json'), 'utf8')).types, './types/index.d.ts');
});

const H = 3_600_000;

test('meter text, colors and labels', () => {
  assert.deepEqual([kTokens(118000), kTokens(999_499), kTokens(999_500), kTokens(967_000)], ['118k', '999k', '1.0M', '967k']);
  assert.deepEqual([duration(59_000), duration(12 * 60_000), duration(220 * 60_000), duration((2 * 1440 + 4 * 60) * 60_000)], ['', '12m', '3h40m', '2d4h']);
  assert.deepEqual([rampColor(49), rampColor(50), rampColor(75), rampColor(90)], ['success', 'warning', '#ff8700', 'error']);
  assert.deepEqual([limitLabel('five_hour'), limitLabel('seven_day'), limitLabel('spend_limit')], ['5h', '7d', 'spend']);
  assert.deepEqual([isAtLeast('2.1.323', '2.1.295'), isAtLeast('2.1.290', '2.1.295'), isAtLeast(undefined, '2.1.295')], [true, false, false]);
});

test('a meter fills to its share and each mark lands on its cell', () => {
  const parts = track(0.118, 40, [{ at: 0.15, glyph: '┃', name: 'reset' }, { at: 0.967, glyph: '┊', name: 'compact' }]);
  const cells = [...parts.map(part => part.text).join('')];
  assert.equal(cells.length, 40);
  assert.equal(cells[6], '┃');
  assert.equal(cells[38], '┊');
  assert.equal(cells.filter(cell => cell === '▰').length, 5);
  assert.equal(meterBar(0.999, 10), '▰▰▰▰▰▰▰▰▰▱');
  const runs = trackRuns(parts, 'success', { reset: 'error' });
  assert.deepStrictEqual(runs.find(run => run.text === '┃'), { text: '┃', color: 'error', bold: true });
  assert.deepStrictEqual(runs.find(run => run.text === '┊'), { text: '┊', color: 'success', bold: true });
  assert.deepStrictEqual(runs[0], { text: '▰▰▰▰▰', color: 'success' });
  assert.equal(runs[1].dim, true);
});

test('sparkline, stacked runs, window share and pace', () => {
  assert.deepEqual([sparkline([100000, 118000]), sparkline([1, 2, 3]), sparkline([5, 5])], ['▁█', '▁▅█', '▄▄']);
  const runs = stackedRuns([318, 41, 9, 6, 4, 2], 50);
  assert.equal(runs.reduce((sum, run) => sum + run, 0), 50);
  assert.ok(runs.every(run => run >= 1));
  const now = 1_000_000_000_000;
  assert.equal(Math.round(windowElapsed('five_hour', now + 3.4 * H, now) * 100), 32);
  assert.equal(windowElapsed('spend_limit', now + H, now), null);
  assert.equal(limitForecast('five_hour', 23, now + (3 * H + 40 * 60_000), now), 'pace');
  assert.equal(typeof limitForecast('seven_day', 61, now + (2 * 24 + 19) * H, now), 'number');
  assert.equal(limitForecast('five_hour', 23, now + (4 * H + 55 * 60_000), now), null);
});

test('widths count terminal cells and a cut row ends in an ellipsis', () => {
  assert.deepEqual([cellWidth('🚀'), cellWidth('é'), cellWidth('Task 5')], [2, 1, 6]);
  assert.deepStrictEqual(runsCut([{ text: 'abcdef', bold: true }], 4), [{ text: 'abc', bold: true }, { text: '…', dim: true }]);
  assert.deepStrictEqual(runsCut([{ text: 'ab🚀' }], 3), [{ text: 'ab' }, { text: '…', dim: true }]);
  assert.deepStrictEqual(runsCut([{ text: 'abc' }], 3), [{ text: 'abc' }]);
});

const text = runs => runs.map(run => run.text).join('');
const rowsOf = card => card.rows.map(text);
const PLAN_HUD = {
  branch: 'feat/x',
  next: '/dflow:build — Task 5: Wire the meter',
  plan: {
    title: 'Rate-limit meter', file: 'docs/dflow/plans/meter.md', done: 4, total: 7,
    current: { number: 5, title: 'Wire the meter', state: 'wip', attempts: 1 },
    blocked: [{ number: 6, reason: 'no API key' }],
    tasks: [
      ...[1, 2, 3, 4].map(number => ({ number, title: `Step ${number}`, state: 'done', run: 'inline' })),
      { number: 5, title: 'Wire the meter', state: 'wip', run: 'inline' },
      { number: 6, title: 'Cache the reading', state: 'blocked', run: 'inline' },
      { number: 7, title: 'Draw the meter', state: 'todo', run: 'worker' },
    ],
  },
  gates: null,
  review: { recorded: null, open: 2, blocking: 1 },
  board: { counts: { todo: 3, doing: 1, blocked: 1 }, row: { number: 12, state: 'doing' } },
  sync: { enabled: true, queued: 3 },
  context: { resetAt: 150000 },
  workers: [{ task: 7, path: '.dflow/workers/7', branch: 'dflow/w7' }],
  checks: ['Task 2 is ticked without a recorded `dflow done`'],
};
const forty = Array.from({ length: 40 }, (_, index) => ({ number: index + 1, title: `T${index + 1}`, state: index < 19 ? 'done' : index === 19 ? 'wip' : 'todo', run: 'inline' }));

test('the Now row names the state of the plan', () => {
  assert.equal(text(nowRow(PLAN_HUD)), '● Task 5 in progress · verify failed 1×');
  assert.equal(text(nowRow({ ...PLAN_HUD, plan: { ...PLAN_HUD.plan, current: { number: 5, title: 't', state: 'todo', attempts: 0 } } })), '● Task 5 ready');
  assert.equal(text(nowRow({ ...PLAN_HUD, plan: { ...PLAN_HUD.plan, done: 7, current: null } })), '✓ All 7 tasks done');
  assert.equal(text(nowRow({ ...PLAN_HUD, plan: { ...PLAN_HUD.plan, current: null } })), '✗ Every remaining task is blocked');
  assert.equal(text(nowRow({ ...PLAN_HUD, plan: null })), '○ No active plan on feat/x');
});

test('the task window centres on the current task and counts what it cuts', () => {
  const window = taskWindow(forty, 20, 8);
  assert.deepEqual([window.rows[0].number, window.rows.at(-1).number, window.above, window.aboveDone, window.below, window.belowDone], [16, 23, 15, true, 17, false]);
  const card = planCard({ ...PLAN_HUD, plan: { ...PLAN_HUD.plan, done: 19, total: 40, current: { number: 20, title: 'T20', state: 'wip', attempts: 0 }, blocked: [], tasks: forty } });
  assert.equal(rowsOf(card).filter(row => /^[✓▸✗○] Task/.test(row)).length, 8);
  assert.ok(rowsOf(card).includes('… 15 more done'));
  assert.ok(rowsOf(card).includes('… 17 more'));
});

test('the Plan card lists tasks with their glyphs, details and checks', () => {
  const card = planCard(PLAN_HUD);
  assert.deepEqual([card.key, card.title, card.color, text(card.headline)], ['plan', 'Plan', 'yellow', '4/7 · 1 blocked']);
  assert.equal(card.headline.find(run => run.text.includes('blocked')).color, 'red');
  const rows = rowsOf(card);
  for (const row of ['Rate-limit meter', 'docs/dflow/plans/meter.md', '✓ Task 4: Step 4', '▸ Task 5: Wire the meter', '  verify failed 1×', '✗ Task 6: Cache the reading', '  blocked: no API key', '○ Task 7: Draw the meter · worker', '⚠ Task 2 is ticked without a recorded `dflow done`']) assert.ok(rows.includes(row), row);
  assert.equal(text(planCard({ ...PLAN_HUD, plan: { ...PLAN_HUD.plan, done: 7, current: null, blocked: [] } }).headline), '✓ done');
  const none = planCard({ ...PLAN_HUD, plan: null });
  assert.deepEqual([text(none.headline), rowsOf(none)], ['', ['No active plan on feat/x.']]);
  assert.deepEqual(rowsOf(planCard({ ...PLAN_HUD, plan: { ...PLAN_HUD.plan, done: 0, total: 0, current: null, blocked: [], tasks: [] } })).slice(0, 2), ['Rate-limit meter', 'docs/dflow/plans/meter.md']);
});

test('the Checks card puts the worst reading in its headline', () => {
  const headline = hud => text(checksCard(hud).headline);
  assert.equal(checksCard({ ...PLAN_HUD, plan: null }), null);
  assert.equal(headline(PLAN_HUD), '● 1 blocking');
  assert.equal(headline({ ...PLAN_HUD, gates: { ok: false, stale: false, failed: ['lint', 'test'] } }), '✗ failed');
  assert.equal(headline({ ...PLAN_HUD, review: { recorded: null, open: 0, blocking: 0 }, gates: { ok: true, stale: true, failed: [] } }), 'stale');
  assert.equal(headline({ ...PLAN_HUD, review: { recorded: { tier: 2 }, open: 0, blocking: 0 }, gates: { ok: true, stale: false, failed: [] } }), '✓ passed');
  assert.equal(headline({ ...PLAN_HUD, review: { recorded: null, open: 0, blocking: 0 } }), 'not run');
  assert.deepEqual(rowsOf(checksCard({ ...PLAN_HUD, gates: { ok: false, stale: false, failed: ['lint', 'test'] } })), ['Gates   ✗ failed: lint, test', 'Review  not run · 2 open, 1 blocking']);
  assert.deepEqual(rowsOf(checksCard({ ...PLAN_HUD, review: { recorded: { tier: 1 }, open: 2, blocking: 1 } })), ['Gates   not run', 'Review  tier 1 recorded · 2 open, 1 blocking']);
  assert.equal(rowsOf(checksCard({ ...PLAN_HUD, gates: { ok: true, stale: false, failed: [] } }))[0], 'Gates   ✓ passed');
  assert.equal(rowsOf(checksCard({ ...PLAN_HUD, gates: { ok: true, stale: true, failed: [] } }))[0], 'Gates   ✓ passed · stale, the head moved');
});

test('the Board card reads darkmem in five states', () => {
  const card = boardCard(PLAN_HUD);
  assert.deepEqual([text(card.headline), rowsOf(card)[0]], ['#12 doing', '3 todo · 1 doing · 1 blocked']);
  const sync = fields => rowsOf(boardCard({ ...PLAN_HUD, sync: { enabled: true, queued: 3, ...fields } })).at(-1);
  assert.deepEqual(
    [sync({ queued: 0 }), sync({}), sync({ error: 'x', offline: true }), sync({ error: 'x', offline: false }), sync({ refused: 1 }), sync({ conflict: 'c' })],
    ['darkmem ● synced · 0 queued', 'darkmem ◐ 3 queued', 'darkmem ○ offline · 3 queued', 'darkmem ✗ refused: run dflow sync push · 3 queued', 'darkmem ✗ refused: run dflow sync push · 3 queued', 'darkmem ✗ conflict: run dflow sync pull'],
  );
  assert.equal(boardCard({ ...PLAN_HUD, board: null, sync: { enabled: false } }), null);
  assert.deepEqual(rowsOf(boardCard({ ...PLAN_HUD, board: null })), ['darkmem ◐ 3 queued']);
  assert.equal(text(boardCard({ ...PLAN_HUD, board: { counts: { todo: 3, done: 1 }, row: null } }).headline), '4 rows');
});

test('the Workers card, the Next row and the stored collapse list', () => {
  const card = workersCard({ ...PLAN_HUD, workers: [{ task: 6, branch: 'dflow/w6' }, { task: 7, branch: 'dflow/w7' }] });
  assert.deepEqual([text(card.headline), rowsOf(card)], ['● 2 running', ['● Task 6: Cache the reading  dflow/w6', '● Task 7: Draw the meter  dflow/w7']]);
  assert.equal(workersCard({ ...PLAN_HUD, workers: [] }), null);
  assert.equal(text(nextRow(PLAN_HUD)), 'Next  /dflow:build — Task 5: Wire the meter');
  assert.deepEqual(SECTIONS, ['account', 'plan', 'context', 'usage', 'checks', 'board', 'workers', 'repo']);
  assert.deepEqual([collapsedFrom(['plan', 'nope', 'plan', 'repo']), collapsedFrom('plan'), collapsedFrom(undefined)], [['plan', 'repo'], [], []]);
});
