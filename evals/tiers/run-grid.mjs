#!/usr/bin/env node
// Run every cell of one stage that has no scored result yet, two at a time.
// Usage: node evals/tiers/run-grid.mjs --stage smoke|written|stripped|review [--rep N] [--minutes M] [--pass P]
// --minutes stops starting cells after M minutes, so a long stage can run in
// slices; cells already running finish. --pass numbers the grading passes P
// and P + 1 (default 1 and 2), so every review can be graded again after a
// grader fix without touching the earlier grades.
// Exit: 0 the stage is complete; 1 cells remain after harness errors; 2 usage,
// or the plugin differs from the manifest's start commit; 3 stopped at the
// spend cap, at a rate limit or at --minutes.
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { parseArgs } from 'node:util';
import { reviewCases } from './build-case.mjs';
import { gradeReview } from './grade-review.mjs';
import { runCell } from './run-case.mjs';
import { readManifest } from './lib/cases.mjs';
import { RESULTS, RESULT_COLUMNS, appendTsv, readTsv, scored } from './lib/results.mjs';
import { DATA, sh } from './lib/sh.mjs';

// The two limits of the spec; the tests lower them through the environment.
const JOBS = Number(process.env.TIER_EVAL_JOBS ?? 2);
const CAP_USD = Number(process.env.TIER_EVAL_CAP_USD ?? 250);
const REPEAT_GRADINGS = 6;
const STAGES = ['smoke', 'written', 'stripped', 'review'];

const { values } = parseArgs({ options: { stage: { type: 'string' }, rep: { type: 'string', default: '1' }, minutes: { type: 'string' }, pass: { type: 'string', default: '1' } } });
const { stage, rep } = values;
const deadline = values.minutes === undefined ? Infinity : Date.now() + Number(values.minutes) * 60000;
const pass = Number(values.pass);
if (!STAGES.includes(stage) || Number.isNaN(deadline) || !Number.isInteger(pass) || pass < 1) { console.error(`usage: run-grid.mjs --stage ${STAGES.join('|')} [--rep N] [--minutes M] [--pass P]`); process.exit(2); }
const { start, cases } = readManifest();
if (sh('git', ['diff', '--quiet', start, '--', 'plugins/dr-superpowers']).code !== 0) {
  console.error(`run-grid: plugins/dr-superpowers differs from the manifest's start commit ${start}`);
  process.exit(2);
}
const arms = JSON.parse(readFileSync(resolve(DATA, 'arms.json'), 'utf8'));
const reviews = reviewCases();

function cells() {
  if (stage === 'review') return reviews.flatMap(c => arms.review.map(arm => ({ c, arm })));
  if (stage !== 'smoke') return cases.filter(c => c.pool === stage).flatMap(c => arms.rows[c.row].map(arm => ({ c, arm })));
  const first = row => cases.find(c => c.pool === 'written' && c.row === row);
  return [
    { c: first(1), arm: 'impl-haiku' },
    { c: first(3), arm: 'impl-sonnet-medium' },
    { c: first(5), arm: 'impl-opus-low' },
    { c: reviews[0], arm: 'judge-sonnet-high' },
    { c: reviews[0], arm: 'judge-opus@medium' },
  ].filter(cell => cell.c);
}

// excluded — the cases a person took out of this repetition with
// `run-case.mjs --exclude`: one EXCLUDED row removes the case for every arm.
const excluded = () => new Set(readTsv(RESULTS).filter(r => r.rep === rep && r.outcome === 'EXCLUDED').map(r => r.case));

// gradings — the first pass for every settled review cell of this repetition
// (one only in the smoke stage), then a repeat pass on the first
// REPEAT_GRADINGS reviews. A BLOCKED cell wrote no review; gradeReview grades
// it as missing every defect, so each arm ends with a grade per defect.
function gradings() {
  if (stage !== 'smoke' && stage !== 'review') return [];
  const out = excluded();
  const settled = readTsv(RESULTS).filter(r => r.rep === rep && r.pool === 'review' && !out.has(r.case) && (r.outcome === 'REVIEWED' || r.outcome === 'BLOCKED'))
    .sort((a, b) => a.case.localeCompare(b.case) || a.arm.localeCompare(b.arm));
  const reviewed = settled.filter(r => r.outcome === 'REVIEWED');
  const first = (stage === 'smoke' ? reviewed.slice(0, 1) : settled).map(r => ({ id: r.case, arm: r.arm, pass: String(pass) }));
  const second = stage === 'review' ? reviewed.slice(0, REPEAT_GRADINGS).map(r => ({ id: r.case, arm: r.arm, pass: String(pass + 1) })) : [];
  return [...first, ...second];
}

const spent = () => readTsv(RESULTS).filter(r => r.rep === rep).reduce((sum, r) => sum + Number(r.cost), 0);
let stop = null, ran = 0;

async function drain(queue, work) {
  await Promise.all(Array.from({ length: JOBS }, async () => {
    while (stop === null && queue.length > 0) {
      if (spent() >= CAP_USD) { stop = 'cap'; break; }
      if (Date.now() >= deadline) { stop = 'time'; break; }
      const row = await work(queue.shift());
      appendTsv(RESULTS, RESULT_COLUMNS, row);
      ran += 1;
      console.log(RESULT_COLUMNS.map(k => row[k] ?? '').join('\t'));
      if (row.outcome === 'NOT_RUN' && row.detail.startsWith('limit')) stop = 'limit';
    }
  }));
}

const pendingCells = () => cells().filter(({ c, arm }) => !excluded().has(c.id) && !scored(readTsv(RESULTS), rep, c.id, arm));
const pendingGradings = () => gradings().filter(g => !scored(readTsv(RESULTS), rep, g.id, `grade${g.pass}:${g.arm}`));
await drain(pendingCells(), ({ c, arm }) => runCell({ rep, stage, c, arm }));
await drain(pendingGradings(), g => gradeReview({ rep, ...g, grader: arms.grader }));
const remaining = pendingCells().length + pendingGradings().length;
console.log(`run-grid stage=${stage} rep=${rep} ran=${ran} remaining=${remaining} spent=${spent().toFixed(2)} stop=${stop ?? '-'}`);
process.exit(stop ? 3 : remaining > 0 ? 1 : 0);
