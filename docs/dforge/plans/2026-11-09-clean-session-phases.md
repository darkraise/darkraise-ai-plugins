# Clean-session phases Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: the skill the **Execution:** line names — dforge:subagent-driven-development for `subagent`, dforge:executing-plans for `inline`. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Auto runs clear the session after the plan and before finishing, and review packages stop carrying the branch's own spec, plan and register files.

**Architecture:** The cockpit's `switch` stage takes the existing phase-clear path and the compaction machinery behind it is removed. dforge:finishing-a-development-branch clears once at its entry in an auto run, keyed on the phase. `scripts/review-package` excludes the three document directories from its stat and diff.

**Tech Stack:** Bash scripts and bash test suites, a TypeScript cockpit mod tested with `claude plugin test`, Markdown skills and references pinned by text tests.

**Spec:** docs/dforge/specs/2026-11-09-clean-session-phases-design.md

**Execution:** inline — `claude --model opus --effort high` — the hardest task totals 6

**Parallelism:** sequential — inline execution

**Task check:** `timeout 1500 node scripts/test-all.mjs` — the full suite last passed in 184 s

**Integration check:** `timeout 1500 node scripts/test-all.mjs && timeout 240 /root/.local/bin/claude plugin test plugins/dforge && timeout 60 node scripts/validate-repository.mjs && timeout 60 /root/.local/bin/claude plugin validate . && timeout 60 /root/.local/bin/claude plugin validate plugins/dforge`

**CI:** `.github/workflows/validate.yml` — platforms: uutils (ubuntu-latest), Windows Git Bash — local: `node scripts/test-all.mjs`; `node scripts/validate-repository.mjs`; `claude plugin validate plugins/dforge`; `claude plugin test plugins/dforge` — uncovered: uutils (ubuntu-latest), Windows Git Bash

**Worktree setup:** none

**Plan review:** 2026-11-09 — dforge:judge-opus — executability 6 / coherence 9 / coverage 15 / assumptions 11 (round 1)

## Global Constraints

