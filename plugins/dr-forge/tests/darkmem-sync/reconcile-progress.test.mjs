import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import test from "node:test";
import { createClient } from "../../scripts/lib/darkmem-client.mjs";
import { checkProgressTargets, gatherLocalProgress } from "../../scripts/lib/darkmem-progress-move.mjs";
import { STUB_KEY, sha, startStub } from "./stub-server.mjs";
import { git, makeHome, makeRepo, read, run, scratch, write } from "./helpers.mjs";

const LEDGER = name => `# SDD ledger — plan: docs/forge/plans/${name}.md\nTask 1: complete (commits aaaa..bbbb)\n`;
const LATEST = "## State\n- Plan: `docs/forge/plans/p1.md`\n";

function repoWithWorktree() {
  const repo = makeRepo();
  const worktree = path.join(scratch("dms-wt-"), "side");
  git(repo, "worktree", "add", "-q", "-b", "side", worktree);
  return { repo, worktree };
}

test("progress sources come from every checkout, and agreeing copies are one source", () => {
  const { repo, worktree } = repoWithWorktree();
  write(path.join(repo, ".forge", "sdd", "p1", "progress.md"), LEDGER("p1"));
  write(path.join(repo, ".forge", "sdd", "p1", "handoff.md"), "# Handoff p1\n");
  write(path.join(repo, ".forge", "sdd", "p1", "brief.md"), "a workspace file, not progress\n");
  write(path.join(repo, ".forge", "handoff", "latest.md"), LATEST);
  write(path.join(worktree, ".forge", "sdd", "p1", "progress.md"), LEDGER("p1"));
  write(path.join(worktree, ".forge", "sdd", "p2", "progress.md"), LEDGER("p2"));
  write(path.join(worktree, ".forge", "handoff", "latest.md"), "a linked worktree's latest.md is not progress\n");
  const { problems, files, sources } = gatherLocalProgress({ repoRoot: repo });
  assert.deepEqual(problems, []);
  assert.deepEqual(sources.map(item => item.rel).sort(), ["handoff/latest.md", "sdd/p1/handoff.md", "sdd/p1/progress.md", "sdd/p2/progress.md"]);
  assert.equal(files.length, 5);
  assert.equal(sources.find(item => item.kind === "handoff").uri, "superpowers/handoff/p1.md");
});

