import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import test from "node:test";
import { createClient } from "../../scripts/lib/darkmem-client.mjs";
import { STUB_KEY, sha, startStub } from "./stub-server.mjs";
import { makeHome, makeRepo, read, run, write } from "./helpers.mjs";

async function setup(t, stubOptions = {}) {
  const stub = await startStub(stubOptions);
  t.after(() => stub.close());
  const repo = makeRepo();
  const home = makeHome({ repo, url: stub.url });
  const seed = createClient({ url: stub.url, apiKey: STUB_KEY, runKey: "seed" });
  const state = () => JSON.parse(fs.readFileSync(path.join(home.mirror, ".sync-state.json"), "utf8"));
  return { stub, repo, ...home, seed, state, pull: () => run(["pull"], { cwd: repo, env: home.env }) };
}

const fetches = stub => stub.db.requests.filter(r => r.path === "/api/v1/documents/by-uri").length;

test("pull writes documents and handoff notes under the prefix, and records their hashes", async t => {
  const s = await setup(t);
  await s.seed.putDocument({ project: "proj", uri: "superpowers/specs/a.md", content: "# A\n" });
  await s.seed.putDocument({ project: "proj", uri: "superpowers/handoff/p1.md", content: "# Handoff\n" });
  await s.seed.putDocument({ project: "proj", uri: "other/x.md", content: "x" });
  await s.seed.putDocument({ project: "else", uri: "superpowers/specs/b.md", content: "b" });
  const result = await s.pull();
  assert.equal(result.code, 0, result.stdout + result.stderr);
  assert.match(result.stdout, /darkmem-sync pull: 2 documents, 0 ledgers, 0 checkpoints; 0 conflicts, 0 failures/);
  assert.equal(read(path.join(s.docsRoot, "specs", "a.md")), "# A\n");
  assert.equal(read(path.join(s.workRoot, "sdd", "p1", "handoff.md")), "# Handoff\n");
  assert.equal(fs.existsSync(path.join(s.docsRoot, "..", "other")), false);
  assert.deepEqual(s.state().documents, { "superpowers/specs/a.md": sha("# A\n"), "superpowers/handoff/p1.md": sha("# Handoff\n") });
  const before = fetches(s.stub);
  assert.equal((await s.pull()).code, 0);
  assert.equal(fetches(s.stub), before, "an unchanged manifest fetches nothing");
});

test("a document changed on darkmem replaces an unchanged local copy", async t => {
  const s = await setup(t);
  await s.seed.putDocument({ project: "proj", uri: "superpowers/a.md", content: "one\n" });
  await s.pull();
  await s.seed.putDocument({ project: "proj", uri: "superpowers/a.md", content: "two\n" });
  assert.equal((await s.pull()).code, 0);
  assert.equal(read(path.join(s.docsRoot, "a.md")), "two\n");
});

test("a document changed on both sides is a conflict and the local copy stays", async t => {
  const s = await setup(t);
  await s.seed.putDocument({ project: "proj", uri: "superpowers/a.md", content: "one\n" });
  await s.pull();
  write(path.join(s.docsRoot, "a.md"), "local\n");
  const localOnly = await s.pull();
  assert.equal(localOnly.code, 0, "an edit darkmem has not moved past is push's to send");
  assert.doesNotMatch(localOnly.stdout, /^conflict:/m);
  assert.equal(read(path.join(s.docsRoot, "a.md")), "local\n");
  await s.seed.putDocument({ project: "proj", uri: "superpowers/a.md", content: "remote\n" });
  const result = await s.pull();
  assert.equal(result.code, 1);
  assert.match(result.stdout, /^conflict: superpowers\/a\.md: changed locally and on darkmem; move the local file aside/m);
  assert.equal(read(path.join(s.docsRoot, "a.md")), "local\n");
  assert.equal(s.state().conflicts.length, 1);
  const status = await run(["status"], { cwd: s.repo, env: s.env });
  assert.match(status.stdout, /^conflict: superpowers\/a\.md/m);
});

test("open workstreams render their ledgers; closed ones do not", async t => {
  const s = await setup(t);
  await s.seed.append({ project: "proj", workstream: "p1", entries: [{ kind: "ledger", body: "# SDD ledger — plan: x\n" }, { kind: "ledger", body: "Task 1: a\n\n| t |\n" }] });
  await s.seed.append({ project: "proj", workstream: "p1", entries: [{ kind: "ledger", body: "Task 2: b\n" }, { kind: "note", body: "not a ledger line" }] });
  const { workstream } = await s.seed.append({ project: "proj", workstream: "done", entries: [{ kind: "ledger", body: "old\n" }] });
  await s.seed.updateWorkstream(workstream.id, { state: "closed" });
  assert.equal((await s.pull()).code, 0);
  const file = path.join(s.workRoot, "sdd", "p1", "progress.md");
  assert.equal(read(file), "# SDD ledger — plan: x\nTask 1: a\n\n| t |\nTask 2: b\n");
  assert.equal(fs.existsSync(path.join(s.workRoot, "sdd", "done")), false);
  assert.deepEqual(s.state().ledgers.p1, { offset: fs.statSync(file).size, prefix: sha(read(file)) });
});

