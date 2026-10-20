import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import test from "node:test";
import { startStub } from "./stub-server.mjs";
import { makeHome, makeRepo, run, scratch, write } from "./helpers.mjs";

const LEDGER = "# SDD ledger — plan: docs/superpowers/plans/p1.md\n\nTask 1: implementer (assigned)\nTask 1: complete\n\n\n| a | b |\r\n\r\nTask 2: complete\n";

async function setup(t, stubOptions = {}) {
  const stub = await startStub(stubOptions);
  t.after(() => stub.close());
  const repo = makeRepo();
  const home = makeHome({ repo, url: stub.url });
  write(path.join(repo, "docs", "dforge", "specs", "s.md"), "# Spec\n");
  write(path.join(repo, "docs", "dforge", "plans", "p1.md"), "# P1\n\n**Spec:** `docs/superpowers/specs/s.md`\n");
  write(path.join(repo, ".dforge", "sdd", "p1", "progress.md"), LEDGER);
  write(path.join(repo, ".dforge", "sdd", "p1", "handoff.md"), "# p1 handoff\n");
  write(path.join(repo, ".dforge", "sdd", "brief-only", "task-1-brief.md"), "not synced\n");
  const importing = (...args) => run(["import", ...args], { cwd: repo, env: home.env });
  return { stub, repo, ...home, importing };
}

test("import files every document, closes each ledger as a retained workstream, and verifies it", async t => {
  const s = await setup(t);
  const result = await s.importing();
  assert.equal(result.code, 0, result.stdout + result.stderr);
  assert.match(result.stdout, /note: verified: a pull of every imported file reads back byte-identical/);
  assert.match(result.stdout, /darkmem-sync import: 3 documents, 1 workstreams; 0 conflicts, 0 failures/);
  assert.deepEqual([...s.stub.db.documents.keys()].map(k => k.split("\u0000")[1]).sort(), [
    "dforge/handoff/p1.md", "dforge/plans/p1.md", "dforge/specs/s.md",
  ]);
  const [ws] = s.stub.db.workstreams;
  assert.equal(ws.key, "p1");
  assert.equal(ws.state, "closed");
  assert.equal(ws.retain, true);
  assert.equal(ws.entries.map(e => e.body).join(""), LEDGER);
  assert.deepEqual(ws.entries.map(e => e.body), [
    "# SDD ledger — plan: docs/superpowers/plans/p1.md\n\n",
    "Task 1: implementer (assigned)\nTask 1: complete\n\n",
    "\n",
    "| a | b |\r\n\r\n",
    "Task 2: complete\n",
  ]);
  const mtime = fs.statSync(path.join(s.repo, ".dforge", "sdd", "p1", "progress.md")).mtime.toISOString();
  assert.deepEqual(ws.properties, {
    plan_uri: "dforge/plans/p1.md", spec_uri: "dforge/specs/s.md", handoff_uri: "dforge/handoff/p1.md", imported_mtime: mtime,
  });
});

test("a re-run refuses a workstream darkmem already holds; --replace purges and re-imports it", async t => {
  const s = await setup(t);
  assert.equal((await s.importing()).code, 0);
  const appends = () => s.stub.db.requests.filter(r => r.path === "/api/v1/worklog/entries").length;
  const before = appends();
  const again = await s.importing();
  assert.equal(again.code, 1);
  assert.match(again.stdout, /failed: already in darkmem: p1; run import --replace to purge and re-import them/);
  assert.equal(appends(), before);
  const replaced = await s.importing("--replace");
  assert.equal(replaced.code, 0, replaced.stdout);
  assert.equal(s.stub.db.requests.filter(r => r.method === "DELETE").length, 1);
  assert.equal(s.stub.db.workstreams.length, 1);
  assert.equal(s.stub.db.workstreams[0].entries.length, 5);
});

test("a ledger of more than 100 pieces spans several appends in one workstream", async t => {
  const s = await setup(t);
  const big = Array.from({ length: 250 }, (_, i) => `Task ${i}: complete\n\n`).join("");
  write(path.join(s.repo, ".dforge", "sdd", "p1", "progress.md"), big);
  assert.equal((await s.importing()).code, 0);
  const [ws] = s.stub.db.workstreams;
  assert.equal(ws.entries.length, 250);
  assert.equal(ws.entries.map(e => e.body).join(""), big);
  assert.equal(s.stub.db.requests.filter(r => r.path === "/api/v1/worklog/entries").length, 3);
});

test("the verification fails the import on a single changed byte", async t => {
  const s = await setup(t, { transformContent: content => content.replace("# Spec", "# Spex") });
  const result = await s.importing();
  assert.equal(result.code, 1);
  const failed = /failed: dforge\/specs\/s\.md: a pull of darkmem's copy differs from the source; compare under (\S+)/.exec(result.stdout);
  assert.ok(failed, result.stdout);
  fs.rmSync(failed[1], { recursive: true, force: true });
});

