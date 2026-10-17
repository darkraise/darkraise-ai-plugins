import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import test from "node:test";
import { createClient } from "../../scripts/lib/darkmem-client.mjs";
import { migrateHome } from "../../scripts/lib/dforge-home-migrate.mjs";
import { STUB_KEY, sha, startStub } from "./stub-server.mjs";
import { makeHome, makeRepo, read, run, scratch, write } from "./helpers.mjs";

const STATE = documents => JSON.stringify({ version: 1, documents, ledgers: {}, checkpoint: null, checkpointAt: null, conflicts: [], pendingLinks: [] });

async function setup(t) {
  const stub = await startStub();
  t.after(() => stub.close());
  const repo = makeRepo();
  const home = makeHome({ repo, url: stub.url, stores: { documents: "darkmem", progress: "darkmem" } });
  const seed = createClient({ url: stub.url, apiKey: STUB_KEY, runKey: "seed" });
  return { stub, repo, seed, ...home, sync: (...args) => run(args, { cwd: repo, env: home.env }) };
}

test("a pre-3.0 mirror and darkmem's superpowers/ documents move to dforge/ before the first pull", async t => {
  const s = await setup(t);
  await s.seed.putDocument({ project: "proj", uri: "superpowers/specs/a.md", content: "# A\n" });
  await s.seed.putDocument({ project: "proj", uri: "superpowers/archive/20260101T000000Z/old.md", content: "old\n" });
  write(path.join(s.mirror, "superpowers", "specs", "a.md"), "# A\n");
  write(path.join(s.mirror, ".sync-state.json"), STATE({ "superpowers/specs/a.md": sha("# A\n") }));
  const result = await s.sync("pull");
  assert.equal(result.code, 0, result.stdout + result.stderr);
  assert.match(result.stdout, /renamed .*superpowers\/ to dforge\//);
  assert.equal(read(path.join(s.docsRoot, "specs", "a.md")), "# A\n");
  assert.equal(fs.existsSync(path.join(s.mirror, "superpowers")), false);
  const uris = [...s.stub.db.documents.keys()].map(key => key.split("\u0000")[1]).sort();
  assert.deepEqual(uris, ["dforge/archive/20260101T000000Z/old.md", "dforge/specs/a.md"]);
  const state = JSON.parse(read(path.join(s.mirror, ".sync-state.json")));
  assert.deepEqual(Object.keys(state.documents), ["dforge/specs/a.md"]);
  assert.equal(state.prefix, "dforge");
  const requests = s.stub.db.requests.length;
  assert.equal((await s.sync("pull")).code, 0);
  assert.equal(s.stub.db.requests.slice(requests).filter(r => r.method === "PATCH").length, 0, "nothing moves twice");
  assert.ok(s.stub.db.requests.length > requests);
});

test("a name darkmem holds under both prefixes refuses push and pull, and is never overwritten", async t => {
  const s = await setup(t);
  await s.seed.putDocument({ project: "proj", uri: "superpowers/a.md", content: "old\n" });
  await s.seed.putDocument({ project: "proj", uri: "dforge/a.md", content: "new\n" });
  for (const command of ["pull", "push"]) {
    const result = await s.sync(command);
    assert.equal(result.code, 2, result.stdout + result.stderr);
    assert.match(result.stderr, new RegExp(`${command} refused: darkmem still holds pre-3\\.0 superpowers/ documents`));
    assert.match(result.stdout, /^failed: superpowers\/a\.md: darkmem also holds dforge\/a\.md with other content; keep one$/m);
  }
  assert.equal(s.stub.db.documents.get("proj\u0000dforge/a.md").content, "new\n");
  assert.equal(JSON.parse(read(path.join(s.mirror, ".sync-state.json"))).prefix, undefined);
});

test("reconcile still moves a family back from the mirror while darkmem's uris cannot move", async t => {
  const s = await setup(t);
  write(path.join(s.home, ".dforge", "config.json"), JSON.stringify({
    darkmemEnabled: true, darkmem: { url: s.stub.url, api_key_env: "DARKMEM_API_KEY", repos: { [s.repo]: { project: "proj", documentStore: "local" } } },
  }));
  await s.seed.putDocument({ project: "proj", uri: "superpowers/a.md", content: "old\n" });
  await s.seed.putDocument({ project: "proj", uri: "dforge/a.md", content: "new\n" });
  write(path.join(s.docsRoot, "b.md"), "b\n");
  const result = await s.sync("reconcile");
  assert.equal(result.code, 1, result.stdout + result.stderr);
  assert.match(result.stdout, /^darkmem-sync reconcile: documents moved to local from the mirror, without darkmem \(darkmem still holds pre-3\.0 superpowers\/ documents/m);
  assert.equal(read(path.join(s.repo, "docs", "dforge", "b.md")), "b\n");
});

test("a held lock on a pre-3.0 mirror refuses the command and changes nothing", async t => {
  const s = await setup(t);
  write(path.join(s.mirror, "superpowers", "a.md"), "a\n");
  fs.mkdirSync(path.join(s.mirror, ".sync.lock"), { recursive: true });
  const result = await s.sync("pull");
  assert.equal(result.code, 1);
  assert.match(result.stderr, /^darkmem-sync: pull refused: .* is still in the pre-3\.0 layout and another darkmem-sync holds its lock/);
  assert.equal(fs.existsSync(s.docsRoot), false);
  assert.equal(s.stub.db.requests.length, 0);
});

test("a conflict line that names an old uri does not make a mirror pre-3.0", async t => {
  const s = await setup(t);
  write(path.join(s.mirror, ".sync-state.json"), JSON.stringify({
    version: 1, documents: {}, ledgers: {}, checkpoint: null, checkpointAt: null, conflicts: ["superpowers/a.md: old"], pendingLinks: [], prefix: "dforge",
  }));
  const result = await s.sync("status");
  assert.equal(result.stderr, "");
  assert.match(result.stdout, /^conflict: superpowers\/a\.md: old$/m);
  assert.doesNotMatch(result.stdout, /renamed|pre-3\.0/);
});

test("migrateHome copies the darkmem mapping, moves each mirror and renames its folder", () => {
  const home = scratch("dms-home-");
  const old = path.join(home, ".dr-superpowers");
  write(path.join(old, "config.json"), JSON.stringify({ darkmem: { url: "http://h:8000", repos: { "/r": { project: "p" } } } }));
  write(path.join(old, "mirror", "p", "superpowers", "a.md"), "a\n");
  write(path.join(old, "mirror", "p", ".sync-state.json"), STATE({ "superpowers/a.md": sha("a\n") }));
  write(path.join(old, "mirror", "q", "work", "x"), "x\n");
  write(path.join(home, ".dforge", "mirror", "q", "kept"), "kept\n");
  const { lines, refused } = migrateHome({ HOME: home });
  assert.equal(refused, 1);
  const config = JSON.parse(read(path.join(home, ".dforge", "config.json")));
  assert.equal(config.darkmem.repos["/r"].project, "p");
  assert.equal(config.darkmemEnabled, undefined, "darkmem stays off until turned on");
  assert.ok(lines.some(line => line.includes("dforge-config set darkmemEnabled true")), lines.join("\n"));
  assert.equal(read(path.join(home, ".dforge", "mirror", "p", "dforge", "a.md")), "a\n");
  assert.deepEqual(Object.keys(JSON.parse(read(path.join(home, ".dforge", "mirror", "p", ".sync-state.json"))).documents), ["dforge/a.md"]);
  assert.ok(lines.some(line => line.startsWith("refused: ") && line.includes(path.join("mirror", "q"))), lines.join("\n"));
  assert.equal(read(path.join(old, "mirror", "q", "work", "x")), "x\n");
  const again = migrateHome({ HOME: home });
  assert.ok(again.lines.some(line => line.includes("already has a darkmem section")), again.lines.join("\n"));
});
