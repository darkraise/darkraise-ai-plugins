import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import {
  EMPTY_SHA, StateError, acquireLock, checkpointTarget, lockOwner, decodeUtf8, emptyState, ledgerFiles, ledgerPlanPath,
  listDocumentFiles, loadState, localChanges, pathToUri, propertiesFor, saveState, sha256, splitAtBlankLines,
  splitAtLimit, unsupportedPlanDirs, uriToLocal,
} from "../../scripts/lib/darkmem-mirror.mjs";
import { scratch, write } from "./helpers.mjs";

function mirror() {
  const root = scratch("dms-mirror-");
  return { root, roots: { docsRoot: path.join(root, "superpowers"), workRoot: path.join(root, "work") } };
}

test("uris map to the docs root, handoff uris to the plan's directory, and nothing climbs out or names a dotfile", () => {
  const { roots } = mirror();
  assert.equal(uriToLocal(roots, "superpowers/specs/a.md"), path.join(roots.docsRoot, "specs", "a.md"));
  assert.equal(uriToLocal(roots, "superpowers/handoff/p1.md"), path.join(roots.workRoot, "sdd", "p1", "handoff.md"));
  for (const bad of [
    "superpowers/../x.md", "superpowers//a.md", "other/a.md", "superpowers", "superpowers/handoff/a/b.md",
    "superpowers/handoff/x.txt", "superpowers/.hidden.md", "superpowers/notes/.x/a.md",
  ]) {
    assert.equal(uriToLocal(roots, bad), null, bad);
  }
});

test("document files list docs and handoff notes, skip dotfiles, and reserve docs/handoff", () => {
  const { roots } = mirror();
  write(path.join(roots.docsRoot, "specs", "a.md"), "a");
  write(path.join(roots.docsRoot, ".hidden"), "h");
  write(path.join(roots.docsRoot, "handoff", "x.md"), "x");
  write(path.join(roots.workRoot, "sdd", "p1", "handoff.md"), "h");
  write(path.join(roots.workRoot, "sdd", "p1", "progress.md"), "l");
  write(path.join(roots.workRoot, "sdd", "bad name", "progress.md"), "l");
  assert.deepEqual(listDocumentFiles(roots).map(f => f.uri), [null, "superpowers/specs/a.md", "superpowers/handoff/p1.md"]);
  assert.deepEqual(ledgerFiles(roots.workRoot).map(f => f.slug), ["p1"]);
  assert.deepEqual(unsupportedPlanDirs(roots.workRoot), [path.join(roots.workRoot, "sdd", "bad name")]);
});

test("a directory that cannot be read is an error, not an empty listing", () => {
  const { roots } = mirror();
  write(roots.docsRoot, "a file where the docs root should be");
  assert.throws(() => listDocumentFiles(roots), { code: "ENOTDIR" });
  assert.deepEqual(listDocumentFiles({ docsRoot: path.join(roots.docsRoot, "..", "absent"), workRoot: roots.workRoot }), []);
});

test("splitAtLimit cuts after newlines, never splits a surrogate pair, and concatenates back", () => {
  const text = `${"a".repeat(7)}\n${"b".repeat(3)}\n${"c".repeat(12)}`;
  const pieces = splitAtLimit(text, 10);
  assert.equal(pieces.join(""), text);
  assert.ok(pieces.every(p => p.length <= 10));
  assert.equal(pieces[0], `${"a".repeat(7)}\n`);
  const emoji = `${"x".repeat(9)}😀tail`;
  const split = splitAtLimit(emoji, 10);
  assert.equal(split.join(""), emoji);
  assert.equal(split[0], "x".repeat(9));
});

test("splitAtBlankLines keeps each blank line at the end of its piece", () => {
  const text = "# L\n\nTask 1: a\nmore\n\n\nTask 2: b\r\n\r\ntail";
  const pieces = splitAtBlankLines(text);
  assert.equal(pieces.join(""), text);
  assert.deepEqual(pieces, ["# L\n\n", "Task 1: a\nmore\n\n", "\n", "Task 2: b\r\n\r\n", "tail"]);
});

