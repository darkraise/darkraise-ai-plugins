# Task-Loop Steps and Digests Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: the skill the **Execution:** line names — dforge:subagent-driven-development for `subagent`, dforge:executing-plans for `inline`. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Cut the orchestrator's per-task cost: waiting ends the turn instead of polling, `scripts/task-step` runs each loop phase in one call, mechanical checks and Sonnet seats take the simple rulings, `scripts/suite-run` records and digests suite runs, and re-reviews move to a typed judge seat.

**Architecture:** The cockpit (`hooks/cockpit/`) gains a reconcile prompt for an auto run held only by background work, and `scripts/lib/in-flight.sh` prints launch ages for it. `scripts/review-route --ruling` routes simple kinds to `dforge:judge-sonnet-high`. Two new scripts, `scripts/suite-run` and `scripts/task-step`, wrap existing scripts and keep their state under the plan workspace and `<state>`. The skill and reference text then calls them in place of the hand-run steps.

**Tech Stack:** bash (3.2+, mawk-safe awk), jq, git, TypeScript (the cockpit mod and its `claude-code/testing` suite), markdown.

**Spec:** `docs/dforge/specs/2026-10-26-task-loop-steps-design.md`

**Execution:** inline — `claude --model sonnet --effort high` — 2 of 11 tasks are heavy (Tasks 2 and 10, total 5) and are delegated

**Parallelism:** sequential — the spec's Execution strategy line: the text tasks consume every script's interface, and Tasks 5-8 build one script

**Plan review:** 2026-10-26 — dforge:judge-opus — executability 15 / coherence 12 / coverage 16 / assumptions 15 (round 1)

## Global Constraints

- All code changes are under `plugins/dforge/` in this repository; never edit the installed copy under `/root/.claude/plugins/cache/`. Task 11 writes only under `/tmp/dforge-loop-measure-2026-10-26/` (outside the repository, deleted at its end) and `docs/dforge/notes/`.
- Commit as `Darkraise <quangtc94@gmail.com>` (`git -c user.name=Darkraise -c user.email=quangtc94@gmail.com commit …`). No `Co-Authored-By`, `Claude-Session`, "Generated with" or other AI attribution in any commit. Subjects follow `<type>(<scope>): <subject>`, at most 50 characters, imperative, no period.
- Every test suite, build, network call and long-running CLI command runs under `timeout` (quick local `git` calls are exempt). Shell suites run from the repository root as `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID -u CLAUDE_CONFIG_DIR timeout 600 bash plugins/dforge/tests/<name>.test.sh`; the cockpit suite as `timeout 600 /root/.local/bin/claude plugin test plugins/dforge`; the whole sweep as `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID -u CLAUDE_CONFIG_DIR timeout 3600 node scripts/test-all.mjs`.
- `claude` and `rg` are shell functions on this host: call `/root/.local/bin/claude`, and use `grep` in scripts and steps.
- Shell code must run under bash 3.2+ and Git Bash on Windows CI: no awk interval expressions (`{m,n}`; the host awk is mawk 1.3.4), no `grep -P`, no `mapfile`, no `flock`; expand a possibly empty array as `${a[@]+"${a[@]}"}`; strip `\r` from anything read from a file or a command; never rely on `stat -c` alone (fall back to `stat -f %m` for BSD and to `date -r` where neither works).
- New scripts and tests are committed with mode 100644, like `scripts/task-brief` and `tests/fleet.test.sh`, and are run through `bash`.
- `node scripts/validate-repository.mjs` resolves every `dforge:<name>` written under `plugins/dforge/` against `skills/` and `agents/`: never write a glob such as `dforge:judge-*`; name concrete seats.
- Do not edit `docs/superpowers/`, historical plans or specs. The spec is read-only.
- Tests stay apart at run time: the cockpit suite runs in its own mock world, and every shell suite works only inside its own `mktemp -d` directory (a throwaway git repository where it needs one), with `HOME` pointed into it where a script reads dforge settings.
- Codex hosts keep today's loop: every new behaviour that names a Claude Code mechanism leaves `skills/using-dforge/references/codex-tools.md` and `reference/native-codex.md` unchanged.

## Contracts

- **Reconcile prompt** (Task 1), submitted by the cockpit as one prompt, exactly:
  `Background work has run 20 minutes since the last turn with no notification. Run \`scripts/in-flight\`. Stop with TaskStop each launch idle 30 minutes or more, and record a \`Ruling:\` line naming the task it served and that its result is void; leave the others running. Then continue the run, and end the turn again if only waiting remains.`
  with `scripts/in-flight` written as `bash "<plugin root>/scripts/in-flight"` where the cockpit's other prompts name a script that way. Constant `RECONCILE_MS = 1_200_000` in `hooks/cockpit/register.tsx`.
- **`inflight_scan` line** (Task 2), consumed by `scripts/in-flight`, `scripts/turn-end.sh` and `scripts/next-step`: `<agent|shell>\t<task id>\t<started HH:MM>\t<idle Nm|idle ->\t<what>` — five tab-separated fields; `<what>` keeps today's 80-character cut. `scripts/in-flight` prints the fields separated by single spaces.
- **Ruling route** (Task 3): `review-route PLAN_FILE --ruling KIND[,KIND...] [ID ...]` prints `review-seat ruling=<kinds as given> tasks=<ids|plan> primary=<seat> fallback=- reason=<reason>`, where `<seat>` is `dforge:judge-sonnet-high` and `<reason>` is `simple-kind` when every kind is `cannot-verify`, `executor-empty-diff` or `codex-empty-diff` and no named task is risk 3; otherwise `<seat>` is `dforge:judge-opus` with today's reasons (`merge-gate`, `risk`, `intricate`, `routine`).
- **`scripts/suite-run`** (Task 4): `suite-run [--timeout SECONDS] -- COMMAND [ARG ...]`, run from inside a git checkout.
  - Record file `<state>/suites.tsv` (`<state>` = `bash scripts/dforge-path state` in that checkout), one row per run: `<HEAD sha>\t<clean|dirty>\t<command joined by single spaces>\t<exit>\t<log path>\t<epoch>`. Log files `<state>/suites/<epoch>-<pid>.log`.
  - Clean means `git status --porcelain --untracked-files=all` prints nothing.
  - Output: `suite-run: running <m>m` every 300 seconds while the command runs; then exactly one of `suite: reused pass at <sha7> (<age>)`, `suite: pass (exit 0)` or `suite: FAIL (exit <code>)`, followed by `counts: <pass> pass, <fail> fail` when it read counts, up to 20 failing-test lines, or `last 30 lines of <log path>:` and those lines when it matched none; last line `log: <log path>`.
  - Exit: the command's exit code; 0 on a reuse; 124 on timeout (default 3600 s); 2 usage or not in a git checkout.
