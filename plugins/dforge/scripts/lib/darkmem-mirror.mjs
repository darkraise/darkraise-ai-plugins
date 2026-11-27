// The mirror's layout and bookkeeping (darkmem mirror spec §2-§3): which file a
// document uri lives at, the sync state, the lock, and how text is cut into
// work-log entries. Filesystem only; nothing here speaks HTTP.
import { spawnSync } from "node:child_process";
import crypto from "node:crypto";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

export const DOC_PREFIX = "dforge";
// The pre-3.0 prefix, read only to migrate a mirror and darkmem's documents.
export const LEGACY_PREFIX = "superpowers";
export const MAX_ENTRY_CHARS = 65536;
export const MAX_ENTRIES_PER_APPEND = 100;
export const EMPTY_SHA = sha256(Buffer.alloc(0));
const HANDOFF_DIR = "handoff";
const AMENDMENTS_DIR = "amendments";
// Per-plan files that live beside a ledger, by the docs uri directory that
// holds them: dforge/<dir>/<slug>.md is work/sdd/<slug>/<file>.
const PLAN_FILES = { [HANDOFF_DIR]: "handoff.md", [AMENDMENTS_DIR]: "amendments.md" };
export const ARCHIVE_PREFIX = `${DOC_PREFIX}/archive`;
// Top-level directories of the docs root whose files are never documents:
// their uri spaces hold the plans' handoff notes and amendments, and the
// archived documents.
export const RESERVED_DIRS = { handoff: "handoff notes", amendments: "plan amendments", archive: "archived documents" };
const KEY = /^[A-Za-z0-9._-]{1,200}$/;
const HASH = /^[0-9a-f]{64}$/;
const REBUILD = "move it aside to rebuild it from darkmem";

export class StateError extends Error {}
export class UsageError extends Error {}

export function sha256(data) {
  return crypto.createHash("sha256").update(data).digest("hex");
}

// A workstream key doubles as a directory name under work/sdd/, so it must be
// one the uri mapping takes (no leading dot) and every mirror can hold.
export function validKey(key) {
  return storedKey(key) && !key.startsWith(".") && uriProblem(key) === null;
}

// The rule a saved state's keys were written under; a state saved before
// validKey tightened stays loadable.
function storedKey(key) {
  return typeof key === "string" && KEY.test(key) && key !== "." && key !== "..";
}

// uri -> absolute file. `dforge/handoff/<slug>.md` and
// `dforge/amendments/<slug>.md` are reserved for a plan's handoff.md and
// amendments.md, which live beside its ledger; any other
// `dforge/<path>` lives under the docs root. A uri that would climb out
// of the mirror, or name a dotfile, maps nowhere: dotfiles are never synced.
export function uriToLocal(roots, uri) {
  const parts = String(uri).split("/");
  if (parts[0] !== DOC_PREFIX || parts.length < 2) return null;
  if (parts.slice(1).some(part => part === "" || part.startsWith(".") || part.includes("\\"))) return null;
  if (Object.hasOwn(PLAN_FILES, parts[1])) {
    if (parts.length !== 3 || !parts[2].endsWith(".md")) return null;
    const slug = parts[2].slice(0, -3);
    return validKey(slug) ? path.join(roots.workRoot, "sdd", slug, PLAN_FILES[parts[1]]) : null;
  }
  return path.join(roots.docsRoot, ...parts.slice(1));
}

// The families a sync touches. Roots without the field (import's, and the
// scratch roots its verification pulls into) touch both.
export function familiesOf(roots) {
  return roots.families ?? { documents: true, progress: true };
}

// A plan's handoff note and amendments are progress; every other document
// uri is documents.
export function uriFamily(uri) {
  const parts = String(uri).split("/");
  return parts.length === 3 && parts[0] === DOC_PREFIX && Object.hasOwn(PLAN_FILES, parts[1]) ? "progress" : "documents";
}

export function isArchiveUri(uri) {
  return uri === ARCHIVE_PREFIX || String(uri).startsWith(`${ARCHIVE_PREFIX}/`);
}

// UTC as YYYYMMDDTHHMMSSZ: archive stamps and the moves' backup directories.
export function utcStamp(date = new Date()) {
  return date.toISOString().replace(/\.\d+Z$/, "Z").replace(/[-:]/g, "");
}

// Where a deleted document is archived: dforge/<rest> becomes
// dforge/archive/<stamp>/<rest>. The stamp has one-second resolution, so a uri
// archived twice within one second collides: darkmem refuses the second move,
// which archiveDeleted reports as a conflict.
export function archiveUri(uri, stamp) {
  return `${ARCHIVE_PREFIX}/${stamp}/${String(uri).slice(DOC_PREFIX.length + 1)}`;
}

