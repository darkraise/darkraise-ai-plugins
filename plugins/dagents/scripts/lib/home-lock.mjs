// A lock directory, DIR/.sync.lock, holding its owner's pid, host and token.
// Every writer of a file in ~/.dagents takes it on ~/.dagents/.lock. migrate
// takes the older plugin's home lock with it too, which has the same layout,
// so the names never change.
import crypto from "node:crypto";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

const sha256 = data => crypto.createHash("sha256").update(data).digest("hex");

function sortedEntries(dir) {
  let entries;
  try {
    entries = fs.readdirSync(dir, { withFileTypes: true });
  } catch (error) {
    if (error.code === "ENOENT") return [];
    throw error;
  }
  return entries.sort((a, b) => (a.name < b.name ? -1 : a.name > b.name ? 1 : 0));
}

function processAlive(pid) {
  try {
    process.kill(pid, 0);
    return true;
  } catch (error) {
    return error.code === "EPERM";
  }
}

function readOwner(lock) {
  try {
    return JSON.parse(fs.readFileSync(path.join(lock, "owner.json"), "utf8"));
  } catch {
    return null;
  }
}

// Who holds the lock in DIR, for the message a refused caller prints.
export function lockOwner(dir) {
  return readOwner(path.join(dir, ".sync.lock"));
}

// One reading of a lock, so the judgment that it is abandoned and the identity
// later checked against it describe the same lock: two separate reads let a
// lock created in between be taken for the abandoned one.
function lockSnapshot(lock) {
  let mtimeMs = null;
  try {
    mtimeMs = fs.statSync(lock).mtimeMs;
  } catch {
    // The lock is gone; the snapshot says so.
  }
  return { owner: readOwner(lock), mtimeMs };
}

// A lock is abandoned when the process that took it on this host is gone. A
// lock with no readable owner (a crash between mkdir and the owner write), or
// taken on another host, is abandoned once older than staleMs.
function lockAbandoned({ owner, mtimeMs }, staleMs) {
  if (owner?.host === os.hostname() && Number.isSafeInteger(owner.pid)) return !processAlive(owner.pid);
  return mtimeMs === null || Date.now() - mtimeMs >= staleMs;
}

// What makes a lock this lock rather than one taken since: its owner's token,
// or for a lock with no owner record, its modification time.
function lockIdentity({ owner, mtimeMs }) {
  if (typeof owner?.token === "string") return `token:${owner.token}`;
  return mtimeMs === null ? null : `mtime:${mtimeMs}`;
}

// A lock moved aside and left there, because it could not be given back, or
// one a crash left half built, is removed by a later acquire once it is older
// than staleMs.
function removeOldLeftovers(dir, staleMs) {
  for (const entry of sortedEntries(dir)) {
    if (!entry.isDirectory() || !/^\.sync\.lock\.(stale|new|claim)-/.test(entry.name)) continue;
    const aside = path.join(dir, entry.name);
    try {
      if (Date.now() - fs.statSync(aside).mtimeMs >= staleMs) fs.rmSync(aside, { recursive: true, force: true });
    } catch {
      // Another acquire removed it first.
    }
  }
}

// A lock appears with its owner record already inside: it is built under a
// temporary name and renamed into place. A rename replaces an empty directory
// on POSIX, so a lock that were ever empty could be replaced by a restore;
// one that never is cannot. False when another lock got there first.
function placeLock(dir, lock, owner) {
  if (process.platform === "win32") {
    // A Windows rename never replaces a directory, so an empty lock is safe
    // there, and mkdir avoids renaming a just-written directory, which
    // antivirus and indexer handles make fail intermittently.
    try {
      fs.mkdirSync(lock);
    } catch (error) {
      if (error.code === "EEXIST") return false;
      throw error;
    }
    fs.writeFileSync(path.join(lock, "owner.json"), JSON.stringify(owner));
    return true;
  }
  const building = path.join(dir, `.sync.lock.new-${owner.token}`);
  fs.mkdirSync(building);
  fs.writeFileSync(path.join(building, "owner.json"), JSON.stringify(owner));
  try {
    fs.renameSync(building, lock);
    return true;
  } catch (error) {
    fs.rmSync(building, { recursive: true, force: true });
    // A lock was in the way, or was until a release moved it off since; the
    // caller judges whatever is there now.
    if (error.code === "EEXIST" || error.code === "ENOTEMPTY") return false;
    throw error;
  }
}

