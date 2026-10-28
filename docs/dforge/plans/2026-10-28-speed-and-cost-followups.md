# Speed-and-cost Follow-ups Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: the skill the **Execution:** line names — dforge:subagent-driven-development for `subagent`, dforge:executing-plans for `inline`. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the speed-and-cost register's fix rows: keep every review seat's text away from `bash -c` (a judge write guard and plan-named baseline commands), harden task-step, the stop gate and the eval harness, and clean up the docs and tests the run left behind.

**Architecture:** A write guard in the cockpit mod's `tool.call` hook limits `dforge:judge-*` seats to the report files their dispatch names; `task-step`'s `settle_item` runs only baseline commands the plan names. The other tasks are independent fixes in `scripts/task-step`, `scripts/impl-stop-gate`, `evals/tiers/lib`, `scripts/draft-pack` and skill or reference text, each with its tests.

**Tech Stack:** Bash (POSIX tools; Linux, macOS and Windows Git Bash), jq, TypeScript for the cockpit mod (tested by `claude plugin test plugins/dforge`), Node 22 for `evals/tiers`.

**Spec:** docs/dforge/specs/2026-10-28-speed-and-cost-followups-design.md

**Execution:** subagent — `claude --model sonnet --effort high` — the plan runs parallel waves

**Parallelism:** waves — 1 | 2-4 | 5 | 6 | 7

**Integration check:** node scripts/test-all.mjs

**Worktree setup:** none

**Plan review:** 2026-10-28 — dforge:judge-opus — executability 15 / coherence 16 / coverage 18 / assumptions 12 (round 1)

## Global Constraints

- Shell scripts and tests run under Bash on Linux, macOS and Windows Git Bash: POSIX tools only, no GNU-only flags, `tr -d '\r'` on any text read from a file or a command, and `rg` never appears in a script (it is not installed as a binary; use `grep`).
- `claude` is a shell function on the development host, so steps call `/root/.local/bin/claude` (Claude Code 2.1.312 there).
- Every test, build and CLI command a step runs carries an explicit timeout (`timeout <s> …`), and nothing is left running afterwards.
- Every test suite builds its own `mktemp -d` repository or directory and removes it on exit; no two suites share a path, a port or global state. Suites that read Claude config `unset CLAUDE_CONFIG_DIR`.
- English only. Commits are `<type>(<scope>): <subject>`, subject at most 50 characters, imperative, no period; no AI attribution of any kind, no `Co-Authored-By:` trailer; author and committer `Darkraise <quangtc94@gmail.com>`.
- Historical plans and specs under `docs/dforge/plans/` and `docs/dforge/specs/` other than this plan and its spec are never edited.
- Keep the existing comment density and naming of each file you touch; comments only where the why is non-obvious.

## Contracts

- **Guard refusal** (Task 1 produces; Task 5's docs cite it). A judge write the guard refuses is denied with exactly `dforge: a review seat writes only the report file its dispatch names (<allowed paths, comma-separated, or none>); <target path> is not one.` A write-tool call from a judge loop refused by the hook's `.catch` reads `dforge: the review-seat write guard could not check this write (<error message>); it is refused.`
- **Allowed report paths** (Task 1). Captured at `agent.spawn` from the dispatch prompt: every absolute path ending `-report.md` under `<checkout>/.dforge` or `<primary>/.dforge`. Task 5's `delegated-task.md` text says a review seat writes only its report file.
- **Plan-named command** (Task 5). `settle_item` returns 0 settled, 1 could not check, 2 command not named in the plan. Only status 2 makes `settle_cannot_verify` append ` (command not named in the plan)` to the kept item.
- **`reference/delegated-task.md`** is edited by Tasks 5, 6 and 7, one after another, each in its own passage: Task 5 the cannot-verify passage ("The reviewer's `cannot-verify: exists …`"), Task 6 the `rereview --covered` "takes up to ten minutes" sentence, Task 7 the suite-findings passage and the `## Verified` evidence sentence. `tests/delegated-suite.test.sh` is Task 5's; Tasks 6 and 7 add their pins to their own `task-step-*.test.sh` files.
- **Shared test files across waves.** `tests/task-step-text.test.sh` takes one pin change from Task 4 (wave 2) and Task 5's pins (wave 3); `tests/task-step-settle.test.sh` takes Task 5's section, then Task 7's, appended after it; `tests/speed-and-cost.acceptance.test.sh` is Task 5's and `tests/task-step.test.sh` Task 6's. No two tasks of one wave touch the same file.
- **Setup log** (Task 6). `run_at_base` writes the Worktree setup's output to `<OUT_LOG>.setup.log`; a failed setup prints `task-step: the worktree setup failed at <sha7> (log <path>)` on stderr.

## Assumptions (evidence)

- The cockpit's `tool.call` hook runs before every tool call of a judge subagent, background dispatches included, and the spawning seat is known then — unverified — Task 1 verifies it (A22's live probe in an interactive session and a `claude -p` run). Partial evidence: `plugins/dforge/hooks/cockpit/register.tsx:720-731` reads `e.agentId` and the `spawns` seat in that hook; `claude-code.d.ts` of 2.1.310 (AgentLoop, AgentInfo) says `agentId` names the subagent's loop and `AgentInfo.type` its spawned type.
- Review dispatches name their report file as an absolute path under the state directory: task-step builds the workspace with `dforge_workspace` (`plugins/dforge/scripts/task-step:313`, `:497`; `plugins/dforge/scripts/lib/roots.sh:105-108`), which on Windows converts through `cygpath -m -l` to the `C:/…` long form (`roots.sh:21-34`), the spelling `git rev-parse --show-toplevel` gives the cockpit's roots; on Linux it printed `/root/repositories/darkraise-ai-plugins/.dforge/sdd/…` (2026-10-28). Task 1's `canonPath` also maps a `/c/…` spelling, so either form matches.
- The cockpit test engine answers `on('agent.list', …)` the way it answers `on('config.list', …)` in `plugins/dforge/tests/cockpit.test.ts`: the Task 1 drafter's scratch run on 2026-10-28 passed the guard tests against a prototype guard, and Task 1's Step 3 shows the handler is reached (the new tests fail on `Received: undefined`, not on a missing handler).
- The waves put the security task (Task 1) first and alone, where the spec's decomposition ran Part A after B, C and D: the spec's riskiest assumption must be verified by the plan's first task, and a risk-3 task runs alone. The order changes nothing else.
- Borderline review score (assumptions 12, round 1): its two unsupported assumptions, the report-path spelling and the `agent.list` test mock, now carry evidence above, and the remaining one is Task 1's live probe; no second round, since no score was 8 or below.
- Spec A23 (repository validation, `node scripts/test-all.mjs`, `claude plugin validate` on the marketplace and every Claude plugin, green CI on every job) is checked by the finishing flow: the final whole-branch review's gates and the merge's push, which waits for the CI run as the repository's CLAUDE.md requires. No task carries it.
- `settle_item` sees the amended plan: `src="$TMP/plan.md"` is set globally (`plugins/dforge/scripts/task-step:486`).
- The cockpit tests run only through `claude plugin test plugins/dforge` (`.github/workflows/validate.yml:101-104`); `node scripts/test-all.mjs` skips them when `claude` is not on PATH (`scripts/test-all.mjs:41-42`), as on the development host.
- A Codex task reviewer cannot write files: `scripts/run-codex-review.sh:146` runs it `read-only`.

## Task index

1. Judge write guard
2. Stop gate retry and evidence checks
3. Eval harness isolation and manifest parsing
4. Doc pointers and test cleanups
5. Plan-named baseline commands
6. task-step base runs and step-file checks
7. Suite findings and exists checks

---

### Task 1: Judge write guard

**Files:**
- Modify: `plugins/dforge/hooks/cockpit/register.tsx` (the `agent.spawn` hook where `const spawn: CockpitSpawn` is built; the `tool.call` hook and its `.catch`; new helpers just above `async function attributionLine`)
- Modify: `plugins/dforge/types/index.d.ts` (`CockpitSpawn` gains an optional `reports`)
- Test: `plugins/dforge/tests/cockpit.test.ts`
- Create: `docs/dforge/notes/2026-10-28-judge-write-guard-probe.md`

**Interfaces:**
- Consumes: nothing from another task.
- Produces: the **Guard refusal** and **Allowed report paths** entries of Contracts, exactly as worded there. Task 5's `delegated-task.md` text cites the refusal; nothing imports a symbol from this task.

**Items:** 27

**Depends on:** none

**Implementer:** dforge:impl-opus-high
**Evaluation:** files 2 - spec 2 - coupling 1 - risk 3 = 8
**Lenses:** security, lang-typescript

This task's riskiest assumption is that the cockpit's `tool.call` hook runs before every tool call a judge subagent makes, background dispatches included, and that both the `spawns` record and `$.agent.list()` name the agent's type at that moment. Step 1 settles it with a live probe before anything is built. Run every command of this task from the repository root unless it says otherwise. A drafting run on 2026-10-28 (Claude Code 2.1.312, Linux) already saw it hold in `claude -p` and in an interactive tmux session; Step 1 repeats that on the implementer's tree so the note records it.

- [ ] **Step 1: Probe the assumption with a throwaway guard**

Nothing in the checkout changes in this step. Everything lives in a scratch directory, `PROBE`, outside the repository.

1. Create the directory and the two probe scripts below (`$PROBE/setup.sh`, `$PROBE/run.sh`), then run the setup. The setup copies the host's login into an isolated Claude config directory (the same way `evals/tiers/lib/pipeline.mjs` does) and makes a throwaway git repository; the copy is removed in Step 6.

```bash
PROBE=$(mktemp -d)
cat > "$PROBE/setup.sh" <<'SCRIPT'
#!/usr/bin/env bash
# setup.sh PROBE: an isolated Claude config, a throwaway repository and the probe prompt under PROBE.
set -euo pipefail
R=$1/root
W=$R/work
mkdir -p "$R"/{home,xdg/config,xdg/cache,xdg/data,xdg/state,claude,tmp} "$W"
git init -q "$W"
git -C "$W" -c user.name=probe -c user.email=probe@example.com commit -q --allow-empty -m init
mkdir -p "$W/.dforge/sdd/probe"
printf '{"hasCompletedOnboarding":true,"projects":{"%s":{"hasTrustDialogAccepted":true}}}\n' "$W" > "$R/claude/.claude.json"
cp "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/.credentials.json" "$R/claude/.credentials.json"
cat > "$1/prompt.txt" <<PROMPT
Call the Agent tool exactly once, with subagent_type "dforge:judge-sonnet-high" and this prompt, word for word: "You are running a write-guard probe. Your dispatch names two report files. Use the Write tool to write the single line PROBE-OUTSIDE to the first report file, $W/.dforge/sdd/probe/amendments.md, then use the Write tool to write the single line PROBE-REPORT to the second report file, $W/.dforge/sdd/probe/task-1-review-report.md. Attempt both even if the first call is refused. Reply with one line per file: its name and either WRITTEN or the refusal text you received, verbatim." When the agent returns, print its reply and nothing else.
PROMPT
SCRIPT
cat > "$PROBE/run.sh" <<'SCRIPT'
#!/usr/bin/env bash
# run.sh PROBE MODE PLUGIN_DIR OUT: one run against the probe repository.
# MODE is p (claude -p) or tui (interactive, in a tmux session of its own).
# OUT receives the run's output; the files the judge left in the workspace are listed.
set -u
PROBE=$1 MODE=$2 PLUGIN=$3 OUT=$4
R=$PROBE/root
W=$R/work
rm -f "$W"/.dforge/sdd/probe/*
ENVV=(env -i PATH="$PATH" HOME="$R/home" XDG_CONFIG_HOME="$R/xdg/config" XDG_CACHE_HOME="$R/xdg/cache"
  XDG_DATA_HOME="$R/xdg/data" XDG_STATE_HOME="$R/xdg/state" CLAUDE_CONFIG_DIR="$R/claude" TMPDIR="$R/tmp"
  IS_SANDBOX=1 CLAUDE_CODE_DISABLE_CLAUDE_MDS=1 TERM=xterm-256color)
cd "$W" || exit 1
if [ "$MODE" = p ]; then
  timeout 400 "${ENVV[@]}" /root/.local/bin/claude -p --model sonnet --effort low --plugin-dir "$PLUGIN" \
    --setting-sources project --dangerously-skip-permissions --output-format stream-json --verbose \
    --max-budget-usd 1 --no-session-persistence < "$PROBE/prompt.txt" > "$OUT" 2> "$OUT.err"
else
  printf 'cd %q\nexec %s\n' "$W" "$(printf '%q ' "${ENVV[@]}" /root/.local/bin/claude --model sonnet --effort low \
    --plugin-dir "$PLUGIN" --setting-sources project --permission-mode acceptEdits)" > "$PROBE/launch.sh"
  tmux new-session -d -s probe-judge-guard -x 220 -y 50 "bash $PROBE/launch.sh" || exit 1
  sleep 15
  tmux send-keys -t probe-judge-guard -l "$(tr '\n' ' ' < "$PROBE/prompt.txt")"
  sleep 1
  tmux send-keys -t probe-judge-guard Enter
  for _ in $(seq 1 30); do
    sleep 5
    tmux capture-pane -J -p -S -200 -t probe-judge-guard > "$OUT"
    grep -qE 'finished · [0-9]+s' "$OUT" && break
  done
  sleep 25
  tmux capture-pane -J -p -S -200 -t probe-judge-guard > "$OUT"
  tmux kill-session -t probe-judge-guard
fi
ls "$W/.dforge/sdd/probe"
SCRIPT
chmod +x "$PROBE/setup.sh" "$PROBE/run.sh"
bash "$PROBE/setup.sh" "$PROBE"
```

2. Make the throwaway guard: copy the plugin without its tests, `cp -R plugins/dforge "$PROBE/spike" && rm -rf "$PROBE/spike/tests"`, and in `$PROBE/spike/hooks/cockpit/register.tsx` insert, directly after `const tool = String(e.tool)` in the `tool.call` hook, a check that runs only when `e.agentId` is set and the tool is `Write`: read the `spawns` record for `e.agentId`, call `$.agent.list()` (spelled exactly so; the mod loader rejects it used as a value) and find the entry with that id, and, when `file_path` does not end in `-report.md`, return `{ deny: 'PROBE-DENY agentId=<id> spawns=<seat or null> list=<type or null>' }`.

3. Run the judge probe in both modes against the copy. Each run starts a `dforge:judge-sonnet-high` whose dispatch names `amendments.md` as its first "report file" (so it attempts the write) and a real `-report.md` as its second. Each costs a few cents.

```bash
bash "$PROBE/run.sh" "$PROBE" p "$PROBE/spike" "$PROBE/spike-p.jsonl"
grep -o 'PROBE-DENY agentId=[^ ]* spawns=[^ ]* list=[^ "<\\]*' "$PROBE/spike-p.jsonl" | head -1
bash "$PROBE/run.sh" "$PROBE" tui "$PROBE/spike" "$PROBE/spike-tui.txt"
grep -o 'PROBE-DENY agentId=[^ ]* spawns=[^ ]* list=[^ "<\\]*' "$PROBE/spike-tui.txt" | head -1
tmux ls 2>&1 | grep -c probe-judge-guard
```

Expected, for each mode: `run.sh` lists only `task-1-review-report.md`; the grep prints one line `PROBE-DENY agentId=<id> spawns=dforge:judge-sonnet-high list=dforge:judge-sonnet-high`; the last command prints `0` (the tmux session is gone). If a judge's reply says it skipped the write, nothing was attempted and the run proves nothing: run that mode once more.

4. If, after the retry, either mode shows no `PROBE-DENY` line, or `amendments.md` was written, or `spawns=` or `list=` is `null`, the hook does not see the judge's call: stop. Write the note (Step 6's file) with the `## Setup` and `## Before the build` sections and the verdict `BLOCKED`, remove `$PROBE`, commit only the note, and report BLOCKED. Otherwise keep `$PROBE` for Step 6.

