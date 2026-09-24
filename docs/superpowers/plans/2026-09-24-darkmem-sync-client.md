# darkmem-sync Client Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: the skill the **Execution:** line names — dr-superpowers:subagent-driven-development for `subagent`, dr-superpowers:executing-plans for `inline`. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship `scripts/darkmem-sync` — `status`, `pull`, `push` and `import` — which keeps a mapped repository's dr-superpowers documents and progress in darkmem through a local mirror, and changes nothing for an unmapped repository.

**Architecture:** A bash wrapper execs one Node entry module, which parses arguments, resolves the mode from `~/.dr-superpowers/config.json`, takes a per-mirror lock, and loads the sync state. Four library modules sit under it: config (mode, roots, run key), client (darkmem's keyed REST routes with a bounded timeout), mirror (layout, state, lock, text chunking), and one module per command (pull, push, import). Tests are `node:test` suites run against an in-memory stub of darkmem's routes, collected by one `.test.sh` wrapper so `scripts/test-all.mjs` finds them.

**Tech Stack:** Node.js 22 built-ins only (`fetch`, `node:http`, `node:test`), bash, git.

**Spec:** `docs/superpowers/specs/2026-09-23-darkmem-mirror-design.md`

**Execution:** inline — `claude --model sonnet --effort high` — 3 of 8 tasks are heavy (Tasks 5–7, delegated to `impl-opus-medium`), none is four-band, and Tasks 1 and 3 carry an `**Executor:**` line; the session implements Tasks 2, 4 and 8 itself, and effort is high because tasks are delegated.

**Plan review:** 2026-09-24 — dr-superpowers:judge-opus — executability 17 / coherence 16 / coverage 17 / assumptions 16 (round 2)

> **External executors:** codex

## Global Constraints

- Node.js 22 built-ins only: no npm dependency, no `package.json`. CI runs Node 22 on Linux and Windows (`.github/workflows/validate.yml:17,49`).
- Local mode is exactly today's behaviour: Tasks 1–7 add files and change no existing script, skill, hook, reference or test. Task 8 edits only the README, the two dr-superpowers manifests, the version pin in `tests/review-route.test.sh`, and one register row.
- The configuration file is `~/.dr-superpowers/config.json` and the mirror is `~/.dr-superpowers/mirror/<project>/`, both under the user's home (`HOME`, else the OS home). The API key is read from the environment variable the file names, never from the file (spec §1).
- The sync speaks only the routes in Contracts → **darkmem routes**, with `Authorization: Bearer <key>` and `X-Darkmem-Client: dr-superpowers` on every call and a timeout on every call (spec §3).
- A local file with changes of its own is never overwritten, and a conflict is reported, never merged (spec §3, Not in scope).
- Tests call no model and no real darkmem. Run every test suite, `node` command and `claude plugin validate` under `timeout`; plain `git`, `grep` and `cat` reads need none.
- Every `node --test` command passes `--test-reporter=spec`: Node 22 prints TAP, not the `ℹ pass` summary the steps check, when stdout is not a terminal.
- A write whose answer may have been lost is reconciled against darkmem before it is retried, so a retry never files the same ledger bytes or checkpoint twice (spec §3's exact-concatenation rule).
- Both dr-superpowers manifests carry the same version; the target is `1.22.0`.
- Commit messages follow `<type>(superpowers): <subject>`, subject 50 characters or fewer, and end with the `Co-Authored-By:` line naming the model that did the work. Each task's commit step spells the line for its assigned implementer; an implementer running on a different model writes its own model's name.
- English only in code, comments, docs and tests. Do not edit historical plans or specs.

## Contracts

- **Files** (all under `plugins/dr-superpowers/`): `scripts/darkmem-sync` (Task 4), `scripts/lib/darkmem-config.mjs` (Task 1), `scripts/lib/darkmem-client.mjs` (Task 2), `scripts/lib/darkmem-mirror.mjs` (Task 3), `scripts/lib/darkmem-sync.mjs` (Task 4; Tasks 5–7 each add one import and one `COMMANDS` entry), `scripts/lib/darkmem-pull.mjs` (Task 5), `scripts/lib/darkmem-push.mjs` (Task 6), `scripts/lib/darkmem-import.mjs` (Task 7); tests `tests/darkmem-sync.test.sh` (Task 3) and `tests/darkmem-sync/{helpers,stub-server}.mjs` plus one `<name>.test.mjs` per task.
- **Command** (Task 4): `darkmem-sync status | pull | push [--workstream KEY] | import [--replace]`. Exit 0 done; 1 conflicts, refused or failed items, or another sync holds the mirror; 2 usage, a malformed config or state file, or `import` in local mode; 3 darkmem unreachable, or an answer that stopped the command; 4 an unexpected error. Output lines: `darkmem-sync: local mode — <reason>`; `conflict: <what>`, `failed: <what>`, `note: <what>`; and, for pull, push and import, the summary `darkmem-sync <command>: <n> <counter>, …; <c> conflicts, <f> failures`. Counters: pull `documents`, `ledgers`, `checkpoints`; push `documents`, `ledger entries`, `checkpoints`; import `documents`, `workstreams`.
- **darkmem-config.mjs** (Task 1): `ConfigError`; `superpowersHome(env)`; `primaryRoot(cwd)`; `resolveMode({cwd, env})` returns `{mode: "local", reason, repoRoot, docsRoot, workRoot}` or `{mode: "darkmem", reason, repoRoot, project, url, apiKey, mirror, docsRoot, workRoot, statePath}`; `runKey({cwd, env, now})`.
- **darkmem-client.mjs** (Task 2): `TransportError`; `HttpError` with `.status` and `.detail`; `createClient({url, apiKey, runKey, timeoutMs, fetchImpl})` returning `manifest(project, uriPrefix)`, `getDocument(project, uri)`, `putDocument({project, uri, content, expectedHash})`, `append({project, workstream, entries, properties})`, `resume(project, workstream)` (`null` on 404), `workstreams(project, state)`, `entries(workstreamId, kind)`, `updateWorkstream(id, patch)`, `purgeWorkstream(id)`. The list calls follow every page.
- **darkmem routes** (Task 2 calls them; the stub serves them): `GET /api/v1/documents/manifest?project=&uri_prefix=&after=&limit=` → `{items: [{id, uri, content_hash, updated_at}], next_after}`; `GET /api/v1/documents/by-uri?project=&uri=&include_content=true` → `{document_id, blocks, content, content_hash}`; `POST /api/v1/documents {project, uri, content, expected_hash?}` → 201 `{document_id, outcome, content_hash, …}`, 409 on a stale or absent-document `expected_hash`; `POST /api/v1/worklog/entries {project, workstream, run_key, client, properties?, entries: [{kind, body}]}` → 201 `{workstream, entry_ids}`; `GET /api/v1/worklog/resume?project=&workstream=` → `{workstream, checkpoint, notes, notes_truncated, ledger}`, 404 when absent; `GET /api/v1/worklog/workstreams?project=&state=&before=&limit=` → `{items, next_before}`; `GET /api/v1/worklog/workstreams/{id}/entries?kind=&after=&limit=` → `{items, next_after}`, oldest first; `PATCH /api/v1/worklog/workstreams/{id} {state?, retain?, title?, properties?}`; `DELETE /api/v1/worklog/workstreams/{id}` → 204.
- **darkmem-mirror.mjs** (Task 3): constants `DOC_PREFIX = "superpowers"`, `MAX_ENTRY_CHARS = 65536`, `MAX_ENTRIES_PER_APPEND = 100`, `EMPTY_SHA`; errors `StateError`, `UsageError`; functions `sha256`, `validKey`, `uriToLocal(roots, uri)` (null for a uri that climbs out or names a dotfile), `listDocumentFiles(roots)` → `[{file, uri}]` (`uri` null for the reserved `handoff/` directory under the docs root), `ledgerFiles(workRoot)` → `[{slug, file}]`, `unsupportedPlanDirs(workRoot)` → paths of `sdd/` directories holding a `progress.md` or `handoff.md` under a name `validKey` refuses, `emptyState()`, `loadState(file)`, `saveState(file, state)`, `writeFileAtomic(file, data)` (temporary file `.<name>.tmp` beside the target), `acquireLock(dir, {staleMs, beforeTakeover})` → release function or null (`beforeTakeover` is a test seam), `lockOwner(dir)` → the holder's `{pid, host, token}` or null, `decodeUtf8`, `splitAtLimit(text, limit)`, `splitAtBlankLines(text)`, `pathToUri(path)`, `ledgerPlanPath(ledgerText)` → the identity line's plan path or null, `propertiesFor(roots, slug, namedPath)` → `{plan_uri?, spec_uri?, handoff_uri?}`, `checkpointTarget(text)` → `{slug, path}` or null, `localChanges(roots, state)`. `roots` is always `{docsRoot, workRoot}`. A directory that cannot be read, other than a missing one, throws.
- **Mirror layout** (Task 3): document uri `superpowers/<path>` ↔ `<docsRoot>/<path>`; uri `superpowers/handoff/<slug>.md` ↔ `<workRoot>/sdd/<slug>/handoff.md`; ledger `<workRoot>/sdd/<slug>/progress.md` ↔ `ledger` entries of workstream `<slug>`; `<workRoot>/handoff/latest.md` ↔ `checkpoint` entries. Dotfiles are never synced.
- **State file** (Task 3): `<mirror>/.sync-state.json` = `{version: 1, documents: {<uri>: <sha256>}, ledgers: {<slug>: {offset, prefix, pending?}}, checkpoint: <sha256>|null, checkpointAt: <ISO time>|null, conflicts: [<text>]}`. `offset` counts bytes pushed or pulled, `prefix` is the SHA-256 of those bytes, and `pending: true` marks an append sent without a recorded answer. `checkpointAt` is darkmem's `created_at` of the last synced checkpoint. `documents` and `ledgers` load as prototype-free dictionaries, and a file failing any of these shapes is a `StateError`. The lock is the directory `<mirror>/.sync.lock` holding `owner.json` = `{pid, host, token}`: a holder on this host is waited on while its process lives; a lock with no readable owner, or from another host, is taken over after ten minutes. A takeover moves the lock aside and deletes it only if it is still the lock it judged abandoned (same owner token, or for an ownerless lock the same modification time), so two takeovers at once leave one holder; a release removes the lock only while it still carries the releaser's token. A refused command names the holder's pid and host and the lock path.
- **Command modules** (Tasks 5–7): each exports one `async (context)` — `pull` from `darkmem-pull.mjs` (which also exports `ledgerText(client, workstreamId)`, `pullDocuments(context)` and `pullLedgers(context, workstreams)`), `push` from `darkmem-push.mjs`, `importRepository` from `darkmem-import.mjs`. `context` = `{cfg, roots, state, persist, client, report, options, out}`; `report` = `{conflicts: [], failures: [], notes: [], counts: {}}`; `persist()` saves the state. A completed pull or push replaces `state.conflicts` with its own; one that stopped part-way (exit 3) adds its findings to them.
- **darkmem objects** (served by the routes above; the stub serves the same fields): a workstream is `{id, project, key, title, client, state: "open"|"closed", closed_at, retain, properties, last_entry_at, created_at, updated_at}`; an entry is `{id, workstream_id, seq, run_key, kind: "checkpoint"|"ledger"|"note", body, properties, created_at}`; resume's `checkpoint` is an entry or `null`, `notes` and `ledger` are entry lists; entry pages are ordered by `seq`, and `next_after` is the last `seq` of a full page.
- **Test fixtures**: `helpers.mjs` (Task 1) exports `SCRIPT`, `KEY`, `scratch(prefix)` (a temporary directory removed when the test process exits), `git(cwd, ...args)`, `makeRepo()`, `makeHome({repo, url, project, config})` → `{home, env, mirror, docsRoot, workRoot}`, `run(args, {cwd, env})` → `{code, stdout, stderr}`, `write(file, content)`, `read(file)`. `stub-server.mjs` (Task 2) exports `STUB_KEY`, `sha(text)`, `storedDocument(project, uri, content)` and `startStub({pageSize, transformContent, onRequest})` → `{url, db, close}`. `db.documents` is a `Map` keyed `` `${project}\u0000${uri}` `` holding `{id, project, uri, content, content_hash, updated_at}`; `db.workstreams` is an array of workstream objects each carrying its `entries`; `db.requests` records every call as `{method, path, query, headers, body}`; `db.failures` holds `{method, path, status, detail?, commit?}` injections, matched on method and path prefix, used once, where `commit: true` applies the request before answering the failure (a lost response). `onRequest(request, db)` runs before each authenticated request is answered.

## Assumptions (evidence)

- darkmem's contract, read at darkmem `master` `54f34e44` on 2026-09-24: `content_hash` is SHA-256 of the UTF-8 content (`backend/app/services/document_ingest.py:184-188`); a put whose `expected_hash` names an absent document is a conflict (`document_ingest.py:280-283`), mapped to 409 (`backend/app/api/routes/documents.py:785-796`); the put body and reply (`documents.py:262-271`, `:321-340`); the manifest's `limit ≤ 1000`, uri keyset and trailing-slash strip (`documents.py:502-525`); the keyed by-uri read with `include_content` (`documents.py:991-1011`); the work-log routes (`backend/app/api/routes/worklog.py:42-160`); entry bodies of 1–65,536 characters, 1–100 entries per append (`backend/app/services/worklog.py:54,60`, `backend/app/schemas/worklog.py:64-82`); the run key is the body's `run_key` and `X-Darkmem-Client` sets the source (`worklog.py:47-52`); `dmk_` bearer keys reach `require_scope` routes (`backend/app/api/auth.py:104`).
- The keyed routes are merged in darkmem but not deployed on the live instance (increment 1 merged 2026-09-24; the owner's go-ahead is pending). Every test here runs against the stub; the first call against a real darkmem is the owner's, after that deploy.
- darkmem's `docs/superpowers/` holds 162 files, all `.md`, the largest 247,646 bytes — under the server's 1,000,000-character bound (`find docs/superpowers -type f`, 2026-09-24). `.superpowers/sdd/*/progress.md`: 9 files, the largest 65,551 bytes, so import splits at least one ledger at the entry limit.
- `scripts/session-start.sh:18-33` already persists `session_id` in `~/.claude/dr-superpowers/sessions/<cwd key>.json`, so the run key needs no hook change.
- Every file in Tasks 1–8 was prototyped in a scratch copy of `ba1e112` on 2026-09-24, revised after plan-review rounds 1 and 2: `tests/darkmem-sync.test.sh` 69/69 on three consecutive runs (config 6, client 6, mirror 13, cli 6, pull 11, push 18, import 9), leaving no temporary directory behind; `node scripts/validate-repository.mjs` valid; `tests/test-shards.test.mjs` 3/3; `node scripts/test-all.mjs --list` lists the new suite; `review-route.test.sh` 229/0 after the bump; `claude plugin validate` passed on the marketplace and all four plugins. `node scripts/test-all.mjs` failed only the known environmental case, `tests/ui-discovery.test.mjs` "documented Win32 discovery finds centrally managed versions" (the child shell's PATH has no `rg`).
- Windows is unverified locally: CI's six Windows shards are the first run there, and Task 8 Step 5 records that check as a register row for the owner. The fixtures take `DR_TEST_BASH` (as `scripts/test-all.mjs:11` does) and `realpathSync.native` (Windows short names), and the entry module runs unconditionally, as `scripts/lib/codex-gate.mjs` does, rather than comparing `import.meta.url` to a path Git Bash has converted.
- Scope: the spec's Delivery section (amended 2026-09-24) makes this plan increment 1 — §1, §3 and the §7 tests — and register row 1 of `docs/superpowers/registers/2026-09-24-darkmem-mirror.md`. Increment 2 (§2's roots, §4's triggers, §5's promotion; rows 2–4) needs a ruling on how a plan outside the repository is identified, because `plan_require_same_repo`, ledger identity lines, register `Covers` paths and `plans/completed.md` all assume a repository-relative plan path (`scripts/lib/plan.sh:367-384`). §6 is row 5, owner-run.
- darkmem has no create-only put (`put_document` takes `expected_hash` or nothing; `document_ingest.py:280`). So a document no mirror has synced is created last-writer-wins, and a push that finds, from the put's own `outcome: "updated"`, that another client filed the uri between its manifest read and its put reports that as a failure. The window is one request; closing it needs a server change, which is recorded here rather than built.
- A lost answer is reconciled rather than prevented: a ledger append is marked `pending` in the state before it is sent, and the next push adopts darkmem's copy when it is a prefix of the file; a checkpoint is compared with the workstream's latest checkpoint before it is filed; a document put that answers 409 is compared with darkmem's current hash, and an equal hash is recorded, not reported.
- Codex executor: `codex-gate` printed `lane=true` on 2026-09-24. Tasks 1–4 clear the lane gate (total ≥ 2, risk ≤ 1); Tasks 2 and 4 bind localhost sockets, which the Codex sandbox refused on three runs of darkmem's last plan (its ledger, 2026-09-23). The owner ticked the lane on 2026-09-24 for the two socket-free tasks: Tasks 1 and 3 carry `**Executor:** codex gpt-6-sol / medium` (the `codex-assignment` row for total 3); Tasks 2 and 4 stay on Claude because their tests bind sockets. Task 1's tests spawn `git` and write temporary directories, which the sandbox may also refuse; a BLOCKED run hands the task back to its Claude implementer.
- Review: round 1 (codex gpt-6-astra / xhigh, 15 / 13 / 10 / 14) raised 2 Critical and 18 Important findings, all fixed; round 2 (judge-opus) confirmed every one addressed and raised 2 Important and 3 Minor findings — a 404 escaping the push 409 fallback, and a check-then-act lock takeover — which were fixed and re-tested after the round. The review cap (2) is reached, so no third round ran.

## Task index

1. Mode and run key
2. darkmem client and stub
3. Mirror layout and state
4. The darkmem-sync command
5. pull
6. push and status
7. import
8. Release 1.22.0

---

### Task 1: Mode and run key

**Files:**
- Create: `plugins/dr-superpowers/scripts/lib/darkmem-config.mjs`
- Create: `plugins/dr-superpowers/tests/darkmem-sync/helpers.mjs`
- Test: `plugins/dr-superpowers/tests/darkmem-sync/config.test.mjs`

**Interfaces:**
- Consumes: nothing.
- Produces: Contracts → **darkmem-config.mjs** and the `helpers.mjs` half of **Test fixtures**.

**Implementer:** dr-superpowers:impl-sonnet-high
**Executor:** codex gpt-6-sol / medium
**Evaluation:** files 1 - spec 0 - coupling 2 - risk 0 = 3

- [ ] **Step 1: Write the fixtures and the failing test**

Create `plugins/dr-superpowers/tests/darkmem-sync/helpers.mjs`:

```js
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
```

Create `plugins/dr-superpowers/tests/darkmem-sync/config.test.mjs`:

```js
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { ConfigError, resolveMode, runKey } from "../../scripts/lib/darkmem-config.mjs";
import { git, makeHome, makeRepo, scratch } from "./helpers.mjs";

test("no config file is local mode on the repository's own paths", () => {
  const repo = makeRepo();
  const { env } = makeHome({ repo, config: null });
  const mode = resolveMode({ cwd: repo, env });
  assert.equal(mode.mode, "local");
  assert.match(mode.reason, /^no .*config\.json$/);
  assert.equal(mode.docsRoot, path.join(repo, "docs", "superpowers"));
  assert.equal(mode.workRoot, path.join(repo, ".superpowers"));
});

test("a mapped repository with its key set is darkmem mode on the mirror", () => {
  const repo = makeRepo();
  const { home, env } = makeHome({ repo, url: "http://darkmem.test:8000/", project: "proj" });
  const mode = resolveMode({ cwd: repo, env });
  const mirror = path.join(home, ".dr-superpowers", "mirror", "proj");
  assert.equal(mode.mode, "darkmem");
  assert.equal(mode.project, "proj");
  assert.equal(mode.url, "http://darkmem.test:8000");
  assert.equal(mode.apiKey, "dmk_test_secret");
  assert.equal(mode.mirror, mirror);
  assert.equal(mode.docsRoot, path.join(mirror, "superpowers"));
  assert.equal(mode.workRoot, path.join(mirror, "work"));
  assert.equal(mode.statePath, path.join(mirror, ".sync-state.json"));
});

test("a linked worktree resolves through its primary checkout's mapping", () => {
  const repo = makeRepo();
  const { env } = makeHome({ repo });
  const worktree = path.join(scratch("dms-wt-"), "wt");
  git(repo, "worktree", "add", "-q", "-b", "wt", worktree);
  assert.equal(resolveMode({ cwd: worktree, env }).mode, "darkmem");
});

test("a missing key, an unmapped repository and no git repository are local mode", () => {
  const repo = makeRepo();
  const { env } = makeHome({ repo });
  delete env.DARKMEM_API_KEY;
  assert.deepEqual([resolveMode({ cwd: repo, env }).mode, resolveMode({ cwd: repo, env }).reason], ["local", "DARKMEM_API_KEY is not set"]);
  const other = makeRepo();
  assert.match(resolveMode({ cwd: other, env: makeHome({ repo }).env }).reason, /^no darkmem mapping for /);
  const plain = scratch("dms-plain-");
  assert.equal(resolveMode({ cwd: plain, env }).reason, "not inside a git repository");
});

test("a malformed config file, a climbing project or a bad url is a ConfigError", () => {
  const repo = makeRepo();
  assert.throws(() => resolveMode({ cwd: repo, env: makeHome({ repo, config: "{not json" }).env }), ConfigError);
  assert.throws(() => resolveMode({ cwd: repo, env: makeHome({ repo, project: "../up" }).env }), /needs a project/);
  assert.throws(() => resolveMode({ cwd: repo, env: makeHome({ repo, url: "darkmem.test" }).env }), /darkmem\.url/);
});

test("the run key prefers the declared id, then the session record, then a day key", () => {
  const repo = makeRepo();
  const { home, env } = makeHome({ repo });
  assert.equal(runKey({ cwd: repo, env }), "sess-1");
  delete env.DR_SUPERPOWERS_SESSION_ID;
  const now = new Date("2026-09-24T10:00:00Z");
  assert.equal(runKey({ cwd: repo, env, now }), `codex:${os.hostname()}:2026-09-24`);
  const sessions = path.join(home, ".claude", "dr-superpowers", "sessions");
  fs.mkdirSync(sessions, { recursive: true });
  fs.writeFileSync(path.join(sessions, `${repo.replace(/[^A-Za-z0-9]/g, "-")}.json`), JSON.stringify({ session_id: "abc-123" }));
  assert.equal(runKey({ cwd: repo, env, now }), "abc-123");
});
```

- [ ] **Step 2: Run it to verify it fails**

```bash
timeout 120 node --test --test-reporter=spec plugins/dr-superpowers/tests/darkmem-sync/config.test.mjs
```

Expected: FAIL with `ERR_MODULE_NOT_FOUND` naming `darkmem-config.mjs`.

- [ ] **Step 3: Write the module**

Create `plugins/dr-superpowers/scripts/lib/darkmem-config.mjs`:

```js
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
```

- [ ] **Step 4: Run it to verify it passes**

```bash
timeout 120 node --test --test-reporter=spec plugins/dr-superpowers/tests/darkmem-sync/config.test.mjs
```

Expected: `ℹ pass 6`, `ℹ fail 0`.

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-superpowers/scripts/lib/darkmem-config.mjs plugins/dr-superpowers/tests/darkmem-sync/helpers.mjs plugins/dr-superpowers/tests/darkmem-sync/config.test.mjs
git commit -m "feat(superpowers): resolve darkmem mode and run key" -m "Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

### Task 2: darkmem client and stub

**Files:**
- Create: `plugins/dr-superpowers/scripts/lib/darkmem-client.mjs`
- Create: `plugins/dr-superpowers/tests/darkmem-sync/stub-server.mjs`
- Test: `plugins/dr-superpowers/tests/darkmem-sync/client.test.mjs`

**Interfaces:**
- Consumes: nothing.
- Produces: Contracts → **darkmem-client.mjs**, **darkmem routes**, and the `stub-server.mjs` half of **Test fixtures**.

**Implementer:** dr-superpowers:impl-sonnet-high
**Evaluation:** files 1 - spec 0 - coupling 2 - risk 0 = 3

- [ ] **Step 1: Write the stub and the failing test**

The stub is the test's stand-in for darkmem, so it is written first and in full. Create `plugins/dr-superpowers/tests/darkmem-sync/stub-server.mjs`:

```js
// An in-memory stand-in for the darkmem routes darkmem-sync calls, faithful to
// the contract points the sync relies on: content_hash is SHA-256 of the UTF-8
// content; a stale or absent expected_hash is a 409; an append needs a run key,
// holds 1-100 entries of 1-65,536 characters, and reopens a closed workstream;
// every list is keyset-paged. db.failures injects answers: {method, path,
// status, detail, commit}, where commit: true applies the request first and
// then answers the failure, which is what a lost response looks like.
import crypto from "node:crypto";
import http from "node:http";

export const STUB_KEY = "dmk_test_secret";

export const sha = text => crypto.createHash("sha256").update(text, "utf8").digest("hex");

// A document as the stub stores it, for a test that plants one directly.
export function storedDocument(project, uri, content) {
  return { id: crypto.randomUUID(), project, uri, content, content_hash: sha(content), updated_at: new Date().toISOString() };
}

// pageSize caps every page, to exercise paging. transformContent rewrites a
// document's content as it is stored, to simulate a server that alters bytes.
// onRequest(request, db) runs before each authenticated request is answered,
// to simulate another client or a local edit landing mid-sync.
export async function startStub({ pageSize, transformContent, onRequest } = {}) {
  const db = { documents: new Map(), workstreams: [], requests: [], failures: [], nextSeq: 1, clock: Date.now() };
  const tick = () => new Date((db.clock += 1000)).toISOString();
  const docKey = (project, uri) => `${project}\u0000${uri}`;
  const limitOf = (url, fallback) => {
    const asked = Number(url.searchParams.get("limit") ?? fallback);
    return pageSize ? Math.min(asked, pageSize) : asked;
  };
  const wsOut = ws => ({
    id: ws.id, project: ws.project, key: ws.key, title: ws.title, client: ws.client, state: ws.state,
    closed_at: ws.closed_at, retain: ws.retain, properties: ws.properties, last_entry_at: ws.last_entry_at,
    created_at: ws.created_at, updated_at: ws.updated_at,
  });
  const entryOut = (ws, e) => ({
    id: e.id, workstream_id: ws.id, seq: e.seq, run_key: e.run_key, kind: e.kind, body: e.body,
    properties: e.properties, created_at: e.created_at,
  });

  function route(method, url, body, send) {
    const q = url.searchParams;
    const p = url.pathname;
    let m;
    if (method === "GET" && p === "/api/v1/documents/manifest") {
      const project = q.get("project");
      const prefix = (q.get("uri_prefix") ?? "").replace(/\/+$/, "");
      const after = q.get("after");
      const limit = limitOf(url, 500);
      const items = [...db.documents.values()]
        .filter(d => d.project === project && (prefix === "" || d.uri === prefix || d.uri.startsWith(`${prefix}/`)) && (after === null || d.uri > after))
        .sort((a, b) => (a.uri < b.uri ? -1 : a.uri > b.uri ? 1 : 0))
        .slice(0, limit)
        .map(d => ({ id: d.id, uri: d.uri, content_hash: d.content_hash, updated_at: d.updated_at }));
      return send(200, { items, next_after: items.length === limit ? items.at(-1).uri : null });
    }
    if (method === "GET" && p === "/api/v1/documents/by-uri") {
      const doc = db.documents.get(docKey(q.get("project"), q.get("uri")));
      if (!doc) return send(404, { detail: "Document not found" });
      const answer = { document_id: doc.id, blocks: [], content_hash: doc.content_hash, horizon: true };
      if (q.get("include_content") === "true") answer.content = doc.content;
      return send(200, answer);
    }
    if (method === "POST" && p === "/api/v1/documents") {
      if (typeof body?.content !== "string" || body.content.length === 0) return send(422, { detail: "content must not be empty" });
      const key = docKey(body.project, body.uri);
      const existing = db.documents.get(key);
      const content = transformContent ? transformContent(body.content) : body.content;
      const hash = sha(content);
      if (body.expected_hash !== undefined && body.expected_hash !== null && (!existing || existing.content_hash !== body.expected_hash)) {
        return send(409, { detail: `expected_hash ${body.expected_hash} does not match the document's current content_hash ${existing?.content_hash ?? null}` });
      }
      const outcome = !existing ? "created" : existing.content_hash === hash ? "unchanged" : "updated";
      const doc = existing ?? { id: crypto.randomUUID(), project: body.project, uri: body.uri };
      if (outcome !== "unchanged") Object.assign(doc, { content, content_hash: hash, updated_at: tick() });
      db.documents.set(key, doc);
      return send(201, {
        document_id: doc.id, outcome, blocks_filed: 0, blocks_embedded: 0, title_applied: outcome !== "unchanged",
        oversized_blocks: null, largest_block_chars: null, content_hash: doc.content_hash,
      });
    }
    if (method === "POST" && p === "/api/v1/worklog/entries") {
      if (!body?.run_key) return send(422, { detail: "a work-log entry needs a declared agent-run identity" });
      if (!Array.isArray(body.entries) || body.entries.length < 1 || body.entries.length > 100) {
        return send(422, { detail: "entries must hold 1 to 100 items" });
      }
      for (const e of body.entries) {
        if (!["checkpoint", "ledger", "note"].includes(e.kind)) return send(422, { detail: `unknown kind ${e.kind}` });
        const chars = [...(e.body ?? "")].length;
        if (chars < 1 || chars > 65536) return send(422, { detail: `body must hold 1 to 65536 characters, got ${chars}` });
      }
      const now = tick();
      let ws = db.workstreams.find(w => w.project === body.project && w.key === body.workstream);
      if (!ws) {
        ws = {
          id: crypto.randomUUID(), project: body.project, key: body.workstream, title: body.title ?? null,
          client: body.client ?? null, state: "open", closed_at: null, retain: false, properties: {}, entries: [],
          created_at: now, updated_at: now, last_entry_at: now,
        };
        db.workstreams.push(ws);
      }
      if (ws.state === "closed") Object.assign(ws, { state: "open", closed_at: null });
      Object.assign(ws.properties, body.properties ?? {});
      const ids = body.entries.map(e => {
        const entry = { id: crypto.randomUUID(), seq: db.nextSeq++, run_key: body.run_key, kind: e.kind, body: e.body, properties: e.properties ?? {}, created_at: now };
        ws.entries.push(entry);
        return entry.id;
      });
      Object.assign(ws, { last_entry_at: now, updated_at: now });
      return send(201, { workstream: wsOut(ws), entry_ids: ids });
    }
    if (method === "GET" && p === "/api/v1/worklog/resume") {
      const ws = db.workstreams.find(w => w.project === q.get("project") && w.key === q.get("workstream"));
      if (!ws) return send(404, { detail: "No workstream with that key in that project" });
      const of = kind => ws.entries.filter(e => e.kind === kind);
      const checkpoints = of("checkpoint");
      const notes = of("note");
      return send(200, {
        workstream: wsOut(ws),
        checkpoint: checkpoints.length ? entryOut(ws, checkpoints.at(-1)) : null,
        notes: notes.slice(-50).map(e => entryOut(ws, e)),
        notes_truncated: notes.length > 50,
        ledger: of("ledger").slice(-20).map(e => entryOut(ws, e)),
      });
    }
    if (method === "GET" && p === "/api/v1/worklog/workstreams") {
      const state = q.get("state");
      const before = q.get("before");
      const limit = limitOf(url, 50);
      const all = db.workstreams.filter(w => w.project === q.get("project") && (!state || w.state === state)).reverse();
      const start = before ? all.findIndex(w => w.id === before) + 1 : 0;
      const items = all.slice(start, start + limit);
      return send(200, { items: items.map(wsOut), next_before: items.length === limit ? items.at(-1).id : null });
    }
    if (method === "GET" && (m = p.match(/^\/api\/v1\/worklog\/workstreams\/([^/]+)\/entries$/))) {
      const ws = db.workstreams.find(w => w.id === m[1]);
      if (!ws) return send(404, { detail: "No such workstream" });
      const kind = q.get("kind");
      const after = q.get("after") === null ? 0 : Number(q.get("after"));
      const limit = limitOf(url, 100);
      const items = ws.entries.filter(e => (!kind || e.kind === kind) && e.seq > after).slice(0, limit);
      return send(200, { items: items.map(e => entryOut(ws, e)), next_after: items.length === limit ? items.at(-1).seq : null });
    }
    if ((m = p.match(/^\/api\/v1\/worklog\/workstreams\/([^/]+)$/))) {
      const index = db.workstreams.findIndex(w => w.id === m[1]);
      if (index < 0) return send(404, { detail: "No such workstream" });
      const ws = db.workstreams[index];
      if (method === "PATCH") {
        if (body?.state) Object.assign(ws, { state: body.state, closed_at: body.state === "closed" ? tick() : null });
        if (typeof body?.retain === "boolean") ws.retain = body.retain;
        if (typeof body?.title === "string") ws.title = body.title;
        if (body?.properties) Object.assign(ws.properties, body.properties);
        return send(200, wsOut(ws));
      }
      if (method === "DELETE") {
        db.workstreams.splice(index, 1);
        return send(204);
      }
    }
    return send(404, { detail: `stub has no route ${method} ${p}` });
  }

  const server = http.createServer((req, res) => {
    let raw = "";
    req.setEncoding("utf8");
    req.on("data", chunk => { raw += chunk; });
    req.on("end", () => {
      const url = new URL(req.url, "http://stub");
      const send = (status, payload) => {
        res.writeHead(status, { "Content-Type": "application/json" });
        res.end(payload === undefined ? "" : JSON.stringify(payload));
      };
      let body;
      try {
        body = raw ? JSON.parse(raw) : undefined;
      } catch {
        return send(400, { detail: "body is not JSON" });
      }
      const request = { method: req.method, path: url.pathname, query: Object.fromEntries(url.searchParams), headers: req.headers, body };
      db.requests.push(request);
      if (req.headers.authorization !== `Bearer ${STUB_KEY}`) return send(401, { detail: "Not authenticated" });
      if (onRequest) onRequest(request, db);
      const injected = db.failures.findIndex(f => f.method === req.method && url.pathname.startsWith(f.path));
      if (injected >= 0) {
        const [failure] = db.failures.splice(injected, 1);
        if (failure.commit) route(req.method, url, body, () => {});
        return send(failure.status, { detail: failure.detail ?? "injected failure" });
      }
      return route(req.method, url, body, send);
    });
  });
  await new Promise(resolve => server.listen(0, "127.0.0.1", resolve));
  return {
    url: `http://127.0.0.1:${server.address().port}`,
    db,
    close: () => new Promise(resolve => {
      server.closeAllConnections();
      server.close(() => resolve());
    }),
  };
}
```

Create `plugins/dr-superpowers/tests/darkmem-sync/client.test.mjs`:

```js
import assert from "node:assert/strict";
import http from "node:http";
import test from "node:test";
import { HttpError, TransportError, createClient } from "../../scripts/lib/darkmem-client.mjs";
import { STUB_KEY, startStub } from "./stub-server.mjs";

