import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';
import { isFreshReset, isResetFor, nextMode } from '../hooks/hud/view.mjs';
import { bar as meterBar, cellWidth, duration, isAtLeast, kTokens, limitForecast, limitLabel, rampColor, runsCut, sparkline, stackedRuns, track, trackRuns, windowElapsed } from '../hooks/hud/meter.mjs';
import { SECTIONS, boardCard, checksCard, collapsedFrom, nextRow, nowRow, planCard, taskWindow, workersCard } from '../hooks/hud/view.mjs';
import { contextCard } from '../hooks/hud/view.mjs';
import { accountColor, accountFrom, accountKey, billingLabel, modelName, remoteRuns } from '../hooks/hud/account.mjs';
import { accountCard } from '../hooks/hud/view.mjs';
import { usageCard } from '../hooks/hud/view.mjs';
import { repoFromPorcelain, repoName, shortDir } from '../hooks/hud/repo.mjs';
import { repoCard } from '../hooks/hud/view.mjs';
import { denseLines } from '../hooks/hud/view.mjs';
import { BAND_TIERS, bandLines, bandTop, bandWarning, fitBand } from '../hooks/hud/band.mjs';
import { sectionsArg, sectionsFrom, sectionsMoved, sectionsToggled } from '../hooks/hud/view.mjs';
import { isOfferOver, resumeOffer } from '../hooks/hud/view.mjs';
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

const BREAKDOWN = { rows: [['Messages', 318000], ['System tools', 41000], ['System prompt', 9000], ['Memory files', 6000], ['Skills', 4000], ['Custom agents', 2000], ['MCP tools', 1000]].map(([name, tokens]) => ({ name, tokens })), compactAt: null, total: 381000 };

test('the Context card reads the window against the reset point', () => {
  const card = contextCard({ hud: PLAN_HUD, context: { tokens: 118000, window: 1000000 }, breakdown: null, readings: [], width: 50 });
  assert.deepEqual([card.key, card.color, text(card.headline)], ['context', 'cyan', '79% of reset']);
  assert.equal(card.headline[0].color, '#ff8700');
  const meter = [...text(card.rows[0])];
  assert.equal(meter.length, 50);
  assert.equal(meter[7], '┃');
  assert.equal(text(card.rows[1]), '118k of 1.0M ┃ resets at 150k');
  const compacting = contextCard({ hud: PLAN_HUD, context: { tokens: 118000, window: 1000000 }, breakdown: { ...BREAKDOWN, compactAt: 967000 }, readings: [100000, 118000], width: 50 });
  assert.equal([...text(compacting.rows[0])][48], '┊');
  assert.equal(text(compacting.rows[1]), '118k of 1.0M ┃ resets at 150k ┊ compacts 967k');
  assert.equal(text(compacting.rows[2]), 'trend ▁█ +18k');
});

test('the breakdown lists the six largest categories under a stacked bar', () => {
  const card = contextCard({ hud: PLAN_HUD, context: { tokens: 118000, window: 1000000 }, breakdown: BREAKDOWN, readings: [], width: 50 });
  const stack = card.rows[2];
  assert.equal(stack.reduce((sum, run) => sum + run.text.length, 0), 50);
  assert.deepEqual(stack.map(run => run.color), ['cyan', 'magenta', 'yellow', 'green', 'blue', 'red']);
  const rows = card.rows.slice(3).map(text);
  assert.equal(rows.length, 6);
  assert.match(rows[0], /^ {2}■ Messages +318k +84%$/);
  assert.ok(!rows.some(row => row.includes('MCP tools')));
});

test('before a reading the Context card shows the estimate', () => {
  const card = contextCard({ hud: PLAN_HUD, context: { window: 1000000 }, breakdown: { ...BREAKDOWN, total: 37000 }, readings: [], width: 50 });
  assert.equal(text(card.headline), '≈37k estimated');
  assert.ok(!card.rows.some(row => text(row).includes('▰')));
  assert.equal(text(contextCard({ hud: PLAN_HUD, context: { window: 1000000 }, breakdown: null, readings: [], width: 50 }).headline), 'no reading yet');
  assert.equal(contextCard({ hud: { ...PLAN_HUD, context: null }, context: null, breakdown: null, readings: [], width: 50 }), null);
  const unset = contextCard({ hud: { ...PLAN_HUD, context: null }, context: { tokens: 118000, window: 1000000 }, breakdown: null, readings: [], width: 50 });
  assert.equal(text(unset.headline), '118k of 1.0M');
  assert.ok(!text(unset.rows[0]).includes('┃'));
  assert.equal(text(unset.rows[1]), '118k of 1.0M');
});

const CLAUDE_JSON = { oauthAccount: { emailAddress: 'you@example.com', displayName: 'You', organizationName: 'Acme', organizationRole: 'admin', billingType: 'stripe_subscription' } };

