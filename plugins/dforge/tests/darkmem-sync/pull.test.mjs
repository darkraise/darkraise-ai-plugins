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
  await s.seed.putDocument({ project: "proj", uri: "dforge/specs/a.md", content: "# A\n" });
  await s.seed.putDocument({ project: "proj", uri: "dforge/handoff/p1.md", content: "# Handoff\n" });
  await s.seed.putDocument({ project: "proj", uri: "other/x.md", content: "x" });
  await s.seed.putDocument({ project: "else", uri: "dforge/specs/b.md", content: "b" });
  const result = await s.pull();
  assert.equal(result.code, 0, result.stdout + result.stderr);
  assert.match(result.stdout, /darkmem-sync pull: 2 documents, 0 ledgers, 0 checkpoints; 0 conflicts, 0 failures/);
  assert.equal(read(path.join(s.docsRoot, "specs", "a.md")), "# A\n");
  assert.equal(read(path.join(s.workRoot, "sdd", "p1", "handoff.md")), "# Handoff\n");
  assert.equal(fs.existsSync(path.join(s.docsRoot, "..", "other")), false);
  assert.deepEqual(s.state().documents, { "dforge/specs/a.md": sha("# A\n"), "dforge/handoff/p1.md": sha("# Handoff\n") });
  const before = fetches(s.stub);
  assert.equal((await s.pull()).code, 0);
  assert.equal(fetches(s.stub), before, "an unchanged manifest fetches nothing");
});

test("a document changed on darkmem replaces an unchanged local copy", async t => {
  const s = await setup(t);
  await s.seed.putDocument({ project: "proj", uri: "dforge/a.md", content: "one\n" });
  await s.pull();
  await s.seed.putDocument({ project: "proj", uri: "dforge/a.md", content: "two\n" });
  assert.equal((await s.pull()).code, 0);
  assert.equal(read(path.join(s.docsRoot, "a.md")), "two\n");
});

test("a document changed on both sides is a conflict and the local copy stays", async t => {
  const s = await setup(t);
  await s.seed.putDocument({ project: "proj", uri: "dforge/a.md", content: "one\n" });
  await s.pull();
  write(path.join(s.docsRoot, "a.md"), "local\n");
  const localOnly = await s.pull();
  assert.equal(localOnly.code, 0, "an edit darkmem has not moved past is push's to send");
  assert.doesNotMatch(localOnly.stdout, /^conflict:/m);
  assert.equal(read(path.join(s.docsRoot, "a.md")), "local\n");
  await s.seed.putDocument({ project: "proj", uri: "dforge/a.md", content: "remote\n" });
  const result = await s.pull();
  assert.equal(result.code, 1);
  assert.match(result.stdout, /^conflict: dforge\/a\.md: changed locally and on darkmem; move the local file aside/m);
  assert.equal(read(path.join(s.docsRoot, "a.md")), "local\n");
  assert.equal(s.state().conflicts.length, 1);
  const status = await run(["status"], { cwd: s.repo, env: s.env });
  assert.match(status.stdout, /^conflict: dforge\/a\.md/m);
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
  const newest = s.stub.db.workstreams.find(w => w.key === "p1").entries.filter(e => e.kind === "ledger").at(-1);
  assert.deepEqual(s.state().ledgers.p1, { offset: fs.statSync(file).size, prefix: sha(read(file)), lastSeq: newest.seq });
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
  await s.seed.putDocument({ project: "proj", uri: "dforge/a.md", content: "one\n" });
  await s.pull();
  await s.seed.putDocument({ project: "proj", uri: "dforge/a.md", content: "two\n" });
  docsRoot = s.docsRoot;
  const result = await s.pull();
  assert.equal(result.code, 1);
  assert.match(result.stdout, /conflict: dforge\/a\.md: changed locally during the pull/);
  assert.equal(read(path.join(s.docsRoot, "a.md")), "edited mid-pull\n");
});