// A missing directory is empty; any other failure to read one is an error,
// because a silently empty listing would read as "nothing to sync".
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

function planDirs(workRoot) {
  const sdd = path.join(workRoot, "sdd");
  return sortedEntries(sdd)
    .filter(entry => entry.isDirectory() && validKey(entry.name))
    .map(entry => ({ slug: entry.name, dir: path.join(sdd, entry.name) }));
}

// Plan directories holding a ledger, handoff note or amendments under a name that cannot
// be a workstream key; callers report them rather than skip them silently.
export function unsupportedPlanDirs(workRoot) {
  const sdd = path.join(workRoot, "sdd");
  return sortedEntries(sdd)
    .filter(entry => entry.isDirectory() && !validKey(entry.name))
    .map(entry => path.join(sdd, entry.name))
    .filter(dir => ["progress.md", ...Object.values(PLAN_FILES)].some(name => fs.existsSync(path.join(dir, name))));
}

// Every document file the mirror syncs, with its uri: files under the docs
// root when documents sync, then each plan's handoff.md and amendments.md
// when progress does. Dotfiles are never synced. A file under the docs root's
// handoff/, amendments/ or archive/ directory gets uri null: those uri spaces
// belong to the handoff notes, the amendments and the archived documents.
export function listDocumentFiles(roots) {
  const families = familiesOf(roots);
  const found = [];
  const walk = (dir, rel) => {
    for (const entry of sortedEntries(dir)) {
      if (entry.name.startsWith(".")) continue;
      const file = path.join(dir, entry.name);
      const next = [...rel, entry.name];
      if (entry.isDirectory()) walk(file, next);
      else if (entry.isFile()) found.push({ file, uri: Object.hasOwn(RESERVED_DIRS, next[0]) ? null : `${DOC_PREFIX}/${next.join("/")}` });
    }
  };
  if (families.documents) walk(roots.docsRoot, []);
  if (families.progress) {
    for (const { slug, dir } of planDirs(roots.workRoot)) {
      for (const [uriDir, name] of Object.entries(PLAN_FILES)) {
        const file = path.join(dir, name);
        if (fs.existsSync(file)) found.push({ file, uri: `${DOC_PREFIX}/${uriDir}/${slug}.md` });
      }
    }
  }
  return found;
}

export function ledgerFiles(workRoot) {
  return planDirs(workRoot)
    .map(({ slug, dir }) => ({ slug, file: path.join(dir, "progress.md") }))
    .filter(({ file }) => fs.existsSync(file));
}

// documents and ledgers are keyed by uri and slug, which may be any valid key
// ("constructor", "__proto__"), so both are prototype-free dictionaries.
export function emptyState() {
  return {
    version: 1, documents: Object.create(null), ledgers: Object.create(null), checkpoint: null, checkpoints: Object.create(null),
    checkpointAt: null, conflicts: [], pendingLinks: [],
  };
}

function dictOf(value, check) {
  if (value === null || typeof value !== "object" || Array.isArray(value)) return null;
  const dict = Object.create(null);
  for (const [key, entry] of Object.entries(value)) {
    if (!check(key, entry)) return null;
    dict[key] = entry;
  }
  return dict;
}

const isHash = value => typeof value === "string" && HASH.test(value);
const isLines = value => Array.isArray(value) && value.every(line => typeof line === "string");
const isLedgerRecord = (slug, record) => storedKey(slug) && record !== null && typeof record === "object"
  && Number.isSafeInteger(record.offset) && record.offset >= 0 && isHash(record.prefix)
  && (record.pending === undefined || typeof record.pending === "boolean")
  && (record.lastSeq === undefined || (Number.isSafeInteger(record.lastSeq) && record.lastSeq >= 0));

// checkpointAt is darkmem's created_at of the last checkpoint this mirror
// synced, per workstream key, so a push's duplicate lookup starts from its own
// workstream's. A state file written before holds one value (a string, or
// null); it stands for every workstream until that one is next written, kept
// under "*", which no workstream key can spell. A key here is only looked up,
// never a path, so it may be any darkmem workstream key, "feature/foo" included.
const EVERY_WORKSTREAM = "*";
const isStamp = value => typeof value === "string" && !Number.isNaN(Date.parse(value));

const stampDict = value => dictOf(value, (key, at) => key !== "" && isStamp(at));

