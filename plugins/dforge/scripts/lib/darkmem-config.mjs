// dforge's darkmem stores for one repository (darkmem store options spec
// §1): whether darkmem is enabled (the darkmemEnabled setting), the mapping in
// ~/.dforge/config.json, each family's configured store and its applied
// store from ~/.dforge/stores.json, the mirror, the API key's variable, and
// the run key a sync declares. A disabled or unmapped repository configures
// both families local; a family still applied darkmem keeps its mirror until
// reconcile moves it back.
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { resolve as resolveSettings, withHomeLock } from "./dforge-config.mjs";
import { DOC_PREFIX } from "./darkmem-mirror.mjs";

export class ConfigError extends Error {}

// A project names a mirror directory, so it may not climb out of one.
const PROJECT = /^[A-Za-z0-9][A-Za-z0-9._-]{0,199}$/;

function homeOf(env) {
  return env.HOME || os.homedir();
}

export function dforgeHome(env = process.env) {
  return path.join(homeOf(env), ".dforge");
}

// A repository's dforge directory: docs/dforge/ or .dforge/.
export function dforgeDir(kind, root) {
  return kind === "docs" ? path.join(root, "docs", "dforge") : path.join(root, ".dforge");
}

function git(cwd, args) {
  const result = spawnSync("git", ["-C", cwd, ...args], { encoding: "utf8", timeout: 10000 });
  return result.status === 0 ? result.stdout.trim() : null;
}

// The primary checkout's top level, so every worktree of one repository shares
// one mapping and one mirror. A submodule's common directory lies under its
// superproject's .git/modules/, which has no work tree, and git before 2.31
// does not answer --path-format with an absolute path: both fall back to the
// checkout's own top level, so a submodule is a repository of its own.
export function primaryRoot(cwd) {
  const common = git(cwd, ["rev-parse", "--path-format=absolute", "--git-common-dir"]);
  const primary = common && path.isAbsolute(common) ? git(path.dirname(common), ["rev-parse", "--show-toplevel"]) : null;
  return primary ?? git(cwd, ["rev-parse", "--show-toplevel"]);
}

// A configured key may name the checkout through a symbolic link, and may name
// a directory that no longer exists, which compares as written.
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

const FAMILIES = ["documents", "progress"];
const STORES = ["local", "darkmem"];
const OPTION = { documents: "documentStore", progress: "progressSource" };


