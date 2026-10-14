# darkmem Mirror Open Rows Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: the skill the **Execution:** line names — dr-superpowers:subagent-driven-development for `subagent`, dr-superpowers:executing-plans for `inline`. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close register rows 23-26 of the darkmem mirror: resume a stopped multi-batch ledger import, count a plan with an absolute ledger identity as finished, run the Stop push in the background, and let the cockpit tell a timeout from a missing node by the engine's wording.

**Architecture:** Four file-disjoint fixes in dr-forge, each with its own tests, then one release bump. The ledger and identity fixes live in the darkmem-sync Node modules and `scripts/next-step`; the Stop push moves from `turn-end.sh` into a new async hook script whose bound lives in `lib/darkmem-hook.sh`, and `push` learns to wait for the mirror lock; the cockpit change is confined to `readRoots`.

**Tech Stack:** Node.js ESM (`node:test`), bash, Claude Code mod (TSX, `claude plugin test`), jq.

**Spec:** docs/superpowers/specs/2026-10-14-darkmem-mirror-open-rows-design.md

**Execution:** inline — `claude --model sonnet --effort high` — 3 of 7 tasks are heavy (not a majority); the highest self-implemented total is 3 (medium), raised to high because tasks are delegated

**Plan review:** 2026-10-14 — dr-superpowers:judge-opus — executability 17 / coherence 18 / coverage 17 / assumptions 16 (round 2)

**Parallelism:** sequential — the spec chose sequential execution; the work is small and the release bump touches every manifest

> **External executors:** codex

## Global Constraints

- Working directory: every `Run:` command and every Commit step runs from `plugins/dr-forge/` of the checkout the plan executes in. Paths in **Files:** blocks and in commands are relative to it, except `docs/…` paths, which are relative to the repository root. A command that needs the repository root runs it in a subshell: `(cd ../.. && …)`. Never use an absolute `/root/…` path.
- Commit as `Darkraise <quangtc94@gmail.com>`: `git -c user.name=Darkraise -c user.email=quangtc94@gmail.com commit …`. No `Co-Authored-By:`, `Claude-Session:` or "Generated with" lines, and no statement that an AI wrote the work.
- Commit subjects: `<type>(<scope>): <subject>`, type one of feat|fix|docs|style|refactor|test|chore|perf, subject at most 50 characters, imperative, no trailing period.
- Comments: none unless the why is non-obvious; never reference the task, the plan or a register row in code.
- Every test, validation and `claude` CLI command runs under an explicit `timeout` (git commands are exempt); kill anything a step starts before the step ends. A command piped into `tail` or `grep` is written so its own exit status is still checked.
- The darkmem-sync suites need localhost listeners (the stub server); run them on the host, not in a sandbox that denies them.
- Keep the Claude and Codex manifest versions equal (`.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`).
- Preserve existing `DCC_*` variables and statusline user storage paths (repository rule; nothing here should touch them).

## Contracts

- **`ledgerPieces(text) → string[]`** (Task 3), exported from `scripts/lib/darkmem-mirror.mjs`: `splitAtBlankLines(text).flatMap(piece => splitAtLimit(piece))`. The only splitter `importLedger` and the move's stopped-import check use.
- **`importLedger(context, roots, ledger, resume = null)`** (Task 3), `scripts/lib/darkmem-import.mjs`: `resume` is `{ id, lastSeq, from }` or null/undefined. With it, pieces before index `from` are skipped and every append carries `expectedLastSeq`, starting at `lastSeq` and then each answer's `last_seq`; a 409 or 422 records `sdd/<slug>/progress.md: darkmem refused an entry: <detail>` in `report.failures`, sets `ledger.id = null` and returns.
- **`checkProgressTargets(...) → { problems, filed, partial }`** (Task 3), `scripts/lib/darkmem-progress-move.mjs`: `partial` is a `Map<slug, { id, lastSeq, from }>`.
- **`DARKMEM_SYNC_LOCK_WAIT_MS`** (Task 4): how long `darkmem-sync push` waits for a held mirror lock, in milliseconds; unset, empty or `0` means 100000. Only `push` reads it.
- **`scripts/darkmem-stop-push.sh`** (Task 5): the async Stop hook; reads the Stop payload on stdin, prints nothing, exits 0.
- **`_darkmem_watchdog SECONDS CMD...`** and **`_darkmem_bounded SECONDS CMD...`** (Task 5), `scripts/lib/darkmem-hook.sh`: run CMD, killing it and its children after SECONDS; `_darkmem_bounded` uses GNU `timeout` when present, else `_darkmem_watchdog`. Both return CMD's exit status.
- **`plan_name ROOT NAME`** (Task 2), `scripts/next-step`: prints NAME, or for an absolute NAME its name from the roots.
- **`TIMED_OUT`** (Task 6), `hooks/cockpit/register.tsx`: `/still running after/i`.

## Assumptions (evidence)

- `$.process.run` rejects both when the command cannot start and when it outlives `timeoutMs`, resolving every exit code otherwise — `claude-code.d.ts` (bundled plugin-authoring, Claude Code 2.1.296), `process.run` doc comment.
- The engine words the two rejections differently — probe run 2026-10-14 on Claude Code 2.1.299 (throwaway mod in the session scratchpad, `claude -p` with `--plugin-dir`): missing command `HooksError: runprobe: $.process.run(dr-forge-no-such-command) failed to start: ENOENT: Executable not found in $PATH: "dr-forge-no-such-command"`; timeout `HooksError: runprobe: $.process.run(sleep) aborted: still running after 500ms`; neither carries a `code`.
- Async command hooks are not awaited, cannot block, are not bounded by `timeout`, and run in parallel with the other matching hooks — https://code.claude.com/docs/en/hooks.md (read 2026-10-14).
- `darkmem-sync` refuses at once when the mirror lock is held — `scripts/lib/darkmem-sync.mjs:211-221`.
- The stub server's `expected_last_seq` check is per entry kind and answers 409 on a mismatch; a closed workstream reopens on append — `tests/darkmem-sync/stub-server.mjs:131-150`.
- Reconcile moves documents before progress and the documents move stages `git rm -r` of the docs directory — `scripts/lib/darkmem-reconcile.mjs:15`, `:267`.
- Planning ruling: the spec has `_forge_name_of` gain the primary checkout's bases; this plan puts that fallback in `next-step`'s `plan_name` instead, so `forge_name`'s other callers keep their behaviour. `tests/roots.test.sh` is therefore unchanged.
- Planning ruling: the macOS bound for the background push lives in `_darkmem_run` (via `_darkmem_bounded`), so session start's reconcile and pull are bounded the same way where GNU `timeout` is missing.
- Task 5's `_darkmem_watchdog`, run verbatim in a scratch shell on 2026-10-14 (bash 5, Linux): a command finishing in time keeps stdout, stderr and exit status 3; `sleep 30` behind `bash -c` is stopped after 1 s with status 143, its child is gone, nothing reaches stderr, and no process is left. macOS's bash 3.2 is unverified; no CI shard runs macOS.
- Not changed, on purpose (round-1 plan review): the primary-checkout fallback stays out of `roots.sh`'s `_forge_name_of`. There it would let every `forge_name` caller in a worktree turn a primary-checkout path into a relative name that resolves to a different file in the worktree. `plan_name` applies it only to completed-plan lookups, with the same logical-then-physical retry `forge_name` uses.
- Known gap: macOS's bash 3.2 cannot be exercised here (no macOS host, no macOS CI shard). Task 5 tests the watchdog and `_darkmem_bounded`'s fallback to it on Linux bash with GNU `timeout` hidden from `PATH`.
- `darkmem-stop-push.sh` wraps config discovery (`forge_project`) and the push in one `_darkmem_bounded 100`, so a stalled preflight is cut off at 100 s. The push inside starts its own process group under its own 100 s bound, which the outer kill does not reach, so the worst case is the config lookup's time plus 100 s; the bound mechanism is what Task 5 tests, since a stalled `forge_project` cannot be staged without editing it.
- Release version 2.3.1: these are fixes to 2.3.0 behaviour.

## Task index

