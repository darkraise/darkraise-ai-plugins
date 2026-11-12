import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';
import { parseBoard } from '../lib/board.mjs';
import { parsePlan } from '../lib/plan.mjs';
import { PLAN_FILE, dflow, git, makeProject, makeRepo, read, write } from './helpers.mjs';

test('init scaffolds the docs once and ignores .dflow', t => {
  const root = makeRepo(t);
  const first = dflow(root, ['init', '--gate', 'test=node t.mjs', '--darkmem', 'fixture']);
  assert.equal(first.status, 0, first.stderr);
  for (const file of ['project.md', 'decisions.md', 'gotchas.md', 'board.md', 'config.json']) assert.ok(fs.existsSync(path.join(root, 'docs/dflow', file)), file);
  assert.deepEqual(JSON.parse(read(root, 'docs/dflow/config.json')), { gates: [{ name: 'test', cmd: 'node t.mjs' }], darkmem: { project: 'fixture' } });
  assert.match(read(root, '.gitignore'), /^\.dflow\/$/m);

  write(root, 'docs/dflow/project.md', '# mine\n');
  const second = dflow(root, ['init']);
  assert.match(second.stdout, /already set up/);
  assert.equal(read(root, 'docs/dflow/project.md'), '# mine\n');
  assert.equal(read(root, '.gitignore').match(/\.dflow/g).length, 1);
});

test('plan new creates the file and a linked board row', t => {
  const root = makeRepo(t);
  dflow(root, ['init']);
  const created = dflow(root, ['plan', 'new', 'meter', '--title', 'Rate-limit meter']);
  assert.equal(created.status, 0, created.stderr);
  const plan = parsePlan(read(root, PLAN_FILE));
  assert.equal(plan.fields.branch, 'feat/x');
  assert.equal(plan.fields.board, '1');
  assert.deepEqual(parseBoard(read(root, 'docs/dflow/board.md')).rows.map(row => [row.item, row.assigned, row.state]), [['Rate-limit meter', PLAN_FILE, 'planned']]);
  assert.equal(dflow(root, ['plan', 'check']).status, 1);
  assert.equal(dflow(root, ['plan', 'new', 'meter', '--title', 'again']).status, 1);
});

test('approve stamps the plan, links the row and commits only those files', t => {
  const root = makeProject(t);
  assert.equal(parsePlan(read(root, PLAN_FILE)).fields.approved, '2026-11-12');
  assert.deepEqual(parseBoard(read(root, 'docs/dflow/board.md')).rows.map(row => [row.assigned, row.state]), [[PLAN_FILE, 'planned']]);
  assert.equal(git(root, 'log', '-1', '--format=%s'), 'docs(dflow): approve plan 2026-11-12-meter');
  assert.equal(git(root, 'status', '--porcelain'), '');
  assert.equal(dflow(root, ['plan', 'approve']).status, 1);
});

test('next refuses an unapproved plan, then walks the dependency order', t => {
  const root = makeProject(t);
  const first = dflow(root, ['next']);
  assert.equal(first.status, 0, first.stderr);
  assert.match(first.stdout, /### Task 1: Parse the header/);
  assert.match(first.stdout, /D1: a parser function/);
  assert.match(first.stdout, /dflow done 1 -m/);
  assert.doesNotMatch(first.stdout, /Task 2/);

  const status = JSON.parse(dflow(root, ['status', '--json']).stdout);
  assert.deepEqual(status.plan.current, { number: 1, title: 'Parse the header', state: 'wip', attempts: 0 });
  assert.equal(status.board.row.state, 'planned');
  assert.match(status.next, /^\/dflow:build — Task 1/);
  assert.ok(fs.existsSync(path.join(root, '.dflow/hud.json')));

  const unapproved = makeRepo(t);
  dflow(unapproved, ['init']);
  dflow(unapproved, ['plan', 'new', 'meter', '--title', 'Meter']);
  const refused = dflow(unapproved, ['next']);
  assert.equal(refused.status, 1);
  assert.match(refused.stderr, /not approved/);
});

test('status says so when no plan is active, and the brief is empty', t => {
  const root = makeRepo(t);
  assert.match(dflow(root, ['status']).stdout, /no active plan on feat\/x/);
  assert.equal(dflow(root, ['status', '--brief']).stdout, '');
  assert.equal(dflow(root, ['nonsense']).status, 2);
});
