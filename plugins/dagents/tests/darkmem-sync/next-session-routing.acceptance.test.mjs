// Acceptance test A22 for docs/dagents/specs/2026-11-16-next-session-routing-design.md:
// a latest.md written by `next-step --complete` or `--project` is pushed as a
// checkpoint under the `project` workstream, and a second mirror's pull
// receives it.
import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";
import { startStub } from "./stub-server.mjs";
import { git, makeHome, makeRepo, read, run, write } from "./helpers.mjs";

const NEXT_STEP = fileURLToPath(new URL("../../scripts/next-step", import.meta.url));
const PLAN = "docs/dagents/plans/2026-11-01-p1.md";
const PLAN_TEXT = "# P1\n\n**Spec:** docs/dagents/specs/s.md\n**Execution:** inline — `claude --model sonnet --effort high` — small\n\n### Task 1: One\n\nBody.\n";
const REGISTER = [
  "# r — item register", "", "**Source:** test", "**Covers:** docs/dagents/specs/s.md", "",
  "| # | Item | Assigned | Acceptance | State | Note |", "|---|---|---|---|---|---|",
  "| 1 | A requirement | docs/dagents/specs/s.md | - | open | - |", "",
].join("\n");

function nextStep(args, { cwd, env }) {
  return new Promise(resolve => {
    execFile("bash", [NEXT_STEP, ...args], { cwd, env: { ...env, DAGENTS_NO_SETTINGS: "1" }, timeout: 60000 }, (error, stdout, stderr) => {
      resolve({ code: error ? (typeof error.code === "number" ? error.code : -1) : 0, stdout, stderr });
    });
  });
}

// A repository with its documents local and its progress in darkmem, so
// next-step writes latest.md into the mirror, where darkmem-sync reads it.
function plannedRepo() {
  const repo = makeRepo();
  write(path.join(repo, ".gitignore"), ".dagents/\n");
  write(path.join(repo, "docs", "dagents", "specs", "s.md"), "# S\n");
  write(path.join(repo, PLAN), PLAN_TEXT);
  write(path.join(repo, "docs", "dagents", "plans", "completed.md"), `# Completed plans\n\n- 2026-11-02 — \`${PLAN}\` — merged\n`);
  write(path.join(repo, "docs", "dagents", "registers", "r.md"), REGISTER);
  git(repo, "add", "-A");
  git(repo, "commit", "-q", "-m", "docs");
  return repo;
}

for (const mode of ["--complete", "--project"]) {
  test(`A22: a latest.md written by next-step ${mode} is pushed under the project workstream and a second mirror pulls it`, async t => {
    const stub = await startStub();
    t.after(() => stub.close());
    const repo = plannedRepo();
    const home = makeHome({ repo, url: stub.url, stores: { documents: "local", progress: "darkmem" } });
    // The finished plan's own ledger is in the mirror too: pushing it closes its workstream.
    write(path.join(home.workRoot, "sdd", "2026-11-01-p1", "progress.md"), `# SDD ledger — plan: ${PLAN}\nTask 1: complete (commits a..b, review clean)\n`);
    const args = mode === "--complete" ? ["--complete", PLAN] : ["--project"];
    const wrote = await nextStep(args, { cwd: repo, env: home.env });
    assert.equal(wrote.code, 0, wrote.stdout + wrote.stderr);
    const latest = path.join(home.workRoot, "handoff", "latest.md");
    assert.ok(fs.existsSync(latest), "next-step wrote latest.md into the mirror");
    const text = read(latest);
    assert.match(text, /^## Next session$/m);
    assert.doesNotMatch(text, /^## State$/m, "the block has no State section naming a plan");

    const pushed = await run(["push"], { cwd: repo, env: home.env });
    assert.equal(pushed.code, 0, pushed.stdout + pushed.stderr);
    assert.doesNotMatch(pushed.stdout, /^failed:/m);
    const project = stub.db.workstreams.find(w => w.key === "project");
    assert.ok(project, "darkmem holds a workstream named project");
    const checkpoints = project.entries.filter(e => e.kind === "checkpoint");
    assert.equal(checkpoints.length, 1, "one checkpoint under it");
    assert.equal(checkpoints[0].body, text, "carrying latest.md as written");
    const finished = stub.db.workstreams.find(w => w.key === "2026-11-01-p1");
    assert.equal((finished?.entries ?? []).filter(e => e.kind === "checkpoint").length, 0, "none under the finished plan's workstream");

    // A different machine: a fresh checkout, a fresh home, the same darkmem.
    const repo2 = plannedRepo();
    const home2 = makeHome({ repo: repo2, url: stub.url, stores: { documents: "local", progress: "darkmem" } });
    const pulled = await run(["pull"], { cwd: repo2, env: home2.env });
    assert.equal(pulled.code, 0, pulled.stdout + pulled.stderr);
    assert.equal(read(path.join(home2.workRoot, "handoff", "latest.md")), text, "the second mirror receives latest.md");
  });
}