test("conflicts found before a failure are kept for status", async t => {
  const s = await setup(t);
  await s.seed.putDocument({ project: "proj", uri: "dforge/a.md", content: "one\n" });
  await s.pull();
  write(path.join(s.docsRoot, "a.md"), "local\n");
  await s.seed.putDocument({ project: "proj", uri: "dforge/a.md", content: "remote\n" });
  s.stub.db.failures.push({ method: "GET", path: "/api/v1/worklog/workstreams", status: 401, detail: "Not authenticated" });
  const result = await s.pull();
  assert.equal(result.code, 3);
  assert.match(result.stdout, /^conflict: dforge\/a\.md/m);
  assert.deepEqual(s.state().conflicts.length, 1);
  const status = await run(["status"], { cwd: s.repo, env: s.env });
  assert.match(status.stdout, /^conflict: dforge\/a\.md: changed locally and on darkmem/m);
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
  const { env } = makeHome({ repo, config: null, stores: null });
  const result = await run(["pull"], { cwd: repo, env });
  assert.equal(result.code, 0);
  assert.match(result.stdout, /^darkmem-sync: local mode/);
});

test("a pulled ledger records its newest seq, so the next push appends without re-reading it", async t => {
  const s = await setup(t);
  await s.seed.append({ project: "proj", workstream: "p1", entries: [{ kind: "ledger", body: "one\n" }] });
  assert.equal((await s.pull()).code, 0);
  const file = path.join(s.workRoot, "sdd", "p1", "progress.md");
  fs.appendFileSync(file, "two\n");
  const reads = () => s.stub.db.requests.filter(r => r.method === "GET" && r.path.endsWith("/entries")).length;
  const before = reads();
  const pushed = await run(["push"], { cwd: s.repo, env: s.env });
  assert.equal(pushed.code, 0, pushed.stdout + pushed.stderr);
  assert.equal(reads(), before, "push trusts the pulled seq instead of reading the ledger again");
  const [append] = s.stub.db.requests.filter(r => r.method === "POST" && r.path === "/api/v1/worklog/entries" && r.body.run_key !== "seed");
  assert.equal(append.body.expected_last_seq, s.stub.db.workstreams[0].entries[0].seq);
  assert.deepEqual(s.stub.db.workstreams[0].entries.map(e => e.body), ["one\n", "two\n"]);
});

test("a failed document fetch names its uri and the pull goes on; a failed manifest or workstream list fails its phase", async t => {
  const s = await setup(t);
  await s.seed.putDocument({ project: "proj", uri: "dforge/a.md", content: "a\n" });
  await s.seed.putDocument({ project: "proj", uri: "dforge/b.md", content: "b\n" });
  await s.seed.append({ project: "proj", workstream: "p1", entries: [{ kind: "ledger", body: "one\n" }] });
  s.stub.db.failures.push({ method: "GET", path: "/api/v1/documents/by-uri", status: 503 });
  const one = await s.pull();
  assert.equal(one.code, 1);
  assert.match(one.stdout, /^failed: dforge\/a\.md: darkmem answered 503: injected failure$/m);
  assert.equal(fs.existsSync(path.join(s.docsRoot, "a.md")), false);
  assert.equal(read(path.join(s.docsRoot, "b.md")), "b\n");
  assert.equal(read(path.join(s.workRoot, "sdd", "p1", "progress.md")), "one\n");
  await s.seed.append({ project: "proj", workstream: "p1", entries: [{ kind: "ledger", body: "two\n" }] });
  s.stub.db.failures.push({ method: "GET", path: "/api/v1/documents/manifest", status: 503 });
  const manifest = await s.pull();
  assert.equal(manifest.code, 1);
  assert.match(manifest.stdout, /^failed: document manifest: darkmem answered 503: injected failure; no document pulled$/m);
  assert.equal(read(path.join(s.workRoot, "sdd", "p1", "progress.md")), "one\ntwo\n", "the ledgers still pull");
  s.stub.db.failures.push({ method: "GET", path: "/api/v1/worklog/workstreams", status: 503 });
  const list = await s.pull();
  assert.equal(list.code, 1);
  assert.match(list.stdout, /^failed: workstream list: darkmem answered 503: injected failure; no ledger or checkpoint pulled$/m);
  assert.equal(read(path.join(s.docsRoot, "a.md")), "a\n", "the documents still pull");
});

