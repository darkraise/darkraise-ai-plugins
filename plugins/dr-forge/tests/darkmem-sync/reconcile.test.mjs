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

// A repository whose committed docs/forge holds `files` (name -> content),
// mapped with documents configured darkmem; progress stays local. `stores` is
// the stores.json record (null: none); `stub` is passed to startStub.
async function docsRepo(t, files = { "specs/a.md": "# A\n" }, { stores = { documents: "local", progress: "local" }, stub: stubOptions = {} } = {}) {
  const stub = await startStub(stubOptions);
  t.after(() => stub.close());
  const repo = makeRepo();
  for (const [name, content] of Object.entries(files)) write(path.join(repo, "docs", "forge", ...name.split("/")), content);
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
  const s = await docsRepo(t, { "specs/a.md": "# A\n", "plans/p.md": "# P\n**Spec:** docs/forge/specs/a.md\n" });
  write(path.join(s.repo, "CLAUDE.md"), "See docs/superpowers/specs/a.md\n");
  write(path.join(s.repo, "README.md"), "No citations\n");
  commitAll(s.repo, "cite");
  await s.seed.putDocument({ project: "proj", uri: "superpowers/specs/a.md", content: "# A\n" });
  const result = await s.reconcile();
  assert.equal(result.code, 0, result.stdout + result.stderr);
  assert.match(result.stdout, /^darkmem-sync reconcile: documents moved to darkmem$/m);
  assert.ok(result.stdout.includes(`  the deletion of docs/forge is staged in ${s.repo}; commit it\n`), result.stdout);
  assert.ok(result.stdout.includes("    CLAUDE.md\n"), result.stdout);
  assert.doesNotMatch(result.stdout, /README\.md/);
  assert.equal(read(path.join(s.docsRoot, "plans", "p.md")), "# P\n**Spec:** docs/forge/specs/a.md\n");
  assert.equal(s.stub.db.documents.size, 2);
  assert.equal(writes(s.stub).filter(r => r.body?.uri === "superpowers/specs/a.md").length, 1, "the copy darkmem already held is not sent again");
  assert.equal(git(s.repo, "status", "--porcelain"), "D  docs/forge/plans/p.md\nD  docs/forge/specs/a.md");
  assert.equal(fs.existsSync(path.join(s.repo, "docs", "forge")), false);
  assert.deepEqual(s.stores(), { documents: "darkmem", progress: "local" });
  const again = await s.reconcile();
  assert.equal(again.code, 0, again.stderr);
  assert.equal(again.stdout, "");
});

test("a docs directory with no tracked files moves without staging anything, and is then named as not read", async t => {
  const stub = await startStub();
  t.after(() => stub.close());
  const repo = makeRepo();
  fs.mkdirSync(path.join(repo, "docs", "forge", "specs"), { recursive: true });
  const { env, home, docsRoot } = mapped(repo, { url: stub.url, entry: { progressSource: "local" } });
  await createClient({ url: stub.url, apiKey: STUB_KEY, runKey: "seed" }).putDocument({ project: "proj", uri: "superpowers/specs/b.md", content: "# B\n" });
  const result = await reconcile(repo, env);
  assert.equal(result.code, 0, result.stdout + result.stderr);
  assert.match(result.stdout, /^darkmem-sync reconcile: documents moved to darkmem$/m);
  assert.ok(result.stdout.includes("  docs/forge holds no tracked files; nothing to stage\n"), result.stdout);
  assert.ok(result.stdout.includes(`darkmem-sync reconcile: ${path.join(repo, "docs", "forge")} is not read while documents are applied darkmem\n`), result.stdout);
  assert.equal(read(path.join(docsRoot, "specs", "b.md")), "# B\n");
  assert.equal(git(repo, "status", "--porcelain"), "");
  assert.deepEqual(storesOf(home, repo), { documents: "darkmem", progress: "local" });
});