// The loaded checkpointAt, or undefined when it is malformed. The saved
// record (byWorkstream) is used only while the file's own checkpointAt is its
// newest date; any other value means an older dforge wrote the file since, and
// that value stands as it always did.
function checkpointAtRecord(value, byWorkstream) {
  const held = value === null || isStamp(value) ? value : stampDict(value) ?? undefined;
  if (held === undefined || byWorkstream === undefined) return held;
  const record = stampDict(byWorkstream);
  if (record === null) return undefined;
  return value === newestCheckpointAt({ checkpointAt: record }) ? record : held;
}

export function checkpointAtOf(state, workstream) {
  const held = state.checkpointAt;
  if (held === null || typeof held === "string") return held;
  return held[workstream] ?? held[EVERY_WORKSTREAM] ?? null;
}

// The newest checkpoint this mirror synced in any workstream: the baseline of
// a workstream with no entry of its own, and the saved form's string
// checkpointAt.
export function newestCheckpointAt(state) {
  const held = state.checkpointAt;
  if (held === null || typeof held === "string") return held;
  let newest = null;
  for (const at of Object.values(held)) if (newest === null || isoMicros(at) > isoMicros(newest)) newest = at;
  return newest;
}

export function recordCheckpointAt(state, workstream, at) {
  const held = state.checkpointAt;
  const record = held !== null && typeof held === "object" ? held : Object.create(null);
  if (typeof held === "string") record[EVERY_WORKSTREAM] = held;
  record[workstream] = at;
  state.checkpointAt = record;
}

// The checkpoint of `existing` (a resume answer, or null) holding `hash` that
// was filed after the one this mirror last recorded for `workstream`, or null:
// a filing whose answer was lost, recorded rather than filed twice. The entry
// recorded at that time is already acknowledged, so only a newer one counts.
export async function checkpointFiledSince(client, state, workstream, existing, hash) {
  if (!existing) return null;
  const since = (checkpointAtOf(state, workstream) && isoMicros(checkpointAtOf(state, workstream))) ?? -Infinity;
  return (await client.entries(existing.workstream.id, "checkpoint"))
    .find(entry => isoMicros(entry.created_at) > since && sha256(Buffer.from(entry.body, "utf8")) === hash) ?? null;
}

// The mirror's handoff directory, beside the state file at the mirror's root.
const handoffDirOf = stateFile => path.join(path.dirname(stateFile), "work", "handoff");

// The last next-step marker of a handoff: its kind, and its subject (null for
// `-`). Words are read by name; subject= runs to the closing at=.
export function handoffMarker(text) {
  const last = (text.match(/^<!-- next-step: .* -->\r?$/gm) ?? []).at(-1);
  if (!last) return null;
  const kind = /^<!-- next-step: kind=(\S+)/.exec(last)?.[1] ?? null;
  const subject = / subject=(.*) at=-?\d+ -->\r?$/.exec(last)?.[1] ?? "-";
  return { kind, subject: subject === "-" ? null : subject };
}

// The handoff key rule: the state's own key rule, and never "latest".
export function usableHandoffKey(key) {
  return validKey(key) && key !== "latest";
}

// The key a mirror handoff's checkpoint hash is kept under: its file name;
// null for a name the key rule refuses, which is no handoff.
export function handoffKey(name) {
  const key = name.slice(0, -".md".length);
  return usableHandoffKey(key) ? key : null;
}

// The key the migration gives a handoff of the older layout (one whose name is
// no key): the plan or draft its marker names; null for neither.
function subjectKey(text) {
  const subject = handoffMarker(text)?.subject;
  const key = subject && path.posix.basename(subject.replace(/\\/g, "/"), ".md");
  return key && usableHandoffKey(key) ? key : null;
}

// The key of the mirror handoff whose content hashes to `hash`; null for none.
function keyHashing(dir, hash) {
  let names;
  try {
    names = fs.readdirSync(dir).filter(name => name.endsWith(".md")).sort();
  } catch {
    return null;
  }
  for (const name of names) {
    let buffer;
    try {
      buffer = fs.readFileSync(path.join(dir, name));
    } catch {
      continue;
    }
    if (sha256(buffer) === hash) return handoffKey(name) ?? subjectKey(buffer.toString("utf8"));
  }
  return null;
}

