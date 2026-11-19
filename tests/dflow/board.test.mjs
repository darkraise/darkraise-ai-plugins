import assert from 'node:assert/strict';
import test from 'node:test';
import { addRow, boardCounts, emptyBoard, lintBoard, parseBoard, rewriteRow } from '../../plugins/dflow/lib/board.mjs';

const BOARD = `# board

**Covers:** the fixture.

| # | Item | Assigned | Acceptance | State | Note |
|---|---|---|---|---|---|
| 1 | Meter | docs/dflow/plans/a.md | It works | doing | - |
| 2 | Pipe \\| in a cell | - | Passes | verify | - |
| 3 | Short | - | open |
| x | Not numbered | - | Passes | open | - |
| 5 | Twice | - | Passes | open | - |
| 5 | Twice again | - | Passes | sleeping | - |
`;

test('a board parses to rows and reports malformed ones', () => {
  const board = parseBoard(BOARD);
  assert.equal(board.covers, 'the fixture.');
  assert.deepEqual(board.rows.map(row => [row.number, row.item, row.state]), [[1, 'Meter', 'doing'], [2, 'Pipe | in a cell', 'verify']]);
  assert.deepEqual(board.malformed.map(row => row.reason), ['4 cells, not 6', 'the # cell is not a number', 'duplicate number 5', 'duplicate number 5']);
  assert.deepEqual(boardCounts(board), { doing: 1, verify: 1 });
});

test('lint reports unknown states and a missing note', () => {
  const errors = lintBoard(parseBoard(BOARD.replace('| open | - |\n| 5 | Twice again', '| waiting | - |\n| 6 | Twice again')));
  assert.ok(errors.includes('board row 2: a row in verify needs a Note'));
  assert.ok(errors.some(error => error.startsWith('board row 5: state "waiting"')));
});

test('a row edit changes that row only, and a new row takes the next number', () => {
  const edited = rewriteRow(BOARD, 1, { state: 'verify', note: 'all tasks done at abc1234' });
  const changed = edited.split('\n').filter((line, index) => line !== BOARD.split('\n')[index]);
  assert.deepEqual(changed, ['| 1 | Meter | docs/dflow/plans/a.md | It works | verify | all tasks done at abc1234 |']);
  assert.equal(rewriteRow(BOARD, 9, { state: 'done' }), null);

  const { text, number } = addRow(BOARD, { item: 'New', assigned: 'p.md', acceptance: 'Passes', state: 'planned' });
  assert.equal(number, 6);
  assert.equal(parseBoard(text).rows.at(-1).item, 'New');
  const fresh = addRow(emptyBoard('b'), { item: 'First', assigned: '-', acceptance: 'Passes', state: 'open' });
  assert.deepEqual(parseBoard(fresh.text).rows.map(row => [row.number, row.note]), [[1, '-']]);
});
