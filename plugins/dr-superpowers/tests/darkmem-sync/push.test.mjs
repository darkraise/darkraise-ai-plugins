import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { createClient } from "../../scripts/lib/darkmem-client.mjs";
import { STUB_KEY, sha, startStub, storedDocument } from "./stub-server.mjs";
import { makeHome, makeRepo, read, run, write } from "./helpers.mjs";

async function setup(t, stubOptions = {}) {
  const stub = await startStub(stubOptions);
  t.after(() => stub.close());
  const repo = makeRepo();
  const home = makeHome({ repo, url: stub.url });
  const seed = createClient({ url: stub.url, apiKey: STUB_KEY, runKey: "seed" });
  const push = (...args) => run(["push", ...args], { cwd: repo, env: home.env });
  const posts = path => stub.db.requests.filter(r => r.method === "POST" && r.path === path);
  const ledger = async slug => {
    const ws = stub.db.workstreams.find(w => w.key === slug);
    return ws.entries.filter(e => e.kind === "ledger");
  };
  return { stub, repo, ...home, seed, push, posts, ledger };
}

test("a new document goes up without a precondition, then only when it changes, under the recorded hash", async t => {
  const s = await setup(t);
  write(path.join(s.docsRoot, "specs", "a.md"), "# A\n");
  const first = await s.push();
  assert.equal(first.code, 0, first.stdout + first.stderr);
  assert.match(first.stdout, /darkmem-sync push: 1 documents, 0 ledger entries, 0 checkpoints; 0 conflicts, 0 failures/);
  const [created] = s.posts("/api/v1/documents");
  assert.deepEqual(created.body, { project: "proj", uri: "superpowers/specs/a.md", content: "# A\n" });
  assert.equal((await s.push()).code, 0);
  assert.equal(s.posts("/api/v1/documents").length, 1, "an unchanged document is not sent again");
  write(path.join(s.docsRoot, "specs", "a.md"), "# A2\n");
  assert.equal((await s.push()).code, 0);
  assert.equal(s.posts("/api/v1/documents")[1].body.expected_hash, sha("# A\n"));
});

test("a document moved on darkmem is a conflict and the local file stays", async t => {
  const s = await setup(t);
  write(path.join(s.docsRoot, "a.md"), "one\n");
  await s.push();
  await s.seed.putDocument({ project: "proj", uri: "superpowers/a.md", content: "theirs\n" });
  write(path.join(s.docsRoot, "a.md"), "mine\n");
  const result = await s.push();
  assert.equal(result.code, 1);
  assert.match(result.stdout, /^conflict: superpowers\/a\.md: changed on darkmem since the last sync; pull, reconcile, then push$/m);
  assert.equal(read(path.join(s.docsRoot, "a.md")), "mine\n");
  assert.equal(s.stub.db.documents.get("proj\u0000superpowers/a.md").content, "theirs\n");
});

test("a document deleted on darkmem since the last sync is a conflict and the local file stays", async t => {
  const s = await setup(t);
  write(path.join(s.docsRoot, "a.md"), "one\n");
  await s.push();
  s.stub.db.documents.delete("proj\u0000superpowers/a.md");
  write(path.join(s.docsRoot, "a.md"), "two\n");
  const result = await s.push();
  assert.equal(result.code, 1, result.stderr);
  assert.match(result.stdout, /^conflict: superpowers\/a\.md: deleted on darkmem since the last sync; pull, reconcile, then push$/m);
  assert.equal(read(path.join(s.docsRoot, "a.md")), "two\n");
});

test("an unrecorded file darkmem already holds is adopted when equal and a conflict when not", async t => {
  const s = await setup(t);
  await s.seed.putDocument({ project: "proj", uri: "superpowers/same.md", content: "same\n" });
  await s.seed.putDocument({ project: "proj", uri: "superpowers/diff.md", content: "theirs\n" });
  write(path.join(s.docsRoot, "same.md"), "same\n");
  write(path.join(s.docsRoot, "diff.md"), "mine\n");
  const result = await s.push();
  assert.equal(result.code, 1);
  assert.match(result.stdout, /conflict: superpowers\/diff\.md: darkmem already holds different content/);
  assert.equal(s.posts("/api/v1/documents").length, 2, "only the two seeding puts");
});

