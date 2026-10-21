import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import {
  EMPTY_SHA, MAX_ENTRY_CHARS, StateError, acquireLock, archiveUri, caseGroups, checkRemote, checkpointTarget, lockOwner, decodeUtf8, emptyState, familiesOf,
  isArchiveUri, isoMicros, ledgerEntries, ledgerFiles, ledgerPieces, ledgerPlanPath, lineProperties, listDocumentFiles, loadState, localChanges,
  pathToUri, propertiesFor, saveState, sha256, splitAtBlankLines, splitAtLimit, unsupportedPlanDirs, uriFamily, uriProblem, uriToLocal,
  utcStamp, utf8Fault, checkpointAtOf, newestCheckpointAt, recordCheckpointAt,
} from "../../scripts/lib/darkmem-mirror.mjs";
import { git, makeRepo, scratch, write } from "./helpers.mjs";

function mirror() {
  const root = scratch("dms-mirror-");
  return { root, roots: { docsRoot: path.join(root, "dforge"), workRoot: path.join(root, "work") } };
}

test("uris map to the docs root, handoff uris to the plan's directory, and nothing climbs out or names a dotfile", () => {
  const { roots } = mirror();
  assert.equal(uriToLocal(roots, "dforge/specs/a.md"), path.join(roots.docsRoot, "specs", "a.md"));
  assert.equal(uriToLocal(roots, "dforge/handoff/p1.md"), path.join(roots.workRoot, "sdd", "p1", "handoff.md"));
  for (const bad of [
    "dforge/../x.md", "dforge//a.md", "other/a.md", "dforge", "dforge/handoff/a/b.md",
    "dforge/handoff/x.txt", "dforge/.hidden.md", "dforge/notes/.x/a.md",
  ]) {
    assert.equal(uriToLocal(roots, bad), null, bad);
  }
});

test("document files list docs and handoff notes, skip dotfiles, and reserve docs/handoff and docs/archive", () => {
  const { roots } = mirror();
  write(path.join(roots.docsRoot, "specs", "a.md"), "a");
  write(path.join(roots.docsRoot, ".hidden"), "h");
  write(path.join(roots.docsRoot, "handoff", "x.md"), "x");
  write(path.join(roots.docsRoot, "archive", "20261013T091502Z", "a.md"), "old");
  write(path.join(roots.workRoot, "sdd", "p1", "handoff.md"), "h");
  write(path.join(roots.workRoot, "sdd", "p1", "progress.md"), "l");
  write(path.join(roots.workRoot, "sdd", "bad name", "progress.md"), "l");
  assert.deepEqual(listDocumentFiles(roots).map(f => f.uri), [null, null, "dforge/specs/a.md", "dforge/handoff/p1.md"]);
  assert.deepEqual(ledgerFiles(roots.workRoot).map(f => f.slug), ["p1"]);
  assert.deepEqual(unsupportedPlanDirs(roots.workRoot), [path.join(roots.workRoot, "sdd", "bad name")]);
});

test("checkRemote refuses another darkmem while hashes remain, and adopts it once the files moved home", () => {
  const state = emptyState();
  checkRemote("state.json", state, "http://a", "proj");
  assert.deepEqual(state.remote, { url: "http://a", project: "proj" });
  state.documents["dforge/specs/a.md"] = sha256("# A\n");
  assert.throws(() => checkRemote("state.json", state, "http://b", "proj"), StateError);
  delete state.documents["dforge/specs/a.md"];
  state.ledgers.plan = { offset: 1, prefix: sha256("x"), lastSeq: 1 };
  assert.throws(() => checkRemote("state.json", state, "http://b", "proj"), StateError);
  delete state.ledgers.plan;
  checkRemote("state.json", state, "http://b", "other");
  assert.deepEqual(state.remote, { url: "http://b", project: "other" });
});

test("archive uris carry a UTC stamp under dforge/archive/", () => {
  assert.equal(utcStamp(new Date("2026-10-13T09:15:02.789Z")), "20261013T091502Z");
  assert.match(utcStamp(), /^\d{8}T\d{6}Z$/);
  assert.equal(archiveUri("dforge/specs/a.md", "20261013T091502Z"), "dforge/archive/20261013T091502Z/specs/a.md");
  for (const uri of ["dforge/archive", "dforge/archive/20261013T091502Z/specs/a.md"]) assert.equal(isArchiveUri(uri), true, uri);
  for (const uri of ["dforge/archives/a.md", "dforge/specs/archive/a.md", "dforge/a.md"]) assert.equal(isArchiveUri(uri), false, uri);
});

