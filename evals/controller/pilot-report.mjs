// node evals/controller/pilot-report.mjs
// Measures every plan pilot.tsv lists and prints one row per plan, then the
// Stage 1 decision over the rows whose status is ok. Reads only; calls no model.
import { existsSync, readFileSync } from 'node:fs';
import { basename, isAbsolute, join, resolve } from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { readTsv } from '../tiers/lib/results.mjs';
import { BASE, CANDIDATE, stage1 } from './lib/decide.mjs';
import { REPOS, flatten, measureSessions, planSessions, planSlugs } from './lib/sessions.mjs';

const HERE = fileURLToPath(new URL('.', import.meta.url));
const DATA = process.env.CONTROLLER_EVAL_DATA ?? HERE;
const COLUMNS = ['plan', 'arm', 'status', 'complete', 'sessions', 'shared', 'models', 'efforts', 'controllerCost', 'subagentCost', 'dispatches', 'calls', 'costPerDispatch', 'nudges', 'inFlight', 'seatMisses', 'sleeps', 'listAgents', 'monitors', 'unpriced'];

// planTasks TEXT — the task numbers of a plan's `### Task N` headings,
// skipping fenced code, where a plan may quote another plan.
function planTasks(text) {
  const tasks = new Set();
  let fence = null;
  for (const line of text.split('\n')) {
    const marker = line.match(/^ {0,3}(`{3,}|~{3,})(.*)$/);
    if (fence === null) {
      if (marker) fence = marker[1];
      else if (/^### Task (\d+)/.test(line)) tasks.add(line.match(/^### Task (\d+)/)[1]);
    } else if (marker && marker[1][0] === fence[0] && marker[1].length >= fence.length && marker[2].trim() === '') fence = null;
  }
  return [...tasks];
}

// complete REPO PLAN DONE — yes when every task of PLAN, as committed at
// REPO's HEAD (or read from disk when PLAN is an absolute path, as a plan kept
// outside the checkout is), has a complete line among DONE; unknown when the
// plan cannot be read or has no task.
function complete(repo, plan, done) {
  let text = null;
  if (isAbsolute(plan)) {
    if (existsSync(plan)) text = readFileSync(plan, 'utf8');
  } else {
    const shown = spawnSync('git', ['-C', repo, 'show', `HEAD:${plan}`], { encoding: 'utf8' });
    if (shown.status === 0) text = shown.stdout;
  }
  const tasks = text === null ? [] : planTasks(text);
  if (tasks.length === 0) return 'unknown';
  return tasks.every(n => done.includes(n)) ? 'yes' : 'no';
}

// The arm's model and effort must be the only ones its controller sessions
// ran on; a resume on another launch line would mix the arms.
function onArm(arm, controller) {
  const [family, effort] = arm.split('@');
  return controller.models.length > 0 && controller.models.every(m => m.startsWith(`claude-${family}-5-5`))
    && controller.efforts.length === 1 && controller.efforts[0] === effort;
}

const rows = [];
for (const entry of readTsv(join(DATA, 'pilot.tsv'))) {
  if (entry.arm !== BASE && entry.arm !== CANDIDATE) {
    console.error(`pilot-report: ${entry.plan}: arm must be ${BASE} or ${CANDIDATE}, not ${entry.arm}`);
    process.exit(2);
  }
  const slug = basename(entry.plan, '.md');
  const repo = isAbsolute(entry.repo) ? entry.repo : resolve(REPOS, entry.repo);
  const files = planSessions(slug, repo);
  const measured = measureSessions(files);
  const row = { plan: slug, arm: entry.arm, complete: complete(repo, entry.plan, measured.controller.completed), shared: files.filter(f => planSlugs(f).length > 1).length, ...flatten(measured) };
  if (row.sessions === 0) row.status = 'no-sessions';
  else if (row.shared > 0) row.status = 'shared';
  else if (!onArm(entry.arm, measured.controller)) row.status = 'mismatch';
  else if (row.unpriced !== '') row.status = 'unpriced';
  else if (row.complete === 'unknown') row.status = 'no-plan';
  else row.status = 'ok';
  rows.push(row);
}
console.log(COLUMNS.join('\t'));
for (const row of rows) console.log(COLUMNS.map(k => row[k]).join('\t'));
const usable = rows.filter(row => row.status === 'ok');
const r = stage1(usable);
console.log(`stage1: ${r.decision} — ${usable.length} of ${rows.length} plans usable; ${CANDIDATE} costs ${r.ratio.toFixed(2)}x ${BASE} per dispatch; failures ${BASE} ${r.failures[BASE]}, ${CANDIDATE} ${r.failures[CANDIDATE]}`);
