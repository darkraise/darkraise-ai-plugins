import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import test from "node:test";
import { createClient } from "../../scripts/lib/darkmem-client.mjs";
import { STUB_KEY, sha, startStub } from "./stub-server.mjs";
import { makeHome, makeRepo, read, run, write } from "./helpers.mjs";

const USAGE = "usage: darkmem-sync status | pull | push [--workstream KEY] | import [--replace] | restore NAME | revision NAME | reconcile\n";

async function setup(t, stubOptions = {}) {
  const stub = await startStub(stubOptions);
  t.after(() => stub.close());
  const repo = makeRepo();
  const home = makeHome({ repo, url: stub.url });
  const seed = createClient({ url: stub.url, apiKey: STUB_KEY, runKey: "seed" });
  const sync = (...args) => run(args, { cwd: repo, env: home.env });
  return { stub, repo, ...home, seed, sync };
}

test("revision prints the newest revision of a synced, unchanged document under the name given", async t => {
  const s = await setup(t);
  write(path.join(s.docsRoot, "notes", "n.md"), "one\n");
  await s.sync("push");
  write(path.join(s.docsRoot, "notes", "n.md"), "two\n");
  await s.sync("push");
  const newest = s.stub.db.documents.get("proj\u0000forge/notes/n.md").revisions.at(-1).id;
  for (const name of ["docs/forge/notes/n.md", "docs/superpowers/notes/n.md"]) {
    const result = await s.sync("revision", name);
    assert.equal(result.code, 0, result.stdout + result.stderr);
    assert.equal(result.stdout, `${name}@r${newest}\n`);
  }
});

