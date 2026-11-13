import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import http from 'node:http';
import test from 'node:test';
import { parseBoard, rewriteRow } from '../lib/board.mjs';
import { dflow, dflowAsync, git, makeProject, read, write } from './helpers.mjs';

const hash = text => createHash('sha256').update(text).digest('hex').slice(0, 16);

// A stand-in for the darkmem routes dflow uses, with the same conflict codes.
async function stub(t) {
  const server = { documents: new Map(), entries: [], closed: [], requests: [], blockFirst: new Set() };
  const listener = http.createServer((request, response) => {
    let raw = '';
    request.on('data', chunk => { raw += chunk; });
    request.on('end', () => {
      const url = new URL(request.url, 'http://x');
      const body = raw ? JSON.parse(raw) : null;
      server.requests.push(`${request.method} ${url.pathname}`);
      const send = (status, value) => {
        response.writeHead(status, { 'Content-Type': 'application/json' });
        response.end(JSON.stringify(value));
      };
      if (request.headers.authorization !== 'Bearer secret' || request.headers['x-darkmem-client'] !== 'dflow') return send(401, { detail: 'bad key' });
      const byId = id => [...server.documents.values()].find(document => document.document_id === id);
      const row = /^\/api\/v1\/board\/registers\/([^/]+)\/rows\/(\d+)$/.exec(url.pathname);
      if (request.method === 'POST' && url.pathname === '/api/v1/documents') {
        const current = server.documents.get(body.uri);
        if (body.expected_hash && current && current.content_hash !== body.expected_hash) return send(409, { detail: 'hash mismatch' });
        if (server.blockFirst.has(body.uri)) return send(409, { detail: 'document is block-first' });
        const document = { document_id: current?.document_id ?? `doc-${server.documents.size + 1}`, uri: body.uri, content: body.content, content_hash: hash(body.content) };
        server.documents.set(body.uri, document);
        if (server.dropNextAnswer) {
          server.dropNextAnswer = false;
          return response.destroy();
        }
        return send(200, document);
      }
      if (request.method === 'GET' && url.pathname === '/api/v1/documents/by-uri') {
        const document = server.documents.get(url.searchParams.get('uri'));
        return document ? send(200, document) : send(404, { detail: 'no document is filed at uri' });
      }
      if (request.method === 'PATCH' && row) {
        if (server.rowsNeedLogin) return send(401, { detail: 'login required' });
        const document = byId(row[1]);
        if (!document) return send(422, { detail: 'invalid document id' });
        if (document.content_hash !== body.expected_hash) return send(409, { detail: 'hash_conflict' });
        const { expected_hash: _, ...changes } = body;
        document.content = rewriteRow(document.content, Number(row[2]), changes);
        document.content_hash = hash(document.content);
        return send(200, { document_id: document.document_id, content_hash: document.content_hash });
      }
      if (request.method === 'POST' && url.pathname === '/api/v1/worklog/entries') {
        for (const entry of body.entries) server.entries.push({ workstream: body.workstream, run_key: body.run_key, plan_uri: body.properties.plan_uri, ...entry });
        if (server.dropNextAppendAnswer) {
          server.dropNextAppendAnswer = false;
          return response.destroy();
        }
        return send(201, { last_seq: server.entries.length });
      }
      if (request.method === 'GET' && url.pathname === '/api/v1/worklog/resume') {
        return send(200, { workstream: { id: 'ws-1' }, ledger: server.entries.filter(entry => entry.kind === 'ledger' && entry.workstream === url.searchParams.get('workstream')).slice(-20) });
      }
      if (request.method === 'PATCH' && url.pathname === '/api/v1/worklog/workstreams/ws-1') {
        server.closed.push(body.state);
        return send(200, {});
      }
      return send(404, { detail: 'no route' });
    });
  });
  await new Promise(resolve => listener.listen(0, '127.0.0.1', resolve));
  t.after(() => new Promise(resolve => listener.close(resolve)));
  server.env = { DFLOW_DARKMEM_URL: `http://127.0.0.1:${listener.address().port}`, DARKMEM_API_KEY: 'secret' };
  return server;
}

