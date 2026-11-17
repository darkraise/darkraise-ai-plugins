// Acceptance tests A13 and A26 of docs/dforge/specs/2026-11-16-dagents-split-design.md:
// dagents' darkmem namespace, and migrating a darkmem-applied dforge 4.x project.
import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";
import { createClient } from "../../../plugins/dagents/scripts/lib/darkmem-client.mjs";
import { STUB_KEY, sha, startStub } from "./stub-server.mjs";
import { KEY, makeHome, makeRepo, run, scratch, write } from "./helpers.mjs";

const MIGRATE = fileURLToPath(new URL("../../../plugins/dagents/scripts/dagents-migrate", import.meta.url));
const PROJECT = "proj";
const DOCS = {
  "dforge/specs/a.md": "# A\n",
  "dforge/plans/b.md": "# B plan\n\nbody\n",
  "dforge/archive/20260101T000000Z/old.md": "old\n",
};

function clean(env) {
  const out = { ...env };
  for (const name of Object.keys(out)) {
    if (/^(DFORGE_|DAGENTS_(?!SESSION_ID|DARKMEM)|WORKFLOW_GUARD_)/.test(name) || name === "CLAUDE_CONFIG_DIR" || name === "CLAUDE_CODE_SESSION_ID" || name === "NODE_TEST_CONTEXT") delete out[name];
  }
  return out;
}
const execBash = (args, { cwd, env }) => new Promise(resolve => {
  execFile("bash", args, { cwd, env, timeout: 60000 }, (error, stdout, stderr) => resolve({ code: error ? (typeof error.code === "number" ? error.code : -1) : 0, stdout, stderr }));
});

// A 4.x project whose documents live in darkmem: dforge's home config, record
// and mirror, the project's documents and two bare-key workstreams on the stub.
async function dforgeProject(t) {
  const stub = await startStub();
  t.after(() => stub.close());
  const repo = makeRepo();
  fs.mkdirSync(path.join(repo, ".dforge"));
  const home = scratch("dsplit-home-");
  const dforgeHome = path.join(home, ".dforge");
  const mirror = path.join(dforgeHome, "mirror", PROJECT);
  write(path.join(dforgeHome, "config.json"), JSON.stringify({ darkmemEnabled: true, handoffTokens: 4242, darkmem: { url: stub.url, api_key_env: "DARKMEM_API_KEY", repos: { [repo]: { project: PROJECT } } } }));
  write(path.join(dforgeHome, "stores.json"), JSON.stringify({ [repo]: { project: PROJECT, mirror, documents: "darkmem", progress: "darkmem" } }));
  const seed = createClient({ url: stub.url, apiKey: STUB_KEY, runKey: "seed" });
  const documents = {};
  for (const [uri, content] of Object.entries(DOCS)) {
    await seed.putDocument({ project: PROJECT, uri, content });
    documents[uri] = sha(content);
    if (!uri.includes("/archive/")) write(path.join(mirror, ...uri.split("/")), content);
  }
  await seed.putDocument({ project: PROJECT, uri: "notes/unrelated.md", content: "unrelated\n" });
  write(path.join(mirror, ".sync-state.json"), JSON.stringify({ version: 1, documents: Object.fromEntries(Object.entries(documents).filter(([uri]) => !uri.includes("/archive/"))), ledgers: {}, checkpoint: null, checkpointAt: null, conflicts: [], pendingLinks: [], prefix: "dforge" }));
  await seed.append({ project: PROJECT, workstream: "plan-one", entries: [{ kind: "ledger", body: "Task 1: complete\n" }, { kind: "ledger", body: "Task 2: complete\n" }] });
  await seed.append({ project: PROJECT, workstream: "plan-two", entries: [{ kind: "checkpoint", body: "checkpoint\n" }] });
  const env = clean({ ...process.env, HOME: home, DARKMEM_API_KEY: KEY, DAGENTS_SESSION_ID: "acc-1", DAGENTS_DARKMEM_SYNC_TIMEOUT_MS: "3000" });
  return { stub, repo, home, mirror, env, seed };
}
const dforgeData = db => JSON.stringify({
  documents: [...db.documents.entries()].filter(([key]) => key.split("\u0000")[1].startsWith("dforge/")).sort(),
  workstreams: db.workstreams.filter(ws => !ws.key.includes("/")).map(ws => ({ key: ws.key, state: ws.state, entries: ws.entries.map(entry => [entry.kind, entry.body]) })).sort((a, b) => a.key.localeCompare(b.key)),
});
const writes = (db, from = 0) => db.requests.slice(from).filter(request => ["POST", "PUT", "PATCH", "DELETE"].includes(request.method));