1. planFinished maps absolute ledger identities
2. next-step maps absolute plan names
3. Resume a stopped ledger import
4. push waits for the mirror lock
5. Run the Stop push as an async hook
6. Cockpit reads a timeout by its wording
7. Release 2.3.1

---

### Task 1: planFinished maps absolute ledger identities

**Files:**
- Modify: `scripts/lib/darkmem-reconcile.mjs:112-122`
- Test: `tests/darkmem-sync/reconcile-progress.test.mjs`

**Interfaces:**
- Consumes: none
- Produces: none

**Items:** 24

**Implementer:** dr-superpowers:impl-sonnet-medium
**Evaluation:** files 1 - spec 0 - coupling 0 - risk 2 = 3

- [ ] **Step 1: Write the failing tests**

Append to `tests/darkmem-sync/reconcile-progress.test.mjs` (it already imports `fs`, `path`, `test`, `assert`, `scratch`, `write`, and defines `setup`):

```js
const ABSOLUTE_LEDGER = file => `# SDD ledger — plan: ${file}\nTask 1: complete (commits aaaa..bbbb)\n`;

test("an absolute ledger identity into the checkout counts as finished after the documents move removed it", async t => {
  const s = await setup(t, "darkmem");
  write(path.join(s.home, ".dr-forge", "config.json"), JSON.stringify({ darkmem: { url: s.stub.url, api_key_env: "DARKMEM_API_KEY", repos: { [s.repo]: { project: "proj" } } } }));
  write(path.join(s.repo, ".forge", "sdd", "p1", "progress.md"), ABSOLUTE_LEDGER(path.join(s.repo, "docs", "forge", "plans", "p1.md")));
  const result = await s.reconcile();
  assert.equal(result.code, 0, result.stdout + result.stderr);
  assert.match(result.stdout, /^darkmem-sync reconcile: documents moved to darkmem$/m);
  assert.match(result.stdout, /^darkmem-sync reconcile: progress moved to darkmem$/m);
  assert.equal(fs.existsSync(path.join(s.repo, "docs", "forge", "plans", "p1.md")), false, "the documents move ran first");
});

test("a worktree's ledger whose absolute identity points into the primary checkout counts as finished", async t => {
  const s = await setup(t, "darkmem");
  write(path.join(s.worktree, ".forge", "sdd", "p2", "progress.md"), ABSOLUTE_LEDGER(path.join(s.repo, "docs", "forge", "plans", "p2.md")));
  const result = await s.reconcile();
  assert.equal(result.code, 0, result.stdout + result.stderr);
  assert.match(result.stdout, /^darkmem-sync reconcile: progress moved to darkmem$/m);
});

test("an absolute ledger identity under no root stays in progress and is named, even beside a completed.md naming it", async t => {
  const s = await setup(t, "darkmem");
  const elsewhere = path.join(scratch("dms-elsewhere-"), "docs", "forge", "plans", "p1.md");
  write(path.join(path.dirname(elsewhere), "completed.md"), `- \`${elsewhere}\`\n`);
  write(path.join(s.repo, ".forge", "sdd", "p1", "progress.md"), ABSOLUTE_LEDGER(elsewhere));
  const result = await s.reconcile();
  assert.equal(result.code, 1, result.stdout + result.stderr);
  assert.ok(result.stdout.includes(`darkmem-sync reconcile: progress stay local (configured darkmem): a plan is in progress: ${elsewhere}\n`), result.stdout);
});

test("an absolute ledger identity through a symbolic-linked docs directory is named from its physical path", { skip: process.platform === "win32" && "directory symbolic links need privileges on Windows" }, async t => {
  const s = await setup(t, "darkmem");
  const outside = path.join(scratch("dms-docs-"), "forge");
  fs.renameSync(path.join(s.repo, "docs", "forge"), outside);
  fs.symlinkSync(outside, path.join(s.repo, "docs", "forge"), "dir");
  write(path.join(s.repo, ".forge", "sdd", "p1", "progress.md"), ABSOLUTE_LEDGER(path.join(outside, "plans", "p1.md")));
  const result = await s.reconcile();
  assert.equal(result.code, 0, result.stdout + result.stderr);
  assert.match(result.stdout, /^darkmem-sync reconcile: progress moved to darkmem$/m);
});
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `timeout 300 node --test --test-timeout=60000 --test-name-pattern="absolute" tests/darkmem-sync/reconcile-progress.test.mjs`
Expected: all four tests FAIL. The first, second and fourth refuse with exit code 1 (`… stay local (configured darkmem): a plan is in progress: /…/plans/p1.md` or `p2.md`); the third moves (exit 0), because today the absolute spelling matches the `completed.md` beside it.

- [ ] **Step 3: Write the implementation**

In `scripts/lib/darkmem-reconcile.mjs`, replace the block

```js
// Matched on the backticked name, as plan_finished does, so one plan's name
// that is a substring of another's cannot claim its outcome.
function planFinished(cfg, checkout, name) {
  let text;
  try {
    text = fs.readFileSync(path.join(path.dirname(planFile(cfg, checkout, name)), "completed.md"), "utf8");
  } catch {
    return false;
  }
  return nameSpellings(name).some(spelling => text.includes(`\`${spelling}\``));
}
```

with

```js
const realOr = file => {
  try {
    return fs.realpathSync(file);
  } catch {
    return path.resolve(file);
  }
};

// The name an absolute ledger identity stands for, computed from the roots and
// never by searching for a docs segment (as pathToUri does): under the docs
// root in use, then this checkout's docs directory and top level, then the
// primary checkout's, tried as written and then with symbolic links resolved.
// A relative name, or an absolute one under no root, is unchanged.
function rootedName(cfg, checkout, name) {
  if (!path.isAbsolute(name)) return name;
  const bases = [
    [forgeDir("docs", checkout), DOCS],
    [checkout, null],
    [forgeDir("docs", cfg.repoRoot), DOCS],
    [cfg.repoRoot, null],
  ];
  if (cfg.documents.applied === "darkmem") bases.unshift([path.join(cfg.mirror, "superpowers"), DOCS]);
  for (const resolve of [file => path.resolve(file), realOr]) {
    for (const [base, prefix] of bases) {
      const rel = path.relative(resolve(base), resolve(name));
      if (rel && rel !== ".." && !rel.startsWith(`..${path.sep}`) && !path.isAbsolute(rel)) {
        const posix = rel.split(path.sep).join("/");
        return prefix ? `${prefix}/${posix}` : posix;
      }
    }
  }
  return name;
}

// Matched on the backticked name, as plan_finished does, so one plan's name
// that is a substring of another's cannot claim its outcome. An absolute
// identity is mapped first and completed.md is found from the mapped name: the
// directory the absolute path names is gone once the documents have moved. An
// identity no root maps is never finished, whatever lies beside it.
function planFinished(cfg, checkout, identity) {
  const name = rootedName(cfg, checkout, identity);
  if (path.isAbsolute(name)) return false;
  let text;
  try {
    text = fs.readFileSync(path.join(path.dirname(planFile(cfg, checkout, name)), "completed.md"), "utf8");
  } catch {
    return false;
  }
  return nameSpellings(name).some(spelling => text.includes(`\`${spelling}\``));
}
```

`DOCS` (`"docs/forge"`), `fs`, `path`, `forgeDir`, `planFile` and `nameSpellings` already exist in this file. `forgeDir("docs", dir)` answers `docs/superpowers` where only that pre-2.0 directory exists; mapping under it with the `docs/forge` prefix is right, because `nameSpellings` also tries the `docs/superpowers` spelling.

- [ ] **Step 4: Run the tests to verify they pass, then the whole reconcile suites**

Run: `timeout 300 node --test --test-timeout=60000 --test-name-pattern="absolute" tests/darkmem-sync/reconcile-progress.test.mjs`
Expected: 4 tests PASS (3 on Windows, where the symbolic-link test is skipped).
Run: `timeout 600 node --test --test-timeout=60000 tests/darkmem-sync/reconcile-progress.test.mjs tests/darkmem-sync/reconcile.test.mjs`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/lib/darkmem-reconcile.mjs tests/darkmem-sync/reconcile-progress.test.mjs
git -c user.name=Darkraise -c user.email=quangtc94@gmail.com commit -m "fix(darkmem): map absolute ledger identities"
```

