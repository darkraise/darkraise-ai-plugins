// Pure text for the HUD, shared by the mod and the Node tests. No engine
// access here: the hooks module passes plain values in.

import { bar as meterBar } from './meter.mjs';

export const MODES = ['band', 'pane', 'off'];
export const RESET_FRESH_MS = 10 * 60 * 1000;
export const RESET_INSTRUCTIONS = 'A dflow build is in progress; the plan file and the git history hold all task state. Keep only: the plan path, the task in progress with what is finished and what is left inside it, why any uncommitted change was made, decisions not yet recorded with `dflow log`, and instructions the owner gave. Leave out tool output, file contents and finished tasks.';

export function nextMode(current, argument) {
  if (!argument) return MODES[(MODES.indexOf(current) + 1) % MODES.length];
  return MODES.includes(argument) ? argument : null;
}

export function tokens(count) {
  if (count >= 1000000) return `${(count / 1000000).toFixed(count % 1000000 ? 1 : 0)}M`;
  return count >= 1000 ? `${Math.round(count / 1000)}k` : String(count);
}

export function bar(done, total, width) {
  const filled = total ? Math.round((done / total) * width) : 0;
  return `${'█'.repeat(filled)}${'░'.repeat(width - filled)}`;
}

function fit(text, columns) {
  return text.length <= columns ? text : `${text.slice(0, Math.max(0, columns - 1))}…`;
}

function taskText(current) {
  if (!current) return 'no task ready';
  return `Task ${current.number} ${current.state}${current.attempts ? ` · verify failed ${current.attempts}×` : ''}`;
}

export function bandText(hud, context, columns) {
  const { plan } = hud;
  const parts = [`dflow ▸ ${plan.title}`, `${bar(plan.done, plan.total, 8)} ${plan.done}/${plan.total}`, taskText(plan.current)];
  if (plan.blocked.length) parts.push(`${plan.blocked.length} blocked`);
  if (context && typeof context.tokens === 'number') parts.push(`ctx ${tokens(context.tokens)}${hud.context?.resetAt ? `/${tokens(hud.context.resetAt)}` : ''}`);
  return fit(parts.join(' · '), columns);
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
