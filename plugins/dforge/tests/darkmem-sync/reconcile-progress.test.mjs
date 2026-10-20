import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import test from "node:test";
import { pathToFileURL } from "node:url";
import { createClient } from "../../scripts/lib/darkmem-client.mjs";
import { emptyState, ledgerPieces, loadState, utcStamp } from "../../scripts/lib/darkmem-mirror.mjs";
import { checkProgressTargets, gatherLocalProgress, progressToLocal, readNoFollow, readRegular } from "../../scripts/lib/darkmem-progress-move.mjs";
import { STUB_KEY, sha, startStub } from "./stub-server.mjs";
import { git, makeHome, makeRepo, namedPipe, read, run, scratch, write } from "./helpers.mjs";

const LEDGER = name => `# SDD ledger — plan: docs/dforge/plans/${name}.md\nTask 1: complete (commits aaaa..bbbb)\n`;
const LATEST = "## State\n- Plan: `docs/dforge/plans/p1.md`\n";

function repoWithWorktree() {
  const repo = makeRepo();
  const worktree = path.join(scratch("dms-wt-"), "side");
  git(repo, "worktree", "add", "-q", "-b", "side", worktree);
  return { repo, worktree };
}

test("progress sources come from every checkout, and agreeing copies are one source", () => {
  const { repo, worktree } = repoWithWorktree();
  write(path.join(repo, ".dforge", "sdd", "p1", "progress.md"), LEDGER("p1"));
  write(path.join(repo, ".dforge", "sdd", "p1", "handoff.md"), "# Handoff p1\n");
  write(path.join(repo, ".dforge", "sdd", "p1", "brief.md"), "a workspace file, not progress\n");
  write(path.join(repo, ".dforge", "handoff", "latest.md"), LATEST);
  write(path.join(worktree, ".dforge", "sdd", "p1", "progress.md"), LEDGER("p1"));
  write(path.join(worktree, ".dforge", "sdd", "p2", "progress.md"), LEDGER("p2"));
  write(path.join(worktree, ".dforge", "handoff", "latest.md"), "a linked worktree's latest.md is not progress\n");
  const { problems, files, sources } = gatherLocalProgress({ repoRoot: repo });
  assert.deepEqual(problems, []);
  assert.deepEqual(sources.map(item => item.rel).sort(), ["handoff/latest.md", "sdd/p1/handoff.md", "sdd/p1/progress.md", "sdd/p2/progress.md"]);
  assert.equal(files.length, 5);
  assert.equal(sources.find(item => item.kind === "handoff").uri, "dforge/handoff/p1.md");
});

test("an unusable plan directory, unreadable text and disagreeing copies are all problems", () => {
  const { repo, worktree } = repoWithWorktree();
  write(path.join(repo, ".dforge", "sdd", "bad name", "handoff.md"), "# note\n");
  write(path.join(repo, ".dforge", "sdd", "p1", "progress.md"), LEDGER("p1"));
  write(path.join(worktree, ".dforge", "sdd", "p1", "progress.md"), `${LEDGER("p1")}Task 2: complete (commits cccc..dddd)\n`);
  write(path.join(repo, ".dforge", "sdd", "p3", "handoff.md"), Buffer.from([0xff, 0xfe]));
  const { problems } = gatherLocalProgress({ repoRoot: repo });
  assert.equal(problems.length, 3, problems.join("\n"));
  assert.match(problems.join("\n"), /bad name: not a usable workstream key$/m);
  assert.match(problems.join("\n"), /^sdd\/p1\/progress\.md: .+ and .+ differ$/m);
  assert.match(problems.join("\n"), /p3[\\/]handoff\.md: empty or not UTF-8 text$/m);
});

test("an equal ledger on darkmem is already filed; a different ledger, handoff note or mirror copy is a problem", async t => {
  const stub = await startStub();
  t.after(() => stub.close());
  const client = createClient({ url: stub.url, apiKey: STUB_KEY, runKey: "seed" });
  const repo = makeRepo();
  const mirror = scratch("dms-mirror-");
  write(path.join(repo, ".dforge", "sdd", "p1", "progress.md"), LEDGER("p1"));
  write(path.join(repo, ".dforge", "sdd", "p2", "progress.md"), LEDGER("p2"));
  write(path.join(repo, ".dforge", "sdd", "p2", "handoff.md"), "# local note\n");
  write(path.join(repo, ".dforge", "handoff", "latest.md"), "local latest\n");
  const { workstream } = await client.append({ project: "proj", workstream: "p1", entries: [{ kind: "ledger", body: LEDGER("p1") }] });
  await client.append({ project: "proj", workstream: "p2", entries: [{ kind: "ledger", body: "# SDD ledger — plan: elsewhere\n" }] });
  await client.putDocument({ project: "proj", uri: "dforge/handoff/p2.md", content: "# darkmem note\n" });
  write(path.join(mirror, "work", "handoff", "latest.md"), "mirror latest\n");
  const { sources } = gatherLocalProgress({ repoRoot: repo });
  const { problems, filed } = await checkProgressTargets({ cfg: { project: "proj", mirror }, client }, sources);
  assert.deepEqual([...filed], [["p1", workstream.id]]);
  assert.equal(problems.length, 3, problems.join("\n"));
  assert.match(problems.join("\n"), /^sdd\/p2\/progress\.md: darkmem already holds a different ledger for workstream p2$/m);
  assert.match(problems.join("\n"), /^dforge\/handoff\/p2\.md: darkmem already holds a different handoff note$/m);
  assert.match(problems.join("\n"), /work[\\/]handoff[\\/]latest\.md: the mirror already holds a different copy of handoff\/latest\.md$/m);
});

// A mapped repository whose only pending family is progress, moving toward
// `target`. Plans p1, p2 and p4 are recorded in completed.md, committed before
// the linked worktree is cut, so no ledger counts as in progress in either
// checkout; p4's plan file is written by the test that needs it.
async function setup(t, target) {
  const stub = await startStub();
  t.after(() => stub.close());
  const repo = makeRepo();
  write(path.join(repo, "docs", "dforge", "plans", "p1.md"), "# p1\n");
  write(path.join(repo, "docs", "dforge", "plans", "p2.md"), "# p2\n");
  write(path.join(repo, "docs", "dforge", "plans", "completed.md"), "- `docs/dforge/plans/p1.md`\n- `docs/dforge/plans/p2.md`\n- `docs/dforge/plans/p4.md`\n");
  git(repo, "add", "docs");
  git(repo, "commit", "-q", "-m", "plans");
  const worktree = path.join(scratch("dms-wt-"), "side");
  git(repo, "worktree", "add", "-q", "-b", "side", worktree);
  const home = makeHome({
    repo,
    config: { darkmemEnabled: true, darkmem: { url: stub.url, api_key_env: "DARKMEM_API_KEY", repos: { [repo]: { project: "proj", documentStore: "local", progressSource: target } } } },
    stores: { documents: "local", progress: target === "darkmem" ? "local" : "darkmem" },
  });
  const seed = createClient({ url: stub.url, apiKey: STUB_KEY, runKey: "seed" });
  return {
    stub, repo, worktree, ...home, seed,
    state: () => JSON.parse(fs.readFileSync(path.join(home.mirror, ".sync-state.json"), "utf8")),
    stores: () => {
      const { documents, progress } = JSON.parse(fs.readFileSync(path.join(home.home, ".dforge", "stores.json"), "utf8"))[repo];
      return { documents, progress };
    },
    reconcile: () => run(["reconcile"], { cwd: repo, env: home.env }),
  };
}

const movedAside = dir => (fs.existsSync(path.join(dir, ".dforge")) ? fs.readdirSync(path.join(dir, ".dforge")).filter(name => /^moved-\d{8}T\d{6}Z$/.test(name)) : []);

test("progress moves into darkmem from every checkout, and a second run does nothing", async t => {
  const s = await setup(t, "darkmem");
  write(path.join(s.repo, ".dforge", "sdd", "p1", "progress.md"), LEDGER("p1"));
  write(path.join(s.repo, ".dforge", "sdd", "p1", "handoff.md"), "# Handoff p1\n");
  write(path.join(s.repo, ".dforge", "sdd", "p1", "brief.md"), "workspace\n");
  write(path.join(s.repo, ".dforge", "handoff", "latest.md"), LATEST);
  write(path.join(s.worktree, ".dforge", "sdd", "p1", "progress.md"), LEDGER("p1"));
  write(path.join(s.worktree, ".dforge", "sdd", "p2", "progress.md"), LEDGER("p2"));
  const result = await s.reconcile();
  assert.equal(result.code, 0, result.stdout + result.stderr);
  assert.match(result.stdout, /^darkmem-sync reconcile: progress moved to darkmem$/m);
  for (const key of ["p1", "p2"]) {
    const ws = s.stub.db.workstreams.find(w => w.key === key);
    assert.equal(ws.state, "closed");
    const ledger = ws.entries.filter(e => e.kind === "ledger");
    assert.equal(ledger.map(e => e.body).join(""), LEDGER(key));
    assert.equal(read(path.join(s.workRoot, "sdd", key, "progress.md")), LEDGER(key));
    assert.deepEqual(s.state().ledgers[key], { offset: Buffer.byteLength(LEDGER(key)), prefix: sha(LEDGER(key)), lastSeq: ledger.at(-1).seq });
  }
  assert.equal(s.stub.db.documents.get("proj\u0000dforge/handoff/p1.md").content, "# Handoff p1\n");
  assert.equal(read(path.join(s.workRoot, "sdd", "p1", "handoff.md")), "# Handoff p1\n");
  assert.equal(s.state().documents["dforge/handoff/p1.md"], sha("# Handoff p1\n"));
  assert.equal(read(path.join(s.workRoot, "handoff", "latest.md")), LATEST);
  const p1 = s.stub.db.workstreams.find(w => w.key === "p1");
  const [checkpoint, ...more] = p1.entries.filter(e => e.kind === "checkpoint");
  assert.equal(checkpoint.body, LATEST, "latest.md is filed as a checkpoint of the plan it names");
  assert.deepEqual(more, []);
  assert.equal(p1.state, "closed", "a closed workstream is closed again after its checkpoint");
  assert.equal(s.state().checkpoint, sha(LATEST));
  for (const dir of [s.repo, s.worktree]) assert.equal(git(dir, "status", "--porcelain", "--untracked-files=all", "--", ".dforge"), "", `${dir}'s backup is ignored`);
  assert.equal(s.state().checkpointAt, checkpoint.created_at);
  assert.deepEqual(s.state().checkpointAtByWorkstream, { p1: checkpoint.created_at });
  assert.match(result.stdout, /^ {2}latest\.md filed as a checkpoint of p1$/m);
  assert.deepEqual(s.stores(), { documents: "local", progress: "darkmem" });
  const [primaryAside] = movedAside(s.repo);
  assert.equal(read(path.join(s.repo, ".dforge", primaryAside, "sdd", "p1", "progress.md")), LEDGER("p1"));
  assert.equal(read(path.join(s.repo, ".dforge", primaryAside, "sdd", "p1", "handoff.md")), "# Handoff p1\n");
  assert.equal(read(path.join(s.repo, ".dforge", primaryAside, "handoff", "latest.md")), LATEST);
  assert.equal(fs.existsSync(path.join(s.repo, ".dforge", "sdd", "p1", "progress.md")), false);
  assert.equal(read(path.join(s.repo, ".dforge", "sdd", "p1", "brief.md")), "workspace\n", "workspaces stay");
  const [sideAside] = movedAside(s.worktree);
  assert.equal(read(path.join(s.worktree, ".dforge", sideAside, "sdd", "p2", "progress.md")), LEDGER("p2"));
  assert.equal(fs.existsSync(path.join(s.worktree, ".dforge", "sdd", "p1", "progress.md")), false);
  const again = await s.reconcile();
  assert.equal(again.code, 0, again.stdout + again.stderr);
  assert.equal(again.stdout, "");
});