### Task 2: next-step maps absolute plan names

**Files:**
- Modify: `scripts/next-step:87-99`, `scripts/next-step:282`
- Test: `tests/next-step.test.sh`

**Interfaces:**
- Consumes: none
- Produces: `plan_name ROOT NAME` (Contracts)

**Items:** 24

**Implementer:** dr-superpowers:impl-sonnet-low
**Executor:** codex gpt-6.1-sol / low
**Evaluation:** files 1 - spec 0 - coupling 0 - risk 1 = 2

- [ ] **Step 1: Write the failing test**

In `tests/next-step.test.sh`, directly after the block that ends

```bash
printf '# Completed plans\n\n- 2026-01-01 `docs/superpowers/plans/inc1.md` — merged into `main` at abc1234\n' \
  > "$GREPO/docs/superpowers/plans/completed.md"
bash "$HERE/../scripts/register" set "$GREG" 1 doing --assigned docs/superpowers/plans/inc2.md >/dev/null
```

insert

```bash

# An absolute Assigned cell is named from the roots: one naming the plan being
# completed and one naming a finished plan are both stale.
bash "$HERE/../scripts/register" set "$GREG" 1 doing --assigned "$GREPO/docs/superpowers/plans/inc2.md" >/dev/null
bash "$HERE/../scripts/register" set "$GREG" 6 open --assigned "$GREPO/docs/superpowers/plans/inc1.md" >/dev/null
OUT=$(cd "$GREPO" && bash "$SCRIPT" --complete docs/superpowers/plans/inc2.md 2>&1)
has "routing: absolute Assigned cells name finished plans" "$OUT" "Still assigned to a finished plan: #1, #6"
bash "$HERE/../scripts/register" set "$GREG" 1 doing --assigned docs/superpowers/plans/inc2.md >/dev/null
bash "$HERE/../scripts/register" set "$GREG" 6 open --assigned docs/superpowers/plans/inc1.md >/dev/null

# From a linked worktree, an Assigned cell naming the primary checkout's copy
# of a finished plan is stale too. The worktree holds the committed register
# and completed.md (row 1 on inc2, row 6 on inc1, inc1 recorded).
GWT="$TMP/routing-wt"
git -C "$GREPO" worktree add -q -b routing-side "$GWT"
bash "$HERE/../scripts/register" set "$GWT/docs/superpowers/registers/lane.md" 6 open --assigned "$GREPO/docs/superpowers/plans/inc1.md" >/dev/null
OUT=$(cd "$GWT" && bash "$SCRIPT" --complete docs/superpowers/plans/inc2.md 2>&1)
has "routing: a worktree names the primary checkout's absolute plan path" "$OUT" "Still assigned to a finished plan: #1, #6"
git -C "$GREPO" worktree remove --force "$GWT"
git -C "$GREPO" branch -q -D routing-side
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `timeout 300 bash tests/next-step.test.sh 2>&1 | grep -E "absolute Assigned|FAIL" | head`
Expected: `FAIL` on "routing: absolute Assigned cells name finished plans" (row 1 routes back to `inc2.md` instead) and on "routing: a worktree names the primary checkout's absolute plan path". Read the suite's own result line too: `timeout 300 bash tests/next-step.test.sh >/dev/null 2>&1; echo "exit=$?"` prints a non-zero exit.

- [ ] **Step 3: Write the implementation**

In `scripts/next-step`, replace

```bash
plan_finished() {
  local f s
  f="$(dirname "$(forge_resolve "$2" "$1")")/completed.md"
  [ -f "$f" ] || return 1
  while IFS= read -r s; do
    grep -qF "\`$s\`" "$f" && return 0
  done < <(forge_name_spellings "$2")
  return 1
}
```

with

```bash
plan_finished() {
  local f s name
  name=$(plan_name "$1" "$2")
  case $name in /*|[A-Za-z]:/*|[A-Za-z]:\\*) return 1 ;; esac
  f="$(dirname "$(forge_resolve "$name" "$1")")/completed.md"
  [ -f "$f" ] || return 1
  while IFS= read -r s; do
    grep -qF "\`$s\`" "$f" && return 0
  done < <(forge_name_spellings "$name")
  return 1
}

# plan_name ROOT NAME — NAME; an absolute NAME is named from the roots instead
# (forge_name), else from the primary checkout's top level, as written and then
# in its physical form, so a worktree's register or ledger naming the primary's
# copy still finds its plan. Never a search for a docs segment; an absolute name
# under no root is printed unchanged, and plan_finished never counts it. Only
# an absolute NAME goes through forge_name, which would make an existing
# relative name absolute.
plan_name() {
  local name=$2 common primary physical spelling
  case $name in
    /*|[A-Za-z]:/*|[A-Za-z]:\\*) ;;
    *) printf '%s\n' "$name"; return 0 ;;
  esac
  name=$(forge_name "$name" "$1")
  case $name in
    /*|[A-Za-z]:/*|[A-Za-z]:\\*) ;;
    *) printf '%s\n' "$name"; return 0 ;;
  esac
  if common=$(git -C "$1" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) \
    && primary=$(git -C "$(dirname "$common")" rev-parse --show-toplevel 2>/dev/null); then
    primary=$(_forge_path "$primary")
    physical=$(_forge_path "$(cd "$(dirname "$name")" 2>/dev/null && pwd -P)/$(basename "$name")")
    for spelling in "$name" "$physical"; do
      case $spelling in "$primary"/*) printf '%s\n' "${spelling#"$primary"/}"; return 0 ;; esac
    done
  fi
  printf '%s\n' "$name"
}
```

Then replace the line

```bash
        elif [ "$(forge_name_key "$a")" = "$(forge_name_key "$rel")" ] || plan_finished "$root" "$a"; then
```

with

```bash
        elif [ "$(forge_name_key "$(plan_name "$root" "$a")")" = "$(forge_name_key "$rel")" ] || plan_finished "$root" "$a"; then
```

Update the comment above `plan_finished` (`# plan_finished ROOT NAME — …`) by appending one sentence: `An absolute NAME is named from the roots first (plan_name); one no root maps never counts.`

The `case` patterns are the same absolute-path test `forge_resolve` uses (`/*`, `C:/…`, `C:\…`). `_forge_path` comes from `lib/roots.sh`, which `next-step` already sources; it turns a Git Bash `/c/…` path into git's `C:/…` form.

- [ ] **Step 4: Run the suite to verify it passes**

Run: `timeout 300 bash tests/next-step.test.sh; echo "exit=$?"`
Expected: every check passes, including both new routing checks; `exit=0`.

- [ ] **Step 5: Commit**

```bash
git add scripts/next-step tests/next-step.test.sh
git -c user.name=Darkraise -c user.email=quangtc94@gmail.com commit -m "fix(next-step): name absolute plan paths by roots"
```

### Task 3: Resume a stopped ledger import

**Files:**
- Modify: `scripts/lib/darkmem-mirror.mjs` (after `splitAtBlankLines`)
- Modify: `scripts/lib/darkmem-import.mjs:11-14`, `:50-66`
- Modify: `scripts/lib/darkmem-progress-move.mjs:12-15`, `:84-117`, `:227`
- Test: `tests/darkmem-sync/mirror.test.mjs`, `tests/darkmem-sync/reconcile-progress.test.mjs`

**Interfaces:**
- Consumes: none
- Produces: `ledgerPieces`, `importLedger(…, resume)`, `checkProgressTargets(...) → { problems, filed, partial }` (Contracts)

**Items:** 23

**Implementer:** dr-superpowers:impl-sonnet-high
**Evaluation:** files 2 - spec 0 - coupling 1 - risk 2 = 5

- [ ] **Step 1: Write the failing tests**

In `tests/darkmem-sync/mirror.test.mjs`, add `MAX_ENTRY_CHARS` and `ledgerPieces` to the existing import from `../../scripts/lib/darkmem-mirror.mjs`, then append:

```js
test("ledgerPieces cuts at blank lines, then at the entry limit, and concatenates back", () => {
  const text = `# SDD ledger\n\nTask 1: a\n\n${"x".repeat(MAX_ENTRY_CHARS + 10)}\n`;
  const pieces = ledgerPieces(text);
  assert.equal(pieces.join(""), text);
  assert.deepEqual(pieces.slice(0, 2), ["# SDD ledger\n\n", "Task 1: a\n\n"]);
  assert.equal(pieces.length, 4);
  assert.ok(pieces.every(piece => piece.length <= MAX_ENTRY_CHARS));
});
```

In `tests/darkmem-sync/reconcile-progress.test.mjs`, add `import { ledgerPieces } from "../../scripts/lib/darkmem-mirror.mjs";` below the existing imports, then append:

```js
// 251 pieces: a stopped import holding the first 100 leaves two batches to send.
const LONG = `# SDD ledger — plan: docs/forge/plans/p1.md\n\n${Array.from({ length: 250 }, (_, i) => `Task ${i + 1}: complete (commits aaaa..bbbb)\n\n`).join("")}`;
const FIRST_BATCH = () => ledgerPieces(LONG).slice(0, 100).map(body => ({ kind: "ledger", body }));
const ledgerOf = ws => ws.entries.filter(e => e.kind === "ledger");
const ledgerAppends = s => s.stub.db.requests.filter(r => r.method === "POST" && r.path === "/api/v1/worklog/entries" && r.body.entries[0].kind === "ledger");

test("a move stopped after its first append batch resumes the import", async t => {
  const s = await setup(t, "darkmem");
  write(path.join(s.repo, ".forge", "sdd", "p1", "progress.md"), LONG);
  await s.seed.append({ project: "proj", workstream: "p1", entries: FIRST_BATCH() });
  const result = await s.reconcile();
  assert.equal(result.code, 0, result.stdout + result.stderr);
  assert.match(result.stdout, /^darkmem-sync reconcile: progress moved to darkmem$/m);
  const ws = s.stub.db.workstreams.find(w => w.key === "p1");
  assert.equal(ws.state, "closed");
  assert.equal(ledgerOf(ws).map(e => e.body).join(""), LONG);
  assert.equal(ledgerOf(ws).length, ledgerPieces(LONG).length);
  const resumed = ledgerAppends(s).slice(1);
  assert.equal(resumed.length, 2, "the two remaining batches");
  assert.equal(resumed[0].body.expected_last_seq, ledgerOf(ws)[99].seq, "the first resumed batch follows the stopped import");
  assert.equal(resumed[1].body.expected_last_seq, ledgerOf(ws)[199].seq, "the next batch follows the answer to the one before");
  assert.equal(read(path.join(s.workRoot, "sdd", "p1", "progress.md")), LONG);
});

test("another writer's append during a resumed import refuses the move, and nothing local moves", async t => {
  const s = await setup(t, "darkmem");
  const ledger = path.join(s.repo, ".forge", "sdd", "p1", "progress.md");
  write(ledger, LONG);
  await s.seed.append({ project: "proj", workstream: "p1", entries: FIRST_BATCH() });
  let competed = false;
  s.stub.db.onRequest = (method, pathname) => {
    if (competed || method !== "POST" || pathname !== "/api/v1/worklog/entries") return;
    competed = true;
    const ws = s.stub.db.workstreams.find(w => w.key === "p1");
    ws.entries.push({ id: "competing", seq: s.stub.db.nextSeq++, run_key: "other", kind: "ledger", body: "another writer\n", properties: {}, created_at: new Date().toISOString() });
  };
  const result = await s.reconcile();
  assert.equal(result.code, 1, result.stdout + result.stderr);
  assert.ok(result.stdout.includes("darkmem-sync reconcile: progress stay local (configured darkmem): darkmem refused part of the progress; nothing was moved locally\n"), result.stdout);
  assert.match(result.stdout, /^ {2}sdd\/p1\/progress\.md: darkmem refused an entry: expected the newest ledger entry to be seq \d+, but it is \d+$/m);
  assert.equal(s.stores().progress, "local");
  assert.deepEqual(movedAside(s.repo), []);
  assert.equal(read(ledger), LONG);
  assert.equal(fs.existsSync(path.join(s.workRoot, "sdd", "p1", "progress.md")), false);
});

test("an open workstream holding no ledger entries yet is resumed from the start", async t => {
  const s = await setup(t, "darkmem");
  write(path.join(s.repo, ".forge", "sdd", "p1", "progress.md"), LEDGER("p1"));
  await s.seed.append({ project: "proj", workstream: "p1", entries: [{ kind: "checkpoint", body: "## State\n- Plan: `docs/forge/plans/p1.md`\n" }] });
  const result = await s.reconcile();
  assert.equal(result.code, 0, result.stdout + result.stderr);
  const ws = s.stub.db.workstreams.find(w => w.key === "p1");
  assert.equal(ws.state, "closed");
  assert.equal(ledgerOf(ws).map(e => e.body).join(""), LEDGER("p1"));
});

for (const [name, prepare] of [
  ["a closed workstream holding a prefix", async s => {
    const { workstream } = await s.seed.append({ project: "proj", workstream: "p1", entries: FIRST_BATCH() });
    await s.seed.updateWorkstream(workstream.id, { state: "closed", retain: true });
  }],
  ["a prefix ending inside a piece", async s => {
    await s.seed.append({ project: "proj", workstream: "p1", entries: [{ kind: "ledger", body: LONG.slice(0, 20) }] });
  }],
  ["a different ledger", async s => {
    await s.seed.append({ project: "proj", workstream: "p1", entries: [{ kind: "ledger", body: "# SDD ledger — plan: elsewhere\n" }] });
  }],
]) {
  test(`${name} refuses the move and sends nothing`, async t => {
    const s = await setup(t, "darkmem");
    write(path.join(s.repo, ".forge", "sdd", "p1", "progress.md"), LONG);
    await prepare(s);
    const appends = () => s.stub.db.requests.filter(r => r.method === "POST" && r.path === "/api/v1/worklog/entries").length;
    const before = appends();
    const result = await s.reconcile();
    assert.equal(result.code, 1, result.stdout + result.stderr);
    assert.match(result.stdout, /^darkmem-sync reconcile: progress stay local \(configured darkmem\): darkmem or the mirror already holds different progress$/m);
    assert.match(result.stdout, /^ {2}sdd\/p1\/progress\.md: darkmem already holds a different ledger for workstream p1$/m);
    assert.equal(appends(), before);
    assert.equal(read(path.join(s.repo, ".forge", "sdd", "p1", "progress.md")), LONG);
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `timeout 600 node --test --test-timeout=60000 tests/darkmem-sync/mirror.test.mjs tests/darkmem-sync/reconcile-progress.test.mjs; echo "exit=$?"`
Expected: FAIL, non-zero exit — both files stop at load with `SyntaxError: The requested module '../../scripts/lib/darkmem-mirror.mjs' does not provide an export named 'ledgerPieces'`, so no test in them runs yet. The behaviour checks come in Step 4: the resume tests must pass there, and the three "refuses the move and sends nothing" tests guard refusals that already hold today.

- [ ] **Step 3: Write the implementation**

In `scripts/lib/darkmem-mirror.mjs`, directly after the `splitAtBlankLines` function, add:

```js
// A ledger's import entries. Import and the move's stopped-import check both
// split with this, so the entries a stopped import sent are the first pieces
// of the same ledger's split.
export function ledgerPieces(text) {
  return splitAtBlankLines(text).flatMap(piece => splitAtLimit(piece));
}
```

In `scripts/lib/darkmem-import.mjs`, change the import list from `./darkmem-mirror.mjs` so it names `ledgerPieces` instead of `splitAtBlankLines, splitAtLimit`:

```js
import {
  MAX_ENTRIES_PER_APPEND, RESERVED_DIRS, decodeUtf8, emptyState, ledgerFiles, ledgerPieces, ledgerPlanPath, listDocumentFiles, propertiesFor,
  unsupportedPlanDirs, uriToLocal,
} from "./darkmem-mirror.mjs";
```

and replace the whole `importLedger` function with:

```js
// `resume` continues a stopped import of the same ledger: { id, lastSeq, from }
// names darkmem's open workstream, its newest ledger entry and how many pieces
// it already holds. Each later batch is sent under the last sequence number
// darkmem answered, so another writer's append is a 409, not interleaved lines.
export async function importLedger({ cfg, client, report }, roots, ledger, resume = null) {
  const pieces = ledgerPieces(ledger.text);
  const properties = { ...propertiesFor(roots, ledger.slug, ledgerPlanPath(ledger.text)), imported_mtime: ledger.mtime };
  let lastSeq = resume?.lastSeq;
  ledger.id = resume?.id ?? null;
  for (let i = resume?.from ?? 0; i < pieces.length; i += MAX_ENTRIES_PER_APPEND) {
    const entries = pieces.slice(i, i + MAX_ENTRIES_PER_APPEND).map(body => ({ kind: "ledger", body }));
    try {
      const answer = await client.append({ project: cfg.project, workstream: ledger.slug, properties, entries, expectedLastSeq: lastSeq });
      ledger.id = answer.workstream.id;
      if (resume) lastSeq = answer.last_seq;
    } catch (error) {
      if (!(error instanceof HttpError && (error.status === 422 || (resume && error.status === 409)))) throw error;
      report.failures.push(`sdd/${ledger.slug}/progress.md: darkmem refused an entry: ${error.detail}`);
      ledger.id = null;
      return;
    }
  }
  await client.updateWorkstream(ledger.id, { state: "closed", retain: true });
  report.counts.workstreams += 1;
}
```

Without `resume`, `lastSeq` stays `undefined`, so `client.append` sends no `expected_last_seq` and the first-import path is unchanged.

In `scripts/lib/darkmem-progress-move.mjs`, add `ledgerPieces` to the import list from `./darkmem-mirror.mjs` (keep the list alphabetical: `… isoMicros, ledgerFiles, ledgerPieces, listDocumentFiles, …`). Replace the comment and function `checkProgressTargets` (from `// What darkmem and the mirror already hold at each source's place.` through its closing `}`) with:

```js
// How many of the ledger's import pieces darkmem's bytes are, when they are a
// proper prefix ending on a piece boundary; -1 otherwise.
function stoppedImport(held, buffer) {
  if (held.length >= buffer.length || !buffer.subarray(0, held.length).equals(held)) return -1;
  let at = 0;
  for (const [k, piece] of ledgerPieces(decodeUtf8(buffer)).entries()) {
    if (at === held.length) return k;
    if (at > held.length) return -1;
    at += Buffer.byteLength(piece, "utf8");
  }
  return -1;
}

// What darkmem and the mirror already hold at each source's place. A ledger
// darkmem holds byte for byte is already filed, and one an open workstream
// holds the first pieces of is a stopped import to resume, so a move stopped
// part-way runs again; any other existing copy that differs is a problem, so
// nothing is overwritten.
export async function checkProgressTargets({ cfg, client }, sources) {
  const problems = [];
  const filed = new Map();
  const partial = new Map();
  for (const item of sources) {
    const target = local(path.join(cfg.mirror, "work"), item.rel);
    if (!fs.existsSync(target)) continue;
    let held;
    try {
      held = fs.readFileSync(target);
    } catch (error) {
      problems.push(`${target}: could not be read (${error.code})`);
      continue;
    }
    if (!held.equals(item.buffer)) problems.push(`${target}: the mirror already holds a different copy of ${item.rel}`);
  }
  const notes = new Map((await client.manifest(cfg.project, `${DOC_PREFIX}/handoff`)).map(doc => [doc.uri, doc.content_hash]));
  for (const item of sources) {
    if (item.kind === "handoff") {
      const hash = notes.get(item.uri);
      if (hash !== undefined && hash !== sha256(item.buffer)) problems.push(`${item.uri}: darkmem already holds a different handoff note`);
    } else if (item.kind === "ledger") {
      const existing = await client.resume(cfg.project, item.slug);
      if (!existing) continue;
      const { text, lastSeq } = await remoteLedger(client, existing.workstream.id);
      const held = Buffer.from(text, "utf8");
      const from = existing.workstream.state === "closed" ? -1 : stoppedImport(held, item.buffer);
      if (held.equals(item.buffer)) filed.set(item.slug, existing.workstream.id);
      else if (from >= 0) partial.set(item.slug, { id: existing.workstream.id, lastSeq, from });
      else problems.push(`${item.rel}: darkmem already holds a different ledger for workstream ${item.slug}`);
    }
  }
  return { problems, filed, partial };
}
```

In `progressToDarkmem`, replace

```js
        await importLedger({ ...context, report }, checkoutRoots(cfg, item.stateDir), ledger);
```

with

```js
        await importLedger({ ...context, report }, checkoutRoots(cfg, item.stateDir), ledger, checked.partial.get(item.slug));
```

- [ ] **Step 4: Run the tests to verify they pass, then the darkmem-sync suite**

Run: `timeout 600 node --test --test-timeout=60000 tests/darkmem-sync/mirror.test.mjs tests/darkmem-sync/reconcile-progress.test.mjs; echo "exit=$?"`
Expected: all PASS, `exit=0`.
Run: `timeout 900 bash tests/darkmem-sync.test.sh; echo "exit=$?"`
Expected: all suites PASS, `exit=0` (the import suite's callers of `importLedger` pass no `resume` and are unchanged).

- [ ] **Step 5: Commit**

```bash
git add scripts/lib/darkmem-mirror.mjs scripts/lib/darkmem-import.mjs scripts/lib/darkmem-progress-move.mjs tests/darkmem-sync/mirror.test.mjs tests/darkmem-sync/reconcile-progress.test.mjs
git -c user.name=Darkraise -c user.email=quangtc94@gmail.com commit -m "fix(darkmem): resume a stopped ledger import"
```

### Task 4: push waits for the mirror lock

**Files:**
- Modify: `scripts/lib/darkmem-sync.mjs:211-216`
- Test: `tests/darkmem-sync/cli.test.mjs`

**Interfaces:**
- Consumes: none
- Produces: `DARKMEM_SYNC_LOCK_WAIT_MS` (Contracts)

**Items:** 25

**Implementer:** dr-superpowers:impl-sonnet-medium
**Evaluation:** files 1 - spec 0 - coupling 0 - risk 3 = 4

- [ ] **Step 1: Write the failing test**

In `tests/darkmem-sync/cli.test.mjs`, add `import { startStub } from "./stub-server.mjs";` below the existing imports (the file already imports `fs`, `path`, `test`, `assert`, and `makeHome`, `makeRepo`, `run`, `write` from `./helpers.mjs`), then append. The ledger sits in the mirror with no sync state, so `push` sends it as a new workstream, as the hooks suite's Stop test does:

```js
test("push waits for a held lock and then runs; past its wait it refuses as before", async t => {
  const stub = await startStub();
  t.after(() => stub.close());
  const repo = makeRepo();
  const { env, mirror, workRoot } = makeHome({ repo, url: stub.url });
  const ledger = "# SDD ledger — plan: docs/forge/plans/p1.md\nTask 1: a\n";
  write(path.join(workRoot, "sdd", "p1", "progress.md"), ledger);
  const appended = () => stub.db.workstreams.find(w => w.key === "p1")?.entries.map(e => e.body).join("") ?? null;
  const lock = path.join(mirror, ".sync.lock");
  fs.mkdirSync(lock, { recursive: true });
  const released = setTimeout(() => fs.rmdirSync(lock), 1500);
  t.after(() => clearTimeout(released));
  const started = Date.now();
  const waited = await run(["push"], { cwd: repo, env: { ...env, DARKMEM_SYNC_LOCK_WAIT_MS: "20000" } });
  assert.equal(waited.code, 0, waited.stdout + waited.stderr);
  assert.ok(Date.now() - started >= 1400, "push waited for the lock");
  assert.equal(appended(), ledger, "the push ran once the lock was free");
  assert.equal(fs.existsSync(lock), false, "push released the lock it took");
  fs.appendFileSync(path.join(workRoot, "sdd", "p1", "progress.md"), "Task 1: complete\n");
  fs.mkdirSync(lock, { recursive: true });
  const again = Date.now();
  const refused = await run(["push"], { cwd: repo, env: { ...env, DARKMEM_SYNC_LOCK_WAIT_MS: "1500" } });
  const waitedFor = Date.now() - again;
  assert.equal(refused.code, 1);
  assert.ok(waitedFor >= 1400 && waitedFor < 15000, `refused after its wait, not at once or never (${waitedFor} ms)`);
  assert.match(refused.stderr, /another darkmem-sync \(an unknown process\) holds .*\.sync\.lock; if that process is gone, remove the directory/);
  assert.equal(appended(), ledger, "a refused push sends nothing");
  fs.rmdirSync(lock);
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `timeout 300 node --test --test-timeout=60000 --test-name-pattern="push waits" tests/darkmem-sync/cli.test.mjs`
Expected: FAIL — the first `push` exits 1 at once with "another darkmem-sync … holds".

- [ ] **Step 3: Write the implementation**

In `scripts/lib/darkmem-sync.mjs`, add above `async function main(`:

```js
// The Stop hook's push runs in the background, so a skill's push at a stop
// point can meet its lock: push waits for it, every other command refuses at
// once.
async function lockForPush(mirror, env) {
  const deadline = Date.now() + (Number(env.DARKMEM_SYNC_LOCK_WAIT_MS) || 100000);
  for (;;) {
    const release = acquireLock(mirror);
    if (release || Date.now() >= deadline) return release;
    await new Promise(resolve => setTimeout(resolve, Math.min(1000, Math.max(0, deadline - Date.now()))));
  }
}
```

and replace

```js
  const release = acquireLock(cfg.mirror);
```

with

```js
  const release = parsed.name === "push" ? await lockForPush(cfg.mirror, env) : acquireLock(cfg.mirror);
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `timeout 300 node --test --test-timeout=60000 tests/darkmem-sync/cli.test.mjs; echo "exit=$?"`
Expected: all PASS, `exit=0`, including "a held lock is exit 1, and an unreadable state file is exit 2" (status still refuses at once; `run` gives up after 30 s, so a status that waited would fail it).

- [ ] **Step 5: Commit**

```bash
git add scripts/lib/darkmem-sync.mjs tests/darkmem-sync/cli.test.mjs
git -c user.name=Darkraise -c user.email=quangtc94@gmail.com commit -m "fix(darkmem): let push wait for the mirror lock"
```

### Task 5: Run the Stop push as an async hook

**Files:**
- Create: `scripts/darkmem-stop-push.sh`
- Modify: `scripts/lib/darkmem-hook.sh:17-26`, `:76-83`
- Modify: `scripts/turn-end.sh:27-33`
- Modify: `hooks/hooks.json` (the `Stop` group)
- Modify: `README.md:911-912`
- Test: `tests/darkmem-sync/hooks.test.mjs`

**Interfaces:**
- Consumes: `DARKMEM_SYNC_LOCK_WAIT_MS` behaviour (Contracts) — the background push and a skill's push now queue on the lock instead of refusing
- Produces: `scripts/darkmem-stop-push.sh`, `_darkmem_watchdog`, `_darkmem_bounded` (Contracts)

**Items:** 25

**Implementer:** dr-superpowers:impl-sonnet-high
**Evaluation:** files 2 - spec 0 - coupling 1 - risk 2 = 5

- [ ] **Step 1: Write the failing tests**

In `tests/darkmem-sync/hooks.test.mjs`, add `scratch` to the existing `./helpers.mjs` import. Replace the test

```js
test("the hooks are bounded: SessionStart 300 seconds, Stop 120", () => {
  const hooks = JSON.parse(fs.readFileSync(HOOKS_JSON, "utf8")).hooks;
  assert.equal(hooks.SessionStart[0].hooks[0].timeout, 300);
  assert.equal(hooks.Stop[0].hooks[0].timeout, 120);
});
```

with

```js
test("the hooks are bounded: SessionStart 300 seconds, Stop 120, and the darkmem push runs in the background", () => {
  const hooks = JSON.parse(fs.readFileSync(HOOKS_JSON, "utf8")).hooks;
  assert.equal(hooks.SessionStart[0].hooks[0].timeout, 300);
  const [turnEnd, stopPush, ...more] = hooks.Stop[0].hooks;
  assert.match(turnEnd.command, /scripts\/turn-end\.sh/);
  assert.equal(turnEnd.async, false);
  assert.equal(turnEnd.timeout, 120);
  assert.match(stopPush.command, /scripts\/darkmem-stop-push\.sh/);
  assert.equal(stopPush.async, true);
  assert.equal(stopPush.timeout, undefined, "Claude Code does not enforce an async hook's timeout; the push bounds itself");
  assert.deepEqual(more, []);
});
```

Replace the test `"the Stop hook pushes under its session id, a retried stop too, and prints nothing"` (the whole `test(…)` call) with

```js
test("the Stop push sends under its session id, a retried stop too, and prints nothing; turn-end.sh sends nothing", { skip: !hasJq && "jq is not on PATH" }, async t => {
  const s = await setup(t);
  const ledger = path.join(s.home.workRoot, "sdd", "p1", "progress.md");
  write(ledger, "# SDD ledger — plan: docs/forge/plans/p1.md\nTask 1: a\n");
  const payload = active => ({ hook_event_name: "Stop", session_id: "sid-stop", cwd: s.repo, transcript_path: "", stop_hook_active: active });
  const appends = () => s.stub.db.requests.filter(r => r.method === "POST" && r.path === "/api/v1/worklog/entries");
  const requests = s.stub.db.requests.length;
  assert.deepEqual(await runHook("turn-end.sh", payload(false), { cwd: s.repo, env: s.env }), { code: 0, stdout: "", stderr: "" });
  assert.equal(s.stub.db.requests.length, requests, "turn-end.sh makes no darkmem request");
  assert.deepEqual(await runHook("darkmem-stop-push.sh", payload(false), { cwd: s.repo, env: s.env }), { code: 0, stdout: "", stderr: "" });
  assert.equal(appends().length, 1, "the Stop push sent the ledger");
  fs.appendFileSync(ledger, "Task 1: complete (commits abc1234..def5678, review clean)\n");
  assert.deepEqual(await runHook("darkmem-stop-push.sh", payload(true), { cwd: s.repo, env: s.env }), { code: 0, stdout: "", stderr: "" });
  assert.equal(appends().length, 2, "a retried stop pushes the lines written since");
  assert.ok(appends().every(r => r.body.run_key === "sid-stop"));
});

test("the watchdog bounds a command and its children where GNU timeout is missing", async () => {
  const dir = scratch("dmh-wd-");
  const pidFile = path.join(dir, "child.pid");
  const quick = await bash(["-c", '. "$1"; _darkmem_watchdog 5 bash -c "echo out; echo err >&2; exit 3"', "hook-test", LIB], { cwd: dir, env: process.env });
  assert.deepEqual(quick, { code: 3, stdout: "out\n", stderr: "err\n" });
  const started = Date.now();
  const slow = await bash(["-c", '. "$1"; _darkmem_watchdog 1 bash -c "sleep 30 & echo \\$! > \\"\\$0\\"; wait" "$2"', "hook-test", LIB, pidFile], { cwd: dir, env: process.env });
  assert.ok(Date.now() - started < 10000, "the command was stopped at its bound");
  assert.notEqual(slow.code, 0);
  assert.equal(slow.stderr, "", "no job-control notice reaches stderr");
  await new Promise(resolve => setTimeout(resolve, 300));
  assert.throws(() => process.kill(Number(fs.readFileSync(pidFile, "utf8")), 0), { code: "ESRCH" }, "the command's child was killed too");
});

test("_darkmem_bounded falls back to the watchdog where GNU timeout is missing", { skip: process.platform === "win32" && "file symbolic links need privileges on Windows" }, async () => {
  const dir = scratch("dmh-bin-");
  const bin = path.join(dir, "bin");
  fs.mkdirSync(bin);
  for (const tool of ["bash", "sleep"]) {
    fs.symlinkSync(spawnSync("bash", ["-c", `command -v ${tool}`], { encoding: "utf8" }).stdout.trim(), path.join(bin, tool));
  }
  const pidFile = path.join(dir, "child.pid");
  const started = Date.now();
  const result = await bash(["-c", '. "$1"; PATH="$3"; command -v timeout && exit 9; _darkmem_bounded 1 bash -c "sleep 30 & echo \\$! > \\"\\$0\\"; wait" "$2"', "hook-test", LIB, pidFile, bin], { cwd: dir, env: process.env });
  assert.notEqual(result.code, 9, "timeout must not be on the trimmed PATH");
  assert.ok(Date.now() - started < 10000, "the watchdog stopped the command at its bound");
  assert.notEqual(result.code, 0);
  await new Promise(resolve => setTimeout(resolve, 300));
  assert.throws(() => process.kill(Number(fs.readFileSync(pidFile, "utf8")), 0), { code: "ESRCH" }, "the command's child was killed too");
});
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `timeout 600 node --test --test-timeout=120000 tests/darkmem-sync/hooks.test.mjs`
Expected: the bounded-hooks test FAILS (`stopPush` is undefined), the Stop push test FAILS (turn-end.sh still pushes; `darkmem-stop-push.sh` does not exist), and both watchdog tests FAIL (`_darkmem_watchdog: command not found`, `_darkmem_bounded: command not found`).

- [ ] **Step 3: Write the implementation**

In `scripts/lib/darkmem-hook.sh`, replace

```bash
# _darkmem_run DIR SID SECONDS COMMAND — darkmem-sync COMMAND in DIR, bounded
# when GNU timeout exists (macOS ships none; the hook's own timeout bounds it).
_darkmem_run() {
  if command -v timeout >/dev/null 2>&1; then
    (cd "$1" 2>/dev/null && DR_FORGE_SESSION_ID=$2 timeout "$3" bash "$_DARKMEM_HOOK_SCRIPTS/darkmem-sync" "$4" </dev/null)
  else
    (cd "$1" 2>/dev/null && DR_FORGE_SESSION_ID=$2 bash "$_DARKMEM_HOOK_SCRIPTS/darkmem-sync" "$4" </dev/null)
  fi
}
```

with

```bash
# _darkmem_watchdog SECONDS CMD... — CMD, killed with its children after
# SECONDS, where GNU timeout is missing (macOS ships none): an async hook's
# timeout is not enforced, so nothing else would stop it. set -m starts CMD in
# its own process group, which the kill takes whole, node included.
_darkmem_watchdog() {
  local seconds=$1 pid watchdog status
  shift
  set -m
  "$@" &
  pid=$!
  (sleep "$seconds"; kill -TERM -- "-$pid") >/dev/null 2>&1 &
  watchdog=$!
  wait "$pid" 2>/dev/null
  status=$?
  kill -TERM -- "-$watchdog" 2>/dev/null
  wait "$watchdog" 2>/dev/null
  set +m
  return "$status"
}

# _darkmem_bounded SECONDS CMD... — CMD under GNU timeout, else the watchdog.
_darkmem_bounded() {
  if command -v timeout >/dev/null 2>&1; then
    timeout "$@"
  else
    _darkmem_watchdog "$@"
  fi
}

# _darkmem_run DIR SID SECONDS COMMAND — darkmem-sync COMMAND in DIR, bounded.
_darkmem_run() {
  (cd "$1" 2>/dev/null && export DR_FORGE_SESSION_ID=$2 && _darkmem_bounded "$3" bash "$_DARKMEM_HOOK_SCRIPTS/darkmem-sync" "$4" </dev/null)
}
```

and replace the comment

```bash
# darkmem_push_quietly DIR SID — the Stop hook's push. Its stdout is the hook's
# decision JSON, so nothing may reach it.
```

with

```bash
# darkmem_push_quietly DIR SID — the background Stop push
# (scripts/darkmem-stop-push.sh). Nothing it prints would reach anyone.
```

If the watchdog test reports a job-control notice (`Terminated`) on stderr, suppress it only on the shell's own `wait`/`kill` lines (for example `{ wait "$pid"; } 2>/dev/null`), never on `"$@" &`, whose stderr must pass through.

Create `scripts/darkmem-stop-push.sh`:

```bash
#!/usr/bin/env bash
# Async Stop hook: darkmem's safety-net push (darkmem store options spec §5),
# apart from turn-end.sh so a slow darkmem never delays a turn's end or its
# decision. Claude Code waits for nothing here and enforces no timeout, so the
# push bounds itself (lib/darkmem-hook.sh). Prints nothing; always exits 0.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

command -v jq >/dev/null 2>&1 || exit 0
stdin_json="$(cat 2>/dev/null || true)"
jq -e . >/dev/null 2>&1 <<<"$stdin_json" || exit 0
session_id=$(jq -r '.session_id // empty' <<<"$stdin_json")
cwd=$(jq -r '.cwd // empty' <<<"$stdin_json")
[ -n "$session_id" ] || exit 0
hook_lib="${SCRIPT_DIR}/lib/darkmem-hook.sh"
# One bound around config discovery and the push together: darkmem_push_quietly
# resolves the mapping (a node start) before its own bounded push.
if . "$hook_lib" 2>/dev/null; then
  _darkmem_bounded 100 bash -c '. "$1" && darkmem_push_quietly "$2" "$3"' darkmem-stop-push "$hook_lib" "${cwd:-$PWD}" "$session_id" >/dev/null 2>&1
fi
exit 0
```

In `scripts/turn-end.sh`, delete these lines (and the blank line before them), leaving `[ -n "$session_id" ] || exit 0` directly followed by the `stop_hook_active` check:

```bash
# darkmem's safety-net push (darkmem store options spec §5), before the
# recursion guard and every early exit below, so every stop sends the work
# before it, a retried stop included. stdout is this hook's decision, so the
# push prints nothing.
if . "${SCRIPT_DIR}/lib/darkmem-hook.sh" 2>/dev/null; then
  darkmem_push_quietly "${cwd:-$PWD}" "$session_id"
fi
```

In `hooks/hooks.json`, make the `Stop` group's `hooks` array hold two entries — the existing `turn-end.sh` entry unchanged, then:

```json
          {
            "type": "command",
            "command": "bash \"${CLAUDE_PLUGIN_ROOT}/scripts/darkmem-stop-push.sh\"",
            "shell": "bash",
            "async": true
          }
```

In `README.md`, replace

```markdown
`scripts/roadmap` verb against a temporary repository. `turn-end.test.sh`
drives the turn-stamp and Stop hooks against a temporary repository and ledger.
```

with

```markdown
`scripts/roadmap` verb against a temporary repository. `turn-end.test.sh`
drives the turn-stamp and Stop hooks against a temporary repository and ledger;
`darkmem-sync/hooks.test.mjs` drives darkmem's session-start sync and the
background Stop push (`scripts/darkmem-stop-push.sh`) against the stub.
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `timeout 600 node --test --test-timeout=120000 tests/darkmem-sync/hooks.test.mjs; echo "exit=$?"`
Expected: all PASS, `exit=0`.
Run: `timeout 300 bash tests/turn-end.test.sh; echo "exit=$?"`
Expected: every check passes, `exit=0`.
Run: `timeout 120 claude plugin validate .; echo "exit=$?"`
Expected: validation passes (the async Stop hook entry is accepted), `exit=0`.

- [ ] **Step 5: Commit**

```bash
git add scripts/darkmem-stop-push.sh scripts/lib/darkmem-hook.sh scripts/turn-end.sh hooks/hooks.json README.md tests/darkmem-sync/hooks.test.mjs
git -c user.name=Darkraise -c user.email=quangtc94@gmail.com commit -m "feat(darkmem): push at Stop from an async hook"
```

### Task 6: Cockpit reads a timeout by its wording

**Files:**
- Modify: `hooks/cockpit/register.tsx:2329-2349`
- Test: `tests/cockpit.test.ts:322-327`, `:2203-2211`

**Interfaces:**
- Consumes: none
- Produces: `TIMED_OUT` (Contracts)

**Items:** 26

**Implementer:** dr-superpowers:impl-sonnet-low
**Executor:** codex gpt-6.1-sol / low
**Evaluation:** files 1 - spec 0 - coupling 0 - risk 1 = 2

- [ ] **Step 1: Write the failing test**

In `tests/cockpit.test.ts`, in the fake `process.run` handler, replace

```ts
      if (w.modeOut === 'missing') throw new Error('spawn node ENOENT')
      if (w.modeOut === 'rejects') throw new Error('the engine refused to start the process')
      if (w.modeOut === 'timeout') {
        return clock.advance(5_000).then(() => {
          throw new Error('the process was stopped')
        })
      }
```

with

```ts
      if (w.modeOut === 'missing') throw new Error('dr-forge: $.process.run(node) failed to start: ENOENT: Executable not found in $PATH: "node"')
      if (w.modeOut === 'rejects') throw new Error('the engine refused to start the process')
      if (w.modeOut === 'timeout') throw new Error('dr-forge: $.process.run(node) aborted: still running after 5000ms')
```

and rename the test `'a run that fails only after its 5 seconds says it gave no answer'` to `'a run the engine stops at its timeout says it gave no answer'` (its body is unchanged). The rejection now comes at once, so only its wording can mark it a timeout.

- [ ] **Step 2: Run the tests to verify the timeout test fails**

Run: `out=$(mktemp); timeout 900 claude plugin test . >"$out" 2>&1; status=$?; tail -40 "$out"; rm -f "$out"; echo "exit=$status"`
Expected: non-zero `exit=`; "a run the engine stops at its timeout says it gave no answer" FAILS (no note: the elapsed-time check sees no time pass); "without node the checkout paths stay silently" and "a run that fails at once without naming node keeps the checkout paths silently" PASS.

- [ ] **Step 3: Write the implementation**

In `hooks/cockpit/register.tsx`, below `const NO_NODE = /ENOENT|not found/i`, add:

```ts
// The engine's rejection for a run still going at its timeoutMs (Claude Code
// 2.1.299: "…aborted: still running after 5000ms"); a command that cannot
// start rejects "…failed to start: ENOENT…" instead.
const TIMED_OUT = /still running after/i
```

In `readRoots`, replace

```ts
  const started = await $.clock.now()
  try {
    const ran = await $.process.run(['node', `${$.plugin.root}/scripts/lib/darkmem-config.mjs`, '--mode', primary], { timeoutMs: 5000 })
    if (ran.exitCode === 0) value = parseModeLines(ran.stdout)
    else if (ran.exitCode !== 127 && !NO_NODE.test(ran.stderr)) {
      note = ran.stderr.split(/\r?\n/).map(line => line.trim()).find(Boolean) ?? `darkmem-config.mjs --mode exited ${ran.exitCode}`
    }
  } catch (error) {
    // How the engine words a timeout or a missing node is unconfirmed, so the
    // run's duration decides: a failure well inside the bound is not a timeout.
    if (!NO_NODE.test(String(error)) && (await $.clock.now()) - started >= 4900) note = 'darkmem-config.mjs --mode gave no answer within 5 seconds'
  }
```

with

```ts
  try {
    const ran = await $.process.run(['node', `${$.plugin.root}/scripts/lib/darkmem-config.mjs`, '--mode', primary], { timeoutMs: 5000 })
    if (ran.exitCode === 0) value = parseModeLines(ran.stdout)
    else if (!NO_NODE.test(ran.stderr)) {
      note = ran.stderr.split(/\r?\n/).map(line => line.trim()).find(Boolean) ?? `darkmem-config.mjs --mode exited ${ran.exitCode}`
    }
  } catch (error) {
    // run rejects only when the command cannot start or outlives timeoutMs;
    // any other wording, a later engine's included, keeps the paths silently.
    if (TIMED_OUT.test(String(error))) note = 'darkmem-config.mjs --mode gave no answer within 5 seconds'
  }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `out=$(mktemp); timeout 900 claude plugin test . >"$out" 2>&1; status=$?; tail -40 "$out"; rm -f "$out"; echo "exit=$status"`
Expected: `exit=0`; all tests PASS, including the three readRoots rejection tests and "an exit 127 keeps the checkout paths silently".

- [ ] **Step 5: Commit**

```bash
git add hooks/cockpit/register.tsx tests/cockpit.test.ts
git -c user.name=Darkraise -c user.email=quangtc94@gmail.com commit -m "fix(cockpit): read a run timeout by its wording"
```

### Task 7: Release 2.3.1

**Files:**
- Modify: `.claude-plugin/plugin.json` (version), `.codex-plugin/plugin.json` (version)
- Modify: `tests/review-route.test.sh:584-585`
- Modify: `README.md` (darkmem section)

**Interfaces:**
- Consumes: none
- Produces: none

**Items:** 23, 24, 25, 26

**Implementer:** dr-superpowers:impl-sonnet-low
**Evaluation:** files 1 - spec 0 - coupling 0 - risk 0 = 1

- [ ] **Step 1: Move the version pin first (the failing check)**

In `tests/review-route.test.sh`, replace

```bash
present "the Claude manifest is 2.3.0" "$P/.claude-plugin/plugin.json" '"version": "2.3.0"'
present "the Codex manifest is 2.3.0" "$P/.codex-plugin/plugin.json" '"version": "2.3.0"'
```

with

```bash
present "the Claude manifest is 2.3.1" "$P/.claude-plugin/plugin.json" '"version": "2.3.1"'
present "the Codex manifest is 2.3.1" "$P/.codex-plugin/plugin.json" '"version": "2.3.1"'
```

- [ ] **Step 2: Run it to verify it fails**

Run: `timeout 300 bash tests/review-route.test.sh >review-route.out 2>&1; echo "exit=$?"; grep -E "manifest is 2.3.1" review-route.out; rm -f review-route.out`
Expected: non-zero `exit=`, and both manifest lines report FAIL.

- [ ] **Step 3: Bump the manifests and document the behaviour**

In `.claude-plugin/plugin.json` and `.codex-plugin/plugin.json`, change `"version": "2.3.0"` to `"version": "2.3.1"`.

In `README.md`, replace

```markdown
  runs `reconcile` and `pull`; the Stop hook and the skills' stop points run
  `push`. A document deleted from the mirror is archived on darkmem under
```

with

```markdown
  runs `reconcile` and `pull`; the skills' stop points run `push`, and a
  background Stop hook pushes as a safety net, each of its steps bounded at
  100 seconds. `push`
  waits up to 100 seconds for another run's mirror lock before refusing. A
  move stopped part-way through filing a ledger resumes it at the next session
  start. A document deleted from the mirror is archived on darkmem under
```

- [ ] **Step 4: Run the repository checks**

Run: `timeout 300 bash tests/review-route.test.sh; echo "exit=$?"`
Expected: every check passes, `exit=0`.
Run: `(cd ../.. && timeout 120 node scripts/validate-repository.mjs); echo "exit=$?"`
Expected: `exit=0`.
Run: `(cd ../.. && for target in . plugins/dr-forge plugins/dr-status plugins/dcc-darkraise-ui plugins/dcc-darkraise-win32ui; do timeout 120 claude plugin validate "$target" || echo "FAILED: $target"; done)`
Expected: the marketplace and all four plugins validate; no `FAILED:` line.
Run: `out=$(mktemp); timeout 900 claude plugin test . >"$out" 2>&1; status=$?; tail -20 "$out"; rm -f "$out"; echo "exit=$status"`
Expected: `exit=0`.
Run: `(cd ../.. && timeout 3000 node scripts/test-all.mjs); echo "exit=$?"`
Expected: every maintained suite passes, `exit=0`. Before reporting, confirm nothing the run started is still alive: `pgrep -af "darkmem-sync|node --test|claude plugin test"` prints only processes that predate the step.

- [ ] **Step 5: Commit**

```bash
git add .claude-plugin/plugin.json .codex-plugin/plugin.json tests/review-route.test.sh README.md
git -c user.name=Darkraise -c user.email=quangtc94@gmail.com commit -m "docs(dr-forge): document darkmem fixes, 2.3.1"
```