test("localChanges names a synced document deleted from the mirror, only while documents sync", () => {
  const { roots } = mirror();
  const state = emptyState();
  write(path.join(roots.docsRoot, "kept.md"), "k");
  state.documents["dforge/kept.md"] = sha256("k");
  state.documents["dforge/specs/gone.md"] = sha256("g");
  state.documents["dforge/handoff/p1.md"] = sha256("h");
  write(path.join(roots.docsRoot, "archive", "x.md"), "x");
  assert.deepEqual(localChanges(roots, state), [
    `reserved: ${path.join("archive", "x.md")} (the docs root's archive/ directory is not synced)`,
    "deleted: dforge/specs/gone.md",
  ]);
  assert.deepEqual(localChanges({ ...roots, families: { documents: false, progress: true } }, state), []);
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
  assert.throws(() => splitAtLimit("ab", 1), RangeError, "a limit under 2 cannot hold a surrogate pair");
  assert.throws(() => splitAtLimit("😀", 1), RangeError);
});

test("splitAtBlankLines keeps each blank line at the end of its piece", () => {
  const text = "# L\n\nTask 1: a\nmore\n\n\nTask 2: b\r\n\r\ntail";
  const pieces = splitAtBlankLines(text);
  assert.equal(pieces.join(""), text);
  assert.deepEqual(pieces, ["# L\n\n", "Task 1: a\nmore\n\n", "\n", "Task 2: b\r\n\r\n", "tail"]);
});

test("a ledger line yields its task, state and commit; a blank line joins the entry before it", () => {
  const rows = [
    ["Task 3: complete (commits a1b2c3d..f0e1d2c, review clean) — done: x\n", { task: 3, state: "done", commit: "f0e1d2c" }],
    ["Task 4: BLOCKED — impl-opus-high exhausted — decide\n", { task: 4, state: "blocked" }],
    ["Task 5: fix round 2/5 (1 addressed, 0 open — x; commits 1234567..89abcde; resumed)\n", { task: 5, state: "review", commit: "89abcde" }],
    ["Task 6: implementer dforge:impl-sonnet-low (assigned; base 1a2b3c4)\n", { task: 6, state: "wip" }],
    ["Task 7: implementer (assigned)\n", { task: 7 }],
    ["Task 8: minor (deferred): complete (later)\n", { task: 8 }],
    ["Group 1-2: review round 1/5 (commits a..b)\n", {}],
    ["# SDD ledger — plan: docs/dforge/plans/p.md\n", {}],
  ];
  for (const [line, want] of rows) assert.deepEqual(lineProperties(line), want, line);
  assert.deepEqual(ledgerEntries("# L\n\nTask 1: complete (x)\n\n\nTask 2: BLOCKED — y\r\n"), [
    { body: "# L\n\n", properties: {} },
    { body: "Task 1: complete (x)\n\n\n", properties: { task: 1, state: "done" } },
    { body: "Task 2: BLOCKED — y\r\n", properties: { task: 2, state: "blocked" } },
  ]);
  assert.deepEqual(ledgerEntries("\nTask 1: x\n"), [{ body: "\nTask 1: x\n", properties: { task: 1 } }]);
  assert.deepEqual(ledgerEntries("\n\n"), [{ body: "\n\n", properties: {} }]);
});

test("decodeUtf8 refuses invalid bytes and keeps a byte order mark", () => {
  assert.equal(decodeUtf8(Buffer.from([0xff, 0xfe, 0x41])), null);
  assert.equal(decodeUtf8(Buffer.from([0xef, 0xbb, 0xbf, 0x41])), "﻿A");
});