- **`scripts/task-step`** (Tasks 5, 6, 8):
  - Usage: `task-step start PLAN_FILE N [M ...] [--wave K] [--reset]` · `task-step review PLAN_FILE N [M ...] [--base SHA] [--head REF] [--cwd DIR]` · `task-step rereview PLAN_FILE N [M ...] [--base SHA] [--head REF] [--covered]`. Task numbers are normalised with `10#`, so `01` names Task 1 in every subcommand.
  - Workspace `<ws>` = the directory `bash scripts/sdd-workspace PLAN_FILE` prints; ledger `<ws>/progress.md`.
  - State file `<ws>/task-<N>-step.json` (N = the first task number given), written with `jq`: `{"tasks":[N,...],"base":"<sha>","head":"<ref>"|null,"reviewHead":"<sha>"|null,"round":<int>,"t0":<epoch>|null,"wave":<K>|null}`. `start` writes it with `round` 0, but keeps a state file that already exists (its base, round, review head, `t0` and wave stay, and no second assigned line is written) unless `--reset` discards it, so a restarted task is reviewed from the base its first `start` recorded; `review` sets `reviewHead`, `t0`, with `--base` `base` and with `--head` `head`; `rereview` sets the same four fields the same way and `round` = round + 1, and exits 6 when the fix message for that round is missing. `--cwd DIR` is the working directory `review` puts in the Codex runner command (default: `git rev-parse --show-toplevel`); a wave passes the task's worktree. It is not recorded.
  - Files: `<ws>/task-<N>-dispatch.md` (start), `<ws>/task-<N>-review-prompt.md` and, for a Codex seat, `<ws>/task-<N>-review-codex-prompt.md` (review), `<ws>/task-<N>-rereview-<R>-prompt.md` (rereview, R = the new round). Reports stay `<ws>/task-<N>-report.md`, briefs `<ws>/task-<N>-brief.md` (`task-brief`'s default).
  - A prompt file holds the template's fenced `prompt: |` body with its four-space indent removed and every placeholder replaced; a template section the step does not use (`[LENS_FILES]` with no lens, the Second Pass section below risk 3) is removed with its heading.
  - Digest lines, in order: `task <ids>: <what was done>` (for `start` on a kept state file it says `state kept`); `gate: <codex-gate line>` (review only), right after the `task` line, when `review-route` printed `reason=codex-off` or the gate answered `source=probe`, so the session can write the complete line's `(codex off — <reason>)` clause; the seat line; for a Codex seat `codex: <the exact run-codex-review.sh command>` and `timeout: <ms>`; `check identity: clean|<sha7> <what>` and `check attribution: clean|<sha7> <what>` (review only); `re-review: skipped (<n> changed lines, 1 finding, <file>)` (rereview only, when skipped); `state: base <sha7> review-head <sha7|-> round <R> t0 <epoch|->`; then the budget line `scripts/context-size` prints. At most 15 lines.
  - Seat line forms: `seat: <subagent_type> prompt: <path>` (or `executor <id>: follow executor-lane.md §Dispatch`) for a judge or implementer; for `review` on a failed `review-route` the same judge form ends ` (review-route exited <N>: <first line of its message>)`, names `dforge:judge-opus`, and its prompt file is complete; for a light Codex seat `seat: codex:light prompt: <Codex prompt> fallback: <judge> prompt: <judge prompt>`; for a heavy one `seat: codex:heavy+judge-opus prompt: <Codex prompt> then: dforge:judge-opus prompt: <judge prompt>`. The `fallback:` judge is the seat when the Codex seat fails or times out, and the `then:` judge is the risk 3 second pass; both prompt files are already written, so the session never reruns `review-route` for them. The `rereview` seat line always names `dforge:judge-sonnet-high`; the session dispatches `dforge:judge-opus` in its place for a subtle concurrency fix.
  - Fix message `<ws>/task-<N>-fix-<R>.md`, written by the session before `rereview` for round R: its first lines are one `- <file>: <finding one-liner>` bullet per open finding, then a blank line, then free text.
  - Exit: 0 ok; 2 usage, or any subcommand on a `Host: codex` plan (writing nothing); 3 no such task; 4 an amendment does not apply; 6 a required earlier step has not run (`review` before `start`, `rereview` before `review`).
- **Assigned line** written by `task-step start`: `Task <N>: implementer <agent> (assigned; base <sha7>)`, ending `; wave <K>)` in place of `)` with `--wave K`, as parallel-waves.md writes it today. For a batch, `start` writes one such line per task of the batch, because the ledger grammar and `task_agents` parse only `Task <N>:` lines.
- **Re-review template** (Task 7): `skills/subagent-driven-development/references/re-review-prompt.md` keeps its placeholders `[BRIEF_FILE]`, `[FINDINGS]`, `[REPORT_FILE]`, `[FIX_BASE_SHA]`, `[HEAD_SHA]`, `[DIFF_FILE]`, drops `[MODEL]`, and its block line reads `Subagent (dforge:judge-sonnet-high; dforge:judge-opus for a subtle concurrency fix):`.

## Assumptions (evidence)

- That the cockpit can tell a bound auto run held only by background work, and drive a prompt from it: the watchdog guard `!S.isTurnLive && !S.autoBusy && auto.active && isMainBackground($)` with `activity.endedAt` (`hooks/cockpit/register.tsx`, read 2026-10-26). Unverified — Task 1 verifies it (the spec's riskiest assumption).
- Background launches notify and start a turn: this session (2026-10-26) was restarted by notifications for two background Bash runs and three background Agents; `scripts/turn-end.sh` passes a plain stop while background work runs (its "While background work runs" block).
- This host's Agent launch results carry `output_file: <path>` (observed in this session's results, 2026-10-26), while `tests/in-flight.test.sh`, `tests/turn-end.test.sh` and `tests/snapshot.test.sh` fixtures carry none; subagent transcripts live at `<projects dir>/<session>/subagents/agent-<id>.jsonl` (memory note on the transcript store, 2026-10-23).
- `DEFER_CAP_MS = 1_800_000`, `WATCHDOG_MS = 60_000`, and `autoStage` books a failure once background work has deferred a stage `DEFER_CAP_MS` (`hooks/cockpit/register.tsx`, read 2026-10-26).
- `review-route --ruling` sends every kind to `$OPUS` today (`scripts/review-route`, the `--ruling)` branch).
- `scripts/test-all.mjs` runs every `plugins/dforge/tests/*.test.sh`, so new suites need no registration (the typed-seats plan's assumption, still true: the loop over `plugins/dforge/tests`).
- Prompt templates' placeholders, read 2026-10-26: `implementer-prompt.md` `[BRIEF_FILE] [IMPLEMENTER] [REPORT_FILE]`; `task-reviewer-prompt.md` `[BASE_SHA] [BRIEF_FILE] [CODEX_REVIEW_FILE] [DIFF_FILE] [HEAD_SHA] [JUDGE] [LENS_FILES] [PLUGIN_ROOT] [REPORT_FILE]`; `re-review-prompt.md` `[BRIEF_FILE] [DIFF_FILE] [FINDINGS] [FIX_BASE_SHA] [HEAD_SHA] [MODEL] [REPORT_FILE]`.
- `review-package` prints `wrote <path>: <n> commit(s), <bytes> bytes` (`scripts/review-package:49`); `lens-route --task` prints `lens <id> criteria=<path>` lines (its header).
- Planning ruling on spec §4: suite records live in `<state>/suites.tsv` rather than the plan workspace, because `suite-run` takes no plan argument and the spec places a row "in the checkout the implementer ran in"; `<state>` is per checkout.
- Planning ruling on spec §2: the spec's `task-step` digest names a seat and prompt file; the session still writes the Agent prompt itself (the prompt file's path plus the items only it knows), so no task changes how an Agent call is made.
- Planning ruling on spec §2: two flags beyond the spec's usage lines. `start --reset` exists because a restarted task must keep the base its first `start` recorded (delegated-task.md §Recovery re-enters §1 after a resume), so a repeated `start` keeps the state file and `--reset` is the explicit way to discard it. `review --cwd DIR` exists because the Codex runner command names a working directory, which in a wave is the task's worktree and not the session's top level.
- Task 11's environment, both observed on this host 2026-10-26 and both checked by its steps: `/root/.claude-alt2` holds a login the nested session can use (Step 4 runs it; an invalid login is BLOCKED), and the baseline transcript `/root/.claude/projects/-root-repositories-darkraise-ai-plugins/40cb3d10-fb44-41ea-a1f9-91e02a074fd1.jsonl` is on disk (the store keeps about 30 days; Step 3 handles its absence).
- Codex lane: off for this session (`codex-gate`, 2026-10-26), so the plan is Claude-only.
- Plan review round 1 scored coherence 12 (borderline): its five Important findings were seams between the parallel-drafted slices (the `rereview` state, Task 10's account of Task 6's digest and exit codes, the recovery path, a Common Rationalizations row); all are fixed in place, and no round 2 ran because the round returned no Critical finding and no score of 8 or below.

## Task index

1. Reconcile an auto run held by background work
2. Print launch ages from in-flight
3. Route simple rulings to judge-sonnet-high
4. Add suite-run
5. Add task-step start
6. Add task-step review and its checks
7. Type the re-review seat
8. Add task-step rereview and the skip rule
9. End the turn to wait in subagent-driven-development
10. Run the loop through task-step and suite-run
11. Measure an execution run against the baseline

---

### Task 1: Reconcile an auto run held by background work

**Files:**
- Modify: `plugins/dforge/hooks/cockpit/lib.ts` (a new pure function after `endsOnSentinel`, near line 1385)
- Modify: `plugins/dforge/hooks/cockpit/register.tsx` (the `lib` import, near line 22; constants beside `WATCHDOG_MS`, near line 167; the `S` state, near line 2424; the `session.start` hook, near line 385; `autoStage`, near line 2682; `watchdogTick`, near line 2897)
- Test: `plugins/dforge/tests/cockpit.test.ts` (the `lib` import, near line 5; `describe('pane helpers')`, near line 622; `describe('auto run')`, near line 5389)

**Interfaces:**
- Consumes: none from an earlier task.
- Produces: the Contracts entry "Reconcile prompt" (the exact prompt text, written with `bash "<plugin root>/scripts/in-flight"`) and `RECONCILE_MS = 1_200_000` in `hooks/cockpit/register.tsx`.

**Items:** 2
**Implementer:** dforge:impl-sonnet-medium
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 2 = 4

**Acceptance:** A12, A13

This task also verifies the spec's riskiest assumption: that the cockpit can tell "no live turn, only background work holds a bound run" and drive a prompt from it. Step 2 must pass before anything is built on it.

How the spec's A13 is read: for one pending stage the cockpit submits at most three reconcile prompts in a row while the same launches keep running (the same set of running agents and background shells, under the same pending action). At the next 20-minute occasion it books the stage failure (`scripts/auto-run failure`) in place of a fourth prompt. A launch that ends or is stopped, or a different pending action, restarts the count at one. That counting is a pure function, `reconcileStep`, tested directly, because a test that waits out four 20-minute windows takes about 4.5 seconds here.

Two limits of this test runner shape the tests. First, a single test that runs 5 seconds of real time kills its whole file, and every million milliseconds of fake clock time costs about 0.8 seconds, so no clock test below advances more than about 2.6 million milliseconds; do not lengthen them. Second, when more than one test in `cockpit.test.ts` fails, `claude plugin test` prints `(fail) the file did not load` and `its run ended without a report` in place of the per-test report; a single failure is reported by name.

- [ ] **Step 1: Write the verification test for the assumption**

In `plugins/dforge/tests/cockpit.test.ts`, directly after the line `describe('auto run', () => {` insert the helper (the file's tests build a background agent the same way):

```ts
  const spawnTask4 = ($: Parameters<TestBody>[0]) =>
    $.agent.spawn({
      tool_use_id: 'toolu_1',
      prompt: 'Implement task 4',
      description: 'Task 4',
      subagentType: 'dforge:impl-sonnet-low',
      provider: { plugin: 'dforge', tier: 'user' },
      parentModel: 'claude-opus-5-5',
      background: true,
      fork: false,
    })

```

Then insert this test directly before the line `  test('leaves the run alone while a turn runs', async ($, on) => {`:

```ts
  test('a background agent alone holds a bound run, and its ending frees the run', async ($, on) => {
    const files = autoFiles({ pending: null })
    const w: World = { ...SIGNED_IN, autoRuns: [], prompts: [], autoFile: files[AUTO] }
    const clock = world(on, w)
    signedIn(on, files)
    await $.session.start(START)
    await spawnTask4($)
    await $.turn.complete({ answer: 'Waiting for the implementer.', durationMs: 1, isAborted: false, turnId: 't1', reason: 'answer' })
    await clock.advance(1_100_000)
    expect(w.autoRuns?.filter(call => call.includes(' stalled'))).toEqual([])
    expect(w.prompts).toEqual([])
    await $.turn.complete({ answer: 'Done.', durationMs: 1, isAborted: false, turnId: 'a1', reason: 'answer', agentId: 'agent-1' })
    await clock.advance(60_000)
    expect(w.autoRuns?.filter(call => call.includes(' stalled'))).toHaveLength(1)
  })

```

- [ ] **Step 2: Run it against the unchanged cockpit: the assumption must hold**

Run (from the repository root): `timeout 600 /root/.local/bin/claude plugin test plugins/dforge`
Expected: PASS for `auto run > a background agent alone holds a bound run, and its ending frees the run`, and `0 fail` overall. The test shows the cockpit telling the two states apart: while the agent runs, the watchdog books no stall and submits nothing for 18 minutes (so the run counts as held by background work); once the agent ends, the next tick books the stall. If this test fails, stop: the assumption is false and the rest of this task cannot be built on it. Report BLOCKED with the failing output.

- [ ] **Step 3: Write the reconcile tests**

In `plugins/dforge/tests/cockpit.test.ts`, add `reconcileStep,` to the import from `'../hooks/cockpit/lib'`, directly after the line `  isServiceCommand,`.

Directly after the line `describe('pane helpers', () => {` insert the two tests of the counting rule:

```ts
  test('reconcileStep prompts three times for the same launches, then fails the stage in place of a fourth prompt', () => {
    let seen = { key: '', count: 0 }
    const actions: string[] = []
    for (let i = 0; i < 4; i++) {
      const step = reconcileStep(seen, 'compact|a:agent-1', true, 3)
      actions.push(step.action)
      seen = step.seen
    }
    expect(actions).toEqual(['prompt', 'prompt', 'prompt', 'fail'])
    expect(seen).toEqual({ key: '', count: 0 })
  })

  test('reconcileStep restarts its count when a launch ends or the pending action changes, and never fails without a stage', () => {
    let seen = reconcileStep({ key: '', count: 0 }, 'compact|a:agent-1,a:agent-2', true, 3).seen
    seen = reconcileStep(seen, 'compact|a:agent-1,a:agent-2', true, 3).seen
    seen = reconcileStep(seen, 'compact|a:agent-1,a:agent-2', true, 3).seen
    expect(seen.count).toBe(3)
    expect(reconcileStep(seen, 'compact|a:agent-1', true, 3)).toEqual({ action: 'prompt', seen: { key: 'compact|a:agent-1', count: 1 } })
    expect(reconcileStep(seen, 'clear|a:agent-1,a:agent-2', true, 3).action).toBe('prompt')
    expect(reconcileStep({ key: '|a:agent-1', count: 9 }, '|a:agent-1', false, 3)).toEqual({ action: 'prompt', seen: { key: '|a:agent-1', count: 10 } })
  })

```

Directly after the `spawnTask4` helper from Step 1 (still above the first `test(` of `describe('auto run')`), insert the expected prompt:

```ts
  const RECONCILE_PROMPT =
    /^Background work has run 20 minutes since the last turn with no notification\. Run `bash "[^"]*\/scripts\/in-flight"`\. Stop with TaskStop each launch idle 30 minutes or more, and record a `Ruling:` line naming the task it served and that its result is void; leave the others running\. Then continue the run, and end the turn again if only waiting remains\.$/

```

Insert these tests directly before `  test('leaves the run alone while a turn runs', async ($, on) => {` (after the Step 1 test):

```ts
  for (const holder of ['agent', 'shell'] as const) {
    test(`submits one reconcile prompt when a background ${holder} alone holds a bound run for 20 minutes`, async ($, on) => {
      const files = autoFiles({ pending: null })
      const bash = { Bash: () => ({ result: { stdout: '', stderr: '', interrupted: false, backgroundTaskId: 'b9w1' }, text: 'Running in the background' }) }
      const w: World = { ...SIGNED_IN, autoRuns: [], prompts: [], autoFile: files[AUTO], tools: bash }
      const clock = world(on, w)
      signedIn(on, files)
      await $.session.start(START)
      if (holder === 'agent') await spawnTask4($)
      else await $.tool.call({ tool: 'Bash', command: 'npm test', run_in_background: true } as never)
      await $.turn.complete({ answer: 'Waiting for the implementer.', durationMs: 1, isAborted: false, turnId: 't1', reason: 'answer' })
      await clock.advance(1_200_000)
      expect(w.prompts).toEqual([])
      await clock.advance(60_000)
      expect(w.prompts).toEqual([expect.stringMatching(RECONCILE_PROMPT)])
      await clock.advance(1_200_000)
      expect(w.prompts).toHaveLength(1)
      await clock.advance(60_000)
      expect(w.prompts).toHaveLength(2)
      expect(w.autoRuns?.filter(call => call.includes(' stalled'))).toEqual([])
    })
  }

  test('submits no reconcile prompt outside an auto run', async ($, on) => {
    const files = autoFiles({ active: false, pending: null })
    const w: World = { ...SIGNED_IN, autoRuns: [], prompts: [], autoFile: files[AUTO] }
    const clock = world(on, w)
    signedIn(on, files)
    await $.session.start(START)
    await spawnTask4($)
    await $.turn.complete({ answer: 'Waiting for the implementer.', durationMs: 1, isAborted: false, turnId: 't1', reason: 'answer' })
    await clock.advance(1_500_000)
    expect(w.prompts).toEqual([])
  })

  test('submits no reconcile prompt while a turn is live', async ($, on) => {
    const files = autoFiles({ pending: null })
    const w: World = { ...SIGNED_IN, autoRuns: [], prompts: [], autoFile: files[AUTO] }
    const clock = world(on, w)
    signedIn(on, files)
    await $.session.start(START)
    await spawnTask4($)
    await $.turn.complete({ answer: 'Waiting for the implementer.', durationMs: 1, isAborted: false, turnId: 't1', reason: 'answer' })
    await $.turn.start({ text: 'How is Task 4 going?', turnId: 't2' })
    await clock.advance(1_500_000)
    expect(w.prompts).toEqual([])
  })

  test("a pending stage's reconcile prompt comes before its 30-minute failure", async ($, on) => {
    const files = autoFiles()
    const w: World = { ...SIGNED_IN, compacts: [], autoRuns: [], prompts: [], autoFile: files[AUTO] }
    const clock = world(on, w)
    signedIn(on, files)
    await $.session.start(START)
    await spawnTask4($)
    await $.turn.complete({ answer: SENTINEL, durationMs: 1, isAborted: false, turnId: 't1', reason: 'answer' })
    await settle(clock)
    await clock.advance(1_265_000)
    expect(w.prompts).toEqual([expect.stringMatching(RECONCILE_PROMPT)])
    expect(w.autoRuns?.filter(call => call.includes(' failure '))).toEqual([])
    await clock.advance(545_000)
    expect(w.autoRuns?.filter(call => call.includes(' failure '))).toHaveLength(1)
    expect(w.compacts).toEqual([])
  })

```

The existing test `ends the run when the deferral cap's failure exits ${code}` now sees the reconcile prompt (at 20 minutes) before its own stop prompt (at 30). In that test, replace

```ts
      expect(w.prompts).toEqual([prompt])
```

with

```ts
      expect(w.prompts).toEqual([expect.stringMatching(RECONCILE_PROMPT), prompt])
```

- [ ] **Step 4: Run the suite to see the new tests fail**

Run: `timeout 600 /root/.local/bin/claude plugin test plugins/dforge`
Expected: FAIL. `tests/cockpit.test.ts` does not load: the runner prints `(fail) the file did not load` with `Export named 'reconcileStep' not found in module` and the path of `hooks/cockpit/lib.ts`.

- [ ] **Step 5: Implement the reconcile prompt in the watchdog**

First, in `plugins/dforge/hooks/cockpit/lib.ts`, directly before the comment block that starts `/**` and ends `* An auto run's compaction point (reference/auto-run.md): the task budget, or`, add:

```ts
/**
 * The next step for a bound run held only by background work, taken every
 * RECONCILE_MS: another prompt, or, once `cap` prompts in a row found the same
 * launches under the same pending action, the failure of the stage that action
 * names (`isStaged`) in place of a further prompt.
 */
export function reconcileStep(
  seen: { key: string; count: number },
  key: string,
  isStaged: boolean,
  cap: number,
): { action: 'prompt' | 'fail'; seen: { key: string; count: number } } {
  const count = seen.key === key ? seen.count : 0
  if (isStaged && count >= cap) return { action: 'fail', seen: { key: '', count: 0 } }
  return { action: 'prompt', seen: { key, count: count + 1 } }
}

```

The remaining edits are in `plugins/dforge/hooks/cockpit/register.tsx`. Each block replaces the exact old text with the new text.

The import. In the import from `'./lib'`, replace

```ts
  rampColor,
  remoteRuns,
```

with

```ts
  rampColor,
  reconcileStep,
  remoteRuns,
```

Constants. Replace

```ts
const WATCHDOG_MS = 60_000
const DEFER_CAP_MS = 1_800_000
const STALL_MS = 180_000
```

with

```ts
const WATCHDOG_MS = 60_000
const DEFER_CAP_MS = 1_800_000
const STALL_MS = 180_000
// How long a bound run may go with no live turn while only background work
// holds it before the watchdog asks the session to look at that work, and how
// many such prompts in a row may find the same launches running before the
// pending stage's failure is booked in place of a further prompt.
const RECONCILE_MS = 1_200_000
const RECONCILE_CAP = 3
```

The prompt. Replace

```ts
// The tools that wait on the person by their nature: their dialog is the question.
```

with

```ts
function reconcilePrompt(root: string): string {
  return `Background work has run 20 minutes since the last turn with no notification. Run \`bash "${root}/scripts/in-flight"\`. Stop with TaskStop each launch idle 30 minutes or more, and record a \`Ruling:\` line naming the task it served and that its result is void; leave the others running. Then continue the run, and end the turn again if only waiting remains.`
}
// The tools that wait on the person by their nature: their dialog is the question.
```

State. Replace

```ts
  // When the last stalled call failed: the watchdog waits STALL_MS before the next.
  stallFailedAt: null as number | null,
```

with

```ts
  // When the last stalled call failed: the watchdog waits STALL_MS before the next.
  stallFailedAt: null as number | null,
  // When the watchdog last submitted a reconcile prompt, and how many in a row
  // found the same launches running under the same pending action.
  reconciledAt: null as number | null,
  reconcileSeen: { key: '', count: 0 },
```

Reset at session start. Replace

```ts
    S.watchedSince = await $.clock.now()
    await beat($)
```

with

```ts
    S.watchedSince = await $.clock.now()
    S.reconciledAt = null
    S.reconcileSeen = { key: '', count: 0 }
    await beat($)
```

The stage failure, moved out of `autoStage` so the watchdog can book it too. Replace

```ts
async function autoStage($: EngineInterface, stage: AutoStage) {
  const auto = await readAutoRun($)
```

with

```ts
// A launch that never reports would hold the stage forever: book it as a
// failure, so the second one stops the run with a reason.
async function bookStageFailure($: EngineInterface, stage: AutoStage, why: string) {
  S.autoDeferredSince = null
  const owner = await $.session.id()
  const code = await autoRunCall($, owner, ['failure', '--reason', why])
  if (code === 0) scheduleAutoAct($, stage, AUTO_RETRY_MS)
  else if (code === 5) await endStoppedRun($)
  else await endUnboundRun($, owner, `${why}, and the failure could not be booked (exit ${code})`)
}

async function autoStage($: EngineInterface, stage: AutoStage) {
  const auto = await readAutoRun($)
```

and, inside `autoStage`, replace

```ts
    // A launch that never reports would hold the stage forever: book it as a
    // failure, so the second one stops the run with a reason.
    S.autoDeferredSince = null
    const owner = await $.session.id()
    const why = `a background launch kept the ${stage} waiting 30 minutes`
    const code = await autoRunCall($, owner, ['failure', '--reason', why])
    if (code === 0) scheduleAutoAct($, stage, AUTO_RETRY_MS)
    else if (code === 5) await endStoppedRun($)
    else await endUnboundRun($, owner, `${why}, and the failure could not be booked (exit ${code})`)
    return
```

with

```ts
    await bookStageFailure($, stage, `a background launch kept the ${stage} waiting 30 minutes`)
    return
```

The watchdog branch. In `watchdogTick`, replace

```ts
  if (await isMainBackground($)) return
  const now = await read($, activity)
  if (now.kind !== 'idle' && now.kind !== 'failed') return
```

with

```ts
  if (await isMainBackground($)) {
    await reconcileBackground($, auto)
    return
  }
  const now = await read($, activity)
  if (now.kind !== 'idle' && now.kind !== 'failed') return
```

The reconcile itself. Replace

```ts
// The run stopped while the session was idle: record it, and give the model a
```

with

```ts
async function backgroundKey($: EngineInterface): Promise<string> {
  const agents = (await read($, spawns)).filter(one => !one.isDone).map(one => `a:${one.agentId}`)
  const commands = (await read($, shells)).filter(one => (one.agentId ?? null) === null && !isServiceCommand(one.command)).map(one => `s:${one.id}`)
  return [...agents, ...commands].sort().join(',')
}

// A bound run with no live turn that only background work holds: a launch that
// hangs never notifies, so each RECONCILE_MS the session is asked to look at
// its launches. That prompt's turn restarts autoStage's deferral clock, so a
// stage held by work that never changes is failed here instead, once
// RECONCILE_CAP prompts in a row found the same launches running.
async function reconcileBackground($: EngineInterface, auto: CockpitAutoRun) {
  const now = await read($, activity)
  if (now.kind !== 'idle' && now.kind !== 'background' && now.kind !== 'failed') return
  const stamp = await $.clock.now()
  const last = Math.max(S.watchedSince ?? 0, now.endedAt ?? 0, S.reconciledAt ?? 0)
  if (stamp - last <= RECONCILE_MS) return
  const stage = WATCHED_STAGES[auto.pending ?? '']
  const step = reconcileStep(S.reconcileSeen, `${auto.pending ?? ''}|${await backgroundKey($)}`, stage !== undefined, RECONCILE_CAP)
  S.reconciledAt = stamp
  S.reconcileSeen = step.seen
  if (step.action === 'fail' && stage !== undefined) {
    await bookStageFailure($, stage, `${RECONCILE_CAP} reconcile prompts left the ${stage} waiting on background work`)
    return
  }
  if (!S.isTurnLive) await $.prompt.submit({ text: reconcilePrompt($.plugin.root), asUser: true }).catch(() => undefined)
}

// The run stopped while the session was idle: record it, and give the model a
```

`last` leaves out `S.autoActedAt` on purpose: a stage deferred by background work retries every 5 seconds and stamps it each time, which would keep the reconcile from ever firing.

- [ ] **Step 6: Run the suite to verify it passes**

Run: `timeout 600 /root/.local/bin/claude plugin test plugins/dforge`
Expected: PASS, `0 fail`, with the new tests listed: the Step 1 test, both `reconcileStep` tests, both `submits one reconcile prompt …` variants, the two no-prompt tests and the pending-stage test, beside every existing test. If the run reports `(fail) the file did not load` again, a test is running close to the 5-second limit: run the suite once more on an idle machine before changing a test. Then run `node scripts/validate-repository.mjs`; expected: it prints that the repository is valid.

- [ ] **Step 7: Commit**

```bash
git add plugins/dforge/hooks/cockpit/lib.ts plugins/dforge/hooks/cockpit/register.tsx plugins/dforge/tests/cockpit.test.ts
git -c user.name=Darkraise -c user.email=quangtc94@gmail.com commit -m "feat(cockpit): reconcile background-held runs"
```

### Task 2: Print launch ages from in-flight

**Files:**
- Modify: `plugins/dforge/scripts/lib/in-flight.sh` (the whole file, given in Step 3)
- Modify: `plugins/dforge/scripts/in-flight` (the listing line, near line 35; the header comment)
- Modify: `plugins/dforge/scripts/turn-end.sh` (the hold reason, near line 115)
- Test: `plugins/dforge/tests/in-flight.test.sh`
- Test: `plugins/dforge/tests/turn-end.test.sh` (one added check)

**Interfaces:**
- Consumes: none from an earlier task.
- Produces: the Contracts entry "`inflight_scan` line": five tab-separated fields `<agent|shell>\t<task id>\t<started HH:MM>\t<idle Nm|idle ->\t<what>`, and `scripts/in-flight` printing them separated by single spaces. The new lib functions are `inflight_mtime`, `inflight_idle` and `inflight_text`.

**Items:** 2
**Implementer:** dforge:impl-sonnet-high
**Evaluation:** files 1 - spec 0 - coupling 2 - risk 2 = 5

**Acceptance:** A11

`scripts/next-step` needs no change: it runs `scripts/in-flight` and prints that script's output, and `tests/next-step.test.sh` already passes with the new lines. Do not edit either. `scripts/turn-end.sh` reads only the count (`grep -c .`) and prints the lines in its hold message, so it only needs the tab-to-space rendering.

The start time is the local time of the launch result's transcript timestamp, and `-` when that entry has none (the repository's older fixtures carry none). The idle age is the whole minutes since the launch's activity file last changed: the file after `Output is being written to:` for a shell, the file after `output_file:` for an agent, and for an agent without a usable named file its own transcript, `<main transcript without .jsonl>/subagents/agent-<id>.jsonl`. An agent's `output_file` is a symbolic link to that transcript on this host, so the link is followed (`stat -L`).

- [ ] **Step 1: Update the existing checks and add the new ones**

In `plugins/dforge/tests/in-flight.test.sh`, change three existing checks to the new line shape (a launch with no timestamp and no activity file prints `-` and `idle -`). Replace

```bash
check "it is named with its id and description" "$(grep -c '^- agent a3 Implement task 3$' <<<"$out")" "1"
```

with

```bash
check "it is named with its id and description" "$(grep -c '^- agent a3 - idle - Implement task 3$' <<<"$out")" "1"
```

Replace

```bash
check "the shell is named" "$(grep -c '^- shell b9 Run the suite$' <<<"$out")" "1"
```

with

```bash
check "the shell is named" "$(grep -c '^- shell b9 - idle - Run the suite$' <<<"$out")" "1"
```

Replace

```bash
check "a long transcript: the launch is named" "$(grep -c '^- shell b10 Watch the build$' <<<"$out")" "1"
```

with

```bash
check "a long transcript: the launch is named" "$(grep -c '^- shell b10 - idle - Watch the build$' <<<"$out")" "1"
```

Then insert this block directly before the line `# --- no transcript for this session ---`:

```bash
# --- start time and idle age ---
result_at() { # result_at <tool_use_id> <iso timestamp> <text>
  fjq -nc --arg id "$1" --arg ts "$2" --arg t "$3" '{type:"user",timestamp:$ts,message:{role:"user",content:[{type:"tool_result",tool_use_id:$id,content:$t}]}}' >> "$TP"
}
ago() { touch -d "$1 minutes ago" "$2"; } # ago <minutes> <file>
: > "$TP"
mkdir -p "$TMP/$SID/subagents"

use toolu_s11 'Run the suite'
result_at toolu_s11 2026-10-26T08:05:00.000Z "Command running in background with ID: b11. Output is being written to: $TMP/b11.output. You will be notified when it completes."
: > "$TMP/b11.output"; ago 47 "$TMP/b11.output"
out=$(TZ=UTC0 bash "$INFLIGHT")
check "a shell: its start time and the idle age of the file its result names" \
  "$(grep -c '^- shell b11 08:05 idle 47m Run the suite$' <<<"$out")" "1"

use toolu_a11 'Implement task 4'
result toolu_a11 "$(printf 'Async agent launched successfully.\nagentId: a11 (internal ID)\noutput_file: %s/a11.output\nDo NOT Read or tail this file.' "$TMP")"
: > "$TMP/a11.output"; ago 12 "$TMP/a11.output"
out=$(bash "$INFLIGHT")
check "an agent: the idle age of its output_file" "$(grep -c '^- agent a11 - idle 12m Implement task 4$' <<<"$out")" "1"

use toolu_a12 'Review task 4'
result toolu_a12 $'Async agent launched successfully.\nagentId: a12 (internal ID)'
: > "$TMP/$SID/subagents/agent-a12.jsonl"; ago 9 "$TMP/$SID/subagents/agent-a12.jsonl"
out=$(bash "$INFLIGHT")
check "an agent with no output_file: the idle age of its own transcript" "$(grep -c '^- agent a12 - idle 9m Review task 4$' <<<"$out")" "1"

use toolu_a13 'Review task 5'
result toolu_a13 "$(printf 'Async agent launched successfully.\nagentId: a13 (internal ID)\noutput_file: %s/gone.output' "$TMP")"
: > "$TMP/$SID/subagents/agent-a13.jsonl"; ago 5 "$TMP/$SID/subagents/agent-a13.jsonl"
out=$(bash "$INFLIGHT")
check "an agent whose named file is gone: its transcript instead" "$(grep -c '^- agent a13 - idle 5m Review task 5$' <<<"$out")" "1"

use toolu_a14 'Review task 6'
result toolu_a14 $'Async agent launched successfully.\nagentId: a14 (internal ID)'
out=$(bash "$INFLIGHT")
check "an agent with neither file: idle -" "$(grep -c '^- agent a14 - idle - Review task 6$' <<<"$out")" "1"

use toolu_a15 'Review task 7'
: > "$TMP/a15-transcript.jsonl"; ago 33 "$TMP/a15-transcript.jsonl"
if ln -s "$TMP/a15-transcript.jsonl" "$TMP/a15.output" 2>/dev/null && [ -L "$TMP/a15.output" ]; then
  result toolu_a15 "$(printf 'Async agent launched successfully.\nagentId: a15 (internal ID)\noutput_file: %s/a15.output' "$TMP")"
  out=$(bash "$INFLIGHT")
  check "an output file that is a link: the age of what it points at" "$(grep -c '^- agent a15 - idle 33m Review task 7$' <<<"$out")" "1"
fi

```

In `plugins/dforge/tests/turn-end.test.sh`, directly after the line

```bash
check "the hold names it" "$(jq -r .reason <<<"$out" | grep -c '^- agent a8 ')" "1"
```

add

```bash
check "the hold shows its start and idle age fields" "$(jq -r .reason <<<"$out" | grep -c '^- agent a8 - idle - ')" "1"
```

- [ ] **Step 2: Run the tests to verify they fail**

Run:
`env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID -u CLAUDE_CONFIG_DIR timeout 600 bash plugins/dforge/tests/in-flight.test.sh`
Expected: FAIL, 9 `FAIL -` lines (the three changed checks and the six new ones; the `a15` link check is among them on a host where `ln -s` makes links).
Run:
`env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID -u CLAUDE_CONFIG_DIR timeout 600 bash plugins/dforge/tests/turn-end.test.sh`
Expected: FAIL on `the hold shows its start and idle age fields`.

- [ ] **Step 3: Replace `scripts/lib/in-flight.sh`**

The whole file becomes:

```bash
# Background work this session started that is still listed as running.
# Sourced by scripts/turn-end.sh, scripts/in-flight and scripts/next-step;
# defines functions only.
#
# The transcript schema is observed, not documented. A launch's tool result
# opens "Command running in background with ID: <id>" (Bash) or "Async agent
# launched" with an "agentId: <id>" line (Agent). Its task notification names
# the launch's tool_use id and a status. A launch is still running when:
#   - it has no notification with a finished status yet, or
#   - its latest notification says the agent "stopped with background work of
#     its own still running": the agent sent its report, but a shell or agent it
#     started is alive, so Claude Code still lists it and will notify again.
# Two kinds of launch never get a notification and are not running: one
# stopped by TaskStop (its result opens "Successfully stopped task: <id>"), and
# one made before the session last started or resumed (SINCE), whose process
# died with the old one. A line that is not JSON is skipped.

# inflight_mtime FILE: the modification time of the file FILE names, in epoch
# seconds, links followed (an agent's output file is a link to its transcript).
# Returns 1 when there is no such file.
inflight_mtime() {
  local t
  [ -n "$1" ] || return 1
  t=$(stat -L -c %Y -- "$1" 2>/dev/null | tr -d '\r') || t=""
  case $t in ''|*[!0-9]*) t=$(stat -L -f %m -- "$1" 2>/dev/null | tr -d '\r') || t="" ;; esac
  case $t in ''|*[!0-9]*) t=$(date -r "$1" +%s 2>/dev/null | tr -d '\r') || t="" ;; esac
  case $t in ''|*[!0-9]*) return 1 ;; esac
  printf '%s' "$t"
}

# inflight_idle KIND ID OUTPUT_FILE TRANSCRIPT: "idle <N>m", the minutes since
# the launch's activity file last changed, or "idle -" when there is none. The
# file is the one the launch result names (OUTPUT_FILE, or "-"); an agent whose
# result names none, or whose named file is gone, is read from its own
# transcript, <session>/subagents/agent-<id>.jsonl beside the main one.
inflight_idle() {
  local kind=$1 id=$2 out=$3 tp=$4 t="" now
  [ "$out" = "-" ] || t=$(inflight_mtime "$out") || t=""
  if [ -z "$t" ] && [ "$kind" = agent ] && [ -n "$tp" ]; then
    t=$(inflight_mtime "${tp%.jsonl}/subagents/agent-$id.jsonl") || t=""
  fi
  if [ -z "$t" ]; then printf 'idle -'; return 0; fi
  now=$(date +%s)
  if [ "$now" -gt "$t" ]; then printf 'idle %sm' $(( (now - t) / 60 )); else printf 'idle 0m'; fi
}

# inflight_scan TRANSCRIPT [SINCE]
# stdout: one line per launch still running, five tab-separated fields:
#   <agent|shell> <task id> <started HH:MM> <idle Nm|idle -> <what>
# The start is the launch result's own timestamp in local time ("-" when it
# has none); the idle age is inflight_idle's; <what> is cut at 80 characters.
# Returns 1 when the transcript could not be scanned, which is not "nothing".
inflight_scan() {
  local tp=$1 since=${2:-} events launched stopped latest running kind id start out what
  [ -n "$tp" ] && [ -f "$tp" ] || return 0
  events=$(set -o pipefail; jq -rR --arg since "$since" 'def hm($t): try ($t | sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601 | localtime | strftime("%H:%M")) catch "-";
      fromjson? | select(.isSidechain? != true)
      | select($since == "" or ((.timestamp? // $since) >= $since))
      | if .type? == "assistant" then
          .message.content? | arrays | .[] | select(.type? == "tool_use")
          | "U\t\(.id // "-")\t\((.input.description? // .input.command? // "") | tostring | gsub("[\t\r\n]+"; " ") | .[0:80])"
        elif .type? == "user" then
          (.timestamp? // "") as $ts
          | .message.content? | arrays | .[] | select(.type? == "tool_result")
          | (.content | if type == "array" then (.[0].text? // "") else tostring end) as $text
          | if ($text | test("^Command running in background with ID")) then
              "L\t\(.tool_use_id // "-")\t\(($text | capture("with ID: (?<id>[A-Za-z0-9_-]+)").id) // "-")\tshell\t\(hm($ts))\t\(([$text | capture("Output is being written to: (?<p>[^\\s]+)").p | sub("\\.$"; "")] | first) // "-")"
            elif ($text | test("^Async agent launched")) then
              "L\t\(.tool_use_id // "-")\t\(($text | capture("agentId: (?<id>[A-Za-z0-9_-]+)").id) // "-")\tagent\t\(hm($ts))\t\(([$text | capture("output_file: (?<p>[^\\s]+)").p] | first) // "-")"
            elif ($text | test("^(\\{\"message\":\")?Successfully (stopped task|killed shell): ")) then
              "S\t\(($text | capture("Successfully (stopped task|killed shell): (?<id>[A-Za-z0-9_-]+)").id) // "-")"
            else empty end
        else empty end' "$tp" 2>/dev/null | tr -d '\r') || return 1
  launched=$(awk -F '\t' '$1 == "L" && $2 != "-"' <<<"$events")
  [ -n "$launched" ] || return 0
  stopped=$(awk -F '\t' '$1 == "S" && $2 != "-" { print $2 }' <<<"$events" | sort -u)
  # The latest notification per launch decides. Notifications are read only
  # where Claude Code delivers them (a queued command, a queue operation, or a
  # user message's own text), never from tool output that quotes one. Each is
  # copied into several entries, in order, so the last copy is the latest.
  latest=$(set -o pipefail; jq -rR 'fromjson? | select(.isSidechain? != true)
      | [ .attachment.prompt?, (select(.type? == "queue-operation") | .content?),
          (select(.type? == "user") | .message.content? | if type == "string" then . elif type == "array" then (.[] | select(.type? == "text") | .text?) else empty end) ]
      | .[] | strings | select(contains("<task-notification>")) | gsub("[\r\n]+"; " ")' "$tp" 2>/dev/null \
      | awk '
        # One line per delivered text; a text can carry several notifications.
        # A notification names the launch by task id and, usually, by tool_use
        # id: an agent'"'"'s final one after its own work ended carries only the
        # task id. Each key keeps the state of its latest notification.
        { n = split($0, chunk, "</task-notification>")
          for (i = 1; i <= n; i++) {
            c = chunk[i]
            if (c !~ /<status>[a-z_]+<\/status>/) continue
            state = "done"
            if (c ~ /<status>(running|pending)<\/status>/ || c ~ /background work of its own still running/) state = "running"
            seq++
            if (match(c, /<task-id>[^<]+<\/task-id>/)) print "t:" substr(c, RSTART + 9, RLENGTH - 19) "\t" seq "\t" state
            if (match(c, /<tool-use-id>[^<]+<\/tool-use-id>/)) print "u:" substr(c, RSTART + 13, RLENGTH - 27) "\t" seq "\t" state
          } }') || return 1
  # The three tables reach awk as files: a long transcript's events overflow
  # the per-string limit of an environment variable or an argument.
  running=$(awk -F '\t' '
      FILENAME == ARGV[1] { if ($0 != "") gone[$0] = 1; next }
      FILENAME == ARGV[2] { if ($0 != "") { seq[$1] = $2 + 0; state[$1] = $3 }; next }
      FILENAME == ARGV[3] { if ($1 == "U") what[$2] = $3; next }
      { u = "u:" $2; t = "t:" $3; k = ""
        if (u in seq) k = u
        if ((t in seq) && (k == "" || seq[t] > seq[k])) k = t
        if (k != "" && state[k] == "done") next }
      ($3 in gone) || seen[$2]++ { next }
      { w = what[$2]; if (w == "") w = "(no description)"; print $4 "\t" $3 "\t" $5 "\t" $6 "\t" w }' \
      <(printf '%s\n' "$stopped") <(printf '%s\n' "$latest") <(printf '%s\n' "$events") - <<<"$launched") || return 1
  [ -z "$running" ] && return 0
  while IFS=$'\t' read -r kind id start out what; do
    printf '%s\t%s\t%s\t%s\t%s\n' "$kind" "$id" "$start" "$(inflight_idle "$kind" "$id" "$out" "$tp")" "$what"
  done <<<"$running"
}

# inflight_text: inflight_scan's lines on stdin with single spaces between the
# fields, for a person to read.
inflight_text() { tr '\t' ' '; }

# inflight_since SESSION_ID: the time scripts/session-start.sh recorded when
# the session last started or resumed, or nothing.
inflight_since() {
  local f="${HOME:-}/.claude/dforge/sessions/turns/$(printf '%s' "$1" | tr -c 'A-Za-z0-9' '-').since"
  [ -n "$1" ] && [ -f "$f" ] && head -n 1 "$f" | tr -d '\r'
  return 0
}
```

- [ ] **Step 4: Render the fields for people in the two callers**

In `plugins/dforge/scripts/in-flight`, add this paragraph to the header comment, directly above the `# Usage: in-flight` line:

```bash
# Each launch prints as "<agent|shell> <task id> <started HH:MM> <idle Nm|idle -> <what>":
# the start is the launch result's local time, and the idle age is the minutes
# since the launch's output file (an agent's own transcript when its result
# names none) last changed; "-" where there is no such time or file.
#
```

and replace

```bash
sed 's/^/- /' <<<"$running"
```

with

```bash
inflight_text <<<"$running" | sed 's/^/- /'
```

In `plugins/dforge/scripts/turn-end.sh`, in the `reason=` message of the `has_pending_background` block, replace

```bash
$(sed 's/^/- /' <<<"$running")
```

with

```bash
$(inflight_text <<<"$running" | sed 's/^/- /')
```

- [ ] **Step 5: Run the tests to verify they pass**

Run each, expecting `0 failed`:
`env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID -u CLAUDE_CONFIG_DIR timeout 600 bash plugins/dforge/tests/in-flight.test.sh`
`env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID -u CLAUDE_CONFIG_DIR timeout 600 bash plugins/dforge/tests/turn-end.test.sh`
`env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID -u CLAUDE_CONFIG_DIR timeout 600 bash plugins/dforge/tests/next-step.test.sh`
The `next-step` run proves `scripts/next-step` still counts and names the launches with no edit.

- [ ] **Step 6: Commit**

```bash
git add plugins/dforge/scripts/lib/in-flight.sh plugins/dforge/scripts/in-flight plugins/dforge/scripts/turn-end.sh plugins/dforge/tests/in-flight.test.sh plugins/dforge/tests/turn-end.test.sh
git -c user.name=Darkraise -c user.email=quangtc94@gmail.com commit -m "feat(in-flight): print start time and idle age"
```

### Task 3: Route simple rulings to judge-sonnet-high

**Files:**
- Modify: `plugins/dforge/scripts/review-route` (header comment and the `usage` line; the `--ruling)` branch)
- Test: `plugins/dforge/tests/review-route.test.sh` (the "ruling seat" block near line 200 and the "ruling kinds are executor-neutral" block near line 730)

**Acceptance:** A7

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: the Ruling route contract: `review-route PLAN_FILE --ruling KIND[,KIND...] [ID ...]` prints `review-seat ruling=<kinds as given> tasks=<ids|plan> primary=<seat> fallback=- reason=<reason>`. `<seat>` is `dforge:judge-sonnet-high` with `reason=simple-kind` when every kind is `cannot-verify`, `executor-empty-diff` or `codex-empty-diff` and no named task is risk 3; otherwise `dforge:judge-opus` with `merge-gate` (the list names `final-residual`), `risk` (a named task is risk 3), `intricate` (the list names `preflight` on an intricate plan) or `routine`, in that order. A single Opus kind prints exactly what it printed before.

**Items:** 4
**Implementer:** dforge:impl-sonnet-medium
**Evaluation:** files 1 - spec 0 - coupling 2 - risk 1 = 4

The existing `--ruling` branch validates one kind, sends every ruling to `$OPUS` and echoes `$kind`. The new branch validates a comma-separated list with a regex first (so an empty element, a leading or trailing comma, or an empty argument exits 2), checks each element, and keeps every kind name that prints as the caller gave it, including the legacy `codex-empty-diff`.

- [ ] **Step 1: Write the failing tests**

In `plugins/dforge/tests/review-route.test.sh`, make three edits.

Edit 1 - the comment above `rule()` (in the "the ruling seat" block). Replace

```bash
# Every ruling goes to Opus; the reason still marks where a wrong verdict is
# expensive: the merge gate, a risk-3 task, and an intricate plan's preflight.
```

with

```bash
# Rulings go to Opus, except a list made only of cannot-verify and
# executor-empty-diff kinds on no risk-3 task, which goes to Sonnet. The reason
# marks where a wrong verdict is expensive: the merge gate, a risk-3 task, and
# an intricate plan's preflight.
```

Edit 2 - replace the two lines

```bash
rule "$TMP/round.md" --ruling cannot-verify 4
check "a routine item goes to Opus" "$out" "review-seat ruling=cannot-verify tasks=4 primary=dforge:judge-opus fallback=- reason=routine"
```

with

```bash
rule "$TMP/round.md" --ruling cannot-verify 4
check "a cannot-verify item goes to Sonnet" "$out" "review-seat ruling=cannot-verify tasks=4 primary=dforge:judge-sonnet-high fallback=- reason=simple-kind"
rule "$TMP/round.md" --ruling cannot-verify
check "a plan-wide cannot-verify goes to Sonnet" "$out" "review-seat ruling=cannot-verify tasks=plan primary=dforge:judge-sonnet-high fallback=- reason=simple-kind"
rule "$TMP/round.md" --ruling cannot-verify 8
check "a cannot-verify item on a risk-3 task goes to Opus" "$out" "review-seat ruling=cannot-verify tasks=8 primary=dforge:judge-opus fallback=- reason=risk"
rule "$TMP/round.md" --ruling cannot-verify,executor-empty-diff 1 4
check "a list of Sonnet kinds goes to Sonnet" "$out" "review-seat ruling=cannot-verify,executor-empty-diff tasks=1,4 primary=dforge:judge-sonnet-high fallback=- reason=simple-kind"
rule "$TMP/round.md" --ruling cannot-verify,codex-empty-diff 1
check "the legacy kind joins a Sonnet list as given" "$out" "review-seat ruling=cannot-verify,codex-empty-diff tasks=1 primary=dforge:judge-sonnet-high fallback=- reason=simple-kind"
rule "$TMP/round.md" --ruling cannot-verify,breaker 1
check "a mixed list goes to Opus" "$out" "review-seat ruling=cannot-verify,breaker tasks=1 primary=dforge:judge-opus fallback=- reason=routine"
rule "$TMP/round.md" --ruling cannot-verify,executor-empty-diff 1 8
check "a Sonnet list with one risk-3 task goes to Opus" "$out" "review-seat ruling=cannot-verify,executor-empty-diff tasks=1,8 primary=dforge:judge-opus fallback=- reason=risk"
rule "$TMP/light.md" --ruling cannot-verify,final-residual
check "a list naming final-residual is the merge gate" "$out" "review-seat ruling=cannot-verify,final-residual tasks=plan primary=dforge:judge-opus fallback=- reason=merge-gate"
rule "$TMP/round.md" --ruling cannot-verify,preflight
check "a list with preflight on an intricate plan is intricate" "$out" "review-seat ruling=cannot-verify,preflight tasks=plan primary=dforge:judge-opus fallback=- reason=intricate"
for bad in cannot-verify, ,cannot-verify cannot-verify,,breaker cannot-verify,guess ""; do
  rule "$TMP/round.md" --ruling "$bad" 1
  check "a malformed kind list [$bad] exits 2" "$rc" "2"
done
```

Edit 3 - in the "ruling kinds are executor-neutral" block, replace the neutral and legacy expectations (the risk-3 and unknown-kind checks below them stay as they are):

```bash
check "the neutral kind prints itself" \
  "$out" "review-seat ruling=executor-empty-diff tasks=1 primary=dforge:judge-opus fallback=- reason=routine"
```

with

```bash
check "the neutral kind prints itself and goes to Sonnet" \
  "$out" "review-seat ruling=executor-empty-diff tasks=1 primary=dforge:judge-sonnet-high fallback=- reason=simple-kind"
```

and

```bash
check "the legacy kind prints its own spelling, not the new one" \
  "$out" "review-seat ruling=codex-empty-diff tasks=1 primary=dforge:judge-opus fallback=- reason=routine"
```

with

```bash
check "the legacy kind prints its own spelling, not the new one" \
  "$out" "review-seat ruling=codex-empty-diff tasks=1 primary=dforge:judge-sonnet-high fallback=- reason=simple-kind"
```

- [ ] **Step 2: Run the suite to verify it fails**

Run: `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID -u CLAUDE_CONFIG_DIR timeout 600 bash plugins/dforge/tests/review-route.test.sh 2>&1 | grep -c '^FAIL'`
Expected: a count above 0 (the Sonnet expectations and the comma-list cases fail; the Opus cases still pass).

- [ ] **Step 3: Write the implementation**

In `plugins/dforge/scripts/review-route`, edit the header comment: change the usage line `#        review-route PLAN_FILE --ruling KIND [ID ...]` to

```bash
#        review-route PLAN_FILE --ruling KIND[,KIND...] [ID ...]
```

change the `usage()` message to read `--ruling KIND[,KIND...] [ID ...]` in place of `--ruling KIND [ID ...]`, and replace the whole `--ruling)` branch (from the line `  --ruling)` up to, not including, the line `  --final)`) with:

```bash
  --ruling)
    shift
    [ $# -ge 1 ] || usage
    kinds=$1; shift
    [[ "$kinds" =~ ^[a-z-]+(,[a-z-]+)*$ ]] || die "not a ruling kind: $kinds"
    simple=1 residual=0 preflight=0
    for kind in ${kinds//,/ }; do
      case $kind in
        # executor-empty-diff is the neutral kind. codex-empty-diff is its
        # earlier name and stays accepted, but it is not canonicalised: the
        # printf below echoes $kinds, so rewriting it here would change an
        # existing caller's output.
        cannot-verify|executor-empty-diff|codex-empty-diff) ;;
        preflight) simple=0 preflight=1 ;;
        final-residual) simple=0 residual=1 ;;
        plan-conflict|breaker|blocked-plan|acceptance-ambiguous) simple=0 ;;
        *) die "not a ruling kind: $kind" ;;
      esac
    done
    plan_shape
    scores=$(plan_scores "$src")
    ids="" risky=0
    for id in "$@"; do
      [[ "$id" =~ ^([0-9]+)([A-Z]?)$ ]] || die "not a task id: $id"
      row=$(awk -F'\t' -v n="${BASH_REMATCH[1]}" '$1 == n' <<<"$scores")
      [ -n "$row" ] || die "no Task ${BASH_REMATCH[1]} in the plan"
      [ "$(cut -f3 <<<"$row")" != 3 ] || risky=1
      ids="${ids:+$ids,}$id"
    done
    # Only a list made wholly of the simple kinds, on no risk-3 task, leaves
    # Opus; the reason records why, for the ledger.
    seat=$OPUS
    if [ "$residual" -eq 1 ]; then reason=merge-gate
    elif [ "$risky" -eq 1 ]; then reason=risk
    elif [ "$simple" -eq 1 ]; then seat=$SONNET reason=simple-kind
    elif [ "$preflight" -eq 1 ] && [ "$intricate" -eq 1 ]; then reason=intricate
    else reason=routine
    fi
    printf 'review-seat ruling=%s tasks=%s primary=%s fallback=- reason=%s\n' "$kinds" "${ids:-plan}" "$seat" "$reason"
    exit 0 ;;
```

- [ ] **Step 4: Run the suites to verify they pass**

Run: `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID -u CLAUDE_CONFIG_DIR timeout 600 bash plugins/dforge/tests/review-route.test.sh 2>&1 | tail -3`
Expected: `287 passed, 0 failed` (the count may differ by the number of cases other tasks have since added; the last line must read `0 failed`).

Run: `for t in inline-mode process-roles seats native-routing; do env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID -u CLAUDE_CONFIG_DIR timeout 600 bash plugins/dforge/tests/$t.test.sh 2>&1 | tail -1; done`
Expected: four lines, each ending `0 failed`.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/scripts/review-route plugins/dforge/tests/review-route.test.sh
git -c user.name=Darkraise -c user.email=quangtc94@gmail.com commit -m "feat(review-route): route simple rulings to Sonnet"
```

### Task 4: Add suite-run

**Files:**
- Create: `plugins/dforge/scripts/suite-run`
- Create: `plugins/dforge/tests/suite-run.test.sh`

**Acceptance:** A9, A10

**Interfaces:**
- Consumes: `scripts/dforge-path state` for `<state>` and `dforge_self_ignore` from `scripts/lib/dforge-dir.sh`; no earlier task's output.
- Produces: the `scripts/suite-run` contract: `suite-run [--timeout SECONDS] -- COMMAND [ARG ...]`, run from inside a git checkout. It appends `<HEAD sha>\t<clean|dirty>\t<command joined by single spaces>\t<exit>\t<log path>\t<epoch>` to `<state>/suites.tsv` and writes the output to `<state>/suites/<epoch>-<pid>.log`. It prints `suite-run: running <m>m` every 300 seconds, then exactly one of `suite: reused pass at <sha7> (<age>)`, `suite: pass (exit 0)` or `suite: FAIL (exit <code>)`, then `counts: <pass> pass, <fail> fail` when it read counts, up to 20 failing-test lines (or, on a failure that matched none, `last 30 lines of <log path>:` and those lines), and last `log: <log path>`. Exit: the command's code; 0 on a reuse; 124 on timeout; 2 usage, or not in a git checkout. Tasks 9 and 10 call it by this contract.

**Items:** 2
**Implementer:** dforge:impl-sonnet-medium
**Evaluation:** files 1 - spec 0 - coupling 2 - risk 0 = 3

Design points the code carries, each pinned by a test: the run is clean only if `git status --porcelain --untracked-files=all` printed nothing both before and after the command; `suite-run` makes `<state>` self-ignoring (`dforge_self_ignore`), because a `.dforge/` that is not ignored would make its own record dirty the tree and defeat every reuse; the digest prints failing lines only on a non-zero exit, and a non-zero exit that matched no failing line prints the log tail, so a failure is never silent; a timeout waits `SUITE_RUN_KILL_AFTER` (default 10) seconds after TERM and still reports 124; `SUITE_RUN_HEARTBEAT` (default 300) exists so a test can see a heartbeat in seconds.

- [ ] **Step 1: Write the failing test**

Create `plugins/dforge/tests/suite-run.test.sh` (mode 100644, run through `bash`):

```bash
#!/usr/bin/env bash
# suite-run records a command's run per HEAD, reuses a clean pass at the same
# HEAD, and prints a digest that never reports a failure as silence. Every case
# works in a throwaway git repository; HOME points into the temporary directory.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUITE="$HERE/../scripts/suite-run"

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
has() { # has <name> <text> <needle>
  case $2 in
    *"$3"*) printf 'ok   - %s\n' "$1"; pass=$((pass + 1)) ;;
    *) printf 'FAIL - %s\n       missing: [%s]\n       in:      [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)) ;;
  esac
}
lacks() { # lacks <name> <text> <needle>
  case $2 in
    *"$3"*) printf 'FAIL - %s\n       unexpected: [%s]\n' "$1" "$3"; fail=$((fail + 1)) ;;
    *) printf 'ok   - %s\n' "$1"; pass=$((pass + 1)) ;;
  esac
}

TMP=$(mktemp -d)
if command -v cygpath >/dev/null 2>&1; then TMP=$(cygpath -m "$TMP"); fi
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
mkdir -p "$HOME"
export MSYS_NO_PATHCONV=1

REPO="$TMP/repo"
git init -q -b main "$REPO"
git -C "$REPO" config user.name Tester
git -C "$REPO" config user.email tester@example.com
printf 'one\n' > "$REPO/a.txt"
git -C "$REPO" add a.txt
git -C "$REPO" commit -q -m one
commit() { printf '%s\n' "$1" >> "$REPO/a.txt"; git -C "$REPO" commit -q -am "$1"; }

# probe.sh stands in for a test suite: it counts its runs in $PROBE_RUNS, prints
# the file it is given and exits with the code it is given.
export PROBE_RUNS="$TMP/runs"
cat > "$TMP/probe.sh" <<'PROBE'
echo x >> "$PROBE_RUNS"
[ -z "${2:-}" ] || cat "$2"
exit "${1:-0}"
PROBE
runs() { if [ -f "$PROBE_RUNS" ]; then wc -l < "$PROBE_RUNS" | tr -d ' '; else echo 0; fi; }
probe() { run -- bash "$TMP/probe.sh" "$@"; }
run() { out=$(cd "$REPO" && bash "$SUITE" "$@" 2>&1); rc=$?; }
rows() { wc -l < "$REPO/.dforge/suites.tsv" | tr -d ' '; }
last_row() { tail -n 1 "$REPO/.dforge/suites.tsv" | tr -d '\r'; }
field() { last_row | cut -f"$1"; }

printf '# tests 3\n# pass 3\n# fail 0\n' > "$TMP/out-tap-pass"
printf 'ok 1 - a\nnot ok 2 - b broke\nnot ok 3 - c broke\n# pass 1\n# fail 2\n' > "$TMP/out-tap-fail"
printf 'boom: something broke\nsecond line\n' > "$TMP/out-opaque"
seq 1 40 | sed 's/^/line /' > "$TMP/out-long"
printf 'bun test\n(pass) a\n(fail) b > breaks [1.2ms]\n\n 1 pass\n 1 fail\n' > "$TMP/out-bun"
printf 'ok   - one\nFAIL - two\n       want: [a]\n\n3 passed, 1 failed\n' > "$TMP/out-fail-word"
i=0; : > "$TMP/out-many"
while [ "$i" -lt 25 ]; do i=$((i + 1)); printf 'not ok %s - case %s\n' "$i" "$i" >> "$TMP/out-many"; done

# --- a first run, a reuse, and what ends one -------------------------------
HEAD1=$(git -C "$REPO" rev-parse HEAD)
probe 0 "$TMP/out-tap-pass"
check "a passing run exits 0" "$rc" "0"
has "a pass prints its verdict" "$out" "suite: pass (exit 0)"
has "a pass prints the counts it read" "$out" "counts: 3 pass, 0 fail"
check "the digest ends with the log path" "$(printf '%s\n' "$out" | tail -n 1 | cut -c1-5)" "log: "
check "the command ran once" "$(runs)" "1"
check "the row has six fields" "$(last_row | awk -F'\t' '{print NF}')" "6"
check "the row records HEAD" "$(field 1)" "$HEAD1"
check "the row records a clean tree" "$(field 2)" "clean"
check "the row records the command" "$(field 3)" "bash $TMP/probe.sh 0 $TMP/out-tap-pass"
check "the row records the exit" "$(field 4)" "0"
check "the logged output is kept" "$(cat "$(field 5)")" "$(cat "$TMP/out-tap-pass")"
check "the run leaves the tree clean" "$(git -C "$REPO" status --porcelain --untracked-files=all)" ""

