// The moves from dagents's older darkmem names to its own: the homes
// ~/.dr-superpowers/ and ~/.dr-forge/ to ~/.dagents/, a mirror's superpowers/
// or forge/ folder and sync state uris to dagents/, and darkmem's superpowers/
// and forge/ documents to dagents/. For one repository, dforge 4.x's home
// record, mirror and settings, and its darkmem dforge/ documents and bare-key
// workstreams, are copied or moved to dagents' names (migrateDforge). The only
// module besides the document-name translation that reads the old names.
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import SCHEMA, { isValidValue } from "../../config/schema.mjs";
import { HttpError, TransportError, WORKSTREAM_PREFIX, createClient } from "./darkmem-client.mjs";
import { DOC_PREFIX, LEGACY_PREFIX, MAX_ENTRIES_PER_APPEND, StateError, acquireLock, loadState, saveState } from "./darkmem-mirror.mjs";
import { claudeSettingsPath, withHomeLock } from "./dagents-config.mjs";
import { primaryRoot, runKey } from "./darkmem-config.mjs";

// dr-superpowers wrote superpowers/, dr-forge forge/.
export const OLD_PREFIXES = [LEGACY_PREFIX, "forge"];
const oldPrefixOf = uri => OLD_PREFIXES.find(prefix => String(uri).startsWith(`${prefix}/`));
const renamed = uri => {
  const prefix = oldPrefixOf(uri);
  return prefix ? `${DOC_PREFIX}/${uri.slice(prefix.length + 1)}` : uri;
};
const heldFolders = mirror => [...OLD_PREFIXES, DOC_PREFIX].filter(prefix => fs.existsSync(path.join(mirror, prefix)));
// What a mirror is renamed from, for the line that says so: its old folder,
// or else the old prefixes its state's uris hold. Read before migrateMirror.
function oldNamesIn(mirror, state) {
  const folder = heldFolders(mirror).find(prefix => prefix !== DOC_PREFIX);
  if (folder) return folder;
  const uris = [...Object.keys(state.documents), ...state.pendingLinks];
  return OLD_PREFIXES.filter(prefix => uris.some(uri => oldPrefixOf(uri) === prefix)).join("/ and ");
}

// A mirror's local half: the docs folder and every uri its state records.
// Returns whether anything changed; a mirror holding two docs folders throws.
export function migrateMirror(mirror, state) {
  let changed = false;
  const held = heldFolders(mirror);
  if (held.length > 1) throw new StateError(`${mirror} holds ${held.map(prefix => `${prefix}/`).join(" and ")}; move all but one aside`);
  if (held.length === 1 && held[0] !== DOC_PREFIX) {
    fs.renameSync(path.join(mirror, held[0]), path.join(mirror, DOC_PREFIX));
    changed = true;
  }
  const documents = Object.create(null);
  for (const [uri, hash] of Object.entries(state.documents)) {
    documents[renamed(uri)] = hash;
    if (oldPrefixOf(uri)) changed = true;
  }
  state.documents = documents;
  const links = state.pendingLinks.map(renamed);
  if (links.some((uri, index) => uri !== state.pendingLinks[index])) changed = true;
  state.pendingLinks = links;
  return changed;
}

// A mirror in an older layout: an old folder, or an old uri its state records.
export function legacyMirror(mirror) {
  if (OLD_PREFIXES.some(prefix => fs.existsSync(path.join(mirror, prefix)))) return true;
  let raw;
  try {
    raw = JSON.parse(fs.readFileSync(path.join(mirror, ".sync-state.json"), "utf8"));
  } catch (error) {
    // An unreadable state file goes on to loadState, which refuses it by name.
    return error?.code !== "ENOENT";
  }
  const uris = [...Object.keys(raw?.documents ?? {}), ...(Array.isArray(raw?.pendingLinks) ? raw.pendingLinks : [])];
  return uris.some(uri => oldPrefixOf(uri) !== undefined);
}

const lockedLine = mirror => `${mirror} is still in an older layout and another darkmem-sync holds its lock; try again once it is done`;

// The local half under the mirror's lock, for a caller that holds none.
// Answers { line, blocked } saying what happened, or null when nothing needed
// doing; blocked: a held lock left the mirror in an older layout.
export function migrateMirrorLocked(mirror) {
  if (!legacyMirror(mirror)) return null;
  const release = acquireLock(mirror);
  if (!release) return { line: lockedLine(mirror), blocked: true };
  try {
    const statePath = path.join(mirror, ".sync-state.json");
    const state = loadState(statePath);
    const from = oldNamesIn(mirror, state);
    if (!migrateMirror(mirror, state)) return null;
    saveState(statePath, state);
    return { line: `renamed ${mirror}'s ${from}/ to ${DOC_PREFIX}/; darkmem's documents follow at its next sync`, blocked: false };
  } finally {
    release();
  }
}

