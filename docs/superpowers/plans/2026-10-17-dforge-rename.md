# dforge Rename Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: the skill the **Execution:** line names — dr-superpowers:subagent-driven-development for `subagent`, dr-superpowers:executing-plans for `inline`. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rename dr-forge to dforge with every internal `forge` name, rename the two `dcc-` UI plugins to `darkraise-ui` and `darkraise-win32ui`, and add a `dforge:migrate` skill over a widened `dforge-migrate` that moves dr-superpowers and dr-forge repositories and homes to the dforge names.

**Architecture:** Three node scripts make the mechanical renames: the UI plugins, then the `dr-forge` directory and name, then the internal `forge` names. Hand-written patches then widen the migration (darkmem prefixes, the home, the checkout layer, `--dry-run`), add the skill and the lines that point at it, extend the citation translators to `docs/forge/`, add the old-name guard, and finish the docs and versions. Every script and patch below is the prototype on branch `prototype/dforge-rename`, replayed on `main` in this task order and tested there.

**Tech Stack:** Bash scripts and shell test suites, Node.js ESM modules with `node:test`, the TypeScript cockpit mod (tested by `claude plugin test`), Markdown skills and docs, JSON manifests.

**Spec:** `docs/superpowers/specs/2026-10-17-dforge-rename-design.md`

**Execution:** subagent — `claude --model sonnet --effort high` — 8 of 14 tasks are heavy (Tasks 2, 3, 4, 5, 6, 7, 11 and 12, totals 5 and 6 or risk 3)

**Plan review:** 2026-10-17 — dr-superpowers:judge-opus — executability 14 / coherence 17 / coverage 15 / assumptions 14 (round 1)

**Parallelism:** sequential — the spec's Execution strategy is sequential: the renames share both catalogs, `CLAUDE.md`, the root `README.md`, `scripts/validate-repository.mjs` and `.github/workflows/validate.yml`, and every later task consumes the new names

## Global Constraints

