# Cockpit Live State and Layouts Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: the skill the **Execution:** line names — dr-superpowers:subagent-driven-development for `subagent`, dr-superpowers:executing-plans for `inline`. Steps use checkbox (`- [ ]`) syntax for tracking.

> **External executors:** codex

**Goal:** The cockpit shows a `◐ background` state and holds the Done notification while the main conversation's background work runs; it re-reads its settings, run ledger and git state while visible; it offers a dense one-line-per-section pane; and minimized on the terminal it draws as a framed box below the prompt.

**Architecture:** Shell rows learn which loop started them, so `isMainBackground` can tell the main conversation's work from a subagent's; `turn.complete` holds Done in `S.heldDone` and a release timer, the watchdog cap and `session.end` settle it. A session-long 2 s poll does nothing unless the pane is placed or the cockpit minimized, then re-applies changed settings, re-reads a changed ledger, and every fifth tick refreshes git and the breakdown. `lib.ts` gains pure builders for the dense rows, the background Now row and the box's bottom rule; a `PromptHint` render hook draws the minimized band there on the terminal, sized to leave the widest permission-mode label its room.

**Tech Stack:** The TypeScript/TSX cockpit mod in `plugins/dforge/hooks/cockpit/` (Claude Code 2.1.304 mod API), tested by `claude plugin test`; the Node.js ESM settings schema `plugins/dforge/config/schema.mjs`; Markdown docs.

**Spec:** `docs/superpowers/specs/2026-10-21-cockpit-live-state-design.md`

**Execution:** inline — `claude --model sonnet --effort high` — 1 of 10 tasks is heavy (Task 1, total 5) and five carry a Codex `**Executor:**` line (Tasks 2, 5, 6, 7, 8), so six tasks are delegated; the four self-implemented tasks (3, 4, 9, 10) total at most 4 (`impl-sonnet-medium`, effort medium), raised to high because tasks are delegated

**Plan review:** 2026-10-21 — dr-superpowers:judge-opus — executability 17 / coherence 18 / coverage 16 / assumptions 15 (round 1)

**Parallelism:** sequential — the spec's Execution strategy is sequential: every part edits `hooks/cockpit/register.tsx` and `tests/cockpit.test.ts`

## Global Constraints