// darkmem's half, once per mirror: every superpowers/ and forge/ document
// moves to the same name under dagents/, under its own hash. A name darkmem
// already holds under dagents/ is a failure, never overwritten. Answers the
// failure lines; state.prefix is set only when there are none.
export async function migrateServer({ cfg, client, state, persist }) {
  if (state.prefix === DOC_PREFIX) return [];
  const failures = [];
  const held = new Map((await client.manifest(cfg.project, `${DOC_PREFIX}/`)).map(item => [item.uri, item.content_hash]));
  for (const prefix of OLD_PREFIXES) {
    const old = (await client.manifest(cfg.project, prefix)).filter(item => item.uri.startsWith(`${prefix}/`));
    for (const item of old) {
      const uri = renamed(item.uri);
      if (held.has(uri)) {
        failures.push(`${item.uri}: darkmem also holds ${uri}${held.get(uri) === item.content_hash ? " with the same content; delete one" : " with other content; keep one"}`);
        continue;
      }
      try {
        await client.moveDocument(item.id, { uri, expectedHash: item.content_hash });
        held.set(uri, item.content_hash);
      } catch (error) {
        if (!(error instanceof HttpError) || error.status === 401) throw error;
        failures.push(`${item.uri}: darkmem refused the move to ${uri}: ${error.detail}`);
      }
    }
  }
  if (!failures.length) {
    state.prefix = DOC_PREFIX;
    persist();
  }
  return failures;
}

function readJson(file) {
  try {
    return JSON.parse(fs.readFileSync(file, "utf8"));
  } catch (error) {
    if (error.code === "ENOENT") return undefined;
    throw new Error(`${file} could not be read: ${error.message}`);
  }
}

const notObject = value => value === null || typeof value !== "object" || Array.isArray(value);
// What readOrRefuse answers for a file it refused.
const UNREADABLE = Symbol("unreadable");

function writeJson(file, data) {
  const temporary = path.join(path.dirname(file), `.${path.basename(file)}.${process.pid}.tmp`);
  fs.writeFileSync(temporary, `${JSON.stringify(data, null, 2)}\n`);
  fs.renameSync(temporary, file);
}

function sameFile(a, b) {
  try {
    return fs.statSync(a).isFile() && fs.statSync(b).isFile() && fs.readFileSync(a).equals(fs.readFileSync(b));
  } catch {
    return false;
  }
}