async function withStub(options, body) {
  const stub = await startStub(options);
  try {
    await body(stub, createClient({ url: stub.url, apiKey: STUB_KEY, runKey: "run-1", timeoutMs: 3000 }));
  } finally {
    await stub.close();
  }
}

test("every call carries the key and names the client; an append declares the run", () => withStub({}, async (stub, client) => {
  await client.append({ project: "p", workstream: "w", entries: [{ kind: "ledger", body: "line\n" }], properties: { plan_uri: "superpowers/plans/w.md" } });
  const [request] = stub.db.requests;
  assert.equal(request.headers.authorization, `Bearer ${STUB_KEY}`);
  assert.equal(request.headers["x-darkmem-client"], "dr-superpowers");
  assert.equal(request.body.run_key, "run-1");
  assert.equal(request.body.client, "dr-superpowers");
  assert.deepEqual(request.body.properties, { plan_uri: "superpowers/plans/w.md" });
}));

test("a filed document reads back with its content and hash", () => withStub({}, async (stub, client) => {
  const put = await client.putDocument({ project: "p", uri: "superpowers/specs/a.md", content: "# A\n" });
  assert.equal(put.outcome, "created");
  const doc = await client.getDocument("p", "superpowers/specs/a.md");
  assert.equal(doc.content, "# A\n");
  assert.equal(doc.content_hash, put.content_hash);
  assert.equal("expected_hash" in stub.db.requests[0].body, false);
}));

test("a stale expected hash is an HttpError 409", () => withStub({}, async (stub, client) => {
  await client.putDocument({ project: "p", uri: "superpowers/a.md", content: "one" });
  await assert.rejects(
    client.putDocument({ project: "p", uri: "superpowers/a.md", content: "two", expectedHash: "0".repeat(64) }),
    error => error instanceof HttpError && error.status === 409,
  );
}));

test("manifest, workstreams and entries follow every page", () => withStub({ pageSize: 2 }, async (stub, client) => {
  for (const name of ["a", "b", "c", "d", "e"]) {
    await client.putDocument({ project: "p", uri: `superpowers/${name}.md`, content: name });
    await client.append({ project: "p", workstream: `w${name}`, entries: [{ kind: "ledger", body: name }] });
  }
  await client.putDocument({ project: "p", uri: "other/x.md", content: "x" });
  assert.deepEqual((await client.manifest("p", "superpowers")).map(i => i.uri), ["a", "b", "c", "d", "e"].map(n => `superpowers/${n}.md`));
  assert.equal((await client.workstreams("p", "open")).length, 5);
  const ws = (await client.resume("p", "wa")).workstream;
  await client.append({ project: "p", workstream: "wa", entries: ["2", "3", "4", "5"].map(body => ({ kind: "ledger", body })) });
  assert.equal((await client.entries(ws.id, "ledger")).map(e => e.body).join(""), "a2345");
}));

