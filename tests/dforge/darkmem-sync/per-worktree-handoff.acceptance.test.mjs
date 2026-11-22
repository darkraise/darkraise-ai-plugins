// Acceptance tests for the per-worktree handoff spec, A11: with progress in
// darkmem, push and pull carry only the primary's handoff, and a push run from
// a linked worktree says the worktree's stays local.
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import test from "node:test";
import { createClient } from "../../../plugins/dforge/scripts/lib/darkmem-client.mjs";
import { STUB_KEY, startStub } from "./stub-server.mjs";
import { git, makeHome, makeRepo, read, run, scratch, write } from "./helpers.mjs";

async function setup(t) {
  const stub = await startStub();
  t.after(() => stub.close());
  const repo = makeRepo();
  const home = makeHome({ repo, url: stub.url });
  const seed = createClient({ url: stub.url, apiKey: STUB_KEY, runKey: "seed" });
  const worktree = path.join(scratch("dms-a11-wt-"), "wt");
  git(repo, "worktree", "add", "-q", "-b", "wt", worktree);
  const primaryFile = path.join(home.workRoot, "handoff", "stored.md");
  const worktreeFile = path.join(worktree, ".dforge", "handoff", "stored.md");
  return { stub, repo, worktree, seed, primaryFile, worktreeFile, ...home };
}

const checkpoints = (stub, key) => (stub.db.workstreams.find(w => w.key === key)?.entries ?? []).filter(e => e.kind === "checkpoint");
const sentBodies = stub => JSON.stringify(stub.db.requests.map(r => r.body ?? null));

test("A11: push run from the primary sends the primary's handoff and not the worktree's", async t => {
  const s = await setup(t);
  write(s.primaryFile, "# Handoff\n\nPRIMARY-HANDOFF-MARKER\n");
  write(s.worktreeFile, "# Handoff\n\nWORKTREE-HANDOFF-MARKER\n");
  const result = await run(["push", "--handoff", s.primaryFile, "--workstream", "ws-primary"], { cwd: s.repo, env: s.env });
  assert.equal(result.code, 0, result.stdout + result.stderr);
  assert.equal(checkpoints(s.stub, "ws-primary").length, 1);
  assert.match(checkpoints(s.stub, "ws-primary")[0].body, /PRIMARY-HANDOFF-MARKER/);
  assert.doesNotMatch(sentBodies(s.stub), /WORKTREE-HANDOFF-MARKER/);
  assert.doesNotMatch(result.stdout, /worktree handoff stays local/);
});

test("A11: push run from a linked worktree prints that its handoff stays local and never sends it", async t => {
  const s = await setup(t);
  write(s.primaryFile, "# Handoff\n\nPRIMARY-HANDOFF-MARKER\n");
  write(s.worktreeFile, "# Handoff\n\nWORKTREE-HANDOFF-MARKER\n");
  const result = await run(["push", "--handoff", s.primaryFile, "--workstream", "ws-primary"], { cwd: s.worktree, env: s.env });
  assert.equal(result.code, 0, result.stdout + result.stderr);
  assert.ok(result.stdout.split("\n").includes(`worktree handoff stays local: ${s.worktreeFile}`), result.stdout);
  assert.doesNotMatch(sentBodies(s.stub), /WORKTREE-HANDOFF-MARKER/);
  assert.match(checkpoints(s.stub, "ws-primary")[0]?.body ?? "", /PRIMARY-HANDOFF-MARKER/, "the primary's handoff is what a worktree's push carries");
  assert.equal(read(s.worktreeFile), "# Handoff\n\nWORKTREE-HANDOFF-MARKER\n");
});

test("A11: pull writes only the primary's handoff under the mirror, from the primary and from a worktree", async t => {
  const s = await setup(t);
  await s.seed.append({ project: "proj", workstream: "ws-pull", entries: [{ kind: "checkpoint", body: "# From darkmem\n\nDARKMEM-CHECKPOINT-MARKER\n" }] });
  write(s.worktreeFile, "# Handoff\n\nWORKTREE-LOCAL-MARKER\n");
  const fromWorktree = await run(["pull"], { cwd: s.worktree, env: s.env });
  assert.equal(fromWorktree.code, 0, fromWorktree.stdout + fromWorktree.stderr);
  // An unmarked checkpoint lands in the mirror under the migration's adhoc-legacy key.
  const mirrorHandoffs = path.dirname(s.primaryFile);
  const pulled = () => fs.readdirSync(mirrorHandoffs).map(name => read(path.join(mirrorHandoffs, name)));
  assert.equal(pulled().length, 1);
  assert.match(pulled()[0], /DARKMEM-CHECKPOINT-MARKER/);
  assert.equal(read(s.worktreeFile), "# Handoff\n\nWORKTREE-LOCAL-MARKER\n", "pull leaves the worktree's handoff alone");
  fs.rmSync(s.worktreeFile);
  const fromPrimary = await run(["pull"], { cwd: s.repo, env: s.env });
  assert.equal(fromPrimary.code, 0, fromPrimary.stdout + fromPrimary.stderr);
  assert.equal(fs.existsSync(s.worktreeFile), false, "pull never creates a worktree's handoff");
  assert.match(pulled()[0], /DARKMEM-CHECKPOINT-MARKER/);
});