// The home's half, run by scripts/dagents-migrate. ~/.dr-forge/ becomes
// ~/.dagents/: renamed whole when ~/.dagents/ is absent, otherwise entry by
// entry, its config.json merged key by key. ~/.dr-superpowers/ then gives
// ~/.dagents/config.json its darkmem mapping when that file has none, and each
// mirror the new home lacks. stores.json follows every mirror that moved, and
// every mirror gets its local half. The old files stay wherever something was
// refused. With dryRun nothing is written and each line says what would
// happen. Answers { lines, refused }.
export function migrateHome(env = process.env, { dryRun = false } = {}) {
  const home = env.HOME || os.homedir();
  const forgeHome = path.join(home, ".dr-forge");
  const oldHome = path.join(home, ".dr-superpowers");
  const newHome = path.join(home, ".dagents");
  const lines = [];
  let refused = 0;
  const refuse = line => {
    lines.push(`refused: ${line}`);
    refused += 1;
  };
  const did = (done, would) => lines.push(dryRun ? would : done);
  // A change to config.json or stores.json reads and writes under the lock
  // every other writer of those files takes.
  const locked = change => (dryRun ? change() : withHomeLock(env, change));
  // [from, to, whole]: whole marks a home's mirror folder moving, not one mirror.
  const moves = [];
  // In a dry run nothing has moved, so a path in the new home is read where
  // it still is: under the old entry an earlier line would move there.
  const pending = [];
  let merged;
  const badConfigs = new Set();
  // Each file is refused once however many blocks read it; the block that
  // reads it is skipped, as a file that is not an object is.
  const readOrRefuse = file => {
    try {
      return readJson(file);
    } catch (error) {
      if (!badConfigs.has(file)) refuse(`${error.message}; fix or delete it, then run dagents-migrate again`);
      badConfigs.add(file);
      return UNREADABLE;
    }
  };
  const view = (...parts) => {
    const target = path.join(newHome, ...parts);
    const hit = pending.find(([to]) => target === to || target.startsWith(`${to}${path.sep}`));
    return hit ? `${hit[1]}${target.slice(hit[0].length)}` : target;
  };
  const whole = fs.existsSync(forgeHome) && !fs.existsSync(newHome);

  if (whole) {
    if (dryRun) pending.push([newHome, forgeHome]);
    else fs.renameSync(forgeHome, newHome);
    did(`moved ${forgeHome} to ${newHome}`, `would move ${forgeHome} to ${newHome}`);
    moves.push([path.join(forgeHome, "mirror"), path.join(newHome, "mirror"), true]);
  } else if (fs.existsSync(forgeHome)) {
    for (const entry of fs.readdirSync(forgeHome, { withFileTypes: true })) {
      const from = path.join(forgeHome, entry.name);
      const to = path.join(newHome, entry.name);
      if (entry.name === "config.json" && entry.isFile() && fs.existsSync(to)) {
        locked(() => {
          const old = readOrRefuse(from);
          const next = readOrRefuse(to);
          if (old === UNREADABLE || next === UNREADABLE) return;
          const bad = [[from, old], [to, next]].find(([, value]) => notObject(value));
          if (bad) {
            badConfigs.add(bad[0]);
            refuse(`${bad[0]} does not hold a JSON object; fix or delete it, then run dagents-migrate again`);
            return;
          }
          const clash = Object.keys(old).filter(key => key in next && JSON.stringify(old[key]) !== JSON.stringify(next[key]));
          if (clash.length) {
            refuse(`${from} and ${to} set ${clash.join(", ")} differently; keep one value in ${to} and delete it from ${from}, then run dagents-migrate again`);
            return;
          }
          const copied = Object.keys(old).filter(key => !(key in next));
          merged = { ...next, ...old };
          if (!dryRun) {
            writeJson(to, merged);
            fs.rmSync(from);
          }
          did(`merged ${from} into ${to} (${copied.length ? copied.join(", ") : "no new keys"})`,
            `would merge ${from} into ${to} (${copied.length ? copied.join(", ") : "no new keys"})`);
        });
        continue;
      }
      if (entry.name === "mirror" && entry.isDirectory() && fs.existsSync(to)) {
        for (const child of fs.readdirSync(from, { withFileTypes: true })) {
          const source = path.join(from, child.name);
          const target = path.join(to, child.name);
          if (!child.isDirectory()) {
            if (!fs.existsSync(target)) {
              if (dryRun) pending.push([target, source]);
              else fs.renameSync(source, target);
              did(`moved ${source} to ${target}`, `would move ${source} to ${target}`);
            } else if (sameFile(source, target)) {
              if (!dryRun) fs.rmSync(source);
              did(`dropped ${source}, the same as ${target}`, `would drop ${source}, the same as ${target}`);
            } else {
              refuse(`${source} differs from ${target}; keep one by hand, then run dagents-migrate again`);
            }
            continue;
          }
          if (fs.existsSync(target)) {
            refuse(`${target} exists, so ${source} was not moved`);
            continue;
          }
          if (dryRun) pending.push([target, source]);
          else fs.renameSync(source, target);
          did(`moved ${source} to ${target}`, `would move ${source} to ${target}`);
          moves.push([source, target]);
        }
        continue;
      }
      if (!fs.existsSync(to)) {
        if (dryRun) pending.push([to, from]);
        else fs.renameSync(from, to);
        did(`moved ${from} to ${to}`, `would move ${from} to ${to}`);
        if (entry.name === "mirror") moves.push([from, to, true]);
        continue;
      }
      if (sameFile(from, to)) {
        if (!dryRun) fs.rmSync(from);
        did(`dropped ${from}, the same as ${to}`, `would drop ${from}, the same as ${to}`);
        continue;
      }
      refuse(`${from} differs from ${to}; keep one by hand, then run dagents-migrate again`);
    }
    if (!dryRun) {
      for (const dir of [path.join(forgeHome, "mirror"), forgeHome]) {
        try {
          fs.rmdirSync(dir);
        } catch (error) {
          // Still holds something refused (ENOTEMPTY, or EEXIST on some
          // systems), already gone, or is a mirror file whose merge was refused.
          if (!["ENOTEMPTY", "EEXIST", "ENOENT", "ENOTDIR"].includes(error.code)) refuse(`${dir} could not be removed: ${error.message}`);
        }
      }
    }
  }

  const oldConfig = readOrRefuse(path.join(oldHome, "config.json"));
  if (oldConfig !== UNREADABLE && oldConfig?.darkmem && typeof oldConfig.darkmem === "object") {
    const file = path.join(newHome, "config.json");
    const source = view("config.json");
    if (!dryRun) fs.mkdirSync(newHome, { recursive: true });
    locked(() => {
      const current = (dryRun && merged) ? { ...merged } : readOrRefuse(source);
      const config = current ?? {};
      if (current === UNREADABLE || (current !== undefined && notObject(current))) {
        if (!badConfigs.has(source)) refuse(`${source} does not hold a JSON object; fix or delete it, then run dagents-migrate again`);
      } else if (config.darkmem === undefined) {
        config.darkmem = oldConfig.darkmem;
        if (!dryRun) writeJson(file, config);
        did(`copied the darkmem mapping from ${path.join(oldHome, "config.json")} into ${file}`,
          `would copy the darkmem mapping from ${path.join(oldHome, "config.json")} into ${file}`);
        if (config.darkmemEnabled === undefined) lines.push("darkmem is off until you turn it on: bash <plugin-root>/scripts/dagents-config set darkmemEnabled true");
      } else {
        lines.push(`${file} already has a darkmem section; ${path.join(oldHome, "config.json")} was not copied`);
      }
    });
  }
  const oldMirrors = path.join(oldHome, "mirror");
  const newMirrors = path.join(newHome, "mirror");
  for (const entry of fs.existsSync(oldMirrors) ? fs.readdirSync(oldMirrors, { withFileTypes: true }) : []) {
    if (!entry.isDirectory()) continue;
    const source = path.join(oldMirrors, entry.name);
    const target = path.join(newMirrors, entry.name);
    if (fs.existsSync(view("mirror", entry.name))) {
      refuse(`${target} exists, so ${source} was not moved`);
      continue;
    }
    if (!dryRun) {
      fs.mkdirSync(newMirrors, { recursive: true });
      fs.renameSync(source, target);
    }
    did(`moved ${source} to ${target}`, `would move ${source} to ${target}`);
    moves.push([source, target]);
  }

  const stores = view("stores.json");
  // A home with no stores.json has nothing to point, and no lock to take.
  const pointStores = () => {
    const data = readOrRefuse(stores);
    if (data !== UNREADABLE && data && typeof data === "object" && !Array.isArray(data)) {
      let pointed = 0;
      for (const record of Object.values(data)) {
        if (!record || typeof record.mirror !== "string") continue;
        const move = moves.find(([from]) => record.mirror === from || record.mirror.startsWith(`${from}${path.sep}`));
        if (!move) continue;
        record.mirror = `${move[1]}${record.mirror.slice(move[0].length)}`;
        pointed += 1;
      }
      if (pointed) {
        if (!dryRun) writeJson(path.join(newHome, "stores.json"), data);
        did(`pointed ${pointed} ${path.join(newHome, "stores.json")} record(s) at the moved mirrors`,
          `would point ${pointed} ${path.join(newHome, "stores.json")} record(s) at the moved mirrors`);
      }
    }
  };
  if (fs.existsSync(stores)) locked(pointStores);

  const mirrors = new Set();
  for (const entry of fs.existsSync(view("mirror")) ? fs.readdirSync(view("mirror"), { withFileTypes: true }) : []) {
    if (entry.isDirectory()) mirrors.add(view("mirror", entry.name));
  }
  if (dryRun) for (const [from, , whole] of moves) if (!whole) mirrors.add(from);
  for (const mirror of mirrors) {
    if (dryRun) {
      // The real run's checks in its order: the lock, the state, the folders.
      // A lock the real run would find abandoned and take over is still
      // foretold as held.
      if (!legacyMirror(mirror)) continue;
      if (fs.existsSync(path.join(mirror, ".sync.lock"))) {
        refuse(lockedLine(mirror));
        continue;
      }
      let state;
      try {
        state = loadState(path.join(mirror, ".sync-state.json"));
      } catch (error) {
        if (!(error instanceof StateError)) throw error;
        refuse(error.message);
        continue;
      }
      const held = heldFolders(mirror);
      if (held.length > 1) refuse(`${mirror} holds ${held.map(prefix => `${prefix}/`).join(" and ")}; move all but one aside`);
      else lines.push(`would rename ${mirror}'s ${oldNamesIn(mirror, state)}/ to ${DOC_PREFIX}/; darkmem's documents follow at its next sync`);
      continue;
    }
    try {
      const result = migrateMirrorLocked(mirror);
      if (result?.blocked) refused += 1;
      if (result) lines.push(result.blocked ? `refused: ${result.line}` : result.line);
    } catch (error) {
      if (!(error instanceof StateError)) throw error;
      refuse(error.message);
    }
  }
  return { lines, refused };
}

