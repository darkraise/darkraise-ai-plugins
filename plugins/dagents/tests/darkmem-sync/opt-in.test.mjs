import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import test from "node:test";
import { sha } from "./stub-server.mjs";
import { makeHome, makeRepo, read, run, write } from "./helpers.mjs";

const STATE = documents => JSON.stringify({ version: 1, documents, ledgers: {}, checkpoint: null, checkpointAt: null, conflicts: [], pendingLinks: [], prefix: "dforge" });

// A repository whose documents and progress a 2.x run put in the mirror;
// `enabled` as makeHome takes it, and an unreachable darkmem url.
function inMirror({ enabled = "off", config } = {}) {
  const repo = makeRepo();
  const home = makeHome({ repo, enabled, config });
  write(path.join(home.docsRoot, "specs", "synced.md"), "synced\n");
  write(path.join(home.docsRoot, "specs", "edited.md"), "edited locally\n");
  write(path.join(home.docsRoot, "specs", "new.md"), "new\n");
  write(path.join(home.workRoot, "sdd", "p1", "progress.md"), "# SDD ledger — plan: docs/dforge/plans/p1.md\n");
  write(path.join(home.workRoot, "handoff", "latest.md"), "# Handoff\n");
  write(path.join(home.mirror, ".sync-state.json"), STATE({
    "dforge/specs/synced.md": sha("synced\n"), "dforge/specs/edited.md": sha("edited\n"), "dforge/specs/deleted.md": sha("gone\n"),
    "dforge/plans/completed.md": sha("- `docs/dforge/plans/p1.md`\n"),
  }));
  write(path.join(home.docsRoot, "plans", "completed.md"), "- `docs/dforge/plans/p1.md`\n");
  return { repo, ...home, sync: (...args) => run(args, { cwd: repo, env: home.env }) };
}