test("resume on an absent workstream is null; purge removes one", () => withStub({}, async (stub, client) => {
  assert.equal(await client.resume("p", "absent"), null);
  const { workstream } = await client.append({ project: "p", workstream: "w", entries: [{ kind: "note", body: "n" }] });
  assert.equal((await client.updateWorkstream(workstream.id, { state: "closed", retain: true })).state, "closed");
  assert.equal(await client.purgeWorkstream(workstream.id), null);
  assert.equal(await client.resume("p", "w"), null);
}));

test("a refused connection and a silent server are TransportErrors within the timeout", async () => {
  const refused = createClient({ url: "http://127.0.0.1:9", apiKey: "k", runKey: "r", timeoutMs: 2000 });
  await assert.rejects(refused.manifest("p", "superpowers"), TransportError);
  const silent = http.createServer(() => {});
  await new Promise(resolve => silent.listen(0, "127.0.0.1", resolve));
  try {
    const client = createClient({ url: `http://127.0.0.1:${silent.address().port}`, apiKey: "k", runKey: "r", timeoutMs: 300 });
    const started = Date.now();
    await assert.rejects(client.manifest("p", "superpowers"), /no answer within 300 ms/);
    assert.ok(Date.now() - started < 3000);
  } finally {
    silent.closeAllConnections();
    await new Promise(resolve => silent.close(resolve));
  }
});
```

- [ ] **Step 2: Run it to verify it fails**

```bash
timeout 120 node --test --test-reporter=spec plugins/dr-superpowers/tests/darkmem-sync/client.test.mjs
```

Expected: FAIL with `ERR_MODULE_NOT_FOUND` naming `darkmem-client.mjs`.

- [ ] **Step 3: Write the client**

Create `plugins/dr-superpowers/scripts/lib/darkmem-client.mjs`:

```js
// The keyed REST surface darkmem serves a mirror (work-log lane spec §2): the
// work-log routes, POST /documents, GET /documents/by-uri and the manifest.
// Every call carries the API key, names this client, and gives up after a
// bounded timeout.
export class TransportError extends Error {}

export class HttpError extends Error {
  constructor(method, route, status, detail) {
    super(`${method} ${route} answered ${status}: ${detail}`);
    this.status = status;
    this.detail = detail;
  }
}

const CLIENT = "dr-superpowers";

export function createClient({ url, apiKey, runKey, timeoutMs = 10000, fetchImpl = globalThis.fetch }) {
  async function call(method, route, { query = {}, body } = {}) {
    const target = new URL(`${url}${route}`);
    for (const [name, value] of Object.entries(query)) {
      if (value !== undefined && value !== null) target.searchParams.set(name, String(value));
    }
    const headers = { Authorization: `Bearer ${apiKey}`, "X-Darkmem-Client": CLIENT, Accept: "application/json" };
    if (body !== undefined) headers["Content-Type"] = "application/json";
    let response;
    let text;
    try {
      response = await fetchImpl(target, {
        method,
        headers,
        body: body === undefined ? undefined : JSON.stringify(body),
        signal: AbortSignal.timeout(timeoutMs),
      });
      text = await response.text();
    } catch (error) {
      const reason = error?.name === "TimeoutError"
        ? `no answer within ${timeoutMs} ms`
        : (error?.cause?.message ?? error?.message ?? String(error));
      throw new TransportError(`${method} ${route}: ${reason}`);
    }
    let data = null;
    if (text) {
      try {
        data = JSON.parse(text);
      } catch {
        data = null;
      }
    }
    if (!response.ok) {
      const detail = typeof data?.detail === "string"
        ? data.detail
        : data?.detail !== undefined ? JSON.stringify(data.detail) : text.slice(0, 300);
      throw new HttpError(method, route, response.status, detail);
    }
    return data;
  }

  return {
    async manifest(project, uriPrefix) {
      const items = [];
      let after;
      do {
        const page = await call("GET", "/api/v1/documents/manifest", { query: { project, uri_prefix: uriPrefix, after, limit: 1000 } });
        items.push(...page.items);
        after = page.next_after;
      } while (after);
      return items;
    },
    getDocument(project, uri) {
      return call("GET", "/api/v1/documents/by-uri", { query: { project, uri, include_content: "true" } });
    },
    putDocument({ project, uri, content, expectedHash }) {
      const body = { project, uri, content };
      if (expectedHash) body.expected_hash = expectedHash;
      return call("POST", "/api/v1/documents", { body });
    },
    append({ project, workstream, entries, properties }) {
      const body = { project, workstream, run_key: runKey, client: CLIENT, entries };
      if (properties) body.properties = properties;
      return call("POST", "/api/v1/worklog/entries", { body });
    },
    async resume(project, workstream) {
      try {
        return await call("GET", "/api/v1/worklog/resume", { query: { project, workstream } });
      } catch (error) {
        if (error instanceof HttpError && error.status === 404) return null;
        throw error;
      }
    },
    async workstreams(project, state) {
      const items = [];
      let before;
      do {
        const page = await call("GET", "/api/v1/worklog/workstreams", { query: { project, state, before, limit: 200 } });
        items.push(...page.items);
        before = page.next_before;
      } while (before);
      return items;
    },
    async entries(workstreamId, kind) {
      const items = [];
      let after;
      do {
        const page = await call("GET", `/api/v1/worklog/workstreams/${encodeURIComponent(workstreamId)}/entries`, { query: { kind, after, limit: 500 } });
        items.push(...page.items);
        after = page.next_after;
      } while (after !== null && after !== undefined);
      return items;
    },
    updateWorkstream(id, patch) {
      return call("PATCH", `/api/v1/worklog/workstreams/${encodeURIComponent(id)}`, { body: patch });
    },
    purgeWorkstream(id) {
      return call("DELETE", `/api/v1/worklog/workstreams/${encodeURIComponent(id)}`);
    },
  };
}
```

- [ ] **Step 4: Run it to verify it passes**

```bash
timeout 120 node --test --test-reporter=spec plugins/dr-superpowers/tests/darkmem-sync/client.test.mjs
```

Expected: `ℹ pass 6`, `ℹ fail 0`. The last test takes about 300 ms: it waits out a 300 ms timeout on a server that never answers.

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-superpowers/scripts/lib/darkmem-client.mjs plugins/dr-superpowers/tests/darkmem-sync/stub-server.mjs plugins/dr-superpowers/tests/darkmem-sync/client.test.mjs
git commit -m "feat(superpowers): add the darkmem REST client" -m "Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

### Task 3: Mirror layout and state

**Files:**
- Create: `plugins/dr-superpowers/scripts/lib/darkmem-mirror.mjs`
- Create: `plugins/dr-superpowers/tests/darkmem-sync.test.sh`
- Test: `plugins/dr-superpowers/tests/darkmem-sync/mirror.test.mjs`

**Interfaces:**
- Consumes: `scratch` and `write` from `helpers.mjs` (Task 1).
- Produces: Contracts → **darkmem-mirror.mjs**, **Mirror layout**, **State file**.

**Implementer:** dr-superpowers:impl-sonnet-high
**Executor:** codex gpt-6-sol / medium
**Evaluation:** files 1 - spec 0 - coupling 2 - risk 0 = 3

- [ ] **Step 1: Write the failing test and the suite runner**

Create `plugins/dr-superpowers/tests/darkmem-sync/mirror.test.mjs`:

```js
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import {
  EMPTY_SHA, StateError, acquireLock, checkpointTarget, lockOwner, decodeUtf8, emptyState, ledgerFiles, ledgerPlanPath,
  listDocumentFiles, loadState, localChanges, pathToUri, propertiesFor, saveState, sha256, splitAtBlankLines,
  splitAtLimit, unsupportedPlanDirs, uriToLocal,
} from "../../scripts/lib/darkmem-mirror.mjs";
import { scratch, write } from "./helpers.mjs";

function mirror() {
  const root = scratch("dms-mirror-");
  return { root, roots: { docsRoot: path.join(root, "superpowers"), workRoot: path.join(root, "work") } };
}

test("uris map to the docs root, handoff uris to the plan's directory, and nothing climbs out or names a dotfile", () => {
  const { roots } = mirror();
  assert.equal(uriToLocal(roots, "superpowers/specs/a.md"), path.join(roots.docsRoot, "specs", "a.md"));
  assert.equal(uriToLocal(roots, "superpowers/handoff/p1.md"), path.join(roots.workRoot, "sdd", "p1", "handoff.md"));
  for (const bad of [
    "superpowers/../x.md", "superpowers//a.md", "other/a.md", "superpowers", "superpowers/handoff/a/b.md",
    "superpowers/handoff/x.txt", "superpowers/.hidden.md", "superpowers/notes/.x/a.md",
  ]) {
    assert.equal(uriToLocal(roots, bad), null, bad);
  }
});

test("document files list docs and handoff notes, skip dotfiles, and reserve docs/handoff", () => {
  const { roots } = mirror();
  write(path.join(roots.docsRoot, "specs", "a.md"), "a");
  write(path.join(roots.docsRoot, ".hidden"), "h");
  write(path.join(roots.docsRoot, "handoff", "x.md"), "x");
  write(path.join(roots.workRoot, "sdd", "p1", "handoff.md"), "h");
  write(path.join(roots.workRoot, "sdd", "p1", "progress.md"), "l");
  write(path.join(roots.workRoot, "sdd", "bad name", "progress.md"), "l");
  assert.deepEqual(listDocumentFiles(roots).map(f => f.uri), [null, "superpowers/specs/a.md", "superpowers/handoff/p1.md"]);
  assert.deepEqual(ledgerFiles(roots.workRoot).map(f => f.slug), ["p1"]);
  assert.deepEqual(unsupportedPlanDirs(roots.workRoot), [path.join(roots.workRoot, "sdd", "bad name")]);
});

test("a directory that cannot be read is an error, not an empty listing", () => {
  const { roots } = mirror();
  write(roots.docsRoot, "a file where the docs root should be");
  assert.throws(() => listDocumentFiles(roots), { code: "ENOTDIR" });
  assert.deepEqual(listDocumentFiles({ docsRoot: path.join(roots.docsRoot, "..", "absent"), workRoot: roots.workRoot }), []);
});

test("splitAtLimit cuts after newlines, never splits a surrogate pair, and concatenates back", () => {
  const text = `${"a".repeat(7)}\n${"b".repeat(3)}\n${"c".repeat(12)}`;
  const pieces = splitAtLimit(text, 10);
  assert.equal(pieces.join(""), text);
  assert.ok(pieces.every(p => p.length <= 10));
  assert.equal(pieces[0], `${"a".repeat(7)}\n`);
  const emoji = `${"x".repeat(9)}😀tail`;
  const split = splitAtLimit(emoji, 10);
  assert.equal(split.join(""), emoji);
  assert.equal(split[0], "x".repeat(9));
});

test("splitAtBlankLines keeps each blank line at the end of its piece", () => {
  const text = "# L\n\nTask 1: a\nmore\n\n\nTask 2: b\r\n\r\ntail";
  const pieces = splitAtBlankLines(text);
  assert.equal(pieces.join(""), text);
  assert.deepEqual(pieces, ["# L\n\n", "Task 1: a\nmore\n\n", "\n", "Task 2: b\r\n\r\n", "tail"]);
});

test("decodeUtf8 refuses invalid bytes and keeps a byte order mark", () => {
  assert.equal(decodeUtf8(Buffer.from([0xff, 0xfe, 0x41])), null);
  assert.equal(decodeUtf8(Buffer.from([0xef, 0xbb, 0xbf, 0x41])), "﻿A");
});

test("paths name their uris; plans and drafts name their properties; a handoff note names its target", () => {
  const { roots } = mirror();
  assert.equal(pathToUri("docs/superpowers/plans/p1.md"), "superpowers/plans/p1.md");
  assert.equal(pathToUri("/home/u/.dr-superpowers/mirror/p/superpowers/plans/p1.md"), "superpowers/plans/p1.md");
  assert.equal(pathToUri("/repo/.superpowers/sdd/p1/progress.md"), null);
  assert.equal(ledgerPlanPath("# SDD ledger — plan: docs/superpowers/plans/p1.md\nTask 1: x\n"), "docs/superpowers/plans/p1.md");
  assert.equal(ledgerPlanPath("Task 1: x\n"), null);
  write(path.join(roots.docsRoot, "plans", "p1.md"), "# P\n\n**Spec:** `docs/superpowers/specs/s.md`\n");
  write(path.join(roots.workRoot, "sdd", "p1", "handoff.md"), "h");
  assert.deepEqual(propertiesFor(roots, "p1", "docs/superpowers/plans/p1.md"), {
    plan_uri: "superpowers/plans/p1.md", spec_uri: "superpowers/specs/s.md", handoff_uri: "superpowers/handoff/p1.md",
  });
  assert.deepEqual(propertiesFor(roots, "d-design", "docs/superpowers/specs/d-design.md"), { spec_uri: "superpowers/specs/d-design.md" });
  assert.deepEqual(propertiesFor(roots, "adhoc", null), {});
  assert.deepEqual(
    checkpointTarget("# Handoff\n\n## State\n- Worktree: `/r`\n- Plan: `docs/superpowers/plans/p1.md`; ledger: `x`\n\n## Gotchas\n- Plan: `other.md`\n"),
    { slug: "p1", path: "docs/superpowers/plans/p1.md" },
  );
  assert.deepEqual(checkpointTarget("## State\n- Draft: `docs/superpowers/specs/d-design.md`\n"), { slug: "d-design", path: "docs/superpowers/specs/d-design.md" });
  assert.equal(checkpointTarget("## State\n- a punch list\n## Gotchas\n- Plan: `x.md`\n"), null);
});

test("state round-trips, including keys an ordinary object would inherit", () => {
  const { root } = mirror();
  const file = path.join(root, ".sync-state.json");
  assert.deepEqual(loadState(file), emptyState());
  const state = emptyState();
  state.documents["superpowers/a.md"] = sha256("a");
  for (const slug of ["constructor", "toString", "__proto__"]) state.ledgers[slug] = { offset: 3, prefix: sha256("abc") };
  state.checkpoint = sha256("c");
  state.checkpointAt = "2026-09-24T10:00:00.000Z";
  saveState(file, state);
  const loaded = loadState(file);
  assert.deepEqual(Object.keys(loaded.ledgers).sort(), ["__proto__", "constructor", "toString"]);
  assert.deepEqual(loaded.ledgers.constructor, { offset: 3, prefix: sha256("abc") });
  assert.equal(loaded.documents["superpowers/a.md"], sha256("a"));
  assert.equal(loaded.checkpointAt, "2026-09-24T10:00:00.000Z");
});

test("an unreadable or malformed state file is an error rather than a fresh start", () => {
  const { root } = mirror();
  const file = path.join(root, ".sync-state.json");
  const good = { version: 1, documents: {}, ledgers: {}, checkpoint: null, checkpointAt: null, conflicts: [] };
  for (const bad of [
    "{broken",
    JSON.stringify({ ...good, version: 2 }),
    JSON.stringify({ ...good, documents: null }),
    JSON.stringify({ ...good, documents: { "superpowers/a.md": "not-a-hash" } }),
    JSON.stringify({ ...good, ledgers: { p1: { offset: -1, prefix: EMPTY_SHA } } }),
    JSON.stringify({ ...good, ledgers: { p1: { offset: "3", prefix: EMPTY_SHA } } }),
    JSON.stringify({ ...good, ledgers: { "../x": { offset: 0, prefix: EMPTY_SHA } } }),
    JSON.stringify({ ...good, checkpoint: "x" }),
    JSON.stringify({ ...good, conflicts: [1] }),
  ]) {
    fs.writeFileSync(file, bad);
    assert.throws(() => loadState(file), StateError, bad);
  }
});

test("localChanges names new, modified, unpushed, rewritten, unsupported and checkpoint changes", () => {
  const { roots } = mirror();
  const state = emptyState();
  write(path.join(roots.docsRoot, "a.md"), "a");
  write(path.join(roots.docsRoot, "b.md"), "b");
  state.documents["superpowers/b.md"] = sha256("old");
  write(path.join(roots.workRoot, "sdd", "p1", "progress.md"), "one\ntwo\n");
  state.ledgers.p1 = { offset: 4, prefix: sha256("one\n") };
  write(path.join(roots.workRoot, "sdd", "p2", "progress.md"), "changed\n");
  state.ledgers.p2 = { offset: 4, prefix: sha256("orig") };
  write(path.join(roots.workRoot, "sdd", "bad name", "handoff.md"), "h");
  write(path.join(roots.workRoot, "handoff", "latest.md"), "# H\n");
  assert.deepEqual(localChanges(roots, state), [
    "new: superpowers/a.md",
    "modified: superpowers/b.md",
    "unpushed: sdd/p1/progress.md (4 bytes)",
    "rewritten: sdd/p2/progress.md",
    `unsupported: ${path.join(roots.workRoot, "sdd", "bad name")} (not a usable workstream key)`,
    "modified: handoff/latest.md",
  ]);
  assert.equal(EMPTY_SHA, sha256(""));
});

test("the lock admits one holder, waits on a live one however old, and takes over a dead one", () => {
  const { root } = mirror();
  const lock = path.join(root, ".sync.lock");
  const release = acquireLock(root);
  assert.equal(typeof release, "function");
  assert.equal(lockOwner(root).pid, process.pid);
  assert.equal(acquireLock(root), null);
  const old = new Date(Date.now() - 60 * 60 * 1000);
  fs.utimesSync(lock, old, old);
  assert.equal(acquireLock(root), null, "this process is alive, so its lock is not stale");
  const dead = spawnSync(process.execPath, ["-e", ""]).pid;
  fs.writeFileSync(path.join(lock, "owner.json"), JSON.stringify({ pid: dead, host: os.hostname(), token: "t" }));
  const successor = acquireLock(root);
  assert.equal(typeof successor, "function");
  release();
  assert.equal(fs.existsSync(lock), true, "a displaced holder's release leaves its successor's lock");
  successor();
  assert.equal(fs.existsSync(lock), false);
  assert.deepEqual(fs.readdirSync(root), [], "no side directory is left behind");
});

test("two takeovers of one abandoned lock leave exactly one holder", () => {
  const { root } = mirror();
  const lock = path.join(root, ".sync.lock");
  fs.mkdirSync(lock);
  const dead = spawnSync(process.execPath, ["-e", ""]).pid;
  fs.writeFileSync(path.join(lock, "owner.json"), JSON.stringify({ pid: dead, host: os.hostname(), token: "stale" }));
  let first = null;
  const second = acquireLock(root, { beforeTakeover: () => { first ??= acquireLock(root); } });
  assert.equal(typeof first, "function", "the takeover that ran first holds the lock");
  assert.equal(second, null, "the later takeover finds a live lock and backs off");
  assert.equal(fs.existsSync(lock), true);
  first();
  assert.equal(fs.existsSync(lock), false);
  assert.deepEqual(fs.readdirSync(root), []);
});

