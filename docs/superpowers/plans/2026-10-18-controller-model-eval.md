# Controller Model Evaluation Harness Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: the skill the **Execution:** line names — dr-superpowers:subagent-driven-development for `subagent`, dr-superpowers:executing-plans for `inline`. Steps use checkbox (`- [ ]`) syntax for tracking.

> **External executors:** codex

**Goal:** Build `evals/controller/`, a harness that measures dforge's subagent-mode controller from Claude Code transcripts and prints the Stage 1 decision of the controller model evaluation, so the owner can decide between Sonnet high and Opus low after the production pilot.

**Architecture:** Pure Node ES modules beside `evals/tiers/`, reusing its TSV reader. `lib/transcript.mjs` prices one transcript per meter and counts tracking slips, seat misses and ledger `complete` lines; `lib/sessions.mjs` finds a plan's controller sessions in one repository and counts launches running at each handoff through dforge's own in-flight scanner; `lib/decide.mjs` holds the Stage 1 rule; `pilot-report.mjs` measures every plan in `pilot.tsv`, marks the rows it cannot use, and applies the rule. Stage 2, the controlled replay, is deferred (register row 24).

**Tech Stack:** Node 24 built-ins (`node:test`, `node:child_process`, `node:fs`), git, bash and jq through dforge's `scripts/lib/in-flight.sh`.

**Spec:** docs/superpowers/notes/2026-10-17-controller-model-eval.md

**Execution:** inline — `claude --model sonnet --effort high` — no task is heavy (highest total 3, no risk 3); every task carries an Executor line and is delegated, which raises the effort to high

**Plan review:** 2026-10-18 — dr-superpowers:judge-opus — executability 16 / coherence 17 / coverage 17 / assumptions 13 (round 2)

**Parallelism:** sequential — the owner chose sequential execution on 2026-10-18

## Global Constraints

- Node built-ins only. Add no dependency and touch no `package.json` or lockfile.
- ES modules (`.mjs`), two-space indent, single quotes, semicolons, matching `evals/tiers/`.
- POSIX only, like `evals/tiers/`: the harness runs dforge's bash in-flight scanner.
- No test calls a model or reads or writes the real `~/.claude/projects`. Tests point `CONTROLLER_EVAL_*` at temporary directories and remove them.
- Prices, USD per million tokens, from <https://platform.claude.com/docs/en/about-claude/pricing> fetched 2026-10-17: Opus 5.5 input 4, 5-minute cache write 5, 1-hour cache write 8, cache read 0.20, output 20; Sonnet 5.5 input 2, 5-minute write 2.50, 1-hour write 4, cache read 0.10, output 10.
- Do not modify `plugins/dforge/` or `evals/tiers/`; import from `evals/tiers/lib/` only.
- Comments only where the reason is not obvious; never name the task or the plan in code.
- Commits: `<type>(evals): <subject>`, subject at most 50 characters, imperative, no period; author `Darkraise <quangtc94@gmail.com>`; no `Co-Authored-By`, `Claude-Session` or "Generated with" lines.
- Each task's test command must finish within 300 seconds; run it with `timeout 300`.

## Contracts

All paths are under `evals/controller/`.

- `lib/transcript.mjs`
  - `PRICES`: `{ 'claude-opus-5-5': { input, write5m, write1h, read, output }, 'claude-sonnet-5-5': { … } }`, the Global Constraints prices.
  - `priceOf(model) -> price | null`: matches a key exactly or as a prefix followed by `-`.
  - `measureTranscript(source: string) -> Metrics`, where `Metrics` is `{ models: string[], efforts: string[], unpriced: string[], completed: string[], last: string, calls, input, write5m, write1h, read, output, cost, dispatches, sleeps, listAgents, monitors, nudges, seatMisses }` (all numbers except the first five fields). `completed` holds the task numbers, in numeric order, of the non-deferred `Task N: complete (` ledger lines the session wrote. A `<synthetic>` message is not a call.
  - `sumMetrics(list: Metrics[]) -> Metrics`; `sumMetrics([])` is all zeros and empty lists.
- `lib/sessions.mjs`
  - `PROJECTS` (env `CONTROLLER_EVAL_PROJECTS`, default `~/.claude/projects`), `PLUGIN` (absolute path of `plugins/dforge`), `REPOS` (env `CONTROLLER_EVAL_REPOS`, default the directory holding this repository).
  - `projectFolder(repo) -> string`; `transcripts(repo, dir = PROJECTS) -> string[]`; `planSlugs(file) -> string[]`; `planSessions(slug, repo, dir = PROJECTS) -> string[]`; `inFlight(file) -> number`.
  - `measureSessions(files) -> { sessions, controller: Metrics, subagents: Metrics, inFlight }`.
  - `flatten(measured) -> Row`, where `Row` is `{ sessions, models, efforts, calls, dispatches, controllerCost, subagentCost, costPerDispatch, sleeps, listAgents, monitors, nudges, seatMisses, inFlight, unpriced }` (`models`, `efforts` and `unpriced` joined with `+`; costs rounded to cents; `costPerDispatch` to thousandths, 0 with no dispatch).
- `lib/decide.mjs`: `BASE = 'sonnet@high'`, `CANDIDATE = 'opus@low'`, `MAX_RATIO = 1.5`, `BUSY = 20`, `MARGIN = 2`; `failures(row) -> number`; `stage1(rows) -> { decision: 'incomplete' | 'keep' | 'switch' | 'ambiguous', ratio, failures }`. Row values may be strings.
- `pilot.tsv` columns: `plan repo arm note` (tab-separated).

## Assumptions (evidence)