test("paths name their uris; plans and drafts name their properties; a handoff note names its target", () => {
  const { roots } = mirror();
  // A checkout and a project both named dforge; the uri comes from the
  // roots, never from the leftmost dforge/ segment.
  const named = {
    docsRoot: "/home/u/.dforge/mirror/dforge/dforge",
    workRoot: "/home/u/.dforge/mirror/dforge/work",
    worktreeRoot: "/w/dforge",
  };
  assert.equal(pathToUri(named, "docs/superpowers/plans/p1.md"), "dforge/plans/p1.md");
  assert.equal(pathToUri(named, "docs/forge/plans/p1.md"), "dforge/plans/p1.md");
  assert.equal(pathToUri(named, "./docs/dforge/plans/p1.md"), "dforge/plans/p1.md");
  assert.equal(pathToUri(named, "/home/u/.dforge/mirror/dforge/dforge/plans/p1.md"), "dforge/plans/p1.md");
  assert.equal(pathToUri(named, "/w/dforge/docs/dforge/specs/s.md"), "dforge/specs/s.md");
  assert.equal(pathToUri(named, "/w/dforge/docs/superpowers/specs/s.md"), null);
  assert.equal(pathToUri(named, "/w/dforge/docs/forge/specs/s.md"), null);
  assert.equal(pathToUri(named, "/w/dforge/.dforge/sdd/p1/progress.md"), null);
  assert.equal(pathToUri(named, "/elsewhere/dforge/plans/p1.md"), null);
  assert.equal(pathToUri(named, "plans/p1.md"), null);
  assert.equal(pathToUri(named, "docs/dforge/../../x.md"), null);
  assert.equal(pathToUri(named, "docs/forge/plans/"), null, "an empty segment names no document");
  assert.equal(pathToUri(named, "docs/dforge//plans/p1.md"), null);
  assert.equal(ledgerPlanPath("# SDD ledger — plan: docs/superpowers/plans/p1.md\nTask 1: x\n"), "docs/superpowers/plans/p1.md");
  assert.equal(ledgerPlanPath("Task 1: x\n"), null);
  write(path.join(roots.docsRoot, "plans", "p1.md"), "# P\n\n**Spec:** `docs/superpowers/specs/s.md`\n");
  write(path.join(roots.workRoot, "sdd", "p1", "handoff.md"), "h");
  assert.deepEqual(propertiesFor(roots, "p1", "docs/superpowers/plans/p1.md"), {
    plan_uri: "dforge/plans/p1.md", spec_uri: "dforge/specs/s.md", handoff_uri: "dforge/handoff/p1.md",
  });
  assert.deepEqual(propertiesFor(roots, "d-design", "docs/superpowers/specs/d-design.md"), { spec_uri: "dforge/specs/d-design.md" });
  assert.deepEqual(propertiesFor(roots, "adhoc", null), {});
  assert.deepEqual(
    checkpointTarget("# Handoff\n\n## State\n- Worktree: `/r`\n- Plan: `docs/superpowers/plans/p1.md`; ledger: `x`\n\n## Gotchas\n- Plan: `other.md`\n"),
    { slug: "p1", path: "docs/superpowers/plans/p1.md" },
  );
  assert.deepEqual(checkpointTarget("## State\n- Draft: `docs/superpowers/specs/d-design.md`\n"), { slug: "d-design", path: "docs/superpowers/specs/d-design.md" });
  assert.equal(checkpointTarget("## State\n- a punch list\n## Gotchas\n- Plan: `x.md`\n"), null);
});

test("pathToUri reads an absolute path under any worktree's docs directory", () => {
  const repo = makeRepo();
  const worktree = path.join(scratch("dms-wt-"), "wt");
  git(repo, "worktree", "add", "-q", "-b", "wt", worktree);
  const { roots } = mirror();
  const file = path.join(worktree, "docs", "dforge", "plans", "p.md");
  assert.equal(pathToUri({ ...roots, worktreeRoot: repo }, file), "dforge/plans/p.md");
  assert.equal(pathToUri({ ...roots, worktreeRoot: repo }, path.join(worktree, ".dforge", "x.md")), null);
  assert.equal(pathToUri(roots, file), null, "without a worktree root no worktree is listed");
});

test("propertiesFor reads a missing plan as no spec; any other read failure is an error", () => {
  const { roots } = mirror();
  assert.deepEqual(propertiesFor(roots, "p1", "docs/dforge/plans/p1.md"), { plan_uri: "dforge/plans/p1.md" });
  fs.mkdirSync(path.join(roots.docsRoot, "plans", "p1.md"), { recursive: true });
  assert.throws(() => propertiesFor(roots, "p1", "docs/dforge/plans/p1.md"), { code: "EISDIR" });
});

test("a state file the mirror cannot reach is an error, not a fresh start", { skip: process.platform === "win32" && "Windows reports ENOENT under a file" }, () => {
  const { root } = mirror();
  fs.writeFileSync(path.join(root, "file"), "x");
  assert.throws(() => loadState(path.join(root, "file", ".sync-state.json")), StateError);
});

test("each family lists, reports and links only when the roots sync it", () => {
  const { roots } = mirror();
  write(path.join(roots.docsRoot, "specs", "a.md"), "a");
  write(path.join(roots.workRoot, "sdd", "p1", "handoff.md"), "h");
  write(path.join(roots.workRoot, "sdd", "p1", "progress.md"), "l\n");
  write(path.join(roots.workRoot, "handoff", "latest.md"), "x");
  const only = (documents, progress) => ({ ...roots, families: { documents, progress } });
  const uris = r => listDocumentFiles(r).map(f => f.uri);
  assert.deepEqual(uris(roots), ["dforge/specs/a.md", "dforge/handoff/p1.md"]);
  assert.deepEqual(uris(only(true, false)), ["dforge/specs/a.md"]);
  assert.deepEqual(uris(only(false, true)), ["dforge/handoff/p1.md"]);
  assert.deepEqual(uris(only(false, false)), []);
  assert.deepEqual(localChanges(only(true, false), emptyState()), ["new: dforge/specs/a.md"]);
  assert.deepEqual(localChanges(only(false, true), emptyState()), [
    "new: dforge/handoff/p1.md", "unpushed: sdd/p1/progress.md (2 bytes, never synced)", "modified: handoff/latest.md",
  ]);
  assert.deepEqual(propertiesFor(only(true, false), "p1", null), {});
  assert.deepEqual(propertiesFor(only(false, true), "p1", null), { handoff_uri: "dforge/handoff/p1.md" });
  assert.deepEqual(familiesOf(roots), { documents: true, progress: true });
  assert.equal(uriFamily("dforge/handoff/p1.md"), "progress");
  assert.equal(uriFamily("dforge/specs/a.md"), "documents");
  assert.equal(uriFamily("dforge/handoff/sub/x.md"), "documents");
});