- Work in a worktree branched from local `main` (local `main` runs ahead of `origin/main`): `git worktree add .claude/worktrees/dforge-rename -b dforge-rename main`. This plan and its register must be committed on local `main` first (dr-superpowers:handoff commits them), because every block is read from the plan file in the worktree: before Task 1, `ls docs/superpowers/plans/2026-10-17-dforge-rename.md` in the worktree must list the file, or stop. Do not merge to `main` before Task 14 is done (users install from `main`), and do not push.
- Never edit anything under `docs/superpowers/`: it is history. The rename scripts skip it, `docs/migration.md` (Task 14 edits it by patch) and, for Tasks 2 and 3, `.gitignore` (Task 3 edits it by exact text).
- dr-status keeps its internal `dcc-` names: the `DCC_*` variables, `scripts/dcc-statusline.schema.json`, `~/.claude/dcc-statusline/` and `~/.claude/dcc-statusline-installations.json`.
- Versions: dforge 4.0.0, `darkraise-ui` and `darkraise-win32ui` 0.3.0, each equal in its `.claude-plugin/plugin.json` and `.codex-plugin/plugin.json`; the Claude marketplace 0.7.0.
- **Applying a block (C1).** Every script and patch in this plan is a fenced block after a line `<!-- block: <id> -->`. From the worktree root, extract it to a file in your scratchpad directory (`<scratch>`; the session's system prompt names it, and when it names none, run `mktemp -d` once per task and use the directory it prints) with one command, then use the file in a second command. Never retype a block by hand.
- A block that does not apply, a script that throws, or an Expected result that differs is a stop: report BLOCKED with the command and its output. Never hand-edit a file to make a block apply or a check pass.
- Run each command on its own line; do not chain commands that mention git with `&&`, `;` or a pipe (the worktree guard refuses them).
- Run suites from the worktree root under a bound, with the host's `CLAUDE_CONFIG_DIR` removed: `env -u CLAUDE_CONFIG_DIR timeout 300 <command>`, except the whole suite, which takes CI's bound: `env -u CLAUDE_CONFIG_DIR timeout --kill-after=10s 690s node scripts/test-all.mjs`. In this host's Bash `claude` is a shell function that exits 127: call `/root/.local/bin/claude`.
- Commits: `<type>(<scope>): <subject>`, subject at most 50 characters, imperative, no period; author and committer `Darkraise <quangtc94@gmail.com>` (the repository's `user.name`/`user.email`); no `Co-Authored-By:`, `Claude-Session:` or "Generated with" line, nor any other AI attribution.
- After Task 2 a checkout that had ignored files under `plugins/dr-forge/` (`tsconfig.json`, `.claude-plugin/types/`) keeps them there: report the leftover directory, do not delete it.
- Stop every process a check starts; nothing in this plan starts a long-lived one.

## Contracts

- **C1 Block extraction.** `awk -v id=<id> '$0 == "<!-- block: " id " -->" { f = 1; next } f == 1 && /^````/ { f = 2; next } f == 2 && /^````/ { exit } f == 2' docs/superpowers/plans/2026-10-17-dforge-rename.md > <scratch>/<file>` writes block `<id>` byte for byte. A patch is then applied with `git apply --index <scratch>/<id>.patch`, which stages exactly the files it touches; a script runs with `node <scratch>/<id>.mjs`.
- **C2 Names (spec §1), from Task 3 on.** Plugin `plugins/dforge/`, name `dforge`, prefix `dforge:`, entry skill `using-dforge`; state `.dforge/`; docs `docs/dforge/`; git dir `<git dir>/dforge/`; home `~/.dforge/`; variables `DFORGE_*`; darkmem prefix `dforge` (`DOC_PREFIX`); scripts `scripts/dforge-config`, `scripts/dforge-migrate`, `scripts/dforge-path`; libraries `scripts/lib/dforge-config.mjs`, `dforge-dir.sh`, `dforge-env.sh`, `dforge-home-migrate.mjs`; shell functions `dforge_*`. UI plugins (Task 1): `plugins/darkraise-ui/`, `plugins/darkraise-win32ui/`.
- **C3 Home-migration module** `plugins/dforge/scripts/lib/dforge-home-migrate.mjs`. Task 4 exports `OLD_PREFIXES = [LEGACY_PREFIX, "forge"]` (`LEGACY_PREFIX` is `"superpowers"`) and makes `migrateMirror`, `legacyMirror`, `migrateMirrorLocked` and `migrateServer` handle both old prefixes, with the module-private helpers `oldPrefixOf(uri)`, `renamed(uri)` and `heldFolders(mirror)`. Task 5 makes it `migrateHome(env = process.env, { dryRun = false } = {})` answering `{ lines, refused }`, and the module's command line accepts `--dry-run`; each dry line starts `would `; each refusal line starts `refused: `.
- **C4 `scripts/dforge-migrate [--dry-run] [DIR]`.** Exit 0 done or nothing to do, 1 something refused (or, dry, predicted), 2 usage or not in a git repository. Stdout lines: `moved A -> B`, `rewrote the older names in F`, `rewrote the plugin prefixes in F`, `dforge-home-migrate: <line>`, `commit: <checkout>: <what to commit>`, `dforge-migrate: nothing to migrate in <root>`; dry: `would move A -> B`, `would drop A, the same as B`, `would rewrite the older names in F`, `would rewrite the plugin prefixes in F`, and no `commit:` line. Refusals go to stderr as `dforge-migrate: refused: <reason and fix>`. Task 6 widens the moves and adds the active-plan rewrite; Task 7 adds `--dry-run`.
- **C5 The migrate skill** `plugins/dforge/skills/migrate/SKILL.md`, name `migrate`, invoked as `dforge:migrate` (`/dforge:migrate` on Claude Code); routed from `skills/using-dforge/SKILL.md` by the row `| A repository or home on an older layout | dforge:migrate |`. Task 8.
- **C6 `dforge_legacy_layout [ROOT]`** in `scripts/lib/dforge-dir.sh` prints each older path, one per line: `~/.dr-superpowers` when unmigrated, `~/.dr-forge` while it holds anything, then ROOT's `.superpowers`, `.forge`, `docs/superpowers`, `docs/forge`, the git dir's `dr-superpowers` and `dr-forge`, and a linked worktree's primary `.superpowers` and `.forge`. Task 9.
- **C7 The layout line.** `dforge: this repository still uses an older layout (<paths, comma-separated>); run the dforge:migrate skill (/dforge:migrate)`, printed by `scripts/session-start.sh` and, after `- `, by `scripts/repo-audit`. Task 10.

## Assumptions (evidence)

- **The patches are the tested prototype.** On 2026-10-17 the three rename scripts and the prototype's hand-written commits were applied to `main` at `3ff1a68` in this plan's task order, in a scratch worktree, one commit per task. Every block applied cleanly, and the result equals the prototype's last code commit (`e4ea31b`) except the intended changes listed here and in the Task 5 bullet below: `evals/tiers/README.md` says `dforge 4.0.0` (the `plugins/dforge` path first exists in 4.0.0; the prototype kept `2.0.0`), `tests/review-route.test.sh` expects `4.0.0` manifests, and `tests/hook.test.sh` greps the exact layout line (next bullet). Each block in this plan is `git diff` of that replay, generated, not retyped.
- **`hook.test.sh` "4.0 layout: no migration line" failed in the prototype for a real reason**, not flakiness: it ran `grep -c 'older layout'` over the session context, and that context includes `using-dforge/SKILL.md`, whose Task 8 routing row says "on an older layout". It failed alone as well as under `test-all` (run 2026-10-17 on the replay). Task 10's test greps `still uses an older layout`, the line itself; with that, `hook.test.sh` passes 69 of 69.
- **Each task's tests fail first, then pass.** On the replay, for Tasks 4 to 14, the task's test files applied alone to the previous task's commit failed, and the full task passed: results are quoted in each task's Expected lines (run 2026-10-17).
- **The full suite passes on the replay.** `node scripts/test-all.mjs` ran 54 jobs; before the hook-test fix 53 passed, with `hook.test.sh` the only failure; with every change in this plan applied, all 54 jobs pass and `test-all.mjs` exits 0 (run 2026-10-17). The whole suite (53 jobs there, `claude plugin test` among them; Task 8's new suite makes 54) also exits 0 at the replayed commits of Tasks 1, 2 and 3, so each rename leaves the tree green (run 2026-10-17).
- `main` (`3ff1a68`) differs from the prototype's base (`e8c1da7`) only under `docs/superpowers/` (`git diff --stat e8c1da7 main`, 2026-10-17), which no task edits.
- The guard check of Task 2 and Task 3 uses `git grep -P`; PCRE works in this host's git (run 2026-10-17: the Task 3 check finds 117 files before the rename and none after).
- New suites under `plugins/dforge/tests/*.test.sh` are collected by `scripts/test-all.mjs` from the directory listing (`scripts/test-all.mjs`, the `readdirSync(... 'plugins/dforge/tests')` job), so Task 8's `migrate-skill.test.sh` needs no registration. `scripts/test-shards.mjs` names no test file (it only shards the job list).
- The spec's riskiest assumption (a renamed plugin is a new plugin, so the uninstall note is the whole client-side migration): dr-forge never reads `CLAUDE_PLUGIN_DATA`; its one mention, `scripts/lib/codex-client.mjs:180`, is a comment on how the Codex broker keys its sessions. Inference: under the new plugin name a broker dr-forge left is not reused, which costs one broker start and nothing else.
- **Deviation from spec §7, kept from the prototype:** the dr-forge guard exempts every file under `plugins/dforge/tests/` and `plugins/dforge/LICENSES/` (the spec says "the tests for these"), as the existing superpowers guard does; it does not list `reference/project-state.md`, which holds no retired name after Task 3 (the validator passes on the replay); and the `dcc-darkraise` sweep also exempts `scripts/validate-repository.mjs` and `tests/repository-layout.test.mjs`, which must spell the pattern they check.
- `dforge-migrate` rewrites an older prefix only before a skill or agent name (`dr-forge:impl-sonnet-low`), as the spec says; a bare prefix in prose (`` `dr-superpowers:` agents``) is left. The end-to-end run in Task 14 counts only prefixed names, and the migrated plan passes `plan-lint` (run 2026-10-17 on the replay).
- **A fix beyond the prototype, Task 5:** plan review round 1 found that a dry run merging `~/.dr-forge` into an existing `~/.dforge` (which a first dforge session creates) did not list the `stores.json` repointing or the mirror's folder rename. Task 5 now reads each new-home path, in a dry run, from the old entry an earlier line would move there, and adds a test that the dry run's actions equal the real run's. On the replay the end-to-end dry run then lists all fourteen actions and changes no file (run 2026-10-17). Task 13's test table also gained four fixtures (`docs/forge/`, `.dr-forge`, `forge_dir`, `$FORGE_HOME`).
- The uninstall commands the migrate skill names exist: `claude plugin --help` (Claude Code 2.1.302) lists `uninstall|remove [options] <plugin>`, and `codex plugin --help` (codex-cli 0.160.1) lists `remove  Uninstall a plugin and remove its local cache` (run 2026-10-17).
- Task 14's end-to-end script uses `jq` (`/usr/bin/jq` on this host, also required by the existing `hook.test.sh`) and `cksum`.
- Codex lane: `codex-gate usable=false reason=plugin-not-enabled review=false lane=false resets_at=- source=probe` (2026-10-17), so no task carries an `**Executor:**` line.
- The installed tooling is dr-superpowers 1.34.1, so this plan's `**Implementer:**` lines name `dr-superpowers:` agents; the code it changes names `dforge:`.

## Task index

1. Rename the dcc- UI plugins
2. Rename the dr-forge plugin to dforge
3. Rename the forge internals to dforge
4. Move forge/ darkmem documents and mirrors to dforge/
5. Migrate the ~/.dr-forge home
6. Migrate dr-forge checkouts and active plans
7. Add dforge-migrate --dry-run
8. Add the migrate skill
9. Detect the dr-forge layout
10. Point the layout line at /dforge:migrate
11. Read docs/forge citations in roots.sh and the cockpit
12. Read docs/forge citations in darkmem
13. Guard against the retired names
14. Document the 4.0 migration and release

---

### Task 1: Rename the dcc- UI plugins

**Files:**
- Move: `plugins/dcc-darkraise-ui/` → `plugins/darkraise-ui/`, `plugins/dcc-darkraise-win32ui/` → `plugins/darkraise-win32ui/` (`git mv`, by the script)
- Modify (by the script): every tracked file outside `docs/superpowers/` and `docs/migration.md` that names `dcc-darkraise-ui` or `dcc-darkraise-win32ui`: `.agents/plugins/marketplace.json`, `.claude-plugin/marketplace.json`, `.github/ISSUE_TEMPLATE/bug_report.yml`, `.github/ISSUE_TEMPLATE/feature_request.yml`, `.github/workflows/validate.yml`, `CLAUDE.md`, `CONTRIBUTING.md`, `README.md`, `docs/testing/dual-client-marketplace-validation.md`, `scripts/validate-repository.mjs`, `tests/marketplace-smoke.ps1`, `tests/repository-layout.test.mjs`, `tests/ui-discovery.test.mjs`, and the plugins' own files
- Modify (by the script): both manifests of each UI plugin, `"version": "0.2.1"` → `"version": "0.3.0"`

**Interfaces:**
- Consumes: C1.
- Produces: the UI plugin names in C2.

**Items:** 3
**Implementer:** dr-superpowers:impl-sonnet-medium
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 1 = 3

- [ ] **Step 1: Confirm the old names are present**

Run: `git grep -n -e dcc-darkraise -- . ':!docs/superpowers' ':!docs/migration.md'`
Expected: matching lines, exit 0.

- [ ] **Step 2: Extract the script**

Run C1 with id `rename-ui`, writing `<scratch>/rename-ui.mjs`.

<!-- block: rename-ui -->
````js
import { execFileSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";

for (const name of ["darkraise-ui", "darkraise-win32ui"]) execFileSync("git", ["mv", `plugins/dcc-${name}`, `plugins/${name}`]);
const files = execFileSync("git", ["ls-files", "-z"], { encoding: "utf8", maxBuffer: 1 << 26 }).split("\0").filter(Boolean);
const skip = rel => rel.startsWith("docs/superpowers/") || rel === "docs/migration.md";
let rewrote = 0;
for (const rel of files) {
  if (skip(rel) || fs.lstatSync(rel).isSymbolicLink()) continue;
  const buffer = fs.readFileSync(rel);
  if (buffer.includes(0)) continue;
  const before = buffer.toString("utf8");
  const after = before
    .replace(/dcc-darkraise-(ui|win32ui)/g, "darkraise-$1")
    .replaceAll("../plugins/dcc-${name}/skills/${name}/SKILL.md", "../plugins/${name}/skills/${name}/SKILL.md");
  if (after !== before) {
    fs.writeFileSync(rel, after);
    rewrote++;
  }
}
for (const name of ["darkraise-ui", "darkraise-win32ui"]) {
  for (const client of [".claude-plugin", ".codex-plugin"]) {
    const file = path.join("plugins", name, client, "plugin.json");
    const text = fs.readFileSync(file, "utf8");
    if (!text.includes('"version": "0.2.1"')) throw new Error(`${file}: version is not 0.2.1`);
    fs.writeFileSync(file, text.replace('"version": "0.2.1"', '"version": "0.3.0"'));
  }
}
console.log(`rename-ui: rewrote ${rewrote}`);
````

- [ ] **Step 3: Run it from the worktree root**

Run: `node <scratch>/rename-ui.mjs`
Expected: `rename-ui: rewrote 21`

- [ ] **Step 4: Check the result**

Run: `git grep -n -e dcc-darkraise -- . ':!docs/superpowers' ':!docs/migration.md'`
Expected: no output, exit 1.

Run: `node scripts/validate-repository.mjs`
Expected: exit 0, no error lines.

Run: `env -u CLAUDE_CONFIG_DIR timeout 300 node --test tests/repository-layout.test.mjs tests/ui-discovery.test.mjs tests/test-shards.test.mjs`
Expected: `ℹ fail 0`.

Run: `timeout 90 /root/.local/bin/claude plugin validate plugins/darkraise-ui`, then the same for `plugins/darkraise-win32ui`, then `timeout 90 /root/.local/bin/claude plugin validate .`
Expected: each passes.

- [ ] **Step 5: Commit**

Run: `git add -u`
Run: `git status --short`
Expected: only staged `R` and `M` lines, no `??` line.

```bash
git commit -m "refactor(ui): drop the dcc- prefix from the UI plugins"
```

### Task 2: Rename the dr-forge plugin to dforge

**Files:**
- Move (by the script): every tracked path outside `docs/superpowers/`, `docs/migration.md` and `.gitignore` containing `dr-forge`, chiefly `plugins/dr-forge/` → `plugins/dforge/` (259 paths)
- Modify (by the script): every such file whose text names `dr-forge` (180 files), including both catalogs, `CLAUDE.md`, `README.md`, `CONTRIBUTING.md`, `.github/`, `scripts/validate-repository.mjs`, `scripts/test-shards.mjs`, `tests/`, the dr-status README and every file in the plugin. A dated plan or spec name (`2026-10-12-dr-forge-settings`) is history and keeps its spelling.

**Interfaces:**
- Consumes: C1.
- Produces: `plugins/dforge/`, the name `dforge` and the prefix `dforge:` (C2).

**Items:** 1
**Implementer:** dr-superpowers:impl-sonnet-high
**Evaluation:** files 1 - spec 0 - coupling 2 - risk 2 = 5

- [ ] **Step 1: Confirm the old name is present**

Run: `git grep -c -P '(?<!\d{4}-\d{2}-\d{2}-)dr-forge' -- . ':!docs/superpowers' ':!docs/migration.md' ':!.gitignore'`
Expected: one count line per file, exit 0.

- [ ] **Step 2: Extract the script**

Run C1 with id `rename-1`, writing `<scratch>/rename-1.mjs`.

<!-- block: rename-1 -->
````js
import { execFileSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";

const files = execFileSync("git", ["ls-files", "-z"], { encoding: "utf8", maxBuffer: 1 << 26 }).split("\0").filter(Boolean);
const skip = rel => rel.startsWith("docs/superpowers/") || rel === ".gitignore" || rel === "docs/migration.md";
const KEEP = "\u0001KEEP\u0001";
const prune = dir => { while (dir && dir !== ".") { try { fs.rmdirSync(dir); } catch { return; } dir = path.dirname(dir); } };
const rename = s => s
  .replace(/(\d{4}-\d{2}-\d{2})-dr-forge/g, `$1-${KEEP}`)
  .replace(/dr-forge/g, "dforge")
  .replaceAll(KEEP, "dr-forge");
let moved = 0, rewrote = 0;
for (const rel of files) {
  if (skip(rel)) continue;
  const to = rename(rel);
  if (to !== rel) {
    fs.mkdirSync(path.dirname(to), { recursive: true });
    execFileSync("git", ["mv", rel, to]);
    prune(path.dirname(rel));
    moved++;
  }
  if (fs.lstatSync(to).isSymbolicLink()) continue;
  const buffer = fs.readFileSync(to);
  if (buffer.includes(0)) continue;
  const before = buffer.toString("utf8");
  const after = rename(before);
  if (after !== before) {
    fs.writeFileSync(to, after);
    rewrote++;
  }
}
console.log(`rename-1: moved ${moved}, rewrote ${rewrote}`);
````

- [ ] **Step 3: Run it from the worktree root**

Run: `node <scratch>/rename-1.mjs`
Expected: `rename-1: moved 259, rewrote 180`

- [ ] **Step 4: Check the result**

Run: `git grep -n -P '(?<!\d{4}-\d{2}-\d{2}-)dr-forge' -- . ':!docs/superpowers' ':!docs/migration.md' ':!.gitignore'`
Expected: no output, exit 1.

Run: `ls plugins`
Expected: `darkraise-ui`, `darkraise-win32ui`, `dforge`, `dr-status`, and no `dr-forge` (if `plugins/dr-forge/` remains holding only ignored files, report it and leave it).

Run: `env -u CLAUDE_CONFIG_DIR timeout --kill-after=10s 690s node scripts/test-all.mjs`
Expected: exit 0, and no line `Finished ... (exit 1)`.

- [ ] **Step 5: Commit**

Run: `git add -u`
Run: `git status --short`
Expected: only staged `R` and `M` lines, no `??` line.

```bash
git commit -m "refactor(dforge): rename the dr-forge plugin to dforge"
```

### Task 3: Rename the forge internals to dforge

**Files:**
- Move (by the script): `plugins/dforge/scripts/forge-config`, `forge-migrate`, `forge-path` → `dforge-config`, `dforge-migrate`, `dforge-path`; `scripts/lib/forge-config.mjs`, `forge-dir.sh`, `forge-env.sh` → `dforge-config.mjs`, `dforge-dir.sh`, `dforge-env.sh`; `scripts/lib/darkmem-migrate.mjs` → `scripts/lib/dforge-home-migrate.mjs`; `skills/using-forge/` → `skills/using-dforge/` (two files); `tests/forge-config.test.sh`, `forge-dir.test.sh`, `forge-migrate.test.sh`, `forge-state.test.sh` → `tests/dforge-*.test.sh`
- Modify (by the script): every tracked file outside `docs/superpowers/`, `docs/migration.md` and `.gitignore` naming `forge`, `Forge`, `FORGE`, `DR_FORGE` or `darkmem-migrate` as a code name (118 files)
- Modify (by the script, exact text): `evals/tiers/lib/cases.mjs` (`slug` strips both the `dr-forge-` and `dforge-` plan prefixes), `evals/tiers/README.md` (`before dforge 4.0.0`), `.gitignore` (the agent scratch block ignores `.dforge/` and keeps `.forge/`)

**Interfaces:**
- Consumes: C1, the names Task 2 produced.
- Produces: every name in C2.

**Items:** 1
**Implementer:** dr-superpowers:impl-sonnet-high
**Evaluation:** files 1 - spec 0 - coupling 2 - risk 2 = 5

- [ ] **Step 1: Confirm the internal names are present**

Run: `git grep -c -P '(?<![A-Za-z0-9d])(?<!\d{4}-\d{2}-\d{2}-dr-)forge(?![a-z])|(?<!D)FORGE' -- . ':!docs/superpowers' ':!docs/migration.md' ':!.gitignore' ':!evals/tiers/lib/cases.mjs'`
Expected: 117 count lines, exit 0.

- [ ] **Step 2: Extract the script**

Run C1 with id `rename-2`, writing `<scratch>/rename-2.mjs`.

<!-- block: rename-2 -->
````js
import { execFileSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";

const files = execFileSync("git", ["ls-files", "-z"], { encoding: "utf8", maxBuffer: 1 << 26 }).split("\0").filter(Boolean);
const skip = rel => rel.startsWith("docs/superpowers/") || rel === ".gitignore" || rel === "docs/migration.md";
const KEEP = "\u0001KEEP\u0001";
const prune = dir => { while (dir && dir !== ".") { try { fs.rmdirSync(dir); } catch { return; } dir = path.dirname(dir); } };
const VALIDATOR_OLD = String.raw`darkmem-(?:sync|migrate|mirror|reconcile)\.mjs`;
const VALIDATOR_NEW = String.raw`(?:darkmem-(?:sync|mirror|reconcile)|dforge-home-migrate)\.mjs`;
const rename = s => s
  .replace(/(\d{4}-\d{2}-\d{2})-dr-forge/g, `$1-${KEEP}`)
  .replaceAll(VALIDATOR_OLD, VALIDATOR_NEW)
  .replace(/darkmem-migrate/g, "dforge-home-migrate")
  .replace(/DR_FORGE/g, "DFORGE")
  .replace(/(?<!D)FORGE/g, "DFORGE")
  .replace(/(?<!D)Forge(?![a-z])/g, "Dforge")
  .replace(/\\u0000forge/g, "\\u0000dforge")
  .replace(/(?<![A-Za-z0-9d])forge(?![a-z])/g, "dforge")
  .replaceAll(KEEP, "dr-forge");
let moved = 0, rewrote = 0;
for (const rel of files) {
  if (skip(rel)) continue;
  const to = rename(rel);
  if (to !== rel) {
    fs.mkdirSync(path.dirname(to), { recursive: true });
    execFileSync("git", ["mv", rel, to]);
    prune(path.dirname(rel));
    moved++;
  }
  if (fs.lstatSync(to).isSymbolicLink()) continue;
  const buffer = fs.readFileSync(to);
  if (buffer.includes(0)) continue;
  const before = buffer.toString("utf8");
  const after = rename(before);
  if (after !== before) {
    fs.writeFileSync(to, after);
    rewrote++;
  }
}
// The forge rule cannot tell a historical name from a live one in these two.
const fixups = [
  ["evals/tiers/lib/cases.mjs", ".replace(/^dr-(?:superpowers|dforge)-/, '')", ".replace(/^(?:dr-(?:superpowers|forge)|dforge)-/, '')"],
  ["evals/tiers/README.md", "A manifest built before dforge 2.0.0 names a start commit without `plugins/dforge`", "A manifest built before dforge 4.0.0 names a start commit without `plugins/dforge`"],
];
for (const [file, from, to] of fixups) {
  const content = fs.readFileSync(file, "utf8");
  if (content.split(from).length !== 2) throw new Error(`${file}: the text to fix is not there exactly once`);
  fs.writeFileSync(file, content.split(from).join(to));
}
const ignore = fs.readFileSync(".gitignore", "utf8");
const block = "# dr-forge agent scratch (ledgers, briefs, review packages); .superpowers/ before 2.0\n.forge/\n";
if (!ignore.includes(block)) throw new Error(".gitignore: the agent scratch block is not as expected");
fs.writeFileSync(".gitignore", ignore.replace(block,
  "# dforge agent scratch (ledgers, briefs, review packages); .forge/ before 4.0, .superpowers/ before 2.0\n.dforge/\n.forge/\n"));
console.log(`rename-2: moved ${moved}, rewrote ${rewrote}`);
````

- [ ] **Step 3: Run it from the worktree root**

Run: `node <scratch>/rename-2.mjs`
Expected: `rename-2: moved 13, rewrote 118`

- [ ] **Step 4: Check the result**

Run the Step 1 command again.
Expected: no output, exit 1.

Run: `sed -n '14,17p' .gitignore`
Expected exactly:

```
# dforge agent scratch (ledgers, briefs, review packages); .forge/ before 4.0, .superpowers/ before 2.0
.dforge/
.forge/
.superpowers/
```

Run: `env -u CLAUDE_CONFIG_DIR timeout --kill-after=10s 690s node scripts/test-all.mjs`
Expected: exit 0, and no line `Finished ... (exit 1)`.

- [ ] **Step 5: Commit**

Run: `git add -u`
Run: `git status --short`
Expected: only staged `R` and `M` lines, no `??` line.

```bash
git commit -m "refactor(dforge): rename the forge internals to dforge"
```

### Task 4: Move forge/ darkmem documents and mirrors to dforge/

**Files:**
- Modify: `plugins/dforge/scripts/lib/dforge-home-migrate.mjs` (`OLD_PREFIXES`, `migrateMirror`, `legacyMirror`, `migrateMirrorLocked`, `migrateServer`)
- Modify: `plugins/dforge/scripts/lib/darkmem-mirror.mjs` (`loadState` accepts the `forge` prefix dr-forge recorded)
- Modify: `plugins/dforge/scripts/lib/darkmem-sync.mjs` (the server move runs while `state.prefix` is not `dforge`)
- Test: `plugins/dforge/tests/darkmem-sync/migrate.test.mjs`

**Interfaces:**
- Consumes: C1, C2.
- Produces: C3's `OLD_PREFIXES` and the two-prefix mirror and server moves.

**Items:** 1
**Implementer:** dr-superpowers:impl-opus-high
**Evaluation:** files 2 - spec 0 - coupling 1 - risk 3 = 6

- [ ] **Step 1: Write the failing tests**

Run C1 with id `t4-tests`, writing `<scratch>/t4-tests.patch`, then `git apply --index <scratch>/t4-tests.patch`.

<!-- block: t4-tests -->
````diff
diff --git a/plugins/dforge/tests/darkmem-sync/migrate.test.mjs b/plugins/dforge/tests/darkmem-sync/migrate.test.mjs
index b622a7d..65f7559 100644
--- a/plugins/dforge/tests/darkmem-sync/migrate.test.mjs
+++ b/plugins/dforge/tests/darkmem-sync/migrate.test.mjs
@@ -47,7 +47,7 @@ test("a name darkmem holds under both prefixes refuses push and pull, and is nev
   for (const command of ["pull", "push"]) {
     const result = await s.sync(command);
     assert.equal(result.code, 2, result.stdout + result.stderr);
-    assert.match(result.stderr, new RegExp(`${command} refused: darkmem still holds pre-3\\.0 superpowers/ documents`));
+    assert.match(result.stderr, new RegExp(`${command} refused: darkmem still holds superpowers/ or forge/ documents`));
     assert.match(result.stdout, /^failed: superpowers\/a\.md: darkmem also holds dforge\/a\.md with other content; keep one$/m);
   }
   assert.equal(s.stub.db.documents.get("proj\u0000dforge/a.md").content, "new\n");
@@ -64,17 +64,59 @@ test("reconcile still moves a family back from the mirror while darkmem's uris c
   write(path.join(s.docsRoot, "b.md"), "b\n");
   const result = await s.sync("reconcile");
   assert.equal(result.code, 1, result.stdout + result.stderr);
-  assert.match(result.stdout, /^darkmem-sync reconcile: documents moved to local from the mirror, without darkmem \(darkmem still holds pre-3\.0 superpowers\/ documents/m);
+  assert.match(result.stdout, /^darkmem-sync reconcile: documents moved to local from the mirror, without darkmem \(darkmem still holds superpowers\/ or forge\/ documents/m);
   assert.equal(read(path.join(s.repo, "docs", "dforge", "b.md")), "b\n");
 });
 
+test("a dr-forge mirror and darkmem's forge/ documents move to dforge/, even after the 3.0 move", async t => {
+  const s = await setup(t);
+  await s.seed.putDocument({ project: "proj", uri: "forge/specs/a.md", content: "# A\n" });
+  await s.seed.putDocument({ project: "proj", uri: "forge/archive/20260101T000000Z/old.md", content: "old\n" });
+  write(path.join(s.mirror, "forge", "specs", "a.md"), "# A\n");
+  write(path.join(s.mirror, ".sync-state.json"), JSON.stringify({
+    version: 1, documents: { "forge/specs/a.md": sha("# A\n") }, ledgers: {}, checkpoint: null, checkpointAt: null, conflicts: [], pendingLinks: [], prefix: "forge",
+  }));
+  const result = await s.sync("pull");
+  assert.equal(result.code, 0, result.stdout + result.stderr);
+  assert.match(result.stdout, /renamed .*'s forge\/ to dforge\//);
+  assert.equal(read(path.join(s.docsRoot, "specs", "a.md")), "# A\n");
+  assert.equal(fs.existsSync(path.join(s.mirror, "forge")), false);
+  const uris = [...s.stub.db.documents.keys()].map(key => key.split("\u0000")[1]).sort();
+  assert.deepEqual(uris, ["dforge/archive/20260101T000000Z/old.md", "dforge/specs/a.md"]);
+  const state = JSON.parse(read(path.join(s.mirror, ".sync-state.json")));
+  assert.deepEqual(Object.keys(state.documents), ["dforge/specs/a.md"]);
+  assert.equal(state.prefix, "dforge");
+});
+
+test("one name under superpowers/ and forge/ moves once; the second is refused, never overwritten", async t => {
+  const s = await setup(t);
+  await s.seed.putDocument({ project: "proj", uri: "superpowers/a.md", content: "old\n" });
+  await s.seed.putDocument({ project: "proj", uri: "forge/a.md", content: "new\n" });
+  const result = await s.sync("pull");
+  assert.equal(result.code, 2, result.stdout + result.stderr);
+  assert.match(result.stdout, /^failed: forge\/a\.md: darkmem also holds dforge\/a\.md with other content; keep one$/m);
+  assert.equal(s.stub.db.documents.get("proj\u0000dforge/a.md").content, "old\n");
+  assert.equal(s.stub.db.documents.get("proj\u0000forge/a.md").content, "new\n");
+});
+
+test("a mirror holding two docs folders is refused before anything syncs", async t => {
+  const s = await setup(t);
+  write(path.join(s.mirror, "forge", "a.md"), "a\n");
+  write(path.join(s.mirror, "dforge", "b.md"), "b\n");
+  const result = await s.sync("pull");
+  assert.equal(result.code, 2, result.stdout + result.stderr);
+  assert.match(result.stderr, /holds forge\/ and dforge\/; move all but one aside/);
+  assert.equal(read(path.join(s.mirror, "forge", "a.md")), "a\n");
+  assert.equal(s.stub.db.requests.length, 0);
+});
+
 test("a held lock on a pre-3.0 mirror refuses the command and changes nothing", async t => {
   const s = await setup(t);
   write(path.join(s.mirror, "superpowers", "a.md"), "a\n");
   fs.mkdirSync(path.join(s.mirror, ".sync.lock"), { recursive: true });
   const result = await s.sync("pull");
   assert.equal(result.code, 1);
-  assert.match(result.stderr, /^darkmem-sync: pull refused: .* is still in the pre-3\.0 layout and another darkmem-sync holds its lock/);
+  assert.match(result.stderr, /^darkmem-sync: pull refused: .* is still in an older layout and another darkmem-sync holds its lock/);
   assert.equal(fs.existsSync(s.docsRoot), false);
   assert.equal(s.stub.db.requests.length, 0);
 });
````

- [ ] **Step 2: Run the tests to verify they fail**

Run: `env -u CLAUDE_CONFIG_DIR timeout 300 node --test plugins/dforge/tests/darkmem-sync/migrate.test.mjs`
Expected: FAIL — `ℹ tests 9`, `ℹ pass 3`, `ℹ fail 6`, among them `a dr-forge mirror and darkmem's forge/ documents move to dforge/, even after the 3.0 move` and `a mirror holding two docs folders is refused before anything syncs`.

- [ ] **Step 3: Write the implementation**

Run C1 with id `t4-impl`, writing `<scratch>/t4-impl.patch`, then `git apply --index <scratch>/t4-impl.patch`.

<!-- block: t4-impl -->
````diff
diff --git a/plugins/dforge/scripts/lib/darkmem-mirror.mjs b/plugins/dforge/scripts/lib/darkmem-mirror.mjs
index 63f409b..6e126a7 100644
--- a/plugins/dforge/scripts/lib/darkmem-mirror.mjs
+++ b/plugins/dforge/scripts/lib/darkmem-mirror.mjs
@@ -181,7 +181,8 @@ export function loadState(file) {
     && (raw.checkpointAt === null || (typeof raw.checkpointAt === "string" && !Number.isNaN(Date.parse(raw.checkpointAt))))
     && Array.isArray(raw.conflicts) && raw.conflicts.every(line => typeof line === "string")
     && (raw.pendingLinks === undefined || (Array.isArray(raw.pendingLinks) && raw.pendingLinks.every(uri => typeof uri === "string")))
-    && (raw.prefix === undefined || raw.prefix === DOC_PREFIX);
+    // dr-forge recorded forge; migrateServer moves its documents on and records dforge.
+    && (raw.prefix === undefined || raw.prefix === DOC_PREFIX || raw.prefix === "forge");
   if (!valid) throw new StateError(`${file} does not hold a valid sync state; ${REBUILD}`);
   const state = {
     version: 1, documents, ledgers, checkpoint: raw.checkpoint, checkpointAt: raw.checkpointAt, conflicts: raw.conflicts,
diff --git a/plugins/dforge/scripts/lib/darkmem-sync.mjs b/plugins/dforge/scripts/lib/darkmem-sync.mjs
index 2fe5dda..411d8af 100644
--- a/plugins/dforge/scripts/lib/darkmem-sync.mjs
+++ b/plugins/dforge/scripts/lib/darkmem-sync.mjs
@@ -290,11 +290,11 @@ async function main(argv, {
     // the command may not sync, or null. Reconcile calls it after its own
     // refusals and still moves a family back to the checkout, from the mirror.
     const migrate = async () => {
-      if (!cfg.enabled || !cfg.url || !cfg.apiKey || state.prefix !== undefined) return null;
+      if (!cfg.enabled || !cfg.url || !cfg.apiKey || state.prefix === DOC_PREFIX) return null;
       const failures = await migrateServer({ cfg, client, state, persist });
       if (!failures.length) return null;
       report.failures.push(...failures);
-      return `darkmem still holds pre-3.0 superpowers/ documents it could not move to ${DOC_PREFIX}/`;
+      return `darkmem still holds superpowers/ or forge/ documents it could not move to ${DOC_PREFIX}/`;
     };
     if (parsed.command.needsKey) {
       const blocked = await migrate();
diff --git a/plugins/dforge/scripts/lib/dforge-home-migrate.mjs b/plugins/dforge/scripts/lib/dforge-home-migrate.mjs
index d45b0df..7546e67 100644
--- a/plugins/dforge/scripts/lib/dforge-home-migrate.mjs
+++ b/plugins/dforge/scripts/lib/dforge-home-migrate.mjs
@@ -1,7 +1,8 @@
-// The move from dforge's pre-3.0 darkmem names to its own: the home
-// ~/.dr-superpowers/ to ~/.dforge/, a mirror's superpowers/ folder and sync
-// state uris to dforge/, and darkmem's superpowers/ documents to dforge/. The
-// only module besides the document-name translation that reads the old names.
+// The moves from dforge's older darkmem names to its own: the homes
+// ~/.dr-superpowers/ and ~/.dr-forge/ to ~/.dforge/, a mirror's superpowers/
+// or forge/ folder and sync state uris to dforge/, and darkmem's superpowers/
+// and forge/ documents to dforge/. The only module besides the document-name
+// translation that reads the old names.
 import fs from "node:fs";
 import os from "node:os";
 import path from "node:path";
@@ -9,24 +10,29 @@ import { fileURLToPath } from "node:url";
 import { HttpError } from "./darkmem-client.mjs";
 import { DOC_PREFIX, LEGACY_PREFIX, StateError, acquireLock, loadState, saveState } from "./darkmem-mirror.mjs";
 
-const OLD = `${LEGACY_PREFIX}/`;
-const renamed = uri => (uri.startsWith(OLD) ? `${DOC_PREFIX}/${uri.slice(OLD.length)}` : uri);
+// dr-superpowers wrote superpowers/, dr-forge forge/.
+export const OLD_PREFIXES = [LEGACY_PREFIX, "forge"];
+const oldPrefixOf = uri => OLD_PREFIXES.find(prefix => String(uri).startsWith(`${prefix}/`));
+const renamed = uri => {
+  const prefix = oldPrefixOf(uri);
+  return prefix ? `${DOC_PREFIX}/${uri.slice(prefix.length + 1)}` : uri;
+};
+const heldFolders = mirror => [...OLD_PREFIXES, DOC_PREFIX].filter(prefix => fs.existsSync(path.join(mirror, prefix)));
 
 // A mirror's local half: the docs folder and every uri its state records.
-// Returns whether anything changed; a mirror holding both folders throws.
+// Returns whether anything changed; a mirror holding two docs folders throws.
 export function migrateMirror(mirror, state) {
   let changed = false;
-  const old = path.join(mirror, LEGACY_PREFIX);
-  const next = path.join(mirror, DOC_PREFIX);
-  if (fs.existsSync(old)) {
-    if (fs.existsSync(next)) throw new StateError(`${mirror} holds both ${LEGACY_PREFIX}/ and ${DOC_PREFIX}/; move one aside`);
-    fs.renameSync(old, next);
+  const held = heldFolders(mirror);
+  if (held.length > 1) throw new StateError(`${mirror} holds ${held.map(prefix => `${prefix}/`).join(" and ")}; move all but one aside`);
+  if (held.length === 1 && held[0] !== DOC_PREFIX) {
+    fs.renameSync(path.join(mirror, held[0]), path.join(mirror, DOC_PREFIX));
     changed = true;
   }
   const documents = Object.create(null);
   for (const [uri, hash] of Object.entries(state.documents)) {
     documents[renamed(uri)] = hash;
-    if (uri.startsWith(OLD)) changed = true;
+    if (oldPrefixOf(uri)) changed = true;
   }
   state.documents = documents;
   const links = state.pendingLinks.map(renamed);
@@ -35,9 +41,9 @@ export function migrateMirror(mirror, state) {
   return changed;
 }
 
-// A pre-3.0 mirror: its old folder, or an old uri its state records.
+// A mirror in an older layout: an old folder, or an old uri its state records.
 export function legacyMirror(mirror) {
-  if (fs.existsSync(path.join(mirror, LEGACY_PREFIX))) return true;
+  if (OLD_PREFIXES.some(prefix => fs.existsSync(path.join(mirror, prefix)))) return true;
   let raw;
   try {
     raw = JSON.parse(fs.readFileSync(path.join(mirror, ".sync-state.json"), "utf8"));
@@ -45,47 +51,51 @@ export function legacyMirror(mirror) {
     return false;
   }
   const uris = [...Object.keys(raw?.documents ?? {}), ...(Array.isArray(raw?.pendingLinks) ? raw.pendingLinks : [])];
-  return uris.some(uri => String(uri).startsWith(OLD));
+  return uris.some(uri => oldPrefixOf(uri) !== undefined);
 }
 
 // The local half under the mirror's lock, for a caller that holds none.
 // Answers { line, blocked } saying what happened, or null when nothing needed
-// doing; blocked: a held lock left the mirror in the pre-3.0 layout.
+// doing; blocked: a held lock left the mirror in an older layout.
 export function migrateMirrorLocked(mirror) {
   if (!legacyMirror(mirror)) return null;
   const release = acquireLock(mirror);
-  if (!release) return { line: `${mirror} is still in the pre-3.0 layout and another darkmem-sync holds its lock; try again once it is done`, blocked: true };
+  if (!release) return { line: `${mirror} is still in an older layout and another darkmem-sync holds its lock; try again once it is done`, blocked: true };
   try {
     const statePath = path.join(mirror, ".sync-state.json");
     const state = loadState(statePath);
+    const from = heldFolders(mirror).find(prefix => prefix !== DOC_PREFIX);
     if (!migrateMirror(mirror, state)) return null;
     saveState(statePath, state);
-    return { line: `renamed ${mirror}'s ${LEGACY_PREFIX}/ to ${DOC_PREFIX}/; darkmem's documents follow at its next sync`, blocked: false };
+    return { line: `renamed ${mirror}'s ${from ?? OLD_PREFIXES.join("/ and ")}/ to ${DOC_PREFIX}/; darkmem's documents follow at its next sync`, blocked: false };
   } finally {
     release();
   }
 }
 
-// darkmem's half, once per mirror: every superpowers/ document moves to the
-// same name under dforge/, under its own hash. A name darkmem already holds
-// under dforge/ is a failure, never overwritten. Answers the failure lines;
-// state.prefix is set only when there are none.
+// darkmem's half, once per mirror: every superpowers/ and forge/ document
+// moves to the same name under dforge/, under its own hash. A name darkmem
+// already holds under dforge/ is a failure, never overwritten. Answers the
+// failure lines; state.prefix is set only when there are none.
 export async function migrateServer({ cfg, client, state, persist }) {
   if (state.prefix === DOC_PREFIX) return [];
   const failures = [];
   const held = new Map((await client.manifest(cfg.project, DOC_PREFIX)).map(item => [item.uri, item.content_hash]));
-  const old = (await client.manifest(cfg.project, LEGACY_PREFIX)).filter(item => item.uri.startsWith(OLD));
-  for (const item of old) {
-    const uri = renamed(item.uri);
-    if (held.has(uri)) {
-      failures.push(`${item.uri}: darkmem also holds ${uri}${held.get(uri) === item.content_hash ? " with the same content; delete one" : " with other content; keep one"}`);
-      continue;
-    }
-    try {
-      await client.moveDocument(item.id, { uri, expectedHash: item.content_hash });
-    } catch (error) {
-      if (!(error instanceof HttpError) || error.status === 401) throw error;
-      failures.push(`${item.uri}: darkmem refused the move to ${uri}: ${error.detail}`);
+  for (const prefix of OLD_PREFIXES) {
+    const old = (await client.manifest(cfg.project, prefix)).filter(item => item.uri.startsWith(`${prefix}/`));
+    for (const item of old) {
+      const uri = renamed(item.uri);
+      if (held.has(uri)) {
+        failures.push(`${item.uri}: darkmem also holds ${uri}${held.get(uri) === item.content_hash ? " with the same content; delete one" : " with other content; keep one"}`);
+        continue;
+      }
+      try {
+        await client.moveDocument(item.id, { uri, expectedHash: item.content_hash });
+        held.set(uri, item.content_hash);
+      } catch (error) {
+        if (!(error instanceof HttpError) || error.status === 401) throw error;
+        failures.push(`${item.uri}: darkmem refused the move to ${uri}: ${error.detail}`);
+      }
     }
   }
   if (!failures.length) {
````

- [ ] **Step 4: Run the tests to verify they pass**

Run: `env -u CLAUDE_CONFIG_DIR timeout 300 node --test plugins/dforge/tests/darkmem-sync/migrate.test.mjs`
Expected: `ℹ tests 9`, `ℹ pass 9`, `ℹ fail 0`.

- [ ] **Step 5: Commit**

```bash
git commit -m "feat(dforge): move forge/ darkmem documents to dforge/"
```

### Task 5: Migrate the ~/.dr-forge home

**Files:**
- Modify: `plugins/dforge/scripts/lib/dforge-home-migrate.mjs` (`writeJson`, `sameFile`, `migrateHome` with `dryRun`, the `--dry-run` flag; in a dry run `view()` reads a new-home path from the old entry an earlier line would move there)
- Test: `plugins/dforge/tests/darkmem-sync/migrate.test.mjs`

**Interfaces:**
- Consumes: C1, C3 from Task 4 (`OLD_PREFIXES`, `heldFolders`, `legacyMirror`, `migrateMirrorLocked`).
- Produces: C3's `migrateHome(env, { dryRun })` and the module's `--dry-run` flag, which Task 7 passes.

**Items:** 2
**Implementer:** dr-superpowers:impl-sonnet-high
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 3 = 5

- [ ] **Step 1: Write the failing tests**

Run C1 with id `t5-tests`, writing `<scratch>/t5-tests.patch`, then `git apply --index <scratch>/t5-tests.patch`.

<!-- block: t5-tests -->
````diff
diff --git a/plugins/dforge/tests/darkmem-sync/migrate.test.mjs b/plugins/dforge/tests/darkmem-sync/migrate.test.mjs
index 65f7559..faf8756 100644
--- a/plugins/dforge/tests/darkmem-sync/migrate.test.mjs
+++ b/plugins/dforge/tests/darkmem-sync/migrate.test.mjs
@@ -153,3 +153,91 @@ test("migrateHome copies the darkmem mapping, moves each mirror and renames its
   const again = migrateHome({ HOME: home });
   assert.ok(again.lines.some(line => line.includes("already has a darkmem section")), again.lines.join("\n"));
 });
+
+test("migrateHome renames ~/.dr-forge whole and points stores.json at the moved mirror", () => {
+  const home = scratch("dms-home-");
+  const forge = path.join(home, ".dr-forge");
+  write(path.join(forge, "config.json"), JSON.stringify({ handoffTokens: 325000 }));
+  write(path.join(forge, "mirror", "p", "forge", "a.md"), "a\n");
+  write(path.join(forge, "mirror", "p", ".sync-state.json"), STATE({ "forge/a.md": sha("a\n") }));
+  write(path.join(forge, "stores.json"), JSON.stringify({ "/r": { project: "p", mirror: path.join(forge, "mirror", "p"), documents: "darkmem" } }));
+  const { lines, refused } = migrateHome({ HOME: home });
+  assert.equal(refused, 0, lines.join("\n"));
+  assert.equal(fs.existsSync(forge), false);
+  assert.equal(JSON.parse(read(path.join(home, ".dforge", "config.json"))).handoffTokens, 325000);
+  assert.equal(JSON.parse(read(path.join(home, ".dforge", "stores.json")))["/r"].mirror, path.join(home, ".dforge", "mirror", "p"));
+  assert.equal(read(path.join(home, ".dforge", "mirror", "p", "dforge", "a.md")), "a\n");
+  assert.deepEqual(Object.keys(JSON.parse(read(path.join(home, ".dforge", "mirror", "p", ".sync-state.json"))).documents), ["dforge/a.md"]);
+  assert.deepEqual(migrateHome({ HOME: home }), { lines: [], refused: 0 });
+});
+
+test("migrateHome merges ~/.dr-forge into an existing ~/.dforge entry by entry", () => {
+  const home = scratch("dms-home-");
+  const forge = path.join(home, ".dr-forge");
+  const dforge = path.join(home, ".dforge");
+  write(path.join(forge, "config.json"), JSON.stringify({ handoffTokens: 325000, layout: "auto" }));
+  write(path.join(dforge, "config.json"), JSON.stringify({ layout: "auto" }));
+  write(path.join(forge, "same.txt"), "same\n");
+  write(path.join(dforge, "same.txt"), "same\n");
+  write(path.join(forge, "only-old.txt"), "old\n");
+  write(path.join(forge, "mirror", "p", "work", "x"), "x\n");
+  write(path.join(dforge, "mirror", "q", "kept"), "kept\n");
+  const { lines, refused } = migrateHome({ HOME: home });
+  assert.equal(refused, 0, lines.join("\n"));
+  assert.deepEqual(JSON.parse(read(path.join(dforge, "config.json"))), { layout: "auto", handoffTokens: 325000 });
+  assert.equal(read(path.join(dforge, "only-old.txt")), "old\n");
+  assert.equal(read(path.join(dforge, "mirror", "p", "work", "x")), "x\n");
+  assert.equal(read(path.join(dforge, "mirror", "q", "kept")), "kept\n");
+  assert.equal(fs.existsSync(forge), false);
+});
+
+test("migrateHome refuses a key both configs set differently and keeps the old file", () => {
+  const home = scratch("dms-home-");
+  const forge = path.join(home, ".dr-forge");
+  const dforge = path.join(home, ".dforge");
+  write(path.join(forge, "config.json"), JSON.stringify({ handoffTokens: 325000 }));
+  write(path.join(dforge, "config.json"), JSON.stringify({ handoffTokens: 200000 }));
+  const { lines, refused } = migrateHome({ HOME: home });
+  assert.equal(refused, 1);
+  assert.ok(lines.some(line => line.startsWith("refused: ") && line.includes("set handoffTokens differently")), lines.join("\n"));
+  assert.equal(JSON.parse(read(path.join(forge, "config.json"))).handoffTokens, 325000);
+  assert.equal(JSON.parse(read(path.join(dforge, "config.json"))).handoffTokens, 200000);
+});
+
+test("migrateHome with dryRun writes nothing and says what would happen", () => {
+  const home = scratch("dms-home-");
+  const forge = path.join(home, ".dr-forge");
+  write(path.join(forge, "config.json"), JSON.stringify({ handoffTokens: 325000 }));
+  write(path.join(forge, "mirror", "p", "forge", "a.md"), "a\n");
+  write(path.join(forge, "stores.json"), JSON.stringify({ "/r": { project: "p", mirror: path.join(forge, "mirror", "p") } }));
+  write(path.join(home, ".dr-superpowers", "mirror", "q", "superpowers", "b.md"), "b\n");
+  const before = fs.readdirSync(home, { recursive: true }).sort();
+  const { lines, refused } = migrateHome({ HOME: home }, { dryRun: true });
+  assert.equal(refused, 0, lines.join("\n"));
+  assert.deepEqual(fs.readdirSync(home, { recursive: true }).sort(), before);
+  assert.ok(lines.every(line => line.startsWith("would ")), lines.join("\n"));
+  assert.ok(lines.includes(`would move ${forge} to ${path.join(home, ".dforge")}`), lines.join("\n"));
+  assert.ok(lines.some(line => line.startsWith("would point 1 ")), lines.join("\n"));
+  assert.ok(lines.some(line => line.includes(`${path.join(forge, "mirror", "p")}'s forge/ to dforge/`)), lines.join("\n"));
+  assert.ok(lines.some(line => line.includes(`${path.join(home, ".dr-superpowers", "mirror", "q")}'s superpowers/ to dforge/`)), lines.join("\n"));
+});
+
+test("migrateHome with dryRun, merging into an existing ~/.dforge, lists every action the real run takes", () => {
+  const home = scratch("dms-home-");
+  const forge = path.join(home, ".dr-forge");
+  const dforge = path.join(home, ".dforge");
+  write(path.join(dforge, "config.json"), JSON.stringify({ layout: "auto" }));
+  write(path.join(forge, "config.json"), JSON.stringify({ handoffTokens: 325000 }));
+  write(path.join(forge, "mirror", "p", "forge", "a.md"), "a\n");
+  write(path.join(forge, "stores.json"), JSON.stringify({ "/r": { project: "p", mirror: path.join(forge, "mirror", "p") } }));
+  const before = fs.readdirSync(home, { recursive: true }).sort();
+  const dry = migrateHome({ HOME: home }, { dryRun: true });
+  assert.equal(dry.refused, 0, dry.lines.join("\n"));
+  assert.deepEqual(fs.readdirSync(home, { recursive: true }).sort(), before);
+  const real = migrateHome({ HOME: home });
+  assert.equal(real.refused, 0, real.lines.join("\n"));
+  const verb = line => line.replace(/^would /, "").split(" ")[0];
+  const done = { merge: "merged", move: "moved", point: "pointed", rename: "renamed" };
+  assert.deepEqual(real.lines.map(verb), ["merged", "moved", "moved", "pointed", "renamed"], real.lines.join("\n"));
+  assert.deepEqual(dry.lines.map(line => done[verb(line)]), real.lines.map(verb), dry.lines.join("\n"));
+});
````

- [ ] **Step 2: Run the tests to verify they fail**

Run: `env -u CLAUDE_CONFIG_DIR timeout 300 node --test plugins/dforge/tests/darkmem-sync/migrate.test.mjs`
Expected: FAIL — `ℹ tests 14`, `ℹ pass 9`, `ℹ fail 5`: the five new `migrateHome` tests (renames `~/.dr-forge` whole, merges entry by entry, refuses a differing key, dry run writes nothing, and a dry run merging into an existing `~/.dforge` lists every action the real run takes).

- [ ] **Step 3: Write the implementation**

Run C1 with id `t5-impl`, writing `<scratch>/t5-impl.patch`, then `git apply --index <scratch>/t5-impl.patch`.

<!-- block: t5-impl -->
````diff
diff --git a/plugins/dforge/scripts/lib/dforge-home-migrate.mjs b/plugins/dforge/scripts/lib/dforge-home-migrate.mjs
index 7546e67..01df4b3 100644
--- a/plugins/dforge/scripts/lib/dforge-home-migrate.mjs
+++ b/plugins/dforge/scripts/lib/dforge-home-migrate.mjs
@@ -114,27 +114,129 @@ function readJson(file) {
   }
 }
 
-// The home's half, run by scripts/dforge-migrate: the darkmem mapping into
-// ~/.dforge/config.json when that file has none, each mirror the new home
-// lacks, then every mirror's local half. The old files stay where a copy was
-// made. Answers { lines, refused }.
-export function migrateHome(env = process.env) {
+function writeJson(file, data) {
+  const temporary = path.join(path.dirname(file), `.${path.basename(file)}.${process.pid}.tmp`);
+  fs.writeFileSync(temporary, `${JSON.stringify(data, null, 2)}\n`);
+  fs.renameSync(temporary, file);
+}
+
+function sameFile(a, b) {
+  try {
+    return fs.statSync(a).isFile() && fs.statSync(b).isFile() && fs.readFileSync(a).equals(fs.readFileSync(b));
+  } catch {
+    return false;
+  }
+}
+
+// The home's half, run by scripts/dforge-migrate. ~/.dr-forge/ becomes
+// ~/.dforge/: renamed whole when ~/.dforge/ is absent, otherwise entry by
+// entry, its config.json merged key by key. ~/.dr-superpowers/ then gives
+// ~/.dforge/config.json its darkmem mapping when that file has none, and each
+// mirror the new home lacks. stores.json follows every mirror that moved, and
+// every mirror gets its local half. The old files stay wherever something was
+// refused. With dryRun nothing is written and each line says what would
+// happen. Answers { lines, refused }.
+export function migrateHome(env = process.env, { dryRun = false } = {}) {
   const home = env.HOME || os.homedir();
+  const forgeHome = path.join(home, ".dr-forge");
   const oldHome = path.join(home, ".dr-superpowers");
   const newHome = path.join(home, ".dforge");
   const lines = [];
   let refused = 0;
+  const refuse = line => {
+    lines.push(`refused: ${line}`);
+    refused += 1;
+  };
+  const did = (done, would) => lines.push(dryRun ? would : done);
+  const moves = [];
+  // In a dry run nothing has moved, so a path in the new home is read where
+  // it still is: under the old entry an earlier line would move there.
+  const pending = [];
+  const view = (...parts) => {
+    const target = path.join(newHome, ...parts);
+    const hit = pending.find(([to]) => target === to || target.startsWith(`${to}${path.sep}`));
+    return hit ? `${hit[1]}${target.slice(hit[0].length)}` : target;
+  };
+  const whole = fs.existsSync(forgeHome) && !fs.existsSync(newHome);
+
+  if (whole) {
+    if (dryRun) pending.push([newHome, forgeHome]);
+    else fs.renameSync(forgeHome, newHome);
+    did(`moved ${forgeHome} to ${newHome}`, `would move ${forgeHome} to ${newHome}`);
+    moves.push([path.join(forgeHome, "mirror"), path.join(newHome, "mirror")]);
+  } else if (fs.existsSync(forgeHome)) {
+    for (const entry of fs.readdirSync(forgeHome, { withFileTypes: true })) {
+      const from = path.join(forgeHome, entry.name);
+      const to = path.join(newHome, entry.name);
+      if (entry.name === "config.json" && entry.isFile() && fs.existsSync(to)) {
+        const old = readJson(from) ?? {};
+        const next = readJson(to) ?? {};
+        const clash = Object.keys(old).filter(key => key in next && JSON.stringify(old[key]) !== JSON.stringify(next[key]));
+        if (clash.length) {
+          refuse(`${from} and ${to} set ${clash.join(", ")} differently; keep one value in ${to} and delete it from ${from}, then run dforge-migrate again`);
+          continue;
+        }
+        const copied = Object.keys(old).filter(key => !(key in next));
+        if (!dryRun) {
+          writeJson(to, { ...next, ...old });
+          fs.rmSync(from);
+        }
+        did(`merged ${from} into ${to} (${copied.length ? copied.join(", ") : "no new keys"})`,
+          `would merge ${from} into ${to} (${copied.length ? copied.join(", ") : "no new keys"})`);
+        continue;
+      }
+      if (entry.name === "mirror" && entry.isDirectory() && fs.existsSync(to)) {
+        for (const child of fs.readdirSync(from, { withFileTypes: true })) {
+          if (!child.isDirectory()) continue;
+          const source = path.join(from, child.name);
+          const target = path.join(to, child.name);
+          if (fs.existsSync(target)) {
+            refuse(`${target} exists, so ${source} was not moved`);
+            continue;
+          }
+          if (!dryRun) fs.renameSync(source, target);
+          did(`moved ${source} to ${target}`, `would move ${source} to ${target}`);
+          moves.push([source, target]);
+        }
+        continue;
+      }
+      if (!fs.existsSync(to)) {
+        if (dryRun) pending.push([to, from]);
+        else fs.renameSync(from, to);
+        did(`moved ${from} to ${to}`, `would move ${from} to ${to}`);
+        if (entry.name === "mirror") moves.push([from, to]);
+        continue;
+      }
+      if (sameFile(from, to)) {
+        if (!dryRun) fs.rmSync(from);
+        did(`dropped ${from}, the same as ${to}`, `would drop ${from}, the same as ${to}`);
+        continue;
+      }
+      refuse(`${from} differs from ${to}; keep one by hand, then run dforge-migrate again`);
+    }
+    if (!dryRun) {
+      for (const dir of [path.join(forgeHome, "mirror"), forgeHome]) {
+        try {
+          fs.rmdirSync(dir);
+        } catch {
+          // Still holds something refused, or already gone.
+        }
+      }
+    }
+  }
+
   const oldConfig = readJson(path.join(oldHome, "config.json"));
   if (oldConfig?.darkmem && typeof oldConfig.darkmem === "object") {
     const file = path.join(newHome, "config.json");
-    const config = readJson(file) ?? {};
+    const config = readJson(view("config.json")) ?? {};
     if (config.darkmem === undefined) {
       config.darkmem = oldConfig.darkmem;
-      fs.mkdirSync(newHome, { recursive: true });
-      const temporary = `${file}.${process.pid}.tmp`;
-      fs.writeFileSync(temporary, `${JSON.stringify(config, null, 2)}\n`);
-      fs.renameSync(temporary, file);
-      lines.push(`copied the darkmem mapping from ${path.join(oldHome, "config.json")} into ${file}`);
+      if (!dryRun) {
+        fs.mkdirSync(newHome, { recursive: true });
+        writeJson(file, config);
+      }
+      did(`copied the darkmem mapping from ${path.join(oldHome, "config.json")} into ${file}`,
+        `would copy the darkmem mapping from ${path.join(oldHome, "config.json")} into ${file}`);
       if (config.darkmemEnabled === undefined) lines.push("darkmem is off until you turn it on: bash <plugin-root>/scripts/dforge-config set darkmemEnabled true");
     } else {
       lines.push(`${file} already has a darkmem section; ${path.join(oldHome, "config.json")} was not copied`);
@@ -144,26 +246,57 @@ export function migrateHome(env = process.env) {
   const newMirrors = path.join(newHome, "mirror");
   for (const entry of fs.existsSync(oldMirrors) ? fs.readdirSync(oldMirrors, { withFileTypes: true }) : []) {
     if (!entry.isDirectory()) continue;
+    const source = path.join(oldMirrors, entry.name);
     const target = path.join(newMirrors, entry.name);
-    if (fs.existsSync(target)) {
-      lines.push(`refused: ${target} exists, so ${path.join(oldMirrors, entry.name)} was not moved`);
-      refused += 1;
+    if (fs.existsSync(view("mirror", entry.name))) {
+      refuse(`${target} exists, so ${source} was not moved`);
       continue;
     }
-    fs.mkdirSync(newMirrors, { recursive: true });
-    fs.renameSync(path.join(oldMirrors, entry.name), target);
-    lines.push(`moved ${path.join(oldMirrors, entry.name)} to ${target}`);
+    if (!dryRun) {
+      fs.mkdirSync(newMirrors, { recursive: true });
+      fs.renameSync(source, target);
+    }
+    did(`moved ${source} to ${target}`, `would move ${source} to ${target}`);
+    moves.push([source, target]);
   }
-  for (const entry of fs.existsSync(newMirrors) ? fs.readdirSync(newMirrors, { withFileTypes: true }) : []) {
-    if (!entry.isDirectory()) continue;
+
+  const stores = view("stores.json");
+  const data = readJson(stores);
+  if (data && typeof data === "object" && !Array.isArray(data)) {
+    let pointed = 0;
+    for (const record of Object.values(data)) {
+      if (!record || typeof record.mirror !== "string") continue;
+      const move = moves.find(([from]) => record.mirror === from || record.mirror.startsWith(`${from}${path.sep}`));
+      if (!move) continue;
+      record.mirror = `${move[1]}${record.mirror.slice(move[0].length)}`;
+      pointed += 1;
+    }
+    if (pointed) {
+      if (!dryRun) writeJson(path.join(newHome, "stores.json"), data);
+      did(`pointed ${pointed} ${path.join(newHome, "stores.json")} record(s) at the moved mirrors`,
+        `would point ${pointed} ${path.join(newHome, "stores.json")} record(s) at the moved mirrors`);
+    }
+  }
+
+  const mirrors = new Set();
+  for (const entry of fs.existsSync(view("mirror")) ? fs.readdirSync(view("mirror"), { withFileTypes: true }) : []) {
+    if (entry.isDirectory()) mirrors.add(view("mirror", entry.name));
+  }
+  if (dryRun) for (const [from] of moves) if (!from.endsWith(`${path.sep}mirror`)) mirrors.add(from);
+  for (const mirror of mirrors) {
+    if (dryRun) {
+      const held = heldFolders(mirror);
+      if (held.length > 1) refuse(`${mirror} holds ${held.map(prefix => `${prefix}/`).join(" and ")}; move all but one aside`);
+      else if (legacyMirror(mirror)) lines.push(`would rename ${mirror}'s ${held[0] ?? OLD_PREFIXES.join("/ and ")}/ to ${DOC_PREFIX}/; darkmem's documents follow at its next sync`);
+      continue;
+    }
     try {
-      const result = migrateMirrorLocked(path.join(newMirrors, entry.name));
+      const result = migrateMirrorLocked(mirror);
       if (result?.blocked) refused += 1;
       if (result) lines.push(result.blocked ? `refused: ${result.line}` : result.line);
     } catch (error) {
       if (!(error instanceof StateError)) throw error;
-      lines.push(`refused: ${error.message}`);
-      refused += 1;
+      refuse(error.message);
     }
   }
   return { lines, refused };
@@ -180,7 +313,7 @@ function isMain() {
 
 if (isMain()) {
   try {
-    const { lines, refused } = migrateHome();
+    const { lines, refused } = migrateHome(process.env, { dryRun: process.argv.includes("--dry-run") });
     for (const line of lines) process.stdout.write(`dforge-home-migrate: ${line}\n`);
     process.exitCode = refused ? 1 : 0;
   } catch (error) {
````

- [ ] **Step 4: Run the tests to verify they pass**

Run: `env -u CLAUDE_CONFIG_DIR timeout 300 node --test plugins/dforge/tests/darkmem-sync/migrate.test.mjs`
Expected: `ℹ tests 14`, `ℹ pass 14`, `ℹ fail 0`.

- [ ] **Step 5: Commit**

```bash
git commit -m "feat(dforge): migrate the ~/.dr-forge home"
```

### Task 6: Migrate dr-forge checkouts and active plans

**Files:**
- Modify: `plugins/dforge/scripts/dforge-migrate` (both older state directories, docs trees and git-dir names; `docs_trees`; the widened `rewrite_names`; `writable`, `rewrite_prefixes`, `plan_done`, `rewrite_active_plans`; temporary files from `mktemp`; the no-node refusal names both homes)
- Modify: `scripts/validate-repository.mjs` (`legacyAllowed` admits `dforge-migrate` and its test, which spell the older prefixes)
- Test: `plugins/dforge/tests/dforge-migrate.test.sh`

**Interfaces:**
- Consumes: C1, C2.
- Produces: C4 without `--dry-run`.

**Items:** 2
**Implementer:** dr-superpowers:impl-sonnet-high
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 3 = 5

- [ ] **Step 1: Write the failing tests**

Run C1 with id `t6-tests`, writing `<scratch>/t6-tests.patch`, then `git apply --index <scratch>/t6-tests.patch`.

<!-- block: t6-tests -->
````diff
diff --git a/plugins/dforge/tests/dforge-migrate.test.sh b/plugins/dforge/tests/dforge-migrate.test.sh
index 2b1fef9..634214a 100755
--- a/plugins/dforge/tests/dforge-migrate.test.sh
+++ b/plugins/dforge/tests/dforge-migrate.test.sh
@@ -146,6 +146,82 @@ check "both docs: exit 1" "$?" "1"
 bash "$FM" "$TMP/home" > /dev/null 2>&1
 check "outside git: exit 2" "$?" "2"
 
+# --- a dr-forge repository: .forge/, docs/forge/, <git dir>/dr-forge/ ---
+F="$TMP/forge"
+repo "$F"
+mkdir -p "$F/.forge/sdd/p1" "$F/.forge/handoff" "$F/docs/forge/plans" "$F/docs/forge/specs" "$F/.git/dr-forge/tasks"
+echo ledger > "$F/.forge/sdd/p1/progress.md"
+printf 'Resume with dr-forge:resume-execution\n' > "$F/.forge/handoff/latest.md"
+printf '> REQUIRED SUB-SKILL: dr-forge:subagent-driven-development\n**Implementer:** `dr-forge:impl-sonnet-low`\nsee dr-superpowers:executing-plans\n' > "$F/docs/forge/plans/active.md"
+printf '**Implementer:** dr-forge:impl-sonnet-low\n' > "$F/docs/forge/plans/done.md"
+printf -- '- 2026-10-01 `docs/forge/plans/done.md` — merged into `main` at abc1234\n' > "$F/docs/forge/plans/completed.md"
+printf 'use dr-forge:brainstorming\n' > "$F/docs/forge/specs/s.md"
+printf '.forge/\n' > "$F/.gitignore"
+printf 'docs/forge/** linguist-documentation\n' > "$F/.gitattributes"
+git -C "$F" add .gitignore .gitattributes docs
+git -C "$F" commit -q -m docs
+out=$(bash "$FM" "$F" 2>&1); code=$?
+check "dr-forge: exit 0" "$code" "0"
+check "dr-forge: .dforge holds the ledger" "$(cat "$F/.dforge/sdd/p1/progress.md" 2>/dev/null)" "ledger"
+check "dr-forge: .forge gone" "$(exists "$F/.forge")" "no"
+check "dr-forge: docs moved" "$(exists "$F/docs/dforge/specs/s.md")" "yes"
+check "dr-forge: docs/forge gone" "$(exists "$F/docs/forge")" "no"
+check "dr-forge: the rename is staged" "$(git -C "$F" status --porcelain -- docs/dforge/specs docs/forge/specs | cut -c1-2 | sort -u | tr -d ' ')" "R"
+check "dr-forge: git dir state moved" "$(exists "$F/.git/dforge/tasks")" "yes"
+check "dr-forge: .gitignore rewritten" "$(cat "$F/.gitignore")" ".dforge/"
+check "dr-forge: .gitattributes rewritten" "$(cat "$F/.gitattributes")" "docs/dforge/** linguist-documentation"
+check "dr-forge: the active plan's prefixes rewritten" "$(cat "$F/docs/dforge/plans/active.md")" \
+  $'> REQUIRED SUB-SKILL: dforge:subagent-driven-development\n**Implementer:** `dforge:impl-sonnet-low`\nsee dforge:executing-plans'
+check "dr-forge: a finished plan keeps its text" "$(cat "$F/docs/dforge/plans/done.md")" "**Implementer:** dr-forge:impl-sonnet-low"
+check "dr-forge: a spec keeps its text" "$(cat "$F/docs/dforge/specs/s.md")" "use dr-forge:brainstorming"
+check "dr-forge: the handoff note's prefixes rewritten" "$(cat "$F/.dforge/handoff/latest.md")" "Resume with dforge:resume-execution"
+check "dr-forge: names the staged rename" "$(grep -c "^commit: $F: the staged rename docs/forge/ -> docs/dforge/" <<<"$out")" "1"
+check "dr-forge: names the rewritten plan" "$(grep -c "^commit: $F: docs/dforge/plans/active.md$" <<<"$out")" "1"
+out=$(bash "$FM" "$F" 2>&1); code=$?
+check "dr-forge again: exit 0" "$code" "0"
+check "dr-forge again: nothing to migrate" "$out" "dforge-migrate: nothing to migrate in $F"
+
+# --- .superpowers/ and .forge/ both present: both merged into .dforge/ ---
+T="$TMP/two-states"
+repo "$T"
+mkdir -p "$T/.superpowers" "$T/.forge"
+echo a > "$T/.superpowers/a.md"
+echo b > "$T/.forge/b.md"
+out=$(bash "$FM" "$T" 2>&1); code=$?
+check "two states: exit 0" "$code" "0"
+check "two states: both merged" "$(cat "$T/.dforge/a.md" "$T/.dforge/b.md" 2>/dev/null | tr '\n' ' ')" "a b "
+check "two states: both gone" "$(exists "$T/.superpowers")$(exists "$T/.forge")" "nono"
+
+# --- docs/forge/ beside docs/dforge/: refused, and no plan is rewritten ---
+K="$TMP/forge-both-docs"
+repo "$K"
+mkdir -p "$K/docs/forge/plans" "$K/docs/dforge"
+printf 'dr-forge:impl-sonnet-low\n' > "$K/docs/forge/plans/p.md"
+out=$(bash "$FM" "$K" 2>&1); code=$?
+check "forge and dforge docs: exit 1" "$code" "1"
+check "forge and dforge docs: refusal names both" "$(grep -c "refused: $K/docs/forge and $K/docs/dforge all exist" <<<"$out")" "1"
+check "forge and dforge docs: the plan is untouched" "$(cat "$K/docs/forge/plans/p.md")" "dr-forge:impl-sonnet-low"
+
+# --- a cloned repository controls these names: nothing is written through a link ---
+L="$TMP/links"
+repo "$L"
+mkdir -p "$TMP/outside/state/handoff" "$L/docs/dforge/plans"
+printf 'dr-forge:resume-execution\n' > "$TMP/outside/note.md"
+printf 'dr-forge:resume-execution\n' > "$TMP/outside/state/handoff/latest.md"
+printf '.forge/\n' > "$TMP/outside/ignore"
+mkdir -p "$L/.dforge/handoff"
+ln -s "$TMP/outside/note.md" "$L/.dforge/handoff/latest.md"
+ln -s "$TMP/outside/note.md" "$L/docs/dforge/plans/linked.md"
+ln -s "$TMP/outside/ignore" "$L/.gitignore"
+LL="$TMP/linked-state"
+repo "$LL"
+ln -s "$TMP/outside/state" "$LL/.forge"
+bash "$FM" "$L" > /dev/null 2>&1
+bash "$FM" "$LL" > /dev/null 2>&1
+check "links: a linked handoff note is not rewritten" "$(cat "$TMP/outside/note.md")" "dr-forge:resume-execution"
+check "links: a linked .gitignore is not rewritten" "$(cat "$TMP/outside/ignore")" ".forge/"
+check "links: a state directory linked outside is not rewritten" "$(cat "$TMP/outside/state/handoff/latest.md")" "dr-forge:resume-execution"
+
 # --- the home step runs when dforge-home-migrate.mjs is installed ---
 P="$TMP/plugin/scripts"
 mkdir -p "$P/lib"
@@ -180,6 +256,11 @@ mkdir -p "$NH/.dr-superpowers"
 out=$(HOME="$NH" PATH="$NB" bash "$P/dforge-migrate" "$H" 2>&1); code=$?
 check "no node, old home present: exit 1" "$code" "1"
 check "no node, old home present: refused" "$(grep -c 'refused: node is not on PATH' <<<"$out")" "1"
+rm -rf "$NH/.dr-superpowers"
+mkdir -p "$NH/.dr-forge"
+out=$(HOME="$NH" PATH="$NB" bash "$P/dforge-migrate" "$H" 2>&1); code=$?
+check "no node, dr-forge home present: exit 1" "$code" "1"
+check "no node, dr-forge home present: refused" "$(grep -c 'refused: node is not on PATH' <<<"$out")" "1"
 
 printf '\n%d passed, %d failed\n' "$pass" "$fail"
 [ "$fail" -eq 0 ]
````

- [ ] **Step 2: Run the tests to verify they fail**

Run: `env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/dforge-migrate.test.sh`
Expected: FAIL — `66 passed, 20 failed`, starting with `FAIL - dr-forge: .dforge holds the ledger`.

- [ ] **Step 3: Write the implementation**

Run C1 with id `t6-impl`, writing `<scratch>/t6-impl.patch`, then `git apply --index <scratch>/t6-impl.patch`.

<!-- block: t6-impl -->
````diff
diff --git a/plugins/dforge/scripts/dforge-migrate b/plugins/dforge/scripts/dforge-migrate
index 9a2ada5..e02422a 100755
--- a/plugins/dforge/scripts/dforge-migrate
+++ b/plugins/dforge/scripts/dforge-migrate
@@ -1,23 +1,29 @@
 #!/usr/bin/env bash
-# dforge-migrate [DIR] — move a repository from the pre-3.0 names to dforge
-# 3.0's, which reads only the new ones. For the repository at DIR (default:
-# the working directory), its primary checkout and every linked worktree:
-#   .superpowers/          -> .dforge/            (plain rename)
-#   docs/superpowers/      -> docs/dforge/        (git mv when tracked)
-#   <git dir>/dr-superpowers/ -> <git dir>/dforge/
+# dforge-migrate [DIR] — move a repository from the older names to dforge
+# 4.0's, which reads only the new ones: dr-superpowers' (before 3.0) and
+# dr-forge's (3.x). For the repository at DIR (default: the working
+# directory), its primary checkout and every linked worktree:
+#   .superpowers/, .forge/                    -> .dforge/      (plain rename)
+#   docs/superpowers/ or docs/forge/          -> docs/dforge/  (git mv when tracked)
+#   <git dir>/dr-superpowers/, <git dir>/dr-forge/ -> <git dir>/dforge/
 # then, once every move has succeeded, the lines of .gitignore, .gitattributes
-# and the shared info/exclude that name .superpowers or docs/superpowers. No
-# other file's content changes: historical plans and specs keep the citations
-# dforge translates when it reads them. Last, scripts/lib/dforge-home-migrate.mjs
-# moves the home (~/.dr-superpowers/ -> ~/.dforge/) when it is installed.
+# and the shared info/exclude that name an older directory. An active plan
+# (one the completed.md beside it does not record) and the checkout's handoff
+# note have their dr-superpowers: and dr-forge: prefixes rewritten to
+# dforge:, so they keep running. No other file's content changes: finished
+# plans, specs, ledgers and registers keep the citations dforge translates
+# when it reads them. Last, scripts/lib/dforge-home-migrate.mjs moves the
+# homes (~/.dr-superpowers/ and ~/.dr-forge/ -> ~/.dforge/) when it is
+# installed.
 #
-# A checkout holding both .superpowers/ and .dforge/ is merged file by file: a
-# file only the old one has moves, an identical one is dropped, and a file that
-# differs is refused and left. A checkout holding both docs trees, or a
-# docs/superpowers/ with uncommitted changes, is refused and left as it is.
-# The rest still moves, and a second run finishes the job once the refusal is
-# resolved. A checkout that was refused keeps its old ignore lines and gains
-# the new ones beside them, so a moved directory is never left un-ignored.
+# A checkout holding an older state directory and .dforge/ is merged file by
+# file: a file only the old one has moves, an identical one is dropped, and a
+# file that differs is refused and left. A checkout holding two docs trees,
+# or an older docs tree with uncommitted changes, is refused and left as it
+# is, and its plans are not rewritten. The rest still moves, and a second run
+# finishes the job once the refusal is resolved. A checkout that was refused
+# keeps its old ignore lines and gains the new ones beside them, so a moved
+# directory is never left un-ignored.
 #
 # Exit: 0 done or nothing to do; 1 something was refused; 2 usage or not
 # inside a git repository.
@@ -83,35 +89,49 @@ mv_plain() {
   if mv -- "$1" "$2"; then done_move "$1" "$2"; else refuse "could not rename $1"; fi
 }
 
+# docs_trees CHECKOUT — each docs tree the checkout holds, one per line.
+docs_trees() {
+  local name
+  for name in superpowers forge dforge; do [ ! -e "$1/docs/$name" ] || printf '%s\n' "$1/docs/$name"; done
+}
+
 migrate_docs() { # CHECKOUT
-  local wt=$1 old="$1/docs/superpowers" new="$1/docs/dforge"
-  [ -e "$old" ] || return 0
-  if [ -e "$new" ]; then refuse "$old and $new both exist; merge them by hand, then run dforge-migrate again"; return 0; fi
-  if [ -z "$(g -C "$wt" ls-files -- docs/superpowers | head -n 1)" ]; then mv_plain "$old" "$new"; return 0; fi
-  if [ -n "$(g -C "$wt" status --porcelain --untracked-files=all -- docs/superpowers)" ]; then
+  local wt=$1 trees name old new="$1/docs/dforge"
+  trees=$(docs_trees "$wt")
+  [ -n "$trees" ] || return 0
+  if [ "$(wc -l <<<"$trees")" -gt 1 ]; then
+    refuse "$(paste -sd, - <<<"$trees" | sed 's/,/ and /g') all exist; merge them by hand, then run dforge-migrate again"
+    return 0
+  fi
+  [ "$trees" != "$new" ] || return 0
+  old=$trees name=${trees##*/}
+  if [ -z "$(g -C "$wt" ls-files -- "docs/$name" | head -n 1)" ]; then mv_plain "$old" "$new"; return 0; fi
+  if [ -n "$(g -C "$wt" status --porcelain --untracked-files=all -- "docs/$name")" ]; then
     refuse "$old has uncommitted changes; commit or stash them, then run dforge-migrate again"
     return 0
   fi
-  if g -C "$wt" mv docs/superpowers docs/dforge; then
+  if g -C "$wt" mv "docs/$name" docs/dforge; then
     done_move "$old" "$new"
-    commit_notes+=("$wt: the staged rename docs/superpowers/ -> docs/dforge/")
+    commit_notes+=("$wt: the staged rename docs/$name/ -> docs/dforge/")
   else
-    refuse "git mv docs/superpowers docs/dforge failed in $wt"
+    refuse "git mv docs/$name docs/dforge failed in $wt"
   fi
 }
 
-# rewrite_names FILE MODE — the ignore and attribute lines that name a
-# pre-3.0 directory. MODE replace renames them in place, dropping a renamed
+# rewrite_names FILE MODE — the ignore and attribute lines that name an
+# older directory. MODE replace renames them in place, dropping a renamed
 # line the file already holds; MODE add keeps each line and puts the renamed
 # one after it, skipping comments and lines already present.
 rewrite_names() {
   local file=$1 mode=$2 renamed tmp
-  [ -f "$file" ] || return 1
-  grep -qE '(^|[^A-Za-z0-9_-])\.superpowers([/[:space:]*]|$)|docs/superpowers([/[:space:]*]|$)' "$file" || return 1
-  renamed="$file.dforge-migrate.$$.renamed"
-  tmp="$file.dforge-migrate.$$"
-  sed -E -e 's#(^|[^A-Za-z0-9_-])\.superpowers([/[:space:]*]|$)#\1.dforge\2#g' \
-         -e 's#docs/superpowers([/[:space:]*]|$)#docs/dforge\1#g' "$file" > "$renamed" \
+  [ -f "$file" ] && [ ! -L "$file" ] || return 1
+  grep -qE '(^|[^A-Za-z0-9_-])\.(superpowers|forge)([/[:space:]*]|$)|docs/(superpowers|forge)([/[:space:]*]|$)' "$file" || return 1
+  # mktemp creates each name exclusively, so a link planted at it is never
+  # written through.
+  renamed=$(mktemp "$file.dforge-migrate.XXXXXX") || return 1
+  tmp=$(mktemp "$file.dforge-migrate.XXXXXX") || { rm -f -- "$renamed"; return 1; }
+  sed -E -e 's#(^|[^A-Za-z0-9_-])\.(superpowers|forge)([/[:space:]*]|$)#\1.dforge\3#g' \
+         -e 's#docs/(superpowers|forge)([/[:space:]*]|$)#docs/dforge\2#g' "$file" > "$renamed" \
     && awk -v mode="$mode" '
       NR == FNR { old[FNR] = $0; have[$0] = 1; n = FNR; next }
       { new[FNR] = $0 }
@@ -128,10 +148,69 @@ rewrite_names() {
     && cat "$tmp" > "$file" \
     || { rm -f -- "$tmp" "$renamed"; return 1; }
   rm -f -- "$tmp" "$renamed"
-  printf 'rewrote the pre-3.0 names in %s\n' "$file"
+  printf 'rewrote the older names in %s\n' "$file"
   moved=1
 }
 
+# writable CHECKOUT FILE — FILE is no symbolic link and lies inside CHECKOUT
+# once links are resolved: a cloned repository controls these names, so a
+# rewrite must never land outside it.
+writable() {
+  local top real
+  [ ! -L "$2" ] || return 1
+  top=$(cd "$1" 2>/dev/null && pwd -P) && real=$(cd "$(dirname -- "$2")" 2>/dev/null && pwd -P) || return 1
+  case $real/ in "$top"/*) return 0 ;; *) return 1 ;; esac
+}
+
+PREFIX_RE='(^|[^A-Za-z0-9_-])dr-(superpowers|forge):([a-z])'
+
+# rewrite_prefixes FILE CHECKOUT — the older plugin prefixes before a skill or
+# agent name, as dforge's own. Status 1 when FILE names none, or is not
+# writable in CHECKOUT.
+rewrite_prefixes() {
+  local file=$1 tmp
+  writable "$2" "$file" || return 1
+  grep -qE "$PREFIX_RE" "$file" 2>/dev/null || return 1
+  tmp=$(mktemp "$file.dforge-migrate.XXXXXX") || { refuse "could not rewrite the plugin prefixes in $file"; return 1; }
+  if sed -E "s#$PREFIX_RE#\\1dforge:\\3#g" "$file" > "$tmp" && cat "$tmp" > "$file"; then
+    rm -f -- "$tmp"
+    printf 'rewrote the plugin prefixes in %s\n' "$file"
+    moved=1
+    return 0
+  fi
+  rm -f -- "$tmp"
+  refuse "could not rewrite the plugin prefixes in $file"
+  return 1
+}
+
+# plan_done DOCS REL — the completed.md beside the plan DOCS/REL records it,
+# under any of the three docs spellings, as next-step's plan_finished reads it.
+plan_done() {
+  local f="$1/$(dirname -- "$2")/completed.md" spelling
+  [ -f "$f" ] || return 1
+  for spelling in dforge forge superpowers; do
+    grep -qF "\`docs/$spelling/$2\`" "$f" && return 0
+  done
+  return 1
+}
+
+# rewrite_active_plans CHECKOUT — every plan under docs/dforge/plans/ that is
+# still active, and the checkout's handoff note.
+rewrite_active_plans() {
+  local wt=$1 docs="$1/docs/dforge" plan rel
+  if [ -d "$docs/plans" ]; then
+    while IFS= read -r -d '' plan; do
+      rel=${plan#"$docs"/}
+      [ "${rel##*/}" != completed.md ] || continue
+      plan_done "$docs" "$rel" && continue
+      if rewrite_prefixes "$plan" "$wt" && g -C "$wt" ls-files --error-unmatch -- "docs/dforge/$rel" >/dev/null 2>&1; then
+        commit_notes+=("$wt: docs/dforge/$rel")
+      fi
+    done < <(find "$docs/plans" -type f -name '*.md' -print0)
+  fi
+  [ ! -f "$wt/.dforge/handoff/latest.md" ] || rewrite_prefixes "$wt/.dforge/handoff/latest.md" "$wt" || true
+}
+
 while IFS= read -r wt; do
   [ -n "$wt" ] && [ -d "$wt" ] && checkouts+=("$wt")
 done < <(g -C "$root" worktree list --porcelain 2>/dev/null | tr -d '\r' | sed -n 's/^worktree //p')
@@ -139,13 +218,16 @@ done < <(g -C "$root" worktree list --porcelain 2>/dev/null | tr -d '\r' | sed -
 
 for wt in "${checkouts[@]}"; do
   checkout_refused=0
-  if [ -e "$wt/.superpowers" ] && [ -n "$(g -C "$wt" ls-files -- .superpowers | head -n 1)" ]; then
-    commit_notes+=("$wt: the rename .superpowers/ -> .dforge/ (git add -A .superpowers .dforge)")
-  fi
-  mv_plain "$wt/.superpowers" "$wt/.dforge"
+  for old in .superpowers .forge; do
+    if [ -e "$wt/$old" ] && [ -n "$(g -C "$wt" ls-files -- "$old" | head -n 1)" ]; then
+      commit_notes+=("$wt: the rename $old/ -> .dforge/ (git add -A $old .dforge)")
+    fi
+    mv_plain "$wt/$old" "$wt/.dforge"
+  done
   migrate_docs "$wt"
+  [ -n "$(docs_trees "$wt" | grep -vxF "$wt/docs/dforge")" ] || rewrite_active_plans "$wt"
   if gitdir=$(g -C "$wt" rev-parse --absolute-git-dir 2>/dev/null); then
-    mv_plain "$gitdir/dr-superpowers" "$gitdir/dforge"
+    for old in dr-superpowers dr-forge; do mv_plain "$gitdir/$old" "$gitdir/dforge"; done
   else
     refuse "cannot read the git directory of $wt"
   fi
@@ -170,7 +252,9 @@ rewrite_names "$common/info/exclude" "$mode" || true
 
 if [ -f "$HERE/lib/dforge-home-migrate.mjs" ]; then
   if ! command -v node >/dev/null 2>&1; then
-    if [ -e "${HOME:-}/.dr-superpowers" ]; then refuse "node is not on PATH, so the home (~/.dr-superpowers/) was not migrated"; fi
+    if [ -e "${HOME:-}/.dr-superpowers" ] || [ -e "${HOME:-}/.dr-forge" ]; then
+      refuse "node is not on PATH, so the homes (~/.dr-superpowers/, ~/.dr-forge/) were not migrated"
+    fi
   else
     home_out=$(cd "$root" && node "$(dr_native_path "$HERE/lib/dforge-home-migrate.mjs")")
     home_status=$?
diff --git a/scripts/validate-repository.mjs b/scripts/validate-repository.mjs
index 954480e..b758a28 100644
--- a/scripts/validate-repository.mjs
+++ b/scripts/validate-repository.mjs
@@ -87,8 +87,12 @@ export function validateRepository(root) {
     visit(skillRoot);
   }
   const legacyPattern = /(?:^|[^\w-])superpowers:|dr-superpowers:|dcc-superpower-companions:/;
+  // dforge-migrate rewrites the older prefixes in active plans, so it and its
+  // tests must spell them.
   const legacyAllowed = new Set([
     'plugins/dforge/tests/cockpit.test.ts',
+    'plugins/dforge/scripts/dforge-migrate',
+    'plugins/dforge/tests/dforge-migrate.test.sh',
   ]);
   // dforge 3.0 spells the retired name only where it translates historical
   // citations, migrates a pre-3.0 layout, cites this repository's historical
````

- [ ] **Step 4: Run the tests to verify they pass**

Run: `env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/dforge-migrate.test.sh`
Expected: `86 passed, 0 failed`.

Run: `node scripts/validate-repository.mjs`
Expected: exit 0, no error lines.

- [ ] **Step 5: Commit**

```bash
git commit -m "feat(dforge): migrate dr-forge checkouts and plans"
```

### Task 7: Add dforge-migrate --dry-run

**Files:**
- Modify: `plugins/dforge/scripts/dforge-migrate` (the `--dry-run` flag: `would` lines from `done_move`, `merge_into`, `rewrite_names` and `rewrite_prefixes`; `migrate_docs` sets `docs_ok` and `docs_at`; plans and handoff notes are read where they are before the move; the home module runs with `--dry-run`; no `commit:` lines)
- Test: `plugins/dforge/tests/dforge-migrate.test.sh`

**Interfaces:**
- Consumes: C1, C3's `--dry-run` flag (Task 5), C4 (Task 6).
- Produces: C4 with `--dry-run`, which Task 8's skill runs.

**Items:** 2
**Implementer:** dr-superpowers:impl-sonnet-high
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 3 = 5

- [ ] **Step 1: Write the failing tests**

Run C1 with id `t7-tests`, writing `<scratch>/t7-tests.patch`, then `git apply --index <scratch>/t7-tests.patch`.

<!-- block: t7-tests -->
````diff
diff --git a/plugins/dforge/tests/dforge-migrate.test.sh b/plugins/dforge/tests/dforge-migrate.test.sh
index 634214a..d521ce7 100755
--- a/plugins/dforge/tests/dforge-migrate.test.sh
+++ b/plugins/dforge/tests/dforge-migrate.test.sh
@@ -222,6 +222,49 @@ check "links: a linked handoff note is not rewritten" "$(cat "$TMP/outside/note.
 check "links: a linked .gitignore is not rewritten" "$(cat "$TMP/outside/ignore")" ".forge/"
 check "links: a state directory linked outside is not rewritten" "$(cat "$TMP/outside/state/handoff/latest.md")" "dr-forge:resume-execution"
 
+# --- --dry-run: every action listed, nothing written in the checkout or the home ---
+snapshot() { # snapshot DIR... — every path and file checksum under DIR, the git index aside
+  find "$@" -not -path '*/.git/index' -not -path '*/.git/objects/*' -print | sort
+  find "$@" -type f -not -path '*/.git/index' -not -path '*/.git/objects/*' -exec cksum {} + | sort
+}
+DR="$TMP/dry"
+repo "$DR"
+mkdir -p "$DR/.forge/sdd/p1" "$DR/docs/forge/plans" "$DR/.git/dr-forge"
+echo ledger > "$DR/.forge/sdd/p1/progress.md"
+printf '**Implementer:** dr-forge:impl-sonnet-low\n' > "$DR/docs/forge/plans/active.md"
+printf '.forge/\n' > "$DR/.gitignore"
+git -C "$DR" add .gitignore docs
+git -C "$DR" commit -q -m docs
+DH="$TMP/dry-home"
+mkdir -p "$DH/.dr-forge"
+printf '{"handoffTokens":325000}\n' > "$DH/.dr-forge/config.json"
+before=$(snapshot "$DR" "$DH")
+out=$(HOME="$DH" bash "$FM" --dry-run "$DR" 2>&1); code=$?
+check "dry: exit 0" "$code" "0"
+check "dry: nothing written" "$(snapshot "$DR" "$DH")" "$before"
+check "dry: the state move listed" "$(grep -cxF "would move $DR/.forge -> $DR/.dforge" <<<"$out")" "1"
+check "dry: the docs move listed" "$(grep -cxF "would move $DR/docs/forge -> $DR/docs/dforge" <<<"$out")" "1"
+check "dry: the git dir move listed" "$(grep -cxF "would move $DR/.git/dr-forge -> $DR/.git/dforge" <<<"$out")" "1"
+check "dry: the ignore rewrite listed" "$(grep -cxF "would rewrite the older names in $DR/.gitignore" <<<"$out")" "1"
+check "dry: the plan rewrite listed" "$(grep -cxF "would rewrite the plugin prefixes in $DR/docs/forge/plans/active.md" <<<"$out")" "1"
+check "dry: the home move listed" "$(grep -cxF "dforge-home-migrate: would move $DH/.dr-forge to $DH/.dforge" <<<"$out")" "1"
+check "dry: no commit lines" "$(grep -c '^commit:' <<<"$out")" "0"
+out=$(HOME="$DH" bash "$FM" "$DR" 2>&1); code=$?
+check "after the dry run, the real run: exit 0" "$code" "0"
+check "after the dry run, the real run: the plan rewritten" "$(cat "$DR/docs/dforge/plans/active.md")" "**Implementer:** dforge:impl-sonnet-low"
+
+DB="$TMP/dry-both-docs"
+repo "$DB"
+mkdir -p "$DB/docs/forge" "$DB/docs/dforge"
+before=$(snapshot "$DB")
+out=$(bash "$FM" --dry-run "$DB" 2>&1); code=$?
+check "dry, two docs trees: exit 1" "$code" "1"
+check "dry, two docs trees: the refusal foretold" "$(grep -c "refused: $DB/docs/forge and $DB/docs/dforge all exist" <<<"$out")" "1"
+check "dry, two docs trees: nothing written" "$(snapshot "$DB")" "$before"
+
+bash "$FM" --dry-run "$DB" extra > /dev/null 2>&1
+check "dry: a second directory is a usage error" "$?" "2"
+
 # --- the home step runs when dforge-home-migrate.mjs is installed ---
 P="$TMP/plugin/scripts"
 mkdir -p "$P/lib"
````

- [ ] **Step 2: Run the tests to verify they fail**

Run: `env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/dforge-migrate.test.sh`
Expected: FAIL — `92 passed, 9 failed`, starting with `FAIL - dry: exit 0`.

- [ ] **Step 3: Write the implementation**

Run C1 with id `t7-impl`, writing `<scratch>/t7-impl.patch`, then `git apply --index <scratch>/t7-impl.patch`.

<!-- block: t7-impl -->
````diff
diff --git a/plugins/dforge/scripts/dforge-migrate b/plugins/dforge/scripts/dforge-migrate
index e02422a..829cec6 100755
--- a/plugins/dforge/scripts/dforge-migrate
+++ b/plugins/dforge/scripts/dforge-migrate
@@ -1,7 +1,7 @@
 #!/usr/bin/env bash
-# dforge-migrate [DIR] — move a repository from the older names to dforge
-# 4.0's, which reads only the new ones: dr-superpowers' (before 3.0) and
-# dr-forge's (3.x). For the repository at DIR (default: the working
+# dforge-migrate [--dry-run] [DIR] — move a repository from the older names
+# to dforge 4.0's, which reads only the new ones: dr-superpowers' (before 3.0)
+# and dr-forge's (3.x). For the repository at DIR (default: the working
 # directory), its primary checkout and every linked worktree:
 #   .superpowers/, .forge/                    -> .dforge/      (plain rename)
 #   docs/superpowers/ or docs/forge/          -> docs/dforge/  (git mv when tracked)
@@ -25,13 +25,20 @@
 # keeps its old ignore lines and gains the new ones beside them, so a moved
 # directory is never left un-ignored.
 #
-# Exit: 0 done or nothing to do; 1 something was refused; 2 usage or not
-# inside a git repository.
+# --dry-run writes nothing, in the checkouts or the homes: each line says what
+# would move or be rewritten, and each refusal the files and git can foretell
+# is printed. It treats a directory an earlier line would create as absent, so
+# a second source into it is listed as a move rather than a merge.
+#
+# Exit: 0 done or nothing to do; 1 something was (or, dry, would be) refused;
+# 2 usage or not inside a git repository.
 set -uo pipefail
 HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
 . "$HERE/lib/native-path.sh"
 
-[ $# -le 1 ] || { echo "usage: dforge-migrate [DIR]" >&2; exit 2; }
+dry=0
+if [ "${1:-}" = --dry-run ]; then dry=1; shift; fi
+[ $# -le 1 ] || { echo "usage: dforge-migrate [--dry-run] [DIR]" >&2; exit 2; }
 dir=${1:-$PWD}
 
 if command -v timeout >/dev/null 2>&1; then g() { timeout 60 git "$@"; }; else g() { git "$@"; }; fi
@@ -41,13 +48,16 @@ root=$(g -C "$dir" rev-parse --show-toplevel 2>/dev/null) \
 common=$(g -C "$root" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) \
   || { echo "dforge-migrate: cannot read the git directory of $root" >&2; exit 2; }
 
-refused=0 moved=0 checkout_refused=0
+refused=0 moved=0 checkout_refused=0 docs_ok=1 docs_at=""
 checkouts=()
 clean=()
 commit_notes=()
 
 refuse() { printf 'dforge-migrate: refused: %s\n' "$1" >&2; refused=1; checkout_refused=1; }
-done_move() { printf 'moved %s -> %s\n' "$1" "$2"; moved=1; }
+done_move() {
+  if [ "$dry" -eq 1 ]; then printf 'would move %s -> %s\n' "$1" "$2"; else printf 'moved %s -> %s\n' "$1" "$2"; fi
+  moved=1
+}
 
 # same_entry A B — whether two files, or two symlinks, hold the same thing.
 same_entry() {
@@ -62,6 +72,15 @@ same_entry() {
 # lacks moves, an identical one is dropped, a differing one is refused and left.
 merge_into() {
   local from=$1 to=$2 file rel conflicts=0 touched=0
+  if [ "$dry" -eq 1 ]; then
+    while IFS= read -r -d '' file; do
+      rel=${file#"$from"/}
+      if [ ! -e "$to/$rel" ] && [ ! -L "$to/$rel" ]; then printf 'would move %s -> %s\n' "$file" "$to/$rel"; moved=1
+      elif same_entry "$file" "$to/$rel"; then printf 'would drop %s, the same as %s\n' "$file" "$to/$rel"; moved=1
+      else refuse "$file differs from $to/$rel; keep one by hand, then run dforge-migrate again"; fi
+    done < <(find "$from" \( -type f -o -type l \) -print0)
+    return 0
+  fi
   while IFS= read -r -d '' file; do
     rel=${file#"$from"/}
     if [ ! -e "$to/$rel" ] && [ ! -L "$to/$rel" ]; then
@@ -86,7 +105,7 @@ mv_plain() {
     if [ -d "$1" ] && [ -d "$2" ]; then merge_into "$1" "$2"; else refuse "$1 and $2 both exist and are not both directories; merge them by hand, then run dforge-migrate again"; fi
     return 0
   fi
-  if mv -- "$1" "$2"; then done_move "$1" "$2"; else refuse "could not rename $1"; fi
+  if [ "$dry" -eq 1 ] || mv -- "$1" "$2"; then done_move "$1" "$2"; else refuse "could not rename $1"; fi
 }
 
 # docs_trees CHECKOUT — each docs tree the checkout holds, one per line.
@@ -95,26 +114,35 @@ docs_trees() {
   for name in superpowers forge dforge; do [ ! -e "$1/docs/$name" ] || printf '%s\n' "$1/docs/$name"; done
 }
 
-migrate_docs() { # CHECKOUT
+# migrate_docs CHECKOUT — the one docs tree to docs/dforge/. Sets docs_ok to 0
+# when it refused, and docs_at to where the plans are once it is done: the new
+# tree, or in a dry run the tree that would move.
+migrate_docs() {
   local wt=$1 trees name old new="$1/docs/dforge"
+  docs_ok=1 docs_at=""
   trees=$(docs_trees "$wt")
   [ -n "$trees" ] || return 0
   if [ "$(wc -l <<<"$trees")" -gt 1 ]; then
     refuse "$(paste -sd, - <<<"$trees" | sed 's/,/ and /g') all exist; merge them by hand, then run dforge-migrate again"
+    docs_ok=0
     return 0
   fi
+  docs_at=$new
   [ "$trees" != "$new" ] || return 0
   old=$trees name=${trees##*/}
+  [ "$dry" -eq 0 ] || docs_at=$old
   if [ -z "$(g -C "$wt" ls-files -- "docs/$name" | head -n 1)" ]; then mv_plain "$old" "$new"; return 0; fi
   if [ -n "$(g -C "$wt" status --porcelain --untracked-files=all -- "docs/$name")" ]; then
     refuse "$old has uncommitted changes; commit or stash them, then run dforge-migrate again"
+    docs_ok=0
     return 0
   fi
-  if g -C "$wt" mv "docs/$name" docs/dforge; then
+  if [ "$dry" -eq 1 ] || g -C "$wt" mv "docs/$name" docs/dforge; then
     done_move "$old" "$new"
     commit_notes+=("$wt: the staged rename docs/$name/ -> docs/dforge/")
   else
     refuse "git mv docs/$name docs/dforge failed in $wt"
+    docs_ok=0
   fi
 }
 
@@ -145,10 +173,10 @@ rewrite_names() {
         }
       }' "$file" "$renamed" > "$tmp" \
     && ! cmp -s -- "$tmp" "$file" \
-    && cat "$tmp" > "$file" \
+    && { [ "$dry" -eq 1 ] || cat "$tmp" > "$file"; } \
     || { rm -f -- "$tmp" "$renamed"; return 1; }
   rm -f -- "$tmp" "$renamed"
-  printf 'rewrote the older names in %s\n' "$file"
+  if [ "$dry" -eq 1 ]; then printf 'would rewrite the older names in %s\n' "$file"; else printf 'rewrote the older names in %s\n' "$file"; fi
   moved=1
 }
 
@@ -171,6 +199,11 @@ rewrite_prefixes() {
   local file=$1 tmp
   writable "$2" "$file" || return 1
   grep -qE "$PREFIX_RE" "$file" 2>/dev/null || return 1
+  if [ "$dry" -eq 1 ]; then
+    printf 'would rewrite the plugin prefixes in %s\n' "$file"
+    moved=1
+    return 0
+  fi
   tmp=$(mktemp "$file.dforge-migrate.XXXXXX") || { refuse "could not rewrite the plugin prefixes in $file"; return 1; }
   if sed -E "s#$PREFIX_RE#\\1dforge:\\3#g" "$file" > "$tmp" && cat "$tmp" > "$file"; then
     rm -f -- "$tmp"
@@ -194,21 +227,23 @@ plan_done() {
   return 1
 }
 
-# rewrite_active_plans CHECKOUT — every plan under docs/dforge/plans/ that is
+# rewrite_active_plans CHECKOUT DOCS — every plan under DOCS/plans/ that is
 # still active, and the checkout's handoff note.
 rewrite_active_plans() {
-  local wt=$1 docs="$1/docs/dforge" plan rel
-  if [ -d "$docs/plans" ]; then
+  local wt=$1 docs=$2 plan rel state
+  if [ -n "$docs" ] && [ -d "$docs/plans" ]; then
     while IFS= read -r -d '' plan; do
       rel=${plan#"$docs"/}
       [ "${rel##*/}" != completed.md ] || continue
       plan_done "$docs" "$rel" && continue
-      if rewrite_prefixes "$plan" "$wt" && g -C "$wt" ls-files --error-unmatch -- "docs/dforge/$rel" >/dev/null 2>&1; then
+      if rewrite_prefixes "$plan" "$wt" && g -C "$wt" ls-files --error-unmatch -- "${docs#"$wt"/}/$rel" >/dev/null 2>&1; then
         commit_notes+=("$wt: docs/dforge/$rel")
       fi
     done < <(find "$docs/plans" -type f -name '*.md' -print0)
   fi
-  [ ! -f "$wt/.dforge/handoff/latest.md" ] || rewrite_prefixes "$wt/.dforge/handoff/latest.md" "$wt" || true
+  for state in .dforge .forge .superpowers; do
+    [ ! -f "$wt/$state/handoff/latest.md" ] || rewrite_prefixes "$wt/$state/handoff/latest.md" "$wt" || true
+  done
 }
 
 while IFS= read -r wt; do
@@ -225,7 +260,7 @@ for wt in "${checkouts[@]}"; do
     mv_plain "$wt/$old" "$wt/.dforge"
   done
   migrate_docs "$wt"
-  [ -n "$(docs_trees "$wt" | grep -vxF "$wt/docs/dforge")" ] || rewrite_active_plans "$wt"
+  [ "$docs_ok" -eq 0 ] || rewrite_active_plans "$wt" "$docs_at"
   if gitdir=$(g -C "$wt" rev-parse --absolute-git-dir 2>/dev/null); then
     for old in dr-superpowers dr-forge; do mv_plain "$gitdir/$old" "$gitdir/dforge"; done
   else
@@ -256,13 +291,15 @@ if [ -f "$HERE/lib/dforge-home-migrate.mjs" ]; then
       refuse "node is not on PATH, so the homes (~/.dr-superpowers/, ~/.dr-forge/) were not migrated"
     fi
   else
-    home_out=$(cd "$root" && node "$(dr_native_path "$HERE/lib/dforge-home-migrate.mjs")")
+    home_args=()
+    [ "$dry" -eq 0 ] || home_args=(--dry-run)
+    home_out=$(cd "$root" && node "$(dr_native_path "$HERE/lib/dforge-home-migrate.mjs")" "${home_args[@]+"${home_args[@]}"}")
     home_status=$?
     if [ -n "$home_out" ]; then printf '%s\n' "$home_out"; moved=1; fi
     [ "$home_status" -eq 0 ] || refuse "scripts/lib/dforge-home-migrate.mjs did not finish; see its output above"
   fi
 fi
 
-for note in "${commit_notes[@]+"${commit_notes[@]}"}"; do printf 'commit: %s\n' "$note"; done
+[ "$dry" -eq 1 ] || for note in "${commit_notes[@]+"${commit_notes[@]}"}"; do printf 'commit: %s\n' "$note"; done
 [ "$moved" -eq 1 ] || [ "$refused" -eq 1 ] || echo "dforge-migrate: nothing to migrate in $root"
 exit "$refused"
````

- [ ] **Step 4: Run the tests to verify they pass**

Run: `env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/dforge-migrate.test.sh`
Expected: `101 passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git commit -m "feat(dforge): add dforge-migrate --dry-run"
```

### Task 8: Add the migrate skill

**Files:**
- Create: `plugins/dforge/skills/migrate/SKILL.md`
- Modify: `plugins/dforge/skills/using-dforge/SKILL.md` (the routing row)
- Modify: `scripts/validate-repository.mjs` (`legacyAllowed` and `superpowersAllowed` admit the skill, which names the older plugins)
- Test: `plugins/dforge/tests/migrate-skill.test.sh` (new)

**Interfaces:**
- Consumes: C1, C4.
- Produces: C5.

**Items:** 2
**Implementer:** dr-superpowers:impl-sonnet-medium
**Evaluation:** files 2 - spec 0 - coupling 1 - risk 1 = 4

- [ ] **Step 1: Write the failing test**

Run C1 with id `t8-tests`, writing `<scratch>/t8-tests.patch`, then `git apply --index <scratch>/t8-tests.patch`.

<!-- block: t8-tests -->
````diff
diff --git a/plugins/dforge/tests/migrate-skill.test.sh b/plugins/dforge/tests/migrate-skill.test.sh
new file mode 100755
index 0000000..fd4231f
--- /dev/null
+++ b/plugins/dforge/tests/migrate-skill.test.sh
@@ -0,0 +1,38 @@
+#!/usr/bin/env bash
+# The migrate skill is a document: what makes it safe is its order (a dry run
+# before anything writes, a confirmation before the migration and before the
+# commit) and the names it hands the human. A model is not needed to check them.
+set -uo pipefail
+
+HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
+P="$HERE/.."
+SKILL="$P/skills/migrate/SKILL.md"
+
+pass=0 fail=0
+check() { # check <name> <got> <want>
+  if [ "$2" = "$3" ]; then pass=$((pass + 1))
+  else printf 'FAIL - %s\n       got:  [%s]\n       want: [%s]\n' "$1" "$2" "$3"; fail=$((fail + 1)); fi
+}
+present() { # present <name> <file> <needle>
+  if grep -qF -- "$3" "$2"; then pass=$((pass + 1))
+  else printf 'FAIL - %s\n       missing: [%s]\n       in: [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
+}
+line_of() { grep -nF -- "$2" "$1" | head -n 1 | cut -d: -f1; }
+
+check "exists: skills/migrate/SKILL.md" "$([ -f "$SKILL" ] && echo yes || echo no)" "yes"
+present "named migrate" "$SKILL" "name: migrate"
+dry=$(line_of "$SKILL" 'scripts/dforge-migrate --dry-run')
+real=$(line_of "$SKILL" 'Run `bash <plugin-root>/scripts/dforge-migrate` and show')
+confirm=$(line_of "$SKILL" 'Run nothing')
+check "the dry run comes first" "$([ -n "$dry" ] && [ -n "$real" ] && [ "$dry" -lt "$real" ] && echo yes || echo no)" "yes"
+check "the confirmation comes before the migration" "$([ -n "$confirm" ] && [ "$confirm" -lt "$real" ] && echo yes || echo no)" "yes"
+present "asks before migrating" "$SKILL" "that writes before a yes"
+present "asks before committing" "$SKILL" "human partner agrees, and stage nothing"
+present "commits only what the commit lines name" "$SKILL" "stage nothing the lines do not name"
+present "names the plugin uninstall" "$SKILL" '`dr-forge@darkraise` and `dr-superpowers@darkraise`'
+present "names the environment rename" "$SKILL" '`DFORGE_*` environment variables in place of `DR_FORGE_*`'
+present "writes nothing itself" "$SKILL" "This skill writes nothing"
+present "the entry point routes to it" "$P/skills/using-dforge/SKILL.md" "| dforge:migrate |"
+
+printf '\n%d passed, %d failed\n' "$pass" "$fail"
+[ "$fail" -eq 0 ]
````

- [ ] **Step 2: Run the test to verify it fails**

Run: `env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/migrate-skill.test.sh`
Expected: FAIL — `0 passed, 11 failed`, starting with `FAIL - exists: skills/migrate/SKILL.md`.

- [ ] **Step 3: Write the skill**

Run C1 with id `t8-impl`, writing `<scratch>/t8-impl.patch`, then `git apply --index <scratch>/t8-impl.patch`.

<!-- block: t8-impl -->
````diff
diff --git a/plugins/dforge/skills/migrate/SKILL.md b/plugins/dforge/skills/migrate/SKILL.md
new file mode 100644
index 0000000..e142541
--- /dev/null
+++ b/plugins/dforge/skills/migrate/SKILL.md
@@ -0,0 +1,54 @@
+---
+name: migrate
+description: Use when session start or repo-audit says a repository or home still uses an older layout, or when moving from dr-superpowers or dr-forge to dforge - previews the move with a dry run, migrates on one confirmation, and offers the commit
+---
+
+# Migrate
+
+**Announce at start:** "I'm using the migrate skill to move this repository to dforge's names."
+
+dforge reads only its own names. A repository or home that dr-superpowers
+(before 3.0) or dr-forge (3.x) set up keeps its work under the older ones until
+`scripts/dforge-migrate` moves it:
+
+| Older | dforge |
+|---|---|
+| `.superpowers/`, `.forge/` | `.dforge/` |
+| `docs/superpowers/`, `docs/forge/` | `docs/dforge/` |
+| `<git dir>/dr-superpowers/`, `<git dir>/dr-forge/` | `<git dir>/dforge/` |
+| `~/.dr-superpowers/`, `~/.dr-forge/` | `~/.dforge/` |
+| darkmem's `superpowers/` and `forge/` documents | `dforge/` |
+
+An active plan (one its `completed.md` does not record) and the handoff note
+get their `dr-superpowers:` and `dr-forge:` prefixes rewritten to `dforge:`,
+so they keep running. Finished plans, specs, ledgers and registers keep their
+text as history; dforge still reads their citations.
+
+Every change goes through `scripts/dforge-migrate`. This skill writes nothing
+itself.
+
+## Steps
+
+1. **Preview.** From the repository, run
+   `bash <plugin-root>/scripts/dforge-migrate --dry-run` and show its output.
+   When `~/.dr-forge/config.json`, `~/.dr-superpowers/config.json` or
+   `~/.dforge/config.json` holds a `darkmem` section, say that darkmem's
+   documents move to `dforge/` at its next sync.
+2. **Nothing to move.** When it prints `nothing to migrate`, say so and stop.
+3. **Foretold refusals.** When it exits 1, show each `refused:` line with the
+   fix it names, and ask whether to resolve them first. A refusal stops only
+   its own part; the rest still moves.
+4. **Confirm once.** Ask your human partner whether to migrate. Run nothing
+   that writes before a yes.
+5. **Migrate.** Run `bash <plugin-root>/scripts/dforge-migrate` and show its
+   output. On exit 1, list each refusal and its fix, and offer to run it again
+   once they are resolved: a second run finishes the job.
+6. **Commit.** Show the `commit:` lines and offer to commit what they name as
+   one commit, `chore: move to the dforge layout`. Commit only after your
+   human partner agrees, and stage nothing the lines do not name.
+7. **Retire the old plugins.** Remind your human partner to uninstall
+   `dr-forge@darkraise` and `dr-superpowers@darkraise` when either is
+   installed (`claude plugin uninstall <name>`, or `codex plugin remove
+   <name>`), so their hooks do not run beside dforge's. dforge reads
+   `DFORGE_*` environment variables in place of `DR_FORGE_*`: rename any that
+   a shell profile sets.
diff --git a/plugins/dforge/skills/using-dforge/SKILL.md b/plugins/dforge/skills/using-dforge/SKILL.md
index bd3baee..b55f537 100644
--- a/plugins/dforge/skills/using-dforge/SKILL.md
+++ b/plugins/dforge/skills/using-dforge/SKILL.md
@@ -40,6 +40,7 @@ If a skill might apply to what you are doing, invoke it before any response or a
 | Before the final review or merge, when `gates.md` exists | dforge:running-gates |
 | Session notes have accumulated | dforge:distilling-docs |
 | Slow or heavy tests | dforge:test-simplifier |
+| A repository or home on an older layout | dforge:migrate |
 
 ## Principles
 
diff --git a/scripts/validate-repository.mjs b/scripts/validate-repository.mjs
index b758a28..41b7c3d 100644
--- a/scripts/validate-repository.mjs
+++ b/scripts/validate-repository.mjs
@@ -88,11 +88,12 @@ export function validateRepository(root) {
   }
   const legacyPattern = /(?:^|[^\w-])superpowers:|dr-superpowers:|dcc-superpower-companions:/;
   // dforge-migrate rewrites the older prefixes in active plans, so it and its
-  // tests must spell them.
+  // tests and the migrate skill must spell them.
   const legacyAllowed = new Set([
     'plugins/dforge/tests/cockpit.test.ts',
     'plugins/dforge/scripts/dforge-migrate',
     'plugins/dforge/tests/dforge-migrate.test.sh',
+    'plugins/dforge/skills/migrate/SKILL.md',
   ]);
   // dforge 3.0 spells the retired name only where it translates historical
   // citations, migrates a pre-3.0 layout, cites this repository's historical
@@ -109,6 +110,7 @@ export function validateRepository(root) {
     'plugins/dforge/reference/auto-run.md',
     'plugins/dforge/reference/parallel-waves.md',
     'plugins/dforge/reference/session-budget.md',
+    'plugins/dforge/skills/migrate/SKILL.md',
   ]);
   const superpowersExempt = rel => superpowersAllowed.has(rel) ||
     /^plugins\/dforge\/(?:LICENSES|tests)\//.test(rel) ||
````

- [ ] **Step 4: Run the test to verify it passes**

Run: `env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/migrate-skill.test.sh`
Expected: `11 passed, 0 failed`.

Run: `node scripts/validate-repository.mjs`
Expected: exit 0, no error lines.

- [ ] **Step 5: Commit**

```bash
git commit -m "feat(dforge): add the migrate skill"
```

### Task 9: Detect the dr-forge layout

**Files:**
- Modify: `plugins/dforge/scripts/lib/dforge-dir.sh` (`dforge_legacy_layout`)
- Test: `plugins/dforge/tests/dforge-dir.test.sh`

**Interfaces:**
- Consumes: C1, C2.
- Produces: C6.

**Items:** 1
**Implementer:** dr-superpowers:impl-sonnet-medium
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 1 = 3

- [ ] **Step 1: Write the failing tests**

Run C1 with id `t9-tests`, writing `<scratch>/t9-tests.patch`, then `git apply --index <scratch>/t9-tests.patch`.

<!-- block: t9-tests -->
````diff
diff --git a/plugins/dforge/tests/dforge-dir.test.sh b/plugins/dforge/tests/dforge-dir.test.sh
index 9e387cd..0611911 100755
--- a/plugins/dforge/tests/dforge-dir.test.sh
+++ b/plugins/dforge/tests/dforge-dir.test.sh
@@ -100,6 +100,20 @@ check "home: reported once beside a repository path" "$(mkdir -p "$R/.superpower
 rm -rf "$R/.superpowers" "$OLDH"
 export HOME=$SAVED_HOME
 
+# --- dforge_legacy_layout: dr-forge's 3.x names ---
+mkdir -p "$R/.forge" "$R/docs/forge"
+check "dr-forge: state and docs" "$(dforge_legacy_layout "$R" | tr '\n' '|')" "$R/.forge|$R/docs/forge|"
+rm -rf "$R/.forge" "$R/docs/forge"
+mkdir -p "$WG/dr-forge" "$G/.forge"
+check "dr-forge: a worktree's git dir and the primary's state" "$(dforge_legacy_layout "$W" | tr '\n' '|')" "$WG/dr-forge|$TOP/.forge|"
+rm -rf "$WG/dr-forge" "$G/.forge"
+SAVED_HOME=$HOME
+export HOME="$TMP/home3"; mkdir -p "$HOME/.dr-forge"
+check "dr-forge: an empty ~/.dr-forge is not named" "$(dforge_legacy_layout "$R")" ""
+printf '{}\n' > "$HOME/.dr-forge/config.json"
+check "dr-forge: a ~/.dr-forge holding anything is named" "$(dforge_legacy_layout "$R")" "$HOME/.dr-forge"
+export HOME=$SAVED_HOME
+
 # Codex runs no session-start hook, so its tool notes carry the check.
 check "codex-tools: names the pre-3.0 check" "$(grep -c 'pre-3.0 layout' "$HERE/../skills/using-dforge/references/codex-tools.md")" "1"
 
````

- [ ] **Step 2: Run the tests to verify they fail**

Run: `env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/dforge-dir.test.sh`
Expected: FAIL — `35 passed, 3 failed`: `dr-forge: state and docs`, `dr-forge: a worktree's git dir and the primary's state`, `dr-forge: a ~/.dr-forge holding anything is named`.

- [ ] **Step 3: Write the implementation**

Run C1 with id `t9-impl`, writing `<scratch>/t9-impl.patch`, then `git apply --index <scratch>/t9-impl.patch`.

<!-- block: t9-impl -->
````diff
diff --git a/plugins/dforge/scripts/lib/dforge-dir.sh b/plugins/dforge/scripts/lib/dforge-dir.sh
index 77e318d..2ec68b1 100644
--- a/plugins/dforge/scripts/lib/dforge-dir.sh
+++ b/plugins/dforge/scripts/lib/dforge-dir.sh
@@ -37,27 +37,34 @@ dforge_dir_rel() {
   printf '%s\n' "${dir#"${2:-.}"/}"
 }
 
-# dforge_legacy_layout [ROOT] — each pre-3.0 path of the checkout at ROOT
-# (default: .) that still exists, one per line: its .superpowers/ and
-# docs/superpowers/, its git dir's dr-superpowers/, and the primary checkout's
-# .superpowers/, which holds a linked worktree's handoff. It also names
-# ~/.dr-superpowers when that home is unmigrated: its config holds a darkmem
-# mapping the new config lacks, or its mirror folder still holds a mirror.
-# dforge reads none of them since 3.0.0, so scripts/dforge-migrate must move
-# them first.
+# dforge_legacy_layout [ROOT] — each older path of the checkout at ROOT
+# (default: .) that still exists, one per line: dr-superpowers' (before 3.0)
+# and dr-forge's (3.x) state directories .superpowers/ and .forge/, docs trees
+# docs/superpowers/ and docs/forge/, its git dir's dr-superpowers/ and
+# dr-forge/, and the primary checkout's .superpowers/ and .forge/, which hold a
+# linked worktree's handoff. It also names ~/.dr-superpowers when that home is
+# unmigrated (its config holds a darkmem mapping the new config lacks, or its
+# mirror folder still holds a mirror) and ~/.dr-forge while it holds anything.
+# dforge reads none of them, so the migrate skill must move them first.
 dforge_legacy_layout() {
-  local root=${1:-.} gitdir common primary home=${HOME:-}/.dr-superpowers
+  local root=${1:-.} gitdir common primary home=${HOME:-}/.dr-superpowers name
   if [ -n "${HOME:-}" ] && {
     { grep -qs '"darkmem"[[:space:]]*:' "$home/config.json" && ! grep -qs '"darkmem"[[:space:]]*:' "${HOME}/.dforge/config.json"; } ||
     [ -n "$(ls -A "$home/mirror" 2>/dev/null)" ]
   }; then printf '%s\n' "$home"; fi
-  [ ! -e "$root/.superpowers" ] || printf '%s\n' "$root/.superpowers"
-  [ ! -e "$root/docs/superpowers" ] || printf '%s\n' "$root/docs/superpowers"
+  [ -z "${HOME:-}" ] || [ -z "$(ls -A "$HOME/.dr-forge" 2>/dev/null)" ] || printf '%s\n' "$HOME/.dr-forge"
+  for name in .superpowers .forge docs/superpowers docs/forge; do
+    [ ! -e "$root/$name" ] || printf '%s\n' "$root/$name"
+  done
   gitdir=$(git -C "$root" rev-parse --absolute-git-dir 2>/dev/null) || return 0
-  [ ! -e "$gitdir/dr-superpowers" ] || printf '%s\n' "$gitdir/dr-superpowers"
+  for name in dr-superpowers dr-forge; do
+    [ ! -e "$gitdir/$name" ] || printf '%s\n' "$gitdir/$name"
+  done
   common=$(git -C "$root" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || return 0
   [ "$common" != "$gitdir" ] || return 0
   primary=$(git -C "$(dirname "$common")" rev-parse --show-toplevel 2>/dev/null) || return 0
-  [ ! -e "$primary/.superpowers" ] || printf '%s\n' "$primary/.superpowers"
+  for name in .superpowers .forge; do
+    [ ! -e "$primary/$name" ] || printf '%s\n' "$primary/$name"
+  done
   return 0
 }
````

- [ ] **Step 4: Run the tests to verify they pass**

Run: `env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/dforge-dir.test.sh`
Expected: `38 passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git commit -m "feat(dforge): detect the dr-forge layout"
```

### Task 10: Point the layout line at /dforge:migrate

**Files:**
- Modify: `plugins/dforge/scripts/session-start.sh`, `plugins/dforge/scripts/repo-audit` (C7's line)
- Modify: `plugins/dforge/skills/using-dforge/references/codex-tools.md` (Codex runs no session-start hook, so its notes name the check)
- Test: `plugins/dforge/tests/hook.test.sh`, `plugins/dforge/tests/repo-audit.test.sh`, `plugins/dforge/tests/dforge-dir.test.sh`

**Interfaces:**
- Consumes: C1, C5 (the validator rejects `dforge:migrate` until the skill exists), C6.
- Produces: C7.

**Items:** 1
**Implementer:** dr-superpowers:impl-sonnet-medium
**Evaluation:** files 2 - spec 0 - coupling 1 - risk 1 = 4

- [ ] **Step 1: Write the failing tests**

Run C1 with id `t10-tests`, writing `<scratch>/t10-tests.patch`, then `git apply --index <scratch>/t10-tests.patch`.

<!-- block: t10-tests -->
````diff
diff --git a/plugins/dforge/tests/dforge-dir.test.sh b/plugins/dforge/tests/dforge-dir.test.sh
index 0611911..4cbe34f 100755
--- a/plugins/dforge/tests/dforge-dir.test.sh
+++ b/plugins/dforge/tests/dforge-dir.test.sh
@@ -115,7 +115,7 @@ check "dr-forge: a ~/.dr-forge holding anything is named" "$(dforge_legacy_layou
 export HOME=$SAVED_HOME
 
 # Codex runs no session-start hook, so its tool notes carry the check.
-check "codex-tools: names the pre-3.0 check" "$(grep -c 'pre-3.0 layout' "$HERE/../skills/using-dforge/references/codex-tools.md")" "1"
+check "codex-tools: names the older-layout check" "$(grep -c 'an `older layout` line' "$HERE/../skills/using-dforge/references/codex-tools.md")" "1"
 
 printf '\n%d passed, %d failed\n' "$pass" "$fail"
 [ "$fail" -eq 0 ]
diff --git a/plugins/dforge/tests/hook.test.sh b/plugins/dforge/tests/hook.test.sh
index e36ae60..6908890 100644
--- a/plugins/dforge/tests/hook.test.sh
+++ b/plugins/dforge/tests/hook.test.sh
@@ -164,13 +164,13 @@ check "roadmap: survives compaction alongside the snapshot" "$(grep -c '^Roadmap
 check "roadmap: still under the 10,000-character hook cap" "$([ "${#rm_ctx}" -lt 10000 ] && echo yes || echo no)" "yes"
 check "no roadmap: nothing injected" "$(grep -c '^Roadmap:' <<<"$startup_ctx")" "0"
 
-# --- a pre-3.0 directory left behind is named, with the command that moves it ---
-check "3.0 layout: no migration line" "$(grep -c 'pre-3.0 layout' <<<"$rm_ctx")" "0"
+# --- an older directory left behind is named, with the skill that moves it ---
+check "4.0 layout: no migration line" "$(grep -c 'still uses an older layout' <<<"$rm_ctx")" "0"
 mkdir -p "$REPO/.superpowers"
 lg_out=$(startup_payload | HOME="$HOME_D" bash "$SCRIPT" 2>/dev/null)
 check "pre-3.0: output stays valid JSON" "$(jq -e . >/dev/null 2>&1 <<<"$lg_out" && echo yes || echo no)" "yes"
 check "pre-3.0: the migration line is injected" \
-  "$(jq -r '.hookSpecificOutput.additionalContext // ""' <<<"$lg_out" | grep -cF "dforge: this repository still uses the pre-3.0 layout ($(git -C "$REPO" rev-parse --show-toplevel)/.superpowers); run bash $(cd "$HERE/.." && pwd)/scripts/dforge-migrate")" "1"
+  "$(jq -r '.hookSpecificOutput.additionalContext // ""' <<<"$lg_out" | grep -cF "dforge: this repository still uses an older layout ($(git -C "$REPO" rev-parse --show-toplevel)/.superpowers); run the dforge:migrate skill (/dforge:migrate)")" "1"
 rm -rf "$REPO/.superpowers"
 
 # --- workflow settings ride in every session as one line ---
diff --git a/plugins/dforge/tests/repo-audit.test.sh b/plugins/dforge/tests/repo-audit.test.sh
index 2b47fdb..f06186d 100755
--- a/plugins/dforge/tests/repo-audit.test.sh
+++ b/plugins/dforge/tests/repo-audit.test.sh
@@ -150,15 +150,15 @@ out=$(cd "$REPO" && bash "$SCRIPT")
 has "lettered: the task total is unknown" "$out" "- \`docs/lettered.md\` in \`$ROOT\`: 0 of ? tasks complete"
 rm -rf "$REPO/docs/lettered.md" "$REPO/.dforge/sdd/lettered"
 
-# --- a pre-3.0 directory is named with the command that moves it ---
-check "3.0 layout: no migration line" "$(grep -c 'pre-3.0 layout' <<<"$out")" "0"
+# --- an older directory is named with the skill that moves it ---
+check "4.0 layout: no migration line" "$(grep -c 'older layout' <<<"$out")" "0"
 W2="$TMP/wt2"
 git -C "$REPO" worktree add -q --detach "$W2"
 W2_ROOT="$(git -C "$W2" rev-parse --show-toplevel)"
 mkdir -p "$REPO/.superpowers" "$W2/docs/superpowers"
 out=$(cd "$W2" && bash "$SCRIPT" 2>&1)
 has "pre-3.0: the worktree's and the primary's directories, and the command" "$out" \
-  "- dforge: this repository still uses the pre-3.0 layout ($ROOT/.superpowers, $W2_ROOT/docs/superpowers); run bash $(cd "$HERE/../scripts" && pwd)/dforge-migrate"
+  "- dforge: this repository still uses an older layout ($ROOT/.superpowers, $W2_ROOT/docs/superpowers); run the dforge:migrate skill (/dforge:migrate)"
 git -C "$REPO" worktree remove --force "$W2" >/dev/null 2>&1
 rm -rf "$REPO/.superpowers"
 
````

- [ ] **Step 2: Run the tests to verify they fail**

Run each: `env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/hook.test.sh`, then `repo-audit.test.sh`, then `dforge-dir.test.sh`
Expected: FAIL in each: `68 passed, 1 failed` (`FAIL - pre-3.0: the migration line is injected`), `34 passed, 1 failed` (`FAIL - pre-3.0: the worktree's and the primary's directories, and the command`), `37 passed, 1 failed` (`FAIL - codex-tools: names the older-layout check`).

- [ ] **Step 3: Write the implementation**

Run C1 with id `t10-impl`, writing `<scratch>/t10-impl.patch`, then `git apply --index <scratch>/t10-impl.patch`.

<!-- block: t10-impl -->
````diff
diff --git a/plugins/dforge/scripts/repo-audit b/plugins/dforge/scripts/repo-audit
index af756a4..8e0c964 100755
--- a/plugins/dforge/scripts/repo-audit
+++ b/plugins/dforge/scripts/repo-audit
@@ -32,7 +32,7 @@ echo "- Root: \`$root\`"
 echo "- Branch: \`$branch\` at $head$tracking"
 echo "- $("$here/context-size" 2>/dev/null)"
 legacy=$( { dforge_legacy_layout "$root"; [ "$root" = "$primary" ] || dforge_legacy_layout "$primary"; } | sort -u | paste -sd, - | sed 's/,/, /g')
-[ -z "$legacy" ] || echo "- dforge: this repository still uses the pre-3.0 layout ($legacy); run bash $here/dforge-migrate"
+[ -z "$legacy" ] || echo "- dforge: this repository still uses an older layout ($legacy); run the dforge:migrate skill (/dforge:migrate)"
 
 echo
 echo "## Worktrees"
diff --git a/plugins/dforge/scripts/session-start.sh b/plugins/dforge/scripts/session-start.sh
index e359626..6dabe34 100644
--- a/plugins/dforge/scripts/session-start.sh
+++ b/plugins/dforge/scripts/session-start.sh
@@ -100,13 +100,13 @@ if [ -n "$settings_line" ]; then
   context="${context}\n\n$(escape_for_json "$settings_line")"
 fi
 
-# dforge reads none of the pre-3.0 names, so a repository that still has them
+# dforge reads none of the older names, so a repository that still has them
 # would split its work between the old directories and the new ones unnoticed.
 legacy_line=""
 if [ -n "$roadmap_root" ]; then
   legacy=$(dforge_legacy_layout "$roadmap_root" | paste -sd, - | sed 's/,/, /g' | tr -d '\001-\037')
   if [ -n "$legacy" ]; then
-    legacy_line="dforge: this repository still uses the pre-3.0 layout ($legacy); run bash $plugin_root_shown/scripts/dforge-migrate"
+    legacy_line="dforge: this repository still uses an older layout ($legacy); run the dforge:migrate skill (/dforge:migrate)"
     context="${context}\n\n$(escape_for_json "$legacy_line")"
   fi
 fi
diff --git a/plugins/dforge/skills/using-dforge/references/codex-tools.md b/plugins/dforge/skills/using-dforge/references/codex-tools.md
index 044e05d..c464997 100644
--- a/plugins/dforge/skills/using-dforge/references/codex-tools.md
+++ b/plugins/dforge/skills/using-dforge/references/codex-tools.md
@@ -39,9 +39,9 @@ disagree.
 ## Pre-3.0 layout check
 
 Codex runs no session-start hook, so nothing reports a repository or home that
-still uses the pre-3.0 names. Run `scripts/repo-audit` once at the start of a
-session; if it prints a `pre-3.0 layout` line, run the `dforge-migrate` command
-that line names before any other work.
+still uses an older layout. Run `scripts/repo-audit` once at the start of a
+session; if it prints an `older layout` line, use the `dforge:migrate` skill
+before any other work.
 
 ## Waiting on children
 
````

- [ ] **Step 4: Run the tests to verify they pass**

Run the three commands of Step 2.
Expected: `69 passed, 0 failed`, `35 passed, 0 failed`, `38 passed, 0 failed`.

Run: `node scripts/validate-repository.mjs`
Expected: exit 0, no error lines.

- [ ] **Step 5: Commit**

```bash
git commit -m "feat(dforge): point the layout line at /dforge:migrate"
```

### Task 11: Read docs/forge citations in roots.sh and the cockpit

**Files:**
- Modify: `plugins/dforge/scripts/lib/roots.sh` (`dforge_name_key`, `dforge_name_spellings`, `dforge_resolve`)
- Modify: `plugins/dforge/hooks/cockpit/lib.ts` (`planCandidates`)
- Test: `plugins/dforge/tests/roots.test.sh`, `plugins/dforge/tests/cockpit.test.ts`

**Interfaces:**
- Consumes: C1, C2.
- Produces: `docs/forge/<rest>` read as `docs/dforge/<rest>`; `dforge_name_spellings` prints the key, then the `docs/forge/` and `docs/superpowers/` spellings.

**Items:** 1
**Implementer:** dr-superpowers:impl-sonnet-high
**Evaluation:** files 2 - spec 0 - coupling 1 - risk 2 = 5

- [ ] **Step 1: Write the failing tests**

Run C1 with id `t11-tests`, writing `<scratch>/t11-tests.patch`, then `git apply --index <scratch>/t11-tests.patch`.

<!-- block: t11-tests -->
````diff
diff --git a/plugins/dforge/tests/cockpit.test.ts b/plugins/dforge/tests/cockpit.test.ts
index 9ea1727..e117393 100644
--- a/plugins/dforge/tests/cockpit.test.ts
+++ b/plugins/dforge/tests/cockpit.test.ts
@@ -2405,15 +2405,16 @@ describe('cockpit roots', () => {
     const darkmem = { store: 'darkmem' as const, root: `${MIRROR}/superpowers` }
     const w = { root: '/w', docsDir: '/w/docs/dforge' }
     const p = { root: '/p', docsDir: '/p/docs/dforge' }
-    for (const name of ['docs/superpowers/plans/p.md', 'docs/dforge/plans/p.md', './docs/dforge/plans/p.md']) {
+    for (const name of ['docs/superpowers/plans/p.md', 'docs/forge/plans/p.md', 'docs/dforge/plans/p.md', './docs/dforge/plans/p.md']) {
       expect(planCandidates(name, darkmem, [w, p])).toEqual([`${MIRROR}/superpowers/plans/p.md`])
-      // Either prefix names the same document: a pre-3.0 citation reads under each checkout's docs/dforge.
+      // Every prefix names the same document: an older citation reads under each checkout's docs/dforge.
       expect(planCandidates(name, { store: 'local', root: '/p/docs/dforge' }, [w, p])).toEqual(['/w/docs/dforge/plans/p.md', '/p/docs/dforge/plans/p.md'])
       expect(planCandidates(name, null, [p, p])).toEqual(['/p/docs/dforge/plans/p.md'])
     }
     expect(planCandidates('docs/plans/p.md', null, [w, p])).toEqual(['/w/docs/plans/p.md', '/p/docs/plans/p.md'])
     expect(planCandidates('/abs/plans/p.md', darkmem, [w])).toEqual(['/abs/plans/p.md'])
     expect(planCandidates('docs/superpowersx/p.md', darkmem, [w])).toEqual(['/w/docs/superpowersx/p.md'])
+    expect(planCandidates('docs/forgex/p.md', darkmem, [w])).toEqual(['/w/docs/forgex/p.md'])
   })
 
   test('reads a plan named under docs/superpowers from a checkout that has only docs/dforge', async ($, on) => {
diff --git a/plugins/dforge/tests/roots.test.sh b/plugins/dforge/tests/roots.test.sh
index a197f75..3b3e681 100644
--- a/plugins/dforge/tests/roots.test.sh
+++ b/plugins/dforge/tests/roots.test.sh
@@ -84,9 +84,13 @@ printf 'p\n' > "$WT/docs/dforge/plans/p.md"
 check "subdirectory: a relative file" "$(cd "$WT/docs/dforge/plans" && dforge_name p.md)" "docs/dforge/plans/p.md"
 check "subdirectory: a name that is no file here stays" "$(cd "$WT/docs/dforge/plans" && dforge_name docs/superpowers/plans/p.md)" "docs/superpowers/plans/p.md"
 check "a historical citation resolves to the file" "$(cd "$WT" && cat "$(dforge_resolve docs/superpowers/plans/p.md)")" "p"
+check "a 3.x citation resolves to the file" "$(cd "$WT" && cat "$(dforge_resolve docs/forge/plans/p.md)")" "p"
 
 # --- one name under either docs prefix (spec §7.1) ---
 check "name key: the pre-2.0 prefix" "$(dforge_name_key docs/superpowers/plans/p.md)" "docs/dforge/plans/p.md"
+check "name key: the 3.x prefix" "$(dforge_name_key docs/forge/plans/p.md)" "docs/dforge/plans/p.md"
+check "name key: a bare docs/forge" "$(dforge_name_key docs/forge)" "docs/dforge"
+check "name key: docs/forgex is another name" "$(dforge_name_key docs/forgex/a.md)" "docs/forgex/a.md"
 check "name key: the dforge prefix" "$(dforge_name_key docs/dforge/plans/p.md)" "docs/dforge/plans/p.md"
 check "name key: a bare docs/superpowers" "$(dforge_name_key docs/superpowers)" "docs/dforge"
 check "name key: a leading ./" "$(dforge_name_key ./docs/superpowers/specs/s.md)" "docs/dforge/specs/s.md"
@@ -94,9 +98,9 @@ check "name key: docs/superpowersx is another name" "$(dforge_name_key docs/supe
 check "name key: a name outside the docs directory" "$(dforge_name_key .dforge/sdd/p/progress.md)" ".dforge/sdd/p/progress.md"
 check "name key: an absolute path stays" "$(dforge_name_key /x/docs/superpowers/a.md)" "/x/docs/superpowers/a.md"
 check "name spellings: a document name" \
-  "$(dforge_name_spellings docs/superpowers/plans/p.md | tr '\n' '|')" "docs/dforge/plans/p.md|docs/superpowers/plans/p.md|"
+  "$(dforge_name_spellings docs/superpowers/plans/p.md | tr '\n' '|')" "docs/dforge/plans/p.md|docs/forge/plans/p.md|docs/superpowers/plans/p.md|"
 check "name spellings: the docs directory itself" \
-  "$(dforge_name_spellings ./docs/dforge | tr '\n' '|')" "docs/dforge|docs/superpowers|"
+  "$(dforge_name_spellings ./docs/dforge | tr '\n' '|')" "docs/dforge|docs/forge|docs/superpowers|"
 check "name spellings: any other name" "$(dforge_name_spellings .dforge/x.md | tr '\n' '|')" ".dforge/x.md|"
 
 # --- the mapped project, from roots.sh and from dforge-path ---
````

- [ ] **Step 2: Run the tests to verify they fail**

Run: `env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/roots.test.sh`
Expected: FAIL — `136 passed, 5 failed`, starting with `FAIL - a 3.x citation resolves to the file`.

Run: `env -u CLAUDE_CONFIG_DIR timeout 300 /root/.local/bin/claude plugin test plugins/dforge`
Expected: FAIL — `217 pass`, `1 fail`: `cockpit roots > resolves a plan under the docs root in darkmem, under the docs directory of each checkout otherwise`.

- [ ] **Step 3: Write the implementation**

Run C1 with id `t11-impl`, writing `<scratch>/t11-impl.patch`, then `git apply --index <scratch>/t11-impl.patch`.

<!-- block: t11-impl -->
````diff
diff --git a/plugins/dforge/hooks/cockpit/lib.ts b/plugins/dforge/hooks/cockpit/lib.ts
index 9469b5b..fcf1ed7 100644
--- a/plugins/dforge/hooks/cockpit/lib.ts
+++ b/plugins/dforge/hooks/cockpit/lib.ts
@@ -503,14 +503,14 @@ export function isAbsolutePath(path: string): boolean {
  * §7.1 and §7.3): an absolute name as written; a document name under the docs
  * root while documents are in darkmem, else under each checkout's own docs
  * directory; any other name under each checkout. The session's checkout comes
- * first. A ledger written before 3.0.0 cites its plan as
- * docs/superpowers/<rest>, which still names docs/dforge/<rest>: ledgers are
- * never rewritten.
+ * first. A ledger written before 4.0.0 cites its plan as docs/forge/<rest>,
+ * or before 3.0.0 as docs/superpowers/<rest>; both still name
+ * docs/dforge/<rest>: ledgers are never rewritten.
  */
 export function planCandidates(plan: string, docs: CockpitRoots['docs'] | null, checkouts: readonly { root: string; docsDir: string }[]): string[] {
   if (isAbsolutePath(plan)) return [plan]
   const name = plan.replace(/^\.\//, '')
-  const doc = /^docs\/(?:dforge|superpowers)(?:\/(.*))?$/.exec(name)
+  const doc = /^docs\/(?:dforge|forge|superpowers)(?:\/(.*))?$/.exec(name)
   const under = (dir: string) => (doc?.[1] ? `${dir}/${doc[1]}` : dir)
   if (doc && docs?.store === 'darkmem') return [under(docs.root)]
   const seen = new Set<string>()
diff --git a/plugins/dforge/scripts/lib/roots.sh b/plugins/dforge/scripts/lib/roots.sh
index 2ea21b4..90d945d 100644
--- a/plugins/dforge/scripts/lib/roots.sh
+++ b/plugins/dforge/scripts/lib/roots.sh
@@ -114,44 +114,47 @@ dforge_ledger_files() {
   return 0
 }
 
-# dforge_name_key NAME — the one name both docs prefixes share (store options
-# spec §7.1): docs/superpowers/<rest> is docs/dforge/<rest>. dforge has
-# written only docs/dforge since 3.0.0, but plans, specs, ledgers and registers
-# written before it cite the old prefix and are never rewritten, so every
-# comparison of two document names compares their keys.
+# dforge_name_key NAME — the one name every docs prefix shares (store options
+# spec §7.1): docs/superpowers/<rest> (before 3.0) and docs/forge/<rest> (3.x)
+# are docs/dforge/<rest>. dforge has written only docs/dforge since 4.0.0, but
+# plans, specs, ledgers and registers written before it cite an old prefix and
+# are never rewritten, so every comparison of two document names compares
+# their keys.
 dforge_name_key() {
   local name=${1#./}
   case $name in
-    docs/superpowers) printf 'docs/dforge\n' ;;
+    docs/superpowers|docs/forge) printf 'docs/dforge\n' ;;
     docs/superpowers/*) printf 'docs/dforge/%s\n' "${name#docs/superpowers/}" ;;
+    docs/forge/*) printf 'docs/dforge/%s\n' "${name#docs/forge/}" ;;
     *) printf '%s\n' "$name" ;;
   esac
 }
 
 # dforge_name_spellings NAME — the key, then for a document name the same name
-# under the pre-3.0 docs/superpowers. completed.md and register cells keep the
-# spelling they were written with, so a search runs once per line and accepts
-# either.
+# under the 3.x docs/forge and the pre-3.0 docs/superpowers. completed.md and
+# register cells keep the spelling they were written with, so a search runs
+# once per line and accepts any.
 dforge_name_spellings() {
   local key
   key=$(dforge_name_key "$1")
   printf '%s\n' "$key"
   case $key in
-    docs/dforge) printf 'docs/superpowers\n' ;;
-    docs/dforge/*) printf 'docs/superpowers/%s\n' "${key#docs/dforge/}" ;;
+    docs/dforge) printf 'docs/forge\ndocs/superpowers\n' ;;
+    docs/dforge/*) printf 'docs/forge/%s\ndocs/superpowers/%s\n' "${key#docs/dforge/}" "${key#docs/dforge/}" ;;
   esac
 }
 
 # dforge_resolve NAME [DIR] — a document name under the docs root, any other
 # relative name under the worktree, an absolute path unchanged. A historical
-# citation docs/superpowers/… resolves as docs/dforge/… does.
+# citation docs/superpowers/… or docs/forge/… resolves as docs/dforge/… does.
 dforge_resolve() {
   local name=${1#./}
   dforge_stores_init "${2:-}"
   case $name in
     /*|[A-Za-z]:/*|[A-Za-z]:\\*) printf '%s\n' "$1" ;;
-    docs/dforge|docs/superpowers) printf '%s\n' "$_DFORGE_DOCS_ROOT" ;;
+    docs/dforge|docs/forge|docs/superpowers) printf '%s\n' "$_DFORGE_DOCS_ROOT" ;;
     docs/dforge/*) printf '%s/%s\n' "$_DFORGE_DOCS_ROOT" "${name#docs/dforge/}" ;;
+    docs/forge/*) printf '%s/%s\n' "$_DFORGE_DOCS_ROOT" "${name#docs/forge/}" ;;
     docs/superpowers/*) printf '%s/%s\n' "$_DFORGE_DOCS_ROOT" "${name#docs/superpowers/}" ;;
     *) printf '%s/%s\n' "${_DFORGE_TOP:-${2:-$PWD}}" "$name" ;;
   esac
````

- [ ] **Step 4: Run the tests to verify they pass**

Run the two commands of Step 2.
Expected: `141 passed, 0 failed`; then `218 pass`, `0 fail`.

- [ ] **Step 5: Commit**

```bash
git commit -m "feat(dforge): read docs/forge citations"
```

### Task 12: Read docs/forge citations in darkmem

**Files:**
- Modify: `plugins/dforge/scripts/lib/darkmem-mirror.mjs` (`pathToUri`), `plugins/dforge/scripts/lib/darkmem-sync.mjs` (`documentUri`), `plugins/dforge/scripts/lib/darkmem-reconcile.mjs` (`LEGACY`, `nameSpellings`, the citation search before a deletion)
- Test: `plugins/dforge/tests/darkmem-sync/mirror.test.mjs`, `plugins/dforge/tests/darkmem-sync/reconcile.test.mjs`

**Interfaces:**
- Consumes: C1, C2.
- Produces: `docs/forge/<rest>` names the uri `dforge/<rest>`; `nameSpellings` answers the key, then the `docs/forge` and `docs/superpowers` spellings.

**Items:** 1
**Implementer:** dr-superpowers:impl-sonnet-high
**Evaluation:** files 2 - spec 0 - coupling 1 - risk 2 = 5

- [ ] **Step 1: Write the failing tests**

Run C1 with id `t12-tests`, writing `<scratch>/t12-tests.patch`, then `git apply --index <scratch>/t12-tests.patch`.

<!-- block: t12-tests -->
````diff
diff --git a/plugins/dforge/tests/darkmem-sync/mirror.test.mjs b/plugins/dforge/tests/darkmem-sync/mirror.test.mjs
index 73207fd..fea139f 100644
--- a/plugins/dforge/tests/darkmem-sync/mirror.test.mjs
+++ b/plugins/dforge/tests/darkmem-sync/mirror.test.mjs
@@ -128,10 +128,12 @@ test("paths name their uris; plans and drafts name their properties; a handoff n
     worktreeRoot: "/w/dforge",
   };
   assert.equal(pathToUri(named, "docs/superpowers/plans/p1.md"), "dforge/plans/p1.md");
+  assert.equal(pathToUri(named, "docs/forge/plans/p1.md"), "dforge/plans/p1.md");
   assert.equal(pathToUri(named, "./docs/dforge/plans/p1.md"), "dforge/plans/p1.md");
   assert.equal(pathToUri(named, "/home/u/.dforge/mirror/dforge/dforge/plans/p1.md"), "dforge/plans/p1.md");
   assert.equal(pathToUri(named, "/w/dforge/docs/dforge/specs/s.md"), "dforge/specs/s.md");
   assert.equal(pathToUri(named, "/w/dforge/docs/superpowers/specs/s.md"), null);
+  assert.equal(pathToUri(named, "/w/dforge/docs/forge/specs/s.md"), null);
   assert.equal(pathToUri(named, "/w/dforge/.dforge/sdd/p1/progress.md"), null);
   assert.equal(pathToUri(named, "/elsewhere/dforge/plans/p1.md"), null);
   assert.equal(pathToUri(named, "plans/p1.md"), null);
diff --git a/plugins/dforge/tests/darkmem-sync/reconcile.test.mjs b/plugins/dforge/tests/darkmem-sync/reconcile.test.mjs
index 11d954c..41c15a1 100644
--- a/plugins/dforge/tests/darkmem-sync/reconcile.test.mjs
+++ b/plugins/dforge/tests/darkmem-sync/reconcile.test.mjs
@@ -30,10 +30,12 @@ const storesOf = (home, repo) => {
   return { documents, progress };
 };
 
-test("a document name has one key under either prefix", () => {
-  assert.deepEqual(nameSpellings("docs/superpowers/plans/p.md"), ["docs/dforge/plans/p.md", "docs/superpowers/plans/p.md"]);
-  assert.deepEqual(nameSpellings("./docs/dforge/plans/p.md"), ["docs/dforge/plans/p.md", "docs/superpowers/plans/p.md"]);
-  assert.deepEqual(nameSpellings("docs/superpowers"), ["docs/dforge", "docs/superpowers"]);
+test("a document name has one key under every prefix", () => {
+  assert.deepEqual(nameSpellings("docs/superpowers/plans/p.md"), ["docs/dforge/plans/p.md", "docs/forge/plans/p.md", "docs/superpowers/plans/p.md"]);
+  assert.deepEqual(nameSpellings("docs/forge/plans/p.md"), ["docs/dforge/plans/p.md", "docs/forge/plans/p.md", "docs/superpowers/plans/p.md"]);
+  assert.deepEqual(nameSpellings("./docs/dforge/plans/p.md"), ["docs/dforge/plans/p.md", "docs/forge/plans/p.md", "docs/superpowers/plans/p.md"]);
+  assert.deepEqual(nameSpellings("docs/superpowers"), ["docs/dforge", "docs/forge", "docs/superpowers"]);
+  assert.deepEqual(nameSpellings("docs/forgex/a.md"), ["docs/forgex/a.md"]);
   assert.deepEqual(nameSpellings("docs/superpowersx/a.md"), ["docs/superpowersx/a.md"]);
   assert.deepEqual(nameSpellings("/abs/docs/superpowers/a.md"), ["/abs/docs/superpowers/a.md"]);
 });
@@ -405,7 +407,7 @@ test("a failing citation search is named in the move's details", { skip: process
   fs.writeFileSync(path.join(bin, "git"), `#!/bin/sh\nfor a in "$@"; do [ "$a" = "grep" ] && { echo "fatal: grep refused by the test" >&2; exit 128; }; done\nexec "${realGit}" "$@"\n`, { mode: 0o755 });
   const result = await reconcile(s.repo, { ...s.env, PATH: `${bin}${path.delimiter}${s.env.PATH ?? process.env.PATH}` });
   assert.equal(result.code, 0, result.stdout + result.stderr);
-  assert.match(result.stdout, /git grep failed: fatal: grep refused by the test; check for docs\/superpowers\/ and docs\/dforge\/ citations before you commit/);
+  assert.match(result.stdout, /git grep failed: fatal: grep refused by the test; check for docs\/superpowers\/, docs\/forge\/ and docs\/dforge\/ citations before you commit/);
 });
 
 for (const { arg, reason } of [
````

- [ ] **Step 2: Run the tests to verify they fail**

Run: `env -u CLAUDE_CONFIG_DIR timeout 300 node --test plugins/dforge/tests/darkmem-sync/mirror.test.mjs plugins/dforge/tests/darkmem-sync/reconcile.test.mjs`
Expected: FAIL — `ℹ tests 71`, `ℹ pass 68`, `ℹ fail 3`: `paths name their uris; ...`, `a document name has one key under every prefix`, `a failing citation search is named in the move's details`.

- [ ] **Step 3: Write the implementation**

Run C1 with id `t12-impl`, writing `<scratch>/t12-impl.patch`, then `git apply --index <scratch>/t12-impl.patch`.

<!-- block: t12-impl -->
````diff
diff --git a/plugins/dforge/scripts/lib/darkmem-mirror.mjs b/plugins/dforge/scripts/lib/darkmem-mirror.mjs
index 6e126a7..a71101e 100644
--- a/plugins/dforge/scripts/lib/darkmem-mirror.mjs
+++ b/plugins/dforge/scripts/lib/darkmem-mirror.mjs
@@ -532,12 +532,12 @@ export function ledgerEntries(text) {
 }
 
 // The darkmem uri a document's name or path stands for: a name under
-// docs/dforge/ or docs/superpowers/ (as a ledger or a **Spec:** line writes
+// docs/dforge/, docs/forge/ or docs/superpowers/ (as a ledger or a **Spec:** line writes
 // it), or an absolute path under the docs root or the worktree's docs
 // directory. Computed from the roots, never by searching for a segment.
 export function pathToUri(roots, file) {
   const text = String(file).replace(/\\/g, "/");
-  const name = /^(?:\.\/)?docs\/(?:dforge|superpowers)\/(.+)$/.exec(text);
+  const name = /^(?:\.\/)?docs\/(?:dforge|forge|superpowers)\/(.+)$/.exec(text);
   if (name) return name[1].split("/").some(segment => segment === ".." || segment === ".") ? null : `${DOC_PREFIX}/${name[1]}`;
   if (!path.isAbsolute(String(file))) return null;
   const bases = [roots.docsRoot];
diff --git a/plugins/dforge/scripts/lib/darkmem-reconcile.mjs b/plugins/dforge/scripts/lib/darkmem-reconcile.mjs
index 3fcd504..ad76aad 100644
--- a/plugins/dforge/scripts/lib/darkmem-reconcile.mjs
+++ b/plugins/dforge/scripts/lib/darkmem-reconcile.mjs
@@ -13,7 +13,8 @@ import { progressToDarkmem, progressToLocal } from "./darkmem-progress-move.mjs"
 import { pullDocuments } from "./darkmem-pull.mjs";
 
 const FAMILIES = ["documents", "progress"];
-const LEGACY = "docs/superpowers";
+// dr-forge wrote docs/forge, dr-superpowers docs/superpowers.
+const LEGACY = ["docs/forge", "docs/superpowers"];
 const DOCS = "docs/dforge";
 
 // Each move, under "<family>:<target store>". A move answers
@@ -41,13 +42,15 @@ function dirEntries(dir) {
   }
 }
 
-// One document name under either docs prefix (spec §7.1), as dforge_name_key
-// and dforge_name_spellings spell it in roots.sh. The pre-3.0 docs/superpowers
-// spelling stays readable because historical plans and ledgers cite it.
+// One document name under any docs prefix (spec §7.1), as dforge_name_key
+// and dforge_name_spellings spell it in roots.sh. The older docs/forge and
+// docs/superpowers spellings stay readable because historical plans and
+// ledgers cite them.
 export function nameSpellings(name) {
   const text = String(name).replace(/^\.\//, "");
-  const key = text === LEGACY || text.startsWith(`${LEGACY}/`) ? `${DOCS}${text.slice(LEGACY.length)}` : text;
-  return key === DOCS || key.startsWith(`${DOCS}/`) ? [key, `${LEGACY}${key.slice(DOCS.length)}`] : [key];
+  const old = LEGACY.find(prefix => text === prefix || text.startsWith(`${prefix}/`));
+  const key = old ? `${DOCS}${text.slice(old.length)}` : text;
+  return key === DOCS || key.startsWith(`${DOCS}/`) ? [key, ...LEGACY.map(prefix => `${prefix}${key.slice(DOCS.length)}`)] : [key];
 }
 
 export function pendingFamilies(cfg) {
@@ -356,11 +359,11 @@ async function documentsToDarkmem(context) {
   const removed = runGit(cfg.repoRoot, ["rm", "-r", "-q", "--", rel]);
   if (removed.status !== 0) return { moved: false, reason: `git rm failed: ${removed.stderr.trim()}`, details: [] };
   const details = [`the deletion of ${rel} is staged in ${cfg.repoRoot}; commit it`];
-  const cites = runGit(cfg.repoRoot, ["grep", "-I", "-l", "-F", "-e", "docs/superpowers/", "-e", "docs/dforge/", "--", ".", `:(exclude)${rel}`]);
+  const cites = runGit(cfg.repoRoot, ["grep", "-I", "-l", "-F", "-e", "docs/superpowers/", "-e", "docs/forge/", "-e", "docs/dforge/", "--", ".", `:(exclude)${rel}`]);
   const citing = cites.status === 0 ? cites.stdout.split("\n").filter(Boolean) : [];
-  if (cites.status > 1) details.push(`git grep failed: ${cites.stderr.trim()}; check for docs/superpowers/ and docs/dforge/ citations before you commit`);
+  if (cites.status > 1) details.push(`git grep failed: ${cites.stderr.trim()}; check for docs/superpowers/, docs/forge/ and docs/dforge/ citations before you commit`);
   if (citing.length) {
-    details.push("these tracked files cite docs/superpowers/ or docs/dforge/ names; rewrite them before you commit the deletion:");
+    details.push("these tracked files cite docs/superpowers/, docs/forge/ or docs/dforge/ names; rewrite them before you commit the deletion:");
     details.push(...citing.slice(0, 20).map(file => `  ${file}`));
     if (citing.length > 20) details.push(`and ${citing.length - 20} more`);
   }
diff --git a/plugins/dforge/scripts/lib/darkmem-sync.mjs b/plugins/dforge/scripts/lib/darkmem-sync.mjs
index 411d8af..6b1e39b 100644
--- a/plugins/dforge/scripts/lib/darkmem-sync.mjs
+++ b/plugins/dforge/scripts/lib/darkmem-sync.mjs
@@ -61,10 +61,11 @@ async function revision({ cfg, roots, state, client, report, args, out }) {
 }
 
 // A document name as ledgers and plans write it, docs/dforge/<rest> or the
-// pre-3.0 docs/superpowers/<rest> that historical plans cite, as its uri dforge/<rest>; null for a
+// older docs/forge/<rest> and docs/superpowers/<rest> that historical plans
+// cite, as its uri dforge/<rest>; null for a
 // path, a handoff note, an archived copy, or a name that climbs.
 function documentUri(name) {
-  const match = /^(?:\.\/)?docs\/(?:dforge|superpowers)\/(.+)$/.exec(name);
+  const match = /^(?:\.\/)?docs\/(?:dforge|forge|superpowers)\/(.+)$/.exec(name);
   if (!match || match[1].split("/").some(segment => segment === "" || segment === "." || segment === "..")) return null;
   const uri = `${DOC_PREFIX}/${match[1]}`;
   return uriFamily(uri) === "documents" && !isArchiveUri(uri) ? uri : null;
````

- [ ] **Step 4: Run the tests to verify they pass**

Run the command of Step 2.
Expected: `ℹ tests 71`, `ℹ pass 71`, `ℹ fail 0`.

- [ ] **Step 5: Commit**

```bash
git commit -m "feat(dforge): map docs/forge citations to darkmem"
```

### Task 13: Guard against the retired names

**Files:**
- Modify: `scripts/validate-repository.mjs` (`retiredForge` with `forgeAllowed` inside `plugins/dforge/`; a sweep for `dcc-darkraise` outside `docs/superpowers/` with `dccAllowed`)
- Test: `tests/repository-layout.test.mjs`

**Interfaces:**
- Consumes: C1, C2; the allowlisted files exist from Tasks 4 to 12.
- Produces: the validator errors `<file>:<line>: retired dr-forge name` and `<file>:<line>: retired dcc- plugin name`.

**Items:** 1
**Implementer:** dr-superpowers:impl-sonnet-medium
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 1 = 3

- [ ] **Step 1: Write the failing tests**

Run C1 with id `t13-tests`, writing `<scratch>/t13-tests.patch`, then `git apply --index <scratch>/t13-tests.patch`.

<!-- block: t13-tests -->
````diff
diff --git a/tests/repository-layout.test.mjs b/tests/repository-layout.test.mjs
index 7419e59..0aa5381 100644
--- a/tests/repository-layout.test.mjs
+++ b/tests/repository-layout.test.mjs
@@ -42,6 +42,13 @@ test('repository validator rejects broken distribution contracts', async t => {
     ['retired name in the Claude catalog entry', c => { c.plugins.find(p => p.name === 'dforge').keywords.push('superpowers'); }, /\.claude-plugin\/marketplace\.json: dforge entry: retired superpowers name/],
     ['retired name in the Codex catalog entry', c => { c.plugins.find(p => p.name === 'dforge').description = 'a superpowers fork'; }, /\.agents\/plugins\/marketplace\.json: dforge entry: retired superpowers name/, '.agents/plugins/marketplace.json'],
     ['retired name in any case', (c, dir) => { writeFileSync(resolve(dir, 'plugins/dforge/reference/stray.md'), 'a Superpowers worktree\n'); }, /plugins\/dforge\/reference\/stray\.md:1: retired superpowers name/],
+    ['retired dr-forge name', (c, dir) => { writeFileSync(resolve(dir, 'plugins/dforge/scripts/stray.sh'), 'mkdir -p .forge/sdd\n'); }, /plugins\/dforge\/scripts\/stray\.sh:1: retired dr-forge name/],
+    ['retired dr-forge variable', (c, dir) => { writeFileSync(resolve(dir, 'plugins/dforge/scripts/stray.sh'), 'echo "$DR_FORGE_BUDGET"\n'); }, /plugins\/dforge\/scripts\/stray\.sh:1: retired dr-forge name/],
+    ['retired dr-forge docs root', (c, dir) => { writeFileSync(resolve(dir, 'plugins/dforge/scripts/stray.sh'), 'cat docs/forge/plans/p.md\n'); }, /plugins\/dforge\/scripts\/stray\.sh:1: retired dr-forge name/],
+    ['retired dr-forge home', (c, dir) => { writeFileSync(resolve(dir, 'plugins/dforge/scripts/stray.sh'), 'ls ~/.dr-forge\n'); }, /plugins\/dforge\/scripts\/stray\.sh:1: retired dr-forge name/],
+    ['retired forge_ code name', (c, dir) => { writeFileSync(resolve(dir, 'plugins/dforge/scripts/stray.sh'), 'forge_dir .\n'); }, /plugins\/dforge\/scripts\/stray\.sh:1: retired dr-forge name/],
+    ['retired FORGE variable', (c, dir) => { writeFileSync(resolve(dir, 'plugins/dforge/scripts/stray.sh'), 'echo "$FORGE_HOME"\n'); }, /plugins\/dforge\/scripts\/stray\.sh:1: retired dr-forge name/],
+    ['retired dcc- plugin name', (c, dir) => { writeFileSync(resolve(dir, 'plugins/dr-status/stray.md'), 'install dcc-darkraise-ui\n'); }, /plugins\/dr-status\/stray\.md:1: retired dcc- plugin name/],
   ]) {
     await t.test(name, () => {
       const dir = mkdtempSync(resolve(tmpdir(), 'dr-catalog-'));
@@ -91,6 +98,25 @@ test('the retired superpowers name is allowed only in the allowlisted files', as
   } finally { rmSync(dir, { recursive: true, force: true }); }
 });
 
+test('the retired dr-forge names are allowed only in the allowlisted files', async () => {
+  const { validateRepository } = await import('../scripts/validate-repository.mjs');
+  const dir = mkdtempSync(resolve(tmpdir(), 'dr-catalog-'));
+  try {
+    for (const path of ['.claude-plugin', '.agents/plugins', ...json('.claude-plugin/marketplace.json').plugins.map(p => p.source)]) {
+      cpSync(resolve(root, path), resolve(dir, path), { recursive: true });
+    }
+    for (const path of ['plugins/dforge/tests/stray.test.sh', 'plugins/dforge/scripts/lib/roots.sh']) {
+      writeFileSync(resolve(dir, path), 'mkdir -p .forge\n');
+    }
+    // A dated plan name cites history, and other words merely contain the letters.
+    writeFileSync(resolve(dir, 'plugins/dforge/reference/dated.md'), 'see docs/dforge/plans/2026-10-12-dr-forge-settings.md; git forges forget\n');
+    const retired = () => validateRepository(dir).filter(error => error.includes('retired dr-forge name'));
+    assert.deepEqual(retired(), []);
+    writeFileSync(resolve(dir, 'plugins/dforge/reference/stray.md'), 'run dr-forge:brainstorming\n');
+    assert.deepEqual(retired(), ['plugins/dforge/reference/stray.md:1: retired dr-forge name']);
+  } finally { rmSync(dir, { recursive: true, force: true }); }
+});
+
 test('reference check skips template placeholders and resolves agents', async () => {
   const { validateRepository } = await import('../scripts/validate-repository.mjs');
   const dir = mkdtempSync(resolve(tmpdir(), 'dr-catalog-'));
````

- [ ] **Step 2: Run the tests to verify they fail**

Run: `env -u CLAUDE_CONFIG_DIR timeout 300 node --test tests/repository-layout.test.mjs`
Expected: FAIL — `ℹ tests 31`, `ℹ pass 22`, `ℹ fail 9`: the subtests `retired dr-forge name`, `retired dr-forge variable`, `retired dr-forge docs root`, `retired dr-forge home`, `retired forge_ code name`, `retired FORGE variable`, `retired dcc- plugin name`, their parent `repository validator rejects broken distribution contracts`, and `the retired dr-forge names are allowed only in the allowlisted files`.

- [ ] **Step 3: Write the implementation**

Run C1 with id `t13-impl`, writing `<scratch>/t13-impl.patch`, then `git apply --index <scratch>/t13-impl.patch`.

<!-- block: t13-impl -->
````diff
diff --git a/scripts/validate-repository.mjs b/scripts/validate-repository.mjs
index 41b7c3d..fdc7f7e 100644
--- a/scripts/validate-repository.mjs
+++ b/scripts/validate-repository.mjs
@@ -115,6 +115,23 @@ export function validateRepository(root) {
   const superpowersExempt = rel => superpowersAllowed.has(rel) ||
     /^plugins\/dforge\/(?:LICENSES|tests)\//.test(rel) ||
     /^plugins\/dforge\/scripts\/lib\/(?:darkmem-(?:sync|mirror|reconcile)|dforge-home-migrate)\.mjs$/.test(rel);
+  // dforge 4.0 spells the dr-forge names only where it migrates or translates
+  // them. A dated plan or spec name (2026-10-12-dr-forge-settings) cites
+  // history and is not a retired name.
+  const retiredForge = /dr-forge|DR_FORGE|(?<!D)FORGE|(?<![A-Za-z0-9_d])forge(?![a-z])/;
+  const forgeAllowed = new Set([
+    'plugins/dforge/README.md',
+    'plugins/dforge/hooks/cockpit/lib.ts',
+    'plugins/dforge/scripts/dforge-migrate',
+    'plugins/dforge/scripts/lib/dforge-dir.sh',
+    'plugins/dforge/scripts/lib/roots.sh',
+    'plugins/dforge/scripts/lib/dforge-home-migrate.mjs',
+    'plugins/dforge/scripts/lib/darkmem-mirror.mjs',
+    'plugins/dforge/scripts/lib/darkmem-sync.mjs',
+    'plugins/dforge/scripts/lib/darkmem-reconcile.mjs',
+    'plugins/dforge/skills/migrate/SKILL.md',
+  ]);
+  const forgeExempt = rel => forgeAllowed.has(rel) || /^plugins\/dforge\/(?:LICENSES|tests)\//.test(rel);
   for (const name of names) {
     const pluginRoot = resolve(root, 'plugins', name);
     if (!existsSync(pluginRoot)) continue;
@@ -124,8 +141,10 @@ export function validateRepository(root) {
         if (item.isDirectory()) { visit(path); continue; }
         const rel = relative(root, path).replaceAll('\\', '/');
         const checksSuperpowers = name === 'dforge' && !superpowersExempt(rel);
+        const checksForge = name === 'dforge' && !forgeExempt(rel);
         readFileSync(path, 'utf8').split('\n').forEach((line, index) => {
           if (checksSuperpowers && /superpowers/i.test(line)) errors.push(`${rel}:${index + 1}: retired superpowers name`);
+          if (checksForge && retiredForge.test(line.replace(/\d{4}-\d{2}-\d{2}-dr-forge/g, ''))) errors.push(`${rel}:${index + 1}: retired dr-forge name`);
           if (legacyAllowed.has(rel)) return;
           if (legacyPattern.test(line)) errors.push(`${rel}:${index + 1}: legacy plugin-name reference`);
           for (const match of line.matchAll(/dforge:([a-z0-9-]+)/g)) {
@@ -142,6 +161,25 @@ export function validateRepository(root) {
     };
     visit(pluginRoot);
   }
+  // The UI plugins dropped their dcc- prefix in 0.3.0; only the migration
+  // notes and the historical plans and specs still spell it.
+  const dccAllowed = new Set(['docs/migration.md', 'scripts/validate-repository.mjs', 'tests/repository-layout.test.mjs']);
+  const unswept = new Set(['.git', '.claude', 'node_modules', '.worktrees', '.dforge', '.forge', '.superpowers']);
+  const sweep = dir => {
+    for (const item of readdirSync(dir, { withFileTypes: true })) {
+      const path = resolve(dir, item.name);
+      const rel = relative(root, path).replaceAll('\\', '/');
+      if (item.isDirectory()) {
+        if (!unswept.has(item.name) && rel !== 'docs/superpowers') sweep(path);
+        continue;
+      }
+      if (!item.isFile() || dccAllowed.has(rel)) continue;
+      readFileSync(path, 'utf8').split('\n').forEach((line, index) => {
+        if (line.includes('dcc-darkraise')) errors.push(`${rel}:${index + 1}: retired dcc- plugin name`);
+      });
+    }
+  };
+  sweep(root);
   return errors;
 }
 
````

- [ ] **Step 4: Run the tests to verify they pass**

Run: `env -u CLAUDE_CONFIG_DIR timeout 300 node --test tests/repository-layout.test.mjs`
Expected: `ℹ tests 31`, `ℹ pass 31`, `ℹ fail 0`.

Run: `node scripts/validate-repository.mjs`
Expected: exit 0, no error lines (the real tree passes the new guard).

- [ ] **Step 5: Commit**

```bash
git commit -m "feat(validate): reject retired dr-forge and dcc- names"
```

### Task 14: Document the 4.0 migration and release

**Files:**
- Modify: `plugins/dforge/README.md` ("Migrating to 4.0"; the earlier migration sections keep the dr-forge names of their day), `docs/migration.md` (the dforge 4.0 and UI plugin paragraphs; links to `plugins/dforge/`), `README.md` (the link to "Migrating to 4.0")
- Modify: `plugins/dforge/.claude-plugin/plugin.json`, `plugins/dforge/.codex-plugin/plugin.json` (`4.0.0`), `.claude-plugin/marketplace.json` (`0.7.0`)
- Test: `plugins/dforge/tests/review-route.test.sh` (the manifests are `4.0.0`)

**Interfaces:**
- Consumes: C1, C2, C4, C5.
- Produces: nothing later tasks consume.

**Items:** 1, 2, 3
**Implementer:** dr-superpowers:impl-sonnet-medium
**Evaluation:** files 2 - spec 0 - coupling 1 - risk 1 = 4

- [ ] **Step 1: Write the docs**

Run C1 with id `t14-docs`, writing `<scratch>/t14-docs.patch`, then `git apply --index <scratch>/t14-docs.patch`.

<!-- block: t14-docs -->
````diff
diff --git a/README.md b/README.md
index eca8595..2716b21 100644
--- a/README.md
+++ b/README.md
@@ -146,7 +146,7 @@ See the [cockpit section](plugins/dforge/README.md#cockpit) and
 Releases are versioned per plugin. Renamed plugins, retired plugins and
 re-registering the marketplace are covered in [docs/migration.md](docs/migration.md);
 dforge's own steps are in its README under
-[Migrating to 3.0](plugins/dforge/README.md#migrating-to-30).
+[Migrating to 4.0](plugins/dforge/README.md#migrating-to-40).
 
 ## Contributing
 
diff --git a/docs/migration.md b/docs/migration.md
index 3846f74..8bc5894 100644
--- a/docs/migration.md
+++ b/docs/migration.md
@@ -1,8 +1,8 @@
 # Migration
 
 Notes for moving to the current plugin names and for re-registering the
-marketplace. dr-forge's own upgrade steps live in its README:
-[Migrating to 3.0](../plugins/dr-forge/README.md#migrating-to-30).
+marketplace. dforge's own upgrade steps live in its README:
+[Migrating to 4.0](../plugins/dforge/README.md#migrating-to-40).
 
 ## Re-registering the marketplace
 
@@ -17,14 +17,23 @@ marketplace keeps its installations.
 ## Replaced plugins
 
 Disable the old Claude `dcc-statusline` and `dcc-superpower-companions` plugins
-before enabling `dr-status` and `dr-forge`, so their hooks do not run twice.
+before enabling `dr-status` and `dforge`, so their hooks do not run twice.
 
 `dr-forge` 2.0.0 replaces `dr-superpowers` and `dr-cockpit`: install it, start
 one session so it imports their settings, then uninstall both (see
-[Migrating from dr-superpowers and dr-cockpit](../plugins/dr-forge/README.md#migrating-from-dr-superpowers-and-dr-cockpit)).
+[Migrating from dr-superpowers and dr-cockpit](../plugins/dforge/README.md#migrating-from-dr-superpowers-and-dr-cockpit)).
 `dr-forge` 3.0.0 then renames the pre-3.0 repository directories and the home
 with `forge-migrate` (see
-[Migrating to 3.0](../plugins/dr-forge/README.md#migrating-to-30)).
+[Migrating to 3.0](../plugins/dforge/README.md#migrating-to-30)).
+
+`dforge` 4.0.0 replaces `dr-forge`: install `dforge@darkraise`, uninstall
+`dr-forge@darkraise`, and run `/dforge:migrate` in each repository. It takes a
+dr-superpowers repository straight to 4.0 as well (see
+[Migrating to 4.0](../plugins/dforge/README.md#migrating-to-40)).
+
+`darkraise-ui` and `darkraise-win32ui` 0.3.0 replace `dcc-darkraise-ui` and
+`dcc-darkraise-win32ui`, with the same skills: install the new names, then
+uninstall the old ones.
 
 ## Status line
 
diff --git a/plugins/dforge/README.md b/plugins/dforge/README.md
index 3bdeed9..2af3b8b 100644
--- a/plugins/dforge/README.md
+++ b/plugins/dforge/README.md
@@ -823,6 +823,43 @@ The last loads the working copy into a session and reloads it on save. The
 engine lays its type declarations under `.claude-plugin/types/` when it loads
 the folder; they are not committed.
 
+## Migrating to 4.0
+
+dforge 4.0 is dr-forge renamed, internals included, and it reads none of the
+3.x names:
+
+| 3.x | 4.0 |
+|---|---|
+| plugin `dr-forge@darkraise`, skills and agents `dr-forge:<name>` | `dforge@darkraise`, `dforge:<name>` |
+| `.forge/`, `docs/forge/`, `<git dir>/dr-forge/` | `.dforge/`, `docs/dforge/`, `<git dir>/dforge/` |
+| `~/.dr-forge/` | `~/.dforge/` |
+| `DR_FORGE_*` environment variables | `DFORGE_*` |
+| `scripts/forge-config`, `scripts/forge-path`, `scripts/forge-migrate` | `scripts/dforge-config`, `scripts/dforge-path`, `scripts/dforge-migrate` |
+| darkmem documents under `forge/` | `dforge/` |
+
+1. Install dforge, then uninstall dr-forge, so their hooks do not run twice:
+
+       /plugin install dforge@darkraise
+       /plugin uninstall dr-forge@darkraise
+
+   On Codex: `codex plugin add dforge@darkraise`, then
+   `codex plugin remove dr-forge@darkraise`.
+2. In each repository, run `/dforge:migrate` (on Codex, ask for the
+   `dforge:migrate` skill). It shows what `scripts/dforge-migrate --dry-run`
+   would move, asks once, then moves every checkout and the home, rewrites the
+   old plugin prefixes (`dr-forge`, `dr-superpowers`) in plans still in
+   progress, and offers to commit what moved. It takes a dr-superpowers
+   repository straight to 4.0 as well. Session start and `repo-audit` name
+   any older path still present.
+3. Rename any `DR_FORGE_*` variable a shell profile sets to `DFORGE_*`.
+
+darkmem's documents move from `forge/` to `dforge/` at the first sync after
+the mirror moved. A name darkmem already holds under `dforge/` is refused,
+never overwritten.
+
+The sections below record the earlier migrations under the names of their
+day; their steps now run through `/dforge:migrate`.
+
 ## Migrating from 0.x
 
 1.0.0 is standalone and breaking. On a machine with the old setup:
@@ -842,33 +879,33 @@ the folder; they are not committed.
 
 ## Migrating from dr-superpowers and dr-cockpit
 
-dforge 2.0.0 replaces both plugins. Install dforge and start one session
+dr-forge 2.0.0 replaces both plugins. Install dr-forge and start one session
 before you uninstall the old plugins, because the first session reads their
 saved settings:
 
-    /plugin install dforge@darkraise
+    /plugin install dr-forge@darkraise
     /plugin uninstall dr-superpowers@darkraise
     /plugin uninstall dr-cockpit@darkraise
 
 The first session imports the cockpit's options into
-`~/.dforge/config.json`, and the cockpit's Discord webhook and mention into
-dforge's own plugin store, once; the old files stay. Since 3.0.0 the
+`~/.dr-forge/config.json`, and the cockpit's Discord webhook and mention into
+dr-forge's own plugin store, once; the old files stay. Since 3.0.0 the
 dr-superpowers names are no longer read: see Migrating to 3.0.
 
 ## Migrating to 3.0
 
-dforge 3.0.0 reads and writes only its own names: `.dforge/`, `docs/dforge/`,
-the git directory's `dforge/`, `~/.dforge/`, the `DFORGE_*` variables
-and the `dforge:` prefix. The pre-2.0 `.superpowers/`, `docs/superpowers/`,
+dr-forge 3.0.0 reads and writes only its own names: `.forge/`, `docs/forge/`,
+the git directory's `dr-forge/`, `~/.dr-forge/`, the `DR_FORGE_*` variables
+and the `dr-forge:` prefix. The pre-2.0 `.superpowers/`, `docs/superpowers/`,
 `dr-superpowers/` and `DR_SUPERPOWERS_*` names and the `dr-superpowers`
 prefix are no longer read. Session start and `repo-audit` print one line naming
 any pre-3.0 directory a repository still has; run, once per repository:
 
-    bash <plugin-root>/scripts/dforge-migrate [DIR]
+    bash <plugin-root>/scripts/forge-migrate [DIR]
 
 In the primary checkout and every linked worktree it moves `.superpowers/` to
-`.dforge/`, `docs/superpowers/` to `docs/dforge/` (with `git mv` when the
-directory is tracked) and `<git dir>/dr-superpowers/` to `<git dir>/dforge/`,
+`.forge/`, `docs/superpowers/` to `docs/forge/` (with `git mv` when the
+directory is tracked) and `<git dir>/dr-superpowers/` to `<git dir>/dr-forge/`,
 then rewrites the lines of `.gitignore`, `.gitattributes` and
 `.git/info/exclude` that name the old directories. It prints each move and what
 you must commit. A checkout that has both the old and the new directory, or a
@@ -878,20 +915,20 @@ exits 0 when done or when there was nothing to do, and 1 when something was
 refused.
 
 No other file is edited: plans, specs and ledgers that cite
-`docs/superpowers/<rest>` keep that spelling, and dforge still reads it as
-`docs/dforge/<rest>`. A plan whose `**Implementer:**` lines name agents under an
-older plugin prefix fails `scripts/plan-lint` until they name `dforge:`.
-Rename any `DR_SUPERPOWERS_*` variable you set to its `DFORGE_*` name.
-`DFORGE_DOCUMENT_STORE` and `DFORGE_PROGRESS_SOURCE`, which 2.x read, are
+`docs/superpowers/<rest>` keep that spelling, and dr-forge still reads it as
+`docs/forge/<rest>`. A plan whose `**Implementer:**` lines name agents under an
+older plugin prefix fails `scripts/plan-lint` until they name `dr-forge:`.
+Rename any `DR_SUPERPOWERS_*` variable you set to its `DR_FORGE_*` name.
+`DR_FORGE_DOCUMENT_STORE` and `DR_FORGE_PROGRESS_SOURCE`, which 2.x read, are
 no longer read at all: set `documentStore` and `progressSource` instead.
 
-`dforge-migrate` also moves the home: the darkmem mapping in
-`~/.dr-superpowers/config.json` into `~/.dforge/config.json` when that file
+`forge-migrate` also moves the home: the darkmem mapping in
+`~/.dr-superpowers/config.json` into `~/.dr-forge/config.json` when that file
 has none, and each `~/.dr-superpowers/mirror/<project>/` that
-`~/.dforge/mirror/` lacks. darkmem itself is off in 3.0 until you set
-`darkmemEnabled`. A mirror's `superpowers/` folder becomes `dforge/` at the next
+`~/.dr-forge/mirror/` lacks. darkmem itself is off in 3.0 until you set
+`darkmemEnabled`. A mirror's `superpowers/` folder becomes `forge/` at the next
 `darkmem-sync` run, and the first online run moves darkmem's `superpowers/`
-documents to `dforge/`; upgrade every machine that shares a darkmem project,
+documents to `forge/`; upgrade every machine that shares a darkmem project,
 since a 2.x client no longer sees the moved documents.
 
 ## What a plan looks like
````

Run: `node scripts/validate-repository.mjs`
Expected: exit 0, no error lines.

```bash
git commit -m "docs(dforge): add the Migrating to 4.0 notes"
```

- [ ] **Step 2: Write the failing version test**

Run C1 with id `t14-tests`, writing `<scratch>/t14-tests.patch`, then `git apply --index <scratch>/t14-tests.patch`.

<!-- block: t14-tests -->
````diff
diff --git a/plugins/dforge/tests/review-route.test.sh b/plugins/dforge/tests/review-route.test.sh
index ed5221b..78a4c5c 100755
--- a/plugins/dforge/tests/review-route.test.sh
+++ b/plugins/dforge/tests/review-route.test.sh
@@ -594,8 +594,8 @@ present "README counts twenty agents" "$RD" '**Twenty agents in three classes.**
 absent "README drops the three-seat risk-3 mean" "$RD" 'spread above 6 points'
 present "README names review-route" "$RD" '`scripts/review-route` prints the review seat'
 present "README names the plan-review schema" "$RD" '`codex-plan-review-schema.json`'
-present "the Claude manifest is 3.1.0" "$P/.claude-plugin/plugin.json" '"version": "3.1.0"'
-present "the Codex manifest is 3.1.0" "$P/.codex-plugin/plugin.json" '"version": "3.1.0"'
+present "the Claude manifest is 4.0.0" "$P/.claude-plugin/plugin.json" '"version": "4.0.0"'
+present "the Codex manifest is 4.0.0" "$P/.codex-plugin/plugin.json" '"version": "4.0.0"'
 present "the program design names sub-project 10" "$P/../../docs/superpowers/specs/2026-09-11-dr-superpowers-fork-design.md" '**Amendment 2026-09-17 (sub-project 10 spec).**'
 present "approach ranking runs on Opus" "$P/skills/selecting-approaches/SKILL.md" 'Dispatch one `dforge:judge-opus` to run the ring'
 present "the budget reference derives the budget" "$P/reference/session-budget.md" 'min(`autoCompactWindow`, model window) × 93% − 140,000'
````

Run: `env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/review-route.test.sh`
Expected: FAIL — `244 passed, 2 failed`: `the Claude manifest is 4.0.0`, `the Codex manifest is 4.0.0`.

- [ ] **Step 3: Bump the versions**

Run C1 with id `t14-release`, writing `<scratch>/t14-release.patch`, then `git apply --index <scratch>/t14-release.patch`.

<!-- block: t14-release -->
````diff
diff --git a/.claude-plugin/marketplace.json b/.claude-plugin/marketplace.json
index e6fb06b..80abb11 100644
--- a/.claude-plugin/marketplace.json
+++ b/.claude-plugin/marketplace.json
@@ -1,7 +1,7 @@
 {
   "$schema": "https://json.schemastore.org/claude-code-marketplace.json",
   "name": "darkraise",
-  "version": "0.6.0",
+  "version": "0.7.0",
   "description": "Darkraise plugins for Claude Code and Codex.",
   "owner": {
     "name": "Darkraise",
diff --git a/plugins/dforge/.claude-plugin/plugin.json b/plugins/dforge/.claude-plugin/plugin.json
index 55727ef..5e3d84b 100644
--- a/plugins/dforge/.claude-plugin/plugin.json
+++ b/plugins/dforge/.claude-plugin/plugin.json
@@ -2,7 +2,7 @@
   "$schema": "https://json.schemastore.org/claude-code-plugin-manifest.json",
   "name": "dforge",
   "description": "Brainstorm, plan and execute with scored tasks, tiered implementers, criteria-based review and an external Codex executor; on Claude Code a cockpit pane shows the session, the run, context against its handoff budget, usage limits and the repo, with Discord notifications and an attribution guard.",
-  "version": "3.1.0",
+  "version": "4.0.0",
   "author": {
     "name": "Darkraise"
   },
diff --git a/plugins/dforge/.codex-plugin/plugin.json b/plugins/dforge/.codex-plugin/plugin.json
index 4bcb503..a62d3fe 100644
--- a/plugins/dforge/.codex-plugin/plugin.json
+++ b/plugins/dforge/.codex-plugin/plugin.json
@@ -1,6 +1,6 @@
 {
   "name": "dforge",
-  "version": "3.1.0",
+  "version": "4.0.0",
   "description": "Brainstorm, plan and execute with scored tasks, tiered implementers, criteria-based review and an external Codex executor; on Claude Code a cockpit pane shows the session, the run, context against its handoff budget, usage limits and the repo, with Discord notifications and an attribution guard.",
   "author": {
     "name": "Darkraise"
````

Run: `env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/review-route.test.sh`
Expected: `246 passed, 0 failed`.

```bash
git commit -m "chore(dforge): release 4.0.0"
```

- [ ] **Step 4: Run the whole validation**

Run: `node scripts/validate-repository.mjs`
Expected: exit 0, no error lines.

Run: `env -u CLAUDE_CONFIG_DIR timeout --kill-after=10s 690s node scripts/test-all.mjs`
Expected: exit 0, and no line `Finished ... (exit 1)`.

Run: `timeout 90 /root/.local/bin/claude plugin validate .`, then `timeout 90 /root/.local/bin/claude plugin validate plugins/<name>` for each of `dforge`, `dr-status`, `darkraise-ui`, `darkraise-win32ui`
Expected: each passes.

Run: `env -u CLAUDE_CONFIG_DIR timeout 300 /root/.local/bin/claude plugin test plugins/dforge`
Expected: `218 pass`, `0 fail`.

- [ ] **Step 5: Run the end-to-end migration (acceptance 4 and 5)**

Run C1 with id `e2e`, writing `<scratch>/e2e.sh`.

<!-- block: e2e -->
````bash
#!/usr/bin/env bash
# Acceptance 4 and 5: a dr-forge repository with history, a linked worktree,
# an active plan naming older agent prefixes and a home holding config.json,
# stores.json and a mirror, previewed and then migrated by this worktree's
# dforge-migrate. Run from the worktree root.
set -uo pipefail
P="$PWD/plugins/dforge"
SRC="$PWD/docs/superpowers"
E=$(mktemp -d)
trap 'rm -rf "$E"' EXIT
export HOME="$E/home" GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com
R="$E/repo"
git init -q -b main "$R"
mkdir -p "$R/docs/forge/plans" "$R/docs/forge/specs" "$R/.forge/sdd/active" "$R/.forge/handoff"
cp "$SRC/plans/2026-10-17-dr-forge-process-roles.md" "$R/docs/forge/plans/active.md"
cp "$SRC/specs/2026-10-17-dr-forge-process-roles-design.md" "$R/docs/forge/specs/"
sed -i 's#docs/superpowers/specs/#docs/forge/specs/#g' "$R/docs/forge/plans/active.md"
printf '# Completed plans\n' > "$R/docs/forge/plans/completed.md"
printf '.forge/\n' > "$R/.gitignore"
git -C "$R" add -A
git -C "$R" commit -q -m "dr-forge layout"
echo ledger > "$R/.forge/sdd/active/progress.md"
printf 'Resume with dr-forge:resume-execution\n' > "$R/.forge/handoff/latest.md"
git -C "$R" worktree add -q -b feature "$E/wt"
mkdir -p "$(git -C "$E/wt" rev-parse --absolute-git-dir)/dr-forge"
mkdir -p "$HOME/.dr-forge/mirror/p/forge"
printf '{"handoffTokens":325000}\n' > "$HOME/.dr-forge/config.json"
printf '{"%s":{"project":"p","mirror":"%s","documents":"local","progress":"local"}}\n' "$R" "$HOME/.dr-forge/mirror/p" > "$HOME/.dr-forge/stores.json"
echo a > "$HOME/.dr-forge/mirror/p/forge/a.md"

session_line() {
  printf '{"hook_event_name":"SessionStart","session_id":"e2e","cwd":"%s","source":"startup"}' "$R" \
    | bash "$P/scripts/session-start.sh" 2>/dev/null | jq -r '.hookSpecificOutput.additionalContext // ""' | grep 'still uses an older layout'
}
echo "== session start before (acceptance 6)"
session_line
echo "== lint before: older agent prefixes"
(cd "$R" && bash "$P/scripts/plan-lint" docs/forge/plans/active.md 2>&1 | grep -c "not a dforge agent")
snapshot() { # every path and file checksum under $E, the git index and objects aside
  (cd "$E" && find . -not -path '*/.git/index' -not -path '*/.git/objects/*' -print | sort
   find . -type f -not -path '*/.git/index' -not -path '*/.git/objects/*' -exec cksum {} + | sort)
}
before=$(snapshot)
echo "== dry run"
(cd "$R" && bash "$P/scripts/dforge-migrate" --dry-run); echo "dry exit $?"
[ "$before" = "$(snapshot)" ] && echo "dry run changed no file" || echo "DRY RUN CHANGED FILES"
echo "== real run"
(cd "$R" && bash "$P/scripts/dforge-migrate"); echo "exit $?"
echo "== staged"
git -C "$R" status --porcelain -- docs | cut -c1-2 | sort | uniq -c
echo "== lint after"
(cd "$R" && bash "$P/scripts/plan-lint" docs/dforge/plans/active.md 2>&1 | tail -1)
echo "== leftovers"
find "$E" -path "$R/.git/objects" -prune -o \( -name '*forge*' ! -name '*dforge*' ! -name '*dr-forge-process-roles*' -o -name '*superpowers*' \) -print
echo "skill or agent names under an older prefix left in the plan: $(grep -cE '(^|[^A-Za-z0-9_-])dr-(superpowers|forge):[a-z]' "$R/docs/dforge/plans/active.md")"
cat "$R/.dforge/handoff/latest.md" "$R/.gitignore"
cat "$HOME/.dforge/stores.json"
echo "== session start after: lines naming an older layout"
session_line | wc -l
echo "== second run"
(cd "$R" && bash "$P/scripts/dforge-migrate"); echo "exit $?"
````

Run: `env -u CLAUDE_CONFIG_DIR timeout 300 bash <scratch>/e2e.sh` from the worktree root.
Expected: exactly this output, where `$E` stands for the temporary directory the script made (`/tmp/tmp.<random>`):

````
== session start before (acceptance 6)
dforge: this repository still uses an older layout ($E/home/.dr-forge, $E/repo/.forge, $E/repo/docs/forge); run the dforge:migrate skill (/dforge:migrate)
== lint before: older agent prefixes
14
== dry run
would move $E/repo/.forge -> $E/repo/.dforge
would move $E/repo/docs/forge -> $E/repo/docs/dforge
would rewrite the plugin prefixes in $E/repo/docs/forge/plans/active.md
would rewrite the plugin prefixes in $E/repo/.forge/handoff/latest.md
would move $E/wt/docs/forge -> $E/wt/docs/dforge
would rewrite the plugin prefixes in $E/wt/docs/forge/plans/active.md
would move $E/repo/.git/worktrees/wt/dr-forge -> $E/repo/.git/worktrees/wt/dforge
would rewrite the older names in $E/repo/.gitignore
would rewrite the older names in $E/wt/.gitignore
dforge-home-migrate: would merge $E/home/.dr-forge/config.json into $E/home/.dforge/config.json (handoffTokens)
dforge-home-migrate: would move $E/home/.dr-forge/mirror to $E/home/.dforge/mirror
dforge-home-migrate: would move $E/home/.dr-forge/stores.json to $E/home/.dforge/stores.json
dforge-home-migrate: would point 1 $E/home/.dforge/stores.json record(s) at the moved mirrors
dforge-home-migrate: would rename $E/home/.dr-forge/mirror/p's forge/ to dforge/; darkmem's documents follow at its next sync
dry exit 0
dry run changed no file
== real run
moved $E/repo/.forge -> $E/repo/.dforge
moved $E/repo/docs/forge -> $E/repo/docs/dforge
rewrote the plugin prefixes in $E/repo/docs/dforge/plans/active.md
rewrote the plugin prefixes in $E/repo/.dforge/handoff/latest.md
moved $E/wt/docs/forge -> $E/wt/docs/dforge
rewrote the plugin prefixes in $E/wt/docs/dforge/plans/active.md
moved $E/repo/.git/worktrees/wt/dr-forge -> $E/repo/.git/worktrees/wt/dforge
rewrote the older names in $E/repo/.gitignore
rewrote the older names in $E/wt/.gitignore
dforge-home-migrate: merged $E/home/.dr-forge/config.json into $E/home/.dforge/config.json (handoffTokens)
dforge-home-migrate: moved $E/home/.dr-forge/mirror to $E/home/.dforge/mirror
dforge-home-migrate: moved $E/home/.dr-forge/stores.json to $E/home/.dforge/stores.json
dforge-home-migrate: pointed 1 $E/home/.dforge/stores.json record(s) at the moved mirrors
dforge-home-migrate: renamed $E/home/.dforge/mirror/p's forge/ to dforge/; darkmem's documents follow at its next sync
commit: $E/repo: the staged rename docs/forge/ -> docs/dforge/
commit: $E/repo: docs/dforge/plans/active.md
commit: $E/wt: the staged rename docs/forge/ -> docs/dforge/
commit: $E/wt: docs/dforge/plans/active.md
commit: $E/repo: .gitignore
commit: $E/wt: .gitignore
exit 0
== staged
      2 R 
      1 RM
== lint after
plan-lint: 0 errors, 0 warnings
== leftovers
skill or agent names under an older prefix left in the plan: 0
Resume with dforge:resume-execution
.dforge/
{
  "$E/repo": {
    "project": "p",
    "mirror": "$E/home/.dforge/mirror/p",
    "documents": "local",
    "progress": "local"
  }
}
== session start after: lines naming an older layout
0
== second run
dforge-migrate: nothing to migrate in $E/repo
exit 0
````