test("a ledger darkmem already holds unchanged is not filed again, so a stopped move can run again", async t => {
  const s = await setup(t, "darkmem");
  write(path.join(s.repo, ".dforge", "sdd", "p1", "progress.md"), LEDGER("p1"));
  await s.seed.append({ project: "proj", workstream: "p1", entries: [{ kind: "ledger", body: LEDGER("p1") }] });
  const result = await s.reconcile();
  assert.equal(result.code, 0, result.stdout + result.stderr);
  assert.match(result.stdout, /^darkmem-sync reconcile: progress moved to darkmem$/m);
  const ws = s.stub.db.workstreams.find(w => w.key === "p1");
  assert.equal(ws.entries.length, 1);
  assert.equal(ws.state, "closed");
  assert.equal(s.state().ledgers.p1.lastSeq, ws.entries[0].seq);
});

test("a latest.md that names no plan is copied unsent, behind darkmem's newest checkpoint", async t => {
  const s = await setup(t, "darkmem");
  const { workstream } = await s.seed.append({ project: "proj", workstream: "p9", entries: [{ kind: "checkpoint", body: "## State\n- Plan: `docs/dforge/plans/p9.md`\n" }] });
  write(path.join(s.repo, ".dforge", "handoff", "latest.md"), "a note with no State section\n");
  const result = await s.reconcile();
  assert.equal(result.code, 0, result.stdout + result.stderr);
  assert.match(result.stdout, /^darkmem-sync reconcile: progress moved to darkmem$/m);
  assert.match(result.stdout, /^ {2}latest\.md names no plan or draft; copied to the mirror, not sent$/m);
  assert.equal(read(path.join(s.workRoot, "handoff", "latest.md")), "a note with no State section\n");
  assert.equal(s.state().checkpoint, sha("a note with no State section\n"));
  assert.equal(s.state().checkpointAt, workstream.last_entry_at);
  assert.deepEqual(s.state().checkpointAtByWorkstream, { p9: workstream.last_entry_at });
  assert.equal(s.stub.db.workstreams.flatMap(w => w.entries).filter(e => e.kind === "checkpoint").length, 1);
});

test("a copy dated at a checkpoint of a workstream key with a slash leaves a loadable state", async t => {
  const s = await setup(t, "darkmem");
  await s.seed.append({ project: "proj", workstream: "feature/foo", entries: [{ kind: "checkpoint", body: "# Foo\n" }] });
  write(path.join(s.repo, ".dforge", "handoff", "latest.md"), "a note with no State section\n");
  const result = await s.reconcile();
  assert.equal(result.code, 0, result.stdout + result.stderr);
  assert.doesNotThrow(() => loadState(path.join(s.mirror, ".sync-state.json")));
  const pull = await run(["pull"], { cwd: s.repo, env: s.env });
  assert.equal(pull.code, 0, pull.stdout + pull.stderr);
});

test("a ledger's workstream properties read its plan in its own checkout", async t => {
  const s = await setup(t, "darkmem");
  write(path.join(s.worktree, "docs", "dforge", "plans", "p4.md"), "# p4\n\n**Spec:** `docs/dforge/specs/s4.md`\n");
  write(path.join(s.worktree, ".dforge", "sdd", "p4", "progress.md"), LEDGER("p4"));
  const result = await s.reconcile();
  assert.equal(result.code, 0, result.stdout + result.stderr);
  const { plan_uri, spec_uri } = s.stub.db.workstreams.find(w => w.key === "p4").properties;
  assert.deepEqual({ plan_uri, spec_uri }, { plan_uri: "dforge/plans/p4.md", spec_uri: "dforge/specs/s4.md" });
});

test("documents and progress both move to darkmem in one run, and the ledger's properties read the plan from the mirror", async t => {
  const s = await setup(t, "darkmem");
  write(path.join(s.repo, "docs", "dforge", "plans", "p1.md"), "# p1\n\n**Spec:** `docs/dforge/specs/s1.md`\n");
  write(path.join(s.repo, "docs", "dforge", "specs", "s1.md"), "# s1\n");
  git(s.repo, "add", "docs");
  git(s.repo, "commit", "-q", "-m", "spec");
  write(path.join(s.home, ".dforge", "config.json"), JSON.stringify({ darkmemEnabled: true, darkmem: { url: s.stub.url, api_key_env: "DARKMEM_API_KEY", repos: { [s.repo]: { project: "proj" } } } }));
  write(path.join(s.repo, ".dforge", "sdd", "p1", "progress.md"), LEDGER("p1"));
  const result = await s.reconcile();
  assert.equal(result.code, 0, result.stdout + result.stderr);
  assert.match(result.stdout, /^darkmem-sync reconcile: documents moved to darkmem$/m);
  assert.match(result.stdout, /^darkmem-sync reconcile: progress moved to darkmem$/m);
  assert.equal(fs.existsSync(path.join(s.repo, "docs", "dforge", "plans", "p1.md")), false, "the documents move ran first and removed the checkout's copy");
  const { plan_uri, spec_uri } = s.stub.db.workstreams.find(w => w.key === "p1").properties;
  assert.deepEqual({ plan_uri, spec_uri }, { plan_uri: "dforge/plans/p1.md", spec_uri: "dforge/specs/s1.md" });
  assert.deepEqual(s.stores(), { documents: "darkmem", progress: "darkmem" });
});

const UP_REFUSALS = [
  {
    name: "copies of one ledger that differ between checkouts",
    plant: async s => {
      write(path.join(s.repo, ".dforge", "sdd", "p1", "progress.md"), LEDGER("p1"));
      write(path.join(s.worktree, ".dforge", "sdd", "p1", "progress.md"), `${LEDGER("p1")}Task 2: complete (commits cccc..dddd)\n`);
    },
    detail: /^ {2}sdd\/p1\/progress\.md: .+ and .+ differ$/m,
  },
  {
    name: "a plan directory that is not a workstream key",
    plant: async s => write(path.join(s.repo, ".dforge", "sdd", "bad name", "handoff.md"), "# note\n"),
    detail: /^ {2}.+bad name: not a usable workstream key$/m,
  },
  {
    name: "a different ledger on darkmem",
    plant: async s => {
      write(path.join(s.repo, ".dforge", "sdd", "p1", "progress.md"), LEDGER("p1"));
      await s.seed.append({ project: "proj", workstream: "p1", entries: [{ kind: "ledger", body: "# SDD ledger — plan: elsewhere\n" }] });
    },
    detail: /^ {2}sdd\/p1\/progress\.md: darkmem already holds a different ledger for workstream p1$/m,
  },
  {
    name: "a different copy in the mirror",
    plant: async s => {
      write(path.join(s.repo, ".dforge", "sdd", "p1", "progress.md"), LEDGER("p1"));
      write(path.join(s.workRoot, "sdd", "p1", "progress.md"), "other\n");
    },
    detail: /the mirror already holds a different copy of sdd\/p1\/progress\.md$/m,
  },
];

for (const row of UP_REFUSALS) {
  test(`progress stays local on ${row.name}, and nothing is sent or moved`, async t => {
    const s = await setup(t, "darkmem");
    await row.plant(s);
    const before = s.stub.db.requests.length;
    const result = await s.reconcile();
    assert.equal(result.code, 1, result.stdout + result.stderr);
    assert.match(result.stdout, /^darkmem-sync reconcile: progress stay local \(configured darkmem\): /m);
    assert.match(result.stdout, row.detail);
    assert.deepEqual(s.stub.db.requests.slice(before).filter(r => r.method !== "GET").map(r => `${r.method} ${r.path}`), []);
    assert.equal(s.stores().progress, "local");
    assert.deepEqual(movedAside(s.repo), []);
  });
}

test("a progress file or mirror copy that cannot be read is a problem, not a crash", async t => {
  const stub = await startStub();
  t.after(() => stub.close());
  const client = createClient({ url: stub.url, apiKey: STUB_KEY, runKey: "seed" });
  const repo = makeRepo();
  const mirror = scratch("dms-mirror-");
  fs.mkdirSync(path.join(repo, ".dforge", "sdd", "p1", "progress.md"), { recursive: true });
  write(path.join(repo, ".dforge", "sdd", "p2", "progress.md"), LEDGER("p2"));
  fs.mkdirSync(path.join(mirror, "work", "sdd", "p2", "progress.md"), { recursive: true });
  const { problems, sources } = gatherLocalProgress({ repoRoot: repo });
  assert.deepEqual(problems.map(line => line.replace(repo, "<repo>").split(path.sep).join("/")), ["<repo>/.dforge/sdd/p1/progress.md: could not be read (EISDIR)"]);
  const checked = await checkProgressTargets({ cfg: { project: "proj", mirror }, client }, sources);
  assert.deepEqual(checked.problems.map(line => line.replace(mirror, "<mirror>").split(path.sep).join("/")), ["<mirror>/work/sdd/p2/progress.md: could not be read (EISDIR)"]);
});

test("a state directory whose sdd cannot be listed is a problem, not a crash", () => {
  const repo = makeRepo();
  write(path.join(repo, ".dforge", "sdd"), "not a directory\n");
  const { problems, sources } = gatherLocalProgress({ repoRoot: repo });
  assert.deepEqual(problems, [`${path.join(repo, ".dforge", "sdd")}: could not be read (ENOTDIR)`]);
  assert.deepEqual(sources, []);
});

test("a symbolic-linked progress file is a problem, and is not read through", { skip: process.platform === "win32" }, () => {
  const repo = makeRepo();
  const outside = path.join(scratch("dms-link-"), "progress.md");
  write(outside, LEDGER("p1"));
  const link = path.join(repo, ".dforge", "sdd", "p1", "progress.md");
  fs.mkdirSync(path.dirname(link), { recursive: true });
  fs.symlinkSync(outside, link);
  const { problems, sources } = gatherLocalProgress({ repoRoot: repo });
  assert.deepEqual(problems, [`${link}: a symbolic link, which the move will not read through`]);
  assert.deepEqual(sources, []);
});

