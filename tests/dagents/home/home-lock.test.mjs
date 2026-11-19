import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import crypto from "node:crypto";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { acquireLock, lockOwner } from "../../../plugins/dagents/scripts/lib/home-lock.mjs";

const created = [];
process.on("exit", () => {
  for (const dir of created) fs.rmSync(dir, { recursive: true, force: true });
});

function lockDir() {
  const root = fs.realpathSync.native(fs.mkdtempSync(path.join(os.tmpdir(), "dagents-lock-")));
  created.push(root);
  return { root };
}

const sha256 = data => crypto.createHash("sha256").update(data).digest("hex");

test("the lock admits one holder, waits on a live one however old, and takes over a dead one", () => {
  const { root } = lockDir();
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
  const { root } = lockDir();
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
  const { root } = lockDir();
  const lock = path.join(root, ".sync.lock");
  fs.mkdirSync(lock);
  assert.equal(acquireLock(root), null);
  const old = new Date(Date.now() - 20 * 60 * 1000);
  fs.utimesSync(lock, old, old);
  const release = acquireLock(root);
  assert.equal(typeof release, "function");
  release();
});

test("a takeover never moves aside the lock another takeover of the same abandoned lock placed since", () => {
  const { root } = lockDir();
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
  const { root } = lockDir();
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
  const { root } = lockDir();
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
  const { root } = lockDir();
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
  const { root } = lockDir();
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
