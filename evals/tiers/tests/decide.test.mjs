import assert from 'node:assert/strict';
import { test } from 'node:test';
import { decideReview, decideRow, graderDisagreements } from '../lib/decide.mjs';

const cases = n => Array.from({ length: n }, (_, i) => ({ id: `c${i}`, pool: i < 4 ? 'stripped' : 'written' }));
const table = spec => (id, arm) => spec[arm]?.[id] ?? spec[arm]?.all;
const pass = cost => ({ outcome: 'PASS', cost }), fail = cost => ({ outcome: 'FAIL', cost });

test('decideRow moves to the cheapest arm with no regression', () => {
  const d = decideRow(['cur', 'mid', 'low'], cases(8), table({ cur: { all: pass(4) }, mid: { all: pass(2) }, low: { all: pass(1) } }));
  assert.equal(d.verdict, 'MOVE to low');
  assert.match(d.notes[0], /^8 paired trials \(4 stripped\); zero regressions is consistent with a true regression rate up to 38%$/);
  assert.deepEqual(d.stats.map(s => [s.arm, s.pass, s.of, s.perPass, s.regressions.length]), [['cur', 8, 8, 4, 0], ['mid', 8, 8, 2, 0], ['low', 8, 8, 1, 0]]);
  const skip = decideRow(['cur', 'mid', 'low'], cases(8), table({ cur: { all: pass(4) }, mid: { all: pass(2) }, low: { all: pass(1), c5: fail(1) } }));
  assert.equal(skip.verdict, 'MOVE to mid');
  assert.equal(skip.notes[1], 'low regresses on c5');
});

test('decideRow holds a row on regressions and flags thin evidence', () => {
  assert.equal(decideRow(['cur', 'low'], cases(8), table({ cur: { all: pass(4) }, low: { all: pass(1), c0: fail(1) } })).verdict, 'INCONCLUSIVE');
  assert.equal(decideRow(['cur', 'low'], cases(8), table({ cur: { all: pass(4) }, low: { all: pass(1), c0: fail(1), c1: fail(1) } })).verdict, 'UNCHANGED');
  assert.equal(decideRow(['cur', 'low'], cases(8), table({ cur: { all: pass(1) }, low: { all: pass(4) } })).verdict, 'UNCHANGED');
  assert.equal(decideRow(['cur', 'low'], cases(3), table({ cur: { all: pass(4) }, low: { all: pass(1) } })).verdict, 'MOVE to low - owner ruling, only 3 stripped cases');
  assert.equal(decideRow(['cur', 'low'], cases(3), table({ cur: { all: pass(4) }, low: { all: pass(1) } }), false).verdict, 'MOVE to low');
  assert.equal(decideRow(['cur', 'low'], cases(8), table({ cur: { all: pass(4) } })).verdict, 'INCOMPLETE');
  assert.equal(decideRow(['cur', 'low'], [], table({})).verdict, 'NOT MEASURED');
  const flagged = decideRow(['cur', 'low'], cases(8), table({ cur: { all: pass(4), c0: fail(4), c1: fail(4) }, low: { all: pass(1) } }));
  assert.equal(flagged.notes.at(-1), 'cur does not pass 2 cases: second repetition with the next agent up');
});

const grade = (arm, defect, found, severity = 'Important', pass = '1') => ({ case: 'r', arm, pass, defect, found, severity });

test('decideReview needs equal recall and no missed Critical', () => {
  const cur = [grade('cur', 'D1', '1', 'Critical'), grade('cur', 'D2', '1'), grade('cur', 'D3', '0')];
  const verdict = rows => decideReview(['cur', 'low'], [...cur, ...rows])[1];
  assert.deepEqual(decideReview(['cur', 'low'], cur)[0], { arm: 'cur', found: 2, of: 3, underGraded: 0, verdict: 'current', missedCritical: [] });
  assert.equal(verdict([grade('low', 'D1', '1', 'Minor'), grade('low', 'D2', '1', 'null'), grade('low', 'D3', '0', 'Minor')]).underGraded, 2);
  assert.equal(verdict([grade('low', 'D1', '1'), grade('low', 'D2', '1'), grade('low', 'D3', '0')]).verdict, 'SUPPORTED');
  assert.equal(verdict([grade('low', 'D1', '1'), grade('low', 'D2', '0'), grade('low', 'D3', '0')]).verdict, 'NOT SUPPORTED');
  const missed = verdict([grade('low', 'D1', '0'), grade('low', 'D2', '1'), grade('low', 'D3', '1')]);
  assert.deepEqual([missed.verdict, missed.missedCritical], ['NOT SUPPORTED', ['r/D1']]);
  assert.equal(verdict([grade('low', 'D1', '1')]).verdict, 'INCOMPLETE');
});

test('graderDisagreements counts second-pass changes', () => {
  const rows = [grade('a', 'D1', '1'), grade('a', 'D2', '0'), grade('a', 'D1', '1', 'Important', '2'), grade('a', 'D2', '1', 'Important', '2')];
  assert.deepEqual(graderDisagreements(rows), { repeated: 2, disagreements: 1 });
  assert.deepEqual(graderDisagreements(rows, 3), { repeated: 0, disagreements: 0 });
});