test("state round-trips, including keys an ordinary object would inherit", () => {
  const { root } = mirror();
  const file = path.join(root, ".sync-state.json");
  assert.deepEqual(loadState(file), emptyState());
  const state = emptyState();
  state.documents["dforge/a.md"] = sha256("a");
  for (const slug of ["constructor", "toString", "__proto__"]) state.ledgers[slug] = { offset: 3, prefix: sha256("abc") };
  state.checkpoint = sha256("c");
  state.checkpointAt = "2026-09-24T10:00:00.000Z";
  saveState(file, state);
  const loaded = loadState(file);
  assert.deepEqual(Object.keys(loaded.ledgers).sort(), ["__proto__", "constructor", "toString"]);
  assert.deepEqual(loaded.ledgers.constructor, { offset: 3, prefix: sha256("abc") });
  assert.equal(loaded.documents["dforge/a.md"], sha256("a"));
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
    JSON.stringify({ ...good, documents: { "dforge/a.md": "not-a-hash" } }),
    JSON.stringify({ ...good, ledgers: { p1: { offset: -1, prefix: EMPTY_SHA } } }),
    JSON.stringify({ ...good, ledgers: { p1: { offset: "3", prefix: EMPTY_SHA } } }),
    JSON.stringify({ ...good, ledgers: { "../x": { offset: 0, prefix: EMPTY_SHA } } }),
    JSON.stringify({ ...good, checkpoint: "x" }),
    JSON.stringify({ ...good, conflicts: [1] }),
    JSON.stringify({ ...good, ledgers: { p1: { offset: 0, prefix: EMPTY_SHA, lastSeq: -1 } } }),
    JSON.stringify({ ...good, ledgers: { p1: { offset: 0, prefix: EMPTY_SHA, lastSeq: "3" } } }),
    JSON.stringify({ ...good, ledgers: { p1: { offset: 0, prefix: EMPTY_SHA, lastSeq: 1.5 } } }),
    JSON.stringify({ ...good, pendingLinks: "dforge/handoff/p1.md" }),
    JSON.stringify({ ...good, pendingLinks: [1] }),
    JSON.stringify({ ...good, checkpointAt: 5 }),
    JSON.stringify({ ...good, checkpointAt: { "": "2026-09-24T10:00:00.000Z" } }),
    JSON.stringify({ ...good, checkpointAt: { p1: "not a date" } }),
    JSON.stringify({ ...good, checkpointAtByWorkstream: { p1: "not a date" } }),
    JSON.stringify({ ...good, checkpointAtByWorkstream: { "": "2026-09-24T10:00:00.000Z" } }),
    JSON.stringify({ ...good, checkpointAtByWorkstream: "2026-09-24T10:00:00.000Z" }),
  ]) {
    fs.writeFileSync(file, bad);
    assert.throws(() => loadState(file), StateError, bad);
  }
});

test("checkpointAt is kept per workstream; an old single value stands for every workstream until each is written", () => {
  const { root } = mirror();
  const file = path.join(root, ".sync-state.json");
  const old = "2026-09-24T10:00:00.000Z";
  const later = "2026-09-25T10:00:00.000001+00:00";
  fs.writeFileSync(file, JSON.stringify({ version: 1, documents: {}, ledgers: {}, checkpoint: null, checkpointAt: old, conflicts: [] }));
  const state = loadState(file);
  assert.equal(checkpointAtOf(state, "p1"), old);
  recordCheckpointAt(state, "p1", later);
  assert.equal(checkpointAtOf(state, "p1"), later);
  assert.equal(checkpointAtOf(state, "p2"), old, "a workstream not yet written keeps the old value");
  assert.equal(newestCheckpointAt(state), later);
  saveState(file, state);
  const loaded = loadState(file);
  assert.equal(checkpointAtOf(loaded, "p1"), later);
  assert.equal(checkpointAtOf(loaded, "p2"), old);
  assert.equal(newestCheckpointAt(loaded), later);
  const fresh = emptyState();
  assert.equal(checkpointAtOf(fresh, "p1"), null);
  assert.equal(newestCheckpointAt(fresh), null);
  recordCheckpointAt(fresh, "constructor", old);
  assert.equal(checkpointAtOf(fresh, "toString"), null, "the per-workstream record has no prototype");
  assert.equal(checkpointAtOf(fresh, "constructor"), old);
});

