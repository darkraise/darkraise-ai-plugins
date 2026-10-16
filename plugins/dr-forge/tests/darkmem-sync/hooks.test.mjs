import assert from "node:assert/strict";
import { execFile, spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";
import { createClient } from "../../scripts/lib/darkmem-client.mjs";
import { STUB_KEY, startStub } from "./stub-server.mjs";
import { makeHome, makeRepo, scratch, write } from "./helpers.mjs";

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

const sessionLines = (dir, sid, env, room = "", seconds = "") => bash(["-c", '. "$1"; darkmem_session_lines "$2" "$3" "$4" "$5"', "hook-test", LIB, dir, sid, room, seconds], { cwd: dir, env });
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
  await s.seed.putDocument({ project: "proj", uri: "forge/specs/a.md", content: "# A\n" });
  await s.seed.putDocument({ project: "proj", uri: "forge/.x.md", content: "hidden\n" });
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
    await s.seed.putDocument({ project: "proj", uri: `forge/n${String(i).padStart(2, "0")}.`, content: "x\n" });
  }
  const result = await sessionLines(s.repo, "sid-hook", s.env);
  assert.equal(result.code, 0, result.stderr);
  const lines = result.stdout.split("\n").filter(Boolean);
  assert.equal(lines.filter(line => line.startsWith("failed: forge/n")).length, 25);
  assert.match(lines.at(-1), /^darkmem-sync pull: 0 documents, 0 ledgers, 0 checkpoints; 0 conflicts, 25 failures$/);
  assert.doesNotMatch(result.stdout, MORE);
  const tight = await sessionLines(s.repo, "sid-hook", s.env, "400");
  assert.ok(tight.stdout.length <= 400, `${tight.stdout.length} characters`);
  assert.match(tight.stdout, /^failed: forge\/n00\.: /m);
  assert.match(tight.stdout.trimEnd().split("\n").at(-1), MORE);
});

test("session lines print nothing for an unmapped repository or one with nothing to pull", async t => {
  const s = await setup(t);
  const other = makeHome({ repo: makeRepo(), url: s.stub.url });
  assert.deepEqual(await sessionLines(s.repo, "sid-hook", hookEnv(other)), { code: 0, stdout: "", stderr: "" });
  const none = makeHome({ repo: s.repo, url: s.stub.url, config: null, stores: null });
  assert.deepEqual(await sessionLines(s.repo, "sid-hook", hookEnv(none)), { code: 0, stdout: "", stderr: "" });
  const local = makeHome({
    repo: s.repo, url: s.stub.url, stores: { documents: "local", progress: "local" },
    config: { darkmemEnabled: true, darkmem: { url: s.stub.url, api_key_env: "DARKMEM_API_KEY", repos: { [s.repo]: { project: "proj", documentStore: "local", progressSource: "local" } } } },
  });
  assert.deepEqual(await sessionLines(s.repo, "sid-hook", hookEnv(local)), { code: 0, stdout: "", stderr: "" });
  assert.equal(s.stub.db.requests.length, 0);
});

