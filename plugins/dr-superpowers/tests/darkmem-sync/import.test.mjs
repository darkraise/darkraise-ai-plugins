import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import test from "node:test";
import { startStub } from "./stub-server.mjs";
import { makeHome, makeRepo, run, write } from "./helpers.mjs";

const LEDGER = "# SDD ledger — plan: docs/superpowers/plans/p1.md\n\nTask 1: implementer (assigned)\nTask 1: complete\n\n\n| a | b |\r\n\r\nTask 2: complete\n";

async function setup(t, stubOptions = {}) {
  const stub = await startStub(stubOptions);
  t.after(() => stub.close());
  const repo = makeRepo();
  const home = makeHome({ repo, url: stub.url });
  write(path.join(repo, "docs", "superpowers", "specs", "s.md"), "# Spec\n");
  write(path.join(repo, "docs", "superpowers", "plans", "p1.md"), "# P1\n\n**Spec:** `docs/superpowers/specs/s.md`\n");
  write(path.join(repo, ".superpowers", "sdd", "p1", "progress.md"), LEDGER);
  write(path.join(repo, ".superpowers", "sdd", "p1", "handoff.md"), "# p1 handoff\n");
  write(path.join(repo, ".superpowers", "sdd", "brief-only", "task-1-brief.md"), "not synced\n");
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
    "superpowers/handoff/p1.md", "superpowers/plans/p1.md", "superpowers/specs/s.md",
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
  const mtime = fs.statSync(path.join(s.repo, ".superpowers", "sdd", "p1", "progress.md")).mtime.toISOString();
  assert.deepEqual(ws.properties, {
    plan_uri: "superpowers/plans/p1.md", spec_uri: "superpowers/specs/s.md", handoff_uri: "superpowers/handoff/p1.md", imported_mtime: mtime,
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
  write(path.join(s.repo, ".superpowers", "sdd", "p1", "progress.md"), big);
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
  const failed = /failed: superpowers\/specs\/s\.md: a pull of darkmem's copy differs from the source; compare under (\S+)/.exec(result.stdout);
  assert.ok(failed, result.stdout);
  fs.rmSync(failed[1], { recursive: true, force: true });
});

test("an empty source file refuses the whole import before any write", async t => {
  const s = await setup(t);
  write(path.join(s.repo, "docs", "superpowers", "notes", "empty.md"), "");
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
  write(path.join(s.repo, ".superpowers", "sdd", "bad name", "progress.md"), "x\n");
  const result = await s.importing();
  assert.equal(result.code, 1);
  assert.match(result.stdout, /failed: .*bad name: not a usable workstream key/);
  assert.equal(s.stub.db.requests.filter(r => r.method !== "GET").length, 0);
});

test("a source file changed during the import fails its verification", async t => {
  let repo = null;
  const s = await setup(t, {
    onRequest: request => {
      if (request.method === "PATCH" && repo) write(path.join(repo, "docs", "superpowers", "specs", "s.md"), "# Spec, edited mid-import\n");
    },
  });
  repo = s.repo;
  const result = await s.importing();
  assert.equal(result.code, 1);
  assert.match(result.stdout, /failed: the source files changed during the import; run it again with --replace/);
});

test("import in local mode is exit 2", async () => {
  const repo = makeRepo();
  const { env } = makeHome({ repo, config: null });
  const result = await run(["import"], { cwd: repo, env });
  assert.equal(result.code, 2);
  assert.match(result.stdout, /^darkmem-sync: local mode/);
});
