// dr-superpowers' darkmem mode for one repository (darkmem mirror spec §1):
// the mapping in ~/.dr-superpowers/config.json, the API key from the
// environment variable the file names, the mirror's two roots, and the run key
// a sync declares. No mapping, or no key, is local mode.
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

export class ConfigError extends Error {}

// A project names a mirror directory, so it may not climb out of one.
const PROJECT = /^[A-Za-z0-9][A-Za-z0-9._-]{0,199}$/;

function homeOf(env) {
  return env.HOME || os.homedir();
}

export function superpowersHome(env = process.env) {
  return path.join(homeOf(env), ".dr-superpowers");
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

export function resolveMode({ cwd = process.cwd(), env = process.env } = {}) {
  const repoRoot = primaryRoot(cwd);
  const local = reason => ({
    mode: "local",
    reason,
    repoRoot,
    docsRoot: repoRoot ? path.join(repoRoot, "docs", "superpowers") : null,
    workRoot: repoRoot ? path.join(repoRoot, ".superpowers") : null,
  });
  if (!repoRoot) return local("not inside a git repository");
  const file = path.join(superpowersHome(env), "config.json");
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
  const project = mapping[1]?.project;
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
  const apiKey = env[keyEnv];
  if (!apiKey) return local(`${keyEnv} is not set`);
  const mirror = path.join(superpowersHome(env), "mirror", project);
  return {
    mode: "darkmem",
    reason: `project ${project}`,
    repoRoot,
    project,
    url: darkmem.url.replace(/\/+$/, ""),
    apiKey,
    mirror,
    docsRoot: path.join(mirror, "superpowers"),
    workRoot: path.join(mirror, "work"),
    statePath: path.join(mirror, ".sync-state.json"),
  };
}

// The run a sync declares; darkmem refuses an undeclared one.
// DR_SUPERPOWERS_SESSION_ID lets a hook pass the id it holds; otherwise the
// record scripts/session-start.sh writes for this directory; otherwise one run
// per machine per day, which is what a Codex session (no hooks) gets.
export function runKey({ cwd = process.cwd(), env = process.env, now = new Date() } = {}) {
  const declared = env.DR_SUPERPOWERS_SESSION_ID?.trim();
  if (declared) return declared;
  const sessions = path.join(homeOf(env), ".claude", "dr-superpowers", "sessions");
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