test("decodeUtf8 refuses invalid bytes and keeps a byte order mark", () => {
  assert.equal(decodeUtf8(Buffer.from([0xff, 0xfe, 0x41])), null);
  assert.equal(decodeUtf8(Buffer.from([0xef, 0xbb, 0xbf, 0x41])), "﻿A");
});

test("paths name their uris; plans and drafts name their properties; a handoff note names its target", () => {
  const { roots } = mirror();
  assert.equal(pathToUri("docs/superpowers/plans/p1.md"), "superpowers/plans/p1.md");
  assert.equal(pathToUri("/home/u/.dr-superpowers/mirror/p/superpowers/plans/p1.md"), "superpowers/plans/p1.md");
  assert.equal(pathToUri("/repo/.superpowers/sdd/p1/progress.md"), null);
  assert.equal(ledgerPlanPath("# SDD ledger — plan: docs/superpowers/plans/p1.md\nTask 1: x\n"), "docs/superpowers/plans/p1.md");
  assert.equal(ledgerPlanPath("Task 1: x\n"), null);
  write(path.join(roots.docsRoot, "plans", "p1.md"), "# P\n\n**Spec:** `docs/superpowers/specs/s.md`\n");
  write(path.join(roots.workRoot, "sdd", "p1", "handoff.md"), "h");
  assert.deepEqual(propertiesFor(roots, "p1", "docs/superpowers/plans/p1.md"), {
    plan_uri: "superpowers/plans/p1.md", spec_uri: "superpowers/specs/s.md", handoff_uri: "superpowers/handoff/p1.md",
  });
  assert.deepEqual(propertiesFor(roots, "d-design", "docs/superpowers/specs/d-design.md"), { spec_uri: "superpowers/specs/d-design.md" });
  assert.deepEqual(propertiesFor(roots, "adhoc", null), {});
  assert.deepEqual(
    checkpointTarget("# Handoff\n\n## State\n- Worktree: `/r`\n- Plan: `docs/superpowers/plans/p1.md`; ledger: `x`\n\n## Gotchas\n- Plan: `other.md`\n"),
    { slug: "p1", path: "docs/superpowers/plans/p1.md" },
  );
  assert.deepEqual(checkpointTarget("## State\n- Draft: `docs/superpowers/specs/d-design.md`\n"), { slug: "d-design", path: "docs/superpowers/specs/d-design.md" });
  assert.equal(checkpointTarget("## State\n- a punch list\n## Gotchas\n- Plan: `x.md`\n"), null);
});

test("state round-trips, including keys an ordinary object would inherit", () => {
  const { root } = mirror();
  const file = path.join(root, ".sync-state.json");
  assert.deepEqual(loadState(file), emptyState());
  const state = emptyState();
  state.documents["superpowers/a.md"] = sha256("a");
  for (const slug of ["constructor", "toString", "__proto__"]) state.ledgers[slug] = { offset: 3, prefix: sha256("abc") };
  state.checkpoint = sha256("c");
  state.checkpointAt = "2026-09-24T10:00:00.000Z";
  saveState(file, state);
  const loaded = loadState(file);
  assert.deepEqual(Object.keys(loaded.ledgers).sort(), ["__proto__", "constructor", "toString"]);
  assert.deepEqual(loaded.ledgers.constructor, { offset: 3, prefix: sha256("abc") });
  assert.equal(loaded.documents["superpowers/a.md"], sha256("a"));
  assert.equal(loaded.checkpointAt, "2026-09-24T10:00:00.000Z");
});

test("an unreadable or malformed state file is an error rather than a fresh start", () => {
  const { root } = mirror();
  const file = path.join(root, ".sync-state.json");
  const good = { version: 1, documents: {}, ledgers: {}, checkpoint: null, checkpointAt: null, conflicts: [] };
  for (const bad of [
    "{broken",
    JSON.stringify({ ...good, version: 2 }),
    JSON.stringify({ ...good, documents: null }),
    JSON.stringify({ ...good, documents: { "superpowers/a.md": "not-a-hash" } }),
    JSON.stringify({ ...good, ledgers: { p1: { offset: -1, prefix: EMPTY_SHA } } }),
    JSON.stringify({ ...good, ledgers: { p1: { offset: "3", prefix: EMPTY_SHA } } }),
    JSON.stringify({ ...good, ledgers: { "../x": { offset: 0, prefix: EMPTY_SHA } } }),
    JSON.stringify({ ...good, checkpoint: "x" }),
    JSON.stringify({ ...good, conflicts: [1] }),
  ]) {
    fs.writeFileSync(file, bad);
    assert.throws(() => loadState(file), StateError, bad);
  }
});