// A missing state file is a fresh mirror. An unreadable or malformed one is an
// error, not a fresh start: forgetting a ledger's offset would re-send lines.
// checkpoints holds each mirror handoff's synced hash by key; a state an older
// dforge wrote holds one checkpoint, kept under the key of the handoff it
// hashes to (an older layout's keyed as the migration keys it), or dropped.
export function loadState(file) {
  try {
    fs.statSync(file);
  } catch (error) {
    if (error.code === "ENOENT") return emptyState();
    throw new StateError(`${file} is unreadable (${error.message}); ${REBUILD}`);
  }
  let raw;
  try {
    raw = JSON.parse(fs.readFileSync(file, "utf8"));
  } catch (error) {
    throw new StateError(`${file} is unreadable (${error.message}); ${REBUILD}`);
  }
  const documents = dictOf(raw?.documents, (uri, hash) => isHash(hash));
  const ledgers = dictOf(raw?.ledgers, isLedgerRecord);
  const checkpointAt = checkpointAtRecord(raw?.checkpointAt, raw?.checkpointAtByWorkstream);
  const checkpoints = raw?.checkpoints === undefined
    ? Object.create(null)
    : dictOf(raw.checkpoints, (key, hash) => storedKey(key) && isHash(hash));
  // Each command's own conflicts (darkmem-sync.mjs recordConflicts); absent
  // in a state written before it was kept.
  const conflictsBy = raw?.conflictsBy === undefined ? undefined : dictOf(raw.conflictsBy, (name, lines) => isLines(lines));
  const valid = raw?.version === 1 && documents && ledgers
    && (raw.checkpoint === null || isHash(raw.checkpoint))
    && checkpoints !== null
    && checkpointAt !== undefined
    && isLines(raw.conflicts)
    && conflictsBy !== null
    && (raw.pendingLinks === undefined || (Array.isArray(raw.pendingLinks) && raw.pendingLinks.every(uri => typeof uri === "string")))
    // dr-forge recorded forge; migrateServer moves its documents on and records dforge.
    && (raw.prefix === undefined || raw.prefix === DOC_PREFIX || raw.prefix === "forge")
    && (raw.remote === undefined || (typeof raw.remote?.url === "string" && typeof raw.remote?.project === "string"));
  if (!valid) throw new StateError(`${file} does not hold a valid sync state; ${REBUILD}`);
  if (raw.checkpoint !== null) {
    const key = keyHashing(handoffDirOf(file), raw.checkpoint);
    if (key !== null && checkpoints[key] === undefined) checkpoints[key] = raw.checkpoint;
  }
  const state = {
    version: 1, documents, ledgers, checkpoint: raw.checkpoint, checkpoints, checkpointAt, conflicts: raw.conflicts,
    pendingLinks: raw.pendingLinks ?? [],
  };
  // Set once darkmem was checked for older (superpowers/ or forge/) uris
  // (dforge-home-migrate.mjs).
  if (raw.prefix !== undefined) state.prefix = raw.prefix;
  if (raw.remote !== undefined) state.remote = { url: raw.remote.url, project: raw.remote.project };
  if (conflictsBy !== undefined) state.conflictsBy = conflictsBy;
  return state;
}

// The darkmem a sync state was synced with, recorded by the first sync that
// sees none. A state synced with another server, or with another project that
// shares this mirror directory (a name differing only in case, on a
// case-insensitive file system), is refused: its hashes would read every
// document missing from this darkmem as deleted there. A state the moves home
// have emptied holds nothing synced to misread, so it takes the new darkmem,
// forgetting the old one's prefix migration and conflicts.
export function checkRemote(file, state, url, project) {
  if (state.remote === undefined) {
    state.remote = { url, project };
    return;
  }
  const isEmpty = Object.keys(state.documents).length === 0 && Object.keys(state.ledgers).length === 0
    && (state.checkpoint ?? null) === null && Object.keys(state.checkpoints ?? {}).length === 0 && state.pendingLinks.length === 0;
  if (isEmpty && (state.remote.url !== url || state.remote.project !== project)) {
    state.remote = { url, project };
    delete state.prefix;
    state.conflicts = [];
    delete state.conflictsBy;
    return;
  }
  if (state.remote.url !== url || state.remote.project !== project) {
    throw new StateError(`${file} was synced with project ${state.remote.project} at ${state.remote.url}, not project ${project} at ${url}; map the repository back, or keep unpushed edits by turning darkmem off (dforge-config set darkmemEnabled false), letting the next session start with no plan in progress move the files home, then turning it back on`);
  }
}

// Throws ELOOP when a directory from `root` (exclusive) down to `dir` is a
// symbolic link, so a write or removal there cannot land outside the root. The
// walk stops at the first missing directory: mkdir creates the rest as real ones.
export function refuseLinkedDirs(root, dir) {
  const rel = path.relative(root, dir);
  if (rel === ".." || rel.startsWith(`..${path.sep}`) || path.isAbsolute(rel)) throw new Error(`${dir} is not under ${root}`);
  let at = root;
  for (const part of rel ? rel.split(path.sep) : []) {
    at = path.join(at, part);
    const stat = fs.lstatSync(at, { throwIfNoEntry: false });
    if (!stat) return;
    if (stat.isSymbolicLink()) throw Object.assign(new Error(`${at} is a symbolic link`), { code: "ELOOP", syscall: "lstat", path: at });
  }
}

