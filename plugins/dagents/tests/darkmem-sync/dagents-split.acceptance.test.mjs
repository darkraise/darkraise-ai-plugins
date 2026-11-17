// Acceptance test A26 of docs/dforge/specs/2026-11-16-dagents-split-design.md:
// dagents' darkmem namespace.
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import test from "node:test";
import { createClient } from "../../scripts/lib/darkmem-client.mjs";
import { STUB_KEY, sha, startStub } from "./stub-server.mjs";
import { KEY, makeHome, makeRepo, run, scratch, write } from "./helpers.mjs";

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