probe 0 "$TMP/out-tap-pass"
check "a repeat at the same HEAD exits 0" "$rc" "0"
has "a repeat reuses the pass" "$out" "suite: reused pass at ${HEAD1:0:7} ("
check "a reuse does not run the command" "$(runs)" "1"
check "a reuse records no row" "$(rows)" "1"

probe 0 "$TMP/out-opaque"
check "another command runs" "$(runs)" "2"

commit two
probe 0 "$TMP/out-tap-pass"
check "a new HEAD runs again" "$(runs)" "3"
HEAD2=$(git -C "$REPO" rev-parse HEAD)
check "the new row records the new HEAD" "$(field 1)" "$HEAD2"

# --- a dirty tree never reuses and never records a reusable row --------------
printf 'x\n' > "$REPO/scratch.txt"
probe 0 "$TMP/out-tap-pass"
check "a dirty tree runs despite a clean pass at this HEAD" "$(runs)" "4"
check "the dirty run is recorded as dirty" "$(field 2)" "dirty"
probe 0 "$TMP/out-tap-pass"
check "a dirty tree never reuses its own row" "$(runs)" "5"
rm "$REPO/scratch.txt"
probe 0 "$TMP/out-tap-pass"
has "a clean tree reuses the earlier clean pass" "$out" "suite: reused pass at ${HEAD2:0:7} ("
check "the dirty rows did not run it again" "$(runs)" "5"

commit three
printf 'x\n' > "$REPO/scratch.txt"
probe 0 "$TMP/out-tap-pass"
rm "$REPO/scratch.txt"
probe 0 "$TMP/out-tap-pass"
check "a pass recorded dirty is not reused once the tree is clean" "$(runs)" "7"
check "the clean run is recorded clean" "$(field 2)" "clean"

printf 'tracked change\n' >> "$REPO/a.txt"
probe 0 "$TMP/out-tap-pass"
check "a modified tracked file counts as dirty" "$(field 2)" "dirty"
git -C "$REPO" checkout -q -- a.txt

# --- a command that dirties the tree is recorded dirty -------------------------
commit four
run -- bash -c 'echo made > made.txt'
check "a run that leaves a file behind records dirty" "$(field 2)" "dirty"
rm "$REPO/made.txt"

# --- failures ----------------------------------------------------------------
commit five
probe 1 "$TMP/out-tap-fail"
check "a failing run exits with the command's code" "$rc" "1"
has "a failure prints its verdict" "$out" "suite: FAIL (exit 1)"
has "a failure prints the counts" "$out" "counts: 1 pass, 2 fail"
has "a failure prints its failing lines" "$out" "not ok 2 - b broke"
has "a failure prints every failing line" "$out" "not ok 3 - c broke"
lacks "a matched failure does not print the log tail" "$out" "last 30 lines"
check "the failing exit is recorded" "$(field 4)" "1"
before=$(runs)
probe 1 "$TMP/out-tap-fail"
check "a failure is never reused" "$(runs)" "$((before + 1))"

probe 7 "$TMP/out-opaque"
check "an unmatched failure keeps its exit code" "$rc" "7"
has "an unmatched failure is still a FAIL" "$out" "suite: FAIL (exit 7)"
has "an unmatched failure prints the log tail" "$out" "last 30 lines of "
has "an unmatched failure prints the output" "$out" "boom: something broke"
has "an unmatched failure names the log" "$out" "log: "

probe 4 "$TMP/out-long"
has "the tail holds the last line" "$out" "line 40"
has "the tail holds the 30th line from the end" "$out" "line 11"
lacks "the tail stops at 30 lines" "$out" "line 10"$'\n'
lacks "the tail drops the early lines" "$out" "line 1"$'\n'

probe 5
check "a failure with no output exits non-zero" "$rc" "5"
has "a failure with no output is still reported" "$out" "suite: FAIL (exit 5)"
has "a failure with no output names the log tail" "$out" "last 30 lines of "

probe 1 "$TMP/out-bun"
has "a Bun failing line is matched" "$out" "(fail) b > breaks [1.2ms]"
has "Bun counts are read" "$out" "counts: 1 pass, 1 fail"
lacks "a Bun passing line is not a failing line" "$out" "(pass) a"

probe 1 "$TMP/out-fail-word"
has "a line starting FAIL is matched" "$out" "FAIL - two"
has "a shell suite's summary supplies the counts" "$out" "counts: 3 pass, 1 fail"

probe 1 "$TMP/out-many"
check "at most 20 failing lines are printed" "$(printf '%s\n' "$out" | grep -c '^not ok')" "20"
has "the 20th failing line is printed" "$out" "not ok 20 - case 20"
lacks "the 21st failing line is not" "$out" "not ok 21 - case 21"

run -- bash -c 'printf "not ok 1 - crlf\r\n"; exit 1'
has "a CR does not hide a failing line" "$out" "not ok 1 - crlf"

run -- no-such-command-here
check "a command that does not start fails" "$rc" "127"
has "a command that does not start is reported" "$out" "suite: FAIL (exit 127)"

# --- timeout and heartbeat ---------------------------------------------------------
run --timeout 1 -- sleep 5
check "a timeout exits 124" "$rc" "124"
has "a timeout is a FAIL" "$out" "suite: FAIL (exit 124)"
check "a timeout is recorded" "$(field 4)" "124"

out=$(cd "$REPO" && SUITE_RUN_KILL_AFTER=1 bash "$SUITE" --timeout 1 -- bash -c 'trap "" TERM; sleep 30' 2>&1); rc=$?
check "a command that ignores TERM is still a timeout" "$rc" "124"

out=$(cd "$REPO" && SUITE_RUN_HEARTBEAT=1 bash "$SUITE" -- sleep 3 2>&1); rc=$?
check "a heartbeat run passes" "$rc" "0"
has "a running command prints a heartbeat" "$out" "suite-run: running "

# --- usage ---------------------------------------------------------------------------
run
check "no command exits 2" "$rc" "2"
run -- 
check "an empty command exits 2" "$rc" "2"
run bash -c true
check "a command without -- exits 2" "$rc" "2"
run --timeout x -- true
check "a bad timeout exits 2" "$rc" "2"
run --timeout 0 -- true
check "a zero timeout exits 2" "$rc" "2"
mkdir "$TMP/plain"
out=$(cd "$TMP/plain" && bash "$SUITE" -- true 2>&1); rc=$?
check "outside a git checkout exits 2" "$rc" "2"
has "outside a git checkout says so" "$out" "not in a git checkout"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID -u CLAUDE_CONFIG_DIR timeout 600 bash plugins/dforge/tests/suite-run.test.sh 2>&1 | tail -3`
Expected: the last line reads `... failed` with a non-zero failure count (`scripts/suite-run` does not exist yet, so every case that runs it fails).

- [ ] **Step 3: Write the implementation**

Create `plugins/dforge/scripts/suite-run` (mode 100644, like `scripts/task-brief`; callers run it through `bash`):

```bash
#!/usr/bin/env bash
# Run a test or validation command, record the run, and print a short digest,
# so a session reads a verdict instead of digging through the output. The
# record lets the session skip a rerun at a HEAD that already passed.
#
# One row per run goes to <state>/suites.tsv (<state> is `dforge-path state`):
#   <HEAD sha> <clean|dirty> <command> <exit> <log path> <epoch>
# separated by tabs; the output goes to <state>/suites/<epoch>-<pid>.log. Clean
# means `git status --porcelain --untracked-files=all` printed nothing before
# and after the run; ignored files, such as a local .env, are outside the
# guarantee. A pass is reused only from a row with the same HEAD, the same
# command and exit 0, clean when it ran and clean now. A dirty tree never
# reuses and never records a reusable row.
#
# Usage: suite-run [--timeout SECONDS] -- COMMAND [ARG ...]
# Output: "suite-run: running <m>m" every 300 seconds while the command runs
#         (SUITE_RUN_HEARTBEAT overrides the interval and SUITE_RUN_KILL_AFTER
#         the 10 seconds timeout waits after TERM, both for tests); then one of
#           suite: reused pass at <sha7> (<age>)
#           suite: pass (exit 0)
#           suite: FAIL (exit <code>)
#         and, when it read them, "counts: <pass> pass, <fail> fail"; on a
#         failure, up to 20 failing-test lines (TAP "not ok", Bun "(fail)",
#         lines starting FAIL) or, when none matched, "last 30 lines of <log>:"
#         and those lines; the last line is "log: <log path>".
# Default timeout 3600 seconds.
# Exit: the command's exit code; 0 on a reuse; 124 on timeout; 2 usage, or not
# in a git checkout, or no GNU timeout on PATH.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib/dforge-dir.sh"

die() { printf 'suite-run: %s\n' "$1" >&2; exit 2; }
usage() { die "usage: suite-run [--timeout SECONDS] -- COMMAND [ARG ...]"; }

secs=3600
while [ $# -gt 0 ]; do
  case $1 in
    --timeout)
      [ $# -ge 2 ] && [[ "$2" =~ ^[1-9][0-9]*$ ]] || usage
      secs=$2; shift 2 ;;
    --) shift; break ;;
    *) usage ;;
  esac
done
[ $# -ge 1 ] || usage
command -v timeout >/dev/null 2>&1 || die "GNU timeout is required but not on PATH"

root=$(git rev-parse --show-toplevel 2>/dev/null) || die "not in a git checkout"
head=$(git rev-parse HEAD 2>/dev/null | tr -d '\r') || head=""
[ -n "$head" ] || die "the checkout has no commit"
state=$(bash "$HERE/dforge-path" state | tr -d '\r') || die "no state directory"
mkdir -p "$state/suites" || die "cannot create $state/suites"
dforge_self_ignore "$state"

record="$state/suites.tsv"
command_text=$(printf '%s' "$*" | tr '\t\r\n' '   ')
short=${head:0:7}

is_clean() { [ -z "$(git status --porcelain --untracked-files=all 2>/dev/null | tr -d '\r')" ]; }

age() { # age SECONDS
  if [ "$1" -lt 60 ]; then printf '%ss' "$1"
  elif [ "$1" -lt 3600 ]; then printf '%sm' $(($1 / 60))
  elif [ "$1" -lt 86400 ]; then printf '%sh' $(($1 / 3600))
  else printf '%sd' $(($1 / 86400)); fi
}

clean_before=dirty
if is_clean; then clean_before=clean; fi

if [ "$clean_before" = clean ] && [ -f "$record" ]; then
  hit=$(tr -d '\r' < "$record" | H=$head C=$command_text awk -F'\t' '
    $1 == ENVIRON["H"] && $2 == "clean" && $3 == ENVIRON["C"] && $4 == "0" { row = $5 "\t" $6 }
    END { if (row != "") print row }')
  if [ -n "$hit" ]; then
    hit_log=${hit%%$'\t'*} hit_epoch=${hit##*$'\t'}
    now=$(date +%s)
    printf 'suite: reused pass at %s (%s)\n' "$short" "$(age $((now - hit_epoch)))"
    printf 'log: %s\n' "$hit_log"
    exit 0
  fi
fi

start=$(date +%s)
log="$state/suites/$start-$$.log"
beat=${SUITE_RUN_HEARTBEAT:-300}

timeout -k "${SUITE_RUN_KILL_AFTER:-10}" "$secs" "$@" > "$log" 2>&1 < /dev/null &
pid=$!
# The ticker wakes once a second so that nothing outlives the command by more
# than that: a single sleep of the whole interval would be left behind.
(
  next=$((start + beat))
  while kill -0 "$pid" 2>/dev/null; do
    sleep 1
    now=$(date +%s)
    if [ "$now" -ge "$next" ]; then
      printf 'suite-run: running %sm\n' $(((now - start) / 60))
      next=$((next + beat))
    fi
  done
) &
ticker=$!
trap 'kill -TERM "$pid" "$ticker" 2>/dev/null; exit 130' INT TERM
wait "$pid"
code=$?
trap - INT TERM
kill "$ticker" 2>/dev/null
wait "$ticker" 2>/dev/null
[ "$code" -ne 137 ] || code=124

recorded=$clean_before
if [ "$recorded" = clean ] && ! is_clean; then recorded=dirty; fi
printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$head" "$recorded" "$command_text" "$code" "$log" "$(date +%s)" >> "$record"

counts=$(tr -d '\r' < "$log" | awk '
  /^# pass [0-9][0-9]*[ \t]*$/ { tp = $3; tap = 1 }
  /^# fail [0-9][0-9]*[ \t]*$/ { tf = $3; tap = 1 }
  /^[ \t]*[0-9][0-9]* pass[ \t]*$/ { bp = $1; bun = 1 }
  /^[ \t]*[0-9][0-9]* fail[ \t]*$/ { bf = $1; bun = 1 }
  /[0-9][0-9]* passed, [0-9][0-9]* failed/ {
    match($0, /[0-9][0-9]* passed, [0-9][0-9]* failed/)
    split(substr($0, RSTART, RLENGTH), w, " ")
    sp += w[1]; sf += w[3]; sh = 1
  }
  /^ok / { okc++ }
  /^not ok / { nok++ }
  END {
    if (tap) print tp + 0, tf + 0
    else if (bun) print bp + 0, bf + 0
    else if (sh) print sp, sf
    else if (okc + nok > 0) print okc + 0, nok + 0
  }')

if [ "$code" -eq 0 ]; then
  printf 'suite: pass (exit 0)\n'
else
  printf 'suite: FAIL (exit %s)\n' "$code"
fi
if [ -n "$counts" ]; then
  set -- $counts
  printf 'counts: %s pass, %s fail\n' "$1" "$2"
fi
if [ "$code" -ne 0 ]; then
  fails=$(tr -d '\r' < "$log" | awk '
    /^[ \t]*(not ok|\(fail\)|FAIL)/ { n++; if (n <= 20) print substr($0, 1, 200) }')
  if [ -n "$fails" ]; then
    printf '%s\n' "$fails"
  else
    printf 'last 30 lines of %s:\n' "$log"
    tr -d '\r' < "$log" | tail -n 30
  fi
fi
printf 'log: %s\n' "$log"
exit "$code"
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID -u CLAUDE_CONFIG_DIR timeout 600 bash plugins/dforge/tests/suite-run.test.sh 2>&1 | tail -3`
Expected: the last line reads `72 passed, 0 failed` (about 25 seconds, most of it the timeout and heartbeat cases).

Run: `ls -l plugins/dforge/scripts/suite-run plugins/dforge/tests/suite-run.test.sh && pgrep -af 'suite-run|probe.sh' | grep -v pgrep`
Expected: both files `-rw-r--r--`, and no process listed.

Run: `timeout 300 node scripts/validate-repository.mjs`
Expected: `Repository catalogs, manifests, versions, bundled links and the settings schema are valid.`

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/scripts/suite-run plugins/dforge/tests/suite-run.test.sh
git -c user.name=Darkraise -c user.email=quangtc94@gmail.com commit -m "feat(suite-run): record and digest suite runs"
```

### Task 5: Add task-step start

**Files:**
- Create: `plugins/dforge/scripts/task-step`
- Test: `plugins/dforge/tests/task-step.test.sh`

**Acceptance:** A1, A3, A4

**Interfaces:**
- Consumes: the Contracts entry `scripts/task-step` (usage, state file, files, assigned line, digest lines, exit codes); `scripts/task-brief` (writes `<ws>/task-<N>-brief.md`, prints the budget line last); `scripts/sdd-workspace`; `scripts/lib/plan.sh` (`plan_task_text`, `plan_lines`, `plan_executors`, `plan_apply_amendments`, `plan_header`, `plan_tasks`); `skills/subagent-driven-development/references/implementer-prompt.md` (placeholders `[BRIEF_FILE]`, `[IMPLEMENTER]`, `[REPORT_FILE]`, and the `Task N: [task name]`, `Work from: [directory]` and scene-setting lines).
- Produces: `scripts/task-step start`, the state file `<ws>/task-<N>-step.json`, the assigned ledger line, and `<ws>/task-<N>-dispatch.md` (Contracts entries `scripts/task-step` and Assigned line). Task 6 extends the script's argument parser, `prompt_text`, `fill`, `state_line` and `budget_of`; Task 8's `rereview` is a separate function block that uses none of them. A repeated `start` keeps the state file it finds (and writes no second assigned line) unless `--reset` is given. A batch writes one assigned line per task, because the ledger grammar gives every task its own line (subagent-driven-development §The Ledger). An `**Executor:**` task and a task with no known `**Implementer:**` line get no assigned line, since the session writes theirs after the executor starts or after it scores the task.

**Items:** 2
**Implementer:** dforge:impl-sonnet-medium
**Evaluation:** files 1 - spec 0 - coupling 2 - risk 0 = 3

- [ ] **Step 1: Write the failing test**

Create `plugins/dforge/tests/task-step.test.sh`. It builds a throwaway repository and a fixture plan, runs `task-step start` against it, and checks the ledger, dispatch file, state file and digest. Its fixture lines carry a leading `|` so that this plan, which quotes the suite, still lints.

`````bash
#!/usr/bin/env bash
# task-step runs one phase of the delegated task loop in a single call. Each
# case runs against a throwaway repository and plan; no case starts Codex.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
P="$HERE/.."
STEP="$P/scripts/task-step"

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}

TMP=$(mktemp -d)
if command -v cygpath >/dev/null 2>&1; then TMP=$(cygpath -m "$TMP"); fi
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
mkdir -p "$HOME/.claude"
export MSYS_NO_PATHCONV=1 GIT_CONFIG_NOSYSTEM=1 DFORGE_NO_SETTINGS=1
unset DFORGE_BUDGET DR_SUPERPOWERS_BUDGET CLAUDE_CONFIG_DIR CODEX_HOME CLAUDE_CODE_SESSION_ID AR_SESSION CLAUDE_PROJECT_DIR

REPO="$TMP/repo"
git init -q "$REPO"
cd "$REPO" || exit 1
git config user.name Darkraise
git config user.email dark@example.invalid
mkdir docs

# Fixture lines carry a leading | so a plan that quotes this suite still lints.
sed 's/^|//' > docs/plan.md <<'PLAN'
|# Step Fixture Plan
|
|**Goal:** Fixture.
|
|**Execution:** subagent — `claude --model sonnet --effort high` — fixture
|
|## Global Constraints
|
|- Fixture constraint.
|
|## Contracts
|
|- Fixture contract.
|
|## Task index
|
|1. plain
|2. second
|3. executor
|4. unscored
|5. batch low
|6. batch high
|
|### Task 1: plain
|
|**Implementer:** dforge:impl-sonnet-low
|**Evaluation:** files 0 - spec 0 - coupling 1 - risk 0 = 1
|
|Body one.
|
|### Task 2: second
|
|**Implementer:** `dforge:impl-sonnet-high`
|**Evaluation:** files 1 - spec 0 - coupling 1 - risk 1 = 3
|
|### Task 3: executor
|
|**Implementer:** dforge:impl-sonnet-high
|**Executor:** codex gpt-6.1-sol / high
|**Evaluation:** files 1 - spec 0 - coupling 1 - risk 1 = 3
|
|### Task 4: unscored
|
|**Evaluation:** files 1 - spec 0 - coupling 1 - risk 1 = 3
|
|### Task 5: batch low
|
|**Implementer:** dforge:impl-sonnet-low
|**Evaluation:** files 0 - spec 0 - coupling 0 - risk 0 = 0
|
|### Task 6: batch high
|
|**Implementer:** dforge:impl-opus-medium
|**Evaluation:** files 0 - spec 0 - coupling 0 - risk 0 = 0
PLAN
sed 's/^|//' > docs/codex-plan.md <<'PLAN'
|# Codex Fixture
|
|**Host:** codex
|
|### Task 1: only
|
|**Evaluation:** files 0 - spec 0 - coupling 0 - risk 0 = 0
PLAN
git add -A && git commit -qm "docs: add fixture plans"
BASE=$(git rev-parse HEAD)

WS=$(bash "$P/scripts/sdd-workspace" docs/plan.md)
LEDGER="$WS/progress.md"
rm -f "$WS"/*
step() { out=$(bash "$STEP" "$@" 2>"$TMP/err"); rc=$?; }
count_lines() { printf '%s\n' "$1" | grep -c .; }

# start: the assigned line, the dispatch file, the state and the digest.
step start docs/plan.md 1
check "start: exit 0" "$rc" "0"
check "start: the assigned line" "$(tail -n 1 "$LEDGER")" "Task 1: implementer impl-sonnet-low (assigned; base ${BASE:0:7})"
check "start: the ledger names the plan" "$(head -n 1 "$LEDGER")" "# SDD ledger — plan: docs/plan.md"
check "start: the brief exists" "$([ -f "$WS/task-1-brief.md" ] && echo yes || echo no)" "yes"
check "start: the digest is at most 15 lines" "$([ "$(count_lines "$out")" -le 15 ] && echo yes || echo no)" "yes"
check "start: the seat line" "$(grep '^seat:' <<<"$out")" "seat: dforge:impl-sonnet-low prompt: $WS/task-1-dispatch.md"
check "start: the state line precedes the budget line" "$(tail -n 2 <<<"$out" | head -n 1)" \
  "state: base ${BASE:0:7} review-head - round 0 t0 -"
check "start: the last line is the budget line" "$(tail -n 1 <<<"$out" | cut -c1-6)" "budget"
D="$WS/task-1-dispatch.md"
check "start: the brief path is expanded" "$(grep -c "Read your task brief first: $WS/task-1-brief.md" "$D")" "1"
check "start: the report path is expanded" "$(grep -c "Write your full report to $WS/task-1-report.md:" "$D")" "1"
check "start: no placeholder is left" "$(grep -cE '\[(BRIEF_FILE|REPORT_FILE|PLUGIN_ROOT|IMPLEMENTER)\]' "$D")" "0"
check "start: the task name is filled" "$(grep -c 'You are implementing Task 1: plain' "$D")" "1"
check "start: the working directory is filled" "$(grep -c "^Work from: $(git rev-parse --show-toplevel)\$" "$D")" "1"
check "start: the dispatch file is a bare prompt" "$(grep -c '^Subagent (' "$D")" "0"
check "start: the state file" \
  "$(jq -c '[.tasks, .base == "'"$BASE"'", .head, .reviewHead, .round, .t0, .wave]' "$WS/task-1-step.json" | tr -d '\r')" '[[1],true,null,null,0,null,null]'

# start: a backticked Implementer, a wave, a prefix-free ledger name.
step start docs/plan.md 2 --wave 3
check "start: a wave ends the assigned line" "$(tail -n 1 "$LEDGER")" "Task 2: implementer impl-sonnet-high (assigned; base ${BASE:0:7}; wave 3)"
check "start: the wave is recorded" "$(jq -r .wave "$WS/task-2-step.json" | tr -d '\r')" "3"
check "start: a wave names its worktree" "$(grep -c '^Work from: your worktree' "$WS/task-2-dispatch.md")" "1"

# start: an executor task writes no dispatch file and no assigned line.
before=$(wc -l < "$LEDGER")
step start docs/plan.md 3
check "start: executor line" "$(grep '^executor' <<<"$out")" "executor codex: follow executor-lane.md §Dispatch"
check "start: no dispatch file for an executor task" "$([ -e "$WS/task-3-dispatch.md" ] && echo yes || echo no)" "no"
check "start: no assigned line for an executor task" "$(wc -l < "$LEDGER" | tr -d ' ')" "$(echo "$before" | tr -d ' ')"
check "start: an executor task still records its state" "$([ -f "$WS/task-3-step.json" ] && echo yes || echo no)" "yes"

# start: a task without an Implementer line is scored at dispatch.
before=$(wc -l < "$LEDGER")
step start docs/plan.md 4
check "start: unscored seat line" "$(grep -c '^seat: unscored (no known \*\*Implementer:\*\* line' <<<"$out")" "1"
check "start: no assigned line when unscored" "$(wc -l < "$LEDGER" | tr -d ' ')" "$(echo "$before" | tr -d ' ')"
check "start: the dispatch file is still written" "$([ -f "$WS/task-4-dispatch.md" ] && echo yes || echo no)" "yes"

# start: a batch takes the highest tier, one assigned line per task and one brief.
step start docs/plan.md 5 6
check "start: batch seat" "$(grep '^seat:' <<<"$out")" "seat: dforge:impl-opus-medium prompt: $WS/task-5-dispatch.md"
check "start: batch assigned lines" "$(tail -n 2 "$LEDGER" | sed 's/base [0-9a-f]*/base B/' | tr '\n' ';')" \
  "Task 5: implementer impl-opus-medium (assigned; base B);Task 6: implementer impl-opus-medium (assigned; base B);"
check "start: the digest names the batch" "$(head -n 1 <<<"$out" | cut -c1-12)" "task 5,6: br"
check "start: the batch brief holds both tasks" \
  "$(grep -cE '^### Task (5: batch low|6: batch high)$' "$WS/task-5-brief.md")" "2"
check "start: the batch brief carries the header excerpt once" "$(grep -c '^## Plan header excerpt$' "$WS/task-5-brief.md")" "1"
check "start: the batch brief ends with the header excerpt" "$(grep -v '^$' "$WS/task-5-brief.md" | tail -n 1)" "- Fixture contract."
check "start: the batch state names both tasks" "$(jq -c .tasks "$WS/task-5-step.json" | tr -d '\r')" "[5,6]"

# start: a second call keeps the recorded state and writes no second assigned
# line; --reset discards the state and starts over.
echo moved > moved.txt && git add moved.txt && git commit -qm "chore: move head"
MOVED=$(git rev-parse HEAD)
before=$(wc -l < "$LEDGER")
step start docs/plan.md 1
check "start again: exit 0" "$rc" "0"
check "start again: no second assigned line" "$(wc -l < "$LEDGER" | tr -d ' ')" "$(echo "$before" | tr -d ' ')"
check "start again: the recorded base is kept" "$(jq -r .base "$WS/task-1-step.json" | tr -d '\r')" "$BASE"
check "start again: the digest says the state is kept" "$(head -n 1 <<<"$out" | grep -c 'state kept')" "1"
check "start again: the state line shows the kept base" "$(tail -n 2 <<<"$out" | head -n 1)" \
  "state: base ${BASE:0:7} review-head - round 0 t0 -"
step start docs/plan.md 1 --reset
check "start --reset: the base is HEAD again" "$(jq -r .base "$WS/task-1-step.json" | tr -d '\r')" "$MOVED"
check "start --reset: a new assigned line" "$(tail -n 1 "$LEDGER")" "Task 1: implementer impl-sonnet-low (assigned; base ${MOVED:0:7})"
check "start --reset: the digest does not say kept" "$(head -n 1 <<<"$out" | grep -c 'state kept')" "0"

# Negative: usage, a missing task, a Codex host, an amendment that does not apply.
step start docs/plan.md 9
check "start: no such task exits 3" "$rc" "3"
step start docs/plan.md
check "start: no task number exits 2" "$rc" "2"
step start docs/plan.md x
check "start: a non-numeric task exits 2" "$rc" "2"
step start docs/plan.md 1 --nope
check "start: an unknown flag exits 2" "$rc" "2"
step start docs/plan.md 1 --wave
check "start: --wave without a value exits 2" "$rc" "2"
step bogus docs/plan.md 1
check "an unknown subcommand exits 2" "$rc" "2"
step start docs/missing.md 1
check "start: a missing plan exits 2" "$rc" "2"
CWS=$(bash "$P/scripts/sdd-workspace" docs/codex-plan.md)
rm -rf "$CWS"
step start docs/codex-plan.md 1
check "start: a Host: codex plan exits 2" "$rc" "2"
check "start: a Host: codex plan writes nothing" "$([ -e "$CWS" ] && ls -A "$CWS" | grep -c . || echo 0)" "0"
mkdir -p "$WS"
sed 's/^|//' > "$WS/amendments.md" <<'AMEND'
|## A1 — Task 1
|
|### Old
|````
|a line the task does not hold
|````
|
|### New
|````
|replacement
|````
AMEND
step start docs/plan.md 1
check "start: an amendment that does not apply exits 4" "$rc" "4"
rm -f "$WS/amendments.md"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
`````

- [ ] **Step 2: Run the test to verify it fails**

Run: `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID -u CLAUDE_CONFIG_DIR timeout 600 bash plugins/dforge/tests/task-step.test.sh`
Expected: FAIL lines for every `start:` case (`plugins/dforge/scripts/task-step` does not exist yet) and exit status 1.

- [ ] **Step 3: Write the script**

Create `plugins/dforge/scripts/task-step`. Do not make it executable: scripts in this repository are committed at mode 100644 and run through `bash`.

`````bash
#!/usr/bin/env bash
# One command per mechanical phase of the delegated task loop
# (reference/delegated-task.md): each wraps today's scripts, writes the filled
# prompt to a file in the plan workspace and prints a digest of at most 15
# lines. State for a task, or a batch named after its first task, lives in
# <workspace>/task-<N>-step.json.
#
# Usage: task-step start PLAN_FILE N [M ...] [--wave K] [--reset]
# A start that finds the task's state file keeps it (and writes no second
# assigned line) unless --reset is given.
# Exit: 0 ok; 2 usage, or any subcommand on a Host: codex plan; 3 no such task;
# 4 an amendment does not apply; 6 a required earlier step has not run.
# 5 is context-size's handoff code and is never used here.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib/plan.sh"

die() { printf 'task-step: %s\n' "$1" >&2; exit "${2:-2}"; }
usage() { die "usage: task-step start PLAN_FILE N [M ...] [--wave K] [--reset]"; }

[ $# -ge 3 ] || usage
sub=$1; plan_arg=$2; shift 2
case $sub in start) ;; *) usage ;; esac

ids=() wave="" reset=0
while [ $# -gt 0 ]; do
  case $1 in
    --wave) [ "$sub" = start ] && [ $# -ge 2 ] && [[ $2 =~ ^[1-9][0-9]*$ ]] || usage; wave=$2; shift 2 ;;
    --reset) [ "$sub" = start ] || usage; reset=1; shift ;;
    -*) usage ;;
    *) [[ $1 =~ ^[0-9]+$ ]] || usage; ids+=("$((10#$1))"); shift ;;
  esac
done
[ ${#ids[@]} -ge 1 ] || usage
first=${ids[0]}
idlist=$(IFS=,; echo "${ids[*]}")

plan=$(plan_locate "$plan_arg")
[ -f "$plan" ] || die "no such plan file: $plan"
plan_require_same_project "$plan"
ctx=$(_plan_ctx "$plan")
dforge_stores_init "$ctx"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
src="$TMP/plan.md"
plan_apply_amendments "$plan" "$(plan_amendments_file "$plan")" > "$src" 2>/dev/null \
  || die "an amendment does not apply; run plan-lint" 4
if grep -qE '^(\*\*)?Host:(\*\*)?[ \t]+codex[ \t]*$' <<<"$(plan_header "$src")"; then
  die "a Host: codex plan runs the Codex loop (reference/native-codex.md); task-step is for Claude Code"
fi
for n in "${ids[@]}"; do
  plan_task_text "$src" "$n" >/dev/null || die "no Task $n in $plan" 3
done

slug=$(basename "$plan" .md)
ws=$(dforge_workspace "$slug" "$ctx")
ledger="$(dforge_ledger_dir "$slug" "$ctx")/progress.md"
state="$ws/task-$first-step.json"
plugin_root=$(cd "$HERE/.." && pwd)
brief="$ws/task-$first-brief.md"
report="$ws/task-$first-report.md"

budget_of() { grep -E '^budget' | tail -n 1; }

# The fenced `prompt: |` body of a template, de-indented, without the
# "[Include this section only ...]" instruction lines.
prompt_text() {
  tr -d '\r' < "$1" | awk '
    /^  prompt: \|[ \t]*$/ && !done { on = 1; next }
    on && /^```/ { on = 0; done = 1; next }
    on { sub(/^    /, "") }
    on && !/^\[Include this section only/ { print }'
}

# fill TOKEN VALUE [TOKEN VALUE ...]: stdin to stdout, each literal TOKEN
# replaced by its VALUE. The pairs travel in the environment so that a path
# with a backslash or an ampersand is never read as an escape.
fill() {
  local i=0
  while [ $# -ge 2 ]; do export "TS_T$i=$1" "TS_V$i=$2"; i=$((i + 1)); shift 2; done
  TS_N=$i awk '
    BEGIN { n = ENVIRON["TS_N"] + 0 }
    {
      line = $0
      for (k = 0; k < n; k++) {
        t = ENVIRON["TS_T" k]; v = ENVIRON["TS_V" k]; out = ""
        while ((p = index(line, t)) > 0) { out = out substr(line, 1, p - 1) v; line = substr(line, p + length(t)) }
        line = out line
      }
      print line
    }'
}

title_of() { plan_tasks "$src" | awk -F'\t' -v n="$1" '$1 == n && !d { print $2; d = 1 }' | tr -d '\r'; }

agent_rank() {
  local m e
  if [ "$1" = impl-haiku ]; then echo 0; return; fi
  [[ "$1" =~ ^impl-(sonnet|opus|fable)-(low|medium|high|xhigh|max)$ ]] || return 0
  case ${BASH_REMATCH[1]} in sonnet) m=1 ;; opus) m=2 ;; *) m=3 ;; esac
  case ${BASH_REMATCH[2]} in low) e=0 ;; medium) e=1 ;; high) e=2 ;; xhigh) e=3 ;; *) e=4 ;; esac
  echo $((m * 10 + e))
}

implementer_of() {
  plan_task_text "$src" "$1" | plan_lines Implementer | head -n 1 \
    | sed -nE 's/^\*\*Implementer:\*\*[ \t]*`?([^` \t]+)`?.*/\1/p' | sed 's/^.*://' | tr -d '\r'
}

strip_excerpt() { awk '/^## Plan header excerpt$/ { skip = 1 } /^## UI\/UX contract items$/ { skip = 0 } !skip { print }' "$1"; }
only_excerpt() { awk '/^## Plan header excerpt$/ { on = 1 } /^## UI\/UX contract items$/ { on = 0 } on { print }' "$1"; }

state_line() {
  jq -r '"state: base \(.base[0:7]) review-head \(if .reviewHead then .reviewHead[0:7] else "-" end) round \(.round) t0 \(.t0 // "-")"' "$state" | tr -d '\r'
}

