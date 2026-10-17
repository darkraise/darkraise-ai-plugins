import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";
import { ConfigError, resolveStores, runKey, storesPath, writeApplied } from "../../scripts/lib/darkmem-config.mjs";
import { KEY, git, makeHome, makeRepo, scratch, write } from "./helpers.mjs";

const MODULE = fileURLToPath(new URL("../../scripts/lib/darkmem-config.mjs", import.meta.url));
const applied = stores => [stores.documents.applied, stores.progress.applied];
const mapped = (repo, entry = {}, global = {}) => ({ darkmemEnabled: true, ...global, darkmem: { url: "http://127.0.0.1:9", repos: { [repo]: { project: "proj", ...entry } } } });

test("no config file and no record keep both families local in the checkout", () => {
  const repo = makeRepo();
  const { env } = makeHome({ repo, config: null, stores: null });
  const stores = resolveStores({ cwd: repo, env });
  assert.equal(stores.sync, null);
  assert.match(stores.reason, /^darkmem is disabled/);
  assert.deepEqual(stores.documents, { configured: "local", applied: "local", root: path.join(repo, "docs", "forge") });
  assert.deepEqual(stores.progress, {
    configured: "local", applied: "local",
    ledgerRoot: path.join(repo, ".forge", "sdd"), latestFile: path.join(repo, ".forge", "handoff", "latest.md"),
  });
});

test("a mapped repository applies each family as its record says", () => {
  const repo = makeRepo();
  const { env, mirror } = makeHome({ repo, url: "http://darkmem.test:8000/", stores: { documents: "darkmem", progress: "local" } });
  const stores = resolveStores({ cwd: repo, env });
  assert.equal(stores.reason, "project proj");
  assert.deepEqual(stores.documents, { configured: "darkmem", applied: "darkmem", root: path.join(mirror, "forge") });
  assert.deepEqual(stores.progress, {
    configured: "darkmem", applied: "local",
    ledgerRoot: path.join(repo, ".forge", "sdd"), latestFile: path.join(repo, ".forge", "handoff", "latest.md"),
  });
  assert.deepEqual(stores.sync, {
    project: "proj", enabled: true, url: "http://darkmem.test:8000", apiKey: KEY, keyEnv: "DARKMEM_API_KEY",
    mirror, statePath: path.join(mirror, ".sync-state.json"),
  });
  const both = resolveStores({ cwd: repo, env: makeHome({ repo }).env });
  assert.equal(both.progress.ledgerRoot, path.join(path.dirname(both.documents.root), "work", "sdd"));
  assert.equal(both.progress.latestFile, path.join(path.dirname(both.documents.root), "work", "handoff", "latest.md"));
});

test("the configured store: the mapping entry, then the global key, then darkmem; no environment variable", () => {
  const repo = makeRepo();
  const rows = [
    [{}, {}, "darkmem"],
    [{ documentStore: "local" }, {}, "local"],
    [{ documentStore: "local" }, { documentStore: "darkmem" }, "darkmem"],
    [{}, { documentStore: "local" }, "local"],
  ];
  for (const [global, entry, want] of rows) {
    const { env } = makeHome({ repo, config: mapped(repo, entry, global) });
    env.DR_FORGE_DOCUMENT_STORE = want === "local" ? "darkmem" : "local";
    assert.equal(resolveStores({ cwd: repo, env }).documents.configured, want, JSON.stringify({ global, entry }));
  }
  const { env } = makeHome({ repo, config: mapped(repo, { progressSource: "local" }) });
  env.DR_FORGE_PROGRESS_SOURCE = "darkmem";
  assert.equal(resolveStores({ cwd: repo, env }).progress.configured, "local");
});

test("an override or a record that is neither local nor darkmem is a ConfigError", () => {
  const repo = makeRepo();
  assert.throws(() => resolveStores({ cwd: repo, env: makeHome({ repo, config: mapped(repo, { documentStore: "cloud" }) }).env }), /sets documentStore to "cloud"; use local or darkmem/);
  assert.throws(() => resolveStores({ cwd: repo, env: makeHome({ repo, stores: { progress: "cloud" } }).env }), /progress for .* must be local or darkmem/);
  const { env, home } = makeHome({ repo });
  fs.writeFileSync(path.join(home, ".dforge", "stores.json"), "[]");
  assert.throws(() => resolveStores({ cwd: repo, env }), ConfigError);
});

