import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import test from "node:test";
import { createClient } from "../../scripts/lib/darkmem-client.mjs";
import { resolveStores, writeApplied } from "../../scripts/lib/darkmem-config.mjs";
import {
  inProgress, inProgressReason, nameSpellings, pendingFamilies, refreshContext, stayLine,
} from "../../scripts/lib/darkmem-reconcile.mjs";
import { STUB_KEY, sha, startStub } from "./stub-server.mjs";
import { git, makeHome, makeRepo, read, run, scratch, write } from "./helpers.mjs";

// A HOME mapping `repo` to project "proj" with the mapping entry's overrides,
// and stores.json recording `stores` (null: no record).
function mapped(repo, { url = "http://127.0.0.1:9", entry = {}, stores = { documents: "local", progress: "local" } } = {}) {
  return makeHome({ repo, url, stores, config: { darkmem: { url, api_key_env: "DARKMEM_API_KEY", repos: { [repo]: { project: "proj", ...entry } } } } });
}

// The command context's cfg, built as main builds it.
function cfgFor(cwd, env) {
  const stores = resolveStores({ cwd, env });
  return { ...stores.sync, repoRoot: stores.repoRoot, worktreeRoot: stores.worktreeRoot, documents: stores.documents, progress: stores.progress };
}

const reconcile = (cwd, env) => run(["reconcile"], { cwd, env });
const LEDGER = name => `# SDD ledger — plan: ${name}\nTask 1: complete (abc)\n`;
const storesOf = (home, repo) => JSON.parse(read(path.join(home, ".dr-forge", "stores.json")))[repo];

test("a document name has one key under either prefix", () => {
  assert.deepEqual(nameSpellings("docs/superpowers/plans/p.md"), ["docs/forge/plans/p.md", "docs/superpowers/plans/p.md"]);
  assert.deepEqual(nameSpellings("./docs/forge/plans/p.md"), ["docs/forge/plans/p.md", "docs/superpowers/plans/p.md"]);
  assert.deepEqual(nameSpellings("docs/superpowers"), ["docs/forge", "docs/superpowers"]);
  assert.deepEqual(nameSpellings("docs/superpowersx/a.md"), ["docs/superpowersx/a.md"]);
  assert.deepEqual(nameSpellings("/abs/docs/superpowers/a.md"), ["/abs/docs/superpowers/a.md"]);
});

test("pending families are those whose configured store differs from the applied one", () => {
  const repo = makeRepo();
  const { env } = mapped(repo, { entry: { progressSource: "local" } });
  const cfg = cfgFor(repo, env);
  assert.deepEqual(pendingFamilies(cfg), ["documents"]);
  assert.equal(stayLine(cfg, "documents", "why"), "darkmem-sync reconcile: documents stay local (configured darkmem): why");
});

test("refreshContext re-reads the stores, so a second move sees the roots the first produced", () => {
  const repo = makeRepo();
  const { env, docsRoot } = mapped(repo, { entry: { progressSource: "local" } });
  const context = { cfg: cfgFor(repo, env), env };
  assert.equal(context.cfg.documents.root, path.join(repo, "docs", "forge"));
  writeApplied(env, repo, { documents: "darkmem" });
  refreshContext(context);
  assert.equal(context.cfg.documents.applied, "darkmem");
  assert.equal(context.cfg.documents.root, docsRoot);
  assert.equal(context.roots.docsRoot, docsRoot);
  assert.deepEqual(context.roots.families, { documents: true, progress: false });
});

test("an unmapped repository is local mode", async () => {
  const repo = makeRepo();
  const { env } = makeHome({ repo, config: null });
  const result = await reconcile(repo, env);
  assert.equal(result.code, 0, result.stderr);
  assert.match(result.stdout, /^darkmem-sync: local mode — /);
});

test("with nothing to move reconcile prints nothing, takes no lock and calls nothing", async t => {
  const stub = await startStub();
  t.after(() => stub.close());
  const repo = makeRepo();
  const { env, mirror } = mapped(repo, { url: stub.url, entry: { documentStore: "local", progressSource: "local" } });
  const result = await reconcile(repo, env);
  assert.equal(result.code, 0, result.stderr);
  assert.equal(result.stdout, "");
  assert.equal(stub.db.requests.length, 0);
  assert.equal(fs.existsSync(path.join(mirror, ".sync.lock")), false);
});

