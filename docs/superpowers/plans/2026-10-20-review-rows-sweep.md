# Review Rows Sweep Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: the skill the **Execution:** line names — dr-superpowers:subagent-driven-development for `subagent`, dr-superpowers:executing-plans for `inline`. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the eight register rows the open-rows sweep's final review left open, verify DF 27 on this host, and release dforge 4.2.2.

**Architecture:** The darkmem moves gain one non-blocking read helper (`readRegular`), and every plain read in the two move modules goes through it: with no link following for files in the mirror and the checkout, and with link following for `auto-run.json`, `completed.md` and `fileHash`. A tracked document deleted during a move's pull becomes a refusal instead of a crash, and one refusal's wording is corrected. Three unrelated small fixes (the executor probe's request, the eval parser's no-exec flags, a config test) run beside each other, then the release and a host check.

**Tech Stack:** Node ES modules with `node --test`, Bash scripts and their bash test suites, Markdown.

**Spec:** docs/superpowers/specs/2026-10-20-review-rows-sweep-design.md

**Execution:** subagent — `claude --model sonnet --effort high` — the plan runs parallel waves, which only subagent mode can run

**Plan review:** 2026-10-20 — codex gpt-6-astra / xhigh — executability 16 / coherence 15 / coverage 15 / assumptions 16 (round 1)

**Parallelism:** waves — 1 | 2 | 3 | 4-5 | 6-8 | 9-10

**Integration check:** `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID timeout 1800 node scripts/test-all.mjs && timeout 120 node scripts/validate-repository.mjs && timeout 120 /root/.local/bin/claude plugin validate . && timeout 120 /root/.local/bin/claude plugin validate plugins/dforge && timeout 120 /root/.local/bin/claude plugin validate plugins/dr-status && timeout 120 /root/.local/bin/claude plugin validate plugins/darkraise-ui && timeout 120 /root/.local/bin/claude plugin validate plugins/darkraise-win32ui && env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID timeout 300 /root/.local/bin/claude plugin test plugins/dforge`

**Worktree setup:** none

## Global Constraints

- Controller only, once before Task 1: create the plan's worktree from local `main` (local `main` runs ahead of `origin/main`) with `timeout 60 git worktree add .claude/worktrees/review-rows-sweep -b review-rows-sweep main`, and set the commit identity in it with `timeout 60 git config user.name Darkraise` and `timeout 60 git config user.email quangtc94@gmail.com`. An implementer works in the workspace the controller assigns, which holds every earlier wave's merged work, and creates no worktree or branch. Do not push.
- No `Co-Authored-By`, `Claude-Session` or other AI attribution in any commit.
- Commit subjects: `<type>(<scope>): <subject>`, type one of feat|fix|docs|style|refactor|test|chore|perf, at most 50 characters, imperative, no period.
- Never edit plans, specs or notes under `docs/superpowers/`, except `docs/superpowers/distilled/constraints.md` in Task 7; register rows change only through the installed plugin's `<plugin-root>/scripts/register`.
- Every test, build or CLI command runs under `timeout`, a step's checks (`grep`, `git diff`, `git show`, `sed`) included; only the commit blocks and one-line file setup or cleanup (`mkdir`, `printf … >`, `cat`, `rm`, `cp`) run without one. Leave no process running.
- Run every test suite, `scripts/test-all.mjs` and `claude plugin test` with `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID` in front.
- `claude` and `rg` are shell functions on this host: call `/root/.local/bin/claude`, and use `grep` in scripts and steps.
- Each suite makes its own temporary directories, so no two tasks' tests meet at run time; the named pipes the darkmem tests create live inside them.
- The darkmem sync suites start a localhost stub server (`plugins/dforge/tests/darkmem-sync/stub-server.mjs`); run them with `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID timeout 900 bash plugins/dforge/tests/darkmem-sync.test.sh` or `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID timeout 600 node --test <file>`.
- A darkmem test whose fix is missing and that meets a named pipe through the CLI child hangs until `run()`'s 30-second timeout and fails as `-1 !== 1`; a failing-first run of several such tests takes a few minutes.
- Keep `DCC_*` variables and statusline storage paths as they are.
- When a quoted anchor is not found, the file changed since the task was written: find the code by its function and intent, make the same change, and say so in the task report. Never invent a change the task does not describe.

## Contracts

