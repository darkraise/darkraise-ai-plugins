import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';
import { bandText, bar, isFreshReset, isResetFor, nextMode, paneRows } from '../hooks/hud/view.mjs';
import { bar as meterBar, cellWidth, duration, isAtLeast, kTokens, limitForecast, limitLabel, rampColor, runsCut, sparkline, stackedRuns, track, trackRuns, windowElapsed } from '../hooks/hud/meter.mjs';
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
  assert.deepEqual(paneRows({ branch: 'main', next: '/dflow:plan', plan: null }, null, 60).map(row => row[0]), ['', 'Next']);
  const sync = fields => paneRows({ ...model, gates: null, review: null, board: null, sync: { enabled: true, queued: 3, ...fields } }, null, 80).find(row => row[0] === 'darkmem')[1];
  assert.deepEqual([sync({}), sync({ error: 'x', offline: true }), sync({ error: 'x', offline: false }), sync({ refused: 1 })], ['3 queued', 'offline · 3 queued', 'refused: run dflow sync push · 3 queued', '1 refused: run dflow sync push · 3 queued']);
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