test("with no record, a family whose files the sync state lists counts as applied darkmem", async () => {
  const repo = makeRepo();
  const { env, mirror } = mapped(repo, { entry: { progressSource: "local" }, stores: null });
  delete env.DARKMEM_API_KEY;
  const before = await reconcile(repo, env);
  assert.equal(before.code, 1);
  assert.equal(before.stdout, "darkmem-sync reconcile: documents stay local (configured darkmem): DARKMEM_API_KEY is not set\n");
  write(path.join(mirror, ".sync-state.json"), JSON.stringify({
    version: 1, documents: { "superpowers/specs/a.md": sha("a") }, ledgers: {}, checkpoint: null, checkpointAt: null, conflicts: [],
  }));
  const after = await reconcile(repo, env);
  assert.equal(after.code, 0, after.stderr);
  assert.equal(after.stdout, "");
});

test("each common refusal names every pending family and records nothing", async () => {
  const repo = makeRepo();
  const { env, home, mirror } = mapped(repo, { stores: null });
  const lines = reason => ["documents", "progress"].map(f => `darkmem-sync reconcile: ${f} stay local (configured darkmem): ${reason}`);
  const noKey = { ...env };
  delete noKey.DARKMEM_API_KEY;
  const missing = await reconcile(repo, noKey);
  assert.equal(missing.code, 1);
  assert.equal(missing.stdout, `${lines("DARKMEM_API_KEY is not set").join("\n")}\n`);
  const unreachable = await reconcile(repo, env);
  assert.equal(unreachable.code, 1);
  assert.equal(unreachable.stdout.split("\n").filter(line => /stay local \(configured darkmem\): darkmem is unreachable: /.test(line)).length, 2, unreachable.stdout);
  fs.mkdirSync(path.join(mirror, ".sync.lock"), { recursive: true });
  const locked = await reconcile(repo, env);
  assert.equal(locked.code, 1);
  assert.equal(locked.stdout, `${lines("another darkmem-sync holds the mirror lock").join("\n")}\n`);
  assert.equal(fs.existsSync(path.join(home, ".dr-forge", "stores.json")), false, "no refusal writes the record");
});

test("reconcile refuses every pending family while a plan is in progress", async t => {
  const stub = await startStub();
  t.after(() => stub.close());
  const repo = makeRepo();
  const { env } = mapped(repo, { url: stub.url });
  write(path.join(repo, ".forge", "sdd", "p1", "progress.md"), LEDGER("docs/forge/plans/p1.md"));
  write(path.join(repo, ".forge", "sdd", "p2", "progress.md"), LEDGER("docs/forge/plans/p2.md"));
  const result = await reconcile(repo, env);
  assert.equal(result.code, 1);
  assert.equal(result.stdout, [
    "darkmem-sync reconcile: documents stay local (configured darkmem): a plan is in progress: docs/forge/plans/p1.md",
    "  docs/forge/plans/p2.md",
    "darkmem-sync reconcile: progress stay local (configured darkmem): a plan is in progress: docs/forge/plans/p1.md",
    "  docs/forge/plans/p2.md",
    "",
  ].join("\n"));
  assert.equal(stub.db.requests.length, 0);
});

test("a ledger whose plan completed.md does not record is in progress, under either spelling", () => {
  const repo = makeRepo();
  const { env } = mapped(repo, { entry: { documentStore: "local", progressSource: "local" } });
  const completed = path.join(repo, "docs", "forge", "plans", "completed.md");
  write(path.join(repo, ".forge", "sdd", "p1", "progress.md"), LEDGER("docs/superpowers/plans/p1.md"));
  write(path.join(repo, "docs", "forge", "plans", "p1.md"), "# P1\n");
  assert.deepEqual(inProgress(cfgFor(repo, env)), ["docs/superpowers/plans/p1.md"]);
  write(completed, "- `docs/forge/plans/p1.md` — done\n");
  assert.deepEqual(inProgress(cfgFor(repo, env)), []);
  write(completed, "- `docs/superpowers/plans/p1.md` — done\n");
  assert.deepEqual(inProgress(cfgFor(repo, env)), []);
  write(completed, "- `docs/forge/plans/p10.md` — done\n");
  assert.deepEqual(inProgress(cfgFor(repo, env)), ["docs/superpowers/plans/p1.md"]);
});

