// dr-forge's darkmem stores for one repository (darkmem store options spec
// §1): the mapping in ~/.dr-forge/config.json (the pre-2.0
// ~/.dr-superpowers/config.json until the new file exists), each family's
// configured store and its applied store from ~/.dr-forge/stores.json, the
// mirror, the API key's variable, and the run key a sync declares. An
// unmapped repository keeps both families local.
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { resolve as resolveSettings } from "./forge-config.mjs";

export class ConfigError extends Error {}

// A project names a mirror directory, so it may not climb out of one.
const PROJECT = /^[A-Za-z0-9][A-Za-z0-9._-]{0,199}$/;

function homeOf(env) {
  return env.HOME || os.homedir();
}

export function forgeHome(env = process.env) {
  return path.join(homeOf(env), ".dr-forge");
}

function legacyHome(env) {
  return path.join(homeOf(env), ".dr-superpowers");
}

// The new path, unless it does not exist and the pre-2.0 one does.
export function preferNew(next, old) {
  return !fs.existsSync(next) && fs.existsSync(old) ? old : next;
}

// A repository's dr-forge directory: docs/forge/ or .forge/, or the pre-2.0
// docs/superpowers/ or .superpowers/ where only that exists.
export function forgeDir(kind, root) {
  return kind === "docs"
    ? preferNew(path.join(root, "docs", "forge"), path.join(root, "docs", "superpowers"))
    : preferNew(path.join(root, ".forge"), path.join(root, ".superpowers"));
}

function git(cwd, args) {
  const result = spawnSync("git", ["-C", cwd, ...args], { encoding: "utf8", timeout: 10000 });
  return result.status === 0 ? result.stdout.trim() : null;
}

// The primary checkout's top level, so every worktree of one repository shares
// one mapping and one mirror.
export function primaryRoot(cwd) {
  const common = git(cwd, ["rev-parse", "--path-format=absolute", "--git-common-dir"]);
  return common ? git(path.dirname(common), ["rev-parse", "--show-toplevel"]) : null;
}

function samePath(a, b) {
  const x = path.resolve(a);
  const y = path.resolve(b);
  return process.platform === "win32" ? x.toLowerCase() === y.toLowerCase() : x === y;
}

const FAMILIES = ["documents", "progress"];
const STORES = ["local", "darkmem"];
const OPTION = { documents: "documentStore", progress: "progressSource" };

// Each primary checkout's applied store per family (darkmem store options
// spec §4), written once a move or an import verifies.
export function storesPath(env = process.env) {
  return path.join(forgeHome(env), "stores.json");
}

function readRecord(env) {
  const file = storesPath(env);
  let text;
  try {
    text = fs.readFileSync(file, "utf8");
  } catch (error) {
    if (error.code === "ENOENT") return {};
    throw error;
  }
  let data;
  try {
    data = JSON.parse(text);
  } catch (error) {
    throw new ConfigError(`${file} is not valid JSON: ${error.message}`);
  }
  if (!data || typeof data !== "object" || Array.isArray(data)) throw new ConfigError(`${file} must hold a JSON object`);
  return data;
}

export function writeApplied(env, repoRoot, applied) {
  const file = storesPath(env);
  const data = readRecord(env);
  let entry = {};
  for (const key of Object.keys(data)) {
    if (!samePath(key, repoRoot)) continue;
    entry = { ...entry, ...data[key] };
    delete data[key];
  }
  data[repoRoot] = { ...entry, ...applied };
  fs.mkdirSync(path.dirname(file), { recursive: true });
  const temporary = path.join(path.dirname(file), `.stores.json.${process.pid}.tmp`);
  fs.writeFileSync(temporary, `${JSON.stringify(data, null, 2)}\n`);
  fs.renameSync(temporary, file);
}

// With no record, a family counts as applied darkmem only when the mirror's
// sync state already lists its files, so a repository synced by hand is never
// imported over darkmem's copy.
function syncedFamilies(statePath) {
  let raw;
  try {
    raw = JSON.parse(fs.readFileSync(statePath, "utf8"));
  } catch {
    return { documents: false, progress: false };
  }
  const uris = Object.keys(raw?.documents ?? {});
  const handoff = uri => uri.startsWith("superpowers/handoff/");
  return {
    documents: uris.some(uri => !handoff(uri)),
    progress: uris.some(handoff) || Object.keys(raw?.ledgers ?? {}).length > 0 || Boolean(raw?.checkpoint),
  };
}