test("darkmem turned off still reconciles a family left in the mirror, and the Stop push sends nothing", async t => {
  const s = await setup(t);
  const off = makeHome({ repo: s.repo, url: s.stub.url, enabled: "off", stores: { documents: "darkmem", progress: "local" } });
  write(path.join(off.docsRoot, "a.md"), "a\n");
  const result = await sessionLines(s.repo, "sid-hook", hookEnv(off));
  assert.equal(result.code, 0, result.stderr);
  assert.match(result.stdout, /^darkmem-sync reconcile: documents moved to local/m);
  assert.doesNotMatch(result.stdout, /pull skipped/);
  assert.equal(fs.readFileSync(path.join(s.repo, "docs", "forge", "a.md"), "utf8"), "a\n");
  const before = s.stub.db.requests.length;
  assert.deepEqual(await pushQuietly(s.repo, "sid-stop", hookEnv(off)), { code: 0, stdout: "", stderr: "" });
  assert.equal(s.stub.db.requests.length, before);
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

const SCRIPTS = fileURLToPath(new URL("../../scripts/", import.meta.url));
const HOOKS_JSON = fileURLToPath(new URL("../../hooks/hooks.json", import.meta.url));
const hasJq = spawnSync("jq", ["--version"]).status === 0;
const runHook = (name, payload, options) => bash([path.join(SCRIPTS, name)], { ...options, input: JSON.stringify(payload) });

test("the hooks are bounded: SessionStart 300 seconds, Stop 120, and the darkmem push runs in the background", () => {
  const hooks = JSON.parse(fs.readFileSync(HOOKS_JSON, "utf8")).hooks;
  assert.equal(hooks.SessionStart[0].hooks[0].timeout, 300);
  const [turnEnd, stopPush, ...more] = hooks.Stop[0].hooks;
  assert.match(turnEnd.command, /scripts\/turn-end\.sh/);
  assert.equal(turnEnd.async, false);
  assert.equal(turnEnd.timeout, 120);
  assert.match(stopPush.command, /scripts\/darkmem-stop-push\.sh/);
  assert.equal(stopPush.async, true);
  assert.equal(stopPush.timeout, undefined, "Claude Code does not enforce an async hook's timeout; the push bounds itself");
  assert.deepEqual(more, []);
});

test("session start adds the darkmem lines on every source, compaction included", { skip: !hasJq && "jq is not on PATH" }, async t => {
  const s = await setup(t);
  const payload = source => ({ hook_event_name: "SessionStart", session_id: "sid-start", transcript_path: "", cwd: s.repo, source });
  for (const [source, uri] of [["startup", "forge/specs/a.md"], ["compact", "forge/specs/b.md"]]) {
    await s.seed.putDocument({ project: "proj", uri, content: `# ${uri}\n` });
    const result = await runHook("session-start.sh", payload(source), { cwd: s.repo, env: s.env });
    assert.equal(result.code, 0, result.stderr);
    const context = JSON.parse(result.stdout).hookSpecificOutput.additionalContext;
    assert.match(context, /darkmem-sync pull: 1 documents, 0 ledgers, 0 checkpoints; 0 conflicts, 0 failures/, source);
    assert.match(context, /dr-forge:using-forge/, source);
  }
});

test("the Stop push sends under its session id, a retried stop too, and prints nothing; turn-end.sh sends nothing", { skip: !hasJq && "jq is not on PATH" }, async t => {
  const s = await setup(t);
  const ledger = path.join(s.home.workRoot, "sdd", "p1", "progress.md");
  write(ledger, "# SDD ledger — plan: docs/forge/plans/p1.md\nTask 1: a\n");
  const payload = active => ({ hook_event_name: "Stop", session_id: "sid-stop", cwd: s.repo, transcript_path: "", stop_hook_active: active });
  const appends = () => s.stub.db.requests.filter(r => r.method === "POST" && r.path === "/api/v1/worklog/entries");
  const requests = s.stub.db.requests.length;
  assert.deepEqual(await runHook("turn-end.sh", payload(false), { cwd: s.repo, env: s.env }), { code: 0, stdout: "", stderr: "" });
  assert.equal(s.stub.db.requests.length, requests, "turn-end.sh makes no darkmem request");
  assert.deepEqual(await runHook("darkmem-stop-push.sh", payload(false), { cwd: s.repo, env: s.env }), { code: 0, stdout: "", stderr: "" });
  assert.equal(appends().length, 1, "the Stop push sent the ledger");
  fs.appendFileSync(ledger, "Task 1: complete (commits abc1234..def5678, review clean)\n");
  assert.deepEqual(await runHook("darkmem-stop-push.sh", payload(true), { cwd: s.repo, env: s.env }), { code: 0, stdout: "", stderr: "" });
  assert.equal(appends().length, 2, "a retried stop pushes the lines written since");
  assert.ok(appends().every(r => r.body.run_key === "sid-stop"));
});

test("the watchdog bounds a command and its children where GNU timeout is missing", async () => {
  const dir = scratch("dmh-wd-");
  const pidFile = path.join(dir, "child.pid");
  const quick = await bash(["-c", '. "$1"; _darkmem_watchdog 5 bash -c "echo out; echo err >&2; exit 3"', "hook-test", LIB], { cwd: dir, env: process.env });
  assert.deepEqual(quick, { code: 3, stdout: "out\n", stderr: "err\n" });
  const started = Date.now();
  const slow = await bash(["-c", '. "$1"; _darkmem_watchdog 1 bash -c "sleep 30 & echo \\$! > \\"\\$0\\"; wait" "$2"', "hook-test", LIB, pidFile], { cwd: dir, env: process.env });
  assert.ok(Date.now() - started < 10000, "the command was stopped at its bound");
  assert.notEqual(slow.code, 0);
  assert.equal(slow.stderr, "", "no job-control notice reaches stderr");
  await new Promise(resolve => setTimeout(resolve, 300));
  assert.throws(() => process.kill(Number(fs.readFileSync(pidFile, "utf8")), 0), { code: "ESRCH" }, "the command's child was killed too");
});

test("_darkmem_bounded falls back to the watchdog where GNU timeout is missing", { skip: process.platform === "win32" && "file symbolic links need privileges on Windows" }, async () => {
  const dir = scratch("dmh-bin-");
  const bin = path.join(dir, "bin");
  fs.mkdirSync(bin);
  for (const tool of ["bash", "sleep"]) {
    fs.symlinkSync(spawnSync("bash", ["-c", `command -v ${tool}`], { encoding: "utf8" }).stdout.trim(), path.join(bin, tool));
  }
  const pidFile = path.join(dir, "child.pid");
  const started = Date.now();
  const result = await bash(["-c", '. "$1"; PATH="$3"; command -v timeout && exit 9; _darkmem_bounded 1 bash -c "sleep 30 & echo \\$! > \\"\\$0\\"; wait" "$2"', "hook-test", LIB, pidFile, bin], { cwd: dir, env: process.env });
  assert.notEqual(result.code, 9, "timeout must not be on the trimmed PATH");
  assert.ok(Date.now() - started < 10000, "the watchdog stopped the command at its bound");
  assert.notEqual(result.code, 0);
  await new Promise(resolve => setTimeout(resolve, 300));
  assert.throws(() => process.kill(Number(fs.readFileSync(pidFile, "utf8")), 0), { code: "ESRCH" }, "the command's child was killed too");
});

// Ignores SIGTERM, as does its child: only SIGKILL stops it before it ends by itself.
const STUBBORN = `'trap "" TERM; sleep 20 & echo $! > "$0"; wait'`;

test("the watchdog escalates to SIGKILL when SIGTERM does not stop the command", async () => {
  const dir = scratch("dmh-kill-");
  const pidFile = path.join(dir, "child.pid");
  const started = Date.now();
  const result = await bash(["-c", `. "$1"; _darkmem_watchdog 1 bash -c ${STUBBORN} "$2"`, "hook-test", LIB, pidFile], { cwd: dir, env: { ...process.env, DARKMEM_KILL_GRACE: "1" } });
  assert.ok(Date.now() - started < 10000, "the command was killed after the grace period");
  assert.notEqual(result.code, 0);
  await new Promise(resolve => setTimeout(resolve, 300));
  assert.throws(() => process.kill(Number(fs.readFileSync(pidFile, "utf8")), 0), { code: "ESRCH" }, "the command's child was killed too");
});

test("GNU timeout escalates to SIGKILL when SIGTERM does not stop the command", { skip: spawnSync("timeout", ["--version"]).status !== 0 && "GNU timeout is not on PATH" }, async () => {
  const dir = scratch("dmh-tkill-");
  const pidFile = path.join(dir, "child.pid");
  const started = Date.now();
  const result = await bash(["-c", `. "$1"; _darkmem_bounded 1 bash -c ${STUBBORN} "$2"`, "hook-test", LIB, pidFile], { cwd: dir, env: { ...process.env, DARKMEM_KILL_GRACE: "1" } });
  assert.ok(Date.now() - started < 10000, "the command was killed after the grace period");
  assert.notEqual(result.code, 0);
  await new Promise(resolve => setTimeout(resolve, 300));
  assert.throws(() => process.kill(Number(fs.readFileSync(pidFile, "utf8")), 0), { code: "ESRCH" }, "the command's child was killed too");
});

test("the watchdog leaves the caller's job-control setting as it found it", async () => {
  const dir = scratch("dmh-jc-");
  const probe = setting => bash(["-c", `. "$1"; ${setting}; _darkmem_watchdog 5 true; case $- in *m*) echo on ;; *) echo off ;; esac`, "hook-test", LIB], { cwd: dir, env: process.env });
  assert.equal((await probe("set -m")).stdout, "on\n");
  assert.equal((await probe("set +m")).stdout, "off\n");
});

test("the Stop push refuses at once while another darkmem-sync holds the mirror lock", async t => {
  const s = await setup(t);
  write(path.join(s.home.workRoot, "sdd", "p1", "progress.md"), "# SDD ledger — plan: docs/forge/plans/p1.md\nTask 1: a\n");
  const lock = path.join(s.home.mirror, ".sync.lock");
  fs.mkdirSync(lock, { recursive: true });
  const released = setTimeout(() => fs.rmdirSync(lock), 3000);
  t.after(() => clearTimeout(released));
  const started = Date.now();
  const result = await pushQuietly(s.repo, "sid-hook", s.env);
  assert.deepEqual(result, { code: 0, stdout: "", stderr: "" });
  assert.ok(Date.now() - started < 2500, "the Stop push did not wait for the lock");
  assert.equal(s.stub.db.requests.some(r => r.method === "POST" && r.path === "/api/v1/worklog/entries"), false, "nothing was sent");
});

test("session start waits for a Stop push's mirror lock before it pulls", async t => {
  const s = await setup(t);
  await s.seed.putDocument({ project: "proj", uri: "forge/specs/a.md", content: "# A\n" });
  const lock = path.join(s.home.mirror, ".sync.lock");
  fs.mkdirSync(lock, { recursive: true });
  const released = setTimeout(() => fs.rmdirSync(lock), 2000);
  t.after(() => clearTimeout(released));
  const result = await sessionLines(s.repo, "sid-hook", s.env);
  assert.equal(result.code, 0, result.stderr);
  assert.doesNotMatch(result.stdout, /holds/);
  assert.match(result.stdout, /^darkmem-sync pull: 1 documents, 0 ledgers, 0 checkpoints; 0 conflicts, 0 failures$/m);
});

test("session lines skip the sync, and say so, when too little of the hook's time is left", async t => {
  const s = await setup(t);
  const started = Date.now();
  const result = await sessionLines(s.repo, "sid-hook", s.env, "", "20");
  assert.equal(result.code, 0, result.stderr);
  assert.equal(result.stdout, "darkmem-sync: reconcile and pull skipped at session start: too little of the hook's time is left; run darkmem-sync reconcile, then pull\n");
  assert.ok(Date.now() - started < 10000);
  assert.equal(s.stub.db.requests.length, 0);
});
