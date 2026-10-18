// The Stage 1 decision rule of docs/superpowers/notes/2026-10-17-controller-model-eval.md.
// Rows may come from a TSV, so every number is read through Number().

export const BASE = 'sonnet@high';
export const CANDIDATE = 'opus@low';
// The most an Opus controller may cost per dispatch, as a multiple of the base.
export const MAX_RATIO = 1.5;
// Sleep and ListAgents calls in one plan at which the plan counts as a busy wait.
export const BUSY = 20;
// How many more tracking failures the base needs before the difference is
// read as more than noise.
export const MARGIN = 2;

const num = v => Number(v ?? 0);

// failures ROW — the tracking and protocol slips of one plan: launches left
// running, routed reviews that missed their seat, owner nudges, and one for a
// busy wait.
export function failures(row) {
  return num(row.inFlight) + num(row.seatMisses) + num(row.nudges) + (num(row.sleeps) + num(row.listAgents) >= BUSY ? 1 : 0);
}

const total = (rows, key) => rows.reduce((sum, r) => sum + num(r[key]), 0);
const slips = rows => rows.reduce((sum, r) => sum + failures(r), 0);
const perDispatch = rows => total(rows, 'controllerCost') / Math.max(1, total(rows, 'dispatches'));

// stage1 ROWS — the production A/B over usable rows { arm, complete: yes|no,
// ... }. keep when Opus costs over MAX_RATIO per dispatch or fails as often;
// switch when the base fails at least MARGIN more often and Opus left no more
// plans unfinished; ambiguous otherwise; incomplete until each arm has 3 plans.
export function stage1(rows) {
  const base = rows.filter(r => r.arm === BASE);
  const opus = rows.filter(r => r.arm === CANDIDATE);
  const facts = { ratio: perDispatch(opus) / Math.max(1e-9, perDispatch(base)), failures: { [BASE]: slips(base), [CANDIDATE]: slips(opus) } };
  if (base.length < 3 || opus.length < 3) return { decision: 'incomplete', ...facts };
  const unfinished = list => list.filter(r => r.complete !== 'yes').length;
  if (facts.ratio > MAX_RATIO || slips(opus) >= slips(base)) return { decision: 'keep', ...facts };
  if (slips(base) - slips(opus) >= MARGIN && unfinished(opus) <= unfinished(base)) return { decision: 'switch', ...facts };
  return { decision: 'ambiguous', ...facts };
}
