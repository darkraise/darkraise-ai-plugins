// The mirror's layout and bookkeeping (darkmem mirror spec §2-§3): which file a
// document uri lives at, the sync state, the lock, and how text is cut into
// work-log entries. Filesystem only; nothing here speaks HTTP.
import crypto from "node:crypto";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

export const DOC_PREFIX = "superpowers";
export const MAX_ENTRY_CHARS = 65536;
export const MAX_ENTRIES_PER_APPEND = 100;
export const EMPTY_SHA = sha256(Buffer.alloc(0));
const HANDOFF_DIR = "handoff";
const KEY = /^[A-Za-z0-9._-]{1,200}$/;
const HASH = /^[0-9a-f]{64}$/;
const REBUILD = "move it aside to rebuild it from darkmem";

export class StateError extends Error {}
export class UsageError extends Error {}

export function sha256(data) {
  return crypto.createHash("sha256").update(data).digest("hex");
}

// A workstream key doubles as a directory name under work/sdd/.
export function validKey(key) {
  return typeof key === "string" && KEY.test(key) && key !== "." && key !== "..";
}

// uri -> absolute file. `superpowers/handoff/<slug>.md` is reserved for a
// plan's handoff.md, which lives beside its ledger; any other
// `superpowers/<path>` lives under the docs root. A uri that would climb out
// of the mirror, or name a dotfile, maps nowhere: dotfiles are never synced.
export function uriToLocal(roots, uri) {
  const parts = String(uri).split("/");
  if (parts[0] !== DOC_PREFIX || parts.length < 2) return null;
  if (parts.slice(1).some(part => part === "" || part.startsWith(".") || part.includes("\\"))) return null;
  if (parts[1] === HANDOFF_DIR) {
    if (parts.length !== 3 || !parts[2].endsWith(".md")) return null;
    const slug = parts[2].slice(0, -3);
    return validKey(slug) ? path.join(roots.workRoot, "sdd", slug, "handoff.md") : null;
  }
  return path.join(roots.docsRoot, ...parts.slice(1));
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

// Plan directories holding a ledger or handoff note under a name that cannot
// be a workstream key; callers report them rather than skip them silently.
export function unsupportedPlanDirs(workRoot) {
  const sdd = path.join(workRoot, "sdd");
  return sortedEntries(sdd)
    .filter(entry => entry.isDirectory() && !validKey(entry.name))
    .map(entry => path.join(sdd, entry.name))
    .filter(dir => fs.existsSync(path.join(dir, "progress.md")) || fs.existsSync(path.join(dir, "handoff.md")));
}

// Every document file the mirror syncs, with its uri: files under the docs
// root, then each plan's handoff.md. Dotfiles are never synced. A file under
// the docs root's handoff/ directory gets uri null: that uri space belongs to
// the handoff notes.
export function listDocumentFiles(roots) {
  const found = [];
  const walk = (dir, rel) => {
    for (const entry of sortedEntries(dir)) {
      if (entry.name.startsWith(".")) continue;
      const file = path.join(dir, entry.name);
      const next = [...rel, entry.name];
      if (entry.isDirectory()) walk(file, next);
      else if (entry.isFile()) found.push({ file, uri: next[0] === HANDOFF_DIR ? null : `${DOC_PREFIX}/${next.join("/")}` });
    }
  };
  walk(roots.docsRoot, []);
  for (const { slug, dir } of planDirs(roots.workRoot)) {
    const file = path.join(dir, "handoff.md");
    if (fs.existsSync(file)) found.push({ file, uri: `${DOC_PREFIX}/${HANDOFF_DIR}/${slug}.md` });
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
    version: 1, documents: Object.create(null), ledgers: Object.create(null), checkpoint: null, checkpointAt: null,
    conflicts: [], pendingLinks: [],
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
const isLedgerRecord = (slug, record) => validKey(slug) && record !== null && typeof record === "object"
  && Number.isSafeInteger(record.offset) && record.offset >= 0 && isHash(record.prefix)
  && (record.pending === undefined || typeof record.pending === "boolean")
  && (record.lastSeq === undefined || (Number.isSafeInteger(record.lastSeq) && record.lastSeq >= 0));

// A missing state file is a fresh mirror. An unreadable or malformed one is an
// error, not a fresh start: forgetting a ledger's offset would re-send lines.
export function loadState(file) {
  if (!fs.existsSync(file)) return emptyState();
  let raw;
  try {
    raw = JSON.parse(fs.readFileSync(file, "utf8"));
  } catch (error) {
    throw new StateError(`${file} is unreadable (${error.message}); ${REBUILD}`);
  }
  const documents = dictOf(raw?.documents, (uri, hash) => isHash(hash));
  const ledgers = dictOf(raw?.ledgers, isLedgerRecord);
  const valid = raw?.version === 1 && documents && ledgers
    && (raw.checkpoint === null || isHash(raw.checkpoint))
    && (raw.checkpointAt === null || (typeof raw.checkpointAt === "string" && !Number.isNaN(Date.parse(raw.checkpointAt))))
    && Array.isArray(raw.conflicts) && raw.conflicts.every(line => typeof line === "string")
    && (raw.pendingLinks === undefined || (Array.isArray(raw.pendingLinks) && raw.pendingLinks.every(uri => typeof uri === "string")));
  if (!valid) throw new StateError(`${file} does not hold a valid sync state; ${REBUILD}`);
  return {
    version: 1, documents, ledgers, checkpoint: raw.checkpoint, checkpointAt: raw.checkpointAt, conflicts: raw.conflicts,
    pendingLinks: raw.pendingLinks ?? [],
  };
}

// The temporary file is a dotfile, so a crash between write and rename never
// leaves something the document listing would sync.
export function writeFileAtomic(file, data) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  const temporary = path.join(path.dirname(file), `.${path.basename(file)}.tmp`);
  fs.writeFileSync(temporary, data);
  fs.renameSync(temporary, file);
}

export function saveState(file, state) {
  writeFileAtomic(file, `${JSON.stringify(state, null, 2)}\n`);
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
    if (!entry.isDirectory() || !/^\.sync\.lock\.(stale|new)-/.test(entry.name)) continue;
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
// live sync holds the lock. Taking over an abandoned lock moves it aside and
// deletes it only if it is still the lock judged abandoned, so two processes
// taking over at once cannot delete each other's fresh lock; a lock moved
// aside by mistake is given back, or left aside when a third process has
// taken the lock meanwhile, and never deleted. The release removes the lock
// only while it still carries this holder's token. beforeTakeover and
// beforeRestore are test seams: the first runs between judging a lock
// abandoned and moving it aside, the second before giving back a lock that was
// moved aside by mistake.
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
      beforeTakeover?.();
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
        // Another process took the lock over first; give its lock back. When a
        // third has taken the lock since, the moved lock stays aside: it may
        // be a live holder's, and it is not this process's to delete.
        beforeRestore?.();
        try {
          fs.renameSync(aside, lock);
        } catch {
          // Left aside; removeOldLeftovers clears it once it is stale.
        }
        return null;
      }
      fs.rmSync(aside, { recursive: true, force: true });
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
export function splitAtLimit(text, limit = MAX_ENTRY_CHARS) {
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

// The darkmem uri a path names: what follows its `superpowers/` segment, so a
// repository path (`docs/superpowers/plans/x.md`) and a mirror path both map.
export function pathToUri(file) {
  const match = String(file).replace(/\\/g, "/").match(/(?:^|\/)superpowers\/(.+)$/);
  return match ? `${DOC_PREFIX}/${match[1]}` : null;
}

// The plan path a ledger's identity line names, or null.
export function ledgerPlanPath(ledgerText) {
  const identity = /^# SDD ledger — plan: (.+)$/.exec(ledgerText.split(/\r?\n/, 1)[0] ?? "");
  return identity ? identity[1].trim() : null;
}

// The workstream properties worklog_resume hands back. `namedPath` is the plan
// or draft the workstream is about: a plan yields plan_uri plus the spec its
// **Spec:** line names; anything else (a draft spec) yields spec_uri. A plan's
// handoff note adds handoff_uri.
export function propertiesFor(roots, slug, namedPath) {
  const properties = {};
  const uri = namedPath ? pathToUri(namedPath) : null;
  if (uri && uri.startsWith(`${DOC_PREFIX}/plans/`)) {
    properties.plan_uri = uri;
    try {
      const spec = /^\*\*Spec:\*\*\s*`?([^`\s]+)`?/m.exec(fs.readFileSync(uriToLocal(roots, uri), "utf8"));
      const specUri = spec ? pathToUri(spec[1]) : null;
      if (specUri) properties.spec_uri = specUri;
    } catch {
      // The plan is not in this mirror; the workstream carries no spec_uri.
    }
  } else if (uri) {
    properties.spec_uri = uri;
  }
  if (fs.existsSync(path.join(roots.workRoot, "sdd", slug, "handoff.md"))) {
    properties.handoff_uri = `${DOC_PREFIX}/${HANDOFF_DIR}/${slug}.md`;
  }
  return properties;
}

// What a handoff note is about: the plan or draft its `## State` section names
// on a `- Plan:` or `- Draft:` line, as {slug, path}, or null.
export function checkpointTarget(text) {
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
      lines.push(`reserved: ${path.relative(roots.docsRoot, file)} (the docs root's handoff/ directory is not synced)`);
      continue;
    }
    const recorded = state.documents[uri];
    if (recorded === undefined) lines.push(`new: ${uri}`);
    else if (sha256(fs.readFileSync(file)) !== recorded) lines.push(`modified: ${uri}`);
  }
  for (const { slug, file } of ledgerFiles(roots.workRoot)) {
    const buffer = fs.readFileSync(file);
    const record = state.ledgers[slug];
    if (!record) lines.push(`unpushed: sdd/${slug}/progress.md (${buffer.length} bytes, never synced)`);
    else if (buffer.length < record.offset || sha256(buffer.subarray(0, record.offset)) !== record.prefix) lines.push(`rewritten: sdd/${slug}/progress.md`);
    else if (buffer.length > record.offset) lines.push(`unpushed: sdd/${slug}/progress.md (${buffer.length - record.offset} bytes)`);
  }
  for (const dir of unsupportedPlanDirs(roots.workRoot)) lines.push(`unsupported: ${dir} (not a usable workstream key)`);
  const latest = path.join(roots.workRoot, "handoff", "latest.md");
  if (fs.existsSync(latest) && sha256(fs.readFileSync(latest)) !== state.checkpoint) lines.push("modified: handoff/latest.md");
  return lines;
}