do_start() {
  local base base7 out rc n a agent="" best=-1 rank unknown=0 exec_id="" suffix=")" label titles kept=0
  local template="$plugin_root/skills/subagent-driven-development/references/implementer-prompt.md"
  local dispatch="$ws/task-$first-dispatch.md" budget="" workfrom scene

  if [ -f "$state" ] && [ "$reset" -eq 0 ]; then
    kept=1
    base=$(jq -r '.base' "$state" | tr -d '\r')
  else
    base=$(git rev-parse HEAD) || die "not inside a git checkout"
  fi
  base7=${base:0:7}
  bash "$HERE/sdd-workspace" "$plan" >/dev/null || exit 2

  for n in "${ids[@]}"; do
    out=$(bash "$HERE/task-brief" "$plan" "$n"); rc=$?
    [ "$rc" -eq 0 ] || { printf '%s\n' "$out" >&2; exit "$rc"; }
    if [ "$n" = "$first" ]; then budget=$(budget_of <<<"$out"); fi
  done
  if [ ${#ids[@]} -gt 1 ]; then
    {
      strip_excerpt "$brief"
      for n in "${ids[@]}"; do
        [ "$n" = "$first" ] && continue
        printf '\n---\n\n'
        strip_excerpt "$ws/task-$n-brief.md"
      done
      only_excerpt "$brief"
    } > "$brief.tmp" && mv "$brief.tmp" "$brief"
  fi

  for n in "${ids[@]}"; do
    a=$(implementer_of "$n")
    if [[ "$a" == impl-* ]] && [ -f "$plugin_root/agents/$a.md" ]; then
      rank=$(agent_rank "$a")
      if [ "${rank:--1}" -gt "$best" ]; then best=$rank agent=$a; fi
    else
      unknown=1
    fi
  done
  [ "$unknown" -eq 0 ] || agent=""
  if [ ${#ids[@]} -eq 1 ]; then
    exec_id=$(plan_executors "$src" | awk -F'\t' -v n="$first" '$1 == n { print $2 }' | tr -d '\r')
  fi

  [ -z "$wave" ] || suffix="; wave $wave)"
  if [ -n "$agent" ] && [ -z "$exec_id" ] && [ "$kept" -eq 0 ]; then
    if [ ! -f "$ledger" ]; then
      mkdir -p "$(dirname "$ledger")"
      printf '# SDD ledger — plan: %s\n' "$(dforge_name "$plan" "$ctx")" > "$ledger"
    fi
    for n in "${ids[@]}"; do
      printf 'Task %s: implementer %s (assigned; base %s%s\n' "$n" "$agent" "$base7" "$suffix" >> "$ledger"
    done
  fi

  if [ "$kept" -eq 0 ]; then
    jq -n --argjson tasks "$(printf '%s\n' "${ids[@]}" | jq -sc .)" --arg base "$base" --argjson wave "${wave:-null}" \
      '{tasks: $tasks, base: $base, head: null, reviewHead: null, round: 0, t0: null, wave: $wave}' > "$state.tmp" \
      && mv "$state.tmp" "$state"
  fi

  if [ -z "$exec_id" ]; then
    if [ ${#ids[@]} -eq 1 ]; then
      label="Task $first: $(title_of "$first")"
    else
      titles=$(for n in "${ids[@]}"; do title_of "$n"; done | awk 'NR > 1 { printf "; " } { printf "%s", $0 } END { print "" }')
      label="Tasks $(IFS=,; echo "${ids[*]}" | sed 's/,/, /g'): $titles"
    fi
    workfrom="Work from: $(git rev-parse --show-toplevel)"
    [ -z "$wave" ] || workfrom="Work from: your worktree (see the Parallel workspace section)"
    scene="The message that sent you to this file says where the task fits, and carries the interfaces from earlier tasks and the verdicts that bear on it."
    prompt_text "$template" | fill \
      '[BRIEF_FILE]' "$brief" '[REPORT_FILE]' "$report" '[PLUGIN_ROOT]' "$plugin_root" \
      '[IMPLEMENTER]' "${agent:-the scored implementer}" 'Task N: [task name]' "$label" \
      'Work from: [directory]' "$workfrom" \
      '[Scene-setting: where this fits, dependencies, architectural context]' "$scene" > "$dispatch"
  fi

  printf 'task %s: briefed %s, base %s' "$idlist" "$brief" "$base7"
  if [ "$kept" -eq 1 ]; then printf '; state kept, no assigned line written (--reset discards the state)\n'
  elif [ -n "$exec_id" ]; then printf '; executor task, no dispatch file written\n'
  elif [ -n "$agent" ]; then printf '; assigned %s\n' "$agent"
  else printf '; no assigned line written\n'; fi
  if [ -n "$exec_id" ]; then
    printf 'executor %s: follow executor-lane.md §Dispatch\n' "$exec_id"
  elif [ -n "$agent" ]; then
    printf 'seat: dforge:%s prompt: %s\n' "$agent" "$dispatch"
  else
    printf 'seat: unscored (no known **Implementer:** line; score it per ladder.md, dispatch that agent, end its assigned line with "; scored at dispatch") prompt: %s\n' "$dispatch"
  fi
  state_line
  printf '%s\n' "${budget:-budget: unknown}"
}

case $sub in
  start) do_start ;;
esac
`````

- [ ] **Step 4: Run the test to verify it passes**

Run: `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID -u CLAUDE_CONFIG_DIR timeout 600 bash plugins/dforge/tests/task-step.test.sh`
Expected: `50 passed, 0 failed`.

Run: `timeout 300 node scripts/validate-repository.mjs`
Expected: `Repository catalogs, manifests, versions, bundled links and the settings schema are valid.`

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/scripts/task-step plugins/dforge/tests/task-step.test.sh
git ls-files -s plugins/dforge/scripts/task-step plugins/dforge/tests/task-step.test.sh
git -c user.name=Darkraise -c user.email=quangtc94@gmail.com commit -m "feat(dforge): add task-step start"
```

`git ls-files -s` must show mode `100644` for both files.

### Task 6: Add task-step review and its checks

**Files:**
- Modify: `plugins/dforge/scripts/task-step`
- Test: `plugins/dforge/tests/task-step.test.sh`

**Acceptance:** A2, A3, A4, A8

**Interfaces:**
- Consumes: Task 5's `scripts/task-step` (argument parser, `prompt_text`, `fill`, `state_line`, `budget_of`, the state file); the Contracts entry `scripts/task-step` (the `review` usage, `--base`/`--head`/`--cwd`, prompt files, digest and seat lines, exit 6); `scripts/review-package` (prints `wrote <path>: <n> commit(s), <bytes> bytes`, then the budget line); `scripts/codex-gate`; `scripts/review-route --task`; `scripts/lens-route --task` (prints `lens <id> criteria=<path>`); `scripts/lib/plan.sh` `ladder_block` (the `codex-judge` rows give the Codex timeouts); `skills/subagent-driven-development/references/task-reviewer-prompt.md` (placeholders `[BASE_SHA] [BRIEF_FILE] [CODEX_REVIEW_FILE] [DIFF_FILE] [HEAD_SHA] [JUDGE] [LENS_FILES] [PLUGIN_ROOT] [REPORT_FILE]`); `criteria/task-review.md`.
- Produces: `scripts/task-step review PLAN_FILE N [M ...] [--base SHA] [--head REF] [--cwd DIR]`, which updates `reviewHead`, `t0`, with `--base` `base` and with `--head` `head` in the state file, and writes `<ws>/task-<N>-review-prompt.md` and, for a Codex seat, `<ws>/task-<N>-review-codex-prompt.md`; the functions `drop_sections`, `check_identity` and `check_attribution` (Task 8's `rereview` uses none of them); and the environment variable `TASK_STEP_CODEX_GATE`, read only by the test suite to replace `scripts/codex-gate` with a stub, so that no test can reach a real Codex.

**Items:** 2, 4
**Implementer:** dforge:impl-sonnet-medium
**Evaluation:** files 1 - spec 0 - coupling 2 - risk 1 = 4

The Codex prompt is built as `reference/executor-lane.md` §Codex task review seats describes: the judge template's body without the Second Pass section, the Lens Criteria section and the Output Format section, the criteria file inlined, and a closing Output section asking for the JSON object that `criteria/codex-review-schema.json` defines. The timeouts are `(bound + 120) * 1000` from the `codex-judge` block of `reference/ladder.md`: the last row for `--tier light` (2520000) and the first for `--tier heavy` (5520000). The runner command's `--cwd` is the session's top level unless `review` is given `--cwd DIR` (a wave passes the task's worktree). The attribution check matches a `Co-Authored-By:` or `Claude-Session:` trailer, or a line that begins `Generated with` after any leading symbols, and not those words inside a sentence.

- [ ] **Step 1: Extend the test**

Apply these edits to `plugins/dforge/tests/task-step.test.sh`, in order. Each "Replace" text occurs exactly once at that point. The first edit stubs the Codex gate and the session file `review-route` reads; the next three add review fixtures (a lens on Task 1, and the risk-3 Task 7 and the unparseable Task 8); the last adds the review cases above the summary line.

Replace in `plugins/dforge/tests/task-step.test.sh`:

`````bash
unset DFORGE_BUDGET DR_SUPERPOWERS_BUDGET CLAUDE_CONFIG_DIR CODEX_HOME CLAUDE_CODE_SESSION_ID AR_SESSION CLAUDE_PROJECT_DIR
`````

with:

`````bash
unset DFORGE_BUDGET DR_SUPERPOWERS_BUDGET CLAUDE_CONFIG_DIR CODEX_HOME CLAUDE_CODE_SESSION_ID AR_SESSION CLAUDE_PROJECT_DIR

# review-route reads this session's gate file; the gate itself is a stub, so no
# case can reach a real Codex.
export DR_CODEX_SESSION_DIR="$TMP/sessions" CLAUDE_CODE_SESSION_ID=task-step-test
printf '%s\n' '#!/usr/bin/env bash' 'echo "codex-gate usable=true reason= review=true lane=false resets_at=- source=cache"' > "$TMP/gate-stub"
export TASK_STEP_CODEX_GATE="$TMP/gate-stub"
review_surface() { # review_surface <true|false|absent>
  rm -rf "$DR_CODEX_SESSION_DIR"
  [ "$1" != absent ] || return 0
  mkdir -p "$DR_CODEX_SESSION_DIR"
  printf '{"session_id":"task-step-test","usable":true,"review":%s,"lane":false}\n' "$1" > "$DR_CODEX_SESSION_DIR/task-step-test.json"
}
`````

Replace in `plugins/dforge/tests/task-step.test.sh`:

`````bash
|5. batch low
|6. batch high
|
`````

with:

`````bash
|5. batch low
|6. batch high
|7. risky
|8. unparseable
|
`````

Replace in `plugins/dforge/tests/task-step.test.sh`:

`````bash
|**Evaluation:** files 0 - spec 0 - coupling 1 - risk 0 = 1
|
|Body one.
`````

with:

`````bash
|**Evaluation:** files 0 - spec 0 - coupling 1 - risk 0 = 1
|**Lenses:** lang-bash
|
|Body one.
`````

Replace in `plugins/dforge/tests/task-step.test.sh`:

`````bash
|**Implementer:** dforge:impl-opus-medium
|**Evaluation:** files 0 - spec 0 - coupling 0 - risk 0 = 0
PLAN
`````

with:

`````bash
|**Implementer:** dforge:impl-opus-medium
|**Evaluation:** files 0 - spec 0 - coupling 0 - risk 0 = 0
|
|### Task 7: risky
|
|**Implementer:** dforge:impl-opus-high
|**Evaluation:** files 1 - spec 1 - coupling 1 - risk 3 = 6
|
|### Task 8: unparseable
|
|**Implementer:** dforge:impl-sonnet-low
|**Evaluation:** one plus one
PLAN
`````

Replace in `plugins/dforge/tests/task-step.test.sh`:

`````bash
printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
`````

with:

`````bash
# review: the preconditions.
PR=$(cd "$P" && pwd)
TOP=$(git rev-parse --show-toplevel)
short() { git rev-parse --short "$1"; }
placeholders() { grep -cE '\[[A-Z][A-Z_]*\]' "$1"; }
ws_count() { ls -A "$WS" | wc -l | tr -d ' '; }
state_of() { jq -r "$2" "$WS/task-$1-step.json" | tr -d '\r'; }
before=$(ws_count)
step review docs/plan.md 7
check "review: before start exits 6" "$rc" "6"
check "review: before start writes nothing" "$(ws_count)" "$before"
step review docs/codex-plan.md 1
check "review: a Host: codex plan exits 2" "$rc" "2"
check "review: a Host: codex plan writes nothing" "$([ -e "$CWS" ] && echo yes || echo no)" "no"
step review docs/plan.md 99
check "review: no such task exits 3" "$rc" "3"
step review docs/plan.md 1 --base
check "review: --base without a value exits 2" "$rc" "2"
step start docs/plan.md 1 --head HEAD
check "start: --head is a review flag only" "$rc" "2"
step start docs/plan.md 1 --cwd "$TMP"
check "start: --cwd is a review flag only" "$rc" "2"
step review docs/plan.md 1 --reset
check "review: --reset is a start flag only" "$rc" "2"
step review docs/plan.md 1 --cwd
check "review: --cwd without a value exits 2" "$rc" "2"
step start docs/plan.md 1 --reset
BASE1=$(git rev-parse HEAD)

# review: a judge seat below risk 3, Codex off for the session.
echo a > a.txt && git add a.txt && git commit -qm "feat: add a"
C1=$(git rev-parse HEAD)
review_surface absent
step review docs/plan.md 1
JP="$WS/task-1-review-prompt.md"
check "review: exit 0" "$rc" "0"
check "review: the digest is at most 15 lines" "$([ "$(count_lines "$out")" -le 15 ] && echo yes || echo no)" "yes"
check "review: the judge seat" "$(grep '^seat:' <<<"$out")" "seat: dforge:judge-sonnet-high prompt: $JP"
check "review: codex off shows the gate line" "$(grep -c '^gate: codex-gate usable=true' <<<"$out")" "1"
check "review: no runner lines for a judge seat" "$(grep -cE '^(codex|timeout):' <<<"$out")" "0"
check "review: no Codex prompt for a judge seat" "$([ -e "$WS/task-1-review-codex-prompt.md" ] && echo yes || echo no)" "no"
check "review: the judge prompt has no unexpanded placeholder" "$(placeholders "$JP")" "0"
check "review: base, head and diff file" "$(grep -E '^\*\*(Base|Head|Diff file):\*\*' "$JP" | tr '\n' ' ' | sed 's/ $//')" \
  "**Base:** $BASE1 **Head:** $C1 **Diff file:** $WS/review-$(short "$BASE1")..$(short "$C1").diff"
check "review: the diff file exists" "$([ -f "$WS/review-$(short "$BASE1")..$(short "$C1").diff" ] && echo yes || echo no)" "yes"
check "review: brief and report paths" "$(grep -cE "^(Read the task brief: $WS/task-1-brief.md|Read the implementer's report: $WS/task-1-report.md)\$" "$JP")" "2"
check "review: the criteria path is expanded" "$(grep -c "Read the criteria file at $PR/criteria/task-review.md and score" "$JP")" "1"
check "review: the lens path is named" "$(grep -c "^Read each lens file in $PR/criteria/lenses/lang-bash.md\. Lens criteria" "$JP")" "1"
check "review: no Second Pass section below risk 3" "$(grep -c 'Second Pass' "$JP")" "0"
check "review: identity check" "$(grep '^check identity' <<<"$out")" "check identity: clean"
check "review: attribution check" "$(grep '^check attribution' <<<"$out")" "check attribution: clean"
check "review: the state records the review head" "$(state_of 1 .reviewHead)" "$C1"
check "review: the state records t0" "$(state_of 1 '.t0 | type')" "number"
check "review: the state keeps the round" "$(state_of 1 .round)" "0"
check "review: the state line precedes the budget line" "$(tail -n 2 <<<"$out" | head -n 1)" \
  "state: base $(short "$BASE1") review-head $(short "$C1") round 0 t0 $(state_of 1 .t0)"
check "review: the last line is the budget line" "$(tail -n 1 <<<"$out" | cut -c1-6)" "budget"

step review docs/plan.md 2
check "review: a task with no lens drops the section" "$(grep -c 'Lens Criteria' "$WS/task-2-review-prompt.md")" "0"
check "review: and leaves no placeholder" "$(placeholders "$WS/task-2-review-prompt.md")" "0"

# review: a light Codex seat, with the judge prompt beside it as the fallback.
review_surface true
step review docs/plan.md 1
CP="$WS/task-1-review-codex-prompt.md"
check "review: the light seat" "$(grep '^seat:' <<<"$out")" "seat: codex:light prompt: $CP fallback: dforge:judge-sonnet-high prompt: $JP"
check "review: the runner command" "$(grep '^codex:' <<<"$out")" \
  "codex: bash \"$PR/scripts/run-codex-review.sh\" --kind task --tier light --cwd \"$TOP\" --out \"$WS/task-1-review-codex.json\" --prompt \"$CP\""
check "review: the light timeout" "$(grep '^timeout:' <<<"$out")" "timeout: 2520000"
check "review: no gate line while the surface is open" "$(grep -c '^gate:' <<<"$out")" "0"
check "review: the judge prompt is still written, with its lens" "$(grep -c 'Lens Criteria' "$JP")" "1"
check "review: the Codex prompt has no unexpanded placeholder" "$(placeholders "$CP")" "0"
check "review: the Codex prompt asks for one JSON object" "$(grep -c 'one JSON object' "$CP")" "1"
check "review: the Codex prompt carries the criteria" "$(grep -c '^#### Spec Compliance {#spec}$' "$CP")" "1"
check "review: the Codex prompt drops the markdown report" "$(grep -cE 'Verification Scores|Output Format|Lens Criteria|Second Pass' "$CP")" "0"
check "review: the Codex prompt names the diff file" "$(grep -c "^\*\*Diff file:\*\* $WS/review-" "$CP")" "1"
mkdir -p "$TMP/wt"
step review docs/plan.md 1 --cwd "$TMP/wt"
check "review: --cwd names the runner's working directory" "$(grep -c -- "--kind task --tier light --cwd \"$TMP/wt\" --out" <<<"$out")" "1"
step review docs/plan.md 1 --cwd "$TMP/no-such-dir"
check "review: a missing --cwd directory exits 2" "$rc" "2"

# review: a heavy Codex seat on risk 3, then the judge with the Second Pass section.
step start docs/plan.md 7
echo b > b.txt && git add b.txt && git commit -qm "feat: add b"
C2=$(git rev-parse HEAD)
step review docs/plan.md 7
JP7="$WS/task-7-review-prompt.md"
check "review: the heavy seat" "$(grep '^seat:' <<<"$out")" \
  "seat: codex:heavy+judge-opus prompt: $WS/task-7-review-codex-prompt.md then: dforge:judge-opus prompt: $JP7"
check "review: the heavy timeout" "$(grep '^timeout:' <<<"$out")" "timeout: 5520000"
check "review: the runner command names the tier" "$(grep -c -- '--kind task --tier heavy --cwd' <<<"$out")" "1"
check "review: the judge prompt carries the Second Pass section" "$(grep -c '^## Second Pass: The Codex Review$' "$JP7")" "1"
check "review: the Second Pass names the Codex output file" "$(grep -c "^review of the same diff: $WS/task-7-review-codex.json\$" "$JP7")" "1"
check "review: the Codex prompt leaves the Second Pass out" "$(grep -c 'Second Pass' "$WS/task-7-review-codex-prompt.md")" "0"
check "review: the risk-3 judge prompt has no placeholder" "$(placeholders "$JP7")" "0"
review_surface false
step review docs/plan.md 7
check "review: risk 3 with Codex off is a judge-opus seat" "$(grep '^seat:' <<<"$out")" "seat: dforge:judge-opus prompt: $JP7"
check "review: and carries no Second Pass section" "$(grep -c 'Second Pass' "$JP7")" "0"
review_surface absent

# review: --head and --base.
git branch taskref "$C1"
step review docs/plan.md 1 --head taskref
check "review: --head records the ref" "$(state_of 1 .head)" "taskref"
check "review: --head records the ref's commit" "$(state_of 1 .reviewHead)" "$C1"
check "review: --head packages base..REF" "$(grep -c "^\*\*Head:\*\* $C1\$" "$JP")" "1"
step review docs/plan.md 1
check "review: a later review reuses the recorded ref" "$(state_of 1 .reviewHead)" "$C1"
step review docs/plan.md 2 --base "$C1"
DIFF2="$WS/review-$(short "$C1")..$(short "$C2").diff"
check "review: --base starts the package at SHA" "$(grep -c "^\*\*Diff file:\*\* $DIFF2\$" "$WS/task-2-review-prompt.md")" "1"
check "review: --base leaves the earlier commit out" "$(grep -c 'add a' "$DIFF2")" "0"
check "review: --base is recorded" "$(state_of 2 .base)" "$C1"
step review docs/plan.md 1 --head nope
check "review: a bad ref exits 2" "$rc" "2"
check "review: a bad ref leaves the state alone" "$(state_of 1 .head)" "taskref"
step review docs/plan.md 1 --base nope
check "review: a bad base exits 2" "$rc" "2"

# review: the mechanical checks.
CO="Co-Authored""-By"
CS="Claude""-Session"
PREV=$(git rev-parse HEAD)
git commit -q --allow-empty --author="Other <other@example.invalid>" -m "feat: written by another author"
step review docs/plan.md 2 --base "$PREV"
check "check identity: a different author" "$(grep '^check identity' <<<"$out")" \
  "check identity: $(short HEAD) author Other <other@example.invalid> (expected Darkraise <dark@example.invalid>)"
check "check attribution: clean beside a bad identity" "$(grep '^check attribution' <<<"$out")" "check attribution: clean"
PREV=$(git rev-parse HEAD)
GIT_COMMITTER_NAME=Other GIT_COMMITTER_EMAIL=other@example.invalid git commit -q --allow-empty -m "feat: committed by another"
step review docs/plan.md 2 --base "$PREV"
check "check identity: a different committer" "$(grep '^check identity' <<<"$out")" \
  "check identity: $(short HEAD) committer Other <other@example.invalid> (expected Darkraise <dark@example.invalid>)"
PREV=$(git rev-parse HEAD)
git -c user.name=Other -c user.email=other@example.invalid commit -q --allow-empty -m "feat: both differ"
step review docs/plan.md 2 --base "$PREV"
check "check identity: author and committer" "$(grep '^check identity' <<<"$out")" \
  "check identity: $(short HEAD) author Other <other@example.invalid>, committer Other <other@example.invalid> (expected Darkraise <dark@example.invalid>)"
PREV=$(git rev-parse HEAD)
git commit -q --allow-empty -m "feat: with a co-author" -m "$CO: X <x@example.invalid>"
step review docs/plan.md 2 --base "$PREV"
check "check attribution: a co-author trailer" "$(grep '^check attribution' <<<"$out")" \
  "check attribution: $(short HEAD) $CO: X <x@example.invalid>"
check "check identity: clean beside a bad attribution" "$(grep '^check identity' <<<"$out")" "check identity: clean"
PREV=$(git rev-parse HEAD)
git commit -q --allow-empty -m "feat: with a session" -m "$CS: abc123"
step review docs/plan.md 2 --base "$PREV"
check "check attribution: a session trailer" "$(grep '^check attribution' <<<"$out")" "check attribution: $(short HEAD) $CS: abc123"
PREV=$(git rev-parse HEAD)
git commit -q --allow-empty -m "feat: tool line" -m "Generated with a tool"
step review docs/plan.md 2 --base "$PREV"
check "check attribution: a generated-with line" "$(grep '^check attribution' <<<"$out")" "check attribution: $(short HEAD) Generated with a tool"
PREV=$(git rev-parse HEAD)
git commit -q --allow-empty -m "feat: mentions the words" -m "The table is generated with a script, and a co-authored-by: note is prose here."
step review docs/plan.md 2 --base "$PREV"
check "check attribution: the words inside a sentence are not a trailer" "$(grep '^check attribution' <<<"$out")" "check attribution: clean"
PREV=$(git rev-parse HEAD)
git commit -q --allow-empty -m "feat: clean one"
step review docs/plan.md 2 --base "$PREV"
check "checks: a clean commit passes both" "$(grep '^check' <<<"$out" | tr '\n' ';')" "check identity: clean;check attribution: clean;"
step review docs/plan.md 2 --base "$(git rev-parse HEAD~7)"
check "checks: several offenders name the first and count the rest" "$(grep '^check attribution' <<<"$out" | grep -c '; 2 more commit(s)$')" "1"

# review: a batch, and a route that fails.
step review docs/plan.md 5 6
check "review: a batch names its tasks" "$(head -n 1 <<<"$out" | cut -c1-19)" "task 5,6: reviewed "
check "review: a batch state is named after its first task" "$(state_of 5 .reviewHead)" "$(git rev-parse HEAD)"
check "review: a batch prompt names the batch brief" "$(grep -c "^Read the task brief: $WS/task-5-brief.md\$" "$WS/task-5-review-prompt.md")" "1"
step start docs/plan.md 8
step review docs/plan.md 8
check "review: a failed route falls back to judge-opus and says why" \
  "$(grep -c "^seat: dforge:judge-opus prompt: $WS/task-8-review-prompt.md (review-route exited 2: review-route: Task 8: the Evaluation line does not parse" <<<"$out")" "1"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
`````

- [ ] **Step 2: Run the test to verify it fails**

Run: `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID -u CLAUDE_CONFIG_DIR timeout 600 bash plugins/dforge/tests/task-step.test.sh`
Expected: FAIL lines for every `review:` and `check` case (`review` is not yet a subcommand, so each call exits 2), and exit status 1; the Task 5 `start:` cases still pass.

- [ ] **Step 3: Extend the script**

Apply these edits to `plugins/dforge/scripts/task-step`, in order. Each "Replace" text occurs exactly once at that point.

Replace in `plugins/dforge/scripts/task-step`:

`````bash
# Usage: task-step start PLAN_FILE N [M ...] [--wave K] [--reset]
`````

with:

`````bash
# Usage: task-step start  PLAN_FILE N [M ...] [--wave K] [--reset]
#        task-step review PLAN_FILE N [M ...] [--base SHA] [--head REF] [--cwd DIR]
`````

Replace in `plugins/dforge/scripts/task-step`:

`````bash
usage() { die "usage: task-step start PLAN_FILE N [M ...] [--wave K] [--reset]"; }

[ $# -ge 3 ] || usage
`````

with:

`````bash
usage() { die "usage: task-step start PLAN_FILE N [M ...] [--wave K] [--reset] | review PLAN_FILE N [M ...] [--base SHA] [--head REF] [--cwd DIR]"; }

[ $# -ge 3 ] || usage
`````

Replace in `plugins/dforge/scripts/task-step`:

`````bash
case $sub in start) ;; *) usage ;; esac

ids=() wave="" reset=0
`````

with:

`````bash
case $sub in start|review) ;; *) usage ;; esac

ids=() wave="" reset=0 base_arg="" head_arg="" cwd_arg=""
`````

Replace in `plugins/dforge/scripts/task-step`:

`````bash
    -*) usage ;;
    *) [[ $1 =~ ^[0-9]+$ ]] || usage; ids+=("$((10#$1))"); shift ;;
`````

with:

`````bash
    --base) [ "$sub" = review ] && [ $# -ge 2 ] && [ -n "$2" ] || usage; base_arg=$2; shift 2 ;;
    --head) [ "$sub" = review ] && [ $# -ge 2 ] && [ -n "$2" ] || usage; head_arg=$2; shift 2 ;;
    --cwd) [ "$sub" = review ] && [ $# -ge 2 ] && [ -n "$2" ] || usage; cwd_arg=$2; shift 2 ;;
    -*) usage ;;
    *) [[ $1 =~ ^[0-9]+$ ]] || usage; ids+=("$((10#$1))"); shift ;;
`````

Replace in `plugins/dforge/scripts/task-step`:

`````bash
state_line() {
`````

with:

`````bash
# drop_sections HEADING ...: stdin to stdout without the `## ` sections whose
# heading begins with one of the given words.
drop_sections() {
  local list="" h
  for h in "$@"; do list="$list${list:+|}$h"; done
  TS_DROP=$list awk '
    BEGIN { n = split(ENVIRON["TS_DROP"], d, "|") }
    /^## / { skip = 0; for (i = 1; i <= n; i++) if (index($0, "## " d[i]) == 1) skip = 1 }
    !skip { print }'
}

# Every commit from $1 to $2 is authored and committed by the configured
# user. Prints the digest line.
check_identity() {
  local un ue sha an ae cn ce who bad="" count=0
  un=$(git config user.name | tr -d '\r') ue=$(git config user.email | tr -d '\r')
  if [ -z "$un" ] || [ -z "$ue" ]; then echo "check identity: no git user.name and user.email configured"; return; fi
  while IFS=$'\x1f' read -r sha an ae cn ce; do
    [ -n "$sha" ] || continue
    who=""
    if [ "$an" != "$un" ] || [ "$ae" != "$ue" ]; then who="author $an <$ae>"; fi
    if [ "$cn" != "$un" ] || [ "$ce" != "$ue" ]; then who="${who:+$who, }committer $cn <$ce>"; fi
    [ -n "$who" ] || continue
    count=$((count + 1))
    [ -n "$bad" ] || bad="$sha $who"
  done < <(git log --reverse --format='%h%x1f%an%x1f%ae%x1f%cn%x1f%ce' "$1..$2" | tr -d '\r')
  if [ "$count" -eq 0 ]; then echo "check identity: clean"; return; fi
  echo "check identity: $bad (expected $un <$ue>)$([ "$count" -le 1 ] || echo "; $((count - 1)) more commit(s)")"
}

# No commit from $1 to $2 carries an attribution trailer (a co-author or a
# session line) or a line that begins "Generated with", after any leading
# symbols such as a bullet or an emoji. A mention inside a sentence is not
# attribution. Prints the digest line.
check_attribution() {
  local sha hit bad="" count=0
  for sha in $(git rev-list --reverse "$1..$2"); do
    hit=$(git log -1 --format=%B "$sha" | tr -d '\r' | grep -iE '^[[:space:]]*(co-authored-by|claude-session):|^[^[:alnum:]]*generated with' | head -n 1)
    [ -n "$hit" ] || continue
    count=$((count + 1))
    [ -n "$bad" ] || bad="$(git rev-parse --short=7 "$sha") $(cut -c1-70 <<<"$hit")"
  done
  if [ "$count" -eq 0 ]; then echo "check attribution: clean"; return; fi
  echo "check attribution: $bad$([ "$count" -le 1 ] || echo "; $((count - 1)) more commit(s)")"
}

state_line() {
`````

Replace in `plugins/dforge/scripts/task-step`:

`````bash
case $sub in
  start) do_start ;;
esac
`````

with:

`````bash
route_field() { sed -n "s/.* $1=\\([^ ]*\\).*/\\1/p" <<<"$route" | tr -d '\r'; }

do_review() {
  local base head basesha headsha diff pkgout rc t0 gate route rrc primary fallback reason note="" tier="" judge
  local lens_files="" lout lrc n line secs timeout_ms cmd top drops=() unexpanded
  local template="$plugin_root/skills/subagent-driven-development/references/task-reviewer-prompt.md"
  local judge_prompt="$ws/task-$first-review-prompt.md" codex_prompt="$ws/task-$first-review-codex-prompt.md"
  local codex_out="$ws/task-$first-review-codex.json"

  [ -f "$state" ] || die "Task $first has no step state; run task-step start first" 6
  top=$(git rev-parse --show-toplevel)
  if [ -n "$cwd_arg" ]; then
    [ -d "$cwd_arg" ] || die "bad --cwd: $cwd_arg"
    top=$cwd_arg
  fi
  base=$base_arg
  [ -n "$base" ] || base=$(jq -r '.base' "$state" | tr -d '\r')
  head=$head_arg
  [ -n "$head" ] || head=$(jq -r '.head // empty' "$state" | tr -d '\r')
  [ -n "$head" ] || head=HEAD
  basesha=$(git rev-parse --verify --quiet "$base^{commit}") || die "bad BASE: $base"
  headsha=$(git rev-parse --verify --quiet "$head^{commit}") || die "bad head: $head"

  gate=$(bash "${TASK_STEP_CODEX_GATE:-$HERE/codex-gate}" 2>/dev/null | tail -n 1 | tr -d '\r')
  route=$(bash "$HERE/review-route" "$plan" --task "${ids[@]}" 2>"$TMP/route.err"); rrc=$?
  if [ "$rrc" -eq 0 ]; then
    primary=$(route_field primary) fallback=$(route_field fallback) reason=$(route_field reason)
  else
    primary=dforge:judge-opus fallback=- reason=route-failed
    note=" (review-route exited $rrc: $(tr -d '\r' < "$TMP/route.err" | head -n 1))"
  fi
  case $primary in
    codex:light) tier=light judge=$fallback ;;
    codex:heavy+judge-opus) tier=heavy judge=dforge:judge-opus ;;
    *) judge=$primary ;;
  esac
  case $judge in dforge:*) ;; *) judge=dforge:judge-opus ;; esac

  for n in "${ids[@]}"; do
    lout=$(bash "$HERE/lens-route" "$plan" --task "$n" 2>&1); lrc=$?
    [ "$lrc" -eq 0 ] || die "lens-route: $(tr -d '\r' <<<"$lout" | head -n 1)"
    while IFS= read -r line; do
      line=$(sed -n 's/^lens [^ ]* criteria=\(.*\)$/\1/p' <<<"$line" | tr -d '\r')
      [ -n "$line" ] || continue
      case ", $lens_files, " in *", $line, "*) continue ;; esac
      lens_files="${lens_files:+$lens_files, }$line"
    done <<<"$lout"
  done

  pkgout=$(bash "$HERE/review-package" "$plan" "$basesha" "$headsha"); rc=$?
  [ "$rc" -eq 0 ] || { printf '%s\n' "$pkgout" >&2; exit "$rc"; }
  t0=$(date +%s)
  diff=$(sed -n 's/^wrote \(.*\): [0-9]* commit(s), [0-9]* bytes$/\1/p' <<<"$pkgout" | head -n 1 | tr -d '\r')

  [ -n "$lens_files" ] || drops+=("Lens Criteria")
  [ "$tier" = heavy ] || drops+=("Second Pass")
  prompt_text "$template" | drop_sections ${drops[@]+"${drops[@]}"} | fill \
    '[BASE_SHA]' "$basesha" '[HEAD_SHA]' "$headsha" '[DIFF_FILE]' "$diff" '[BRIEF_FILE]' "$brief" \
    '[REPORT_FILE]' "$report" '[PLUGIN_ROOT]' "$plugin_root" '[JUDGE]' "$judge" \
    '[LENS_FILES]' "$lens_files" '[CODEX_REVIEW_FILE]' "$codex_out" > "$judge_prompt"

  if [ -n "$tier" ]; then
    {
      prompt_text "$template" | drop_sections "Output Format" "Criteria" "Lens Criteria" "Second Pass" | fill \
        '[BASE_SHA]' "$basesha" '[HEAD_SHA]' "$headsha" '[DIFF_FILE]' "$diff" '[BRIEF_FILE]' "$brief" \
        '[REPORT_FILE]' "$report" '[PLUGIN_ROOT]' "$plugin_root" '[JUDGE]' "$judge"
      printf '\n## Criteria\n\nScore each criterion independently on a 1 to 20 scale, where 1 is a clear failure, 10 is genuinely uncertain, and 20 is clearly met.\n\n'
      tr -d '\r' < "$plugin_root/criteria/task-review.md" | sed 's/^#/##/'
      printf '\nScore against those criteria and nothing else. Where a criterion tells you to ignore something, ignoring it is part of scoring correctly.\n\n'
      printf '## Output\n\nYour final message is one JSON object that satisfies the output schema, and nothing else: no markdown and no preamble. It carries the four scores (spec, scope, verification, quality), spec_verdict (compliant or issues), task_quality (approved or needs_fixes), findings (severity, file, line and summary for each; line is 0 when a finding has no single line) and cannot_verify (the requirements you could not verify from the diff alone; an empty array when there are none). This overrides any instruction above about the shape of your final message.\n'
    } > "$codex_prompt"
    case $tier in
      light) secs=$(ladder_block codex-judge | awk 'END { print $3 }') ;;
      *) secs=$(ladder_block codex-judge | awk 'NR == 1 { print $3 }') ;;
    esac
    timeout_ms=$(( (${secs:-0} + 120) * 1000 ))
    cmd="bash \"$plugin_root/scripts/run-codex-review.sh\" --kind task --tier $tier --cwd \"$top\" --out \"$codex_out\" --prompt \"$codex_prompt\""
  fi
  for line in "$judge_prompt" ${tier:+"$codex_prompt"}; do
    unexpanded=$(grep -oE '\[[A-Z][A-Z_]*\]' "$line" | head -n 1)
    [ -z "$unexpanded" ] || die "unexpanded placeholder $unexpanded in $line"
  done

  jq --arg rh "$headsha" --argjson t0 "$t0" --arg base "$base_arg" --arg bsha "$basesha" --arg head "$head_arg" \
    '.reviewHead = $rh | .t0 = $t0 | (if $base == "" then . else .base = $bsha end) | (if $head == "" then . else .head = $head end)' \
    "$state" > "$state.tmp" && mv "$state.tmp" "$state"

  printf 'task %s: reviewed %s..%s (%s commit(s)), diff %s\n' "$idlist" "${basesha:0:7}" "${headsha:0:7}" \
    "$(git rev-list --count "$basesha..$headsha")" "$diff"
  if [ "$reason" = codex-off ] || [[ "$gate" == *source=probe ]]; then printf 'gate: %s\n' "$gate"; fi
  case $tier in
    light) printf 'seat: codex:light prompt: %s fallback: %s prompt: %s\n' "$codex_prompt" "$judge" "$judge_prompt" ;;
    heavy) printf 'seat: codex:heavy+judge-opus prompt: %s then: %s prompt: %s\n' "$codex_prompt" "$judge" "$judge_prompt" ;;
    *) printf 'seat: %s prompt: %s%s\n' "$judge" "$judge_prompt" "$note" ;;
  esac
  if [ -n "$tier" ]; then printf 'codex: %s\ntimeout: %s\n' "$cmd" "$timeout_ms"; fi
  check_identity "$basesha" "$headsha"
  check_attribution "$basesha" "$headsha"
  state_line
  printf '%s\n' "$(budget_of <<<"$pkgout")"
}

