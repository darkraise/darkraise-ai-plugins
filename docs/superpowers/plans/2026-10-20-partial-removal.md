# Partial Removal Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: the skill the **Execution:** line names — dr-superpowers:subagent-driven-development for `subagent`, dr-superpowers:executing-plans for `inline`. Steps use checkbox (`- [ ]`) syntax for tracking.

> **External executors:** codex

**Goal:** Close register row DM 74: `writeExclusive` removes its partial file after a failed write only while the path still names the file its descriptor created; release dforge 4.2.4.

**Architecture:** In `writeExclusive`'s `catch`, the descriptor's `fstat` and the path's `lstat` are taken while the descriptor is still open, the descriptor is closed, and the file is removed only when both report the same device and inode. Every step after the failed write swallows its own error, so the write error is what leaves the function. `progressToLocal` gains a comment naming the unguarded parent swap (DM 73, deferred).

**Tech Stack:** Node ES modules with `node --test`.

**Spec:** docs/superpowers/specs/2026-10-20-partial-removal-design.md

**Execution:** inline — `claude --model sonnet --effort medium` — no task is heavy (highest total 3, risk 2) and none carries an Executor line

**Plan review:** 2026-10-20 — codex gpt-6-astra / xhigh — executability 18 / coherence 18 / coverage 20 / assumptions 16 (round 1)

**Parallelism:** sequential — the spec's strategy: one function, one test and a release

## Global Constraints

- Before Task 1: create the plan's worktree from local `main` (local `main` runs ahead of `origin/main`) with `timeout 60 git worktree add .claude/worktrees/partial-removal -b partial-removal main`, and set the commit identity in it with `timeout 60 git config user.name Darkraise` and `timeout 60 git config user.email quangtc94@gmail.com`. Work only in that worktree. Do not push.
- No `Co-Authored-By`, `Claude-Session` or other AI attribution in any commit.
- Commit subjects: `<type>(<scope>): <subject>`, type one of feat|fix|docs|style|refactor|test|chore|perf, at most 50 characters, imperative, no period.
- Never edit plans, specs or notes under `docs/superpowers/`; register rows change only through the installed plugin's `<plugin-root>/scripts/register`. `<plugin-root>` is the dr-superpowers root the session's entry point prints (`Plugin root: …`); on this host on 2026-10-20 it was `/root/.claude/plugins/cache/darkraise/dr-superpowers/1.34.1`.
- Every test, build or CLI command runs under `timeout`, a step's checks (`grep`, `git diff`) included; only the commit blocks run without one. Leave no process running.
- Run every test suite, `scripts/test-all.mjs` and `claude plugin test` with `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID -u CLAUDE_CONFIG_DIR` in front.
- `claude` and `rg` are shell functions on this host: call `/root/.local/bin/claude`, and use `grep` in scripts and steps.
- Code paths in a task are repository-relative. Each suite makes its own temporary directories, so no test meets another at run time.
- Finishing, after Task 2: dr-superpowers:finishing-a-development-branch merges `partial-removal` into local `main`, reruns Task 2 Step 3's validation commands on the merged `main` (acceptance A2), and closes register row DM 74 with `timeout 60 bash <plugin-root>/scripts/register set docs/superpowers/registers/2026-09-24-darkmem-mirror.md 74 done --note "<the merge commit and the checks run>"`, then `timeout 60 bash <plugin-root>/scripts/register check docs/superpowers/registers/2026-09-24-darkmem-mirror.md` must print `register: 0 errors` (acceptance A3; DM 73 is already `deferred`). The worktree-only rule above ends when finishing begins.
- When a quoted anchor is not found, the file changed since the task was written: find the code by its function and intent, make the same change, and say so in the task report. Never invent a change the task does not describe.

## Contracts

None. `writeExclusive(file, buffer)` keeps its signature and its success path; its callers' refusals (`progressToLocal`, `documentsToLocal`) are unchanged.

## Assumptions (evidence)

