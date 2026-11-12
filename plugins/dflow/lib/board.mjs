import { fenceFlags, splitLines } from './plan.mjs';

export const STATES = ['open', 'planned', 'doing', 'verify', 'done', 'deferred', 'n/a'];
export const NOTE_REQUIRED = new Set(['verify', 'deferred', 'n/a']);
const SEPARATOR = /^:?-+:?$/;
const ESCAPED = '\u0001';
const COLUMNS = { item: 2, assigned: 3, acceptance: 4, state: 5, note: 6 };

export const HEADER = '| # | Item | Assigned | Acceptance | State | Note |\n|---|---|---|---|---|---|';

function cells(line) {
  const trimmed = line.trim();
  if (!trimmed.startsWith('|')) return null;
  return trimmed.replaceAll('\\|', ESCAPED).split('|').map(field => field.trim().replaceAll(ESCAPED, '|'));
}

function blankNote(note) {
  return !note || note.trim() === '' || note.trim() === '-';
}

// The row rules mirror darkmem's board parser: six cells, a numeric first
// cell, unique numbers.
export function parseBoard(text) {
  const lines = splitLines(text);
  const fenced = fenceFlags(lines);
  const board = { title: null, covers: null, rows: [], malformed: [], lastRowLine: 0, hasTable: false };
  const candidates = [];
  lines.forEach((line, index) => {
    if (fenced[index]) return;
    if (board.title === null && line.startsWith('# ')) board.title = line.slice(2).trim();
    if (board.covers === null && line.startsWith('**Covers:**')) {
      board.covers = line.slice('**Covers:**'.length).trim();
      return;
    }
    const fields = cells(line);
    if (!fields) return;
    const first = fields[1] ?? '';
    if (first === '#' || SEPARATOR.test(first)) {
      board.hasTable = true;
      board.lastRowLine = index + 1;
      return;
    }
    board.lastRowLine = index + 1;
    const number = /^[0-9]+$/.test(first) ? Number(first) : null;
    if (fields.length !== 8) board.malformed.push({ line: index + 1, text: line, reason: `${fields.length - 2} cells, not 6`, number });
    else if (number === null) board.malformed.push({ line: index + 1, text: line, reason: 'the # cell is not a number', number });
    else candidates.push({ line: index + 1, fields, text: line, number });
  });
  const counts = new Map();
  for (const candidate of candidates) counts.set(candidate.number, (counts.get(candidate.number) ?? 0) + 1);
  for (const candidate of candidates) {
    if (counts.get(candidate.number) > 1) {
      board.malformed.push({ line: candidate.line, text: candidate.text, reason: `duplicate number ${candidate.number}`, number: candidate.number });
      continue;
    }
    const [, , item, assigned, acceptance, state, note] = candidate.fields;
    board.rows.push({ number: candidate.number, item, assigned, acceptance, state, note, line: candidate.line });
  }
  board.malformed.sort((left, right) => left.line - right.line);
  return board;
}

export function lintBoard(board) {
  const errors = board.malformed.map(row => `board line ${row.line}: ${row.reason}`);
  for (const row of board.rows) {
    if (!STATES.includes(row.state)) errors.push(`board row ${row.number}: state ${JSON.stringify(row.state)} is not one of ${STATES.join(', ')}`);
    else if (NOTE_REQUIRED.has(row.state) && blankNote(row.note)) errors.push(`board row ${row.number}: a row in ${row.state} needs a Note`);
  }
  return errors;
}

function escape(value) {
  return String(value ?? '').replace(/[\r\n]+/g, ' ').trim().replaceAll('|', '\\|');
}

function formatRow(number, row) {
  return `| ${number} | ${escape(row.item)} | ${escape(row.assigned)} | ${escape(row.acceptance)} | ${escape(row.state)} | ${escape(row.note) || '-'} |`;
}

export function addRow(text, row) {
  const board = parseBoard(text);
  const taken = [...board.rows, ...board.malformed].map(entry => entry.number ?? 0);
  const number = Math.max(0, ...taken) + 1;
  const lines = text.replace(/\s+$/, '').split('\n');
  if (!board.hasTable) {
    lines.push('', ...HEADER.split('\n'), formatRow(number, row));
  } else {
    lines.splice(board.lastRowLine, 0, formatRow(number, row));
  }
  return { text: `${lines.join('\n')}\n`, number };
}

// Only the changed cells are replaced, so padding and every other line keep
// their bytes and a branch that edits one row merges cleanly with another.
export function rewriteRow(text, number, changes) {
  const board = parseBoard(text);
  const row = board.rows.find(candidate => candidate.number === number);
  if (!row) return null;
  const lines = text.split('\n');
  const original = lines[row.line - 1];
  const pipes = [...original].flatMap((character, index) => (character === '|' && original[index - 1] !== '\\' ? [index] : []));
  let updated = original;
  for (const column of Object.keys(changes).sort((left, right) => COLUMNS[right] - COLUMNS[left])) {
    const start = pipes[COLUMNS[column] - 1] + 1;
    const end = pipes[COLUMNS[column]];
    updated = `${updated.slice(0, start)} ${escape(changes[column]) || '-'} ${updated.slice(end)}`;
  }
  lines[row.line - 1] = updated;
  return lines.join('\n');
}

export function boardCounts(board) {
  const counts = {};
  for (const row of board.rows) counts[row.state] = (counts[row.state] ?? 0) + 1;
  return counts;
}

export function emptyBoard(title) {
  return `# ${title}\n\n**Covers:** work planned and built with dflow in this repository.\n\n${HEADER}\n`;
}
