// Pure text for the HUD, shared by the mod and the Node tests. No engine
// access here: the hooks module passes plain values in.

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

function contextText(context, resetAt) {
  if (!context || typeof context.tokens !== 'number') return null;
  return `${tokens(context.tokens)}${context.window ? ` of ${tokens(context.window)}` : ''}${resetAt ? ` · resets at ${tokens(resetAt)}` : ''}`;
}

export function bandText(hud, context, columns) {
  const { plan } = hud;
  const parts = [`dflow ▸ ${plan.title}`, `${bar(plan.done, plan.total, 8)} ${plan.done}/${plan.total}`, taskText(plan.current)];
  if (plan.blocked.length) parts.push(`${plan.blocked.length} blocked`);
  if (context && typeof context.tokens === 'number') parts.push(`ctx ${tokens(context.tokens)}${hud.context?.resetAt ? `/${tokens(hud.context.resetAt)}` : ''}`);
  return fit(parts.join(' · '), columns);
}

// Rows of the pane as [label, text, isDim]; the mod maps them to elements.
export function paneRows(hud, context, columns) {
  const width = Math.max(20, columns - 9);
  if (!hud.plan) return [['', fit(`No active plan on ${hud.branch ?? 'this checkout'}.`, columns), true], ['Next', fit(hud.next, width), false]];
  const { plan } = hud;
  const rows = [
    ['', fit(`${plan.title} · ${hud.branch}`, columns), false],
    ['Plan', fit(`${bar(plan.done, plan.total, 14)} ${plan.done}/${plan.total} · ${taskText(plan.current)}`, width), false],
  ];
  if (plan.current) rows.push(['Task', fit(plan.current.title, width), true]);
  for (const task of plan.blocked) rows.push(['Blocked', fit(`Task ${task.number}: ${task.reason}`, width), false]);
  const text = contextText(context, hud.context?.resetAt);
  if (text) rows.push(['Context', fit(text, width), true]);
  rows.push(['Gates', !hud.gates ? 'not run' : hud.gates.ok ? `passed${hud.gates.stale ? ' · stale' : ''}` : `failed: ${hud.gates.failed.join(', ')}`, !hud.gates?.failed?.length]);
  const review = hud.review?.recorded ? `tier ${hud.review.recorded.tier} recorded` : 'not run';
  rows.push(['Review', fit(`${review}${hud.review?.open ? ` · ${hud.review.open} open, ${hud.review.blocking} blocking` : ''}`, width), !hud.review?.blocking]);
  if (hud.board) {
    const counts = Object.entries(hud.board.counts).map(([state, count]) => `${count} ${state}`).join(' · ');
    rows.push(['Board', fit(`${hud.board.row ? `#${hud.board.row.number} ${hud.board.row.state} · ` : ''}${counts}`, width), true]);
  }
  if (hud.sync?.enabled) rows.push(['darkmem', fit(syncText(hud.sync), width), !hud.sync.conflict && !hud.sync.error && !hud.sync.refused]);
  if (hud.workers?.length) rows.push(['Workers', fit(hud.workers.map(worker => `T${worker.task}`).join(', '), width), true]);
  rows.push(['Next', fit(hud.next, width), false]);
  return rows;
}

// A server that cannot be reached and one that answered with a refusal need
// different things from the owner, so they read differently.
function syncText(sync) {
  if (sync.conflict) return 'conflict: run dflow sync pull';
  const queued = `${sync.queued ?? 0} queued`;
  if (sync.error) return sync.offline ? `offline · ${queued}` : `refused: run dflow sync push · ${queued}`;
  return sync.refused ? `${sync.refused} refused: run dflow sync push · ${queued}` : queued;
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