test("a lock with no owner record is taken over only once it is stale", () => {
  const { root } = mirror();
  const lock = path.join(root, ".sync.lock");
  fs.mkdirSync(lock);
  assert.equal(acquireLock(root), null);
  const old = new Date(Date.now() - 20 * 60 * 1000);
  fs.utimesSync(lock, old, old);
  const release = acquireLock(root);
  assert.equal(typeof release, "function");
  release();
});
```

Create `plugins/dr-superpowers/tests/darkmem-sync.test.sh` (mode 100644, like every other `.test.sh` here — `scripts/test-all.mjs` runs it through bash):

```bash
#!/usr/bin/env bash
# darkmem-sync's suites are JavaScript (node:test); this wrapper is how
# scripts/test-all.mjs, which collects *.test.sh here, finds them.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
command -v node >/dev/null 2>&1 || { echo "darkmem-sync tests: node is required but not on PATH" >&2; exit 2; }
exec node --test --test-reporter=spec --test-timeout=60000 "$HERE"/darkmem-sync/*.test.mjs
```

- [ ] **Step 2: Run it to verify it fails**

```bash
timeout 120 node --test --test-reporter=spec plugins/dr-superpowers/tests/darkmem-sync/mirror.test.mjs
```

Expected: FAIL with `ERR_MODULE_NOT_FOUND` naming `darkmem-mirror.mjs`.

- [ ] **Step 3: Write the module**

Create `plugins/dr-superpowers/scripts/lib/darkmem-mirror.mjs`:

```js
// The mirror's layout and bookkeeping (darkmem mirror spec §2-§3): which file a
// document uri lives at, the sync state, the lock, and how text is cut into
// work-log entries. Filesystem only; nothing here speaks HTTP.
import crypto from "node:crypto";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

export const DOC_PREFIX = "superpowers";
export const MAX_ENTRY_CHARS = 65536;
export const MAX_ENTRIES_PER_APPEND = 100;
export const EMPTY_SHA = sha256(Buffer.alloc(0));
const HANDOFF_DIR = "handoff";
const KEY = /^[A-Za-z0-9._-]{1,200}$/;
const HASH = /^[0-9a-f]{64}$/;
const REBUILD = "move it aside to rebuild it from darkmem";

export class StateError extends Error {}
export class UsageError extends Error {}

export function sha256(data) {
  return crypto.createHash("sha256").update(data).digest("hex");
}

// A workstream key doubles as a directory name under work/sdd/.
export function validKey(key) {
  return typeof key === "string" && KEY.test(key) && key !== "." && key !== "..";
}

// uri -> absolute file. `superpowers/handoff/<slug>.md` is reserved for a
// plan's handoff.md, which lives beside its ledger; any other
// `superpowers/<path>` lives under the docs root. A uri that would climb out
// of the mirror, or name a dotfile, maps nowhere: dotfiles are never synced.
export function uriToLocal(roots, uri) {
  const parts = String(uri).split("/");
  if (parts[0] !== DOC_PREFIX || parts.length < 2) return null;
  if (parts.slice(1).some(part => part === "" || part.startsWith(".") || part.includes("\\"))) return null;
  if (parts[1] === HANDOFF_DIR) {
    if (parts.length !== 3 || !parts[2].endsWith(".md")) return null;
    const slug = parts[2].slice(0, -3);
    return validKey(slug) ? path.join(roots.workRoot, "sdd", slug, "handoff.md") : null;
  }
  return path.join(roots.docsRoot, ...parts.slice(1));
}

// A missing directory is empty; any other failure to read one is an error,
// because a silently empty listing would read as "nothing to sync".
function sortedEntries(dir) {
  let entries;
  try {
    entries = fs.readdirSync(dir, { withFileTypes: true });
  } catch (error) {
    if (error.code === "ENOENT") return [];
    throw error;
  }
  return entries.sort((a, b) => (a.name < b.name ? -1 : a.name > b.name ? 1 : 0));
}

function planDirs(workRoot) {
  const sdd = path.join(workRoot, "sdd");
  return sortedEntries(sdd)
    .filter(entry => entry.isDirectory() && validKey(entry.name))
    .map(entry => ({ slug: entry.name, dir: path.join(sdd, entry.name) }));
}

// Plan directories holding a ledger or handoff note under a name that cannot
// be a workstream key; callers report them rather than skip them silently.
export function unsupportedPlanDirs(workRoot) {
  const sdd = path.join(workRoot, "sdd");
  return sortedEntries(sdd)
    .filter(entry => entry.isDirectory() && !validKey(entry.name))
    .map(entry => path.join(sdd, entry.name))
    .filter(dir => fs.existsSync(path.join(dir, "progress.md")) || fs.existsSync(path.join(dir, "handoff.md")));
}

// Every document file the mirror syncs, with its uri: files under the docs
// root, then each plan's handoff.md. Dotfiles are never synced. A file under
// the docs root's handoff/ directory gets uri null: that uri space belongs to
// the handoff notes.
export function listDocumentFiles(roots) {
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
  walk(roots.docsRoot, []);
  for (const { slug, dir } of planDirs(roots.workRoot)) {
    const file = path.join(dir, "handoff.md");
    if (fs.existsSync(file)) found.push({ file, uri: `${DOC_PREFIX}/${HANDOFF_DIR}/${slug}.md` });
  }
  return found;
}

export function ledgerFiles(workRoot) {
  return planDirs(workRoot)
    .map(({ slug, dir }) => ({ slug, file: path.join(dir, "progress.md") }))
    .filter(({ file }) => fs.existsSync(file));
}

// documents and ledgers are keyed by uri and slug, which may be any valid key
// ("constructor", "__proto__"), so both are prototype-free dictionaries.
export function emptyState() {
  return { version: 1, documents: Object.create(null), ledgers: Object.create(null), checkpoint: null, checkpointAt: null, conflicts: [] };
}

function dictOf(value, check) {
  if (value === null || typeof value !== "object" || Array.isArray(value)) return null;
  const dict = Object.create(null);
  for (const [key, entry] of Object.entries(value)) {
    if (!check(key, entry)) return null;
    dict[key] = entry;
  }
  return dict;
}

const isHash = value => typeof value === "string" && HASH.test(value);
const isLedgerRecord = (slug, record) => validKey(slug) && record !== null && typeof record === "object"
  && Number.isSafeInteger(record.offset) && record.offset >= 0 && isHash(record.prefix)
  && (record.pending === undefined || typeof record.pending === "boolean");

// A missing state file is a fresh mirror. An unreadable or malformed one is an
// error, not a fresh start: forgetting a ledger's offset would re-send lines.
export function loadState(file) {
  if (!fs.existsSync(file)) return emptyState();
  let raw;
  try {
    raw = JSON.parse(fs.readFileSync(file, "utf8"));
  } catch (error) {
    throw new StateError(`${file} is unreadable (${error.message}); ${REBUILD}`);
  }
  const documents = dictOf(raw?.documents, (uri, hash) => isHash(hash));
  const ledgers = dictOf(raw?.ledgers, isLedgerRecord);
  const valid = raw?.version === 1 && documents && ledgers
    && (raw.checkpoint === null || isHash(raw.checkpoint))
    && (raw.checkpointAt === null || (typeof raw.checkpointAt === "string" && !Number.isNaN(Date.parse(raw.checkpointAt))))
    && Array.isArray(raw.conflicts) && raw.conflicts.every(line => typeof line === "string");
  if (!valid) throw new StateError(`${file} does not hold a valid sync state; ${REBUILD}`);
  return { version: 1, documents, ledgers, checkpoint: raw.checkpoint, checkpointAt: raw.checkpointAt, conflicts: raw.conflicts };
}

// The temporary file is a dotfile, so a crash between write and rename never
// leaves something the document listing would sync.
export function writeFileAtomic(file, data) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  const temporary = path.join(path.dirname(file), `.${path.basename(file)}.tmp`);
  fs.writeFileSync(temporary, data);
  fs.renameSync(temporary, file);
}

export function saveState(file, state) {
  writeFileAtomic(file, `${JSON.stringify(state, null, 2)}\n`);
}

function processAlive(pid) {
  try {
    process.kill(pid, 0);
    return true;
  } catch (error) {
    return error.code === "EPERM";
  }
}

function readOwner(lock) {
  try {
    return JSON.parse(fs.readFileSync(path.join(lock, "owner.json"), "utf8"));
  } catch {
    return null;
  }
}

// Who holds the mirror's lock, for the message a refused sync prints.
export function lockOwner(dir) {
  return readOwner(path.join(dir, ".sync.lock"));
}

// A lock is abandoned when the process that took it on this host is gone. A
// lock with no readable owner (a crash between mkdir and the owner write), or
// taken on another host, is abandoned once older than staleMs.
function lockAbandoned(lock, owner, staleMs) {
  if (owner?.host === os.hostname() && Number.isSafeInteger(owner.pid)) return !processAlive(owner.pid);
  try {
    return Date.now() - fs.statSync(lock).mtimeMs >= staleMs;
  } catch {
    return true;
  }
}

// What makes a lock this lock rather than one taken since: its owner's token,
// or for a lock with no owner record, its modification time.
function lockIdentity(lock) {
  const token = readOwner(lock)?.token;
  if (typeof token === "string") return `token:${token}`;
  try {
    return `mtime:${fs.statSync(lock).mtimeMs}`;
  } catch {
    return null;
  }
}

// One sync per mirror at a time. Returns a release function, or null when a
// live sync holds the lock. Taking over an abandoned lock moves it aside and
// deletes it only if it is still the lock judged abandoned, so two processes
// taking over at once cannot delete each other's fresh lock. The release
// removes the lock only while it still carries this holder's token.
// beforeTakeover is a test seam: it runs between judging a lock abandoned and
// moving it aside.
export function acquireLock(dir, { staleMs = 10 * 60 * 1000, beforeTakeover } = {}) {
  const lock = path.join(dir, ".sync.lock");
  const owner = { pid: process.pid, host: os.hostname(), token: crypto.randomUUID() };
  fs.mkdirSync(dir, { recursive: true });
  for (let attempt = 0; attempt < 3; attempt += 1) {
    try {
      fs.mkdirSync(lock);
    } catch (error) {
      if (error.code !== "EEXIST") throw error;
      if (!lockAbandoned(lock, readOwner(lock), staleMs)) return null;
      const identity = lockIdentity(lock);
      beforeTakeover?.();
      const aside = `${lock}.stale-${owner.token}`;
      try {
        fs.renameSync(lock, aside);
      } catch {
        continue;
      }
      if (lockIdentity(aside) !== identity) {
        // Another process took the lock over first; give its lock back.
        try {
          fs.renameSync(aside, lock);
        } catch {
          fs.rmSync(aside, { recursive: true, force: true });
        }
        return null;
      }
      fs.rmSync(aside, { recursive: true, force: true });
      continue;
    }
    fs.writeFileSync(path.join(lock, "owner.json"), JSON.stringify(owner));
    return () => {
      if (readOwner(lock)?.token === owner.token) fs.rmSync(lock, { recursive: true, force: true });
    };
  }
  return null;
}

// Strict UTF-8, BOM kept, or null: the server stores text, and a lossy decode
// would change the bytes a later pull writes back.
export function decodeUtf8(buffer) {
  try {
    return new TextDecoder("utf-8", { fatal: true, ignoreBOM: true }).decode(buffer);
  } catch {
    return null;
  }
}

// Cut text into pieces of at most `limit` characters, each ending after its
// last newline when it has one, so the pieces concatenate back to the text.
// Counted in UTF-16 units, which never undercounts the server's code points.
export function splitAtLimit(text, limit = MAX_ENTRY_CHARS) {
  const pieces = [];
  let rest = text;
  while (rest.length > limit) {
    let cut = rest.lastIndexOf("\n", limit - 1) + 1;
    if (cut === 0) {
      cut = limit;
      const code = rest.charCodeAt(cut - 1);
      if (code >= 0xd800 && code <= 0xdbff) cut -= 1;
    }
    pieces.push(rest.slice(0, cut));
    rest = rest.slice(cut);
  }
  if (rest.length) pieces.push(rest);
  return pieces;
}

// Import's chunking: a new piece starts after every blank line, the blank
// line staying at the end of the piece before it.
export function splitAtBlankLines(text) {
  return text.split(/(?<=\n\r?\n)/).filter(piece => piece.length > 0);
}

// The darkmem uri a path names: what follows its `superpowers/` segment, so a
// repository path (`docs/superpowers/plans/x.md`) and a mirror path both map.
export function pathToUri(file) {
  const match = String(file).replace(/\\/g, "/").match(/(?:^|\/)superpowers\/(.+)$/);
  return match ? `${DOC_PREFIX}/${match[1]}` : null;
}

// The plan path a ledger's identity line names, or null.
export function ledgerPlanPath(ledgerText) {
  const identity = /^# SDD ledger — plan: (.+)$/.exec(ledgerText.split(/\r?\n/, 1)[0] ?? "");
  return identity ? identity[1].trim() : null;
}

// The workstream properties worklog_resume hands back. `namedPath` is the plan
// or draft the workstream is about: a plan yields plan_uri plus the spec its
// **Spec:** line names; anything else (a draft spec) yields spec_uri. A plan's
// handoff note adds handoff_uri.
export function propertiesFor(roots, slug, namedPath) {
  const properties = {};
  const uri = namedPath ? pathToUri(namedPath) : null;
  if (uri && uri.startsWith(`${DOC_PREFIX}/plans/`)) {
    properties.plan_uri = uri;
    try {
      const spec = /^\*\*Spec:\*\*\s*`?([^`\s]+)`?/m.exec(fs.readFileSync(uriToLocal(roots, uri), "utf8"));
      const specUri = spec ? pathToUri(spec[1]) : null;
      if (specUri) properties.spec_uri = specUri;
    } catch {
      // The plan is not in this mirror; the workstream carries no spec_uri.
    }
  } else if (uri) {
    properties.spec_uri = uri;
  }
  if (fs.existsSync(path.join(roots.workRoot, "sdd", slug, "handoff.md"))) {
    properties.handoff_uri = `${DOC_PREFIX}/${HANDOFF_DIR}/${slug}.md`;
  }
  return properties;
}

// What a handoff note is about: the plan or draft its `## State` section names
// on a `- Plan:` or `- Draft:` line, as {slug, path}, or null.
export function checkpointTarget(text) {
  const state = /^## State[ \t]*\r?\n([\s\S]*?)(?=^## |(?![\s\S]))/m.exec(text);
  if (!state) return null;
  const named = /^- (?:Plan|Draft): `([^`]+)`/m.exec(state[1]);
  if (!named) return null;
  const slug = path.posix.basename(named[1].replace(/\\/g, "/"), ".md");
  return validKey(slug) ? { slug, path: named[1] } : null;
}

// What `status` prints: local changes the last sync did not see.
export function localChanges(roots, state) {
  const lines = [];
  for (const { file, uri } of listDocumentFiles(roots)) {
    if (!uri) {
      lines.push(`reserved: ${path.relative(roots.docsRoot, file)} (the docs root's handoff/ directory is not synced)`);
      continue;
    }
    const recorded = state.documents[uri];
    if (recorded === undefined) lines.push(`new: ${uri}`);
    else if (sha256(fs.readFileSync(file)) !== recorded) lines.push(`modified: ${uri}`);
  }
  for (const { slug, file } of ledgerFiles(roots.workRoot)) {
    const buffer = fs.readFileSync(file);
    const record = state.ledgers[slug];
    if (!record) lines.push(`unpushed: sdd/${slug}/progress.md (${buffer.length} bytes, never synced)`);
    else if (buffer.length < record.offset || sha256(buffer.subarray(0, record.offset)) !== record.prefix) lines.push(`rewritten: sdd/${slug}/progress.md`);
    else if (buffer.length > record.offset) lines.push(`unpushed: sdd/${slug}/progress.md (${buffer.length - record.offset} bytes)`);
  }
  for (const dir of unsupportedPlanDirs(roots.workRoot)) lines.push(`unsupported: ${dir} (not a usable workstream key)`);
  const latest = path.join(roots.workRoot, "handoff", "latest.md");
  if (fs.existsSync(latest) && sha256(fs.readFileSync(latest)) !== state.checkpoint) lines.push("modified: handoff/latest.md");
  return lines;
}
```

- [ ] **Step 4: Run it and the collected suite to verify they pass**

```bash
timeout 120 node --test --test-reporter=spec plugins/dr-superpowers/tests/darkmem-sync/mirror.test.mjs
timeout 300 bash plugins/dr-superpowers/tests/darkmem-sync.test.sh | grep -E '^ℹ (tests|pass|fail)'
timeout 30 node scripts/test-all.mjs --list | grep darkmem
```

Expected: `ℹ pass 13`, `ℹ fail 0`; then `ℹ tests 25`, `ℹ pass 25`, `ℹ fail 0` (config 6, client 6, mirror 13); then `plugins/dr-superpowers/tests/darkmem-sync.test.sh`.

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-superpowers/scripts/lib/darkmem-mirror.mjs plugins/dr-superpowers/tests/darkmem-sync.test.sh plugins/dr-superpowers/tests/darkmem-sync/mirror.test.mjs
git commit -m "feat(superpowers): add the darkmem mirror layout" -m "Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

### Task 4: The darkmem-sync command

**Files:**
- Create: `plugins/dr-superpowers/scripts/darkmem-sync`
- Create: `plugins/dr-superpowers/scripts/lib/darkmem-sync.mjs`
- Test: `plugins/dr-superpowers/tests/darkmem-sync/cli.test.mjs`

**Interfaces:**
- Consumes: Contracts → **darkmem-config.mjs**, **darkmem-client.mjs**, **darkmem-mirror.mjs**; `helpers.mjs`.
- Produces: Contracts → **Command** and the `COMMANDS` registry Tasks 5–7 extend.

**Implementer:** dr-superpowers:impl-sonnet-high
**Evaluation:** files 1 - spec 0 - coupling 2 - risk 0 = 3

- [ ] **Step 1: Write the failing test**

Create `plugins/dr-superpowers/tests/darkmem-sync/cli.test.mjs`:

```js
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import test from "node:test";
import { makeHome, makeRepo, run, write } from "./helpers.mjs";

test("no command, an unknown command or an unknown flag is a usage error", async () => {
  const repo = makeRepo();
  const { env } = makeHome({ repo });
  for (const args of [[], ["sync"], ["status", "--force"]]) {
    const result = await run(args, { cwd: repo, env });
    assert.equal(result.code, 2, args.join(" "));
    assert.match(result.stderr, /^usage: darkmem-sync status/);
  }
});

test("local mode prints one line and succeeds", async () => {
  const repo = makeRepo();
  const { env } = makeHome({ repo, config: null });
  const result = await run(["status"], { cwd: repo, env });
  assert.equal(result.code, 0);
  assert.match(result.stdout, /^darkmem-sync: local mode — no .*config\.json\n$/);
});

test("a malformed config is exit 2 naming the file", async () => {
  const repo = makeRepo();
  const { env } = makeHome({ repo, config: "{nope" });
  const result = await run(["status"], { cwd: repo, env });
  assert.equal(result.code, 2);
  assert.match(result.stderr, /config\.json is not valid JSON/);
});

test("status in darkmem mode names the mirror and its local changes", async () => {
  const repo = makeRepo();
  const { env, mirror, docsRoot, workRoot } = makeHome({ repo });
  write(path.join(docsRoot, "specs", "a.md"), "# A\n");
  write(path.join(workRoot, "sdd", "p1", "progress.md"), "# SDD ledger — plan: docs/superpowers/plans/p1.md\n");
  const result = await run(["status"], { cwd: repo, env });
  assert.equal(result.code, 0, result.stderr);
  assert.equal(result.stdout, [
    `darkmem-sync: darkmem mode — project proj at http://127.0.0.1:9; mirror ${mirror}`,
    "new: superpowers/specs/a.md",
    "unpushed: sdd/p1/progress.md (52 bytes, never synced)",
    "",
  ].join("\n"));
  assert.equal(fs.existsSync(path.join(mirror, ".sync.lock")), false);
});

test("a held lock is exit 1, and an unreadable state file is exit 2", async () => {
  const repo = makeRepo();
  const { env, mirror } = makeHome({ repo });
  fs.mkdirSync(path.join(mirror, ".sync.lock"), { recursive: true });
  const locked = await run(["status"], { cwd: repo, env });
  assert.equal(locked.code, 1);
  assert.match(locked.stderr, /another darkmem-sync \(an unknown process\) holds .*\.sync\.lock; if that process is gone, remove the directory/);
  fs.rmdirSync(path.join(mirror, ".sync.lock"));
  fs.writeFileSync(path.join(mirror, ".sync-state.json"), "{broken");
  const broken = await run(["status"], { cwd: repo, env });
  assert.equal(broken.code, 2);
  assert.match(broken.stderr, /\.sync-state\.json is unreadable/);
  assert.equal(fs.readFileSync(path.join(mirror, ".sync-state.json"), "utf8"), "{broken");
});

test("the lock is released even when the state file cannot be saved", async () => {
  const repo = makeRepo();
  const { env, mirror } = makeHome({ repo });
  fs.mkdirSync(path.join(mirror, "..sync-state.json.tmp"), { recursive: true });
  const failed = await run(["status"], { cwd: repo, env });
  assert.equal(failed.code, 4);
  assert.match(failed.stderr, /unexpected error/);
  assert.equal(fs.existsSync(path.join(mirror, ".sync.lock")), false);
  fs.rmdirSync(path.join(mirror, "..sync-state.json.tmp"));
  assert.equal((await run(["status"], { cwd: repo, env })).code, 0);
});
```

- [ ] **Step 2: Run it to verify it fails**

```bash
timeout 120 node --test --test-reporter=spec plugins/dr-superpowers/tests/darkmem-sync/cli.test.mjs
```

Expected: `ℹ fail 6`; each `run` answers exit 127 because `scripts/darkmem-sync` does not exist.

- [ ] **Step 3: Write the wrapper and the entry module**

Create `plugins/dr-superpowers/scripts/darkmem-sync`:

```bash
#!/usr/bin/env bash
# Keep this repository's dr-superpowers documents and progress in darkmem.
#
# A repository mapped in ~/.dr-superpowers/config.json, with the API key in the
# environment variable that file names, syncs a mirror at
# ~/.dr-superpowers/mirror/<project>/: superpowers/ (specs, plans, registers,
# notes), work/sdd/<plan>/{progress.md,handoff.md}, work/handoff/latest.md.
# Anything else is local mode: every command except import prints one line
# and does nothing.
#
# Usage: darkmem-sync status | pull | push [--workstream KEY] | import [--replace]
# Exit: 0 done; 1 conflicts, refused or failed items, or another sync holds the
#       mirror; 2 usage, a malformed config or state file, or import in local
#       mode; 3 darkmem unreachable, or an answer that stopped the command;
#       4 an unexpected error (a bug)
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
command -v node >/dev/null 2>&1 || { echo "darkmem-sync: node is required but not on PATH" >&2; exit 2; }
exec node "$HERE/lib/darkmem-sync.mjs" "$@"
```

Create `plugins/dr-superpowers/scripts/lib/darkmem-sync.mjs`:

```js
// darkmem-sync's entry point, run by scripts/darkmem-sync: argument parsing,
// mode, lock, state and exit codes. The commands live in darkmem-pull.mjs,
// darkmem-push.mjs and darkmem-import.mjs; scripts/darkmem-sync documents the
// usage and exit codes.
import path from "node:path";
import { ConfigError, resolveMode, runKey } from "./darkmem-config.mjs";
import { HttpError, TransportError, createClient } from "./darkmem-client.mjs";
import { StateError, UsageError, acquireLock, loadState, localChanges, lockOwner, saveState } from "./darkmem-mirror.mjs";

const USAGE = "usage: darkmem-sync status | pull | push [--workstream KEY] | import [--replace]";

async function status({ cfg, roots, state, report, out }) {
  out(`darkmem-sync: darkmem mode — project ${cfg.project} at ${cfg.url}; mirror ${cfg.mirror}`);
  for (const line of localChanges(roots, state)) out(line);
  report.conflicts.push(...(state.conflicts ?? []));
}

// options maps each accepted flag to whether it takes a value. needsDarkmem
// makes local mode a usage error; recordsConflicts keeps this run's conflicts
// in the state file for `status`.
const COMMANDS = {
  status: { options: {}, needsDarkmem: false, recordsConflicts: false, run: status },
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
  let cfg;
  try {
    cfg = resolveMode({ cwd, env });
  } catch (error) {
    if (!(error instanceof ConfigError)) throw error;
    err(`darkmem-sync: ${error.message}`);
    return 2;
  }
  if (cfg.mode === "local") {
    out(`darkmem-sync: local mode — ${cfg.reason}`);
    return parsed.command.needsDarkmem ? 2 : 0;
  }
  const release = acquireLock(cfg.mirror);
  if (!release) {
    const owner = lockOwner(cfg.mirror);
    const holder = owner ? `pid ${owner.pid} on ${owner.host}` : "an unknown process";
    err(`darkmem-sync: another darkmem-sync (${holder}) holds ${path.join(cfg.mirror, ".sync.lock")}; if that process is gone, remove the directory`);
    return 1;
  }
  const report = { conflicts: [], failures: [], notes: [], counts: {} };
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
    const roots = { docsRoot: cfg.docsRoot, workRoot: cfg.workRoot };
    await parsed.command.run({ cfg, roots, state, persist, client, report, options: parsed.options, out });
  } catch (error) {
    if (error instanceof TransportError || error instanceof HttpError) {
      err(`darkmem-sync: ${parsed.name} failed: ${error.message}`);
      code = 3;
    } else if (error instanceof StateError || error instanceof UsageError) {
      err(`darkmem-sync: ${error.message}`);
      code = 2;
    } else {
      throw error;
    }
  } finally {
    try {
      if (state) {
        // A completed run replaces the recorded conflicts; a run that stopped
        // part-way adds what it found, since it never re-checked the rest.
        if (parsed.command.recordsConflicts) {
          state.conflicts = code === 0 ? report.conflicts : [...new Set([...state.conflicts, ...report.conflicts])];
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

Make the wrapper executable, in the working tree and in the index (every script under `scripts/` is mode 100755):

```bash
chmod +x plugins/dr-superpowers/scripts/darkmem-sync
```

- [ ] **Step 4: Run it to verify it passes**

```bash
timeout 120 node --test --test-reporter=spec plugins/dr-superpowers/tests/darkmem-sync/cli.test.mjs
```

Expected: `ℹ pass 6`, `ℹ fail 0`.

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-superpowers/scripts/darkmem-sync plugins/dr-superpowers/scripts/lib/darkmem-sync.mjs plugins/dr-superpowers/tests/darkmem-sync/cli.test.mjs
git update-index --chmod=+x plugins/dr-superpowers/scripts/darkmem-sync
git commit -m "feat(superpowers): add the darkmem-sync command" -m "Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

### Task 5: pull

**Files:**
- Create: `plugins/dr-superpowers/scripts/lib/darkmem-pull.mjs`
- Modify: `plugins/dr-superpowers/scripts/lib/darkmem-sync.mjs` (one import, one `COMMANDS` entry)
- Test: `plugins/dr-superpowers/tests/darkmem-sync/pull.test.mjs`

**Interfaces:**
- Consumes: Contracts → **darkmem-client.mjs**, **darkmem-mirror.mjs**, **Command**, **Test fixtures**.
- Produces: `pull`, `ledgerText`, `pullDocuments` and `pullLedgers` (Contracts → **Command modules**); Task 6 imports `ledgerText`, Task 7 imports `pullDocuments` and `pullLedgers`.

**Items:** 1

**Implementer:** dr-superpowers:impl-opus-medium
**Evaluation:** files 1 - spec 0 - coupling 2 - risk 2 = 5

`pull` writes into the mirror, so the risk is overwriting a local change. Three rules keep that from happening, and the tests pin each one: a document is written only when the local file is absent or still matches the last synced hash, checked again after the fetch returns, since an edit can land while the request is out; a ledger is written only when the local file is absent or exactly what was last synced, and a local ledger that already starts with darkmem's text is left alone; `latest.md` takes darkmem's newest checkpoint across the open workstreams only when it is newer, by darkmem's `created_at`, than the last checkpoint synced (`checkpointAt`), and never over unpushed local edits, which are then a conflict. File modification times are never compared with darkmem's clock. `pullDocuments` and `pullLedgers` are exported because Task 7's verification reuses them.

- [ ] **Step 1: Write the failing test**

Create `plugins/dr-superpowers/tests/darkmem-sync/pull.test.mjs`:

```js
import assert from "node:assert/strict";
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import test from "node:test";
import { createClient } from "../../scripts/lib/darkmem-client.mjs";
import { STUB_KEY, startStub } from "./stub-server.mjs";
import { makeHome, makeRepo, read, run, write } from "./helpers.mjs";

const sha = text => crypto.createHash("sha256").update(text, "utf8").digest("hex");

async function setup(t, stubOptions = {}) {
  const stub = await startStub(stubOptions);
  t.after(() => stub.close());
  const repo = makeRepo();
  const home = makeHome({ repo, url: stub.url });
  const seed = createClient({ url: stub.url, apiKey: STUB_KEY, runKey: "seed" });
  const state = () => JSON.parse(fs.readFileSync(path.join(home.mirror, ".sync-state.json"), "utf8"));
  return { stub, repo, ...home, seed, state, pull: () => run(["pull"], { cwd: repo, env: home.env }) };
}

const fetches = stub => stub.db.requests.filter(r => r.path === "/api/v1/documents/by-uri").length;

test("pull writes documents and handoff notes under the prefix, and records their hashes", async t => {
  const s = await setup(t);
  await s.seed.putDocument({ project: "proj", uri: "superpowers/specs/a.md", content: "# A\n" });
  await s.seed.putDocument({ project: "proj", uri: "superpowers/handoff/p1.md", content: "# Handoff\n" });
  await s.seed.putDocument({ project: "proj", uri: "other/x.md", content: "x" });
  await s.seed.putDocument({ project: "else", uri: "superpowers/specs/b.md", content: "b" });
  const result = await s.pull();
  assert.equal(result.code, 0, result.stdout + result.stderr);
  assert.match(result.stdout, /darkmem-sync pull: 2 documents, 0 ledgers, 0 checkpoints; 0 conflicts, 0 failures/);
  assert.equal(read(path.join(s.docsRoot, "specs", "a.md")), "# A\n");
  assert.equal(read(path.join(s.workRoot, "sdd", "p1", "handoff.md")), "# Handoff\n");
  assert.equal(fs.existsSync(path.join(s.docsRoot, "..", "other")), false);
  assert.deepEqual(s.state().documents, { "superpowers/specs/a.md": sha("# A\n"), "superpowers/handoff/p1.md": sha("# Handoff\n") });
  const before = fetches(s.stub);
  assert.equal((await s.pull()).code, 0);
  assert.equal(fetches(s.stub), before, "an unchanged manifest fetches nothing");
});

test("a document changed on darkmem replaces an unchanged local copy", async t => {
  const s = await setup(t);
  await s.seed.putDocument({ project: "proj", uri: "superpowers/a.md", content: "one\n" });
  await s.pull();
  await s.seed.putDocument({ project: "proj", uri: "superpowers/a.md", content: "two\n" });
  assert.equal((await s.pull()).code, 0);
  assert.equal(read(path.join(s.docsRoot, "a.md")), "two\n");
});

test("a document changed on both sides is a conflict and the local copy stays", async t => {
  const s = await setup(t);
  await s.seed.putDocument({ project: "proj", uri: "superpowers/a.md", content: "one\n" });
  await s.pull();
  write(path.join(s.docsRoot, "a.md"), "local\n");
  await s.seed.putDocument({ project: "proj", uri: "superpowers/a.md", content: "remote\n" });
  const result = await s.pull();
  assert.equal(result.code, 1);
  assert.match(result.stdout, /^conflict: superpowers\/a\.md: changed locally and on darkmem; move the local file aside/m);
  assert.equal(read(path.join(s.docsRoot, "a.md")), "local\n");
  assert.equal(s.state().conflicts.length, 1);
  const status = await run(["status"], { cwd: s.repo, env: s.env });
  assert.match(status.stdout, /^conflict: superpowers\/a\.md/m);
});

test("open workstreams render their ledgers; closed ones do not", async t => {
  const s = await setup(t);
  await s.seed.append({ project: "proj", workstream: "p1", entries: [{ kind: "ledger", body: "# SDD ledger — plan: x\n" }, { kind: "ledger", body: "Task 1: a\n\n| t |\n" }] });
  await s.seed.append({ project: "proj", workstream: "p1", entries: [{ kind: "ledger", body: "Task 2: b\n" }, { kind: "note", body: "not a ledger line" }] });
  const { workstream } = await s.seed.append({ project: "proj", workstream: "done", entries: [{ kind: "ledger", body: "old\n" }] });
  await s.seed.updateWorkstream(workstream.id, { state: "closed" });
  assert.equal((await s.pull()).code, 0);
  const file = path.join(s.workRoot, "sdd", "p1", "progress.md");
  assert.equal(read(file), "# SDD ledger — plan: x\nTask 1: a\n\n| t |\nTask 2: b\n");
  assert.equal(fs.existsSync(path.join(s.workRoot, "sdd", "done")), false);
  assert.deepEqual(s.state().ledgers.p1, { offset: fs.statSync(file).size, prefix: sha(read(file)) });
});

test("a ledger ahead locally is kept; a diverged one is a conflict", async t => {
  const s = await setup(t);
  await s.seed.append({ project: "proj", workstream: "p1", entries: [{ kind: "ledger", body: "one\n" }] });
  await s.pull();
  const file = path.join(s.workRoot, "sdd", "p1", "progress.md");
  fs.appendFileSync(file, "two\n");
  assert.equal((await s.pull()).code, 0);
  assert.equal(read(file), "one\ntwo\n");
  await s.seed.append({ project: "proj", workstream: "p1", entries: [{ kind: "ledger", body: "three\n" }] });
  const result = await s.pull();
  assert.equal(result.code, 1);
  assert.match(result.stdout, /conflict: sdd\/p1\/progress\.md: the local ledger and darkmem's have diverged/);
  assert.equal(read(file), "one\ntwo\n");
});

test("latest.md takes the newest checkpoint across open workstreams, by darkmem's clock", async t => {
  const s = await setup(t);
  await s.seed.append({ project: "proj", workstream: "p1", entries: [{ kind: "checkpoint", body: "# older\n" }] });
  await s.seed.append({ project: "proj", workstream: "p2", entries: [{ kind: "checkpoint", body: "# newest\n" }] });
  assert.equal((await s.pull()).code, 0);
  const latest = path.join(s.workRoot, "handoff", "latest.md");
  assert.equal(read(latest), "# newest\n");
  const future = new Date(Date.now() + 24 * 60 * 60 * 1000);
  fs.utimesSync(latest, future, future);
  await s.seed.append({ project: "proj", workstream: "p1", entries: [{ kind: "checkpoint", body: "# later still\n" }] });
  assert.equal((await s.pull()).code, 0);
  assert.equal(read(latest), "# later still\n", "a file's mtime never hides a newer checkpoint");
  assert.equal(s.state().checkpoint, sha("# later still\n"));
});

test("an unpushed edit to latest.md holds until darkmem has a newer checkpoint, which is then a conflict", async t => {
  const s = await setup(t);
  await s.seed.append({ project: "proj", workstream: "p1", entries: [{ kind: "checkpoint", body: "# synced\n" }] });
  await s.pull();
  const latest = path.join(s.workRoot, "handoff", "latest.md");
  write(latest, "# edited here\n");
  assert.equal((await s.pull()).code, 0);
  assert.equal(read(latest), "# edited here\n");
  await s.seed.append({ project: "proj", workstream: "p2", entries: [{ kind: "checkpoint", body: "# newer\n" }] });
  const result = await s.pull();
  assert.equal(result.code, 1);
  assert.match(result.stdout, /conflict: handoff\/latest\.md: changed locally, and darkmem holds a newer checkpoint/);
  assert.equal(read(latest), "# edited here\n");
});

test("an edit that lands while a document is being fetched is kept and reported", async t => {
  let docsRoot = null;
  const s = await setup(t, {
    onRequest: request => {
      if (request.path === "/api/v1/documents/by-uri" && docsRoot) write(path.join(docsRoot, "a.md"), "edited mid-pull\n");
    },
  });
  await s.seed.putDocument({ project: "proj", uri: "superpowers/a.md", content: "one\n" });
  await s.pull();
  await s.seed.putDocument({ project: "proj", uri: "superpowers/a.md", content: "two\n" });
  docsRoot = s.docsRoot;
  const result = await s.pull();
  assert.equal(result.code, 1);
  assert.match(result.stdout, /conflict: superpowers\/a\.md: changed locally during the pull/);
  assert.equal(read(path.join(s.docsRoot, "a.md")), "edited mid-pull\n");
});

test("conflicts found before a failure are kept for status", async t => {
  const s = await setup(t);
  await s.seed.putDocument({ project: "proj", uri: "superpowers/a.md", content: "one\n" });
  await s.pull();
  write(path.join(s.docsRoot, "a.md"), "local\n");
  await s.seed.putDocument({ project: "proj", uri: "superpowers/a.md", content: "remote\n" });
  s.stub.db.failures.push({ method: "GET", path: "/api/v1/worklog/workstreams", status: 503 });
  const result = await s.pull();
  assert.equal(result.code, 3);
  assert.match(result.stdout, /^conflict: superpowers\/a\.md/m);
  assert.deepEqual(s.state().conflicts.length, 1);
  const status = await run(["status"], { cwd: s.repo, env: s.env });
  assert.match(status.stdout, /^conflict: superpowers\/a\.md: changed locally and on darkmem/m);
});

test("pull fails open: an unreachable darkmem is one line and exit 3 within the timeout", async () => {
  const repo = makeRepo();
  const { env } = makeHome({ repo, url: "http://127.0.0.1:9" });
  const started = Date.now();
  const result = await run(["pull"], { cwd: repo, env });
  assert.equal(result.code, 3);
  assert.match(result.stderr, /^darkmem-sync: pull failed: GET \/api\/v1\/documents\/manifest: /);
  assert.equal(result.stderr.trim().split("\n").length, 1);
  assert.ok(Date.now() - started < 10000);
});

test("pull in local mode does nothing and succeeds", async () => {
  const repo = makeRepo();
  const { env } = makeHome({ repo, config: null });
  const result = await run(["pull"], { cwd: repo, env });
  assert.equal(result.code, 0);
  assert.match(result.stdout, /^darkmem-sync: local mode/);
});
```

- [ ] **Step 2: Run it to verify it fails**

```bash
timeout 180 node --test --test-reporter=spec plugins/dr-superpowers/tests/darkmem-sync/pull.test.mjs
```

Expected: `ℹ fail 11` — `pull` is not a command yet, so every run is a usage error (exit 2).

- [ ] **Step 3: Write the module and register the command**

Create `plugins/dr-superpowers/scripts/lib/darkmem-pull.mjs`:

```js
// darkmem-sync pull (darkmem mirror spec §3): bring the mirror up to darkmem.
// A local file with changes of its own is never overwritten: it is reported
// as a conflict and left for the agent to resolve.
import fs from "node:fs";
import path from "node:path";
import { DOC_PREFIX, sha256, uriToLocal, validKey, writeFileAtomic } from "./darkmem-mirror.mjs";

const RESOLVE = "move the local file aside, pull, and re-apply your change";

const localHash = file => (fs.existsSync(file) ? sha256(fs.readFileSync(file)) : null);

// A workstream's ledger as a file: its ledger entries' bodies, in order.
export async function ledgerText(client, workstreamId) {
  return (await client.entries(workstreamId, "ledger")).map(entry => entry.body).join("");
}

// Every document under superpowers/ whose manifest hash differs from the
// mirror's copy. The local file is hashed again after the fetch, because an
// edit can land while the request is out.
export async function pullDocuments({ cfg, client, roots, state, persist, report }) {
  for (const item of await client.manifest(cfg.project, DOC_PREFIX)) {
    if (!item.content_hash) continue;
    const file = uriToLocal(roots, item.uri);
    if (!file) {
      report.notes.push(`${item.uri}: has no place in the mirror, skipped`);
      continue;
    }
    const local = localHash(file);
    if (local === item.content_hash) {
      state.documents[item.uri] = local;
      continue;
    }
    if (local !== null && local !== state.documents[item.uri]) {
      report.conflicts.push(`${item.uri}: changed locally and on darkmem; ${RESOLVE}`);
      continue;
    }
    const doc = await client.getDocument(cfg.project, item.uri);
    if (typeof doc.content !== "string") {
      report.notes.push(`${item.uri}: darkmem holds no text for it, skipped`);
      continue;
    }
    if (localHash(file) !== local) {
      report.conflicts.push(`${item.uri}: changed locally during the pull; ${RESOLVE}`);
      continue;
    }
    writeFileAtomic(file, doc.content);
    state.documents[item.uri] = doc.content_hash;
    persist();
    report.counts.documents += 1;
  }
}

// Render each workstream's ledger entries into work/sdd/<key>/progress.md.
export async function pullLedgers({ client, roots, state, persist, report }, workstreams) {
  for (const ws of workstreams) {
    if (!validKey(ws.key)) {
      report.notes.push(`workstream ${JSON.stringify(ws.key)}: not usable as a directory name, skipped`);
      continue;
    }
    const text = await ledgerText(client, ws.id);
    if (!text) continue;
    const remote = Buffer.from(text, "utf8");
    const synced = { offset: remote.length, prefix: sha256(remote) };
    const file = path.join(roots.workRoot, "sdd", ws.key, "progress.md");
    const local = fs.existsSync(file) ? fs.readFileSync(file) : null;
    const record = state.ledgers[ws.key];
    if (local && local.length >= remote.length && local.subarray(0, remote.length).equals(remote)) {
      // Equal, or ahead by lines push has not sent yet.
      state.ledgers[ws.key] = synced;
    } else if (!local || (record && !record.pending && local.length === record.offset && sha256(local) === record.prefix)) {
      writeFileAtomic(file, remote);
      state.ledgers[ws.key] = synced;
      report.counts.ledgers += 1;
    } else {
      report.conflicts.push(`sdd/${ws.key}/progress.md: the local ledger and darkmem's have diverged; ${RESOLVE}`);
      continue;
    }
    persist();
  }
}

// latest.md is the most recent stop: the newest checkpoint across the open
// workstreams, taken when it is newer than the last checkpoint this mirror
// synced (by darkmem's own timestamps, never the file's mtime) and never over
// local edits that have not been pushed.
async function pullCheckpoint({ cfg, client, roots, state, persist, report }, open) {
  let newest = null;
  for (const ws of open) {
    const checkpoint = (await client.resume(cfg.project, ws.key))?.checkpoint;
    if (checkpoint && (!newest || Date.parse(checkpoint.created_at) > Date.parse(newest.created_at))) newest = checkpoint;
  }
  if (!newest) return;
  if (state.checkpointAt && Date.parse(newest.created_at) <= Date.parse(state.checkpointAt)) return;
  const file = path.join(roots.workRoot, "handoff", "latest.md");
  const remote = Buffer.from(newest.body, "utf8");
  const remoteHash = sha256(remote);
  const local = localHash(file);
  if (local !== null && local !== remoteHash && local !== state.checkpoint) {
    report.conflicts.push(`handoff/latest.md: changed locally, and darkmem holds a newer checkpoint; ${RESOLVE}`);
    return;
  }
  if (local !== remoteHash) {
    writeFileAtomic(file, remote);
    report.counts.checkpoints += 1;
  }
  state.checkpoint = remoteHash;
  state.checkpointAt = newest.created_at;
  persist();
}

export async function pull(context) {
  Object.assign(context.report.counts, { documents: 0, ledgers: 0, checkpoints: 0 });
  await pullDocuments(context);
  const open = await context.client.workstreams(context.cfg.project, "open");
  await pullLedgers(context, open);
  await pullCheckpoint(context, open);
}
```

In `plugins/dr-superpowers/scripts/lib/darkmem-sync.mjs`, add after the `darkmem-mirror.mjs` import line:

```js
import { pull } from "./darkmem-pull.mjs";
```

and add after the `status:` line of `COMMANDS`:

```js
  pull: { options: {}, needsDarkmem: false, recordsConflicts: true, run: pull },
```

- [ ] **Step 4: Run it to verify it passes**

```bash
timeout 180 node --test --test-reporter=spec plugins/dr-superpowers/tests/darkmem-sync/pull.test.mjs
timeout 300 bash plugins/dr-superpowers/tests/darkmem-sync.test.sh | grep -E '^ℹ (tests|pass|fail)'
```

Expected: `ℹ pass 11`, `ℹ fail 0`; then `ℹ tests 42`, `ℹ pass 42`, `ℹ fail 0`.

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-superpowers/scripts/lib/darkmem-pull.mjs plugins/dr-superpowers/scripts/lib/darkmem-sync.mjs plugins/dr-superpowers/tests/darkmem-sync/pull.test.mjs
git commit -m "feat(superpowers): add darkmem-sync pull" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 6: push and status

**Files:**
- Create: `plugins/dr-superpowers/scripts/lib/darkmem-push.mjs`
- Modify: `plugins/dr-superpowers/scripts/lib/darkmem-sync.mjs` (one import, one `COMMANDS` entry)
- Test: `plugins/dr-superpowers/tests/darkmem-sync/push.test.mjs`

**Interfaces:**
- Consumes: `ledgerText` (Task 5); Contracts → **darkmem-client.mjs**, **darkmem-mirror.mjs**, **Command**, **Test fixtures**.
- Produces: `push` (Contracts → **Command modules**).

**Items:** 1

**Implementer:** dr-superpowers:impl-opus-medium
**Evaluation:** files 1 - spec 0 - coupling 2 - risk 2 = 5

`push` writes to darkmem, so the risk is clobbering a newer copy or sending a ledger line twice. A document goes up under its recorded hash (`expected_hash`), so one that moved on darkmem answers 409 and is reported, unless darkmem already holds exactly the local bytes (an earlier put whose answer was lost), which is recorded instead. A document never synced is checked against the manifest first; an empty or non-UTF-8 document is a failure and keeps its record. A ledger goes up as exactly the bytes appended since the recorded offset, checked against the recorded prefix hash. Each append is marked `pending` in the state before it is sent and the new offset is saved after it lands, so a lost answer or a crash in between is reconciled on the next push by adopting darkmem's copy when it is a prefix of the file; the same adoption makes a lost state file safe. A checkpoint is compared with its workstream's latest checkpoint before it is filed. Workstream properties come from `propertiesFor`, for ledgers and checkpoints alike, and a handoff note filed after its workstream began is linked with `handoff_uri`. See Assumptions for the one window this cannot close: a uri another client creates between the manifest read and the put. `status` (Task 4) needs no change: this task's tests cover it after a push.

- [ ] **Step 1: Write the failing test**

Create `plugins/dr-superpowers/tests/darkmem-sync/push.test.mjs`:

```js
import assert from "node:assert/strict";
import crypto from "node:crypto";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { createClient } from "../../scripts/lib/darkmem-client.mjs";
import { STUB_KEY, startStub, storedDocument } from "./stub-server.mjs";
import { makeHome, makeRepo, read, run, write } from "./helpers.mjs";

const sha = text => crypto.createHash("sha256").update(text, "utf8").digest("hex");

async function setup(t, stubOptions = {}) {
  const stub = await startStub(stubOptions);
  t.after(() => stub.close());
  const repo = makeRepo();
  const home = makeHome({ repo, url: stub.url });
  const seed = createClient({ url: stub.url, apiKey: STUB_KEY, runKey: "seed" });
  const push = (...args) => run(["push", ...args], { cwd: repo, env: home.env });
  const posts = path => stub.db.requests.filter(r => r.method === "POST" && r.path === path);
  const ledger = async slug => {
    const ws = stub.db.workstreams.find(w => w.key === slug);
    return ws.entries.filter(e => e.kind === "ledger");
  };
  return { stub, repo, ...home, seed, push, posts, ledger };
}

test("a new document goes up without a precondition, then only when it changes, under the recorded hash", async t => {
  const s = await setup(t);
  write(path.join(s.docsRoot, "specs", "a.md"), "# A\n");
  const first = await s.push();
  assert.equal(first.code, 0, first.stdout + first.stderr);
  assert.match(first.stdout, /darkmem-sync push: 1 documents, 0 ledger entries, 0 checkpoints; 0 conflicts, 0 failures/);
  const [created] = s.posts("/api/v1/documents");
  assert.deepEqual(created.body, { project: "proj", uri: "superpowers/specs/a.md", content: "# A\n" });
  assert.equal((await s.push()).code, 0);
  assert.equal(s.posts("/api/v1/documents").length, 1, "an unchanged document is not sent again");
  write(path.join(s.docsRoot, "specs", "a.md"), "# A2\n");
  assert.equal((await s.push()).code, 0);
  assert.equal(s.posts("/api/v1/documents")[1].body.expected_hash, sha("# A\n"));
});

test("a document moved on darkmem is a conflict and the local file stays", async t => {
  const s = await setup(t);
  write(path.join(s.docsRoot, "a.md"), "one\n");
  await s.push();
  await s.seed.putDocument({ project: "proj", uri: "superpowers/a.md", content: "theirs\n" });
  write(path.join(s.docsRoot, "a.md"), "mine\n");
  const result = await s.push();
  assert.equal(result.code, 1);
  assert.match(result.stdout, /^conflict: superpowers\/a\.md: changed on darkmem since the last sync; pull, reconcile, then push$/m);
  assert.equal(read(path.join(s.docsRoot, "a.md")), "mine\n");
  assert.equal(s.stub.db.documents.get("proj\u0000superpowers/a.md").content, "theirs\n");
});

test("a document deleted on darkmem since the last sync is a conflict and the local file stays", async t => {
  const s = await setup(t);
  write(path.join(s.docsRoot, "a.md"), "one\n");
  await s.push();
  s.stub.db.documents.delete("proj\u0000superpowers/a.md");
  write(path.join(s.docsRoot, "a.md"), "two\n");
  const result = await s.push();
  assert.equal(result.code, 1, result.stderr);
  assert.match(result.stdout, /^conflict: superpowers\/a\.md: deleted on darkmem since the last sync; pull, reconcile, then push$/m);
  assert.equal(read(path.join(s.docsRoot, "a.md")), "two\n");
});

test("an unrecorded file darkmem already holds is adopted when equal and a conflict when not", async t => {
  const s = await setup(t);
  await s.seed.putDocument({ project: "proj", uri: "superpowers/same.md", content: "same\n" });
  await s.seed.putDocument({ project: "proj", uri: "superpowers/diff.md", content: "theirs\n" });
  write(path.join(s.docsRoot, "same.md"), "same\n");
  write(path.join(s.docsRoot, "diff.md"), "mine\n");
  const result = await s.push();
  assert.equal(result.code, 1);
  assert.match(result.stdout, /conflict: superpowers\/diff\.md: darkmem already holds different content/);
  assert.equal(s.posts("/api/v1/documents").length, 2, "only the two seeding puts");
});

test("handoff notes go up as documents and are linked from their workstream", async t => {
  const s = await setup(t);
  await s.seed.append({ project: "proj", workstream: "p1", entries: [{ kind: "ledger", body: "one\n" }] });
  write(path.join(s.workRoot, "sdd", "p1", "handoff.md"), "# Handoff p1\n");
  const result = await s.push();
  assert.equal(result.code, 0, result.stdout);
  assert.equal(s.stub.db.documents.get("proj\u0000superpowers/handoff/p1.md").content, "# Handoff p1\n");
  assert.equal(s.stub.db.workstreams.find(w => w.key === "p1").properties.handoff_uri, "superpowers/handoff/p1.md");
});

test("an empty document fails the push and keeps its record; a reserved file is a note", async t => {
  const s = await setup(t);
  write(path.join(s.docsRoot, "a.md"), "a\n");
  await s.push();
  write(path.join(s.docsRoot, "a.md"), "");
  write(path.join(s.docsRoot, "handoff", "x.md"), "x");
  const result = await s.push();
  assert.equal(result.code, 1);
  assert.match(result.stdout, /failed: superpowers\/a\.md: empty or not UTF-8 text, which darkmem cannot store; not pushed/);
  assert.match(result.stdout, /note: handoff\/x\.md: the docs root's handoff\/ directory is reserved, not pushed/);
  assert.equal(s.stub.db.documents.get("proj\u0000superpowers/a.md").content, "a\n");
  assert.match((await run(["status"], { cwd: s.repo, env: s.env })).stdout, /^modified: superpowers\/a\.md$/m);
});

test("a document another client files during the push is reported as replaced", async t => {
  const s = await setup(t, {
    onRequest: (request, db) => {
      if (request.method === "POST" && request.path === "/api/v1/documents" && request.body.uri === "superpowers/race.md") {
        db.documents.set("proj\u0000superpowers/race.md", storedDocument("proj", "superpowers/race.md", "theirs\n"));
      }
    },
  });
  write(path.join(s.docsRoot, "race.md"), "mine\n");
  const result = await s.push();
  assert.equal(result.code, 1);
  assert.match(result.stdout, /failed: superpowers\/race\.md: another client filed it during this push, and this push replaced its content/);
});

test("a document put whose answer was lost is recorded on the next push, not reported as a conflict", async t => {
  const s = await setup(t);
  write(path.join(s.docsRoot, "a.md"), "one\n");
  await s.push();
  write(path.join(s.docsRoot, "a.md"), "two\n");
  s.stub.db.failures.push({ method: "POST", path: "/api/v1/documents", status: 502, commit: true });
  assert.equal((await s.push()).code, 3);
  const retry = await s.push();
  assert.equal(retry.code, 0, retry.stdout);
  assert.equal(s.stub.db.documents.get("proj\u0000superpowers/a.md").content, "two\n");
  assert.equal((await run(["status"], { cwd: s.repo, env: s.env })).stdout.split("\n").filter(Boolean).length, 1);
});

test("a ledger goes up as the appended bytes, one entry per push, and darkmem's concatenation is the file", async t => {
  const s = await setup(t);
  write(path.join(s.docsRoot, "plans", "p1.md"), "# P1\n\n**Spec:** `docs/superpowers/specs/s.md`\n");
  const file = path.join(s.workRoot, "sdd", "p1", "progress.md");
  write(file, "# SDD ledger — plan: docs/superpowers/plans/p1.md\n\nTask 1: implementer (assigned)\n");
  assert.equal((await s.push()).code, 0);
  fs.appendFileSync(file, "Task 1: complete\n\n| a | b |\n|---|---|\n");
  const second = await s.push();
  assert.match(second.stdout, /0 documents, 1 ledger entries/);
  const entries = await s.ledger("p1");
  assert.equal(entries.length, 2);
  assert.equal(entries[1].body, "Task 1: complete\n\n| a | b |\n|---|---|\n");
  assert.equal(entries.map(e => e.body).join(""), read(file));
  assert.equal(entries[0].run_key, "sess-1");
  const ws = s.stub.db.workstreams.find(w => w.key === "p1");
  assert.deepEqual(ws.properties, { plan_uri: "superpowers/plans/p1.md", spec_uri: "superpowers/specs/s.md" });
  assert.equal((await s.push()).code, 0);
  assert.equal((await s.ledger("p1")).length, 2, "nothing new, nothing sent");
});

test("a rewritten ledger is refused and nothing is sent", async t => {
  const s = await setup(t);
  const file = path.join(s.workRoot, "sdd", "p1", "progress.md");
  write(file, "one\ntwo\n");
  await s.push();
  write(file, "one\nTWO\nthree\n");
  const result = await s.push();
  assert.equal(result.code, 1);
  assert.match(result.stdout, /conflict: sdd\/p1\/progress\.md: rewritten rather than appended to/);
  assert.equal((await s.ledger("p1")).length, 1);
});

test("an append longer than one entry is split at a newline and still concatenates exactly", async t => {
  const s = await setup(t);
  const file = path.join(s.workRoot, "sdd", "big", "progress.md");
  const line = `${"x".repeat(999)}\n`;
  write(file, line.repeat(70));
  assert.equal((await s.push()).code, 0);
  const entries = await s.ledger("big");
  assert.equal(entries.length, 2);
  assert.ok(entries.every(e => e.body.length <= 65536 && e.body.endsWith("\n")));
  assert.equal(entries.map(e => e.body).join(""), line.repeat(70));
});

test("a lost state file never re-sends lines darkmem already holds", async t => {
  const s = await setup(t);
  const file = path.join(s.workRoot, "sdd", "p1", "progress.md");
  write(file, "one\n");
  await s.push();
  fs.rmSync(path.join(s.mirror, ".sync-state.json"));
  fs.appendFileSync(file, "two\n");
  assert.equal((await s.push()).code, 0);
  assert.deepEqual((await s.ledger("p1")).map(e => e.body), ["one\n", "two\n"]);
});

test("a ledger append whose answer was lost is reconciled, never sent twice", async t => {
  const s = await setup(t);
  const file = path.join(s.workRoot, "sdd", "p1", "progress.md");
  write(file, "one\n");
  s.stub.db.failures.push({ method: "POST", path: "/api/v1/worklog/entries", status: 502, commit: true });
  const lost = await s.push();
  assert.equal(lost.code, 3);
  assert.equal(JSON.parse(read(path.join(s.mirror, ".sync-state.json"))).ledgers.p1.pending, true);
  assert.equal((await s.push()).code, 0);
  assert.deepEqual((await s.ledger("p1")).map(e => e.body), ["one\n"]);
  fs.appendFileSync(file, "two\n");
  assert.equal((await s.push()).code, 0);
  assert.deepEqual((await s.ledger("p1")).map(e => e.body), ["one\n", "two\n"]);
});

test("a ledger append refused by darkmem is a failure and nothing is marked sent", async t => {
  const s = await setup(t);
  const file = path.join(s.workRoot, "sdd", "p1", "progress.md");
  write(file, "one\n");
  s.stub.db.failures.push({ method: "POST", path: "/api/v1/worklog/entries", status: 422, detail: "refused" });
  const refused = await s.push();
  assert.equal(refused.code, 1);
  assert.match(refused.stdout, /failed: sdd\/p1\/progress\.md: darkmem refused an entry: refused/);
  assert.equal((await s.push()).code, 0);
  assert.deepEqual((await s.ledger("p1")).map(e => e.body), ["one\n"]);
});

test("a plan directory whose name cannot be a workstream key fails the push", async t => {
  const s = await setup(t);
  write(path.join(s.workRoot, "sdd", "bad name", "progress.md"), "x\n");
  const result = await s.push();
  assert.equal(result.code, 1);
  assert.match(result.stdout, /failed: .*bad name: not a usable workstream key/);
});

test("latest.md goes up as a checkpoint on the plan its State names, or on --workstream", async t => {
  const s = await setup(t);
  const latest = path.join(s.workRoot, "handoff", "latest.md");
  write(latest, "# Handoff — 2026-09-24 (phase stop)\n\n## State\n- Plan: `docs/superpowers/plans/p1.md`; ledger: `x`\n");
  assert.equal((await s.push()).code, 0);
  const p1 = s.stub.db.workstreams.find(w => w.key === "p1");
  assert.deepEqual(p1.entries.map(e => e.kind), ["checkpoint"]);
  assert.deepEqual(p1.properties, { plan_uri: "superpowers/plans/p1.md" });
  assert.equal((await s.push()).code, 0);
  assert.equal(p1.entries.length, 1, "an unchanged checkpoint is not sent again");
  write(latest, "# Handoff\n\n## State\n- unplanned work\n");
  const unnamed = await s.push();
  assert.equal(unnamed.code, 1);
  assert.match(unnamed.stdout, /failed: handoff\/latest\.md: its State section names no plan or draft; push again with --workstream KEY/);
  assert.equal((await s.push("--workstream", "adhoc")).code, 0);
  assert.equal(s.stub.db.workstreams.find(w => w.key === "adhoc").entries[0].kind, "checkpoint");
  write(latest, "# Handoff\n\n## State\n- Draft: `docs/superpowers/specs/d-design.md`\n");
  s.stub.db.failures.push({ method: "POST", path: "/api/v1/worklog/entries", status: 502, commit: true });
  assert.equal((await s.push()).code, 3);
  assert.equal((await s.push()).code, 0);
  const draft = s.stub.db.workstreams.find(w => w.key === "d-design");
  assert.equal(draft.entries.length, 1, "a checkpoint whose answer was lost is not filed twice");
  assert.deepEqual(draft.properties, { spec_uri: "superpowers/specs/d-design.md" });
  const bad = await s.push("--workstream", "../x");
  assert.equal(bad.code, 2);
  assert.match(bad.stderr, /--workstream "\.\.\/x" is not a workstream key/);
});

test("without a declared session the run key falls back to the machine and day", async t => {
  const s = await setup(t);
  delete s.env.DR_SUPERPOWERS_SESSION_ID;
  write(path.join(s.workRoot, "sdd", "p1", "progress.md"), "one\n");
  assert.equal((await s.push()).code, 0);
  const [append] = s.posts("/api/v1/worklog/entries");
  assert.match(append.body.run_key, new RegExp(`^codex:${os.hostname().replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}:\\d{4}-\\d{2}-\\d{2}$`));
  assert.equal(append.headers["x-darkmem-client"], "dr-superpowers");
});

test("status is clean after a push and names an edit made after it", async t => {
  const s = await setup(t);
  write(path.join(s.docsRoot, "a.md"), "a\n");
  await s.push();
  const clean = await run(["status"], { cwd: s.repo, env: s.env });
  assert.equal(clean.stdout.split("\n").filter(Boolean).length, 1);
  write(path.join(s.docsRoot, "a.md"), "b\n");
  const dirty = await run(["status"], { cwd: s.repo, env: s.env });
  assert.match(dirty.stdout, /^modified: superpowers\/a\.md$/m);
});
```

- [ ] **Step 2: Run it to verify it fails**

```bash
timeout 180 node --test --test-reporter=spec plugins/dr-superpowers/tests/darkmem-sync/push.test.mjs
```

Expected: `ℹ fail 18` — `push` is not a command yet, so every run is a usage error (exit 2).

- [ ] **Step 3: Write the module and register the command**

Create `plugins/dr-superpowers/scripts/lib/darkmem-push.mjs`:

```js
// darkmem-sync push (darkmem mirror spec §3): send the mirror's local changes
// to darkmem. Documents go up under the recorded hash, so a document that moved
// on darkmem is a conflict rather than an overwrite; a ledger goes up as the
// bytes appended since the last push, never as a rewrite. Every write whose
// answer may have been lost is reconciled against darkmem before it is retried,
// so a retry never sends the same bytes twice.
import fs from "node:fs";
import path from "node:path";
import { HttpError } from "./darkmem-client.mjs";
import {
  DOC_PREFIX, EMPTY_SHA, MAX_ENTRIES_PER_APPEND, MAX_ENTRY_CHARS, UsageError, checkpointTarget, decodeUtf8,
  ledgerFiles, ledgerPlanPath, listDocumentFiles, propertiesFor, sha256, splitAtLimit, unsupportedPlanDirs, validKey,
} from "./darkmem-mirror.mjs";
import { ledgerText } from "./darkmem-pull.mjs";

const RESOLVE = "pull, reconcile, then push";
const HANDOFF_URI = new RegExp(`^${DOC_PREFIX}/handoff/([^/]+)\\.md$`);

// A handoff note filed after its workstream began: point the workstream at it.
async function linkHandoff({ cfg, client }, uri) {
  const slug = HANDOFF_URI.exec(uri)?.[1];
  if (!slug) return;
  const existing = await client.resume(cfg.project, slug);
  if (existing && existing.workstream.properties?.handoff_uri !== uri) {
    await client.updateWorkstream(existing.workstream.id, { properties: { handoff_uri: uri } });
  }
}

async function pushDocuments(context) {
  const { cfg, client, roots, state, persist, report } = context;
  let remote = null;
  const remoteHash = async uri => {
    remote ??= new Map((await client.manifest(cfg.project, DOC_PREFIX)).map(item => [item.uri, item.content_hash]));
    return remote.get(uri) ?? null;
  };
  for (const { file, uri } of listDocumentFiles(roots)) {
    if (!uri) {
      report.notes.push(`${path.relative(roots.docsRoot, file)}: the docs root's handoff/ directory is reserved, not pushed`);
      continue;
    }
    const buffer = fs.readFileSync(file);
    const local = sha256(buffer);
    const recorded = state.documents[uri];
    if (local === recorded) continue;
    const content = decodeUtf8(buffer);
    if (!content) {
      report.failures.push(`${uri}: empty or not UTF-8 text, which darkmem cannot store; not pushed`);
      continue;
    }
    if (recorded === undefined) {
      const current = await remoteHash(uri);
      if (current === local) {
        state.documents[uri] = local;
        persist();
        continue;
      }
      if (current !== null) {
        report.conflicts.push(`${uri}: darkmem already holds different content; ${RESOLVE}`);
        continue;
      }
    }
    let answer;
    try {
      answer = await client.putDocument({ project: cfg.project, uri, content, expectedHash: recorded });
    } catch (error) {
      if (error instanceof HttpError && error.status === 422) {
        report.failures.push(`${uri}: darkmem refused it: ${error.detail}`);
        continue;
      }
      if (!(error instanceof HttpError && error.status === 409)) throw error;
      // A 409 may be this mirror's own earlier put whose answer was lost.
      let current = null;
      try {
        current = (await client.getDocument(cfg.project, uri)).content_hash;
      } catch (readError) {
        if (!(readError instanceof HttpError && readError.status === 404)) throw readError;
        report.conflicts.push(`${uri}: deleted on darkmem since the last sync; ${RESOLVE}`);
        continue;
      }
      if (current !== local) {
        report.conflicts.push(`${uri}: changed on darkmem since the last sync; ${RESOLVE}`);
        continue;
      }
      answer = { content_hash: current, outcome: "unchanged" };
    }
    state.documents[uri] = answer.content_hash;
    persist();
    report.counts.documents += 1;
    if (recorded === undefined && answer.outcome === "updated") {
      // darkmem has no create-only put: another client filed this uri between
      // the manifest read and this put, and its content was replaced.
      report.failures.push(`${uri}: another client filed it during this push, and this push replaced its content`);
    }
    await linkHandoff(context, uri);
  }
}

// What darkmem already holds of a ledger, adopted when it is a prefix of the
// file: used for a ledger this mirror never synced (a lost state file) and for
// one whose last append may have landed without an answer.
async function adoptRemoteLedger({ cfg, client }, slug, buffer) {
  const existing = await client.resume(cfg.project, slug);
  if (!existing) return { offset: 0, prefix: EMPTY_SHA };
  const remote = Buffer.from(await ledgerText(client, existing.workstream.id), "utf8");
  if (buffer.length >= remote.length && buffer.subarray(0, remote.length).equals(remote)) {
    return { offset: remote.length, prefix: sha256(remote) };
  }
  return null;
}

async function pushLedgers(context) {
  const { cfg, client, roots, state, persist, report } = context;
  for (const dir of unsupportedPlanDirs(roots.workRoot)) {
    report.failures.push(`${dir}: not a usable workstream key; rename the directory to letters, digits, '.', '_' or '-'`);
  }
  for (const { slug, file } of ledgerFiles(roots.workRoot)) {
    const buffer = fs.readFileSync(file);
    let record = state.ledgers[slug];
    if (!record || record.pending) {
      record = await adoptRemoteLedger(context, slug, buffer);
      if (!record) {
        report.conflicts.push(`sdd/${slug}/progress.md: darkmem's ledger for ${slug} is not a prefix of this file; move the local file aside, pull, and re-apply your lines`);
        continue;
      }
      state.ledgers[slug] = record;
      persist();
    }
    if (buffer.length < record.offset || sha256(buffer.subarray(0, record.offset)) !== record.prefix) {
      report.conflicts.push(`sdd/${slug}/progress.md: rewritten rather than appended to; refusing to push it`);
      continue;
    }
    if (buffer.length === record.offset) continue;
    const appended = decodeUtf8(buffer.subarray(record.offset));
    if (appended === null) {
      report.notes.push(`sdd/${slug}/progress.md: the appended bytes end inside a character; push again once the write finishes`);
      continue;
    }
    const properties = propertiesFor(roots, slug, ledgerPlanPath(buffer.toString("utf8")));
    const pieces = splitAtLimit(appended);
    for (let i = 0; i < pieces.length; i += MAX_ENTRIES_PER_APPEND) {
      const group = pieces.slice(i, i + MAX_ENTRIES_PER_APPEND);
      // Marked before the call: if the answer is lost, or this process dies
      // before the offset is saved, the next push reconciles instead of
      // re-sending.
      state.ledgers[slug] = { ...record, pending: true };
      persist();
      try {
        await client.append({ project: cfg.project, workstream: slug, properties, entries: group.map(body => ({ kind: "ledger", body })) });
      } catch (error) {
        if (!(error instanceof HttpError && error.status === 422)) throw error;
        state.ledgers[slug] = record;
        persist();
        report.failures.push(`sdd/${slug}/progress.md: darkmem refused an entry: ${error.detail}`);
        break;
      }
      const offset = record.offset + Buffer.byteLength(group.join(""), "utf8");
      record = { offset, prefix: sha256(buffer.subarray(0, offset)) };
      state.ledgers[slug] = record;
      persist();
      report.counts["ledger entries"] += group.length;
    }
  }
}

async function pushCheckpoint({ cfg, client, roots, state, persist, report }, named) {
  const file = path.join(roots.workRoot, "handoff", "latest.md");
  if (!fs.existsSync(file)) return;
  const buffer = fs.readFileSync(file);
  const hash = sha256(buffer);
  if (hash === state.checkpoint) return;
  const body = decodeUtf8(buffer);
  if (!body) {
    report.failures.push("handoff/latest.md: empty or not UTF-8 text, not pushed");
    return;
  }
  const target = checkpointTarget(body);
  const workstream = named ?? target?.slug;
  if (!workstream) {
    report.failures.push("handoff/latest.md: its State section names no plan or draft; push again with --workstream KEY");
    return;
  }
  const chars = [...body].length;
  if (chars > MAX_ENTRY_CHARS) {
    report.failures.push(`handoff/latest.md: ${chars} characters, over the ${MAX_ENTRY_CHARS} one checkpoint holds`);
    return;
  }
  // The same note already filed (an earlier push whose answer was lost) is
  // recorded, not filed twice.
  const latest = (await client.resume(cfg.project, workstream))?.checkpoint;
  if (latest && sha256(Buffer.from(latest.body, "utf8")) === hash) {
    state.checkpoint = hash;
    state.checkpointAt = latest.created_at;
    persist();
    return;
  }
  const properties = propertiesFor(roots, workstream, target && target.slug === workstream ? target.path : null);
  let answer;
  try {
    answer = await client.append({ project: cfg.project, workstream, properties, entries: [{ kind: "checkpoint", body }] });
  } catch (error) {
    if (!(error instanceof HttpError && error.status === 422)) throw error;
    report.failures.push(`handoff/latest.md: darkmem refused it: ${error.detail}`);
    return;
  }
  state.checkpoint = hash;
  state.checkpointAt = answer.workstream.last_entry_at;
  persist();
  report.counts.checkpoints += 1;
}

export async function push(context) {
  const named = context.options["--workstream"];
  if (named !== undefined && !validKey(named)) throw new UsageError(`--workstream ${JSON.stringify(named)} is not a workstream key`);
  Object.assign(context.report.counts, { documents: 0, "ledger entries": 0, checkpoints: 0 });
  await pushDocuments(context);
  await pushLedgers(context);
  await pushCheckpoint(context, named);
}
```

In `plugins/dr-superpowers/scripts/lib/darkmem-sync.mjs`, add after the `darkmem-pull.mjs` import line:

```js
import { push } from "./darkmem-push.mjs";
```

and add after the `pull:` line of `COMMANDS`:

```js
  push: { options: { "--workstream": true }, needsDarkmem: false, recordsConflicts: true, run: push },
```

- [ ] **Step 4: Run it to verify it passes**

```bash
timeout 180 node --test --test-reporter=spec plugins/dr-superpowers/tests/darkmem-sync/push.test.mjs
timeout 300 bash plugins/dr-superpowers/tests/darkmem-sync.test.sh | grep -E '^ℹ (tests|pass|fail)'
```

Expected: `ℹ pass 18`, `ℹ fail 0`; then `ℹ tests 60`, `ℹ pass 60`, `ℹ fail 0`.

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-superpowers/scripts/lib/darkmem-push.mjs plugins/dr-superpowers/scripts/lib/darkmem-sync.mjs plugins/dr-superpowers/tests/darkmem-sync/push.test.mjs
git commit -m "feat(superpowers): add darkmem-sync push" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 7: import

**Files:**
- Create: `plugins/dr-superpowers/scripts/lib/darkmem-import.mjs`
- Modify: `plugins/dr-superpowers/scripts/lib/darkmem-sync.mjs` (one import, one `COMMANDS` entry)
- Test: `plugins/dr-superpowers/tests/darkmem-sync/import.test.mjs`

**Interfaces:**
- Consumes: `pullDocuments` and `pullLedgers` (Task 5; Contracts → **Command modules**); Contracts → **darkmem-client.mjs**, **darkmem-mirror.mjs**, **Command**, **Test fixtures** (including `startStub`'s `transformContent` and `onRequest`).
- Produces: `importRepository` (Contracts → **Command modules**).

**Items:** 1

**Implementer:** dr-superpowers:impl-opus-medium
**Evaluation:** files 1 - spec 0 - coupling 2 - risk 2 = 5

`import` reads the repository (`docs/superpowers/`, `.superpowers/sdd/*/progress.md` and `handoff.md`), never the mirror. It refuses before any write when a source file is empty or not UTF-8, when a plan directory's name cannot be a workstream key, or when a workstream it would create already exists. `--replace` purges those workstreams before any document is written, so a key without the admin scope stops the import with nothing changed. A ledger is chunked at blank lines (the blank line ends the chunk before it) and at the 65,536-character entry limit, appended 100 entries per call, then closed with `retain: true`. It finishes by re-reading the sources — a file added, removed or changed during the import fails it — and then pulling everything it filed into a scratch directory with Task 5's `pullDocuments` and `pullLedgers` and comparing bytes; a difference fails the import and leaves the scratch directory for inspection.

- [ ] **Step 1: Write the failing test**

Create `plugins/dr-superpowers/tests/darkmem-sync/import.test.mjs`:

```js
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import test from "node:test";
import { startStub } from "./stub-server.mjs";
import { makeHome, makeRepo, run, write } from "./helpers.mjs";

