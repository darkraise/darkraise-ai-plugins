import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";
import { createClient } from "../../../plugins/dagents/scripts/lib/darkmem-client.mjs";
import { migrateHome } from "../../../plugins/dagents/scripts/lib/dagents-home-migrate.mjs";
import { acquireLock } from "../../../plugins/dagents/scripts/lib/darkmem-mirror.mjs";
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

const MIGRATE = fileURLToPath(new URL("../../../plugins/dagents/scripts/dagents-migrate", import.meta.url));
// Spawned, not spawnSync: the stub darkmem answers from this process's event loop.
const runMigrate = (repo, env, ...args) => new Promise(resolve => {
  const child = spawn(process.env.DR_TEST_BASH ?? "bash", [MIGRATE, ...args, repo], { cwd: repo, env });
  let stdout = "";
  let stderr = "";
  child.stdout.on("data", chunk => { stdout += chunk; });
  child.stderr.on("data", chunk => { stderr += chunk; });
  const timer = setTimeout(() => child.kill("SIGKILL"), 120000);
  child.on("close", status => {
    clearTimeout(timer);
    resolve({ status, stdout, stderr });
  });
});

test("a dforge 4.x project's home record and darkmem data move to dagents, and dforge keeps the rest", async t => {
  const stub = await startStub();
  t.after(() => stub.close());
  const seed = createClient({ url: stub.url, apiKey: STUB_KEY, runKey: "seed" });
  const home = scratch("home-");
  const a = makeRepo(); const b = makeRepo();
  const dforgeHome = path.join(home, ".dforge");
  const mirrorA = path.join(dforgeHome, "mirror", "projA");
  write(path.join(dforgeHome, "config.json"), JSON.stringify({ autoRun: "off", darkmemEnabled: true, darkmem: { url: stub.url, repos: { [a]: { project: "projA" }, [b]: { project: "projB" } } } }));
  write(path.join(dforgeHome, "stores.json"), JSON.stringify({
    [a]: { documents: "darkmem", progress: "darkmem", project: "projA", mirror: mirrorA },
    [b]: { documents: "darkmem", progress: "darkmem", project: "projB", mirror: path.join(dforgeHome, "mirror", "projB") },
  }));
  write(path.join(mirrorA, "dforge", "plans", "p1.md"), "# P1\n");
  write(path.join(mirrorA, ".sync-state.json"), JSON.stringify({
    ...JSON.parse(STATE({ "dforge/plans/p1.md": sha("# P1\n") })), prefix: "dforge", remote: { url: stub.url, project: "projA" },
  }));
  await seed.putDocument({ project: "projA", uri: "dforge/plans/p1.md", content: "# P1\n" });
  await seed.append({ project: "projA", workstream: "p1", entries: [{ kind: "ledger", body: "Task 1: complete (abc)\n" }] });
  const env = { ...process.env, HOME: home, DARKMEM_API_KEY: STUB_KEY, CLAUDE_CONFIG_DIR: "" };

  const out = await runMigrate(a, env);
  assert.equal(out.status, 0, out.stdout + out.stderr);
  const dagentsConfig = JSON.parse(read(path.join(home, ".dagents", "config.json")));
  assert.equal(dagentsConfig.autoRun, "off");
  assert.equal(dagentsConfig.darkmem.repos[a].project, "projA");
  assert.equal(dagentsConfig.darkmem.repos[b], undefined);
  const dforgeStores = JSON.parse(read(path.join(dforgeHome, "stores.json")));
  assert.equal(dforgeStores[a], undefined);
  assert.equal(dforgeStores[b].project, "projB");
  assert.equal(JSON.parse(read(path.join(dforgeHome, "config.json"))).darkmem.repos[b].project, "projB");
  const dagentsStores = JSON.parse(read(path.join(home, ".dagents", "stores.json")));
  assert.match(dagentsStores[a].mirror, /\.dagents[\\/]mirror[\\/]projA$/);
  assert.equal(read(path.join(dagentsStores[a].mirror, "dagents", "plans", "p1.md")), "# P1\n");
  const movedState = read(path.join(dagentsStores[a].mirror, ".sync-state.json"));
  assert.equal(JSON.parse(movedState).documents["dagents/plans/p1.md"], sha("# P1\n"));
  assert.doesNotMatch(movedState, /dforge/);
  assert.equal(fs.existsSync(mirrorA), false);
  assert.ok(stub.db.workstreams.some(w => w.key === "dagents/p1"));
  assert.ok(stub.db.workstreams.some(w => w.key === "p1"), "the dforge workstream is kept");
  assert.ok(!stub.db.requests.some(r => r.method === "DELETE"));
  assert.match(out.stdout, /dforge\/ documents and workstreams were copied, not deleted; to delete them once no dforge checkout maps projA, run: /);

  const before = stub.db.requests.length;
  const sync = await run(["push"], { cwd: a, env: { ...env } });
  assert.equal(sync.code, 0, sync.stdout + sync.stderr);
  const after = stub.db.requests.slice(before);
  assert.ok(!after.some(r => r.method === "DELETE"));
  assert.ok(!after.some(r => r.method === "POST" && r.path === "/api/v1/documents"), "nothing is re-uploaded");
});