- Transcript records: an assistant record carries `message.id`, `message.model`, `message.usage` with a `cache_creation` split into `ephemeral_5m_input_tokens` and `ephemeral_1h_input_tokens`, and a record-level `effort`; one message spans several records under one id. Observed in `~/.claude/projects/-root-repositories-darkraise-ai-plugins/59a902c2-4774-489f-b450-3d85738445e0.jsonl` on 2026-10-18.
- Claude Code keeps a session's transcript under `~/.claude/projects/<the session's directory with every character other than a letter or digit as ->`; worktrees inside a repository appear as `<repository folder>--claude-worktrees-…` and `<repository folder>--worktrees-…`, and a sibling repository such as `darkraise-ai-plugins-wt-sdd-gitignore` as `<repository folder>-…` (`ls ~/.claude/projects`, 2026-10-18).
- The code in Tasks 1 and 2 reproduces the note's recorded costs exactly when run with `--repo` on this machine's transcripts (2026-10-18, scratch worktree): `2026-10-06-enrichment-and-jobs-residuals-8` in `/root/repositories/darkcloud` $2.22 controller and $4.69 subagents, `2026-10-17-m1-repository-tooling` in `/root/repositories/darkpanel` $4.78 and $5.27, `2026-10-13-dr-forge-auto-run` in this repository $7.76 and $16.46. Matching on the plan name alone over-counted (8 sessions and $40.90 for the second), which is why `planSlugs` requires a per-task script run on the plan.
- On those transcripts the seat matcher reports 0 seat misses for the darkcloud and dr-forge plans. A `final-fix` route prints an implementer as its seat (`review-seat final-fix primary=dr-superpowers:impl-sonnet-high fallback=- reason=floor`), and the dr-forge plan's last session printed that route twice before one fixer dispatch; matching only judges, or counting both routes, reported 3 false misses (2026-10-18).
- All code and tests in this plan were run in a scratch worktree of `main` at `ae3c9bb` on 2026-10-18: 19 harness tests pass, `node scripts/validate-repository.mjs` passes, and `tests/repository-layout.test.mjs`, `tests/test-shards.test.mjs` and `tests/ui-discovery.test.mjs` run 37 tests, 36 passing and 1 skipped because `rg` is not installed (the same on `main`).
- Ledger lines: `Task <N>: complete (…` for a finished task and `Task <N>: complete (deferred by the auto run) …` for a deferred one (`plugins/dforge/skills/subagent-driven-development/SKILL.md:331`, `:48`). The controller writes them with its own tool calls, so they stay in the transcript after the worktree and ledger are removed. Checked on the three completed plans above (2026-10-18): the detector, which reads Write, Edit and MultiEdit calls on a `progress.md` path and Bash commands that name `progress.md` and write (`>`, `tee` or a heredoc), finds a `complete` line for every `### Task N` heading of each plan (11, 10 and 3 tasks).
- Per-task scripts take the plan as their first argument (`review-route PLAN_FILE --final-fix <file> …`, `review-package PLAN_FILE BASE HEAD [OUTFILE]`), and controllers often pass it as a variable assigned earlier in the same command (`PLAN=docs/…/x.md` … `task-brief "$PLAN" 3`, seen in the darkpanel plan's session). Taking every `.md` token instead gave that session six extra plans and would have marked it `shared`; reading only the first argument, with the variable resolved, gives each of the three plans exactly its own (2026-10-18).
- A handoff checks that nothing is running (step 0), writes `.dforge/handoff/latest.md` (step 3) and runs `scripts/next-step` (step 4) (`plugins/dforge/skills/handoff/SKILL.md:46`, `:86`, `:112`); `inFlight` takes those two calls, and a session's end, as the boundaries.
- `inflight_scan TRANSCRIPT` prints one line per launch still running, `<agent|shell> <task id> <what>` (`plugins/dforge/scripts/lib/in-flight.sh:18-20`, `:76`). `inFlight` passes no `SINCE`, so a launch made before a resume in the same transcript, whose process died with the old session, counts as running at the end; accepted, since a launch left running at a resume is itself a slip.
- `review-route` prints `review-seat <scope> primary=<seat> fallback=<seat|-> reason=<why>` (`plugins/dforge/scripts/review-route:19-20`). Some judge dispatches are made without a route (`plugins/dforge/skills/subagent-driven-development/SKILL.md:444-448`), so a dispatch with no route waiting is never a miss. Limit: an unrouted confirmation dispatched while a route still waits answers that route, so one miss can be reported or hidden; on the real transcripts above no route waited across such a dispatch.
- Every resume guide takes its launch command from the plan's Execution line (`plugins/dforge/scripts/next-step:230-237`, `execution_launch` at `:76`), so an `opus@low` pilot plan must carry the override in that line, not only in its first launch.
- `git` and `jq` resolve on `PATH` in a non-interactive bash (`command -v`, 2026-10-18).
- Interpretations of the note (it leaves these open): Stage 1 is `ambiguous` when Opus low has fewer failures than Sonnet high but by less than 2, or leaves more plans unfinished; a plan counts one busy wait at 20 or more `sleep` and ListAgents calls; "whether every task has a `complete` line" is read from the ledger lines written in the plan's sessions against the plan's `### Task N` headings at the repository's `HEAD`; "launches still unreported at handoff" is read as launches still running at a handoff, since dforge forbids handing off over running work (commit `39cc554`), whatever the controller said about them; a plan whose session also executed another plan, or whose sessions ran a model or effort other than its arm, is reported and left out of the decision rather than split or relabelled.
- Plan review round 2 scored assumptions 13 (borderline): decision — proceed; the code it doubted (completion detection, plan arguments) was then checked on real transcripts as recorded above, and the remaining limits are stated here.
- Scope: the owner deferred Stage 2 on 2026-10-18, after plan review round 1 found the note's three replay cases unusable as written (register `docs/superpowers/registers/2026-10-17-run-order-finish-controller.md` row 24 holds the reasons, the case criteria and every Stage 2 requirement the review raised).

## Task index

1. Transcript metrics
2. Plan sessions and the measure command
3. Decision rule
4. Stage 1 pilot report and README

---

### Task 1: Transcript metrics

**Files:**
- Create: `evals/controller/lib/transcript.mjs`
- Test: `evals/controller/tests/transcript.test.mjs`
- Modify: `scripts/test-all.mjs:48` (register the suite)

**Interfaces:**
- Consumes: nothing.
- Produces: `lib/transcript.mjs` (Contracts).

**Items:** 3

**Implementer:** dr-superpowers:impl-sonnet-medium
**Executor:** codex gpt-6.1-sol / medium
**Evaluation:** files 1 - spec 0 - coupling 2 - risk 0 = 3

- [ ] **Step 1: Write the failing test**

Create `evals/controller/tests/transcript.test.mjs`:

```js
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { measureTranscript, priceOf, sumMetrics } from '../lib/transcript.mjs';

const usage = (read, output, extra = {}) => ({ input_tokens: 10, cache_read_input_tokens: read, output_tokens: output, cache_creation_input_tokens: 1000, cache_creation: { ephemeral_5m_input_tokens: 0, ephemeral_1h_input_tokens: 1000 }, ...extra });
const said = (id, model, u, content = [], effort = 'high') => ({ type: 'assistant', effort, timestamp: `2026-10-18T00:00:0${id.length % 10}Z`, message: { id, model, usage: u, content } });
const use = (id, name, input) => ({ type: 'tool_use', id, name, input });
const result = (id, text) => ({ type: 'user', message: { content: [{ type: 'tool_result', tool_use_id: id, content: text }] } });
const typed = (text, extra = {}) => ({ type: 'user', message: { content: text }, ...extra });
const jsonl = records => records.map(r => JSON.stringify(r)).join('\n') + '\nnot json\n';

test('each message id is counted once, from its last record, and priced by meter', () => {
  const m = measureTranscript(jsonl([
    said('msg_a', 'claude-sonnet-5-5', usage(200000, 100)),
    said('msg_a', 'claude-sonnet-5-5', usage(200000, 700)),
    said('msg_b', 'claude-opus-5-5', usage(100000, 300), [], 'low'),
  ]));
  assert.equal(m.calls, 2);
  assert.deepEqual([m.input, m.write5m, m.write1h, m.read, m.output], [20, 0, 2000, 300000, 1000]);
  const sonnet = (10 * 2 + 1000 * 4 + 200000 * 0.1 + 700 * 10) / 1e6;
  const opus = (10 * 4 + 1000 * 8 + 100000 * 0.2 + 300 * 20) / 1e6;
  assert.ok(Math.abs(m.cost - (sonnet + opus)) < 1e-9);
  assert.deepEqual(m.models, ['claude-opus-5-5', 'claude-sonnet-5-5']);
  assert.deepEqual(m.efforts, ['high', 'low']);
  assert.deepEqual(m.unpriced, []);
});

test('a usage without the cache split counts its writes as 5-minute writes', () => {
  const m = measureTranscript(jsonl([said('msg_a', 'claude-sonnet-5-5', { input_tokens: 0, cache_creation_input_tokens: 400, cache_read_input_tokens: 0, output_tokens: 0 })]));
  assert.deepEqual([m.write5m, m.write1h], [400, 0]);
  assert.ok(Math.abs(m.cost - 400 * 2.5 / 1e6) < 1e-12);
});

test('an unlisted model is named and left unpriced; a synthetic one is not a call', () => {
  const m = measureTranscript(jsonl([
    said('msg_a', 'claude-haiku-5-5', usage(10, 10)),
    said('msg_b', '<synthetic>', { input_tokens: 0, output_tokens: 0 }),
  ]));
  assert.deepEqual(m.unpriced, ['claude-haiku-5-5']);
  assert.equal(m.cost, 0);
  assert.equal(m.calls, 1);
  assert.deepEqual(m.models, ['claude-haiku-5-5']);
  assert.equal(measureTranscript(jsonl([said('msg_s', '<synthetic>', { input_tokens: 0, output_tokens: 0 })])).calls, 0);
  assert.equal(priceOf('claude-sonnet-5-5-20261001').output, 10);
  assert.equal(priceOf('claude-sonnet-5'), null);
});

test('dispatches, busy waits, monitors and nudges are counted', () => {
  const m = measureTranscript(jsonl([
    said('msg_a', 'claude-sonnet-5-5', usage(1, 1), [
      use('t1', 'Agent', { subagent_type: 'dforge:impl-sonnet-low' }),
      use('t2', 'Bash', { command: 'bash /p/scripts/run-codex-task.sh --task 3' }),
      use('t3', 'Bash', { command: 'sleep 1' }),
      use('t4', 'Bash', { command: 'sleep 30; echo done' }),
      use('t5', 'ListAgents', {}),
      use('t6', 'Monitor', { command: 'tail -f x' }),
    ]),
    said('msg_a', 'claude-sonnet-5-5', usage(1, 1), [use('t1', 'Agent', { subagent_type: 'dforge:impl-sonnet-low' })]),
    typed('check status, I see that there are still agent and shell running'),
    typed('<command-name>/status</command-name> still running'),
    typed('the skill says check status', { isMeta: true }),
  ]));
  assert.deepEqual([m.dispatches, m.sleeps, m.listAgents, m.monitors, m.nudges], [2, 1, 1, 1, 1]);
});

test('each routed review is the next review dispatched, and must reach the printed seat', () => {
  const route = (id, primary, fallback) => [said(`m${id}`, 'claude-sonnet-5-5', usage(1, 1), [use(id, 'Bash', { command: `bash /p/scripts/review-route plan.md --task ${id}` })]), result(id, `review-seat task=${id} primary=${primary} fallback=${fallback} reason=band`)];
  const call = (id, input, name = 'Agent') => said(`c${id}`, 'claude-sonnet-5-5', usage(1, 1), [use(id, name, input)]);
  const m = measureTranscript(jsonl([
    call('early', { subagent_type: 'dforge:judge-opus' }),
    ...route('r1', 'dforge:judge-sonnet-high', '-'),
    call('a1', { subagent_type: 'dforge:impl-sonnet-low' }),
    call('a2', { subagent_type: 'dforge:judge-sonnet-high' }),
    ...route('r2', 'codex:light', 'dforge:judge-opus'),
    ...route('r3', 'codex:light', 'dforge:judge-opus'),
    call('b1', { command: 'bash /p/scripts/run-codex-review.sh --kind code' }, 'Bash'),
    call('b2', { subagent_type: 'dforge:judge-opus' }),
    call('b3', { subagent_type: 'dforge:judge-opus' }),
    ...route('r4', 'dforge:judge-opus', '-'),
    call('c1', { subagent_type: 'dforge:judge-sonnet-high' }),
    call('c2', { subagent_type: 'dforge:judge-opus' }),
    said('mf1', 'claude-sonnet-5-5', usage(1, 1), [use('f1', 'Bash', { command: 'bash /p/scripts/review-route plan.md --final-fix' })]),
    result('f1', 'review-seat final-fix primary=dforge:impl-sonnet-high fallback=- reason=floor'),
    said('mf3', 'claude-sonnet-5-5', usage(1, 1), [use('f3', 'Bash', { command: 'bash /p/scripts/review-route plan.md --final-fix' })]),
    result('f3', 'review-seat final-fix primary=dforge:impl-sonnet-high fallback=- reason=tasks:1,2'),
    call('c3', { subagent_type: 'dforge:judge-opus' }),
    call('f2', { subagent_type: 'dforge:impl-sonnet-high' }),
  ]));
  // r1 reached its seat; r2 and r3, printed together, were answered in order
  // (r3 through its fallback); b3 and c2 are unrouted; r4 went to the wrong
  // judge, and the right judge dispatched after it does not repair that; the
  // final-fix route, printed twice, waits for one implementer, so c3 does not
  // answer it.
  assert.equal(m.seatMisses, 1);
  const open = measureTranscript(jsonl([...route('r5', 'dforge:judge-opus', '-'), call('i1', { subagent_type: 'dforge:impl-sonnet-low' })]));
  assert.equal(open.seatMisses, 1);
});

test('ledger complete lines the controller wrote are collected, deferred ones left out', () => {
  const ledger = '/w/.dforge/sdd/p/progress.md';
  const m = measureTranscript(jsonl([
    said('msg_a', 'claude-sonnet-5-5', usage(1, 1), [
      use('w1', 'Write', { file_path: ledger, content: 'Task 1: complete (commits a..b, review clean) — done: x\nTask 2: complete (deferred by the auto run) — done: nothing\n' }),
      use('e1', 'Edit', { file_path: ledger, old_string: 'x', new_string: 'Task 10: complete (commits c..d, review clean)' }),
      use('b1', 'Bash', { command: "printf '%s\\n' 'Task 4: complete (commits e..f, review clean)' >> .dforge/sdd/p/progress.md" }),
      use('n1', 'Write', { file_path: '/w/notes.md', content: 'Task 5: complete (commits g..h)' }),
      use('n2', 'Write', { file_path: ledger, content: 'Task 6: BLOCKED (tests fail)' }),
      use('r1', 'Bash', { command: "grep -c 'Task 7: complete (' .dforge/sdd/p/progress.md" }),
    ]),
  ]));
  assert.deepEqual(m.completed, ['1', '4', '10']);
});

test('sumMetrics adds counts and merges names', () => {
  const a = measureTranscript(jsonl([said('msg_a', 'claude-sonnet-5-5', usage(100, 10), [use('w', 'Write', { file_path: 'progress.md', content: 'Task 2: complete (x)' })])]));
  const b = measureTranscript(jsonl([said('msg_b', 'claude-opus-5-5', usage(100, 10), [use('v', 'Write', { file_path: 'progress.md', content: 'Task 10: complete (x)\nTask 2: complete (x)' })], 'low'), typed('anything still running?')]));
  const s = sumMetrics([a, b]);
  assert.equal(s.calls, 2);
  assert.equal(s.nudges, 1);
  assert.ok(Math.abs(s.cost - (a.cost + b.cost)) < 1e-12);
  assert.deepEqual(s.efforts, ['high', 'low']);
  assert.deepEqual(s.completed, ['2', '10']);
  assert.equal(sumMetrics([]).calls, 0);
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `timeout 300 node --test evals/controller/tests/transcript.test.mjs`
Expected: FAIL with `ERR_MODULE_NOT_FOUND` for `lib/transcript.mjs`.

- [ ] **Step 3: Write the implementation**

Create `evals/controller/lib/transcript.mjs`:

```js
// USD per million tokens, from https://platform.claude.com/docs/en/about-claude/pricing
// as fetched on 2026-10-17. A model not listed is named in `unpriced`, and its
// tokens are counted but not priced.
export const PRICES = {
  'claude-opus-5-5': { input: 4, write5m: 5, write1h: 8, read: 0.2, output: 20 },
  'claude-sonnet-5-5': { input: 2, write5m: 2.5, write1h: 4, read: 0.1, output: 10 },
};

const METERS = ['input', 'write5m', 'write1h', 'read', 'output'];
const COUNTS = ['calls', ...METERS, 'cost', 'dispatches', 'sleeps', 'listAgents', 'monitors', 'nudges', 'seatMisses'];
const NAMES = ['models', 'efforts', 'unpriced', 'completed'];
// What an owner types when the controller has lost track of its background work.
const NUDGE = /check (the )?status|still running|anything (still )?running/i;
const SLEEP = /^\s*sleep\s+[\d.]+\s*;?\s*$/;
const SEAT = /^review-seat (\S+) .*primary=(\S+) fallback=(\S+)/gm;
// A ledger line the controller wrote; a task the auto run deferred is not done.
const COMPLETE = /(?:^|[\s'"])Task (\d+): complete \((?!deferred by the auto run\))/g;
const isAgent = use => use.name === 'Agent' || use.name === 'Task';
const byNumber = list => [...new Set(list)].sort((a, b) => Number(a) - Number(b));

export function priceOf(model) {
  const key = Object.keys(PRICES).find(k => model === k || model.startsWith(`${k}-`));
  return key === undefined ? null : PRICES[key];
}

function textOf(content) {
  if (typeof content === 'string') return content;
  if (Array.isArray(content)) return content.map(c => (typeof c?.text === 'string' ? c.text : '')).join('\n');
  return '';
}

// The text a tool call writes into a ledger (progress.md), or ''.
function ledgerText(use) {
  const input = use.input ?? {};
  // A Bash command that only reads the ledger (grep, cat) writes nothing into it.
  if (use.name === 'Bash') return /progress\.md/.test(String(input.command ?? '')) && /(>|\btee\b|<<)/.test(String(input.command)) ? String(input.command) : '';
  if (!/progress\.md$/.test(String(input.file_path ?? ''))) return '';
  if (use.name === 'Write') return String(input.content ?? '');
  if (use.name === 'Edit') return String(input.new_string ?? '');
  if (use.name === 'MultiEdit') return (input.edits ?? []).map(e => String(e?.new_string ?? '')).join('\n');
  return '';
}

// measureTranscript SOURCE — one session's metrics from its JSONL transcript.
// Claude Code writes one record per content block, so a message's usage
// repeats under one id: each id is counted once, from its last record.
export function measureTranscript(source) {
  const usage = new Map();
  const uses = new Map();
  const results = new Map();
  const models = new Set();
  const efforts = new Set();
  let nudges = 0;
  let last = '';
  for (const line of source.split('\n')) {
    let r;
    try { r = JSON.parse(line); } catch { continue; }
    if (typeof r?.timestamp === 'string' && r.timestamp > last) last = r.timestamp;
    const m = r?.message;
    // A <synthetic> message is written by Claude Code itself and was never billed.
    if (r?.type === 'assistant' && m?.id && m.usage && !String(m.model ?? '').startsWith('<')) {
      usage.set(m.id, { model: m.model ?? '', usage: m.usage });
      if (m.model) models.add(m.model);
      if (r.effort) efforts.add(r.effort);
    }
    if (r?.type === 'assistant' && Array.isArray(m?.content)) {
      for (const c of m.content) if (c?.type === 'tool_use') uses.set(c.id, c);
    }
    if (r?.type === 'user' && Array.isArray(m?.content)) {
      for (const c of m.content) if (c?.type === 'tool_result') results.set(c.tool_use_id, textOf(c.content));
    }
    // Skill bodies and command wrappers arrive as user records too; only what
    // a person typed counts.
    if (r?.type === 'user' && typeof m?.content === 'string' && !r.isMeta && !m.content.startsWith('<') && NUDGE.test(m.content)) nudges++;
  }

  const out = { models: [...models].sort(), efforts: [...efforts].sort(), unpriced: [], completed: [], last, calls: usage.size };
  for (const k of [...METERS, 'cost']) out[k] = 0;
  const unpriced = new Set();
  for (const { model, usage: u } of usage.values()) {
    const split = u.cache_creation;
    const n = {
      input: u.input_tokens ?? 0,
      write5m: split ? split.ephemeral_5m_input_tokens ?? 0 : u.cache_creation_input_tokens ?? 0,
      write1h: split ? split.ephemeral_1h_input_tokens ?? 0 : 0,
      read: u.cache_read_input_tokens ?? 0,
      output: u.output_tokens ?? 0,
    };
    for (const k of METERS) out[k] += n[k];
    const price = priceOf(model);
    if (price !== null) out.cost += METERS.reduce((sum, k) => sum + n[k] * price[k], 0) / 1e6;
    else if (METERS.some(k => n[k] > 0)) unpriced.add(model);
  }
  out.unpriced = [...unpriced].sort();

  let dispatches = 0, sleeps = 0, listAgents = 0, monitors = 0, seatMisses = 0;
  const completed = [];
  // Routes wait in print order, a review route for the next review dispatch
  // and a final-fix route for the next implementer dispatch; each dispatch
  // answers the oldest route of its kind. A dispatch with no route waiting (a
  // header amendment's confirmation, a task's implementer) is unrouted and
  // never a miss.
  const waiting = { review: [], fix: [] };
  for (const use of uses.values()) {
    const cmd = use.name === 'Bash' ? String(use.input?.command ?? '') : '';
    const type = isAgent(use) ? String(use.input?.subagent_type ?? '') : '';
    if (isAgent(use) || /run-codex-(task|review)\.sh/.test(cmd)) dispatches++;
    if (SLEEP.test(cmd)) sleeps++;
    if (use.name === 'ListAgents') listAgents++;
    if (use.name === 'Monitor') monitors++;
    for (const hit of ledgerText(use).matchAll(COMPLETE)) completed.push(hit[1]);
    let seat = null;
    if (/run-codex-review\.sh/.test(cmd) || /judge-/.test(type)) seat = { kind: 'review', name: type || 'codex' };
    else if (/run-codex-task\.sh/.test(cmd) || /impl-/.test(type)) seat = { kind: 'fix', name: type || 'codex' };
    if (seat !== null && waiting[seat.kind].length > 0) {
      const route = waiting[seat.kind].shift();
      const fits = route.primary.startsWith('codex:') ? seat.name === 'codex' || seat.name === route.fallback : seat.name === route.primary;
      if (!fits) seatMisses++;
    }
    if (/review-route/.test(cmd)) {
      for (const hit of (results.get(use.id) ?? '').matchAll(SEAT)) {
        const queue = waiting[hit[1] === 'final-fix' || /impl-/.test(hit[2]) ? 'fix' : 'review'];
        // A route printed again for a scope still waiting is a re-query, not a second review.
        const again = queue.findIndex(route => route.scope === hit[1]);
        const route = { scope: hit[1], primary: hit[2], fallback: hit[3] };
        if (again === -1) queue.push(route);
        else queue[again] = route;
      }
    }
  }
  seatMisses += waiting.review.length + waiting.fix.length;
  out.completed = byNumber(completed);
  return { ...out, dispatches, sleeps, listAgents, monitors, nudges, seatMisses };
}

// sumMetrics LIST — the metrics of several transcripts added together.
export function sumMetrics(list) {
  const total = measureTranscript('');
  for (const m of list) {
    for (const k of COUNTS) total[k] += m[k];
    for (const k of NAMES) total[k] = k === 'completed' ? byNumber([...total[k], ...m[k]]) : [...new Set([...total[k], ...m[k]])].sort();
    if (m.last > total.last) total.last = m.last;
  }
  return total;
}
```

In `scripts/test-all.mjs`, directly below the line that registers `evals/tiers/tests`, add:

```js
  // The controller-eval harness reads transcripts through dforge's bash
  // in-flight scanner, so it is POSIX only too.
  ...(process.platform === 'win32' ? [] : [[process.execPath, ['--test', ...readdirSync(resolve(root, 'evals/controller/tests')).filter(name => name.endsWith('.test.mjs')).map(name => `evals/controller/tests/${name}`)], 300]]),
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `timeout 300 node --test evals/controller/tests/transcript.test.mjs`
Expected: PASS, 7 tests.
Run: `timeout 60 node scripts/test-all.mjs --list | grep -c evals/controller/tests/transcript.test.mjs`
Expected: `1`.

- [ ] **Step 5: Commit**

```bash
git add evals/controller/lib/transcript.mjs evals/controller/tests/transcript.test.mjs scripts/test-all.mjs
git commit -m "feat(evals): measure controller transcripts"
```

### Task 2: Plan sessions and the measure command

**Files:**
- Create: `evals/controller/lib/sessions.mjs`
- Create: `evals/controller/measure.mjs`
- Test: `evals/controller/tests/sessions.test.mjs`

**Interfaces:**
- Consumes: `lib/transcript.mjs` (Contracts).
- Produces: `lib/sessions.mjs` (Contracts) and `measure.mjs --plan SLUG --repo PATH | --session FILE ...`, which prints `{ files, ...Row }` as JSON and exits 0, 1 when no session matches, 2 on bad usage.

**Items:** 3

**Implementer:** dr-superpowers:impl-sonnet-medium
**Executor:** codex gpt-6.1-sol / medium
**Evaluation:** files 1 - spec 0 - coupling 2 - risk 0 = 3

- [ ] **Step 1: Write the failing test**

Create `evals/controller/tests/sessions.test.mjs`:

```js
import assert from 'node:assert/strict';
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { after, test } from 'node:test';
import { flatten, inFlight, measureSessions, planSessions, planSlugs, projectFolder } from '../lib/sessions.mjs';

const top = mkdtempSync(join(tmpdir(), 'controller-sessions-'));
after(() => rmSync(top, { recursive: true, force: true }));
const usage = { input_tokens: 0, cache_read_input_tokens: 1000000, output_tokens: 0 };
const said = (id, content, model = 'claude-sonnet-5-5') => ({ type: 'assistant', effort: 'high', message: { id, model, usage, content } });
const bash = (id, command, extra = {}) => said(`m-${id}`, [{ type: 'tool_use', id, name: 'Bash', input: { command, ...extra } }]);
const skill = name => said(`s-${name}`, [{ type: 'tool_use', id: `u-${name}`, name: 'Skill', input: { skill: name } }]);
const brief = slug => bash(`u-${slug}`, `bash /p/scripts/task-brief docs/plans/${slug}.md 1`);
const launch = id => [bash(id, 'npm test', { run_in_background: true }), { type: 'user', message: { content: [{ type: 'tool_result', tool_use_id: id, content: `Command running in background with ID: shell-${id}` }] } }];
const done = id => ({ type: 'user', message: { content: `<task-notification><tool-use-id>${id}</tool-use-id><status>completed</status></task-notification>` } });
const write = (path, records) => { mkdirSync(join(path, '..'), { recursive: true }); writeFileSync(path, records.map(r => JSON.stringify(r)).join('\n') + '\n'); };

const REPO = '/r/app';
const own = join(top, '-r-app');
const tree = join(top, '-r-app--worktrees-x');
const SDD = 'dforge:subagent-driven-development';
write(join(own, 's1.jsonl'), [skill(SDD), brief('2026-10-18-alpha'), ...launch('bg')]);
write(join(own, 's1/subagents/agent-x.jsonl'), [said('x1', [], 'claude-opus-5-5')]);
write(join(own, 's2.jsonl'), [brief('2026-10-18-alpha')]);
write(join(tree, 's3.jsonl'), [skill('dr-superpowers:subagent-driven-development'), brief('2026-10-18-beta')]);
write(join(tree, 's4.jsonl'), [skill(SDD), brief('2026-10-18-alpha')]);
write(join(own, 's5.jsonl'), [skill(SDD), brief('2026-10-18-beta'), bash('cat', 'cat docs/plans/2026-10-18-alpha.md')]);
write(join(top, '-r-app-two/s6.jsonl'), [skill(SDD), brief('2026-10-18-alpha')]);
write(join(own, 's7.jsonl'), [skill(SDD), brief('2026-10-18-alpha'), brief('2026-10-18-beta')]);
write(join(own, 's9.jsonl'), [skill(SDD), bash('ff', 'bash /p/scripts/review-route docs/plans/2026-10-18-alpha.md --final-fix README.md docs/guide.md && cat .dforge/handoff/latest.md'), bash('pk', "bash /p/scripts/review-package 'docs/plans/2026-10-18-alpha.md' a1 b2 out/package.md; cat notes.md"), bash('vr', 'PLAN=docs/plans/2026-10-18-alpha.md\nbash $P/scripts/task-brief "$PLAN" 2 > $W/task-2-brief.md\ncp x/task-3-report.md $W/task-3-report.md')]);
write(join(own, 's8.jsonl'), [...launch('early'), done('early'), ...launch('late'), bash('next', 'bash /p/scripts/next-step docs/plans/x.md'), done('late')]);

test('projectFolder spells a path as Claude Code names its project folder', () => {
  assert.equal(projectFolder('/root/repositories/darkraise-ai-plugins'), '-root-repositories-darkraise-ai-plugins');
});

test('planSessions finds the repository\'s sessions that ran a task script on the plan', () => {
  assert.deepEqual(planSessions('2026-10-18-alpha', REPO, top).map(f => f.slice(top.length)).sort(), ['/-r-app--worktrees-x/s4.jsonl', '/-r-app/s1.jsonl', '/-r-app/s7.jsonl', '/-r-app/s9.jsonl']);
  assert.deepEqual(planSessions('2026-10-18-gamma', REPO, top), []);
  assert.deepEqual(planSessions('x', REPO, join(top, 'missing')), []);
});

test('planSlugs names every plan a session executed', () => {
  assert.deepEqual(planSlugs(join(own, 's7.jsonl')), ['2026-10-18-alpha', '2026-10-18-beta']);
  assert.deepEqual(planSlugs(join(own, 's5.jsonl')), ['2026-10-18-beta']);
  assert.deepEqual(planSlugs(join(own, 's2.jsonl')), []);
  assert.deepEqual(planSlugs(join(own, 's9.jsonl')), ['2026-10-18-alpha']);
});

test('inFlight counts launches running at a handoff or at the end', () => {
  assert.equal(inFlight(join(own, 's1.jsonl')), 1);
  assert.equal(inFlight(join(tree, 's3.jsonl')), 0);
  assert.equal(inFlight(join(own, 's8.jsonl')), 1);
});

test('measureSessions sums controllers and subagents, and flatten rounds the costs', () => {
  const row = flatten(measureSessions([join(own, 's1.jsonl'), join(tree, 's4.jsonl')]));
  assert.equal(row.sessions, 2);
  assert.equal(row.calls, 5);
  assert.equal(row.controllerCost, 0.5);
  assert.equal(row.subagentCost, 0.2);
  assert.equal(row.inFlight, 1);
  assert.equal(row.dispatches, 0);
  assert.equal(row.costPerDispatch, 0);
  assert.equal(row.models, 'claude-sonnet-5-5');
});

test('measure.mjs prints a plan\'s row, and exits 1 when no session matches', () => {
  const run = (...args) => spawnSync(process.execPath, ['evals/controller/measure.mjs', ...args], { encoding: 'utf8', env: { ...process.env, CONTROLLER_EVAL_PROJECTS: top } });
  const ok = run('--plan', '2026-10-18-beta', '--repo', REPO);
  assert.equal(ok.status, 0, ok.stderr);
  assert.equal(JSON.parse(ok.stdout).sessions, 3);
  assert.equal(run('--plan', '2026-10-18-gamma', '--repo', REPO).status, 1);
  assert.equal(run('--plan', '2026-10-18-beta').status, 2);
  assert.equal(run().status, 2);
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `timeout 300 node --test evals/controller/tests/sessions.test.mjs`
Expected: FAIL with `ERR_MODULE_NOT_FOUND` for `lib/sessions.mjs`.

- [ ] **Step 3: Write the implementation**

Create `evals/controller/lib/sessions.mjs`:

```js
import { existsSync, mkdtempSync, readFileSync, readdirSync, rmSync, statSync, writeFileSync } from 'node:fs';
import { homedir, tmpdir } from 'node:os';
import { basename, dirname, join, resolve } from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { measureTranscript, sumMetrics } from './transcript.mjs';

export const PROJECTS = process.env.CONTROLLER_EVAL_PROJECTS ?? join(homedir(), '.claude/projects');
export const PLUGIN = fileURLToPath(new URL('../../../plugins/dforge', import.meta.url));
// A pilot repository given by a relative path is a sibling of this one.
export const REPOS = process.env.CONTROLLER_EVAL_REPOS ?? fileURLToPath(new URL('../../../..', import.meta.url));

// Every per-task script takes the plan as its first argument, often as a
// variable the same command assigned (PLAN=docs/…/x.md … task-brief "$PLAN").
const PER_TASK = /\b(?:task-brief|review-route|review-package)[ \t]+([^\s;&|]+)/g;
const ASSIGN = /\b([A-Za-z_]\w*)=(['"]?)([^\s'";&|]+)\2/g;

function planArgs(cmd) {
  const vars = Object.fromEntries([...cmd.matchAll(ASSIGN)].map(m => [m[1], m[3]]));
  return [...cmd.matchAll(PER_TASK)].flatMap(m => {
    const arg = m[1].replace(/^['"]|['"]$/g, '').replace(/^\$\{?(\w+)\}?$/, (_, name) => vars[name] ?? '');
    return arg.endsWith('.md') ? [basename(arg, '.md')] : [];
  });
}
// A handoff writes .dforge/handoff/latest.md and runs scripts/next-step.
const BOUNDARY = use => (use.name === 'Bash' && /scripts\/next-step\b/.test(String(use.input?.command ?? '')))
  || (['Write', 'Edit'].includes(use.name) && /handoff\/latest\.md$/.test(String(use.input?.file_path ?? '')));

// projectFolder REPO — the folder Claude Code keeps REPO's transcripts in: the
// absolute path with every character other than a letter or digit as '-'.
export const projectFolder = repo => resolve(repo).replace(/[^A-Za-z0-9]/g, '-');

// transcripts REPO [DIR] — every main-session transcript of REPO and of the
// worktrees inside it. Subagent transcripts sit one level deeper and are not
// listed; a sibling repository whose name starts with REPO's is not REPO.
export function transcripts(repo, dir = PROJECTS) {
  if (!existsSync(dir)) return [];
  const own = projectFolder(repo);
  return readdirSync(dir).flatMap(project => {
    const folder = join(dir, project);
    if ((project !== own && !project.startsWith(`${own}--`)) || !statSync(folder).isDirectory()) return [];
    return readdirSync(folder).filter(name => name.endsWith('.jsonl')).map(name => join(folder, name));
  });
}

function toolUses(file) {
  return readFileSync(file, 'utf8').split('\n').flatMap(line => {
    let r;
    try { r = JSON.parse(line); } catch { return []; }
    return r?.type === 'assistant' && Array.isArray(r.message?.content) ? r.message.content.filter(c => c?.type === 'tool_use') : [];
  });
}

// planSlugs FILE — the plans FILE's session executed: those it ran a per-task
// script on, when it invoked subagent-driven-development. A later plan's
// sessions often name an earlier plan without executing it.
export function planSlugs(file) {
  const uses = toolUses(file);
  if (!uses.some(u => u.name === 'Skill' && /subagent-driven-development$/.test(String(u.input?.skill ?? '')))) return [];
  const slugs = uses.flatMap(u => (u.name === 'Bash' ? planArgs(String(u.input?.command ?? '')) : []));
  return [...new Set(slugs)].sort();
}

// planSessions SLUG REPO [DIR] — the controller sessions of the plan whose
// file is SLUG.md in REPO, oldest first.
export function planSessions(slug, repo, dir = PROJECTS) {
  return transcripts(repo, dir).filter(file => planSlugs(file).includes(slug)).sort((a, b) => statSync(a).mtimeMs - statSync(b).mtimeMs);
}

// inFlight FILE — the background launches still running at a handoff or at
// the end of FILE's session, as scripts/in-flight counts them. Work running
// at a handoff is a slip however it is reported, and a notification after it
// does not undo that.
export function inFlight(file) {
  const lines = readFileSync(file, 'utf8').split('\n');
  const cuts = [];
  lines.forEach((line, i) => {
    let r;
    try { r = JSON.parse(line); } catch { return; }
    if (r?.type === 'assistant' && Array.isArray(r.message?.content) && r.message.content.some(c => c?.type === 'tool_use' && BOUNDARY(c))) cuts.push(i + 1);
  });
  cuts.push(lines.length);
  const tmp = mkdtempSync(join(tmpdir(), 'controller-inflight-'));
  const running = new Set();
  try {
    for (const cut of cuts) {
      const part = join(tmp, 'part.jsonl');
      writeFileSync(part, lines.slice(0, cut).join('\n') + '\n');
      const r = spawnSync('bash', ['-c', '. "$1/scripts/lib/in-flight.sh"; inflight_scan "$2"', 'in-flight', PLUGIN, part], { encoding: 'utf8' });
      if (r.status !== 0) throw new Error(`inflight_scan ${file}: ${r.stderr.trim()}`);
      for (const launch of r.stdout.split('\n').filter(Boolean)) running.add(launch.split(' ')[1]);
    }
  } finally {
    rmSync(tmp, { recursive: true, force: true });
  }
  return running.size;
}

// measureSessions FILES — the controller metrics of FILES summed, their
// subagents' summed, and the launches each session left running.
export function measureSessions(files) {
  const subagents = files.flatMap(file => {
    const folder = join(dirname(file), basename(file, '.jsonl'), 'subagents');
    if (!existsSync(folder)) return [];
    return readdirSync(folder).filter(name => name.endsWith('.jsonl')).map(name => measureTranscript(readFileSync(join(folder, name), 'utf8')));
  });
  return {
    sessions: files.length,
    controller: sumMetrics(files.map(file => measureTranscript(readFileSync(file, 'utf8')))),
    subagents: sumMetrics(subagents),
    inFlight: files.reduce((sum, file) => sum + inFlight(file), 0),
  };
}

const cents = n => Math.round(n * 100) / 100;

// flatten MEASURED — one row of the numbers the reports compare.
export function flatten(m) {
  const c = m.controller;
  return {
    sessions: m.sessions,
    models: c.models.join('+'),
    efforts: c.efforts.join('+'),
    calls: c.calls,
    dispatches: c.dispatches,
    controllerCost: cents(c.cost),
    subagentCost: cents(m.subagents.cost),
    costPerDispatch: c.dispatches === 0 ? 0 : Math.round((c.cost / c.dispatches) * 1000) / 1000,
    sleeps: c.sleeps,
    listAgents: c.listAgents,
    monitors: c.monitors,
    nudges: c.nudges,
    seatMisses: c.seatMisses,
    inFlight: m.inFlight,
    unpriced: [...new Set([...c.unpriced, ...m.subagents.unpriced])].sort().join('+'),
  };
}
```

Create `evals/controller/measure.mjs`:

```js
// node evals/controller/measure.mjs --plan SLUG --repo PATH | --session FILE [FILE ...]
// Prints the controller metrics of a plan's controller sessions in the
// repository at PATH, or of the transcripts named, as one JSON object. Reads
// only; calls no model.
import { flatten, measureSessions, planSessions } from './lib/sessions.mjs';

const args = process.argv.slice(2);
let files;
if (args.length === 4 && args[0] === '--plan' && args[2] === '--repo') files = planSessions(args[1], args[3]);
else if (args[0] === '--session' && args.length > 1) files = args.slice(1);
else {
  console.error('usage: measure.mjs --plan SLUG --repo PATH | --session FILE [FILE ...]');
  process.exit(2);
}
if (files.length === 0) {
  console.error(`measure: no controller session found for ${args[1]} in ${args[3]}`);
  process.exit(1);
}
console.log(JSON.stringify({ files, ...flatten(measureSessions(files)) }, null, 2));
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `timeout 300 node --test evals/controller/tests/transcript.test.mjs evals/controller/tests/sessions.test.mjs`
Expected: PASS, 13 tests.
Run: `timeout 300 node evals/controller/measure.mjs --plan 2026-10-13-dr-forge-auto-run --repo /root/repositories/darkraise-ai-plugins | grep -E '"(controllerCost|subagentCost|seatMisses)"'`
Expected, on the owner's machine where those transcripts exist: `"controllerCost": 7.76,`, `"subagentCost": 16.46,` and `"seatMisses": 0,`. Where they do not exist, the command prints `measure: no controller session found` and exits 1; record that and continue.

- [ ] **Step 5: Commit**

```bash
git add evals/controller/lib/sessions.mjs evals/controller/measure.mjs evals/controller/tests/sessions.test.mjs
git commit -m "feat(evals): find and measure a plan's sessions"
```

### Task 3: Decision rule

**Files:**
- Create: `evals/controller/lib/decide.mjs`
- Test: `evals/controller/tests/decide.test.mjs`

**Interfaces:**
- Consumes: nothing.
- Produces: `lib/decide.mjs` (Contracts).

**Items:** 3

**Implementer:** dr-superpowers:impl-sonnet-medium
**Executor:** codex gpt-6.1-sol / medium
**Evaluation:** files 1 - spec 0 - coupling 2 - risk 0 = 3

- [ ] **Step 1: Write the failing test**

Create `evals/controller/tests/decide.test.mjs`:

```js
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { failures, stage1 } from '../lib/decide.mjs';

const plan = (arm, cost, extra = {}) => ({ arm, complete: 'yes', controllerCost: String(cost), dispatches: '10', inFlight: '0', seatMisses: '0', nudges: '0', sleeps: '0', listAgents: '0', ...extra });
const three = (arm, cost, extras = [{}, {}, {}]) => extras.map(e => plan(arm, cost, e));

test('failures adds launches left running, seat misses, nudges and one busy wait', () => {
  assert.equal(failures({ inFlight: '1', seatMisses: '2', nudges: '1', sleeps: '19', listAgents: '0' }), 4);
  assert.equal(failures({ inFlight: 0, seatMisses: 0, nudges: 0, sleeps: 15, listAgents: 5 }), 1);
  assert.equal(failures({}), 0);
});

test('stage1 waits for three plans per arm', () => {
  assert.equal(stage1([...three('sonnet@high', 2), plan('opus@low', 3)]).decision, 'incomplete');
});

test('stage1 keeps Sonnet when Opus costs too much or fixes nothing', () => {
  assert.equal(stage1([...three('sonnet@high', 2, [{ nudges: 3 }, {}, {}]), ...three('opus@low', 3.1)]).decision, 'keep');
  const even = stage1([...three('sonnet@high', 2, [{ nudges: 1 }, {}, {}]), ...three('opus@low', 2.8, [{ inFlight: 1 }, {}, {}])]);
  assert.equal(even.decision, 'keep');
  assert.ok(Math.abs(even.ratio - 1.4) < 1e-9);
});

test('stage1 switches on a clear margin and is ambiguous on a narrow one', () => {
  assert.equal(stage1([...three('sonnet@high', 2, [{ nudges: 1 }, { inFlight: 1 }, {}]), ...three('opus@low', 2.8)]).decision, 'switch');
  assert.equal(stage1([...three('sonnet@high', 2, [{ nudges: 1 }, {}, {}]), ...three('opus@low', 2.8)]).decision, 'ambiguous');
  assert.equal(stage1([...three('sonnet@high', 2, [{ nudges: 2 }, {}, {}]), ...three('opus@low', 2.8, [{ complete: 'no' }, {}, {}])]).decision, 'ambiguous');
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `timeout 300 node --test evals/controller/tests/decide.test.mjs`
Expected: FAIL with `ERR_MODULE_NOT_FOUND` for `lib/decide.mjs`.

- [ ] **Step 3: Write the implementation**

Create `evals/controller/lib/decide.mjs`:

```js
// The Stage 1 decision rule of docs/superpowers/notes/2026-10-17-controller-model-eval.md.
// Rows may come from a TSV, so every number is read through Number().

export const BASE = 'sonnet@high';
export const CANDIDATE = 'opus@low';
// The most an Opus controller may cost per dispatch, as a multiple of the base.
export const MAX_RATIO = 1.5;
// Sleep and ListAgents calls in one plan at which the plan counts as a busy wait.
export const BUSY = 20;
// How many more tracking failures the base needs before the difference is
// read as more than noise.
export const MARGIN = 2;

const num = v => Number(v ?? 0);

// failures ROW — the tracking and protocol slips of one plan: launches left
// running, routed reviews that missed their seat, owner nudges, and one for a
// busy wait.
export function failures(row) {
  return num(row.inFlight) + num(row.seatMisses) + num(row.nudges) + (num(row.sleeps) + num(row.listAgents) >= BUSY ? 1 : 0);
}

const total = (rows, key) => rows.reduce((sum, r) => sum + num(r[key]), 0);
const slips = rows => rows.reduce((sum, r) => sum + failures(r), 0);
const perDispatch = rows => total(rows, 'controllerCost') / Math.max(1, total(rows, 'dispatches'));

// stage1 ROWS — the production A/B over usable rows { arm, complete: yes|no,
// ... }. keep when Opus costs over MAX_RATIO per dispatch or fails as often;
// switch when the base fails at least MARGIN more often and Opus left no more
// plans unfinished; ambiguous otherwise; incomplete until each arm has 3 plans.
export function stage1(rows) {
  const base = rows.filter(r => r.arm === BASE);
  const opus = rows.filter(r => r.arm === CANDIDATE);
  const facts = { ratio: perDispatch(opus) / Math.max(1e-9, perDispatch(base)), failures: { [BASE]: slips(base), [CANDIDATE]: slips(opus) } };
  if (base.length < 3 || opus.length < 3) return { decision: 'incomplete', ...facts };
  const unfinished = list => list.filter(r => r.complete !== 'yes').length;
  if (facts.ratio > MAX_RATIO || slips(opus) >= slips(base)) return { decision: 'keep', ...facts };
  if (slips(base) - slips(opus) >= MARGIN && unfinished(opus) <= unfinished(base)) return { decision: 'switch', ...facts };
  return { decision: 'ambiguous', ...facts };
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `timeout 300 node --test evals/controller/tests/decide.test.mjs`
Expected: PASS, 4 tests.

- [ ] **Step 5: Commit**

```bash
git add evals/controller/lib/decide.mjs evals/controller/tests/decide.test.mjs
git commit -m "feat(evals): add the controller decision rule"
```

### Task 4: Stage 1 pilot report and README

**Files:**
- Create: `evals/controller/pilot.tsv`
- Create: `evals/controller/pilot-report.mjs`
- Create: `evals/controller/README.md`
- Test: `evals/controller/tests/pilot.test.mjs`

**Interfaces:**
- Consumes: `REPOS`, `planSessions`, `planSlugs`, `measureSessions` and `flatten` from `lib/sessions.mjs`, and `projectFolder` in the test only; `BASE`, `CANDIDATE` and `stage1` from `lib/decide.mjs` (Contracts); `readTsv` from `evals/tiers/lib/results.mjs`.
- Produces: `pilot.tsv` (Contracts) and `pilot-report.mjs`, which prints a header, one row per plan with its `status` and a `stage1: …` line; exit 2 on an arm other than `sonnet@high` or `opus@low`.

**Items:** 3

**Implementer:** dr-superpowers:impl-sonnet-medium
**Executor:** codex gpt-6.1-sol / medium
**Evaluation:** files 1 - spec 0 - coupling 2 - risk 0 = 3

- [ ] **Step 1: Write the failing test**

Create `evals/controller/tests/pilot.test.mjs`:

````js
import assert from 'node:assert/strict';
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { after, test } from 'node:test';
import { projectFolder } from '../lib/sessions.mjs';

const top = mkdtempSync(join(tmpdir(), 'controller-pilot-'));
after(() => rmSync(top, { recursive: true, force: true }));
const projects = join(top, 'projects');
const data = join(top, 'data');
const repo = join(top, 'repos/app');
const folder = join(projects, projectFolder(repo));

const usage = { input_tokens: 0, cache_read_input_tokens: 1000000, output_tokens: 0 };
const said = (id, model, effort, content) => ({ type: 'assistant', effort, message: { id, model, usage, content } });
const use = (id, name, input) => ({ type: 'tool_use', id, name, input });
const session = (slugs, model, effort, done = []) => [
  said('s', model, effort, [use('u0', 'Skill', { skill: 'dforge:subagent-driven-development' })]),
  ...slugs.map((slug, i) => said(`b${i}`, model, effort, [use(`u${i + 1}`, 'Bash', { command: `bash /p/scripts/task-brief docs/plans/${slug}.md 1` })])),
  ...done.map(n => said(`l${n}`, model, effort, [use(`w${n}`, 'Write', { file_path: '/w/.dforge/sdd/x/progress.md', content: `Task ${n}: complete (commits a..b, review clean)\n` })])),
  { type: 'user', message: { content: 'check status please' } },
].map(r => JSON.stringify(r)).join('\n') + '\n';
const write = (path, text) => { mkdirSync(join(path, '..'), { recursive: true }); writeFileSync(path, text); };

const SONNET = 'claude-sonnet-5-5';
const OPUS = 'claude-opus-5-5';
write(join(folder, 'one.jsonl'), session(['2026-10-18-one'], SONNET, 'high', [1, 2]));
write(join(folder, 'two.jsonl'), session(['2026-10-18-two'], SONNET, 'low', [1, 2]));
write(join(folder, 'four.jsonl'), session(['2026-10-18-four'], OPUS, 'low', [1]));
// Five ran one session on the arm and one on Opus medium: the arms mixed.
write(join(folder, 'five-a.jsonl'), session(['2026-10-18-five'], OPUS, 'low', [1]));
write(join(folder, 'five-b.jsonl'), session(['2026-10-18-five'], OPUS, 'medium', [2]));
write(join(folder, 'mixed.jsonl'), session(['2026-10-18-six', '2026-10-18-seven'], OPUS, 'low', [1, 2]));
write(join(folder, 'eight.jsonl'), session(['2026-10-18-eight'], SONNET, 'high', [1, 2]));
// Task 9 is quoted inside a fence and is not one of the plan's tasks.
const PLAN_TEXT = '# P\n\n### Task 1: A\n\n````markdown\n```js\n### Task 9: quoted\n```\n````\n\n### Task 2: B\n';
for (const slug of ['one', 'two', 'three', 'four', 'five', 'six']) write(join(repo, `docs/plans/2026-10-18-${slug}.md`), PLAN_TEXT);
spawnSync('git', ['init', '-q', repo]);
spawnSync('git', ['-C', repo, 'add', '-A']);
spawnSync('git', ['-C', repo, '-c', 'user.name=t', '-c', 'user.email=t@example.invalid', 'commit', '-q', '-m', 'init']);

const report = rows => {
  write(join(data, 'pilot.tsv'), ['plan\trepo\tarm\tnote', ...rows].join('\n') + '\n');
  return spawnSync(process.execPath, ['evals/controller/pilot-report.mjs'], { encoding: 'utf8', env: { ...process.env, CONTROLLER_EVAL_PROJECTS: projects, CONTROLLER_EVAL_DATA: data, CONTROLLER_EVAL_REPOS: join(top, 'repos') } });
};

test('pilot-report prints a row per plan with its status, and decides on the usable ones', () => {
  const r = report([
    'docs/plans/2026-10-18-one.md\tapp\tsonnet@high\t-',
    `docs/plans/2026-10-18-two.md\t${repo}\topus@low\tlaunched on the wrong line`,
    'docs/plans/2026-10-18-three.md\tapp\topus@low\tnot run yet',
    'docs/plans/2026-10-18-four.md\tapp\topus@low\t-',
    'docs/plans/2026-10-18-five.md\tapp\topus@low\tresumed on medium',
    'docs/plans/2026-10-18-six.md\tapp\topus@low\tran with seven',
    'docs/plans/2026-10-18-eight.md\tapp\tsonnet@high\tplan not committed',
  ]);
  assert.equal(r.status, 0, r.stderr);
  const lines = r.stdout.trim().split('\n');
  assert.equal(lines.length, 9);
  const rows = lines.slice(1, 8).map(l => l.split('\t'));
  assert.deepEqual(rows.map(row => row.slice(0, 4)), [
    ['2026-10-18-one', 'sonnet@high', 'ok', 'yes'],
    ['2026-10-18-two', 'opus@low', 'mismatch', 'yes'],
    ['2026-10-18-three', 'opus@low', 'no-sessions', 'no'],
    ['2026-10-18-four', 'opus@low', 'ok', 'no'],
    ['2026-10-18-five', 'opus@low', 'mismatch', 'yes'],
    ['2026-10-18-six', 'opus@low', 'shared', 'yes'],
    ['2026-10-18-eight', 'sonnet@high', 'no-plan', 'unknown'],
  ]);
  assert.deepEqual(rows[0].slice(4, 8), ['1', '0', SONNET, 'high']);
  assert.deepEqual([rows[0][11], rows[0][13]], ['4', '1']);
  assert.equal(lines[8], 'stage1: incomplete — 2 of 7 plans usable; opus@low costs 1.50x sonnet@high per dispatch; failures sonnet@high 1, opus@low 1');
});

test('pilot-report refuses an arm the pilot does not run', () => {
  const r = report(['docs/plans/2026-10-18-one.md\tapp\tsonnet@medium\t-']);
  assert.equal(r.status, 2);
  assert.match(r.stderr, /arm must be sonnet@high or opus@low/);
});
````

- [ ] **Step 2: Run the test to verify it fails**

Run: `timeout 300 node --test evals/controller/tests/pilot.test.mjs`
Expected: FAIL: both tests report a nonzero exit, because `pilot-report.mjs` does not exist.

- [ ] **Step 3: Write the implementation and the README**

Create `evals/controller/pilot.tsv` holding only its tab-separated header:

```bash
printf 'plan\trepo\tarm\tnote\n' > evals/controller/pilot.tsv
```

Create `evals/controller/pilot-report.mjs`:

```js
// node evals/controller/pilot-report.mjs
// Measures every plan pilot.tsv lists and prints one row per plan, then the
// Stage 1 decision over the rows whose status is ok. Reads only; calls no model.
import { basename, isAbsolute, join, resolve } from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { readTsv } from '../tiers/lib/results.mjs';
import { BASE, CANDIDATE, stage1 } from './lib/decide.mjs';
import { REPOS, flatten, measureSessions, planSessions, planSlugs } from './lib/sessions.mjs';

const HERE = fileURLToPath(new URL('.', import.meta.url));
const DATA = process.env.CONTROLLER_EVAL_DATA ?? HERE;
const COLUMNS = ['plan', 'arm', 'status', 'complete', 'sessions', 'shared', 'models', 'efforts', 'controllerCost', 'subagentCost', 'dispatches', 'calls', 'costPerDispatch', 'nudges', 'inFlight', 'seatMisses', 'sleeps', 'listAgents', 'monitors', 'unpriced'];

// planTasks TEXT — the task numbers of a plan's `### Task N` headings,
// skipping fenced code, where a plan may quote another plan.
function planTasks(text) {
  const tasks = new Set();
  let fence = null;
  for (const line of text.split('\n')) {
    const marker = line.match(/^ {0,3}(`{3,}|~{3,})(.*)$/);
    if (fence === null) {
      if (marker) fence = marker[1];
      else if (/^### Task (\d+)/.test(line)) tasks.add(line.match(/^### Task (\d+)/)[1]);
    } else if (marker && marker[1][0] === fence[0] && marker[1].length >= fence.length && marker[2].trim() === '') fence = null;
  }
  return [...tasks];
}

// complete REPO PLAN DONE — yes when every task of PLAN, as committed at
// REPO's HEAD, has a complete line among DONE; unknown when the plan cannot
// be read there or has no task.
function complete(repo, plan, done) {
  const shown = spawnSync('git', ['-C', repo, 'show', `HEAD:${plan}`], { encoding: 'utf8' });
  const tasks = shown.status === 0 ? planTasks(shown.stdout) : [];
  if (tasks.length === 0) return 'unknown';
  return tasks.every(n => done.includes(n)) ? 'yes' : 'no';
}

// The arm's model and effort must be the only ones its controller sessions
// ran on; a resume on another launch line would mix the arms.
function onArm(arm, controller) {
  const [family, effort] = arm.split('@');
  return controller.models.length > 0 && controller.models.every(m => m.startsWith(`claude-${family}-5-5`))
    && controller.efforts.length === 1 && controller.efforts[0] === effort;
}

const rows = [];
for (const entry of readTsv(join(DATA, 'pilot.tsv'))) {
  if (entry.arm !== BASE && entry.arm !== CANDIDATE) {
    console.error(`pilot-report: ${entry.plan}: arm must be ${BASE} or ${CANDIDATE}, not ${entry.arm}`);
    process.exit(2);
  }
  const slug = basename(entry.plan, '.md');
  const repo = isAbsolute(entry.repo) ? entry.repo : resolve(REPOS, entry.repo);
  const files = planSessions(slug, repo);
  const measured = measureSessions(files);
  const row = { plan: slug, arm: entry.arm, complete: complete(repo, entry.plan, measured.controller.completed), shared: files.filter(f => planSlugs(f).length > 1).length, ...flatten(measured) };
  if (row.sessions === 0) row.status = 'no-sessions';
  else if (row.shared > 0) row.status = 'shared';
  else if (!onArm(entry.arm, measured.controller)) row.status = 'mismatch';
  else if (row.unpriced !== '') row.status = 'unpriced';
  else if (row.complete === 'unknown') row.status = 'no-plan';
  else row.status = 'ok';
  rows.push(row);
}
console.log(COLUMNS.join('\t'));
for (const row of rows) console.log(COLUMNS.map(k => row[k]).join('\t'));
const usable = rows.filter(row => row.status === 'ok');
const r = stage1(usable);
console.log(`stage1: ${r.decision} — ${usable.length} of ${rows.length} plans usable; ${CANDIDATE} costs ${r.ratio.toFixed(2)}x ${BASE} per dispatch; failures ${BASE} ${r.failures[BASE]}, ${CANDIDATE} ${r.failures[CANDIDATE]}`);
```

Create `evals/controller/README.md`:

```markdown
# Controller model evaluation harness

Decides whether dforge's subagent-mode controller should move from
`claude --model sonnet --effort high` to Opus 5.5 at `low`. The question, the
evidence and the decision rules are in
`docs/superpowers/notes/2026-10-17-controller-model-eval.md`.

This is Stage 1 of that note: it reads Claude Code transcripts and calls no
model. Stage 2, the controlled replay, is planned only if Stage 1 ends
`ambiguous`. POSIX only.

## Commands

Run them from the repository root.

| Command | What it does |
|---|---|
| `node evals/controller/measure.mjs --plan SLUG --repo PATH` | The controller metrics of one plan's controller sessions in the repository at PATH, as JSON |
| `node evals/controller/measure.mjs --session FILE ...` | The same for named transcripts |
| `node evals/controller/pilot-report.mjs` | One row per plan in `pilot.tsv`, then `stage1: keep, switch, ambiguous or incomplete` |
| `node --test evals/controller/tests/*.test.mjs` | The harness tests |

## Running the pilot

For each of the next 6 subagent-mode plans, alternating and starting with
`opus@low`:

1. Add a row to `pilot.tsv`: the plan's repository-relative path, its
   repository (a sibling directory name of this repository, or an absolute
   path), the arm, and a note.
2. For an `opus@low` row, change the plan's `**Execution:**` line to
   `claude --model opus --effort low` and commit it before the first execution
   session. Every handoff and resume guide takes its launch command from that
   line, so changing only the first launch would put later sessions back on
   Sonnet. `plan-lint` only warns about the override. Leave a `sonnet@high`
   plan's line as it is.
3. Execute each plan in sessions of its own: a session that also executes
   another plan cannot be priced per plan.
4. When all 6 plans are done, run `pilot-report.mjs`. On `ambiguous`, plan
   Stage 2.

A plan's controller sessions are the repository's transcripts, its worktrees'
included, that invoked `subagent-driven-development` and ran `task-brief`,
`review-route` or `review-package` on that plan. A plan is complete when every
`### Task N` heading of the plan, as committed at the repository's `HEAD`, has a
`Task N: complete (` ledger line written in those sessions; a line the auto run
marked `deferred by the auto run` does not count.

Only rows whose `status` is `ok` enter the decision:

| Status | Meaning |
|---|---|
| `ok` | Measured and usable |
| `no-sessions` | No controller session found yet |
| `shared` | A session also executed another plan, so its cost cannot be split |
| `mismatch` | A controller session ran on a model or effort other than the arm's |
| `unpriced` | A model has no price in `lib/transcript.mjs` |
| `no-plan` | The plan cannot be read at the repository's `HEAD`, or has no task |

## Metrics

| Metric | Meaning |
|---|---|
| `controllerCost`, `subagentCost` | Transcript tokens priced per meter at the rates in `lib/transcript.mjs` |
| `dispatches` | Agent dispatches plus Codex task and review runs |
| `calls` | Controller API calls, one per message; the note's baseline is 5.8 per dispatch |
| `costPerDispatch` | `controllerCost / dispatches` |
| `sleeps`, `listAgents` | Busy-wait calls: bare `sleep N` commands and ListAgents calls |
| `nudges` | Messages typed by a person asking about status or running work |
| `seatMisses` | Routes `review-route` printed whose next review (or, for a final fix, next implementer) dispatch went to another seat, or never came |
| `inFlight` | Background launches still running at a handoff or at the end of a session, as `scripts/in-flight` counts them |

A plan's failures are `inFlight + seatMisses + nudges`, plus one when
`sleeps + listAgents` reaches 20.

## Environment

| Variable | Default |
|---|---|
| `CONTROLLER_EVAL_PROJECTS` | `~/.claude/projects` |
| `CONTROLLER_EVAL_REPOS` | the directory holding this repository |
| `CONTROLLER_EVAL_DATA` | `evals/controller` |
```

- [ ] **Step 4: Run the full checks**

Run: `timeout 300 node --test evals/controller/tests/*.test.mjs`
Expected: PASS, 19 tests.
Run: `timeout 300 node evals/controller/pilot-report.mjs`
Expected: the header line, then `stage1: incomplete — 0 of 0 plans usable; opus@low costs 0.00x sonnet@high per dispatch; failures sonnet@high 0, opus@low 0`.
Run: `timeout 120 node scripts/validate-repository.mjs`
Expected: `Repository catalogs, manifests, versions, bundled links and the settings schema are valid.`
Run: `timeout 300 node --test tests/repository-layout.test.mjs tests/test-shards.test.mjs tests/ui-discovery.test.mjs`
Expected: 37 tests, 0 failing; one is skipped where `rg` is not installed.

- [ ] **Step 5: Commit**

```bash
git add evals/controller/pilot.tsv evals/controller/pilot-report.mjs evals/controller/README.md evals/controller/tests/pilot.test.mjs
git commit -m "feat(evals): report the controller pilot"
```
