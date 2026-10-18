# Controller Model Evaluation Harness Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: the skill the **Execution:** line names — dr-superpowers:subagent-driven-development for `subagent`, dr-superpowers:executing-plans for `inline`. Steps use checkbox (`- [ ]`) syntax for tracking.

> **External executors:** codex

**Goal:** Build `evals/controller/`, a harness that measures dforge's subagent-mode controller from Claude Code transcripts (Stage 1) and replays completed plans headless on any controller model and effort (Stage 2), so the owner can decide between Sonnet high, Opus low and Sonnet medium.

**Architecture:** Pure Node ES modules beside `evals/tiers/`, reusing its process-group runner (`run`), its headless-result classifier (`classify`) and its TSV helpers. Stage 1 reads `~/.claude/projects` transcripts, prices them per meter and counts tracking slips; `pilot-report.mjs` applies the Stage 1 rule. Stage 2 clones a case repository at its base commit with later history deleted, migrates it to dforge 4.0's layout, drives an auto run through `claude -p` while standing in for the cockpit between turns, grades the ledger and hidden tests, and `replay-report.mjs` applies the Stage 2 rule.

**Tech Stack:** Node 24 built-ins (`node:test`, `node:child_process`, `node:fs`), git, bash and jq through dforge's own scripts.

**Spec:** docs/superpowers/notes/2026-10-17-controller-model-eval.md

**Execution:** inline — `claude --model sonnet --effort high` — no task is heavy (highest total 4, no risk 3); every task carries an Executor line and is delegated, which raises the effort to high

**Parallelism:** sequential — the owner chose sequential execution on 2026-10-18

## Global Constraints

- Node built-ins only. Add no dependency and touch no `package.json` or lockfile.
- ES modules (`.mjs`), two-space indent, single quotes, semicolons, matching `evals/tiers/`.
- POSIX only, like `evals/tiers/`: the harness runs bash scripts and kills process groups.
- No test calls a real model, writes to the real `~/.claude/projects`, or reads or writes the real `~/.dforge`, `~/.dr-forge` or `~/.dr-superpowers`. Tests point `CONTROLLER_EVAL_*` at temporary directories and `CONTROLLER_EVAL_CLAUDE` at the stub.
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
  - `measureTranscript(source: string) -> Metrics`, where `Metrics` is `{ models: string[], efforts: string[], unpriced: string[], last: string, calls, input, write5m, write1h, read, output, cost, dispatches, sleeps, listAgents, monitors, nudges, seatMisses }` (all numbers except the first four fields).
  - `sumMetrics(list: Metrics[]) -> Metrics`; `sumMetrics([])` is all zeros.
- `lib/sessions.mjs`
  - `PROJECTS` (env `CONTROLLER_EVAL_PROJECTS`, default `~/.claude/projects`), `PLUGIN` (absolute path of `plugins/dforge`), `REPOS` (env `CONTROLLER_EVAL_REPOS`, default the directory holding this repository).
  - `transcripts(dir = PROJECTS) -> string[]`, `planSessions(slug, dir = PROJECTS) -> string[]`, `sessionFile(id, dir = PROJECTS) -> string | null`, `inFlight(file) -> number`.
  - `measureSessions(files) -> { sessions, controller: Metrics, subagents: Metrics, inFlight }`.
  - `flatten(measured) -> Row`, where `Row` is `{ sessions, models, efforts, calls, dispatches, controllerCost, subagentCost, costPerDispatch, sleeps, listAgents, monitors, nudges, seatMisses, inFlight, unpriced }` (`models`, `efforts` and `unpriced` joined with `+`; costs rounded to cents; `costPerDispatch` to thousandths, 0 with no dispatch).
- `lib/decide.mjs`: `BASE = 'sonnet@high'`, `CANDIDATE = 'opus@low'`, `CHEAPER = 'sonnet@medium'`, `MAX_RATIO = 1.5`, `BUSY = 20`, `MARGIN = 2`; `failures(row) -> number`; `passed(row) -> boolean`; `stage1(rows) -> { decision: 'incomplete' | 'keep' | 'switch' | 'ambiguous', ratio, failures }`; `stage2(rows) -> { decision: 'incomplete' | 'switch-opus-low' | 'adopt-sonnet-medium' | 'keep-sonnet-high', ratio, failures, passed }`. Row values may be strings.
- `lib/prepare.mjs`: `git(cwd, ...args) -> stdout` (throws on a nonzero exit); `repoOf(case) -> path`; `clone(case, dir, commit)`; `dforgePath(path) -> path`; `prepare(case, dir) -> { head, plan, spec, lintErrors, lint }`.
- `lib/drive.mjs`: `COMPACT_INSTRUCTIONS`, `RESUME`, `STALL_PROMPT`, `MAX_INVOCATIONS = 12`, `continuePrompt(plan)`, `startPrompt(plan)`, `autoRun(dir, session, args)`, `readState(dir)`, `replayEnv()`, `drive({ dir, plan, spec, model, effort, budget, seconds, out, maxInvocations }) -> Promise<{ sessions, invocations, compactions, stalls, cost, outcome, stopped }>`; `outcome` is one of `finished`, `stopped`, `budget`, `limit`, `timeout`, `cut`, `error`, `compact-failed`, `stalled`.
- `lib/grade.mjs`: `resultCheckout(dir, slug) -> { path, ledger }`; `hiddenTests(case, checkout, log) -> Promise<'pass' | 'fail'>`; `golden(case, dir) -> Promise<{ final, base }>`; `grade(case, dir, plan, out) -> Promise<{ checkout, tasks, complete, deferred, finalClean, tests }>`.
- A case (an entry of `cases.json`): `{ id, repo, plan, base, final, historical: { controller, subagents }, hidden: string[], tests: string[], cleanup: string[], seconds }`. A relative `repo` resolves against `REPOS`.
- `tests/fixture.mjs`: `PLAN`, `SPEC`, `git(dir, ...args)`, `fixture() -> { top, repo, base, final, kase, stub }` (sets `CONTROLLER_EVAL_CLAUDE` and `STUB_DIR` to the stub), `modes(stub, ...list)`.
- `tests/stub-claude.mjs` modes: `finish`, `stop`, `compact-due`, `compacted`, `clear-due`, `stall`, `limit`, `budget`; each call is logged to `$STUB_DIR/calls.log` as `{ mode, args, cwd, env: { mds, sandbox, noImport, configDir, session } }`.
- `pilot.tsv` columns: `plan repo arm note` (tab-separated).
- `results/replay.tsv` columns: `rep case arm outcome stopped invocations stalls compactions tasks complete deferred finalClean tests sessions calls dispatches controllerCost subagentCost costPerDispatch cliCost sleeps listAgents monitors nudges seatMisses inFlight unpriced seconds`.

## Assumptions (evidence)

- Transcript records: an assistant record carries `message.id`, `message.model`, `message.usage` with a `cache_creation` split into `ephemeral_5m_input_tokens` and `ephemeral_1h_input_tokens`, and a record-level `effort`; one message spans several records under one id. Observed in `~/.claude/projects/-root-repositories-darkraise-ai-plugins/59a902c2-4774-489f-b450-3d85738445e0.jsonl` on 2026-10-18.
- The code in Tasks 1 and 2 reproduces the note's recorded costs exactly when run on this machine's transcripts (2026-10-18, scratch worktree): `2026-10-06-enrichment-and-jobs-residuals-8` $2.22 controller and $4.69 subagents, `2026-10-17-m1-repository-tooling` $4.78 and $5.27, `2026-10-13-dr-forge-auto-run` $7.76 and $16.46. Matching on the plan name alone over-counted (8 sessions and $40.90 for the second), which is why `planSessions` requires a per-task script run on the plan.
- All code and tests in this plan were run in a scratch worktree of `main` at `38b20f6` on 2026-10-18: 40 harness tests pass, `node scripts/validate-repository.mjs` passes, and `tests/repository-layout.test.mjs`, `tests/test-shards.test.mjs` and `tests/ui-discovery.test.mjs` pass (36 tests).
- Headless CLI (Claude Code 2.1.302, probe on 2026-10-18 with Haiku, under $0.01): `claude -p --session-id <id> --plugin-dir plugins/dforge --setting-sources project` loads `dforge` 4.0.0 and its `dforge:` skills; `claude -p --resume <id> "/compact <text>"` exits 0 with `is_error: false` and writes a `compact_boundary` record.
- The case plans sit under `docs/superpowers/`; dforge 4.0's `plan-lint` resolves docs under `docs/dforge/` and reports `Spec path does not exist` for all three. After `scripts/dforge-migrate`, all three lint with 0 errors (run 2026-10-18).
- `scripts/dforge-migrate` moves `~/.dr-forge` and `~/.dr-superpowers` when they exist (`plugins/dforge/scripts/dforge-migrate:325-341`), and `~/.dr-forge` exists on this machine; `prepare` runs it under an empty `HOME`, and a test fails without that guard (checked 2026-10-18).
- Loading dforge 4.0 imports `~/.dr-forge/config.json` into `~/.dforge/config.json` unless `DFORGE_NO_IMPORT` is set (`plugins/dforge/scripts/lib/dforge-config.mjs:276`); the 2026-10-18 probe created `~/.dforge/config.json` that way.
- Auto-run state is `<checkout>/.dforge/sdd/auto-run.json` (`plugins/dforge/scripts/lib/auto-run.sh:25-29`); `rebind`, `resumed` and `compacted` are at `:212-220`. The cockpit's stage driver and prompt texts are `plugins/dforge/hooks/cockpit/register.tsx:2317-2377` and `:116-137`.
- `inflight_scan TRANSCRIPT` prints one line per launch still running (`plugins/dforge/scripts/lib/in-flight.sh:18-20`).
- The ledger is `<checkout>/.dforge/sdd/<plan name without .md>/progress.md` (`plugins/dforge/scripts/lib/plan.sh:349`); a clean final review writes `Final review: clean (…)` (`plugins/dforge/skills/subagent-driven-development/SKILL.md:336`).
- `review-route` prints `review-seat <scope> primary=<seat> fallback=<seat|-> reason=<why>` (`plugins/dforge/scripts/review-route:19-20`). Some judge dispatches are made without a route (`plugins/dforge/skills/subagent-driven-development/SKILL.md:444-448`), so a seat miss counts only a route that never reached its seat.
- dforge defaults are `finishAction: ask` and `darkmemEnabled: false` (`plugins/dforge/config/schema.mjs:130-131`, `:160-161`); `dforge-config get` printed `false` and `ask` on 2026-10-18.
- Running as root, `--permission-mode bypassPermissions` needs `IS_SANDBOX=1` (project memory `driving-nested-claude-smoke-runs.md`, from a smoke run on 2026-10-13).
- `claude`, `pnpm`, `go`, `dotnet` and `jq` resolve on `PATH` in a non-interactive bash (`command -v`, 2026-10-18).
- Interpretations of the note (it leaves these open): Stage 1 is `ambiguous` when Opus low has fewer failures than Sonnet high but by less than 2, or leaves more plans unfinished; a run counts one busy wait at 20 or more `sleep` and ListAgents calls; Stage 2 "passes the same tests" means Opus low passes every case Sonnet high passes; Stage 1 reads a plan as complete from its repository's `completed.md` rather than from ledger lines, since a finished plan's worktree and ledger may be gone; Stage 2 replays in a clone with later history deleted rather than a worktree of the source repository, so a replay never adds refs or worktrees to it.
- Unverified on purpose: the golden checks of the three cases and the behavior of dforge's Stop hook and cockpit mod under `claude -p` need the real case toolchains or a paid run. The README makes `golden` the first Stage 2 step, and the driver records any ending it does not expect as a stall, a stop or an error rather than guessing.

## Task index

1. Transcript metrics
2. Plan sessions and the measure command
3. Decision rules
4. Stage 1 pilot report
5. Case preparation
6. Replay driver
7. Replay grader
8. Replay command and cases
9. Stage 2 report and README

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