test("the migrate dry run lists the home steps and the variables to rename, and writes nothing", async t => {
  const stub = await startStub();
  t.after(() => stub.close());
  const home = scratch("home-");
  const a = makeRepo();
  write(path.join(home, ".dforge", "config.json"), JSON.stringify({ autoRun: "off", darkmem: { url: stub.url, repos: { [a]: { project: "projA" } } } }));
  write(path.join(home, ".dforge", "stores.json"), JSON.stringify({ [a]: { documents: "darkmem", progress: "darkmem", project: "projA", mirror: path.join(home, ".dforge", "mirror", "projA") } }));
  const env = { ...process.env, HOME: home, DARKMEM_API_KEY: STUB_KEY, CLAUDE_CONFIG_DIR: "", DFORGE_BUDGET: "200k" };
  const before = stub.db.requests.filter(r => r.method !== "GET").length;
  const out = await runMigrate(a, env, "--dry-run");
  assert.equal(out.status, 0, out.stdout + out.stderr);
  assert.match(out.stdout, /DFORGE_BUDGET .*DAGENTS_BUDGET/);
  assert.equal(fs.existsSync(path.join(home, ".dagents")), false);
  assert.equal(JSON.parse(read(path.join(home, ".dforge", "stores.json")))[a].project, "projA");
  assert.equal(stub.db.requests.filter(r => r.method !== "GET").length, before);
});

test("a darkmem copy that differs from its dforge original stops the home migration and deletes nothing", async t => {
  const stub = await startStub();
  t.after(() => stub.close());
  const seed = createClient({ url: stub.url, apiKey: STUB_KEY, runKey: "seed" });
  const home = scratch("home-");
  const a = makeRepo();
  const mirror = path.join(home, ".dforge", "mirror", "projA");
  write(path.join(home, ".dforge", "config.json"), JSON.stringify({ autoRun: "off", darkmem: { url: stub.url, repos: { [a]: { project: "projA" } } } }));
  write(path.join(home, ".dforge", "stores.json"), JSON.stringify({ [a]: { documents: "darkmem", progress: "darkmem", project: "projA", mirror } }));
  write(path.join(mirror, "dforge", "plans", "p1.md"), "# P1\n");
  await seed.putDocument({ project: "projA", uri: "dforge/plans/p1.md", content: "# P1\n" });
  await seed.putDocument({ project: "projA", uri: "dagents/plans/p1.md", content: "# P1, edited\n" });
  const out = await runMigrate(a, { ...process.env, HOME: home, DARKMEM_API_KEY: STUB_KEY, CLAUDE_CONFIG_DIR: "" });
  assert.equal(out.status, 1, out.stdout + out.stderr);
  assert.match(out.stdout, /refused: darkmem holds dagents\/plans\/p1\.md with other content than dforge\/plans\/p1\.md/);
  assert.doesNotMatch(out.stdout, /were copied, not deleted/);
  assert.equal(JSON.parse(read(path.join(home, ".dforge", "stores.json")))[a].project, "projA");
  assert.equal(read(path.join(mirror, "dforge", "plans", "p1.md")), "# P1\n");
  assert.equal(fs.existsSync(path.join(home, ".dagents")), false);
  assert.ok(!stub.db.requests.some(r => r.method === "DELETE"));
});