test("with no record both families are applied local, whatever the mirror's sync state lists", () => {
  const repo = makeRepo();
  const { env, mirror } = makeHome({ repo, stores: null });
  write(path.join(mirror, ".sync-state.json"), JSON.stringify({
    version: 1, documents: { "forge/specs/a.md": "0".repeat(64), "forge/handoff/p1.md": "0".repeat(64) },
    ledgers: {}, checkpoint: null, checkpointAt: null, conflicts: [],
  }));
  assert.deepEqual(applied(resolveStores({ cwd: repo, env })), ["local", "local"]);
});

test("darkmemEnabled false configures both families local; a family in the mirror resolves there, unsynced", () => {
  const repo = makeRepo();
  const { env, mirror } = makeHome({ repo, enabled: "off", stores: { documents: "darkmem", progress: "local" } });
  const stores = resolveStores({ cwd: repo, env });
  assert.equal(stores.reason, "darkmem is disabled (darkmemEnabled is false)");
  assert.deepEqual([stores.documents.configured, stores.progress.configured], ["local", "local"]);
  assert.deepEqual(applied(stores), ["darkmem", "local"]);
  assert.equal(stores.documents.root, path.join(mirror, "forge"));
  assert.equal(stores.sync.enabled, false);
  assert.equal(stores.sync.url, "http://127.0.0.1:9");
  const off = makeHome({ repo, enabled: "off", stores: { documents: "local", progress: "local" } });
  assert.equal(resolveStores({ cwd: repo, env: off.env }).sync, null);
});

test("darkmemEnabled unset leaves a family a 2.x run put in the mirror where it is", () => {
  const repo = makeRepo();
  const { env } = makeHome({ repo, enabled: false, stores: { documents: "darkmem", progress: "local" } });
  const stores = resolveStores({ cwd: repo, env });
  assert.match(stores.reason, /off by default since dforge 3\.0 and darkmemEnabled is unset/);
  assert.deepEqual([stores.documents.configured, stores.progress.configured], ["darkmem", "local"]);
  assert.equal(stores.sync.enabled, false);
});

test("an unmapped family in the mirror resolves to the mirror its record names", () => {
  const repo = makeRepo();
  const { env, mirror } = makeHome({ repo, config: { darkmemEnabled: true, layout: "compact" } });
  const stores = resolveStores({ cwd: repo, env });
  assert.match(stores.reason, /has no darkmem section$/);
  assert.deepEqual([stores.documents.configured, stores.progress.configured], ["local", "local"]);
  assert.deepEqual(stores.sync, {
    project: "proj", enabled: false, url: null, apiKey: null, keyEnv: "DARKMEM_API_KEY",
    mirror, statePath: path.join(mirror, ".sync-state.json"),
  });
  const bare = makeHome({ repo, config: null, stores: null });
  fs.mkdirSync(path.join(bare.home, ".dforge"), { recursive: true });
  fs.writeFileSync(path.join(bare.home, ".dforge", "stores.json"), JSON.stringify({ [repo]: { documents: "darkmem", progress: "local" } }));
  assert.throws(() => resolveStores({ cwd: repo, env: bare.env }), /names no project and mirror/);
});

test("--mode names the project only while darkmem is enabled", () => {
  const repo = makeRepo();
  const mode = env => spawnSync(process.execPath, [MODULE, "--mode"], { cwd: repo, env, encoding: "utf8", timeout: 10000 }).stdout;
  assert.match(mode(makeHome({ repo }).env), /^project\tproj$/m);
  assert.doesNotMatch(mode(makeHome({ repo, enabled: "off" }).env), /^project/m);
});

test("a missing key keeps an applied-darkmem family on the mirror", () => {
  const repo = makeRepo();
  const { env, mirror } = makeHome({ repo });
  delete env.DARKMEM_API_KEY;
  const stores = resolveStores({ cwd: repo, env });
  assert.equal(stores.sync.apiKey, null);
  assert.equal(stores.documents.root, path.join(mirror, "forge"));
});