case $sub in
  start) do_start ;;
  review) do_review ;;
esac
`````

- [ ] **Step 4: Run the test to verify it passes**

Run: `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID -u CLAUDE_CONFIG_DIR timeout 600 bash plugins/dforge/tests/task-step.test.sh`
Expected: `128 passed, 0 failed`.

Run: `timeout 300 node scripts/validate-repository.mjs`
Expected: `Repository catalogs, manifests, versions, bundled links and the settings schema are valid.`

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/scripts/task-step plugins/dforge/tests/task-step.test.sh
git -c user.name=Darkraise -c user.email=quangtc94@gmail.com commit -m "feat(dforge): add task-step review"
```

### Task 7: Type the re-review seat

**Files:**
- Modify: `plugins/dforge/skills/subagent-driven-development/references/re-review-prompt.md`
- Modify: `plugins/dforge/reference/delegated-task.md:28`
- Modify: `plugins/dforge/skills/subagent-driven-development/SKILL.md:331-334`
- Test: `plugins/dforge/tests/seats.test.sh`
- Test: `plugins/dforge/tests/review-route.test.sh:384`

**Acceptance:** A15

**Interfaces:**
- Consumes: the Re-review template contract (Contracts); the typed-seats pattern in `plugins/dforge/skills/requesting-code-review/references/code-reviewer.md` (a `Subagent (dforge:judge-opus):` block line, a required `[DIFF_FILE]`, no git fallback).
- Produces: `re-review-prompt.md` with the block line `Subagent (dforge:judge-sonnet-high; dforge:judge-opus for a subtle concurrency fix):`, no `model:` line, no `[MODEL]` placeholder, and `[DIFF_FILE]` marked REQUIRED; Task 8 renders this template and fails if a placeholder other than the six it fills is left in it.

**Items:** 6
**Implementer:** dforge:impl-sonnet-medium
**Evaluation:** files 1 - spec 0 - coupling 2 - risk 1 = 4

- [ ] **Step 1: Write the failing tests**

In `plugins/dforge/tests/seats.test.sh`, the `good.md` fixture still presents the scoped re-review as a passing general-purpose case. Replace this fixture:

````bash
cat > "$TMP/good.md" <<'EOF'
```
Subagent (general-purpose):
  description: "Re-review"
  model: [MODEL]
  prompt: |
    Re-review it.
```

| Seat | Agent | Model argument |
|---|---|---|
| Scoped re-review | general-purpose | `sonnet` |
EOF
````

with:

````bash
cat > "$TMP/good.md" <<'EOF'
```
Subagent (general-purpose):
  description: "Probe"
  model: sonnet
  prompt: |
    Probe it.
```

| Seat | Agent | Model argument |
|---|---|---|
| Verifier | general-purpose | `sonnet` |
EOF
````

In the same file, insert these lines directly above the line `names "entry point: the Seats section" "$UD" '## Seats'`:

```bash
RRP="$P/skills/subagent-driven-development/references/re-review-prompt.md"
DT="$P/reference/delegated-task.md"
names "re-review: the judge seat" "$RRP" 'Subagent (dforge:judge-sonnet-high; dforge:judge-opus for a subtle concurrency fix):'
check "re-review: no general-purpose seat" "$(grep -c 'general-purpose' "$RRP")" "0"
check "re-review: no model line" "$(grep -c '^  model:' "$RRP")" "0"
check "re-review: no model placeholder" "$(grep -c '\[MODEL\]' "$RRP")" "0"
check "re-review: no git fallback" "$(grep -c 'git diff' "$RRP")" "0"
names "re-review: the diff file is required" "$RRP" '`[DIFF_FILE]` — REQUIRED'
names "re-review: the read-only clause stays" "$RRP" 'Your review is read-only on this checkout.'
check "delegated loop: no general-purpose re-review row" "$(grep -c '^| Scoped re-review | general-purpose' "$DT")" "0"
names "delegated loop: the re-review row names the judge seats" "$DT" '| Scoped re-review | `dforge:judge-sonnet-high`; `dforge:judge-opus` for a subtle concurrency fix | None |'
```

In `plugins/dforge/tests/review-route.test.sh`, replace line 384:

```bash
present "the scoped re-review names its model" "$DT" '| Scoped re-review | general-purpose | `sonnet`; `opus` for a subtle concurrency fix |'
```

with:

```bash
present "the scoped re-review names its judge seats" "$DT" '| Scoped re-review | `dforge:judge-sonnet-high`; `dforge:judge-opus` for a subtle concurrency fix | None |'
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID -u CLAUDE_CONFIG_DIR timeout 600 bash plugins/dforge/tests/seats.test.sh; env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID -u CLAUDE_CONFIG_DIR timeout 600 bash plugins/dforge/tests/review-route.test.sh | grep -E '^FAIL|passed'`
Expected: `seats.test.sh` prints 8 `FAIL` lines (`re-review: the judge seat`, `no general-purpose seat`, `no model line`, `no model placeholder`, `no git fallback`, `the diff file is required`, and the two `delegated loop` rows) and `8 failed` in its last line; `review-route.test.sh` prints `FAIL - the scoped re-review names its judge seats`.

- [ ] **Step 3: Rewrite the template and the seat rows**

In `plugins/dforge/skills/subagent-driven-development/references/re-review-prompt.md`, make these five edits.

1. Name the seat as a fleet agent. After the `**Purpose:**` paragraph (which ends `that the fix itself broke nothing.`), add a blank line and:

```markdown
**Seat:** a fleet judge agent, so the dispatch carries no `model` or `effort`
argument ([delegated-task.md](../../../reference/delegated-task.md) §Seats).
```

2. Replace the block line and its model line:

```
Subagent (general-purpose):
  description: "Re-review Task N fix round R"
  model: [MODEL — REQUIRED: `sonnet`, or `opus` for a subtle concurrency
         fix, per delegated-task.md §Seats; an omitted model silently
         inherits the session's most expensive one]
  prompt: |
```

with:

```
Subagent (dforge:judge-sonnet-high; dforge:judge-opus for a subtle concurrency fix):
  description: "Re-review Task N fix round R"
  prompt: |
```

3. Remove the git fallback. Replace:

```
    and the fix diff with surrounding context. Do not re-run git commands.
    If the diff file is missing, fetch the diff yourself:
    `git diff --stat [FIX_BASE_SHA]..[HEAD_SHA]` and
    `git diff [FIX_BASE_SHA]..[HEAD_SHA]`.
```

with:

```
    and the fix diff with surrounding context. Do not re-run git commands.
```

The read-only paragraph that follows (`Your review is read-only on this checkout. Do not mutate the working tree, the index, HEAD, or branch state in any way.`) stays as it is.

4. In the **Placeholders** list, delete the `[MODEL]` item, these two lines:

```
- `[MODEL]` — REQUIRED: `sonnet`, or `opus` for a subtle concurrency fix, per
  delegated-task.md §Seats
```

5. In the same list, replace the `[DIFF_FILE]` item:

```
- `[DIFF_FILE]` — the path `scripts/review-package PLAN_FILE FIX_BASE HEAD` printed
```

with:

```
- `[DIFF_FILE]` — REQUIRED: the path `scripts/review-package PLAN_FILE FIX_BASE HEAD`
  printed; `task-step rereview` runs it and fills this in
```

In `plugins/dforge/reference/delegated-task.md`, replace the Seats row at line 28:

```
| Scoped re-review | general-purpose | `sonnet`; `opus` for a subtle concurrency fix |
```

with:

```
| Scoped re-review | `dforge:judge-sonnet-high`; `dforge:judge-opus` for a subtle concurrency fix | None |
```

In `plugins/dforge/skills/subagent-driven-development/SKILL.md`, the general-purpose paragraph at lines 331-334 still gives the re-review its models. Replace:

```
which silently defeats the choice. Scoped re-reviews of small fix diffs take
`sonnet`; a subtle concurrency fix takes `opus`.
```

with:

```
which silently defeats the choice.
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `for t in seats review-route process-roles inline-mode; do env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID -u CLAUDE_CONFIG_DIR timeout 600 bash plugins/dforge/tests/$t.test.sh | grep -E '^FAIL|passed'; done; timeout 300 bash plugins/dforge/tests/typed-seats-and-drafting.acceptance.sh A5 A6 | grep -E '^FAIL|passed'; timeout 300 node scripts/validate-repository.mjs | tail -n 1`
Expected: no `FAIL` line; each suite ends `N passed, 0 failed`, and the validator prints `Repository catalogs, manifests, versions, bundled links and the settings schema are valid.`

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/skills/subagent-driven-development/references/re-review-prompt.md plugins/dforge/reference/delegated-task.md plugins/dforge/skills/subagent-driven-development/SKILL.md plugins/dforge/tests/seats.test.sh plugins/dforge/tests/review-route.test.sh
git -c user.name=Darkraise -c user.email=quangtc94@gmail.com commit -m "feat(dforge): type the scoped re-review seat"
```

### Task 8: Add task-step rereview and the skip rule

**Files:**
- Modify: `plugins/dforge/scripts/task-step`
- Modify: `plugins/dforge/tests/task-step.test.sh`

**Acceptance:** A5, A6, A4 (the rereview half)

**Interfaces:**
- Consumes: the `task-step` contract (Contracts): the state file `<ws>/task-<N>-step.json` that `start` and `review` write, the fix message `<ws>/task-<N>-fix-<R>.md`, the prompt file `<ws>/task-<N>-rereview-<R>-prompt.md`, the digest lines, and exits 2, 3, 4 and 6; the Re-review template contract (Task 7); `scripts/review-package`, `scripts/sdd-workspace`, `scripts/context-size`, and `plan_scores` from `scripts/lib/plan.sh`.
- Produces: `task-step rereview PLAN_FILE N [M ...] [--base SHA] [--head REF] [--covered]` as the Contracts entry fixes it. It adds `rr_usage`, `rr_render` and `cmd_rereview` to the script and edits three of its lines (the header's usage comment, the `usage()` message and the point where `rereview` is dispatched). Task 10's text calls the subcommand and reads its `re-review: skipped (...)` line and its `seat:` line.

**Items:** 6
**Implementer:** dforge:impl-sonnet-medium
**Evaluation:** files 1 - spec 1 - coupling 1 - risk 1 = 4

The `rereview` block is self-contained: it uses only `scripts/lib/plan.sh`, the sibling scripts and `jq`, and none of Task 5's and 6's helpers (`prompt_text`, `fill`, `state_line`, `budget_of`, `drop_sections`, their argument parser). So it carries its own copies of plan resolution, the amendment step, the `Host: codex` check and argument parsing, and they must agree with the script's other subcommands: task numbers are normalised with `10#` (`01` finds Task 1's state file), an empty `--base` or `--head` value exits 2, and `--base` and `--head` are recorded in the state file as `review` records them (the state line it prints then shows the new base, which is the `wave merge` argument after an overlap rebase). Three more things differ from what a reader of the contract might assume. `rereview` also sets `t0` (the delegated loop takes the next round's `t0` at the re-review's package call). The seat line always names `dforge:judge-sonnet-high`; the session substitutes `dforge:judge-opus` for a subtle concurrency fix and says so aloud. A missing fix message exits 6, because it is a required earlier step the session has not done.

- [ ] **Step 1: Write the failing tests**

Append this section to `plugins/dforge/tests/task-step.test.sh`, above the lines that end the file (the final `printf '\n%d passed, %d failed\n'` and `[ "$fail" -eq 0 ]`). It relies on the suite's `check` helper and on `HERE` (the absolute directory of the test file) and `TMP` (its `mktemp -d` directory, removed by the suite's `EXIT` trap), all of which the file defines in its header. It builds its own fixture repository under `$TMP/rr`, calls `task-step start` and `task-step review` on it, and then drives `rereview`.

````bash
# --- rereview: the skip rule, the package and the state ---
# The fixture plan's lines carry a leading | so a plan that quotes this suite still lints.
RR_S="$HERE/../scripts"
RR_TMP=$TMP/rr
mkdir -p "$RR_TMP"
RR_REPO=$RR_TMP/repo
rr_run() { # rr_run <args...> — task-step in the fixture repo; sets rr_out, rr_err, rr_rc
  rr_out=$(cd "$RR_REPO" && env HOME="$RR_TMP/home" DR_CODEX_SESSION_DIR="$RR_TMP/sessions" CLAUDE_CODE_SESSION_ID=rr-test \
    GIT_CONFIG_NOSYSTEM=1 DFORGE_NO_SETTINGS=1 MSYS_NO_PATHCONV=1 bash "$RR_S/task-step" "$@" 2>"$RR_TMP/err"); rr_rc=$?
  rr_err=$(cat "$RR_TMP/err")
}
rr_git() { git -C "$RR_REPO" "$@"; }
rr_state() { # rr_state <task> <jq filter>
  jq -r "$2" "$RR_WS/task-$1-step.json" | tr -d '\r'
}
rr_edit() { # rr_edit <file> <mod|add1|add3|add4|bin> — change a fixture file
  local f=$RR_REPO/$1
  RR_N=$((RR_N + 1))
  case $2 in
    mod) awk -v n="$RR_N" 'NR == 2 { print "changed " n; next } { print }' "$f" > "$f.tmp" && mv "$f.tmp" "$f" ;;
    add1) printf 'a%s\n' "$RR_N" >> "$f" ;;
    add3) printf 'a%s\nb\nc\n' "$RR_N" >> "$f" ;;
    add4) printf 'a%s\nb\nc\nd\n' "$RR_N" >> "$f" ;;
    bin) printf 'x\000y%s' "$RR_N" >> "$f" ;;
  esac
}
rr_fix() { # rr_fix <task> <round> <bullets separated by |>
  { printf '%s\n' "$3" | tr '|' '\n'; printf '\nFixed.\n'; } > "$RR_WS/task-$1-fix-$2.md"
}
rr_reset() { # back to the reviewed head with the recorded states
  rr_git reset -q --hard "$RR_R0"
  rm -f "$RR_WS"/task-*-fix-*.md "$RR_WS"/task-*-rereview-*-prompt.md
  cp "$RR_TMP/state1.0" "$RR_WS/task-1-step.json"
  cp "$RR_TMP/state2.0" "$RR_WS/task-2-step.json"
}
rr_verdict() { # rr_verdict <task> <round> — the skip line, or "prompt", or "none"
  if grep -q '^re-review: ' <<<"$rr_out"; then grep '^re-review: ' <<<"$rr_out"
  elif [ -f "$RR_WS/task-$1-rereview-$2-prompt.md" ]; then echo prompt
  else echo none; fi
}
rr_case() { # rr_case <name> <task> <flags> <bullets> <edits> <want> — one fix, one rereview
  local e
  rr_reset
  for e in $5; do rr_edit "${e%%:*}" "${e#*:}"; done
  rr_git add -A && rr_git commit -qm fix
  rr_fix "$2" 1 "$4"
  # shellcheck disable=SC2086
  rr_run rereview docs/plan.md "$2" $3
  check "rereview $1" "$rr_rc $(rr_verdict "$2" 1)" "$6"
}

mkdir -p "$RR_TMP/home" "$RR_REPO/docs"
git init -q "$RR_REPO"
rr_git config user.name t
rr_git config user.email t@example.invalid
sed 's/^|//' > "$RR_REPO/docs/plan.md" <<'PLAN'
|# Rereview Fixture Plan
|
|**Goal:** Fixture.
|
|**Execution:** subagent — `claude --model sonnet --effort high` — fixture
|
|## Task index
|
|1. Small
|2. Risky
|3. Unreviewed
|
|### Task 1: Small
|
|**Files:**
|- Modify: `app.txt`
|
|**Implementer:** dforge:impl-sonnet-low
|**Evaluation:** files 0 - spec 0 - coupling 1 - risk 0 = 1
|
|### Task 2: Risky
|
|**Files:**
|- Modify: `app.txt`
|
|**Implementer:** dforge:impl-opus-high
|**Evaluation:** files 1 - spec 1 - coupling 1 - risk 3 = 6
|
|### Task 3: Unreviewed
|
|**Files:**
|- Modify: `other.txt`
|
|**Implementer:** dforge:impl-sonnet-low
|**Evaluation:** files 0 - spec 0 - coupling 1 - risk 0 = 1
PLAN
awk '{ print } /^\*\*Goal:\*\*/ { print ""; print "**Host:** codex" }' "$RR_REPO/docs/plan.md" > "$RR_REPO/docs/codex-plan.md"
seq 1 10 | sed 's/^/line /' > "$RR_REPO/app.txt"
cp "$RR_REPO/app.txt" "$RR_REPO/other.txt"
cp "$RR_REPO/app.txt" "$RR_REPO/test.txt"
printf 'a\000b' > "$RR_REPO/bin.dat"
rr_git add -A && rr_git commit -qm base
RR_N=0

rr_run start docs/plan.md 1
check "rereview fixture: start 1" "$rr_rc" "0"
rr_run start docs/plan.md 2
check "rereview fixture: start 2" "$rr_rc" "0"
rr_run start docs/plan.md 3
check "rereview fixture: start 3" "$rr_rc" "0"
rr_edit app.txt mod
rr_git add -A && rr_git commit -qm work
rr_run review docs/plan.md 1
check "rereview fixture: review 1" "$rr_rc" "0"
rr_run review docs/plan.md 2
check "rereview fixture: review 2" "$rr_rc" "0"
RR_WS=$(cd "$RR_REPO" && env HOME="$RR_TMP/home" bash "$RR_S/sdd-workspace" docs/plan.md)
RR_R0=$(rr_git rev-parse HEAD)
cp "$RR_WS/task-1-step.json" "$RR_TMP/state1.0"
cp "$RR_WS/task-2-step.json" "$RR_TMP/state2.0"

# The skip rule: one open finding, at most 3 changed lines (test files
# included) touching the finding's file, a task below risk 3, and --covered.
rr_case "skips a one-line fix" 1 --covered "- app.txt: wrong value" "app.txt:mod" "0 re-review: skipped (2 changed lines, 1 finding, app.txt)"
rr_case "skips exactly 3 changed lines" 1 --covered "- app.txt: wrong value" "app.txt:add3" "0 re-review: skipped (3 changed lines, 1 finding, app.txt)"
rr_case "counts a test file edit toward the limit" 1 --covered "- app.txt: wrong value" "app.txt:mod test.txt:mod" "0 prompt"
rr_case "skips a small fix that also adds a test line" 1 --covered "- app.txt: wrong value" "app.txt:add1 test.txt:add1" "0 re-review: skipped (2 changed lines, 1 finding, app.txt)"
rr_case "does not skip 4 changed lines" 1 --covered "- app.txt: wrong value" "app.txt:add4" "0 prompt"
rr_case "does not skip without --covered" 1 "" "- app.txt: wrong value" "app.txt:mod" "0 prompt"
rr_case "does not skip with two open findings" 1 --covered "- app.txt: wrong value|- other.txt: stale" "app.txt:mod" "0 prompt"
rr_case "does not skip a fix that edits only another test file" 1 --covered "- app.txt: wrong value" "test.txt:mod" "0 prompt"
rr_case "does not skip a fix to another file than the finding's" 1 --covered "- app.txt: wrong value" "other.txt:mod" "0 prompt"
rr_case "does not skip a binary fix" 1 --covered "- bin.dat: wrong blob" "bin.dat:bin" "0 prompt"
rr_case "does not skip a risk 3 task" 2 --covered "- app.txt: wrong value" "app.txt:mod" "0 prompt"
rr_case "reads a backticked finding path with a line suffix" 1 --covered '- `app.txt:12`: wrong value' "app.txt:mod" "0 re-review: skipped (2 changed lines, 1 finding, app.txt)"

# A skipped round still packages the fix and advances the state.
rr_reset
rr_edit app.txt mod
rr_git add -A && rr_git commit -qm fix
rr_fix 1 1 "- app.txt: wrong value"
rr_run rereview docs/plan.md 1 --covered
check "rereview skip: records the head as the review head" "$(rr_state 1 .reviewHead)" "$(rr_git rev-parse HEAD)"
check "rereview skip: increments the round" "$(rr_state 1 .round)" "1"
check "rereview skip: records t0" "$([ "$(rr_state 1 .t0)" != null ] && echo yes || echo no)" "yes"
check "rereview skip: the digest fits 15 lines" "$([ "$(wc -l <<<"$rr_out")" -le 15 ] && echo yes || echo no)" "yes"
check "rereview skip: the digest names the state" "$(grep -c "^state: base .* review-head $(rr_git rev-parse --short HEAD) round 1 t0 " <<<"$rr_out")" "1"
check "rereview skip: the digest ends with the budget line" "$(tail -n 1 <<<"$rr_out" | cut -c1-7)" "budget:"
check "rereview skip: no prompt is written" "$(ls "$RR_WS"/task-1-rereview-*-prompt.md 2>/dev/null | wc -l | tr -d ' ')" "0"

# A written prompt: the judge seat, no unexpanded placeholder, the open
# findings, the fix base and the diff file.
rr_reset
rr_edit app.txt add4
rr_git add -A && rr_git commit -qm fix
rr_fix 1 1 "- app.txt: wrong value|- other.txt: stale"
rr_run rereview docs/plan.md 1 --covered
RR_P=$RR_WS/task-1-rereview-1-prompt.md
check "rereview prompt: the digest names the seat and the file" "$(grep -c "^seat: dforge:judge-sonnet-high prompt: $RR_P\$" <<<"$rr_out")" "1"
check "rereview prompt: no placeholder is left" "$(grep -cE '\[(BRIEF_FILE|FINDINGS|REPORT_FILE|FIX_BASE_SHA|HEAD_SHA|DIFF_FILE|MODEL)\]' "$RR_P")" "0"
check "rereview prompt: the open findings are listed" "$(grep -c '^- app.txt: wrong value$\|^- other.txt: stale$' "$RR_P")" "2"
check "rereview prompt: the fix base is the recorded review head" "$(grep -c "Fix base:\*\* $RR_R0 " "$RR_P")" "1"
check "rereview prompt: the head is HEAD" "$(grep -c "Head:\*\* $(rr_git rev-parse HEAD)\$" "$RR_P")" "1"
RR_DIFF=$(sed -n 's/^\*\*Diff file:\*\* //p' "$RR_P")
check "rereview prompt: the diff file exists" "$([ -s "$RR_DIFF" ] && echo yes || echo no)" "yes"
check "rereview prompt: the report and brief paths" "$(grep -c "$RR_WS/task-1-report.md\|$RR_WS/task-1-brief.md" "$RR_P")" "2"
check "rereview prompt: the fence and indent are removed" "$(grep -c '^```\|^    You are re-reviewing' "$RR_P")" "0"

# Rounds chain: the next round's base is the last round's head.
RR_H1=$(rr_git rev-parse HEAD)
rr_edit app.txt add4
rr_git add -A && rr_git commit -qm fix2
rr_fix 1 2 "- app.txt: still wrong"
rr_run rereview docs/plan.md 1 --covered
check "rereview round 2: writes the round 2 prompt" "$([ -f "$RR_WS/task-1-rereview-2-prompt.md" ] && echo yes || echo no)" "yes"
check "rereview round 2: the fix base is round 1's head" "$(grep -c "Fix base:\*\* $RR_H1 " "$RR_WS/task-1-rereview-2-prompt.md")" "1"
check "rereview round 2: the state round is 2" "$(rr_state 1 .round)" "2"

# --base moves the package start, and the skip rule counts from it.
rr_reset
rr_edit app.txt mod
rr_git add -A && rr_git commit -qm fix-a
rr_edit app.txt add3
rr_git add -A && rr_git commit -qm fix-b
rr_fix 1 1 "- app.txt: wrong value"
rr_run rereview docs/plan.md 1 --covered
check "rereview without --base counts from the recorded review head" "$(rr_verdict 1 1)" "prompt"
rr_reset
rr_edit app.txt mod
rr_git add -A && rr_git commit -qm fix-a
RR_A=$(rr_git rev-parse HEAD)
rr_edit app.txt add3
rr_git add -A && rr_git commit -qm fix-b
rr_fix 1 1 "- app.txt: wrong value"
rr_run rereview docs/plan.md 1 --covered --base "$RR_A"
check "rereview --base counts from the given base" "$(rr_verdict 1 1)" "re-review: skipped (3 changed lines, 1 finding, app.txt)"
rr_reset
rr_edit app.txt mod
rr_git add -A && rr_git commit -qm fix-a
RR_A=$(rr_git rev-parse HEAD)
rr_edit app.txt add3
rr_git add -A && rr_git commit -qm fix-b
rr_fix 1 1 "- app.txt: wrong value"
rr_run rereview docs/plan.md 1 --base "$RR_A"
check "rereview --base: the prompt's fix base is the given base" "$(grep -c "Fix base:\*\* $RR_A " "$RR_WS/task-1-rereview-1-prompt.md")" "1"
check "rereview --base: the diff file starts at the given base" "$(sed -n 's/^\*\*Diff file:\*\* //p' "$RR_WS/task-1-rereview-1-prompt.md" | xargs basename | grep -c "^review-$(rr_git rev-parse --short "$RR_A")\.\.")" "1"
check "rereview --base: the state records it as the base" "$(rr_state 1 .base)" "$RR_A"
check "rereview --base: the state line shows it" "$(grep -c "^state: base $(rr_git rev-parse --short "$RR_A") " <<<"$rr_out")" "1"

# --head packages up to the task ref and leaves later commits out.
rr_reset
rr_edit app.txt mod
rr_git add -A && rr_git commit -qm fix-a
rr_git branch -f rr-task-ref
rr_edit app.txt add4
rr_git add -A && rr_git commit -qm later
rr_fix 1 1 "- app.txt: wrong value"
rr_run rereview docs/plan.md 1 --covered --head rr-task-ref
check "rereview --head: skips on the ref's diff alone" "$(rr_verdict 1 1)" "re-review: skipped (2 changed lines, 1 finding, app.txt)"
check "rereview --head: records the ref's commit as the review head" "$(rr_state 1 .reviewHead)" "$(rr_git rev-parse rr-task-ref)"
check "rereview --head: records the ref" "$(rr_state 1 .head)" "rr-task-ref"

# A zero-padded task number names the same task.
rr_reset
rr_edit app.txt mod
rr_git add -A && rr_git commit -qm fix
rr_fix 1 1 "- app.txt: wrong value"
rr_run rereview docs/plan.md 01 --covered
check "rereview names Task 1 as 01" "$rr_rc $(rr_verdict 1 1)" "0 re-review: skipped (2 changed lines, 1 finding, app.txt)"

# Refusals write nothing.
rr_reset
rr_run rereview docs/plan.md 3
check "rereview before review exits 6" "$rr_rc" "6"
rr_reset
rr_run rereview docs/plan.md 1 --covered
check "rereview with no fix message exits 6" "$rr_rc" "6"
check "rereview with no fix message leaves the state alone" "$(cmp -s "$RR_WS/task-1-step.json" "$RR_TMP/state1.0" && echo same || echo changed)" "same"
printf 'No bullets here.\n' > "$RR_WS/task-1-fix-1.md"
rr_run rereview docs/plan.md 1
check "rereview with a fix message that has no bullets exits 2" "$rr_rc" "2"
rr_reset
rr_run rereview docs/plan.md 9
check "rereview of a task not in the plan exits 3" "$rr_rc" "3"
rr_run rereview docs/codex-plan.md 1
check "rereview on a Host: codex plan exits 2" "$rr_rc" "2"
check "rereview on a Host: codex plan writes nothing" "$(ls -A "$(dirname "$RR_WS")/codex-plan" 2>/dev/null | wc -l | tr -d ' ')" "0"
rr_run rereview docs/plan.md 1 --bogus
check "rereview with an unknown flag exits 2" "$rr_rc" "2"
rr_run rereview docs/plan.md 1 --base ""
check "rereview with an empty --base exits 2" "$rr_rc" "2"
rr_run rereview docs/plan.md 1 --head ""
check "rereview with an empty --head exits 2" "$rr_rc" "2"
````

- [ ] **Step 2: Run the tests to verify they fail**

Run: `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID -u CLAUDE_CONFIG_DIR timeout 600 bash plugins/dforge/tests/task-step.test.sh | grep -E '^FAIL|passed'`
Expected: the five `rereview fixture:` lines pass (they only call `start` and `review`), and the skip, prompt, round, `--base`, `--head` and exit 3 and 6 lines fail, because the script does not know the `rereview` subcommand and exits 2; the run ends `143 passed, 40 failed`.

- [ ] **Step 3: Add the rereview subcommand**

Apply these three edits to `plugins/dforge/scripts/task-step`, in order. Each "Replace" text occurs exactly once in the script as Task 6 left it. The `case $sub in start|review) ;; *) usage ;; esac` line stays as it is: `rereview` is dispatched before it, because the argument loop that `start` and `review` share rejects `--covered`.

Replace in `plugins/dforge/scripts/task-step`:

`````bash
#        task-step review PLAN_FILE N [M ...] [--base SHA] [--head REF] [--cwd DIR]
`````

with:

`````bash
#        task-step review PLAN_FILE N [M ...] [--base SHA] [--head REF] [--cwd DIR]
#        task-step rereview PLAN_FILE N [M ...] [--base SHA] [--head REF] [--covered]
`````

Replace in `plugins/dforge/scripts/task-step`:

`````bash
usage() { die "usage: task-step start PLAN_FILE N [M ...] [--wave K] [--reset] | review PLAN_FILE N [M ...] [--base SHA] [--head REF] [--cwd DIR]"; }
`````

with:

`````bash
usage() { die "usage: task-step start PLAN_FILE N [M ...] [--wave K] [--reset] | review PLAN_FILE N [M ...] [--base SHA] [--head REF] [--cwd DIR] | rereview PLAN_FILE N [M ...] [--base SHA] [--head REF] [--covered]"; }
`````

Replace in `plugins/dforge/scripts/task-step`:

`````bash
[ $# -ge 3 ] || usage
sub=$1; plan_arg=$2; shift 2
`````

with the function block below (it defines three functions and runs nothing), followed by the dispatch lines under it, in that order:

````bash
rr_usage() {
  echo "usage: task-step rereview PLAN_FILE N [M ...] [--base SHA] [--head REF] [--covered]" >&2
  exit 2
}