test("a mirror another dforge record still names is copied, not moved, and a closed workstream is copied closed", async t => {
  const stub = await startStub();
  t.after(() => stub.close());
  const seed = createClient({ url: stub.url, apiKey: STUB_KEY, runKey: "seed" });
  const home = scratch("home-");
  const a = makeRepo(); const b = makeRepo();
  const mirror = path.join(home, ".dforge", "mirror", "projA");
  write(path.join(home, ".dforge", "config.json"), JSON.stringify({ darkmem: { url: stub.url, repos: { [a]: { project: "projA" }, [b]: { project: "projA" } } } }));
  write(path.join(home, ".dforge", "stores.json"), JSON.stringify({
    [a]: { documents: "darkmem", progress: "darkmem", project: "projA", mirror },
    [b]: { documents: "darkmem", progress: "darkmem", project: "projA", mirror },
  }));
  write(path.join(mirror, "dforge", "plans", "p1.md"), "# P1\n");
  // A sync state, so the shared record alone keeps the source in place.
  write(path.join(mirror, ".sync-state.json"), JSON.stringify({
    ...JSON.parse(STATE({ "dforge/plans/p1.md": sha("# P1\n") })), prefix: "dforge", remote: { url: stub.url, project: "projA" },
  }));
  await seed.putDocument({ project: "projA", uri: "dforge/plans/p1.md", content: "# P1\n" });
  const done = await seed.append({ project: "projA", workstream: "done", entries: [{ kind: "ledger", body: "Task 1: complete (abc)\n" }] });
  await seed.updateWorkstream(done.workstream.id, { state: "closed" });
  const out = await runMigrate(a, { ...process.env, HOME: home, DARKMEM_API_KEY: STUB_KEY, CLAUDE_CONFIG_DIR: "" });
  assert.equal(out.status, 0, out.stdout + out.stderr);
  assert.match(out.stdout, /copied .*projA to .*\.dagents[\\/]mirror[\\/]projA \(another .* record still names it\)/);
  assert.equal(read(path.join(mirror, "dforge", "plans", "p1.md")), "# P1\n");
  assert.equal(read(path.join(home, ".dagents", "mirror", "projA", "dagents", "plans", "p1.md")), "# P1\n");
  const sourceState = JSON.parse(read(path.join(mirror, ".sync-state.json")));
  assert.deepEqual([sourceState.prefix, Object.keys(sourceState.documents)], ["dforge", ["dforge/plans/p1.md"]]);
  const copyState = JSON.parse(read(path.join(home, ".dagents", "mirror", "projA", ".sync-state.json")));
  assert.deepEqual([copyState.prefix, Object.keys(copyState.documents)], ["dagents", ["dagents/plans/p1.md"]]);
  const dforgeStores = JSON.parse(read(path.join(home, ".dforge", "stores.json")));
  assert.deepEqual([dforgeStores[a], dforgeStores[b].mirror], [undefined, mirror]);
  assert.equal(stub.db.workstreams.find(w => w.key === "dagents/done")?.state, "closed");
  assert.match(out.stdout, /worklog_purge \(project projA\) on the workstreams done;/);
});

