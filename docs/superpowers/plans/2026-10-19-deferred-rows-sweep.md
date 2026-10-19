# Deferred Rows Sweep Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: the skill the **Execution:** line names — dr-superpowers:subagent-driven-development for `subagent`, dr-superpowers:executing-plans for `inline`. Steps use checkbox (`- [ ]`) syntax for tracking.

> **External executors:** codex

**Goal:** Fix the 118 still-real findings that sat as deferred rows in nine item registers, and release dforge 4.2.0.

**Architecture:** One task per cluster of findings, grouped by the area that owns its files (cockpit, skill text, config and plan tooling, validation and evals, darkmem sync, migration, auto-run scripts, release), in the spec's phase order. Every behaviour change lands with a test that fails first; text-only changes are checked by grep and by the suites that read the text.

**Tech Stack:** Bash scripts and their bash test suites, Node ES modules with `node --test`, the Claude Code mod (TypeScript/TSX) tested with `claude plugin test`, Markdown skills and references.

**Spec:** docs/superpowers/specs/2026-10-19-deferred-rows-sweep-design.md

**Execution:** subagent — `claude --model sonnet --effort high` — the plan runs parallel waves, which only subagent mode can run

**Plan review:** 2026-10-19 — dr-superpowers:judge-opus — executability 17 / coherence 17 / coverage 17 / assumptions 15 (round 2)

**Parallelism:** waves — 1-3 | 4-5 | 6 | 7 | 8 | 9 | 10 | 11 | 12 | 13 | 14 | 15 | 16 | 17 | 18 | 19-20 | 21-22 | 23 | 24 | 25 | 26 | 27 | 28 | 29 | 30 | 31 | 32 | 33 | 34 | 35 | 36 | 37 | 38 | 39

**Integration check:** `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID timeout 1800 node scripts/test-all.mjs && timeout 120 node scripts/validate-repository.mjs && timeout 120 /root/.local/bin/claude plugin validate . && timeout 120 /root/.local/bin/claude plugin validate plugins/dforge && timeout 120 /root/.local/bin/claude plugin validate plugins/dr-status && timeout 120 /root/.local/bin/claude plugin validate plugins/darkraise-ui && timeout 120 /root/.local/bin/claude plugin validate plugins/darkraise-win32ui && env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID timeout 300 /root/.local/bin/claude plugin test plugins/dforge`

**Worktree setup:** none

## Global Constraints

- Work in a worktree branched from local `main` (local `main` runs ahead of `origin/main`): `git worktree add .claude/worktrees/deferred-rows-sweep -b deferred-rows-sweep main`. Do not push.
- Commit identity: run `git config user.name Darkraise` and `git config user.email quangtc94@gmail.com` in the worktree before the first commit. No `Co-Authored-By`, `Claude-Session` or other AI attribution in any commit.
- Commit subjects: `<type>(<scope>): <subject>`, type one of feat|fix|docs|style|refactor|test|chore|perf, at most 50 characters, imperative, no period.
- Never edit plans, specs or notes under `docs/superpowers/`; register rows change only through `scripts/register` (the installed plugin's copy, `<plugin-root>/scripts/register`).
- Every test, build or CLI command runs under `timeout`; leave no process running.
- Run every test suite, `scripts/test-all.mjs` and `claude plugin test` with `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID` in front. Until Tasks 35 and 36 make the suites unset these themselves, a suite that runs `context-size`, `task-brief` or `auto-run` would otherwise bind to the live auto run of the session executing this plan. Suites that need a session id set their own.
- `test-all.mjs` runs the cockpit suite only when `claude` is on PATH, which it is not here (a shell function), so the integration check runs `claude plugin test` itself.
- `claude` is a shell function on this host: call `/root/.local/bin/claude`.
- Each suite makes its own temporary directories, so tasks in one wave cannot meet at run time; the cockpit suite runs inside `claude plugin test`.
- Keep `DCC_*` variables and statusline storage paths as they are.
- When a quoted anchor line is not found, the file changed since the task was written: find the code by its function and intent, make the same change, and say so in the task report. Never invent a change the task does not describe.

## Contracts

- `plugins/dforge/scripts/lib/darkmem-mirror.mjs` exports, from Task 20: `checkpointAtOf(state, workstream)` (string or null, that workstream's last synced checkpoint, falling back to an old single value), `newestCheckpointAt(state)` (string or null, the newest across all workstreams), `recordCheckpointAt(state, workstream, at)` (sets `state.checkpointAt[workstream] = at`, turning an old single value into the `"*"` entry). `loadState` accepts `checkpointAt` as null, a date string (old shape) or an object of workstream key (or `"*"`) to date string. Tasks 22 and 28 use them.
- `fileLatest` in `darkmem-progress-move.mjs` answers `{ hash, at, workstream, detail }` after Task 22; `renderCheckpoint` begins with `const synced = newestCheckpointAt(state);`. Tasks 27 and 28 quote that text.
- `primaryRoot` in `darkmem-config.mjs` falls back to `--show-toplevel` when the common-dir lookup fails (Task 19); Task 21's tests rely on it.
- The final review's skipped lenses go to the ledger as one line per lens, `final review lens-skipped <id> reason=cap` (Task 9 writes the rule; Task 10's `reference/auto-run.md` §Finishing reads it). It never starts with `Final review:`.
- A deferred wave task's ledger line and register note carry `; unmerged task ref <ref>` (Task 10 for the ledger line, Task 9 for finishing's register note).
- The executing skills' sentence ``After each `complete` and `fix round` line, run `scripts/darkmem-sync push`;`` stays on one line (Task 10 keeps it; Task 11's test pins it).
- Stop reasons in `scripts/lib/auto-run.sh` read their cap as digits, for example `after 3 compactions` (Task 34; the cockpit mock strings follow).
- The session-hygiene scan (Task 36) flags a `plugins/dforge/tests/*.sh` suite that runs `scripts/context-size`, `scripts/auto-run`, `scripts/task-brief`, `scripts/review-package` or `scripts/repo-audit`, or sources `auto-run.sh` or `context.sh`, unless it exports or unsets both `AR_SESSION` and `CLAUDE_CODE_SESSION_ID`; Task 35 fixes every suite it flags today.
- `config/schema.mjs` exports `isValidValue(spec, value)` and `config/schema.d.mts` declares it (Task 37).

## Assumptions (evidence)

- The Codex executor lane is on: `scripts/codex-gate` printed `usable=true reason=ok review=true lane=true` (probe, 2026-10-19), and docs/superpowers/distilled/constraints.md ticks it for this repository.
- The cockpit suite does not load in the Codex sandbox (register AE row 12), so no task that edits or runs `cockpit.test.ts` carries an Executor line.
- The darkmem sync suites start a localhost stub server, which the Codex sandbox refuses (register DM row 32's note), so no darkmem task carries an Executor line.
- plan-lint warns that Tasks 1, 7, 11, 24, 29, 34 and 38 are lane-eligible with no Executor line: Tasks 1, 7 and 38 edit the cockpit, and Task 34 edits `cockpit.test.ts`'s mock strings (the cockpit suite cannot run in the sandbox); Tasks 11, 24 and 29 run darkmem sync suites (localhost stub). They stay on the Claude lane by design.
- Where a task departs from the spec's wording, reading the code required it: DM 22 keeps `dforge_name`'s working-directory test (callers pass paths relative to it) and adds a test pinning that; FS 7 takes `tr` out of the pipeline so `|| value=""` tests dforge-config's own status, instead of deleting the fallback that keeps `dforge_setting` from failing a `set -e` caller; AE 10.L1 puts the "Outside `autoRun=on`," sentence before the `specReview=false` sentence, which `tests/settings-skills.test.sh` greps verbatim; DM 42 closes a finished plan's workstream and otherwise leaves the append's state, never reopening by PATCH; DM 50 bounds the config lookup inside `darkmem_push_quietly` (30 s), since bounding it only in the Stop script would not reach the second lookup.
- A subagent's shell has the controller's `CLAUDE_CODE_SESSION_ID` and the same set of `CLAUDE_*` variables (probe, 2026-10-19), so the session fix is test hygiene plus a prompt rule, not a script guard.
- `npx -y -p typescript@5.6.3 tsc` fetches and runs here (2026-10-19). On f2471d7 it reported 5 errors in 3 files: `config.ts` (Task 37) and `register.tsx`/`cockpit.test.ts` (Task 38). Until Task 38 lands, `node scripts/test-all.mjs` fails on a host with `tsc` on PATH and generated types; this host has no `tsc` on PATH, so the integration check prints the skip line.
- This repository keeps the `docs/superpowers/` layout, which the in-tree dforge `register check` resolves to a missing `docs/dforge/` (2026-10-19), so register checks use the installed plugin's script.
- darkmem row 37's "re-hash just before the removal" is already true: `localHash` and `fs.rmSync` run in one synchronous step in `removeVanished`, so Task 25 adds no second hash.
- darkmem row 43's `stateRel` guard is dropped: `stateRel` is always `.dforge` (`dforgeDir("state", cfg.repoRoot)`), so no test could reach it.
- The session-hygiene scan is a line heuristic: a suite that runs the scripts only through a helper taking the script name as an argument is not seen (`tests/working-directory.test.sh` is caught only by a literal path elsewhere in it).
- Executor tasks run alone in their wave, so most of this plan runs one task at a time; the waves of two or three tasks are the Claude-lane tasks that share no file.

## Task index

1. Measure a plan's tail against the final limit
2. Relabel older-layout checks and size comment
3. Follow link chains and keep the owner in dforge-config
4. Harden the cockpit's auto-run stages and watchdog
5. Type-check the dforge mod in test-all when possible
6. Fix the settings import, locks and editors
7. Refresh darkmem roots on config change
8. Align brainstorming and writing-plans auto-run text
9. Fix the final review and finishing text
10. Fix auto-run text in the execution skills
11. Qualify handoff and entry text, name Codex push
12. Fix README, prompt and reference text gaps
13. Harden plan-lint's Codex header checks
14. Keep empty register cells in their place
15. Name every ladder offender and fix fixture agents
16. Tighten the repository validator's name sweeps
17. Align the CI CLI pin and drop the dependency smoke
18. Count failed Bash ledger writes and widen script paths
19. Resolve submodules and linked darkmem config keys
20. Load a per-workstream checkpointAt
21. Key trailing slashes and keep mirror plans local
22. Track each workstream's last synced checkpoint
23. Harden mirror paths, splits and state loading
24. Report import and archive refusals once
25. Guard pull's removal of vanished documents
26. Harden reconcile's document moves
27. Harden the progress move into darkmem
28. Guard the progress move back to the checkout
29. Fit session lines in order and unnest the Stop push
30. Close the home migration's gaps
31. Make dforge-migrate's dry run match the real run
32. State the migrate skill's scope and dry-run limit
33. Fix auto-run start lock, beat skew and stale state
34. Build stop reasons from caps, quote the root
35. Unset the session ids in script suites
36. Scan the suites for session hygiene
37. Share the settings value check
38. Clear the cockpit's type errors
39. Release dforge 4.2.0

---

### Task 1: Measure a plan's tail against the final limit

**Files:**
- Modify: `plugins/dforge/hooks/cockpit/lib.ts`
- Modify: `plugins/dforge/hooks/cockpit/register.tsx`
- Test: `plugins/dforge/tests/cockpit.test.ts`

**Interfaces:**
- Consumes: None
- Produces: `isPlanTail(run: { done: number; total: number; isFinished: boolean }): boolean`, exported from `hooks/cockpit/lib.ts`

**Items:** AE 8, RO 21

**Depends on:** none
**Implementer:** dr-superpowers:impl-sonnet-low
**Evaluation:** files 1 - spec 0 - coupling 0 - risk 1 = 2

The cockpit's `refresh` measures a plan session's context against the handoff
budget (`budgetFor`) even when the session's plan has two tasks left or fewer, or is
in its final phase. The budget line (`scripts/lib/context.sh`, `CTX_TAIL_TASKS=2`)
measures those against the final-phase limit (`finalLimitFor`). After this task,
`refresh` uses `finalLimitFor` for both the budget and the handoff note once the
Run card's summary (the `run` atom, which `readRun` builds from `parseLedger` and
`planTasks`) shows at most two tasks left or a clean final review. RO 21 is a
coverage-only test: a recorded finish choice with nothing live starts no
once-a-second redraw.

- [ ] **Step 1: Write the failing tests**

These tests prove that a plan with two tasks left or fewer, or in its final phase, gets no handoff note between the 464,500 budget and the 552,500 final-phase limit (650k window), that it still gets the note past the final limit, that three tasks left still get it at the budget, and that a recorded finish choice starts no redraw ticker.

In `plugins/dforge/tests/cockpit.test.ts`, add `isPlanTail` to the import from `'../hooks/cockpit/lib'`. Replace:

```ts
  isDforge,
  attributionIn,
```

with:

```ts
  isDforge,
  isPlanTail,
  attributionIn,
```

Then, inside `describe('run card', …)`, insert the following immediately before the line `  test('reads the finish choice', () => {`:

```ts
  // Five tasks in the 650k window: the handoff budget is 464,500 and the
  // final-phase limit 552,500. A plan's last two tasks and its final phase
  // measure against the latter, as scripts/lib/context.sh's tail does.
  const TAIL_PLAN = `# Plan\n\n${[1, 2, 3, 4, 5].map(n => `### Task ${n}: Step ${n}\n`).join('\n')}`
  const tailLedger = (done: number, isFinished: boolean) =>
    [
      '# SDD ledger — plan: docs/plans/p.md',
      ...Array.from({ length: done }, (_, i) => `Task ${i + 1}: complete (commits a..b, review clean) — done: x; verified: y; remaining: none; discovered: none; assumptions: none`),
      ...(isFinished ? ['Final review: clean (commits a..b)'] : []),
    ].join('\n')

  test('a run is at its tail with two tasks left or fewer, or once its final review is clean', () => {
    expect(isPlanTail({ done: 2, total: 5, isFinished: false })).toBe(false)
    expect(isPlanTail({ done: 3, total: 5, isFinished: false })).toBe(true)
    expect(isPlanTail({ done: 5, total: 5, isFinished: false })).toBe(true)
    expect(isPlanTail({ done: 0, total: 0, isFinished: false })).toBe(false)
    expect(isPlanTail({ done: 0, total: 0, isFinished: true })).toBe(true)
  })

  for (const [name, done, isFinished, tokens, note] of [
    ['three tasks left', 2, false, 500_000, /^dforge: budget: 500k of 465k — handoff\. /],
    ['two tasks left', 3, false, 500_000, null],
    ['every task complete', 5, false, 500_000, null],
    ['the final review clean', 5, true, 500_000, null],
    ['two tasks left, past the final-phase limit', 3, false, 560_000, /^dforge: budget: 560k of 553k — handoff\. /],
  ] as const) {
    test(`the handoff note with ${name} at ${tokens / 1000}k`, async ($, on) => {
      const notes: string[] = []
      const files: World['files'] = {
        '/home/me/code/shop/.dforge/sdd/p/progress.md': { text: tailLedger(done, isFinished), mtimeMs: 2_000_000 },
        '/home/me/code/shop/docs/plans/p.md': { text: TAIL_PLAN },
      }
      world(on, { ...SIGNED_IN, tokens, notes, files })
      signedIn(on, files)
      // The session start reads the ledger; the Skill call makes it a plan session.
      await $.session.start(START)
      await $.tool.call({ tool: 'Skill', skill: 'dforge:subagent-driven-development' })
      const sent = notes.filter(text => /— handoff\./.test(text))
      if (note === null) expect(sent).toEqual([])
      else expect(sent).toEqual([expect.stringMatching(note)])
    })
  }

  test('a ledger write that reaches the tail is read before the budget in the same call', async ($, on) => {
    const notes: string[] = []
    const files: World['files'] = {
      '/home/me/code/shop/.dforge/sdd/p/progress.md': { text: tailLedger(2, false), mtimeMs: 2_000_000 },
      '/home/me/code/shop/docs/plans/p.md': { text: TAIL_PLAN },
    }
    const w: World = { ...SIGNED_IN, tokens: 400_000, notes, files }
    world(on, w)
    signedIn(on, files)
    await $.session.start(START)
    await $.tool.call({ tool: 'Skill', skill: 'dforge:subagent-driven-development' })
    // One call both completes Task 3 (two tasks left) and crosses the 465k budget.
    files['/home/me/code/shop/.dforge/sdd/p/progress.md'] = { text: tailLedger(3, false), mtimeMs: 2_100_000 }
    w.tokens = 500_000
    await $.tool.call({ tool: 'Bash', command: 'echo "Task 3: complete" >> .dforge/sdd/p/progress.md' })
    expect(notes.filter(text => /— handoff\./.test(text))).toEqual([])
  })

  test('a recorded finish choice starts no once-a-second redraw', async ($, on) => {
    const files = {
      ...runFiles(LEDGER),
      '/home/me/code/shop/.dforge/sdd/p/finish.json': { text: '{"action":"merge","base":"main","chosenAt":900,"armedAt":1000,"dueAt":2800}' },
    }
    let redraws = 0
    const clock = world(on, { ...SIGNED_IN, files })
    on('ui.invalidate', () => {
      redraws++
      return { value: undefined } as never
    })
    signedIn(on, files)
    await $.tool.call({ tool: 'Skill', skill: 'dforge:subagent-driven-development' })
    await $.session.start(START)
    await clock.advance(5_000)
    expect(redraws).toBe(0)
    // A live turn does tick: the count above would have seen a ticker.
    await $.turn.start({ text: 'go', turnId: 't1' })
    await clock.advance(2_000)
    expect(redraws).toBeGreaterThan(0)
  })
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `timeout 300 /root/.local/bin/claude plugin test plugins/dforge`
Expected: FAIL — the file does not load, because `lib.ts` has no `isPlanTail`
export. If you comment out the `isPlanTail` import and unit test to check the
rest: the "two tasks left", "every task complete" and "the final review clean" cases
get a `budget: 500k of 465k — handoff` note, and the past-the-final-limit case
gets `560k of 465k`. "three tasks left" and the finish-choice redraw test pass
(the redraw test only adds coverage, RO 21). Restore the import before Step 3. The new "ledger write that reaches the tail" test
fails too: the Bash call refreshes the budget before it re-reads the ledger,
so it still sees three tasks left and sends a `500k of 465k` note.

- [ ] **Step 3: Implement**

In `plugins/dforge/hooks/cockpit/lib.ts`, insert immediately before the line
`const RUN_ORDER: Readonly<Record<string, number>> = { assigned: 0, blocked: 1, pending: 2, complete: 3 }`:

```ts
// A plan's last tasks join its final phase once this many or fewer remain
// (CTX_TAIL_TASKS in scripts/lib/context.sh).
const TAIL_TASKS = 2

/**
 * Whether a run is at its plan's tail or in its final phase: at most
 * TAIL_TASKS tasks left by its ledger, or its final review clean. The budget
 * line measures both against the final-phase limit.
 */
export function isPlanTail(run: { done: number; total: number; isFinished: boolean }): boolean {
  return run.isFinished || (run.total > 0 && run.total - run.done <= TAIL_TASKS)
}

```

In `plugins/dforge/hooks/cockpit/register.tsx`, add the import. Replace:

```ts
  isDforge,
  kTokens,
```

with:

```ts
  isDforge,
  isPlanTail,
  kTokens,
```

Then in `refresh`, replace:

```ts
  const auto = await read($, autoRun)
  const isAuto = auto !== null && auto.active
  const limit = isAuto
    ? autoLimitFor(auto.regime, handoffTokens, window, compactWindow)
    : tuning.isRelaxed
      ? finalLimitFor(window, compactWindow)
      : budgetFor(handoffTokens, undefined, window, compactWindow)
```

with:

```ts
  const auto = await read($, autoRun)
  const isAuto = auto !== null && auto.active
  // A plan's last tasks and its final phase share the final-phase limit, as
  // the budget line measures them; the handoff note follows the same limit.
  const summary = await read($, run)
  const isTail = summary !== null && isPlanTail(summary)
  const limit = isAuto
    ? autoLimitFor(auto.regime, handoffTokens, window, compactWindow)
    : tuning.isRelaxed || isTail
      ? finalLimitFor(window, compactWindow)
      : budgetFor(handoffTokens, undefined, window, compactWindow)
```

(`run` is the existing atom `const run = atom({ plugin: 'dforge', key: 'run' } as const, null)`;
`readRun` fills it from `parseLedger` and `planTasks`. Do not name the local `plan`:
that is another atom.)

Then make both events read the ledger before they measure the budget, so a
ledger write that reaches the tail is seen by the same event's check.

In the `tool.call` handler, replace:

```ts
      await onBudget($, await refresh($, (await live($)).tuning, compactWindow))
      // The controller writes its ledger with its own tool calls.
      if (/\.dforge|\.dforge|finish-choice/.test(JSON.stringify(e))) await readRun($)
```

with:

```ts
      // The controller writes its ledger with its own tool calls; read it
      // before the budget, which measures a plan's tail by it.
      if (/\.dforge|\.dforge|finish-choice/.test(JSON.stringify(e))) await readRun($)
      await onBudget($, await refresh($, (await live($)).tuning, compactWindow))
```

(Task 7 later removes the repeated `\.dforge` alternative from that regex;
keep it as it is here.)

In the `turn.complete` handler, replace:

```ts
      await trackAutoRun($)
      compactWindow = await readCompactWindow($)
      await onBudget($, await refresh($, (await live($)).tuning, compactWindow))
```

with:

```ts
      await trackAutoRun($)
      compactWindow = await readCompactWindow($)
      await readRun($)
      await onBudget($, await refresh($, (await live($)).tuning, compactWindow))
```

and delete the later `      await readRun($)` line in the same handler, the one
directly after the `await setActivity($, now => ({` … `}))` call and before
`      if (failed) {`.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `timeout 300 /root/.local/bin/claude plugin test plugins/dforge`
Expected: PASS, the existing `handoff reading`, `flight deck` (six tasks,
one done: still `handoff 465k`) and `auto run in the pane` tests included. No
other suite reads these files.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/hooks/cockpit/lib.ts plugins/dforge/hooks/cockpit/register.tsx plugins/dforge/tests/cockpit.test.ts
git commit -m "fix(cockpit): measure a plan's tail at the final limit"
```

---

---

### Task 2: Relabel older-layout checks and size comment

**Files:**
- Modify: `plugins/dforge/scripts/lib/snapshot.sh`
- Modify: `plugins/dforge/tests/hook.test.sh`
- Modify: `plugins/dforge/tests/repo-audit.test.sh`

**Interfaces:**
- Consumes: None
- Produces: None

**Items:** DR 31, DF 18

**Depends on:** none
**Implementer:** dr-superpowers:impl-sonnet-low
**Evaluation:** files 1 - spec 0 - coupling 0 - risk 0 = 1

This task covers DR 31 (the "pre-3.0:" labels become "older layout:", and repo-audit's ", and the command" wording is fixed) and DF 18, plugin half (snapshot.sh's size comment says about 5,000; the 5,100 cap in hook.test.sh stays). All three changes are to labels and a comment, and no assertion changes.

- [ ] **Step 1: Verify the current text**

Run: `grep -nF -e 'check "pre-3.0: ' plugins/dforge/tests/hook.test.sh`
Expected: two lines (`pre-3.0: output stays valid JSON` and `pre-3.0: the migration line is injected`).

Run: `grep -nF 'has "pre-3.0: the worktree'"'"'s and the primary'"'"'s directories, and the command"' plugins/dforge/tests/repo-audit.test.sh`
Expected: one line.

Run: `grep -nF 'already takes about 4,800;' plugins/dforge/scripts/lib/snapshot.sh`
Expected: one line.

- [ ] **Step 2: Run the suites before the change**

Run: `timeout 600 bash plugins/dforge/tests/hook.test.sh` and `timeout 600 bash plugins/dforge/tests/repo-audit.test.sh`
Expected: PASS. These are label-only changes, so no test fails first.

- [ ] **Step 3: Implement**

**3a. `plugins/dforge/tests/hook.test.sh`.** Replace:

```bash
check "pre-3.0: output stays valid JSON" "$(jq -e . >/dev/null 2>&1 <<<"$lg_out" && echo yes || echo no)" "yes"
check "pre-3.0: the migration line is injected" \
```

with:

```bash
check "older layout: output stays valid JSON" "$(jq -e . >/dev/null 2>&1 <<<"$lg_out" && echo yes || echo no)" "yes"
check "older layout: the migration line is injected" \
```

**3b. `plugins/dforge/tests/repo-audit.test.sh`.** Replace:

```bash
has "pre-3.0: the worktree's and the primary's directories, and the command" "$out" \
```

with:

```bash
has "older layout: the worktree's and the primary's directories, with the migrate command" "$out" \
```

**3c. `plugins/dforge/scripts/lib/snapshot.sh`.** Replace:

```bash
# Capped because hook output over 10,000 characters is replaced by a file
# reference, and the injected entry point already takes about 4,800;
# session-start.sh subtracts its measured length, so this is only the ceiling.
```

with:

```bash
# Capped because hook output over 10,000 characters is replaced by a file
# reference, and the injected entry point already takes about 5,000
# (tests/hook.test.sh caps it at 5,100 bytes); session-start.sh subtracts its
# measured length, so this is only the ceiling.
```

Leave `SNAPSHOT_CAP=5500` and the `-le 5100` check in `tests/hook.test.sh` unchanged.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `grep -c 'pre-3.0' plugins/dforge/tests/hook.test.sh plugins/dforge/tests/repo-audit.test.sh`
Expected: `plugins/dforge/tests/hook.test.sh:0` and `plugins/dforge/tests/repo-audit.test.sh:0`

Run: `grep -cF 'about 5,000' plugins/dforge/scripts/lib/snapshot.sh`
Expected: `1`

Run: `timeout 600 bash plugins/dforge/tests/hook.test.sh`
Expected: PASS, with the two cases now printed as `ok   - older layout: …`.

Run: `timeout 600 bash plugins/dforge/tests/repo-audit.test.sh`
Expected: PASS, with `ok   - older layout: the worktree's and the primary's directories, with the migrate command`.

The comment edit leaves the sourced functions unchanged, but these suites source snapshot.sh, so run them too:
- `timeout 600 bash plugins/dforge/tests/snapshot.test.sh`
- `timeout 600 bash plugins/dforge/tests/working-directory.test.sh`
- `timeout 600 bash plugins/dforge/tests/turn-end.test.sh`
- `timeout 300 node --test plugins/dforge/tests/darkmem-sync/hooks.test.mjs`

The last two run `session-start.sh`, which sources snapshot.sh. All must PASS.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/scripts/lib/snapshot.sh plugins/dforge/tests/hook.test.sh plugins/dforge/tests/repo-audit.test.sh
git commit -m "chore(dforge): relabel layout tests, size comment"
```

---

### Task 3: Follow link chains and keep the owner in dforge-config

**Files:**
- Modify: `plugins/dforge/scripts/lib/dforge-config.mjs`
- Modify: `plugins/dforge/scripts/lib/dforge-env.sh`
- Test: `plugins/dforge/tests/dforge-config.test.sh`
- Test: `plugins/dforge/tests/settings-skills.test.sh`

**Interfaces:**
- Consumes: None
- Produces: None

**Items:** FS 7, FS 9, FS 11, FS 34

**Depends on:** none
**Implementer:** dr-superpowers:impl-sonnet-medium
**Evaluation:** files 2 - spec 0 - coupling 0 - risk 2 = 4

- [ ] **Step 1: Write the failing tests**

The tests prove that a write through a dangling two-link chain keeps both links and creates the chain's end (FS 9), that a rewrite run as root keeps the file's owner and group (FS 11), that `dforge_setting` never uses what a failed command printed and never aborts a `set -e`/`pipefail` caller (FS 7), and that a skill names each skill-enforced key as `` `key` `` or `key=`, not as a bare word (FS 34).

Add the chain and owner cases at the end of the symlink block, after the existing dangling-symlink case:

In `plugins/dforge/tests/dforge-config.test.sh`, find:

```bash
  check "claude: its destination is created" "$(tr -d ' \n' < "$TMP/dotfiles/later.json")" '{"autoCompactWindow":600000}'
fi
```

Replace it with:

```bash
  check "claude: its destination is created" "$(tr -d ' \n' < "$TMP/dotfiles/later.json")" '{"autoCompactWindow":600000}'
  # A dangling chain is followed to its end: no link in it is replaced by a file.
  rm -f "$CS"; ln -s "$TMP/dotfiles/end.json" "$TMP/dotfiles/hop.json"; ln -s "$TMP/dotfiles/hop.json" "$CS"
  fc set autoCompactWindow 550000
  check "claude: a dangling chain: the first link stays" "$([ -L "$CS" ] && echo yes || echo no)" "yes"
  check "claude: a dangling chain: the middle link stays" "$([ -L "$TMP/dotfiles/hop.json" ] && echo yes || echo no)" "yes"
  check "claude: a dangling chain: its end is created" "$(tr -d ' \n' < "$TMP/dotfiles/end.json" 2>/dev/null)" '{"autoCompactWindow":550000}'
fi

# As root, a rewrite keeps the file's owner and group: the temporary file is
# created by root and would otherwise hand a user's settings file to root.
if [ "$(id -u)" = 0 ] && ! command -v cygpath > /dev/null 2>&1; then
  mkdir -p "$TMP/alt-o"
  printf '%s\n' '{"model":"opus"}' > "$TMP/alt-o/settings.json"
  chown 4321:4322 "$TMP/alt-o/settings.json"
  CLAUDE_CONFIG_DIR="$TMP/alt-o" fc set autoCompactWindow 500000
  check "claude: as root, the value is written" "$(at "$TMP/alt-o/settings.json" autoCompactWindow)" "500000"
  check "claude: as root, the owner and group are kept" "$(node -e 'const s = require("fs").statSync(process.argv[1]); console.log(s.uid + ":" + s.gid)' "$TMP/alt-o/settings.json")" "4321:4322"
else
  echo "skip - the owner is kept when root writes (not running as root)"
fi
```

Add the `dforge_setting` cases after the `DFORGE_NO_SETTINGS` case:

In `plugins/dforge/tests/dforge-config.test.sh`, find:

```bash
check "DFORGE_NO_SETTINGS answers the default" "$(DFORGE_NO_SETTINGS=1 dforge_setting worktree ask)" "ask"
```

Replace it with:

```bash
check "DFORGE_NO_SETTINGS answers the default" "$(DFORGE_NO_SETTINGS=1 dforge_setting worktree ask)" "ask"
# A command that fails is never read for what it printed, with or without
# pipefail, and a caller under set -e and pipefail survives the failure.
mkdir -p "$TMP/fake/lib"
printf '#!/usr/bin/env bash\nprintf partial\nexit 1\n' > "$TMP/fake/dforge-config"
check "dforge_setting: a failed command's output is not used" "$(set +o pipefail; _DFORGE_ENV_DIR="$TMP/fake/lib"; dforge_setting worktree ask)" "ask"
check "dforge_setting: a set -e pipefail caller survives a failure" "$(set -eo pipefail; _DFORGE_ENV_DIR="$TMP/fake/lib"; dforge_setting worktree ask > /dev/null; echo survived)" "survived"
```

Tighten the per-key loop in the settings-skills suite:

In `plugins/dforge/tests/settings-skills.test.sh`, find:

```bash
# Every skill-enforced key in the schema is named by at least one skill.
```

Replace it with:

```bash
# Every skill-enforced key in the schema is named by at least one skill, as
# `key` or key=value: a bare word such as "worktree" is not a naming.
```

In `plugins/dforge/tests/settings-skills.test.sh`, find:

```bash
  check "a skill names $key" "$(grep -lF -- "$key" "$P"/skills/*/SKILL.md | head -n 1 | grep -c .)" "1"
```

Replace it with:

```bash
  check "a skill names $key" "$(grep -lE -- "\`$key\`|$key=" "$P"/skills/*/SKILL.md | head -n 1 | grep -c .)" "1"
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `timeout 600 bash plugins/dforge/tests/dforge-config.test.sh`
Expected: FAIL — 4 failures: "claude: a dangling chain: the middle link stays" (got `no`: the rename replaced `hop.json` with a regular file), "claude: a dangling chain: its end is created" (got empty: `end.json` was never written), "claude: as root, the owner and group are kept" (got `0:0`), and "dforge_setting: a failed command's output is not used" (got `partial`). On a host not running as root the owner case prints `skip - the owner is kept when root writes (not running as root)` instead of failing.

Run: `timeout 600 bash plugins/dforge/tests/settings-skills.test.sh`
Expected: PASS — every skill-enforced key (executionStrategy, executionMode, worktree, autoRun, processBias, designApproval, specReview, questionStyle) is already named as `` `key` `` or `key=` in a SKILL.md; the gap was that the loop also accepted a bare word.

- [ ] **Step 3: Implement**

FS 7: take `tr` out of the pipeline so `|| value=""` tests the command's own exit status, and strip carriage returns afterwards.

In `plugins/dforge/scripts/lib/dforge-env.sh`, find:

```bash
    value=$(DFORGE_NO_IMPORT=1 bash "$_DFORGE_ENV_DIR/../dforge-config" get "$1" 2>/dev/null | tr -d '\r') || value=""
```

Replace it with:

```bash
    value=$(DFORGE_NO_IMPORT=1 bash "$_DFORGE_ENV_DIR/../dforge-config" get "$1" 2>/dev/null) || value=""
    value=${value//$'\r'/}
```

FS 11: record the original's owner and group, and give them to the temporary file when running as root, before the rename.

In `plugins/dforge/scripts/lib/dforge-config.mjs`, find:

```js
// Replaces a file in one rename, keeping the mode it had: Claude's settings
// file may be private, and a temporary file would otherwise take the umask's.
function writeFile(file, data) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  let mode;
  try {
    mode = fs.statSync(file).mode & 0o777;
  } catch (error) {
    if (error.code !== "ENOENT") throw error;
  }
```

Replace it with:

```js
// Replaces a file in one rename, keeping the mode it had: Claude's settings
// file may be private, and a temporary file would otherwise take the umask's.
// Run as root (sudo, a container), it keeps the owner and group too, or the
// rename would hand the user's file to root.
function writeFile(file, data) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  let mode;
  let owner;
  try {
    const stat = fs.statSync(file);
    mode = stat.mode & 0o777;
    owner = { uid: stat.uid, gid: stat.gid };
  } catch (error) {
    if (error.code !== "ENOENT") throw error;
  }
```

In `plugins/dforge/scripts/lib/dforge-config.mjs`, find:

```js
    if (mode !== undefined) fs.chmodSync(temp, mode);
    fs.renameSync(temp, file);
```

Replace it with:

```js
    if (owner && process.getuid?.() === 0) fs.chownSync(temp, owner.uid, owner.gid);
    if (mode !== undefined) fs.chmodSync(temp, mode);
    fs.renameSync(temp, file);
```

FS 9: follow a dangling chain link by link to its first missing path, with a hop limit.

In `plugins/dforge/scripts/lib/dforge-config.mjs`, find:

```js
// The file a write lands on: where a symlink points, even when that
// destination does not exist yet, so a rename never replaces the link itself.
function realTarget(file) {
  try {
    return fs.realpathSync(file);
  } catch (error) {
    if (error.code !== "ENOENT") throw error;
  }
  try {
    return path.resolve(path.dirname(file), fs.readlinkSync(file));
  } catch {
    return file;
  }
}
```

Replace it with:

```js
const MAX_LINK_HOPS = 40;

// The file a write lands on: where a symlink points, even when that
// destination does not exist yet, so a rename never replaces the link itself.
// A dangling chain is followed link by link to its first missing path.
function realTarget(file) {
  try {
    return fs.realpathSync(file);
  } catch (error) {
    if (error.code !== "ENOENT") throw error;
  }
  let target = file;
  for (let hop = 0; hop < MAX_LINK_HOPS; hop++) {
    let link;
    try {
      link = fs.readlinkSync(target);
    } catch {
      return target;
    }
    target = path.resolve(path.dirname(target), link);
  }
  throw new Error(`${file}: more than ${MAX_LINK_HOPS} symbolic links`);
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `timeout 600 bash plugins/dforge/tests/dforge-config.test.sh`
Expected: PASS (181 passed, 0 failed when run as root).

Run: `timeout 600 bash plugins/dforge/tests/settings-skills.test.sh`
Expected: PASS.

Other suites that source `dforge-env.sh` or import `dforge-config.mjs`, which must still pass:
`timeout 600 bash plugins/dforge/tests/finish-choice.test.sh`,
`timeout 600 bash plugins/dforge/tests/codex-gate.test.sh`,
`timeout 600 bash plugins/dforge/tests/lens-route.test.sh`,
`timeout 600 bash plugins/dforge/tests/darkmem-sync.test.sh`, and the cockpit suite, which runs `dforge-config.mjs set`:
`timeout 300 /root/.local/bin/claude plugin test plugins/dforge`.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/scripts/lib/dforge-config.mjs plugins/dforge/scripts/lib/dforge-env.sh plugins/dforge/tests/dforge-config.test.sh plugins/dforge/tests/settings-skills.test.sh
git commit -m "fix(config): follow link chains, keep file owner"
```

---

### Task 4: Harden the cockpit's auto-run stages and watchdog

**Files:**
- Modify: `plugins/dforge/hooks/cockpit/register.tsx`
- Test: `plugins/dforge/tests/cockpit.test.ts`

**Interfaces:**
- Consumes: None
- Produces: None (test-harness `World` fields `gitRuns`, `commonDir`, `onAutoRun`, `sessionIdFailures`, local to `cockpit.test.ts`)

**Items:** AE 32, AE 34

**Depends on:** Task 1
**Implementer:** dr-superpowers:impl-sonnet-medium
**Evaluation:** files 1 - spec 1 - coupling 0 - risk 2 = 4

This task makes five fixes. The first four are AE 32 sub-findings and AE 34;
the fifth, the watchdog's guards, is the rest of AE 34:
1. **32.L1:** in the switch stage, a `skip` answer from `$.session.compact` no
   longer throws (which booked a failure). It is booked as
   `compacted --switch` and the stage goes on to switch-resume. The run's status
   then counts one compaction that did not run. That count is informational, and
   it stays.
2. **32.L4:** the cockpit derives the primary checkout as `ar_primary_root` in
   `scripts/lib/auto-run.sh` does:
   `git -C <dirname of the common dir> rev-parse --show-toplevel`. A submodule
   then has no primary, as in the scripts.
3. **32.L7, cockpit half:** the plugin root is quoted
   (`bash "<root>/scripts/auto-run" …`) in all three model-facing prompts the
   cockpit builds: the continue prompt, the stall prompt, and the
   switch-resume lead. `turn-end.sh` is P2's.
4. **AE 34, deferral:** the deferral clock resets while a turn is live.
5. **AE 34, watchdog:** after a failed `stalled` call the watchdog waits one
   `STALL_MS` before it tries again, and `beat` has its own catch, so a failed
   heartbeat cannot abort the tick. The cap's exit-5 and other non-zero branches
   get coverage tests, and so does the turn guard after the `stalled` call.

- [ ] **Step 1: Write the failing tests**

The tests prove each fix above. The harness first learns to answer
`git -C … rev-parse --show-toplevel`, to record git calls, to fail a
session-id read, and to run code inside a `scripts/auto-run` call.

In `plugins/dforge/tests/cockpit.test.ts`, extend `type World`. Replace:

```ts
  /** How long each compaction takes, in the clock's milliseconds; at once unless said. */
  compactMs?: number
}
```

with:

```ts
  /** How long each compaction takes, in the clock's milliseconds; at once unless said. */
  compactMs?: number
  /** Each git command the plugin runs, as one line. */
  gitRuns?: string[]
  /** What `git rev-parse --git-common-dir` answers; `<primary>/.git` unless said. */
  commonDir?: string
  /** Runs inside each scripts/auto-run call, given its command word, before the call answers. */
  onAutoRun?: (word: string) => unknown
  /** How many `$.session.id()` calls fail before one answers. */
  sessionIdFailures?: number
}
```

In `function world`, replace:

```ts
        w.autoFile.text = JSON.stringify(state)
      }
      return { value: { exitCode, stdout: '', stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }
    }
```

with:

```ts
        w.autoFile.text = JSON.stringify(state)
      }
      const answer = { value: { exitCode, stdout: '', stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }
      const during = w.onAutoRun?.(word)
      return during instanceof Promise ? during.then(() => answer) : answer
    }
```

Replace:

```ts
    const stdout = argv === 'hostname' ? 'devbox\n' : argv.startsWith('git rev-parse') ? `${w.primary ?? '/home/me/code/shop'}/.git\n` : PORCELAIN
    return { value: { exitCode: 0, stdout, stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }
```

with:

```ts
    if (argv.startsWith('git ')) w.gitRuns?.push(argv)
    const common = w.commonDir ?? `${w.primary ?? '/home/me/code/shop'}/.git`
    // A directory is a work tree when the common directory is its .git: a
    // primary checkout is; a submodule's modules directory is not.
    const toplevel = /^git -C (.+) rev-parse --show-toplevel$/.exec(argv)
    if (toplevel !== null) {
      const isTree = `${toplevel[1]}/.git` === common
      return {
        value: {
          exitCode: isTree ? 0 : 128,
          stdout: isTree ? `${toplevel[1]}\n` : '',
          stderr: isTree ? '' : 'fatal: not a git repository (or any of the parent directories): .git\n',
          isStdoutTruncated: false,
          isStderrTruncated: false,
        },
      }
    }
    const stdout = argv === 'hostname' ? 'devbox\n' : argv.startsWith('git rev-parse') ? `${common}\n` : PORCELAIN
    return { value: { exitCode: 0, stdout, stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }
```

Replace:

```ts
  on('session.id', () => ({ value: w.sessionId ?? 'sess-1' }))
```

with:

```ts
  on('session.id', () => {
    if ((w.sessionIdFailures ?? 0) > 0) {
      w.sessionIdFailures = (w.sessionIdFailures ?? 1) - 1
      throw new Error('no session id')
    }
    return { value: w.sessionId ?? 'sess-1' }
  })
```

**32.L7 (quoted root):** tighten the existing prompt assertions. In the test
`'compacts on the sentinel, books it and submits the continue prompt'`, replace:

```ts
    expect(w.prompts?.[0]).toMatch(/scripts\/auto-run after-compact/)
```

with:

```ts
    expect(w.prompts?.[0]).toMatch(/`bash "[^"]*\/scripts\/auto-run" after-compact`/)
    expect(w.prompts?.[0]).toMatch(/`bash "[^"]*\/scripts\/auto-run" status` names/)
```

In `'switches in place: compacts, books it, sets the model and submits the first prompt'`, replace:

```ts
    expect(w.prompts?.[0]).toMatch(/^Run `bash .*\/scripts\/auto-run after-compact` first\. Continue `docs\/plan\.md`/)
```

with:

```ts
    expect(w.prompts?.[0]).toMatch(/^Run `bash "[^"]*\/scripts\/auto-run" after-compact` first\. Continue `docs\/plan\.md`/)
```

In `'nudges a stalled run, and again only once its last nudge is as old'`, replace:

```ts
      expect.stringMatching(/^The auto run stalled: the last turn ended without its sentinel line\. Run `bash .*\/scripts\/auto-run status`, continue the phase it names, and end the turn as reference\/auto-run\.md §Ending a turn says\.$/),
```

with:

```ts
      expect.stringMatching(/^The auto run stalled: the last turn ended without its sentinel line\. Run `bash "[^"]*\/scripts\/auto-run" status`, continue the phase it names, and end the turn as reference\/auto-run\.md §Ending a turn says\.$/),
```

**32.L1 (switch over a refused compaction):** insert immediately before the line
`  test('stops the run when the switch cannot book its resume', async ($, on) => {`:

```ts
  test('switches over a refused compaction: books it and submits the first prompt', async ($, on) => {
    const files = autoFiles({ phase: 'execute', pending: 'switch', resumePrompt: 'Continue `docs/plan.md`.', launch: null })
    const w: World = { ...SIGNED_IN, compacts: [], autoRuns: [], prompts: [], autoFile: files[AUTO], isCompactVetoed: true }
    const clock = world(on, w)
    signedIn(on, files)
    await $.session.start(START)
    await $.turn.complete({ answer: 'Plan saved.\n\nAuto run: switching', durationMs: 1, isAborted: false, turnId: 't1', reason: 'answer' })
    await settle(clock)
    expect(w.compacts).toHaveLength(1)
    expect(w.autoRuns?.filter(call => call.includes(' failure '))).toEqual([])
    expect(w.autoRuns).toContain('--session sess-1 compacted --switch')
    expect(w.prompts).toEqual([expect.stringMatching(/after-compact` first\. Continue `docs\/plan\.md`\.$/)])
    expect(pendingOf(files)).toBe('after-compact')
  })

```

**32.L4 (primary checkout):** inside `describe('cockpit roots', …)`, insert
immediately before the line
`  test('a changed stores.json moves the card to the new roots', async ($, on) => {`:

```ts
  test('takes the primary checkout from the common directory, as the scripts do', async ($, on) => {
    // stores.json makes the cockpit ask darkmem-config for the primary's roots.
    const files: NonNullable<World['files']> = { '/home/me/.dforge/stores.json': { text: '{}', mtimeMs: 1 } }
    const gitRuns: string[] = []
    const modeRuns: string[] = []
    world(on, { ...SIGNED_IN, files, primary: '/home/me/code/main', gitRuns, modeRuns })
    signedIn(on, files)
    await $.session.start(START)
    expect(gitRuns).toContain('git -C /home/me/code/main rev-parse --show-toplevel')
    expect(modeRuns).toEqual(['/home/me/code/main'])
  })

  test('a submodule has no primary checkout, as in the scripts', async ($, on) => {
    const files: NonNullable<World['files']> = { '/home/me/.dforge/stores.json': { text: '{}', mtimeMs: 1 } }
    const modeRuns: string[] = []
    world(on, { ...SIGNED_IN, files, commonDir: '/home/me/code/shop/.git/modules/web', modeRuns })
    signedIn(on, files)
    await $.session.start(START)
    // With no primary, the session's own repository stands in.
    expect(modeRuns).toEqual(['/home/me/code/shop'])
  })

```

**AE 34 (deferral, cap branches):** inside `describe('auto run', …)`, insert
immediately before the line
`  test("starts a new run's deferral afresh after the last one stopped", async ($, on) => {`:

```ts
  test('a live turn restarts the deferral, so the cap counts background work alone', async ($, on) => {
    const files = autoFiles()
    const w: World = { ...SIGNED_IN, compacts: [], autoRuns: [], autoFile: files[AUTO] }
    const clock = world(on, w)
    signedIn(on, files)
    await $.session.start(START)
    await $.agent.spawn({
      tool_use_id: 'toolu_1',
      prompt: 'Implement task 4',
      description: 'Task 4',
      subagentType: 'dforge:impl-sonnet-low',
      provider: { plugin: 'dforge', tier: 'user' },
      parentModel: 'claude-opus-5-5',
      background: true,
      fork: false,
    })
    await $.turn.complete({ answer: SENTINEL, durationMs: 1, isAborted: false, turnId: 't1', reason: 'answer' })
    await settle(clock)
    await $.turn.start({ text: 'How is Task 4 going?', turnId: 't2' })
    await clock.advance(1_795_000)
    await $.turn.complete({ answer: 'Still running.', durationMs: 1, isAborted: false, turnId: 't2', reason: 'answer' })
    await clock.advance(10_000)
    expect(w.autoRuns?.filter(call => call.includes(' failure '))).toEqual([])
    expect(w.compacts).toEqual([])
  })

  for (const [code, prompt] of [
    [5, 'The auto run stopped: the cockpit could not compact twice. End as reference/auto-run.md §Stopping says.'],
    [1, 'The auto run stopped: a background launch kept the compact waiting 30 minutes, and the failure could not be booked (exit 1). End as reference/auto-run.md §Stopping says.'],
  ] as const) {
    test(`ends the run when the deferral cap's failure exits ${code}`, async ($, on) => {
      const files = autoFiles()
      const w: World = { ...SIGNED_IN, compacts: [], autoRuns: [], prompts: [], autoFile: files[AUTO], autoRunExits: { failure: code } }
      const clock = world(on, w)
      signedIn(on, files)
      await $.session.start(START)
      await $.agent.spawn({
        tool_use_id: 'toolu_1',
        prompt: 'Implement task 4',
        description: 'Task 4',
        subagentType: 'dforge:impl-sonnet-low',
        provider: { plugin: 'dforge', tier: 'user' },
        parentModel: 'claude-opus-5-5',
        background: true,
        fork: false,
      })
      await $.turn.complete({ answer: SENTINEL, durationMs: 1, isAborted: false, turnId: 't1', reason: 'answer' })
      await settle(clock)
      await clock.advance(1_805_000)
      expect(w.prompts).toEqual([prompt])
      expect(w.compacts).toEqual([])
      if (code === 1) {
        expect(w.autoRuns).toContain('--session sess-1 stop --reason a background launch kept the compact waiting 30 minutes, and the failure could not be booked (exit 1)')
      }
    })
  }

```

**AE 34 (watchdog):** inside `describe('auto run', …)`, insert immediately
before the line
`  test('reads a run only for its session, and its sentinel only as the last line', () => {`:

```ts
  test('after a stalled call that fails, waits STALL_MS before the next', async ($, on) => {
    const files = autoFiles({ pending: null })
    const w: World = { ...SIGNED_IN, autoRuns: [], prompts: [], autoFile: files[AUTO], autoRunExits: { stalled: 1 } }
    const clock = world(on, w)
    signedIn(on, files)
    await $.session.start(START)
    await $.turn.complete({ answer: 'Task 3: complete.', durationMs: 1, isAborted: false, turnId: 't1', reason: 'answer' })
    const stalls = () => w.autoRuns?.filter(call => call === '--session sess-1 stalled').length
    await clock.advance(240_000)
    expect(stalls()).toBe(1)
    await clock.advance(180_000)
    expect(stalls()).toBe(1)
    await clock.advance(60_000)
    expect(stalls()).toBe(2)
    expect(w.prompts).toEqual([])
  })

  test('a heartbeat that fails leaves the rest of the tick to run', async ($, on) => {
    const files = autoFiles({ pending: null })
    const w: World = { ...SIGNED_IN, autoRuns: [], prompts: [], autoFile: files[AUTO] }
    const clock = world(on, w)
    signedIn(on, files)
    await $.session.start(START)
    await $.turn.complete({ answer: 'Task 3: complete.', durationMs: 1, isAborted: false, turnId: 't1', reason: 'answer' })
    await clock.advance(180_000)
    // The tick at 240 s: its heartbeat's session id read fails once.
    w.sessionIdFailures = 1
    await clock.advance(60_000)
    expect(w.autoRuns).toContain('--session sess-1 stalled')
  })

  test('submits no stall prompt once a turn has started during the stalled call', async ($, on) => {
    const files = autoFiles({ pending: null })
    const w: World = { ...SIGNED_IN, autoRuns: [], prompts: [], autoFile: files[AUTO] }
    const clock = world(on, w)
    signedIn(on, files)
    await $.session.start(START)
    await $.turn.complete({ answer: 'Task 3: complete.', durationMs: 1, isAborted: false, turnId: 't1', reason: 'answer' })
    // The activity read before the call was idle; the person's prompt starts a
    // turn while scripts/auto-run books the stall, so only the turn guard
    // holds the stall prompt back.
    w.onAutoRun = word => (word === 'stalled' ? $.turn.start({ text: 'Continue.', turnId: 't2' }) : undefined)
    await clock.advance(240_000)
    expect(w.autoRuns).toContain('--session sess-1 stalled')
    expect(w.prompts).toEqual([])
  })

```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `timeout 300 /root/.local/bin/claude plugin test plugins/dforge`
Expected: FAIL. These fail:
- The three tightened prompt assertions: the root is not quoted.
- `'switches over a refused compaction…'`: a `failure --reason the cockpit could not switch: vetoed` is booked and no prompt is sent.
- `'takes the primary checkout from the common directory…'`: no `git -C` call.
- `'a submodule has no primary checkout…'`: modeRuns names `/home/me/code/shop/.git/modules/web`.
- `'a live turn restarts the deferral…'`: a failure is booked at 30 minutes.
- `'after a stalled call that fails…'`: four stalled calls by 420 s.
- `'a heartbeat that fails…'`: the tick aborts at `beat`, so no stalled call.

These pass, because they only add coverage: both `ends the run when the deferral cap's failure exits …` tests and `'submits no stall prompt once a turn has started during the stalled call'`.
To confirm that the last one guards something, temporarily delete
`&& !S.isTurnLive` from the `else if (code === 0 && !S.isTurnLive)` line in
`watchdogTick`, rerun (it must fail with one stall prompt), then restore the
line. If the harness refuses the re-entrant `$.turn.start` from inside the
process.run mock, report it rather than weakening the test.

- [ ] **Step 3: Implement**

All edits are in `plugins/dforge/hooks/cockpit/register.tsx`.

**32.L7.** Replace:

```ts
  return `Continue the auto run: run \`bash ${root}/scripts/auto-run after-compact\` first, then continue the phase \`bash ${root}/scripts/auto-run status\` names${where}, as reference/auto-run.md §After a compaction says.`
```

with:

```ts
  return `Continue the auto run: run \`bash "${root}/scripts/auto-run" after-compact\` first, then continue the phase \`bash "${root}/scripts/auto-run" status\` names${where}, as reference/auto-run.md §After a compaction says.`
```

Replace:

```ts
  return `The auto run stalled: the last turn ended without its sentinel line. Run \`bash ${root}/scripts/auto-run status\`, continue the phase it names, and end the turn as reference/auto-run.md §Ending a turn says.`
```

with:

```ts
  return `The auto run stalled: the last turn ended without its sentinel line. Run \`bash "${root}/scripts/auto-run" status\`, continue the phase it names, and end the turn as reference/auto-run.md §Ending a turn says.`
```

Replace:

```ts
    const lead = at === 'switch-resume' ? `Run \`bash ${$.plugin.root}/scripts/auto-run after-compact\` first. ` : ''
```

with:

```ts
    const lead = at === 'switch-resume' ? `Run \`bash "${$.plugin.root}/scripts/auto-run" after-compact\` first. ` : ''
```

**32.L1.** In `autoStage`, replace:

```ts
    if (at === 'switch') {
      const done = await $.session.compact({ instructions: AUTO_SWITCH_INSTRUCTIONS })
      if ('skip' in done && typeof done.skip === 'string') throw new Error(done.skip)
      await update($, budget, () => null)
```

with:

```ts
    if (at === 'switch') {
      // A refused compaction leaves the switch only its model change. It is
      // booked as compacted all the same, so the run's status counts one
      // compaction that did not run.
      await $.session.compact({ instructions: AUTO_SWITCH_INSTRUCTIONS })
      await update($, budget, () => null)
```

(The compact stage's own `if ('skip' in done …) throw` line, under
`if (at === 'compact') {`, stays.)

**32.L4.** In `readWhere`, replace:

```ts
  // A worktree's .dforge/ lives in the primary checkout.
  const common = await firstLine(['git', 'rev-parse', '--path-format=absolute', '--git-common-dir'])
  S.where.primary = common === null ? null : common.replace(/[\\/]\.git[\\/]?$/, '') || null
```

with:

```ts
  // A worktree's .dforge/ lives in the primary checkout: the work tree of the
  // common git directory's parent, as ar_primary_root (scripts/lib/auto-run.sh)
  // finds it, so a layout the scripts resolve no primary for (a submodule)
  // has none here either.
  const common = await firstLine(['git', 'rev-parse', '--path-format=absolute', '--git-common-dir'])
  const parent = common === null ? '' : common.replace(/[\\/]+$/, '').replace(/[\\/][^\\/]*$/, '')
  S.where.primary = parent === '' ? null : await firstLine(['git', '-C', parent, 'rev-parse', '--show-toplevel'])
```

**AE 34, deferral.** In `autoStage`, replace:

```ts
    const stamp = await $.clock.now()
    S.autoDeferredSince = isBackground ? (S.autoDeferredSince ?? stamp) : null
```

with:

```ts
    const stamp = await $.clock.now()
    // Only background work with no turn live counts toward the cap: a live
    // turn restarts it.
    S.autoDeferredSince = S.isTurnLive ? null : (S.autoDeferredSince ?? stamp)
```

In `const S = {`, replace:

```ts
  // When background work began deferring the pending stage; null while nothing does.
  autoDeferredSince: null as number | null,
```

with:

```ts
  // When background work began deferring the pending stage; null while nothing
  // does or a turn is live.
  autoDeferredSince: null as number | null,
  // When the last stalled call failed: the watchdog waits STALL_MS before the next.
  stallFailedAt: null as number | null,
```

**AE 34, beat.** Replace the whole function:

```ts
async function beat($: EngineInterface) {
  const home = (await $.env.get('HOME')) || (await $.env.get('USERPROFILE'))
  if (!home) return
  const id = (await $.session.id()).replace(/[^A-Za-z0-9]/g, '-')
  const seconds = Math.floor((await $.clock.now()) / 1000)
  await $.fs.write(`${home.replace(/[\\/]+$/, '')}/.claude/dforge/sessions/cockpit/${id}`, `${seconds}\n`).catch(() => undefined)
}
```

with:

```ts
async function beat($: EngineInterface) {
  try {
    const home = (await $.env.get('HOME')) || (await $.env.get('USERPROFILE'))
    if (!home) return
    const id = (await $.session.id()).replace(/[^A-Za-z0-9]/g, '-')
    const seconds = Math.floor((await $.clock.now()) / 1000)
    await $.fs.write(`${home.replace(/[\\/]+$/, '')}/.claude/dforge/sessions/cockpit/${id}`, `${seconds}\n`)
  } catch {
    // A beat that cannot be written is skipped; the watchdog's tick goes on.
  }
}
```

**AE 34, stalled backoff.** At the end of `watchdogTick`, replace:

```ts
  const code = await autoRunCall($, await $.session.id(), ['stalled'])
  if (code === 5) await endStoppedRun($)
```

with:

```ts
  const stamp = await $.clock.now()
  if (S.stallFailedAt !== null && stamp - S.stallFailedAt <= STALL_MS) return
  const code = await autoRunCall($, await $.session.id(), ['stalled'])
  S.stallFailedAt = code === 0 || code === 5 ? null : stamp
  if (code === 5) await endStoppedRun($)
```

(The next line, `else if (code === 0 && !S.isTurnLive) await $.prompt.submit(…)`, stays.)

- [ ] **Step 4: Run the tests to verify they pass**

Run: `timeout 300 /root/.local/bin/claude plugin test plugins/dforge`
Expected: PASS, including the existing `auto run` and `cockpit roots` tests
(`'reads finish.json and a local plan from the session's worktree before the
primary'` exercises the linked-worktree path through the new `git -C` answer).
`plugins/dforge/tests/turn-end.test.sh` is not affected: the hold reasons in
`turn-end.sh` are P2's.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/hooks/cockpit/register.tsx plugins/dforge/tests/cockpit.test.ts
git commit -m "fix(cockpit): harden auto-run stages and watchdog"
```

---

---

### Task 5: Type-check the dforge mod in test-all when possible

**Files:**
- Modify: `scripts/test-all.mjs`

**Interfaces:**
- Consumes: None
- Produces: None

**Items:** RO 11

**Depends on:** none
**Implementer:** dr-superpowers:impl-sonnet-low
**Evaluation:** files 0 - spec 0 - coupling 0 - risk 1 = 1

- [ ] **Step 1: Record the current behaviour**

`--list` prints every job test-all would run, without running any:

```bash
timeout 60 node scripts/test-all.mjs --list | grep -c -- '--noEmit -p plugins/dforge'
```

- [ ] **Step 2: Verify it lists no type-check job**

Expected: `0`.

The tsc run recorded on 2026-10-19 (HEAD f2471d7), verbatim apart from two `npm notice` lines: 5 errors in 3 files.

```text
plugins/dforge/hooks/cockpit/config.ts(1,17): error TS7016: Could not find a declaration file for module '../../config/schema.mjs'. '/root/repositories/darkraise-ai-plugins/plugins/dforge/config/schema.mjs' implicitly has an 'any' type.
plugins/dforge/hooks/cockpit/register.tsx(608,11): error TS2769: No overload matches this call.
  Overload 1 of 2, '($: StateDollar, target: Atom<CockpitSpawn[]>, change: (value: CockpitSpawn[]) => CockpitSpawn[]): Promise<CockpitSpawn[]>', gave the following error.
    Type '(CockpitSpawn | { isDone: boolean; outcome: string; agentId: string; seat: string; model: string; description: string; startedAt: number; })[]' is not assignable to type 'CockpitSpawn[]'.
      Type 'CockpitSpawn | { isDone: boolean; outcome: string; agentId: string; seat: string; model: string; description: string; startedAt: number; }' is not assignable to type 'CockpitSpawn'.
        Type '{ isDone: boolean; outcome: string; agentId: string; seat: string; model: string; description: string; startedAt: number; }' is not assignable to type 'CockpitSpawn'.
          Types of property 'outcome' are incompatible.
            Type 'string' is not assignable to type '"failed" | "done" | null | undefined'.
  Overload 2 of 2, '($: StateDollar, target: StateRef<"dforge", "account" | "usage" | "shells" | "plan" | "repo" | "run" | "engine" | "budget" | "settings" | "breakdown" | "seats" | "spawns" | "remote" | ... 16 more ... | "autoRun">, change: (value: string | ... 26 more ... | undefined) => string | ... 25 more ... | null): Promise<...>', gave the following error.
    Argument of type 'Atom<CockpitSpawn[]>' is not assignable to parameter of type 'StateRef<"dforge", "account" | "usage" | "shells" | "plan" | "repo" | "run" | "engine" | "budget" | "settings" | "breakdown" | "seats" | "spawns" | "remote" | "refusals" | "place" | "alerted" | ... 13 more ... | "autoRun">'.
      Type 'Atom<CockpitSpawn[]>' is missing the following properties from type 'StateName<"dforge", "account" | "usage" | "shells" | "plan" | "repo" | "run" | "engine" | "budget" | "settings" | "breakdown" | "seats" | "spawns" | "remote" | "refusals" | "place" | "alerted" | ... 13 more ... | "autoRun">': plugin, key
plugins/dforge/hooks/cockpit/register.tsx(678,59): error TS2345: Argument of type '($: EngineInterface, e: { readonly surface: "mobile"; readonly component: "Pane"; readonly requestId: "dforge"; readonly viewport?: { readonly columns: number; readonly rows: number; readonly isFullscreen?: boolean | undefined; } | undefined; readonly props: { ...; }; } | { ...; } | { ...; } | { ...; }) => Promise<....' is not assignable to parameter of type '($: EngineInterface, e: { readonly surface: "mobile"; readonly component: "Pane"; readonly requestId: "dforge"; readonly viewport?: { readonly columns: number; readonly rows: number; readonly isFullscreen?: boolean | undefined; } | undefined; readonly props: { ...; }; } | { ...; } | { ...; } | { ...; }, next: Next<....'.
  Type 'Promise<string | number | boolean | StyledElement<"Box", BoxHoverProps> | StyledElement<"Text", TextHoverProps> | ... 13 more ... | undefined>' is not assignable to type 'RenderElement | Promise<RenderElement>'.
    Type 'Promise<string | number | boolean | StyledElement<"Box", BoxHoverProps> | StyledElement<"Text", TextHoverProps> | ... 13 more ... | undefined>' is not assignable to type 'Promise<RenderElement>'.
      Type 'string | number | boolean | StyledElement<"Box", BoxHoverProps> | StyledElement<"Text", TextHoverProps> | ... 13 more ... | undefined' is not assignable to type 'RenderElement'.
        Type 'undefined' is not assignable to type 'RenderElement'.
plugins/dforge/tests/cockpit.test.ts(3958,25): error TS2345: Argument of type '{ reason: "other"; sessionId: string; }' is not assignable to parameter of type 'SessionEndInput'.
  Property 'resume' is missing in type '{ reason: "other"; sessionId: string; }' but required in type 'SessionEndInput'.
plugins/dforge/tests/cockpit.test.ts(4190,69): error TS7053: Element implicitly has an 'any' type because expression of type '"/home/me/code/shop/.dforge/sdd/auto-run.json"' can't be used to index type '{ '/home/me/code/shop/.dforge/handoff/latest.md': { text: string; mtimeMs: number; }; }'.
  Property '/home/me/code/shop/.dforge/sdd/auto-run.json' does not exist on type '{ '/home/me/code/shop/.dforge/handoff/latest.md': { text: string; mtimeMs: number; }; }'.
exit=2
```

- [ ] **Step 3: Implement**

Import `existsSync`:

In `scripts/test-all.mjs`, find:

```js
import { readdirSync } from 'node:fs';
```

Replace it with:

```js
import { existsSync, readdirSync } from 'node:fs';
```

Detect the generated types and `tsc`, after the `hasClaude` line:

In `scripts/test-all.mjs`, find:

```js
const hasClaude = !options.list && process.platform !== 'win32' && spawnSync('claude', ['--version'], { stdio: 'ignore', timeout: 5000 }).status === 0;
```

Replace it with:

```js
const hasClaude = !options.list && process.platform !== 'win32' && spawnSync('claude', ['--version'], { stdio: 'ignore', timeout: 5000 }).status === 0;
// The mod's type check needs tsc on PATH and the declarations Claude Code lays
// beside a mod it loads from a folder, which are gitignored: a fresh clone has none.
const typesGenerated = ['plugins/dforge/tsconfig.json', 'plugins/dforge/.claude-plugin/types/tsconfig.json'].every(path => existsSync(resolve(root, path)));
// Detected under --list too, so a listing shows the job that a run would start.
const hasTsc = typesGenerated && spawnSync('tsc', ['--version'], { stdio: 'ignore', timeout: 10000 }).status === 0;
```

Add the bounded job, and print a skipped line when it cannot run:

In `scripts/test-all.mjs`, find:

```js
  ...(hasClaude ? [['claude', ['plugin', 'test', 'plugins/dforge'], 300]] : []),
];
```

Replace it with:

```js
  ...(hasClaude ? [['claude', ['plugin', 'test', 'plugins/dforge'], 300]] : []),
  ...(hasTsc ? [['tsc', ['--noEmit', '-p', 'plugins/dforge'], 300]] : []),
];
if (!options.list && !hasTsc) {
  console.log(`Skipped tsc --noEmit -p plugins/dforge: ${typesGenerated ? 'tsc is not on PATH' : 'the generated types are missing (Claude Code writes them when it loads plugins/dforge from the folder)'}`);
}
```

- [ ] **Step 4: Verify the job runs and its result reaches test-all's exit code**

Generate the mod's declarations in this worktree first (they are gitignored, so
a fresh worktree has none; `claude plugin test` writes them):

```bash
timeout 300 /root/.local/bin/claude plugin test plugins/dforge > /dev/null 2>&1; ls plugins/dforge/tsconfig.json plugins/dforge/.claude-plugin/types/tsconfig.json
```

Expected: both paths listed. If either is missing, copy them from the primary
checkout, where Claude Code has loaded the mod (both existed there on
2026-10-19): `cp /root/repositories/darkraise-ai-plugins/plugins/dforge/tsconfig.json plugins/dforge/ && cp -r /root/repositories/darkraise-ai-plugins/plugins/dforge/.claude-plugin/types plugins/dforge/.claude-plugin/`.
Both paths are gitignored, so nothing is staged.

`--list` always leaves out the `claude plugin test` job, while a real run adds
it when `claude` is on PATH, which would shift the shards. Confirm it is not:
`command -v claude` must print nothing (on this host `claude` is a shell
function, not on PATH); if it prints a path, run the commands below with
`PATH` set without that directory.

Then drive test-all with a stub `tsc` that logs its arguments and exits with a
chosen code. With as many shards as jobs, each shard holds one job, so the shard
that lists the type-check job runs only that job:

```bash
shim=$(mktemp -d)
printf '#!/bin/sh
echo "$@" >> "$TSC_LOG"
exit "${TSC_EXIT:-0}"
' > "$shim/tsc"
chmod +x "$shim/tsc"
export TSC_LOG="$shim/args"
n=$(PATH="$shim:$PATH" timeout 60 node scripts/test-all.mjs --list | wc -l)
k=""
for i in $(seq 1 "$n"); do
  PATH="$shim:$PATH" timeout 60 node scripts/test-all.mjs --list --shard "$i/$n" | grep -q -- '--noEmit -p plugins/dforge' && k=$i
done
echo "shard $k of $n"
PATH="$shim:$PATH" TSC_EXIT=0 timeout 120 node scripts/test-all.mjs --shard "$k/$n" > /dev/null 2>&1; echo "pass: $?"
PATH="$shim:$PATH" TSC_EXIT=2 timeout 120 node scripts/test-all.mjs --shard "$k/$n" > /dev/null 2>&1; echo "fail: $?"
grep -c -- '^--noEmit -p plugins/dforge$' "$TSC_LOG"
rm -rf "$shim"; unset TSC_LOG
```

Expected: `shard <k> of <n>` with `k` set; `pass: 0`; `fail:` followed by a
non-zero code; the final count `2` (the two runs, beside the `--version`
probes).

Skipped path, with no `tsc` on PATH (this host has none):

```bash
n=$(timeout 60 node scripts/test-all.mjs --list | wc -l)
timeout 300 node scripts/test-all.mjs --shard "$n/$n" 2>&1 | grep '^Skipped tsc'
```

Expected: `Skipped tsc --noEmit -p plugins/dforge: tsc is not on PATH` (the
last shard holds one light suite; the line prints before it runs).

Finally, the real compiler on this worktree, as spec P7 item 8 requires:

```bash
timeout 300 npx -y -p typescript@5.6.3 tsc --noEmit --pretty false -p plugins/dforge 2>&1 | grep 'error TS'
```

Expected: the five errors listed above (in `config.ts`, `register.tsx` and
`cockpit.test.ts`), whose positions may have moved with this wave's cockpit
tasks. Copy the output into the task report: Tasks 37 and 38 fix exactly these.
Any other error is new; list it in the report so Task 38 fixes it too.

- [ ] **Step 5: Commit**

```bash
git add scripts/test-all.mjs
git commit -m "feat(test-all): run tsc on the dforge mod"
```

---

### Task 6: Fix the settings import, locks and editors

**Files:**
- Modify: `plugins/dforge/hooks/cockpit/register.tsx`
- Modify: `plugins/dforge/hooks/cockpit/config.ts`
- Test: `plugins/dforge/tests/cockpit.test.ts`

**Interfaces:**
- Consumes: None
- Produces: None

**Items:** DF 17, FS 25, FS 41, FS 27, FS 30, FS 32

**Depends on:** Task 4
**Implementer:** dr-superpowers:impl-sonnet-medium
**Evaluation:** files 1 - spec 0 - coupling 0 - risk 2 = 3

This task makes three fixes and adds two sets of coverage tests:
1. **DF 17:** on a first run, `importSettings` lets
   `node <root>/scripts/lib/dforge-config.mjs get --json` make the import.
   That call creates the file atomically through a hard link (`importLegacy`).
   Its stdout (resolved values, not the file) is discarded, and the file is
   read back with `readSettingsFile`. Only when node cannot start (`nodeRuns`)
   does the cockpit keep its own exists-then-write.
2. **FS 25 / FS 41:** `claudeLocks` names a merged value that does not fit
   its setting, for example `50000 from a project or managed file, not valid`.
   Today the row says only "set by a project or managed settings file" while
   it shows the default.
3. **FS 27:** the settings `show` path also closes an open webhook or mention
   field, so only one editor is open at a time. The webhook and mention
   submits call `show({})` first.
4. **FS 30, coverage only:** strict mode at 276,250 tokens reads 59%, and
   relaxed mode warns past 80% of the final-phase limit and hands off at it.
5. **FS 32, coverage only:** a changed skill setting is told to the model once
   when a dforge subagent spawns, and once when the pane closes.

- [ ] **Step 1: Write the failing tests**

The tests prove: the first run leaves the import to dforge-config and reads
its file; a node-less first run still writes the import itself; an invalid
locked Claude value is named; only one editor is open; and Reset group closes
an open webhook field. They also cover FS 30 and FS 32.

In `plugins/dforge/tests/cockpit.test.ts`, in `function world`, replace:

```ts
    if (argv.includes('/scripts/lib/dforge-config.mjs ')) {
      w.runs?.push(argv)
```

with:

```ts
    if (argv.includes('/scripts/lib/dforge-config.mjs ')) {
      w.runs?.push(argv)
      // dforge-config's first run creates the settings file with dr-cockpit's
      // options (importLegacy), unless the file exists or it refuses.
      if (e.argv.includes('get') && w.config === undefined && !w.isDforgeConfigRefusing && w.written !== undefined && !(CONFIG in w.written)) {
        w.written[CONFIG] = `${JSON.stringify(importedSettings(SCHEMA, w.userSettings ?? w.settings ?? {}), null, 2)}\n`
      }
```

**DF 17.** In the describe that holds the import tests, insert immediately before the line
`  test('a settings file dforge-config wrote first is kept, and the webhook still comes over', async ($, on) => {`:

```ts
  test('the first session leaves the import to dforge-config and reads the file it made', async ($, on) => {
    const written: Record<string, string> = {}
    const runs: string[] = []
    world(on, { tokens: 284_000, written, runs, env: { HOME: '/home/me' }, settings: legacy(70), files: LISTED })
    disk(on, written, OLD_FILES)
    memory(on)
    await $.session.start(START)
    expect(runs).toEqual([expect.stringMatching(/^node .*\/scripts\/lib\/dforge-config\.mjs get --json$/)])
    expect(JSON.parse(written[CONFIG] ?? '{}')).toEqual({ warnAt: 70 })
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    await ui.press({ key: 'pane-settings' })
    await ui.press({ key: 'settings-tab-Context' })
    expect((await ui.find({ key: 'set-warnAt-value' }))?.text).toMatch(/^70%/)
  })

  test('without node the first session writes the import itself', async ($, on) => {
    const written: Record<string, string> = {}
    const runs: string[] = []
    world(on, { tokens: 284_000, written, runs, isNodeMissing: true, env: { HOME: '/home/me' }, settings: legacy(70), files: LISTED })
    disk(on, written, OLD_FILES)
    memory(on)
    await $.session.start(START)
    expect(runs).toEqual([])
    expect(JSON.parse(written[CONFIG] ?? '{}')).toEqual({ warnAt: 70 })
  })

```

**FS 25 / FS 41.** In `describe('settings rows', …)`, replace:

```ts
    expect(claudeLocks(ROWS, {}, {})).toEqual({})
```

with:

```ts
    expect(claudeLocks(ROWS, {}, {})).toEqual({})
    expect(claudeLocks(ROWS, { compactAt: 50_000 }, { compactAt: 650_000 })).toEqual({ compactAt: '50000 from a project or managed file, not valid' })
```

Then insert immediately before the line
`  test('a Claude key stays locked after a save while a project file forces another value', async ($, on) => {`:

```ts
  test('a Claude key a project or managed file sets to an invalid value names that value', async ($, on) => {
    world(on, { tokens: 284_000, config: {}, settings: { autoCompactWindow: 50_000 }, userSettings: { autoCompactWindow: 650_000 } })
    await $.session.start(START)
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    await ui.press({ key: 'pane-settings' })
    await ui.press({ key: 'settings-tab-Context' })
    expect(await ui.find({ type: 'Text', text: '50000 from a project or managed file, not valid' })).toBeDefined()
    expect(await ui.find({ key: 'set-autoCompactWindow-more' })).toBeUndefined()
  })

```

**FS 27.** In `describe('discord', …)`, insert immediately before the line
`  test('sends to the webhook named by DFORGE_NOTIFY_URL alone', async ($, on) => {`:

```ts
  test('keeps one editor open on the Notifications tab', async ($, on) => {
    world(on, { tokens: 50_000 })
    mock.store(on, {})
    await $.session.start(START)
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    await ui.press({ key: 'pane-settings' })
    await ui.press({ key: 'settings-tab-Notifications' })
    await ui.press({ key: 'set-notify-url-edit' })
    expect(await ui.find({ key: 'set-notify-url-input' })).toBeDefined()
    await ui.press({ key: 'set-notifyAfter-edit' })
    expect(await ui.find({ key: 'set-notifyAfter-input' })).toBeDefined()
    expect(await ui.find({ key: 'set-notify-url-input' })).toBeUndefined()
  })

  test('Reset group closes an open webhook field', async ($, on) => {
    world(on, { tokens: 50_000, config: { notifyAfter: 0 }, written: {} })
    mock.store(on, {})
    await $.session.start(START)
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    await ui.press({ key: 'pane-settings' })
    await ui.press({ key: 'settings-tab-Notifications' })
    await ui.press({ key: 'set-notify-url-edit' })
    await ui.press({ key: 'settings-reset' })
    expect(await ui.find({ key: 'settings-reset-confirm' })).toBeDefined()
    expect(await ui.find({ key: 'set-notify-url-input' })).toBeUndefined()
    // Opening the field again ends the pending reset, and a save keeps it ended.
    await ui.press({ key: 'set-notify-url-edit' })
    expect(await ui.find({ key: 'settings-reset-confirm' })).toBeUndefined()
    await ui.input({ key: 'set-notify-url-input', text: WEBHOOK, kind: 'submit' })
    expect(await ui.find({ key: 'settings-reset-confirm' })).toBeUndefined()
    expect(await ui.find({ key: 'settings-reset' })).toBeDefined()
  })

```

**FS 30 (coverage).** In `describe('settings', …)`, insert immediately before
the line `  test('sections picks and orders the pane', async ($, on) => {`:

```ts
  test('strict handoff reads the same context against the handoff budget', async ($, on) => {
    // 276,250 of the 464,500 budget: 59%, where relaxed reads 50%.
    world(on, { tokens: 276_250, config: { handoffMode: 'strict' } })
    await $.session.start(START)
    await $.tool.call({ tool: 'Bash', command: 'ls' })
    const ui = await $.ui.mount({ ...INLINE, surface: 'terminal' })
    expect(await ui.find({ type: 'Text', text: /^59%$/ })).toBeDefined()
  })

  test('relaxed handoff warns and hands off against the final-phase limit', async ($, on) => {
    const notes: string[] = []
    const w: World = { tokens: 440_000, notes, config: { handoffMode: 'relaxed' } }
    world(on, w)
    await $.session.start(START)
    await $.tool.call({ tool: 'Skill', skill: 'dforge:subagent-driven-development' })
    // 440,000 of 552,500 is under warnAt's 80%: Hand off is not the one to press.
    let ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    expect((await ui.find({ key: 'pane-handoff-box' }))?.props.borderColor).toBe('inactive')
    await ui.unmount()
    // Past the strict budget and warnAt, short of the limit: the warning, no note.
    w.tokens = 470_000
    await $.tool.call({ tool: 'Bash', command: 'ls' })
    ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    expect((await ui.find({ key: 'pane-handoff-box' }))?.props.borderColor).toBe('permission')
    await ui.unmount()
    expect(notes.filter(text => /— handoff\./.test(text))).toEqual([])
    w.tokens = 560_000
    await $.tool.call({ tool: 'Bash', command: 'ls' })
    expect(notes.filter(text => /— handoff\./.test(text))).toEqual([expect.stringMatching(/^dforge: budget: 560k of 553k — handoff\. /)])
  })

```

**FS 32 (coverage).** In `describe('settings held outside the file', …)`,
insert immediately before the line
`  test('a dforge skill started as a slash command marks the session and sends the waiting note', async ($, on) => {`:

```ts
  test('a dforge subagent spawn sends the waiting note once', async ($, on) => {
    const notes: string[] = []
    world(on, { tokens: 50_000, config: {}, notes, written: {} })
    await $.session.start(START)
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    await ui.press({ key: 'pane-settings' })
    await ui.press({ key: 'settings-tab-Process' })
    await ui.press({ key: 'set-designApproval-whole' })
    await ui.press({ key: 'settings-back' })
    expect(notes.filter(note => note.startsWith(NOTE))).toEqual([])
    const spawn = (n: number) =>
      $.agent.spawn({ tool_use_id: `toolu_${n}`, prompt: 'Implement', description: `Task ${n}`, subagentType: 'dforge:impl-sonnet-low', provider: { plugin: 'dforge', tier: 'user' }, parentModel: 'claude-opus-5-5', background: false, fork: false })
    await spawn(1)
    expect(notes.filter(note => note.startsWith(NOTE))).toEqual([
      'dforge settings changed: designApproval=whole. Each replaces the matching question or default in the skills.',
    ])
    await spawn(2)
    expect(notes.filter(note => note.startsWith(NOTE))).toHaveLength(1)
  })

  test('closing the pane sends the note once', async ($, on) => {
    const notes: string[] = []
    world(on, { tokens: 50_000, config: {}, notes, written: {} })
    await $.session.start(START)
    await $.tool.call({ tool: 'Skill', skill: 'dforge:subagent-driven-development' })
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    await ui.press({ key: 'pane-settings' })
    await ui.press({ key: 'settings-tab-Workflow' })
    await ui.press({ key: 'set-worktree-always' })
    expect(notes.filter(note => note.startsWith(NOTE))).toEqual([])
    await $.ui.close({ id: 'dforge', origin: { kind: 'person' } } as never)
    expect(notes.filter(note => note.startsWith(NOTE))).toEqual([
      'dforge settings changed: worktree=always. Each replaces the matching question or default in the skills.',
    ])
    await $.ui.close({ id: 'dforge', origin: { kind: 'person' } } as never)
    expect(notes.filter(note => note.startsWith(NOTE))).toHaveLength(1)
  })

```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `timeout 300 /root/.local/bin/claude plugin test plugins/dforge`
Expected: FAIL. These fail:
- `'the first session leaves the import to dforge-config…'`: `runs` is `[]`.
- The `claudeLocks` unit assertion and `'…sets to an invalid value names that value'`: the text is "set by a project or managed settings file".
- `'keeps one editor open…'`: the webhook input stays drawn.
- `'Reset group closes an open webhook field'`: the webhook input stays drawn after Reset group.

These pass, because they only add coverage: `'without node the first session writes the import itself'`, the two FS 30 tests, and the two FS 32 tests. If an FS 30 or FS 32 test fails, stop and report it: it is a real defect. If `$.ui.close` from a test does not carry `origin` through to the hook, report that instead of changing the hook.

- [ ] **Step 3: Implement**

**DF 17.** In `plugins/dforge/hooks/cockpit/register.tsx`, replace:

```ts
/** The first run: dr-cockpit's options, written to the new file. */
async function importSettings($: EngineInterface, path: string): Promise<SettingsFile> {
  const claude = await $.settings.read({ source: 'user' }).catch(() => ({}))
  const file = importedSettings(SCHEMA, claude)
  // The mod has no exclusive create: a file saved while the reads above ran is kept.
  if (await $.fs.exists(path).catch(() => false)) return (await readSettingsFile($, path)) ?? file
  await $.fs.write(path, `${JSON.stringify(file, null, 2)}\n`).catch(() => undefined)
  return file
}
```

with:

```ts
/** The first run: dr-cockpit's options, imported into the new file. */
async function importSettings($: EngineInterface, path: string): Promise<SettingsFile> {
  if (await nodeRuns($)) {
    // dforge-config imports before any command, creating the file with a hard
    // link that never replaces one saved meanwhile. `get --json` prints the
    // resolved values, not the file, so its output is not used.
    await $.process.run(['node', `${$.plugin.root}/scripts/lib/dforge-config.mjs`, 'get', '--json'], { timeoutMs: 15_000 }).catch(() => null)
    return (await readSettingsFile($, path)) ?? {}
  }
  const claude = await $.settings.read({ source: 'user' }).catch(() => ({}))
  const file = importedSettings(SCHEMA, claude)
  // The mod has no exclusive create: a file saved while the reads above ran is kept.
  if (await $.fs.exists(path).catch(() => false)) return (await readSettingsFile($, path)) ?? file
  await $.fs.write(path, `${JSON.stringify(file, null, 2)}\n`).catch(() => undefined)
  return file
}
```

(`nodeRuns` is the existing `async function nodeRuns($: EngineInterface): Promise<boolean>`
further down the file.)

**FS 25 / FS 41.** In `plugins/dforge/hooks/cockpit/config.ts`, replace:

```ts
/** The Claude keys a project or managed settings file overrides: the merged value is not the user file's. */
export function claudeLocks(schema: Schema, merged: Readonly<Record<string, unknown>>, user: Readonly<Record<string, unknown>>): Record<string, string> {
  const locks: Record<string, string> = {}
  for (const [key, spec] of Object.entries(schema)) {
    if (spec.target === 'claude' && merged[key] !== undefined && merged[key] !== user[key]) locks[key] = 'set by a project or managed settings file'
  }
  return locks
}
```

with:

```ts
/**
 * The Claude keys a project or managed settings file overrides: the merged
 * value is not the user file's. A merged value that does not fit its setting
 * is named, since the row shows the default in its place.
 */
export function claudeLocks(schema: Schema, merged: Readonly<Record<string, unknown>>, user: Readonly<Record<string, unknown>>): Record<string, string> {
  const locks: Record<string, string> = {}
  for (const [key, spec] of Object.entries(schema)) {
    if (spec.target !== 'claude' || merged[key] === undefined || merged[key] === user[key]) continue
    locks[key] = isValidSetting(spec, merged[key]) ? 'set by a project or managed settings file' : `${JSON.stringify(merged[key])} from a project or managed file, not valid`
  }
  return locks
}
```

(`isValidSetting` is defined earlier in the same file:
`export function isValidSetting(spec: SettingSpec, value: unknown): value is SettingValue {`.)

**FS 27.** In `plugins/dforge/hooks/cockpit/register.tsx`, in the settings
view's `field` helper, replace:

```tsx
              onSubmit={async (value: string) => {
                const problem = await onSave(value)
                await update($, notifier, now => ({ ...now, editing: problem === null ? null : key, error: problem }))
              }}
```

with:

```tsx
              onSubmit={async (value: string) => {
                // A save ends a pending reset like any other press.
                await show({})
                const problem = await onSave(value)
                await update($, notifier, now => ({ ...now, editing: problem === null ? null : key, error: problem }))
              }}
```

Then replace:

```ts
      // Every press but the one that asked for it ends an edit or a pending reset.
      const show = (change: Partial<CockpitSettingsView>) =>
        update($, settingsView, now => ({ ...now, editing: null, error: null, isConfirmingReset: false, ...change }))
```

with:

```ts
      // Every press but the one that asked for it ends an edit, a webhook or
      // mention field's included, or a pending reset.
      const show = async (change: Partial<CockpitSettingsView>) => {
        if ((await read($, notifier)).editing !== null) await update($, notifier, now => ({ ...now, editing: null, error: null }))
        await update($, settingsView, now => ({ ...now, editing: null, error: null, isConfirmingReset: false, ...change }))
      }
```

(`show` is declared after `field`. It is used only inside the submit callback,
which runs after the render, the same way the existing `compact` helper already
uses `state` and `show`.)

- [ ] **Step 4: Run the tests to verify they pass**

Run: `timeout 300 /root/.local/bin/claude plugin test plugins/dforge`
Expected: PASS, including the existing import tests (`'the first session
imports the cockpit options and the webhook…'` now goes through the mocked
dforge-config) and `'takes the webhook in the settings view and shows it
masked'` (an invalid URL still leaves the field open with its error).
Also run `timeout 600 bash plugins/dforge/tests/dforge-config.test.sh`: it
should still PASS. This task does not change `dforge-config.mjs`, but the cockpit
now depends on its import-before-command behaviour.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/hooks/cockpit/register.tsx plugins/dforge/hooks/cockpit/config.ts plugins/dforge/tests/cockpit.test.ts
git commit -m "fix(cockpit): fix settings import, locks and editors"
```

---

---

### Task 7: Refresh darkmem roots on config change

**Files:**
- Modify: `plugins/dforge/hooks/cockpit/register.tsx`
- Test: `plugins/dforge/tests/cockpit.test.ts`

**Interfaces:**
- Consumes: None
- Produces: None

**Items:** DM 27, DM 28, DM 46, DR 5

**Depends on:** Task 6
**Implementer:** dr-superpowers:impl-sonnet-low
**Evaluation:** files 1 - spec 0 - coupling 0 - risk 1 = 2

`readRoots` asks `scripts/lib/darkmem-config.mjs --mode` where the docs and
progress stores live, and caches the answer. This task makes four fixes:
1. **DM 27, cockpit half:** the cache key adds the modification time of
   `~/.dforge/config.json`, where a repository's darkmem mapping lives, so
   mapping a repository takes effect in the running session.
2. **DM 28, cockpit half:** `NO_NODE` matches only the wording of a node that
   cannot start (the engine's "failed to start", or a shell's
   `node: not found`). Today any stderr that contains ENOENT or "not found"
   is silently hidden.
3. **DM 46:** a run that timed out is not cached, so the next read tries
   again. When neither `~/.dforge/config.json` nor `~/.dforge/stores.json`
   exists, node is not started at all, since every store is then local.
4. **DR 5:** the repeated `\.dforge` alternative in the `tool.call` hook's
   regex is removed.

- [ ] **Step 1: Write the failing tests**

The tests prove that a `config.json` change re-reads the roots, that a
script stderr naming ENOENT is shown, that a timeout is retried, and that no
node runs without either file. The existing roots tests that expect a node run
gain a `stores.json`, because without one the run is now skipped.

In `plugins/dforge/tests/cockpit.test.ts`, inside `describe('cockpit roots', …)`,
replace:

```ts
  const checkoutFiles = (): NonNullable<World['files']> => ({
    '/home/me/code/shop/.dforge/sdd/p/progress.md': { text: LEDGER, mtimeMs: 2_000_000 },
    '/home/me/code/shop/docs/dforge/plans/p.md': { text: PLAN },
  })
```

with:

```ts
  // darkmem-config runs only once one of the ~/.dforge files exists.
  const storesFile = (): NonNullable<World['files']> => ({ '/home/me/.dforge/stores.json': { text: '{}', mtimeMs: 1 } })
  const checkoutFiles = (): NonNullable<World['files']> => ({
    ...storesFile(),
    '/home/me/code/shop/.dforge/sdd/p/progress.md': { text: LEDGER, mtimeMs: 2_000_000 },
    '/home/me/code/shop/docs/dforge/plans/p.md': { text: PLAN },
  })
```

In `'reads the ledger and the plan from the mirror when both families are in darkmem'`, replace:

```ts
    const files: World['files'] = {
      [`${MIRROR}/work/sdd/p/progress.md`]: { text: LEDGER, mtimeMs: 2_000_000 },
```

with:

```ts
    const files: World['files'] = {
      ...storesFile(),
      [`${MIRROR}/work/sdd/p/progress.md`]: { text: LEDGER, mtimeMs: 2_000_000 },
```

In `'offers Resume for latest.md in the mirror, naming it'`, replace:

```ts
    const files: World['files'] = { [`${MIRROR}/work/handoff/latest.md`]: { text: RESUMABLE, mtimeMs: 900_000 } }
```

with:

```ts
    const files: World['files'] = { ...storesFile(), [`${MIRROR}/work/handoff/latest.md`]: { text: RESUMABLE, mtimeMs: 900_000 } }
```

Then insert immediately before the line
`  test('resolves a plan under the docs root in darkmem, under the docs directory of each checkout otherwise', () => {`:

```ts
  test('reads the roots again when ~/.dforge/config.json changes', async ($, on) => {
    const files: NonNullable<World['files']> = { ...checkoutFiles(), [CONFIG]: { text: '{}', mtimeMs: 1 } }
    const modeRuns: string[] = []
    world(on, { ...SIGNED_IN, files, modeRuns })
    signedIn(on, files)
    await $.session.start(START)
    expect(modeRuns).toEqual(['/home/me/code/shop'])
    await $.tool.call({ tool: 'Bash', command: 'cat ~/.dforge/config.json' })
    expect(modeRuns).toHaveLength(1)
    files[CONFIG]!.mtimeMs = 2
    await $.tool.call({ tool: 'Bash', command: 'cat ~/.dforge/config.json' })
    expect(modeRuns).toHaveLength(2)
  })

  test('a --mode failure that names a missing file is shown, not taken for a missing node', async ($, on) => {
    const files = checkoutFiles()
    const stderr = "darkmem-config: ENOENT: no such file or directory, open '/home/me/.dforge/mirror/shop/.sync-state.json'\n"
    world(on, { ...SIGNED_IN, files, modeOut: { exitCode: 1, stdout: '', stderr } })
    signedIn(on, files)
    await $.tool.call({ tool: 'Skill', skill: 'dforge:subagent-driven-development' })
    await $.session.start(START)
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    expect(await ui.find({ type: 'Text', text: /^darkmem-config: ENOENT: no such file or directory/ })).toBeDefined()
  })

  test('a run that timed out is tried again at the next read', async ($, on) => {
    const files = checkoutFiles()
    const modeRuns: string[] = []
    world(on, { ...SIGNED_IN, files, modeRuns, modeOut: 'timeout' })
    signedIn(on, files)
    await $.session.start(START)
    expect(modeRuns).toHaveLength(1)
    await $.tool.call({ tool: 'Bash', command: 'cat .dforge/sdd/p/progress.md' })
    expect(modeRuns).toHaveLength(2)
  })

  test('runs no node while neither ~/.dforge/config.json nor stores.json exists', async ($, on) => {
    const files: NonNullable<World['files']> = {
      '/home/me/code/shop/.dforge/sdd/p/progress.md': { text: LEDGER, mtimeMs: 2_000_000 },
      '/home/me/code/shop/docs/dforge/plans/p.md': { text: PLAN },
    }
    const modeRuns: string[] = []
    world(on, { ...SIGNED_IN, files, modeRuns })
    signedIn(on, files)
    await $.tool.call({ tool: 'Skill', skill: 'dforge:subagent-driven-development' })
    await $.session.start(START)
    expect(modeRuns).toEqual([])
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    expect(await ui.find({ type: 'Text', text: /Task 1: Add the helpers/ })).toBeDefined()
  })

```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `timeout 300 /root/.local/bin/claude plugin test plugins/dforge`
Expected: FAIL. These fail:
- `'reads the roots again when ~/.dforge/config.json changes'`: one run, because the key ignores config.json.
- `'a --mode failure that names a missing file…'`: NO_NODE hides the line.
- `'a run that timed out is tried again…'`: the timeout is cached.
- `'runs no node while neither…'`: modeRuns is `['/home/me/code/shop']`.

The edited existing tests still pass.

- [ ] **Step 3: Implement**

All edits are in `plugins/dforge/hooks/cockpit/register.tsx`.

**DM 28.** Replace:

```ts
// The roots darkmem-config.mjs --mode names for the primary checkout (store
// options spec §7.3). Read again when the checkout or ~/.dforge/stores.json
// changes, so the session that ran a move sees the new roots. Null keeps the
// checkout paths: silently without node or mode lines, with a note in the
// pane when the run fails or outruns its 5 seconds.
const NO_NODE = /ENOENT|not found/i
```

with:

```ts
// The roots darkmem-config.mjs --mode names for the primary checkout (store
// options spec §7.3). Read again when the checkout, ~/.dforge/stores.json or
// ~/.dforge/config.json changes, so the session that ran a move or mapped the
// repository sees the new roots. Null keeps the checkout paths: silently
// without node, mode lines or either file, with a note in the pane when the
// run fails or outruns its 5 seconds.
// A node that cannot start: the engine's "failed to start", or a shell's
// "node: not found" (exit 127). Any other stderr is the script's own, ENOENT
// included.
const NO_NODE = /failed to start|\bnode: (?:command )?not found/i
```

**DM 27 and DM 46.** Replace the whole `readRoots` function:

```ts
async function readRoots($: EngineInterface, primary: string): Promise<CockpitRoots | null> {
  const home = (await read($, place))?.home ?? null
  const stores = home === null ? null : await $.fs.stat(`${home}/.dforge/stores.json`).catch(() => null)
  const key = `${primary}|${stores?.mtimeMs ?? 'none'}`
  if (S.roots.key === key) return S.roots.value
  let value: CockpitRoots | null = null
  let note: string | null = null
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
  S.roots = { key, value }
  if ((await read($, rootsNote)) !== note) await update($, rootsNote, () => note)
  return value
}
```

with:

```ts
async function readRoots($: EngineInterface, primary: string): Promise<CockpitRoots | null> {
  const home = (await read($, place))?.home ?? null
  const mtimeOf = async (name: string) => (home === null ? null : ((await $.fs.stat(`${home}/.dforge/${name}`).catch(() => null))?.mtimeMs ?? null))
  const stores = await mtimeOf('stores.json')
  const config = await mtimeOf('config.json')
  const key = `${primary}|${stores ?? 'none'}|${config ?? 'none'}`
  if (S.roots.key === key) return S.roots.value
  let value: CockpitRoots | null = null
  let note: string | null = null
  let isTimedOut = false
  // Without either file every store is local, which the checkout paths
  // already are: there is nothing to ask node.
  if (stores !== null || config !== null) {
    try {
      const ran = await $.process.run(['node', `${$.plugin.root}/scripts/lib/darkmem-config.mjs`, '--mode', primary], { timeoutMs: 5000 })
      if (ran.exitCode === 0) value = parseModeLines(ran.stdout)
      else if (!NO_NODE.test(ran.stderr)) {
        note = ran.stderr.split(/\r?\n/).map(line => line.trim()).find(Boolean) ?? `darkmem-config.mjs --mode exited ${ran.exitCode}`
      }
    } catch (error) {
      // run rejects only when the command cannot start or outlives timeoutMs;
      // any other wording, a later engine's included, keeps the paths silently.
      if (TIMED_OUT.test(String(error))) {
        isTimedOut = true
        note = 'darkmem-config.mjs --mode gave no answer within 5 seconds'
      }
    }
  }
  // A run that timed out is not kept: the next read tries again.
  S.roots = isTimedOut ? { key: '', value: null } : { key, value }
  if ((await read($, rootsNote)) !== note) await update($, rootsNote, () => note)
  return value
}
```

In `const S = {`, replace:

```ts
  // The roots --mode last named, and the primary checkout and stores.json
  // modification time they were read for.
```

with:

```ts
  // The roots --mode last named, and the primary checkout and the
  // modification times of stores.json and config.json they were read for.
```

**DR 5.** In the `tool.call` hook, replace:

```ts
      if (/\.dforge|\.dforge|finish-choice/.test(JSON.stringify(e))) await readRun($)
```

with:

```ts
      if (/\.dforge|finish-choice/.test(JSON.stringify(e))) await readRun($)
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `timeout 300 /root/.local/bin/claude plugin test plugins/dforge`
Expected: PASS, including every `cockpit roots` test (`'an exit 127 keeps the
checkout paths silently'` still matches `node: not found`; `'without node the
checkout paths stay silently'` still matches "failed to start"), and Task 4's two
primary-checkout tests, which carry their own `stores.json`.

Then confirm DR 5:
Run: `grep -c '\\.dforge|\\.dforge' plugins/dforge/hooks/cockpit/register.tsx`
Expected: `0`

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/hooks/cockpit/register.tsx plugins/dforge/tests/cockpit.test.ts
git commit -m "fix(cockpit): refresh darkmem roots on config change"
```

---

### Task 8: Align brainstorming and writing-plans auto-run text

**Files:**
- Modify: `plugins/dforge/skills/brainstorming/SKILL.md`
- Modify: `plugins/dforge/skills/writing-plans/SKILL.md`

**Interfaces:**
- Consumes: None
- Produces: None

**Items:** AE 9, AE 10, AE 25

**Depends on:** none
**Implementer:** dr-superpowers:impl-sonnet-low
**Executor:** codex gpt-6.1-sol / low
**Evaluation:** files 1 - spec 0 - coupling 0 - risk 1 = 2

This task changes skill text only, so it has no failing test. It discharges
AE 10.L1-L5 (brainstorming), AE 25.L6 for the brainstorming and writing-plans
clauses, AE 25.L8 parts (a) brainstorming and (c) writing-plans, and AE 9.L3
for writing-plans (rewrap prose over 80 columns).

Nine suites grep these two files, and several phrases they grep must stay
whole on one line. Do not edit any test file in this task (in particular
`plugins/dforge/tests/settings-skills.test.sh`, `auto-default.test.sh` and
`parallel-grouping.test.sh` belong to other work). Every old and new block
below was checked against those suites: copy each new block exactly,
including its line breaks.

- [ ] **Step 1: Verify the current text**

Run each command; each must print `1`:

```bash
grep -cF 'skip this gate and go to Implementation. Otherwise, after posting the self-review block' plugins/dforge/skills/brainstorming/SKILL.md
grep -cF 'or does it need decomposition?' plugins/dforge/skills/brainstorming/SKILL.md
grep -cF '  an auto run skip this check: the plan is always written in this session.' plugins/dforge/skills/brainstorming/SKILL.md
grep -cF '(an auto run has Fable review it instead)' plugins/dforge/skills/brainstorming/SKILL.md
grep -cF '"User reviews spec?" -> "Invoke writing-plans skill" [label="approved"];' plugins/dforge/skills/brainstorming/SKILL.md
grep -cF 'new self-review round; the critic and Fable do not run again.' plugins/dforge/skills/brainstorming/SKILL.md
grep -cF '  with none, write `sequential`.' plugins/dforge/skills/writing-plans/SKILL.md
grep -cF 'never suggest a split, and take a later change of scope' plugins/dforge/skills/writing-plans/SKILL.md
```

Then confirm the reader suites pass before the change:

```bash
for t in auto-default process-roles settings-skills parallel-grouping project-status review-route inline-mode lanes test-simplifier; do timeout 600 bash plugins/dforge/tests/$t.test.sh > /dev/null 2>&1 && echo "$t ok" || echo "$t FAIL"; done
```

Expected: every suite prints `ok`.

- [ ] **Step 2: Implement**

Make each replacement below exactly once. Each "Old" block occurs exactly
once in its file today; replace it with the "New" block. Edits are listed in
file order.


**File `plugins/dforge/skills/brainstorming/SKILL.md`**

Edit 1 — item 9 (AE 25 L6): designApproval setting.

Old:

```text
  for approval once, instead of after each section. It has no effect under
  `autoRun=on`, which presents no design.
```

New:

```text
  for approval once, instead of after each section. It has no effect on Claude
  Code under `autoRun=on`, which presents no design.
```

Edit 2 — item 9 (AE 25 L6): specReview setting.

Old:

```text
  Gate and go on to Implementation. It has no effect under `autoRun=on`:
  the spec review always happens.
```

New:

```text
  Gate and go on to Implementation. It has no effect under `autoRun=on`:
  on Claude Code the spec review always happens.
```

Edit 3 — item 4 (AE 10 L4): checklist step 12.

Old:

```text
12. **User reviews written spec** — ask user to review the spec file before proceeding (an auto run has Fable review it instead)
```

New:

```text
12. **User reviews written spec** — ask user to review the spec file before proceeding; under `autoRun=on` Fable reviews it first and this is Auto by default's spec review message (an auto run started from the offer has Fable review it instead)
```

Edit 4 — item 4 (AE 10 L5): process graph nodes.

Old:

```text
    "Invoke writing-plans skill" [shape=doublecircle];
    "Hidden complexity? Upgrade path" [shape=box];

```

New:

```text
    "Invoke writing-plans skill" [shape=doublecircle];
    "Hidden complexity? Upgrade path" [shape=box];
    "Write spec directly\n(autoRun=on, with ## Decisions)" [shape=box];
    "Draft acceptance in the spec\n(ask nothing yet)" [shape=box];
    "Fable spec review\n(at most two rounds)" [shape=box];
    "Spec review\n(the one stop)" [shape=diamond];
    "Revise spec\n+ one new self-review round" [shape=box];

```

Edit 5 — item 4 (AE 10 L5): process graph edges.

Old:

```text
    "User reviews spec?" -> "Invoke writing-plans skill" [label="approved"];
}
```

New:

```text
    "User reviews spec?" -> "Invoke writing-plans skill" [label="approved"];
    "Ask execution strategy\n(parallel or sequential)" -> "Write spec directly\n(autoRun=on, with ## Decisions)" [label="autoRun=on"];
    "Write spec directly\n(autoRun=on, with ## Decisions)" -> "Draft acceptance in the spec\n(ask nothing yet)";
    "Draft acceptance in the spec\n(ask nothing yet)" -> "Spec self-review\n(one round, shown)";
    "Architecture critic\n(one judge-opus round)" -> "Fable spec review\n(at most two rounds)" [label="autoRun=on"];
    "Fable spec review\n(at most two rounds)" -> "Spec review\n(the one stop)";
    "Spec review\n(the one stop)" -> "Revise spec\n+ one new self-review round" [label="changes needed"];
    "Revise spec\n+ one new self-review round" -> "Spec review\n(the one stop)";
    "Spec review\n(the one stop)" -> "Invoke writing-plans skill" [label="either approval"];
}
```

Edit 6 — item 9 (AE 25 L6): decomposition bullet.

Old:

```text
- Under `autoRun=ask` or `autoRun=off` only (under `on`, one spec covers the whole request): if the project
```

New:

```text
- Under `autoRun=ask` or `autoRun=off` only (under `on`, one spec covers the whole request) on Claude Code, and under any setting on a Codex host: if the project
```

Edit 7 — item 9 (AE 25 L6): presenting the design.

Old:

```text
; under `autoRun=on` present no design (see Auto by default)

```

New:

```text
; under `autoRun=on` present no design (see Auto by default), on Claude Code only

```

Edit 8 — item 11 (AE 25 L8 a): re-present the spec review.

Old:

```text
   Apply the answers to the spec. **Changes needed** gets the revision and one
   new self-review round; the critic and Fable do not run again.
   `specReview=false` does not skip this stop.
```

New:

```text
   Apply the answers to the spec. **Changes needed** gets the revision and one
   new self-review round; the critic and Fable do not run again. Then present
   this step's message again, with the questions still open, until your human
   partner picks one of the two approvals.
   `specReview=false` does not skip this stop.
```

Edit 9 — item 4 (AE 10 L2): self-review scope check.

Old:

```text
3. **Scope check:** Is this focused enough for a single implementation plan, or does it need decomposition?
```

New:

```text
3. **Scope check:** Is this focused enough for a single implementation plan, or does it need decomposition (not under `autoRun=on` on Claude Code)?
```

Edit 10 — item 4 (AE 10 L1): User Review Gate skip.

Old:

```text
With `specReview=false` (see Settings), skip this gate and go to Implementation. Otherwise, after posting the self-review block, ask the user to review the written spec before proceeding:
```

New:

```text
Outside `autoRun=on`, the `specReview` setting can skip this gate.
With `specReview=false` (see Settings), skip this gate and go to Implementation.
Otherwise, after posting the self-review block, ask the user to review the
written spec before proceeding:
```

Edit 11 — item 4 (AE 10 L3): plan budget check.

Old:

```text
- Run `scripts/context-size --plan` (see using-dforge §Session Budget).
  It measures against 150% of the task budget, capped at the final-phase
  limit: writing the plan here costs less than a fresh session's baseline
  and reload. On exit 5 (handoff), invoke dforge:handoff with
  the spec as the draft and the next action "Write the implementation plan
  with dforge:writing-plans." — the plan is written in a fresh session. In
  an auto run skip this check: the plan is always written in this session.
```

New:

```text
- In an auto run skip this check: the plan is always written in this session.
  Otherwise run `scripts/context-size --plan` (see using-dforge §Session
  Budget). It measures against 150% of the task budget, capped at the
  final-phase limit: writing the plan here costs less than a fresh session's
  baseline and reload. On exit 5 (handoff), invoke dforge:handoff with the spec
  as the draft and the next action "Write the implementation plan with
  dforge:writing-plans." — the plan is written in a fresh session.
```


**File `plugins/dforge/skills/writing-plans/SKILL.md`**

Edit 12 — item 2 (AE 9 L3): rewrap Overview.

Old:

```text
Write comprehensive implementation plans assuming the engineer has zero context for our codebase and questionable taste. Document everything they need to know: which files to touch for each task, code, testing, docs they might need to check, how to test it. Give them the whole plan as bite-sized tasks. DRY. YAGNI. TDD. Frequent commits.
```

New:

```text
Write comprehensive implementation plans assuming the engineer has zero context
for our codebase and questionable taste. Document everything they need to know:
which files to touch for each task, code, testing, docs they might need to
check, how to test it. Give them the whole plan as bite-sized tasks. DRY. YAGNI.
TDD. Frequent commits.
```

Edit 13 — item 2 (AE 9 L3): rewrap Overview.

Old:

```text
Assume they are a skilled developer, but know almost nothing about our toolset or problem domain. Assume they don't know good test design very well. Small models execute these plans literally: each task's implementer sees only that task's text plus the header's Global Constraints and Contracts.
```

New:

```text
Assume they are a skilled developer, but know almost nothing about our toolset
or problem domain. Assume they don't know good test design very well. Small
models execute these plans literally: each task's implementer sees only that
task's text plus the header's Global Constraints and Contracts.
```

Edit 14 — item 2 (AE 9 L3): rewrap Overview.

Old:

```text
**Keep it minimal and checkable:** no speculative abstractions; each task is the minimum that meets the spec; each task ends with a check that proves it.
```

New:

```text
**Keep it minimal and checkable:** no speculative abstractions; each task is the
minimum that meets the spec; each task ends with a check that proves it.
```

Edit 15 — item 2 (AE 9 L3): rewrap Overview.

Old:

```text
**Announce at start:** "I'm using the writing-plans skill to create the implementation plan."
```

New:

```text
**Announce at start:** "I'm using the writing-plans skill to create the
implementation plan."
```

Edit 16 — item 2 (AE 9 L3): rewrap Overview.

Old:

```text
**Context:** If working in an isolated worktree, it should have been created via the `dforge:using-git-worktrees` skill at execution time.
```

New:

```text
**Context:** If working in an isolated worktree, it should have been created via
the `dforge:using-git-worktrees` skill at execution time.
```

Edit 17 — item 11 (AE 25 L8 c): auto-run strategy default.

Old:

```text
- **The execution strategy:** take the spec's `**Execution strategy:**` line;
  with none, write `sequential`.
```

New:

```text
- **The execution strategy:** take the spec's `**Execution strategy:**` line;
  with none, take the `executionStrategy` setting (`parallel` by default) as
  Parallel waves says, and write `sequential` when it is `ask`.
```

Edit 18 — item 9 (AE 25 L6) + item 2 rewrap: Scope Check.

Old:

```text
If the spec covers multiple independent subsystems, it should have been broken into sub-project specs during brainstorming. If it wasn't, suggest breaking this into separate plans — one per subsystem. Each plan should produce working, testable software on its own. Under `autoRun=on` the spec covers the whole request by design: write one plan for it, never suggest a split, and take a later change of scope through the ruling seat's AMEND path.
```

New:

```text
If the spec covers multiple independent subsystems, it should have been broken
into sub-project specs during brainstorming. If it wasn't, suggest breaking this
into separate plans — one per subsystem. Each plan should produce working,
testable software on its own.
Under `autoRun=on` the spec covers the whole request by design: write one plan for it, never suggest a split,
and take a later change of scope through the ruling seat's AMEND path. That
holds on Claude Code; on a Codex host `on` behaves as `off`.
```

Edit 19 — item 2 (AE 9 L3): rewrap File Structure.

Old:

```text
Before defining tasks, map out which files will be created or modified and what each one is responsible for. This is where decomposition decisions get locked in.
```

New:

```text
Before defining tasks, map out which files will be created or modified and what
each one is responsible for. This is where decomposition decisions get locked
in.
```

Edit 20 — item 2 (AE 9 L3): rewrap File Structure.

Old:

```text
This structure informs the task decomposition. Each task should produce self-contained changes that make sense independently.
```

New:

```text
This structure informs the task decomposition. Each task should produce
self-contained changes that make sense independently.
```

Edit 21 — item 2 (AE 9 L3): rewrap File Structure.

Old:

```text
**Walking skeleton:** for a greenfield system, Task 1 builds the thinnest end-to-end path through every layer, with its test, before any layer is fleshed out.
```

New:

```text
**Walking skeleton:** for a greenfield system, Task 1 builds the thinnest
end-to-end path through every layer, with its test, before any layer is fleshed
out.
```

Edit 22 — item 2 (AE 9 L3): rewrap File Structure.

Old:

```text
- Design units with clear boundaries and well-defined interfaces. Each file should have one clear responsibility.
```

New:

```text
- Design units with clear boundaries and well-defined interfaces. Each file
  should have one clear responsibility.
```

Edit 23 — item 2 (AE 9 L3): rewrap File Structure.

Old:

```text
- You reason best about code you can hold in context at once, and your edits are more reliable when files are focused. Prefer smaller, focused files over large ones that do too much.
```

New:

```text
- You reason best about code you can hold in context at once, and your edits are
  more reliable when files are focused. Prefer smaller, focused files over large
  ones that do too much.
```

Edit 24 — item 2 (AE 9 L3): rewrap File Structure.

Old:

```text
- Files that change together should live together. Split by responsibility, not by technical layer.
```

New:

```text
- Files that change together should live together. Split by responsibility, not
  by technical layer.
```

Edit 25 — item 2 (AE 9 L3): rewrap File Structure.

Old:

```text
- In existing codebases, follow established patterns. If the codebase uses large files, don't unilaterally restructure - but if a file you're modifying has grown unwieldy, including a split in the plan is reasonable.
```

New:

```text
- In existing codebases, follow established patterns. If the codebase uses large
  files, don't unilaterally restructure - but if a file you're modifying has
  grown unwieldy, including a split in the plan is reasonable.
```

Edit 26 — item 2 (AE 9 L3): rewrap Codex Execution line sentence.

Old:

```text
names the native pair: `**Execution:** <inline|subagent> — codex <model> / <effort> — <why>`.
```

New:

```text
names the native pair:
`**Execution:** <inline|subagent> — codex <model> / <effort> — <why>`.
```

Edit 27 — item 2 (AE 9 L3): rewrap settings paragraph.

Old:

```text
defaults. A key the line does not name is at its default, and your human partner's
own instructions outrank a setting.
```

New:

```text
defaults. A key the line does not name is at its default, and your human
partner's own instructions outrank a setting.
```

Edit 28 — item 2 (AE 9 L3): rewrap No Placeholders.

Old:

```text
Every step must contain the actual content an engineer needs. These are **plan failures** — never write them:
```

New:

```text
Every step must contain the actual content an engineer needs. These are
**plan failures** — never write them:
```

Edit 29 — item 2 (AE 9 L3): rewrap No Placeholders.

Old:

```text
- "Similar to Task N" (repeat the code — the engineer may be reading tasks out of order)
```

New:

```text
- "Similar to Task N" (repeat the code — the engineer may be reading tasks out
  of order)
```

Edit 30 — item 2 (AE 9 L3): rewrap No Placeholders.

Old:

```text
- Steps that describe what to do without showing how (code blocks required for code steps)
```

New:

```text
- Steps that describe what to do without showing how (code blocks required for
  code steps)
```

Edit 31 — item 2 (AE 9 L3): rewrap Self-Review.

Old:

```text
After writing the complete plan, look at the spec with fresh eyes and check the plan against it. This round is required, and it is yours: run the checklist once, never through a subagent. The plan review under Lint and Review comes after it and does not replace it.
```

New:

```text
After writing the complete plan, look at the spec with fresh eyes and check the
plan against it. This round is required, and it is yours: run the checklist
once, never through a subagent. The plan review under Lint and Review comes
after it and does not replace it.
```

Edit 32 — item 2 (AE 9 L3): rewrap Self-Review.

Old:

```text
**1. Spec coverage:** Skim each section/requirement in the spec. Can you point to a task that implements it? List any gaps.
```

New:

```text
**1. Spec coverage:** Skim each section/requirement in the spec. Can you point
to a task that implements it? List any gaps.
```

Edit 33 — item 2 (AE 9 L3): rewrap Self-Review.

Old:

```text
**2. Placeholder scan:** Search your plan for red flags — any of the patterns from the "No Placeholders" section above. Fix them.
```

New:

```text
**2. Placeholder scan:** Search your plan for red flags — any of the patterns
from the "No Placeholders" section above. Fix them.
```

Edit 34 — item 2 (AE 9 L3): rewrap Self-Review.

Old:

```text
**3. Contracts:** Every cross-task name appears in Contracts, and every task uses it exactly as stated there. A function called `clearLayers()` in Task 3 but `clearFullLayers()` in Task 7 is a bug.
```

New:

```text
**3. Contracts:** Every cross-task name appears in Contracts, and every task
uses it exactly as stated there. A function called `clearLayers()` in Task 3 but
`clearFullLayers()` in Task 7 is a bug.
```

Edit 35 — item 2 (AE 9 L3): rewrap Self-Review.

Old:

```text
**3a. Waves (waves plans only):** Every `**Depends on:**` line names every task whose output the task consumes, including through Contracts; a missing dependency is the one waves error `plan-lint` cannot see.
```

New:

```text
**3a. Waves (waves plans only):** Every `**Depends on:**` line names every task
whose output the task consumes, including through Contracts; a missing
dependency is the one waves error `plan-lint` cannot see.
```

Edit 36 — item 2 (AE 9 L3): rewrap Self-Review.

Old:

```text
If you find issues, fix them inline. If you find a spec requirement with no task, add the task. Once `plan-lint` reports `0 errors`, post `Self-review (round 1 of 1):` with one line per item (clean, or what you fixed) before the first plan-review round. Do not re-review after fixing, and fixes a plan-review round asks for do not start another round. A revision your human partner asks for gets one new round.
```

New:

```text
If you find issues, fix them inline. If you find a spec requirement with no
task, add the task. Once `plan-lint` reports `0 errors`, post
`Self-review (round 1 of 1):` with one line per item (clean, or what you fixed)
before the first plan-review round. Do not re-review after fixing, and fixes a
plan-review round asks for do not start another round.
A revision your human partner asks for gets one new round.
```

Edit 37 — item 2 (AE 9 L3): rewrap Lint step 1.

Old:

```text
1. **Lint.** Run `scripts/plan-lint PLAN_FILE` (see using-dforge §Session Budget)
   until it reports `0 errors`. Fix each
   WARN, or explain it in one line of the plan's Assumptions. The checker
   covers the header sections, the task headings and index, the Execution
   line, placeholders, and every task's assignment lines.
```

New:

```text
1. **Lint.** Run `scripts/plan-lint PLAN_FILE` (see
   using-dforge §Session Budget) until it reports `0 errors`. Fix each WARN, or
   explain it in one line of the plan's Assumptions. The checker covers the
   header sections, the task headings and index, the Execution line,
   placeholders, and every task's assignment lines.
```

Edit 38 — item 2 (AE 9 L3): rewrap the codex-off bullet.

Old:

```text
   - **`reason=codex-off`** (round 1 while the gate has not opened the review
     surface). No Codex seat runs. The `primary` is
     `dforge:judge-opus`. Dispatch it with the full-plan template, save its reply to
     `<workspace>/plan-review-round-1.md`, and say `codex off — <reason>`,
     quoting the gate line's `reason` (`untrusted` when it printed
     `usable=true`).
```

New:

```text
   - **`reason=codex-off`** (round 1 while the gate has not opened the review
     surface). No Codex seat runs. The `primary` is `dforge:judge-opus`.
     Dispatch it with the full-plan template, save its reply to
     `<workspace>/plan-review-round-1.md`, and say `codex off — <reason>`,
     quoting the gate line's `reason` (`untrusted` when it printed
     `usable=true`).
```


After the edits, these lines of `plugins/dforge/skills/writing-plans/SKILL.md`
are still over 80 columns, deliberately (report them in the task report):

- the frontmatter `description:` line (YAML, one line);
- the Scope Check line beginning "Under `autoRun=on` the spec covers the
  whole request by design" (a `parallel-grouping.test.sh` needle of 109
  characters);
- inside the `markdown` header template fence: the `> **For agentic
  workers:**` line, the `**Execution:**`, `**Parallelism:**`,
  `**Integration check:**` and `**Worktree setup:**` template lines, and the
  Assumptions placeholder line ending "Task 1 is that verifying step.]" (plan
  template text copied into plans, left as is);
- "default is `parallel`), take that value and do not ask. On a Codex host do
  not ask:" (83 characters: it is the union of a `parallel-grouping.test.sh`
  needle and a `settings-skills.test.sh` needle, so it cannot break);
- the `--out <workspace>/plan-review-round-1.json ...` line inside the `bash`
  fence, and the `diff -u ...` and `**Plan review:** ...` code spans, which
  cannot break.

New brainstorming lines follow their neighbours' style (the checklist, the
bulleted lists and the dot graph are one line per entry there); brainstorming
is not part of the AE 9.L3 rewrap.

- [ ] **Step 3: Verify the new text and the reader suites**

Each command must print `1`:

```bash
grep -cF 'Outside `autoRun=on`, the `specReview` setting can skip this gate.' plugins/dforge/skills/brainstorming/SKILL.md
grep -cF 'With `specReview=false` (see Settings), skip this gate and go to Implementation.' plugins/dforge/skills/brainstorming/SKILL.md
grep -cF 'or does it need decomposition (not under `autoRun=on` on Claude Code)?' plugins/dforge/skills/brainstorming/SKILL.md
grep -cF -- '- In an auto run skip this check: the plan is always written in this session.' plugins/dforge/skills/brainstorming/SKILL.md
grep -cF "this is Auto by default's spec review message" plugins/dforge/skills/brainstorming/SKILL.md
grep -cF '"Fable spec review\n(at most two rounds)" -> "Spec review\n(the one stop)";' plugins/dforge/skills/brainstorming/SKILL.md
grep -cF 'this step'"'"'s message again, with the questions still open, until your human' plugins/dforge/skills/brainstorming/SKILL.md
grep -cF '  on Claude Code the spec review always happens.' plugins/dforge/skills/brainstorming/SKILL.md
grep -cF 'Code under `autoRun=on`, which presents no design.' plugins/dforge/skills/brainstorming/SKILL.md
grep -cF 'on Claude Code, and under any setting on a Codex host: if the project' plugins/dforge/skills/brainstorming/SKILL.md
grep -cF '(see Auto by default), on Claude Code only' plugins/dforge/skills/brainstorming/SKILL.md
grep -cF 'with none, take the `executionStrategy` setting (`parallel` by default) as' plugins/dforge/skills/writing-plans/SKILL.md
grep -cF 'holds on Claude Code; on a Codex host `on` behaves as `off`.' plugins/dforge/skills/writing-plans/SKILL.md
```

Each must print `0`:

```bash
grep -cF '(an auto run has Fable review it instead)' plugins/dforge/skills/brainstorming/SKILL.md
grep -cF '  with none, write `sequential`.' plugins/dforge/skills/writing-plans/SKILL.md
```

List the writing-plans lines still over 80 columns and compare them with the
list in Step 2 (only those may remain):

```bash
awk 'length($0) > 80 { print FILENAME ":" NR }' plugins/dforge/skills/writing-plans/SKILL.md
```

(`awk` may count bytes, so a line with an em dash can show up at 81-83
bytes while being 80 characters or fewer; check any extra line with
`sed -n '<N>p' <file> | python3 -c 'import sys; print(len(sys.stdin.read().rstrip()))'`.)

Run every suite that reads these two files:

```bash
timeout 600 bash plugins/dforge/tests/auto-default.test.sh
timeout 600 bash plugins/dforge/tests/process-roles.test.sh
timeout 600 bash plugins/dforge/tests/settings-skills.test.sh
timeout 600 bash plugins/dforge/tests/parallel-grouping.test.sh
timeout 600 bash plugins/dforge/tests/project-status.test.sh
timeout 600 bash plugins/dforge/tests/review-route.test.sh
timeout 600 bash plugins/dforge/tests/inline-mode.test.sh
timeout 600 bash plugins/dforge/tests/lanes.test.sh
timeout 600 bash plugins/dforge/tests/test-simplifier.test.sh
```

Expected: PASS, `0 failed` from each. A failure names a phrase a suite greps
for: restore that phrase to one line exactly as the suite spells it, never
edit the suite.

Read the brainstorming dot graph once: every edge ends with `;`, and every
node an edge names is declared above the edges.

- [ ] **Step 4: Commit**

```bash
git add plugins/dforge/skills/brainstorming/SKILL.md plugins/dforge/skills/writing-plans/SKILL.md
git commit -m "docs(skills): align brainstorming and plans text"
```

---

### Task 9: Fix the final review and finishing text

**Files:**
- Modify: `plugins/dforge/reference/final-review.md`
- Modify: `plugins/dforge/skills/finishing-a-development-branch/SKILL.md`
- Test (read only, not edited): `plugins/dforge/tests/auto-default.test.sh`, `plugins/dforge/tests/auto-run-skills.test.sh`, `plugins/dforge/tests/final-phase.test.sh`, `plugins/dforge/tests/gates-manifest.test.sh`, `plugins/dforge/tests/inline-mode.test.sh`, `plugins/dforge/tests/process-roles.test.sh`, `plugins/dforge/tests/project-status.test.sh`, `plugins/dforge/tests/settings-skills.test.sh`

**Interfaces:**
- Consumes: None
- Produces: the ledger line `final review lens-skipped <id> reason=cap` (one per lens `scripts/lens-route --final` skipped), which Task 10's `reference/auto-run.md` §Finishing reads.

**Items:** AE 9, AE 25, PR 7

**Depends on:** none
**Implementer:** dr-superpowers:impl-sonnet-low
**Executor:** codex gpt-6.1-sol / low
**Evaluation:** files 1 - spec 0 - coupling 0 - risk 1 = 2

Sub-findings discharged: AE 9.L3 (finishing rewrap) and 9.L5 (final-review half); AE 25.L2 (final-review and finishing halves), 25.L4 (finishing's deferred-row note), 25.L7, 25.L8 (d); PR 7.

These are text edits with no failing test. Every phrase a suite greps for in these two files stays whole on one line; do not edit any test file (`tests/settings-skills.test.sh` and `tests/process-roles.test.sh` belong to other parts).

- [ ] **Step 1: Verify the current text**

Run from the repository root:

```bash
grep -c 'prints as `lens-skipped`. Run `scripts/auto-run stop`' plugins/dforge/skills/finishing-a-development-branch/SKILL.md
grep -c "recorded-choice block. Three cases override this: on a" plugins/dforge/skills/finishing-a-development-branch/SKILL.md
grep -c 'deferred by the auto run: <the line'"'"'s Ruling>"`' plugins/dforge/skills/finishing-a-development-branch/SKILL.md
grep -c '^0.5 \*\*Acceptance QA.\*\*' plugins/dforge/reference/final-review.md
grep -c 'exists, read it and go to (c) below;' plugins/dforge/reference/final-review.md
grep -c '`git status --porcelain` and keep its output.' plugins/dforge/reference/final-review.md
grep -c 'lens file paths. `lens-skipped` lines and `lenses off` dispatch' plugins/dforge/reference/final-review.md
grep -c 'final review lens-skipped' plugins/dforge/reference/final-review.md plugins/dforge/skills/finishing-a-development-branch/SKILL.md
```

Expected: `1` for each of the first seven; `0` for both files on the last.

Then run the suites that read these files, as a baseline:

```bash
for s in auto-default auto-run-skills final-phase gates-manifest inline-mode process-roles project-status settings-skills; do timeout 600 bash plugins/dforge/tests/$s.test.sh | tail -n 1; done
```

Expected: every line ends `0 failed`.

- [ ] **Step 2: Implement**

Apply each edit below in order with an exact find-and-replace: find the OLD text (it occurs exactly once in the file) and replace it with the NEW text. Indentation and line breaks are part of the text.

**`plugins/dforge/reference/final-review.md`**

Edit FR1: §Who runs it: rewrap the first bullet, add the auto-run `compact` bullet (AE 9.L5), rewrap the Either mode bullet.

OLD:

```text
  final phase never hands off. The final
  phase - this review, its one fix wave and finishing - is measured against
  that final-phase limit, not the task budget, so a `review-package` budget
  line saying `handoff` here does not stop it. Once the review is clean,
  finishing follows with no budget check.
- **Either mode:** point the reviewer at the ledger's deferred-minor and parked
  lines, the complete lines' `discovered:` fields, every borderline (9-13) score,
  and every `(unseated)` ruling, so it can triage what must be fixed before
  merge.
```

NEW:

```text
  final phase never hands off. The final phase - this review, its one fix wave
  and finishing - is measured against that final-phase limit, not the task
  budget, so a `review-package` budget line saying `handoff` here does not
  stop it. Once the review is clean, finishing follows with no budget check.
- **In an auto run** ([auto-run.md](auto-run.md)) the budget line prints the
  run's verdict, and a `compact` line does end the turn here: finish the step
  in flight, with no reviewer or fixer still running, and end the turn as
  auto-run.md §Ending a turn says. After the compaction,
  `scripts/auto-run after-compact` prints `continue` in this phase: resume the
  review from the ledger as the execution skill's After compaction section
  says. It never hands off, and once a compaction has run in this phase every
  budget line says `ok`.
- **Either mode:** point the reviewer at the ledger's deferred-minor and
  parked lines, the complete lines' `discovered:` fields, every borderline
  (9-13) score, and every `(unseated)` ruling, so it can triage what must be
  fixed before merge.
```

Edit FR2: Step 0.5 made a bullet, its recovery path fixed, its status saved to a file, deferred-task rows excluded from the fix wave, rewrapped (PR 7, AE 25.L8 d).

OLD:

```text
0.5 **Acceptance QA.** Skip this step, saying so in one line, when the plan's
   spec has no `A<n>` statement tagged `test`, or when the ledger already holds `Acceptance QA: complete`. When the ledger holds
   `Acceptance QA: dispatched` with no `complete` line, QA was cut off: when
   `<workspace>/acceptance-report.md` exists, read it and go to (c) below;
   otherwise re-dispatch once with `[MODE]` `rerun`, under (b)'s timer, then
   continue at (c); it counts as this review's one re-dispatch. When the
   ledger already holds the re-dispatch `Ruling:` line below, that re-dispatch
   is spent: write `<workspace>/acceptance-report.md` yourself, with
   `cannot-test: timeout` for every `test` statement, and continue at (c).
   Otherwise:

   (a) Append `Acceptance QA: dispatched (base <sha7>)` (the HEAD you hand QA).

   (b) Dispatch `dforge:impl-sonnet-high` (on a Codex host, the native
      implementer `gpt-6.1-sol / high`) with
      [acceptance-qa.md](acceptance-qa.md) and its placeholders: the spec,
      its `test` statements verbatim, MERGE_BASE, HEAD, the test command
      `gates.md` declares or `none`, the workspace, and `[MODE]` `first`.
      When the plan has a `**Worktree setup:**` line, give QA that command
      too, for its mutation worktree. Before dispatching, run
      `git status --porcelain` and keep its output.
      Dispatch it in the background and, in the same message, start a
      background timer, `sleep 2700` (45 minutes), as
      [executor-lane.md](executor-lane.md) arms its timers. When the timer
      finishes first, stop the QA agent (TaskStop on Claude Code; on Codex,
      close the child). Run `git status --porcelain` again: each path it
      lists that the earlier output did not is QA's unfinished work. Restore
      a tracked one with `git restore --staged --worktree -- <path>`, delete
      an untracked one, and log
      `Ruling: QA timed out — its uncommitted files were removed — none`.
      Then write or complete `<workspace>/acceptance-report.md` yourself,
      with `cannot-test: timeout` for every statement it does not cover.
      When QA finishes first, stop the timer.

   (c) When it returns, or on recovery, run `git worktree list`. A QA worktree still listed is
      removed with `git worktree remove --force <workspace>/qa-mutation` and
      `git worktree prune`, and logged as
      `Ruling: QA worktree removed — it held only the throwaway break — none`.
   (d) Read the report and act on each row:
      - `fail`, `flaky`, mutation `green`, or `cannot-test: no-surface`: a
        finding added to the Claude list (step 1), written
        `[qa] A<n>: <result> — <test>`.
      - `cannot-test: ambiguous`: an item for
        `scripts/review-route PLAN_FILE --ruling acceptance-ambiguous`, sent
        with [ruling-prompt.md](../skills/subagent-driven-development/references/ruling-prompt.md).
        `REWORD`: replace the statement's text in the spec with the
        `New statement:` line, commit the spec, and re-dispatch QA with
        `[MODE]` `reword A<n>[, A<m>]`; every ambiguous statement of one
        report shares that single re-dispatch. `PARK`: run
        `scripts/register add <register> "A<n>: <statement>" --state deferred --note "<the ruling>"`
        and change the spec line to `A<n>. deferred — register row <id>`.
        In an auto run a missing ruling follows
        [auto-run.md](auto-run.md) §Rulings.
      - `cannot-test: timeout`: no finding; it is reported, and it keeps the
        branch at an auto run's finish.
   (e) Append `Acceptance QA: complete — <p> pass, <f> fail, <k> flaky, <c> cannot-test, <d> demo`,
      counted from the final report, except `<d>`: the number of the spec's
      statements tagged `demo`, which QA is not given and finishing lists.

   QA is re-dispatched at most once per final review, the recovery
   re-dispatch included. Before that re-dispatch, append
   `Ruling: Acceptance QA re-dispatched (<rerun | reword A<n>[, A<m>]>) — <why> — none`;
   on recovery, that line means the re-dispatch is spent. When it is spent,
   carry out a `REWORD` verdict as `PARK`.
```

NEW:

```text
- 0.5 **Acceptance QA.** Skip this step, saying so in one line, when the
  plan's spec has no `A<n>` statement tagged `test`, or when
  the ledger already holds `Acceptance QA: complete`. When the ledger holds
  `Acceptance QA: dispatched` with no `complete` line, QA was cut off. First,
  when `<workspace>/qa-status-before.txt` exists, remove QA's uncommitted work
  as (b) does when its timer finishes first, and log
  `Ruling: QA cut off — its uncommitted files were removed — none`; without
  that file, remove nothing. Then, when
  `<workspace>/acceptance-report.md` exists, read it, complete it yourself
  with `cannot-test: timeout` for every `test` statement it does not cover,
  and go to (c) below; otherwise re-dispatch once with `[MODE]` `rerun`, under
  (b)'s timer, then continue at (c); it counts as this review's one
  re-dispatch. When the re-dispatch `Ruling:` line below is already in the
  ledger, that re-dispatch
  is spent: write `<workspace>/acceptance-report.md` yourself, with
  `cannot-test: timeout` for every `test` statement, and continue at (c).
  Otherwise:

  (a) Append `Acceptance QA: dispatched (base <sha7>)` (the HEAD you hand QA).

  (b) Dispatch `dforge:impl-sonnet-high` (on a Codex host, the native
      implementer `gpt-6.1-sol / high`) with
      [acceptance-qa.md](acceptance-qa.md) and its placeholders: the spec,
      its `test` statements verbatim, MERGE_BASE, HEAD, the test command
      `gates.md` declares or `none`, the workspace, and `[MODE]` `first`.
      When the plan has a `**Worktree setup:**` line, give QA that command
      too, for its mutation worktree. Before dispatching, save the output of
      `git status --porcelain` to `<workspace>/qa-status-before.txt`.
      Dispatch it in the background and, in the same message, start a
      background timer, `sleep 2700` (45 minutes), as
      [executor-lane.md](executor-lane.md) arms its timers. When the timer
      finishes first, stop the QA agent (TaskStop on Claude Code; on Codex,
      close the child). Run `git status --porcelain` again: each path it
      lists that `<workspace>/qa-status-before.txt` does not is QA's
      unfinished work. Restore a tracked one with
      `git restore --staged --worktree -- <path>`, delete an untracked one,
      and log
      `Ruling: QA timed out — its uncommitted files were removed — none`.
      Then write or complete `<workspace>/acceptance-report.md` yourself,
      with `cannot-test: timeout` for every statement it does not cover.
      When QA finishes first, stop the timer.

  (c) When it returns, or on recovery, run `git worktree list`. A QA worktree
      still listed is removed with
      `git worktree remove --force <workspace>/qa-mutation` and
      `git worktree prune`, and logged as
      `Ruling: QA worktree removed — it held only the throwaway break — none`.

  (d) Read the report and act on each row:
    - In an auto run, a `fail` or `flaky` row whose statement needs work that
      a `Task <N>: complete (deferred by the auto run)` line lists under
      `remaining:` is no finding: the fix wave never does a deferred task's
      work, nor anything [auto-run.md](auto-run.md) §Rulings says is never
      performed. Handle its test as Fixing what it finds §Acceptance tests
      says, with the note `deferred task <N>`.
    - Any other `fail`, `flaky`, mutation `green`, or
      `cannot-test: no-surface`: a finding added to the Claude list (step 1),
      written `[qa] A<n>: <result> — <test>`.
    - `cannot-test: ambiguous`: an item for
      `scripts/review-route PLAN_FILE --ruling acceptance-ambiguous`, sent
      with
      [ruling-prompt.md](../skills/subagent-driven-development/references/ruling-prompt.md).
      `REWORD`: replace the statement's text in the spec with the
      `New statement:` line, commit the spec, and re-dispatch QA with
      `[MODE]` `reword A<n>[, A<m>]`; every ambiguous statement of one
      report shares that single re-dispatch. `PARK`: run
      `scripts/register add <register> "A<n>: <statement>" --state deferred --note "<the ruling>"`
      and change the spec line to `A<n>. deferred — register row <id>`.
      In an auto run a missing ruling follows
      [auto-run.md](auto-run.md) §Rulings.
    - `cannot-test: timeout`: no finding; it is reported, and it keeps the
      branch at an auto run's finish.

  (e) Append
      `Acceptance QA: complete — <p> pass, <f> fail, <k> flaky, <c> cannot-test, <d> demo`,
      counted from the final report, except `<d>`: the number of the spec's
      statements tagged `demo`, which QA is not given and finishing lists.

  QA is re-dispatched at most once per final review, the recovery
  re-dispatch included. Before that re-dispatch, append
  `Ruling: Acceptance QA re-dispatched (<rerun | reword A<n>[, A<m>]>) — <why> — none`;
  on recovery, that line means the re-dispatch is spent. When it is spent,
  carry out a `REWORD` verdict as `PARK`.
```

Edit FR3: Step 1 §Lenses: rewrap, and say step 4 writes skipped lenses to the ledger (AE 25.L2).

OLD:

```text
   and the dedupe judge and the fixer receive the lens file paths. `lens-skipped` lines and `lenses off` dispatch
   nothing; step 4 names them. Lens seats are read-only, so a recovery may
   dispatch them again.
```

NEW:

```text
   and the dedupe judge and the fixer receive the lens file paths.
   `lens-skipped` lines and `lenses off` dispatch nothing; step 4 names them
   and writes each `lens-skipped` line to the ledger. Lens seats are
   read-only, so a recovery may dispatch them again.
```

Edit FR4: Step 4: write each skipped lens to the ledger; rewrap (AE 25.L2).

OLD:

```text
   `lenses off`), and the `Acceptance QA: complete` counts. With two lists:
   confirmed findings ranked most severe first, then
   the rejected ones with the reason each was rejected; a finding both reviewers
   raised and the judge confirmed is the strongest signal available in this
   loop, so say so. With one list: the findings ranked most severe first, then,
   after the fix wave, which were fixed and which the fixer rejected, with the
   re-review's verdict on each rejection. The report is not where the turn
   ends: after the fix wave, the execution skill's Finish section goes
   straight on to dforge:finishing-a-development-branch, and the report
   sits above its menu.

## Fixing what it finds

A confirmed finding gates the handoff whichever reviewer raised it; a rejected
one never does. With one list, every finding gates the handoff until the fixer
fixes it or rejects it with evidence the re-review upholds.

If confirmed findings remain, fix them in ONE wave with the complete list — in
subagent mode one fix subagent, in inline mode one pass of your own. Never one
fixer per finding: per-finding fixers each rebuild context and re-run suites, and
a real session's final-review fix wave cost more than all its tasks combined.

**The fix subagent** (subagent mode). Run
`scripts/review-route PLAN_FILE --final-fix <file> [<file> ...]` with every
repository-relative path the findings name. It prints the highest implementer
tier among the tasks whose `**Files:**` blocks name those paths, as the ledger
last recorded each (an escalation counts, and an `inline` implementer counts as
the Execution line's rung), raised to `impl-sonnet-high` and capped at
`impl-opus-high`; no matched task gives `reason=floor`. Append
`Final fix: implementer <agent> (assigned; base <sha7>)` to the ledger, then
dispatch the printed `primary` as `subagent_type`, with no `model` or `effort` argument.
```

NEW:

```text
   `lenses off`), and the `Acceptance QA: complete` counts. Append each
   `lens-skipped <id> reason=cap` line step 1 printed to the ledger as
   `final review lens-skipped <id> reason=cap`, one line per lens, unless the
   ledger already holds it: finishing lists them from there, because after a
   merge `scripts/lens-route` has no diff left to read. With two lists:
   confirmed findings ranked most severe first, then the rejected ones with
   the reason each was rejected; a finding both reviewers raised and the judge
   confirmed is the strongest signal available in this loop, so say so. With
   one list: the findings ranked most severe first, then, after the fix wave,
   which were fixed and which the fixer rejected, with the re-review's verdict
   on each rejection. The report is not where the turn ends: after the fix
   wave, the execution skill's Finish section goes straight on to
   dforge:finishing-a-development-branch, and the report sits above its menu.

## Fixing what it finds

A confirmed finding gates the handoff whichever reviewer raised it; a rejected
one never does. With one list, every finding gates the handoff until the fixer
fixes it or rejects it with evidence the re-review upholds.

If confirmed findings remain, fix them in ONE wave with the complete list — in
subagent mode one fix subagent, in inline mode one pass of your own. Never one
fixer per finding: per-finding fixers each rebuild context and re-run suites,
and a real session's final-review fix wave cost more than all its tasks
combined. In an auto run a deferred task's acceptance failures are not on that
list (step 0.5 (d)).

**The fix subagent** (subagent mode). Run
`scripts/review-route PLAN_FILE --final-fix <file> [<file> ...]` with every
repository-relative path the findings name. It prints the highest implementer
tier among the tasks whose `**Files:**` blocks name those paths, as the ledger
last recorded each (an escalation counts, and an `inline` implementer counts as
the Execution line's rung), raised to `impl-sonnet-high` and capped at
`impl-opus-high`; no matched task gives `reason=floor`. Append
`Final fix: implementer <agent> (assigned; base <sha7>)` to the ledger, then
dispatch the printed `primary` as `subagent_type`, with no `model` or `effort`
argument.
```

Edit FR5: §Fixing what it finds: rewraps, the deferred-task exclusion, and the acceptance-test edit rule (AE 25.L8 d, PR 7).

OLD:

```text
rejection upheld, or the ruling seat parking it) is the one edit allowed on an acceptance test:
mark that test skipped with a reason naming its register row, commit it, and
run `scripts/register add <register> "A<n>: <statement>" --state deferred --note "<the upheld rejection>"`,
so finishing's test run is green and the statement is not lost.

There is no second fix wave. Residual load-bearing findings surface to your human
partner when dforge:finishing-a-development-branch presents the options.
```

NEW:

```text
rejection upheld, or the ruling seat parking it), or one step 0.5 left to a
deferred task, is the one edit allowed on an acceptance test: mark that test
skipped with a reason naming its register row, commit it, and run
`scripts/register add <register> "A<n>: <statement>" --state deferred --note "<the upheld rejection>"`,
so finishing's test run is green and the statement is not lost.

There is no second fix wave. Residual load-bearing findings surface to your
human partner when dforge:finishing-a-development-branch presents the options.
```

**`plugins/dforge/skills/finishing-a-development-branch/SKILL.md`**

Edit FIN1: §Overview: rewrap the two long lines (AE 9.L3).

OLD:

```text
**Core principle:** Verify tests → Detect environment → Carry out the choice made before the run, or present options → Execute choice → Record the plan → Clean up → Report the next step.

**Announce at start:** "I'm using the finishing-a-development-branch skill to complete this work."
```

NEW:

```text
**Core principle:** Verify tests → Detect environment → Carry out the choice
made before the run, or present options → Execute choice → Record the plan →
Clean up → Report the next step.

**Announce at start:** "I'm using the finishing-a-development-branch skill to
complete this work."
```

Edit FIN2: §Auto run: rewrap the Step 3 bullet and the head of the Step 4 bullet (AE 9.L3).

OLD:

```text
- **Step 3** asks nothing: the base branch is the base `scripts/auto-run status` names.
- **Step 4 shows no menu.** Read `scripts/finish-choice get --plan PLAN_FILE`:
  with nothing recorded in this checkout's plan workspace it reads the spec's
  `Finish:` line itself and records it with `"source": "spec"`, so the spec
  review's answer reaches an execution worktree too; else the `finishAction`
  setting; exit 3 means `ask`. Carry out the matching option as if your
  human partner had chosen it, by
  name, since the detached-HEAD menu renumbers them: `merge` is Merge Locally
  into that base, `pr` is Push and Create PR, and `keep`, `ask` and `wait` are
  Keep As-Is. Never discard. In an auto run this mapping replaces Step 4's
  recorded-choice block. Three cases override this: on a
  detached HEAD (Step 2) there is no merge, so `merge` keeps and `pr` pushes a
  new branch (`git push origin HEAD:refs/heads/<new-branch>`); when the base is
  `none`, `merge` keeps and `pr` opens its request against the dforge's default
  branch; and `merge` keeps when the ledger holds a
  `Task <N>: complete (deferred by the auto run)` line, so a deferred task's
  partial commits never reach the base unreviewed. `merge` also keeps when the `Acceptance QA: complete` line reports a nonzero count of
```

NEW:

```text
- **Step 3** asks nothing: the base branch is
  the base `scripts/auto-run status` names.
- **Step 4 shows no menu.** Read `scripts/finish-choice get --plan PLAN_FILE`:
  with nothing recorded in this checkout's plan workspace it reads the spec's
  `Finish:` line itself and records it with `"source": "spec"`, so the spec
  review's answer reaches an execution worktree too; else the `finishAction`
  setting; exit 3 means `ask`. Carry out the matching option as if your human
  partner had chosen it, by name, since the detached-HEAD menu renumbers them:
  `merge` is Merge Locally into that base, `pr` is Push and Create PR, and
  `keep`, `ask` and `wait` are Keep As-Is. Never discard. In an auto run this
  mapping replaces Step 4's recorded-choice block. Three cases override this:
  on a detached HEAD (Step 2) there is no merge, so `merge` keeps and `pr`
  pushes a new branch (`git push origin HEAD:refs/heads/<new-branch>`); when
  the base is `none`, `merge` keeps and `pr` opens its request against the
  dforge's default branch; and `merge` keeps when the ledger holds a
  `Task <N>: complete (deferred by the auto run)` line, so a deferred task's
  partial commits never reach the base unreviewed.
  `merge` also keeps when the `Acceptance QA: complete` line reports a nonzero count of
```

Edit FIN3: §Auto run Step 4: keep the `finish-choice answer` call (AE 25.L7).

OLD:

```text
  at Step 1, and one the fix wave fixed does not keep the branch.
```

NEW:

```text
  at Step 1, and one the fix wave fixed does not keep the branch. The mapping
  keeps the recorded-choice block's first call: once these cases settle the
  option (`merge`, `pr` or `keep`), run
  `scripts/finish-choice answer <action> --plan PLAN_FILE` with it before
  carrying it out, so the cockpit's Run card drops its finish row and the
  record reads as acted on.
```

Edit FIN4: §Auto run rulings bullet: list skipped lenses from the ledger, rewrap (AE 25.L2, AE 9.L3).

OLD:

```text
  `scripts/lens-route PLAN_FILE --final <base> HEAD` prints as `lens-skipped`. Run `scripts/auto-run stop` with no `--reason` before printing the next-step block: a reason marks the run as stopped and sends a `blocked` notice.
```

NEW:

```text
  a `final review lens-skipped <id> reason=cap` ledger line names (the final
  review wrote them; never run `scripts/lens-route` here, since after a merge
  base..HEAD is empty). Run
  `scripts/auto-run stop` with no `--reason` before printing the next-step block:
  a reason marks the run as stopped and sends a `blocked` notice.
```

Edit FIN5: Step 1: rewrap (AE 9.L3).

OLD:

```text
**If tests fail**, report the failures and stop — the menu comes after a green suite:
```

NEW:

```text
**If tests fail**, report the failures and stop — the menu comes after a
green suite:
```

Edit FIN6: Step 3: rewrap (AE 9.L3).

OLD:

```text
Otherwise, if it is not already known, ask: "This branch split from <your best guess> - is that
correct?" Confirm before merging: merging into the wrong base is expensive to
undo.
```

NEW:

```text
Otherwise, if it is not already known, ask: "This branch split from <your
best guess> - is that correct?" Confirm before merging: merging into the
wrong base is expensive to undo.
```

Edit FIN7: Step 4 menu paragraphs: rewrap (AE 9.L3).

OLD:

```text
the Program line answer, read as before: `After integration: sub-project <k+1> (<title>) of
<spec>` when it names `next: <title>`, `After integration: the program is
complete` when it is the last sub-project, and `After integration: no
follow-on work recorded` when there is no Program line or no plan. Step 7 turns
this into the launch block once the choice is made.

Present the menu exactly as written — concise, with every option coming
from the list above. The menu is the last thing in your message: rulings,
findings and the summary go above it, never after, and never replace it with
a request in prose such as "tell me 'merge it'". Discarding the work happens only in response to your
human partner explicitly asking for it (see "If your human partner asks to
discard the work" below). Wait for their answer; the integration decision
is theirs.
```

NEW:

```text
the Program line answer, read as before:
`After integration: sub-project <k+1> (<title>) of <spec>` when it names
`next: <title>`, `After integration: the program is complete` when it is the
last sub-project, and `After integration: no follow-on work recorded` when
there is no Program line or no plan. Step 7 turns this into the launch block
once the choice is made.

Present the menu exactly as written — concise, with every option coming
from the list above. The menu is the last thing in your message: rulings,
findings and the summary go above it, never after, and never replace it with
a request in prose such as "tell me 'merge it'". Discarding the work happens
only in response to your human partner explicitly asking for it (see "If your
human partner asks to discard the work" below). Wait for their answer; the
integration decision is theirs.
```

Edit FIN8: Step 5b: rewrap (AE 9.L3).

OLD:

```text
Either prefix names the same document: an entry spelled `docs/superpowers/<rest>`
already records the plan `docs/dforge/<rest>`, so never add a second line for it.
```

NEW:

```text
Either prefix names the same document: an entry spelled
`docs/superpowers/<rest>` already records the plan `docs/dforge/<rest>`, so
never add a second line for it.
```

Edit FIN9: Step 5b: a deferred task's row keeps its unmerged task ref (AE 25.L4).

OLD:

```text
  `scripts/register set <register> <id> deferred --note "deferred by the auto run: <the line's Ruling>"`
  instead, whichever finish action runs this step, never `done` or `verify`;
```

NEW:

```text
  `scripts/register set <register> <id> deferred --note "deferred by the auto run: <the line's Ruling>[; unmerged task ref <ref>]"`
  instead, with the line's `unmerged task ref <ref>` clause when it has one,
  whichever finish action runs this step, never `done` or `verify`;
```

Edit FIN10: Step 6: rewrap (AE 9.L3).

OLD:

```text
and `handoff.md` while progress is local) is git-ignored and lives in the worktree, so it goes with it —
`git worktree remove` deletes ignored files without `--force`. Options 2 and 3
keep it for the next session.
```

NEW:

```text
and `handoff.md` while progress is local) is git-ignored and lives in the
worktree, so it goes with it — `git worktree remove` deletes ignored files
without `--force`. Options 2 and 3 keep it for the next session.
```

- [ ] **Step 3: Verify the new text and run the suites**

```bash
grep -c 'final review lens-skipped <id> reason=cap' plugins/dforge/reference/final-review.md plugins/dforge/skills/finishing-a-development-branch/SKILL.md
grep -c 'lens-route PLAN_FILE --final <base> HEAD' plugins/dforge/skills/finishing-a-development-branch/SKILL.md
grep -c '`scripts/finish-choice answer <action> --plan PLAN_FILE` with it before' plugins/dforge/skills/finishing-a-development-branch/SKILL.md
grep -c '\[; unmerged task ref <ref>\]"`' plugins/dforge/skills/finishing-a-development-branch/SKILL.md
grep -c '^- 0.5 \*\*Acceptance QA.\*\*' plugins/dforge/reference/final-review.md
grep -c 'qa-status-before.txt' plugins/dforge/reference/final-review.md
grep -c 'Ruling: QA cut off — its uncommitted files were removed — none' plugins/dforge/reference/final-review.md
grep -c 'with `cannot-test: timeout` for every `test` statement it does not cover,' plugins/dforge/reference/final-review.md
grep -c 'In an auto run, a `fail` or `flaky` row whose statement needs work that' plugins/dforge/reference/final-review.md
grep -c '^- \*\*In an auto run\*\* (\[auto-run.md\](auto-run.md)) the budget line prints the$' plugins/dforge/reference/final-review.md
LC_ALL=C.UTF-8 grep -c '.\{81,\}' plugins/dforge/reference/final-review.md
```

Expected, in order: `1` for each file on the first line (final-review.md 1, SKILL.md 1); `0`; `1`; `1`; `1`; `3`; `1`; `1`; `1`; `1`; `7` (the seven lines that cannot break: the `[ruling-prompt.md](...)`, `[code-reviewer.md](...)` and `[re-review-prompt.md](...)` links, the two `scripts/register add ... --note "..."` spans, the `Acceptance QA: complete — ...` span and the `Ruling: Acceptance QA re-dispatched ...` span; the UTF-8 locale makes each em dash count as one column).

Then run every suite that reads these files, and the repository validator (it checks the links):

```bash
for s in auto-default auto-run-skills final-phase gates-manifest inline-mode process-roles project-status settings-skills; do timeout 600 bash plugins/dforge/tests/$s.test.sh | tail -n 1; done
timeout 120 node scripts/validate-repository.mjs
```

Expected: every suite line ends `0 failed`. These suites hold the needles this task keeps whole: in final-review.md the `0.5 **Acceptance QA.**` order check and the phrases on QA recovery, the spent re-dispatch, the `<d>` count, the one allowed acceptance-test edit and the same-session rule (process-roles, final-phase, inline-mode, auto-run-skills); in finishing the auto-run bullets, the recorded-choice block, Step 3, Step 5b and the menu (auto-default, auto-run-skills, final-phase, gates-manifest, project-status, settings-skills). The validator prints `Repository catalogs, manifests, versions, bundled links and the settings schema are valid.`

Read each changed passage once against its finding: AE 9.L5 (§Who runs it names the auto-run `compact` line), AE 25.L2 (step 4 ledgers the lines; finishing lists them from the ledger and never runs `lens-route` after the merge), AE 25.L4 (the deferred-row note keeps the unmerged task ref), AE 25.L7 (the auto mapping still runs `finish-choice answer`), AE 25.L8 (d) (a deferred task's acceptance failures never reach the fix wave), PR 7 (recovery fills `cannot-test: timeout` and removes QA's uncommitted paths; 0.5 is a bullet; no prose line over 80 columns).

- [ ] **Step 4: Commit**

```bash
git add plugins/dforge/reference/final-review.md plugins/dforge/skills/finishing-a-development-branch/SKILL.md
git commit -m "docs(dforge): fix final review and finishing text"
```

---

### Task 10: Fix auto-run text in the execution skills

**Files:**
- Modify: `plugins/dforge/skills/executing-plans/SKILL.md`
- Modify: `plugins/dforge/skills/subagent-driven-development/SKILL.md`
- Modify: `plugins/dforge/reference/auto-run.md`
- Modify: `plugins/dforge/reference/parallel-waves.md`
- Test: `plugins/dforge/tests/auto-run-skills.test.sh` (read only, not edited)

**Interfaces:**
- Consumes: the ledger line `final review lens-skipped <id> reason=cap`, which Task 9 makes `reference/final-review.md` step 4 write (one line per skipped lens). This task cites it; Task 9 runs first (see Depends on).
- Produces: None

**Items:** AE 9, AE 25, AE 36, FS 36

**Depends on:** Task 9
**Implementer:** dr-superpowers:impl-sonnet-medium
**Executor:** codex gpt-6.1-sol / high
**Evaluation:** files 2 - spec 0 - coupling 1 - risk 1 = 4

These are text edits with no failing test. The sub-findings: AE 25.L1 (name the two execution-phase turn-ending lines), AE 25.L2 (auto-run.md §Finishing half: list skipped lenses from the ledger), AE 25.L3 (run `after-compact` after any compaction), AE 25.L4 (a deferred wave task names its unmerged task ref), AE 36 (§Clears handles `next-step` exit 5), FS 36 (rewrap the finish-preference parenthetical in both execution skills), AE 9.L3 (auto-run.md half: rewrap prose over 80 columns).

Other suites grep these files for exact phrases. Do not edit any test file. Every replacement below keeps each of these phrases whole on one line; do not reflow text beyond what is quoted:
- `tests/auto-run-skills.test.sh`: '`scripts/auto-run after-compact` before step 0 above', 'then run `scripts/auto-run clear` and end as auto-run.md §Clears says', "a deferred task's branch is", 'also keeps the branch when the ledger holds a', '`merge` also keeps the branch when the `Acceptance QA: complete` line reports a nonzero count of', '`cannot-test`, or when the run added a deferred register row', 'whose Item begins `A<n>:` or whose Note is `critic Blocker unresolved`', "at it. The line's `fail` and `flaky` counts are not read: they are taken", 'deferred at the spec review, before the run started, counts as one the run', 'added. `merge` also keeps the branch when the run added a deferred row whose', 'every `demo` statement of the spec, every lens', 'stop` with no `--reason` before', 'the choice `scripts/finish-choice get --plan PLAN_FILE` prints, which the spec', 'If `scripts/next-step` exits 4, do not run `scripts/auto-run clear`', '`scripts/next-step` exits 4 during a clear (see Clears).', "it leaves undecided or without a suggestion to the run's register, except a", 'a `next-step` exit 4 or 5 there is', and `grep -c 'clear --phase'` over auto-run.md must stay 1.
- `tests/final-phase.test.sh`: '`scripts/finish-choice set <action> --plan PLAN_FILE` instead of asking.' in both skills.
- `tests/project-status.test.sh` (Task 11 adds this needle): 'After each `complete` and `fix round` line, run `scripts/darkmem-sync push`;' in both skills. This task does not touch that sentence.

- [ ] **Step 1: Verify the current text**

Run each command from the repository root; each prints a count of at least 1:

```bash
grep -c 'one of the two auto-run lines' plugins/dforge/skills/executing-plans/SKILL.md plugins/dforge/skills/subagent-driven-development/SKILL.md
grep -c "the cockpit's prompt has you run" plugins/dforge/skills/executing-plans/SKILL.md plugins/dforge/skills/subagent-driven-development/SKILL.md
grep -c 'already prints a choice (it does so unasked when the `finishAction` setting' plugins/dforge/skills/executing-plans/SKILL.md plugins/dforge/skills/subagent-driven-development/SKILL.md
grep -c 'not merged. Other tasks keep running.' plugins/dforge/skills/subagent-driven-development/SKILL.md
grep -c "The cockpit's prompt asks you to run" plugins/dforge/reference/auto-run.md
grep -c 'prints as `lens-skipped`, and' plugins/dforge/reference/auto-run.md
grep -c 'wave, a deferred task.s branch is not merged.$' plugins/dforge/reference/auto-run.md
grep -c 'run defers is not merged.$' plugins/dforge/reference/parallel-waves.md
```

Expected: every count is 1 (the first three print 1 for each file).

- [ ] **Step 2: Implement**

Make each replacement below exactly once. The old text is quoted whole, including indentation; replace it with the new text verbatim.

**Edit 1: executing-plans: after any compaction (AE 25.L3)** — `plugins/dforge/skills/executing-plans/SKILL.md`

Old:

````markdown
- **After a compaction**, the cockpit's prompt has you run
  `scripts/auto-run after-compact` before step 0 above. On `handoff` (exit 5),
  invoke dforge:handoff, then run `scripts/auto-run clear` and end as auto-run.md §Clears says.
````

New:

````markdown
- **After any compaction**, whether or not a prompt asks for it (the
  cockpit's prompt does; a compaction Claude Code starts on its own comes with
  none), run `scripts/auto-run after-compact` before step 0 above. On
  `handoff` (exit 5), invoke dforge:handoff,
  then run `scripts/auto-run clear` and end as auto-run.md §Clears says.
````

**Edit 2: executing-plans: name the two turn-ending lines (AE 25.L1)** — `plugins/dforge/skills/executing-plans/SKILL.md`

Old:

````markdown
- **A turn ends** only on one of the two auto-run lines, or after
  `scripts/auto-run stop --reason "<why>"` when the run must stop.
````

New:

````markdown
- **A turn ends** only on `Auto run: compacting` or `Auto run: clearing` as
  its last line, or after `scripts/auto-run stop --reason "<why>"` when the
  run must stop.
````

**Edit 3: executing-plans: rewrap the finish-preference parenthetical (FS 36)** — `plugins/dforge/skills/executing-plans/SKILL.md`

Old:

````markdown
answer, and start work in the same turn. Skip it when
`scripts/finish-choice get --plan PLAN_FILE` already prints a choice (it does so unasked when the `finishAction` setting
names an action), or when
this plan's ledger already exists: a resumed run does not stop to ask. When
````

New:

````markdown
answer, and start work in the same turn. Skip it when
`scripts/finish-choice get --plan PLAN_FILE` already prints a choice (it does
so unasked when the `finishAction` setting names an action), or when this
plan's ledger already exists: a resumed run does not stop to ask. When
````

**Edit 4: subagent-driven-development: after any compaction (AE 25.L3)** — `plugins/dforge/skills/subagent-driven-development/SKILL.md`

Old:

````markdown
- **After a compaction**, the cockpit's prompt has you run
  `scripts/auto-run after-compact` before step 0 above. On `handoff` (exit 5),
  invoke dforge:handoff, then run `scripts/auto-run clear` and end as auto-run.md §Clears says.
````

New:

````markdown
- **After any compaction**, whether or not a prompt asks for it (the
  cockpit's prompt does; a compaction Claude Code starts on its own comes with
  none), run `scripts/auto-run after-compact` before step 0 above. On
  `handoff` (exit 5), invoke dforge:handoff,
  then run `scripts/auto-run clear` and end as auto-run.md §Clears says.
````

**Edit 5: subagent-driven-development: name the two turn-ending lines (AE 25.L1)** — `plugins/dforge/skills/subagent-driven-development/SKILL.md`

Old:

````markdown
- **A turn ends** only on one of the two auto-run lines, or after
  `scripts/auto-run stop --reason "<why>"` when the run must stop.
````

New:

````markdown
- **A turn ends** only on `Auto run: compacting` or `Auto run: clearing` as
  its last line, or after `scripts/auto-run stop --reason "<why>"` when the
  run must stop.
````

**Edit 6: subagent-driven-development: rewrap the finish-preference parenthetical (FS 36)** — `plugins/dforge/skills/subagent-driven-development/SKILL.md`

Old:

````markdown
answer, and start work in the same turn. Skip it when
`scripts/finish-choice get --plan PLAN_FILE` already prints a choice (it does so unasked when the `finishAction` setting
names an action), or when
this plan's ledger already exists: a resumed run does not stop to ask. When
````

New:

````markdown
answer, and start work in the same turn. Skip it when
`scripts/finish-choice get --plan PLAN_FILE` already prints a choice (it does
so unasked when the `finishAction` setting names an action), or when this
plan's ledger already exists: a resumed run does not stop to ask. When
````

**Edit 7: subagent-driven-development: a deferred wave task names its ref (AE 25.L4)** — `plugins/dforge/skills/subagent-driven-development/SKILL.md`

Old:

````markdown
  `Task <N>: complete (deferred by the auto run) — done: nothing; verified: not run; remaining: <the item>[; partial commits <a7>..<b7>, kept for the final review]; discovered: none; assumptions: none; Ruling: <why> — <cost if wrong>`
  and a deferred register row for each. In a wave, a deferred task's branch is
  not merged. Other tasks keep running.
````

New:

````markdown
  `Task <N>: complete (deferred by the auto run) — done: nothing; verified: not run; remaining: <the item>[; partial commits <a7>..<b7>, kept for the final review | ; unmerged task ref <ref>]; discovered: none; assumptions: none; Ruling: <why> — <cost if wrong>`
  and a deferred register row for each. In a wave, a deferred task's branch is
  not merged, so its commits lie outside the final review's range: its line
  takes `unmerged task ref <ref>`, the ref `scripts/wave ref PLAN_FILE <N>`
  prints, in place of the partial-commits clause, and its register row's note
  names the same ref. Other tasks keep running.
````

**Edit 8: auto-run.md: rewrap the spec-phase Fable paragraph (AE 9.L3)** — `plugins/dforge/reference/auto-run.md`

Old:

````markdown
(dforge:brainstorming §Architecture critic), dispatch `dforge:judge-fable` on the spec
against the approved design: the design sections as approved, verbatim, and
the spec's path. Apply what it rules, and record each ruling with
````

New:

````markdown
(dforge:brainstorming §Architecture critic), dispatch `dforge:judge-fable` on
the spec against the approved design: the design sections as approved,
verbatim, and the spec's path. Apply what it rules, and record each ruling
with
````

**Edit 9: auto-run.md: a deferred wave task names its ref (AE 25.L4)** — `plugins/dforge/reference/auto-run.md`

Old:

````markdown
      Task <N>: complete (deferred by the auto run) — done: nothing; verified: not run; remaining: <the item>[; partial commits <a7>..<b7>, kept for the final review]; discovered: none; assumptions: none; Ruling: <why> — <cost if wrong>

  Add one deferred register row per such task. Recovery, `scripts/next-step`
  and the final review count the line as complete, so the run moves on. In a
  wave, a deferred task's branch is not merged.
````

New:

````markdown
      Task <N>: complete (deferred by the auto run) — done: nothing; verified: not run; remaining: <the item>[; partial commits <a7>..<b7>, kept for the final review | ; unmerged task ref <ref>]; discovered: none; assumptions: none; Ruling: <why> — <cost if wrong>

  Add one deferred register row per such task. Recovery, `scripts/next-step`
  and the final review count the line as complete, so the run moves on. In a
  wave, a deferred task's branch is not merged, so its commits lie outside the
  final review's range: its line takes `unmerged task ref <ref>`, the ref
  `scripts/wave ref PLAN_FILE <N>` prints, in place of the partial-commits
  clause, and its register row's note names the same ref. Only outside a wave
  are partial commits kept for the final review.
````

**Edit 10: auto-run.md: after-compact after any compaction (AE 25.L3)** — `plugins/dforge/reference/auto-run.md`

Old:

````markdown
The cockpit's prompt asks you to run `scripts/auto-run after-compact` first.
It prints `continue` (exit 0) or `handoff` (exit 5); in the `plan`, `final`
````

New:

````markdown
Run `scripts/auto-run after-compact` first after any compaction, whether or
not a prompt asks for it: the cockpit's prompt asks after the compactions it
runs, but a compaction Claude Code starts on its own comes with no prompt.
It prints `continue` (exit 0) or `handoff` (exit 5); in the `plan`, `final`
````

**Edit 11: auto-run.md: §Clears handles next-step's exit 5 (AE 36)** — `plugins/dforge/reference/auto-run.md`

Old:

````markdown
If `scripts/next-step` exits 4, do not run `scripts/auto-run clear`: the
`latest.md` it would read is an older handoff's. Run `scripts/auto-run stop
--reason "the handoff file could not be written"` and end as Stopping says.
````

New:

````markdown
If `scripts/next-step` exits 4, do not run `scripts/auto-run clear`: the
`latest.md` it would read is an older handoff's. Run `scripts/auto-run stop
--reason "the handoff file could not be written"` and end as Stopping says.

If it exits 5, background work is still listed and nothing was written: run
`scripts/in-flight`, wait for or stop each launch it lists, and run
`scripts/next-step PLAN_FILE` again, as §The switch step 3 does. A second
exit 5 runs
`scripts/auto-run stop --reason "background work still running at the clear: <next-step's message>"`
and ends as Stopping says; do not run `scripts/auto-run clear`.
````

**Edit 12: auto-run.md: §Stopping lists the second exit 5 (AE 36)** — `plugins/dforge/reference/auto-run.md`

Old:

````markdown
- `scripts/next-step` exits 4 during a clear (see Clears).
````

New:

````markdown
- `scripts/next-step` exits 4 during a clear (see Clears).
- `scripts/next-step` exits 5 a second time during a clear (see Clears).
````

**Edit 13: auto-run.md: §Finishing lists lens-skipped lines from the ledger, rewrapped (AE 25.L2, AE 9.L3)** — `plugins/dforge/reference/auto-run.md`

Old:

````markdown
Finishing carries out at once, into the base `scripts/auto-run status` names,
the choice `scripts/finish-choice get --plan PLAN_FILE` prints, which the spec
review recorded, or else the `finishAction` setting: `merge` and `pr` as named; `keep`, `ask` and
`wait` keep the branch, and so does `merge` when the base is `none`. `merge`
also keeps the branch when the ledger holds a
`Task <N>: complete (deferred by the auto run)` line, so a deferred task's
partial commits reach the base only after a person has looked at them.
`merge` also keeps the branch when the `Acceptance QA: complete` line reports a nonzero count of
`cannot-test`, or when the run added a deferred register row
whose Item begins `A<n>:` or whose Note is `critic Blocker unresolved`: an
acceptance statement that failed or went unverified reaches the base only after
a person has looked at it. The line's `fail` and `flaky` counts are not read: they are taken
before the fix wave, a failure that survives it is a deferred `A<n>:` row or a
red test at finishing's first step, and one the fix wave fixed does not keep the branch. A row
deferred at the spec review, before the run started, counts as one the run
added. `merge` also keeps the branch when the run added a deferred row whose
Note is `final review residual`. On a
detached HEAD there is no merge: `merge` keeps the branch and `pr` pushes a new
branch from the detached HEAD. A `pr` with base `none` opens its request
against the dforge's default branch. No menu. Its final message lists
every `Ruling:` ledger line, every line of `scripts/auto-run ruling list`,
every deferred row the run added, every `demo` statement of the spec, every lens
`scripts/lens-route PLAN_FILE --final <base> HEAD` prints as `lens-skipped`, and
it runs `scripts/auto-run stop` with no `--reason` before
the next-step block: a reason marks the run as stopped and sends a `blocked` notice.
````

New:

````markdown
Finishing carries out at once, into the base `scripts/auto-run status` names,
the choice `scripts/finish-choice get --plan PLAN_FILE` prints, which the spec
review recorded, or else the `finishAction` setting: `merge` and `pr` as
named; `keep`, `ask` and `wait` keep the branch, and so does `merge` when the
base is `none`. `merge`
also keeps the branch when the ledger holds a
`Task <N>: complete (deferred by the auto run)` line, so a deferred task's
partial commits reach the base only after a person has looked at them.
`merge` also keeps the branch when the `Acceptance QA: complete` line reports a nonzero count of
`cannot-test`, or when the run added a deferred register row
whose Item begins `A<n>:` or whose Note is `critic Blocker unresolved`: an
acceptance statement that failed or went unverified reaches the base only
after a person has looked
at it. The line's `fail` and `flaky` counts are not read: they are taken
before the fix wave, a failure that survives it is a deferred `A<n>:` row or a
red test at finishing's first step, and one the fix wave fixed does not keep
the branch. A row
deferred at the spec review, before the run started, counts as one the run
added. `merge` also keeps the branch when the run added a deferred row whose
Note is `final review residual`. On a detached HEAD there is no merge: `merge`
keeps the branch and `pr` pushes a new branch from the detached HEAD. A `pr`
with base `none` opens its request against the dforge's default branch. No
menu. Its final message lists every `Ruling:` ledger line, every line of
`scripts/auto-run ruling list`, every deferred row the run added,
every `demo` statement of the spec, every lens
named by a `final review lens-skipped <id> reason=cap` line in the ledger
(final-review.md step 4 writes them; do not run `scripts/lens-route --final`
here, since after a merge its base..HEAD range is empty), and it runs
`scripts/auto-run stop` with no `--reason` before the next-step block: a
reason marks the run as stopped and sends a `blocked` notice.
````

**Edit 14: parallel-waves.md: a deferred task names its unmerged ref (AE 25.L4)** — `plugins/dforge/reference/parallel-waves.md`

Old:

````markdown
the task in flight and ending the turn with `Auto run: compacting`. A task the
run defers is not merged.
````

New:

````markdown
the task in flight and ending the turn with `Auto run: compacting`. A task the
run defers is not merged, and `scripts/wave clean` keeps its ref: its deferred
ledger line and register row name that unmerged task ref
(`scripts/wave ref PLAN_FILE <N>`), since its commits lie outside the final
review's range ([auto-run.md](auto-run.md) §Rulings).
````

Rewrap record for AE 9.L3 (auto-run.md) and FS 36: after these edits the only lines in `plugins/dforge/reference/auto-run.md` over 80 columns are these, and they stay because each is an indented code block, a single code span that cannot break, or a phrase `tests/auto-run-skills.test.sh` greps as one line:
- `    scripts/register add <register> "<item>" --state deferred --note "Fable: <its words>"` (code block)
- `` `scripts/register add <register> "<the finding>" --state deferred --note "critic Blocker unresolved"` `` (code span; needle)
- `    scripts/auto-run decision add --id <id> ...` (code block)
- `      Task <N>: complete (deferred by the auto run) — ...` (code block)
- `` `scripts/register add <register> "A<n>: <statement>" --state deferred --note "Fable gave no ruling"`, `` (code span)
- `` `scripts/register add <run register> "<the finding>" --state deferred --note "final review residual"`. `` (code span; needle)
- `` `scripts/auto-run stop --reason "background work still running at the switch: <next-step's message>"` `` (code span; needle)
- `` `scripts/auto-run stop --reason "background work still running at the clear: <next-step's message>"` `` (code span, added by Edit 11)
- `` `merge` also keeps the branch when the `Acceptance QA: complete` line reports a nonzero count of `` (96 columns; the whole line is a needle)

In the two execution skills, FS 36 rewraps only the parenthetical (Edits 3 and 6). Their remaining over-80 lines (the deferred-line code span, and the budget-line bullet's `then run ... §Clears says.` line in §Auto run) are outside FS 36 and stay.

- [ ] **Step 3: Check the new text**

Run from the repository root:

```bash
grep -c 'only on `Auto run: compacting` or `Auto run: clearing` as' plugins/dforge/skills/executing-plans/SKILL.md plugins/dforge/skills/subagent-driven-development/SKILL.md
grep -c 'After any compaction' plugins/dforge/skills/executing-plans/SKILL.md plugins/dforge/skills/subagent-driven-development/SKILL.md
grep -c 'so unasked when the `finishAction` setting names an action), or when this' plugins/dforge/skills/executing-plans/SKILL.md plugins/dforge/skills/subagent-driven-development/SKILL.md
grep -c 'unmerged task ref' plugins/dforge/skills/subagent-driven-development/SKILL.md plugins/dforge/reference/auto-run.md plugins/dforge/reference/parallel-waves.md
grep -c 'after any compaction, whether or' plugins/dforge/reference/auto-run.md
grep -c 'background work still running at the clear' plugins/dforge/reference/auto-run.md
grep -c 'final review lens-skipped <id> reason=cap' plugins/dforge/reference/auto-run.md
grep -c 'one of the two auto-run lines\|prints as `lens-skipped`' plugins/dforge/skills/executing-plans/SKILL.md plugins/dforge/skills/subagent-driven-development/SKILL.md plugins/dforge/reference/auto-run.md
grep -c 'clear --phase' plugins/dforge/reference/auto-run.md
```

Expected: 1 per file for the first three; for `unmerged task ref`, 2 in subagent-driven-development, 2 in auto-run.md, 1 in parallel-waves.md; 1, 1 and 1 for the next three; 0 in every file for the removed text; 1 for `clear --phase`.

Then read each changed passage once against its finding: L1 names both lines; L2 lists the ledger's lines and no longer runs `lens-route` after the merge; L3 says "any compaction, prompted or not"; L4 names the ref and drops "kept for the final review" for a wave; AE 36 waits or stops, retries once, then stops the run.

- [ ] **Step 4: Run the suites that read these files**

```bash
timeout 600 bash plugins/dforge/tests/auto-run-skills.test.sh
timeout 600 bash plugins/dforge/tests/final-phase.test.sh
timeout 600 bash plugins/dforge/tests/inline-mode.test.sh
timeout 600 bash plugins/dforge/tests/process-roles.test.sh
timeout 600 bash plugins/dforge/tests/project-status.test.sh
timeout 600 bash plugins/dforge/tests/settings-skills.test.sh
timeout 600 bash plugins/dforge/tests/auto-default.test.sh
timeout 600 bash plugins/dforge/tests/turn-end.test.sh
timeout 600 bash plugins/dforge/tests/review-route.test.sh
timeout 600 bash plugins/dforge/tests/next-step.test.sh
timeout 120 node scripts/validate-repository.mjs
```

Expected: every suite ends `0 failed` and the validator passes. `auto-run-skills`, `final-phase`, `project-status`, `inline-mode`, `process-roles`, `turn-end` and `review-route` grep the two execution skills; `auto-run-skills` and `settings-skills` grep `reference/auto-run.md`; `auto-run-skills` greps `reference/parallel-waves.md`; `scripts/validate-repository.mjs` lists auto-run.md and parallel-waves.md in its spelling allowlist. If `project-status` fails only on Task 11's new push-instruction needle, check that the sentence 'After each `complete` and `fix round` line, run `scripts/darkmem-sync push`;' is unchanged in both skills.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/skills/executing-plans/SKILL.md plugins/dforge/skills/subagent-driven-development/SKILL.md plugins/dforge/reference/auto-run.md plugins/dforge/reference/parallel-waves.md
git commit -m "docs(dforge): fix auto-run text in execution skills"
```

---

### Task 11: Qualify handoff and entry text, name Codex push

**Files:**
- Modify: `plugins/dforge/skills/handoff/SKILL.md`
- Modify: `plugins/dforge/skills/using-dforge/SKILL.md`
- Modify: `plugins/dforge/skills/using-dforge/references/codex-tools.md`
- Test: `plugins/dforge/tests/project-status.test.sh`

**Interfaces:**
- Consumes: None
- Produces: None

**Items:** AE 9, AE 25, DR 30, DM 45

**Depends on:** Task 10
**Implementer:** dr-superpowers:impl-sonnet-medium
**Evaluation:** files 2 - spec 0 - coupling 1 - risk 1 = 4

This task covers AE 9.L5 (handoff half: the hard-stop bullet says "outside an auto run"), AE 9.L3 (handoff rewrap), AE 25.L6 (the using-dforge clause says "on Claude Code"), DR 30 (codex-tools heading) and DM 45 (project-status asserts the push instruction; handoff's push paragraph moves ahead of the Codex paragraph; codex-tools names `darkmem-sync push`).

Several lines in `skills/handoff/SKILL.md` are needles other suites grep for, so each must stay whole on one line: `plan saved outside an auto run` (line 3), `The last task completing is never a stop in either execution`, `a compaction that left too much. A saved plan switches in place instead`, `mode hands off too, and the step that invoked this skill runs`, `never runs \`scripts/auto-run clear\` itself`, `- Draft: \`<spec path>\``, `run \`scripts/darkmem-sync push\` and promote` and `the measured number does not override it`. The replacements below keep every one intact.

- [ ] **Step 1: Write the failing tests**

The tests prove three things: both execution skills carry the push instruction itself (not only the citation); handoff's push paragraph comes before its Codex-only paragraph; and codex-tools names the push command.

In `plugins/dforge/tests/project-status.test.sh`, replace this block:

```bash
for skill in subagent-driven-development executing-plans; do
  present "$skill: pushes after each ledger line" "$P/skills/$skill/SKILL.md" '§darkmem sync points'
done
```

with:

```bash
for skill in subagent-driven-development executing-plans; do
  present "$skill: pushes after each ledger line" "$P/skills/$skill/SKILL.md" '§darkmem sync points'
  present "$skill: the push instruction itself" "$P/skills/$skill/SKILL.md" \
    'After each `complete` and `fix round` line, run `scripts/darkmem-sync push`;'
done
HANDOFF_SKILL="$P/skills/handoff/SKILL.md"
push_line=$(grep -nF 'run `scripts/darkmem-sync push` and promote' "$HANDOFF_SKILL" | cut -d: -f1)
codex_line=$(grep -nF 'On Codex, add `--host codex`' "$HANDOFF_SKILL" | cut -d: -f1)
check "handoff: the push comes before the Codex-only paragraph" \
  "$([ -n "$push_line" ] && [ -n "$codex_line" ] && [ "$push_line" -lt "$codex_line" ] && echo yes || echo no)" "yes"
present "codex-tools: names the push at the stop points" "$P/skills/using-dforge/references/codex-tools.md" \
  'run `bash <plugin-root>/scripts/darkmem-sync push`'
```

`check` is `check <name> <got> <want>` and `present` is `present <name> <file> <needle>` (`grep -qF`); both are already defined at the top of the suite.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `timeout 600 bash plugins/dforge/tests/project-status.test.sh`
Expected: FAIL with exactly two failures:
- `handoff: the push comes before the Codex-only paragraph` reports `got: [no]`, because the push paragraph currently follows the "On Codex" paragraph.
- `codex-tools: names the push at the stop points` reports the needle as missing.

The two `the push instruction itself` cases PASS. They are check-only: the sentence already exists, and the gap was coverage.

Then confirm the text-only items' current text:

Run: `grep -nF -e '- A hard stop: the plan is saved, or a plan has just switched from inline to' -e '## Pre-3.0 layout check' -e 'still get approval (under `autoRun=on`, the spec review). Execute' plugins/dforge/skills/handoff/SKILL.md plugins/dforge/skills/using-dforge/references/codex-tools.md plugins/dforge/skills/using-dforge/SKILL.md`
Expected: one match in each of the three files.

Run: `wc -c < plugins/dforge/skills/using-dforge/SKILL.md`
Expected: `5033`

- [ ] **Step 3: Implement**

**3a. `plugins/dforge/skills/handoff/SKILL.md`: rewrap the announce line (AE 9.L3).** Replace:

```markdown
**Announce at start:** "I'm using the handoff skill to end this session cleanly."
```

with:

```markdown
**Announce at start:** "I'm using the handoff skill to end this session
cleanly."
```

**3b. Same file: the hard-stop bullet (AE 9.L5, with the AE 9.L3 rewrap).** Replace:

```markdown
- A hard stop: the plan is saved, or a plan has just switched from inline to
  subagent mode. The last task completing is never a stop in either execution
  mode: the final review and finishing run in the same session whatever
  `scripts/context-size --final` prints. A task
  budget line printed during that final phase does not stop it, and nothing
  stops finishing once the final review is clean. The plan's last two tasks
  are measured against the same final-phase limit, so a short tail never hands
  off on the task budget.
```

with:

```markdown
- A hard stop: the plan is saved outside an auto run, or a plan has just
  switched from inline to subagent mode.
  The last task completing is never a stop in either execution mode: the
  final review and finishing run in the same session whatever
  `scripts/context-size --final` prints. A task budget line printed during
  that final phase does not stop it, and nothing stops finishing once the
  final review is clean. The plan's last two tasks are measured against the
  same final-phase limit, so a short tail never hands off on the task budget.
```

The line break after "subagent mode." keeps the needle `The last task completing is never a stop in either execution` on one line.

**3c. Same file: the auto-run bullet (AE 9.L3 rewrap).** Replace:

```markdown
  end on the next-step block: return to the step that invoked this skill, which runs
  `scripts/auto-run clear` and ends the turn (auto-run.md §Clears). This skill
  never runs `scripts/auto-run clear` itself. A switch from inline to subagent
  mode hands off too, and the step that invoked this skill runs
```

with:

```markdown
  end on the next-step block: return to the step that invoked this skill,
  which runs `scripts/auto-run clear` and ends the turn (auto-run.md §Clears).
  This skill never runs `scripts/auto-run clear` itself. A switch from inline
  to subagent mode hands off too, and the step that invoked this skill runs
```

**3d. Same file: step 2 (AE 9.L3 rewrap).** Replace:

```markdown
   `docs(<scope>): …` commit of their own (push instead while documents live in
   darkmem; see project-state.md). Never commit `<state>/`.
```

with:

```markdown
   `docs(<scope>): …` commit of their own (push instead while documents live
   in darkmem; see project-state.md). Never commit `<state>/`.
```

**3e. Same file: move the push paragraph ahead of the Codex paragraph (DM 45).** Replace:

```markdown
   On Codex, add `--host codex` to the design-phase and unplanned-work calls,
   so the block names the Codex client rather than Claude. A plan states its
   own host in its header, so the execution call needs no flag.

   Then run `scripts/darkmem-sync push` and promote the session's durable
   facts ([project-state.md](../../reference/project-state.md) §darkmem sync
   points): the push carries the ledger, `handoff.md` and `latest.md`.
5. **End the session.**
```

with:

```markdown
   Then run `scripts/darkmem-sync push` and promote the session's durable
   facts ([project-state.md](../../reference/project-state.md) §darkmem sync
   points): the push carries the ledger, `handoff.md` and `latest.md`.

   On Codex, add `--host codex` to the design-phase and unplanned-work calls,
   so the block names the Codex client rather than Claude. A plan states its
   own host in its header, so the execution call needs no flag.
5. **End the session.**
```

After 3a-3e, these handoff lines still run past 80 columns and stay as they are. List them in the task report:
- Line 3: the frontmatter `description:`. It is one YAML line and holds the needle `plan saved outside an auto run`.
- The ruling template code span, `` `Task <N>: Ruling: stopped <what> at handoff — its result is void — <cost if wrong>`. ``
- The `# Handoff — <YYYY-MM-DD> (…)` and `- Plan: …` lines, inside the fenced `latest.md` template.
- Step 4's three command code spans: `- Design phase: \`scripts/next-step --draft …\``, ``for example `--next "Write the implementation plan with dforge:writing-plans."` `` and `- Unplanned work: \`scripts/next-step --adhoc …\``.
- The seven Red Flags table rows, since markdown table rows cannot wrap.

**3f. `plugins/dforge/skills/using-dforge/SKILL.md`: the Process Depth clause (AE 25.L6).** Replace this exact text in the Process Depth paragraph:

```markdown
and still get approval (under `autoRun=on`, the spec review). Execute
```

with:

```markdown
and still get approval (under `autoRun=on`, the spec review). That is on Claude Code; Codex runs `on` as `off`. Execute
```

The paragraph is a single line, so this is an in-line insertion and the paragraph stays on one line. The existing clause is left unchanged because `tests/auto-default.test.sh` greps it verbatim. The file grows by 50 bytes, from 5,033 to 5,083, which stays within the 5,100-byte cap in `tests/hook.test.sh`. Do not raise the cap.

**3g. `plugins/dforge/skills/using-dforge/references/codex-tools.md`: heading (DR 30).** Replace:

```markdown
## Pre-3.0 layout check
```

with:

```markdown
## Older layout check
```

**3h. Same file: name the push command (DM 45).** Replace:

```markdown
that moved or stayed and why. Push at the stop points
[project-state.md](../../../reference/project-state.md) §darkmem sync points
names; nothing pushes for you at the end of a turn.
```

with:

```markdown
that moved or stayed and why. At the stop points
[project-state.md](../../../reference/project-state.md) §darkmem sync points
names, run `bash <plugin-root>/scripts/darkmem-sync push`;
nothing pushes for you at the end of a turn.
```

`tests/settings-skills.test.sh` (P6) greps `nothing pushes for you at the end of a turn`, so that phrase stays whole on its own line.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `timeout 600 bash plugins/dforge/tests/project-status.test.sh`
Expected: PASS (0 failed).

Run: `wc -c < plugins/dforge/skills/using-dforge/SKILL.md`
Expected: `5083` (at most 5100).

Confirm the new text:

Run: `grep -cF -e 'the plan is saved outside an auto run, or a plan has just' -e 'That is on Claude Code; Codex runs `on` as `off`.' -e '## Older layout check' -e 'names, run `bash <plugin-root>/scripts/darkmem-sync push`;' plugins/dforge/skills/handoff/SKILL.md plugins/dforge/skills/using-dforge/SKILL.md plugins/dforge/skills/using-dforge/references/codex-tools.md`
Expected: `handoff/SKILL.md:1`, `using-dforge/SKILL.md:1` and `codex-tools.md:2` (the heading and the push line).

Confirm no new overlong prose:

Run: `LC_ALL=C.UTF-8 awk 'length > 80 { print FNR }' plugins/dforge/skills/handoff/SKILL.md`
Expected: only the lines that 3a-3e list as staying, which are the description, the ruling template, the two template lines, the three step-4 command lines and the seven table rows (14 lines in all).

These suites read the changed files. Run each, and each must PASS:
- handoff: `timeout 600 bash plugins/dforge/tests/final-phase.test.sh`, `timeout 600 bash plugins/dforge/tests/auto-run-skills.test.sh`, `timeout 600 bash plugins/dforge/tests/settings-skills.test.sh`, `timeout 600 bash plugins/dforge/tests/inline-mode.test.sh`
- using-dforge: `timeout 600 bash plugins/dforge/tests/hook.test.sh` (5,100-byte cap), `timeout 600 bash plugins/dforge/tests/auto-default.test.sh`, `timeout 600 bash plugins/dforge/tests/migrate-skill.test.sh`, `timeout 600 bash plugins/dforge/tests/plan-revise.test.sh`, `timeout 600 bash plugins/dforge/tests/review-route.test.sh`, `timeout 600 bash plugins/dforge/tests/test-simplifier.test.sh`, `timeout 600 bash plugins/dforge/tests/working-directory.test.sh`, `timeout 300 node --test plugins/dforge/tests/darkmem-sync/hooks.test.mjs`
- codex-tools: `timeout 600 bash plugins/dforge/tests/dforge-dir.test.sh` (greps ``an `older layout` line``, which is unchanged) and settings-skills (above)

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/skills/handoff/SKILL.md plugins/dforge/skills/using-dforge/SKILL.md plugins/dforge/skills/using-dforge/references/codex-tools.md plugins/dforge/tests/project-status.test.sh
git commit -m "docs(dforge): qualify handoff and name codex push"
```

---

### Task 12: Fix README, prompt and reference text gaps

**Files:**
- Modify: `plugins/dforge/README.md`
- Modify: `plugins/dforge/skills/subagent-driven-development/references/implementer-prompt.md`
- Modify: `plugins/dforge/reference/native-codex.md`
- Modify: `plugins/dforge/skills/revising-plans/SKILL.md`
- Modify: `plugins/dforge/skills/distilling-docs/SKILL.md`

**Interfaces:**
- Consumes: None
- Produces: None

**Items:** AE 9, AE 32, DR 39, CX 8, CX 14, DM 28

**Depends on:** none
**Implementer:** dr-superpowers:impl-sonnet-medium
**Executor:** codex gpt-6.1-sol / medium
**Evaluation:** files 2 - spec 0 - coupling 0 - risk 1 = 3

These are text-only edits; no behaviour changes, so no failing test is
written. Never edit a file under `plugins/dforge/tests/`. Several suites grep
these files for fixed phrases; the edits below leave every such phrase
untouched and on one line. Never put the strings `superpowers:` or
`dr-superpowers:` (with a colon) in any of these files:
`scripts/validate-repository.mjs` refuses them. Outside `README.md`, never
write the word `superpowers` or a bare `forge`.

- [ ] **Step 1: Verify the current text**

Run each command from the repository root. Every one must print the count
shown; if one does not, stop and report BLOCKED with the output.

```bash
grep -cF '| Process | `designApproval` | `sections` | `sections` approves each design section in turn; `whole` presents the design once with one approval. |' plugins/dforge/README.md   # 1
grep -cF '| Process | `specReview` | `true` | Stop for you to review the written spec before the plan is written. |' plugins/dforge/README.md   # 1
grep -cF '   `codex plugin remove dr-forge@darkraise`.' plugins/dforge/README.md   # 1
grep -cF '    Report instead.' plugins/dforge/skills/subagent-driven-development/references/implementer-prompt.md   # 1
grep -cF 'documents ultra as using subagents for separate parts of a complex task. The' plugins/dforge/reference/native-codex.md   # 1
grep -cF '[native-codex.md](../../reference/native-codex.md) §Existing plans instead.' plugins/dforge/skills/revising-plans/SKILL.md   # 1
grep -cF '  When it differs, stop and tell your human partner that the cited text is not' plugins/dforge/skills/distilling-docs/SKILL.md   # 1
```

- [ ] **Step 2: Edit the README settings rows (AE 9.L1)**

File: `plugins/dforge/README.md`, in the settings table.

Old text (two lines, adjacent):

```markdown
| Process | `designApproval` | `sections` | `sections` approves each design section in turn; `whole` presents the design once with one approval. |
| Process | `specReview` | `true` | Stop for you to review the written spec before the plan is written. |
```

New text:

```markdown
| Process | `designApproval` | `sections` | `sections` approves each design section in turn; `whole` presents the design once with one approval. No effect under `autoRun=on` on Claude Code, which presents no design. |
| Process | `specReview` | `true` | Stop for you to review the written spec before the plan is written. No effect under `autoRun=on` on Claude Code: the spec review always happens. |
```

- [ ] **Step 3: Tell dr-superpowers and dr-cockpit users to install dforge (DR 39)**

File: `plugins/dforge/README.md`, section `## Migrating to 4.0`, the end of
numbered step 1.

Old text:

```markdown
   On Codex: `codex plugin add dforge@darkraise`, then
   `codex plugin remove dr-forge@darkraise`.
2. In each repository, run `/dforge:migrate` (on Codex, ask for the
```

New text:

```markdown
   On Codex: `codex plugin add dforge@darkraise`, then
   `codex plugin remove dr-forge@darkraise`.

   From dr-superpowers or dr-cockpit, skip dr-forge and install dforge
   directly. Start one dforge session before you uninstall the old plugins:
   it imports dr-cockpit's options and its Discord webhook and mention, once.
   Migrating from dr-superpowers and dr-cockpit below names
   `dr-forge@darkraise`, the plugin of its day; install `dforge@darkraise`
   in its place.
2. In each repository, run `/dforge:migrate` (on Codex, ask for the
```

(The blank line before the new paragraph is inside list item 1; keep the
three-space indentation on every new line.)

- [ ] **Step 4: Forbid the run-control commands in the implementer prompt (AE 32.L5, prompt half)**

File:
`plugins/dforge/skills/subagent-driven-development/references/implementer-prompt.md`,
inside the fenced prompt template, between the `## You Do Not Dispatch
Subagents` section and the `## Code Organization` section. Every line keeps
the template's four-space indentation.

Old text:

```markdown
    would strengthen my report" — that review is already scheduled.
    Report instead.

    ## Code Organization
```

New text:

```markdown
    would strengthen my report" — that review is already scheduled.
    Report instead.

    ## Run Control Belongs to the Controller

    Never run `scripts/context-size`, `scripts/auto-run` or
    `scripts/next-step` yourself: they belong to the controller. Your shell
    carries the controller's session id, so a call from you reads or moves
    the controller's session budget and auto-run state.

    ## Code Organization
```

- [ ] **Step 5: Restate the ultra sentence as policy (CX 8)**

File: `plugins/dforge/reference/native-codex.md`, the paragraph after the
one ending "split budget, or the five-round cap.".

Old text:

```markdown
An ultra implementer may run subagents in parallel inside its own task: OpenAI
documents ultra as using subagents for separate parts of a complex task. The
task's approved write set, the before/after snapshot and the review still apply
to the task as a whole. Only implementers reach the reserve, so the
no-delegation instruction for scouts and judges is unaffected.
```

New text:

```markdown
An ultra implementer may run subagents in parallel inside its own task: that is
this plugin's policy, not a property of the ultra effort level, so the brief
says so explicitly. The task's approved write set, the before/after snapshot
and the review still apply to the task as a whole. Only implementers reach the
reserve, so the no-delegation instruction for scouts and judges is unaffected.
```

The unsourced claim about OpenAI's documentation goes. OpenAI's Subagents page
(<https://learn.chatgpt.com/docs/agent-configuration/subagents>, read
2026-10-19) describes ultra's proactive delegation for ChatGPT Work, while its
Codex guidance needs an explicit request or project instructions, so it does not
support a claim about native Codex.

- [ ] **Step 6: Name the Codex refusal's stderr text (CX 14)**

File: `plugins/dforge/skills/revising-plans/SKILL.md`. `scripts/plan-revise`
exits 2 through `die` for a usage error, "no executor is registered", "no
such directory", "no such plan file" and the Codex refusal, whose message is
`plan-revise: <plan> is a Codex-host plan; convert it per
reference/native-codex.md §Existing plans`. Keep the phrase "revises Claude
plans only" on its line (`tests/plan-revise.test.sh` greps it).

Old text:

```markdown
This skill revises Claude plans only. `plan-revise` refuses a plan whose header
carries `Host: codex` with exit 2, and the survey lists one as
`host=codex  skipped`: convert a Codex plan per
[native-codex.md](../../reference/native-codex.md) §Existing plans instead.
```

New text:

```markdown
This skill revises Claude plans only. `plan-revise` refuses a plan whose header
carries `Host: codex` with exit 2, and the survey lists one as
`host=codex  skipped`: convert a Codex plan per
[native-codex.md](../../reference/native-codex.md) §Existing plans instead.
Exit 2 also means a usage error, no registered executor, or a missing file or
directory; only the Codex refusal's stderr says "is a Codex-host plan".
```

- [ ] **Step 7: Undo the restore on the stop path (DM 28, skill half)**

File: `plugins/dforge/skills/distilling-docs/SKILL.md`, section `## Documents
in darkmem`, the end of the **Rewrites** bullet. Do not touch the bullet's
earlier lines: `tests/distilling-docs.test.sh` greps "restore <name>\` brings
the newest archived copy back" and "only when the \`@r<id>\` it prints equals
the cited one" on single lines. `darkmem-sync push` moves a document deleted
from the mirror to `dforge/archive/<stamp>/`, which is what undoes a restore.

Old text:

```markdown
  When it differs, stop and tell your human partner that the cited text is not
  recoverable by name. Delete the restored copy again in this wave's removal
  push.
```

New text:

```markdown
  When it differs, undo the restore: delete the restored file from the mirror
  and run `darkmem-sync push`, which moves it back to the archive. Then stop
  and tell your human partner that the cited text is not recoverable by name.
  When it matches, delete the restored copy again in this wave's removal push.
```

- [ ] **Step 8: Verify the new text and run the suites that read these files**

Each grep must print the count shown:

```bash
grep -cF 'No effect under `autoRun=on` on Claude Code, which presents no design. |' plugins/dforge/README.md   # 1
grep -cF 'No effect under `autoRun=on` on Claude Code: the spec review always happens. |' plugins/dforge/README.md   # 1
grep -cF 'From dr-superpowers or dr-cockpit, skip dr-forge and install dforge' plugins/dforge/README.md   # 1
grep -cF '## Run Control Belongs to the Controller' plugins/dforge/skills/subagent-driven-development/references/implementer-prompt.md   # 1
grep -cF '`scripts/next-step` yourself: they belong to the controller.' plugins/dforge/skills/subagent-driven-development/references/implementer-prompt.md   # 1
grep -cF 'separate parts of a complex task' plugins/dforge/reference/native-codex.md   # 0
grep -cF 'this plugin'"'"'s policy, not a property of the ultra effort level' plugins/dforge/reference/native-codex.md   # 1
grep -cF 'documents ultra' plugins/dforge/reference/native-codex.md   # 0
grep -cF 'only the Codex refusal'"'"'s stderr says "is a Codex-host plan".' plugins/dforge/skills/revising-plans/SKILL.md   # 1
grep -cF 'When it differs, undo the restore: delete the restored file from the mirror' plugins/dforge/skills/distilling-docs/SKILL.md   # 1
awk 'length > 80' plugins/dforge/skills/revising-plans/SKILL.md plugins/dforge/skills/distilling-docs/SKILL.md | grep -c 'Codex refusal\|undo the restore\|moves it back\|recoverable by name\|When it matches'   # 0
```

Then run every suite that reads one of these files (each from the
repository root, each must PASS):

- `timeout 600 bash plugins/dforge/tests/auto-run-skills.test.sh` (README)
- `timeout 600 bash plugins/dforge/tests/final-phase.test.sh` (README)
- `timeout 600 bash plugins/dforge/tests/project-status.test.sh` (README)
- `timeout 600 bash plugins/dforge/tests/settings-skills.test.sh` (README,
  every `skills/*/references/*.md` and `reference/*.md`)
- `timeout 600 bash plugins/dforge/tests/dforge-config.test.sh` (README)
- `timeout 600 bash plugins/dforge/tests/inline-mode.test.sh` (README,
  native-codex.md)
- `timeout 600 bash plugins/dforge/tests/review-route.test.sh` (README,
  native-codex.md)
- `timeout 600 bash plugins/dforge/tests/native-routing.test.sh`
  (native-codex.md)
- `timeout 600 bash plugins/dforge/tests/plan-lint.test.sh` (native-codex.md)
- `timeout 600 bash plugins/dforge/tests/next-step.test.sh` (native-codex.md)
- `timeout 600 bash plugins/dforge/tests/process-roles.test.sh`
  (native-codex.md)
- `timeout 600 bash plugins/dforge/tests/plan-revise.test.sh`
  (native-codex.md, revising-plans)
- `timeout 600 bash plugins/dforge/tests/distilling-docs.test.sh`
  (distilling-docs)
- `timeout 600 bash plugins/dforge/tests/hook.test.sh` (routes to
  distilling-docs)
- `timeout 120 node --test tests/repository-layout.test.mjs`
  (native-codex.md)
- `timeout 120 node scripts/validate-repository.mjs` (README allowlists,
  retired-name and skill-link checks over every edited file)

Expected: all PASS. A failure in `validate-repository.mjs` naming a
`retired superpowers name`, `retired dr-forge name` or `legacy plugin-name
reference` means a new line used a refused spelling: reword the line, do not
edit the validator.

- [ ] **Step 9: Commit**

```bash
git add plugins/dforge/README.md plugins/dforge/skills/subagent-driven-development/references/implementer-prompt.md plugins/dforge/reference/native-codex.md plugins/dforge/skills/revising-plans/SKILL.md plugins/dforge/skills/distilling-docs/SKILL.md
git commit -m "docs(dforge): close README and reference text gaps"
```

---

### Task 13: Harden plan-lint's Codex header checks

**Files:**
- Modify: `plugins/dforge/scripts/plan-lint`
- Test: `plugins/dforge/tests/plan-lint.test.sh`

**Interfaces:**
- Consumes: None
- Produces: None

**Items:** CX 9, CX 10, CX 11, CX 12, CX 13

**Depends on:** none
**Implementer:** dr-superpowers:impl-sonnet-low
**Executor:** codex gpt-6.1-sol / low
**Evaluation:** files 1 - spec 0 - coupling 0 - risk 1 = 2

- [ ] **Step 1: Write the failing tests**

The tests prove that a fenced Routing policy line suppresses the pair and tier errors so the conversion error is the only finding (CX 9), that a fenced `Host: codex` line leaves a Claude plan a Claude plan (CX 10), that a backticked Routing policy value is read (CX 11), that an unreadable routing policy exits 2 with a message (CX 12), and that a converted plan with a `## Policy conversion` record lints clean (CX 13).

Replace the fenced-policy case (it gains the older pairs `cnone.md` uses, so the suppression is tested) and add the new cases after it:

In `plugins/dforge/tests/plan-lint.test.sh`, find:

````bash
codex_plan | sed '/^Routing policy:/d; s#^\*\*Goal:\*\* Demo\.$#**Goal:** Demo.\n\n```text\nRouting policy: codex-v4\n```#' > cfenced.md
lint cfenced.md
has "a fenced Routing policy line does not count" "$out" "ERROR header: Routing policy is missing, not codex-v4; convert the plan per reference/native-codex.md §Existing plans"
````

Replace it with:

````bash
codex_plan | sed '/^Routing policy:/d; s#codex gpt-6.1-sol / high#codex gpt-5.6-sol / high#; s#codex gpt-6.1-sol / low#codex gpt-5.6-terra / medium#; s#^\*\*Goal:\*\* Demo\.$#**Goal:** Demo.\n\n```text\nRouting policy: codex-v4\n```#' > cfenced.md
lint cfenced.md
has "a fenced Routing policy line does not count" "$out" "ERROR header: Routing policy is missing, not codex-v4; convert the plan per reference/native-codex.md §Existing plans"
lacks "a fenced Routing policy line: no Execution pair error" "$out" "is not in codex-routing.json"
lacks "a fenced Routing policy line: no Implementer tier error" "$out" "is not an execution tier"
has "a fenced Routing policy line: the conversion error is the only finding" "$out" "plan-lint: 1 errors, 0 warnings"
# A fenced Host line is an example, not the host: the plan stays a Claude plan.
variant chost.md 's/^\*\*Goal:\*\* Demo\.$/**Goal:** Demo.\n\n```text\nHost: codex\n```/'
lint chost.md
check "a fenced Host line: exit 0" "$status" "0"
lacks "a fenced Host line: no Codex checks" "$out" "Routing policy"
has "a fenced Host line: lints as the Claude plan" "$out" "plan-lint: 0 errors, 2 warnings"
# A backticked Routing policy value is the value.
codex_plan | sed 's#^Routing policy: codex-v4$#Routing policy: `codex-v4`#' > cbt.md
lint cbt.md
check "a backticked Routing policy: exit 0" "$status" "0"
check "a backticked Routing policy: clean" "$out" "plan-lint: 0 errors, 0 warnings"
# A routing policy that cannot be read is a usage failure, not a finding.
mkdir -p "$TMP/nojq"
printf '#!/bin/sh\nexit 1\n' > "$TMP/nojq/jq"
chmod +x "$TMP/nojq/jq"
out=$(PATH="$TMP/nojq:$PATH" bash "$LINT" codex.md 2>&1); status=$?
check "an unreadable routing policy: exit 2" "$status" "2"
has "an unreadable routing policy: says so" "$out" "plan-lint: cannot read the routing policy version from"
lacks "an unreadable routing policy: no empty-policy finding" "$out" "not ;"
# A converted plan keeps its conversion record before the Task index and lints clean.
codex_plan | awk '/^## Task index$/ { print "## Policy conversion\n\ncodex-v3 → codex-v4, approved 2026-09-23. Scores unchanged.\n\n| Task | Axes (f/s/c/r) | Score | codex-v3 | codex-v4 | Source |\n|---|---|---|---|---|---|\n| 1 | 1/1/1/0 | 3 | gpt-6-sol / low | gpt-6.1-sol / low | rubric |\n" } { print }' > cconv.md
lint cconv.md
check "a Policy conversion record: exit 0" "$status" "0"
check "a Policy conversion record: clean" "$out" "plan-lint: 0 errors, 0 warnings"
````

- [ ] **Step 2: Run the tests to verify they fail**

Run: `timeout 600 bash plugins/dforge/tests/plan-lint.test.sh`
Expected: FAIL — 8 failures: the three "a fenced Host line" checks (exit 1, the Codex checks ran: "Routing policy is missing" plus Execution and Evaluation errors), the two "a backticked Routing policy" checks ("Routing policy is `codex-v4`, not codex-v4"), and the three "an unreadable routing policy" checks (exit 1 with "Routing policy is codex-v4, not ;"). The four extended fenced-policy checks and the two Policy conversion checks pass already (CX 9 and CX 13 are coverage).

- [ ] **Step 3: Implement**

Document the new exit-2 cause in the usage comment:

In `plugins/dforge/scripts/plan-lint`, find:

```bash
# Exit: 0 no errors; 1 errors; 2 usage or missing file.
```

Replace it with:

```bash
# Exit: 0 no errors; 1 errors; 2 usage, missing file, or an unreadable
# routing policy.
```

CX 10: read the Host line from the unfenced header, the same text the Routing policy read already uses:

In `plugins/dforge/scripts/plan-lint`, find:

```bash
codex=0
grep -qE '^(\*\*)?Host:(\*\*)?[ \t]+codex[ \t]*$' <<<"$header" && codex=1
```

Replace it with:

```bash
# A fenced Host or Routing policy line is an example, not the plan's own.
unfenced_header=$(awk "$_PLAN_AWK"'in_fence($0) { next } { print }' <<<"$header")
codex=0
grep -qE '^(\*\*)?Host:(\*\*)?[ \t]+codex[ \t]*$' <<<"$unfenced_header" && codex=1
```

CX 12 and CX 11: stop with exit 2 when the policy version cannot be read, and accept an optional backtick around the plan's value. `// empty` makes a file with no `version` read as empty instead of the string `null`.

In `plugins/dforge/scripts/plan-lint`, find:

```bash
  want_policy=$(jq -r '.version' "$ROUTING" 2>/dev/null | tr -d '\r')
  got_policy=$(awk "$_PLAN_AWK"'in_fence($0) { next } { print }' <<<"$header" \
    | sed -nE 's/^(\*\*)?Routing policy:(\*\*)?[ \t]+([^ \t]+)[ \t]*$/\3/p' | head -n 1)
```

Replace it with:

```bash
  want_policy=$(jq -r '.version // empty' "$ROUTING" 2>/dev/null | tr -d '\r')
  if [ -z "$want_policy" ]; then
    echo "plan-lint: cannot read the routing policy version from $ROUTING (is jq installed?)" >&2
    exit 2
  fi
  got_policy=$(sed -nE 's/^(\*\*)?Routing policy:(\*\*)?[ \t]+`?([^ \t`]+)`?[ \t]*$/\3/p' <<<"$unfenced_header" | head -n 1)
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `timeout 600 bash plugins/dforge/tests/plan-lint.test.sh`
Expected: PASS.

The other suites that run `plan-lint` must still pass: `timeout 600 bash plugins/dforge/tests/plan-amend.test.sh` and `timeout 600 bash plugins/dforge/tests/plan-revise.test.sh`.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/scripts/plan-lint plugins/dforge/tests/plan-lint.test.sh
git commit -m "fix(plan-lint): harden the Codex header checks"
```

---

### Task 14: Keep empty register cells in their place

**Files:**
- Modify: `plugins/dforge/scripts/plan-lint`
- Modify: `plugins/dforge/scripts/lib/roadmap.sh`
- Test: `plugins/dforge/tests/plan-lint.test.sh`
- Test: `plugins/dforge/tests/roadmap.test.sh`

**Interfaces:**
- Consumes: None
- Produces: None

**Items:** DM 34

**Depends on:** Task 13
**Implementer:** dr-superpowers:impl-sonnet-medium
**Executor:** codex gpt-6.1-sol / medium
**Evaluation:** files 2 - spec 0 - coupling 0 - risk 1 = 3

- [ ] **Step 1: Write the failing tests**

The tests prove that a register row with an empty Item cell is still read with its Assigned and State cells in place, by plan-lint's register checks and by `roadmap_unresolved` (both its milestone rows and an epic row whose spec register must be followed). `scripts/lib/register.sh` is not changed.

In the plan-lint suite, after the "'last' leaves out this plan's row under the other prefix" case:

In `plugins/dforge/tests/plan-lint.test.sh`, find:

```bash
has "plan-lint: 'last' leaves out this plan's row under the other prefix" "$OUT" \
  "ERROR header: Program line says 'last' while register rows are open: #2"
```

Replace it with:

```bash
has "plan-lint: 'last' leaves out this plan's row under the other prefix" "$OUT" \
  "ERROR header: Program line says 'last' while register rows are open: #2"

# An empty Item cell keeps its place: the Assigned cell is still read as Assigned.
cat > "$LREPO/docs/dforge/registers/r.md" <<'REG'
# R — item register

**Source:** review 2026-09-20
**Covers:** docs/superpowers/specs/s-design.md

| # | Item | Assigned | Acceptance | State | Note |
|---|---|---|---|---|---|
| 1 |  | docs/superpowers/plans/p.md | - | planned | - |
| 2 | Someone else's | C2 | - | planned | - |
REG
write_plan "next: Two" ""
OUT=$(cd "$LREPO" && bash "$LINT" docs/superpowers/plans/p.md --no-probe 2>&1)
has "plan-lint: an empty Item cell: the row is still this plan's" "$OUT" \
  "ERROR header: register row #1 is assigned to this plan but no task cites it"
write_plan "last" "**Items:** 1"
OUT=$(cd "$LREPO" && bash "$LINT" docs/superpowers/plans/p.md --no-probe 2>&1)
has "plan-lint: an empty Item cell: 'last' names only the other row" "$OUT" \
  "ERROR header: Program line says 'last' while register rows are open: #2"
```

At the end of the roadmap suite, after the mirror cases and before the summary line:

In `plugins/dforge/tests/roadmap.test.sh`, find:

```bash
  "$(printf 'docs/superpowers/registers/m9.md\t1|docs/dforge/registers/m1.md\t2|')"
```

Replace it with:

```bash
  "$(printf 'docs/superpowers/registers/m9.md\t1|docs/dforge/registers/m1.md\t2|')"

# --- an empty cell keeps its place ---
# Tab-split reads collapse an empty cell, which shifts every later cell left:
# the state would read as the note, and an epic's spec as its Item.
printf '# Gift design\n' > "$D/specs/2026-10-09-gift-design.md"
GIFT=docs/dforge/specs/2026-10-09-gift-design.md
register "$D/registers/gift.md" "$GIFT" '| 1 | Wrap |  | - | open | - |'
register "$D/registers/m5.md" "$GIFT" \
  '| 1 |  | - | - | open | - |' \
  "| 2 |  | $GIFT | - | done | - |"
check "roadmap_unresolved: an empty cell keeps its place" \
  "$(roadmap_unresolved "$ROOT" docs/dforge/registers/m5.md | tr '\t' ',' | tr '\n' '|')" \
  "docs/dforge/registers/m5.md,1,,open,-|docs/dforge/registers/gift.md,1,Wrap,open,-|"
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `timeout 600 bash plugins/dforge/tests/plan-lint.test.sh`
Expected: FAIL — "plan-lint: an empty Item cell: the row is still this plan's" (no error: the Assigned cell was read from the Acceptance column) and "plan-lint: an empty Item cell: 'last' names only the other row" (got `open: #1, #2`).

Run: `timeout 600 bash plugins/dforge/tests/roadmap.test.sh`
Expected: FAIL — "roadmap_unresolved: an empty cell keeps its place": got `docs/dforge/registers/m5.md,1,-,-,-|` (state read from the Note column, and epic row 2's spec read as its Item, so `gift.md` was never followed).

- [ ] **Step 3: Implement**

In `plan-lint`, store the open rows split on `\037` and read them with that IFS. `\037` is not IFS whitespace, so `read` keeps an empty field:

In `plugins/dforge/scripts/plan-lint`, find:

```bash
  : > "$TMP/reg-ids"
  : > "$TMP/reg-open"
  while IFS= read -r reg_file; do
    [ -n "$reg_file" ] || continue
    register_rows "$reg_file" | cut -f1 >> "$TMP/reg-ids"
    register_open "$reg_file" >> "$TMP/reg-open"
  done < <(register_for_spec "$root" "${reg_specs[@]}")
```

Replace it with:

```bash
  : > "$TMP/reg-ids"
  : > "$TMP/reg-open"
  # reg-open holds the rows split on \037, not a tab: `read` collapses runs of
  # a whitespace IFS, so an empty cell would shift every later cell left.
  while IFS= read -r reg_file; do
    [ -n "$reg_file" ] || continue
    register_rows "$reg_file" | cut -f1 >> "$TMP/reg-ids"
    register_open "$reg_file" | tr '\t' '\037' >> "$TMP/reg-open"
  done < <(register_for_spec "$root" "${reg_specs[@]}")
```

In `plugins/dforge/scripts/plan-lint`, find:

```bash
    while IFS=$'\t' read -r rid ritem rassigned _ _ _; do
```

Replace it with:

```bash
    while IFS=$'\037' read -r rid ritem rassigned _ _ _; do
```

In `plugins/dforge/scripts/plan-lint`, find:

```bash
      while IFS=$'\t' read -r rid _ rassigned _; do
```

Replace it with:

```bash
      while IFS=$'\037' read -r rid _ rassigned _; do
```

In `roadmap.sh`, add the converter, read every `register_rows`/`register_open` row through it, and de-duplicate on the name key:

In `plugins/dforge/scripts/lib/roadmap.sh`, find:

```bash
# roadmap_unresolved ROOT REGISTER — every unresolved row below a milestone,
```

Replace it with:

```bash
# _roadmap_cells — tab-separated rows on stdin, split on \037 instead: `read`
# collapses runs of a whitespace IFS, so an empty cell would shift every later
# cell left. Read the result with IFS=$'\037'.
_roadmap_cells() {
  tr '\t' '\037'
}

# roadmap_unresolved ROOT REGISTER — every unresolved row below a milestone,
```

In `plugins/dforge/scripts/lib/roadmap.sh`, find:

```bash
  while IFS=$'\t' read -r id item assigned acceptance state note; do
    printf '%s\t%s\t%s\t%s\t%s\n' "$reg" "$id" "$item" "$state" "${assigned:--}"
  done < <(register_open "$path")
  while IFS=$'\t' read -r id item assigned acceptance state note; do
```

Replace it with:

```bash
  while IFS=$'\037' read -r id item assigned acceptance state note; do
    printf '%s\t%s\t%s\t%s\t%s\n' "$reg" "$id" "$item" "$state" "${assigned:--}"
  done < <(register_open "$path" | _roadmap_cells)
  while IFS=$'\037' read -r id item assigned acceptance state note; do
```

In `plugins/dforge/scripts/lib/roadmap.sh`, find:

```bash
      case " $seen " in *" $rel "*) continue ;; esac
      seen="$seen $rel"
      while IFS=$'\t' read -r rid ritem rassigned racc rstate rnote; do
        printf '%s\t%s\t%s\t%s\t%s\n' "$rel" "$rid" "$ritem" "$rstate" "${rassigned:--}"
      done < <(register_open "$f")
    done < <(register_for_spec "$root" "$a")
  done < <(register_rows "$path")
```

Replace it with:

```bash
      key=$(dforge_name_key "$rel")
      case " $seen " in *" $key "*) continue ;; esac
      seen="$seen $key"
      while IFS=$'\037' read -r rid ritem rassigned racc rstate rnote; do
        printf '%s\t%s\t%s\t%s\t%s\n' "$rel" "$rid" "$ritem" "$rstate" "${rassigned:--}"
      done < <(register_open "$f" | _roadmap_cells)
    done < <(register_for_spec "$root" "$a")
  done < <(register_rows "$path" | _roadmap_cells)
```

In `plugins/dforge/scripts/lib/roadmap.sh`, find:

```bash
  local root=$1 reg=$2 path rel id item assigned acceptance state note a f seen=""
```

Replace it with:

```bash
  local root=$1 reg=$2 path rel key id item assigned acceptance state note a f seen=""
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `timeout 600 bash plugins/dforge/tests/plan-lint.test.sh`
Expected: PASS.

Run: `timeout 600 bash plugins/dforge/tests/roadmap.test.sh`
Expected: PASS.

Other readers of these functions, which must still pass: `timeout 600 bash plugins/dforge/tests/next-step.test.sh`, `timeout 600 bash plugins/dforge/tests/repo-audit.test.sh`, `timeout 600 bash plugins/dforge/tests/register.test.sh`, and `timeout 600 bash plugins/dforge/tests/hook.test.sh` (the SessionStart roadmap line).

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/scripts/plan-lint plugins/dforge/scripts/lib/roadmap.sh plugins/dforge/tests/plan-lint.test.sh plugins/dforge/tests/roadmap.test.sh
git commit -m "fix(dforge): keep empty register cells in place"
```

---

### Task 15: Name every ladder offender and fix fixture agents

**Files:**
- Test: `plugins/dforge/tests/plan-revise.test.sh`
- Test: `plugins/dforge/tests/ladder.test.sh`

**Interfaces:**
- Consumes: None
- Produces: None

**Items:** TR 15, TR 16

**Depends on:** Task 14
**Implementer:** dr-superpowers:impl-sonnet-low
**Evaluation:** files 1 - spec 0 - coupling 0 - risk 0 = 1

- [ ] **Step 1: Write the failing tests**

The plan-revise fixtures name the agent the ladder assigns to each total (`impl-sonnet-low` for totals 0-2), and the ladder suite's implementer check names every offending row, skipping blank lines, with a self-test on synthetic rows.

TR 15, in `plan-revise.test.sh`:

In `plugins/dforge/tests/plan-revise.test.sh`, find:

```bash
mktask() { # mktask <files> <spec> <coupling> <risk> <total>
  printf '### Task 1: One\n\n**Files:**\n- Create: `x`\n\n**Implementer:** dforge:impl-sonnet-medium\n**Evaluation:** files %s - spec %s - coupling %s - risk %s = %s\n' "$@"
}
```

Replace it with:

```bash
mktask() { # mktask <files> <spec> <coupling> <risk> <total> — the Implementer the ladder gives the total
  local agent=impl-sonnet-low
  case $5 in 3|4) agent=impl-sonnet-medium ;; 5) agent=impl-sonnet-high ;; 6) agent=impl-opus-high ;; esac
  printf '### Task 1: One\n\n**Files:**\n- Create: `x`\n\n**Implementer:** dforge:%s\n**Evaluation:** files %s - spec %s - coupling %s - risk %s = %s\n' "$agent" "$@"
}
```

In `plugins/dforge/tests/plan-revise.test.sh`, find:

```bash
#### Part A: a\n\n**Files:**\n- Create: `a`\n\n**Implementer:** dforge:impl-sonnet-medium\n**Evaluation:** files 1 - spec 0 - coupling 1 - risk 0 = 2\n\n#### Part B: b\n\n**Files:**\n- Create: `b`\n\n**Implementer:** dforge:impl-sonnet-medium\n**Evaluation:** files 1 - spec 0 - coupling 1 - risk 0 = 2\n')"
```

Replace it with:

```bash
#### Part A: a\n\n**Files:**\n- Create: `a`\n\n**Implementer:** dforge:impl-sonnet-low\n**Evaluation:** files 1 - spec 0 - coupling 1 - risk 0 = 2\n\n#### Part B: b\n\n**Files:**\n- Create: `b`\n\n**Implementer:** dforge:impl-sonnet-low\n**Evaluation:** files 1 - spec 0 - coupling 1 - risk 0 = 2\n')"
```

In `plugins/dforge/tests/plan-revise.test.sh`, find:

````bash
**Implementer:** dforge:impl-sonnet-medium\n**Evaluation:** files 1 - spec 0 - coupling 1 - risk 0 = 2\n\n```markdown\n> **External executors:** stub\n```\n')"
````

Replace it with:

````bash
**Implementer:** dforge:impl-sonnet-low\n**Evaluation:** files 1 - spec 0 - coupling 1 - risk 0 = 2\n\n```markdown\n> **External executors:** stub\n```\n')"
````

TR 16, in `ladder.test.sh`, replace the single-offender loop with calls to a `not_implementers` function (defined in Step 3):

In `plugins/dforge/tests/ladder.test.sh`, find:

```bash
not_impl=NONE
while read -r _ agent; do
  case " $IMPLEMENTERS " in *" $agent "*) ;; *) not_impl="$agent" ;; esac
done <<< "$assignment"
check "every assigned agent is an execution implementer" "$not_impl" "NONE"
```

Replace it with:

```bash
check "every assigned agent is an execution implementer" "$(not_implementers "$assignment")" "NONE"
check "the implementer check names every offending row and skips blank lines" \
  "$(not_implementers "$(printf '0 impl-sonnet-low\n\n1 judge-opus\n2\n3 impl-sonnet-medium\n')")" "1:judge-opus, 2:(no agent)"
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `timeout 600 bash plugins/dforge/tests/plan-revise.test.sh`
Expected: PASS (93 passed) — no assertion reads the Implementer line; the gap was stale fixtures.

Run: `timeout 600 bash plugins/dforge/tests/ladder.test.sh`
Expected: FAIL — `not_implementers: command not found`, so "every assigned agent is an execution implementer" and "the implementer check names every offending row and skips blank lines" both fail with an empty value.

- [ ] **Step 3: Implement**

Define the function just above its first use:

In `plugins/dforge/tests/ladder.test.sh`, find:

```bash
check "every assigned agent is an execution implementer" "$(not_implementers "$assignment")" "NONE"
```

Replace it with:

```bash
# not_implementers <rows> — "score:agent" for every row whose agent is not an
# execution implementer, comma-separated; NONE when there is none.
not_implementers() {
  local score agent list=""
  while read -r score agent; do
    [ -n "$score" ] || continue
    case " $IMPLEMENTERS " in *" $agent "*) ;; *) list="${list:+$list, }$score:${agent:-(no agent)}" ;; esac
  done <<< "$1"
  printf '%s\n' "${list:-NONE}"
}
check "every assigned agent is an execution implementer" "$(not_implementers "$assignment")" "NONE"
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `timeout 600 bash plugins/dforge/tests/ladder.test.sh`
Expected: PASS (28 passed).

Run: `timeout 600 bash plugins/dforge/tests/plan-revise.test.sh`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/tests/plan-revise.test.sh plugins/dforge/tests/ladder.test.sh
git commit -m "test(ladder): name every offender, fix fixtures"
```

---

### Task 16: Tighten the repository validator's name sweeps

**Files:**
- Modify: `scripts/validate-repository.mjs`
- Test: `tests/repository-layout.test.mjs`

**Interfaces:**
- Consumes: None
- Produces: None

**Items:** FS 4, DR 36, DR 37, DR 38

**Depends on:** none
**Implementer:** dr-superpowers:impl-sonnet-low
**Executor:** codex gpt-6.1-sol / low
**Evaluation:** files 1 - spec 0 - coupling 0 - risk 1 = 2

- [ ] **Step 1: Write the failing tests**

The tests prove that `my_forge_dir` is a retired forge name (DR 36), that a forge name under `plugins/dforge/LICENSES/` is allowed and the dcc sweep allows `docs/migration.md` and `docs/superpowers/` but nothing else (DR 37), that a binary file is not swept for names (DR 38), and that the schema rules for `unit`/`zero` on a boolean and `floor` with `min: 1` hold (FS 4).

DR 36, a new broken case after the "retired FORGE variable" case:

In `tests/repository-layout.test.mjs`, find:

```js
    ['retired FORGE variable', (c, dir) => { writeFileSync(resolve(dir, 'plugins/dforge/scripts/stray.sh'), 'echo "$FORGE_HOME"\n'); }, /plugins\/dforge\/scripts\/stray\.sh:1: retired dr-forge name/],
```

Replace it with:

```js
    ['retired FORGE variable', (c, dir) => { writeFileSync(resolve(dir, 'plugins/dforge/scripts/stray.sh'), 'echo "$FORGE_HOME"\n'); }, /plugins\/dforge\/scripts\/stray\.sh:1: retired dr-forge name/],
    ['retired _forge code name', (c, dir) => { writeFileSync(resolve(dir, 'plugins/dforge/scripts/stray.sh'), 'my_forge_dir=.\n'); }, /plugins\/dforge\/scripts\/stray\.sh:1: retired dr-forge name/],
```

DR 37, LICENSES in the forge allowlist test:

In `tests/repository-layout.test.mjs`, find:

```js
    for (const path of ['plugins/dforge/tests/stray.test.sh', 'plugins/dforge/scripts/lib/roots.sh']) {
      writeFileSync(resolve(dir, path), 'mkdir -p .forge\n');
    }
```

Replace it with:

```js
    for (const path of ['plugins/dforge/tests/stray.test.sh', 'plugins/dforge/scripts/lib/roots.sh', 'plugins/dforge/LICENSES/stray-LICENSE']) {
      writeFileSync(resolve(dir, path), 'mkdir -p .forge\n');
    }
```

DR 37 and DR 38, two new tests before the reference-check test:

In `tests/repository-layout.test.mjs`, find:

```js
test('reference check skips template placeholders and resolves agents', async () => {
```

Replace it with:

```js
test('the retired dcc- name is allowed only in the migration notes and historical documents', async () => {
  const { validateRepository } = await import('../scripts/validate-repository.mjs');
  const dir = mkdtempSync(resolve(tmpdir(), 'dr-catalog-'));
  try {
    for (const path of ['.claude-plugin', '.agents/plugins', ...json('.claude-plugin/marketplace.json').plugins.map(p => p.source)]) {
      cpSync(resolve(root, path), resolve(dir, path), { recursive: true });
    }
    mkdirSync(resolve(dir, 'docs/superpowers/plans'), { recursive: true });
    writeFileSync(resolve(dir, 'docs/migration.md'), 'install dcc-darkraise-ui\n');
    writeFileSync(resolve(dir, 'docs/superpowers/plans/old.md'), 'install dcc-darkraise-ui\n');
    const retired = () => validateRepository(dir).filter(error => error.includes('retired dcc- plugin name'));
    assert.deepEqual(retired(), []);
    writeFileSync(resolve(dir, 'docs/stray.md'), 'install dcc-darkraise-ui\n');
    assert.deepEqual(retired(), ['docs/stray.md:1: retired dcc- plugin name']);
  } finally { rmSync(dir, { recursive: true, force: true }); }
});

test('the name sweeps skip binary files', async () => {
  const { validateRepository } = await import('../scripts/validate-repository.mjs');
  const dir = mkdtempSync(resolve(tmpdir(), 'dr-catalog-'));
  try {
    for (const path of ['.claude-plugin', '.agents/plugins', ...json('.claude-plugin/marketplace.json').plugins.map(p => p.source)]) {
      cpSync(resolve(root, path), resolve(dir, path), { recursive: true });
    }
    const bytes = Buffer.from('\u0000superpowers dr-forge dcc-darkraise-ui\n', 'utf8');
    writeFileSync(resolve(dir, 'plugins/dforge/reference/image.bin'), bytes);
    writeFileSync(resolve(dir, 'plugins/dr-status/image.bin'), bytes);
    assert.deepEqual(validateRepository(dir), []);
  } finally { rmSync(dir, { recursive: true, force: true }); }
});

test('reference check skips template placeholders and resolves agents', async () => {
```

FS 4, at the end of the schema test, after the `floor: 50` assertion:

In `tests/repository-layout.test.mjs`, find:

```js
  assert.match(await broken(entry('floor: 50')), /schema n: floor must lie between 1 and max, on a number whose min is 0/);
```

Replace it with:

```js
  assert.match(await broken(entry('floor: 50')), /schema n: floor must lie between 1 and max, on a number whose min is 0/);
  assert.match(await broken(entry('floor: 5').replace('min: 0', 'min: 1').replace('default: 0', 'default: 5')), /schema n: floor must lie between 1 and max, on a number whose min is 0/);
  const flag = extra => `export default { b: { type: 'boolean', default: false, group: 'Cockpit', label: 'B', title: 't', description: 'd', target: 'dforge', ${extra} } }\n`;
  assert.equal(await broken(flag('')), '');
  assert.match(await broken(flag("unit: 'k'")), /schema b: unit must be one of k, %, s, min, on a number/);
  assert.match(await broken(flag("zero: 'off'")), /schema b: zero must be one of auto, off, any, hidden, unset, on a number/);
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `timeout 120 node --test tests/repository-layout.test.mjs`
Expected: FAIL — "retired _forge code name" (no error reported for `my_forge_dir=.`), its parent test "repository validator rejects broken distribution contracts", and "the name sweeps skip binary files" (four errors from the two `image.bin` files: retired superpowers, dr-forge and dcc- names). The dcc-exemption test, the LICENSES case and the FS 4 assertions pass already.

- [ ] **Step 3: Implement**

DR 38: a shared reader that returns null for a binary file (one holding a NUL byte):

In `scripts/validate-repository.mjs`, find:

```js
const contained = (root, path) => { const rel = relative(root, path); return rel !== '..' && !rel.startsWith(`..${process.platform === 'win32' ? '\\' : '/'}`) && !isAbsolute(rel); };
```

Replace it with:

```js
const contained = (root, path) => { const rel = relative(root, path); return rel !== '..' && !rel.startsWith(`..${process.platform === 'win32' ? '\\' : '/'}`) && !isAbsolute(rel); };
// A file's lines for the name sweeps, or null for a binary file (one holding a
// NUL byte), whose bytes are not text to read names in.
const textLines = path => {
  const bytes = readFileSync(path);
  return bytes.includes(0) ? null : bytes.toString('utf8').split('\n');
};
```

DR 38: one exemption pattern for both sweeps:

In `scripts/validate-repository.mjs`, find:

```js
  const superpowersExempt = rel => superpowersAllowed.has(rel) ||
    /^plugins\/dforge\/(?:LICENSES|tests)\//.test(rel) ||
```

Replace it with:

```js
  // Third-party licence texts and the test suites spell every retired name.
  const licensesOrTests = /^plugins\/dforge\/(?:LICENSES|tests)\//;
  const superpowersExempt = rel => superpowersAllowed.has(rel) ||
    licensesOrTests.test(rel) ||
```

DR 36: drop `_` from the lookbehind (keeping `d`, so `dforge` passes) and the `DR_FORGE` alternative, which `(?<!D)FORGE` already matches:

In `scripts/validate-repository.mjs`, find:

```js
  const retiredForge = /dr-forge|DR_FORGE|(?<!D)FORGE|(?<![A-Za-z0-9_d])forge(?![a-z])/;
```

Replace it with:

```js
  const retiredForge = /dr-forge|(?<!D)FORGE|(?<![A-Za-z0-9d])forge(?![a-z])/;
```

In `scripts/validate-repository.mjs`, find:

```js
  const forgeExempt = rel => forgeAllowed.has(rel) || /^plugins\/dforge\/(?:LICENSES|tests)\//.test(rel);
```

Replace it with:

```js
  const forgeExempt = rel => forgeAllowed.has(rel) || licensesOrTests.test(rel);
```

DR 38: skip binary files before splitting lines, in the plugin sweep and the dcc sweep:

In `scripts/validate-repository.mjs`, find:

```js
        const checksForge = name === 'dforge' && !forgeExempt(rel);
        readFileSync(path, 'utf8').split('\n').forEach((line, index) => {
```

Replace it with:

```js
        const checksForge = name === 'dforge' && !forgeExempt(rel);
        const lines = textLines(path);
        if (!lines) continue;
        lines.forEach((line, index) => {
```

In `scripts/validate-repository.mjs`, find:

```js
      if (!item.isFile() || dccAllowed.has(rel)) continue;
      readFileSync(path, 'utf8').split('\n').forEach((line, index) => {
```

Replace it with:

```js
      if (!item.isFile() || dccAllowed.has(rel)) continue;
      (textLines(path) ?? []).forEach((line, index) => {
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `timeout 120 node --test tests/repository-layout.test.mjs`
Expected: PASS (34 tests).

Run: `timeout 120 node scripts/validate-repository.mjs`
Expected: `Repository catalogs, manifests, versions, bundled links and the settings schema are valid.`

- [ ] **Step 5: Commit**

```bash
git add scripts/validate-repository.mjs tests/repository-layout.test.mjs
git commit -m "fix(validate): tighten the retired-name sweeps"
```

---

### Task 17: Align the CI CLI pin and drop the dependency smoke

**Files:**
- Modify: `.github/workflows/validate.yml`
- Modify: `tests/marketplace-smoke.ps1`
- Modify: `docs/testing/dual-client-marketplace-validation.md`
- Test: `plugins/dforge/tests/review-route.test.sh`

**Interfaces:**
- Consumes: None
- Produces: None

**Items:** DF 14, DF 15, DF 18, DM 32

**Depends on:** none
**Implementer:** dr-superpowers:impl-sonnet-medium
**Executor:** codex gpt-6.1-sol / medium
**Evaluation:** files 2 - spec 0 - coupling 0 - risk 1 = 3

- [ ] **Step 1: Verify the current text and write the version test**

The workflow, smoke script and doc are text edits with no runnable test on this host (no PowerShell; CI runs only after a push). Confirm the old text:

```bash
grep -n '2.1.263' .github/workflows/validate.yml
grep -n 'claude-plugins-official' tests/marketplace-smoke.ps1
grep -n -i 'superpowers' docs/testing/dual-client-marketplace-validation.md
grep -n '4.1.0' plugins/dforge/tests/review-route.test.sh
```

Expected: lines 28 and 30 of the workflow; two smoke lines (the marketplace add and the `superpowers@claude-plugins-official` check); doc lines 14, 15, 23 and 25 (line 14 is the `.superpowers` fixture workspace, which stays); two review-route lines.

DM 32: read the expected version from the Claude manifest instead of pinning 4.1.0, so the release bump in P8 needs no edit here:

In `plugins/dforge/tests/review-route.test.sh`, find:

```bash
present "the Claude manifest is 4.1.0" "$P/.claude-plugin/plugin.json" '"version": "4.1.0"'
present "the Codex manifest is 4.1.0" "$P/.codex-plugin/plugin.json" '"version": "4.1.0"'
```

Replace it with:

```bash
# The version is read from the Claude manifest, so a release bump needs no edit here.
version=$(sed -nE 's/^[[:space:]]*"version": "([^"]+)".*/\1/p' "$P/.claude-plugin/plugin.json" | head -n 1)
check "the Claude manifest names a release version" "$([[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] && echo yes || echo no)" "yes"
present "the Codex manifest carries the Claude manifest's version" "$P/.codex-plugin/plugin.json" "\"version\": \"$version\""
```

- [ ] **Step 2: Run the version test**

Run: `timeout 600 bash plugins/dforge/tests/review-route.test.sh`
Expected: PASS — both manifests read 4.1.0 today; the gap was the pin. (In scratch, changing only the Codex manifest's version made "the Codex manifest carries the Claude manifest's version" fail, so the check still catches a mismatch.)

- [ ] **Step 3: Implement**

DF 14: run every `plugin validate` step on the dforge step's CLI version:

In `.github/workflows/validate.yml`, find:

```yaml
          timeout 90s npx --yes @anthropic-ai/claude-code@2.1.263 plugin validate .
          for plugin in dr-status darkraise-ui darkraise-win32ui; do
            timeout 30s npx --yes @anthropic-ai/claude-code@2.1.263 plugin validate "plugins/$plugin"
          done

      # Mods (hooks modules) need a newer CLI than the pinned validator above.
      - name: Validate and test dforge
```

Replace it with:

```yaml
          timeout 90s npx --yes @anthropic-ai/claude-code@2.1.295 plugin validate .
          for plugin in dr-status darkraise-ui darkraise-win32ui; do
            timeout 30s npx --yes @anthropic-ai/claude-code@2.1.295 plugin validate "plugins/$plugin"
          done

      # One CLI version for every validate step: dforge's mod (hooks modules)
      # needs 2.1.295, and the marketplace step reads dforge too.
      - name: Validate and test dforge
```

DF 15: drop the official marketplace add and the dependency check from the smoke script (dforge declares no dependency; the repository validator forbids one):

In `tests/marketplace-smoke.ps1`, find:

```powershell
  Invoke-Client $Claude @('plugin','marketplace','add','https://github.com/anthropics/claude-plugins-official.git') | Out-Null
  Invoke-Client $Claude @('plugin','marketplace','add',$market) | Out-Null
```

Replace it with:

```powershell
  Invoke-Client $Claude @('plugin','marketplace','add',$market) | Out-Null
```

In `tests/marketplace-smoke.ps1`, find:

```powershell
  Check ($ownEntries.Count -eq 4) 'Claude installs four repository plugins'
  Check (@($claudeList | Where-Object { $_.id -eq 'superpowers@claude-plugins-official' }).Count -eq 1) 'Claude resolves the declared cross-marketplace dependency'
```

Replace it with:

```powershell
  Check ($ownEntries.Count -eq 4) 'Claude installs four repository plugins'
```

DF 15: drop the doc's download sentence:

In `docs/testing/dual-client-marketplace-validation.md`, find:

```markdown
under the ignored `.superpowers` workspace and are removed after the run.
The harness downloads the actual official Claude marketplace and Superpowers
dependency over HTTPS; no paid model or Telegram calls are made.
```

Replace it with:

```markdown
under the ignored `.superpowers` workspace and are removed after the run.
No paid model or Telegram calls are made.
```

DF 18 (doc half) and DF 15: the manifest is dforge's, and the dependency half of the bullet goes:

In `docs/testing/dual-client-marketplace-validation.md`, find:

```markdown
- All three Codex plugins install; installed native manifest bytes match source.
  Superpowers' native manifest explicitly contains `"hooks": {}`.
- Claude installs all four repository plugins and resolves the declared
  `superpowers@claude-plugins-official` dependency. Dependency entries are counted
  separately from the four repository plugins.
```

Replace it with:

```markdown
- All three Codex plugins install; installed native manifest bytes match source.
  dforge's native manifest explicitly contains `"hooks": {}`.
- Claude installs all four repository plugins.
```

- [ ] **Step 4: Verify the new text**

```bash
grep -c '2.1.263' .github/workflows/validate.yml
grep -c '@anthropic-ai/claude-code@2.1.295' .github/workflows/validate.yml
grep -c 'claude-plugins-official' tests/marketplace-smoke.ps1
grep -c "dforge's native manifest" docs/testing/dual-client-marketplace-validation.md
grep -c 'superpowers@claude-plugins-official' docs/testing/dual-client-marketplace-validation.md
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/validate.yml'))"
```

Expected, in order: `0`, `4`, `0`, `1`, `0`, and no output from the YAML parse.

Run: `timeout 600 bash plugins/dforge/tests/review-route.test.sh`
Expected: PASS.

Run: `timeout 120 node scripts/validate-repository.mjs`
Expected: valid (the doc and smoke script are outside its sweeps, which this confirms).

- [ ] **Step 5: Commit**

```bash
git add .github/workflows/validate.yml tests/marketplace-smoke.ps1 docs/testing/dual-client-marketplace-validation.md plugins/dforge/tests/review-route.test.sh
git commit -m "chore(ci): align CLI pin and drop dependency check"
```

---

### Task 18: Count failed Bash ledger writes and widen script paths

**Files:**
- Modify: `evals/controller/lib/transcript.mjs`
- Modify: `evals/controller/lib/sessions.mjs`
- Test: `evals/controller/tests/transcript.test.mjs`
- Test: `evals/controller/tests/pilot.test.mjs`
- Test: `evals/tiers/tests/cases.test.mjs`

**Interfaces:**
- Consumes: None
- Produces: None

**Items:** RO 27, RO 28, DR 6

**Depends on:** none
**Implementer:** dr-superpowers:impl-sonnet-medium
**Executor:** codex gpt-6.1-sol / medium
**Evaluation:** files 2 - spec 0 - coupling 0 - risk 1 = 3

- [ ] **Step 1: Write the failing tests**

The tests prove that a ledger line a Bash call appended before a failing command counts while a failed Write does not (RO 27), that a session running a per-task script through a variable path (`$S/task-brief`) is found, that `pilot-report` reaches the `unpriced` status for a subagent on an unlisted model (RO 28), and that the slug drops a `dforge-` prefix (DR 6).

RO 27, after the "a ledger check that only redirects stderr, and a write that failed, are not completions" test:

In `evals/controller/tests/transcript.test.mjs`, find:

```js
    { type: 'user', message: { content: [{ type: 'tool_result', tool_use_id: 'e1', is_error: true, content: 'String to replace not found' }] } },
  ]));
  assert.deepEqual(m.completed, ['2', '3', '4', '5']);
});
```

Replace it with:

```js
    { type: 'user', message: { content: [{ type: 'tool_result', tool_use_id: 'e1', is_error: true, content: 'String to replace not found' }] } },
  ]));
  assert.deepEqual(m.completed, ['2', '3', '4', '5']);
});

test('a Bash call that fails after writing the ledger still wrote it; a failed Write did not', () => {
  const ledger = '/w/.dforge/sdd/p/progress.md';
  const m = measureTranscript(jsonl([
    said('msg_a', 'claude-sonnet-5-5', usage(1, 1), [
      use('b1', 'Bash', { command: "echo 'Task 1: complete (commits a..b)' >> .dforge/sdd/p/progress.md; false" }),
      use('w1', 'Write', { file_path: ledger, content: 'Task 2: complete (commits c..d)\n' }),
    ]),
    { type: 'user', message: { content: [{ type: 'tool_result', tool_use_id: 'b1', is_error: true, content: 'Exit code 1' }] } },
    { type: 'user', message: { content: [{ type: 'tool_result', tool_use_id: 'w1', is_error: true, content: 'EACCES: permission denied' }] } },
  ]));
  assert.deepEqual(m.completed, ['1']);
});
```

RO 28 fixtures: two sessions and their plan files, written before the fixture repository's commit:

In `evals/controller/tests/pilot.test.mjs`, find:

```js
for (const slug of ['one', 'two', 'three', 'four', 'five', 'six']) write(join(repo, `docs/plans/2026-10-18-${slug}.md`), PLAN_TEXT);
```

Replace it with:

```js
// Ten ran its per-task script through a variable holding the scripts directory.
write(join(folder, 'ten.jsonl'), session(['2026-10-18-ten'], SONNET, 'high', [1, 2]).replace('bash /p/scripts/task-brief', 'S=/p/scripts; bash $S/task-brief'));
// Eleven's subagent ran on a model the price table does not list.
write(join(folder, 'eleven.jsonl'), session(['2026-10-18-eleven'], SONNET, 'high', [1, 2]));
write(join(folder, 'eleven/subagents/agent-1.jsonl'), `${JSON.stringify(said('h1', 'claude-haiku-5-5', 'high', []))}\n`);
for (const slug of ['one', 'two', 'three', 'four', 'five', 'six', 'ten', 'eleven']) write(join(repo, `docs/plans/2026-10-18-${slug}.md`), PLAN_TEXT);
```

RO 28 tests, before the arm-refusal test:

In `evals/controller/tests/pilot.test.mjs`, find:

```js
test('pilot-report refuses an arm the pilot does not run', () => {
```

Replace it with:

```js
test('pilot-report finds a session that runs a per-task script by any path', () => {
  const r = report(['docs/plans/2026-10-18-ten.md\tapp\tsonnet@high\t-']);
  assert.equal(r.status, 0, r.stderr);
  assert.deepEqual(r.stdout.trim().split('\n')[1].split('\t').slice(0, 5), ['2026-10-18-ten', 'sonnet@high', 'ok', 'yes', '1']);
});

test('pilot-report marks a plan unpriced when a model it ran on has no price', () => {
  const r = report(['docs/plans/2026-10-18-eleven.md\tapp\tsonnet@high\t-']);
  assert.equal(r.status, 0, r.stderr);
  const row = r.stdout.trim().split('\n')[1].split('\t');
  assert.deepEqual([row[0], row[2], row.at(-1)], ['2026-10-18-eleven', 'unpriced', 'claude-haiku-5-5']);
  assert.match(r.stdout, /0 of 1 plans usable/);
});

test('pilot-report refuses an arm the pilot does not run', () => {
```

DR 6:

In `evals/tiers/tests/cases.test.mjs`, find:

```js
    [slug('docs/superpowers/plans/2026-09-15-dr-superpowers-review-routing.md'), slug('docs/dforge/plans/2026-11-01-dr-forge-settings.md'), slug(PLAN)],
    ['review-routing', 'settings', 'fixture'],
```

Replace it with:

```js
    [slug('docs/superpowers/plans/2026-09-15-dr-superpowers-review-routing.md'), slug('docs/dforge/plans/2026-11-01-dr-forge-settings.md'), slug('docs/dforge/plans/2026-11-02-dforge-cockpit.md'), slug(PLAN)],
    ['review-routing', 'settings', 'cockpit', 'fixture'],
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `timeout 300 node --test evals/controller/tests/transcript.test.mjs evals/controller/tests/pilot.test.mjs evals/tiers/tests/cases.test.mjs`
Expected: FAIL — "a Bash call that fails after writing the ledger still wrote it; a failed Write did not" (completed is `[]`, expected `['1']`), and "pilot-report finds a session that runs a per-task script by any path" (row `2026-10-18-ten, sonnet@high, no-sessions, no, 0`). The unpriced test and the slug test pass already (coverage).

- [ ] **Step 3: Implement**

RO 27:

In `evals/controller/lib/transcript.mjs`, find:

```js
    // A write that failed (an Edit whose old string was not found) recorded nothing.
    if (!failed.has(use.id)) for (const hit of ledgerText(use).matchAll(COMPLETE)) completed.push(hit[1]);
```

Replace it with:

```js
    // A write that failed (an Edit whose old string was not found) recorded
    // nothing. A Bash call's error is its last command's exit status, so a
    // ledger line it appended before a failing command was still written.
    if (use.name === 'Bash' || !failed.has(use.id)) for (const hit of ledgerText(use).matchAll(COMPLETE)) completed.push(hit[1]);
```

RO 28: require a path separator before the script name instead of a literal `scripts/`:

In `evals/controller/lib/sessions.mjs`, find:

```js
// Every per-task script takes the plan as its first argument, often as a
// variable the same command assigned (PLAN=docs/…/x.md … task-brief "$PLAN").
// The scripts/ prefix keeps a search for the script name (rg task-brief …) from
// counting as running it, and the optional quote admits a quoted script path.
const PER_TASK = /scripts\/(?:task-brief|review-route|review-package)['"]?[ \t]+(['"]?[^\s;&|]+)/g;
```

Replace it with:

```js
// Every per-task script takes the plan as its first argument, often as a
// variable the same command assigned (PLAN=docs/…/x.md … task-brief "$PLAN").
// The script is run by a path (scripts/task-brief, $S/task-brief), so the
// required slash keeps a search for the bare name (rg task-brief …) from
// counting as running it, and the optional quote admits a quoted script path.
const PER_TASK = /\/(?:task-brief|review-route|review-package)['"]?[ \t]+(['"]?[^\s;&|]+)/g;
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `timeout 300 node --test evals/controller/tests/transcript.test.mjs evals/controller/tests/pilot.test.mjs evals/tiers/tests/cases.test.mjs`
Expected: PASS.

Run: `timeout 300 node --test evals/controller/tests/sessions.test.mjs evals/controller/tests/decide.test.mjs`
Expected: PASS (`planSlugs` still ignores `rg task-brief …`).

- [ ] **Step 5: Commit**

```bash
git add evals/controller/lib/transcript.mjs evals/controller/lib/sessions.mjs evals/controller/tests/transcript.test.mjs evals/controller/tests/pilot.test.mjs evals/tiers/tests/cases.test.mjs
git commit -m "fix(evals): count failed Bash ledger writes"
```

---

### Task 19: Resolve submodules and linked darkmem config keys

**Files:**
- Modify: `plugins/dforge/scripts/lib/darkmem-config.mjs`
- Test: `plugins/dforge/tests/darkmem-sync/config.test.mjs`
- Test: `plugins/dforge/tests/roots.test.sh`

**Interfaces:**
- Consumes: None
- Produces: `primaryRoot(cwd)` (same signature) now answers a submodule's own top level and, on git before 2.31, the checkout's top level, instead of null

**Items:** DM 9, DM 38

**Depends on:** none
**Implementer:** dr-superpowers:impl-sonnet-medium
**Evaluation:** files 1 - spec 0 - coupling 0 - risk 2 = 3

- [ ] **Step 1: Write the failing tests**

The tests prove that a submodule resolves its own darkmem mapping, that a mapping and a stores record keyed by a symbolic-linked path find the repository, and that `--mode ""` is a usage error. Two roots.test.sh changes cover the rest of DM 38: the unused `MIRROR=` assignments go, and a no-node `dforge_project` case is added (coverage only; it passes today).

In `plugins/dforge/tests/darkmem-sync/config.test.mjs`, replace the whole existing submodule test:

```js
test("--mode in a submodule falls back to the worktree for latest.md", () => {
  const outer = makeRepo();
  const inner = makeRepo();
  git(outer, "-c", "protocol.file.allow=always", "submodule", "add", "-q", inner, "sub");
  const sub = path.join(outer, "sub");
  const result = spawnSync(process.execPath, [MODULE, "--mode"], { cwd: sub, env: makeHome({ repo: sub }).env, encoding: "utf8", timeout: 10000 });
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.stdout.split("\n")[1].split("\t")[3], path.join(sub, ".dforge", "handoff", "latest.md"));
});
```

with:

```js
test("a submodule is its own repository: mapped by its top level, latest.md in its own checkout", () => {
  const outer = makeRepo();
  const inner = makeRepo();
  git(outer, "-c", "protocol.file.allow=always", "submodule", "add", "-q", inner, "sub");
  const sub = path.join(outer, "sub");
  const { env } = makeHome({ repo: sub, stores: { documents: "local", progress: "local" } });
  const result = spawnSync(process.execPath, [MODULE, "--mode"], { cwd: sub, env, encoding: "utf8", timeout: 10000 });
  assert.equal(result.status, 0, result.stderr);
  const lines = result.stdout.split("\n");
  assert.equal(lines[1].split("\t")[3], path.join(sub, ".dforge", "handoff", "latest.md"));
  assert.equal(lines[2], "project\tproj", "the submodule's mapping is found");
  assert.equal(resolveStores({ cwd: sub, env }).repoRoot, sub);
});

test("a mapping and a record keyed by a symbolic-linked path name the same repository", () => {
  const repo = makeRepo();
  const link = path.join(scratch("dms-link-"), "repo");
  fs.symlinkSync(repo, link, "dir");
  const { env, mirror } = makeHome({ repo: link });
  const stores = resolveStores({ cwd: repo, env });
  assert.equal(stores.reason, "project proj");
  assert.deepEqual(applied(stores), ["darkmem", "darkmem"]);
  assert.equal(stores.documents.root, path.join(mirror, "dforge"));
});
```

In the same file, in the test `"--mode DIR resolves that checkout from anywhere; an unmapped one prints no project line"`, replace its last assertion and closing line:

```js
  assert.equal(extra.stderr, "usage: darkmem-config.mjs --mode [DIR]\n");
});
```

with:

```js
  assert.equal(extra.stderr, "usage: darkmem-config.mjs --mode [DIR]\n");
  const empty = mode(elsewhere, ["--mode", ""]);
  assert.equal(empty.status, 2, "an empty DIR is a usage error, not the working directory");
  assert.equal(empty.stderr, "usage: darkmem-config.mjs --mode [DIR]\n");
});
```

In `plugins/dforge/tests/roots.test.sh`, three `MIRROR=$(stores_home …)` assignments are never read. Keep each call, since it writes the config, and drop the assignment. Replace:

```bash
printf 'x\n' > "$WT/.dforge/sdd/b/progress.md"
MIRROR=$(stores_home "$HOME" "$REPO" superpowers local local)
```

with:

```bash
printf 'x\n' > "$WT/.dforge/sdd/b/progress.md"
stores_home "$HOME" "$REPO" superpowers local local > /dev/null
```

Replace:

```bash
MIRROR=$(stores_home "$HOME" "$REPO" superpowers local local)
mkdir -p "$WT/docs/dforge/plans"
```

with:

```bash
stores_home "$HOME" "$REPO" superpowers local local > /dev/null
mkdir -p "$WT/docs/dforge/plans"
```

Replace:

```bash
FP="$HERE/../scripts/dforge-path"
MIRROR=$(stores_home "$HOME" "$REPO" superpowers local local)
```

with:

```bash
FP="$HERE/../scripts/dforge-path"
stores_home "$HOME" "$REPO" superpowers local local > /dev/null
```

(Leave `MIRROR=$(stores_home "$HOME" "$REPO" superpowers local darkmem)` and the one inside the four-combination loop alone: both are read.)

Then add the no-node case. Replace:

```bash
check "project: dforge-path takes no argument" "$?" "2"
```

with:

```bash
check "project: dforge-path takes no argument" "$?" "2"
NB="$TMP/nonode-bin"
mkdir -p "$NB"
for c in git dirname; do ln -s "$(type -P "$c")" "$NB/$c"; done
(cd "$WT" && PATH="$NB" dforge_project > "$TMP/project-out")
check "project: without node is status 1" "$?" "1"
check "project: without node prints nothing" "$(cat "$TMP/project-out")" ""
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `timeout 300 node --test plugins/dforge/tests/darkmem-sync/config.test.mjs`
Expected: FAIL, 3 tests:
- `a submodule is its own repository…`: `lines[2]` is `''`, not `'project\tproj'`. `primaryRoot` runs `--show-toplevel` in `.git/modules`, which has no work tree, so the submodule reads as "not inside a git repository".
- `a mapping and a record keyed by a symbolic-linked path…`: the reason is `no darkmem mapping for /tmp/dms-repo-…`, because `samePath` compares unresolved paths.
- `--mode DIR resolves that checkout…`: the empty DIR exits 3 (it resolved to the non-repository working directory), not 2.

Run: `timeout 600 bash plugins/dforge/tests/roots.test.sh`
Expected: PASS. The no-node case closes a coverage gap, and dropping the assignments changes nothing.

- [ ] **Step 3: Implement**

In `plugins/dforge/scripts/lib/darkmem-config.mjs`, replace:

```js
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
```

with:

```js
// The primary checkout's top level, so every worktree of one repository shares
// one mapping and one mirror. A submodule's common directory lies under its
// superproject's .git/modules/, which has no work tree, and git before 2.31
// does not answer --path-format with an absolute path: both fall back to the
// checkout's own top level, so a submodule is a repository of its own.
export function primaryRoot(cwd) {
  const common = git(cwd, ["rev-parse", "--path-format=absolute", "--git-common-dir"]);
  const primary = common && path.isAbsolute(common) ? git(path.dirname(common), ["rev-parse", "--show-toplevel"]) : null;
  return primary ?? git(cwd, ["rev-parse", "--show-toplevel"]);
}

// A configured key may name the checkout through a symbolic link, and may name
// a directory that no longer exists, which compares as written.
function realOrResolved(file) {
  try {
    return fs.realpathSync.native(file);
  } catch {
    return path.resolve(file);
  }
}

function samePath(a, b) {
  const x = realOrResolved(a);
  const y = realOrResolved(b);
  return process.platform === "win32" ? x.toLowerCase() === y.toLowerCase() : x === y;
}
```

In the same file, in the `isMain()` block at the bottom, replace:

```js
  if (flag !== "--mode" || extra.length) {
```

with:

```js
  if (flag !== "--mode" || dir === "" || extra.length) {
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `timeout 300 node --test plugins/dforge/tests/darkmem-sync/config.test.mjs`
Expected: PASS (22 tests)

Run: `timeout 600 bash plugins/dforge/tests/roots.test.sh`
Expected: PASS

Other suites this can break, since every darkmem-sync command and `roots.sh` resolve through `primaryRoot` and `samePath`:
- `timeout 600 bash plugins/dforge/tests/darkmem-sync.test.sh`
- `timeout 600 bash plugins/dforge/tests/plan-lib.test.sh`
- `timeout 300 /root/.local/bin/claude plugin test plugins/dforge` (the cockpit calls `darkmem-config.mjs --mode DIR`)

All are expected to PASS.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/scripts/lib/darkmem-config.mjs plugins/dforge/tests/darkmem-sync/config.test.mjs plugins/dforge/tests/roots.test.sh
git commit -m "fix(darkmem): map submodules and linked keys"
```

---

### Task 20: Load a per-workstream checkpointAt

**Files:**
- Modify: `plugins/dforge/scripts/lib/darkmem-mirror.mjs`
- Test: `plugins/dforge/tests/darkmem-sync/mirror.test.mjs`

**Interfaces:**
- Consumes: None
- Produces: exports from `plugins/dforge/scripts/lib/darkmem-mirror.mjs`:
  - `checkpointAtOf(state, workstream)`: string or null, this workstream's last synced checkpoint `created_at`, falling back to an old single value
  - `newestCheckpointAt(state)`: string or null, the newest value across all workstreams
  - `recordCheckpointAt(state, workstream, at)`: sets `state.checkpointAt[workstream] = at`, converting an old single value into the `"*"` entry
  - `loadState` accepts `checkpointAt` as null, a date string (old shape), or a prototype-free object of workstream key (or `"*"`) to date string

**Items:** DM 12 (state half)

**Depends on:** none
**Implementer:** dr-superpowers:impl-sonnet-medium
**Evaluation:** files 1 - spec 0 - coupling 0 - risk 2 = 3

- [ ] **Step 1: Write the failing tests**

The tests prove that an old single `checkpointAt` stands for every workstream until that workstream is written, that the per-workstream record survives a save and load, and that malformed records are refused.

In `plugins/dforge/tests/darkmem-sync/mirror.test.mjs`, extend the import from `darkmem-mirror.mjs`. Replace:

```js
  utcStamp, utf8Fault,
} from "../../scripts/lib/darkmem-mirror.mjs";
```

with:

```js
  utcStamp, utf8Fault, checkpointAtOf, newestCheckpointAt, recordCheckpointAt,
} from "../../scripts/lib/darkmem-mirror.mjs";
```

In the same file, at the end of the test `"an unreadable or malformed state file is an error rather than a fresh start"`, replace:

```js
    JSON.stringify({ ...good, pendingLinks: [1] }),
  ]) {
    fs.writeFileSync(file, bad);
    assert.throws(() => loadState(file), StateError, bad);
  }
});
```

with:

```js
    JSON.stringify({ ...good, pendingLinks: [1] }),
    JSON.stringify({ ...good, checkpointAt: 5 }),
    JSON.stringify({ ...good, checkpointAt: { "../x": "2026-09-24T10:00:00.000Z" } }),
    JSON.stringify({ ...good, checkpointAt: { p1: "not a date" } }),
  ]) {
    fs.writeFileSync(file, bad);
    assert.throws(() => loadState(file), StateError, bad);
  }
});

test("checkpointAt is kept per workstream; an old single value stands for every workstream until each is written", () => {
  const { root } = mirror();
  const file = path.join(root, ".sync-state.json");
  const old = "2026-09-24T10:00:00.000Z";
  const later = "2026-09-25T10:00:00.000001+00:00";
  fs.writeFileSync(file, JSON.stringify({ version: 1, documents: {}, ledgers: {}, checkpoint: null, checkpointAt: old, conflicts: [] }));
  const state = loadState(file);
  assert.equal(checkpointAtOf(state, "p1"), old);
  recordCheckpointAt(state, "p1", later);
  assert.equal(checkpointAtOf(state, "p1"), later);
  assert.equal(checkpointAtOf(state, "p2"), old, "a workstream not yet written keeps the old value");
  assert.equal(newestCheckpointAt(state), later);
  saveState(file, state);
  const loaded = loadState(file);
  assert.equal(checkpointAtOf(loaded, "p1"), later);
  assert.equal(checkpointAtOf(loaded, "p2"), old);
  assert.equal(newestCheckpointAt(loaded), later);
  const fresh = emptyState();
  assert.equal(checkpointAtOf(fresh, "p1"), null);
  assert.equal(newestCheckpointAt(fresh), null);
  recordCheckpointAt(fresh, "constructor", old);
  assert.equal(checkpointAtOf(fresh, "toString"), null, "the per-workstream record has no prototype");
  assert.equal(checkpointAtOf(fresh, "constructor"), old);
});
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `timeout 300 node --test plugins/dforge/tests/darkmem-sync/mirror.test.mjs`
Expected: FAIL. The module fails to load with `SyntaxError: The requested module '../../scripts/lib/darkmem-mirror.mjs' does not provide an export named 'checkpointAtOf'`.

- [ ] **Step 3: Implement**

In `plugins/dforge/scripts/lib/darkmem-mirror.mjs`, insert the helpers above `loadState`. Replace:

```js
// A missing state file is a fresh mirror. An unreadable or malformed one is an
// error, not a fresh start: forgetting a ledger's offset would re-send lines.
```

with:

```js
// checkpointAt is darkmem's created_at of the last checkpoint this mirror
// synced, per workstream key, so a push's duplicate lookup starts from its own
// workstream's. A state file written before holds one value (a string, or
// null); it stands for every workstream until that one is next written, kept
// under "*", which no workstream key can spell.
const EVERY_WORKSTREAM = "*";
const isStamp = value => typeof value === "string" && !Number.isNaN(Date.parse(value));

// The loaded checkpointAt, or undefined when it is malformed.
function checkpointAtRecord(value) {
  if (value === null || isStamp(value)) return value;
  return dictOf(value, (key, at) => (key === EVERY_WORKSTREAM || validKey(key)) && isStamp(at)) ?? undefined;
}

export function checkpointAtOf(state, workstream) {
  const held = state.checkpointAt;
  if (held === null || typeof held === "string") return held;
  return held[workstream] ?? held[EVERY_WORKSTREAM] ?? null;
}

// The newest checkpoint this mirror synced in any workstream: latest.md is the
// most recent stop, so a pull replaces it only with a newer one.
export function newestCheckpointAt(state) {
  const held = state.checkpointAt;
  if (held === null || typeof held === "string") return held;
  let newest = null;
  for (const at of Object.values(held)) if (newest === null || isoMicros(at) > isoMicros(newest)) newest = at;
  return newest;
}

export function recordCheckpointAt(state, workstream, at) {
  const held = state.checkpointAt;
  const record = held !== null && typeof held === "object" ? held : Object.create(null);
  if (typeof held === "string") record[EVERY_WORKSTREAM] = held;
  record[workstream] = at;
  state.checkpointAt = record;
}

// A missing state file is a fresh mirror. An unreadable or malformed one is an
// error, not a fresh start: forgetting a ledger's offset would re-send lines.
```

In `loadState`, replace:

```js
  const ledgers = dictOf(raw?.ledgers, isLedgerRecord);
  const valid = raw?.version === 1 && documents && ledgers
    && (raw.checkpoint === null || isHash(raw.checkpoint))
    && (raw.checkpointAt === null || (typeof raw.checkpointAt === "string" && !Number.isNaN(Date.parse(raw.checkpointAt))))
```

with:

```js
  const ledgers = dictOf(raw?.ledgers, isLedgerRecord);
  const checkpointAt = checkpointAtRecord(raw?.checkpointAt);
  const valid = raw?.version === 1 && documents && ledgers
    && (raw.checkpoint === null || isHash(raw.checkpoint))
    && checkpointAt !== undefined
```

In the same function, replace:

```js
    version: 1, documents, ledgers, checkpoint: raw.checkpoint, checkpointAt: raw.checkpointAt, conflicts: raw.conflicts,
```

with:

```js
    version: 1, documents, ledgers, checkpoint: raw.checkpoint, checkpointAt, conflicts: raw.conflicts,
```

Leave `emptyState()` as it is (`checkpointAt: null`).

- [ ] **Step 4: Run the tests to verify they pass**

Run: `timeout 300 node --test plugins/dforge/tests/darkmem-sync/mirror.test.mjs`
Expected: PASS

Run: `timeout 600 bash plugins/dforge/tests/darkmem-sync.test.sh`
Expected: PASS. Every suite still writes and reads the old shape, including `migrate.test.mjs`'s fixtures, which are not edited.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/scripts/lib/darkmem-mirror.mjs plugins/dforge/tests/darkmem-sync/mirror.test.mjs
git commit -m "fix(darkmem): load per-workstream checkpointAt"
```

---

### Task 21: Key trailing slashes and keep mirror plans local

**Files:**
- Modify: `plugins/dforge/scripts/lib/roots.sh`
- Modify: `plugins/dforge/scripts/lib/plan.sh`
- Test: `plugins/dforge/tests/roots.test.sh`
- Test: `plugins/dforge/tests/next-step.test.sh`
- Test: `plugins/dforge/tests/plan-lib.test.sh`

**Interfaces:**
- Consumes: Task 19's `primaryRoot` fallback (a submodule resolves; no code call)
- Produces: None

**Items:** DM 22, DM 33, DR 32

**Depends on:** Task 19
**Implementer:** dr-superpowers:impl-sonnet-high
**Evaluation:** files 2 - spec 0 - coupling 1 - risk 2 = 5

- [ ] **Step 1: Write the failing tests**

The tests prove five things. `dforge_name_key` and `dforge_name_spellings` drop a trailing slash. A bare `dforge_resolve docs/forge` resolves to the docs root (DR 32, coverage). A relative file given to `dforge_name` with a DIR is a path from the working directory (DM 22, pins today's behaviour). A docs/forge Assigned cell matches a docs/superpowers completed.md entry (DM 33, coverage). And `plan_ledger` keeps a mirror plan with its working checkout when the home directory is a git repository, and exits 2 on a ConfigError (DM 22).

In `plugins/dforge/tests/roots.test.sh`, replace:

```bash
check "a 3.x citation resolves to the file" "$(cd "$WT" && cat "$(dforge_resolve docs/forge/plans/p.md)")" "p"
```

with:

```bash
check "a 3.x citation resolves to the file" "$(cd "$WT" && cat "$(dforge_resolve docs/forge/plans/p.md)")" "p"
check "a bare 3.x docs directory resolves to the docs root" "$(cd "$WT" && dforge_resolve docs/forge)" "$WT/docs/dforge"
check "DIR: a relative file is a path from the working directory" \
  "$(cd "$WT/docs/dforge" && dforge_name plans/p.md plans)" "docs/dforge/plans/p.md"
```

Replace:

```bash
check "name key: a bare docs/superpowers" "$(dforge_name_key docs/superpowers)" "docs/dforge"
```

with:

```bash
check "name key: a bare docs/superpowers" "$(dforge_name_key docs/superpowers)" "docs/dforge"
check "name key: a trailing slash" "$(dforge_name_key docs/superpowers/)" "docs/dforge"
check "name key: a trailing slash after a name" "$(dforge_name_key docs/forge/plans/)" "docs/dforge/plans"
```

Replace (the second line of the `"name spellings: the docs directory itself"` check):

```bash
  "$(dforge_name_spellings ./docs/dforge | tr '\n' '|')" "docs/dforge|docs/forge|docs/superpowers|"
```

with:

```bash
  "$(dforge_name_spellings ./docs/dforge | tr '\n' '|')" "docs/dforge|docs/forge|docs/superpowers|"
check "name spellings: a trailing slash" \
  "$(dforge_name_spellings docs/forge/ | tr '\n' '|')" "docs/dforge|docs/forge|docs/superpowers|"
```

In `plugins/dforge/tests/next-step.test.sh`, after the block that restores completed.md and row 1 following the `"routing: either prefix names a finished plan"` check, replace:

```bash
printf '# Completed plans\n\n- 2026-01-01 `docs/superpowers/plans/inc1.md` — merged into `main` at abc1234\n' \
  > "$GREPO/docs/dforge/plans/completed.md"
bash "$HERE/../scripts/register" set "$GREG" 1 doing --assigned docs/superpowers/plans/inc2.md >/dev/null
```

with:

```bash
printf '# Completed plans\n\n- 2026-01-01 `docs/superpowers/plans/inc1.md` — merged into `main` at abc1234\n' \
  > "$GREPO/docs/dforge/plans/completed.md"
bash "$HERE/../scripts/register" set "$GREG" 1 doing --assigned docs/superpowers/plans/inc2.md >/dev/null

# The reverse direction: Assigned cells spelled docs/forge/ match the plan
# being completed and a completed.md entry spelled docs/superpowers/.
bash "$HERE/../scripts/register" set "$GREG" 1 doing --assigned docs/forge/plans/inc2.md >/dev/null
bash "$HERE/../scripts/register" set "$GREG" 6 open --assigned docs/forge/plans/inc1.md >/dev/null
OUT=$(cd "$GREPO" && bash "$SCRIPT" --complete docs/superpowers/plans/inc2.md 2>&1)
has "routing: docs/forge cells name docs/superpowers plans" "$OUT" "Still assigned to a finished plan: #1, #6"
bash "$HERE/../scripts/register" set "$GREG" 1 doing --assigned docs/superpowers/plans/inc2.md >/dev/null
bash "$HERE/../scripts/register" set "$GREG" 6 open --assigned docs/superpowers/plans/inc1.md >/dev/null
```

(The three-line anchor is unique. The `printf` line also appears earlier in the file, but there it is followed by `cat > …lane.md`.)

In `plugins/dforge/tests/plan-lib.test.sh`, replace the last check before the summary:

```bash
(cd "$SR" && HOME=$SH plan_require_same_project "$M/dforge/plans/mp.md" 2>/dev/null)
check "same project: a mirror plan while documents are local is refused" "$?" "2"
```

with:

```bash
(cd "$SR" && HOME=$SH plan_require_same_project "$M/dforge/plans/mp.md" 2>/dev/null)
check "same project: a mirror plan while documents are local is refused" "$?" "2"

# --- a home that is a git repository: a mirror plan still belongs to the
# working directory's checkout, and a ConfigError stops plan_ledger ---
GH="$TMP/git-home"
git init -q "$GH"
GM=$(stores_home "$GH" "$SR" proj darkmem darkmem)
mkdir -p "$GM/dforge/plans" "$GM/work/sdd/gp"
printf '# GP\n' > "$GM/dforge/plans/gp.md"
printf '# SDD ledger — plan: docs/dforge/plans/gp.md\n' > "$GM/work/sdd/gp/progress.md"
check "plan_ledger: a mirror plan in a home under git finds its ledger" \
  "$(cd "$SR" && HOME=$GH plan_ledger "$GM/dforge/plans/gp.md")" "$GM/work/sdd/gp/progress.md"
printf '{not json\n' > "$GH/.dforge/config.json"
(cd "$SR" && HOME=$GH plan_ledger "$GM/dforge/plans/gp.md" > /dev/null 2> "$TMP/ledger-err")
check "plan_ledger: a ConfigError exits 2" "$?" "2"
check "plan_ledger: the ConfigError is named once" "$(grep -c 'not valid JSON' "$TMP/ledger-err")" "1"
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `timeout 600 bash plugins/dforge/tests/roots.test.sh`
Expected: FAIL, 3 checks: `name key: a trailing slash` (got `docs/dforge/`), `name key: a trailing slash after a name` (got `docs/dforge/plans/`), and `name spellings: a trailing slash` (got `docs/dforge/|docs/forge/|docs/superpowers/|`). The bare-resolve and DIR checks pass: they cover existing behaviour.

Run: `timeout 600 bash plugins/dforge/tests/next-step.test.sh`
Expected: PASS (coverage for the reverse prefix direction)

Run: `timeout 600 bash plugins/dforge/tests/plan-lib.test.sh`
Expected: FAIL, 3 checks:
- `plan_ledger: a mirror plan in a home under git finds its ledger` gets `''`: `_plan_ctx` returns the mirror directory, which lies inside the home's repository, so the ledger is looked up under that repository.
- `plan_ledger: a ConfigError exits 2` gets `0`: every root lookup runs inside `$(…)`, so its `exit 2` is lost.
- `plan_ledger: the ConfigError is named once` gets `2`.

- [ ] **Step 3: Implement**

In `plugins/dforge/scripts/lib/roots.sh`, replace the start of `dforge_name_key`:

```bash
dforge_name_key() {
  local name=${1#./}
  case $name in
```

with:

```bash
dforge_name_key() {
  local name=${1#./}
  [ "$name" = / ] || name=${name%/}
  case $name in
```

In the same file, replace `dforge_name_spellings`, so the suffix is computed once:

```bash
dforge_name_spellings() {
  local key
  key=$(dforge_name_key "$1")
  printf '%s\n' "$key"
  case $key in
    docs/dforge) printf 'docs/forge\ndocs/superpowers\n' ;;
    docs/dforge/*) printf 'docs/forge/%s\ndocs/superpowers/%s\n' "${key#docs/dforge/}" "${key#docs/dforge/}" ;;
  esac
}
```

with:

```bash
dforge_name_spellings() {
  local key rest
  key=$(dforge_name_key "$1")
  printf '%s\n' "$key"
  case $key in
    docs/dforge) printf 'docs/forge\ndocs/superpowers\n' ;;
    docs/dforge/*)
      rest=${key#docs/dforge/}
      printf 'docs/forge/%s\ndocs/superpowers/%s\n' "$rest" "$rest" ;;
  esac
}
```

In the same file, replace the comment above `dforge_name()`. The function body does not change: every caller passes FILE relative to the working directory, often with a relative DIR (`completed_form` in `scripts/plan-revise` calls `dforge_name "$1" "$(_plan_ctx "$1")"`, and `_plan_ctx plans/x.md` returns `plans`), so testing `$DIR/$file` instead would break the completed.md lookup:

```bash
# dforge_name FILE [DIR] — the inverse of dforge_resolve, computed from the roots.
# A relative FILE that exists from a subdirectory of the checkout is made
# absolute first; a path spelled through a symbolic link is retried in its
# physical form, and a Git Bash /c/… path in git's C:/… form.
```

with:

```bash
# dforge_name FILE [DIR] — the inverse of dforge_resolve, computed from the roots.
# A relative FILE is a path from the working directory, as every caller holds
# it, even when DIR names another directory: one that exists from a
# subdirectory of the checkout is made absolute first. A path spelled through a
# symbolic link is retried in its physical form, and a Git Bash /c/… path in
# git's C:/… form.
```

In `plugins/dforge/scripts/lib/plan.sh`, replace `_plan_ctx`:

```bash
# _plan_ctx PLAN — the directory whose checkout a plan belongs to: its own
# directory inside a git repository, else the working directory (a plan in
# the darkmem mirror belongs to the checkout it is worked from).
_plan_ctx() {
  if git -C "$(dirname "$1")" rev-parse --show-toplevel >/dev/null 2>&1; then dirname "$1"; else printf '%s\n' "$PWD"; fi
}
```

with:

```bash
# _plan_ctx PLAN — the directory whose checkout a plan belongs to: its own
# directory inside a git repository, else the working directory. A plan in
# the darkmem mirror belongs to the checkout it is worked from, even when the
# mirror lies inside a repository (a home directory under git).
_plan_ctx() {
  local dir mirror physical
  dir=$(dirname "$1")
  mirror=$(cd "${HOME:-}/.dforge/mirror" 2>/dev/null && pwd -P) || mirror=""
  physical=$(cd "$dir" 2>/dev/null && pwd -P) || physical=""
  if [ -n "$mirror" ] && [ -n "$physical" ]; then
    case "$physical/" in "$mirror"/*) printf '%s\n' "$PWD"; return 0 ;; esac
  fi
  if git -C "$dir" rev-parse --show-toplevel >/dev/null 2>&1; then printf '%s\n' "$dir"; else printf '%s\n' "$PWD"; fi
}
```

In the same file, replace the start of `plan_ledger`:

```bash
plan_ledger() {
  local ctx want file named
  ctx=$(_plan_ctx "$1")
  want=$(dforge_name_key "$(dforge_name "$1" "$ctx")")
```

with:

```bash
plan_ledger() {
  local ctx want file named
  ctx=$(_plan_ctx "$1")
  # In this shell, so a ConfigError exits the caller rather than a $(…) below.
  dforge_stores_init "$ctx"
  want=$(dforge_name_key "$(dforge_name "$1" "$ctx")")
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `timeout 600 bash plugins/dforge/tests/roots.test.sh`
Expected: PASS

Run: `timeout 600 bash plugins/dforge/tests/plan-lib.test.sh`
Expected: PASS

Run: `timeout 600 bash plugins/dforge/tests/next-step.test.sh`
Expected: PASS

Other suites that read `plan_ledger`, `_plan_ctx` or the name keys, all expected to PASS:
- `timeout 600 bash plugins/dforge/tests/plan-revise.test.sh`
- `timeout 600 bash plugins/dforge/tests/plan-lint.test.sh`
- `timeout 600 bash plugins/dforge/tests/register.test.sh`
- `timeout 600 bash plugins/dforge/tests/roadmap.test.sh`
- `timeout 600 bash plugins/dforge/tests/auto-run.test.sh`
- `timeout 600 bash plugins/dforge/tests/in-flight.test.sh`

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/scripts/lib/roots.sh plugins/dforge/scripts/lib/plan.sh plugins/dforge/tests/roots.test.sh plugins/dforge/tests/next-step.test.sh plugins/dforge/tests/plan-lib.test.sh
git commit -m "fix(roots): mirror plan context and name keys"
```

---

### Task 22: Track each workstream's last synced checkpoint

**Files:**
- Modify: `plugins/dforge/scripts/lib/darkmem-push.mjs`
- Modify: `plugins/dforge/scripts/lib/darkmem-pull.mjs`
- Modify: `plugins/dforge/scripts/lib/darkmem-progress-move.mjs`
- Test: `plugins/dforge/tests/darkmem-sync/push.test.mjs`
- Test: `plugins/dforge/tests/darkmem-sync/pull.test.mjs`
- Test: `plugins/dforge/tests/darkmem-sync/reconcile-progress.test.mjs`

**Interfaces:**
- Consumes: `checkpointAtOf`, `newestCheckpointAt`, `recordCheckpointAt` from Task 20
- Produces: `fileLatest` (darkmem-progress-move.mjs, not exported) answers `{ hash, at, workstream, detail }`; `newestCheckpoint` (not exported) answers the checkpoint plus `workstream`, the key of the workstream holding it

**Items:** DM 12

**Depends on:** Task 20
**Implementer:** dr-superpowers:impl-sonnet-high
**Evaluation:** files 2 - spec 0 - coupling 1 - risk 2 = 5

Every reader of `checkpointAt`, from `grep -rn "checkpointAt" plugins/dforge/scripts` before this task:
- `darkmem-push.mjs`: the duplicate lookup's `since` and both writes in `sendCheckpoint`
- `darkmem-pull.mjs`: the gate and the write in `pullCheckpoint`
- `darkmem-progress-move.mjs`: the write after `fileLatest` in the move into darkmem, the gate and the write in `renderCheckpoint`, and the reset to `null` in `progressToLocal`, which stays
- `darkmem-mirror.mjs`: `emptyState` and `loadState`, done in Task 20

No hook, cockpit or other script reads it.

- [ ] **Step 1: Write the failing tests**

The tests prove four things. With two workstreams, a checkpoint whose answer was lost is still found after a push to another workstream. An old state file's single value is the floor for a workstream until that workstream is written, and is then kept as `"*"`. A pull still never replaces latest.md with a checkpoint older than the newest one synced (a regression guard: it passes before and after). And the state now records the workstream.

In `plugins/dforge/tests/darkmem-sync/push.test.mjs`, at the end of the test `"a checkpoint filed a microsecond before the last synced one is not taken for this note"`, replace:

```js
  assert.deepEqual(s.stub.db.workstreams[0].entries.map(e => e.body), ["# X\n", "# Y\n", "# X\n"]);
});
```

with:

```js
  assert.deepEqual(s.stub.db.workstreams[0].entries.map(e => e.body), ["# X\n", "# Y\n", "# X\n"]);
});

test("a checkpoint whose answer was lost is found after a push to another workstream", async t => {
  const s = await setup(t);
  const latest = path.join(s.workRoot, "handoff", "latest.md");
  const p1 = "# Handoff\n\n## State\n- Plan: `docs/dforge/plans/p1.md`\n";
  write(latest, p1);
  s.stub.db.failures.push({ method: "POST", path: "/api/v1/worklog/entries", status: 502, commit: true });
  assert.equal((await s.push()).code, 1);
  write(latest, "# Handoff\n\n## State\n- Plan: `docs/dforge/plans/p2.md`\n");
  assert.equal((await s.push()).code, 0);
  write(latest, p1);
  const result = await s.push();
  assert.equal(result.code, 0, result.stdout);
  assert.match(result.stdout, / 0 checkpoints;/);
  const filed = key => s.stub.db.workstreams.find(w => w.key === key).entries;
  assert.equal(filed("p1").length, 1, "p1's lost checkpoint is recorded, not filed twice");
  const { checkpointAt } = JSON.parse(read(path.join(s.mirror, ".sync-state.json")));
  assert.deepEqual(checkpointAt, { p1: filed("p1")[0].created_at, p2: filed("p2")[0].created_at });
});

test("an old state file's single checkpointAt stands for a workstream until it is pushed", async t => {
  const s = await setup(t);
  await s.seed.append({ project: "proj", workstream: "p1", entries: [{ kind: "checkpoint", body: "# X\n" }] });
  const old = new Date(Date.parse(s.stub.db.workstreams[0].entries[0].created_at) + 500).toISOString();
  write(path.join(s.mirror, ".sync-state.json"), JSON.stringify({
    version: 1, documents: {}, ledgers: {}, checkpoint: null, checkpointAt: old, conflicts: [], pendingLinks: [], prefix: "dforge",
  }));
  write(path.join(s.workRoot, "handoff", "latest.md"), "# X\n");
  const result = await s.push("--workstream", "p1");
  assert.equal(result.code, 0, result.stdout);
  assert.match(result.stdout, / 1 checkpoints;/, "the old value is the floor: X filed before it is not this note");
  const entries = s.stub.db.workstreams[0].entries;
  assert.deepEqual(JSON.parse(read(path.join(s.mirror, ".sync-state.json"))).checkpointAt, { "*": old, p1: entries.at(-1).created_at });
});
```

In `plugins/dforge/tests/darkmem-sync/pull.test.mjs`, at the end of the test `"checkpoints a microsecond apart are ordered by darkmem's clock, not rounded to the millisecond"`, replace:

```js
  assert.equal(s.state().checkpointAt, "2026-09-25T10:00:00.000003+00:00");
});
```

with:

```js
  assert.deepEqual(s.state().checkpointAt, { p1: "2026-09-25T10:00:00.000003+00:00" });
});

test("latest.md stays the newest stop when the workstream that filed it closes", async t => {
  const s = await setup(t);
  await s.seed.append({ project: "proj", workstream: "p2", entries: [{ kind: "checkpoint", body: "# B\n" }] });
  await s.seed.append({ project: "proj", workstream: "p1", entries: [{ kind: "checkpoint", body: "# C\n" }] });
  assert.equal((await s.pull()).code, 0);
  const latest = path.join(s.workRoot, "handoff", "latest.md");
  assert.equal(read(latest), "# C\n");
  s.stub.db.workstreams.find(w => w.key === "p1").state = "closed";
  assert.equal((await s.pull()).code, 0);
  assert.equal(read(latest), "# C\n", "p2's older checkpoint does not replace p1's newer one");
});

test("an old state file's single checkpointAt gates a pull, which then records the workstream", async t => {
  const s = await setup(t);
  await s.seed.append({ project: "proj", workstream: "p1", entries: [{ kind: "checkpoint", body: "# A\n" }] });
  const filed = s.stub.db.workstreams[0].entries[0].created_at;
  const old = new Date(Date.parse(filed) + 500).toISOString();
  write(path.join(s.mirror, ".sync-state.json"), JSON.stringify({
    version: 1, documents: {}, ledgers: {}, checkpoint: null, checkpointAt: old, conflicts: [], pendingLinks: [], prefix: "dforge",
  }));
  const latest = path.join(s.workRoot, "handoff", "latest.md");
  assert.equal((await s.pull()).code, 0);
  assert.equal(fs.existsSync(latest), false, "a checkpoint older than the old value is not taken");
  await s.seed.append({ project: "proj", workstream: "p2", entries: [{ kind: "checkpoint", body: "# B\n" }] });
  assert.equal((await s.pull()).code, 0);
  assert.equal(read(latest), "# B\n");
  assert.deepEqual(s.state().checkpointAt, { "*": old, p2: s.stub.db.workstreams[1].entries[0].created_at });
});
```

In `plugins/dforge/tests/darkmem-sync/reconcile-progress.test.mjs`, in the test `"progress moves into darkmem from every checkout, and a second run does nothing"`, replace:

```js
  assert.equal(s.state().checkpointAt, checkpoint.created_at);
```

with:

```js
  assert.deepEqual(s.state().checkpointAt, { p1: checkpoint.created_at });
```

In the same file, in the test `"a latest.md that names no plan is copied unsent, behind darkmem's newest checkpoint"`, replace:

```js
  assert.equal(s.state().checkpointAt, workstream.last_entry_at);
```

with:

```js
  assert.deepEqual(s.state().checkpointAt, { p9: workstream.last_entry_at });
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `timeout 300 node --test plugins/dforge/tests/darkmem-sync/push.test.mjs`
Expected: FAIL, 2 tests:
- `a checkpoint whose answer was lost is found after a push to another workstream`: the third push prints `1 checkpoints`, because the global `checkpointAt` (p2's) is newer than p1's lost entry, so p1's checkpoint is filed twice.
- `an old state file's single checkpointAt…`: `checkpointAt` is a string, not `{ "*": …, p1: … }`.

Run: `timeout 300 node --test plugins/dforge/tests/darkmem-sync/pull.test.mjs`
Expected: FAIL, 2 tests: `checkpoints a microsecond apart…` and `an old state file's single checkpointAt gates a pull…` both read a string where an object is expected. `latest.md stays the newest stop…` passes.

Run: `timeout 300 node --test plugins/dforge/tests/darkmem-sync/reconcile-progress.test.mjs`
Expected: FAIL, 2 tests (the two edited assertions read a string).

- [ ] **Step 3: Implement**

`plugins/dforge/scripts/lib/darkmem-push.mjs`. In the import from `./darkmem-mirror.mjs`, replace:

```js
  DOC_PREFIX, EMPTY_SHA, MAX_ENTRIES_PER_APPEND, MAX_ENTRY_CHARS, UsageError, archiveUri, caseGroups, checkpointTarget, decodeUtf8,
```

with:

```js
  DOC_PREFIX, EMPTY_SHA, MAX_ENTRIES_PER_APPEND, MAX_ENTRY_CHARS, UsageError, archiveUri, caseGroups, checkpointAtOf, checkpointTarget, decodeUtf8,
```

and replace:

```js
  unsupportedPlanDirs, uriFamily, uriProblem, uriToLocal, utcStamp, utf8Fault, validKey,
} from "./darkmem-mirror.mjs";
```

with:

```js
  recordCheckpointAt, unsupportedPlanDirs, uriFamily, uriProblem, uriToLocal, utcStamp, utf8Fault, validKey,
} from "./darkmem-mirror.mjs";
```

In `sendCheckpoint`, replace:

```js
  // The same note already filed since the last synced checkpoint (an earlier
  // push whose answer was lost, even behind another client's checkpoint) is
  // recorded, not filed twice.
  const existing = await client.resume(cfg.project, workstream);
  const since = (state.checkpointAt && isoMicros(state.checkpointAt)) ?? -Infinity;
  const filed = existing && (await client.entries(existing.workstream.id, "checkpoint"))
    .find(entry => isoMicros(entry.created_at) >= since && sha256(Buffer.from(entry.body, "utf8")) === hash);
  if (filed) {
    state.checkpoint = hash;
    state.checkpointAt = filed.created_at;
```

with:

```js
  // The same note already filed since this workstream's last synced checkpoint
  // (an earlier push whose answer was lost, even behind another client's
  // checkpoint or this mirror's push to another workstream) is recorded, not
  // filed twice.
  const existing = await client.resume(cfg.project, workstream);
  const synced = checkpointAtOf(state, workstream);
  const since = (synced && isoMicros(synced)) ?? -Infinity;
  const filed = existing && (await client.entries(existing.workstream.id, "checkpoint"))
    .find(entry => isoMicros(entry.created_at) >= since && sha256(Buffer.from(entry.body, "utf8")) === hash);
  if (filed) {
    state.checkpoint = hash;
    recordCheckpointAt(state, workstream, filed.created_at);
```

At the end of `sendCheckpoint`, replace:

```js
  state.checkpoint = hash;
  state.checkpointAt = answer.workstream.last_entry_at;
```

with:

```js
  state.checkpoint = hash;
  recordCheckpointAt(state, workstream, answer.workstream.last_entry_at);
```

`plugins/dforge/scripts/lib/darkmem-pull.mjs`. In the import from `./darkmem-mirror.mjs`, replace:

```js
  DOC_PREFIX, caseGroups, familiesOf, isArchiveUri, isoMicros, sha256, uriFamily, uriProblem, uriToLocal, validKey, writeFileAtomic,
```

with:

```js
  DOC_PREFIX, caseGroups, familiesOf, isArchiveUri, isoMicros, newestCheckpointAt, recordCheckpointAt, sha256, uriFamily, uriProblem, uriToLocal,
  validKey, writeFileAtomic,
```

Replace the comment and start of `pullCheckpoint`:

```js
// latest.md is the most recent stop: the newest checkpoint across the open
// workstreams, taken when it is newer than the last checkpoint this mirror
// synced (by darkmem's own timestamps, never the file's mtime) and never over
// local edits that have not been pushed.
async function pullCheckpoint({ cfg, client, roots, state, persist, report }, open) {
  let newest = null;
  let unread = false;
```

with:

```js
// latest.md is the most recent stop: the newest checkpoint across the open
// workstreams, taken when it is newer than the newest checkpoint this mirror
// synced in any workstream (by darkmem's own timestamps, never the file's
// mtime) and never over local edits that have not been pushed.
async function pullCheckpoint({ cfg, client, roots, state, persist, report }, open) {
  let newest = null;
  let newestKey = null;
  let unread = false;
```

In the same function, replace:

```js
    if (checkpoint && (!newest || isoMicros(checkpoint.created_at) > isoMicros(newest.created_at))) newest = checkpoint;
  }
  // Without every workstream's checkpoint the newest is unknown.
  if (!newest || unread) return;
  if (state.checkpointAt && isoMicros(newest.created_at) <= isoMicros(state.checkpointAt)) return;
```

with:

```js
    if (checkpoint && (!newest || isoMicros(checkpoint.created_at) > isoMicros(newest.created_at))) {
      newest = checkpoint;
      newestKey = ws.key;
    }
  }
  // Without every workstream's checkpoint the newest is unknown.
  if (!newest || unread) return;
  const synced = newestCheckpointAt(state);
  if (synced && isoMicros(newest.created_at) <= isoMicros(synced)) return;
```

and at its end replace:

```js
  state.checkpoint = remoteHash;
  state.checkpointAt = newest.created_at;
```

with:

```js
  state.checkpoint = remoteHash;
  recordCheckpointAt(state, newestKey, newest.created_at);
```

`plugins/dforge/scripts/lib/darkmem-progress-move.mjs`. In the import from `./darkmem-mirror.mjs`, replace:

```js
  DOC_PREFIX, checkpointTarget, decodeUtf8, isoMicros, ledgerFiles, ledgerPieces, listDocumentFiles, propertiesFor, sha256, unsupportedPlanDirs,
  uriFamily, utcStamp, writeFileAtomic,
```

with:

```js
  DOC_PREFIX, checkpointTarget, decodeUtf8, isoMicros, ledgerFiles, ledgerPieces, listDocumentFiles, newestCheckpointAt, propertiesFor,
  recordCheckpointAt, sha256, unsupportedPlanDirs, uriFamily, utcStamp, writeFileAtomic,
```

Replace `newestCheckpoint`:

```js
// The newest checkpoint darkmem holds across `workstreams`, or null.
async function newestCheckpoint({ cfg, client }, workstreams) {
  let newest = null;
  for (const ws of workstreams) {
    const checkpoint = (await client.resume(cfg.project, ws.key))?.checkpoint;
    if (checkpoint && (!newest || isoMicros(checkpoint.created_at) > isoMicros(newest.created_at))) newest = checkpoint;
  }
  return newest;
}
```

with:

```js
// The newest checkpoint darkmem holds across `workstreams`, with the key of
// the workstream that holds it as `workstream`, or null.
async function newestCheckpoint({ cfg, client }, workstreams) {
  let newest = null;
  for (const ws of workstreams) {
    const checkpoint = (await client.resume(cfg.project, ws.key))?.checkpoint;
    if (checkpoint && (!newest || isoMicros(checkpoint.created_at) > isoMicros(newest.created_at))) newest = { ...checkpoint, workstream: ws.key };
  }
  return newest;
}
```

In the comment above `fileLatest`, replace:

```js
// pull only replaces it with a newer one. Answers { hash, at, detail }, or
// { problem } when darkmem reads it back different.
```

with:

```js
// pull only replaces it with a newer one. Answers { hash, at, workstream,
// detail }, `workstream` naming the key `at` was read from (null with a null
// `at`), or { problem } when darkmem reads it back different.
```

In `fileLatest`, replace:

```js
    return { hash, at: newest?.created_at ?? null, detail: "latest.md names no plan or draft; copied to the mirror, not sent" };
```

with:

```js
    return {
      hash, at: newest?.created_at ?? null, workstream: newest?.workstream ?? null,
      detail: "latest.md names no plan or draft; copied to the mirror, not sent",
    };
```

and replace:

```js
  return { hash, at, detail: `latest.md filed as a checkpoint of ${target.slug}` };
```

with:

```js
  return { hash, at, workstream: target.slug, detail: `latest.md filed as a checkpoint of ${target.slug}` };
```

In the move into darkmem (the loop over `sources` after the mirror copies are written), replace:

```js
      state.checkpoint = latest.hash;
      state.checkpointAt = latest.at;
```

with:

```js
      state.checkpoint = latest.hash;
      if (latest.at === null) state.checkpointAt = null;
      else recordCheckpointAt(state, latest.workstream, latest.at);
```

In `renderCheckpoint`, replace its first line:

```js
  if (!newest || (state.checkpointAt && isoMicros(newest.created_at) <= isoMicros(state.checkpointAt))) return;
```

with:

```js
  const synced = newestCheckpointAt(state);
  if (!newest || (synced && isoMicros(newest.created_at) <= isoMicros(synced))) return;
```

and replace:

```js
  if (current !== hash) writeFileAtomic(file, remote);
  state.checkpoint = hash;
  state.checkpointAt = newest.created_at;
```

with:

```js
  if (current !== hash) writeFileAtomic(file, remote);
  state.checkpoint = hash;
  recordCheckpointAt(state, newest.workstream, newest.created_at);
```

Leave `state.checkpointAt = null;` in `progressToLocal` as it is.

Then confirm that no direct read is left: `grep -n "state.checkpointAt" plugins/dforge/scripts/lib/darkmem-push.mjs plugins/dforge/scripts/lib/darkmem-pull.mjs plugins/dforge/scripts/lib/darkmem-progress-move.mjs` prints only the two `= null` assignments in darkmem-progress-move.mjs.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `timeout 300 node --test plugins/dforge/tests/darkmem-sync/push.test.mjs plugins/dforge/tests/darkmem-sync/pull.test.mjs plugins/dforge/tests/darkmem-sync/reconcile-progress.test.mjs`
Expected: PASS

Run: `timeout 600 bash plugins/dforge/tests/darkmem-sync.test.sh`
Expected: PASS (includes `migrate.test.mjs`, whose old-shape fixtures still load)

Run: `timeout 600 bash plugins/dforge/tests/dforge-migrate.test.sh`
Expected: PASS (dforge-home-migrate.mjs loads and saves the sync state)

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/scripts/lib/darkmem-push.mjs plugins/dforge/scripts/lib/darkmem-pull.mjs plugins/dforge/scripts/lib/darkmem-progress-move.mjs plugins/dforge/tests/darkmem-sync/push.test.mjs plugins/dforge/tests/darkmem-sync/pull.test.mjs plugins/dforge/tests/darkmem-sync/reconcile-progress.test.mjs
git commit -m "fix(darkmem): find lost checkpoints per workstream"
```

---

### Task 23: Harden mirror paths, splits and state loading

**Files:**
- Modify: `plugins/dforge/scripts/lib/darkmem-mirror.mjs`
- Modify: `plugins/dforge/scripts/lib/darkmem-sync.mjs`
- Test: `plugins/dforge/tests/darkmem-sync/mirror.test.mjs`

**Interfaces:**
- Consumes: None
- Produces: `splitAtLimit(text, limit)` throws `RangeError` for a limit under 2; `pathToUri(roots, file)` (same signature) also resolves an absolute path under any `git worktree list` checkout's `docs/dforge`, and returns null for a name with an empty segment

**Items:** DM 10, DM 20, DR 9, DR 33, DR 35

**Depends on:** Task 20
**Implementer:** dr-superpowers:impl-sonnet-medium
**Evaluation:** files 1 - spec 0 - coupling 0 - risk 2 = 3

- [ ] **Step 1: Write the failing tests**

The tests prove five things. `splitAtLimit` rejects a limit under 2 instead of looping. `pathToUri` refuses an empty segment and finds a path in another worktree. `propertiesFor` treats only a missing plan as "no spec". And a state file whose path cannot be reached is an error, not a fresh start.

In `plugins/dforge/tests/darkmem-sync/mirror.test.mjs`, replace the helpers import:

```js
import { scratch, write } from "./helpers.mjs";
```

with:

```js
import { git, makeRepo, scratch, write } from "./helpers.mjs";
```

At the end of the test `"splitAtLimit cuts after newlines, never splits a surrogate pair, and concatenates back"`, replace:

```js
  assert.equal(split[0], "x".repeat(9));
});
```

with:

```js
  assert.equal(split[0], "x".repeat(9));
  assert.throws(() => splitAtLimit("ab", 1), RangeError, "a limit under 2 cannot hold a surrogate pair");
  assert.throws(() => splitAtLimit("😀", 1), RangeError);
});
```

(The `"ab"` assertion comes first on purpose. Before the fix it returns `["a", "b"]` and fails at once, so the test never reaches the surrogate case, which loops forever.)

In the test `"paths name their uris; plans and drafts name their properties; a handoff note names its target"`, replace:

```js
  assert.equal(pathToUri(named, "docs/dforge/../../x.md"), null);
```

with:

```js
  assert.equal(pathToUri(named, "docs/dforge/../../x.md"), null);
  assert.equal(pathToUri(named, "docs/forge/plans/"), null, "an empty segment names no document");
  assert.equal(pathToUri(named, "docs/dforge//plans/p1.md"), null);
```

Add three tests before the test `"each family lists, reports and links only when the roots sync it"`. Replace:

```js
test("each family lists, reports and links only when the roots sync it", () => {
```

with:

```js
test("pathToUri reads an absolute path under any worktree's docs directory", () => {
  const repo = makeRepo();
  const worktree = path.join(scratch("dms-wt-"), "wt");
  git(repo, "worktree", "add", "-q", "-b", "wt", worktree);
  const { roots } = mirror();
  const file = path.join(worktree, "docs", "dforge", "plans", "p.md");
  assert.equal(pathToUri({ ...roots, worktreeRoot: repo }, file), "dforge/plans/p.md");
  assert.equal(pathToUri({ ...roots, worktreeRoot: repo }, path.join(worktree, ".dforge", "x.md")), null);
  assert.equal(pathToUri(roots, file), null, "without a worktree root no worktree is listed");
});

test("propertiesFor reads a missing plan as no spec; any other read failure is an error", () => {
  const { roots } = mirror();
  assert.deepEqual(propertiesFor(roots, "p1", "docs/dforge/plans/p1.md"), { plan_uri: "dforge/plans/p1.md" });
  fs.mkdirSync(path.join(roots.docsRoot, "plans", "p1.md"), { recursive: true });
  assert.throws(() => propertiesFor(roots, "p1", "docs/dforge/plans/p1.md"), { code: "EISDIR" });
});

test("a state file the mirror cannot reach is an error, not a fresh start", { skip: process.platform === "win32" && "Windows reports ENOENT under a file" }, () => {
  const { root } = mirror();
  fs.writeFileSync(path.join(root, "file"), "x");
  assert.throws(() => loadState(path.join(root, "file", ".sync-state.json")), StateError);
});

test("each family lists, reports and links only when the roots sync it", () => {
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `timeout 300 node --test plugins/dforge/tests/darkmem-sync/mirror.test.mjs`
Expected: FAIL, 5 tests:
- `splitAtLimit cuts after newlines…`: no RangeError for limit 1.
- `paths name their uris…`: `docs/forge/plans/` maps to `dforge/plans/`.
- `pathToUri reads an absolute path under any worktree's docs directory`: null for the other worktree.
- `propertiesFor reads a missing plan as no spec…`: the EISDIR error is swallowed.
- `a state file the mirror cannot reach…`: `existsSync` reads ENOTDIR as missing and returns a fresh state.

- [ ] **Step 3: Implement**

`plugins/dforge/scripts/lib/darkmem-mirror.mjs`. Add the child-process import. Replace:

```js
import crypto from "node:crypto";
import fs from "node:fs";
```

with:

```js
import { spawnSync } from "node:child_process";
import crypto from "node:crypto";
import fs from "node:fs";
```

In `loadState`, replace:

```js
export function loadState(file) {
  if (!fs.existsSync(file)) return emptyState();
  let raw;
```

with:

```js
export function loadState(file) {
  try {
    fs.statSync(file);
  } catch (error) {
    if (error.code === "ENOENT") return emptyState();
    throw new StateError(`${file} is unreadable (${error.message}); ${REBUILD}`);
  }
  let raw;
```

In `loadState`, reword the pre-3.0 comment (DR 9). Replace:

```js
  // Set once darkmem was checked for pre-3.0 uris (dforge-home-migrate.mjs).
```

with:

```js
  // Set once darkmem was checked for older (superpowers/ or forge/) uris
  // (dforge-home-migrate.mjs).
```

Replace the start of `splitAtLimit`:

```js
// Counted in UTF-16 units, which never undercounts the server's code points.
export function splitAtLimit(text, limit = MAX_ENTRY_CHARS) {
  const pieces = [];
```

with:

```js
// Counted in UTF-16 units, which never undercounts the server's code points.
// A limit under 2 cannot hold a surrogate pair, and would never advance.
export function splitAtLimit(text, limit = MAX_ENTRY_CHARS) {
  if (!Number.isSafeInteger(limit) || limit < 2) throw new RangeError(`splitAtLimit needs a limit of at least 2, got ${limit}`);
  const pieces = [];
```

Replace the whole of `pathToUri` and its comment. This rewraps the 89-character comment line (DR 33), rejects an empty segment (DR 35), and tries every worktree's docs directory (DM 20):

```js
// The darkmem uri a document's name or path stands for: a name under
// docs/dforge/, docs/forge/ or docs/superpowers/ (as a ledger or a **Spec:** line writes
// it), or an absolute path under the docs root or the worktree's docs
// directory. Computed from the roots, never by searching for a segment.
export function pathToUri(roots, file) {
  const text = String(file).replace(/\\/g, "/");
  const name = /^(?:\.\/)?docs\/(?:dforge|forge|superpowers)\/(.+)$/.exec(text);
  if (name) return name[1].split("/").some(segment => segment === ".." || segment === ".") ? null : `${DOC_PREFIX}/${name[1]}`;
  if (!path.isAbsolute(String(file))) return null;
  const bases = [roots.docsRoot];
  if (roots.worktreeRoot) bases.push(path.join(roots.worktreeRoot, "docs", "dforge"));
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

with:

```js
// Every worktree's docs directory, as `git worktree list` names the
// checkouts; none when git cannot list them.
function worktreeDocsRoots(worktreeRoot) {
  if (!worktreeRoot) return [];
  const listed = spawnSync("git", ["-C", worktreeRoot, "worktree", "list", "--porcelain"], { encoding: "utf8", timeout: 10000 });
  if (listed.status !== 0) return [];
  return listed.stdout.split(/\r?\n/).filter(line => line.startsWith("worktree "))
    .map(line => path.join(line.slice("worktree ".length), "docs", "dforge"));
}

// The darkmem uri a document's name or path stands for: a name under
// docs/dforge/, docs/forge/ or docs/superpowers/ (as a ledger or a **Spec:**
// line writes it), or an absolute path under the docs root, the worktree's
// docs directory or another worktree's (an older ledger's identity line may
// name one). Computed from the roots, never by searching for a segment.
export function pathToUri(roots, file) {
  const text = String(file).replace(/\\/g, "/");
  const name = /^(?:\.\/)?docs\/(?:dforge|forge|superpowers)\/(.+)$/.exec(text);
  if (name) return name[1].split("/").some(segment => segment === "" || segment === ".." || segment === ".") ? null : `${DOC_PREFIX}/${name[1]}`;
  if (!path.isAbsolute(String(file))) return null;
  const under = base => {
    const rel = path.relative(path.resolve(base), path.resolve(String(file)));
    return rel && rel !== ".." && !rel.startsWith(`..${path.sep}`) && !path.isAbsolute(rel) ? `${DOC_PREFIX}/${rel.split(path.sep).join("/")}` : null;
  };
  const bases = [roots.docsRoot];
  if (roots.worktreeRoot) bases.push(path.join(roots.worktreeRoot, "docs", "dforge"));
  for (const base of bases) {
    const uri = base && under(base);
    if (uri) return uri;
  }
  // Listed only when the roots do not hold the path: git runs once per miss.
  for (const base of worktreeDocsRoots(roots.worktreeRoot)) {
    const uri = under(base);
    if (uri) return uri;
  }
  return null;
}
```

In `propertiesFor`, replace:

```js
    try {
      const spec = /^\*\*Spec:\*\*\s*`?([^`\s]+)`?/m.exec(fs.readFileSync(uriToLocal(roots, uri), "utf8"));
      const specUri = spec ? pathToUri(roots, spec[1]) : null;
      if (specUri) properties.spec_uri = specUri;
    } catch {
      // The plan is not in this mirror; the workstream carries no spec_uri.
    }
```

with:

```js
    try {
      const spec = /^\*\*Spec:\*\*\s*`?([^`\s]+)`?/m.exec(fs.readFileSync(uriToLocal(roots, uri), "utf8"));
      const specUri = spec ? pathToUri(roots, spec[1]) : null;
      if (specUri) properties.spec_uri = specUri;
    } catch (error) {
      // The plan is not in this mirror; the workstream carries no spec_uri.
      // Any other failure to read it is a real fault, not a missing plan.
      if (error.code !== "ENOENT") throw error;
    }
```

`plugins/dforge/scripts/lib/darkmem-sync.mjs`. Rewrap the `documentUri` comment (DR 33). Replace:

```js
// A document name as ledgers and plans write it, docs/dforge/<rest> or the
// older docs/forge/<rest> and docs/superpowers/<rest> that historical plans
// cite, as its uri dforge/<rest>; null for a
// path, a handoff note, an archived copy, or a name that climbs.
```

with:

```js
// A document name as ledgers and plans write it, docs/dforge/<rest> or the
// older docs/forge/<rest> and docs/superpowers/<rest> that historical plans
// cite, as its uri dforge/<rest>; null for a path, a handoff note, an
// archived copy, or a name that climbs.
```

Reword the two pre-3.0 comments (DR 9). Replace:

```js
  // A command must not run on a pre-3.0 mirror: a pull would fill dforge/
  // beside superpowers/ and every later run would refuse.
```

with:

```js
  // A command must not run on a mirror holding older (superpowers/ or forge/)
  // uris: a pull would fill dforge/ beside them and every later run would
  // refuse.
```

and replace:

```js
    // darkmem's pre-3.0 uris move before anything syncs: a pull would read a
    // document still under superpowers/ as deleted from dforge/. Answers why
    // the command may not sync, or null. Reconcile calls it after its own
    // refusals and still moves a family back to the checkout, from the mirror.
```

with:

```js
    // darkmem's older (superpowers/ or forge/) uris move before anything
    // syncs: a pull would read a document still under an older prefix as
    // deleted from dforge/. Answers why the command may not sync, or null.
    // Reconcile calls it after its own refusals and still moves a family back
    // to the checkout, from the mirror.
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `timeout 300 node --test plugins/dforge/tests/darkmem-sync/mirror.test.mjs`
Expected: PASS

Run: `grep -n "pre-3.0" plugins/dforge/scripts/lib/darkmem-sync.mjs plugins/dforge/scripts/lib/darkmem-mirror.mjs`
Expected: only `darkmem-mirror.mjs`'s `// The pre-3.0 prefix, read only to migrate a mirror and darkmem's documents.` (that comment names the superpowers/ prefix constant and is accurate).

Run: `timeout 600 bash plugins/dforge/tests/darkmem-sync.test.sh`
Expected: PASS (push, import and reconcile call `propertiesFor`, `pathToUri` and `loadState`)

Run: `timeout 600 bash plugins/dforge/tests/dforge-migrate.test.sh`
Expected: PASS (dforge-home-migrate.mjs calls `loadState`)

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/scripts/lib/darkmem-mirror.mjs plugins/dforge/scripts/lib/darkmem-sync.mjs plugins/dforge/tests/darkmem-sync/mirror.test.mjs
git commit -m "fix(darkmem): harden mirror paths and state load"
```

---

### Task 24: Report import and archive refusals once

**Files:**
- Modify: `plugins/dforge/scripts/lib/darkmem-push.mjs`
- Modify: `plugins/dforge/scripts/lib/darkmem-import.mjs`
- Test: `plugins/dforge/tests/darkmem-sync/push.test.mjs`
- Test: `plugins/dforge/tests/darkmem-sync/import.test.mjs`

**Interfaces:**
- Consumes: None
- Produces: `pushDocuments(context)` (not exported) answers the manifest it read, or null; `archiveDeleted(context, manifest)` (not exported) takes it

**Items:** DM 13, DM 36

**Depends on:** Task 22
**Implementer:** dr-superpowers:impl-sonnet-medium
**Evaluation:** files 2 - spec 0 - coupling 0 - risk 1 = 3

- [ ] **Step 1: Write the failing tests**

The tests prove three things. A refused document and a refused ledger are each reported once, and the import keeps no `darkmem-import-*` scratch directory for them. An archive whose document darkmem no longer holds leaves a note. And a push that both changes and archives documents reads the manifest once.

In `plugins/dforge/tests/darkmem-sync/push.test.mjs`, in the test `"a deleted document darkmem changed is a conflict that keeps its record; one darkmem no longer holds is dropped"`, replace:

```js
  assert.match(result.stdout, /^conflict: dforge\/a\.md: deleted locally and changed on darkmem; pull to bring darkmem's copy back$/m);
  assert.equal(s.stub.db.requests.some(r => r.method === "PATCH"), false);
```

with:

```js
  assert.match(result.stdout, /^conflict: dforge\/a\.md: deleted locally and changed on darkmem; pull to bring darkmem's copy back$/m);
  assert.match(result.stdout, /^note: dforge\/b\.md: deleted locally and already gone from darkmem; its record is dropped$/m);
  assert.equal(s.stub.db.requests.some(r => r.method === "PATCH"), false);
```

In the same file, add a test before the test `"a refused move is a conflict…"`. Replace:

```js
test("a refused move is a conflict that keeps the record; a move whose answer was lost is settled by the next push", async t => {
```

with:

```js
test("a push that changes one document and archives another reads darkmem's manifest once", async t => {
  const s = await setup(t);
  write(path.join(s.docsRoot, "a.md"), "a\n");
  write(path.join(s.docsRoot, "b.md"), "b\n");
  assert.equal((await s.push()).code, 0);
  write(path.join(s.docsRoot, "a.md"), "a2\n");
  fs.rmSync(path.join(s.docsRoot, "b.md"));
  const manifests = () => s.stub.db.requests.filter(r => r.path === "/api/v1/documents/manifest").length;
  const before = manifests();
  const result = await s.push();
  assert.equal(result.code, 0, result.stdout + result.stderr);
  assert.match(result.stdout, /darkmem-sync push: 1 documents, 0 ledger entries, 0 checkpoints, 1 archived;/);
  assert.equal(manifests() - before, 1);
});

test("a refused move is a conflict that keeps the record; a move whose answer was lost is settled by the next push", async t => {
```

In `plugins/dforge/tests/darkmem-sync/import.test.mjs`, replace the helpers import:

```js
import { makeHome, makeRepo, run, write } from "./helpers.mjs";
```

with:

```js
import { makeHome, makeRepo, run, scratch, write } from "./helpers.mjs";
```

and add a test before the test `"an empty source file refuses the whole import before any write"`. Replace:

```js
test("an empty source file refuses the whole import before any write", async t => {
```

with:

```js
test("a refused document and a refused ledger are reported once, and no scratch copy is kept", async t => {
  const s = await setup(t);
  const tmp = scratch("dms-tmp-");
  s.stub.db.failures.push({ method: "POST", path: "/api/v1/documents", status: 422, detail: "refused" });
  s.stub.db.failures.push({ method: "POST", path: "/api/v1/worklog/entries", status: 422, detail: "refused" });
  const result = await run(["import"], { cwd: s.repo, env: { ...s.env, TMPDIR: tmp, TMP: tmp, TEMP: tmp } });
  assert.equal(result.code, 1, result.stdout);
  assert.equal(result.stdout.match(/darkmem refused/g)?.length, 2, result.stdout);
  assert.match(result.stdout, /^failed: sdd\/p1\/progress\.md: darkmem refused an entry: refused$/m);
  assert.doesNotMatch(result.stdout, /a pull of darkmem's copy differs/);
  assert.deepEqual(fs.readdirSync(tmp).filter(name => name.startsWith("darkmem-import-")), []);
});

test("an empty source file refuses the whole import before any write", async t => {
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `timeout 300 node --test plugins/dforge/tests/darkmem-sync/push.test.mjs`
Expected: FAIL, 2 tests: the deleted-document test finds no `note: dforge/b.md: …` line, and the manifest test counts 2 manifest reads, not 1.

Run: `timeout 300 node --test plugins/dforge/tests/darkmem-sync/import.test.mjs`
Expected: FAIL, 1 test: the output also holds `failed: dforge/plans/p1.md: a pull of darkmem's copy differs from the source; compare under …/darkmem-import-…` and the same line for `sdd/p1/progress.md`, and the scratch directory is left in `tmp`.

- [ ] **Step 3: Implement**

`plugins/dforge/scripts/lib/darkmem-push.mjs`. Replace the end of the comment above `archiveDeleted` and its signature:

```js
// back. A missing docs root archives nothing: a lost mirror is not a request
// to archive every document.
async function archiveDeleted(context) {
```

with:

```js
// back. A missing docs root archives nothing: a lost mirror is not a request
// to archive every document. `manifest` is the listing pushDocuments read this
// run, or null; a deleted document is never put, so its entry is as read.
async function archiveDeleted(context, manifest) {
```

In `archiveDeleted`, replace:

```js
  let remote;
  try {
    remote = new Map((await client.manifest(cfg.project, DOC_PREFIX)).map(item => [item.uri, item]));
  } catch (error) {
    failItem(report, "document manifest", error, "; no document archived");
```

with:

```js
  let remote;
  try {
    remote = new Map((manifest ?? await client.manifest(cfg.project, DOC_PREFIX)).map(item => [item.uri, item]));
  } catch (error) {
    failItem(report, "document manifest", error, "; no document archived");
```

and replace:

```js
      // Gone from darkmem too, perhaps by this mirror's own move whose answer
      // was lost: nothing is left to archive.
      delete state.documents[uri];
```

with:

```js
      // Gone from darkmem too, perhaps by this mirror's own move whose answer
      // was lost: nothing is left to archive.
      report.notes.push(`${uri}: deleted locally and already gone from darkmem; its record is dropped`);
      delete state.documents[uri];
```

Above `pushDocuments`, replace:

```js
async function pushDocuments(context) {
```

with:

```js
// Answers darkmem's document manifest when it read one, else null.
async function pushDocuments(context) {
```

In `pushDocuments`, replace:

```js
  if (!changed.length) return;
  let remote;
  try {
    remote = new Map((await client.manifest(cfg.project, DOC_PREFIX)).map(item => [item.uri, item.content_hash]));
  } catch (error) {
    failItem(report, "document manifest", error, "; no document pushed");
    return;
  }
```

with:

```js
  if (!changed.length) return null;
  let manifest;
  try {
    manifest = await client.manifest(cfg.project, DOC_PREFIX);
  } catch (error) {
    failItem(report, "document manifest", error, "; no document pushed");
    return null;
  }
  const remote = new Map(manifest.map(item => [item.uri, item.content_hash]));
```

At the end of `pushDocuments`, replace:

```js
    try {
      await pushDocument(context, item, remote);
    } catch (error) {
      failItem(report, item.uri, error);
    }
  }
}
```

with:

```js
    try {
      await pushDocument(context, item, remote);
    } catch (error) {
      failItem(report, item.uri, error);
    }
  }
  return manifest;
}
```

In `push`, replace:

```js
  await pushDocuments(context);
  if (families.documents) await archiveDeleted(context);
```

with:

```js
  const manifest = await pushDocuments(context);
  if (families.documents) await archiveDeleted(context, manifest);
```

`plugins/dforge/scripts/lib/darkmem-import.mjs`. In `verify`, replace:

```js
    const differing = [
      ...snapshot.documents.filter(d => !sameBytes(uriToLocal(scratchRoots, d.uri), d.buffer)).map(d => d.uri),
      ...snapshot.ledgers.filter(l => !sameBytes(path.join(scratchRoots.workRoot, "sdd", l.slug, "progress.md"), l.buffer)).map(l => `sdd/${l.slug}/progress.md`),
    ];
```

with:

```js
    // A refused document or ledger (no id) was reported where darkmem refused
    // it and was never filed, so it has no copy to compare.
    const differing = [
      ...snapshot.documents.filter(d => !d.refused && !sameBytes(uriToLocal(scratchRoots, d.uri), d.buffer)).map(d => d.uri),
      ...snapshot.ledgers.filter(l => l.id && !sameBytes(path.join(scratchRoots.workRoot, "sdd", l.slug, "progress.md"), l.buffer))
        .map(l => `sdd/${l.slug}/progress.md`),
    ];
```

In `importRepository`'s document loop, replace:

```js
      report.failures.push(`${doc.uri}: darkmem refused it: ${error.detail}`);
```

with:

```js
      report.failures.push(`${doc.uri}: darkmem refused it: ${error.detail}`);
      doc.refused = true;
```

(A refused ledger needs no mark: `importLedger` already sets `ledger.id = null` when darkmem refuses it.)

- [ ] **Step 4: Run the tests to verify they pass**

Run: `timeout 300 node --test plugins/dforge/tests/darkmem-sync/push.test.mjs plugins/dforge/tests/darkmem-sync/import.test.mjs`
Expected: PASS

Run: `timeout 600 bash plugins/dforge/tests/darkmem-sync.test.sh`
Expected: PASS (reconcile's progress move calls `importLedger`; the cli and opt-in suites run push)

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/scripts/lib/darkmem-push.mjs plugins/dforge/scripts/lib/darkmem-import.mjs plugins/dforge/tests/darkmem-sync/push.test.mjs plugins/dforge/tests/darkmem-sync/import.test.mjs
git commit -m "fix(darkmem): import refusals and archive notes"
```

---

### Task 25: Guard pull's removal of vanished documents

**Files:**
- Modify: `plugins/dforge/scripts/lib/darkmem-pull.mjs`
- Modify: `plugins/dforge/tests/darkmem-sync/stub-server.mjs`
- Test: `plugins/dforge/tests/darkmem-sync/pull.test.mjs`
- Test: `plugins/dforge/tests/darkmem-sync/restore.test.mjs`

**Interfaces:**
- Consumes: None
- Produces: None

**Items:** DM 35, DM 37, DR 34

**Depends on:** Task 22
**Implementer:** dr-superpowers:impl-sonnet-high
**Evaluation:** files 2 - spec 0 - coupling 0 - risk 3 = 5

- [ ] **Step 1: Write the failing tests**

The tests prove four things:
- An exactly full last page of workstreams ends the listing (DM 35).
- A vanished document whose local copy cannot be read is one item's failure, not a crash, and the pull goes on (DM 37, failItem half).
- A case-only rename on darkmem that also edits the document never removes the shared local file (DM 37, case-twin half).
- A synced archive uri is never removed (DM 37's `isArchiveUri` guard, coverage only).

DR 34's restore case also asserts its exit code (coverage only).

In `plugins/dforge/tests/darkmem-sync/pull.test.mjs`, append at the end of the file, after the last test, which ends with:

```js
  assert.deepEqual(Object.keys(s.state().documents), ["dforge/A.md"]);
});
```

the following:

```js
test("a case-only rename on darkmem that also edits it keeps the file a case-insensitive file system shares", async t => {
  const s = await setup(t);
  await s.seed.putDocument({ project: "proj", uri: "dforge/a.md", content: "a\n" });
  await s.pull();
  const id = s.stub.db.documents.get("proj\u0000dforge/a.md").id;
  await s.seed.moveDocument(id, { uri: "dforge/A.md" });
  await s.seed.putDocument({ project: "proj", uri: "dforge/A.md", content: "A edited\n", expectedHash: sha("a\n") });
  // A hard link stands in for a case-insensitive file system: both names reach one file.
  fs.linkSync(path.join(s.docsRoot, "a.md"), path.join(s.docsRoot, "A.md"));
  const result = await s.pull();
  assert.equal(result.code, 1, result.stdout + result.stderr);
  assert.match(result.stdout, /^conflict: dforge\/A\.md: changed locally and on darkmem; move the local file aside/m);
  assert.doesNotMatch(result.stdout, /removed/);
  assert.equal(read(path.join(s.docsRoot, "a.md")), "a\n");
  assert.deepEqual(Object.keys(s.state().documents), []);
});

test("a vanished document whose local copy cannot be read is one failure, and the pull goes on", async t => {
  const s = await setup(t);
  await s.seed.putDocument({ project: "proj", uri: "dforge/a.md", content: "a\n" });
  await s.seed.putDocument({ project: "proj", uri: "dforge/b.md", content: "b\n" });
  assert.equal((await s.pull()).code, 0);
  const id = uri => s.stub.db.documents.get(`proj\u0000${uri}`).id;
  await s.seed.moveDocument(id("dforge/a.md"), { uri: "dforge/archive/20261013T091502Z/a.md" });
  await s.seed.moveDocument(id("dforge/b.md"), { uri: "dforge/archive/20261013T091502Z/b.md" });
  fs.rmSync(path.join(s.docsRoot, "a.md"));
  fs.mkdirSync(path.join(s.docsRoot, "a.md", "inner"), { recursive: true });
  const result = await s.pull();
  assert.equal(result.code, 1, result.stdout + result.stderr);
  assert.doesNotMatch(result.stderr, /unexpected error/);
  assert.match(result.stdout, /^failed: dforge\/a\.md: archived or deleted on darkmem, and the local copy could not be checked or removed \(\w+\); it stays$/m);
  assert.match(result.stdout, /darkmem-sync pull: 0 documents, 0 ledgers, 0 checkpoints, 1 removed; 0 conflicts, 1 failures/);
  assert.equal(fs.existsSync(path.join(s.docsRoot, "b.md")), false, "the next vanished document is still removed");
  assert.ok(fs.statSync(path.join(s.docsRoot, "a.md")).isDirectory());
  assert.deepEqual(Object.keys(s.state().documents), ["dforge/a.md"]);
});

test("a synced archive uri is never removed, even once darkmem no longer files it", async t => {
  const s = await setup(t);
  await s.seed.putDocument({ project: "proj", uri: "dforge/a.md", content: "a\n" });
  assert.equal((await s.pull()).code, 0);
  const archived = "dforge/archive/20261013T091502Z/old.md";
  const file = path.join(s.docsRoot, "archive", "20261013T091502Z", "old.md");
  write(file, "old\n");
  const state = s.state();
  state.documents[archived] = sha("old\n");
  fs.writeFileSync(path.join(s.mirror, ".sync-state.json"), JSON.stringify(state));
  const result = await s.pull();
  assert.equal(result.code, 0, result.stdout + result.stderr);
  assert.doesNotMatch(result.stdout, /removed/);
  assert.equal(read(file), "old\n");
  assert.equal(s.state().documents[archived], sha("old\n"));
});

test("a workstream list whose last page is exactly full ends without an empty page", async t => {
  const s = await setup(t, { pageSize: 2 });
  await s.seed.append({ project: "proj", workstream: "p1", entries: [{ kind: "ledger", body: "one\n" }] });
  await s.seed.append({ project: "proj", workstream: "p2", entries: [{ kind: "ledger", body: "two\n" }] });
  assert.equal((await s.pull()).code, 0);
  const lists = s.stub.db.requests.filter(r => r.path === "/api/v1/worklog/workstreams");
  assert.equal(lists.length, 1, "two open workstreams fill one page of two, and no empty page follows");
  assert.equal(read(path.join(s.workRoot, "sdd", "p2", "progress.md")), "two\n");
});
```

In `plugins/dforge/tests/darkmem-sync/restore.test.mjs`, in the test `restore refuses an occupied uri or a name with no archived copy, and needs documents applied darkmem`, replace this line:

```js
  assert.match((await s.sync("restore", "docs/forge/b.md")).stdout, /^refused: no archived copy of dforge\/b\.md on darkmem$/m);
```

with:

```js
  const legacy = await s.sync("restore", "docs/forge/b.md");
  assert.equal(legacy.code, 1);
  assert.match(legacy.stdout, /^refused: no archived copy of dforge\/b\.md on darkmem$/m);
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `timeout 300 node --test plugins/dforge/tests/darkmem-sync/pull.test.mjs plugins/dforge/tests/darkmem-sync/restore.test.mjs`

Expected: FAIL. Three new pull tests fail:
- The case-only rename with an edit: the pull removes `a.md` ("1 removed" in the summary), because the twin lookup reads only the sync state.
- The unreadable vanished copy: the pull exits 4 with `darkmem-sync: unexpected error: ... EISDIR`, because `localHash` throws outside any guard.
- The exactly full workstream page: two list requests, because the stub answers `next_before` on a full last page.

The archive-uri test and the restore case pass. Those were coverage gaps.

- [ ] **Step 3: Implement**

In `plugins/dforge/tests/darkmem-sync/stub-server.mjs`, in the revisions route, replace:

```js
      const items = (doc.revisions ?? []).filter(r => r.id < before).reverse().slice(0, limit);
      return send(200, { document_id: doc.id, items, next_before: items.length === limit ? items.at(-1).id : null });
```

with:

```js
      const all = (doc.revisions ?? []).filter(r => r.id < before).reverse();
      const items = all.slice(0, limit);
      return send(200, { document_id: doc.id, items, next_before: all.length > limit ? items.at(-1).id : null });
```

In the same file, in the workstreams list route, replace:

```js
      const items = all.slice(start, start + limit);
      return send(200, { items: items.map(wsOut), next_before: items.length === limit ? items.at(-1).id : null });
```

with:

```js
      const items = all.slice(start, start + limit);
      return send(200, { items: items.map(wsOut), next_before: start + limit < all.length ? items.at(-1).id : null });
```

In `plugins/dforge/scripts/lib/darkmem-pull.mjs`, replace the whole of `removeVanished` with its comment, from:

```js
// A synced document darkmem no longer holds was archived or deleted
// elsewhere: an unchanged local copy goes with it, an edited one stays.
function removeVanished({ roots, state, persist, report }, filed) {
```

through the function's closing lines:

```js
    delete state.documents[uri];
    persist();
  }
}
```

with:

```js
// A synced document darkmem no longer holds was archived or deleted
// elsewhere: an unchanged local copy goes with it, an edited one stays. A
// name that case-folds to a uri darkmem still files, and reaches the same
// file, is that document on a case-insensitive file system, so it is never
// removed. A copy that cannot be read or removed is one item's failure.
function removeVanished({ roots, state, persist, report }, filed) {
  for (const uri of Object.keys(state.documents).sort()) {
    if (filed.has(uri) || uriFamily(uri) !== "documents" || isArchiveUri(uri)) continue;
    const file = uriToLocal(roots, uri);
    if (!file) continue;
    const twin = [...filed].find(other => other !== uri && !isArchiveUri(other) && other.toLowerCase() === uri.toLowerCase());
    if (twin && sameFile(file, uriToLocal(roots, twin))) {
      delete state.documents[uri];
      persist();
      continue;
    }
    try {
      // Hashed directly before the removal, with nothing in between.
      const local = localHash(file);
      if (local !== null && local !== state.documents[uri]) {
        report.conflicts.push(`${uri}: archived or deleted on darkmem, and changed locally; the local file stays — push it under a new name, or delete it`);
        continue;
      }
      if (local !== null) {
        fs.rmSync(file);
        report.counts.removed = (report.counts.removed ?? 0) + 1;
      }
    } catch (error) {
      report.failures.push(`${uri}: archived or deleted on darkmem, and the local copy could not be checked or removed (${error.code}); it stays`);
      continue;
    }
    delete state.documents[uri];
    persist();
  }
}
```

`failItem` is not used here on purpose: it rethrows every error that is not darkmem's HTTP answer, so it cannot hold a file-system error.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `timeout 300 node --test plugins/dforge/tests/darkmem-sync/pull.test.mjs plugins/dforge/tests/darkmem-sync/restore.test.mjs plugins/dforge/tests/darkmem-sync/client.test.mjs`

Expected: PASS. `client.test.mjs` exercises the stub's paging and revisions routes.

Then run every darkmem-sync suite, since every suite uses the stub:

Run: `timeout 600 bash plugins/dforge/tests/darkmem-sync.test.sh`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/scripts/lib/darkmem-pull.mjs plugins/dforge/tests/darkmem-sync/stub-server.mjs plugins/dforge/tests/darkmem-sync/pull.test.mjs plugins/dforge/tests/darkmem-sync/restore.test.mjs
git commit -m "fix(darkmem): guard removals in pull"
```

---

### Task 26: Harden reconcile's document moves

**Files:**
- Modify: `plugins/dforge/scripts/lib/darkmem-reconcile.mjs`
- Test: `plugins/dforge/tests/darkmem-sync/reconcile.test.mjs`

**Interfaces:**
- Consumes: None
- Produces: `fileHash(file)` and `NOT_A_FILE`, exported from `darkmem-reconcile.mjs`. `fileHash` answers the file's SHA-256, `null` when nothing is there, or `NOT_A_FILE` for a directory or other non-file.

**Items:** DM 28, DM 33, DM 39, DM 40

**Depends on:** Task 21, Task 25
**Implementer:** dr-superpowers:impl-sonnet-medium
**Evaluation:** files 1 - spec 0 - coupling 0 - risk 3 = 4

- [ ] **Step 1: Write the failing tests**

The tests prove these points:
- `nameSpellings` strips a trailing slash (DM 33's JavaScript half).
- `fileHash` answers a sentinel for a directory (DM 39).
- Uncommitted changes print raw paths (DM 39).
- The recheck refusal names what changed (DM 28).
- A git grep killed before it finishes is named (DM 28 and DM 39).
- A file at `docs/dforge` and a linked mirror docs root refuse the move back (DM 40).
- A mirror rename that fails leaves the sync state intact and refuses with one line (DM 40).

In `plugins/dforge/tests/darkmem-sync/reconcile.test.mjs`, replace the import block:

```js
import {
  inProgress, inProgressReason, nameSpellings, pendingFamilies, refreshContext, stayLine,
} from "../../scripts/lib/darkmem-reconcile.mjs";
```

with:

```js
import { utcStamp } from "../../scripts/lib/darkmem-mirror.mjs";
import {
  NOT_A_FILE, fileHash, inProgress, inProgressReason, nameSpellings, pendingFamilies, refreshContext, stayLine,
} from "../../scripts/lib/darkmem-reconcile.mjs";
```

In the test `a document name has one key under every prefix`, after this line:

```js
  assert.deepEqual(nameSpellings("/abs/docs/superpowers/a.md"), ["/abs/docs/superpowers/a.md"]);
```

add:

```js
  assert.deepEqual(nameSpellings("docs/superpowers/"), ["docs/dforge", "docs/forge", "docs/superpowers"]);
  assert.deepEqual(nameSpellings("docs/forge/plans/"), ["docs/dforge/plans", "docs/forge/plans", "docs/superpowers/plans"]);
```

Directly after that test (it ends with the lines just edited and `});`), and before `test("pending families are those whose configured store differs from the applied one", () => {`, add:

```js
test("a directory where a document should be hashes as a non-file instead of throwing", () => {
  const dir = scratch("dms-hash-");
  assert.equal(fileHash(dir), NOT_A_FILE);
  assert.equal(fileHash(path.join(dir, "absent.md")), null);
  write(path.join(dir, "a.md"), "a\n");
  assert.equal(fileHash(path.join(dir, "a.md")), sha("a\n"));
});
```

Before the comment line `// Documents applied darkmem and configured local, darkmem holding two of them.` (directly above `async function darkmemDocs(`), add:

```js
test("uncommitted changes are named by their raw paths, not git's quoted ones", async t => {
  const s = await docsRepo(t);
  write(path.join(s.repo, "docs", "dforge", "spécs", "naïve.md"), "new\n");
  const result = await s.reconcile();
  assert.equal(result.code, 1, result.stdout + result.stderr);
  assert.match(result.stdout, /^darkmem-sync reconcile: documents stay local \(configured darkmem\): docs\/dforge has uncommitted changes$/m);
  assert.ok(result.stdout.includes("  ?? docs/dforge/spécs/naïve.md\n"), result.stdout);
  assert.deepEqual(writes(s.stub), []);
});

test("a file the move cannot carry, committed during the pull, is named in the refusal", async t => {
  let repo;
  let committed = false;
  const s = await docsRepo(t, undefined, {
    stub: {
      onRequest: request => {
        if (!repo || committed || request.path !== "/api/v1/documents/by-uri") return;
        committed = true;
        write(at(repo, "docs/dforge/.hidden.md"), "hidden\n");
        commitAll(repo, "hidden");
      },
    },
  });
  repo = s.repo;
  const result = await s.reconcile();
  assert.equal(result.code, 1, result.stdout + result.stderr);
  assert.match(result.stdout, /^darkmem-sync reconcile: documents stay local \(configured darkmem\): docs\/dforge changed during the move; the repository copy stays$/m);
  assert.ok(result.stdout.includes("  docs/dforge/.hidden.md: a dot name, which the mirror never syncs\n"), result.stdout);
  assert.equal(git(s.repo, "diff", "--cached", "--name-only"), "");
  assert.deepEqual(s.stores(), { documents: "local", progress: "local" });
});

test("a citation search killed before it finishes is named in the move's details", { skip: process.platform === "win32" }, async t => {
  const s = await docsRepo(t);
  const realGit = process.env.PATH.split(path.delimiter).map(dir => path.join(dir, "git")).find(file => fs.existsSync(file));
  const bin = scratch("dms-git-");
  fs.writeFileSync(path.join(bin, "git"), `#!/bin/sh\nfor a in "$@"; do [ "$a" = "grep" ] && kill -KILL $$; done\nexec "${realGit}" "$@"\n`, { mode: 0o755 });
  const result = await reconcile(s.repo, { ...s.env, PATH: `${bin}${path.delimiter}${s.env.PATH ?? process.env.PATH}` });
  assert.equal(result.code, 0, result.stdout + result.stderr);
  assert.match(result.stdout, /git grep failed: it did not finish \(SIGKILL\); check for docs\/superpowers\/, docs\/forge\/ and docs\/dforge\/ citations before you commit/);
});

```

At the end of the file, after the last test (`documents stay darkmem when git check-ignore fails`, which ends with):

```js
  assert.equal(fs.existsSync(s.docsRoot), true);
  assert.deepEqual(s.stores(), { documents: "darkmem", progress: "local" });
});
```

append:

```js
test("a file at docs/dforge refuses the move back, and nothing is copied", async t => {
  const s = await darkmemDocs(t);
  write(path.join(s.repo, "docs", "dforge"), "not a directory\n");
  const result = await s.reconcile();
  assert.equal(result.code, 1, result.stdout + result.stderr);
  assert.ok(result.stdout.includes("darkmem-sync reconcile: documents stay darkmem (configured local): docs/dforge is not a directory; nothing was copied\n"), result.stdout);
  assert.equal(read(path.join(s.repo, "docs", "dforge")), "not a directory\n");
  assert.equal(fs.existsSync(s.docsRoot), true);
  assert.deepEqual(s.stores(), { documents: "darkmem", progress: "local" });
});

test("a mirror docs root that is a symbolic link refuses the move back, and nothing is copied or set aside", { skip: process.platform === "win32" }, async t => {
  const s = await darkmemDocs(t);
  const outside = scratch("dms-link-");
  write(path.join(outside, "specs", "a.md"), "# A\n");
  write(path.join(outside, "plans", "p.md"), "# P\n");
  fs.mkdirSync(s.mirror, { recursive: true });
  fs.symlinkSync(outside, s.docsRoot);
  const result = await s.reconcile();
  assert.equal(result.code, 1, result.stdout + result.stderr);
  assert.ok(result.stdout.includes(`darkmem-sync reconcile: documents stay darkmem (configured local): the mirror's docs root ${s.docsRoot} is a symbolic link; nothing was copied\n`), result.stdout);
  assert.equal(fs.existsSync(path.join(s.repo, "docs", "dforge")), false);
  assert.ok(fs.lstatSync(s.docsRoot).isSymbolicLink(), "the link is not set aside");
  assert.deepEqual(s.stores(), { documents: "darkmem", progress: "local" });
});

test("a mirror copy that cannot be set aside refuses the move, keeps the sync state, and a rerun finishes it", async t => {
  const s = await darkmemDocs(t);
  assert.equal((await s.pull()).code, 0);
  // Every name the aside rename can take for the next minute is a non-empty directory.
  const now = Date.now();
  const blockers = [];
  for (let i = 0; i < 60; i += 1) {
    const dir = path.join(s.mirror, `dforge-moved-${utcStamp(new Date(now + i * 1000))}`);
    blockers.push(dir);
    write(path.join(dir, "keep.md"), "taken\n");
  }
  const result = await s.reconcile();
  assert.equal(result.code, 1, result.stdout + result.stderr);
  assert.doesNotMatch(result.stderr, /unexpected error/);
  assert.match(result.stdout, /^darkmem-sync reconcile: documents stay darkmem \(configured local\): the mirror's copy could not be set aside \(\w+\); docs\/dforge holds the copied files, and the next reconcile finishes the move$/m);
  assert.deepEqual(Object.keys(JSON.parse(read(path.join(s.mirror, ".sync-state.json"))).documents).sort(), ["dforge/plans/p.md", "dforge/specs/a.md"]);
  assert.equal(fs.existsSync(s.docsRoot), true);
  assert.deepEqual(s.stores(), { documents: "darkmem", progress: "local" });
  for (const dir of blockers) fs.rmSync(dir, { recursive: true });
  const again = await s.reconcile();
  assert.equal(again.code, 0, again.stdout + again.stderr);
  assert.match(again.stdout, /^darkmem-sync reconcile: documents moved to local$/m);
  assert.equal(read(path.join(s.repo, "docs", "dforge", "specs", "a.md")), "# A\n");
});
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `timeout 300 node --test plugins/dforge/tests/darkmem-sync/reconcile.test.mjs`

Expected: FAIL. The file does not load: `SyntaxError: The requested module '../../scripts/lib/darkmem-reconcile.mjs' does not provide an export named 'NOT_A_FILE'`. That load failure is the first failing check.

To see the behavioural failures as well, temporarily drop `NOT_A_FILE, fileHash, ` from the import and comment out the `fileHash` test, then run again. With that change, these tests fail:
- The trailing-slash spellings: `docs/dforge/` keeps its slash.
- The raw-path test: git prints `"docs/dforge/sp\303\251cs/na\303\257ve.md"`.
- The committed-during-the-pull test: the refusal has no detail lines.
- The killed grep: a null status is silent.
- The file at `docs/dforge`: exit 4, `ENOTDIR` thrown by the link walk.
- The linked docs root: the move succeeds through the link.
- The blocked rename: exit 4, and the state's documents are already empty.

Restore the import and the `fileHash` test before Step 3.

- [ ] **Step 3: Implement**

All edits are in `plugins/dforge/scripts/lib/darkmem-reconcile.mjs`.

1. `runGit` also answers the signal that ended git. Replace:

```js
  return { status: result.status, stdout: result.stdout ?? "", stderr: result.stderr ?? "" };
```

with:

```js
  return { status: result.status, signal: result.signal, stdout: result.stdout ?? "", stderr: result.stderr ?? "" };
```

2. In `nameSpellings`, replace:

```js
  const text = String(name).replace(/^\.\//, "");
```

with:

```js
  const text = String(name).replace(/^\.\//, "").replace(/(.)\/+$/, "$1");
```

3. Replace:

```js
const fileHash = file => (fs.existsSync(file) ? sha256(fs.readFileSync(file)) : null);
```

with:

```js
// A directory or other non-file where a document belongs reads as a hash no
// file has, so it is reported as differing instead of throwing EISDIR.
export const NOT_A_FILE = "not a regular file";

export function fileHash(file) {
  const stat = fs.statSync(file, { throwIfNoEntry: false });
  if (!stat) return null;
  return stat.isFile() ? sha256(fs.readFileSync(file)) : NOT_A_FILE;
}

// git status --porcelain -z as "XY path" lines with raw paths, which plain
// --porcelain would C-quote; a rename or copy reads "XY from -> to".
function statusLines(stdout) {
  const entries = stdout.split("\0");
  const lines = [];
  for (let i = 0; i < entries.length; i += 1) {
    const item = entries[i];
    if (item.length < 4) continue;
    if ("RC".includes(item[0])) {
      lines.push(`${item.slice(0, 3)}${entries[i + 1]} -> ${item.slice(3)}`);
      i += 1;
    } else {
      lines.push(item);
    }
  }
  return lines;
}
```

4. In `documentsToDarkmem`, replace:

```js
  const dirty = runGit(cfg.repoRoot, ["status", "--porcelain", "--untracked-files=all", "--", rel]);
  if (dirty.status !== 0) return { moved: false, reason: `git status failed: ${dirty.stderr.trim()}`, details: [] };
  if (dirty.stdout.trim()) return { moved: false, reason: `${rel} has uncommitted changes`, details: dirty.stdout.split("\n").filter(Boolean) };
```

with:

```js
  const dirty = runGit(cfg.repoRoot, ["status", "--porcelain", "-z", "--untracked-files=all", "--", rel]);
  if (dirty.status !== 0) return { moved: false, reason: `git status failed: ${dirty.stderr.trim()}`, details: [] };
  const changes = statusLines(dirty.stdout);
  if (changes.length) return { moved: false, reason: `${rel} has uncommitted changes`, details: changes };
```

5. In `documentsToDarkmem`, replace:

```js
    return { moved: false, reason: `${rel} changed during the move; the repository copy stays`, details: [] };
```

with:

```js
    return { moved: false, reason: `${rel} changed during the move; the repository copy stays`, details: [...(again.failed ? [again.failed] : []), ...again.problems] };
```

6. In `documentsToDarkmem`, replace:

```js
  if (cites.status > 1) details.push(`git grep failed: ${cites.stderr.trim()}; check for docs/superpowers/, docs/forge/ and docs/dforge/ citations before you commit`);
```

with:

```js
  // 1 is "no match"; anything else, a killed or timed-out run's null included, is a failure.
  if (cites.status !== 0 && cites.status !== 1) {
    const why = cites.stderr.trim() || `it did not finish (${cites.signal ?? "no exit status"})`;
    details.push(`git grep failed: ${why}; check for docs/superpowers/, docs/forge/ and docs/dforge/ citations before you commit`);
  }
```

7. In `documentsToLocal`, replace:

```js
  const { cfg, client, state, persist } = context;
  const mirror = mirrorRoots(cfg, "documents");
  if (!offline) {
```

with:

```js
  const { cfg, client, state, persist } = context;
  const mirror = mirrorRoots(cfg, "documents");
  // A linked docs root would be read through, copied from and set aside as a link.
  if (fs.lstatSync(mirror.docsRoot, { throwIfNoEntry: false })?.isSymbolicLink()) {
    return { moved: false, reason: `the mirror's docs root ${mirror.docsRoot} is a symbolic link; nothing was copied`, details: [] };
  }
  if (!offline) {
```

8. In `documentsToLocal`, replace:

```js
  // Copies and equality reads must not follow a link out of the repository.
  const checked = new Set(["docs", DOCS]);
```

with:

```js
  // mkdirSync cannot make docs/dforge where a file stands. A link is left to
  // the walk below, which names it.
  for (const rel of ["docs", DOCS]) {
    const stat = fs.lstatSync(path.join(cfg.repoRoot, ...rel.split("/")), { throwIfNoEntry: false });
    if (!stat || stat.isSymbolicLink()) break;
    if (!stat.isDirectory()) return { moved: false, reason: `${rel} is not a directory; nothing was copied`, details: [] };
  }
  // Copies and equality reads must not follow a link out of the repository.
  const checked = new Set(["docs", DOCS]);
```

9. In `documentsToLocal`, replace:

```js
  for (const uri of Object.keys(state.documents)) {
    if (uriFamily(uri) === "documents") delete state.documents[uri];
  }
  persist();
  const aside = path.join(cfg.mirror, `${DOC_PREFIX}-moved-${utcStamp()}`);
  if (fs.existsSync(mirror.docsRoot)) fs.renameSync(mirror.docsRoot, aside);
```

with:

```js
  // Set aside before the sync state forgets the documents, so a failed rename
  // leaves a state that still describes the mirror.
  const aside = path.join(cfg.mirror, `${DOC_PREFIX}-moved-${utcStamp()}`);
  if (fs.existsSync(mirror.docsRoot)) {
    try {
      fs.renameSync(mirror.docsRoot, aside);
    } catch (error) {
      return { moved: false, reason: `the mirror's copy could not be set aside (${error.code}); docs/dforge holds the copied files, and the next reconcile finishes the move`, details: [] };
    }
  }
  for (const uri of Object.keys(state.documents)) {
    if (uriFamily(uri) === "documents") delete state.documents[uri];
  }
  persist();
```

Keep every other refusal in `documentsToDarkmem` and `documentsToLocal` exactly as it is.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `timeout 300 node --test plugins/dforge/tests/darkmem-sync/reconcile.test.mjs`

Expected: PASS

Reconcile runs at session start, and `reconcile-progress.test.mjs` imports this module, so run the whole darkmem-sync set too:

Run: `timeout 600 bash plugins/dforge/tests/darkmem-sync.test.sh`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/scripts/lib/darkmem-reconcile.mjs plugins/dforge/tests/darkmem-sync/reconcile.test.mjs
git commit -m "fix(darkmem): harden reconcile's document moves"
```

---

### Task 27: Harden the progress move into darkmem

**Files:**
- Modify: `plugins/dforge/scripts/lib/darkmem-progress-move.mjs`
- Modify: `plugins/dforge/scripts/lib/darkmem-reconcile.mjs` (export `planFinished` only)
- Test: `plugins/dforge/tests/darkmem-sync/reconcile-progress.test.mjs`

**Interfaces:**
- Consumes: None
- Produces: `planFinished(cfg, checkout, identity)` exported from `darkmem-reconcile.mjs`. Its signature and behaviour are unchanged.

**Items:** DM 28, DM 30, DM 41, DM 42

**Depends on:** Task 22, Task 26
**Implementer:** dr-superpowers:impl-sonnet-high
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 3 = 5

- [ ] **Step 1: Write the failing tests**

The tests prove these points:
- An `sdd` that cannot be listed is a problem, not a crash (DM 41, DM 42).
- A symbolic-linked `progress.md` is a problem and is not read through (DM 41).
- A source that cannot be moved aside ends the move with one line, and a rerun finishes it (DM 30).
- `fileLatest`'s workstream follows its plan: open while active, closed once `completed.md` records it, even when `fileLatest` created it (DM 42).

The rule has one stated limit: `fileLatest` never reopens a workstream by
itself. An append reopens a closed workstream (darkmem does that), so an active
plan's workstream is open after any new checkpoint. When darkmem already holds
an identical checkpoint, nothing is appended and a closed workstream stays
closed: reopening it would need a PATCH to `open`, which darkmem's server is not
known to accept (the stub accepts any state, so a test could not show it). Do
not add such a PATCH.
- A refused ledger names what darkmem now holds (DM 42).

Coverage only:
- The `git worktree list` failure (DM 41).
- The post-write in-progress recheck (DM 42).
- DM 28's checkpoint read-back guard.

In `plugins/dforge/tests/darkmem-sync/reconcile-progress.test.mjs`, replace:

```js
import { ledgerPieces } from "../../scripts/lib/darkmem-mirror.mjs";
```

with:

```js
import { ledgerPieces, utcStamp } from "../../scripts/lib/darkmem-mirror.mjs";
```

After the test `a progress file or mirror copy that cannot be read is a problem, not a crash`, which ends with:

```js
  assert.deepEqual(checked.problems.map(line => line.replace(mirror, "<mirror>").split(path.sep).join("/")), ["<mirror>/work/sdd/p2/progress.md: could not be read (EISDIR)"]);
});
```

add:

```js
test("a state directory whose sdd cannot be listed is a problem, not a crash", () => {
  const repo = makeRepo();
  write(path.join(repo, ".dforge", "sdd"), "not a directory\n");
  const { problems, sources } = gatherLocalProgress({ repoRoot: repo });
  assert.deepEqual(problems, [`${path.join(repo, ".dforge", "sdd")}: could not be read (ENOTDIR)`]);
  assert.deepEqual(sources, []);
});

test("a symbolic-linked progress file is a problem, and is not read through", { skip: process.platform === "win32" }, () => {
  const repo = makeRepo();
  const outside = path.join(scratch("dms-link-"), "progress.md");
  write(outside, LEDGER("p1"));
  const link = path.join(repo, ".dforge", "sdd", "p1", "progress.md");
  fs.mkdirSync(path.dirname(link), { recursive: true });
  fs.symlinkSync(outside, link);
  const { problems, sources } = gatherLocalProgress({ repoRoot: repo });
  assert.deepEqual(problems, [`${link}: a symbolic link, which the move will not read through`]);
  assert.deepEqual(sources, []);
});

test("a git worktree list that fails is the one problem", () => {
  const missing = path.join(scratch("dms-gone-"), "missing");
  const { problems, files, sources } = gatherLocalProgress({ repoRoot: missing });
  assert.equal(problems.length, 1, problems.join("\n"));
  assert.match(problems[0], /^git worktree list failed in .+missing: \S/);
  assert.deepEqual([files, sources], [[], []]);
});
```

After the test `a handoff note that darkmem reads back different stays local, and nothing is copied or moved`, which ends with:

```js
  assert.deepEqual(movedAside(s.repo), []);
  assert.equal(read(note), "# Handoff p1\n");
});
```

add:

```js
test("a checkpoint that darkmem reads back different stays local, and nothing is copied or moved", async t => {
  const s = await setup(t, "darkmem");
  const latest = path.join(s.repo, ".dforge", "handoff", "latest.md");
  write(latest, LATEST);
  s.stub.db.onRequest = (method, pathname) => {
    if (method !== "GET" || pathname !== "/api/v1/worklog/resume") return;
    for (const ws of s.stub.db.workstreams) for (const entry of ws.entries) if (entry.kind === "checkpoint") entry.body = "altered\n";
  };
  const result = await s.reconcile();
  assert.equal(result.code, 1, result.stdout + result.stderr);
  assert.ok(result.stdout.includes("darkmem-sync reconcile: progress stay local (configured darkmem): a read-back of darkmem's copies differs; nothing was moved locally\n"), result.stdout);
  assert.ok(result.stdout.includes("  handoff/latest.md: darkmem's checkpoint reads back different\n"), result.stdout);
  assert.equal(s.stores().progress, "local");
  assert.deepEqual(movedAside(s.repo), []);
  assert.equal(read(latest), LATEST);
  assert.equal(fs.existsSync(path.join(s.workRoot, "handoff", "latest.md")), false);
});

test("a plan that starts while darkmem is written keeps progress local, and nothing is copied or moved", async t => {
  const s = await setup(t, "darkmem");
  write(path.join(s.repo, ".dforge", "sdd", "p1", "progress.md"), LEDGER("p1"));
  let started = false;
  s.stub.db.onRequest = (method, pathname) => {
    if (started || method !== "POST" || pathname !== "/api/v1/worklog/entries") return;
    started = true;
    write(path.join(s.repo, ".dforge", "sdd", "p3", "progress.md"), LEDGER("p3"));
  };
  const result = await s.reconcile();
  assert.equal(result.code, 1, result.stdout + result.stderr);
  assert.ok(result.stdout.includes("darkmem-sync reconcile: progress stay local (configured darkmem): a plan is in progress: docs/dforge/plans/p3.md\n"), result.stdout);
  assert.equal(s.stores().progress, "local");
  assert.deepEqual(movedAside(s.repo), []);
  assert.equal(fs.existsSync(path.join(s.workRoot, "sdd", "p1", "progress.md")), false);
});

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

test("latest.md filed for an active plan leaves its workstream open, even one that was closed", async t => {
  const s = await setup(t, "darkmem");
  const { workstream } = await s.seed.append({ project: "proj", workstream: "p3", entries: [{ kind: "note", body: "earlier\n" }] });
  await s.seed.updateWorkstream(workstream.id, { state: "closed", retain: true });
  write(path.join(s.repo, ".dforge", "handoff", "latest.md"), "## State\n- Plan: `docs/dforge/plans/p3.md`\n");
  const result = await s.reconcile();
  assert.equal(result.code, 0, result.stdout + result.stderr);
  assert.match(result.stdout, /^ {2}latest\.md filed as a checkpoint of p3$/m);
  assert.equal(s.stub.db.workstreams.find(w => w.key === "p3").state, "open", "p3 is not in completed.md");
});

test("latest.md filed for a completed plan closes the workstream it opens", async t => {
  const s = await setup(t, "darkmem");
  write(path.join(s.repo, ".dforge", "handoff", "latest.md"), "## State\n- Plan: `docs/dforge/plans/p2.md`\n");
  const result = await s.reconcile();
  assert.equal(result.code, 0, result.stdout + result.stderr);
  const ws = s.stub.db.workstreams.find(w => w.key === "p2");
  assert.equal(ws.state, "closed", "completed.md records p2");
  assert.equal(ws.retain, true);
  assert.equal(ws.entries.filter(e => e.kind === "checkpoint").length, 1);
});

test("a ledger darkmem refuses names what darkmem now holds, and nothing is moved locally", async t => {
  const s = await setup(t, "darkmem");
  write(path.join(s.repo, ".dforge", "sdd", "p1", "progress.md"), LEDGER("p1"));
  write(path.join(s.repo, ".dforge", "sdd", "p2", "progress.md"), LEDGER("p2"));
  write(path.join(s.repo, ".dforge", "sdd", "p2", "handoff.md"), "# Handoff p2\n");
  s.stub.db.failures.push({ method: "POST", path: "/api/v1/worklog/entries", status: 422, detail: "refused by the test" });
  const result = await s.reconcile();
  assert.equal(result.code, 1, result.stdout + result.stderr);
  assert.ok(result.stdout.includes("darkmem-sync reconcile: progress stay local (configured darkmem): darkmem refused part of the progress; nothing was moved locally, and darkmem keeps what it accepted\n"), result.stdout);
  assert.ok(result.stdout.includes("  sdd/p1/progress.md: darkmem refused an entry: refused by the test\n"), result.stdout);
  assert.ok(result.stdout.includes("  darkmem now holds in full: sdd/p2/progress.md, dforge/handoff/p2.md\n"), result.stdout);
  assert.equal(s.stores().progress, "local");
  assert.deepEqual(movedAside(s.repo), []);
});
```

In the test `another writer's append during a resumed import refuses the move, and nothing local moves`, replace:

```js
  assert.ok(result.stdout.includes("darkmem-sync reconcile: progress stay local (configured darkmem): darkmem refused part of the progress; nothing was moved locally\n"), result.stdout);
```

with:

```js
  assert.ok(result.stdout.includes("darkmem-sync reconcile: progress stay local (configured darkmem): darkmem refused part of the progress; nothing was moved locally, and darkmem keeps what it accepted\n"), result.stdout);
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `timeout 300 node --test plugins/dforge/tests/darkmem-sync/reconcile-progress.test.mjs`

Expected: FAIL in these tests:
- The unlistable `sdd`: `readdirSync` throws `ENOTDIR`.
- The linked `progress.md`: no problem is reported; the file is read through the link.
- The blocked backup: exit 4, `unexpected error ... EISDIR`.
- The active plan: p3 is re-closed because it was closed before.
- The completed plan: p2 is left open because `fileLatest` created it.
- The refused ledger: the old reason, with no "darkmem now holds" line.
- The resumed-import test: its reason string was updated.

These pass, because those paths were coverage gaps: the worktree-list failure, the checkpoint read-back and the plan-starts-during-the-move tests.

- [ ] **Step 3: Implement**

1. In `plugins/dforge/scripts/lib/darkmem-reconcile.mjs`, replace:

```js
function planFinished(cfg, checkout, identity) {
```

with:

```js
export function planFinished(cfg, checkout, identity) {
```

2. In `plugins/dforge/scripts/lib/darkmem-progress-move.mjs`, replace:

```js
import { inProgressReason } from "./darkmem-reconcile.mjs";
```

with:

```js
import { inProgressReason, planFinished } from "./darkmem-reconcile.mjs";
```

3. In `gatherLocalProgress`, replace:

```js
    // A linked plan directory is not listed as one, so its progress would be
    // left behind without a word.
    const entries = fs.existsSync(sdd) ? fs.readdirSync(sdd, { withFileTypes: true }) : [];
```

with:

```js
    // A linked plan directory is not listed as one, so its progress would be
    // left behind without a word. An sdd that cannot be listed is this
    // checkout's problem, and nothing under it is read.
    let entries;
    try {
      entries = fs.readdirSync(sdd, { withFileTypes: true });
    } catch (error) {
      if (error.code !== "ENOENT") {
        problems.push(`${sdd}: could not be read (${error.code})`);
        continue;
      }
      entries = [];
    }
```

4. In `gatherLocalProgress`, replace:

```js
  for (const item of files) {
    try {
      item.buffer = fs.readFileSync(item.file);
```

with:

```js
  for (const item of files) {
    // A linked file is never read through: it could lead anywhere, a FIFO included.
    if (fs.lstatSync(item.file, { throwIfNoEntry: false })?.isSymbolicLink()) {
      problems.push(`${item.file}: a symbolic link, which the move will not read through`);
      continue;
    }
    try {
      item.buffer = fs.readFileSync(item.file);
```

5. Replace the comment above `fileLatest` and its closing block. After Task 22 the comment reads:

```js
// latest.md becomes a checkpoint of the plan or draft it names, so other
// machines receive it; a workstream that was closed is closed again. One that
// names neither is copied unsent, dated at darkmem's newest checkpoint so a
// pull only replaces it with a newer one. Answers { hash, at, workstream,
// detail }, `workstream` naming the key `at` was read from (null with a null
// `at`), or { problem } when darkmem reads it back different.
```

Replace it with:

```js
// latest.md becomes a checkpoint of the plan or draft it names, so other
// machines receive it. The workstream follows that plan: an append reopens a
// closed one, so it stays open while the plan is active, and it is closed once
// completed.md records the plan, whether this append opened it or found it.
// One that names neither is copied unsent, dated at darkmem's newest
// checkpoint so a pull only replaces it with a newer one. Answers
// { hash, at, workstream, detail }, `workstream` naming the key `at` was read
// from (null with a null `at`), or { problem } when darkmem reads it back
// different.
```

In the same function, replace:

```js
  if (before?.workstream.state === "closed") {
    const after = await client.resume(cfg.project, target.slug);
    if (after.workstream.state !== "closed") await client.updateWorkstream(after.workstream.id, { state: "closed", retain: true });
  }
```

with:

```js
  if (planFinished(cfg, path.dirname(item.stateDir), target.path)) {
    const after = await client.resume(cfg.project, target.slug);
    if (after.workstream.state !== "closed") await client.updateWorkstream(after.workstream.id, { state: "closed", retain: true });
  }
```

6. In `progressToDarkmem`, replace:

```js
    if (report.failures.length) return refuse("darkmem refused part of the progress; nothing was moved locally", report.failures);
```

with:

```js
    if (report.failures.length) {
      // Every handoff note was put (a put darkmem refuses throws), and ids
      // holds each ledger darkmem has in full.
      const held = [
        ...sources.filter(item => item.kind === "ledger" && ids.has(item.slug)).map(item => item.rel),
        ...sources.filter(item => item.kind === "handoff").map(item => item.uri),
      ];
      return refuse("darkmem refused part of the progress; nothing was moved locally, and darkmem keeps what it accepted", [
        ...report.failures,
        held.length ? `darkmem now holds in full: ${held.join(", ")}` : "darkmem now holds none of the progress in full",
        "a refused ledger keeps any entries darkmem accepted before the refusal, in its open workstream",
      ]);
    }
```

7. In `progressToDarkmem`, replace:

```js
  const aside = `moved-${utcStamp()}`;
  const backups = new Set();
  for (const item of files) {
    const target = local(path.join(item.stateDir, aside), item.rel);
    fs.mkdirSync(path.dirname(target), { recursive: true });
    fs.renameSync(item.file, target);
    backups.add(path.join(item.stateDir, aside));
  }
```

with:

```js
  const aside = `moved-${utcStamp()}`;
  const backups = new Set();
  const left = [];
  for (const item of files) {
    const target = local(path.join(item.stateDir, aside), item.rel);
    try {
      fs.mkdirSync(path.dirname(target), { recursive: true });
      fs.renameSync(item.file, target);
      backups.add(path.join(item.stateDir, aside));
    } catch (error) {
      left.push(`${item.file} (${error.code})`);
    }
  }
  // darkmem and the mirror already hold every source, so a rerun finds them
  // filed and moves aside only what is left.
  if (left.length) {
    return refuse(`darkmem and the mirror hold the progress, but ${left.length} sources could not be moved aside: ${left.join(", ")}; reconcile again to finish`);
  }
```

Do not touch the `persist()` call or the `state.checkpoint` / `state.checkpointAt` lines above this block; the earlier checkpointAt task owns them. Keep every other refusal in `progressToDarkmem` as it is.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `timeout 300 node --test plugins/dforge/tests/darkmem-sync/reconcile-progress.test.mjs plugins/dforge/tests/darkmem-sync/reconcile.test.mjs`

Expected: PASS

Then the whole darkmem-sync set, since reconcile also runs from the hooks:

Run: `timeout 600 bash plugins/dforge/tests/darkmem-sync.test.sh`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/scripts/lib/darkmem-progress-move.mjs plugins/dforge/scripts/lib/darkmem-reconcile.mjs plugins/dforge/tests/darkmem-sync/reconcile-progress.test.mjs
git commit -m "fix(darkmem): harden the progress move to darkmem"
```

---

### Task 28: Guard the progress move back to the checkout

**Files:**
- Modify: `plugins/dforge/scripts/lib/darkmem-progress-move.mjs`
- Test: `plugins/dforge/tests/darkmem-sync/reconcile-progress.test.mjs`

**Interfaces:**
- Consumes: `newestCheckpointAt(state)` (Contracts, Task 20), already imported into `darkmem-progress-move.mjs` by Task 22; Task 27's edits to both files.
- Produces: None

**Items:** DM 31, DM 43

**Depends on:** Task 27
**Implementer:** dr-superpowers:impl-sonnet-high
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 3 = 5

- [ ] **Step 1: Write the failing tests**

The tests prove these points:
- A mirror that lost `latest.md` takes darkmem's newest checkpoint again (DM 31).
- An edit landing in the checkout just before a copy is never overwritten (DM 31).
- A copy failing part-way is a refusal and a rerun finishes it (DM 43).
- A symbolic link among the mirror's sources refuses the move (DM 43).
- `renderCheckpoint`'s read failure is a refusal (DM 43, coverage only).

In `plugins/dforge/tests/darkmem-sync/reconcile-progress.test.mjs`, replace (the line as Task 27 left it):

```js
import { ledgerPieces, utcStamp } from "../../scripts/lib/darkmem-mirror.mjs";
import { checkProgressTargets, gatherLocalProgress } from "../../scripts/lib/darkmem-progress-move.mjs";
```

with:

```js
import { emptyState, ledgerPieces, utcStamp } from "../../scripts/lib/darkmem-mirror.mjs";
import { checkProgressTargets, gatherLocalProgress, progressToLocal } from "../../scripts/lib/darkmem-progress-move.mjs";
```

After the test `a primary checkout file that cannot be read keeps progress in darkmem, not a crash`, which ends with:

```js
  assert.ok(result.stdout.includes(`  ${target}: could not be read (EISDIR)\n`), result.stdout);
  assert.equal(s.stores().progress, "darkmem");
});
```

add:

```js
test("a mirror that lost latest.md takes darkmem's newest checkpoint again before the move back", async t => {
  const s = await setup(t, "local");
  await s.seed.append({ project: "proj", workstream: "p1", entries: [{ kind: "ledger", body: LEDGER("p1") }, { kind: "checkpoint", body: LATEST }] });
  assert.equal((await run(["pull"], { cwd: s.repo, env: s.env })).code, 0);
  const mirrored = path.join(s.workRoot, "handoff", "latest.md");
  assert.equal(read(mirrored), LATEST);
  fs.rmSync(mirrored);
  const result = await s.reconcile();
  assert.equal(result.code, 0, result.stdout + result.stderr);
  assert.match(result.stdout, /^darkmem-sync reconcile: progress moved to local$/m);
  assert.equal(read(path.join(s.repo, ".dforge", "handoff", "latest.md")), LATEST);
});

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

test("a symbolic link among the mirror's progress keeps progress in darkmem, and nothing is read through it", { skip: process.platform === "win32" }, async t => {
  const s = await setup(t, "local");
  await s.seed.append({ project: "proj", workstream: "p1", entries: [{ kind: "ledger", body: LEDGER("p1") }] });
  const outside = path.join(scratch("dms-link-"), "progress.md");
  write(outside, LEDGER("p1"));
  const link = path.join(s.workRoot, "sdd", "p1", "progress.md");
  fs.mkdirSync(path.dirname(link), { recursive: true });
  fs.symlinkSync(outside, link);
  const result = await s.reconcile();
  assert.equal(result.code, 1, result.stdout + result.stderr);
  assert.match(result.stdout, /^darkmem-sync reconcile: progress stay darkmem \(configured local\): the mirror's progress is reached through symbolic links; nothing was pulled or copied$/m);
  assert.ok(result.stdout.includes(`  ${link}: a symbolic link in the mirror, which the move will not read through\n`), result.stdout);
  assert.equal(fs.existsSync(path.join(s.repo, ".dforge", "sdd", "p1", "progress.md")), false);
  assert.equal(s.stores().progress, "darkmem");
});

test("a linked mirror ledger is refused before the pull, so newer darkmem content neither reads through nor replaces it", { skip: process.platform === "win32" }, async t => {
  const s = await setup(t, "local");
  await s.seed.append({ project: "proj", workstream: "p1", entries: [{ kind: "ledger", body: LEDGER("p1") }] });
  const outside = path.join(scratch("dms-link-"), "progress.md");
  write(outside, "an older ledger\n");
  const link = path.join(s.workRoot, "sdd", "p1", "progress.md");
  fs.mkdirSync(path.dirname(link), { recursive: true });
  fs.symlinkSync(outside, link);
  const result = await s.reconcile();
  assert.equal(result.code, 1, result.stdout + result.stderr);
  assert.match(result.stdout, /^darkmem-sync reconcile: progress stay darkmem \(configured local\): the mirror's progress is reached through symbolic links; nothing was pulled or copied$/m);
  assert.equal(fs.lstatSync(link).isSymbolicLink(), true);
  assert.equal(fs.readFileSync(outside, "utf8"), "an older ledger\n");
  assert.equal(s.stores().progress, "darkmem");
});

// The move back run directly and offline, over a mirror holding two ledgers,
// so a test can stand in for fs between its reads and its copies.
function offlineMove() {
  const repo = makeRepo();
  const mirror = scratch("dms-mirror-");
  write(path.join(mirror, "work", "sdd", "p1", "progress.md"), LEDGER("p1"));
  write(path.join(mirror, "work", "sdd", "p2", "progress.md"), LEDGER("p2"));
  const context = { cfg: { repoRoot: repo, mirror }, client: null, state: emptyState(), persist: () => {} };
  return { mirror, context, target: slug => path.join(repo, ".dforge", "sdd", slug, "progress.md") };
}

test("an edit that lands in the primary checkout just before a copy is never overwritten", async t => {
  const m = offlineMove();
  const mkdir = fs.mkdirSync;
  t.mock.method(fs, "mkdirSync", (dir, options) => {
    const made = mkdir(dir, options);
    if (dir === path.dirname(m.target("p1")) && !fs.existsSync(m.target("p1"))) fs.writeFileSync(m.target("p1"), "edited meanwhile\n");
    return made;
  });
  const result = await progressToLocal(m.context, { offline: "test" });
  assert.equal(result.moved, false);
  assert.equal(result.reason, "the primary checkout changed during the move; nothing was overwritten");
  assert.deepEqual(result.details, [`${m.target("p1")}: changed during the move; not overwritten`]);
  assert.equal(read(m.target("p1")), "edited meanwhile\n");
  assert.equal(fs.existsSync(path.join(m.mirror, "work")), true, "the mirror's copies are not set aside");
});

test("a copy into the primary checkout that fails part-way is a refusal, not a crash, and a rerun finishes it", async t => {
  const m = offlineMove();
  const copy = fs.copyFileSync;
  let calls = 0;
  t.mock.method(fs, "copyFileSync", (...args) => {
    calls += 1;
    if (calls === 2) throw Object.assign(new Error("injected by the test"), { code: "EIO" });
    return copy(...args);
  });
  const result = await progressToLocal(m.context, { offline: "test" });
  assert.equal(result.moved, false);
  assert.equal(result.reason, "a copy into the primary checkout failed (EIO); the files copied so far stay, and a rerun copies the rest");
  assert.deepEqual(result.details, [`${m.target("p1")}: copied`]);
  assert.equal(fs.existsSync(path.join(m.mirror, "work")), true, "the mirror's copies are not set aside");
  t.mock.restoreAll();
  const again = await progressToLocal(m.context, { offline: "test" });
  assert.equal(again.moved, true, again.reason);
  assert.equal(read(m.target("p1")), LEDGER("p1"));
  assert.equal(read(m.target("p2")), LEDGER("p2"));
});
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `timeout 300 node --test plugins/dforge/tests/darkmem-sync/reconcile-progress.test.mjs`

Expected: FAIL in these tests:
- The lost latest.md: `renderCheckpoint` returns early on the recorded checkpoint time, so the checkout gets no `latest.md` (ENOENT on read).
- The linked mirror ledger: the move copies through the link and succeeds.
- Both linked-ledger tests: no refusal names symbolic links before the pull; the newer-content one finds the pull wrote through or replaced the link.
- The landed edit: `copyFileSync` overwrites it, and the move succeeds.
- The part-way copy failure: `progressToLocal` rejects with the injected EIO.

The unreadable mirror `latest.md` test passes; that path was a coverage gap.

- [ ] **Step 3: Implement**

All edits are in `plugins/dforge/scripts/lib/darkmem-progress-move.mjs`.

1. `renderCheckpoint`: a missing `latest.md` is always rendered. After Task 22 the function starts:

```js
// The latest.md file for `newest`, unless the mirror's copy is newer or holds
// a local edit; pull's rule, applied across every workstream.
function renderCheckpoint({ state, persist, report }, workRoot, newest) {
  const synced = newestCheckpointAt(state);
  if (!newest || (synced && isoMicros(newest.created_at) <= isoMicros(synced))) return;
  const file = path.join(workRoot, "handoff", "latest.md");
```

Replace it with:

```js
// The latest.md file for `newest`, unless the mirror's copy is newer or holds
// a local edit; pull's rule, applied across every workstream. A mirror that
// lost latest.md takes darkmem's newest again, however old.
function renderCheckpoint({ state, persist, report }, workRoot, newest) {
  if (!newest) return;
  const file = path.join(workRoot, "handoff", "latest.md");
  const synced = newestCheckpointAt(state);
  if (fs.existsSync(file) && synced && isoMicros(newest.created_at) <= isoMicros(synced)) return;
```

Only the `fs.existsSync(file) &&` guard is new; `newestCheckpointAt` is the helper Task 20 exports from `darkmem-mirror.mjs` and Task 22 imports here.

2. Add this helper directly above the comment `// The symbolic links at or below \`stateRel\` on the way to each rel, as` (the comment above `linksBelow`):

```js
// A file's bytes, or null when it does not exist.
function readOrNull(file) {
  try {
    return fs.readFileSync(file);
  } catch (error) {
    if (error.code === "ENOENT") return null;
    throw error;
  }
}

```

3. No `stateRel` guard: `stateDir` is `dforgeDir("state", cfg.repoRoot)`, which is always `<repoRoot>/.dforge`, so `stateRel` is always `.dforge` and a `..` check could never fire or be tested. Leave the `const stateRel = ...` line as it is.

3b. Refuse a linked mirror source before the pull. In `progressToLocal`, replace:

```js
  const roots = { docsRoot: path.join(cfg.mirror, DOC_PREFIX), workRoot, worktreeRoot: cfg.repoRoot, families: { documents: false, progress: true } };
```

with:

```js
  const roots = { docsRoot: path.join(cfg.mirror, DOC_PREFIX), workRoot, worktreeRoot: cfg.repoRoot, families: { documents: false, progress: true } };
  // The pull below reads and rewrites the mirror's progress files, so a linked
  // one is refused before it, not only before the copies.
  const linked = mirrorLinks(workRoot);
  if (linked.length) return refuse("the mirror's progress is reached through symbolic links; nothing was pulled or copied", linked);
```

and add this helper directly above `export async function progressToLocal(`:

```js
// One line per symbolic link, or directory that cannot be listed, under the
// mirror's work directory. Dirent types come from lstat, so no link is followed.
function mirrorLinks(workRoot) {
  const lines = [];
  const walk = dir => {
    let entries;
    try {
      entries = fs.readdirSync(dir, { withFileTypes: true });
    } catch (error) {
      if (error.code !== "ENOENT") lines.push(`${dir}: could not be listed (${error.code})`);
      return;
    }
    for (const entry of entries) {
      const file = path.join(dir, entry.name);
      if (entry.isSymbolicLink()) lines.push(`${file}: a symbolic link in the mirror, which the move will not read through`);
      else if (entry.isDirectory()) walk(file);
    }
  };
  walk(workRoot);
  return lines;
}
```

Item 4's check below stays as the second guard, for a link that appears
between this walk and the copies.

4. In `progressToLocal`, replace:

```js
  for (const item of sources) {
    item.target = local(stateDir, item.rel);
    try {
      item.buffer = fs.readFileSync(item.file);
```

with:

```js
  for (const item of sources) {
    item.target = local(stateDir, item.rel);
    if (fs.lstatSync(item.file, { throwIfNoEntry: false })?.isSymbolicLink()) {
      problems.push(`${item.file}: a symbolic link in the mirror, which the move will not read through`);
      continue;
    }
    try {
      item.buffer = fs.readFileSync(item.file);
```

5. In `progressToLocal`, replace:

```js
  for (const item of sources) {
    fs.mkdirSync(path.dirname(item.target), { recursive: true });
    fs.copyFileSync(item.file, item.target);
  }
  const differing = sources.filter(item => !fs.readFileSync(item.target).equals(item.buffer)).map(item => `${item.target}: the copy reads back different`);
  if (differing.length) return refuse("a copy into the primary checkout reads back different", differing);
```

with:

```js
  // An edit can land in the checkout between the reads above and a copy: each
  // target is read again just before it is written, a new one is created
  // exclusively, and a failure part-way refuses, keeping what was copied.
  const landed = [];
  const copied = [];
  try {
    for (const item of sources) {
      fs.mkdirSync(path.dirname(item.target), { recursive: true });
      const now = readOrNull(item.target);
      if (now && !now.equals(item.buffer)) {
        landed.push(`${item.target}: changed during the move; not overwritten`);
        continue;
      }
      if (!now) {
        fs.copyFileSync(item.file, item.target, fs.constants.COPYFILE_EXCL);
        copied.push(item);
      }
    }
    if (landed.length) return refuse("the primary checkout changed during the move; nothing was overwritten", landed);
    const differing = sources.filter(item => !readOrNull(item.target)?.equals(item.buffer)).map(item => `${item.target}: the copy reads back different`);
    if (differing.length) return refuse("a copy into the primary checkout reads back different", differing);
  } catch (error) {
    return refuse(
      `a copy into the primary checkout failed (${error.code}); the files copied so far stay, and a rerun copies the rest`,
      copied.map(item => `${item.target}: copied`),
    );
  }
```

Leave the rest of `progressToLocal` (the details, the mirror rename and the state reset) unchanged. Keep every other refusal in this function as it is.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `timeout 300 node --test plugins/dforge/tests/darkmem-sync/reconcile-progress.test.mjs`

Expected: PASS

Then the whole darkmem-sync set (the hooks run reconcile at session start):

Run: `timeout 600 bash plugins/dforge/tests/darkmem-sync.test.sh`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/scripts/lib/darkmem-progress-move.mjs plugins/dforge/tests/darkmem-sync/reconcile-progress.test.mjs
git commit -m "fix(darkmem): guard the progress move back to local"
```

---

### Task 29: Fit session lines in order and unnest the Stop push

**Files:**
- Modify: `plugins/dforge/scripts/lib/darkmem-hook.sh`
- Modify: `plugins/dforge/scripts/darkmem-stop-push.sh`
- Test: `plugins/dforge/tests/darkmem-sync/hooks.test.mjs`

**Interfaces:**
- Consumes: None
- Produces: None

**Items:** DM 27, DM 44, DM 50

**Depends on:** none
**Implementer:** dr-superpowers:impl-sonnet-low
**Evaluation:** files 1 - spec 0 - coupling 0 - risk 1 = 2

- [ ] **Step 1: Write the failing tests**

The tests prove these points:
- `_darkmem_fit`'s first pass stops at the first unindented line the room cannot hold (DM 27, hook half).
- The Stop push's config lookup is bounded apart from the push, so no bound wraps the push's own (DM 50).

Coverage only (DM 44):
- A malformed `~/.dforge/config.json` gives its one-line reason.
- A session start with under 100 characters of room still syncs but adds no darkmem line.

The bash 3.2 watchdog stays untested: CI has no macOS runner (spec P4 item 22).

In `plugins/dforge/tests/darkmem-sync/hooks.test.mjs`, after this line:

```js
const pushQuietly = (dir, sid, env) => bash(["-c", '. "$1"; darkmem_push_quietly "$2" "$3"', "hook-test", LIB, dir, sid], { cwd: dir, env });
```

add:

```js
const fit = (input, lines, chars) => bash(["-c", '. "$1"; _darkmem_fit "$2" "$3"', "hook-test", LIB, String(lines), String(chars)], { cwd: scratch("dmh-fit-"), env: process.env, input });
```

After the test `unindented lines outlast the line cap; the character room trims them last`, which ends with:

```js
  assert.match(tight.stdout, /^failed: dforge\/n00\.: /m);
  assert.match(tight.stdout.trimEnd().split("\n").at(-1), MORE);
});
```

add:

```js
test("the character room keeps unindented lines in order: the first that misses ends them", async () => {
  const result = await fit(`first\n${"x".repeat(50)}\nlast\n`, 20, 120);
  assert.equal(result.code, 0, result.stderr);
  assert.equal(result.stdout, "first\ndarkmem-sync: 2 more lines; run darkmem-sync reconcile or status to see them\n");
});

test("a malformed ~/.dforge/config.json is one line naming it, and nothing is synced", async t => {
  const s = await setup(t, { config: "{ not json" });
  const result = await sessionLines(s.repo, "sid-hook", s.env);
  assert.equal(result.code, 0, result.stderr);
  assert.match(result.stdout, /^darkmem-config: .+config\.json is not valid JSON: [^\n]*\n$/);
  assert.equal(s.stub.db.requests.length, 0);
});
```

After the test `session start adds the darkmem lines on every source, compaction included`, which ends with:

```js
    assert.match(context, /dforge:using-dforge/, source);
  }
});
```

add:

```js
test("session start with under 100 characters of room still syncs, and adds no darkmem line", { skip: !hasJq && "jq is not on PATH" }, async t => {
  const s = await setup(t);
  await s.seed.putDocument({ project: "proj", uri: "dforge/specs/a.md", content: "# A\n" });
  // A roadmap line longer than the hook's whole cap leaves the darkmem lines no room.
  const name = "x".repeat(9200);
  write(path.join(s.home.docsRoot, "registers", "m1.md"), "# M1 — item register\n\n**Source:** roadmap\n\n| # | Item | Assigned | Acceptance | State | Note |\n|---|---|---|---|---|---|\n| 1 | Search | - | - | open | - |\n");
  write(path.join(s.home.docsRoot, "roadmap.md"), `# Shop — roadmap\n\n| M | Name | Exit criteria | Register | State | Note |\n|---|---|---|---|---|---|\n| M1 | ${name} | every epic resolved | docs/dforge/registers/m1.md | open | - |\n`);
  const payload = { hook_event_name: "SessionStart", session_id: "sid-start", transcript_path: "", cwd: s.repo, source: "startup" };
  const result = await runHook("session-start.sh", payload, { cwd: s.repo, env: s.env });
  assert.equal(result.code, 0, result.stderr);
  const context = JSON.parse(result.stdout).hookSpecificOutput.additionalContext;
  assert.match(context, /^Roadmap: M1 x{9200}/m, "the roadmap line took the room");
  assert.doesNotMatch(context, /darkmem-sync/);
  assert.equal(fs.readFileSync(path.join(s.home.docsRoot, "specs", "a.md"), "utf8"), "# A\n", "the pull still ran");
});
```

After the test `the Stop push sends under its session id, a retried stop too, and prints nothing; turn-end.sh sends nothing`, which ends with:

```js
  assert.equal(appends().length, 2, "a retried stop pushes the lines written since");
  assert.ok(appends().every(r => r.body.run_key === "sid-stop"));
});
```

add:

```js
test("the Stop push bounds its config lookup apart from the push, which keeps its own bound", {
  skip: (!hasJq && "jq is not on PATH")
    || (spawnSync("timeout", ["--version"]).status !== 0 && "GNU timeout is not on PATH")
    || (process.platform === "win32" && "the PATH shim is a POSIX shell script"),
}, async t => {
  const s = await setup(t);
  write(path.join(s.home.workRoot, "sdd", "p1", "progress.md"), "# SDD ledger — plan: docs/dforge/plans/p1.md\nTask 1: a\n");
  const dir = scratch("dmh-tmo-");
  const log = path.join(dir, "timeout.log");
  const real = spawnSync("bash", ["-c", "command -v timeout"], { encoding: "utf8" }).stdout.trim();
  fs.mkdirSync(path.join(dir, "bin"));
  fs.writeFileSync(path.join(dir, "bin", "timeout"), `#!/bin/sh\nprintf '%s\\n' "$*" >> "${log}"\nexec "${real}" "$@"\n`, { mode: 0o755 });
  const env = { ...s.env, PATH: `${path.join(dir, "bin")}${path.delimiter}${s.env.PATH}` };
  const payload = { hook_event_name: "Stop", session_id: "sid-stop", cwd: s.repo, transcript_path: "", stop_hook_active: false };
  assert.deepEqual(await runHook("darkmem-stop-push.sh", payload, { cwd: s.repo, env }), { code: 0, stdout: "", stderr: "" });
  const calls = fs.readFileSync(log, "utf8").split("\n").filter(Boolean);
  assert.deepEqual(calls.filter(line => /darkmem_push_quietly/.test(line)), [], "no bound wraps the push's own bound");
  assert.equal(calls.filter(line => / push$/.test(line) && /darkmem-sync/.test(line)).length, 1, calls.join("\n"));
  assert.match(calls.find(line => /dforge_project/.test(line)) ?? "", /^-k \d+ 30 bash -c /);
  assert.ok(s.stub.db.requests.some(r => r.method === "POST" && r.path === "/api/v1/worklog/entries"), "the push still sent the ledger");
});
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `timeout 300 node --test plugins/dforge/tests/darkmem-sync/hooks.test.mjs`

Expected: FAIL in two tests:
- The fit test: it prints `first`, `last` and "1 more lines", because the first pass keeps `last` after the 50-character line missed.
- The Stop-push test: the log holds a `-k 5 100 bash -c . "$1" && darkmem_push_quietly ...` line and no `dforge_project` line.

The malformed-config and under-100-room tests pass; those branches were coverage gaps.

- [ ] **Step 3: Implement**

1. In `plugins/dforge/scripts/lib/darkmem-hook.sh`, replace:

```bash
# _darkmem_fit MAXLINES MAXCHARS — the lines on stdin, fitted. Every unindented
# line (a family's reconcile line, a conflict, a failure, a summary) is kept, in
# order, while the character room holds it; indented detail lines fill what is
# left of both rooms; one closing line counts what was left out. 100 characters
# stay free for that line.
```

with:

```bash
# _darkmem_fit MAXLINES MAXCHARS — the lines on stdin, fitted. Unindented lines
# (a family's reconcile line, a conflict, a failure, a summary) are kept in
# order until the first one the character room cannot hold, so no later line
# stands in for it; indented detail lines fill what is left of both rooms; one
# closing line counts what was left out. 100 characters stay free for that line.
```

2. In the same function, replace:

```awk
        if (used + size <= room) { keep[i] = 1; used += size; tops++ }
      }
      slots = maxlines - tops
```

with:

```awk
        if (!full && used + size <= room) { keep[i] = 1; used += size; tops++ } else full = 1
      }
      slots = maxlines - tops
```

`full` must not end the loop: the loop also counts the detail lines below the miss.

3. In the same file, replace:

```bash
# darkmem_push_quietly DIR SID — the background Stop push
# (scripts/darkmem-stop-push.sh). Nothing it prints would reach anyone. It
# refuses at once when the mirror lock is held (a wait of 1 ms; 0 would mean the
# 100 s default), so Stop pushes never queue up ahead of a skill's own push or
# the next session's reconcile; the next stop pushes what this one missed.
darkmem_push_quietly() {
  _darkmem_configured || return 0
  (dforge_project "$1") >/dev/null 2>&1 || return 0
  DARKMEM_SYNC_LOCK_WAIT_MS=1 _darkmem_run "$1" "$2" 100 push >/dev/null 2>&1
  return 0
}
```

with:

```bash
# darkmem_push_quietly DIR SID — the background Stop push
# (scripts/darkmem-stop-push.sh). Nothing it prints would reach anyone. It
# refuses at once when the mirror lock is held (a wait of 1 ms; 0 would mean the
# 100 s default), so Stop pushes never queue up ahead of a skill's own push or
# the next session's reconcile; the next stop pushes what this one missed. The
# config lookup (a node start) and the push are bounded apart: a bound around
# both would not reach the push, which runs in a process group of its own.
darkmem_push_quietly() {
  _darkmem_configured || return 0
  _darkmem_bounded 30 bash -c '. "$1" && dforge_project "$2"' darkmem-push "$_DARKMEM_HOOK_SCRIPTS/lib/roots.sh" "$1" >/dev/null 2>&1 || return 0
  DARKMEM_SYNC_LOCK_WAIT_MS=1 _darkmem_run "$1" "$2" 100 push >/dev/null 2>&1
  return 0
}
```

4. In `plugins/dforge/scripts/darkmem-stop-push.sh`, replace:

```bash
# One bound around config discovery and the push together: darkmem_push_quietly
# resolves the mapping (a node start) before its own bounded push.
if . "$hook_lib" 2>/dev/null; then
  _darkmem_bounded 100 bash -c '. "$1" && darkmem_push_quietly "$2" "$3"' darkmem-stop-push "$hook_lib" "${cwd:-$PWD}" "$session_id" >/dev/null 2>&1
fi
```

with:

```bash
# darkmem_push_quietly bounds its config lookup and its push apart; a bound
# here around both would not reach the push's own.
if . "$hook_lib" 2>/dev/null; then
  darkmem_push_quietly "${cwd:-$PWD}" "$session_id" >/dev/null 2>&1
fi
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `timeout 300 node --test plugins/dforge/tests/darkmem-sync/hooks.test.mjs`

Expected: PASS

`session-start.sh` sources this library, and the hook suite covers it:

Run: `timeout 600 bash plugins/dforge/tests/hook.test.sh`

Expected: PASS

Run: `timeout 600 bash plugins/dforge/tests/darkmem-sync.test.sh`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/scripts/lib/darkmem-hook.sh plugins/dforge/scripts/darkmem-stop-push.sh plugins/dforge/tests/darkmem-sync/hooks.test.mjs
git commit -m "fix(darkmem): fit lines in order, bound push lookup"
```

---

### Task 30: Close the home migration's gaps

**Files:**
- Modify: `plugins/dforge/scripts/lib/dforge-home-migrate.mjs`
- Test: `plugins/dforge/tests/darkmem-sync/migrate.test.mjs`

**Interfaces:**
- Consumes: None
- Produces: None

**Items:** DR 7, DR 8, DR 10, DR 11, DR 12, DR 13, DR 14

**Depends on:** none
**Implementer:** dr-superpowers:impl-sonnet-medium
**Evaluation:** files 1 - spec 0 - coupling 0 - risk 3 = 4

- [ ] **Step 1: Write the failing tests**

The tests prove these behaviours:
- A rename line names only the old prefixes the mirror's state holds (DR 7).
- A state-only mirror and old uris in `pendingLinks` migrate (DR 8, coverage only).
- A project mirror named `mirror` gets its dry-run line (DR 10).
- The dry run foretells a held lock and an unreadable state (DR 11).
- The dry-run tests compare file contents (DR 12).
- An old home that cannot be removed is reported (DR 13).
- A `config.json` that is not a JSON object is refused (DR 14).

1a. In `plugins/dforge/tests/darkmem-sync/migrate.test.mjs`, find this line:

```js
const STATE = documents => JSON.stringify({ version: 1, documents, ledgers: {}, checkpoint: null, checkpointAt: null, conflicts: [], pendingLinks: [] });
```

Insert these lines immediately above it:

```js
// Every path under dir, each file with its content's hash: a dry run that
// rewrote a file fails the comparison, not only one that added or removed one.
const snapshot = dir => fs.readdirSync(dir, { recursive: true }).sort().map(name => {
  const file = path.join(dir, name);
  return fs.statSync(file).isDirectory() ? `${name}/` : `${name} ${sha(read(file))}`;
});
```

1b. DR 12: in the same file, the line

```js
  const before = fs.readdirSync(home, { recursive: true }).sort();
```

appears 3 times (in the tests "migrateHome with dryRun writes nothing and says what would happen", "…merging into an existing ~/.dforge, lists every action the real run takes" and "…foretells the refusals and darkmem lines a merge into ~/.dforge causes"). Replace each with:

```js
  const before = snapshot(home);
```

The line

```js
  assert.deepEqual(fs.readdirSync(home, { recursive: true }).sort(), before);
```

appears 3 times in the same tests. Replace each with:

```js
  assert.deepEqual(snapshot(home), before);
```

After the edit, `grep -c 'readdirSync(home, { recursive: true })' plugins/dforge/tests/darkmem-sync/migrate.test.mjs` prints `0`.

1c. Append these tests at the end of the file, after the last test ("migrateHome merges the plain files under ~/.dr-forge/mirror into an existing ~/.dforge/mirror"), whose last line is `});`:

```js

test("migrateHome renames a mirror whose state alone holds forge/ uris", () => {
  const home = scratch("dms-home-");
  const mirror = path.join(home, ".dforge", "mirror", "p");
  write(path.join(mirror, ".sync-state.json"), JSON.stringify({
    version: 1, documents: { "forge/a.md": sha("a\n") }, ledgers: {}, checkpoint: null, checkpointAt: null, conflicts: [], pendingLinks: [],
  }));
  const { lines, refused } = migrateHome({ HOME: home });
  assert.equal(refused, 0, lines.join("\n"));
  assert.deepEqual(Object.keys(JSON.parse(read(path.join(mirror, ".sync-state.json"))).documents), ["dforge/a.md"]);
  assert.equal(fs.existsSync(path.join(mirror, "dforge")), false, "no folder is made for a state-only mirror");
});

test("migrateHome renames the old uris a mirror's pendingLinks hold", () => {
  const home = scratch("dms-home-");
  const mirror = path.join(home, ".dforge", "mirror", "p");
  write(path.join(mirror, ".sync-state.json"), JSON.stringify({
    version: 1, documents: {}, ledgers: {}, checkpoint: null, checkpointAt: null, conflicts: [], pendingLinks: ["superpowers/a.md", "forge/b.md", "dforge/c.md"],
  }));
  const { lines, refused } = migrateHome({ HOME: home });
  assert.equal(refused, 0, lines.join("\n"));
  assert.deepEqual(JSON.parse(read(path.join(mirror, ".sync-state.json"))).pendingLinks, ["dforge/a.md", "dforge/b.md", "dforge/c.md"]);
});

test("migrateHome names only the old prefixes a mirror's state holds", () => {
  const home = scratch("dms-home-");
  const mirrors = path.join(home, ".dforge", "mirror");
  write(path.join(mirrors, "p", ".sync-state.json"), JSON.stringify({
    version: 1, documents: { "forge/a.md": sha("a\n") }, ledgers: {}, checkpoint: null, checkpointAt: null, conflicts: [], pendingLinks: [],
  }));
  write(path.join(mirrors, "q", ".sync-state.json"), JSON.stringify({
    version: 1, documents: {}, ledgers: {}, checkpoint: null, checkpointAt: null, conflicts: [], pendingLinks: ["superpowers/b.md"],
  }));
  const dry = migrateHome({ HOME: home }, { dryRun: true });
  const real = migrateHome({ HOME: home });
  for (const [verb, lines] of [["would rename", dry.lines], ["renamed", real.lines]]) {
    assert.ok(lines.includes(`${verb} ${path.join(mirrors, "p")}'s forge/ to dforge/; darkmem's documents follow at its next sync`), lines.join("\n"));
    assert.ok(lines.includes(`${verb} ${path.join(mirrors, "q")}'s superpowers/ to dforge/; darkmem's documents follow at its next sync`), lines.join("\n"));
  }
});

test("migrateHome with dryRun lists a moved project mirror named mirror", () => {
  const home = scratch("dms-home-");
  const superpowers = path.join(home, ".dr-superpowers");
  write(path.join(superpowers, "mirror", "mirror", "superpowers", "b.md"), "b\n");
  const dry = migrateHome({ HOME: home }, { dryRun: true });
  assert.equal(dry.refused, 0, dry.lines.join("\n"));
  assert.ok(dry.lines.includes(`would rename ${path.join(superpowers, "mirror", "mirror")}'s superpowers/ to dforge/; darkmem's documents follow at its next sync`), dry.lines.join("\n"));
  const real = migrateHome({ HOME: home });
  assert.ok(real.lines.includes(`renamed ${path.join(home, ".dforge", "mirror", "mirror")}'s superpowers/ to dforge/; darkmem's documents follow at its next sync`), real.lines.join("\n"));
});

test("migrateHome with dryRun foretells a held lock and an unreadable sync state", () => {
  const home = scratch("dms-home-");
  const mirrors = path.join(home, ".dforge", "mirror");
  write(path.join(mirrors, "p", "forge", "a.md"), "a\n");
  fs.mkdirSync(path.join(mirrors, "p", ".sync.lock"), { recursive: true });
  write(path.join(mirrors, "q", "forge", "b.md"), "b\n");
  write(path.join(mirrors, "q", ".sync-state.json"), "{not json");
  const refusals = lines => lines.filter(line => line.startsWith("refused: ")).sort();
  const dry = migrateHome({ HOME: home }, { dryRun: true });
  const real = migrateHome({ HOME: home });
  assert.equal(real.refused, 2, real.lines.join("\n"));
  assert.equal(dry.refused, 2, dry.lines.join("\n"));
  assert.deepEqual(refusals(dry.lines), refusals(real.lines));
  assert.ok(!dry.lines.some(line => line.startsWith("would rename")), dry.lines.join("\n"));
});

test("migrateHome reports an old home it cannot remove", t => {
  const home = scratch("dms-home-");
  const forge = path.join(home, ".dr-forge");
  write(path.join(forge, "only-old.txt"), "old\n");
  write(path.join(home, ".dforge", "config.json"), "{}\n");
  // The suite may run as root, where permissions cannot make rmdir fail.
  const rmdir = fs.rmdirSync;
  t.mock.method(fs, "rmdirSync", dir => {
    if (dir === forge) throw Object.assign(new Error(`EACCES: permission denied, rmdir '${dir}'`), { code: "EACCES" });
    return rmdir(dir);
  });
  const { lines, refused } = migrateHome({ HOME: home });
  assert.equal(refused, 1, lines.join("\n"));
  assert.ok(lines.includes(`refused: ${forge} could not be removed: EACCES: permission denied, rmdir '${forge}'`), lines.join("\n"));
  assert.equal(read(path.join(home, ".dforge", "only-old.txt")), "old\n");
});

test("migrateHome refuses a config.json that is not a JSON object and keeps both files", () => {
  const home = scratch("dms-home-");
  const forge = path.join(home, ".dr-forge", "config.json");
  const dforge = path.join(home, ".dforge", "config.json");
  write(forge, JSON.stringify(["x"]));
  write(dforge, JSON.stringify({ layout: "auto" }));
  const refusal = `refused: ${forge} does not hold a JSON object; fix or delete it, then run dforge-migrate again`;
  const dry = migrateHome({ HOME: home }, { dryRun: true });
  assert.ok(dry.lines.includes(refusal), dry.lines.join("\n"));
  const { lines, refused } = migrateHome({ HOME: home });
  assert.equal(refused, 1, lines.join("\n"));
  assert.ok(lines.includes(refusal), lines.join("\n"));
  assert.deepEqual(JSON.parse(read(forge)), ["x"]);
  assert.deepEqual(JSON.parse(read(dforge)), { layout: "auto" });
});
```

The `t.mock.method` stub works because `dforge-home-migrate.mjs` calls `fs.rmdirSync` on the same default-export object (`import fs from "node:fs"`).

- [ ] **Step 2: Run the tests to verify they fail**

Run: `timeout 300 node --test plugins/dforge/tests/darkmem-sync/migrate.test.mjs`
Expected: FAIL. Exactly 5 tests fail:
- "migrateHome names only the old prefixes a mirror's state holds": the line reads `superpowers/ and forge/`.
- "migrateHome with dryRun lists a moved project mirror named mirror": the move's source ends in `/mirror` and is dropped.
- "migrateHome with dryRun foretells a held lock and an unreadable sync state": `dry.refused` is 0.
- "migrateHome reports an old home it cannot remove": the error is swallowed, so `refused` is 0.
- "migrateHome refuses a config.json that is not a JSON object and keeps both files": the array is merged and the old file deleted.

The two DR 8 tests ("…whose state alone holds forge/ uris", "…pendingLinks hold") and the three snapshot-based dry-run tests PASS: DR 8 and DR 12 were gaps in coverage.

- [ ] **Step 3: Implement**

All edits are in `plugins/dforge/scripts/lib/dforge-home-migrate.mjs`.

3a. DR 7: add a helper that names what a mirror is renamed from. Find:

```js
const heldFolders = mirror => [...OLD_PREFIXES, DOC_PREFIX].filter(prefix => fs.existsSync(path.join(mirror, prefix)));
```

Replace with:

```js
const heldFolders = mirror => [...OLD_PREFIXES, DOC_PREFIX].filter(prefix => fs.existsSync(path.join(mirror, prefix)));
// What a mirror is renamed from, for the line that says so: its old folder,
// or else the old prefixes its state's uris hold. Read before migrateMirror.
function oldNamesIn(mirror, state) {
  const folder = heldFolders(mirror).find(prefix => prefix !== DOC_PREFIX);
  if (folder) return folder;
  const uris = [...Object.keys(state.documents), ...state.pendingLinks];
  return OLD_PREFIXES.filter(prefix => uris.some(uri => oldPrefixOf(uri) === prefix)).join("/ and ");
}
```

3b. DR 7 and DR 11: share the held-lock line and use the helper. Find:

```js
// The local half under the mirror's lock, for a caller that holds none.
// Answers { line, blocked } saying what happened, or null when nothing needed
// doing; blocked: a held lock left the mirror in an older layout.
export function migrateMirrorLocked(mirror) {
  if (!legacyMirror(mirror)) return null;
  const release = acquireLock(mirror);
  if (!release) return { line: `${mirror} is still in an older layout and another darkmem-sync holds its lock; try again once it is done`, blocked: true };
  try {
    const statePath = path.join(mirror, ".sync-state.json");
    const state = loadState(statePath);
    const from = heldFolders(mirror).find(prefix => prefix !== DOC_PREFIX);
    if (!migrateMirror(mirror, state)) return null;
    saveState(statePath, state);
    return { line: `renamed ${mirror}'s ${from ?? OLD_PREFIXES.join("/ and ")}/ to ${DOC_PREFIX}/; darkmem's documents follow at its next sync`, blocked: false };
```

Replace with:

```js
const lockedLine = mirror => `${mirror} is still in an older layout and another darkmem-sync holds its lock; try again once it is done`;

// The local half under the mirror's lock, for a caller that holds none.
// Answers { line, blocked } saying what happened, or null when nothing needed
// doing; blocked: a held lock left the mirror in an older layout.
export function migrateMirrorLocked(mirror) {
  if (!legacyMirror(mirror)) return null;
  const release = acquireLock(mirror);
  if (!release) return { line: lockedLine(mirror), blocked: true };
  try {
    const statePath = path.join(mirror, ".sync-state.json");
    const state = loadState(statePath);
    const from = oldNamesIn(mirror, state);
    if (!migrateMirror(mirror, state)) return null;
    saveState(statePath, state);
    return { line: `renamed ${mirror}'s ${from}/ to ${DOC_PREFIX}/; darkmem's documents follow at its next sync`, blocked: false };
```

3c. DR 10: flag the moves of a home's whole mirror folder. Find:

```js
  const did = (done, would) => lines.push(dryRun ? would : done);
  const moves = [];
```

Replace with:

```js
  const did = (done, would) => lines.push(dryRun ? would : done);
  // [from, to, whole]: whole marks a home's mirror folder moving, not one mirror.
  const moves = [];
```

Find:

```js
    moves.push([path.join(forgeHome, "mirror"), path.join(newHome, "mirror")]);
```

Replace with:

```js
    moves.push([path.join(forgeHome, "mirror"), path.join(newHome, "mirror"), true]);
```

Find:

```js
        if (entry.name === "mirror") moves.push([from, to]);
```

Replace with:

```js
        if (entry.name === "mirror") moves.push([from, to, true]);
```

Leave the two other `moves.push([source, target]);` lines (single project mirrors) unchanged.

3d. DR 14: refuse a `config.json` that is not a JSON object before the merge. Find:

```js
        const old = readJson(from) ?? {};
        const next = readJson(to) ?? {};
```

Replace with:

```js
        const old = readJson(from);
        const next = readJson(to);
        const notObject = [[from, old], [to, next]].find(([, value]) => value === null || typeof value !== "object" || Array.isArray(value));
        if (notObject) {
          refuse(`${notObject[0]} does not hold a JSON object; fix or delete it, then run dforge-migrate again`);
          continue;
        }
```

3e. DR 13: report an `rmdirSync` failure that is not "still holds something" or "already gone". Find:

```js
        } catch {
          // Still holds something refused, or already gone.
        }
```

Replace with:

```js
        } catch (error) {
          // Still holds something refused (ENOTEMPTY, or EEXIST on some
          // systems), already gone, or is a mirror file whose merge was refused.
          if (!["ENOTEMPTY", "EEXIST", "ENOENT", "ENOTDIR"].includes(error.code)) refuse(`${dir} could not be removed: ${error.message}`);
        }
```

3f. DR 10, DR 11 and DR 7 in the dry run. Find:

```js
  if (dryRun) for (const [from] of moves) if (!from.endsWith(`${path.sep}mirror`)) mirrors.add(from);
  for (const mirror of mirrors) {
    if (dryRun) {
      const held = heldFolders(mirror);
      if (held.length > 1) refuse(`${mirror} holds ${held.map(prefix => `${prefix}/`).join(" and ")}; move all but one aside`);
      else if (legacyMirror(mirror)) lines.push(`would rename ${mirror}'s ${held[0] ?? OLD_PREFIXES.join("/ and ")}/ to ${DOC_PREFIX}/; darkmem's documents follow at its next sync`);
      continue;
    }
```

Replace with:

```js
  if (dryRun) for (const [from, , whole] of moves) if (!whole) mirrors.add(from);
  for (const mirror of mirrors) {
    if (dryRun) {
      // The real run's checks in its order: the lock, the state, the folders.
      // A lock the real run would find abandoned and take over is still
      // foretold as held.
      if (!legacyMirror(mirror)) continue;
      if (fs.existsSync(path.join(mirror, ".sync.lock"))) {
        refuse(lockedLine(mirror));
        continue;
      }
      let state;
      try {
        state = loadState(path.join(mirror, ".sync-state.json"));
      } catch (error) {
        if (!(error instanceof StateError)) throw error;
        refuse(error.message);
        continue;
      }
      const held = heldFolders(mirror);
      if (held.length > 1) refuse(`${mirror} holds ${held.map(prefix => `${prefix}/`).join(" and ")}; move all but one aside`);
      else lines.push(`would rename ${mirror}'s ${oldNamesIn(mirror, state)}/ to ${DOC_PREFIX}/; darkmem's documents follow at its next sync`);
      continue;
    }
```

`loadState` and `StateError` are already imported from `./darkmem-mirror.mjs`. The refusal paths for two docs folders, the held lock in the real run and the config clash are unchanged.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `timeout 300 node --test plugins/dforge/tests/darkmem-sync/migrate.test.mjs`
Expected: PASS (23 tests).

`darkmem-sync.mjs` calls `migrateMirrorLocked`, and `dforge-migrate` runs this module, so also run:
- `timeout 600 bash plugins/dforge/tests/darkmem-sync.test.sh`: PASS.
- `timeout 600 bash plugins/dforge/tests/dforge-migrate.test.sh`: PASS.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/scripts/lib/dforge-home-migrate.mjs plugins/dforge/tests/darkmem-sync/migrate.test.mjs
git commit -m "fix(dforge): close the home migration gaps"
```

---

### Task 31: Make dforge-migrate's dry run match the real run

**Files:**
- Modify: `plugins/dforge/scripts/dforge-migrate`
- Test: `plugins/dforge/tests/dforge-migrate.test.sh`

**Interfaces:**
- Consumes: None
- Produces: None

**Items:** DR 15, DR 16, DR 17, DR 18, DR 19, DR 20, DR 21, DR 23, DR 25, DR 40

**Depends on:** none
**Implementer:** dr-superpowers:impl-sonnet-medium
**Evaluation:** files 1 - spec 0 - coupling 0 - risk 3 = 4

- [ ] **Step 1: Write the failing tests**

The tests prove these behaviours:
- Fenced code blocks keep their prefixes (DR 15).
- The real run's `moved`/`rewrote` lines are asserted (DR 16, coverage only).
- A failed `find` is silent and counts as holding a link (DR 17, DR 18).
- A refused docs move lists no plan rewrite (DR 19).
- A handoff note left under an old directory keeps its text (DR 20).
- A foretold home refusal is named as one (DR 21, DR 25).
- A failed ignore-file rewrite is not listed (DR 23).
- An empty old state directory is listed (DR 40).

All edits are in `plugins/dforge/tests/dforge-migrate.test.sh`. Some blocks contain triple backticks inside strings, so they are shown in four-backtick fences.

1a. DR 16: after the line

```bash
check "dr-forge: names the rewritten plan" "$(grep -c "^commit: $F: docs/dforge/plans/active.md$" <<<"$out")" "1"
```

insert:

```bash
check "dr-forge: the state move printed" "$(grep -cxF "moved $F/.forge -> $F/.dforge" <<<"$out")" "1"
check "dr-forge: the docs move printed" "$(grep -cxF "moved $F/docs/forge -> $F/docs/dforge" <<<"$out")" "1"
check "dr-forge: the git dir move printed" "$(grep -cxF "moved $F/.git/dr-forge -> $F/.git/dforge" <<<"$out")" "1"
check "dr-forge: the plan rewrite printed" "$(grep -cxF "rewrote the plugin prefixes in $F/docs/dforge/plans/active.md" <<<"$out")" "1"
check "dr-forge: the handoff rewrite printed" "$(grep -cxF "rewrote the plugin prefixes in $F/.dforge/handoff/latest.md" <<<"$out")" "1"
```

1b. DR 15: immediately above the line

```bash
# --- .superpowers/ and .forge/ both present: both merged into .dforge/ ---
```

insert:

````bash
# --- an active plan's fenced code blocks keep their prefixes ---
FC="$TMP/fenced"
repo "$FC"
mkdir -p "$FC/docs/dforge/plans"
printf '**Implementer:** dr-forge:impl-sonnet-low\n```bash\necho dr-forge:brainstorming\n```\nthen dr-forge:executing-plans\n' > "$FC/docs/dforge/plans/mixed.md"
printf '```\ndr-forge:impl-sonnet-low\n```\n' > "$FC/docs/dforge/plans/fenced-only.md"
out=$(bash "$FM" --dry-run "$FC" 2>&1); code=$?
check "fenced, dry: exit 0" "$code" "0"
check "fenced, dry: the mixed plan listed" "$(grep -cxF "would rewrite the plugin prefixes in $FC/docs/dforge/plans/mixed.md" <<<"$out")" "1"
check "fenced, dry: a plan with prefixes only in a fence not listed" "$(grep -c "fenced-only.md" <<<"$out")" "0"
out=$(bash "$FM" "$FC" 2>&1); code=$?
check "fenced: exit 0" "$code" "0"
check "fenced: prefixes outside the fence rewritten, inside kept" "$(cat "$FC/docs/dforge/plans/mixed.md")" \
  $'**Implementer:** dforge:impl-sonnet-low\n```bash\necho dr-forge:brainstorming\n```\nthen dforge:executing-plans'
check "fenced: a plan with prefixes only in a fence keeps its text" "$(cat "$FC/docs/dforge/plans/fenced-only.md")" $'```\ndr-forge:impl-sonnet-low\n```'
check "fenced: no rewrite reported for it" "$(grep -c "fenced-only.md" <<<"$out")" "0"

````

and directly below it (this block holds four-backtick text, so it is shown in a
five-backtick fence):

`````bash
# --- a fence closes only on its own character and length ---
printf '````md\n```\ndr-forge:inner\n```\n````\nafter dr-forge:outer\n' > "$FC/docs/dforge/plans/long-fence.md"
printf '~~~\ndr-forge:tilde\n~~~\nthen dr-forge:plain\n' > "$FC/docs/dforge/plans/tilde.md"
out=$(bash "$FM" "$FC" 2>&1); code=$?
check "fence kinds: exit 0" "$code" "0"
check "fence kinds: an inner three-backtick line does not close a four-backtick fence" "$(cat "$FC/docs/dforge/plans/long-fence.md")" \
  $'````md\n```\ndr-forge:inner\n```\n````\nafter dforge:outer'
check "fence kinds: a tilde fence keeps its prefixes" "$(cat "$FC/docs/dforge/plans/tilde.md")" $'~~~\ndr-forge:tilde\n~~~\nthen dforge:plain'

`````

1c. DR 40 and DR 20: immediately above the line

```bash
# --- docs/forge/ beside docs/dforge/: refused, and no plan is rewritten ---
```

insert:

```bash
# --- an empty old state directory, or one holding only directories .dforge/ has ---
EM="$TMP/empty-old"
repo "$EM"
mkdir -p "$EM/.superpowers/sub" "$EM/.forge" "$EM/.dforge/sub"
echo kept > "$EM/.dforge/kept.md"
out=$(bash "$FM" --dry-run "$EM" 2>&1); code=$?
check "empty old dirs, dry: exit 0" "$code" "0"
check "empty old dirs, dry: the empty one listed" "$(grep -cxF "would move $EM/.forge -> $EM/.dforge" <<<"$out")" "1"
check "empty old dirs, dry: the one holding a shared directory listed" "$(grep -cxF "would move $EM/.superpowers -> $EM/.dforge" <<<"$out")" "1"
check "empty old dirs, dry: not nothing to migrate" "$(grep -c 'nothing to migrate' <<<"$out")" "0"
out=$(bash "$FM" "$EM" 2>&1); code=$?
check "empty old dirs: exit 0" "$code" "0"
check "empty old dirs: the real run moves the empty one" "$(grep -cxF "moved $EM/.forge -> $EM/.dforge" <<<"$out")" "1"
check "empty old dirs: both gone" "$(exists "$EM/.superpowers")$(exists "$EM/.forge")" "nono"

# --- a handoff note left under an old state directory keeps its text ---
HN="$TMP/handoff-refused"
repo "$HN"
mkdir -p "$HN/.forge/handoff" "$HN/.dforge/handoff"
printf 'old dr-forge:resume-execution\n' > "$HN/.forge/handoff/latest.md"
printf 'new dr-forge:resume-execution\n' > "$HN/.dforge/handoff/latest.md"
out=$(bash "$FM" --dry-run "$HN" 2>&1); code=$?
check "refused note, dry: exit 1" "$code" "1"
check "refused note, dry: the note left behind not listed" "$(grep -c "would rewrite the plugin prefixes in $HN/.forge/" <<<"$out")" "0"
check "refused note, dry: the .dforge note listed" "$(grep -cxF "would rewrite the plugin prefixes in $HN/.dforge/handoff/latest.md" <<<"$out")" "1"
out=$(bash "$FM" "$HN" 2>&1); code=$?
check "refused note: exit 1" "$code" "1"
check "refused note: the note left behind keeps its text" "$(cat "$HN/.forge/handoff/latest.md")" "old dr-forge:resume-execution"
check "refused note: the .dforge note rewritten" "$(cat "$HN/.dforge/handoff/latest.md")" "new dforge:resume-execution"
HM="$TMP/handoff-moves"
repo "$HM"
mkdir -p "$HM/.forge/handoff" "$HM/.dforge"
printf 'dr-forge:resume-execution\n' > "$HM/.forge/handoff/latest.md"
out=$(bash "$FM" --dry-run "$HM" 2>&1)
check "moving note, dry: listed" "$(grep -cxF "would rewrite the plugin prefixes in $HM/.forge/handoff/latest.md" <<<"$out")" "1"
bash "$FM" "$HM" > /dev/null 2>&1
check "moving note: rewritten once moved" "$(cat "$HM/.dforge/handoff/latest.md")" "dforge:resume-execution"

```

1d. DR 19, DR 17 and DR 18: immediately above the line

```bash
# --- a cloned repository controls these names: nothing is written through a link ---
```

insert this block. It contains a nested here-document: copy the `<<FIND` … `FIND` lines exactly, including the backslashes.

```bash
LR="$TMP/linked-docs-inside"
repo "$LR"
mkdir -p "$LR/real-docs/forge/plans"
printf 'dr-forge:impl-sonnet-low\n' > "$LR/real-docs/forge/plans/p.md"
ln -s real-docs "$LR/docs"
out=$(bash "$FM" --dry-run "$LR" 2>&1); code=$?
check "docs linked inside, dry: exit 1" "$code" "1"
check "docs linked inside, dry: the refusal foretold" "$(grep -c "refused: $LR/docs/forge or $LR/docs/dforge lies in a linked directory" <<<"$out")" "1"
check "docs linked inside, dry: no plan rewrite listed" "$(grep -c 'would rewrite the plugin prefixes' <<<"$out")" "0"
out=$(bash "$FM" "$LR" 2>&1); code=$?
check "docs linked inside: exit 1" "$code" "1"
check "docs linked inside: the plan keeps its text" "$(cat "$LR/real-docs/forge/plans/p.md")" "dr-forge:impl-sonnet-low"

# --- a search of .dforge/ that fails counts as holding a link ---
# The suite may run as root, where permissions cannot make find fail.
FF="$TMP/find-fails"
mkdir -p "$FF"
cat > "$FF/find" <<FIND
#!/bin/sh
case "\$*" in *"-type l -print -quit"*) echo "find: '\$1/locked': Permission denied" >&2; exit 1 ;; esac
exec $(type -P find) "\$@"
FIND
chmod +x "$FF/find"
UF="$TMP/unsearchable"
repo "$UF"
mkdir -p "$UF/.forge" "$UF/.dforge"
echo a > "$UF/.forge/a.md"
out=$(PATH="$FF:$PATH" bash "$FM" "$UF" 2>&1); code=$?
check "unsearchable .dforge: exit 1" "$code" "1"
check "unsearchable .dforge: refused by the link guard" "$(grep -c "holds a symbolic link; merge them by hand" <<<"$out")" "1"
check "unsearchable .dforge: find's error not shown" "$(grep -c 'Permission denied' <<<"$out")" "0"
check "unsearchable .dforge: .forge kept" "$(cat "$UF/.forge/a.md")" "a"
check "unsearchable .dforge: nothing merged" "$(exists "$UF/.dforge/a.md")" "no"

```

1e. DR 23: after the line

```bash
check "dry: a second directory is a usage error" "$?" "2"
```

insert:

```bash

# --- a rewrite that fails is not listed: the real run would skip it ---
AW="$TMP/failing-awk"
mkdir -p "$AW"
printf '#!/bin/sh\nexit 2\n' > "$AW/awk"
chmod +x "$AW/awk"
RN="$TMP/rewrite-fails"
repo "$RN"
printf '.forge/\n' > "$RN/.gitignore"
out=$(PATH="$AW:$PATH" bash "$FM" --dry-run "$RN" 2>&1); code=$?
check "a failing rewrite, dry: exit 0" "$code" "0"
check "a failing rewrite, dry: not listed" "$(grep -c 'would rewrite the older names' <<<"$out")" "0"
out=$(PATH="$AW:$PATH" bash "$FM" "$RN" 2>&1)
check "a failing rewrite: not reported" "$(grep -c 'rewrote the older names' <<<"$out")" "0"
check "a failing rewrite: the file kept" "$(cat "$RN/.gitignore")" ".forge/"
```

1f. DR 21 and DR 25: the settled-home loop ends with `done`, followed by a blank line and then:

```bash
# --- the home step runs when dforge-home-migrate.mjs is installed ---
```

Insert this block between that `done` line and the blank line above the heading. `$SR` is the settled repository defined just above.

```bash

# --- a dry run's foretold home refusal is named as one ---
RH="$TMP/refusing-home"
mkdir -p "$RH/.dr-forge" "$RH/.dforge"
printf '{"handoffTokens":1}\n' > "$RH/.dr-forge/config.json"
printf '{"handoffTokens":2}\n' > "$RH/.dforge/config.json"
out=$(HOME="$RH" bash "$FM" --dry-run "$SR" 2>&1); code=$?
check "refusing home, dry: exit 1" "$code" "1"
check "refusing home, dry: the home's refusal shown" "$(grep -c '^dforge-home-migrate: refused: ' <<<"$out")" "1"
check "refusing home, dry: summed up as foretold" "$(grep -cxF 'dforge-migrate: refused: foretold refusals in the home; see above' <<<"$out")" "1"
check "refusing home, dry: not called unfinished" "$(grep -c 'did not finish' <<<"$out")" "0"
```

1g. DR 21 (the crash keeps its wording): after the line

```bash
check "dforge-home-migrate fails: refused" "$(grep -c 'refused: scripts/lib/dforge-home-migrate.mjs' <<<"$out")" "1"
```

insert:

```bash
out=$(bash "$P/dforge-migrate" --dry-run "$H" 2>&1); code=$?
check "dforge-home-migrate fails, dry: exit 1" "$code" "1"
check "dforge-home-migrate fails, dry: still did not finish" "$(grep -c 'refused: scripts/lib/dforge-home-migrate.mjs did not finish' <<<"$out")" "1"
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `timeout 600 bash plugins/dforge/tests/dforge-migrate.test.sh`
Expected: FAIL with `165 passed, 18 failed`. The failing checks:
- DR 15: "fenced, dry: a plan with prefixes only in a fence not listed", "fenced: prefixes outside the fence rewritten, inside kept", "fenced: a plan with prefixes only in a fence keeps its text", "fenced: no rewrite reported for it". sed rewrites inside fences.
- DR 40: "empty old dirs, dry: the empty one listed", "…the one holding a shared directory listed", "…not nothing to migrate".
- DR 20: "refused note, dry: the note left behind not listed", "refused note: the note left behind keeps its text".
- DR 19: "docs linked inside, dry: no plan rewrite listed".
- DR 17/18: all five "unsearchable .dforge:" checks.
- DR 23: "a failing rewrite, dry: not listed".
- DR 21: "refusing home, dry: summed up as foretold", "refusing home, dry: not called unfinished".

The DR 16 checks, "moving note, dry: listed" and the "dforge-home-migrate fails, dry" checks PASS: they guard behaviour that is already correct.

- [ ] **Step 3: Implement**

All edits are in `plugins/dforge/scripts/dforge-migrate`.

3a. DR 20 and DR 40: record what a dry run would move. Find:

```bash
commit_notes=()

refuse() { printf 'dforge-migrate: refused: %s\n' "$1" >&2; refused=1; checkout_refused=1; }
done_move() {
  if [ "$dry" -eq 1 ]; then printf 'would move %s -> %s\n' "$1" "$2"; else printf 'moved %s -> %s\n' "$1" "$2"; fi
  moved=1
}
```

Replace with:

```bash
commit_notes=()
# In a dry run, each path a line says would move.
dry_moves=()

refuse() { printf 'dforge-migrate: refused: %s\n' "$1" >&2; refused=1; checkout_refused=1; }
done_move() {
  if [ "$dry" -eq 1 ]; then printf 'would move %s -> %s\n' "$1" "$2"; dry_moves+=("$1"); else printf 'moved %s -> %s\n' "$1" "$2"; fi
  moved=1
}

# would_move PATH — a dry run's line said PATH, or a directory holding it,
# would move.
would_move() {
  local from
  for from in "${dry_moves[@]+"${dry_moves[@]}"}"; do
    case $1 in "$from" | "$from"/*) return 0 ;; esac
  done
  return 1
}
```

3b. DR 40: in `merge_into`'s dry-run branch, record the moved files and list an old directory the real run would remove without moving anything. Find:

```bash
  local from=$1 to=$2 file rel conflicts=0 touched=0 dir_conflicts=0
  if [ "$dry" -eq 1 ]; then
    while IFS= read -r -d '' file; do
      rel=${file#"$from"/}
      if [ ! -e "$to/$rel" ] && [ ! -L "$to/$rel" ]; then printf 'would move %s -> %s\n' "$file" "$to/$rel"; moved=1
      elif same_entry "$file" "$to/$rel"; then printf 'would drop %s, the same as %s\n' "$file" "$to/$rel"; moved=1
      else refuse "$file differs from $to/$rel; keep one by hand, then run dforge-migrate again"; fi
    done < <(find "$from" \( -type f -o -type l \) -print0)
    while IFS= read -r -d '' file; do
      rel=${file#"$from"/}
      if [ ! -e "$to/$rel" ] && [ ! -L "$to/$rel" ]; then printf 'would move %s -> %s\n' "$file" "$to/$rel"; moved=1
      elif [ ! -d "$to/$rel" ]; then refuse "$file is a directory and $to/$rel is not; keep one by hand, then run dforge-migrate again"; fi
    done < <(find "$from" -mindepth 1 -type d -empty -print0)
    return 0
  fi
```

Replace with:

```bash
  local from=$1 to=$2 file rel conflicts=0 touched=0 dir_conflicts=0 listed=0
  if [ "$dry" -eq 1 ]; then
    while IFS= read -r -d '' file; do
      rel=${file#"$from"/}
      listed=1
      if [ ! -e "$to/$rel" ] && [ ! -L "$to/$rel" ]; then printf 'would move %s -> %s\n' "$file" "$to/$rel"; moved=1; dry_moves+=("$file")
      elif same_entry "$file" "$to/$rel"; then printf 'would drop %s, the same as %s\n' "$file" "$to/$rel"; moved=1
      else refuse "$file differs from $to/$rel; keep one by hand, then run dforge-migrate again"; fi
    done < <(find "$from" \( -type f -o -type l \) -print0)
    while IFS= read -r -d '' file; do
      rel=${file#"$from"/}
      if [ ! -e "$to/$rel" ] && [ ! -L "$to/$rel" ]; then printf 'would move %s -> %s\n' "$file" "$to/$rel"; moved=1 listed=1
      elif [ ! -d "$to/$rel" ]; then refuse "$file is a directory and $to/$rel is not; keep one by hand, then run dforge-migrate again"; listed=1; fi
    done < <(find "$from" -mindepth 1 -type d -empty -print0)
    # FROM holds nothing, or only directories TO already has: the real run
    # removes it and says it moved, so the dry run says so too.
    if [ "$listed" -eq 0 ] && [ -z "$(find "$from" -mindepth 1 ! -type d -print -quit 2>/dev/null)" ]; then done_move "$from" "$to"; fi
    return 0
  fi
```

3c. DR 17 and DR 18: find:

```bash
# creates the directory it names.
dir_link_in() {
  [ ! -L "$1" ] || return 0
  [ -z "$(find "$1" -mindepth 1 -type l -print -quit)" ] || return 0
  return 1
}
```

Replace with:

```bash
# creates the directory it names. A search that fails part way counts as
# finding one: a link can sit where find could not look.
dir_link_in() {
  local found
  [ ! -L "$1" ] || return 0
  found=$(find "$1" -mindepth 1 -type l -print -quit 2>/dev/null) || return 0
  [ -z "$found" ] || return 0
  return 1
}
```

3d. DR 19: `mv_plain` returns 1 when it refuses. Find:

```bash
# mv_plain FROM TO — the rename; merged file by file when both exist.
mv_plain() {
  [ -e "$1" ] || return 0
  if [ -L "$(dirname -- "$1")" ] || [ -L "$(dirname -- "$2")" ]; then refuse "$1 or $2 lies in a linked directory; move it by hand, then run dforge-migrate again"; return 0; fi
  if [ -e "$2" ]; then
    if [ -L "$1" ] || dir_link_in "$2"; then refuse "$1 or $2 is or holds a symbolic link; merge them by hand, then run dforge-migrate again"; return 0; fi
    if [ -d "$1" ] && [ -d "$2" ]; then merge_into "$1" "$2"; else refuse "$1 and $2 both exist and are not both directories; merge them by hand, then run dforge-migrate again"; fi
    return 0
  fi
  if [ "$dry" -eq 1 ] || mv -- "$1" "$2"; then done_move "$1" "$2"; else refuse "could not rename $1"; fi
}
```

Replace with:

```bash
# mv_plain FROM TO — the rename; merged file by file when both exist. Status
# 1 when it refused outright; merge_into's per-file refusals leave it 0.
mv_plain() {
  [ -e "$1" ] || return 0
  if [ -L "$(dirname -- "$1")" ] || [ -L "$(dirname -- "$2")" ]; then refuse "$1 or $2 lies in a linked directory; move it by hand, then run dforge-migrate again"; return 1; fi
  if [ -e "$2" ]; then
    if [ -L "$1" ] || dir_link_in "$2"; then refuse "$1 or $2 is or holds a symbolic link; merge them by hand, then run dforge-migrate again"; return 1; fi
    if [ -d "$1" ] && [ -d "$2" ]; then merge_into "$1" "$2"; else refuse "$1 and $2 both exist and are not both directories; merge them by hand, then run dforge-migrate again"; return 1; fi
    return 0
  fi
  if [ "$dry" -eq 1 ] || mv -- "$1" "$2"; then done_move "$1" "$2"; else refuse "could not rename $1"; return 1; fi
}
```

The other two callers (the state-directory loop and the git-dir loop) ignore the status, as before.

3e. DR 19: in `migrate_docs`, find:

```bash
  if [ -z "$(g -C "$wt" ls-files -- "docs/$name" | head -n 1)" ]; then mv_plain "$old" "$new"; return 0; fi
```

Replace with:

```bash
  if [ -z "$(g -C "$wt" ls-files -- "docs/$name" | head -n 1)" ]; then mv_plain "$old" "$new" || docs_ok=0; return 0; fi
```

3f. DR 23: in `rewrite_names`, find:

```bash
  if [ "$dry" -eq 1 ]; then
    ! renamed_lines "$file" "$mode" | cmp -s -- - "$file" || return 1
```

Replace with:

```bash
  if [ "$dry" -eq 1 ]; then
    # Piped into cmp, a failed rewrite would read as a difference; the real
    # run skips it, so the dry run lists nothing.
    renamed_lines "$file" "$mode" > /dev/null || return 1
    ! renamed_lines "$file" "$mode" | cmp -s -- - "$file" || return 1
```

3g. DR 15: skip fenced code blocks in the prefix rewrite. Find:

```bash
PREFIX_RE='(^|[^A-Za-z0-9_-])dr-(superpowers|forge):([a-z])'

# rewrite_prefixes FILE CHECKOUT — the older plugin prefixes before a skill or
# agent name, as dforge's own. Status 1 when FILE names none, or is not
# writable in CHECKOUT.
rewrite_prefixes() {
  local file=$1 tmp
  writable "$2" "$file" || return 1
  grep -qE "$PREFIX_RE" "$file" 2>/dev/null || return 1
  if [ "$dry" -eq 1 ]; then
    printf 'would rewrite the plugin prefixes in %s\n' "$file"
    moved=1
    return 0
  fi
  tmp=$(mktemp "$file.dforge-migrate.XXXXXX") || { refuse "could not rewrite the plugin prefixes in $file"; return 1; }
  if sed -E "s#$PREFIX_RE#\\1dforge:\\3#g" "$file" > "$tmp" && cat "$tmp" > "$file"; then
```

Replace with the block below. `prefixes_renamed` is an awk program in single quotes, so its backticks stay literal. It tracks fences as CommonMark does: a fence opens on up to three spaces and three or more backticks or tildes, and closes only on the same character, at least as long, with nothing but spaces after it. awk has no backreferences, so `rename` walks each match instead of using `sub`; the boundary test is `PREFIX_RE`'s `(^|[^A-Za-z0-9_-])`.

````bash
PREFIX_RE='(^|[^A-Za-z0-9_-])dr-(superpowers|forge):([a-z])'
# prefixes_renamed FILE — FILE with the older plugin prefixes outside fenced
# code blocks rewritten as dforge's own. A fence is quoted text, never rewritten.
prefixes_renamed() {
  awk '
    function rename(line,   out, prev) {
      out = ""
      while (match(line, /dr-(superpowers|forge):[a-z]/)) {
        prev = RSTART > 1 ? substr(line, RSTART - 1, 1) : substr(out, length(out), 1)
        if (prev == "" || prev !~ /[A-Za-z0-9_-]/) {
          out = out substr(line, 1, RSTART - 1) "dforge:"
          line = substr(line, RSTART + RLENGTH - 1)
        } else {
          out = out substr(line, 1, RSTART)
          line = substr(line, RSTART + 1)
        }
      }
      return out line
    }
    fence == "" && match($0, /^ ? ? ?(```+|~~~+)/) {
      fence = substr($0, RSTART, RLENGTH); sub(/^ +/, "", fence); print; next
    }
    fence == "" { print rename($0); next }
    match($0, /^ ? ? ?(```+|~~~+)[ \t]*$/) {
      f = $0; sub(/^ +/, "", f); sub(/[ \t]+$/, "", f)
      if (substr(f, 1, 1) == substr(fence, 1, 1) && length(f) >= length(fence)) fence = ""
    }
    { print }
  ' "$1"
}

# rewrite_prefixes FILE CHECKOUT — the older plugin prefixes before a skill or
# agent name, as dforge's own. Status 1 when FILE names none outside a fenced
# block, or is not writable in CHECKOUT.
rewrite_prefixes() {
  local file=$1 tmp
  writable "$2" "$file" || return 1
  grep -qE "$PREFIX_RE" "$file" 2>/dev/null || return 1
  if [ "$dry" -eq 1 ]; then
    ! prefixes_renamed "$file" | cmp -s -- - "$file" || return 1
    printf 'would rewrite the plugin prefixes in %s\n' "$file"
    moved=1
    return 0
  fi
  tmp=$(mktemp "$file.dforge-migrate.XXXXXX") || { refuse "could not rewrite the plugin prefixes in $file"; return 1; }
  if ! prefixes_renamed "$file" > "$tmp"; then
    rm -f -- "$tmp"
    refuse "could not rewrite the plugin prefixes in $file"
    return 1
  fi
  # Every prefix sat inside a fenced block: nothing to rewrite.
  if cmp -s -- "$tmp" "$file"; then
    rm -f -- "$tmp"
    return 1
  fi
  if cat "$tmp" > "$file"; then
````

The lines that follow (`    rm -f -- "$tmp"`, `    printf 'rewrote the plugin prefixes in %s\n' "$file"`, … through the final `refuse "could not rewrite the plugin prefixes in $file"` / `return 1` / `}`) stay as they are.

3h. DR 20: in `rewrite_active_plans`, find:

```bash
  local wt=$1 docs=$2 plan rel state
```

Replace with:

```bash
  local wt=$1 docs=$2 plan rel state note
```

Then find:

```bash
  for state in .dforge .forge .superpowers; do
    [ ! -f "$wt/$state/handoff/latest.md" ] || rewrite_prefixes "$wt/$state/handoff/latest.md" "$wt" || true
  done
}
```

Replace with:

```bash
  # A real run rewrites only .dforge/'s note: one still under an old state
  # directory was left there by a refused merge. A dry run moved nothing, so
  # it also lists an old directory's note that a line above would move.
  [ ! -f "$wt/.dforge/handoff/latest.md" ] || rewrite_prefixes "$wt/.dforge/handoff/latest.md" "$wt" || true
  [ "$dry" -eq 1 ] || return 0
  for state in .forge .superpowers; do
    note="$wt/$state/handoff/latest.md"
    [ ! -f "$note" ] || ! would_move "$note" || rewrite_prefixes "$note" "$wt" || true
  done
}
```

3i. DR 21 and DR 25: find:

```bash
    [ "$home_status" -eq 0 ] || refuse "scripts/lib/dforge-home-migrate.mjs did not finish; see its output above"
```

Replace with:

```bash
    if [ "$home_status" -ne 0 ]; then
      # A dry run's refusals are foretold, not a failure to finish; a non-zero
      # exit with no refused: line is a crash in either mode.
      if [ "$dry" -eq 1 ] && grep -q '^dforge-home-migrate: refused: ' <<<"$home_out"; then
        refuse "foretold refusals in the home; see above"
      else
        refuse "scripts/lib/dforge-home-migrate.mjs did not finish; see its output above"
      fi
    fi
```

Then run `bash -n plugins/dforge/scripts/dforge-migrate`. It prints nothing.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `timeout 600 bash plugins/dforge/tests/dforge-migrate.test.sh`
Expected: PASS (`183 passed, 0 failed`).

Also run:
- `timeout 600 bash plugins/dforge/tests/migrate-skill.test.sh`: PASS.
- `timeout 120 node scripts/validate-repository.mjs`: no errors. The script and its suite are on the validator's `legacyAllowed` list, so the new `dr-forge:` strings are allowed.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/scripts/dforge-migrate plugins/dforge/tests/dforge-migrate.test.sh
git commit -m "fix(dforge): make migrate dry runs match real runs"
```

---

### Task 32: State the migrate skill's scope and dry-run limit

**Files:**
- Modify: `plugins/dforge/skills/migrate/SKILL.md`
- Test: `plugins/dforge/tests/migrate-skill.test.sh`
- Test: `plugins/dforge/tests/dforge-dir.test.sh`

**Interfaces:**
- Consumes: None
- Produces: None

**Items:** DR 24, DR 26, DR 27, DR 28

**Depends on:** Task 31
**Implementer:** dr-superpowers:impl-sonnet-low
**Executor:** codex gpt-6.1-sol / low
**Evaluation:** files 1 - spec 0 - coupling 0 - risk 1 = 2

- [ ] **Step 1: Write the failing tests**

The tests prove these points:
- The skill announces the repository, the home and darkmem (DR 27).
- The skill says the real run can refuse where the dry run exited 0 (DR 24).
- The commit confirmation follows the real-run line (DR 26, coverage only).
- `dforge_legacy_layout` names mixed `.superpowers`/`.forge` paths, and a primary checkout's own `.forge` (DR 28, coverage only).

1a. DR 26: in `plugins/dforge/tests/migrate-skill.test.sh`, find:

```bash
present "asks before committing" "$SKILL" "human partner agrees, and stage nothing"
```

Replace it with this ordering check. The needle is `Commit only after your` because the skill wraps the sentence after "your". `line_of` matches single lines, and `$real` is defined above.

```bash
commit=$(line_of "$SKILL" 'Commit only after your')
check "the commit confirmation follows the migration" "$([ -n "$commit" ] && [ -n "$real" ] && [ "$real" -lt "$commit" ] && echo yes || echo no)" "yes"
```

The neighbouring check `present "commits only what the commit lines name" "$SKILL" "stage nothing the lines do not name"` stays.

1b. DR 27 and DR 24: in the same file, find:

```bash
present "writes nothing itself" "$SKILL" "This skill writes nothing"
```

Replace with:

```bash
present "writes nothing itself" "$SKILL" "This skill writes nothing"
present "announces the repository, the home and darkmem" "$SKILL" "to move this repository, the home directory's dforge files and darkmem's documents"
present "says the real run can refuse where the dry run passed" "$SKILL" "This run can refuse where the dry run exited 0"
```

1c. DR 28: in `plugins/dforge/tests/dforge-dir.test.sh`, immediately above the line

```bash
# Codex runs no session-start hook, so its tool notes carry the check.
```

insert:

```bash
# --- dforge_legacy_layout: both older names at once ---
mkdir -p "$R/.superpowers" "$R/.forge" "$R/docs/superpowers" "$R/docs/forge"
check "mixed: every older path in one checkout" "$(dforge_legacy_layout "$R" | tr '\n' '|')" "$R/.superpowers|$R/.forge|$R/docs/superpowers|$R/docs/forge|"
rm -rf "$R/.superpowers" "$R/.forge" "$R/docs/superpowers" "$R/docs/forge"
mkdir -p "$WG/dr-superpowers" "$WG/dr-forge" "$G/.superpowers" "$G/.forge"
check "mixed: a worktree's git dir and the primary's state, both names" "$(dforge_legacy_layout "$W" | tr '\n' '|')" "$WG/dr-superpowers|$WG/dr-forge|$TOP/.superpowers|$TOP/.forge|"
rm -rf "$WG/dr-superpowers" "$WG/dr-forge" "$G/.superpowers" "$G/.forge"
SAVED_HOME=$HOME
export HOME="$TMP/home4"; mkdir -p "$HOME/.dr-superpowers" "$HOME/.dr-forge"
printf '{"darkmem":{"repos":{}}}\n' > "$HOME/.dr-superpowers/config.json"
printf '{}\n' > "$HOME/.dr-forge/config.json"
check "mixed: both old homes" "$(dforge_legacy_layout "$R" | tr '\n' '|')" "$HOME/.dr-superpowers|$HOME/.dr-forge|"
export HOME=$SAVED_HOME

# --- dforge_legacy_layout: the primary checkout's own .forge ---
GD=$(git -C "$G" rev-parse --absolute-git-dir)
mkdir -p "$G/.forge" "$GD/dr-forge"
check "primary: its .forge and git dir, each named once" "$(dforge_legacy_layout "$G" | tr '\n' '|')" "$G/.forge|$GD/dr-forge|"
rm -rf "$G/.forge" "$GD/dr-forge"

```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `timeout 600 bash plugins/dforge/tests/migrate-skill.test.sh`
Expected: FAIL with `15 passed, 2 failed`. The two failures are "announces the repository, the home and darkmem" and "says the real run can refuse where the dry run passed": the text is not there yet. "the commit confirmation follows the migration" passes (DR 26 was a coverage gap).

Run: `timeout 600 bash plugins/dforge/tests/dforge-dir.test.sh`
Expected: PASS (`45 passed, 0 failed`): DR 28 was a coverage gap, and `dforge-dir.sh` needs no change.

- [ ] **Step 3: Implement**

3a. DR 27: in `plugins/dforge/skills/migrate/SKILL.md`, find:

```markdown
**Announce at start:** "I'm using the migrate skill to move this repository to dforge's names."
```

Replace with:

```markdown
**Announce at start:** "I'm using the migrate skill to move this repository, the home directory's dforge files and darkmem's documents to dforge's names."
```

3b. DR 24: in the same file, find:

```markdown
5. **Migrate.** Run `bash <plugin-root>/scripts/dforge-migrate` and show its
   output. On exit 1, list each refusal and its fix, and offer to run it again
   once they are resolved: a second run finishes the job.
```

Replace with the text below. Keep the line breaks as shown: the test's needle `This run can refuse where the dry run exited 0` must sit on one line.

```markdown
5. **Migrate.** Run `bash <plugin-root>/scripts/dforge-migrate` and show its
   output. On exit 1, list each refusal and its fix, and offer to run it again
   once they are resolved: a second run finishes the job.
   This run can refuse where the dry run exited 0: the dry run treats a
   directory an earlier line would create as absent, so a second directory
   moving into it (`.superpowers/` and `.forge/` both to `.dforge/`) is listed
   as a move, and only this run merges it and finds a file that differs.
```

This matches the limit stated in the `dforge-migrate` header ("It treats a directory an earlier line would create as absent, so a second source into it is listed as a move rather than a merge").

- [ ] **Step 4: Run the tests to verify they pass**

Run: `timeout 600 bash plugins/dforge/tests/migrate-skill.test.sh`
Expected: PASS (`17 passed, 0 failed`).

Run: `timeout 600 bash plugins/dforge/tests/dforge-dir.test.sh`
Expected: PASS (`45 passed, 0 failed`).

Also run `timeout 120 node scripts/validate-repository.mjs`: no errors. The skill is on its allowlists, and the validator also checks skill files.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/skills/migrate/SKILL.md plugins/dforge/tests/migrate-skill.test.sh plugins/dforge/tests/dforge-dir.test.sh
git commit -m "docs(dforge): state the migrate skill's limits"
```

---

### Task 33: Fix auto-run start lock, beat skew and stale state

**Files:**
- Modify: `plugins/dforge/scripts/lib/auto-run.sh`
- Modify: `plugins/dforge/scripts/auto-run`
- Modify: `plugins/dforge/scripts/session-start.sh`
- Modify: `plugins/dforge/scripts/lib/context.sh`
- Test: `plugins/dforge/tests/auto-run.test.sh`
- Test: `plugins/dforge/tests/turn-end.test.sh`

**Interfaces:**
- Consumes: None
- Produces: `ar_locked PATH COMMAND [ARGS…]` (runs COMMAND holding the state
  file's lock) and `ar_create PATH [jq options…] FILTER` (writes a fresh state
  from `jq -n`), both in `scripts/lib/auto-run.sh`

**Items:** AE 32, AE 33, AE 37, AE 9

**Depends on:** none
**Implementer:** dr-superpowers:impl-sonnet-high
**Evaluation:** files 2 - spec 0 - coupling 0 - risk 3 = 5

This task covers AE 32 sub-findings L2 (`ar_start` writes under the update
lock) and L6 (an ok verdict clears a stale `resume`), AE 33 (heartbeat clock
skew, the session-start cockpit directory, the test `beat` helper), AE 37
(`task-complete` stops the run only in the execute or final phase) and AE 9
sub-finding L4 (the `ctx_line` header comment and the `clear --phase` usage
gloss).

- [ ] **Step 1: Write the failing tests**

The tests prove that a start waits for the lock an update holds, that the
heartbeat age reads skew up to 180 seconds ahead as 0 and anything further
ahead as stale, that the test helper names heartbeat files as `ar_beat_file`
does, that an ok verdict clears a stale `resume`, that `task-complete` in the
primary checkout stops the run only in the execute or final phase, and that a
session start without a session record still makes the cockpit directory.

In `plugins/dforge/tests/auto-run.test.sh`, after the line

```bash
check "a run whose cockpit heartbeat is older than 180 seconds is stale" "$status:$(field session)" "0:s-3"
```

add:

```bash

# --- the heartbeat's age, on a clock that stands still ---
# A fixed clock, so the 180-second boundary cannot slip a second between
# writing a heartbeat and reading it.
NOW=$(date +%s)
CLOCK="$TMP/clock"
mkdir -p "$CLOCK"
printf '#!/usr/bin/env bash\nif [ "$*" = +%%s ]; then echo %s; else exec %s "$@"; fi\n' "$NOW" "$(command -v date)" > "$CLOCK/date"
chmod +x "$CLOCK/date"
stamp() { # stamp <session> <seconds before NOW; negative is ahead of it>
  local f
  f="$HOME/.claude/dforge/sessions/cockpit/$(printf '%s' "$1" | tr -c 'A-Za-z0-9' '-')"
  mkdir -p "$(dirname "$f")"
  printf '%s\n' "$(( NOW - $2 ))" > "$f"
}
at_now() { (cd "$REPO" && PATH="$CLOCK:$PATH" bash "$AR" "$@"); }
age_of() { (PATH="$CLOCK:$PATH"; . "$HERE/../scripts/lib/auto-run.sh"; ar_beat_age "$1") 2>/dev/null || echo fails; }
stamp s-4 180
check "a heartbeat 180 seconds old: age 180" "$(age_of s-4)" "180"
stamp s-4 -5
check "a heartbeat 5 seconds ahead (clock skew): age 0" "$(age_of s-4)" "0"
stamp s-4 -180
check "a heartbeat 180 seconds ahead: age 0" "$(age_of s-4)" "0"
stamp s-4 -181
check "a heartbeat 181 seconds ahead: no age" "$(age_of s-4)" "fails"
stamp s-4 180
at_now --session s-4 start --spec "$SPEC" --register docs/r.md --force >/dev/null 2>&1; status=$?
check "start with a heartbeat 180 seconds old: exit 0" "$status:$(field session)" "0:s-4"
stamp s-3 0
at_now --session s-3 start --spec "$SPEC" --register docs/r.md >/dev/null 2>&1; status=$?
check "a run whose heartbeat is 180 seconds old is live" "$status:$(field session)" "4:s-4"
stamp s-4 -5
at_now --session s-3 start --spec "$SPEC" --register docs/r.md >/dev/null 2>&1; status=$?
check "a run whose heartbeat is a few seconds ahead is live" "$status:$(field session)" "4:s-4"
stamp s-4 -3600
at_now --session s-3 start --spec "$SPEC" --register docs/r.md >/dev/null 2>&1; status=$?
check "a run whose heartbeat is an hour ahead is stale" "$status:$(field session)" "0:s-3"
at_now --session s-4 start --spec "$SPEC" --register docs/r.md --force >/dev/null 2>&1; status=$?
check "start with its own heartbeat an hour ahead: no live cockpit" "$status:$(field session)" "2:s-3"
ar --session s.7 start --spec "$SPEC" --register docs/r.md --force >/dev/null 2>&1; status=$?
check "the beat helper names the file as ar_beat_file does" "$status:$(field session)" "0:s.7"
```

In the same file, after the line

```bash
check "no flock: and released" "$([ -e "$STATE.lockd" ] && echo left || echo gone)" "gone"
```

add:

```bash

# --- a start writes under the same lock as an update ---
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
  wait
  check "$lock: a start waits for the lock" "$(field session):$(field rulings)" "s-2:[]"
done
```

In the same file, after the line

```bash
check "verdict without a window: exit 2" "$status" "2"
```

add:

```bash

# --- an ok verdict clears a resume the cockpit never confirmed ---
ar --session s-1 clear --phase
ar --session s-1 rebind --to s-1
check "rebind: a resume is pending" "$(field pending)" "resume"
out=$(verdict --tokens 10000); status=$?
check "an ok verdict clears a stale resume" "$status:${out%% *}:$(field pending)" "0:ok:null"
```

In the same file, after the line

```bash
check "task-complete in the primary checkout: says to end as Stopping says" "$(grep -c 'the run has stopped. End as reference/auto-run.md §Stopping says.' "$TMP/err")" "1"
```

add:

```bash
for phase in spec plan; do
  ar --session s-1 start --spec "$SPEC" --register docs/r.md --force >/dev/null
  ar --session s-1 phase "$phase"
  ar --session s-1 stalled
  ar --session s-1 task-complete 2>"$TMP/err"; status=$?
  check "task-complete in the primary checkout in the $phase phase: the run goes on" "$status:$(field active):$(field stalls)" "0:true:0"
done
ar --session s-1 start --spec "$SPEC" --register docs/r.md --force >/dev/null
ar --session s-1 attach --plan docs/plan.md
ar --session s-1 phase plan
ar --session s-1 switch
ar --session s-1 task-complete 2>/dev/null; status=$?
check "task-complete in the primary checkout in the execute phase stops the run" "$status:$(field phase):$(field active)" "5:execute:false"
```

In `plugins/dforge/tests/turn-end.test.sh`, after the line

```bash
rm -f "$HOME/.claude/dforge/sessions/turns/s-1.since"
```

add (the `cwd` points at the test repository so session-start never reads the
real checkout):

```bash
H3="$TMP/home-no-record"
mkdir -p "$H3"
jq -n --arg cwd "$REPO" '{session_id:"s-6",cwd:$cwd,source:"startup"}' \
  | HOME="$H3" bash "$HERE/../scripts/session-start.sh" >/dev/null
check "session-start without a transcript writes no session record" \
  "$([ -e "$H3/.claude/dforge/sessions/by-id" ] && echo yes || echo no)" "no"
check "session-start makes the cockpit directory without a session record" \
  "$([ -d "$H3/.claude/dforge/sessions/cockpit" ] && echo yes || echo no)" "yes"
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `timeout 600 bash plugins/dforge/tests/auto-run.test.sh`
Expected: FAIL — 11 checks: "a heartbeat 5 seconds ahead (clock skew): age 0"
(got -5), "a heartbeat 180 seconds ahead: age 0" (got -180), "a heartbeat 181
seconds ahead: no age" (got -181), "a run whose heartbeat is an hour ahead is
stale" (got 4:s-4), "start with its own heartbeat an hour ahead: no live
cockpit" (got 0:s-4), "the beat helper names the file as ar_beat_file does"
(got 2:...: the helper writes `cockpit/s.7`, `ar_beat_file` reads
`cockpit/s-7`; Step 3j fixes the helper), "flock: a start waits for the
lock" and "no-such-flock: a start waits for the lock" (got `s-1:["held"]`: the
holder's write overwrote the start), "an ok verdict clears a stale resume"
(got 0:ok:resume), and the spec and plan "task-complete in the primary
checkout ... the run goes on" checks (got 5:false:1).

Run: `timeout 600 bash plugins/dforge/tests/turn-end.test.sh`
Expected: FAIL — "session-start makes the cockpit directory without a session
record" (got no): the `mkdir` sits inside the record branch.

- [ ] **Step 3: Implement**

**3a.** In `plugins/dforge/scripts/lib/auto-run.sh`, replace the whole
`ar_update` function and its comment:

```bash
# ar_update FILTER [jq options…] — apply a jq filter to the state atomically.
# Concurrent updates (a Stop auto press beside a ruling add) queue instead of
# each reading the file the other is about to replace.
ar_update() {
  local path status
  path=$(ar_path) || return 1
  if command -v "${DFORGE_FLOCK:-flock}" >/dev/null 2>&1; then
    (
      "${DFORGE_FLOCK:-flock}" -w 10 9 || exit 1
      ar_write "$path" "$@"
    ) 9>>"$path.lock"
    return
  fi
  ar_lock_dir "$path.lockd" || return 1
  ar_write "$path" "$@"
  status=$?
  rmdir "$path.lockd" 2>/dev/null
  return $status
}
```

with:

```bash
# ar_update FILTER [jq options…] — apply a jq filter to the state atomically.
# Concurrent updates (a Stop auto press beside a ruling add) queue instead of
# each reading the file the other is about to replace.
ar_update() {
  local path
  path=$(ar_path) || return 1
  ar_locked "$path" ar_write "$path" "$@"
}

# ar_locked PATH COMMAND [ARGS…] — run COMMAND holding the state file's lock:
# flock where there is one, else the lock directory.
ar_locked() {
  local path=$1 status
  shift
  if command -v "${DFORGE_FLOCK:-flock}" >/dev/null 2>&1; then
    (
      "${DFORGE_FLOCK:-flock}" -w 10 9 || exit 1
      "$@"
    ) 9>>"$path.lock"
    return
  fi
  ar_lock_dir "$path.lockd" || return 1
  "$@"
  status=$?
  rmdir "$path.lockd" 2>/dev/null
  return $status
}
```

**3b.** In the same file, directly after the `ar_write` function (whose last
lines are quoted here) and before `# ar_get FIELD — one field, raw; empty for
null or false.`:

```bash
    rm -f "$tmp"
    return 1
  fi
}
```

insert:

```bash

ar_create() { # ar_create PATH [jq options…] FILTER — the state from jq -n
  local path=$1 tmp
  shift
  tmp=$(mktemp "$path.XXXXXX") || return 1
  if ar_jq -n "$@" > "$tmp" && [ -s "$tmp" ]; then
    mv -f "$tmp" "$path"
  else
    rm -f "$tmp"
    return 1
  fi
}
```

**3c.** In the same file, replace `ar_beat_age` and its comment:

```bash
# ar_beat_age SESSION — seconds since the session's cockpit last beat; fails
# when the file is missing or holds no number.
ar_beat_age() {
  local file beat
  file=$(ar_beat_file "$1")
  [ -f "$file" ] || return 1
  beat=$(head -n 1 "$file" | tr -dc '0-9')
  [ -n "$beat" ] || return 1
  echo $(( $(date +%s) - beat ))
}
```

with:

```bash
# ar_beat_age SESSION — seconds since the session's cockpit last beat; fails
# when the file is missing or holds no number. A beat up to AR_BEAT_SECONDS
# ahead of this clock is clock skew and reads as age 0; one further ahead
# fails, so ar_is_stale reads it as stale.
ar_beat_age() {
  local file beat age
  file=$(ar_beat_file "$1")
  [ -f "$file" ] || return 1
  beat=$(head -n 1 "$file" | tr -dc '0-9')
  [ -n "$beat" ] || return 1
  age=$(( $(date +%s) - beat ))
  [ "$age" -ge $(( -AR_BEAT_SECONDS )) ] || return 1
  [ "$age" -ge 0 ] || age=0
  echo "$age"
}
```

**3d.** In `ar_start`, replace the locals line

```bash
  local spec=$1 register=$2 force=$3 path top slug base tmp regfile age
```

with:

```bash
  local spec=$1 register=$2 force=$3 path top slug base regfile age
```

and replace the write at the end of `ar_start`:

```bash
  tmp=$(mktemp "$path.XXXXXX") || return 1
  if ! ar_jq -n --arg s "$AR_SESSION" --arg spec "$spec" --arg reg "$register" --arg base "$base" \
    --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '{
    active: true, session: $s, rebind: false, stopped: null, startedAt: $now,
    spec: $spec, plan: null, register: $reg, base: (if $base == "" then null else $base end),
    phase: "spec", regime: "normal", pending: null, resumePrompt: null, launch: null,
    failures: 0, compactions: 0, resumes: 0, decisions: [], rulings: [],
    setupDue: false, stalls: 0, stalledAt: null, compactionsSinceTask: 0
  }' > "$tmp"; then
    rm -f "$tmp"
    return 1
  fi
  mv -f "$tmp" "$path" || return 1
  printf '%s\n' "$register"
```

with:

```bash
  # Under the update lock, so a --force start never lands between another
  # session's read and write of the state and is lost.
  ar_locked "$path" ar_create "$path" --arg s "$AR_SESSION" --arg spec "$spec" --arg reg "$register" --arg base "$base" \
    --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '{
    active: true, session: $s, rebind: false, stopped: null, startedAt: $now,
    spec: $spec, plan: null, register: $reg, base: (if $base == "" then null else $base end),
    phase: "spec", regime: "normal", pending: null, resumePrompt: null, launch: null,
    failures: 0, compactions: 0, resumes: 0, decisions: [], rulings: [],
    setupDue: false, stalls: 0, stalledAt: null, compactionsSinceTask: 0
  }' || return 1
  printf '%s\n' "$register"
```

(The `mkdir -p "$(dirname "$path")"` line above it stays where it is: the
lock file lives in that directory.)

**3e.** Replace the head of `ar_task_complete` and its comment:

```bash
# ar_task_complete — a task's complete line is written, so the progress counts
# start again. In the primary checkout that task ran on the run's base: the run
# stops (return 5) rather than finish there.
ar_task_complete() {
  if ar_in_primary; then
```

with:

```bash
# ar_task_complete — a task's complete line is written, so the progress counts
# start again. In the primary checkout during the execute or final phase that
# task ran on the run's base: the run stops (return 5) rather than finish
# there. The spec and plan phases belong in the primary checkout.
ar_task_complete() {
  local phase
  phase=$(ar_get phase)
  if { [ "$phase" = execute ] || [ "$phase" = final ]; } && ar_in_primary; then
```

The rest of the function is unchanged.

**3f.** In the comment above `ar_verdict`, replace

```bash
# size; a pending clear is a handoff in progress. An ok clears a compaction a
# wider wave probe requested. Once a compaction ran in the final phases
```

with:

```bash
# size; a pending clear is a handoff in progress. An ok clears a compaction a
# wider wave probe requested, and a resume the cockpit never confirmed: the
# session measuring itself is the resumed one. Once a compaction ran in the final phases
```

and in the body of `ar_verdict` replace

```bash
    if [ "$pending" = compact ]; then ar_update '.pending = null' || return 1; fi
```

with:

```bash
    if [ "$pending" = compact ] || [ "$pending" = resume ]; then ar_update '.pending = null' || return 1; fi
```

**3g.** In `plugins/dforge/scripts/session-start.sh`, replace

```bash
      find "$sessions_dir" "$sessions_dir/by-id" -maxdepth 1 -type f -name '*.json' -mtime +30 -delete 2>/dev/null || true
      # The cockpit writes its heartbeat here (scripts/lib/auto-run.sh
      # ar_beat_file) with $.fs.write, which need not create a directory.
      mkdir -p "$sessions_dir/cockpit" 2>/dev/null || true
      find "$sessions_dir/cockpit" -maxdepth 1 -type f -mtime +30 -delete 2>/dev/null || true
    fi
  fi
```

with:

```bash
      find "$sessions_dir" "$sessions_dir/by-id" -maxdepth 1 -type f -name '*.json' -mtime +30 -delete 2>/dev/null || true
    fi
  fi
  # The cockpit writes its heartbeat here (scripts/lib/auto-run.sh
  # ar_beat_file) with $.fs.write, which need not create a directory, so a
  # start that records no session makes it too.
  cockpit_dir="${HOME:-}/.claude/dforge/sessions/cockpit"
  mkdir -p "$cockpit_dir" 2>/dev/null || true
  find "$cockpit_dir" -maxdepth 1 -type f -mtime +30 -delete 2>/dev/null || true
```

The new block stays inside the `if command -v jq ... && jq -e .` branch, not
at the top level: `tests/hook.test.sh` asserts "malformed: persists nothing"
(no `.claude` directory after malformed stdin), and a top-level `mkdir` breaks
it.

**3h.** In `plugins/dforge/scripts/lib/context.sh`, replace the `ctx_line`
header comment:

```bash
# ctx_line [final | tail R | plan | wave W] — print the budget line; return 0 ok, 5
# handoff, 3 unknown. With final, measure against the final-phase limit instead
# of the task budget; tail R does the same before one of a plan's last R tasks
# (CTX_TAIL_TASKS), so the tail of a plan and its final phase share one limit.
# With wave W, reserve one task's worst growth for each of the W - 1
# tasks that run beside the first, so a parallel wave that starts under its
# budget lands before compaction just as one task does
# (reference/parallel-waves.md). With the handoffMode setting at relaxed, a
# plain task and a wave measure against the final-phase limit too, and the
# label says so.
```

with:

```bash
# ctx_line [final | tail R | plan | wave W] — print the budget line; return 0 ok, 5
# handoff, 6 compact (an auto run only), 3 unknown. With final, measure against
# the final-phase limit instead of the task budget; tail R does the same before
# one of a plan's last R tasks (CTX_TAIL_TASKS), so the tail of a plan and its
# final phase share one limit. With wave W, reserve one task's worst growth for
# each of the W - 1 tasks that run beside the first, so a parallel wave that
# starts under its budget lands before compaction just as one task does
# (reference/parallel-waves.md). With the handoffMode setting at relaxed, a
# plain task and a wave measure against the final-phase limit too, and the
# label says so. An auto run bound to the session (AR_SESSION, else
# CLAUDE_CODE_SESSION_ID) replaces every limit but the plan's with its own
# (ar_verdict, reference/auto-run.md): 6 asks for a compaction and 5 for a
# handoff. With final it first moves the run to its final phase once the
# ledger has every task complete (ar_enter_final).
```

**3i.** In `plugins/dforge/scripts/auto-run`, in the `usage` heredoc, replace

```
pending prints compact, after-compact, handoff, clear, resume, switch, switch-resume or none.
```

with:

```
pending prints compact, after-compact, handoff, clear, resume, switch, switch-resume or none.
clear --phase is the switch from inline to subagent mode and never a self-resume; a plain
      clear is one, and the third in a row stops the run (exit 5).
```

**3j.** In `plugins/dforge/tests/auto-run.test.sh`, the test `beat` helper must
name the file as `ar_beat_file` does. Replace its first two lines:

```bash
beat() { # beat <session> [age in seconds]: the heartbeat a live cockpit writes
  local f="$HOME/.claude/dforge/sessions/cockpit/$1"
```

with:

```bash
beat() { # beat <session> [age in seconds]: the heartbeat a live cockpit writes
  local f
  f="$HOME/.claude/dforge/sessions/cockpit/$(printf '%s' "$1" | tr -c 'A-Za-z0-9' '-')"
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `timeout 600 bash plugins/dforge/tests/auto-run.test.sh`
Expected: PASS

Run: `timeout 600 bash plugins/dforge/tests/turn-end.test.sh`
Expected: PASS

Other suites this change can break, each expected to PASS:
- `timeout 600 bash plugins/dforge/tests/hook.test.sh` (runs session-start.sh
  on malformed and empty stdin)
- `timeout 600 bash plugins/dforge/tests/dforge-dir.test.sh` (runs
  session-start.sh)
- `timeout 600 bash plugins/dforge/tests/context-size.test.sh` (auto-run
  verdicts through `ctx_line`)
- `timeout 600 bash plugins/dforge/tests/budget-line.test.sh` (task-brief and
  review-package inside an auto run)
- `bash -n plugins/dforge/scripts/lib/auto-run.sh plugins/dforge/scripts/auto-run plugins/dforge/scripts/session-start.sh plugins/dforge/scripts/lib/context.sh`

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/scripts/lib/auto-run.sh plugins/dforge/scripts/auto-run plugins/dforge/scripts/session-start.sh plugins/dforge/scripts/lib/context.sh plugins/dforge/tests/auto-run.test.sh plugins/dforge/tests/turn-end.test.sh
git commit -m "fix(auto-run): lock start and bound beat skew" -m "ar_start now writes under the lock ar_update takes, so a --force
start is never lost to another session's update. A heartbeat up to
AR_BEAT_SECONDS ahead reads as age 0 and one further ahead as stale.
An ok verdict clears a stale resume, task-complete stops the run in
the primary checkout only in the execute or final phase, and session
start makes the cockpit directory without a session record. The
ctx_line comment and the clear --phase usage are brought up to date."
```

---

### Task 34: Build stop reasons from caps, quote the root

**Files:**
- Modify: `plugins/dforge/scripts/lib/auto-run.sh`
- Modify: `plugins/dforge/scripts/turn-end.sh`
- Test: `plugins/dforge/tests/auto-run.test.sh`
- Test: `plugins/dforge/tests/turn-end.test.sh`
- Test: `plugins/dforge/tests/cockpit.test.ts`

**Interfaces:**
- Consumes: None
- Produces: None

**Items:** AE 32, AE 35

**Depends on:** Task 7, Task 33
**Implementer:** dr-superpowers:impl-sonnet-medium
**Evaluation:** files 2 - spec 0 - coupling 1 - risk 1 = 4

This task covers AE 35 (stop reasons built from the `AR_*_CAP` variables as
digits, plus the missing progress-field cases) and the script half of AE 32
sub-finding L7 (turn-end.sh quotes the plugin root in its hold reasons).

- [ ] **Step 1: Write the failing tests**

The tests prove that each stop reason says its cap as a digit, that the
progress fields start at zero and are counted from zero in a state written
before they existed, that final- and finish-phase compactions never count
toward `compactionsSinceTask`, that after-compact's unknown-size branch still
names a due Setup, and that every turn-end hold quotes the plugin root.

In `plugins/dforge/tests/auto-run.test.sh`, after the line

```bash
check "start: nothing pending" "$(field pending)" "null"
```

add:

```bash
check "start: no stalls, no compactions since a task" "$(field stalls):$(field stalledAt):$(field compactionsSinceTask)" "0:null:0"
```

In the same file, change the expected value of three existing checks:

```bash
check "the stop says why" "$(field stopped)" "three self-resumes without a completed task"
```

becomes

```bash
check "the stop says why" "$(field stopped)" "3 self-resumes without a completed task"
```

```bash
check "the third execute compaction without a completed task stops the run" "$status:$(field active):$(field stopped)" "5:false:three compactions without a completed task"
```

becomes

```bash
check "the third execute compaction without a completed task stops the run" "$status:$(field active):$(field stopped)" "5:false:3 compactions without a completed task"
```

```bash
check "the third stall without a completed task stops the run" "$status:$(field active):$(field stopped)" "5:false:three stalls without a completed task"
```

becomes

```bash
check "the third stall without a completed task stops the run" "$status:$(field active):$(field stopped)" "5:false:3 stalls without a completed task"
```

In the same file, after the line

```bash
check "stalled with no run bound: exit 3" "$status" "3"
```

add (`after`, `asst` and `$T` are the after-compact helpers defined earlier in
the file):

```bash

# --- the progress fields: a state written before them, and the final phases ---
ar --session s-1 start --spec "$SPEC" --register docs/r.md --force >/dev/null
side --session s-1 phase execute
jq 'del(.stalls, .stalledAt, .compactionsSinceTask)' "$STATE" > "$STATE.old" && mv -f "$STATE.old" "$STATE"
ar --session s-1 stalled; status=$?
check "a state without the progress fields: a stall counts from zero" "$status:$(field stalls)" "0:1"
ar --session s-1 compacted; status=$?
check "a state without the progress fields: a compaction counts from zero" "$status:$(field compactionsSinceTask)" "0:1"
for phase in final finish; do
  ar --session s-1 start --spec "$SPEC" --register docs/r.md --force >/dev/null
  ar --session s-1 phase "$phase"
  ar --session s-1 compacted
  ar --session s-1 compacted
  ar --session s-1 compacted; status=$?
  check "$phase-phase compactions are not counted" "$status:$(field active):$(field compactionsSinceTask)" "0:true:0"
done

# --- after-compact: an unknown size still names a due Setup ---
ar --session s-1 start --spec "$SPEC" --register docs/r.md --force >/dev/null
ar --session s-1 attach --plan docs/plan.md
ar --session s-1 phase plan
ar --session s-1 switch
ar --session s-1 compacted --switch
ar --session s-1 resumed
printf '{}\n' > "$T"
out=$(after); status=$?
check "after-compact: an unknown size with setup due names Setup" "$status:$out:$(field pending)" "0:continue — the size after compaction is unknown; record that with auto-run ruling add, and Claude Code's own compaction stays the backstop; setup due: begin at the execution skill's Setup, worktree first:null"
```

In `plugins/dforge/tests/turn-end.test.sh`, after the line

```bash
HOOKS="$HERE/../hooks/hooks.json"
```

add:

```bash
# The plugin root as turn-end.sh shows it in a hold reason.
SHOWN="$(cd "$HERE/.." && pwd)"
if command -v cygpath >/dev/null 2>&1; then SHOWN=$(cygpath -m "$SHOWN"); fi
```

In the same file, replace

```bash
  "$(jq -r .reason <<<"$out" | grep -c 'scripts/next-step docs/superpowers/plans/2026-10-08-example.md')" "1"
```

with:

```bash
  "$(jq -r .reason <<<"$out" | grep -c 'scripts/next-step" docs/superpowers/plans/2026-10-08-example.md')" "1"
check "mid-plan summary: the plugin root is quoted" \
  "$(jq -r .reason <<<"$out" | grep -cF "\`bash \"$SHOWN/scripts/next-step\" docs/superpowers/plans/2026-10-08-example.md\`")" "1"
```

In the same file, change three existing grep needles (each line otherwise
unchanged):
- `grep -c 'scripts/next-step docs/superpowers/plans/2026-10-09-other.md')`
  becomes `grep -c 'scripts/next-step" docs/superpowers/plans/2026-10-09-other.md')`
- `grep -c 'scripts/next-step docs/dforge/plans/2026-10-10-mirror.md')`
  becomes `grep -c 'scripts/next-step" docs/dforge/plans/2026-10-10-mirror.md')`
- `grep -c 'scripts/next-step --adhoc --phase')`
  becomes `grep -c 'scripts/next-step" --adhoc --phase')`

In the same file, after the line

```bash
check "auto run: the reason names the switching line" "$(jq -r .reason <<<"$out" | grep -c 'end with `Auto run: switching`')" "1"
```

add:

```bash
check "auto run: the stop command quotes the plugin root" "$(jq -r .reason <<<"$out" | grep -cF "run \`bash \"$SHOWN/scripts/auto-run\" stop --reason")" "1"
```

After the line

```bash
check "auto run: the switch hold names the switching line" "$(jq -r .reason <<<"$out" | grep -c 'end your message with the line `Auto run: switching`')" "1"
```

add:

```bash
check "auto run: the switch hold quotes the plugin root" "$(jq -r .reason <<<"$out" | grep -cF "run \`bash \"$SHOWN/scripts/auto-run\" stop --reason")" "1"
```

Replace the line

```bash
check "auto run: after a booked compaction the hold says to settle it" "$(stop s-1 $'Task 3: complete.\n\nAuto run: compacting' | jq -r .reason | grep -c 'auto-run after-compact')" "1"
```

with:

```bash
out=$(stop s-1 $'Task 3: complete.\n\nAuto run: compacting')
check "auto run: after a booked compaction the hold says to settle it" "$(jq -r .reason <<<"$out" | grep -c 'auto-run" after-compact')" "1"
check "auto run: the after-compact hold quotes the plugin root" "$(jq -r .reason <<<"$out" | grep -cF "run \`bash \"$SHOWN/scripts/auto-run\" after-compact\` now")" "1"
```

After the line

```bash
check "auto run: the hold says to hand off and clear" "$(jq -r .reason <<<"$out" | grep -c 'run dforge:handoff')" "1"
```

add:

```bash
check "auto run: the handoff hold quotes the plugin root" "$(jq -r .reason <<<"$out" | grep -cF "then \`bash \"$SHOWN/scripts/auto-run\" clear\`")" "1"
```

In `plugins/dforge/tests/cockpit.test.ts`, change these five strings (each
line otherwise unchanged):
- in the run-control mock, `stopped: 'three compactions without a completed task'`
  becomes `stopped: '3 compactions without a completed task'`
- in the run-control mock, `stopped: 'three stalls without a completed task'`
  becomes `stopped: '3 stalls without a completed task'`
- both occurrences of
  `'The auto run stopped: three compactions without a completed task. End as reference/auto-run.md §Stopping says.'`
  become
  `'The auto run stopped: 3 compactions without a completed task. End as reference/auto-run.md §Stopping says.'`
- `'The auto run stopped: three stalls without a completed task. End as reference/auto-run.md §Stopping says.'`
  becomes
  `'The auto run stopped: 3 stalls without a completed task. End as reference/auto-run.md §Stopping says.'`

Check: `grep -c "three \(compactions\|stalls\)" plugins/dforge/tests/cockpit.test.ts` prints `0`.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `timeout 600 bash plugins/dforge/tests/auto-run.test.sh`
Expected: FAIL — exactly "the stop says why", "the third execute compaction
without a completed task stops the run" and "the third stall without a
completed task stops the run" (each still says "three"). The new progress-field
and unknown-size checks pass already: they are coverage AE 35 found missing.

Run: `timeout 600 bash plugins/dforge/tests/turn-end.test.sh`
Expected: FAIL — 10 checks: "mid-plan summary: names next-step and the plan",
"mid-plan summary: the plugin root is quoted", "two ledgers, menu only: names
the mid-plan ledger's next-step", "auto run: the stop command quotes the plugin
root", "auto run: the switch hold quotes the plugin root", "auto run: after a
booked compaction the hold says to settle it", "auto run: the after-compact
hold quotes the plugin root", "auto run: the handoff hold quotes the plugin
root", "darkmem progress: names the plan", "unplanned: the hold names
next-step --adhoc" (all got 0: the root is unquoted).

The cockpit suite passes before and after; its strings only follow the script.

- [ ] **Step 3: Implement**

In `plugins/dforge/scripts/lib/auto-run.sh`, make three one-line changes:

In `ar_clear`:

```bash
      ar_stop "three self-resumes without a completed task" || return 1
```

becomes

```bash
      ar_stop "$AR_RESUME_CAP self-resumes without a completed task" || return 1
```

In `ar_compacted`:

```bash
    ar_stop "three compactions without a completed task" || return 1
```

becomes

```bash
    ar_stop "$AR_COMPACTION_CAP compactions without a completed task" || return 1
```

In `ar_stalled`:

```bash
    ar_stop "three stalls without a completed task" || return 1
```

becomes

```bash
    ar_stop "$AR_STALL_CAP stalls without a completed task" || return 1
```

In `plugins/dforge/scripts/turn-end.sh`, quote the script path in every hold
reason. Replace all 6 occurrences of

```
bash ${root_shown}/scripts/auto-run 
```

(note the trailing space) with

```
bash \"${root_shown}/scripts/auto-run\" 
```

and both occurrences of

```
bash ${root_shown}/scripts/next-step 
```

with

```
bash \"${root_shown}/scripts/next-step\" 
```

The `\"` is the escaped quote inside the existing double-quoted `reason="..."`
strings. For example the end of the default auto-run hold changes from

```bash
run \`bash ${root_shown}/scripts/auto-run stop --reason \"<why>\"\` first, then end as the attended flow would."
```

to

```bash
run \`bash \"${root_shown}/scripts/auto-run\" stop --reason \"<why>\"\` first, then end as the attended flow would."
```

and the plan-advanced hold's `run \`bash ${root_shown}/scripts/next-step ${plan}\``
becomes `run \`bash \"${root_shown}/scripts/next-step\" ${plan}\``. After the
edit, `grep -cF 'bash ${root_shown}/scripts/' plugins/dforge/scripts/turn-end.sh`
prints `0` and `grep -cF 'bash \"${root_shown}/scripts/' plugins/dforge/scripts/turn-end.sh`
prints `6` (lines, since two reasons name the script twice).

- [ ] **Step 4: Run the tests to verify they pass**

Run: `timeout 600 bash plugins/dforge/tests/auto-run.test.sh`
Expected: PASS

Run: `timeout 600 bash plugins/dforge/tests/turn-end.test.sh`
Expected: PASS

Run: `timeout 300 /root/.local/bin/claude plugin test plugins/dforge`
Expected: PASS (the cockpit's stop-reason prompts)

Run: `bash -n plugins/dforge/scripts/turn-end.sh plugins/dforge/scripts/lib/auto-run.sh`
Expected: no output

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/scripts/lib/auto-run.sh plugins/dforge/scripts/turn-end.sh plugins/dforge/tests/auto-run.test.sh plugins/dforge/tests/turn-end.test.sh plugins/dforge/tests/cockpit.test.ts
git commit -m "fix(auto-run): state caps as digits, quote the root" -m "Stop reasons name AR_RESUME_CAP, AR_COMPACTION_CAP and AR_STALL_CAP
instead of a hardcoded \"three\". turn-end.sh quotes the plugin root in
every command its hold reasons give. Adds the missing progress-field,
final-phase compaction and unknown-size Setup cases."
```

---

### Task 35: Unset the session ids in script suites

**Files:**
- Test: `plugins/dforge/tests/budget-line.test.sh`
- Test: `plugins/dforge/tests/context-size.test.sh`
- Test: `plugins/dforge/tests/repo-audit.test.sh`
- Test: `plugins/dforge/tests/turn-end.test.sh`
- Test: `plugins/dforge/tests/working-directory.test.sh`
- Test: `plugins/dforge/tests/inline-mode.test.sh`

**Interfaces:**
- Consumes: None
- Produces: None

**Items:** AE 32

**Depends on:** Task 34
**Implementer:** dr-superpowers:impl-sonnet-low
**Executor:** codex gpt-6.1-sol / low
**Evaluation:** files 2 - spec 0 - coupling 0 - risk 0 = 2

This task covers part of AE 32 sub-finding L5. A subagent's shell carries the
controller's `CLAUDE_CODE_SESSION_ID`, so a suite run there binds to the live
auto run unless it sets or unsets both `AR_SESSION` and
`CLAUDE_CODE_SESSION_ID`. Six suites other than `auto-run.test.sh` run the
run-control scripts today without handling `AR_SESSION`, and two of them
handle neither variable.

- [ ] **Step 1: Verify which suites are flagged**

This step makes no code change and has no failing test. Run the scan Task 36
commits, as a one-off, from the repository root:

```bash
names='(context-size|auto-run|task-brief|review-package|repo-audit)([^[:alnum:]-]|$)'
runs='(bash[[:space:]]+|"\$|\$)[^[:space:]'"'"'`]*scripts/'"$names"'|(^|[;&|(])[[:space:]]*"?(\./)?scripts/'"$names"
sources='(^|[[:space:];&(])(\.|source)[[:space:]]+[^[:space:]]*scripts/lib/(auto-run|context)\.sh'
for f in plugins/dforge/tests/*.sh; do
  grep -Eq "$runs|$sources" "$f" || continue
  printf '%s AR_SESSION:%s CLAUDE_CODE_SESSION_ID:%s\n' "$(basename "$f")" \
    "$(grep -Ec '^[[:space:]]*(export|unset)[[:space:]](.*[[:space:]])?AR_SESSION([=[:space:]]|$)' "$f")" \
    "$(grep -Ec '^[[:space:]]*(export|unset)[[:space:]](.*[[:space:]])?CLAUDE_CODE_SESSION_ID([=[:space:]]|$)' "$f")"
done
```

Expected output (every count for `AR_SESSION` is 0):

```
auto-run.test.sh AR_SESSION:0 CLAUDE_CODE_SESSION_ID:1
budget-line.test.sh AR_SESSION:0 CLAUDE_CODE_SESSION_ID:1
context-size.test.sh AR_SESSION:0 CLAUDE_CODE_SESSION_ID:3
inline-mode.test.sh AR_SESSION:0 CLAUDE_CODE_SESSION_ID:0
repo-audit.test.sh AR_SESSION:0 CLAUDE_CODE_SESSION_ID:1
turn-end.test.sh AR_SESSION:0 CLAUDE_CODE_SESSION_ID:1
working-directory.test.sh AR_SESSION:0 CLAUDE_CODE_SESSION_ID:0
```

`auto-run.test.sh` is fixed in Task 36.

- [ ] **Step 2: Implement**

`plugins/dforge/tests/budget-line.test.sh`, `plugins/dforge/tests/context-size.test.sh`
and `plugins/dforge/tests/repo-audit.test.sh` each have this exact line near
the top:

```bash
unset DFORGE_BUDGET DFORGE_JQ DR_SUPERPOWERS_BUDGET DR_SUPERPOWERS_JQ CLAUDE_CONFIG_DIR CODEX_HOME CLAUDE_CODE_SESSION_ID CLAUDE_PROJECT_DIR
```

In each of the three, replace it with:

```bash
unset DFORGE_BUDGET DFORGE_JQ DR_SUPERPOWERS_BUDGET DR_SUPERPOWERS_JQ CLAUDE_CONFIG_DIR CODEX_HOME CLAUDE_CODE_SESSION_ID AR_SESSION CLAUDE_PROJECT_DIR
```

(`context-size.test.sh` later exports `CLAUDE_CODE_SESSION_ID=auto-1` for its
own auto-run cases; that stays.)

In `plugins/dforge/tests/turn-end.test.sh`, replace

```bash
unset CLAUDE_CONFIG_DIR CLAUDE_CODE_SESSION_ID DFORGE_BUDGET CLAUDE_PROJECT_DIR
```

with:

```bash
unset CLAUDE_CONFIG_DIR CLAUDE_CODE_SESSION_ID AR_SESSION DFORGE_BUDGET CLAUDE_PROJECT_DIR
```

In `plugins/dforge/tests/working-directory.test.sh`, replace

```bash
unset CLAUDE_CONFIG_DIR CODEX_HOME CLAUDE_PROJECT_DIR
```

with:

```bash
unset CLAUDE_CONFIG_DIR CODEX_HOME CLAUDE_PROJECT_DIR CLAUDE_CODE_SESSION_ID AR_SESSION
```

In `plugins/dforge/tests/inline-mode.test.sh`, after the lines

```bash
# The budget lines asserted here are the defaults'; the suite keeps the real
# home, so the settings in it are kept out by name.
export DFORGE_NO_SETTINGS=1
```

add:

```bash
# Run inside an auto run's session, a brief would bind to that run.
unset CLAUDE_CODE_SESSION_ID AR_SESSION
```

- [ ] **Step 3: Run the suites to verify they pass**

Run each; expected PASS for all six:
- `timeout 600 bash plugins/dforge/tests/budget-line.test.sh`
- `timeout 600 bash plugins/dforge/tests/context-size.test.sh`
- `timeout 600 bash plugins/dforge/tests/repo-audit.test.sh`
- `timeout 600 bash plugins/dforge/tests/turn-end.test.sh`
- `timeout 600 bash plugins/dforge/tests/working-directory.test.sh`
- `timeout 600 bash plugins/dforge/tests/inline-mode.test.sh`

Then prove the suites hold under a live session's environment:
`AR_SESSION=live CLAUDE_CODE_SESSION_ID=live timeout 600 bash plugins/dforge/tests/budget-line.test.sh`
and the same for `inline-mode.test.sh`. Expected: PASS.

Rerun the Step 1 scan. Expected: every line except `auto-run.test.sh` shows
`AR_SESSION:1` and a nonzero `CLAUDE_CODE_SESSION_ID` count.

- [ ] **Step 4: Commit**

```bash
git add plugins/dforge/tests/budget-line.test.sh plugins/dforge/tests/context-size.test.sh plugins/dforge/tests/repo-audit.test.sh plugins/dforge/tests/turn-end.test.sh plugins/dforge/tests/working-directory.test.sh plugins/dforge/tests/inline-mode.test.sh
git commit -m "test(dforge): unset run session in script suites"
```

---

### Task 36: Scan the suites for session hygiene

**Files:**
- Test: `plugins/dforge/tests/auto-run.test.sh`

**Interfaces:**
- Consumes: None
- Produces: None

**Items:** AE 32

**Depends on:** Task 35
**Implementer:** dr-superpowers:impl-sonnet-low
**Evaluation:** files 0 - spec 0 - coupling 1 - risk 0 = 1

This task covers the rest of AE 32 sub-finding L5: the check the spec asks for,
which fails for any suite in `plugins/dforge/tests/*.sh` that runs
`scripts/context-size`, `scripts/auto-run`, `scripts/task-brief`,
`scripts/review-package` or `scripts/repo-audit` (after `bash`, `"$`, `$` or
at the start of a command), or sources `auto-run.sh` or `context.sh`, unless
the suite exports or unsets both `AR_SESSION` and `CLAUDE_CODE_SESSION_ID`, or
every such line passes both on its command line. Run after Task 35.

- [ ] **Step 1: Write the failing test**

The test proves the scan's pattern matches runs and not grep needles, and that
no flagged suite leaves either session variable to the environment.

In `plugins/dforge/tests/auto-run.test.sh`, before the closing lines

```bash
printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
```

add:

```bash

# --- every suite that runs the run-control scripts names its own session ---
# A subagent's shell carries the controller's CLAUDE_CODE_SESSION_ID, so a
# suite run there that leaves it set binds to the live auto run. A line runs a
# script when the path follows bash, "$, $ or starts a command; a line that
# only names it in quoted text, as a grep needle does, is not a match.
names='(context-size|auto-run|task-brief|review-package|repo-audit)([^[:alnum:]-]|$)'
runs='(bash[[:space:]]+|"\$|\$)[^[:space:]'"'"'`]*scripts/'"$names"'|(^|[;&|(])[[:space:]]*"?(\./)?scripts/'"$names"
sources='(^|[[:space:];&(])(\.|source)[[:space:]]+[^[:space:]]*scripts/lib/(auto-run|context)\.sh'
is_run() { grep -Eq "$runs|$sources" <<<"$1" && echo run || echo no; }
check "scan: bash and a path variable is a run" "$(is_run 'out=$(bash "$P/scripts/task-brief" docs/plan.md 1)')" "run"
check "scan: a path kept in a variable is a run" "$(is_run 'AR="$HERE/../scripts/auto-run"')" "run"
check "scan: a command that starts with the path is a run" "$(is_run '(cd "$REPO" && scripts/context-size --final)')" "run"
check "scan: sourcing context.sh is a run" "$(is_run '. "$HERE/../scripts/lib/context.sh"')" "run"
check "scan: a grep needle is not a run" "$(is_run "names \"x\" \"\$F\" '\`scripts/auto-run switch\` and end the turn'")" "no"
check "scan: another script of a similar name is not a run" "$(is_run 'bash "$P/scripts/auto-run-probe"')" "no"
named() { # named <suite> <variable>: the suite exports or unsets it
  grep -Eq "^[[:space:]]*(export|unset)[[:space:]](.*[[:space:]])?$2([=[:space:]]|\$)" "$1"
}
found="" unnamed=""
for suite in "$HERE"/*.sh; do
  lines=$(grep -E "$runs|$sources" "$suite") || continue
  found="$found $(basename "$suite")"
  named "$suite" AR_SESSION && named "$suite" CLAUDE_CODE_SESSION_ID && continue
  # Or every such line passes both on its command line.
  [ -n "$(grep -v 'AR_SESSION=' <<<"$lines"; grep -v 'CLAUDE_CODE_SESSION_ID=' <<<"$lines")" ] || continue
  unnamed="$unnamed $(basename "$suite")"
done
check "scan: this suite is found" "$(case "$found " in *" auto-run.test.sh "*) echo found ;; *) echo missed ;; esac)" "found"
check "every suite that runs the run-control scripts sets or unsets both session variables" "${unnamed# }" ""
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `timeout 600 bash plugins/dforge/tests/auto-run.test.sh`
Expected: FAIL — only "every suite that runs the run-control scripts sets or
unsets both session variables", with got `[auto-run.test.sh]`: this suite's
own `unset` line lacks `AR_SESSION`. (Run before Task 35, the same check
lists all seven suites: `auto-run.test.sh budget-line.test.sh
context-size.test.sh inline-mode.test.sh repo-audit.test.sh turn-end.test.sh
working-directory.test.sh`.) The six `scan:` pattern checks pass.

- [ ] **Step 3: Implement**

In `plugins/dforge/tests/auto-run.test.sh`, replace

```bash
unset DFORGE_BUDGET DFORGE_JQ DFORGE_FLOCK DR_SUPERPOWERS_BUDGET DR_SUPERPOWERS_JQ CLAUDE_CONFIG_DIR CODEX_HOME CLAUDE_CODE_SESSION_ID CLAUDE_PROJECT_DIR
```

with:

```bash
unset DFORGE_BUDGET DFORGE_JQ DFORGE_FLOCK DR_SUPERPOWERS_BUDGET DR_SUPERPOWERS_JQ CLAUDE_CONFIG_DIR CODEX_HOME CLAUDE_CODE_SESSION_ID AR_SESSION CLAUDE_PROJECT_DIR
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `timeout 600 bash plugins/dforge/tests/auto-run.test.sh`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/tests/auto-run.test.sh
git commit -m "test(auto-run): scan suites for session hygiene"
```

---

### Task 37: Share the settings value check

**Files:**
- Modify: `plugins/dforge/config/schema.mjs`
- Create: `plugins/dforge/config/schema.d.mts`
- Modify: `plugins/dforge/scripts/lib/dforge-config.mjs`
- Modify: `plugins/dforge/hooks/cockpit/config.ts`
- Test: `plugins/dforge/tests/dforge-config.test.sh`

**Interfaces:**
- Consumes: None
- Produces: None

**Items:** DF 20

**Depends on:** Task 3, Task 5, Task 6
**Implementer:** dr-superpowers:impl-sonnet-high
**Evaluation:** files 2 - spec 0 - coupling 1 - risk 2 = 5

- [ ] **Step 1: Write the failing test**

The schema module exports the one value check both readers use. Add to
`plugins/dforge/tests/dforge-config.test.sh`, directly above the line
`# --- defaults, set, get, unset ---`:

```bash
# --- the value check lives in the schema module, shared with the cockpit ---
SCHEMA_MJS="$HERE/../config/schema.mjs"
vv() { node --input-type=module -e "import { isValidValue } from '$SCHEMA_MJS'; console.log(isValidValue($1, $2))" 2>&1; }
check "schema exports isValidValue: boolean" "$(vv '{ type: "boolean" }' 'true')" "true"
check "isValidValue: a fraction is not a number setting" "$(vv '{ type: "number", min: 0 }' '1.5')" "false"
check "isValidValue: 0 under a floor means unset" "$(vv '{ type: "number", floor: 1000 }' '0')" "true"
check "isValidValue: under the floor" "$(vv '{ type: "number", floor: 1000 }' '5')" "false"
check "isValidValue: enum member" "$(vv '{ type: "enum", values: ["a"] }' '"a"')" "true"
check "isValidValue: unknown type" "$(vv '{ type: "list" }' '[]')" "false"
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `timeout 600 bash plugins/dforge/tests/dforge-config.test.sh`
Expected: FAIL — the six new checks print a SyntaxError ("does not provide an
export named 'isValidValue'") instead of true/false.

- [ ] **Step 3: Implement**

In `plugins/dforge/config/schema.mjs`, add above the line `export default {`:

```js
// A value as ~/.dforge/config.json must hold it: exactly the setting's type.
// scripts/lib/dforge-config.mjs and the cockpit's config.ts both call this, so
// the two readers cannot disagree about what the file may contain.
export function isValidValue(spec, value) {
  switch (spec.type) {
    case "boolean": return typeof value === "boolean";
    case "number":
      if (typeof value !== "number" || !Number.isInteger(value)) return false;
      // A floor leaves 0 as the one value below it: "unset".
      if (spec.floor !== undefined) return value === 0 || (value >= spec.floor && (spec.max === undefined || value <= spec.max));
      return (spec.min === undefined || value >= spec.min) && (spec.max === undefined || value <= spec.max);
    case "enum": return typeof value === "string" && (spec.values ?? []).includes(value);
    case "string": return typeof value === "string";
    default: return false;
  }
}

```

Create `plugins/dforge/config/schema.d.mts`:

```ts
// Types for schema.mjs, so the cockpit's imports type-check.
export type SettingSpecShape = {
  type: string
  min?: number
  max?: number
  floor?: number
  values?: readonly string[]
}
export function isValidValue(spec: SettingSpecShape, value: unknown): boolean
declare const schema: Record<string, Record<string, unknown>>
export default schema
```

In `plugins/dforge/scripts/lib/dforge-config.mjs`, replace

```js
import SCHEMA from "../../config/schema.mjs";
```

with

```js
import SCHEMA, { isValidValue } from "../../config/schema.mjs";
```

and replace the whole `isValid` function — from the comment line
`// A value as the file holds it: exactly the schema's type.` through its
closing `}` — with:

```js
// A value as the file holds it: exactly the schema's type.
export const isValid = isValidValue;
```

In `plugins/dforge/hooks/cockpit/config.ts`, replace

```ts
import RAW from '../../config/schema.mjs'
```

with

```ts
import RAW, { isValidValue } from '../../config/schema.mjs'
```

and replace the body of `isValidSetting` — everything between
`export function isValidSetting(spec: SettingSpec, value: unknown): value is SettingValue {`
and its closing `}` — with:

```ts
  return isValidValue(spec, value)
```

keeping the `/** Whether a value fits a setting exactly as the file must hold it. */`
comment and the signature unchanged.

- [ ] **Step 4: Run the tests to verify they pass**

Run, from the repository root, each bounded:
- `timeout 600 bash plugins/dforge/tests/dforge-config.test.sh` — PASS
- `timeout 120 node --test tests/repository-layout.test.mjs` — PASS
- `timeout 120 node scripts/validate-repository.mjs` — exit 0
- `timeout 300 /root/.local/bin/claude plugin test plugins/dforge` — PASS
- `timeout 300 npx -y -p typescript@5.6.3 tsc --noEmit -p plugins/dforge` —
  no error names `config.ts` or `config/schema.mjs` (the TS7016 "Could not
  find a declaration file for module '../../config/schema.mjs'" error is
  gone). Errors in `register.tsx` and `cockpit.test.ts` remain; Task 38
  fixes them. When the generated types directory
  `plugins/dforge/.claude-plugin/types/` is empty, run
  `/root/.local/bin/claude plugin test plugins/dforge` first, which
  generates it.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/config/schema.mjs plugins/dforge/config/schema.d.mts plugins/dforge/scripts/lib/dforge-config.mjs plugins/dforge/hooks/cockpit/config.ts plugins/dforge/tests/dforge-config.test.sh
git commit -m "refactor(dforge): share the settings value check"
```

---

### Task 38: Clear the cockpit's type errors

**Files:**
- Modify: `plugins/dforge/hooks/cockpit/register.tsx`
- Modify: `plugins/dforge/hooks/cockpit/settings-view.tsx`
- Test: `plugins/dforge/tests/cockpit.test.ts`

**Interfaces:**
- Consumes: Task 5's type-check step and Task 37's `config/schema.d.mts`
- Produces: None

**Items:** RO 11

**Depends on:** Task 34, Task 37
**Implementer:** dr-superpowers:impl-sonnet-low
**Evaluation:** files 1 - spec 0 - coupling 0 - risk 1 = 2

- [ ] **Step 1: Record the errors**

Run: `timeout 300 npx -y -p typescript@5.6.3 tsc --noEmit -p plugins/dforge`
(when `plugins/dforge/.claude-plugin/types/` is empty, run
`timeout 300 /root/.local/bin/claude plugin test plugins/dforge` first, which
generates it).

Expected: exit 2 with four errors, as Task 5 recorded them on f2471d7 (line
numbers have moved since; find each by its code and text):

```
plugins/dforge/hooks/cockpit/register.tsx(608,11): error TS2769: No overload matches this call.
plugins/dforge/hooks/cockpit/register.tsx(678,59): error TS2345: Argument of type '($: EngineInterface, e: { readonly surface: "mobile"; readonly component: "Pane"; ... }) => Promise<...>' is not assignable to parameter of type '($: EngineInterface, e: ..., next: Next<...>) => ...'.
plugins/dforge/tests/cockpit.test.ts(3958,25): error TS2345: Argument of type '{ reason: "other"; sessionId: string; }' is not assignable to parameter of type 'SessionEndInput'.
plugins/dforge/tests/cockpit.test.ts(4190,69): error TS7053: Element implicitly has an 'any' type because expression of type '"/home/me/code/shop/.dforge/sdd/auto-run.json"' can't be used to index type '{ '/home/me/code/shop/.dforge/handoff/latest.md': { text: string; mtimeMs: number; }; }'.
```

Any other error is new since f2471d7: fix it the same way, or, when it lies
outside these two files, stop and report it.

- [ ] **Step 2: Fix each error without changing behaviour**

These four edits were applied together to a scratch copy of f2471d7 (with Task
37's `config/schema.d.mts`) on 2026-10-19, and `tsc --noEmit` then exited 0.

1. `register.tsx` TS2769 — `outcome` widens to `string`, which `CockpitSpawn`
   does not accept. In the agent-end handler replace:

```ts
    const outcome = e.reason === 'answer' ? 'done' : 'failed'
```

with:

```ts
    const outcome: 'done' | 'failed' = e.reason === 'answer' ? 'done' : 'failed'
```

2. `register.tsx` TS2345 at the `on('ui.render', { component: 'Pane', … })`
   registration — the Pane handler's settings branch returns
   `drawSettings(...)`, declared as `RenderChildren`, which may be undefined;
   the handler must return a `RenderElement`. `drawSettings` always returns
   one `<Box>`, so declare it so. In `plugins/dforge/hooks/cockpit/settings-view.tsx`
   replace:

```ts
import type { EngineInterface, RenderChildren } from 'claude-code'
```

with:

```ts
import type { EngineInterface, RenderChildren, RenderElement } from 'claude-code'
```

and replace:

```ts
export function drawSettings(table: Elements, model: SettingsModel, act: SettingsActions): RenderChildren {
```

with:

```ts
export function drawSettings(table: Elements, model: SettingsModel, act: SettingsActions): RenderElement {
```

3. `cockpit.test.ts` TS2345 — `SessionEndInput` requires `resume`. Replace:

```ts
    await $.session.end({ reason: 'other', sessionId: 'sess-1' })
```

with:

```ts
    await $.session.end({ reason: 'other', sessionId: 'sess-1', resume: { id: 'sess-1' } })
```

4. `cockpit.test.ts` TS7053 — the fixture literal's inferred type lacks the
   `auto-run.json` key it is later indexed with. In the test `'hides Resume
   while a run is active and brings it back when the run stops'` replace:

```ts
    const files = { ...autoFiles({ pending: null }), '/home/me/code/shop/.dforge/handoff/latest.md': { text: RESUMABLE, mtimeMs: 900_000 } }
```

with:

```ts
    const files: NonNullable<World['files']> = { ...autoFiles({ pending: null }), '/home/me/code/shop/.dforge/handoff/latest.md': { text: RESUMABLE, mtimeMs: 900_000 } }
```

If Step 1 listed an error not among these four, fix it with the narrowest
change that matches the declared types (no `// @ts-ignore`,
`// @ts-expect-error` or `as any`), and name it in the task report.

- [ ] **Step 3: Verify**

Run, from the repository root, each bounded:
- `timeout 300 npx -y -p typescript@5.6.3 tsc --noEmit -p plugins/dforge` — exit 0
- `timeout 300 /root/.local/bin/claude plugin test plugins/dforge` — PASS
- `timeout 1800 node scripts/test-all.mjs` — PASS

- [ ] **Step 4: Commit**

```bash
git add plugins/dforge/hooks/cockpit/register.tsx plugins/dforge/hooks/cockpit/settings-view.tsx plugins/dforge/tests/cockpit.test.ts
git commit -m "fix(cockpit): clear the mod's type errors"
```

---

### Task 39: Release dforge 4.2.0

**Files:**
- Modify: `plugins/dforge/.claude-plugin/plugin.json`
- Modify: `plugins/dforge/.codex-plugin/plugin.json`

**Interfaces:**
- Consumes: None
- Produces: None

**Depends on:** Task 17, Task 38
**Implementer:** dr-superpowers:impl-sonnet-low
**Evaluation:** files 1 - spec 0 - coupling 0 - risk 0 = 1

- [ ] **Step 1: Verify the current versions**

Run: `grep -n '"version"' plugins/dforge/.claude-plugin/plugin.json plugins/dforge/.codex-plugin/plugin.json`
Expected: both read `"version": "4.1.0",`.

- [ ] **Step 2: Bump both manifests**

In each of the two files replace `"version": "4.1.0",` with
`"version": "4.2.0",`. Nothing else changes: the 4.1.0 release (3ed6bbc)
changed only version fields, and Task 17 removed the version pin from
`plugins/dforge/tests/review-route.test.sh`.

- [ ] **Step 3: Verify**

Run, from the repository root, each bounded:
- `grep -c '"version": "4.2.0"' plugins/dforge/.claude-plugin/plugin.json plugins/dforge/.codex-plugin/plugin.json` — 1 each
- `timeout 120 node scripts/validate-repository.mjs` — exit 0 (it checks the
  two manifests agree)
- `timeout 600 bash plugins/dforge/tests/review-route.test.sh` — PASS
- `grep -rn '4\.1\.0' plugins/dforge --include=*.json --include=*.sh` — no
  version pin left

- [ ] **Step 4: Leave the register rows to finishing**

Change no register row here. dr-superpowers:finishing-a-development-branch
resolves every row this plan covers in the integration commit: `done` for each,
and `verify` for DF 14, whose acceptance names a CI run only the owner can
start. The four AE bundle rows close the same way; their notes already record
the sub-findings fixed before this plan.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/.claude-plugin/plugin.json plugins/dforge/.codex-plugin/plugin.json
git commit -m "chore(dforge): release 4.2.0"
```
