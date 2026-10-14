// dr-forge's settings: their schema (config/schema.mjs), the values in
// ~/.dr-forge/config.json, and the environment variable a key names, which wins
// over both. A key whose target is `claude` lives in Claude's own user settings
// file instead, and this module is its only writer. The first command on a
// machine imports the pre-2.0 settings once.
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import SCHEMA from "../../config/schema.mjs";

export class SettingError extends Error {}

const USAGE = "usage: forge-config get KEY | get --json | set KEY VALUE | unset KEY | claude-restore JSON | workflow";

function homeOf(env) {
  return env.HOME || os.homedir();
}

export function configPath(env = process.env) {
  return path.join(homeOf(env), ".dr-forge", "config.json");
}

// A value as the file holds it: exactly the schema's type.
export function isValid(spec, value) {
  switch (spec.type) {
    case "boolean": return typeof value === "boolean";
    case "number":
      if (typeof value !== "number" || !Number.isInteger(value)) return false;
      // A floor leaves 0 as the one value below it: "unset".
      if (spec.floor !== undefined) return value === 0 || (value >= spec.floor && (spec.max === undefined || value <= spec.max));
      return (spec.min === undefined || value >= spec.min) && (spec.max === undefined || value <= spec.max);
    case "enum": return typeof value === "string" && spec.values.includes(value);
    case "string": return typeof value === "string";
    default: return false;
  }
}

// A value as a command line or an environment variable spells it; undefined when it does not fit.
export function fromText(spec, text) {
  const value = spec.type === "boolean" ? (text === "true" ? true : text === "false" ? false : undefined)
    : spec.type === "number" ? (text.trim() === "" ? undefined : Number(text))
    : text;
  return value !== undefined && isValid(spec, value) ? value : undefined;
}

// The file's object, or null when it does not exist. Anything else unreadable throws.
export function readFile(file) {
  let text;
  try {
    text = fs.readFileSync(file, "utf8");
  } catch (error) {
    if (error.code === "ENOENT") return null;
    throw error;
  }
  let data;
  try {
    data = JSON.parse(text);
  } catch {
    throw new Error(`${file} is not valid JSON; fix or remove it`);
  }
  if (!data || typeof data !== "object" || Array.isArray(data)) throw new Error(`${file} must hold a JSON object`);
  return data;
}

// Replaces a file in one rename, keeping the mode it had: Claude's settings
// file may be private, and a temporary file would otherwise take the umask's.
function writeFile(file, data) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  let mode;
  try {
    mode = fs.statSync(file).mode & 0o777;
  } catch (error) {
    if (error.code !== "ENOENT") throw error;
  }
  const temp = `${file}.${process.pid}.tmp`;
  try {
    // Created with the mode it will keep, so the contents are never readable
    // more widely than the file they replace; chmod then undoes the umask.
    fs.rmSync(temp, { force: true });
    fs.writeFileSync(temp, `${JSON.stringify(data, null, 2)}\n`, mode === undefined ? undefined : { mode });
    if (mode !== undefined) fs.chmodSync(temp, mode);
    fs.renameSync(temp, file);
  } catch (error) {
    fs.rmSync(temp, { force: true });
    throw error;
  }
}

function claudeDir(env) {
  return env.CLAUDE_CONFIG_DIR || path.join(homeOf(env), ".claude");
}

export function claudeSettingsPath(env = process.env) {
  return path.join(claudeDir(env), "settings.json");
}

// Claude's user settings as far as they can be read: a file that cannot be
// parsed is warned about and read as empty, so the forge keys still resolve.
function claudeValues(env, warn) {
  try {
    return readFile(claudeSettingsPath(env)) ?? {};
  } catch (error) {
    warn(error.message);
    return {};
  }
}

// The file a write lands on: where a symlink points, even when that
// destination does not exist yet, so a rename never replaces the link itself.
function realTarget(file) {
  try {
    return fs.realpathSync(file);
  } catch (error) {
    if (error.code !== "ENOENT") throw error;
  }
  try {
    return path.resolve(path.dirname(file), fs.readlinkSync(file));
  } catch {
    return file;
  }
}

// Changes one key of Claude's user settings and nothing else; `undefined`
// removes it. The write goes to the file a symlink points at, so a settings
// file kept in a dotfiles repository stays a link. A file that is not a JSON
// object throws before anything is written.
function writeClaude(env, key, value) {
  writeClaudeKeys(env, [[key, value]]);
}

function writeClaudeKeys(env, entries) {
  const file = realTarget(claudeSettingsPath(env));
  const data = readFile(file) ?? {};
  for (const [key, value] of entries) {
    if (value === undefined) delete data[key];
    else data[key] = value;
  }
  writeFile(file, data);
}

// What /model and /effort save as the user's defaults. An auto run's cleared
// session runs both, and the cockpit puts the saved values back afterwards.
const RESTORABLE = ["model", "modelSettings"];

// claude-restore JSON — sets each named key of Claude's user settings to its
// value, removing a key whose value is null, in one write.
export function restoreClaude(text, env = process.env) {
  let values;
  try {
    values = JSON.parse(text);
  } catch {
    throw new SettingError("claude-restore takes a JSON object");
  }
  if (values === null || typeof values !== "object" || Array.isArray(values)) {
    throw new SettingError("claude-restore takes a JSON object");
  }
  for (const key of Object.keys(values)) {
    if (!RESTORABLE.includes(key)) throw new SettingError(`claude-restore restores only ${RESTORABLE.join(" and ")}, not ${key}`);
  }
  writeClaudeKeys(env, Object.entries(values).map(([key, value]) => [key, value === null ? undefined : value]));
}

