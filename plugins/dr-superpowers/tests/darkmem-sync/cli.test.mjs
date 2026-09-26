import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import test from "node:test";
import { makeHome, makeRepo, run, write } from "./helpers.mjs";

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
  const { env } = makeHome({ repo, config: null });
  const result = await run(["status"], { cwd: repo, env });
  assert.equal(result.code, 0);
  assert.match(result.stdout, /^darkmem-sync: local mode — no .*config\.json\n$/);
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
    `darkmem-sync: darkmem mode — project proj at http://127.0.0.1:9; mirror ${mirror}`,
    "new: superpowers/specs/a.md",
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
  assert.equal(failed.code, 4);
  assert.match(failed.stderr, /unexpected error/);
  assert.equal(fs.existsSync(path.join(mirror, ".sync.lock")), false);
  fs.rmdirSync(path.join(mirror, "..sync-state.json.tmp"));
  assert.equal((await run(["status"], { cwd: repo, env })).code, 0);
});
