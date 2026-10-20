# Open Rows Sweep Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: the skill the **Execution:** line names — dr-superpowers:subagent-driven-development for `subagent`, dr-superpowers:executing-plans for `inline`. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the still-real findings in the 16 register rows the 2026-10-20 triage left open, and release dforge 4.2.1.

**Architecture:** One task per cluster of findings, grouped by the area that owns its files: home migration, repository validator, plan tooling and config, auto-run, evals, repository tooling, then the darkmem sync fixes in dependency order, then the release. Every behaviour change lands with a test that fails first; documentation changes are checked by grep and the validator.

**Tech Stack:** Bash scripts and their bash test suites, Node ES modules with `node --test`, Markdown documentation.

**Spec:** docs/superpowers/specs/2026-10-20-open-rows-sweep-design.md

**Execution:** subagent — `claude --model sonnet --effort high` — the plan runs parallel waves, which only subagent mode can run

**Plan review:** 2026-10-20 — dr-superpowers:judge-opus — executability 16 / coherence 18 / coverage 16 / assumptions 17 (round 2)

**Parallelism:** waves — 1 | 2-4 | 5-7 | 8 | 9 | 10 | 11 | 12 | 13 | 14 | 15

**Integration check:** `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID timeout 1800 node scripts/test-all.mjs && timeout 120 node scripts/validate-repository.mjs && timeout 120 /root/.local/bin/claude plugin validate . && timeout 120 /root/.local/bin/claude plugin validate plugins/dforge && timeout 120 /root/.local/bin/claude plugin validate plugins/dr-status && timeout 120 /root/.local/bin/claude plugin validate plugins/darkraise-ui && timeout 120 /root/.local/bin/claude plugin validate plugins/darkraise-win32ui && env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID timeout 300 /root/.local/bin/claude plugin test plugins/dforge`

**Worktree setup:** none

## Global Constraints

- Work in a worktree branched from local `main` (local `main` runs ahead of `origin/main`): `timeout 60 git worktree add .claude/worktrees/open-rows-sweep -b open-rows-sweep main`. Do not push.
- Commit identity: run `timeout 60 git config user.name Darkraise` and `timeout 60 git config user.email quangtc94@gmail.com` in the worktree before the first commit. No `Co-Authored-By`, `Claude-Session` or other AI attribution in any commit.
- Commit subjects: `<type>(<scope>): <subject>`, type one of feat|fix|docs|style|refactor|test|chore|perf, at most 50 characters, imperative, no period.
- Never edit plans, specs or notes under `docs/superpowers/`; register rows change only through the installed plugin's `<plugin-root>/scripts/register`.
- Every test, build or CLI command runs under `timeout`, a step's checks (`grep`, `git diff`, `git show`, `git rev-parse`, `sed`) included; only the commit blocks and one-line file setup or cleanup (`mkdir`, `mktemp`, `printf … >`, `chmod`, `cat`, `rm`) run without one. Leave no process running.
- Run every test suite, `scripts/test-all.mjs` and `claude plugin test` with `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID` in front.
- `claude` and `rg` are shell functions on this host: call `/root/.local/bin/claude`, and use `grep` in scripts and steps.
- Each suite makes its own temporary directories, so no two tasks' tests meet at run time; Task 3 gives the plan-lint suite its own `HOME`.
- The darkmem sync suites start a localhost stub server (`plugins/dforge/tests/darkmem-sync/stub-server.mjs`); run them with `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID timeout 600 bash plugins/dforge/tests/darkmem-sync.test.sh` or `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID timeout 300 node --test <file>`.
- Keep `DCC_*` variables and statusline storage paths as they are.
- When a quoted anchor line is not found, the file changed since the task was written: find the code by its function and intent, make the same change, and say so in the task report. Never invent a change the task does not describe.

## Contracts

