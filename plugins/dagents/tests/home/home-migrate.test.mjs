import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import crypto from "node:crypto";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";
import { darkmemHeld, migrateDforge, migrateHome } from "../../scripts/lib/dagents-home-migrate.mjs";

const MODULE = fileURLToPath(new URL("../../scripts/lib/dagents-home-migrate.mjs", import.meta.url));
const created = [];
process.on("exit", () => {
  for (const dir of created) fs.rmSync(dir, { recursive: true, force: true });
});

function scratch(prefix) {
  const dir = fs.realpathSync.native(fs.mkdtempSync(path.join(os.tmpdir(), prefix)));
  created.push(dir);
  return dir;
}

function write(file, text) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, text);
}

const read = file => fs.readFileSync(file, "utf8");
const json = file => JSON.parse(read(file));

function makeRepo() {
  const dir = scratch("dagents-migrate-repo-");
  const result = spawnSync("git", ["-C", dir, "init", "-q"], { encoding: "utf8", timeout: 60000 });
  assert.equal(result.status, 0, result.stderr);
  return dir;
}

// Every path under dir with its content's hash: a run that rewrote a file
// fails the comparison, not only one that added or removed one.
const snapshot = dir => fs.readdirSync(dir, { recursive: true }).sort().map(name => {
  const file = path.join(dir, name);
  return fs.statSync(file).isDirectory() ? `${name}/` : `${name} ${crypto.createHash("sha256").update(fs.readFileSync(file)).digest("hex")}`;
});

const cli = (cwd, home, ...args) => spawnSync(process.execPath, [MODULE, ...args], {
  cwd, encoding: "utf8", timeout: 60000, env: { ...process.env, HOME: home, USERPROFILE: home, CLAUDE_CONFIG_DIR: path.join(home, ".claude") },
});