// Each primary checkout's applied store per family (darkmem store options
// spec §4), written once a move or an import verifies.
export function storesPath(env = process.env) {
  return path.join(dforgeHome(env), "stores.json");
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

// The record's project and mirror, written only when they differ.
export function recordWhere(env, repoRoot, where) {
  const held = Object.entries(readRecord(env)).find(([key]) => samePath(key, repoRoot))?.[1] ?? {};
  if (held.project !== where.project || held.mirror !== where.mirror) writeApplied(env, repoRoot, {}, where);
}

// `where` ({ project, mirror }) is kept beside the applied stores, so a family
// applied darkmem can still be found once darkmem is disabled or unmapped.
export function writeApplied(env, repoRoot, applied, where = {}) {
  const file = storesPath(env);
  withHomeLock(env, () => {
    const data = readRecord(env);
    let entry = {};
    for (const key of Object.keys(data)) {
      if (!samePath(key, repoRoot)) continue;
      entry = { ...entry, ...data[key] };
      delete data[key];
    }
    const known = Object.fromEntries(Object.entries(where).filter(([, value]) => value !== undefined && value !== null));
    data[repoRoot] = { ...entry, ...known, ...applied };
    fs.mkdirSync(path.dirname(file), { recursive: true });
    const temporary = path.join(path.dirname(file), `.stores.json.${process.pid}.tmp`);
    fs.writeFileSync(temporary, `${JSON.stringify(data, null, 2)}\n`);
    fs.renameSync(temporary, file);
  }, ConfigError);
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
      root: applied.documents === "darkmem" ? path.join(sync.mirror, DOC_PREFIX) : worktreeRoot && dforgeDir("docs", worktreeRoot),
    },
    progress: {
      configured: configured.progress,
      applied: applied.progress,
      ledgerRoot: applied.progress === "darkmem"
        ? path.join(sync.mirror, "work", "sdd")
        : worktreeRoot && path.join(dforgeDir("state", worktreeRoot), "sdd"),
      latestFile: applied.progress === "darkmem"
        ? path.join(sync.mirror, "work", "handoff", "latest.md")
        : (repoRoot ?? worktreeRoot) && path.join(dforgeDir("state", repoRoot ?? worktreeRoot), "handoff", "latest.md"),
    },
    sync,
  });
  const LOCAL = { documents: "local", progress: "local" };
  if (!repoRoot) return result("not inside a git repository", LOCAL, LOCAL, null);
  const recorded = Object.entries(readRecord(env)).find(([key]) => samePath(key, repoRoot))?.[1] ?? {};
  const applied = {};
  for (const family of FAMILIES) {
    const value = recorded[family] ?? "local";
    if (!STORES.includes(value)) throw new ConfigError(`${storesPath(env)}: ${family} for ${repoRoot} must be local or darkmem`);
    applied[family] = value;
  }
  const inMirror = FAMILIES.some(family => applied[family] === "darkmem");
  const mapped = readMapping(env, repoRoot);
  const settings = resolveSettings(env, () => {});
  const enabled = settings.darkmemEnabled === true;
  // Disabled or unmapped: both families belong in the checkout. A family
  // still in the mirror resolves there, offline, until reconcile moves it.
  if (!enabled || !mapped.entry) {
    if (!inMirror) return result(!enabled ? "darkmem is disabled (darkmemEnabled is false)" : mapped.reason, LOCAL, LOCAL, null);
    // 3.0 made darkmem opt-in. A family a 2.x run put in the mirror is not
    // moved by the upgrade alone: it stays, unsynced, until darkmemEnabled is
    // set either way.
    const undecided = !enabled && mapped.entry && !mapped.decided;
    const reason = undecided
      ? "darkmem is off by default since dforge 3.0 and darkmemEnabled is unset"
      : !enabled ? "darkmem is disabled (darkmemEnabled is false)" : mapped.reason;
    const project = recorded.project ?? mapped.entry?.project;
    const mirror = recorded.mirror ?? (mapped.entry && path.join(dforgeHome(env), "mirror", mapped.entry.project));
    if (typeof project !== "string" || !PROJECT.test(project) || typeof mirror !== "string" || !path.isAbsolute(mirror)) {
      throw new ConfigError(`${storesPath(env)}: ${repoRoot} is applied darkmem but its record names no project and mirror; map the repository in ~/.dforge/config.json again (or run scripts/dforge-migrate if it was mapped before 3.0) so reconcile can move it back`);
    }
    return result(reason, undecided ? applied : LOCAL, applied, syncOf(env, mapped, project, mirror, false));
  }
  const entry = mapped.entry;
  const configured = {};
  for (const family of FAMILIES) configured[family] = entry[OPTION[family]] ?? settings[OPTION[family]];
  const mirror = path.join(dforgeHome(env), "mirror", entry.project);
  return result(`project ${entry.project}`, configured, applied, syncOf(env, mapped, entry.project, mirror, true));
}

