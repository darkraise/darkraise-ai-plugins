import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import test from "node:test";
import { sha } from "./stub-server.mjs";
import { makeHome, makeRepo, read, run, write } from "./helpers.mjs";

const STATE = documents => JSON.stringify({ version: 1, documents, ledgers: {}, checkpoint: null, checkpointAt: null, conflicts: [], pendingLinks: [], prefix: "forge" });

// A repository whose documents and progress a 2.x run put in the mirror;
// `enabled` as makeHome takes it, and an unreachable darkmem url.
function inMirror({ enabled = "off", config } = {}) {
  const repo = makeRepo();
  const home = makeHome({ repo, enabled, config });
  write(path.join(home.docsRoot, "specs", "synced.md"), "synced\n");
  write(path.join(home.docsRoot, "specs", "edited.md"), "edited locally\n");
  write(path.join(home.workRoot, "sdd", "p1", "progress.md"), "# SDD ledger — plan: docs/forge/plans/p1.md\n");
  write(path.join(home.workRoot, "handoff", "latest.md"), "# Handoff\n");
  write(path.join(home.mirror, ".sync-state.json"), STATE({
    "forge/specs/synced.md": sha("synced\n"), "forge/specs/edited.md": sha("edited\n"), "forge/specs/deleted.md": sha("gone\n"),
    "forge/plans/completed.md": sha("- `docs/forge/plans/p1.md`\n"),
  }));
  write(path.join(home.docsRoot, "plans", "completed.md"), "- `docs/forge/plans/p1.md`\n");
  return { repo, ...home, sync: (...args) => run(args, { cwd: repo, env: home.env }) };
}

test("darkmem turned off moves both families back from the mirror without asking darkmem", async () => {
  const s = inMirror();
  const result = await s.sync("reconcile");
  assert.equal(result.code, 0, result.stdout + result.stderr);
  assert.match(result.stdout, /^darkmem-sync reconcile: documents moved to local from the mirror, without darkmem \(darkmem is turned off\)$/m);
  assert.match(result.stdout, /^darkmem-sync reconcile: progress moved to local from the mirror, without darkmem/m);
  assert.match(result.stdout, /^ {4}docs\/forge\/specs\/edited\.md: not on darkmem as the mirror holds it$/m);
  assert.match(result.stdout, /^ {4}forge\/specs\/deleted\.md: deleted in the mirror but not on darkmem$/m);
  assert.doesNotMatch(result.stdout, /synced\.md: not on darkmem/);
  assert.equal(read(path.join(s.repo, "docs", "forge", "specs", "edited.md")), "edited locally\n");
  assert.equal(read(path.join(s.repo, ".forge", "sdd", "p1", "progress.md")), "# SDD ledger — plan: docs/forge/plans/p1.md\n");
  assert.equal(read(path.join(s.repo, ".forge", "handoff", "latest.md")), "# Handoff\n");
  assert.equal(fs.existsSync(s.docsRoot), false);
  assert.equal(fs.readdirSync(s.mirror).filter(name => /^forge-moved-/.test(name)).length, 1, "the mirror is kept as a backup");
  const record = JSON.parse(read(path.join(s.home, ".dr-forge", "stores.json")))[s.repo];
  assert.deepEqual([record.documents, record.progress], ["local", "local"]);
  const again = await s.sync("reconcile");
  assert.deepEqual([again.code, again.stdout], [0, "darkmem-sync: local mode — darkmem is disabled (darkmemEnabled is false)\n"]);
});

test("an unmapped repository moves back from the mirror its record names", async () => {
  const s = inMirror({ enabled: true, config: { darkmemEnabled: true } });
  const result = await s.sync("reconcile");
  assert.equal(result.code, 0, result.stdout + result.stderr);
  assert.match(result.stdout, /^darkmem-sync reconcile: documents moved to local from the mirror, without darkmem \(the repository is not mapped to darkmem\)$/m);
  assert.equal(read(path.join(s.repo, "docs", "forge", "specs", "synced.md")), "synced\n");
});

test("darkmemEnabled unset keeps a 2.x mirror where it is and says how to choose", async () => {
  const s = inMirror({ enabled: false });
  const result = await s.sync("reconcile");
  assert.equal(result.code, 0, result.stdout + result.stderr);
  assert.equal(result.stdout, "darkmem-sync reconcile: darkmem is off by default since dr-forge 3.0 and darkmemEnabled is unset; documents and progress stay in the mirror, unsynced: set darkmemEnabled to true to sync them, or to false to move them back\n");
  assert.equal(read(path.join(s.docsRoot, "specs", "synced.md")), "synced\n");
  assert.equal(fs.existsSync(path.join(s.repo, "docs", "forge", "specs")), false);
});

test("while darkmem is off, push and pull skip, status names the mirror, and revision refuses", async () => {
  const s = inMirror();
  for (const command of ["push", "pull"]) {
    const result = await s.sync(command);
    assert.deepEqual([result.code, result.stdout], [0, `darkmem-sync: ${command} skipped: darkmem is disabled (darkmemEnabled is false); the mirror is not synced, and reconcile moves it back\n`]);
  }
  const status = await s.sync("status");
  assert.equal(status.code, 0, status.stderr);
  assert.match(status.stdout, /^darkmem-sync: project proj not synced \(darkmem disabled or unmapped\); mirror /);
  const revision = await s.sync("revision", "docs/forge/specs/synced.md");
  assert.equal(revision.code, 1);
  assert.match(revision.stdout, /^refused: docs\/forge\/specs\/synced\.md is not synced and unchanged: darkmem is disabled/);
});

test("turned on with darkmem unreachable, a family stays in the mirror and keeps working offline", async () => {
  const s = inMirror({ enabled: true });
  const result = await s.sync("reconcile");
  assert.deepEqual([result.code, result.stdout], [0, ""]);
  const status = await s.sync("status");
  assert.match(status.stdout, /^darkmem-sync: project proj at http:\/\/127\.0\.0\.1:9; mirror /);
});
