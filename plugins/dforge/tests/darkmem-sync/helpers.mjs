// Fixtures shared by the darkmem-sync suites: a throwaway repository, a HOME
// holding a darkmem mapping for it, and a way to run the real command.
import { execFile, spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

export const SCRIPT = fileURLToPath(new URL("../../scripts/darkmem-sync", import.meta.url));
export const KEY = "dmk_test_secret";

const created = [];
process.on("exit", () => {
  for (const dir of created) fs.rmSync(dir, { recursive: true, force: true });
});

// A temporary directory removed when the test process exits. .native expands
// Windows short names, which git never prints.
export function scratch(prefix) {
  const dir = fs.realpathSync.native(fs.mkdtempSync(path.join(os.tmpdir(), prefix)));
  created.push(dir);
  return dir;
}

// A loaded Windows shard has taken over ten seconds for a bare `git init`.
export function git(cwd, ...args) {
  const result = spawnSync("git", ["-C", cwd, "-c", "user.name=t", "-c", "user.email=t@example.com", ...args], { encoding: "utf8", timeout: 60000 });
  if (result.status !== 0) throw new Error(`git ${args.join(" ")}: ${result.error?.message ?? result.stderr}`);
  return result.stdout.trim();
}

export function makeRepo() {
  const dir = scratch("dms-repo-");
  git(dir, "init", "-q");
  git(dir, "commit", "-q", "--allow-empty", "-m", "init");
  return dir;
}

// A HOME whose ~/.dforge/config.json maps `repo` to `project` with darkmem
// enabled (`enabled: false` leaves darkmemEnabled out, `enabled: "off"` sets it false).
// `config` replaces the file's content (a string is written verbatim); null
// writes no file at all. `stores` is the ~/.dforge/stores.json entry for
// `repo` (both families applied darkmem by default); null writes no record.
export function makeHome({
  repo, url = "http://127.0.0.1:9", project = "proj", config, enabled = true,
  stores = { documents: "darkmem", progress: "darkmem" },
} = {}) {
  const home = scratch("dms-home-");
  const dir = path.join(home, ".dforge");
  const mapping = { darkmem: { url, api_key_env: "DARKMEM_API_KEY", repos: { [repo]: { project } } } };
  if (enabled === true) mapping.darkmemEnabled = true;
  if (enabled === "off") mapping.darkmemEnabled = false;
  const body = config !== undefined ? config : mapping;
  if (body !== null) {
    fs.mkdirSync(dir, { recursive: true });
    fs.writeFileSync(path.join(dir, "config.json"), typeof body === "string" ? body : JSON.stringify(body));
  }
  const mirror = path.join(dir, "mirror", project);
  if (stores !== null && repo) {
    fs.mkdirSync(dir, { recursive: true });
    fs.writeFileSync(path.join(dir, "stores.json"), JSON.stringify({ [repo]: { project, mirror, ...stores } }));
  }
  const env = {
    ...process.env,
    HOME: home,
    DARKMEM_API_KEY: KEY,
    DFORGE_SESSION_ID: "sess-1",
    DARKMEM_SYNC_TIMEOUT_MS: "3000",
  };
  return { home, env, mirror, docsRoot: path.join(mirror, "dforge"), workRoot: path.join(mirror, "work") };
}

// Runs scripts/darkmem-sync asynchronously: a stub server in this process
// must keep answering while the command waits on it.
export function run(args, { cwd, env }) {
  return new Promise(resolve => {
    execFile(process.env.DR_TEST_BASH ?? "bash", [SCRIPT, ...args], { cwd, env, timeout: 30000 }, (error, stdout, stderr) => {
      resolve({ code: error ? (typeof error.code === "number" ? error.code : -1) : 0, stdout, stderr });
    });
  });
}

export function write(file, content) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, content);
}

export function read(file) {
  return fs.readFileSync(file, "utf8");
}

// A named pipe nobody writes to: a plain read of it, or through a link to it,
// blocks. Only the command run as a child process meets one before its fix,
// so a blocked read ends at run()'s timeout instead of stopping the test file.
export function namedPipe(file) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  const made = spawnSync("mkfifo", [file], { encoding: "utf8", timeout: 10000 });
  if (made.status !== 0) throw new Error(`mkfifo ${file}: ${made.stderr || made.error?.message}`);
  return file;
}

// A mirror whose darkmem was already checked for pre-3.0 uris, so a test's
// first injected failure meets the command, not that check.
export function markMigrated(mirror) {
  write(path.join(mirror, ".sync-state.json"), JSON.stringify({
    version: 1, documents: {}, ledgers: {}, checkpoint: null, checkpointAt: null, conflicts: [], pendingLinks: [], prefix: "dforge",
  }));
}
