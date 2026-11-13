// Pure text for the HUD, shared by the mod and the Node tests. No engine
// access here: the hooks module passes plain values in.

import { billingLabel, modelName, remoteRuns } from './account.mjs';
import { repoName, shortDir } from './repo.mjs';
import { duration, kTokens, limitForecast, limitLabel, bar as meterBar, rampColor, runsCut, sparkline, stackedRuns, track, trackRuns, windowElapsed } from './meter.mjs';

export const MODES = ['band', 'pane', 'off'];
export const RESET_FRESH_MS = 10 * 60 * 1000;
export const RESET_INSTRUCTIONS = 'A dflow build is in progress; the plan file and the git history hold all task state. Keep only: the plan path, the task in progress with what is finished and what is left inside it, why any uncommitted change was made, decisions not yet recorded with `dflow log`, and instructions the owner gave. Leave out tool output, file contents and finished tasks.';

export function nextMode(current, argument) {
  if (!argument) return MODES[(MODES.indexOf(current) + 1) % MODES.length];
  return MODES.includes(argument) ? argument : null;
}

export function isFreshReset(flag, now) {
  return Boolean(flag && typeof flag.at === 'string' && now - Date.parse(flag.at) < RESET_FRESH_MS);
}

// A flag names the session whose `dflow done` asked for the reset, and only
// that session compacts. One written outside a session names none, and any
// session may take it.
export function isResetFor(flag, now, session) {
  return isFreshReset(flag, now) && (!flag.session || flag.session === session);
}

// One context file per session, so that two sessions open in one checkout
// never read each other's size. lib/context.mjs builds the same name.
export function contextFile(session) {
  return `context/${String(session).replace(/[^A-Za-z0-9_-]/g, '_')}.json`;
}

// The cards of the pane, in the order it shows them by default.
export const SECTIONS = ['account', 'plan', 'context', 'usage', 'checks', 'board', 'workers', 'repo'];

const TASK_ROWS = 8;
const isDone = task => task.state === 'done' || task.state === 'review';
const STATE_WORDS = { todo: 'ready', wip: 'in progress' };

function failedRuns(attempts) {
  return [{ text: `verify failed ${attempts}×`, color: 'yellow' }];
}

export function nowRow(hud) {
  const { plan } = hud;
  if (!plan) return [{ text: `○ No active plan on ${hud.branch ?? 'this checkout'}`, dim: true }];
  const { current } = plan;
  if (current) {
    const runs = [{ text: '●', color: 'cyan' }, { text: ` Task ${current.number} ${STATE_WORDS[current.state] ?? current.state}` }];
    if (current.attempts) runs.push({ text: ' · ' }, ...failedRuns(current.attempts));
    return runs;
  }
  if (plan.done === plan.total) return [{ text: '✓', color: 'green' }, { text: ` All ${plan.total} tasks done` }];
  return [{ text: '✗', color: 'red' }, { text: ' Every remaining task is blocked' }];
}

// At most `size` tasks around the current one (or the first not yet done),
// with how many were cut on each side and whether those are all done.
export function taskWindow(tasks, currentNumber, size) {
  let at = tasks.findIndex(task => task.number === currentNumber);
  if (at < 0) at = tasks.findIndex(task => !isDone(task));
  if (at < 0) at = tasks.length - 1;
  const start = Math.min(Math.max(at - Math.floor(size / 2), 0), Math.max(0, tasks.length - size));
  const rows = tasks.slice(start, start + size);
  const before = tasks.slice(0, start);
  const after = tasks.slice(start + rows.length);
  return { above: before.length, aboveDone: before.every(isDone), rows, below: after.length, belowDone: after.every(isDone) };
}

function overflowRow(count, isAllDone) {
  return [{ text: `… ${count} more${isAllDone ? ' done' : ''}`, dim: true }];
}

function meterRuns(share, width) {
  const cells = meterBar(share, width);
  const filled = cells.replace(/▱+$/, '');
  const runs = [];
  if (filled) runs.push({ text: filled, color: 'green' });
  if (cells.length > filled.length) runs.push({ text: cells.slice(filled.length), dim: true });
  return runs;
}