// dforge 4.x's half, for one repository. dforge keeps ~/.dforge/ for every
// other repository, so only this one's record leaves ~/.dforge/stores.json;
// its settings and mapping are copied, never over a value dagents has. The
// darkmem copy runs first and every copy is read back: on any problem the
// home is left as it was, and nothing in darkmem is ever deleted.
const DFORGE_PREFIX = "dforge";
const DFORGE_LOCK_WAIT_MS = 10000;
const PROJECT_NAME = /^[A-Za-z0-9][A-Za-z0-9._-]{0,199}$/;
// Shared on purpose with dforge and the older plugins, so never renamed.
const SHARED_VARIABLE = /^DR_(TEST_BASH|TEST_ALL)$|^DR_(FORGE|SUPERPOWERS)_/;

function realOrResolved(file) {
  try {
    return fs.realpathSync.native(file);
  } catch {
    return path.resolve(file);
  }
}

function samePath(a, b) {
  const x = realOrResolved(a);
  const y = realOrResolved(b);
  return process.platform === "win32" ? x.toLowerCase() === y.toLowerCase() : x === y;
}

const keyFor = (data, root) => Object.keys(data ?? {}).find(key => samePath(key, root));
const dagentsUri = uri => `${DOC_PREFIX}/${uri.slice(DFORGE_PREFIX.length + 1)}`;
const fromDforge = value => (typeof value === "string" && value.startsWith(`${DFORGE_PREFIX}/`) ? dagentsUri(value) : value);
const sameUrl = (a, b) => String(a).replace(/\/+$/, "") === String(b).replace(/\/+$/, "");

export function renamedVariable(name) {
  if (name.startsWith("DFORGE_")) return `DAGENTS_${name.slice("DFORGE_".length)}`;
  if (/^DR_[A-Z0-9_]+$/.test(name) && !SHARED_VARIABLE.test(name)) return `DAGENTS_${name.slice("DR_".length)}`;
  return null;
}

// dforge's own home lock, the one its config and stores writers take.
function withDforgeLock(home, change) {
  const dir = path.join(home, ".dforge", ".lock");
  const deadline = Date.now() + DFORGE_LOCK_WAIT_MS;
  let release;
  while (!(release = acquireLock(dir))) {
    if (Date.now() >= deadline) throw new Error(`another dforge process has held ${dir} for ${DFORGE_LOCK_WAIT_MS / 1000} s; if none is running, remove it`);
    Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, 25);
  }
  try {
    return change();
  } finally {
    release();
  }
}

