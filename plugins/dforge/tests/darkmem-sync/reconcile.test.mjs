import assert from "node:assert/strict";
import fs from "node:fs";
import net from "node:net";
import path from "node:path";
import test from "node:test";
import { createClient } from "../../scripts/lib/darkmem-client.mjs";
import { resolveStores, writeApplied } from "../../scripts/lib/darkmem-config.mjs";
import { loadState, utcStamp } from "../../scripts/lib/darkmem-mirror.mjs";
import { readNoFollow, readRegular } from "../../scripts/lib/darkmem-progress-move.mjs";
import {
  NOT_A_FILE, carriedDocuments, fileHash, inProgress, inProgressReason, nameSpellings, pendingFamilies, reconcile as reconcileInProcess, refreshContext, runGit, stayLine,
} from "../../scripts/lib/darkmem-reconcile.mjs";
import { STUB_KEY, sha, startStub } from "./stub-server.mjs";
import { git, makeHome, makeRepo, namedPipe, read, run, scratch, write } from "./helpers.mjs";

// A HOME mapping `repo` to project "proj" with the mapping entry's overrides,
// and stores.json recording `stores` (null: no record).
function mapped(repo, { url = "http://127.0.0.1:9", entry = {}, stores = { documents: "local", progress: "local" } } = {}) {
  return makeHome({ repo, url, stores, config: { darkmemEnabled: true, darkmem: { url, api_key_env: "DARKMEM_API_KEY", repos: { [repo]: { project: "proj", ...entry } } } } });
}

// The command context's cfg, built as main builds it.
function cfgFor(cwd, env) {
  const stores = resolveStores({ cwd, env });
  return { ...stores.sync, repoRoot: stores.repoRoot, worktreeRoot: stores.worktreeRoot, documents: stores.documents, progress: stores.progress };
}

const reconcile = (cwd, env) => run(["reconcile"], { cwd, env });
const LEDGER = name => `# SDD ledger — plan: ${name}\nTask 1: complete (abc)\n`;
// The applied stores only; the record also names the project and mirror.
const storesOf = (home, repo) => {
  const { documents, progress } = JSON.parse(read(path.join(home, ".dforge", "stores.json")))[repo];
  return { documents, progress };
};

test("a document name has one key under every prefix", () => {
  assert.deepEqual(nameSpellings("docs/superpowers/plans/p.md"), ["docs/dforge/plans/p.md", "docs/forge/plans/p.md", "docs/superpowers/plans/p.md"]);
  assert.deepEqual(nameSpellings("docs/forge/plans/p.md"), ["docs/dforge/plans/p.md", "docs/forge/plans/p.md", "docs/superpowers/plans/p.md"]);
  assert.deepEqual(nameSpellings("./docs/dforge/plans/p.md"), ["docs/dforge/plans/p.md", "docs/forge/plans/p.md", "docs/superpowers/plans/p.md"]);
  assert.deepEqual(nameSpellings("docs/superpowers"), ["docs/dforge", "docs/forge", "docs/superpowers"]);
  assert.deepEqual(nameSpellings("docs/forgex/a.md"), ["docs/forgex/a.md"]);
  assert.deepEqual(nameSpellings("docs/superpowersx/a.md"), ["docs/superpowersx/a.md"]);
  assert.deepEqual(nameSpellings("/abs/docs/superpowers/a.md"), ["/abs/docs/superpowers/a.md"]);
  assert.deepEqual(nameSpellings("docs/superpowers/"), ["docs/dforge", "docs/forge", "docs/superpowers"]);
  assert.deepEqual(nameSpellings("docs/forge/plans/"), ["docs/dforge/plans", "docs/forge/plans", "docs/superpowers/plans"]);
});

test("a directory or named pipe where a document should be hashes as a non-file instead of throwing or blocking", () => {
  const dir = scratch("dms-hash-");
  assert.equal(fileHash(dir), NOT_A_FILE);
  assert.equal(fileHash(path.join(dir, "absent.md")), null);
  write(path.join(dir, "a.md"), "a\n");
  assert.equal(fileHash(path.join(dir, "a.md")), sha("a\n"));
  assert.equal(fileHash(path.join(dir, "a.md", "below.md")), null);
  if (process.platform === "win32") return;
  fs.symlinkSync(path.join(dir, "a.md"), path.join(dir, "link.md"));
  assert.equal(fileHash(path.join(dir, "link.md")), sha("a\n"));
  assert.equal(fileHash(namedPipe(path.join(dir, "pipe.md"))), NOT_A_FILE);
});

test("a file swapped for a directory as fileHash opens it hashes as a non-file, not a crash", t => {
  const dir = scratch("dms-hash-");
  const file = path.join(dir, "a.md");
  write(file, "a\n");
  const open = fs.openSync;
  let swapped = false;
  t.mock.method(fs, "openSync", (target, ...rest) => {
    if (!swapped && target === file) {
      swapped = true;
      fs.rmSync(file);
      fs.mkdirSync(file);
    }
    return open(target, ...rest);
  });
  assert.equal(fileHash(file), NOT_A_FILE);
});

test("a Unix-domain socket where a document should be hashes as a non-file, and readRegular refuses it as EFTYPE", { skip: process.platform === "win32" }, async t => {
  const socket = path.join(scratch("dms-hash-"), "sock.md");
  const server = net.createServer();
  t.after(() => server.close());
  await new Promise((resolve, reject) => server.once("error", reject).listen(socket, resolve));
  assert.equal(fileHash(socket), NOT_A_FILE);
  assert.throws(() => readRegular(socket, { follow: true }), { code: "EFTYPE" });
  assert.throws(() => readNoFollow(socket), { code: "EFTYPE" });
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
  assert.equal(context.cfg.documents.root, path.join(repo, "docs", "dforge"));
  writeApplied(env, repo, { documents: "darkmem" });
  refreshContext(context);
  assert.equal(context.cfg.documents.applied, "darkmem");
  assert.equal(context.cfg.documents.root, docsRoot);
  assert.equal(context.roots.docsRoot, docsRoot);
  assert.deepEqual(context.roots.families, { documents: true, progress: false });
});

test("an unmapped repository is local mode", async () => {
  const repo = makeRepo();
  const { env } = makeHome({ repo, config: null, stores: null });
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
  assert.equal(fs.existsSync(path.join(home, ".dforge", "stores.json")), false, "no refusal writes the record");
});

test("reconcile refuses every pending family while a plan is in progress", async t => {
  const stub = await startStub();
  t.after(() => stub.close());
  const repo = makeRepo();
  const { env } = mapped(repo, { url: stub.url });
  write(path.join(repo, ".dforge", "sdd", "p1", "progress.md"), LEDGER("docs/dforge/plans/p1.md"));
  write(path.join(repo, ".dforge", "sdd", "p2", "progress.md"), LEDGER("docs/dforge/plans/p2.md"));
  const result = await reconcile(repo, env);
  assert.equal(result.code, 1);
  assert.equal(result.stdout, [
    "darkmem-sync reconcile: documents stay local (configured darkmem): a plan is in progress: docs/dforge/plans/p1.md",
    "  docs/dforge/plans/p2.md",
    "darkmem-sync reconcile: progress stay local (configured darkmem): a plan is in progress: docs/dforge/plans/p1.md",
    "  docs/dforge/plans/p2.md",
    "",
  ].join("\n"));
  assert.equal(stub.db.requests.length, 0);
});

test("a ledger whose plan completed.md does not record is in progress, under either spelling", () => {
  const repo = makeRepo();
  const { env } = mapped(repo, { entry: { documentStore: "local", progressSource: "local" } });
  const completed = path.join(repo, "docs", "dforge", "plans", "completed.md");
  write(path.join(repo, ".dforge", "sdd", "p1", "progress.md"), LEDGER("docs/superpowers/plans/p1.md"));
  write(path.join(repo, "docs", "dforge", "plans", "p1.md"), "# P1\n");
  assert.deepEqual(inProgress(cfgFor(repo, env)), ["docs/superpowers/plans/p1.md"]);
  write(completed, "- `docs/dforge/plans/p1.md` — done\n");
  assert.deepEqual(inProgress(cfgFor(repo, env)), []);
  write(completed, "- `docs/superpowers/plans/p1.md` — done\n");
  assert.deepEqual(inProgress(cfgFor(repo, env)), []);
  write(completed, "- `docs/dforge/plans/p10.md` — done\n");
  assert.deepEqual(inProgress(cfgFor(repo, env)), ["docs/superpowers/plans/p1.md"]);
});

test("every worktree's ledgers count while progress is local, and a ledger without an identity line is in progress", () => {
  const repo = makeRepo();
  const { env } = mapped(repo, { entry: { documentStore: "local", progressSource: "local" } });
  const linked = path.join(scratch("dms-wt-"), "wt");
  git(repo, "worktree", "add", "-q", linked);
  write(path.join(linked, ".dforge", "sdd", "p2", "progress.md"), LEDGER("docs/dforge/plans/p2.md"));
  write(path.join(repo, ".dforge", "sdd", "odd", "progress.md"), "Task 1: complete (abc)\n");
  assert.deepEqual(inProgress(cfgFor(repo, env)).sort(), [path.join(repo, ".dforge", "sdd", "odd", "progress.md"), "docs/dforge/plans/p2.md"].sort());
});