- **`readRegular` (Task 1; Tasks 2-4 use it).** `export function readRegular(file, { follow = false } = {}, constants = fs.constants)` in `plugins/dforge/scripts/lib/darkmem-progress-move.mjs`, a `function` declaration (reconcile imports it across the two modules' import cycle). It returns a `Buffer`, or throws an `Error` whose `code` is `EISDIR` (a directory), `EFTYPE` (any other non-regular file: a named pipe, a device, a socket), or the open's or read's own code (`ENOENT`, `EACCES`, `ENOTDIR`). With `follow: false` a symbolic link at the last component, a dangling one included, throws `ELOOP`; links in earlier path components are always followed. It opens with `O_RDONLY | O_NONBLOCK`, plus `O_NOFOLLOW` without `follow`, so a named pipe never blocks. When `constants.O_NOFOLLOW` or `constants.O_NONBLOCK` is undefined (Windows) it lstats (only without `follow`), throws `ELOOP` for a link, then `fs.readFileSync(file)`.
- **`readNoFollow` (unchanged name).** `export function readNoFollow(file, constants = fs.constants)` returns `readRegular(file, { follow: false }, constants)`; every existing caller keeps its error mapping.
- **`namedPipe` (Task 1; Tasks 2-3 use it).** `export function namedPipe(file)` in `plugins/dforge/tests/darkmem-sync/helpers.mjs` makes `file`'s directory, runs `mkfifo file`, throws `Error("mkfifo <file>: <stderr>")` when that fails, and returns `file`. Tests that call it skip on `win32`.
- **Read error lines (Tasks 2-4).** `checkProgressTargets` and `progressToLocal`'s target pre-check report `<path>: could not be read (<code>)`; `renderCheckpoint` reports `handoff/latest.md: could not be read (<code>)`; `documentsToLocal` reports an unreadable existing copy as `<name>: already exists with different content`; `carriedDocuments` reports `<file>: could not be read (<code>)` and `<file>: missing from the working tree`, each also marking its uri uncarriable, so the documents move's recheck reads `<uri>: changed during the move`.
- **Followed reads (Task 3).** `inProgress` reads `auto-run.json` and `planFinished` reads `completed.md` through `readRegular(…, { follow: true })`; any error means no active run and not finished. `fileHash(file)` returns the sha256 of `readRegular(file, { follow: true })`, `null` on `ENOENT` or `ENOTDIR`, `NOT_A_FILE` on `EISDIR` or `EFTYPE`, and rethrows anything else.
- **`carriedDocuments` export (Task 4).** `export function carriedDocuments(repoRoot, docsDir, rel)` in `darkmem-reconcile.mjs`, unchanged otherwise: `{ failed?, problems, documents, uncarriable }`.
- **Relink refusal (Task 5).** `progressToDarkmem`'s second mirror-link check refuses as `the mirror's progress <found>; nothing was moved locally, and darkmem keeps what it accepted`; its first check keeps `…; nothing was sent or moved`.

## Assumptions (evidence)

- Every task was drafted against HEAD 25cf283 and run through its fail-then-pass cycle in a scratch copy (`git archive HEAD`), Tasks 1-8 applied in order, on 2026-10-20. With all eight applied, `darkmem-sync.test.sh` passed 389 of 389, `detect.test.sh` 63, `dforge-config.test.sh` 195 (as root), and the eval controller suites 33 of 33; `node scripts/test-all.mjs` finished all 58 jobs with exit 0 (its tsc job skipped: the scratch copy has no generated types; run before the plan review added Task 2's and Task 3's swap tests and Task 8's cap check, which then passed in their own suites). Each Step 2 below quotes the failure that run produced.
- Node v24.18.0 on this Linux host (uid 0). An `O_RDONLY | O_NONBLOCK` open of a named pipe with no writer returns at once and `fstat` reports a FIFO; with `O_NOFOLLOW` a link fails with `ELOOP` (the open-rows sweep's probe, 2026-10-20, repeated here by Task 1's tests). `fs.statSync(path, { throwIfNoEntry: false })` returns `undefined` for `ENOTDIR` as well as `ENOENT` (probe, 2026-10-20), so Task 3's `fileHash` maps both to `null`. macOS and Windows are not run here; POSIX specifies the non-blocking FIFO open (https://pubs.opengroup.org/onlinepubs/9799919799/functions/open.html), and Windows takes the lstat fallback, unit-tested with each constant removed.
- `fs.readFileSync(path)` without an encoding opens through the exported `fs.openSync`, so Task 4's `t.mock.method(fs, "openSync")` reaches the old code's read and the new one's (the old code failed with an uncaught `EISDIR` read, 2026-10-20).
- The Codex executor lane is on (`codex-gate` printed `usable=true reason=ok review=true lane=true`, probe, 2026-10-20), and `docs/superpowers/distilled/constraints.md` ticks it, but this plan is Claude-only by the owner's ruling of 2026-10-20: an Executor task runs alone in its wave, and Tasks 6 and 7, which pass the lane gate, would leave wave 2 of the approved parallel strategy with one task. The ruling scopes the constraint for this plan only. plan-lint's lane-eligibility warnings for Tasks 5, 6 and 7 are that ruling; Task 5 could not take the lane anyway, since its suite starts a localhost stub server, which the Codex sandbox refuses (register DM row 32's note).
- DF 27 is unverified until Task 10 runs: `tests/ui-discovery.test.mjs` skips its Win32 discovery test here (`rg is not installed`, 2026-10-20), and `apt-cache policy ripgrep` offers 14.1.1-1+b4. The test probes `rg` through a non-interactive `bash -c`, which does not load the `rg` shell function.
- Where a task departs from the spec's wording, reading the code required it:
  - The spec's P1 item 1 helper and its call sites are split into Task 1 (helper, tests) and Task 2 (the no-follow call sites), by Rule S.
  - P1 item 3: the mirror side of `documentsToLocal`'s killed-run comparison is reached in-process through the exported `reconcile(context)`, offline (darkmem turned off), since `documentsToLocal` itself is private.
  - P1 item 4: `fileHash` no longer `stat`s before it reads (Task 3); the swap its Check names is a file replaced by a directory as `fileHash` opens it, which the old code read after its `stat` and crashed on.
  - P1 item 5: the read-race case needs `carriedDocuments` in-process, so Task 4 exports it. A swap to a directory, not a named pipe, is the failing-first case: the old code's plain read of a pipe would hang the test runner.
  - P4: through the command, a 41-link dangling chain makes `fs.realpathSync` throw `ELOOP` (the kernel's 40-link limit) before `realTarget`'s own loop runs, so `dforge-config.mjs`'s `more than 40 symbolic links` cap is never reached on Linux (run, 2026-10-20), and a chain test through `fc` alone passes with the cap raised. Task 8 therefore adds a second check that stubs `fs.realpathSync` to report `ENOENT` in a child Node process, which reaches the cap; with `MAX_LINK_HOPS` raised to 41 that check fails (run, 2026-10-20). The module loader itself calls `realpathSync`, so the stub goes in after the import.
- The register rows this plan schedules (CX 17, DM 62-65, DF 26, DF 27, FS 50) were set `planned`, assigned to this plan, and DF 21's note was set to the spec's Scope wording, in the same commit as this plan; `main` holds them before Task 1 starts.
- Adjacent, not fixed here: on macOS, whose kernel allows 32 links, the existing 40-link dangling-chain test would also meet `ELOOP` from `realpathSync`, so `realTarget` would refuse a chain its loop is meant to follow (inference from the Linux behaviour; macOS is not run here).

## Task index

1. Add the non-blocking read helper
2. Read move targets without blocking on a pipe
3. Read followed records without blocking on a pipe
4. Refuse a document deleted during the pull
5. Say darkmem keeps what it accepted after a relink
6. Build the probe request with jq
7. Count no run for a shell told not to execute
8. Guard the 41-link settings chain
9. Release dforge 4.2.2
10. Run the Win32 discovery test with ripgrep

---

### Task 1: Add the non-blocking read helper

`readNoFollow` in `darkmem-progress-move.mjs` already opens without blocking and refuses links; the reads that must follow links (Task 3) need the same non-blocking open. This task generalises it into `readRegular(file, { follow })`, keeps `readNoFollow` as a wrapper, and widens the Windows fallback to fire when either `O_NOFOLLOW` or `O_NONBLOCK` is missing. It also moves the test suite's `namedPipe` helper into `helpers.mjs`, so `reconcile.test.mjs` can use it in Tasks 2 and 3.

**Files:**
- Modify: `plugins/dforge/scripts/lib/darkmem-progress-move.mjs`
- Modify: `plugins/dforge/tests/darkmem-sync/helpers.mjs`
- Test: `plugins/dforge/tests/darkmem-sync/reconcile-progress.test.mjs`

**Interfaces:**
- Consumes: None
- Produces: Contracts `readRegular`, `readNoFollow`, `namedPipe`

**Items:** DM 62, DM 64

**Depends on:** none
**Implementer:** dr-superpowers:impl-sonnet-high
**Evaluation:** files 1 - spec 0 - coupling 2 - risk 2 = 5

- [ ] **Step 1: Move the named-pipe helper and write the failing tests**

In `plugins/dforge/tests/darkmem-sync/helpers.mjs`, find:

```js
export function read(file) {
  return fs.readFileSync(file, "utf8");
}
```

Replace it with:

```js
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
```

In `plugins/dforge/tests/darkmem-sync/reconcile-progress.test.mjs`, find:

```js
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import fs from "node:fs";
```

Replace it with:

```js
import assert from "node:assert/strict";
import fs from "node:fs";
```

Find:

```js
import { checkProgressTargets, gatherLocalProgress, progressToLocal, readNoFollow } from "../../scripts/lib/darkmem-progress-move.mjs";
import { STUB_KEY, sha, startStub } from "./stub-server.mjs";
import { git, makeHome, makeRepo, read, run, scratch, write } from "./helpers.mjs";
```

Replace it with:

```js
import { checkProgressTargets, gatherLocalProgress, progressToLocal, readNoFollow, readRegular } from "../../scripts/lib/darkmem-progress-move.mjs";
import { STUB_KEY, sha, startStub } from "./stub-server.mjs";
import { git, makeHome, makeRepo, namedPipe, read, run, scratch, write } from "./helpers.mjs";
```

Delete this block (the helper now lives in `helpers.mjs`), including the blank line after it:

```js
// A named pipe nobody writes to: a plain read of it, or through a link to it,
// blocks. Only the command run as a child process meets one before its fix,
// so a blocked read ends at run()'s timeout instead of stopping this file.
function namedPipe(file) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  const made = spawnSync("mkfifo", [file], { encoding: "utf8", timeout: 10000 });
  assert.equal(made.status, 0, made.stderr || made.error?.message);
  return file;
}

```

Find:

```js
test("without O_NOFOLLOW, as on Windows, readNoFollow refuses a link by lstat before it reads", { skip: process.platform === "win32" }, () => {
  const dir = scratch("dms-read-");
  const file = path.join(dir, "file");
  write(file, "bytes\n");
  fs.symlinkSync(file, path.join(dir, "link"));
  const windows = { ...fs.constants, O_NOFOLLOW: undefined };
  assert.equal(readNoFollow(file, windows).toString(), "bytes\n");
  assert.throws(() => readNoFollow(path.join(dir, "link"), windows), { code: "ELOOP" });
});
```

Replace it with:

```js
test("readRegular with follow reads through a link, and refuses a named pipe, a link to one and a directory", { skip: process.platform === "win32" }, () => {
  const dir = scratch("dms-read-");
  const file = path.join(dir, "file");
  write(file, "bytes\n");
  fs.symlinkSync(file, path.join(dir, "link"));
  fs.symlinkSync(namedPipe(path.join(dir, "pipe")), path.join(dir, "pipe-link"));
  fs.mkdirSync(path.join(dir, "dir"));
  assert.equal(readRegular(path.join(dir, "link"), { follow: true }).toString(), "bytes\n");
  for (const [name, code] of [["pipe", "EFTYPE"], ["pipe-link", "EFTYPE"], ["dir", "EISDIR"], ["missing", "ENOENT"]]) {
    assert.throws(() => readRegular(path.join(dir, name), { follow: true }), { code }, name);
  }
});