function taskRows(plan, task) {
  const label = `Task ${task.number}: ${task.title}${task.run === 'worker' ? ' · worker' : ''}`;
  if (plan.current?.number === task.number) {
    const rows = [[{ text: '▸', color: 'cyan', bold: true }, { text: ` ${label}` }]];
    if (plan.current.attempts) rows.push([{ text: '  ' }, ...failedRuns(plan.current.attempts)]);
    return rows;
  }
  if (isDone(task)) return [[{ text: '✓', color: 'green' }, { text: ` ${label}` }]];
  if (task.state === 'blocked') {
    const reason = plan.blocked.find(entry => entry.number === task.number)?.reason;
    const rows = [[{ text: '✗', color: 'red' }, { text: ` ${label}` }]];
    if (reason) rows.push([{ text: `  blocked: ${reason}`, color: 'red' }]);
    return rows;
  }
  return [[{ text: `○ ${label}`, dim: true }]];
}

export function planCard(hud, width = 50) {
  const card = { key: 'plan', title: 'Plan', color: 'yellow', headline: [], rows: [] };
  const { plan } = hud;
  if (!plan) {
    card.rows.push([{ text: `No active plan on ${hud.branch ?? 'this checkout'}.`, dim: true }]);
    return card;
  }
  if (plan.total > 0 && plan.done === plan.total) card.headline = [{ text: '✓ done', color: 'green' }];
  else {
    card.headline = [{ text: `${plan.done}/${plan.total}` }];
    if (plan.blocked.length) card.headline.push({ text: ' · ' }, { text: `${plan.blocked.length} blocked`, color: 'red' });
  }
  card.rows.push([{ text: plan.title, bold: true }], [{ text: plan.file, dim: true }]);
  if (plan.total > 0) card.rows.push(meterRuns(plan.done / plan.total, width));
  const window = taskWindow(plan.tasks ?? [], plan.current?.number, TASK_ROWS);
  if (window.above) card.rows.push(overflowRow(window.above, window.aboveDone));
  for (const task of window.rows) card.rows.push(...taskRows(plan, task));
  if (window.below) card.rows.push(overflowRow(window.below, window.belowDone));
  for (const check of hud.checks ?? []) card.rows.push([{ text: `⚠ ${check}`, color: 'yellow' }]);
  return card;
}

function checksHeadline(gates, review) {
  if (gates && !gates.ok) return [{ text: '✗ failed', color: 'red' }];
  if (review?.blocking) return [{ text: `● ${review.blocking} blocking`, color: 'red' }];
  if (gates?.stale) return [{ text: 'stale', color: 'yellow' }];
  if (gates?.ok) return [{ text: '✓ passed', color: 'green' }];
  return [{ text: 'not run', dim: true }];
}

export function checksCard(hud) {
  if (!hud.plan) return null;
  const { gates, review } = hud;
  let gateRuns = [{ text: 'not run', dim: true }];
  if (gates && !gates.ok) gateRuns = [{ text: `✗ failed: ${gates.failed.join(', ')}`, color: 'red' }];
  else if (gates?.ok) gateRuns = [{ text: '✓ passed', color: 'green' }, ...(gates.stale ? [{ text: ' · stale, the head moved', color: 'yellow' }] : [])];
  const reviewRuns = review?.recorded ? [{ text: `tier ${review.recorded.tier} recorded` }] : [{ text: 'not run', dim: true }];
  if (review?.open) reviewRuns.push({ text: ` · ${review.open} open, ${review.blocking} blocking`, ...(review.blocking ? { color: 'red' } : {}) });
  return {
    key: 'checks',
    title: 'Checks',
    color: 'red',
    headline: checksHeadline(gates, review),
    rows: [[{ text: 'Gates   ' }, ...gateRuns], [{ text: 'Review  ' }, ...reviewRuns]],
  };
}