test("writeApplied records one family and keeps the other, with the project and mirror", () => {
  const repo = makeRepo();
  const { env } = makeHome({ repo, config: mapped(repo), stores: null });
  writeApplied(env, repo, { documents: "local", progress: "local" });
  writeApplied(env, repo, { documents: "darkmem" }, { project: "proj", mirror: "/m", unknown: undefined });
  assert.deepEqual(JSON.parse(fs.readFileSync(storesPath(env), "utf8")), { [repo]: { documents: "darkmem", progress: "local", project: "proj", mirror: "/m" } });
  assert.deepEqual(applied(resolveStores({ cwd: repo, env })), ["darkmem", "local"]);
});

test("a pre-2.0 checkout's directories and home are not read", () => {
  const repo = makeRepo();
  fs.mkdirSync(path.join(repo, "docs", "superpowers"), { recursive: true });
  fs.mkdirSync(path.join(repo, ".superpowers"), { recursive: true });
  const home = scratch("dms-home-");
  write(path.join(home, ".dr-superpowers", "config.json"), JSON.stringify(mapped(repo)));
  write(path.join(home, ".dforge", "config.json"), JSON.stringify({ darkmemEnabled: true }));
  const stores = resolveStores({ cwd: repo, env: { ...process.env, HOME: home } });
  assert.equal(stores.sync, null);
  assert.equal(stores.documents.root, path.join(repo, "docs", "forge"));
  assert.equal(stores.progress.ledgerRoot, path.join(repo, ".forge", "sdd"));
});

test("a linked worktree keeps local families in itself and latest.md in the primary checkout", () => {
  const repo = makeRepo();
  const { env } = makeHome({ repo, stores: { documents: "local", progress: "local" } });
  const worktree = path.join(scratch("dms-wt-"), "wt");
  git(repo, "worktree", "add", "-q", "-b", "wt", worktree);
  const stores = resolveStores({ cwd: worktree, env });
  assert.equal(stores.sync.project, "proj");
  assert.equal(stores.documents.root, path.join(worktree, "docs", "forge"));
  assert.equal(stores.progress.ledgerRoot, path.join(worktree, ".forge", "sdd"));
  assert.equal(stores.progress.latestFile, path.join(repo, ".forge", "handoff", "latest.md"));
});

test("an unmapped repository and no git repository are local", () => {
  const repo = makeRepo();
  const other = makeRepo();
  assert.match(resolveStores({ cwd: other, env: makeHome({ repo }).env }).reason, /^no darkmem mapping for /);
  const plain = scratch("dms-plain-");
  const stores = resolveStores({ cwd: plain, env: makeHome({ repo }).env });
  assert.equal(stores.reason, "not inside a git repository");
  assert.equal(stores.documents.root, null);
});

test("a malformed config file, a climbing project or a bad url is a ConfigError", () => {
  const repo = makeRepo();
  assert.throws(() => resolveStores({ cwd: repo, env: makeHome({ repo, config: "{not json" }).env }), ConfigError);
  assert.throws(() => resolveStores({ cwd: repo, env: makeHome({ repo, project: "../up" }).env }), /needs a project/);
  assert.throws(() => resolveStores({ cwd: repo, env: makeHome({ repo, url: "darkmem.test" }).env }), /darkmem\.url/);
});

test("--mode prints each family's applied store and roots and the project; a ConfigError exits 2 and no repository 3", () => {
  const repo = makeRepo();
  const { env, mirror } = makeHome({ repo, stores: { documents: "local", progress: "darkmem" } });
  const mode = (cwd, environment, args = ["--mode"]) => spawnSync(process.execPath, [MODULE, ...args], { cwd, env: environment, encoding: "utf8", timeout: 10000 });
  const result = mode(repo, env);
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.stdout, [
    `documents\tlocal\t${path.join(repo, "docs", "forge")}`,
    `progress\tdarkmem\t${path.join(mirror, "work", "sdd")}\t${path.join(mirror, "work", "handoff", "latest.md")}`,
    "project\tproj",
    "",
  ].join("\n"));
  const broken = mode(repo, makeHome({ repo, config: "{nope" }).env);
  assert.equal(broken.status, 2);
  assert.match(broken.stderr, /^darkmem-config: .*not valid JSON/);
  assert.equal(mode(scratch("dms-plain-"), env).status, 3);
  assert.equal(mode(repo, env, []).status, 2);
});

