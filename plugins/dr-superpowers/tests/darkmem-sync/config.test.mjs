import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { ConfigError, resolveMode, runKey } from "../../scripts/lib/darkmem-config.mjs";
import { git, makeHome, makeRepo, scratch } from "./helpers.mjs";

test("no config file is local mode on the repository's own paths", () => {
  const repo = makeRepo();
  const { env } = makeHome({ repo, config: null });
  const mode = resolveMode({ cwd: repo, env });
  assert.equal(mode.mode, "local");
  assert.match(mode.reason, /^no .*config\.json$/);
  assert.equal(mode.docsRoot, path.join(repo, "docs", "superpowers"));
  assert.equal(mode.workRoot, path.join(repo, ".superpowers"));
});

test("a mapped repository with its key set is darkmem mode on the mirror", () => {
  const repo = makeRepo();
  const { home, env } = makeHome({ repo, url: "http://darkmem.test:8000/", project: "proj" });
  const mode = resolveMode({ cwd: repo, env });
  const mirror = path.join(home, ".dr-superpowers", "mirror", "proj");
  assert.equal(mode.mode, "darkmem");
  assert.equal(mode.project, "proj");
  assert.equal(mode.url, "http://darkmem.test:8000");
  assert.equal(mode.apiKey, "dmk_test_secret");
  assert.equal(mode.mirror, mirror);
  assert.equal(mode.docsRoot, path.join(mirror, "superpowers"));
  assert.equal(mode.workRoot, path.join(mirror, "work"));
  assert.equal(mode.statePath, path.join(mirror, ".sync-state.json"));
});

test("a linked worktree resolves through its primary checkout's mapping", () => {
  const repo = makeRepo();
  const { env } = makeHome({ repo });
  const worktree = path.join(scratch("dms-wt-"), "wt");
  git(repo, "worktree", "add", "-q", "-b", "wt", worktree);
  assert.equal(resolveMode({ cwd: worktree, env }).mode, "darkmem");
});

test("a missing key, an unmapped repository and no git repository are local mode", () => {
  const repo = makeRepo();
  const { env } = makeHome({ repo });
  delete env.DARKMEM_API_KEY;
  assert.deepEqual([resolveMode({ cwd: repo, env }).mode, resolveMode({ cwd: repo, env }).reason], ["local", "DARKMEM_API_KEY is not set"]);
  const other = makeRepo();
  assert.match(resolveMode({ cwd: other, env: makeHome({ repo }).env }).reason, /^no darkmem mapping for /);
  const plain = scratch("dms-plain-");
  assert.equal(resolveMode({ cwd: plain, env }).reason, "not inside a git repository");
});

test("a malformed config file, a climbing project or a bad url is a ConfigError", () => {
  const repo = makeRepo();
  assert.throws(() => resolveMode({ cwd: repo, env: makeHome({ repo, config: "{not json" }).env }), ConfigError);
  assert.throws(() => resolveMode({ cwd: repo, env: makeHome({ repo, project: "../up" }).env }), /needs a project/);
  assert.throws(() => resolveMode({ cwd: repo, env: makeHome({ repo, url: "darkmem.test" }).env }), /darkmem\.url/);
});

test("the run key prefers the declared id, then the session record, then a day key", () => {
  const repo = makeRepo();
  const { home, env } = makeHome({ repo });
  assert.equal(runKey({ cwd: repo, env }), "sess-1");
  delete env.DR_SUPERPOWERS_SESSION_ID;
  const now = new Date("2026-09-24T10:00:00Z");
  assert.equal(runKey({ cwd: repo, env, now }), `codex:${os.hostname()}:2026-09-24`);
  const sessions = path.join(home, ".claude", "dr-superpowers", "sessions");
  fs.mkdirSync(sessions, { recursive: true });
  fs.writeFileSync(path.join(sessions, `${repo.replace(/[^A-Za-z0-9]/g, "-")}.json`), JSON.stringify({ session_id: "abc-123" }));
  assert.equal(runKey({ cwd: repo, env, now }), "abc-123");
});