test("a dforge record whose mirror path holds no mirror is refused and the path is left alone", async t => {
  const stub = await startStub();
  t.after(() => stub.close());
  const home = scratch("home-");
  const a = makeRepo();
  const notMirror = scratch("not-mirror-");
  write(path.join(notMirror, "keep.txt"), "mine\n");
  write(path.join(home, ".dforge", "config.json"), JSON.stringify({ darkmem: { url: stub.url, repos: { [a]: { project: "projA" } } } }));
  write(path.join(home, ".dforge", "stores.json"), JSON.stringify({ [a]: { documents: "local", progress: "local", project: "projA", mirror: notMirror } }));
  const out = await runMigrate(a, { ...process.env, HOME: home, DARKMEM_API_KEY: STUB_KEY, CLAUDE_CONFIG_DIR: "" });
  assert.equal(out.status, 1, out.stdout + out.stderr);
  assert.match(out.stdout, /refused: .*holds neither \.sync-state\.json nor dforge\//);
  assert.equal(read(path.join(notMirror, "keep.txt")), "mine\n");
  assert.equal(JSON.parse(read(path.join(home, ".dforge", "stores.json")))[a].mirror, notMirror);
  assert.equal(fs.existsSync(path.join(home, ".dagents")), false);
});

test("a dforge 4.x migrate keeps every value ~/.dagents already has", async t => {
  const stub = await startStub();
  t.after(() => stub.close());
  const home = scratch("home-");
  const a = makeRepo();
  write(path.join(home, ".dforge", "config.json"), JSON.stringify({ autoRun: "off", notifyAfter: 7, darkmem: { url: stub.url, repos: { [a]: { project: "projA" } } } }));
  write(path.join(home, ".dforge", "stores.json"), JSON.stringify({ [a]: { documents: "local", progress: "local", project: "projA" } }));
  write(path.join(home, ".dagents", "config.json"), JSON.stringify({ autoRun: "on" }));
  const out = await runMigrate(a, { ...process.env, HOME: home, DARKMEM_API_KEY: STUB_KEY, CLAUDE_CONFIG_DIR: "" });
  assert.equal(out.status, 0, out.stdout + out.stderr);
  const config = JSON.parse(read(path.join(home, ".dagents", "config.json")));
  assert.deepEqual([config.autoRun, config.notifyAfter, config.darkmem.repos[a].project], ["on", 7, "projA"]);
});

test("a ~/.dagents record, mapping or mirror that clashes with dforge's refuses the move and changes neither home", async t => {
  const stub = await startStub();
  t.after(() => stub.close());
  const cases = [
    ["a record setting documents differently", (home, a) => write(path.join(home, ".dagents", "stores.json"), JSON.stringify({ [a]: { documents: "darkmem", project: "projA" } })), /set documents differently for /],
    ["a mapping to another project", (home, a) => write(path.join(home, ".dagents", "config.json"), JSON.stringify({ darkmem: { url: stub.url, repos: { [a]: { project: "other" } } } })), /maps .* to another darkmem project than /],
    ["a mirror already in place", home => write(path.join(home, ".dagents", "mirror", "projA", "keep.md"), "mine\n"), /exists, so .* was not moved/],
  ];
  for (const [name, seed, refusal] of cases) {
    const home = scratch("home-");
    const a = makeRepo();
    const mirror = path.join(home, ".dforge", "mirror", "projA");
    write(path.join(mirror, "dforge", "plans", "p.md"), "# P\n");
    write(path.join(mirror, ".sync-state.json"), JSON.stringify({ ...JSON.parse(STATE({})), prefix: "dforge" }));
    write(path.join(home, ".dforge", "config.json"), JSON.stringify({ darkmem: { url: stub.url, repos: { [a]: { project: "projA" } } } }));
    write(path.join(home, ".dforge", "stores.json"), JSON.stringify({ [a]: { documents: "local", progress: "local", project: "projA", mirror } }));
    seed(home, a);
    // The home lock's file stays behind any run that took the lock; it holds no data.
    const tree = dir => fs.readdirSync(dir, { recursive: true }).filter(file => file !== ".lock").sort().map(file => {
      const full = path.join(dir, file);
      return fs.statSync(full).isFile() ? `${file}:${read(full)}` : file;
    });
    const before = [tree(path.join(home, ".dforge")), tree(path.join(home, ".dagents"))];
    const out = await runMigrate(a, { ...process.env, HOME: home, DARKMEM_API_KEY: STUB_KEY, CLAUDE_CONFIG_DIR: "" });
    assert.equal(out.status, 1, `${name}: ${out.stdout}${out.stderr}`);
    assert.match(out.stdout, refusal, name);
    assert.deepEqual([tree(path.join(home, ".dforge")), tree(path.join(home, ".dagents"))], before, `${name}: a home changed`);
  }
});

test("a dforge mirror holding no sync state is copied and left in place", async t => {
  const stub = await startStub();
  t.after(() => stub.close());
  const home = scratch("home-");
  const a = makeRepo();
  const mirror = scratch("mirror-");
  write(path.join(mirror, "dforge", "plans", "p.md"), "# P\n");
  write(path.join(mirror, "keep.txt"), "mine\n");
  write(path.join(home, ".dforge", "config.json"), JSON.stringify({ darkmem: { url: stub.url, repos: { [a]: { project: "projA" } } } }));
  write(path.join(home, ".dforge", "stores.json"), JSON.stringify({ [a]: { documents: "local", progress: "local", project: "projA", mirror } }));
  const out = await runMigrate(a, { ...process.env, HOME: home, DARKMEM_API_KEY: STUB_KEY, CLAUDE_CONFIG_DIR: "" });
  assert.equal(out.status, 0, out.stdout + out.stderr);
  assert.match(out.stdout, /copied .* \(it holds no \.sync-state\.json, so it was left in place\)/);
  assert.equal(read(path.join(mirror, "keep.txt")), "mine\n");
  assert.equal(read(path.join(home, ".dagents", "mirror", "projA", "dagents", "plans", "p.md")), "# P\n");
});

test("a dforge mirror a sync holds is refused before anything is copied to darkmem", async t => {
  const stub = await startStub();
  t.after(() => stub.close());
  const seed = createClient({ url: stub.url, apiKey: STUB_KEY, runKey: "seed" });
  const home = scratch("home-");
  const a = makeRepo();
  const mirror = path.join(home, ".dforge", "mirror", "projA");
  write(path.join(home, ".dforge", "config.json"), JSON.stringify({ darkmem: { url: stub.url, repos: { [a]: { project: "projA" } } } }));
  write(path.join(home, ".dforge", "stores.json"), JSON.stringify({ [a]: { documents: "darkmem", progress: "darkmem", project: "projA", mirror } }));
  write(path.join(mirror, "dforge", "plans", "p1.md"), "# P1\n");
  await seed.putDocument({ project: "projA", uri: "dforge/plans/p1.md", content: "# P1\n" });
  const release = acquireLock(mirror);
  t.after(() => release?.());
  const before = stub.db.requests.length;
  const out = await runMigrate(a, { ...process.env, HOME: home, DARKMEM_API_KEY: STUB_KEY, CLAUDE_CONFIG_DIR: "" });
  assert.equal(out.status, 1, out.stdout + out.stderr);
  assert.match(out.stdout, /refused: .*is held by a darkmem sync/);
  assert.deepEqual(stub.db.requests.slice(before).map(r => r.method), []);
  assert.equal(read(path.join(mirror, "dforge", "plans", "p1.md")), "# P1\n");
});