test("an unusable plan directory, unreadable text and disagreeing copies are all problems", () => {
  const { repo, worktree } = repoWithWorktree();
  write(path.join(repo, ".forge", "sdd", "bad name", "handoff.md"), "# note\n");
  write(path.join(repo, ".forge", "sdd", "p1", "progress.md"), LEDGER("p1"));
  write(path.join(worktree, ".forge", "sdd", "p1", "progress.md"), `${LEDGER("p1")}Task 2: complete (commits cccc..dddd)\n`);
  write(path.join(repo, ".forge", "sdd", "p3", "handoff.md"), Buffer.from([0xff, 0xfe]));
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
  write(path.join(repo, ".forge", "sdd", "p1", "progress.md"), LEDGER("p1"));
  write(path.join(repo, ".forge", "sdd", "p2", "progress.md"), LEDGER("p2"));
  write(path.join(repo, ".forge", "sdd", "p2", "handoff.md"), "# local note\n");
  write(path.join(repo, ".forge", "handoff", "latest.md"), "local latest\n");
  const { workstream } = await client.append({ project: "proj", workstream: "p1", entries: [{ kind: "ledger", body: LEDGER("p1") }] });
  await client.append({ project: "proj", workstream: "p2", entries: [{ kind: "ledger", body: "# SDD ledger — plan: elsewhere\n" }] });
  await client.putDocument({ project: "proj", uri: "superpowers/handoff/p2.md", content: "# darkmem note\n" });
  write(path.join(mirror, "work", "handoff", "latest.md"), "mirror latest\n");
  const { sources } = gatherLocalProgress({ repoRoot: repo });
  const { problems, filed } = await checkProgressTargets({ cfg: { project: "proj", mirror }, client }, sources);
  assert.deepEqual([...filed], [["p1", workstream.id]]);
  assert.equal(problems.length, 3, problems.join("\n"));
  assert.match(problems.join("\n"), /^sdd\/p2\/progress\.md: darkmem already holds a different ledger for workstream p2$/m);
  assert.match(problems.join("\n"), /^superpowers\/handoff\/p2\.md: darkmem already holds a different handoff note$/m);
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
  write(path.join(repo, "docs", "forge", "plans", "p1.md"), "# p1\n");
  write(path.join(repo, "docs", "forge", "plans", "p2.md"), "# p2\n");
  write(path.join(repo, "docs", "forge", "plans", "completed.md"), "- `docs/forge/plans/p1.md`\n- `docs/forge/plans/p2.md`\n- `docs/forge/plans/p4.md`\n");
  git(repo, "add", "docs");
  git(repo, "commit", "-q", "-m", "plans");
  const worktree = path.join(scratch("dms-wt-"), "side");
  git(repo, "worktree", "add", "-q", "-b", "side", worktree);
  const home = makeHome({
    repo,
    config: { darkmem: { url: stub.url, api_key_env: "DARKMEM_API_KEY", repos: { [repo]: { project: "proj", documentStore: "local", progressSource: target } } } },
    stores: { documents: "local", progress: target === "darkmem" ? "local" : "darkmem" },
  });
  const seed = createClient({ url: stub.url, apiKey: STUB_KEY, runKey: "seed" });
  return {
    stub, repo, worktree, ...home, seed,
    state: () => JSON.parse(fs.readFileSync(path.join(home.mirror, ".sync-state.json"), "utf8")),
    stores: () => JSON.parse(fs.readFileSync(path.join(home.home, ".dr-forge", "stores.json"), "utf8"))[repo],
    reconcile: () => run(["reconcile"], { cwd: repo, env: home.env }),
  };
}

const movedAside = dir => (fs.existsSync(path.join(dir, ".forge")) ? fs.readdirSync(path.join(dir, ".forge")).filter(name => /^moved-\d{8}T\d{6}Z$/.test(name)) : []);

test("progress moves into darkmem from every checkout, and a second run does nothing", async t => {
  const s = await setup(t, "darkmem");
  write(path.join(s.repo, ".forge", "sdd", "p1", "progress.md"), LEDGER("p1"));
  write(path.join(s.repo, ".forge", "sdd", "p1", "handoff.md"), "# Handoff p1\n");
  write(path.join(s.repo, ".forge", "sdd", "p1", "brief.md"), "workspace\n");
  write(path.join(s.repo, ".forge", "handoff", "latest.md"), LATEST);
  write(path.join(s.worktree, ".forge", "sdd", "p1", "progress.md"), LEDGER("p1"));
  write(path.join(s.worktree, ".forge", "sdd", "p2", "progress.md"), LEDGER("p2"));
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
  assert.equal(s.stub.db.documents.get("proj\u0000superpowers/handoff/p1.md").content, "# Handoff p1\n");
  assert.equal(read(path.join(s.workRoot, "sdd", "p1", "handoff.md")), "# Handoff p1\n");
  assert.equal(s.state().documents["superpowers/handoff/p1.md"], sha("# Handoff p1\n"));
  assert.equal(read(path.join(s.workRoot, "handoff", "latest.md")), LATEST);
  const p1 = s.stub.db.workstreams.find(w => w.key === "p1");
  const [checkpoint, ...more] = p1.entries.filter(e => e.kind === "checkpoint");
  assert.equal(checkpoint.body, LATEST, "latest.md is filed as a checkpoint of the plan it names");
  assert.deepEqual(more, []);
  assert.equal(p1.state, "closed", "a closed workstream is closed again after its checkpoint");
  assert.equal(s.state().checkpoint, sha(LATEST));
  assert.equal(s.state().checkpointAt, checkpoint.created_at);
  assert.match(result.stdout, /^ {2}latest\.md filed as a checkpoint of p1$/m);
  assert.deepEqual(s.stores(), { documents: "local", progress: "darkmem" });
  const [primaryAside] = movedAside(s.repo);
  assert.equal(read(path.join(s.repo, ".forge", primaryAside, "sdd", "p1", "progress.md")), LEDGER("p1"));
  assert.equal(read(path.join(s.repo, ".forge", primaryAside, "sdd", "p1", "handoff.md")), "# Handoff p1\n");
  assert.equal(read(path.join(s.repo, ".forge", primaryAside, "handoff", "latest.md")), LATEST);
  assert.equal(fs.existsSync(path.join(s.repo, ".forge", "sdd", "p1", "progress.md")), false);
  assert.equal(read(path.join(s.repo, ".forge", "sdd", "p1", "brief.md")), "workspace\n", "workspaces stay");
  const [sideAside] = movedAside(s.worktree);
  assert.equal(read(path.join(s.worktree, ".forge", sideAside, "sdd", "p2", "progress.md")), LEDGER("p2"));
  assert.equal(fs.existsSync(path.join(s.worktree, ".forge", "sdd", "p1", "progress.md")), false);
  const again = await s.reconcile();
  assert.equal(again.code, 0, again.stdout + again.stderr);
  assert.equal(again.stdout, "");
});

test("a ledger darkmem already holds unchanged is not filed again, so a stopped move can run again", async t => {
  const s = await setup(t, "darkmem");
  write(path.join(s.repo, ".forge", "sdd", "p1", "progress.md"), LEDGER("p1"));
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
  const { workstream } = await s.seed.append({ project: "proj", workstream: "p9", entries: [{ kind: "checkpoint", body: "## State\n- Plan: `docs/forge/plans/p9.md`\n" }] });
  write(path.join(s.repo, ".forge", "handoff", "latest.md"), "a note with no State section\n");
  const result = await s.reconcile();
  assert.equal(result.code, 0, result.stdout + result.stderr);
  assert.match(result.stdout, /^darkmem-sync reconcile: progress moved to darkmem$/m);
  assert.match(result.stdout, /^ {2}latest\.md names no plan or draft; copied to the mirror, not sent$/m);
  assert.equal(read(path.join(s.workRoot, "handoff", "latest.md")), "a note with no State section\n");
  assert.equal(s.state().checkpoint, sha("a note with no State section\n"));
  assert.equal(s.state().checkpointAt, workstream.last_entry_at);
  assert.equal(s.stub.db.workstreams.flatMap(w => w.entries).filter(e => e.kind === "checkpoint").length, 1);
});

test("a ledger's workstream properties read its plan in its own checkout", async t => {
  const s = await setup(t, "darkmem");
  write(path.join(s.worktree, "docs", "forge", "plans", "p4.md"), "# p4\n\n**Spec:** `docs/forge/specs/s4.md`\n");
  write(path.join(s.worktree, ".forge", "sdd", "p4", "progress.md"), LEDGER("p4"));
  const result = await s.reconcile();
  assert.equal(result.code, 0, result.stdout + result.stderr);
  const { plan_uri, spec_uri } = s.stub.db.workstreams.find(w => w.key === "p4").properties;
  assert.deepEqual({ plan_uri, spec_uri }, { plan_uri: "superpowers/plans/p4.md", spec_uri: "superpowers/specs/s4.md" });
});

test("documents and progress both move to darkmem in one run, and the ledger's properties read the plan from the mirror", async t => {
  const s = await setup(t, "darkmem");
  write(path.join(s.repo, "docs", "forge", "plans", "p1.md"), "# p1\n\n**Spec:** `docs/forge/specs/s1.md`\n");
  write(path.join(s.repo, "docs", "forge", "specs", "s1.md"), "# s1\n");
  git(s.repo, "add", "docs");
  git(s.repo, "commit", "-q", "-m", "spec");
  write(path.join(s.home, ".dr-forge", "config.json"), JSON.stringify({ darkmem: { url: s.stub.url, api_key_env: "DARKMEM_API_KEY", repos: { [s.repo]: { project: "proj" } } } }));
  write(path.join(s.repo, ".forge", "sdd", "p1", "progress.md"), LEDGER("p1"));
  const result = await s.reconcile();
  assert.equal(result.code, 0, result.stdout + result.stderr);
  assert.match(result.stdout, /^darkmem-sync reconcile: documents moved to darkmem$/m);
  assert.match(result.stdout, /^darkmem-sync reconcile: progress moved to darkmem$/m);
  assert.equal(fs.existsSync(path.join(s.repo, "docs", "forge", "plans", "p1.md")), false, "the documents move ran first and removed the checkout's copy");
  const { plan_uri, spec_uri } = s.stub.db.workstreams.find(w => w.key === "p1").properties;
  assert.deepEqual({ plan_uri, spec_uri }, { plan_uri: "superpowers/plans/p1.md", spec_uri: "superpowers/specs/s1.md" });
  assert.deepEqual(s.stores(), { documents: "darkmem", progress: "darkmem" });
});

const UP_REFUSALS = [
  {
    name: "copies of one ledger that differ between checkouts",
    plant: async s => {
      write(path.join(s.repo, ".forge", "sdd", "p1", "progress.md"), LEDGER("p1"));
      write(path.join(s.worktree, ".forge", "sdd", "p1", "progress.md"), `${LEDGER("p1")}Task 2: complete (commits cccc..dddd)\n`);
    },
    detail: /^ {2}sdd\/p1\/progress\.md: .+ and .+ differ$/m,
  },
  {
    name: "a plan directory that is not a workstream key",
    plant: async s => write(path.join(s.repo, ".forge", "sdd", "bad name", "handoff.md"), "# note\n"),
    detail: /^ {2}.+bad name: not a usable workstream key$/m,
  },
  {
    name: "a different ledger on darkmem",
    plant: async s => {
      write(path.join(s.repo, ".forge", "sdd", "p1", "progress.md"), LEDGER("p1"));
      await s.seed.append({ project: "proj", workstream: "p1", entries: [{ kind: "ledger", body: "# SDD ledger — plan: elsewhere\n" }] });
    },
    detail: /^ {2}sdd\/p1\/progress\.md: darkmem already holds a different ledger for workstream p1$/m,
  },
  {
    name: "a different copy in the mirror",
    plant: async s => {
      write(path.join(s.repo, ".forge", "sdd", "p1", "progress.md"), LEDGER("p1"));
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
  fs.mkdirSync(path.join(repo, ".forge", "sdd", "p1", "progress.md"), { recursive: true });
  write(path.join(repo, ".forge", "sdd", "p2", "progress.md"), LEDGER("p2"));
  fs.mkdirSync(path.join(mirror, "work", "sdd", "p2", "progress.md"), { recursive: true });
  const { problems, sources } = gatherLocalProgress({ repoRoot: repo });
  assert.deepEqual(problems.map(line => line.replace(repo, "<repo>").split(path.sep).join("/")), ["<repo>/.forge/sdd/p1/progress.md: could not be read (EISDIR)"]);
  const checked = await checkProgressTargets({ cfg: { project: "proj", mirror }, client }, sources);
  assert.deepEqual(checked.problems.map(line => line.replace(mirror, "<mirror>").split(path.sep).join("/")), ["<mirror>/work/sdd/p2/progress.md: could not be read (EISDIR)"]);
});

test("progress reached through a symbolic link stays local, and nothing is sent or moved", { skip: process.platform === "win32" }, async t => {
  const s = await setup(t, "darkmem");
  write(path.join(s.repo, ".forge", "sdd", "p1", "progress.md"), LEDGER("p1"));
  fs.symlinkSync(path.join(s.repo, ".forge"), path.join(s.worktree, ".forge"));
  const before = s.stub.db.requests.length;
  const result = await s.reconcile();
  assert.equal(result.code, 1, result.stdout + result.stderr);
  assert.ok(result.stdout.includes("darkmem-sync reconcile: progress stay local (configured darkmem): the checkouts' progress is reached through symbolic links; nothing was sent or moved\n"), result.stdout);
  assert.ok(result.stdout.includes(`  ${path.join(s.worktree, ".forge")}: a symbolic link, which the move will not move files through\n`), result.stdout);
  assert.deepEqual(s.stub.db.requests.slice(before).filter(r => r.method !== "GET").map(r => `${r.method} ${r.path}`), []);
  assert.equal(s.stores().progress, "local");
  assert.deepEqual(movedAside(s.repo), []);
  assert.equal(read(path.join(s.repo, ".forge", "sdd", "p1", "progress.md")), LEDGER("p1"));
});