// A server that cannot be reached and one that answered with a refusal need
// different things from the owner, so they read differently.
function darkmemRow(sync) {
  const queued = `${sync.queued ?? 0} queued`;
  let runs;
  if (sync.conflict) runs = [{ text: '✗ conflict: run dflow sync pull', color: 'red' }];
  else if (sync.error && sync.offline) runs = [{ text: '○', color: 'yellow' }, { text: ` offline · ${queued}` }];
  else if (sync.error || sync.refused) runs = [{ text: '✗ refused: run dflow sync push', color: 'red' }, { text: ` · ${queued}` }];
  else if (sync.queued) runs = [{ text: '◐', color: 'yellow' }, { text: ` ${queued}` }];
  else runs = [{ text: '●', color: 'green' }, { text: ` synced · ${queued}` }];
  return [{ text: 'darkmem ' }, ...runs];
}

export function boardCard(hud) {
  const { board, sync } = hud;
  if (!board && !sync?.enabled) return null;
  const card = { key: 'board', title: 'Board', color: 'white', headline: [], rows: [] };
  if (board) {
    const counts = Object.entries(board.counts);
    if (board.row) card.headline = [{ text: `#${board.row.number} ${board.row.state}` }];
    else if (counts.length) card.headline = [{ text: `${counts.reduce((sum, [, count]) => sum + count, 0)} rows` }];
    if (counts.length) card.rows.push([{ text: counts.map(([state, count]) => `${count} ${state}`).join(' · ') }]);
  }
  if (sync?.enabled) card.rows.push(darkmemRow(sync));
  return card;
}

export function workersCard(hud) {
  if (!hud.workers?.length) return null;
  const titles = new Map((hud.plan?.tasks ?? []).map(task => [task.number, task.title]));
  return {
    key: 'workers',
    title: 'Workers',
    color: 'magenta',
    headline: [{ text: `● ${hud.workers.length} running`, color: 'magenta' }],
    rows: hud.workers.map(worker => {
      const title = titles.get(worker.task);
      const runs = [{ text: '●', color: 'magenta' }, { text: ` Task ${worker.task}${title ? `: ${title}` : ''}` }];
      if (worker.branch) runs.push({ text: `  ${worker.branch}`, dim: true });
      return runs;
    }),
  };
}

export function nextRow(hud) {
  return [{ text: 'Next', bold: true }, { text: `  ${hud.next}` }];
}

export function collapsedFrom(value) {
  if (!Array.isArray(value)) return [];
  return [...new Set(value.filter(key => SECTIONS.includes(key)))];
}

const BREAKDOWN_COLORS = ['cyan', 'magenta', 'yellow', 'green', 'blue', 'red'];
const BREAKDOWN_ROWS = 6;
const TREND_LABEL = 16;

function trendRow(readings, width) {
  const recent = readings.slice(-Math.max(2, width - TREND_LABEL));
  const step = recent[recent.length - 1] - recent[recent.length - 2];
  return [
    { text: 'trend ', dim: true },
    { text: sparkline(recent), color: 'cyan' },
    { text: ` ${step < 0 ? '−' : '+'}${kTokens(Math.abs(step))}`, dim: true },
  ];
}

function breakdownRows(breakdown, width) {
  const top = [...breakdown.rows].sort((a, b) => b.tokens - a.tokens).slice(0, BREAKDOWN_ROWS);
  const sum = top.reduce((total, row) => total + row.tokens, 0);
  const cells = stackedRuns(top.map(row => row.tokens), width);
  const stack = top.flatMap((row, index) => (cells[index] ? [{ text: '█'.repeat(cells[index]), color: BREAKDOWN_COLORS[index] }] : []));
  const details = top.map((row, index) => [
    { text: '  ■ ', color: BREAKDOWN_COLORS[index] },
    { text: row.name.padEnd(20) },
    { text: kTokens(row.tokens).padStart(5), bold: true },
    { text: `${String(Math.round((row.tokens / sum) * 100)).padStart(4)}%`, dim: true },
  ]);
  return [stack, ...details];
}

