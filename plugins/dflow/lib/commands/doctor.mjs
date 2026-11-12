import fs from 'node:fs';
import path from 'node:path';
import { lintBoard, parseBoard } from '../board.mjs';
import { fenceFlags, lintPlan, splitLines } from '../plan.mjs';
import { openPlans } from '../status.mjs';
import { backticked, readText } from '../util.mjs';

// decisions.md is history and may name files that are gone; these two describe
// the present.
const CHECKED_FOR_PATHS = ['project.md', 'gotchas.md'];

// A backticked span is treated as a repository path only when its first
// segment exists at the repository root, so `n/a` or `open/closed` never match.
function deadReferences(ctx, name, text) {
  const lines = splitLines(text);
  const fenced = fenceFlags(lines);
  const problems = [];
  lines.forEach((line, index) => {
    if (fenced[index]) return;
    for (const span of backticked(line)) {
      const candidate = span.replace(/[#:][^/]*$/, '').replace(/^\.\//, '');
      if (!/^[\w@.\-/]+$/.test(candidate) || !candidate.includes('/')) continue;
      const first = candidate.split('/')[0];
      if (!fs.existsSync(path.join(ctx.root, first))) continue;
      if (!fs.existsSync(path.join(ctx.root, candidate))) problems.push(`${name}:${index + 1}: \`${span}\` does not exist`);
    }
  });
  return problems;
}

// `plans` narrows the plan lint: ship checks the plan it ships, not a draft
// of other work that happens to sit beside it.
export function diagnose(ctx, { plans = openPlans(ctx) } = {}) {
  const problems = [];
  for (const [name, budget] of Object.entries(ctx.config.budgets)) {
    const text = readText(path.join(ctx.paths.docs, name));
    if (text === null) continue;
    const count = text.replace(/\n$/, '').split('\n').length;
    if (count > budget) problems.push(`${name}: ${count} lines, over its budget of ${budget}; prune it`);
  }
  for (const name of CHECKED_FOR_PATHS) {
    const text = readText(path.join(ctx.paths.docs, name));
    if (text !== null) problems.push(...deadReferences(ctx, name, text));
  }
  const board = readText(ctx.paths.board);
  if (board !== null) problems.push(...lintBoard(parseBoard(board)));
  for (const entry of plans) {
    for (const error of lintPlan(entry.plan).errors) problems.push(`${entry.rel}: ${error}`);
  }
  return problems;
}

export async function run(ctx, argv, { out }) {
  if (!fs.existsSync(ctx.paths.docs)) {
    out('dflow doctor: docs/dflow does not exist; run `dflow init`');
    return 1;
  }
  const problems = diagnose(ctx);
  if (!problems.length) {
    out('dflow doctor: ok (budgets, path references, board, open plans)');
    return 0;
  }
  out(`dflow doctor: ${problems.length} problem(s)`);
  for (const problem of problems) out(`- ${problem}`);
  return 1;
}
