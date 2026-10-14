// The move from dr-forge's pre-3.0 darkmem names to its own: the home
// ~/.dr-superpowers/ to ~/.dr-forge/, a mirror's superpowers/ folder and sync
// state uris to forge/, and darkmem's superpowers/ documents to forge/. The
// only module besides the document-name translation that reads the old names.
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { HttpError } from "./darkmem-client.mjs";
import { DOC_PREFIX, LEGACY_PREFIX, StateError, acquireLock, loadState, saveState } from "./darkmem-mirror.mjs";

const OLD = `${LEGACY_PREFIX}/`;
const renamed = uri => (uri.startsWith(OLD) ? `${DOC_PREFIX}/${uri.slice(OLD.length)}` : uri);

// A mirror's local half: the docs folder and every uri its state records.
// Returns whether anything changed; a mirror holding both folders throws.
export function migrateMirror(mirror, state) {
  let changed = false;
  const old = path.join(mirror, LEGACY_PREFIX);
  const next = path.join(mirror, DOC_PREFIX);
  if (fs.existsSync(old)) {
    if (fs.existsSync(next)) throw new StateError(`${mirror} holds both ${LEGACY_PREFIX}/ and ${DOC_PREFIX}/; move one aside`);
    fs.renameSync(old, next);
    changed = true;
  }
  const documents = Object.create(null);
  for (const [uri, hash] of Object.entries(state.documents)) {
    documents[renamed(uri)] = hash;
    if (uri.startsWith(OLD)) changed = true;
  }
  state.documents = documents;
  const links = state.pendingLinks.map(renamed);
  if (links.some((uri, index) => uri !== state.pendingLinks[index])) changed = true;
  state.pendingLinks = links;
  return changed;
}

// A pre-3.0 mirror: its old folder, or an old uri its state records.
export function legacyMirror(mirror) {
  if (fs.existsSync(path.join(mirror, LEGACY_PREFIX))) return true;
  let raw;
  try {
    raw = JSON.parse(fs.readFileSync(path.join(mirror, ".sync-state.json"), "utf8"));
  } catch {
    return false;
  }
  const uris = [...Object.keys(raw?.documents ?? {}), ...(Array.isArray(raw?.pendingLinks) ? raw.pendingLinks : [])];
  return uris.some(uri => String(uri).startsWith(OLD));
}

// The local half under the mirror's lock, for a caller that holds none.
// Answers { line, blocked } saying what happened, or null when nothing needed
// doing; blocked: a held lock left the mirror in the pre-3.0 layout.
export function migrateMirrorLocked(mirror) {
  if (!legacyMirror(mirror)) return null;
  const release = acquireLock(mirror);
  if (!release) return { line: `${mirror} is still in the pre-3.0 layout and another darkmem-sync holds its lock; try again once it is done`, blocked: true };
  try {
    const statePath = path.join(mirror, ".sync-state.json");
    const state = loadState(statePath);
    if (!migrateMirror(mirror, state)) return null;
    saveState(statePath, state);
    return { line: `renamed ${mirror}'s ${LEGACY_PREFIX}/ to ${DOC_PREFIX}/; darkmem's documents follow at its next sync`, blocked: false };
  } finally {
    release();
  }
}

// darkmem's half, once per mirror: every superpowers/ document moves to the
// same name under forge/, under its own hash. A name darkmem already holds
// under forge/ is a failure, never overwritten. Answers the failure lines;
// state.prefix is set only when there are none.
export async function migrateServer({ cfg, client, state, persist }) {
  if (state.prefix === DOC_PREFIX) return [];
  const failures = [];
  const held = new Map((await client.manifest(cfg.project, DOC_PREFIX)).map(item => [item.uri, item.content_hash]));
  const old = (await client.manifest(cfg.project, LEGACY_PREFIX)).filter(item => item.uri.startsWith(OLD));
  for (const item of old) {
    const uri = renamed(item.uri);
    if (held.has(uri)) {
      failures.push(`${item.uri}: darkmem also holds ${uri}${held.get(uri) === item.content_hash ? " with the same content; delete one" : " with other content; keep one"}`);
      continue;
    }
    try {
      await client.moveDocument(item.id, { uri, expectedHash: item.content_hash });
    } catch (error) {
      if (!(error instanceof HttpError) || error.status === 401) throw error;
      failures.push(`${item.uri}: darkmem refused the move to ${uri}: ${error.detail}`);
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

// The home's half, run by scripts/forge-migrate: the darkmem mapping into
// ~/.dr-forge/config.json when that file has none, each mirror the new home
// lacks, then every mirror's local half. The old files stay where a copy was
// made. Answers { lines, refused }.
export function migrateHome(env = process.env) {
  const home = env.HOME || os.homedir();
  const oldHome = path.join(home, ".dr-superpowers");
  const newHome = path.join(home, ".dr-forge");
  const lines = [];
  let refused = 0;
  const oldConfig = readJson(path.join(oldHome, "config.json"));
  if (oldConfig?.darkmem && typeof oldConfig.darkmem === "object") {
    const file = path.join(newHome, "config.json");
    const config = readJson(file) ?? {};
    if (config.darkmem === undefined) {
      config.darkmem = oldConfig.darkmem;
      fs.mkdirSync(newHome, { recursive: true });
      const temporary = `${file}.${process.pid}.tmp`;
      fs.writeFileSync(temporary, `${JSON.stringify(config, null, 2)}\n`);
      fs.renameSync(temporary, file);
      lines.push(`copied the darkmem mapping from ${path.join(oldHome, "config.json")} into ${file}`);
      if (config.darkmemEnabled === undefined) lines.push("darkmem is off until you turn it on: bash <plugin-root>/scripts/forge-config set darkmemEnabled true");
    } else {
      lines.push(`${file} already has a darkmem section; ${path.join(oldHome, "config.json")} was not copied`);
    }
  }
  const oldMirrors = path.join(oldHome, "mirror");
  const newMirrors = path.join(newHome, "mirror");
  for (const entry of fs.existsSync(oldMirrors) ? fs.readdirSync(oldMirrors, { withFileTypes: true }) : []) {
    if (!entry.isDirectory()) continue;
    const target = path.join(newMirrors, entry.name);
    if (fs.existsSync(target)) {
      lines.push(`refused: ${target} exists, so ${path.join(oldMirrors, entry.name)} was not moved`);
      refused += 1;
      continue;
    }
    fs.mkdirSync(newMirrors, { recursive: true });
    fs.renameSync(path.join(oldMirrors, entry.name), target);
    lines.push(`moved ${path.join(oldMirrors, entry.name)} to ${target}`);
  }
  for (const entry of fs.existsSync(newMirrors) ? fs.readdirSync(newMirrors, { withFileTypes: true }) : []) {
    if (!entry.isDirectory()) continue;
    try {
      const result = migrateMirrorLocked(path.join(newMirrors, entry.name));
      if (result?.blocked) refused += 1;
      if (result) lines.push(result.blocked ? `refused: ${result.line}` : result.line);
    } catch (error) {
      if (!(error instanceof StateError)) throw error;
      lines.push(`refused: ${error.message}`);
      refused += 1;
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
    const { lines, refused } = migrateHome();
    for (const line of lines) process.stdout.write(`darkmem-migrate: ${line}\n`);
    process.exitCode = refused ? 1 : 0;
  } catch (error) {
    process.stderr.write(`darkmem-migrate: ${error.message}\n`);
    process.exitCode = 1;
  }
}
