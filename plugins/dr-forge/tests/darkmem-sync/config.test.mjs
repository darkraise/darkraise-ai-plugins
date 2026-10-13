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
const mapped = (repo, entry = {}, global = {}) => ({ ...global, darkmem: { url: "http://127.0.0.1:9", repos: { [repo]: { project: "proj", ...entry } } } });

test("no config file keeps both families local in the checkout", () => {
  const repo = makeRepo();
  const { env } = makeHome({ repo, config: null });
  const stores = resolveStores({ cwd: repo, env });
  assert.equal(stores.sync, null);
  assert.match(stores.reason, /^no .*config\.json$/);
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
  assert.deepEqual(stores.documents, { configured: "darkmem", applied: "darkmem", root: path.join(mirror, "superpowers") });
  assert.deepEqual(stores.progress, {
    configured: "darkmem", applied: "local",
    ledgerRoot: path.join(repo, ".forge", "sdd"), latestFile: path.join(repo, ".forge", "handoff", "latest.md"),
  });
  assert.deepEqual(stores.sync, {
    project: "proj", url: "http://darkmem.test:8000", apiKey: KEY, keyEnv: "DARKMEM_API_KEY",
    mirror, statePath: path.join(mirror, ".sync-state.json"),
  });
  const both = resolveStores({ cwd: repo, env: makeHome({ repo }).env });
  assert.equal(both.progress.ledgerRoot, path.join(path.dirname(both.documents.root), "work", "sdd"));
  assert.equal(both.progress.latestFile, path.join(path.dirname(both.documents.root), "work", "handoff", "latest.md"));
});