// One holder per DIR at a time. Returns a release function, or null when a
// live sync holds the lock. Taking over an abandoned lock first claims it: of
// the processes that judged one lock abandoned, only the one whose mkdir of
// that lock's claim succeeds moves it, and only once it has checked that the
// lock is still that one, so a slower contender never moves aside the lock the
// winner placed since. The lock moved aside is deleted only if it is the one
// judged abandoned; one moved by mistake (its owner, judged dead, released it
// and another process placed a lock in the moment before the move) is given
// back, or left aside when a third process has taken the lock meanwhile, and
// never deleted. The release removes the lock only while it still carries
// this holder's token. beforeTakeover and beforeRestore are test seams: the
// first runs between judging a lock abandoned and claiming it, the second
// before giving back a lock that was moved aside by mistake.
export function acquireLock(dir, { staleMs = 10 * 60 * 1000, beforeTakeover, beforeRestore } = {}) {
  const lock = path.join(dir, ".sync.lock");
  const owner = { pid: process.pid, host: os.hostname(), token: crypto.randomUUID() };
  fs.mkdirSync(dir, { recursive: true });
  removeOldLeftovers(dir, staleMs);
  for (let attempt = 0; attempt < 3; attempt += 1) {
    // An existing lock, even an empty one an older version left, is judged
    // before placing a new one, so the rename never lands on it.
    if (fs.existsSync(lock) || !placeLock(dir, lock, owner)) {
      const seen = lockSnapshot(lock);
      if (!lockAbandoned(seen, staleMs)) return null;
      const identity = lockIdentity(seen);
      // Gone since it was seen: the slot is free, try again.
      if (identity === null) continue;
      beforeTakeover?.();
      const claim = `${lock}.claim-${sha256(identity).slice(0, 32)}`;
      try {
        fs.mkdirSync(claim);
      } catch (error) {
        // Another process is taking this lock over; judge what it leaves.
        if (error.code === "EEXIST") continue;
        throw error;
      }
      try {
        if (lockIdentity(lockSnapshot(lock)) !== identity) continue;
        const aside = `${lock}.stale-${owner.token}`;
        try {
          fs.renameSync(lock, aside);
        } catch {
          continue;
        }
        const moved = lockSnapshot(aside);
        // Another acquire's cleanup removed the old lock once it was moved here
        // (a rename keeps its old mtime), so the slot is empty: try again.
        if (moved.owner === null && moved.mtimeMs === null) continue;
        if (lockIdentity(moved) !== identity) {
          // A lock placed since was moved; give it back. When a third process
          // has taken the lock since, the moved lock stays aside: it may be a
          // live holder's, and it is not this process's to delete.
          beforeRestore?.();
          try {
            fs.renameSync(aside, lock);
          } catch {
            // Left aside; removeOldLeftovers clears it once it is stale.
          }
          return null;
        }
        fs.rmSync(aside, { recursive: true, force: true });
      } finally {
        fs.rmSync(claim, { recursive: true, force: true });
      }
      continue;
    }
    // Moved aside before it is deleted: a recursive delete in place would
    // leave an empty lock for a moment, which a restore could land on.
    return () => {
      if (readOwner(lock)?.token !== owner.token) return;
      const gone = `${lock}.stale-${owner.token}`;
      try {
        fs.renameSync(lock, gone);
      } catch {
        return;
      }
      if (readOwner(gone)?.token === owner.token) {
        fs.rmSync(gone, { recursive: true, force: true });
        return;
      }
      try {
        fs.renameSync(gone, lock);
      } catch {
        // Left aside; removeOldLeftovers clears it once it is stale.
      }
    };
  }
  return null;
}