test("while progress is applied darkmem only the mirror's ledgers count, resolved under the applied docs root", () => {
  const repo = makeRepo();
  const { env, docsRoot, workRoot } = mapped(repo, { stores: { documents: "darkmem", progress: "darkmem" } });
  write(path.join(repo, ".dforge", "sdd", "local", "progress.md"), LEDGER("docs/dforge/plans/local.md"));
  write(path.join(workRoot, "sdd", "p3", "progress.md"), LEDGER("docs/dforge/plans/p3.md"));
  assert.deepEqual(inProgress(cfgFor(repo, env)), ["docs/dforge/plans/p3.md"]);
  write(path.join(docsRoot, "plans", "completed.md"), "- `docs/superpowers/plans/p3.md`\n");
  assert.deepEqual(inProgress(cfgFor(repo, env)), []);
});

test("an active auto run is in progress", () => {
  const repo = makeRepo();
  const { env } = mapped(repo);
  const file = path.join(repo, ".dforge", "sdd", "auto-run.json");
  write(file, JSON.stringify({ active: true, spec: "docs/dforge/specs/s.md" }));
  assert.deepEqual(inProgress(cfgFor(repo, env)), ["an auto run is active"]);
  assert.deepEqual(inProgressReason({ cfg: cfgFor(repo, env) }), { reason: "a plan is in progress: an auto run is active", details: [] });
  write(file, JSON.stringify({ active: false }));
  assert.deepEqual(inProgress(cfgFor(repo, env)), []);
  assert.equal(inProgressReason({ cfg: cfgFor(repo, env) }), null);
  if (process.platform === "win32") return;
  const record = path.join(scratch("dms-run-"), "auto-run.json");
  write(record, JSON.stringify({ active: true }));
  fs.rmSync(file);
  fs.symlinkSync(record, file);
  assert.deepEqual(inProgress(cfgFor(repo, env)), ["an auto run is active"], "a linked record is read through");
});

for (const [name, at] of [["auto-run.json", [".dforge", "sdd", "auto-run.json"]], ["completed.md", ["docs", "dforge", "plans", "completed.md"]]]) {
  test(`a named pipe at ${name} never blocks reconcile: it records no active run and no finished plan`, { skip: process.platform === "win32" }, async t => {
    const stub = await startStub();
    t.after(() => stub.close());
    const repo = makeRepo();
    const { env } = mapped(repo, { url: stub.url });
    write(path.join(repo, ".dforge", "sdd", "p1", "progress.md"), LEDGER("docs/dforge/plans/p1.md"));
    namedPipe(path.join(repo, ...at));
    const result = await reconcile(repo, env);
    assert.equal(result.code, 1, result.stdout + result.stderr);
    assert.equal(result.stdout, [
      "darkmem-sync reconcile: documents stay local (configured darkmem): a plan is in progress: docs/dforge/plans/p1.md",
      "darkmem-sync reconcile: progress stay local (configured darkmem): a plan is in progress: docs/dforge/plans/p1.md",
      "",
    ].join("\n"));
    assert.equal(stub.db.requests.length, 0);
  });
}

test("an unreadable ledger is in progress, and a slug without a ledger is not", () => {
  const repo = makeRepo();
  const { env } = mapped(repo, { entry: { documentStore: "local", progressSource: "local" } });
  const ledger = path.join(repo, ".dforge", "sdd", "bad", "progress.md");
  fs.mkdirSync(ledger, { recursive: true });
  fs.mkdirSync(path.join(repo, ".dforge", "sdd", "empty"), { recursive: true });
  assert.deepEqual(inProgressReason({ cfg: cfgFor(repo, env) }), { reason: `a plan is in progress: ${ledger}`, details: [] });
});

test("a docs directory left in the checkout while documents are applied darkmem is named as not read", async () => {
  const repo = makeRepo();
  const { env } = mapped(repo, { entry: { progressSource: "local" }, stores: { documents: "darkmem", progress: "local" } });
  write(path.join(repo, "docs", "dforge", "specs", "a.md"), "# A\n");
  const result = await reconcile(repo, env);
  assert.equal(result.code, 0, result.stderr);
  assert.equal(result.stdout, `darkmem-sync reconcile: ${path.join(repo, "docs", "dforge")} is not read while documents are applied darkmem\n`);
});

// A repository whose committed docs/dforge holds `files` (name -> content),
// mapped with documents configured darkmem; progress stays local. `stores` is
// the stores.json record (null: none); `stub` is passed to startStub.
async function docsRepo(t, files = { "specs/a.md": "# A\n" }, { stores = { documents: "local", progress: "local" }, stub: stubOptions = {} } = {}) {
  const stub = await startStub(stubOptions);
  t.after(() => stub.close());
  const repo = makeRepo();
  for (const [name, content] of Object.entries(files)) write(path.join(repo, "docs", "dforge", ...name.split("/")), content);
  git(repo, "add", "-A");
  git(repo, "commit", "-q", "-m", "docs");
  const home = mapped(repo, { url: stub.url, entry: { progressSource: "local" }, stores });
  const seed = createClient({ url: stub.url, apiKey: STUB_KEY, runKey: "seed" });
  return { stub, repo, seed, ...home, stores: () => storesOf(home.home, repo), reconcile: () => reconcile(repo, home.env) };
}

const commitAll = (repo, message) => {
  git(repo, "add", "-A");
  git(repo, "commit", "-q", "-m", message);
};
const writes = (stub, from = 0) => stub.db.requests.slice(from).filter(r => r.method === "POST" || r.method === "PATCH");
const at = (repo, name) => path.join(repo, ...name.split("/"));

test("documents move into darkmem: imported, pulled into the mirror, verified, and their deletion staged", async t => {
  const s = await docsRepo(t, { "specs/a.md": "# A\n", "plans/p.md": "# P\n**Spec:** docs/dforge/specs/a.md\n" });
  write(path.join(s.repo, "CLAUDE.md"), "See docs/superpowers/specs/a.md\n");
  write(path.join(s.repo, "README.md"), "No citations\n");
  commitAll(s.repo, "cite");
  await s.seed.putDocument({ project: "proj", uri: "dforge/specs/a.md", content: "# A\n" });
  const result = await s.reconcile();
  assert.equal(result.code, 0, result.stdout + result.stderr);
  assert.match(result.stdout, /^darkmem-sync reconcile: documents moved to darkmem$/m);
  assert.ok(result.stdout.includes(`  the deletion of docs/dforge is staged in ${s.repo}; commit it\n`), result.stdout);
  assert.ok(result.stdout.includes("    CLAUDE.md\n"), result.stdout);
  assert.doesNotMatch(result.stdout, /README\.md/);
  assert.equal(read(path.join(s.docsRoot, "plans", "p.md")), "# P\n**Spec:** docs/dforge/specs/a.md\n");
  assert.equal(s.stub.db.documents.size, 2);
  assert.equal(writes(s.stub).filter(r => r.body?.uri === "dforge/specs/a.md").length, 1, "the copy darkmem already held is not sent again");
  assert.equal(git(s.repo, "status", "--porcelain"), "D  docs/dforge/plans/p.md\nD  docs/dforge/specs/a.md");
  assert.equal(fs.existsSync(path.join(s.repo, "docs", "dforge")), false);
  assert.deepEqual(s.stores(), { documents: "darkmem", progress: "local" });
  const again = await s.reconcile();
  assert.equal(again.code, 0, again.stderr);
  assert.equal(again.stdout, "");
});

test("a docs directory with no tracked files moves without staging anything, and is then named as not read", async t => {
  const stub = await startStub();
  t.after(() => stub.close());
  const repo = makeRepo();
  fs.mkdirSync(path.join(repo, "docs", "dforge", "specs"), { recursive: true });
  const { env, home, docsRoot } = mapped(repo, { url: stub.url, entry: { progressSource: "local" } });
  await createClient({ url: stub.url, apiKey: STUB_KEY, runKey: "seed" }).putDocument({ project: "proj", uri: "dforge/specs/b.md", content: "# B\n" });
  const result = await reconcile(repo, env);
  assert.equal(result.code, 0, result.stdout + result.stderr);
  assert.match(result.stdout, /^darkmem-sync reconcile: documents moved to darkmem$/m);
  assert.ok(result.stdout.includes("  docs/dforge holds no tracked files; nothing to stage\n"), result.stdout);
  assert.ok(result.stdout.includes(`darkmem-sync reconcile: ${path.join(repo, "docs", "dforge")} is not read while documents are applied darkmem\n`), result.stdout);
  assert.equal(read(path.join(docsRoot, "specs", "b.md")), "# B\n");
  assert.equal(git(repo, "status", "--porcelain"), "");
  assert.deepEqual(storesOf(home, repo), { documents: "darkmem", progress: "local" });
});