// A URL's user and password never reach a printed line.
const withoutUserinfo = url => String(url).replace(/^([a-z][a-z0-9+.-]*:\/\/)[^@/?#]*@/i, "$1");

function variableLines(env) {
  const found = [];
  for (const name of Object.keys(env).sort()) if (renamedVariable(name)) found.push([name, "the environment"]);
  const file = claudeSettingsPath(env);
  let unreadable = [];
  try {
    const settings = JSON.parse(fs.readFileSync(file, "utf8"));
    if (settings && !notObject(settings.env)) {
      for (const name of Object.keys(settings.env).sort()) if (renamedVariable(name)) found.push([name, file]);
    }
  } catch (error) {
    if (error?.code !== "ENOENT") unreadable = [`${file} could not be read, so a DFORGE_* or DR_* name its env sets is not listed`];
  }
  return [...found.map(([name, where]) => `${name} is set in ${where}; dagents reads ${renamedVariable(name)}, so set that name for it`), ...unreadable];
}

const sameEntry = (a, b) => a.kind === b.kind && a.body === b.body;

// darkmem's half: every dforge/ document to the same name under dagents/, and
// every bare-key workstream (dforge 4.x's) to dagents/<key>, each read back.
// A copy already there is kept; a dagents copy a later dforge append left
// short gains the missing entries. Answers { problems, documents, keys }.
async function copyDarkmem(client, project) {
  const problems = [];
  const held = new Map((await client.manifest(project, `${DOC_PREFIX}/`)).map(item => [item.uri, item]));
  const originals = (await client.manifest(project, `${DFORGE_PREFIX}/`)).filter(item => item.uri.startsWith(`${DFORGE_PREFIX}/`));
  for (const item of originals) {
    const uri = dagentsUri(item.uri);
    const existing = held.get(uri);
    if (existing) {
      if (existing.content_hash !== item.content_hash) problems.push(`darkmem holds ${uri} with other content than ${item.uri}; keep one, then run dagents-migrate again`);
      continue;
    }
    const source = await client.getDocument(project, item.uri);
    if (typeof source?.content !== "string" || source.content_hash !== item.content_hash) {
      problems.push(`${item.uri} changed while it was read; run dagents-migrate again`);
      continue;
    }
    await client.putDocument({ project, uri, content: source.content });
    const copy = await client.getDocument(project, uri);
    if (copy?.content !== source.content || copy?.content_hash !== item.content_hash) problems.push(`${uri} reads back other than ${item.uri}`);
  }
  // Each state asked for by name: a server listing only open ones by default
  // would otherwise skip every finished plan's ledger.
  const listed = [...await client.workstreams(project, "open"), ...await client.workstreams(project, "closed")];
  const all = [...new Map(listed.map(ws => [ws.id, ws])).values()];
  const byKey = new Map(all.map(ws => [ws.key, ws]));
  const keys = [];
  for (const key of all.filter(ws => typeof ws.key === "string" && !ws.key.includes("/")).map(ws => ws.key).sort()) {
    const ws = byKey.get(key);
    const target = `${WORKSTREAM_PREFIX}${key}`;
    const source = await client.entries(ws.id);
    let copy = byKey.get(target);
    const have = copy ? await client.entries(copy.id) : [];
    // One must begin with the other: either the copy is whole, or dforge
    // appended after an earlier run and only the tail is missing.
    if (!source.slice(0, have.length).every((entry, index) => sameEntry(entry, have[index]))) {
      problems.push(`darkmem's ${target} holds entries ${key} does not; keep one, then run dagents-migrate again`);
      continue;
    }
    const missing = source.slice(have.length);
    for (let start = 0; start < missing.length; start += MAX_ENTRIES_PER_APPEND) {
      const entries = missing.slice(start, start + MAX_ENTRIES_PER_APPEND).map(entry => ({ kind: entry.kind, body: entry.body, properties: entry.properties ?? {} }));
      const properties = start === 0 && !notObject(ws.properties) && Object.keys(ws.properties).length ? ws.properties : undefined;
      const answer = await client.append({ project, workstream: target, entries, properties });
      copy = answer.workstream;
    }
    if (!copy && missing.length) {
      problems.push(`${target}: darkmem answered the append without the workstream, so ${key} could not be read back`);
      continue;
    }
    // An empty workstream has nothing to copy and is not offered for deletion.
    if (!copy) continue;
    keys.push(key);
    const patch = {};
    if (ws.state === "closed" && copy.state !== "closed") patch.state = "closed";
    if (ws.retain === true && copy.retain !== true) patch.retain = true;
    if (Object.keys(patch).length) await client.updateWorkstream(copy.id, patch);
    const back = await client.entries(copy.id);
    if (!source.every((entry, index) => back[index] && sameEntry(entry, back[index]))) problems.push(`${target} reads back other than ${key}`);
  }
  return { problems, documents: originals.length, keys };
}

// A copy of a dforge mirror in dagents' layout at `target`: its dforge/
// folder renamed and its state's prefix and uris rewritten, written aside
// first so a half-made copy is never found at `target`.
function copyMirror(source, target) {
  const aside = path.join(path.dirname(target), `.${path.basename(target)}.migrating-${process.pid}`);
  fs.rmSync(aside, { recursive: true, force: true });
  fs.mkdirSync(path.dirname(target), { recursive: true });
  try {
    fs.cpSync(source, aside, { recursive: true, filter: file => !path.basename(file).startsWith(".sync.lock") });
    const folders = [DFORGE_PREFIX, DOC_PREFIX].filter(prefix => fs.existsSync(path.join(aside, prefix)));
    if (folders.length > 1) throw new StateError(`${source} holds ${DFORGE_PREFIX}/ and ${DOC_PREFIX}/; move one aside`);
    if (folders[0] === DFORGE_PREFIX) fs.renameSync(path.join(aside, DFORGE_PREFIX), path.join(aside, DOC_PREFIX));
    const statePath = path.join(aside, ".sync-state.json");
    if (fs.existsSync(statePath)) {
      let raw;
      try {
        raw = JSON.parse(fs.readFileSync(statePath, "utf8"));
      } catch (error) {
        throw new StateError(`${path.join(source, ".sync-state.json")} is unreadable (${error.message}); fix or delete it, then run dagents-migrate again`);
      }
      if (notObject(raw)) throw new StateError(`${path.join(source, ".sync-state.json")} does not hold a sync state`);
      if (!notObject(raw.documents)) raw.documents = Object.fromEntries(Object.entries(raw.documents).map(([uri, hash]) => [fromDforge(uri), hash]));
      if (Array.isArray(raw.pendingLinks)) raw.pendingLinks = raw.pendingLinks.map(fromDforge);
      if (raw.prefix === DFORGE_PREFIX) raw.prefix = DOC_PREFIX;
      writeJson(statePath, raw);
      loadState(statePath);
    }
    fs.renameSync(aside, target);
  } catch (error) {
    fs.rmSync(aside, { recursive: true, force: true });
    throw error;
  }
}

export async function migrateDforge(env = process.env, { dryRun = false, root, layout = false, connect = createClient } = {}) {
  const home = env.HOME || os.homedir();
  const dforgeHome = path.join(home, ".dforge");
  const newHome = path.join(home, ".dagents");
  const lines = [];
  let refused = 0;
  const refuse = line => {
    lines.push(`refused: ${line}`);
    refused += 1;
  };
  const did = (done, would) => lines.push(dryRun ? would : done);
  const answer = () => ({ lines, refused });
  if (!root) return answer();
  const readObject = file => {
    let data;
    try {
      data = readJson(file);
    } catch (error) {
      refuse(`${error.message}; fix or delete it, then run dagents-migrate again`);
      return UNREADABLE;
    }
    if (data !== undefined && notObject(data)) {
      refuse(`${file} does not hold a JSON object; fix or delete it, then run dagents-migrate again`);
      return UNREADABLE;
    }
    return data;
  };
  const configFile = path.join(dforgeHome, "config.json");
  const storesFile = path.join(dforgeHome, "stores.json");
  const config = readObject(configFile);
  const stores = readObject(storesFile);
  if (config === UNREADABLE || stores === UNREADABLE) return answer();
  const recordKey = keyFor(stores, root);
  const darkmem = notObject(config?.darkmem) ? undefined : config.darkmem;
  const mapKey = notObject(darkmem?.repos) ? undefined : keyFor(darkmem.repos, root);
  const record = recordKey === undefined ? undefined : stores[recordKey];
  const mapping = mapKey === undefined ? undefined : darkmem.repos[mapKey];
  if (layout || record !== undefined || mapping !== undefined) lines.push(...variableLines(env));
  if (record === undefined && mapping === undefined) {
    if (!layout) return answer();
    const held = readObject(path.join(newHome, "config.json"));
    if (held !== UNREADABLE) copySettings(held, false);
    return answer();
  }
  if (record !== undefined && notObject(record)) {
    refuse(`${storesFile}: the record for ${root} is not a JSON object; fix or delete it, then run dagents-migrate again`);
    return answer();
  }

  // Everything that can refuse is read before anything is written.
  const dagentsConfigFile = path.join(newHome, "config.json");
  const dagentsStoresFile = path.join(newHome, "stores.json");
  const dagentsConfig = readObject(dagentsConfigFile);
  const dagentsStores = readObject(dagentsStoresFile);
  if (dagentsConfig === UNREADABLE || dagentsStores === UNREADABLE) return answer();
  const project = record?.project ?? mapping?.project;
  if (typeof project !== "string" || !PROJECT_NAME.test(project)) {
    refuse(`${root}'s dforge record and mapping name no usable darkmem project; fix ${storesFile} or ${configFile}, then run dagents-migrate again`);
    return answer();
  }
  const heldRecordKey = keyFor(dagentsStores, root);
  const heldRecord = heldRecordKey === undefined ? undefined : dagentsStores[heldRecordKey];
  const target = path.join(newHome, "mirror", project);
  const clash = heldRecord && record ? Object.keys(record).filter(key => key !== "mirror" && key in heldRecord && JSON.stringify(heldRecord[key]) !== JSON.stringify(record[key])) : [];
  if (clash.length) {
    refuse(`${dagentsStoresFile} and ${storesFile} set ${clash.join(", ")} differently for ${root}; keep one, then run dagents-migrate again`);
    return answer();
  }
  const heldDarkmem = dagentsConfig?.darkmem;
  if (heldDarkmem !== undefined && notObject(heldDarkmem)) {
    refuse(`${dagentsConfigFile}: darkmem is not an object; fix it, then run dagents-migrate again`);
    return answer();
  }
  if (mapping !== undefined && heldDarkmem?.url !== undefined && darkmem.url !== undefined && !sameUrl(heldDarkmem.url, darkmem.url)) {
    refuse(`${dagentsConfigFile} names darkmem ${withoutUserinfo(heldDarkmem.url)} and ${configFile} ${withoutUserinfo(darkmem.url)}; ${root}'s mapping was not copied`);
    return answer();
  }
  const heldMapKey = notObject(heldDarkmem?.repos) ? undefined : keyFor(heldDarkmem.repos, root);
  if (mapping !== undefined && heldMapKey !== undefined && heldDarkmem.repos[heldMapKey]?.project !== mapping.project) {
    refuse(`${dagentsConfigFile} maps ${root} to another darkmem project than ${configFile}; keep one, then run dagents-migrate again`);
    return answer();
  }
  const mirror = typeof record?.mirror === "string" ? record.mirror : undefined;
  const mirrorHeld = mirror !== undefined && fs.existsSync(mirror);
  const sharedMirror = mirrorHeld && Object.entries(stores).some(([key, other]) => key !== recordKey && typeof other?.mirror === "string" && samePath(other.mirror, mirror));
  // Only a directory holding darkmem's sync state is deleted once copied.
  const keepMirror = sharedMirror || (mirrorHeld && !fs.existsSync(path.join(mirror, ".sync-state.json")));
  // The path comes from a hand-editable file and is deleted once copied.
  if (mirrorHeld && !fs.existsSync(path.join(mirror, ".sync-state.json")) && !fs.existsSync(path.join(mirror, DFORGE_PREFIX))) {
    refuse(`${mirror}, which ${storesFile} names as ${root}'s mirror, holds neither .sync-state.json nor ${DFORGE_PREFIX}/; fix the record, then run dagents-migrate again`);
    return answer();
  }
  if (mirrorHeld && fs.existsSync(target)) {
    refuse(`${target} exists, so ${mirror} was not moved; move one aside, then run dagents-migrate again`);
    return answer();
  }
  // The real run takes the lock over when it is abandoned; a dry run cannot tell.
  if (dryRun && mirrorHeld && fs.existsSync(path.join(mirror, ".sync.lock"))) {
    refuse(`${mirror} is held by a darkmem sync; try again once it is done`);
    return answer();
  }

  // Held from before the darkmem copy until the mirror is in place, so no
  // sync appends a ledger line the copy misses but the moved state records.
  let release = null;
  if (!dryRun && mirrorHeld) {
    release = acquireLock(mirror);
    if (!release) {
      refuse(`${mirror} is held by a darkmem sync; try again once it is done`);
      return answer();
    }
  }
  try {
    if (!(await moveData())) return answer();
  } finally {
    release?.();
  }

  async function moveData() {
    const applied = ["documents", "progress"].some(family => record?.[family] === "darkmem");
    if (applied || (mapping !== undefined && config.darkmemEnabled === true)) {
      const keyEnv = typeof darkmem?.api_key_env === "string" && darkmem.api_key_env ? darkmem.api_key_env : "DARKMEM_API_KEY";
      if (typeof darkmem?.url !== "string" || !/^https?:\/\/\S+$/.test(darkmem.url) || !env[keyEnv]) {
        refuse(`copying darkmem project ${project} needs darkmem.url in ${configFile} and ${keyEnv} set; nothing in the home was moved`);
        return false;
      }
      if (dryRun) {
        lines.push(`would copy darkmem project ${project}'s ${DFORGE_PREFIX}/ documents and its workstreams to ${DOC_PREFIX}/, reading each copy back and deleting nothing`);
      } else {
        let copied;
        try {
          const client = connect({ url: darkmem.url.replace(/\/+$/, ""), apiKey: env[keyEnv], runKey: runKey({ cwd: root, env }) });
          copied = await copyDarkmem(client, project);
        } catch (error) {
          if (!(error instanceof HttpError) && !(error instanceof TransportError)) throw error;
          refuse(`darkmem could not be copied (${error.message}); nothing in the home was moved and nothing in darkmem was deleted`);
          return false;
        }
        if (copied.problems.length) {
          for (const problem of copied.problems) refuse(problem);
          lines.push(`nothing in the home was moved and nothing in darkmem was deleted`);
          return false;
        }
        if (copied.documents || copied.keys.length) {
          const purge = copied.keys.length ? ` and worklog_purge (project ${project}) on the workstreams ${copied.keys.join(", ")}` : "";
          lines.push(`copied darkmem project ${project}'s ${copied.documents} ${DFORGE_PREFIX}/ document(s) and ${copied.keys.length} workstream(s) to ${DOC_PREFIX}/ and read each copy back`);
          lines.push(`${DFORGE_PREFIX}/ documents and workstreams were copied, not deleted; to delete them once no dforge checkout maps ${project}, run: the darkmem MCP tools document_delete_subtree (project ${project}, uri_prefix ${DFORGE_PREFIX}/)${purge}; they need an admin-scoped key`);
        } else {
          lines.push(`darkmem project ${project} holds no ${DFORGE_PREFIX}/ documents or workstreams to copy`);
        }
      }
    }

    if (mirrorHeld) {
      const verb = keepMirror ? "copied" : "moved";
      if (!dryRun) {
        try {
          copyMirror(mirror, target);
          if (!keepMirror) fs.rmSync(mirror, { recursive: true, force: true });
        } catch (error) {
          if (!(error instanceof StateError)) throw error;
          refuse(error.message);
          return false;
        }
      }
      const why = sharedMirror ? ` (another ${storesFile} record still names it)` : keepMirror ? " (it holds no .sync-state.json, so it was left in place)" : "";
      did(`${verb} ${mirror} to ${target}${why}, its ${DFORGE_PREFIX}/ folder and sync state renamed to ${DOC_PREFIX}/`,
        `would ${keepMirror ? "copy" : "move"} ${mirror} to ${target}${why}, renaming its ${DFORGE_PREFIX}/ folder and sync state to ${DOC_PREFIX}/`);
    }
    return true;
  }

  if (record !== undefined) {
    if (!dryRun) {
      withDforgeLock(home, () => withHomeLock(env, () => {
        const now = readJson(storesFile) ?? {};
        const nowKey = keyFor(now, root);
        const moving = nowKey === undefined ? record : now[nowKey];
        const ours = readJson(dagentsStoresFile) ?? {};
        const oursKey = keyFor(ours, root);
        const held = oursKey === undefined ? {} : ours[oursKey];
        if (oursKey !== undefined) delete ours[oursKey];
        ours[root] = { ...moving, ...held, mirror: target };
        fs.mkdirSync(newHome, { recursive: true });
        writeJson(dagentsStoresFile, ours);
        if (nowKey !== undefined) {
          delete now[nowKey];
          writeJson(storesFile, now);
        }
      }));
    }
    did(`moved ${root}'s record from ${storesFile} to ${dagentsStoresFile}`, `would move ${root}'s record from ${storesFile} to ${dagentsStoresFile}`);
  }

  copySettings(dagentsConfig, mapping !== undefined && heldMapKey === undefined);
  return answer();

  function copySettings(dagentsConfig, addMapping) {
    const settingsFile = path.join(newHome, "config.json");
    const settings = Object.keys(SCHEMA).filter(key => SCHEMA[key].target === "dagents" && config && key in config && !(dagentsConfig && key in dagentsConfig));
    for (const key of settings.filter(key => !isValidValue(SCHEMA[key], config[key]))) lines.push(`${configFile} sets ${key} to a value dagents does not take; it was not copied`);
    const keys = settings.filter(key => isValidValue(SCHEMA[key], config[key]));
    if (keys.length || addMapping) {
      if (!dryRun) {
        withHomeLock(env, () => {
          const current = readJson(settingsFile) ?? {};
          for (const key of keys) if (!(key in current)) current[key] = config[key];
          if (addMapping) {
            const next = notObject(current.darkmem) ? {} : current.darkmem;
            if (next.url === undefined && darkmem.url !== undefined) next.url = darkmem.url;
            if (next.api_key_env === undefined && darkmem.api_key_env !== undefined) next.api_key_env = darkmem.api_key_env;
            next.repos = { ...(notObject(next.repos) ? {} : next.repos), [root]: mapping };
            current.darkmem = next;
          }
          fs.mkdirSync(newHome, { recursive: true });
          writeJson(settingsFile, current);
        });
      }
      const named = [...keys, ...(addMapping ? [`the darkmem mapping for ${root}`] : [])].join(", ");
      did(`copied ${named} from ${configFile} into ${settingsFile}`, `would copy ${named} from ${configFile} into ${settingsFile}`);
    }
  }
}

function isMain() {
  if (!process.argv[1]) return false;
  try {
    return fs.realpathSync(process.argv[1]) === fs.realpathSync(fileURLToPath(import.meta.url));
  } catch {
    return false;
  }
}

if (isMain()) {
  const dryRun = process.argv.includes("--dry-run");
  const say = lines => { for (const line of lines) process.stdout.write(`dagents-home-migrate: ${line}\n`); };
  try {
    const home = migrateHome(process.env, { dryRun });
    say(home.lines);
    const dforge = await migrateDforge(process.env, { dryRun, root: primaryRoot(process.cwd()), layout: process.argv.includes("--dforge-layout") });
    say(dforge.lines);
    process.exitCode = home.refused || dforge.refused ? 1 : 0;
  } catch (error) {
    process.stderr.write(`dagents-home-migrate: ${error.message}\n`);
    process.exitCode = 1;
  }
}