const LEDGER = "# SDD ledger — plan: docs/superpowers/plans/p1.md\n\nTask 1: implementer (assigned)\nTask 1: complete\n\n\n| a | b |\r\n\r\nTask 2: complete\n";

async function setup(t, stubOptions = {}) {
  const stub = await startStub(stubOptions);
  t.after(() => stub.close());
  const repo = makeRepo();
  const home = makeHome({ repo, url: stub.url });
  write(path.join(repo, "docs", "superpowers", "specs", "s.md"), "# Spec\n");
  write(path.join(repo, "docs", "superpowers", "plans", "p1.md"), "# P1\n\n**Spec:** `docs/superpowers/specs/s.md`\n");
  write(path.join(repo, ".superpowers", "sdd", "p1", "progress.md"), LEDGER);
  write(path.join(repo, ".superpowers", "sdd", "p1", "handoff.md"), "# p1 handoff\n");
  write(path.join(repo, ".superpowers", "sdd", "brief-only", "task-1-brief.md"), "not synced\n");
  const importing = (...args) => run(["import", ...args], { cwd: repo, env: home.env });
  return { stub, repo, ...home, importing };
}

test("import files every document, closes each ledger as a retained workstream, and verifies it", async t => {
  const s = await setup(t);
  const result = await s.importing();
  assert.equal(result.code, 0, result.stdout + result.stderr);
  assert.match(result.stdout, /note: verified: a pull of every imported file reads back byte-identical/);
  assert.match(result.stdout, /darkmem-sync import: 3 documents, 1 workstreams; 0 conflicts, 0 failures/);
  assert.deepEqual([...s.stub.db.documents.keys()].map(k => k.split("\u0000")[1]).sort(), [
    "superpowers/handoff/p1.md", "superpowers/plans/p1.md", "superpowers/specs/s.md",
  ]);
  const [ws] = s.stub.db.workstreams;
  assert.equal(ws.key, "p1");
  assert.equal(ws.state, "closed");
  assert.equal(ws.retain, true);
  assert.equal(ws.entries.map(e => e.body).join(""), LEDGER);
  assert.deepEqual(ws.entries.map(e => e.body), [
    "# SDD ledger — plan: docs/superpowers/plans/p1.md\n\n",
    "Task 1: implementer (assigned)\nTask 1: complete\n\n",
    "\n",
    "| a | b |\r\n\r\n",
    "Task 2: complete\n",
  ]);
  const mtime = fs.statSync(path.join(s.repo, ".superpowers", "sdd", "p1", "progress.md")).mtime.toISOString();
  assert.deepEqual(ws.properties, {
    plan_uri: "superpowers/plans/p1.md", spec_uri: "superpowers/specs/s.md", handoff_uri: "superpowers/handoff/p1.md", imported_mtime: mtime,
  });
});

