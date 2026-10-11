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

export function git(cwd, ...args) {
  const result = spawnSync("git", ["-C", cwd, "-c", "user.name=t", "-c", "user.email=t@example.com", ...args], { encoding: "utf8", timeout: 10000 });
  if (result.status !== 0) throw new Error(`git ${args.join(" ")}: ${result.stderr}`);
  return result.stdout.trim();
}

export function makeRepo() {
  const dir = scratch("dms-repo-");
  git(dir, "init", "-q");
  git(dir, "commit", "-q", "--allow-empty", "-m", "init");
  return dir;
}

// A HOME whose ~/.dr-superpowers/config.json maps `repo` to `project`.
// `config` replaces the file's content (a string is written verbatim); null
// writes no file at all.
export function makeHome({ repo, url = "http://127.0.0.1:9", project = "proj", config } = {}) {
  const home = scratch("dms-home-");
  const body = config !== undefined ? config : { darkmem: { url, api_key_env: "DARKMEM_API_KEY", repos: { [repo]: { project } } } };
  if (body !== null) {
    fs.mkdirSync(path.join(home, ".dr-superpowers"), { recursive: true });
    fs.writeFileSync(path.join(home, ".dr-superpowers", "config.json"), typeof body === "string" ? body : JSON.stringify(body));
  }
  const env = {
    ...process.env,
    HOME: home,
    DARKMEM_API_KEY: KEY,
    DR_SUPERPOWERS_SESSION_ID: "sess-1",
    DARKMEM_SYNC_TIMEOUT_MS: "3000",
  };
  const mirror = path.join(home, ".dr-superpowers", "mirror", project);
  return { home, env, mirror, docsRoot: path.join(mirror, "superpowers"), workRoot: path.join(mirror, "work") };
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