- Work in a worktree branched from local `main` (local `main` runs ahead of `origin/main`): `git worktree add .claude/worktrees/cockpit-live-state -b cockpit-live-state main`. This plan and its spec must be on local `main` first: before Task 1, `ls docs/superpowers/plans/2026-10-21-cockpit-live-state.md` in the worktree must list the file, or stop. Do not push.
- Never edit anything under `docs/superpowers/`: it is history (the register rows are set by the execution skill's own scripts, not by hand).
- Run each command on its own line; do not chain commands that mention git with `&&`, `;` or a pipe (the worktree guard refuses them).
- Run the cockpit suite from the worktree root under a bound, with the host's `CLAUDE_CONFIG_DIR` removed: `env -u CLAUDE_CONFIG_DIR timeout 300 /root/.local/bin/claude plugin test plugins/dforge`. It has no filter: every run executes the whole of `tests/cockpit.test.ts` (25 to 45 seconds). In this host's Bash `claude` is a shell function that exits 127: call `/root/.local/bin/claude`.
- Every edit step is an exact replacement: the "replace" text must occur exactly once in the named file, unless the step says "every occurrence". Text that is not found, or found more often than the step says, is a stop: report BLOCKED with the file and the text. Never paraphrase an edit, and apply a task's edits in the order written.
- The suite passed 302 tests, 0 failing, on main 0256c1e. Each task's check is `0 fail`; the pass counts quoted are the prototype's.
- An existing test that fails after a task's edits is a stop, not a test to change: report it with the failure, unless the task's steps change that test.
- Commits: `<type>(<scope>): <subject>`, subject at most 50 characters, imperative, no period; author and committer `Darkraise <quangtc94@gmail.com>` (the repository's `user.name`/`user.email`); no `Co-Authored-By:`, `Claude-Session:` or "Generated with" line, nor any other AI attribution.
- No version bump in any manifest: a release is a separate commit the owner asks for.
- English only. Match the surrounding code: no new comments beyond those written in the steps.
- Stop every process a check starts. Task 9's smoke run starts a tmux session and a nested Claude Code; kill both before the task ends.

## Contracts

- **C1 Shell owner.** `CockpitShell` (`plugins/dforge/types/index.d.ts`) gains `agentId?: string | null`: the subagent whose loop started the shell, `null` for the main conversation's, absent on a row saved before. `trackShells` sets it from the tool call's `agentId`. A subagent's `turn.complete` drops that subagent's shell rows. A `TaskStop`/`KillShell`/`KillBash` naming a spawn's `agentId` marks that spawn `isDone: true, outcome: 'failed'`.
- **C2 Background activity.** `CockpitActivity.kind` and `ActivityInput.kind` (`hooks/cockpit/lib.ts`) gain `'background'`. `lib.ts` exports `type ActivityWork = { shells: readonly { command: string; startedAt: number }[]; agents: number }`, `nowLine(now: ActivityInput, at: number, work: ActivityWork = { shells: [], agents: 0 }): Run[]` (the background row is `◐ background · <n> shell(s) · <newest command, first line, 40 chars> · <age of the oldest> · <n> agent(s)`, each part left out when empty) and `isTypedPrompt(text: string): boolean` (true unless the text is blank or contains `<task-notification>`). A module-private `commandExcerpt(command: string, width: number): string` in `lib.ts` cuts a command's first line to `width` characters with `…`.
- **C3 The hold.** `register.tsx`: `RELEASE_GRACE_MS = 5_000`; `S.heldDone: { startedAt: number; heldAt: number } | null`; `S.releaseTimer: Timer | null`; top-level `isMainBackground($)`, `sendDone($, answer: string, durationMs: number)`, `settleBackground($)`, `releaseHeld($)`. The pane's render scope defines `work: ActivityWork` (main-loop shells and the running spawns' count) right after `actNow`, and both `nowLine` calls pass it.
- **C4 The poll.** `register.tsx`: `POLL_MS = 2_000`, `DETAIL_EVERY = 5`; `S.poll`, `S.isPolling`, `S.polls`, `S.detailAt`, `S.seen: { config: number | null; claude: string }`; top-level `pollTick($)`, `rereadSettings($)`, `markSettingsSeen($)`, `engineSettings($)`. `session.start` starts `S.poll`; `session.end` cancels it; `applySettings` ends with `markSettingsSeen`; `refreshDetail` stamps `S.detailAt`.
- **C5 Run gating.** `S.runKey: string` and `S.runPlan: string | null`; `readRun` skips the ledger and plan reads while `<ledger path>:<ledger mtime>:<plan mtime>` is unchanged and a run is shown, and writes the `run` atom only when the summary differs.
- **C6 Dense rows.** `lib.ts` exports `type DenseInput` (fields `email`, `billing`, `remote`, `context`, `turnsLeft`, `limits`, `shells`, `agents`, `run`, `todos`, `repo`, `refused`, `now`, as Task 6 writes them) and `denseLine(section: Section, input: DenseInput): Run[] | null`. Each row starts with a five-cell label: `acct `, `ctx  `, `lim  `, `$    `, `agt  `, `plan `, `⎇    `, `grd  `.
- **C7 Density.** `config/schema.mjs` key `density`: `type: 'enum'`, `values: ['detailed', 'dense']`, `default: 'detailed'`, `group: 'Cockpit'`, `target: 'dforge'`. `Options.density: string`; `Live.density: 'detailed' | 'dense'` (anything else reads `detailed`). The pane's render scope defines `isDense`; the toggle `Button` is keyed `pane-density`, labelled `Dense` or `Detailed`, hotkey `d`. The dense pane's rows are `Box`es keyed `dense-now` and `dense-<section>`.
- **C8 Band helpers.** `lib.ts` exports `MODE_LABEL_RESERVE = 29`, `bottomRule(label: string | null, width: number): { lead: string; label: string; tail: string }` (the three parts are exactly `width` cells together) and `BandInput.isBackground?: boolean` (line 2 then leads with `◐ `).
- **C9 The box.** `drawBand($, e: RenderInput<'Pane' | 'AbovePrompt' | 'PromptHint'>, onExpand, room: number, hint: string | null = null)`. A `ui.render { component: 'PromptHint' }` hook draws it on the terminal while minimized, with `room = e.viewport.columns - 2 - MODE_LABEL_RESERVE` (`FRAME_MIN_COLUMNS - 1` with no viewport); `AbovePrompt` draws the minimized band only off the terminal. `tests/cockpit.test.ts` gains `minimized(surface, viewport?)`, the mount input of where a minimized cockpit draws.

## Assumptions (evidence)

- **The plan's edits are a passing prototype.** On 2026-10-21 every edit of Tasks 1-10 was replayed in order on a copy of `plugins/` at main 0256c1e, the suite run at each task's fail and pass steps: every replacement matched as the step says, the counts matched the Expected lines, no existing test broke, and Task 10 ended at 329 pass, 0 fail. The replay corrected three test edits now in the plan (two 40-cell excerpts, and the session-end test, which needs the harness's `session.end` stub and a 90 s wait to be able to fail). Task 5's comment placement, its `S.runKey` reset at session start and Task 9's `Math.max(10, …)` floor were added afterwards and re-run on that prototype: 329 pass, 0 fail. After plan review round 1, Task 5's read-counting test was added: on the prototype it passed with the gate (330 pass, 0 fail) and failed with the `runKey` line removed (`reads an unchanged ledger no more, however many ticks pass`). `dforge-config.test.sh` (195 pass), `settings-skills.test.sh` (121 pass) and the schema validator passed on it too. Not replayed: Task 9's tmux smoke run and Task 10's full repository validation.
- **The box draws below the prompt.** On 2026-10-21 a throwaway mod returning a bordered `Box` from `ui.render { component: 'PromptHint' }` drew under the prompt, below a `statusLine` command's output, after the permission-mode label, in Claude Code 2.1.304 (spec §Probe).
- **The widest mode label ends at column 29.** The same probe launched with `--permission-mode` default, acceptEdits, plan, bypassPermissions, dontAsk and auto put the box's `╭` at columns 21, 23, 19, 29, 20 and 20 (`  ⏵⏵ bypass permissions on · ` is the widest, its 2-cell margin included), measured 2026-10-21. `MODE_LABEL_RESERVE = 29` leaves an 80-column terminal a 49-cell box, framed (`FRAME_MIN_COLUMNS` is 48).
- **`PromptHint` hands its hint as `e.props.hint`.** The engine's typings declare `PromptHint: { isDraft; isWorking; hint: string; tail?: string }` (`plugins/dforge/.claude-plugin/types/claude-code/index.d.ts`, the `PromptHint` render props), and the 2026-10-21 probe drew `hint was: ← for agents` from `e.props.hint`. The test world's stand-in renderer draws `tail`, so only Task 9's smoke run checks the real engine; its Expected line names it.
- **The smoke setup works on this host.** A nested Claude Code in tmux with a scratch `CLAUDE_CONFIG_DIR`, a dummy approved API key, `IS_SANDBOX=1`, node from `/root/.nvm/versions/node/v24.18.0/bin` and `--plugin-dir` loading a mod ran on 2026-10-21 for the probe (memory note `driving-nested-claude-smoke-runs`); `tmux` is `/usr/bin/tmux`.
- **The mod cannot read the live permission mode.** It appears only on `agent.spawn` (`permissionMode`), and the cockpit reads `permissions.defaultMode` from settings (`register.tsx` `readWhere`); hence the fixed reserve.
- **What `turn.start`'s `e.text` carries on a task-notification wake-up.** Unverified — no signed-in scratch configuration exists for a model turn. The engine documents `""` for a continuation (`TurnStartInput.text`); `isTypedPrompt` treats both `""` and text holding `<task-notification>` as a continuation, so either shape keeps the chain. Task 9's smoke run records it if a model turn is possible, and says so if not.
- **A background agent's task id is its agent id.** Unverified; Task 1 marks a spawn done when a stop names its `agentId`. If the ids differ, the 30-minute cap in Task 3 still releases the hold.
- **Subagent turn starts reach the cockpit's `turn.start` hook.** The engine says the hooks a spawn was nested in do not hear its start but "every other hook does" (`TurnStartInput.agentId`); today's hook sets the main Now row to running for them. Task 3 returns early for `e.agentId !== undefined`; no existing test starts a subagent turn (`grep "turn.start({[^}]*agentId"` found none on 2026-10-21).
- **The poll runs for the session and gates itself.** The engine raises no event when a waiting pane becomes placed, and the mod's own `$.ui.close` did not reach its `ui.close` hook under `claude plugin test` (`register.tsx` `minimize`), so instead of starting and stopping on open and close (spec §2's `syncPoll`) the 2 s timer runs from `session.start` to `session.end` and a tick returns at once unless `isPaneUp` or `isMinimized`: the same observable rule, with one `$.ui.panes()` call per idle tick.
- **A non-object config file redraws through `$.ui.invalidate`.** `S.settingProblems` is not an atom, so `rereadSettings` invalidates once when it records the problem; that is the poll's only explicit redraw.
- **An unchanged tick reads no ledger.** Task 5 gives `signedIn` an optional `reads` log and asserts no ledger read across five idle ticks; the summary comparison before the `run` write is checked by review. While no run is shown (an older finished ledger cleared in a plan session) the gate stays open and the ledger is read each tick, a cost accepted over keying the clear path. The dense rows also leave out `account` with no email and `repo` with no reading, beyond the spec's list, since an empty label row says nothing.
- **The drawn tree keeps keys only on `Box`, `Button`, `Input` and `Select`** (cockpit-native-desktop plan, 2026-10-18), which is why the dense rows sit in keyed `Box`es.
- **Nothing type-checks the mod.** `claude plugin test` and `claude plugin validate` run no type check (2026-10-18), so the code is given verbatim.
- **Codex executes the lane-eligible tasks.** `codex-gate` printed `usable=true reason=ok review=true lane=true resets_at=- source=probe` on 2026-10-21, `detect-executors.sh` reported `codex` usable, and `docs/superpowers/distilled/constraints.md` ("The Codex executor lane is on") ticks it without asking. Tasks 1, 3, 4 and 9 (risk 2) and Task 10 (total 1) fall outside the lane gate.

## Task index

1. Record which loop started each background shell
2. Draw the background state in the Now row
3. Hold the Done notification for background work
4. Poll the settings while the cockpit is visible
5. Re-read the run ledger only when it changed
6. Build the dense pane's rows
7. Add the density setting and the dense pane
8. Add the band helpers for the box below the prompt
9. Draw the minimized cockpit below the prompt
10. Document the live state, density and the box

---

### Task 1: Record which loop started each background shell

**Files:**
- Modify: `plugins/dforge/types/index.d.ts`
- Modify: `plugins/dforge/hooks/cockpit/register.tsx`
- Test: `plugins/dforge/tests/cockpit.test.ts`

**Interfaces:**
- Consumes: nothing.
- Produces: C1.

**Items:** 1

**Implementer:** dr-superpowers:impl-sonnet-high
**Evaluation:** files 1 - spec 0 - coupling 2 - risk 2 = 5

- [ ] **Step 1: Write the failing tests**

In `plugins/dforge/tests/cockpit.test.ts`, replace:

```ts
    await $.session.append(notified(`[SYSTEM NOTIFICATION - NOT USER INPUT]\n\n${ENDED}`, 'agent-1'))
    ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    expect(await ui.find({ key: 'shells' })).toBeUndefined()
  })
```

with:

```ts
    await $.session.append(notified(`[SYSTEM NOTIFICATION - NOT USER INPUT]\n\n${ENDED}`, 'agent-1'))
    ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    expect(await ui.find({ key: 'shells' })).toBeUndefined()
  })

  test("drops a subagent's shells when the subagent ends", async ($, on) => {
    world(on, { ...SIGNED_IN, tools: { Bash: () => SHELL } })
    signedIn(on)
    await $.session.start(START)
    await $.agent.spawn({ tool_use_id: 'toolu_1', prompt: 'Implement', description: 'Task 1', subagentType: 'dforge:impl-sonnet-low', provider: { plugin: 'dforge', tier: 'user' }, parentModel: 'claude-opus-5-5', background: true, fork: false })
    await $.tool.call({ tool: 'Bash', command: 'npm test', run_in_background: true, agentId: 'agent-1' } as never)
    let ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    expect(await ui.find({ type: 'Text', text: /^\$ npm test/ })).toBeDefined()
    await ui.unmount()
    await $.turn.complete({ answer: 'ok', durationMs: 1_000, isAborted: false, turnId: 'a1', reason: 'answer', agentId: 'agent-1' })
    ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    expect(await ui.find({ key: 'shells' })).toBeUndefined()
  })

  test('a stop naming a background agent ends its spawn', async ($, on) => {
    world(on, { ...SIGNED_IN, tools: { TaskStop: () => ({ result: { task_id: 'agent-1' }, text: 'stopped' }) } })
    signedIn(on)
    await $.session.start(START)
    await $.agent.spawn({ tool_use_id: 'toolu_1', prompt: 'Review', description: 'Review the branch', subagentType: 'dforge:judge-opus', provider: { plugin: 'dforge', tier: 'user' }, parentModel: 'claude-opus-5-5', background: true, fork: false })
    await $.tool.call({ tool: 'TaskStop', task_id: 'agent-1' } as never)
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    expect(await ui.find({ type: 'Text', text: /^Failed · 1$/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /^Working · / })).toBeUndefined()
  })
```

- [ ] **Step 2: Run the suite and verify the new tests fail**

Run: `env -u CLAUDE_CONFIG_DIR timeout 300 /root/.local/bin/claude plugin test plugins/dforge`
Expected: 2 fail — `drops a subagent's shells when the subagent ends` (the shell row stays) and `a stop naming a background agent ends its spawn` (the agent stays under Working).

- [ ] **Step 3: Record the shell's owner in the type**

In `plugins/dforge/types/index.d.ts`, replace:

```ts
  /** When it went to the background, in milliseconds since the epoch. */
  startedAt: number
}

/** Remote Control as the cockpit sees it. */
```

with:

```ts
  /** When it went to the background, in milliseconds since the epoch. */
  startedAt: number
  /** The subagent whose loop started it; null for the main conversation's, absent on a row saved before it was kept. */
  agentId?: string | null
}

/** Remote Control as the cockpit sees it. */
```

- [ ] **Step 4: Set the owner, end a stopped agent, and drop a finished subagent's shells**

In `plugins/dforge/hooks/cockpit/register.tsx`, replace:

```ts
    const shell: CockpitShell = { id, command: String((e as { command?: unknown }).command ?? ''), startedAt: await $.clock.now() }
```

with:

```ts
    const shell: CockpitShell = { id, command: String((e as { command?: unknown }).command ?? ''), startedAt: await $.clock.now(), agentId: (e as { agentId?: string }).agentId ?? null }
```

Then replace:

```ts
    if (typeof id === 'string') {
      await update($, shells, list => list.filter(one => one.id !== id))
      await syncTicker($)
    }
```

with:

```ts
    if (typeof id === 'string') {
      await update($, shells, list => list.filter(one => one.id !== id))
      await update($, spawns, all => all.map(one => (one.agentId === id && !one.isDone ? { ...one, isDone: true, outcome: 'failed' as const } : one)))
      await syncTicker($)
    }
```

Then replace:

```ts
    await update($, spawns, all => all.map(one => (one.agentId === agentId ? { ...one, isDone: true, outcome } : one)))
```

with:

```ts
    await update($, spawns, all => all.map(one => (one.agentId === agentId ? { ...one, isDone: true, outcome } : one)))
    // A notification for a finished subagent's loop may never arrive: its shells end with it.
    await update($, shells, list => list.filter(one => one.agentId !== agentId))
```

- [ ] **Step 5: Run the suite and verify it passes**

Run: `env -u CLAUDE_CONFIG_DIR timeout 300 /root/.local/bin/claude plugin test plugins/dforge`
Expected: 304 pass, 0 fail.

- [ ] **Step 6: Commit**

```bash
git add plugins/dforge/types/index.d.ts plugins/dforge/hooks/cockpit/register.tsx plugins/dforge/tests/cockpit.test.ts
git commit -m "feat(cockpit): track which loop owns each shell"
```

### Task 2: Draw the background state in the Now row

**Files:**
- Modify: `plugins/dforge/types/index.d.ts`
- Modify: `plugins/dforge/hooks/cockpit/lib.ts`
- Test: `plugins/dforge/tests/cockpit.test.ts`

**Interfaces:**
- Consumes: nothing.
- Produces: C2.

**Items:** 1

**Implementer:** dr-superpowers:impl-sonnet-medium
**Executor:** codex gpt-6.1-sol / medium
**Evaluation:** files 1 - spec 0 - coupling 2 - risk 0 = 3

- [ ] **Step 1: Write the failing test**

In `plugins/dforge/tests/cockpit.test.ts`, replace:

```ts
  isAtLeast,
  levelOf,
```

with:

```ts
  isAtLeast,
  isTypedPrompt,
  levelOf,
```

Then replace:

```ts
    expect(elapsed(3_725_000)).toBe('1h02m')
  })
```

with:

```ts
    expect(elapsed(3_725_000)).toBe('1h02m')
  })

  test('reads the background state with what still runs', () => {
    const at = 200_000
    const two = { shells: [{ command: 'npm test', startedAt: 140_000 }, { command: 'node codex-companion.mjs review --background\nsecond line', startedAt: 20_000 }], agents: 1 }
    expect(flat(nowLine({ ...IDLE, kind: 'background' }, at, two))).toBe('◐ background · 2 shells · npm test · 3m · 1 agent')
    const long = { shells: [{ command: 'node codex-companion.mjs review --background', startedAt: 20_000 }], agents: 0 }
    expect(flat(nowLine({ ...IDLE, kind: 'background' }, at, long))).toBe('◐ background · 1 shell · node codex-companion.mjs review --backg… · 3m')
    expect(flat(nowLine({ ...IDLE, kind: 'background' }, at, { shells: [], agents: 2 }))).toBe('◐ background · 2 agents')
    expect(flat(nowLine({ ...IDLE, kind: 'background', isSent: true }, at, { shells: [], agents: 1 }))).toBe('◐ background · 1 agent · Discord ✓')
  })

  test('tells a typed prompt from a continuation', () => {
    expect(isTypedPrompt('go')).toBe(true)
    expect(isTypedPrompt('')).toBe(false)
    expect(isTypedPrompt('  \n')).toBe(false)
    expect(isTypedPrompt('<task-notification>\n<task-id>b7k2</task-id>\n<status>completed</status>\n</task-notification>')).toBe(false)
  })
```

- [ ] **Step 2: Run the suite and verify the new tests fail**

Run: `env -u CLAUDE_CONFIG_DIR timeout 300 /root/.local/bin/claude plugin test plugins/dforge`
Expected: the file fails to load or both new tests fail: `isTypedPrompt` is not exported yet.

- [ ] **Step 3: Add the kind to the activity types**

In `plugins/dforge/types/index.d.ts`, replace:

```ts
  /** `waiting` on an approval, `asking` a question, `failed` once a turn ended in an error, `interrupted` once Esc stopped it. */
  kind: 'idle' | 'running' | 'waiting' | 'asking' | 'failed' | 'interrupted'
```

with:

```ts
  /** `waiting` on an approval, `asking` a question, `failed` once a turn ended in an error, `interrupted` once Esc stopped it, `background` once a turn ended with its shells or subagents still running. */
  kind: 'idle' | 'running' | 'waiting' | 'asking' | 'failed' | 'interrupted' | 'background'
```

In `plugins/dforge/hooks/cockpit/lib.ts`, replace:

```ts
  kind: 'idle' | 'running' | 'waiting' | 'asking' | 'failed' | 'interrupted'
```

with:

```ts
  kind: 'idle' | 'running' | 'waiting' | 'asking' | 'failed' | 'interrupted' | 'background'
```

- [ ] **Step 4: Draw the background row**

In `plugins/dforge/hooks/cockpit/lib.ts`, replace:

```ts
/** The Now row: one line, whatever the state, so the pane never jumps. */
export function nowLine(now: ActivityInput, at: number): Run[] {
```

with:

```ts
/** The main conversation's background work, as the Now row names it. */
export type ActivityWork = { shells: readonly { command: string; startedAt: number }[]; agents: number }

/** A command's first line, cut to `width` characters with an ellipsis. */
function commandExcerpt(command: string, width: number): string {
  const chars = [...(command.split('\n')[0] ?? '')]
  return chars.length <= width ? chars.join('') : `${chars.slice(0, width - 1).join('')}…`
}

/** The Now row: one line, whatever the state, so the pane never jumps. */
export function nowLine(now: ActivityInput, at: number, work: ActivityWork = { shells: [], agents: 0 }): Run[] {
```

Then replace:

```ts
    default:
      return [
        { text: '○ idle', dim: true },
```

with:

```ts
    case 'background': {
      const count = work.shells.length
      const newest = work.shells.reduce<{ command: string; startedAt: number } | null>((last, shell) => (last === null || shell.startedAt > last.startedAt ? shell : last), null)
      const oldest = Math.min(...work.shells.map(shell => shell.startedAt))
      return [
        { text: '◐ background', color: AMBER, bold: true },
        ...(count === 0 ? [] : [sep, { text: `${count} ${count === 1 ? 'shell' : 'shells'}` }]),
        ...(newest === null ? [] : [sep, { text: commandExcerpt(newest.command, 40), dim: true }]),
        ...(count === 0 ? [] : [sep, { text: shellAge(at - oldest), color: AMBER, bold: true }]),
        ...(work.agents === 0 ? [] : [sep, { text: `${work.agents} ${work.agents === 1 ? 'agent' : 'agents'}`, color: 'cyan' }]),
        ...sent,
      ]
    }
    default:
      return [
        { text: '○ idle', dim: true },
```

Then replace:

```ts
/** Whether a release (`2.1.295`) is at least `least`, compared part by part; an unreadable one is not. */
```

with:

```ts
/** Whether a main turn's text is a prompt the person typed: a continuation starts with none, a task notification's wake-up with the notification. */
export function isTypedPrompt(text: string): boolean {
  return text.trim() !== '' && !text.includes('<task-notification>')
}

/** Whether a release (`2.1.295`) is at least `least`, compared part by part; an unreadable one is not. */
```

- [ ] **Step 5: Run the suite and verify it passes**

Run: `env -u CLAUDE_CONFIG_DIR timeout 300 /root/.local/bin/claude plugin test plugins/dforge`
Expected: 306 pass, 0 fail.

- [ ] **Step 6: Commit**

```bash
git add plugins/dforge/types/index.d.ts plugins/dforge/hooks/cockpit/lib.ts plugins/dforge/tests/cockpit.test.ts
git commit -m "feat(cockpit): draw the background state"
```

### Task 3: Hold the Done notification for background work

**Files:**
- Modify: `plugins/dforge/hooks/cockpit/register.tsx`
- Test: `plugins/dforge/tests/cockpit.test.ts`

**Interfaces:**
- Consumes: C1 (`CockpitShell.agentId`), C2 (`nowLine`'s `work`, `isTypedPrompt`, the `background` kind).
- Produces: C3.

**Items:** 1

**Implementer:** dr-superpowers:impl-sonnet-medium
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 2 = 4

- [ ] **Step 1: Write the failing tests**

In `plugins/dforge/tests/cockpit.test.ts`, replace:

```ts
    await $.tool.call({ tool: 'TaskStop', task_id: 'agent-1' } as never)
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    expect(await ui.find({ type: 'Text', text: /^Failed · 1$/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /^Working · / })).toBeUndefined()
  })
```

with:

```ts
    await $.tool.call({ tool: 'TaskStop', task_id: 'agent-1' } as never)
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    expect(await ui.find({ type: 'Text', text: /^Failed · 1$/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /^Working · / })).toBeUndefined()
  })

  describe('a Done held for background work', () => {
    const titles = (fetches: NonNullable<World['fetches']>) => fetches.map(one => (one.body.embeds as Record<string, unknown>[] | undefined)?.[0]?.title)
    // A turn that sends a shell to the background and ends 30 s later, the shell still running.
    const hold = async ($: Parameters<TestBody>[0], on: On, fetches: NonNullable<World['fetches']>) => {
      const clock = world(on, { tokens: 50_000, fetches, config: { notifyAfter: 60 }, tools: { Bash: () => SHELL } })
      mock.store(on, { notifyUrl: WEBHOOK })
      await $.session.start(START)
      await $.turn.start({ text: 'review it', turnId: 't1' })
      await $.tool.call({ tool: 'Bash', command: 'node codex-companion.mjs review', run_in_background: true } as never)
      await clock.advance(30_000)
      await $.turn.complete({ answer: 'Started the review.', durationMs: 30_000, isAborted: false, turnId: 't1', reason: 'answer' })
      return clock
    }

    test('shows the background state and sends one Done after the woken turn', async ($, on) => {
      const fetches: NonNullable<World['fetches']> = []
      const clock = await hold($, on, fetches)
      expect(fetches).toHaveLength(0)
      const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
      expect(await ui.find({ type: 'Text', text: /◐ background · 1 shell · node codex-companion\.mjs review · 30s/ })).toBeDefined()
      await ui.unmount()
      await clock.advance(90_000)
      await $.session.append(notified(`[SYSTEM NOTIFICATION - NOT USER INPUT]\n\n${ENDED}`))
      await $.turn.start({ text: '', turnId: 't2' })
      await clock.advance(5_000)
      await $.turn.complete({ answer: 'Review clean.', durationMs: 5_000, isAborted: false, turnId: 't2', reason: 'answer' })
      expect(titles(fetches)).toEqual(['✅ Done in 2m05s'])
    })

    test('sends the held Done once the grace passes with no turn', async ($, on) => {
      const fetches: NonNullable<World['fetches']> = []
      const clock = await hold($, on, fetches)
      await clock.advance(90_000)
      await $.session.append(notified(ENDED))
      await clock.advance(4_000)
      expect(fetches).toHaveLength(0)
      await clock.advance(2_000)
      expect(titles(fetches)).toEqual(['✅ Done in 2m05s'])
      const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
      expect(await ui.find({ type: 'Text', text: /^○ idle/ })).toBeDefined()
    })

    test('a turn starting in the grace carries the held Done', async ($, on) => {
      const fetches: NonNullable<World['fetches']> = []
      const clock = await hold($, on, fetches)
      await clock.advance(90_000)
      await $.session.append(notified(ENDED))
      await clock.advance(1_000)
      await $.turn.start({ text: '', turnId: 't2' })
      await clock.advance(10_000)
      expect(fetches).toHaveLength(0)
      await $.turn.complete({ answer: 'Review clean.', durationMs: 10_000, isAborted: false, turnId: 't2', reason: 'answer' })
      expect(titles(fetches)).toEqual(['✅ Done in 2m11s'])
    })

    test('a typed prompt starts a new chain', async ($, on) => {
      const fetches: NonNullable<World['fetches']> = []
      const clock = await hold($, on, fetches)
      await clock.advance(60_000)
      await $.turn.start({ text: 'what next?', turnId: 't2' })
      await clock.advance(10_000)
      await $.turn.complete({ answer: 'Waiting on the review.', durationMs: 10_000, isAborted: false, turnId: 't2', reason: 'answer' })
      expect(fetches).toHaveLength(0)
      await clock.advance(60_000)
      await $.session.append(notified(ENDED))
      await $.turn.start({ text: '', turnId: 't3' })
      await clock.advance(5_000)
      await $.turn.complete({ answer: 'Review clean.', durationMs: 5_000, isAborted: false, turnId: 't3', reason: 'answer' })
      expect(titles(fetches)).toEqual(['✅ Done in 1m15s'])
    })

    test("a subagent's shell holds nothing", async ($, on) => {
      const fetches: NonNullable<World['fetches']> = []
      world(on, { tokens: 50_000, fetches, config: { notifyAfter: 0 }, tools: { Bash: () => SHELL } })
      mock.store(on, { notifyUrl: WEBHOOK })
      await $.session.start(START)
      await $.turn.start({ text: 'go', turnId: 't1' })
      await $.tool.call({ tool: 'Bash', command: 'npm test', run_in_background: true, agentId: 'agent-1' } as never)
      await $.turn.complete({ answer: 'ok', durationMs: 5_000, isAborted: false, turnId: 't1', reason: 'answer' })
      expect(titles(fetches)).toEqual(['✅ Done in 5s'])
    })

    test('the watchdog sends a hold older than the cap', async ($, on) => {
      const fetches: NonNullable<World['fetches']> = []
      const clock = await hold($, on, fetches)
      await clock.advance(1_800_000)
      expect(fetches).toHaveLength(0)
      await clock.advance(60_000)
      expect(titles(fetches)).toEqual(['✅ Done in 31m00s'])
    })

    test('a session ending in the grace sends no Done', async ($, on) => {
      const fetches: NonNullable<World['fetches']> = []
      on('session.end', (_$, e) => e as never)
      const clock = await hold($, on, fetches)
      await clock.advance(90_000)
      await $.session.append(notified(ENDED))
      await $.session.end({ reason: 'other', sessionId: 'sess-1' } as never)
      await clock.advance(10_000)
      expect(fetches).toHaveLength(0)
    })
  })
```

- [ ] **Step 2: Run the suite and verify the new tests fail**

Run: `env -u CLAUDE_CONFIG_DIR timeout 300 /root/.local/bin/claude plugin test plugins/dforge`
Expected: 5 fail — the held-Done tests (Done is sent at the first turn's end, or the Now row reads idle); `a subagent's shell holds nothing` and `a session ending in the grace sends no Done` already pass (the second guards the session-end clearing added in Step 8).

- [ ] **Step 3: Add the import, the grace and the state**

In `plugins/dforge/hooks/cockpit/register.tsx`, replace:

```ts
  isGitWriteTool,
  isDforge,
```

with:

```ts
  isGitWriteTool,
  isDforge,
  isTypedPrompt,
```

Then replace:

```ts
const STALL_MS = 180_000
```

with:

```ts
const STALL_MS = 180_000
// How long a Done held for background work waits, once the work ends, for the turn its notification wakes.
const RELEASE_GRACE_MS = 5_000
```

Then replace:

```ts
  offerRead: '',
}
```

with:

```ts
  offerRead: '',
  // A Done held while the main conversation's background work runs: when its
  // chain of turns began, and when a turn last ended with the work pending.
  heldDone: null as { startedAt: number; heldAt: number } | null,
  // Sends the held Done if no turn starts within RELEASE_GRACE_MS of the work ending.
  releaseTimer: null as Timer | null,
}
```

- [ ] **Step 4: Follow the main loop's turns only, and keep or drop the hold at a turn's start**

Replace:

```ts
  on('turn.start', async ($, e, next) => {
    const stamp = await $.clock.now()
```

with:

```ts
  on('turn.start', async ($, e, next) => {
    if (e.agentId !== undefined) return next(e)
    S.releaseTimer?.cancel()
    S.releaseTimer = null
    if (isTypedPrompt(e.text)) S.heldDone = null
    const stamp = await $.clock.now()
```

- [ ] **Step 5: Hold Done at a main turn's end while background work runs**

Replace:

```ts
      const why = failed ? failureOf(e) : null
      await readRemote($)
      await setActivity($, now => ({
        ...IDLE,
        kind: failed ? 'failed' : e.reason === 'aborted' ? 'interrupted' : 'idle',
```

with:

```ts
      const why = failed ? failureOf(e) : null
      const isHeld = e.reason === 'answer' && (await isMainBackground($))
      const turnStartedAt = (await read($, activity)).turnStartedAt ?? stamp - e.durationMs
      if (e.reason !== 'answer') S.heldDone = null
      else if (isHeld) S.heldDone = { startedAt: S.heldDone?.startedAt ?? turnStartedAt, heldAt: stamp }
      await readRemote($)
      await setActivity($, now => ({
        ...IDLE,
        kind: failed ? 'failed' : e.reason === 'aborted' ? 'interrupted' : isHeld ? 'background' : 'idle',
```

Then replace:

```ts
      } else if (e.reason === 'answer' && e.durationMs >= Math.max(0, (await live($)).notifyAfter) * 1000) {
        const messageId = await notify($, {
          kind: 'done',
          title: `✅ Done in ${elapsed(e.durationMs)}`,
          detail: e.answer.trim() === '' ? undefined : excerpt(e.answer, 300),
          fields: await turnFields($),
        })
        if (messageId !== null) await update($, activity, now => ({ ...now, isSent: true }))
      }
```

with:

```ts
      } else if (e.reason === 'answer' && !isHeld) {
        await sendDone($, e.answer, e.durationMs)
      }
```

- [ ] **Step 6: Add the hold's functions**

Replace:

```ts
// The context, cost and plan fields most messages carry.
```

with:

```ts
/**
 * Sends a turn's Done, timed from the start of the held chain when one is
 * held, else from the turn alone; one under notifyAfter sends nothing.
 */
async function sendDone($: EngineInterface, answer: string, durationMs: number) {
  const held = S.heldDone
  S.heldDone = null
  const took = held === null ? durationMs : (await $.clock.now()) - held.startedAt
  if (took < Math.max(0, (await live($)).notifyAfter) * 1000) return
  const messageId = await notify($, {
    kind: 'done',
    title: `✅ Done in ${elapsed(took)}`,
    detail: answer.trim() === '' ? undefined : excerpt(answer, 300),
    fields: await turnFields($),
  })
  if (messageId !== null) await update($, activity, now => ({ ...now, isSent: true }))
}

/** Whether the main conversation still waits on work it sent to the background: its own shells, or a subagent still running. */
async function isMainBackground($: EngineInterface): Promise<boolean> {
  if ((await read($, spawns)).some(one => !one.isDone)) return true
  return (await read($, shells)).some(one => (one.agentId ?? null) === null)
}

/**
 * The background work ended with no turn live: the Now row goes idle, and a
 * held Done waits RELEASE_GRACE_MS for the turn the work's notification wakes.
 */
async function settleBackground($: EngineInterface) {
  if ((await read($, activity)).kind !== 'background' || (await isMainBackground($))) return
  await setActivity($, now => ({ ...now, kind: 'idle' }))
  S.releaseTimer?.cancel()
  S.releaseTimer = $.clock.after(RELEASE_GRACE_MS, () => void releaseHeld($).catch(() => undefined))
}

async function releaseHeld($: EngineInterface) {
  S.releaseTimer = null
  if (S.heldDone !== null && !S.isTurnLive) await sendDone($, '', 0)
}

// The context, cost and plan fields most messages carry.
```

- [ ] **Step 7: Settle the hold wherever background work ends**

Replace:

```ts
  await update($, shells, list => list.filter(one => !ended.has(one.id)))
  await syncTicker($)
}
```

with:

```ts
  await update($, shells, list => list.filter(one => !ended.has(one.id)))
  await syncTicker($)
  await settleBackground($)
}
```

Then replace:

```ts
      await update($, spawns, all => all.map(one => (one.agentId === id && !one.isDone ? { ...one, isDone: true, outcome: 'failed' as const } : one)))
      await syncTicker($)
```

with:

```ts
      await update($, spawns, all => all.map(one => (one.agentId === id && !one.isDone ? { ...one, isDone: true, outcome: 'failed' as const } : one)))
      await syncTicker($)
      await settleBackground($)
```

Then replace:

```ts
    for (const [id, wait] of [...S.waits]) if (wait.agentId === agentId) await endWait($, id, '⏹ Agent ended')
    await syncTicker($)
```

with:

```ts
    for (const [id, wait] of [...S.waits]) if (wait.agentId === agentId) await endWait($, id, '⏹ Agent ended')
    await syncTicker($)
    await settleBackground($)
```

- [ ] **Step 8: Cap the hold in the watchdog and clear it at the session's end**

Replace:

```ts
async function watchdogTick($: EngineInterface) {
  await beat($)
```

with:

```ts
async function watchdogTick($: EngineInterface) {
  await beat($)
  if (S.heldDone !== null && !S.isTurnLive && (await $.clock.now()) - S.heldDone.heldAt > DEFER_CAP_MS) {
    if ((await read($, activity)).kind === 'background') await setActivity($, now => ({ ...now, kind: 'idle' }))
    await sendDone($, '', 0)
  }
```

Then replace:

```ts
    S.watchdog?.cancel()
    S.watchdog = null
    await setActivity($, () => IDLE)
```

with:

```ts
    S.watchdog?.cancel()
    S.watchdog = null
    S.releaseTimer?.cancel()
    S.releaseTimer = null
    S.heldDone = null
    await setActivity($, () => IDLE)
```

- [ ] **Step 9: Give the Now row the main conversation's work**

Replace:

```ts
    const actNow = act.kind === 'interrupted' ? { ...act, detail: kept.length === 0 ? 'nothing left running' : `${kept.join(' and ')} still running` } : act
```

with:

```ts
    const actNow = act.kind === 'interrupted' ? { ...act, detail: kept.length === 0 ? 'nothing left running' : `${kept.join(' and ')} still running` } : act
    const work = { shells: background.filter(one => (one.agentId ?? null) === null), agents: running.length }
```

Then replace every occurrence (two) of:

```ts
nowLine(actNow, now)
```

with:

```ts
nowLine(actNow, now, work)
```

- [ ] **Step 10: Run the suite and verify it passes**

Run: `env -u CLAUDE_CONFIG_DIR timeout 300 /root/.local/bin/claude plugin test plugins/dforge`
Expected: 313 pass, 0 fail.

- [ ] **Step 11: Commit**

```bash
git add plugins/dforge/hooks/cockpit/register.tsx plugins/dforge/tests/cockpit.test.ts
git commit -m "feat(cockpit): hold Done while background work runs"
```

### Task 4: Poll the settings while the cockpit is visible

**Files:**
- Modify: `plugins/dforge/hooks/cockpit/register.tsx`
- Test: `plugins/dforge/tests/cockpit.test.ts`

**Interfaces:**
- Consumes: C3 (`RELEASE_GRACE_MS`, the `S.releaseTimer` lines in `session.end`).
- Produces: C4.

**Items:** 2

**Implementer:** dr-superpowers:impl-sonnet-medium
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 2 = 4

- [ ] **Step 1: Write the failing tests**

In `plugins/dforge/tests/cockpit.test.ts`, replace:

```ts
describe('settings rows', () => {
```

with:

```ts
describe('polling', () => {
  test('puts an edited settings file in force within one tick', async ($, on) => {
    const files: NonNullable<World['files']> = { [CONFIG]: { text: JSON.stringify({ sections: 'context,usage' }), mtimeMs: 1 } }
    const clock = world(on, { ...SIGNED_IN, files })
    signedIn(on, files)
    await $.session.start(START)
    await $.tool.call({ tool: 'Bash', command: 'ls' })
    files[CONFIG] = { text: JSON.stringify({ sections: 'usage' }), mtimeMs: 2 }
    await clock.advance(2_000)
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    expect(await ui.find({ type: 'Button', text: '▾ Context' })).toBeUndefined()
    expect(await ui.find({ type: 'Button', text: '▾ Usage' })).toBeDefined()
  })

  test('keeps the settings in force when the file stops being a JSON object', async ($, on) => {
    const files: NonNullable<World['files']> = { [CONFIG]: { text: JSON.stringify({ sections: 'usage' }), mtimeMs: 1 } }
    const clock = world(on, { ...SIGNED_IN, files })
    signedIn(on, files)
    await $.session.start(START)
    await $.tool.call({ tool: 'Bash', command: 'ls' })
    files[CONFIG] = { text: '{ "sections": ', mtimeMs: 2 }
    await clock.advance(2_000)
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    expect(await ui.find({ type: 'Button', text: '▾ Context' })).toBeUndefined()
    expect(await ui.find({ type: 'Button', text: '▾ Usage' })).toBeDefined()
    await ui.press({ key: 'pane-settings' })
    expect(await ui.find({ type: 'Text', text: /config\.json is not a JSON object; the settings in force are kept/ })).toBeDefined()
  })

  test("puts a Claude key changed outside the pane in force", async ($, on) => {
    const w: World = { tokens: 284_000, config: {}, settings: { autoCompactWindow: 650_000 } }
    const clock = world(on, w)
    await $.session.start(START)
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    await ui.press({ key: 'pane-settings' })
    await ui.press({ key: 'settings-tab-Context' })
    expect(await ui.find({ type: 'Text', text: /^650k/ })).toBeDefined()
    w.settings = { autoCompactWindow: 700_000 }
    await clock.advance(2_000)
    expect(await ui.find({ type: 'Text', text: /^700k/ })).toBeDefined()
  })

  test('reads nothing while the cockpit is hidden', async ($, on) => {
    const gitRuns: string[] = []
    const clock = world(on, { ...SIGNED_IN, gitRuns, isPaneShut: true })
    signedIn(on)
    await $.session.start(START)
    await clock.advance(20_000)
    expect(gitRuns.filter(run => run.includes('status --porcelain=v2'))).toEqual([])
  })

  test('refreshes the git state every ten seconds while the pane is up', async ($, on) => {
    const gitRuns: string[] = []
    const clock = world(on, { ...SIGNED_IN, gitRuns })
    signedIn(on)
    await $.session.start(START)
    await clock.advance(8_000)
    expect(gitRuns.filter(run => run.includes('status --porcelain=v2'))).toEqual([])
    await clock.advance(2_000)
    expect(gitRuns.filter(run => run.includes('status --porcelain=v2'))).toHaveLength(1)
  })
})

describe('settings rows', () => {
```

- [ ] **Step 2: Run the suite and verify the new tests fail**

Run: `env -u CLAUDE_CONFIG_DIR timeout 300 /root/.local/bin/claude plugin test plugins/dforge`
Expected: `puts an edited settings file in force within one tick`, `keeps the settings in force when the file stops being a JSON object`, `puts a Claude key changed outside the pane in force` and `refreshes the git state every ten seconds while the pane is up` fail; `reads nothing while the cockpit is hidden` passes.

- [ ] **Step 3: Add the poll's constants and state**

In `plugins/dforge/hooks/cockpit/register.tsx`, replace:

```ts
const RELEASE_GRACE_MS = 5_000
```

with:

```ts
const RELEASE_GRACE_MS = 5_000
// While the cockpit is drawn its files are checked every POLL_MS, git and the context breakdown every DETAIL_EVERY ticks.
const POLL_MS = 2_000
const DETAIL_EVERY = 5
```

Then replace:

```ts
  releaseTimer: null as Timer | null,
}
```

with:

```ts
  releaseTimer: null as Timer | null,
  // The poll's timer, whether a tick is running, how many ran, and when the slower readings last ran.
  poll: null as Timer | null,
  isPolling: false,
  polls: 0,
  detailAt: 0,
  // The settings file's modification time and the engine's settings, as last put in force.
  seen: { config: null as number | null, claude: '' },
}
```

- [ ] **Step 4: Start the poll with the session and stop it at its end**

Replace:

```ts
    S.watchdog = $.clock.every(WATCHDOG_MS, () => void watchdogTick($).catch(() => undefined))
```

with:

```ts
    S.watchdog = $.clock.every(WATCHDOG_MS, () => void watchdogTick($).catch(() => undefined))
    S.poll?.cancel()
    S.poll = $.clock.every(POLL_MS, () => void pollTick($).catch(() => undefined))
```

Then replace:

```ts
    S.releaseTimer?.cancel()
    S.releaseTimer = null
    S.heldDone = null
```

with:

```ts
    S.releaseTimer?.cancel()
    S.releaseTimer = null
    S.heldDone = null
    S.poll?.cancel()
    S.poll = null
```

- [ ] **Step 5: Record what was put in force, and when the slower readings ran**

Replace:

```ts
  await update($, settings, () => values)
  applyNotify(liveFrom(values as Partial<Options>))
}
```

with:

```ts
  await update($, settings, () => values)
  applyNotify(liveFrom(values as Partial<Options>))
  await markSettingsSeen($)
}
```

Then replace:

```ts
async function refreshDetail($: EngineInterface) {
  await readPlace($)
```

with:

```ts
async function refreshDetail($: EngineInterface) {
  S.detailAt = await $.clock.now()
  await readPlace($)
```

- [ ] **Step 6: Add the poll's functions**

Replace:

```ts
// The pane's slower readings: the /context breakdown, estimated locally, and
```

with:

```ts
/** Records the settings file's modification time and the engine's settings as the ones in force, so the poll re-reads only a change. */
async function markSettingsSeen($: EngineInterface) {
  const path = await configFile($)
  const stat = path === null ? null : await $.fs.stat(path).catch(() => null)
  S.seen = { config: stat?.kind === 'file' ? stat.mtimeMs : null, claude: await engineSettings($) }
}

/** The engine's user and merged settings as one string, to compare between ticks. */
async function engineSettings($: EngineInterface): Promise<string> {
  const user = await $.settings.read({ source: 'user' }).catch(() => null)
  const merged = await $.settings.read().catch(() => null)
  return JSON.stringify([user, merged])
}

/**
 * One poll tick: nothing unless the pane is placed or the cockpit minimized;
 * then changed settings and the run, and every DETAIL_EVERY ticks the slower
 * readings and the auto run.
 */
async function pollTick($: EngineInterface) {
  if (S.isPolling) return
  S.isPolling = true
  try {
    if (!(await live($)).isMinimized && !(await isPaneUp($))) return
    S.polls += 1
    await rereadSettings($)
    await readRun($)
    if (S.polls % DETAIL_EVERY !== 0) return
    if ((await $.clock.now()) - S.detailAt >= DETAIL_EVERY * POLL_MS) await refreshDetail($)
    await trackAutoRun($)
  } finally {
    S.isPolling = false
  }
}

/** Puts the settings in force again when the file or the engine's settings changed; a file that is not a JSON object keeps the values in force. */
async function rereadSettings($: EngineInterface) {
  const path = await configFile($)
  const stat = path === null ? null : await $.fs.stat(path).catch(() => null)
  const mtime = stat?.kind === 'file' ? stat.mtimeMs : null
  const claude = await engineSettings($)
  if (mtime === S.seen.config && claude === S.seen.claude) return
  const file = path === null ? {} : await readSettingsFile($, path)
  if (file === null) {
    S.seen = { config: mtime, claude }
    const problem = `${path} is not a JSON object; the settings in force are kept`
    if (!S.settingProblems.includes(problem)) S.settingProblems = [...S.settingProblems, problem]
    $.ui.invalidate('ui.render')
    return
  }
  await applySettings($, file)
}

// The pane's slower readings: the /context breakdown, estimated locally, and
```

- [ ] **Step 7: Run the suite and verify it passes**

Run: `env -u CLAUDE_CONFIG_DIR timeout 300 /root/.local/bin/claude plugin test plugins/dforge`
Expected: 318 pass, 0 fail.

- [ ] **Step 8: Commit**

```bash
git add plugins/dforge/hooks/cockpit/register.tsx plugins/dforge/tests/cockpit.test.ts
git commit -m "feat(cockpit): re-read settings while visible"
```

### Task 5: Re-read the run ledger only when it changed

**Files:**
- Modify: `plugins/dforge/hooks/cockpit/register.tsx`
- Test: `plugins/dforge/tests/cockpit.test.ts`

**Interfaces:**
- Consumes: C4 (the poll calls `readRun` every tick; the `seen` line of `S`).
- Produces: C5.

**Items:** 2

**Implementer:** dr-superpowers:impl-sonnet-medium
**Executor:** codex gpt-6.1-sol / medium
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 1 = 3

- [ ] **Step 1: Write the tests**

In `plugins/dforge/tests/cockpit.test.ts`, replace:

```ts
function signedIn(on: On, files: World['files'] = {}) {
  on('fs.read', (_$, e) => {
    const file = files[e.path]
```

with:

```ts
function signedIn(on: On, files: World['files'] = {}, reads?: string[]) {
  on('fs.read', (_$, e) => {
    reads?.push(e.path)
    const file = files[e.path]
```

Then replace:

```ts
    expect(drawn.indexOf('Task 3: Ship it')).toBeLessThan(drawn.indexOf('Task 1: Add the helpers'))
  })
```

with:

```ts
    expect(drawn.indexOf('Task 3: Ship it')).toBeLessThan(drawn.indexOf('Task 1: Add the helpers'))
  })

  test('reads an unchanged ledger no more, however many ticks pass', async ($, on) => {
    const files = runFiles(LEDGER) ?? {}
    const reads: string[] = []
    const clock = world(on, { ...SIGNED_IN, files })
    signedIn(on, files, reads)
    await $.tool.call({ tool: 'Skill', skill: 'dforge:subagent-driven-development' })
    await $.session.start(START)
    await clock.advance(4_000)
    const ledgerReads = () => reads.filter(path => path.endsWith('/progress.md')).length
    const before = ledgerReads()
    await clock.advance(10_000)
    expect(ledgerReads()).toBe(before)
  })

  test('picks up a ledger change within one poll tick', async ($, on) => {
    const files = runFiles(LEDGER) ?? {}
    const clock = world(on, { ...SIGNED_IN, files })
    signedIn(on, files)
    await $.tool.call({ tool: 'Skill', skill: 'dforge:subagent-driven-development' })
    await $.session.start(START)
    await clock.advance(4_000)
    files['/home/me/code/shop/.dforge/sdd/p/progress.md'] = {
      text: `${LEDGER}\nTask 2: complete (commits c..e, review clean) — done: x; verified: y; remaining: none; discovered: none; assumptions: none`,
      mtimeMs: 2_100_000,
    }
    await clock.advance(2_000)
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    expect(await ui.find({ type: 'Text', text: /^2\/3$/ })).toBeDefined()
  })
```

- [ ] **Step 2: Run the suite**

Run: `env -u CLAUDE_CONFIG_DIR timeout 300 /root/.local/bin/claude plugin test plugins/dforge`
Expected: 319 pass, 1 fail — `reads an unchanged ledger no more, however many ticks pass` fails (every tick reads the ledger again); `picks up a ledger change within one poll tick` passes.

- [ ] **Step 3: Add the gate's state**

In `plugins/dforge/hooks/cockpit/register.tsx`, replace:

```ts
  seen: { config: null as number | null, claude: '' },
}
```

with:

```ts
  seen: { config: null as number | null, claude: '' },
  // The ledger, its modification time and its plan's, as the run was last read; the plan file found then.
  runKey: '',
  runPlan: null as string | null,
}
```

- [ ] **Step 4: Skip an unchanged ledger, and write only a changed run**

Replace:

```ts
    if (newest === null || (!(await read($, isPlanSession)) && isOlder)) return clear()
    const ledger = parseLedger(String(await $.fs.read(newest.path)))
    let titles: { n: number; title: string }[] = []
    if (ledger.plan !== null) {
      const places: { root: string; docsDir: string }[] = []
      for (const dir of checkouts) places.push({ root: dir, docsDir: `${dir}/docs/dforge` })
      for (const candidate of planCandidates(ledger.plan, roots?.docs ?? null, places)) {
        try {
          titles = planTasks(String(await $.fs.read(candidate)))
          if (titles.length > 0) break
        } catch {
```

with:

```ts
    if (newest === null || (!(await read($, isPlanSession)) && isOlder)) return clear()
    const planStat = S.runPlan === null ? null : await $.fs.stat(S.runPlan).catch(() => null)
    const runKey = `${newest.path}:${newest.at}:${planStat?.mtimeMs ?? ''}`
    if (runKey === S.runKey && (await read($, run)) !== null) return
    const ledger = parseLedger(String(await $.fs.read(newest.path)))
    let titles: { n: number; title: string }[] = []
    let planPath: string | null = null
    if (ledger.plan !== null) {
      const places: { root: string; docsDir: string }[] = []
      for (const dir of checkouts) places.push({ root: dir, docsDir: `${dir}/docs/dforge` })
      for (const candidate of planCandidates(ledger.plan, roots?.docs ?? null, places)) {
        try {
          titles = planTasks(String(await $.fs.read(candidate)))
          if (titles.length > 0) {
            planPath = candidate
            break
          }
        } catch {
```

Then replace:

```ts
    // A run whose every task was done before this session started is history:
    // a new session starts with no Run card.
    if (isOlder && (summary.isFinished || (summary.total > 0 && summary.done === summary.total))) return clear()
    await update($, run, () => summary)
```

with:

```ts
    S.runKey = runKey
    S.runPlan = planPath
    // A run whose every task was done before this session started is history:
    // a new session starts with no Run card.
    if (isOlder && (summary.isFinished || (summary.total > 0 && summary.done === summary.total))) return clear()
    if (JSON.stringify(await read($, run)) === JSON.stringify(summary)) return
    await update($, run, () => summary)
```

Then replace:

```ts
    await readNotifier($)
    await readRun($)
```

with:

```ts
    await readNotifier($)
    S.runKey = ''
    await readRun($)
```

- [ ] **Step 5: Run the suite and verify it passes**

Run: `env -u CLAUDE_CONFIG_DIR timeout 300 /root/.local/bin/claude plugin test plugins/dforge`
Expected: 320 pass, 0 fail.

- [ ] **Step 6: Commit**

```bash
git add plugins/dforge/hooks/cockpit/register.tsx plugins/dforge/tests/cockpit.test.ts
git commit -m "perf(cockpit): read the ledger only when it changed"
```

### Task 6: Build the dense pane's rows

**Files:**
- Modify: `plugins/dforge/hooks/cockpit/lib.ts`
- Test: `plugins/dforge/tests/cockpit.test.ts`

**Interfaces:**
- Consumes: C2 (`commandExcerpt`, placed by Task 2 in `lib.ts`; `isTypedPrompt`, the anchor below).
- Produces: C6.

**Items:** 3

**Implementer:** dr-superpowers:impl-sonnet-medium
**Executor:** codex gpt-6.1-sol / medium
**Evaluation:** files 1 - spec 0 - coupling 2 - risk 0 = 3

- [ ] **Step 1: Write the failing tests**

In `plugins/dforge/tests/cockpit.test.ts`, replace:

```ts
  collapsedToggled,
  duration,
```

with:

```ts
  collapsedToggled,
  denseLine,
  duration,
```

Then replace:

```ts
import type { ActivityInput, Run } from '../hooks/cockpit/lib'
```

with:

```ts
import type { ActivityInput, DenseInput, Run } from '../hooks/cockpit/lib'
```

Then replace:

```ts
describe('shells and remote', () => {
```

with:

```ts
describe('dense rows', () => {
  const INPUT: DenseInput = {
    email: 'me@example.com',
    billing: 'subscription',
    remote: [{ text: '○ not connected' }],
    context: { tokens: 284_000, limit: 465_000 },
    turnsLeft: 8,
    limits: [
      { kind: 'five_hour', percent: 23 },
      { kind: 'seven_day', percent: 61 },
      { kind: 'spend_limit', percent: 5 },
    ],
    shells: [
      { command: 'npm test', startedAt: 100_000 },
      { command: 'node codex-companion.mjs review --background\nmore', startedAt: 160_000 },
    ],
    agents: ['impl-sonnet-medium', 'judge-opus'],
    run: { done: 3, total: 5, current: 'Task 4: Draw the card' },
    todos: null,
    repo: { branch: 'main', ahead: 2, behind: 0, changed: 3, untracked: 1 },
    refused: 0,
    now: 340_000,
  }

  test('draw one line per section', () => {
    expect(flat(denseLine('account', INPUT) ?? [])).toBe('acct me@example.com · subscription · Remote ○ not connected')
    expect(flat(denseLine('context', INPUT) ?? [])).toBe('ctx  ▰▰▰▰▰▰▱▱▱▱ 61% 284k/465k · ≈8 turns')
    expect(flat(denseLine('usage', INPUT) ?? [])).toBe('lim  5h ▰▱▱▱▱▱ 23% · 7d ▰▰▰▰▱▱ 61%')
    expect(flat(denseLine('shells', INPUT) ?? [])).toBe('$    2 shells · node codex-companion.mjs review --backg… · 3m')
    expect(flat(denseLine('agents', INPUT) ?? [])).toBe('agt  2 running · impl-sonnet-medium, judge-opus')
    expect(flat(denseLine('plan', INPUT) ?? [])).toBe('plan ▰▰▰▱▱ 3/5 · Task 4: Draw the card')
    expect(flat(denseLine('repo', INPUT) ?? [])).toBe('⎇    main ↑2 · ~3 changed · ?1')
    expect(denseLine('guard', INPUT)).toBeNull()
    expect(flat(denseLine('guard', { ...INPUT, refused: 2 }) ?? [])).toBe('grd  ✗ 2 refused')
  })

  test('leave out what has nothing to show, and say when nothing was read yet', () => {
    const empty: DenseInput = { ...INPUT, email: null, context: null, limits: [], shells: [], agents: [], run: null, todos: null, repo: null }
    expect(denseLine('account', empty)).toBeNull()
    expect(flat(denseLine('context', empty) ?? [])).toBe('ctx  no reading yet')
    expect(flat(denseLine('usage', empty) ?? [])).toBe('lim  no reading yet')
    for (const section of ['shells', 'agents', 'plan', 'repo', 'guard'] as const) expect(denseLine(section, empty)).toBeNull()
    expect(flat(denseLine('plan', { ...empty, todos: { done: 1, total: 4, current: 'Write the tests' } }) ?? [])).toBe('plan ▰▱▱▱ 1/4 · Write the tests')
  })
})

describe('shells and remote', () => {
```

- [ ] **Step 2: Run the suite and verify the new tests fail**

Run: `env -u CLAUDE_CONFIG_DIR timeout 300 /root/.local/bin/claude plugin test plugins/dforge`
Expected: the file fails to load or both new tests fail: `denseLine` is not exported yet.

- [ ] **Step 3: Write the row builders**

In `plugins/dforge/hooks/cockpit/lib.ts`, replace:

```ts
/** Whether a main turn's text is a prompt the person typed: a continuation starts with none, a task notification's wake-up with the notification. */
```

with:

```ts
/** What the dense pane's rows draw from. */
export type DenseInput = {
  email: string | null
  billing: string | null
  remote: Run[]
  /** The context against the handoff budget. */
  context: { tokens: number; limit: number } | null
  turnsLeft: number | null
  limits: readonly { kind: string; percent: number }[]
  shells: readonly { command: string; startedAt: number }[]
  /** The running subagents' seats, short names. */
  agents: readonly string[]
  run: { done: number; total: number; current: string | null } | null
  todos: { done: number; total: number; current: string | null } | null
  repo: RepoState | null
  refused: number
  now: number
}

/** A dense row's label, padded to five cells so the rows line up. */
function denseLabel(label: string, color?: string): Run {
  return { text: label.padEnd(5), color, dim: color === undefined }
}

/** One dense pane row for a section, or null when the section has nothing to show. */
export function denseLine(section: Section, input: DenseInput): Run[] | null {
  const sep: Run = { text: ' · ', dim: true }
  const join = (parts: Run[][]): Run[] => parts.filter(part => part.length > 0).flatMap((part, index) => (index === 0 ? part : [sep, ...part]))
  switch (section) {
    case 'account':
      if (input.email === null) return null
      return [denseLabel('acct'), ...join([[{ text: input.email, bold: true }], input.billing === null ? [] : [{ text: input.billing, dim: true }], [{ text: 'Remote ', dim: true }, ...input.remote]])]
    case 'context': {
      if (input.context === null) return [denseLabel('ctx'), { text: 'no reading yet', dim: true }]
      const { tokens, limit } = input.context
      const percent = (tokens / limit) * 100
      const color = rampColor(percent)
      const turns = input.turnsLeft
      return [
        denseLabel('ctx'),
        { text: bar(tokens / limit, 10), color },
        { text: ` ${Math.round(percent)}%`, color, bold: true },
        { text: ` ${kTokens(tokens)}/${kTokens(limit)}`, dim: true },
        ...(turns === null ? [] : [sep, { text: `≈${turns} ${turns === 1 ? 'turn' : 'turns'}`, color: turns <= 3 ? AMBER : undefined, dim: turns > 3 }]),
      ]
    }
    case 'usage': {
      const shown = input.limits.filter(limit => limit.kind === 'five_hour' || limit.kind === 'seven_day')
      if (shown.length === 0) return [denseLabel('lim'), { text: 'no reading yet', dim: true }]
      return [
        denseLabel('lim'),
        ...join(
          shown.map(limit => {
            const color = rampColor(limit.percent)
            return [{ text: `${limitLabel(limit.kind)} `, dim: true }, { text: bar(limit.percent / 100, 6), color }, { text: ` ${Math.round(limit.percent)}%`, color, bold: true }]
          }),
        ),
      ]
    }
    case 'shells': {
      if (input.shells.length === 0) return null
      const newest = input.shells.reduce((last, shell) => (shell.startedAt > last.startedAt ? shell : last))
      const count = input.shells.length
      return [
        denseLabel('$', 'yellow'),
        ...join([[{ text: `${count} ${count === 1 ? 'shell' : 'shells'}`, color: 'yellow' }], [{ text: commandExcerpt(newest.command, 40) }], [{ text: shellAge(input.now - newest.startedAt), dim: true }]]),
      ]
    }
    case 'agents':
      if (input.agents.length === 0) return null
      return [denseLabel('agt', 'cyan'), ...join([[{ text: `${input.agents.length} running`, color: 'cyan' }], [{ text: input.agents.join(', ') }]])]
    case 'plan': {
      const plan = input.run ?? input.todos
      if (plan === null || plan.total === 0) return null
      return [
        denseLabel('plan', 'magenta'),
        ...join([[{ text: bar(plan.done / plan.total, Math.min(plan.total, 10)), color: 'magenta' }, { text: ` ${plan.done}/${plan.total}`, bold: true }], plan.current === null ? [] : [{ text: plan.current }]]),
      ]
    }
    case 'repo': {
      if (input.repo === null) return null
      const r = input.repo
      const branch: Run[] = [{ text: r.branch, color: 'magenta', bold: true }, ...(r.ahead > 0 ? [{ text: ` ↑${r.ahead}`, color: 'magenta' }] : []), ...(r.behind > 0 ? [{ text: ` ↓${r.behind}`, color: 'magenta' }] : [])]
      return [denseLabel('⎇', 'magenta'), ...join([branch, r.changed > 0 ? [{ text: `~${r.changed} changed`, color: 'yellow' }] : [], r.untracked > 0 ? [{ text: `?${r.untracked}`, dim: true }] : []])]
    }
    case 'guard':
      return input.refused === 0 ? null : [denseLabel('grd'), { text: `✗ ${input.refused} refused`, color: 'red' }]
  }
}

/** Whether a main turn's text is a prompt the person typed: a continuation starts with none, a task notification's wake-up with the notification. */
```

- [ ] **Step 4: Run the suite and verify it passes**

Run: `env -u CLAUDE_CONFIG_DIR timeout 300 /root/.local/bin/claude plugin test plugins/dforge`
Expected: 322 pass, 0 fail.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/hooks/cockpit/lib.ts plugins/dforge/tests/cockpit.test.ts
git commit -m "feat(cockpit): build one-line rows for a dense pane"
```

### Task 7: Add the density setting and the dense pane

**Files:**
- Modify: `plugins/dforge/config/schema.mjs`
- Modify: `plugins/dforge/hooks/cockpit/register.tsx`
- Test: `plugins/dforge/tests/cockpit.test.ts`

**Interfaces:**
- Consumes: C3 (`work` in the pane's render scope), C6 (`denseLine`, `DenseInput`).
- Produces: C7.

**Items:** 3

**Implementer:** dr-superpowers:impl-sonnet-medium
**Executor:** codex gpt-6.1-sol / medium
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 1 = 3

- [ ] **Step 1: Write the failing tests**

In `plugins/dforge/tests/cockpit.test.ts`, replace:

```ts
describe('/cockpit', () => {
```

with:

```ts
describe('dense pane', () => {
  const SHELL = { result: { stdout: '', stderr: '', interrupted: false, backgroundTaskId: 'b7k2' }, text: 'Running in the background' }

  test('draws one line per shown section, and Detailed switches back', async ($, on) => {
    const written: Record<string, string> = {}
    world(on, { ...SIGNED_IN, written, tools: { Bash: () => SHELL } })
    signedIn(on, configured({ density: 'dense', sections: 'context,usage,shells,agents,repo' }))
    await $.session.start(START)
    await $.tool.call({ tool: 'Bash', command: 'npm run dev', run_in_background: true } as never)
    await $.session.measure(MEASURE)
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    expect(await ui.find({ type: 'Button', text: '▾ Context' })).toBeUndefined()
    expect((await ui.find({ key: 'dense-context' }))?.text).toMatch(/^ctx  ▰+▱* 61% 284k\/465k/)
    expect((await ui.find({ key: 'dense-usage' }))?.text).toMatch(/^lim  5h ▰+▱* 23% · 7d ▰+▱* 61%$/)
    expect((await ui.find({ key: 'dense-shells' }))?.text).toBe('$    1 shell · npm run dev · 0s')
    expect(await ui.find({ key: 'dense-agents' })).toBeUndefined()
    expect((await ui.find({ key: 'dense-repo' }))?.text).toBe('⎇    feat/pane ↑2 ↓1 · ~1 changed · ?1')
    expect(await ui.find({ key: 'pane-compact' })).toBeDefined()
    await ui.press({ key: 'pane-density' })
    expect(JSON.parse(written[CONFIG] ?? '{}').density).toBeUndefined()
    expect(await ui.find({ type: 'Button', text: '▾ Context' })).toBeDefined()
  })

  test('Dense saves the setting', async ($, on) => {
    const written: Record<string, string> = {}
    world(on, { tokens: 284_000, written, config: {} })
    await $.session.start(START)
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    await ui.press({ key: 'pane-density' })
    expect(JSON.parse(written[CONFIG] ?? '{}').density).toBe('dense')
    expect(await ui.find({ key: 'dense-context' })).toBeDefined()
  })

  test('draws the same rows as text on the desktop', async ($, on) => {
    world(on, SIGNED_IN)
    signedIn(on, configured({ density: 'dense' }))
    await $.session.start(START)
    await $.session.measure(MEASURE)
    const ui = await $.ui.mount({ ...PANE, surface: 'desktop' })
    expect(await ui.find({ key: 'dense-context' })).toBeDefined()
    expect(await ui.findAll({ type: 'Svg' })).toEqual([])
    expect(await ui.find({ key: 'pane-minimize' })).toBeDefined()
  })
})

describe('/cockpit', () => {
```

- [ ] **Step 2: Run the suite and verify the new tests fail**

Run: `env -u CLAUDE_CONFIG_DIR timeout 300 /root/.local/bin/claude plugin test plugins/dforge`
Expected: the three `dense pane` tests fail (no `dense-context` row, no `pane-density` button).

- [ ] **Step 3: Add the setting to the schema**

In `plugins/dforge/config/schema.mjs`, replace:

```js
  sections: {
```

with:

```js
  density: {
    type: 'enum', values: ['detailed', 'dense'], default: 'detailed', group: 'Cockpit', target: 'dforge',
    label: 'Density', title: 'Pane density',
    description: 'detailed: cards, charts and lists. dense: one line per section. The pane\'s Dense and Detailed buttons set it.',
  },
  sections: {
```

- [ ] **Step 4: Read the setting live**

In `plugins/dforge/hooks/cockpit/register.tsx`, replace:

```ts
  collapsedToggled,
  duration,
```

with:

```ts
  collapsedToggled,
  denseLine,
  duration,
```

Then replace:

```ts
  shellAge,
  runsWidth,
```

with:

```ts
  shellAge,
  runsCut,
  runsWidth,
```

Then replace:

```ts
import type { AgentGroupKey, BandInput, Run, Section, TrackPart } from './lib'
```

with:

```ts
import type { AgentGroupKey, BandInput, DenseInput, Run, Section, TrackPart } from './lib'
```

Then replace:

```ts
  layout: string
  sections: string
```

with:

```ts
  layout: string
  density: string
  sections: string
```

Then replace:

```ts
type Live = Omit<Options, 'layout'> & {
  layout: 'auto' | 'full' | 'compact'
```

with:

```ts
type Live = Omit<Options, 'layout' | 'density'> & {
  layout: 'auto' | 'full' | 'compact'
  density: 'detailed' | 'dense'
```

Then replace:

```ts
    layout: layoutSetting = 'auto',
```

with:

```ts
    layout: layoutSetting = 'auto',
    density: densitySetting = 'detailed',
```

Then replace:

```ts
    layout,
    sections,
```

with:

```ts
    layout,
    density: densitySetting === 'dense' ? 'dense' : 'detailed',
    sections,
```

- [ ] **Step 5: Add the toggle and draw the action buttons compact when dense**

Replace:

```ts
    const autoNow = await read($, autoRun)
    const actions = (
```

with:

```ts
    const autoNow = await read($, autoRun)
    const isDense = o.density === 'dense'
    const actions = (
```

Then replace:

```ts
        {autoNow?.active && button('pane-stop-auto', 'Stop auto', () => void stopAutoRun($))}
        {canHandOff && !autoNow?.active && button('pane-handoff', 'Hand off', () => $.prompt.submit({ text: HANDOFF_PROMPT, asUser: true }), { hotkey: 'h', isMain: isNearHandoff })}
        {button('pane-compact', 'Compact', () => $.session.compact(), { hotkey: 'c' })}
        {button('pane-settings', 'Settings', () => showSettings($), { hotkey: 's' })}
        {canMinimize && !isDesktop && !isCompact && button('pane-minimize', 'Minimize', minimize, { hotkey: 'm' })}
```

with:

```ts
        {autoNow?.active && button('pane-stop-auto', 'Stop auto', () => void stopAutoRun($), { isCompact: isDense })}
        {canHandOff && !autoNow?.active && button('pane-handoff', 'Hand off', () => $.prompt.submit({ text: HANDOFF_PROMPT, asUser: true }), { hotkey: 'h', isMain: isNearHandoff, isCompact: isDense })}
        {button('pane-compact', 'Compact', () => $.session.compact(), { hotkey: 'c', isCompact: isDense })}
        {button('pane-density', isDense ? 'Detailed' : 'Dense', () => setOption($, 'density', isDense ? 'detailed' : 'dense'), { hotkey: 'd', isCompact: isDense })}
        {button('pane-settings', 'Settings', () => showSettings($), { hotkey: 's', isCompact: isDense })}
        {canMinimize && !isDesktop && !isCompact && button('pane-minimize', 'Minimize', minimize, { hotkey: 'm', isCompact: isDense })}
```

- [ ] **Step 6: Draw the dense pane**

Replace:

```ts
      return drawBand($, e, async () => {
        if ((await setOption($, 'layout', isInline ? 'full' : 'auto')) && isInline) await $.ui.open(paneFor('full'))
      })
    }
```

with:

```ts
      return drawBand($, e, async () => {
        if ((await setOption($, 'layout', isInline ? 'full' : 'auto')) && isInline) await $.ui.open(paneFor('full'))
      })
    }

    if (isDense) {
      const inFlight = summary?.tasks.find(task => task.state === 'assigned') ?? null
      const dense: DenseInput = {
        email: who?.email ?? null,
        billing,
        remote: remoteRuns(remoteNow.clients, remoteNow.setting),
        context: head === null ? null : { tokens: head.tokens, limit: head.limit },
        turnsLeft: head === null ? null : turnsToBudget(await read($, turnTokens), head.limit),
        limits,
        shells: background,
        agents: running.map(one => shortSeat(one.seat)),
        run: summary === null || summary.total === 0 ? null : { done: summary.done, total: summary.total, current: inFlight === null ? null : `Task ${inFlight.n}${inFlight.title === '' ? '' : `: ${inFlight.title}`}` },
        todos: items.length === 0 ? null : { done: doneCount, total: items.length, current: items.find(item => item.status === 'in_progress')?.text ?? null },
        repo: git,
        refused: refused.length,
        now,
      }
      const rows = o.shown.flatMap(name => {
        const runs = denseLine(name, dense)
        return runs === null ? [] : [{ key: `dense-${name}`, runs: runsCut(runs, room) }]
      })
      return (
        <Box flexDirection="column">
          {resumeCard}
          <Box key="dense-now" flexDirection="row" alignItems="center" columnGap={1}>
            <Box key="dense-now-text" flexGrow={1} flexShrink={1}>
              <Text key="now" wrap="truncate-end">
                {drawRuns('now', nowLine(actNow, now, work))}
              </Text>
            </Box>
            {isDesktop && canMinimize && button('pane-minimize', 'Minimize', minimize, { hotkey: 'm' })}
          </Box>
          {rows.map(row => (
            <Box key={row.key}>
              <Text wrap="truncate-end">{drawRuns(row.key, row.runs)}</Text>
            </Box>
          ))}
          {actions}
        </Box>
      )
    }
```

- [ ] **Step 7: Run the suite and verify it passes**

Run: `env -u CLAUDE_CONFIG_DIR timeout 300 /root/.local/bin/claude plugin test plugins/dforge`
Expected: 325 pass, 0 fail.

- [ ] **Step 8: Commit**

```bash
git add plugins/dforge/config/schema.mjs plugins/dforge/hooks/cockpit/register.tsx plugins/dforge/tests/cockpit.test.ts
git commit -m "feat(cockpit): add a dense pane density"
```

### Task 8: Add the band helpers for the box below the prompt

**Files:**
- Modify: `plugins/dforge/hooks/cockpit/lib.ts`
- Test: `plugins/dforge/tests/cockpit.test.ts`

**Interfaces:**
- Consumes: nothing.
- Produces: C8.

**Items:** 4

**Implementer:** dr-superpowers:impl-sonnet-medium
**Executor:** codex gpt-6.1-sol / medium
**Evaluation:** files 1 - spec 0 - coupling 2 - risk 0 = 3

- [ ] **Step 1: Write the failing tests**

In `plugins/dforge/tests/cockpit.test.ts`, replace:

```ts
  billingLabel,
  budgetFor,
```

with:

```ts
  billingLabel,
  bottomRule,
  budgetFor,
```

Then replace:

```ts
  modelName,
  nowLine,
```

with:

```ts
  modelName,
  MODE_LABEL_RESERVE,
  nowLine,
```

Then replace:

```ts
    expect(meters).toContain('>CONTEXT</text>')
    expect(meters).toContain('61%')
  })
})
```

with:

```ts
    expect(meters).toContain('>CONTEXT</text>')
    expect(meters).toContain('61%')
  })

  test('leads line 2 with ◐ while background work runs', () => {
    expect(text(bandLines({ ...input, isBackground: true }, 0)[1])).toBe('◐ ● 1 agent  ·  $ 2 shells · longest 12m  ·  ~/code/shop/web/src ⎇ feat/a-rather-long-branch-name* ↑2 ↓1 ~1 ?2')
    expect(text(bandLines({ ...input, isBackground: false }, 0)[1])).toBe('● 1 agent  ·  $ 2 shells · longest 12m  ·  ~/code/shop/web/src ⎇ feat/a-rather-long-branch-name* ↑2 ↓1 ~1 ?2')
  })

  test('sets a label into the bottom rule, cut to fit', () => {
    const whole = (rule: { lead: string; label: string; tail: string }) => rule.lead + rule.label + rule.tail
    expect(whole(bottomRule('? for shortcuts', 30))).toBe(`╰─ ? for shortcuts ${'─'.repeat(10)}╯`)
    expect(whole(bottomRule('esc to interrupt and more', 20))).toBe('╰─ esc to interr… ─╯')
    expect(whole(bottomRule(null, 10))).toBe('╰────────╯')
    expect(whole(bottomRule('  ', 10))).toBe('╰────────╯')
    for (const width of [10, 20, 30]) expect([...whole(bottomRule('esc to interrupt and more', width))].length).toBe(width)
    expect(MODE_LABEL_RESERVE).toBe(29)
  })
})
```

- [ ] **Step 2: Run the suite and verify the new tests fail**

Run: `env -u CLAUDE_CONFIG_DIR timeout 300 /root/.local/bin/claude plugin test plugins/dforge`
Expected: the file fails to load or both new tests fail: `bottomRule` and `MODE_LABEL_RESERVE` are not exported yet.

- [ ] **Step 3: Lead line 2 with the background mark**

In `plugins/dforge/hooks/cockpit/lib.ts`, replace:

```ts
  /** Background shells running, and how long the oldest has run. */
  shells: { count: number; longest: number }
  now: number
}
```

with:

```ts
  /** Background shells running, and how long the oldest has run. */
  shells: { count: number; longest: number }
  now: number
  /** True while the main conversation's background work runs: line 2 leads with ◐. */
  isBackground?: boolean
}
```

Then replace:

```ts
  return [join([ctx, ...limits]), join([agents, shells, where])]
}
```

with:

```ts
  const two = join([agents, shells, where])
  return [join([ctx, ...limits]), input.isBackground === true ? [{ text: '◐ ', color: AMBER_RUN, bold: true }, ...two] : two]
}
```

- [ ] **Step 4: Add the reserve and the bottom rule**

Replace:

```ts
/** The cells a row of runs takes. */
```

with:

```ts
/**
 * Cells the box below the prompt leaves for Claude Code's permission-mode
 * label on its row: the widest, `⏵⏵ bypass permissions on · ` after a 2-cell
 * margin, measured on Claude Code 2.1.304. The live mode cannot be read at
 * draw time, so every mode gets the widest.
 */
export const MODE_LABEL_RESERVE = 29

/** The band's bottom rule, `width` cells wide, with `label` set into it after `╰─ ` and cut to fit; no label draws a plain rule. */
export function bottomRule(label: string | null, width: number): { lead: string; label: string; tail: string } {
  const text = (label ?? '').trim()
  const room = width - 6
  if (text === '' || room < 4) return { lead: `╰${'─'.repeat(Math.max(0, width - 2))}╯`, label: '', tail: '' }
  const chars = [...text]
  const shown = chars.length <= room ? text : `${chars.slice(0, room - 1).join('')}…`
  return { lead: '╰─ ', label: shown, tail: ` ${'─'.repeat(Math.max(1, width - 5 - [...shown].length))}╯` }
}

/** The cells a row of runs takes. */
```

- [ ] **Step 5: Run the suite and verify it passes**

Run: `env -u CLAUDE_CONFIG_DIR timeout 300 /root/.local/bin/claude plugin test plugins/dforge`
Expected: 327 pass, 0 fail.

- [ ] **Step 6: Commit**

```bash
git add plugins/dforge/hooks/cockpit/lib.ts plugins/dforge/tests/cockpit.test.ts
git commit -m "feat(cockpit): add the helpers for the prompt box"
```

### Task 9: Draw the minimized cockpit below the prompt

**Files:**
- Modify: `plugins/dforge/hooks/cockpit/register.tsx`
- Test: `plugins/dforge/tests/cockpit.test.ts`

**Interfaces:**
- Consumes: C3 (the `background` activity), C7 (the `drawBand` call in the pane, kept as Task 7 left it), C8 (`MODE_LABEL_RESERVE`, `bottomRule`, `BandInput.isBackground`).
- Produces: C9.

**Items:** 4

**Implementer:** dr-superpowers:impl-sonnet-medium
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 2 = 4

- [ ] **Step 1: Add the test helper and move the minimized-band tests below the prompt**

In `plugins/dforge/tests/cockpit.test.ts`, replace:

```ts
const PORCELAIN = '# branch.oid abc1234def\n# branch.head feat/pane\n# branch.ab +2 -1\n1 .M N... 100644 100644 100644 a b src/a.ts\n? notes.md\n'
```

with:

```ts
// Where a minimized cockpit draws: below the prompt on the terminal, above it on the desktop.
const minimized = (surface: (typeof SURFACES)[number], viewport = { columns: 120, rows: 40, isFullscreen: false }) =>
  surface === 'terminal' ? { ...HINT, surface, viewport } : { ...BAND, surface, viewport }
const PORCELAIN = '# branch.oid abc1234def\n# branch.head feat/pane\n# branch.ab +2 -1\n1 .M N... 100644 100644 100644 a b src/a.ts\n? notes.md\n'
```

Then replace:

```ts
    test(`draws the band above the prompt when minimized on ${surface}`, async ($, on) => {
      world(on, SIGNED_IN)
      signedIn(on, configured({ layout: 'compact' }))
      await $.session.start(START)
      await $.tool.call({ tool: 'Bash', command: 'ls' })
      await $.session.measure(MEASURE)
      const band = await $.ui.mount({ ...BAND, surface })
```

with:

```ts
    test(`draws the minimized band on ${surface}`, async ($, on) => {
      world(on, SIGNED_IN)
      signedIn(on, configured({ layout: 'compact' }))
      await $.session.start(START)
      await $.tool.call({ tool: 'Bash', command: 'ls' })
      await $.session.measure(MEASURE)
      const band = await $.ui.mount(minimized(surface))
```

Then replace:

```ts
    test(`Expand on the band above the prompt opens the pane on ${surface}`, async ($, on) => {
```

with:

```ts
    test(`Expand on the minimized band opens the pane on ${surface}`, async ($, on) => {
```

Then replace:

```ts
      const docking = await $.ui.mount({ ...BAND, surface, viewport: { columns: 160, rows: 50, isFullscreen: true } })
```

with:

```ts
      const docking = await $.ui.mount(minimized(surface, { columns: 160, rows: 50, isFullscreen: true }))
```

Then replace:

```ts
      const main = await $.ui.mount({ ...BAND, surface, viewport: { columns: 100, rows: 50, isFullscreen: false } })
```

with:

```ts
      const main = await $.ui.mount(minimized(surface, { columns: 100, rows: 50, isFullscreen: false }))
```

Then replace:

```ts
    const band = await $.ui.mount({ ...BAND, props: { ...BAND.props, hasSurvey: true }, surface: 'terminal' })
    expect(await band.find({ key: 'band-expand' })).toBeUndefined()
```

with:

```ts
    const band = await $.ui.mount({ ...BAND, props: { ...BAND.props, hasSurvey: true }, surface: 'desktop' })
    expect(await band.find({ key: 'band-expand' })).toBeUndefined()
```

Then replace:

```ts
    const band = await $.ui.mount({ ...BAND, surface: 'terminal' })
    expect(await band.find({ type: 'Text', text: /⎇ feat\/pane\*/ })).toBeDefined()
```

with:

```ts
    const band = await $.ui.mount(minimized('terminal'))
    expect(await band.find({ type: 'Text', text: /⎇ feat\/pane\*/ })).toBeDefined()
```

Then replace:

```ts
      await start($, on, RESUMABLE, COMPACT)
      const band = await $.ui.mount({ ...BAND, surface })
      expect(await band.find({ key: 'band-resume' })).toBeDefined()
      expect(await band.find({ key: 'band-expand' })).toBeDefined()
```

with:

```ts
      await start($, on, RESUMABLE, COMPACT)
      const band = await $.ui.mount({ ...BAND, surface })
      expect(await band.find({ key: 'band-resume' })).toBeDefined()
      const site = await $.ui.mount(minimized(surface))
      expect(await site.find({ key: 'band-expand' })).toBeDefined()
```

- [ ] **Step 2: Write the failing tests for the box**

In `plugins/dforge/tests/cockpit.test.ts`, replace:

```ts
    expect(await ui.find({ type: 'Text', text: /✗ 1 refused/ })).toBeDefined()
  })
```

with:

```ts
    expect(await ui.find({ type: 'Text', text: /✗ 1 refused/ })).toBeDefined()
  })

  test('draws below the prompt on the terminal, the hint set into its bottom rule', async ($, on) => {
    world(on, SIGNED_IN)
    signedIn(on, configured({ layout: 'compact' }))
    await $.session.start(START)
    await $.tool.call({ tool: 'Bash', command: 'ls' })
    await $.session.measure(MEASURE)
    const above = await $.ui.mount({ ...BAND, surface: 'terminal' })
    expect(await above.find({ key: 'band-expand' })).toBeUndefined()
    await above.unmount()
    const box = await $.ui.mount(minimized('terminal'))
    expect(await box.find({ key: 'band-expand' })).toBeDefined()
    expect(await box.find({ type: 'Text', text: /^╭─ me@example\.com/ })).toBeDefined()
    expect(await box.find({ type: 'Text', text: /^╰─ \? for shortcuts ─+╯$/ })).toBeDefined()
    const rows = (await box.findAll({ type: 'Text' })).map(one => one.text).filter(text => /^[│╰].*[│╯]$/.test(text))
    expect(rows.length).toBeGreaterThan(2)
    for (const row of rows) expect([...row].length).toBe(120 - 2 - MODE_LABEL_RESERVE)
  })

  test('takes unframed lines below the prompt when no width is reported', async ($, on) => {
    world(on, SIGNED_IN)
    signedIn(on, configured({ layout: 'compact' }))
    await $.session.start(START)
    await $.tool.call({ tool: 'Bash', command: 'ls' })
    const box = await $.ui.mount({ ...HINT, surface: 'terminal' })
    expect(await box.find({ type: 'Text', text: /╭/ })).toBeUndefined()
    expect(await box.find({ type: 'Text', text: 'me@example.com' })).toBeDefined()
    expect(await box.find({ type: 'Text', text: '? for shortcuts' })).toBeDefined()
  })

  test('leads its second line with ◐ while background work runs', async ($, on) => {
    const shell = { result: { stdout: '', stderr: '', interrupted: false, backgroundTaskId: 'b7k2' }, text: 'Running in the background' }
    world(on, { ...SIGNED_IN, tools: { Bash: () => shell } })
    signedIn(on, configured({ layout: 'compact' }))
    await $.session.start(START)
    await $.turn.start({ text: 'go', turnId: 't1' })
    await $.tool.call({ tool: 'Bash', command: 'npm run dev', run_in_background: true } as never)
    await $.turn.complete({ answer: 'ok', durationMs: 1_000, isAborted: false, turnId: 't1', reason: 'answer' })
    const box = await $.ui.mount(minimized('terminal'))
    expect(await box.find({ type: 'Text', text: /^│ ◐ \$ 1 shell/ })).toBeDefined()
  })
```

- [ ] **Step 3: Run the suite and verify the new tests fail**

Run: `env -u CLAUDE_CONFIG_DIR timeout 300 /root/.local/bin/claude plugin test plugins/dforge`
Expected: the terminal cases of the moved tests and the three new box tests fail (nothing draws in `PromptHint`); the desktop cases pass.

- [ ] **Step 4: Import the helpers**

In `plugins/dforge/hooks/cockpit/register.tsx`, replace:

```ts
  billingLabel,
  budgetFor,
```

with:

```ts
  billingLabel,
  bottomRule,
  budgetFor,
```

Then replace:

```ts
  modelName,
  nowLine,
```

with:

```ts
  modelName,
  MODE_LABEL_RESERVE,
  nowLine,
```

- [ ] **Step 5: Let the band take its width, the background mark and a hint**

Replace:

```ts
/** The minimized cockpit's band, drawn in the pane or above the prompt. */
async function drawBand($: EngineInterface, e: RenderInput<'Pane' | 'AbovePrompt'>, onExpand: () => unknown) {
  const table = $.ui.resolve(e)
  const { Box, Button, Text } = table
  const Svg = e.surface === 'desktop' && 'Svg' in table ? table.Svg : undefined
  const isDesktop = Svg !== undefined
  const now = await $.clock.now()
  const room = e.props.bodyColumns
```

with:

```ts
/**
 * The minimized cockpit's band, `room` cells wide: drawn in the pane, above
 * the prompt, or below it with the engine's `hint` set into its bottom rule.
 */
async function drawBand($: EngineInterface, e: RenderInput<'Pane' | 'AbovePrompt' | 'PromptHint'>, onExpand: () => unknown, room: number, hint: string | null = null) {
  const table = $.ui.resolve(e)
  const { Box, Button, Text } = table
  const Svg = e.surface === 'desktop' && 'Svg' in table ? table.Svg : undefined
  const isDesktop = Svg !== undefined
  const now = await $.clock.now()
```

Then replace:

```ts
    now,
  }
  const blocked = summary?.tasks.filter(task => task.state === 'blocked') ?? []
```

with:

```ts
    now,
    isBackground: (await read($, activity)).kind === 'background',
  }
  const blocked = summary?.tasks.filter(task => task.state === 'blocked') ?? []
```

Then replace:

```ts
  const lines = [one, two].filter(line => line.length > 0)
```

with:

```ts
  const lines = [one, two].filter(line => line.length > 0)
  const bottom = bottomRule(hint, room)
```

Then replace:

```ts
      {isFramed && (
        <Text key="frame-bottom" color={tint} wrap="truncate-end">
          {'╰' + '─'.repeat(Math.max(0, room - 2)) + '╯'}
        </Text>
      )}
```

with:

```ts
      {isFramed && (
        <Text key="frame-bottom" color={tint} wrap="truncate-end">
          {bottom.lead}
          <Text dimColor>{bottom.label}</Text>
          {bottom.tail}
        </Text>
      )}
      {!isFramed && hint !== null && hint.trim() !== '' && (
        <Text key="band-hint" dimColor wrap="truncate-end">
          {hint}
        </Text>
      )}
```

- [ ] **Step 6: Pass the width from the pane and the band above the prompt**

Replace:

```ts
      return drawBand($, e, async () => {
        if ((await setOption($, 'layout', isInline ? 'full' : 'auto')) && isInline) await $.ui.open(paneFor('full'))
      })
```

with:

```ts
      return drawBand(
        $,
        e,
        async () => {
          if ((await setOption($, 'layout', isInline ? 'full' : 'auto')) && isInline) await $.ui.open(paneFor('full'))
        },
        e.props.bodyColumns,
      )
```

Then replace:

```ts
  // Minimized, the band sits above the prompt in place of the pane. A handoff
  // to resume rides above it, or alone while the pane is open.
  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    if (e.props.hasSurvey) return next(e)
    const o = await live($)
    const offer = await offerNow($, await $.clock.now())
    const band = o.isMinimized ? await drawBand($, e, () => expand($, e.viewport?.isFullscreen === true)) : null
```

with:

```ts
  // Minimized off the terminal, the band sits above the prompt in place of the
  // pane. A handoff to resume rides above it, or alone while the pane is open.
  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    if (e.props.hasSurvey) return next(e)
    const o = await live($)
    const offer = await offerNow($, await $.clock.now())
    const band = o.isMinimized && e.surface !== 'terminal' ? await drawBand($, e, () => expand($, e.viewport?.isFullscreen === true), e.props.bodyColumns) : null
```

- [ ] **Step 7: Draw the box below the prompt**

Replace:

```ts
      <Box flexDirection="column">
        {await drawResumeBand($, e, offer)}
        {band}
      </Box>
    )
  })
}
```

with:

```ts
      <Box flexDirection="column">
        {await drawResumeBand($, e, offer)}
        {band}
      </Box>
    )
  })

  // Minimized on the terminal, the band is a box below the prompt in the hint
  // line's place, after the permission-mode label. It draws while a turn runs:
  // the Now state is what it is there for.
  on('ui.render', { component: 'PromptHint' }, async ($, e, next) => {
    if (e.surface !== 'terminal' || !(await live($)).isMinimized) return next(e)
    const room = e.viewport === undefined ? FRAME_MIN_COLUMNS - 1 : Math.max(10, e.viewport.columns - 2 - MODE_LABEL_RESERVE)
    return drawBand($, e, () => expand($, e.viewport?.isFullscreen === true), room, e.props.hint)
  })
}
```

- [ ] **Step 8: Run the suite and verify it passes**

Run: `env -u CLAUDE_CONFIG_DIR timeout 300 /root/.local/bin/claude plugin test plugins/dforge`
Expected: 330 pass, 0 fail.

- [ ] **Step 9: Smoke-check the box in a nested Claude Code**

The probe needs no model turn and touches none of the owner's settings. Write `/tmp/cockpit-box-smoke/run.sh`, with the worktree's absolute path in place of `<WORKTREE>`:

```bash
#!/bin/bash
S=/tmp/cockpit-box-smoke
mkdir -p "$S/home/.dforge" "$S/cfg" "$S/work"
printf '{ "layout": "compact" }\n' > "$S/home/.dforge/config.json"
KEY=sk-ant-api03-smokesmokesmokesmokesmoke0123456789abcdef
printf '{ "hasCompletedOnboarding": true, "customApiKeyResponses": { "approved": ["%s"], "rejected": [] }, "projects": { "%s/work": { "hasTrustDialogAccepted": true } } }\n' "${KEY: -20}" "$S" > "$S/cfg/.claude.json"
cd "$S/work"
exec env -i HOME="$S/home" TERM=xterm-256color PATH=/root/.nvm/versions/node/v24.18.0/bin:/usr/local/bin:/usr/bin:/bin CLAUDE_CONFIG_DIR="$S/cfg" IS_SANDBOX=1 ANTHROPIC_API_KEY="$KEY" /root/.local/bin/claude --setting-sources project,local --plugin-dir <WORKTREE>/plugins/dforge "$@"
```

Write `/tmp/cockpit-box-smoke/smoke.sh`, which launches one mode at one width, accepts the bypass-permissions prompt when it shows, saves the screen and closes the session:

```bash
#!/bin/bash
S=/tmp/cockpit-box-smoke
tmux new-session -d -s cockpit-smoke -x "$2" -y 30 "bash $S/run.sh --permission-mode $1"
sleep 8
if tmux capture-pane -p -t cockpit-smoke | grep -q "Yes, I accept"; then
  tmux send-keys -t cockpit-smoke Down Enter
  sleep 6
fi
tmux capture-pane -p -t cockpit-smoke > "$S/capture-$1-$2.txt"
tmux kill-session -t cockpit-smoke
```

Run every mode at both widths (twelve runs, about two minutes), then print the lines around the box from each capture:

```bash
for mode in default acceptEdits plan bypassPermissions dontAsk auto; do for width in 80 120; do timeout 60 bash /tmp/cockpit-box-smoke/smoke.sh "$mode" "$width"; done; done
grep -H -E "╭|│|╰" /tmp/cockpit-box-smoke/capture-*.txt
```

Expected, in every capture: below the prompt the mode label (`⏸ manual mode on ·`, `⏵⏵ bypass permissions on ·`, …) stays on one row with the box's `╭─` after it; the top rule carries `Expand`; two reading lines follow; the bottom rule reads `╰─ ` then the engine's hint text (for example `? for shortcuts` or `← for agents`) — the evidence that `PromptHint` passes its hint as `e.props.hint`; and the box's right edge `╮`/`│`/`╯` is on screen. Record each capture's verdict in the task report, and say that the Expand click and `turn.start`'s text on a notification wake-up were not checked (no model turn, no mouse). A box that wraps the label, loses its right edge, or has an empty bottom rule is a stop: report BLOCKED with the capture. Afterwards `tmux ls` must not list `cockpit-smoke`; remove `/tmp/cockpit-box-smoke`.

- [ ] **Step 10: Commit**

```bash
git add plugins/dforge/hooks/cockpit/register.tsx plugins/dforge/tests/cockpit.test.ts
git commit -m "feat(cockpit): draw the minimized box below the prompt"
```

### Task 10: Document the live state, density and the box

**Files:**
- Modify: `plugins/dforge/README.md`
- Modify: `plugins/dforge/config/schema.mjs`

**Interfaces:**
- Consumes: C3, C4, C7, C9 (the behaviour it documents).
- Produces: nothing.

**Items:** 1, 2, 3, 4

**Implementer:** dr-superpowers:impl-sonnet-low
**Evaluation:** files 1 - spec 0 - coupling 0 - risk 0 = 1

- [ ] **Step 1: Describe the minimized layout in the schema**

In `plugins/dforge/config/schema.mjs`, replace:

```js
    description: 'auto: the full layout docked beside the transcript, the band when the pane sits above the prompt. full: always the full layout. compact: minimized, the band above the prompt; Minimize sets it and Expand sets auto, or full where the pane does not dock.',
```

with:

```js
    description: 'auto: the full layout docked beside the transcript, the band when the pane sits above the prompt. full: always the full layout. compact: minimized, a box below the prompt on the terminal (above it on the desktop); Minimize sets it and Expand sets auto, or full where the pane does not dock.',
```

- [ ] **Step 2: Document the Now row's background state**

In `plugins/dforge/README.md`, replace:

```markdown
  idle with the last turn's length; the last turn failed; or Esc
  interrupted it, with the background shells and agents still running after
  it (Esc stops the turn, not them). It adds
  `Discord ✓` once a notification went out for what it shows.
```

with:

```markdown
  idle with the last turn's length; the last turn failed; or Esc
  interrupted it, with the background shells and agents still running after
  it (Esc stops the turn, not them). When a turn ends with its own background
  shells or subagents still running (a Codex review, a test run), it reads
  `◐ background` with the shells, the newest command and the subagents, and the
  Done notification waits: one Done goes out after the turn their notification
  wakes ends, timed from the first turn. A prompt you type starts the count
  again, a subagent's own shells hold nothing, and after 30 minutes the Done
  goes out anyway. It adds `Discord ✓` once a notification went out for what
  it shows.
```

- [ ] **Step 3: Document the dense pane and live settings**

Replace:

```markdown
**Minimize** (`m`) closes the pane and draws the cockpit as a band directly
above the prompt, across the transcript's width. **Expand** on the band's top
rule opens the pane again, and so does `/cockpit`. Each saves the `layout`
setting, so the next session opens the same way: a minimized cockpit starts
with the band and no pane. `/cockpit settings` still opens the settings, and
**Back** closes them again. Minimize is offered in the terminal and the desktop
app, the two that draw above the prompt; elsewhere a minimized cockpit shows
nothing until `/cockpit` opens it. The band is also what a pane that is not
docked draws (`layout` `auto`, the default). Its frame takes the account's
```

with:

```markdown
**Dense** (`d`) turns the pane into one line per section, in the `sections`
order: the Now row, then `ctx` with a bar, the share of the handoff budget and
the turns left, `lim` with the 5-hour and 7-day limits, the background shells
with the newest command, the running subagents, the plan or run's progress
and its task in flight, the branch and changes, and refusals. A section with
nothing to show is left out; the buttons shrink to one line, and
**Detailed** (`d`) brings the cards back. Each press saves the `density`
setting. In the desktop app the dense rows are text, without the gauges.

**Live readings.** While the pane is up or the cockpit minimized, it checks
`~/.dforge/config.json` and the dforge keys in Claude's settings every two
seconds and puts a change in force, so an edit from `dforge-config`, by hand or
in another session shows without a restart; a file that stops being a JSON
object keeps the settings in force and says so in the settings view. The run
ledger is re-read when it changes, and the git state and the `/context`
breakdown every ten seconds. Nothing is read while the cockpit is hidden. The
account, Remote Control's `/config` row and the usage limits keep their own
timing.

**Minimize** (`m`) closes the pane. In the terminal the cockpit then draws as a
framed box directly below the prompt, in place of the hint line and after the
permission-mode label, with Claude Code's own hint (`esc to interrupt`, `? for
shortcuts`) set into its bottom rule; it leaves room for the widest mode label,
so beside a short one it ends before the right edge. In the desktop app it
draws as a band directly above the prompt, across the transcript's width.
**Expand** on the top rule opens the pane again, and so does `/cockpit`. Each
saves the `layout` setting, so the next session opens the same way: a
minimized cockpit starts with the box or band and no pane. `/cockpit settings`
still opens the settings, and **Back** closes them again. Minimize is offered
in the terminal and the desktop app; elsewhere a minimized cockpit shows
nothing until `/cockpit` opens it. The band is also what a pane that is not
docked draws (`layout` `auto`, the default). Its frame takes the account's
```

Then replace:

```markdown
counts and changes. A blocked run task or a refused command adds a red line.
```

with:

```markdown
counts and changes; it leads with `◐` while the background state shows. A
blocked run task or a refused command adds a red line.
```

Then replace:

```markdown
keyboard: `h` **Hand off**, `r` **Resume**, `c` **Compact**, `s` **Settings**, `m` **Minimize**,
```

with:

```markdown
keyboard: `h` **Hand off**, `r` **Resume**, `c` **Compact**, `d` **Dense** or **Detailed**, `s` **Settings**, `m` **Minimize**,
```

- [ ] **Step 4: Add the setting rows**

Replace:

```markdown
| Cockpit | `layout` | `auto` | `auto`: the full layout docked beside the transcript, the band in a pane above the prompt. `full`: always the full layout. `compact`: minimized, no pane and the band above the prompt. **Minimize** sets `compact`, **Expand** sets `auto` (`full` where the pane does not dock). |
```

with:

```markdown
| Cockpit | `layout` | `auto` | `auto`: the full layout docked beside the transcript, the band in a pane above the prompt. `full`: always the full layout. `compact`: minimized, no pane, and a box below the prompt in the terminal (the band above it in the desktop app). **Minimize** sets `compact`, **Expand** sets `auto` (`full` where the pane does not dock). |
| Cockpit | `density` | `detailed` | `detailed`: cards, charts and lists. `dense`: one line per section. **Dense** and **Detailed** in the pane set it. |
```

Then replace:

```markdown
The cockpit settings (Cockpit, Context, Notifications) apply at once, except
the two Claude keys, which Claude reads at its next session start.
```

with:

```markdown
The cockpit settings (Cockpit, Context, Notifications) apply at once, whether
you change them in the pane, with `dforge-config` or in the file, except the
two Claude keys, which Claude reads at its next session start.
```

- [ ] **Step 5: Run the repository validation**

Run each on its own line from the worktree root:

```bash
node scripts/validate-repository.mjs
timeout 600 node scripts/test-all.mjs
env -u CLAUDE_CONFIG_DIR timeout 300 /root/.local/bin/claude plugin validate .
env -u CLAUDE_CONFIG_DIR timeout 300 /root/.local/bin/claude plugin validate plugins/dforge
env -u CLAUDE_CONFIG_DIR timeout 300 /root/.local/bin/claude plugin validate plugins/dr-status
env -u CLAUDE_CONFIG_DIR timeout 300 /root/.local/bin/claude plugin validate plugins/darkraise-ui
env -u CLAUDE_CONFIG_DIR timeout 300 /root/.local/bin/claude plugin validate plugins/darkraise-win32ui
env -u CLAUDE_CONFIG_DIR timeout 300 /root/.local/bin/claude plugin test plugins/dforge
```

Expected: the validator reports no errors, `test-all` ends with no failing suite, every `plugin validate` passes, and the cockpit suite reports 330 pass, 0 fail.

- [ ] **Step 6: Commit**

```bash
git add plugins/dforge/README.md plugins/dforge/config/schema.mjs
git commit -m "docs(cockpit): document live state, density and box"
```
