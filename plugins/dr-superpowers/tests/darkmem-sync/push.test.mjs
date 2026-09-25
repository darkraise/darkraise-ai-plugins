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
  assert.match(result.stdout, /^conflict: superpowers\/a\.md: changed on darkmem since the last sync \(darkmem said: expected_hash [0-9a-f]{64} does not match[^)]*\); pull, reconcile, then push$/m);
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
  const lost = await s.push();
  assert.equal(lost.code, 1);
  assert.match(lost.stdout, /^failed: superpowers\/a\.md: darkmem answered 502: injected failure$/m);
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
  assert.equal(lost.code, 1);
  assert.match(lost.stdout, /^failed: sdd\/p1\/progress\.md: darkmem answered 502: injected failure$/m);
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
  const lost = await s.push();
  assert.equal(lost.code, 1);
  assert.match(lost.stdout, /^failed: handoff\/latest\.md: darkmem answered 502: injected failure$/m);
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

test("every ledger append names the seq it follows; another mirror's append is a 409 reconciled once", async t => {
  const s = await setup(t);
  const file = path.join(s.workRoot, "sdd", "p1", "progress.md");
  write(file, "one\n");
  assert.equal((await s.push()).code, 0);
  const [first] = s.posts("/api/v1/worklog/entries");
  assert.equal(first.body.expected_last_seq, 0, "a new ledger expects an empty one");
  const oneSeq = (await s.ledger("p1"))[0].seq;
  await s.seed.append({ project: "proj", workstream: "p1", entries: [{ kind: "ledger", body: "two\n" }] });
  fs.appendFileSync(file, "two\nthree\n");
  const result = await s.push();
  assert.equal(result.code, 0, result.stdout + result.stderr);
  assert.deepEqual((await s.ledger("p1")).map(e => e.body), ["one\n", "two\n", "three\n"]);
  const appends = s.posts("/api/v1/worklog/entries").filter(r => r.body.run_key !== "seed");
  assert.equal(appends[1].body.expected_last_seq, oneSeq, "the stale expectation, answered 409");
  assert.deepEqual(appends[2].body.entries, [{ kind: "ledger", body: "three\n" }], "only the bytes darkmem lacked");
  const state = JSON.parse(read(path.join(s.mirror, ".sync-state.json")));
  assert.equal(state.ledgers.p1.lastSeq, (await s.ledger("p1")).at(-1).seq);
});