test("a ledger ahead locally is kept; a diverged one is a conflict", async t => {
  const s = await setup(t);
  await s.seed.append({ project: "proj", workstream: "p1", entries: [{ kind: "ledger", body: "one\n" }] });
  await s.pull();
  const file = path.join(s.workRoot, "sdd", "p1", "progress.md");
  fs.appendFileSync(file, "two\n");
  assert.equal((await s.pull()).code, 0);
  assert.equal(read(file), "one\ntwo\n");
  await s.seed.append({ project: "proj", workstream: "p1", entries: [{ kind: "ledger", body: "three\n" }] });
  const result = await s.pull();
  assert.equal(result.code, 1);
  assert.match(result.stdout, /conflict: sdd\/p1\/progress\.md: the local ledger and darkmem's have diverged/);
  assert.equal(read(file), "one\ntwo\n");
});

test("latest.md takes the newest checkpoint across open workstreams, by darkmem's clock", async t => {
  const s = await setup(t);
  await s.seed.append({ project: "proj", workstream: "p1", entries: [{ kind: "checkpoint", body: "# older\n" }] });
  await s.seed.append({ project: "proj", workstream: "p2", entries: [{ kind: "checkpoint", body: "# newest\n" }] });
  assert.equal((await s.pull()).code, 0);
  const latest = path.join(s.workRoot, "handoff", "latest.md");
  assert.equal(read(latest), "# newest\n");
  const future = new Date(Date.now() + 24 * 60 * 60 * 1000);
  fs.utimesSync(latest, future, future);
  await s.seed.append({ project: "proj", workstream: "p1", entries: [{ kind: "checkpoint", body: "# later still\n" }] });
  assert.equal((await s.pull()).code, 0);
  assert.equal(read(latest), "# later still\n", "a file's mtime never hides a newer checkpoint");
  assert.equal(s.state().checkpoint, sha("# later still\n"));
});

test("an unpushed edit to latest.md holds until darkmem has a newer checkpoint, which is then a conflict", async t => {
  const s = await setup(t);
  await s.seed.append({ project: "proj", workstream: "p1", entries: [{ kind: "checkpoint", body: "# synced\n" }] });
  await s.pull();
  const latest = path.join(s.workRoot, "handoff", "latest.md");
  write(latest, "# edited here\n");
  assert.equal((await s.pull()).code, 0);
  assert.equal(read(latest), "# edited here\n");
  await s.seed.append({ project: "proj", workstream: "p2", entries: [{ kind: "checkpoint", body: "# newer\n" }] });
  const result = await s.pull();
  assert.equal(result.code, 1);
  assert.match(result.stdout, /conflict: handoff\/latest\.md: changed locally, and darkmem holds a newer checkpoint/);
  assert.equal(read(latest), "# edited here\n");
});

test("an edit that lands while a document is being fetched is kept and reported", async t => {
  let docsRoot = null;
  const s = await setup(t, {
    onRequest: request => {
      if (request.path === "/api/v1/documents/by-uri" && docsRoot) write(path.join(docsRoot, "a.md"), "edited mid-pull\n");
    },
  });
  await s.seed.putDocument({ project: "proj", uri: "superpowers/a.md", content: "one\n" });
  await s.pull();
  await s.seed.putDocument({ project: "proj", uri: "superpowers/a.md", content: "two\n" });
  docsRoot = s.docsRoot;
  const result = await s.pull();
  assert.equal(result.code, 1);
  assert.match(result.stdout, /conflict: superpowers\/a\.md: changed locally during the pull/);
  assert.equal(read(path.join(s.docsRoot, "a.md")), "edited mid-pull\n");
});

test("conflicts found before a failure are kept for status", async t => {
  const s = await setup(t);
  await s.seed.putDocument({ project: "proj", uri: "superpowers/a.md", content: "one\n" });
  await s.pull();
  write(path.join(s.docsRoot, "a.md"), "local\n");
  await s.seed.putDocument({ project: "proj", uri: "superpowers/a.md", content: "remote\n" });
  s.stub.db.failures.push({ method: "GET", path: "/api/v1/worklog/workstreams", status: 503 });
  const result = await s.pull();
  assert.equal(result.code, 3);
  assert.match(result.stdout, /^conflict: superpowers\/a\.md/m);
  assert.deepEqual(s.state().conflicts.length, 1);
  const status = await run(["status"], { cwd: s.repo, env: s.env });
  assert.match(status.stdout, /^conflict: superpowers\/a\.md: changed locally and on darkmem/m);
});

test("pull fails open: an unreachable darkmem is one line and exit 3 within the timeout", async () => {
  const repo = makeRepo();
  const { env } = makeHome({ repo, url: "http://127.0.0.1:9" });
  const started = Date.now();
  const result = await run(["pull"], { cwd: repo, env });
  assert.equal(result.code, 3);
  assert.match(result.stderr, /^darkmem-sync: pull failed: GET \/api\/v1\/documents\/manifest: /);
  assert.equal(result.stderr.trim().split("\n").length, 1);
  assert.ok(Date.now() - started < 10000);
});

test("pull in local mode does nothing and succeeds", async () => {
  const repo = makeRepo();
  const { env } = makeHome({ repo, config: null });
  const result = await run(["pull"], { cwd: repo, env });
  assert.equal(result.code, 0);
  assert.match(result.stdout, /^darkmem-sync: local mode/);
});