const CONFIG = { darkmem: { project: 'fixture' } };

// A project mapped to darkmem and enabled by the user, as `dflow init
// --darkmem` or `dflow sync enable` leaves it.
function enabled(t) {
  const root = makeProject(t, { config: CONFIG });
  assert.equal(dflow(root, ['sync', 'enable']).status, 0);
  return root;
}

function finishTask1(root) {
  write(root, 'verify1.mjs', '\n');
  write(root, 'src/limit.mjs', '1\n');
  git(root, 'add', 'src');
}

test('with no project, URL or key every sync command exits 0 with one line', async t => {
  const root = makeProject(t);
  assert.match(dflow(root, ['sync', 'push']).stdout, /^darkmem is off: the repository names no darkmem project/);
  const mapped = makeProject(t, { config: CONFIG });
  assert.match(dflow(mapped, ['sync', 'status']).stdout, /^darkmem is off: no darkmem URL is configured/);
  const keyless = dflow(mapped, ['sync', 'pull'], { env: { DFLOW_DARKMEM_URL: 'http://127.0.0.1:1', DARKMEM_API_KEY: '' } });
  assert.deepEqual([keyless.status, keyless.stdout.trim()], [0, 'darkmem is off: the API key variable DARKMEM_API_KEY is not set']);
  // The repository names a project; only the user's consent turns it on.
  const env = { DFLOW_DARKMEM_URL: 'http://127.0.0.1:1', DARKMEM_API_KEY: 'secret' };
  assert.equal(dflow(mapped, ['sync', 'push'], { env }).stdout.trim(), 'darkmem is off: not enabled for this repository; `dflow sync enable` sends its docs to project "fixture"');
  assert.match(dflow(mapped, ['sync', 'enable']).stdout, /^darkmem enabled for .+: its docs go to project "fixture"$/m);
  assert.match(dflow(mapped, ['sync', 'status'], { env }).stdout, /^darkmem project fixture at http:\/\/127\.0\.0\.1:1/);
  write(mapped, 'docs/dflow/config.json', JSON.stringify({ darkmem: { project: 'someone-else' } }));
  assert.match(dflow(mapped, ['sync', 'status'], { env }).stdout, /this repository now names project "someone-else", but you enabled "fixture" for it/);
  write(mapped, 'docs/dflow/config.json', JSON.stringify(CONFIG));
  assert.equal(dflow(mapped, ['sync', 'disable']).status, 0);
  assert.match(dflow(mapped, ['sync', 'status'], { env }).stdout, /not enabled for this repository/);
  finishTask1(mapped);
  assert.equal(dflow(mapped, ['done', '1', '-m', 'feat: parse']).status, 0);
});

test('on the default branch push files every document by hash, once', async t => {
  const server = await stub(t);
  const root = enabled(t);
  git(root, 'switch', '-q', 'main');
  const first = await dflowAsync(root, ['sync', 'push'], { env: server.env });
  assert.equal(first.status, 0, first.stdout + first.stderr);
  assert.deepEqual([...server.documents.keys()].sort(), ['dflow/board.md', 'dflow/decisions.md', 'dflow/gotchas.md', 'dflow/project.md']);
  assert.equal(server.documents.get('dflow/board.md').content, read(root, 'docs/dflow/board.md'));

  const posts = server.requests.filter(request => request.startsWith('POST /api/v1/documents')).length;
  const second = await dflowAsync(root, ['sync', 'push'], { env: server.env });
  assert.match(second.stdout, /darkmem push: nothing to do/);
  assert.equal(server.requests.filter(request => request.startsWith('POST /api/v1/documents')).length, posts);
});

