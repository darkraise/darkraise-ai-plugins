// Acceptance test A3 for docs/dforge/specs/2026-11-15-plugin-review-fixes-design.md:
// a plan's amendments travel with its ledger through darkmem, and a fresh
// checkout restored from the mirror applies them.
import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";
import { startStub } from "./stub-server.mjs";
import { git, makeHome, makeRepo, read, run, write } from "./helpers.mjs";

const TASK_BRIEF = fileURLToPath(new URL("../../scripts/task-brief", import.meta.url));
const AMENDMENTS = "## A1 — Task 1\nReason: r\nCost if wrong: c\n### Old\n````text\nPrint hello.\n````\n### New\n````text\nPrint HELLO LOUDLY.\n````\n";
const PLAN = "# P1 Implementation Plan\n\n**Goal:** g\n\n## Global Constraints\n\n- c\n\n## Contracts\n\n- c\n\n### Task 1: first\n\n**Evaluation:** files 0 - spec 0 - coupling 1 - risk 0 = 1\n\nPrint hello.\n";
const LEDGER = "# SDD ledger — plan: docs/p1.md\nTask 1: Ruling: amendment A1 — Task 1 — louder — none\n";

function brief(args, { cwd, env }) {
  return new Promise(resolve => {
    execFile("bash", [TASK_BRIEF, ...args], { cwd, env: { ...env, DFORGE_NO_SETTINGS: "1" }, timeout: 60000 }, (error, stdout, stderr) => {
      resolve({ code: error ? (typeof error.code === "number" ? error.code : -1) : 0, stdout, stderr });
    });
  });
}

function planned(repo) {
  write(path.join(repo, "docs", "p1.md"), PLAN);
  write(path.join(repo, ".gitignore"), ".dforge/\n");
  git(repo, "add", "docs/p1.md", ".gitignore");
  git(repo, "commit", "-q", "-m", "plan");
}

test("A3: amendments.md is synced with the ledger, and a fresh checkout restored from the mirror applies it", async t => {
  const stub = await startStub();
  t.after(() => stub.close());
  const repo = makeRepo();
  planned(repo);
  const home = makeHome({ repo, url: stub.url });
  write(path.join(home.workRoot, "sdd", "p1", "progress.md"), LEDGER);
  write(path.join(home.workRoot, "sdd", "p1", "amendments.md"), AMENDMENTS);
  const pushed = await run(["push"], { cwd: repo, env: home.env });
  assert.equal(pushed.code, 0, pushed.stdout + pushed.stderr);

  const stored = [...stub.db.documents.values()].filter(d => d.content === AMENDMENTS);
  assert.equal(stored.length, 1, "darkmem holds the amendments document");
  assert.ok(stub.db.workstreams.some(w => w.key === "p1"), "and the ledger's workstream");

  // A different machine: a fresh checkout, a fresh home, the same darkmem.
  const repo2 = makeRepo();
  planned(repo2);
  const home2 = makeHome({ repo: repo2, url: stub.url });
  const pulled = await run(["pull"], { cwd: repo2, env: home2.env });
  assert.equal(pulled.code, 0, pulled.stdout + pulled.stderr);
  assert.equal(read(path.join(home2.workRoot, "sdd", "p1", "amendments.md")), AMENDMENTS);
  assert.ok(fs.existsSync(path.join(home2.workRoot, "sdd", "p1", "progress.md")), "the ledger is restored beside it");

  const opened = await brief(["docs/p1.md", "1"], { cwd: repo2, env: home2.env });
  assert.equal(opened.code, 0, opened.stdout + opened.stderr);
  const text = [path.join(home2.workRoot, "sdd", "p1", "task-1-brief.md"), path.join(repo2, ".dforge", "sdd", "p1", "task-1-brief.md")]
    .filter(f => fs.existsSync(f)).map(f => read(f)).join("\n");
  assert.match(text, /Print HELLO LOUDLY\./, "the restored checkout applies the approved amendment");
  assert.doesNotMatch(text, /Print hello\./);
});
