import { appendFileSync, existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { DATA, WORK } from './sh.mjs';

export const RESULTS = resolve(DATA, 'results/results.tsv');
export const GRADES = resolve(DATA, 'results/review-grades.tsv');
export const RESULT_COLUMNS = ['rep', 'stage', 'case', 'pool', 'row', 'arm', 'outcome', 'model', 'cost', 'seconds', 'turns', 'detail'];
export const GRADE_COLUMNS = ['rep', 'case', 'arm', 'pass', 'defect', 'found', 'severity', 'quote'];

// armDir REP CASE ARM — where one cell keeps its snapshot and transcripts.
export const armDir = (rep, id, arm) => join(WORK, `rep${rep}`, id, arm.replace('@', '-at-'));

export function readTsv(file) {
  if (!existsSync(file)) return [];
  const [header, ...lines] = readFileSync(file, 'utf8').split('\n').filter(Boolean);
  const keys = header.split('\t');
  return lines.map(line => Object.fromEntries(line.split('\t').map((v, i) => [keys[i], v])));
}

export function appendTsv(file, columns, row) {
  mkdirSync(dirname(file), { recursive: true });
  if (!existsSync(file)) writeFileSync(file, columns.join('\t') + '\n');
  appendFileSync(file, columns.map(k => String(row[k] ?? '').replace(/[\t\n\r]+/g, ' ')).join('\t') + '\n');
}

// scored ROWS REP CASE ARM — the result that settles a cell: its last row that
// is not NOT_RUN, or undefined while the cell still has to run.
export function scored(rows, rep, id, arm) {
  return rows.findLast(r => r.rep === String(rep) && r.case === id && r.arm === arm && r.outcome !== 'NOT_RUN');
}
