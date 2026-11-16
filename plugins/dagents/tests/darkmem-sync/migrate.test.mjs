import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import test from "node:test";
import { createClient } from "../../scripts/lib/darkmem-client.mjs";
import { migrateHome } from "../../scripts/lib/dagents-home-migrate.mjs";
import { STUB_KEY, sha, startStub } from "./stub-server.mjs";
import { makeHome, makeRepo, read, run, scratch, write } from "./helpers.mjs";

// Every path under dir, each file with its content's hash: a dry run that
// rewrote a file fails the comparison, not only one that added or removed one.
const snapshot = dir => fs.readdirSync(dir, { recursive: true }).sort().map(name => {
  const file = path.join(dir, name);
  return fs.statSync(file).isDirectory() ? `${name}/` : `${name} ${sha(read(file))}`;
});
const STATE = documents => JSON.stringify({ version: 1, documents, ledgers: {}, checkpoint: null, checkpointAt: null, conflicts: [], pendingLinks: [] });

async function setup(t) {
  const stub = await startStub();
  t.after(() => stub.close());
  const repo = makeRepo();
  const home = makeHome({ repo, url: stub.url, stores: { documents: "darkmem", progress: "darkmem" } });
  const seed = createClient({ url: stub.url, apiKey: STUB_KEY, runKey: "seed" });
  return { stub, repo, seed, ...home, sync: (...args) => run(args, { cwd: repo, env: home.env }) };
}