test("a re-run refuses a workstream darkmem already holds; --replace purges and re-imports it", async t => {
  const s = await setup(t);
  assert.equal((await s.importing()).code, 0);
  const appends = () => s.stub.db.requests.filter(r => r.path === "/api/v1/worklog/entries").length;
  const before = appends();
  const again = await s.importing();
  assert.equal(again.code, 1);
  assert.match(again.stdout, /failed: already in darkmem: p1; run import --replace to purge and re-import them/);
  assert.equal(appends(), before);
  const replaced = await s.importing("--replace");
  assert.equal(replaced.code, 0, replaced.stdout);
  assert.equal(s.stub.db.requests.filter(r => r.method === "DELETE").length, 1);
  assert.equal(s.stub.db.workstreams.length, 1);
  assert.equal(s.stub.db.workstreams[0].entries.length, 5);
});

test("a ledger of more than 100 pieces spans several appends in one workstream", async t => {
  const s = await setup(t);
  const big = Array.from({ length: 250 }, (_, i) => `Task ${i}: complete\n\n`).join("");
  write(path.join(s.repo, ".superpowers", "sdd", "p1", "progress.md"), big);
  assert.equal((await s.importing()).code, 0);
  const [ws] = s.stub.db.workstreams;
  assert.equal(ws.entries.length, 250);
  assert.equal(ws.entries.map(e => e.body).join(""), big);
  assert.equal(s.stub.db.requests.filter(r => r.path === "/api/v1/worklog/entries").length, 3);
});

