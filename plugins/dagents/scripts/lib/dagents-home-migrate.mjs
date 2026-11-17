// The home's moves to dagents' names: ~/.dr-forge/ to ~/.dagents/, and, for
// one repository, the dforge 4.x settings dagents defines. dagents keeps
// nothing in darkmem, so no darkmem data is moved, copied or deleted: a
// source that keeps a family (documents or progress) in darkmem is refused
// before anything changes, and darkmem settings and credentials are never
// carried over. The only module besides the document-name translation that
// reads the old names.
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import SCHEMA, { isValidValue } from "../../config/schema.mjs";
import { claudeSettingsPath, withHomeLock } from "./dagents-config.mjs";

// The keys of a home's config.json that configure darkmem.
const DARKMEM_KEYS = ["darkmem", "darkmemEnabled", "documentStore", "progressSource"];
const FAMILY_OPTION = { documents: "documentStore", progress: "progressSource" };
// What a home keeps for darkmem alone, left where it is.
const DARKMEM_ENTRIES = ["mirror", "stores.json"];
// Shared on purpose with dforge and the older plugins, so never renamed.
const SHARED_VARIABLE = /^DR_(TEST_BASH|TEST_ALL)$|^DR_(FORGE|SUPERPOWERS)_/;

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
const withoutDarkmem = config => Object.fromEntries(Object.entries(config).filter(([key]) => !DARKMEM_KEYS.includes(key)));

function git(cwd, args) {
  const result = spawnSync("git", ["-C", cwd, ...args], { encoding: "utf8", timeout: 10000 });
  return result.status === 0 ? result.stdout.trim() : null;
}

// The primary checkout's top level, the key dforge's stores.json uses.
export function primaryRoot(cwd) {
  const common = git(cwd, ["rev-parse", "--path-format=absolute", "--git-common-dir"]);
  const primary = common && path.isAbsolute(common) ? git(path.dirname(common), ["rev-parse", "--show-toplevel"]) : null;
  const top = primary ?? git(cwd, ["rev-parse", "--show-toplevel"]);
  return top === null ? null : path.resolve(top);
}

// Why the migration may not start: one line per family a source keeps in
// darkmem, from ~/.dr-forge/stores.json and ~/.dr-superpowers/stores.json
// (every repository, since the whole home moves) and from
// ~/.dforge/stores.json (ROOT's record). A file that cannot be read may keep
// one, so it refuses too. Empty when the migration may run.
export function darkmemHeld(env = process.env, root = null) {
  const home = env.HOME || os.homedir();
  const lines = [];
  const sources = [
    [path.join(home, ".dr-forge", "stores.json"), null],
    [path.join(home, ".dr-superpowers", "stores.json"), null],
    ...(root ? [[path.join(home, ".dforge", "stores.json"), root]] : []),
  ];
  for (const [file, only] of sources) {
    let data;
    try {
      data = readJson(file);
    } catch (error) {
      lines.push(`${error.message}, so a family it may keep in darkmem cannot be ruled out; fix or delete it, then run dagents-migrate again`);
      continue;
    }
    if (data === undefined) continue;
    if (notObject(data)) {
      lines.push(`${file} does not hold a JSON object, so a family it may keep in darkmem cannot be ruled out; fix or delete it, then run dagents-migrate again`);
      continue;
    }
    const keys = only === null ? Object.keys(data) : [keyFor(data, only)].filter(key => key !== undefined);
    for (const key of keys) {
      const record = data[key];
      if (notObject(record)) continue;
      for (const [family, option] of Object.entries(FAMILY_OPTION)) {
        if (record[family] !== "darkmem") continue;
        lines.push(`${file} keeps ${key}'s ${family} in darkmem, which dagents does not read; set ${option} to local in dforge first, which brings the files into the repository, then run dagents-migrate again`);
      }
    }
  }
  return lines;
}

