import fs from 'node:fs';
import path from 'node:path';
import { boardCounts, parseBoard } from './board.mjs';
import { contextSize, formatTokens } from './context.mjs';
import { nextTask, parsePlan, sectionText, taskStates, taskText } from './plan.mjs';
import { currentBranch, head, listPlans, relative } from './repo.mjs';
import { loadState, planState, readEvents } from './state.mjs';
import { capLines, nowIso, readJson, readText, shortSha, writeJson } from './util.mjs';

export function loadPlan(ctx, file) {
  const text = readText(file);
  if (text === null) return null;
  return { file, rel: relative(ctx.root, file), slug: path.basename(file, '.md'), text, plan: parsePlan(text) };
}

export function openPlans(ctx) {
  return listPlans(ctx.paths).map(file => loadPlan(ctx, file)).filter(entry => entry && !entry.plan.fields.shipped);
}

// The plan this checkout is building: the unshipped plan naming this branch,
// else the one last chosen with `dflow plan use`.
export function activePlan(ctx, state = loadState(ctx.paths)) {
  const open = openPlans(ctx);
  const branch = currentBranch(ctx.root);
  const onBranch = open.filter(entry => entry.plan.fields.branch === branch);
  if (onBranch.length === 1) return onBranch[0];
  const chosen = open.find(entry => entry.rel === state.plan);
  if (chosen && (onBranch.length === 0 || onBranch.includes(chosen))) return chosen;
  return onBranch[0] ?? null;
}

export function findingsFile(ctx, slug) {
  return path.join(ctx.paths.stateDir, 'review', slug, 'findings.json');
}

export function loadFindings(ctx, slug) {
  return readJson(findingsFile(ctx, slug), []);
}

export function buildModel(ctx) {
  const state = loadState(ctx.paths);
  const active = activePlan(ctx, state);
  const sha = head(ctx.root);
  const boardText = readText(ctx.paths.board);
  const board = boardText === null ? null : parseBoard(boardText);
  const model = {
    at: nowIso(ctx.env),
    branch: currentBranch(ctx.root),
    head: sha,
    plan: null,
    gates: null,
    review: null,
    board: board && { counts: boardCounts(board), row: null },
    sync: state.sync ?? { enabled: false },
    context: null,
    workers: Object.values(state.workers ?? {}),
    checks: [],
    next: '/dflow:plan — no plan is active on this branch',
  };
  const size = contextSize(ctx, state);
  if (size) model.context = { ...size, resetAt: ctx.config.context.resetAt };
  if (!active) return model;

  const record = planState(state, active.slug);
  const tasks = taskStates(active.plan, record);
  const upcoming = nextTask(tasks);
  const done = tasks.filter(task => task.done).length;
  const findings = loadFindings(ctx, active.slug);
  const open = findings.filter(finding => finding.status === 'open');
  model.plan = {
    file: active.rel,
    slug: active.slug,
    title: active.plan.title,
    approved: active.plan.fields.approved ?? null,
    total: tasks.length,
    done,
    blocked: tasks.filter(task => task.state === 'blocked').map(task => ({ number: task.number, reason: task.blockedReason })),
    current: upcoming && { number: upcoming.number, title: upcoming.title, state: upcoming.state, attempts: upcoming.attempts },
    tasks: tasks.map(task => ({ number: task.number, title: task.title, state: task.state, run: task.run })),
    allDone: tasks.length > 0 && done === tasks.length,
  };
  if (record.gates) model.gates = { ok: record.gates.ok, sha: record.gates.sha, stale: record.gates.sha !== sha || Boolean(record.gates.dirty), failed: record.gates.results.filter(result => !result.ok).map(result => result.name) };
  model.review = {
    recorded: record.review ?? null,
    open: open.length,
    blocking: open.filter(finding => finding.severity === 'blocking').length,
  };
  if (board) {
    const row = board.rows.find(candidate => String(candidate.number) === String(active.plan.fields.board));
    if (row) model.board.row = { number: row.number, state: row.state };
  }

  if (fs.existsSync(ctx.paths.events)) {
    const committed = new Set(readEvents(ctx.paths).filter(event => event.plan === active.slug && event.event === 'done').map(event => event.task));
    for (const task of tasks) {
      if (task.done && !committed.has(task.number)) model.checks.push(`Task ${task.number} is ticked without a recorded \`dflow done\``);
    }
  }
  model.next = recommend(model, ctx);
  return model;
}

