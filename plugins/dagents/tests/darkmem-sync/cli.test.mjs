import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import test from "node:test";
import { makeHome, makeRepo, run, write } from "./helpers.mjs";
import { startStub } from "./stub-server.mjs";

test("no command, an unknown command or an unknown flag is a usage error", async () => {
  const repo = makeRepo();
  const { env } = makeHome({ repo });
  for (const args of [[], ["sync"], ["status", "--force"]]) {
    const result = await run(args, { cwd: repo, env });
    assert.equal(result.code, 2, args.join(" "));
    assert.match(result.stderr, /^usage: darkmem-sync status/);
  }
});

test("local mode prints one line and succeeds", async () => {
  const repo = makeRepo();
  const { env } = makeHome({ repo, config: null, stores: null });
  const result = await run(["status"], { cwd: repo, env });
  assert.equal(result.code, 0);
  assert.match(result.stdout, /^darkmem-sync: local mode — darkmem is disabled \(darkmemEnabled is false\)\n$/);
});

test("a malformed config is exit 2 naming the file", async () => {
  const repo = makeRepo();
  const { env } = makeHome({ repo, config: "{nope" });
  const result = await run(["status"], { cwd: repo, env });
  assert.equal(result.code, 2);
  assert.match(result.stderr, /config\.json is not valid JSON/);
});

test("status in darkmem mode names the mirror and its local changes", async () => {
  const repo = makeRepo();
  const { env, mirror, docsRoot, workRoot } = makeHome({ repo });
  write(path.join(docsRoot, "specs", "a.md"), "# A\n");
  write(path.join(workRoot, "sdd", "p1", "progress.md"), "# SDD ledger — plan: docs/superpowers/plans/p1.md\n");
  const result = await run(["status"], { cwd: repo, env });
  assert.equal(result.code, 0, result.stderr);
  assert.equal(result.stdout, [
    `darkmem-sync: project proj at http://127.0.0.1:9; mirror ${mirror}`,
    "documents: configured darkmem, applied darkmem",
    "progress: configured darkmem, applied darkmem",
    "new: dforge/specs/a.md",
    "unpushed: sdd/p1/progress.md (52 bytes, never synced)",
    "",
  ].join("\n"));
  assert.equal(fs.existsSync(path.join(mirror, ".sync.lock")), false);
});

test("a held lock is exit 1, and an unreadable state file is exit 2", async () => {
  const repo = makeRepo();
  const { env, mirror } = makeHome({ repo });
  fs.mkdirSync(path.join(mirror, ".sync.lock"), { recursive: true });
  const locked = await run(["status"], { cwd: repo, env });
  assert.equal(locked.code, 1);
  assert.match(locked.stderr, /another darkmem-sync \(an unknown process\) holds .*\.sync\.lock; if that process is gone, remove the directory/);
  fs.rmdirSync(path.join(mirror, ".sync.lock"));
  fs.writeFileSync(path.join(mirror, ".sync-state.json"), "{broken");
  const broken = await run(["status"], { cwd: repo, env });
  assert.equal(broken.code, 2);
  assert.match(broken.stderr, /\.sync-state\.json is unreadable/);
  assert.equal(fs.readFileSync(path.join(mirror, ".sync-state.json"), "utf8"), "{broken");
});

test("the lock is released even when the state file cannot be saved", async () => {
  const repo = makeRepo();
  const { env, mirror } = makeHome({ repo });
  fs.mkdirSync(path.join(mirror, "..sync-state.json.tmp"), { recursive: true });
  const failed = await run(["status"], { cwd: repo, env });
  assert.equal(failed.code, 2, failed.stdout + failed.stderr);
  assert.equal(
    failed.stderr.replace(/ could not be saved \(\w+\);/, " could not be saved (CODE);"),
    `darkmem-sync: ${path.join(mirror, ".sync-state.json")} could not be saved (CODE); the run stopped, and the next run checks what this one wrote\n`,
  );
  assert.equal(fs.existsSync(path.join(mirror, ".sync.lock")), false);
  fs.rmdirSync(path.join(mirror, "..sync-state.json.tmp"));
  assert.equal((await run(["status"], { cwd: repo, env })).code, 0);
});

test("status names a local family as not synced and leaves its files out", async () => {
  const repo = makeRepo();
  const { env, docsRoot, workRoot } = makeHome({ repo, stores: { documents: "darkmem", progress: "local" } });
  write(path.join(docsRoot, "specs", "a.md"), "# A\n");
  write(path.join(workRoot, "sdd", "p1", "progress.md"), "one\n");
  const result = await run(["status"], { cwd: repo, env });
  assert.equal(result.code, 0, result.stderr);
  assert.match(result.stdout, /^documents: configured darkmem, applied darkmem$/m);
  assert.match(result.stdout, /^progress: configured darkmem, applied local, not synced$/m);
  assert.match(result.stdout, /^new: dforge\/specs\/a\.md$/m);
  assert.doesNotMatch(result.stdout, /sdd\/p1/);
});

