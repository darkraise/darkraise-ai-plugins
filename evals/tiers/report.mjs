#!/usr/bin/env node
// Print the per-row decision table and the review-seat table as Markdown.
// Usage: node evals/tiers/report.mjs [--rep N] [--pass P]
//        node evals/tiers/report.mjs --pipeline [--rep N]
// --pipeline prints the pipeline stage's pass^2, cost and median wall time per arm.
// --pass reads the review grades of pass P and its repeat P + 1 (default 1).
import { existsSync, readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { parseArgs } from 'node:util';
import { SLICES, readManifest } from './lib/cases.mjs';
import { decideReview, decideRow, decideSlices, graderDisagreements } from './lib/decide.mjs';
import { summarize } from './lib/pipeline-report.mjs';
import { GRADES, PIPELINE_RESULTS, RESULTS, readTsv, scored } from './lib/results.mjs';
import { DATA } from './lib/sh.mjs';

const { values } = parseArgs({ options: { rep: { type: 'string', default: '1' }, pass: { type: 'string', default: '1' }, pipeline: { type: 'boolean', default: false } } });
const rep = values.rep;
if (values.pipeline) {
  const lines = [`# Pipeline eval - repetition ${rep}`, ''];
  const arms = summarize(readTsv(PIPELINE_RESULTS).filter(r => r.rep === rep));
  if (arms.length === 0) lines.push('No pipeline runs recorded.');
  for (const a of arms) lines.push(`- \`${a.arm}\`: pass^2 ${a.pass2}/${a.cases}, cost $${a.cost.toFixed(2)}, median ${a.median}s`);
  console.log(lines.join('\n'));
  process.exit(0);
}
const pass = Number(values.pass);
const arms = JSON.parse(readFileSync(resolve(DATA, 'arms.json'), 'utf8'));
const { start, cases } = readManifest();
const results = readTsv(RESULTS);
const cell = (id, arm) => {
  const r = scored(results, rep, id, arm);
  return r ? { outcome: r.outcome, cost: Number(r.cost) } : undefined;
};
const money = n => Number.isFinite(n) ? `$${n.toFixed(2)}` : '-';
const excluded = new Map(results.filter(r => r.rep === rep && r.outcome === 'EXCLUDED').map(r => [r.case, r.detail]));
const out = [`# Tier eval - repetition ${rep}`, '', `Start commit: \`${start}\``, '', '## Implementer rows', ''];
for (const [row, rowArms] of Object.entries(arms.rows)) {
  const onRow = cases.filter(c => c.row === Number(row));
  const mine = onRow.filter(c => !excluded.has(c.id));
  const d = decideRow(rowArms, mine, cell, Number(row) >= 2);
  for (const c of onRow.filter(c => excluded.has(c.id))) d.notes.push(`excluded ${c.id}: ${excluded.get(c.id)}`);
  out.push(`### Row ${row}: ${d.verdict}`, '');
  if (d.stats.length > 0) {
    out.push('| Arm | PASS | Of | Cost per PASS | Regressions |', '|---|---|---|---|---|');
    for (const s of d.stats) out.push(`| \`${s.arm}\` | ${s.pass} | ${s.of} | ${money(s.perPass)} | ${s.regressions.length} |`);
    out.push('');
  }
  for (const note of d.notes) out.push(`- ${note}`);
  out.push('');
}
const grades = readTsv(GRADES).filter(g => g.rep === rep && !excluded.has(g.case));
out.push('## Review seats', '', '| Arm | Found | Of | Under-graded | Verdict | Missed Critical |', '|---|---|---|---|---|---|');
for (const s of decideReview(arms.review, grades.filter(g => g.pass === String(pass)))) {
  out.push(`| \`${s.arm}\` | ${s.found} | ${s.of} | ${s.underGraded} | ${s.verdict} | ${s.missedCritical.join(', ') || '-'} |`);
}
const sliceCases = existsSync(SLICES) ? readManifest(SLICES).cases : [];
for (const [id, why] of excluded) if (!cases.some(c => c.id === id) && !sliceCases.some(c => c.id === id)) out.push('', `Excluded review case ${id}: ${why}`);
const g = graderDisagreements(grades, pass);
out.push('', `Grader consistency: ${g.disagreements} disagreements on ${g.repeated} repeated gradings - ${g.disagreements > 1 ? 'INCONSISTENT: fix the grader prompt and re-grade before reading the table above' : 'usable'}.`);
if (existsSync(SLICES)) {
  const d = decideSlices(arms.slice, sliceCases.filter(c => !excluded.has(c.id)), cell);
  out.push('', '## Slice cases', '', `| Case | Total | Assigned | ${arms.slice.map(arm => `\`${arm}\``).join(' | ')} |`, `|${'---|'.repeat(3 + arms.slice.length)}`);
  for (const r of d.rows) out.push(`| \`${r.id}\` | ${r.total} | \`${r.assigned}\` | ${r.outcomes.join(' | ')} |`);
  out.push('', `Slice verdict: ${d.verdict}`);
  for (const c of sliceCases.filter(c => excluded.has(c.id))) out.push(`- excluded ${c.id}: ${excluded.get(c.id)}`);
}
const spent = results.filter(r => r.rep === rep).reduce((sum, r) => sum + Number(r.cost), 0);
out.push('', `Notional spend: ${money(spent)} over ${results.filter(r => r.rep === rep).length} runs.`);
console.log(out.join('\n'));