- **State-save failure (Task 8; Tasks 9-14 rely on it).** `persist()` built in `darkmem-sync.mjs`'s `main` throws `new StateError(\`${cfg.statePath} could not be saved (${error.code ?? error.message}); the run stopped, and the next run checks what this one wrote\`)`. `main` prints `darkmem-sync: <message>` on stderr and exits 2; after a failed `persist()` its `finally` does not save again; a failed save in the `finally` prints the same line and turns exit 0 into 2. The lock is always released, and conflict, failure and note lines gathered before still print; the summary line does not.
- **The `syscall` rule (Task 8; Tasks 9-14 keep it).** That `StateError` has no `syscall` property. Any per-item catch in the darkmem commands that turns a file-system error into a report line tests `error?.syscall` (as `pullDocuments` does) and rethrows everything else, so a failed save is never reported as one item's failure. Errors `readNoFollow` raises itself (`EISDIR`, `EFTYPE`, the fallback's `ELOOP`) are handled by their callers explicitly, never by a `syscall` test.
- **Pull failure lines (Task 9).** `sdd/<key>/progress.md: the local ledger could not be read or written (<code>); not pulled`, `handoff/latest.md: could not be written (<code>); not pulled`, and inside a progress move back to local `handoff/latest.md: could not be written (<code>)`; each sets `report.partial`. After Task 9 the last statement of `renderCheckpoint` (`darkmem-progress-move.mjs`) is the `try { … persist(); } catch (error) { … }` block Task 9 quotes.
- **`runGit` (Task 11).** `export function runGit(cwd, args, input)` in `darkmem-reconcile.mjs` answers `{ status, signal, stdout, stderr }`; `stderr` falls back to `result.error.message` when git printed nothing. The documents move's recheck details read `<uri>: added during the move`, `<uri>: removed during the move`, `<uri>: changed during the move`, sorted by uri.
- **`readNoFollow` (Task 12; Tasks 13-14 use it).** `export function readNoFollow(file, constants = fs.constants)` in `darkmem-progress-move.mjs`, a `function` declaration (reconcile imports it across the two modules' import cycle). It returns a `Buffer`, or throws an `Error` whose `code` is `ELOOP` (the last component is a symbolic link, dangling included), `EISDIR` (a directory), `EFTYPE` (any other non-regular file), or the open's or read's own code (`ENOENT`, `EACCES`, `ENOTDIR`). It follows links in earlier path components. With `constants.O_NOFOLLOW === undefined` (Windows) it lstats, throws `ELOOP` for a link, then reads. These are its only call sites, each mapping its errors as stated:
  - `gatherLocalProgress`, reading each checkout file: `ELOOP` is the problem `<file>: a symbolic link, which the move will not read through`, any other code `<file>: could not be read (<code>)`; the move refuses with `the checkouts hold progress the move cannot carry`.
  - `progressToLocal`, reading each mirror source: `ELOOP` is `<file>: a symbolic link in the mirror, which the move will not read through`, any other code `<file>: could not be read (<code>)`; the move refuses with `the primary checkout cannot take the mirror's progress`.
  - `progressToDarkmem`'s recheck of each checkout file after darkmem is written: any error counts as no content, so the file is listed as `<file>: changed or removed during the move` under `progress changed in the checkouts during the move; nothing was moved locally`.
  - `progressToDarkmem`'s read-back of each mirror copy it wrote: any error counts as a differing copy, listed by its path under `a copy into the mirror reads back different`.
  - `readOrNull`, in `progressToLocal`'s copy loop (the re-read before each copy and the read-back after all of them): `ENOENT` is `null`, so an absent target is copied, and one absent at the read-back is `<target>: the copy reads back different`; any other code, `ELOOP` included, reaches the loop's catch, `a copy into the primary checkout failed (<code>); the files copied so far stay, and a rerun copies the rest`, with `<target>: copied` for each file copied. (Task 14's `EEXIST` comes from the exclusive copy, not from `readNoFollow`: `<target>: changed during the move; not overwritten`.)
  - reconcile's `inProgress`, reading each ledger: `ENOENT` means no ledger; any other code, `ELOOP` included, makes it in progress, `a plan is in progress: <ledger>`.
  - Task 13's `ledgersIn` only lists: a dangling link, and a ledger its `lstat` cannot reach, are listed, so the first two reads above report them.
- **Progress-move refusals (Tasks 12-14).** `inProgress` (reconcile) reports a linked ledger, an unreadable one, or a linked plan directory by its path, as `a plan is in progress: <path>`. Mirror-walk refusals read `the mirror's progress <found>; <outcome>`, `<found>` one of `could not be listed`, `is reached through symbolic links`, `could not be listed, and is reached through symbolic links`, `<outcome>` `nothing was pulled or copied` (`progressToLocal`) or `nothing was sent or moved` (`progressToDarkmem`). The moved-aside refusal counts `1 source` / `N sources`.
- **Elsewhere.** plan-lint, when a Codex plan's routing version cannot be read, exits 2 with `plan-lint: cannot read the routing policy version from <path>: <cause>`, `<cause>` one of `jq is not installed`, `the file cannot be parsed`, `the file has no version` (Task 3). The home migration gives one `refused: <file> could not be read: <reason>; fix or delete it, then run dforge-migrate again` per malformed JSON file and never throws on one (Task 1). `test-all.mjs` prints `Skipped tsc --noEmit -p plugins/dforge: tsc not found` (Task 7). `realTarget` keeps its text `more than 40 symbolic links` (Task 4).

## Assumptions (evidence)

- The Codex executor lane is on (`scripts/codex-gate` printed `usable=true reason=ok review=true lane=true`, probe, 2026-10-20) and docs/superpowers/distilled/constraints.md ticks it, but this plan is Claude-only by the owner's ruling of 2026-10-20: an Executor task runs alone in its wave, and Tasks 2-7, the only independent tasks, all passed the lane gate, so the lane would have made the approved parallel waves sequential. The ruling scopes the constraint for this plan only.
- plan-lint's lane-eligibility warnings for Tasks 2-7, 9, 10, 11 and 14 are that ruling. The darkmem tasks could not take the lane anyway: their suites start a localhost stub server, which the Codex sandbox refuses (register DM row 32's note), and so does Task 5's check of `tests/darkmem-sync/hooks.test.mjs`.
- FS 48 is closed `n/a` before this plan, as the spec's A1 allows: under `claude plugin test` (Claude Code 2.1.303, 2026-10-20) a probe failed with `TypeError: $.ui.close is not a function`; the kit's `$.ui` has only focus, input, mount, press, render, scroll and select, and a mounted handle's `unmount()` reaches no `ui.close` hook. The CI-pinned 2.1.295 was not probed.
- Every task was drafted against HEAD 67ede32 and run through its fail-then-pass cycle in a scratch copy (`git archive HEAD`); Tasks 8-10 were applied in order, and Tasks 11-14 in order on a tree without Tasks 8-10, whose anchors they avoid. Task 7's Windows path is unverified.
- Node v24.18.0 on this Linux host (uid 0): `openSync(path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)` opens a regular file, opens a bare FIFO at once without blocking, fails with `ELOOP` at once for a link to a file, to a FIFO, to a directory and for a dangling link, opens a directory, and follows a linked parent directory (probe, 2026-10-20). macOS is not run here; POSIX specifies the same `ELOOP` for `O_NOFOLLOW` on a final symbolic link and a non-blocking read-only open of a FIFO that returns at once (https://pubs.opengroup.org/onlinepubs/9799919799/functions/open.html), and macOS's open(2) documents the same `ELOOP`; Windows takes the lstat fallback, unit-tested by passing constants without `O_NOFOLLOW`, since `fs.constants` is non-configurable (`t.mock.property` throws `Cannot redefine property`).
- `fs.readFileSync(path)` without an encoding opens through the exported `fs.openSync`, so `t.mock.method(fs, "openSync")` reaches it; with `"utf8"` it does not (probe, 2026-10-20).
- A rename onto a directory fails with `EISDIR` on Linux (Task 8's run); the tests normalise the error code, since the Windows CI job may report another.
- `cli.test.mjs`'s "the lock is released even when the state file cannot be saved" pins today's exit 4; Task 8 changes it to 2 (with Task 8's implementation alone, exactly that test failed, `2 !== 4`).
- This host runs the suites as root, so permission cases use `fs` mocks, not `chmod`; `flock` and `jq` are installed (`command -v`).
- git 2.47.3 reports an intent-to-add rename in the worktree column: `" R docs/dforge/specs/b.md\0docs/dforge/specs/a.md\0"` (2026-10-20).
- No tracked file opens with a UTF-16 byte-order mark, so Task 2 adds no validator error on the current tree (`head -c2 | od` over `git ls-files`, 2026-10-20).
- The real checkout has the generated types and no `tsc` on `PATH`, so after Task 7 `test-all.mjs` prints `tsc not found`; no test or script quotes the old skip text (grep, 2026-10-20).
- Where a task departs from the spec's wording, reading the code required it:
  - Task 1 refuses each malformed file once, so a merge with both configs malformed gives two refusals, and also covers `~/.dr-superpowers/config.json` and `stores.json`.
  - Task 3 reports a missing routing file as "cannot be parsed", and runs the malformed-HOME check by hand, since the suite cannot set its own starting `HOME`.
  - Task 5's no-flock holder also writes the ready file, so both variants share one wait. AE 39.a fixes a race in the test, so it has no failing-first case; the task shows the race with a throwaway shim. AE 39.c uses three guards rather than re-indenting the block.
  - Task 6's list splitter ignores separators inside quotes and heredocs and the `&` of a redirect (`2>&1`), which a plain split would mishandle, and gives a heredoc's body to the list whose opener names it, whatever follows the opener on its line. "bash or command position" means the script path is a simple command's first word once assignments, reserved words, the wrappers `bash`, `sh`, `command`, `env`, `exec`, `nohup`, `time` and `timeout`, their options and a duration are skipped; a quoted string is one word, so a run quoted inside another command never counts.
  - Task 7 changes the skip text on Linux too. DF 23's relabelled bullets are the two 03765c6 rewrote.
  - Task 8 covers the `finally` guard through the existing `cli.test.mjs` test.
  - Task 9 keeps the existing read guards in `pullCheckpoint` and `renderCheckpoint`, wraps only their write and `persist()`, and adds checkpoint-write and `StateError`-propagation tests.
  - Task 10's case-twin lookup keeps a vanished uri when any twin reaches the same file, and makes one commit per concern.
  - Task 12 puts its `inProgress` tests in `reconcile-progress.test.mjs` (Rule S). Its in-process checkout-side cases link to a regular file, not a FIFO, since an in-process FIFO read would hang the runner; FIFO cases run through the CLI child. DM 61.e's failing-first case is `ENOTDIR`, since the `EACCES` mock passes before the fix.
  - The spec's P1 items 10-17 are split into Tasks 13 (new link refusals) and 14 (refusal wording and side effects); existing tests whose expectations change are named in each task.
- Three adjacent hazards found while drafting are not fixed here: reconcile takes the mirror lock and `main` saves the sync state under `cfg.mirror` before any move runs, so a linked mirror is still written through by those two; `progressToDarkmem` takes a ledger's `mtime` with `fs.statSync`, which follows a link swapped in after the read; and the moves' listings of an `sdd` directory (`unsupportedPlanDirs` through `darkmem-mirror.mjs`'s `sortedEntries`, and `ledgersIn`'s own `readdirSync`) still throw an error other than `ENOENT`, as they did before this plan, when that directory changes between the moves' first look at it and the listing.

## After finishing

The controller runs this once dr-superpowers:finishing-a-development-branch
has resolved the rows (spec A3). It is a grep, not the repository's
`scripts/register check`, which resolves `docs/dforge/`, a root this
repository does not use:

```bash
for f in 2026-09-23-codex-v3 2026-09-24-darkmem-mirror 2026-10-11-dr-forge 2026-10-12-forge-settings 2026-10-17-dforge-rename 2026-10-18-auto-execution-default; do
  grep -nE '\| (open|planned) \|' docs/superpowers/registers/$f.md
  sed 's/\\|//g' docs/superpowers/registers/$f.md | awk -F'|' -v f=$f '/^\| [0-9]+ \|/ && NF != 8 { print f ": row" $2 "has the wrong cell count" }'
done
grep -n '^| 14 |.*| done |' docs/superpowers/registers/2026-10-11-dr-forge.md
for r in "2026-10-11-dr-forge 22" "2026-10-12-forge-settings 48" "2026-10-17-dforge-rename 45" "2026-10-18-auto-execution-default 41" "2026-09-24-darkmem-mirror 54"; do
  set -- $r; grep -E "^\| $2 \|.*\| n/a \|.*triage 2026-10-20" docs/superpowers/registers/$1.md >/dev/null || echo "$1 #$2: not n/a with a triage 2026-10-20 note"
done
```

Expected: no `open` or `planned` row except one a finding of this work
added, no cell-count line, DF 14 printed as `done`, and no "not n/a" line.
DM 54's note must say `triage 2026-10-20` when finishing closes it.

## Task index

1. Refuse unreadable JSON in the home migration
2. Read UTF-16 text in the validator's name sweeps
3. Name the routing file's fault and isolate HOME
4. Follow the 40th link of a dangling settings chain
5. Wait for the lock holder and skip persistence without HOME
6. Count only real task-script runs and per-list ledger writes
7. Run tsc through cmd.exe on Windows and fix test docs
8. Stop a run whose sync state cannot be saved
9. Fail one ledger or checkpoint write, not the pull
10. Fix the import diagnostic, the Stop bound text, case twins
11. Name what changed during a documents move
12. Read progress files without following links
13. Refuse the links reconcile and the moves still miss
14. Make the progress moves' refusals say what happened
15. Release dforge 4.2.1

---

### Task 1: Refuse unreadable JSON in the home migration

**Files:**
- Modify: `plugins/dforge/scripts/lib/dforge-home-migrate.mjs`
- Test: `plugins/dforge/tests/darkmem-sync/migrate.test.mjs`
- Test: `plugins/dforge/tests/migrate-skill.test.sh`

**Interfaces:**
- Consumes: None
- Produces: None

**Items:** DR 43, DR 46

**Depends on:** none
**Implementer:** dr-superpowers:impl-sonnet-medium
**Evaluation:** files 1 - spec 0 - coupling 0 - risk 3 = 4

`migrateHome` reads four JSON files through `readJson`, which throws
`<file> could not be read: <reason>` on malformed JSON (or any read error other
than a missing file). Every other problem in the migration is a `refused:` line
and the run goes on, but a malformed file aborts the whole run: the
`~/.dr-forge/config.json` / `~/.dforge/config.json` merge, the old
`~/.dr-superpowers/config.json`, the current `~/.dforge/config.json` read for
the darkmem-mapping copy, and `~/.dforge/stores.json`. After this task each of
those reads goes through one helper, `readOrRefuse`, that turns the error into
a single refusal per file (`<file> could not be read: <reason>; fix or delete
it, then run dforge-migrate again`) and skips only the block that needed the
file: the merge `continue`s to the next entry, the darkmem copy and the
stores.json repointing are skipped, and the run finishes (DR 43.b). A test also
pins that an array `~/.dforge/config.json` is refused for the darkmem copy and
left unchanged (DR 43.d, coverage only). Separately, `migrate-skill.test.sh`
pins the migrate skill's commit-consent wording again (DR 46). DR 43.a and
43.c are accepted as they are and need no change here.

- [ ] **Step 1: Write the failing tests**

These tests prove that a malformed `~/.dr-forge/config.json` beside a
`~/.dforge/config.json` gives one refusal while the other entries still move
(dry run and real run alike); that a malformed `~/.dforge/config.json`,
`~/.dr-superpowers/config.json` or `~/.dforge/stores.json` each give one
refusal and the run still renames a mirror; and that a string or an array
config is refused for the darkmem copy and left unchanged.

In `plugins/dforge/tests/darkmem-sync/migrate.test.mjs`, replace the last test in the file:

```js
test("migrateHome refuses a string config.json for the darkmem copy without throwing", () => {
  const home = scratch("dms-home-");
  const dforge = path.join(home, ".dforge", "config.json");
  write(dforge, JSON.stringify("x"));
  write(path.join(home, ".dr-superpowers", "config.json"), JSON.stringify({ darkmem: { project: "p" } }));
  const { lines, refused } = migrateHome({ HOME: home });
  assert.equal(refused, 1, lines.join("\n"));
  assert.equal(JSON.parse(read(dforge)), "x");
});
```

with:

```js
test("migrateHome refuses a string or array config.json for the darkmem copy without throwing", () => {
  for (const value of ["x", ["x"]]) {
    const home = scratch("dms-home-");
    const dforge = path.join(home, ".dforge", "config.json");
    write(dforge, JSON.stringify(value));
    write(path.join(home, ".dr-superpowers", "config.json"), JSON.stringify({ darkmem: { project: "p" } }));
    const { lines, refused } = migrateHome({ HOME: home });
    assert.equal(refused, 1, lines.join("\n"));
    assert.deepEqual(JSON.parse(read(dforge)), value);
    assert.ok(!lines.some(line => line.startsWith("copied the darkmem mapping")), lines.join("\n"));
  }
});

test("migrateHome refuses a malformed ~/.dr-forge config.json once and still moves the other entries", () => {
  const home = scratch("dms-home-");
  const forge = path.join(home, ".dr-forge");
  const dforge = path.join(home, ".dforge");
  write(path.join(forge, "config.json"), "{not json");
  write(path.join(dforge, "config.json"), JSON.stringify({ layout: "auto" }));
  write(path.join(forge, "only-old.txt"), "old\n");
  const refusals = lines => lines.filter(line => line.startsWith("refused: "));
  const dry = migrateHome({ HOME: home }, { dryRun: true });
  const real = migrateHome({ HOME: home });
  for (const { lines, refused } of [dry, real]) {
    assert.equal(refused, 1, lines.join("\n"));
    assert.equal(refusals(lines).length, 1, lines.join("\n"));
    assert.ok(refusals(lines)[0].startsWith(`refused: ${path.join(forge, "config.json")} could not be read: `), lines.join("\n"));
  }
  assert.deepEqual(refusals(dry.lines), refusals(real.lines));
  assert.equal(read(path.join(dforge, "only-old.txt")), "old\n");
  assert.equal(read(path.join(forge, "config.json")), "{not json");
  assert.deepEqual(JSON.parse(read(path.join(dforge, "config.json"))), { layout: "auto" });
});

test("migrateHome refuses an unreadable config or stores file once and finishes the run", () => {
  for (const [label, file, extra] of [
    ["~/.dforge/config.json", [".dforge", "config.json"], home => write(path.join(home, ".dr-superpowers", "config.json"), JSON.stringify({ darkmem: { project: "p" } }))],
    ["~/.dr-superpowers/config.json", [".dr-superpowers", "config.json"], () => {}],
    ["~/.dforge/stores.json", [".dforge", "stores.json"], () => {}],
  ]) {
    const home = scratch("dms-home-");
    const bad = path.join(home, ...file);
    const mirror = path.join(home, ".dforge", "mirror", "p");
    write(bad, "{not json");
    extra(home);
    write(path.join(mirror, "forge", "a.md"), "a\n");
    const dry = migrateHome({ HOME: home }, { dryRun: true });
    const real = migrateHome({ HOME: home });
    for (const [verb, { lines, refused }] of [["would rename", dry], ["renamed", real]]) {
      assert.equal(refused, 1, `${label}: ${lines.join("\n")}`);
      assert.equal(lines.filter(line => line.startsWith(`refused: ${bad} could not be read: `)).length, 1, `${label}: ${lines.join("\n")}`);
      assert.ok(lines.includes(`${verb} ${mirror}'s forge/ to dforge/; darkmem's documents follow at its next sync`), `${label}: ${lines.join("\n")}`);
    }
    assert.equal(read(bad), "{not json", label);
  }
});
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID timeout 300 node --test plugins/dforge/tests/darkmem-sync/migrate.test.mjs`
Expected: FAIL, `tests 27`, `pass 25`, `fail 2`. The two failing tests are "migrateHome refuses a malformed ~/.dr-forge config.json once and still moves the other entries" and "migrateHome refuses an unreadable config or stores file once and finishes the run"; each throws `Error: <path> could not be read: Expected property name or '}' in JSON at position 1 (line 1 column 2)`. "migrateHome refuses a string or array config.json for the darkmem copy without throwing" passes already (DR 43.d is coverage only).

- [ ] **Step 3: Implement**

In `plugins/dforge/scripts/lib/dforge-home-migrate.mjs`, make these six replacements.

3a. Replace:

```js
const notObject = value => value === null || typeof value !== "object" || Array.isArray(value);
```

with:

```js
const notObject = value => value === null || typeof value !== "object" || Array.isArray(value);
// What readOrRefuse answers for a file it refused.
const UNREADABLE = Symbol("unreadable");
```

3b. Replace:

```js
  let merged;
  const badConfigs = new Set();
```

with:

```js
  let merged;
  const badConfigs = new Set();
  // Each file is refused once however many blocks read it; the block that
  // reads it is skipped, as a file that is not an object is.
  const readOrRefuse = file => {
    try {
      return readJson(file);
    } catch (error) {
      if (!badConfigs.has(file)) refuse(`${error.message}; fix or delete it, then run dforge-migrate again`);
      badConfigs.add(file);
      return UNREADABLE;
    }
  };
```

3c. Replace:

```js
        const old = readJson(from);
        const next = readJson(to);
```

with:

```js
        const old = readOrRefuse(from);
        const next = readOrRefuse(to);
        if (old === UNREADABLE || next === UNREADABLE) continue;
```

3d. Replace:

```js
  const oldConfig = readJson(path.join(oldHome, "config.json"));
  if (oldConfig?.darkmem && typeof oldConfig.darkmem === "object") {
```

with:

```js
  const oldConfig = readOrRefuse(path.join(oldHome, "config.json"));
  if (oldConfig !== UNREADABLE && oldConfig?.darkmem && typeof oldConfig.darkmem === "object") {
```

3e. Replace:

```js
    const current = (dryRun && merged) ? { ...merged } : readJson(source);
    const config = current ?? {};
    if (current !== undefined && notObject(current)) {
```

with:

```js
    const current = (dryRun && merged) ? { ...merged } : readOrRefuse(source);
    const config = current ?? {};
    if (current === UNREADABLE || (current !== undefined && notObject(current))) {
```

(The next line, `if (!badConfigs.has(source)) refuse(…does not hold a JSON object…)`, stays: `readOrRefuse` has already put an unreadable `source` in `badConfigs`, so that file gets no second refusal.)

3f. Replace:

```js
  const data = readJson(stores);
  if (data && typeof data === "object" && !Array.isArray(data)) {
```

with:

```js
  const data = readOrRefuse(stores);
  if (data !== UNREADABLE && data && typeof data === "object" && !Array.isArray(data)) {
```

Leave `readJson` itself unchanged. After the edit,
`timeout 60 grep -c 'readJson(' plugins/dforge/scripts/lib/dforge-home-migrate.mjs` prints `2`
(its definition and the call inside `readOrRefuse`).

- [ ] **Step 4: Run the tests to verify they pass**

Run: `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID timeout 300 node --test plugins/dforge/tests/darkmem-sync/migrate.test.mjs`
Expected: PASS, `tests 27`, `pass 27`, `fail 0`.

Run: `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID timeout 600 bash plugins/dforge/tests/dforge-migrate.test.sh`
Expected: PASS, last line `196 passed, 0 failed` (this suite runs the module through `scripts/dforge-migrate`).

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/scripts/lib/dforge-home-migrate.mjs plugins/dforge/tests/darkmem-sync/migrate.test.mjs
git commit -m "fix(migrate): refuse unreadable home JSON files"
```

- [ ] **Step 6: Pin the commit-consent wording (DR 46)**

In `plugins/dforge/tests/migrate-skill.test.sh`, replace:

```bash
commit=$(line_of "$SKILL" 'Commit only after your')
```

with:

```bash
present "asks before committing" "$SKILL" "human partner agrees, and stage nothing"
commit=$(line_of "$SKILL" 'Commit only after your')
```

Run: `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID timeout 600 bash plugins/dforge/tests/migrate-skill.test.sh`
Expected: PASS, last line `18 passed, 0 failed`.

Show the check can fail: run
`timeout 60 sed -i 's/human partner agrees, and stage nothing/human partner says yes, and stage nothing/' plugins/dforge/skills/migrate/SKILL.md`,
then the same suite command. Expected: `FAIL - asks before committing` with `missing: [human partner agrees, and stage nothing]`, last line `17 passed, 1 failed`. Restore with
`timeout 60 git checkout -- plugins/dforge/skills/migrate/SKILL.md`; `timeout 60 git diff --exit-code -- plugins/dforge/skills/migrate/SKILL.md` exits 0, and the suite prints `18 passed, 0 failed` again.

- [ ] **Step 7: Commit**

```bash
git add plugins/dforge/tests/migrate-skill.test.sh
git commit -m "test(migrate): pin the commit consent wording"
```

---

### Task 2: Read UTF-16 text in the validator's name sweeps

**Files:**
- Modify: `scripts/validate-repository.mjs`
- Test: `tests/repository-layout.test.mjs`

**Interfaces:**
- Consumes: None
- Produces: None

**Items:** DR 47

**Depends on:** none
**Implementer:** dr-superpowers:impl-sonnet-low
**Evaluation:** files 1 - spec 0 - coupling 0 - risk 1 = 2

The repository validator's name sweeps (retired `superpowers`, `dr-forge` and
`dcc-` names) read each file through `textLines`, which skips any file holding
a NUL byte as binary. UTF-16 text holds NUL bytes in almost every character, so
a UTF-16 file (a PowerShell script saved by Windows tools, for example) is
never swept (DR 47.a). After this task, a file that opens with a UTF-16
byte-order mark (`FF FE` little-endian, `FE FF` big-endian) is decoded as
UTF-16 first, and the binary rule then applies to the decoded text. The binary
fixture also moves its NUL from byte 0 to the middle of the file, so a rule
that only looked at the first byte would fail it (DR 47.b).

- [ ] **Step 1: Write the failing tests**

In `tests/repository-layout.test.mjs`, inside the table of
`test('repository validator rejects broken distribution contracts', …)`, replace:

```js
    ['retired dr-forge home', (c, dir) => { writeFileSync(resolve(dir, 'plugins/dforge/scripts/stray.sh'), 'ls ~/.dr-forge\n'); }, /plugins\/dforge\/scripts\/stray\.sh:1: retired dr-forge name/],
```

with:

```js
    ['retired dr-forge home', (c, dir) => { writeFileSync(resolve(dir, 'plugins/dforge/scripts/stray.sh'), 'ls ~/.dr-forge\n'); }, /plugins\/dforge\/scripts\/stray\.sh:1: retired dr-forge name/],
    ['retired dr-forge home in UTF-16LE text', (c, dir) => { writeFileSync(resolve(dir, 'plugins/dforge/scripts/stray.sh'), Buffer.concat([Buffer.from([0xff, 0xfe]), Buffer.from('ls ~/.dr-forge\n', 'utf16le')])); }, /plugins\/dforge\/scripts\/stray\.sh:1: retired dr-forge name/],
    ['retired dr-forge home in UTF-16BE text', (c, dir) => { writeFileSync(resolve(dir, 'plugins/dforge/scripts/stray.sh'), Buffer.concat([Buffer.from([0xfe, 0xff]), Buffer.from('ls ~/.dr-forge\n', 'utf16le').swap16()])); }, /plugins\/dforge\/scripts\/stray\.sh:1: retired dr-forge name/],
```

In `test('the name sweeps skip binary files', …)`, replace:

```js
    const bytes = Buffer.from('\u0000superpowers dr-forge dcc-darkraise-ui\n', 'utf8');
```

with:

```js
    const bytes = Buffer.from('superpowers dr-forge\u0000 dcc-darkraise-ui\n', 'utf8');
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID timeout 300 node --test tests/repository-layout.test.mjs`
Expected: FAIL, `tests 36`, `pass 33`, `fail 3`: the subtests "retired dr-forge home in UTF-16LE text" and "retired dr-forge home in UTF-16BE text" (each `The input did not match the regular expression /plugins\/dforge\/scripts\/stray\.sh:1: retired dr-forge name/. Input: ''`) and their parent "repository validator rejects broken distribution contracts". "the name sweeps skip binary files" still passes (DR 47.b strengthens a fixture; Step 4 shows it can fail).

- [ ] **Step 3: Implement**

In `scripts/validate-repository.mjs`, replace:

```js
// A file's lines for the name sweeps, or null for a binary file (one holding a
// NUL byte), whose bytes are not text to read names in.
const textLines = path => {
  const bytes = readFileSync(path);
  return bytes.includes(0) ? null : bytes.toString('utf8').split('\n');
};
```

with:

```js
// A file's lines for the name sweeps, or null for a binary file (one holding a
// NUL character), whose bytes are not text to read names in. UTF-16 text holds
// NUL bytes, so a file opening with a UTF-16 byte-order mark is decoded first.
const textLines = path => {
  const bytes = readFileSync(path);
  const text = bytes[0] === 0xff && bytes[1] === 0xfe ? new TextDecoder('utf-16le').decode(bytes.subarray(2))
    : bytes[0] === 0xfe && bytes[1] === 0xff ? new TextDecoder('utf-16be').decode(bytes.subarray(2))
    : bytes.toString('utf8');
  return text.includes('\u0000') ? null : text.split('\n');
};
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID timeout 300 node --test tests/repository-layout.test.mjs`
Expected: PASS, `tests 36`, `pass 36`, `fail 0`.

Run: `timeout 120 node scripts/validate-repository.mjs`
Expected: exit 0, `Repository catalogs, manifests, versions, bundled links and the settings schema are valid.` (no tracked file opens with a UTF-16 byte-order mark today, so the change adds no error on the tree).

Show the moved NUL fixture can fail: in `scripts/validate-repository.mjs` temporarily change
`  return text.includes('\u0000') ? null : text.split('\n');` to
`  return text[0] === '\u0000' ? null : text.split('\n');`, run the layout test again. Expected: `fail 1`, "the name sweeps skip binary files". Restore the line exactly as Step 3 wrote it and rerun: `pass 36`.

- [ ] **Step 5: Commit**

```bash
git add scripts/validate-repository.mjs tests/repository-layout.test.mjs
git commit -m "fix(validate): read UTF-16 text in name sweeps"
```

---

### Task 3: Name the routing file's fault and isolate HOME

**Files:**
- Modify: `plugins/dforge/scripts/plan-lint`
- Test: `plugins/dforge/tests/plan-lint.test.sh`

**Interfaces:**
- Consumes: None
- Produces: plan-lint's stderr line on an unreadable routing policy, exit 2: `plan-lint: cannot read the routing policy version from <ROUTING>: <cause>`, where `<cause>` is `jq is not installed`, `the file cannot be parsed` or `the file has no version`

**Items:** CX 16

**Depends on:** none
**Implementer:** dr-superpowers:impl-sonnet-low
**Evaluation:** files 1 - spec 0 - coupling 0 - risk 1 = 2

For a Codex plan, plan-lint reads the routing policy version from
`reference/codex-routing.json` with jq. Whenever that version comes back empty
it prints `cannot read the routing policy version from <file> (is jq
installed?)`, also when jq is installed and the file is corrupt or has no
`version` key (CX 16.a). After this task plan-lint checks for jq first, and
with jq present asks `jq empty` whether the file parses, so the message names
the real cause. Separately, the plan-lint suite runs most cases with the
developer's own `HOME`, so a malformed `~/.dforge/config.json` on the machine
fails six register cases (CX 16.b). The suite now exports `HOME="$TMP/home"`
once at its top; the name-key cases keep the `HOME` they set themselves.

- [ ] **Step 1: Show the suite reads the developer's HOME**

Run:

```bash
mkdir -p /tmp/plan-lint-badhome/.dforge && printf '{not json' > /tmp/plan-lint-badhome/.dforge/config.json
env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID HOME=/tmp/plan-lint-badhome timeout 600 bash plugins/dforge/tests/plan-lint.test.sh
```

Expected: last line `205 passed, 6 failed`. The failures are `plan-lint: an uncited assigned row is an error`, `plan-lint: a plan with no Items line warns`, `plan-lint: a dangling citation is an error`, `plan-lint: 'last' with another sub-project's open row is an error`, `plan-lint: an empty Item cell: the row is still this plan's` and `plan-lint: an empty Item cell: 'last' names only the other row`, each printing `darkmem-config: /tmp/plan-lint-badhome/.dforge/config.json is not valid JSON: …`.

- [ ] **Step 2: Give the suite its own HOME**

In `plugins/dforge/tests/plan-lint.test.sh`, replace:

```bash
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cd "$TMP"
```

with:

```bash
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cd "$TMP"
# Every case reads this home, never the developer's ~/.dforge; the name-key
# cases below set their own.
export HOME="$TMP/home"
mkdir -p "$HOME"
```

Leave the `HOME="$TMP/name-key-home"` and `HOME=$SH` prefixes further down as they are.

Run the Step 1 suite command again. Expected: `211 passed, 0 failed`, and `cat /tmp/plan-lint-badhome/.dforge/config.json` still prints `{not json`. Then run without the override: `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID timeout 600 bash plugins/dforge/tests/plan-lint.test.sh` — `211 passed, 0 failed`. Remove the scratch home: `rm -rf /tmp/plan-lint-badhome`.

- [ ] **Step 3: Commit**

```bash
git add plugins/dforge/tests/plan-lint.test.sh
git commit -m "test(plan-lint): give the suite its own HOME"
```

- [ ] **Step 4: Write the failing tests**

These tests prove that a failing jq, a version-less routing file and a corrupt routing file each name their cause and do not mention jq being installed, and that a PATH without jq says jq is not installed.

In `plugins/dforge/tests/plan-lint.test.sh`, replace:

```bash
# A routing policy that cannot be read is a usage failure, not a finding.
mkdir -p "$TMP/nojq"
printf '#!/bin/sh\nexit 1\n' > "$TMP/nojq/jq"
chmod +x "$TMP/nojq/jq"
out=$(PATH="$TMP/nojq:$PATH" bash "$LINT" codex.md 2>&1); status=$?
check "an unreadable routing policy: exit 2" "$status" "2"
has "an unreadable routing policy: says so" "$out" "plan-lint: cannot read the routing policy version from"
lacks "an unreadable routing policy: no empty-policy finding" "$out" "not ;"
```

with:

```bash
# A routing policy that cannot be read is a usage failure, not a finding, and
# its message names the cause. A jq that fails reads as a file it cannot parse.
mkdir -p "$TMP/nojq"
printf '#!/bin/sh\nexit 1\n' > "$TMP/nojq/jq"
chmod +x "$TMP/nojq/jq"
out=$(PATH="$TMP/nojq:$PATH" bash "$LINT" codex.md 2>&1); status=$?
check "an unreadable routing policy: exit 2" "$status" "2"
has "an unreadable routing policy: says so" "$out" "plan-lint: cannot read the routing policy version from"
has "a failing jq: the file cannot be parsed" "$out" "codex-routing.json: the file cannot be parsed"
lacks "an unreadable routing policy: no empty-policy finding" "$out" "not ;"
# A copy of the scripts reads its own reference/codex-routing.json.
KIT="$TMP/kit"
mkdir -p "$KIT"
cp -R "$HERE/../scripts" "$HERE/../reference" "$KIT/"
printf '{"tiers":{}}\n' > "$KIT/reference/codex-routing.json"
out=$(bash "$KIT/scripts/plan-lint" codex.md 2>&1); status=$?
check "a version-less routing policy: exit 2" "$status" "2"
has "a version-less routing policy: says it has no version" "$out" "codex-routing.json: the file has no version"
lacks "a version-less routing policy: does not blame jq" "$out" "jq installed"
printf '{"version":\n' > "$KIT/reference/codex-routing.json"
out=$(bash "$KIT/scripts/plan-lint" codex.md 2>&1); status=$?
check "a corrupt routing policy: exit 2" "$status" "2"
has "a corrupt routing policy: says it cannot be parsed" "$out" "codex-routing.json: the file cannot be parsed"
lacks "a corrupt routing policy: does not blame jq" "$out" "jq installed"
# No jq on PATH: links to every other tool plan-lint runs before the check.
mkdir -p "$TMP/jqless"
for tool in awk cat cut dirname git grep head mktemp rm sed tr; do ln -s "$(type -P "$tool")" "$TMP/jqless/$tool"; done
out=$(PATH="$TMP/jqless" "$BASH" "$LINT" codex.md 2>&1); status=$?
check "no jq: exit 2" "$status" "2"
has "no jq: says jq is not installed" "$out" "codex-routing.json: jq is not installed"
lacks "no jq: plan-lint found every other tool it runs" "$out" "command not found"
```

- [ ] **Step 5: Run the tests to verify they fail**

Run: `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID timeout 600 bash plugins/dforge/tests/plan-lint.test.sh`
Expected: last line `215 passed, 6 failed`. The failures: `a failing jq: the file cannot be parsed`, `a version-less routing policy: says it has no version`, `a version-less routing policy: does not blame jq`, `a corrupt routing policy: says it cannot be parsed`, `a corrupt routing policy: does not blame jq`, `no jq: says jq is not installed`; each shows today's `… codex-routing.json (is jq installed?)`. The exit-2 checks and `no jq: plan-lint found every other tool it runs` pass.

- [ ] **Step 6: Implement**

In `plugins/dforge/scripts/plan-lint`, replace:

```bash
if [ "$codex" -eq 1 ]; then
  want_policy=$(jq -r '.version // empty' "$ROUTING" 2>/dev/null | tr -d '\r')
  if [ -z "$want_policy" ]; then
    echo "plan-lint: cannot read the routing policy version from $ROUTING (is jq installed?)" >&2
    exit 2
  fi
```

with:

```bash
if [ "$codex" -eq 1 ]; then
  if ! command -v jq > /dev/null 2>&1; then
    echo "plan-lint: cannot read the routing policy version from $ROUTING: jq is not installed" >&2
    exit 2
  fi
  want_policy=$(jq -r '.version // empty' "$ROUTING" 2>/dev/null | tr -d '\r')
  if [ -z "$want_policy" ]; then
    if jq empty "$ROUTING" > /dev/null 2>&1; then cause="the file has no version"; else cause="the file cannot be parsed"; fi
    echo "plan-lint: cannot read the routing policy version from $ROUTING: $cause" >&2
    exit 2
  fi
```

- [ ] **Step 7: Run the tests to verify they pass**

Run: `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID timeout 600 bash plugins/dforge/tests/plan-lint.test.sh`
Expected: PASS, last line `221 passed, 0 failed`.

- [ ] **Step 8: Commit**

```bash
git add plugins/dforge/scripts/plan-lint plugins/dforge/tests/plan-lint.test.sh
git commit -m "fix(plan-lint): name the routing file's fault"
```

---

### Task 4: Follow the 40th link of a dangling settings chain

`realTarget` in `dforge-config.mjs` follows a dangling symbolic-link chain hop by hop, at most `MAX_LINK_HOPS` (40) times. The loop runs `hop < MAX_LINK_HOPS`, so after reading the 40th link it stops before checking whether the path it reached is itself a link, and throws `more than 40 symbolic links` for a chain of exactly 40 links. A `dforge-config set` through such a chain exits 1 and writes nothing. The loop changes to `hop <= MAX_LINK_HOPS`: one more pass reads the reached path, finds it is not a link, and returns it, so the write lands on the chain's final path. A 41-link chain is still refused (on Linux the operating system already refuses it with `ELOOP` before this loop runs).

**Files:**
- Modify: `plugins/dforge/scripts/lib/dforge-config.mjs`
- Test: `plugins/dforge/tests/dforge-config.test.sh`

**Interfaces:**
- Consumes: None
- Produces: None

**Items:** FS 49

**Depends on:** none
**Implementer:** dr-superpowers:impl-sonnet-low
**Evaluation:** files 1 - spec 0 - coupling 0 - risk 1 = 2

- [ ] **Step 1: Write the failing test**

The test builds a dangling chain of exactly 40 links (the settings file `$CS`, then `link1` … `link39`, then the missing `end.json`) and writes through it.

In `plugins/dforge/tests/dforge-config.test.sh`, find:

```bash
  check "claude: a dangling chain: its end is created" "$(tr -d ' \n' < "$TMP/dotfiles/end.json" 2>/dev/null)" '{"autoCompactWindow":550000}'
fi
```

Replace it with:

```bash
  check "claude: a dangling chain: its end is created" "$(tr -d ' \n' < "$TMP/dotfiles/end.json" 2>/dev/null)" '{"autoCompactWindow":550000}'
  # A dangling chain of exactly 40 links, the most the loop allows, is still
  # followed: the 40th hop lands on the chain's final path.
  mkdir -p "$TMP/chain40"
  rm -f "$CS"; ln -s "$TMP/chain40/end.json" "$TMP/chain40/link39"
  for n in $(seq 38 -1 1); do ln -s "$TMP/chain40/link$((n + 1))" "$TMP/chain40/link$n"; done
  ln -s "$TMP/chain40/link1" "$CS"
  fc set autoCompactWindow 540000
  check "claude: a 40-link dangling chain: exit 0" "$?" "0"
  check "claude: a 40-link dangling chain: its end is created" "$(tr -d ' \n' < "$TMP/chain40/end.json" 2>/dev/null)" '{"autoCompactWindow":540000}'
  check "claude: a 40-link dangling chain: the last link stays" "$([ -L "$TMP/chain40/link39" ] && echo yes || echo no)" "yes"
fi
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID timeout 600 bash plugins/dforge/tests/dforge-config.test.sh`
Expected: FAIL — `188 passed, 2 failed` when run as root (two fewer passes when not root, where the owner case is skipped). The failures are "claude: a 40-link dangling chain: exit 0" (got `1`) and "claude: a 40-link dangling chain: its end is created" (got empty; the shell also prints a `No such file or directory` line for `end.json`).

- [ ] **Step 3: Implement**

In `plugins/dforge/scripts/lib/dforge-config.mjs`, find:

```js
  for (let hop = 0; hop < MAX_LINK_HOPS; hop++) {
```

Replace it with:

```js
  for (let hop = 0; hop <= MAX_LINK_HOPS; hop++) {
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID timeout 600 bash plugins/dforge/tests/dforge-config.test.sh`
Expected: PASS — `190 passed, 0 failed` when run as root.

The cockpit runs `dforge-config.mjs set`, so it must still pass:
Run: `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID timeout 300 /root/.local/bin/claude plugin test plugins/dforge`
Expected: PASS (301 pass, 0 fail on the current tree).

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/scripts/lib/dforge-config.mjs plugins/dforge/tests/dforge-config.test.sh
git commit -m "fix(config): follow the 40th link of a chain"
```

---

### Task 5: Wait for the lock holder and skip persistence without HOME

Two auto-run findings. First (AE 39.a): in `tests/auto-run.test.sh`, the two "a start … waits for the lock" loops start a background `flock` holder and then `sleep 0.5`, assuming the holder has taken the lock by then. On a slow host the start under test can take the lock first and the case fails (or passes) by chance. The holder now touches `$STATE.ready` once it holds the lock, and the test waits for that file (at most 10 s; on timeout the case fails and the holder is killed, so the suite never hangs). `$STATE.ready` is removed before each holder starts. The `no-such-flock` variant takes its lock directory synchronously, so it touches the ready file right after `mkdir` and shares the same wait.

Second (AE 39.c): `scripts/session-start.sh` writes its session records, the cockpit heartbeat directory and the turn stamp under `${HOME:-}/.claude/...`. With `HOME` empty those paths start at `/.claude`, so the hook creates `/.claude/dforge/sessions/...` at the file-system root (as root) or tries to. Each of the three persistence steps now runs only when `HOME` is non-empty. The entry-point injection is unaffected.

**Files:**
- Modify: `plugins/dforge/scripts/session-start.sh`
- Test: `plugins/dforge/tests/auto-run.test.sh`
- Test: `plugins/dforge/tests/turn-end.test.sh`

**Interfaces:**
- Consumes: None
- Produces: None

**Items:** AE 39

**Depends on:** none
**Implementer:** dr-superpowers:impl-sonnet-low
**Evaluation:** files 1 - spec 0 - coupling 0 - risk 1 = 2

- [ ] **Step 1: Write the empty-HOME test (AE 39.c)**

The case puts logging `mkdir` and `find` shims first on `PATH`. Each shim appends every argument to `$TMP/shim.log`, one per line, and refuses (exit 1, without running the real tool) any argument starting with `/.claude`, so the case can fail as root and never writes `/.claude` on the host. A probe first proves the shim is reached.

In `plugins/dforge/tests/turn-end.test.sh`, find:

```bash
check "session-start makes the cockpit directory without a session record" \
  "$([ -d "$H3/.claude/dforge/sessions/cockpit" ] && echo yes || echo no)" "yes"
```

Replace it with:

```bash
check "session-start makes the cockpit directory without a session record" \
  "$([ -d "$H3/.claude/dforge/sessions/cockpit" ] && echo yes || echo no)" "yes"
# An empty HOME persists nothing: no path under /.claude reaches mkdir or find.
# The shims log every argument and refuse such a path instead of running the
# tool, so the case holds as root and never writes /.claude on the host.
SHIM="$TMP/shim-bin"
mkdir -p "$SHIM"
for tool in mkdir find; do
  real=$(command -v "$tool")
  cat > "$SHIM/$tool" <<EOF
#!/bin/sh
printf '%s\n' "\$@" >> "$TMP/shim.log"
for a in "\$@"; do case "\$a" in /.claude*) exit 1 ;; esac; done
exec "$real" "\$@"
EOF
  chmod +x "$SHIM/$tool"
done
PATH="$SHIM:$PATH" mkdir -p "$TMP/shim-probe"
check "the mkdir shim logs its arguments" "$(grep -c "^$TMP/shim-probe\$" "$TMP/shim.log")" "1"
out=$(jq -n --arg tp "$BG" --arg cwd "$REPO" '{session_id:"s-7",transcript_path:$tp,cwd:$cwd,source:"startup"}' \
  | HOME= PATH="$SHIM:$PATH" bash "$HERE/../scripts/session-start.sh")
check "session-start with an empty HOME touches nothing under /.claude" "$(grep -c '^/\.claude' "$TMP/shim.log")" "0"
check "session-start with an empty HOME still injects the entry point" \
  "$(jq -r '.hookSpecificOutput.additionalContext | contains("You have dforge.")' <<<"$out" 2>/dev/null)" "true"
```

- [ ] **Step 2: Run it to verify it fails**

Run: `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID timeout 600 bash plugins/dforge/tests/turn-end.test.sh`
Expected: FAIL — `119 passed, 1 failed`: "session-start with an empty HOME touches nothing under /.claude" (got `4`: the sessions directory, its `by-id`, the cockpit directory and the turns directory). `timeout 60 ls -d /.claude` afterwards still reports `No such file or directory`.

- [ ] **Step 3: Guard the persistence steps on HOME**

In `plugins/dforge/scripts/session-start.sh`, find:

```bash
  source_event=$(jq -r '.source // empty' <<<"$stdin_json")
  if [ -n "$transcript_path" ] && [ -n "$cwd" ]; then
```

Replace it with:

```bash
  source_event=$(jq -r '.source // empty' <<<"$stdin_json")
  # Every record below lives under $HOME; with HOME empty its paths would start
  # at /.claude, so nothing is persisted.
  if [ -n "${HOME:-}" ] && [ -n "$transcript_path" ] && [ -n "$cwd" ]; then
```

In `plugins/dforge/scripts/session-start.sh`, find:

```bash
  cockpit_dir="${HOME:-}/.claude/dforge/sessions/cockpit"
  mkdir -p "$cockpit_dir" 2>/dev/null || true
  find "$cockpit_dir" -maxdepth 1 -type f -mtime +30 -delete 2>/dev/null || true
```

Replace it with:

```bash
  if [ -n "${HOME:-}" ]; then
    cockpit_dir="$HOME/.claude/dforge/sessions/cockpit"
    mkdir -p "$cockpit_dir" 2>/dev/null || true
    find "$cockpit_dir" -maxdepth 1 -type f -mtime +30 -delete 2>/dev/null || true
  fi
```

In `plugins/dforge/scripts/session-start.sh`, find:

```bash
      if [ -n "$session_id" ] && mkdir -p "${HOME:-}/.claude/dforge/sessions/turns" 2>/dev/null; then
```

Replace it with:

```bash
      if [ -n "${HOME:-}" ] && [ -n "$session_id" ] && mkdir -p "${HOME:-}/.claude/dforge/sessions/turns" 2>/dev/null; then
```

- [ ] **Step 4: Run the session-start suites to verify they pass**

Run: `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID timeout 600 bash plugins/dforge/tests/turn-end.test.sh`
Expected: PASS — `120 passed, 0 failed`.

Other suites that run `session-start.sh`, which must still pass:
Run: `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID timeout 600 bash plugins/dforge/tests/hook.test.sh`
Expected: PASS (`69 passed, 0 failed`).
Run: `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID timeout 300 node --test plugins/dforge/tests/darkmem-sync/hooks.test.mjs`
Expected: PASS (22 pass, 0 fail).

- [ ] **Step 5: Commit the session-start fix**

```bash
git add plugins/dforge/scripts/session-start.sh plugins/dforge/tests/turn-end.test.sh
git commit -m "fix(hooks): persist nothing when HOME is empty"
```

- [ ] **Step 6: Show the lock-holder race (AE 39.a)**

This is a fix to the test itself, so no new case fails first; a `flock` shim that delays only the holder (the holder calls `flock <file> bash -c …`; `auto-run` calls `flock -w 10 9`) shows the race the `sleep 0.5` leaves open. Run, from the worktree root:

```bash
D=$(mktemp -d); printf '#!/bin/sh\n[ "$2" != bash ] || sleep 1\nexec "%s" "$@"\n' "$(command -v flock)" > "$D/flock"; chmod +x "$D/flock"
env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID PATH="$D:$PATH" timeout 600 bash plugins/dforge/tests/auto-run.test.sh; rm -rf "$D"
```

Expected: FAIL — `184 passed, 2 failed`: "flock: a start waits for the lock" (got `s-2:["held"]`) and "flock: a start that waited for the lock finds the run made live meanwhile" (got `0:s-2:true`). Without the shim the suite passes today (`186 passed, 0 failed`). If `flock` is not installed, both loops skip their `flock` variant and this step does not apply; say so in the report.

- [ ] **Step 7: Wait for the holder's ready file**

In `plugins/dforge/tests/auto-run.test.sh`, find:

```bash
# The holder reads the state, keeps the lock two seconds, then writes back what
# it read, as an update does: a start that does not wait for it is lost.
for lock in flock no-such-flock; do
  [ "$lock" = no-such-flock ] || command -v flock >/dev/null 2>&1 || continue
  ar --session s-1 start --spec "$SPEC" --register docs/r.md --force >/dev/null
  if [ "$lock" = flock ]; then
    flock "$STATE.lock" bash -c 's=$(cat "$1"); sleep 2; jq ".rulings = [\"held\"]" <<<"$s" > "$1.held" && mv -f "$1.held" "$1"' _ "$STATE" &
  else
    mkdir "$STATE.lockd"
    (s=$(cat "$STATE"); sleep 2; jq '.rulings = ["held"]' <<<"$s" > "$STATE.held" && mv -f "$STATE.held" "$STATE"; rmdir "$STATE.lockd") &
  fi
  sleep 0.5
  DFORGE_FLOCK=$lock ar --session s-2 start --spec "$SPEC" --register docs/r.md --force >/dev/null
```

Replace it with:

```bash
# The holder reads the state, keeps the lock two seconds, then writes back what
# it read, as an update does: a start that does not wait for it is lost.
# held <name>: waits up to 10 s for the holder to touch $STATE.ready, which it
# does once it holds the lock; on timeout it fails <name> and stops the holder,
# so the case cannot hang.
held() {
  local i
  for i in $(seq 100); do
    [ -e "$STATE.ready" ] && return 0
    sleep 0.1
  done
  check "$1" "the holder never took the lock" "taken"
  kill "$holder" 2>/dev/null
  wait
  return 1
}
for lock in flock no-such-flock; do
  [ "$lock" = no-such-flock ] || command -v flock >/dev/null 2>&1 || continue
  ar --session s-1 start --spec "$SPEC" --register docs/r.md --force >/dev/null
  rm -f "$STATE.ready"
  if [ "$lock" = flock ]; then
    flock "$STATE.lock" bash -c 'touch "$1.ready"; s=$(cat "$1"); sleep 2; jq ".rulings = [\"held\"]" <<<"$s" > "$1.held" && mv -f "$1.held" "$1"' _ "$STATE" &
  else
    mkdir "$STATE.lockd"
    touch "$STATE.ready"
    (s=$(cat "$STATE"); sleep 2; jq '.rulings = ["held"]' <<<"$s" > "$STATE.held" && mv -f "$STATE.held" "$STATE"; rmdir "$STATE.lockd") &
  fi
  holder=$!
  held "$lock: a start waits for the lock" || continue
  DFORGE_FLOCK=$lock ar --session s-2 start --spec "$SPEC" --register docs/r.md --force >/dev/null
```

In `plugins/dforge/tests/auto-run.test.sh`, find:

```bash
  ar --session s-1 stop >/dev/null
  if [ "$lock" = flock ]; then
    flock "$STATE.lock" bash -c 'sleep 2; jq ".active = true" "$1" > "$1.held" && mv -f "$1.held" "$1"' _ "$STATE" &
  else
    mkdir "$STATE.lockd"
    (sleep 2; jq '.active = true' "$STATE" > "$STATE.held" && mv -f "$STATE.held" "$STATE"; rmdir "$STATE.lockd") &
  fi
  sleep 0.5
```

Replace it with:

```bash
  ar --session s-1 stop >/dev/null
  rm -f "$STATE.ready"
  if [ "$lock" = flock ]; then
    flock "$STATE.lock" bash -c 'touch "$1.ready"; sleep 2; jq ".active = true" "$1" > "$1.held" && mv -f "$1.held" "$1"' _ "$STATE" &
  else
    mkdir "$STATE.lockd"
    touch "$STATE.ready"
    (sleep 2; jq '.active = true' "$STATE" > "$STATE.held" && mv -f "$STATE.held" "$STATE"; rmdir "$STATE.lockd") &
  fi
  holder=$!
  held "$lock: a start that waited for the lock finds the run made live meanwhile" || continue
```

- [ ] **Step 8: Run the auto-run suite to verify it passes, with and without the slow holder**

Run: `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID timeout 600 bash plugins/dforge/tests/auto-run.test.sh`
Expected: PASS — `186 passed, 0 failed`.

Run the Step 6 command again (the slow-holder shim).
Expected: PASS — `186 passed, 0 failed`: the start now waits for the ready file, so the delayed holder still takes the lock first.

- [ ] **Step 9: Commit the test fix**

```bash
git add plugins/dforge/tests/auto-run.test.sh
git commit -m "test(auto-run): wait for the lock holder's signal"
```

---

### Task 6: Count only real task-script runs and per-list ledger writes

Two gaps in the controller-eval harness (DF 24). `planSlugs` in `evals/controller/lib/sessions.mjs` matches `/task-brief`, `/review-route` or `/review-package` followed by a plan argument anywhere in a Bash command, so a command that only reads the script (`cat $S/task-brief docs/plans/x.md`, `sed -n 1p /p/scripts/task-brief x.md`) counts as running it on plan `x`, and so does text that only mentions a run (`echo 'bash /p/scripts/task-brief docs/plans/x.md'`). `planArgs` now cuts the command into simple commands at `;`, `&`, `|`, `(`, `)`, a backtick and a newline outside quotes, with each quoted string one word, and counts the script only as a command's first word once the words that may precede a command are skipped: assignments (`FOO=1`), the reserved words `!`, `{`, `if`, `then`, `elif`, `else`, `while`, `until`, `do`, the wrappers `bash`, `sh`, `command`, `env`, `exec`, `nohup`, `time`, `timeout`, their options (with the value of `-u`, `-k` or `-s`), and a duration (`60`, `5m`). A new test pins the negative cases (`cat …`, `sed …`, a quoted `echo`) and the runs `S=/p/scripts; bash $S/task-brief …`, `timeout 60 bash …`, a direct `/p/scripts/review-route …` after `&&`, `FOO=1 /p/scripts/task-brief …` and `env -u AR_SESSION timeout 60 bash …`.

`measureTranscript` in `evals/controller/lib/transcript.mjs` (the `completed` count) treats a failed Bash call as a whole: if any `&&` precedes its first ledger redirect, nothing counts; otherwise every "Task N: complete" in the whole command counts, even one written behind a later `&&`. The failed call is now cut into shell lists (`;`, newline, an `&` that is neither `&&` nor part of a redirect such as `2>&1`, all outside quotes), and only the lists whose ledger redirect has no `&&` ahead of it inside that list are counted. A heredoc's body, on the lines after its opener, belongs to the list that opened it, even when more lists follow the opener on its line (`cat >> progress.md <<'EOF'; false`); its delimiter is the whole word after `<<` or `<<-`, quoted (`'END-OF-DOC'`) or not.

**Files:**
- Modify: `evals/controller/lib/sessions.mjs`
- Modify: `evals/controller/lib/transcript.mjs`
- Test: `evals/controller/tests/sessions.test.mjs`
- Test: `evals/controller/tests/transcript.test.mjs`

**Interfaces:**
- Consumes: None
- Produces: None

**Items:** DF 24

**Depends on:** none
**Implementer:** dr-superpowers:impl-sonnet-medium
**Evaluation:** files 2 - spec 0 - coupling 0 - risk 1 = 3

- [ ] **Step 1: Write the failing tests**

In `evals/controller/tests/sessions.test.mjs`, find:

```js
  assert.deepEqual(planSlugs(join(own, 's9.jsonl')), ['2026-10-18-alpha']);
});
```

Replace it with:

```js
  assert.deepEqual(planSlugs(join(own, 's9.jsonl')), ['2026-10-18-alpha']);
});

test('planSlugs counts a script run, not another command reading its path', () => {
  const dir = join(top, 'slugs');
  write(join(dir, 'cat.jsonl'), [skill(SDD), bash('c', 'cat $S/task-brief docs/plans/2026-10-18-zeta.md')]);
  write(join(dir, 'sed.jsonl'), [skill(SDD), bash('s', 'sed -n 1p /p/scripts/task-brief 2026-10-18-zeta.md')]);
  write(join(dir, 'echo.jsonl'), [skill(SDD), bash('e', "echo 'bash /p/scripts/task-brief docs/plans/2026-10-18-zeta.md'")]);
  write(join(dir, 'run.jsonl'), [skill(SDD), bash('v', 'S=/p/scripts; bash $S/task-brief docs/plans/2026-10-18-eta.md 1'), bash('t', 'timeout 60 bash /p/scripts/task-brief docs/plans/2026-10-18-theta.md 2'), bash('d', 'cd /w && /p/scripts/review-route docs/plans/2026-10-18-iota.md 3'), bash('a', 'FOO=1 /p/scripts/task-brief docs/plans/2026-10-18-kappa.md 4'), bash('w', 'env -u AR_SESSION timeout 60 bash /p/scripts/task-brief docs/plans/2026-10-18-lambda.md 5')]);
  assert.deepEqual(planSlugs(join(dir, 'cat.jsonl')), []);
  assert.deepEqual(planSlugs(join(dir, 'sed.jsonl')), []);
  assert.deepEqual(planSlugs(join(dir, 'echo.jsonl')), []);
  assert.deepEqual(planSlugs(join(dir, 'run.jsonl')), ['2026-10-18-eta', '2026-10-18-iota', '2026-10-18-kappa', '2026-10-18-lambda', '2026-10-18-theta']);
});
```

In `evals/controller/tests/transcript.test.mjs`, find:

```js
  assert.deepEqual(m.completed, ['8', '9']);
});
```

Replace it with:

```js
  assert.deepEqual(m.completed, ['8', '9']);
});

test('a failed Bash call counts the ledger lines of each list that wrote them, not of one behind an &&', () => {
  const failedCall = id => ({ type: 'user', message: { content: [{ type: 'tool_result', tool_use_id: id, is_error: true, content: 'Exit code 1' }] } });
  const m = measureTranscript(jsonl([
    said('msg_a', 'claude-sonnet-5-5', usage(1, 1), [
      use('l1', 'Bash', { command: "echo 'Task 1: complete (commits a..b)' >> .dforge/sdd/p/progress.md; false && echo 'Task 2: complete (commits c..d)' >> .dforge/sdd/p/progress.md" }),
      use('l2', 'Bash', { command: "x && y; echo 'Task 3: complete (commits e..f)' >> .dforge/sdd/p/progress.md; false" }),
      use('l3', 'Bash', { command: "echo 'Task 4: complete (commits g..h; review clean)' >> .dforge/sdd/p/progress.md 2>&1; false" }),
      use('l4', 'Bash', { command: "cat >> .dforge/sdd/p/progress.md <<'EOF'\nTask 5: complete (commits i..j)\nEOF\nfalse" }),
      use('l5', 'Bash', { command: "cat >> .dforge/sdd/p/progress.md <<'EOF'; false\nTask 6: complete (commits k..l)\nEOF" }),
      use('l6', 'Bash', { command: "cat >> .dforge/sdd/p/progress.md <<'END-OF-DOC'\nTask 7: complete (commits m..n)\nEND-OF-DOC\nfalse" }),
      use('l7', 'Bash', { command: "false && cat >> .dforge/sdd/p/progress.md <<'EOF'; true\nTask 8: complete (commits o..p)\nEOF\nfalse" }),
    ]),
    failedCall('l1'), failedCall('l2'), failedCall('l3'), failedCall('l4'), failedCall('l5'), failedCall('l6'), failedCall('l7'),
  ]));
  assert.deepEqual(m.completed, ['1', '3', '4', '5', '6', '7']);
});
```

`l3` (a `;` inside the quoted ledger text, and a `2>&1`), `l4` (a heredoc body on its own lines), `l5` (a heredoc whose opener's line goes on to another list), `l6` (a quoted delimiter that is not a single word of letters) and `l7` (a heredoc whose list sits behind an `&&`, so its body never counts) pass today; they guard the list splitter against losing lines today's code counts, and against counting a body for a list that never wrote it.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID timeout 300 node --test evals/controller/tests/sessions.test.mjs`
Expected: FAIL — 8 pass, 1 fail: "planSlugs counts a script run, not another command reading its path" (actual `[ '2026-10-18-zeta' ]`, expected `[]`, from the `cat` session).

Run: `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID timeout 300 node --test evals/controller/tests/transcript.test.mjs`
Expected: FAIL — 12 pass, 1 fail: "a failed Bash call counts the ledger lines of each list that wrote them, not of one behind an &&" (actual `[ '1', '2', '4', '5', '6', '7' ]`, expected `[ '1', '3', '4', '5', '6', '7' ]`).

- [ ] **Step 3: Require a run of the script in planSlugs**

In `evals/controller/lib/sessions.mjs`, find:

```js
// The script is run by a path (scripts/task-brief, $S/task-brief), so the
// required slash keeps a search for the bare name (rg task-brief …) from
// counting as running it, and the optional quote admits a quoted script path.
const PER_TASK = /\/(?:task-brief|review-route|review-package)['"]?[ \t]+(['"]?[^\s;&|]+)/g;
const ASSIGN = /\b([A-Za-z_]\w*)=(['"]?)([^\s'";&|]+)\2/g;

function planArgs(cmd) {
  const vars = Object.fromEntries([...cmd.matchAll(ASSIGN)].map(m => [m[1], m[3]]));
  return [...cmd.matchAll(PER_TASK)].flatMap(m => {
    const arg = m[1].replace(/^['"]|['"]$/g, '').replace(/^\$\{?(\w+)\}?$/, (_, name) => vars[name] ?? '');
    return arg.endsWith('.md') ? [basename(arg, '.md')] : [];
  });
}
```

Replace it with:

```js
// The script is run by a path (scripts/task-brief, $S/task-brief), so the
// required slash keeps a search for the bare name (rg task-brief …) from
// counting as running it. The path must also be a command's first word once
// the words that may precede a command are skipped (BEFORE_COMMAND, an
// assignment, an option, a timeout's duration), so a command that only reads
// the script (cat $S/task-brief …) or quotes a run (echo 'bash …/task-brief …')
// is not a run. A run inside a quoted string (bash -c '…/task-brief x.md') is
// one word too, so it is not counted either.
const SCRIPT = /\/(?:task-brief|review-route|review-package)$/;
const BEFORE_COMMAND = new Set(['!', '{', 'if', 'then', 'elif', 'else', 'while', 'until', 'do', 'bash', 'sh', 'command', 'env', 'exec', 'nohup', 'time', 'timeout']);
const OPTION_VALUE = new Set(['-u', '-k', '-s']);
const ASSIGN = /\b([A-Za-z_]\w*)=(['"]?)([^\s'";&|]+)\2/g;

// simpleCommands CMD — CMD cut at `;`, `&`, `|`, `(`, `)`, a backtick and a
// newline outside quotes, each piece as its words with the quotes removed, so
// a quoted string is one word and never a command.
function simpleCommands(cmd) {
  const commands = [[]];
  let word = null;
  let quote = '';
  const end = () => {
    if (word !== null) commands.at(-1).push(word);
    word = null;
  };
  for (const c of cmd) {
    if (quote) {
      if (c === quote) quote = '';
      else word += c;
    } else if (c === "'" || c === '"') {
      quote = c;
      word ??= '';
    } else if (c === ' ' || c === '\t') end();
    else if (/[;&|()`\n]/.test(c)) {
      end();
      commands.push([]);
    } else word = (word ?? '') + c;
  }
  end();
  return commands;
}

function planArgs(cmd) {
  const vars = Object.fromEntries([...cmd.matchAll(ASSIGN)].map(m => [m[1], m[3]]));
  return simpleCommands(cmd).flatMap(words => {
    let i = 0;
    while (i < words.length && !SCRIPT.test(words[i]) && (BEFORE_COMMAND.has(words[i]) || /^(?:[A-Za-z_]\w*=|-|\d)/.test(words[i]))) i += OPTION_VALUE.has(words[i]) ? 2 : 1;
    if (!SCRIPT.test(words[i] ?? '')) return [];
    const arg = (words[i + 1] ?? '').replace(/^\$\{?(\w+)\}?$/, (_, name) => vars[name] ?? '');
    return arg.endsWith('.md') ? [basename(arg, '.md')] : [];
  });
}
```

`ASSIGN` and the plan-variable lookup are as before; `PER_TASK` is gone, and nothing else in the file uses it.

- [ ] **Step 4: Count a failed call's ledger lines list by list**

In `evals/controller/lib/transcript.mjs`, find:

```js
// The text a tool call writes into a ledger (progress.md), or ''.
function ledgerText(use) {
```

Replace it with:

```js
// shellLists CMD — CMD cut at its list separators outside quotes: `;`, a
// newline, and an `&` that is not part of `&&` or a redirect (`2>&1`, `&>`).
// A heredoc's body, on the lines after its opener, is appended to the list
// that opened it, even when more lists follow the opener on its line. The
// delimiter is the whole word after << or <<-, quoted ('END-OF-DOC') or not.
function shellLists(cmd) {
  const lists = [];
  const bodies = [];
  const pending = [];
  let start = 0;
  let quote = '';
  for (let i = 0; i < cmd.length; i++) {
    const c = cmd[i];
    if (quote) {
      if (c === quote) quote = '';
      else if (c === '\\' && quote === '"') i++;
    } else if (c === "'" || c === '"') quote = c;
    else if (c === '\\') i++;
    else if (cmd.startsWith('<<', i)) {
      const opener = /^<<-?[ \t]*(?:'([^'\n]*)'|"([^"\n]*)"|([^\s;&|<>()'"]+))/.exec(cmd.slice(i));
      if (opener) pending.push({ list: lists.length, word: opener[1] ?? opener[2] ?? opener[3] });
      i += opener ? opener[0].length - 1 : 1;
    } else if (c === '\n' || c === ';' || (c === '&' && !/[&<>|]/.test(cmd[i - 1] ?? '') && !/[&>]/.test(cmd[i + 1] ?? ''))) {
      lists.push(cmd.slice(start, i));
      if (c === '\n') {
        for (const { list, word } of pending.splice(0)) {
          const quoted = word.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
          const end = new RegExp(`\\n[ \\t]*${quoted}[ \\t]*(?=\\n|$)`).exec(cmd.slice(i));
          const stop = end ? i + end.index + end[0].length : cmd.length;
          bodies[list] = (bodies[list] ?? '') + cmd.slice(i, stop);
          i = stop;
        }
      }
      start = i + 1;
    }
  }
  lists.push(cmd.slice(start));
  return lists.map((list, n) => list + (bodies[n] ?? ''));
}

// ledgerWrites CMD — the lists of a failed Bash command that still wrote the
// ledger: the call's error is only its last command's exit status, so a list
// wrote unless an `&&` ahead of its redirect let an earlier failure skip it.
function ledgerWrites(cmd) {
  return shellLists(cmd).filter(list => {
    const at = list.search(WRITES_LEDGER);
    return at !== -1 && !/&&/.test(list.slice(0, at));
  }).join('\n');
}

// The text a tool call writes into a ledger (progress.md), or ''.
function ledgerText(use) {
```

In `evals/controller/lib/transcript.mjs`, find:

```js
    // A write that failed (an Edit whose old string was not found) recorded
    // nothing. A Bash call's error is its last command's exit status, so a
    // ledger line it appended before a failing command was still written,
    // unless an `&&` ahead of the redirect let an earlier failure skip it.
    if (!failed.has(use.id) || (use.name === 'Bash' && !/&&/.test(cmd.slice(0, Math.max(0, cmd.search(WRITES_LEDGER)))))) for (const hit of ledgerText(use).matchAll(COMPLETE)) completed.push(hit[1]);
```

Replace it with:

```js
    // A write that failed (an Edit whose old string was not found) recorded
    // nothing; a failed Bash call recorded what its lists wrote (ledgerWrites).
    const written = !failed.has(use.id) ? ledgerText(use) : use.name === 'Bash' && ledgerText(use) !== '' ? ledgerWrites(cmd) : '';
    for (const hit of written.matchAll(COMPLETE)) completed.push(hit[1]);
```

`ledgerText(use) !== ''` keeps today's whole-command gate (the command names `progress.md` and has a ledger redirect), so a list that redirects into a variable set in another list (`L=…/progress.md; echo … >> $L; false`) still counts.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID timeout 300 node --test evals/controller/tests/sessions.test.mjs`
Expected: PASS — 9 pass, 0 fail.

Run: `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID timeout 300 node --test evals/controller/tests/transcript.test.mjs`
Expected: PASS — 13 pass, 0 fail.

The other controller suites import these modules and must still pass:
Run: `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID timeout 300 node --test evals/controller/tests/decide.test.mjs evals/controller/tests/pilot.test.mjs`
Expected: PASS (5 and 5 pass, 0 fail).

- [ ] **Step 6: Commit**

```bash
git add evals/controller/lib/sessions.mjs evals/controller/tests/sessions.test.mjs
git commit -m "fix(evals): count a task script only when run"
git add evals/controller/lib/transcript.mjs evals/controller/tests/transcript.test.mjs
git commit -m "fix(evals): count ledger writes per shell list"
```

---

### Task 7: Run tsc through cmd.exe on Windows and fix test docs

Three small repository-tooling fixes. DF 21: on Windows npm installs `tsc` as `tsc.cmd`, and `scripts/test-all.mjs` probes and runs it with a shell-free `spawnSync('tsc', …)` / `spawn('tsc', …)`. Node refuses to spawn a `.cmd` file without a shell (`EINVAL` since the April 2024 security releases), so the probe fails and the tsc job is skipped with the misleading reason "tsc is not on PATH". On `win32` the probe and the job now go through `process.env.ComSpec ?? 'cmd.exe'` with `/d /s /c tsc …`; `run` needs no new option, and the skip reason reads "tsc not found". On Linux the executable stays `tsc` with no prefix, so `--list` output is unchanged.

DF 23.b: commit 03765c6 removed one line of `tests/marketplace-smoke.ps1` and with it the blank line before the `git init` block; it is restored. DF 23 (adjacent): the same commit rewrote two "Verified outcomes" bullets in `docs/testing/dual-client-marketplace-validation.md` to describe the current plugins (dforge's manifest instead of Superpowers', and no dependency resolution), under a heading that dates the results to the 2026-09-08 run. Those two statements are labelled as current-state notes.

**Files:**
- Modify: `scripts/test-all.mjs`
- Modify: `tests/marketplace-smoke.ps1`
- Modify: `docs/testing/dual-client-marketplace-validation.md`

**Interfaces:**
- Consumes: None
- Produces: the skip line `Skipped tsc --noEmit -p plugins/dforge: tsc not found` (printed by `node scripts/test-all.mjs` without `--list` when the generated types exist and the tsc probe fails)

**Items:** DF 21, DF 23

**Depends on:** none
**Implementer:** dr-superpowers:impl-sonnet-low
**Evaluation:** files 1 - spec 0 - coupling 0 - risk 1 = 2

- [ ] **Step 1: Record the Linux `--list` output before the change**

No automated test can fail first: the change affects only `win32`, which this Linux host cannot run. Record the listing to prove Linux is unchanged:

Run: `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID timeout 60 node scripts/test-all.mjs --list > "$(timeout 60 git rev-parse --git-dir)/test-all-list-before.txt"`
Expected: exit 0 (the file sits in the worktree's git directory, outside the tracked tree). If `tsc` is on `PATH` and the generated types exist, the last line is `--noEmit -p plugins/dforge`; on a host without `tsc` (this one) that line is absent.

- [ ] **Step 2: Run tsc through cmd.exe on Windows**

In `scripts/test-all.mjs`, find:

```js
// Detected under --list too, so a listing shows the job that a run would start.
const hasTsc = typesGenerated && spawnSync('tsc', ['--version'], { stdio: 'ignore', timeout: 10000 }).status === 0;
```

Replace it with:

```js
// npm installs tsc on Windows as tsc.cmd, which Node spawns only through a
// shell (EINVAL without one since the April 2024 security releases), so there
// both the probe and the job run it through cmd.exe.
const [tscExecutable, tscPrefix] = process.platform === 'win32' ? [process.env.ComSpec ?? 'cmd.exe', ['/d', '/s', '/c', 'tsc']] : ['tsc', []];
// Detected under --list too, so a listing shows the job that a run would start.
const hasTsc = typesGenerated && spawnSync(tscExecutable, [...tscPrefix, '--version'], { stdio: 'ignore', timeout: 10000, windowsHide: true }).status === 0;
```

In `scripts/test-all.mjs`, find:

```js
  ...(hasTsc ? [['tsc', ['--noEmit', '-p', 'plugins/dforge'], 300]] : []),
```

Replace it with:

```js
  ...(hasTsc ? [[tscExecutable, [...tscPrefix, '--noEmit', '-p', 'plugins/dforge'], 300]] : []),
```

In `scripts/test-all.mjs`, find:

```js
  console.log(`Skipped tsc --noEmit -p plugins/dforge: ${typesGenerated ? 'tsc is not on PATH' : 'the generated types are missing (Claude Code writes them when it loads plugins/dforge from the folder)'}`);
```

Replace it with:

```js
  console.log(`Skipped tsc --noEmit -p plugins/dforge: ${typesGenerated ? 'tsc not found' : 'the generated types are missing (Claude Code writes them when it loads plugins/dforge from the folder)'}`);
```

- [ ] **Step 3: Check Linux is unchanged**

Run: `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID timeout 60 node scripts/test-all.mjs --list | timeout 60 cmp - "$(timeout 60 git rev-parse --git-dir)/test-all-list-before.txt" && echo unchanged; rm -f "$(timeout 60 git rev-parse --git-dir)/test-all-list-before.txt"`
Expected: `unchanged`.

Run, to see the tsc row still listed on Linux, with a stand-in `tsc` on `PATH` (the generated types exist in a checkout where Claude Code has loaded `plugins/dforge`; if `plugins/dforge/tsconfig.json` or `plugins/dforge/.claude-plugin/types/tsconfig.json` is missing, skip this command and say so):
`D=$(mktemp -d); printf '#!/bin/sh\nexit 0\n' > "$D/tsc"; chmod +x "$D/tsc"; env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID PATH="$D:$PATH" timeout 60 node scripts/test-all.mjs --list | tail -n 1; rm -rf "$D"`
Expected: `--noEmit -p plugins/dforge`.

Run, to see the new skip reason without starting the suites (an out-of-range shard makes `selectShard` throw after the skip line prints):
`env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID timeout 60 node scripts/test-all.mjs --shard 999/1000 2>&1 | head -n 1`
Expected, with the generated types present and no `tsc` on `PATH`: `Skipped tsc --noEmit -p plugins/dforge: tsc not found`. Without the generated types the line names them instead.

The Windows behaviour (the probe and job running `tsc.cmd` through `cmd.exe`, and the job listed as `/d /s /c tsc --noEmit -p plugins/dforge`) is **unverified** on this host; report it so.

Run: `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID timeout 300 node --test tests/test-shards.test.mjs`
Expected: PASS.

- [ ] **Step 4: Commit the tsc change**

```bash
git add scripts/test-all.mjs
git commit -m "fix(test-all): run tsc through cmd.exe on Windows"
```

- [ ] **Step 5: Restore the smoke script's blank line**

In `tests/marketplace-smoke.ps1`, find:

```powershell
  Check ($ownEntries.Count -eq 4) 'Claude installs four repository plugins'
  Invoke-Client git @('-C',$market,'init','-q','-b','main') | Out-Null
```

Replace it with:

```powershell
  Check ($ownEntries.Count -eq 4) 'Claude installs four repository plugins'

  Invoke-Client git @('-C',$market,'init','-q','-b','main') | Out-Null
```

The file is LF-only ASCII with no byte-order mark; keep it so.

- [ ] **Step 6: Label the rewritten bullets as current-state notes**

`timeout 60 git show 03765c6 -- docs/testing/dual-client-marketplace-validation.md` shows the two bullets it rewrote: the second sentence of "All three Codex plugins install …" (was "Superpowers' native manifest explicitly contains `"hooks": {}`.") and "Claude installs all four repository plugins." (was "… and resolves the declared `superpowers@claude-plugins-official` dependency …").

In `docs/testing/dual-client-marketplace-validation.md`, find:

```markdown
- All three Codex plugins install; installed native manifest bytes match source.
  dforge's native manifest explicitly contains `"hooks": {}`.
- Claude installs all four repository plugins.
```

Replace it with:

```markdown
- All three Codex plugins install; installed native manifest bytes match source.
  Current-state note, not a result of the 2026-09-08 run: dforge's native
  manifest explicitly contains `"hooks": {}`.
- Current-state note, not a result of the 2026-09-08 run: Claude installs all
  four repository plugins.
```

- [ ] **Step 7: Check the docs**

Run: `timeout 60 git diff -- tests/marketplace-smoke.ps1`
Expected: one added empty line after `Check ($ownEntries.Count -eq 4) 'Claude installs four repository plugins'`, nothing else.

Run: `timeout 60 grep -c 'Current-state note, not a result of the 2026-09-08 run' docs/testing/dual-client-marketplace-validation.md`
Expected: `2`.

Run: `timeout 120 node scripts/validate-repository.mjs`
Expected: PASS — `Repository catalogs, manifests, versions, bundled links and the settings schema are valid.`

Run: `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID timeout 300 node --test tests/*.test.mjs`
Expected: PASS (42 tests, 41 pass, 1 skipped, 0 fail: Task 2 adds two subtests, and the Win32 discovery test skips without rg).

- [ ] **Step 8: Commit the docs**

```bash
git add tests/marketplace-smoke.ps1
git commit -m "style(smoke): restore a blank line"
git add docs/testing/dual-client-marketplace-validation.md
git commit -m "docs(testing): label current-state notes"
```

---

### Task 8: Stop a run whose sync state cannot be saved

**Files:**
- Modify: `plugins/dforge/scripts/lib/darkmem-sync.mjs`
- Test: `plugins/dforge/tests/darkmem-sync/pull.test.mjs`
- Test: `plugins/dforge/tests/darkmem-sync/reconcile.test.mjs`
- Test: `plugins/dforge/tests/darkmem-sync/cli.test.mjs`

**Interfaces:**
- Consumes: None
- Produces: `persist()` in `main` (`darkmem-sync.mjs`) throws a `StateError` (from `darkmem-mirror.mjs`, no `syscall` property) whose message is `<statePath> could not be saved (<code>); the run stopped, and the next run checks what this one wrote`; `main` prints it on stderr as `darkmem-sync: <message>` and exits 2. A failed save in `main`'s `finally` prints the same line and turns exit 0 into 2.

**Items:** DM 53, DM 60

**Depends on:** none
**Implementer:** dr-superpowers:impl-sonnet-high
**Evaluation:** files 1 - spec 0 - coupling 2 - risk 2 = 5

Today `main` hands every command `persist = () => saveState(cfg.statePath, state)`. When the state file cannot be written (here: it was turned into a directory mid-run), the raw `EISDIR` error carries a `syscall`, so `pullDocuments`' per-item catch reports a document it has just written as "could not be read or written … not pulled", and every later item fails the same way. In reconcile the error escapes the move as an unexpected error. Either way `main`'s `finally` then calls `saveState` again, which throws once more and turns the run into `darkmem-sync: unexpected error` with exit 4. After this task, `persist` wraps a failed save in a `StateError` naming the state file. `main`'s existing catch already maps a `StateError` to one stderr line and exit 2. The `finally` skips its own save once `persist` has failed, and guards that save otherwise. The lock is still released and the report lines gathered so far still print. `saveState` itself and the `StateError` export of `darkmem-mirror.mjs` are unchanged, since `dforge-home-migrate.mjs` uses both directly.

- [ ] **Step 1: Write the failing tests**

The tests prove three things. A pull whose state file becomes a directory after the first document fetch exits 2 with one line naming the state file, prints the conflict line it gathered before, prints no "not pulled" line, and leaves the lock released. A reconcile whose state file becomes a directory at its final manifest read (the last request before the set-aside rename and the save after it) exits 2 the same way. A `status` run whose closing save fails exits 2 with that line instead of crashing (this is the existing lock-release test, which pins today's exit 4).

In `plugins/dforge/tests/darkmem-sync/pull.test.mjs`, append the following at the end of the file, after the last test (the one named `a workstream list whose last page is exactly full ends without an empty page`):

```js

test("a sync state that cannot be saved stops the pull: exit 2, one line, and the lines gathered before it", async t => {
  const s = await setup(t);
  assert.equal((await s.pull()).code, 0);
  for (const uri of ["dforge/T.md", "dforge/t.md", "dforge/a.md", "dforge/b.md"]) {
    await s.seed.putDocument({ project: "proj", uri, content: `${uri}\n` });
  }
  const stateFile = path.join(s.mirror, ".sync-state.json");
  // The first document fetch turns the state file into a directory, so the
  // save after a.md is written fails.
  s.stub.db.onRequest = (method, pathname) => {
    if (method !== "GET" || pathname !== "/api/v1/documents/by-uri" || fs.statSync(stateFile).isDirectory()) return;
    fs.rmSync(stateFile);
    fs.mkdirSync(stateFile);
  };
  const result = await s.pull();
  assert.equal(result.code, 2, result.stdout + result.stderr);
  assert.equal(
    result.stderr.replace(/ could not be saved \(\w+\);/, " could not be saved (CODE);"),
    `darkmem-sync: ${stateFile} could not be saved (CODE); the run stopped, and the next run checks what this one wrote\n`,
  );
  assert.match(result.stdout, /^conflict: dforge\/T\.md, dforge\/t\.md: differ only in case/m);
  assert.doesNotMatch(result.stdout, /not pulled/);
  assert.doesNotMatch(result.stdout, /^darkmem-sync pull:/m);
  assert.equal(read(path.join(s.docsRoot, "a.md")), "dforge/a.md\n");
  assert.equal(fs.existsSync(path.join(s.docsRoot, "b.md")), false, "the pull stopped at the failed save");
  assert.equal(fs.existsSync(path.join(s.mirror, ".sync.lock")), false, "the lock is released");
});
```

In `plugins/dforge/tests/darkmem-sync/reconcile.test.mjs`, append the following at the end of the file, after the last test (the one named `a mirror copy that cannot be set aside refuses the move, keeps the sync state, and a rerun finishes it`):

```js

test("a sync state that cannot be saved after the set-aside stops reconcile with exit 2 and one line", async t => {
  const s = await darkmemDocs(t);
  assert.equal((await s.pull()).code, 0);
  const stateFile = path.join(s.mirror, ".sync-state.json");
  // Reconcile reads the manifest three times: its probe, the pull into the
  // mirror, and the check before anything is copied, which is the last request
  // before the set-aside rename and the save after it.
  let manifests = 0;
  s.stub.db.onRequest = (method, pathname) => {
    if (method !== "GET" || pathname !== "/api/v1/documents/manifest" || ++manifests !== 3) return;
    fs.rmSync(stateFile);
    fs.mkdirSync(stateFile);
  };
  const result = await s.reconcile();
  assert.equal(result.code, 2, result.stdout + result.stderr);
  assert.equal(manifests, 3);
  assert.equal(
    result.stderr.replace(/ could not be saved \(\w+\);/, " could not be saved (CODE);"),
    `darkmem-sync: ${stateFile} could not be saved (CODE); the run stopped, and the next run checks what this one wrote\n`,
  );
  assert.doesNotMatch(result.stdout, /moved to local/);
  assert.equal(read(path.join(s.repo, "docs", "dforge", "specs", "a.md")), "# A\n");
  assert.equal(fs.existsSync(s.docsRoot), false, "the mirror copy was set aside before the save");
  assert.equal(fs.existsSync(path.join(s.mirror, ".sync.lock")), false, "the lock is released");
  assert.deepEqual(s.stores(), { documents: "darkmem", progress: "local" });
});
```

In `plugins/dforge/tests/darkmem-sync/cli.test.mjs`, in the test `the lock is released even when the state file cannot be saved`, replace:

```js
  const failed = await run(["status"], { cwd: repo, env });
  assert.equal(failed.code, 4);
  assert.match(failed.stderr, /unexpected error/);
```

with:

```js
  const failed = await run(["status"], { cwd: repo, env });
  assert.equal(failed.code, 2, failed.stdout + failed.stderr);
  assert.equal(
    failed.stderr.replace(/ could not be saved \(\w+\);/, " could not be saved (CODE);"),
    `darkmem-sync: ${path.join(mirror, ".sync-state.json")} could not be saved (CODE); the run stopped, and the next run checks what this one wrote\n`,
  );
```

(The error code is normalised because a rename onto a directory is `EISDIR` on Linux and macOS but may differ on the Windows CI job.)

- [ ] **Step 2: Run the tests to verify they fail**

Run: `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID timeout 300 node --test plugins/dforge/tests/darkmem-sync/pull.test.mjs plugins/dforge/tests/darkmem-sync/reconcile.test.mjs plugins/dforge/tests/darkmem-sync/cli.test.mjs`

Expected: FAIL, three tests:
- The new pull test and the new reconcile test: `4 !== 2`, with `darkmem-sync: unexpected error: Error: EISDIR: illegal operation on a directory, rename '…/..sync-state.json.tmp' -> '…/.sync-state.json'` on stderr.
- `the lock is released even when the state file cannot be saved`: `4 !== 2`.

Every other test passes.

- [ ] **Step 3: Implement**

In `plugins/dforge/scripts/lib/darkmem-sync.mjs`, insert the following immediately before the line `// The Stop hook's push runs in the background, so a skill's push at a stop`:

```js
// A sync state that cannot be saved stops the run; what the run wrote stays
// for the next run to find.
const unsaved = (file, error) => `${file} could not be saved (${error.code ?? error.message}); the run stopped, and the next run checks what this one wrote`;

```

In the same file, in `main`, replace:

```js
  let state = null;
  let code = 0;
  try {
    state = loadState(cfg.statePath);
    const persist = () => saveState(cfg.statePath, state);
```

with:

```js
  let state = null;
  let code = 0;
  let unsavable = false;
  try {
    state = loadState(cfg.statePath);
    // A StateError has no syscall, so no command's per-item catch of a file
    // error reads a failed save as its item's failure.
    const persist = () => {
      try {
        saveState(cfg.statePath, state);
      } catch (error) {
        unsavable = true;
        throw new StateError(unsaved(cfg.statePath, error));
      }
    };
```

Then, in the `finally` of the same function, replace:

```js
      if (state) {
        // A completed run replaces the recorded conflicts; a run that stopped
        // part-way, or failed an item or phase darkmem answered with an error,
        // adds what it found, since it never re-checked the rest.
        if (parsed.command.recordsConflicts) {
          state.conflicts = code === 0 && !report.partial ? report.conflicts : [...new Set([...state.conflicts, ...report.conflicts])];
        }
        saveState(cfg.statePath, state);
      }
```

with:

```js
      if (state && !unsavable) {
        // A completed run replaces the recorded conflicts; a run that stopped
        // part-way, or failed an item or phase darkmem answered with an error,
        // adds what it found, since it never re-checked the rest.
        if (parsed.command.recordsConflicts) {
          state.conflicts = code === 0 && !report.partial ? report.conflicts : [...new Set([...state.conflicts, ...report.conflicts])];
        }
        try {
          saveState(cfg.statePath, state);
        } catch (error) {
          err(`darkmem-sync: ${unsaved(cfg.statePath, error)}`);
          if (code === 0) code = 2;
        }
      }
```

Leave `saveState` in `darkmem-mirror.mjs`, the `StateError` export and the catch above the `finally` (which already prints a `StateError` as `darkmem-sync: <message>` and sets `code = 2`) as they are. No other file changes. Every catch a failed `persist()` passes through already rethrows an error without `syscall` that is not darkmem's HTTP answer: `pullDocuments` (via `failItem`), push's `failItem` calls, reconcile's move catch, `progressToLocal`'s `darkmemRefusal`.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID timeout 300 node --test plugins/dforge/tests/darkmem-sync/pull.test.mjs plugins/dforge/tests/darkmem-sync/reconcile.test.mjs plugins/dforge/tests/darkmem-sync/cli.test.mjs`

Expected: PASS

Then run every darkmem-sync suite, `migrate.test.mjs` included, since every command goes through `main`:

Run: `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID timeout 600 bash plugins/dforge/tests/darkmem-sync.test.sh`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/scripts/lib/darkmem-sync.mjs plugins/dforge/tests/darkmem-sync/pull.test.mjs plugins/dforge/tests/darkmem-sync/reconcile.test.mjs plugins/dforge/tests/darkmem-sync/cli.test.mjs
git commit -m "fix(darkmem): stop on an unsavable sync state"
```

---

### Task 9: Fail one ledger or checkpoint write, not the pull

**Files:**
- Modify: `plugins/dforge/scripts/lib/darkmem-pull.mjs`
- Modify: `plugins/dforge/scripts/lib/darkmem-progress-move.mjs`
- Test: `plugins/dforge/tests/darkmem-sync/pull.test.mjs`
- Test: `plugins/dforge/tests/darkmem-sync/reconcile-progress.test.mjs`

**Interfaces:**
- Consumes: Task 8's `persist()`, which throws a `StateError` with no `syscall` and the message `<statePath> could not be saved (<code>); the run stopped, and the next run checks what this one wrote`
- Produces: failure lines `sdd/<key>/progress.md: the local ledger could not be read or written (<code>); not pulled` and `handoff/latest.md: could not be written (<code>); not pulled` (pull), and `handoff/latest.md: could not be written (<code>)` (`renderCheckpoint`, inside a progress move back to local)

**Items:** DM 52

**Depends on:** Task 8
**Implementer:** dr-superpowers:impl-sonnet-medium
**Evaluation:** files 2 - spec 0 - coupling 1 - risk 1 = 4

Today `pullLedgers` reads the mirror's `progress.md` and writes it outside any guard, and the writes in `pullCheckpoint` and in `progressToLocal`'s `renderCheckpoint` are unguarded too. A `progress.md` that is a directory, an `sdd/<key>` that is a file, or a `latest.md` whose atomic write cannot create its temporary file throws out of `pull()`. The run then ends as `darkmem-sync: unexpected error`, exit 4, and drops the report lines it had gathered. After this task each of those steps sits in a try/catch that adds one "failed:" line and sets `report.partial`, as `pullDocuments` does. The catch tells a file-system error (it has `syscall`) from anything else, so Task 8's `StateError` and real bugs still propagate. The existing read guards in `pullCheckpoint` and `renderCheckpoint` stay as they are. `darkmemRefusal` in `darkmem-progress-move.mjs` is unchanged: file-system errors no longer reach it.

- [ ] **Step 1: Write the failing tests**

The tests prove four things:
- A ledger whose mirror copy is a directory, or sits under a file, is one failure. The documents (with their conflict line), the other workstream's ledger and the checkpoint still land, and the summary prints.
- A `latest.md` that cannot be written is one failure of a pull, and nothing records the checkpoint.
- A state save that fails after a ledger is written still stops the pull with Task 8's exit 2 and line, with no "failed:" line. This guards the rethrow, so it already passes after Task 8.
- In a progress move back to local, a mirror `latest.md` that cannot be written refuses the move with a "failed:" detail instead of crashing.

In `plugins/dforge/tests/darkmem-sync/pull.test.mjs`, insert the following immediately before the line `test("a document that cannot be read is one failure, and the others are still pulled", async t => {`:

```js
for (const [name, block] of [
  ["is a directory", file => fs.mkdirSync(file, { recursive: true })],
  ["sits under a file", file => write(path.dirname(file), "not a directory\n")],
]) {
  test(`a ledger whose local copy ${name} is one failure, and the documents, other ledgers and checkpoint still land`, async t => {
    const s = await setup(t);
    await s.seed.putDocument({ project: "proj", uri: "dforge/T.md", content: "T\n" });
    await s.seed.putDocument({ project: "proj", uri: "dforge/t.md", content: "t\n" });
    await s.seed.putDocument({ project: "proj", uri: "dforge/a.md", content: "a\n" });
    await s.seed.append({ project: "proj", workstream: "k", entries: [{ kind: "ledger", body: "k\n" }] });
    await s.seed.append({ project: "proj", workstream: "m", entries: [{ kind: "ledger", body: "m\n" }, { kind: "checkpoint", body: "# m\n" }] });
    block(path.join(s.workRoot, "sdd", "k", "progress.md"));
    const result = await s.pull();
    assert.equal(result.code, 1, result.stdout + result.stderr);
    assert.doesNotMatch(result.stderr, /unexpected error/);
    assert.match(result.stdout, /^conflict: dforge\/T\.md, dforge\/t\.md: differ only in case/m);
    assert.match(result.stdout, /^failed: sdd\/k\/progress\.md: the local ledger could not be read or written \(\w+\); not pulled$/m);
    assert.equal((result.stdout.match(/^failed:/gm) ?? []).length, 1);
    assert.match(result.stdout, /darkmem-sync pull: 1 documents, 1 ledgers, 1 checkpoints; 1 conflicts, 1 failures/);
    assert.equal(read(path.join(s.docsRoot, "a.md")), "a\n");
    assert.equal(read(path.join(s.workRoot, "sdd", "m", "progress.md")), "m\n");
    assert.equal(read(path.join(s.workRoot, "handoff", "latest.md")), "# m\n");
    assert.equal(s.state().ledgers.k, undefined);
  });
}

test("a latest.md that cannot be written is one failure, and the rest of the pull still lands", async t => {
  const s = await setup(t);
  await s.seed.putDocument({ project: "proj", uri: "dforge/a.md", content: "a\n" });
  await s.seed.append({ project: "proj", workstream: "p1", entries: [{ kind: "ledger", body: "one\n" }, { kind: "checkpoint", body: "# p1\n" }] });
  // The atomic write's temporary file cannot be made where a directory stands.
  fs.mkdirSync(path.join(s.workRoot, "handoff", ".latest.md.tmp"), { recursive: true });
  const result = await s.pull();
  assert.equal(result.code, 1, result.stdout + result.stderr);
  assert.doesNotMatch(result.stderr, /unexpected error/);
  assert.match(result.stdout, /^failed: handoff\/latest\.md: could not be written \(\w+\); not pulled$/m);
  assert.equal((result.stdout.match(/^failed:/gm) ?? []).length, 1);
  assert.match(result.stdout, /darkmem-sync pull: 1 documents, 1 ledgers, 0 checkpoints; 0 conflicts, 1 failures/);
  assert.equal(fs.existsSync(path.join(s.workRoot, "handoff", "latest.md")), false);
  assert.equal(s.state().checkpoint, null);
});

test("a sync state that cannot be saved after a ledger is written still stops the pull with exit 2", async t => {
  const s = await setup(t);
  assert.equal((await s.pull()).code, 0);
  await s.seed.append({ project: "proj", workstream: "p1", entries: [{ kind: "ledger", body: "one\n" }] });
  const stateFile = path.join(s.mirror, ".sync-state.json");
  s.stub.db.onRequest = (method, pathname) => {
    if (method !== "GET" || !pathname.endsWith("/entries") || fs.statSync(stateFile).isDirectory()) return;
    fs.rmSync(stateFile);
    fs.mkdirSync(stateFile);
  };
  const result = await s.pull();
  assert.equal(result.code, 2, result.stdout + result.stderr);
  assert.equal(
    result.stderr.replace(/ could not be saved \(\w+\);/, " could not be saved (CODE);"),
    `darkmem-sync: ${stateFile} could not be saved (CODE); the run stopped, and the next run checks what this one wrote\n`,
  );
  assert.doesNotMatch(result.stdout, /^failed:/m);
  assert.equal(read(path.join(s.workRoot, "sdd", "p1", "progress.md")), "one\n");
});

```

In `plugins/dforge/tests/darkmem-sync/reconcile-progress.test.mjs`, insert the following immediately before the line `test("a symbolic link among the mirror's progress keeps progress in darkmem, and nothing is read through it", { skip: process.platform === "win32" }, async t => {`:

```js
test("a mirror latest.md that cannot be written keeps progress in darkmem, not a crash", async t => {
  const s = await setup(t, "local");
  await s.seed.append({ project: "proj", workstream: "p1", entries: [{ kind: "ledger", body: LEDGER("p1") }, { kind: "checkpoint", body: LATEST }] });
  // The atomic write's temporary file cannot be made where a directory stands.
  fs.mkdirSync(path.join(s.workRoot, "handoff", ".latest.md.tmp"), { recursive: true });
  const result = await s.reconcile();
  assert.equal(result.code, 1, result.stdout + result.stderr);
  assert.doesNotMatch(result.stderr, /unexpected error/);
  assert.match(result.stdout, /^darkmem-sync reconcile: progress stay darkmem \(configured local\): the pull into the mirror did not finish cleanly$/m);
  assert.match(result.stdout, /^ {2}failed: handoff\/latest\.md: could not be written \(\w+\)$/m);
  assert.equal(fs.existsSync(path.join(s.repo, ".dforge", "handoff", "latest.md")), false);
  assert.equal(s.stores().progress, "darkmem");
});

```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID timeout 300 node --test plugins/dforge/tests/darkmem-sync/pull.test.mjs plugins/dforge/tests/darkmem-sync/reconcile-progress.test.mjs`

Expected: FAIL, four tests, each `4 !== 1` with `darkmem-sync: unexpected error:` on stderr:
- `… local copy is a directory …`: `EISDIR: illegal operation on a directory, read`.
- `… local copy sits under a file …`: `EEXIST: file already exists, mkdir '…/work/sdd/k'`.
- `a latest.md that cannot be written …`: `EISDIR: illegal operation on a directory, open '…/work/handoff/.latest.md.tmp'`.
- `a mirror latest.md that cannot be written …`: the same `EISDIR` on `.latest.md.tmp`.

`a sync state that cannot be saved after a ledger is written still stops the pull with exit 2` passes already: it guards the rethrow added in Step 3.

- [ ] **Step 3: Implement**

In `plugins/dforge/scripts/lib/darkmem-pull.mjs`, in `pullLedgers`, replace:

```js
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
```

with:

```js
    const file = path.join(roots.workRoot, "sdd", ws.key, "progress.md");
    try {
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
    } catch (error) {
      // persist's StateError, or a bug, is not this ledger's failure.
      if (!error?.syscall) throw error;
      report.failures.push(`sdd/${ws.key}/progress.md: the local ledger could not be read or written (${error.code}); not pulled`);
      report.partial = true;
    }
  }
}
```

In the same file, at the end of `pullCheckpoint`, replace:

```js
  if (local !== remoteHash) {
    writeFileAtomic(file, remote);
    report.counts.checkpoints += 1;
  }
  state.checkpoint = remoteHash;
  recordCheckpointAt(state, newestKey, newest.created_at);
  persist();
}
```

with:

```js
  try {
    if (local !== remoteHash) {
      writeFileAtomic(file, remote);
      report.counts.checkpoints += 1;
    }
    state.checkpoint = remoteHash;
    recordCheckpointAt(state, newestKey, newest.created_at);
    persist();
  } catch (error) {
    if (!error?.syscall) throw error;
    report.failures.push(`handoff/latest.md: could not be written (${error.code}); not pulled`);
    report.partial = true;
  }
}
```

In `plugins/dforge/scripts/lib/darkmem-progress-move.mjs`, at the end of `renderCheckpoint`, replace:

```js
  if (current !== hash) writeFileAtomic(file, remote);
  state.checkpoint = hash;
  recordCheckpointAt(state, newest.workstream, newest.created_at);
  persist();
}
```

with:

```js
  try {
    if (current !== hash) writeFileAtomic(file, remote);
    state.checkpoint = hash;
    recordCheckpointAt(state, newest.workstream, newest.created_at);
    persist();
  } catch (error) {
    // persist's StateError, or a bug, propagates.
    if (!error?.syscall) throw error;
    report.failures.push(`handoff/latest.md: could not be written (${error.code})`);
    report.partial = true;
  }
}
```

Change nothing else in `darkmem-progress-move.mjs`: Tasks 11-14 edit other parts of it. `progressToLocal` already turns a "failed:" line in its scratch report into the refusal `the pull into the mirror did not finish cleanly`.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID timeout 300 node --test plugins/dforge/tests/darkmem-sync/pull.test.mjs plugins/dforge/tests/darkmem-sync/reconcile-progress.test.mjs`

Expected: PASS

Then run every darkmem-sync suite, `migrate.test.mjs` included:

Run: `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID timeout 600 bash plugins/dforge/tests/darkmem-sync.test.sh`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/scripts/lib/darkmem-pull.mjs plugins/dforge/scripts/lib/darkmem-progress-move.mjs plugins/dforge/tests/darkmem-sync/pull.test.mjs plugins/dforge/tests/darkmem-sync/reconcile-progress.test.mjs
git commit -m "fix(darkmem): fail one ledger or checkpoint write"
```

---

### Task 10: Fix the import diagnostic, the Stop bound text, case twins

**Files:**
- Modify: `plugins/dforge/scripts/lib/darkmem-pull.mjs`
- Modify: `plugins/dforge/README.md`
- Test: `plugins/dforge/tests/darkmem-sync/import.test.mjs`
- Test: `plugins/dforge/tests/darkmem-sync/hooks.test.mjs`
- Test: `plugins/dforge/tests/darkmem-sync/pull.test.mjs`

**Interfaces:**
- Consumes: None
- Produces: None

**Items:** DM 54, DM 55, DM 59

**Depends on:** Task 9
**Implementer:** dr-superpowers:impl-sonnet-medium
**Evaluation:** files 2 - spec 0 - coupling 0 - risk 1 = 3

This task fixes three small findings and commits each on its own:
- DM 54: `import.test.mjs`'s `a source file changed during the import fails its verification` once exited 4 instead of 1 and passed on rerun. Its exit-code assertion prints no output, so the cause was lost. It gets the command's output as its message; nothing else changes, and the row closes `n/a` (not reproduced) once this lands.
- DM 55: `README.md` says the background Stop push is "the whole run bounded at 100 seconds". The real worst case is 140 s: a 30 s config lookup and a 100 s push (`darkmem_push_quietly` in `scripts/lib/darkmem-hook.sh`), each with a 5 s kill grace. The text changes to say so; the push keeps its 100 s. `hooks.test.mjs` already pins the lookup's 30 s bound and now pins the push's 100 s beside it.
- DM 59.b: `removeVanished` in `darkmem-pull.mjs` scans every filed uri for each vanished document to find a case twin (quadratic). It now builds one map from lower-cased uri to the list of non-archive filed uris before the loop. A vanished uri is kept when any entry in its list other than itself reaches the same file, since darkmem can hold two twins of one fold.

- [ ] **Step 1: Give the import race test its output (DM 54)**

In `plugins/dforge/tests/darkmem-sync/import.test.mjs`, in the test `a source file changed during the import fails its verification`, replace:

```js
  const result = await s.importing();
  assert.equal(result.code, 1);
  assert.match(result.stdout, /failed: the source files changed during the import; run it again with --replace/);
```

with:

```js
  const result = await s.importing();
  assert.equal(result.code, 1, result.stdout + result.stderr);
  assert.match(result.stdout, /failed: the source files changed during the import; run it again with --replace/);
```

Run: `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID timeout 300 node --test plugins/dforge/tests/darkmem-sync/import.test.mjs`

Expected: PASS. Check by reading: the replaced `assert.equal` line passes `result.stdout + result.stderr` as its message.

```bash
git add plugins/dforge/tests/darkmem-sync/import.test.mjs
git commit -m "test(darkmem): print output on the import race"
```

- [ ] **Step 2: Pin the push's bound and state the Stop push's 140 s (DM 55)**

In `plugins/dforge/tests/darkmem-sync/hooks.test.mjs`, in the test `the Stop push bounds its config lookup apart from the push, which keeps its own bound`, replace:

```js
  assert.equal(calls.filter(line => / push$/.test(line) && /darkmem-sync/.test(line)).length, 1, calls.join("\n"));
  assert.match(calls.find(line => /dforge_project/.test(line)) ?? "", /^-k \d+ 30 bash -c /);
```

with:

```js
  assert.equal(calls.filter(line => / push$/.test(line) && /darkmem-sync/.test(line)).length, 1, calls.join("\n"));
  assert.match(calls.find(line => /dforge_project/.test(line)) ?? "", /^-k \d+ 30 bash -c /);
  assert.match(calls.find(line => / push$/.test(line) && /darkmem-sync/.test(line)) ?? "", /^-k \d+ 100 bash /);
```

Run: `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID timeout 300 node --test plugins/dforge/tests/darkmem-sync/hooks.test.mjs`

Expected: PASS. The bound is already 100 s, so this assertion adds coverage. The logged push line reads `-k 5 100 bash <plugin>/scripts/darkmem-sync push`. With `100 push` temporarily changed to `70 push` in `scripts/lib/darkmem-hook.sh`, the test fails with `actual: '-k 5 70 bash …'`. Do not commit that change.

In `plugins/dforge/README.md`, replace:

```markdown
  background Stop hook pushes as a safety net, the whole run bounded at 100
  seconds (SIGTERM, then SIGKILL after 5 seconds). `push` waits up to 100
```

with:

```markdown
  background Stop hook pushes as a safety net in at most 140 seconds: its
  config lookup is bounded at 30 seconds and its push at 100, each sent
  SIGTERM at its bound and SIGKILL 5 seconds later. `push` waits up to 100
```

Run: `timeout 120 node scripts/validate-repository.mjs`

Expected: PASS (`Repository catalogs, manifests, versions, bundled links and the settings schema are valid.`)

```bash
git add plugins/dforge/README.md plugins/dforge/tests/darkmem-sync/hooks.test.mjs
git commit -m "docs(darkmem): state the Stop push's 140 s bound"
```

- [ ] **Step 3: Write the two-twin test (DM 59.b)**

In `plugins/dforge/tests/darkmem-sync/pull.test.mjs`, insert the following immediately before the line `test("a case-only rename on darkmem that also edits it keeps the file a case-insensitive file system shares", async t => {`:

```js
test("two case-only renames on darkmem keep both files a case-insensitive file system shares", async t => {
  const s = await setup(t);
  await s.seed.putDocument({ project: "proj", uri: "dforge/a.md", content: "a\n" });
  await s.seed.putDocument({ project: "proj", uri: "dforge/b.md", content: "b\n" });
  assert.equal((await s.pull()).code, 0);
  for (const name of ["a", "b"]) {
    const id = s.stub.db.documents.get(`proj\u0000dforge/${name}.md`).id;
    await s.seed.moveDocument(id, { uri: `dforge/${name.toUpperCase()}.md` });
    // A hard link stands in for a case-insensitive file system, which already
    // reaches the file under both names.
    const twin = path.join(s.docsRoot, `${name.toUpperCase()}.md`);
    if (!fs.existsSync(twin)) fs.linkSync(path.join(s.docsRoot, `${name}.md`), twin);
  }
  const result = await s.pull();
  assert.equal(result.code, 0, result.stdout + result.stderr);
  assert.doesNotMatch(result.stdout, /removed/);
  assert.equal(read(path.join(s.docsRoot, "a.md")), "a\n");
  assert.equal(read(path.join(s.docsRoot, "b.md")), "b\n");
  assert.deepEqual(Object.keys(s.state().documents).sort(), ["dforge/A.md", "dforge/B.md"]);
});

```

Run: `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID timeout 300 node --test --test-name-pattern="case-only rename" plugins/dforge/tests/darkmem-sync/pull.test.mjs`

Expected: PASS, three tests. The change below is a complexity fix with the same answers, so this test and the existing `a case-only rename on darkmem keeps the file a case-insensitive file system shares` are the regression checks; they pass before and after.

- [ ] **Step 4: Look up case twins in one map (DM 59.b)**

In `plugins/dforge/scripts/lib/darkmem-pull.mjs`, replace:

```js
function removeVanished({ roots, state, persist, report }, filed) {
  for (const uri of Object.keys(state.documents).sort()) {
    if (filed.has(uri) || uriFamily(uri) !== "documents" || isArchiveUri(uri)) continue;
    const file = uriToLocal(roots, uri);
    if (!file) continue;
    const twin = [...filed].find(other => other !== uri && !isArchiveUri(other) && other.toLowerCase() === uri.toLowerCase());
    if (twin && sameFile(file, uriToLocal(roots, twin))) {
```

with:

```js
function removeVanished({ roots, state, persist, report }, filed) {
  // Built once: darkmem can hold two twins of one fold.
  const byFold = new Map();
  for (const uri of filed) {
    if (isArchiveUri(uri)) continue;
    const fold = uri.toLowerCase();
    if (!byFold.has(fold)) byFold.set(fold, []);
    byFold.get(fold).push(uri);
  }
  for (const uri of Object.keys(state.documents).sort()) {
    if (filed.has(uri) || uriFamily(uri) !== "documents" || isArchiveUri(uri)) continue;
    const file = uriToLocal(roots, uri);
    if (!file) continue;
    const twins = (byFold.get(uri.toLowerCase()) ?? []).filter(other => other !== uri);
    if (twins.some(twin => sameFile(file, uriToLocal(roots, twin)))) {
```

The lines after it (`      delete state.documents[uri];`, `      persist();`, `      continue;`, `    }`, and the `try` block) stay as they are.

Run: `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID timeout 300 node --test plugins/dforge/tests/darkmem-sync/pull.test.mjs`

Expected: PASS

Then run every darkmem-sync suite, `migrate.test.mjs` included:

Run: `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID timeout 600 bash plugins/dforge/tests/darkmem-sync.test.sh`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/scripts/lib/darkmem-pull.mjs plugins/dforge/tests/darkmem-sync/pull.test.mjs
git commit -m "perf(darkmem): look up case twins in one map"
```

---

### Task 11: Name what changed during a documents move

The documents move into darkmem (`documentsToDarkmem` in
`plugins/dforge/scripts/lib/darkmem-reconcile.mjs`) lists the tracked
documents again just before `git rm`. When they changed during the move, its
refusal lists only listing failures and uncarried files, never the document
that was added, removed or edited. `git status --porcelain` reports an
intent-to-add rename (`git add -N`) in the worktree column (`" R new\0old"`),
but `statusLines` and `worktreeOnlyDocuments` look for `R`/`C` in the first
column only, so they print the source path as a separate bogus entry. And
`runGit` drops `result.error`, so a git that could not be started yields an
empty reason. After this task the refusal names each uri added, removed or
changed; a rename or copy in either column is one entry; and `runGit` returns
`result.error.message` as its `stderr` when git printed nothing.

**Files:**
- Modify: `plugins/dforge/scripts/lib/darkmem-reconcile.mjs`
- Test: `plugins/dforge/tests/darkmem-sync/reconcile.test.mjs`

**Interfaces:**
- Consumes: None
- Produces: `runGit(cwd, args, input)` exported from `darkmem-reconcile.mjs`, answering `{ status, signal, stdout, stderr }` where `stderr` is git's stderr, or `result.error.message` when that is empty.

**Items:** DM 60

**Depends on:** Task 8
**Implementer:** dr-superpowers:impl-sonnet-low
**Evaluation:** files 1 - spec 0 - coupling 0 - risk 1 = 2

- [ ] **Step 1: Write the failing tests**

These tests prove that a document added, removed or changed and committed
during the move is named in the refusal (DM 60.a), that an intent-to-add
rename is one uncommitted change and one worktree entry (DM 60.b), and that
`runGit` gives a reason when git cannot be started (DM 60.d).

First make `runGit` importable, so the test file loads; the keyword alone
changes no behaviour. In `plugins/dforge/scripts/lib/darkmem-reconcile.mjs`
replace:

```js
function runGit(cwd, args, input) {
```

with:

```js
export function runGit(cwd, args, input) {
```

In `plugins/dforge/tests/darkmem-sync/reconcile.test.mjs`, replace:

```js
  NOT_A_FILE, fileHash, inProgress, inProgressReason, nameSpellings, pendingFamilies, refreshContext, stayLine,
} from "../../scripts/lib/darkmem-reconcile.mjs";
```

with:

```js
  NOT_A_FILE, fileHash, inProgress, inProgressReason, nameSpellings, pendingFamilies, refreshContext, runGit, stayLine,
} from "../../scripts/lib/darkmem-reconcile.mjs";
```

Replace the whole test `a document committed during the pull keeps the repository copy`:

```js
test("a document committed during the pull keeps the repository copy", async t => {
  let repo;
  let committed = false;
  const s = await docsRepo(t, undefined, {
    stub: {
      onRequest: request => {
        if (!repo || committed || request.path !== "/api/v1/documents/by-uri") return;
        committed = true;
        write(at(repo, "docs/dforge/specs/a.md"), "# A newer\n");
        commitAll(repo, "newer");
      },
    },
  });
  repo = s.repo;
  const result = await s.reconcile();
  assert.equal(result.code, 1, result.stdout + result.stderr);
  assert.match(result.stdout, /^darkmem-sync reconcile: documents stay local \(configured darkmem\): docs\/dforge changed during the move; the repository copy stays$/m);
  assert.equal(git(s.repo, "diff", "--cached", "--name-only"), "");
  assert.equal(read(at(s.repo, "docs/dforge/specs/a.md")), "# A newer\n");
  assert.deepEqual(s.stores(), { documents: "local", progress: "local" });
});
```

with:

```js
for (const { name, files, change, line } of [
  { name: "changed", files: { "specs/a.md": "# A\n" }, change: repo => write(at(repo, "docs/dforge/specs/a.md"), "# A newer\n"), line: "dforge/specs/a.md: changed during the move" },
  { name: "added", files: { "specs/a.md": "# A\n" }, change: repo => write(at(repo, "docs/dforge/specs/b.md"), "# B\n"), line: "dforge/specs/b.md: added during the move" },
  { name: "removed", files: { "specs/a.md": "# A\n", "specs/b.md": "# B\n" }, change: repo => fs.rmSync(at(repo, "docs/dforge/specs/b.md")), line: "dforge/specs/b.md: removed during the move" },
]) {
  test(`a document ${name} and committed during the pull keeps the repository copy and is named`, async t => {
    let repo;
    let committed = false;
    const s = await docsRepo(t, files, {
      stub: {
        onRequest: request => {
          if (!repo || committed || request.path !== "/api/v1/documents/by-uri") return;
          committed = true;
          change(repo);
          commitAll(repo, name);
        },
      },
    });
    repo = s.repo;
    const result = await s.reconcile();
    assert.equal(result.code, 1, result.stdout + result.stderr);
    assert.match(result.stdout, /^darkmem-sync reconcile: documents stay local \(configured darkmem\): docs\/dforge changed during the move; the repository copy stays$/m);
    assert.ok(result.stdout.includes(`  ${line}\n`), result.stdout);
    assert.equal(git(s.repo, "diff", "--cached", "--name-only"), "");
    assert.equal(fs.existsSync(at(s.repo, "docs/dforge/specs/a.md")), true);
    assert.deepEqual(s.stores(), { documents: "local", progress: "local" });
  });
}
```

Directly after the test `documents stay local while the docs directory has uncommitted changes`, which ends with:

```js
  assert.match(result.stdout, /^ {2}\?\? docs\/dforge\/new\.md$/m);
  assert.deepEqual(writes(s.stub), []);
});
```

insert:

```js

test("an intent-to-add rename in the docs directory is one uncommitted change", async t => {
  const s = await docsRepo(t);
  fs.renameSync(at(s.repo, "docs/dforge/specs/a.md"), at(s.repo, "docs/dforge/specs/b.md"));
  git(s.repo, "add", "-N", "docs/dforge/specs/b.md");
  const result = await s.reconcile();
  assert.equal(result.code, 1, result.stdout + result.stderr);
  assert.equal(result.stdout, [
    "darkmem-sync reconcile: documents stay local (configured darkmem): docs/dforge has uncommitted changes",
    "   R docs/dforge/specs/a.md -> docs/dforge/specs/b.md",
    "",
  ].join("\n"));
  assert.deepEqual(writes(s.stub), []);
});
```

Directly after the test `documents stay local while a linked worktree holds documents the primary checkout does not`, which ends with:

```js
  assert.ok(result.stdout.includes(`  ${tree}: docs/dforge/specs/c.md\n`), result.stdout);
  assert.deepEqual(writes(s.stub), []);
  assert.deepEqual(s.stores(), { documents: "local", progress: "local" });
});
```

insert:

```js

test("an intent-to-add rename in a linked worktree names only the new path", async t => {
  const s = await docsRepo(t);
  const tree = path.join(scratch("dms-tree-"), "wt");
  git(s.repo, "worktree", "add", "-q", "-b", "feature", tree);
  fs.renameSync(at(tree, "docs/dforge/specs/a.md"), at(tree, "docs/dforge/specs/b.md"));
  git(tree, "add", "-N", "docs/dforge/specs/b.md");
  const result = await s.reconcile();
  assert.equal(result.code, 1, result.stdout + result.stderr);
  assert.match(result.stdout, /^darkmem-sync reconcile: documents stay local \(configured darkmem\): a linked worktree holds documents the primary checkout does not; merge or remove them first$/m);
  assert.deepEqual(result.stdout.split("\n").filter(line => line.startsWith(`  ${tree}: `)), [`  ${tree}: docs/dforge/specs/b.md`]);
  assert.deepEqual(writes(s.stub), []);
});
```

Immediately before the line `test("uncommitted changes are named by their raw paths, not git's quoted ones", async t => {`, insert:

```js
// The CLI cannot reach this: without git, resolveStores answers local mode
// first, and a failing git shim exits with a status, which sets no error.
test("a git that cannot be started gives runGit a reason", t => {
  const saved = process.env.PATH;
  process.env.PATH = scratch("dms-nogit-");
  t.after(() => {
    process.env.PATH = saved;
  });
  const result = runGit(scratch("dms-cwd-"), ["status"]);
  assert.equal(result.status, null);
  assert.match(result.stderr, /\bENOENT\b/);
});

```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID timeout 300 node --test plugins/dforge/tests/darkmem-sync/reconcile.test.mjs`

Expected: FAIL in exactly these six tests, every other test passing:
- The three `a document … and committed during the pull …` rows: the refusal has no `changed during the move` / `added during the move` / `removed during the move` detail line.
- `an intent-to-add rename in the docs directory …`: stdout holds two detail lines, `   R docs/dforge/specs/b.md` and `  docs/dforge/specs/a.md`.
- `an intent-to-add rename in a linked worktree …`: an extra line `  <tree>: s/dforge/specs/a.md`.
- `a git that cannot be started gives runGit a reason`: `stderr` is `''`.

- [ ] **Step 3: Implement**

All edits are in `plugins/dforge/scripts/lib/darkmem-reconcile.mjs`.

1. `runGit`. Replace:

```js
export function runGit(cwd, args, input) {
  const result = spawnSync("git", ["-C", cwd, ...args], { encoding: "utf8", timeout: 60000, input, maxBuffer: 64 * 1024 * 1024 });
  return { status: result.status, signal: result.signal, stdout: result.stdout ?? "", stderr: result.stderr ?? "" };
}
```

with:

```js
// A git that could not be started or was timed out sets result.error and
// prints nothing, so its message stands in for the empty stderr.
export function runGit(cwd, args, input) {
  const result = spawnSync("git", ["-C", cwd, ...args], { encoding: "utf8", timeout: 60000, input, maxBuffer: 64 * 1024 * 1024 });
  return { status: result.status, signal: result.signal, stdout: result.stdout ?? "", stderr: result.stderr || result.error?.message || "" };
}
```

2. Renames in either column. Replace:

```js
// git status --porcelain -z as "XY path" lines with raw paths, which plain
// --porcelain would C-quote; a rename or copy reads "XY from -> to".
function statusLines(stdout) {
  const entries = stdout.split("\0");
  const lines = [];
  for (let i = 0; i < entries.length; i += 1) {
    const item = entries[i];
    if (item.length < 4) continue;
    if ("RC".includes(item[0])) {
```

with:

```js
// A rename or copy in either column: an intent-to-add file (git add -N) is
// detected as a rename in the worktree column, Y.
const renamed = item => "RC".includes(item[0]) || "RC".includes(item[1]);

// git status --porcelain -z as "XY path" lines with raw paths, which plain
// --porcelain would C-quote; a rename or copy reads "XY from -> to".
function statusLines(stdout) {
  const entries = stdout.split("\0");
  const lines = [];
  for (let i = 0; i < entries.length; i += 1) {
    const item = entries[i];
    if (item.length < 4) continue;
    if (renamed(item)) {
```

and in `worktreeOnlyDocuments` replace:

```js
      // A rename or copy is followed by its source path, which is no entry.
      if ("RC".includes(item[0])) i += 1;
```

with:

```js
      // A rename or copy is followed by its source path, which is no entry.
      if (renamed(item)) i += 1;
```

3. The recheck names what drifted. In `documentsToDarkmem` replace:

```js
  const again = carriedDocuments(cfg.repoRoot, docsDir, rel);
  const sent = new Map(documents.map(doc => [doc.uri, doc.hash]));
  if (again.failed || again.problems.length || again.documents.length !== sent.size || again.documents.some(doc => sent.get(doc.uri) !== doc.hash)) {
    return { moved: false, reason: `${rel} changed during the move; the repository copy stays`, details: [...(again.failed ? [again.failed] : []), ...again.problems] };
  }
```

with:

```js
  const again = carriedDocuments(cfg.repoRoot, docsDir, rel);
  const sent = new Map(documents.map(doc => [doc.uri, doc.hash]));
  const now = new Map(again.documents.map(doc => [doc.uri, doc.hash]));
  // A failed listing holds no documents, which would read as every one removed.
  const drifted = again.failed ? [] : [...new Set([...sent.keys(), ...now.keys()])].sort().flatMap(uri => {
    if (!now.has(uri)) return [`${uri}: removed during the move`];
    if (!sent.has(uri)) return [`${uri}: added during the move`];
    return sent.get(uri) === now.get(uri) ? [] : [`${uri}: changed during the move`];
  });
  if (again.failed || again.problems.length || drifted.length) {
    return { moved: false, reason: `${rel} changed during the move; the repository copy stays`, details: [...(again.failed ? [again.failed] : []), ...again.problems, ...drifted] };
  }
```

`drifted` is empty exactly when the old size-and-hash test passed, so the
refusal fires in the same cases as before.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID timeout 300 node --test plugins/dforge/tests/darkmem-sync/reconcile.test.mjs`

Expected: PASS, including the existing git-failure, citation and `a file the move cannot carry, committed during the pull` tests.

Then the whole darkmem-sync set:

Run: `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID timeout 600 bash plugins/dforge/tests/darkmem-sync.test.sh`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/scripts/lib/darkmem-reconcile.mjs plugins/dforge/tests/darkmem-sync/reconcile.test.mjs
git commit -m "fix(darkmem): name drift and renames in doc moves"
```

---

### Task 12: Read progress files without following links

The progress moves check a file with `lstat` and then read it with
`readFileSync`, so a link swapped in between the two is read through, and a
link to a named pipe (FIFO) blocks the command for good. The rechecks after
writes (`progressToDarkmem`'s comparison of every source after darkmem is
written, its read-back of the mirror copies, and `progressToLocal`'s
`readOrNull` before and after the copies) follow links outright, and
reconcile's `inProgress` reads every ledger through links. An `lstat` that
throws (`ENOTDIR`, `EACCES`) in `progressToLocal` sits outside the read's
try/catch and crashes the move. This task adds one helper, `readNoFollow`,
in `darkmem-progress-move.mjs`: it opens with
`O_RDONLY | O_NOFOLLOW | O_NONBLOCK`, refuses anything `fstat` does not show
as a regular file, then reads. `ELOOP` from the open means a symbolic link.
Where `O_NOFOLLOW` is undefined (Windows) it keeps today's lstat-then-read. It
replaces the reads in `gatherLocalProgress`, `progressToDarkmem`'s two
rechecks, `progressToLocal`'s source read and `readOrNull`, and
`inProgress`'s read, where a linked or unreadable ledger counts as in
progress. It is a `function` declaration because `darkmem-reconcile.mjs` and
`darkmem-progress-move.mjs` import each other.

**Files:**
- Modify: `plugins/dforge/scripts/lib/darkmem-progress-move.mjs`
- Modify: `plugins/dforge/scripts/lib/darkmem-reconcile.mjs`
- Test: `plugins/dforge/tests/darkmem-sync/reconcile-progress.test.mjs`

**Interfaces:**
- Consumes: None
- Produces: `export function readNoFollow(file, constants = fs.constants)` in `darkmem-progress-move.mjs`, and the mapping of its errors at every call site this task writes (`gatherLocalProgress`, `progressToLocal`'s source read, `progressToDarkmem`'s recheck and read-back, `readOrNull`, `inProgress`), both exactly as the Contracts bullet `readNoFollow` states. Task 13 relies on its `ELOOP` for a dangling link.

**Items:** DM 61

**Depends on:** Task 8
**Implementer:** dr-superpowers:impl-opus-high
**Evaluation:** files 1 - spec 0 - coupling 2 - risk 3 = 6

- [ ] **Step 1: Write the failing tests**

These tests prove that:
- The helper refuses a link, a dangling link, a link to a named pipe and a directory by code, and refuses a link that is swapped in after the check (DM 61.a).
- Without `O_NOFOLLOW` it falls back to lstat-then-read (the Windows path).
- A checkout or mirror ledger swapped for a link after its check is a problem, not read through (DM 61.a).
- A ledger, or a ledger linked to a named pipe, is "in progress" and never blocks reconcile (DM 61.j).
- `progressToDarkmem`'s recheck refuses a handoff note linked to a pipe instead of blocking (DM 61.b).
- A link landing at a checkout target before or after its copy is never read through (DM 61.b).
- A failing open or a vanished directory is a problem line, not a crash (DM 61.e).

The child-process cases block before the fix until `run()`'s 30 s timeout.
That is why no in-process test reads a pipe.

So the test file loads, first add the helper in its fallback form (today's
behaviour, used nowhere yet). In `plugins/dforge/scripts/lib/darkmem-progress-move.mjs`,
directly after the line:

```js
const local = (base, rel) => path.join(base, ...rel.split("/"));
```

insert:

```js

// `file`'s bytes, refusing a symbolic link with an ELOOP error.
export function readNoFollow(file, constants = fs.constants) {
  if (fs.lstatSync(file, { throwIfNoEntry: false })?.isSymbolicLink()) throw Object.assign(new Error(`${file} is a symbolic link`), { code: "ELOOP" });
  return fs.readFileSync(file);
}
```

In `plugins/dforge/tests/darkmem-sync/reconcile-progress.test.mjs`:

1. Replace:

```js
import assert from "node:assert/strict";
import fs from "node:fs";
```

with:

```js
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import fs from "node:fs";
```

and replace:

```js
import { checkProgressTargets, gatherLocalProgress, progressToLocal } from "../../scripts/lib/darkmem-progress-move.mjs";
```

with:

```js
import { checkProgressTargets, gatherLocalProgress, progressToLocal, readNoFollow } from "../../scripts/lib/darkmem-progress-move.mjs";
```

2. Directly after the test `a symbolic-linked progress file is a problem, and is not read through`, which ends with:

```js
  assert.deepEqual(problems, [`${link}: a symbolic link, which the move will not read through`]);
  assert.deepEqual(sources, []);
});
```

insert:

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

// Replaces `victim` with a link to `outside` the first time the code lstats
// or opens it: after an lstat, so a check that read it as a file then follows
// the link, or before an open, so an open that follows links reads `outside`.
function swapToLink(t, victim, outside) {
  let swapped = false;
  const swap = () => {
    swapped = true;
    fs.unlinkSync(victim);
    fs.symlinkSync(outside, victim);
  };
  const lstat = fs.lstatSync;
  t.mock.method(fs, "lstatSync", (file, ...rest) => {
    const stat = lstat(file, ...rest);
    if (!swapped && file === victim) swap();
    return stat;
  });
  const open = fs.openSync;
  t.mock.method(fs, "openSync", (file, ...rest) => {
    if (!swapped && file === victim) swap();
    return open(file, ...rest);
  });
}

test("readNoFollow reads a regular file and refuses a link, a dangling link, a link to a named pipe and a directory", { skip: process.platform === "win32" }, () => {
  const dir = scratch("dms-read-");
  const file = path.join(dir, "file");
  write(file, "bytes\n");
  fs.symlinkSync(file, path.join(dir, "link"));
  fs.symlinkSync(path.join(dir, "missing"), path.join(dir, "dangling"));
  fs.symlinkSync(namedPipe(path.join(dir, "pipe")), path.join(dir, "pipe-link"));
  fs.mkdirSync(path.join(dir, "dir"));
  assert.equal(readNoFollow(file).toString(), "bytes\n");
  for (const [name, code] of [["link", "ELOOP"], ["dangling", "ELOOP"], ["pipe-link", "ELOOP"], ["dir", "EISDIR"], ["missing", "ENOENT"]]) {
    assert.throws(() => readNoFollow(path.join(dir, name)), { code }, name);
  }
});

test("without O_NOFOLLOW, as on Windows, readNoFollow refuses a link by lstat before it reads", { skip: process.platform === "win32" }, () => {
  const dir = scratch("dms-read-");
  const file = path.join(dir, "file");
  write(file, "bytes\n");
  fs.symlinkSync(file, path.join(dir, "link"));
  const windows = { ...fs.constants, O_NOFOLLOW: undefined };
  assert.equal(readNoFollow(file, windows).toString(), "bytes\n");
  assert.throws(() => readNoFollow(path.join(dir, "link"), windows), { code: "ELOOP" });
});

test("a link swapped in for a file after any lstat of it is still not read through", { skip: process.platform === "win32" }, t => {
  const dir = scratch("dms-read-");
  const victim = path.join(dir, "progress.md");
  const outside = path.join(dir, "outside.md");
  write(victim, "inside\n");
  write(outside, "outside\n");
  swapToLink(t, victim, outside);
  assert.throws(() => readNoFollow(victim), { code: "ELOOP" });
});

test("a checkout ledger swapped for a link after its check is a problem, and is not read through", { skip: process.platform === "win32" }, t => {
  const repo = makeRepo();
  const ledger = path.join(repo, ".dforge", "sdd", "p1", "progress.md");
  const outside = path.join(scratch("dms-link-"), "progress.md");
  write(ledger, LEDGER("p1"));
  write(outside, LEDGER("p1"));
  swapToLink(t, ledger, outside);
  const { problems, sources } = gatherLocalProgress({ repoRoot: repo });
  assert.deepEqual(problems, [`${ledger}: a symbolic link, which the move will not read through`]);
  assert.deepEqual(sources, []);
});
```

3. Directly after the test `a plan that starts while darkmem is written keeps progress local, and nothing is copied or moved`, which ends with:

```js
  assert.ok(result.stdout.includes("darkmem-sync reconcile: progress stay local (configured darkmem): a plan is in progress: docs/dforge/plans/p3.md\n"), result.stdout);
  assert.equal(s.stores().progress, "local");
  assert.deepEqual(movedAside(s.repo), []);
  assert.equal(fs.existsSync(path.join(s.workRoot, "sdd", "p1", "progress.md")), false);
});
```

insert:

```js

test("a ledger linked to a named pipe while darkmem is written is in progress, and is never opened for a blocking read", { skip: process.platform === "win32" }, async t => {
  const s = await setup(t, "darkmem");
  write(path.join(s.repo, ".dforge", "sdd", "p1", "progress.md"), LEDGER("p1"));
  const pipe = namedPipe(path.join(scratch("dms-pipe-"), "pipe"));
  const late = path.join(s.repo, ".dforge", "sdd", "p3", "progress.md");
  let linked = false;
  s.stub.db.onRequest = (method, pathname) => {
    if (linked || method !== "POST" || pathname !== "/api/v1/worklog/entries") return;
    linked = true;
    fs.mkdirSync(path.dirname(late), { recursive: true });
    fs.symlinkSync(pipe, late);
  };
  const result = await s.reconcile();
  assert.equal(result.code, 1, result.stdout + result.stderr);
  assert.ok(result.stdout.includes(`darkmem-sync reconcile: progress stay local (configured darkmem): a plan is in progress: ${late}\n`), result.stdout);
  assert.equal(s.stores().progress, "local");
  assert.deepEqual(movedAside(s.repo), []);
});

test("a named pipe where a ledger belongs is in progress, and is never opened for a blocking read", { skip: process.platform === "win32" }, async t => {
  const s = await setup(t, "darkmem");
  const ledger = namedPipe(path.join(s.repo, ".dforge", "sdd", "p1", "progress.md"));
  const result = await s.reconcile();
  assert.equal(result.code, 1, result.stdout + result.stderr);
  assert.ok(result.stdout.includes(`darkmem-sync reconcile: progress stay local (configured darkmem): a plan is in progress: ${ledger}\n`), result.stdout);
  assert.equal(s.stub.db.requests.length, 0);
});

test("a handoff note linked to a named pipe while darkmem is written stays local, and the recheck never blocks on it", { skip: process.platform === "win32" }, async t => {
  const s = await setup(t, "darkmem");
  const note = path.join(s.repo, ".dforge", "sdd", "p1", "handoff.md");
  write(note, "# Handoff p1\n");
  const pipe = namedPipe(path.join(scratch("dms-pipe-"), "pipe"));
  let linked = false;
  s.stub.db.onRequest = (method, pathname) => {
    if (linked || method !== "POST" || pathname !== "/api/v1/documents") return;
    linked = true;
    fs.rmSync(note);
    fs.symlinkSync(pipe, note);
  };
  const result = await s.reconcile();
  assert.equal(result.code, 1, result.stdout + result.stderr);
  assert.ok(result.stdout.includes("darkmem-sync reconcile: progress stay local (configured darkmem): progress changed in the checkouts during the move; nothing was moved locally\n"), result.stdout);
  assert.ok(result.stdout.includes(`  ${note}: changed or removed during the move\n`), result.stdout);
  assert.equal(fs.lstatSync(note).isSymbolicLink(), true);
  assert.equal(s.stores().progress, "local");
  assert.deepEqual(movedAside(s.repo), []);
});
```

4. Reconcile's in-progress check now refuses a linked mirror ledger before
the move's own walk of the mirror runs, so two existing tests change. In the
test `a symbolic link among the mirror's progress keeps progress in darkmem, and nothing is read through it`, replace:

```js
  await s.seed.append({ project: "proj", workstream: "p1", entries: [{ kind: "ledger", body: LEDGER("p1") }] });
  const outside = path.join(scratch("dms-link-"), "progress.md");
  write(outside, LEDGER("p1"));
  const link = path.join(s.workRoot, "sdd", "p1", "progress.md");
```

with:

```js
  await s.seed.append({ project: "proj", workstream: "p1", entries: [{ kind: "ledger", body: LEDGER("p1") }] });
  // A handoff note, which reconcile's in-progress check never reads, so the
  // move's own walk of the mirror is what refuses it.
  const outside = path.join(scratch("dms-link-"), "handoff.md");
  write(outside, "# Handoff p1\n");
  const link = path.join(s.workRoot, "sdd", "p1", "handoff.md");
```

(that exact four-line text occurs only in this test; the next test's `outside` line differs). In the test `a linked mirror ledger is refused before the pull, so newer darkmem content neither reads through nor replaces it`, replace:

```js
  fs.symlinkSync(outside, link);
  const result = await s.reconcile();
  assert.equal(result.code, 1, result.stdout + result.stderr);
  assert.match(result.stdout, /^darkmem-sync reconcile: progress stay darkmem \(configured local\): the mirror's progress is reached through symbolic links; nothing was pulled or copied$/m);
  assert.equal(fs.lstatSync(link).isSymbolicLink(), true);
```

with:

```js
  fs.symlinkSync(outside, link);
  const result = await s.reconcile();
  assert.equal(result.code, 1, result.stdout + result.stderr);
  // Reconcile's in-progress check will not read a ledger through a link either.
  assert.ok(result.stdout.includes(`darkmem-sync reconcile: progress stay darkmem (configured local): a plan is in progress: ${link}\n`), result.stdout);
  assert.equal(fs.lstatSync(link).isSymbolicLink(), true);
```

5. Directly after the test `a copy into the primary checkout that fails part-way is a refusal, not a crash, and a rerun finishes it`, which ends with:

```js
  t.mock.restoreAll();
  const again = await progressToLocal(m.context, { offline: "test" });
  assert.equal(again.moved, true, again.reason);
  assert.equal(read(m.target("p1")), LEDGER("p1"));
  assert.equal(read(m.target("p2")), LEDGER("p2"));
});
```

insert:

```js

test("a mirror ledger swapped for a link after its check is refused, and nothing is read through it", { skip: process.platform === "win32" }, async t => {
  const m = offlineMove();
  const ledger = path.join(m.mirror, "work", "sdd", "p1", "progress.md");
  const outside = path.join(scratch("dms-link-"), "progress.md");
  write(outside, LEDGER("p1"));
  swapToLink(t, ledger, outside);
  const result = await progressToLocal(m.context, { offline: "test" });
  assert.equal(result.moved, false);
  assert.equal(result.reason, "the primary checkout cannot take the mirror's progress");
  assert.deepEqual(result.details, [`${ledger}: a symbolic link in the mirror, which the move will not read through`]);
  assert.equal(fs.existsSync(m.target("p1")), false);
});

test("a mirror ledger whose directory turns into a file before its read is a problem line, not a crash", async t => {
  const m = offlineMove();
  const dir = path.join(m.mirror, "work", "sdd", "p1");
  const latest = path.join(m.mirror, "work", "handoff", "latest.md");
  // The move asks whether latest.md exists after it lists the ledgers and
  // before it reads them.
  const exists = fs.existsSync;
  t.mock.method(fs, "existsSync", file => {
    if (file === latest && fs.statSync(dir, { throwIfNoEntry: false })?.isDirectory()) {
      fs.rmSync(dir, { recursive: true });
      fs.writeFileSync(dir, "not a directory\n");
    }
    return exists(file);
  });
  const result = await progressToLocal(m.context, { offline: "test" });
  assert.equal(result.moved, false);
  assert.equal(result.reason, "the primary checkout cannot take the mirror's progress");
  assert.deepEqual(result.details, [`${path.join(dir, "progress.md")}: could not be read (ENOTDIR)`]);
});

test("a mirror ledger that cannot be opened is a problem line, whoever runs the test", async t => {
  const m = offlineMove();
  const ledger = path.join(m.mirror, "work", "sdd", "p1", "progress.md");
  const open = fs.openSync;
  t.mock.method(fs, "openSync", (file, ...rest) => {
    if (file === ledger) throw Object.assign(new Error("injected by the test"), { code: "EACCES" });
    return open(file, ...rest);
  });
  const result = await progressToLocal(m.context, { offline: "test" });
  assert.equal(result.moved, false);
  assert.equal(result.reason, "the primary checkout cannot take the mirror's progress");
  assert.deepEqual(result.details, [`${ledger}: could not be read (EACCES)`]);
});

test("a link that lands at a checkout target just before its copy is never read or written through", { skip: process.platform === "win32" }, async t => {
  const m = offlineMove();
  const outside = path.join(scratch("dms-link-"), "progress.md");
  write(outside, LEDGER("p1"));
  const mkdir = fs.mkdirSync;
  t.mock.method(fs, "mkdirSync", (dir, options) => {
    const made = mkdir(dir, options);
    if (dir === path.dirname(m.target("p1")) && !fs.lstatSync(m.target("p1"), { throwIfNoEntry: false })) fs.symlinkSync(outside, m.target("p1"));
    return made;
  });
  const result = await progressToLocal(m.context, { offline: "test" });
  assert.equal(result.moved, false);
  assert.equal(result.reason, "a copy into the primary checkout failed (ELOOP); the files copied so far stay, and a rerun copies the rest");
  assert.deepEqual(result.details, []);
  assert.equal(fs.lstatSync(m.target("p1")).isSymbolicLink(), true);
  assert.equal(fs.existsSync(path.join(m.mirror, "work")), true, "the mirror's copies are not set aside");
});

test("a link that replaces a copied target before the read-back is never read through", { skip: process.platform === "win32" }, async t => {
  const m = offlineMove();
  const outside = path.join(scratch("dms-link-"), "progress.md");
  write(outside, LEDGER("p1"));
  const copy = fs.copyFileSync;
  t.mock.method(fs, "copyFileSync", (from, to, mode) => {
    copy(from, to, mode);
    if (to === m.target("p2")) {
      fs.rmSync(m.target("p1"));
      fs.symlinkSync(outside, m.target("p1"));
    }
  });
  const result = await progressToLocal(m.context, { offline: "test" });
  assert.equal(result.moved, false);
  assert.equal(result.reason, "a copy into the primary checkout failed (ELOOP); the files copied so far stay, and a rerun copies the rest");
  assert.deepEqual(result.details, [`${m.target("p1")}: copied`, `${m.target("p2")}: copied`]);
  assert.equal(fs.existsSync(path.join(m.mirror, "work")), true, "the mirror's copies are not set aside");
});
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID timeout 300 node --test plugins/dforge/tests/darkmem-sync/reconcile-progress.test.mjs`

Expected: FAIL in exactly these ten tests, after about two minutes. Three of
them run the command as a child process that blocks on the pipe until
`run()`'s 30 s timeout kills it; it `exec`s node and installs no signal
handler, so nothing is left running.
- `a link swapped in for a file after any lstat of it …`: `Missing expected exception` (the fallback form reads `outside`).
- `a checkout ledger swapped for a link after its check …`: `problems` is `[]`.
- `a ledger linked to a named pipe …`, `a named pipe where a ledger belongs …`, `a handoff note linked to a named pipe …`: `result.code` is `-1` (the child was killed at 30 s).
- `a linked mirror ledger is refused before the pull …`: stdout names `the mirror's progress is reached through symbolic links`, not `a plan is in progress`.
- `a mirror ledger swapped for a link after its check …`, `a link that lands at a checkout target …`, `a link that replaces a copied target …`: `result.moved` is `true`.
- `a mirror ledger whose directory turns into a file …`: `progressToLocal` rejects with `ENOTDIR: not a directory, lstat '…/work/sdd/p1/progress.md'`.

These pass already: the helper's contract test and the Windows fallback test
(the fallback form is today's behaviour), `a mirror ledger that cannot be
opened …`, and the rewritten `a symbolic link among the mirror's progress …`.
The `cannot be opened` case passes because `readFileSync(path)` already
opens through `fs.openSync`. It is coverage that does not depend on running
as non-root.

- [ ] **Step 3: Implement**

1. In `plugins/dforge/scripts/lib/darkmem-progress-move.mjs`, replace the fallback form from Step 1:

```js
// `file`'s bytes, refusing a symbolic link with an ELOOP error.
export function readNoFollow(file, constants = fs.constants) {
  if (fs.lstatSync(file, { throwIfNoEntry: false })?.isSymbolicLink()) throw Object.assign(new Error(`${file} is a symbolic link`), { code: "ELOOP" });
  return fs.readFileSync(file);
}
```

with:

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
  try {
    const stat = fs.fstatSync(fd);
    if (!stat.isFile()) throw Object.assign(new Error(`${file} is not a regular file`), { code: stat.isDirectory() ? "EISDIR" : "EFTYPE" });
    return fs.readFileSync(fd);
  } finally {
    fs.closeSync(fd);
  }
}
```

2. `gatherLocalProgress`. Replace:

```js
    // A linked file is never read through: it could lead anywhere, a FIFO included.
    if (fs.lstatSync(item.file, { throwIfNoEntry: false })?.isSymbolicLink()) {
      problems.push(`${item.file}: a symbolic link, which the move will not read through`);
      continue;
    }
    try {
      item.buffer = fs.readFileSync(item.file);
    } catch (error) {
      problems.push(`${item.file}: could not be read (${error.code})`);
      continue;
    }
```

with:

```js
    // A linked file is never read through: it could lead anywhere, a FIFO included.
    try {
      item.buffer = readNoFollow(item.file);
    } catch (error) {
      problems.push(error.code === "ELOOP" ? `${item.file}: a symbolic link, which the move will not read through` : `${item.file}: could not be read (${error.code})`);
      continue;
    }
```

3. `progressToDarkmem`'s recheck and read-back. Replace:

```js
    let now;
    try {
      now = fs.readFileSync(item.file);
    } catch {
      now = null;
    }
    if (!now?.equals(item.buffer)) changed.push(`${item.file}: changed or removed during the move`);
  }
  if (changed.length) return refuse("progress changed in the checkouts during the move; nothing was moved locally", changed);
  const workRoot = path.join(cfg.mirror, "work");
  for (const item of sources) writeFileAtomic(local(workRoot, item.rel), item.buffer);
  const unread = sources.filter(item => !fs.readFileSync(local(workRoot, item.rel)).equals(item.buffer));
```

with:

```js
    let now;
    try {
      now = readNoFollow(item.file);
    } catch {
      now = null;
    }
    if (!now?.equals(item.buffer)) changed.push(`${item.file}: changed or removed during the move`);
  }
  if (changed.length) return refuse("progress changed in the checkouts during the move; nothing was moved locally", changed);
  const workRoot = path.join(cfg.mirror, "work");
  for (const item of sources) writeFileAtomic(local(workRoot, item.rel), item.buffer);
  const unread = sources.filter(item => {
    try {
      return !readNoFollow(local(workRoot, item.rel)).equals(item.buffer);
    } catch {
      return true;
    }
  });
```

4. `readOrNull`, which `progressToLocal` uses before each copy and for the read-back. Replace:

```js
// A file's bytes, or null when it does not exist.
function readOrNull(file) {
  try {
    return fs.readFileSync(file);
  } catch (error) {
```

with:

```js
// A file's bytes, or null when it does not exist; never read through a link.
function readOrNull(file) {
  try {
    return readNoFollow(file);
  } catch (error) {
```

Any other error, `ELOOP` included, still throws into the copy loop's catch,
which refuses with `a copy into the primary checkout failed (ELOOP); …`.

5. `progressToLocal`'s source read. Replace:

```js
    item.target = local(stateDir, item.rel);
    if (fs.lstatSync(item.file, { throwIfNoEntry: false })?.isSymbolicLink()) {
      problems.push(`${item.file}: a symbolic link in the mirror, which the move will not read through`);
      continue;
    }
    try {
      item.buffer = fs.readFileSync(item.file);
    } catch (error) {
      problems.push(`${item.file}: could not be read (${error.code})`);
      continue;
    }
```

with:

```js
    item.target = local(stateDir, item.rel);
    try {
      item.buffer = readNoFollow(item.file);
    } catch (error) {
      problems.push(error.code === "ELOOP" ? `${item.file}: a symbolic link in the mirror, which the move will not read through` : `${item.file}: could not be read (${error.code})`);
      continue;
    }
```

Leave the target read just below it (`held = fs.readFileSync(item.target)`)
and `checkProgressTargets`' read unchanged: `linksBelow` and the mirror walk
guard those paths.

6. In `plugins/dforge/scripts/lib/darkmem-reconcile.mjs`, replace:

```js
import { progressToDarkmem, progressToLocal } from "./darkmem-progress-move.mjs";
```

with:

```js
import { progressToDarkmem, progressToLocal, readNoFollow } from "./darkmem-progress-move.mjs";
```

and in `inProgress` replace:

```js
      let text;
      try {
        text = fs.readFileSync(ledger, "utf8");
      } catch (error) {
        if (error.code === "ENOENT") continue;
        found.push(ledger);
        continue;
      }
```

with:

```js
      // A linked ledger is never read through, and an unread one is in progress.
      let text;
      try {
        text = readNoFollow(ledger).toString("utf8");
      } catch (error) {
        if (error.code === "ENOENT") continue;
        found.push(ledger);
        continue;
      }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID timeout 300 node --test plugins/dforge/tests/darkmem-sync/reconcile-progress.test.mjs`

Expected: PASS, in about 25 s, including the existing tests at the moves' link refusals (`a symbolic-linked progress file is a problem …`, `a symbolic-linked mirror work directory …`) and the EISDIR cases.

Then:

Run: `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID timeout 300 node --test plugins/dforge/tests/darkmem-sync/reconcile.test.mjs`

Expected: PASS (`an unreadable ledger is in progress …` still names the directory ledger).

Run: `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID timeout 600 bash plugins/dforge/tests/darkmem-sync.test.sh`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/scripts/lib/darkmem-progress-move.mjs plugins/dforge/scripts/lib/darkmem-reconcile.mjs plugins/dforge/tests/darkmem-sync/reconcile-progress.test.mjs
git commit -m "fix(darkmem): read progress files without links"
```

---

### Task 13: Refuse the links reconcile and the moves still miss

Four ways a link still reaches progress after Task 12:

- Both progress moves list ledgers through `ledgerFiles`, whose `existsSync`
  follows links, so a dangling `progress.md` link is never listed and is left
  behind (DM 61.c). `ledgerFiles` itself stays as it is: `localChanges`,
  `pushLedgers` and `gatherSources` rely on it skipping such a link.
- `progressToDarkmem` writes into the mirror's `work` directory without
  checking `cfg.mirror`, `work` or the plan directories under it for links
  (DM 61.i).
- `progressToLocal`'s walk of the mirror says "reached through symbolic
  links" even when its only finding is a directory that could not be listed
  (DM 61.f).
- Reconcile's `dirEntries` drops a plan directory that is a link, so
  `inProgress` never sees it and a documents move proceeds (DM 61.j,
  adjacent).

After this task the moves list ledgers with their own lstat-based listing,
`progressToDarkmem` refuses a linked mirror, `work` or plan directory before
it reads or sends anything, the refusal names what the walk found, and
`inProgress` counts a linked plan directory as in progress without reading
through it.

**Files:**
- Modify: `plugins/dforge/scripts/lib/darkmem-progress-move.mjs`
- Modify: `plugins/dforge/scripts/lib/darkmem-reconcile.mjs`
- Test: `plugins/dforge/tests/darkmem-sync/reconcile-progress.test.mjs`
- Test: `plugins/dforge/tests/darkmem-sync/reconcile.test.mjs`

**Interfaces:**
- Consumes: `readNoFollow(file)` from Task 12 and its call sites' mapping, as the Contracts bullet `readNoFollow` states: `ledgersIn` lists a dangling link, whose open throws `ELOOP`, and a ledger its `lstat` cannot reach, and the `gatherLocalProgress` and `progressToLocal` reads report them (`ELOOP` as their link line, any other code as `<file>: could not be read (<code>)`).
- Produces: None

**Items:** DM 61

**Depends on:** Task 12
**Implementer:** dr-superpowers:impl-sonnet-high
**Evaluation:** files 2 - spec 0 - coupling 1 - risk 2 = 5

- [ ] **Step 1: Write the failing tests**

These tests prove that:
- A dangling `progress.md` link is a problem for the move, and `status` is unchanged by it (DM 61.c).
- A linked mirror plan directory or a linked mirror refuses the move into darkmem before anything is sent or written through it (DM 61.i).
- An unlistable mirror `work` directory is named as unlistable (DM 61.f).
- A ledger the new listing's `lstat` cannot reach is left to the guarded read, which reports it, rather than crashing the move (the crash Task 12 removed from the reads).
- A linked plan directory blocks a documents move (61.j, adjacent).

One existing test changes: a linked checkout plan directory is now refused by
reconcile's in-progress check before the move runs.

In `plugins/dforge/tests/darkmem-sync/reconcile-progress.test.mjs`:

1. Immediately before the comment line `// A named pipe nobody writes to: a plain read of it, or through a link to it,` (Task 12 added it), insert:

```js
test("a dangling progress.md link is a problem, not a ledger left behind", { skip: process.platform === "win32" }, () => {
  const repo = makeRepo();
  const link = path.join(repo, ".dforge", "sdd", "p1", "progress.md");
  fs.mkdirSync(path.dirname(link), { recursive: true });
  fs.symlinkSync(path.join(scratch("dms-link-"), "missing.md"), link);
  const { problems, sources } = gatherLocalProgress({ repoRoot: repo });
  assert.deepEqual(problems, [`${link}: a symbolic link, which the move will not read through`]);
  assert.deepEqual(sources, []);
});

test("a dangling progress.md link in the mirror leaves status as it was", { skip: process.platform === "win32" }, async t => {
  const s = await setup(t, "local");
  write(path.join(s.workRoot, "sdd", "p2", "progress.md"), LEDGER("p2"));
  const before = await run(["status"], { cwd: s.repo, env: s.env });
  assert.equal(before.code, 0, before.stdout + before.stderr);
  const link = path.join(s.workRoot, "sdd", "p1", "progress.md");
  fs.mkdirSync(path.dirname(link), { recursive: true });
  fs.symlinkSync(path.join(scratch("dms-link-"), "missing.md"), link);
  const after = await run(["status"], { cwd: s.repo, env: s.env });
  assert.deepEqual(after, before);
});

```

2. In the test `a plan directory that is a symbolic link stays local, and nothing is sent or moved`, replace:

```js
  assert.ok(result.stdout.includes("darkmem-sync reconcile: progress stay local (configured darkmem): the checkouts hold progress the move cannot carry\n"), result.stdout);
  assert.ok(result.stdout.includes(`  ${link}: a symbolic link, which the move will not move files through\n`), result.stdout);
  assert.deepEqual(s.stub.db.requests.slice(before).filter(r => r.method !== "GET").map(r => `${r.method} ${r.path}`), []);
  assert.equal(s.stores().progress, "local");
  assert.deepEqual(movedAside(s.worktree), []);
});
```

with:

```js
  // Reconcile's in-progress check counts a linked plan directory before the
  // move runs; the move's own listing names it too.
  assert.ok(result.stdout.includes(`darkmem-sync reconcile: progress stay local (configured darkmem): a plan is in progress: ${link}\n`), result.stdout);
  assert.deepEqual(gatherLocalProgress({ repoRoot: s.repo }).problems, [`${link}: a symbolic link, which the move will not move files through`]);
  assert.deepEqual(s.stub.db.requests.slice(before).filter(r => r.method !== "GET").map(r => `${r.method} ${r.path}`), []);
  assert.equal(s.stores().progress, "local");
  assert.deepEqual(movedAside(s.worktree), []);
});

for (const { name, plant, linked, unwritten } of [
  {
    name: "a plan directory in the mirror",
    plant: s => {
      fs.mkdirSync(path.join(s.workRoot, "sdd"), { recursive: true });
      fs.symlinkSync(scratch("dms-link-"), path.join(s.workRoot, "sdd", "p1"));
    },
    linked: s => path.join(s.workRoot, "sdd", "p1"),
    unwritten: s => path.join(fs.realpathSync(path.join(s.workRoot, "sdd", "p1")), "progress.md"),
  },
  {
    name: "the mirror itself",
    plant: s => {
      fs.mkdirSync(path.dirname(s.mirror), { recursive: true });
      fs.symlinkSync(scratch("dms-link-"), s.mirror);
    },
    linked: s => s.mirror,
    unwritten: s => path.join(fs.realpathSync(s.mirror), "work"),
  },
]) {
  test(`progress stays local when ${name} is a symbolic link, and nothing is sent or written through it`, { skip: process.platform === "win32" }, async t => {
    const s = await setup(t, "darkmem");
    write(path.join(s.repo, ".dforge", "sdd", "p1", "progress.md"), LEDGER("p1"));
    plant(s);
    const result = await s.reconcile();
    assert.equal(result.code, 1, result.stdout + result.stderr);
    assert.ok(result.stdout.includes("darkmem-sync reconcile: progress stay local (configured darkmem): the mirror's progress is reached through symbolic links; nothing was sent or moved\n"), result.stdout);
    assert.ok(result.stdout.includes(`  ${linked(s)}: a symbolic link in the mirror, which the move will not read through\n`), result.stdout);
    assert.deepEqual(s.stub.db.requests.filter(r => r.method !== "GET").map(r => `${r.method} ${r.path}`), []);
    assert.equal(fs.existsSync(unwritten(s)), false, "nothing is written through the link");
    assert.equal(s.stores().progress, "local");
    assert.deepEqual(movedAside(s.repo), []);
  });
}
```

3. Immediately before the line `test("a mirror ledger swapped for a link after its check is refused, and nothing is read through it", { skip: process.platform === "win32" }, async t => {` (Task 12 added it), insert:

```js
test("a mirror work directory that cannot be listed is named as such, not as a symbolic link", async () => {
  const m = offlineMove();
  const work = path.join(m.mirror, "work");
  fs.rmSync(work, { recursive: true });
  write(work, "not a directory\n");
  const result = await progressToLocal(m.context, { offline: "test" });
  assert.equal(result.moved, false);
  assert.equal(result.reason, "the mirror's progress could not be listed; nothing was pulled or copied");
  assert.deepEqual(result.details, [`${work}: could not be listed (ENOTDIR)`]);
});

test("a mirror ledger that lstat cannot reach while ledgers are listed is a problem line from the read, not a crash", async t => {
  const m = offlineMove();
  const ledger = path.join(m.mirror, "work", "sdd", "p1", "progress.md");
  // As if its directory turned unreadable after it was listed: every look at
  // the ledger fails, the listing's lstat and the read's open alike.
  const denied = () => {
    throw Object.assign(new Error("injected by the test"), { code: "EACCES" });
  };
  const lstat = fs.lstatSync;
  t.mock.method(fs, "lstatSync", (file, ...rest) => (file === ledger ? denied() : lstat(file, ...rest)));
  const open = fs.openSync;
  t.mock.method(fs, "openSync", (file, ...rest) => (file === ledger ? denied() : open(file, ...rest)));
  const result = await progressToLocal(m.context, { offline: "test" });
  assert.equal(result.moved, false);
  assert.equal(result.reason, "the primary checkout cannot take the mirror's progress");
  assert.deepEqual(result.details, [`${ledger}: could not be read (EACCES)`]);
});

```

In `plugins/dforge/tests/darkmem-sync/reconcile.test.mjs`, immediately before the line `test("a plan that starts during the pull stops the move before the deletion is staged", async t => {`, insert:

```js
test("a plan directory reached through a symbolic link is in progress, and a documents move stays local", { skip: process.platform === "win32" }, async t => {
  const s = await docsRepo(t, { "specs/a.md": "# A\n", "plans/k.md": "# K\n", "plans/completed.md": "- `docs/dforge/plans/k.md`\n" });
  // Its ledger reads as finished, which only a read through the link could tell.
  const outside = scratch("dms-link-");
  write(path.join(outside, "progress.md"), LEDGER("docs/dforge/plans/k.md"));
  const link = path.join(s.repo, ".dforge", "sdd", "k");
  fs.mkdirSync(path.dirname(link), { recursive: true });
  fs.symlinkSync(outside, link);
  const result = await s.reconcile();
  assert.equal(result.code, 1, result.stdout + result.stderr);
  assert.equal(result.stdout, `darkmem-sync reconcile: documents stay local (configured darkmem): a plan is in progress: ${link}\n`);
  assert.equal(s.stub.db.requests.length, 0);
  assert.equal(git(s.repo, "diff", "--cached", "--name-only"), "");
  assert.equal(read(at(s.repo, "docs/dforge/specs/a.md")), "# A\n");
  assert.deepEqual(s.stores(), { documents: "local", progress: "local" });
});

```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID timeout 300 node --test plugins/dforge/tests/darkmem-sync/reconcile-progress.test.mjs`

Expected: FAIL in exactly these five tests:
- `a dangling progress.md link is a problem …`: `problems` is `[]` (`ledgerFiles` skips the link).
- `a plan directory that is a symbolic link stays local …`: stdout still names `the checkouts hold progress the move cannot carry`.
- Both `progress stays local when … is a symbolic link …` rows: `result.code` is `0`; the move wrote through the link.
- `a mirror work directory that cannot be listed …`: the reason says `is reached through symbolic links`.

`a dangling progress.md link in the mirror leaves status as it was` passes;
it guards `ledgerFiles`, which this task leaves alone. `a mirror ledger that
lstat cannot reach while ledgers are listed …` passes too, since
`ledgerFiles` lists through `existsSync`, which the test's mocks do not reach;
it guards the new listing, which would otherwise reject with the injected
`EACCES` from its `lstat`.

Run: `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID timeout 300 node --test plugins/dforge/tests/darkmem-sync/reconcile.test.mjs`

Expected: FAIL in `a plan directory reached through a symbolic link is in progress …` only: `result.code` is `0` (`documents moved to darkmem`).

- [ ] **Step 3: Implement**

In `plugins/dforge/scripts/lib/darkmem-progress-move.mjs`:

1. Import `validKey` instead of `ledgerFiles`. Replace:

```js
  DOC_PREFIX, checkpointTarget, decodeUtf8, isoMicros, ledgerFiles, ledgerPieces, listDocumentFiles, newestCheckpointAt, propertiesFor,
  recordCheckpointAt, sha256, unsupportedPlanDirs, uriFamily, utcStamp, writeFileAtomic,
} from "./darkmem-mirror.mjs";
```

with:

```js
  DOC_PREFIX, checkpointTarget, decodeUtf8, isoMicros, ledgerPieces, listDocumentFiles, newestCheckpointAt, propertiesFor,
  recordCheckpointAt, sha256, unsupportedPlanDirs, uriFamily, utcStamp, validKey, writeFileAtomic,
} from "./darkmem-mirror.mjs";
```

2. Immediately before the line `// The primary checkout first, then every linked worktree git lists.`, insert:

```js
// Each plan directory's progress.md that lstat finds, a dangling link
// included, so the read's link check names it. ledgerFiles' existsSync skips
// a dangling link, which its other callers rely on. An lstat that fails other
// than by ENOENT (EACCES, or ENOTDIR once the directory changed) keeps the
// file, so the callers' guarded read reports it instead of the listing throwing.
function ledgersIn(workRoot) {
  const sdd = path.join(workRoot, "sdd");
  let entries;
  try {
    entries = fs.readdirSync(sdd, { withFileTypes: true });
  } catch (error) {
    if (error.code === "ENOENT") return [];
    throw error;
  }
  return entries
    .filter(entry => entry.isDirectory() && validKey(entry.name))
    .map(entry => ({ slug: entry.name, file: path.join(sdd, entry.name, "progress.md") }))
    .filter(({ file }) => {
      try {
        return fs.lstatSync(file, { throwIfNoEntry: false }) !== undefined;
      } catch {
        return true;
      }
    })
    .sort((a, b) => (a.slug < b.slug ? -1 : a.slug > b.slug ? 1 : 0));
}

```

3. In `gatherLocalProgress`, replace:

```js
    for (const { slug, file } of ledgerFiles(stateDir)) files.push({ kind: "ledger", slug, file, stateDir, rel: `sdd/${slug}/progress.md` });
```

with:

```js
    for (const { slug, file } of ledgersIn(stateDir)) files.push({ kind: "ledger", slug, file, stateDir, rel: `sdd/${slug}/progress.md` });
```

and in `progressToLocal`, replace:

```js
    ...ledgerFiles(workRoot).map(({ slug, file }) => ({ file, rel: `sdd/${slug}/progress.md` })),
```

with:

```js
    ...ledgersIn(workRoot).map(({ slug, file }) => ({ file, rel: `sdd/${slug}/progress.md` })),
```

4. Name the walk's findings. Replace:

```js
// One line per symbolic link, or directory that cannot be listed, at or under the
// mirror's work directory. Dirent types come from lstat, so no link is followed.
function mirrorLinks(workRoot) {
```

with:

```js
const MIRROR_LINK = "a symbolic link in the mirror, which the move will not read through";

// One line per symbolic link, or directory that cannot be listed, at or under the
// mirror's work directory. Dirent types come from lstat, so no link is followed.
function mirrorLinks(workRoot) {
```

then replace:

```js
      if (entry.isSymbolicLink()) lines.push(`${file}: a symbolic link in the mirror, which the move will not read through`);
```

with:

```js
      if (entry.isSymbolicLink()) lines.push(`${file}: ${MIRROR_LINK}`);
```

then replace:

```js
  if (top?.isSymbolicLink()) return [`${workRoot}: a symbolic link in the mirror, which the move will not read through`];
  walk(workRoot);
  return lines;
}
```

with:

```js
  if (top?.isSymbolicLink()) return [`${workRoot}: ${MIRROR_LINK}`];
  walk(workRoot);
  return lines;
}

// The refusal for mirrorLinks' lines, or null when there are none, saying
// whether the mirror could not be listed, is reached through links, or both.
function mirrorRefusal(lines, outcome) {
  if (!lines.length) return null;
  const found = [
    lines.some(line => !line.endsWith(MIRROR_LINK)) && "could not be listed",
    lines.some(line => line.endsWith(MIRROR_LINK)) && "is reached through symbolic links",
  ].filter(Boolean).join(", and ");
  return refuse(`the mirror's progress ${found}; ${outcome}`, lines);
}
```

and in `progressToLocal` replace:

```js
  const linked = mirrorLinks(workRoot);
  if (linked.length) return refuse("the mirror's progress is reached through symbolic links; nothing was pulled or copied", linked);
```

with:

```js
  const linked = mirrorRefusal(mirrorLinks(workRoot), "nothing was pulled or copied");
  if (linked) return linked;
```

Leave the source-read line Task 12 wrote (`a symbolic link in the mirror, which the move will not read through`) as it is.

5. Check the mirror in `progressToDarkmem` before anything is read or sent. Replace:

```js
      links.map(link => `${link}: a symbolic link, which the move will not move files through`),
    );
  }
  const report = scratchReport();
```

with:

```js
      links.map(link => `${link}: a symbolic link, which the move will not move files through`),
    );
  }
  // The mirror's copies are read and written under its work directory, so a
  // link at the mirror, at work or below it would carry them elsewhere.
  const workRoot = path.join(cfg.mirror, "work");
  const top = fs.lstatSync(cfg.mirror, { throwIfNoEntry: false })?.isSymbolicLink() ? [`${cfg.mirror}: ${MIRROR_LINK}`] : [];
  const linked = mirrorRefusal([...top, ...mirrorLinks(workRoot)], "nothing was sent or moved");
  if (linked) return linked;
  const report = scratchReport();
```

and delete the now-duplicate declaration further down the same function. Replace:

```js
  if (changed.length) return refuse("progress changed in the checkouts during the move; nothing was moved locally", changed);
  const workRoot = path.join(cfg.mirror, "work");
```

with:

```js
  if (changed.length) return refuse("progress changed in the checkouts during the move; nothing was moved locally", changed);
```

(`progressToLocal` has its own `const workRoot` line; leave that one.)

In `plugins/dforge/scripts/lib/darkmem-reconcile.mjs`:

6. Replace:

```js
function dirEntries(dir) {
  try {
    return fs.readdirSync(dir, { withFileTypes: true }).filter(entry => entry.isDirectory()).map(entry => entry.name).sort();
  } catch (error) {
```

with:

```js
// stat follows a link to its target's type, and reads nothing through it.
const isDirectoryLink = file => {
  try {
    return fs.statSync(file).isDirectory();
  } catch {
    return false;
  }
};

// The directories under `dir`, a symbolic link to one included, as
// { name, linked }.
function dirEntries(dir) {
  try {
    return fs.readdirSync(dir, { withFileTypes: true })
      .filter(entry => entry.isDirectory() || (entry.isSymbolicLink() && isDirectoryLink(path.join(dir, entry.name))))
      .map(entry => ({ name: entry.name, linked: entry.isSymbolicLink() }))
      .sort((a, b) => (a.name < b.name ? -1 : a.name > b.name ? 1 : 0));
  } catch (error) {
```

7. In `inProgress`, replace:

```js
    for (const slug of dirEntries(sdd)) {
      const ledger = path.join(sdd, slug, "progress.md");
```

with:

```js
    for (const { name: slug, linked } of dirEntries(sdd)) {
      // A linked plan directory is not read through, so nothing can show its
      // plan finished.
      if (linked) {
        found.push(path.join(sdd, slug));
        continue;
      }
      const ledger = path.join(sdd, slug, "progress.md");
```

`dirEntries` has no other caller.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID timeout 300 node --test plugins/dforge/tests/darkmem-sync/reconcile-progress.test.mjs`

Expected: PASS, including `a symbolic-linked mirror work directory …` and `a symbolic link among the mirror's progress …` (both still say `is reached through symbolic links; nothing was pulled or copied`).

Run: `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID timeout 300 node --test plugins/dforge/tests/darkmem-sync/reconcile.test.mjs`

Expected: PASS

Run: `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID timeout 600 bash plugins/dforge/tests/darkmem-sync.test.sh`

Expected: PASS (the mirror, push and status suites still use `ledgerFiles`).

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/scripts/lib/darkmem-progress-move.mjs plugins/dforge/scripts/lib/darkmem-reconcile.mjs plugins/dforge/tests/darkmem-sync/reconcile-progress.test.mjs plugins/dforge/tests/darkmem-sync/reconcile.test.mjs
git commit -m "fix(darkmem): refuse links the progress moves miss"
```

---

### Task 14: Make the progress moves' refusals say what happened

Three refusals in `darkmem-progress-move.mjs` misreport what happened:

- When some sources could not be moved aside, `progressToDarkmem` returns
  before it writes the state directory's `.gitignore`, so the backups it did
  make show as untracked. The refusal also reads "1 sources" (DM 61.d).
- When an edit lands in the primary checkout during `progressToLocal`'s
  copies, the refusal names only the changed file, not the files already
  copied (DM 61.g).
- When the edit lands between the re-read and the exclusive copy, the copy's
  `EEXIST` reaches the generic catch and reads as "a copy … failed" instead
  of a change during the move (DM 61.h).

After this task the `.gitignore` files are written before the moved-aside
refusal, the count reads "1 source" / "N sources", the landed-edit refusal
also names each file copied so far, and an `EEXIST` is a change during the
move.

**Files:**
- Modify: `plugins/dforge/scripts/lib/darkmem-progress-move.mjs`
- Test: `plugins/dforge/tests/darkmem-sync/reconcile-progress.test.mjs`

**Interfaces:**
- Consumes: the copy loop's mapping in the Contracts bullet `readNoFollow` (Task 12): `readOrNull`'s errors other than `ENOENT`, `ELOOP` included, still reach the loop's generic catch; this task's `EEXIST` branch wraps only the exclusive copy. It runs after Tasks 12 and 13, which edit the same file; none of its anchors is text they change.
- Produces: None

**Items:** DM 61

**Depends on:** Task 13
**Implementer:** dr-superpowers:impl-sonnet-low
**Evaluation:** files 1 - spec 0 - coupling 0 - risk 1 = 2

- [ ] **Step 1: Write the failing tests**

These tests prove that one or two sources that cannot be moved aside are
counted in the right number and leave the backup ignored (DM 61.d). They
prove that a landed edit's refusal names the file copied before it (DM 61.g),
and that an `EEXIST` from the exclusive copy is a change during the move
(DM 61.h).

In `plugins/dforge/tests/darkmem-sync/reconcile-progress.test.mjs`:

1. Replace the whole test `a source that cannot be moved aside is one line naming it, and a rerun finishes the move`:

```js
test("a source that cannot be moved aside is one line naming it, and a rerun finishes the move", async t => {
  const s = await setup(t, "darkmem");
  const ledger = path.join(s.repo, ".dforge", "sdd", "p1", "progress.md");
  write(ledger, LEDGER("p1"));
  // A non-empty directory at the ledger's backup path, for every stamp the next minute can name.
  const now = Date.now();
  const blockers = [];
  for (let i = 0; i < 60; i += 1) {
    const dir = path.join(s.repo, ".dforge", `moved-${utcStamp(new Date(now + i * 1000))}`);
    blockers.push(dir);
    write(path.join(dir, "sdd", "p1", "progress.md", "keep"), "taken\n");
  }
  const result = await s.reconcile();
  assert.equal(result.code, 1, result.stdout + result.stderr);
  assert.doesNotMatch(result.stderr, /unexpected error/);
  assert.match(result.stdout, /^darkmem-sync reconcile: progress stay local \(configured darkmem\): darkmem and the mirror hold the progress, but 1 sources could not be moved aside: .+progress\.md \(\w+\); reconcile again to finish$/m);
  assert.equal(read(ledger), LEDGER("p1"));
  assert.equal(s.stores().progress, "local");
  for (const dir of blockers) fs.rmSync(dir, { recursive: true });
  const again = await s.reconcile();
  assert.equal(again.code, 0, again.stdout + again.stderr);
  assert.match(again.stdout, /^darkmem-sync reconcile: progress moved to darkmem$/m);
  assert.equal(fs.existsSync(ledger), false);
});
```

with:

```js
for (const [slugs, count] of [[["p1"], "1 source"], [["p1", "p2"], "2 sources"]]) {
  test(`a move-aside that leaves ${count} behind names them in one line, still ignores the backup, and a rerun finishes the move`, async t => {
    const s = await setup(t, "darkmem");
    const ledgers = slugs.map(slug => path.join(s.repo, ".dforge", "sdd", slug, "progress.md"));
    for (const [k, slug] of slugs.entries()) write(ledgers[k], LEDGER(slug));
    // A non-empty directory at each ledger's backup path, for every stamp the next minute can name.
    const now = Date.now();
    const blockers = [];
    for (let i = 0; i < 60; i += 1) {
      const dir = path.join(s.repo, ".dforge", `moved-${utcStamp(new Date(now + i * 1000))}`);
      blockers.push(dir);
      for (const slug of slugs) write(path.join(dir, "sdd", slug, "progress.md", "keep"), "taken\n");
    }
    const result = await s.reconcile();
    assert.equal(result.code, 1, result.stdout + result.stderr);
    assert.doesNotMatch(result.stderr, /unexpected error/);
    const named = slugs.map(() => ".+progress\\.md \\(\\w+\\)").join(", ");
    assert.match(result.stdout, new RegExp(`^darkmem-sync reconcile: progress stay local \\(configured darkmem\\): darkmem and the mirror hold the progress, but ${count} could not be moved aside: ${named}; reconcile again to finish$`, "m"));
    for (const [k, slug] of slugs.entries()) assert.equal(read(ledgers[k]), LEDGER(slug));
    assert.equal(read(path.join(s.repo, ".dforge", ".gitignore")), "*\n");
    assert.equal(s.stores().progress, "local");
    for (const dir of blockers) fs.rmSync(dir, { recursive: true });
    const again = await s.reconcile();
    assert.equal(again.code, 0, again.stdout + again.stderr);
    assert.match(again.stdout, /^darkmem-sync reconcile: progress moved to darkmem$/m);
    for (const ledger of ledgers) assert.equal(fs.existsSync(ledger), false);
  });
}
```

2. In the test `an edit that lands in the primary checkout just before a copy is never overwritten`, replace:

```js
  assert.deepEqual(result.details, [`${m.target("p1")}: changed during the move; not overwritten`]);
  assert.equal(read(m.target("p1")), "edited meanwhile\n");
  assert.equal(fs.existsSync(path.join(m.mirror, "work")), true, "the mirror's copies are not set aside");
});
```

with:

```js
  assert.deepEqual(result.details, [`${m.target("p1")}: changed during the move; not overwritten`, `${m.target("p2")}: copied`]);
  assert.equal(read(m.target("p1")), "edited meanwhile\n");
  assert.equal(fs.existsSync(path.join(m.mirror, "work")), true, "the mirror's copies are not set aside");
});

test("an edit that lands between the read and the exclusive copy is a change during the move, not a failed copy", async t => {
  const m = offlineMove();
  const copy = fs.copyFileSync;
  t.mock.method(fs, "copyFileSync", (from, to, mode) => {
    if (to !== m.target("p1")) return copy(from, to, mode);
    fs.writeFileSync(to, "edited meanwhile\n");
    throw Object.assign(new Error("injected by the test"), { code: "EEXIST" });
  });
  const result = await progressToLocal(m.context, { offline: "test" });
  assert.equal(result.moved, false);
  assert.equal(result.reason, "the primary checkout changed during the move; nothing was overwritten");
  assert.deepEqual(result.details, [`${m.target("p1")}: changed during the move; not overwritten`, `${m.target("p2")}: copied`]);
  assert.equal(read(m.target("p1")), "edited meanwhile\n");
  assert.equal(fs.existsSync(path.join(m.mirror, "work")), true, "the mirror's copies are not set aside");
});
```

That existing test already edits p1's target while p2 is copied after it, so
its corrected details are DM 61.g's check.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID timeout 300 node --test plugins/dforge/tests/darkmem-sync/reconcile-progress.test.mjs`

Expected: FAIL in exactly these four tests:
- `a move-aside that leaves 1 source behind …`: stdout reads `but 1 sources could not be moved aside`.
- `a move-aside that leaves 2 sources behind …`: `ENOENT` reading `.dforge/.gitignore`.
- `an edit that lands in the primary checkout just before a copy …`: `details` lacks `<p2 target>: copied`.
- `an edit that lands between the read and the exclusive copy …`: the reason is `a copy into the primary checkout failed (EEXIST); …`.

- [ ] **Step 3: Implement**

All edits are in `plugins/dforge/scripts/lib/darkmem-progress-move.mjs`.

1. In `progressToDarkmem`, write the `.gitignore` files first. Replace:

```js
  // darkmem and the mirror already hold every source, so a rerun finds them
  // filed and moves aside only what is left.
  if (left.length) {
    return refuse(`darkmem and the mirror hold the progress, but ${left.length} sources could not be moved aside: ${left.join(", ")}; reconcile again to finish`);
  }
  // The checkout's state directory ignores itself, as .dforge/sdd/ does, so a
  // backup never shows as untracked in a repository that does not list it.
  // "wx" never writes through a link or over a file already there.
  for (const stateDir of new Set(files.map(item => item.stateDir))) {
    if (fs.lstatSync(stateDir).isSymbolicLink()) continue;
    try {
      fs.writeFileSync(path.join(stateDir, ".gitignore"), "*\n", { flag: "wx" });
    } catch (error) {
      if (error.code !== "EEXIST") throw error;
    }
  }
```

with:

```js
  // The checkout's state directory ignores itself, as .dforge/sdd/ does, so a
  // backup never shows as untracked in a repository that does not list it.
  // "wx" never writes through a link or over a file already there.
  for (const stateDir of new Set(files.map(item => item.stateDir))) {
    if (fs.lstatSync(stateDir).isSymbolicLink()) continue;
    try {
      fs.writeFileSync(path.join(stateDir, ".gitignore"), "*\n", { flag: "wx" });
    } catch (error) {
      if (error.code !== "EEXIST") throw error;
    }
  }
  // darkmem and the mirror already hold every source, so a rerun finds them
  // filed and moves aside only what is left.
  if (left.length) {
    const sourceCount = left.length === 1 ? "1 source" : `${left.length} sources`;
    return refuse(`darkmem and the mirror hold the progress, but ${sourceCount} could not be moved aside: ${left.join(", ")}; reconcile again to finish`);
  }
```

2. In `progressToLocal`, replace:

```js
      if (!now) {
        fs.copyFileSync(item.file, item.target, fs.constants.COPYFILE_EXCL);
        copied.push(item);
      }
    }
    if (landed.length) return refuse("the primary checkout changed during the move; nothing was overwritten", landed);
```

with:

```js
      if (!now) {
        // A file the exclusive copy finds there landed after the read above.
        try {
          fs.copyFileSync(item.file, item.target, fs.constants.COPYFILE_EXCL);
        } catch (error) {
          if (error.code !== "EEXIST") throw error;
          landed.push(`${item.target}: changed during the move; not overwritten`);
          continue;
        }
        copied.push(item);
      }
    }
    if (landed.length) {
      return refuse("the primary checkout changed during the move; nothing was overwritten", [...landed, ...copied.map(item => `${item.target}: copied`)]);
    }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID timeout 300 node --test plugins/dforge/tests/darkmem-sync/reconcile-progress.test.mjs`

Expected: PASS, including the part-way copy failure (`EIO`) and Task 12's `ELOOP` cases, which still take the generic catch.

Run: `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID timeout 600 bash plugins/dforge/tests/darkmem-sync.test.sh`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/scripts/lib/darkmem-progress-move.mjs plugins/dforge/tests/darkmem-sync/reconcile-progress.test.mjs
git commit -m "fix(darkmem): say what the progress moves left"
```

---

### Task 15: Release dforge 4.2.1

**Files:**
- Modify: `plugins/dforge/.claude-plugin/plugin.json`
- Modify: `plugins/dforge/.codex-plugin/plugin.json`

**Interfaces:**
- Consumes: None
- Produces: None

**Depends on:** Task 14
**Implementer:** dr-superpowers:impl-sonnet-low
**Evaluation:** files 0 - spec 0 - coupling 0 - risk 0 = 0

- [ ] **Step 1: Verify the current versions**

Run: `timeout 60 grep -n '"version"' plugins/dforge/.claude-plugin/plugin.json plugins/dforge/.codex-plugin/plugin.json`
Expected: both read `"version": "4.2.0",`.

- [ ] **Step 2: Bump both manifests**

In each of the two files replace `"version": "4.2.0",` with
`"version": "4.2.1",`. Nothing else changes: no test or script pins the
dforge version (`timeout 60 grep -rln '4\.2\.0' plugins/dforge --include=*.sh --include=*.mjs --include=*.ts --include=*.json`
lists only the two manifests and generated types, 2026-10-20).

- [ ] **Step 3: Verify the release and the whole branch (spec A2, A4)**

Run, from the worktree root, each bounded:
- `timeout 60 grep -c '"version": "4.2.1"' plugins/dforge/.claude-plugin/plugin.json plugins/dforge/.codex-plugin/plugin.json` — 1 each
- `timeout 120 node scripts/validate-repository.mjs` — exit 0 (it checks the
  two manifests agree)
- `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID timeout 1800 node scripts/test-all.mjs` — exit 0 (it prints `Skipped tsc --noEmit -p plugins/dforge: tsc not found` on this host)
- `timeout 120 /root/.local/bin/claude plugin validate .`, then the same for
  `plugins/dforge`, `plugins/dr-status`, `plugins/darkraise-ui` and
  `plugins/darkraise-win32ui` — each prints `Validation passed`
- `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID timeout 300 /root/.local/bin/claude plugin test plugins/dforge` — exit 0

Any failure stops the task: report it with the failing test's name.

- [ ] **Step 4: Leave the register rows to finishing**

Change no register row here. dr-superpowers:finishing-a-development-branch
resolves every row this plan covers in the integration commit: `done` for
each fixed row, and `n/a` for DM 54 (not reproduced once its diagnostic
landed). FS 48 is already `n/a` (header, Assumptions). Do not run the
header's **After finishing** check here: the rows are still `planned` until
finishing resolves them.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/.claude-plugin/plugin.json plugins/dforge/.codex-plugin/plugin.json
git commit -m "chore(dforge): release 4.2.1"
```