test("the configured store: the mapping entry, then the environment, then the global key, then darkmem", () => {
  const repo = makeRepo();
  const rows = [
    [{}, {}, {}, "darkmem"],
    [{ documentStore: "local" }, {}, {}, "local"],
    [{ documentStore: "local" }, { DR_FORGE_DOCUMENT_STORE: "darkmem" }, {}, "darkmem"],
    [{ documentStore: "local" }, { DR_FORGE_DOCUMENT_STORE: "darkmem" }, { documentStore: "local" }, "local"],
    [{}, { DR_FORGE_DOCUMENT_STORE: "local" }, { documentStore: "darkmem" }, "darkmem"],
  ];
  for (const [global, variables, entry, want] of rows) {
    const { env } = makeHome({ repo, config: mapped(repo, entry, global) });
    Object.assign(env, variables);
    assert.equal(resolveStores({ cwd: repo, env }).documents.configured, want, JSON.stringify({ global, variables, entry }));
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
  fs.writeFileSync(path.join(home, ".dr-forge", "stores.json"), "[]");
  assert.throws(() => resolveStores({ cwd: repo, env }), ConfigError);
});

test("with no record a family is applied darkmem only when the mirror's sync state lists its files", () => {
  const repo = makeRepo();
  const { env, mirror } = makeHome({ repo, stores: null });
  const state = (documents, ledgers = {}) => write(path.join(mirror, ".sync-state.json"), JSON.stringify({
    version: 1, documents, ledgers, checkpoint: null, checkpointAt: null, conflicts: [],
  }));
  const hash = "0".repeat(64);
  assert.deepEqual(applied(resolveStores({ cwd: repo, env })), ["local", "local"]);
  state({ "superpowers/specs/a.md": hash });
  assert.deepEqual(applied(resolveStores({ cwd: repo, env })), ["darkmem", "local"]);
  state({ "superpowers/handoff/p1.md": hash });
  assert.deepEqual(applied(resolveStores({ cwd: repo, env })), ["local", "darkmem"]);
  state({}, { p1: { offset: 0, prefix: hash } });
  assert.deepEqual(applied(resolveStores({ cwd: repo, env })), ["local", "darkmem"]);
});

test("a missing key keeps an applied-darkmem family on the mirror", () => {
  const repo = makeRepo();
  const { env, mirror } = makeHome({ repo });
  delete env.DARKMEM_API_KEY;
  const stores = resolveStores({ cwd: repo, env });
  assert.equal(stores.sync.apiKey, null);
  assert.equal(stores.documents.root, path.join(mirror, "superpowers"));
});

test("writeApplied records one family and keeps the other", () => {
  const repo = makeRepo();
  const { env } = makeHome({ repo, stores: { documents: "local", progress: "local" } });
  writeApplied(env, repo, { documents: "darkmem" });
  assert.deepEqual(JSON.parse(fs.readFileSync(storesPath(env), "utf8")), { [repo]: { documents: "darkmem", progress: "local" } });
  assert.deepEqual(applied(resolveStores({ cwd: repo, env })), ["darkmem", "local"]);
});

test("a pre-2.0 checkout keeps its docs/superpowers and .superpowers", () => {
  const repo = makeRepo();
  fs.mkdirSync(path.join(repo, "docs", "superpowers"), { recursive: true });
  fs.mkdirSync(path.join(repo, ".superpowers"), { recursive: true });
  const stores = resolveStores({ cwd: repo, env: makeHome({ repo, config: null }).env });
  assert.equal(stores.documents.root, path.join(repo, "docs", "superpowers"));
  assert.equal(stores.progress.ledgerRoot, path.join(repo, ".superpowers", "sdd"));
});

test("the pre-2.0 config and mirror are used until the new ones exist", () => {
  const repo = makeRepo();
  const { home, env } = makeHome({ repo, legacy: true });
  const old = path.join(home, ".dr-superpowers", "mirror", "proj");
  fs.mkdirSync(old, { recursive: true });
  assert.equal(resolveStores({ cwd: repo, env }).sync.mirror, old);
  const next = path.join(home, ".dr-forge", "mirror", "proj");
  fs.mkdirSync(next, { recursive: true });
  assert.equal(resolveStores({ cwd: repo, env }).sync.mirror, next);
});

test("the new config wins over the pre-2.0 one", () => {
  const repo = makeRepo();
  const { home, env } = makeHome({ repo, legacy: true });
  fs.writeFileSync(path.join(home, ".dr-forge", "config.json"), JSON.stringify({ layout: "compact" }));
  assert.equal(resolveStores({ cwd: repo, env }).sync, null);
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

test("--mode prints each family's applied store and roots; a ConfigError exits 2 and no repository 3", () => {
  const repo = makeRepo();
  const { env, mirror } = makeHome({ repo, stores: { documents: "local", progress: "darkmem" } });
  const mode = (cwd, environment, args = ["--mode"]) => spawnSync(process.execPath, [MODULE, ...args], { cwd, env: environment, encoding: "utf8", timeout: 10000 });
  const result = mode(repo, env);
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.stdout, [
    `documents\tlocal\t${path.join(repo, "docs", "forge")}`,
    `progress\tdarkmem\t${path.join(mirror, "work", "sdd")}\t${path.join(mirror, "work", "handoff", "latest.md")}`,
    "",
  ].join("\n"));
  const broken = mode(repo, makeHome({ repo, config: "{nope" }).env);
  assert.equal(broken.status, 2);
  assert.match(broken.stderr, /^darkmem-config: .*not valid JSON/);
  assert.equal(mode(scratch("dms-plain-"), env).status, 3);
  assert.equal(mode(repo, env, []).status, 2);
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
  delete env.DR_SUPERPOWERS_SESSION_ID;
  const now = new Date("2026-09-24T10:00:00Z");
  assert.equal(runKey({ cwd: repo, env, now }), `codex:${os.hostname()}:2026-09-24`);
  const sessions = path.join(home, ".claude", "dr-forge", "sessions");
  fs.mkdirSync(sessions, { recursive: true });
  fs.writeFileSync(path.join(sessions, `${repo.replace(/[^A-Za-z0-9]/g, "-")}.json`), JSON.stringify({ session_id: "abc-123" }));
  assert.equal(runKey({ cwd: repo, env, now }), "abc-123");
});

// Carried over unchanged from the current file: it needs an empty HOME, not makeHome's mapping.
test("the pre-2.0 session id variable still declares the run, behind the new one", () => {
  const cwd = makeRepo();
  const HOME = scratch("dms-home-");
  assert.equal(runKey({ cwd, env: { HOME, DR_SUPERPOWERS_SESSION_ID: "old-1" } }), "old-1");
  assert.equal(runKey({ cwd, env: { HOME, DR_FORGE_SESSION_ID: "new-1", DR_SUPERPOWERS_SESSION_ID: "old-1" } }), "new-1");
});