test('on a plan branch push sends the plan, its board row and the task transitions', async t => {
  const server = await stub(t);
  const root = enabled(t);
  git(root, 'switch', '-q', 'main');
  await dflowAsync(root, ['sync', 'push'], { env: server.env });
  git(root, 'switch', '-q', 'feat/x');

  finishTask1(root);
  const done = await dflowAsync(root, ['done', '1', '-m', 'feat: parse'], { env: server.env });
  assert.equal(done.status, 0, done.stderr);
  assert.ok(server.documents.has('dflow/plans/2026-11-12-meter.md'));
  const row = parseBoard(server.documents.get('dflow/board.md').content).rows[0];
  assert.deepEqual([row.state, row.assigned], ['doing', 'docs/dflow/plans/2026-11-12-meter.md']);
  assert.ok(!server.requests.slice(server.requests.lastIndexOf('POST /api/v1/documents')).includes('POST /api/v1/documents', 1), 'the whole board is not re-filed from a plan branch');

  const ledger = server.entries.filter(entry => entry.kind === 'ledger');
  assert.deepEqual(ledger.map(entry => [entry.properties.task ?? null, entry.properties.state ?? null]), [[null, null], [1, 'done'], [2, 'wip']]);
  assert.match(ledger[1].properties.commit, /^[0-9a-f]{40}$/);
  assert.deepEqual([ledger[1].workstream, ledger[1].plan_uri], ['2026-11-12-meter', 'dflow/plans/2026-11-12-meter.md']);

  await dflowAsync(root, ['block', '2', 'the design is undecided'], { env: server.env });
  const blocked = server.entries.at(-1);
  assert.deepEqual([blocked.body, blocked.properties.task, blocked.properties.state], ['the design is undecided', 2, 'blocked']);
  assert.match(blocked.properties.event_id, /^[0-9a-f]{16}$/);

  await dflowAsync(root, ['hook', 'stop'], { env: server.env });
  await dflowAsync(root, ['hook', 'stop'], { env: server.env });
  const checkpoints = server.entries.filter(entry => entry.kind === 'checkpoint');
  assert.equal(checkpoints.length, 1);
  assert.match(checkpoints[0].body, /^1\/2 tasks done · no task ready · feat\/x @ [0-9a-f]{7}$/);
});

test('a row edited on darkmem is pulled on the default branch; a two-sided change is reported and kept', async t => {
  const server = await stub(t);
  const root = enabled(t);
  git(root, 'switch', '-q', 'main');
  await dflowAsync(root, ['sync', 'push'], { env: server.env });
  const remote = server.documents.get('dflow/board.md');
  const edit = (state, note) => {
    remote.content = rewriteRow(remote.content, 1, { state, note });
    remote.content_hash = hash(remote.content);
  };

  edit('deferred', 'waiting for the vendor');
  const pulled = await dflowAsync(root, ['hook', 'session-start'], { env: server.env });
  assert.equal(pulled.status, 0);
  assert.deepEqual(parseBoard(read(root, 'docs/dflow/board.md')).rows.map(row => [row.state, row.note]), [['deferred', 'waiting for the vendor']]);

  edit('open', '-');
  write(root, 'docs/dflow/board.md', rewriteRow(read(root, 'docs/dflow/board.md'), 1, { note: 'edited locally' }));
  const conflict = await dflowAsync(root, ['sync', 'pull'], { env: server.env });
  assert.equal(conflict.status, 1);
  assert.match(conflict.stdout, /darkmem conflict: dflow\/board\.md changed on darkmem and in the repository; nothing was overwritten/);
  assert.equal(parseBoard(read(root, 'docs/dflow/board.md')).rows[0].note, 'edited locally');
  const pushed = await dflowAsync(root, ['sync', 'push'], { env: server.env });
  assert.match(pushed.stdout, /darkmem conflict: dflow\/board\.md changed on darkmem and in the repository/);
  assert.equal(parseBoard(remote.content).rows[0].state, 'open');
});

test('an unreachable server leaves the work queued and does not fail the build', async t => {
  const root = enabled(t);
  const env = { DFLOW_DARKMEM_URL: 'http://127.0.0.1:9', DARKMEM_API_KEY: 'secret' };
  finishTask1(root);
  const done = await dflowAsync(root, ['done', '1', '-m', 'feat: parse'], { env });
  assert.equal(done.status, 0, done.stderr);
  assert.match(done.stdout, /^Task 1 done/);
  const status = JSON.parse(dflow(root, ['status', '--json']).stdout);
  assert.equal(status.sync.enabled, true);
  assert.ok(status.sync.queued >= 2);
  const push = await dflowAsync(root, ['sync', 'push'], { env });
  assert.equal(push.status, 1);
  assert.match(push.stdout, /darkmem push stopped: .*What was not sent stays queued/);
});