export function resolveStores({ cwd = process.cwd(), env = process.env } = {}) {
  const repoRoot = primaryRoot(cwd);
  const worktreeRoot = git(cwd, ["rev-parse", "--show-toplevel"]);
  const result = (reason, configured, applied, sync) => ({
    repoRoot,
    worktreeRoot,
    reason,
    documents: {
      configured: configured.documents,
      applied: applied.documents,
      root: applied.documents === "darkmem" ? path.join(sync.mirror, "superpowers") : worktreeRoot && forgeDir("docs", worktreeRoot),
    },
    progress: {
      configured: configured.progress,
      applied: applied.progress,
      ledgerRoot: applied.progress === "darkmem"
        ? path.join(sync.mirror, "work", "sdd")
        : worktreeRoot && path.join(forgeDir("state", worktreeRoot), "sdd"),
      latestFile: applied.progress === "darkmem"
        ? path.join(sync.mirror, "work", "handoff", "latest.md")
        : repoRoot && path.join(forgeDir("state", repoRoot), "handoff", "latest.md"),
    },
    sync,
  });
  const LOCAL = { documents: "local", progress: "local" };
  const local = reason => result(reason, LOCAL, LOCAL, null);
  if (!repoRoot) return local("not inside a git repository");
  const file = preferNew(path.join(forgeHome(env), "config.json"), path.join(legacyHome(env), "config.json"));
  if (!fs.existsSync(file)) return local(`no ${file}`);
  let config;
  try {
    config = JSON.parse(fs.readFileSync(file, "utf8"));
  } catch (error) {
    throw new ConfigError(`${file} is not valid JSON: ${error.message}`);
  }
  const darkmem = config?.darkmem;
  if (darkmem === undefined) return local(`${file} has no darkmem section`);
  if (!darkmem || typeof darkmem !== "object") throw new ConfigError(`${file}: darkmem must be an object`);
  const mapping = Object.entries(darkmem.repos ?? {}).find(([key]) => samePath(key, repoRoot));
  if (!mapping) return local(`no darkmem mapping for ${repoRoot}`);
  const entry = mapping[1];
  const project = entry?.project;
  if (typeof project !== "string" || !PROJECT.test(project)) {
    throw new ConfigError(`${file}: the mapping for ${repoRoot} needs a project made of letters, digits, '.', '_' or '-'`);
  }
  if (typeof darkmem.url !== "string" || !/^https?:\/\/\S+$/.test(darkmem.url)) {
    throw new ConfigError(`${file}: darkmem.url must be an http or https URL`);
  }
  const keyEnv = darkmem.api_key_env ?? "DARKMEM_API_KEY";
  if (typeof keyEnv !== "string" || !keyEnv) {
    throw new ConfigError(`${file}: darkmem.api_key_env must name an environment variable`);
  }
  // The mapping entry is the most specific choice, so it outranks the
  // environment variable, unlike every other forge-config key.
  const settings = resolveSettings(env, () => {});
  const configured = {};
  for (const family of FAMILIES) {
    const key = OPTION[family];
    const override = entry[key];
    if (override !== undefined && !STORES.includes(override)) {
      throw new ConfigError(`${file}: the mapping for ${repoRoot} sets ${key} to ${JSON.stringify(override)}; use local or darkmem`);
    }
    configured[family] = override ?? settings[key];
  }
  const mirror = preferNew(path.join(forgeHome(env), "mirror", project), path.join(legacyHome(env), "mirror", project));
  const sync = {
    project,
    url: darkmem.url.replace(/\/+$/, ""),
    apiKey: env[keyEnv] || null,
    keyEnv,
    mirror,
    statePath: path.join(mirror, ".sync-state.json"),
  };
  const recorded = Object.entries(readRecord(env)).find(([key]) => samePath(key, repoRoot))?.[1] ?? {};
  let synced = null;
  const applied = {};
  for (const family of FAMILIES) {
    const value = recorded[family];
    if (value === undefined) {
      synced ??= syncedFamilies(sync.statePath);
      applied[family] = synced[family] ? "darkmem" : "local";
    } else if (STORES.includes(value)) {
      applied[family] = value;
    } else {
      throw new ConfigError(`${storesPath(env)}: ${family} for ${repoRoot} must be local or darkmem`);
    }
  }
  return result(`project ${project}`, configured, applied, sync);
}

export function modeLines(stores) {
  return [
    `documents\t${stores.documents.applied}\t${stores.documents.root}`,
    `progress\t${stores.progress.applied}\t${stores.progress.ledgerRoot}\t${stores.progress.latestFile}`,
  ];
}

// The run a sync declares; darkmem refuses an undeclared one.
// DR_FORGE_SESSION_ID (or the pre-2.0 DR_SUPERPOWERS_SESSION_ID) lets a hook pass the id it holds; otherwise the
// record scripts/session-start.sh writes for this directory; otherwise one run
// per machine per day, which is what a Codex session (no hooks) gets.
export function runKey({ cwd = process.cwd(), env = process.env, now = new Date() } = {}) {
  const declared = env.DR_FORGE_SESSION_ID?.trim() || env.DR_SUPERPOWERS_SESSION_ID?.trim();
  if (declared) return declared;
  const sessions = path.join(homeOf(env), ".claude", "dr-forge", "sessions");
  for (const dir of [cwd, git(cwd, ["rev-parse", "--show-toplevel"]), primaryRoot(cwd)]) {
    if (!dir) continue;
    try {
      const record = JSON.parse(fs.readFileSync(path.join(sessions, `${dir.replace(/[^A-Za-z0-9]/g, "-")}.json`), "utf8"));
      if (typeof record.session_id === "string" && record.session_id.trim()) return record.session_id.trim();
    } catch {
      // No usable record for this candidate; try the next one.
    }
  }
  return `codex:${os.hostname()}:${now.toISOString().slice(0, 10)}`;
}

// `node darkmem-config.mjs --mode`, which scripts/lib/roots.sh reads.
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  if (process.argv.length !== 3 || process.argv[2] !== "--mode") {
    process.stderr.write("usage: darkmem-config.mjs --mode\n");
    process.exitCode = 2;
  } else {
    try {
      const stores = resolveStores();
      if (stores.worktreeRoot) {
        process.stdout.write(`${modeLines(stores).join("\n")}\n`);
      } else {
        process.stderr.write("darkmem-config: not inside a git repository\n");
        process.exitCode = 3;
      }
    } catch (error) {
      if (!(error instanceof ConfigError)) throw error;
      process.stderr.write(`darkmem-config: ${error.message}\n`);
      process.exitCode = 2;
    }
  }
}
