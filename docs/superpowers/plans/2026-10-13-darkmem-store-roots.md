# darkmem Store Options, Plan 1 (Roots and Sync) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: the skill the **Execution:** line names — dr-superpowers:subagent-driven-development for `subagent`, dr-superpowers:executing-plans for `inline`. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a mapped repository keep its documents and its progress each locally or in darkmem: two settings with a per-repository override, roots and names that follow each family's applied store, per-family sync, and ledger entries that carry board properties.

**Architecture:** `darkmem-config.mjs` gains `resolveStores` and a `--mode` CLI; `~/.dr-forge/stores.json` records each family's applied store. The mirror and the sync commands gate every step by family. A new `scripts/lib/roots.sh` reads `--mode` once per script and exposes the root and name helpers every script, hook and skill uses instead of spelling `.forge/` or `docs/forge/`.

**Tech Stack:** Node ES modules with `node:test` (darkmem-sync), bash + git (scripts and shell suites), Markdown skills.

**Spec:** docs/superpowers/specs/2026-10-13-darkmem-store-options-design.md

**Execution:** inline — `claude --model sonnet --effort high` — 4 of 17 tasks are heavy (Tasks 2, 3, 4, 10) and are delegated; the rest total 4 or less

**Plan review:** 2026-10-13 — dr-superpowers:judge-opus — executability 17 / coherence 18 / coverage 17 / assumptions 17 (round 2)

**Parallelism:** sequential — the spec's Execution strategy: the options feed the roots, the roots feed the rewiring and the sync

## Global Constraints

- All paths below are relative to `plugins/dr-forge/` unless they start with `docs/` or name the repository-root scripts `scripts/test-all.mjs` and `scripts/validate-repository.mjs`.
- English only. Commit messages: `<type>(dr-forge): <subject>`, subject at most 50 characters, imperative, no period. No AI attribution of any kind; commit as `Darkraise <quangtc94@gmail.com>`.
- Inside `plugins/dr-forge/`, write skill references as `dr-forge:<name>`, never `dr-superpowers:` (`scripts/validate-repository.mjs` rejects the legacy names).
- Comments only where the why is non-obvious, matching the surrounding files.
- Bash executables use `set -uo pipefail`; libraries are sourced and define functions only.
- Every new shell check sets `HOME` to a directory under the suite's own `mktemp -d` (inline as `HOME=… command`, or the suite's exported `HOME`) and never reads the real home directory. New `node:test` cases build their HOME with `makeHome`.
- Bound every run, from the repository root: one shell suite `timeout 600 bash plugins/dr-forge/tests/<name>.test.sh`; one sync file `timeout 300 node --test plugins/dr-forge/tests/darkmem-sync/<file>.test.mjs`; the whole sync suite `timeout 900 bash plugins/dr-forge/tests/darkmem-sync.test.sh`; the mod suite `timeout 600 claude plugin test plugins/dr-forge`.
- darkmem uris do not change: documents stay under `superpowers/`, a plan's handoff note at `superpowers/handoff/<slug>.md`, the mirror's subtrees stay `superpowers/` and `work/`. No darkmem server change.
- Preserve every `DCC_*` variable and the pre-2.0 fallbacks (`~/.dr-superpowers/`, `docs/superpowers/`, `.superpowers/`, `DR_SUPERPOWERS_SESSION_ID`).
- Workspaces stay local in both stores: briefs, reports, review packages, `amendments.md`, `auto-run.json`, `finish.json` and `budget-log.tsv` keep their current paths.
- No version bump in this plan: plan 2 delivers the move the setting descriptions promise and releases.

## Contracts

**C1. Settings.** `config/schema.mjs` gains, after `notifyDetail`, exactly:

```js
  documentStore: {
    type: 'enum', values: ['local', 'darkmem'], default: 'darkmem', env: 'DR_FORGE_DOCUMENT_STORE', group: 'darkmem', target: 'forge',
    label: 'Documents', title: 'Document store',
    description: 'Where a mapped repository keeps its specs, plans, registers and notes: local in the repository, or darkmem through the mirror. A change moves them at the next session start.',
  },
  progressSource: {
    type: 'enum', values: ['local', 'darkmem'], default: 'darkmem', env: 'DR_FORGE_PROGRESS_SOURCE', group: 'darkmem', target: 'forge',
    label: 'Progress', title: 'Progress tracking source',
    description: 'Where a mapped repository keeps its plan ledgers and handoffs: local in the repository, or darkmem through the mirror. A change moves them at the next session start.',
  },
```

**C2. `scripts/lib/darkmem-config.mjs` exports** (Task 2):

- `resolveStores({ cwd, env })` returns
  `{ repoRoot, worktreeRoot, reason, documents: { configured, applied, root }, progress: { configured, applied, ledgerRoot, latestFile }, sync }`.
  `repoRoot` is the primary checkout's top level, `worktreeRoot` the working directory's (both `null` outside git). `sync` is `null` for an unmapped repository, else `{ project, url, apiKey, keyEnv, mirror, statePath }` with `apiKey` `null` when the variable is unset. `reason` is a one-line why (`no <file>`, `no darkmem mapping for <root>`, `not inside a git repository`, `<file> has no darkmem section`, or `project <name>`).
  Roots: documents applied `darkmem` → `<mirror>/superpowers`, else `forgeDir("docs", worktreeRoot)`; progress applied `darkmem` → ledgerRoot `<mirror>/work/sdd` and latestFile `<mirror>/work/handoff/latest.md`, else `<forgeDir("state", worktreeRoot)>/sdd` and `<forgeDir("state", repoRoot)>/handoff/latest.md`.
  Configured store per family: unmapped → `local`; else the mapping entry's `documentStore`/`progressSource`, else `DR_FORGE_DOCUMENT_STORE`/`DR_FORGE_PROGRESS_SOURCE`, else the config file's global key, else `darkmem`. An entry value other than `local`/`darkmem` is a `ConfigError`.
  Applied store per family: unmapped → `local`; else the record's value (C3), else `darkmem` when the mirror's `.sync-state.json` lists files of that family, else `local`.
- `storesPath(env)` → `<HOME>/.dr-forge/stores.json`.
- `writeApplied(env, repoRoot, applied)` merges `applied` (e.g. `{ progress: "darkmem" }`) into the record's entry for `repoRoot`, replacing any key that names the same checkout.
- `modeLines(stores)` → `["documents\t<applied>\t<root>", "progress\t<applied>\t<ledgerRoot>\t<latestFile>"]`.
- CLI `node scripts/lib/darkmem-config.mjs --mode`, run in a checkout: prints `modeLines` one per line, exit 0; a `ConfigError` exits 2 with `darkmem-config: <message>` on stderr; outside git exits 3; any other arguments exit 2 with a usage line.
- `resolveMode` stays until Task 4 removes it.

**C3. `~/.dr-forge/stores.json`.** A JSON object mapping a primary checkout's absolute path to `{ "documents": "local"|"darkmem", "progress": "local"|"darkmem" }`; either key may be absent. Any other value, or a file that is not a JSON object, is a `ConfigError`.

**C4. Mirror roots** (`scripts/lib/darkmem-mirror.mjs`, Task 3). `roots = { docsRoot, workRoot, worktreeRoot?, families? }`, `families = { documents: boolean, progress: boolean }`; absent `families` means both true. New exports: `familiesOf(roots)`, `uriFamily(uri)` (`"progress"` for exactly `superpowers/handoff/<name>`, else `"documents"`), and `pathToUri(roots, file)` (replaces `pathToUri(file)`). `listDocumentFiles` lists docs-root files only when `families.documents`, plan `handoff.md` files only when `families.progress`; `localChanges` reports ledgers, unsupported plan directories and `latest.md` only when `families.progress`; `propertiesFor` adds `handoff_uri` only when `families.progress`.

**C5. Sync command context** (Task 4). Every command receives `{ cfg, roots, state, persist, client, report, options, out, env }` where `cfg = { ...stores.sync, repoRoot, worktreeRoot, documents, progress }` and `roots = { docsRoot: stores.documents.root, workRoot: <mirror>/work, worktreeRoot, families: { documents: documents.applied === "darkmem", progress: progress.applied === "darkmem" } }`.

**C6. Ledger entries** (`darkmem-mirror.mjs`, Task 7). `lineProperties(line)` → `{ task?, state?, commit? }`; `ledgerEntries(text)` → `[{ body, properties }]` for text made of complete lines.

**C7. `scripts/lib/roots.sh`** (Task 8). Sourced; sources `forge-dir.sh` and `native-path.sh`. Every helper takes an optional trailing `DIR` (default: the working directory) naming the checkout:

| Helper | Prints |
|---|---|
| `forge_stores_init [DIR]` | nothing; resolves and caches; a `ConfigError` exits the script 2 |
| `forge_docs_root [DIR]` | the documents root |
| `forge_docs_store [DIR]` / `forge_progress_store [DIR]` | `local` or `darkmem` |
| `forge_ledger_root [DIR]` | the directory holding `<slug>/progress.md` |
| `forge_ledger_dir SLUG [DIR]` | `<ledger root>/SLUG` |
| `forge_latest_file [DIR]` | the `latest.md` path |
| `forge_workspace SLUG [DIR]` | `<worktree>/<state>/sdd/SLUG`, always local |
| `forge_ledger_files [DIR]` | `<ledger file>\t<checkout path>` for every worktree's ledgers when progress is local; `<ledger file>\tmirror` for the mirror's when darkmem |
| `forge_resolve NAME [DIR]` | absolute path: `docs/forge/<rest>` or `docs/superpowers/<rest>` → `<docs root>/<rest>`; another relative name → `<worktree>/<name>`; an absolute path unchanged |
| `forge_name FILE [DIR]` | name: under the docs root → `<docs name>/<rest>` (`<docs name>` is `forge_dir_rel docs <worktree>`); under the worktree → the relative path; a relative FILE → itself minus a leading `./`; anything else unchanged |

**C8. Test fixture** `tests/fixtures/darkmem-stores.sh` (Task 8): `stores_home HOME REPO PROJECT DOCS PROGRESS` writes `HOME/.dr-forge/config.json` mapping REPO's primary checkout to PROJECT, and `HOME/.dr-forge/stores.json` applying documents DOCS and progress PROGRESS; creates the mirror's `superpowers/`, `work/sdd/` and `work/handoff/`; prints the mirror path `HOME/.dr-forge/mirror/PROJECT`.

**C9. `scripts/forge-path`** (Task 9): `state [REL]` (unchanged), `docs [REL]` (follows the documents root), `ledger SLUG`, `latest`, `store` (two lines, `documents <applied>` and `progress <applied>`), `name PATH`.