test('the account comes from .claude.json with a color of its own', () => {
  const account = accountFrom(CLAUDE_JSON, '', '/home/me');
  assert.deepEqual([account.email, account.name, account.organization, account.role, account.billing, account.key], ['you@example.com', 'You', 'Acme', 'admin', 'stripe_subscription', '~/.claude']);
  assert.equal(account.color, accountColor('~/.claude'));
  assert.equal(accountKey('/home/me/.claude-alt', '/home/me'), '~/.claude-alt');
  assert.deepEqual([billingLabel('stripe_subscription'), billingLabel(null), modelName('claude-opus-5-5[1m]')], ['subscription', null, 'Opus 5.5']);
  assert.equal(accountFrom({}, '', '/home/me').email, null);
  assert.deepEqual([remoteRuns([{ surface: 'mobile' }], null), remoteRuns([], 'true'), remoteRuns([], null)].map(text), ['● connected · phone', '○ on · no device yet', '○ not connected']);
});

test('the Account card lists who, which model and where', () => {
  const card = accountCard({ account: accountFrom(CLAUDE_JSON, '', '/home/me'), engine: { model: 'claude-opus-5-5', effort: 'xhigh' }, remote: { clients: [{ surface: 'mobile' }], setting: null } });
  assert.deepEqual([card.key, card.title, text(card.headline)], ['account', 'Account', 'subscription']);
  assert.deepEqual(rowsOf(card), ['● you@example.com', '  You · Acme (admin)', '  Opus 5.5 · xhigh effort', '  Remote ● connected · phone', '  config ~/.claude']);
  const bare = accountCard({ account: accountFrom({}, '', '/home/me'), engine: { model: 'claude-opus-5-5', effort: 'xhigh' }, remote: { clients: [], setting: null } });
  assert.deepEqual(rowsOf(bare), ['  config ~/.claude']);
});

test('the Usage card draws each window with its share, reset and pace', () => {
  const now = 1_000_000_000_000;
  const card = usageCard({ usage: { limits: [{ kind: 'five_hour', percent: 23, resetsAt: now + 3 * H + 40 * 60_000 }, { kind: 'seven_day', percent: 61, resetsAt: now + (2 * 24 + 19) * H }, { kind: 'spend_limit', percent: 42, resetsAt: null }], usd: 4.86, startedAt: now - 2 * H }, now, width: 50 });
  assert.deepEqual([card.key, card.color, text(card.headline)], ['usage', 'blue', '$4.86 · $2.43/h']);
  const rows = rowsOf(card);
  assert.match(rows[0], /^5h {2}[▰▱┊]+ {2}23%$/);
  assert.ok(rows[0].includes('┊'));
  assert.equal(rows[1], '    resets in 3h40m · on pace');
  assert.match(rows[3], /^ {4}resets in 2d19h · out in \d+d\d+h$/);
  assert.equal(rows[4], 'spend 42%');
  assert.equal(card.rows[1].at(-1).color, 'green');
  const young = usageCard({ usage: { limits: [{ kind: 'five_hour', percent: 2, resetsAt: now + 4 * H + 55 * 60_000 }], usd: null, startedAt: now }, now, width: 50 });
  assert.equal(rowsOf(young)[1], '    resets in 4h55m');
});

test('the Usage card without windows shows the cost alone, and nothing without either', () => {
  const now = 1_000_000_000_000;
  const card = usageCard({ usage: { limits: [], usd: 4.8, startedAt: now - 2 * H }, now, width: 50 });
  assert.deepEqual([text(card.headline), card.rows], ['$4.80 · $2.40/h', []]);
  assert.equal(usageCard({ usage: { limits: [], usd: null, startedAt: now }, now, width: 50 }), null);
  assert.equal(usageCard({ usage: null, now, width: 50 }), null);
});

const PORCELAIN = '# branch.oid abc1234def\n# branch.head feat/x\n# branch.ab +3 -1\n1 .M N... 100644 100644 100644 a b src/a.mjs\r\n1 M. N... 100644 100644 100644 a b src/b.mjs\n? notes.txt\n';

test('git porcelain, the repository name and the folder', () => {
  assert.deepEqual(repoFromPorcelain(PORCELAIN), { branch: 'feat/x', ahead: 3, behind: 1, changed: 2, untracked: 1 });
  assert.equal(repoFromPorcelain('# branch.oid abc1234def\n# branch.head (detached)\n').branch, '@abc1234');
  assert.equal(repoFromPorcelain(''), null);
  assert.deepEqual([repoName('git@github.com:darkraise/shop.git', '/x/shop'), repoName('https://github.com/darkraise/shop', '/x'), repoName(null, '/home/me/code/shop')], ['darkraise/shop', 'darkraise/shop', 'shop']);
  assert.deepEqual([shortDir('/home/me/code/shop', '/home/me'), shortDir('C:\\Users\\me\\shop', 'C:\\Users\\me'), shortDir('/srv/shop', '/home/me')], ['~/code/shop', '~/shop', '/srv/shop']);
});