test("a failed ledger or checkpoint read names its item and the rest still pull", async t => {
  const s = await setup(t);
  await s.seed.append({ project: "proj", workstream: "p1", entries: [{ kind: "ledger", body: "one\n" }] });
  await s.seed.append({ project: "proj", workstream: "p2", entries: [{ kind: "ledger", body: "two\n" }, { kind: "checkpoint", body: "# p2\n" }] });
  s.stub.db.failures.push({ method: "GET", path: `/api/v1/worklog/workstreams/${s.stub.db.workstreams[1].id}/entries`, status: 503 });
  const ledger = await s.pull();
  assert.equal(ledger.code, 1);
  assert.match(ledger.stdout, /^failed: sdd\/p2\/progress\.md: darkmem answered 503: injected failure$/m);
  assert.equal(read(path.join(s.workRoot, "sdd", "p1", "progress.md")), "one\n");
  assert.equal(read(path.join(s.workRoot, "handoff", "latest.md")), "# p2\n");
  await s.seed.append({ project: "proj", workstream: "p1", entries: [{ kind: "checkpoint", body: "# p1\n" }] });
  s.stub.db.failures.push({ method: "GET", path: "/api/v1/worklog/resume", status: 503 });
  const resumes = () => s.stub.db.requests.filter(r => r.path === "/api/v1/worklog/resume").length;
  const before = resumes();
  const checkpoint = await s.pull();
  assert.equal(resumes() - before, 2, "the other workstream's checkpoint is still read");
  assert.equal(checkpoint.code, 1);
  assert.match(checkpoint.stdout, /^failed: handoff\/latest\.md: darkmem answered 503: injected failure \(reading workstream p2\); not pulled$/m);
  assert.equal(read(path.join(s.workRoot, "handoff", "latest.md")), "# p2\n", "without every checkpoint the newest is unknown");
  assert.equal(read(path.join(s.workRoot, "sdd", "p2", "progress.md")), "two\n");
});

test("checkpoints a microsecond apart are ordered by darkmem's clock, not rounded to the millisecond", async t => {
  const s = await setup(t);
  await s.seed.append({ project: "proj", workstream: "p1", entries: [{ kind: "checkpoint", body: "# A\n" }] });
  s.stub.db.workstreams[0].entries[0].created_at = "2026-09-25T10:00:00.000001+00:00";
  assert.equal((await s.pull()).code, 0);
  const latest = path.join(s.workRoot, "handoff", "latest.md");
  assert.equal(read(latest), "# A\n");
  await s.seed.append({ project: "proj", workstream: "p2", entries: [{ kind: "checkpoint", body: "# B\n" }] });
  await s.seed.append({ project: "proj", workstream: "p1", entries: [{ kind: "checkpoint", body: "# C\n" }] });
  s.stub.db.workstreams[1].entries[0].created_at = "2026-09-25T10:00:00.000002+00:00";
  s.stub.db.workstreams[0].entries[1].created_at = "2026-09-25T10:00:00.000003+00:00";
  assert.equal((await s.pull()).code, 0);
  assert.equal(read(latest), "# C\n", "p2 is listed first, and C is newer than B by one microsecond");
  assert.equal(s.state().checkpointAt, "2026-09-25T10:00:00.000003+00:00", "the string is the newest date");
  assert.deepEqual(s.state().checkpointAtByWorkstream, { p1: "2026-09-25T10:00:00.000003+00:00" });
});

