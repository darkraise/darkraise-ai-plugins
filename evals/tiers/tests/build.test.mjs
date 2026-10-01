import assert from 'node:assert/strict';
import { existsSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { after, test } from 'node:test';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { PLAN, fixture } from './fixture.mjs';

const fx = fixture();
after(() => rmSync(fx.top, { recursive: true, force: true }));
const { buildCase, buildReview } = await import('../build-case.mjs');
const { gradeImpl } = await import('../grade-case.mjs');
const { MARKER } = await import('../lib/strip.mjs');

const greet = { id: 'w-fixture-t1', pool: 'written', row: 1, plan: PLAN, task: 1, base: fx.planned, result: fx.greet };
const shout = { id: 's-fixture-t2', pool: 'stripped', row: 5, plan: PLAN, task: 2, base: fx.greet, result: fx.shout };
const done = { kind: 'ok', text: '**Status:** DONE' };
const script = name => fileURLToPath(new URL(`../${name}`, import.meta.url));

// built — a fresh greet case with the historical change applied, as a run
// that implemented the task would leave it.
function built(name) {
  const { info } = buildCase(greet, join(fx.work, name));
  spawnSync('git', ['apply', join(fx.stub, 'greet.patch')], { cwd: info.work });
  return info;
}

test('an as-written case is the base snapshot with the brief where production puts it', () => {
  const dir = join(fx.work, 'written');
  const { info, prompt } = buildCase(greet, dir);
  assert.deepEqual([info.id, info.kind, info.work, info.result, info.allowed, info.tests], ['w-fixture-t1', 'impl', join(dir, 'work'), fx.greet, ['src/greet.sh', 'tests/greet.test.sh'], ['tests/greet.test.sh']]);
  assert.deepEqual(JSON.parse(readFileSync(join(dir, 'case.json'), 'utf8')), info);
  assert.equal(existsSync(join(info.work, 'src/greet.sh')), false);
  assert.match(readFileSync(join(info.work, '.superpowers/sdd/eval/task-1-brief.md'), 'utf8'), /echo hello/);
  assert.match(prompt, /^You are implementing Task 1: Greet\n/);
  assert.match(prompt, new RegExp(`Read your task brief first: ${join(info.work, '.superpowers/sdd/eval/task-1-brief.md')}`));
  assert.match(prompt, /This is Task 1 of the plan 2026-09-20-fixture\.md\./);
  assert.match(prompt, new RegExp(`Work from: ${info.work}`));
  assert.doesNotMatch(prompt, /\[BRIEF_FILE\]|\[REPORT_FILE\]|\[directory\]|\[task name\]|write that code yourself/);
});

test('a stripped case hides the implementation and the plan', () => {
  const { info, prompt } = buildCase(shout, join(fx.work, 'stripped'));
  const brief = readFileSync(join(info.work, '.superpowers/sdd/eval/task-2-brief.md'), 'utf8');
  assert.equal(brief.split(MARKER).length - 1, 1);
  assert.doesNotMatch(brief, /echo HELLO/);
  assert.match(brief, /\[ "\$out" = "HELLO" \]/);
  assert.equal(existsSync(join(info.work, 'docs/superpowers')), false);
  assert.equal(existsSync(join(info.work, 'src/greet.sh')), true);
  assert.match(prompt, /write that code yourself\. The plan file is not available\./);
  assert.deepEqual([info.allowed, info.tests], [['src/shout.sh', 'tests/shout.test.sh'], ['tests/shout.test.sh']]);
});

test('a code review case snapshots the head and hands over one diff file', () => {
  const { info, prompt } = buildReview({ id: 'r-code-fixture', kind: 'code', base: fx.planned, head: fx.greet, plan: PLAN, description: 'Adds the greet script.' }, join(fx.work, 'codereview'));
  const diffFile = join(info.work, '.superpowers/sdd/eval/review.diff');
  assert.match(readFileSync(diffFile, 'utf8'), /feat: add greet[\s\S]*2 files changed[\s\S]*\+echo hello/);
  assert.deepEqual([existsSync(join(info.work, 'src/greet.sh')), existsSync(join(info.work, 'src/shout.sh'))], [true, false]);
  assert.match(prompt, /## What Was Implemented\n\nAdds the greet script\./);
  assert.match(prompt, new RegExp(`Read this file first: ${diffFile}`));
  assert.match(prompt, new RegExp(`for ${fx.planned.slice(0, 7)}\\.\\.${fx.greet.slice(0, 7)}`));
  assert.doesNotMatch(prompt, /\[DESCRIPTION\]|\[PLAN_OR_REQUIREMENTS\]|\[DIFF_FILE\]|\[BASE_SHA\]|\[HEAD_SHA\]/);
});

test('a plan review case hides the earlier verdict and supplies the criteria', () => {
  const { info, prompt } = buildReview({ id: 'r-plan-fixture', kind: 'plan', commit: fx.planned, plan: PLAN, spec: PLAN }, join(fx.work, 'planreview'));
  assert.doesNotMatch(readFileSync(join(info.work, PLAN), 'utf8'), /Plan review:/);
  assert.match(prompt, /\*\*Plan:\*\* .*2026-09-20-fixture\.md/);
  const root = prompt.match(/Read the criteria file at (\S+)\/criteria\/plan-review\.md/)[1];
  assert.equal(existsSync(join(root, 'criteria/plan-review.md')), true);
  assert.match(readFileSync(prompt.match(/\*\*plan-lint output:\*\* (\S+)/)[1], 'utf8'), /was not run/);
  assert.throws(() => buildReview({ id: 'r-plan-bad', kind: 'plan', commit: fx.planned, plan: PLAN, spec: 'docs/none.md' }, join(fx.work, 'bad')), /docs\/none\.md is missing/);
});

test('gradeImpl passes the historical change and fails a wrong, cheating or stray one', async () => {
  assert.deepEqual(await gradeImpl(built('g-pass'), done), { outcome: 'PASS', detail: 'status=DONE' });
  const wrong = built('g-wrong');
  writeFileSync(join(wrong.work, 'src/greet.sh'), 'echo nope\n');
  assert.deepEqual(await gradeImpl(wrong, done), { outcome: 'FAIL', detail: 'status=DONE failed=tests/greet.test.sh' });
  const cheat = built('g-cheat');
  writeFileSync(join(cheat.work, 'src/greet.sh'), 'echo nope\n');
  writeFileSync(join(cheat.work, 'tests/greet.test.sh'), 'true\n');
  assert.equal((await gradeImpl(cheat, done)).outcome, 'FAIL');
  const stray = built('g-stray');
  writeFileSync(join(stray.work, 'extra.txt'), 'x\n');
  assert.deepEqual(await gradeImpl(stray, done), { outcome: 'FAIL', detail: 'status=DONE outside=extra.txt' });
});

test('gradeImpl grades a blocked or cut-short run as BLOCKED', async () => {
  assert.equal((await gradeImpl(built('g-blocked'), { kind: 'ok', text: 'Status: BLOCKED' })).outcome, 'BLOCKED');
  assert.deepEqual(await gradeImpl(built('g-timeout'), { kind: 'timeout', text: '' }), { outcome: 'BLOCKED', detail: 'status=none cut=timeout' });
});

test('the two command lines build a manifest case and re-grade a finished run', () => {
  const reviewDir = join(fx.work, 'cli-review');
  assert.equal(spawnSync(process.execPath, [script('build-case.mjs'), 'r-code-fixture', reviewDir]).status, 0);
  assert.match(readFileSync(join(reviewDir, 'prompt.txt'), 'utf8'), /Adds the greet script\./);
  mkdirSync(join(fx.data, 'cases'), { recursive: true });
  writeFileSync(join(fx.data, 'cases/manifest.tsv'), `# start ${fx.planned}\nid\tpool\trow\tplan\ttask\tbase\tresult\nw-fixture-t1\twritten\t1\t${PLAN}\t1\t${fx.planned}\t${fx.greet}\n`);
  const dir = join(fx.work, 'cli');
  const builtCli = spawnSync(process.execPath, [script('build-case.mjs'), 'w-fixture-t1', dir], { encoding: 'utf8' });
  assert.equal(builtCli.status, 0, builtCli.stderr);
  assert.match(readFileSync(join(dir, 'prompt.txt'), 'utf8'), /^You are implementing Task 1: Greet/);
  assert.equal(spawnSync(process.execPath, [script('build-case.mjs'), 'no-such-case', dir]).status, 2);
  spawnSync('git', ['apply', join(fx.stub, 'greet.patch')], { cwd: join(dir, 'work') });
  writeFileSync(join(dir, 'output.json'), JSON.stringify({ result: '**Status:** DONE' }));
  const graded = spawnSync(process.execPath, [script('grade-case.mjs'), dir], { encoding: 'utf8' });
  assert.deepEqual([graded.status, graded.stdout], [0, 'w-fixture-t1\tPASS\tstatus=DONE\n']);
  assert.equal(spawnSync(process.execPath, [script('grade-case.mjs'), join(fx.work, 'nowhere')]).status, 2);
});