for (const removed of ["O_NOFOLLOW", "O_NONBLOCK"]) {
  test(`without ${removed}, as on Windows, readNoFollow refuses a link by lstat before it reads, and readRegular with follow reads through it`, { skip: process.platform === "win32" }, t => {
    const dir = scratch("dms-read-");
    const file = path.join(dir, "file");
    const link = path.join(dir, "link");
    write(file, "bytes\n");
    fs.symlinkSync(file, link);
    const windows = { ...fs.constants, [removed]: undefined };
    const lstat = t.mock.method(fs, "lstatSync");
    assert.equal(readNoFollow(file, windows).toString(), "bytes\n");
    assert.equal(lstat.mock.callCount(), 1, "the fallback lstats before it reads");
    assert.throws(() => readNoFollow(link, windows), { code: "ELOOP" });
    assert.equal(readRegular(link, { follow: true }, windows).toString(), "bytes\n");
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID timeout 600 node --test plugins/dforge/tests/darkmem-sync/reconcile-progress.test.mjs`
Expected: FAIL — the file does not load: `SyntaxError: The requested module '../../scripts/lib/darkmem-progress-move.mjs' does not provide an export named 'readRegular'`.

- [ ] **Step 3: Implement**

In `plugins/dforge/scripts/lib/darkmem-progress-move.mjs`, find:

```js
// `file`'s bytes, read without following a symbolic link at its last component
// and without blocking on a FIFO or device: it throws an error whose code is
// ELOOP for a symbolic link (a dangling one too), EISDIR for a directory,
// EFTYPE for any other file that is not regular, or the open's or read's own
// (ENOENT, EACCES, ENOTDIR). Links earlier in the path are followed. A function
// declaration, since darkmem-reconcile.mjs imports it across the import cycle
// between the two modules. Without O_NOFOLLOW (Windows) a link is refused by
// lstat before the read, which leaves a window between the two. fs.constants
// cannot be stubbed, so a test passes a copy without O_NOFOLLOW as `constants`.
export function readNoFollow(file, constants = fs.constants) {
  if (constants.O_NOFOLLOW === undefined) {
    if (fs.lstatSync(file, { throwIfNoEntry: false })?.isSymbolicLink()) throw Object.assign(new Error(`${file} is a symbolic link`), { code: "ELOOP" });
    return fs.readFileSync(file);
  }
  const fd = fs.openSync(file, constants.O_RDONLY | constants.O_NOFOLLOW | constants.O_NONBLOCK);
```

Replace it with:

```js
// `file`'s bytes, read without blocking on a FIFO or device: it throws an
// error whose code is EISDIR for a directory, EFTYPE for any other file that
// is not regular, or the open's or read's own (ENOENT, EACCES, ENOTDIR).
// Without `follow`, a symbolic link at the last component (a dangling one
// too) throws ELOOP; links earlier in the path are always followed. Function
// declarations, since darkmem-reconcile.mjs imports them across the import
// cycle between the two modules. Without O_NOFOLLOW or O_NONBLOCK (Windows,
// which has no FIFOs) a link is refused by lstat before the read, which
// leaves a window between the two. fs.constants cannot be stubbed, so a test
// passes a copy without them as `constants`.
export function readRegular(file, { follow = false } = {}, constants = fs.constants) {
  if (constants.O_NOFOLLOW === undefined || constants.O_NONBLOCK === undefined) {
    if (!follow && fs.lstatSync(file, { throwIfNoEntry: false })?.isSymbolicLink()) throw Object.assign(new Error(`${file} is a symbolic link`), { code: "ELOOP" });
    return fs.readFileSync(file);
  }
  const fd = fs.openSync(file, constants.O_RDONLY | constants.O_NONBLOCK | (follow ? 0 : constants.O_NOFOLLOW));
```

Then find the end of the same function:

```js
    return fs.readFileSync(fd);
  } finally {
    fs.closeSync(fd);
  }
}
```

Replace it with:

```js
    return fs.readFileSync(fd);
  } finally {
    fs.closeSync(fd);
  }
}

export function readNoFollow(file, constants = fs.constants) {
  return readRegular(file, { follow: false }, constants);
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID timeout 600 node --test plugins/dforge/tests/darkmem-sync/reconcile-progress.test.mjs`
Expected: PASS, 0 fail.

Run: `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID timeout 900 bash plugins/dforge/tests/darkmem-sync.test.sh`
Expected: PASS, 0 fail.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/scripts/lib/darkmem-progress-move.mjs plugins/dforge/tests/darkmem-sync/helpers.mjs plugins/dforge/tests/darkmem-sync/reconcile-progress.test.mjs
git commit -m "refactor(darkmem): add a non-blocking read helper"
```

---

### Task 2: Read move targets without blocking on a pipe

Four reads in the progress and documents moves use a plain `fs.readFileSync`, so a named pipe at the path blocks reconcile forever: the mirror's copy of a progress file (`checkProgressTargets`), the primary checkout's copy (`progressToLocal`'s pre-check), the mirror's `handoff/latest.md` (`renderCheckpoint`), and an existing `docs/dforge` copy (`documentsToLocal`'s killed-run comparison). Each switches to `readNoFollow`; an unreadable file joins the error list the site already has.

**Files:**
- Modify: `plugins/dforge/scripts/lib/darkmem-progress-move.mjs`
- Modify: `plugins/dforge/scripts/lib/darkmem-reconcile.mjs`
- Test: `plugins/dforge/tests/darkmem-sync/reconcile-progress.test.mjs`
- Test: `plugins/dforge/tests/darkmem-sync/reconcile.test.mjs`

**Interfaces:**
- Consumes: Contracts `readNoFollow`, `namedPipe`
- Produces: Contracts "Read error lines" (the first three sites)

**Items:** DM 62

**Depends on:** Task 1
**Implementer:** dr-superpowers:impl-sonnet-high
**Evaluation:** files 2 - spec 0 - coupling 1 - risk 2 = 5

- [ ] **Step 1: Write the failing tests**

In `plugins/dforge/tests/darkmem-sync/reconcile-progress.test.mjs`, find:

```js
test("a primary checkout file that cannot be read keeps progress in darkmem, not a crash", async t => {
  const s = await setup(t, "local");
  await s.seed.append({ project: "proj", workstream: "p1", entries: [{ kind: "ledger", body: LEDGER("p1") }] });
  const target = path.join(s.repo, ".dforge", "sdd", "p1", "progress.md");
  fs.mkdirSync(target, { recursive: true });
  const result = await s.reconcile();
  assert.equal(result.code, 1, result.stdout + result.stderr);
  assert.match(result.stdout, /^darkmem-sync reconcile: progress stay darkmem \(configured local\): the primary checkout cannot take the mirror's progress$/m);
  assert.ok(result.stdout.includes(`  ${target}: could not be read (EISDIR)\n`), result.stdout);
  assert.equal(s.stores().progress, "darkmem");
});
```

Replace it with:

```js
for (const [what, plant, code] of [["a directory", file => fs.mkdirSync(file, { recursive: true }), "EISDIR"], ["a named pipe", namedPipe, "EFTYPE"]]) {
  test(`a primary checkout file that is ${what} keeps progress in darkmem, not a crash or a blocking read`, { skip: code === "EFTYPE" && process.platform === "win32" }, async t => {
    const s = await setup(t, "local");
    await s.seed.append({ project: "proj", workstream: "p1", entries: [{ kind: "ledger", body: LEDGER("p1") }] });
    const target = path.join(s.repo, ".dforge", "sdd", "p1", "progress.md");
    plant(target);
    const result = await s.reconcile();
    assert.equal(result.code, 1, result.stdout + result.stderr);
    assert.match(result.stdout, /^darkmem-sync reconcile: progress stay darkmem \(configured local\): the primary checkout cannot take the mirror's progress$/m);
    assert.ok(result.stdout.includes(`  ${target}: could not be read (${code})\n`), result.stdout);
    assert.equal(s.stores().progress, "darkmem");
  });
}
```

Find:

```js
test("a mirror latest.md that cannot be read keeps progress in darkmem, not a crash", async t => {
  const s = await setup(t, "local");
  await s.seed.append({ project: "proj", workstream: "p1", entries: [{ kind: "ledger", body: LEDGER("p1") }, { kind: "checkpoint", body: LATEST }] });
  fs.mkdirSync(path.join(s.workRoot, "handoff", "latest.md"), { recursive: true });
  const result = await s.reconcile();
  assert.equal(result.code, 1, result.stdout + result.stderr);
  assert.match(result.stdout, /^darkmem-sync reconcile: progress stay darkmem \(configured local\): the pull into the mirror did not finish cleanly$/m);
  assert.ok(result.stdout.includes("  failed: handoff/latest.md: could not be read (EISDIR)\n"), result.stdout);
  assert.equal(s.stores().progress, "darkmem");
});
```

Replace it with:

```js
for (const [what, plant, code] of [["a directory", file => fs.mkdirSync(file, { recursive: true }), "EISDIR"], ["a named pipe", namedPipe, "EFTYPE"]]) {
  test(`a mirror latest.md that is ${what} keeps progress in darkmem, not a crash or a blocking read`, { skip: code === "EFTYPE" && process.platform === "win32" }, async t => {
    const s = await setup(t, "local");
    await s.seed.append({ project: "proj", workstream: "p1", entries: [{ kind: "ledger", body: LEDGER("p1") }, { kind: "checkpoint", body: LATEST }] });
    plant(path.join(s.workRoot, "handoff", "latest.md"));
    const result = await s.reconcile();
    assert.equal(result.code, 1, result.stdout + result.stderr);
    assert.match(result.stdout, /^darkmem-sync reconcile: progress stay darkmem \(configured local\): the pull into the mirror did not finish cleanly$/m);
    assert.ok(result.stdout.includes(`  failed: handoff/latest.md: could not be read (${code})\n`), result.stdout);
    assert.equal(s.stores().progress, "darkmem");
  });
}
```

Find:

```js
test("a handoff note linked to a named pipe while darkmem is written stays local, and the recheck never blocks on it", { skip: process.platform === "win32" }, async t => {
```

Replace it with:

```js
test("a named pipe at the mirror's copy of a ledger is a problem, and is never opened for a blocking read", { skip: process.platform === "win32" }, async t => {
  const s = await setup(t, "darkmem");
  write(path.join(s.repo, ".dforge", "sdd", "p1", "progress.md"), LEDGER("p1"));
  const target = namedPipe(path.join(s.workRoot, "sdd", "p1", "progress.md"));
  const result = await s.reconcile();
  assert.equal(result.code, 1, result.stdout + result.stderr);
  assert.ok(result.stdout.includes("darkmem-sync reconcile: progress stay local (configured darkmem): darkmem or the mirror already holds different progress\n"), result.stdout);
  assert.ok(result.stdout.includes(`  ${target}: could not be read (EFTYPE)\n`), result.stdout);
  assert.equal(s.stores().progress, "local");
});

test("a handoff note linked to a named pipe while darkmem is written stays local, and the recheck never blocks on it", { skip: process.platform === "win32" }, async t => {
```

In `plugins/dforge/tests/darkmem-sync/reconcile.test.mjs`, find:

```js
import { utcStamp } from "../../scripts/lib/darkmem-mirror.mjs";
import {
  NOT_A_FILE, fileHash, inProgress, inProgressReason, nameSpellings, pendingFamilies, refreshContext, runGit, stayLine,
} from "../../scripts/lib/darkmem-reconcile.mjs";
import { STUB_KEY, sha, startStub } from "./stub-server.mjs";
import { git, makeHome, makeRepo, read, run, scratch, write } from "./helpers.mjs";
```

Replace it with:

```js
import { loadState, utcStamp } from "../../scripts/lib/darkmem-mirror.mjs";
import {
  NOT_A_FILE, fileHash, inProgress, inProgressReason, nameSpellings, pendingFamilies, reconcile as reconcileInProcess, refreshContext, runGit, stayLine,
} from "../../scripts/lib/darkmem-reconcile.mjs";
import { STUB_KEY, sha, startStub } from "./stub-server.mjs";
import { git, makeHome, makeRepo, namedPipe, read, run, scratch, write } from "./helpers.mjs";
```

(The file's own `reconcile` is its CLI runner, so the module's `reconcile` is imported as `reconcileInProcess`.)

Find:

```js
test("a differing file already in docs/dforge refuses the move and nothing is copied", async t => {
  const s = await darkmemDocs(t);
  write(path.join(s.repo, "docs", "dforge", "specs", "a.md"), "# A local\n");
  const result = await s.reconcile();
  assert.equal(result.code, 1);
  assert.match(result.stdout, /^darkmem-sync reconcile: documents stay darkmem \(configured local\): docs\/dforge already holds different copies; nothing was copied$/m);
  assert.ok(result.stdout.includes("  docs/dforge/specs/a.md: already exists with different content\n"), result.stdout);
  assert.equal(fs.existsSync(path.join(s.repo, "docs", "dforge", "plans", "p.md")), false);
  assert.equal(read(path.join(s.docsRoot, "plans", "p.md")), "# P\n");
  assert.deepEqual(s.stores(), { documents: "darkmem", progress: "local" });
});
```

Replace it with:

```js
for (const [what, plant] of [["a differing file", file => write(file, "# A local\n")], ["a named pipe", namedPipe]]) {
  test(`${what} already in docs/dforge refuses the move and nothing is copied`, { skip: what === "a named pipe" && process.platform === "win32" }, async t => {
    const s = await darkmemDocs(t);
    plant(path.join(s.repo, "docs", "dforge", "specs", "a.md"));
    const result = await s.reconcile();
    assert.equal(result.code, 1);
    assert.match(result.stdout, /^darkmem-sync reconcile: documents stay darkmem \(configured local\): docs\/dforge already holds different copies; nothing was copied$/m);
    assert.ok(result.stdout.includes("  docs/dforge/specs/a.md: already exists with different content\n"), result.stdout);
    assert.equal(fs.existsSync(path.join(s.repo, "docs", "dforge", "plans", "p.md")), false);
    assert.equal(read(path.join(s.docsRoot, "plans", "p.md")), "# P\n");
    assert.deepEqual(s.stores(), { documents: "darkmem", progress: "local" });
  });
}

test("a mirror copy swapped for a directory during the killed-run comparison refuses the move, not a crash", async t => {
  const repo = makeRepo();
  const home = mapped(repo, { entry: { documentStore: "local", progressSource: "local" }, stores: { documents: "darkmem", progress: "local" } });
  const mirrorCopy = path.join(home.docsRoot, "specs", "a.md");
  const dest = path.join(repo, "docs", "dforge", "specs", "a.md");
  write(mirrorCopy, "# A\n");
  write(dest, "# A\n");
  // Offline (darkmem turned off) the move needs no client.
  const cfg = { ...cfgFor(repo, home.env), enabled: false };
  const lines = [];
  const context = { cfg, client: null, env: home.env, out: line => lines.push(line), report: { refused: 0 }, state: loadState(cfg.statePath), persist: () => {} };
  // The comparison reads the repository's copy, then the mirror's: the
  // mirror's becomes a directory at that second open.
  const open = fs.openSync;
  let armed = false;
  t.mock.method(fs, "openSync", (target, ...rest) => {
    if (target === dest) armed = true;
    else if (armed && target === mirrorCopy) {
      armed = false;
      fs.rmSync(mirrorCopy);
      fs.mkdirSync(mirrorCopy);
    }
    return open(target, ...rest);
  });
  await reconcileInProcess(context);
  assert.ok(lines.includes("darkmem-sync reconcile: documents stay darkmem (configured local): docs/dforge already holds different copies; nothing was copied"), lines.join("\n"));
  assert.ok(lines.includes("  docs/dforge/specs/a.md: already exists with different content"), lines.join("\n"));
});
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID timeout 900 node --test --test-name-pattern='named pipe|killed-run comparison' plugins/dforge/tests/darkmem-sync/reconcile-progress.test.mjs plugins/dforge/tests/darkmem-sync/reconcile.test.mjs`
Expected: FAIL — exactly these five fail. Four fail as `-1 !== 1` after about 30 s each (the child blocked on the pipe and was killed): "a named pipe at the mirror's copy of a ledger is a problem, …", "a primary checkout file that is a named pipe …", "a mirror latest.md that is a named pipe …", "a named pipe already in docs/dforge refuses the move …". "a mirror copy swapped for a directory during the killed-run comparison …" fails on an uncaught `EISDIR: illegal operation on a directory, read`. The other named-pipe tests pass.

- [ ] **Step 3: Implement**

In `plugins/dforge/scripts/lib/darkmem-progress-move.mjs`, find (in `checkProgressTargets`):

```js
    let held;
    try {
      held = fs.readFileSync(target);
```

Replace it with:

```js
    let held;
    try {
      held = readNoFollow(target);
```

Find (in `renderCheckpoint`):

```js
    current = sha256(fs.readFileSync(file));
```

Replace it with:

```js
    current = sha256(readNoFollow(file));
```

Find (in `progressToLocal`):

```js
      held = fs.readFileSync(item.target);
```

Replace it with:

```js
      held = readNoFollow(item.target);
```

In `plugins/dforge/scripts/lib/darkmem-reconcile.mjs`, find (in `documentsToLocal`):

```js
  // A killed earlier run may have copied some files: equal ones are fine.
  const differing = files
    .filter(({ file, dest }) => fs.existsSync(dest) && !fs.readFileSync(dest).equals(fs.readFileSync(file)))
    .map(({ name }) => `${name}: already exists with different content`);
```

Replace it with:

```js
  // A killed earlier run may have copied some files: equal ones are fine. One
  // that cannot be read, a named pipe included, differs.
  const differing = files
    .filter(({ file, dest }) => {
      if (!fs.existsSync(dest)) return false;
      try {
        return !readNoFollow(dest).equals(readNoFollow(file));
      } catch {
        return true;
      }
    })
    .map(({ name }) => `${name}: already exists with different content`);
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID timeout 600 node --test --test-name-pattern='named pipe|killed-run comparison' plugins/dforge/tests/darkmem-sync/reconcile-progress.test.mjs plugins/dforge/tests/darkmem-sync/reconcile.test.mjs`
Expected: PASS, 0 fail.

Run: `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID timeout 900 bash plugins/dforge/tests/darkmem-sync.test.sh`
Expected: PASS, 0 fail.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/scripts/lib/darkmem-progress-move.mjs plugins/dforge/scripts/lib/darkmem-reconcile.mjs plugins/dforge/tests/darkmem-sync/reconcile-progress.test.mjs plugins/dforge/tests/darkmem-sync/reconcile.test.mjs
git commit -m "fix(darkmem): never block on a pipe at a move target"
```

---

### Task 3: Read followed records without blocking on a pipe

Reconcile's `inProgress` reads `.dforge/sdd/auto-run.json`, and `planFinished` reads a plan directory's `completed.md`, with a plain `fs.readFileSync`, so a named pipe at either blocks reconcile forever. Both follow links today, as `auto-run.sh` does, and keep doing so: they read through `readRegular(…, { follow: true })`, and any error keeps its meaning (no active run; not finished). `fileHash` reads the same way and drops its `stat`, so a file swapped between the two can no longer be read as something else.

**Files:**
- Modify: `plugins/dforge/scripts/lib/darkmem-reconcile.mjs`
- Test: `plugins/dforge/tests/darkmem-sync/reconcile.test.mjs`

**Interfaces:**
- Consumes: Contracts `readRegular`, `namedPipe` (and Task 2's `namedPipe` import in `reconcile.test.mjs`)
- Produces: Contracts "Followed reads"

**Items:** DM 64

**Depends on:** Task 1, Task 2
**Implementer:** dr-superpowers:impl-sonnet-medium
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 2 = 4

- [ ] **Step 1: Write the failing tests**

In `plugins/dforge/tests/darkmem-sync/reconcile.test.mjs`, find:

```js
test("a directory where a document should be hashes as a non-file instead of throwing", () => {
  const dir = scratch("dms-hash-");
  assert.equal(fileHash(dir), NOT_A_FILE);
  assert.equal(fileHash(path.join(dir, "absent.md")), null);
  write(path.join(dir, "a.md"), "a\n");
  assert.equal(fileHash(path.join(dir, "a.md")), sha("a\n"));
});
```

Replace it with:

```js
test("a directory or named pipe where a document should be hashes as a non-file instead of throwing or blocking", () => {
  const dir = scratch("dms-hash-");
  assert.equal(fileHash(dir), NOT_A_FILE);
  assert.equal(fileHash(path.join(dir, "absent.md")), null);
  write(path.join(dir, "a.md"), "a\n");
  assert.equal(fileHash(path.join(dir, "a.md")), sha("a\n"));
  assert.equal(fileHash(path.join(dir, "a.md", "below.md")), null);
  if (process.platform === "win32") return;
  fs.symlinkSync(path.join(dir, "a.md"), path.join(dir, "link.md"));
  assert.equal(fileHash(path.join(dir, "link.md")), sha("a\n"));
  assert.equal(fileHash(namedPipe(path.join(dir, "pipe.md"))), NOT_A_FILE);
});

test("a file swapped for a directory as fileHash opens it hashes as a non-file, not a crash", t => {
  const dir = scratch("dms-hash-");
  const file = path.join(dir, "a.md");
  write(file, "a\n");
  const open = fs.openSync;
  let swapped = false;
  t.mock.method(fs, "openSync", (target, ...rest) => {
    if (!swapped && target === file) {
      swapped = true;
      fs.rmSync(file);
      fs.mkdirSync(file);
    }
    return open(target, ...rest);
  });
  assert.equal(fileHash(file), NOT_A_FILE);
});
```

Find:

```js
  write(file, JSON.stringify({ active: false }));
  assert.deepEqual(inProgress(cfgFor(repo, env)), []);
  assert.equal(inProgressReason({ cfg: cfgFor(repo, env) }), null);
});
```

Replace it with:

```js
  write(file, JSON.stringify({ active: false }));
  assert.deepEqual(inProgress(cfgFor(repo, env)), []);
  assert.equal(inProgressReason({ cfg: cfgFor(repo, env) }), null);
  if (process.platform === "win32") return;
  const record = path.join(scratch("dms-run-"), "auto-run.json");
  write(record, JSON.stringify({ active: true }));
  fs.rmSync(file);
  fs.symlinkSync(record, file);
  assert.deepEqual(inProgress(cfgFor(repo, env)), ["an auto run is active"], "a linked record is read through");
});