function readJson(file) {
  try {
    return JSON.parse(fs.readFileSync(file, "utf8"));
  } catch {
    return null;
  }
}

function need(key) {
  if (!Object.hasOwn(SCHEMA, key)) throw new SettingError(`unknown setting ${key}`);
  return SCHEMA[key];
}

export function resolve(env = process.env, warn = message => process.stderr.write(`forge-config: ${message}\n`)) {
  const file = configPath(env);
  const data = readFile(file) ?? {};
  let claude;
  const values = {};
  for (const [key, spec] of Object.entries(SCHEMA)) {
    if (spec.target === "claude") {
      claude ??= claudeValues(env, warn);
      if (Object.hasOwn(claude, key)) {
        if (isValid(spec, claude[key])) { values[key] = claude[key]; continue; }
        warn(`${key} in ${claudeSettingsPath(env)} is not valid; ignored`);
      }
      values[key] = spec.default;
      continue;
    }
    const raw = spec.env === undefined ? undefined : env[spec.env];
    if (raw !== undefined && raw !== "") {
      const value = fromText(spec, raw);
      if (value !== undefined) { values[key] = value; continue; }
      warn(`${spec.env}=${raw} is not a valid ${key}; ignored`);
    }
    if (key in data) {
      if (isValid(spec, data[key])) { values[key] = data[key]; continue; }
      warn(`${key} in ${file} is not valid; ignored`);
    }
    values[key] = spec.default;
  }
  return values;
}

// One line naming the skill-enforced keys that differ from their defaults, for
// the session-start hook and the skills; empty when every one is at its default.
export function workflowLine(env = process.env) {
  const values = resolve(env, () => {});
  const parts = Object.entries(SCHEMA)
    .filter(([key, spec]) => spec.enforcedBy === "skill" && values[key] !== spec.default)
    .map(([key]) => `${key}=${values[key]}`);
  return parts.length === 0 ? "" : `dr-forge settings in force (each replaces the matching question or default in the skills): ${parts.join("; ")}`;
}

export function setValue(key, text, env = process.env) {
  const spec = need(key);
  const value = fromText(spec, text);
  if (value === undefined) throw new SettingError(`${text} is not a valid ${key}`);
  if (spec.target === "claude") {
    // 0 on a floored key means "unset"; any other value is written as given,
    // a default included, because Claude's own default is not ours to assume.
    writeClaude(env, key, spec.floor !== undefined && value === 0 ? undefined : value);
    return value;
  }
  const file = configPath(env);
  const data = readFile(file) ?? {};
  if (value === spec.default && !spec.keepDefault) delete data[key];
  else data[key] = value;
  writeFile(file, data);
  return value;
}

export function unsetValue(key, env = process.env) {
  const spec = need(key);
  if (spec.target === "claude") { writeClaude(env, key, undefined); return; }
  const file = configPath(env);
  const data = readFile(file) ?? {};
  delete data[key];
  writeFile(file, data);
}

// Once per machine, while ~/.dr-forge/config.json does not exist: dr-cockpit's
// options from the Claude settings file. The old file stays in place.
export function importLegacy(env = process.env) {
  const file = configPath(env);
  if (fs.existsSync(file)) return false;
  const data = {};
  const options = readJson(claudeSettingsPath(env))?.pluginConfigs?.["dr-cockpit@darkraise"]?.options;
  if (options && typeof options === "object") {
    for (const [key, spec] of Object.entries(SCHEMA)) {
      if (spec.target === "forge" && key in options && isValid(spec, options[key]) && options[key] !== spec.default) data[key] = options[key];
    }
  }
  fs.mkdirSync(path.dirname(file), { recursive: true });
  const temp = `${file}.${process.pid}.import`;
  fs.writeFileSync(temp, `${JSON.stringify(data, null, 2)}\n`);
  try {
    // A hard link creates the file only if nobody did first, so of two first
    // runs at once exactly one import lands, whole.
    fs.linkSync(temp, file);
    return true;
  } catch (error) {
    if (error.code === "EEXIST") return false;
    throw error;
  } finally {
    fs.rmSync(temp, { force: true });
  }
}

export function main(argv, env = process.env, out = process.stdout) {
  const [command, ...rest] = argv;
  try {
    // A script reading one setting must not be what creates the settings file.
    if (!env.DR_FORGE_NO_IMPORT) importLegacy(env);
    if (command === "get" && rest.length === 1 && rest[0] === "--json") {
      out.write(`${JSON.stringify(resolve(env))}\n`);
      return 0;
    }
    if (command === "get" && rest.length === 1) {
      need(rest[0]);
      out.write(`${resolve(env)[rest[0]]}\n`);
      return 0;
    }
    if (command === "set" && rest.length === 2) { setValue(rest[0], rest[1], env); return 0; }
    if (command === "unset" && rest.length === 1) { unsetValue(rest[0], env); return 0; }
    if (command === "claude-restore" && rest.length === 1) { restoreClaude(rest[0], env); return 0; }
    if (command === "workflow" && rest.length === 0) {
      const line = workflowLine(env);
      if (line) out.write(`${line}\n`);
      return 0;
    }
    process.stderr.write(`${USAGE}\n`);
    return 2;
  } catch (error) {
    process.stderr.write(`forge-config: ${error.message}\n`);
    return error instanceof SettingError ? 2 : 1;
  }
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  process.exitCode = main(process.argv.slice(2));
}