test("A13: migrating a darkmem project copies its dforge/ documents and workstreams, reads each copy back, deletes nothing, and prints the deletion command", async t => {
  const s = await dforgeProject(t);
  const before = dforgeData(s.stub.db);
  const result = await execBash([MIGRATE], { cwd: s.repo, env: s.env });
  assert.equal(result.code, 0, result.stdout + result.stderr);
  const { db } = s.stub;
  for (const [uri, content] of Object.entries(DOCS)) {
    const copy = db.documents.get(`${PROJECT}\u0000dagents/${uri.slice("dforge/".length)}`);
    assert.ok(copy, `no dagents copy of ${uri}`);
    assert.equal(copy.content, content, `${uri} copy differs`);
    assert.ok(db.documents.has(`${PROJECT}\u0000${uri}`), `${uri} was deleted`);
  }
  assert.ok(db.documents.has(`${PROJECT}\u0000notes/unrelated.md`));
  for (const key of ["plan-one", "plan-two"]) {
    const original = db.workstreams.find(ws => ws.key === key);
    const copy = db.workstreams.find(ws => ws.key === `dagents/${key}`);
    assert.ok(original, `workstream ${key} was deleted`);
    assert.ok(copy, `no dagents/${key} workstream`);
    assert.deepEqual(copy.entries.map(entry => [entry.kind, entry.body]), original.entries.map(entry => [entry.kind, entry.body]));
  }
  assert.equal(dforgeData(db), before, "the dforge originals changed");
  assert.deepEqual(db.requests.filter(request => request.method === "DELETE"), [], "a DELETE was sent");
  // Each copy is read back: a by-uri read of the dagents uri follows its write.
  for (const uri of Object.keys(DOCS)) {
    const target = `dagents/${uri.slice("dforge/".length)}`;
    const written = db.requests.findIndex(request => request.method === "POST" && request.path === "/api/v1/documents" && request.body?.uri === target);
    const readBack = db.requests.findIndex((request, index) => index > written && request.method === "GET" && request.path === "/api/v1/documents/by-uri" && request.query.uri === target && request.query.include_content === "true");
    assert.ok(written >= 0 && readBack > written, `${target} was not read back after it was written`);
  }
  for (const key of ["plan-one", "plan-two"]) {
    const target = `dagents/${key}`;
    const copy = db.workstreams.find(ws => ws.key === target);
    const written = db.requests.findIndex(request => request.method === "POST" && request.body?.workstream === target);
    const readBack = db.requests.findIndex((request, index) => index > written && request.method === "GET" && request.path === `/api/v1/worklog/workstreams/${copy.id}/entries`);
    assert.ok(written >= 0 && readBack > written, `${target}'s entries were not read back`);
  }
  assert.match(result.stdout, /document_delete_subtree/);
  assert.match(result.stdout, /uri_prefix dforge\//);
  assert.match(result.stdout, /worklog_purge/);
  assert.match(result.stdout, /plan-one/);
  assert.match(result.stdout, /plan-two/);
  assert.match(result.stdout, /copied.* not deleted/);
});

test("A26: a dagents push and pull request only the dagents client and dagents/ names, leaving dforge/ data untouched", { skip: "deferred: docs/dforge/registers/2026-11-16-dagents-split.md row 10 (it counts the 4.17.1 superpowers/ and forge/ server move as outside dagents)" }, async t => {
  const stub = await startStub();
  t.after(() => stub.close());
  const repo = makeRepo();
  const home = makeHome({ repo, url: stub.url, project: PROJECT });
  const env = clean({ ...home.env, DAGENTS_SESSION_ID: "acc-2" });
  const seed = createClient({ url: stub.url, apiKey: STUB_KEY, runKey: "seed" });
  for (const [uri, content] of Object.entries(DOCS)) await seed.putDocument({ project: PROJECT, uri, content });
  await seed.putDocument({ project: PROJECT, uri: "dagents/specs/remote.md", content: "remote\n" });
  await seed.append({ project: PROJECT, workstream: "plan-one", entries: [{ kind: "ledger", body: "Task 1: complete\n" }] });
  const before = dforgeData(stub.db);
  const start = stub.db.requests.length;
  write(path.join(home.docsRoot, "specs", "local.md"), "local\n");
  write(path.join(home.workRoot, "sdd", "demo-plan", "progress.md"), "# SDD ledger — plan: docs/dagents/plans/demo-plan.md\nTask 1: complete (x)\n");
  for (const command of ["pull", "push", "pull"]) {
    const result = await run([command], { cwd: repo, env });
    assert.equal(result.code, 0, `${command}: ${result.stdout}${result.stderr}`);
  }
  const mine = stub.db.requests.slice(start);
  assert.ok(mine.length > 5, "the sync made requests");
  const outside = [];
  for (const request of mine) {
    if (request.headers["x-darkmem-client"] !== "dagents") outside.push(`${request.method} ${request.path}: client ${request.headers["x-darkmem-client"]}`);
    for (const name of ["uri", "uri_prefix"]) {
      const value = request.query[name];
      if (value !== undefined && !/^dagents(\/|$)/.test(value)) outside.push(`${request.method} ${request.path}?${name}=${value}`);
    }
    if (request.query.workstream !== undefined && !/^dagents\//.test(request.query.workstream)) outside.push(`${request.path} workstream=${request.query.workstream}`);
    if (request.body?.uri !== undefined && !/^dagents\//.test(request.body.uri)) outside.push(`${request.path} body uri ${request.body.uri}`);
    if (request.body?.workstream !== undefined && !/^dagents\//.test(request.body.workstream)) outside.push(`${request.path} body workstream ${request.body.workstream}`);
  }
  assert.deepEqual([...new Set(outside)], [], "requests outside the dagents client and dagents/ names");
  assert.ok(stub.db.documents.has(`${PROJECT}\u0000dagents/specs/local.md`), "the local document was pushed under dagents/");
  assert.ok(stub.db.workstreams.some(ws => ws.key.startsWith("dagents/") && ws.entries.length > 0), "the ledger went to a dagents/ workstream");
  assert.equal(dforgeData(stub.db), before, "dforge/ data changed");
  assert.deepEqual(mine.filter(request => request.method === "DELETE"), []);
});

test("A26: the first dagents sync after migrating a darkmem-applied project deletes nothing and re-uploads nothing", async t => {
  const s = await dforgeProject(t);
  const migrated = await execBash([MIGRATE], { cwd: s.repo, env: s.env });
  assert.equal(migrated.code, 0, migrated.stdout + migrated.stderr);
  const state = JSON.parse(fs.readFileSync(path.join(s.home, ".dagents", "mirror", PROJECT, ".sync-state.json"), "utf8"));
  assert.ok(Object.keys(state.documents).length > 0 && Object.keys(state.documents).every(uri => uri.startsWith("dagents/")), "the mirror's state names dagents/ uris");
  const start = s.stub.db.requests.length;
  const documents = JSON.stringify([...s.stub.db.documents.entries()].map(([key, doc]) => [key, doc.content_hash]).sort());
  const workstreams = JSON.stringify(s.stub.db.workstreams.map(ws => [ws.key, ws.entries.length]).sort());
  for (const command of ["pull", "push"]) {
    const result = await run([command], { cwd: s.repo, env: s.env });
    assert.equal(result.code, 0, `${command}: ${result.stdout}${result.stderr}`);
  }
  assert.ok(s.stub.db.requests.length > start, "the sync reached the server");
  assert.deepEqual(writes(s.stub.db, start), [], "the first sync wrote or deleted something");
  assert.equal(JSON.stringify([...s.stub.db.documents.entries()].map(([key, doc]) => [key, doc.content_hash]).sort()), documents);
  assert.equal(JSON.stringify(s.stub.db.workstreams.map(ws => [ws.key, ws.entries.length]).sort()), workstreams);
});

test("A26: no dagents sync request names dforge/ or a bare workstream key", async t => {
  const stub = await startStub();
  t.after(() => stub.close());
  const repo = makeRepo();
  const home = makeHome({ repo, url: stub.url, project: PROJECT });
  const env = clean({ ...home.env, DAGENTS_SESSION_ID: "acc-3" });
  const seed = createClient({ url: stub.url, apiKey: STUB_KEY, runKey: "seed" });
  for (const [uri, content] of Object.entries(DOCS)) await seed.putDocument({ project: PROJECT, uri, content });
  await seed.append({ project: PROJECT, workstream: "plan-one", entries: [{ kind: "ledger", body: "Task 1: complete\n" }] });
  write(path.join(home.workRoot, "sdd", "demo-plan", "progress.md"), "# SDD ledger — plan: docs/dagents/plans/demo-plan.md\nTask 1: complete (x)\n");
  const start = stub.db.requests.length;
  for (const command of ["pull", "push", "reconcile"]) await run([command], { cwd: repo, env });
  const named = stub.db.requests.slice(start).filter(request => /dforge|plan-one/.test(JSON.stringify([request.query, request.body])));
  assert.deepEqual(named.map(request => `${request.method} ${request.path}`), []);
});