test("a second 409 in one push is a conflict and nothing more is sent", async t => {
  const racing = [];
  const s = await setup(t, {
    onRequest: (request, db) => {
      if (racing.length && request.method === "POST" && request.path === "/api/v1/worklog/entries") {
        const ws = db.workstreams.find(w => w.key === "p1");
        ws.entries.push({ id: `race-${db.nextSeq}`, seq: db.nextSeq++, run_key: "other", kind: "ledger", body: racing.shift(), properties: {}, created_at: ws.last_entry_at });
      }
    },
  });
  const file = path.join(s.workRoot, "sdd", "p1", "progress.md");
  write(file, "one\n");
  await s.push();
  fs.appendFileSync(file, "two\nthree\n");
  racing.push("two\n", "three\n");
  const result = await s.push();
  assert.equal(result.code, 1);
  assert.match(result.stdout, /^conflict: sdd\/p1\/progress\.md: darkmem's ledger for p1 changed since the last sync/m);
  assert.deepEqual((await s.ledger("p1")).map(e => e.body), ["one\n", "two\n", "three\n"], "the other client's lines, none sent twice");
  assert.equal(s.posts("/api/v1/worklog/entries").length, 3, "the first push, the 409, and the retry's 409");
});

test("a ledger with a byte that is not UTF-8 fails with its offset; a character still being written is a note", async t => {
  const s = await setup(t);
  const file = path.join(s.workRoot, "sdd", "p1", "progress.md");
  write(file, "one\n");
  await s.push();
  fs.appendFileSync(file, Buffer.from([0x61, 0xff, 0x62, 0x0a]));
  const middle = await s.push();
  assert.equal(middle.code, 1);
  assert.match(middle.stdout, /^failed: sdd\/p1\/progress\.md: byte 5 is not UTF-8 text; not pushed$/m);
  write(file, "one\n");
  fs.appendFileSync(file, Buffer.from([0xff]));
  const lone = await s.push();
  assert.equal(lone.code, 1);
  assert.match(lone.stdout, /^failed: sdd\/p1\/progress\.md: byte 4 is not UTF-8 text; not pushed$/m);
  write(file, "one\n");
  fs.appendFileSync(file, Buffer.from([0xe2, 0x82]));
  const partial = await s.push();
  assert.equal(partial.code, 0, partial.stdout);
  assert.match(partial.stdout, /^note: sdd\/p1\/progress\.md: the appended bytes end inside a character; push again once the write finishes$/m);
  fs.appendFileSync(file, Buffer.from([0xac, 0x0a]));
  assert.equal((await s.push()).code, 0);
  assert.deepEqual((await s.ledger("p1")).map(e => e.body), ["one\n", "€\n"]);
});

test("a ledger longer than one append call chains each call's last_seq into the next", async t => {
  const s = await setup(t);
  const file = path.join(s.workRoot, "sdd", "big", "progress.md");
  const line = `${"x".repeat(65535)}\n`;
  write(file, line.repeat(101));
  const result = await s.push();
  assert.equal(result.code, 0, result.stdout + result.stderr);
  assert.match(result.stdout, /101 ledger entries/);
  const appends = s.posts("/api/v1/worklog/entries");
  assert.deepEqual(appends.map(r => r.body.entries.length), [100, 1]);
  const entries = await s.ledger("big");
  assert.equal(appends[0].body.expected_last_seq, 0);
  assert.equal(appends[1].body.expected_last_seq, entries[99].seq, "the second call expects the first call's last seq");
  assert.equal(entries.map(e => e.body).join(""), read(file));
  assert.equal(JSON.parse(read(path.join(s.mirror, ".sync-state.json"))).ledgers.big.lastSeq, entries[100].seq);
});

test("a 503 on one document names its uri, and the other documents, the ledger and the checkpoint still land", async t => {
  const s = await setup(t);
  write(path.join(s.docsRoot, "a.md"), "a\n");
  write(path.join(s.docsRoot, "b.md"), "b\n");
  write(path.join(s.workRoot, "sdd", "p1", "progress.md"), "one\n");
  write(path.join(s.workRoot, "handoff", "latest.md"), "# Handoff\n\n## State\n- Plan: `docs/superpowers/plans/p1.md`\n");
  s.stub.db.failures.push({ method: "POST", path: "/api/v1/documents", status: 503 });
  const result = await s.push();
  assert.equal(result.code, 1);
  assert.match(result.stdout, /^failed: superpowers\/a\.md: darkmem answered 503: injected failure$/m);
  assert.equal(s.stub.db.documents.has("proj\u0000superpowers/a.md"), false);
  assert.equal(s.stub.db.documents.get("proj\u0000superpowers/b.md").content, "b\n");
  assert.deepEqual(s.stub.db.workstreams.find(w => w.key === "p1").entries.map(e => e.kind), ["ledger", "checkpoint"]);
  assert.equal((await s.push()).code, 0);
  assert.equal(s.stub.db.documents.get("proj\u0000superpowers/a.md").content, "a\n");
});

test("a 401 on a document stops the push before the ledgers", async t => {
  const s = await setup(t);
  write(path.join(s.docsRoot, "a.md"), "a\n");
  write(path.join(s.workRoot, "sdd", "p1", "progress.md"), "one\n");
  s.stub.db.failures.push({ method: "POST", path: "/api/v1/documents", status: 401, detail: "Not authenticated" });
  const result = await s.push();
  assert.equal(result.code, 3);
  assert.match(result.stderr, /^darkmem-sync: push failed: POST \/api\/v1\/documents answered 401: Not authenticated$/m);
  assert.equal(s.stub.db.workstreams.length, 0);
});

test("a failed document manifest fails the documents phase and the ledgers still push", async t => {
  const s = await setup(t);
  write(path.join(s.docsRoot, "a.md"), "a\n");
  write(path.join(s.workRoot, "sdd", "p1", "progress.md"), "one\n");
  s.stub.db.failures.push({ method: "GET", path: "/api/v1/documents/manifest", status: 503 });
  const result = await s.push();
  assert.equal(result.code, 1);
  assert.match(result.stdout, /^failed: document manifest: darkmem answered 503: injected failure; no document pushed$/m);
  assert.equal(s.posts("/api/v1/documents").length, 0);
  assert.deepEqual((await s.ledger("p1")).map(e => e.body), ["one\n"]);
});

test("a failed handoff link stays pending and the next push links it; a pending link with no workstream is dropped", async t => {
  const s = await setup(t);
  await s.seed.append({ project: "proj", workstream: "p1", entries: [{ kind: "ledger", body: "one\n" }] });
  write(path.join(s.workRoot, "sdd", "p1", "handoff.md"), "# Handoff p1\n");
  s.stub.db.failures.push({ method: "PATCH", path: "/api/v1/worklog/workstreams/", status: 503 });
  const failed = await s.push();
  assert.equal(failed.code, 1);
  assert.match(failed.stdout, /^failed: superpowers\/handoff\/p1\.md: linking it from workstream p1: darkmem answered 503: injected failure$/m);
  const stateFile = path.join(s.mirror, ".sync-state.json");
  assert.deepEqual(JSON.parse(read(stateFile)).pendingLinks, ["superpowers/handoff/p1.md"]);
  const retried = await s.push();
  assert.equal(retried.code, 0, retried.stdout);
  assert.equal(s.stub.db.workstreams.find(w => w.key === "p1").properties.handoff_uri, "superpowers/handoff/p1.md");
  assert.deepEqual(JSON.parse(read(stateFile)).pendingLinks, []);
  const state = JSON.parse(read(stateFile));
  state.pendingLinks = ["superpowers/handoff/ghost.md"];
  fs.writeFileSync(stateFile, JSON.stringify(state));
  const dropped = await s.push();
  assert.equal(dropped.code, 0, dropped.stdout);
  assert.deepEqual(JSON.parse(read(stateFile)).pendingLinks, []);
  assert.equal(s.stub.db.workstreams.some(w => w.key === "ghost"), false);
});

test("a checkpoint filed a microsecond before the last synced one is not taken for this note", async t => {
  const s = await setup(t);
  await s.seed.append({ project: "proj", workstream: "p1", entries: [{ kind: "checkpoint", body: "# X\n" }] });
  await s.seed.append({ project: "proj", workstream: "p1", entries: [{ kind: "checkpoint", body: "# Y\n" }] });
  const [x, y] = s.stub.db.workstreams[0].entries;
  x.created_at = "2026-09-25T10:00:00.000001+00:00";
  y.created_at = "2026-09-25T10:00:00.000002+00:00";
  assert.equal((await run(["pull"], { cwd: s.repo, env: s.env })).code, 0);
  assert.equal(read(path.join(s.workRoot, "handoff", "latest.md")), "# Y\n");
  write(path.join(s.workRoot, "handoff", "latest.md"), "# X\n");
  const result = await s.push("--workstream", "p1");
  assert.equal(result.code, 0, result.stdout);
  assert.match(result.stdout, /1 checkpoints/);
  assert.deepEqual(s.stub.db.workstreams[0].entries.map(e => e.body), ["# X\n", "# Y\n", "# X\n"]);
});

test("push refuses a uri Windows cannot hold", { skip: process.platform === "win32" && "Windows cannot create these files" }, async t => {
  const s = await setup(t);
  write(path.join(s.docsRoot, "notes", "a:b.md"), "x\n");
  write(path.join(s.docsRoot, "notes", "CON.md"), "y\n");
  const result = await s.push();
  assert.equal(result.code, 1);
  assert.match(result.stdout, /^failed: superpowers\/notes\/a:b\.md: the name "a:b\.md" holds a character Windows refuses, so not every mirror can hold it as a file; not pushed$/m);
  assert.match(result.stdout, /^failed: superpowers\/notes\/CON\.md: the name "CON\.md" is a Windows device name/m);
  assert.equal(s.posts("/api/v1/documents").length, 0);
});

test("push refuses a uri that differs only in case from one darkmem holds", async t => {
  const s = await setup(t);
  await s.seed.putDocument({ project: "proj", uri: "superpowers/notes/A.md", content: "theirs\n" });
  write(path.join(s.docsRoot, "notes", "a.md"), "mine\n");
  const result = await s.push();
  assert.equal(result.code, 1);
  assert.match(result.stdout, /^conflict: superpowers\/notes\/a\.md: darkmem holds superpowers\/notes\/A\.md, which differ only in case from it; not pushed — rename the local file, or rename or delete the others on darkmem by hand \(the sync has no rename or delete route\)$/m);
  assert.equal(s.posts("/api/v1/documents").length, 1, "only the seeding put");
  await s.seed.putDocument({ project: "proj", uri: "superpowers/notes/a.md", content: "also theirs\n" });
  const pair = await s.push();
  assert.equal(pair.code, 1);
  assert.match(pair.stdout, /^conflict: superpowers\/notes\/a\.md: darkmem holds superpowers\/notes\/A\.md, which differ only in case/m, "a local file matching one of a remote pair still collides with the other");
  assert.equal(s.posts("/api/v1/documents").length, 2, "only the two seeding puts");
});

test("push refuses local files that differ only in case", { skip: process.platform !== "linux" && "needs a case-sensitive file system" }, async t => {
  const s = await setup(t);
  write(path.join(s.docsRoot, "A.md"), "one\n");
  write(path.join(s.docsRoot, "a.md"), "two\n");
  const result = await s.push();
  assert.equal(result.code, 1);
  assert.match(result.stdout, /^conflict: superpowers\/A\.md, superpowers\/a\.md: differ only in case, which a case-insensitive file system holds as one file; none of them pushed — rename all but one$/m);
  assert.equal(s.posts("/api/v1/documents").length, 0);
});

test("a 409 whose read answers darkmem's own 404 is a deletion; any other 404 is a failure", async t => {
  const s = await setup(t);
  write(path.join(s.docsRoot, "a.md"), "one\n");
  await s.push();
  await s.seed.putDocument({ project: "proj", uri: "superpowers/a.md", content: "theirs\n" });
  write(path.join(s.docsRoot, "a.md"), "two\n");
  s.stub.db.failures.push({ method: "GET", path: "/api/v1/documents/by-uri", status: 404, detail: "Not Found" });
  const result = await s.push();
  assert.equal(result.code, 1);
  assert.match(result.stdout, /^failed: superpowers\/a\.md: darkmem answered 404: Not Found$/m);
  assert.doesNotMatch(result.stdout, /deleted on darkmem/);
});