test("latest.md stays the newest stop when the workstream that filed it closes", async t => {
  const s = await setup(t);
  await s.seed.append({ project: "proj", workstream: "p2", entries: [{ kind: "checkpoint", body: "# B\n" }] });
  await s.seed.append({ project: "proj", workstream: "p1", entries: [{ kind: "checkpoint", body: "# C\n" }] });
  assert.equal((await s.pull()).code, 0);
  const latest = path.join(s.workRoot, "handoff", "latest.md");
  assert.equal(read(latest), "# C\n");
  s.stub.db.workstreams.find(w => w.key === "p1").state = "closed";
  assert.equal((await s.pull()).code, 0);
  assert.equal(read(latest), "# C\n", "p2's older checkpoint does not replace p1's newer one");
});

test("an old state file's single checkpointAt gates a pull, which then records the workstream", async t => {
  const s = await setup(t);
  await s.seed.append({ project: "proj", workstream: "p1", entries: [{ kind: "checkpoint", body: "# A\n" }] });
  const filed = s.stub.db.workstreams[0].entries[0].created_at;
  const old = new Date(Date.parse(filed) + 500).toISOString();
  write(path.join(s.mirror, ".sync-state.json"), JSON.stringify({
    version: 1, documents: {}, ledgers: {}, checkpoint: null, checkpointAt: old, conflicts: [], pendingLinks: [], prefix: "dforge",
  }));
  const latest = path.join(s.workRoot, "handoff", "latest.md");
  assert.equal((await s.pull()).code, 0);
  assert.equal(fs.existsSync(latest), false, "a checkpoint older than the old value is not taken");
  await s.seed.append({ project: "proj", workstream: "p2", entries: [{ kind: "checkpoint", body: "# B\n" }] });
  assert.equal((await s.pull()).code, 0);
  assert.equal(read(latest), "# B\n");
  const recorded = s.stub.db.workstreams[1].entries[0].created_at;
  assert.equal(s.state().checkpointAt, recorded, "an older dforge reads a string");
  assert.deepEqual(s.state().checkpointAtByWorkstream, { "*": old, p2: recorded });
});

test("a latest.md that cannot be read is one failure, and the rest of the pull still lands", async t => {
  const s = await setup(t);
  await s.seed.putDocument({ project: "proj", uri: "dforge/a.md", content: "a\n" });
  await s.seed.append({ project: "proj", workstream: "p1", entries: [{ kind: "ledger", body: "one\n" }, { kind: "checkpoint", body: "# p1\n" }] });
  fs.mkdirSync(path.join(s.workRoot, "handoff", "latest.md"), { recursive: true });
  const result = await s.pull();
  assert.equal(result.code, 1, result.stdout + result.stderr);
  assert.match(result.stdout, /^failed: handoff\/latest\.md: could not be read \(EISDIR\); not pulled$/m);
  assert.equal((result.stdout.match(/^failed:/gm) ?? []).length, 1);
  assert.equal(read(path.join(s.docsRoot, "a.md")), "a\n");
  assert.equal(read(path.join(s.workRoot, "sdd", "p1", "progress.md")), "one\n");
});

test("a document that cannot be read is one failure, and the others are still pulled", async t => {
  const s = await setup(t);
  await s.seed.putDocument({ project: "proj", uri: "dforge/a.md", content: "a\n" });
  await s.seed.putDocument({ project: "proj", uri: "dforge/b.md", content: "b\n" });
  await s.seed.putDocument({ project: "proj", uri: "dforge/c.md", content: "c\n" });
  fs.mkdirSync(path.join(s.docsRoot, "b.md"), { recursive: true });
  const result = await s.pull();
  assert.equal(result.code, 1, result.stdout + result.stderr);
  assert.match(result.stdout, /^failed: dforge\/b\.md: the local copy could not be read or written \(EISDIR\); not pulled$/m);
  assert.equal((result.stdout.match(/^failed:/gm) ?? []).length, 1);
  assert.equal(read(path.join(s.docsRoot, "a.md")), "a\n");
  assert.equal(read(path.join(s.docsRoot, "c.md")), "c\n");
  assert.match(result.stdout, / 2 documents,/);
});

