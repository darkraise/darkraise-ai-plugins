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
export const SLICE_CAP = 5;
export const SLICES = resolve(DATA, 'cases/slices.tsv');

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

export function candidate(plan, task, headText, subjects, tmp) {
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
  const drop = c.tasks ? ['docs/superpowers'] : [];
  try {
    let text;
    try { text = c.tasks ? sliceBrief(c, join(tmp, 'brief')) : brief(c, join(tmp, 'brief')); } catch { return 'the brief does not build'; }
    if (c.tasks && strip(text, addedLines(c.base, c.result)).removed === 0) return 'stripping removes no code';
    snapshot(c.result, join(tmp, 'result'), drop);
    const good = await runTests(join(tmp, 'result'), c.tests);
    if (!good.pass) return `${good.failed} fails on the result commit`;
    snapshot(c.base, join(tmp, 'base'), drop);
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
  return basename(plan, '.md').replace(/^\d{4}-\d{2}-\d{2}-/, '').replace(/^(?:dr-(?:superpowers|forge)|dforge)-/, '');
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

// scoreSlice MEMBERS — MEMBERS are candidate rows in task order. The merged
// task is { axes, allowed, tests } scored with spec 2, as stripping raises it,
// or { reason } for the first rule it breaks.
export function scoreSlice(members) {
  const bad = members.find(m => m.axes.spec === 3);
  if (bad) return { reason: `Task ${bad.task} scores spec 3` };
  const merged = key => [...new Set(members.flatMap(m => m[key]))];
  const allowed = merged('allowed'), tests = merged('tests');
  const files = allowed.length === 1 ? 0 : allowed.length <= 3 ? 1 : allowed.length <= 6 ? 2 : 3;
  const coupling = Math.max(...members.map(m => m.axes.coupling));
  const risk = Math.max(...members.map(m => m.axes.risk));
  if (files + 2 + coupling >= 6) return { reason: `Rule S: files ${files} + spec 2 + coupling ${coupling} = ${files + 2 + coupling}` };
  const total = files + 2 + coupling + risk;
  if (total < 5) return { reason: `total ${total}: §1 assigns no slice arm` };
  return { axes: { files, spec: 2, coupling, risk, total }, allowed, tests };
}

// slices ALL — ALL is candidates(start). Every run of two or three consecutive
// eligible tasks of one plan is a window { plan, tasks, task, base, result }
// with either { reason } or the merged { axes, allowed, tests }.
export function slices(all) {
  const out = [];
  for (const plan of [...new Set(all.map(c => c.plan))]) {
    const own = all.filter(c => c.plan === plan);
    for (const first of own) {
      if (first.reason) continue;
      for (const size of [3, 2]) {
        const members = Array.from({ length: size }, (_, i) => own.find(c => c.task === first.task + i));
        if (members.some(m => !m || m.reason)) continue;
        const window = { plan, tasks: members.map(m => m.task), task: first.task, base: members[0].base, result: members.at(-1).result };
        const inOrder = members.every((m, i) => i === 0 || sh('git', ['merge-base', '--is-ancestor', members[i - 1].result, m.base]).code === 0);
        out.push({ ...window, ...(inOrder ? scoreSlice(members) : { reason: 'the tasks were not committed in task order' }) });
      }
    }
  }
  return out;
}

export const sliceId = w => `l-${slug(w.plan)}-t${w.tasks[0]}-${w.tasks.at(-1)}`;

// orderSlices WINDOWS — round-robin across plans in plan order and, inside a
// plan, by first task and then larger windows first, without a cap.
export function orderSlices(windows) {
  const byPlan = new Map();
  for (const w of [...windows].sort((a, b) => a.plan.localeCompare(b.plan) || a.tasks[0] - b.tasks[0] || b.tasks.length - a.tasks.length)) {
    byPlan.set(w.plan, [...(byPlan.get(w.plan) ?? []), w]);
  }
  const ordered = [];
  while ([...byPlan.values()].some(list => list.length > 0)) {
    for (const list of byPlan.values()) if (list.length > 0) ordered.push(list.shift());
  }
  return ordered;
}

// pickSlices ORDERED CHECK [CAP] — walks ORDERED and picks the windows CHECK
// accepts (null) until CAP are picked; a window sharing a task with a picked
// one of its plan is excluded unchecked. Returns { picked, excluded }.
export async function pickSlices(ordered, check, cap = SLICE_CAP) {
  const picked = [], excluded = [];
  for (const w of ordered) {
    if (picked.length >= cap) { excluded.push({ ...w, reason: `not selected: ${cap} slices already picked` }); continue; }
    if (picked.some(p => p.plan === w.plan && p.tasks.some(n => w.tasks.includes(n)))) { excluded.push({ ...w, reason: 'overlaps a picked slice' }); continue; }
    const reason = await check(w);
    if (reason === null) picked.push(w); else excluded.push({ ...w, reason });
  }
  return { picked, excluded };
}

// sliceBrief CASE DIR — the brief of a slice case: each task's brief as a
// numbered part, with the first task's plan header excerpt once at the end.
export function sliceBrief(c, dir) {
  const plan = planAt(c.base, c.plan, dir);
  if (plan === null) throw new Error(`${c.plan} is missing at ${c.base}`);
  const titles = tasks(plan);
  const parts = [], names = [];
  let excerpt = '';
  c.tasks.forEach((n, i) => {
    const title = titles.find(t => t.n === n).title;
    const text = taskBrief(plan, n, join(dir, `t${n}`));
    const cut = text.indexOf('\n## Plan header excerpt\n');
    const body = (cut < 0 ? text : text.slice(0, cut)).split('\n').filter(l => !/^\*\*(Implementer|Evaluation|Override):\*\*/.test(l));
    if (i === 0 && cut >= 0) excerpt = text.slice(cut + 1).trim();
    parts.push([`## Part ${i + 1} (Task ${n}): ${title}`, ...body.slice(1)].join('\n').trim());
    names.push(title);
  });
  return [`# Tasks ${c.tasks[0]}-${c.tasks.at(-1)}: ${names.join('; ')}`, `One task made of ${c.tasks.length} parts: implement every part, in order, as a single change.`, ...parts, ...(excerpt ? [excerpt] : [])].join('\n\n') + '\n';
}

export function readManifest(file = MANIFEST) {
  const lines = readFileSync(file, 'utf8').split('\n').filter(Boolean);
  const start = lines[0].match(/^# start ([0-9a-f]{40})$/)?.[1];
  if (!start) throw new Error(`${file}: the first line must be "# start <commit>"`);
  const keys = lines[1].split('\t');
  const cases = lines.slice(2).map(line => Object.fromEntries(line.split('\t').map((v, i) => [keys[i], v])));
  return { start, cases: cases.map(c => ({ ...c, row: Number(c.row), task: Number(c.task), ...(c.tasks === undefined ? {} : { tasks: c.tasks.split(',').map(Number) }) })) };
}