// The temporary file is a dotfile, so a crash between write and rename never
// leaves something the document listing would sync. It is created exclusively,
// so a link planted at its name is removed rather than written through; with
// `root`, a linked directory between it and the file refuses the write.
export function writeFileAtomic(file, data, root) {
  if (root) refuseLinkedDirs(root, path.dirname(file));
  fs.mkdirSync(path.dirname(file), { recursive: true });
  const temporary = path.join(path.dirname(file), `.${path.basename(file)}.tmp`);
  try {
    fs.writeFileSync(temporary, data, { flag: "wx" });
  } catch (error) {
    if (error.code !== "EEXIST") throw error;
    fs.rmSync(temporary);
    fs.writeFileSync(temporary, data, { flag: "wx" });
  }
  fs.renameSync(temporary, file);
}

// dforge 4.1.0 refuses a checkpointAt that is not null or a string and ignores
// fields it does not know, so the per-workstream record is saved beside a
// string checkpointAt holding its newest date. loadState trusts the record
// only while that string is still its newest date. An older dforge reads
// checkpoint as the synced hash of its one handoff file, which this dforge
// never syncs, so it is saved null.
function savedForm(state) {
  const saved = { ...state, checkpoint: null, checkpoints: state.checkpoints ?? Object.create(null) };
  const held = state.checkpointAt;
  if (held === null || typeof held === "string") return saved;
  return { ...saved, checkpointAt: newestCheckpointAt(state), checkpointAtByWorkstream: held };
}

