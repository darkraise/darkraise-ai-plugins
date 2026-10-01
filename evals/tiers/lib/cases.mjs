import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { basename, join, resolve } from 'node:path';
import { DATA, git, sh } from './sh.mjs';
import { tasks, taskText, evaluation, commitMessages, filesBlock, taskBrief } from './plan.mjs';
import { snapshot } from './snapshot.mjs';
import { overlayTests, runTests } from './grade.mjs';
import { addedLines, strip } from './strip.mjs';

const PLAN_DIR = 'docs/superpowers/plans';
const FIRST_PLAN_DATE = '2026-09-11';
const LAST_PLAN_DATE = '2026-09-30';
const RUNNABLE = /\.test\.(sh|mjs)$/;
export const CAP = 8;
export const MANIFEST = resolve(DATA, 'cases/manifest.tsv');

// plans START — the dated plan files at START from FIRST_PLAN_DATE, the day
// dr-superpowers became the plugin these plans build, to LAST_PLAN_DATE, the
// last plan written before this eval: its own plan is not one of its cases.
export function plans(start) {
  return git(['ls-tree', '--name-only', `${start}:${PLAN_DIR}`]).split('\n')
    .filter(name => /^\d{4}-\d{2}-\d{2}-.+\.md$/.test(name) && name.slice(0, 10) >= FIRST_PLAN_DATE && name.slice(0, 10) <= LAST_PLAN_DATE)
    .sort().map(name => `${PLAN_DIR}/${name}`);
}

// planAt COMMIT PLAN DIR — PLAN as it stood at COMMIT, written into DIR, or
// null when COMMIT has no such file.
export function planAt(commit, plan, dir) {
  const shown = sh('git', ['show', `${commit}:${plan}`]);
  if (shown.code !== 0) return null;
  mkdirSync(dir, { recursive: true });
  const file = join(dir, 'plan.md');
  writeFileSync(file, shown.out);
  return file;
}

// candidates START — every task of every plan as { plan, task, title } plus
// either { reason } when it is ineligible or the fields a case needs. The
// task is found in the plan at START and then read as it stood at its base
// commit, which is the text its implementer saw.
export function candidates(start) {
  const subjects = new Map();
  for (const line of git(['log', '--format=%H%x09%s', start]).split('\n').filter(Boolean)) {
    const [sha, subject] = line.split('\t');
    subjects.set(subject, [...(subjects.get(subject) ?? []), sha]);
  }
  const tmp = mkdtempSync(join(tmpdir(), 'tier-eval-plan-'));
  const out = [];
  try {
    for (const plan of plans(start)) {
      const head = planAt(start, plan, tmp);
      for (const { n, title } of tasks(head)) {
        out.push({ plan, task: n, title, ...candidate(plan, n, taskText(head, n), subjects, tmp) });
      }
    }
  } finally {
    rmSync(tmp, { recursive: true, force: true });
  }
  return out;
}

function candidate(plan, task, headText, subjects, tmp) {
  const messages = commitMessages(headText);
  if (messages.length !== 1) return { reason: `${messages.length} commit messages in the task` };
  const shas = subjects.get(messages[0]) ?? [];
  if (shas.length !== 1) return { reason: `${shas.length} commits match the commit message` };
  const result = shas[0];
  const base = git(['rev-parse', `${result}^`]).trim();
  const at = planAt(base, plan, tmp);
  if (at === null) return { reason: 'no plan at the base commit' };
  const text = taskText(at, task);
  if (text === null) return { reason: 'no such task at the base commit' };
  const axes = evaluation(text);
  if (!axes) return { reason: 'not exactly one Evaluation line' };
  const { allowed, tests } = filesBlock(text);
  if (tests.length === 0) return { reason: 'no test file in the Files block' };
  if (!tests.every(t => RUNNABLE.test(t))) return { reason: 'a Test file has no runner' };
  return { base, result, axes, allowed, tests };
}

// golden CASE — null when the brief builds, the grader passes on the result
// commit and it fails on the base commit; else the reason the case is unusable.
export async function golden(c) {
  const touched = git(['diff', '--name-only', c.base, c.result]).split('\n').filter(Boolean);
  const outside = touched.filter(p => !c.allowed.includes(p));
  if (outside.length > 0) return `the result commit changes ${outside[0]}, outside the Files block`;
  const tmp = mkdtempSync(join(tmpdir(), 'tier-eval-golden-'));
  try {
    try { brief(c, join(tmp, 'brief')); } catch { return 'the brief does not build'; }
    snapshot(c.result, join(tmp, 'result'));
    const good = await runTests(join(tmp, 'result'), c.tests);
    if (!good.pass) return `${good.failed} fails on the result commit`;
    snapshot(c.base, join(tmp, 'base'));
    if (!overlayTests(join(tmp, 'base'), c.result, c.tests)) return 'a test file is missing at the result commit';
    const bad = await runTests(join(tmp, 'base'), c.tests);
    return bad.pass ? 'the tests already pass on the base commit' : null;
  } finally {
    rmSync(tmp, { recursive: true, force: true });
  }
}

// brief CASE DIR — the as-written brief of CASE, built from the plan at its
// base commit.
export function brief(c, dir) {
  const plan = planAt(c.base, c.plan, dir);
  if (plan === null) throw new Error(`${c.plan} is missing at ${c.base}`);
  return taskBrief(plan, c.task, dir);
}

// strippedRow CASE — the row a stripped CASE files under, or null when
// stripping it would break Rule S or removes nothing. Stripping raises spec
// completeness to 2, so the total is files + 2 + coupling + risk.
export function strippedRow(c) {
  const { files, spec, coupling, risk } = c.axes;
  if (spec > 1 || files + coupling > 1) return null;
  const tmp = mkdtempSync(join(tmpdir(), 'tier-eval-strip-'));
  try {
    return strip(brief(c, tmp), addedLines(c.base, c.result)).removed > 0 ? files + 2 + coupling + risk : null;
  } finally {
    rmSync(tmp, { recursive: true, force: true });
  }
}

export function slug(plan) {
  return basename(plan, '.md').replace(/^\d{4}-\d{2}-\d{2}-/, '').replace(/^dr-superpowers-/, '');
}

// select CASES — at most CAP of CASES, taken round-robin across plans in plan
// order and, inside a plan, in task order.
export function select(cases) {
  const byPlan = new Map();
  for (const c of [...cases].sort((a, b) => a.plan.localeCompare(b.plan) || a.task - b.task)) {
    byPlan.set(c.plan, [...(byPlan.get(c.plan) ?? []), c]);
  }
  const picked = [];
  while (picked.length < CAP && [...byPlan.values()].some(list => list.length > 0)) {
    for (const list of byPlan.values()) {
      if (list.length > 0 && picked.length < CAP) picked.push(list.shift());
    }
  }
  return picked;
}

export function readManifest(file = MANIFEST) {
  const lines = readFileSync(file, 'utf8').split('\n').filter(Boolean);
  const start = lines[0].match(/^# start ([0-9a-f]{40})$/)?.[1];
  if (!start) throw new Error(`${file}: the first line must be "# start <commit>"`);
  const keys = lines[1].split('\t');
  const cases = lines.slice(2).map(line => Object.fromEntries(line.split('\t').map((v, i) => [keys[i], v])));
  return { start, cases: cases.map(c => ({ ...c, row: Number(c.row), task: Number(c.task) })) };
}
