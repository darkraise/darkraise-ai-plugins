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
  return { version: 1, documents: Object.create(null), ledgers: Object.create(null), checkpoint: null, checkpointAt: null, conflicts: [] };
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
  && (record.pending === undefined || typeof record.pending === "boolean");

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
    && Array.isArray(raw.conflicts) && raw.conflicts.every(line => typeof line === "string");
  if (!valid) throw new StateError(`${file} does not hold a valid sync state; ${REBUILD}`);
  return { version: 1, documents, ledgers, checkpoint: raw.checkpoint, checkpointAt: raw.checkpointAt, conflicts: raw.conflicts };
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

// A lock is abandoned when the process that took it on this host is gone. A
// lock with no readable owner (a crash between mkdir and the owner write), or
// taken on another host, is abandoned once older than staleMs.
function lockAbandoned(lock, owner, staleMs) {
  if (owner?.host === os.hostname() && Number.isSafeInteger(owner.pid)) return !processAlive(owner.pid);
  try {
    return Date.now() - fs.statSync(lock).mtimeMs >= staleMs;
  } catch {
    return true;
  }
}

// What makes a lock this lock rather than one taken since: its owner's token,
// or for a lock with no owner record, its modification time.
function lockIdentity(lock) {
  const token = readOwner(lock)?.token;
  if (typeof token === "string") return `token:${token}`;
  try {
    return `mtime:${fs.statSync(lock).mtimeMs}`;
  } catch {
    return null;
  }
}

// One sync per mirror at a time. Returns a release function, or null when a
// live sync holds the lock. Taking over an abandoned lock moves it aside and
// deletes it only if it is still the lock judged abandoned, so two processes
// taking over at once cannot delete each other's fresh lock. The release
// removes the lock only while it still carries this holder's token.
// beforeTakeover is a test seam: it runs between judging a lock abandoned and
// moving it aside.
export function acquireLock(dir, { staleMs = 10 * 60 * 1000, beforeTakeover } = {}) {
  const lock = path.join(dir, ".sync.lock");
  const owner = { pid: process.pid, host: os.hostname(), token: crypto.randomUUID() };
  fs.mkdirSync(dir, { recursive: true });
  for (let attempt = 0; attempt < 3; attempt += 1) {
    try {
      fs.mkdirSync(lock);
    } catch (error) {
      if (error.code !== "EEXIST") throw error;
      if (!lockAbandoned(lock, readOwner(lock), staleMs)) return null;
      const identity = lockIdentity(lock);
      beforeTakeover?.();
      const aside = `${lock}.stale-${owner.token}`;
      try {
        fs.renameSync(lock, aside);
      } catch {
        continue;
      }
      if (lockIdentity(aside) !== identity) {
        // Another process took the lock over first; give its lock back.
        try {
          fs.renameSync(aside, lock);
        } catch {
          fs.rmSync(aside, { recursive: true, force: true });
        }
        return null;
      }
      fs.rmSync(aside, { recursive: true, force: true });
      continue;
    }
    fs.writeFileSync(path.join(lock, "owner.json"), JSON.stringify(owner));
    return () => {
      if (readOwner(lock)?.token === owner.token) fs.rmSync(lock, { recursive: true, force: true });
    };
  }
  return null;
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