test("a refused document and a refused ledger are reported once, and no scratch copy is kept", async t => {
  const s = await setup(t);
  const tmp = scratch("dms-tmp-");
  s.stub.db.failures.push({ method: "POST", path: "/api/v1/documents", status: 422, detail: "refused" });
  s.stub.db.failures.push({ method: "POST", path: "/api/v1/worklog/entries", status: 422, detail: "refused" });
  const result = await run(["import"], { cwd: s.repo, env: { ...s.env, TMPDIR: tmp, TMP: tmp, TEMP: tmp } });
  assert.equal(result.code, 1, result.stdout);
  assert.equal(result.stdout.match(/darkmem refused/g)?.length, 2, result.stdout);
  assert.match(result.stdout, /^failed: sdd\/p1\/progress\.md: darkmem refused an entry: refused$/m);
  assert.doesNotMatch(result.stdout, /a pull of darkmem's copy differs/);
  assert.deepEqual(fs.readdirSync(tmp).filter(name => name.startsWith("darkmem-import-")), []);
});

test("an empty source file refuses the whole import before any write", async t => {
  const s = await setup(t);
  write(path.join(s.repo, "docs", "dforge", "notes", "empty.md"), "");
  const result = await s.importing();
  assert.equal(result.code, 1);
  assert.match(result.stdout, /failed: .*empty\.md: empty or not UTF-8 text/);
  assert.match(result.stdout, /note: nothing was imported/);
  assert.equal(s.stub.db.requests.filter(r => r.method !== "GET").length, 0);
});

test("--replace purges before any document is written, so a refused purge writes nothing", async t => {
  const s = await setup(t);
  assert.equal((await s.importing()).code, 0);
  const writesBefore = s.stub.db.requests.filter(r => r.method === "POST" && r.path === "/api/v1/documents").length;
  s.stub.db.failures.push({ method: "DELETE", path: "/api/v1/worklog/workstreams/", status: 403, detail: "needs the admin scope" });
  const result = await s.importing("--replace");
  assert.equal(result.code, 3);
  assert.match(result.stderr, /import failed: DELETE .* answered 403: needs the admin scope/);
  assert.equal(s.stub.db.requests.filter(r => r.method === "POST" && r.path === "/api/v1/documents").length, writesBefore);
});

test("a plan directory whose name cannot be a workstream key refuses the import", async t => {
  const s = await setup(t);
  write(path.join(s.repo, ".dforge", "sdd", "bad name", "progress.md"), "x\n");
  const result = await s.importing();
  assert.equal(result.code, 1);
  assert.match(result.stdout, /failed: .*bad name: not a usable workstream key/);
  assert.equal(s.stub.db.requests.filter(r => r.method !== "GET").length, 0);
});

test("a source file changed during the import fails its verification", async t => {
  let repo = null;
  const s = await setup(t, {
    onRequest: request => {
      if (request.method === "GET" && request.path === "/api/v1/documents/by-uri" && repo) write(path.join(repo, "docs", "dforge", "specs", "s.md"), "# Spec, edited mid-import\n");
    },
  });
  repo = s.repo;
  const result = await s.importing();
  assert.equal(result.code, 1, result.stdout + result.stderr);
  assert.match(result.stdout, /failed: the source files changed during the import; run it again with --replace/);
});

test("import in local mode is exit 2", async () => {
  const repo = makeRepo();
  const { env } = makeHome({ repo, config: null, stores: null });
  const result = await run(["import"], { cwd: repo, env });
  assert.equal(result.code, 2);
  assert.match(result.stdout, /^darkmem-sync: local mode/);
});

test("a verified import records documents, never progress, as applied darkmem", async t => {
  const stub = await startStub();
  t.after(() => stub.close());
  const repo = makeRepo();
  const home = makeHome({ repo, url: stub.url, stores: null });
  write(path.join(repo, "docs", "dforge", "specs", "s.md"), "# Spec\n");
  write(path.join(repo, ".dforge", "sdd", "p1", "progress.md"), "# SDD ledger — plan: docs/dforge/plans/p1.md\nTask 1: complete\n");
  const result = await run(["import"], { cwd: repo, env: home.env });
  assert.equal(result.code, 0, result.stdout + result.stderr);
  const record = JSON.parse(fs.readFileSync(path.join(home.home, ".dforge", "stores.json"), "utf8"));
  assert.deepEqual(record, { [repo]: { project: "proj", mirror: home.mirror, documents: "darkmem" } });
  assert.match(result.stdout, /^note: recorded documents as applied darkmem in .*stores\.json$/m);
});

test("an import with documents configured local records nothing", async t => {
  const stub = await startStub();
  t.after(() => stub.close());
  const repo = makeRepo();
  const config = { darkmemEnabled: true, documentStore: "local", darkmem: { url: stub.url, api_key_env: "DARKMEM_API_KEY", repos: { [repo]: { project: "proj" } } } };
  const home = makeHome({ repo, config, stores: null });
  write(path.join(repo, "docs", "dforge", "specs", "s.md"), "# Spec\n");
  write(path.join(repo, ".dforge", "sdd", "p1", "progress.md"), "# SDD ledger — plan: docs/dforge/plans/p1.md\nTask 1: complete\n");
  const result = await run(["import"], { cwd: repo, env: home.env });
  assert.equal(result.code, 0, result.stdout + result.stderr);
  assert.equal(fs.existsSync(path.join(home.home, ".dforge", "stores.json")), false);
});

test("an import with a refused document records nothing", async t => {
  const stub = await startStub();
  t.after(() => stub.close());
  const repo = makeRepo();
  const home = makeHome({ repo, url: stub.url, stores: null });
  write(path.join(repo, "docs", "dforge", "specs", "s.md"), "# Spec\n");
  stub.db.failures.push({ method: "POST", path: "/api/v1/documents", status: 422, detail: "refused" });
  const result = await run(["import"], { cwd: repo, env: home.env });
  assert.equal(result.code, 1, result.stdout);
  assert.equal(fs.existsSync(path.join(home.home, ".dforge", "stores.json")), false);
});