test("the citation list stops at 20 and counts the rest, and does not refuse the move", async t => {
  const s = await docsRepo(t);
  for (let i = 0; i < 23; i += 1) write(path.join(s.repo, "cite", `f${String(i).padStart(2, "0")}.md`), "docs/dforge/specs/a.md\n");
  commitAll(s.repo, "cite");
  const result = await s.reconcile();
  assert.equal(result.code, 0, result.stdout + result.stderr);
  assert.ok(result.stdout.includes("    cite/f19.md\n"), result.stdout);
  assert.doesNotMatch(result.stdout, /cite\/f20\.md/);
  assert.ok(result.stdout.includes("  and 3 more\n"), result.stdout);
});

const caseFolds = (() => {
  const dir = scratch("dms-case-");
  fs.writeFileSync(path.join(dir, "a"), "");
  return fs.existsSync(path.join(dir, "A"));
})();
const UNCARRIED = [
  { kind: "a dotfile at depth", named: "docs/dforge/specs/.draft.md", plant: repo => write(at(repo, "docs/dforge/specs/.draft.md"), "x\n") },
  { kind: "a dot directory", named: "docs/dforge/.cache/x.md", plant: repo => write(at(repo, "docs/dforge/.cache/x.md"), "x\n") },
  { kind: "a symbolic link", named: "docs/dforge/link.md", skip: process.platform === "win32", plant: repo => fs.symlinkSync("specs/a.md", at(repo, "docs/dforge/link.md")) },
  { kind: "a file under handoff/", named: "docs/dforge/handoff/x.md", plant: repo => write(at(repo, "docs/dforge/handoff/x.md"), "x\n") },
  { kind: "a file under archive/", named: "docs/dforge/archive/x.md", plant: repo => write(at(repo, "docs/dforge/archive/x.md"), "x\n") },
  { kind: "an empty file", named: "docs/dforge/empty.md", plant: repo => write(at(repo, "docs/dforge/empty.md"), "") },
  { kind: "a file that is not UTF-8", named: "docs/dforge/bin.md", plant: repo => write(at(repo, "docs/dforge/bin.md"), Buffer.from([0x41, 0xff, 0x0a])) },
  { kind: "a name uriProblem rejects", named: "docs/dforge/specs/aux.md", skip: process.platform === "win32", plant: repo => write(at(repo, "docs/dforge/specs/aux.md"), "x\n") },
  { kind: "a case twin", named: "docs/dforge/specs/A.md", skip: caseFolds, plant: repo => write(at(repo, "docs/dforge/specs/A.md"), "# twin\n") },
  {
    kind: "an ignored file", named: "docs/dforge/secret.md",
    plant: repo => {
      write(at(repo, ".gitignore"), "docs/dforge/secret.md\n");
      write(at(repo, "docs/dforge/secret.md"), "s\n");
    },
  },
];

for (const { kind, named, plant, skip = false } of UNCARRIED) {
  test(`documents stay local when the docs directory holds ${kind}`, { skip }, async t => {
    const s = await docsRepo(t);
    plant(s.repo);
    commitAll(s.repo, "plant");
    const result = await s.reconcile();
    assert.equal(result.code, 1, result.stdout + result.stderr);
    assert.match(result.stdout, /^darkmem-sync reconcile: documents stay local \(configured darkmem\): docs\/dforge holds files the move cannot carry$/m);
    assert.ok(result.stdout.includes(`  ${named}`), result.stdout);
    assert.deepEqual(writes(s.stub), []);
    assert.equal(s.stub.db.documents.size, 0);
    assert.deepEqual(s.stores(), { documents: "local", progress: "local" });
    assert.equal(git(s.repo, "status", "--porcelain"), "");
  });
}

test("documents stay local while the docs directory has uncommitted changes", async t => {
  const s = await docsRepo(t);
  write(path.join(s.repo, "docs", "dforge", "specs", "a.md"), "# A edited\n");
  write(path.join(s.repo, "docs", "dforge", "new.md"), "new\n");
  const result = await s.reconcile();
  assert.equal(result.code, 1);
  assert.match(result.stdout, /^darkmem-sync reconcile: documents stay local \(configured darkmem\): docs\/dforge has uncommitted changes$/m);
  assert.match(result.stdout, /^ {3}M docs\/dforge\/specs\/a\.md$/m);
  assert.match(result.stdout, /^ {2}\?\? docs\/dforge\/new\.md$/m);
  assert.deepEqual(writes(s.stub), []);
});

test("an intent-to-add rename in the docs directory is one uncommitted change", async t => {
  const s = await docsRepo(t);
  fs.renameSync(at(s.repo, "docs/dforge/specs/a.md"), at(s.repo, "docs/dforge/specs/b.md"));
  git(s.repo, "add", "-N", "docs/dforge/specs/b.md");
  const result = await s.reconcile();
  assert.equal(result.code, 1, result.stdout + result.stderr);
  assert.equal(result.stdout, [
    "darkmem-sync reconcile: documents stay local (configured darkmem): docs/dforge has uncommitted changes",
    "   R docs/dforge/specs/a.md -> docs/dforge/specs/b.md",
    "",
  ].join("\n"));
  assert.deepEqual(writes(s.stub), []);
});

test("documents stay local while a linked worktree holds documents the primary checkout does not", async t => {
  const s = await docsRepo(t);
  const tree = path.join(scratch("dms-tree-"), "wt");
  git(s.repo, "worktree", "add", "-q", "-b", "feature", tree);
  write(at(tree, "docs/dforge/specs/b.md"), "# B\n");
  commitAll(tree, "spec b");
  write(at(tree, "docs/dforge/specs/c.md"), "# C draft\n");
  const result = await s.reconcile();
  assert.equal(result.code, 1);
  assert.match(result.stdout, /^darkmem-sync reconcile: documents stay local \(configured darkmem\): a linked worktree holds documents the primary checkout does not; merge or remove them first$/m);
  assert.ok(result.stdout.includes(`  ${tree}: docs/dforge/specs/b.md\n`), result.stdout);
  assert.ok(result.stdout.includes(`  ${tree}: docs/dforge/specs/c.md\n`), result.stdout);
  assert.deepEqual(writes(s.stub), []);
  assert.deepEqual(s.stores(), { documents: "local", progress: "local" });
});

test("an intent-to-add rename in a linked worktree names only the new path", async t => {
  const s = await docsRepo(t);
  const tree = path.join(scratch("dms-tree-"), "wt");
  git(s.repo, "worktree", "add", "-q", "-b", "feature", tree);
  fs.renameSync(at(tree, "docs/dforge/specs/a.md"), at(tree, "docs/dforge/specs/b.md"));
  git(tree, "add", "-N", "docs/dforge/specs/b.md");
  const result = await s.reconcile();
  assert.equal(result.code, 1, result.stdout + result.stderr);
  assert.match(result.stdout, /^darkmem-sync reconcile: documents stay local \(configured darkmem\): a linked worktree holds documents the primary checkout does not; merge or remove them first$/m);
  assert.deepEqual(result.stdout.split("\n").filter(line => line.startsWith(`  ${tree}: `)), [`  ${tree}: docs/dforge/specs/b.md`]);
  assert.deepEqual(writes(s.stub), []);
});

test("a linked worktree holding only the primary checkout's documents does not refuse the move", async t => {
  const s = await docsRepo(t);
  git(s.repo, "worktree", "add", "-q", "-b", "feature", path.join(scratch("dms-tree-"), "wt"));
  write(at(s.repo, "docs/dforge/specs/d.md"), "# D\n");
  commitAll(s.repo, "spec d on the primary");
  const result = await s.reconcile();
  assert.equal(result.code, 0, result.stdout + result.stderr);
  assert.match(result.stdout, /^darkmem-sync reconcile: documents moved to darkmem$/m);
});

test("a different version on darkmem refuses the move before anything is sent", async t => {
  const s = await docsRepo(t, { "specs/a.md": "# A\n", "specs/b.md": "# B\n" });
  await s.seed.putDocument({ project: "proj", uri: "dforge/specs/a.md", content: "# A on darkmem\n" });
  const from = s.stub.db.requests.length;
  const result = await s.reconcile();
  assert.equal(result.code, 1);
  assert.match(result.stdout, /^darkmem-sync reconcile: documents stay local \(configured darkmem\): darkmem holds a different version of some documents; nothing was sent$/m);
  assert.match(result.stdout, /^ {2}dforge\/specs\/a\.md: darkmem holds a different version$/m);
  assert.deepEqual(writes(s.stub, from), []);
  assert.equal(s.stub.db.documents.size, 1);
  assert.equal(git(s.repo, "status", "--porcelain"), "");
});