test("the citation list stops at 20 and counts the rest, and does not refuse the move", async t => {
  const s = await docsRepo(t);
  for (let i = 0; i < 23; i += 1) write(path.join(s.repo, "cite", `f${String(i).padStart(2, "0")}.md`), "docs/forge/specs/a.md\n");
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
  { kind: "a dotfile at depth", named: "docs/forge/specs/.draft.md", plant: repo => write(at(repo, "docs/forge/specs/.draft.md"), "x\n") },
  { kind: "a dot directory", named: "docs/forge/.cache/x.md", plant: repo => write(at(repo, "docs/forge/.cache/x.md"), "x\n") },
  { kind: "a symbolic link", named: "docs/forge/link.md", skip: process.platform === "win32", plant: repo => fs.symlinkSync("specs/a.md", at(repo, "docs/forge/link.md")) },
  { kind: "a file under handoff/", named: "docs/forge/handoff/x.md", plant: repo => write(at(repo, "docs/forge/handoff/x.md"), "x\n") },
  { kind: "a file under archive/", named: "docs/forge/archive/x.md", plant: repo => write(at(repo, "docs/forge/archive/x.md"), "x\n") },
  { kind: "an empty file", named: "docs/forge/empty.md", plant: repo => write(at(repo, "docs/forge/empty.md"), "") },
  { kind: "a file that is not UTF-8", named: "docs/forge/bin.md", plant: repo => write(at(repo, "docs/forge/bin.md"), Buffer.from([0x41, 0xff, 0x0a])) },
  { kind: "a name uriProblem rejects", named: "docs/forge/specs/aux.md", skip: process.platform === "win32", plant: repo => write(at(repo, "docs/forge/specs/aux.md"), "x\n") },
  { kind: "a case twin", named: "docs/forge/specs/A.md", skip: caseFolds, plant: repo => write(at(repo, "docs/forge/specs/A.md"), "# twin\n") },
  {
    kind: "an ignored file", named: "docs/forge/secret.md",
    plant: repo => {
      write(at(repo, ".gitignore"), "docs/forge/secret.md\n");
      write(at(repo, "docs/forge/secret.md"), "s\n");
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
    assert.match(result.stdout, /^darkmem-sync reconcile: documents stay local \(configured darkmem\): docs\/forge holds files the move cannot carry$/m);
    assert.ok(result.stdout.includes(`  ${named}`), result.stdout);
    assert.deepEqual(writes(s.stub), []);
    assert.equal(s.stub.db.documents.size, 0);
    assert.deepEqual(s.stores(), { documents: "local", progress: "local" });
    assert.equal(git(s.repo, "status", "--porcelain"), "");
  });
}

test("documents stay local while the docs directory has uncommitted changes", async t => {
  const s = await docsRepo(t);
  write(path.join(s.repo, "docs", "forge", "specs", "a.md"), "# A edited\n");
  write(path.join(s.repo, "docs", "forge", "new.md"), "new\n");
  const result = await s.reconcile();
  assert.equal(result.code, 1);
  assert.match(result.stdout, /^darkmem-sync reconcile: documents stay local \(configured darkmem\): docs\/forge has uncommitted changes$/m);
  assert.match(result.stdout, /^ {3}M docs\/forge\/specs\/a\.md$/m);
  assert.match(result.stdout, /^ {2}\?\? docs\/forge\/new\.md$/m);
  assert.deepEqual(writes(s.stub), []);
});

test("a different version on darkmem refuses the move before anything is sent", async t => {
  const s = await docsRepo(t, { "specs/a.md": "# A\n", "specs/b.md": "# B\n" });
  await s.seed.putDocument({ project: "proj", uri: "superpowers/specs/a.md", content: "# A on darkmem\n" });
  const from = s.stub.db.requests.length;
  const result = await s.reconcile();
  assert.equal(result.code, 1);
  assert.match(result.stdout, /^darkmem-sync reconcile: documents stay local \(configured darkmem\): darkmem holds a different version of some documents; nothing was sent$/m);
  assert.match(result.stdout, /^ {2}superpowers\/specs\/a\.md: darkmem holds a different version$/m);
  assert.deepEqual(writes(s.stub, from), []);
  assert.equal(s.stub.db.documents.size, 1);
  assert.equal(git(s.repo, "status", "--porcelain"), "");
});

test("a pull that reads back different bytes refuses the move, keeps the repository copy, and with no record keeps documents applied local", async t => {
  const s = await docsRepo(t, undefined, { stores: null, stub: { transformContent: content => `${content}altered\n` } });
  const result = await s.reconcile();
  assert.equal(result.code, 1, result.stdout + result.stderr);
  assert.match(result.stdout, /^darkmem-sync reconcile: documents stay local \(configured darkmem\): a pull of darkmem's copy differs from the repository$/m);
  assert.match(result.stdout, /^ {2}superpowers\/specs\/a\.md: the mirror's copy differs from the repository's$/m);
  assert.equal(read(at(s.repo, "docs/forge/specs/a.md")), "# A\n");
  assert.equal(git(s.repo, "status", "--porcelain"), "");
  assert.deepEqual(s.stores(), { documents: "local", progress: "local" });
  assert.equal(cfgFor(s.repo, s.env).documents.applied, "local", "the pulled sync state does not tip the first-run rule");
});

test("a plan that starts during the pull stops the move before the deletion is staged", async t => {
  let repo;
  const s = await docsRepo(t, undefined, {
    stub: {
      onRequest: request => {
        if (repo && request.path === "/api/v1/documents/by-uri") write(at(repo, ".forge/sdd/late/progress.md"), LEDGER("docs/forge/plans/late.md"));
      },
    },
  });
  repo = s.repo;
  const result = await s.reconcile();
  assert.equal(result.code, 1, result.stdout + result.stderr);
  assert.match(result.stdout, /^darkmem-sync reconcile: documents stay local \(configured darkmem\): a plan is in progress: docs\/forge\/plans\/late\.md$/m);
  assert.equal(git(s.repo, "diff", "--cached", "--name-only"), "");
  assert.equal(read(at(s.repo, "docs/forge/specs/a.md")), "# A\n");
  assert.deepEqual(s.stores(), { documents: "local", progress: "local" });
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

// Documents applied darkmem and configured local, darkmem holding two of them.
async function darkmemDocs(t, { seeded = true } = {}) {
  const stub = await startStub();
  t.after(() => stub.close());
  const repo = makeRepo();
  const home = mapped(repo, { url: stub.url, entry: { documentStore: "local", progressSource: "local" }, stores: { documents: "darkmem", progress: "local" } });
  const seed = createClient({ url: stub.url, apiKey: STUB_KEY, runKey: "seed" });
  if (seeded) {
    await seed.putDocument({ project: "proj", uri: "superpowers/specs/a.md", content: "# A\n" });
    await seed.putDocument({ project: "proj", uri: "superpowers/plans/p.md", content: "# P\n" });
  }
  return {
    stub, repo, seed, ...home,
    stores: () => storesOf(home.home, repo),
    reconcile: () => reconcile(repo, home.env),
    pull: () => run(["pull"], { cwd: repo, env: home.env }),
  };
}

test("documents move back into docs/forge, untracked, and the mirror copy is set aside", async t => {
  const s = await darkmemDocs(t);
  write(path.join(s.repo, ".gitattributes"), "docs/superpowers/plans/completed.md merge=union\n");
  write(path.join(s.repo, ".gitignore"), "docs/forge/plans/\n");
  commitAll(s.repo, "attributes");
  write(path.join(s.repo, "docs", "forge", "specs", "a.md"), "# A\n");
  const result = await s.reconcile();
  assert.equal(result.code, 0, result.stdout + result.stderr);
  assert.match(result.stdout, /^darkmem-sync reconcile: documents moved to local$/m);
  assert.ok(result.stdout.includes("  copied 2 files into docs/forge, untracked; commit them\n"), result.stdout);
  assert.ok(result.stdout.includes("  docs/forge/plans/p.md: ignored by git, so a commit would leave it out\n"), result.stdout);
  assert.ok(result.stdout.includes("  .gitattributes line 1 still names docs/superpowers/: docs/superpowers/plans/completed.md merge=union\n"), result.stdout);
  assert.equal(read(path.join(s.repo, "docs", "forge", "plans", "p.md")), "# P\n");
  assert.equal(fs.existsSync(s.docsRoot), false);
  const aside = fs.readdirSync(s.mirror).filter(name => /^superpowers-moved-\d{8}T\d{6}Z$/.test(name));
  assert.equal(aside.length, 1);
  assert.equal(read(path.join(s.mirror, aside[0], "specs", "a.md")), "# A\n");
  assert.deepEqual(Object.keys(JSON.parse(read(path.join(s.mirror, ".sync-state.json"))).documents), []);
  assert.deepEqual(s.stores(), { documents: "local", progress: "local" });
  assert.equal(s.stub.db.documents.size, 2, "darkmem keeps its copy");
  const again = await s.reconcile();
  assert.equal(again.code, 0, again.stderr);
  assert.equal(again.stdout, "");
});

test("a legacy docs/superpowers directory stays untouched and is named as not read", async t => {
  const s = await darkmemDocs(t);
  write(path.join(s.repo, "docs", "superpowers", "old.md"), "old\n");
  const result = await s.reconcile();
  assert.equal(result.code, 0, result.stdout + result.stderr);
  assert.match(result.stdout, /^darkmem-sync reconcile: documents moved to local$/m);
  assert.ok(result.stdout.includes(`  ${path.join(s.repo, "docs", "superpowers")} is a legacy docs directory and is not read; documents now live in docs/forge\n`), result.stdout);
  assert.equal(read(path.join(s.repo, "docs", "superpowers", "old.md")), "old\n");
  assert.equal(read(path.join(s.repo, "docs", "forge", "specs", "a.md")), "# A\n");
  assert.deepEqual(s.stores(), { documents: "local", progress: "local" });
});

test("a differing file already in docs/forge refuses the move and nothing is copied", async t => {
  const s = await darkmemDocs(t);
  write(path.join(s.repo, "docs", "forge", "specs", "a.md"), "# A local\n");
  const result = await s.reconcile();
  assert.equal(result.code, 1);
  assert.match(result.stdout, /^darkmem-sync reconcile: documents stay darkmem \(configured local\): docs\/forge already holds different copies; nothing was copied$/m);
  assert.ok(result.stdout.includes("  docs/forge/specs/a.md: already exists with different content\n"), result.stdout);
  assert.equal(fs.existsSync(path.join(s.repo, "docs", "forge", "plans", "p.md")), false);
  assert.equal(read(path.join(s.docsRoot, "plans", "p.md")), "# P\n");
  assert.deepEqual(s.stores(), { documents: "darkmem", progress: "local" });
});

test("a mirror copy that differs from darkmem's refuses the move before anything is copied or set aside", async t => {
  const s = await darkmemDocs(t);
  assert.equal((await s.pull()).code, 0);
  write(path.join(s.docsRoot, "specs", "a.md"), "# A corrupted\n");
  const result = await s.reconcile();
  assert.equal(result.code, 1, result.stdout + result.stderr);
  assert.match(result.stdout, /^darkmem-sync reconcile: documents stay darkmem \(configured local\): the mirror does not match darkmem; nothing was copied$/m);
  assert.ok(result.stdout.includes("  superpowers/specs/a.md: the mirror's copy differs from darkmem's; push or discard it first\n"), result.stdout);
  assert.equal(fs.existsSync(path.join(s.repo, "docs", "forge")), false);
  assert.equal(read(path.join(s.docsRoot, "specs", "a.md")), "# A corrupted\n");
  assert.deepEqual(fs.readdirSync(s.mirror).filter(name => name.startsWith("superpowers-moved-")), []);
  assert.deepEqual(s.stores(), { documents: "darkmem", progress: "local" });
});

test("a completed.md the pull changes is checked again before anything is copied", async t => {
  const s = await darkmemDocs(t);
  await s.seed.putDocument({ project: "proj", uri: "superpowers/plans/completed.md", content: "- `docs/forge/plans/p.md`\n" });
  assert.equal((await s.pull()).code, 0);
  write(at(s.repo, ".forge/sdd/p/progress.md"), LEDGER("docs/forge/plans/p.md"));
  await s.seed.putDocument({ project: "proj", uri: "superpowers/plans/completed.md", content: "- `docs/forge/plans/other.md`\n" });
  const result = await s.reconcile();
  assert.equal(result.code, 1, result.stdout + result.stderr);
  assert.match(result.stdout, /^darkmem-sync reconcile: documents stay darkmem \(configured local\): a plan is in progress: docs\/forge\/plans\/p\.md$/m);
  assert.equal(fs.existsSync(path.join(s.repo, "docs", "forge")), false);
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
  assert.ok(result.stdout.includes("  superpowers/specs/a.md\n"), result.stdout);
  assert.equal(fs.existsSync(path.join(s.repo, "docs", "forge")), false);
  assert.deepEqual(s.stores(), { documents: "darkmem", progress: "local" });
  assert.equal((await run(["push"], { cwd: s.repo, env: s.env })).code, 0);
  const moved = await s.reconcile();
  assert.equal(moved.code, 0, moved.stdout + moved.stderr);
  assert.ok(moved.stdout.includes("  copied 1 files into docs/forge, untracked; commit them\n"), moved.stdout);
  assert.equal(fs.existsSync(path.join(s.repo, "docs", "forge", "specs", "a.md")), false);
});

test("a move with no documents still creates docs/forge and leaves a legacy directory untouched", async t => {
  const s = await darkmemDocs(t, { seeded: false });
  write(path.join(s.repo, "docs", "superpowers", "old.md"), "old\n");
  const result = await s.reconcile();
  assert.equal(result.code, 0, result.stdout + result.stderr);
  assert.match(result.stdout, /^darkmem-sync reconcile: documents moved to local$/m);
  assert.ok(result.stdout.includes("  copied 0 files into docs/forge, untracked; commit them\n"), result.stdout);
  assert.ok(result.stdout.includes(`  ${path.join(s.repo, "docs", "superpowers")} is a legacy docs directory and is not read; documents now live in docs/forge\n`), result.stdout);
  assert.ok(fs.statSync(path.join(s.repo, "docs", "forge")).isDirectory());
  assert.equal(read(path.join(s.repo, "docs", "superpowers", "old.md")), "old\n");
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
  assert.ok(result.stdout.includes("  superpowers/specs/a.md: the mirror holds a symbolic link or other non-file here, which the move cannot copy; make it a regular file\n"), result.stdout);
  assert.equal(fs.existsSync(path.join(s.repo, "docs", "forge")), false);
  assert.equal(fs.existsSync(s.docsRoot), true);
  assert.deepEqual(s.stores(), { documents: "darkmem", progress: "local" });
});

test("a .gitattributes that cannot be read is named after the move", async t => {
  const s = await darkmemDocs(t);
  fs.mkdirSync(path.join(s.repo, ".gitattributes"));
  const result = await s.reconcile();
  assert.equal(result.code, 0, result.stdout + result.stderr);
  assert.match(result.stdout, /^darkmem-sync reconcile: documents moved to local$/m);
  assert.ok(result.stdout.includes("  .gitattributes could not be read (EISDIR); check it for lines naming docs/superpowers/\n"), result.stdout);
});

test("docs/forge reached through a symbolic link refuses the move and writes nothing through it", { skip: process.platform === "win32" }, async t => {
  const s = await darkmemDocs(t);
  const outside = scratch("dms-link-");
  fs.mkdirSync(path.join(s.repo, "docs"), { recursive: true });
  fs.symlinkSync(outside, path.join(s.repo, "docs", "forge"));
  const result = await s.reconcile();
  assert.equal(result.code, 1, result.stdout + result.stderr);
  assert.ok(result.stdout.includes("documents stay darkmem (configured local): docs/forge is reached through symbolic links; nothing was copied\n"), result.stdout);
  assert.ok(result.stdout.includes("  docs/forge: a symbolic link, which the move will not write through\n"), result.stdout);
  assert.deepEqual(fs.readdirSync(outside), []);
  assert.deepEqual(s.stores(), { documents: "darkmem", progress: "local" });
  assert.equal(fs.existsSync(s.docsRoot), true);
});

test("a dangling link at a destination file refuses the move and is not written through", { skip: process.platform === "win32" }, async t => {
  const s = await darkmemDocs(t);
  const outside = path.join(scratch("dms-link-"), "created.md");
  fs.mkdirSync(path.join(s.repo, "docs", "forge", "plans"), { recursive: true });
  fs.symlinkSync(outside, path.join(s.repo, "docs", "forge", "plans", "p.md"));
  const result = await s.reconcile();
  assert.equal(result.code, 1, result.stdout + result.stderr);
  assert.ok(result.stdout.includes("  docs/forge/plans/p.md: a symbolic link, which the move will not write through\n"), result.stdout);
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
  assert.equal(fs.existsSync(path.join(s.repo, "docs", "forge")), false);
  assert.equal(fs.existsSync(s.docsRoot), true);
  assert.deepEqual(s.stores(), { documents: "darkmem", progress: "local" });
});
