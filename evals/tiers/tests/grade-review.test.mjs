import assert from 'node:assert/strict';
import { mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { after, test } from 'node:test';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { fixture, modes } from './fixture.mjs';

const fx = fixture();
after(() => rmSync(fx.top, { recursive: true, force: true }));
const { defects, gradeReview, graderPrompt, readGrades } = await import('../grade-review.mjs');
const { GRADES, RESULTS, armDir, readTsv } = await import('../lib/results.mjs');

const REVIEW = 'The refusal search is unanchored,\n  so any line matches. Also a typo.';
const grader = { model: 'opus', effort: 'low' };
const reply = defectList => writeFileSync(join(fx.stub, 'grade.json'), JSON.stringify({ defects: defectList }));
const lastCall = () => JSON.parse(readFileSync(join(fx.stub, 'calls.log'), 'utf8').trim().split('\n').at(-1));

function reviewed(rep, arm) {
  mkdirSync(armDir(rep, 'r-code-fixture', arm), { recursive: true });
  writeFileSync(join(armDir(rep, 'r-code-fixture', arm), 'review.md'), REVIEW);
}

test('a rubric declares its defects and the grader sees the rubric and the review', () => {
  assert.deepEqual(defects('# R\n\n## D1: a\n\n## D2: b\n\ntext ## D9: not a heading\n## D3: c\n'), ['D1', 'D2', 'D3']);
  assert.match(graderPrompt('RUBRIC TEXT', 'REVIEW TEXT'), /one JSON object and nothing else[\s\S]*<rubric>\nRUBRIC TEXT\n<\/rubric>\n\n<review>\nREVIEW TEXT\n<\/review>/);
});

test('readGrades counts a defect only when the quote is in the review', () => {
  const text = 'Here: {"defects": [{"id": "D1", "found": true, "severity": "Critical", "quote": "The refusal search is unanchored, so any line matches."}, {"id": "D2", "found": true, "severity": "Minor", "quote": "The stub never emits JSON at all."}]}';
  assert.deepEqual(readGrades(['D1', 'D2', 'D3'], REVIEW, text), [
    { defect: 'D1', found: '1', severity: 'Critical', quote: 'The refusal search is unanchored, so any line matches.' },
    { defect: 'D2', found: '0', severity: '', quote: '' },
    { defect: 'D3', found: '0', severity: '', quote: '' },
  ]);
  assert.equal(readGrades(['D1'], REVIEW, 'no json here'), null);
  assert.equal(readGrades(['D1'], REVIEW, '{"other": 1}'), null);
  assert.equal(readGrades(['D1'], REVIEW, '{"defects": [{"id": "D1", "found": true, "severity": "Minor", "quote": "Also"}]}')[0].found, '0');
});

test('gradeReview appends one grade per defect and returns the grading row', async () => {
  reviewed(1, 'judge-opus@high');
  reply([{ id: 'D1', found: true, severity: 'Important', quote: 'The refusal search is unanchored' }]);
  modes(fx.stub, 'grade');
  const row = await gradeReview({ rep: '1', id: 'r-code-fixture', arm: 'judge-opus@high', pass: '1', grader });
  assert.deepEqual([row.stage, row.case, row.arm, row.outcome, row.detail, row.cost], ['grade', 'r-code-fixture', 'grade1:judge-opus@high', 'GRADED', 'found=1/2', '0.5000']);
  assert.deepEqual(readTsv(GRADES).map(g => [g.rep, g.case, g.arm, g.pass, g.defect, g.found, g.severity].join(' ')), [
    '1 r-code-fixture judge-opus@high 1 D1 1 Important', '1 r-code-fixture judge-opus@high 1 D2 0 ',
  ]);
  const call = lastCall();
  assert.deepEqual(call.args.slice(0, 5), ['-p', '--model', 'opus', '--effort', 'low']);
  assert.equal(call.args.includes('--append-system-prompt-file'), false);
  assert.match(call.prompt, /<rubric>\n# Rubric[\s\S]*<review>\nThe refusal search/);
});

test('a grader reply without JSON, or a rate limit, is NOT_RUN and writes no grade', async () => {
  reviewed(2, 'judge-opus@high');
  modes(fx.stub, 'blocked');
  const bad = await gradeReview({ rep: '2', id: 'r-code-fixture', arm: 'judge-opus@high', pass: '1', grader });
  assert.deepEqual([bad.outcome, bad.detail], ['NOT_RUN', 'error: the grader reply holds no JSON object']);
  modes(fx.stub, 'limit');
  const limited = await gradeReview({ rep: '2', id: 'r-code-fixture', arm: 'judge-opus@high', pass: '1', grader });
  assert.equal(limited.outcome, 'NOT_RUN');
  assert.match(limited.detail, /^limit: /);
  assert.equal(readTsv(GRADES).filter(g => g.rep === '2').length, 0);
});

test('a cell that produced no review misses every defect without a grader call', async () => {
  const calls = readFileSync(join(fx.stub, 'calls.log'), 'utf8');
  const row = await gradeReview({ rep: '5', id: 'r-code-fixture', arm: 'judge-opus@high', pass: '1', grader });
  assert.deepEqual([row.outcome, row.detail, row.cost], ['GRADED', 'found=0/2', '0.0000']);
  assert.deepEqual(readTsv(GRADES).filter(g => g.rep === '5').map(g => [g.defect, g.found]), [['D1', '0'], ['D2', '0']]);
  assert.equal(readFileSync(join(fx.stub, 'calls.log'), 'utf8'), calls);
  const missing = await gradeReview({ rep: '5', id: 'r-no-rubric', arm: 'judge-opus@high', pass: '1', grader });
  assert.equal(missing.outcome, 'NOT_RUN');
  assert.match(missing.detail, /^error: ENOENT/);
});

test('the command line grades one review and appends the grading row', () => {
  reviewed(3, 'judge-sonnet-high');
  reply([{ id: 'D2', found: true, severity: 'Minor', quote: 'so any line matches.' }]);
  modes(fx.stub, 'grade');
  const cli = (...args) => spawnSync(process.execPath, [fileURLToPath(new URL('../grade-review.mjs', import.meta.url)), ...args], { encoding: 'utf8' });
  const ok = cli('r-code-fixture', 'judge-sonnet-high', '--rep', '3', '--pass', '2');
  assert.equal(ok.status, 0, ok.stderr);
  assert.equal(cli('r-code-fixture').status, 2);
  assert.deepEqual(readTsv(RESULTS).filter(r => r.rep === '3').map(r => [r.arm, r.outcome, r.detail]), [['grade2:judge-sonnet-high', 'GRADED', 'found=1/2']]);
  assert.deepEqual(readTsv(GRADES).filter(g => g.rep === '3').map(g => [g.pass, g.defect, g.found]), [['2', 'D1', '0'], ['2', 'D2', '1']]);
});