// The live context against the point where dflow resets it (`┃`) and where
// Claude Code would compact on its own (`┊`), with the local /context
// breakdown below.
export function contextCard({ hud, context, breakdown, readings, width }) {
  const tokens = typeof context?.tokens === 'number' ? context.tokens : null;
  const resetAt = hud.context?.resetAt ?? null;
  const hasBreakdown = Boolean(breakdown?.rows?.length);
  if (tokens === null && resetAt === null && !hasBreakdown) return null;
  const card = { key: 'context', title: 'Context', color: 'cyan', headline: [], rows: [] };
  if (tokens === null) {
    card.headline = [{ text: breakdown?.total ? `≈${kTokens(breakdown.total)} estimated` : 'no reading yet', dim: true }];
  } else {
    const window = context.window;
    const compactAt = breakdown?.compactAt ?? null;
    const ramp = rampColor(resetAt ? (tokens / resetAt) * 100 : (tokens / window) * 100);
    card.headline = resetAt
      ? [{ text: `${Math.round((tokens / resetAt) * 100)}% of reset`, color: ramp }]
      : [{ text: `${kTokens(tokens)} of ${kTokens(window)}`, dim: true }];
    const marks = [];
    if (resetAt) marks.push({ at: resetAt / window, glyph: '┃', name: 'reset' });
    if (compactAt) marks.push({ at: compactAt / window, glyph: '┊', name: 'compact' });
    card.rows.push(trackRuns(track(tokens / window, width, marks), ramp, { reset: ramp, compact: 'gray' }));
    const legend = [{ text: kTokens(tokens), bold: true }, { text: ` of ${kTokens(window)}`, dim: true }];
    if (resetAt) legend.push({ text: ` ┃ resets at ${kTokens(resetAt)}`, color: ramp });
    if (compactAt) legend.push({ text: ` ┊ compacts ${kTokens(compactAt)}`, dim: true });
    card.rows.push(legend);
    if (readings.length >= 2) card.rows.push(trendRow(readings, width));
  }
  if (hasBreakdown) card.rows.push(...breakdownRows(breakdown, width));
  return card;
}

// Who the session runs as. Without an email the account file was not read,
// and only the config directory is known.
export function accountCard({ account, engine, remote }) {
  const billing = billingLabel(account.billing);
  const card = { key: 'account', title: 'Account', color: account.color, headline: billing ? [{ text: billing, dim: true }] : [], rows: [] };
  const config = [{ text: `  config ${account.key}`, dim: true }];
  if (!account.email) {
    card.rows.push(config);
    return card;
  }
  card.rows.push([{ text: '●', color: account.color }, { text: ` ${account.email}` }]);
  const where = account.organization ? `${account.organization}${account.role ? ` (${account.role})` : ''}` : null;
  const who = [account.name, where].filter(Boolean);
  if (who.length) card.rows.push([{ text: `  ${who.join(' · ')}` }]);
  if (engine?.model) card.rows.push([{ text: `  ${modelName(engine.model)}${engine.effort ? ` · ${engine.effort} effort` : ''}` }]);
  if (remote) card.rows.push([{ text: '  Remote ' }, ...remoteRuns(remote.clients, remote.setting)]);
  card.rows.push(config);
  return card;
}

const WINDOWED = ['five_hour', 'seven_day'];

function windowRows(limit, now, width) {
  const ramp = rampColor(limit.percent);
  const elapsed = windowElapsed(limit.kind, limit.resetsAt, now);
  const marks = elapsed === null ? [] : [{ at: elapsed, glyph: '┊', name: 'elapsed' }];
  const meter = [
    { text: `${limitLabel(limit.kind)}  ` },
    ...trackRuns(track(limit.percent / 100, width - 10, marks), ramp, { elapsed: 'gray' }),
    { text: `  ${Math.round(limit.percent)}%`, color: ramp },
  ];
  if (limit.resetsAt === null) return [meter];
  const reset = [{ text: `    resets in ${duration(limit.resetsAt - now)}`, dim: true }];
  const forecast = limitForecast(limit.kind, limit.percent, limit.resetsAt, now);
  if (forecast === 'pace') reset.push({ text: ' · on pace', color: 'green' });
  else if (typeof forecast === 'number') reset.push({ text: ` · out in ${duration(forecast)}`, color: '#ff8700' });
  return [meter, reset];
}