test("the verification fails the import on a single changed byte", async t => {
  const s = await setup(t, { transformContent: content => content.replace("# Spec", "# Spex") });
  const result = await s.importing();
  assert.equal(result.code, 1);
  const failed = /failed: superpowers\/specs\/s\.md: a pull of darkmem's copy differs from the source; compare under (\S+)/.exec(result.stdout);
  assert.ok(failed, result.stdout);
  fs.rmSync(failed[1], { recursive: true, force: true });
});

test("an empty source file refuses the whole import before any write", async t => {
  const s = await setup(t);
  write(path.join(s.repo, "docs", "superpowers", "notes", "empty.md"), "");
  const result = await s.importing();
  assert.equal(result.code, 1);
  assert.match(result.stdout, /failed: .*empty\.md: empty or not UTF-8 text/);
  assert.match(result.stdout, /note: nothing was imported/);
  assert.equal(s.stub.db.requests.filter(r => r.method !== "GET").length, 0);
});

test("--replace purges before any document is written, so a refused purge writes nothing", async t => {
  const s = await setup(t);
  assert.equal((await s.importing()).code, 0);
  const writesBefore = s.stub.db.requests.filter(r => r.method === "POST" && r.path === "/api/v1/documents").length;
  s.stub.db.failures.push({ method: "DELETE", path: "/api/v1/worklog/workstreams/", status: 403, detail: "needs the admin scope" });
  const result = await s.importing("--replace");
  assert.equal(result.code, 3);
  assert.match(result.stderr, /import failed: DELETE .* answered 403: needs the admin scope/);
  assert.equal(s.stub.db.requests.filter(r => r.method === "POST" && r.path === "/api/v1/documents").length, writesBefore);
});