- Task 1 was drafted against HEAD f4ff54f and run through its fail-then-pass cycle in a scratch copy (`git archive HEAD`) on 2026-10-20, Node v24.18.0, Linux, uid 0. Before the fix the new test failed with `Error: ENOENT: no such file or directory, open '…/.dforge/sdd/p2/progress.md'` (the planted file was deleted). With the fix `reconcile-progress.test.mjs` passed 85 of 85 and `reconcile.test.mjs` 80 of 80.
- Mutation check, same scratch copy and date: with the removal condition forced false, the four regression guards the spec names failed (`reconcile-progress.test.mjs` "fails after a partial write" and "fails part-way", `reconcile.test.mjs` "fails after a partial write" and "fails part-way") and the new test passed. The spec's Testing section was corrected from three guards to four in the commit that adds this plan.
- `exclusiveOpens(t)` (`plugins/dforge/tests/darkmem-sync/reconcile-progress.test.mjs`, about line 998) maps each descriptor a `"wx"` open returns to its path, so a `writeFileSync` mock that receives the descriptor finds the target with `opened.get(file)`; a call with a path string finds nothing (Fable review of the spec, 2026-10-20).
- Windows: renaming a file whose descriptor is open works because libuv opens with `FILE_SHARE_DELETE` (confirmed in libuv's `src/win/fs.c` by the Fable review). `fstat` and `lstat` agreeing on `dev` and `ino` there is unverified — no task verifies it: the Windows CI shards run only on a push or pull request, and this plan does not push. The new test and the four regression guards check it once the owner pushes `main`; until then the finishing report names it as unverified. A disagreement fails safe (spec, Riskiest assumption): the partial file is left and a rerun refuses it.
- Executor lane: `codex-gate` printed `usable=true reason=ok review=true lane=true` (probe, 2026-10-20) and `docs/superpowers/distilled/constraints.md` turns the lane on, so codex is ticked without asking. No task passes the lane gate (`min_score 2`, `max_risk 1`): Task 1 carries risk 2 and Task 2 totals 0.
- Task 1's risk is 2, not 3: `writeExclusive` is a shared code path for both moves, and the change narrows when a file is deleted without adding a new deletion; the copy-race plan scored its race fixes the same way.
- The register row this plan schedules (DM 74) was set `planned`, assigned to this plan, in the same commit as this plan; `main` holds it before Task 1 starts.

## Task index

1. Keep a file another process put at the target
2. Release dforge 4.2.4

---

### Task 1: Keep a file another process put at the target

**Files:**
- Modify: `plugins/dforge/scripts/lib/darkmem-progress-move.mjs` (`writeExclusive`, about lines 57-70; `progressToLocal`, about lines 653-655)
- Test: `plugins/dforge/tests/darkmem-sync/reconcile-progress.test.mjs` (after the test at about line 1062)

**Interfaces:**
- Consumes: None
- Produces: None (Contracts)

**Items:** 74

**Implementer:** dr-superpowers:impl-sonnet-medium
**Evaluation:** files 1 - spec 0 - coupling 0 - risk 2 = 3

`writeExclusive` creates the target with an exclusive open and writes through the descriptor. When the write throws, it removes the file by path, which deletes a file another process put at that path after unlinking or renaming ours. The fix removes the file only when the path still names the descriptor's file.

- [ ] **Step 1: Write the failing test**

In `plugins/dforge/tests/darkmem-sync/reconcile-progress.test.mjs`, insert this test immediately before the test `a mirror ledger replaced by a link after it was read is copied as read, not through the link`:

```js
test("a failed write never removes a file another process put at the target meanwhile", async t => {
  const m = offlineMove();
  const opened = exclusiveOpens(t);
  const writeFile = fs.writeFileSync;
  t.mock.method(fs, "writeFileSync", (file, ...rest) => {
    if (opened.get(file) !== m.target("p2")) return writeFile(file, ...rest);
    fs.renameSync(m.target("p2"), `${m.target("p2")}.aside`);
    writeFile(m.target("p2"), "planted meanwhile\n");
    throw Object.assign(new Error("injected by the test"), { code: "EIO" });
  });
  const result = await progressToLocal(m.context, { offline: "test" });
  assert.equal(result.moved, false);
  assert.equal(result.reason, "a copy into the primary checkout failed (EIO); the files copied so far stay, and a rerun copies the rest");
  assert.deepEqual(result.details, [`${m.target("p1")}: copied`]);
  assert.equal(fs.existsSync(path.join(m.mirror, "work")), true, "the mirror's copies are not set aside");
  assert.equal(read(m.target("p2")), "planted meanwhile\n");
});
```

The rename stays in the target's directory, where a rename across devices cannot fail with `EXDEV`; `ledgersIn` lists only `progress.md`, so the `.aside` file is never read as a ledger. The planted file goes through the captured original `writeFile`, which the mock does not intercept.

- [ ] **Step 2: Run the test to verify it fails**

Run: `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID -u CLAUDE_CONFIG_DIR timeout 600 node --test --test-reporter=spec --test-name-pattern 'another process put at the target' plugins/dforge/tests/darkmem-sync/reconcile-progress.test.mjs`
Expected: FAIL, `ℹ fail 1`, with `Error: ENOENT: no such file or directory, open '…/.dforge/sdd/p2/progress.md'`: the failed write removed the planted file.

- [ ] **Step 3: Remove only the descriptor's own file**

In `plugins/dforge/scripts/lib/darkmem-progress-move.mjs`, replace:

```js
// Written through the descriptor the exclusive create returned, so a failed
// write removes only the partial file it made; left behind, a rerun's
// comparison would refuse it as a different copy.
export function writeExclusive(file, buffer) {
  const fd = fs.openSync(file, "wx");
  try {
    fs.writeFileSync(fd, buffer);
  } catch (error) {
    try { fs.closeSync(fd); } catch {}
    try { fs.rmSync(file, { force: true }); } catch {}
    throw error;
  }
  fs.closeSync(fd);
}
```

with:

```js
// Written through the descriptor the exclusive create returned. A failed
// write removes the partial file, which a rerun's comparison would refuse as
// a different copy, only while the path still names it: a file another
// process put there meanwhile is kept. Both stats are taken before the close,
// while the descriptor keeps the inode from being reused, and the close comes
// before the removal because Windows keeps a name until its last handle
// closes. A file swapped in between the lstat and the removal is still removed.
export function writeExclusive(file, buffer) {
  const fd = fs.openSync(file, "wx");
  try {
    fs.writeFileSync(fd, buffer);
  } catch (error) {
    let own;
    let now;
    try {
      own = fs.fstatSync(fd, { bigint: true });
      now = fs.lstatSync(file, { bigint: true, throwIfNoEntry: false });
    } catch {}
    try { fs.closeSync(fd); } catch {}
    if (own && now && own.dev === now.dev && own.ino === now.ino) {
      try { fs.rmSync(file, { force: true }); } catch {}
    }
    throw error;
  }
  fs.closeSync(fd);
}
```

Then, in `progressToLocal`, replace:

```js
  // exclusively, and a failure part-way refuses, keeping what was copied.
  const landed = [];
```

with:

```js
  // exclusively, and a failure part-way refuses, keeping what was copied. A
  // parent directory swapped for a link after the check above is not guarded.
  const landed = [];
```

- [ ] **Step 4: Run the suites to verify they pass**

Run: `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID -u CLAUDE_CONFIG_DIR timeout 900 node --test plugins/dforge/tests/darkmem-sync/reconcile-progress.test.mjs`
Expected: PASS, `ℹ pass 85`, `ℹ fail 0`.

Run: `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID -u CLAUDE_CONFIG_DIR timeout 900 node --test plugins/dforge/tests/darkmem-sync/reconcile.test.mjs`
Expected: PASS, `ℹ pass 80`, `ℹ fail 0`. `documentsToLocal` calls the same `writeExclusive`; its two failed-write tests guard the removal there.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/scripts/lib/darkmem-progress-move.mjs plugins/dforge/tests/darkmem-sync/reconcile-progress.test.mjs
git commit -m "fix(darkmem): keep a file put at a failed target"
```

### Task 2: Release dforge 4.2.4

**Files:**
- Modify: `plugins/dforge/.claude-plugin/plugin.json`
- Modify: `plugins/dforge/.codex-plugin/plugin.json`

**Interfaces:**
- Consumes: None
- Produces: None

**Implementer:** dr-superpowers:impl-sonnet-low
**Evaluation:** files 0 - spec 0 - coupling 0 - risk 0 = 0

- [ ] **Step 1: Verify the current versions**

Run: `timeout 60 grep -h '"version"' plugins/dforge/.claude-plugin/plugin.json plugins/dforge/.codex-plugin/plugin.json`
Expected: two lines, both `"version": "4.2.3",`.

- [ ] **Step 2: Bump both manifests**

In each of the two files, replace `"version": "4.2.3",` with `"version": "4.2.4",`.

- [ ] **Step 3: Validate**

Run: `timeout 60 grep -h '"version"' plugins/dforge/.claude-plugin/plugin.json plugins/dforge/.codex-plugin/plugin.json`
Expected: two lines, both `"version": "4.2.4",`.

Run: `timeout 120 node scripts/validate-repository.mjs`
Expected: PASS, no errors.

Run, one at a time: `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID -u CLAUDE_CONFIG_DIR timeout 1800 node scripts/test-all.mjs`, `timeout 120 /root/.local/bin/claude plugin validate .`, `timeout 120 /root/.local/bin/claude plugin validate plugins/dforge`, `timeout 120 /root/.local/bin/claude plugin validate plugins/dr-status`, `timeout 120 /root/.local/bin/claude plugin validate plugins/darkraise-ui`, `timeout 120 /root/.local/bin/claude plugin validate plugins/darkraise-win32ui`, `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID -u CLAUDE_CONFIG_DIR timeout 300 /root/.local/bin/claude plugin test plugins/dforge`
Expected: each exits 0. `test-all.mjs` may print a `Skipped tsc --noEmit -p plugins/dforge: …` line; that is not a failure.

- [ ] **Step 4: Commit**

```bash
git add plugins/dforge/.claude-plugin/plugin.json plugins/dforge/.codex-plugin/plugin.json
git commit -m "chore(dforge): release 4.2.4"
```