rr_render() { # rr_render TEMPLATE FINDINGS_FILE — the fenced prompt body, de-indented, placeholders filled from RR_*
  awk -v findings="$2" '
    function rep(s, key, val,   out, i) {
      out = ""
      while ((i = index(s, key)) > 0) { out = out substr(s, 1, i - 1) val; s = substr(s, i + length(key)) }
      return out s
    }
    BEGIN { while ((getline line < findings) > 0) fl = fl (fl == "" ? "" : "\n") line }
    { sub(/\r$/, "") }
    !fenced { if ($0 == "```") fenced = 1; next }
    !body { if ($0 ~ /^[ ]+prompt: \|$/) body = 1; next }
    $0 == "```" { exit }
    {
      sub(/^    /, "")
      if ($0 == "[FINDINGS]") { print fl; next }
      $0 = rep($0, "[BRIEF_FILE]", ENVIRON["RR_BRIEF"])
      $0 = rep($0, "[REPORT_FILE]", ENVIRON["RR_REPORT"])
      $0 = rep($0, "[FIX_BASE_SHA]", ENVIRON["RR_FIX_BASE"])
      $0 = rep($0, "[HEAD_SHA]", ENVIRON["RR_HEAD"])
      $0 = rep($0, "[DIFF_FILE]", ENVIRON["RR_DIFF"])
      print
    }
  ' "$1"
}

# A subshell body: every exit below leaves only the subshell, so the
# dispatch branch passes the status on.
cmd_rereview() (
  local here plan_arg plan tmp src header ws state first t scores row risk
  local fix bullets nopen file review_head round new_round head_ref head_sha fix_base fix_base_sha
  local pkg diff_file numstat a d f lines over touched risk3 skip why now prompt tpl ids
  local tasks=() base_arg="" head_arg="" covered=0
  here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
  . "$here/lib/plan.sh"
  [ $# -ge 2 ] || rr_usage
  plan_arg=$1; shift
  while [ $# -gt 0 ]; do
    case $1 in
      --base) [ $# -ge 2 ] && [ -n "$2" ] || rr_usage; base_arg=$2; shift 2 ;;
      --head) [ $# -ge 2 ] && [ -n "$2" ] || rr_usage; head_arg=$2; shift 2 ;;
      --covered) covered=1; shift ;;
      *) [[ $1 =~ ^[0-9]+$ ]] || rr_usage; tasks+=("$((10#$1))"); shift ;;
    esac
  done
  [ "${#tasks[@]}" -ge 1 ] || rr_usage

  plan=$(plan_locate "$plan_arg")
  [ -f "$plan" ] || { echo "no such plan file: $plan" >&2; exit 2; }
  dforge_stores_init "$(_plan_ctx "$plan")"
  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' EXIT
  src=$tmp/plan.md
  if ! plan_apply_amendments "$plan" "$(plan_amendments_file "$plan")" > "$src" 2> "$tmp/err"; then
    cat "$tmp/err" >&2
    exit 4
  fi
  header=$(plan_header "$src")
  if grep -qE '^(\*\*)?Host:(\*\*)?[ \t]+codex[ \t]*$' <<<"$header"; then
    echo "task-step: a Host: codex plan runs the Codex loop; task-step does not apply" >&2
    exit 2
  fi
  plan_require_same_project "$plan"
  for t in "${tasks[@]}"; do
    plan_task_text "$src" "$t" >/dev/null || { echo "task $t not found in $plan" >&2; exit 3; }
  done

  first=${tasks[0]}
  ids=$(IFS=,; echo "${tasks[*]}")
  ws=$(bash "$here/sdd-workspace" "$plan")
  state=$ws/task-$first-step.json
  review_head=""
  [ ! -f "$state" ] || review_head=$(jq -r '.reviewHead // empty' "$state" | tr -d '\r')
  if [ -z "$review_head" ]; then
    echo "task-step: rereview before review: run task-step review for task $first first" >&2
    exit 6
  fi
  round=$(jq -r '.round // 0' "$state" | tr -d '\r')
  new_round=$((round + 1))

  fix=$ws/task-$first-fix-$new_round.md
  if [ ! -f "$fix" ]; then
    echo "task-step: no fix message $fix; write it before rereview" >&2
    exit 6
  fi
  bullets=$(awk '{ sub(/\r$/, "") } /^- / { print; next } { exit }' "$fix")
  nopen=$(printf '%s\n' "$bullets" | awk 'NF { n++ } END { print n + 0 }')
  if [ "$nopen" -lt 1 ]; then
    echo "task-step: $fix must start with one '- <file>: <finding>' bullet per open finding" >&2
    exit 2
  fi
  file=${bullets%%$'\n'*}
  file=${file#- }
  file=${file%%: *}
  file=$(printf '%s' "$file" | tr -d '`' | sed -E 's/:[0-9][0-9,-]*$//; s#^\./##')

  head_ref=$head_arg
  [ -n "$head_ref" ] || head_ref=$(jq -r '.head // empty' "$state" | tr -d '\r')
  [ -n "$head_ref" ] || head_ref=HEAD
  head_sha=$(git rev-parse --verify --quiet "$head_ref^{commit}") || { echo "bad HEAD: $head_ref" >&2; exit 2; }
  fix_base=$base_arg
  [ -n "$fix_base" ] || fix_base=$review_head
  fix_base_sha=$(git rev-parse --verify --quiet "$fix_base^{commit}") || { echo "bad BASE: $fix_base" >&2; exit 2; }

  scores=$(plan_scores "$src")
  risk3=0
  for t in "${tasks[@]}"; do
    row=$(awk -F'\t' -v n="$t" '$1 == n' <<<"$scores")
    risk=$(cut -f3 <<<"$row")
    case $risk in 0|1|2) ;; *) risk3=1 ;; esac
  done

  lines=0 over=0 touched=0
  numstat=$(git -c core.quotepath=off diff --numstat --no-renames "$fix_base_sha..$head_sha")
  while IFS=$'\t' read -r a d f; do
    [ -n "$f" ] || continue
    f=${f%$'\r'}
    if [ "$a" = "-" ] || [ "$d" = "-" ]; then over=1; else lines=$((lines + a + d)); fi
    [ "$f" != "$file" ] || touched=1
  done <<<"$numstat"

  skip=0 why=""
  if [ "$nopen" -ne 1 ]; then why="$nopen findings open"
  elif [ "$risk3" -eq 1 ]; then why="risk 3 or unscored"
  elif [ "$covered" -ne 1 ]; then why="--covered not given"
  elif [ "$over" -eq 1 ]; then why="binary file in the fix"
  elif [ "$lines" -gt 3 ]; then why="$lines changed lines"
  elif [ "$touched" -ne 1 ]; then why="the fix does not touch $file"
  else skip=1
  fi

  pkg=$(bash "$here/review-package" "$plan" "$fix_base_sha" "$head_sha") || { printf '%s\n' "$pkg" >&2; exit 2; }
  diff_file=$(printf '%s\n' "$pkg" | sed -n -E '/^wrote /{s/^wrote (.*): [0-9]+ commit\(s\), [0-9]+ bytes$/\1/;p;q;}')

  prompt=$ws/task-$first-rereview-$new_round-prompt.md
  if [ "$skip" -eq 0 ]; then
    tpl=$here/../skills/subagent-driven-development/references/re-review-prompt.md
    [ -f "$tpl" ] || { echo "task-step: missing template $tpl" >&2; exit 2; }
    printf '%s\n' "$bullets" > "$tmp/findings"
    RR_BRIEF=$ws/task-$first-brief.md RR_REPORT=$ws/task-$first-report.md RR_FIX_BASE=$fix_base_sha \
      RR_HEAD=$head_sha RR_DIFF=$diff_file rr_render "$tpl" "$tmp/findings" > "$tmp/prompt"
    if grep -qE '\[(BRIEF_FILE|FINDINGS|REPORT_FILE|FIX_BASE_SHA|HEAD_SHA|DIFF_FILE|MODEL)\]' "$tmp/prompt"; then
      echo "task-step: $tpl holds a placeholder rereview does not fill" >&2
      exit 2
    fi
    cp "$tmp/prompt" "$prompt"
  fi

  now=$(date +%s)
  jq --arg rh "$head_sha" --argjson r "$new_round" --argjson t "$now" \
    --arg base "$base_arg" --arg bsha "$fix_base_sha" --arg head "$head_arg" \
    '.reviewHead = $rh | .round = $r | .t0 = $t | (if $base == "" then . else .base = $bsha end) | (if $head == "" then . else .head = $head end)' \
    "$state" > "$state.tmp"
  mv "$state.tmp" "$state"

  if [ "$skip" -eq 1 ]; then
    printf 'task %s: re-review round %s: packaged %s..%s, skipped\n' "$ids" "$new_round" "${fix_base_sha:0:7}" "${head_sha:0:7}"
    printf 're-review: skipped (%s changed lines, 1 finding, %s)\n' "$lines" "$file"
  else
    printf 'task %s: re-review round %s: packaged %s..%s, prompt written (not skipped: %s)\n' "$ids" "$new_round" "${fix_base_sha:0:7}" "${head_sha:0:7}" "$why"
    printf 'seat: dforge:judge-sonnet-high prompt: %s\n' "$prompt"
  fi
  printf 'state: base %s review-head %s round %s t0 %s\n' \
    "$(jq -r '.base' "$state" | tr -d '\r' | cut -c1-7)" "${head_sha:0:7}" "$new_round" "$now"
  DFORGE_BUDGET_CALLER="task-step:rereview" bash "$here/context-size" 2>/dev/null || true
)
````

Directly after the function block come the early dispatch and the two lines the edit replaced. `cmd_rereview` is a subshell function, so its `exit` codes arrive at the dispatch as `$?`:

```bash
if [ "${1:-}" = rereview ]; then
  shift
  cmd_rereview "$@"
  exit $?
fi
[ $# -ge 3 ] || usage
sub=$1; plan_arg=$2; shift 2
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID -u CLAUDE_CONFIG_DIR timeout 600 bash plugins/dforge/tests/task-step.test.sh | grep -E '^FAIL|passed'; bash -n plugins/dforge/scripts/task-step && echo syntax ok`
Expected: no `FAIL` line, a final `183 passed, 0 failed`, and `syntax ok`.

Then run the suites that read the template and the neighbouring scripts: `for t in seats review-route working-directory budget-line; do env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID -u CLAUDE_CONFIG_DIR timeout 600 bash plugins/dforge/tests/$t.test.sh | grep -E '^FAIL|passed'; done`
Expected: no `FAIL` line.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/scripts/task-step plugins/dforge/tests/task-step.test.sh
git -c user.name=Darkraise -c user.email=quangtc94@gmail.com commit -m "feat(dforge): add task-step rereview"
```

### Task 9: End the turn to wait in subagent-driven-development

**Files:**
- Create: `plugins/dforge/tests/waiting-text.test.sh`
- Modify: `plugins/dforge/skills/subagent-driven-development/SKILL.md` (§The Task Loop, "Waiting on dispatched subagents"; §The Ruling Seat, "How")
- Modify: `plugins/dforge/reference/delegated-task.md` (§2 "No status line")
- Modify: `plugins/dforge/skills/executing-plans/SKILL.md` (the ruling "How" paragraph)
- Unchanged, and pinned by the new test: `plugins/dforge/skills/using-dforge/references/codex-tools.md` (§Waiting on children keeps Codex's bounded `wait_agent` stretches)

**Acceptance:** A14

**Interfaces:**
- Consumes: Contracts "Reconcile prompt" (the 20-minute and 30-minute figures the new text repeats), "`inflight_scan` line" (the start time and idle minutes that `scripts/in-flight` prints), "Ruling route" (a comma-separated kind list; `dforge:judge-sonnet-high` with `reason=simple-kind`) and "`scripts/task-step`" (the `check identity:` and `check attribution:` digest lines).
- Produces: the waiting rule in `skills/subagent-driven-development/SKILL.md` §The Task Loop, which `reference/delegated-task.md` §2 and `reference/parallel-waves.md` already point at, and the ledger line `Task <N>: Ruling: cannot-verify — settled by task-step check <name> — none`.

**Items:** 2, 4
**Implementer:** dforge:impl-sonnet-medium
**Evaluation:** files 2 - spec 0 - coupling 1 - risk 1 = 4

`skills/subagent-driven-development/SKILL.md` is 43,444 bytes. No test caps a skill file's size (`tests/hook.test.sh` caps only `skills/using-dforge/SKILL.md`, at 5,500 bytes), and this task grows it by under 2,000 bytes.

- [ ] **Step 1: Write the failing test**

Create `plugins/dforge/tests/waiting-text.test.sh` with mode 100644 (it is run through `bash`):

````bash
#!/usr/bin/env bash
# A Claude Code session waits for background work by ending its turn, and only
# Codex waits in bounded wait_agent stretches. The skill text must not send a
# Claude Code session back to Monitor or sleep polling, and must keep Codex's
# stretches where they are.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
P="$HERE/.."
SDD="$P/skills/subagent-driven-development/SKILL.md"
DT="$P/reference/delegated-task.md"
CODEX="$P/skills/using-dforge/references/codex-tools.md"

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
names() { # names <label> <file> <text>
  check "$1" "$(grep -qF -- "$3" "$2" 2>/dev/null && echo yes || echo no)" "yes"
}
lacks() { # lacks <label> <file> <text>
  check "$1" "$(grep -qF -- "$3" "$2" 2>/dev/null && echo yes || echo no)" "no"
}

# polling FILE - one "line: text" per line that names a Monitor, a sleep or an
# until-loop without forbidding it
polling() {
  grep -n -i -E 'monitor|sleep|until-loop' "$1" \
    | grep -vF 'Never wait with `Monitor`, `sleep` or a polling loop.' || true
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/old-wait.md" <<'FIXTURE'
On Claude Code a bounded stretch is a `Monitor` with an until-loop, never a
background `sleep`: a sleep is one more launch that has not reported back.
FIXTURE
check "a Monitor wait is caught" "$(polling "$TMP/old-wait.md" | cut -d: -f1 | tr '\n' ' ')" "1 2 "

cat > "$TMP/new-wait.md" <<'FIXTURE'
Never wait with `Monitor`, `sleep` or a polling loop.
FIXTURE
check "the prohibition is not caught" "$(polling "$TMP/new-wait.md")" ""

check "subagent-driven-development prescribes no Monitor or sleep wait" "$(polling "$SDD")" ""
names "a Claude Code session ends the turn when only waiting remains" "$SDD" \
  'arrive on their own. When only waiting remains, end the turn: each completion'
names "the prohibition is stated" "$SDD" 'Never wait with `Monitor`, `sleep` or a polling loop.'
names "a notification turn starts with in-flight" "$SDD" 'On a turn that a notification started, run `scripts/in-flight` before'
lacks "the bounded Monitor stretch is gone" "$SDD" 'a bounded stretch is a `Monitor`'
lacks "the stretch advice is gone" "$SDD" 'wait in bounded stretches (five to ten'
names "Codex keeps its stretches in the skill" "$SDD" 'On Codex, `wait_agent` covers the idle window instead, in bounded stretches,'
lacks "the delegated loop no longer says wait in bounded stretches" "$DT" 'wait in bounded stretches'
names "the delegated loop points at the waiting rule" "$DT" \
  'subagents says (on Claude Code, end the turn; on Codex, bounded `wait_agent`'

names "codex-tools keeps the bounded wait_agent stretch" "$CODEX" 'bounded stretches: `wait_agent` with `timeout_ms` 300000-600000'
names "codex-tools keeps the five-minute floor" "$CODEX" 'Never stack polls shorter than five minutes'

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
````

- [ ] **Step 2: Run the test to verify it fails**

Run: `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID -u CLAUDE_CONFIG_DIR timeout 600 bash plugins/dforge/tests/waiting-text.test.sh`
Expected: exit 1, `4 passed, 9 failed`. The passes are the two fixture checks and the two `codex-tools.md` checks; the failures name the Monitor wait still in the skill.

- [ ] **Step 3: Rewrite the waiting paragraph for Claude Code**

In `plugins/dforge/skills/subagent-driven-development/SKILL.md`, replace:

````text
**Waiting on dispatched subagents:** never poll a wait interface with
short timeouts, and never sit in one silent, open-ended wait either.
While you have local work — ledger updates, packaging the next review,
reading reports — keep working; child results arrive on their own.
When you are genuinely idle, wait in bounded stretches (five to ten
minutes, where your platform allows), and between stretches post one
line of status and reconcile your live children: list them, and chase
any that finished without reporting. A bounded stretch keeps nearly
all of a long wait's efficiency while guaranteeing a stuck or lost
child is noticed within minutes, not at the end of the session.
On Claude Code a bounded stretch is a `Monitor` with an until-loop, never a
background `sleep`: a sleep is one more launch that has not reported back.
Stop the monitor with `TaskStop` once the stretch has served, and always
before dforge:handoff.
````

with:

````text
**Waiting on dispatched subagents (Claude Code):** Agent dispatches run in
the background, and so do a Codex review seat and a suite that outruns Bash's
ten-minute foreground cap. While local work remains — ledger updates,
packaging the next review, reading reports — keep working; child results
arrive on their own. When only waiting remains, end the turn: each completion
notification starts the next turn.
Never wait with `Monitor`, `sleep` or a polling loop.

On a turn that a notification started, run `scripts/in-flight` before
anything else and handle every launch that finished, including one whose
notification you missed. Its lines show each launch's start time and idle
minutes. In an auto run, a launch that never notifies is caught by the
cockpit, which after 20 minutes without a turn tells you to stop each launch
idle for 30 minutes or more.

On Codex, `wait_agent` covers the idle window instead, in bounded stretches,
because completion mail does not wake an idle session: see Waiting on
children in `skills/using-dforge/references/codex-tools.md`.
````

- [ ] **Step 4: Point the delegated loop at the new rule**

In `plugins/dforge/reference/delegated-task.md`, replace:

````text
finish first: wait in bounded stretches (subagent-driven-development, Waiting
on dispatched subagents), and stop it with `TaskStop` if it outlives the
rung's bound. After two continuations with no status, handle the task as
````

with:

````text
finish first: wait as subagent-driven-development's Waiting on dispatched
subagents says (on Claude Code, end the turn; on Codex, bounded `wait_agent`
stretches), and stop it with `TaskStop` if it outlives the rung's bound.
After two continuations with no status, handle the task as
````

- [ ] **Step 5: Run the test and the suites that read these files**

Run, with the Bash tool's `timeout` at 600000 ms:

```bash
for t in waiting-text review-route inline-mode auto-run-skills final-phase process-roles seats project-status turn-end; do
  printf '%s: ' "$t"
  env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID -u CLAUDE_CONFIG_DIR timeout 600 bash plugins/dforge/tests/$t.test.sh | tail -n 1
done
```

Expected: every line ends `0 failed`, and `waiting-text` prints `13 passed, 0 failed`.

- [ ] **Step 6: Commit the waiting rule**

```bash
git add plugins/dforge/tests/waiting-text.test.sh plugins/dforge/skills/subagent-driven-development/SKILL.md plugins/dforge/reference/delegated-task.md
git -c user.name=Darkraise -c user.email=quangtc94@gmail.com commit -m "docs(dforge): wait by ending the turn"
```

- [ ] **Step 7: Extend the test with the ruling-seat text**

In `plugins/dforge/tests/waiting-text.test.sh`, replace

````text
CODEX="$P/skills/using-dforge/references/codex-tools.md"
````

with

````text
CODEX="$P/skills/using-dforge/references/codex-tools.md"
INLINE="$P/skills/executing-plans/SKILL.md"
````

and replace the last block (the line `printf '\n%d passed, %d failed\n' "$pass" "$fail"` and the line after it, which exits on failure)

````text
printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
````

with

````text
names "the ruling route takes a comma-separated kind list" "$SDD" '`<kind>` is then one comma-separated list, such as'
names "simple kinds route to judge-sonnet-high" "$SDD" '`dforge:judge-sonnet-high` (`reason=simple-kind`) when every kind in the list'
names "the other kinds stay on judge-opus" "$SDD" '`blocked-plan`, `final-residual` and `acceptance-ambiguous` always go to'
names "a mechanical check settles a cannot-verify item" "$SDD" '`Task <N>: Ruling: cannot-verify — settled by task-step check <name> — none`,'
names "a failed check is a fix-loop finding" "$SDD" 'finding for the fix loop, not a cannot-verify item.'
names "inline mode routes the simple kinds" "$INLINE" '`dforge:judge-sonnet-high` when every kind is `cannot-verify` or'
names "inline mode settles by mechanical check" "$INLINE" '`Task <N>: Ruling: cannot-verify — settled by task-step check <name> — none`.'

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
````

Run: `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID -u CLAUDE_CONFIG_DIR timeout 600 bash plugins/dforge/tests/waiting-text.test.sh`
Expected: exit 1, `13 passed, 7 failed`.

- [ ] **Step 8: Update the ruling seat text in both execution skills**

Subagent mode, `plugins/dforge/skills/subagent-driven-development/SKILL.md`. The kind list and the Sonnet kinds, then the mechanical-check settlement:

In `plugins/dforge/skills/subagent-driven-development/SKILL.md`, replace:

````text
`scripts/review-route PLAN_FILE --ruling <kind> [<task> ...]` for the point's
kind and the tasks its items concern, and dispatch the `primary` it prints
with [ruling-prompt.md](references/ruling-prompt.md), expanding its
placeholders. Items of different kinds at one point share one dispatch. On any
exit 2, dispatch `dforge:judge-opus` and say why,
quoting its message. Codex hosts, where `review-route` exits 2, use a native
judge at Astra high or above ([native-codex.md](../../reference/native-codex.md)).
````

with:

````text
`scripts/review-route PLAN_FILE --ruling <kind> [<task> ...]` for the point's
kinds and the tasks its items concern, and dispatch the `primary` it prints
with [ruling-prompt.md](references/ruling-prompt.md), expanding its
placeholders. Items of different kinds at one point share one dispatch, and
`<kind>` is then one comma-separated list, such as
`cannot-verify,executor-empty-diff`. The route prints
`dforge:judge-sonnet-high` (`reason=simple-kind`) when every kind in the list
is `cannot-verify` or `executor-empty-diff` and no task it names is risk 3,
and `dforge:judge-opus` otherwise; `preflight`, `plan-conflict`, `breaker`,
`blocked-plan`, `final-residual` and `acceptance-ambiguous` always go to
`dforge:judge-opus`. On any exit 2, dispatch `dforge:judge-opus` and say why,
quoting its message. Codex hosts, where `review-route` exits 2, use a native
judge at Astra high or above ([native-codex.md](../../reference/native-codex.md)).

**Settled by a mechanical check.** `scripts/task-step review` prints
`check identity:` and `check attribution:` lines for the task's commits. A
reviewer's cannot-verify item that one of those lines answers `clean` (commit
author and committer, or an attribution trailer) goes to no seat; log it as
`Task <N>: Ruling: cannot-verify — settled by task-step check <name> — none`,
with `<name>` `identity` or `attribution`. A check that found something is a
finding for the fix loop, not a cannot-verify item.
````

Inline mode, `plugins/dforge/skills/executing-plans/SKILL.md`:

In `plugins/dforge/skills/executing-plans/SKILL.md`, replace:

````text
`scripts/review-route PLAN_FILE --ruling <kind> [<task> ...]` and dispatch the
`primary` it prints with
[ruling-prompt.md](../subagent-driven-development/references/ruling-prompt.md),
expanding its placeholders. On any exit 2, dispatch
`dforge:judge-opus` and say why, quoting its message - except on a
````

with:

````text
`scripts/review-route PLAN_FILE --ruling <kind> [<task> ...]` and dispatch the
`primary` it prints with
[ruling-prompt.md](../subagent-driven-development/references/ruling-prompt.md),
expanding its placeholders. Items of several kinds at one point share one
dispatch, and `<kind>` is then one comma-separated list; the route prints
`dforge:judge-sonnet-high` when every kind is `cannot-verify` or
`executor-empty-diff` and no task it names is risk 3, and `dforge:judge-opus`
otherwise. A delegated task's cannot-verify item that a `check identity:` or
`check attribution:` line of `scripts/task-step review` answers `clean` goes to
no seat: log
`Task <N>: Ruling: cannot-verify — settled by task-step check <name> — none`.
On any exit 2, dispatch
`dforge:judge-opus` and say why, quoting its message - except on a
````

- [ ] **Step 9: Run the test, the neighbouring suites and the repository validation**

Run, with the Bash tool's `timeout` at 600000 ms:

```bash
for t in waiting-text review-route inline-mode auto-run-skills final-phase process-roles seats project-status turn-end native-routing; do
  printf '%s: ' "$t"
  env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID -u CLAUDE_CONFIG_DIR timeout 600 bash plugins/dforge/tests/$t.test.sh | tail -n 1
done
timeout 120 node scripts/validate-repository.mjs
```

Expected: every suite line ends `0 failed`, `waiting-text` prints `20 passed, 0 failed`, and the validation prints `Repository catalogs, manifests, versions, bundled links and the settings schema are valid.` The existing pins `inline routes the ruling seat` and `SDD routes the ruling seat` still hold, because the new text keeps the command form `scripts/review-route PLAN_FILE --ruling <kind> [<task> ...]`.

- [ ] **Step 10: Commit the ruling seat text**

```bash
git add plugins/dforge/tests/waiting-text.test.sh plugins/dforge/skills/subagent-driven-development/SKILL.md plugins/dforge/skills/executing-plans/SKILL.md
git -c user.name=Darkraise -c user.email=quangtc94@gmail.com commit -m "docs(dforge): route simple rulings to Sonnet"
```

---

### Task 10: Run the loop through task-step and suite-run

**Files:**
- Create: `plugins/dforge/tests/task-step-text.test.sh`
- Modify: `plugins/dforge/reference/delegated-task.md` (§1, §2, §3, §4, and a new section "The steps by hand")
- Modify: `plugins/dforge/skills/subagent-driven-development/SKILL.md` (§Session Budget, §Example Workflow)
- Modify: `plugins/dforge/reference/parallel-waves.md` (§1, §2, §3, §4, §5)
- Modify: `plugins/dforge/reference/final-review.md` (§Fixing what it finds)
- Modify: `plugins/dforge/skills/finishing-a-development-branch/SKILL.md` (Step 1, Step 5's merge block)
- Modify: `plugins/dforge/skills/subagent-driven-development/references/implementer-prompt.md`
- Modify: `evals/tiers/build-case.mjs` (the implementer prompt's placeholders)
- Modify: `plugins/dforge/tests/process-roles.test.sh`, `plugins/dforge/tests/review-route.test.sh` (four pinned lines)
- Unchanged: `plugins/dforge/skills/executing-plans/SKILL.md` — it restates no replaced mechanic (Step 1's last two checks prove it) and reaches `task-step` through `delegated-task.md` §1

**Acceptance:** A16 (the text the demonstration run in Task 11 executes)

**Interfaces:**
- Consumes: Contracts "`scripts/task-step`" (the three subcommands, `--wave`, `--reset`, `--head`, `--base`, `--cwd`, `--covered`, the digest lines `gate:`, `seat:` in all its forms (including `fallback:`, `then:` and the `(review-route exited …)` note), `codex:`, `timeout:`, `check identity:`, `check attribution:`, `re-review: skipped (…)`, `state:`, the state file, the dispatch, review-prompt and rereview-prompt files, the fix message file, exit 2 on a `Host: codex` plan), "Assigned line", "`scripts/suite-run`" (the call form, the `suite: reused pass at <sha7>` line, the digest), and "Re-review template". Task 9 owns the Waiting and Ruling Seat passages: this task does not touch them.
- Produces: the text that makes a session call `task-step start|review|rereview` and `suite-run` in place of the hand-run steps.

**Items:** 2
**Implementer:** dforge:impl-sonnet-high
**Evaluation:** files 2 - spec 0 - coupling 1 - risk 2 = 5

The `task-step` and `suite-run` scripts exist when this task runs (Tasks 4-8). The Codex-host mechanics stay documented in the new section "The steps by hand", because `task-step` exits 2 on a `Host: codex` plan and `codex-tools.md` and `native-codex.md` stay unchanged.

- [ ] **Step 1: Write the failing test**

Create `plugins/dforge/tests/task-step-text.test.sh` with mode 100644:

````bash
#!/usr/bin/env bash
# The delegated task loop, the waves, the final review and finishing call the
# step and suite scripts instead of describing their mechanics. Each call is a
# whole instruction a session follows, so each is pinned by the text that
# carries it.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
P="$HERE/.."
DT="$P/reference/delegated-task.md"
PW="$P/reference/parallel-waves.md"
FR="$P/reference/final-review.md"
FIN="$P/skills/finishing-a-development-branch/SKILL.md"
IP="$P/skills/subagent-driven-development/references/implementer-prompt.md"
SDD="$P/skills/subagent-driven-development/SKILL.md"
INLINE="$P/skills/executing-plans/SKILL.md"

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
names() { # names <label> <file> <text>
  check "$1" "$(grep -qF -- "$3" "$2" 2>/dev/null && echo yes || echo no)" "yes"
}
lacks() { # lacks <label> <file> <text>
  check "$1" "$(grep -qF -- "$3" "$2" 2>/dev/null && echo yes || echo no)" "no"
}

# loop_steps - the delegated loop's text before its by-hand section
loop_steps() { sed '/^## The steps by hand/,$d' "$DT"; }

check "delegated-task.md has the by-hand section" "$(grep -c '^## The steps by hand' "$DT")" "1"

for call in 'task-step start PLAN_FILE N' 'task-step review PLAN_FILE N' 'task-step rereview PLAN_FILE N'; do
  check "the loop steps name $call" "$([ "$(loop_steps | grep -cF -- "$call")" -ge 1 ] && echo yes || echo no)" "yes"
done
for gone in 'scripts/review-package' 'scripts/task-brief PLAN_FILE N' 'Record BASE' 'run `scripts/lens-route'; do
  check "the loop steps no longer carry: $gone" "$(loop_steps | grep -cF -- "$gone")" "0"
done
check "only the cache rule runs date +%s in the loop steps" "$(loop_steps | grep -cF 'date +%s')" "1"
names "the fix message is a file of finding bullets" "$DT" '`<workspace>/task-<N>-fix-<R>.md`'
names "the fix message bullet format" "$DT" 'per open finding, `- <file>: <finding one-liner>`, then a blank line, then'
names "the skip rule needs --covered" "$DT" '`bash <plugin-root>/scripts/task-step rereview PLAN_FILE N` (with `--covered`'
names "a skipped re-review is recorded on the fix-round line" "$DT" 're-review skipped (<n> lines)'
names "the review step names the checks" "$DT" 'lines, each `clean` or the short SHA and what it found'
names "a repeated start keeps the recorded base" "$DT" 'keeps the recorded BASE'
names "the Codex seat line carries the fallback judge" "$DT" 'the judge after `fallback:` as the seat when it'
names "a failed route is read off the seat line" "$DT" '`(review-route exited <N>: …)`'
names "the gate line position is stated" "$DT" 'A `gate:` line right'

names "waves open a task with --wave" "$PW" '`bash <plugin-root>/scripts/task-step start PLAN_FILE N --wave <k>`'
names "waves review against the task ref" "$PW" '`--head <TASK_REF>` to'
names "waves pass the worktree to a Codex review" "$PW" '`--cwd <worktree>`, so that a Codex seat'
names "an overlap rebase passes --base" "$PW" '`task-step rereview PLAN_FILE N --head <TASK_REF> --base <that HEAD>`'
names "waves batch the in-hand cannot-verify items" "$PW" 'of every task whose review is in hand when one task reaches its cannot-verify'
names "the wave base check runs through suite-run" "$PW" '`bash <plugin-root>/scripts/suite-run -- bash -c '"'"'<the check>'"'"'`, in the'
check "the wave integration check runs through suite-run" "$(grep -cF 'scripts/suite-run -- bash -c' "$PW")" "2"
lacks "the wave check output file is gone" "$PW" 'wave-<k>-check.txt'

names "the final review runs suites through suite-run" "$FR" '`bash <plugin-root>/scripts/suite-run -- <command>`'
names "finishing runs the suite through suite-run" "$FIN" '`bash <plugin-root>/scripts/suite-run -- <test command>`, in the background'
names "finishing verifies the merged result through suite-run" "$FIN" 'bash <plugin-root>/scripts/suite-run -- <test command>'
names "implementers run the full suite through suite-run" "$IP" '`bash [PLUGIN_ROOT]/scripts/suite-run -- <the suite command>` and report'
lacks "implementers no longer run the full suite before committing" "$IP" 'full suite once before committing, not after every edit.'

names "the example workflow starts a task with task-step" "$SDD" '[task-step start PLAN_FILE 1:'
names "the example workflow reviews with task-step" "$SDD" '[task-step review PLAN_FILE 1:'
names "the example workflow re-reviews with task-step" "$SDD" '[task-step rereview PLAN_FILE 2:'
lacks "the example workflow no longer hand-runs review-package" "$SDD" 'review-package PLAN_FILE a1b2c3d HEAD'
names "the budget line is on every task-step digest" "$SDD" 'every `scripts/task-step`'
names "the rationalization row names the skip rule" "$SDD" 'Only `task-step rereview --covered` skips one'
lacks "the rationalization row no longer says every round is re-reviewed" "$SDD" 'Every round ends with a scoped re-review.'
names "inline mode hands delegated tasks to delegated-task.md" "$INLINE" '[delegated-task.md](../../reference/delegated-task.md) for this task instead'
check "inline mode restates no hand-run review mechanic" "$(grep -cE 'date \+%s|codex-gate|lens-route' "$INLINE")" "0"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
````

Run: `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID -u CLAUDE_CONFIG_DIR timeout 600 bash plugins/dforge/tests/task-step-text.test.sh`
Expected: exit 1, `2 passed, 38 failed`. The two passes are the checks that `executing-plans/SKILL.md` already hands delegated tasks to `delegated-task.md` and restates no `date +%s`, `codex-gate` or `lens-route`.

- [ ] **Step 2: delegated-task.md §1 — open the task with `task-step start`**

In `plugins/dforge/reference/delegated-task.md`, make these three replacements.

Open the task:

In `plugins/dforge/reference/delegated-task.md`, replace:

````text
## 1. Dispatch the implementer

Record BASE (`git rev-parse HEAD`) before dispatching — the review package,
the fix-round diffs, and the assigned line need it.

**Read the task's `**Executor:**` line first.** A task carrying one runs on
that CLI — follow [executor-lane.md](executor-lane.md)
§Dispatch — and the steps here are its fallback. A task without one takes
these steps directly.
````

with:

````text
## 1. Dispatch the implementer

**Read the task's `**Executor:**` line first.** A task carrying one runs on
that CLI — follow [executor-lane.md](executor-lane.md)
§Dispatch — and the steps here are its fallback. A task without one takes
these steps directly.