test("a checkpointAt key is only looked up, so any workstream key loads, including one with a slash", () => {
  const { root } = mirror();
  const file = path.join(root, ".sync-state.json");
  const at = "2026-09-24T10:00:00.000Z";
  fs.writeFileSync(file, JSON.stringify({ version: 1, documents: {}, ledgers: {}, checkpoint: null, checkpointAt: { "feature/foo": at, "../x": at }, conflicts: [] }));
  const state = loadState(file);
  assert.equal(checkpointAtOf(state, "feature/foo"), at);
  assert.equal(newestCheckpointAt(state), at);
});

test("a single recorded workstream is saved with a string checkpointAt an older dforge reads, and loads back as that workstream", () => {
  const { root } = mirror();
  const file = path.join(root, ".sync-state.json");
  const first = "2026-09-25T10:00:00.000001+00:00";
  const second = "2026-09-25T10:00:00.000002+00:00";
  const state = emptyState();
  recordCheckpointAt(state, "feature/foo", first);
  saveState(file, state);
  const raw = () => JSON.parse(fs.readFileSync(file, "utf8"));
  assert.equal(raw().checkpointAt, first);
  assert.deepEqual(raw().checkpointAtByWorkstream, { "feature/foo": first });
  const loaded = loadState(file);
  assert.equal(checkpointAtOf(loaded, "feature/foo"), first);
  assert.equal(checkpointAtOf(loaded, "p2"), null, "the record stands for the workstream that wrote it, not for every one");
  recordCheckpointAt(loaded, "feature/foo", second);
  saveState(file, loaded);
  assert.equal(raw().checkpointAt, second, "the same workstream again stays a string");
  assert.deepEqual(raw().checkpointAtByWorkstream, { "feature/foo": second });
  const legacy = { version: 1, documents: {}, ledgers: {}, checkpoint: null, checkpointAt: first, conflicts: [] };
  fs.writeFileSync(file, JSON.stringify(legacy));
  const legacyState = loadState(file);
  assert.equal(checkpointAtOf(legacyState, "p2"), first, "a string with no record stands for every workstream");
  saveState(file, legacyState);
  assert.equal(raw().checkpointAt, first);
  assert.equal("checkpointAtByWorkstream" in raw(), false, "a string is saved unchanged, with no extra field");
  saveState(file, emptyState());
  assert.equal(raw().checkpointAt, null);
  assert.equal("checkpointAtByWorkstream" in raw(), false, "null is saved unchanged, with no extra field");
});

test("a legacy string checkpointAt stays a string when a second workstream is recorded, and the legacy value still reads for the others", () => {
  const { root } = mirror();
  const file = path.join(root, ".sync-state.json");
  const old = "2026-09-24T10:00:00.000Z";
  const later = "2026-09-25T10:00:00.000001+00:00";
  fs.writeFileSync(file, JSON.stringify({ version: 1, documents: {}, ledgers: {}, checkpoint: null, checkpointAt: old, conflicts: [] }));
  const state = loadState(file);
  recordCheckpointAt(state, "p2", later);
  saveState(file, state);
  const raw = JSON.parse(fs.readFileSync(file, "utf8"));
  assert.equal(raw.checkpointAt, later, "an older dforge reads a string");
  assert.deepEqual(raw.checkpointAtByWorkstream, { "*": old, p2: later });
  const loaded = loadState(file);
  assert.equal(checkpointAtOf(loaded, "p2"), later);
  assert.equal(checkpointAtOf(loaded, "p1"), old, "the legacy value still stands for a workstream not yet written");
  assert.equal(newestCheckpointAt(loaded), later);
});

test("two recorded workstreams are saved with the newer date as the string, and each loads back per workstream", () => {
  const { root } = mirror();
  const file = path.join(root, ".sync-state.json");
  const first = "2026-09-25T10:00:00.000001+00:00";
  const second = "2026-09-25T10:00:00.000002+00:00";
  const state = emptyState();
  recordCheckpointAt(state, "p1", second);
  recordCheckpointAt(state, "feature/foo", first);
  saveState(file, state);
  const raw = JSON.parse(fs.readFileSync(file, "utf8"));
  assert.equal(raw.checkpointAt, second, "the string is the newer date, whichever workstream recorded it");
  assert.deepEqual(raw.checkpointAtByWorkstream, { p1: second, "feature/foo": first });
  assert.equal(raw.checkpointWorkstream, undefined);
  const loaded = loadState(file);
  assert.equal(checkpointAtOf(loaded, "p1"), second);
  assert.equal(checkpointAtOf(loaded, "feature/foo"), first);
  assert.equal(checkpointAtOf(loaded, "p3"), null);
  assert.equal(newestCheckpointAt(loaded), second);
});