test("a dangling progress.md link is a problem, not a ledger left behind", { skip: process.platform === "win32" }, () => {
  const repo = makeRepo();
  const link = path.join(repo, ".dforge", "sdd", "p1", "progress.md");
  fs.mkdirSync(path.dirname(link), { recursive: true });
  fs.symlinkSync(path.join(scratch("dms-link-"), "missing.md"), link);
  const { problems, sources } = gatherLocalProgress({ repoRoot: repo });
  assert.deepEqual(problems, [`${link}: a symbolic link, which the move will not read through`]);
  assert.deepEqual(sources, []);
});

test("a dangling progress.md link in the mirror leaves status as it was", { skip: process.platform === "win32" }, async t => {
  const s = await setup(t, "local");
  write(path.join(s.workRoot, "sdd", "p2", "progress.md"), LEDGER("p2"));
  const before = await run(["status"], { cwd: s.repo, env: s.env });
  assert.equal(before.code, 0, before.stdout + before.stderr);
  const link = path.join(s.workRoot, "sdd", "p1", "progress.md");
  fs.mkdirSync(path.dirname(link), { recursive: true });
  fs.symlinkSync(path.join(scratch("dms-link-"), "missing.md"), link);
  const after = await run(["status"], { cwd: s.repo, env: s.env });
  assert.deepEqual(after, before);
});

// Replaces `victim` with a link to `outside` the first time the code lstats
// or opens it: after an lstat, so a check that read it as a file then follows
// the link, or before an open, so an open that follows links reads `outside`.
function swapToLink(t, victim, outside) {
  let swapped = false;
  const swap = () => {
    swapped = true;
    fs.unlinkSync(victim);
    fs.symlinkSync(outside, victim);
  };
  const lstat = fs.lstatSync;
  t.mock.method(fs, "lstatSync", (file, ...rest) => {
    const stat = lstat(file, ...rest);
    if (!swapped && file === victim) swap();
    return stat;
  });
  const open = fs.openSync;
  t.mock.method(fs, "openSync", (file, ...rest) => {
    if (!swapped && file === victim) swap();
    return open(file, ...rest);
  });
}

test("readNoFollow reads a regular file and refuses a link, a dangling link, a link to a named pipe and a directory", { skip: process.platform === "win32" }, () => {
  const dir = scratch("dms-read-");
  const file = path.join(dir, "file");
  write(file, "bytes\n");
  fs.symlinkSync(file, path.join(dir, "link"));
  fs.symlinkSync(path.join(dir, "missing"), path.join(dir, "dangling"));
  fs.symlinkSync(namedPipe(path.join(dir, "pipe")), path.join(dir, "pipe-link"));
  fs.mkdirSync(path.join(dir, "dir"));
  assert.equal(readNoFollow(file).toString(), "bytes\n");
  for (const [name, code] of [["link", "ELOOP"], ["dangling", "ELOOP"], ["pipe-link", "ELOOP"], ["dir", "EISDIR"], ["missing", "ENOENT"]]) {
    assert.throws(() => readNoFollow(path.join(dir, name)), { code }, name);
  }
});

test("readRegular with follow reads through a link, and refuses a named pipe, a link to one and a directory", { skip: process.platform === "win32" }, () => {
  const dir = scratch("dms-read-");
  const file = path.join(dir, "file");
  write(file, "bytes\n");
  fs.symlinkSync(file, path.join(dir, "link"));
  fs.symlinkSync(namedPipe(path.join(dir, "pipe")), path.join(dir, "pipe-link"));
  fs.mkdirSync(path.join(dir, "dir"));
  assert.equal(readRegular(path.join(dir, "link"), { follow: true }).toString(), "bytes\n");
  for (const [name, code] of [["pipe", "EFTYPE"], ["pipe-link", "EFTYPE"], ["dir", "EISDIR"], ["missing", "ENOENT"]]) {
    assert.throws(() => readRegular(path.join(dir, name), { follow: true }), { code }, name);
  }
});

for (const removed of ["O_NOFOLLOW", "O_NONBLOCK"]) {
  test(`without ${removed}, as on Windows, readNoFollow refuses a link by lstat before it reads, and readRegular with follow reads through it`, { skip: process.platform === "win32" }, t => {
    const dir = scratch("dms-read-");
    const file = path.join(dir, "file");
    const link = path.join(dir, "link");
    write(file, "bytes\n");
    fs.symlinkSync(file, link);
    const windows = { ...fs.constants, [removed]: undefined };
    const lstat = t.mock.method(fs, "lstatSync");
    assert.equal(readNoFollow(file, windows).toString(), "bytes\n");
    assert.equal(lstat.mock.callCount(), 1, "the fallback lstats before it reads");
    assert.throws(() => readNoFollow(link, windows), { code: "ELOOP" });
    assert.equal(readRegular(link, { follow: true }, windows).toString(), "bytes\n");
  });
}

test("a link swapped in for a file after any lstat of it is still not read through", { skip: process.platform === "win32" }, t => {
  const dir = scratch("dms-read-");
  const victim = path.join(dir, "progress.md");
  const outside = path.join(dir, "outside.md");
  write(victim, "inside\n");
  write(outside, "outside\n");
  swapToLink(t, victim, outside);
  assert.throws(() => readNoFollow(victim), { code: "ELOOP" });
});

test("a checkout ledger swapped for a link after its check is a problem, and is not read through", { skip: process.platform === "win32" }, t => {
  const repo = makeRepo();
  const ledger = path.join(repo, ".dforge", "sdd", "p1", "progress.md");
  const outside = path.join(scratch("dms-link-"), "progress.md");
  write(ledger, LEDGER("p1"));
  write(outside, LEDGER("p1"));
  swapToLink(t, ledger, outside);
  const { problems, sources } = gatherLocalProgress({ repoRoot: repo });
  assert.deepEqual(problems, [`${ledger}: a symbolic link, which the move will not read through`]);
  assert.deepEqual(sources, []);
});

test("a git worktree list that fails is the one problem", () => {
  const missing = path.join(scratch("dms-gone-"), "missing");
  const { problems, files, sources } = gatherLocalProgress({ repoRoot: missing });
  assert.equal(problems.length, 1, problems.join("\n"));
  assert.match(problems[0], /^git worktree list failed in .+missing: \S/);
  assert.deepEqual([files, sources], [[], []]);
});

test("progress reached through a symbolic link stays local, and nothing is sent or moved", { skip: process.platform === "win32" }, async t => {
  const s = await setup(t, "darkmem");
  write(path.join(s.repo, ".dforge", "sdd", "p1", "progress.md"), LEDGER("p1"));
  fs.symlinkSync(path.join(s.repo, ".dforge"), path.join(s.worktree, ".dforge"));
  const before = s.stub.db.requests.length;
  const result = await s.reconcile();
  assert.equal(result.code, 1, result.stdout + result.stderr);
  assert.ok(result.stdout.includes("darkmem-sync reconcile: progress stay local (configured darkmem): the checkouts' progress is reached through symbolic links; nothing was sent or moved\n"), result.stdout);
  assert.ok(result.stdout.includes(`  ${path.join(s.worktree, ".dforge")}: a symbolic link, which the move will not move files through\n`), result.stdout);
  assert.deepEqual(s.stub.db.requests.slice(before).filter(r => r.method !== "GET").map(r => `${r.method} ${r.path}`), []);
  assert.equal(s.stores().progress, "local");
  assert.deepEqual(movedAside(s.repo), []);
  assert.equal(read(path.join(s.repo, ".dforge", "sdd", "p1", "progress.md")), LEDGER("p1"));
});

test("a darkmem error inside the move refuses it as a failure during the move, and nothing is moved", async t => {
  const s = await setup(t, "darkmem");
  write(path.join(s.repo, ".dforge", "sdd", "p1", "handoff.md"), "# Handoff p1\n");
  s.stub.db.failures.push({ method: "POST", path: "/api/v1/documents", status: 503, detail: "busy" });
  const result = await s.reconcile();
  assert.equal(result.code, 1, result.stdout + result.stderr);
  assert.match(result.stdout, /^darkmem-sync reconcile: progress stay local \(configured darkmem\): darkmem failed during the move: .*503: busy$/m);
  assert.equal(s.stores().progress, "local");
  assert.deepEqual(movedAside(s.repo), []);
});

test("a ledger that changes while the move sends it stays local, and nothing is copied or moved", async t => {
  const s = await setup(t, "darkmem");
  const ledger = path.join(s.repo, ".dforge", "sdd", "p1", "progress.md");
  write(ledger, LEDGER("p1"));
  let appended = false;
  s.stub.db.onRequest = (method, pathname) => {
    if (appended || method !== "POST" || pathname !== "/api/v1/worklog/entries") return;
    appended = true;
    fs.appendFileSync(ledger, "Task 9: late\n");
  };
  const result = await s.reconcile();
  assert.equal(result.code, 1, result.stdout + result.stderr);
  assert.ok(result.stdout.includes("darkmem-sync reconcile: progress stay local (configured darkmem): progress changed in the checkouts during the move; nothing was moved locally\n"), result.stdout);
  assert.ok(result.stdout.includes(`  ${ledger}: changed or removed during the move\n`), result.stdout);
  assert.equal(s.stores().progress, "local");
  assert.deepEqual(movedAside(s.repo), []);
  assert.ok(read(ledger).endsWith("Task 9: late\n"));
  assert.equal(fs.existsSync(path.join(s.workRoot, "sdd", "p1", "progress.md")), false);
});

test("a ledger that darkmem reads back different stays local, and nothing is copied or moved", async t => {
  const s = await setup(t, "darkmem");
  const ledger = path.join(s.repo, ".dforge", "sdd", "p1", "progress.md");
  write(ledger, LEDGER("p1"));
  let appended = false;
  let altered = false;
  s.stub.db.onRequest = (method, pathname) => {
    if (method === "POST" && pathname === "/api/v1/worklog/entries") appended = true;
    if (!appended || altered || method !== "GET" || !pathname.endsWith("/entries")) return;
    altered = true;
    for (const ws of s.stub.db.workstreams) for (const entry of ws.entries) if (entry.kind === "ledger") entry.body += "altered\n";
  };
  const result = await s.reconcile();
  assert.equal(result.code, 1, result.stdout + result.stderr);
  assert.ok(result.stdout.includes("darkmem-sync reconcile: progress stay local (configured darkmem): a read-back of darkmem's copies differs; nothing was moved locally\n"), result.stdout);
  assert.ok(result.stdout.includes("  sdd/p1/progress.md: darkmem's copy reads back different\n"), result.stdout);
  assert.equal(s.stores().progress, "local");
  assert.deepEqual(movedAside(s.repo), []);
  assert.equal(read(ledger), LEDGER("p1"));
  assert.equal(fs.existsSync(path.join(s.workRoot, "sdd", "p1", "progress.md")), false);
});