test("a dforge record keeping a family in darkmem refuses the migration before anything changes", () => {
  const repo = makeRepo();
  const home = scratch("dagents-migrate-home-");
  write(path.join(home, ".dforge", "config.json"), JSON.stringify({ handoffTokens: 325000, darkmemEnabled: true, darkmem: { url: "http://127.0.0.1:9", repos: { [repo]: { project: "p" } } } }));
  write(path.join(home, ".dforge", "stores.json"), JSON.stringify({ [repo]: { project: "p", documents: "local", progress: "darkmem" }, "/elsewhere": { documents: "darkmem" } }));
  write(path.join(home, ".dforge", "mirror", "p", "work", "sdd", "p1", "progress.md"), "ledger\n");
  write(path.join(home, ".dr-forge", "config.json"), JSON.stringify({ layout: "auto" }));
  const before = snapshot(home);
  const held = darkmemHeld({ HOME: home }, repo);
  assert.equal(held.length, 1, held.join("\n"));
  assert.match(held[0], /keeps .*'s progress in darkmem.*set progressSource to local in dforge first, which brings the files into the repository, then run dagents-migrate again/);
  const check = cli(repo, home, "--check");
  assert.equal(check.status, 1, check.stdout + check.stderr);
  assert.equal(check.stdout, `dagents-home-migrate: refused: ${held[0]}\n`);
  const run = cli(repo, home, "--dforge-layout");
  assert.equal(run.status, 1, run.stdout + run.stderr);
  assert.equal(run.stdout, check.stdout, "a full run refuses the same and does nothing else");
  assert.deepEqual(snapshot(home), before);
  assert.deepEqual(migrateDforge({ HOME: home }, { root: repo }).refused, 1);
  assert.deepEqual(snapshot(home), before);
});

test("an older home's stores.json keeping any family in darkmem refuses, as does one that cannot be read", () => {
  const home = scratch("dagents-migrate-home-");
  write(path.join(home, ".dr-forge", "stores.json"), JSON.stringify({ "/r": { documents: "darkmem", progress: "local" } }));
  write(path.join(home, ".dr-superpowers", "stores.json"), "{ not json");
  const held = darkmemHeld({ HOME: home }, null);
  assert.equal(held.length, 2, held.join("\n"));
  assert.match(held[0], /\.dr-forge.*keeps \/r's documents in darkmem.*set documentStore to local in dforge first/);
  assert.match(held[1], /\.dr-superpowers.*could not be read: .*, so a family it may keep in darkmem cannot be ruled out/);
  const repo = makeRepo();
  const before = snapshot(home);
  assert.equal(cli(repo, home).status, 1);
  assert.deepEqual(snapshot(home), before);
});

test("a dforge record with local stores copies the settings dagents defines and no darkmem setting", () => {
  const repo = makeRepo();
  const home = scratch("dagents-migrate-home-");
  const dforgeConfig = { handoffTokens: 325000, layout: "compact", darkmemEnabled: true, documentStore: "local", progressSource: "local", darkmem: { url: "http://127.0.0.1:9", api_key_env: "MY_KEY", repos: { [repo]: { project: "p" } } } };
  write(path.join(home, ".dforge", "config.json"), JSON.stringify(dforgeConfig));
  write(path.join(home, ".dforge", "stores.json"), JSON.stringify({ [repo]: { project: "p", mirror: path.join(home, ".dforge", "mirror", "p"), documents: "local", progress: "local" } }));
  write(path.join(home, ".dforge", "mirror", "p", ".sync-state.json"), "{}\n");
  write(path.join(home, ".dagents", "config.json"), JSON.stringify({ layout: "auto" }));
  const dforgeBefore = snapshot(path.join(home, ".dforge"));
  assert.deepEqual(darkmemHeld({ HOME: home }, repo), []);
  const dry = migrateDforge({ HOME: home }, { root: repo, dryRun: true });
  assert.equal(dry.refused, 0, dry.lines.join("\n"));
  assert.deepEqual(json(path.join(home, ".dagents", "config.json")), { layout: "auto" });
  const { lines, refused } = migrateDforge({ HOME: home }, { root: repo });
  assert.equal(refused, 0, lines.join("\n"));
  assert.deepEqual(dry.lines.map(line => line.replace(/^would copy/, "copied")), lines);
  assert.deepEqual(json(path.join(home, ".dagents", "config.json")), { layout: "auto", handoffTokens: 325000 });
  assert.equal(fs.existsSync(path.join(home, ".dagents", "stores.json")), false);
  assert.equal(fs.existsSync(path.join(home, ".dagents", "mirror")), false);
  assert.deepEqual(snapshot(path.join(home, ".dforge")), dforgeBefore, "dforge's home is never changed");
});

test("a repository dforge never recorded copies nothing unless its checkout has the dforge layout", () => {
  const repo = makeRepo();
  const home = scratch("dagents-migrate-home-");
  write(path.join(home, ".dforge", "config.json"), JSON.stringify({ handoffTokens: 325000 }));
  assert.deepEqual(migrateDforge({ HOME: home }, { root: repo }), { lines: [], refused: 0 });
  assert.equal(fs.existsSync(path.join(home, ".dagents")), false);
  const { lines, refused } = migrateDforge({ HOME: home, DFORGE_LAYOUT: "x" }, { root: repo, layout: true });
  assert.equal(refused, 0, lines.join("\n"));
  assert.ok(lines.includes("DFORGE_LAYOUT is set in the environment; dagents reads DAGENTS_LAYOUT, so set that name for it"), lines.join("\n"));
  assert.deepEqual(json(path.join(home, ".dagents", "config.json")), { handoffTokens: 325000 });
});

test("migrateHome renames a ~/.dr-forge holding nothing for darkmem whole", () => {
  const home = scratch("dagents-migrate-home-");
  const forge = path.join(home, ".dr-forge");
  write(path.join(forge, "config.json"), JSON.stringify({ handoffTokens: 325000 }));
  write(path.join(forge, "notes.txt"), "n\n");
  const { lines, refused } = migrateHome({ HOME: home });
  assert.equal(refused, 0, lines.join("\n"));
  assert.deepEqual(lines, [`moved ${forge} to ${path.join(home, ".dagents")}`]);
  assert.equal(fs.existsSync(forge), false);
  assert.equal(json(path.join(home, ".dagents", "config.json")).handoffTokens, 325000);
  assert.deepEqual(migrateHome({ HOME: home }), { lines: [], refused: 0 });
});

test("migrateHome leaves ~/.dr-forge's mirror and stores.json in place and drops its darkmem settings", () => {
  const home = scratch("dagents-migrate-home-");
  const forge = path.join(home, ".dr-forge");
  const dagents = path.join(home, ".dagents");
  write(path.join(forge, "config.json"), JSON.stringify({ handoffTokens: 325000, darkmemEnabled: true, darkmem: { url: "http://127.0.0.1:9", repos: {} } }));
  write(path.join(forge, "stores.json"), JSON.stringify({ "/r": { project: "p", documents: "local", progress: "local" } }));
  write(path.join(forge, "mirror", "p", "forge", "a.md"), "a\n");
  write(path.join(forge, "only-old.txt"), "old\n");
  const { lines, refused } = migrateHome({ HOME: home });
  assert.equal(refused, 0, lines.join("\n"));
  assert.deepEqual(json(path.join(dagents, "config.json")), { handoffTokens: 325000 });
  assert.equal(read(path.join(dagents, "only-old.txt")), "old\n");
  assert.equal(read(path.join(forge, "mirror", "p", "forge", "a.md")), "a\n");
  assert.equal(fs.existsSync(path.join(forge, "stores.json")), true);
  assert.equal(fs.existsSync(path.join(dagents, "mirror")), false);
  assert.equal(fs.existsSync(path.join(dagents, "stores.json")), false);
  assert.equal(fs.existsSync(path.join(forge, "config.json")), false);
  assert.ok(lines.includes(`dropped darkmemEnabled, darkmem from ${path.join(forge, "config.json")}: dagents does not sync with darkmem`), lines.join("\n"));
  assert.ok(lines.includes(`left ${path.join(forge, "mirror")} in place; dagents keeps no darkmem mirror or stores`), lines.join("\n"));
  const again = migrateHome({ HOME: home });
  assert.equal(again.refused, 0);
  assert.ok(again.lines.every(line => line.startsWith("left ")), again.lines.join("\n"));
});

test("migrateHome writes config.json holding the home lock", t => {
  const home = scratch("dagents-migrate-home-");
  const dagents = path.join(home, ".dagents");
  write(path.join(home, ".dr-forge", "config.json"), JSON.stringify({ handoffTokens: 325000 }));
  write(path.join(dagents, "config.json"), JSON.stringify({ layout: "auto" }));
  const written = [];
  const writeFile = fs.writeFileSync;
  t.mock.method(fs, "writeFileSync", (file, ...rest) => {
    if (/^\.config\.json\./.test(path.basename(String(file)))) written.push(fs.existsSync(path.join(dagents, ".lock", ".sync.lock")) ? "locked" : "unlocked");
    return writeFile(file, ...rest);
  });
  const { lines, refused } = migrateHome({ HOME: home });
  assert.equal(refused, 0, lines.join("\n"));
  assert.deepEqual(written, ["locked"]);
});

test("migrateHome merges ~/.dr-forge into an existing ~/.dagents entry by entry, and refuses a clash", () => {
  const home = scratch("dagents-migrate-home-");
  const forge = path.join(home, ".dr-forge");
  const dagents = path.join(home, ".dagents");
  write(path.join(forge, "config.json"), JSON.stringify({ handoffTokens: 325000, layout: "auto" }));
  write(path.join(dagents, "config.json"), JSON.stringify({ layout: "auto" }));
  write(path.join(forge, "same.txt"), "same\n");
  write(path.join(dagents, "same.txt"), "same\n");
  write(path.join(forge, "only-old.txt"), "old\n");
  const { lines, refused } = migrateHome({ HOME: home });
  assert.equal(refused, 0, lines.join("\n"));
  assert.deepEqual(json(path.join(dagents, "config.json")), { layout: "auto", handoffTokens: 325000 });
  assert.equal(read(path.join(dagents, "only-old.txt")), "old\n");
  assert.equal(fs.existsSync(forge), false);

  write(path.join(forge, "config.json"), JSON.stringify({ handoffTokens: 1 }));
  const clash = migrateHome({ HOME: home });
  assert.equal(clash.refused, 1);
  assert.ok(clash.lines.some(line => line.startsWith("refused: ") && line.includes("set handoffTokens differently")), clash.lines.join("\n"));
  assert.equal(json(path.join(forge, "config.json")).handoffTokens, 1);
  assert.equal(json(path.join(dagents, "config.json")).handoffTokens, 325000);
});

test("migrateHome with dryRun writes nothing and lists every action the real run takes", () => {
  const home = scratch("dagents-migrate-home-");
  const forge = path.join(home, ".dr-forge");
  write(path.join(home, ".dagents", "config.json"), JSON.stringify({ layout: "auto" }));
  write(path.join(forge, "config.json"), JSON.stringify({ handoffTokens: 325000, darkmem: {} }));
  write(path.join(forge, "notes.txt"), "n\n");
  write(path.join(forge, "mirror", "p", "x"), "x\n");
  const before = snapshot(home);
  const dry = migrateHome({ HOME: home }, { dryRun: true });
  assert.equal(dry.refused, 0, dry.lines.join("\n"));
  assert.deepEqual(snapshot(home), before);
  const real = migrateHome({ HOME: home });
  assert.equal(real.refused, 0, real.lines.join("\n"));
  const done = line => line.replace(/^would merge/, "merged").replace(/^would drop/, "dropped").replace(/^would move/, "moved");
  assert.deepEqual([...dry.lines].map(done).sort(), [...real.lines].sort());
});

test("migrateHome refuses a ~/.dr-forge config.json that is not a JSON object once and still moves the other entries", () => {
  const home = scratch("dagents-migrate-home-");
  const forge = path.join(home, ".dr-forge");
  write(path.join(forge, "config.json"), "[1]");
  write(path.join(forge, "notes.txt"), "n\n");
  const { lines, refused } = migrateHome({ HOME: home });
  assert.equal(refused, 1, lines.join("\n"));
  assert.equal(read(path.join(forge, "config.json")), "[1]");
  assert.equal(read(path.join(home, ".dagents", "notes.txt")), "n\n");
});