test("a string checkpointAt that differs from the record's newest date stands for every workstream", () => {
  const { root } = mirror();
  const file = path.join(root, ".sync-state.json");
  const first = "2026-09-25T10:00:00.000001+00:00";
  const second = "2026-09-25T10:00:00.000002+00:00";
  const newer = "2026-09-26T10:00:00.000000+00:00";
  const base = { version: 1, documents: {}, ledgers: {}, checkpoint: null, conflicts: [] };
  fs.writeFileSync(file, JSON.stringify({ ...base, checkpointAt: newer, checkpointAtByWorkstream: { p1: first, "feature/foo": second } }));
  const loaded = loadState(file);
  for (const workstream of ["p1", "feature/foo", "p3"]) assert.equal(checkpointAtOf(loaded, workstream), newer, workstream);
  assert.equal(newestCheckpointAt(loaded), newer);
  fs.writeFileSync(file, JSON.stringify({ ...base, checkpointAt: null, checkpointAtByWorkstream: { p1: first } }));
  assert.equal(checkpointAtOf(loadState(file), "p1"), null, "null means none, whatever the record holds");
});

test("localChanges names new, modified, unpushed, rewritten, unsupported and checkpoint changes", () => {
  const { roots } = mirror();
  const state = emptyState();
  write(path.join(roots.docsRoot, "a.md"), "a");
  write(path.join(roots.docsRoot, "b.md"), "b");
  state.documents["dforge/b.md"] = sha256("old");
  write(path.join(roots.workRoot, "sdd", "p1", "progress.md"), "one\ntwo\n");
  state.ledgers.p1 = { offset: 4, prefix: sha256("one\n") };
  write(path.join(roots.workRoot, "sdd", "p2", "progress.md"), "changed\n");
  state.ledgers.p2 = { offset: 4, prefix: sha256("orig") };
  write(path.join(roots.workRoot, "sdd", "bad name", "handoff.md"), "h");
  write(path.join(roots.workRoot, "handoff", "latest.md"), "# H\n");
  assert.deepEqual(localChanges(roots, state), [
    "new: dforge/a.md",
    "modified: dforge/b.md",
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

test("a ledger's lastSeq and the pending handoff links survive a save, and an older state loads with no links", () => {
  const { root } = mirror();
  const file = path.join(root, ".sync-state.json");
  const state = emptyState();
  assert.deepEqual(state.pendingLinks, []);
  state.ledgers.p1 = { offset: 3, prefix: sha256("abc"), lastSeq: 7 };
  state.pendingLinks.push("dforge/handoff/p1.md");
  saveState(file, state);
  const loaded = loadState(file);
  assert.deepEqual(loaded.ledgers.p1, { offset: 3, prefix: sha256("abc"), lastSeq: 7 });
  assert.deepEqual(loaded.pendingLinks, ["dforge/handoff/p1.md"]);
  fs.writeFileSync(file, JSON.stringify({ version: 1, documents: {}, ledgers: {}, checkpoint: null, checkpointAt: null, conflicts: [] }));
  assert.deepEqual(loadState(file).pendingLinks, []);
});

test("utf8Fault finds the first undecodable byte and tells a character cut short at the end apart", () => {
  assert.equal(utf8Fault(Buffer.from("héllo ✓ 😀\n")), null);
  assert.deepEqual(utf8Fault(Buffer.from([0x61, 0xe2, 0x82])), { offset: 1, partial: true });
  assert.deepEqual(utf8Fault(Buffer.from([0x61, 0xf0, 0x9f, 0x98])), { offset: 1, partial: true });
  assert.deepEqual(utf8Fault(Buffer.from([0x61, 0xff])), { offset: 1, partial: false }, "a lone 0xFF is never a partial character");
  assert.deepEqual(utf8Fault(Buffer.from([0x61, 0xc3, 0x28, 0x62])), { offset: 1, partial: false });
  assert.deepEqual(utf8Fault(Buffer.from([0x61, 0x62, 0x80])), { offset: 2, partial: false });
  assert.deepEqual(utf8Fault(Buffer.from([0xe0, 0x80])), { offset: 0, partial: false }, "an overlong lead is refused at once");
  const pool = [0x00, 0x41, 0x7f, 0x80, 0x9f, 0xa0, 0xbf, 0xc1, 0xc2, 0xdf, 0xe0, 0xed, 0xef, 0xf0, 0xf4, 0xf5, 0xff];
  let seed = 7;
  // Math.imul keeps the 32-bit product exact, and the low bits of a
  // power-of-two generator repeat quickly, so only the high 16 are used.
  const next = () => (seed = (Math.imul(seed, 1103515245) + 12345) >>> 0) >>> 16;
  for (let n = 0; n < 20000; n += 1) {
    const buffer = Buffer.from(Array.from({ length: 1 + (next() % 6) }, () => pool[next() % pool.length]));
    assert.equal(utf8Fault(buffer) === null, decodeUtf8(buffer) !== null, buffer.toString("hex"));
  }
});

test("isoMicros orders darkmem's timestamps to the microsecond, offsets applied", () => {
  assert.equal(isoMicros("2026-09-25T10:00:00.000002+00:00") - isoMicros("2026-09-25T10:00:00.000001+00:00"), 1);
  assert.equal(isoMicros("2026-09-25T10:00:00+00:00"), isoMicros("2026-09-25T10:00:00.000000Z"), "a dropped zero fraction");
  assert.equal(isoMicros("2026-09-25T12:00:00.5+02:00"), isoMicros("2026-09-25T10:00:00.500000Z"));
  assert.equal(isoMicros("2026-09-25T10:00:00.1234567Z"), isoMicros("2026-09-25T10:00:00.123456Z"), "digits past six are dropped");
  assert.equal(isoMicros("2026-09-24T10:00:00.123Z"), Date.parse("2026-09-24T10:00:00.123Z") * 1000);
  assert.equal(isoMicros("2200-12-31T23:59:59.999999Z"), Date.UTC(2200, 11, 31, 23, 59, 59) * 1000 + 999999);
  assert.ok(Number.isSafeInteger(isoMicros("2200-12-31T23:59:59.999999Z")));
  for (const bad of [
    "yesterday", "2026-02-30T10:00:00Z", "0099-01-01T00:00:00Z", "1969-12-31T23:59:59Z", "2201-01-01T00:00:00Z",
    "2026-09-25T24:00:00Z", "2026-09-25T10:60:00Z", "2026-09-25T10:00:60Z", "2026-09-25T10:00:00+24:00",
    "2026-09-25T10:00:00+05:60", "2026-09-25T10:00:00",
  ]) {
    assert.equal(isoMicros(bad), null, bad);
  }
});

test("uriProblem refuses names Windows cannot hold, and caseGroups finds uris that differ only in case", () => {
  for (const bad of [
    "dforge/notes/a:b.md", "dforge/notes/a?.md", "dforge/notes/a\u0001.md", "dforge/notes/a.",
    "dforge/notes/a\u007f.md", "dforge/notes/a\u0085.md", "dforge/notes/a ", "dforge/notes/CON.md", "dforge/con/a.md", "dforge/notes/lpt9", "dforge/Aux.tar.gz",
    "dforge/notes/COM¹.md", "dforge/notes/lpt²", "dforge/LPT³.tar.gz",
  ]) {
    assert.notEqual(uriProblem(bad), null, bad);
  }
  for (const good of ["dforge/notes/a.md", "dforge/notes/console.md", "dforge/notes/com10.md", "dforge/handoff/p1.md"]) {
    assert.equal(uriProblem(good), null, good);
  }
  assert.match(uriProblem("dforge/notes/CON.md"), /"CON\.md" is a Windows device name/);
  assert.deepEqual(caseGroups(["dforge/A.md", "dforge/b.md", "dforge/a.md", "dforge/A.md"]), [["dforge/A.md", "dforge/a.md"]]);
  assert.deepEqual(caseGroups(["dforge/a.md", "dforge/b.md"]), []);
});

test("a takeover never moves aside the lock another takeover of the same abandoned lock placed since", () => {
  const { root } = mirror();
  const lock = path.join(root, ".sync.lock");
  fs.mkdirSync(lock);
  const dead = spawnSync(process.execPath, ["-e", ""]).pid;
  fs.writeFileSync(path.join(lock, "owner.json"), JSON.stringify({ pid: dead, host: os.hostname(), token: "stale" }));
  let first = null;
  let third = null;
  const second = acquireLock(root, {
    beforeTakeover: () => { first ??= acquireLock(root); },
    beforeRestore: () => { third ??= acquireLock(root); },
  });
  assert.equal(typeof first, "function", "the first takeover holds the lock");
  assert.equal(second, null, "the slower takeover backs off");
  assert.equal(third, null, "the first holder's lock was never moved aside, so no third holder got in");
  const firstToken = lockOwner(root).token;
  assert.notEqual(firstToken, "stale");
  assert.deepEqual(fs.readdirSync(root), [".sync.lock"]);
  first();
  assert.deepEqual(fs.readdirSync(root), []);
});

test("a lock placed in the moment before a takeover's move is given back, or left aside when a third process took the lock, and a later acquire clears it once stale", () => {
  const { root } = mirror();
  const lock = path.join(root, ".sync.lock");
  fs.mkdirSync(lock);
  const dead = spawnSync(process.execPath, ["-e", ""]).pid;
  fs.writeFileSync(path.join(lock, "owner.json"), JSON.stringify({ pid: dead, host: os.hostname(), token: "stale" }));
  const rename = fs.renameSync;
  let first = null;
  let third = null;
  // The owner judged dead releases its lock and a new holder places one just
  // before the takeover's move, which therefore moves the new holder's lock.
  fs.renameSync = (from, to) => {
    if (first === null && from === lock && path.basename(String(to)).startsWith(".sync.lock.stale-")) {
      fs.rmSync(lock, { recursive: true });
      fs.renameSync = rename;
      first = acquireLock(root);
    }
    return rename(from, to);
  };
  let second;
  try {
    second = acquireLock(root, { beforeRestore: () => { third ??= acquireLock(root); } });
  } finally {
    fs.renameSync = rename;
  }
  assert.equal(typeof first, "function");
  assert.equal(typeof third, "function", "a third process took the slot the move emptied");
  assert.equal(second, null);
  const asides = fs.readdirSync(root).filter(name => name.startsWith(".sync.lock.stale-"));
  assert.equal(asides.length, 1, "the moved lock was left aside, not deleted");
  const aside = path.join(root, asides[0]);
  assert.notEqual(JSON.parse(fs.readFileSync(path.join(aside, "owner.json"), "utf8")).token, lockOwner(root).token);
  first();
  assert.equal(fs.existsSync(lock), true, "the displaced holder leaves the third's lock alone");
  third();
  assert.equal(fs.existsSync(lock), false);
  const release = acquireLock(root);
  assert.equal(fs.existsSync(aside), true, "a fresh aside is kept");
  release();
  const old = new Date(Date.now() - 60 * 60 * 1000);
  fs.utimesSync(aside, old, old);
  acquireLock(root)();
  assert.deepEqual(fs.readdirSync(root), [], "a stale aside is removed by the next acquire");
});

test("a claim a crashed takeover left keeps its lock until the claim is stale", () => {
  const { root } = mirror();
  const lock = path.join(root, ".sync.lock");
  fs.mkdirSync(lock);
  const dead = spawnSync(process.execPath, ["-e", ""]).pid;
  fs.writeFileSync(path.join(lock, "owner.json"), JSON.stringify({ pid: dead, host: os.hostname(), token: "stale" }));
  const claim = path.join(root, `.sync.lock.claim-${sha256("token:stale").slice(0, 32)}`);
  fs.mkdirSync(claim);
  assert.equal(acquireLock(root), null, "a fresh claim means another process is taking it over");
  const old = new Date(Date.now() - 60 * 60 * 1000);
  fs.utimesSync(claim, old, old);
  const release = acquireLock(root);
  assert.equal(typeof release, "function");
  release();
  assert.deepEqual(fs.readdirSync(root), []);
});

test("a half-built lock a crash left is kept while fresh and cleared once stale", () => {
  const { root } = mirror();
  const half = path.join(root, ".sync.lock.new-crashed");
  fs.mkdirSync(half);
  const release = acquireLock(root);
  assert.equal(lockOwner(root).pid, process.pid);
  assert.deepEqual(fs.readdirSync(root).sort(), [".sync.lock", ".sync.lock.new-crashed"], "a fresh half-built lock is kept");
  release();
  const old = new Date(Date.now() - 60 * 60 * 1000);
  fs.utimesSync(half, old, old);
  acquireLock(root)();
  assert.deepEqual(fs.readdirSync(root), []);
  const rename = fs.renameSync;
  let raced = false;
  fs.renameSync = (from, to) => {
    if (!raced && path.basename(String(from)).startsWith(".sync.lock.new-")) {
      raced = true;
      throw Object.assign(new Error("ENOTEMPTY: a lock released since"), { code: "ENOTEMPTY" });
    }
    return rename(from, to);
  };
  let again;
  try {
    again = acquireLock(root);
  } finally {
    fs.renameSync = rename;
  }
  assert.equal(raced, process.platform !== "win32");
  assert.equal(typeof again, "function", "a lock released during a failed placement is retried, not thrown");
  again();
  assert.deepEqual(fs.readdirSync(root), []);
});

test("a takeover whose moved-aside lock another acquire's cleanup removed tries again rather than reporting busy", () => {
  const { root } = mirror();
  const lock = path.join(root, ".sync.lock");
  fs.mkdirSync(lock);
  const dead = spawnSync(process.execPath, ["-e", ""]).pid;
  fs.writeFileSync(path.join(lock, "owner.json"), JSON.stringify({ pid: dead, host: os.hostname(), token: "old" }));
  const rename = fs.renameSync;
  let cleaned = false;
  fs.renameSync = (from, to) => {
    rename(from, to);
    if (!cleaned && path.basename(String(to)).startsWith(".sync.lock.stale-")) {
      cleaned = true;
      fs.rmSync(to, { recursive: true, force: true });
    }
  };
  let release;
  try {
    release = acquireLock(root);
  } finally {
    fs.renameSync = rename;
  }
  assert.equal(cleaned, true);
  assert.equal(typeof release, "function", "the slot is empty, so the lock is taken");
  release();
  assert.deepEqual(fs.readdirSync(root), []);
});

test("ledgerPieces cuts at blank lines, then at the entry limit, and concatenates back", () => {
  const text = `# SDD ledger\n\nTask 1: a\n\n${"x".repeat(MAX_ENTRY_CHARS + 10)}\n`;
  const pieces = ledgerPieces(text);
  assert.equal(pieces.join(""), text);
  assert.deepEqual(pieces.slice(0, 2), ["# SDD ledger\n\n", "Task 1: a\n\n"]);
  assert.equal(pieces.length, 4);
  assert.ok(pieces.every(piece => piece.length <= MAX_ENTRY_CHARS));
});