// The repository's darkmem mapping: { file, entry, url, keyEnv }, or
// { reason } when there is none. A malformed file or entry throws.
function readMapping(env, repoRoot) {
  const file = path.join(dforgeHome(env), "config.json");
  let text;
  try {
    text = fs.readFileSync(file, "utf8");
  } catch (error) {
    if (error.code === "ENOENT") return { reason: `no ${file}` };
    throw error;
  }
  let config;
  try {
    config = JSON.parse(text);
  } catch (error) {
    throw new ConfigError(`${file} is not valid JSON: ${error.message}`);
  }
  const darkmem = config?.darkmem;
  if (darkmem === undefined) return { reason: `${file} has no darkmem section` };
  if (!darkmem || typeof darkmem !== "object") throw new ConfigError(`${file}: darkmem must be an object`);
  const mapping = Object.entries(darkmem.repos ?? {}).find(([key]) => samePath(key, repoRoot));
  if (!mapping) return { reason: `no darkmem mapping for ${repoRoot}` };
  const entry = mapping[1];
  if (typeof entry?.project !== "string" || !PROJECT.test(entry.project)) {
    throw new ConfigError(`${file}: the mapping for ${repoRoot} needs a project made of letters, digits, '.', '_' or '-'`);
  }
  if (typeof darkmem.url !== "string" || !/^https?:\/\/\S+$/.test(darkmem.url)) {
    throw new ConfigError(`${file}: darkmem.url must be an http or https URL`);
  }
  const keyEnv = darkmem.api_key_env ?? "DARKMEM_API_KEY";
  if (typeof keyEnv !== "string" || !keyEnv) {
    throw new ConfigError(`${file}: darkmem.api_key_env must name an environment variable`);
  }
  for (const key of Object.values(OPTION)) {
    if (entry[key] !== undefined && !STORES.includes(entry[key])) {
      throw new ConfigError(`${file}: the mapping for ${repoRoot} sets ${key} to ${JSON.stringify(entry[key])}; use local or darkmem`);
    }
  }
  return { file, entry, url: darkmem.url.replace(/\/+$/, ""), keyEnv, decided: typeof config.darkmemEnabled === "boolean" };
}

// enabled false: the mirror is read and moved from, never synced.
function syncOf(env, mapped, project, mirror, enabled) {
  const keyEnv = mapped.keyEnv ?? "DARKMEM_API_KEY";
  return {
    project,
    enabled,
    url: mapped.url ?? null,
    apiKey: (mapped.url && env[keyEnv]) || null,
    keyEnv,
    mirror,
    statePath: path.join(mirror, ".sync-state.json"),
  };
}

export function modeLines(stores) {
  const lines = [
    `documents\t${stores.documents.applied}\t${stores.documents.root}`,
    `progress\t${stores.progress.applied}\t${stores.progress.ledgerRoot}\t${stores.progress.latestFile}`,
  ];
  if (stores.sync?.enabled) lines.push(`project\t${stores.sync.project}`);
  return lines;
}

// The run a sync declares; darkmem refuses an undeclared one.
// DFORGE_SESSION_ID lets a hook pass the id it holds; otherwise the
// record scripts/session-start.sh writes for this directory; otherwise one run
// per machine per day, which is what a Codex session (no hooks) gets.
export function runKey({ cwd = process.cwd(), env = process.env, now = new Date() } = {}) {
  const declared = env.DFORGE_SESSION_ID?.trim();
  if (declared) return declared;
  const sessions = path.join(homeOf(env), ".claude", "dforge", "sessions");
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

// Node resolves a module's symbolic links, argv[1] is not, so compare real paths.
function isMain() {
  if (!process.argv[1]) return false;
  try {
    return fs.realpathSync(process.argv[1]) === fs.realpathSync(fileURLToPath(import.meta.url));
  } catch {
    return false;
  }
}

// `node darkmem-config.mjs --mode [DIR]`, which scripts/lib/roots.sh reads.
// DIR names the checkout for a caller that cannot set the working directory:
// a mod's process call sets none.
if (isMain()) {
  const [flag, dir, ...extra] = process.argv.slice(2);
  if (flag !== "--mode" || dir === "" || extra.length) {
    process.stderr.write("usage: darkmem-config.mjs --mode [DIR]\n");
    process.exitCode = 2;
  } else {
    try {
      const stores = resolveStores({ cwd: dir === undefined ? process.cwd() : path.resolve(dir) });
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