for (const [name, at] of [["auto-run.json", [".dforge", "sdd", "auto-run.json"]], ["completed.md", ["docs", "dforge", "plans", "completed.md"]]]) {
  test(`a named pipe at ${name} never blocks reconcile: it records no active run and no finished plan`, { skip: process.platform === "win32" }, async t => {
    const stub = await startStub();
    t.after(() => stub.close());
    const repo = makeRepo();
    const { env } = mapped(repo, { url: stub.url });
    write(path.join(repo, ".dforge", "sdd", "p1", "progress.md"), LEDGER("docs/dforge/plans/p1.md"));
    namedPipe(path.join(repo, ...at));
    const result = await reconcile(repo, env);
    assert.equal(result.code, 1, result.stdout + result.stderr);
    assert.equal(result.stdout, [
      "darkmem-sync reconcile: documents stay local (configured darkmem): a plan is in progress: docs/dforge/plans/p1.md",
      "darkmem-sync reconcile: progress stay local (configured darkmem): a plan is in progress: docs/dforge/plans/p1.md",
      "",
    ].join("\n"));
    assert.equal(stub.db.requests.length, 0);
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID timeout 600 node --test --test-name-pattern='named pipe|auto run|hashes' plugins/dforge/tests/darkmem-sync/reconcile.test.mjs`
Expected: FAIL — exactly three fail: "a named pipe at auto-run.json …" and "a named pipe at completed.md …", each as `-1 !== 1` after about 30 s, and "a file swapped for a directory as fileHash opens it …" on an uncaught `EISDIR: illegal operation on a directory, read` (today's `fileHash` stats a file, then reads what replaced it). "a directory or named pipe where a document should be hashes …" and "an active auto run is in progress" pass: they are regression guards (today's `fileHash` stats before it reads, and today's read already follows links).

- [ ] **Step 3: Implement**

In `plugins/dforge/scripts/lib/darkmem-reconcile.mjs`, find:

```js
import { progressToDarkmem, progressToLocal, readNoFollow } from "./darkmem-progress-move.mjs";
```

Replace it with:

```js
import { progressToDarkmem, progressToLocal, readNoFollow, readRegular } from "./darkmem-progress-move.mjs";
```

Find (in `planFinished`):

```js
    text = fs.readFileSync(path.join(path.dirname(planFile(cfg, checkout, name)), "completed.md"), "utf8");
```

Replace it with:

```js
    text = readRegular(path.join(path.dirname(planFile(cfg, checkout, name)), "completed.md"), { follow: true }).toString("utf8");
```

Find (in `inProgress`):

```js
    const run = JSON.parse(fs.readFileSync(path.join(dforgeDir("state", cfg.repoRoot), "sdd", "auto-run.json"), "utf8"));
    if (run?.active === true) found.push("an auto run is active");
  } catch {
    // No auto run, or an unreadable record, which auto-run.sh reads as inactive too.
  }
```

Replace it with:

```js
    const run = JSON.parse(readRegular(path.join(dforgeDir("state", cfg.repoRoot), "sdd", "auto-run.json"), { follow: true }).toString("utf8"));
    if (run?.active === true) found.push("an auto run is active");
  } catch {
    // No auto run, or an unreadable record, which auto-run.sh reads as inactive
    // too. The record is read through a link, as auto-run.sh reads it; one that
    // is not a regular file holds no run, since auto-run.sh writes the record
    // with tmp+mv, which replaces a link or a pipe at the path.
  }
```

Find:

```js
export function fileHash(file) {
  const stat = fs.statSync(file, { throwIfNoEntry: false });
  if (!stat) return null;
  return stat.isFile() ? sha256(fs.readFileSync(file)) : NOT_A_FILE;
}
```

Replace it with:

```js
export function fileHash(file) {
  try {
    return sha256(readRegular(file, { follow: true }));
  } catch (error) {
    if (error.code === "ENOENT" || error.code === "ENOTDIR") return null;
    if (error.code === "EISDIR" || error.code === "EFTYPE") return NOT_A_FILE;
    throw error;
  }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID timeout 600 node --test --test-name-pattern='named pipe|auto run|hashes' plugins/dforge/tests/darkmem-sync/reconcile.test.mjs`
Expected: PASS, 0 fail.

Run: `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID timeout 900 bash plugins/dforge/tests/darkmem-sync.test.sh`
Expected: PASS, 0 fail.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/scripts/lib/darkmem-reconcile.mjs plugins/dforge/tests/darkmem-sync/reconcile.test.mjs
git commit -m "fix(darkmem): never block on a pipe at a run record"
```

---

### Task 4: Refuse a document deleted during the pull

A documents move into darkmem checks the tracked documents twice: before the upload and again after the pull, so a change made meanwhile keeps the repository copy. The recheck's `uncarried()` calls `fs.lstatSync` on each tracked path; a document deleted without a commit during the pull makes it throw `ENOENT`, and reconcile exits 4 with `unexpected error`. A missing path becomes the problem `missing from the working tree`, which marks the uri uncarriable, so the existing recheck reports `changed during the move` and nothing is staged. The document's read, which follows the `lstat` check, moves to `readNoFollow` inside a `try`, so a file swapped between the two lines is refused rather than crashing.

**Files:**
- Modify: `plugins/dforge/scripts/lib/darkmem-reconcile.mjs`
- Test: `plugins/dforge/tests/darkmem-sync/reconcile.test.mjs`

**Interfaces:**
- Consumes: Contracts `readNoFollow`
- Produces: Contracts "`carriedDocuments` export", "Read error lines" (`carriedDocuments`)

**Items:** DM 63

**Depends on:** Task 2, Task 3
**Implementer:** dr-superpowers:impl-sonnet-medium
**Evaluation:** files 1 - spec 0 - coupling 0 - risk 2 = 3

- [ ] **Step 1: Write the failing end-to-end test**

In `plugins/dforge/tests/darkmem-sync/reconcile.test.mjs`, find:

```js
test("a document emptied and committed during the pull is named as changed and uncarriable, not removed", async t => {
```

Replace it with:

```js
test("a document deleted without a commit during the pull is named as missing and changed, and nothing is staged", async t => {
  let repo;
  let deleted = false;
  const s = await docsRepo(t, { "specs/a.md": "# A\n", "specs/b.md": "# B\n" }, {
    stub: {
      onRequest: request => {
        if (!repo || deleted || request.path !== "/api/v1/documents/by-uri") return;
        deleted = true;
        fs.rmSync(at(repo, "docs/dforge/specs/b.md"));
      },
    },
  });
  repo = s.repo;
  const result = await s.reconcile();
  assert.equal(result.code, 1, result.stdout + result.stderr);
  assert.match(result.stdout, /^darkmem-sync reconcile: documents stay local \(configured darkmem\): docs\/dforge changed during the move; the repository copy stays$/m);
  assert.ok(result.stdout.includes("  docs/dforge/specs/b.md: missing from the working tree\n"), result.stdout);
  assert.ok(result.stdout.includes("  dforge/specs/b.md: changed during the move\n"), result.stdout);
  assert.equal(git(s.repo, "diff", "--cached", "--name-only"), "");
  assert.equal(read(at(s.repo, "docs/dforge/specs/a.md")), "# A\n");
  assert.deepEqual(s.stores(), { documents: "local", progress: "local" });
});

test("a document emptied and committed during the pull is named as changed and uncarriable, not removed", async t => {
```

- [ ] **Step 2: Run it to verify it fails**

Run: `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID timeout 300 node --test --test-name-pattern='deleted without a commit' plugins/dforge/tests/darkmem-sync/reconcile.test.mjs`
Expected: FAIL — `4 !== 1`, with stderr `darkmem-sync: unexpected error: Error: ENOENT: no such file or directory, lstat '…/docs/dforge/specs/b.md'`.

- [ ] **Step 3: Write the failing read-race test**

In the same file, find (the import Task 2 extended):

```js
  NOT_A_FILE, fileHash, inProgress, inProgressReason, nameSpellings, pendingFamilies, reconcile as reconcileInProcess, refreshContext, runGit, stayLine,
```

Replace it with:

```js
  NOT_A_FILE, carriedDocuments, fileHash, inProgress, inProgressReason, nameSpellings, pendingFamilies, reconcile as reconcileInProcess, refreshContext, runGit, stayLine,
```

Find:

```js
test("a document emptied and committed during the pull is named as changed and uncarriable, not removed", async t => {
```

Replace it with:

```js
test("a tracked document swapped for a directory after its check is uncarriable, not a crash", t => {
  const repo = makeRepo();
  const docsDir = path.join(repo, "docs", "dforge");
  const file = path.join(docsDir, "specs", "a.md");
  write(file, "# A\n");
  commitAll(repo, "docs");
  const open = fs.openSync;
  let swapped = false;
  t.mock.method(fs, "openSync", (target, ...rest) => {
    if (!swapped && target === file) {
      swapped = true;
      fs.rmSync(file);
      fs.mkdirSync(file);
    }
    return open(target, ...rest);
  });
  const { problems, documents, uncarriable } = carriedDocuments(repo, docsDir, "docs/dforge");
  assert.deepEqual(problems, ["docs/dforge/specs/a.md: could not be read (EISDIR)"]);
  assert.deepEqual(documents, []);
  assert.deepEqual([...uncarriable], ["dforge/specs/a.md"]);
});

test("a document emptied and committed during the pull is named as changed and uncarriable, not removed", async t => {
```

- [ ] **Step 4: Run it to verify it fails**

Run: `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID timeout 300 node --test --test-name-pattern='swapped for a directory' plugins/dforge/tests/darkmem-sync/reconcile.test.mjs`
Expected: FAIL — the file does not load: `SyntaxError: The requested module '../../scripts/lib/darkmem-reconcile.mjs' does not provide an export named 'carriedDocuments'`. (With only the export added, the test fails on an uncaught `EISDIR: illegal operation on a directory, read`.)

- [ ] **Step 5: Implement**

In `plugins/dforge/scripts/lib/darkmem-reconcile.mjs`, find (in `uncarried`):

```js
  let at = docsDir;
  for (const part of parts) {
    at = path.join(at, part);
    if (fs.lstatSync(at).isSymbolicLink()) return "a symbolic link, or reached through one, which the mirror never syncs";
  }
  return fs.lstatSync(at).isFile() ? null : "not a regular file";
}
```

Replace it with:

```js
  let at = docsDir;
  let stat;
  for (const part of parts) {
    at = path.join(at, part);
    stat = fs.lstatSync(at, { throwIfNoEntry: false });
    // Tracked but deleted without a commit, as during a move's pull.
    if (!stat) return "missing from the working tree";
    if (stat.isSymbolicLink()) return "a symbolic link, or reached through one, which the mirror never syncs";
  }
  return stat.isFile() ? null : "not a regular file";
}
```

Find:

```js
function carriedDocuments(repoRoot, docsDir, rel) {
```

Replace it with:

```js
export function carriedDocuments(repoRoot, docsDir, rel) {
```

Find (in `carriedDocuments`):

```js
    const buffer = fs.readFileSync(path.join(docsDir, ...parts));
    const content = decodeUtf8(buffer);
```

Replace it with:

```js
    let buffer;
    try {
      buffer = readNoFollow(path.join(docsDir, ...parts));
    } catch (error) {
      refuse(`could not be read (${error.code})`);
      continue;
    }
    const content = decodeUtf8(buffer);
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID timeout 300 node --test --test-name-pattern='deleted without a commit|swapped for a directory' plugins/dforge/tests/darkmem-sync/reconcile.test.mjs`
Expected: PASS, 2 pass, 0 fail.

Run: `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID timeout 900 bash plugins/dforge/tests/darkmem-sync.test.sh`
Expected: PASS, 0 fail.

- [ ] **Step 7: Commit**

```bash
git add plugins/dforge/scripts/lib/darkmem-reconcile.mjs plugins/dforge/tests/darkmem-sync/reconcile.test.mjs
git commit -m "fix(darkmem): refuse a document deleted mid-move"
```

---

### Task 5: Say darkmem keeps what it accepted after a relink

`progressToDarkmem` checks the mirror for symbolic links twice: before it sends anything, and again after darkmem has accepted the progress, just before it writes into the mirror's `work/`. Both refuse with `nothing was sent or moved`, which is false for the second: darkmem already holds the progress. The second check's outcome becomes `nothing was moved locally, and darkmem keeps what it accepted`, the wording the module already uses after a partial refusal. The first check is unchanged.

**Files:**
- Modify: `plugins/dforge/scripts/lib/darkmem-progress-move.mjs`
- Test: `plugins/dforge/tests/darkmem-sync/reconcile-progress.test.mjs`

**Interfaces:**
- Consumes: None
- Produces: Contracts "Relink refusal"

**Items:** DM 65

**Depends on:** none
**Implementer:** dr-superpowers:impl-sonnet-low
**Evaluation:** files 1 - spec 0 - coupling 0 - risk 1 = 2

- [ ] **Step 1: Update the test to the new wording**

In `plugins/dforge/tests/darkmem-sync/reconcile-progress.test.mjs`, in the test "a mirror directory linked while darkmem is written refuses the move, and nothing is written through it", find:

```js
  assert.ok(result.stdout.includes("darkmem-sync reconcile: progress stay local (configured darkmem): the mirror's progress is reached through symbolic links; nothing was sent or moved\n"), result.stdout);
  assert.ok(result.stdout.includes(`  ${planDir}: a symbolic link in the mirror, which the move will not read through\n`), result.stdout);
```

Replace it with:

```js
  assert.ok(result.stdout.includes("darkmem-sync reconcile: progress stay local (configured darkmem): the mirror's progress is reached through symbolic links; nothing was moved locally, and darkmem keeps what it accepted\n"), result.stdout);
  assert.ok(result.stdout.includes(`  ${planDir}: a symbolic link in the mirror, which the move will not read through\n`), result.stdout);
```

Leave the loop "progress stays local when … is a symbolic link, and nothing is sent or written through it" on `nothing was sent or moved`: its link is in place before reconcile starts, so the first check refuses it.

- [ ] **Step 2: Run the tests to verify the changed one fails**

Run: `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID timeout 300 node --test --test-name-pattern='linked while darkmem is written|is a symbolic link, and nothing is sent' plugins/dforge/tests/darkmem-sync/reconcile-progress.test.mjs`
Expected: FAIL — exactly "a mirror directory linked while darkmem is written refuses the move, …" fails; the two loop tests pass.

- [ ] **Step 3: Implement**

In `plugins/dforge/scripts/lib/darkmem-progress-move.mjs`, find:

```js
  const relinked = mirrorRefusal([...mirrorTop(cfg.mirror), ...mirrorLinks(workRoot)], "nothing was sent or moved");
```

Replace it with:

```js
  const relinked = mirrorRefusal([...mirrorTop(cfg.mirror), ...mirrorLinks(workRoot)], "nothing was moved locally, and darkmem keeps what it accepted");
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID timeout 300 node --test --test-name-pattern='linked while darkmem is written|is a symbolic link, and nothing is sent' plugins/dforge/tests/darkmem-sync/reconcile-progress.test.mjs`
Expected: PASS, 3 pass, 0 fail.

Run: `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID timeout 900 bash plugins/dforge/tests/darkmem-sync.test.sh`
Expected: PASS, 0 fail.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/scripts/lib/darkmem-progress-move.mjs plugins/dforge/tests/darkmem-sync/reconcile-progress.test.mjs
git commit -m "fix(darkmem): say what a late relink refusal kept"
```

---

### Task 6: Build the probe request with jq

`detect-executors.sh` builds each registered executor's auth-probe request with `printf '{"op":"%s","cwd":"%s"}'`, so a working directory holding `"` or `\` produces invalid JSON. The probe then cannot read its `cwd`. Windows paths are not affected (`dr_native_path` gives forward slashes). The request is built with `jq -nc --arg`, which the script already requires.

**Files:**
- Modify: `plugins/dforge/scripts/detect-executors.sh`
- Test: `plugins/dforge/tests/detect.test.sh`

**Interfaces:**
- Consumes: None
- Produces: None

**Items:** CX 17

**Depends on:** none
**Implementer:** dr-superpowers:impl-sonnet-low
**Evaluation:** files 1 - spec 0 - coupling 0 - risk 1 = 2

- [ ] **Step 1: Write the failing test**

The stub probe (`tests/fixtures/executors/bin/stub-probe.mjs`) logs the `cwd` it parsed, or `-` when the request is not valid JSON. It answers `authed: true` even then, so the auth status cannot show the fault; the log can.

In `plugins/dforge/tests/detect.test.sh`, find:

```bash
check "a registry probe receives a native-form cwd" \
  "$(head -1 "$TMP/probe-cwd.log")" "$expected_cwd"
```

Replace it with:

```bash
check "a registry probe receives a native-form cwd" \
  "$(head -1 "$TMP/probe-cwd.log")" "$expected_cwd"

# A cwd holding a quote and a backslash reaches the probe as valid JSON.
# Windows does not allow either in a file name.
if ! command -v cygpath >/dev/null 2>&1; then
  odd="$TMP/a\"b\\c"
  mkdir -p "$odd"
  : > "$TMP/probe-odd.log"
  (cd "$odd" && STUB_PROBE_LOG="$TMP/probe-odd.log" regrun >/dev/null)
  check "a cwd with a quote and a backslash reaches the probe intact" \
    "$(head -1 "$TMP/probe-odd.log")" "$odd"
fi
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID timeout 120 bash plugins/dforge/tests/detect.test.sh`
Expected: FAIL — `62 passed, 1 failed`; "a cwd with a quote and a backslash reaches the probe intact" wants `…/a"b\c` and got `-`.

- [ ] **Step 3: Implement**

In `plugins/dforge/scripts/detect-executors.sh`, find:

```bash
      auth_json=$(printf '{"op":"%s","cwd":"%s"}' "$probe_op" "$(dr_native_path "$PWD")" \
        | timeout 60 node "$probe_cmd" "$locator_root" 2>/dev/null)
```

Replace it with:

```bash
      auth_json=$(jq -nc --arg op "$probe_op" --arg cwd "$(dr_native_path "$PWD")" '{op: $op, cwd: $cwd}' \
        | timeout 60 node "$probe_cmd" "$locator_root" 2>/dev/null)
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID timeout 120 bash plugins/dforge/tests/detect.test.sh`
Expected: PASS — `63 passed, 0 failed`.

Run: `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID timeout 300 bash plugins/dforge/tests/executors.test.sh`
Expected: PASS, 0 failed.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/scripts/detect-executors.sh plugins/dforge/tests/detect.test.sh
git commit -m "fix(executors): build the probe request with jq"
```

---

### Task 7: Count no run for a shell told not to execute

The eval controller's `planSlugs` (`evals/controller/lib/sessions.mjs`) counts a per-task script run in a transcript. It already skips `bash -n script`, which only parses the script, but it matches `-n` exactly, so `bash -nx`, `sh -en` and `bash -o noexec` (also `-eo noexec`) count as runs. A short-option cluster holding `n`, or `-o`/`-…o` followed by `noexec`, now ends the command as not a run; long options such as `--norc` are not clusters. Separately, the `<<-'EOF'` test in `transcript.test.mjs` passes with or without the tab handling it guards; it is rewritten so a missing tab rule swallows a counted line. The eval-parser bound the owner set goes into `constraints.md`.

**Files:**
- Modify: `evals/controller/lib/sessions.mjs`
- Modify: `evals/controller/lib/heredoc.mjs` (Step 5 only: changed temporarily and restored; not committed)
- Modify: `docs/superpowers/distilled/constraints.md`
- Test: `evals/controller/tests/sessions.test.mjs`
- Test: `evals/controller/tests/transcript.test.mjs`

**Interfaces:**
- Consumes: None
- Produces: None

**Items:** DF 26

**Depends on:** none
**Implementer:** dr-superpowers:impl-sonnet-medium
**Evaluation:** files 2 - spec 0 - coupling 0 - risk 1 = 3

- [ ] **Step 1: Write the failing tests**

In `evals/controller/tests/sessions.test.mjs`, find:

```js
  write(join(dir, 'n.jsonl'), [skill(SDD), bash('n', 'bash -n /p/scripts/task-brief docs/plans/2026-10-18-zeta.md'), bash('bn', '/bin/bash -n /p/scripts/task-brief docs/plans/2026-10-18-zeta.md')]);
```

Replace it with:

```js
  write(join(dir, 'n.jsonl'), [skill(SDD), bash('n', 'bash -n /p/scripts/task-brief docs/plans/2026-10-18-zeta.md'), bash('bn', '/bin/bash -n /p/scripts/task-brief docs/plans/2026-10-18-zeta.md'), bash('nx', 'bash -nx /p/scripts/task-brief docs/plans/2026-10-18-zeta.md'), bash('en', 'sh -en /p/scripts/task-brief docs/plans/2026-10-18-zeta.md'), bash('on', 'bash -o noexec /p/scripts/task-brief docs/plans/2026-10-18-zeta.md'), bash('eon', 'bash -eo noexec /p/scripts/task-brief docs/plans/2026-10-18-zeta.md')]);
```

In the same file, the `run.jsonl` line ends with:

```js
docs/plans/2026-10-18-sigma.md 11")]);
```

Replace that ending (only those characters) with:

```js
docs/plans/2026-10-18-sigma.md 11"), bash('nr', 'bash --norc /p/scripts/task-brief docs/plans/2026-10-18-tau.md 12')]);
```

and in its expectation, find:

```js
'2026-10-18-sigma', '2026-10-18-theta', '2026-10-18-xi']);
```

Replace it with:

```js
'2026-10-18-sigma', '2026-10-18-tau', '2026-10-18-theta', '2026-10-18-xi']);
```

In `evals/controller/tests/transcript.test.mjs`, in the test "a heredoc body ends only at a line that is exactly its delimiter, tabs allowed for <<-", find:

```js
      use('h2', 'Bash', { command: "cat >> .dforge/sdd/p/progress.md <<-'EOF'\nTask 22: complete (commits s..t)\n\tEOF\nfalse" }),
    ]),
    failedCall('h1'), failedCall('h2'),
  ]));
  assert.deepEqual(m.completed, ['21', '22']);