// The rate-limit windows with how far through each one the session is (`┊`),
// and the session's cost.
export function usageCard({ usage, now, width }) {
  if (!usage || (!usage.limits.length && usage.usd === null)) return null;
  const card = { key: 'usage', title: 'Usage', color: 'blue', headline: [], rows: [] };
  if (usage.usd !== null) {
    const hours = (now - usage.startedAt) / 3_600_000;
    const rate = hours >= 1 / 60 ? ` · $${(usage.usd / hours).toFixed(2)}/h` : '';
    card.headline = [{ text: `$${usage.usd.toFixed(2)}${rate}`, dim: true }];
  }
  const ordered = [...WINDOWED.flatMap(kind => usage.limits.filter(limit => limit.kind === kind)), ...usage.limits.filter(limit => !WINDOWED.includes(limit.kind))];
  for (const limit of ordered) {
    if (WINDOWED.includes(limit.kind)) card.rows.push(...windowRows(limit, now, width));
    else card.rows.push([{ text: `${limitLabel(limit.kind)} ${Math.round(limit.percent)}%`, color: rampColor(limit.percent) }]);
  }
  return card;
}

// The repository and the working folder; with no git reading yet, the folder alone.
export function repoCard({ repo, where }) {
  const card = { key: 'repo', title: 'Repo', color: 'green', headline: [], rows: [] };
  const dir = [{ text: `dir  ${shortDir(where.cwd, where.home)}` }];
  if (!repo) {
    card.rows.push(dir);
    return card;
  }
  const isDirty = repo.changed + repo.untracked > 0;
  card.headline = isDirty ? [{ text: '● dirty', color: 'yellow' }] : [{ text: '✓ clean', color: 'green' }];
  card.rows.push([{ text: `repo ${repoName(where.remote, where.root ?? where.cwd)}` }], dir);
  card.rows.push([
    { text: `⎇ ${repo.branch}` },
    ...(repo.ahead ? [{ text: ` ↑${repo.ahead}`, color: 'green' }] : []),
    ...(repo.behind ? [{ text: ` ↓${repo.behind}`, color: 'yellow' }] : []),
  ]);
  const changes = [repo.changed ? `~${repo.changed} changed` : '', repo.untracked ? `?${repo.untracked} untracked` : ''].filter(Boolean);
  card.rows.push(changes.length ? [{ text: changes.join(' '), color: 'yellow' }] : [{ text: 'clean', dim: true }]);
  return card;
}

const DENSE_LABELS = { account: 'acct', plan: 'plan', context: 'ctx', usage: 'lim', checks: 'chk', board: 'board', workers: 'work', repo: 'repo' };
const DENSE_METER = 8;

function denseAccount({ account, remote }) {
  if (!account) return null;
  if (!account.email) return [{ text: `config ${account.key}`, dim: true }];
  const billing = billingLabel(account.billing);
  return [
    { text: account.email },
    ...(billing ? [{ text: ` · ${billing}`, dim: true }] : []),
    { text: ' · Remote ', dim: true },
    remote?.clients?.length ? { text: '●', color: 'green' } : { text: '○', dim: true },
  ];
}

function densePlan({ hud }) {
  const { plan } = hud;
  if (!plan) return [{ text: `No active plan on ${hud.branch ?? 'this checkout'}`, dim: true }];
  const runs = [];
  if (plan.total > 0) runs.push(...meterRuns(plan.done / plan.total, DENSE_METER), { text: ' ' });
  runs.push({ text: `${plan.done}/${plan.total}` });
  if (plan.current) runs.push({ text: ` · Task ${plan.current.number}` });
  if (plan.blocked.length) runs.push({ text: ' · ' }, { text: `${plan.blocked.length} blocked`, color: 'red' });
  return runs;
}

function denseContext({ hud, context }) {
  if (typeof context?.tokens !== 'number') return null;
  const { tokens, window } = context;
  const resetAt = hud.context?.resetAt ?? null;
  const ramp = rampColor(resetAt ? (tokens / resetAt) * 100 : (tokens / window) * 100);
  const marks = resetAt ? [{ at: resetAt / window, glyph: '┃', name: 'reset' }] : [];
  const meter = trackRuns(track(tokens / window, DENSE_METER, marks), ramp, { reset: ramp });
  if (!resetAt) return [...meter, { text: ` ${kTokens(tokens)} of ${kTokens(window)}`, dim: true }];
  return [...meter, { text: ` ${Math.round((tokens / resetAt) * 100)}% of reset`, color: ramp }, { text: ` · ${kTokens(tokens)}`, dim: true }];
}

