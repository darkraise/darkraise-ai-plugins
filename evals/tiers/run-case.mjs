#!/usr/bin/env node
// Run one case on one arm and grade it: one row of results.tsv.
// Usage: node evals/tiers/run-case.mjs CASE_ID ARM [--rep N] [--stage NAME]
//        node evals/tiers/run-case.mjs CASE_ID ARM [--rep N] --exclude REASON
// --exclude runs nothing: it records the cell as EXCLUDED, for a case whose
// run cannot start for a harness reason.
// Exit: 0 scored or excluded; 1 NOT_RUN; 2 usage.
import { rmSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { parseArgs } from 'node:util';
import { buildCase, buildReview, findCase } from './build-case.mjs';
import { gradeImpl } from './grade-case.mjs';
import { agent, invoke } from './lib/claude.mjs';
import { RESULTS, RESULT_COLUMNS, appendTsv, armDir } from './lib/results.mjs';

const IMPL = { tools: ['Bash', 'Edit', 'Write', 'Read', 'Grep', 'Glob'], seconds: 1800 };
const REVIEW = { tools: ['Read', 'Grep', 'Glob'], seconds: 1200 };

// runCell { rep, stage, c, arm } — C is a manifest row (it has a pool) or a
// review case. A rate limit or a harness error is NOT_RUN and its detail
// starts with the kind, so the grid can tell a limit from an error. A harness
// exception is such an error: it must cost the grid one row, not the stage.
export async function runCell({ rep, stage, c, arm }) {
  const review = !c.pool;
  const row = { rep, stage, case: c.id, pool: c.pool ?? 'review', row: c.row ?? '', arm, model: '', cost: '0.0000', seconds: 0, turns: 0 };
  try {
    const dir = armDir(rep, c.id, arm);
    rmSync(dir, { recursive: true, force: true });
    const built = review ? buildReview(c, dir) : buildCase(c, dir);
    const inv = await invoke({ ...agent(arm), prompt: built.prompt, cwd: built.info.work, ...(review ? REVIEW : IMPL), dir });
    Object.assign(row, { model: inv.model, cost: inv.cost.toFixed(4), seconds: inv.seconds, turns: inv.turns });
    if (inv.kind === 'limit' || inv.kind === 'error') return { ...row, outcome: 'NOT_RUN', detail: `${inv.kind}: ${inv.text.slice(0, 200)}` };
    if (!review) return { ...row, ...(await gradeImpl(built.info, inv)) };
    if (inv.kind !== 'ok') return { ...row, outcome: 'BLOCKED', detail: `cut=${inv.kind}` };
    writeFileSync(join(dir, 'review.md'), inv.text);
    return { ...row, outcome: 'REVIEWED', detail: '' };
  } catch (error) {
    return { ...row, outcome: 'NOT_RUN', detail: `error: ${error.message.slice(0, 200)}` };
  }
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const { values, positionals } = parseArgs({ allowPositionals: true, options: { rep: { type: 'string', default: '1' }, stage: { type: 'string', default: 'manual' }, exclude: { type: 'string' } } });
  const [id, arm] = positionals;
  const c = id && arm ? findCase(id) : null;
  if (!c) { console.error('usage: run-case.mjs CASE_ID ARM [--rep N] [--stage NAME | --exclude REASON]'); process.exit(2); }
  const row = values.exclude === undefined
    ? await runCell({ rep: values.rep, stage: values.stage, c, arm })
    : { rep: values.rep, stage: 'manual', case: c.id, pool: c.pool ?? 'review', row: c.row ?? '', arm, outcome: 'EXCLUDED', model: '', cost: '0.0000', seconds: 0, turns: 0, detail: values.exclude };
  appendTsv(RESULTS, RESULT_COLUMNS, row);
  console.log(RESULT_COLUMNS.map(k => row[k] ?? '').join('\t'));
  process.exit(row.outcome === 'NOT_RUN' ? 1 : 0);
}