test('an unlisted model is named and left unpriced; a synthetic one is ignored', () => {
  const m = measureTranscript(jsonl([
    said('msg_a', 'claude-haiku-5-5', usage(10, 10)),
    said('msg_b', '<synthetic>', { input_tokens: 0, output_tokens: 0 }),
  ]));
  assert.deepEqual(m.unpriced, ['claude-haiku-5-5']);
  assert.equal(m.cost, 0);
  assert.deepEqual(m.models, ['claude-haiku-5-5']);
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

test('a routed review that never reaches its seat is a seat miss', () => {
  const route = (id, primary, fallback) => [said(`m${id}`, 'claude-sonnet-5-5', usage(1, 1), [use(id, 'Bash', { command: `bash /p/scripts/review-route plan.md --task ${id}` })]), result(id, `review-seat task=${id} primary=${primary} fallback=${fallback} reason=band`)];
  const call = (id, input, name = 'Agent') => said(`c${id}`, 'claude-sonnet-5-5', usage(1, 1), [use(id, name, input)]);
  const m = measureTranscript(jsonl([
    call('early', { subagent_type: 'dforge:judge-opus' }),
    ...route('r1', 'dforge:judge-sonnet-high', '-'),
    call('a1', { subagent_type: 'dforge:impl-sonnet-low' }),
    call('a2', { subagent_type: 'dforge:judge-sonnet-high' }),
    ...route('r2', 'codex:light', 'dforge:judge-opus'),
    call('b1', { command: 'bash /p/scripts/run-codex-review.sh --kind code' }, 'Bash'),
    ...route('r3', 'codex:light', 'dforge:judge-opus'),
    call('b2', { subagent_type: 'dforge:judge-opus' }),
    call('b3', { subagent_type: 'dforge:judge-opus' }),
    ...route('r4', 'dforge:judge-opus', '-'),
    call('c1', { subagent_type: 'dforge:judge-sonnet-high' }),
  ]));
  // r1, r2 and r3 reached their seats (r3 through its fallback); b3 is an
  // unrouted confirmation; r4 went to the wrong judge.
  assert.equal(m.seatMisses, 1);
});

test('sumMetrics adds counts and merges names', () => {
  const a = measureTranscript(jsonl([said('msg_a', 'claude-sonnet-5-5', usage(100, 10))]));
  const b = measureTranscript(jsonl([said('msg_b', 'claude-opus-5-5', usage(100, 10), [], 'low'), typed('anything still running?')]));
  const s = sumMetrics([a, b]);
  assert.equal(s.calls, 2);
  assert.equal(s.nudges, 1);
  assert.ok(Math.abs(s.cost - (a.cost + b.cost)) < 1e-12);
  assert.deepEqual(s.efforts, ['high', 'low']);
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
// What an owner types when the controller has lost track of its background work.
const NUDGE = /check (the )?status|still running|anything (still )?running/i;
const SLEEP = /^\s*sleep\s+[\d.]+\s*;?\s*$/;
const SEAT = /^review-seat .* primary=(\S+) fallback=(\S+)/gm;
const isAgent = use => use.name === 'Agent' || use.name === 'Task';

export function priceOf(model) {
  const key = Object.keys(PRICES).find(k => model === k || model.startsWith(`${k}-`));
  return key === undefined ? null : PRICES[key];
}

function textOf(content) {
  if (typeof content === 'string') return content;
  if (Array.isArray(content)) return content.map(c => (typeof c?.text === 'string' ? c.text : '')).join('\n');
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
    if (r?.type === 'assistant' && m?.id && m.usage) {
      usage.set(m.id, { model: m.model ?? '', usage: m.usage });
      if (m.model && !m.model.startsWith('<')) models.add(m.model);
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

  const out = { models: [...models].sort(), efforts: [...efforts].sort(), unpriced: [], last, calls: usage.size };
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

  let dispatches = 0, sleeps = 0, listAgents = 0, monitors = 0;
  const routes = [];
  const reviews = [];
  for (const use of uses.values()) {
    const cmd = use.name === 'Bash' ? String(use.input?.command ?? '') : '';
    if (isAgent(use) || /run-codex-(task|review)\.sh/.test(cmd)) dispatches++;
    if (SLEEP.test(cmd)) sleeps++;
    if (use.name === 'ListAgents') listAgents++;
    if (use.name === 'Monitor') monitors++;
    if (/run-codex-review\.sh/.test(cmd)) reviews.push({ at: reviews.length + routes.length, seat: 'codex' });
    else if (isAgent(use)) reviews.push({ at: reviews.length + routes.length, seat: String(use.input?.subagent_type ?? '') });
    if (/review-route/.test(cmd)) {
      for (const hit of (results.get(use.id) ?? '').matchAll(SEAT)) routes.push({ at: reviews.length + routes.length, primary: hit[1], fallback: hit[2] });
    }
  }
  // A route is kept when a later dispatch went to its seat: the printed
  // primary, or for a Codex primary a Codex run or the printed fallback.
  // Unrouted judge dispatches (a header amendment's confirmation) are not
  // misses, so only routes that never reached their seat are counted.
  let seatMisses = 0;
  const used = new Set();
  for (const route of routes) {
    const fits = r => (route.primary.startsWith('codex:') ? r.seat === 'codex' || r.seat === route.fallback : r.seat === route.primary);
    const hit = reviews.find(r => r.at > route.at && !used.has(r) && fits(r));
    if (hit === undefined) seatMisses++;
    else used.add(hit);
  }
  return { ...out, dispatches, sleeps, listAgents, monitors, nudges, seatMisses };
}

// sumMetrics LIST — the metrics of several transcripts added together.
export function sumMetrics(list) {
  const total = measureTranscript('');
  for (const m of list) {
    for (const k of COUNTS) total[k] += m[k];
    for (const k of ['models', 'efforts', 'unpriced']) total[k] = [...new Set([...total[k], ...m[k]])].sort();
    if (m.last > total.last) total.last = m.last;
  }
  return total;
}
```

In `scripts/test-all.mjs`, directly below the line that registers `evals/tiers/tests`, add:

```js
  // The controller-eval harness reuses the tier eval's process-group runner
  // and drives dforge's bash scripts, so it is POSIX only too.
  ...(process.platform === 'win32' ? [] : [[process.execPath, ['--test', ...readdirSync(resolve(root, 'evals/controller/tests')).filter(name => name.endsWith('.test.mjs')).map(name => `evals/controller/tests/${name}`)], 300]]),
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `timeout 300 node --test evals/controller/tests/transcript.test.mjs`
Expected: PASS, 6 tests.
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
- Produces: `lib/sessions.mjs` (Contracts) and `measure.mjs --plan SLUG | --session FILE ...`, which prints `{ files, ...Row }` as JSON and exits 0, 1 when no session matches, 2 on bad usage.

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
import { flatten, inFlight, measureSessions, planSessions, sessionFile } from '../lib/sessions.mjs';

const top = mkdtempSync(join(tmpdir(), 'controller-sessions-'));
after(() => rmSync(top, { recursive: true, force: true }));
const usage = { input_tokens: 0, cache_read_input_tokens: 1000000, output_tokens: 0 };
const said = (id, content, model = 'claude-sonnet-5-5') => ({ type: 'assistant', effort: 'high', message: { id, model, usage, content } });
const skill = name => said(`s-${name}`, [{ type: 'tool_use', id: `u-${name}`, name: 'Skill', input: { skill: name } }]);
const brief = slug => said(`b-${slug}`, [{ type: 'tool_use', id: `u-${slug}`, name: 'Bash', input: { command: `bash /p/scripts/task-brief docs/plans/${slug}.md 1` } }]);
const launch = [
  said('l1', [{ type: 'tool_use', id: 'bg', name: 'Bash', input: { command: 'npm test', run_in_background: true } }]),
  { type: 'user', message: { content: [{ type: 'tool_result', tool_use_id: 'bg', content: 'Command running in background with ID: bash_1' }] } },
];
const write = (path, records) => { mkdirSync(join(path, '..'), { recursive: true }); writeFileSync(path, records.map(r => JSON.stringify(r)).join('\n') + '\n'); };

write(join(top, 'proj-a/s1.jsonl'), [skill('dforge:subagent-driven-development'), brief('2026-10-18-alpha'), ...launch]);
write(join(top, 'proj-a/s1/subagents/agent-x.jsonl'), [said('x1', [], 'claude-opus-5-5')]);
write(join(top, 'proj-a/s2.jsonl'), [brief('2026-10-18-alpha')]);
write(join(top, 'proj-b/s3.jsonl'), [skill('dr-superpowers:subagent-driven-development'), brief('2026-10-18-beta')]);
write(join(top, 'proj-b/s4.jsonl'), [skill('dr-superpowers:subagent-driven-development'), brief('2026-10-18-alpha')]);
write(join(top, 'proj-b/s5.jsonl'), [skill('dforge:subagent-driven-development'), brief('2026-10-18-beta'), said('r1', [{ type: 'tool_use', id: 'cat', name: 'Bash', input: { command: 'cat docs/plans/2026-10-18-alpha.md' } }])]);

test('planSessions finds the controller sessions that ran a task script on the plan', () => {
  assert.deepEqual(planSessions('2026-10-18-alpha', top).map(f => f.slice(top.length)).sort(), ['/proj-a/s1.jsonl', '/proj-b/s4.jsonl']);
  assert.deepEqual(planSessions('2026-10-18-gamma', top), []);
  assert.deepEqual(planSessions('x', join(top, 'missing')), []);
});

test('sessionFile finds a transcript by session id', () => {
  assert.equal(sessionFile('s3', top), join(top, 'proj-b/s3.jsonl'));
  assert.equal(sessionFile('nope', top), null);
});

test('inFlight counts launches with no finished notification', () => {
  assert.equal(inFlight(join(top, 'proj-a/s1.jsonl')), 1);
  assert.equal(inFlight(join(top, 'proj-b/s3.jsonl')), 0);
});

test('measureSessions sums controllers and subagents, and flatten rounds the costs', () => {
  const row = flatten(measureSessions([join(top, 'proj-a/s1.jsonl'), join(top, 'proj-b/s4.jsonl')]));
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
  const ok = run('--plan', '2026-10-18-beta');
  assert.equal(ok.status, 0, ok.stderr);
  assert.equal(JSON.parse(ok.stdout).sessions, 2);
  assert.equal(run('--plan', '2026-10-18-gamma').status, 1);
  assert.equal(run().status, 2);
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `timeout 300 node --test evals/controller/tests/sessions.test.mjs`
Expected: FAIL with `ERR_MODULE_NOT_FOUND` for `lib/sessions.mjs`.

- [ ] **Step 3: Write the implementation**

Create `evals/controller/lib/sessions.mjs`:

```js
import { existsSync, readFileSync, readdirSync, statSync } from 'node:fs';
import { homedir } from 'node:os';
import { basename, dirname, join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { measureTranscript, sumMetrics } from './transcript.mjs';

export const PROJECTS = process.env.CONTROLLER_EVAL_PROJECTS ?? join(homedir(), '.claude/projects');
export const PLUGIN = fileURLToPath(new URL('../../../plugins/dforge', import.meta.url));
// A case or pilot repository given by a relative path is a sibling of this one.
export const REPOS = process.env.CONTROLLER_EVAL_REPOS ?? fileURLToPath(new URL('../../../..', import.meta.url));

// transcripts [DIR] — every main-session transcript in DIR's project folders.
// Subagent transcripts sit one level deeper and are not listed.
export function transcripts(dir = PROJECTS) {
  if (!existsSync(dir)) return [];
  return readdirSync(dir).flatMap(project => {
    const folder = join(dir, project);
    if (!statSync(folder).isDirectory()) return [];
    return readdirSync(folder).filter(name => name.endsWith('.jsonl')).map(name => join(folder, name));
  });
}

// planSessions SLUG [DIR] — the controller sessions of the plan whose file is
// SLUG.md: sessions that invoked subagent-driven-development and ran a
// per-task script on that plan. A later plan's sessions often name an earlier
// plan without executing it. Oldest first.
export function planSessions(slug, dir = PROJECTS) {
  return transcripts(dir)
    .filter(file => {
      const text = readFileSync(file, 'utf8');
      if (!/"skill":"[^"]*subagent-driven-development"/.test(text) || !text.includes(`${slug}.md`)) return false;
      return text.split('\n').some(line => line.includes('"name":"Bash"') && line.includes(`${slug}.md`) && /task-brief|review-route|review-package/.test(line));
    })
    .sort((a, b) => statSync(a).mtimeMs - statSync(b).mtimeMs);
}

// sessionFile ID [DIR] — the main transcript of session ID, or null.
export function sessionFile(id, dir = PROJECTS) {
  return transcripts(dir).find(file => basename(file, '.jsonl') === id) ?? null;
}

// inFlight FILE — the background launches FILE's session left running, as
// scripts/in-flight counts them.
export function inFlight(file) {
  const r = spawnSync('bash', ['-c', '. "$1/scripts/lib/in-flight.sh"; inflight_scan "$2"', 'in-flight', PLUGIN, file], { encoding: 'utf8' });
  if (r.status !== 0) throw new Error(`inflight_scan ${file}: ${r.stderr.trim()}`);
  return r.stdout.split('\n').filter(Boolean).length;
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
// node evals/controller/measure.mjs --plan SLUG | --session FILE [FILE ...]
// Prints the controller metrics of a plan's controller sessions, or of the
// transcripts named, as one JSON object. Reads only; calls no model.
import { flatten, measureSessions, planSessions } from './lib/sessions.mjs';

const [flag, ...rest] = process.argv.slice(2);
let files;
if (flag === '--plan' && rest.length === 1) files = planSessions(rest[0]);
else if (flag === '--session' && rest.length > 0) files = rest;
else {
  console.error('usage: measure.mjs --plan SLUG | --session FILE [FILE ...]');
  process.exit(2);
}
if (files.length === 0) {
  console.error(`measure: no controller session found for ${rest[0]}`);
  process.exit(1);
}
console.log(JSON.stringify({ files, ...flatten(measureSessions(files)) }, null, 2));
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `timeout 300 node --test evals/controller/tests/transcript.test.mjs evals/controller/tests/sessions.test.mjs`
Expected: PASS, 11 tests.
Run: `timeout 300 node evals/controller/measure.mjs --plan 2026-10-13-dr-forge-auto-run | grep -E '"(controllerCost|subagentCost)"'`
Expected, on the owner's machine where those transcripts exist: `"controllerCost": 7.76,` and `"subagentCost": 16.46,`. Where they do not exist, the command prints `measure: no controller session found` and exits 1; record that and continue.

- [ ] **Step 5: Commit**

```bash
git add evals/controller/lib/sessions.mjs evals/controller/measure.mjs evals/controller/tests/sessions.test.mjs
git commit -m "feat(evals): find and measure a plan's sessions"
```

### Task 3: Decision rules

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
import { failures, passed, stage1, stage2 } from '../lib/decide.mjs';

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

const run = (c, arm, cost, extra = {}) => ({ case: c, arm, outcome: 'finished', complete: '5', tasks: '5', finalClean: 'yes', tests: 'pass', controllerCost: String(cost), dispatches: '10', inFlight: '0', seatMisses: '0', nudges: '0', sleeps: '0', listAgents: '0', ...extra });
const grid = (opus = {}, medium = {}, base = {}) => ['a', 'b'].flatMap(c => [run(c, 'sonnet@high', 2, base[c]), run(c, 'opus@low', 2.8, opus[c]), run(c, 'sonnet@medium', 1.6, medium[c])]);

test('passed needs every task complete, a clean final review and passing tests', () => {
  assert.equal(passed(run('a', 'x', 1)), true);
  assert.equal(passed(run('a', 'x', 1, { complete: '4' })), false);
  assert.equal(passed(run('a', 'x', 1, { tests: 'fail' })), false);
  assert.equal(passed(run('a', 'x', 1, { finalClean: 'no' })), false);
  assert.equal(passed(run('a', 'x', 1, { complete: '0', tasks: '0' })), false);
});

test('stage2 is incomplete until every arm ran every case', () => {
  assert.equal(stage2(grid().slice(0, 5)).decision, 'incomplete');
  assert.equal(stage2([]).decision, 'incomplete');
});

test('stage2 switches to Opus low only when it slips less, passes as much and costs at most 1.5x', () => {
  assert.equal(stage2(grid({}, { a: { inFlight: 2 } }, { a: { nudges: 1 } })).decision, 'switch-opus-low');
  assert.equal(stage2(grid({ b: { tests: 'fail' } }, { a: { inFlight: 2 } }, { a: { nudges: 1 } })).decision, 'keep-sonnet-high');
  assert.equal(stage2(grid({ a: { controllerCost: '3.5' }, b: { controllerCost: '3.5' } }, { a: { inFlight: 2 } }, { a: { nudges: 1 } })).decision, 'keep-sonnet-high');
});

test('stage2 adopts Sonnet medium when it matches the base, else keeps the base', () => {
  const r = stage2(grid());
  assert.equal(r.decision, 'adopt-sonnet-medium');
  assert.deepEqual(r.passed['sonnet@high'], ['a', 'b']);
  assert.equal(stage2(grid({}, { b: { finalClean: 'no' } })).decision, 'keep-sonnet-high');
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `timeout 300 node --test evals/controller/tests/decide.test.mjs`
Expected: FAIL with `ERR_MODULE_NOT_FOUND` for `lib/decide.mjs`.

- [ ] **Step 3: Write the implementation**

Create `evals/controller/lib/decide.mjs`:

```js
// The decision rules of docs/superpowers/notes/2026-10-17-controller-model-eval.md.
// Rows may come from a TSV, so every number is read through Number().

export const BASE = 'sonnet@high';
export const CANDIDATE = 'opus@low';
export const CHEAPER = 'sonnet@medium';
// The most an Opus controller may cost per dispatch, as a multiple of the base.
export const MAX_RATIO = 1.5;
// Sleep and ListAgents calls in one run at which the run counts as a busy wait.
export const BUSY = 20;
// How many more tracking failures the base needs in Stage 1 before the
// difference is read as more than noise.
export const MARGIN = 2;

const num = v => Number(v ?? 0);

// failures ROW — the tracking and protocol slips of one plan or run: launches
// left running, routed reviews that missed their seat, owner nudges, and one
// for a busy wait.
export function failures(row) {
  return num(row.inFlight) + num(row.seatMisses) + num(row.nudges) + (num(row.sleeps) + num(row.listAgents) >= BUSY ? 1 : 0);
}

const total = (rows, key) => rows.reduce((sum, r) => sum + num(r[key]), 0);
const slips = rows => rows.reduce((sum, r) => sum + failures(r), 0);
const perDispatch = rows => total(rows, 'controllerCost') / Math.max(1, total(rows, 'dispatches'));

// stage1 ROWS — the production A/B: rows { arm, complete: yes|no, ... }.
// keep when Opus costs over MAX_RATIO per dispatch or fails as often; switch
// when the base fails at least MARGIN more often and Opus left no more plans
// unfinished; ambiguous otherwise; incomplete until each arm has 3 plans.
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

// passed ROW — the run finished every task, its final review is clean and the
// hidden tests pass.
export function passed(row) {
  return row.tests === 'pass' && row.finalClean === 'yes' && num(row.complete) === num(row.tasks) && num(row.tasks) > 0;
}

// stage2 ROWS — the controlled replay: rows { case, arm, ... } of one
// repetition. Switch to Opus low when it slips less, passes every case the
// base passes, and costs at most MAX_RATIO per dispatch; else adopt Sonnet
// medium when it slips no more and passes every case the base passes; else
// keep the base. Incomplete until every arm has run every case.
export function stage2(rows) {
  const cases = [...new Set(rows.map(r => r.case))].sort();
  const of = arm => rows.filter(r => r.arm === arm);
  const wins = arm => of(arm).filter(passed).map(r => r.case).sort();
  const facts = {
    ratio: perDispatch(of(CANDIDATE)) / Math.max(1e-9, perDispatch(of(BASE))),
    failures: Object.fromEntries([BASE, CANDIDATE, CHEAPER].map(arm => [arm, slips(of(arm))])),
    passed: Object.fromEntries([BASE, CANDIDATE, CHEAPER].map(arm => [arm, wins(arm)])),
  };
  const ran = arm => cases.every(c => of(arm).some(r => r.case === c));
  if (cases.length === 0 || ![BASE, CANDIDATE, CHEAPER].every(ran)) return { decision: 'incomplete', ...facts };
  const covers = arm => wins(BASE).every(c => wins(arm).includes(c));
  if (slips(of(CANDIDATE)) < slips(of(BASE)) && covers(CANDIDATE) && facts.ratio <= MAX_RATIO) return { decision: 'switch-opus-low', ...facts };
  if (slips(of(CHEAPER)) <= slips(of(BASE)) && covers(CHEAPER)) return { decision: 'adopt-sonnet-medium', ...facts };
  return { decision: 'keep-sonnet-high', ...facts };
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `timeout 300 node --test evals/controller/tests/decide.test.mjs`
Expected: PASS, 8 tests.

- [ ] **Step 5: Commit**

```bash
git add evals/controller/lib/decide.mjs evals/controller/tests/decide.test.mjs
git commit -m "feat(evals): add controller decision rules"
```

### Task 4: Stage 1 pilot report

**Files:**
- Create: `evals/controller/pilot.tsv`
- Create: `evals/controller/pilot-report.mjs`
- Test: `evals/controller/tests/pilot.test.mjs`

**Interfaces:**
- Consumes: `lib/sessions.mjs` and `lib/decide.mjs` (Contracts); `readTsv` from `evals/tiers/lib/results.mjs`.
- Produces: `pilot.tsv` (Contracts) and `pilot-report.mjs`, which prints a header, one row per plan and a `stage1: …` line; exit 2 on an arm other than `sonnet@high` or `opus@low`.

**Items:** 3

**Implementer:** dr-superpowers:impl-sonnet-medium
**Executor:** codex gpt-6.1-sol / medium
**Evaluation:** files 1 - spec 0 - coupling 2 - risk 0 = 3

- [ ] **Step 1: Write the failing test**

Create `evals/controller/tests/pilot.test.mjs`:

```js
import assert from 'node:assert/strict';
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { after, test } from 'node:test';

const top = mkdtempSync(join(tmpdir(), 'controller-pilot-'));
after(() => rmSync(top, { recursive: true, force: true }));
const projects = join(top, 'projects');
const data = join(top, 'data');
const repo = join(top, 'repos/app');

const usage = { input_tokens: 0, cache_read_input_tokens: 1000000, output_tokens: 0 };
const session = (slug, effort) => [
  { type: 'assistant', effort, message: { id: `s-${slug}`, model: 'claude-sonnet-5-5', usage, content: [{ type: 'tool_use', id: 'u1', name: 'Skill', input: { skill: 'dforge:subagent-driven-development' } }] } },
  { type: 'assistant', effort, message: { id: `b-${slug}`, model: 'claude-sonnet-5-5', usage, content: [{ type: 'tool_use', id: 'u2', name: 'Bash', input: { command: `bash /p/scripts/task-brief docs/plans/${slug}.md 1` } }] } },
  { type: 'user', message: { content: 'check status please' } },
].map(r => JSON.stringify(r)).join('\n') + '\n';
const write = (path, text) => { mkdirSync(join(path, '..'), { recursive: true }); writeFileSync(path, text); };

write(join(projects, 'p/one.jsonl'), session('2026-10-18-one', 'high'));
write(join(projects, 'p/two.jsonl'), session('2026-10-18-two', 'low'));
write(join(repo, 'docs/plans/completed.md'), '- 2026-10-18 `docs/plans/2026-10-18-one.md` — merged\n');
spawnSync('git', ['init', '-q', repo]);
spawnSync('git', ['-C', repo, 'add', '-A']);
spawnSync('git', ['-C', repo, '-c', 'user.name=t', '-c', 'user.email=t@example.invalid', 'commit', '-q', '-m', 'init']);

const report = rows => {
  write(join(data, 'pilot.tsv'), ['plan\trepo\tarm\tnote', ...rows].join('\n') + '\n');
  return spawnSync(process.execPath, ['evals/controller/pilot-report.mjs'], { encoding: 'utf8', env: { ...process.env, CONTROLLER_EVAL_PROJECTS: projects, CONTROLLER_EVAL_DATA: data, CONTROLLER_EVAL_REPOS: join(top, 'repos') } });
};

test('pilot-report prints a row per plan and the Stage 1 decision', () => {
  const r = report([
    'docs/plans/2026-10-18-one.md\tapp\tsonnet@high\t-',
    `docs/plans/2026-10-18-two.md\t${repo}\topus@low\t-`,
    'docs/plans/2026-10-18-three.md\tapp\topus@low\tnot run yet',
  ]);
  assert.equal(r.status, 0, r.stderr);
  const lines = r.stdout.trim().split('\n');
  assert.equal(lines.length, 5);
  const [one, two, three] = lines.slice(1, 4).map(l => l.split('\t'));
  assert.deepEqual(one.slice(0, 5), ['2026-10-18-one', 'sonnet@high', 'yes', '1', 'claude-sonnet-5-5']);
  assert.deepEqual(two.slice(0, 4), ['2026-10-18-two', 'opus@low', 'no', '1']);
  assert.equal(two[10], '1');
  assert.deepEqual(three.slice(0, 4), ['2026-10-18-three', 'opus@low', 'no', '0']);
  assert.match(lines[4], /^stage1: incomplete — opus@low costs .*x sonnet@high per dispatch; failures sonnet@high 1, opus@low 1$/);
});

test('pilot-report refuses an arm the pilot does not run', () => {
  const r = report(['docs/plans/2026-10-18-one.md\tapp\tsonnet@medium\t-']);
  assert.equal(r.status, 2);
  assert.match(r.stderr, /arm must be sonnet@high or opus@low/);
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `timeout 300 node --test evals/controller/tests/pilot.test.mjs`
Expected: FAIL: both tests report a nonzero exit, because `pilot-report.mjs` does not exist.

- [ ] **Step 3: Write the implementation**

Create `evals/controller/pilot.tsv` holding only its tab-separated header:

```bash
printf 'plan\trepo\tarm\tnote\n' > evals/controller/pilot.tsv
```

Create `evals/controller/pilot-report.mjs`:

```js
// node evals/controller/pilot-report.mjs
// Measures every plan pilot.tsv lists and prints one row per plan, then the
// Stage 1 decision. Reads only; calls no model.
import { basename, isAbsolute, join, resolve } from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { readTsv } from '../tiers/lib/results.mjs';
import { BASE, CANDIDATE, stage1 } from './lib/decide.mjs';
import { REPOS, flatten, measureSessions, planSessions } from './lib/sessions.mjs';

const HERE = fileURLToPath(new URL('.', import.meta.url));
const DATA = process.env.CONTROLLER_EVAL_DATA ?? HERE;
const COLUMNS = ['plan', 'arm', 'complete', 'sessions', 'models', 'efforts', 'controllerCost', 'subagentCost', 'dispatches', 'costPerDispatch', 'nudges', 'inFlight', 'seatMisses', 'sleeps', 'listAgents', 'monitors', 'unpriced'];

// A plan is complete once a completed.md in its repository lists it.
const isComplete = (repo, slug) => spawnSync('git', ['-C', repo, 'grep', '-q', '-F', `${slug}.md`, '--', '*completed.md']).status === 0;

const rows = [];
for (const entry of readTsv(join(DATA, 'pilot.tsv'))) {
  if (entry.arm !== BASE && entry.arm !== CANDIDATE) {
    console.error(`pilot-report: ${entry.plan}: arm must be ${BASE} or ${CANDIDATE}, not ${entry.arm}`);
    process.exit(2);
  }
  const slug = basename(entry.plan, '.md');
  const repo = isAbsolute(entry.repo) ? entry.repo : resolve(REPOS, entry.repo);
  rows.push({ plan: slug, arm: entry.arm, complete: isComplete(repo, slug) ? 'yes' : 'no', ...flatten(measureSessions(planSessions(slug))) });
}
console.log(COLUMNS.join('\t'));
for (const row of rows) console.log(COLUMNS.map(k => row[k]).join('\t'));
const r = stage1(rows.filter(row => row.sessions > 0));
console.log(`stage1: ${r.decision} — ${CANDIDATE} costs ${r.ratio.toFixed(2)}x ${BASE} per dispatch; failures ${BASE} ${r.failures[BASE]}, ${CANDIDATE} ${r.failures[CANDIDATE]}`);
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `timeout 300 node --test evals/controller/tests/pilot.test.mjs`
Expected: PASS, 2 tests.
Run: `timeout 300 node evals/controller/pilot-report.mjs`
Expected: the header line, then `stage1: incomplete — opus@low costs 0.00x sonnet@high per dispatch; failures sonnet@high 0, opus@low 0`.

- [ ] **Step 5: Commit**

```bash
git add evals/controller/pilot.tsv evals/controller/pilot-report.mjs evals/controller/tests/pilot.test.mjs
git commit -m "feat(evals): report the controller pilot"
```

### Task 5: Case preparation

**Files:**
- Create: `evals/controller/lib/prepare.mjs`
- Create: `evals/controller/tests/fixture.mjs`
- Test: `evals/controller/tests/prepare.test.mjs`

**Interfaces:**
- Consumes: `PLUGIN` and `REPOS` from `lib/sessions.mjs` (Contracts).
- Produces: `lib/prepare.mjs`, `tests/fixture.mjs` and the case shape (Contracts). The fixture already wires the stub `claude` that Task 6 creates; nothing in this task calls it.

**Items:** 3

**Implementer:** dr-superpowers:impl-sonnet-medium
**Executor:** codex gpt-6.1-sol / high
**Evaluation:** files 1 - spec 0 - coupling 2 - risk 1 = 4

- [ ] **Step 1: Write the fixture and the failing test**

Create `evals/controller/tests/fixture.mjs`:

```js
// A throwaway repository holding one case: a base commit with a spec and a
// two-task plan, and a final commit that carried the plan out, with a hidden
// test. Every replay test runs against it without a model call.
import { chmodSync, mkdirSync, mkdtempSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

// The case trees predate dforge 4.0, so the fixture uses the older docs root.
export const PLAN = 'docs/superpowers/plans/2026-10-18-demo.md';
export const SPEC = 'docs/superpowers/specs/2026-10-18-demo-design.md';

const PLAN_TEXT = `# Demo Implementation Plan

**Goal:** greet with hello

**Spec:** ${SPEC}

**Execution:** inline — \`claude --model sonnet --effort low\` — fixture

**Parallelism:** sequential — fixture

**Plan review:** 2026-10-18 — fixture

## Global Constraints

The skill under change is dr-forge:brainstorming.

## Contracts

None

## Assumptions (evidence)

None

## Task index

1. Greet
2. Notes

---

### Task 1: Greet

**Files:**
- Modify: \`src/greet.sh\`

**Implementer:** dr-superpowers:impl-sonnet-low
**Evaluation:** files 0 - spec 0 - coupling 0 - risk 0 = 0

### Task 2: Notes

**Files:**
- Create: \`notes.md\`

**Implementer:** \`dr-forge:impl-sonnet-low\`
**Evaluation:** files 0 - spec 0 - coupling 0 - risk 0 = 0
`;

export function git(dir, ...args) {
  const r = spawnSync('git', ['-c', 'user.name=fixture', '-c', 'user.email=fixture@example.invalid', ...args], { cwd: dir, encoding: 'utf8' });
  if (r.status !== 0) throw new Error(`git ${args.join(' ')}: ${r.stderr}`);
  return r.stdout.trim();
}

function put(dir, files) {
  for (const [path, text] of Object.entries(files)) {
    mkdirSync(dirname(join(dir, path)), { recursive: true });
    writeFileSync(join(dir, path), text);
  }
}

// fixture — { top, repo, base, final, kase, stub }: kase is the case
// definition. Points CONTROLLER_EVAL_CLAUDE at the stub, so call it before a
// replay runs.
export function fixture() {
  const top = mkdtempSync(join(tmpdir(), 'controller-replay-'));
  const stub = join(top, 'stub');
  mkdirSync(stub, { recursive: true });
  writeFileSync(join(stub, 'claude'), `#!/bin/sh\nexec "${process.execPath}" "${fileURLToPath(new URL('./stub-claude.mjs', import.meta.url))}" "$@"\n`);
  chmodSync(join(stub, 'claude'), 0o755);
  Object.assign(process.env, { CONTROLLER_EVAL_CLAUDE: join(stub, 'claude'), STUB_DIR: stub });
  const repo = join(top, 'repos/demo');
  mkdirSync(repo, { recursive: true });
  git(repo, 'init', '-q', '-b', 'main');
  put(repo, { [SPEC]: '# Demo design\n', [PLAN]: PLAN_TEXT, 'src/greet.sh': 'echo hi\n' });
  git(repo, 'add', '-A');
  git(repo, 'commit', '-q', '-m', 'docs: plan the demo');
  const base = git(repo, 'rev-parse', 'HEAD');
  put(repo, { 'src/greet.sh': 'echo hello\n', 'tests/hello.test.sh': '[ "$(bash src/greet.sh)" = hello ]\n' });
  git(repo, 'add', '-A');
  git(repo, 'commit', '-q', '-m', 'feat: greet with hello');
  const final = git(repo, 'rev-parse', 'HEAD');
  git(repo, 'tag', 'v1');
  git(repo, 'branch', 'feature');
  const kase = {
    id: 'demo', repo, plan: PLAN, base, final,
    historical: { controller: 1, subagents: 2 },
    hidden: ['tests/hello.test.sh'],
    tests: ['bash tests/hello.test.sh'],
    cleanup: ['true'],
    seconds: 60,
  };
  return { top, repo, base, final, kase, stub };
}

// modes STUB MODE... — the stub's replies, one per call; the last repeats.
export function modes(stub, ...list) {
  writeFileSync(join(stub, 'modes'), list.join('\n') + '\n');
  writeFileSync(join(stub, 'calls.log'), '');
}
```

Create `evals/controller/tests/prepare.test.mjs`:

```js
import assert from 'node:assert/strict';
import { existsSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { after, test } from 'node:test';
import { fixture, git, PLAN } from './fixture.mjs';
import { dforgePath, prepare, repoOf } from '../lib/prepare.mjs';

const fx = fixture();
after(() => rmSync(fx.top, { recursive: true, force: true }));
const dir = join(fx.top, 'work/demo');
const r = prepare(fx.kase, dir);

test('prepare clones the base with no later commit reachable', () => {
  assert.equal(git(dir, 'branch', '--show-current'), 'eval-base');
  assert.equal(git(dir, 'for-each-ref', '--format=%(refname)'), 'refs/heads/eval-base');
  assert.equal(git(dir, 'remote'), '');
  assert.notEqual(spawnSync('git', ['cat-file', '-e', `${fx.final}^{commit}`], { cwd: dir }).status, 0);
  assert.equal(git(dir, 'rev-parse', 'HEAD~1'), fx.base);
  assert.equal(r.head, git(dir, 'rev-parse', 'HEAD'));
  assert.equal(readFileSync(join(dir, 'src/greet.sh'), 'utf8'), 'echo hi\n');
});

test('prepare moves the clone to dforge 4.0 layout and commits it', () => {
  assert.equal(r.plan, 'docs/dforge/plans/2026-10-18-demo.md');
  assert.equal(r.spec, 'docs/dforge/specs/2026-10-18-demo-design.md');
  assert.equal(existsSync(join(dir, r.spec)), true);
  assert.equal(existsSync(join(dir, PLAN)), false);
  const plan = readFileSync(join(dir, r.plan), 'utf8');
  assert.match(plan, /^\*\*Implementer:\*\* dforge:impl-sonnet-low$/m);
  assert.doesNotMatch(plan, /dr-superpowers:|dr-forge:/);
  assert.equal(git(dir, 'status', '--porcelain'), '');
  assert.match(r.lint, /plan-lint: \d+ errors/);
  assert.equal(typeof r.lintErrors, 'number');
});

test('prepare never migrates the dforge homes of the caller', () => {
  const home = join(fx.top, 'home');
  mkdirSync(join(home, '.dr-forge'), { recursive: true });
  writeFileSync(join(home, '.dr-forge/config.json'), '{}\n');
  const saved = process.env.HOME;
  process.env.HOME = home;
  try {
    prepare(fx.kase, join(fx.top, 'work/home'));
  } finally {
    process.env.HOME = saved;
  }
  assert.equal(existsSync(join(home, '.dr-forge/config.json')), true);
  assert.equal(existsSync(join(home, '.dforge')), false);
});

test('dforgePath and repoOf', () => {
  assert.equal(dforgePath('docs/forge/plans/a.md'), 'docs/dforge/plans/a.md');
  assert.equal(dforgePath('docs/dforge/plans/a.md'), 'docs/dforge/plans/a.md');
  assert.equal(repoOf({ repo: '/abs/demo' }), '/abs/demo');
  assert.ok(repoOf({ repo: 'demo' }).endsWith('/demo'));
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `timeout 300 node --test evals/controller/tests/prepare.test.mjs`
Expected: FAIL with `ERR_MODULE_NOT_FOUND` for `lib/prepare.mjs`.

- [ ] **Step 3: Write the implementation**

Create `evals/controller/lib/prepare.mjs`:

```js
import { mkdirSync, mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, isAbsolute, join, resolve } from 'node:path';
import { spawnSync } from 'node:child_process';
import { PLUGIN, REPOS } from './sessions.mjs';

const IDENT = ['-c', 'user.name=controller-eval', '-c', 'user.email=controller-eval@example.invalid'];

export function git(cwd, ...args) {
  const r = spawnSync('git', args, { cwd, encoding: 'utf8', maxBuffer: 256 * 1024 * 1024 });
  if (r.status !== 0) throw new Error(`git ${args.join(' ')}: ${(r.stderr ?? '').trim()}`);
  return r.stdout;
}

export const repoOf = c => (isAbsolute(c.repo) ? c.repo : resolve(REPOS, c.repo));

// clone CASE DIR COMMIT — a clone of the case's repository in DIR on branch
// eval-base at COMMIT, with every other ref, the remote and every unreachable
// object gone, so no commit after COMMIT can be read from it.
export function clone(c, dir, commit) {
  rmSync(dir, { recursive: true, force: true });
  mkdirSync(dirname(dir), { recursive: true });
  git(dirname(dir), 'clone', '-q', '--no-local', repoOf(c), dir);
  git(dir, 'checkout', '-q', '-B', 'eval-base', commit);
  git(dir, 'remote', 'remove', 'origin');
  for (const ref of git(dir, 'for-each-ref', '--format=%(refname)').split('\n').filter(Boolean)) {
    if (ref !== 'refs/heads/eval-base') git(dir, 'update-ref', '-d', ref);
  }
  git(dir, 'reflog', 'expire', '--expire=now', '--all');
  git(dir, 'gc', '-q', '--prune=now');
}

// dforgePath PATH — where a docs path sits once the clone uses dforge 4.0's
// docs root.
export const dforgePath = path => path.replace(/^docs\/(superpowers|forge)\//, 'docs/dforge/');

// prepare CASE DIR — the case's base in DIR, ready for a replay: moved to
// dforge 4.0's layout by scripts/dforge-migrate, which also respells the
// active plan's agent prefixes, and committed. Returns { head, plan, spec,
// lintErrors, lint }: spec is the plan's Spec line, or null without one;
// lintErrors is -1 when plan-lint printed no summary.
export function prepare(c, dir) {
  clone(c, dir, c.base);
  if (spawnSync('git', ['cat-file', '-e', `${c.final}^{commit}`], { cwd: dir }).status === 0) {
    throw new Error(`${c.id}: ${c.final} is still reachable from the clone`);
  }
  // dforge-migrate also moves ~/.dr-superpowers and ~/.dr-forge; an empty
  // HOME keeps it inside the clone.
  const home = mkdtempSync(join(tmpdir(), 'controller-eval-home-'));
  const migrated = spawnSync('bash', [join(PLUGIN, 'scripts/dforge-migrate'), dir], { cwd: dir, encoding: 'utf8', env: { ...process.env, HOME: home } });
  rmSync(home, { recursive: true, force: true });
  if (migrated.status !== 0) throw new Error(`${c.id}: dforge-migrate: ${(migrated.stdout + migrated.stderr).trim()}`);
  git(dir, 'add', '-A');
  if (git(dir, 'status', '--porcelain') !== '') git(dir, ...IDENT, 'commit', '-q', '-m', 'eval: dforge 4.0 layout');
  const plan = dforgePath(c.plan);
  const spec = readFileSync(join(dir, plan), 'utf8').match(/^\*\*Spec:\*\*[ \t]*`?([^`\s]+)/m)?.[1];
  const lint = spawnSync('bash', [join(PLUGIN, 'scripts/plan-lint'), plan], { cwd: dir, encoding: 'utf8' });
  const summary = lint.stdout.match(/plan-lint: (\d+) errors/);
  return { head: git(dir, 'rev-parse', 'HEAD').trim(), plan, spec: spec === undefined ? null : dforgePath(spec), lintErrors: summary ? Number(summary[1]) : -1, lint: lint.stdout + lint.stderr };
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `timeout 300 node --test evals/controller/tests/prepare.test.mjs`
Expected: PASS, 4 tests. Then `ls /tmp | grep -c '^controller-'` prints `0`: the tests leave no temporary directory behind.

- [ ] **Step 5: Commit**

```bash
git add evals/controller/lib/prepare.mjs evals/controller/tests/fixture.mjs evals/controller/tests/prepare.test.mjs
git commit -m "feat(evals): prepare a replay case clone"
```

### Task 6: Replay driver

**Files:**
- Create: `evals/controller/lib/drive.mjs`
- Create: `evals/controller/tests/stub-claude.mjs`
- Test: `evals/controller/tests/drive.test.mjs`

**Interfaces:**
- Consumes: `prepare` (Task 5), `PLUGIN` (Task 2), `fixture` and `modes` (Task 5), `run` from `evals/tiers/lib/sh.mjs` and `classify` from `evals/tiers/lib/claude.mjs`.
- Produces: `lib/drive.mjs` and the stub modes (Contracts).

**Items:** 3

**Implementer:** dr-superpowers:impl-sonnet-medium
**Executor:** codex gpt-6.1-sol / high
**Evaluation:** files 1 - spec 0 - coupling 2 - risk 1 = 4

- [ ] **Step 1: Write the stub and the failing test**

Create `evals/controller/tests/stub-claude.mjs`:

```js
// Stands in for the `claude` CLI in the replay tests. Each call takes the next
// mode from $STUB_DIR/modes (the last one repeats), records its arguments and
// environment in $STUB_DIR/calls.log, changes the auto-run state in its
// working directory as a controller's turn would, and prints the JSON a
// headless run prints.
import { appendFileSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

const dir = process.env.STUB_DIR;
const list = readFileSync(join(dir, 'modes'), 'utf8').split('\n').filter(Boolean);
const mode = list[0];
if (list.length > 1) writeFileSync(join(dir, 'modes'), list.slice(1).join('\n') + '\n');
const args = process.argv.slice(2);
appendFileSync(join(dir, 'calls.log'), JSON.stringify({
  mode, args, cwd: process.cwd(),
  env: { mds: process.env.CLAUDE_CODE_DISABLE_CLAUDE_MDS, sandbox: process.env.IS_SANDBOX, noImport: process.env.DFORGE_NO_IMPORT, configDir: process.env.CLAUDE_CONFIG_DIR ?? null, session: process.env.CLAUDE_CODE_SESSION_ID ?? null },
}) + '\n');

const statePath = join(process.cwd(), '.dforge/sdd/auto-run.json');
const edit = change => writeFileSync(statePath, JSON.stringify({ ...JSON.parse(readFileSync(statePath, 'utf8')), ...change }));
const reply = (extra = {}) => console.log(JSON.stringify({ type: 'result', is_error: false, result: 'done', total_cost_usd: 1, num_turns: 3, modelUsage: { 'stub-model': {} }, ...extra }));

if (mode === 'finish') { edit({ active: false, stopped: null, pending: null }); reply(); }
else if (mode === 'stop') { edit({ active: false, stopped: 'tests failed at finishing', pending: null }); reply(); }
else if (mode === 'compact-due') { edit({ pending: 'compact' }); reply(); }
else if (mode === 'compacted') { reply({ total_cost_usd: 0.25 }); }
else if (mode === 'clear-due') { edit({ pending: 'clear', rebind: true, resumePrompt: 'RESUME FROM HANDOFF' }); reply(); }
else if (mode === 'stall') { reply(); }
else if (mode === 'limit') { reply({ is_error: true, result: "You've hit your usage limit", total_cost_usd: 0 }); process.exitCode = 1; }
else if (mode === 'budget') { reply({ is_error: true, subtype: 'error_max_budget_usd' }); process.exitCode = 1; }
else { console.error(`stub-claude: unknown mode ${mode}`); process.exitCode = 2; }
```

Create `evals/controller/tests/drive.test.mjs`:

```js
import assert from 'node:assert/strict';
import { readFileSync, rmSync } from 'node:fs';
import { join } from 'node:path';
import { after, test } from 'node:test';
import { fixture, modes } from './fixture.mjs';
import { prepare } from '../lib/prepare.mjs';
import { COMPACT_INSTRUCTIONS, drive, readState } from '../lib/drive.mjs';

const fx = fixture();
after(() => rmSync(fx.top, { recursive: true, force: true }));
const calls = () => readFileSync(join(fx.stub, 'calls.log'), 'utf8').trim().split('\n').map(line => JSON.parse(line));
const flag = (call, name) => call.args[call.args.indexOf(name) + 1];
let n = 0;
const replay = async (extra = {}) => {
  const dir = join(fx.top, `work/run${++n}`);
  const { plan, spec } = prepare(fx.kase, dir);
  const r = await drive({ dir, plan, spec, model: 'opus', effort: 'low', budget: 10, seconds: 60, out: join(dir, '..', `out${n}`), ...extra });
  return { dir, plan, r };
};

test('a run that finishes in one turn starts bound, on the arm, in a clean environment', async () => {
  modes(fx.stub, 'finish');
  const { dir, plan, r } = await replay();
  assert.equal(r.outcome, 'finished');
  assert.deepEqual([r.invocations, r.compactions, r.stalls, r.cost, r.sessions.length], [1, 0, 0, 1, 1]);
  const [first] = calls();
  assert.equal(flag(first, '--session-id'), r.sessions[0]);
  assert.deepEqual([flag(first, '--model'), flag(first, '--effort'), flag(first, '--setting-sources'), flag(first, '--max-budget-usd')], ['opus', 'low', 'project', '10.00']);
  assert.match(flag(first, '--plugin-dir'), /plugins\/dforge$/);
  assert.match(first.args.at(-1), new RegExp(`^Execute the plan ${plan} with the dforge:subagent-driven-development skill`));
  assert.deepEqual(first.env, { mds: '1', sandbox: '1', noImport: '1', configDir: null, session: null });
  const state = readState(dir);
  assert.equal(state.plan, plan);
  assert.equal(state.phase, 'execute');
});

test('a compaction is run, booked, and followed by the continue prompt', async () => {
  modes(fx.stub, 'compact-due', 'compacted', 'finish');
  const { dir, r } = await replay();
  assert.equal(r.outcome, 'finished');
  assert.deepEqual([r.invocations, r.compactions, r.cost], [2, 1, 2.25]);
  const [, compact, next] = calls();
  assert.equal(flag(compact, '--resume'), r.sessions[0]);
  assert.equal(compact.args.at(-1), `/compact ${COMPACT_INSTRUCTIONS}`);
  assert.equal(flag(next, '--resume'), r.sessions[0]);
  assert.match(next.args.at(-1), /^Continue the auto run: run `bash .*\/scripts\/auto-run after-compact` first/);
  assert.equal(readState(dir).compactions, 1);
});

test('a clear starts a new session, rebinds the run to it and sends the stored prompt', async () => {
  modes(fx.stub, 'clear-due', 'finish');
  const { dir, r } = await replay();
  assert.equal(r.outcome, 'finished');
  assert.equal(r.sessions.length, 2);
  const [, resumed] = calls();
  assert.equal(flag(resumed, '--session-id'), r.sessions[1]);
  assert.equal(flag(resumed, '--model'), 'opus');
  assert.equal(resumed.args.at(-1), 'RESUME FROM HANDOFF');
  assert.equal(readState(dir).session, r.sessions[1]);
});

test('a turn that ends with nothing pending is a stall, and stalls end the run', async () => {
  modes(fx.stub, 'stall');
  const { r } = await replay({ maxInvocations: 3 });
  assert.deepEqual([r.outcome, r.invocations, r.stalls], ['stalled', 3, 3]);
  assert.match(calls()[1].args.at(-1), /^Continue the auto run: run `bash .*\/scripts\/auto-run status`/);
});

test('a stopped run, a usage limit and a spent budget end the replay', async () => {
  modes(fx.stub, 'stop');
  const stopped = (await replay()).r;
  assert.deepEqual([stopped.outcome, stopped.stopped], ['stopped', 'tests failed at finishing']);
  modes(fx.stub, 'limit');
  assert.equal((await replay()).r.outcome, 'limit');
  modes(fx.stub, 'stall');
  const spent = (await replay({ budget: 2 })).r;
  assert.deepEqual([spent.outcome, spent.invocations], ['budget', 2]);
  assert.equal(flag(calls()[1], '--max-budget-usd'), '1.00');
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `timeout 300 node --test evals/controller/tests/drive.test.mjs`
Expected: FAIL with `ERR_MODULE_NOT_FOUND` for `lib/drive.mjs`.

- [ ] **Step 3: Write the implementation**

Create `evals/controller/lib/drive.mjs`:

```js
import { randomUUID } from 'node:crypto';
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { classify } from '../../tiers/lib/claude.mjs';
import { run } from '../../tiers/lib/sh.mjs';
import { PLUGIN } from './sessions.mjs';

// The cockpit's wording (hooks/cockpit/register.tsx), so a replay compacts and
// resumes as an attended auto run would.
export const COMPACT_INSTRUCTIONS =
  'Preserve verbatim: the worktree path; the plan, ledger, handoff and auto-run state file paths; the current HEAD; every Ruling: line; and the auto run pending decisions. Name the task in progress and its fix round.';
export const RESUME = 'Resume the work in .dforge/handoff/latest.md with the dforge resume-execution skill.';
export const continuePrompt = plan =>
  `Continue the auto run: run \`bash ${PLUGIN}/scripts/auto-run after-compact\` first, then continue the phase \`bash ${PLUGIN}/scripts/auto-run status\` names for plan ${plan}, through the After compaction steps of the execution skill its Execution line names, as reference/auto-run.md §After a compaction says.`;
export const startPrompt = plan =>
  `Execute the plan ${plan} with the dforge:subagent-driven-development skill. An auto run is bound to this session: ask nothing, and follow ${PLUGIN}/reference/auto-run.md.`;
export const STALL_PROMPT = `Continue the auto run: run \`bash ${PLUGIN}/scripts/auto-run status\` and carry on with the phase it names, as ${PLUGIN}/reference/auto-run.md says.`;
export const MAX_INVOCATIONS = 12;

// autoRun DIR SESSION ARGS — scripts/auto-run in DIR, speaking as SESSION.
export function autoRun(dir, session, args) {
  const r = spawnSync('bash', [join(PLUGIN, 'scripts/auto-run'), '--session', session, ...args], { cwd: dir, encoding: 'utf8' });
  if (r.status !== 0) throw new Error(`auto-run ${args.join(' ')}: exit ${r.status}: ${(r.stdout + r.stderr).trim()}`);
  return r.stdout;
}

export const readState = dir => JSON.parse(readFileSync(join(dir, '.dforge/sdd/auto-run.json'), 'utf8'));

// replayEnv — this process's environment without the parent session's
// identity or config directory, with the global CLAUDE.md off, root allowed
// to bypass permissions, and no import of the legacy dforge home.
export function replayEnv() {
  const env = { ...process.env, CLAUDE_CODE_DISABLE_CLAUDE_MDS: '1', IS_SANDBOX: '1', DFORGE_NO_IMPORT: '1' };
  for (const key of ['CLAUDE_CONFIG_DIR', 'CLAUDECODE', 'CLAUDE_CODE_SESSION_ID', 'CLAUDE_CODE_ENTRYPOINT', 'CLAUDE_CODE_SSE_PORT']) delete env[key];
  return env;
}

// drive { dir, plan, spec, model, effort, budget, seconds, out, maxInvocations }
// — runs PLAN in DIR under an auto run on one model and effort, standing in
// for the cockpit between turns: it compacts, clears and rebinds, or sends the
// continue prompt the run's pending action asks for. The arm's model and
// effort hold after a clear, whatever the plan's Execution line says. Resolves
// { sessions, invocations, compactions, stalls, cost, outcome, stopped }:
// outcome is finished, stopped, budget, limit, timeout, cut, error,
// compact-failed or stalled (MAX_INVOCATIONS turns without an end).
export async function drive({ dir, plan, spec, model, effort, budget, seconds, out, maxInvocations = MAX_INVOCATIONS }) {
  mkdirSync(out, { recursive: true });
  let session = randomUUID();
  const r = { sessions: [session], invocations: 0, compactions: 0, stalls: 0, cost: 0, outcome: 'stalled', stopped: null };
  autoRun(dir, session, ['start', '--spec', spec]);
  autoRun(dir, session, ['attach', '--plan', plan]);
  autoRun(dir, session, ['phase', 'execute']);
  let calls = 0;
  const call = async (flags, prompt) => {
    const n = ++calls;
    const args = ['-p', ...flags, '--model', model, '--effort', effort, '--plugin-dir', PLUGIN, '--setting-sources', 'project',
      '--permission-mode', 'bypassPermissions', '--output-format', 'json', '--max-budget-usd', Math.max(0.01, budget - r.cost).toFixed(2), prompt];
    const started = Date.now();
    const res = await run(process.env.CONTROLLER_EVAL_CLAUDE ?? 'claude', args, { cwd: dir, seconds, input: '', env: replayEnv() });
    writeFileSync(join(out, `call-${n}.json`), res.out);
    writeFileSync(join(out, `call-${n}.stderr.txt`), res.err);
    const found = classify(res, (Date.now() - started) / 1000);
    r.cost += found.cost;
    return found;
  };

  let flags = ['--session-id', session];
  let prompt = startPrompt(plan);
  while (r.invocations < maxInvocations) {
    r.invocations++;
    const turn = await call(flags, prompt);
    if (turn.kind !== 'ok') return { ...r, outcome: turn.kind };
    if (r.cost >= budget) return { ...r, outcome: 'budget' };
    let state = readState(dir);
    if (state.active && state.pending === 'compact') {
      const compact = await call(['--resume', session], `/compact ${COMPACT_INSTRUCTIONS}`);
      if (compact.kind !== 'ok') return { ...r, outcome: 'compact-failed' };
      autoRun(dir, session, ['compacted']);
      r.compactions++;
      state = readState(dir);
    }
    if (!state.active) return { ...r, outcome: state.stopped ? 'stopped' : 'finished', stopped: state.stopped };
    if (state.pending === 'clear') {
      session = randomUUID();
      r.sessions.push(session);
      autoRun(dir, session, ['rebind', '--to', session]);
      autoRun(dir, session, ['resumed']);
      flags = ['--session-id', session];
      prompt = state.resumePrompt ?? RESUME;
      continue;
    }
    flags = ['--resume', session];
    if (state.pending === 'after-compact') prompt = continuePrompt(plan);
    else if (state.pending === 'resume') prompt = state.resumePrompt ?? RESUME;
    else {
      r.stalls++;
      prompt = STALL_PROMPT;
    }
  }
  return r;
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `timeout 300 node --test evals/controller/tests/drive.test.mjs`
Expected: PASS, 5 tests.

- [ ] **Step 5: Commit**

```bash
git add evals/controller/lib/drive.mjs evals/controller/tests/stub-claude.mjs evals/controller/tests/drive.test.mjs
git commit -m "feat(evals): drive an auto run headless"
```

### Task 7: Replay grader

**Files:**
- Create: `evals/controller/lib/grade.mjs`
- Test: `evals/controller/tests/grade.test.mjs`

**Interfaces:**
- Consumes: `clone`, `git` and `repoOf` from `lib/prepare.mjs`, `fixture` (Task 5), `run` from `evals/tiers/lib/sh.mjs`.
- Produces: `lib/grade.mjs` (Contracts).

**Items:** 3

**Implementer:** dr-superpowers:impl-sonnet-medium
**Executor:** codex gpt-6.1-sol / high
**Evaluation:** files 1 - spec 0 - coupling 2 - risk 1 = 4

- [ ] **Step 1: Write the failing test**

Create `evals/controller/tests/grade.test.mjs`:

```js
import assert from 'node:assert/strict';
import { mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { after, test } from 'node:test';
import { fixture, git } from './fixture.mjs';
import { prepare } from '../lib/prepare.mjs';
import { golden, grade, hiddenTests, resultCheckout } from '../lib/grade.mjs';

const fx = fixture();
after(() => rmSync(fx.top, { recursive: true, force: true }));
const SLUG = '2026-10-18-demo';

test('golden passes on the final commit and fails on the base', async () => {
  assert.deepEqual(await golden(fx.kase, join(fx.top, 'golden')), { final: 'pass', base: 'fail' });
  assert.match(readFileSync(join(fx.top, 'golden/base.log'), 'utf8'), /^\$ bash tests\/hello\.test\.sh\n.*exit 1\n\$ true\nexit 0\n$/s);
});

test('grade reads the worktree that holds the ledger and runs the hidden tests there', async () => {
  const dir = join(fx.top, 'work/done');
  const { plan } = prepare(fx.kase, dir);
  const tree = join(fx.top, 'work/done-tree');
  git(dir, 'worktree', 'add', '-q', '-b', 'work', tree);
  writeFileSync(join(tree, 'src/greet.sh'), 'echo hello\n');
  mkdirSync(join(tree, '.dforge/sdd', SLUG), { recursive: true });
  writeFileSync(join(tree, '.dforge/sdd', SLUG, 'progress.md'), [
    'Task 1: complete (commits a..b, review clean)',
    'Task 2: complete (deferred by the auto run) — done: nothing',
    'Final review: clean (commits a..c)',
  ].join('\n') + '\n');
  assert.equal(resultCheckout(dir, SLUG).path, tree);
  const g = await grade(fx.kase, dir, plan, join(fx.top, 'out/done'));
  assert.deepEqual(g, { checkout: tree, tasks: 2, complete: 1, deferred: 1, finalClean: 'yes', tests: 'pass' });
});

test('grade without a ledger grades the clone, which fails its hidden tests', async () => {
  const dir = join(fx.top, 'work/bare');
  const { plan } = prepare(fx.kase, dir);
  const g = await grade(fx.kase, dir, plan, join(fx.top, 'out/bare'));
  assert.deepEqual(g, { checkout: dir, tasks: 2, complete: 0, deferred: 0, finalClean: 'no', tests: 'fail' });
});

test('hiddenTests stops at the first failing command and still cleans up', async () => {
  const dir = join(fx.top, 'work/cleanup');
  prepare(fx.kase, dir);
  const log = join(fx.top, 'out/cleanup.log');
  const kase = { ...fx.kase, tests: ['false', 'touch never'], cleanup: ['touch cleaned'] };
  assert.equal(await hiddenTests(kase, dir, log), 'fail');
  assert.equal(git(dir, 'status', '--porcelain', '--', 'never', 'cleaned'), '?? cleaned');
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `timeout 300 node --test evals/controller/tests/grade.test.mjs`
Expected: FAIL with `ERR_MODULE_NOT_FOUND` for `lib/grade.mjs`.

- [ ] **Step 3: Write the implementation**

Create `evals/controller/lib/grade.mjs`:

```js
import { appendFileSync, existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { basename, dirname, join } from 'node:path';
import { run } from '../../tiers/lib/sh.mjs';
import { clone, git, repoOf } from './prepare.mjs';

const CLEANUP_SECONDS = 300;

// resultCheckout DIR SLUG — the checkout a replay's work ended in: the
// worktree of DIR that holds the plan's ledger, or DIR itself when none does.
export function resultCheckout(dir, slug) {
  const trees = git(dir, 'worktree', 'list', '--porcelain').split('\n').filter(line => line.startsWith('worktree ')).map(line => line.slice('worktree '.length));
  const path = trees.find(tree => existsSync(join(tree, '.dforge/sdd', slug, 'progress.md')));
  return path === undefined ? { path: dir, ledger: null } : { path, ledger: join(path, '.dforge/sdd', slug, 'progress.md') };
}

// hiddenTests CASE CHECKOUT LOG — writes the final commit's version of each
// hidden test file into CHECKOUT, runs the test commands there in order until
// one fails, then every cleanup command. Resolves pass or fail; all output
// goes to LOG.
export async function hiddenTests(c, checkout, log) {
  mkdirSync(dirname(log), { recursive: true });
  writeFileSync(log, '');
  for (const path of c.hidden) {
    mkdirSync(dirname(join(checkout, path)), { recursive: true });
    writeFileSync(join(checkout, path), git(repoOf(c), 'show', `${c.final}:${path}`));
  }
  let result = 'pass';
  for (const cmd of c.tests) {
    const r = await run('bash', ['-c', cmd], { cwd: checkout, seconds: c.seconds });
    appendFileSync(log, `$ ${cmd}\n${r.out}${r.err}exit ${r.code}${r.timedOut ? ' (timed out)' : ''}\n`);
    if (r.code !== 0 || r.timedOut) {
      result = 'fail';
      break;
    }
  }
  for (const cmd of c.cleanup ?? []) {
    const r = await run('bash', ['-c', cmd], { cwd: checkout, seconds: CLEANUP_SECONDS });
    appendFileSync(log, `$ ${cmd}\n${r.out}${r.err}exit ${r.code}\n`);
  }
  return result;
}

// golden CASE DIR — the hidden tests on fresh clones of the final commit and
// of the base: { final, base }. A case is usable only when they pass on the
// final commit and fail on the base, so a pass means the work was done.
export async function golden(c, dir) {
  clone(c, join(dir, 'final'), c.final);
  const final = await hiddenTests(c, join(dir, 'final'), join(dir, 'final.log'));
  clone(c, join(dir, 'base'), c.base);
  const base = await hiddenTests(c, join(dir, 'base'), join(dir, 'base.log'));
  return { final, base };
}

// grade CASE DIR PLAN OUT — the deterministic checks on a finished replay:
// { checkout, tasks, complete, deferred, finalClean, tests }. A task split
// into parts counts once.
export async function grade(c, dir, plan, out) {
  const { path, ledger } = resultCheckout(dir, basename(plan, '.md'));
  const text = ledger === null ? '' : readFileSync(ledger, 'utf8');
  const tasks = (readFileSync(join(dir, plan), 'utf8').match(/^### Task \d+/gm) ?? []).length;
  const done = new Set();
  const deferred = new Set();
  for (const m of text.matchAll(/^Task (\d+)[A-Z]?: complete(.*)$/gm)) (m[2].includes('(deferred by the auto run)') ? deferred : done).add(m[1]);
  return {
    checkout: path,
    tasks,
    complete: done.size,
    deferred: deferred.size,
    finalClean: /^Final review: clean/m.test(text) ? 'yes' : 'no',
    tests: await hiddenTests(c, path, join(out, 'tests.log')),
  };
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `timeout 300 node --test evals/controller/tests/grade.test.mjs`
Expected: PASS, 4 tests.

- [ ] **Step 5: Commit**

```bash
git add evals/controller/lib/grade.mjs evals/controller/tests/grade.test.mjs
git commit -m "feat(evals): grade a finished replay"
```

### Task 8: Replay command and cases

**Files:**
- Create: `evals/controller/cases.json`
- Create: `evals/controller/replay.mjs`
- Test: `evals/controller/tests/replay.test.mjs`

**Interfaces:**
- Consumes: `drive` (Task 6), `golden` and `grade` (Task 7), `prepare` (Task 5), `PLUGIN`, `flatten`, `measureSessions` and `sessionFile` (Task 2), `appendTsv` and `readTsv` from `evals/tiers/lib/results.mjs`.
- Produces: `cases.json`, `results/replay.tsv` (written on the first run; Contracts) and `replay.mjs golden CASE | run CASE ARM [--rep N]` with exits 0 done or already scored, 1 golden unusable or lint failure, 2 usage or refused setting, 3 usage limit with nothing recorded.

**Items:** 3

**Implementer:** dr-superpowers:impl-sonnet-medium
**Executor:** codex gpt-6.1-sol / high
**Evaluation:** files 1 - spec 0 - coupling 2 - risk 1 = 4

- [ ] **Step 1: Write the failing test**

Create `evals/controller/tests/replay.test.mjs`:

```js
import assert from 'node:assert/strict';
import { existsSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { spawn } from 'node:child_process';
import { after, test } from 'node:test';
import { fixture, modes } from './fixture.mjs';

const fx = fixture();
after(() => rmSync(fx.top, { recursive: true, force: true }));
const data = join(fx.top, 'data');
const home = join(fx.top, 'home');
mkdirSync(data, { recursive: true });
mkdirSync(home, { recursive: true });
writeFileSync(join(data, 'cases.json'), JSON.stringify([fx.kase]));
const results = join(data, 'results/replay.tsv');
const calls = () => (existsSync(join(fx.stub, 'calls.log')) ? readFileSync(join(fx.stub, 'calls.log'), 'utf8').trim().split('\n').filter(Boolean).length : 0);

const replay = (...args) => new Promise(done => {
  const child = spawn(process.execPath, ['evals/controller/replay.mjs', ...args], {
    env: { ...process.env, HOME: home, CONTROLLER_EVAL_DATA: data, CONTROLLER_EVAL_WORK: join(fx.top, 'work'), CONTROLLER_EVAL_PROJECTS: join(fx.top, 'projects') },
  });
  let out = '', err = '';
  child.stdout.on('data', d => { out += d; });
  child.stderr.on('data', d => { err += d; });
  child.on('close', status => done({ status, out, err }));
});

test('golden reports a usable case', async () => {
  const r = await replay('golden', 'demo');
  assert.equal(r.status, 0, r.err);
  assert.match(r.out, /^golden demo: final pass, base fail — usable;/);
});

test('run replays, grades and records one row; a second run is skipped', async () => {
  modes(fx.stub, 'finish');
  const r = await replay('run', 'demo', 'opus@low');
  assert.equal(r.status, 0, r.err);
  const [header, line] = readFileSync(results, 'utf8').trim().split('\n');
  const row = Object.fromEntries(header.split('\t').map((k, i) => [k, line.split('\t')[i]]));
  assert.deepEqual([row.rep, row.case, row.arm, row.outcome, row.invocations, row.tasks, row.complete, row.finalClean, row.tests, row.sessions, row.cliCost],
    ['1', 'demo', 'opus@low', 'finished', '1', '2', '0', 'no', 'fail', '0', '1.00']);
  assert.match(r.out, /^rep=1 case=demo arm=opus@low outcome=finished /);
  const before = calls();
  const again = await replay('run', 'demo', 'opus@low');
  assert.equal(again.status, 0);
  assert.match(again.out, /already scored/);
  assert.equal(calls(), before);
});

test('a usage limit records nothing', async () => {
  modes(fx.stub, 'limit');
  const r = await replay('run', 'demo', 'sonnet@high', '--rep', '2');
  assert.equal(r.status, 3);
  assert.doesNotMatch(readFileSync(results, 'utf8'), /^2\tdemo\tsonnet@high/m);
});

test('usage errors exit 2', async () => {
  assert.equal((await replay('run', 'demo', 'haiku@low')).status, 2);
  assert.equal((await replay('run', 'nope', 'opus@low')).status, 2);
  assert.equal((await replay('run', 'demo', 'opus@low', '--rep', '0')).status, 2);
  assert.equal((await replay('golden', 'demo', 'extra')).status, 2);
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `timeout 300 node --test evals/controller/tests/replay.test.mjs`
Expected: FAIL: every test sees a nonzero exit or a missing `results/replay.tsv`, because `replay.mjs` does not exist.

- [ ] **Step 3: Write the implementation**

Create `evals/controller/cases.json`:

```json
[
  {
    "id": "darkcloud-residuals-8",
    "repo": "darkcloud",
    "plan": "docs/superpowers/plans/2026-10-06-enrichment-and-jobs-residuals-8.md",
    "base": "7ea63d97",
    "final": "28ff8360",
    "historical": { "controller": 2.22, "subagents": 4.69 },
    "hidden": [
      "tests/Darkcloud.Api.IntegrationTests/NetworkShares/NetworkDaemonSandboxTests.cs",
      "tests/Darkcloud.Api.IntegrationTests/RcloneSandboxLifecycleTests.cs"
    ],
    "tests": [
      "dotnet test tests/Darkcloud.Api.IntegrationTests/Darkcloud.Api.IntegrationTests.csproj --filter \"FullyQualifiedName~NetworkDaemonSandboxTests|FullyQualifiedName~RcloneSandboxLifecycleTests\""
    ],
    "cleanup": ["dotnet build-server shutdown"],
    "seconds": 1800
  },
  {
    "id": "darkpanel-m1-tooling",
    "repo": "darkpanel",
    "plan": "docs/superpowers/plans/2026-10-17-m1-repository-tooling.md",
    "base": "a525f59",
    "final": "eed7a01",
    "historical": { "controller": 4.78, "subagents": 5.27 },
    "hidden": ["cmd/darkpanel/version_test.go", "web/embed_test.go", "web/src/app.test.tsx"],
    "tests": ["go test -count=1 ./...", "pnpm -C web install --frozen-lockfile", "pnpm -C web test"],
    "cleanup": [],
    "seconds": 1800
  },
  {
    "id": "dforge-auto-run",
    "repo": "darkraise-ai-plugins",
    "plan": "docs/superpowers/plans/2026-10-13-dr-forge-auto-run.md",
    "base": "8045a02",
    "final": "609c023",
    "historical": { "controller": 7.76, "subagents": 16.46 },
    "hidden": [
      "plugins/dr-forge/tests/auto-run-skills.test.sh",
      "plugins/dr-forge/tests/auto-run.test.sh",
      "plugins/dr-forge/tests/budget-line.test.sh",
      "plugins/dr-forge/tests/cockpit.test.ts",
      "plugins/dr-forge/tests/context-size.test.sh",
      "plugins/dr-forge/tests/review-route.test.sh",
      "plugins/dr-forge/tests/settings-skills.test.sh",
      "plugins/dr-forge/tests/turn-end.test.sh"
    ],
    "tests": [
      "bash plugins/dr-forge/tests/auto-run-skills.test.sh",
      "bash plugins/dr-forge/tests/auto-run.test.sh",
      "bash plugins/dr-forge/tests/budget-line.test.sh",
      "bash plugins/dr-forge/tests/context-size.test.sh",
      "bash plugins/dr-forge/tests/review-route.test.sh",
      "bash plugins/dr-forge/tests/settings-skills.test.sh",
      "bash plugins/dr-forge/tests/turn-end.test.sh",
      "claude plugin test plugins/dr-forge"
    ],
    "cleanup": [],
    "seconds": 1800
  }
]
```

Create `evals/controller/replay.mjs`:

```js
// node evals/controller/replay.mjs golden CASE
// node evals/controller/replay.mjs run CASE ARM [--rep N]
// Stage 2 of docs/superpowers/notes/2026-10-17-controller-model-eval.md.
// `golden` runs a case's hidden tests on its final commit and its base and
// calls no model. `run` replays the case's plan under an auto run on ARM
// (model@effort) through `claude -p`, spending up to twice the case's
// historical cost, grades it and appends one row to results/replay.tsv.
// Exit: 0 done or already scored; 1 golden not usable, or a lint failure;
// 2 usage or a refused setting; 3 a usage limit (nothing recorded; run again).
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { join, resolve } from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { appendTsv, readTsv } from '../tiers/lib/results.mjs';
import { drive } from './lib/drive.mjs';
import { golden, grade } from './lib/grade.mjs';
import { prepare } from './lib/prepare.mjs';
import { PLUGIN, flatten, measureSessions, sessionFile } from './lib/sessions.mjs';

const DATA = process.env.CONTROLLER_EVAL_DATA ?? fileURLToPath(new URL('.', import.meta.url));
const WORK = process.env.CONTROLLER_EVAL_WORK ?? resolve(homedir(), '.cache/dr-controller-eval');
const RESULTS = join(DATA, 'results/replay.tsv');
const COLUMNS = ['rep', 'case', 'arm', 'outcome', 'stopped', 'invocations', 'stalls', 'compactions', 'tasks', 'complete', 'deferred', 'finalClean', 'tests',
  'sessions', 'calls', 'dispatches', 'controllerCost', 'subagentCost', 'costPerDispatch', 'cliCost', 'sleeps', 'listAgents', 'monitors', 'nudges', 'seatMisses', 'inFlight', 'unpriced', 'seconds'];
const ARMS = ['sonnet@high', 'opus@low', 'sonnet@medium', 'opus@medium'];
// One headless turn may run this long; a replay's whole plan usually runs in one.
const TURN_SECONDS = 4 * 3600;

function usage() {
  console.error(`usage: replay.mjs golden CASE | run CASE ARM [--rep N]  (ARM: ${ARMS.join(', ')})`);
  process.exit(2);
}

const [command, id, arm, ...rest] = process.argv.slice(2);
const cases = JSON.parse(readFileSync(join(DATA, 'cases.json'), 'utf8'));
const c = cases.find(k => k.id === id);
if (c === undefined) {
  console.error(`replay: no case ${id ?? ''}; cases: ${cases.map(k => k.id).join(', ')}`);
  usage();
}

if (command === 'golden' && arm === undefined) {
  const dir = join(WORK, 'golden', c.id);
  const r = await golden(c, dir);
  const usable = r.final === 'pass' && r.base === 'fail';
  console.log(`golden ${c.id}: final ${r.final}, base ${r.base} — ${usable ? 'usable' : 'not usable'}; logs in ${dir}`);
  process.exit(usable ? 0 : 1);
}
if (command !== 'run' || !ARMS.includes(arm)) usage();
if (!(rest.length === 0 || (rest.length === 2 && rest[0] === '--rep' && /^[1-9]\d*$/.test(rest[1])))) usage();
const rep = rest.length === 0 ? 1 : Number(rest[1]);

if (readTsv(RESULTS).some(r => r.rep === String(rep) && r.case === c.id && r.arm === arm)) {
  console.log(`replay: rep ${rep} ${c.id} ${arm} is already scored in ${RESULTS}`);
  process.exit(0);
}
// The replay runs on this machine's dforge settings: a darkmem store would
// send its ledgers out of the clone, and a merge or pr finish would move its
// result off the worktree the grader reads.
const setting = key => spawnSync('bash', [join(PLUGIN, 'scripts/dforge-config'), 'get', key], { encoding: 'utf8', env: { ...process.env, DFORGE_NO_IMPORT: '1' } }).stdout.trim();
if (setting('darkmemEnabled') !== 'false' || !['ask', 'keep', 'wait'].includes(setting('finishAction'))) {
  console.error('replay: needs dforge darkmemEnabled=false and finishAction ask, keep or wait; see dforge-config get');
  process.exit(2);
}

const dir = join(WORK, `rep${rep}`, c.id, arm.replace('@', '-at-'));
const out = `${dir}-out`;
mkdirSync(out, { recursive: true });
const prepared = prepare(c, dir);
writeFileSync(join(out, 'plan-lint.txt'), prepared.lint);
const row = { rep, case: c.id, arm };
if (prepared.lintErrors !== 0 || prepared.spec === null) {
  appendTsv(RESULTS, COLUMNS, { ...row, outcome: 'lint' });
  console.error(`replay: ${c.plan} does not lint clean or names no spec; see ${join(out, 'plan-lint.txt')}`);
  process.exit(1);
}
const [model, effort] = arm.split('@');
const started = Date.now();
const d = await drive({ dir, plan: prepared.plan, spec: prepared.spec, model, effort, budget: 2 * (c.historical.controller + c.historical.subagents), seconds: TURN_SECONDS, out });
if (d.outcome === 'limit') {
  console.error(`replay: usage limit after ${d.invocations} turns; nothing recorded, run again later`);
  process.exit(3);
}
const g = await grade(c, dir, prepared.plan, out);
const measured = flatten(measureSessions(d.sessions.map(s => sessionFile(s)).filter(file => file !== null)));
Object.assign(row, {
  outcome: d.outcome, stopped: d.stopped ?? '', invocations: d.invocations, stalls: d.stalls, compactions: d.compactions,
  tasks: g.tasks, complete: g.complete, deferred: g.deferred, finalClean: g.finalClean, tests: g.tests,
  ...measured, cliCost: d.cost.toFixed(2), seconds: Math.round((Date.now() - started) / 1000),
});
appendTsv(RESULTS, COLUMNS, row);
console.log(COLUMNS.map(k => `${k}=${row[k]}`).join(' '));
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `timeout 300 node --test evals/controller/tests/*.test.mjs`
Expected: PASS, 38 tests.
Run: `timeout 300 node evals/controller/replay.mjs run darkpanel-m1-tooling haiku@low; echo "exit $?"`
Expected: the usage line and `exit 2`, with no model call.

- [ ] **Step 5: Commit**

```bash
git add evals/controller/cases.json evals/controller/replay.mjs evals/controller/tests/replay.test.mjs
git commit -m "feat(evals): replay a plan on a controller arm"
```

### Task 9: Stage 2 report and README

**Files:**
- Create: `evals/controller/replay-report.mjs`
- Create: `evals/controller/README.md`
- Test: `evals/controller/tests/replay-report.test.mjs`

**Interfaces:**
- Consumes: `lib/decide.mjs` (Task 3), `readTsv` from `evals/tiers/lib/results.mjs`, `results/replay.tsv` columns (Contracts).
- Produces: `replay-report.mjs [--rep N]`, printing a header, one row per run and a `stage2: …` line; exit 2 on a bad `--rep`.

**Items:** 3

**Implementer:** dr-superpowers:impl-sonnet-low
**Executor:** codex gpt-6.1-sol / low
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 0 = 2

- [ ] **Step 1: Write the failing test**

Create `evals/controller/tests/replay-report.test.mjs`:

```js
import assert from 'node:assert/strict';
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { after, test } from 'node:test';

const data = mkdtempSync(join(tmpdir(), 'controller-report-'));
after(() => rmSync(data, { recursive: true, force: true }));
const KEYS = ['rep', 'case', 'arm', 'outcome', 'tasks', 'complete', 'finalClean', 'tests', 'controllerCost', 'subagentCost', 'costPerDispatch', 'dispatches', 'inFlight', 'seatMisses', 'nudges', 'sleeps', 'listAgents'];
const line = (rep, c, arm, cost, extra = {}) => {
  const row = { rep, case: c, arm, outcome: 'finished', tasks: 3, complete: 3, finalClean: 'yes', tests: 'pass', controllerCost: cost, subagentCost: 5, costPerDispatch: cost / 10, dispatches: 10, inFlight: 0, seatMisses: 0, nudges: 0, sleeps: 0, listAgents: 0, ...extra };
  return KEYS.map(k => row[k]).join('\t');
};
mkdirSync(join(data, 'results'), { recursive: true });
writeFileSync(join(data, 'results/replay.tsv'), [
  KEYS.join('\t'),
  line(1, 'a', 'sonnet@high', 2, { nudges: 1 }),
  line(1, 'a', 'opus@low', 2.8),
  line(1, 'a', 'sonnet@medium', 1.6, { inFlight: 2 }),
  line(1, 'b', 'sonnet@high', 2, { outcome: 'lint' }),
  line(2, 'a', 'sonnet@high', 2),
].join('\n') + '\n');
const report = (...args) => spawnSync(process.execPath, ['evals/controller/replay-report.mjs', ...args], { encoding: 'utf8', env: { ...process.env, CONTROLLER_EVAL_DATA: data } });

test('replay-report prints the repetition and its decision, leaving lint rows out', () => {
  const r = report();
  assert.equal(r.status, 0, r.stderr);
  const lines = r.stdout.trim().split('\n');
  assert.equal(lines.length, 5);
  assert.deepEqual(lines[1].split('\t').slice(0, 3).concat(lines[1].split('\t').at(-1)), ['a', 'sonnet@high', 'finished', '1']);
  assert.equal(lines[4], 'stage2: switch-opus-low — opus@low costs 1.40x sonnet@high per dispatch; failures sonnet@high 1, opus@low 0, sonnet@medium 2; cases passed sonnet@high 1, opus@low 1, sonnet@medium 1');
});

test('replay-report reads another repetition, and refuses a bad one', () => {
  assert.match(report('--rep', '2').stdout, /^stage2: incomplete/m);
  assert.equal(report('--rep', 'x').status, 2);
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `timeout 300 node --test evals/controller/tests/replay-report.test.mjs`
Expected: FAIL: both tests see a nonzero exit, because `replay-report.mjs` does not exist.

- [ ] **Step 3: Write the implementation and the README**

Create `evals/controller/replay-report.mjs`:

```js
// node evals/controller/replay-report.mjs [--rep N]
// Prints the replay rows of one repetition (default 1) and the Stage 2
// decision. Rows that failed plan-lint are left out. Reads only; calls no model.
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { readTsv } from '../tiers/lib/results.mjs';
import { BASE, CANDIDATE, CHEAPER, failures, stage2 } from './lib/decide.mjs';

const DATA = process.env.CONTROLLER_EVAL_DATA ?? fileURLToPath(new URL('.', import.meta.url));
const COLUMNS = ['case', 'arm', 'outcome', 'tasks', 'complete', 'finalClean', 'tests', 'controllerCost', 'subagentCost', 'costPerDispatch', 'failures'];

const args = process.argv.slice(2);
if (!(args.length === 0 || (args.length === 2 && args[0] === '--rep' && /^[1-9]\d*$/.test(args[1])))) {
  console.error('usage: replay-report.mjs [--rep N]');
  process.exit(2);
}
const rep = args.length === 0 ? '1' : args[1];
const rows = readTsv(join(DATA, 'results/replay.tsv')).filter(r => r.rep === rep && r.outcome !== 'lint');
console.log(COLUMNS.join('\t'));
for (const r of rows) console.log(COLUMNS.map(k => (k === 'failures' ? failures(r) : r[k])).join('\t'));
const d = stage2(rows);
const arms = [BASE, CANDIDATE, CHEAPER];
console.log(`stage2: ${d.decision} — ${CANDIDATE} costs ${d.ratio.toFixed(2)}x ${BASE} per dispatch; failures ${arms.map(a => `${a} ${d.failures[a]}`).join(', ')}; cases passed ${arms.map(a => `${a} ${d.passed[a].length}`).join(', ')}`);
```

Create `evals/controller/README.md`:

```markdown
# Controller model evaluation harness

Decides whether dforge's subagent-mode controller should move from
`claude --model sonnet --effort high` to Opus 5.5 at `low` (or to Sonnet at
`medium`). The question, the evidence and the decision rules are in
`docs/superpowers/notes/2026-10-17-controller-model-eval.md`.

Stage 1 reads Claude Code transcripts and calls no model. Stage 2's `run`
calls `claude -p`, which draws on the Claude subscription's usage limits.
Everything else, including the tests, is free. POSIX only.

## Commands

Run them from the repository root.

| Command | What it does |
|---|---|
| `node evals/controller/measure.mjs --plan SLUG` | The controller metrics of one plan's controller sessions, as JSON |
| `node evals/controller/measure.mjs --session FILE ...` | The same for named transcripts |
| `node evals/controller/pilot-report.mjs` | Stage 1: one row per plan in `pilot.tsv`, then `stage1: keep, switch, ambiguous or incomplete` |
| `node evals/controller/replay.mjs golden CASE` | Stage 2: checks that a case's hidden tests pass on its final commit and fail on its base; exit 1 means the case is not usable |
| `node evals/controller/replay.mjs run CASE ARM [--rep N]` | Stage 2: replays one case on ARM (`sonnet@high`, `opus@low`, `sonnet@medium`, `opus@medium`), grades it and appends a row to `results/replay.tsv` |
| `node evals/controller/replay-report.mjs [--rep N]` | Stage 2: the rows of one repetition and `stage2: switch-opus-low, adopt-sonnet-medium, keep-sonnet-high or incomplete` |
| `node --test evals/controller/tests/*.test.mjs` | The harness tests, against a stub `claude` |

`replay.mjs` exits 0 when done or already scored, 1 when a golden check fails
or the plan does not lint clean, 2 on bad usage or a refused dforge setting, and
3 at a usage limit, having recorded nothing: run the same command again later.

## Stage 1: production A/B

For each of the next 6 subagent-mode plans, alternating and starting with
`opus@low`:

1. Add a row to `pilot.tsv`: the plan's repository-relative path, its
   repository (a sibling directory name of this repository, or an absolute
   path), the arm, and a note.
2. For an `opus@low` row, launch the execution session with
   `claude --model opus --effort low` instead of the plan's Execution line.
   `plan-lint` only warns about the difference.
3. When all 6 plans are complete, run `pilot-report.mjs`. On `ambiguous`, run
   Stage 2.

A plan's controller sessions are the transcripts that invoked
`subagent-driven-development` and ran `task-brief`, `review-route` or
`review-package` on that plan. A plan is complete when a `completed.md` in its
repository lists it.

## Stage 2: controlled replay

`cases.json` holds three completed plans. For each case, `replay.mjs run`:

- clones the case's repository at its base commit into
  `~/.cache/dr-controller-eval/rep<N>/<case>/<arm>`, deleting every other ref
  and every unreachable object, so no later commit can be read;
- moves the clone to dforge 4.0's layout with `scripts/dforge-migrate` (under an
  empty `HOME`, so it never moves `~/.dr-forge` or `~/.dr-superpowers`) and
  refuses a plan that does not lint clean;
- starts an auto run bound to a new session, attaches the plan, and runs
  `claude -p` on the arm with this repository's `plugins/dforge`, project
  settings only, no CLAUDE.md, and a budget of twice the case's historical
  cost. Between turns it does what the cockpit does: compact, clear and
  rebind, or send the continue prompt;
- grades the checkout holding the plan's ledger: every task `complete`, a clean
  `Final review:` line, and the final commit's hidden tests passing;
- measures the replay's transcripts as Stage 1 does.

Run `golden` for every case first. Then run each case on `sonnet@high`,
`opus@low` and `sonnet@medium`; add `opus@medium` only if `opus@low` shows
slips that more effort might fix. Three cases and one repetition show only
large differences, so treat the result as a screen.

`replay.mjs run` refuses to start unless dforge's `darkmemEnabled` is `false`
and `finishAction` is `ask`, `keep` or `wait`, so ledgers stay in the clone and
the work stays on the worktree the grader reads.

## Metrics

| Metric | Meaning |
|---|---|
| `controllerCost`, `subagentCost` | Transcript tokens priced per meter at the rates in `lib/transcript.mjs`; a model not listed there is named in `unpriced` |
| `dispatches` | Agent dispatches plus Codex task and review runs |
| `costPerDispatch` | `controllerCost / dispatches` |
| `sleeps`, `listAgents` | Busy-wait calls: bare `sleep N` commands and ListAgents calls |
| `nudges` | Messages typed by a person asking about status or running work |
| `seatMisses` | Reviews `review-route` routed that never reached the printed seat |
| `inFlight` | Background launches each session left running, as `scripts/in-flight` counts them |

A run's failures are `inFlight + seatMisses + nudges`, plus one when
`sleeps + listAgents` reaches 20.

## Environment

| Variable | Default |
|---|---|
| `CONTROLLER_EVAL_PROJECTS` | `~/.claude/projects` |
| `CONTROLLER_EVAL_REPOS` | the directory holding this repository |
| `CONTROLLER_EVAL_DATA` | `evals/controller` |
| `CONTROLLER_EVAL_WORK` | `~/.cache/dr-controller-eval` |
| `CONTROLLER_EVAL_CLAUDE` | `claude` |
```

- [ ] **Step 4: Run the full checks**

Run: `timeout 300 node --test evals/controller/tests/*.test.mjs`
Expected: PASS, 40 tests.
Run: `timeout 120 node scripts/validate-repository.mjs`
Expected: `Repository catalogs, manifests, versions, bundled links and the settings schema are valid.`
Run: `timeout 300 node --test tests/repository-layout.test.mjs tests/test-shards.test.mjs tests/ui-discovery.test.mjs`
Expected: PASS, 36 tests.

- [ ] **Step 5: Commit**

```bash
git add evals/controller/replay-report.mjs evals/controller/README.md evals/controller/tests/replay-report.test.mjs
git commit -m "docs(evals): report the replay and document it"
```
