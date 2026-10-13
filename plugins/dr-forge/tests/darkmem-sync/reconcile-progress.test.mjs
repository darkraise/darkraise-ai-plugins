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