test("handoff notes go up as documents and are linked from their workstream", async t => {
  const s = await setup(t);
  await s.seed.append({ project: "proj", workstream: "p1", entries: [{ kind: "ledger", body: "one\n" }] });
  write(path.join(s.workRoot, "sdd", "p1", "handoff.md"), "# Handoff p1\n");
  const result = await s.push();
  assert.equal(result.code, 0, result.stdout);
  assert.equal(s.stub.db.documents.get("proj\u0000superpowers/handoff/p1.md").content, "# Handoff p1\n");
  assert.equal(s.stub.db.workstreams.find(w => w.key === "p1").properties.handoff_uri, "superpowers/handoff/p1.md");
  delete s.stub.db.workstreams.find(w => w.key === "p1").properties.handoff_uri;
  fs.rmSync(path.join(s.mirror, ".sync-state.json"));
  assert.equal((await s.push()).code, 0);
  assert.equal(s.stub.db.workstreams.find(w => w.key === "p1").properties.handoff_uri, "superpowers/handoff/p1.md", "an adopted handoff note is linked too");
});

test("an empty document fails the push and keeps its record; a reserved file is a note", async t => {
  const s = await setup(t);
  write(path.join(s.docsRoot, "a.md"), "a\n");
  await s.push();
  write(path.join(s.docsRoot, "a.md"), "");
  write(path.join(s.docsRoot, "handoff", "x.md"), "x");
  const result = await s.push();
  assert.equal(result.code, 1);
  assert.match(result.stdout, /failed: superpowers\/a\.md: empty or not UTF-8 text, which darkmem cannot store; not pushed/);
  assert.match(result.stdout, /note: handoff\/x\.md: the docs root's handoff\/ directory is reserved, not pushed/);
  assert.equal(s.stub.db.documents.get("proj\u0000superpowers/a.md").content, "a\n");
  assert.match((await run(["status"], { cwd: s.repo, env: s.env })).stdout, /^modified: superpowers\/a\.md$/m);
});

test("a document another client files during the push is reported as replaced", async t => {
  const s = await setup(t, {
    onRequest: (request, db) => {
      if (request.method === "POST" && request.path === "/api/v1/documents" && request.body.uri === "superpowers/race.md") {
        db.documents.set("proj\u0000superpowers/race.md", storedDocument("proj", "superpowers/race.md", "theirs\n"));
      }
    },
  });
  write(path.join(s.docsRoot, "race.md"), "mine\n");
  const result = await s.push();
  assert.equal(result.code, 1);
  assert.match(result.stdout, /failed: superpowers\/race\.md: another client filed it during this push, and this push replaced its content/);
});

test("a document put whose answer was lost is recorded on the next push, not reported as a conflict", async t => {
  const s = await setup(t);
  write(path.join(s.docsRoot, "a.md"), "one\n");
  await s.push();
  write(path.join(s.docsRoot, "a.md"), "two\n");
  s.stub.db.failures.push({ method: "POST", path: "/api/v1/documents", status: 502, commit: true });
  assert.equal((await s.push()).code, 3);
  const retry = await s.push();
  assert.equal(retry.code, 0, retry.stdout);
  assert.equal(s.stub.db.documents.get("proj\u0000superpowers/a.md").content, "two\n");
  assert.equal((await run(["status"], { cwd: s.repo, env: s.env })).stdout.split("\n").filter(Boolean).length, 1);
});

test("a ledger goes up as the appended bytes, one entry per push, and darkmem's concatenation is the file", async t => {
  const s = await setup(t);
  write(path.join(s.docsRoot, "plans", "p1.md"), "# P1\n\n**Spec:** `docs/superpowers/specs/s.md`\n");
  const file = path.join(s.workRoot, "sdd", "p1", "progress.md");
  write(file, "# SDD ledger — plan: docs/superpowers/plans/p1.md\n\nTask 1: implementer (assigned)\n");
  assert.equal((await s.push()).code, 0);
  fs.appendFileSync(file, "Task 1: complete\n\n| a | b |\n|---|---|\n");
  const second = await s.push();
  assert.match(second.stdout, /0 documents, 1 ledger entries/);
  const entries = await s.ledger("p1");
  assert.equal(entries.length, 2);
  assert.equal(entries[1].body, "Task 1: complete\n\n| a | b |\n|---|---|\n");
  assert.equal(entries.map(e => e.body).join(""), read(file));
  assert.equal(entries[0].run_key, "sess-1");
  const ws = s.stub.db.workstreams.find(w => w.key === "p1");
  assert.deepEqual(ws.properties, { plan_uri: "superpowers/plans/p1.md", spec_uri: "superpowers/specs/s.md" });
  assert.equal((await s.push()).code, 0);
  assert.equal((await s.ledger("p1")).length, 2, "nothing new, nothing sent");
});

test("a rewritten ledger is refused and nothing is sent", async t => {
  const s = await setup(t);
  const file = path.join(s.workRoot, "sdd", "p1", "progress.md");
  write(file, "one\ntwo\n");
  await s.push();
  write(file, "one\nTWO\nthree\n");
  const result = await s.push();
  assert.equal(result.code, 1);
  assert.match(result.stdout, /conflict: sdd\/p1\/progress\.md: rewritten rather than appended to/);
  assert.equal((await s.ledger("p1")).length, 1);
});

test("an append longer than one entry is split at a newline and still concatenates exactly", async t => {
  const s = await setup(t);
  const file = path.join(s.workRoot, "sdd", "big", "progress.md");
  const line = `${"x".repeat(999)}\n`;
  write(file, line.repeat(70));
  assert.equal((await s.push()).code, 0);
  const entries = await s.ledger("big");
  assert.equal(entries.length, 2);
  assert.ok(entries.every(e => e.body.length <= 65536 && e.body.endsWith("\n")));
  assert.equal(entries.map(e => e.body).join(""), line.repeat(70));
});

test("a lost state file never re-sends lines darkmem already holds", async t => {
  const s = await setup(t);
  const file = path.join(s.workRoot, "sdd", "p1", "progress.md");
  write(file, "one\n");
  await s.push();
  fs.rmSync(path.join(s.mirror, ".sync-state.json"));
  fs.appendFileSync(file, "two\n");
  assert.equal((await s.push()).code, 0);
  assert.deepEqual((await s.ledger("p1")).map(e => e.body), ["one\n", "two\n"]);
});

test("a ledger append whose answer was lost is reconciled, never sent twice", async t => {
  const s = await setup(t);
  const file = path.join(s.workRoot, "sdd", "p1", "progress.md");
  write(file, "one\n");
  s.stub.db.failures.push({ method: "POST", path: "/api/v1/worklog/entries", status: 502, commit: true });
  const lost = await s.push();
  assert.equal(lost.code, 3);
  assert.equal(JSON.parse(read(path.join(s.mirror, ".sync-state.json"))).ledgers.p1.pending, true);
  assert.equal((await s.push()).code, 0);
  assert.deepEqual((await s.ledger("p1")).map(e => e.body), ["one\n"]);
  fs.appendFileSync(file, "two\n");
  assert.equal((await s.push()).code, 0);
  assert.deepEqual((await s.ledger("p1")).map(e => e.body), ["one\n", "two\n"]);
  await s.seed.append({ project: "proj", workstream: "p1", entries: [{ kind: "ledger", body: "three\n" }] });
  fs.appendFileSync(file, "three\n");
  assert.equal((await s.push()).code, 0);
  assert.deepEqual((await s.ledger("p1")).map(e => e.body), ["one\n", "two\n", "three\n"]);
  await s.seed.append({ project: "proj", workstream: "p1", entries: [{ kind: "ledger", body: "theirs\n" }] });
  fs.appendFileSync(file, "four\n");
  const stale = await s.push();
  assert.equal(stale.code, 1);
  assert.match(stale.stdout, /^conflict: sdd\/p1\/progress\.md: darkmem's ledger for p1 changed since the last sync/m);
  assert.equal((await s.ledger("p1")).length, 4);
});

test("a ledger append refused by darkmem is a failure and nothing is marked sent", async t => {
  const s = await setup(t);
  const file = path.join(s.workRoot, "sdd", "p1", "progress.md");
  write(file, "one\n");
  s.stub.db.failures.push({ method: "POST", path: "/api/v1/worklog/entries", status: 422, detail: "refused" });
  const refused = await s.push();
  assert.equal(refused.code, 1);
  assert.match(refused.stdout, /failed: sdd\/p1\/progress\.md: darkmem refused an entry: refused/);
  assert.equal((await s.push()).code, 0);
  assert.deepEqual((await s.ledger("p1")).map(e => e.body), ["one\n"]);
});

test("a plan directory whose name cannot be a workstream key fails the push", async t => {
  const s = await setup(t);
  write(path.join(s.workRoot, "sdd", "bad name", "progress.md"), "x\n");
  const result = await s.push();
  assert.equal(result.code, 1);
  assert.match(result.stdout, /failed: .*bad name: not a usable workstream key/);
});

test("latest.md goes up as a checkpoint on the plan its State names, or on --workstream", async t => {
  const s = await setup(t);
  const latest = path.join(s.workRoot, "handoff", "latest.md");
  write(latest, "# Handoff — 2026-09-24 (phase stop)\n\n## State\n- Plan: `docs/superpowers/plans/p1.md`; ledger: `x`\n");
  assert.equal((await s.push()).code, 0);
  const p1 = s.stub.db.workstreams.find(w => w.key === "p1");
  assert.deepEqual(p1.entries.map(e => e.kind), ["checkpoint"]);
  assert.deepEqual(p1.properties, { plan_uri: "superpowers/plans/p1.md" });
  assert.equal((await s.push()).code, 0);
  assert.equal(p1.entries.length, 1, "an unchanged checkpoint is not sent again");
  write(latest, "# Handoff\n\n## State\n- unplanned work\n");
  const unnamed = await s.push();
  assert.equal(unnamed.code, 1);
  assert.match(unnamed.stdout, /failed: handoff\/latest\.md: its State section names no plan or draft; push again with --workstream KEY/);
  assert.equal((await s.push("--workstream", "adhoc")).code, 0);
  assert.equal(s.stub.db.workstreams.find(w => w.key === "adhoc").entries[0].kind, "checkpoint");
  write(latest, "# Handoff\n\n## State\n- Draft: `docs/superpowers/specs/d-design.md`\n");
  s.stub.db.failures.push({ method: "POST", path: "/api/v1/worklog/entries", status: 502, commit: true });
  assert.equal((await s.push()).code, 3);
  await s.seed.append({ project: "proj", workstream: "d-design", entries: [{ kind: "checkpoint", body: "# Handoff from another machine\n" }] });
  assert.equal((await s.push()).code, 0);
  const draft = s.stub.db.workstreams.find(w => w.key === "d-design");
  assert.equal(draft.entries.length, 2, "a checkpoint whose answer was lost is not filed twice, even behind another client's");
  assert.deepEqual(draft.properties, { spec_uri: "superpowers/specs/d-design.md" });
  const bad = await s.push("--workstream", "../x");
  assert.equal(bad.code, 2);
  assert.match(bad.stderr, /--workstream "\.\.\/x" is not a workstream key/);
});

test("without a declared session the run key falls back to the machine and day", async t => {
  const s = await setup(t);
  delete s.env.DR_SUPERPOWERS_SESSION_ID;
  write(path.join(s.workRoot, "sdd", "p1", "progress.md"), "one\n");
  assert.equal((await s.push()).code, 0);
  const [append] = s.posts("/api/v1/worklog/entries");
  assert.match(append.body.run_key, new RegExp(`^codex:${os.hostname().replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}:\\d{4}-\\d{2}-\\d{2}$`));
  assert.equal(append.headers["x-darkmem-client"], "dr-superpowers");
});

test("status is clean after a push and names an edit made after it", async t => {
  const s = await setup(t);
  write(path.join(s.docsRoot, "a.md"), "a\n");
  await s.push();
  const clean = await run(["status"], { cwd: s.repo, env: s.env });
  assert.equal(clean.stdout.split("\n").filter(Boolean).length, 1);
  write(path.join(s.docsRoot, "a.md"), "b\n");
  const dirty = await run(["status"], { cwd: s.repo, env: s.env });
  assert.match(dirty.stdout, /^modified: superpowers\/a\.md$/m);
});
