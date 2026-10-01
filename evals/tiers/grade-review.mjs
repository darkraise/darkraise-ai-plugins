#!/usr/bin/env node
// Grade one review against its case rubric with a model call.
// Usage: node evals/tiers/grade-review.mjs CASE_ID ARM [--rep N] [--pass P]
// Exit: 0 graded; 1 the grader produced nothing usable; 2 usage.
import { existsSync, readFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { parseArgs } from 'node:util';
import { DATA } from './lib/sh.mjs';
import { invoke } from './lib/claude.mjs';
import { GRADES, GRADE_COLUMNS, RESULTS, RESULT_COLUMNS, appendTsv, armDir } from './lib/results.mjs';

const SECONDS = 600;
const squash = s => s.replace(/\s+/g, ' ').trim();

// defects RUBRIC — the defect ids a rubric declares, one `## D<n>:` heading each.
export function defects(rubric) {
  return [...rubric.matchAll(/^## (D\d+):/gm)].map(m => m[1]);
}

export function graderPrompt(rubric, review) {
  return `You are grading a review against a list of known defects. Use only the two documents below.

For each defect in the rubric, decide whether the review reports it. A defect counts as found when the review names the same faulty behaviour or mechanism, even in other words or at another line. A finding about the same file that describes a different problem does not count. When it is found, quote one sentence of the review, verbatim, that reports it, and give the severity the review assigned it: Critical, Important or Minor.

Reply with one JSON object and nothing else:
{"defects": [{"id": "D1", "found": true, "severity": "Important", "quote": "..."}, {"id": "D2", "found": false, "severity": null, "quote": null}]}

<rubric>
${rubric}
</rubric>

<review>
${review}
</review>
`;
}

// readGrades IDS REVIEW REPLY — one grade per rubric defect, or null when the
// reply holds no JSON object. A defect is found only when the grader's quote
// is really in the review: a quote it invented is a miss.
export function readGrades(ids, review, reply) {
  let parsed;
  try { parsed = JSON.parse(reply.slice(reply.indexOf('{'), reply.lastIndexOf('}') + 1)); } catch { return null; }
  if (!Array.isArray(parsed.defects)) return null;
  const text = squash(review);
  return ids.map(id => {
    const g = parsed.defects.find(d => d.id === id) ?? {};
    const quote = typeof g.quote === 'string' ? squash(g.quote) : '';
    const found = g.found === true && quote.length >= 12 && text.includes(quote);
    return { defect: id, found: found ? '1' : '0', severity: found ? String(g.severity ?? '') : '', quote: found ? quote : '' };
  });
}

// gradeReview { rep, id, arm, pass, grader } — grades DIR/review.md, appends
// one row per defect to review-grades.tsv, and returns the results row. A cell
// with no review.md was cut short before it reported anything: it misses
// every defect, with no grader call, so the arm still has a full set of grades.
export async function gradeReview({ rep, id, arm, pass, grader }) {
  const row = { rep, stage: 'grade', case: id, pool: 'review', row: '', arm: `grade${pass}:${arm}`, model: '', cost: '0.0000', seconds: 0, turns: 0 };
  try {
    const dir = armDir(rep, id, arm);
    const ids = defects(readFileSync(resolve(DATA, 'cases/reviews', `${id}.md`), 'utf8'));
    let grades;
    if (existsSync(join(dir, 'review.md'))) {
      const review = readFileSync(join(dir, 'review.md'), 'utf8');
      const rubric = readFileSync(resolve(DATA, 'cases/reviews', `${id}.md`), 'utf8');
      const inv = await invoke({ ...grader, body: null, prompt: graderPrompt(rubric, review), cwd: dir, tools: [], seconds: SECONDS, dir: join(dir, `grade${pass}`) });
      Object.assign(row, { model: inv.model, cost: inv.cost.toFixed(4), seconds: inv.seconds, turns: inv.turns });
      grades = inv.kind === 'ok' ? readGrades(ids, review, inv.text) : null;
      if (grades === null) return { ...row, outcome: 'NOT_RUN', detail: inv.kind === 'ok' ? 'error: the grader reply holds no JSON object' : `${inv.kind}: ${inv.text.slice(0, 200)}` };
    } else {
      grades = ids.map(defect => ({ defect, found: '0', severity: '', quote: '' }));
    }
    for (const g of grades) appendTsv(GRADES, GRADE_COLUMNS, { rep, case: id, arm, pass, ...g });
    return { ...row, outcome: 'GRADED', detail: `found=${grades.filter(g => g.found === '1').length}/${grades.length}` };
  } catch (error) {
    return { ...row, outcome: 'NOT_RUN', detail: `error: ${error.message.slice(0, 200)}` };
  }
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const { values, positionals } = parseArgs({ allowPositionals: true, options: { rep: { type: 'string', default: '1' }, pass: { type: 'string', default: '1' } } });
  const [id, arm] = positionals;
  if (!id || !arm) { console.error('usage: grade-review.mjs CASE_ID ARM [--rep N] [--pass P]'); process.exit(2); }
  const { grader } = JSON.parse(readFileSync(resolve(DATA, 'arms.json'), 'utf8'));
  const row = await gradeReview({ rep: values.rep, id, arm, pass: values.pass, grader });
  appendTsv(RESULTS, RESULT_COLUMNS, row);
  console.log(RESULT_COLUMNS.map(k => row[k] ?? '').join('\t'));
  process.exit(row.outcome === 'GRADED' ? 0 : 1);
}
