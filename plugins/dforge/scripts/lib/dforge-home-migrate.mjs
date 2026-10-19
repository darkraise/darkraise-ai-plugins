// The moves from dforge's older darkmem names to its own: the homes
// ~/.dr-superpowers/ and ~/.dr-forge/ to ~/.dforge/, a mirror's superpowers/
// or forge/ folder and sync state uris to dforge/, and darkmem's superpowers/
// and forge/ documents to dforge/. The only module besides the document-name
// translation that reads the old names.
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { HttpError } from "./darkmem-client.mjs";
import { DOC_PREFIX, LEGACY_PREFIX, StateError, acquireLock, loadState, saveState } from "./darkmem-mirror.mjs";

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
  } catch {
    return false;
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
// moves to the same name under dforge/, under its own hash. A name darkmem
// already holds under dforge/ is a failure, never overwritten. Answers the
// failure lines; state.prefix is set only when there are none.
export async function migrateServer({ cfg, client, state, persist }) {
  if (state.prefix === DOC_PREFIX) return [];
  const failures = [];
  const held = new Map((await client.manifest(cfg.project, DOC_PREFIX)).map(item => [item.uri, item.content_hash]));
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

// The home's half, run by scripts/dforge-migrate. ~/.dr-forge/ becomes
// ~/.dforge/: renamed whole when ~/.dforge/ is absent, otherwise entry by
// entry, its config.json merged key by key. ~/.dr-superpowers/ then gives
// ~/.dforge/config.json its darkmem mapping when that file has none, and each
// mirror the new home lacks. stores.json follows every mirror that moved, and
// every mirror gets its local half. The old files stay wherever something was
// refused. With dryRun nothing is written and each line says what would
// happen. Answers { lines, refused }.
export function migrateHome(env = process.env, { dryRun = false } = {}) {
  const home = env.HOME || os.homedir();
  const forgeHome = path.join(home, ".dr-forge");
  const oldHome = path.join(home, ".dr-superpowers");
  const newHome = path.join(home, ".dforge");
  const lines = [];
  let refused = 0;
  const refuse = line => {
    lines.push(`refused: ${line}`);
    refused += 1;
  };
  const did = (done, would) => lines.push(dryRun ? would : done);
  // [from, to, whole]: whole marks a home's mirror folder moving, not one mirror.
  const moves = [];
  // In a dry run nothing has moved, so a path in the new home is read where
  // it still is: under the old entry an earlier line would move there.
  const pending = [];
  let merged;
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
        const old = readJson(from);
        const next = readJson(to);
        const notObject = [[from, old], [to, next]].find(([, value]) => value === null || typeof value !== "object" || Array.isArray(value));
        if (notObject) {
          refuse(`${notObject[0]} does not hold a JSON object; fix or delete it, then run dforge-migrate again`);
          continue;
        }
        const clash = Object.keys(old).filter(key => key in next && JSON.stringify(old[key]) !== JSON.stringify(next[key]));
        if (clash.length) {
          refuse(`${from} and ${to} set ${clash.join(", ")} differently; keep one value in ${to} and delete it from ${from}, then run dforge-migrate again`);
          continue;
        }
        const copied = Object.keys(old).filter(key => !(key in next));
        merged = { ...next, ...old };
        if (!dryRun) {
          writeJson(to, merged);
          fs.rmSync(from);
        }
        did(`merged ${from} into ${to} (${copied.length ? copied.join(", ") : "no new keys"})`,
          `would merge ${from} into ${to} (${copied.length ? copied.join(", ") : "no new keys"})`);
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
              refuse(`${source} differs from ${target}; keep one by hand, then run dforge-migrate again`);
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
      refuse(`${from} differs from ${to}; keep one by hand, then run dforge-migrate again`);
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

  const oldConfig = readJson(path.join(oldHome, "config.json"));
  if (oldConfig?.darkmem && typeof oldConfig.darkmem === "object") {
    const file = path.join(newHome, "config.json");
    const config = (dryRun && merged) ? { ...merged } : readJson(view("config.json")) ?? {};
    if (config.darkmem === undefined) {
      config.darkmem = oldConfig.darkmem;
      if (!dryRun) {
        fs.mkdirSync(newHome, { recursive: true });
        writeJson(file, config);
      }
      did(`copied the darkmem mapping from ${path.join(oldHome, "config.json")} into ${file}`,
        `would copy the darkmem mapping from ${path.join(oldHome, "config.json")} into ${file}`);
      if (config.darkmemEnabled === undefined) lines.push("darkmem is off until you turn it on: bash <plugin-root>/scripts/dforge-config set darkmemEnabled true");
    } else {
      lines.push(`${file} already has a darkmem section; ${path.join(oldHome, "config.json")} was not copied`);
    }
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
  const data = readJson(stores);
  if (data && typeof data === "object" && !Array.isArray(data)) {
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

function isMain() {
  if (!process.argv[1]) return false;
  try {
    return fs.realpathSync(process.argv[1]) === fs.realpathSync(fileURLToPath(import.meta.url));
  } catch {
    return false;
  }
}

if (isMain()) {
  try {
    const { lines, refused } = migrateHome(process.env, { dryRun: process.argv.includes("--dry-run") });
    for (const line of lines) process.stdout.write(`dforge-home-migrate: ${line}\n`);
    process.exitCode = refused ? 1 : 0;
  } catch (error) {
    process.stderr.write(`dforge-home-migrate: ${error.message}\n`);
    process.exitCode = 1;
  }
}