test("--mode DIR resolves that checkout from anywhere; an unmapped one prints no project line", () => {
  const repo = makeRepo();
  const { env, mirror } = makeHome({ repo });
  const mode = (cwd, args) => spawnSync(process.execPath, [MODULE, ...args], { cwd, env, encoding: "utf8", timeout: 10000 });
  const elsewhere = scratch("dms-plain-");
  const result = mode(elsewhere, ["--mode", repo]);
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.stdout, [
    `documents\tdarkmem\t${path.join(mirror, "forge")}`,
    `progress\tdarkmem\t${path.join(mirror, "work", "sdd")}\t${path.join(mirror, "work", "handoff", "latest.md")}`,
    "project\tproj",
    "",
  ].join("\n"));
  assert.equal(mode(path.dirname(repo), ["--mode", path.basename(repo)]).stdout, result.stdout, "a relative DIR resolves against the working directory");
  const unmapped = mode(elsewhere, ["--mode", makeRepo()]);
  assert.equal(unmapped.status, 0, unmapped.stderr);
  assert.doesNotMatch(unmapped.stdout, /^project\t/m);
  assert.equal(mode(elsewhere, ["--mode", elsewhere]).status, 3);
  const extra = mode(elsewhere, ["--mode", repo, "extra"]);
  assert.equal(extra.status, 2);
  assert.equal(extra.stderr, "usage: darkmem-config.mjs --mode [DIR]\n");
});

test("--mode runs through a symlinked plugin path", () => {
  const repo = makeRepo();
  const { env } = makeHome({ repo });
  const link = path.join(scratch("dms-link-"), "lib");
  fs.symlinkSync(path.dirname(MODULE), link, "dir");
  const result = spawnSync(process.execPath, [path.join(link, "darkmem-config.mjs"), "--mode"], { cwd: repo, env, encoding: "utf8", timeout: 10000 });
  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /^documents\t/);
});

test("--mode in a submodule falls back to the worktree for latest.md", () => {
  const outer = makeRepo();
  const inner = makeRepo();
  git(outer, "-c", "protocol.file.allow=always", "submodule", "add", "-q", inner, "sub");
  const sub = path.join(outer, "sub");
  const result = spawnSync(process.execPath, [MODULE, "--mode"], { cwd: sub, env: makeHome({ repo: sub }).env, encoding: "utf8", timeout: 10000 });
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.stdout.split("\n")[1].split("\t")[3], path.join(sub, ".forge", "handoff", "latest.md"));
});

test("the run key prefers the declared id, then the session record, then a day key", () => {
  const repo = makeRepo();
  const { home, env } = makeHome({ repo });
  assert.equal(runKey({ cwd: repo, env }), "sess-1");
  delete env.DR_FORGE_SESSION_ID;
  const now = new Date("2026-09-24T10:00:00Z");
  assert.equal(runKey({ cwd: repo, env, now }), `codex:${os.hostname()}:2026-09-24`);
  const sessions = path.join(home, ".claude", "dforge", "sessions");
  fs.mkdirSync(sessions, { recursive: true });
  fs.writeFileSync(path.join(sessions, `${repo.replace(/[^A-Za-z0-9]/g, "-")}.json`), JSON.stringify({ session_id: "abc-123" }));
  assert.equal(runKey({ cwd: repo, env, now }), "abc-123");
});

test("the pre-2.0 session id variable no longer declares the run", () => {
  const cwd = makeRepo();
  const HOME = scratch("dms-home-");
  assert.match(runKey({ cwd, env: { HOME, DR_SUPERPOWERS_SESSION_ID: "old-1" } }), /^codex:/);
  assert.equal(runKey({ cwd, env: { HOME, DR_FORGE_SESSION_ID: "new-1" } }), "new-1");
});