test("without the key status still runs, and pull and push skip with exit 3", async () => {
  const repo = makeRepo();
  const { env, mirror } = makeHome({ repo });
  delete env.DARKMEM_API_KEY;
  assert.equal((await run(["status"], { cwd: repo, env })).code, 0);
  for (const command of ["pull", "push"]) {
    const result = await run([command], { cwd: repo, env });
    assert.equal(result.code, 3, command);
    assert.equal(result.stderr, `darkmem-sync: ${command} skipped: DARKMEM_API_KEY is not set; working offline from the mirror\n`);
  }
  assert.equal(fs.existsSync(path.join(mirror, ".sync.lock")), false);
});

test("a mapped repository with both families local has nothing to pull or push", async () => {
  const repo = makeRepo();
  const { env } = makeHome({ repo, stores: { documents: "local", progress: "local" } });
  for (const command of ["pull", "push"]) {
    const result = await run([command], { cwd: repo, env });
    assert.equal(result.code, 0, command);
    assert.equal(result.stdout, `darkmem-sync: nothing to ${command}: documents and progress are both applied local\n`);
  }
});

test("push waits for a held lock and then runs; past its wait it refuses as before", async t => {
  const stub = await startStub();
  t.after(() => stub.close());
  const repo = makeRepo();
  const { env, mirror, workRoot } = makeHome({ repo, url: stub.url });
  const ledger = "# SDD ledger — plan: docs/dforge/plans/p1.md\nTask 1: a\n";
  write(path.join(workRoot, "sdd", "p1", "progress.md"), ledger);
  const appended = () => stub.db.workstreams.find(w => w.key === "p1")?.entries.map(e => e.body).join("") ?? null;
  const lock = path.join(mirror, ".sync.lock");
  fs.mkdirSync(lock, { recursive: true });
  const released = setTimeout(() => fs.rmdirSync(lock), 1500);
  t.after(() => clearTimeout(released));
  const started = Date.now();
  const waited = await run(["push"], { cwd: repo, env: { ...env, DARKMEM_SYNC_LOCK_WAIT_MS: "20000" } });
  assert.equal(waited.code, 0, waited.stdout + waited.stderr);
  assert.ok(Date.now() - started >= 1400, "push waited for the lock");
  assert.equal(appended(), ledger, "the push ran once the lock was free");
  assert.equal(fs.existsSync(lock), false, "push released the lock it took");
  fs.appendFileSync(path.join(workRoot, "sdd", "p1", "progress.md"), "Task 1: complete\n");
  fs.mkdirSync(lock, { recursive: true });
  const again = Date.now();
  const refused = await run(["push"], { cwd: repo, env: { ...env, DARKMEM_SYNC_LOCK_WAIT_MS: "1500" } });
  const waitedFor = Date.now() - again;
  assert.equal(refused.code, 1);
  assert.ok(waitedFor >= 1400 && waitedFor < 15000, `refused after its wait, not at once or never (${waitedFor} ms)`);
  assert.match(refused.stderr, /another darkmem-sync \(an unknown process\) holds .*\.sync\.lock; if that process is gone, remove the directory/);
  assert.equal(appended(), ledger, "a refused push sends nothing");
  fs.rmdirSync(lock);
});

test("a negative or infinite lock wait falls back to the default wait", async t => {
  const stub = await startStub();
  t.after(() => stub.close());
  const repo = makeRepo();
  const { env, mirror, workRoot } = makeHome({ repo, url: stub.url });
  const ledger = "# SDD ledger — plan: docs/dforge/plans/p1.md\nTask 1: a\n";
  write(path.join(workRoot, "sdd", "p1", "progress.md"), ledger);
  const lock = path.join(mirror, ".sync.lock");
  fs.mkdirSync(lock, { recursive: true });
  const released = setTimeout(() => fs.rmdirSync(lock), 1500);
  t.after(() => clearTimeout(released));
  const started = Date.now();
  const waited = await run(["push"], { cwd: repo, env: { ...env, DARKMEM_SYNC_LOCK_WAIT_MS: "-5" } });
  assert.equal(waited.code, 0, waited.stdout + waited.stderr);
  assert.ok(Date.now() - started >= 1400, "a negative wait did not refuse at once");
});