test("a checkpoint from a workstream key the directory rule refuses is pulled once and the state stays loadable", async t => {
  const s = await setup(t);
  await s.seed.append({ project: "proj", workstream: "feature/foo", entries: [{ kind: "checkpoint", body: "# Foo\n" }] });
  const first = await s.pull();
  assert.equal(first.code, 0, first.stdout + first.stderr);
  assert.match(first.stdout, / 1 checkpoints;/);
  assert.equal(read(path.join(s.workRoot, "handoff", "latest.md")), "# Foo\n");
  const second = await s.pull();
  assert.equal(second.code, 0, second.stdout + second.stderr);
  assert.match(second.stdout, / 0 checkpoints;/);
  assert.doesNotMatch(second.stdout + second.stderr, /valid sync state/);
});

test("pull refuses uris Windows cannot hold, and writes none of a set that differ only in case", async t => {
  const s = await setup(t);
  for (const uri of ["dforge/notes/a:b.md", "dforge/notes/CON.md", "dforge/handoff/a:b.md", "dforge/A.md", "dforge/a.md", "dforge/ok.md"]) {
    await s.seed.putDocument({ project: "proj", uri, content: `${uri}\n` });
  }
  const result = await s.pull();
  assert.equal(result.code, 1);
  assert.match(result.stdout, /^failed: dforge\/notes\/a:b\.md: the name "a:b\.md" holds a character Windows refuses, so not every mirror can hold it as a file; not pulled — rename it on darkmem by hand$/m);
  assert.match(result.stdout, /^failed: dforge\/notes\/CON\.md: the name "CON\.md" is a Windows device name/m);
  assert.match(result.stdout, /^failed: dforge\/handoff\/a:b\.md: the name "a:b\.md" holds a character Windows refuses/m, "a handoff uri is checked before it is mapped");
  assert.match(result.stdout, /^conflict: dforge\/A\.md, dforge\/a\.md: differ only in case, which a case-insensitive file system holds as one file; none of them pulled — rename or delete all but one on darkmem by hand \(the sync has no rename or delete route\)$/m);
  assert.deepEqual(fs.readdirSync(s.docsRoot), ["ok.md"]);
});

test("a pull whose manifest read fails keeps the conflicts it never re-checked", async t => {
  const s = await setup(t);
  await s.seed.putDocument({ project: "proj", uri: "dforge/a.md", content: "one\n" });
  await s.pull();
  write(path.join(s.docsRoot, "a.md"), "local\n");
  await s.seed.putDocument({ project: "proj", uri: "dforge/a.md", content: "remote\n" });
  assert.equal((await s.pull()).code, 1);
  s.stub.db.failures.push({ method: "GET", path: "/api/v1/documents/manifest", status: 503 });
  const failed = await s.pull();
  assert.equal(failed.code, 1);
  assert.match(failed.stdout, /^failed: document manifest: darkmem answered 503: .*; no document pulled$/m);
  const status = await run(["status"], { cwd: s.repo, env: s.env });
  assert.equal(status.code, 1);
  assert.match(status.stdout, /^conflict: dforge\/a\.md: changed locally and on darkmem/m);
});