test("a plan directory whose name cannot be a workstream key refuses the import", async t => {
  const s = await setup(t);
  write(path.join(s.repo, ".superpowers", "sdd", "bad name", "progress.md"), "x\n");
  const result = await s.importing();
  assert.equal(result.code, 1);
  assert.match(result.stdout, /failed: .*bad name: not a usable workstream key/);
  assert.equal(s.stub.db.requests.filter(r => r.method !== "GET").length, 0);
});

test("a source file changed during the import fails its verification", async t => {
  let repo = null;
  const s = await setup(t, {
    onRequest: request => {
      if (request.method === "PATCH" && repo) write(path.join(repo, "docs", "superpowers", "specs", "s.md"), "# Spec, edited mid-import\n");
    },
  });
  repo = s.repo;
  const result = await s.importing();
  assert.equal(result.code, 1);
  assert.match(result.stdout, /failed: the source files changed during the import; run it again with --replace/);
});

test("import in local mode is exit 2", async () => {
  const repo = makeRepo();
  const { env } = makeHome({ repo, config: null });
  const result = await run(["import"], { cwd: repo, env });
  assert.equal(result.code, 2);
  assert.match(result.stdout, /^darkmem-sync: local mode/);
});
```

- [ ] **Step 2: Run it to verify it fails**

```bash
timeout 180 node --test --test-reporter=spec plugins/dr-superpowers/tests/darkmem-sync/import.test.mjs
```

Expected: `ℹ fail 9` — `import` is not a command yet, so every run is a usage error (exit 2) with nothing on stdout.

- [ ] **Step 3: Write the module and register the command**

Create `plugins/dr-superpowers/scripts/lib/darkmem-import.mjs`:

```js
// darkmem-sync import (darkmem mirror spec §3): the one-time move of a
// repository's docs/superpowers/ and its local ledgers and handoff notes into
// darkmem. It reads the repository, never the mirror, and finishes by pulling
// everything it filed into a scratch directory with pull's own code and
// comparing bytes. A pull afterwards fills the real mirror.
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { HttpError } from "./darkmem-client.mjs";
import {
  MAX_ENTRIES_PER_APPEND, decodeUtf8, emptyState, ledgerFiles, ledgerPlanPath, listDocumentFiles, propertiesFor,
  splitAtBlankLines, splitAtLimit, unsupportedPlanDirs, uriToLocal,
} from "./darkmem-mirror.mjs";
import { pullDocuments, pullLedgers } from "./darkmem-pull.mjs";

// The import's source snapshot. Every problem is collected, so one run names
// all of them.
function readSources(roots) {
  const problems = [];
  const documents = [];
  const ledgers = [];
  for (const dir of unsupportedPlanDirs(roots.workRoot)) problems.push(`${dir}: not a usable workstream key`);
  for (const { file, uri } of listDocumentFiles(roots)) {
    if (!uri) {
      problems.push(`${file}: docs/superpowers/handoff/ is reserved for handoff notes`);
      continue;
    }
    const buffer = fs.readFileSync(file);
    const content = decodeUtf8(buffer);
    if (!content) {
      problems.push(`${file}: empty or not UTF-8 text`);
      continue;
    }
    documents.push({ uri, buffer, content });
  }
  for (const { slug, file } of ledgerFiles(roots.workRoot)) {
    const buffer = fs.readFileSync(file);
    const text = decodeUtf8(buffer);
    if (!text) {
      problems.push(`${file}: empty or not UTF-8 text`);
      continue;
    }
    ledgers.push({ slug, buffer, text, mtime: fs.statSync(file).mtime.toISOString(), id: null });
  }
  return { problems, documents, ledgers };
}

async function importLedger({ cfg, client, report }, roots, ledger) {
  const pieces = splitAtBlankLines(ledger.text).flatMap(piece => splitAtLimit(piece));
  const properties = { ...propertiesFor(roots, ledger.slug, ledgerPlanPath(ledger.text)), imported_mtime: ledger.mtime };
  for (let i = 0; i < pieces.length; i += MAX_ENTRIES_PER_APPEND) {
    const entries = pieces.slice(i, i + MAX_ENTRIES_PER_APPEND).map(body => ({ kind: "ledger", body }));
    try {
      ledger.id = (await client.append({ project: cfg.project, workstream: ledger.slug, properties, entries })).workstream.id;
    } catch (error) {
      if (!(error instanceof HttpError && error.status === 422)) throw error;
      report.failures.push(`sdd/${ledger.slug}/progress.md: darkmem refused an entry: ${error.detail}`);
      ledger.id = null;
      return;
    }
  }
  await client.updateWorkstream(ledger.id, { state: "closed", retain: true });
  report.counts.workstreams += 1;
}

const sameBytes = (file, buffer) => fs.existsSync(file) && fs.readFileSync(file).equals(buffer);

async function verify(context, roots, snapshot) {
  const { report } = context;
  const again = readSources(roots);
  const inventory = source => [...source.documents.map(d => d.uri), ...source.ledgers.map(l => `sdd/${l.slug}`)].sort().join("\n");
  const changed = inventory(again) !== inventory(snapshot)
    || again.documents.some((d, i) => !d.buffer.equals(snapshot.documents[i].buffer))
    || again.ledgers.some((l, i) => !l.buffer.equals(snapshot.ledgers[i].buffer));
  if (changed || again.problems.length) {
    report.failures.push("the source files changed during the import; run it again with --replace");
    return;
  }
  const scratch = fs.mkdtempSync(path.join(os.tmpdir(), "darkmem-import-"));
  const scratchRoots = { docsRoot: path.join(scratch, "superpowers"), workRoot: path.join(scratch, "work") };
  const scratchContext = {
    ...context,
    roots: scratchRoots,
    state: emptyState(),
    persist: () => {},
    report: { conflicts: [], failures: [], notes: [], counts: { documents: 0, ledgers: 0 } },
  };
  await pullDocuments(scratchContext);
  const imported = snapshot.ledgers.filter(l => l.id).map(l => ({ id: l.id, key: l.slug }));
  await pullLedgers(scratchContext, imported);
  const differing = [
    ...snapshot.documents.filter(d => !sameBytes(uriToLocal(scratchRoots, d.uri), d.buffer)).map(d => d.uri),
    ...snapshot.ledgers.filter(l => !sameBytes(path.join(scratchRoots.workRoot, "sdd", l.slug, "progress.md"), l.buffer)).map(l => `sdd/${l.slug}/progress.md`),
  ];
  if (differing.length) {
    for (const name of differing) report.failures.push(`${name}: a pull of darkmem's copy differs from the source; compare under ${scratch}`);
    return;
  }
  fs.rmSync(scratch, { recursive: true, force: true });
  report.notes.push("verified: a pull of every imported file reads back byte-identical");
}

export async function importRepository(context) {
  const { cfg, client, report, options } = context;
  Object.assign(report.counts, { documents: 0, workstreams: 0 });
  const roots = { docsRoot: path.join(cfg.repoRoot, "docs", "superpowers"), workRoot: path.join(cfg.repoRoot, ".superpowers") };
  const snapshot = readSources(roots);
  if (snapshot.problems.length) {
    report.failures.push(...snapshot.problems);
    report.notes.push("nothing was imported");
    return;
  }
  const existing = new Map();
  for (const ledger of snapshot.ledgers) {
    const answer = await client.resume(cfg.project, ledger.slug);
    if (answer) existing.set(ledger.slug, answer.workstream.id);
  }
  if (existing.size && !options["--replace"]) {
    report.failures.push(`already in darkmem: ${[...existing.keys()].join(", ")}; run import --replace to purge and re-import them (needs an admin key)`);
    report.notes.push("nothing was imported");
    return;
  }
  // Purges come first: a key that may not purge stops the import before any
  // document is written.
  for (const id of existing.values()) await client.purgeWorkstream(id);
  for (const doc of snapshot.documents) {
    try {
      await client.putDocument({ project: cfg.project, uri: doc.uri, content: doc.content });
      report.counts.documents += 1;
    } catch (error) {
      if (!(error instanceof HttpError && error.status === 422)) throw error;
      report.failures.push(`${doc.uri}: darkmem refused it: ${error.detail}`);
    }
  }
  for (const ledger of snapshot.ledgers) await importLedger(context, roots, ledger);
  await verify(context, roots, snapshot);
}
```

In `plugins/dr-superpowers/scripts/lib/darkmem-sync.mjs`, add before the `darkmem-pull.mjs` import line:

```js
import { importRepository } from "./darkmem-import.mjs";
```

and add after the `push:` line of `COMMANDS`:

```js
  import: { options: { "--replace": false }, needsDarkmem: true, recordsConflicts: false, run: importRepository },
```

- [ ] **Step 4: Run it to verify it passes**

```bash
timeout 180 node --test --test-reporter=spec plugins/dr-superpowers/tests/darkmem-sync/import.test.mjs
timeout 300 bash plugins/dr-superpowers/tests/darkmem-sync.test.sh | grep -E '^ℹ (tests|pass|fail)'
```

Expected: `ℹ pass 9`, `ℹ fail 0`; then `ℹ tests 69`, `ℹ pass 69`, `ℹ fail 0`.

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-superpowers/scripts/lib/darkmem-import.mjs plugins/dr-superpowers/scripts/lib/darkmem-sync.mjs plugins/dr-superpowers/tests/darkmem-sync/import.test.mjs
git commit -m "feat(superpowers): add darkmem-sync import" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 8: Release 1.22.0

**Files:**
- Modify: `plugins/dr-superpowers/README.md` (after the **Project state** paragraph, and after the `codex-review.test.sh` paragraph under `## Tests`)
- Modify: `plugins/dr-superpowers/.claude-plugin/plugin.json:5`
- Modify: `plugins/dr-superpowers/.codex-plugin/plugin.json:3`
- Modify: `docs/superpowers/registers/2026-09-24-darkmem-mirror.md` (one row, through `scripts/register`)
- Test: `plugins/dr-superpowers/tests/review-route.test.sh:581-582`

**Interfaces:**
- Consumes: Tasks 1–7 committed.
- Produces: nothing.

**Implementer:** dr-superpowers:impl-sonnet-low
**Evaluation:** files 1 - spec 0 - coupling 0 - risk 0 = 1

- [ ] **Step 1: Write the failing assertion**

In `plugins/dr-superpowers/tests/review-route.test.sh`, replace

```bash
present "the Claude manifest is 1.21.0" "$P/.claude-plugin/plugin.json" '"version": "1.21.0"'
present "the Codex manifest is 1.21.0" "$P/.codex-plugin/plugin.json" '"version": "1.21.0"'
```

with

```bash
present "the Claude manifest is 1.22.0" "$P/.claude-plugin/plugin.json" '"version": "1.22.0"'
present "the Codex manifest is 1.22.0" "$P/.codex-plugin/plugin.json" '"version": "1.22.0"'
```

- [ ] **Step 2: Run it to verify it fails**

```bash
timeout 300 bash plugins/dr-superpowers/tests/review-route.test.sh | grep -E '^FAIL|passed'
```

Expected: two `FAIL` lines naming the manifests, and `2 failed`.

- [ ] **Step 3: Bump both manifests and document the command**

In both `plugins/dr-superpowers/.claude-plugin/plugin.json` and `plugins/dr-superpowers/.codex-plugin/plugin.json`, change `"version": "1.21.0"` to `"version": "1.22.0"`. Nothing else in either file changes.

In `plugins/dr-superpowers/README.md`, insert after the paragraph that ends `optional; a project without them behaves exactly as before.` (one blank line before and after):

```markdown
**darkmem mirror (optional).** `scripts/darkmem-sync` keeps a repository's
  planning documents and progress in a darkmem instance over its keyed REST
  routes. Map the repository's primary checkout in
  `~/.dr-superpowers/config.json` —
  `{"darkmem": {"url": "http://<host>:8000", "api_key_env": "DARKMEM_API_KEY", "repos": {"<primary checkout path>": {"project": "<name>"}}}}`
  — and export a `dmk_` key in that variable, and the repository syncs a mirror
  at `~/.dr-superpowers/mirror/<project>/`. `pull` fetches what changed;
  `push` sends documents under their last synced hash and ledgers as the bytes
  appended since the last push; `status` lists local changes and the last
  run's conflicts; `import` moves an existing `docs/superpowers/` and its
  ledgers in once, verified byte for byte. A conflict is reported, never
  merged. Without a mapping every command but `import` prints one line and
  does nothing. The skills do not call it yet: they still read and write the
  repository's own paths.
```

and append to the paragraph under `## Tests` that ends `report — is exercised without a model call.`, on the lines directly after it:

```markdown
`darkmem-sync.test.sh` runs the `node:test` suites under
`tests/darkmem-sync/` against an in-memory stub of darkmem's routes, so no
darkmem instance is needed.
```

- [ ] **Step 4: Run the full validation**

```bash
timeout 300 bash plugins/dr-superpowers/tests/review-route.test.sh | tail -1
timeout 60 node scripts/validate-repository.mjs
timeout 900 node scripts/test-all.mjs > .superpowers/darkmem-sync-test-all.log 2>&1; echo "test-all=$?"
grep -E '^Finished .*\(exit [^0]' .superpowers/darkmem-sync-test-all.log
grep -E '^✖ ' .superpowers/darkmem-sync-test-all.log | sort -u
for p in . plugins/dr-status plugins/dr-superpowers plugins/dcc-darkraise-ui plugins/dcc-darkraise-win32ui; do timeout 60 claude plugin validate "$p" | tail -1; done
```

Expected: `229 passed, 0 failed`; `Repository catalogs, manifests, versions, and bundled links are valid.`; five lines of `✔ Validation passed`.

`test-all` either passes completely (`test-all=0`, and both greps print nothing) or fails only on the known environmental case. That case prints `test-all=1`, exactly one `Finished` line (the combined root job `Finished --test tests/repository-layout.test.mjs tests/test-shards.test.mjs tests/ui-discovery.test.mjs in <t>s (exit 1)`), and `✖` lines naming only `documented Win32 discovery finds centrally managed versions` plus the runner's own `✖ failing tests:` header. Any other `Finished … (exit N)` line or `✖` test name is a regression from this plan: keep the log, stop, and fix it before committing. Once the failures are classified, remove the log:

```bash
rm -f .superpowers/darkmem-sync-test-all.log
```

- [ ] **Step 5: Record the Windows check for the owner**

Nothing here can run Windows, and CI runs only on a push, which is the owner's. Record the check as a register row, so finishing the branch surfaces it:

```bash
bash plugins/dr-superpowers/scripts/register add docs/superpowers/registers/2026-09-24-darkmem-mirror.md "darkmem-sync on Windows: CI's six Windows shards green at the release commit" --state verify --note "the suite has run on Linux only; a red Windows shard reopens row 1"
bash plugins/dr-superpowers/scripts/register check docs/superpowers/registers/2026-09-24-darkmem-mirror.md
```

Expected: `register: 0 errors`.

- [ ] **Step 6: Commit**

```bash
git add plugins/dr-superpowers/README.md plugins/dr-superpowers/.claude-plugin/plugin.json plugins/dr-superpowers/.codex-plugin/plugin.json plugins/dr-superpowers/tests/review-route.test.sh docs/superpowers/registers/2026-09-24-darkmem-mirror.md
git commit -m "feat(superpowers): release darkmem-sync as 1.22.0" -m "Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```
