import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";
import { createClient } from "../../scripts/lib/darkmem-client.mjs";
import { STUB_KEY, startStub } from "./stub-server.mjs";
import { makeHome, makeRepo, write } from "./helpers.mjs";

const LIB = fileURLToPath(new URL("../../scripts/lib/darkmem-hook.sh", import.meta.url));

// Runs bash asynchronously: the stub in this process must keep answering.
function bash(args, { cwd, env, input }) {
  return new Promise(resolve => {
    const child = execFile(process.env.DR_TEST_BASH ?? "bash", args, { cwd, env, timeout: 120000 }, (error, stdout, stderr) => {
      resolve({ code: error ? (typeof error.code === "number" ? error.code : -1) : 0, stdout, stderr });
    });
    child.stdin.end(input ?? "");
  });
}

const sessionLines = (dir, sid, env, room = "") => bash(["-c", '. "$1"; darkmem_session_lines "$2" "$3" "$4"', "hook-test", LIB, dir, sid, room], { cwd: dir, env });
const MORE = /^darkmem-sync: (\d+) more lines; run darkmem-sync reconcile or status to see them$/m;
const pushQuietly = (dir, sid, env) => bash(["-c", '. "$1"; darkmem_push_quietly "$2" "$3"', "hook-test", LIB, dir, sid], { cwd: dir, env });

// The hooks must export the session id themselves, so the test environment
// carries none.
function hookEnv(home) {
  const env = { ...home.env };
  delete env.DR_FORGE_SESSION_ID;
  delete env.DR_SUPERPOWERS_SESSION_ID;
  delete env.CLAUDE_CONFIG_DIR;
  return env;
}

async function setup(t, homeOptions = {}) {
  const stub = await startStub();
  t.after(() => stub.close());
  const repo = makeRepo();
  const home = makeHome({ repo, url: stub.url, ...homeOptions });
  const seed = createClient({ url: stub.url, apiKey: STUB_KEY, runKey: "seed" });
  return { stub, repo, home, seed, env: hookEnv(home) };
}

test("session lines show reconcile's refusal and pull's result, without notes", async t => {
  const s = await setup(t, { stores: { documents: "darkmem", progress: "local" } });
  write(path.join(s.repo, ".forge", "sdd", "p1", "progress.md"), "# SDD ledger — plan: docs/forge/plans/p1.md\nTask 1: implementer x (assigned; base abc1234)\n");
  await s.seed.putDocument({ project: "proj", uri: "superpowers/specs/a.md", content: "# A\n" });
  await s.seed.putDocument({ project: "proj", uri: "superpowers/.x.md", content: "hidden\n" });
  const result = await sessionLines(s.repo, "sid-hook", s.env);
  assert.equal(result.code, 0, result.stderr);
  assert.match(result.stdout, /^darkmem-sync reconcile: progress stay local \(configured darkmem\): a plan is in progress/m);
  assert.match(result.stdout, /^darkmem-sync pull: 1 documents, 0 ledgers, 0 checkpoints; 0 conflicts, 0 failures$/m);
  assert.doesNotMatch(result.stdout, /^note:/m);
});

test("the line cap trims only detail lines, keeping both families' lines", async t => {
  const s = await setup(t, { stores: { documents: "local", progress: "local" } });
  for (let i = 0; i < 25; i += 1) {
    const slug = `p${String(i).padStart(2, "0")}`;
    write(path.join(s.repo, ".forge", "sdd", slug, "progress.md"), `# SDD ledger — plan: docs/forge/plans/${slug}.md\nTask 1: a\n`);
  }
  const result = await sessionLines(s.repo, "sid-hook", s.env);
  assert.equal(result.code, 0, result.stderr);
  const lines = result.stdout.split("\n").filter(Boolean);
  assert.equal(lines.length, 20);
  assert.match(result.stdout, /^darkmem-sync reconcile: documents stay local \(configured darkmem\): a plan is in progress/m);
  assert.match(result.stdout, /^darkmem-sync reconcile: progress stay local \(configured darkmem\): a plan is in progress/m);
  assert.match(lines.at(-1), MORE);
  assert.equal(lines.filter(line => /^[ \t]/.test(line)).length, 17);
});

test("unindented lines outlast the line cap; the character room trims them last", async t => {
  const s = await setup(t);
  for (let i = 0; i < 25; i += 1) {
    await s.seed.putDocument({ project: "proj", uri: `superpowers/n${String(i).padStart(2, "0")}.`, content: "x\n" });
  }
  const result = await sessionLines(s.repo, "sid-hook", s.env);
  assert.equal(result.code, 0, result.stderr);
  const lines = result.stdout.split("\n").filter(Boolean);
  assert.equal(lines.filter(line => line.startsWith("failed: superpowers/n")).length, 25);
  assert.match(lines.at(-1), /^darkmem-sync pull: 0 documents, 0 ledgers, 0 checkpoints; 0 conflicts, 25 failures$/);
  assert.doesNotMatch(result.stdout, MORE);
  const tight = await sessionLines(s.repo, "sid-hook", s.env, "400");
  assert.ok(tight.stdout.length <= 400, `${tight.stdout.length} characters`);
  assert.match(tight.stdout, /^failed: superpowers\/n00\.: /m);
  assert.match(tight.stdout.trimEnd().split("\n").at(-1), MORE);
});

test("session lines print nothing for an unmapped repository or one with nothing to pull", async t => {
  const s = await setup(t);
  const other = makeHome({ repo: makeRepo(), url: s.stub.url });
  assert.deepEqual(await sessionLines(s.repo, "sid-hook", hookEnv(other)), { code: 0, stdout: "", stderr: "" });
  const none = makeHome({ repo: s.repo, url: s.stub.url, config: null });
  assert.deepEqual(await sessionLines(s.repo, "sid-hook", hookEnv(none)), { code: 0, stdout: "", stderr: "" });
  const local = makeHome({
    repo: s.repo, url: s.stub.url, stores: { documents: "local", progress: "local" },
    config: { darkmem: { url: s.stub.url, api_key_env: "DARKMEM_API_KEY", repos: { [s.repo]: { project: "proj", documentStore: "local", progressSource: "local" } } } },
  });
  assert.deepEqual(await sessionLines(s.repo, "sid-hook", hookEnv(local)), { code: 0, stdout: "", stderr: "" });
  assert.equal(s.stub.db.requests.length, 0);
});

test("a pull that changes nothing prints no line", async t => {
  const s = await setup(t);
  const result = await sessionLines(s.repo, "sid-hook", s.env);
  assert.deepEqual(result, { code: 0, stdout: "", stderr: "" });
  assert.ok(s.stub.db.requests.some(r => r.path === "/api/v1/documents/manifest"), "the pull ran");
});

test("the quiet push prints nothing and declares the session it was given", async t => {
  const s = await setup(t);
  write(path.join(s.home.workRoot, "sdd", "p1", "progress.md"), "# SDD ledger — plan: docs/forge/plans/p1.md\nTask 1: a\n");
  const result = await pushQuietly(s.repo, "sid-hook", s.env);
  assert.deepEqual(result, { code: 0, stdout: "", stderr: "" });
  const append = s.stub.db.requests.find(r => r.method === "POST" && r.path === "/api/v1/worklog/entries");
  assert.ok(append, "push appended the ledger");
  assert.equal(append.body.run_key, "sid-hook");
});