test("pull writes only the applied families, a handoff note with progress", async t => {
  const s = await setup(t);
  const records = stores => fs.writeFileSync(path.join(s.home, ".dforge", "stores.json"), JSON.stringify({ [s.repo]: stores }));
  await s.seed.putDocument({ project: "proj", uri: "dforge/specs/a.md", content: "# A\n" });
  await s.seed.putDocument({ project: "proj", uri: "dforge/handoff/p1.md", content: "# Handoff\n" });
  await s.seed.append({ project: "proj", workstream: "p1", entries: [{ kind: "ledger", body: "one\n" }] });
  records({ documents: "darkmem", progress: "local" });
  const documents = await s.pull();
  assert.equal(documents.code, 0, documents.stdout + documents.stderr);
  assert.equal(read(path.join(s.docsRoot, "specs", "a.md")), "# A\n");
  assert.equal(fs.existsSync(path.join(s.workRoot, "sdd", "p1", "handoff.md")), false);
  assert.equal(fs.existsSync(path.join(s.workRoot, "sdd", "p1", "progress.md")), false);
  fs.rmSync(path.join(s.docsRoot, "specs", "a.md"));
  records({ documents: "local", progress: "darkmem" });
  const progress = await s.pull();
  assert.equal(progress.code, 0, progress.stdout + progress.stderr);
  assert.equal(read(path.join(s.workRoot, "sdd", "p1", "handoff.md")), "# Handoff\n");
  assert.equal(read(path.join(s.workRoot, "sdd", "p1", "progress.md")), "one\n");
  assert.equal(fs.existsSync(path.join(s.docsRoot, "specs", "a.md")), false);
});

test("pull never writes an archived copy", async t => {
  const s = await setup(t);
  await s.seed.putDocument({ project: "proj", uri: "dforge/archive/20261013T091502Z/specs/a.md", content: "old\n" });
  await s.seed.putDocument({ project: "proj", uri: "dforge/specs/b.md", content: "b\n" });
  const result = await s.pull();
  assert.equal(result.code, 0, result.stdout + result.stderr);
  assert.equal(fs.existsSync(path.join(s.docsRoot, "archive")), false);
  assert.deepEqual(Object.keys(s.state().documents), ["dforge/specs/b.md"]);
});

test("a document archived elsewhere is removed when unchanged and kept as a conflict when edited", async t => {
  const s = await setup(t);
  await s.seed.putDocument({ project: "proj", uri: "dforge/a.md", content: "a\n" });
  await s.seed.putDocument({ project: "proj", uri: "dforge/b.md", content: "b\n" });
  await s.pull();
  const id = uri => s.stub.db.documents.get(`proj\u0000${uri}`).id;
  await s.seed.moveDocument(id("dforge/a.md"), { uri: "dforge/archive/20261013T091502Z/a.md" });
  await s.seed.moveDocument(id("dforge/b.md"), { uri: "dforge/archive/20261013T091502Z/b.md" });
  write(path.join(s.docsRoot, "b.md"), "edited\n");
  const result = await s.pull();
  assert.equal(result.code, 1);
  assert.match(result.stdout, /^conflict: dforge\/b\.md: archived or deleted on darkmem, and changed locally; the local file stays — push it under a new name, or delete it$/m);
  assert.match(result.stdout, /darkmem-sync pull: 0 documents, 0 ledgers, 0 checkpoints, 1 removed; 1 conflicts, 0 failures/);
  assert.equal(fs.existsSync(path.join(s.docsRoot, "a.md")), false);
  assert.equal(read(path.join(s.docsRoot, "b.md")), "edited\n");
  assert.deepEqual(Object.keys(s.state().documents), ["dforge/b.md"]);
});