export function saveState(file, state) {
  writeFileAtomic(file, `${JSON.stringify(savedForm(state), null, 2)}\n`);
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

// Who holds the mirror's lock, for the message a refused sync prints.
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

// A holder refreshes its lock's mtime every heartbeat, so a lock nobody
// refreshed for staleMs is abandoned on any host: on this one its pid may
// have been reused. A lock taken on this host is also abandoned once its
// process is gone. A lock with no readable owner (a crash between mkdir and
// the owner write) is judged by its age alone.
function lockAbandoned({ owner, mtimeMs }, staleMs) {
  const old = mtimeMs === null || Date.now() - mtimeMs >= staleMs;
  if (owner?.host === os.hostname() && Number.isSafeInteger(owner.pid)) return old || !processAlive(owner.pid);
  return old;
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

// One sync per mirror at a time. Returns a release function, or null when a
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
export function acquireLock(dir, { staleMs = 10 * 60 * 1000, heartbeatMs = 60 * 1000, beforeTakeover, beforeRestore } = {}) {
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
    // The heartbeat keeps a long sync's lock from reading as abandoned.
    const heartbeat = setInterval(() => {
      if (readOwner(lock)?.token !== owner.token) return;
      try {
        const now = new Date();
        fs.utimesSync(lock, now, now);
      } catch {
        // Gone or unwritable: the next acquire judges what is left.
      }
    }, heartbeatMs);
    heartbeat.unref();
    // Moved aside before it is deleted: a recursive delete in place would
    // leave an empty lock for a moment, which a restore could land on.
    return () => {
      clearInterval(heartbeat);
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

// Where strict UTF-8 decoding of `buffer` first fails, or null when it does
// not: {offset, partial}, where partial means the only fault is a character
// cut short by the end of the buffer, which is what a file still being written
// looks like. The byte ranges are the WHATWG decoder's, so this agrees with
// decodeUtf8 on every input.
export function utf8Fault(buffer) {
  let i = 0;
  while (i < buffer.length) {
    const lead = buffer[i];
    if (lead < 0x80) {
      i += 1;
      continue;
    }
    let need = 0;
    if (lead >= 0xc2 && lead <= 0xdf) need = 1;
    else if (lead >= 0xe0 && lead <= 0xef) need = 2;
    else if (lead >= 0xf0 && lead <= 0xf4) need = 3;
    else return { offset: i, partial: false };
    const low = lead === 0xe0 ? 0xa0 : lead === 0xf0 ? 0x90 : 0x80;
    const high = lead === 0xed ? 0x9f : lead === 0xf4 ? 0x8f : 0xbf;
    for (let k = 1; k <= need; k += 1) {
      if (i + k >= buffer.length) return { offset: i, partial: true };
      const byte = buffer[i + k];
      if (byte < (k === 1 ? low : 0x80) || byte > (k === 1 ? high : 0xbf)) return { offset: i, partial: false };
    }
    i += need + 1;
  }
  return null;
}

// darkmem's ISO timestamps as microseconds since the epoch, or null. Python's
// isoformat writes six fraction digits and drops a zero fraction; Date.parse
// keeps three, so two entries filed in one millisecond would compare equal.
// Years 1970-2200 keep the result a safe integer.
export function isoMicros(text) {
  const m = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.(\d+))?(Z|[+-](\d{2}):(\d{2}))$/.exec(String(text));
  if (!m) return null;
  const [year, month, day, hour, minute, second] = m.slice(1, 7).map(Number);
  const [fraction = "", zone, zoneHours, zoneMinutes] = m.slice(7);
  if (year < 1970 || year > 2200 || (zone !== "Z" && (Number(zoneHours) > 23 || Number(zoneMinutes) > 59))) return null;
  const ms = Date.UTC(year, month - 1, day, hour, minute, second);
  // Date.UTC rolls an impossible field over (February 30 becomes March 2,
  // minute 60 the next hour); a round trip refuses it.
  const date = new Date(ms);
  if (date.getUTCMonth() !== month - 1 || date.getUTCDate() !== day || date.getUTCHours() !== hour
    || date.getUTCMinutes() !== minute || date.getUTCSeconds() !== second) return null;
  const offsetMinutes = zone === "Z" ? 0 : (zone[0] === "-" ? -1 : 1) * (Number(zoneHours) * 60 + Number(zoneMinutes));
  return (ms - offsetMinutes * 60000) * 1000 + Number(fraction.padEnd(6, "0").slice(0, 6));
}

// Why a uri cannot be a file name on every platform the mirror runs on, or
// null. Windows refuses these characters, a trailing dot or space, and its
// device names whatever their extension; checking everywhere keeps a Linux
// mirror from filing what a Windows mirror cannot hold. Windows reads the
// superscript digits U+00B9, U+00B2 and U+00B3 as digits in COM and LPT names.
export function uriProblem(uri) {
  for (const segment of String(uri).split("/")) {
    if (/[<>:"|?*\p{Cc}]/u.test(segment)) return `the name ${JSON.stringify(segment)} holds a character Windows refuses`;
    if (/[. ]$/.test(segment)) return `the name ${JSON.stringify(segment)} ends in a dot or a space`;
    if (/^(con|prn|aux|nul|com[1-9¹²³]|lpt[1-9¹²³])(\..*)?$/i.test(segment)) return `the name ${JSON.stringify(segment)} is a Windows device name`;
  }
  return null;
}

// Groups of two or more uris that differ only in case, which a
// case-insensitive file system holds as one file.
export function caseGroups(uris) {
  const byFold = new Map();
  for (const uri of new Set(uris)) {
    const fold = uri.toLowerCase();
    byFold.set(fold, [...(byFold.get(fold) ?? []), uri]);
  }
  return [...byFold.values()].filter(group => group.length > 1).map(group => group.sort());
}

// Strict UTF-8, BOM kept, or null: the server stores text, and a lossy decode
// would change the bytes a later pull writes back.
export function decodeUtf8(buffer) {
  try {
    return new TextDecoder("utf-8", { fatal: true, ignoreBOM: true }).decode(buffer);
  } catch {
    return null;
  }
}

// Cut text into pieces of at most `limit` characters, each ending after its
// last newline when it has one, so the pieces concatenate back to the text.
// Counted in UTF-16 units, which never undercounts the server's code points.
// A limit under 2 cannot hold a surrogate pair, and would never advance.
export function splitAtLimit(text, limit = MAX_ENTRY_CHARS) {
  if (!Number.isSafeInteger(limit) || limit < 2) throw new RangeError(`splitAtLimit needs a limit of at least 2, got ${limit}`);
  const pieces = [];
  let rest = text;
  while (rest.length > limit) {
    let cut = rest.lastIndexOf("\n", limit - 1) + 1;
    if (cut === 0) {
      cut = limit;
      const code = rest.charCodeAt(cut - 1);
      if (code >= 0xd800 && code <= 0xdbff) cut -= 1;
    }
    pieces.push(rest.slice(0, cut));
    rest = rest.slice(cut);
  }
  if (rest.length) pieces.push(rest);
  return pieces;
}

// Import's chunking: a new piece starts after every blank line, the blank
// line staying at the end of the piece before it.
export function splitAtBlankLines(text) {
  return text.split(/(?<=\n\r?\n)/).filter(piece => piece.length > 0);
}

// A ledger's import entries. Import and the move's stopped-import check both
// split with this, so the entries a stopped import sent are the first pieces
// of the same ledger's split.
export function ledgerPieces(text) {
  return splitAtBlankLines(text).flatMap(piece => splitAtLimit(piece));
}

// What a darkmem progress board reads from one ledger line without parsing
// markdown (darkmem store options spec §3). Only a `Task N:` line yields any.
export function lineProperties(line) {
  const head = /^Task (\d+): /.exec(line);
  if (!head) return {};
  const properties = { task: Number(head[1]) };
  const rest = line.slice(head[0].length);
  const state = /^complete \(/.test(rest) ? "done"
    : /^BLOCKED/.test(rest) ? "blocked"
    : /^fix round /.test(rest) ? "review"
    : /^implementer \S+ \(assigned/.test(rest) ? "wip"
    : null;
  if (state) properties.state = state;
  const commits = /\bcommits [0-9a-f]{4,40}\.\.([0-9a-f]{4,40})\b/.exec(rest);
  if (commits) properties.commit = commits[1];
  return properties;
}

// One entry per line of `text`, which holds complete lines only. A blank line
// joins the entry before it, or the next one when it leads, so no entry is
// blank unless the text is.
export function ledgerEntries(text) {
  const entries = [];
  let lead = "";
  for (const line of text.split(/(?<=\n)/)) {
    if (/^[ \t]*\r?\n$/.test(line)) {
      if (entries.length) entries.at(-1).body += line;
      else lead += line;
      continue;
    }
    entries.push({ body: lead + line, properties: lineProperties(line) });
    lead = "";
  }
  if (lead) entries.push({ body: lead, properties: {} });
  return entries;
}

// Every worktree's docs directory, as `git worktree list` names the
// checkouts; none when git cannot list them.
function worktreeDocsRoots(worktreeRoot) {
  if (!worktreeRoot) return [];
  const listed = spawnSync("git", ["-C", worktreeRoot, "worktree", "list", "--porcelain"], { encoding: "utf8", timeout: 10000 });
  if (listed.status !== 0) return [];
  return listed.stdout.split(/\r?\n/).filter(line => line.startsWith("worktree "))
    .map(line => path.join(line.slice("worktree ".length), "docs", "dforge"));
}

// The darkmem uri a document's name or path stands for: a name under
// docs/dforge/, docs/forge/ or docs/superpowers/ (as a ledger or a **Spec:**
// line writes it), or an absolute path under the docs root, the worktree's
// docs directory or another worktree's (an older ledger's identity line may
// name one). Computed from the roots, never by searching for a segment.
export function pathToUri(roots, file) {
  const text = String(file).replace(/\\/g, "/");
  const name = /^(?:\.\/)?docs\/(?:dforge|forge|superpowers)\/(.+)$/.exec(text);
  if (name) {
    const uri = `${DOC_PREFIX}/${name[1]}`;
    return uriToLocal(roots, uri) ? uri : null;
  }
  if (!path.isAbsolute(String(file))) return null;
  const under = base => {
    const rel = path.relative(path.resolve(base), path.resolve(String(file)));
    const uri = rel && rel !== ".." && !rel.startsWith(`..${path.sep}`) && !path.isAbsolute(rel) ? `${DOC_PREFIX}/${rel.split(path.sep).join("/")}` : null;
    return uri && uriToLocal(roots, uri) ? uri : null;
  };
  const bases = [roots.docsRoot];
  if (roots.worktreeRoot) bases.push(path.join(roots.worktreeRoot, "docs", "dforge"));
  for (const base of bases) {
    const uri = base && under(base);
    if (uri) return uri;
  }
  // Listed only when the roots do not hold the path: git runs once per miss.
  for (const base of worktreeDocsRoots(roots.worktreeRoot)) {
    const uri = under(base);
    if (uri) return uri;
  }
  return null;
}

// The plan path a ledger's identity line names, or null.
export function ledgerPlanPath(ledgerText) {
  const identity = /^# SDD ledger — plan: (.+)$/.exec(ledgerText.split(/\r?\n/, 1)[0] ?? "");
  return identity ? identity[1].trim() : null;
}

// The workstream properties worklog_resume hands back. `namedPath` is the plan
// or draft the workstream is about: a plan yields plan_uri plus the spec its
// **Spec:** line names; anything else (a draft spec) yields spec_uri. A plan's
// handoff note adds handoff_uri, and its amendments amendments_uri.
export function propertiesFor(roots, slug, namedPath) {
  const properties = {};
  const uri = namedPath ? pathToUri(roots, namedPath) : null;
  if (uri && uri.startsWith(`${DOC_PREFIX}/plans/`)) {
    properties.plan_uri = uri;
    try {
      const spec = /^\*\*Spec:\*\*\s*`?([^`\s]+)`?/m.exec(fs.readFileSync(uriToLocal(roots, uri), "utf8"));
      const specUri = spec ? pathToUri(roots, spec[1]) : null;
      if (specUri) properties.spec_uri = specUri;
    } catch (error) {
      // The plan is not in this mirror; the workstream carries no spec_uri.
      // Any other failure to read it is a real fault, not a missing plan.
      if (error.code !== "ENOENT") throw error;
    }
  } else if (uri) {
    properties.spec_uri = uri;
  }
  if (familiesOf(roots).progress && fs.existsSync(path.join(roots.workRoot, "sdd", slug, "handoff.md"))) {
    properties.handoff_uri = `${DOC_PREFIX}/${HANDOFF_DIR}/${slug}.md`;
  }
  if (familiesOf(roots).progress && fs.existsSync(path.join(roots.workRoot, "sdd", slug, "amendments.md"))) {
    properties.amendments_uri = `${DOC_PREFIX}/${AMENDMENTS_DIR}/${slug}.md`;
  }
  return properties;
}

// What a handoff note is about: the plan or draft its `## State` section names
// on a `- Plan:` or `- Draft:` line, as {slug, path}, or null. With `marker`,
// its last next-step marker decides first: kind=complete or kind=project is
// the project's, whatever `## State` it kept from before, and a plan, draft or
// kept marker's subject names the plan or draft.
export function checkpointTarget(text, { marker = false } = {}) {
  const mark = marker ? handoffMarker(text) : null;
  if (mark?.kind === "complete" || mark?.kind === "project") return { slug: "project", path: null };
  if (mark?.subject && ["plan", "draft", "kept"].includes(mark.kind)) {
    const slug = path.posix.basename(mark.subject.replace(/\\/g, "/"), ".md");
    if (validKey(slug)) return { slug, path: mark.subject };
  }
  const state = /^## State[ \t]*\r?\n([\s\S]*?)(?=^## |(?![\s\S]))/m.exec(text);
  if (!state) return null;
  const named = /^- (?:Plan|Draft): `([^`]+)`/m.exec(state[1]);
  if (!named) return null;
  const slug = path.posix.basename(named[1].replace(/\\/g, "/"), ".md");
  return validKey(slug) ? { slug, path: named[1] } : null;
}

// What `status` prints: local changes the last sync did not see.
export function localChanges(roots, state) {
  const lines = [];
  for (const { file, uri } of listDocumentFiles(roots)) {
    if (!uri) {
      const rel = path.relative(roots.docsRoot, file);
      lines.push(`reserved: ${rel} (the docs root's ${rel.split(path.sep)[0]}/ directory is not synced)`);
      continue;
    }
    const recorded = state.documents[uri];
    if (recorded === undefined) lines.push(`new: ${uri}`);
    else if (sha256(fs.readFileSync(file)) !== recorded) lines.push(`modified: ${uri}`);
  }
  // Synced documents whose mirror file is gone: push archives them.
  if (familiesOf(roots).documents) {
    for (const uri of Object.keys(state.documents).sort()) {
      if (uriFamily(uri) !== "documents" || isArchiveUri(uri)) continue;
      const file = uriToLocal(roots, uri);
      if (file && !fs.existsSync(file)) lines.push(`deleted: ${uri}`);
    }
  }
  if (!familiesOf(roots).progress) return lines;
  for (const { slug, file } of ledgerFiles(roots.workRoot)) {
    const buffer = fs.readFileSync(file);
    const record = state.ledgers[slug];
    if (!record) lines.push(`unpushed: sdd/${slug}/progress.md (${buffer.length} bytes, never synced)`);
    else if (buffer.length < record.offset || sha256(buffer.subarray(0, record.offset)) !== record.prefix) lines.push(`rewritten: sdd/${slug}/progress.md`);
    else if (buffer.length > record.offset) lines.push(`unpushed: sdd/${slug}/progress.md (${buffer.length - record.offset} bytes)`);
  }
  for (const dir of unsupportedPlanDirs(roots.workRoot)) lines.push(`unsupported: ${dir} (not a usable workstream key)`);
  // Each handoff against its key's synced hash; a file whose name is no key
  // has none.
  const dir = path.join(roots.workRoot, "handoff");
  let names = [];
  try {
    names = fs.readdirSync(dir, { withFileTypes: true }).filter(entry => entry.isFile() && entry.name.endsWith(".md")).map(entry => entry.name).sort();
  } catch (error) {
    if (error.code !== "ENOENT") throw error;
  }
  for (const name of names) {
    const buffer = fs.readFileSync(path.join(dir, name));
    const key = handoffKey(name);
    const synced = key === null ? undefined : state.checkpoints?.[key];
    if (sha256(buffer) !== synced) lines.push(`modified: handoff/${name}`);
  }
  return lines;
}