test("revision refuses a document that is unsynced, edited, behind darkmem, missing or local", async t => {
  const s = await setup(t);
  write(path.join(s.docsRoot, "a.md"), "a\n");
  const unsynced = await s.sync("revision", "docs/forge/a.md");
  assert.equal(unsynced.code, 1);
  assert.equal(unsynced.stdout, "refused: docs/forge/a.md is not synced and unchanged: it was never synced\n");
  await s.sync("push");
  write(path.join(s.docsRoot, "a.md"), "edited\n");
  assert.match((await s.sync("revision", "docs/forge/a.md")).stdout, /: it changed since the last sync; push first\n$/);
  write(path.join(s.docsRoot, "a.md"), "a\n");
  await s.seed.putDocument({ project: "proj", uri: "forge/a.md", content: "remote\n" });
  assert.match((await s.sync("revision", "docs/forge/a.md")).stdout, /: darkmem's copy differs; pull first\n$/);
  assert.match((await s.sync("revision", "docs/forge/missing.md")).stdout, /missing\.md does not exist\n$/);
  fs.writeFileSync(path.join(s.home, ".dr-forge", "stores.json"), JSON.stringify({ [s.repo]: { documents: "local", progress: "darkmem" } }));
  const local = await s.sync("revision", "docs/forge/a.md");
  assert.equal(local.code, 1);
  assert.match(local.stdout, /: documents are applied local\n$/);
});

test("revision refuses a name that is a directory", async t => {
  const s = await setup(t);
  write(path.join(s.docsRoot, "notes", "n.md"), "n\n");
  const result = await s.sync("revision", "docs/forge/notes");
  assert.equal(result.code, 1, result.stdout + result.stderr);
  assert.equal(result.stderr, "");
  assert.match(result.stdout, /^refused: docs\/forge\/notes is not synced and unchanged: .*notes is not a file\n$/);
});

test("revision refuses when darkmem files a newer version between the manifest read and the revisions read", async t => {
  let armed = false;
  const s = await setup(t, {
    onRequest: (request, db) => {
      if (!armed || !request.path.endsWith("/revisions")) return;
      armed = false;
      const doc = db.documents.get("proj\u0000forge/a.md");
      Object.assign(doc, { content: "newer\n", content_hash: sha("newer\n") });
      doc.revisions.push({ id: db.nextRevision++, content_hash: sha("newer\n"), actor: "stub", api_key_id: null, created_at: new Date().toISOString() });
    },
  });
  write(path.join(s.docsRoot, "a.md"), "a\n");
  await s.sync("push");
  armed = true;
  const result = await s.sync("revision", "docs/forge/a.md");
  assert.equal(result.code, 1);
  assert.equal(result.stdout, "refused: docs/forge/a.md is not synced and unchanged: darkmem's newest revision differs; pull first\n");
});

test("revision refuses in an unmapped repository", async () => {
  const repo = makeRepo();
  const { env } = makeHome({ repo, config: null, stores: null });
  const result = await run(["revision", "docs/forge/a.md"], { cwd: repo, env });
  assert.equal(result.code, 1);
  assert.match(result.stdout, /^refused: docs\/forge\/a\.md is not synced and unchanged: local mode — darkmem is disabled \(darkmemEnabled is false\)\n$/);
});

test("a missing or extra argument is a usage error", async t => {
  const s = await setup(t);
  for (const args of [["revision"], ["revision", "a", "b"], ["status", "x"], ["push", "x"]]) {
    const result = await s.sync(...args);
    assert.equal(result.code, 2, args.join(" "));
    assert.equal(result.stderr, USAGE);
  }
});

test("restore moves the newest archived copy back under its hash and pulls it", async t => {
  const s = await setup(t);
  write(path.join(s.docsRoot, "specs", "a.md"), "one\n");
  await s.sync("push");
  fs.rmSync(path.join(s.docsRoot, "specs", "a.md"));
  await s.sync("push");
  await s.seed.putDocument({ project: "proj", uri: "forge/archive/20000101T000000Z/specs/a.md", content: "ancient\n" });
  const result = await s.sync("restore", "docs/superpowers/specs/a.md");
  assert.equal(result.code, 0, result.stdout + result.stderr);
  assert.match(result.stdout, /^restored: forge\/specs\/a\.md from forge\/archive\/\d{8}T\d{6}Z\/specs\/a\.md$/m);
  assert.doesNotMatch(result.stdout, /20000101T000000Z/);
  assert.match(result.stdout, /^darkmem-sync restore: 1 documents; 0 conflicts, 0 failures$/m);
  assert.equal(read(path.join(s.docsRoot, "specs", "a.md")), "one\n");
  const patch = s.stub.db.requests.filter(r => r.method === "PATCH").at(-1);
  assert.deepEqual(patch.body, { uri: "forge/specs/a.md", expected_hash: sha("one\n") });
});

test("restore brings the document back even when the sync state still holds the hash of the archived one", async t => {
  const s = await setup(t);
  write(path.join(s.docsRoot, "specs", "a.md"), "one\n");
  await s.sync("push");
  fs.rmSync(path.join(s.docsRoot, "specs", "a.md"));
  await s.sync("push");
  const statePath = path.join(s.mirror, ".sync-state.json");
  const state = JSON.parse(read(statePath));
  state.documents["forge/specs/a.md"] = sha("one\n");
  fs.writeFileSync(statePath, JSON.stringify(state));
  const result = await s.sync("restore", "docs/forge/specs/a.md");
  assert.equal(result.code, 0, result.stdout + result.stderr);
  assert.equal(read(path.join(s.docsRoot, "specs", "a.md")), "one\n");
  const again = await s.sync("push");
  assert.equal(again.code, 0, again.stdout + again.stderr);
  assert.ok(s.stub.db.documents.has("proj\u0000forge/specs/a.md"), "the next push does not archive it again");
});

test("restore refuses an occupied uri or a name with no archived copy, and needs documents applied darkmem", async t => {
  const s = await setup(t);
  await s.seed.putDocument({ project: "proj", uri: "forge/a.md", content: "live\n" });
  await s.seed.putDocument({ project: "proj", uri: "forge/archive/20261013T091502Z/a.md", content: "old\n" });
  const occupied = await s.sync("restore", "docs/forge/a.md");
  assert.equal(occupied.code, 1);
  assert.match(occupied.stdout, /^refused: forge\/a\.md is occupied on darkmem; move or rename that document first$/m);
  const none = await s.sync("restore", "docs/forge/b.md");
  assert.equal(none.code, 1);
  assert.match(none.stdout, /^refused: no archived copy of forge\/b\.md on darkmem$/m);
  assert.equal(s.stub.db.requests.some(r => r.method === "PATCH"), false);
  fs.writeFileSync(path.join(s.home, ".dr-forge", "stores.json"), JSON.stringify({ [s.repo]: { documents: "local", progress: "darkmem" } }));
  const local = await s.sync("restore", "docs/forge/a.md");
  assert.equal(local.code, 2);
  assert.equal(local.stderr, "darkmem-sync: restore needs documents applied darkmem\n");
});

test("restore takes only a document name and refuses in an unmapped repository", async t => {
  const s = await setup(t);
  await s.seed.putDocument({ project: "proj", uri: "forge/archive/20261013T091502Z/a.md", content: "old\n" });
  for (const name of [path.join(s.docsRoot, "a.md"), "a.md", "docs/forge/../a.md", "docs/forge/./a.md", "docs/forge/handoff/p1.md", "docs/forge/archive/20261013T091502Z/a.md"]) {
    const result = await s.sync("restore", name);
    assert.equal(result.code, 2, name);
    assert.equal(result.stderr, `darkmem-sync: ${name} does not name a document\n`);
  }
  assert.equal(s.stub.db.requests.some(r => r.method === "PATCH"), false);
  const repo = makeRepo();
  const { env } = makeHome({ repo, config: null, stores: null });
  const unmapped = await run(["restore", "docs/forge/a.md"], { cwd: repo, env });
  assert.equal(unmapped.code, 2);
  assert.equal(unmapped.stderr, "darkmem-sync: restore needs documents applied darkmem\n");
});