test("a local deletion waits for push while darkmem is unchanged; a changed copy or a lost docs root comes back", async t => {
  const s = await setup(t);
  await s.seed.putDocument({ project: "proj", uri: "dforge/a.md", content: "one\n" });
  await s.seed.putDocument({ project: "proj", uri: "dforge/b.md", content: "b\n" });
  await s.pull();
  fs.rmSync(path.join(s.docsRoot, "a.md"));
  const before = fetches(s.stub);
  assert.equal((await s.pull()).code, 0);
  assert.equal(fs.existsSync(path.join(s.docsRoot, "a.md")), false);
  assert.equal(fetches(s.stub), before, "nothing is fetched for a deletion push will archive");
  await s.seed.putDocument({ project: "proj", uri: "dforge/a.md", content: "two\n", expectedHash: sha("one\n") });
  const changed = await s.pull();
  assert.equal(changed.code, 0, changed.stdout + changed.stderr);
  assert.match(changed.stdout, /^note: dforge\/a\.md: deleted locally but changed on darkmem; darkmem's copy pulled back$/m);
  assert.equal(read(path.join(s.docsRoot, "a.md")), "two\n");
  fs.rmSync(s.docsRoot, { recursive: true });
  assert.equal((await s.pull()).code, 0);
  assert.equal(read(path.join(s.docsRoot, "a.md")), "two\n");
  assert.equal(read(path.join(s.docsRoot, "b.md")), "b\n");
});

test("a case-only rename on darkmem keeps the file a case-insensitive file system shares", async t => {
  const s = await setup(t);
  await s.seed.putDocument({ project: "proj", uri: "dforge/a.md", content: "a\n" });
  await s.pull();
  const id = s.stub.db.documents.get("proj\u0000dforge/a.md").id;
  await s.seed.moveDocument(id, { uri: "dforge/A.md" });
  // A hard link stands in for a case-insensitive file system: both names reach one file.
  fs.linkSync(path.join(s.docsRoot, "a.md"), path.join(s.docsRoot, "A.md"));
  const result = await s.pull();
  assert.equal(result.code, 0, result.stdout + result.stderr);
  assert.doesNotMatch(result.stdout, /removed/);
  assert.equal(read(path.join(s.docsRoot, "a.md")), "a\n");
  assert.deepEqual(Object.keys(s.state().documents), ["dforge/A.md"]);
});

test("a case-only rename on darkmem that also edits it keeps the file a case-insensitive file system shares", async t => {
  const s = await setup(t);
  await s.seed.putDocument({ project: "proj", uri: "dforge/a.md", content: "a\n" });
  await s.pull();
  const id = s.stub.db.documents.get("proj\u0000dforge/a.md").id;
  await s.seed.moveDocument(id, { uri: "dforge/A.md" });
  await s.seed.putDocument({ project: "proj", uri: "dforge/A.md", content: "A edited\n", expectedHash: sha("a\n") });
  // A hard link stands in for a case-insensitive file system: both names reach one file.
  fs.linkSync(path.join(s.docsRoot, "a.md"), path.join(s.docsRoot, "A.md"));
  const result = await s.pull();
  assert.equal(result.code, 1, result.stdout + result.stderr);
  assert.match(result.stdout, /^conflict: dforge\/A\.md: changed locally and on darkmem; move the local file aside/m);
  assert.doesNotMatch(result.stdout, /removed/);
  assert.equal(read(path.join(s.docsRoot, "a.md")), "a\n");
  assert.deepEqual(Object.keys(s.state().documents), []);
});

test("a vanished document whose local copy cannot be read is one failure, and the pull goes on", async t => {
  const s = await setup(t);
  await s.seed.putDocument({ project: "proj", uri: "dforge/a.md", content: "a\n" });
  await s.seed.putDocument({ project: "proj", uri: "dforge/b.md", content: "b\n" });
  assert.equal((await s.pull()).code, 0);
  const id = uri => s.stub.db.documents.get(`proj\u0000${uri}`).id;
  await s.seed.moveDocument(id("dforge/a.md"), { uri: "dforge/archive/20261013T091502Z/a.md" });
  await s.seed.moveDocument(id("dforge/b.md"), { uri: "dforge/archive/20261013T091502Z/b.md" });
  fs.rmSync(path.join(s.docsRoot, "a.md"));
  fs.mkdirSync(path.join(s.docsRoot, "a.md", "inner"), { recursive: true });
  const result = await s.pull();
  assert.equal(result.code, 1, result.stdout + result.stderr);
  assert.doesNotMatch(result.stderr, /unexpected error/);
  assert.match(result.stdout, /^failed: dforge\/a\.md: archived or deleted on darkmem, and the local copy could not be checked or removed \(\w+\); it stays$/m);
  assert.match(result.stdout, /darkmem-sync pull: 0 documents, 0 ledgers, 0 checkpoints, 1 removed; 0 conflicts, 1 failures/);
  assert.equal(fs.existsSync(path.join(s.docsRoot, "b.md")), false, "the next vanished document is still removed");
  assert.ok(fs.statSync(path.join(s.docsRoot, "a.md")).isDirectory());
  assert.deepEqual(Object.keys(s.state().documents), ["dforge/a.md"]);
});

test("a synced archive uri is never removed, even once darkmem no longer files it", async t => {
  const s = await setup(t);
  await s.seed.putDocument({ project: "proj", uri: "dforge/a.md", content: "a\n" });
  assert.equal((await s.pull()).code, 0);
  const archived = "dforge/archive/20261013T091502Z/old.md";
  const file = path.join(s.docsRoot, "archive", "20261013T091502Z", "old.md");
  write(file, "old\n");
  const state = s.state();
  state.documents[archived] = sha("old\n");
  fs.writeFileSync(path.join(s.mirror, ".sync-state.json"), JSON.stringify(state));
  const result = await s.pull();
  assert.equal(result.code, 0, result.stdout + result.stderr);
  assert.doesNotMatch(result.stdout, /removed/);
  assert.equal(read(file), "old\n");
  assert.equal(s.state().documents[archived], sha("old\n"));
});

test("a workstream list whose last page is exactly full ends without an empty page", async t => {
  const s = await setup(t, { pageSize: 2 });
  await s.seed.append({ project: "proj", workstream: "p1", entries: [{ kind: "ledger", body: "one\n" }] });
  await s.seed.append({ project: "proj", workstream: "p2", entries: [{ kind: "ledger", body: "two\n" }] });
  assert.equal((await s.pull()).code, 0);
  const lists = s.stub.db.requests.filter(r => r.path === "/api/v1/worklog/workstreams");
  assert.equal(lists.length, 1, "two open workstreams fill one page of two, and no empty page follows");
  assert.equal(read(path.join(s.workRoot, "sdd", "p2", "progress.md")), "two\n");
});

test("a sync state that cannot be saved stops the pull: exit 2, one line, and the lines gathered before it", async t => {
  const s = await setup(t);
  assert.equal((await s.pull()).code, 0);
  for (const uri of ["dforge/T.md", "dforge/t.md", "dforge/a.md", "dforge/b.md"]) {
    await s.seed.putDocument({ project: "proj", uri, content: `${uri}\n` });
  }
  const stateFile = path.join(s.mirror, ".sync-state.json");
  // The first document fetch turns the state file into a directory, so the
  // save after a.md is written fails.
  s.stub.db.onRequest = (method, pathname) => {
    if (method !== "GET" || pathname !== "/api/v1/documents/by-uri" || fs.statSync(stateFile).isDirectory()) return;
    fs.rmSync(stateFile);
    fs.mkdirSync(stateFile);
  };
  const result = await s.pull();
  assert.equal(result.code, 2, result.stdout + result.stderr);
  assert.equal(
    result.stderr.replace(/ could not be saved \(\w+\);/, " could not be saved (CODE);"),
    `darkmem-sync: ${stateFile} could not be saved (CODE); the run stopped, and the next run checks what this one wrote\n`,
  );
  assert.match(result.stdout, /^conflict: dforge\/T\.md, dforge\/t\.md: differ only in case/m);
  assert.doesNotMatch(result.stdout, /not pulled/);
  assert.doesNotMatch(result.stdout, /^darkmem-sync pull:/m);
  assert.equal(read(path.join(s.docsRoot, "a.md")), "dforge/a.md\n");
  assert.equal(fs.existsSync(path.join(s.docsRoot, "b.md")), false, "the pull stopped at the failed save");
  assert.equal(fs.existsSync(path.join(s.mirror, ".sync.lock")), false, "the lock is released");
});