test("localChanges names new, modified, unpushed, rewritten, unsupported and checkpoint changes", () => {
  const { roots } = mirror();
  const state = emptyState();
  write(path.join(roots.docsRoot, "a.md"), "a");
  write(path.join(roots.docsRoot, "b.md"), "b");
  state.documents["superpowers/b.md"] = sha256("old");
  write(path.join(roots.workRoot, "sdd", "p1", "progress.md"), "one\ntwo\n");
  state.ledgers.p1 = { offset: 4, prefix: sha256("one\n") };
  write(path.join(roots.workRoot, "sdd", "p2", "progress.md"), "changed\n");
  state.ledgers.p2 = { offset: 4, prefix: sha256("orig") };
  write(path.join(roots.workRoot, "sdd", "bad name", "handoff.md"), "h");
  write(path.join(roots.workRoot, "handoff", "latest.md"), "# H\n");
  assert.deepEqual(localChanges(roots, state), [
    "new: superpowers/a.md",
    "modified: superpowers/b.md",
    "unpushed: sdd/p1/progress.md (4 bytes)",
    "rewritten: sdd/p2/progress.md",
    `unsupported: ${path.join(roots.workRoot, "sdd", "bad name")} (not a usable workstream key)`,
    "modified: handoff/latest.md",
  ]);
  assert.equal(EMPTY_SHA, sha256(""));
});

test("the lock admits one holder, waits on a live one however old, and takes over a dead one", () => {
  const { root } = mirror();
  const lock = path.join(root, ".sync.lock");
  const release = acquireLock(root);
  assert.equal(typeof release, "function");
  assert.equal(lockOwner(root).pid, process.pid);
  assert.equal(acquireLock(root), null);
  const old = new Date(Date.now() - 60 * 60 * 1000);
  fs.utimesSync(lock, old, old);
  assert.equal(acquireLock(root), null, "this process is alive, so its lock is not stale");
  const dead = spawnSync(process.execPath, ["-e", ""]).pid;
  fs.writeFileSync(path.join(lock, "owner.json"), JSON.stringify({ pid: dead, host: os.hostname(), token: "t" }));
  const successor = acquireLock(root);
  assert.equal(typeof successor, "function");
  release();
  assert.equal(fs.existsSync(lock), true, "a displaced holder's release leaves its successor's lock");
  successor();
  assert.equal(fs.existsSync(lock), false);
  assert.deepEqual(fs.readdirSync(root), [], "no side directory is left behind");
});

test("two takeovers of one abandoned lock leave exactly one holder", () => {
  const { root } = mirror();
  const lock = path.join(root, ".sync.lock");
  fs.mkdirSync(lock);
  const dead = spawnSync(process.execPath, ["-e", ""]).pid;
  fs.writeFileSync(path.join(lock, "owner.json"), JSON.stringify({ pid: dead, host: os.hostname(), token: "stale" }));
  let first = null;
  const second = acquireLock(root, { beforeTakeover: () => { first ??= acquireLock(root); } });
  assert.equal(typeof first, "function", "the takeover that ran first holds the lock");
  assert.equal(second, null, "the later takeover finds a live lock and backs off");
  assert.equal(fs.existsSync(lock), true);
  first();
  assert.equal(fs.existsSync(lock), false);
  assert.deepEqual(fs.readdirSync(root), []);
});

test("a lock with no owner record is taken over only once it is stale", () => {
  const { root } = mirror();
  const lock = path.join(root, ".sync.lock");
  fs.mkdirSync(lock);
  assert.equal(acquireLock(root), null);
  const old = new Date(Date.now() - 20 * 60 * 1000);
  fs.utimesSync(lock, old, old);
  const release = acquireLock(root);
  assert.equal(typeof release, "function");
  release();
});