function denseUsage({ usage, now }) {
  if (!usage || (!usage.limits.length && usage.usd === null)) return null;
  const parts = [];
  for (const kind of WINDOWED) {
    const limit = usage.limits.find(one => one.kind === kind);
    if (!limit) continue;
    const runs = [{ text: `${limitLabel(kind)} ` }, { text: `${Math.round(limit.percent)}%`, color: rampColor(limit.percent) }];
    if (kind === 'five_hour') {
      const forecast = limitForecast(kind, limit.percent, limit.resetsAt, now);
      if (forecast === 'pace') runs.push({ text: ' on pace', color: 'green' });
      else if (typeof forecast === 'number') runs.push({ text: ` out in ${duration(forecast)}`, color: '#ff8700' });
    }
    parts.push(runs);
  }
  if (usage.usd !== null) parts.push([{ text: `$${usage.usd.toFixed(2)}`, dim: true }]);
  return parts.flatMap((runs, index) => (index ? [{ text: ' · ', dim: true }, ...runs] : runs));
}

function denseChecks({ hud }) {
  if (!hud.plan) return null;
  const { gates, review } = hud;
  let gate = [{ text: 'not run', dim: true }];
  if (gates && !gates.ok) gate = [{ text: `✗ ${gates.failed.join(', ')}`, color: 'red' }];
  else if (gates?.ok) gate = [{ text: '✓ passed', color: 'green' }];
  let verdict = [{ text: 'not run', dim: true }];
  if (review?.blocking) verdict = [{ text: `${review.blocking} blocking`, color: 'red' }];
  else if (review?.recorded) verdict = [{ text: `tier ${review.recorded.tier}` }];
  return [{ text: 'gates ' }, ...gate, { text: ' · review ' }, ...verdict];
}

function denseBoard({ hud }) {
  const { board, sync } = hud;
  if (!board && !sync?.enabled) return null;
  const parts = [];
  if (board?.row) parts.push([{ text: `#${board.row.number} ${board.row.state}` }]);
  else if (board) parts.push([{ text: `${Object.values(board.counts).reduce((sum, count) => sum + count, 0)} rows` }]);
  if (sync?.enabled) {
    parts.push(sync.conflict ? [{ text: 'darkmem ✗ conflict: run dflow sync pull', color: 'red' }] : [{ text: `darkmem ${sync.queued ?? 0} queued` }]);
  }
  return parts.flatMap((runs, index) => (index ? [{ text: ' · ', dim: true }, ...runs] : runs));
}

function denseWorkers({ hud }) {
  if (!hud.workers?.length) return null;
  return [{ text: hud.workers.map(worker => `Task ${worker.task}`).join(', '), color: 'magenta' }];
}

function denseRepo({ repo, where }) {
  if (!repo) return where ? [{ text: shortDir(where.cwd, where.home), dim: true }] : null;
  const isDirty = repo.changed + repo.untracked > 0;
  const counts = [repo.ahead ? `↑${repo.ahead}` : '', repo.behind ? `↓${repo.behind}` : '', repo.changed ? `~${repo.changed}` : '', repo.untracked ? `?${repo.untracked}` : ''].filter(Boolean);
  return [{ text: `⎇ ${repo.branch}` }, ...(isDirty ? [{ text: '*', color: 'yellow' }] : []), ...(counts.length ? [{ text: ` ${counts.join(' ')}`, dim: true }] : [])];
}

const DENSE_CONTENT = { account: denseAccount, plan: densePlan, context: denseContext, usage: denseUsage, checks: denseChecks, board: denseBoard, workers: denseWorkers, repo: denseRepo };

// One labelled line per shown card with something to show, then the Next line.
export function denseLines(input, width) {
  const lines = input.shown.flatMap(key => {
    const runs = DENSE_CONTENT[key]?.(input);
    return runs ? [{ key, runs: [{ text: DENSE_LABELS[key].padEnd(6), bold: true }, ...runs] }] : [];
  });
  lines.push({ key: 'next', runs: [{ text: 'next  ', bold: true }, { text: input.hud.next }] });
  return lines.map(line => Object.assign(runsCut(line.runs, width), { key: line.key }));
}