**C10. `scripts/lib/plan.sh`** (Tasks 10, 16): sources `roots.sh` instead of `forge-dir.sh`; new `plan_locate PLAN` (PLAN when it is a file, else `forge_resolve PLAN` when that is a file, else PLAN unchanged) and `plan_require_same_project FILE` (accepts FILE inside the working directory's top level, or under the documents root when documents are applied darkmem; otherwise the existing message and exit 2), plus the internal `_plan_ctx PLAN` (Task 10) that Task 16 also calls: prints PLAN's own directory when that directory is inside a git repository, else `$PWD`. Task 11 deletes `plan_require_same_repo`; Task 16 deletes `plan_repo_canon`.

**C11. Prose tokens** (Task 17): `<ledger dir>` = `bash <plugin-root>/scripts/forge-path ledger <plan-basename>`; `<latest.md>` = `bash <plugin-root>/scripts/forge-path latest`.

## Assumptions (evidence)

- darkmem's `WorklogEntryIn` takes per-entry `properties`: darkmem `backend/app/schemas/worklog.py:68` (inventory, 2026-10-13); the stub stores them (`tests/darkmem-sync/stub-server.mjs:118`).
- No hook or skill calls `darkmem-sync` yet: `README.md:289` ("The skills do not call it yet"), grep of `scripts`, `hooks`, `skills` on 2026-10-13. Plan 2 wires the triggers.
- `createClient` accepts a null key and only uses it per call: `scripts/lib/darkmem-client.mjs:27-33`. So `status` works offline.
- `forge-config.mjs` is safe to import: its CLI runs only under the `process.argv[1]` guard (`scripts/lib/forge-config.mjs`, last lines).
- The host's `~/.dr-forge/config.json` has no `darkmem` section (read 2026-10-13), and every existing suite works in temporary repositories, so with this plan every existing suite keeps local behaviour.
- Existing shell suites that leave `HOME` real stay correct once scripts source `roots.sh`: for an unmapped repository `resolveStores` reads only `~/.dr-forge/config.json` (Task 2 calls `resolveSettings` and reads `stores.json` only after a mapping matches), and every suite works in temporary repositories no host mapping names. The one host dependency left is a malformed `~/.dr-forge/config.json`, which now exits 2 as a `ConfigError` by design; Task 9 isolates `HOME` in `forge-dir.test.sh`, the suite that exercises `forge-path` directly.
- `resolveStores` reads the global settings through `resolve(env, warn)` (`scripts/lib/forge-config.mjs:179`), which applies a key's environment variable over the config file's value; Task 2 passes a silent `warn`.
- The executor lane is closed: `codex-gate usable=false reason=plugin-not-enabled lane=false` (2026-10-13), so no task carries an Executor line.
- `resolveStores` adds `worktreeRoot`, `reason` and `sync.keyEnv` to the spec §1 shape: additive, needed for local roots, the local-mode message and the offline message.
- `roots.sh` converts node's paths with `cygpath -m`, not the inventory's `-u`: `-m` gives the `C:/…` form `git rev-parse` prints under Git Bash, so prefix comparisons in `forge_name` match.
- The spec's §2 rewiring list misses the `$root/<name>` joins in `scripts/roadmap`, `scripts/register` and `lib/roadmap.sh`, and every script's `PLAN_FILE` argument: handoff prompts name plans as `docs/forge/…`, which only resolve through `plan_locate`. Tasks 11 and 12 cover them (inventory re-checked 2026-10-13 with `grep -n '\$root/'`).
- Out of this plan: the cockpit mod (`hooks/cockpit/register.tsx:2290-2325`) reads ledgers and `latest.md` from `<primary>/<state>/` directly; already recorded as open row 17 of `docs/superpowers/registers/2026-09-24-darkmem-mirror.md` (committed with this plan, 2659b22), so no task edits it.
- Register row 16 stays `doing`, assigned to the spec, because plan 2 delivers its move; this plan discharges row 2 and dr-forge register row 13 (`docs/superpowers/registers/2026-10-11-dr-forge.md`, which does not cover this spec, so Task 3 names it in its text instead of an Items line). Both rows were already set `planned` and assigned to this plan when it was written (2659b22); finishing the branch moves them on, so no task edits a register.
- Until plan 2, flipping `documentStore` or `progressSource` changes only the configured store; the applied store (`stores.json`) moves nothing until plan 2's reconcile. Plan 1 writes the record only from `darkmem-sync import` (Task 5). This pulls one piece of the spec's plan 2 (`stores.json`, Delivery item 2) forward: `resolveStores` must read the record to report an applied store, and an import is the one plan 1 command that makes a family darkmem-held, so without Task 5 the applied store would rest on the `.sync-state.json` inference alone. Owner to confirm at handoff.
- `skills/using-superpowers/SKILL.md` must stay at or under 5,100 bytes (`tests/hook.test.sh:183`); it is 5,025 bytes today, and Task 17's replacement line is 43 bytes shorter than the line it replaces (measured 2026-10-13).

## Task index

1. Add the two store settings
2. Resolve each family's configured and applied store
3. Gate the mirror by family and compute uris from roots
4. Run darkmem-sync on the stores
5. Record the applied stores after a verified import
6. Push and pull only the applied families
7. Send one ledger entry per line with its properties
8. Add the roots library
9. Teach forge-path the new kinds
10. Resolve plan paths through the roots
11. Locate plan arguments and check the same project
12. Read registers and the roadmap from the docs root
13. Read ledgers and latest.md through the roots in hooks
14. Route next-step through the roots
15. Route repo-audit and task-brief through the roots
16. Route plan-revise and plan-lint through the roots
17. Write the skill prose against the new tokens

---

### Task 1: Add the two store settings

**Files:**
- Modify: `config/schema.mjs` (append after `notifyDetail`, before the closing `};`)
- Modify: `scripts/validate-repository.mjs:122` (repository root)
- Modify: `README.md:712` (after the `notifyDetail` row)
- Test: `tests/forge-config.test.sh:117-130`, `tests/cockpit.test.ts:2259`

**Interfaces:**
- Consumes: none
- Produces: C1

**Implementer:** dr-superpowers:impl-sonnet-medium
**Evaluation:** files 1 - spec 0 - coupling 2 - risk 0 = 3

- [ ] **Step 1: Write the failing tests**

In `tests/forge-config.test.sh`, add two rows to the heredoc that ends in `ROWS`, after `finishTimeout 30 45 3`:

```
documentStore darkmem local remote
progressSource darkmem local remote
```

In `tests/cockpit.test.ts:2259`, replace

```ts
    expect(tabsOf(SCHEMA)).toEqual(['Cockpit', 'Context', 'Workflow', 'Process', 'Finish', 'Notifications'])
```

with

```ts
    expect(tabsOf(SCHEMA)).toEqual(['Cockpit', 'Context', 'Workflow', 'Process', 'Finish', 'Notifications', 'darkmem'])
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `timeout 600 bash plugins/dr-forge/tests/forge-config.test.sh`
Expected: FAIL on `documentStore: default` (`unknown setting documentStore`).

- [ ] **Step 3: Write the implementation**

Append C1's two entries to `config/schema.mjs` after the `notifyDetail` entry. In `scripts/validate-repository.mjs:122` replace

```js
const GROUPS = ['Cockpit', 'Context', 'Workflow', 'Process', 'Finish', 'Notifications'];
```

with

```js
const GROUPS = ['Cockpit', 'Context', 'Workflow', 'Process', 'Finish', 'Notifications', 'darkmem'];
```

In `README.md`, insert directly after the `| Notifications | \`notifyDetail\` | …` row:

```markdown
| darkmem | `documentStore` | `darkmem` | Where a repository mapped to darkmem keeps its specs, plans, registers and notes: `local` in the repository, `darkmem` through the mirror. A mapping entry's own `documentStore` outranks it and `DR_FORGE_DOCUMENT_STORE`; an unmapped repository is always local. |
| darkmem | `progressSource` | `darkmem` | The same choice for plan ledgers and handoffs. A mapping entry's own `progressSource` outranks it and `DR_FORGE_PROGRESS_SOURCE`. |
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `timeout 600 bash plugins/dr-forge/tests/forge-config.test.sh`, then `node scripts/validate-repository.mjs`, then `timeout 600 claude plugin test plugins/dr-forge`
Expected: `0 failed`; `… the settings schema are valid.`; the mod suite passes.

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-forge/config/schema.mjs scripts/validate-repository.mjs plugins/dr-forge/README.md plugins/dr-forge/tests/forge-config.test.sh plugins/dr-forge/tests/cockpit.test.ts
git commit -m "feat(dr-forge): add documentStore and progressSource"
```

### Task 2: Resolve each family's configured and applied store

**Files:**
- Modify: `scripts/lib/darkmem-config.mjs`
- Modify: `tests/darkmem-sync/helpers.mjs:38-59`
- Test: `tests/darkmem-sync/config.test.mjs` (rewritten)

**Interfaces:**
- Consumes: C1
- Produces: C2, C3; `makeHome`'s `stores` option (below)

**Implementer:** dr-superpowers:impl-sonnet-high
**Evaluation:** files 1 - spec 0 - coupling 2 - risk 2 = 5

- [ ] **Step 1: Give `makeHome` a stores record**

In `tests/darkmem-sync/helpers.mjs`, replace `makeHome` (lines 38-59, comment included) with:

```js
// A HOME whose ~/.dr-forge/config.json (with legacy: true, the pre-2.0
// ~/.dr-superpowers/config.json) maps `repo` to `project`.
// `config` replaces the file's content (a string is written verbatim); null
// writes no file at all. `stores` is the ~/.dr-forge/stores.json entry for
// `repo` (both families applied darkmem by default); null writes no record.
export function makeHome({
  repo, url = "http://127.0.0.1:9", project = "proj", config, legacy = false,
  stores = { documents: "darkmem", progress: "darkmem" },
} = {}) {
  const home = scratch("dms-home-");
  const dir = path.join(home, legacy ? ".dr-superpowers" : ".dr-forge");
  const body = config !== undefined ? config : { darkmem: { url, api_key_env: "DARKMEM_API_KEY", repos: { [repo]: { project } } } };
  if (body !== null) {
    fs.mkdirSync(dir, { recursive: true });
    fs.writeFileSync(path.join(dir, "config.json"), typeof body === "string" ? body : JSON.stringify(body));
  }
  if (stores !== null && repo) {
    fs.mkdirSync(path.join(home, ".dr-forge"), { recursive: true });
    fs.writeFileSync(path.join(home, ".dr-forge", "stores.json"), JSON.stringify({ [repo]: stores }));
  }
  const env = {
    ...process.env,
    HOME: home,
    DARKMEM_API_KEY: KEY,
    DR_FORGE_SESSION_ID: "sess-1",
    DARKMEM_SYNC_TIMEOUT_MS: "3000",
  };
  delete env.DR_FORGE_DOCUMENT_STORE;
  delete env.DR_FORGE_PROGRESS_SOURCE;
  const mirror = path.join(dir, "mirror", project);
  return { home, env, mirror, docsRoot: path.join(mirror, "superpowers"), workRoot: path.join(mirror, "work") };
}
```

- [ ] **Step 2: Write the failing tests**

Replace `tests/darkmem-sync/config.test.mjs` with:

```js
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";
import { ConfigError, resolveStores, runKey, storesPath, writeApplied } from "../../scripts/lib/darkmem-config.mjs";
import { KEY, git, makeHome, makeRepo, scratch, write } from "./helpers.mjs";

const MODULE = fileURLToPath(new URL("../../scripts/lib/darkmem-config.mjs", import.meta.url));
const applied = stores => [stores.documents.applied, stores.progress.applied];
const mapped = (repo, entry = {}, global = {}) => ({ ...global, darkmem: { url: "http://127.0.0.1:9", repos: { [repo]: { project: "proj", ...entry } } } });

test("no config file keeps both families local in the checkout", () => {
  const repo = makeRepo();
  const { env } = makeHome({ repo, config: null });
  const stores = resolveStores({ cwd: repo, env });
  assert.equal(stores.sync, null);
  assert.match(stores.reason, /^no .*config\.json$/);
  assert.deepEqual(stores.documents, { configured: "local", applied: "local", root: path.join(repo, "docs", "forge") });
  assert.deepEqual(stores.progress, {
    configured: "local", applied: "local",
    ledgerRoot: path.join(repo, ".forge", "sdd"), latestFile: path.join(repo, ".forge", "handoff", "latest.md"),
  });
});

test("a mapped repository applies each family as its record says", () => {
  const repo = makeRepo();
  const { env, mirror } = makeHome({ repo, url: "http://darkmem.test:8000/", stores: { documents: "darkmem", progress: "local" } });
  const stores = resolveStores({ cwd: repo, env });
  assert.equal(stores.reason, "project proj");
  assert.deepEqual(stores.documents, { configured: "darkmem", applied: "darkmem", root: path.join(mirror, "superpowers") });
  assert.deepEqual(stores.progress, {
    configured: "darkmem", applied: "local",
    ledgerRoot: path.join(repo, ".forge", "sdd"), latestFile: path.join(repo, ".forge", "handoff", "latest.md"),
  });
  assert.deepEqual(stores.sync, {
    project: "proj", url: "http://darkmem.test:8000", apiKey: KEY, keyEnv: "DARKMEM_API_KEY",
    mirror, statePath: path.join(mirror, ".sync-state.json"),
  });
  const both = resolveStores({ cwd: repo, env: makeHome({ repo }).env });
  assert.equal(both.progress.ledgerRoot, path.join(path.dirname(both.documents.root), "work", "sdd"));
  assert.equal(both.progress.latestFile, path.join(path.dirname(both.documents.root), "work", "handoff", "latest.md"));
});

test("the configured store: the mapping entry, then the environment, then the global key, then darkmem", () => {
  const repo = makeRepo();
  const rows = [
    [{}, {}, {}, "darkmem"],
    [{ documentStore: "local" }, {}, {}, "local"],
    [{ documentStore: "local" }, { DR_FORGE_DOCUMENT_STORE: "darkmem" }, {}, "darkmem"],
    [{ documentStore: "local" }, { DR_FORGE_DOCUMENT_STORE: "darkmem" }, { documentStore: "local" }, "local"],
    [{}, { DR_FORGE_DOCUMENT_STORE: "local" }, { documentStore: "darkmem" }, "darkmem"],
  ];
  for (const [global, variables, entry, want] of rows) {
    const { env } = makeHome({ repo, config: mapped(repo, entry, global) });
    Object.assign(env, variables);
    assert.equal(resolveStores({ cwd: repo, env }).documents.configured, want, JSON.stringify({ global, variables, entry }));
  }
  const { env } = makeHome({ repo, config: mapped(repo, { progressSource: "local" }) });
  env.DR_FORGE_PROGRESS_SOURCE = "darkmem";
  assert.equal(resolveStores({ cwd: repo, env }).progress.configured, "local");
});

test("an override or a record that is neither local nor darkmem is a ConfigError", () => {
  const repo = makeRepo();
  assert.throws(() => resolveStores({ cwd: repo, env: makeHome({ repo, config: mapped(repo, { documentStore: "cloud" }) }).env }), /sets documentStore to "cloud"; use local or darkmem/);
  assert.throws(() => resolveStores({ cwd: repo, env: makeHome({ repo, stores: { progress: "cloud" } }).env }), /progress for .* must be local or darkmem/);
  const { env, home } = makeHome({ repo });
  fs.writeFileSync(path.join(home, ".dr-forge", "stores.json"), "[]");
  assert.throws(() => resolveStores({ cwd: repo, env }), ConfigError);
});

test("with no record a family is applied darkmem only when the mirror's sync state lists its files", () => {
  const repo = makeRepo();
  const { env, mirror } = makeHome({ repo, stores: null });
  const state = (documents, ledgers = {}) => write(path.join(mirror, ".sync-state.json"), JSON.stringify({
    version: 1, documents, ledgers, checkpoint: null, checkpointAt: null, conflicts: [],
  }));
  const hash = "0".repeat(64);
  assert.deepEqual(applied(resolveStores({ cwd: repo, env })), ["local", "local"]);
  state({ "superpowers/specs/a.md": hash });
  assert.deepEqual(applied(resolveStores({ cwd: repo, env })), ["darkmem", "local"]);
  state({ "superpowers/handoff/p1.md": hash });
  assert.deepEqual(applied(resolveStores({ cwd: repo, env })), ["local", "darkmem"]);
  state({}, { p1: { offset: 0, prefix: hash } });
  assert.deepEqual(applied(resolveStores({ cwd: repo, env })), ["local", "darkmem"]);
});

test("a missing key keeps an applied-darkmem family on the mirror", () => {
  const repo = makeRepo();
  const { env, mirror } = makeHome({ repo });
  delete env.DARKMEM_API_KEY;
  const stores = resolveStores({ cwd: repo, env });
  assert.equal(stores.sync.apiKey, null);
  assert.equal(stores.documents.root, path.join(mirror, "superpowers"));
});

test("writeApplied records one family and keeps the other", () => {
  const repo = makeRepo();
  const { env } = makeHome({ repo, stores: { documents: "local", progress: "local" } });
  writeApplied(env, repo, { documents: "darkmem" });
  assert.deepEqual(JSON.parse(fs.readFileSync(storesPath(env), "utf8")), { [repo]: { documents: "darkmem", progress: "local" } });
  assert.deepEqual(applied(resolveStores({ cwd: repo, env })), ["darkmem", "local"]);
});

test("a pre-2.0 checkout keeps its docs/superpowers and .superpowers", () => {
  const repo = makeRepo();
  fs.mkdirSync(path.join(repo, "docs", "superpowers"), { recursive: true });
  fs.mkdirSync(path.join(repo, ".superpowers"), { recursive: true });
  const stores = resolveStores({ cwd: repo, env: makeHome({ repo, config: null }).env });
  assert.equal(stores.documents.root, path.join(repo, "docs", "superpowers"));
  assert.equal(stores.progress.ledgerRoot, path.join(repo, ".superpowers", "sdd"));
});

test("the pre-2.0 config and mirror are used until the new ones exist", () => {
  const repo = makeRepo();
  const { home, env } = makeHome({ repo, legacy: true });
  const old = path.join(home, ".dr-superpowers", "mirror", "proj");
  fs.mkdirSync(old, { recursive: true });
  assert.equal(resolveStores({ cwd: repo, env }).sync.mirror, old);
  const next = path.join(home, ".dr-forge", "mirror", "proj");
  fs.mkdirSync(next, { recursive: true });
  assert.equal(resolveStores({ cwd: repo, env }).sync.mirror, next);
});

test("the new config wins over the pre-2.0 one", () => {
  const repo = makeRepo();
  const { home, env } = makeHome({ repo, legacy: true });
  fs.writeFileSync(path.join(home, ".dr-forge", "config.json"), JSON.stringify({ layout: "compact" }));
  assert.equal(resolveStores({ cwd: repo, env }).sync, null);
});

test("a linked worktree keeps local families in itself and latest.md in the primary checkout", () => {
  const repo = makeRepo();
  const { env } = makeHome({ repo, stores: { documents: "local", progress: "local" } });
  const worktree = path.join(scratch("dms-wt-"), "wt");
  git(repo, "worktree", "add", "-q", "-b", "wt", worktree);
  const stores = resolveStores({ cwd: worktree, env });
  assert.equal(stores.sync.project, "proj");
  assert.equal(stores.documents.root, path.join(worktree, "docs", "forge"));
  assert.equal(stores.progress.ledgerRoot, path.join(worktree, ".forge", "sdd"));
  assert.equal(stores.progress.latestFile, path.join(repo, ".forge", "handoff", "latest.md"));
});

test("an unmapped repository and no git repository are local", () => {
  const repo = makeRepo();
  const other = makeRepo();
  assert.match(resolveStores({ cwd: other, env: makeHome({ repo }).env }).reason, /^no darkmem mapping for /);
  const plain = scratch("dms-plain-");
  const stores = resolveStores({ cwd: plain, env: makeHome({ repo }).env });
  assert.equal(stores.reason, "not inside a git repository");
  assert.equal(stores.documents.root, null);
});

test("a malformed config file, a climbing project or a bad url is a ConfigError", () => {
  const repo = makeRepo();
  assert.throws(() => resolveStores({ cwd: repo, env: makeHome({ repo, config: "{not json" }).env }), ConfigError);
  assert.throws(() => resolveStores({ cwd: repo, env: makeHome({ repo, project: "../up" }).env }), /needs a project/);
  assert.throws(() => resolveStores({ cwd: repo, env: makeHome({ repo, url: "darkmem.test" }).env }), /darkmem\.url/);
});

test("--mode prints each family's applied store and roots; a ConfigError exits 2 and no repository 3", () => {
  const repo = makeRepo();
  const { env, mirror } = makeHome({ repo, stores: { documents: "local", progress: "darkmem" } });
  const mode = (cwd, environment, args = ["--mode"]) => spawnSync(process.execPath, [MODULE, ...args], { cwd, env: environment, encoding: "utf8", timeout: 10000 });
  const result = mode(repo, env);
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.stdout, [
    `documents\tlocal\t${path.join(repo, "docs", "forge")}`,
    `progress\tdarkmem\t${path.join(mirror, "work", "sdd")}\t${path.join(mirror, "work", "handoff", "latest.md")}`,
    "",
  ].join("\n"));
  const broken = mode(repo, makeHome({ repo, config: "{nope" }).env);
  assert.equal(broken.status, 2);
  assert.match(broken.stderr, /^darkmem-config: .*not valid JSON/);
  assert.equal(mode(scratch("dms-plain-"), env).status, 3);
  assert.equal(mode(repo, env, []).status, 2);
});

test("the run key prefers the declared id, then the session record, then a day key", () => {
  const repo = makeRepo();
  const { home, env } = makeHome({ repo });
  assert.equal(runKey({ cwd: repo, env }), "sess-1");
  delete env.DR_FORGE_SESSION_ID;
  delete env.DR_SUPERPOWERS_SESSION_ID;
  const now = new Date("2026-09-24T10:00:00Z");
  assert.equal(runKey({ cwd: repo, env, now }), `codex:${os.hostname()}:2026-09-24`);
  const sessions = path.join(home, ".claude", "dr-forge", "sessions");
  fs.mkdirSync(sessions, { recursive: true });
  fs.writeFileSync(path.join(sessions, `${repo.replace(/[^A-Za-z0-9]/g, "-")}.json`), JSON.stringify({ session_id: "abc-123" }));
  assert.equal(runKey({ cwd: repo, env, now }), "abc-123");
});

// Carried over unchanged from the current file: it needs an empty HOME, not makeHome's mapping.
test("the pre-2.0 session id variable still declares the run, behind the new one", () => {
  const cwd = makeRepo();
  const HOME = scratch("dms-home-");
  assert.equal(runKey({ cwd, env: { HOME, DR_SUPERPOWERS_SESSION_ID: "old-1" } }), "old-1");
  assert.equal(runKey({ cwd, env: { HOME, DR_FORGE_SESSION_ID: "new-1", DR_SUPERPOWERS_SESSION_ID: "old-1" } }), "new-1");
});
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `timeout 300 node --test plugins/dr-forge/tests/darkmem-sync/config.test.mjs`
Expected: FAIL — `resolveStores` is not exported.

- [ ] **Step 4: Write the implementation**

In `scripts/lib/darkmem-config.mjs`, add to the imports:

```js
import { fileURLToPath } from "node:url";
import { resolve as resolveSettings } from "./forge-config.mjs";
```

After `samePath`, add:

```js
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
```

At the end of the file, add the CLI:

```js
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
```

Leave `resolveMode` in place: `darkmem-sync.mjs` still calls it until Task 4.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `timeout 300 node --test plugins/dr-forge/tests/darkmem-sync/config.test.mjs`, then `timeout 900 bash plugins/dr-forge/tests/darkmem-sync.test.sh`
Expected: PASS; the whole sync suite still passes (it still runs on `resolveMode`).

- [ ] **Step 6: Commit**

```bash
git add plugins/dr-forge/scripts/lib/darkmem-config.mjs plugins/dr-forge/tests/darkmem-sync/helpers.mjs plugins/dr-forge/tests/darkmem-sync/config.test.mjs
git commit -m "feat(dr-forge): resolve each family's store"
```

### Task 3: Gate the mirror by family and compute uris from roots

This task also discharges dr-forge register row 13 (`docs/superpowers/registers/2026-10-11-dr-forge.md`): `pathToUri` no longer matches the leftmost `superpowers/` segment.

**Files:**
- Modify: `scripts/lib/darkmem-mirror.mjs:76-97` (`listDocumentFiles`), `:448-453` (`pathToUri`), `:465-484` (`propertiesFor`), `:497-520` (`localChanges`)
- Test: `tests/darkmem-sync/mirror.test.mjs:7-11` (imports), `:75-81`, plus one new test

**Interfaces:**
- Consumes: none
- Produces: C4

**Implementer:** dr-superpowers:impl-sonnet-high
**Evaluation:** files 1 - spec 0 - coupling 2 - risk 2 = 5

- [ ] **Step 1: Write the failing tests**

In `tests/darkmem-sync/mirror.test.mjs`, add `familiesOf` and `uriFamily` to the import list from `darkmem-mirror.mjs`. Replace lines 77-81 (the five `pathToUri` assertions) with:

```js
  // A checkout and a project both named superpowers: the uri comes from the
  // roots, never from the leftmost superpowers/ segment.
  const named = {
    docsRoot: "/home/u/.dr-forge/mirror/superpowers/superpowers",
    workRoot: "/home/u/.dr-forge/mirror/superpowers/work",
    worktreeRoot: "/w/superpowers",
  };
  assert.equal(pathToUri(named, "docs/superpowers/plans/p1.md"), "superpowers/plans/p1.md");
  assert.equal(pathToUri(named, "./docs/forge/plans/p1.md"), "superpowers/plans/p1.md");
  assert.equal(pathToUri(named, "/home/u/.dr-forge/mirror/superpowers/superpowers/plans/p1.md"), "superpowers/plans/p1.md");
  assert.equal(pathToUri(named, "/w/superpowers/docs/forge/specs/s.md"), "superpowers/specs/s.md");
  assert.equal(pathToUri(named, "/w/superpowers/docs/superpowers/specs/s.md"), "superpowers/specs/s.md");
  assert.equal(pathToUri(named, "/w/superpowers/.forge/sdd/p1/progress.md"), null);
  assert.equal(pathToUri(named, "/elsewhere/superpowers/plans/p1.md"), null);
  assert.equal(pathToUri(named, "plans/p1.md"), null);
```

Add this test after the one that ends with `checkpointTarget(...), null);`:

```js
test("each family lists, reports and links only when the roots sync it", () => {
  const { roots } = mirror();
  write(path.join(roots.docsRoot, "specs", "a.md"), "a");
  write(path.join(roots.workRoot, "sdd", "p1", "handoff.md"), "h");
  write(path.join(roots.workRoot, "sdd", "p1", "progress.md"), "l\n");
  write(path.join(roots.workRoot, "handoff", "latest.md"), "x");
  const only = (documents, progress) => ({ ...roots, families: { documents, progress } });
  const uris = r => listDocumentFiles(r).map(f => f.uri);
  assert.deepEqual(uris(roots), ["superpowers/specs/a.md", "superpowers/handoff/p1.md"]);
  assert.deepEqual(uris(only(true, false)), ["superpowers/specs/a.md"]);
  assert.deepEqual(uris(only(false, true)), ["superpowers/handoff/p1.md"]);
  assert.deepEqual(uris(only(false, false)), []);
  assert.deepEqual(localChanges(only(true, false), emptyState()), ["new: superpowers/specs/a.md"]);
  assert.deepEqual(localChanges(only(false, true), emptyState()), [
    "new: superpowers/handoff/p1.md", "unpushed: sdd/p1/progress.md (2 bytes, never synced)", "modified: handoff/latest.md",
  ]);
  assert.deepEqual(propertiesFor(only(true, false), "p1", null), {});
  assert.deepEqual(propertiesFor(only(false, true), "p1", null), { handoff_uri: "superpowers/handoff/p1.md" });
  assert.deepEqual(familiesOf(roots), { documents: true, progress: true });
  assert.equal(uriFamily("superpowers/handoff/p1.md"), "progress");
  assert.equal(uriFamily("superpowers/specs/a.md"), "documents");
  assert.equal(uriFamily("superpowers/handoff/sub/x.md"), "documents");
});
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `timeout 300 node --test plugins/dr-forge/tests/darkmem-sync/mirror.test.mjs`
Expected: FAIL — `familiesOf` is not exported.

- [ ] **Step 3: Write the implementation**

In `scripts/lib/darkmem-mirror.mjs`, add after `uriToLocal`:

```js
// The families a sync touches. Roots without the field (import's, and the
// scratch roots its verification pulls into) touch both.
export function familiesOf(roots) {
  return roots.families ?? { documents: true, progress: true };
}

// A plan's handoff note is progress; every other document uri is documents.
export function uriFamily(uri) {
  const parts = String(uri).split("/");
  return parts.length === 3 && parts[0] === DOC_PREFIX && parts[1] === HANDOFF_DIR ? "progress" : "documents";
}
```

Replace `listDocumentFiles` (its comment and body) with:

```js
// Every document file the mirror syncs, with its uri: files under the docs
// root when documents sync, then each plan's handoff.md when progress does.
// Dotfiles are never synced. A file under the docs root's handoff/ directory
// gets uri null: that uri space belongs to the handoff notes.
export function listDocumentFiles(roots) {
  const families = familiesOf(roots);
  const found = [];
  const walk = (dir, rel) => {
    for (const entry of sortedEntries(dir)) {
      if (entry.name.startsWith(".")) continue;
      const file = path.join(dir, entry.name);
      const next = [...rel, entry.name];
      if (entry.isDirectory()) walk(file, next);
      else if (entry.isFile()) found.push({ file, uri: next[0] === HANDOFF_DIR ? null : `${DOC_PREFIX}/${next.join("/")}` });
    }
  };
  if (families.documents) walk(roots.docsRoot, []);
  if (families.progress) {
    for (const { slug, dir } of planDirs(roots.workRoot)) {
      const file = path.join(dir, "handoff.md");
      if (fs.existsSync(file)) found.push({ file, uri: `${DOC_PREFIX}/${HANDOFF_DIR}/${slug}.md` });
    }
  }
  return found;
}
```

Replace `pathToUri` (its comment and body) with:

```js
// The darkmem uri a document's name or path stands for: a name under
// docs/forge/ or docs/superpowers/ (as a ledger or a **Spec:** line writes
// it), or an absolute path under the docs root or the worktree's docs
// directory. Computed from the roots, never by searching for a segment.
export function pathToUri(roots, file) {
  const text = String(file).replace(/\\/g, "/");
  const name = /^(?:\.\/)?docs\/(?:forge|superpowers)\/(.+)$/.exec(text);
  if (name) return `${DOC_PREFIX}/${name[1]}`;
  if (!path.isAbsolute(String(file))) return null;
  const bases = [roots.docsRoot];
  if (roots.worktreeRoot) bases.push(path.join(roots.worktreeRoot, "docs", "forge"), path.join(roots.worktreeRoot, "docs", "superpowers"));
  for (const base of bases) {
    if (!base) continue;
    const rel = path.relative(path.resolve(base), path.resolve(String(file)));
    if (rel && rel !== ".." && !rel.startsWith(`..${path.sep}`) && !path.isAbsolute(rel)) {
      return `${DOC_PREFIX}/${rel.split(path.sep).join("/")}`;
    }
  }
  return null;
}
```

In `propertiesFor`, change both `pathToUri(` calls to pass `roots` first (`pathToUri(roots, namedPath)` and `pathToUri(roots, spec[1])`), and replace

```js
  if (fs.existsSync(path.join(roots.workRoot, "sdd", slug, "handoff.md"))) {
```

with

```js
  if (familiesOf(roots).progress && fs.existsSync(path.join(roots.workRoot, "sdd", slug, "handoff.md"))) {
```

In `localChanges`, insert directly after the first `for` loop (the one over `listDocumentFiles`):

```js
  if (!familiesOf(roots).progress) return lines;
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `timeout 300 node --test plugins/dr-forge/tests/darkmem-sync/mirror.test.mjs`, then `timeout 900 bash plugins/dr-forge/tests/darkmem-sync.test.sh`
Expected: PASS; the whole sync suite passes (its roots carry no `families`, so both families sync).

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-forge/scripts/lib/darkmem-mirror.mjs plugins/dr-forge/tests/darkmem-sync/mirror.test.mjs
git commit -m "fix(dr-forge): compute darkmem uris from the roots"
```

### Task 4: Run darkmem-sync on the stores

**Files:**
- Modify: `scripts/lib/darkmem-sync.mjs` (replace the whole file)
- Modify: `scripts/lib/darkmem-config.mjs` (delete `resolveMode`; new header comment)
- Modify: `scripts/darkmem-sync:2-16` (header comment)
- Test: `tests/darkmem-sync/cli.test.mjs`, `tests/darkmem-sync/push.test.mjs:131,282`

**Interfaces:**
- Consumes: C2, C4
- Produces: C5

**Implementer:** dr-superpowers:impl-sonnet-high
**Evaluation:** files 1 - spec 0 - coupling 2 - risk 2 = 5

- [ ] **Step 1: Write the failing tests**

In `tests/darkmem-sync/cli.test.mjs`, replace the expected output in "status in darkmem mode names the mirror and its local changes" with:

```js
  assert.equal(result.stdout, [
    `darkmem-sync: project proj at http://127.0.0.1:9; mirror ${mirror}`,
    "documents: configured darkmem, applied darkmem",
    "progress: configured darkmem, applied darkmem",
    "new: superpowers/specs/a.md",
    "unpushed: sdd/p1/progress.md (52 bytes, never synced)",
    "",
  ].join("\n"));
```

In `tests/darkmem-sync/push.test.mjs`, `status` now prints three header lines (the project line, `documents: …`, `progress: …`) before any change line. Change the expected count in both clean-status assertions from `1` to `3`: line 131, which ends `.stdout.split("\n").filter(Boolean).length, 1);`, and line 282, `assert.equal(clean.stdout.split("\n").filter(Boolean).length, 1);`. The `pull.test.mjs` status checks are regex matches and need no change.

In `tests/darkmem-sync/cli.test.mjs`, append these tests:

```js
test("status names a local family as not synced and leaves its files out", async () => {
  const repo = makeRepo();
  const { env, docsRoot, workRoot } = makeHome({ repo, stores: { documents: "darkmem", progress: "local" } });
  write(path.join(docsRoot, "specs", "a.md"), "# A\n");
  write(path.join(workRoot, "sdd", "p1", "progress.md"), "one\n");
  const result = await run(["status"], { cwd: repo, env });
  assert.equal(result.code, 0, result.stderr);
  assert.match(result.stdout, /^documents: configured darkmem, applied darkmem$/m);
  assert.match(result.stdout, /^progress: configured darkmem, applied local, not synced$/m);
  assert.match(result.stdout, /^new: superpowers\/specs\/a\.md$/m);
  assert.doesNotMatch(result.stdout, /sdd\/p1/);
});

test("without the key status still runs, and pull and push skip with exit 3", async () => {
  const repo = makeRepo();
  const { env, mirror } = makeHome({ repo });
  delete env.DARKMEM_API_KEY;
  assert.equal((await run(["status"], { cwd: repo, env })).code, 0);
  for (const command of ["pull", "push"]) {
    const result = await run([command], { cwd: repo, env });
    assert.equal(result.code, 3, command);
    assert.equal(result.stderr, `darkmem-sync: ${command} skipped: DARKMEM_API_KEY is not set; working offline from the mirror\n`);
  }
  assert.equal(fs.existsSync(path.join(mirror, ".sync.lock")), false);
});

test("a mapped repository with both families local has nothing to pull or push", async () => {
  const repo = makeRepo();
  const { env } = makeHome({ repo, stores: { documents: "local", progress: "local" } });
  for (const command of ["pull", "push"]) {
    const result = await run([command], { cwd: repo, env });
    assert.equal(result.code, 0, command);
    assert.equal(result.stdout, `darkmem-sync: nothing to ${command}: documents and progress are both applied local\n`);
  }
});
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `timeout 300 node --test plugins/dr-forge/tests/darkmem-sync/cli.test.mjs`
Expected: FAIL — status still prints `darkmem mode — project proj …`.

- [ ] **Step 3: Write the implementation**

Replace `scripts/lib/darkmem-sync.mjs` with:

```js
// darkmem-sync's entry point, run by scripts/darkmem-sync: argument parsing,
// the stores, lock, state and exit codes. The commands live in darkmem-pull.mjs,
// darkmem-push.mjs and darkmem-import.mjs; scripts/darkmem-sync documents the
// usage and exit codes.
import path from "node:path";
import { ConfigError, resolveStores, runKey } from "./darkmem-config.mjs";
import { HttpError, TransportError, createClient } from "./darkmem-client.mjs";
import { StateError, UsageError, acquireLock, loadState, localChanges, lockOwner, saveState } from "./darkmem-mirror.mjs";
import { importRepository } from "./darkmem-import.mjs";
import { pull } from "./darkmem-pull.mjs";
import { push } from "./darkmem-push.mjs";

const USAGE = "usage: darkmem-sync status | pull | push [--workstream KEY] | import [--replace]";

const familyLine = (name, family) => `${name}: configured ${family.configured}, applied ${family.applied}${family.applied === "darkmem" ? "" : ", not synced"}`;

async function status({ cfg, roots, state, report, out }) {
  out(`darkmem-sync: project ${cfg.project} at ${cfg.url}; mirror ${cfg.mirror}`);
  out(familyLine("documents", cfg.documents));
  out(familyLine("progress", cfg.progress));
  for (const line of localChanges(roots, state)) out(line);
  report.conflicts.push(...(state.conflicts ?? []));
}

// options maps each accepted flag to whether it takes a value. needsKey skips
// the command when the API key is unset, since the mirror stays usable
// offline; syncsFamilies makes it a no-op when no family is applied darkmem;
// recordsConflicts keeps this run's conflicts in the state file for `status`.
const COMMANDS = {
  status: { options: {}, needsKey: false, syncsFamilies: false, recordsConflicts: false, run: status },
  pull: { options: {}, needsKey: true, syncsFamilies: true, recordsConflicts: true, run: pull },
  push: { options: { "--workstream": true }, needsKey: true, syncsFamilies: true, recordsConflicts: true, run: push },
  import: { options: { "--replace": false }, needsKey: true, syncsFamilies: false, recordsConflicts: false, run: importRepository },
};

function parse(argv) {
  const [name, ...rest] = argv;
  const command = Object.hasOwn(COMMANDS, name) ? COMMANDS[name] : null;
  if (!command) return null;
  const options = {};
  for (let i = 0; i < rest.length; i += 1) {
    const flag = rest[i];
    if (!Object.hasOwn(command.options, flag)) return null;
    if (command.options[flag]) {
      const value = rest[i + 1];
      if (value === undefined) return null;
      options[flag] = value;
      i += 1;
    } else {
      options[flag] = true;
    }
  }
  return { name, command, options };
}

function summary(name, report) {
  const counts = Object.entries(report.counts).map(([what, n]) => `${n} ${what}`).join(", ") || "nothing to do";
  return `darkmem-sync ${name}: ${counts}; ${report.conflicts.length} conflicts, ${report.failures.length} failures`;
}

async function main(argv, {
  cwd = process.cwd(),
  env = process.env,
  out = line => process.stdout.write(`${line}\n`),
  err = line => process.stderr.write(`${line}\n`),
} = {}) {
  const parsed = parse(argv);
  if (!parsed) {
    err(USAGE);
    return 2;
  }
  let stores;
  try {
    stores = resolveStores({ cwd, env });
  } catch (error) {
    if (!(error instanceof ConfigError)) throw error;
    err(`darkmem-sync: ${error.message}`);
    return 2;
  }
  if (!stores.sync) {
    out(`darkmem-sync: local mode — ${stores.reason}`);
    return parsed.name === "import" ? 2 : 0;
  }
  const cfg = { ...stores.sync, repoRoot: stores.repoRoot, worktreeRoot: stores.worktreeRoot, documents: stores.documents, progress: stores.progress };
  const families = { documents: cfg.documents.applied === "darkmem", progress: cfg.progress.applied === "darkmem" };
  if (parsed.command.syncsFamilies && !families.documents && !families.progress) {
    out(`darkmem-sync: nothing to ${parsed.name}: documents and progress are both applied local`);
    return 0;
  }
  if (parsed.command.needsKey && !cfg.apiKey) {
    err(`darkmem-sync: ${parsed.name} skipped: ${cfg.keyEnv} is not set; working offline from the mirror`);
    return 3;
  }
  const release = acquireLock(cfg.mirror);
  if (!release) {
    const owner = lockOwner(cfg.mirror);
    const holder = owner ? `pid ${owner.pid} on ${owner.host}` : "an unknown process";
    err(`darkmem-sync: another darkmem-sync (${holder}) holds ${path.join(cfg.mirror, ".sync.lock")}; if that process is gone, remove the directory`);
    return 1;
  }
  const report = { conflicts: [], failures: [], notes: [], counts: {}, partial: false };
  let state = null;
  let code = 0;
  try {
    state = loadState(cfg.statePath);
    const persist = () => saveState(cfg.statePath, state);
    const client = createClient({
      url: cfg.url,
      apiKey: cfg.apiKey,
      runKey: runKey({ cwd, env }),
      timeoutMs: Number(env.DARKMEM_SYNC_TIMEOUT_MS) || 10000,
    });
    const roots = { docsRoot: cfg.documents.root, workRoot: path.join(cfg.mirror, "work"), worktreeRoot: cfg.worktreeRoot, families };
    await parsed.command.run({ cfg, roots, state, persist, client, report, options: parsed.options, out, env });
  } catch (error) {
    if (error instanceof TransportError || error instanceof HttpError) {
      err(`darkmem-sync: ${parsed.name} failed: ${error.message}`);
      code = 3;
    } else if (error instanceof StateError || error instanceof UsageError) {
      err(`darkmem-sync: ${error.message}`);
      code = 2;
    } else {
      code = 4;
      throw error;
    }
  } finally {
    try {
      if (state) {
        // A completed run replaces the recorded conflicts; a run that stopped
        // part-way, or failed an item or phase darkmem answered with an error,
        // adds what it found, since it never re-checked the rest.
        if (parsed.command.recordsConflicts) {
          state.conflicts = code === 0 && !report.partial ? report.conflicts : [...new Set([...state.conflicts, ...report.conflicts])];
        }
        saveState(cfg.statePath, state);
      }
    } finally {
      release();
    }
  }
  for (const line of report.conflicts) out(`conflict: ${line}`);
  for (const line of report.failures) out(`failed: ${line}`);
  for (const line of report.notes) out(`note: ${line}`);
  if (code !== 0) return code;
  if (parsed.name !== "status") out(summary(parsed.name, report));
  return report.conflicts.length || report.failures.length ? 1 : 0;
}

main(process.argv.slice(2)).then(
  code => { process.exitCode = code; },
  error => {
    process.stderr.write(`darkmem-sync: unexpected error: ${error?.stack ?? error}\n`);
    process.exitCode = 4;
  },
);
```

In `scripts/lib/darkmem-config.mjs`, delete the whole `resolveMode` function, and replace the file's first five comment lines with:

```js
// dr-forge's darkmem stores for one repository (darkmem store options spec
// §1): the mapping in ~/.dr-forge/config.json (the pre-2.0
// ~/.dr-superpowers/config.json until the new file exists), each family's
// configured store and its applied store from ~/.dr-forge/stores.json, the
// mirror, the API key's variable, and the run key a sync declares. An
// unmapped repository keeps both families local.
```

In `scripts/darkmem-sync`, replace lines 2-16 (from `# Keep this repository's` through the `#       4 an unexpected error (a bug)` line) with:

```bash
# Keep this repository's dr-forge documents and progress in darkmem.
#
# A repository mapped in ~/.dr-forge/config.json (~/.dr-superpowers/ before 2.0)
# syncs a mirror at ~/.dr-forge/mirror/<project>/ (~/.dr-superpowers/ before
# 2.0): superpowers/ (specs, plans, registers, notes) while its documents are
# applied darkmem, work/sdd/<plan>/{progress.md,handoff.md} and
# work/handoff/latest.md while its progress is. ~/.dr-forge/stores.json records
# the applied stores; documentStore and progressSource choose them. An
# unmapped repository is local mode: every command except import prints one
# line and does nothing.
#
# Usage: darkmem-sync status | pull | push [--workstream KEY] | import [--replace]
# Exit: 0 done, or no family applied darkmem; 1 conflicts, refused or failed
#       items, or another sync holds the mirror; 2 usage, a malformed config,
#       stores or state file, or import in local mode; 3 darkmem unreachable,
#       the API key unset (pull, push, import), or an answer that stopped the
#       command; 4 an unexpected error (a bug)
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `timeout 900 bash plugins/dr-forge/tests/darkmem-sync.test.sh`
Expected: PASS, every file.

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-forge/scripts/lib/darkmem-sync.mjs plugins/dr-forge/scripts/lib/darkmem-config.mjs plugins/dr-forge/scripts/darkmem-sync plugins/dr-forge/tests/darkmem-sync/cli.test.mjs plugins/dr-forge/tests/darkmem-sync/push.test.mjs
git commit -m "feat(dr-forge): run darkmem-sync on the stores"
```

### Task 5: Record the applied stores after a verified import

**Files:**
- Modify: `scripts/lib/darkmem-import.mjs:10` (import), `:111-145` (`importRepository`)
- Test: `tests/darkmem-sync/import.test.mjs`

**Interfaces:**
- Consumes: C2 (`writeApplied`, `storesPath`), C5 (`cfg.documents`, `cfg.progress`, `env`)
- Produces: none

**Implementer:** dr-superpowers:impl-sonnet-medium
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 1 = 3

- [ ] **Step 1: Write the failing tests**

Append to `tests/darkmem-sync/import.test.mjs`:

```js
test("a verified import records each family configured darkmem as applied darkmem", async t => {
  const stub = await startStub();
  t.after(() => stub.close());
  const repo = makeRepo();
  const config = { documentStore: "local", darkmem: { url: stub.url, api_key_env: "DARKMEM_API_KEY", repos: { [repo]: { project: "proj" } } } };
  const home = makeHome({ repo, config, stores: null });
  write(path.join(repo, "docs", "forge", "specs", "s.md"), "# Spec\n");
  write(path.join(repo, ".forge", "sdd", "p1", "progress.md"), "# SDD ledger — plan: docs/forge/plans/p1.md\nTask 1: complete\n");
  const result = await run(["import"], { cwd: repo, env: home.env });
  assert.equal(result.code, 0, result.stdout + result.stderr);
  const record = JSON.parse(fs.readFileSync(path.join(home.home, ".dr-forge", "stores.json"), "utf8"));
  assert.deepEqual(record, { [repo]: { progress: "darkmem" } });
  assert.match(result.stdout, /^note: recorded progress as applied darkmem in .*stores\.json$/m);
});

test("an import with a refused document records nothing", async t => {
  const stub = await startStub();
  t.after(() => stub.close());
  const repo = makeRepo();
  const home = makeHome({ repo, url: stub.url, stores: null });
  write(path.join(repo, "docs", "forge", "specs", "s.md"), "# Spec\n");
  stub.db.failures.push({ method: "POST", path: "/api/v1/documents", status: 422, detail: "refused" });
  const result = await run(["import"], { cwd: repo, env: home.env });
  assert.equal(result.code, 1, result.stdout);
  assert.equal(fs.existsSync(path.join(home.home, ".dr-forge", "stores.json")), false);
});
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `timeout 300 node --test plugins/dr-forge/tests/darkmem-sync/import.test.mjs`
Expected: FAIL — `stores.json` does not exist after the import.

- [ ] **Step 3: Write the implementation**

In `scripts/lib/darkmem-import.mjs`, change the config import to:

```js
import { forgeDir, storesPath, writeApplied } from "./darkmem-config.mjs";
```

In `importRepository`, change the destructuring to `const { cfg, client, report, options, env } = context;`, change the roots line to

```js
  const roots = { docsRoot: forgeDir("docs", cfg.repoRoot), workRoot: forgeDir("state", cfg.repoRoot), worktreeRoot: cfg.repoRoot };
```

and replace the last line, `await verify(context, roots, snapshot);`, with:

```js
  await verify(context, roots, snapshot);
  // Only a clean, verified import moves a family's applied store; a family
  // configured local stays local even though its files were filed.
  if (report.failures.length || report.conflicts.length) return;
  const families = ["documents", "progress"].filter(family => cfg[family].configured === "darkmem");
  if (!families.length) return;
  writeApplied(env, cfg.repoRoot, Object.fromEntries(families.map(family => [family, "darkmem"])));
  report.notes.push(`recorded ${families.join(" and ")} as applied darkmem in ${storesPath(env)}`);
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `timeout 300 node --test plugins/dr-forge/tests/darkmem-sync/import.test.mjs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-forge/scripts/lib/darkmem-import.mjs plugins/dr-forge/tests/darkmem-sync/import.test.mjs
git commit -m "feat(dr-forge): record applied stores after import"
```

### Task 6: Push and pull only the applied families

**Files:**
- Modify: `scripts/lib/darkmem-push.mjs:10-14` (imports), `:334-342` (`push`)
- Modify: `scripts/lib/darkmem-pull.mjs:7` (imports), `:64-88` (`pullDocuments`), `:164-176` (`pull`)
- Test: `tests/darkmem-sync/push.test.mjs`, `tests/darkmem-sync/pull.test.mjs`