test("a pull that reads back different bytes refuses the move, keeps the repository copy, and with no record keeps documents applied local", async t => {
  const s = await docsRepo(t, undefined, { stores: null, stub: { transformContent: content => `${content}altered\n` } });
  const result = await s.reconcile();
  assert.equal(result.code, 1, result.stdout + result.stderr);
  assert.match(result.stdout, /^darkmem-sync reconcile: documents stay local \(configured darkmem\): a pull of darkmem's copy differs from the repository$/m);
  assert.match(result.stdout, /^ {2}dforge\/specs\/a\.md: the mirror's copy differs from the repository's$/m);
  assert.equal(read(at(s.repo, "docs/dforge/specs/a.md")), "# A\n");
  assert.equal(git(s.repo, "status", "--porcelain"), "");
  assert.deepEqual(s.stores(), { documents: "local", progress: "local" });
  assert.equal(cfgFor(s.repo, s.env).documents.applied, "local", "the pulled sync state does not tip the first-run rule");
});

test("a plan directory reached through a symbolic link is in progress, and a documents move stays local", { skip: process.platform === "win32" }, async t => {
  const s = await docsRepo(t, { "specs/a.md": "# A\n", "plans/k.md": "# K\n", "plans/completed.md": "- `docs/dforge/plans/k.md`\n" });
  // Its ledger reads as finished, which only a read through the link could tell.
  const outside = scratch("dms-link-");
  write(path.join(outside, "progress.md"), LEDGER("docs/dforge/plans/k.md"));
  const link = path.join(s.repo, ".dforge", "sdd", "k");
  fs.mkdirSync(path.dirname(link), { recursive: true });
  fs.symlinkSync(outside, link);
  const result = await s.reconcile();
  assert.equal(result.code, 1, result.stdout + result.stderr);
  assert.equal(result.stdout, `darkmem-sync reconcile: documents stay local (configured darkmem): a plan is in progress: ${link}\n`);
  assert.equal(s.stub.db.requests.length, 0);
  assert.equal(git(s.repo, "diff", "--cached", "--name-only"), "");
  assert.equal(read(at(s.repo, "docs/dforge/specs/a.md")), "# A\n");
  assert.deepEqual(s.stores(), { documents: "local", progress: "local" });
});

test("a dangling plan directory link is in progress, and a documents move stays local", { skip: process.platform === "win32" }, async t => {
  const s = await docsRepo(t, { "specs/a.md": "# A\n", "plans/k.md": "# K\n", "plans/completed.md": "- `docs/dforge/plans/k.md`\n" });
  const link = path.join(s.repo, ".dforge", "sdd", "k");
  fs.mkdirSync(path.dirname(link), { recursive: true });
  fs.symlinkSync(path.join(scratch("dms-link-"), "missing"), link);
  const result = await s.reconcile();
  assert.equal(result.code, 1, result.stdout + result.stderr);
  assert.equal(result.stdout, `darkmem-sync reconcile: documents stay local (configured darkmem): a plan is in progress: ${link}\n`);
  assert.equal(s.stub.db.requests.length, 0);
  assert.equal(git(s.repo, "diff", "--cached", "--name-only"), "");
  assert.equal(read(at(s.repo, "docs/dforge/specs/a.md")), "# A\n");
  assert.deepEqual(s.stores(), { documents: "local", progress: "local" });
});

test("a plan that starts during the pull stops the move before the deletion is staged", async t => {
  let repo;
  const s = await docsRepo(t, undefined, {
    stub: {
      onRequest: request => {
        if (repo && request.path === "/api/v1/documents/by-uri") write(at(repo, ".dforge/sdd/late/progress.md"), LEDGER("docs/dforge/plans/late.md"));
      },
    },
  });
  repo = s.repo;
  const result = await s.reconcile();
  assert.equal(result.code, 1, result.stdout + result.stderr);
  assert.match(result.stdout, /^darkmem-sync reconcile: documents stay local \(configured darkmem\): a plan is in progress: docs\/dforge\/plans\/late\.md$/m);
  assert.equal(git(s.repo, "diff", "--cached", "--name-only"), "");
  assert.equal(read(at(s.repo, "docs/dforge/specs/a.md")), "# A\n");
  assert.deepEqual(s.stores(), { documents: "local", progress: "local" });
});

for (const { name, files, change, line } of [
  { name: "changed", files: { "specs/a.md": "# A\n" }, change: repo => write(at(repo, "docs/dforge/specs/a.md"), "# A newer\n"), line: "dforge/specs/a.md: changed during the move" },
  { name: "added", files: { "specs/a.md": "# A\n" }, change: repo => write(at(repo, "docs/dforge/specs/b.md"), "# B\n"), line: "dforge/specs/b.md: added during the move" },
  { name: "removed", files: { "specs/a.md": "# A\n", "specs/b.md": "# B\n" }, change: repo => fs.rmSync(at(repo, "docs/dforge/specs/b.md")), line: "dforge/specs/b.md: removed during the move" },
]) {
  test(`a document ${name} and committed during the pull keeps the repository copy and is named`, async t => {
    let repo;
    let committed = false;
    const s = await docsRepo(t, files, {
      stub: {
        onRequest: request => {
          if (!repo || committed || request.path !== "/api/v1/documents/by-uri") return;
          committed = true;
          change(repo);
          commitAll(repo, name);
        },
      },
    });
    repo = s.repo;
    const result = await s.reconcile();
    assert.equal(result.code, 1, result.stdout + result.stderr);
    assert.match(result.stdout, /^darkmem-sync reconcile: documents stay local \(configured darkmem\): docs\/dforge changed during the move; the repository copy stays$/m);
    assert.ok(result.stdout.includes(`  ${line}\n`), result.stdout);
    assert.equal(git(s.repo, "diff", "--cached", "--name-only"), "");
    assert.equal(fs.existsSync(at(s.repo, "docs/dforge/specs/a.md")), true);
    assert.deepEqual(s.stores(), { documents: "local", progress: "local" });
  });
}

test("a document deleted without a commit during the pull is named as missing and changed, and nothing is staged", async t => {
  let repo;
  let deleted = false;
  const s = await docsRepo(t, { "specs/a.md": "# A\n", "specs/b.md": "# B\n" }, {
    stub: {
      onRequest: request => {
        if (!repo || deleted || request.path !== "/api/v1/documents/by-uri") return;
        deleted = true;
        fs.rmSync(at(repo, "docs/dforge/specs/b.md"));
      },
    },
  });
  repo = s.repo;
  const result = await s.reconcile();
  assert.equal(result.code, 1, result.stdout + result.stderr);
  assert.match(result.stdout, /^darkmem-sync reconcile: documents stay local \(configured darkmem\): docs\/dforge changed during the move; the repository copy stays$/m);
  assert.ok(result.stdout.includes("  docs/dforge/specs/b.md: missing from the working tree\n"), result.stdout);
  assert.ok(result.stdout.includes("  dforge/specs/b.md: changed during the move\n"), result.stdout);
  assert.equal(git(s.repo, "diff", "--cached", "--name-only"), "");
  assert.equal(read(at(s.repo, "docs/dforge/specs/a.md")), "# A\n");
  assert.deepEqual(s.stores(), { documents: "local", progress: "local" });
});

test("a tracked document swapped for a directory after its check is uncarriable, not a crash", t => {
  const repo = makeRepo();
  const docsDir = path.join(repo, "docs", "dforge");
  const file = path.join(docsDir, "specs", "a.md");
  write(file, "# A\n");
  commitAll(repo, "docs");
  const open = fs.openSync;
  let swapped = false;
  t.mock.method(fs, "openSync", (target, ...rest) => {
    if (!swapped && target === file) {
      swapped = true;
      fs.rmSync(file);
      fs.mkdirSync(file);
    }
    return open(target, ...rest);
  });
  const { problems, documents, uncarriable } = carriedDocuments(repo, docsDir, "docs/dforge");
  assert.deepEqual(problems, ["docs/dforge/specs/a.md: could not be read (EISDIR)"]);
  assert.deepEqual(documents, []);
  assert.deepEqual([...uncarriable], ["dforge/specs/a.md"]);
});

test("a document emptied and committed during the pull is named as changed and uncarriable, not removed", async t => {
  let repo;
  let committed = false;
  const s = await docsRepo(t, { "specs/a.md": "# A\n", "specs/b.md": "# B\n" }, {
    stub: {
      onRequest: request => {
        if (!repo || committed || request.path !== "/api/v1/documents/by-uri") return;
        committed = true;
        write(at(repo, "docs/dforge/specs/b.md"), "");
        commitAll(repo, "emptied");
      },
    },
  });
  repo = s.repo;
  const result = await s.reconcile();
  assert.equal(result.code, 1, result.stdout + result.stderr);
  assert.match(result.stdout, /^darkmem-sync reconcile: documents stay local \(configured darkmem\): docs\/dforge changed during the move; the repository copy stays$/m);
  assert.ok(result.stdout.includes("  docs/dforge/specs/b.md: empty or not UTF-8 text, which darkmem cannot store\n"), result.stdout);
  assert.ok(result.stdout.includes("  dforge/specs/b.md: changed during the move\n"), result.stdout);
  assert.ok(!result.stdout.includes("dforge/specs/b.md: removed during the move"), result.stdout);
  assert.equal(git(s.repo, "diff", "--cached", "--name-only"), "");
  assert.deepEqual(s.stores(), { documents: "local", progress: "local" });
});

test("a failing citation search is named in the move's details", { skip: process.platform === "win32" }, async t => {
  const s = await docsRepo(t);
  const realGit = process.env.PATH.split(path.delimiter).map(dir => path.join(dir, "git")).find(file => fs.existsSync(file));
  const bin = scratch("dms-git-");
  fs.writeFileSync(path.join(bin, "git"), `#!/bin/sh\nfor a in "$@"; do [ "$a" = "grep" ] && { echo "fatal: grep refused by the test" >&2; exit 128; }; done\nexec "${realGit}" "$@"\n`, { mode: 0o755 });
  const result = await reconcile(s.repo, { ...s.env, PATH: `${bin}${path.delimiter}${s.env.PATH ?? process.env.PATH}` });
  assert.equal(result.code, 0, result.stdout + result.stderr);
  assert.match(result.stdout, /git grep failed: fatal: grep refused by the test; check for docs\/superpowers\/, docs\/forge\/ and docs\/dforge\/ citations before you commit/);
});

for (const { arg, reason } of [
  { arg: "ls-files", reason: "git ls-files failed: fatal: refused by the test" },
  { arg: "--ignored=matching", reason: "git status failed: fatal: refused by the test" },
]) {
  test(`documents stay local when git ${arg} fails`, { skip: process.platform === "win32" }, async t => {
    const s = await docsRepo(t);
    const realGit = process.env.PATH.split(path.delimiter).map(dir => path.join(dir, "git")).find(file => fs.existsSync(file));
    const bin = scratch("dms-git-");
    fs.writeFileSync(path.join(bin, "git"), `#!/bin/sh\nfor a in "$@"; do [ "$a" = "${arg}" ] && { echo "fatal: refused by the test" >&2; exit 128; }; done\nexec "${realGit}" "$@"\n`, { mode: 0o755 });
    const result = await reconcile(s.repo, { ...s.env, PATH: `${bin}${path.delimiter}${s.env.PATH ?? process.env.PATH}` });
    assert.equal(result.code, 1, result.stdout + result.stderr);
    assert.ok(result.stdout.includes(`darkmem-sync reconcile: documents stay local (configured darkmem): ${reason}\n`), result.stdout);
    assert.deepEqual(writes(s.stub), []);
    assert.equal(s.stub.db.documents.size, 0);
    assert.deepEqual(s.stores(), { documents: "local", progress: "local" });
  });
}

// The CLI cannot reach this: without git, resolveStores answers local mode
// first, and a failing git shim exits with a status, which sets no error.
test("a git that cannot be started gives runGit a reason", t => {
  const saved = process.env.PATH;
  process.env.PATH = scratch("dms-nogit-");
  t.after(() => {
    process.env.PATH = saved;
  });
  const result = runGit(scratch("dms-cwd-"), ["status"]);
  assert.equal(result.status, null);
  assert.match(result.stderr, /\bENOENT\b/);
});

test("uncommitted changes are named by their raw paths, not git's quoted ones", async t => {
  const s = await docsRepo(t);
  write(path.join(s.repo, "docs", "dforge", "spécs", "naïve.md"), "new\n");
  const result = await s.reconcile();
  assert.equal(result.code, 1, result.stdout + result.stderr);
  assert.match(result.stdout, /^darkmem-sync reconcile: documents stay local \(configured darkmem\): docs\/dforge has uncommitted changes$/m);
  assert.ok(result.stdout.includes("  ?? docs/dforge/spécs/naïve.md\n"), result.stdout);
  assert.deepEqual(writes(s.stub), []);
});

test("a file the move cannot carry, committed during the pull, is named in the refusal", async t => {
  let repo;
  let committed = false;
  const s = await docsRepo(t, undefined, {
    stub: {
      onRequest: request => {
        if (!repo || committed || request.path !== "/api/v1/documents/by-uri") return;
        committed = true;
        write(at(repo, "docs/dforge/.hidden.md"), "hidden\n");
        commitAll(repo, "hidden");
      },
    },
  });
  repo = s.repo;
  const result = await s.reconcile();
  assert.equal(result.code, 1, result.stdout + result.stderr);
  assert.match(result.stdout, /^darkmem-sync reconcile: documents stay local \(configured darkmem\): docs\/dforge changed during the move; the repository copy stays$/m);
  assert.ok(result.stdout.includes("  docs/dforge/.hidden.md: a dot name, which the mirror never syncs\n"), result.stdout);
  assert.equal(git(s.repo, "diff", "--cached", "--name-only"), "");
  assert.deepEqual(s.stores(), { documents: "local", progress: "local" });
});

test("a citation search killed before it finishes is named in the move's details", { skip: process.platform === "win32" }, async t => {
  const s = await docsRepo(t);
  const realGit = process.env.PATH.split(path.delimiter).map(dir => path.join(dir, "git")).find(file => fs.existsSync(file));
  const bin = scratch("dms-git-");
  fs.writeFileSync(path.join(bin, "git"), `#!/bin/sh\nfor a in "$@"; do [ "$a" = "grep" ] && kill -KILL $$; done\nexec "${realGit}" "$@"\n`, { mode: 0o755 });
  const result = await reconcile(s.repo, { ...s.env, PATH: `${bin}${path.delimiter}${s.env.PATH ?? process.env.PATH}` });
  assert.equal(result.code, 0, result.stdout + result.stderr);
  assert.match(result.stdout, /git grep failed: it did not finish \(SIGKILL\); check for docs\/superpowers\/, docs\/forge\/ and docs\/dforge\/ citations before you commit/);
});

// Documents applied darkmem and configured local, darkmem holding two of them.
async function darkmemDocs(t, { seeded = true } = {}) {
  const stub = await startStub();
  t.after(() => stub.close());
  const repo = makeRepo();
  const home = mapped(repo, { url: stub.url, entry: { documentStore: "local", progressSource: "local" }, stores: { documents: "darkmem", progress: "local" } });
  const seed = createClient({ url: stub.url, apiKey: STUB_KEY, runKey: "seed" });
  if (seeded) {
    await seed.putDocument({ project: "proj", uri: "dforge/specs/a.md", content: "# A\n" });
    await seed.putDocument({ project: "proj", uri: "dforge/plans/p.md", content: "# P\n" });
  }
  return {
    stub, repo, seed, ...home,
    stores: () => storesOf(home.home, repo),
    reconcile: () => reconcile(repo, home.env),
    pull: () => run(["pull"], { cwd: repo, env: home.env }),
  };
}

test("documents move back into docs/dforge, untracked, and the mirror copy is set aside", async t => {
  const s = await darkmemDocs(t);
  write(path.join(s.repo, ".gitignore"), "docs/dforge/plans/\n");
  commitAll(s.repo, "attributes");
  write(path.join(s.repo, "docs", "dforge", "specs", "a.md"), "# A\n");
  const result = await s.reconcile();
  assert.equal(result.code, 0, result.stdout + result.stderr);
  assert.match(result.stdout, /^darkmem-sync reconcile: documents moved to local$/m);
  assert.ok(result.stdout.includes("  copied 2 files into docs/dforge, untracked; commit them\n"), result.stdout);
  assert.ok(result.stdout.includes("  docs/dforge/plans/p.md: ignored by git, so a commit would leave it out\n"), result.stdout);
  assert.equal(read(path.join(s.repo, "docs", "dforge", "plans", "p.md")), "# P\n");
  assert.equal(fs.existsSync(s.docsRoot), false);
  const aside = fs.readdirSync(s.mirror).filter(name => /^dforge-moved-\d{8}T\d{6}Z$/.test(name));
  assert.equal(aside.length, 1);
  assert.equal(read(path.join(s.mirror, aside[0], "specs", "a.md")), "# A\n");
  assert.deepEqual(Object.keys(JSON.parse(read(path.join(s.mirror, ".sync-state.json"))).documents), []);
  assert.deepEqual(s.stores(), { documents: "local", progress: "local" });
  assert.equal(s.stub.db.documents.size, 2, "darkmem keeps its copy");
  const again = await s.reconcile();
  assert.equal(again.code, 0, again.stderr);
  assert.equal(again.stdout, "");
});

for (const [what, plant] of [["a differing file", file => write(file, "# A local\n")], ["a named pipe", namedPipe]]) {
  test(`${what} already in docs/dforge refuses the move and nothing is copied`, { skip: what === "a named pipe" && process.platform === "win32" }, async t => {
    const s = await darkmemDocs(t);
    plant(path.join(s.repo, "docs", "dforge", "specs", "a.md"));
    const result = await s.reconcile();
    assert.equal(result.code, 1);
    assert.match(result.stdout, /^darkmem-sync reconcile: documents stay darkmem \(configured local\): docs\/dforge already holds different copies; nothing was copied$/m);
    assert.ok(result.stdout.includes("  docs/dforge/specs/a.md: already exists with different content\n"), result.stdout);
    assert.equal(fs.existsSync(path.join(s.repo, "docs", "dforge", "plans", "p.md")), false);
    assert.equal(read(path.join(s.docsRoot, "plans", "p.md")), "# P\n");
    assert.deepEqual(s.stores(), { documents: "darkmem", progress: "local" });
  });
}

test("a mirror copy swapped for a directory during the killed-run comparison refuses the move, not a crash", async t => {
  const repo = makeRepo();
  const home = mapped(repo, { entry: { documentStore: "local", progressSource: "local" }, stores: { documents: "darkmem", progress: "local" } });
  const mirrorCopy = path.join(home.docsRoot, "specs", "a.md");
  const dest = path.join(repo, "docs", "dforge", "specs", "a.md");
  write(mirrorCopy, "# A\n");
  write(dest, "# A\n");
  // Offline (darkmem turned off) the move needs no client.
  const cfg = { ...cfgFor(repo, home.env), enabled: false };
  const lines = [];
  const context = { cfg, client: null, env: home.env, out: line => lines.push(line), report: { refused: 0 }, state: loadState(cfg.statePath), persist: () => {} };
  // The comparison reads the repository's copy, then the mirror's: the
  // mirror's becomes a directory at that second open.
  const open = fs.openSync;
  let armed = false;
  t.mock.method(fs, "openSync", (target, ...rest) => {
    if (target === dest) armed = true;
    else if (armed && target === mirrorCopy) {
      armed = false;
      fs.rmSync(mirrorCopy);
      fs.mkdirSync(mirrorCopy);
    }
    return open(target, ...rest);
  });
  await reconcileInProcess(context);
  assert.ok(lines.includes("darkmem-sync reconcile: documents stay darkmem (configured local): docs/dforge already holds different copies; nothing was copied"), lines.join("\n"));
  assert.ok(lines.includes("  docs/dforge/specs/a.md: already exists with different content"), lines.join("\n"));
});

// Documents applied darkmem and configured local, the mirror holding
// specs/a.md and specs/b.md with their sync state, moved in-process so a test
// can mock fs. Offline (darkmem turned off) the move needs no client.
const SYNCED = { "dforge/specs/a.md": sha("# A\n"), "dforge/specs/b.md": sha("# B\n") };

function offlineDocs() {
  const repo = makeRepo();
  const home = mapped(repo, { entry: { documentStore: "local", progressSource: "local" }, stores: { documents: "darkmem", progress: "local" } });
  write(path.join(home.docsRoot, "specs", "a.md"), "# A\n");
  write(path.join(home.docsRoot, "specs", "b.md"), "# B\n");
  const cfg = { ...cfgFor(repo, home.env), enabled: false };
  const state = loadState(cfg.statePath);
  state.documents = { ...SYNCED };
  const lines = [];
  let persisted = 0;
  const context = { cfg, client: null, env: home.env, out: line => lines.push(line), report: { refused: 0 }, state, persist: () => { persisted += 1; } };
  return {
    ...home, repo, lines, state,
    persisted: () => persisted,
    mirrorCopy: rel => path.join(home.docsRoot, ...rel.split("/")),
    dest: rel => path.join(repo, "docs", "dforge", ...rel.split("/")),
    reconcile: () => reconcileInProcess(context),
  };
}

const STAY = "darkmem-sync reconcile: documents stay darkmem (configured local): ";

// A refused move keeps the mirror and its sync state, and a.md, written
// before the refusal, holds the mirror's content.
function assertKept(s) {
  assert.equal(fs.existsSync(s.docsRoot), true, "the mirror is not set aside");
  assert.deepEqual(s.state.documents, SYNCED);
  assert.equal(s.persisted(), 0);
  assert.equal(read(s.dest("specs/a.md")), "# A\n");
}

// Maps each descriptor the exclusive create returns to its path: the copy
// writes through that descriptor, so a mock of writeFileSync sees no path.
function exclusiveOpens(t) {
  const open = fs.openSync;
  const opened = new Map();
  t.mock.method(fs, "openSync", (file, flags, ...rest) => {
    const fd = open(file, flags, ...rest);
    if (flags === "wx") opened.set(fd, file);
    return fd;
  });
  return opened;
}

// The lines from the refusal on, so a test can check the details' order.
function from(s, reason) {
  return s.lines.slice(s.lines.indexOf(`${STAY}${reason}`));
}

// Runs `act` once, when the move makes b.md's directory after writing a.md:
// between b.md's checks and its write. Returns how often it ran.
function beforeSecondWrite(t, s, act) {
  const mkdir = fs.mkdirSync;
  let ran = 0;
  t.mock.method(fs, "mkdirSync", (dir, options) => {
    const made = mkdir(dir, options);
    if (dir === path.dirname(s.dest("specs/b.md")) && fs.existsSync(s.dest("specs/a.md")) && !fs.lstatSync(s.dest("specs/b.md"), { throwIfNoEntry: false })) {
      ran += 1;
      act();
    }
    return made;
  });
  return () => ran;
}

test("a file that lands in docs/dforge just before its write is never overwritten", async t => {
  const s = offlineDocs();
  const ran = beforeSecondWrite(t, s, () => fs.writeFileSync(s.dest("specs/b.md"), "# B local\n"));
  await s.reconcile();
  assert.equal(ran(), 1);
  assert.ok(s.lines.includes(`${STAY}docs/dforge changed during the move; nothing was overwritten`), s.lines.join("\n"));
  assert.ok(s.lines.includes("  docs/dforge/specs/b.md: changed during the move; not overwritten"), s.lines.join("\n"));
  assert.ok(s.lines.includes("  docs/dforge/specs/a.md: copied"), s.lines.join("\n"));
  assert.equal(read(s.dest("specs/b.md")), "# B local\n");
  assertKept(s);
});

test("a link that lands at a docs/dforge destination after the comparison is never written through", { skip: process.platform === "win32" }, async t => {
  const s = offlineDocs();
  const outside = path.join(scratch("dms-link-"), "b.md");
  write(outside, "outside the repository\n");
  const ran = beforeSecondWrite(t, s, () => fs.symlinkSync(outside, s.dest("specs/b.md")));
  await s.reconcile();
  assert.equal(ran(), 1);
  assert.ok(s.lines.includes(`${STAY}docs/dforge changed during the move; nothing was overwritten`), s.lines.join("\n"));
  assert.ok(s.lines.includes("  docs/dforge/specs/b.md: changed during the move; not overwritten"), s.lines.join("\n"));
  assert.ok(s.lines.includes("  docs/dforge/specs/a.md: copied"), s.lines.join("\n"));
  assert.equal(fs.lstatSync(s.dest("specs/b.md")).isSymbolicLink(), true);
  assert.equal(read(outside), "outside the repository\n");
  assertKept(s);
});

test("a mirror copy edited after darkmem confirmed it is not copied", async t => {
  const s = offlineDocs();
  const ran = beforeSecondWrite(t, s, () => write(s.mirrorCopy("specs/b.md"), "# B edited\n"));
  await s.reconcile();
  assert.equal(ran(), 1);
  assert.ok(s.lines.includes(`${STAY}the mirror changed during the move; nothing more was copied`), s.lines.join("\n"));
  assert.ok(s.lines.includes("  docs/dforge/specs/b.md: the mirror's copy changed after darkmem confirmed it"), s.lines.join("\n"));
  assert.ok(s.lines.includes("  docs/dforge/specs/a.md: copied"), s.lines.join("\n"));
  assert.equal(fs.existsSync(s.dest("specs/b.md")), false);
  assert.equal(read(s.mirrorCopy("specs/b.md")), "# B edited\n");
  assertKept(s);
});

test("a mirror copy replaced by a link after it was hashed is never read through", { skip: process.platform === "win32" }, async t => {
  const s = offlineDocs();
  const outside = path.join(scratch("dms-link-"), "b.md");
  write(outside, "# B\n");
  const ran = beforeSecondWrite(t, s, () => {
    fs.rmSync(s.mirrorCopy("specs/b.md"));
    fs.symlinkSync(outside, s.mirrorCopy("specs/b.md"));
  });
  await s.reconcile();
  assert.equal(ran(), 1);
  assert.ok(s.lines.includes(`${STAY}a copy into docs/dforge failed (ELOOP); the files copied so far stay, and a rerun copies the rest`), s.lines.join("\n"));
  assert.ok(s.lines.includes("  docs/dforge/specs/a.md: copied"), s.lines.join("\n"));
  assert.equal(fs.existsSync(s.dest("specs/b.md")), false);
  assert.equal(fs.lstatSync(s.mirrorCopy("specs/b.md")).isSymbolicLink(), true);
  assertKept(s);
});

test("a write into docs/dforge that fails part-way is a refusal, not a crash, and a rerun finishes the move", async t => {
  const s = offlineDocs();
  const opened = exclusiveOpens(t);
  const writeFile = fs.writeFileSync;
  t.mock.method(fs, "writeFileSync", (file, ...rest) => {
    if (opened.get(file) === s.dest("specs/b.md")) throw Object.assign(new Error("injected by the test"), { code: "EIO" });
    return writeFile(file, ...rest);
  });
  await s.reconcile();
  assert.ok(s.lines.includes(`${STAY}a copy into docs/dforge failed (EIO); the files copied so far stay, and a rerun copies the rest`), s.lines.join("\n"));
  assert.ok(s.lines.includes("  docs/dforge/specs/a.md: copied"), s.lines.join("\n"));
  assertKept(s);
  t.mock.restoreAll();
  s.lines.length = 0;
  await s.reconcile();
  assert.ok(s.lines.some(line => line.startsWith("darkmem-sync reconcile: documents moved to local")), s.lines.join("\n"));
  assert.equal(read(s.dest("specs/a.md")), "# A\n");
  assert.equal(read(s.dest("specs/b.md")), "# B\n");
});

test("a link that replaces a written copy before the read-back is never read through", { skip: process.platform === "win32" }, async t => {
  const s = offlineDocs();
  const outside = path.join(scratch("dms-link-"), "a.md");
  write(outside, "# A\n");
  const opened = exclusiveOpens(t);
  const writeFile = fs.writeFileSync;
  const written = [];
  t.mock.method(fs, "writeFileSync", (file, ...rest) => {
    writeFile(file, ...rest);
    const target = opened.get(file);
    if (target === s.dest("specs/a.md") || target === s.dest("specs/b.md")) written.push(target);
    if (target === s.dest("specs/b.md")) {
      fs.rmSync(s.dest("specs/a.md"));
      fs.symlinkSync(outside, s.dest("specs/a.md"));
    }
  });
  await s.reconcile();
  assert.deepEqual(written, [s.dest("specs/a.md"), s.dest("specs/b.md")]);
  assert.ok(s.lines.includes(`${STAY}a copy into docs/dforge failed (ELOOP); the files copied so far stay, and a rerun copies the rest`), s.lines.join("\n"));
  assert.ok(s.lines.includes("  docs/dforge/specs/a.md: copied"), s.lines.join("\n"));
  assert.ok(s.lines.includes("  docs/dforge/specs/b.md: copied"), s.lines.join("\n"));
  assert.equal(fs.lstatSync(s.dest("specs/a.md")).isSymbolicLink(), true);
  assert.equal(read(s.dest("specs/b.md")), "# B\n");
  assert.equal(fs.existsSync(s.docsRoot), true, "the mirror is not set aside");
  assert.deepEqual(s.state.documents, SYNCED);
  assert.equal(s.persisted(), 0);
});

test("a docs/dforge copy a killed run left equal is not written again", async t => {
  const s = offlineDocs();
  write(s.dest("specs/a.md"), "# A\n");
  const opens = t.mock.method(fs, "openSync");
  await s.reconcile();
  assert.ok(s.lines.some(line => line.startsWith("darkmem-sync reconcile: documents moved to local")), s.lines.join("\n"));
  assert.ok(s.lines.includes("  copied 2 files into docs/dforge, untracked; commit them"), s.lines.join("\n"));
  assert.equal(opens.mock.calls.filter(call => call.arguments[0] === s.dest("specs/a.md") && call.arguments[1] === "wx").length, 0);
  assert.equal(read(s.dest("specs/b.md")), "# B\n");
});

test("a write into docs/dforge that fails after a partial write leaves no partial file, and a rerun finishes the move", async t => {
  const s = offlineDocs();
  const opened = exclusiveOpens(t);
  const writeFile = fs.writeFileSync;
  t.mock.method(fs, "writeFileSync", (file, data, ...rest) => {
    if (opened.get(file) !== s.dest("specs/b.md")) return writeFile(file, data, ...rest);
    writeFile(file, data.subarray(0, 1), ...rest);
    throw Object.assign(new Error("injected by the test"), { code: "ENOSPC" });
  });
  await s.reconcile();
  const refusal = "a copy into docs/dforge failed (ENOSPC); the files copied so far stay, and a rerun copies the rest";
  assert.deepEqual(from(s, refusal).slice(0, 2), [`${STAY}${refusal}`, "  docs/dforge/specs/a.md: copied"], s.lines.join("\n"));
  assert.equal(fs.lstatSync(s.dest("specs/b.md"), { throwIfNoEntry: false }), undefined);
  assertKept(s);
  t.mock.restoreAll();
  s.lines.length = 0;
  await s.reconcile();
  assert.ok(s.lines.some(line => line.startsWith("darkmem-sync reconcile: documents moved to local")), s.lines.join("\n"));
  assert.equal(read(s.dest("specs/b.md")), "# B\n");
});

test("a bug in the docs/dforge copy loop crashes reconcile rather than refusing", async t => {
  const s = offlineDocs();
  beforeSecondWrite(t, s, () => { throw new TypeError("injected by the test"); });
  await assert.rejects(s.reconcile(), TypeError);
  assert.equal(s.persisted(), 0);
  assert.equal(fs.existsSync(s.docsRoot), true);
});

test("a written copy that changes before the read-back is a difference, listed before the copied files", async t => {
  const s = offlineDocs();
  const opened = exclusiveOpens(t);
  const writeFile = fs.writeFileSync;
  t.mock.method(fs, "writeFileSync", (file, ...rest) => {
    writeFile(file, ...rest);
    if (opened.get(file) === s.dest("specs/b.md")) writeFile(s.dest("specs/a.md"), "# A tampered\n");
  });
  await s.reconcile();
  assert.deepEqual(from(s, "a copied file differs from the mirror's").slice(0, 4), [
    `${STAY}a copied file differs from the mirror's`,
    "  docs/dforge/specs/a.md: differs from the mirror's copy",
    "  docs/dforge/specs/a.md: copied",
    "  docs/dforge/specs/b.md: copied",
  ], s.lines.join("\n"));
  assert.deepEqual(s.state.documents, SYNCED);
  assert.equal(s.persisted(), 0);
});

test("a mirror copy that differs from darkmem's refuses the move before anything is copied or set aside", async t => {
  const s = await darkmemDocs(t);
  assert.equal((await s.pull()).code, 0);
  write(path.join(s.docsRoot, "specs", "a.md"), "# A corrupted\n");
  const result = await s.reconcile();
  assert.equal(result.code, 1, result.stdout + result.stderr);
  assert.match(result.stdout, /^darkmem-sync reconcile: documents stay darkmem \(configured local\): the mirror does not match darkmem; nothing was copied$/m);
  assert.ok(result.stdout.includes("  dforge/specs/a.md: the mirror's copy differs from darkmem's; push or discard it first\n"), result.stdout);
  assert.equal(fs.existsSync(path.join(s.repo, "docs", "dforge")), false);
  assert.equal(read(path.join(s.docsRoot, "specs", "a.md")), "# A corrupted\n");
  assert.deepEqual(fs.readdirSync(s.mirror).filter(name => name.startsWith("dforge-moved-")), []);
  assert.deepEqual(s.stores(), { documents: "darkmem", progress: "local" });
});

test("a completed.md the pull changes is checked again before anything is copied", async t => {
  const s = await darkmemDocs(t);
  await s.seed.putDocument({ project: "proj", uri: "dforge/plans/completed.md", content: "- `docs/dforge/plans/p.md`\n" });
  assert.equal((await s.pull()).code, 0);
  write(at(s.repo, ".dforge/sdd/p/progress.md"), LEDGER("docs/dforge/plans/p.md"));
  await s.seed.putDocument({ project: "proj", uri: "dforge/plans/completed.md", content: "- `docs/dforge/plans/other.md`\n" });
  const result = await s.reconcile();
  assert.equal(result.code, 1, result.stdout + result.stderr);
  assert.match(result.stdout, /^darkmem-sync reconcile: documents stay darkmem \(configured local\): a plan is in progress: docs\/dforge\/plans\/p\.md$/m);
  assert.equal(fs.existsSync(path.join(s.repo, "docs", "dforge")), false);
  assert.equal(fs.existsSync(s.docsRoot), true);
  assert.deepEqual(s.stores(), { documents: "darkmem", progress: "local" });
});

test("a deletion the mirror has not pushed refuses the move until a push archives it", async t => {
  const s = await darkmemDocs(t);
  assert.equal((await s.pull()).code, 0);
  fs.rmSync(path.join(s.docsRoot, "specs", "a.md"));
  const result = await s.reconcile();
  assert.equal(result.code, 1, result.stdout + result.stderr);
  assert.match(result.stdout, /^darkmem-sync reconcile: documents stay darkmem \(configured local\): the mirror holds deletions not yet pushed; push first$/m);
  assert.ok(result.stdout.includes("  dforge/specs/a.md\n"), result.stdout);
  assert.equal(fs.existsSync(path.join(s.repo, "docs", "dforge")), false);
  assert.deepEqual(s.stores(), { documents: "darkmem", progress: "local" });
  assert.equal((await run(["push"], { cwd: s.repo, env: s.env })).code, 0);
  const moved = await s.reconcile();
  assert.equal(moved.code, 0, moved.stdout + moved.stderr);
  assert.ok(moved.stdout.includes("  copied 1 files into docs/dforge, untracked; commit them\n"), moved.stdout);
  assert.equal(fs.existsSync(path.join(s.repo, "docs", "dforge", "specs", "a.md")), false);
});

test("a move with no documents still creates docs/dforge", async t => {
  const s = await darkmemDocs(t, { seeded: false });
  const result = await s.reconcile();
  assert.equal(result.code, 0, result.stdout + result.stderr);
  assert.match(result.stdout, /^darkmem-sync reconcile: documents moved to local$/m);
  assert.ok(result.stdout.includes("  copied 0 files into docs/dforge, untracked; commit them\n"), result.stdout);
  assert.ok(fs.statSync(path.join(s.repo, "docs", "dforge")).isDirectory());
  assert.deepEqual(s.stores(), { documents: "local", progress: "local" });
});

test("a mirror link where darkmem holds a document refuses the move", { skip: process.platform === "win32" }, async t => {
  const s = await darkmemDocs(t);
  assert.equal((await s.pull()).code, 0);
  const outside = path.join(scratch("dms-link-"), "a.md");
  fs.writeFileSync(outside, "# A\n");
  fs.rmSync(path.join(s.docsRoot, "specs", "a.md"));
  fs.symlinkSync(outside, path.join(s.docsRoot, "specs", "a.md"));
  const result = await s.reconcile();
  assert.equal(result.code, 1, result.stdout + result.stderr);
  assert.ok(result.stdout.includes("darkmem-sync reconcile: documents stay darkmem (configured local): the mirror does not match darkmem; nothing was copied\n"), result.stdout);
  assert.ok(result.stdout.includes("  dforge/specs/a.md: the mirror holds a symbolic link or other non-file here, which the move cannot copy; make it a regular file\n"), result.stdout);
  assert.equal(fs.existsSync(path.join(s.repo, "docs", "dforge")), false);
  assert.equal(fs.existsSync(s.docsRoot), true);
  assert.deepEqual(s.stores(), { documents: "darkmem", progress: "local" });
});

test("docs/dforge reached through a symbolic link refuses the move and writes nothing through it", { skip: process.platform === "win32" }, async t => {
  const s = await darkmemDocs(t);
  const outside = scratch("dms-link-");
  fs.mkdirSync(path.join(s.repo, "docs"), { recursive: true });
  fs.symlinkSync(outside, path.join(s.repo, "docs", "dforge"));
  const result = await s.reconcile();
  assert.equal(result.code, 1, result.stdout + result.stderr);
  assert.ok(result.stdout.includes("documents stay darkmem (configured local): docs/dforge is reached through symbolic links; nothing was copied\n"), result.stdout);
  assert.ok(result.stdout.includes("  docs/dforge: a symbolic link, which the move will not write through\n"), result.stdout);
  assert.deepEqual(fs.readdirSync(outside), []);
  assert.deepEqual(s.stores(), { documents: "darkmem", progress: "local" });
  assert.equal(fs.existsSync(s.docsRoot), true);
});

test("a dangling link at a destination file refuses the move and is not written through", { skip: process.platform === "win32" }, async t => {
  const s = await darkmemDocs(t);
  const outside = path.join(scratch("dms-link-"), "created.md");
  fs.mkdirSync(path.join(s.repo, "docs", "dforge", "plans"), { recursive: true });
  fs.symlinkSync(outside, path.join(s.repo, "docs", "dforge", "plans", "p.md"));
  const result = await s.reconcile();
  assert.equal(result.code, 1, result.stdout + result.stderr);
  assert.ok(result.stdout.includes("  docs/dforge/plans/p.md: a symbolic link, which the move will not write through\n"), result.stdout);
  assert.equal(fs.existsSync(outside), false);
  assert.deepEqual(s.stores(), { documents: "darkmem", progress: "local" });
});

test("documents stay darkmem when git check-ignore fails", { skip: process.platform === "win32" }, async t => {
  const s = await darkmemDocs(t);
  const realGit = process.env.PATH.split(path.delimiter).map(dir => path.join(dir, "git")).find(file => fs.existsSync(file));
  const bin = scratch("dms-git-");
  fs.writeFileSync(path.join(bin, "git"), `#!/bin/sh\nfor a in "$@"; do [ "$a" = "check-ignore" ] && { echo "fatal: refused by the test" >&2; exit 128; }; done\nexec "${realGit}" "$@"\n`, { mode: 0o755 });
  const result = await reconcile(s.repo, { ...s.env, PATH: `${bin}${path.delimiter}${s.env.PATH ?? process.env.PATH}` });
  assert.equal(result.code, 1, result.stdout + result.stderr);
  assert.ok(result.stdout.includes("darkmem-sync reconcile: documents stay darkmem (configured local): git check-ignore failed: fatal: refused by the test\n"), result.stdout);
  assert.equal(fs.existsSync(path.join(s.repo, "docs", "dforge")), false);
  assert.equal(fs.existsSync(s.docsRoot), true);
  assert.deepEqual(s.stores(), { documents: "darkmem", progress: "local" });
});

test("a file at docs/dforge refuses the move back, and nothing is copied", async t => {
  const s = await darkmemDocs(t);
  write(path.join(s.repo, "docs", "dforge"), "not a directory\n");
  const result = await s.reconcile();
  assert.equal(result.code, 1, result.stdout + result.stderr);
  assert.ok(result.stdout.includes("darkmem-sync reconcile: documents stay darkmem (configured local): docs/dforge is not a directory; nothing was copied\n"), result.stdout);
  assert.equal(read(path.join(s.repo, "docs", "dforge")), "not a directory\n");
  assert.equal(fs.existsSync(s.docsRoot), true);
  assert.deepEqual(s.stores(), { documents: "darkmem", progress: "local" });
});

test("a mirror docs root that is a symbolic link refuses the move back, and nothing is copied or set aside", { skip: process.platform === "win32" }, async t => {
  const s = await darkmemDocs(t);
  const outside = scratch("dms-link-");
  write(path.join(outside, "specs", "a.md"), "# A\n");
  write(path.join(outside, "plans", "p.md"), "# P\n");
  fs.mkdirSync(s.mirror, { recursive: true });
  fs.symlinkSync(outside, s.docsRoot);
  const result = await s.reconcile();
  assert.equal(result.code, 1, result.stdout + result.stderr);
  assert.ok(result.stdout.includes(`darkmem-sync reconcile: documents stay darkmem (configured local): the mirror's docs root ${s.docsRoot} is a symbolic link; nothing was copied\n`), result.stdout);
  assert.equal(fs.existsSync(path.join(s.repo, "docs", "dforge")), false);
  assert.ok(fs.lstatSync(s.docsRoot).isSymbolicLink(), "the link is not set aside");
  assert.deepEqual(s.stores(), { documents: "darkmem", progress: "local" });
});

test("a mirror copy that cannot be set aside refuses the move, keeps the sync state, and a rerun finishes it", async t => {
  const s = await darkmemDocs(t);
  assert.equal((await s.pull()).code, 0);
  // Every name the aside rename can take for the next minute is a non-empty directory.
  const now = Date.now();
  const blockers = [];
  for (let i = 0; i < 60; i += 1) {
    const dir = path.join(s.mirror, `dforge-moved-${utcStamp(new Date(now + i * 1000))}`);
    blockers.push(dir);
    write(path.join(dir, "keep.md"), "taken\n");
  }
  const result = await s.reconcile();
  assert.equal(result.code, 1, result.stdout + result.stderr);
  assert.doesNotMatch(result.stderr, /unexpected error/);
  assert.match(result.stdout, /^darkmem-sync reconcile: documents stay darkmem \(configured local\): the mirror's copy could not be set aside \(\w+\); docs\/dforge holds the copied files, and the next reconcile finishes the move$/m);
  assert.deepEqual(Object.keys(JSON.parse(read(path.join(s.mirror, ".sync-state.json"))).documents).sort(), ["dforge/plans/p.md", "dforge/specs/a.md"]);
  assert.equal(fs.existsSync(s.docsRoot), true);
  assert.deepEqual(s.stores(), { documents: "darkmem", progress: "local" });
  for (const dir of blockers) fs.rmSync(dir, { recursive: true });
  const again = await s.reconcile();
  assert.equal(again.code, 0, again.stdout + again.stderr);
  assert.match(again.stdout, /^darkmem-sync reconcile: documents moved to local$/m);
  assert.equal(read(path.join(s.repo, "docs", "dforge", "specs", "a.md")), "# A\n");
});

test("a sync state that cannot be saved after the set-aside stops reconcile with exit 2 and one line", async t => {
  const s = await darkmemDocs(t);
  assert.equal((await s.pull()).code, 0);
  const stateFile = path.join(s.mirror, ".sync-state.json");
  // Reconcile reads the manifest three times: its probe, the pull into the
  // mirror, and the check before anything is copied, which is the last request
  // before the set-aside rename and the save after it.
  let manifests = 0;
  s.stub.db.onRequest = (method, pathname) => {
    if (method !== "GET" || pathname !== "/api/v1/documents/manifest" || ++manifests !== 3) return;
    fs.rmSync(stateFile);
    fs.mkdirSync(stateFile);
  };
  const result = await s.reconcile();
  assert.equal(result.code, 2, result.stdout + result.stderr);
  assert.equal(manifests, 3);
  assert.equal(
    result.stderr.replace(/ could not be saved \(\w+\);/, " could not be saved (CODE);"),
    `darkmem-sync: ${stateFile} could not be saved (CODE); the run stopped, and the next run checks what this one wrote\n`,
  );
  assert.doesNotMatch(result.stdout, /moved to local/);
  assert.equal(read(path.join(s.repo, "docs", "dforge", "specs", "a.md")), "# A\n");
  assert.equal(fs.existsSync(s.docsRoot), false, "the mirror copy was set aside before the save");
  assert.equal(fs.existsSync(path.join(s.mirror, ".sync.lock")), false, "the lock is released");
  assert.deepEqual(s.stores(), { documents: "darkmem", progress: "local" });
});