test("every worktree's ledgers count while progress is local, and a ledger without an identity line is in progress", () => {
  const repo = makeRepo();
  const { env } = mapped(repo, { entry: { documentStore: "local", progressSource: "local" } });
  const linked = path.join(scratch("dms-wt-"), "wt");
  git(repo, "worktree", "add", "-q", linked);
  write(path.join(linked, ".forge", "sdd", "p2", "progress.md"), LEDGER("docs/forge/plans/p2.md"));
  write(path.join(repo, ".forge", "sdd", "odd", "progress.md"), "Task 1: complete (abc)\n");
  assert.deepEqual(inProgress(cfgFor(repo, env)).sort(), [path.join(repo, ".forge", "sdd", "odd", "progress.md"), "docs/forge/plans/p2.md"].sort());
});

test("while progress is applied darkmem only the mirror's ledgers count, resolved under the applied docs root", () => {
  const repo = makeRepo();
  const { env, docsRoot, workRoot } = mapped(repo, { stores: { documents: "darkmem", progress: "darkmem" } });
  write(path.join(repo, ".forge", "sdd", "local", "progress.md"), LEDGER("docs/forge/plans/local.md"));
  write(path.join(workRoot, "sdd", "p3", "progress.md"), LEDGER("docs/forge/plans/p3.md"));
  assert.deepEqual(inProgress(cfgFor(repo, env)), ["docs/forge/plans/p3.md"]);
  write(path.join(docsRoot, "plans", "completed.md"), "- `docs/superpowers/plans/p3.md`\n");
  assert.deepEqual(inProgress(cfgFor(repo, env)), []);
});

test("an active auto run is in progress", () => {
  const repo = makeRepo();
  const { env } = mapped(repo);
  const file = path.join(repo, ".forge", "sdd", "auto-run.json");
  write(file, JSON.stringify({ active: true, spec: "docs/forge/specs/s.md" }));
  assert.deepEqual(inProgress(cfgFor(repo, env)), ["an auto run is active"]);
  assert.deepEqual(inProgressReason({ cfg: cfgFor(repo, env) }), { reason: "a plan is in progress: an auto run is active", details: [] });
  write(file, JSON.stringify({ active: false }));
  assert.deepEqual(inProgress(cfgFor(repo, env)), []);
  assert.equal(inProgressReason({ cfg: cfgFor(repo, env) }), null);
});

test("an unreadable ledger is in progress, and a slug without a ledger is not", () => {
  const repo = makeRepo();
  const { env } = mapped(repo, { entry: { documentStore: "local", progressSource: "local" } });
  const ledger = path.join(repo, ".forge", "sdd", "bad", "progress.md");
  fs.mkdirSync(ledger, { recursive: true });
  fs.mkdirSync(path.join(repo, ".forge", "sdd", "empty"), { recursive: true });
  assert.deepEqual(inProgressReason({ cfg: cfgFor(repo, env) }), { reason: `a plan is in progress: ${ledger}`, details: [] });
});

test("a docs directory left in the checkout while documents are applied darkmem is named as not read", async () => {
  const repo = makeRepo();
  const { env } = mapped(repo, { entry: { progressSource: "local" }, stores: { documents: "darkmem", progress: "local" } });
  write(path.join(repo, "docs", "forge", "specs", "a.md"), "# A\n");
  const result = await reconcile(repo, env);
  assert.equal(result.code, 0, result.stderr);
  assert.equal(result.stdout, `darkmem-sync reconcile: ${path.join(repo, "docs", "forge")} is not read while documents are applied darkmem\n`);
});