function recommend(model, ctx) {
  const { plan } = model;
  if (!plan.approved) return `dflow plan approve — ${plan.file} is not approved yet`;
  if (!plan.allDone) {
    if (plan.current) return `/dflow:build — Task ${plan.current.number}: ${plan.current.title}`;
    return `every remaining task is blocked or waits on a blocked task; resolve: ${plan.blocked.map(task => `Task ${task.number}`).join(', ')}`;
  }
  if (model.review.blocking) return `fix ${model.review.blocking} blocking finding(s), then dflow review verify`;
  if (!model.review.recorded) return '/dflow:review — every task is done';
  if (ctx.config.gates.length && (!model.gates || !model.gates.ok || model.gates.stale)) return '/dflow:ship — it runs the gates, which have not passed on this commit';
  return '/dflow:ship';
}

export function statusLines(model) {
  const lines = [];
  const { plan } = model;
  if (!plan) {
    lines.push(`dflow · no active plan on ${model.branch ?? 'a detached head'}`);
  } else {
    lines.push(`dflow · ${plan.title} · ${model.branch}`);
    const current = plan.current ? ` · Task ${plan.current.number} ${plan.current.state}${plan.current.attempts ? ` (verify failed ${plan.current.attempts}×)` : ''}` : '';
    const blocked = plan.blocked.length ? ` · ${plan.blocked.length} blocked` : '';
    lines.push(`Plan    ${plan.done}/${plan.total} done${current}${blocked} · ${plan.file}`);
    for (const task of plan.blocked) lines.push(`Blocked Task ${task.number}: ${task.reason}`);
    if (model.gates) lines.push(`Gates   ${model.gates.ok ? 'passed' : `failed (${model.gates.failed.join(', ')})`} at ${shortSha(model.gates.sha)}${model.gates.stale ? ' · stale, the head moved' : ''}`);
    else lines.push('Gates   not run');
    const review = model.review.recorded ? `tier ${model.review.recorded.tier} at ${shortSha(model.review.recorded.sha)}` : 'not run';
    lines.push(`Review  ${review}${model.review.open ? ` · ${model.review.open} open, ${model.review.blocking} blocking` : ''}`);
  }
  if (model.board) {
    const counts = Object.entries(model.board.counts).map(([state, count]) => `${count} ${state}`).join(' · ') || 'empty';
    lines.push(`Board   ${model.board.row ? `#${model.board.row.number} ${model.board.row.state} · ` : ''}${counts}`);
  }
  if (model.context) lines.push(`Context ${formatTokens(model.context.tokens)}${model.context.window ? ` of ${formatTokens(model.context.window)}` : ''} · resets at ${formatTokens(model.context.resetAt)}`);
  if (model.sync.enabled) lines.push(`darkmem ${model.sync.conflict ? `conflict: ${model.sync.conflict}` : `${model.sync.queued ?? 0} queued${model.sync.lastAt ? ` · last push ${model.sync.lastAt}` : ''}`}`);
  for (const check of model.checks) lines.push(`Check   ${check}`);
  lines.push(`Next    ${model.next}`);
  return lines;
}

export function briefLines(model) {
  if (!model.plan) return [];
  const { plan } = model;
  return [
    `dflow: plan "${plan.title}" (${plan.file}) is ${plan.done}/${plan.total} done on ${model.branch}.`,
    `Next: ${model.next}`,
  ];
}

export function taskBrief(ctx, active, task, { designLimit = 40 } = {}) {
  const { plan } = active;
  const lines = [
    `Plan: ${plan.title} (${active.rel})`,
    `Goal: ${plan.fields.goal ?? ''}`,
  ];
  const design = designLimit > 0 ? sectionText(plan, 'design', designLimit) : [];
  if (design.length) lines.push('', '## Design', ...design);
  lines.push('', ...taskText(plan, task));
  const notes = plan.log.filter(entry => entry.task === task.number);
  if (notes.length) lines.push('', 'Log for this task:', ...notes.map(entry => `- ${entry.date} ${entry.kind}: ${entry.text}`));
  return capLines(lines, 90, more => `… ${more} more lines; read ${active.rel}`);
}

export function refreshHud(ctx) {
  // Only a repository that uses dflow gets a .dflow directory.
  if (!fs.existsSync(ctx.paths.docs)) return;
  try {
    writeJson(ctx.paths.hud, buildModel(ctx));
  } catch {
    // The HUD is a view; a failure to refresh it must not fail the command.
  }
}