// The home's half, run by scripts/dagents-migrate. ~/.dr-forge/ becomes
// ~/.dagents/: renamed whole when ~/.dagents/ is absent and the old home holds
// nothing for darkmem, otherwise entry by entry, its config.json merged key by
// key. Its mirror/ and stores.json stay where they are, and its config.json's
// darkmem keys are dropped. The old files stay wherever something was
// refused. With dryRun nothing is written and each line says what would
// happen. Answers { lines, refused }.
export function migrateHome(env = process.env, { dryRun = false } = {}) {
  const home = env.HOME || os.homedir();
  const forgeHome = path.join(home, ".dr-forge");
  const newHome = path.join(home, ".dagents");
  const lines = [];
  let refused = 0;
  const refuse = line => {
    lines.push(`refused: ${line}`);
    refused += 1;
  };
  const did = (done, would) => lines.push(dryRun ? would : done);
  // A change to config.json reads and writes under the lock every other
  // writer of that file takes.
  const locked = change => (dryRun ? change() : withHomeLock(env, change));
  const badConfigs = new Set();
  const readOrRefuse = file => {
    try {
      return readJson(file);
    } catch (error) {
      if (!badConfigs.has(file)) refuse(`${error.message}; fix or delete it, then run dagents-migrate again`);
      badConfigs.add(file);
      return UNREADABLE;
    }
  };
  if (!fs.existsSync(forgeHome)) return { lines, refused };

  const oldConfigFile = path.join(forgeHome, "config.json");
  const oldConfig = fs.existsSync(oldConfigFile) ? readOrRefuse(oldConfigFile) : undefined;
  if (oldConfig !== undefined && oldConfig !== UNREADABLE && notObject(oldConfig)) {
    badConfigs.add(oldConfigFile);
    refuse(`${oldConfigFile} does not hold a JSON object; fix or delete it, then run dagents-migrate again`);
  }
  const usableConfig = oldConfig !== undefined && !badConfigs.has(oldConfigFile);
  const dropped = usableConfig ? Object.keys(oldConfig).filter(key => DARKMEM_KEYS.includes(key)) : [];
  const forDarkmem = DARKMEM_ENTRIES.filter(name => fs.existsSync(path.join(forgeHome, name)));
  const dropLine = () => did(
    `dropped ${dropped.join(", ")} from ${oldConfigFile}: dagents does not sync with darkmem`,
    `would drop ${dropped.join(", ")} from ${oldConfigFile}: dagents does not sync with darkmem`,
  );

  if (!fs.existsSync(newHome) && !forDarkmem.length && !dropped.length && !badConfigs.size) {
    if (!dryRun) fs.renameSync(forgeHome, newHome);
    did(`moved ${forgeHome} to ${newHome}`, `would move ${forgeHome} to ${newHome}`);
    return { lines, refused };
  }

  if (!dryRun) fs.mkdirSync(newHome, { recursive: true });
  for (const entry of fs.readdirSync(forgeHome, { withFileTypes: true })) {
    const from = path.join(forgeHome, entry.name);
    const to = path.join(newHome, entry.name);
    if (DARKMEM_ENTRIES.includes(entry.name)) {
      lines.push(`left ${from} in place; dagents keeps no darkmem mirror or stores`);
      continue;
    }
    if (entry.name === "config.json" && entry.isFile()) {
      if (!usableConfig) continue;
      const carried = withoutDarkmem(oldConfig);
      locked(() => {
        const next = fs.existsSync(to) ? readOrRefuse(to) : {};
        if (next === UNREADABLE) return;
        if (notObject(next)) {
          badConfigs.add(to);
          refuse(`${to} does not hold a JSON object; fix or delete it, then run dagents-migrate again`);
          return;
        }
        const clash = Object.keys(carried).filter(key => key in next && JSON.stringify(carried[key]) !== JSON.stringify(next[key]));
        if (clash.length) {
          refuse(`${from} and ${to} set ${clash.join(", ")} differently; keep one value in ${to} and delete it from ${from}, then run dagents-migrate again`);
          return;
        }
        const copied = Object.keys(carried).filter(key => !(key in next));
        if (!dryRun) {
          writeJson(to, { ...next, ...carried });
          fs.rmSync(from);
        }
        did(`merged ${from} into ${to} (${copied.length ? copied.join(", ") : "no new keys"})`,
          `would merge ${from} into ${to} (${copied.length ? copied.join(", ") : "no new keys"})`);
        if (dropped.length) dropLine();
      });
      continue;
    }
    if (!fs.existsSync(to)) {
      if (!dryRun) fs.renameSync(from, to);
      did(`moved ${from} to ${to}`, `would move ${from} to ${to}`);
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
    try {
      fs.rmdirSync(forgeHome);
    } catch (error) {
      // Still holds something refused or left for darkmem (ENOTEMPTY, or
      // EEXIST on some systems), or is already gone.
      if (!["ENOTEMPTY", "EEXIST", "ENOENT"].includes(error.code)) refuse(`${forgeHome} could not be removed: ${error.message}`);
    }
  }
  return { lines, refused };
}

export function renamedVariable(name) {
  if (name.startsWith("DFORGE_")) return `DAGENTS_${name.slice("DFORGE_".length)}`;
  if (/^DR_[A-Z0-9_]+$/.test(name) && !SHARED_VARIABLE.test(name)) return `DAGENTS_${name.slice("DR_".length)}`;
  return null;
}

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

// dforge 4.x's half, for one repository: the ~/.dforge/config.json settings
// dagents defines, copied never over a value dagents has, and the variables
// to rename. ~/.dforge/ itself is never changed: dforge keeps it for every
// other repository.
export function migrateDforge(env = process.env, { dryRun = false, root, layout = false } = {}) {
  const home = env.HOME || os.homedir();
  const dforgeHome = path.join(home, ".dforge");
  const newHome = path.join(home, ".dagents");
  const lines = [];
  let refused = 0;
  const refuse = line => {
    lines.push(`refused: ${line}`);
    refused += 1;
  };
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
  for (const line of darkmemHeld(env, root).filter(line => line.startsWith(storesFile))) refuse(line);
  if (refused) return answer();
  const recordKey = keyFor(stores, root);
  const repos = notObject(config?.darkmem) || notObject(config.darkmem.repos) ? undefined : config.darkmem.repos;
  const known = recordKey !== undefined || keyFor(repos, root) !== undefined;
  if (!layout && !known) return answer();
  lines.push(...variableLines(env));
  const settingsFile = path.join(newHome, "config.json");
  const held = readObject(settingsFile);
  if (held === UNREADABLE) return answer();
  const settings = Object.keys(SCHEMA).filter(key => SCHEMA[key].target === "dagents" && !DARKMEM_KEYS.includes(key) && config && key in config && !(held && key in held));
  for (const key of settings.filter(key => !isValidValue(SCHEMA[key], config[key]))) lines.push(`${configFile} sets ${key} to a value dagents does not take; it was not copied`);
  const keys = settings.filter(key => isValidValue(SCHEMA[key], config[key]));
  if (keys.length) {
    if (!dryRun) {
      withHomeLock(env, () => {
        const current = readJson(settingsFile) ?? {};
        for (const key of keys) if (!(key in current)) current[key] = config[key];
        fs.mkdirSync(newHome, { recursive: true });
        writeJson(settingsFile, current);
      });
    }
    lines.push(dryRun
      ? `would copy ${keys.join(", ")} from ${configFile} into ${settingsFile}`
      : `copied ${keys.join(", ")} from ${configFile} into ${settingsFile}`);
  }
  return answer();
}

function isMain() {
  if (!process.argv[1]) return false;
  try {
    return fs.realpathSync(process.argv[1]) === fs.realpathSync(fileURLToPath(import.meta.url));
  } catch {
    return false;
  }
}

// `--check` only answers whether the migration may start: each refusal on a
// line, exit 1 when there is one. A full run checks the same first and
// changes nothing when it refuses.
if (isMain()) {
  const dryRun = process.argv.includes("--dry-run");
  const say = lines => { for (const line of lines) process.stdout.write(`dagents-home-migrate: ${line}\n`); };
  try {
    const root = primaryRoot(process.cwd());
    const held = darkmemHeld(process.env, root);
    say(held.map(line => `refused: ${line}`));
    if (held.length) {
      process.exitCode = 1;
    } else if (!process.argv.includes("--check")) {
      const home = migrateHome(process.env, { dryRun });
      say(home.lines);
      const dforge = migrateDforge(process.env, { dryRun, root, layout: process.argv.includes("--dforge-layout") });
      say(dforge.lines);
      process.exitCode = home.refused || dforge.refused ? 1 : 0;
    }
  } catch (error) {
    process.stderr.write(`dagents-home-migrate: ${error.message}\n`);
    process.exitCode = 1;
  }
}