test('the Repo card reads dirty or clean', () => {
  const where = { cwd: '/home/me/code/shop', root: '/home/me/code/shop', home: '/home/me', remote: 'git@github.com:darkraise/shop.git' };
  const card = repoCard({ repo: repoFromPorcelain(PORCELAIN), where });
  assert.deepEqual([card.key, card.color, text(card.headline)], ['repo', 'green', '● dirty']);
  assert.deepEqual(rowsOf(card), ['repo darkraise/shop', 'dir  ~/code/shop', '⎇ feat/x ↑3 ↓1', '~2 changed ?1 untracked']);
  const clean = repoCard({ repo: { branch: 'main', ahead: 0, behind: 0, changed: 0, untracked: 0 }, where: { ...where, remote: null } });
  assert.deepEqual([text(clean.headline), rowsOf(clean)], ['✓ clean', ['repo shop', 'dir  ~/code/shop', '⎇ main', 'clean']]);
  assert.deepEqual(rowsOf(repoCard({ repo: null, where })), ['dir  ~/code/shop']);
});

test('the dense layout is one labelled line per card', () => {
  const now = 1_000_000_000_000;
  const input = {
    hud: PLAN_HUD,
    account: accountFrom(CLAUDE_JSON, '', '/home/me'),
    remote: { clients: [{ surface: 'mobile' }], setting: null },
    context: { tokens: 118000, window: 1000000 },
    usage: { limits: [{ kind: 'five_hour', percent: 23, resetsAt: now + 3 * H + 40 * 60_000 }, { kind: 'seven_day', percent: 61, resetsAt: now + 4 * 24 * H }], usd: 4.85, startedAt: now - 2 * H },
    now,
    repo: repoFromPorcelain(PORCELAIN),
    where: { cwd: '/home/me/code/shop', root: '/home/me/code/shop', home: '/home/me', remote: null },
    shown: ['account', 'plan', 'context', 'usage', 'checks', 'board', 'workers', 'repo'],
  };
  const lines = denseLines(input, 56).map(text);
  assert.deepEqual(lines.map(line => line.split(' ')[0]), ['acct', 'plan', 'ctx', 'lim', 'chk', 'board', 'work', 'repo', 'next']);
  assert.equal(lines[0], 'acct  you@example.com · subscription · Remote ●');
  assert.match(lines[1], /^plan  [▰▱]{8} 4\/7 · Task 5 · 1 blocked$/);
  assert.match(lines[2], /^ctx   [▰▱┃]{8} 79% of reset · 118k$/);
  assert.equal(lines[4], 'chk   gates not run · review 1 blocking');
  assert.equal(lines[6], 'work  Task 7');
  assert.equal(lines[7], 'repo  ⎇ feat/x* ↑3 ↓1 ~2 ?1');
  assert.ok(denseLines({ ...input, hud: { ...PLAN_HUD, workers: [] } }, 56).every(line => !text(line).startsWith('work')));
  assert.ok(denseLines(input, 30).every(line => cellWidth(text(line)) <= 30));
  assert.deepEqual(denseLines({ ...input, shown: ['repo', 'plan'] }, 56).map(line => text(line).split(' ')[0]), ['repo', 'plan', 'next']);
  const noReset = denseLines({ ...input, hud: { ...PLAN_HUD, context: null } }, 56).map(text).find(line => line.startsWith('ctx'));
  assert.match(noReset, /^ctx {3}[▰▱]{8} 118k of 1\.0M$/);
});

const BAND_INPUT = {
  hud: PLAN_HUD,
  where: { cwd: '/home/me/code/shop', root: '/home/me/code/shop', home: '/home/me', remote: 'git@github.com:darkraise/shop.git' },
  repo: repoFromPorcelain(PORCELAIN),
  engine: { model: 'claude-opus-5-5', effort: 'xhigh' },
  account: accountFrom(CLAUDE_JSON, '', '/home/me'),
  remote: { clients: [{ surface: 'mobile' }], setting: null },
  context: { tokens: 118000, window: 1000000 },
  usage: { limits: [{ kind: 'five_hour', percent: 23, resetsAt: 1_000_000_000_000 + 3 * H + 40 * 60_000 }, { kind: 'seven_day', percent: 61, resetsAt: 1_000_000_000_000 + 4 * 24 * H }], usd: 1.2, startedAt: 1_000_000_000_000 - H },
  now: 1_000_000_000_000,
};