test("a handoff note that darkmem reads back different stays local, and nothing is copied or moved", async t => {
  const s = await setup(t, "darkmem");
  const note = path.join(s.repo, ".dforge", "sdd", "p1", "handoff.md");
  write(note, "# Handoff p1\n");
  s.stub.db.onRequest = (method, pathname) => {
    const held = s.stub.db.documents.get("proj\u0000dforge/handoff/p1.md");
    if (held && method === "GET" && pathname === "/api/v1/documents/by-uri") held.content_hash = sha("altered\n");
  };
  const result = await s.reconcile();
  assert.equal(result.code, 1, result.stdout + result.stderr);
  assert.ok(result.stdout.includes("darkmem-sync reconcile: progress stay local (configured darkmem): a read-back of darkmem's copies differs; nothing was moved locally\n"), result.stdout);
  assert.ok(result.stdout.includes("  dforge/handoff/p1.md: darkmem's copy reads back different\n"), result.stdout);
  assert.equal(s.stores().progress, "local");
  assert.deepEqual(movedAside(s.repo), []);
  assert.equal(read(note), "# Handoff p1\n");
});

test("a checkpoint that darkmem reads back different stays local, and nothing is copied or moved", async t => {
  const s = await setup(t, "darkmem");
  const latest = path.join(s.repo, ".dforge", "handoff", "latest.md");
  write(latest, LATEST);
  s.stub.db.onRequest = (method, pathname) => {
    if (method !== "GET" || pathname !== "/api/v1/worklog/resume") return;
    for (const ws of s.stub.db.workstreams) for (const entry of ws.entries) if (entry.kind === "checkpoint") entry.body = "altered\n";
  };
  const result = await s.reconcile();
  assert.equal(result.code, 1, result.stdout + result.stderr);
  assert.ok(result.stdout.includes("darkmem-sync reconcile: progress stay local (configured darkmem): a read-back of darkmem's copies differs; nothing was moved locally\n"), result.stdout);
  assert.ok(result.stdout.includes("  handoff/latest.md: darkmem's checkpoint reads back different\n"), result.stdout);
  assert.equal(s.stores().progress, "local");
  assert.deepEqual(movedAside(s.repo), []);
  assert.equal(read(latest), LATEST);
  assert.equal(fs.existsSync(path.join(s.workRoot, "handoff", "latest.md")), false);
});

test("a plan that starts while darkmem is written keeps progress local, and nothing is copied or moved", async t => {
  const s = await setup(t, "darkmem");
  write(path.join(s.repo, ".dforge", "sdd", "p1", "progress.md"), LEDGER("p1"));
  let started = false;
  s.stub.db.onRequest = (method, pathname) => {
    if (started || method !== "POST" || pathname !== "/api/v1/worklog/entries") return;
    started = true;
    write(path.join(s.repo, ".dforge", "sdd", "p3", "progress.md"), LEDGER("p3"));
  };
  const result = await s.reconcile();
  assert.equal(result.code, 1, result.stdout + result.stderr);
  assert.ok(result.stdout.includes("darkmem-sync reconcile: progress stay local (configured darkmem): a plan is in progress: docs/dforge/plans/p3.md\n"), result.stdout);
  assert.equal(s.stores().progress, "local");
  assert.deepEqual(movedAside(s.repo), []);
  assert.equal(fs.existsSync(path.join(s.workRoot, "sdd", "p1", "progress.md")), false);
});

test("a ledger linked to a named pipe while darkmem is written is in progress, and is never opened for a blocking read", { skip: process.platform === "win32" }, async t => {
  const s = await setup(t, "darkmem");
  write(path.join(s.repo, ".dforge", "sdd", "p1", "progress.md"), LEDGER("p1"));
  const pipe = namedPipe(path.join(scratch("dms-pipe-"), "pipe"));
  const late = path.join(s.repo, ".dforge", "sdd", "p3", "progress.md");
  let linked = false;
  s.stub.db.onRequest = (method, pathname) => {
    if (linked || method !== "POST" || pathname !== "/api/v1/worklog/entries") return;
    linked = true;
    fs.mkdirSync(path.dirname(late), { recursive: true });
    fs.symlinkSync(pipe, late);
  };
  const result = await s.reconcile();
  assert.equal(result.code, 1, result.stdout + result.stderr);
  assert.ok(result.stdout.includes(`darkmem-sync reconcile: progress stay local (configured darkmem): a plan is in progress: ${late}\n`), result.stdout);
  assert.equal(s.stores().progress, "local");
  assert.deepEqual(movedAside(s.repo), []);
});

test("a mirror directory linked while darkmem is written refuses the move, and nothing is written through it", { skip: process.platform === "win32" }, async t => {
  const s = await setup(t, "darkmem");
  const note = path.join(s.repo, ".dforge", "sdd", "p1", "handoff.md");
  write(note, "# Handoff p1\n");
  const outside = scratch("dms-outside-");
  const planDir = path.join(s.workRoot, "sdd", "p1");
  let linked = false;
  s.stub.db.onRequest = (method, pathname) => {
    if (linked || method !== "POST" || pathname !== "/api/v1/documents") return;
    linked = true;
    fs.rmSync(planDir, { recursive: true, force: true });
    fs.mkdirSync(path.dirname(planDir), { recursive: true });
    fs.symlinkSync(outside, planDir);
  };
  const result = await s.reconcile();
  assert.equal(result.code, 1, result.stdout + result.stderr);
  assert.ok(result.stdout.includes("darkmem-sync reconcile: progress stay local (configured darkmem): the mirror's progress is reached through symbolic links; nothing was moved locally, and darkmem keeps what it accepted\n"), result.stdout);
  assert.ok(result.stdout.includes(`  ${planDir}: a symbolic link in the mirror, which the move will not read through\n`), result.stdout);
  assert.deepEqual(fs.readdirSync(outside), []);
  assert.equal(read(note), "# Handoff p1\n");
  assert.deepEqual(movedAside(s.repo), []);
  assert.equal(s.stores().progress, "local");
});

test("a named pipe where a ledger belongs is in progress, and is never opened for a blocking read", { skip: process.platform === "win32" }, async t => {
  const s = await setup(t, "darkmem");
  const ledger = namedPipe(path.join(s.repo, ".dforge", "sdd", "p1", "progress.md"));
  const result = await s.reconcile();
  assert.equal(result.code, 1, result.stdout + result.stderr);
  assert.ok(result.stdout.includes(`darkmem-sync reconcile: progress stay local (configured darkmem): a plan is in progress: ${ledger}\n`), result.stdout);
  assert.equal(s.stub.db.requests.length, 0);
});

test("a named pipe at the mirror's copy of a ledger is a problem, and is never opened for a blocking read", { skip: process.platform === "win32" }, async t => {
  const s = await setup(t, "darkmem");
  write(path.join(s.repo, ".dforge", "sdd", "p1", "progress.md"), LEDGER("p1"));
  const target = namedPipe(path.join(s.workRoot, "sdd", "p1", "progress.md"));
  const result = await s.reconcile();
  assert.equal(result.code, 1, result.stdout + result.stderr);
  assert.ok(result.stdout.includes("darkmem-sync reconcile: progress stay local (configured darkmem): darkmem or the mirror already holds different progress\n"), result.stdout);
  assert.ok(result.stdout.includes(`  ${target}: could not be read (EFTYPE)\n`), result.stdout);
  assert.equal(s.stores().progress, "local");
});

test("a handoff note linked to a named pipe while darkmem is written stays local, and the recheck never blocks on it", { skip: process.platform === "win32" }, async t => {
  const s = await setup(t, "darkmem");
  const note = path.join(s.repo, ".dforge", "sdd", "p1", "handoff.md");
  write(note, "# Handoff p1\n");
  const pipe = namedPipe(path.join(scratch("dms-pipe-"), "pipe"));
  let linked = false;
  s.stub.db.onRequest = (method, pathname) => {
    if (linked || method !== "POST" || pathname !== "/api/v1/documents") return;
    linked = true;
    fs.rmSync(note);
    fs.symlinkSync(pipe, note);
  };
  const result = await s.reconcile();
  assert.equal(result.code, 1, result.stdout + result.stderr);
  assert.ok(result.stdout.includes("darkmem-sync reconcile: progress stay local (configured darkmem): progress changed in the checkouts during the move; nothing was moved locally\n"), result.stdout);
  assert.ok(result.stdout.includes(`  ${note}: changed or removed during the move\n`), result.stdout);
  assert.equal(fs.lstatSync(note).isSymbolicLink(), true);
  assert.equal(s.stores().progress, "local");
  assert.deepEqual(movedAside(s.repo), []);
});

for (const [slugs, count] of [[["p1"], "1 source"], [["p1", "p2"], "2 sources"]]) {
  test(`a move-aside that leaves ${count} behind names them in one line, still ignores the backup, and a rerun finishes the move`, async t => {
    const s = await setup(t, "darkmem");
    const ledgers = slugs.map(slug => path.join(s.repo, ".dforge", "sdd", slug, "progress.md"));
    for (const [k, slug] of slugs.entries()) write(ledgers[k], LEDGER(slug));
    // A non-empty directory at each ledger's backup path, for every stamp the next minute can name.
    const now = Date.now();
    const blockers = [];
    for (let i = 0; i < 60; i += 1) {
      const dir = path.join(s.repo, ".dforge", `moved-${utcStamp(new Date(now + i * 1000))}`);
      blockers.push(dir);
      for (const slug of slugs) write(path.join(dir, "sdd", slug, "progress.md", "keep"), "taken\n");
    }
    const result = await s.reconcile();
    assert.equal(result.code, 1, result.stdout + result.stderr);
    assert.doesNotMatch(result.stderr, /unexpected error/);
    const named = slugs.map(() => ".+progress\\.md \\(\\w+\\)").join(", ");
    assert.match(result.stdout, new RegExp(`^darkmem-sync reconcile: progress stay local \\(configured darkmem\\): darkmem and the mirror hold the progress, but ${count} could not be moved aside: ${named}; reconcile again to finish$`, "m"));
    for (const [k, slug] of slugs.entries()) assert.equal(read(ledgers[k]), LEDGER(slug));
    assert.equal(read(path.join(s.repo, ".dforge", ".gitignore")), "*\n");
    assert.equal(s.stores().progress, "local");
    for (const dir of blockers) fs.rmSync(dir, { recursive: true });
    const again = await s.reconcile();
    assert.equal(again.code, 0, again.stdout + again.stderr);
    assert.match(again.stdout, /^darkmem-sync reconcile: progress moved to darkmem$/m);
    for (const ledger of ledgers) assert.equal(fs.existsSync(ledger), false);
  });
}