test('a board row the server refuses does not hold back the plan or the work log', async t => {
  const server = await stub(t);
  const root = enabled(t);
  git(root, 'switch', '-q', 'main');
  await dflowAsync(root, ['sync', 'push'], { env: server.env });
  git(root, 'switch', '-q', 'feat/x');
  server.rowsNeedLogin = true;
  finishTask1(root);
  await dflowAsync(root, ['done', '1', '-m', 'feat: parse'], { env: server.env });
  assert.ok(server.entries.some(entry => entry.properties.task === 1 && entry.properties.state === 'done'));
  assert.ok(server.documents.has('dflow/plans/2026-11-12-meter.md'));
  const push = await dflowAsync(root, ['sync', 'push'], { env: server.env });
  assert.equal(push.status, 1);
  assert.match(push.stdout, /darkmem refused board row 1: PATCH .* answered 401/);
  assert.equal(JSON.parse(dflow(root, ['status', '--json']).stdout).sync.refused, 1);
});

test('an answer lost after the server filed it does not file the entry or flag the board twice', async t => {
  const server = await stub(t);
  const root = enabled(t);
  git(root, 'switch', '-q', 'main');
  await dflowAsync(root, ['sync', 'push'], { env: server.env });
  write(root, 'docs/dflow/board.md', rewriteRow(read(root, 'docs/dflow/board.md'), 1, { note: 'edited locally' }));
  server.dropNextAnswer = true;
  assert.equal((await dflowAsync(root, ['sync', 'push'], { env: server.env })).status, 1);
  const again = await dflowAsync(root, ['sync', 'push'], { env: server.env });
  assert.equal(again.status, 0, again.stdout);
  assert.doesNotMatch(again.stdout, /conflict/);

  git(root, 'commit', '-q', '-am', 'docs: note');
  git(root, 'switch', '-q', 'feat/x');
  finishTask1(root);
  server.dropNextAppendAnswer = true;
  await dflowAsync(root, ['done', '1', '-m', 'feat: parse'], { env: server.env });
  await dflowAsync(root, ['sync', 'push'], { env: server.env });
  const bodies = server.entries.filter(entry => entry.kind === 'ledger').map(entry => entry.body);
  assert.equal(new Set(bodies).size, bodies.length, bodies.join(' | '));
  assert.ok(bodies.some(body => /^Task 1: complete/.test(body)));
});

test('a document the server refuses is skipped until it changes, and the rest goes through', async t => {
  const server = await stub(t);
  const root = enabled(t);
  git(root, 'switch', '-q', 'main');
  server.blockFirst.add('dflow/decisions.md');
  const push = await dflowAsync(root, ['sync', 'push'], { env: server.env });
  assert.match(push.stdout, /darkmem refused dflow\/decisions\.md/);
  assert.ok(server.documents.has('dflow/project.md'));
  const posts = server.requests.length;
  const again = await dflowAsync(root, ['sync', 'push'], { env: server.env });
  assert.equal(again.status, 0, again.stdout);
  assert.equal(server.requests.length, posts, 'the refused document is not sent again unchanged');
});

test('two pushes at once do not send the queued entries twice', async t => {
  const server = await stub(t);
  const root = enabled(t);
  finishTask1(root);
  const off = { DFLOW_DARKMEM_URL: 'http://127.0.0.1:9', DARKMEM_API_KEY: 'secret' };
  await dflowAsync(root, ['done', '1', '-m', 'feat: parse'], { env: off });
  await Promise.all(Array.from({ length: 4 }, () => dflowAsync(root, ['sync', 'push'], { env: server.env })));
  const bodies = server.entries.filter(entry => entry.kind === 'ledger').map(entry => entry.body);
  assert.ok(bodies.length >= 2);
  assert.equal(new Set(bodies).size, bodies.length, bodies.join(' | '));
});