test("darkmem turned off moves both families back from the mirror without asking darkmem", async () => {
  const s = inMirror();
  const result = await s.sync("reconcile");
  assert.equal(result.code, 0, result.stdout + result.stderr);
  assert.match(result.stdout, /^darkmem-sync reconcile: documents moved to local from the mirror, without darkmem \(darkmem is turned off\)$/m);
  assert.match(result.stdout, /^darkmem-sync reconcile: progress moved to local from the mirror, without darkmem/m);
  assert.match(result.stdout, /^ {4}docs\/dforge\/specs\/edited\.md: edited since the last sync; a later move to darkmem refuses it until darkmem's copy matches$/m);
  assert.match(result.stdout, /^ {4}docs\/dforge\/specs\/new\.md: new since the last sync; a later move to darkmem sends it$/m);
  assert.match(result.stdout, /^ {4}dforge\/specs\/deleted\.md: deleted since the last sync; darkmem still holds it, and a later move to darkmem brings it back$/m);
  assert.doesNotMatch(result.stdout, /synced\.md: /);
  assert.equal(read(path.join(s.repo, "docs", "dforge", "specs", "edited.md")), "edited locally\n");
  assert.equal(read(path.join(s.repo, ".dforge", "sdd", "p1", "progress.md")), "# SDD ledger — plan: docs/dforge/plans/p1.md\n");
  assert.equal(read(path.join(s.repo, ".dforge", "handoff", "latest.md")), "# Handoff\n");
  assert.equal(fs.existsSync(s.docsRoot), false);
  assert.equal(fs.readdirSync(s.mirror).filter(name => /^dforge-moved-/.test(name)).length, 1, "the mirror is kept as a backup");
  const record = JSON.parse(read(path.join(s.home, ".dforge", "stores.json")))[s.repo];
  assert.deepEqual([record.documents, record.progress], ["local", "local"]);
  const again = await s.sync("reconcile");
  assert.deepEqual([again.code, again.stdout], [0, "darkmem-sync: local mode — darkmem is disabled (darkmemEnabled is false)\n"]);
});

test("an unmapped repository moves back from the mirror its record names", async () => {
  const s = inMirror({ enabled: true, config: { darkmemEnabled: true } });
  const result = await s.sync("reconcile");
  assert.equal(result.code, 0, result.stdout + result.stderr);
  assert.match(result.stdout, /^darkmem-sync reconcile: documents moved to local from the mirror, without darkmem \(the repository is not mapped to darkmem\)$/m);
  assert.equal(read(path.join(s.repo, "docs", "dforge", "specs", "synced.md")), "synced\n");
});

test("darkmemEnabled unset keeps a 2.x mirror where it is and says how to choose", async () => {
  const s = inMirror({ enabled: false });
  const result = await s.sync("reconcile");
  assert.equal(result.code, 0, result.stdout + result.stderr);
  assert.equal(result.stdout, "darkmem-sync reconcile: darkmem is off by default since dforge 3.0 and darkmemEnabled is unset; documents and progress stay in the mirror, unsynced: set darkmemEnabled to true to sync them, or to false to move them back\n");
  assert.equal(read(path.join(s.docsRoot, "specs", "synced.md")), "synced\n");
  assert.equal(fs.existsSync(path.join(s.repo, "docs", "dforge", "specs")), false);
});

test("while darkmem is off, push and pull skip, status names the mirror, and revision refuses", async () => {
  const s = inMirror();
  for (const command of ["push", "pull"]) {
    const result = await s.sync(command);
    assert.deepEqual([result.code, result.stdout], [0, `darkmem-sync: ${command} skipped: darkmem is disabled (darkmemEnabled is false); the mirror is not synced, and reconcile moves it back\n`]);
  }
  const status = await s.sync("status");
  assert.equal(status.code, 0, status.stderr);
  assert.match(status.stdout, /^darkmem-sync: project proj not synced \(darkmem is disabled \(darkmemEnabled is false\)\); mirror /);
  const revision = await s.sync("revision", "docs/dforge/specs/synced.md");
  assert.equal(revision.code, 1);
  assert.match(revision.stdout, /^refused: docs\/dforge\/specs\/synced\.md is not synced and unchanged: darkmem is disabled/);
});

test("turned on with darkmem unreachable, nothing pending stays in the mirror; a store set local moves back offline", async () => {
  const s = inMirror({ enabled: true });
  const result = await s.sync("reconcile");
  assert.deepEqual([result.code, result.stdout], [0, ""]);
  assert.equal(read(path.join(s.docsRoot, "specs", "synced.md")), "synced\n");
  const status = await s.sync("status");
  assert.match(status.stdout, /^darkmem-sync: project proj at http:\/\/127\.0\.0\.1:9; mirror /);
  write(path.join(s.home, ".dforge", "config.json"), JSON.stringify({
    darkmemEnabled: true, darkmem: { url: "http://127.0.0.1:9", api_key_env: "DARKMEM_API_KEY", repos: { [s.repo]: { project: "proj", documentStore: "local" } } },
  }));
  const moved = await s.sync("reconcile");
  assert.equal(moved.code, 0, moved.stdout + moved.stderr);
  assert.match(moved.stdout, /^darkmem-sync reconcile: documents moved to local from the mirror, without darkmem \(darkmem is unreachable: /m);
  assert.equal(read(path.join(s.repo, "docs", "dforge", "specs", "synced.md")), "synced\n");
});

test("undecided, push and pull skip without promising a move", async () => {
  const s = inMirror({ enabled: false });
  const result = await s.sync("push");
  assert.deepEqual([result.code, result.stdout], [0, "darkmem-sync: push skipped: darkmem is off by default since dforge 3.0 and darkmemEnabled is unset; the mirror is not synced until darkmemEnabled is set\n"]);
});

test("a 2.x record gains its project and mirror at the next command, so unmapping later still finds the mirror", async () => {
  const s = inMirror({ enabled: true });
  write(path.join(s.home, ".dforge", "stores.json"), JSON.stringify({ [s.repo]: { documents: "darkmem", progress: "darkmem" } }));
  assert.equal((await s.sync("status")).code, 0);
  const record = JSON.parse(read(path.join(s.home, ".dforge", "stores.json")))[s.repo];
  assert.deepEqual([record.project, record.mirror], ["proj", s.mirror]);
  write(path.join(s.home, ".dforge", "config.json"), JSON.stringify({ darkmemEnabled: true }));
  const moved = await s.sync("reconcile");
  assert.equal(moved.code, 0, moved.stdout + moved.stderr);
  assert.equal(read(path.join(s.repo, "docs", "dforge", "specs", "synced.md")), "synced\n");
});