test("a pre-3.0 mirror and darkmem's superpowers/ documents move to dagents/ before the first pull", async t => {
  const s = await setup(t);
  await s.seed.putDocument({ project: "proj", uri: "superpowers/specs/a.md", content: "# A\n" });
  await s.seed.putDocument({ project: "proj", uri: "superpowers/archive/20260101T000000Z/old.md", content: "old\n" });
  write(path.join(s.mirror, "superpowers", "specs", "a.md"), "# A\n");
  write(path.join(s.mirror, ".sync-state.json"), STATE({ "superpowers/specs/a.md": sha("# A\n") }));
  const result = await s.sync("pull");
  assert.equal(result.code, 0, result.stdout + result.stderr);
  assert.match(result.stdout, /renamed .*superpowers\/ to dagents\//);
  assert.equal(read(path.join(s.docsRoot, "specs", "a.md")), "# A\n");
  assert.equal(fs.existsSync(path.join(s.mirror, "superpowers")), false);
  const uris = [...s.stub.db.documents.keys()].map(key => key.split("\u0000")[1]).sort();
  assert.deepEqual(uris, ["dagents/archive/20260101T000000Z/old.md", "dagents/specs/a.md"]);
  const state = JSON.parse(read(path.join(s.mirror, ".sync-state.json")));
  assert.deepEqual(Object.keys(state.documents), ["dagents/specs/a.md"]);
  assert.equal(state.prefix, "dagents");
  const requests = s.stub.db.requests.length;
  assert.equal((await s.sync("pull")).code, 0);
  assert.equal(s.stub.db.requests.slice(requests).filter(r => r.method === "PATCH").length, 0, "nothing moves twice");
  assert.ok(s.stub.db.requests.length > requests);
});

test("a name darkmem holds under both prefixes refuses push and pull, and is never overwritten", async t => {
  const s = await setup(t);
  await s.seed.putDocument({ project: "proj", uri: "superpowers/a.md", content: "old\n" });
  await s.seed.putDocument({ project: "proj", uri: "dagents/a.md", content: "new\n" });
  for (const command of ["pull", "push"]) {
    const result = await s.sync(command);
    assert.equal(result.code, 2, result.stdout + result.stderr);
    assert.match(result.stderr, new RegExp(`${command} refused: darkmem still holds superpowers/ or forge/ documents`));
    assert.match(result.stdout, /^failed: superpowers\/a\.md: darkmem also holds dagents\/a\.md with other content; keep one$/m);
  }
  assert.equal(s.stub.db.documents.get("proj\u0000dagents/a.md").content, "new\n");
  assert.equal(JSON.parse(read(path.join(s.mirror, ".sync-state.json"))).prefix, undefined);
});

test("reconcile still moves a family back from the mirror while darkmem's uris cannot move", async t => {
  const s = await setup(t);
  write(path.join(s.home, ".dagents", "config.json"), JSON.stringify({
    darkmemEnabled: true, darkmem: { url: s.stub.url, api_key_env: "DARKMEM_API_KEY", repos: { [s.repo]: { project: "proj", documentStore: "local" } } },
  }));
  await s.seed.putDocument({ project: "proj", uri: "superpowers/a.md", content: "old\n" });
  await s.seed.putDocument({ project: "proj", uri: "dagents/a.md", content: "new\n" });
  write(path.join(s.docsRoot, "b.md"), "b\n");
  const result = await s.sync("reconcile");
  assert.equal(result.code, 1, result.stdout + result.stderr);
  assert.match(result.stdout, /^darkmem-sync reconcile: documents moved to local from the mirror, without darkmem \(darkmem still holds superpowers\/ or forge\/ documents/m);
  assert.equal(read(path.join(s.repo, "docs", "dagents", "b.md")), "b\n");
});

test("a dr-forge mirror and darkmem's forge/ documents move to dagents/, even after the 3.0 move", async t => {
  const s = await setup(t);
  await s.seed.putDocument({ project: "proj", uri: "forge/specs/a.md", content: "# A\n" });
  await s.seed.putDocument({ project: "proj", uri: "forge/archive/20260101T000000Z/old.md", content: "old\n" });
  write(path.join(s.mirror, "forge", "specs", "a.md"), "# A\n");
  write(path.join(s.mirror, ".sync-state.json"), JSON.stringify({
    version: 1, documents: { "forge/specs/a.md": sha("# A\n") }, ledgers: {}, checkpoint: null, checkpointAt: null, conflicts: [], pendingLinks: [], prefix: "forge",
  }));
  const result = await s.sync("pull");
  assert.equal(result.code, 0, result.stdout + result.stderr);
  assert.match(result.stdout, /renamed .*'s forge\/ to dagents\//);
  assert.equal(read(path.join(s.docsRoot, "specs", "a.md")), "# A\n");
  assert.equal(fs.existsSync(path.join(s.mirror, "forge")), false);
  const uris = [...s.stub.db.documents.keys()].map(key => key.split("\u0000")[1]).sort();
  assert.deepEqual(uris, ["dagents/archive/20260101T000000Z/old.md", "dagents/specs/a.md"]);
  const state = JSON.parse(read(path.join(s.mirror, ".sync-state.json")));
  assert.deepEqual(Object.keys(state.documents), ["dagents/specs/a.md"]);
  assert.equal(state.prefix, "dagents");
});

test("one name under superpowers/ and forge/ moves once; the second is refused, never overwritten", async t => {
  const s = await setup(t);
  await s.seed.putDocument({ project: "proj", uri: "superpowers/a.md", content: "old\n" });
  await s.seed.putDocument({ project: "proj", uri: "forge/a.md", content: "new\n" });
  const result = await s.sync("pull");
  assert.equal(result.code, 2, result.stdout + result.stderr);
  assert.match(result.stdout, /^failed: forge\/a\.md: darkmem also holds dagents\/a\.md with other content; keep one$/m);
  assert.equal(s.stub.db.documents.get("proj\u0000dagents/a.md").content, "old\n");
  assert.equal(s.stub.db.documents.get("proj\u0000forge/a.md").content, "new\n");
});

test("a mirror holding two docs folders is refused before anything syncs", async t => {
  const s = await setup(t);
  write(path.join(s.mirror, "forge", "a.md"), "a\n");
  write(path.join(s.mirror, "dagents", "b.md"), "b\n");
  const result = await s.sync("pull");
  assert.equal(result.code, 2, result.stdout + result.stderr);
  assert.match(result.stderr, /holds forge\/ and dagents\/; move all but one aside/);
  assert.equal(read(path.join(s.mirror, "forge", "a.md")), "a\n");
  assert.equal(s.stub.db.requests.length, 0);
});

test("a held lock on a pre-3.0 mirror refuses the command and changes nothing", async t => {
  const s = await setup(t);
  write(path.join(s.mirror, "superpowers", "a.md"), "a\n");
  fs.mkdirSync(path.join(s.mirror, ".sync.lock"), { recursive: true });
  const result = await s.sync("pull");
  assert.equal(result.code, 1);
  assert.match(result.stderr, /^darkmem-sync: pull refused: .* is still in an older layout and another darkmem-sync holds its lock/);
  assert.equal(fs.existsSync(s.docsRoot), false);
  assert.equal(s.stub.db.requests.length, 0);
});

test("a conflict line that names an old uri does not make a mirror pre-3.0", async t => {
  const s = await setup(t);
  write(path.join(s.mirror, ".sync-state.json"), JSON.stringify({
    version: 1, documents: {}, ledgers: {}, checkpoint: null, checkpointAt: null, conflicts: ["superpowers/a.md: old"], pendingLinks: [], prefix: "dagents",
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
  write(path.join(home, ".dagents", "mirror", "q", "kept"), "kept\n");
  const { lines, refused } = migrateHome({ HOME: home });
  assert.equal(refused, 1);
  const config = JSON.parse(read(path.join(home, ".dagents", "config.json")));
  assert.equal(config.darkmem.repos["/r"].project, "p");
  assert.equal(config.darkmemEnabled, undefined, "darkmem stays off until turned on");
  assert.ok(lines.some(line => line.includes("dagents-config set darkmemEnabled true")), lines.join("\n"));
  assert.equal(read(path.join(home, ".dagents", "mirror", "p", "dagents", "a.md")), "a\n");
  assert.deepEqual(Object.keys(JSON.parse(read(path.join(home, ".dagents", "mirror", "p", ".sync-state.json"))).documents), ["dagents/a.md"]);
  assert.ok(lines.some(line => line.startsWith("refused: ") && line.includes(path.join("mirror", "q"))), lines.join("\n"));
  assert.equal(read(path.join(old, "mirror", "q", "work", "x")), "x\n");
  const again = migrateHome({ HOME: home });
  assert.ok(again.lines.some(line => line.includes("already has a darkmem section")), again.lines.join("\n"));
});

test("migrateHome renames ~/.dr-forge whole and points stores.json at the moved mirror", () => {
  const home = scratch("dms-home-");
  const forge = path.join(home, ".dr-forge");
  write(path.join(forge, "config.json"), JSON.stringify({ handoffTokens: 325000 }));
  write(path.join(forge, "mirror", "p", "forge", "a.md"), "a\n");
  write(path.join(forge, "mirror", "p", ".sync-state.json"), STATE({ "forge/a.md": sha("a\n") }));
  write(path.join(forge, "stores.json"), JSON.stringify({ "/r": { project: "p", mirror: path.join(forge, "mirror", "p"), documents: "darkmem" } }));
  const { lines, refused } = migrateHome({ HOME: home });
  assert.equal(refused, 0, lines.join("\n"));
  assert.equal(fs.existsSync(forge), false);
  assert.equal(JSON.parse(read(path.join(home, ".dagents", "config.json"))).handoffTokens, 325000);
  assert.equal(JSON.parse(read(path.join(home, ".dagents", "stores.json")))["/r"].mirror, path.join(home, ".dagents", "mirror", "p"));
  assert.equal(read(path.join(home, ".dagents", "mirror", "p", "dagents", "a.md")), "a\n");
  assert.deepEqual(Object.keys(JSON.parse(read(path.join(home, ".dagents", "mirror", "p", ".sync-state.json"))).documents), ["dagents/a.md"]);
  assert.deepEqual(migrateHome({ HOME: home }), { lines: [], refused: 0 });
});

test("migrateHome writes config.json and stores.json holding the home lock", t => {
  const home = scratch("dms-home-");
  const forge = path.join(home, ".dr-forge");
  const dagents = path.join(home, ".dagents");
  const superpowers = path.join(home, ".dr-superpowers");
  write(path.join(forge, "config.json"), JSON.stringify({ handoffTokens: 325000 }));
  write(path.join(forge, "stores.json"), JSON.stringify({ "/r": { project: "p", mirror: path.join(forge, "mirror", "p") } }));
  write(path.join(forge, "mirror", "p", "forge", "a.md"), "a\n");
  write(path.join(dagents, "config.json"), JSON.stringify({ layout: "auto" }));
  write(path.join(superpowers, "config.json"), JSON.stringify({ darkmem: { url: "http://127.0.0.1:9" } }));
  const written = [];
  const writeFile = fs.writeFileSync;
  t.mock.method(fs, "writeFileSync", (file, ...rest) => {
    const name = /^\.(config|stores)\.json\./.exec(path.basename(String(file)))?.[1];
    if (name) written.push(`${name} ${fs.existsSync(path.join(dagents, ".lock", ".sync.lock")) ? "locked" : "unlocked"}`);
    return writeFile(file, ...rest);
  });
  const { lines, refused } = migrateHome({ HOME: home });
  assert.equal(refused, 0, lines.join("\n"));
  assert.deepEqual(written, ["config locked", "config locked", "stores locked"]);
});

test("migrateHome merges ~/.dr-forge into an existing ~/.dagents entry by entry", () => {
  const home = scratch("dms-home-");
  const forge = path.join(home, ".dr-forge");
  const dagents = path.join(home, ".dagents");
  write(path.join(forge, "config.json"), JSON.stringify({ handoffTokens: 325000, layout: "auto" }));
  write(path.join(dagents, "config.json"), JSON.stringify({ layout: "auto" }));
  write(path.join(forge, "same.txt"), "same\n");
  write(path.join(dagents, "same.txt"), "same\n");
  write(path.join(forge, "only-old.txt"), "old\n");
  write(path.join(forge, "mirror", "p", "work", "x"), "x\n");
  write(path.join(dagents, "mirror", "q", "kept"), "kept\n");
  const { lines, refused } = migrateHome({ HOME: home });
  assert.equal(refused, 0, lines.join("\n"));
  assert.deepEqual(JSON.parse(read(path.join(dagents, "config.json"))), { layout: "auto", handoffTokens: 325000 });
  assert.equal(read(path.join(dagents, "only-old.txt")), "old\n");
  assert.equal(read(path.join(dagents, "mirror", "p", "work", "x")), "x\n");
  assert.equal(read(path.join(dagents, "mirror", "q", "kept")), "kept\n");
  assert.equal(fs.existsSync(forge), false);
});

test("migrateHome refuses a key both configs set differently and keeps the old file", () => {
  const home = scratch("dms-home-");
  const forge = path.join(home, ".dr-forge");
  const dagents = path.join(home, ".dagents");
  write(path.join(forge, "config.json"), JSON.stringify({ handoffTokens: 325000 }));
  write(path.join(dagents, "config.json"), JSON.stringify({ handoffTokens: 200000 }));
  const { lines, refused } = migrateHome({ HOME: home });
  assert.equal(refused, 1);
  assert.ok(lines.some(line => line.startsWith("refused: ") && line.includes("set handoffTokens differently")), lines.join("\n"));
  assert.equal(JSON.parse(read(path.join(forge, "config.json"))).handoffTokens, 325000);
  assert.equal(JSON.parse(read(path.join(dagents, "config.json"))).handoffTokens, 200000);
});

test("migrateHome with dryRun writes nothing and says what would happen", () => {
  const home = scratch("dms-home-");
  const forge = path.join(home, ".dr-forge");
  write(path.join(forge, "config.json"), JSON.stringify({ handoffTokens: 325000 }));
  write(path.join(forge, "mirror", "p", "forge", "a.md"), "a\n");
  write(path.join(forge, "stores.json"), JSON.stringify({ "/r": { project: "p", mirror: path.join(forge, "mirror", "p") } }));
  write(path.join(home, ".dr-superpowers", "mirror", "q", "superpowers", "b.md"), "b\n");
  const before = snapshot(home);
  const { lines, refused } = migrateHome({ HOME: home }, { dryRun: true });
  assert.equal(refused, 0, lines.join("\n"));
  assert.deepEqual(snapshot(home), before);
  assert.ok(lines.every(line => line.startsWith("would ")), lines.join("\n"));
  assert.ok(lines.includes(`would move ${forge} to ${path.join(home, ".dagents")}`), lines.join("\n"));
  assert.ok(lines.some(line => line.startsWith("would point 1 ")), lines.join("\n"));
  assert.ok(lines.some(line => line.includes(`${path.join(forge, "mirror", "p")}'s forge/ to dagents/`)), lines.join("\n"));
  assert.ok(lines.some(line => line.includes(`${path.join(home, ".dr-superpowers", "mirror", "q")}'s superpowers/ to dagents/`)), lines.join("\n"));
});

test("migrateHome with dryRun, merging into an existing ~/.dagents, lists every action the real run takes", () => {
  const home = scratch("dms-home-");
  const forge = path.join(home, ".dr-forge");
  const dagents = path.join(home, ".dagents");
  write(path.join(dagents, "config.json"), JSON.stringify({ layout: "auto" }));
  write(path.join(forge, "config.json"), JSON.stringify({ handoffTokens: 325000 }));
  write(path.join(forge, "mirror", "p", "forge", "a.md"), "a\n");
  write(path.join(forge, "stores.json"), JSON.stringify({ "/r": { project: "p", mirror: path.join(forge, "mirror", "p") } }));
  const before = snapshot(home);
  const dry = migrateHome({ HOME: home }, { dryRun: true });
  assert.equal(dry.refused, 0, dry.lines.join("\n"));
  assert.deepEqual(snapshot(home), before);
  const real = migrateHome({ HOME: home });
  assert.equal(real.refused, 0, real.lines.join("\n"));
  const verb = line => line.replace(/^would /, "").split(" ")[0];
  const done = { merge: "merged", move: "moved", point: "pointed", rename: "renamed" };
  assert.deepEqual(real.lines.map(verb), ["merged", "moved", "moved", "pointed", "renamed"], real.lines.join("\n"));
  assert.deepEqual(dry.lines.map(line => done[verb(line)]), real.lines.map(verb), dry.lines.join("\n"));
});

test("migrateHome with dryRun foretells the refusals and darkmem lines a merge into ~/.dagents causes", () => {
  const home = scratch("dms-home-");
  const forge = path.join(home, ".dr-forge");
  const dagents = path.join(home, ".dagents");
  const superpowers = path.join(home, ".dr-superpowers");
  write(path.join(dagents, "config.json"), JSON.stringify({ layout: "auto" }));
  write(path.join(dagents, "mirror", "q", "kept"), "kept\n");
  write(path.join(forge, "config.json"), JSON.stringify({ darkmem: { repos: {} } }));
  write(path.join(forge, "mirror", "p", "work", "x"), "x\n");
  write(path.join(superpowers, "config.json"), JSON.stringify({ darkmem: { repos: {} } }));
  write(path.join(superpowers, "mirror", "p", "work", "y"), "y\n");
  const refusal = `refused: ${path.join(dagents, "mirror", "p")} exists, so ${path.join(superpowers, "mirror", "p")} was not moved`;
  const before = snapshot(home);
  const dry = migrateHome({ HOME: home }, { dryRun: true });
  assert.deepEqual(snapshot(home), before);
  assert.equal(dry.refused, 1, dry.lines.join("\n"));
  assert.ok(dry.lines.includes(refusal), dry.lines.join("\n"));
  assert.ok(dry.lines.some(line => line.includes("already has a darkmem section")), dry.lines.join("\n"));
  assert.ok(!dry.lines.some(line => line.startsWith("would copy the darkmem mapping")), dry.lines.join("\n"));
  assert.ok(!dry.lines.some(line => line.includes("darkmem is off")), dry.lines.join("\n"));
  const real = migrateHome({ HOME: home });
  assert.equal(real.refused, 1, real.lines.join("\n"));
  assert.ok(real.lines.includes(refusal), real.lines.join("\n"));
});

test("migrateHome merges the plain files under ~/.dr-forge/mirror into an existing ~/.dagents/mirror", () => {
  const home = scratch("dms-home-");
  const forge = path.join(home, ".dr-forge", "mirror");
  const dagents = path.join(home, ".dagents", "mirror");
  write(path.join(forge, "only-old.txt"), "old\n");
  write(path.join(forge, "same.txt"), "same\n");
  write(path.join(dagents, "same.txt"), "same\n");
  write(path.join(dagents, "q", "kept"), "kept\n");
  const dry = migrateHome({ HOME: home }, { dryRun: true });
  assert.equal(dry.refused, 0, dry.lines.join("\n"));
  assert.ok(dry.lines.includes(`would move ${path.join(forge, "only-old.txt")} to ${path.join(dagents, "only-old.txt")}`), dry.lines.join("\n"));
  assert.ok(dry.lines.includes(`would drop ${path.join(forge, "same.txt")}, the same as ${path.join(dagents, "same.txt")}`), dry.lines.join("\n"));
  const real = migrateHome({ HOME: home });
  assert.equal(real.refused, 0, real.lines.join("\n"));
  assert.equal(read(path.join(dagents, "only-old.txt")), "old\n");
  assert.equal(read(path.join(dagents, "same.txt")), "same\n");
  assert.equal(fs.existsSync(path.join(home, ".dr-forge")), false);

  const clash = scratch("dms-home-");
  const from = path.join(clash, ".dr-forge", "mirror", "notes.txt");
  const to = path.join(clash, ".dagents", "mirror", "notes.txt");
  write(from, "old\n");
  write(to, "new\n");
  const refusal = `refused: ${from} differs from ${to}; keep one by hand, then run dagents-migrate again`;
  assert.ok(migrateHome({ HOME: clash }, { dryRun: true }).lines.includes(refusal));
  const result = migrateHome({ HOME: clash });
  assert.equal(result.refused, 1, result.lines.join("\n"));
  assert.ok(result.lines.includes(refusal), result.lines.join("\n"));
  assert.equal(read(from), "old\n");
  assert.equal(read(to), "new\n");
});

test("migrateHome renames a mirror whose state alone holds forge/ uris", () => {
  const home = scratch("dms-home-");
  const mirror = path.join(home, ".dagents", "mirror", "p");
  write(path.join(mirror, ".sync-state.json"), JSON.stringify({
    version: 1, documents: { "forge/a.md": sha("a\n") }, ledgers: {}, checkpoint: null, checkpointAt: null, conflicts: [], pendingLinks: [],
  }));
  const { lines, refused } = migrateHome({ HOME: home });
  assert.equal(refused, 0, lines.join("\n"));
  assert.deepEqual(Object.keys(JSON.parse(read(path.join(mirror, ".sync-state.json"))).documents), ["dagents/a.md"]);
  assert.equal(fs.existsSync(path.join(mirror, "dagents")), false, "no folder is made for a state-only mirror");
});

test("migrateHome renames the old uris a mirror's pendingLinks hold", () => {
  const home = scratch("dms-home-");
  const mirror = path.join(home, ".dagents", "mirror", "p");
  write(path.join(mirror, ".sync-state.json"), JSON.stringify({
    version: 1, documents: {}, ledgers: {}, checkpoint: null, checkpointAt: null, conflicts: [], pendingLinks: ["superpowers/a.md", "forge/b.md", "dagents/c.md"],
  }));
  const { lines, refused } = migrateHome({ HOME: home });
  assert.equal(refused, 0, lines.join("\n"));
  assert.deepEqual(JSON.parse(read(path.join(mirror, ".sync-state.json"))).pendingLinks, ["dagents/a.md", "dagents/b.md", "dagents/c.md"]);
});

test("migrateHome names only the old prefixes a mirror's state holds", () => {
  const home = scratch("dms-home-");
  const mirrors = path.join(home, ".dagents", "mirror");
  write(path.join(mirrors, "p", ".sync-state.json"), JSON.stringify({
    version: 1, documents: { "forge/a.md": sha("a\n") }, ledgers: {}, checkpoint: null, checkpointAt: null, conflicts: [], pendingLinks: [],
  }));
  write(path.join(mirrors, "q", ".sync-state.json"), JSON.stringify({
    version: 1, documents: {}, ledgers: {}, checkpoint: null, checkpointAt: null, conflicts: [], pendingLinks: ["superpowers/b.md"],
  }));
  const dry = migrateHome({ HOME: home }, { dryRun: true });
  const real = migrateHome({ HOME: home });
  for (const [verb, lines] of [["would rename", dry.lines], ["renamed", real.lines]]) {
    assert.ok(lines.includes(`${verb} ${path.join(mirrors, "p")}'s forge/ to dagents/; darkmem's documents follow at its next sync`), lines.join("\n"));
    assert.ok(lines.includes(`${verb} ${path.join(mirrors, "q")}'s superpowers/ to dagents/; darkmem's documents follow at its next sync`), lines.join("\n"));
  }
});

test("migrateHome with dryRun lists a moved project mirror named mirror", () => {
  const home = scratch("dms-home-");
  const superpowers = path.join(home, ".dr-superpowers");
  write(path.join(superpowers, "mirror", "mirror", "superpowers", "b.md"), "b\n");
  const dry = migrateHome({ HOME: home }, { dryRun: true });
  assert.equal(dry.refused, 0, dry.lines.join("\n"));
  assert.ok(dry.lines.includes(`would rename ${path.join(superpowers, "mirror", "mirror")}'s superpowers/ to dagents/; darkmem's documents follow at its next sync`), dry.lines.join("\n"));
  const real = migrateHome({ HOME: home });
  assert.ok(real.lines.includes(`renamed ${path.join(home, ".dagents", "mirror", "mirror")}'s superpowers/ to dagents/; darkmem's documents follow at its next sync`), real.lines.join("\n"));
});

test("migrateHome with dryRun foretells a held lock and an unreadable sync state", () => {
  const home = scratch("dms-home-");
  const mirrors = path.join(home, ".dagents", "mirror");
  write(path.join(mirrors, "p", "forge", "a.md"), "a\n");
  fs.mkdirSync(path.join(mirrors, "p", ".sync.lock"), { recursive: true });
  write(path.join(mirrors, "q", "forge", "b.md"), "b\n");
  write(path.join(mirrors, "q", ".sync-state.json"), "{not json");
  const refusals = lines => lines.filter(line => line.startsWith("refused: ")).sort();
  const dry = migrateHome({ HOME: home }, { dryRun: true });
  const real = migrateHome({ HOME: home });
  assert.equal(real.refused, 2, real.lines.join("\n"));
  assert.equal(dry.refused, 2, dry.lines.join("\n"));
  assert.deepEqual(refusals(dry.lines), refusals(real.lines));
  assert.ok(!dry.lines.some(line => line.startsWith("would rename")), dry.lines.join("\n"));
});

test("migrateHome reports an old home it cannot remove", t => {
  const home = scratch("dms-home-");
  const forge = path.join(home, ".dr-forge");
  write(path.join(forge, "only-old.txt"), "old\n");
  write(path.join(home, ".dagents", "config.json"), "{}\n");
  // The suite may run as root, where permissions cannot make rmdir fail.
  const rmdir = fs.rmdirSync;
  t.mock.method(fs, "rmdirSync", dir => {
    if (dir === forge) throw Object.assign(new Error(`EACCES: permission denied, rmdir '${dir}'`), { code: "EACCES" });
    return rmdir(dir);
  });
  const { lines, refused } = migrateHome({ HOME: home });
  assert.equal(refused, 1, lines.join("\n"));
  assert.ok(lines.includes(`refused: ${forge} could not be removed: EACCES: permission denied, rmdir '${forge}'`), lines.join("\n"));
  assert.equal(read(path.join(home, ".dagents", "only-old.txt")), "old\n");
});

test("migrateHome refuses a config.json that is not a JSON object and keeps both files", () => {
  const home = scratch("dms-home-");
  const forge = path.join(home, ".dr-forge", "config.json");
  const dagents = path.join(home, ".dagents", "config.json");
  write(forge, JSON.stringify(["x"]));
  write(dagents, JSON.stringify({ layout: "auto" }));
  const refusal = `refused: ${forge} does not hold a JSON object; fix or delete it, then run dagents-migrate again`;
  const dry = migrateHome({ HOME: home }, { dryRun: true });
  assert.ok(dry.lines.includes(refusal), dry.lines.join("\n"));
  const { lines, refused } = migrateHome({ HOME: home });
  assert.equal(refused, 1, lines.join("\n"));
  assert.ok(lines.includes(refusal), lines.join("\n"));
  assert.deepEqual(JSON.parse(read(forge)), ["x"]);
  assert.deepEqual(JSON.parse(read(dagents)), { layout: "auto" });
});

test("migrateHome refuses a null config.json once and skips the darkmem copy", () => {
  const home = scratch("dms-home-");
  const forge = path.join(home, ".dr-forge", "config.json");
  const dagents = path.join(home, ".dagents", "config.json");
  write(forge, "{}\n");
  write(dagents, "null\n");
  write(path.join(home, ".dr-superpowers", "config.json"), JSON.stringify({ darkmem: { project: "p" } }));
  const dry = migrateHome({ HOME: home }, { dryRun: true });
  const real = migrateHome({ HOME: home });
  for (const { lines, refused } of [dry, real]) {
    assert.equal(refused, 1, lines.join("\n"));
    assert.equal(lines.filter(line => line.startsWith("refused: ") && line.includes(dagents)).length, 1, lines.join("\n"));
    assert.ok(!lines.some(line => line.startsWith("copied the darkmem mapping") || line.startsWith("would copy the darkmem mapping")), lines.join("\n"));
  }
  assert.equal(JSON.parse(read(dagents)), null);
  assert.equal(fs.existsSync(forge), true);
});

test("migrateHome refuses a string or array config.json for the darkmem copy without throwing", () => {
  for (const value of ["x", ["x"]]) {
    const home = scratch("dms-home-");
    const dagents = path.join(home, ".dagents", "config.json");
    write(dagents, JSON.stringify(value));
    write(path.join(home, ".dr-superpowers", "config.json"), JSON.stringify({ darkmem: { project: "p" } }));
    const { lines, refused } = migrateHome({ HOME: home });
    assert.equal(refused, 1, lines.join("\n"));
    assert.deepEqual(JSON.parse(read(dagents)), value);
    assert.ok(!lines.some(line => line.startsWith("copied the darkmem mapping")), lines.join("\n"));
  }
});

test("migrateHome refuses a malformed ~/.dr-forge config.json once and still moves the other entries", () => {
  const home = scratch("dms-home-");
  const forge = path.join(home, ".dr-forge");
  const dagents = path.join(home, ".dagents");
  write(path.join(forge, "config.json"), "{not json");
  write(path.join(dagents, "config.json"), JSON.stringify({ layout: "auto" }));
  write(path.join(forge, "only-old.txt"), "old\n");
  const refusals = lines => lines.filter(line => line.startsWith("refused: "));
  const dry = migrateHome({ HOME: home }, { dryRun: true });
  const real = migrateHome({ HOME: home });
  for (const { lines, refused } of [dry, real]) {
    assert.equal(refused, 1, lines.join("\n"));
    assert.equal(refusals(lines).length, 1, lines.join("\n"));
    assert.ok(refusals(lines)[0].startsWith(`refused: ${path.join(forge, "config.json")} could not be read: `), lines.join("\n"));
  }
  assert.deepEqual(refusals(dry.lines), refusals(real.lines));
  assert.equal(read(path.join(dagents, "only-old.txt")), "old\n");
  assert.equal(read(path.join(forge, "config.json")), "{not json");
  assert.deepEqual(JSON.parse(read(path.join(dagents, "config.json"))), { layout: "auto" });
});

test("migrateHome refuses an unreadable config or stores file once and finishes the run", () => {
  for (const [label, file, extra] of [
    ["~/.dagents/config.json", [".dagents", "config.json"], home => write(path.join(home, ".dr-superpowers", "config.json"), JSON.stringify({ darkmem: { project: "p" } }))],
    ["~/.dr-superpowers/config.json", [".dr-superpowers", "config.json"], () => {}],
    ["~/.dagents/stores.json", [".dagents", "stores.json"], () => {}],
  ]) {
    const home = scratch("dms-home-");
    const bad = path.join(home, ...file);
    const mirror = path.join(home, ".dagents", "mirror", "p");
    write(bad, "{not json");
    extra(home);
    write(path.join(mirror, "forge", "a.md"), "a\n");
    const dry = migrateHome({ HOME: home }, { dryRun: true });
    const real = migrateHome({ HOME: home });
    for (const [verb, { lines, refused }] of [["would rename", dry], ["renamed", real]]) {
      assert.equal(refused, 1, `${label}: ${lines.join("\n")}`);
      assert.equal(lines.filter(line => line.startsWith(`refused: ${bad} could not be read: `)).length, 1, `${label}: ${lines.join("\n")}`);
      assert.ok(lines.includes(`${verb} ${mirror}'s forge/ to dagents/; darkmem's documents follow at its next sync`), `${label}: ${lines.join("\n")}`);
    }
    assert.equal(read(bad), "{not json", label);
  }
});
