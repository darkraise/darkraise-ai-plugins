import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { git } from './sh.mjs';
import { candidate, planAt, slug } from './cases.mjs';
import { commitMessages, taskText, tasks } from './plan.mjs';

export const PIPELINE_CASES = 12;

// finishedPlans TEXT — { plan, merge } for each line of completed.md that names
// a plan and the commit that merged it.
export function finishedPlans(text) {
  return text.split('\n').flatMap(line => {
    const m = line.match(/`(docs\/dforge\/plans\/[^`]+\.md)` — merged into `[^`]+` at ([0-9a-f]{7,40})\b/);
    return m ? [{ plan: m[1], merge: m[2] }] : [];
  });
}

// fixRounds { result, merge, allowed, own } — the review-fix commits of one
// task: the commits after its RESULT commit, up to the next commit that
// carries a task of the plan (OWN is the set of their subjects), that touch a
// path of the task's Files block ALLOWED. A plan's last task has none: what
// follows it is the final review's fixes. This approximates the fix rounds the
// ledger counted, which survive only on the machine that ran the plan.
export function fixRounds({ result, merge, allowed, own }) {
  const log = git(['log', '--reverse', '--no-merges', '--ancestry-path', '--format=@@%H%x09%s', '--name-only', `${result}..${merge}`])
    .split('@@').filter(Boolean).map(block => {
      const [head, ...files] = block.split('\n').filter(Boolean);
      return { subject: head.slice(head.indexOf('\t') + 1), files };
    });
  const next = log.findIndex(entry => own.has(entry.subject));
  if (next < 0) return 0;
  return log.slice(0, next).filter(entry => entry.files.some(file => allowed.includes(file))).length;
}

// pipelineCandidates START DONE — every task of the finished plans DONE that
// the case builder accepts, as { plan, task, title, base, result, allowed,
// tests, fixRounds }.
export function pipelineCandidates(start, done) {
  const subjects = new Map();
  for (const line of git(['log', '--format=%H%x09%s', start]).split('\n').filter(Boolean)) {
    const [sha, subject] = line.split('\t');
    subjects.set(subject, [...(subjects.get(subject) ?? []), sha]);
  }
  const tmp = mkdtempSync(join(tmpdir(), 'tier-eval-pipeline-'));
  const out = [];
  try {
    for (const { plan, merge } of done) {
      const head = planAt(start, plan, join(tmp, 'head'));
      if (head === null) continue;
      const list = tasks(head);
      const own = new Set(list.flatMap(({ n }) => commitMessages(taskText(head, n) ?? '')));
      for (const { n, title } of list) {
        const c = candidate(plan, n, taskText(head, n), subjects, join(tmp, 'work'));
        if (c.reason) continue;
        out.push({ plan, task: n, title, ...c, fixRounds: fixRounds({ result: c.result, merge, allowed: c.allowed, own }) });
      }
    }
  } finally {
    rmSync(tmp, { recursive: true, force: true });
  }
  return out;
}

// pickCases LIST TOTAL — TOTAL cases: first those that needed fix rounds, most
// rounds first, then the rest round-robin across plans in plan order.
export function pickCases(list, total = PIPELINE_CASES) {
  const byTask = (a, b) => a.plan.localeCompare(b.plan) || a.task - b.task;
  const picked = list.filter(c => c.fixRounds > 0).sort((a, b) => b.fixRounds - a.fixRounds || byTask(a, b)).slice(0, total);
  const byPlan = new Map();
  for (const c of list.filter(c => !picked.includes(c)).sort(byTask)) byPlan.set(c.plan, [...(byPlan.get(c.plan) ?? []), c]);
  while (picked.length < total && [...byPlan.values()].some(rest => rest.length > 0)) {
    for (const rest of byPlan.values()) {
      if (rest.length > 0 && picked.length < total) picked.push(rest.shift());
    }
  }
  return picked.sort(byTask);
}

export const caseId = c => `p-${slug(c.plan)}-t${c.task}`;

export function manifestText(cases) {
  const rows = cases.map(c => [caseId(c), c.plan, c.task, c.base, c.fixRounds].join('\t'));
  return ['case\tplan\ttask\tbase\tfixRounds', ...rows].join('\n') + '\n';
}