- [ ] **Step 2: Write the failing tests**

Two small edits to the `World` type and the `world` helper in `plugins/dforge/tests/cockpit.test.ts`, so a test can say a file is a symbolic link.

In `type World`, the `files` line becomes:

```ts
  files?: Record<string, { text: string; mtimeMs?: number; kind?: 'file' | 'dir' | 'other'; isLink?: boolean }>
```

In `world`, the `fs.stat` handler returns `isLink: file.isLink ?? false` where it returned `isLink: false`.

Then insert this block between the closing `})` of `describe('seat check', …)` and `describe('handoff reading', …)`:

```ts
describe('review seat write guard', () => {
  const STATE = '/home/me/code/shop/.dforge'
  const WS = `${STATE}/sdd/2026-10-28-plan`
  const REVIEW = `${WS}/task-1-review-report.md`
  const GUARD = /^dforge: a review seat writes only the report file its dispatch names \(/
  const dispatch = (prompt: string, subagentType: string, n: number) =>
    ({ tool_use_id: `toolu_${n}`, prompt, description: 'Review task 1', subagentType, provider: { plugin: 'dforge', tier: 'user' }, parentModel: 'claude-opus-5-5', background: true, fork: false }) as never
  const write = ($: Parameters<TestBody>[0], agentId: string | undefined, path: string, tool = 'Write') =>
    $.tool.call({ tool, ...(tool === 'NotebookEdit' ? { notebook_path: path } : { file_path: path }), content: 'x', ...(agentId === undefined ? {} : { agentId }) } as never)
  // A judge (agent judge-1) that names `named`, and an implementer (impl-1), started in a session at /home/me/code/shop.
  const started = async ($: Parameters<TestBody>[0], on: On, named: string[] = [REVIEW], extra: Partial<World> = {}, list: () => unknown = () => ({ value: [] })) => {
    world(on, { tokens: 10_000, agentIds: ['judge-1', 'impl-1'], ...extra })
    on('agent.list', list as never)
    await $.session.start(START)
    await $.agent.spawn(dispatch(`Review task 1 of the plan. Write your full report to ${named.join(' and ')}, then reply in 10 lines.`, 'dforge:judge-sonnet-high', 1))
    await $.agent.spawn(dispatch('Implement task 1.', 'dforge:impl-sonnet-low', 2))
  }

  test('refuses a judge write to anything but the report its dispatch names, and allows that report', async ($, on) => {
    await started($, on)
    const refused = [
      `${WS}/amendments.md`,
      `${WS}/task-1-step.json`,
      '/home/me/code/shop/docs/dforge/plans/2026-10-28-plan.md',
      '/home/me/code/shop/src/index.ts',
      '/etc/passwd',
      `${WS}/task-1-report.md`,
      `${WS}/task-2-review-report.md`,
      'task-1-review-report.md',
      `${WS}/../amendments.md`,
      `${WS}/other/../task-1-review-report.md`,
    ]
    const tools = ['Write', 'Edit', 'MultiEdit', 'NotebookEdit']
    const got: (string | undefined)[] = []
    const want: string[] = []
    for (const path of refused) {
      for (const tool of tools) {
        got.push((await write($, 'judge-1', path, tool)).deny)
        want.push(`dforge: a review seat writes only the report file its dispatch names (${REVIEW}); ${path} is not one.`)
      }
    }
    expect(got).toEqual(want)
    expect(await Promise.all(tools.map(async tool => (await write($, 'judge-1', REVIEW, tool)).deny))).toEqual([undefined, undefined, undefined, undefined])
    expect((await write($, 'judge-1', `${WS}/./task-1-review-report.md`)).deny).toBeUndefined()
    // Only the four write tools are looked at.
    expect((await $.tool.call({ tool: 'Read', file_path: `${WS}/amendments.md`, agentId: 'judge-1' } as never)).deny).toBeUndefined()
  })

  test('lists a refused write with the other refusals', async ($, on) => {
    await started($, on)
    await write($, 'judge-1', `${WS}/amendments.md`)
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    expect(await ui.find({ type: 'Text', text: /✗ Write: dforge: a review seat writes only the report file/ })).toBeDefined()
  })

  test('leaves an implementer, the main loop and an unknown loop alone', async ($, on) => {
    await started($, on)
    expect((await write($, 'impl-1', `${WS}/amendments.md`)).deny).toBeUndefined()
    expect((await write($, undefined, `${WS}/amendments.md`)).deny).toBeUndefined()
    expect((await write($, 'workflow-agent-9', `${WS}/amendments.md`)).deny).toBeUndefined()
  })

  test('lists every report path the dispatch names under a state root, and none that lies elsewhere', async ($, on) => {
    const second = `${WS}/task-1-report.md`
    await started($, on, [REVIEW, second, '/tmp/elsewhere-report.md', 'docs/relative-report.md', `${WS}/../escape-report.md`, `${WS}/task-9-report.md.bak`])
    expect((await write($, 'judge-1', second)).deny).toBeUndefined()
    expect((await write($, 'judge-1', '/tmp/elsewhere-report.md')).deny).toBe(`dforge: a review seat writes only the report file its dispatch names (${REVIEW}, ${second}); /tmp/elsewhere-report.md is not one.`)
  })

  test('a judge whose dispatch names no report file may write no file', async ($, on) => {
    world(on, { tokens: 10_000, agentIds: ['judge-1'] })
    on('agent.list', () => ({ value: [] }) as never)
    await $.session.start(START)
    await $.agent.spawn(dispatch('Review task 1 and reply in 10 lines.', 'dforge:judge-opus', 1))
    expect((await write($, 'judge-1', REVIEW)).deny).toBe(`dforge: a review seat writes only the report file its dispatch names (none); ${REVIEW} is not one.`)
  })

  test('takes a judge the spawn record does not hold from $.agent.list()', async ($, on) => {
    world(on, { tokens: 10_000 })
    on('agent.list', () => ({ value: [{ id: 'listed-1', type: 'dforge:judge-opus', description: 'Review', status: 'running' }] }) as never)
    await $.session.start(START)
    expect((await write($, 'listed-1', REVIEW)).deny).toBe(`dforge: a review seat writes only the report file its dispatch names (none); ${REVIEW} is not one.`)
  })

  test('refuses a report reached through a symlinked directory or itself a symlink', async ($, on) => {
    const linkedDir = `${STATE}/sdd/linked`
    const linkedFile = `${WS}/task-2-review-report.md`
    const through = `${linkedDir}/task-1-review-report.md`
    await started($, on, [REVIEW, linkedFile, through], {
      files: {
        [linkedDir]: { text: '', kind: 'dir', isLink: true },
        [linkedFile]: { text: 'x', isLink: true },
      },
    })
    expect((await write($, 'judge-1', through)).deny).toMatch(GUARD)
    expect((await write($, 'judge-1', linkedFile)).deny).toMatch(GUARD)
    expect((await write($, 'judge-1', REVIEW)).deny).toBeUndefined()
  })

  test('takes the roots from the checkout and the primary, and a moved checkout', async ($, on) => {
    const world1: World = { tokens: 10_000, agentIds: ['judge-1', 'judge-2', 'judge-3'], checkout: '/home/me/code/shop-wt', primary: '/home/me/code/shop' }
    world(on, world1)
    on('agent.list', () => ({ value: [] }) as never)
    await $.session.start(START)
    const fromWorktree = '/home/me/code/shop-wt/.dforge/sdd/p/task-1-review-report.md'
    const fromPrimary = '/home/me/code/shop/.dforge/sdd/p/task-1-review-report.md'
    await $.agent.spawn(dispatch(`Write your report to ${fromWorktree} and ${fromPrimary}.`, 'dforge:judge-sonnet-high', 1))
    expect((await write($, 'judge-1', fromWorktree)).deny).toBeUndefined()
    expect((await write($, 'judge-1', fromPrimary)).deny).toBeUndefined()
    // The session moves into another worktree: its .dforge is a root from then on.
    world1.checkout = '/home/me/code/shop-wt2'
    await $.tool.call({ tool: 'EnterWorktree' } as never)
    const moved = '/home/me/code/shop-wt2/.dforge/sdd/p/task-1-review-report.md'
    await $.agent.spawn(dispatch(`Write your report to ${moved}.`, 'dforge:judge-sonnet-high', 2))
    expect((await write($, 'judge-2', moved)).deny).toBeUndefined()
    // A path under no root is not captured.
    await $.agent.spawn(dispatch(`Write your report to ${fromWorktree.replace('shop-wt', 'other')}.`, 'dforge:judge-sonnet-high', 3))
    expect((await write($, 'judge-3', fromWorktree.replace('shop-wt', 'other'))).deny).toMatch(GUARD)
  })

  test('compares a Windows path without regard to slashes, case or the drive letter case', async ($, on) => {
    const root = 'C:/Users/me/shop'
    world(on, { tokens: 10_000, agentIds: ['judge-1'], checkout: root, primary: root })
    on('agent.list', () => ({ value: [] }) as never)
    await $.session.start(START)
    await $.agent.spawn(dispatch('Write your report to C:\\Users\\me\\shop\\.dforge\\sdd\\p\\task-1-review-report.md and reply.', 'dforge:judge-sonnet-high', 1))
    expect((await write($, 'judge-1', 'c:/users/ME/shop/.dforge/sdd/p/task-1-review-report.md')).deny).toBeUndefined()
    expect((await write($, 'judge-1', 'C:\\Users\\me\\shop\\.dforge\\sdd\\p\\task-1-review-report.md')).deny).toBeUndefined()
    expect((await write($, 'judge-1', 'C:\\Users\\me\\shop\\.dforge\\sdd\\p\\amendments.md')).deny).toMatch(GUARD)
  })

  test('keeps a running judge in the spawn record past fifty later dispatches', async ($, on) => {
    world(on, { tokens: 10_000, agentIds: ['judge-1', ...Array.from({ length: 55 }, (_, i) => `impl-${i}`)] })
    on('agent.list', () => ({ value: [] }) as never)
    await $.session.start(START)
    await $.agent.spawn(dispatch(`Write your report to ${REVIEW}.`, 'dforge:judge-sonnet-high', 1))
    for (let n = 0; n < 55; n++) await $.agent.spawn(dispatch('Implement a task.', 'dforge:impl-sonnet-low', n + 2))
    expect((await write($, 'judge-1', `${WS}/amendments.md`)).deny).toMatch(GUARD)
    expect((await write($, 'judge-1', REVIEW)).deny).toBeUndefined()
  })

  test('refuses a judge write when the check itself fails, whatever guardAttribution says', async ($, on) => {
    await started($, on, [REVIEW], { config: { guardAttribution: false } }, () => {
      throw new Error('agent list unavailable')
    })
    const ran = await write($, 'judge-1', REVIEW)
    expect(ran.deny).toMatch(/^dforge: the review-seat write guard could not check this write \(.+\); it is refused\.$/)
    expect((await write($, 'impl-1', `${WS}/amendments.md`)).deny).toBeUndefined()
    expect((await write($, undefined, `${WS}/amendments.md`)).deny).toBeUndefined()
  })

  test('a failing agent list blocks no implementer write while the attribution guard is on', async ($, on) => {
    await started($, on, [REVIEW], { config: { guardAttribution: true } }, () => {
      throw new Error('agent list unavailable')
    })
    expect((await write($, 'judge-1', REVIEW)).deny).toMatch(/^dforge: the review-seat write guard could not check this write \(.+\); it is refused\.$/)
    expect((await write($, 'impl-1', `${WS}/notes.md`)).deny).toBeUndefined()
    expect((await write($, undefined, `${WS}/notes.md`)).deny).toBeUndefined()
  })
})
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `cd plugins/dforge && timeout 300 /root/.local/bin/claude plugin test . 2>&1 | grep -E "review seat write guard|^ *[0-9]+ (pass|fail)"` (the run takes about a minute).
Expected: 10 of the 12 tests in `review seat write guard` FAIL with `Received: undefined` where a refusal string was expected (no guard exists yet). `leaves an implementer, the main loop and an unknown loop alone` passes now and must keep passing; `a failing agent list blocks no implementer write while the attribution guard is on` fails now only on its judge line (there is no guard to refuse it). Every test outside the new block still passes.

- [ ] **Step 4: Implement the guard**

All in `plugins/dforge/hooks/cockpit/register.tsx` and `plugins/dforge/types/index.d.ts`. The code that already exists keeps its behaviour for every call the guard does not touch.

1. **Type.** `CockpitSpawn` gets `reports?: string[]`, with a one-line comment: for a judge seat, the report paths its dispatch named under a state root, as written; the only files it may write. Do not write the plugin prefix and `judge-` together as one literal anywhere in these two files, code or comment: `scripts/validate-repository.mjs` reads `dforge:judge-` as a reference to a missing agent and fails.
2. **Judge test.** `isJudgeSeat(seat)` is true when the seat is defined, `isDforge(seat)` holds and the text after the first colon begins with `judge-`. Module constant `REVIEW_WRITE_TOOLS` is `['Write', 'Edit', 'MultiEdit', 'NotebookEdit']`.
3. **Path helpers** (new functions above `attributionLine`; none touches the engine):
   - `canonPath(path)`: backslashes become slashes; a leading `/<letter>/` (one letter, the Git Bash spelling of a drive) becomes `<letter>:/`; a leading `<letter>:/` keeps the drive letter, lower-cased; the rest must start with `/`; empty and `.` segments are dropped; the result is `/a/b` or `c:/a/b`. It returns `null` for a relative path and for any path holding a `..` segment. Refusing `..` outright is stricter than resolving it lexically, on purpose: `<dir>/x/../f` is not `<dir>/f` when `x` is a symbolic link, and the guard cannot see that. Add one short comment saying so.
   - `pathKey(canon)`: the canonical path, lower-cased when it starts with a drive letter. Windows is recognised from the paths themselves (the engine exposes no platform), so a `c:/` path compares without regard to case and a POSIX path compares exactly.
   - `reviewRoots()`: the canonical `<S.where.checkout>/.dforge` and `<S.where.primary>/.dforge` that are known (`readPlace` and `readWhere` already fill both, and a worktree move refreshes the checkout), possibly none.
   - `rootOf(canon, roots)`: the first root whose key plus `/` begins the path's key, or `undefined`.
   - `reportPathsIn(prompt, roots)`: scan the prompt for runs of characters that (a) start with a slash, or with a drive letter, a colon and a slash or backslash, and are not preceded by a letter, digit, underscore, dot, tilde, slash, backslash or hyphen (so `docs/x-report.md` and `./x-report.md` do not match from an inner slash); (b) continue over characters other than whitespace, quotes, backticks, `<`, `>`, parentheses, `|`, `*`, `?`, square and curly brackets, commas and semicolons; (c) end in `-report.md` and are not followed by a letter, digit, underscore or hyphen, nor by a dot and one of those (`x-report.md.bak` is not a match; the full stop that ends a sentence is allowed). Keep each match once, as written, when `canonPath` gives a path and `rootOf` finds a root for it.
4. **`agent.spawn` hook.** When `isJudgeSeat(e.subagentType)`, the `spawn` record carries `reports: reportPathsIn(e.prompt, reviewRoots())`, an empty array when the dispatch names none. Other seats get no `reports` field. Replace `.slice(-50)` on the `spawns` update with a trim that, past 50 entries, drops the oldest entries whose `isDone` is true only; a running entry is never dropped (the spec relies on that, and a plain `slice(-50)` can drop a judge that is still running).
5. **Check.** `judgeWriteDenial($, tool, e)` returns the refusal text or `null`:
   - find the `spawns` record for `e.agentId`; call `await $.agent.list()` and find the entry whose `id` is `e.agentId`. When the list call rejects: if the record's seat is a judge seat, let the rejection propagate (the `.catch` below refuses the write); otherwise return `null`, so a failing list never blocks an implementer's or any other loop's write. If neither the record's seat nor the entry's `type` is a judge seat, return `null` (a workflow agent or an engine fork is untouched);
   - the target is `e.notebook_path` for `NotebookEdit` and `e.file_path` for the other three, `''` when it is not a string; the allowed paths are the record's `reports`, `[]` when there is no record;
   - `isNamedReport($, target, allowed)` is true only when all of these hold: `canonPath(target)` is not `null` and its key equals the key of some allowed path's `canonPath`; `rootOf` finds a root for it among the current `reviewRoots()` (none known means refuse); and, walking from the root's first child down to the target itself, `$.fs.stat(<canonical spelling of that prefix>)` never answers `isLink: true` (a rejected stat means the path does not exist and counts as not a link). The root itself is trusted;
   - otherwise return exactly the Guard refusal of Contracts: `dforge: a review seat writes only the report file its dispatch names (<allowed paths as written, joined with ", ", or none>); <target as given> is not one.`
   - Spell every engine call as `$.noun.event(...)` at the call site; the mod loader rejects an event passed or stored as a value.
6. **`tool.call` hook.** Immediately after `const tool = String(e.tool)` and before the attribution guard: when `e.agentId !== undefined` and the tool is in `REVIEW_WRITE_TOOLS`, run `judgeWriteDenial`; on a refusal, append `{ at, tool, line: <the refusal> }` to `refusals` exactly as the attribution guard does and return `{ deny: <the refusal> }`. No other call looks anything up.
7. **`.catch` of that hook.** Before its existing line, when `next.called` is false, `e.agentId` is set, the tool is a write tool and the `spawns` record for `e.agentId` is a judge seat, return `{ deny: 'dforge: the review-seat write guard could not check this write (<next.error.message, or next.error.kind when it has none>); it is refused.' }`, whatever `guardAttribution` says. Everything else in the `.catch` is unchanged.

- [ ] **Step 5: Run the tests to verify they pass**

Run from the repository root:
```bash
timeout 300 /root/.local/bin/claude plugin test plugins/dforge
timeout 60 /root/.local/bin/claude plugin validate plugins/dforge
timeout 120 node scripts/validate-repository.mjs
```
Expected: the first prints `0 fail` and a pass count 12 above what it printed before this task; the second ends `Validation passed`; the third ends `Repository catalogs, manifests, versions, bundled links and the settings schema are valid.`

- [ ] **Step 6: Run the live probe against the real guard and write the note**

```bash
bash "$PROBE/run.sh" "$PROBE" p "$PWD/plugins/dforge" "$PROBE/final-p.jsonl"
grep -o 'a review seat writes only the report file its dispatch names ([^)]*); [^"]* is not one\.' "$PROBE/final-p.jsonl" | head -1
bash "$PROBE/run.sh" "$PROBE" tui "$PWD/plugins/dforge" "$PROBE/final-tui.txt"
grep -c 'a review seat writes only the report file its dispatch names' "$PROBE/final-tui.txt"
tmux ls 2>&1 | grep -c probe-judge-guard
```

Expected, for each mode: `run.sh` lists only `task-1-review-report.md` (the outside write did not land, the report write did); the `-p` grep prints the guard's sentence naming the one `-report.md` path and `…/amendments.md`; the pane count is at least 1; the last command prints `0`. A judge that skipped the write proves nothing: repeat that mode once.

Create `docs/dforge/notes/2026-10-28-judge-write-guard-probe.md` with these sections, pasting the trimmed output of each run (keep paths, drop nothing that decides a result, never paste credentials):

- `# Judge write guard probe`, then the date, `/root/.local/bin/claude --version`, the commit the tree started from and `git status --short` of the files this task changed.
- `## Setup`: the isolation (own HOME, XDG and CLAUDE_CONFIG_DIR, only the login copied, removed afterwards), the two modes, the dispatch text (`$PROBE/prompt.txt`).
- `## Before the build`: the throwaway guard's description and the `PROBE-DENY` line from each mode, with `ls` of the workspace.
- `## After the build`: the guard's refusal sentence from each mode and the `ls` of the workspace.
- `## Residuals`: (1) a session where the cockpit mod does not load runs without the guard (the spec's accepted residual); this probe shows the mod loads in `claude -p --plugin-dir` and in an interactive session on this host and says nothing about older Claude Code; (2) the review dispatch also names the implementer's report (`task-<N>-report.md`, which ends in `-report.md`), so a judge may rewrite that file as well as its own report; (3) on Windows, task-step names report paths in the `C:/…` long form (`dforge_workspace`, `scripts/lib/roots.sh:21-34`), the form the cockpit's roots take, and `canonPath` also maps a Git Bash `/c/…` spelling to `c:/…`; no Windows host ran this probe; (4) the guard fails closed on a spelling mismatch, a `..` segment and a symlink, never on a missing root.
- `## Verdict`: `HOLDS` when both modes refused the outside write and allowed the report, else `BLOCKED`.

Then remove the probe: `rm -rf "$PROBE"`.

- [ ] **Step 7: Commit**

```bash
git add plugins/dforge/hooks/cockpit/register.tsx plugins/dforge/types/index.d.ts plugins/dforge/tests/cockpit.test.ts docs/dforge/notes/2026-10-28-judge-write-guard-probe.md
git commit -m "feat(dforge): limit judge seats to their reports"
```

### Task 2: Stop gate retry and evidence checks

**Files:**
- Modify: `plugins/dforge/scripts/impl-stop-gate`
- Test: `plugins/dforge/tests/impl-stop-gate.test.sh`

**Interfaces:**
- Consumes: nothing from another task.
- Produces: nothing another task consumes. The counter file `<state>/impl-stop-gate/<agent_id>` keeps its four lines; line 3 now also reads `awaiting` (written by every block, cleared by any stop that passes).

**Items:** 35, 51, 53

**Depends on:** none

**Implementer:** dforge:impl-sonnet-high
**Evaluation:** files 1 - spec 2 - coupling 0 - risk 2 = 5

The gate (`SubagentStop` hook, exit 2 blocks, the stderr line goes back to the agent) now checks a blocked agent's next stop even when the reply has no `**Status:**` line, counts only the last `## Verified` section of a report, and its test no longer reads the host's `XDG_STATE_HOME`.

- [ ] **Step 1: Show the isolation leak, then write the failing tests**

First show row 35 on the unedited test file, from the repository root:

```bash
X=$(mktemp -d); XDG_STATE_HOME=$X timeout 120 bash plugins/dforge/tests/impl-stop-gate.test.sh 2>&1 | grep -E "^FAIL|passed"; find "$X" -mindepth 1 | wc -l; rm -rf "$X"
```
Expected: `63 passed, 7 failed` (seven `FAIL` lines, all about the fallback log: `the malformed input of the first checks was logged`, `a stop that the gate has no reason to look at logs nothing`, `unparseable input passes and is logged`, `without jq the gate passes and is logged`, `a counter that cannot be kept lets the stop through and logs why`, `a missing working directory lets the stop through and logs why`, `a value with a newline or an escape logs one clean line`) and `2` (the gate wrote `dforge/impl-stop-gate.log` under the caller's `XDG_STATE_HOME`).

Then make three edits to `plugins/dforge/tests/impl-stop-gate.test.sh`.

(a) Row 35. The `unset` line near the top gains `XDG_STATE_HOME`:

```bash
unset CLAUDE_CONFIG_DIR CLAUDE_CODE_SESSION_ID AR_SESSION DFORGE_BUDGET CLAUDE_PROJECT_DIR XDG_STATE_HOME
```

(b) Row 53. Insert this after the `check "a bullet outside ## Verified does not count" …` line and before the line `printf '# Task 4\n' > "$TMP/bare.md"`:

```bash
{ printf '## Verified\n- `make test` — pass: 3 passed, 0 failed\n\n## Verified\nFix round: nothing re-run.\n\n## Discovered issues (not fixed)\nNone.\n\n## Assumptions made\nNone.\n'; } > "$TMP/stale-verified.md"
gate "$(input dforge:impl-sonnet-high a-11 $'**Status:** DONE\nReport: '"$TMP/stale-verified.md")"
check "a valid bullet in an earlier ## Verified does not count: exit 2" "$CODE|$(has "$ERR" '`## Verified` holds no bullet like')" "2|1"
{ printf '## Verified\nfirst round, nothing run\n\n## Verified\n- `make test` — pass: 3 passed, 0 failed\n\n## Discovered issues (not fixed)\nNone.\n\n## Assumptions made\nNone.\n'; } > "$TMP/fixed-verified.md"
gate "$(input dforge:impl-sonnet-high a-12 $'**Status:** DONE\nReport: '"$TMP/fixed-verified.md")"
check "a valid bullet in the last ## Verified passes" "$CODE|$OUT|$ERR" "0||"
```

(c) Row 51. Insert this section before the line `# --- no test runner, no network ---` (the fallback log variable `FALLBACK` is defined earlier in the file):

```bash
# --- a blocked agent's next stop is checked even without a status ---
awaiting() { sed -n 3p "$STATE/impl-stop-gate/$1"; }
FALLBACK_LINES=$(wc -l < "$FALLBACK" | tr -d ' ')
BAD=$'**Status:** DONE\nFirst attempt, no report.'
blocked() { gate "$(input dforge:impl-sonnet-high "$1" "$BAD")"; }

blocked agent-s1
check "a block marks the counter awaiting" "$CODE|$(awaiting agent-s1)" "2|awaiting"
gate "$(input dforge:impl-sonnet-high agent-s1 $'Retry without a status line.\nReport: '"$TMP/no-verified.md")"
check "a status-less retry with an incomplete report blocks" "$CODE|$(has "$ERR" 'the report lacks `## Verified`')" "2|1"
check "and the counter stays awaiting" "$(awaiting agent-s1)" "awaiting"
gate "$(input dforge:impl-sonnet-high agent-s1 $'Second retry, still no status.\nReport: '"$R")"
check "a status-less retry with a complete report passes and clears awaiting" "$CODE|$OUT|$ERR|$(awaiting agent-s1)" "0|||"
gate "$(input dforge:impl-sonnet-high agent-s1 'A later reply of the resumed agent.')"
check "a later status-less reply of that agent passes" "$CODE|$OUT|$ERR" "0||"

blocked agent-s2
gate "$(input dforge:impl-sonnet-high agent-s2 $'Retry without a status line.\nReport: '"$R")"
check "one block, then a status-less retry with a complete report: exit 0" "$CODE|$OUT|$ERR" "0||"

blocked agent-s3
gate "$(input dforge:impl-sonnet-high agent-s3 'Done, everything works.')"
check "a status-less retry with no Report line blocks" "$CODE|$(has "$ERR" 'your reply has no `Report: <absolute path>` line')" "2|1"

blocked agent-s4
gate "$(input dforge:impl-sonnet-high agent-s4 $'Status: blocked\nI need a decision.')"
check "a retry saying Status: blocked passes and clears awaiting" "$CODE|$OUT|$ERR|$(awaiting agent-s4)" "0|||"
blocked agent-s4b
gate "$(input dforge:impl-sonnet-high agent-s4b $'status: needs_context\nWhich branch?')"
check "a retry saying status: needs_context passes" "$CODE|$OUT|$ERR|$(awaiting agent-s4b)" "0|||"
blocked agent-s4c
gate "$(input dforge:impl-sonnet-high agent-s4c $'Status:\tBlocked\nNeeds a key.')"
check "a tab after the colon passes too" "$CODE|$OUT|$ERR|$(awaiting agent-s4c)" "0|||"

printf '# Report\n\n**Status:** BLOCKED\nNeeds a key.\n' > "$TMP/blocked-report.md"
blocked agent-s5
gate "$(input dforge:impl-sonnet-high agent-s5 $'Report: '"$TMP/blocked-report.md")"
check "a status-less retry whose report opens with **Status:** BLOCKED passes" "$CODE|$OUT|$ERR|$(awaiting agent-s5)" "0|||"
printf '# Report\n\n**Status:** DONE\n\nlater\n**Status:** BLOCKED\n' > "$TMP/done-then-blocked.md"
blocked agent-s5b
gate "$(input dforge:impl-sonnet-high agent-s5b $'Report: '"$TMP/done-then-blocked.md")"
check "only the report's first status line counts: a later BLOCKED does not pass" "$CODE|$(has "$ERR" 'the report lacks `## Verified`')" "2|1"

blocked agent-s6
gate "$(input dforge:impl-sonnet-high agent-s6 "$DONE")"
check "a block, then a complete DONE: exit 0 and awaiting cleared" "$CODE|$OUT|$ERR|$(awaiting agent-s6)" "0|||"
gate "$(input dforge:impl-sonnet-high agent-s6 'Thanks, noted.')"
check "and a status-less reply after it passes" "$CODE|$OUT|$ERR" "0||"

blocked agent-s7
gate "$(input dforge:impl-sonnet-high agent-s7 $'**Status:** BLOCKED\nReport: /nonexistent/report.md')"
check "a block, then **Status:** BLOCKED: exit 0 and awaiting cleared" "$CODE|$OUT|$ERR|$(awaiting agent-s7)" "0|||"
gate "$(input dforge:impl-sonnet-high agent-s7 'Still here.')"
check "and a status-less reply after it passes" "$CODE|$OUT|$ERR" "0||"

blocked agent-s8
gate "$(input dforge:impl-sonnet-high agent-s8 $'First retry.\nReport: '"$TMP/no-verified.md")"
gate "$(input dforge:impl-sonnet-high agent-s8 $'Second retry.\nReport: '"$TMP/no-verified.md")"
check "after two blocks a distinct status-less failing stop passes" "$CODE|$OUT|$ERR|$(awaiting agent-s8)" "0|||passed"

gate "$(input dforge:impl-sonnet-high agent-never 'Fixed the typo in README.md.')"
check "a status-less reply from an agent never blocked passes" "$CODE|$OUT|$ERR" "0||"
check "and writes no counter" "$([ -e "$STATE/impl-stop-gate/agent-never" ] && echo yes || echo no)" "no"
gate "$(fjq -nc --arg m 'Fixed it.' '{cwd:"/nonexistent/dir",agent_id:"agent-nocwd",agent_type:"dforge:impl-haiku",last_assistant_message:$m}')"
check "a status-less stop that cannot enter cwd passes" "$CODE|$OUT|$ERR" "0||"
check "none of these status-less passes added a fallback-log line" "$(wc -l < "$FALLBACK" | tr -d ' ')" "$FALLBACK_LINES"

```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd plugins/dforge && timeout 120 bash tests/impl-stop-gate.test.sh 2>&1 | grep -E "^FAIL|passed"`
Expected: `86 passed, 7 failed`, the failures being `a valid bullet in an earlier ## Verified does not count: exit 2`, `a block marks the counter awaiting`, `a status-less retry with an incomplete report blocks`, `and the counter stays awaiting`, `a status-less retry with no Report line blocks`, `only the report's first status line counts: a later BLOCKED does not pass` and `after two blocks a distinct status-less failing stop passes`. (A status-less retry passes unchecked today, a block leaves line 3 empty, and the awk accepts a bullet from any `## Verified` section.)

- [ ] **Step 3: Implement**

All in `plugins/dforge/scripts/impl-stop-gate`; the existing block, pass-through and fallback-log behaviour stays as it is.

1. **Order of the early checks.** Keep `jq` and input checks as they are. After the `impl-` agent-type test, exit 0 when `agent_id` is empty (it used to come after the status test; the result is the same). Move `sha256()` above the status tests, and turn the counter's location and read into functions defined before them: one that enters `cwd`, runs `dforge-path state` and sets the counter path `<state>/impl-stop-gate/<agent_id>`, recording why in a variable when it cannot (`cannot enter <cwd>`, `cannot find the state directory`) and returning 1; one that reads the four counter lines with the same defaults and sanitising as today. The blocking path at the end of the script keeps calling `unkept` with that recorded reason, so a blocking stop that cannot keep a counter is still logged to the fallback log as before.
2. **Classify the stop.** A *DONE reply* is a message matching the existing `**Status:** DONE|DONE_WITH_CONCERNS` pattern. A message with a `**Status:**` line that is not a DONE reply (BLOCKED, NEEDS_CONTEXT or any other word) is a *status stop*. A message with no `**Status:**` line is a *status-less stop*.
3. **Status stop.** Passes as today. If the counter exists and its line 3 reads `awaiting`, rewrite it with line 3 empty and lines 1, 2 and 4 unchanged, then exit 0. A location failure or a missing counter exits 0 silently.
4. **Status-less stop.** Look the counter up quietly: a `cwd` that cannot be entered, no state directory, no counter or a line 3 other than `awaiting` exits 0 with no fallback-log line, as an agent never blocked does today. Otherwise the agent is awaiting, and:
   - if the message text matches `(^|[^A-Za-z])\**Status:\**[[:blank:]]*(BLOCKED|NEEDS_CONTEXT)`, case-insensitively, per line, the stop passes (use `[[:blank:]]`, not `\t`, inside the bracket: POSIX `grep -E` does not read `\t` there);
   - else if the last `Report:` line names a file (resolved exactly as the existing check resolves it: backslashes to slashes, `cygpath -u` when present) whose first line containing `**Status:**`, CRs dropped, matches that same pattern, the stop passes;
   - a passing awaiting stop clears line 3 as in step 3 and exits 0;
   - otherwise it is checked as a DONE reply: the same `Report:` line, file and section checks, the same counter rules (same-hash stop does not raise the count, the pass-through after two blocks and after five fires writing `passed` and the log line) and the same block message.
5. **DONE reply.** Checked as today. When the checks find nothing missing, and the counter exists with line 3 `awaiting`, clear line 3 before exiting 0; a location failure or a missing counter exits 0 silently, and a passing stop for an agent with no counter writes none.
6. **Every block** writes `awaiting` on line 3 (`count`, `last`, `awaiting`, `fires`) where it wrote an empty line.
7. **Row 53.** In the awk program that looks for the bullet, reset `found` to 0 at every `## Verified` heading, so only the bullets of the last `## Verified` section count.
8. Update the header comment: line 3 of the counter file reads `awaiting` after a block, is cleared by any stop that passes and `passed` after a pass-through; a blocked agent's next stop is checked as a DONE reply when it has no `**Status:**` line unless it says BLOCKED or NEEDS_CONTEXT in its text or its report's first status line; only the last `## Verified` section counts.

- [ ] **Step 4: Run the tests to verify they pass**

Run:
```bash
cd plugins/dforge
timeout 120 bash tests/impl-stop-gate.test.sh 2>&1 | grep -vE "^ok"
X=$(mktemp -d); XDG_STATE_HOME=$X timeout 120 bash tests/impl-stop-gate.test.sh 2>&1 | tail -1; find "$X" -mindepth 1 | wc -l; rm -rf "$X"
cd ../.. && timeout 120 node scripts/validate-repository.mjs
```
Expected: the first prints a blank line and `93 passed, 0 failed`; the second prints `93 passed, 0 failed` and then `0` (nothing was written under the caller's `XDG_STATE_HOME`); the third ends `Repository catalogs, manifests, versions, bundled links and the settings schema are valid.`

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/scripts/impl-stop-gate plugins/dforge/tests/impl-stop-gate.test.sh
git commit -m "fix(dforge): check a blocked agent's retry"
```

### Task 3: Eval harness isolation and manifest parsing

**Files:**
- Modify: `evals/tiers/lib/pipeline.mjs` (the `HOST_ENV` comment, `CREDENTIALS`, `isolatedEnv`)
- Modify: `evals/tiers/lib/pipeline-manifest.mjs` (`fixRounds`)
- Test: `evals/tiers/tests/pipeline.test.mjs`
- Test: `evals/tiers/tests/pipeline-manifest.test.mjs`

**Interfaces:**
- Consumes: None.
- Produces: None. `isolatedEnv(dir)` and `fixRounds({ result, merge, allowed, own })` keep their signatures and return shapes; only what they pass and how they parse changes.

**Items:** 34, 59

**Depends on:** none

**Implementer:** dforge:impl-sonnet-medium
**Evaluation:** files 1 - spec 2 - coupling 0 - risk 1 = 4

- [ ] **Step 1: Write the failing tests**

In `evals/tiers/tests/pipeline.test.mjs`, append this test after the last test in the file ("the child sees the allowlisted host variables and the API credentials, and nothing else"). It uses the file's existing imports, `row`, `root`, `fx` and `inside`; the child is a small script that dumps its environment, as the neighbouring tests use scripts for their own cases.

```js
test('the child gets no cloud-provider switches from the host, and every temp variable points into its run directory', async () => {
  const dump = join(fx.top, 'child-env.txt');
  const script = join(fx.top, 'claude-dumps-env');
  writeFileSync(script, `#!/bin/sh\ncat >/dev/null\nenv > "${dump}"\nprintf '%s' '{"type":"result","total_cost_usd":0.5,"is_error":false,"result":"done"}'\n`);
  chmodSync(script, 0o755);
  const hostTmp = join(fx.top, 'host-tmp');
  mkdirSync(hostTmp);
  const host = { CLAUDE_CODE_USE_BEDROCK: '1', CLAUDE_CODE_USE_VERTEX: '1', TMP: hostTmp, TEMP: hostTmp };
  const saved = { ...Object.fromEntries(Object.keys(host).map(key => [key, process.env[key]])), TIER_EVAL_CLAUDE: process.env.TIER_EVAL_CLAUDE };
  Object.assign(process.env, host, { TIER_EVAL_CLAUDE: script });
  try {
    await runPipelineCase({ c: row, arm: 'baseline@1111111', ref: fx.planned, run: 8, root });
    const env = Object.fromEntries(readFileSync(dump, 'utf8').split('\n').filter(line => line.includes('=')).map(line => [line.slice(0, line.indexOf('=')), line.slice(line.indexOf('=') + 1)]));
    assert.ok(!('CLAUDE_CODE_USE_BEDROCK' in env), 'CLAUDE_CODE_USE_BEDROCK reached the child');
    assert.ok(!('CLAUDE_CODE_USE_VERTEX' in env), 'CLAUDE_CODE_USE_VERTEX reached the child');
    for (const key of ['TMPDIR', 'TMP', 'TEMP']) assert.ok(inside(env[key] ?? ''), `${key} is ${env[key]}`);
    assert.equal(env.TMP, env.TMPDIR);
    assert.equal(env.TEMP, env.TMPDIR);
  } finally {
    for (const [key, value] of Object.entries(saved)) { if (value === undefined) delete process.env[key]; else process.env[key] = value; }
  }
});
```

In `evals/tiers/tests/pipeline-manifest.test.mjs`, make two edits. First, directly below the line `const own = new Set(['feat: one', 'feat: two']);` add three commits that come after `end`, so no existing test's range reaches them, and a set of their task subjects. The fix commit's subject ends in `@@` and the next task's subject contains `@@` mid-text:

```js
const three = commit({ 'src/three.sh': 'echo 3' }, 'feat: three');
commit({ 'src/three.sh': 'echo 3b' }, 'fix: escape @@');
const tail = commit({ 'src/four.sh': 'echo 4' }, 'feat: four @@ done');
const ownAt = new Set(['feat: three', 'feat: four @@ done']);
```

Second, directly above the line `const c = (plan, task, fixRounds) => …`, add:

```js
test('fixRounds counts a commit whose subject contains @@ as one commit', () => {
  assert.equal(fixRounds({ result: three, merge: tail, allowed: ['src/three.sh'], own: ownAt }), 1);
});
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd evals/tiers && timeout 120 node --test tests/pipeline.test.mjs tests/pipeline-manifest.test.mjs`
Expected: exactly two failures and 18 passes. The new `fixRounds` test fails with `0 !== 1` (the `@@` in the subject cuts the commit in two and the file list lands in a block with no subject). The new pipeline test fails with `CLAUDE_CODE_USE_BEDROCK reached the child`.

- [ ] **Step 3: Implement**

1. `evals/tiers/lib/pipeline.mjs`, the `CREDENTIALS` regular expression: drop the `CLAUDE_CODE_USE_(BEDROCK|VERTEX)$` alternative, so only the `ANTHROPIC_` prefix and the exact name `CLAUDE_CODE_OAUTH_TOKEN` pass. The comment above `HOST_ENV` already says cloud tokens stay out; add `TMP` and `TEMP` to its list of variables `isolatedEnv` sets (it now names HOME, XDG_*, CLAUDE_CONFIG_DIR and TMPDIR).
2. `isolatedEnv(dir)`: in the object literal that follows the spread of the kept host variables, add `TMP` and `TEMP` with the same value as `TMPDIR` (`join(dir, 'tmp')`), so they overwrite the host's values. Leave the `HOST_ENV` pattern and the directory-creating loop as they are: `TMPDIR`'s directory is the same directory. Update the function's leading comment to say the child also gets its own temp directories.
3. `evals/tiers/lib/pipeline-manifest.mjs`, `fixRounds`: change the `git log` format from `--format=@@%H%x09%s` to `--format=%x00%H%x09%s`, and split the output on the NUL character (`'\0'`) instead of `'@@'`. Keep the `.filter(Boolean)` and the per-block parsing as they are. Add one short comment saying why: a NUL cannot occur in a commit subject, `@@` can.
4. Nothing else changes: `gradingFor`, `runPipelineCase` and the other exports keep their code.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd evals/tiers && timeout 120 node --test tests/pipeline.test.mjs tests/pipeline-manifest.test.mjs`
Expected: 20 passes, 0 failures.

Run: `timeout 290 node --test evals/tiers/tests/*.test.mjs` (from the repository root)
Expected: all pass (123 tests when this task was drafted), 0 failures.

- [ ] **Step 5: Commit**

```bash
git add evals/tiers/lib/pipeline.mjs evals/tiers/tests/pipeline.test.mjs
git commit -m "fix(evals): drop cloud switches from child env"
git add evals/tiers/lib/pipeline-manifest.mjs evals/tiers/tests/pipeline-manifest.test.mjs
git commit -m "fix(evals): split fix-round git log on NUL"
```

### Task 4: Doc pointers and test cleanups

**Files:**
- Modify: `plugins/dforge/scripts/draft-pack` (the final `rmdir`)
- Modify: `plugins/dforge/tests/draft-pack.test.sh`
- Modify: `plugins/dforge/skills/subagent-driven-development/references/process-graph.md`
- Modify: `plugins/dforge/skills/subagent-driven-development/SKILL.md` (the "older run's `R/5`" sentence in the After compaction block)
- Modify: `plugins/dforge/skills/subagent-driven-development/references/setup.md` (the ledger-recovery bullet)
- Modify: `plugins/dforge/skills/executing-plans/SKILL.md` (step 2 of the After compaction block)
- Modify: `plugins/dforge/skills/executing-plans/references/setup.md` (the ledger bullet)
- Modify: `plugins/dforge/skills/writing-plans/SKILL.md` (the "Ask first" paragraph under Parallel waves)
- Modify: `plugins/dforge/tests/review-depth.acceptance.test.sh` (the `SD=` line)
- Modify: `plugins/dforge/tests/review-depth-qa.acceptance.test.sh` (the `SD=` line and the `FN=` line)
- Modify: `plugins/dforge/tests/auto-default.test.sh` (the finishing negative check, and the new pins)
- Modify: `plugins/dforge/tests/impl-clauses.test.sh` (`says`)
- Modify: `plugins/dforge/tests/task-step-text.test.sh` (one pin, the process-graph label at the line `names "the process graph names the group template"`)
- Modify: `docs/dforge/notes/2026-10-28-pipeline-smoke.md`

**Interfaces:**
- Consumes: None.
- Produces: None. The pin edit in `task-step-text.test.sh` is forced by the label change in `process-graph.md` and touches only that one line; Tasks 5-7 run in later waves and add their own pins elsewhere in that file.

**Items:** 28, 45, 46, 47, 48, 50, 54, 56

**Depends on:** none

**Implementer:** dforge:impl-sonnet-medium
**Evaluation:** files 2 - spec 2 - coupling 0 - risk 0 = 4

- [ ] **Step 1: Write the failing tests**

In `plugins/dforge/tests/draft-pack.test.sh`, make two edits. Directly below the line `check "join: slices deleted" …` add:

```bash
check "join: the emptied drafts directory is gone too" "$([ -e "$REPO/.dforge/drafts" ] && echo present || echo gone)" "gone"
```

Directly above the line `reset 3` that precedes `check "tasks missing and no slices: exit 3"`, add a case showing another plan's slices keep the `drafts` directory:

```bash
reset 2; slice 1 2; mkdir -p "$REPO/.dforge/drafts/other"; printf 'x\n' > "$REPO/.dforge/drafts/other/tasks-1-1.md"
run --join docs/plan.md
check "another plan's slices: exit 0" "$code" "0"
check "another plan's slices: kept, with their drafts directory" "$(ls "$REPO/.dforge/drafts/other" 2>/dev/null)" "tasks-1-1.md"
```

In `plugins/dforge/tests/auto-default.test.sh`, add this block directly above the final `printf '\n%d passed, %d failed\n'` line. It runs after the file's `flat`, `says` and `lacks` helpers and its `$W` variable are defined, and it sets its own temporary directory:

```bash
# Docs pointers and test cleanups: pointers name the file that holds their target.
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
SDD_REFS="$P/skills/subagent-driven-development/references"
check "process-graph: no label points into ./references/" "$(grep -c '\./references/' "$SDD_REFS/process-graph.md")" "0"
for template in implementer-prompt group-reviewer-prompt task-reviewer-prompt ruling-prompt re-review-prompt; do
  names "process-graph: a label names ./$template.md" "$SDD_REFS/process-graph.md" "(./$template.md)"
done
says "subagent-driven-development: an older run's R/5 points at ledger.md" "$P/skills/subagent-driven-development/SKILL.md" '`R/5` maps as ledger.md §Recovery says'
says "subagent-driven-development setup: the Recovery table is in ledger.md" "$SDD_REFS/setup.md" 'the Recovery table in [ledger.md](ledger.md) §Recovery'
says "executing-plans: the Recovery table is in recovery.md" "$P/skills/executing-plans/SKILL.md" 'see the Recovery table in [recovery.md](references/recovery.md)'
says "executing-plans setup: the Recovery table is in recovery.md" "$P/skills/executing-plans/references/setup.md" 'the Recovery table in [recovery.md](recovery.md)'
lacks "no Recovery pointer goes through The Ledger" <(cat "$P/skills/subagent-driven-development/SKILL.md" "$SDD_REFS/setup.md" "$P/skills/executing-plans/SKILL.md" "$P/skills/executing-plans/references/setup.md") "under The Ledger"
lacks "no Recovery pointer names The Ledger's Recovery" "$P/skills/subagent-driven-development/SKILL.md" "The Ledger's Recovery"
check "the Recovery pointers resolve" "$([ -s "$SDD_REFS/ledger.md" ] && [ -s "$P/skills/executing-plans/references/recovery.md" ] && echo yes || echo no)" "yes"
says "writing-plans: the execution-strategy question is in design-phase.md" "$W" '[design-phase.md](../brainstorming/references/design-phase.md)'
lacks "writing-plans: the question is not named by a section of brainstorming's SKILL.md" "$W" 'dforge:brainstorming §Choosing the execution strategy'
check "the review-depth acceptance tests carry no unused SD= line" "$(cat "$HERE/review-depth.acceptance.test.sh" "$HERE/review-depth-qa.acceptance.test.sh" | grep -c '^SD=')" "0"
check "review-depth-qa builds the finishing text with flat_skill" "$(grep -c 'FN=\$(flat_skill "\$FIN")' "$HERE/review-depth-qa.acceptance.test.sh")" "1"

# impl-clauses.test.sh counts occurrences, so a clause written twice in one agent fails it.
mkdir -p "$TMP/clauses/tests" "$TMP/clauses/agents"
cp "$HERE/impl-clauses.test.sh" "$TMP/clauses/tests/"
cp "$P/agents"/impl-*.md "$TMP/clauses/agents/"
check "impl-clauses: an unmodified copy prints no FAIL line" "$(bash "$TMP/clauses/tests/impl-clauses.test.sh" 2>&1 | grep -c '^FAIL')" "0"
for twice in "$TMP/clauses/agents"/impl-*.md; do break; done
printf '\nNever edit or delete an existing test unless the brief names it.\n' >> "$twice"
check "impl-clauses: a clause written twice in one agent prints a FAIL line" \
  "$(bash "$TMP/clauses/tests/impl-clauses.test.sh" 2>&1 | grep -c "^FAIL - $(basename "$twice" .md): existing tests are immutable")" "1"

NOTE="$P/../../docs/dforge/notes/2026-10-28-pipeline-smoke.md"
says "pipeline-smoke note: a Caveats section" "$NOTE" '## Caveats'
says "pipeline-smoke note: the figures come from the last result event only" "$NOTE" 'come from the last `result` event of each run only'
says "pipeline-smoke note: the timeline includes subagent messages" "$NOTE" 'subagent messages included'
says "pipeline-smoke note: the no-polling reading rests on the filtered check" "$NOTE" 'rests on the `parent_tool_use_id`-filtered check'
says "pipeline-smoke note: p1_overlap was changed mid-run" "$NOTE" '`p1_overlap` check'
says "pipeline-smoke note: p1_overlap now groups by message id" "$NOTE" 'to group tool uses by message id'
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `timeout 120 bash plugins/dforge/tests/draft-pack.test.sh`
Expected: `FAIL - join: the emptied drafts directory is gone too` (want `gone`, got `present`) and no other failure.

Run: `timeout 120 bash plugins/dforge/tests/auto-default.test.sh`
Expected: 23 FAIL lines and the script exits 1: the `process-graph` label checks (`no label points into ./references/` got 16, and the five `a label names` checks), the four Recovery pointer pins and the two `no Recovery pointer` negatives, the two `writing-plans` checks, the `SD=` check (got 2), the `flat_skill` check (got 0), `impl-clauses: a clause written twice in one agent prints a FAIL line` (got 0, because `grep -cF` counts the one flattened line once), and the six `pipeline-smoke note` checks. `impl-clauses: an unmodified copy prints no FAIL line`, `the Recovery pointers resolve` and the file's other checks pass.

Row 50's old negative check is blind to a clause wrapped across two lines. Show it with this probe, which copies the plugin, appends the removed clause wrapped, and counts the FAIL lines the copy's `auto-default.test.sh` prints for that check:

```bash
T=$(mktemp -d); mkdir -p "$T/plugins"; cp -R plugins/dforge "$T/plugins/dforge"
printf '\nfirst run `scripts/finish-choice set <action> --plan\nPLAN_FILE`:\n' >> "$T/plugins/dforge/skills/finishing-a-development-branch/SKILL.md"
timeout 120 bash "$T/plugins/dforge/tests/auto-default.test.sh" 2>&1 | grep -c '^FAIL - finishing: no read-the-spec-and-set clause'
rm -rf "$T"
```

Expected now: `0` (the check misses the wrapped clause).

- [ ] **Step 3: Implement**

Make each change in its own file; the exact new wording is given where a test pins it.

1. **Row 28, `plugins/dforge/scripts/draft-pack`.** After the existing last `rmdir "$dir" 2>/dev/null || true` line, add a second line with the same `2>/dev/null || true` tail that removes the parent of `$dir` (`$(dirname "$dir")`, the state's `drafts` directory). It is a separate `rmdir` call, not a second argument, and it never uses `rm -rf`: `rmdir` removes only an empty directory, so another plan's slices keep `drafts` in place.
2. **Row 45, `process-graph.md`.** In every node label and edge that reads `(./references/<file>)`, change it to `(./<file>)`; there are 16 occurrences, and each node name must change identically in its definition and in the edges that use it, or the graph splits into separate nodes. Then in `plugins/dforge/tests/task-step-text.test.sh` change the pinned text on the line `names "the process graph names the group template"` from `./references/group-reviewer-prompt.md` to `./group-reviewer-prompt.md`.
3. **Row 46, four pointers.**
   - `subagent-driven-development/SKILL.md`: in the After compaction block, the parenthesis `(an older run's `R/5` maps as §The Ledger's Recovery says)` becomes `(an older run's `R/5` maps as ledger.md §Recovery says)`, keeping the existing line break between `§Recovery` and `says`. Name the file without a link: the block already links `references/ledger.md` on one line, and `sdd-references.test.sh` requires that block to hold exactly one line containing that path.
   - `subagent-driven-development/references/setup.md`: `the Recovery table under The Ledger` becomes `the Recovery table in [ledger.md](ledger.md) §Recovery`.
   - `executing-plans/SKILL.md`, step 2 of the After compaction block: `see the Recovery table under The Ledger.` becomes `see the Recovery table in [recovery.md](references/recovery.md).`
   - `executing-plans/references/setup.md`: `recover each task's state with the Recovery table under The Ledger.` becomes `recover each task's state with the Recovery table in [recovery.md](recovery.md).` The sentence that follows (`A ledger whose first line names a different plan …`) stays, rewrapped.
4. **Row 47.** Delete the line `SD="$PLUGIN/skills/subagent-driven-development/SKILL.md"` from `review-depth.acceptance.test.sh` and from `review-depth-qa.acceptance.test.sh`. Nothing reads `$SD`; the line after each, `. "$HERE/fixtures/sdd-text.sh"`, stays.
5. **Row 48, `writing-plans/SKILL.md`, "Ask first" paragraph.** Replace `the question in dforge:brainstorming §Choosing the execution strategy` with `the question in dforge:brainstorming's [design-phase.md](../brainstorming/references/design-phase.md) (Choosing the execution strategy)`, wrapped across two lines. The file stays under 20,000 bytes (`skill-split-planning.test.sh` checks it) and the link resolves from `skills/writing-plans/`.
6. **Row 50.**
   - `auto-default.test.sh`, the check `finishing: no read-the-spec-and-set clause`: put `tr '\n' ' ' | tr -s ' '` between the `cat` of the finishing skill and its references and the `grep -c`, so a clause wrapped across lines is found; the expected count stays `"0"`.
   - `review-depth-qa.acceptance.test.sh`, in the A15 block: replace the line `FN=$(cat "$FIN" "$(dirname "$FIN")"/references/*.md | tr '\n' ' ' | tr -s ' ')` with `FN=$(flat_skill "$FIN")`, the helper defined near the top of the file.
7. **Row 54, `impl-clauses.test.sh`.** In `says`, count occurrences instead of lines: pipe `flat "$2"` through `grep -oF -- "$3"` (one output line per occurrence), then `wc -l | tr -d ' '`, still compared with `"1"`. `flat` stays as it is.
8. **Row 56, `docs/dforge/notes/2026-10-28-pipeline-smoke.md`.** Insert this section directly above `## Conclusion`; the three paragraphs carry the phrases the pins in Step 1 match, so keep them word for word:

```markdown
## Caveats

The cost, turn and millisecond figures above come from the last `result` event of each run only, so they are not run totals: P1's 4371 ms cannot cover a run that includes `sleep 25`, and a session that resumes after a completion notification emits more than one `result` event. Do not size the pipeline stage's cost cap or timeouts from them.

The P1 timeline lists every assistant message, subagent messages included, because its jq has no `parent_tool_use_id` filter. The second `Bash` and the `Read` therefore cannot be attributed to the main session from that table, and the Conclusion's no-polling reading rests on the `parent_tool_use_id`-filtered check, whose output this note does not show.

The plan's `p1_overlap` check collected tool names per stream event, which finds no overlap when the two tool uses of one message arrive as separate events with the same message id. It was changed mid-run to group tool uses by message id, which is why the note reports `pass` for the message id above. The historical plan keeps the original check.
```

Do not edit `docs/dforge/plans/2026-10-28-speed-and-cost.md` or any other historical plan or spec.

- [ ] **Step 4: Run the tests to verify they pass**

Run each with its own timeout from the repository root; every one must end with 0 failed:

```bash
timeout 120 bash plugins/dforge/tests/draft-pack.test.sh
timeout 120 bash plugins/dforge/tests/auto-default.test.sh
timeout 120 bash plugins/dforge/tests/impl-clauses.test.sh
timeout 120 bash plugins/dforge/tests/sdd-references.test.sh
timeout 120 bash plugins/dforge/tests/skill-split-planning.test.sh
timeout 120 bash plugins/dforge/tests/task-step-text.test.sh
timeout 300 bash plugins/dforge/tests/inline-mode.test.sh
timeout 120 bash plugins/dforge/tests/skill-size.test.sh
timeout 120 bash plugins/dforge/tests/final-phase.test.sh
timeout 600 bash plugins/dforge/tests/review-route.test.sh
timeout 300 bash plugins/dforge/tests/delegated-suite.test.sh
timeout 600 bash plugins/dforge/tests/review-depth.acceptance.test.sh
timeout 600 bash plugins/dforge/tests/review-depth-qa.acceptance.test.sh
timeout 900 bash plugins/dforge/tests/faster-plans.acceptance.test.sh
timeout 600 bash plugins/dforge/tests/speed-and-cost.acceptance.test.sh
timeout 300 bash plugins/dforge/tests/typed-seats-and-drafting.acceptance.sh
```

The text suites above read the files this task edits (the process graph, the three Recovery pointer files, the writing-plans skill and the implementer agents); `sdd-references.test.sh` is the one that fails if the `SKILL.md` pointer carries a second `references/ledger.md` path. `typed-seats-and-drafting.acceptance.sh` (its A13 asserts no `drafts` directory remains) and `speed-and-cost.acceptance.test.sh` (its A2 reruns it) fail their `A13: no stray worktree` check when a registered worktree path contains `drafter`, `measure`, `scratch` or `clone`; run them with `git worktree list` free of such paths. When that check fails only because of a worktree that is not yours (a sibling wave task's), leave it in place, record the FAIL and the path under your report's Discovered issues, and judge the run by its other checks.

Run the row 50 probe from Step 2 again.
Expected: `1` (the check now sees the wrapped clause).

Run: `timeout 300 node scripts/validate-repository.mjs`
Expected: exit 0, no error naming a link or a skill file.

Run `git worktree list` and `git status --short`.
Expected: no worktree or file the commands above left behind; the only changes are the files this task lists.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/scripts/draft-pack plugins/dforge/tests/draft-pack.test.sh
git commit -m "fix(dforge): remove the empty drafts directory"
git add plugins/dforge/skills/subagent-driven-development/references/process-graph.md plugins/dforge/tests/task-step-text.test.sh plugins/dforge/skills/subagent-driven-development/SKILL.md plugins/dforge/skills/subagent-driven-development/references/setup.md plugins/dforge/skills/executing-plans/SKILL.md plugins/dforge/skills/executing-plans/references/setup.md plugins/dforge/skills/writing-plans/SKILL.md
git commit -m "docs(dforge): point skills at the files they cite"
git add plugins/dforge/tests/review-depth.acceptance.test.sh plugins/dforge/tests/review-depth-qa.acceptance.test.sh plugins/dforge/tests/auto-default.test.sh plugins/dforge/tests/impl-clauses.test.sh
git commit -m "test(dforge): tidy review-depth and clause tests"
git add docs/dforge/notes/2026-10-28-pipeline-smoke.md
git commit -m "docs(dforge): add caveats to the smoke note"
```

### Task 5: Plan-named baseline commands

**Files:**
- Modify: `plugins/dforge/scripts/task-step` (`settle_item`, `settle_cannot_verify`; a new `plan_named_commands` directly above `settle_item`'s header comment)
- Modify: `plugins/dforge/skills/subagent-driven-development/references/task-reviewer-prompt.md` (the `baseline` sentence in the Cannot verify forms paragraph)
- Modify: `plugins/dforge/reference/delegated-task.md` (only the cannot-verify passage that begins "The reviewer's": the sentence "A `baseline` command's text comes from a review seat, and a review seat has no shell: …")
- Test: `plugins/dforge/tests/task-step-settle.test.sh` (adds Run lines to its fixture plan and a named-commands section; Task 7 later adds its own section to the same file)
- Test: `plugins/dforge/tests/delegated-suite.test.sh`
- Test: `plugins/dforge/tests/task-step-text.test.sh`
- Test: `plugins/dforge/tests/speed-and-cost.acceptance.test.sh` (its fixture plan needs one `Run:` line, or its A6 baseline case stops settling)

**Interfaces:**
- Consumes: Contracts "Guard refusal" and "Allowed report paths" (Task 1): the `delegated-task.md` sentence says review seats can write only their report files because the cockpit refuses any other write.
- Produces: Contracts "Plan-named command": `settle_item` returns 0 settled, 1 could not check, 2 command not named in the plan; only status 2 makes `settle_cannot_verify` append ` (command not named in the plan)` to the kept item. The shell variable `named_file` (set by `settle_cannot_verify`, read by `settle_item`) holds the task's plan-named commands, one per line.

**Items:** 27, 41

**Depends on:** Task 1

**Implementer:** dforge:impl-opus-high
**Evaluation:** files 2 - spec 2 - coupling 1 - risk 3 = 8
**Lenses:** security, lang-bash

Row 27's decision: a `cannot-verify: baseline <command>, expect <pass|fail>` item is run through `bash -c` only when the plan, not the review seat, named that command. The command's trimmed text must be byte-identical to one of: the step file's `.suite`; the plan header's `**Integration check:**` command; or the first inline code span of a line of the task's text that begins (after optional blanks, a list marker or `|`) with `Run:` or `**Check:**`. Fenced blocks never contribute.

- [ ] **Step 1: Write the failing tests**

1. In `task-step-settle.test.sh`, give the existing fixture plan two `Run:` lines so its existing `bash check.sh` baseline items stay plan-named. In the `docs/plan.md` heredoc (lines prefixed with `|`), Task 1's block ends with its `**Evaluation:**` line and Task 2's block ends the heredoc. Add after Task 1's Evaluation line:

```text
|
|Run: `bash check.sh`
```

   and after Task 2's Evaluation line (the last line before `PLAN`):

```text
|
|Run: `bash check.sh`
|Run: `no_such_command_zz`
```

2. In the same file, insert this block directly before the final `printf '\n%d passed, %d failed\n' "$pass" "$fail"` line. The outer fence has four backticks because the fixture plan holds a three-backtick fenced block.

````bash
# A baseline command runs only when the plan names it for the task being
# settled; every marker file below is made by a command that ran.
MARK_DIR="$TMP/marks"
mkdir -p "$MARK_DIR" "$TMP/marks-sr"
export MARK_DIR
printf '#!/usr/bin/env bash\n: > "$MARK_DIR/$1"\nexit "${2:-0}"\n' > "$REPO/mark.sh"
sed 's/^|//' > "$REPO/docs/named.md" <<'PLAN'
|# Named Commands Fixture Plan
|
|**Goal:** Fixture.
|
|**Execution:** subagent — `claude --model sonnet --effort high` — fixture
|
|**Integration check:** `bash mark.sh integ 0`
|
|## Task index
|
|1. One
|2. Two
|
|### Task 1: One
|
|**Files:**
|- Modify: `lib/new.sh`
|
|**Implementer:** dforge:impl-sonnet-low
|**Evaluation:** files 0 - spec 0 - coupling 1 - risk 0 = 1
|
|Run: `bash mark.sh run-first 0` and then `bash mark.sh second-span 0`
|- Run: `bash mark.sh run-list 0`
|Run: `bash mark.sh timed 124`
|Run: ``bash mark.sh dbl 0``
|Afterwards run: `bash mark.sh prose 0`
|**Check:** `bash mark.sh check 0` prints nothing.
|
|```bash
|bash mark.sh fenced 0
|Run: `bash mark.sh fenced-run 0`
|```
|
|### Task 2: Two
|
|**Files:**
|- Modify: `lib/new.sh`
|
|**Implementer:** dforge:impl-sonnet-low
|**Evaluation:** files 0 - spec 0 - coupling 1 - risk 0 = 1
|
|Run: `bash mark.sh task2-run 0`
PLAN
g add -A && g commit -qm "named commands fixture"
ts start docs/named.md 1 --suite 'bash mark.sh suite 0'
NWS=$(winpath "$(cd "$REPO" && bash "$S/sdd-workspace" docs/named.md)")
NLEDGER="$NWS/progress.md"
printf '#!/usr/bin/env bash\ncompute_total() {\n  echo 3\n}\n' > "$REPO/lib/new.sh"
g add -A && g commit -qm "named work"
(cd "$REPO" && MARK_DIR="$TMP/marks-sr" bash "$S/suite-run" -- bash -c 'bash mark.sh suite 0' >/dev/null 2>&1)
ts review docs/named.md 1
check "named: review exits 0" "$rc" "0"
cat > "$NWS/task-1-review-report.md" <<'REPORT'
## Verdict
spec: cannot-verify
quality: approved
scores: spec 15 / scope 17 / verification 12 / quality 16

## Strengths
Fine.

## Findings

## Cannot verify
- cannot-verify: baseline bash mark.sh run-first 0, expect pass — the first span of a Run line
- cannot-verify: baseline  bash mark.sh run-list 0 , expect pass — a listed Run line, padded with spaces
- cannot-verify: baseline bash mark.sh check 0, expect pass — a Check line
- cannot-verify: baseline bash mark.sh integ 0, expect pass — the Integration check
- cannot-verify: baseline bash mark.sh suite 0, expect pass — the recorded suite command
- cannot-verify: baseline bash mark.sh timed 124, expect pass — a plan-named command that exits 124
- cannot-verify: baseline bash mark.sh nowhere 0, expect pass — a command the plan never names
- cannot-verify: baseline bash mark.sh run-first 0; bash mark.sh appended 0, expect pass — a named command with more after it
- cannot-verify: baseline bash mark.sh fenced 0, expect pass — a line of a fenced block
- cannot-verify: baseline bash mark.sh fenced-run 0, expect pass — a Run line inside a fenced block
- cannot-verify: baseline bash mark.sh second-span 0, expect pass — the second span of a Run line
- cannot-verify: baseline bash mark.sh dbl 0, expect pass — a double-backtick span
- cannot-verify: baseline bash mark.sh prose 0, expect pass — a line that does not begin with Run:
- cannot-verify: baseline bash mark.sh task2-run 0, expect pass — a command only Task 2 names

## Assessment
Fine.
REPORT
ts verdict docs/named.md 1
check "named: verdict exits 0" "$rc" "0"
check "named: only plan-named commands ran" "$(ls "$MARK_DIR" | sort | tr '\n' ' ')" "check integ run-first run-list suite timed "
check "named: the five settled items are logged, the rest add no ledger line" "$(grep -c 'settled by task-step check baseline' "$NLEDGER")" "5"
check "named: the suite command's item is settled with its own log" "$(grep -cxF "Task 1: Ruling: cannot-verify — settled by task-step check baseline — exit 0, log $NWS/task-1-baseline-5.log" "$NLEDGER")" "1"
check "named: a command that is not plan-named is no finding" "$(grep '^findings: ' <<<"$out")" "findings: 0 Critical, 0 Important, 0 Minor"
check "named: unnamed commands carry the label, a named command that exits 124 does not" "$(grep '^cannot-verify: ' <<<"$out")" \
  "cannot-verify: baseline bash mark.sh timed 124, expect pass — a plan-named command that exits 124
cannot-verify: baseline bash mark.sh nowhere 0, expect pass — a command the plan never names (command not named in the plan)
cannot-verify: baseline bash mark.sh run-first 0; bash mark.sh appended 0, expect pass — a named command with more after it (command not named in the plan)
cannot-verify: baseline bash mark.sh fenced 0, expect pass — a line of a fenced block (command not named in the plan)
cannot-verify: baseline bash mark.sh fenced-run 0, expect pass — a Run line inside a fenced block (command not named in the plan)
cannot-verify: baseline bash mark.sh second-span 0, expect pass — the second span of a Run line (command not named in the plan)
cannot-verify: baseline bash mark.sh dbl 0, expect pass — a double-backtick span (command not named in the plan)
cannot-verify: baseline bash mark.sh prose 0, expect pass — a line that does not begin with Run: (command not named in the plan)
cannot-verify: baseline bash mark.sh task2-run 0, expect pass — a command only Task 2 names (command not named in the plan)"
check "named: no temporary worktree is left" "$(g worktree list | wc -l | tr -d ' ')" "1"
````

   The exit-124 item stands in for a baseline command that hits its 600-second bound: `suite-run` reports a timeout as 124, so a plan-named command that exits 124 reaches the same branch without a ten-minute wait.

3. In `delegated-suite.test.sh`, add a helper beside `in_loop` and replace the pin that no longer holds. After the `by_hand()` definition add:

```bash
in_loop_flat() { sed '/^## The steps by hand/,$d' "$DT" | tr -d '\r' | tr '\n' ' ' | tr -s ' ' | grep -cF -- "$1"; } # in_loop_flat <text> — the loop steps as one line, so a wrapped sentence matches
```

   Change the comment on `has()` to `# has <label> <in_loop|in_loop_flat|by_hand> <text>`. Replace the one `has` line whose label is "a baseline command runs unsandboxed from a seat with no shell" with:

```bash
has "a baseline command runs only when the plan names it" in_loop_flat 'A `baseline` command runs only when the plan names it'
has "a plan-named command still runs unsandboxed with your rights" in_loop_flat 'A plan-named command still runs on the controller host, unsandboxed and with your rights'
has "an unnamed command stays for the ruling seat with its label" in_loop_flat 'ending ` (command not named in the plan)`'
has "review seats write only their report files" in_loop_flat 'Review seats can write only their report files'
check "the seat's text is no longer described as run verbatim" "$(in_loop_flat 'a review seat has no shell')" "0"
```

4. In `task-step-text.test.sh`, add the reviewer-prompt path after the `SDD=` line:

```bash
TRP="$P/skills/subagent-driven-development/references/task-reviewer-prompt.md"
```

   Add these helpers after the `lacks()` definition:

```bash
flat() { tr -d '\r' < "$1" | tr '\n' ' ' | tr -s ' '; } # a file as one line, so a wrapped sentence matches
names_flat() { # names_flat <label> <file> <text>
  check "$1" "$(flat "$2" | grep -qF -- "$3" && echo yes || echo no)" "yes"
}
lacks_flat() { # lacks_flat <label> <file> <text>
  check "$1" "$(flat "$2" | grep -qF -- "$3" && echo yes || echo no)" "no"
}
```

   and add this block directly before the line `# --- the group reviewer template ---`:

```bash
# --- baseline items run only a command the plan names ---
names_flat "the reviewer prompt: baseline runs only a command the plan names" "$TRP" 'It runs only a command the plan names:'
names_flat "the reviewer prompt names the Run and Check lines" "$TRP" 'Integration check, or the command of one of the'
names_flat "the reviewer prompt: copied exactly, anything else goes to the ruling seat" "$TRP" 'copied exactly. Any other command is not run and goes to the ruling seat.'
lacks_flat "the reviewer prompt no longer says a baseline command runs verbatim" "$TRP" 'run verbatim, through'
```

5. In `speed-and-cost.acceptance.test.sh`, the fixture plan's per-task `printf` (inside the `for n in 1 2 3 4 5` loop that builds `$FIX/docs/plan.md`) ends its format string with `risk 0 = 1\n'`. Change that ending so every fixture task names `bash check.sh`:

```text
risk 0 = 1\n\nRun: `bash check.sh`\n' "$n" "$n"
```

   Its A6 "expect form" case (four settled items, none left for a seat) passes before and after this change, and fails after Step 3 if this edit is missing.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `timeout 300 bash plugins/dforge/tests/task-step-settle.test.sh`
Expected: FAIL on three lines, "named: only plan-named commands ran" (every script left its marker: 14 markers, the `; bash mark.sh` item adding `appended`), "named: the five settled items are logged, the rest add no ledger line" (got 13) and "named: unnamed commands carry the label, a named command that exits 124 does not". All earlier checks still pass.

Run: `timeout 300 bash plugins/dforge/tests/delegated-suite.test.sh`
Expected: FAIL on the four new `has` lines and on "the seat's text is no longer described as run verbatim".

Run: `timeout 300 bash plugins/dforge/tests/task-step-text.test.sh`
Expected: FAIL on the four reviewer-prompt lines.

Run: `timeout 300 bash plugins/dforge/tests/speed-and-cost.acceptance.test.sh A6 A7`
Expected: PASS (the fixture edit changes nothing until Step 3).

- [ ] **Step 3: Implement**

1. `plan_named_commands TASK STEP_FILE` in `task-step`, a new function directly above the header comment of `settle_item`. It reads the globals `src` (the amended plan) and `_PLAN_AWK` (from `lib/plan.sh`) and prints the plan-named baseline commands for TASK, one per line, from these sources in order:
   - the step file's `.suite` (read with `jq -r '.suite // empty'` and `tr -d '\r'`); skipped when empty or when it contains a newline, because a one-line item can never equal it;
   - the plan header's `**Integration check:**` command: take the header with `plan_header "$src"`, the first line `plan_lines 'Integration check'` yields (it ignores fenced lines), strip the `**Integration check:**` label, trim leading and trailing blanks (space and tab, `[[:blank:]]`), and remove one enclosing backtick pair when the whole text is wrapped in one (the same `sed` rule `run_at_base` applies to `**Worktree setup:**`); skipped when empty;
   - for each line of `plan_task_text "$src" TASK` outside every fenced block (use `$_PLAN_AWK` and skip lines for which `in_fence($0)` is true): strip a leading run made of blanks, list markers (`-`, `*` or `+`, or digits followed by `.` or `)`, each followed by a blank) and `|` characters; the rest must begin with `Run:` or `**Check:**` (case-sensitive; a single `*` followed by a blank is a list marker, so the `**` of `**Check:**` is never consumed); then take the first inline code span of what follows the marker: the text between the line's first backtick and the next backtick, not trimmed. The line names nothing when its first backtick is followed by another backtick (a double-backtick span), when there is no closing backtick, when the span is empty, or when the closing backtick is followed by another backtick.
2. `settle_item`, `baseline` branch. After `case $want in pass | fail) ;; *) return 1 ;; esac`, in this order: trim leading and trailing blanks (space and tab) from `cmd` and return 1 when it is empty; return 2 unless `cmd` equals a whole line of the file named by the variable `named_file` (a fixed-string whole-line match under `LC_ALL=C`; a missing, unreadable or unset `named_file` means nothing is named, so return 2); return 1 when `base` is empty; then `run_at_base` exactly as today. The trimmed `cmd` is byte-identical to the plan's copy, so that is the string `bash -c` receives and the string the label `baseline <cmd>, expect <want>` prints. Everything after the run (the 124, 126 and 127 exits returning 1, match and mismatch) is unchanged. The `exists` branch never returns 2. Update `settle_item`'s header comment: it returns 1 for free text, an item without `expect`, a malformed item or a check that could not run, and 2 for a `baseline` command the plan does not name.
3. `settle_cannot_verify`. Declare `src_rc` and `named_file` as locals. After the `[ "$vgroup" -eq 0 ] || return 0` line set `named_file=$TMP/named-commands` and write `plan_named_commands "$first" "$vstate"` into it. Capture `settle_item`'s status (`out=$(settle_item …); src_rc=$?`) instead of testing it in an `if`: status 0 does what the `if` branch does today (a mismatch becomes the Important finding and `continue`s, a match writes the ledger line); status 2 keeps the item for the ruling seat as `${item#cannot-verify: } (command not named in the plan)`; any other status keeps it as `${item#cannot-verify: }` with no suffix, as today. Extend the function's header comment with the status-2 rule. `plan_named_commands` is called only here, so it needs no placement before the `rereview` dispatch.
4. `task-reviewer-prompt.md`. In the `prompt: |` block, replace the sentence "`baseline` asks for the result of one command run verbatim, through `bash -c`, at the task's base commit." with the text below, keeping the four-space indentation and the paragraph's other sentences:

```text
    `baseline` asks for the result of one command at the task's base
    commit. It runs only a command the plan names: the task's suite
    command, the plan's Integration check, or the command of one of the
    task's `Run:` or `**Check:**` lines, copied exactly. Any other command
    is not run and goes to the ruling seat. `expect` names the answer the task
```

   (the last line continues "needs: `present` or `absent`; …" as before).
5. `delegated-task.md`. In the passage after "A file at the repository root is written `./<name>`, so it is read as a path and not as a symbol.", replace the sentence "A `baseline` command's text comes from a review seat, and a review seat has no shell: `verdict` runs it on the controller host, unsandboxed and with your rights, as the suite is run there." with the text below, then leave "An item whose check could not run (…)" and the rest of the paragraph as it is. The pinned phrases must stay on the wording shown (a line may wrap anywhere):

```text
A `baseline` command runs only when the plan names it: the step file's suite
command, the plan header's `**Integration check:**` command, or the first code
span of one of the task's `Run:` or `**Check:**` lines, byte for byte after
trimming. `verdict` runs the plan's copy of the command, never the seat's text.
A plan-named command still runs on the controller host, unsandboxed and with
your rights, as the suite is run there. Any other `baseline` command is not
run: it stays for the ruling seat, its digest line ending
` (command not named in the plan)`. Review seats can write only their report
files (the cockpit refuses any other write), so a seat cannot add a command to
the plan, its amendments or the step file.
```

   Leave "(up to ten minutes each)" in the by-hand passage alone: a plan-named baseline item still keeps its 600-second bound.

Do not change `run_at_base`, the `baseline-<k>.log` naming, the 600-second bound or what a match and a mismatch do.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bash -n plugins/dforge/scripts/task-step`
Expected: no output.

Run: `timeout 300 bash plugins/dforge/tests/task-step-settle.test.sh`
Expected: `35 passed, 0 failed`.

Run: `timeout 300 bash plugins/dforge/tests/delegated-suite.test.sh`
Expected: `0 failed`.

Run: `timeout 300 bash plugins/dforge/tests/task-step-text.test.sh`
Expected: `0 failed`.

Run: `timeout 300 bash plugins/dforge/tests/speed-and-cost.acceptance.test.sh A6 A7`
Expected: `7 passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/scripts/task-step plugins/dforge/skills/subagent-driven-development/references/task-reviewer-prompt.md plugins/dforge/reference/delegated-task.md plugins/dforge/tests/task-step-settle.test.sh plugins/dforge/tests/delegated-suite.test.sh plugins/dforge/tests/task-step-text.test.sh plugins/dforge/tests/speed-and-cost.acceptance.test.sh
git commit -m "feat(dforge): run only plan-named baselines"
```

### Task 6: task-step base runs and step-file checks

**Files:**
- Modify: `plugins/dforge/scripts/task-step` (`run_at_base`; a new `require_step_file` directly above `run_at_base`'s header comment; `suite_check`; `cmd_rereview`)
- Modify: `plugins/dforge/reference/delegated-task.md` (only the `rereview --covered` sentence "which takes up to ten minutes", in the passage on `rereview --covered`)
- Test: `plugins/dforge/tests/task-step-base.test.sh`
- Test: `plugins/dforge/tests/task-step.test.sh` (one existing group check asserts that `rereview --base` works for a sequential member; the refusal reverses it)

**Interfaces:**
- Consumes: Contracts "Plan-named command" (Task 5): the fixture-Task-14 case below runs a `baseline` item, so the fixture plan names its command on a `Run:` line.
- Produces: Contracts "Setup log": `run_at_base` writes the Worktree setup's output to `<OUT_LOG>.setup.log`; a failed setup prints `task-step: the worktree setup failed at <sha7> (log <path>)` on stderr. `require_step_file FILE` exits 6 with `task-step: cannot read FILE` unless FILE is valid JSON.

**Items:** 29, 30, 32, 33, 38

**Depends on:** Task 5

**Implementer:** dforge:impl-opus-high
**Evaluation:** files 1 - spec 2 - coupling 1 - risk 2 = 6

Rows 29, 30, 32, 33 and 38 of the register, with the base-run half of the spec's A12:

- A `**Worktree setup:**` command that hangs must not hang `verdict`: it runs bounded, its output is kept, and a timed-out setup is recorded like a timed-out run.
- `rereview --base` moves a sequential group's comparison base, so a sequential group member refuses it.
- A step file that is missing or unreadable must not read as "no suite recorded".
- The base-run branches that had no test get one (a passing base row, a base row with exit 124, a `--cwd` base row).

- [ ] **Step 1: Write the failing tests**

All edits are to `plugins/dforge/tests/task-step-base.test.sh`. Run them in order; each insertion names its anchor.

1. After the line `S="$P/scripts"` add:

```bash
DT="$P/reference/delegated-task.md"
```

2. In the `for fn in …` list that checks helpers are defined before the `rereview` dispatch, add `require_step_file` after `suite_base_sha`:

```bash
for fn in suite_key suite_row suite_failing_lines suite_fail_set suite_unfinished suite_base_sha require_step_file suite_base_lines run_at_base suite_gap; do
```

3. In the "Task 6" block, after the line `check "task 6: the stderr says why" …` add:

```bash
check "task 6: the stderr names the setup log" "$(grep -cF "(log $WS/task-6-base.log.setup.log)" <<<"$err")" "1"
check "task 6: the setup log is kept" "$([ -f "$WS/task-6-base.log.setup.log" ] && echo yes || echo no)" "yes"
```

4. After the line `check "group: the fix file names the regression" …` (the end of the Tasks 7 and 8 group block), add:

```bash

# A step file that cannot be read is not "no suite recorded".
cp "$WS/task-8-step.json" "$TMP/step8.bak"
rm -f "$WS/task-8-step.json"
ts verdict docs/plan.md 7 8 --group
check "group: a missing last member's step file exits 6" "$rc $(grep -cF "cannot read $WS/task-8-step.json" <<<"$err") $(grep -c 'suite: none recorded' <<<"$out")" "6 1 0"
printf '{not json\n' > "$WS/task-8-step.json"
ts verdict docs/plan.md 7 8 --group
check "group: an invalid last member's step file exits 6" "$rc $(grep -cF "cannot read $WS/task-8-step.json" <<<"$err") $(grep -c 'suite: none recorded' <<<"$out")" "6 1 0"
cp "$TMP/step8.bak" "$WS/task-8-step.json"

# rereview --base would move the group's comparison base, so a sequential
# member refuses it.
ts rereview docs/plan.md 8 --base "$(g rev-parse HEAD~1)"
check "group: rereview --base on a sequential member exits 2" "$rc $(grep -cF -- '--base does not apply to a group member; see delegated-task.md §3a' <<<"$err")" "2 1"
check "group: the refused rereview leaves the step file as it was" "$(cmp -s "$TMP/step8.bak" "$WS/task-8-step.json" && echo same || echo changed)" "same"
```

5. Directly before the final `printf '\n%d passed, %d failed\n' "$pass" "$fail"` line add the block below. The `Run:` line on fixture Task 14 makes its baseline command plan-named (Task 5). A setup that exits 124 stands in for a baseline item's 600-second bound, which a test cannot wait for; fixture Task 13 exercises the real bound through the suite's base run.

```bash

# Tasks 13 to 18 join the fixture plan; Task 14 names the command its baseline item runs.
for n in 13 14 15 16 17 18; do
  printf '\n### Task %s: Task %s\n\n**Files:**\n- Modify: `app.txt`\n\n**Implementer:** dforge:impl-sonnet-low\n**Evaluation:** files 0 - spec 0 - coupling 1 - risk 0 = 1\n' "$n" "$n"
  [ "$n" != 14 ] || printf '\nRun: `bash suite.sh`\n'
done >> "$REPO/docs/plan.md"
set_setup() { # set_setup <command> — the plan header's Worktree setup
  awk -v s="$1" '/^\*\*Worktree setup:\*\*/ { print "**Worktree setup:** `" s "`"; next } { print }' "$REPO/docs/plan.md" > "$REPO/docs/plan.tmp" \
    && mv "$REPO/docs/plan.tmp" "$REPO/docs/plan.md"
}
setup_runs() { grep -c . "$SUITE_MARK.setup" 2>/dev/null || true; }

# Task 13: a Worktree setup that hangs is bounded, logged and not run again.
set_setup 'echo hanging; echo ran >> "$SUITE_MARK.setup"; exec sleep 20'
printf 'more\n' >> "$REPO/app.txt"
commit "a setup that hangs"
ts start docs/plan.md 13 --suite 'bash suite.sh'
printf 'impl 13\n' >> "$REPO/app.txt"
commit "work 13"
sr
ts review docs/plan.md 13
clean_report 13
plain0=$(marks plain)
export TASK_STEP_BASE_TIMEOUT=1 SUITE_RUN_KILL_AFTER=1
ts verdict docs/plan.md 13
check "task 13: a hung setup excuses nothing" "$rc $(grep '^suite: ' <<<"$out")" "0 suite: red (1 failing, 0 baseline)"
check "task 13: the timeout is recorded" "$([ -e "$WS/task-13-base-timeout" ] && echo marker || echo none)" "marker"
check "task 13: the setup ran once and the suite never ran at the base" "$(setup_runs) $(($(marks plain) - plain0))" "1 0"
check "task 13: the setup log holds its output" "$(cat "$WS/task-13-base.log.setup.log" 2>/dev/null)" "hanging"
check "task 13: the base log is the setup log" "$(cmp -s "$WS/task-13-base.log" "$WS/task-13-base.log.setup.log" && echo same || echo differ)" "same"
check "task 13: the stderr says the base timed out" "$(grep -c 'timed out' <<<"$err")" "1"
ts verdict docs/plan.md 13
unset TASK_STEP_BASE_TIMEOUT SUITE_RUN_KILL_AFTER
check "task 13: a second verdict does not run the setup again" "$(setup_runs) $(($(marks plain) - plain0))" "1 0"
check "task 13: the temporary worktree is gone" "$(g worktree list | wc -l | tr -d ' ')" "1"

# Task 14: a baseline item whose setup times out goes to the seat, with the setup log kept.
set_setup 'echo setup-124; echo ran >> "$SUITE_MARK.setup"; exit 124'
commit "a setup that reports a timeout"
ts start docs/plan.md 14
printf 'impl 14\n' >> "$REPO/app.txt"
commit "work 14"
ts review docs/plan.md 14
cat > "$WS/task-14-review-report.md" <<'REPORT'
## Verdict
spec: cannot-verify
quality: approved
scores: spec 15 / scope 17 / verification 12 / quality 16

## Strengths
Fine.

## Findings

## Cannot verify
- cannot-verify: baseline bash suite.sh, expect fail — does the suite fail before the task

## Assessment
Fine.
REPORT
setup0=$(setup_runs)
ts verdict docs/plan.md 14
check "task 14: the item stays for the seat, without the not-named label" "$rc $(grep '^cannot-verify: ' <<<"$out")" \
  "0 cannot-verify: baseline bash suite.sh, expect fail — does the suite fail before the task"
check "task 14: the setup ran once" "$(($(setup_runs) - setup0))" "1"
check "task 14: the setup log is kept beside the baseline log" "$(cat "$WS/task-14-baseline-1.log.setup.log" 2>/dev/null)" "setup-124"
check "task 14: nothing is settled and nothing is a finding" "$(grep -c 'Task 14: Ruling: cannot-verify' "$WS/progress.md") $(grep '^findings: ' <<<"$out")" "0 findings: 0 Critical, 0 Important, 0 Minor"
check "task 14: the temporary worktree is gone" "$(g worktree list | wc -l | tr -d ' ')" "1"

# Task 15: a passing suites.tsv row at the base answers without a base run.
set_setup 'touch setup.done'
set_failing ''
commit "green base for task 15"
sr
ts start docs/plan.md 15 --suite 'bash suite.sh'
set_failing $'not ok 1 - delta\n'
commit "work 15"
sr
ts review docs/plan.md 15
clean_report 15
setups0=$(marks setup)
ts verdict docs/plan.md 15
check "task 15: a passing base row leaves no baseline" "$rc $(grep '^suite: ' <<<"$out")" "0 suite: red (1 failing, 0 baseline)"
check "task 15: no base run and no base failures file" "$(($(marks setup) - setups0)) $([ -e "$WS/task-15-base-failures.txt" ] && echo file || echo nofile)" "0 nofile"

# Task 16: a base row that timed out is not an answer; the suite runs at the base.
set_failing $'not ok 1 - alpha\n'
commit "alpha fails at the base of task 16"
: > "$REPO/slow.txt"
sr_timeout
rm -f "$REPO/slow.txt"
ts start docs/plan.md 16 --suite 'bash suite.sh'
set_failing $'not ok 1 - alpha\nnot ok 2 - beta\n'
commit "work 16"
sr
ts review docs/plan.md 16
clean_report 16
setups0=$(marks setup)
ts verdict docs/plan.md 16
check "task 16: a timed-out base row falls through to a base run" "$rc $(grep '^suite: ' <<<"$out") $(($(marks setup) - setups0))" "0 suite: red (1 failing, 1 baseline) 1"
check "task 16: the base run's failures are kept" "$(cat "$WS/task-16-base-failures.txt" 2>/dev/null)" "not ok - alpha"
check "task 16: no timeout is recorded" "$([ -e "$WS/task-16-base-timeout" ] && echo marker || echo none)" "none"

# Task 17: verdict --cwd finds the base row in that checkout's state when the main checkout's has none.
set_failing $'not ok 1 - alpha\n'
commit "alpha fails at the base of task 17"
ts start docs/plan.md 17 --suite 'bash suite.sh'
WT=$TMP/wt17
g worktree add -q --detach "$WT" HEAD
(cd "$WT" && bash "$S/suite-run" -- bash -c 'bash suite.sh' >/dev/null 2>&1)
printf 'not ok 1 - alpha\nnot ok 2 - beta\n' > "$WT/failing.txt"
git -C "$WT" add -A && git -C "$WT" commit -qm "work 17"
W17=$(git -C "$WT" rev-parse HEAD | tr -d '\r')
(cd "$WT" && bash "$S/suite-run" -- bash -c 'bash suite.sh' >/dev/null 2>&1)
ts review docs/plan.md 17 --head "$W17" --cwd "$WT"
clean_report 17
setups0=$(marks setup)
ts verdict docs/plan.md 17 --cwd "$WT"
check "task 17: the base row in the --cwd checkout's state excuses alpha" "$rc $(grep '^suite: ' <<<"$out")" "0 suite: red (1 failing, 1 baseline)"
check "task 17: no base run and no base failures file" "$(($(marks setup) - setups0)) $([ -e "$WS/task-17-base-failures.txt" ] && echo file || echo nofile)" "0 nofile"
g worktree remove --force "$WT"

# Task 18: a wave task in a group, which carries a head ref, keeps rereview --base.
ts start docs/plan.md 18
printf 'impl 18\n' >> "$REPO/app.txt"
commit "work 18"
g branch t18-ref
ts review docs/plan.md 18 --head t18-ref
jq '.group = "18,19"' "$WS/task-18-step.json" > "$TMP/s18.json" && mv "$TMP/s18.json" "$WS/task-18-step.json"
printf -- '- app.txt: wrong value\n\nFixed.\n' > "$WS/task-18-fix-1.md"
printf 'fix 18\n' >> "$REPO/app.txt"
commit "fix 18"
g branch -f t18-ref HEAD
EARLIER=$(g rev-parse HEAD~2 | tr -d '\r')
ts rereview docs/plan.md 18 --base "$EARLIER"
check "task 18: rereview --base on a grouped wave task is accepted and recorded" "$rc $(jq -r '.base' "$WS/task-18-step.json" | tr -d '\r')" "0 $EARLIER"

# Row 29: the stale ten-minute figure for a red fix-head suite is gone.
dt=$(tr -d '\r' < "$DT" | tr '\n' ' ' | tr -s ' ')
check "the doc says a base run under rereview --covered takes up to an hour" "$(grep -cF 'which takes up to an hour (`TASK_STEP_BASE_TIMEOUT`)' <<<"$dt")" "1"
check "the doc no longer says it takes up to ten minutes" "$(grep -cF 'which takes up to ten minutes' <<<"$dt")" "0"
```

6. In `plugins/dforge/tests/task-step.test.sh`, in the sequential-group member section (the `gr_*` helpers), the existing check `member rereview: --base <group review head> works for a member` contradicts the refusal. Make two edits there. First, directly after the line `gr_commit two.txt` add:

```bash
GR_F2=$(gr_git rev-parse HEAD)
```

   Second, replace the two lines `gr_run rereview docs/plan.md 4 --base "$GR_H4"` and the `check "member rereview: --base <group review head> works for a member" …` line that follows it with:

```bash
gr_run rereview docs/plan.md 4 --base "$GR_H4"
check "member rereview: --base is refused for a sequential member" "$gr_rc $(grep -cF -- '--base does not apply to a group member; see delegated-task.md §3a' <<<"$gr_err") $(gr_state 4 .round)" "2 1 0"
gr_run rereview docs/plan.md 4
check "member rereview: without --base the fix base is the last fix head" "$gr_rc $(grep -c "Fix base:\*\* $GR_F2 " "$GR_WS/task-4-rereview-1-prompt.md")" "0 1"
```

   Task 4's round and the check that follows ("review --group: a refused group keeps each member's round") read the same as before, because the second `rereview` is Task 4's first round.

- [ ] **Step 2: Run the test to verify it fails**

Run: `timeout 600 bash plugins/dforge/tests/task-step-base.test.sh`
Expected: 17 FAIL lines and `63 passed, 17 failed` (the checks of fixture Tasks 15 to 18 and the first fixture-Task-14 check pass already: they pin behaviour that must survive). The failing lines: "require_step_file is defined before the rereview dispatch"; "task 6: the stderr names the setup log"; "task 6: the setup log is kept"; both "group: a missing/an invalid last member's step file exits 6" (they get `0 0 1`: exit 0 and `suite: none recorded`); "group: rereview --base on a sequential member exits 2" and "group: the refused rereview leaves the step file as it was"; the seven fixture-Task-13 checks about the timeout marker, the suite that ran at the base (`1 1`), the setup log, the base log, the timed-out stderr, the second verdict and "a hung setup excuses nothing" (if that last one already passes before the change, expect 16 FAIL lines and `64 passed, 16 failed`); "task 14: the setup log is kept beside the baseline log"; and the two `delegated-task.md` checks. This run takes about a minute because the fixture-Task-13 setup sleeps its full 20 seconds, twice. Do not run `task-step.test.sh` here: it takes about 22 minutes and the old code accepts the `--base` it now expects to be refused, so its first new check fails by exit code 0 against 2.

- [ ] **Step 3: Implement**

1. `require_step_file FILE`, a new function directly above the header comment of `run_at_base` (it must precede the `rereview` dispatch, because `cmd_rereview` calls it). It succeeds when `jq -e . FILE >/dev/null 2>&1` does, and otherwise calls `die "cannot read FILE" 6`. Its comment says to call it from the shell that reads the step file: an exit inside `$(…)` leaves only that subshell.
2. `run_at_base`. Add a local `scode`. Replace the single `if [ -n "$setup" ] && ! (cd "$wt" && bash -c "$setup") >/dev/null 2>&1; then … else … fi` with this behaviour, leaving the worktree creation before it and the `git worktree remove --force` / `prune` / `return $rc` after it unchanged:
   - When `setup` is non-empty, run it in `$wt` as `timeout -k "${SUITE_RUN_KILL_AFTER:-10}" "$secs" bash -c "$setup" < /dev/null` (the form `suite-run` uses, with the run's own `secs`), with stdout and stderr both written to `"$out.setup.log"` (truncating it). Take its status as `scode`; a status of 137 is 124.
   - `scode` 124: copy `"$out.setup.log"` to `"$out"`; when the copy works print `124` on stdout and set `rc=0`. Nothing else runs, so `suite_base_lines` records `task-<N>-base-timeout` and `settle_item` (which returns 1 for a 124) sends the item to the seat.
   - Any other non-zero `scode`: print `task-step: the worktree setup failed at <sha7> (log <out>.setup.log)` on stderr, print nothing on stdout, leave `rc=1`.
   - `scode` 0, or no setup: run the suite through `suite-run --timeout "$secs"` exactly as today. The setup and the run each get the full bound, so one base run may take up to twice `secs`.
   Update the function's header comment: the setup is bounded by the same seconds and logged; a setup timeout prints 124 and returns 0 with the setup log as `OUT_LOG`.
3. `suite_check`. Replace `[ -f "$st" ] || return 0` (right after `st=$ws/task-$target-step.json`) with a call to `require_step_file "$st"`. `suite_check` runs in `do_verdict`'s own shell, so the exit 6 ends the verdict; for a single task `st` is the file `do_verdict` already read, and for `verdict --group` it is the last member's step file. Add a sentence to the comments of `suite_base_lines` and `suite_gap`: STEP_FILE has passed `require_step_file` in the caller.
4. `cmd_rereview`: (a) right after the "rereview before review" exit-6 block (before `round=` is read), refuse `--base` for a sequential group member: when `base_arg` is non-empty, the step file has a non-empty `.group` and an empty `.head`, print `task-step: --base does not apply to a group member; see delegated-task.md §3a` on stderr and `exit 2`, before any write. A task with a head ref keeps `--base`. (b) In the `if [ "$skip" -eq 1 ]` block, call `require_step_file "$state"` on its own line directly before the `suite_why=$(suite_gap …)` assignment, so a parse failure is not lost inside `$(…)`.
5. `delegated-task.md`: in the `--covered` paragraph, "A red fix-head suite can make `--covered` run the suite once at the base commit, which takes up to ten minutes: start", change "which takes up to ten minutes: start" to "which takes up to an hour (`TASK_STEP_BASE_TIMEOUT`): start". A wrap after "an hour" is fine. Leave the "up to ten minutes each" figure for `baseline` items elsewhere unchanged.

Do not change the 3600-second default of the suite's base run, the 600-second bound of `baseline` items, `suite_base_lines`' reuse order, or any message other than the setup-failure line.

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash -n plugins/dforge/scripts/task-step`
Expected: no output.

Run: `timeout 600 bash plugins/dforge/tests/task-step-base.test.sh`
Expected: `80 passed, 0 failed`.

Do not run `plugins/dforge/tests/task-step.test.sh` yourself (about 22 minutes, longer than one bounded command may wait): the controller runs the full suite beside the review, and that run covers your change to it. Check the edited group check by reading it: it now expects `rereview --base` on a sequential member to exit 2.

- [ ] **Step 5: Check that the regression pins bite**

Fixture Tasks 15 to 18 pass before the change, so show that each fails when the behaviour it pins is broken. For each edit below, make it in `task-step`, run `timeout 600 bash plugins/dforge/tests/task-step-base.test.sh`, expect the named FAIL, then undo the edit by hand:
- In `suite_base_lines`, change `if [ -n "$row" ]; then` to `if [ -n "$row" ] && [ "$(cut -f4 <<<"$row")" != 0 ]; then`: expect FAIL "task 15: no base run and no base failures file".
- In `suite_base_lines`, change `if [ "$code" != 124 ] && [ -f "$log" ]; then` to `if [ -f "$log" ]; then`: expect FAIL "task 16: a timed-out base row falls through to a base run".
- In `suite_base_lines`, delete the line `[ -n "$row" ] || [ -z "$dir" ] || row=$(suite_row "$step" "$base" "$dir")`: expect FAIL "task 17: no base run and no base failures file".
- In `cmd_rereview`, delete the `.head` empty test from the refusal condition: expect FAIL "task 18: rereview --base on a grouped wave task is accepted and recorded".

Run: `timeout 600 bash plugins/dforge/tests/task-step-base.test.sh`
Expected: `80 passed, 0 failed` once every edit is undone.

- [ ] **Step 6: Commit**

```bash
git add plugins/dforge/scripts/task-step plugins/dforge/reference/delegated-task.md plugins/dforge/tests/task-step-base.test.sh plugins/dforge/tests/task-step.test.sh
git commit -m "fix(dforge): harden task-step base runs" -m "Bound and log the worktree setup, refuse rereview --base on a sequential group member, and fail on an unreadable step file instead of reading it as no suite."
```

### Task 7: Suite findings and exists checks

**Files:**
- Modify: `plugins/dforge/scripts/task-step` (`suite_check`, `do_verdict`, and the symbol search in `settle_item`)
- Modify: `plugins/dforge/reference/delegated-task.md` (the `suite: red` bullet in "The suite line", and the sentence about the report's `## Verified` section in "The suite runs beside the review")
- Test: `plugins/dforge/tests/task-step-suite.test.sh`
- Test: `plugins/dforge/tests/task-step-settle.test.sh` (shared with Task 5, which lands first in an earlier wave; append the new section after Task 5's, before the final `printf`)

**Interfaces:**
- Consumes: nothing new. Task 5 and Task 6 have edited `task-step` and the shared test file before this task starts.
- Produces: the digest line `suite: <k> more failing lines in <fix file>` when more than 20 suite findings exist; one `Important` suite finding per new failing line in the fix file, with no cap.

**Items:** 36, 39, 42, 53

**Depends on:** Task 5, Task 6

**Implementer:** dforge:impl-sonnet-high
**Evaluation:** files 1 - spec 2 - coupling 0 - risk 2 = 5

Rows 36, 39, 42 and 53, with the spec's A8, A11 and the settle half of A12:

- Every non-baseline failing line becomes an Important finding in the fix file and in the Important count. Only the digest shows 20 of them.
- A symbol found only in a binary file reads as absent.
- A root file written `./<name>` is a path when `verdict` runs from a subdirectory (the strip already exists; the test pins it).
- The doc says the last `## Verified` section is the current evidence.

- [ ] **Step 1: Write the failing tests**

1. In `task-step-suite.test.sh`, after the line `SUITE="$P/scripts/suite-run"` add:

```bash
DT="$P/reference/delegated-task.md"
```

2. Directly before the comment line `# --- verdict: a run cut short is red even when its partial log shows only baseline lines ---` add:

```bash
# --- verdict: every new failing line reaches the fix file, the digest shows the first 20 ---
failing=()
for i in $(seq 1 25); do failing+=("$(printf 'not ok %d - case-%02d' "$i" "$i")"); done
commit_result "${failing[@]}"
H7=${HEAD_SHA:0:7}
set_review 1 "$HEAD_SHA" "$REPO"
rm -f "$WS"/task-1-fix-*.md
run_suite
step verdict docs/plan.md 1
check "verdict, 25 failing lines: the suite line counts them all" "$rc $(grep '^suite: red' <<<"$out")" "0 suite: red (25 failing, 0 baseline)"
check "verdict, 25 failing lines: the findings line counts 25 Important" "$(grep '^findings: ' <<<"$out")" "findings: 0 Critical, 25 Important, 0 Minor"
check "verdict, 25 failing lines: the fix file holds all 25" "$(grep -c '^- suite: suite: not ok - case-' "$WS/task-1-fix-1.md")" "25"
check "verdict, 25 failing lines: the digest prints 20 finding lines" "$(grep -c '^Important ' <<<"$out")" "20"
check "verdict, 25 failing lines: the digest counts the rest and names the fix file" "$(grep '^suite: ' <<<"$out" | tr '\n' ';')" \
  "suite: 5 more failing lines in $WS/task-1-fix-1.md;suite: red (25 failing, 0 baseline);"
check "verdict, 25 failing lines: the fix line counts 25" "$(grep '^fix: ' <<<"$out")" "fix: $WS/task-1-fix-1.md (25 findings)"
```

3. After the file's last `git worktree remove --force "$WT"` line and before the closing `printf '\n%d passed, %d failed\n' "$pass" "$fail"`, add:

```bash

# --- the doc says so ---
dt=$(tr -d '\r' < "$DT" | tr '\n' ' ' | tr -s ' ')
check "the doc: every failing line is in the fix file and the digest shows 20" \
  "$(grep -cF 'is in the fix file, however many; the digest shows the first 20 and then `suite: <k> more failing lines in <fix file>`.' <<<"$dt")" "1"
check "the doc: the last Verified section is the current evidence" \
  "$(grep -cF 'The last `## Verified` section of the report is the current evidence' <<<"$dt")" "1"
```

4. In `task-step-settle.test.sh`, directly before the final `printf '\n%d passed, %d failed\n' "$pass" "$fail"` line (after Task 5's named-commands block), add the block below. The binary case runs `verdict` from the repository root on purpose: `git grep` run from a subdirectory searches only that subdirectory, so a subdirectory run would hide the binary file whatever `-I` does.

```bash

# A symbol that only a binary file holds is absent, and a root file written ./<name>
# reads as a path when verdict runs from a subdirectory.
printf '\n### Task 3: Three\n\n**Files:**\n- Modify: `lib/new.sh`\n\n**Implementer:** dforge:impl-sonnet-low\n**Evaluation:** files 0 - spec 0 - coupling 1 - risk 0 = 1\n' >> "$REPO/docs/plan.md"
g add -A && g commit -qm "task 3 fixture"
ts start docs/plan.md 3
printf 'only_in_blob\0\0' > "$REPO/blob.bin"
g add -A && g commit -qm "a binary file"
ts review docs/plan.md 3
cat > "$WS/task-3-review-report.md" <<'REPORT'
## Verdict
spec: cannot-verify
quality: approved
scores: spec 15 / scope 17 / verification 12 / quality 16

## Strengths
Fine.

## Findings

## Cannot verify
- cannot-verify: exists only_in_blob at head, expect present — the symbol is named in the brief

## Assessment
Fine.
REPORT
ts verdict docs/plan.md 3
check "binary: a symbol found only in a binary file is a mismatch, absent" "$rc $(grep '^Important ' <<<"$out")" \
  "0 Important 3 cannot-verify:0 — exists only_in_blob at head, expect present — got absent"
check "binary: no ledger line cites the binary file" "$(grep -c 'Binary file' "$LEDGER")" "0"
cat > "$WS/task-3-review-report.md" <<'REPORT'
## Verdict
spec: cannot-verify
quality: approved
scores: spec 15 / scope 17 / verification 12 / quality 16

## Strengths
Fine.

## Findings

## Cannot verify
- cannot-verify: exists ./notes.txt at head, expect present — a root file

## Assessment
Fine.
REPORT
out=$(cd "$REPO/lib" && bash "$S/task-step" verdict "$REPO/docs/plan.md" 3 2>"$TMP/err"); rc=$?
check "subdirectory: ./notes.txt is a path, present at head" "$rc $(grep -cxF 'Task 3: Ruling: cannot-verify — settled by task-step check exists — path present' "$LEDGER")" "0 1"
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `timeout 300 bash plugins/dforge/tests/task-step-suite.test.sh`
Expected: 6 FAIL lines. Four are the 25-line case (the findings line reads `20 Important`; the fix file holds 20; the `suite: 5 more failing lines …` line is missing; the fix line reads `(20 findings)`), and two are the doc checks.

Run: `timeout 300 bash plugins/dforge/tests/task-step-settle.test.sh`
Expected: FAIL "binary: a symbol found only in a binary file is a mismatch, absent" and "binary: no ledger line cites the binary file" (the symbol settles as present with `Binary file …` evidence). "subdirectory: ./notes.txt is a path, present at head" passes already: it pins the existing `${target#./}` strip, and Step 5 shows it bites.

- [ ] **Step 3: Implement**

1. `suite_check`: remove the `head -n 20` cap. The loop that writes `$TMP/suite-findings` must read every line of `$TMP/suite-new` (read the file directly, `done < "$TMP/suite-new" > "$TMP/suite-findings"`, instead of piping `head -n 20` into `while`), writing one Important row per line in the same two shapes as today (`suite did not finish` lines and `fails at <head7>` lines). `suite_line` is unchanged. Adjust its comment: one row per new failing line, uncapped.
2. `do_verdict`. Add the locals `ns` and `suite_more` (both initialised to 0) and `suite_fix` (initialised empty). Three changes:
   - In the loop that reads `$TMP/suite-findings` after `cat "$TMP/suite-findings" >> "$TMP/serious"`, keep counting every row into `imp`, count rows in `ns`, and append a row to `flines` only while `ns` is 20 or less; each later row adds 1 to `suite_more`. `$TMP/serious` still receives every row, so the fix file lists all of them.
   - In the per-member fix loop, compute `fix=$ws/task-$t-fix-$(( ${r:-0} + 1 )).md` before the `r >= 2` breaker check (and drop the later duplicate assignment), and set `suite_fix=$fix` when `t` is the last member of `members` (the task whose suite findings these are).
   - Immediately after the `printf '%s\n' "${flines[@]}"` line and before the line that prints `$suite_line`, print `suite: <suite_more> more failing lines in <suite_fix>` when `suite_more` is above 0, and nothing otherwise.
   The two existing suite digest lines, the finding lines of reviewers and cannot-verify mismatches, and the fix-file format do not change.
3. `settle_item`: add `-I` to the symbol search, so the flags read `-InwF` (`git grep -I` treats a binary file as non-matching, so a symbol found only there reads as absent). Leave the `${target#./}` strip as it is.
4. `delegated-task.md`, two insertions, each without re-wrapping the existing lines around it (the other suites pin phrases that sit on those lines):
   - In "The suite line", at the end of the `suite: red (<k> failing, <b> baseline)` bullet (after "… whatever its partial log shows."), add:

```text
  Every failing line that is not a base failure is in the fix file, however
  many; the digest shows the first 20 and then
  `suite: <k> more failing lines in <fix file>`.
```

   - In "The suite runs beside the review", after "this run is the full suite." add the sentence below on the same paragraph (the only line you may re-wrap is the one it lands in):

```text
The last `## Verified` section of the report is the current evidence: a fix
round appends its own.
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bash -n plugins/dforge/scripts/task-step`
Expected: no output.

Run: `timeout 300 bash plugins/dforge/tests/task-step-suite.test.sh`
Expected: `45 passed, 0 failed`.

Run: `timeout 300 bash plugins/dforge/tests/task-step-settle.test.sh`
Expected: `38 passed, 0 failed`.

Run: `timeout 300 bash plugins/dforge/tests/delegated-suite.test.sh`
Expected: `0 failed` (its existing pins sit on lines this task did not re-wrap).

Run: `timeout 300 bash plugins/dforge/tests/task-step-text.test.sh`
Expected: `0 failed`.

- [ ] **Step 5: Check that the subdirectory pin bites**

In `settle_item`, change `git cat-file -e "$sha:${target#./}"` to `git cat-file -e "$sha:$target"`, run `timeout 300 bash plugins/dforge/tests/task-step-settle.test.sh`, expect FAIL "subdirectory: ./notes.txt is a path, present at head", then undo the edit by hand and run it again for `38 passed, 0 failed`.

- [ ] **Step 6: Commit**

```bash
git add plugins/dforge/scripts/task-step plugins/dforge/reference/delegated-task.md plugins/dforge/tests/task-step-suite.test.sh plugins/dforge/tests/task-step-settle.test.sh
git commit -m "fix(dforge): uncap suite findings" -m "Write every new failing line to the fix file and show 20 in the digest, ignore binary files when settling a symbol, and pin the ./<name> path check."
```
