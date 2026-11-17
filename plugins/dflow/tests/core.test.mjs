import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { parseBoard } from '../lib/board.mjs';
import { parsePlan } from '../lib/plan.mjs';
import { PLAN, PLAN_FILE, dflow, git, makeProject, makeRepo, read, write } from './helpers.mjs';

test('init scaffolds the docs once and ignores .dflow', t => {
  const root = makeRepo(t);
  const first = dflow(root, ['init', '--gate', 'test=node t.mjs']);
  assert.equal(first.status, 0, first.stderr);
  for (const file of ['project.md', 'decisions.md', 'gotchas.md', 'board.md', 'config.json']) assert.ok(fs.existsSync(path.join(root, 'docs/dflow', file)), file);
  assert.deepEqual(JSON.parse(read(root, 'docs/dflow/config.json')), { gates: [{ name: 'test', cmd: 'node t.mjs' }] });
  assert.match(read(root, '.gitignore'), /^\.dflow\/$/m);
  assert.match(read(root, '.gitattributes'), /^docs\/dflow\/decisions\.md merge=union\ndocs\/dflow\/gotchas\.md merge=union$/m);

  write(root, 'docs/dflow/project.md', '# mine\n');
  const second = dflow(root, ['init']);
  assert.match(second.stdout, /already set up/);
  assert.equal(read(root, 'docs/dflow/project.md'), '# mine\n');
  assert.equal(read(root, '.gitignore').match(/\.dflow/g).length, 1);
  assert.equal(read(root, '.gitattributes').match(/merge=union/g).length, 2);
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

test('.dflow ignores itself, also where init never ran or its line was dropped', t => {
  const fresh = makeRepo(t);
  assert.equal(dflow(fresh, ['plan', 'new', 'demo', '--title', 'Demo']).status, 0);
  assert.equal(read(fresh, '.dflow/.gitignore'), '*\n');
  assert.doesNotMatch(git(fresh, 'status', '--porcelain', '--untracked-files=all'), /\.dflow/);

  const root = makeProject(t);
  write(root, '.gitignore', read(root, '.gitignore').replace(/^\.dflow\/\n/m, ''));
  git(root, 'commit', '-q', '-am', 'chore: drop the .dflow line');
  fs.rmSync(path.join(root, '.dflow'), { recursive: true, force: true });
  write(root, 'verify1.mjs', '\n');
  write(root, 'src/limit.mjs', '1\n');
  git(root, 'add', 'src');
  const done = dflow(root, ['done', '1', '-m', 'feat: parse']);
  assert.equal(done.status, 0, done.stderr);
  assert.doesNotMatch(git(root, 'status', '--porcelain', '--untracked-files=all'), /\.dflow/);
});

test('the .dflow ignore file is never written through a symbolic link', t => {
  const outside = fs.realpathSync.native(fs.mkdtempSync(path.join(os.tmpdir(), 'dflow-outside-')));
  t.after(() => fs.rmSync(outside, { recursive: true, force: true }));

  const dangling = makeRepo(t);
  fs.mkdirSync(path.join(dangling, '.dflow'));
  fs.symlinkSync(path.join(outside, 'target'), path.join(dangling, '.dflow/.gitignore'));
  assert.equal(dflow(dangling, ['plan', 'new', 'demo', '--title', 'Demo']).status, 0);
  assert.equal(fs.existsSync(path.join(outside, 'target')), false);

  const linked = makeRepo(t);
  fs.symlinkSync(outside, path.join(linked, '.dflow'), 'dir');
  assert.equal(dflow(linked, ['plan', 'new', 'demo', '--title', 'Demo']).status, 0);
  assert.equal(fs.existsSync(path.join(outside, '.gitignore')), false);
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

test('a refused approval commit leaves the plan unapproved', t => {
  const root = makeRepo(t);
  dflow(root, ['init']);
  write(root, PLAN_FILE, PLAN);
  write(root, 'docs/dflow/board.md', '# board\n\n| # | Item | Assigned | Acceptance | State | Note |\n|---|---|---|---|---|---|\n| 1 | Meter | - | It works | open | - |\n');
  git(root, 'add', '-A');
  git(root, 'commit', '-q', '-m', 'docs: draft');
  write(root, '.git/hooks/pre-commit', '#!/bin/sh\nexit 1\n');
  fs.chmodSync(path.join(root, '.git/hooks/pre-commit'), 0o755);
  const refused = dflow(root, ['plan', 'approve']);
  assert.equal(refused.status, 1);
  assert.match(refused.stderr, /the plan is not approved/);
  assert.equal(parsePlan(read(root, PLAN_FILE)).fields.approved, undefined);
  assert.equal(parseBoard(read(root, 'docs/dflow/board.md')).rows[0].state, 'open');
  assert.equal(git(root, 'status', '--porcelain'), '');
  fs.rmSync(path.join(root, '.git/hooks/pre-commit'));
  assert.equal(dflow(root, ['plan', 'approve']).status, 0);
});

test('a board row that belongs to an open plan is not handed to another', t => {
  const root = makeProject(t);
  const taken = dflow(root, ['plan', 'new', 'second', '--title', 'Second', '--board', '1']);
  assert.equal(taken.status, 1);
  assert.match(taken.stderr, /board row 1 already belongs to the open plan docs\/dflow\/plans\/2026-11-12-meter\.md/);
});

test('init accepts a configuration without gates', t => {
  const root = makeRepo(t);
  write(root, 'docs/dflow/config.json', '{"autoShip": false}');
  const result = dflow(root, ['init']);
  assert.equal(result.status, 0, result.stderr);
  assert.deepEqual(JSON.parse(read(root, 'docs/dflow/config.json')), { autoShip: false, gates: [] });
});

test('darkmem settings left in either config are ignored without a word', t => {
  const root = makeProject(t, { config: { gates: [], darkmem: { project: 'x' } } });
  write(root, '.test-home/.dflow/config.json', JSON.stringify({ darkmem: { url: 'http://127.0.0.1:9', repositories: { [root]: 'x' } } }));
  const state = JSON.parse(read(root, '.dflow/state.json'));
  write(root, '.dflow/state.json', JSON.stringify({ ...state, sync: { enabled: true, queued: 3, conflict: 'board row 1' } }));
  const env = { DARKMEM_API_KEY: 'secret', DFLOW_DARKMEM_URL: 'http://127.0.0.1:9' };
  write(root, 'verify1.mjs', '\n');
  write(root, 'src/limit.mjs', '1\n');
  git(root, 'add', 'src');
  for (const args of [['status'], ['next'], ['done', '1', '-m', 'feat: parse'], ['block', '2', 'waiting'], ['unblock', '2', 'cleared'], ['hook', 'stop'], ['hook', 'session-start'], ['init']]) {
    const result = dflow(root, args, { env, input: '{}' });
    assert.equal(result.status, 0, `${args.join(' ')}: ${result.stderr}`);
    assert.equal(result.stderr, '', args.join(' '));
    assert.doesNotMatch(result.stdout, /darkmem|sync/i, args.join(' '));
  }
  assert.equal(JSON.parse(read(root, '.dflow/hud.json')).sync, undefined);
  assert.deepEqual(JSON.parse(read(root, 'docs/dflow/config.json')).darkmem, { project: 'x' });
});

test('decisions added on two branches merge without a conflict', t => {
  const root = makeRepo(t, { branch: null });
  assert.equal(dflow(root, ['init']).status, 0);
  git(root, 'add', '-A');
  git(root, 'commit', '-q', '-m', 'docs: set up dflow');
  const decide = (branch, text) => {
    git(root, 'switch', '-q', '-c', branch, 'main');
    fs.appendFileSync(path.join(root, 'docs/dflow/decisions.md'), `\n## D-${branch}/1 · 2026-11-12\n\n${text}\n`);
    git(root, 'commit', '-q', '-am', `docs: decide on ${branch}`);
  };
  decide('one', 'the first plan\'s decision');
  decide('two', 'the second plan\'s decision');
  git(root, 'switch', '-q', 'main');
  git(root, 'merge', '-q', '--no-edit', 'one');
  git(root, 'merge', '-q', '--no-edit', 'two');
  const text = read(root, 'docs/dflow/decisions.md');
  assert.match(text, /## D-one\/1/);
  assert.match(text, /## D-two\/1/);
});