test("a move-aside that leaves a source behind and cannot write .gitignore still ends in the refusal", async t => {
  const s = await setup(t, "darkmem");
  const ledger = path.join(s.repo, ".dforge", "sdd", "p1", "progress.md");
  write(ledger, LEDGER("p1"));
  const now = Date.now();
  for (let i = 0; i < 60; i += 1) {
    const dir = path.join(s.repo, ".dforge", `moved-${utcStamp(new Date(now + i * 1000))}`);
    write(path.join(dir, "sdd", "p1", "progress.md", "keep"), "taken\n");
  }
  // This host runs as root, which bypasses chmod, so the write is made to fail.
  const preload = path.join(scratch("dms-preload-"), "preload.mjs");
  write(preload, [
    'import fs from "node:fs";',
    'import path from "node:path";',
    "const w = fs.writeFileSync;",
    "fs.writeFileSync = (f, ...a) => {",
    '  if (String(f).endsWith(`${path.sep}.dforge${path.sep}.gitignore`)) throw Object.assign(new Error("injected by the test"), { code: "EACCES", syscall: "open" });',
    "  return w(f, ...a);",
    "};",
    "",
  ].join("\n"));
  const result = await run(["reconcile"], { cwd: s.repo, env: { ...s.env, NODE_OPTIONS: `--import ${pathToFileURL(preload).href}` } });
  assert.equal(result.code, 1, result.stdout + result.stderr);
  assert.doesNotMatch(result.stderr, /unexpected error/);
  assert.match(result.stdout, /^darkmem-sync reconcile: progress stay local \(configured darkmem\): darkmem and the mirror hold the progress, but 1 source could not be moved aside: .+progress\.md \(\w+\), and .+\.dforge[\\/]\.gitignore \(EACCES\) could not be written; reconcile again to finish$/m);
  assert.equal(read(ledger), LEDGER("p1"));
  assert.equal(fs.existsSync(path.join(s.repo, ".dforge", ".gitignore")), false);
  assert.equal(s.stores().progress, "local");
});

test("a move that sets every source aside but cannot write .gitignore still moves, and names the file", async t => {
  const s = await setup(t, "darkmem");
  const ledger = path.join(s.repo, ".dforge", "sdd", "p1", "progress.md");
  write(ledger, LEDGER("p1"));
  // This host runs as root, which bypasses chmod, so the write is made to fail.
  const preload = path.join(scratch("dms-preload-"), "preload.mjs");
  write(preload, [
    'import fs from "node:fs";',
    'import path from "node:path";',
    "const w = fs.writeFileSync;",
    "fs.writeFileSync = (f, ...a) => {",
    '  if (String(f).endsWith(`${path.sep}.dforge${path.sep}.gitignore`)) throw Object.assign(new Error("injected by the test"), { code: "EACCES", syscall: "open" });',
    "  return w(f, ...a);",
    "};",
    "",
  ].join("\n"));
  const result = await run(["reconcile"], { cwd: s.repo, env: { ...s.env, NODE_OPTIONS: `--import ${pathToFileURL(preload).href}` } });
  assert.equal(result.code, 0, result.stdout + result.stderr);
  assert.doesNotMatch(result.stderr, /unexpected error/);
  assert.match(result.stdout, /^darkmem-sync reconcile: progress moved to darkmem$/m);
  assert.ok(result.stdout.includes(`  ${path.join(s.repo, ".dforge", ".gitignore")} could not be written (EACCES)\n`), result.stdout);
  assert.equal(fs.existsSync(ledger), false);
  assert.equal(movedAside(s.repo).length, 1);
  assert.equal(fs.existsSync(path.join(s.repo, ".dforge", ".gitignore")), false);
  assert.equal(s.stores().progress, "darkmem");
});

test("latest.md filed for an active plan leaves its workstream open, even one that was closed", async t => {
  const s = await setup(t, "darkmem");
  const { workstream } = await s.seed.append({ project: "proj", workstream: "p3", entries: [{ kind: "note", body: "earlier\n" }] });
  await s.seed.updateWorkstream(workstream.id, { state: "closed", retain: true });
  write(path.join(s.repo, ".dforge", "handoff", "latest.md"), "## State\n- Plan: `docs/dforge/plans/p3.md`\n");
  const result = await s.reconcile();
  assert.equal(result.code, 0, result.stdout + result.stderr);
  assert.match(result.stdout, /^ {2}latest\.md filed as a checkpoint of p3$/m);
  assert.equal(s.stub.db.workstreams.find(w => w.key === "p3").state, "open", "p3 is not in completed.md");
});

test("latest.md filed for a completed plan closes the workstream it opens", async t => {
  const s = await setup(t, "darkmem");
  write(path.join(s.repo, ".dforge", "handoff", "latest.md"), "## State\n- Plan: `docs/dforge/plans/p2.md`\n");
  const result = await s.reconcile();
  assert.equal(result.code, 0, result.stdout + result.stderr);
  const ws = s.stub.db.workstreams.find(w => w.key === "p2");
  assert.equal(ws.state, "closed", "completed.md records p2");
  assert.equal(ws.retain, true);
  assert.equal(ws.entries.filter(e => e.kind === "checkpoint").length, 1);
});

test("a ledger darkmem refuses names what darkmem now holds, and nothing is moved locally", async t => {
  const s = await setup(t, "darkmem");
  write(path.join(s.repo, ".dforge", "sdd", "p1", "progress.md"), LEDGER("p1"));
  write(path.join(s.repo, ".dforge", "sdd", "p2", "progress.md"), LEDGER("p2"));
  write(path.join(s.repo, ".dforge", "sdd", "p2", "handoff.md"), "# Handoff p2\n");
  s.stub.db.failures.push({ method: "POST", path: "/api/v1/worklog/entries", status: 422, detail: "refused by the test" });
  const result = await s.reconcile();
  assert.equal(result.code, 1, result.stdout + result.stderr);
  assert.ok(result.stdout.includes("darkmem-sync reconcile: progress stay local (configured darkmem): darkmem refused part of the progress; nothing was moved locally, and darkmem keeps what it accepted\n"), result.stdout);
  assert.ok(result.stdout.includes("  sdd/p1/progress.md: darkmem refused an entry: refused by the test\n"), result.stdout);
  assert.ok(result.stdout.includes("  darkmem now holds in full: sdd/p2/progress.md, dforge/handoff/p2.md\n"), result.stdout);
  assert.equal(s.stores().progress, "local");
  assert.deepEqual(movedAside(s.repo), []);
});

test("a plan directory that is a symbolic link stays local, and nothing is sent or moved", { skip: process.platform === "win32" }, async t => {
  const s = await setup(t, "darkmem");
  const outside = path.join(scratch("dms-link-"), "p1");
  write(path.join(outside, "progress.md"), LEDGER("p1"));
  const link = path.join(s.worktree, ".dforge", "sdd", "p1");
  fs.mkdirSync(path.dirname(link), { recursive: true });
  fs.symlinkSync(outside, link);
  const before = s.stub.db.requests.length;
  const result = await s.reconcile();
  assert.equal(result.code, 1, result.stdout + result.stderr);
  // Reconcile's in-progress check counts a linked plan directory before the
  // move runs; the move's own listing names it too.
  assert.ok(result.stdout.includes(`darkmem-sync reconcile: progress stay local (configured darkmem): a plan is in progress: ${link}\n`), result.stdout);
  assert.deepEqual(gatherLocalProgress({ repoRoot: s.repo }).problems, [`${link}: a symbolic link, which the move will not move files through`]);
  assert.deepEqual(s.stub.db.requests.slice(before).filter(r => r.method !== "GET").map(r => `${r.method} ${r.path}`), []);
  assert.equal(s.stores().progress, "local");
  assert.deepEqual(movedAside(s.worktree), []);
});

for (const { name, plant, linked, unwritten } of [
  {
    name: "a plan directory in the mirror",
    plant: s => {
      fs.mkdirSync(path.join(s.workRoot, "sdd"), { recursive: true });
      fs.symlinkSync(scratch("dms-link-"), path.join(s.workRoot, "sdd", "p1"));
    },
    linked: s => path.join(s.workRoot, "sdd", "p1"),
    unwritten: s => path.join(fs.realpathSync(path.join(s.workRoot, "sdd", "p1")), "progress.md"),
  },
  {
    name: "the mirror itself",
    plant: s => {
      fs.mkdirSync(path.dirname(s.mirror), { recursive: true });
      fs.symlinkSync(scratch("dms-link-"), s.mirror);
    },
    linked: s => s.mirror,
    unwritten: s => path.join(fs.realpathSync(s.mirror), "work"),
  },
]) {
  test(`progress stays local when ${name} is a symbolic link, and nothing is sent or written through it`, { skip: process.platform === "win32" }, async t => {
    const s = await setup(t, "darkmem");
    write(path.join(s.repo, ".dforge", "sdd", "p1", "progress.md"), LEDGER("p1"));
    plant(s);
    const result = await s.reconcile();
    assert.equal(result.code, 1, result.stdout + result.stderr);
    assert.ok(result.stdout.includes("darkmem-sync reconcile: progress stay local (configured darkmem): the mirror's progress is reached through symbolic links; nothing was sent or moved\n"), result.stdout);
    assert.ok(result.stdout.includes(`  ${linked(s)}: a symbolic link in the mirror, which the move will not read through\n`), result.stdout);
    assert.deepEqual(s.stub.db.requests.filter(r => r.method !== "GET").map(r => `${r.method} ${r.path}`), []);
    assert.equal(fs.existsSync(unwritten(s)), false, "nothing is written through the link");
    assert.equal(s.stores().progress, "local");
    assert.deepEqual(movedAside(s.repo), []);
  });
}

test("progress moves back into the primary checkout from closed and open workstreams, and darkmem keeps its copy", async t => {
  const s = await setup(t, "local");
  const { workstream } = await s.seed.append({ project: "proj", workstream: "p1", entries: [{ kind: "ledger", body: LEDGER("p1") }] });
  await s.seed.append({ project: "proj", workstream: "p1", entries: [{ kind: "checkpoint", body: LATEST }] });
  await s.seed.updateWorkstream(workstream.id, { state: "closed", retain: true });
  await s.seed.append({ project: "proj", workstream: "p2", entries: [{ kind: "ledger", body: LEDGER("p2") }] });
  await s.seed.putDocument({ project: "proj", uri: "dforge/handoff/p1.md", content: "# Handoff p1\n" });
  assert.equal(fs.existsSync(s.mirror), false, "the mirror starts empty");
  const result = await s.reconcile();
  assert.equal(result.code, 0, result.stdout + result.stderr);
  assert.match(result.stdout, /^darkmem-sync reconcile: progress moved to local$/m);
  const stateDir = path.join(s.repo, ".dforge");
  assert.equal(read(path.join(stateDir, "sdd", "p1", "progress.md")), LEDGER("p1"), "a closed workstream's ledger comes back");
  assert.equal(read(path.join(stateDir, "sdd", "p2", "progress.md")), LEDGER("p2"));
  assert.equal(read(path.join(stateDir, "sdd", "p1", "handoff.md")), "# Handoff p1\n");
  assert.equal(read(path.join(stateDir, "handoff", "latest.md")), LATEST);
  assert.equal(fs.existsSync(s.workRoot), false);
  const [aside] = fs.readdirSync(s.mirror).filter(name => /^work-moved-\d{8}T\d{6}Z$/.test(name));
  assert.equal(read(path.join(s.mirror, aside, "sdd", "p1", "progress.md")), LEDGER("p1"));
  const after = s.state();
  assert.deepEqual(after.ledgers, {});
  assert.equal(after.checkpoint, null);
  assert.equal(after.checkpointAt, null);
  assert.deepEqual(after.pendingLinks, []);
  assert.equal("dforge/handoff/p1.md" in after.documents, false);
  assert.deepEqual(s.stores(), { documents: "local", progress: "local" });
  assert.equal(s.stub.db.workstreams.length, 2);
  assert.equal(s.stub.db.documents.has("proj\u0000dforge/handoff/p1.md"), true);
  const again = await s.reconcile();
  assert.equal(again.code, 0, again.stdout + again.stderr);
  assert.equal(again.stdout, "");
});