```

Replace it with:

```js
      use('h2', 'Bash', { command: "false && cat >> .dforge/sdd/p/progress.md <<-'EOF'\nTask 22: complete (commits s..t)\n\tEOF\necho 'Task 23: complete (commits u..v)' >> .dforge/sdd/p/progress.md; false" }),
    ]),
    failedCall('h1'), failedCall('h2'),
  ]));
  assert.deepEqual(m.completed, ['21', '23']);
```

(The `false &&` gates the heredoc's write, so Task 22 never reached the ledger; the echo after the tab-indented terminator did. Without the `<<-` tab rule the heredoc runs to the end and swallows the echo.)

- [ ] **Step 2: Run the tests to verify they fail**

Run: `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID timeout 300 node --test evals/controller/tests/sessions.test.mjs evals/controller/tests/transcript.test.mjs`
Expected: FAIL — exactly "planSlugs counts a script run, not another command reading its path" fails (`n.jsonl` yields slugs). The heredoc test passes; Step 5 shows it guards the tab rule.

- [ ] **Step 3: Implement**

In `evals/controller/lib/sessions.mjs`, find:

```js
const NOT_A_RUN = { bash: new Set(['-n']), sh: new Set(['-n']), command: new Set(['-v', '-V']) };
```

Replace it with:

```js
const NOT_A_RUN = { command: new Set(['-v', '-V']) };
// A shell given -n, alone or in a cluster (-nx, -en), or -o noexec (-eo
// noexec) reads the script without running it. A long option (--norc) is not
// a cluster.
const noExec = (wrapper, w, next) => (wrapper === 'bash' || wrapper === 'sh')
  && (/^-[A-Za-z]*n[A-Za-z]*$/.test(w) || (/^-[A-Za-z]*o$/.test(w) && next === 'noexec'));