**Interfaces:**
- Consumes: C4 (`familiesOf`, `uriFamily`), C5
- Produces: none

**Items:** 2

**Implementer:** dr-superpowers:impl-sonnet-medium
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 2 = 4

- [ ] **Step 1: Write the failing tests**

Append to `tests/darkmem-sync/push.test.mjs`:

```js
test("push sends only the applied families, a plan's handoff.md with progress, and --workstream needs progress", async t => {
  const s = await setup(t);
  const records = stores => fs.writeFileSync(path.join(s.home, ".dr-forge", "stores.json"), JSON.stringify({ [s.repo]: stores }));
  const uris = () => [...s.stub.db.documents.keys()].map(k => k.split("\u0000")[1]).sort();
  records({ documents: "darkmem", progress: "local" });
  write(path.join(s.docsRoot, "specs", "a.md"), "# A\n");
  write(path.join(s.workRoot, "sdd", "p1", "handoff.md"), "# h\n");
  write(path.join(s.workRoot, "sdd", "p1", "progress.md"), "one\n");
  const documents = await s.push();
  assert.equal(documents.code, 0, documents.stdout + documents.stderr);
  assert.deepEqual(uris(), ["superpowers/specs/a.md"]);
  assert.equal(s.stub.db.workstreams.length, 0);
  const refused = await s.push("--workstream", "p1");
  assert.equal(refused.code, 2);
  assert.match(refused.stderr, /--workstream needs progress applied darkmem/);
  records({ documents: "local", progress: "darkmem" });
  const progress = await s.push();
  assert.equal(progress.code, 0, progress.stdout + progress.stderr);
  assert.deepEqual(uris(), ["superpowers/handoff/p1.md", "superpowers/specs/a.md"]);
  assert.deepEqual((await s.ledger("p1")).map(e => e.body), ["one\n"]);
});
```

Append to `tests/darkmem-sync/pull.test.mjs`:

```js
test("pull writes only the applied families, a handoff note with progress", async t => {
  const s = await setup(t);
  const records = stores => fs.writeFileSync(path.join(s.home, ".dr-forge", "stores.json"), JSON.stringify({ [s.repo]: stores }));
  await s.seed.putDocument({ project: "proj", uri: "superpowers/specs/a.md", content: "# A\n" });
  await s.seed.putDocument({ project: "proj", uri: "superpowers/handoff/p1.md", content: "# Handoff\n" });
  await s.seed.append({ project: "proj", workstream: "p1", entries: [{ kind: "ledger", body: "one\n" }] });
  records({ documents: "darkmem", progress: "local" });
  const documents = await s.pull();
  assert.equal(documents.code, 0, documents.stdout + documents.stderr);
  assert.equal(read(path.join(s.docsRoot, "specs", "a.md")), "# A\n");
  assert.equal(fs.existsSync(path.join(s.workRoot, "sdd", "p1", "handoff.md")), false);
  assert.equal(fs.existsSync(path.join(s.workRoot, "sdd", "p1", "progress.md")), false);
  fs.rmSync(path.join(s.docsRoot, "specs", "a.md"));
  records({ documents: "local", progress: "darkmem" });
  const progress = await s.pull();
  assert.equal(progress.code, 0, progress.stdout + progress.stderr);
  assert.equal(read(path.join(s.workRoot, "sdd", "p1", "handoff.md")), "# Handoff\n");
  assert.equal(read(path.join(s.workRoot, "sdd", "p1", "progress.md")), "one\n");
  assert.equal(fs.existsSync(path.join(s.docsRoot, "specs", "a.md")), false);
});
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `timeout 300 node --test plugins/dr-forge/tests/darkmem-sync/push.test.mjs`, then the same for `pull.test.mjs`
Expected: FAIL — the ledger is pushed while progress is local; the handoff note is pulled while progress is local.

- [ ] **Step 3: Write the implementation**

In `scripts/lib/darkmem-push.mjs`, add `familiesOf` to the import list from `./darkmem-mirror.mjs`, and replace `push` with:

```js
export async function push(context) {
  const named = context.options["--workstream"];
  if (named !== undefined && !validKey(named)) throw new UsageError(`--workstream ${JSON.stringify(named)} is not a workstream key`);
  const families = familiesOf(context.roots);
  if (named !== undefined && !families.progress) throw new UsageError("--workstream needs progress applied darkmem; latest.md is local");
  Object.assign(context.report.counts, { documents: 0, "ledger entries": 0, checkpoints: 0 });
  if (families.progress) for (const uri of [...context.state.pendingLinks]) await linkHandoff(context, uri);
  await pushDocuments(context);
  if (!families.progress) return;
  await pushLedgers(context);
  await pushCheckpoint(context, named);
}
```

In `scripts/lib/darkmem-pull.mjs`, add `familiesOf` and `uriFamily` to the import list from `./darkmem-mirror.mjs`. In `pullDocuments`, replace

```js
  const twins = caseGroups(items.map(item => item.uri));
```

with

```js
  const families = familiesOf(context.roots);
  items = items.filter(item => families[uriFamily(item.uri)]);
  const twins = caseGroups(items.map(item => item.uri));