**Open the task with one call:**
`bash <plugin-root>/scripts/task-step start PLAN_FILE N` (a batch passes every
task number, `N M …`; a wave task adds `--wave K`). It runs `task-brief`,
records BASE in `<workspace>/task-<N>-step.json`, writes the
assigned line (below), and writes `<workspace>/task-<N>-dispatch.md`:
[implementer-prompt.md](../skills/subagent-driven-development/references/implementer-prompt.md)
with the brief path, the report path and the plugin root filled in. It prints
at most 15 lines: the `subagent_type`, the dispatch file's path, the state it
recorded and the budget line (see the caller's Session Budget section). Every
later step reads that state file, so you never carry a SHA. Calling `start`
again for a task whose state file exists — a task resumed after a restart, a
dispatch repeated — keeps the recorded BASE, round and review head and writes
no second assigned line, so the review still packages every commit made since
the first dispatch; pass `--reset` only to discard the state and start over,
and say why on the ledger. A task with an
`**Executor:**` line prints `executor <id>: follow executor-lane.md
§Dispatch` and writes no dispatch file. Exit 3 means the plan has no such
task; exit 2 on a `Host: codex` plan sends you to *The steps by hand* below.
````

The brief and the report file:

In `plugins/dforge/reference/delegated-task.md`, replace:

````text
- **Task brief:** run `scripts/task-brief PLAN_FILE N`
  (see using-dforge §Session Budget) — it extracts the task's full text
  to a uniquely named file and prints `wrote <path>: <N> lines`, then the
  budget line (see the caller's Session Budget section). Read the path out of the first line; do
  not pipe the output into a prompt as if it were a filename. Compose the
  dispatch so the brief stays the single source of
  requirements. Your dispatch should contain: (1) one line on where this
  task fits in the project; (2) the brief path, introduced as "read this
  first — it is your requirements, with the exact values to use verbatim,
  and it ends with the plan's Global Constraints and Contracts";
  (3) interfaces and decisions from earlier tasks that the brief cannot
  know; (4) the ruling-seat verdicts in the ledger that bear on this task,
  copied verbatim (an ambiguity you notice in the brief goes to the seat as a
  `plan-conflict` item before you dispatch); (5) the report-file
  path and report contract. Exact values (numbers, magic strings, signatures,
  test cases) appear only in the brief. Never make a subagent read the whole
  plan file. A brief whose task the seat split into `#### Part` units is
  dispatched one part at a time, in order, the dispatch naming the part;
  the assigned line carries `; part <X>`.
- **Report file:** name the implementer's report file after the brief
  (brief `…/task-N-brief.md` → report `…/task-N-report.md`) and put it in
  the dispatch prompt. The implementer writes the full report there and
  returns only status, commits, a one-line test summary, and concerns.
````

with:

````text
- **Task brief:** `task-step start` extracted it to
  `<workspace>/task-<N>-brief.md` (see using-dforge §Session Budget). The
  brief stays the single source of requirements: the dispatch file tells the
  implementer to read it first, with the exact values to use verbatim, and it
  ends with the plan's Global Constraints and Contracts. Your Agent prompt
  holds only what the dispatch file cannot know: (1) one line on where this
  task fits in the project; (2) "your complete instructions are in
  `<dispatch file>`: read it first and follow it"; (3) interfaces and
  decisions from earlier tasks that the brief cannot know; (4) the
  ruling-seat verdicts in the ledger that bear on this task, copied verbatim
  (an ambiguity you notice in the brief goes to the seat as a `plan-conflict`
  item before you dispatch). Exact values (numbers, magic strings,
  signatures, test cases) appear only in the brief. Never make a subagent
  read the whole plan file. A brief whose task the seat split into
  `#### Part` units is dispatched one part at a time, in order, the prompt
  naming the part; its assigned line carries `; part <X>`.
- **Report file:** the dispatch file names it after the brief (brief
  `…/task-N-brief.md` → report `…/task-N-report.md`). The implementer writes
  the full report there and returns only status, commits, a one-line test
  summary, and concerns.
````

The dispatch and the assigned line:

In `plugins/dforge/reference/delegated-task.md`, replace:

````text
- Dispatch with the agent as `subagent_type` and no `model` or `effort` argument, using
  [implementer-prompt.md](../skills/subagent-driven-development/references/implementer-prompt.md). Never dispatch a
  `fork` implementer: it would inherit your whole context.
- Record the implementer's agent identity from the dispatch result — fix
  rounds 1-3 may resume it — and write the assigned line:
  `Task <N>: implementer <agent> (assigned; base <sha7>)`.
````

with:

````text
- Dispatch the printed `subagent_type` with no `model` or `effort` argument
  and the prompt above. Never dispatch a `fork` implementer: it would inherit
  your whole context.
- Record the implementer's agent identity from the dispatch result — fix
  rounds 1-3 may resume it. `start` already wrote
  `Task <N>: implementer <agent> (assigned; base <sha7>)`, ending
  `; wave <k>)` for a wave task. When what you dispatch differs from that
  line, or needs a note it cannot know — an agent scored at dispatch, a
  substitute for an unavailable model, a reserve tier, a `#### Part` — append
  a new assigned line for it with the note (`; scored at dispatch`,
  `; reserve tier`, `; part <X>`), as an escalation does: the last assigned
  line decides.
````

- [ ] **Step 3: delegated-task.md §2 — the DONE status**

In `plugins/dforge/reference/delegated-task.md`, replace:

````text
**DONE:** Generate the review package and dispatch the task reviewer (step 3).
Run `date +%s` in the same Bash call as `review-package` and keep the value as
`t0` — the cache rule in step 4 needs it.
````

with:

````text
**DONE:** Review the task (step 3). `task-step review` packages the diff and
records `t0`, the time the cache rule in step 4 needs.
````

- [ ] **Step 4: delegated-task.md §3 — review the task with `task-step review`**

The package, seat, lens and reviewer-input bullets:

In `plugins/dforge/reference/delegated-task.md`, replace:

````text
- Hand the reviewer its diff as a file: run
  `scripts/review-package PLAN_FILE BASE HEAD`
  (see using-dforge §Session Budget), and pass the reviewer the
  file path it prints (or, without bash: `git log --oneline`, `git diff --stat`,
  and `git diff -U10` for the range, redirected to one uniquely named
  file). The output never enters your own context. Use the BASE you recorded
  before dispatching the implementer — never `HEAD~1`, which silently
  truncates multi-commit tasks. Never dispatch a task reviewer without a diff
  file.
- **The seat:** run `scripts/codex-gate` (say its line aloud when it ends
  `source=probe`; add `--refresh` when Codex may have come back since an
  earlier off answer, such as after a login, because an off answer is kept for
  the session), then `scripts/review-route PLAN_FILE --task <N>` (all of a
  batch's task numbers for a batch), and review with the `primary` it prints.
  A judge seat gets [task-reviewer-prompt.md](../skills/subagent-driven-development/references/task-reviewer-prompt.md)
  with `[PLUGIN_ROOT]` expanded to this plugin's resolved directory; a Codex
  seat is run as below. On `reason=codex-off` the review surface is off for
  this session: the `primary` is a judge, no Codex seat runs, and the seat
  clause records `(codex off — <reason>)` with the gate line's `reason`
  (`untrusted` when it printed `usable=true`). If `review-route` exits 2,
  review with `dforge:judge-opus` and say why, quoting its message.
  Codex hosts are the exception: `review-route --task` exits 2 on every `Host: codex`
  plan, and the seat is a native judge at Astra high or above
  ([native-codex.md](native-codex.md)).
- **Lenses:** run `scripts/lens-route PLAN_FILE --task <N>`. For each `lens`
  line it prints, add its `criteria=` path to the judge seat's `[LENS_FILES]`;
  with none, delete that section of the prompt. A Codex seat gets no lens
  files: on a risk-3 task the Claude judge beside it reads them. On a
  `Host: codex` plan `lens-route` exits 2; choose the lenses as
  [native-codex.md](native-codex.md) says.
- **Reviewer inputs:** the brief file (it ends with the plan's Global
  Constraints and Contracts — the reviewer's attention lens), the report
  file, and the review package. Never tell the reviewer which lane produced
  the diff: a judge that knows the author scores the author.
````

with:

````text
- **One call does the plumbing:**
  `bash <plugin-root>/scripts/task-step review PLAN_FILE N` (all of a batch's
  task numbers for a batch; a wave task adds `--head <task ref>` and
  `--cwd <worktree>`, see [parallel-waves.md](parallel-waves.md)). It packages the diff from the base
  `start` recorded to HEAD — never `HEAD~1`, which silently truncates
  multi-commit tasks — and records the review head and `t0`. It runs
  `scripts/codex-gate`, `scripts/review-route PLAN_FILE --task <N>` and
  `scripts/lens-route PLAN_FILE --task <N>`, and writes
  `<workspace>/task-<N>-review-prompt.md`:
  [task-reviewer-prompt.md](../skills/subagent-driven-development/references/task-reviewer-prompt.md)
  with every placeholder filled in, the diff file, the plugin directory and
  each lens's `criteria=` path among them (a task with no lens has no lens
  section). It runs the mechanical checks below, and for a Codex seat also
  writes the Codex prompt. It prints at most 15 lines: the seat and its prompt
  file, for a Codex seat the runner command and its timeout, the check lines,
  the state it recorded and the budget line. The diff never enters your own
  context, and a reviewer is never dispatched without it.
- **The seat:** dispatch the `seat:` line's `subagent_type`, with no `model`
  or `effort` argument, and the prompt "your complete instructions are in
  `<prompt file>`: read it first and follow it". A Codex seat's line names
  both prompt files, `seat: codex:light prompt: <Codex prompt> fallback:
  <judge> prompt: <judge prompt>` or `seat: codex:heavy+judge-opus prompt:
  <Codex prompt> then: dforge:judge-opus prompt: <judge prompt>`: run the
  Codex seat as below, with the judge after `fallback:` as the seat when it
  fails and the judge after `then:` as the risk 3 second pass. Both judge
  prompts are already written, so you never run `review-route` again for
  them. Run `scripts/codex-gate --refresh` before `task-step review` when
  Codex may have come back since an earlier off answer, such as after a
  login, because an off answer is kept for the session. A `gate:` line right
  after the digest's first line carries the gate's answer when the route was
  `reason=codex-off` or the gate answered `source=probe`; say it aloud when
  it ends `source=probe`. A task without an `**Executor:**` line
  whose `seat:` line names a judge was routed with `reason=codex-off`: the
  review surface is off for this session, no Codex seat runs, and the seat
  clause records `(codex off — <reason>)` with the `reason` on the `gate:`
  line (`untrusted` when it printed `usable=true`). When the `seat:` line
  ends `(review-route exited <N>: …)`, `review-route` failed but
  `task-step review` still wrote the complete judge prompt: dispatch the
  `dforge:judge-opus` seat it names as printed, and say why, quoting that
  note. If `task-step review` itself exits 2 (a `lens-route` failure) it
  wrote nothing: take *The steps by hand*.
  Codex hosts are the exception: `review-route --task` exits 2 on every `Host: codex`
  plan, and the seat is a native judge at Astra high or above
  ([native-codex.md](native-codex.md)).
- **Lenses:** the prompt file already carries each `lens-route` line's
  `criteria=` path. A Codex seat gets no lens files: on a risk-3 task the
  Claude judge beside it reads them. On a `Host: codex` plan `lens-route`
  exits 2; choose the lenses as [native-codex.md](native-codex.md) says.
- **Reviewer inputs:** the brief file (it ends with the plan's Global
  Constraints and Contracts — the reviewer's attention lens), the report
  file, and the diff file, all named in the prompt file. Never tell the
  reviewer which lane produced the diff: a judge that knows the author scores
  the author.
````

The mechanical checks and the Codex seat:

In `plugins/dforge/reference/delegated-task.md`, replace:

````text
**Codex seats.** Write the task-reviewer prompt for Codex as
[executor-lane.md](executor-lane.md) §Codex task review
seats describes, to `<workspace>/task-<N>-review-codex-prompt.md`, and run it
as a background Bash call with `timeout` = (row bound + 120) × 1000 ms: 2520000
for `--tier light`, 5520000 for `--tier heavy`:
````

with:

````text
**Mechanical checks.** `task-step review` also checks the commits from the
base to the review head and prints `check identity:` and `check attribution:`
lines, each `clean` or the short SHA and what it found: an author or committer
that differs from `git config user.name` and `user.email`, or a
`Co-Authored-By:` or `Claude-Session:` trailer, or a line beginning
`Generated with`. A check that
found something is a finding for the fix loop. A reviewer's cannot-verify item
that a `clean` line answers is settled without a seat (subagent-driven-development,
The Ruling Seat).

**Codex seats.** `task-step review` wrote the task-reviewer prompt for Codex,
as [executor-lane.md](executor-lane.md) §Codex task review
seats describes, to `<workspace>/task-<N>-review-codex-prompt.md`, and printed
the runner command and its `timeout` (the command's `--cwd` is your checkout's
top level, or the `--cwd DIR` you passed to `task-step review`). Run that
command as a background Bash
call with `timeout` = (row bound + 120) × 1000 ms: 2520000
for `--tier light`, 5520000 for `--tier heavy`; its shape is:
````

The Codex fallback:

In `plugins/dforge/reference/delegated-task.md`, replace:

````text
`TIMEOUT or FAILED` is a seat that did not: dispatch the route's `fallback`
seat with the ordinary prompt, say so with the runner's reason, and
never re-dispatch the Codex seat.
````

with:

````text
`TIMEOUT or FAILED` is a seat that did not: dispatch the route's `fallback`
seat (`scripts/review-route PLAN_FILE --task <N>` prints it) with the judge
prompt file, say so with the runner's reason, and
never re-dispatch the Codex seat.
````

The risk 3 judge:

In `plugins/dforge/reference/delegated-task.md`, replace:

````text
first, then dispatch `dforge:judge-opus` with the task-reviewer prompt
and its Second Pass section, `[CODEX_REVIEW_FILE]` set to the Codex seat's
`--out` path. The task's verdicts and scores are the judge's.
````

with:

````text
first, then dispatch `dforge:judge-opus` with the judge prompt file, whose
Second Pass section already names the Codex seat's `--out` path. The task's
verdicts and scores are the judge's.
````

In `plugins/dforge/reference/delegated-task.md`, replace:

````text
re-dispatch it. If the Codex seat produced nothing, dispatch the judge without
the Second Pass section and say so. This replaces
````

with:

````text
re-dispatch it. If the Codex seat produced nothing, dispatch the judge with the
same prompt file and one added line, "No Codex review file exists: skip the
Second Pass section", and say so. This replaces
````

The cannot-verify items:

In `plugins/dforge/reference/delegated-task.md`, replace:

````text
the task completes: the seat holds the plan and cross-task context the
reviewer lacks. A CONFIRMED-GAP is a failed spec review — it enters the fix
loop with the other findings.
````

with:

````text
the task completes, unless a mechanical check settles it: the seat holds
the plan and cross-task context the reviewer lacks. A CONFIRMED-GAP is a
failed spec review — it enters the fix loop with the other findings.
````

- [ ] **Step 5: delegated-task.md §4 — the fix message and `task-step rereview`**

The cache rule's `t0`:

In `plugins/dforge/reference/delegated-task.md`, replace:

````text
`t1` is `date +%s` from a dedicated Bash call immediately before you decide.
The context figure
````

with:

````text
`t0` is the one on the latest `state:` line a `task-step` digest printed; `t1`
is `date +%s` from a dedicated Bash call immediately before you decide.
The context figure
````

The progress rule after a skip:

In `plugins/dforge/reference/delegated-task.md`, replace:

````text
**Progress.** The re-reviewer returns `**Progress:** <1-20>`. If round N's
reading is less than or equal to round N-1's, escalate at the start of the next
round rather than waiting for round 4. Never escalate before round 3, and never
later than round 4. Record the reading on the fix-round line
(`progress 11 -> 9`).
````

with:

````text
**Progress.** The re-reviewer returns `**Progress:** <1-20>`. If round N's
reading is less than or equal to round N-1's, escalate at the start of the next
round rather than waiting for round 4. Never escalate before round 3, and never
later than round 4. Record the reading on the fix-round line
(`progress 11 -> 9`). A round whose re-review was skipped has no reading: the
next reading is compared with the last round that returned one.
````

The fix message, the scoped re-review and the skip rule:

In `plugins/dforge/reference/delegated-task.md`, replace:

````text
output; dispatch the re-review once all three are present. Name the
covering test files in the fix message — a one-line fix does not need the
whole suite.

**The re-review is scoped.** Run `scripts/review-package PLAN_FILE FIX_BASE HEAD`
where FIX_BASE is the head the previous review saw, and dispatch
[re-review-prompt.md](../skills/subagent-driven-development/references/re-review-prompt.md) with the findings list, the
brief, the report file, and the printed diff path. The re-reviewer verdicts
each finding ADDRESSED or NOT ADDRESSED, flags new breakage in the fix
diff only, and returns the progress reading. New Critical/Important breakage in
the fix diff joins the open findings list. Out-of-scope observations go to the
ledger as deferred minors — they never extend the loop. Run `date +%s` with that
`review-package` call too: it is the next round's `t0`.
````

with:

````text
output; dispatch the re-review once all three are present. Name the
covering test files in the fix message — a one-line fix does not need the
whole suite.

**The fix message** is the file `<workspace>/task-<N>-fix-<R>.md`, `R` being
the round you are starting (1 for the first). Its first lines are one bullet
per open finding, `- <file>: <finding one-liner>`, then a blank line, then
what the implementer needs: the finding's detail, the ruling's smallest fix,
the covering test files. Send the implementer, resumed or fresh, the file's
path rather than its text. `task-step rereview` reads the bullets for the
findings list and the skip rule, so write the file before you call it.

**The re-review is scoped.** Run
`bash <plugin-root>/scripts/task-step rereview PLAN_FILE N` (with `--covered`
under the skip rule below). It packages the fix diff from the review head it
recorded last to HEAD, records the new review head, adds one to the
recorded round, and writes
`<workspace>/task-<N>-rereview-<R>-prompt.md`:
[re-review-prompt.md](../skills/subagent-driven-development/references/re-review-prompt.md)
with the findings from your fix message, the brief, the report file and the
diff path filled in. It prints the seat and that file; dispatch the seat with
the prompt "your complete instructions are in `<prompt file>`: read it first
and follow it". It prints `dforge:judge-sonnet-high`; for a subtle
concurrency fix dispatch `dforge:judge-opus` with the same file and say so.
The re-reviewer verdicts each finding ADDRESSED or NOT ADDRESSED, flags new
breakage in the fix diff only, and returns the progress reading. New
Critical/Important breakage in the fix diff joins the open findings list.
Out-of-scope observations go to the ledger as deferred minors — they never
extend the loop.

**The skip rule.** Pass `--covered` only after confirming that the fix report
names the covering tests, the command and passing output. With it,
`rereview` skips the re-review when exactly one finding is open, the fix
changes at most 3 lines (added plus deleted, test files included) and touches
that finding's file, and the task is not risk 3. It prints
`re-review: skipped (<n> changed lines, 1 finding, <file>)` and writes no
prompt: count the finding addressed, dispatch no seat, and write the fix-round
line with `re-review skipped (<n> lines)` in place of the progress reading. A
skip never triggers escalation. Without `--covered`, or in any other case, the
re-review runs.
````

The fix-round ledger line:

In `plugins/dforge/reference/delegated-task.md`, replace:

````text
`Task <N>: fix round <R>/5 (<X> addressed, <Y> open — <finding one-liners>; commits <a7>..<b7>; progress <p> -> <q>; resumed | fresh (<why>) | escalated <old> -> <new> | HANDBACK to <agent>)`
````

with:

````text
`Task <N>: fix round <R>/5 (<X> addressed, <Y> open — <finding one-liners>; commits <a7>..<b7>; progress <p> -> <q> | re-review skipped (<n> lines); resumed | fresh (<why>) | escalated <old> -> <new> | HANDBACK to <agent>)`
````

- [ ] **Step 6: delegated-task.md — keep the Codex-host mechanics in one section**

In `plugins/dforge/reference/delegated-task.md`, replace:

````text
## Recovery

For a task whose last ledger line
````

with:

````text
## The steps by hand

`task-step` exits 2 on a `Host: codex` plan, and `task-step review` exits 2,
writing nothing, when `lens-route` does. Then run the mechanics yourself:

- **§1.** Record BASE (`git rev-parse HEAD`) before dispatching. Run
  `scripts/task-brief PLAN_FILE N` (see using-dforge §Session Budget): it
  prints `wrote <path>: <N> lines`, then the budget line; read the path out of
  the first line and never pipe the output into a prompt as if it were a
  filename. Dispatch with
  [implementer-prompt.md](../skills/subagent-driven-development/references/implementer-prompt.md),
  its placeholders filled in, the brief path introduced as "read this first —
  it is your requirements, with the exact values to use verbatim, and it ends
  with the plan's Global Constraints and Contracts" and the report-file path
  named after the brief. Write the assigned line
  `Task <N>: implementer <agent> (assigned; base <sha7>)`.
- **§3.** Run `scripts/review-package PLAN_FILE BASE HEAD` (or, without bash:
  `git log --oneline`, `git diff --stat` and `git diff -U10` for the range,
  redirected to one uniquely named file) and pass the reviewer the path it
  prints; run `date +%s` in the same Bash call and keep the value as `t0`. Fill
  [task-reviewer-prompt.md](../skills/subagent-driven-development/references/task-reviewer-prompt.md)
  yourself, `[PLUGIN_ROOT]` expanded to this plugin's resolved directory and
  `[LENS_FILES]` set to each `criteria=` path `scripts/lens-route PLAN_FILE --task <N>`
  prints (with none, delete that section). Check the commits' identity and
  attribution yourself, as the mechanical checks above describe.
- **§4.** Run `scripts/review-package PLAN_FILE FIX_BASE HEAD` where FIX_BASE
  is the head the previous review saw, with `date +%s` in the same call as the
  next round's `t0`, and fill the re-review prompt's placeholders yourself.

## Recovery

For a task whose last ledger line
````

- [ ] **Step 7: subagent-driven-development — the budget sentence and the Example Workflow**

In `plugins/dforge/skills/subagent-driven-development/SKILL.md`:

In `plugins/dforge/skills/subagent-driven-development/SKILL.md`, replace:

````text
`scripts/task-brief` and `scripts/review-package` end their output with the
budget line
````

with:

````text
`scripts/task-brief`, `scripts/review-package` and every `scripts/task-step`
digest end their output with the budget line
````

In `plugins/dforge/skills/subagent-driven-development/SKILL.md`, replace:

````text
[BASE=a1b2c3d; run task-brief for Task 1; dispatch impl-sonnet-low, no model or effort argument]
[Ledger: Task 1: implementer impl-sonnet-low (assigned; base a1b2c3d)]

Implementer: DONE — 5/5 passing; report file written; assumptions: user-level install (brief silent)

[date +%s; review-package PLAN_FILE a1b2c3d HEAD; review-route --task 1 prints judge-sonnet-high; dispatch it with the printed path]
Judge: Spec ✅. Task quality: Approved.
````

with:

````text
[task-step start PLAN_FILE 1: brief written, assigned line Task 1: implementer impl-sonnet-low (assigned; base a1b2c3d), dispatch file task-1-dispatch.md; dispatch impl-sonnet-low with that path, no model or effort argument]
[Only waiting remains: end the turn; the implementer's completion starts the next one]

Implementer: DONE — 5/5 passing; report file written; assumptions: user-level install (brief silent)

[task-step review PLAN_FILE 1: seat judge-sonnet-high, prompt task-1-review-prompt.md, check identity: clean, check attribution: clean; dispatch the seat with the prompt path]
Judge: Spec ✅. Task quality: Approved.
````

In `plugins/dforge/skills/subagent-driven-development/SKILL.md`, replace:

````text
[BASE=d4e5f6a; dispatch impl-sonnet-medium]
Implementer: DONE — 8/8 passing

[date +%s → t0; review-package; review-route --task 2; dispatch judge-sonnet-high]
Judge: Spec ❌ — missing progress reporting. Important: magic number (100).
  Verification Scores: spec 7 / scope 17 / verification 15 / quality 12

[date +%s → t1; t1 − t0 = 140s, so resume the implementer with both findings]
Implementer: Added progress reporting, extracted PROGRESS_INTERVAL. 10/10 passing.

[date +%s; review-package PLAN_FILE FIX_BASE HEAD; dispatch scoped re-review]
Re-reviewer: both ADDRESSED. New breakage: none. Progress: 18
````

with:

````text
[task-step start PLAN_FILE 2; dispatch impl-sonnet-medium with the dispatch file's path]
Implementer: DONE — 8/8 passing

[task-step review PLAN_FILE 2: state line shows t0; dispatch judge-sonnet-high with the prompt path]
Judge: Spec ❌ — missing progress reporting. Important: magic number (100).
  Verification Scores: spec 7 / scope 17 / verification 15 / quality 12

[date +%s → t1; t1 − t0 = 140s, so resume the implementer with the path of task-2-fix-1.md, whose two bullets name both findings]
Implementer: Added progress reporting, extracted PROGRESS_INTERVAL. 10/10 passing.

[task-step rereview PLAN_FILE 2: two findings are open, so no skip; dispatch the printed seat with task-2-rereview-1-prompt.md]
Re-reviewer: both ADDRESSED. New breakage: none. Progress: 18
````

In `plugins/dforge/skills/subagent-driven-development/SKILL.md`, replace the Common Rationalizations row that this task's skip rule contradicts:

````text
| "The fix was small, skip the re-review" | Unreviewed fixes are how regressions land. Every round ends with a scoped re-review. |
````

with:

````text
| "The fix was small, skip the re-review" | Unreviewed fixes are how regressions land. Only `task-step rereview --covered` skips one, and only for exactly one open finding, a fix of at most 3 changed lines touching that finding's file, a task below risk 3 and a fix report that names a passing covering test. Every other round ends with a scoped re-review. |
````

In `plugins/dforge/skills/subagent-driven-development/SKILL.md`, replace:

````text
[ONE fix dispatch; one scoped re-review; clean]
````

with:

````text
[ONE fix dispatch, told to run the full suite through suite-run after its last commit; one scoped re-review; clean]
````

In `plugins/dforge/skills/subagent-driven-development/SKILL.md`, replace:

````text
[Skill tool: dforge:finishing-a-development-branch, in this turn — gates, Rulings I made, the three-option menu last]
````

with:

````text
[Skill tool: dforge:finishing-a-development-branch, in this turn — suite-run reuses the fix wave's pass at the unchanged HEAD; gates, Rulings I made, the three-option menu last]
````

- [ ] **Step 8: parallel-waves.md — `--wave`, `--head`, `--base`, the in-hand batch and `suite-run`**

In `plugins/dforge/reference/parallel-waves.md`:

In `plugins/dforge/reference/parallel-waves.md`, replace:

````text
2. **Prove the base.** Unless the last `Wave <j>: integrated` line names the
   current `HEAD`, run the plan's `**Worktree setup:**` (when it is not `none`)
   and `**Integration check:**` in the checkout, bounded like any long command.
   A failure here is not this wave's: serialize the wave and record the
   output's summary in the Ruling, so the next wave's check is not blamed on
   it.
````

with:

````text
2. **Prove the base.** Unless the last `Wave <j>: integrated` line names the
   current `HEAD`, run the plan's `**Worktree setup:**` (when it is not `none`)
   in the checkout, then its `**Integration check:**` through
   `bash <plugin-root>/scripts/suite-run -- bash -c '<the check>'`, in the
   background when it can outrun Bash's ten-minute cap. A failure here is not
   this wave's: serialize the wave and record the digest's summary in the
   Ruling, so the next wave's check is not blamed on it.
````

In `plugins/dforge/reference/parallel-waves.md`, replace:

````text
Dispatch up to `c` tasks of the wave in one message. Each is
[delegated-task.md](delegated-task.md) §1 with three differences:
````

with:

````text
Dispatch up to `c` tasks of the wave in one message. Each is
[delegated-task.md](delegated-task.md) §1, opened with
`bash <plugin-root>/scripts/task-step start PLAN_FILE N --wave <k>`, with three
differences:
````

In `plugins/dforge/reference/parallel-waves.md`, replace:

````text
Write each assigned line, ending `; wave <k>`, in the message that dispatches
it. While tasks run, keep working as subagent-driven-development's Waiting on
dispatched subagents says; every report that arrives is handled at once.
````

with:

````text
`task-step start --wave <k>` writes each assigned line, ending `; wave <k>`, and
its dispatch file; call it for every task in the message that dispatches them.
The dispatch file does not hold the section above: add the filled Parallel
workspace section to each Agent prompt, after the line naming the dispatch
file. While tasks run, keep working as subagent-driven-development's Waiting on
dispatched subagents says; every report that arrives is handled at once.
````

In `plugins/dforge/reference/parallel-waves.md`, replace:

````text
- **HEAD is the task ref.** The review package is
  `scripts/review-package PLAN_FILE <base> <TASK_REF>`; a scoped re-review's
  FIX_BASE is the task ref's commit the previous review saw. Both run from
  your checkout: the worktrees share its objects.
````

with:

````text
- **HEAD is the task ref.** Pass `--head <TASK_REF>` to
  `task-step review PLAN_FILE N` and to `task-step rereview PLAN_FILE N`: the
  review package then runs from the recorded base to the task ref, and a
  scoped re-review's FIX_BASE is the task ref's commit the previous review saw,
  which `task-step` recorded. Both run from your checkout: the worktrees share
  its objects. Give `review` also `--cwd <worktree>`, so that a Codex seat's
  printed runner command runs in the task's worktree and not in your
  checkout.
````

In `plugins/dforge/reference/parallel-waves.md`, replace:

````text
Every finding, ruling and verdict is the task's own, exactly as in sequential
mode. Rulings for several tasks that arise together share one ruling-seat
dispatch, as they always do at one decision point.
````

with:

````text
Every finding, ruling and verdict is the task's own, exactly as in sequential
mode. Rulings for several tasks that arise together share one ruling-seat
dispatch, as they always do at one decision point. The `cannot-verify` items
of every task whose review is in hand when one task reaches its cannot-verify
point go to one dispatch, written with `<kind>` `cannot-verify` and every
such task number. A task not yet reviewed, or not yet dispatched, never holds
that dispatch back: its items wait for its own decision point.
````

In `plugins/dforge/reference/parallel-waves.md`, replace:

````text
  rounds. The rebased task's base is now that `HEAD`: the re-review's
  FIX_BASE, the `wave merge` argument and the complete line's range all start
  there, because the task ref no longer descends from what the last review
  saw.
````

with:

````text
  rounds. The rebased task's base is now that `HEAD`: the re-review's
  FIX_BASE, the `wave merge` argument and the complete line's range all start
  there, because the task ref no longer descends from what the last review
  saw. Pass that `HEAD` to the scoped re-review as
  `task-step rereview PLAN_FILE N --head <TASK_REF> --base <that HEAD>`; the
  state line it prints then shows it as the task's base, which is the
  `wave merge` argument.
````

In `plugins/dforge/reference/parallel-waves.md`, replace:

````text
2. Run the plan's `**Worktree setup:**` (when it is not `none`) and its
   `**Integration check:**` in the checkout, bounded like any long command,
   with the output written to `<workspace>/wave-<k>-check.txt`.
3. **Pass:** log `Wave <k>: integrated (head <sha7>; <command> → pass)` and
   go to the next wave.
4. **Fail:** log `Wave <k>: check failed — <command> → <summary>` and run the
   wave's fix loop: delegated-task.md §4 with the check output as its one
````

with:

````text
2. Run the plan's `**Worktree setup:**` (when it is not `none`) in the
   checkout, then its `**Integration check:**` through
   `bash <plugin-root>/scripts/suite-run -- bash -c '<the check>'`, in the
   background when it can outrun Bash's ten-minute cap. The digest and the log
   path it prints replace a hand-made output file.
3. **Pass:** log `Wave <k>: integrated (head <sha7>; <command> → pass)` and
   go to the next wave.
4. **Fail:** log `Wave <k>: check failed — <command> → <summary>` and run the
   wave's fix loop: delegated-task.md §4 with the digest and its log as its one
````

In `plugins/dforge/reference/parallel-waves.md`, replace:

````text
fix." Each round's scoped re-review covers the fix diff; you re-run the
   check after it, and the round passes only when the check does.
````

with:

````text
fix." Each round's scoped re-review covers the fix diff; you re-run the
   check through `suite-run` after it, and the round passes only when the
   check does.
````

- [ ] **Step 9: final-review.md and finishing — suites through `suite-run`**

In `plugins/dforge/reference/final-review.md`:

In `plugins/dforge/reference/final-review.md`, replace:

````text
There is no second fix wave. Residual load-bearing findings surface to your
human partner when dforge:finishing-a-development-branch presents the options.
````

with:

````text
**Suites.** Any test or validation suite you run in the final review — the
check after the fix wave, or the project's full suite in inline mode — goes
through `bash <plugin-root>/scripts/suite-run -- <command>`, which records the
HEAD it ran at and prints a digest in place of the output. Tell the fix
subagent to run the project's full suite the same way after its last commit,
on a clean tree: finishing's verification then reuses that pass at the
unchanged HEAD instead of running the suite again. A fix wave whose commits
moved HEAD past that run is not reused.

There is no second fix wave. Residual load-bearing findings surface to your
human partner when dforge:finishing-a-development-branch presents the options.
````

In `plugins/dforge/skills/finishing-a-development-branch/SKILL.md`, Step 1:

In `plugins/dforge/skills/finishing-a-development-branch/SKILL.md`, replace:

````text
though Step 3 has not established one yet. Otherwise run the project's full test
suite (`npm test` / `cargo test` / `pytest` / `go test ./...`).

**If tests fail**, report the failures and stop — the menu comes after a
green suite:

```
Tests failing (<N> failures). Must fix before completing:

[Show failures]
````

with:

````text
though Step 3 has not established one yet. Otherwise run the project's full test
suite (`npm test` / `cargo test` / `pytest` / `go test ./...`) through
`bash <plugin-root>/scripts/suite-run -- <test command>`, in the background
when it can outrun Bash's ten-minute cap. It prints a digest, never the whole
output, and reuses a recorded pass (`suite: reused pass at <sha7>`) only at
the same HEAD, with a clean tree then and now, for the same command: a fix
wave's passing run at this HEAD stands, and any other tree runs the suite.
Its exit code is the verdict.

**If tests fail**, report the failures and stop — the menu comes after a
green suite:

```
Tests failing (<N> failures). Must fix before completing:

[Show the digest's failing lines]
````

and Step 5's merge block:

In `plugins/dforge/skills/finishing-a-development-branch/SKILL.md`, replace:

````text
# Verify the merged result: gates when the project declares a manifest
# (dforge:running-gates, with the sha printed above as its base), otherwise
# the full test suite. Gates that passed on the branch say nothing about the
# merged tree.
<test command>
```
````

with:

````text
# Verify the merged result: gates when the project declares a manifest
# (dforge:running-gates, with the sha printed above as its base), otherwise
# the full test suite through suite-run. Gates that passed on the branch say
# nothing about the merged tree, and the merged HEAD is new, so suite-run runs.
bash <plugin-root>/scripts/suite-run -- <test command>
```
````

- [ ] **Step 10: implementer-prompt.md — targeted tests before committing, the full suite through `suite-run` after**

In `plugins/dforge/skills/subagent-driven-development/references/implementer-prompt.md`:

In `plugins/dforge/skills/subagent-driven-development/references/implementer-prompt.md`, replace:

````text
    While iterating, run the focused test for what you're changing; run the
    full suite once before committing, not after every edit.
````

with:

````text
    While iterating, run the focused test for what you're changing before
    each commit, not the full suite after every edit. After your final
    commit, on a clean tree, run the project's full suite once through
    `bash [PLUGIN_ROOT]/scripts/suite-run -- <the suite command>` and report
    its digest in your report's test results: it records the HEAD it ran at,
    so the controller does not run the suite again on a HEAD you already
    covered.
````

Then run `grep -c '^- `\[PLUGIN_ROOT\]`' plugins/dforge/skills/subagent-driven-development/references/implementer-prompt.md`. When it prints `0` (Task 5 added no such bullet), make this replacement in the same file; when it prints `1`, skip it:

In `plugins/dforge/skills/subagent-driven-development/references/implementer-prompt.md`, replace:

````text
- `[IMPLEMENTER]` — the task's `**Implementer:**` agent (for example
  `dforge:impl-sonnet-medium`), passed as `subagent_type` with no
  `model` argument: the agent file pins both model and effort
````

with:

````text
- `[IMPLEMENTER]` — the task's `**Implementer:**` agent (for example
  `dforge:impl-sonnet-medium`), passed as `subagent_type` with no
  `model` argument: the agent file pins both model and effort
- `[PLUGIN_ROOT]` — the resolved dforge plugin directory; expand it before
  sending, so the `suite-run` call above names a real path
````

The eval harness fills every placeholder of the implementer template (`evals/tiers/lib/prompt.mjs` `fill`), so the new one needs a value there. Run `sed -n '/fill(template(IMPLEMENTER)/,/});/p' evals/tiers/build-case.mjs | grep -c PLUGIN_ROOT`. When it prints `0`, make this replacement in `evals/tiers/build-case.mjs`; when it prints `1`, skip it:

In `evals/tiers/build-case.mjs`, replace:

````text
    '[REPORT_FILE]': join(work, SCRATCH, `task-${c.task}-report.md`),
  });
  const info = { id: c.id, kind: 'impl',
````

with:

````text
    '[REPORT_FILE]': join(work, SCRATCH, `task-${c.task}-report.md`),
    '[PLUGIN_ROOT]': PLUGIN,
  });
  const info = { id: c.id, kind: 'impl',
````

- [ ] **Step 11: Update the four pinned lines the rewrite moves**

In `plugins/dforge/tests/process-roles.test.sh`:

In `plugins/dforge/tests/process-roles.test.sh`, replace:

````text
names "task review: lens-route per task" "$P/reference/delegated-task.md" 'run `scripts/lens-route PLAN_FILE --task <N>`'
````

with:

````text
names "task review: lens-route per task" "$P/reference/delegated-task.md" '`scripts/lens-route PLAN_FILE --task <N>`, and writes'
````

In `plugins/dforge/tests/review-route.test.sh`, three pins: the gate, the codex-off route (the lines starting `present "the delegated loop runs the gate before routing"` and `present "the delegated loop names a codex-off route"`) and the failed-route fallback (the line starting `present "the delegated loop falls back to Opus on exit 2"`):

In `plugins/dforge/tests/review-route.test.sh`, replace:

````text
present "the delegated loop runs the gate before routing" "$DT" '- **The seat:** run `scripts/codex-gate` (say its line aloud when it ends'
present "the delegated loop names a codex-off route" "$DT" 'On `reason=codex-off` the review surface is off for'
````

with:

````text
present "the delegated loop refreshes the gate before the review" "$DT" 'Run `scripts/codex-gate --refresh` before `task-step review` when'
present "the delegated loop names a codex-off route" "$DT" 'was routed with `reason=codex-off`: the'
````

In `plugins/dforge/tests/review-route.test.sh`, replace:

````text
present "the delegated loop falls back to Opus on exit 2" "$DT" 'review with `dforge:judge-opus` and say why, quoting its message.'
````

with:

````text
present "the delegated loop falls back to Opus on a failed route" "$DT" 'seat it names as printed, and say why, quoting that'
````

- [ ] **Step 12: Run the new test, every suite that reads these files, the repository validation and the eval text tests**

Run, with the Bash tool's `timeout` at 600000 ms:

```bash
for t in task-step-text waiting-text review-route process-roles inline-mode final-phase auto-run-skills seats native-routing project-status turn-end next-step lanes executor-recovery wave; do
  printf '%s: ' "$t"
  env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID -u CLAUDE_CONFIG_DIR timeout 600 bash plugins/dforge/tests/$t.test.sh | tail -n 1
done
timeout 120 node scripts/validate-repository.mjs
timeout 280 node --test evals/tiers/tests/text.test.mjs evals/tiers/tests/build.test.mjs evals/tiers/tests/cases.test.mjs
```

Expected: every suite line ends `0 failed`, `task-step-text` prints `40 passed, 0 failed`, the validation prints `Repository catalogs, manifests, versions, bundled links and the settings schema are valid.`, and the eval tests report `fail 0`.

- [ ] **Step 13: Commit**

```bash
git add plugins/dforge/tests/task-step-text.test.sh plugins/dforge/tests/process-roles.test.sh plugins/dforge/tests/review-route.test.sh plugins/dforge/reference/delegated-task.md plugins/dforge/reference/parallel-waves.md plugins/dforge/reference/final-review.md plugins/dforge/skills/subagent-driven-development/SKILL.md plugins/dforge/skills/subagent-driven-development/references/implementer-prompt.md plugins/dforge/skills/finishing-a-development-branch/SKILL.md evals/tiers/build-case.mjs
git -c user.name=Darkraise -c user.email=quangtc94@gmail.com commit -m "docs(dforge): run the task loop through task-step"
```

---

### Task 11: Measure an execution run against the baseline

**Files:**
- Create: `docs/dforge/notes/2026-10-26-task-loop-measurement.md`
- Scratch (never committed, deleted at the end): `/tmp/dforge-loop-measure-2026-10-26/`, holding `measure.sh`, `make-subject.py`, `count.py`, `repo`, `prompt.txt`, `model-before`, a clone of this repository at `6df85ec4`, a copy of this branch's `plugins/dforge` and the run's outputs

**Acceptance:** A16

**Interfaces:**
- Consumes: everything Tasks 1-10 built, through the plugin copy the nested session loads (`scripts/task-step`, `scripts/suite-run`, `scripts/in-flight`, and the skill and reference text of Tasks 9 and 10).
- Produces: the measurement note, with its `**Wait calls:** <n>` line and a per-task table.

**Items:** 2
**Implementer:** dforge:impl-sonnet-medium
**Evaluation:** files 1 - spec 1 - coupling 1 - risk 1 = 4

The subject is the trimmed ui-ux plan of the drafter measurement (`docs/dforge/notes/2026-10-25-drafter-measurement.md`): Tasks 1-6 of `docs/dforge/plans/2026-10-24-ui-ux-skill.md` at `6df85ec4`, with their drafted bodies (the measurement's scratch plan was deleted, but the plan at that commit already holds the six tasks, with `**Implementer:**` and `**Evaluation:**` lines). Two changes keep the run safe and runnable: the clone's plan keeps only its header, a six-row Task index and Tasks 1-6, and Task 1's Playwright probe, which edits paths inside the real checkout and needs Playwright MCP tools the nested session does not have, becomes a two-step stand-in that writes the note without probing. The nested session runs `claude --model sonnet --effort high` (the plan's Execution line) with `--plugin-dir` on a copy of this branch's `plugins/dforge`, in `/root/.claude-alt2` with `--setting-sources project,local`, as the drafter measurement launched its sessions. It executes with `dforge:subagent-driven-development` and stops at `Task 6: complete`, so the final review and finishing are not part of the count. The baseline is the typed-seats session `40cb3d10-fb44-41ea-a1f9-91e02a074fd1`: 330 main-loop calls over 5 tasks and a final review, of which 230 fall up to the fifth task's complete line (Step 3 recomputes both).

Shell variables do not survive from one Bash call to the next, so every command below spells the scratch root out as `/tmp/dforge-loop-measure-2026-10-26`, called `M` in the prose. Run Steps 4 and 5 with the Bash tool's `timeout` at 600000 ms, and every other command with at most 180000 ms except Step 7, whose command waits up to 590 seconds.

The nested account is the one the drafter measurement used. Its weekly usage may run out during a two-hour run; the wait command then exits 5 and Step 8 onward records an incomplete run.

- [ ] **Step 1: Check the preconditions and create the scratch root**

```bash
git status --short
test -f plugins/dforge/scripts/task-step && test -f plugins/dforge/scripts/suite-run && grep -q 'Never wait with' plugins/dforge/skills/subagent-driven-development/SKILL.md && echo ready
```

Expected: no status line that names a file under `plugins/dforge/` or `docs/dforge/notes/`, then `ready`. Anything else means Tasks 1-10 are not all committed here: report BLOCKED with what is missing.

```bash
mkdir /tmp/dforge-loop-measure-2026-10-26
git rev-parse --show-toplevel > /tmp/dforge-loop-measure-2026-10-26/repo
jq -r .model /root/.claude-alt2/settings.json > /tmp/dforge-loop-measure-2026-10-26/model-before
jq -r '.model // "none"' /root/.claude/settings.json >> /tmp/dforge-loop-measure-2026-10-26/model-before
cat /tmp/dforge-loop-measure-2026-10-26/model-before
```

If the `mkdir` fails because the directory exists, a previous attempt left it: run `tmux kill-session -t loop-measure` (it may report no such session), remove `/tmp/dforge-loop-measure-2026-10-26` and start this step again.

- [ ] **Step 2: Write the three scripts**

Write `/tmp/dforge-loop-measure-2026-10-26/make-subject.py`:

````python
#!/usr/bin/env python3
"""Trim the ui-ux plan to its header, a six-row Task index and Tasks 1-6.

usage: python3 -I make-subject.py PLAN_FILE   (rewritten in place)

Task 1 probes Playwright MCP and edits paths in the real checkout; the nested
session has no Playwright MCP, so its body becomes a two-step stand-in that
writes the note without the probe. Tasks 2-6 are kept as written.
"""
import re, sys

path = sys.argv[1]
text = open(path, encoding="utf-8").read()
head, rest = text.split("\n## Task index\n", 1)
index, body = rest.split("\n---\n", 1)

head = re.sub(
    r"^\*\*Execution:\*\*.*$",
    "**Execution:** subagent — `claude --model sonnet --effort high` — Tasks 1-6 of nineteen, trimmed for the task-loop measurement",
    head, count=1, flags=re.M)
rows = [l for l in index.splitlines() if re.match(r"^[1-6]\. ", l)]
assert len(rows) == 6, rows

tasks = re.split(r"(?m)^(?=### Task \d+: )", body)
keep = []
for t in tasks:
    m = re.match(r"### Task (\d+): ", t)
    if not m:
        continue
    if int(m.group(1)) != len(keep) + 1:
        break
    keep.append(t)
    if len(keep) == 6:
        break
assert len(keep) == 6, len(keep)

standin = """### Task 1: Verify Playwright MCP writes into a worktree

**Files:**
- Create: `docs/dforge/notes/2026-10-24-ui-ux-playwright-worktree.md`

**Interfaces:**
- Consumes: None
- Produces: the Task 1 note (Contracts)

**Implementer:** dforge:impl-sonnet-low
**Evaluation:** files 0 - spec 0 - coupling 0 - risk 0 = 0

This run has no Playwright MCP, so the note records that and nothing else.

- [ ] **Step 1: Write the note**

Create `docs/dforge/notes/2026-10-24-ui-ux-playwright-worktree.md` with exactly this content:

```markdown
# Playwright MCP and worktree evidence paths

The probe was not run: this session has no Playwright MCP tools.

- **Absolute worktree path:** not probed
- **Bare filename:** not probed
- **Snapshot files:** not probed
```

- [ ] **Step 2: Commit**

```bash
git add docs/dforge/notes/2026-10-24-ui-ux-playwright-worktree.md
git commit -m "docs(notes): record the Playwright worktree probe"
```

---

"""
keep[0] = standin
out = head + "\n## Task index\n\n" + "\n".join(rows) + "\n\n---\n\n" + "".join(keep).rstrip() + "\n"
open(path, "w", encoding="utf-8").write(out)
````

Write `/tmp/dforge-loop-measure-2026-10-26/count.py`:

````python
#!/usr/bin/env python3
"""Count a session transcript's main-loop tool calls per plan task.

usage: python3 -I count.py TRANSCRIPT.jsonl PLAN_TASKS [--skill NAME]

PLAN_TASKS is the number of tasks the plan has. The span starts at the first
call of the Skill tool for NAME (default dforge:subagent-driven-development).
Task N's span starts at the first call after that whose Bash command opens it
(`task-step start <plan> N`, or the older `task-brief <plan> N`) and ends where
the next task's begins. A task counts as done once a Bash call writes
`Task <N>: complete`; the table covers the tasks done in order, and the last
one's span ends after that call. Prints a markdown table, a `**Run:**` line and
a `**Wait calls:**` line.
"""
import json, re, sys

args = sys.argv[1:]
skill = "dforge:subagent-driven-development"
if "--skill" in args:
    i = args.index("--skill")
    skill = args[i + 1]
    del args[i:i + 2]
path, plan_tasks = args[0], int(args[1])

rows = [json.loads(l) for l in open(path, encoding="utf-8")]
ctx = {}
for d in rows:
    if d.get("type") == "assistant" and not d.get("isSidechain"):
        u = d["message"].get("usage") or {}
        c = u.get("input_tokens", 0) + u.get("cache_read_input_tokens", 0) + u.get("cache_creation_input_tokens", 0)
        mid = d["message"]["id"]
        ctx[mid] = max(ctx.get(mid, 0), c)

calls = []
for i, d in enumerate(rows):
    if d.get("type") != "assistant" or d.get("isSidechain"):
        continue
    m = d["message"]
    for b in m["content"]:
        if b.get("type") == "tool_use":
            calls.append({"line": i, "name": b["name"], "inp": b.get("input") or {}, "mid": m["id"], "ctx": ctx[m["id"]]})

def cmd(c):
    return c["inp"].get("command", "") or ""

start = next((k for k, c in enumerate(calls) if c["name"] == "Skill" and c["inp"].get("skill") == skill), None)
if start is None:
    sys.exit("no Skill call for " + skill)
calls = calls[start:]

def opens(c, n):
    return c["name"] == "Bash" and re.search(r"task-(?:step start|brief)\s+(?:--header\s+)?\S+\s+%d(?:\s|$)" % n, cmd(c)) is not None

marks, dones = {}, {}
for n in range(1, plan_tasks + 1):
    k = next((k for k, c in enumerate(calls) if opens(c, n)), None)
    d = next((k for k, c in enumerate(calls) if c["name"] == "Bash" and ("Task %d: complete" % n) in cmd(c)), None)
    if k is None or d is None:
        break
    marks[n], dones[n] = k, d
last = len(marks)
if last == 0:
    sys.exit("no task reached its complete line")

def is_wait(c):
    return c["name"] == "Monitor" or (c["name"] == "Bash" and re.search(r"(?<![\w-])sleep\s+\d", cmd(c)) is not None)

spans = [("setup", 0, marks[1])]
for n in range(1, last + 1):
    spans.append(("Task %d" % n, marks[n], marks[n + 1] if n < last else dones[n] + 1))
spans.append(("after Task %d" % last, dones[last] + 1, len(calls)))

print("| Span | Main-loop calls | Turns | Wait calls | Context at first call | Context at last call | Sum of context over turns |")
print("|---|---|---|---|---|---|---|")
tot = [0, 0, 0, 0]
for name, a, b in spans:
    seg = calls[a:b]
    if not seg:
        print("| %s | 0 | 0 | 0 | - | - | - |" % name)
        continue
    mids = []
    for c in seg:
        if c["mid"] not in mids:
            mids.append(c["mid"])
    waits = sum(1 for c in seg if is_wait(c))
    csum = sum(ctx[m] for m in mids)
    print("| %s | %d | %d | %d | %d | %d | %d |" % (name, len(seg), len(mids), waits, seg[0]["ctx"], seg[-1]["ctx"], csum))
    tot[0] += len(seg); tot[1] += len(mids); tot[2] += waits; tot[3] += csum
print("| total | %d | %d | %d | | | %d |" % tuple(tot))
monitors = sum(1 for c in calls if c["name"] == "Monitor")
print()
print("**Run:** %s" % ("complete: all %d tasks done" % plan_tasks if last == plan_tasks else "incomplete: %d of %d tasks done" % (last, plan_tasks)))
print("**Wait calls:** %d" % tot[2])
print("Monitor calls: %d; Bash sleep calls: %d" % (monitors, tot[2] - monitors))
````

Write `/tmp/dforge-loop-measure-2026-10-26/measure.sh`:

````bash
#!/usr/bin/env bash
# The task-loop measurement's mechanics. M is the directory this script is in.
set -euo pipefail
M=$(cd "$(dirname "$0")" && pwd)
REPO=$(cat "$M/repo")
BASE=6df85ec4
PLAN=docs/dforge/plans/2026-10-24-ui-ux-skill.md
NODEBIN=$(dirname "$(command -v node)")
CFG=/root/.claude-alt2
SESSION=loop-measure
nested() { # nested CMD... - run CMD in a clean environment on the nested login
  env -i HOME=/root PATH="/root/.local/bin:$NODEBIN:/usr/local/bin:/usr/bin:/bin" TERM=xterm-256color LANG=C.UTF-8 \
    CLAUDE_CONFIG_DIR="$CFG" IS_SANDBOX=1 "$@"
}

case ${1:-} in
  login) # login - exit 0 only when the nested login answers
    out=$(nested timeout 150 /root/.local/bin/claude -p --model sonnet --setting-sources project,local \
      "Reply with the single word OK." </dev/null 2>&1 || true)
    printf '%s\n' "$out" | tail -n 3
    printf '%s\n' "$out" | grep -qx 'OK'
    ;;
  setup) # setup - the clone at BASE with the trimmed plan, and the plugin copy
    timeout 300 git clone -q "$REPO" "$M/clone"
    git -C "$M/clone" checkout -q -B main "$BASE"
    git -C "$M/clone" remote remove origin
    for b in $(git -C "$M/clone" branch --format='%(refname:short)'); do
      [ "$b" = main ] || git -C "$M/clone" branch -q -D "$b"
    done
    python3 -I "$M/make-subject.py" "$M/clone/$PLAN"
    git -C "$M/clone" -c user.name=Darkraise -c user.email=quangtc94@gmail.com commit -q -am "docs(plans): trim the ui-ux plan to Tasks 1-6"
    mkdir -p "$M/plugin"
    git -C "$REPO" archive HEAD plugins/dforge | tar -x -C "$M/plugin"
    printf '{}\n' > "$M/measure-settings.json"
    printf 'clone at %s: %s\n' "$(git -C "$M/clone" rev-parse --short HEAD)" "$(git -C "$M/clone" log -1 --format=%s)"
    printf 'plugin copy has task-step: %s, suite-run: %s\n' \
      "$([ -f "$M/plugin/plugins/dforge/scripts/task-step" ] && echo yes || echo no)" \
      "$([ -f "$M/plugin/plugins/dforge/scripts/suite-run" ] && echo yes || echo no)"
    ;;
  launch) # launch - the nested interactive session, in tmux
    printf '#!/usr/bin/env bash\ncd %q\n' "$M/clone" > "$M/start.sh"
    printf 'exec env -i HOME=/root PATH=%q TERM=xterm-256color LANG=C.UTF-8 CLAUDE_CONFIG_DIR=%q IS_SANDBOX=1 /root/.local/bin/claude --model sonnet --effort high --setting-sources project,local --settings %q --plugin-dir %q --dangerously-skip-permissions\n' \
      "/root/.local/bin:$NODEBIN:/usr/local/bin:/usr/bin:/bin" "$CFG" "$M/measure-settings.json" "$M/plugin/plugins/dforge" >> "$M/start.sh"
    date +%s > "$M/launched"
    timeout 30 tmux new-session -d -s "$SESSION" -x 200 -y 50 "bash $M/start.sh"
    ;;
  screen) tmux capture-pane -p -t "$SESSION" | tail -n 30 ;;
  keys) shift; tmux send-keys -t "$SESSION" "$@" ;;
  send) # send FILE - type the file's text as one prompt and submit it
    tmux send-keys -t "$SESSION" -l "$(cat "$2")"; sleep 2; tmux send-keys -t "$SESSION" Enter
    ;;
  transcript) # transcript - the nested session's main transcript
    slug=$(printf '%s' "$M/clone" | sed 's/[^A-Za-z0-9]/-/g')
    for f in $(find "$CFG/projects/" -maxdepth 2 -name '*.jsonl' -path "*$slug*" -newer "$M/launched" 2>/dev/null); do
      grep -q '"skill":"dforge:subagent-driven-development"' "$f" && echo "$f"
    done | head -n 1
    ;;
  wait) # wait SECONDS - until the run reports FINISHED; exit 0 finished, 1 timed out, 3 login invalid, 4 session gone, 5 usage limit
    end=$((SECONDS + ${2:-7000}))
    while [ $SECONDS -lt $end ]; do
      pane=$(tmux capture-pane -p -t "$SESSION" 2>/dev/null) || { echo "session gone"; exit 4; }
      if printf '%s\n' "$pane" | grep -qiE 'not logged in|please run /login|invalid api key|oauth token has expired'; then
        echo "login invalid"; exit 3
      fi
      if printf '%s\n' "$pane" | grep -qiE 'limit reached'; then
        echo "usage limit"; exit 5
      fi
      t=$("$0" transcript)
      if [ -n "$t" ] && grep -q 'Task 6: complete (' "$t" && printf '%s\n' "$pane" | grep -q '^● FINISHED'; then
        echo "finished after $SECONDS s"; exit 0
      fi
      sleep 20
    done
    echo "timed out after ${2:-7000} s"; exit 1
    ;;
  stop) # stop - end only this script's tmux session and anything left under the plugin copy or the clone
    tmux kill-session -t "$SESSION" 2>/dev/null || true
    for p in $(pgrep -f -- "--plugin-dir $M/[p]lugin" || true); do kill "$p" 2>/dev/null || true; done
    printf 'tmux sessions named %s: %s\n' "$SESSION" "$(tmux ls 2>/dev/null | grep -c "^$SESSION:" || true)"
    printf 'processes left: %s\n' "$(pgrep -fc -- "$M/[c]lone|--plugin-dir $M/[p]lugin" || true)"
    ;;
  *) echo "usage: measure.sh login|setup|launch|screen|keys KEY...|send FILE|transcript|wait SECONDS|stop" >&2; exit 2 ;;