test('the band carries the folder, model, plan and workers, then the readings', () => {
  const [one, two] = bandLines(BAND_INPUT, 0).map(text);
  for (const part of ['~/code/shop', '⎇ feat/x', '↑3', 'Opus 5.5', 'xhigh', 'dflow 4/7 · Task 5', '● 1 worker']) assert.ok(one.includes(part), part);
  for (const part of ['ctx ', '79%', '5h ', '23% on pace', '7d ', '61%', '$1.20']) assert.ok(two.includes(part), part);
  assert.ok(!bandLines({ ...BAND_INPUT, hud: { ...PLAN_HUD, plan: null } }, 0).map(text)[0].includes('dflow'));
  assert.equal(text(bandTop(BAND_INPUT)), 'you@example.com · subscription · Remote ● connected');
});

test('each band line shrinks a tier at a time until it fits', () => {
  for (const width of [196, 116, 76, 44]) {
    for (const line of fitBand(BAND_INPUT, width)) assert.ok(cellWidth(text(line)) <= width, `${width}: ${text(line)}`);
  }
  const widths = Array.from({ length: BAND_TIERS }, (_, tier) => cellWidth(text(bandLines(BAND_INPUT, tier)[1])));
  assert.deepEqual([...widths].sort((a, b) => b - a), widths);
  assert.ok(text(fitBand(BAND_INPUT, 44)[0]).startsWith('shop'));
  const noReset = text(bandLines({ ...BAND_INPUT, hud: { ...PLAN_HUD, context: null } }, 0)[1]);
  assert.ok(noReset.startsWith('ctx ') && noReset.includes('118k of 1.0M') && !noReset.includes('NaN') && !noReset.includes('┃'));
});

test('a blocked task, failed gates or a darkmem conflict make a warning line', () => {
  assert.deepEqual(bandWarning({ ...PLAN_HUD, sync: { enabled: false } }).map(run => run.text).join(''), '✗ Task 6 blocked');
  const all = bandWarning({ ...PLAN_HUD, gates: { ok: false, stale: false, failed: ['lint'] }, sync: { enabled: true, conflict: 'c' } });
  assert.equal(text(all), '✗ Task 6 blocked · ✗ gates failed · ✗ darkmem conflict');
  assert.ok(all.filter(run => run.text !== ' · ').every(run => run.color === 'red'));
  assert.deepEqual(bandWarning({ ...PLAN_HUD, plan: { ...PLAN_HUD.plan, blocked: [] }, sync: { enabled: false } }), []);
  assert.deepEqual(['band', 'pane', 'off'].map(mode => nextMode(mode, '')), ['pane', 'off', 'band']);
  assert.deepEqual([nextMode('band', 'off'), nextMode('band', 'sideways')], ['off', null]);
});

test('the sections list is parsed, toggled and moved', () => {
  assert.deepEqual(sectionsFrom(undefined), SECTIONS);
  assert.deepEqual(sectionsFrom([]), SECTIONS);
  assert.deepEqual(sectionsFrom(['repo', 'nope', 'plan', 'repo']), ['repo', 'plan']);
  assert.deepEqual(sectionsArg('plan, context,repo'), ['plan', 'context', 'repo']);
  assert.equal(sectionsArg('plan,shells'), null);
  assert.equal(sectionsArg(''), null);
  assert.deepEqual(sectionsToggled(['plan', 'context'], 'context'), ['plan']);
  assert.deepEqual(sectionsToggled(['plan', 'context'], 'repo'), ['plan', 'context', 'repo']);
  assert.deepEqual(sectionsMoved(['plan', 'context', 'repo'], 'plan', 1), ['context', 'plan', 'repo']);
  assert.deepEqual(sectionsMoved(['plan', 'context'], 'plan', -1), ['plan', 'context']);
});

test('an approved, unfinished plan with a current task is offered for resuming', () => {
  const approved = { ...PLAN_HUD, plan: { ...PLAN_HUD.plan, approved: '2026-11-12' } };
  assert.deepEqual(resumeOffer(approved), { title: 'Rate-limit meter', next: 'Task 5: Wire the meter (in progress)' });
  assert.equal(resumeOffer({ ...approved, plan: { ...approved.plan, current: { number: 7, title: 'Draw the meter', state: 'todo' } } }).next, 'Task 7: Draw the meter (ready)');
  assert.equal(resumeOffer(PLAN_HUD), null);
  assert.equal(resumeOffer({ ...approved, plan: { ...approved.plan, done: 7, current: null } }), null);
  assert.equal(resumeOffer({ ...approved, plan: { ...approved.plan, current: null } }), null);
  assert.equal(resumeOffer({ ...approved, plan: null }), null);
  assert.equal(isOfferOver(approved, approved), false);
  assert.equal(isOfferOver(approved, { ...approved, plan: { ...approved.plan, done: 5 } }), true);
  assert.equal(isOfferOver(approved, { ...approved, plan: { ...approved.plan, current: { ...approved.plan.current, number: 6 } } }), true);
});