- English only in code, comments, docs, commits and tests.
- Commits are `<type>(<scope>): <subject>`, subject at most 50 characters, authored as `Darkraise <quangtc94@gmail.com>`, with no AI attribution of any kind.
- No code comment unless the why is non-obvious; never reference this task or plan in a comment.
- Nothing is pushed during this run.
- Every `skills/*/SKILL.md` stays at or under 20,000 bytes (`tests/speed-and-cost.acceptance.test.sh`).
- Windows Git Bash: A native program (`git.exe`, `jq.exe`) given a path built from `$PWD`, `$(pwd)` or `$TMPDIR` gets a POSIX form it cannot open, or has its argument rewritten when path conversion is on (`MSYS_NO_PATHCONV` unset). Convert the path with `cygpath -m` before the call (dforge's `dr_native_path`, `plugins/dforge/scripts/lib/native-path.sh`), and feed `jq` a file on stdin in a script that exports `MSYS_NO_PATHCONV`.
- Windows Git Bash: The same directory is `/c/Users/x` in the shell and `C:/Users/x` from a native tool, so a string comparison never matches. Normalise both sides with `cygpath -m`, or compare with `-ef`.
- Windows Git Bash: Files a Windows tool wrote, and native program output, end lines with `\r`, which `read`, `awk` and `[ = ]` keep. Pipe through `tr -d '\r'` before comparing or parsing.
- Windows Git Bash: `awk -v name=value` processes backslash escapes in the value, so a regex or a Windows path changes. Pass the value in the environment and read `ENVIRON["NAME"]`.
- Windows Git Bash: Node's `import()` of an absolute `D:/x/y.mjs` reads `d:` as a URL scheme and fails. Import with `import(pathToFileURL(path).href)`.
- uutils (ubuntu-latest): A lock built on `mkdir` failing when the directory exists does not exclude a second process. Create the lock file with `set -C` (noclobber), or use `flock`.
- uutils (ubuntu-latest): `timeout` signals only the command it started, so the command's children keep running. Run the command in its own process group (`setsid`) and signal the group.

## Contracts

- `review-package` left-out line, the last line of `## Files changed` when files were left out: `Left out: <path>, <path> — the seat has the spec and plan by path, or the brief`, paths in `git diff --name-only` order.
- The cockpit's failure text when the switch's clear fails: `the cockpit could not switch: the phase clear exited <code>`.
- `auto-run compacted` takes no flag; any argument is a usage error (exit 2).
- `auto-run pending` no longer prints `switch-resume`.
- Finishing's entry, in an auto run whose phase is not `finish`: `scripts/auto-run phase finish`, dforge:handoff steps 0-3, `scripts/next-step PLAN_FILE`, `scripts/auto-run clear --phase`, then the turn ends with `Auto run: clearing`.

## Assumptions (evidence)

- The clear path already does what the switch needs: `plugins/dforge/hooks/cockpit/register.tsx` runs `clear --phase` and sets `at = 'clear'` on a refused compaction, and the shared code below it applies the launch model and submits the prompt.
- `ar_clear` touches neither the phase nor `setupDue`, and `--phase` counts no self-resume: `plugins/dforge/scripts/lib/auto-run.sh`, `ar_clear`.
- `next-step` prints finishing's first prompt for a clean final review: `plugins/dforge/tests/next-step.test.sh:296-297`.
- The full suite takes about three minutes here: `.dforge/suites.tsv`, 184 s, read 2026-11-09.
- `claude` is a shell function in this tool shell, so test commands name `/root/.local/bin/claude` (`ls -l`, 2026-11-09). That path is host-specific; CI uses its own install.
- Git Bash delivers the `:(exclude)` pathspecs intact when the two `git diff` calls carry `MSYS_NO_PATHCONV=1`: unverified — Task 1 verifies it. Task 1's test drops the suite's own `MSYS_NO_PATHCONV`, but only the Windows shards exercise it, and the spec records `Early CI: none` and `Finish: merge`, so this stays unobserved through the merge. The final report must tell the owner it is settled only by the Windows shards on their later push.
- A12 is a `demo` statement, so no task builds it; finishing lists it for the owner.
- Plan review round 1 scored coherence 9 and assumptions 11 (borderline): the coherence score came from the test pins the plan missed, now fixed in Tasks 2 and 4, and the assumptions score from the Windows item above, now stated as open through the merge.

## Task index

1. Leave the branch's own documents out of review packages
2. Clear the session at the switch in the cockpit
3. Remove the switch compaction from the run state
4. Document the switch as a clear
5. Finish in a clean session

---

### Task 1: Leave the branch's own documents out of review packages

**Files:**
- Modify: `plugins/dforge/scripts/review-package`
- Modify: `plugins/dforge/skills/subagent-driven-development/references/task-reviewer-prompt.md`
- Test: `plugins/dforge/tests/budget-line.test.sh`

**Interfaces:**
- Consumes: none
- Produces: the `Left out:` line in Contracts

**Items:** 2

**Implementer:** dforge:impl-sonnet-high
**Evaluation:** files 1 - spec 2 - coupling 0 - risk 2 = 5
**Approach:** inline - skip 3: the owner chose among the measured options

- [ ] **Step 1: Extend the test `plugins/dforge/tests/budget-line.test.sh::review-package`**

Insert this block directly above the file's final `printf '\n%d passed, %d failed\n'` line:

```bash
# --- the package leaves out the branch's own design documents ---
# The suite's MSYS_NO_PATHCONV would hide a pathspec Git Bash rewrites.
PKG="$TMP/pkg"
git init -q "$PKG"
mkdir -p "$PKG/docs/dforge/specs" "$PKG/docs/dforge/plans" "$PKG/docs/dforge/registers" "$PKG/docs/superpowers/plans" "$PKG/docs/guide" "$PKG/src/deep"
printf '# Plan\n\n### Task 1: First\n\nBody.\n' > "$PKG/docs/dforge/plans/p.md"
printf 'a\n' > "$PKG/src/deep/code.txt"
printf 'a\n' > "$PKG/docs/guide/g.md"
printf 'a\n' > "$PKG/docs/dforge/specs/s.md"
printf 'a\n' > "$PKG/docs/dforge/registers/r.md"
printf 'a\n' > "$PKG/docs/superpowers/plans/old.md"
git -C "$PKG" add -A && git -C "$PKG" commit -qm pkg-base
PBASE=$(git -C "$PKG" rev-parse HEAD)
for f in docs/dforge/specs/s.md docs/dforge/plans/p.md docs/dforge/registers/r.md docs/superpowers/plans/old.md; do printf 'b\n' >> "$PKG/$f"; done
git -C "$PKG" add -A && git -C "$PKG" commit -qm pkg-docs
PDOCS=$(git -C "$PKG" rev-parse HEAD)
printf 'b\n' >> "$PKG/src/deep/code.txt"
printf 'b\n' >> "$PKG/docs/guide/g.md"
git -C "$PKG" add -A && git -C "$PKG" commit -qm pkg-code
pkg() { # pkg <directory to run from> <base> <head> <output name>
  (cd "$1" && env -u MSYS_NO_PATHCONV bash "$P/scripts/review-package" "$PKG/docs/dforge/plans/p.md" "$2" "$3" "$TMP/$4" >/dev/null 2>&1)
}
count() { grep -cF -- "$2" "$TMP/$1"; }
pkg "$PKG" "$PBASE" HEAD mixed.diff
check "package: the code is diffed" "$(count mixed.diff 'diff --git a/src/deep/code.txt')" "1"
for f in docs/dforge/specs/s.md docs/dforge/plans/p.md docs/dforge/registers/r.md docs/superpowers/plans/old.md; do
  check "package: $f is not diffed" "$(count mixed.diff "diff --git a/$f")" "0"
  check "package: $f is not in the stat" "$(grep -cE -- " ${f//./\\.} +\\|" "$TMP/mixed.diff")" "0"
done
check "package: the left-out line names each file" "$(grep '^Left out: ' "$TMP/mixed.diff")" \
  "Left out: docs/dforge/plans/p.md, docs/dforge/registers/r.md, docs/dforge/specs/s.md, docs/superpowers/plans/old.md — the seat has the spec and plan by path, or the brief"
check "package: another document stays" "$(count mixed.diff 'diff --git a/docs/guide/g.md')" "1"
check "package: the commit list keeps every commit" "$(count mixed.diff ' pkg-docs'):$(count mixed.diff ' pkg-code')" "1:1"
pkg "$PKG" "$PBASE" "$PDOCS" docs-only.diff
check "package: a documents-only range keeps its diff" "$(count docs-only.diff 'diff --git a/docs/dforge/specs/s.md')" "1"
check "package: a documents-only range leaves nothing out" "$(count docs-only.diff 'Left out:')" "0"
pkg "$PKG/src/deep" "$PBASE" HEAD subdir.diff
check "package: the same from a subdirectory" "$(cat "$TMP/subdir.diff")" "$(cat "$TMP/mixed.diff")"
check "task reviewer: may open a left-out file" "$(grep -c 'named on a `Left out:` line' "$P/skills/subagent-driven-development/references/task-reviewer-prompt.md")" "1"
. "$HERE/fixtures/darkmem-stores.sh"
SH="$TMP/stores-home"; mkdir -p "$SH"
stores_home "$SH" "$PKG" p darkmem local >/dev/null
(cd "$PKG" && HOME="$SH" env -u MSYS_NO_PATHCONV bash "$P/scripts/review-package" "$PKG/docs/dforge/plans/p.md" "$PBASE" HEAD "$TMP/store.diff" >/dev/null 2>&1); status=$?
check "package: a document store: exit 0" "$status" "0"
check "package: a document store: the code is still diffed" "$(count store.diff 'diff --git a/src/deep/code.txt')" "1"

```

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 120 bash plugins/dforge/tests/budget-line.test.sh`
Expected: FAIL on the `package:` checks of the mixed range and the `task reviewer:` check; the earlier checks, the documents-only range's diff, the same-from-a-subdirectory check and the two document-store checks pass already, because they pin what must keep working.

- [ ] **Step 3: Implement**

1. In `plugins/dforge/scripts/review-package`, above the `{ echo "# Review package: ..."` group, compute the excludes. `top=$(git rev-parse --show-toplevel)`. Take the documents root as `ar_start` does, `dforge_name "$(dforge_docs_root "$top")" "$top"`; skip all exclusion when it is absolute, matching both forms `/*` and `[A-Za-z]:/*` (a `documentStore` can keep documents outside the repository, and git refuses an absolute path inside `:(exclude)`). For each spelling `dforge_name_spellings` prints for that name, add the three pathspecs `:(exclude)<spelling>/specs`, `:(exclude)<spelling>/plans` and `:(exclude)<spelling>/registers`. `lib/plan.sh`, already sourced, sources `lib/roots.sh`.
2. List the left-out files with `git -C "$top" diff --name-only "${base}..${head}" -- <the same directories as plain paths>` and the kept files with `git -C "$top" diff --name-only "${base}..${head}" -- . <the excludes>`. Pass `tr -d '\r'` over both.
3. When both lists are non-empty, the `--stat` and `-U10` calls run as `MSYS_NO_PATHCONV=1 git -C "$top" diff ... -- . <the excludes>`, and the `Left out:` line of Contracts follows the stat, its paths joined with `, `. When either list is empty, both calls have no pathspec and no line prints, so a documents-only range keeps its diff. `## Commits` does not change. Every `git` call that carries a pathspec gets the `MSYS_NO_PATHCONV=1` prefix.
4. In `task-reviewer-prompt.md`, after the sentence ending `mid-function — and say so in your report.`, add on the same paragraph: `A file named on a `Left out:` line of the diff file is not in the diff; Read it only if the task's change depends on it.`

- [ ] **Step 4: Run test to verify it passes**

Run: `timeout 120 bash plugins/dforge/tests/budget-line.test.sh`
Expected: PASS, `0 failed`.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/scripts/review-package plugins/dforge/skills/subagent-driven-development/references/task-reviewer-prompt.md plugins/dforge/tests/budget-line.test.sh
git commit -m "feat(dforge): drop own docs from review packages"
```

### Task 2: Clear the session at the switch in the cockpit

**Files:**
- Modify: `plugins/dforge/hooks/cockpit/register.tsx`
- Test: `plugins/dforge/tests/cockpit.test.ts`

**Interfaces:**
- Consumes: `auto-run clear --phase`, existing
- Produces: the failure text in Contracts

**Items:** 3

**Implementer:** dforge:impl-opus-high
**Evaluation:** files 1 - spec 2 - coupling 1 - risk 2 = 6
**Approach:** inline - skip 3: the owner's notes chose the clear path

- [ ] **Step 1: Extend the test `plugins/dforge/tests/cockpit.test.ts::auto-run switch`**

In the `process.run` simulator, change the `word === 'compacted'` line to `if (exitCode === 0 && word === 'compacted') Object.assign(state, { pending: 'after-compact', compactions: Number(state.compactions) + 1 })`, and delete the `else if (exitCode === 0 && word === 'resumed' && state.pending === 'switch-resume') state.pending = 'after-compact'` line.

Delete these five tests by their titles: `switches in place: compacts, books it, sets the model and submits the first prompt`, `retries the first prompt after the switch compaction without compacting again`, `clears over a refused switch compaction before it sets the model`, `stops the run when the switch cannot book its resume`, and `stops the run when the switch's compaction cannot be booked`. Also delete `books no engine compaction over a pending switch-resume` and `says at the switch that execution begins at Setup` (the second asserts on the compaction instructions; Task 3's `the switch's clear: phase execute, setup due` check keeps Setup pinned). In place of the first five, add:

```ts
  test('switches by clearing: no compaction, the launch model, then the first prompt', async ($, on) => {
    const files = autoFiles({ phase: 'execute', pending: 'switch', resumePrompt: 'Continue `docs/plan.md` with dforge:subagent-driven-development.', launch: { model: 'sonnet', effort: 'high' } })
    const w: World = { ...SIGNED_IN, compacts: [], commands: [], autoRuns: [], prompts: [], autoFile: files[AUTO] }
    const clock = world(on, w)
    signedIn(on, files)
    await $.session.start(START)
    await $.turn.complete({ answer: 'Plan saved.\n\nAuto run: switching', durationMs: 1, isAborted: false, turnId: 't1', reason: 'answer' })
    await settle(clock)
    expect(w.compacts).toEqual([])
    expect(w.autoRuns?.filter(call => call.includes(' compacted'))).toEqual([])
    expect(w.autoRuns).toContain('--session sess-1 clear --phase')
    expect(w.autoRuns).toContain('--session sess-2 rebind --to sess-2')
    expect(w.commands).toEqual(['/clear', '/model sonnet', '/effort high'])
    expect(w.prompts).toEqual(['Continue `docs/plan.md` with dforge:subagent-driven-development.'])
    expect(pendingOf(files)).toBeNull()
  })

  test('retries a failed switch clear, naming the switch in each failure', async ($, on) => {
    const files = autoFiles({ phase: 'execute', pending: 'switch', resumePrompt: 'Continue `docs/plan.md`.', launch: null })
    const w: World = { ...SIGNED_IN, compacts: [], commands: [], autoRuns: [], prompts: [], autoFile: files[AUTO], autoRunExits: { clear: 1 } }
    const clock = world(on, w)
    signedIn(on, files)
    await $.session.start(START)
    await $.turn.complete({ answer: 'Plan saved.\n\nAuto run: switching', durationMs: 1, isAborted: false, turnId: 't1', reason: 'answer' })
    await settle(clock)
    const failures = () => w.autoRuns?.filter(call => call.includes(' failure --reason the cockpit could not switch: the phase clear exited 1'))
    expect(failures()).toHaveLength(1)
    expect(w.compacts).toEqual([])
    expect(w.prompts).toEqual([])
    expect(pendingOf(files)).toBe('switch')
    await clock.advance(5_000)
    await settle(clock)
    expect(w.autoRuns?.filter(call => call === '--session sess-1 clear --phase')).toHaveLength(2)
    expect(failures()).toHaveLength(2)
  })

  test('stops the run when a failed switch clear reaches the failure cap', async ($, on) => {
    const files = autoFiles({ phase: 'execute', pending: 'switch', resumePrompt: 'Continue `docs/plan.md`.', launch: null })
    const w: World = { ...SIGNED_IN, compacts: [], commands: [], autoRuns: [], prompts: [], autoFile: files[AUTO], autoRunExits: { clear: 1, failure: 5 } }
    const clock = world(on, w)
    signedIn(on, files)
    await $.session.start(START)
    await $.turn.complete({ answer: 'Plan saved.\n\nAuto run: switching', durationMs: 1, isAborted: false, turnId: 't1', reason: 'answer' })
    await settle(clock)
    expect(w.autoRuns?.filter(call => call.includes(' failure --reason the cockpit could not switch: '))).toHaveLength(1)
    expect(w.prompts).toEqual([])
    expect(pendingOf(files)).toBeNull()
  })
```

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 240 /root/.local/bin/claude plugin test plugins/dforge`
Expected: FAIL on `switches by clearing` (a compaction runs), `retries a failed switch clear` and `stops the run when a failed switch clear reaches the failure cap`.

- [ ] **Step 3: Implement**

In `plugins/dforge/hooks/cockpit/register.tsx`:

1. Delete `AUTO_SWITCH_INSTRUCTIONS` and the comment above it.
2. Remove `'switch-resume'` from the `AutoStage` union, from `AUTO_STAGE_PENDING`, from `WATCHED_STAGES`, and from the pending list in `bookAutoCompaction` (the `['clear', 'switch', 'switch-resume', 'handoff']` array).
3. Replace the body of `if (at === 'switch')` with: run `autoRunCall($, bound, ['clear', '--phase'])`; on a nonzero result throw `new Error(`the phase clear exited ${cleared}`)`; otherwise set `at = 'clear'`. No compaction call, no `update` of `budget` or `isNudged`, no `compacted --switch` booking.
4. In the shared resume code, delete `lead` and submit `${auto.resumePrompt ?? resumePrompt()}${note}`. Replace the `resumed` call and its `switch-resume` condition with a plain `await autoRunCall($, bound, ['resumed'])`, and delete the comment above it that describes the switch-resume case.
5. In the `catch`, the action becomes `at === 'compact' || at === 'continue' ? 'compact' : at === 'switch' ? 'switch' : 'clear'`.

Nothing else in the file changes.

- [ ] **Step 4: Run test to verify it passes**

Run: `timeout 240 /root/.local/bin/claude plugin test plugins/dforge`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/hooks/cockpit/register.tsx plugins/dforge/tests/cockpit.test.ts
git commit -m "feat(dforge): clear the session at the switch"
```

### Task 3: Remove the switch compaction from the run state

**Files:**
- Modify: `plugins/dforge/scripts/lib/auto-run.sh`
- Modify: `plugins/dforge/scripts/auto-run`
- Modify: `plugins/dforge/scripts/turn-end.sh`
- Modify: `plugins/dforge/types/index.d.ts`
- Test: `plugins/dforge/tests/auto-run.test.sh`
- Test: `plugins/dforge/tests/turn-end.test.sh`

**Interfaces:**
- Consumes: Task 2's cockpit, which no longer calls `compacted --switch`
- Produces: the `auto-run compacted` and `auto-run pending` entries in Contracts

**Items:** 3

**Implementer:** dforge:impl-opus-high
**Evaluation:** files 2 - spec 2 - coupling 1 - risk 1 = 6
**Approach:** inline - skip 3: the spec lists what is removed

- [ ] **Step 1: Extend the test `plugins/dforge/tests/auto-run.test.sh::the switch`**

Make these edits in `plugins/dforge/tests/auto-run.test.sh`, each located by its quoted text:

1. In the loop `for fn in ar_failure ar_stalled ar_compacted "ar_compacted --switch"; do`, drop the `"ar_compacted --switch"` entry.
2. Replace everything from the line `ar --session s-1 compacted --switch` directly after `check "pending prints switch"` through the line `check "after a switch, a small context continues" ...` with:

```bash
ar --session s-1 compacted --switch >/dev/null 2>&1; status=$?
check "compacted --switch: a usage error, nothing booked" "$status:$(field compactions):$(field pending)" "2:0:switch"
usage_text=$(ar --session s-1 compacted --what 2>&1)
check "usage: compacted has no --switch" "$(grep -c -- '--switch' <<<"$usage_text")" "0"
check "usage: no switch-resume" "$(grep -c 'switch-resume' <<<"$usage_text")" "0"
ar --session s-1 clear --phase; status=$?
check "the switch's clear: exit 0, clear pending" "$status:$(field pending)" "0:clear"
check "the switch's clear: phase execute, setup due, no self-resume" "$(field phase):$(field setupDue):$(field resumes)" "execute:true:0"
check "status after the switch's clear: execute and setup due" "$(ar --session s-1 status | grep -c '^auto run: execute .* — 0 resumes .* — setup due$')" "1"
ar --session s-1 start --spec "$SPEC" --register docs/r.md --force >/dev/null
```

3. In the Setup section, replace the pair `ar --session s-1 compacted --switch` and `ar --session s-1 resumed` above `check "after a switch, continue names Setup"` with the one line `ar --session s-1 compacted`.
4. In the progress-caps section, delete the three lines `ar --session s-1 compacted --switch`, `check "the switch's compaction is not counted" ...` and `ar --session s-1 resumed` that follow `ar --session s-1 switch`.
5. In the section `# --- after-compact: an unknown size still names a due Setup ---`, replace the pair `ar --session s-1 compacted --switch` and `ar --session s-1 resumed` with the one line `ar --session s-1 compacted`.

In `plugins/dforge/tests/turn-end.test.sh`, delete the two lines `pend switch-resume` and `check "auto run: a pending switch-resume is held" ...`.

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 300 bash plugins/dforge/tests/auto-run.test.sh`
Expected: FAIL on `compacted --switch: a usage error, nothing booked` and both `usage:` checks.

- [ ] **Step 3: Implement**

1. `scripts/lib/auto-run.sh`, `ar_resumed`: drop the `switch-resume` branch, leaving `.failures = 0` and the `resume` to null case; rewrite its comment to say only that the cockpit submitted its stage's prompt.
2. `ar_compacted`: remove the `--switch` argument and the `next` variable. The update always sets `.pending = "after-compact"`, keeps the `finalCompacted` line, and counts `compactionsSinceTask` when `.phase == "execute"`; the cap check always runs. Rewrite the comment so it no longer mentions the switch.
3. `ar_switch`'s comment: its first line becomes `# ar_switch — at plan saved, the move to execution: the first prompt`, and the sentence about the switch's compaction becomes `The phase moves to execute before the cockpit clears the session.` `ar_holds_session`'s comment becomes `# ar_holds_session — true in the phases no compaction hands off from: the plan is written, the final review runs, and finishing runs in its own session.`, wrapped as its neighbours are.
4. `scripts/auto-run`: the `compacted)` case becomes `compacted) [ $# -eq 0 ] || usage; bound; ar_compacted ;;`. In `usage`, `compacted [--switch]` becomes `compacted`; the pending line drops `switch-resume`; the `clear --phase` paragraph reads `clear --phase is for a phase transition (the switch, finishing, or a plan that left inline mode before this change: a ledger executing-plans' recovery.md sends to subagent-driven-development) and never a self-resume; a plain clear is one, and the third in a row stops the run (exit 5).`
5. `scripts/turn-end.sh`, the switch hold message: `the cockpit then compacts and moves this session to the plan's launch model.` becomes `the cockpit then clears this session and starts the plan on its launch model.`
6. `types/index.d.ts`, the `pending` comment on `CockpitAutoRun`: remove `` `switch-resume`, ``.

- [ ] **Step 4: Run test to verify it passes**

Run: `timeout 300 bash plugins/dforge/tests/auto-run.test.sh`
Expected: PASS, `0 failed`.

Run: `timeout 120 bash plugins/dforge/tests/turn-end.test.sh`
Expected: PASS, `0 failed`.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/scripts/lib/auto-run.sh plugins/dforge/scripts/auto-run plugins/dforge/scripts/turn-end.sh plugins/dforge/types/index.d.ts plugins/dforge/tests/auto-run.test.sh plugins/dforge/tests/turn-end.test.sh
git commit -m "refactor(dforge): drop the switch compaction state"
```

### Task 4: Document the switch as a clear

**Files:**
- Modify: `plugins/dforge/reference/auto-run.md`
- Modify: `plugins/dforge/reference/session-budget.md`
- Modify: `plugins/dforge/skills/handoff/SKILL.md`
- Modify: `plugins/dforge/README.md`
- Test: `plugins/dforge/tests/auto-run-skills.test.sh`
- Test: `plugins/dforge/tests/final-phase.test.sh`

**Interfaces:**
- Consumes: Task 2 and Task 3's behaviour
- Produces: none

**Items:** 3

**Implementer:** dforge:impl-sonnet-high
**Evaluation:** files 2 - spec 1 - coupling 1 - risk 1 = 5
**Approach:** inline - skip 3: the spec names each passage

- [ ] **Step 1: Extend the tests `plugins/dforge/tests/auto-run-skills.test.sh::the switch` and `plugins/dforge/tests/final-phase.test.sh::handoff`**

In `plugins/dforge/tests/final-phase.test.sh`, delete the line `names "handoff: a saved plan switches in place" ...` and add directly below the `says()` definition's closing brace:

```bash
says "handoff: a saved plan goes through the switch" "$H" 'A saved plan moves through the switch instead'
```

In `plugins/dforge/tests/auto-run-skills.test.sh`, delete the line `check "auto-run.md: the one phase clear is for an old switch" ...` (the phase clear now has three callers, and the pins below and in Task 5 name the new ones). Change the line `names "auto-run.md: the switch starts at Setup" ...` to use `says` in place of `names`, keeping its label, file and text. Replace the line `names "auto-run.md: plan saved is no clear" ...` with:

```bash
says "auto-run.md: a saved plan goes through the switch" "$R" 'A saved plan moves through §The switch, where the cockpit runs the phase clear.'
says "auto-run.md: the switch clears the session" "$R" 'The cockpit then runs `scripts/auto-run clear --phase`, clears the session and binds the new one,'
says "auto-run.md: the switch's prompt has no after-compact lead" "$R" 'and submits the plan'"'"'s first prompt. Follow it in the new session.'
says "auto-run.md: clears names the switch" "$R" '**The switch** (§The switch): the cockpit runs `scripts/auto-run clear --phase` itself.'
check "auto-run.md: no switch-resume" "$(grep -c 'switch-resume' "$R")" "0"
check "auto-run.md: no compacted --switch" "$(grep -c 'compacted --switch' "$R")" "0"
says "session-budget: the switch clears" "$P/reference/session-budget.md" 'no stop: the cockpit clears the session and starts execution'
says "handoff: the switch clears" "$P/skills/handoff/SKILL.md" 'only steps 0-3 below run, and the cockpit clears the session.'
says "readme: the switch clears" "$P/README.md" 'the cockpit clears the session and starts it on the plan'"'"'s launch model'
```

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 120 bash plugins/dforge/tests/auto-run-skills.test.sh`
Expected: FAIL on each new check above, except `auto-run.md: the switch starts at Setup`, which passes already.

Run: `timeout 60 bash plugins/dforge/tests/final-phase.test.sh`
Expected: FAIL on `handoff: a saved plan goes through the switch`.

- [ ] **Step 3: Implement**

1. `reference/auto-run.md` §The switch: the opening sentence becomes `Once the plan is reviewed and attached, the run moves to execution in a cleared session; dforge:handoff does not end the run.` Replace the paragraph beginning `The cockpit then compacts the session,` through `A failure in either stage is retried once in that stage; the second stops the run.` with: `The cockpit then runs `scripts/auto-run clear --phase`, clears the session and binds the new one, runs `/model` and `/effort` from the plan's launch command, puts back the user's default model and effort, and submits the plan's first prompt. Follow it in the new session. No ledger exists yet, so the execution skill starts at its Setup, workspace first: `scripts/auto-run status` says setup is due until `phase execute` runs from the execution workspace. A switch is a phase transition: it never counts as a self-resume. A failure in either stage is retried once in that stage; the second stops the run.` Keep ``execution skill starts at its Setup, workspace first: `scripts/auto-run status` `` on one physical line: `tests/auto-run-worktree-setting.acceptance.test.sh` greps it.
2. §Ending a turn: drop `` `switch-resume` `` from the `scripts/auto-run pending` list.
3. §Clears: add the bullet `- **The switch** (§The switch): the cockpit runs `scripts/auto-run clear --phase` itself.` after the existing `clear --phase` bullet. Replace `Plan saved is no clear: the session switches in place (§The switch).` with `A saved plan moves through §The switch, where the cockpit runs the phase clear.`
4. `reference/session-budget.md` §Stops: `no stop: the cockpit switches the session in place` becomes `no stop: the cockpit clears the session and starts execution`.
5. `skills/handoff/SKILL.md` `When`, the auto-run bullet: `A saved plan switches in place instead (auto-run.md §The switch): only steps 0-3 below run, and the session does not end.` becomes `A saved plan moves through the switch instead (auto-run.md §The switch): only steps 0-3 below run, and the cockpit clears the session.`
6. `README.md` §Auto run: `the cockpit compacts and switches the session to the plan's launch model in place, and the plan executes` becomes `the cockpit clears the session and starts it on the plan's launch model, and the plan executes`. §Session budget `Stops`: `(an auto run switches in place)` becomes `(an auto run clears the session and goes on)`.

- [ ] **Step 4: Run test to verify it passes**

Run: `timeout 120 bash plugins/dforge/tests/auto-run-skills.test.sh`
Expected: PASS, `0 failed`.

Run: `timeout 60 bash plugins/dforge/tests/final-phase.test.sh`
Expected: PASS, `0 failed`.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/reference/auto-run.md plugins/dforge/reference/session-budget.md plugins/dforge/skills/handoff/SKILL.md plugins/dforge/README.md plugins/dforge/tests/auto-run-skills.test.sh plugins/dforge/tests/final-phase.test.sh
git commit -m "docs(dforge): describe the switch as a clear"
```

### Task 5: Finish in a clean session

**Files:**
- Modify: `plugins/dforge/skills/finishing-a-development-branch/SKILL.md`
- Modify: `plugins/dforge/reference/auto-run.md`
- Modify: `plugins/dforge/reference/final-review.md`
- Modify: `plugins/dforge/reference/session-budget.md`
- Modify: `plugins/dforge/skills/handoff/SKILL.md`
- Modify: `plugins/dforge/README.md`
- Test: `plugins/dforge/tests/final-phase.test.sh`
- Test: `plugins/dforge/tests/auto-run-skills.test.sh`
- Test: `plugins/dforge/tests/auto-run.test.sh`

**Interfaces:**
- Consumes: the finishing entry in Contracts
- Produces: none

**Items:** 1

**Implementer:** dforge:impl-opus-high
**Evaluation:** files 3 - spec 1 - coupling 1 - risk 1 = 6
**Approach:** inline - skip 3: the owner's notes chose it and Fable approved the placement

- [ ] **Step 1: Extend the tests `plugins/dforge/tests/final-phase.test.sh::finishing` and `plugins/dforge/tests/auto-run.test.sh::the switch`**

Add to `plugins/dforge/tests/final-phase.test.sh`, directly below the `says()` definition's closing brace:

```bash
says "finishing: phases other than finish clear first" "$FIN" 'and its phase is not `finish`, run `scripts/auto-run phase finish`'
says "finishing: the clear's steps" "$FIN" 'dforge:handoff steps 0-3, `scripts/next-step PLAN_FILE` and `scripts/auto-run clear --phase`, and end the turn with `Auto run: clearing`.'
says "finishing: phase finish continues" "$FIN" 'In phase `finish`, follow this skill with these changes:'
check "finishing: only the Auto run section names auto-run clear" "$(awk '/^## /{sec=$0} /auto-run clear/ && sec!="## Auto run"{c++} END{print c+0}' "$FIN")" "0"
says "session budget: attended finishing stays" "$P/reference/session-budget.md" 'Once the final review is clean, finishing runs in the same session.'
says "session budget: the auto-run exception" "$P/reference/session-budget.md" 'In an auto run it runs in a session of its own ([auto-run.md](auto-run.md) §Finishing).'
says "handoff: attended finishing stays" "$H" 'nothing stops finishing once the final review is clean'
says "handoff: the auto run clears before finishing" "$H" 'It also clears before finishing (auto-run.md §Finishing), through dforge:finishing-a-development-branch.'
says "final review: the auto-run exception" "$FR" 'In an auto run finishing clears the session first (auto-run.md §Finishing).'
says "readme: the auto-run exception" "$P/README.md" 'In an auto run, finishing runs in a session of its own.'
R="$P/reference/auto-run.md"
says "auto-run.md: finishing runs alone" "$R" 'Finishing runs in a session of its own.'
says "auto-run.md: finishing's clear" "$R" '**Finishing** (§Finishing): `scripts/auto-run clear --phase`.'
says "auto-run.md: where the clean session reads" "$R" 'the ledger'"'"'s parked and `Ruling:` lines, the `final review residual` register rows, and the workspace'"'"'s `final-fix-report.md` and `final-rereview-report.md`'
says "auto-run.md: after-compact in finish" "$R" 'since the plan and the final review stay in this session and finishing runs in one of its own.'
```

In `plugins/dforge/tests/auto-run-skills.test.sh`, delete the line `names "finishing: fail and flaky counts are not read" ...`, because `auto-run.md` keeps that sentence and its own pin.

In `plugins/dforge/tests/auto-run.test.sh`, insert above the line `# --- the plan, final and finish phases never hand off ---`:

```bash
# --- finishing in a clean session: phase finish first, then a phase clear ---
ar --session s-1 start --spec "$SPEC" --register docs/r.md --force >/dev/null
ar --session s-1 attach --plan docs/plan.md
ar --session s-1 phase final
ar --session s-1 phase finish
# The prompt next-step writes for a clean final review (next-step.test.sh).
finish_prompt='Resume `docs/plan.md` with dforge:resume-execution. Run dforge:finishing-a-development-branch.'
cp "$REPO/.dforge/handoff/latest.md" "$TMP/latest.keep"
sed "s|^Execute docs/plan.md with dforge:subagent-driven-development\.$|$finish_prompt|" "$TMP/latest.keep" > "$REPO/.dforge/handoff/latest.md"
ar --session s-1 clear --phase; status=$?
check "finishing's clear: exit 0, phase finish, clear pending" "$status:$(field phase):$(field pending)" "0:finish:clear"
check "finishing's clear: no self-resume" "$(field resumes)" "0"
check "finishing's clear: next-step's finishing prompt" "$(field resumePrompt)" "$finish_prompt"
cp "$TMP/latest.keep" "$REPO/.dforge/handoff/latest.md"
ar --session s-1 start --spec "$SPEC" --register docs/r.md --force >/dev/null

```

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 60 bash plugins/dforge/tests/final-phase.test.sh`
Expected: FAIL on every check added above except `finishing: only the Auto run section names auto-run clear`, `session budget: attended finishing stays` and `handoff: attended finishing stays`, which pin what must not change. The `finishing's clear` checks in `auto-run.test.sh` pass already: they pin the state behaviour the new rule relies on.

- [ ] **Step 3: Implement**

1. `skills/finishing-a-development-branch/SKILL.md`, `## Auto run`: replace the opening so it reads, keeping the exit 4 parenthetical unchanged: ``When `scripts/auto-run status` exits 0 ([auto-run.md](../../reference/auto-run.md)) and its phase is not `finish`, run `scripts/auto-run phase finish` (exit 4: ...), dforge:handoff steps 0-3, `scripts/next-step PLAN_FILE` and `scripts/auto-run clear --phase`, and end the turn with `Auto run: clearing`. In phase `finish`, follow this skill with these changes:`` Delete from the Step 4 bullet the sentence beginning `The line's `fail` and `flaky` counts are not read:` through `does not keep the branch.`, which `auto-run.md` §Finishing already holds, so the file stays under 20,000 bytes. Do not delete the sentence `The mapping keeps the recorded-choice block's first call`. Keep the exit-4 parenthetical on one physical line as it is today: `tests/auto-run-worktree-setting.acceptance.test.sh` greps it.
2. `reference/auto-run.md` §Finishing: insert this paragraph first: ``Finishing runs in a session of its own. At the entry of dforge:finishing-a-development-branch, a run whose phase is not `finish` runs, in order, `scripts/auto-run phase finish`, dforge:handoff steps 0-3 (do not end the session), `scripts/next-step PLAN_FILE` and `scripts/auto-run clear --phase`, and ends the turn with `Auto run: clearing`. A commit in handoff step 2 moves HEAD and costs one suite run at finishing's first step. `next-step`'s exits 4 and 5 are handled as §Clears says; a nonzero `clear --phase` stops the run as §Stopping says. The cleared session arrives through dforge:resume-execution with phase `finish`, and has no conversation behind it: what the final review left open is in the ledger's parked and `Ruling:` lines, the `final review residual` register rows, and the workspace's `final-fix-report.md` and `final-rereview-report.md`; read them for Step 5b's findings and for the review's report.``
3. `reference/auto-run.md` §Clears: add the bullet `- **Finishing** (§Finishing): `scripts/auto-run clear --phase`.` after the `**The switch**` bullet. §After a compaction: `since the plan, the final review and finishing stay in this session` becomes `since the plan and the final review stay in this session and finishing runs in one of its own`.
4. `reference/final-review.md`, §Who runs it, first bullet: after `Once the review is clean, finishing follows with no budget check.` add `In an auto run finishing clears the session first (auto-run.md §Finishing).`
5. `reference/session-budget.md`: `Once the final review is clean, finishing runs in the same session.` gains ` In an auto run it runs in a session of its own ([auto-run.md](auto-run.md) §Finishing).` §Auto run gains the sentence `Finishing runs in a session of its own.` at its end. §Stops `Never a stop`: after `The final review and finishing follow in the same session whatever `context-size --final` prints` keep the sentence and append at the bullet's end ` In an auto run finishing clears the session first.`
6. `skills/handoff/SKILL.md` `When`, the auto-run bullet: after the sentence about a compaction that left too much, add `It also clears before finishing (auto-run.md §Finishing), through dforge:finishing-a-development-branch.`
7. `README.md` §Session budget `Stops`: after `finishing always run in the same session.` add ` In an auto run, finishing runs in a session of its own.`

- [ ] **Step 4: Run test to verify it passes**

Run: `timeout 60 bash plugins/dforge/tests/final-phase.test.sh`
Expected: PASS, `0 failed`.

Run: `timeout 120 bash plugins/dforge/tests/auto-run-skills.test.sh`
Expected: PASS, `0 failed`.

Run: `timeout 300 bash plugins/dforge/tests/auto-run.test.sh`
Expected: PASS, `0 failed`.

Run: `wc -c plugins/dforge/skills/finishing-a-development-branch/SKILL.md`
Expected: at most 20000.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/skills/finishing-a-development-branch/SKILL.md plugins/dforge/reference/auto-run.md plugins/dforge/reference/final-review.md plugins/dforge/reference/session-budget.md plugins/dforge/skills/handoff/SKILL.md plugins/dforge/README.md plugins/dforge/tests/final-phase.test.sh plugins/dforge/tests/auto-run-skills.test.sh plugins/dforge/tests/auto-run.test.sh
git commit -m "feat(dforge): finish auto runs in a clean session"
```