```

and replace `pull` with:

```js
export async function pull(context) {
  Object.assign(context.report.counts, { documents: 0, ledgers: 0, checkpoints: 0 });
  const families = familiesOf(context.roots);
  if (families.documents || families.progress) await pullDocuments(context);
  if (!families.progress) return;
  let open;
  try {
    open = await context.client.workstreams(context.cfg.project, "open");
  } catch (error) {
    failItem(context.report, "workstream list", error, "; no ledger or checkpoint pulled");
    return;
  }
  await pullLedgers(context, open);
  await pullCheckpoint(context, open);
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `timeout 900 bash plugins/dr-forge/tests/darkmem-sync.test.sh`
Expected: PASS, every file.

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-forge/scripts/lib/darkmem-push.mjs plugins/dr-forge/scripts/lib/darkmem-pull.mjs plugins/dr-forge/tests/darkmem-sync/push.test.mjs plugins/dr-forge/tests/darkmem-sync/pull.test.mjs
git commit -m "feat(dr-forge): sync only the applied families"
```

### Task 7: Send one ledger entry per line with its properties

**Files:**
- Modify: `scripts/lib/darkmem-mirror.mjs` (add after `splitAtBlankLines`)
- Modify: `scripts/lib/darkmem-push.mjs:182-258` (`pushLedger`)
- Test: `tests/darkmem-sync/mirror.test.mjs`, `tests/darkmem-sync/push.test.mjs:134-176`, `:334-356`

**Interfaces:**
- Consumes: none
- Produces: C6

**Implementer:** dr-superpowers:impl-sonnet-medium
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 2 = 4

- [ ] **Step 1: Write the failing tests**

In `tests/darkmem-sync/mirror.test.mjs`, add `ledgerEntries` and `lineProperties` to the import list, and add:

```js
test("a ledger line yields its task, state and commit; a blank line joins the entry before it", () => {
  const rows = [
    ["Task 3: complete (commits a1b2c3d..f0e1d2c, review clean) — done: x\n", { task: 3, state: "done", commit: "f0e1d2c" }],
    ["Task 4: BLOCKED — impl-opus-high exhausted — decide\n", { task: 4, state: "blocked" }],
    ["Task 5: fix round 2/5 (1 addressed, 0 open — x; commits 1234567..89abcde; resumed)\n", { task: 5, state: "review", commit: "89abcde" }],
    ["Task 6: implementer dr-forge:impl-sonnet-low (assigned; base 1a2b3c4)\n", { task: 6, state: "wip" }],
    ["Task 7: implementer (assigned)\n", { task: 7 }],
    ["Task 8: minor (deferred): complete (later)\n", { task: 8 }],
    ["Group 1-2: review round 1/5 (commits a..b)\n", {}],
    ["# SDD ledger — plan: docs/forge/plans/p.md\n", {}],
  ];
  for (const [line, want] of rows) assert.deepEqual(lineProperties(line), want, line);
  assert.deepEqual(ledgerEntries("# L\n\nTask 1: complete (x)\n\n\nTask 2: BLOCKED — y\r\n"), [
    { body: "# L\n\n", properties: {} },
    { body: "Task 1: complete (x)\n\n\n", properties: { task: 1, state: "done" } },
    { body: "Task 2: BLOCKED — y\r\n", properties: { task: 2, state: "blocked" } },
  ]);
  assert.deepEqual(ledgerEntries("\nTask 1: x\n"), [{ body: "\nTask 1: x\n", properties: { task: 1 } }]);
  assert.deepEqual(ledgerEntries("\n\n"), [{ body: "\n\n", properties: {} }]);
});
```

In `tests/darkmem-sync/push.test.mjs` (every line number below is the original file's; find each test by its name once an earlier edit has shifted them), replace the test "a ledger goes up as the appended bytes, one entry per push, and darkmem's concatenation is the file" (lines 134-152) with:

```js
test("a ledger goes up one entry per complete line, with the line's properties, and darkmem's concatenation is the file", async t => {
  const s = await setup(t);
  write(path.join(s.docsRoot, "plans", "p1.md"), "# P1\n\n**Spec:** `docs/superpowers/specs/s.md`\n");
  const file = path.join(s.workRoot, "sdd", "p1", "progress.md");
  write(file, "# SDD ledger — plan: docs/superpowers/plans/p1.md\n\nTask 1: implementer dr-forge:impl-sonnet-low (assigned; base 1a2b3c4)\n");
  assert.equal((await s.push()).code, 0);
  fs.appendFileSync(file, "Task 1: complete (commits 1a2b3c4..5d6e7f8, review clean)\n\n| a | b |\n|---|---|\nTask 2: held");
  const second = await s.push();
  assert.match(second.stdout, /0 documents, 3 ledger entries/);
  assert.match(second.stdout, /^note: sdd\/p1\/progress\.md: the last line has no newline yet; it is held until the next push$/m);
  const entries = await s.ledger("p1");
  assert.deepEqual(entries.map(e => [e.body, e.properties]), [
    ["# SDD ledger — plan: docs/superpowers/plans/p1.md\n\n", {}],
    ["Task 1: implementer dr-forge:impl-sonnet-low (assigned; base 1a2b3c4)\n", { task: 1, state: "wip" }],
    ["Task 1: complete (commits 1a2b3c4..5d6e7f8, review clean)\n\n", { task: 1, state: "done", commit: "5d6e7f8" }],
    ["| a | b |\n", {}],
    ["|---|---|\n", {}],
  ]);
  assert.equal(entries[0].run_key, "sess-1");
  const ws = s.stub.db.workstreams.find(w => w.key === "p1");
  assert.deepEqual(ws.properties, { plan_uri: "superpowers/plans/p1.md", spec_uri: "superpowers/specs/s.md" });
  fs.appendFileSync(file, "\n");
  assert.equal((await s.push()).code, 0);
  assert.equal((await s.ledger("p1")).map(e => e.body).join(""), read(file));
  assert.equal((await s.push()).code, 0);
  assert.equal((await s.ledger("p1")).length, 6, "nothing new, nothing sent");
});
```

In the test "a rewritten ledger is refused and nothing is sent" (line 154), the first push of `"one\ntwo\n"` now sends two entries: change its last line, `assert.equal((await s.ledger("p1")).length, 1);` (line 163), to `assert.equal((await s.ledger("p1")).length, 2);`.

After that test, add:

```js
test("a ledger line longer than one entry is split and every piece carries the line's properties", async t => {
  const s = await setup(t);
  const file = path.join(s.workRoot, "sdd", "p1", "progress.md");
  write(file, `Task 1: complete (commits 1a2b3c4..5d6e7f8, review clean) — ${"x".repeat(70000)}\n`);
  assert.equal((await s.push()).code, 0);
  const entries = await s.ledger("p1");
  assert.equal(entries.length, 2);
  for (const entry of entries) assert.deepEqual(entry.properties, { task: 1, state: "done", commit: "5d6e7f8" });
  assert.equal(entries.map(e => e.body).join(""), read(file));
});
```

In the test "an append longer than one entry is split at a newline and still concatenates exactly" (line 166), change `assert.equal(entries.length, 2);` to `assert.equal(entries.length, 70);` and rename it to "an append of many lines goes up one entry per line and still concatenates exactly".

In the test "a ledger with a byte that is not UTF-8 fails with its offset; a character still being written is a note" (line 334), replace

```js
  assert.match(partial.stdout, /^note: sdd\/p1\/progress\.md: the appended bytes end inside a character; push again once the write finishes$/m);
```

with

```js
  assert.match(partial.stdout, /^note: sdd\/p1\/progress\.md: the last line has no newline yet; it is held until the next push$/m);
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `timeout 300 node --test plugins/dr-forge/tests/darkmem-sync/mirror.test.mjs`
Expected: FAIL — `lineProperties` is not exported.

- [ ] **Step 3: Write the implementation**

In `scripts/lib/darkmem-mirror.mjs`, add after `splitAtBlankLines`:

```js
// What a darkmem progress board reads from one ledger line without parsing
// markdown (darkmem store options spec §3). Only a `Task N:` line yields any.
export function lineProperties(line) {
  const head = /^Task (\d+): /.exec(line);
  if (!head) return {};
  const properties = { task: Number(head[1]) };
  const rest = line.slice(head[0].length);
  const state = /^complete \(/.test(rest) ? "done"
    : /^BLOCKED/.test(rest) ? "blocked"
    : /^fix round /.test(rest) ? "review"
    : /^implementer \S+ \(assigned/.test(rest) ? "wip"
    : null;
  if (state) properties.state = state;
  const commits = /\bcommits [0-9a-f]{4,40}\.\.([0-9a-f]{4,40})\b/.exec(rest);
  if (commits) properties.commit = commits[1];
  return properties;
}

// One entry per line of `text`, which holds complete lines only. A blank line
// joins the entry before it, or the next one when it leads, so no entry is
// blank unless the text is.
export function ledgerEntries(text) {
  const entries = [];
  let lead = "";
  for (const line of text.split(/(?<=\n)/)) {
    if (/^[ \t]*\r?\n$/.test(line)) {
      if (entries.length) entries.at(-1).body += line;
      else lead += line;
      continue;
    }
    entries.push({ body: lead + line, properties: lineProperties(line) });
    lead = "";
  }
  if (lead) entries.push({ body: lead, properties: {} });
  return entries;
}
```

In `scripts/lib/darkmem-push.mjs`, add `ledgerEntries` to the import list from `./darkmem-mirror.mjs`. In `pushLedger`, replace the loop head and the body down to `const pieces = splitAtLimit(appended);` —

```js
  sending: while (buffer.length > record.offset) {
    const rest = buffer.subarray(record.offset);
    const appended = decodeUtf8(rest);
    if (appended === null) {
      const fault = utf8Fault(rest);
      if (fault.partial) report.notes.push(`${label}: the appended bytes end inside a character; push again once the write finishes`);
      else report.failures.push(`${label}: byte ${record.offset + fault.offset} is not UTF-8 text; not pushed`);
      return;
    }
    const properties = propertiesFor(roots, slug, ledgerPlanPath(buffer.toString("utf8")));
    const pieces = splitAtLimit(appended);
```

— with:

```js
  sending: while (buffer.length > record.offset) {
    const rest = buffer.subarray(record.offset);
    const fault = utf8Fault(rest);
    if (fault && !fault.partial) {
      report.failures.push(`${label}: byte ${record.offset + fault.offset} is not UTF-8 text; not pushed`);
      return;
    }
    // Only complete lines go up, so the offset advances past whole lines; a
    // character cut short can only follow the last newline.
    const end = rest.lastIndexOf(0x0a) + 1;
    if (end === 0) {
      report.notes.push(`${label}: the last line has no newline yet; it is held until the next push`);
      return;
    }
    const appended = decodeUtf8(rest.subarray(0, end));
    const properties = propertiesFor(roots, slug, ledgerPlanPath(buffer.toString("utf8")));
    const pieces = ledgerEntries(appended).flatMap(entry => splitAtLimit(entry.body).map(body => (
      Object.keys(entry.properties).length ? { kind: "ledger", body, properties: entry.properties } : { kind: "ledger", body }
    )));
```

In the same loop, replace `entries: group.map(body => ({ kind: "ledger", body })),` with `entries: group,` and replace

```js
      const offset = record.offset + Buffer.byteLength(group.join(""), "utf8");
```

with

```js
      const offset = record.offset + Buffer.byteLength(group.map(entry => entry.body).join(""), "utf8");
```

Remove `splitAtLimit` from the import list only if nothing else in the file uses it (it is still used here, so keep it).

- [ ] **Step 4: Run the tests to verify they pass**

Run: `timeout 900 bash plugins/dr-forge/tests/darkmem-sync.test.sh`
Expected: PASS, every file. The reconciliation tests (lost answers, 409s) pass unchanged: their bodies are whole lines and their offsets count bytes sent.

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-forge/scripts/lib/darkmem-mirror.mjs plugins/dr-forge/scripts/lib/darkmem-push.mjs plugins/dr-forge/tests/darkmem-sync/mirror.test.mjs plugins/dr-forge/tests/darkmem-sync/push.test.mjs
git commit -m "feat(dr-forge): send ledger lines with properties"
```

### Task 8: Add the roots library

**Files:**
- Create: `scripts/lib/roots.sh`
- Create: `tests/fixtures/darkmem-stores.sh`
- Test: `tests/roots.test.sh`

**Interfaces:**
- Consumes: C2 (`--mode`)
- Produces: C7, C8

**Items:** 2

**Implementer:** dr-superpowers:impl-sonnet-medium
**Evaluation:** files 1 - spec 0 - coupling 2 - risk 1 = 4

- [ ] **Step 1: Write the fixture and the failing test**

Create `tests/fixtures/darkmem-stores.sh`:

```bash
# Sourced by shell suites: a HOME whose dr-forge config maps a repository to
# darkmem with each family applied as the suite asks.

# stores_home HOME REPO PROJECT DOCS PROGRESS — map REPO's primary checkout to
# PROJECT, record documents DOCS and progress PROGRESS (local or darkmem) as
# applied, create the mirror's directories, and print the mirror's path.
stores_home() {
  local home=$1 project=$3 common top dir
  common=$(git -C "$2" rev-parse --path-format=absolute --git-common-dir)
  top=$(git -C "$(dirname "$common")" rev-parse --show-toplevel)
  dir="$home/.dr-forge"
  mkdir -p "$dir/mirror/$project/superpowers" "$dir/mirror/$project/work/sdd" "$dir/mirror/$project/work/handoff"
  printf '{"darkmem":{"url":"http://127.0.0.1:9","repos":{"%s":{"project":"%s"}}}}\n' "$top" "$project" > "$dir/config.json"
  printf '{"%s":{"documents":"%s","progress":"%s"}}\n' "$top" "$4" "$5" > "$dir/stores.json"
  printf '%s\n' "$dir/mirror/$project"
}
```

Create `tests/roots.test.sh`:

```bash
#!/usr/bin/env bash
# lib/roots.sh: each family's root follows its applied store, from the primary
# checkout and from a linked worktree, and names round-trip in all four
# combinations, including a checkout and a project both named superpowers.
set -uo pipefail
unset CLAUDE_CONFIG_DIR DR_FORGE_DOCUMENT_STORE DR_FORGE_PROGRESS_SOURCE

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/../scripts/lib/roots.sh"
. "$HERE/fixtures/darkmem-stores.sh"

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
mkdir -p "$HOME"
export GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid \
  GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
REPO="$TMP/superpowers"
git init -q -b main "$REPO"
git -C "$REPO" commit -q --allow-empty -m init
TOP=$(git -C "$REPO" rev-parse --show-toplevel)
git -C "$REPO" worktree add -q -b wt "$TMP/wt"
WT=$(git -C "$TMP/wt" rev-parse --show-toplevel)

# --- no config: both families local ---
check "no config: docs root" "$(cd "$REPO" && forge_docs_root)" "$TOP/docs/forge"
check "no config: stores" "$(cd "$REPO" && forge_docs_store) $(cd "$REPO" && forge_progress_store)" "local local"
check "no config: a worktree's ledger dir" "$(cd "$WT" && forge_ledger_dir p1)" "$WT/.forge/sdd/p1"
check "no config: latest.md from a worktree" "$(cd "$WT" && forge_latest_file)" "$TOP/.forge/handoff/latest.md"
check "no config: a DIR argument" "$(forge_docs_root "$WT")" "$WT/docs/forge"
check "outside git: local under the directory" "$(cd "$TMP" && forge_docs_root)" "$TMP/docs/forge"

# --- the four applied combinations, from the primary checkout and a worktree ---
for docs in local darkmem; do
  for progress in local darkmem; do
    MIRROR=$(stores_home "$HOME" "$REPO" superpowers "$docs" "$progress")
    for where in "$TOP" "$WT"; do
      label="$docs/$progress from $(basename "$where")"
      if [ "$docs" = darkmem ]; then want_docs="$MIRROR/superpowers"; else want_docs="$where/docs/forge"; fi
      if [ "$progress" = darkmem ]; then
        want_ledger="$MIRROR/work/sdd/p1" want_latest="$MIRROR/work/handoff/latest.md"
      else
        want_ledger="$where/.forge/sdd/p1" want_latest="$TOP/.forge/handoff/latest.md"
      fi
      check "$label: stores" "$(cd "$where" && forge_docs_store) $(cd "$where" && forge_progress_store)" "$docs $progress"
      check "$label: docs root" "$(cd "$where" && forge_docs_root)" "$want_docs"
      check "$label: ledger dir" "$(cd "$where" && forge_ledger_dir p1)" "$want_ledger"
      check "$label: latest.md" "$(cd "$where" && forge_latest_file)" "$want_latest"
      check "$label: the workspace stays local" "$(cd "$where" && forge_workspace p1)" "$where/.forge/sdd/p1"
      check "$label: a document name" "$(cd "$where" && forge_resolve docs/forge/plans/p1.md)" "$want_docs/plans/p1.md"
      check "$label: a pre-2.0 document name" "$(cd "$where" && forge_resolve docs/superpowers/plans/p1.md)" "$want_docs/plans/p1.md"
      check "$label: a working name" "$(cd "$where" && forge_resolve .forge/sdd/p1/brief.md)" "$where/.forge/sdd/p1/brief.md"
      check "$label: an absolute path stays" "$(cd "$where" && forge_resolve /x/y.md)" "/x/y.md"
      check "$label: a document round-trips" "$(cd "$where" && forge_name "$(forge_resolve docs/forge/plans/p1.md)")" "docs/forge/plans/p1.md"
      check "$label: a working file round-trips" "$(cd "$where" && forge_name "$where/.forge/x.md")" ".forge/x.md"
      check "$label: a name stays a name" "$(cd "$where" && forge_name ./docs/forge/specs/s.md)" "docs/forge/specs/s.md"
      check "$label: an outside path stays" "$(cd "$where" && forge_name /elsewhere/superpowers/a.md)" "/elsewhere/superpowers/a.md"
    done
  done
done

# --- ledger listings: every worktree's when local, the mirror's once when darkmem ---
mkdir -p "$REPO/.forge/sdd/a" "$WT/.forge/sdd/b"
printf 'x\n' > "$REPO/.forge/sdd/a/progress.md"
printf 'x\n' > "$WT/.forge/sdd/b/progress.md"
MIRROR=$(stores_home "$HOME" "$REPO" superpowers local local)
check "ledger files: local lists each worktree's" "$(cd "$WT" && forge_ledger_files | sort)" \
  "$(printf '%s\t%s\n%s\t%s' "$TOP/.forge/sdd/a/progress.md" "$TOP" "$WT/.forge/sdd/b/progress.md" "$WT" | sort)"
MIRROR=$(stores_home "$HOME" "$REPO" superpowers local darkmem)
mkdir -p "$MIRROR/work/sdd/c"
printf 'x\n' > "$MIRROR/work/sdd/c/progress.md"
check "ledger files: darkmem lists the mirror's once" "$(cd "$WT" && forge_ledger_files)" "$(printf '%s\tmirror' "$MIRROR/work/sdd/c/progress.md")"

# --- a pre-2.0 checkout keeps its names ---
MIRROR=$(stores_home "$HOME" "$REPO" superpowers local local)
mkdir -p "$WT/docs/superpowers/plans"
check "pre-2.0: the docs root" "$(cd "$WT" && forge_docs_root)" "$WT/docs/superpowers"
check "pre-2.0: the name" "$(cd "$WT" && forge_name "$WT/docs/superpowers/plans/p.md")" "docs/superpowers/plans/p.md"

# --- a ConfigError stops the script ---
printf '{"darkmem":{"url":"http://127.0.0.1:9","repos":{"%s":{"project":"superpowers","documentStore":"cloud"}}}}\n' "$TOP" > "$HOME/.dr-forge/config.json"
(cd "$REPO" && forge_docs_root > /dev/null 2> "$TMP/err")
check "config error: exit 2" "$?" "2"
check "config error: the message" "$(grep -c 'use local or darkmem' "$TMP/err")" "1"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `timeout 600 bash plugins/dr-forge/tests/roots.test.sh`
Expected: FAIL — `scripts/lib/roots.sh: No such file or directory`.

- [ ] **Step 3: Write the implementation**

Create `scripts/lib/roots.sh`:

```bash
# Sourced. Where a repository's two dr-forge families live (darkmem store
# options spec §2): documents (the docs directory) and progress (plan ledgers,
# their handoff.md, and latest.md), each in the checkout or in the darkmem
# mirror, as `darkmem-config.mjs --mode` resolves them. Defines functions only.
#
# Every helper takes an optional trailing DIR naming the checkout (default: the
# working directory). The resolution is cached per HOME and checkout in shell
# variables; a helper called inside $(…) cannot fill the caller's cache, so a
# script that calls helpers repeatedly calls forge_stores_init in its main
# shell first. A ConfigError exits the script with status 2.

. "$(dirname "${BASH_SOURCE[0]}")/forge-dir.sh"
. "$(dirname "${BASH_SOURCE[0]}")/native-path.sh"
_ROOTS_LIB_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

_FORGE_KEY="" _FORGE_TOP="" _FORGE_DOCS_STORE="" _FORGE_DOCS_ROOT=""
_FORGE_PROGRESS_STORE="" _FORGE_LEDGER_ROOT="" _FORGE_LATEST=""

# Node prints native paths; Git Bash compares them in git's C:/… form.
_forge_path() {
  if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1" 2>/dev/null || printf '%s\n' "$1"
  else printf '%s\n' "$1"; fi
}

# Both families local, computed without node: no node on PATH, or no git
# repository (then DIR stands in for the checkout).
_forge_local() { # DIR TOP
  local base=${2:-$1} primary=${2:-$1} common
  if [ -n "$2" ]; then
    if common=$(git -C "$2" rev-parse --path-format=absolute --git-common-dir 2>/dev/null); then
      primary=$(git -C "$(dirname "$common")" rev-parse --show-toplevel 2>/dev/null) || primary=$2
    fi
  fi
  _FORGE_DOCS_STORE=local
  _FORGE_DOCS_ROOT=$(forge_dir docs "$base")
  _FORGE_PROGRESS_STORE=local
  _FORGE_LEDGER_ROOT="$(forge_dir state "$base")/sdd"
  _FORGE_LATEST="$(forge_dir state "$primary")/handoff/latest.md"
}

forge_stores_init() { # [DIR]
  local dir=${1:-$PWD} top key out kind store root extra
  top=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null) || top=""
  key="${HOME:-}|${top:-nogit:$dir}"
  [ "$_FORGE_KEY" = "$key" ] && return 0
  _FORGE_TOP=$top
  if [ -z "$top" ] || ! command -v node >/dev/null 2>&1; then
    _forge_local "$dir" "$top"
    _FORGE_KEY=$key
    return 0
  fi
  if ! out=$(cd "$dir" && node "$(dr_native_path "$_ROOTS_LIB_DIR/darkmem-config.mjs")" --mode 2>&1); then
    printf '%s\n' "$out" >&2
    exit 2
  fi
  while IFS=$'\t' read -r kind store root extra; do
    case $kind in
      documents) _FORGE_DOCS_STORE=$store _FORGE_DOCS_ROOT=$(_forge_path "$root") ;;
      progress)
        _FORGE_PROGRESS_STORE=$store _FORGE_LEDGER_ROOT=$(_forge_path "$root")
        _FORGE_LATEST=$(_forge_path "$extra")
        ;;
    esac
  done <<<"$out"
  _FORGE_KEY=$key
}

forge_docs_root() { forge_stores_init "${1:-}"; printf '%s\n' "$_FORGE_DOCS_ROOT"; }
forge_docs_store() { forge_stores_init "${1:-}"; printf '%s\n' "$_FORGE_DOCS_STORE"; }
forge_progress_store() { forge_stores_init "${1:-}"; printf '%s\n' "$_FORGE_PROGRESS_STORE"; }
forge_ledger_root() { forge_stores_init "${1:-}"; printf '%s\n' "$_FORGE_LEDGER_ROOT"; }
forge_latest_file() { forge_stores_init "${1:-}"; printf '%s\n' "$_FORGE_LATEST"; }
forge_ledger_dir() { forge_stores_init "${2:-}"; printf '%s/%s\n' "$_FORGE_LEDGER_ROOT" "$1"; } # SLUG [DIR]

forge_workspace() { # SLUG [DIR]
  forge_stores_init "${2:-}"
  printf '%s/sdd/%s\n' "$(forge_dir state "${_FORGE_TOP:-${2:-$PWD}}")" "$1"
}

# forge_ledger_files [DIR] — "<ledger>\t<checkout>" for every worktree's
# ledgers when progress is local; "<ledger>\tmirror" for the mirror's when it
# is darkmem, listed once, since every worktree shares the mirror.
forge_ledger_files() {
  local wt f
  forge_stores_init "${1:-}"
  if [ "$_FORGE_PROGRESS_STORE" = darkmem ]; then
    for f in "$_FORGE_LEDGER_ROOT"/*/progress.md; do
      [ -f "$f" ] && printf '%s\tmirror\n' "$f"
    done
    return 0
  fi
  [ -n "$_FORGE_TOP" ] || return 0
  git -C "$_FORGE_TOP" worktree list --porcelain 2>/dev/null | tr -d '\r' | sed -n 's/^worktree //p' |
  while IFS= read -r wt; do
    for f in "$(forge_dir state "$wt")"/sdd/*/progress.md; do
      [ -f "$f" ] && printf '%s\t%s\n' "$f" "$wt"
    done
  done
  return 0
}

# forge_resolve NAME [DIR] — a document name (docs/forge/… or the pre-2.0
# docs/superpowers/…) under the docs root, any other relative name under the
# worktree, an absolute path unchanged.
forge_resolve() {
  local name=${1#./}
  forge_stores_init "${2:-}"
  case $name in
    /*|[A-Za-z]:/*|[A-Za-z]:\\*) printf '%s\n' "$1" ;;
    docs/forge|docs/superpowers) printf '%s\n' "$_FORGE_DOCS_ROOT" ;;
    docs/forge/*) printf '%s/%s\n' "$_FORGE_DOCS_ROOT" "${name#docs/forge/}" ;;
    docs/superpowers/*) printf '%s/%s\n' "$_FORGE_DOCS_ROOT" "${name#docs/superpowers/}" ;;
    *) printf '%s/%s\n' "${_FORGE_TOP:-${2:-$PWD}}" "$name" ;;
  esac
}

_forge_name_of() { # ABSOLUTE — its name when it lies under a root; status 1 otherwise
  local docs_name
  docs_name=$(forge_dir_rel docs "${_FORGE_TOP:-$PWD}")
  case $1 in
    "$_FORGE_DOCS_ROOT") printf '%s\n' "$docs_name"; return 0 ;;
    "$_FORGE_DOCS_ROOT"/*) printf '%s/%s\n' "$docs_name" "${1#"$_FORGE_DOCS_ROOT"/}"; return 0 ;;
  esac
  [ -n "$_FORGE_TOP" ] || return 1
  case $1 in "$_FORGE_TOP"/*) printf '%s\n' "${1#"$_FORGE_TOP"/}"; return 0 ;; esac
  return 1
}

# forge_name FILE [DIR] — the inverse of forge_resolve, computed from the roots.
# A path spelled through a symbolic link is retried in its physical form.
forge_name() {
  local file=${1//\\//} physical
  forge_stores_init "${2:-}"
  case $file in
    /*|[A-Za-z]:/*) ;;
    *) printf '%s\n' "${file#./}"; return 0 ;;
  esac
  _forge_name_of "$file" && return 0
  physical="$(cd "$(dirname "$file")" 2>/dev/null && pwd -P)/$(basename "$file")"
  [ "$physical" != "/$(basename "$file")" ] && [ "$physical" != "$file" ] && _forge_name_of "$physical" && return 0
  printf '%s\n' "$file"
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `timeout 600 bash plugins/dr-forge/tests/roots.test.sh`
Expected: `0 failed`.

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-forge/scripts/lib/roots.sh plugins/dr-forge/tests/fixtures/darkmem-stores.sh plugins/dr-forge/tests/roots.test.sh
git commit -m "feat(dr-forge): add the roots library"
```

### Task 9: Teach forge-path the new kinds

**Files:**
- Modify: `scripts/forge-path` (replace the whole file)
- Test: `tests/forge-dir.test.sh:14-15`, `:42-50`

**Interfaces:**
- Consumes: C7, C8
- Produces: C9

**Items:** 2

**Implementer:** dr-superpowers:impl-sonnet-medium
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 1 = 3

- [ ] **Step 1: Write the failing tests**

In `tests/forge-dir.test.sh`, directly after `trap 'rm -rf "$TMP"' EXIT` (line 15), add `export HOME="$TMP/home"; mkdir -p "$HOME"`, so the existing forge-path checks no longer read the host's `~/.dr-forge/`. Then insert before the final `printf '\n%d passed…`:

```bash
# --- forge-path: the families' roots and names ---
. "$HERE/fixtures/darkmem-stores.sh"
H=$HOME
git -C "$G" -c user.name=t -c user.email=t@example.com commit -q --allow-empty -m init
FP="$HERE/../scripts/forge-path"
check "forge-path: ledger, local" "$(cd "$G" && HOME=$H bash "$FP" ledger p1)" "$TOP/.superpowers/sdd/p1"
check "forge-path: latest, local" "$(cd "$G" && HOME=$H bash "$FP" latest)" "$TOP/.superpowers/handoff/latest.md"
check "forge-path: store, local" "$(cd "$G" && HOME=$H bash "$FP" store | tr '\n' '|')" "documents local|progress local|"
M=$(stores_home "$H" "$G" proj darkmem darkmem)
check "forge-path: docs, darkmem" "$(cd "$G" && HOME=$H bash "$FP" docs plans/p1.md)" "$M/superpowers/plans/p1.md"
check "forge-path: ledger, darkmem" "$(cd "$G" && HOME=$H bash "$FP" ledger p1)" "$M/work/sdd/p1"
check "forge-path: latest, darkmem" "$(cd "$G" && HOME=$H bash "$FP" latest)" "$M/work/handoff/latest.md"
check "forge-path: state stays local" "$(cd "$G" && HOME=$H bash "$FP" state)" "$TOP/.superpowers"
check "forge-path: store, darkmem" "$(cd "$G" && HOME=$H bash "$FP" store | tr '\n' '|')" "documents darkmem|progress darkmem|"
check "forge-path: name" "$(cd "$G" && HOME=$H bash "$FP" name "$M/superpowers/plans/p1.md")" "docs/forge/plans/p1.md"
(cd "$G" && HOME=$H bash "$FP" ledger > /dev/null 2>&1)
check "forge-path: ledger needs a slug" "$?" "2"
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `timeout 600 bash plugins/dr-forge/tests/forge-dir.test.sh`
Expected: FAIL on `forge-path: ledger, local` (usage error).

- [ ] **Step 3: Write the implementation**

Replace `scripts/forge-path` with:

```bash
#!/usr/bin/env bash
# forge-path state [RELATIVE] | docs [RELATIVE] | ledger SLUG | latest | store | name PATH
# Where this repository's dr-forge files live: the state directory (.forge/,
# or the pre-2.0 .superpowers/; always in the checkout), the docs root and a
# plan's ledger directory and latest.md (in the checkout or in the darkmem
# mirror, as documentStore and progressSource apply them), each family's
# applied store, or the repository-relative name of a path.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/lib/roots.sh"
usage() { echo "usage: forge-path state|docs [RELATIVE] | ledger SLUG | latest | store | name PATH" >&2; exit 2; }
[ $# -ge 1 ] || usage
forge_stores_init
case $1 in
  state)
    [ $# -le 2 ] || usage
    dir=$(forge_dir state "$(git rev-parse --show-toplevel 2>/dev/null || pwd)") || exit 2
    ;;
  docs) [ $# -le 2 ] || usage; dir=$(forge_docs_root) ;;
  ledger) [ $# -eq 2 ] || usage; forge_ledger_dir "$2"; exit 0 ;;
  latest) [ $# -eq 1 ] || usage; forge_latest_file; exit 0 ;;
  store) [ $# -eq 1 ] || usage; printf 'documents %s\nprogress %s\n' "$(forge_docs_store)" "$(forge_progress_store)"; exit 0 ;;
  name) [ $# -eq 2 ] || usage; forge_name "$2"; exit 0 ;;
  *) usage ;;
esac
if [ $# -eq 2 ]; then printf '%s/%s\n' "$dir" "$2"; else printf '%s\n' "$dir"; fi
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `timeout 600 bash plugins/dr-forge/tests/forge-dir.test.sh`
Expected: `0 failed`, the existing `forge-path` checks included.

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-forge/scripts/forge-path plugins/dr-forge/tests/forge-dir.test.sh
git commit -m "feat(dr-forge): add forge-path ledger, latest, name"
```

### Task 10: Resolve plan paths through the roots

**Files:**
- Modify: `scripts/lib/plan.sh:5` (source line), `:320-338` (`plan_ledger`), `:413-423` (`plan_amendments_file`), after `:443` (new functions)
- Test: `tests/plan-lib.test.sh`

**Interfaces:**
- Consumes: C7, C8
- Produces: C10 (`plan_locate`, `plan_require_same_project`)

**Items:** 2

**Implementer:** dr-superpowers:impl-sonnet-high
**Evaluation:** files 1 - spec 0 - coupling 2 - risk 2 = 5

- [ ] **Step 1: Write the failing tests**

In `tests/plan-lib.test.sh`, insert before the final summary `printf`:

```bash
# --- the plan functions follow the roots ---
. "$HERE/fixtures/darkmem-stores.sh"
SH="$TMP/stores-home"; mkdir -p "$SH"
SR="$TMP/stores-repo"
git init -q "$SR"
git -C "$SR" -c user.name=t -c user.email=t@example.com commit -q --allow-empty -m init
STOP=$(git -C "$SR" rev-parse --show-toplevel)
M=$(stores_home "$SH" "$SR" proj darkmem darkmem)
mkdir -p "$M/superpowers/plans" "$M/work/sdd/mp"
printf '# MP\n' > "$M/superpowers/plans/mp.md"
printf '# SDD ledger — plan: docs/forge/plans/mp.md\n' > "$M/work/sdd/mp/progress.md"
check "plan_ledger: a mirror plan finds its mirror ledger by name" \
  "$(cd "$SR" && HOME=$SH plan_ledger "$M/superpowers/plans/mp.md")" "$M/work/sdd/mp/progress.md"
printf '# SDD ledger — plan: %s\n' "$M/superpowers/plans/mp.md" > "$M/work/sdd/mp/progress.md"
check "plan_ledger: an absolute mirror path names it too" \
  "$(cd "$SR" && HOME=$SH plan_ledger "$M/superpowers/plans/mp.md")" "$M/work/sdd/mp/progress.md"
check "plan_locate: a document name finds the mirror's copy" \
  "$(cd "$SR" && HOME=$SH plan_locate docs/forge/plans/mp.md)" "$M/superpowers/plans/mp.md"
check "plan_locate: an existing file stays" "$(cd "$REPO" && plan_locate docs/demo.md)" "docs/demo.md"
check "plan_locate: a missing name stays" "$(cd "$SR" && HOME=$SH plan_locate docs/forge/plans/none.md)" "docs/forge/plans/none.md"
mkdir -p "$STOP/.forge/sdd/mp"
printf '## A1 — Task 1\n' > "$STOP/.forge/sdd/mp/amendments.md"
check "amendments_file: a mirror plan's workspace stays in the checkout" \
  "$(cd "$SR" && HOME=$SH plan_amendments_file "$M/superpowers/plans/mp.md")" "$STOP/.forge/sdd/mp/amendments.md"
(cd "$SR" && HOME=$SH plan_require_same_project "$M/superpowers/plans/mp.md" 2>/dev/null)
check "same project: a mirror plan while documents are in darkmem" "$?" "0"
(cd "$SR" && HOME=$SH plan_require_same_project "$REPO/docs/demo.md" 2>/dev/null)
check "same project: another checkout's plan is refused" "$?" "2"
M=$(stores_home "$SH" "$SR" proj local darkmem)
mkdir -p "$STOP/docs/forge/plans"
printf '# LP\n' > "$STOP/docs/forge/plans/lp.md"
mkdir -p "$M/work/sdd/lp"
printf '# SDD ledger — plan: docs/forge/plans/lp.md\n' > "$M/work/sdd/lp/progress.md"
check "plan_ledger: a checkout plan finds its mirror ledger" \
  "$(cd "$SR" && HOME=$SH plan_ledger "$STOP/docs/forge/plans/lp.md")" "$M/work/sdd/lp/progress.md"
(cd "$SR" && HOME=$SH plan_require_same_project "$M/superpowers/plans/mp.md" 2>/dev/null)
check "same project: a mirror plan while documents are local is refused" "$?" "2"
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `timeout 600 bash plugins/dr-forge/tests/plan-lib.test.sh`
Expected: FAIL on `plan_ledger: a mirror plan finds its mirror ledger by name` (empty output).

- [ ] **Step 3: Write the implementation**

In `scripts/lib/plan.sh`, replace line 5

```bash
. "$(dirname "${BASH_SOURCE[0]}")/forge-dir.sh"
```

with

```bash
. "$(dirname "${BASH_SOURCE[0]}")/roots.sh"
```

Add before `plan_ledger`:

```bash
# _plan_ctx PLAN — the directory whose checkout a plan belongs to: its own
# directory inside a git repository, else the working directory (a plan in
# the darkmem mirror belongs to the checkout it is worked from).
_plan_ctx() {
  if git -C "$(dirname "$1")" rev-parse --show-toplevel >/dev/null 2>&1; then dirname "$1"; else printf '%s\n' "$PWD"; fi
}

# plan_locate PLAN — PLAN when it is a file; otherwise the file its name
# resolves to, so docs/forge/plans/x.md finds the mirror's copy while
# documents live in darkmem; otherwise PLAN, for the caller's own message.
plan_locate() {
  local found
  if [ -f "$1" ]; then printf '%s\n' "$1"; return 0; fi
  found=$(forge_resolve "$1")
  if [ -f "$found" ]; then printf '%s\n' "$found"; else printf '%s\n' "$1"; fi
}
```

Replace `plan_ledger` (its comment and body) with:

```bash
# plan_ledger PLAN — the plan's ledger file when it exists and its identity line
# names PLAN; nothing otherwise. A stale ledger under the same slug is ignored.
# Plan and identity are compared as names, so a ledger in darkmem can name a
# plan in the checkout and the reverse.
plan_ledger() {
  local ctx want file named
  ctx=$(_plan_ctx "$1")
  want=$(forge_name "$1" "$ctx")
  file="$(forge_ledger_dir "$(basename "$1" .md)" "$ctx")/progress.md"
  [ -f "$file" ] || return 0
  named=$(ledger_plan "$file")
  [ -n "$named" ] || return 0
  if command -v cygpath >/dev/null 2>&1; then
    named=$(cygpath -m "$named" 2>/dev/null || printf '%s' "$named")
  fi
  [ "$(forge_name "$named" "$ctx")" != "$want" ] || printf '%s\n' "$file"
  return 0
}
```

Replace `plan_amendments_file` (its comment and body) with:

```bash
# plan_amendments_file PLAN — <workspace>/amendments.md when PLAN belongs to a
# git checkout and that file is non-empty; otherwise nothing. Computed, not
# created: readers never bring the workspace into being.
plan_amendments_file() {
  local ctx file
  ctx=$(_plan_ctx "$1")
  git -C "$ctx" rev-parse --show-toplevel >/dev/null 2>&1 || return 0
  file="$(forge_workspace "$(basename "$1" .md)" "$ctx")/amendments.md"
  [ -s "$file" ] && printf '%s\n' "$file"
  return 0
}
```

After `plan_require_same_repo`, add:

```bash
# plan_require_same_project FILE — return when FILE belongs to the working
# directory's checkout: inside its top level, or under the darkmem mirror's
# docs root while documents are applied darkmem. Otherwise name both on stderr
# and exit 2. Scripts find the repository from the working directory, but the
# plan functions resolve from the plan's location, so a plan in another
# checkout would split one plan's state across two. A linked worktree and its
# primary checkout have different top levels, so a worktree session given the
# primary checkout's plan path is refused as well.
plan_require_same_project() {
  local me cwd_top plan_top dir docs
  me=$(basename "$0")
  cwd_top=$(git rev-parse --show-toplevel 2>/dev/null) \
    || { printf '%s: not inside a git repository\n' "$me" >&2; exit 2; }
  plan_top=$(git -C "$(dirname "$1")" rev-parse --show-toplevel 2>/dev/null) || plan_top=""
  [ "$plan_top" != "$cwd_top" ] || return 0
  forge_stores_init
  if [ "$_FORGE_DOCS_STORE" = darkmem ]; then
    dir=$(cd "$(dirname "$1")" 2>/dev/null && pwd -P) || dir=""
    docs=$(cd "$_FORGE_DOCS_ROOT" 2>/dev/null && pwd -P) || docs=""
    if [ -n "$dir" ] && [ -n "$docs" ]; then
      case "$dir/" in "$docs"/*) return 0 ;; esac
    fi
  fi
  printf "%s: %s is in %s, but the working directory is in %s; run from inside the plan's worktree\n" \
    "$me" "$1" "${plan_top:-no git repository}" "$cwd_top" >&2
  exit 2
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `timeout 600 bash plugins/dr-forge/tests/plan-lib.test.sh`, then `timeout 600 bash plugins/dr-forge/tests/review-route.test.sh`, `timeout 600 bash plugins/dr-forge/tests/plan-lint.test.sh`, `timeout 600 bash plugins/dr-forge/tests/task-state.test.sh`
Expected: `0 failed` in each (they read `plan_ledger` and `plan_amendments_file`).

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-forge/scripts/lib/plan.sh plugins/dr-forge/tests/plan-lib.test.sh
git commit -m "feat(dr-forge): resolve plan paths through roots"
```

### Task 11: Locate plan arguments and check the same project

**Files:**
- Modify: `scripts/task-brief:30`, `scripts/review-route:37`, `scripts/plan-lint:23`, `scripts/plan-amend:18,23`, `scripts/review-package:20,24`, `scripts/sdd-workspace:30,32`, `scripts/next-step:128,130`, `scripts/wave:33`, `scripts/plan-revise:276`
- Modify: `scripts/lib/plan.sh` (delete `plan_require_same_repo`)
- Modify: `skills/finishing-a-development-branch/SKILL.md:388`
- Test: `tests/working-directory.test.sh`

**Interfaces:**
- Consumes: C10 (`plan_locate`, `plan_require_same_project`)
- Produces: none

**Items:** 2

**Implementer:** dr-superpowers:impl-sonnet-medium
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 2 = 4

- [ ] **Step 1: Write the failing tests**

In `tests/working-directory.test.sh`, insert before the final summary `printf`:

```bash
# --- a plan kept in darkmem: found by name, accepted as this project's ---
. "$HERE/fixtures/darkmem-stores.sh"
SH="$TMP/stores-home"; mkdir -p "$SH"
SR="$TMP/stores-repo"
git init -q "$SR"
git -C "$SR" -c user.name=t -c user.email=t@example.com commit -q --allow-empty -m init
STOP=$(git -C "$SR" rev-parse --show-toplevel)
M=$(stores_home "$SH" "$SR" proj darkmem darkmem)
mkdir -p "$M/superpowers/plans"
printf '# Mirror plan\n\n### Task 1: One\n' > "$M/superpowers/plans/mp.md"
check "sdd-workspace: a mirror plan by name gets a local workspace" \
  "$(cd "$SR" && HOME=$SH bash "$P/scripts/sdd-workspace" docs/forge/plans/mp.md)" "$STOP/.forge/sdd/mp"
check "sdd-workspace: a mirror plan by path" \
  "$(cd "$SR" && HOME=$SH bash "$P/scripts/sdd-workspace" "$M/superpowers/plans/mp.md")" "$STOP/.forge/sdd/mp"
```

`$P` is the plugin root the suite already defines (`P="$HERE/.."`, line 102).

- [ ] **Step 2: Run the test to verify it fails**

Run: `timeout 600 bash plugins/dr-forge/tests/working-directory.test.sh`
Expected: FAIL — `no such plan file: docs/forge/plans/mp.md`.

- [ ] **Step 3: Write the implementation**

In each script below, change the line that assigns the plan from its argument so it goes through `plan_locate` (every one of these scripts already sources `lib/plan.sh`):

| File | Old | New |
|---|---|---|
| `scripts/task-brief:30` | `plan=$1` | `plan=$(plan_locate "$1")` |
| `scripts/review-route:37` | `plan=$1; shift` | `plan=$(plan_locate "$1"); shift` |
| `scripts/plan-lint:23` | `plan=$1; shift` | `plan=$(plan_locate "$1"); shift` |
| `scripts/plan-amend:18` | `plan=$1 block=$2` | `plan=$(plan_locate "$1") block=$2` |
| `scripts/review-package:20` | `plan=$1` | `plan=$(plan_locate "$1")` |
| `scripts/sdd-workspace:30` | `plan=$1` | `plan=$(plan_locate "$1")` |
| `scripts/next-step:128` | `  plan=$1` | `  plan=$(plan_locate "$1")` |
| `scripts/wave:33` | `cmd=$1 plan=$2` | `cmd=$1 plan=$(plan_locate "$2")` |
| `scripts/plan-revise:276` | `plan=$1` | `plan=$(plan_locate "$1")` |

Before editing `scripts/wave`, confirm it sources `lib/plan.sh` (`grep -n 'lib/plan.sh' plugins/dr-forge/scripts/wave`); if it does not, add `. "$HERE/lib/plan.sh"` beside its other library lines, using the variable it already uses for its own directory.

Rename every call of `plan_require_same_repo` to `plan_require_same_project`: `scripts/plan-amend:23`, `scripts/review-package:24`, `scripts/sdd-workspace:32`, `scripts/next-step:130`. Then delete `plan_require_same_repo` and its comment from `scripts/lib/plan.sh`. After the skill edit below, `grep -rn plan_require_same_repo plugins/dr-forge` prints nothing.

In `scripts/sdd-workspace`, the header comment's line 4 `# and the progress ledger. Print the plan directory's absolute path.` becomes `# and, while progress is local, the progress ledger. Print the plan`, followed by a new line `# directory's absolute path.`.

In `skills/finishing-a-development-branch/SKILL.md:388`, replace `` (`plan_require_same_repo` treats a linked worktree and its primary `` with `` (`plan_require_same_project` treats a linked worktree and its primary ``.

- [ ] **Step 4: Run the tests to verify they pass**

Run each, bounded: `working-directory`, `plan-amend`, `next-step`, `wave`, `plan-revise`, `plan-lint`, `review-route`, `inline-mode`, `forge-state`, `project-status` (`timeout 600 bash plugins/dr-forge/tests/<name>.test.sh`)
Expected: `0 failed` in each; `grep -rn plan_require_same_repo plugins/dr-forge` prints nothing.

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-forge/scripts plugins/dr-forge/skills/finishing-a-development-branch/SKILL.md plugins/dr-forge/tests/working-directory.test.sh
git commit -m "feat(dr-forge): locate plans kept in darkmem"
```

### Task 12: Read registers and the roadmap from the docs root

**Files:**
- Modify: `scripts/lib/register.sh:3,93`, `scripts/lib/roadmap.sh:18,71,81,84,98,113,118`, `scripts/roadmap:59-60,98,123,125,137,167,288,294,297`, `scripts/register:44,58,116`
- Test: `tests/register.test.sh`, `tests/roadmap.test.sh`

**Interfaces:**
- Consumes: C7, C8
- Produces: none

**Items:** 2

**Implementer:** dr-superpowers:impl-sonnet-medium
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 2 = 4

- [ ] **Step 1: Write the failing tests**

In `tests/register.test.sh`, insert before the final summary `printf`:

```bash
# --- documents kept in darkmem: registers are listed and checked in the mirror ---
. "$HERE/fixtures/darkmem-stores.sh"
SH="$TMP/stores-home"; mkdir -p "$SH"
SR="$TMP/stores-repo"; git init -q "$SR"
M=$(stores_home "$SH" "$SR" proj darkmem local)
mkdir -p "$M/superpowers/registers" "$M/superpowers/specs"
printf '# A\n' > "$M/superpowers/specs/a-design.md"
printf '# B\n' > "$M/superpowers/specs/b-design.md"
reg "$M/superpowers/registers/r.md" '| 1 | One | - | - | planned | - |'
check "register_files: the mirror's registers" "$(HOME=$SH register_files "$SR")" "$M/superpowers/registers/r.md"
out=$(cd "$SR" && HOME=$SH bash "$HERE/../scripts/register" check "$M/superpowers/registers/r.md" 2>&1)
check "register check: Covers names resolve in the mirror" "$(tail -n 1 <<<"$out")" "register: 0 errors"
out=$(cd "$SR" && HOME=$SH bash "$HERE/../scripts/register" open --spec docs/superpowers/specs/a-design.md 2>&1)
check "register open: the register is named, not pathed" "$out" "docs/forge/registers/r.md: #1 One — planned, assigned -"
```

In `tests/roadmap.test.sh`, insert before the final summary `printf`:

```bash
# --- documents kept in darkmem: the roadmap and its registers are read in the mirror ---
. "$HERE/fixtures/darkmem-stores.sh"
SH="$TMP/stores-home"; mkdir -p "$SH"
SR="$TMP/stores-repo"; git init -q -b main "$SR"
M=$(stores_home "$SH" "$SR" proj darkmem local)
mkdir -p "$M/superpowers/registers"
printf '# Roadmap\n' > "$M/superpowers/roadmap.md"
register "$M/superpowers/registers/m1.md" "docs/forge/specs/x.md" \
  '| 1 | A | - | - | done | - |' '| 2 | B | - | - | open | - |'
check "roadmap_file: the mirror's roadmap" "$(HOME=$SH roadmap_file "$SR")" "$M/superpowers/roadmap.md"
check "roadmap_epic_counts: a register name resolves in the mirror" \
  "$(HOME=$SH roadmap_epic_counts "$SR" docs/forge/registers/m1.md)" "1 2"
check "roadmap_unresolved: rows named by register name" \
  "$(HOME=$SH roadmap_unresolved "$SR" docs/forge/registers/m1.md | cut -f1,2)" "$(printf 'docs/forge/registers/m1.md\t2')"
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `timeout 600 bash plugins/dr-forge/tests/register.test.sh`, then `timeout 600 bash plugins/dr-forge/tests/roadmap.test.sh`
Expected: FAIL on `register_files: the mirror's registers` and `roadmap_file: the mirror's roadmap` (empty output).

- [ ] **Step 3: Write the implementation**

`scripts/lib/register.sh`: line 3 `. "$(dirname "${BASH_SOURCE[0]}")/forge-dir.sh"` becomes `. "$(dirname "${BASH_SOURCE[0]}")/roots.sh"`; in `register_files`, `dir="$(forge_dir docs "$1")/registers"` becomes `dir="$(forge_docs_root "$1")/registers"`.

`scripts/lib/roadmap.sh` (line numbers are the original file's; line 98 becomes two lines, so edit from line 118 upward or find each by its old text):

| Line | Old | New |
|---|---|---|
| 18 | `f="$(forge_dir docs "$1")/roadmap.md"` | `f="$(forge_docs_root "$1")/roadmap.md"` |
| 71 | `path=$root/$reg` | `path=$(forge_resolve "$reg" "$root")` |
| 81 | `[ -f "$root/$a" ] \|\| continue` | `[ -f "$(forge_resolve "$a" "$root")" ] \|\| continue` |
| 84 | `rel=${f#"$root"/}` | `rel=$(forge_name "$f" "$root")` |
| 98 | `local path="$1/$2"` | `local path` and, on the next line, `path=$(forge_resolve "$2" "$1")` |
| 113 | `… "$(forge_dir_rel docs "$root")"` | `… "$(forge_name "$(forge_docs_root "$root")" "$root")"` |
| 118 | `open_list=$(register_open "$root/$reg" 2>/dev/null \| awk …` | `open_list=$(register_open "$(forge_resolve "$reg" "$root")" 2>/dev/null \| awk …` |

`scripts/roadmap`: after line 59 (`root=$(cd "$root" 2>/dev/null && pwd) || …`) add `forge_stores_init "$root"`; line 60 becomes `FILE="$(forge_docs_root "$root")/roadmap.md"`. Then replace each `"$root/$spec"` (line 98) with `"$(forge_resolve "$spec" "$root")"`, and each `"$root/$reg"` (lines 123, 125, 137, 167, 288, 294, 297) with `"$(forge_resolve "$reg" "$root")"`. After the edit `grep -n '\$root/\$' plugins/dr-forge/scripts/roadmap` prints nothing.

`scripts/register`: in `cmd_check`, line 44 becomes

```bash
  root=$(git -C "$(dirname "$file")" rev-parse --show-toplevel 2>/dev/null || git rev-parse --show-toplevel 2>/dev/null || pwd)
```

line 58 `[ -f "$root/$line" ] && continue` becomes `[ -f "$(forge_resolve "$line" "$root")" ] && continue`; in `cmd_open`, line 116 `[ -z "$root" ] || rel=${f#"$root"/}` becomes `[ -z "$root" ] || rel=$(forge_name "$f" "$root")`.

- [ ] **Step 4: Run the tests to verify they pass**

Run each, bounded: `register`, `roadmap`, `next-step`, `repo-audit`, `project-status`, `plan-lint` (`timeout 600 bash plugins/dr-forge/tests/<name>.test.sh`)
Expected: `0 failed` in each.

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-forge/scripts/lib/register.sh plugins/dr-forge/scripts/lib/roadmap.sh plugins/dr-forge/scripts/roadmap plugins/dr-forge/scripts/register plugins/dr-forge/tests/register.test.sh plugins/dr-forge/tests/roadmap.test.sh
git commit -m "feat(dr-forge): read registers from the docs root"
```

### Task 13: Read ledgers and latest.md through the roots in hooks

**Files:**
- Modify: `scripts/lib/snapshot.sh:11,18-44`, `scripts/session-start.sh:11,82`, `scripts/turn-end.sh:32-33`, `scripts/lib/auto-run.sh:9,25,135-140,188`
- Test: `tests/snapshot.test.sh`, `tests/turn-end.test.sh`

**Interfaces:**
- Consumes: C7, C8
- Produces: none

**Items:** 2

**Implementer:** dr-superpowers:impl-sonnet-medium
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 2 = 4

- [ ] **Step 1: Write the failing tests**

In `tests/snapshot.test.sh`, insert before the final summary `printf`:

```bash
# --- progress kept in darkmem: the mirror's ledgers and latest.md ---
. "$HERE/fixtures/darkmem-stores.sh"
SH="$TMP/stores-home"; mkdir -p "$SH"
M=$(stores_home "$SH" "$REPO" proj local darkmem)
mkdir -p "$M/work/sdd/mp"
printf '# SDD ledger — plan: docs/forge/plans/mp.md\nTask 1: complete (commits a..b, review clean)\n' > "$M/work/sdd/mp/progress.md"
printf '# Handoff\n\n## Next session\n\n**Next:** the mirror note\n' > "$M/work/handoff/latest.md"
out=$(HOME=$SH snapshot_ledgers "$REPO")
has "darkmem progress: the mirror's ledger" "$out" "### Ledger \`$M/work/sdd/mp/progress.md\` (plan \`docs/forge/plans/mp.md\`)"
check "darkmem progress: listed once" "$(grep -c '^### Ledger' <<<"$out")" "1"
has "darkmem progress: the mirror's latest.md" "$(HOME=$SH snapshot_latest "$REPO")" "**Next:** the mirror note"
```

In `tests/turn-end.test.sh`, insert before the final summary `printf`:

```bash
# --- progress kept in darkmem: the mirror's ledgers are the ones read ---
. "$HERE/fixtures/darkmem-stores.sh"
M=$(stores_home "$HOME" "$REPO" proj local darkmem)
mkdir -p "$M/work/sdd/2026-10-10-mirror"
sleep 1; prompt s-2; sleep 1
printf '# SDD ledger — plan: docs/forge/plans/2026-10-10-mirror.md\nTask 1: complete (commits a..b, review clean)\n' > "$M/work/sdd/2026-10-10-mirror/progress.md"
out=$(stop s-2 'Task 1 is done.')
check "darkmem progress: a mirror ledger blocks a bare summary" "$(decision "$out")" "block"
check "darkmem progress: names the plan" \
  "$(jq -r .reason <<<"$out" | grep -c 'scripts/next-step docs/forge/plans/2026-10-10-mirror.md')" "1"
rm -f "$HOME/.dr-forge/config.json" "$HOME/.dr-forge/stores.json"
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `timeout 600 bash plugins/dr-forge/tests/snapshot.test.sh`, then `timeout 600 bash plugins/dr-forge/tests/turn-end.test.sh`
Expected: FAIL on `darkmem progress: the mirror's ledger` and `darkmem progress: a mirror ledger blocks a bare summary`.

- [ ] **Step 3: Write the implementation**

`scripts/lib/snapshot.sh`: delete line 11 (`. "$(dirname "${BASH_SOURCE[0]}")/forge-dir.sh"`; `plan.sh` now sources `roots.sh`). Replace `snapshot_latest` and `snapshot_ledgers` with:

```bash
snapshot_latest() { # CWD — the Next session block of this repository's latest.md
  local latest
  latest=$(forge_latest_file "$1") || return 0
  [ -f "$latest" ] || return 0
  echo "### From \`$latest\`"
  tr -d '\r' < "$latest" | awk '/^## Next session/ { f = 1; next } f && /^## / { exit } f'
}

snapshot_ledgers() { # CWD — every ledger forge_ledger_files lists: last 8 lines, last 10 rulings
  local ledger _where plan_rel rulings
  forge_ledger_files "$1" | while IFS=$'\t' read -r ledger _where; do
    plan_rel=$(ledger_plan "$ledger")
    echo "### Ledger \`$ledger\` (plan \`${plan_rel:-unknown}\`)"
    echo "Last lines:"
    tr -d '\r' < "$ledger" | grep -v '^[[:space:]]*$' | tail -n 8 | sed 's/^/    /'
    rulings=$(tr -d '\r' < "$ledger" | grep 'Ruling:' | tail -n 10)
    if [ -n "$rulings" ]; then
      echo "Rulings (most recent 10):"
      printf '%s\n' "$rulings" | sed 's/^/    /'
    fi
  done
}
```

`scripts/session-start.sh`: line 11 `. "${SCRIPT_DIR}/lib/forge-dir.sh"` becomes `. "${SCRIPT_DIR}/lib/roots.sh"`; line 82 becomes

```bash
if [ -n "$roadmap_root" ] && [ -f "$(forge_docs_root "$roadmap_root")/roadmap.md" ]; then
```

`scripts/turn-end.sh`: replace lines 32-33

```bash
. "${SCRIPT_DIR}/lib/forge-dir.sh"
sdd="$(forge_dir state "$root")/sdd"
```

with

```bash
. "${SCRIPT_DIR}/lib/roots.sh"
# In a subshell, so a malformed config costs only this check, never the hook.
sdd=$(forge_ledger_root "$root") || sdd=""
```

`scripts/lib/auto-run.sh`: line 9 `. "$(dirname "${BASH_SOURCE[0]}")/forge-dir.sh"` becomes `. "$(dirname "${BASH_SOURCE[0]}")/roots.sh"`. In `ar_start`, add `regfile` to the `local` list on line 25. Replace lines 135-140

```bash
    register="$(forge_dir_rel docs "$top")/registers/$(date +%Y-%m-%d)-$slug-auto.md"
    if [ ! -f "$top/$register" ]; then
      mkdir -p "$(dirname "$top/$register")" || return 1
      printf '# Auto run: %s\n\n**Source:** items the auto run for `%s` deferred\n**Covers:** %s\n\n| # | Item | Assigned | Acceptance | State | Note |\n|---|---|---|---|---|---|\n' \
        "$slug" "$spec" "$spec" > "$top/$register" || return 1
    fi
```

with

```bash
    register="$(forge_name "$(forge_docs_root "$top")" "$top")/registers/$(date +%Y-%m-%d)-$slug-auto.md"
    regfile=$(forge_resolve "$register" "$top")
    if [ ! -f "$regfile" ]; then
      mkdir -p "$(dirname "$regfile")" || return 1
      printf '# Auto run: %s\n\n**Source:** items the auto run for `%s` deferred\n**Covers:** %s\n\n| # | Item | Assigned | Acceptance | State | Note |\n|---|---|---|---|---|---|\n' \
        "$slug" "$spec" "$spec" > "$regfile" || return 1
    fi
```

and in `ar_clear` (line 188) replace `latest="$(forge_dir state "$primary")/handoff/latest.md"` with `latest=$(forge_latest_file "$primary")`.

- [ ] **Step 4: Run the tests to verify they pass**

Run each, bounded: `snapshot`, `turn-end`, `auto-run`, `auto-run-skills`, `hook`, `in-flight` (`timeout 600 bash plugins/dr-forge/tests/<name>.test.sh`)
Expected: `0 failed` in each.

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-forge/scripts/lib/snapshot.sh plugins/dr-forge/scripts/session-start.sh plugins/dr-forge/scripts/turn-end.sh plugins/dr-forge/scripts/lib/auto-run.sh plugins/dr-forge/tests/snapshot.test.sh plugins/dr-forge/tests/turn-end.test.sh
git commit -m "feat(dr-forge): read ledgers through roots in hooks"
```

### Task 14: Route next-step through the roots

**Files:**
- Modify: `scripts/next-step:88-93` (`plan_finished`), `:122-157`, `:171`, `:181-186`, `:239`, `:245`, `:273-274`, `:288-289`, `:319`, `:322`, `:423`
- Test: `tests/next-step.test.sh`

**Interfaces:**
- Consumes: C7, C8, C10
- Produces: none

**Items:** 2

**Implementer:** dr-superpowers:impl-sonnet-medium
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 2 = 4

- [ ] **Step 1: Write the failing tests**

In `tests/next-step.test.sh`, insert before the final summary `printf`:

```bash
# --- documents and progress kept in darkmem ---
. "$HERE/fixtures/darkmem-stores.sh"
SH="$TMP/stores-home"; mkdir -p "$SH"
SR="$TMP/stores-repo"
git init -q "$SR"
git -C "$SR" commit -q --allow-empty -m init
M=$(stores_home "$SH" "$SR" proj darkmem darkmem)
mkdir -p "$M/superpowers/plans" "$M/work/sdd/2026-02-02-mirror"
write_plan "$M/superpowers/plans/2026-02-02-mirror.md" '**Execution:** subagent — `claude --model sonnet --effort high` — demo' ""
printf '# SDD ledger — plan: docs/forge/plans/2026-02-02-mirror.md\nTask 1: complete (commits a..b, review clean)\n' \
  > "$M/work/sdd/2026-02-02-mirror/progress.md"
out=$(cd "$SR" && HOME=$SH bash "$SCRIPT" docs/forge/plans/2026-02-02-mirror.md)
check "darkmem: exit 0" "$?" "0"
has "darkmem: the plan is named" "$out" "docs/forge/plans/2026-02-02-mirror.md"
has "darkmem: the mirror ledger is read" "$out" "ledger \`$M/work/sdd/2026-02-02-mirror/progress.md\`"
check "darkmem: latest.md is written to the mirror" \
  "$(grep -c '^## Next session' "$M/work/handoff/latest.md")" "1"
check "darkmem: nothing is written in the checkout" "$([ -e "$SR/.forge/handoff/latest.md" ] && echo yes || echo no)" "no"
```

`write_plan` is the suite's own helper (line 41): `write_plan <file> <execution line> <program line or empty>`. The ledger text is `next-step`'s own `ledger_note` (``ledger `$ledger_file` ``, `scripts/next-step:188`).

- [ ] **Step 2: Run the test to verify it fails**

Run: `timeout 600 bash plugins/dr-forge/tests/next-step.test.sh`
Expected: FAIL — `plan_repo_canon` cannot canonicalise a mirror plan (`not inside a git repository`).

- [ ] **Step 3: Write the implementation**

Every line number in this step is the original file's: the first replacement adds five lines, so make the edits from the bottom of the file up (line 423 first, `plan_finished` last), or find each by its quoted old text.

Replace `plan_finished` (lines 88-93, comment included) with:

```bash
# plan_finished ROOT NAME — true when the completed.md beside the plan NAME
# records it. Matched on the backticked name, as plan-revise does, so one
# plan's name that is a substring of another's cannot claim its outcome.
plan_finished() {
  local f
  f="$(dirname "$(forge_resolve "$2" "$1")")/completed.md"
  [ -f "$f" ] && grep -qF "\`$2\`" "$f"
}
```

In the plan branch (lines 132-138), replace

```bash
  root=$(git rev-parse --show-toplevel 2>/dev/null) || fail 2 "not inside a git repository"
  primary=$(plan_primary_root "$root")
  dir=$primary

  plan_canon=$(plan_repo_canon "$plan") || fail 2 "not inside a git repository"
  rel=${plan_canon#"$root"/}
  slug=$(basename "$plan" .md)
fi
```

with

```bash
  root=$(git rev-parse --show-toplevel 2>/dev/null) || fail 2 "not inside a git repository"
  primary=$(plan_primary_root "$root")
  dir=$primary

  forge_stores_init "$root"
  rel=$(forge_name "$plan")
  slug=$(basename "$plan" .md)
fi

forge_stores_init "$root"
# Shown repository-relative while progress is local, as before; the mirror's
# path otherwise, which no checkout-relative name can reach.
if [ "$(forge_progress_store)" = darkmem ]; then latest_shown=$(forge_latest_file)
else latest_shown="$(forge_dir_rel state "$primary")/handoff/latest.md"; fi
```

Then replace each `` `$(forge_dir_rel state "$primary")/handoff/latest.md` `` on lines 143, 146 and 155 with `` `$latest_shown` ``.

Line 171, `ledger_file="$(forge_dir state "$root")/sdd/$slug/progress.md"`, becomes `ledger_file="$(forge_ledger_dir "$slug")/progress.md"`. Replace lines 182-186

```bash
    if command -v cygpath >/dev/null 2>&1 && [ -n "$ledger_plan_path" ]; then
      ledger_plan_path=$(cygpath -u "$ledger_plan_path" 2>/dev/null || printf '%s' "$ledger_plan_path")
    fi
    case $ledger_plan_path in /*) ;; *) ledger_plan_path="$root/$ledger_plan_path" ;; esac
    if [ "$(plan_repo_canon "$ledger_plan_path" 2>/dev/null)" = "$plan_canon" ]; then
```

with

```bash
    if command -v cygpath >/dev/null 2>&1 && [ -n "$ledger_plan_path" ]; then
      ledger_plan_path=$(cygpath -m "$ledger_plan_path" 2>/dev/null || printf '%s' "$ledger_plan_path")
    fi
    if [ -n "$ledger_plan_path" ] && [ "$(forge_name "$ledger_plan_path")" = "$rel" ]; then
```

Line 239: `` reg_list="${reg_list:+$reg_list, }\`${reg_file#"$root"/}\`" `` becomes `` reg_list="${reg_list:+$reg_list, }\`$(forge_name "$reg_file")\`" ``.

Line 245: `` roadmap_unresolved "$root" "$(cut -f4 <<<"$current_ms")" | cut -f1 | sed "s|^|$root/|" `` becomes

```bash
          roadmap_unresolved "$root" "$(cut -f4 <<<"$current_ms")" | cut -f1 | while IFS= read -r r; do forge_resolve "$r"; done
```

Lines 273-274

```bash
        elif [ -f "$root/$a" ]; then
          if [ -n "$(plan_tasks "$root/$a")" ]; then r=1 k=plan; else r=2 k=spec; fi
```

become

```bash
        elif [ -f "$(forge_resolve "$a")" ]; then
          if [ -n "$(plan_tasks "$(forge_resolve "$a")")" ]; then r=1 k=plan; else r=2 k=spec; fi
```

Lines 288-289: replace `"$root/$target"` (twice) with `"$(forge_resolve "$target")"`.

Lines 319 and 322: replace `$(forge_dir_rel docs "$root")/roadmap.md` with `$(forge_name "$(forge_docs_root)")/roadmap.md`.

Line 423: `handoff="$(forge_dir state "$primary")/handoff/latest.md"` becomes `handoff=$(forge_latest_file)`.

After the edit, `grep -n 'plan_repo_canon\|\$root/\$' plugins/dr-forge/scripts/next-step` prints nothing.

- [ ] **Step 4: Run the tests to verify they pass**

Run each, bounded: `next-step`, `project-status`, `inline-mode`, `forge-state`, `auto-run` (`timeout 600 bash plugins/dr-forge/tests/<name>.test.sh`)
Expected: `0 failed` in each.

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-forge/scripts/next-step plugins/dr-forge/tests/next-step.test.sh
git commit -m "feat(dr-forge): route next-step through roots"
```

### Task 15: Route repo-audit and task-brief through the roots

**Files:**
- Modify: `scripts/repo-audit:52-71`, `:79`, `:97`, `scripts/task-brief:98`
- Test: `tests/repo-audit.test.sh`

**Interfaces:**
- Consumes: C7, C8
- Produces: none

**Items:** 2

**Implementer:** dr-superpowers:impl-sonnet-medium
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 2 = 4

- [ ] **Step 1: Write the failing tests**

In `tests/repo-audit.test.sh`, insert before the final summary `printf`:

```bash
# --- progress kept in darkmem: the mirror's ledgers and latest.md ---
. "$HERE/fixtures/darkmem-stores.sh"
SH="$TMP/stores-home"; mkdir -p "$SH"
M=$(stores_home "$SH" "$REPO" proj local darkmem)
mkdir -p "$M/work/sdd/plan"
printf '# SDD ledger — plan: docs/plan.md\nTask 1: complete (commits a..b, review clean)\n' > "$M/work/sdd/plan/progress.md"
printf '# Handoff\n\n**Status:** mirror status\n' > "$M/work/handoff/latest.md"
out=$(cd "$REPO" && HOME=$SH bash "$SCRIPT")
has "darkmem: the mirror's ledger" "$out" "- \`docs/plan.md\` in the darkmem mirror: 1 of 3 tasks complete"
has "darkmem: the mirror's latest.md" "$out" "- \`$M/work/handoff/latest.md\`"
has "darkmem: its status" "$out" "**Status:** mirror status"
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `timeout 600 bash plugins/dr-forge/tests/repo-audit.test.sh`
Expected: FAIL on `darkmem: the mirror's ledger`.

- [ ] **Step 3: Write the implementation**

In `scripts/repo-audit`, after `root` and `primary` are set and before the `## Plans in flight` section, add `forge_stores_init "$root"`. Replace the `## Plans in flight` loop (from `found=0` through `[ "$found" -eq 1 ] || echo "- none"`) with:

```bash
found=0
while IFS=$'\t' read -r ledger wt; do
  [ -n "$ledger" ] || continue
  found=1
  plan_rel=$(ledger_plan "$ledger")
  if [ "$wt" = mirror ]; then place="the darkmem mirror" base=$root; else place="\`$wt\`" base=$wt; fi
  total="?"
  if [ -n "$plan_rel" ]; then
    plan_file=$(forge_resolve "$plan_rel" "$base")
    [ ! -f "$plan_file" ] || total=$(plan_tasks "$plan_file" | grep -c . || true)
  fi
  done_n=$(ledger_done "$ledger" | grep -c . || true)
  last=$(tr -d '\r' < "$ledger" | grep -v '^[[:space:]]*$' | tail -n 1 | cut -c1-160)
  has_handoff=no
  [ -f "$(dirname "$ledger")/handoff.md" ] && has_handoff=yes
  echo "- \`${plan_rel:-unknown plan}\` in $place: $done_n of $total tasks complete; handoff.md: $has_handoff"
  echo "  - last ledger line: $last"
done < <(forge_ledger_files "$root")
[ "$found" -eq 1 ] || echo "- none"
```

Line 79 `reg_rel=${reg_file#"$root"/}` becomes `reg_rel=$(forge_name "$reg_file")`. Line 97 `latest="$(forge_dir state "$primary")/handoff/latest.md"` becomes `latest=$(forge_latest_file "$root")`.

In `scripts/task-brief:98`, replace

```bash
  ledger="$(forge_dir state "$(git rev-parse --show-toplevel 2>/dev/null || true)")/sdd/$(basename "$plan" .md)/progress.md"
```

with

```bash
  ledger="$(forge_ledger_dir "$(basename "$plan" .md)")/progress.md"
```

- [ ] **Step 4: Run the tests to verify they pass**

Run each, bounded: `repo-audit`, `budget-line`, `context-size`, `project-status` (`timeout 600 bash plugins/dr-forge/tests/<name>.test.sh`)
Expected: `0 failed` in each.

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-forge/scripts/repo-audit plugins/dr-forge/scripts/task-brief plugins/dr-forge/tests/repo-audit.test.sh
git commit -m "feat(dr-forge): route repo-audit through roots"
```

### Task 16: Route plan-revise and plan-lint through the roots

**Files:**
- Modify: `scripts/plan-revise:140-194` (`ledger_for`, `completed_form`), `:208` (`survey`)
- Modify: `scripts/plan-lint:47`, `:94`, `:102`, `:117-118`
- Modify: `scripts/lib/plan.sh` (delete `plan_repo_canon`)
- Test: `tests/plan-revise.test.sh`, `tests/plan-lint.test.sh`

**Interfaces:**
- Consumes: C7, C8, C10
- Produces: none

**Items:** 2

**Implementer:** dr-superpowers:impl-sonnet-medium
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 2 = 4

- [ ] **Step 1: Write the failing tests**

In `tests/plan-revise.test.sh`, insert before the final summary `printf`:

```bash
# --- documents and progress kept in darkmem: the survey finds the mirror's ledger ---
. "$HERE/fixtures/darkmem-stores.sh"
SH="$TMP/stores-home"; mkdir -p "$SH"
SR="$TMP/stores-repo"
git init -q "$SR"
git -C "$SR" -c user.name=t -c user.email=t@example.com commit -q --allow-empty -m init
M=$(stores_home "$SH" "$SR" proj darkmem darkmem)
mkdir -p "$M/superpowers/plans" "$M/work/sdd/mp"
printf '**Goal:** demo\n\n### Task 1: One\n' > "$M/superpowers/plans/mp.md"
printf '# SDD ledger — plan: docs/forge/plans/mp.md\n' > "$M/work/sdd/mp/progress.md"
row=$(cd "$SR" && HOME=$SH bash "$SCRIPT" --survey "$M/superpowers/plans" | grep '^plan  mp\.md')
check "darkmem survey: live" "$(field live "$row")" "yes"
check "darkmem survey: the evidence names the mirror" "$(grep -c 'ledger in mirror' <<<"$row")" "1"
```

In `tests/plan-lint.test.sh`, insert before the final summary `printf`:

```bash
# --- documents kept in darkmem: Spec paths resolve in the mirror ---
. "$HERE/fixtures/darkmem-stores.sh"
SH="$TMP/stores-home"; mkdir -p "$SH"
SR="$TMP/stores-repo"; git init -q "$SR"
M=$(stores_home "$SH" "$SR" proj darkmem darkmem)
mkdir -p "$M/superpowers/specs" "$M/superpowers/plans"
printf '# Spec\n' > "$M/superpowers/specs/s.md"
printf '# P\n\n**Spec:** docs/forge/specs/s.md\n\n### Task 1: One\n' > "$M/superpowers/plans/p.md"
out=$(cd "$SR" && HOME=$SH bash "$LINT" docs/forge/plans/p.md --no-probe 2>&1)
lacks "darkmem: the Spec path resolves in the mirror" "$out" "Spec path does not exist"
lacks "darkmem: the plan is found by name" "$out" "no such plan file"
has "darkmem: the lint ran to its summary" "$out" " errors, "
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `timeout 600 bash plugins/dr-forge/tests/plan-revise.test.sh`, then `timeout 600 bash plugins/dr-forge/tests/plan-lint.test.sh`
Expected: FAIL on `darkmem survey: live` and `darkmem: the Spec path resolves in the mirror`.

- [ ] **Step 3: Write the implementation**

In `scripts/plan-revise`, replace `ledger_for` and `completed_form` (lines 140-194, comments included) with:

```bash
# ledger_for PLAN — "<where>\t<ledger>" for the ledger whose identity line
# names PLAN: every worktree's ledgers while progress is local (execution may
# run in a linked worktree while the plan is read from the primary checkout),
# the mirror's while it is darkmem. Identities compare as names; an absolute
# local identity is stripped of the longest worktree root it lies under, since
# a worktree created inside the primary checkout has the primary root as a
# prefix of its own.
ledger_for() {
  local ctx slug want ledger where named best wt roots
  ctx=$(_plan_ctx "$1")
  slug=$(basename "$1" .md)
  want=$(forge_name "$1" "$ctx")
  roots=$(git -C "$ctx" worktree list --porcelain 2>/dev/null | tr -d '\r' | sed -n 's/^worktree //p')
  while IFS=$'\t' read -r ledger where; do
    [ -n "$ledger" ] || continue
    [ "$(basename "$(dirname "$ledger")")" = "$slug" ] || continue
    named=$(ledger_plan "$ledger")
    [ -n "$named" ] || continue
    case $named in /*)
      best=""
      while IFS= read -r wt; do
        [ -n "$wt" ] || continue
        case $named in "$wt"/*) [ "${#wt}" -gt "${#best}" ] && best=$wt ;; esac
      done <<<"$roots"
      if [ -n "$best" ]; then named=${named#"$best"/}; else named=$(forge_name "$named" "$ctx"); fi ;;
    esac
    [ "$named" = "$want" ] || continue
    printf '%s\t%s\n' "$where" "$ledger"
    return 0
  done < <(forge_ledger_files "$ctx")
}

# completed_form PLAN — "merged", "pr" or nothing, from the completed.md beside
# the plan. The entry is matched on the plan's name, not a basename substring:
# "docs/scored.md" is a substring of "docs/unscored.md" and would otherwise
# claim another plan's outcome. Merged outranks via PR whatever their order,
# because finishing-a-development-branch writes the via-PR line before the
# push and the merged line after the merge.
completed_form() {
  local f rel hits
  f="$(cd "$(dirname "$1")" && pwd)/completed.md"
  [ -f "$f" ] || return 0
  rel=$(forge_name "$1" "$(_plan_ctx "$1")")
  hits=$(grep -F "\`$rel\`" "$f" 2>/dev/null) || return 0
  [ -n "$hits" ] || return 0
  if grep -qF 'merged into' <<<"$hits"; then printf 'merged\n'
  elif grep -qF 'via PR' <<<"$hits"; then printf 'pr\n'
  fi
}
```

In `survey`, add as its first line after the `local` declarations: `forge_stores_init "$(_plan_ctx "$dir/x")"`.

In `scripts/plan-lint`:

- line 47 becomes `root=$(git -C "$(dirname "$plan")" rev-parse --show-toplevel 2>/dev/null || git rev-parse --show-toplevel 2>/dev/null || pwd)`, followed by a new line `forge_stores_init "$root"`;
- line 94 `[ -f "$root/$spec_path" ] || say …` becomes `[ -f "$(forge_resolve "$spec_path" "$root")" ] || say …`;
- line 102 `[ -f "$root/$ppath" ] || say …` becomes `[ -f "$(forge_resolve "$ppath" "$root")" ] || say …`;
- lines 115-118 (the comment about canonicalising and the two `plan_rel` lines) become the single line `plan_rel=$(forge_name "$plan" "$root")`.

In `scripts/lib/plan.sh`, delete `plan_repo_canon` and its comment. Then `grep -rn plan_repo_canon plugins/dr-forge` must print nothing.

- [ ] **Step 4: Run the tests to verify they pass**

Run each, bounded: `plan-revise`, `plan-lint`, `plan-lib`, `next-step`, `review-route`, `ladder` (`timeout 600 bash plugins/dr-forge/tests/<name>.test.sh`)
Expected: `0 failed` in each; the grep prints nothing.

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-forge/scripts/plan-revise plugins/dr-forge/scripts/plan-lint plugins/dr-forge/scripts/lib/plan.sh plugins/dr-forge/tests/plan-revise.test.sh plugins/dr-forge/tests/plan-lint.test.sh
git commit -m "feat(dr-forge): route plan-revise through roots"
```

### Task 17: Write the skill prose against the new tokens

**Files:**
- Modify: `skills/using-superpowers/SKILL.md:63`, `reference/project-state.md:74-91`
- Modify: `skills/handoff/SKILL.md:76-77,83-87,96,130`, `skills/brainstorming/SKILL.md:367`, `skills/closing-a-milestone/SKILL.md:54`, `skills/writing-plans/SKILL.md:511-512`, `skills/finishing-a-development-branch/SKILL.md:301,341-342,406`, `skills/resume-execution/SKILL.md:17,37`, `skills/executing-plans/SKILL.md:133,158-166,173`, `skills/subagent-driven-development/SKILL.md:123,229-239,245,319`, `skills/subagent-driven-development/references/ruling-prompt.md:121-122`, `skills/distilling-docs/SKILL.md:74`
- Modify: `README.md:274-290`

**Interfaces:**
- Consumes: C9, C11
- Produces: none

**Items:** 2

**Implementer:** dr-superpowers:impl-sonnet-medium
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 1 = 3

- [ ] **Step 1: Confirm the old tokens are there**

Run: `grep -rnE "<workspace>/(progress|handoff)\.md|<state>/handoff/latest\.md|<state>/sdd/[^ ]*progress\.md|<state>/sdd/<plan" plugins/dr-forge/skills plugins/dr-forge/reference`
Expected: 22 lines in the files listed above.

- [ ] **Step 2: Replace the entry point's path line**

In `skills/using-superpowers/SKILL.md`, replace line 63 (the bullet beginning ``- `<state>` and `<docs>` in these skills are repository-relative``) with exactly:

```markdown
- `<state>`, `<docs>`, `<ledger dir>` and `<latest.md>` in these skills: `bash <plugin-root>/scripts/forge-path state|docs [RELATIVE]|ledger <plan>|latest` prints each in the checkout it runs in, or in the darkmem mirror where `documentStore` or `progressSource` keeps it ([project-state.md](../../reference/project-state.md)).
```

Run: `wc -c < plugins/dr-forge/skills/using-superpowers/SKILL.md` — Expected: at most 5100.

- [ ] **Step 3: Rewrite the reference section**

In `reference/project-state.md`, replace everything from `## Where \`<state>\` and \`<docs>\` are` to the end of that section (the paragraph ending `the resolved path minus the checkout's root.`) with:

```markdown
## Where `<state>`, `<docs>`, `<ledger dir>` and `<latest.md>` are

`<state>` is `.forge/` and `<docs>` is `docs/forge/`, except in a repository
that has `.superpowers/` or `docs/superpowers/` and not the new directory:
there the old one stays in use, for writing as well as reading, so a pre-2.0
checkout never splits across both.

A repository mapped to darkmem may keep each family in the darkmem mirror
instead (`documentStore`, `progressSource`; `bash <plugin-root>/scripts/forge-path store`
prints which):

| Token | Local | darkmem |
|---|---|---|
| `<docs>` | `<worktree>/docs/forge` | `~/.dr-forge/mirror/<project>/superpowers` |
| `<ledger dir>` | `<worktree>/<state>/sdd/<plan-basename>` | `~/.dr-forge/mirror/<project>/work/sdd/<plan-basename>` |
| `<latest.md>` | `<primary checkout>/<state>/handoff/latest.md` | `~/.dr-forge/mirror/<project>/work/handoff/latest.md` |

`<state>` and a plan's workspace (`scripts/sdd-workspace`: briefs, reports,
review packages, `amendments.md`) stay in the checkout either way. A plan's
ledger is `<ledger dir>/progress.md` and its handoff note
`<ledger dir>/handoff.md`.

Every script resolves these through `scripts/lib/roots.sh`; a skill resolves
them with `bash <plugin-root>/scripts/forge-path state|docs [RELATIVE] | ledger <plan-basename> | latest`
before it reads or writes, never by spelling a path. `forge-path` answers for
the checkout it runs in; for a path written under another root, such as
`<worktree>/<state>/…`, run it from that root:
`(cd "<root>" && bash <plugin-root>/scripts/forge-path state sdd)`.

Where a path is written into a file or onto a command line (a ledger's
identity line, a roadmap `Spec` or `Register` cell, a `**Spec:**` line,
`.gitattributes`, a script argument), write its name:
`bash <plugin-root>/scripts/forge-path name <path>`. A document's name is
`docs/forge/<rest>` (`docs/superpowers/<rest>` in a pre-2.0 repository) in both
stores, so a ledger in darkmem can name a plan in the checkout and the reverse;
every script accepts a name where it takes a path.

While `forge-path store` prints `documents darkmem`, a step that commits a
spec, plan, register, roadmap or `completed.md` line runs
`bash <plugin-root>/scripts/darkmem-sync push` instead. Code commits are
unchanged.
```

- [ ] **Step 4: Replace the tokens in the skills**

Make each replacement below exactly; each Old text is unique in its file.

`skills/handoff/SKILL.md`:

- Old: ``     `<workspace>/handoff.md` (below); `<workspace>` is the directory`` and the next line ``     `scripts/sdd-workspace PLAN_FILE` prints.`` — New: ``     `<ledger dir>/handoff.md` (below; `<ledger dir>` per``, then ``     using-superpowers §Session Budget).``
- Old: ``2. **Commit the plan and the spec** if either has uncommitted changes, in a`` and the next line ``   `docs(<scope>): …` commit of their own. Never commit `<state>/`.`` — New: ``2. **Commit the plan and the spec** if either has uncommitted changes, in a``, then ``   `docs(<scope>): …` commit of their own (push instead while documents live in``, then ``   darkmem; see project-state.md). Never commit `<state>/`.``
- Old: ``3. **Write the notes sections of `latest.md`** at`` and the next two lines (``   `<primary checkout>/<state>/handoff/latest.md`. The primary checkout is`` and the `git -C …` line) — New: ``3. **Write the notes sections of `latest.md`** at `<latest.md>`.``
- Old: ``   - Plan: `<plan path>`; ledger: `<workspace>/progress.md`; handoff: `<workspace>/handoff.md` `` — New: ``   - Plan: `<plan name>`; ledger: `<ledger dir>/progress.md`; handoff: `<ledger dir>/handoff.md` ``
- Old: ``\`<workspace>/handoff.md\` holds what the ledger cannot, in under 40 lines:`` — New: ``\`<ledger dir>/handoff.md\` holds what the ledger cannot, in under 40 lines:``

`skills/brainstorming/SKILL.md`: Old `- Commit the design document to git` — New `- Commit the design document to git (push instead while documents live in darkmem; see project-state.md)`.

`skills/closing-a-milestone/SKILL.md`: Old `   and commit the registers and the roadmap together.` — New `   and commit the registers and the roadmap together (or push them, while documents live in darkmem).`

`skills/writing-plans/SKILL.md`: Old ``Invoke dr-forge:handoff. It commits the plan and the spec, writes`` and the next line ``\`<state>/handoff/latest.md\`, runs `scripts/next-step PLAN_FILE`, and ends`` — New ``Invoke dr-forge:handoff. It commits (or pushes) the plan and the spec, writes`` and ``\`<latest.md>\`, runs `scripts/next-step PLAN_FILE`, and ends``.

`skills/finishing-a-development-branch/SKILL.md`:

- Old (line 301): ``a full basename would not.`` — New: ``a full basename would not. While documents live in darkmem, `completed.md` is``, then ``in the mirror: push it instead of committing it (see project-state.md).``
- Old: ``A plan's workspace (`<state>/sdd/<plan>/`: ledger, briefs, reports,`` and the next line ``\`handoff.md\`) is git-ignored and lives in the worktree, so it goes with it —`` — New: ``A plan's workspace (`<state>/sdd/<plan>/`: briefs, reports, and the ledger``, then ``and `handoff.md` while progress is local) is git-ignored and lives in the worktree, so it goes with it —``
- Old: ``also rewrites the primary checkout's `<state>/handoff/latest.md` to`` — New: ``also rewrites `<latest.md>` to``

`skills/resume-execution/SKILL.md`:

- Old: ``   `<primary checkout>/<state>/handoff/latest.md`; the audit prints its path.`` — New: ``   `<latest.md>`; the audit prints its path.``
- Old: ``4. **Reload** `<workspace>/handoff.md`, the plan's header (run`` — New: ``4. **Reload** `<ledger dir>/handoff.md`, the plan's header (run``

`skills/executing-plans/SKILL.md`:

- Old: ``\`<state>/handoff/latest.md\`; if it exits 4, say the handoff file could not`` — New: ``\`<latest.md>\`; if it exits 4, say the handoff file could not``
- Old (lines 158-160): ``  (`<repo-root>/<state>/sdd/<plan-basename>/`), home to every artifact for`` / ``  THIS plan. Another plan's directory is never yours to read or write.`` / ``- This plan's ledger is `<workspace>/progress.md`. If its first line names your`` — New: ``  (`<repo-root>/<state>/sdd/<plan-basename>/`), home to every artifact for`` / ``  THIS plan except its ledger and handoff note, which live in `<ledger dir>`.`` / ``  Another plan's directory is never yours to read or write.`` / ``- This plan's ledger is `<ledger dir>/progress.md`. If its first line names your``
- Old: ``  `# SDD ledger — plan: <plan file path>` — the path exactly as you pass it to`` and the next line ``  the scripts (checkout-relative or absolute; `next-step` resolves both).`` — New: ``  `# SDD ledger — plan: <plan name>` — `bash <plugin-root>/scripts/forge-path name PLAN_FILE`,`` and ``  so the ledger names the plan in either store.``
- Old: ``- Create `<workspace>/handoff.md` from the template in dr-forge:handoff`` — New: ``- Create `<ledger dir>/handoff.md` from the template in dr-forge:handoff``

`skills/subagent-driven-development/SKILL.md`:

- Old: ``checkout's `<state>/handoff/latest.md`; if it exits 4, say the handoff`` (line 123, preceded by ``verbatim. It also rewrites the `## Next session` section of the primary``) — New: the two lines ``verbatim. It also rewrites the `## Next session` section of`` and ``\`<latest.md>\`; if it exits 4, say the handoff``
- Old: ``  every artifact for THIS plan: ledger, briefs, reports, review packages.`` — New: ``  every artifact for THIS plan: briefs, reports, review packages. Its ledger``, then ``  and handoff note live in `<ledger dir>`.``
- Old: ``- Check for this plan's ledger at `<workspace>/progress.md`. If its first`` — New: ``- Check for this plan's ledger at `<ledger dir>/progress.md`. If its first``
- Old: ``  `# SDD ledger — plan: <plan file path>` — the path exactly as you pass it to`` and the next line ``  the scripts (checkout-relative or absolute; `next-step` resolves both).`` — New: ``  `# SDD ledger — plan: <plan name>` — `bash <plugin-root>/scripts/forge-path name PLAN_FILE`,`` and ``  so the ledger names the plan in either store.``
- Old: ``- Create `<workspace>/handoff.md` from the template in dr-forge:handoff`` — New: ``- Create `<ledger dir>/handoff.md` from the template in dr-forge:handoff``
- Old: ``This skill owns every line in `<workspace>/progress.md`. The grammar:`` — New: ``This skill owns every line in `<ledger dir>/progress.md`. The grammar:``

`skills/subagent-driven-development/references/ruling-prompt.md`: Old ``- `[AMENDMENTS_FILE]`, `[LEDGER_FILE]` — REQUIRED: `<workspace>/amendments.md` `` and the next line ``  and `<workspace>/progress.md`.`` — New: the same first line, then ``  and `<ledger dir>/progress.md`.``

`skills/distilling-docs/SKILL.md`: Old ``   directories, plus the primary checkout's `<state>/handoff/latest.md`,`` — New ``   directories, plus `<latest.md>`,``

The lines naming the old flat path `<state>/sdd/progress.md` (executing-plans, subagent-driven-development) stay: they describe a pre-workspace stray file in the checkout.

- [ ] **Step 5: Rewrite the README paragraph**

In `README.md`, replace the paragraph from `**darkmem mirror (optional).**` through `repository's own paths.` (lines 274-290) with:

```markdown
**darkmem mirror (optional).** `scripts/darkmem-sync` keeps a repository's
  planning documents and progress in a darkmem instance over its keyed REST
  routes. Map the repository's primary checkout in
  `~/.dr-forge/config.json` —
  `{"darkmem": {"url": "http://<host>:8000", "api_key_env": "DARKMEM_API_KEY", "repos": {"<primary checkout path>": {"project": "<name>"}}}}`
  — and export a `dmk_` key in that variable, and the repository syncs a mirror
  at `~/.dr-forge/mirror/<project>/`. Before 2.0 these lived under
  `~/.dr-superpowers/`, which is still read until the new file exists. The key
  needs the `read` and `capture` scopes, and `import --replace` also `admin`.
  Two settings choose each family's store: `documentStore` (specs, plans,
  registers, notes) and `progressSource` (ledgers and handoffs), `local` or
  `darkmem`; a mapping entry may override either, for example
  `{"project": "plugins", "documentStore": "local"}`. `~/.dr-forge/stores.json`
  records where each family actually lives, and the scripts and skills read
  and write there through `scripts/lib/roots.sh` and `scripts/forge-path`.
  `pull` fetches what changed; `push` sends documents under their last synced
  hash and each new ledger line as its own entry, with `task`, `state` and
  `commit` properties a progress board can read; `status` lists each family's
  store and local changes; `import` moves an existing `docs/forge/` and its
  ledgers in once, verified byte for byte, and records the families configured
  `darkmem` as living there. A conflict is reported, never merged. Without the
  key the mirror still works offline and `pull` and `push` say why they
  skipped. Without a mapping every command but `import` prints one line and
  does nothing.
```

- [ ] **Step 6: Verify**

Run: `grep -rnE "<workspace>/(progress|handoff)\.md|<state>/handoff/latest\.md|<state>/sdd/<plan-basename>/progress" plugins/dr-forge/skills plugins/dr-forge/reference`
Expected: nothing.

Run: `node scripts/validate-repository.mjs`, `timeout 600 bash plugins/dr-forge/tests/hook.test.sh`, `timeout 600 bash plugins/dr-forge/tests/working-directory.test.sh`, `timeout 600 bash plugins/dr-forge/tests/settings-skills.test.sh`, `timeout 600 bash plugins/dr-forge/tests/distilling-docs.test.sh`
Expected: valid; `0 failed` in each.

Then the plan's full validation, from the repository root: `timeout 2700 node scripts/test-all.mjs`, `claude plugin validate .` and `claude plugin validate plugins/<name>` for each Claude plugin in `.claude-plugin/marketplace.json`, and `timeout 600 claude plugin test plugins/dr-forge`. Expected: all pass. Confirm afterwards that no process the run started is still alive.

- [ ] **Step 7: Commit**

```bash
git add plugins/dr-forge/skills plugins/dr-forge/reference/project-state.md plugins/dr-forge/README.md
git commit -m "docs(dr-forge): name ledger and latest.md by token"
```