```

Find:

```js
      if (NOT_A_RUN[wrapper]?.has(w)) return [];
```

Replace it with:

```js
      if (NOT_A_RUN[wrapper]?.has(w) || noExec(wrapper, w, words[i + 1])) return [];
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID timeout 300 node --test evals/controller/tests/*.test.mjs`
Expected: PASS — `tests 33`, `pass 33`, `fail 0`.

- [ ] **Step 5: Show the heredoc test guards the tab rule**

`heredoc.mjs` is not otherwise changed by this task, so git restores it. Revert the tab rule temporarily:

```bash
timeout 60 sed -i "s/\${tabs ? '\\\\\\\\t\*' : ''}//" evals/controller/lib/heredoc.mjs
```

Run: `timeout 60 grep -n 'new RegExp' evals/controller/lib/heredoc.mjs`
Expected: the line reads ``const end = new RegExp(`\\n${quoted}(?=\\n|$)`).exec(cmd.slice(i));`` (no `tabs`). If it does not, restore the file with the `git checkout` below and stop: report that the revert did not apply.

Run: `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID timeout 60 node --test --test-name-pattern='tabs allowed' evals/controller/tests/transcript.test.mjs`
Expected: FAIL — the actual list lacks `'23'`.

Run: `timeout 60 git checkout -- evals/controller/lib/heredoc.mjs`

Run: `timeout 60 git diff --stat -- evals/controller/lib/heredoc.mjs`
Expected: no output (the file is unchanged).

- [ ] **Step 6: Record the parser bound**

Run: `timeout 60 git log -1 --format=%h -- docs/superpowers/specs/2026-10-20-review-rows-sweep-design.md`
It prints a short hash, `<hash>` below.

Append to the end of `docs/superpowers/distilled/constraints.md`, after its last line and one blank line, with `<hash>` replaced:

```markdown
## Evals

### Eval parser shapes need a real transcript
A shell shape the controller's parser (`evals/controller/lib/`) miscounts is fixed only when it appears in a real controller transcript; a shape found by review alone closes `n/a` citing this constraint.
Set by: owner, 2026-10-20 review-rows sweep design session
Scope: `evals/controller/lib/` and every register row against it
Source: docs/superpowers/specs/2026-10-20-review-rows-sweep-design.md@<hash>
```

Run: `timeout 60 grep -c 'Eval parser shapes need a real transcript' docs/superpowers/distilled/constraints.md`
Expected: `1`.

- [ ] **Step 7: Commit**

```bash
git add evals/controller/lib/sessions.mjs evals/controller/tests/sessions.test.mjs evals/controller/tests/transcript.test.mjs
git commit -m "fix(evals): count no run for a no-exec shell"
git add docs/superpowers/distilled/constraints.md
git commit -m "docs(constraints): bound eval parser fixes"
```

---

### Task 8: Guard the 41-link settings chain

`dforge-config.test.sh` checks that a dangling settings chain of exactly 40 links is followed, but nothing checks that a 41-link chain is refused; and the 40-link check reads `$?` on the line after its `fc set`, so a line inserted between them would read the wrong status. A 41-link chain test is added (exit 1, a refusal naming symbolic links, nothing created at the chain's end), and the 40-link `fc set` and its `$?` check share one line, as the file's refusal checks do. On Linux the kernel's own limit refuses the 41-link chain before `realTarget`'s cap is reached (`fs.realpathSync` throws `ELOOP`), so that check guards the outcome only. A second check reaches the cap itself: it runs `dforge-config.mjs`'s `main` in a child Node process whose `fs.realpathSync` reports `ENOENT`, as a system whose kernel allows longer chains would, so `realTarget` walks the chain and its own cap refuses it. Step 3 shows that check fails with the cap raised.

**Files:**
- Modify: `plugins/dforge/scripts/lib/dforge-config.mjs` (Step 3 only: changed temporarily and restored; not committed)
- Test: `plugins/dforge/tests/dforge-config.test.sh`

**Interfaces:**
- Consumes: None
- Produces: None

**Items:** FS 50

**Depends on:** none
**Implementer:** dr-superpowers:impl-sonnet-low
**Evaluation:** files 1 - spec 0 - coupling 0 - risk 0 = 1

- [ ] **Step 1: Add the test and join the status check**

In `plugins/dforge/tests/dforge-config.test.sh`, find:

```bash
  fc set autoCompactWindow 540000
  check "claude: a 40-link dangling chain: exit 0" "$?" "0"
  check "claude: a 40-link dangling chain: its end is created" "$(tr -d ' \n' < "$TMP/chain40/end.json" 2>/dev/null)" '{"autoCompactWindow":540000}'
  check "claude: a 40-link dangling chain: the last link stays" "$([ -L "$TMP/chain40/link39" ] && echo yes || echo no)" "yes"
```

Replace it with:

```bash
  fc set autoCompactWindow 540000; check "claude: a 40-link dangling chain: exit 0" "$?" "0"
  check "claude: a 40-link dangling chain: its end is created" "$(tr -d ' \n' < "$TMP/chain40/end.json" 2>/dev/null)" '{"autoCompactWindow":540000}'
  check "claude: a 40-link dangling chain: the last link stays" "$([ -L "$TMP/chain40/link39" ] && echo yes || echo no)" "yes"
  # One link more is refused, and nothing is created at the chain's end. On
  # Linux the kernel's own 40-link limit refuses it (ELOOP) before the cap.
  mkdir -p "$TMP/chain41"
  rm -f "$CS"; ln -s "$TMP/chain41/end.json" "$TMP/chain41/link40"
  for n in $(seq 39 -1 1); do ln -s "$TMP/chain41/link$((n + 1))" "$TMP/chain41/link$n"; done
  ln -s "$TMP/chain41/link1" "$CS"
  fc set autoCompactWindow 530000; check "claude: a 41-link dangling chain: exit 1" "$?" "1"
  check "claude: a 41-link dangling chain: the refusal names the links" "$(grep -c 'symbolic links' "$TMP/stderr")" "1"
  check "claude: a 41-link dangling chain: nothing is created at its end" "$([ -e "$TMP/chain41/end.json" ] && echo yes || echo no)" "no"
  # The cap itself, reached by making realpath report the chain as missing, as
  # a system whose kernel allows longer chains would: the loop refuses it.
  capped=$(DFORGE_CONFIG_MJS="$HERE/../scripts/lib/dforge-config.mjs" node --input-type=module -e '
    import fs from "node:fs";
    const { main } = await import(process.env.DFORGE_CONFIG_MJS);
    // After the import: the module loader resolves paths with realpathSync too.
    fs.realpathSync = () => { throw Object.assign(new Error("ENOENT: realpath stubbed"), { code: "ENOENT" }); };
    process.exitCode = main(["set", "autoCompactWindow", "520000"]);
  ' 2>&1; printf 'exit %s\n' "$?")
  check "claude: the hop cap refuses a 41-link chain" "$(grep -c -e 'more than 40 symbolic links' -e '^exit 1$' <<<"$capped")" "2"
  check "claude: the hop cap creates nothing at the chain's end" "$([ -e "$TMP/chain41/end.json" ] && echo yes || echo no)" "no"
```

The module path goes in an environment variable, not an argument: with the path as `process.argv[1]`, the module's own entry check would run `main` on import. The exit status is printed inside the substitution, so no line sits between the command and the status it reports.

No later check in the file uses `$CS`, so leaving it as the 41-link chain is safe.

- [ ] **Step 2: Run the tests**

Run: `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID timeout 600 bash plugins/dforge/tests/dforge-config.test.sh`
Expected: PASS — `195 passed, 0 failed` when run as root (the owner case is skipped otherwise). These checks pass before any code change: the cap and the kernel's limit already refuse the chain.

- [ ] **Step 3: Show the cap check guards the cap**

Raise the cap temporarily:

```bash
timeout 60 sed -i 's/^const MAX_LINK_HOPS = 40;/const MAX_LINK_HOPS = 41;/' plugins/dforge/scripts/lib/dforge-config.mjs
```

Run: `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID timeout 600 bash plugins/dforge/tests/dforge-config.test.sh`
Expected: FAIL — `193 passed, 2 failed` as root: "claude: the hop cap refuses a 41-link chain" and "claude: the hop cap creates nothing at the chain's end".

Run: `timeout 60 git checkout -- plugins/dforge/scripts/lib/dforge-config.mjs`

Run: `timeout 60 git diff --stat -- plugins/dforge/scripts/lib/dforge-config.mjs`
Expected: no output.

- [ ] **Step 4: Commit**

```bash
git add plugins/dforge/tests/dforge-config.test.sh
git commit -m "test(config): refuse a 41-link settings chain"
```

---

### Task 9: Release dforge 4.2.2

**Files:**
- Modify: `plugins/dforge/.claude-plugin/plugin.json`
- Modify: `plugins/dforge/.codex-plugin/plugin.json`

**Interfaces:**
- Consumes: None
- Produces: None

**Depends on:** Task 8
**Implementer:** dr-superpowers:impl-sonnet-low
**Evaluation:** files 0 - spec 0 - coupling 0 - risk 0 = 0

- [ ] **Step 1: Verify the current versions**

Run: `timeout 60 grep -h '"version"' plugins/dforge/.claude-plugin/plugin.json plugins/dforge/.codex-plugin/plugin.json`
Expected: two lines, both `"version": "4.2.1",`.

- [ ] **Step 2: Bump both manifests**

In each of the two files, replace `"version": "4.2.1",` with `"version": "4.2.2",`.

- [ ] **Step 3: Validate**

Run: `timeout 60 grep -h '"version"' plugins/dforge/.claude-plugin/plugin.json plugins/dforge/.codex-plugin/plugin.json`
Expected: two lines, both `"version": "4.2.2",`.

Run: `timeout 120 node scripts/validate-repository.mjs`
Expected: PASS, no errors.

- [ ] **Step 4: Commit**

```bash
git add plugins/dforge/.claude-plugin/plugin.json plugins/dforge/.codex-plugin/plugin.json
git commit -m "chore(dforge): release 4.2.2"
```

---

### Task 10: Run the Win32 discovery test with ripgrep

`tests/ui-discovery.test.mjs` skips "documented Win32 discovery finds centrally managed versions" when `bash -c 'command -v rg'` finds nothing, and this host has `rg` only as an interactive shell function. Installing the ripgrep package (a host change outside the repository; the shell function still shadows the binary in interactive shells) lets the test run here. No repository file changes.

**Files:**
- Test: `tests/ui-discovery.test.mjs` (run only, not modified)

**Interfaces:**
- Consumes: None
- Produces: None

**Items:** DF 27

**Depends on:** none
**Implementer:** dr-superpowers:impl-sonnet-low
**Evaluation:** files 0 - spec 0 - coupling 0 - risk 0 = 0

- [ ] **Step 1: Confirm the skip**

Run: `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID timeout 120 node --test tests/ui-discovery.test.mjs`
Expected: `tests 3`, `pass 2`, `skipped 1`, the skipped one marked `# rg is not installed`.

- [ ] **Step 2: Install ripgrep**

Run: `timeout 300 apt-get install -y ripgrep`
Expected: exit 0.

Run: `timeout 30 bash -c 'command -v rg && rg --version | head -1'`
Expected: `/usr/bin/rg`, then a `ripgrep 14.` version line.

- [ ] **Step 3: Run the test**

Run: `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID timeout 120 node --test tests/ui-discovery.test.mjs`
Expected: PASS — `tests 3`, `pass 3`, `skipped 0`.

If the Win32 discovery test fails, do not change the test or the documentation it reads: report its output in the task report, so DF 27 stays `open` with that output as its note.

- [ ] **Step 4: Report**

No commit: nothing in the repository changed. Run `timeout 60 git status --short` and confirm it prints nothing; quote Step 3's summary lines in the task report, which is DF 27's evidence.

## After finishing

When dr-superpowers:finishing-a-development-branch resolves the rows, DF 26 closes `done` with a note recording its sub-findings b and d as `n/a`, in the spec's Scope wording: b, because a successful call's `true || echo … >> progress.md` cannot be told by syntax from `grep -q 'Task N' progress.md || echo …`, which does write, and a failed call's `||` write is counted on purpose (`evals/controller/tests/transcript.test.mjs` case o1); d, not a defect, since the `{ …; } | tee -a` shape is counted on a successful call and correctly not on a failed one, whose `&&` gated the echo (case f2). FS 50's note says its 41-link test guards the outcome, since on Linux the kernel refuses the chain before `realTarget`'s cap. DF 27 closes on Task 10's report: `done` when the test ran and passed, otherwise it stays `open` with the output.

The controller runs this once dr-superpowers:finishing-a-development-branch has resolved the rows (spec A3). It is a grep, not the repository's `scripts/register check`, which resolves `docs/dforge/`, a root this repository does not use:

```bash
for f in 2026-09-23-codex-v3 2026-09-24-darkmem-mirror 2026-10-11-dr-forge 2026-10-12-forge-settings; do
  timeout 60 grep -nE '\| (open|planned) \|' docs/superpowers/registers/$f.md
  timeout 60 sed 's/\\|//g' docs/superpowers/registers/$f.md | timeout 60 awk -F'|' -v f=$f '/^\| [0-9]+ \|/ && NF != 8 { print f ": row" $2 "has the wrong cell count" }'
done
timeout 60 grep -n '^| 21 |.*| verify |.*owed: on a Windows machine with the generated types' docs/superpowers/registers/2026-10-11-dr-forge.md
```

Expected: no `open` or `planned` row except one a finding of this work added, no cell-count line, and DF 21 printed as `verify` with the spec's note.