test("progress stays in darkmem when the primary checkout holds a different file", async t => {
  const s = await setup(t, "local");
  await s.seed.append({ project: "proj", workstream: "p1", entries: [{ kind: "ledger", body: LEDGER("p1") }] });
  write(path.join(s.repo, ".dforge", "sdd", "p1", "progress.md"), "a local ledger\n");
  const result = await s.reconcile();
  assert.equal(result.code, 1, result.stdout + result.stderr);
  assert.match(result.stdout, /^darkmem-sync reconcile: progress stay darkmem \(configured local\): /m);
  assert.match(result.stdout, /^ {2}.+sdd[\\/]p1[\\/]progress\.md: differs from the mirror's sdd\/p1\/progress\.md$/m);
  assert.equal(read(path.join(s.repo, ".dforge", "sdd", "p1", "progress.md")), "a local ledger\n");
  assert.equal(read(path.join(s.workRoot, "sdd", "p1", "progress.md")), LEDGER("p1"));
  assert.equal(s.stores().progress, "darkmem");
});

test("a workstream opened on darkmem since the mirror's last pull, for an unfinished plan, keeps progress in darkmem", async t => {
  const s = await setup(t, "local");
  await s.seed.append({ project: "proj", workstream: "p3", entries: [{ kind: "ledger", body: "# SDD ledger — plan: docs/dforge/plans/p3.md\nTask 1: implementer x (assigned)\n" }] });
  const result = await s.reconcile();
  assert.equal(result.code, 1, result.stdout + result.stderr);
  assert.match(result.stdout, /^darkmem-sync reconcile: progress stay darkmem \(configured local\): a plan is in progress: /m);
  assert.equal(fs.existsSync(path.join(s.repo, ".dforge", "sdd", "p3")), false, "nothing is copied");
  assert.equal(fs.existsSync(path.join(s.workRoot, "sdd", "p3", "progress.md")), true, "the mirror keeps the pulled ledger");
  assert.equal(s.stores().progress, "darkmem");
});

test("a primary state directory reached through a symbolic link keeps progress in darkmem, and nothing is copied", { skip: process.platform === "win32" }, async t => {
  const s = await setup(t, "local");
  await s.seed.append({ project: "proj", workstream: "p1", entries: [{ kind: "ledger", body: LEDGER("p1") }] });
  const outside = scratch("dms-link-");
  fs.mkdirSync(path.join(s.repo, ".dforge"), { recursive: true });
  fs.symlinkSync(outside, path.join(s.repo, ".dforge", "sdd"));
  const result = await s.reconcile();
  assert.equal(result.code, 1, result.stdout + result.stderr);
  assert.ok(result.stdout.includes("darkmem-sync reconcile: progress stay darkmem (configured local): .dforge is reached through symbolic links; nothing was copied\n"), result.stdout);
  assert.ok(result.stdout.includes("  .dforge/sdd: a symbolic link, which the move will not write through\n"), result.stdout);
  assert.deepEqual(fs.readdirSync(outside), []);
  assert.equal(read(path.join(s.workRoot, "sdd", "p1", "progress.md")), LEDGER("p1"));
  assert.equal(s.stores().progress, "darkmem");
});

for (const [what, plant, code] of [["a directory", file => fs.mkdirSync(file, { recursive: true }), "EISDIR"], ["a named pipe", namedPipe, "EFTYPE"]]) {
  test(`a primary checkout file that is ${what} keeps progress in darkmem, not a crash or a blocking read`, { skip: code === "EFTYPE" && process.platform === "win32" }, async t => {
    const s = await setup(t, "local");
    await s.seed.append({ project: "proj", workstream: "p1", entries: [{ kind: "ledger", body: LEDGER("p1") }] });
    const target = path.join(s.repo, ".dforge", "sdd", "p1", "progress.md");
    plant(target);
    const result = await s.reconcile();
    assert.equal(result.code, 1, result.stdout + result.stderr);
    assert.match(result.stdout, /^darkmem-sync reconcile: progress stay darkmem \(configured local\): the primary checkout cannot take the mirror's progress$/m);
    assert.ok(result.stdout.includes(`  ${target}: could not be read (${code})\n`), result.stdout);
    assert.equal(s.stores().progress, "darkmem");
  });
}

test("a mirror that lost latest.md takes darkmem's newest checkpoint again before the move back", async t => {
  const s = await setup(t, "local");
  await s.seed.append({ project: "proj", workstream: "p1", entries: [{ kind: "ledger", body: LEDGER("p1") }, { kind: "checkpoint", body: LATEST }] });
  assert.equal((await run(["pull"], { cwd: s.repo, env: s.env })).code, 0);
  const mirrored = path.join(s.workRoot, "handoff", "latest.md");
  assert.equal(read(mirrored), LATEST);
  fs.rmSync(mirrored);
  const result = await s.reconcile();
  assert.equal(result.code, 0, result.stdout + result.stderr);
  assert.match(result.stdout, /^darkmem-sync reconcile: progress moved to local$/m);
  assert.equal(read(path.join(s.repo, ".dforge", "handoff", "latest.md")), LATEST);
});

for (const [what, plant, code] of [["a directory", file => fs.mkdirSync(file, { recursive: true }), "EISDIR"], ["a named pipe", namedPipe, "EFTYPE"]]) {
  test(`a mirror latest.md that is ${what} keeps progress in darkmem, not a crash or a blocking read`, { skip: code === "EFTYPE" && process.platform === "win32" }, async t => {
    const s = await setup(t, "local");
    await s.seed.append({ project: "proj", workstream: "p1", entries: [{ kind: "ledger", body: LEDGER("p1") }, { kind: "checkpoint", body: LATEST }] });
    plant(path.join(s.workRoot, "handoff", "latest.md"));
    const result = await s.reconcile();
    assert.equal(result.code, 1, result.stdout + result.stderr);
    assert.match(result.stdout, /^darkmem-sync reconcile: progress stay darkmem \(configured local\): the pull into the mirror did not finish cleanly$/m);
    assert.ok(result.stdout.includes(`  failed: handoff/latest.md: could not be read (${code})\n`), result.stdout);
    assert.equal(s.stores().progress, "darkmem");
  });
}

test("a mirror latest.md that cannot be written keeps progress in darkmem, not a crash", async t => {
  const s = await setup(t, "local");
  await s.seed.append({ project: "proj", workstream: "p1", entries: [{ kind: "ledger", body: LEDGER("p1") }, { kind: "checkpoint", body: LATEST }] });
  // The atomic write's temporary file cannot be made where a directory stands.
  fs.mkdirSync(path.join(s.workRoot, "handoff", ".latest.md.tmp"), { recursive: true });
  const result = await s.reconcile();
  assert.equal(result.code, 1, result.stdout + result.stderr);
  assert.doesNotMatch(result.stderr, /unexpected error/);
  assert.match(result.stdout, /^darkmem-sync reconcile: progress stay darkmem \(configured local\): the pull into the mirror did not finish cleanly$/m);
  assert.match(result.stdout, /^ {2}failed: handoff\/latest\.md: could not be written \(\w+\)$/m);
  assert.equal(fs.existsSync(path.join(s.repo, ".dforge", "handoff", "latest.md")), false);
  assert.equal(s.stores().progress, "darkmem");
});

test("a symbolic link among the mirror's progress keeps progress in darkmem, and nothing is read through it", { skip: process.platform === "win32" }, async t => {
  const s = await setup(t, "local");
  await s.seed.append({ project: "proj", workstream: "p1", entries: [{ kind: "ledger", body: LEDGER("p1") }] });
  // A handoff note, which reconcile's in-progress check never reads, so the
  // move's own walk of the mirror is what refuses it.
  const outside = path.join(scratch("dms-link-"), "handoff.md");
  write(outside, "# Handoff p1\n");
  const link = path.join(s.workRoot, "sdd", "p1", "handoff.md");
  fs.mkdirSync(path.dirname(link), { recursive: true });
  fs.symlinkSync(outside, link);
  const result = await s.reconcile();
  assert.equal(result.code, 1, result.stdout + result.stderr);
  assert.match(result.stdout, /^darkmem-sync reconcile: progress stay darkmem \(configured local\): the mirror's progress is reached through symbolic links; nothing was pulled or copied$/m);
  assert.ok(result.stdout.includes(`  ${link}: a symbolic link in the mirror, which the move will not read through\n`), result.stdout);
  assert.equal(fs.existsSync(path.join(s.repo, ".dforge", "sdd", "p1", "progress.md")), false);
  assert.equal(s.stores().progress, "darkmem");
});

test("a linked mirror ledger is refused before the pull, so newer darkmem content neither reads through nor replaces it", { skip: process.platform === "win32" }, async t => {
  const s = await setup(t, "local");
  await s.seed.append({ project: "proj", workstream: "p1", entries: [{ kind: "ledger", body: LEDGER("p1") }] });
  const outside = path.join(scratch("dms-link-"), "progress.md");
  const older = "# SDD ledger — plan: docs/dforge/plans/p1.md\n";
  write(outside, older);
  const link = path.join(s.workRoot, "sdd", "p1", "progress.md");
  fs.mkdirSync(path.dirname(link), { recursive: true });
  fs.symlinkSync(outside, link);
  const result = await s.reconcile();
  assert.equal(result.code, 1, result.stdout + result.stderr);
  // Reconcile's in-progress check will not read a ledger through a link either.
  assert.ok(result.stdout.includes(`darkmem-sync reconcile: progress stay darkmem (configured local): a plan is in progress: ${link}\n`), result.stdout);
  assert.equal(fs.lstatSync(link).isSymbolicLink(), true);
  assert.equal(fs.readFileSync(outside, "utf8"), older);
  assert.equal(s.stores().progress, "darkmem");
});

test("a symbolic-linked mirror work directory keeps progress in darkmem, and nothing is read through it", { skip: process.platform === "win32" }, async t => {
  const s = await setup(t, "local");
  await s.seed.append({ project: "proj", workstream: "p1", entries: [{ kind: "ledger", body: LEDGER("p1") }] });
  const outside = scratch("dms-link-");
  const outsideLedger = path.join(outside, "sdd", "p1", "progress.md");
  const outsideText = "# SDD ledger — plan: docs/dforge/plans/p1.md\n";
  write(outsideLedger, outsideText);
  fs.rmSync(s.workRoot, { recursive: true, force: true });
  fs.mkdirSync(path.dirname(s.workRoot), { recursive: true });
  fs.symlinkSync(outside, s.workRoot);
  const result = await s.reconcile();
  assert.equal(result.code, 1, result.stdout + result.stderr);
  assert.match(result.stdout, /^darkmem-sync reconcile: progress stay darkmem \(configured local\): the mirror's progress is reached through symbolic links; nothing was pulled or copied$/m);
  assert.ok(result.stdout.includes(`  ${s.workRoot}: a symbolic link in the mirror, which the move will not read through\n`), result.stdout);
  assert.equal(fs.existsSync(path.join(s.repo, ".dforge", "sdd", "p1", "progress.md")), false);
  assert.equal(fs.readFileSync(outsideLedger, "utf8"), outsideText);
  assert.equal(s.stores().progress, "darkmem");
});

// The move back run directly and offline, over a mirror holding two ledgers,
// so a test can stand in for fs between its reads and its copies.
function offlineMove() {
  const repo = makeRepo();
  const mirror = scratch("dms-mirror-");
  write(path.join(mirror, "work", "sdd", "p1", "progress.md"), LEDGER("p1"));
  write(path.join(mirror, "work", "sdd", "p2", "progress.md"), LEDGER("p2"));
  const context = { cfg: { repoRoot: repo, mirror }, client: null, state: emptyState(), persist: () => {} };
  return { mirror, context, target: slug => path.join(repo, ".dforge", "sdd", slug, "progress.md") };
}

test("an edit that lands in the primary checkout just before a copy is never overwritten", async t => {
  const m = offlineMove();
  const mkdir = fs.mkdirSync;
  t.mock.method(fs, "mkdirSync", (dir, options) => {
    const made = mkdir(dir, options);
    if (dir === path.dirname(m.target("p1")) && !fs.existsSync(m.target("p1"))) fs.writeFileSync(m.target("p1"), "edited meanwhile\n");
    return made;
  });
  const result = await progressToLocal(m.context, { offline: "test" });
  assert.equal(result.moved, false);
  assert.equal(result.reason, "the primary checkout changed during the move; nothing was overwritten");
  assert.deepEqual(result.details, [`${m.target("p1")}: changed during the move; not overwritten`, `${m.target("p2")}: copied`]);
  assert.equal(read(m.target("p1")), "edited meanwhile\n");
  assert.equal(fs.existsSync(path.join(m.mirror, "work")), true, "the mirror's copies are not set aside");
});

test("an edit that lands between the read and the exclusive copy is a change during the move, not a failed copy", async t => {
  const m = offlineMove();
  const copy = fs.copyFileSync;
  t.mock.method(fs, "copyFileSync", (from, to, mode) => {
    if (to !== m.target("p1")) return copy(from, to, mode);
    fs.writeFileSync(to, "edited meanwhile\n");
    throw Object.assign(new Error("injected by the test"), { code: "EEXIST" });
  });
  const result = await progressToLocal(m.context, { offline: "test" });
  assert.equal(result.moved, false);
  assert.equal(result.reason, "the primary checkout changed during the move; nothing was overwritten");
  assert.deepEqual(result.details, [`${m.target("p1")}: changed during the move; not overwritten`, `${m.target("p2")}: copied`]);
  assert.equal(read(m.target("p1")), "edited meanwhile\n");
  assert.equal(fs.existsSync(path.join(m.mirror, "work")), true, "the mirror's copies are not set aside");
});

test("a copy into the primary checkout that fails part-way is a refusal, not a crash, and a rerun finishes it", async t => {
  const m = offlineMove();
  const copy = fs.copyFileSync;
  let calls = 0;
  t.mock.method(fs, "copyFileSync", (...args) => {
    calls += 1;
    if (calls === 2) throw Object.assign(new Error("injected by the test"), { code: "EIO" });
    return copy(...args);
  });
  const result = await progressToLocal(m.context, { offline: "test" });
  assert.equal(result.moved, false);
  assert.equal(result.reason, "a copy into the primary checkout failed (EIO); the files copied so far stay, and a rerun copies the rest");
  assert.deepEqual(result.details, [`${m.target("p1")}: copied`]);
  assert.equal(fs.existsSync(path.join(m.mirror, "work")), true, "the mirror's copies are not set aside");
  t.mock.restoreAll();
  const again = await progressToLocal(m.context, { offline: "test" });
  assert.equal(again.moved, true, again.reason);
  assert.equal(read(m.target("p1")), LEDGER("p1"));
  assert.equal(read(m.target("p2")), LEDGER("p2"));
});

test("a mirror work directory that cannot be listed is named as such, not as a symbolic link", async () => {
  const m = offlineMove();
  const work = path.join(m.mirror, "work");
  fs.rmSync(work, { recursive: true });
  write(work, "not a directory\n");
  const result = await progressToLocal(m.context, { offline: "test" });
  assert.equal(result.moved, false);
  assert.equal(result.reason, "the mirror's progress could not be listed; nothing was pulled or copied");
  assert.deepEqual(result.details, [`${work}: could not be listed (ENOTDIR)`]);
});

test("a mirror ledger that lstat cannot reach while ledgers are listed is a problem line from the read, not a crash", async t => {
  const m = offlineMove();
  const ledger = path.join(m.mirror, "work", "sdd", "p1", "progress.md");
  // As if its directory turned unreadable after it was listed: every look at
  // the ledger fails, the listing's lstat and the read's open alike.
  const denied = () => {
    throw Object.assign(new Error("injected by the test"), { code: "EACCES" });
  };
  const lstat = fs.lstatSync;
  t.mock.method(fs, "lstatSync", (file, ...rest) => (file === ledger ? denied() : lstat(file, ...rest)));
  const open = fs.openSync;
  t.mock.method(fs, "openSync", (file, ...rest) => (file === ledger ? denied() : open(file, ...rest)));
  const result = await progressToLocal(m.context, { offline: "test" });
  assert.equal(result.moved, false);
  assert.equal(result.reason, "the primary checkout cannot take the mirror's progress");
  assert.deepEqual(result.details, [`${ledger}: could not be read (EACCES)`]);
});

test("a mirror ledger swapped for a link after its check is refused, and nothing is read through it", { skip: process.platform === "win32" }, async t => {
  const m = offlineMove();
  const ledger = path.join(m.mirror, "work", "sdd", "p1", "progress.md");
  const outside = path.join(scratch("dms-link-"), "progress.md");
  write(outside, LEDGER("p1"));
  swapToLink(t, ledger, outside);
  const result = await progressToLocal(m.context, { offline: "test" });
  assert.equal(result.moved, false);
  assert.equal(result.reason, "the primary checkout cannot take the mirror's progress");
  assert.deepEqual(result.details, [`${ledger}: a symbolic link in the mirror, which the move will not read through`]);
  assert.equal(fs.existsSync(m.target("p1")), false);
});

test("a mirror ledger whose directory turns into a file before its read is a problem line, not a crash", async t => {
  const m = offlineMove();
  const dir = path.join(m.mirror, "work", "sdd", "p1");
  const latest = path.join(m.mirror, "work", "handoff", "latest.md");
  // The move asks whether latest.md exists after it lists the ledgers and
  // before it reads them.
  const exists = fs.existsSync;
  t.mock.method(fs, "existsSync", file => {
    if (file === latest && fs.statSync(dir, { throwIfNoEntry: false })?.isDirectory()) {
      fs.rmSync(dir, { recursive: true });
      fs.writeFileSync(dir, "not a directory\n");
    }
    return exists(file);
  });
  const result = await progressToLocal(m.context, { offline: "test" });
  assert.equal(result.moved, false);
  assert.equal(result.reason, "the primary checkout cannot take the mirror's progress");
  assert.deepEqual(result.details, [`${path.join(dir, "progress.md")}: could not be read (ENOTDIR)`]);
});

test("a mirror ledger that cannot be opened is a problem line, whoever runs the test", async t => {
  const m = offlineMove();
  const ledger = path.join(m.mirror, "work", "sdd", "p1", "progress.md");
  const open = fs.openSync;
  t.mock.method(fs, "openSync", (file, ...rest) => {
    if (file === ledger) throw Object.assign(new Error("injected by the test"), { code: "EACCES" });
    return open(file, ...rest);
  });
  const result = await progressToLocal(m.context, { offline: "test" });
  assert.equal(result.moved, false);
  assert.equal(result.reason, "the primary checkout cannot take the mirror's progress");
  assert.deepEqual(result.details, [`${ledger}: could not be read (EACCES)`]);
});

test("a link that lands at a checkout target just before its copy is never read or written through", { skip: process.platform === "win32" }, async t => {
  const m = offlineMove();
  const outside = path.join(scratch("dms-link-"), "progress.md");
  write(outside, LEDGER("p1"));
  const mkdir = fs.mkdirSync;
  t.mock.method(fs, "mkdirSync", (dir, options) => {
    const made = mkdir(dir, options);
    if (dir === path.dirname(m.target("p1")) && !fs.lstatSync(m.target("p1"), { throwIfNoEntry: false })) fs.symlinkSync(outside, m.target("p1"));
    return made;
  });
  const result = await progressToLocal(m.context, { offline: "test" });
  assert.equal(result.moved, false);
  assert.equal(result.reason, "a copy into the primary checkout failed (ELOOP); the files copied so far stay, and a rerun copies the rest");
  assert.deepEqual(result.details, []);
  assert.equal(fs.lstatSync(m.target("p1")).isSymbolicLink(), true);
  assert.equal(fs.existsSync(path.join(m.mirror, "work")), true, "the mirror's copies are not set aside");
});

test("a link that replaces a copied target before the read-back is never read through", { skip: process.platform === "win32" }, async t => {
  const m = offlineMove();
  const outside = path.join(scratch("dms-link-"), "progress.md");
  write(outside, LEDGER("p1"));
  const copy = fs.copyFileSync;
  t.mock.method(fs, "copyFileSync", (from, to, mode) => {
    copy(from, to, mode);
    if (to === m.target("p2")) {
      fs.rmSync(m.target("p1"));
      fs.symlinkSync(outside, m.target("p1"));
    }
  });
  const result = await progressToLocal(m.context, { offline: "test" });
  assert.equal(result.moved, false);
  assert.equal(result.reason, "a copy into the primary checkout failed (ELOOP); the files copied so far stay, and a rerun copies the rest");
  assert.deepEqual(result.details, [`${m.target("p1")}: copied`, `${m.target("p2")}: copied`]);
  assert.equal(fs.existsSync(path.join(m.mirror, "work")), true, "the mirror's copies are not set aside");
});

const ABSOLUTE_LEDGER = file => `# SDD ledger — plan: ${file}\nTask 1: complete (commits aaaa..bbbb)\n`;

test("an absolute ledger identity into the checkout counts as finished after the documents move removed it", async t => {
  const s = await setup(t, "darkmem");
  write(path.join(s.home, ".dforge", "config.json"), JSON.stringify({ darkmemEnabled: true, darkmem: { url: s.stub.url, api_key_env: "DARKMEM_API_KEY", repos: { [s.repo]: { project: "proj" } } } }));
  write(path.join(s.repo, ".dforge", "sdd", "p1", "progress.md"), ABSOLUTE_LEDGER(path.join(s.repo, "docs", "dforge", "plans", "p1.md")));
  const result = await s.reconcile();
  assert.equal(result.code, 0, result.stdout + result.stderr);
  assert.match(result.stdout, /^darkmem-sync reconcile: documents moved to darkmem$/m);
  assert.match(result.stdout, /^darkmem-sync reconcile: progress moved to darkmem$/m);
  assert.equal(fs.existsSync(path.join(s.repo, "docs", "dforge", "plans", "p1.md")), false, "the documents move ran first");
});

test("a worktree's ledger whose absolute identity points into the primary checkout counts as finished", async t => {
  const s = await setup(t, "darkmem");
  write(path.join(s.worktree, ".dforge", "sdd", "p2", "progress.md"), ABSOLUTE_LEDGER(path.join(s.repo, "docs", "dforge", "plans", "p2.md")));
  const result = await s.reconcile();
  assert.equal(result.code, 0, result.stdout + result.stderr);
  assert.match(result.stdout, /^darkmem-sync reconcile: progress moved to darkmem$/m);
});

test("an absolute ledger identity under no root stays in progress and is named, even beside a completed.md naming it", async t => {
  const s = await setup(t, "darkmem");
  const elsewhere = path.join(scratch("dms-elsewhere-"), "docs", "dforge", "plans", "p1.md");
  write(path.join(path.dirname(elsewhere), "completed.md"), `- \`${elsewhere}\`\n`);
  write(path.join(s.repo, ".dforge", "sdd", "p1", "progress.md"), ABSOLUTE_LEDGER(elsewhere));
  const result = await s.reconcile();
  assert.equal(result.code, 1, result.stdout + result.stderr);
  assert.ok(result.stdout.includes(`darkmem-sync reconcile: progress stay local (configured darkmem): a plan is in progress: ${elsewhere}\n`), result.stdout);
});

test("an absolute ledger identity through a symbolic-linked docs directory is named from its physical path", { skip: process.platform === "win32" && "directory symbolic links need privileges on Windows" }, async t => {
  const s = await setup(t, "darkmem");
  const outside = path.join(scratch("dms-docs-"), "dforge");
  fs.renameSync(path.join(s.repo, "docs", "dforge"), outside);
  fs.symlinkSync(outside, path.join(s.repo, "docs", "dforge"), "dir");
  write(path.join(s.repo, ".dforge", "sdd", "p1", "progress.md"), ABSOLUTE_LEDGER(path.join(outside, "plans", "p1.md")));
  const result = await s.reconcile();
  assert.equal(result.code, 0, result.stdout + result.stderr);
  assert.match(result.stdout, /^darkmem-sync reconcile: progress moved to darkmem$/m);
});

// 251 pieces: a stopped import holding the first 100 leaves two batches to send.
const LONG = `# SDD ledger — plan: docs/dforge/plans/p1.md\n\n${Array.from({ length: 250 }, (_, i) => `Task ${i + 1}: complete (commits aaaa..bbbb)\n\n`).join("")}`;
const FIRST_BATCH = () => ledgerPieces(LONG).slice(0, 100).map(body => ({ kind: "ledger", body }));
const ledgerOf = ws => ws.entries.filter(e => e.kind === "ledger");
const ledgerAppends = s => s.stub.db.requests.filter(r => r.method === "POST" && r.path === "/api/v1/worklog/entries" && r.body.entries[0].kind === "ledger");

test("a move stopped after its first append batch resumes the import", async t => {
  const s = await setup(t, "darkmem");
  write(path.join(s.repo, ".dforge", "sdd", "p1", "progress.md"), LONG);
  await s.seed.append({ project: "proj", workstream: "p1", entries: FIRST_BATCH() });
  const result = await s.reconcile();
  assert.equal(result.code, 0, result.stdout + result.stderr);
  assert.match(result.stdout, /^darkmem-sync reconcile: progress moved to darkmem$/m);
  const ws = s.stub.db.workstreams.find(w => w.key === "p1");
  assert.equal(ws.state, "closed");
  assert.equal(ledgerOf(ws).map(e => e.body).join(""), LONG);
  assert.equal(ledgerOf(ws).length, ledgerPieces(LONG).length);
  const resumed = ledgerAppends(s).slice(1);
  assert.equal(resumed.length, 2, "the two remaining batches");
  assert.equal(resumed[0].body.expected_last_seq, ledgerOf(ws)[99].seq, "the first resumed batch follows the stopped import");
  assert.equal(resumed[1].body.expected_last_seq, ledgerOf(ws)[199].seq, "the next batch follows the answer to the one before");
  assert.equal(read(path.join(s.workRoot, "sdd", "p1", "progress.md")), LONG);
});

test("another writer's append during a resumed import refuses the move, and nothing local moves", async t => {
  const s = await setup(t, "darkmem");
  const ledger = path.join(s.repo, ".dforge", "sdd", "p1", "progress.md");
  write(ledger, LONG);
  await s.seed.append({ project: "proj", workstream: "p1", entries: FIRST_BATCH() });
  let competed = false;
  s.stub.db.onRequest = (method, pathname) => {
    if (competed || method !== "POST" || pathname !== "/api/v1/worklog/entries") return;
    competed = true;
    const ws = s.stub.db.workstreams.find(w => w.key === "p1");
    ws.entries.push({ id: "competing", seq: s.stub.db.nextSeq++, run_key: "other", kind: "ledger", body: "another writer\n", properties: {}, created_at: new Date().toISOString() });
  };
  const result = await s.reconcile();
  assert.equal(result.code, 1, result.stdout + result.stderr);
  assert.ok(result.stdout.includes("darkmem-sync reconcile: progress stay local (configured darkmem): darkmem refused part of the progress; nothing was moved locally, and darkmem keeps what it accepted\n"), result.stdout);
  assert.match(result.stdout, /^ {2}sdd\/p1\/progress\.md: darkmem refused an entry: expected the newest ledger entry to be seq \d+, but it is \d+$/m);
  assert.equal(s.stores().progress, "local");
  assert.deepEqual(movedAside(s.repo), []);
  assert.equal(read(ledger), LONG);
  assert.equal(fs.existsSync(path.join(s.workRoot, "sdd", "p1", "progress.md")), false);
});

test("an open workstream holding no ledger entries yet is resumed from the start", async t => {
  const s = await setup(t, "darkmem");
  write(path.join(s.repo, ".dforge", "sdd", "p1", "progress.md"), LEDGER("p1"));
  await s.seed.append({ project: "proj", workstream: "p1", entries: [{ kind: "checkpoint", body: "## State\n- Plan: `docs/dforge/plans/p1.md`\n" }] });
  const result = await s.reconcile();
  assert.equal(result.code, 0, result.stdout + result.stderr);
  const ws = s.stub.db.workstreams.find(w => w.key === "p1");
  assert.equal(ws.state, "closed");
  assert.equal(ledgerOf(ws).map(e => e.body).join(""), LEDGER("p1"));
});

for (const [name, prepare] of [
  ["a closed workstream holding a prefix", async s => {
    const { workstream } = await s.seed.append({ project: "proj", workstream: "p1", entries: FIRST_BATCH() });
    await s.seed.updateWorkstream(workstream.id, { state: "closed", retain: true });
  }],
  ["a prefix ending inside a piece", async s => {
    await s.seed.append({ project: "proj", workstream: "p1", entries: [{ kind: "ledger", body: LONG.slice(0, 20) }] });
  }],
  ["a different ledger", async s => {
    await s.seed.append({ project: "proj", workstream: "p1", entries: [{ kind: "ledger", body: "# SDD ledger — plan: elsewhere\n" }] });
  }],
]) {
  test(`${name} refuses the move and sends nothing`, async t => {
    const s = await setup(t, "darkmem");
    write(path.join(s.repo, ".dforge", "sdd", "p1", "progress.md"), LONG);
    await prepare(s);
    const appends = () => s.stub.db.requests.filter(r => r.method === "POST" && r.path === "/api/v1/worklog/entries").length;
    const before = appends();
    const result = await s.reconcile();
    assert.equal(result.code, 1, result.stdout + result.stderr);
    assert.match(result.stdout, /^darkmem-sync reconcile: progress stay local \(configured darkmem\): darkmem or the mirror already holds different progress$/m);
    assert.match(result.stdout, /^ {2}sdd\/p1\/progress\.md: darkmem already holds a different ledger for workstream p1$/m);
    assert.equal(appends(), before);
    assert.equal(read(path.join(s.repo, ".dforge", "sdd", "p1", "progress.md")), LONG);
  });
}

test("a darkmem ledger whose absolute identity names a linked worktree's plan counts as finished", async t => {
  const s = await setup(t, "local");
  const identity = path.join(s.worktree, "docs", "dforge", "plans", "p2.md");
  await s.seed.append({ project: "proj", workstream: "p2", entries: [{ kind: "ledger", body: ABSOLUTE_LEDGER(identity) }] });
  const result = await s.reconcile();
  assert.equal(result.code, 0, result.stdout + result.stderr);
  assert.match(result.stdout, /^darkmem-sync reconcile: progress moved to local$/m);
});

test("a darkmem ledger whose absolute identity names a worktree nested in the primary counts as finished", async t => {
  const s = await setup(t, "local");
  fs.appendFileSync(path.join(s.repo, ".git", "info", "exclude"), ".claude/worktrees/\n");
  const nested = path.join(s.repo, ".claude", "worktrees", "nested");
  git(s.repo, "worktree", "add", "-q", "-b", "nested", nested);
  const identity = path.join(nested, "docs", "dforge", "plans", "p2.md");
  await s.seed.append({ project: "proj", workstream: "p2", entries: [{ kind: "ledger", body: ABSOLUTE_LEDGER(identity) }] });
  const result = await s.reconcile();
  assert.equal(result.code, 0, result.stdout + result.stderr);
  assert.match(result.stdout, /^darkmem-sync reconcile: progress moved to local$/m);
});