esac
````

- [ ] **Step 3: Check the counter against the baseline transcript**

```bash
timeout 120 python3 -I /tmp/dforge-loop-measure-2026-10-26/count.py /root/.claude/projects/-root-repositories-darkraise-ai-plugins/40cb3d10-fb44-41ea-a1f9-91e02a074fd1.jsonl 5 | tee /tmp/dforge-loop-measure-2026-10-26/baseline.txt
```

Expected: a table whose `total` row starts `| total | 330 |`, then `**Run:** complete: all 5 tasks done` and `**Wait calls:** 114`. In that session Tasks 2-4 ran as one parallel wave, so the table shows their calls under Task 1 and Task 4; use its totals. If the transcript is gone (the store keeps about 30 days), skip this check, write `baseline transcript no longer on disk; the spec's totals only` in the note, and compare against 330 calls over 5 tasks.

- [ ] **Step 4: Check the nested login**

Run: `timeout 180 bash /tmp/dforge-loop-measure-2026-10-26/measure.sh login`
Expected: `OK`, exit 0. Anything else (an expired login, a prompt to sign in) is BLOCKED: report it and do not fall back to another configuration directory or to the host's own login.

- [ ] **Step 5: Set up the subject**

```bash
timeout 400 bash /tmp/dforge-loop-measure-2026-10-26/measure.sh setup
cd /tmp/dforge-loop-measure-2026-10-26/clone && timeout 120 bash /tmp/dforge-loop-measure-2026-10-26/plugin/plugins/dforge/scripts/plan-lint docs/dforge/plans/2026-10-24-ui-ux-skill.md
```

Expected: `clone at <sha7>: docs(plans): trim the ui-ux plan to Tasks 1-6`, `plugin copy has task-step: yes, suite-run: yes`, then `plan-lint: 0 errors, 1 warnings` (the warning is `Execution line is subagent but only 0 of 6 tasks are heavy`). `git clone` may print `hint:` lines about the initial branch name; ignore them.

- [ ] **Step 6: Write the prompt, launch the nested session and send the prompt**

Write `/tmp/dforge-loop-measure-2026-10-26/prompt.txt` (one line):

````text
Execute the plan docs/dforge/plans/2026-10-24-ui-ux-skill.md in this repository with dforge:subagent-driven-development. This is an unattended measurement run: answer the finish preference keep without asking, create the execution worktree from this clone's main branch (it has no remote), and as soon as the ledger holds the line Task 6: complete, stop: run no final review, no finishing and no wrap-up, and reply with the single word FINISHED.
````

Then:

```bash
bash /tmp/dforge-loop-measure-2026-10-26/measure.sh launch
```

Wait a few seconds, then run `bash /tmp/dforge-loop-measure-2026-10-26/measure.sh screen`. A screen asking whether to trust the folder: run `bash /tmp/dforge-loop-measure-2026-10-26/measure.sh keys Down Enter`, then `screen` again. Continue only once the screen shows `bypass permissions on` and an empty prompt; then run `bash /tmp/dforge-loop-measure-2026-10-26/measure.sh send /tmp/dforge-loop-measure-2026-10-26/prompt.txt` and `screen` once more to see the prompt was accepted. A screen asking to log in is BLOCKED (run `measure.sh stop` first).

- [ ] **Step 7: Wait for the run in bounded stretches**

Run, with the Bash tool's `timeout` at 600000 ms: `bash /tmp/dforge-loop-measure-2026-10-26/measure.sh wait 570`

It prints one line and exits: 0 `finished after <n> s`; 1 `timed out after 570 s`; 3 `login invalid`; 4 `session gone`; 5 `usage limit`. On exit 1, run the same command again, up to 13 stretches in all (about two hours); a 13th exit 1 means the run did not finish. Any other exit ends the wait. Between stretches say one line of status and nothing else; do not read the screen or the transcript, and do not touch the nested session. Whatever the outcome, go on to Step 8.

- [ ] **Step 8: Stop the nested session and count its transcript**

```bash
bash /tmp/dforge-loop-measure-2026-10-26/measure.sh stop
bash /tmp/dforge-loop-measure-2026-10-26/measure.sh transcript | tee /tmp/dforge-loop-measure-2026-10-26/transcript-path.txt
timeout 120 python3 -I /tmp/dforge-loop-measure-2026-10-26/count.py "$(cat /tmp/dforge-loop-measure-2026-10-26/transcript-path.txt)" 6 | tee /tmp/dforge-loop-measure-2026-10-26/count.txt
```

Expected from `stop`: `tmux sessions named loop-measure: 0` and `processes left: 0`; if the count is not 0, list them with `pgrep -fa 'dforge-loop-measure-2026-10-26'`, and kill only those PIDs (they carry this run's path).

Expected from `count.py` on a finished run: a table with `setup`, `Task 1` to `Task 6`, `after Task 6` and `total` rows, then `**Run:** complete: all 6 tasks done` and `**Wait calls:** 0`. A run that did not finish still prints its table for the tasks that reached their complete line, with `**Run:** incomplete: <k> of 6 tasks done`. If `count.py` exits with `no task reached its complete line` or the transcript path is empty, no task completed: skip to Step 9 and report BLOCKED with the wait command's exit reason once the scratch root is gone (Step 10).

- [ ] **Step 9: Check the host's settings, and compute the comparison figures**

```bash
jq -r .model /root/.claude-alt2/settings.json > /tmp/dforge-loop-measure-2026-10-26/model-after
jq -r '.model // "none"' /root/.claude/settings.json >> /tmp/dforge-loop-measure-2026-10-26/model-after
diff /tmp/dforge-loop-measure-2026-10-26/model-before /tmp/dforge-loop-measure-2026-10-26/model-after && echo models-unchanged
python3 -I - <<'PY'
import os, re
def through(path):
    calls = waits = tasks = 0; ctx = "-"
    for l in open(path):
        m = re.match(r"\| (setup|Task \d+) \| (\d+) \| \d+ \| (\d+) \| \S+ \| (\S+) \|", l)
        if m:
            calls += int(m.group(2)); waits += int(m.group(3))
            if m.group(1) != "setup":
                tasks += 1; ctx = m.group(4)
    return calls, waits, tasks, ctx
for name in ("baseline", "count"):
    path = "/tmp/dforge-loop-measure-2026-10-26/%s.txt" % name
    if not os.path.exists(path):
        print("%s: no table" % name); continue
    c, w, t, ctx = through(path)
    if ctx.isdigit(): ctx = format(int(ctx), ",")
    print("%s: %d main-loop calls from the skill call through %d tasks (%.1f per task), %d wait calls, context %s at the last call of Task %d" % (name, c, t, c / t, w, ctx, t))
PY
git -C /tmp/dforge-loop-measure-2026-10-26/clone log --oneline 6df85ec4..main | wc -l
```

Expected: `models-unchanged` (a `/model` command in the nested session rewrites the default model; if the diff shows a change, restore the old value from `model-before` with `jq` into a temporary file and move it back, and say so in the note), and two figure lines. The `baseline` line is 230 calls over 5 tasks (46.0 per task); the `count` line is this run's figure over the tasks that finished. Each line also gives the wait calls in its span and the context at the last call of its last task: the note quotes those figures, so write none from memory. A line `baseline: no table` means Step 3 found no transcript. The last command prints the commits on the clone's `main` beyond the plan commit's parent (the trimmed plan, then whatever merged).

- [ ] **Step 10: Write the note and remove the scratch root**

Write `docs/dforge/notes/2026-10-26-task-loop-measurement.md`. The first two lines after the title must be the `**Wait calls:**` and `**Run:**` lines copied from `count.txt`, the table is `count.txt`'s table verbatim, and every `<…>` is filled with what the earlier steps printed:

````markdown
# Task-loop measurement — 2026-10-26

**Wait calls:** <n, from count.txt>
**Run:** <the count.txt Run line> (<`finished after <n> s` | the wait command's last line, with its exit code>)

Subject: Tasks 1-6 of `docs/dforge/plans/2026-10-24-ui-ux-skill.md` at `6df85ec4`, trimmed to its header, a six-row Task index and six tasks; Task 1's Playwright probe is a two-step stand-in because the nested session has no Playwright MCP. The nested session ran `claude --model sonnet --effort high` in `/root/.claude-alt2` with `--setting-sources project,local` and `--plugin-dir` on a copy of this branch's `plugins/dforge` at `<sha7 of git rev-parse --short HEAD>`, answered the finish preference `keep`, and stopped at `Task 6: complete`: no final review and no finishing are in the count.

## Per task

<count.txt's table, verbatim>

Calls are tool calls in the main loop; a turn is one assistant message that made calls; context is input plus cache tokens of the message that made the call, and the last column sums it over the span's turns. `Monitor` and Bash `sleep` calls are the wait calls.

## Against the baseline

The baseline is the typed-seats execution session `40cb3d10-fb44-41ea-a1f9-91e02a074fd1`: 330 main-loop calls over 5 tasks and a final review, <baseline.txt's `**Wait calls:**` figure> of them wait calls (<its `Monitor calls: …; Bash sleep calls: …` line>) by this counter. Through its fifth task's complete line it made <the `baseline:` figure line's calls> calls, <its per-task figure> per task. If Step 3 found no transcript, write instead "the spec's totals only: 330 calls over 5 tasks" and `not recomputed` in the baseline row's wait and context cells.

| | Main-loop calls | Tasks | Calls per task | Wait calls | Context at the last task's last call |
|---|---|---|---|---|---|
| Baseline, through Task 5 | <from the `baseline:` line> | <tasks> | <per task> | <wait calls> | <context> |
| This run | <from the `count:` line> | <tasks> | <per task> | <wait calls> | <context> |

<Two sentences: whether wait calls are zero (the one hard bar), and how the calls per task and the context at the last call compare with the baseline's, both read from the table above.>

## Notes

- The count stops at the last task's complete line; the baseline's 330 includes the <calls in baseline.txt's `after Task 5` row> calls after its fifth task's complete line (its final review and finishing) that this run did not execute.
- <One line per observation worth keeping: a task that needed fix rounds, a re-review skipped under the skip rule, a suite-run reuse, or a hung launch; or `none`.>
- The nested transcript stays in the shared projects store (`<the transcript-path.txt line>`), which keeps about 30 days.
````

Then remove the scratch root and confirm nothing of this run is left:

```bash
rm -rf /tmp/dforge-loop-measure-2026-10-26
tmux ls 2>&1 | grep -c '^loop-measure:'
pgrep -fc 'dforge-loop-measure-[2]026-10-26'
git status --short
```

Expected: `0`, `0`, and a status that lists `?? docs/dforge/notes/2026-10-26-task-loop-measurement.md` and no other file this task created.

- [ ] **Step 11: Commit**

```bash
git add docs/dforge/notes/2026-10-26-task-loop-measurement.md
git -c user.name=Darkraise -c user.email=quangtc94@gmail.com commit -m "docs(notes): measure the task-loop run"
```

If the run was incomplete after at least one task, the note says so in its `**Run:**` line and this task reports DONE_WITH_CONCERNS naming the reason (timeout, login, usage limit); if the nested login was invalid (Step 4) or no task completed (Step 8), it reports BLOCKED and commits nothing. A finished run with `**Wait calls:** 0` is DONE; a finished run with a non-zero count is DONE_WITH_CONCERNS naming the calls, since A16's one hard bar failed.
