# dr-superpowers Codex Through The Plugin Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: the skill the **Execution:** line names — dr-superpowers:subagent-driven-development for `subagent`, dr-superpowers:executing-plans for `inline`. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move every Codex run — the review runner, the task runner and the executor roster — off the `codex` executable and onto the official plugin's client library, through one new module, and drop the `models_cache.json` read that violates the "never read Codex-owned state" boundary.

**Architecture:** A new `scripts/lib/codex-client.mjs` receives an already-vetted plugin root on argv and a JSON request on stdin, runs exactly one Codex turn through the plugin's public `runAppServerTurn` for every kind, owns the deadline, the `turn/interrupt` and the broker reaper, and prints a JSON result. `run-codex-review.sh`, `run-codex-task.sh` and `detect-executors.sh` stay bash and keep every externally visible contract — argv, status line, exit codes, task record, resume semantics — replacing only the block that used to build and spawn a `codex exec` argv. `scripts/codex-plugin` remains the single locator and the single place the version allowlist is enforced.

**Tech Stack:** Bash, Node.js (ES modules), `jq`, the official `codex@openai-codex` plugin 1.0.3 client library (`scripts/lib/codex.mjs`, `scripts/lib/app-server.mjs`, `scripts/lib/broker-lifecycle.mjs`), Markdown, git.

**Spec:** `docs/superpowers/specs/2026-09-16-dr-superpowers-codex-through-plugin-design.md`

**Execution:** subagent — `claude --model sonnet --effort high` — Task 2 totals 5 (coupling 2, risk 2), above the inline band's ceiling of 4.

**Program:** `docs/superpowers/specs/2026-09-11-dr-superpowers-fork-design.md` — sub-project 9 of 9 — last

**Plan review:** 2026-09-16 — dr-superpowers:judge-opus — executability 15 / coherence 14 / coverage 17 / assumptions 17 (round 3)

## Global Constraints

- Plugin version stays `1.9.0` until Task 16, which sets `1.10.0` on both `plugins/dr-superpowers/.claude-plugin/plugin.json` and `plugins/dr-superpowers/.codex-plugin/plugin.json`. The two must stay equal.
- **Not modified by any task:** `scripts/codex-plugin`, `scripts/codex-gate`, `scripts/lib/codex-gate.mjs`, `scripts/lib/codex-session.sh`, `scripts/review-route`, `scripts/plan-lint`, `reference/codex-plugin.json`, `reference/native-codex.md`, and every fenced block in `reference/ladder.md`.
- English only, in every file: code, comments, docs, commits, tests.
- Commits follow `<type>(<scope>): <subject>`, subject 50 characters or fewer, imperative, no trailing period. The scope is `superpowers`.
- New scripts and test suites are mode `100755` in the index. `git config core.filemode` is `false` on this machine, so `chmod +x` does not reach the index: run `git update-index --chmod=+x <path>` after `git add`.
- No file under a plugin may contain `superpowers:` without the `dr-` prefix, or `dcc-superpower-companions:` (`scripts/validate-repository.mjs:85`).
- No script other than `scripts/lib/codex-client.mjs` and the untouched `scripts/lib/codex-gate.mjs` may import from the Codex plugin, and no script may name the `codex` executable or read Codex-owned state (`$CODEX_HOME`, `~/.codex`).
- Every suite touching `scripts/run-codex-review.sh`, `scripts/run-codex-task.sh` or `scripts/detect-executors.sh` exports `DR_CODEX_SESSION_DIR` (a temporary directory) and `CLAUDE_CODE_SESSION_ID` (a fixed id) near its top, so the machine's real session file never reaches a case.
- No test starts a real Codex, spawns a real broker, or reads the machine's Claude config. Every suite runs against the Task 1 stub fixture.
- Every command in every step runs from the repository root: `bash plugins/dr-superpowers/tests/…`, `node scripts/validate-repository.mjs`, `git …`.

## Contracts

Paths are repository-relative unless a step says otherwise. `P` in test suites is the plugin root.

**Files this plan creates**

| Path | Produced by |
|---|---|
| `plugins/dr-superpowers/tests/fixtures/stub-codex-plugin/` | Task 1 |
| `plugins/dr-superpowers/scripts/lib/codex-client.mjs` | Task 2, extended by Tasks 3, 4 and 5 |
| `plugins/dr-superpowers/criteria/codex-final-review.md` | Task 6 |
| `plugins/dr-superpowers/tests/codex-client.test.sh` | Task 2, extended by Tasks 3, 4 and 5 |
| `docs/superpowers/notes/2026-09-16-codex-through-plugin-calibration.md` | Task 15 |

**`codex-client.mjs` interface** (Task 2; consumed by Tasks 6, 9 and 10)

Invocation: `node <P>/scripts/lib/codex-client.mjs <plugin-root>`, request JSON on stdin, result JSON on stdout, always exit 0 unless the process itself fails.

Request fields:

```
{ "op": "turn" | "auth",
  "kind": "task" | "plan" | "risk3" | "final",
  "cwd": "<absolute path>",
  "model": "<slug>", "effort": "<low|medium|high>",
  "prompt": "<text>", "schemaPath": "<path>" | null,
  "sandbox": "read-only" | "workspace-write" | null,
  "resumeThreadId": "<id>" | null,
  "persistThread": true | false,
  "threadName": "<name>" | null,
  "deadlineMs": <positive integer> }
```

Result fields:

```
{ "ok": true | false,
  "turnStatus": 0 | 1 | null,
  "threadId": "<id>" | null, "turnId": "<id>" | null,
  "finalMessage": "<text>" | null,
  "refusal": true | false, "quota": true | false,
  "timedOut": true | false, "interrupted": true | false,
  "reaped": true | false,
  "reason": "<short token>" | null,
  "stderr": "<text>" }
```

`reason` is one of `plugin-api`, `unavailable`, `logged-out`, `quota`, `refusal`, `timeout`, `bad-request`, or `null` when `ok` is true.

`kind` is carried for diagnostics only. **Every kind runs one plain
`runAppServerTurn`.** The client never calls `runAppServerReview`, which reads
only `model`, `threadName`, `target` and `delivery` (`codex.mjs:908-961`) and
would discard the seat's criteria prompt and output schema. `--kind final`
therefore arrives with `criteria/codex-final-review.md` and the branch diff
already composed into `prompt` by `run-codex-review.sh`, and with `schemaPath`
null, because the final round has no schema and its report stays the markdown
findings list `reference/final-review.md` section 3 deduplicates. There is no
`base` field: the runner uses `--base` to build the diff and nothing downstream
of that needs it.

**`op: "auth"`** ignores every turn field and returns `{ ok, reason, authed: true|false|null, detail }`, used by Task 9.

**Stub fixture contract** (Task 1; consumed by Tasks 2, 3, 4, 5, 6, 9, 10, 12, 13)

`tests/fixtures/stub-codex-plugin/` mirrors the real plugin's layout: `.claude-plugin/plugin.json`, `scripts/lib/codex.mjs`, `scripts/lib/app-server.mjs`, `scripts/lib/broker-lifecycle.mjs`. It exports **no** `runAppServerReview`, so no suite can certify a path the client does not take. Behaviour is scripted by environment variables read on every call:

| Variable | Effect |
|---|---|
| `STUB_MODE` | `ok` (default), `refusal`, `quota`, `hang`, `throw`, `logged-out`, `unavailable` |
| `STUB_FINAL_MESSAGE` | the text `runAppServerTurn` returns as `finalMessage` |
| `STUB_TURN_STATUS` | `0` or `1`, default `0` |
| `STUB_EVENT_LOG` | file every stub call appends one line to, for assertions |
| `STUB_EMPTY` | `1` makes a turn return an empty `finalMessage` |
| `STUB_REFUSE_ONCE` | `1` refuses only the first call, so the fallback rung succeeds; the count comes from `STUB_CALL_FILE` |
| `STUB_CALL_FILE` | file holding the turn count. It is a file, not module state, because each seat is a fresh `node` process |
| `STUB_SECOND_MODE` | the `STUB_MODE` value the second and later calls use, for refuse-then-quota |
| `STUB_PRE_EXISTING` | `1` makes a broker session exist before the turn, which must not be reaped |
| `STUB_NO_BROKER` | `1` makes no broker session exist after the turn |
| `STUB_SHUTDOWN_FAILS` | `1` leaves the session in place after a shutdown, forcing teardown |

**Status line** (`run-codex-review.sh`, unchanged shape, Task 6)

```
codex-judge <model>/<effort> status=OK|FALLBACK|TIMEOUT|FAILED exit=<n> out=<path> evidence=none
```

## Assumptions (evidence)

- `codex@openai-codex` 1.0.3 exports `runAppServerTurn`, `runAppServerReview`, `interruptAppServerTurn`, `getCodexAuthStatus` and `getCodexAvailability` from `scripts/lib/codex.mjs` — read 2026-09-16 at `~/.claude-alt/plugins/cache/openai-codex/codex/1.0.3/scripts/lib/codex.mjs:792-1090`.
- `broker-lifecycle.mjs` exports `loadBrokerSession`, `sendBrokerShutdown`, `teardownBrokerSession` and `clearBrokerSession` — read 2026-09-16 at the same root, `scripts/lib/broker-lifecycle.mjs:11-173`.
- `runAppServerTurn` spawns a broker: `withAppServer` calls `connect(cwd)` with no options, and `connect` calls `ensureBrokerSession` unless `disableBroker` is passed — `scripts/lib/codex.mjs:607-635` and `scripts/lib/app-server.mjs:331-348`, read 2026-09-16. This is why the spec chose broker mode plus a reaper.
- `interruptAppServerTurn` requires both `threadId` and `turnId` and returns `{attempted:false}` without them; the progress reporter carries both (`turnId` at `scripts/lib/codex.mjs:512`) — read 2026-09-16.
- `scripts/codex-plugin` already prints `codex-plugin ok version=<v> root=<path>` and enforces the allowlist — `plugins/dr-superpowers/scripts/codex-plugin:61`, read 2026-09-16.
- `node scripts/test-all.mjs` has one pre-existing failure on this machine, `tests/ui-discovery.test.mjs` "documented Win32 discovery finds centrally managed versions", from `bash: rg: command not found`. Verified 2026-09-16.
- Codex quota is exhausted until 2026-09-20 17:03 (+07) and `codex@openai-codex` is not enabled in the `.claude-alt` profile this repository is developed in, so `scripts/codex-gate` reports `usable=false reason=plugin-not-enabled`. Verified 2026-09-16. Task 15 therefore records both shipping gates `PENDING`.
- `runAppServerReview` is not used by this plan. It reads only `model`, `threadName`, `target`, `delivery` and `onProgress` and starts its own read-only thread (`~/.claude-alt/plugins/cache/openai-codex/codex/1.0.3/scripts/lib/codex.mjs:908-961`, read 2026-09-16), so a seat's criteria prompt and output schema are silently discarded and the answer comes back in Codex's report shape. The owner ruled on 2026-09-16 that `--kind final` routes through `runAppServerTurn` with the branch diff in the prompt.
- That ruling also said "with this plugin's own schema". The final round has none, and the nearest candidates are the task and plan review schemas, whose axes are wrong for a whole-branch review. Inventing one would change what `plugins/dr-superpowers/reference/final-review.md:44-49` deduplicates, and that file is outside this plan's scope. `--kind final` therefore keeps `schemaPath` null and keeps returning markdown findings. This is the one narrowing of the ruling and it is raised with the owner.
- `reference/ladder.md`'s `codex-judge` block bounds both rows at 1800 seconds — read 2026-09-16. No suite can reach the timeout branch against that, so Task 7 gives `LADDER` the same environment override `ROSTER` and `GATE` already have at `plugins/dr-superpowers/scripts/run-codex-review.sh:18,21`.
- `plugins/dr-superpowers/tests/run-codex-task.test.sh` has no `$TMP/bin/codex` stub, and no `$TMP/bin` directory at all: its only PATH shim is the `nojq` one at lines 176-178, which writes `$TMP/nojq/dirname`. Every case it runs is a `--dry-run`. Verified 2026-09-16. Task 13 therefore rewrites argv assertions rather than deleting a stub, and Tasks 10 and 13 keep the plugin locator out of the dry-run path so that suite needs no plugin fixture.
- `run-codex-task.sh` polls rather than wrapping in `timeout` because a wrapper process defeats `taskkill`'s native tree-walk — `plugins/dr-superpowers/scripts/run-codex-task.sh:282-287`, read 2026-09-16. Task 11 preserves that reasoning in the reaper.

## Task index

1. Stub Codex plugin fixture
2. codex-client.mjs: request, dispatch and result
3. codex-client.mjs: deadline and interrupt
4. codex-client.mjs: the broker reaper
5. codex-client.mjs: refusal and quota classification
6. run-codex-review.sh: run the seat through the client
7. run-codex-review.sh: drop the catalog and dry-run argv
8. detect-executors.sh: drop the models_cache read
9. detect-executors.sh: presence and auth through the plugin
10. run-codex-task.sh: run the task through the client
11. run-codex-task.sh: reap through the client
12. tests/codex-review.test.sh: update for the client path
13. detect.test.sh and run-codex-task.test.sh: update for the plugin path
14. reference/external-executor.md: retire the catalog prose
15. Calibration and smoke notes
16. README, manifests and the program amendment

---

### Task 1: Stub Codex plugin fixture

**Files:**
- Create: `plugins/dr-superpowers/tests/fixtures/stub-codex-plugin/.claude-plugin/plugin.json`
- Create: `plugins/dr-superpowers/tests/fixtures/stub-codex-plugin/scripts/lib/codex.mjs`
- Create: `plugins/dr-superpowers/tests/fixtures/stub-codex-plugin/scripts/lib/app-server.mjs`
- Create: `plugins/dr-superpowers/tests/fixtures/stub-codex-plugin/scripts/lib/broker-lifecycle.mjs`

**Interfaces:**
- Consumes: nothing.
- Produces: the stub fixture contract in Contracts. Every later suite points `codex-client.mjs` at this tree instead of a real plugin.

- [ ] **Step 1: Create the fixture manifest**

`plugins/dr-superpowers/tests/fixtures/stub-codex-plugin/.claude-plugin/plugin.json`:

```json
{
  "name": "codex",
  "version": "1.0.3",
  "description": "Stub of the official codex plugin, for dr-superpowers tests only."
}
```

- [ ] **Step 2: Create the stub codex.mjs**

`plugins/dr-superpowers/tests/fixtures/stub-codex-plugin/scripts/lib/codex.mjs`:

```javascript
// Stub of codex@openai-codex 1.0.3 scripts/lib/codex.mjs, for dr-superpowers
// tests. Behaviour is scripted by STUB_* environment variables so a suite can
// drive every branch of codex-client.mjs without a real Codex, a real account
// or a real broker.
import fs from "node:fs";

const mode = () => process.env.STUB_MODE || "ok";

function log(entry) {
  const file = process.env.STUB_EVENT_LOG;
  if (!file) return;
  try {
    fs.appendFileSync(file, `${entry}\n`);
  } catch {
    // A test that cannot write its own log will fail on the assertion instead.
  }
}

export function getCodexAvailability() {
  if (mode() === "unavailable") {
    return { available: false, detail: "stub: codex not installed" };
  }
  return { available: true, detail: "stub: codex 0.0.0-stub" };
}

// The real plugin returns `loggedIn`, not `authenticated` (codex.mjs:831-864).
// The field name is copied from the source deliberately: a stub invented from
// the plan would let the suite pass while production reported logged-out
// forever.
export async function getCodexAuthStatus() {
  log("getCodexAuthStatus");
  if (mode() === "throw") {
    throw new Error("stub: app-server exploded");
  }
  if (mode() === "unavailable") {
    return { available: false, loggedIn: false, detail: "stub: codex not installed", source: "availability" };
  }
  if (mode() === "logged-out") {
    return { available: true, loggedIn: false, detail: "stub: not logged in", source: "app-server" };
  }
  return { available: true, loggedIn: true, detail: "stub: logged in", source: "app-server" };
}

export async function interruptAppServerTurn(cwd, { threadId, turnId } = {}) {
  log(`interruptAppServerTurn ${threadId || "-"} ${turnId || "-"}`);
  if (!threadId || !turnId) {
    return { attempted: false, interrupted: false, transport: null, detail: "missing threadId or turnId" };
  }
  return { attempted: true, interrupted: true, transport: "stub", detail: `Interrupted ${turnId}.` };
}

// STUB_REFUSE_ONCE makes only the first call refuse, so a suite can prove the
// fallback rung succeeds; STUB_MODE=refusal refuses every call, which proves
// the FAILED path instead.
//
// The count lives in a file, not in a module-level variable. run-codex-review.sh
// spawns a fresh `node` process per seat, so a module counter is back at zero on
// the fallback rung and the first call refuses again: the FALLBACK outcome would
// be unreachable and the suite would certify a path nothing runs.
let calls = 0;

function bumpCalls() {
  const file = process.env.STUB_CALL_FILE;
  if (!file) {
    calls += 1;
    return calls;
  }
  let n = 0;
  try {
    n = Number(fs.readFileSync(file, "utf8").trim()) || 0;
  } catch {
    n = 0;
  }
  n += 1;
  try {
    fs.writeFileSync(file, String(n));
  } catch {
    // A suite that cannot write its own counter fails on its assertion instead.
  }
  return n;
}

async function turn(cwd, options, label) {
  const n = bumpCalls();
  log(`${label} ${options.model || "-"}/${options.effort || "-"}`);
  let m = mode();
  if (n > 1 && process.env.STUB_SECOND_MODE) m = process.env.STUB_SECOND_MODE;
  if (process.env.STUB_REFUSE_ONCE === "1") {
    m = n === 1 ? "refusal" : (process.env.STUB_SECOND_MODE || "ok");
  }
  // A turn against a logged-out account fails at the turn, not at an auth probe:
  // getCodexAuthStatus is only reached by op:"auth". Without this branch the
  // logged-out case would return status 0 and the suite would assert nothing.
  if (m === "logged-out") {
    return {
      status: 1, threadId: "stub-thread", turnId: "stub-turn", finalMessage: null,
      error: { message: "stream error: 401 unauthorized" }, stderr: "ERROR: 401 unauthorized\n"
    };
  }
  if (m === "unavailable") {
    throw new Error("Codex CLI is not installed or is missing required runtime support.");
  }
  if (m === "throw") {
    throw new Error("stub: app-server exploded");
  }
  // The progress reporter is how codex-client learns the ids it needs to
  // interrupt, so the stub emits them exactly as the real plugin does.
  options.onProgress?.({ message: "Thread ready (stub-thread).", phase: "starting", threadId: "stub-thread" });
  options.onProgress?.({ message: "Turn started.", phase: "running", threadId: "stub-thread", turnId: "stub-turn" });
  if (m === "hang") {
    await new Promise(() => {});
  }
  if (m === "refusal") {
    return {
      status: 1, threadId: "stub-thread", turnId: "stub-turn", finalMessage: null,
      error: { message: "unsupported model for this account" }, stderr: "ERROR: unsupported model\n"
    };
  }
  if (m === "quota") {
    return {
      status: 1, threadId: "stub-thread", turnId: "stub-turn", finalMessage: null,
      error: { message: "You've hit your usage limit." }, stderr: "ERROR: usage limit\n"
    };
  }
  return {
    status: Number(process.env.STUB_TURN_STATUS || 0),
    threadId: "stub-thread", turnId: "stub-turn",
    finalMessage: process.env.STUB_EMPTY === "1" ? "" : (process.env.STUB_FINAL_MESSAGE ?? '{"ok":true}'),
    error: null, stderr: ""
  };
}

export async function runAppServerTurn(cwd, options = {}) {
  return turn(cwd, options, "runAppServerTurn");
}

// There is deliberately no runAppServerReview here. The real one reads only
// model, threadName, target and delivery (codex.mjs:908-961) and answers in
// Codex's own report shape, so it cannot carry a seat's criteria prompt or
// output schema. codex-client.mjs never calls it, and a stub that offered it
// would let a suite certify a path production does not take.

export function parseStructuredOutput(raw, fallback = {}) {
  try {
    return JSON.parse(raw);
  } catch {
    return fallback;
  }
}

export function readOutputSchema(schemaPath) {
  return JSON.parse(fs.readFileSync(schemaPath, "utf8"));
}
```

- [ ] **Step 3: Create the stub app-server.mjs**

`plugins/dr-superpowers/tests/fixtures/stub-codex-plugin/scripts/lib/app-server.mjs`:

```javascript
// Stub of the plugin's app-server module. codex-client.mjs never imports it,
// but scripts/codex-plugin checks that this file exists before calling a root
// usable, so the fixture must carry it.
export const BROKER_ENDPOINT_ENV = "CODEX_COMPANION_APP_SERVER_ENDPOINT";
export const BROKER_BUSY_RPC_CODE = -32001;

export class CodexAppServerClient {
  static async connect() {
    throw new Error("stub: the app-server client is not used by codex-client.mjs");
  }
}
```

- [ ] **Step 4: Create the stub broker-lifecycle.mjs**

`plugins/dr-superpowers/tests/fixtures/stub-codex-plugin/scripts/lib/broker-lifecycle.mjs`:

```javascript
// Stub of the plugin's broker lifecycle module. The reaper in codex-client.mjs
// drives these, so the stub records every call and lets a suite script whether
// a broker session exists at all.
import fs from "node:fs";

function log(entry) {
  const file = process.env.STUB_EVENT_LOG;
  if (!file) return;
  try {
    fs.appendFileSync(file, `${entry}\n`);
  } catch {
    // A test that cannot write its own log will fail on the assertion instead.
  }
}

export const PID_FILE_ENV = "CODEX_COMPANION_APP_SERVER_PID_FILE";
export const LOG_FILE_ENV = "CODEX_COMPANION_APP_SERVER_LOG_FILE";

// The client asks twice: once before the turn, to learn whether a broker it
// must not touch already exists, and once after a shutdown, to learn whether
// the broker actually died. The stub models that sequence rather than a single
// boolean, because the pre-existing case is the one that protects the user's
// own /codex:* session.
let loads = 0;

export function loadBrokerSession() {
  log("loadBrokerSession");
  loads += 1;
  const session = { endpoint: "stub-endpoint", pidFile: "stub.pid", logFile: "stub.log", sessionDir: "stub-dir", pid: 4242 };
  if (loads === 1) {
    // The pre-turn probe.
    return process.env.STUB_PRE_EXISTING === "1" ? session : null;
  }
  return process.env.STUB_NO_BROKER === "1" ? null : session;
}

// The real sendBrokerShutdown resolves undefined (broker-lifecycle.mjs:43-57):
// it reports nothing about whether the broker died. The stub returns undefined
// too, so no caller can be written against a truthiness that does not exist.
// STUB_SHUTDOWN_FAILS instead leaves the session in place, which is what the
// caller must actually probe for.
export async function sendBrokerShutdown(endpoint) {
  log(`sendBrokerShutdown ${endpoint}`);
  if (process.env.STUB_SHUTDOWN_FAILS !== "1") process.env.STUB_NO_BROKER = "1";
}

export function teardownBrokerSession({ pid } = {}) {
  log(`teardownBrokerSession ${pid ?? "-"}`);
  return true;
}

export function clearBrokerSession() {
  log("clearBrokerSession");
}
```

- [ ] **Step 5: Verify the fixture imports cleanly**

Run:

```bash
node -e "import('./plugins/dr-superpowers/tests/fixtures/stub-codex-plugin/scripts/lib/codex.mjs').then(m => console.log(typeof m.runAppServerTurn, typeof m.getCodexAuthStatus, typeof m.runAppServerReview))"
```

Expected: `function function undefined` — the third word proves the review entry
point is absent, which is what stops a suite certifying it.

- [ ] **Step 6: Commit**

```bash
git add plugins/dr-superpowers/tests/fixtures/stub-codex-plugin
git commit -m "test(superpowers): add a stub codex plugin fixture"
```

**Implementer:** dr-superpowers:impl-sonnet-low
**Evaluation:** files 1 - spec 0 - coupling 0 - risk 0 = 1

---

### Task 2: codex-client.mjs: request, dispatch and result

**Files:**
- Create: `plugins/dr-superpowers/scripts/lib/codex-client.mjs`
- Create: `plugins/dr-superpowers/tests/codex-client.test.sh`

**Interfaces:**
- Consumes: the stub fixture contract (Task 1).
- Produces: the `codex-client.mjs` interface in Contracts. Tasks 3, 4 and 5 extend this file; Tasks 6, 9 and 10 call it.

- [ ] **Step 1: Write the failing test**

Create `plugins/dr-superpowers/tests/codex-client.test.sh`:

```bash
#!/usr/bin/env bash
# codex-client.mjs is the only new file that imports the Codex plugin. Every
# case here drives it against the Task 1 stub: no real Codex, no real broker,
# no read of this machine's Claude config.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
P="$HERE/.."
STUB="$HERE/fixtures/stub-codex-plugin"
CLIENT="$P/scripts/lib/codex-client.mjs"

export DR_CODEX_SESSION_DIR="$(mktemp -d)"
export CLAUDE_CODE_SESSION_ID=codex-client-test-session

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP" "$DR_CODEX_SESSION_DIR"' EXIT

run() { # run <request-json>; echoes the result JSON
  printf '%s' "$1" | node "$CLIENT" "$STUB" 2>"$TMP/stderr"
}

req() { # req <extra-json>
  jq -nc --arg cwd "$TMP" --argjson extra "$1" \
    '{op:"turn", kind:"task", cwd:$cwd, model:"gpt-5.6-sol", effort:"high",
      prompt:"review this", schemaPath:null, sandbox:"read-only",
      resumeThreadId:null, persistThread:false, threadName:null,
      deadlineMs:5000} + $extra'
}

# --- a plain turn succeeds ---
export STUB_MODE=ok STUB_FINAL_MESSAGE='{"spec_verdict":"met"}'
out=$(run "$(req '{}')")
check "turn: ok is true" "$(jq -r '.ok' <<<"$out")" "true"
check "turn: turnStatus is 0" "$(jq -r '.turnStatus' <<<"$out")" "0"
check "turn: finalMessage passes through" "$(jq -r '.finalMessage' <<<"$out")" '{"spec_verdict":"met"}'
check "turn: threadId captured" "$(jq -r '.threadId' <<<"$out")" "stub-thread"
check "turn: turnId captured" "$(jq -r '.turnId' <<<"$out")" "stub-turn"
check "turn: reason is null" "$(jq -r '.reason' <<<"$out")" "null"

# --- every kind runs one plain turn; nothing reaches a review entry point ---
export STUB_EVENT_LOG="$TMP/events.log"
: > "$STUB_EVENT_LOG"
run "$(req '{"kind":"final"}')" >/dev/null
check "final: routes to runAppServerTurn" \
  "$(grep -c '^runAppServerTurn' "$STUB_EVENT_LOG")" "1"
: > "$STUB_EVENT_LOG"
run "$(req '{}')" >/dev/null
check "task: routes to runAppServerTurn" \
  "$(grep -c '^runAppServerTurn' "$STUB_EVENT_LOG")" "1"
unset STUB_EVENT_LOG

# --- a plugin that will not import fails closed ---
out=$(printf '%s' "$(req '{}')" | node "$CLIENT" "$TMP/not-a-plugin" 2>/dev/null)
check "missing plugin: ok is false" "$(jq -r '.ok' <<<"$out")" "false"
check "missing plugin: reason" "$(jq -r '.reason' <<<"$out")" "plugin-api"

# --- an unavailable codex fails closed ---
export STUB_MODE=unavailable
out=$(run "$(req '{}')")
check "unavailable: ok is false" "$(jq -r '.ok' <<<"$out")" "false"
check "unavailable: reason" "$(jq -r '.reason' <<<"$out")" "unavailable"
export STUB_MODE=ok

# --- a malformed request is rejected, not guessed at ---
out=$(printf 'not json' | node "$CLIENT" "$STUB" 2>/dev/null)
check "bad request: ok is false" "$(jq -r '.ok' <<<"$out")" "false"
check "bad request: reason" "$(jq -r '.reason' <<<"$out")" "bad-request"
out=$(run "$(jq -nc '{op:"turn", kind:"task"}')")
check "missing cwd: reason" "$(jq -r '.reason' <<<"$out")" "bad-request"

# --- the process always exits 0 so bash reads the JSON, not an exit code ---
printf '%s' "$(req '{}')" | node "$CLIENT" "$STUB" >/dev/null 2>&1
check "exit code is always 0" "$?" "0"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash plugins/dr-superpowers/tests/codex-client.test.sh`
Expected: FAIL — `node: Cannot find module .../scripts/lib/codex-client.mjs`, every check failing.

- [ ] **Step 3: Write the implementation**

Create `plugins/dr-superpowers/scripts/lib/codex-client.mjs`:

```javascript
// The one new seam between dr-superpowers and the official codex plugin.
//
// Usage: node codex-client.mjs <plugin-root>   (request JSON on stdin)
// Prints one JSON result object on stdout and always exits 0: the caller is
// bash, which owns the argv contract, the status line and the exit code, and it
// must be able to read a result rather than infer one from a signal.
//
// <plugin-root> is already vetted. scripts/codex-plugin resolved it for the
// active profile and enforced the version allowlist; nothing here re-checks
// that, and nothing here names the codex executable.
import path from "node:path";
import { pathToFileURL } from "node:url";

const EMPTY = {
  ok: false, turnStatus: null, threadId: null, turnId: null, finalMessage: null,
  refusal: false, quota: false, timedOut: false, interrupted: false,
  reaped: false, reason: null, stderr: ""
};

// Awaited at every call site, and it never resolves: the process ends inside the
// write callback instead. A bare write followed by process.exit truncates a long
// finalMessage, because a write to a pipe is asynchronous on Windows and every
// result now travels this path. Returning normally is not an option either -
// nothing after an emit may run.
function emit(fields) {
  process.stdout.write(`${JSON.stringify({ ...EMPTY, ...fields })}\n`, () => process.exit(0));
  return new Promise(() => {});
}

async function readStdin() {
  const chunks = [];
  for await (const chunk of process.stdin) chunks.push(chunk);
  return Buffer.concat(chunks).toString("utf8");
}

function parseRequest(raw) {
  let req;
  try {
    req = JSON.parse(raw);
  } catch {
    return null;
  }
  if (!req || typeof req !== "object") return null;
  if (typeof req.cwd !== "string" || req.cwd === "") return null;
  if (req.op !== "turn" && req.op !== "auth") return null;
  return req;
}

async function loadPlugin(root) {
  return import(pathToFileURL(path.join(root, "scripts", "lib", "codex.mjs")).href);
}

async function main() {
  const root = process.argv[2];
  if (!root) await emit({ reason: "bad-request", stderr: "a plugin root is required" });

  const req = parseRequest(await readStdin());
  if (!req) await emit({ reason: "bad-request", stderr: "the request is not a valid turn or auth object" });

  let plugin;
  try {
    plugin = await loadPlugin(root);
  } catch (error) {
    await emit({ reason: "plugin-api", stderr: String(error?.message ?? error) });
  }

  const availability = plugin.getCodexAvailability?.(req.cwd);
  if (availability && availability.available === false) {
    await emit({ reason: "unavailable", stderr: String(availability.detail ?? "codex is unavailable") });
  }

  if (req.op === "auth") {
    try {
      // `loggedIn`, not `authenticated`: codex.mjs:831-864 is the shape.
      const status = await plugin.getCodexAuthStatus(req.cwd);
      const authed = status?.loggedIn === true;
      await emit({
        ok: authed, authed, reason: authed ? null : "logged-out",
        stderr: String(status?.detail ?? "")
      });
    } catch (error) {
      await emit({ reason: "plugin-api", authed: null, stderr: String(error?.message ?? error) });
    }
  }

  // The progress reporter is the only place a thread id and a turn id surface
  // while the turn is still running, which is what Task 3's deadline needs to
  // interrupt rather than merely abandon.
  const seen = { threadId: null, turnId: null };
  const onProgress = (update) => {
    if (typeof update !== "object" || update === null) return;
    if (update.threadId) seen.threadId = update.threadId;
    if (update.turnId) seen.turnId = update.turnId;
  };

  let outputSchema = null;
  if (req.schemaPath) {
    try {
      outputSchema = plugin.readOutputSchema(req.schemaPath);
    } catch (error) {
      await emit({ reason: "bad-request", stderr: `cannot read output schema: ${String(error?.message ?? error)}` });
    }
  }

  const options = {
    model: req.model ?? null,
    effort: req.effort ?? null,
    prompt: req.prompt ?? "",
    sandbox: req.sandbox ?? null,
    outputSchema,
    resumeThreadId: req.resumeThreadId ?? null,
    persistThread: req.persistThread === true,
    threadName: req.threadName ?? null,
    onProgress
  };
  // Every kind runs one plain turn. runAppServerReview is never called: it reads
  // only model, threadName, target and delivery (codex.mjs:908-961), starts its
  // own read-only thread and answers in Codex's report shape, so a seat's
  // criteria prompt and output schema would be discarded. `--kind final` arrives
  // with its criteria and the branch diff already in `prompt`, composed by
  // run-codex-review.sh.
  let result;
  try {
    result = await plugin.runAppServerTurn(req.cwd, options);
  } catch (error) {
    await emit({
      reason: "plugin-api", threadId: seen.threadId, turnId: seen.turnId,
      stderr: String(error?.message ?? error)
    });
  }

  const turnStatus = typeof result?.status === "number" ? result.status : null;
  await emit({
    ok: turnStatus === 0,
    turnStatus,
    threadId: result?.threadId ?? seen.threadId,
    turnId: result?.turnId ?? seen.turnId,
    finalMessage: result?.finalMessage ?? null,
    reason: turnStatus === 0 ? null : "plugin-api",
    stderr: String(result?.stderr ?? "")
  });
}

// No await here: nothing follows, and emit ends the process itself.
main().catch((error) => emit({ reason: "plugin-api", stderr: String(error?.message ?? error) }));
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash plugins/dr-superpowers/tests/codex-client.test.sh`
Expected: PASS — `16 passed, 0 failed`

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-superpowers/scripts/lib/codex-client.mjs plugins/dr-superpowers/tests/codex-client.test.sh
git update-index --chmod=+x plugins/dr-superpowers/tests/codex-client.test.sh
git commit -m "feat(superpowers): add the codex client seam"
```

**Implementer:** dr-superpowers:impl-opus-medium
**Evaluation:** files 1 - spec 0 - coupling 2 - risk 2 = 5

---

### Task 3: codex-client.mjs: deadline and interrupt

**Files:**
- Modify: `plugins/dr-superpowers/scripts/lib/codex-client.mjs`
- Modify: `plugins/dr-superpowers/tests/codex-client.test.sh`

**Interfaces:**
- Consumes: the `codex-client.mjs` interface and stub fixture contract in Contracts.
- Produces: `timedOut` and `interrupted` on the result, consumed by Tasks 6 and 10.

- [ ] **Step 1: Write the failing test**

Append to `plugins/dr-superpowers/tests/codex-client.test.sh`, immediately before the final `printf '\n%d passed'` line:

```bash
# --- the deadline interrupts rather than merely abandoning ---
export STUB_MODE=hang STUB_EVENT_LOG="$TMP/deadline.log"
: > "$STUB_EVENT_LOG"
out=$(run "$(req '{"deadlineMs":300}')")
check "deadline: ok is false" "$(jq -r '.ok' <<<"$out")" "false"
check "deadline: timedOut is true" "$(jq -r '.timedOut' <<<"$out")" "true"
check "deadline: reason" "$(jq -r '.reason' <<<"$out")" "timeout"
check "deadline: interrupted is true" "$(jq -r '.interrupted' <<<"$out")" "true"
check "deadline: interrupt carried both ids" \
  "$(grep -c '^interruptAppServerTurn stub-thread stub-turn' "$STUB_EVENT_LOG")" "1"
unset STUB_EVENT_LOG
export STUB_MODE=ok

# --- a turn that finishes in time is never interrupted ---
export STUB_EVENT_LOG="$TMP/no-interrupt.log"
: > "$STUB_EVENT_LOG"
run "$(req '{}')" >/dev/null
check "fast turn: no interrupt" "$(grep -c '^interruptAppServerTurn' "$STUB_EVENT_LOG")" "0"
unset STUB_EVENT_LOG
```

- [ ] **Step 2: Run it to verify it fails**

Run: `timeout 30 bash plugins/dr-superpowers/tests/codex-client.test.sh`
Expected: FAIL — the deadline checks fail because the run never returns; the suite hangs until the stub's `hang` mode is cut off by the harness. Confirm the failure is the missing deadline, not a syntax error, by running with `timeout 30 bash …` and seeing it killed.

- [ ] **Step 3: Write the implementation**

In `plugins/dr-superpowers/scripts/lib/codex-client.mjs`, replace the `let result;` block and everything to the end of `main()` with:

```javascript
  // The deadline is ours, not coreutils timeout: on Windows `timeout` kills
  // only node and strands the app-server it spawned. Interrupting needs both
  // ids, which is why they are captured from progress above.
  const deadlineMs = Number(req.deadlineMs) > 0 ? Number(req.deadlineMs) : 600000;
  let timedOut = false;
  let interrupted = false;
  let timer = null;

  const expiry = new Promise((resolve) => {
    timer = setTimeout(async () => {
      timedOut = true;
      try {
        const outcome = await plugin.interruptAppServerTurn(req.cwd, {
          threadId: seen.threadId,
          turnId: seen.turnId
        });
        interrupted = outcome?.interrupted === true;
      } catch {
        // An interrupt that fails leaves the reaper as the remaining recourse.
      }
      resolve(null);
    }, deadlineMs);
  });

  let result;
  try {
    result = await Promise.race([plugin.runAppServerTurn(req.cwd, options), expiry]);
  } catch (error) {
    clearTimeout(timer);
    await emit({
      reason: "plugin-api", threadId: seen.threadId, turnId: seen.turnId,
      stderr: String(error?.message ?? error)
    });
  }
  clearTimeout(timer);

  if (timedOut) {
    await emit({
      reason: "timeout", timedOut: true, interrupted,
      threadId: seen.threadId, turnId: seen.turnId,
      stderr: "the deadline expired"
    });
  }

  const turnStatus = typeof result?.status === "number" ? result.status : null;
  await emit({
    ok: turnStatus === 0,
    turnStatus,
    threadId: result?.threadId ?? seen.threadId,
    turnId: result?.turnId ?? seen.turnId,
    finalMessage: result?.finalMessage ?? null,
    reason: turnStatus === 0 ? null : "plugin-api",
    stderr: String(result?.stderr ?? "")
  });
}

// No await here: nothing follows, and emit ends the process itself.
main().catch((error) => emit({ reason: "plugin-api", stderr: String(error?.message ?? error) }));
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `timeout 120 bash plugins/dr-superpowers/tests/codex-client.test.sh`
Expected: PASS — `22 passed, 0 failed`

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-superpowers/scripts/lib/codex-client.mjs plugins/dr-superpowers/tests/codex-client.test.sh
git commit -m "feat(superpowers): interrupt a turn on the deadline"
```

**Implementer:** dr-superpowers:impl-opus-low
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 2 = 4

---

### Task 4: codex-client.mjs: the broker reaper

**Files:**
- Modify: `plugins/dr-superpowers/scripts/lib/codex-client.mjs`
- Modify: `plugins/dr-superpowers/tests/codex-client.test.sh`

**Interfaces:**
- Consumes: the `codex-client.mjs` interface and stub fixture contract in Contracts.
- Produces: `reaped` on the result, and the guarantee that no run leaves a broker behind. Task 11 relies on this instead of killing a process tree itself.

- [ ] **Step 1: Write the failing test**

Append to `plugins/dr-superpowers/tests/codex-client.test.sh`, before the final `printf`:

```bash
# --- every run reaps the broker it caused to exist ---
export STUB_EVENT_LOG="$TMP/reap.log"
: > "$STUB_EVENT_LOG"
out=$(run "$(req '{}')")
check "reap: reaped is true" "$(jq -r '.reaped' <<<"$out")" "true"
check "reap: shutdown sent" "$(grep -c '^sendBrokerShutdown stub-endpoint' "$STUB_EVENT_LOG")" "1"
check "reap: session cleared" "$(grep -c '^clearBrokerSession' "$STUB_EVENT_LOG")" "1"

# --- a shutdown that does not land escalates to teardown ---
: > "$STUB_EVENT_LOG"
export STUB_SHUTDOWN_FAILS=1
out=$(run "$(req '{}')")
check "reap: teardown when the session survives shutdown"   "$(grep -c '^teardownBrokerSession 4242' "$STUB_EVENT_LOG")" "1"
check "reap: still reports reaped" "$(jq -r '.reaped' <<<"$out")" "true"
unset STUB_SHUTDOWN_FAILS

# --- a broker that already existed belongs to someone else and survives ---
: > "$STUB_EVENT_LOG"
export STUB_PRE_EXISTING=1
out=$(run "$(req '{}')")
check "reap: a pre-existing broker is not reaped" "$(jq -r '.reaped' <<<"$out")" "false"
check "reap: no shutdown sent to someone else's broker"   "$(grep -c '^sendBrokerShutdown' "$STUB_EVENT_LOG")" "0"
unset STUB_PRE_EXISTING

# --- a timed-out run still reaps ---
: > "$STUB_EVENT_LOG"
export STUB_MODE=hang
out=$(run "$(req '{"deadlineMs":300}')")
check "reap: a timeout still reaps" "$(jq -r '.reaped' <<<"$out")" "true"
export STUB_MODE=ok
unset STUB_EVENT_LOG
```

- [ ] **Step 2: Run it to verify it fails**

Run: `timeout 120 bash plugins/dr-superpowers/tests/codex-client.test.sh`
Expected: FAIL — every reap check fails; `reaped` is `false` and no broker call is logged.

- [ ] **Step 3: Write the implementation**

In `plugins/dr-superpowers/scripts/lib/codex-client.mjs`, add this function directly above `async function main()`:

```javascript
// runAppServerTurn connects without disableBroker, so it spawns a detached
// broker when none is running. The plugin's own SessionEnd hook owns that
// daemon, and that hook does not run in a profile where the plugin is not
// enabled - which is the profile this plugin is developed in. So every run
// shuts down the broker it caused to exist, or it leaks one per run.
async function reap(root, cwd) {
  let lifecycle;
  try {
    lifecycle = await import(
      pathToFileURL(path.join(root, "scripts", "lib", "broker-lifecycle.mjs")).href
    );
  } catch {
    return false;
  }
  let session;
  try {
    session = lifecycle.loadBrokerSession(cwd);
  } catch {
    return false;
  }
  if (!session) return false;

  // sendBrokerShutdown resolves undefined: it reports nothing about whether the
  // broker died (broker-lifecycle.mjs:43-57). So ask afterwards rather than
  // believing a return value that does not exist - treating undefined as
  // failure would taskkill a healthy shutdown's PID, which may already be
  // reused by then.
  try {
    await lifecycle.sendBrokerShutdown(session.endpoint);
  } catch {
    // An unreachable endpoint is already down, or never came up.
  }
  let down = true;
  try {
    down = lifecycle.loadBrokerSession(cwd) === null;
  } catch {
    down = false;
  }
  if (!down) {
    try {
      // killProcess carries the Windows knowledge run-codex-task.sh proved:
      // taskkill walks the native process tree, and a plain kill leaves the
      // node children of the broker running.
      lifecycle.teardownBrokerSession({ ...session, killProcess: killTree });
    } catch {
      // Nothing further is available; the caller reports reaped=false.
    }
  }
  try {
    lifecycle.clearBrokerSession(cwd);
  } catch {
    // A session file we cannot clear is stale, not fatal.
  }
  return true;
}

function killTree(pid) {
  if (!pid) return;
  if (process.platform === "win32") {
    spawnSync("taskkill", ["/F", "/T", "/PID", String(pid)], { stdio: "ignore" });
    return;
  }
  try {
    process.kill(pid, "SIGTERM");
  } catch {
    // Already gone.
  }
}
```

Add this import at the top of the file, below the existing two:

```javascript
import { spawnSync } from "node:child_process";
```

Then make every turn path reap before it emits. Replace the `emit` helper with:

```javascript
let reapContext = null;

async function emit(fields) {
  let reaped = false;
  if (reapContext) {
    const { root, cwd } = reapContext;
    reapContext = null;
    try {
      reaped = await reap(root, cwd);
    } catch {
      reaped = false;
    }
  }
  process.stdout.write(`${JSON.stringify({ ...EMPTY, ...fields, reaped })}\n`, () => process.exit(0));
  return new Promise(() => {});
}
```

**No call site changes.** Task 2 already wrote `await emit(...)` everywhere and
Task 3 added one more, so the helper can become `async` in place. Confirm that
before moving on:

```bash
grep -c 'await emit(' plugins/dr-superpowers/scripts/lib/codex-client.mjs
```

Expected: `10` — nine sites from Task 2 plus the deadline emit from Task 3. The
only other reference is `main().catch((error) => emit(...))`, which needs no
`await` because nothing follows it.

Set the context immediately after the request parses and the plugin loads, directly before the `op === "auth"` branch:

```javascript
  // Only a broker this run caused to exist may be reaped. The broker session is
  // keyed by workspace root and CLAUDE_PLUGIN_DATA, not by who spawned it, so a
  // session that already existed belongs to the user's own /codex:* work and
  // must survive. Recording its absence here is what makes the reap safe.
  let preExisting = null;
  try {
    const lifecycle = await import(
      pathToFileURL(path.join(root, "scripts", "lib", "broker-lifecycle.mjs")).href
    );
    preExisting = lifecycle.loadBrokerSession(req.cwd);
  } catch {
    preExisting = null;
  }
  reapContext = preExisting ? null : { root, cwd: req.cwd };
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `timeout 120 bash plugins/dr-superpowers/tests/codex-client.test.sh`
Expected: PASS — `30 passed, 0 failed` (16 from Task 2, 6 from Task 3, 8 here).

- [ ] **Step 5: Verify no broker leaks on the happy path**

Run:

```bash
STUB_EVENT_LOG=/tmp/reapcheck.log bash -c 'printf "%s" "{\"op\":\"turn\",\"kind\":\"task\",\"cwd\":\"$PWD\",\"deadlineMs\":5000}" | node plugins/dr-superpowers/scripts/lib/codex-client.mjs plugins/dr-superpowers/tests/fixtures/stub-codex-plugin >/dev/null; grep -c sendBrokerShutdown /tmp/reapcheck.log'
```

Expected: `1`

- [ ] **Step 6: Commit**

```bash
git add plugins/dr-superpowers/scripts/lib/codex-client.mjs plugins/dr-superpowers/tests/codex-client.test.sh
git commit -m "feat(superpowers): reap the broker every run"
```

**Implementer:** dr-superpowers:impl-opus-low
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 2 = 4

---

### Task 5: codex-client.mjs: refusal and quota classification

**Files:**
- Modify: `plugins/dr-superpowers/scripts/lib/codex-client.mjs`
- Modify: `plugins/dr-superpowers/tests/codex-client.test.sh`

**Interfaces:**
- Consumes: the `codex-client.mjs` interface and stub fixture contract in Contracts.
- Produces: `refusal` and `quota` on the result, consumed by Tasks 6 and 10 in place of grepping a transcript.

- [ ] **Step 1: Write the failing test**

Append to `plugins/dr-superpowers/tests/codex-client.test.sh`, before the final `printf`:

```bash
# --- a refusal is classified from the result, not grepped from a transcript ---
export STUB_MODE=refusal
out=$(run "$(req '{}')")
check "refusal: ok is false" "$(jq -r '.ok' <<<"$out")" "false"
check "refusal: refusal is true" "$(jq -r '.refusal' <<<"$out")" "true"
check "refusal: quota is false" "$(jq -r '.quota' <<<"$out")" "false"
check "refusal: reason" "$(jq -r '.reason' <<<"$out")" "refusal"

# --- an exhausted quota is its own outcome, never a refusal ---
export STUB_MODE=quota
out=$(run "$(req '{}')")
check "quota: quota is true" "$(jq -r '.quota' <<<"$out")" "true"
check "quota: refusal is false" "$(jq -r '.refusal' <<<"$out")" "false"
check "quota: reason" "$(jq -r '.reason' <<<"$out")" "quota"
export STUB_MODE=ok

# --- prose that merely quotes a refusal is not a refusal ---
export STUB_TURN_STATUS=1 STUB_FINAL_MESSAGE='the reviewer wrote "unsupported model" in its report'
out=$(run "$(req '{}')")
check "quoted prose: not a refusal" "$(jq -r '.refusal' <<<"$out")" "false"
unset STUB_TURN_STATUS STUB_FINAL_MESSAGE
```

- [ ] **Step 2: Run it to verify it fails**

Run: `timeout 120 bash plugins/dr-superpowers/tests/codex-client.test.sh`
Expected: FAIL — `refusal` and `quota` are always `false` and `reason` is `plugin-api`.

- [ ] **Step 3: Write the implementation**

In `plugins/dr-superpowers/scripts/lib/codex-client.mjs`, add these constants directly below `const EMPTY = {...};`:

```javascript
// Classified from the result's own error, never from the transcript. The old
// bash runners searched captured stderr, where a review that merely quoted a
// refusal message read as a refusal: a 2026-09-14 --kind final run left 10,590
// stderr lines carrying 20 false matches.
const REFUSAL = /(unsupported|unknown|invalid|not (supported|available|found)).*(model|effort)|(model|effort).*(unsupported|unknown|invalid|not (supported|available|found))/i;
const QUOTA = /usage limit|rate_limit_reached/i;

function classify(result) {
  const message = String(result?.error?.message ?? "");
  if (!message) return { refusal: false, quota: false };
  if (QUOTA.test(message)) return { refusal: false, quota: true };
  if (REFUSAL.test(message)) return { refusal: true, quota: false };
  return { refusal: false, quota: false };
}
```

Replace the final `emit` call in `main()` with:

```javascript
  const turnStatus = typeof result?.status === "number" ? result.status : null;
  const { refusal, quota } = classify(result);
  let reason = null;
  if (turnStatus !== 0) {
    if (quota) reason = "quota";
    else if (refusal) reason = "refusal";
    else reason = "plugin-api";
  }
  await emit({
    ok: turnStatus === 0,
    turnStatus,
    threadId: result?.threadId ?? seen.threadId,
    turnId: result?.turnId ?? seen.turnId,
    finalMessage: result?.finalMessage ?? null,
    refusal, quota, reason,
    stderr: String(result?.stderr ?? "")
  });
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `timeout 120 bash plugins/dr-superpowers/tests/codex-client.test.sh`
Expected: PASS — `38 passed, 0 failed` (30 after Task 4, plus 8 here).

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-superpowers/scripts/lib/codex-client.mjs plugins/dr-superpowers/tests/codex-client.test.sh
git commit -m "feat(superpowers): classify refusal and quota from result"
```

**Implementer:** dr-superpowers:impl-sonnet-high
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 1 = 3

---

### Task 6: run-codex-review.sh: run the seat through the client

**Files:**
- Modify: `plugins/dr-superpowers/scripts/run-codex-review.sh:149-161,183-277` — `build_argv` at 153-161 with its comment, the refusal and quota helpers at 183-223, and the seat runner and outcome block at 228-277
- Create: `plugins/dr-superpowers/criteria/codex-final-review.md`

**Interfaces:**
- Consumes: the `codex-client.mjs` interface in Contracts.
- Produces: the status line in Contracts, unchanged in shape. Task 12 asserts on it.

- [ ] **Step 1: Replace the argv builder and seat runner**

In `plugins/dr-superpowers/scripts/run-codex-review.sh`, delete `build_argv()`,
`run_seat()`, `error_lines()`, `is_refusal()`, `is_quota()`, `refusal_line()` and
the `REFUSAL`/`QUOTA` constants. These are **not contiguous**: the `--dry-run`
block and `valid_output()` sit between them, and both stay. Insert the
replacement immediately **after** `valid_output()` and before the outcome block,
so the locator never runs on a `--dry-run` invocation:

```bash
# The plugin root, resolved once. scripts/codex-plugin owns the locator and the
# version allowlist; this script never names the codex executable.
#
# A locator refusal is a FAILED seat, not a usage error: spec section 7 maps
# locate and version failures to the status line, and exiting 2 here would make
# a caller that reads the line see nothing at all.
if ! plugin_line=$(bash "$HERE/codex-plugin"); then
  printf 'codex-judge none/none status=FAILED exit=0 out=%s evidence=none\n' "$out"
  printf 'run-codex-review: %s\n' "$plugin_line" >&2
  exit 1
fi
plugin_root=${plugin_line#*root=}

# One seat run, through the plugin's client. The client owns the deadline, the
# interrupt and the broker reaper; this script owns the argv contract, the
# status line and the exit code.
#
# --rawfile, not --arg "$(cat ...)": a reviewer prompt carries a whole branch
# diff and passing it as an argument blows the 32,767-character Windows
# CreateProcess limit.
run_seat() { # run_seat <model> <effort> <seconds> <log-prefix>; echoes the result JSON
  local request
  request=$(jq -nc \
    --arg kind "$kind" --arg cwd "$cwd" --arg model "$1" --arg effort "$2" \
    --rawfile prompt "${prompt:-/dev/null}" --arg schema "${schema:-}" \
    --argjson deadline "$(( $3 * 1000 ))" \
    '{op:"turn", kind:$kind, cwd:$cwd, model:$model, effort:$effort,
      prompt:$prompt,
      schemaPath:(if $schema == "" then null else $schema end),
      sandbox:"read-only", resumeThreadId:null, persistThread:false,
      threadName:null, deadlineMs:$deadline}')
  printf '%s' "$request" | node "$HERE/lib/codex-client.mjs" "$plugin_root" 2>"$4.stderr"
}

# --kind final ships no --prompt of its own: the round is defined by the branch.
# Its criteria and its diff are composed here, because the plugin call that would
# otherwise do this - runAppServerReview - reads only model, threadName, target
# and delivery (codex.mjs:908-961) and answers in Codex's own report shape,
# discarding the criteria a seat has to return.
#
# There is no $base in the request: it is consumed here and nowhere else.
compose_final_prompt() { # compose_final_prompt; echoes the composed prompt path
  local file="$out.prompt" diff="$out.diff"
  git -C "$cwd" diff "$base...HEAD" > "$diff" 2>"$out.diff.err" || return 1
  {
    cat "$HERE/../criteria/codex-final-review.md"
    printf '\n## The diff under review\n\n'
    printf '%s\n' '```diff'
    cat "$diff"
    printf '%s\n' '```'
  } > "$file" || return 1
  printf '%s' "$file"
}

# The report is whatever the seat returned. Writing it here rather than in the
# client keeps the --out contract with bash, which owns it.
write_out() { # write_out <result-json>
  jq -r '.finalMessage // ""' <<<"$1" > "$out"
}
```

- [ ] **Step 1b: Write the final round's criteria**

`--kind final` now sends this plugin's own instructions, so they have to exist as
a file. Create `plugins/dr-superpowers/criteria/codex-final-review.md`:

```markdown
# Final whole-branch review - criteria for the Codex seat

You are one of two independent reviewers of a branch. A third seat deduplicates
both lists afterwards, so report what you find and do not try to guess what the
other reviewer said.

The branch diff follows these criteria. Review that diff: the worktree is
available, but the diff is the change under review.

Report findings as markdown, most severe first, one per heading:

- `### <severity>: <one-line claim>`, where severity is Critical, Important or
  Minor.
- Under it, three lines. `File:` a `path:line` inside the diff. `Why:` the
  concrete failure - the input or state that reaches the defect and the wrong
  result it produces. `Fix:` one sentence.

A finding with no concrete failure is not a finding. Do not report style
preferences, do not restate what the code does, and do not praise. If you find
nothing, write `No findings.` and stop.
```

- [ ] **Step 2: Replace the outcome block**

Replace everything from `rc=$(run_seat "$model" "$effort" "$secs" "$out")` to the end of the file with:

```bash
# The final round composes its prompt from the branch; every other kind was
# given one on argv. A failure here is a FAILED seat, not a usage error: the
# caller reads the status line and would otherwise see nothing at all.
if [ "$kind" = final ]; then
  if ! prompt=$(compose_final_prompt); then
    printf 'codex-judge none/none status=FAILED exit=0 out=%s evidence=none\n' "$out"
    printf 'run-codex-review: cannot diff %s...HEAD in %s\n' "$base" "$cwd" >&2
    exit 1
  fi
fi

result=$(run_seat "$model" "$effort" "$secs" "$out")
write_out "$result"
rc=0
[ "$(jq -r '.ok' <<<"$result")" = true ] || rc=1
[ "$(jq -r '.timedOut' <<<"$result")" = true ] && rc=124

if [ "$rc" -eq 124 ]; then
  status "$model" "$effort" TIMEOUT "$rc"; exit 1
fi

if [ "$rc" -eq 0 ] && valid_output; then
  status "$model" "$effort" OK "$rc"; exit 0
fi

if [ "$(jq -r '.quota' <<<"$result")" = true ]; then
  codex_session_mark_off quota
  status "$model" "$effort" FAILED "$rc"; exit 1
fi

# The fallback is attempted at most once, and never when the row that just ran
# is already the fallback row.
if [ "$(jq -r '.refusal' <<<"$result")" = true ] \
   && { [ "$model" != "$back_model" ] || [ "$effort" != "$back_effort" ]; }; then
  printf 'run-codex-review: %s/%s refused (%s); falling back to %s/%s\n' \
    "$model" "$effort" "$(jq -r '.stderr' <<<"$result" | head -1)" \
    "$back_model" "$back_effort" >&2
  back_secs=$(secs_of "$back_model" "$back_effort")
  result=$(run_seat "$back_model" "$back_effort" "$back_secs" "$out.fallback")
  write_out "$result"
  rc=0
  [ "$(jq -r '.ok' <<<"$result")" = true ] || rc=1
  [ "$(jq -r '.timedOut' <<<"$result")" = true ] && rc=124
  if [ "$rc" -eq 124 ]; then
    status "$back_model" "$back_effort" TIMEOUT "$rc"; exit 1
  fi
  if [ "$rc" -eq 0 ] && valid_output; then
    status "$back_model" "$back_effort" FALLBACK "$rc"; exit 0
  fi
  [ "$(jq -r '.quota' <<<"$result")" = true ] && codex_session_mark_off quota
  status "$back_model" "$back_effort" FAILED "$rc"; exit 1
fi

status "$model" "$effort" FAILED "$rc"; exit 1
```

- [ ] **Step 2b: Confirm no `codex` executable reference survives**

Run: `grep -nE '(^|[^-])\bcodex exec\b|command -v codex|timeout [0-9]+ codex' plugins/dr-superpowers/scripts/run-codex-review.sh`
Expected: no output.

- [ ] **Step 3: Run the existing suite**

Run: `timeout 300 bash plugins/dr-superpowers/tests/codex-review.test.sh`
Expected: FAIL, and **failing wholesale** rather than in a few cases: until Task 12 lands the stub-plugin fixture, every run reaches this machine's real profile, where the locator reports `plugin-not-enabled`, so each case now prints `status=FAILED`. Record the failing count in the ledger. Task 12 is what makes this suite green again; do not attempt to fix it here.

- [ ] **Step 4: Commit**

```bash
git add plugins/dr-superpowers/scripts/run-codex-review.sh plugins/dr-superpowers/criteria/codex-final-review.md
git commit -m "feat(superpowers): run review seats through the client"
```

**Implementer:** dr-superpowers:impl-opus-medium
**Evaluation:** files 1 - spec 0 - coupling 2 - risk 2 = 5

---

### Task 7: run-codex-review.sh: drop the catalog and dry-run argv

**Files:**
- Modify: `plugins/dr-superpowers/scripts/run-codex-review.sh:13,102,122,127-170`

**Interfaces:**
- Consumes: the status line in Contracts.
- Produces: `evidence=none` on every status line, and request JSON from `--dry-run`. Task 12 asserts both.

- [ ] **Step 1: Delete the catalog lookup**

In `plugins/dr-superpowers/scripts/run-codex-review.sh`, delete two things. First,
lines 107-111, the comment beginning `# Selection. The catalog is a negative
filter:` — it states the rule this task removes. **Keep lines 112-114**, the
`# Invoked through bash, not executed directly:` comment, which explains the
roster call and stays true. Second, the whole block that computes `advertised`,
`evidence` and `listed` from the roster row. Replace that second block with:

```bash
# No catalog: the plugin advertises no model list, and reading Codex's own
# models_cache.json is the boundary this sub-project closes. The preferred rung
# is attempted, and a refusal falls back, which is the guarantee that matters.
evidence=none
```

- [ ] **Step 2: Simplify the rung choice**

Replace the `if [ "$tier" = light ] … elif [ "$listed" = true ] … else … fi` block with:

```bash
# The light tier is the last row by definition: the known-good rung, and already
# the fallback row, so the refusal branch never retries it against itself.
if [ "$tier" = light ]; then
  model="$back_model"; effort="$back_effort"
else
  model="$pref_model"; effort="$pref_effort"
fi
```

- [ ] **Step 3: Make --dry-run print the request**

Replace the `if [ "$dry_run" = true ]` block with:

```bash
if [ "$dry_run" = true ]; then
  printf 'would-run:\n'
  jq -nc --arg kind "$kind" --arg cwd "$cwd" --arg model "$model" \
    --arg effort "$effort" --arg schema "${schema:-}" \
    --argjson deadline "$(( secs * 1000 ))" \
    '{op:"turn", kind:$kind, cwd:$cwd, model:$model, effort:$effort,
      schemaPath:(if $schema == "" then null else $schema end),
      sandbox:"read-only", deadlineMs:$deadline}'
  printf 'codex-judge %s/%s status=OK exit=0 out=%s evidence=%s\n' \
    "$model" "$effort" "$out" "$evidence"
  exit 0
fi
```

- [ ] **Step 3b: Fix the two hard-coded evidence values**

Lines 102 and 122 print `evidence=unknown` on the gate-off and roster-unusable
branches. The catalog block above does not reach them, and spec section 2.4
requires `evidence=none` on every status line. Change both to:

```bash
  printf 'codex-judge none/none status=FAILED exit=0 out=%s evidence=none\n' "$out"
```

Then confirm nothing else prints another value:

```bash
grep -n 'evidence=' plugins/dr-superpowers/scripts/run-codex-review.sh
```

Expected: only `evidence=none` literals and the two `evidence=%s` format strings
that take `$evidence`, which is now always `none`.

- [ ] **Step 3c: Make the ladder path overridable**

`LADDER` at line 13 is hard-coded, and both `codex-judge` rows bound a run at
1800 seconds, so no suite can reach the timeout branch without waiting half an
hour. Give it the test seam `ROSTER` (line 18) and `GATE` (line 21) already
have. Replace line 13:

```bash
LADDER="$HERE/../reference/ladder.md"
```

with:

```bash
# Tests point this at a fixture ladder whose seconds are small enough to reach
# the timeout branch. Unset in production, where the shipped table is read.
LADDER="${CODEX_REVIEW_LADDER:-$HERE/../reference/ladder.md}"
```

- [ ] **Step 4: Verify the dry run**

The session gate (lines 97-105) and the roster (lines 114-124) both run **before**
the `--dry-run` block, and on this machine the gate answers
`usable=false reason=plugin-not-enabled`. Point both at stubs, as
`tests/codex-review.test.sh` already does, or the command prints `status=FAILED`
and exits 1 no matter where Step 1's replacement landed:

```bash
TMPD=$(mktemp -d)
cat > "$TMPD/gate" <<'SH'
#!/usr/bin/env bash
echo "codex-gate usable=true reason=ok review=true lane=true resets_at=- source=cache"
SH
cat > "$TMPD/roster" <<'SH'
#!/usr/bin/env bash
echo '[{"id":"codex","present":true,"path":"/stub","version":"1.0.3","authed":true,"auth_status":"authenticated","batch_capable":true,"usable":true,"reason":null}]'
SH
chmod +x "$TMPD/gate" "$TMPD/roster"
CODEX_REVIEW_GATE="$TMPD/gate" CODEX_REVIEW_ROSTER="$TMPD/roster" \
  bash plugins/dr-superpowers/scripts/run-codex-review.sh --kind task \
  --cwd "$PWD" --out "$TMPD/dry.json" --prompt /dev/null --dry-run 2>&1 | head -3
rm -rf "$TMPD"
```

Expected: `would-run:`, then a single JSON object naming `"op":"turn"`, then a
status line ending `evidence=none`.

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-superpowers/scripts/run-codex-review.sh
git commit -m "feat(superpowers): drop the catalog from review routing"
```

**Implementer:** dr-superpowers:impl-sonnet-high
**Evaluation:** files 0 - spec 0 - coupling 1 - risk 2 = 3

---

### Task 8: detect-executors.sh: drop the models_cache read

**Files:**
- Modify: `plugins/dr-superpowers/scripts/detect-executors.sh:25-56,84-118`

**Interfaces:**
- Consumes: nothing.
- Produces: a roster row without `advertised`. Tasks 12 and 13 assert on it.

- [ ] **Step 1: Delete advertised_pairs**

In `plugins/dr-superpowers/scripts/detect-executors.sh`, delete the entire `advertised_pairs()` function and its preceding comment block — everything from the comment line beginning `# The local Codex model catalog` through the closing `}` of `advertised_pairs`.

- [ ] **Step 2: Remove advertised from emit**

In `emit()`, delete the local `advertised=null` initialiser, delete the block:

```bash
  if [ "$id" = codex ] && [ "$present" = true ]; then
    advertised=$(advertised_pairs)
  fi
```

delete the `--argjson advertised "$advertised" \` line from the `jq -n` call, and remove `advertised:$advertised` from the emitted object, leaving the object ending `usable:$usable, reason:$reason}`.

- [ ] **Step 3: Verify the row shape**

Run: `bash plugins/dr-superpowers/scripts/detect-executors.sh | jq -c '.[0] | keys'`
Expected: a key list with no `advertised` entry.

- [ ] **Step 4: Confirm no Codex-owned state is read**

Run: `grep -nE 'CODEX_HOME|models_cache|\.codex/' plugins/dr-superpowers/scripts/detect-executors.sh`
Expected: no output.

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-superpowers/scripts/detect-executors.sh
git commit -m "feat(superpowers): stop reading the codex model cache"
```

**Implementer:** dr-superpowers:impl-sonnet-medium
**Evaluation:** files 0 - spec 0 - coupling 1 - risk 1 = 2

---

### Task 9: detect-executors.sh: presence and auth through the plugin

**Files:**
- Modify: `plugins/dr-superpowers/scripts/detect-executors.sh:57-83`

**Interfaces:**
- Consumes: the `codex-client.mjs` interface in Contracts (`op: "auth"`).
- Produces: a codex roster row whose `present`, `version` and `authed` come from the plugin. Task 13 asserts on it.

- [ ] **Step 1: Replace the codex probes**

In `plugins/dr-superpowers/scripts/detect-executors.sh`, inside `emit()`, replace the `path=$(command -v "$id" …)` assignment, the `version` probe and the `authed` probe with:

```bash
  # Codex is reached only through the official plugin: no `command -v codex`,
  # no `codex --version`, no `codex login status`. Every other id keeps the
  # PATH probe, because no plugin owns it.
  if [ "$id" = codex ]; then
    path=""
    present=false
    version=null
    authed=null
    auth_status=not_applicable
    local plugin_line plugin_root auth_json
    if plugin_line=$(bash "$HERE/codex-plugin" 2>/dev/null); then
      present=true
      plugin_root=${plugin_line#*root=}
      path=$plugin_root
      version=$(jq -Rn --arg v "${plugin_line#*version=}" '$v | sub(" root=.*"; "")')
      auth_json=$(printf '{"op":"auth","cwd":"%s"}' "$PWD" \
        | timeout 60 node "$HERE/lib/codex-client.mjs" "$plugin_root" 2>/dev/null)
      case "$(jq -r '.authed // "null"' <<<"${auth_json:-{\}}" 2>/dev/null)" in
        true)  authed=true;  auth_status=authenticated ;;
        false) authed=false; auth_status=logged_out ;;
        *)     authed=null;  auth_status=probe_failed ;;
      esac
    fi
  else
    path=$(command -v "$id" 2>/dev/null || true)
    if [ -n "$path" ]; then present=true; else present=false; fi
    version=null
    if [ "$present" = true ]; then
      local v
      v=$(timeout 20 "$id" --version 2>/dev/null | head -1 | tr -d '\r')
      [ -n "$v" ] && version=$(jq -Rn --arg v "$v" '$v')
    fi
    authed=null
  fi
```

Add `HERE="$(cd "$(dirname "$0")" && pwd)"` near the top of the script if it is not already defined, directly below the `set` line.

- [ ] **Step 2: Update the not-usable reason for codex**

Replace the reason branch `'"present but not authenticated; run codex login"'` with:

```bash
    reason='"the codex plugin is installed but not logged in; run /codex:setup"'
```

and `'"authentication status probe failed; check codex login status"'` with:

```bash
    reason='"the codex plugin auth probe failed; run /codex:setup"'
```

and `'"not on PATH"'` with, for codex only, the plugin wording — leave the PATH wording for the other ids by replacing the branch with:

```bash
  if [ "$present" != true ]; then
    if [ "$id" = codex ]; then
      reason='"the codex plugin is not enabled in this profile"'
    else
      reason='"not on PATH"'
    fi
```

- [ ] **Step 3: Verify no codex binary reference survives**

Run: `grep -nE 'command -v codex|codex --version|codex login' plugins/dr-superpowers/scripts/detect-executors.sh`
Expected: no output.

- [ ] **Step 4: Run the roster**

Run: `bash plugins/dr-superpowers/scripts/detect-executors.sh | jq -c '.[] | select(.id=="codex")'`
Expected: a row with `"present": false` and `"reason": "the codex plugin is not enabled in this profile"` on this machine, because the plugin is not enabled in the `.claude-alt` profile.

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-superpowers/scripts/detect-executors.sh
git commit -m "feat(superpowers): probe codex through the plugin"
```

**Implementer:** dr-superpowers:impl-opus-low
**Evaluation:** files 0 - spec 0 - coupling 2 - risk 2 = 4

---

### Task 10: run-codex-task.sh: run the task through the client

**Files:**
- Modify: `plugins/dr-superpowers/scripts/run-codex-task.sh:27,114-146,178,211-231,265-337,353-359,399`

**Interfaces:**
- Consumes: the `codex-client.mjs` interface in Contracts.
- Produces: the task record's `thread`, unchanged in meaning, now taken from the client result, and `$report.last.json` written from the turn. Task 11 consumes the same result.

- [ ] **Step 1: Initialise the prompt variable**

At line 27, `prompt` is missing from the variable list and is first assigned at
line 187, but `--dry-run` at line 132 now needs it. Under `set -u` an unset
`prompt` aborts the dry run. Change the line to:

```bash
brief="" report="" model="" effort="" cwd="" timeout_s="" thread="" dry=0 prompt=""
```

- [ ] **Step 2: Replace the argv construction**

Delete the `argv=(...)` construction block and the `command -v timeout` guard,
and put in their place:

The plugin locator does **not** go here. It moves into Step 5's launch block,
below the `--dry-run` return, so a dry run needs no enabled plugin - the order
`run-codex-review.sh` already uses, and what keeps every case in
`tests/run-codex-task.test.sh` runnable without a plugin fixture.

```bash
# Every per-invocation field is rebuilt here, including on resume: the client
# starts a fresh thread unless resumeThreadId is set, and a resumed thread must
# carry the same model and effort the record pins.
#
# --rawfile, not --arg "$(cat ...)": a task prompt is a brief plus CLAUDE.md
# plus a contract, and passing it as an argument blows the 32,767-character
# Windows CreateProcess limit.
build_request() { # build_request; echoes the request JSON
  jq -nc \
    --arg cwd "$cwd" --arg model "$model" --arg effort "$effort" \
    --rawfile prompt "${prompt:-/dev/null}" --arg thread "${thread:-}" \
    --arg schema "$SCHEMA" --argjson deadline "$(( timeout_s * 1000 ))" \
    '{op:"turn", kind:"task", cwd:$cwd, model:$model, effort:$effort,
      prompt:$prompt, schemaPath:$schema, sandbox:"workspace-write",
      resumeThreadId:(if $thread == "" then null else $thread end),
      persistThread:true, threadName:null, deadlineMs:$deadline}'
}
```

`$SCHEMA` is `codex-report-schema.json`, defined at line 11. Passing it keeps the
verdict schema-constrained, which is what lines 366-372 depend on.

- [ ] **Step 3: Replace the dry-run output**

Replace the dry-run block that printed `timeout=<s>` and the argv with:

```bash
if [ "$dry" -eq 1 ]; then
  printf 'would-run:\n'
  build_request
  exit 0
fi
```

- [ ] **Step 4: Delete the stale argv line**

Line 178 still points the deleted array at the report file:

```bash
argv[${#argv[@]}-1]="$report.last.json"
```

Delete that line. Under `set -u` it errors with "bad array subscript" once
`argv` is gone. `$last` is assigned from `$report` at line 189 and is unaffected.

- [ ] **Step 5: Replace the launch, the poll and the reaping block**

Replace the whole range from the `set -m` line (265-269 region, beginning with
the comment about `kill -TERM`) through `dr_task_update '.processes = []' || die 'cannot persist child termination'`
— that is, up to and including the old line 337 — with:

```bash
# The client owns the deadline, the interrupt and the broker reaper, so there is
# no process group for this script to create, poll or signal. `set -m`,
# kill_codex_tree, the polled wait and the grace window all went with it: node
# is a direct child that exits on its own, and the wrapper that used to sit
# between us and node - the one that broke taskkill's native tree-walk - no
# longer exists either.
#
# The plugin root is resolved here rather than beside build_request, so that
# --dry-run returns above without needing an enabled plugin. scripts/codex-plugin
# owns the locator and the version allowlist; this script never names the codex
# executable.
plugin_line=$(bash "$HERE/codex-plugin") || die "the codex plugin is not usable: $plugin_line"
plugin_root=${plugin_line#*root=}

dr_task_update '.phase = "running" | .processes = []' || die 'cannot persist running phase'

result=$(build_request | node "$HERE/lib/codex-client.mjs" "$plugin_root" 2>"$report.stderr")
# A node that died before printing leaves $result empty, and every jq below would
# then fail and take the runner with it. One guard here covers all of them.
[ -n "$result" ] || result='{}'
printf '%s\n' "$result" > "$jsonl"

# The report the verdict is read from. The client returns the model's structured
# output as finalMessage; lines below parse $last for status, summary and
# commit_subject, so writing it here is what keeps the runner able to commit.
jq -r '.finalMessage // ""' <<<"$result" > "$last"

discovered_thread=$(jq -r '.threadId // empty' <<<"$result")
if [ -n "$discovered_thread" ]; then
  dr_task_update '.thread = $thread' --arg thread "$discovered_thread" \
    || die 'cannot persist thread'
fi

timed_out=no
[ "$(jq -r '.timedOut' <<<"$result")" = true ] && timed_out=yes
rc=0
[ "$(jq -r '.ok' <<<"$result")" = true ] || rc=1
[ "$timed_out" = yes ] && rc=124
survivor=no
```

- [ ] **Step 5b: Delete the launch bookkeeping outside Step 5's range**

Three fragments sit outside the range Step 5 replaced and still name a process
that no longer exists. Task 11 Step 4's grep expects no output, so delete all
three here:

- **lines 211-212**, `codex_pid=""` and `codex_winpid=""`;
- **lines 213-231**, the comment block beginning `# Two mechanisms for two
  topologies.` through the closing `}` of `kill_codex_tree`;
- **line 399**, the survivor note
  `[ "$survivor" = yes ] && printf -- '- note: a codex process may still be running (pid %s); ...' "$codex_pid"`.

Line 428, `[ "$survivor" = yes ] && notes="$notes note=codex-may-still-be-running"`,
**stays**: Step 5 assigns `survivor=no` and never changes it, so the line is
inert and the notes field keeps its shape. `cleanup()` at 232-248 also still
references `codex_pid`; Task 11 Step 1 replaces that function whole, and the two
tasks are committed in sequence, so run the Step 6 grep only after Task 11.

- [ ] **Step 5c: Take the failure diagnostics from the client result**

Lines 353-359 extract `codex_error` from `$jsonl` by matching `.type == "error"`
or `.type == "turn.failed"`. `$jsonl` now holds one client result object, which
carries no `.type`, so every failed run would report nothing while the client's
own `reason` and `stderr` - the only thing separating a quota failure from a
refusal from a crash - were discarded. Replace the whole `codex_error=$(jq -r
'...' "$jsonl" ...)` assignment **and the comment above it** with:

```bash
# The client classifies the failure, so this is where the controller reads it.
# `reason` separates quota from refusal from timeout from a plugin fault, and
# `stderr` carries whatever text came back. Without this the task report says
# only "exit 1", which reads as a model that gave up rather than one that was
# never reached.
codex_error=$(jq -r '
  [ (if .reason then "reason=" + .reason else empty end),
    (if .refusal == true then "refusal=true" else empty end),
    (if .quota == true then "quota=true" else empty end),
    (if .timedOut == true then "timedOut=true" else empty end),
    (.stderr // "" | select(. != "")) ]
  | join("\n")' <<<"$result" 2>/dev/null || true)
```

Lines 412-413, `if [ -n "$codex_error" ]` and the `## Codex error` fence, need no
change: they already print whatever the variable holds.

- [ ] **Step 6: Confirm nothing references the deleted machinery**

Run:

```bash
grep -nE 'codex_pid|codex_winpid|kill_codex_tree|set -m|set \+m|argv\[|command -v timeout' plugins/dr-superpowers/scripts/run-codex-task.sh
grep -nE '(^|\s)codex "\$|command -v codex|codex exec' plugins/dr-superpowers/scripts/run-codex-task.sh
```

Expected: no output from either.

- [ ] **Step 7: Run the task-runner suite**

Run: `timeout 300 bash plugins/dr-superpowers/tests/run-codex-task.test.sh`
Expected: FAIL on every assertion that reads the argv the dry run no longer
prints — the eight-fragment loop at lines 80-82, the `--dangerously-bypass`
check at 84, both timeout checks at 88 and 95, the resume block at 101-106, the
ordering block at 116-121, the non-resume block at 124-129, and the space
round-trip at 194-202. This suite has **no** `$TMP/bin/codex` stub to break, and
every other case still passes. Task 13 rewrites all of them. Record the failing
count in the ledger.

- [ ] **Step 8: Commit**

```bash
git add plugins/dr-superpowers/scripts/run-codex-task.sh
git commit -m "feat(superpowers): run executor tasks through the client"
```

**Implementer:** dr-superpowers:impl-opus-low
**Evaluation:** files 0 - spec 0 - coupling 2 - risk 2 = 4

---

### Task 11: run-codex-task.sh: reap through the client

**Files:**
- Modify: `plugins/dr-superpowers/scripts/run-codex-task.sh:232-248`

**Interfaces:**
- Consumes: `reaped` on the client result (Task 4).
- Produces: a task runner that starts no process group of its own, so none can leak.

Task 10 removed the launch machinery. This task removes what remains that
referred to it, and records the reap outcome.

- [ ] **Step 1: Replace the cleanup trap**

`cleanup()` at lines 232-248 signals the process group Task 10 stopped creating.
Two of its statements are **not** optional and must survive:

- `dr_task_unlock` (line 245). `trap cleanup EXIT` at line 248 replaced
  `trap 'dr_task_unlock' EXIT` at line 157, so `cleanup` is now the only thing
  that releases the worktree lock. A body that returns without it leaves
  `$DR_TASK_ROOT/run.lock` behind after **every** completed run, and every later
  task in that worktree dies at `dr_task_lock` with "worktree run lock exists".
- the `dr_task_block 'execution interrupted; ...'` guard (line 243). It is what
  marks a record whose phase is still `running` when the shell exits.

There is no temporary directory to clean up: the existing body removes none.
Replace the whole function with exactly this:

```bash
# The only child is node, which exits when the client does, and the client reaps
# the broker it caused to exist. Nothing here has a process group to signal - but
# the interrupted-run guard and the unlock both stay, because the EXIT trap is
# still the only thing that releases the worktree lock.
cleanup() {
  if [ "$(jq -r .phase "$record" 2>/dev/null)" = running ]; then
    dr_task_update '.processes = []' && dr_task_block 'execution interrupted; reconcile the recorded snapshot' || true
  fi
  dr_task_unlock
  return 0
}
```

- [ ] **Step 2: Record the reap in the task record**

Directly after the `discovered_thread` block Task 10 added, add:

```bash
# The client reaps the broker it caused to exist. Recording the outcome makes a
# leak visible in the task record rather than only in a process list. Task 10
# Step 5 already guarantees $result holds an object, so the jq below cannot be
# handed an empty string; the `if` still defaults a missing key to false.
dr_task_update '.reaped = $reaped' \
  --argjson reaped "$(jq -r 'if .reaped == true then true else false end' <<<"$result" 2>/dev/null || echo false)" \
  || die 'cannot persist reap outcome'
```

- [ ] **Step 3: Verify the record still validates**

`scripts/lib/task-state.sh:51` validates the record by asserting that required
keys are **present** — a chain of `has("candidate") and has("pending") and …`.
It never compares the full key set, so an added key cannot be rejected and
`reaped` needs to be registered nowhere. Confirm that still holds:

```bash
sed -n '45,55p' plugins/dr-superpowers/scripts/lib/task-state.sh
timeout 300 bash plugins/dr-superpowers/tests/task-state.test.sh
```

Expected: line 51 is a `has(...)` chain with no `keys` comparison, and the suite
reports `0 failed`.

- [ ] **Step 4: Verify no orphan is possible**

Run:

```bash
grep -nE 'kill_codex_tree|codex_pid|codex_winpid|taskkill|launch-pending' plugins/dr-superpowers/scripts/run-codex-task.sh
```

Expected: no output. Task 10 Step 5b deleted lines 211-231 and 399; Step 1 above
removed the last references, in `cleanup`. A hit here means one of those two
edits was skipped.

- [ ] **Step 5: Run the task-runner suite**

Run: `timeout 300 bash plugins/dr-superpowers/tests/run-codex-task.test.sh`
Expected: the same failures as Task 10 Step 7 and no new ones.

- [ ] **Step 6: Commit**

```bash
git add plugins/dr-superpowers/scripts/run-codex-task.sh
git commit -m "refactor(superpowers): move the reaper into the client"
```

**Implementer:** dr-superpowers:impl-opus-low
**Evaluation:** files 0 - spec 1 - coupling 1 - risk 2 = 4

---

### Task 12: tests/codex-review.test.sh: update for the client path

**Files:**
- Modify: `plugins/dr-superpowers/tests/codex-review.test.sh`

**Interfaces:**
- Consumes: the status line and the stub fixture contract in Contracts.
- Produces: nothing later tasks read.

This suite drives about forty outcome cases through a `$TMP/bin/codex` PATH stub
and `CODEX_STUB_MODE`. After Task 6 nothing reaches that stub, so every one of
those cases would silently run as a success. They are remapped here, one for one.

- [ ] **Step 1: Point the suite at a stub plugin instead of a stub binary**

Near the top of `plugins/dr-superpowers/tests/codex-review.test.sh`, below the
existing `DR_CODEX_SESSION_DIR` and `CLAUDE_CODE_SESSION_ID` exports, add:

```bash
# The runner resolves its plugin root through scripts/codex-plugin, which reads
# the profile settings and the policy file. Both are fixtures here, and
# CLAUDE_PROJECT_DIR is cleared because the locator also reads a project's own
# .claude/settings*.json - without this a run under Claude Code reads this
# repository's settings.
STUB_PLUGIN="$HERE/fixtures/stub-codex-plugin"
export STUB_MODE=ok
export CLAUDE_PROJECT_DIR=
export CLAUDE_CONFIG_DIR="$TMP/config"
mkdir -p "$CLAUDE_CONFIG_DIR/plugins"
printf '{"enabledPlugins":{"codex@openai-codex":true}}\n' > "$CLAUDE_CONFIG_DIR/settings.json"
jq -nc --arg p "$STUB_PLUGIN" \
  '{version:2, plugins:{"codex@openai-codex":[{scope:"user", installPath:$p, version:"1.0.3"}]}}' \
  > "$CLAUDE_CONFIG_DIR/plugins/installed_plugins.json"
export DR_CODEX_POLICY="$TMP/policy.json"
jq -nc '{plugin:"codex@openai-codex", versions:["1.0.3"],
         trust:{calibration:"pending", smoke:"pending"}}' > "$DR_CODEX_POLICY"

# A fixture ladder, because the shipped codex-judge rows bound a run at 1800
# seconds and the timeout case would wait out half an hour against them. The
# rows and their order are the shipped ones; only the seconds differ. Task 7
# Step 3c adds the CODEX_REVIEW_LADDER override this reads.
export CODEX_REVIEW_LADDER="$TMP/ladder.md"
fence='```'
{ printf '%scodex-judge\n' "$fence"
  printf 'gpt-6-astra high 2\n'
  printf 'gpt-5.6-sol high 2\n'
  printf '%s\n' "$fence"; } > "$CODEX_REVIEW_LADDER"

# --kind final composes its own prompt from `git diff <base>...HEAD` (Task 6), so
# the work tree has to be a real repository with the base branch present. One
# empty commit is enough: the diff may be empty, and the runner only needs the
# compose to succeed.
#
# mkdir here, not only at line 29: this block sits near the top of the file, well
# above the existing `mkdir -p "$TMP/bin" "$TMP/codexhome" "$TMP/work"`, and
# `git -C` on a directory that does not exist yet fails outright.
mkdir -p "$TMP/work"
git -C "$TMP/work" init -q -b main
git -C "$TMP/work" -c user.email=t@example.invalid -c user.name=t \
  commit -q --allow-empty -m base
```

The stub fixture carries version `1.0.3` in its `.claude-plugin/plugin.json` and
ships `scripts/lib/app-server.mjs`, which is what `scripts/codex-plugin` checks
before calling a root usable.

- [ ] **Step 2: Carry the stub environment into every run**

Replace the `run()` helper at lines 61-64 with:

```bash
run() { # run <args...>; STUB_* variables in the environment script the stub
  printf '0' > "$TMP/calls"
  : > "$TMP/events.log"
  PATH="$TMP/bin:$PATH" CODEX_REVIEW_ROSTER="$TMP/bin/detect-stub" \
    CODEX_REVIEW_GATE="$TMP/gate-stub" CODEX_REVIEW_LADDER="$CODEX_REVIEW_LADDER" \
    CLAUDE_CONFIG_DIR="$CLAUDE_CONFIG_DIR" CLAUDE_PROJECT_DIR= \
    DR_CODEX_POLICY="$DR_CODEX_POLICY" \
    STUB_CALL_FILE="$TMP/calls" STUB_EVENT_LOG="$TMP/events.log" \
    "$BASH_BIN" "$SCRIPT" "$@" 2>"$TMP/err"
}
```

**Do not add the `STUB_*` mode variables to that prefix.** Writing
`STUB_FINAL_MESSAGE="${STUB_FINAL_MESSAGE:-}"` exports an empty string, and the
stub reads `process.env.STUB_FINAL_MESSAGE ?? '{"ok":true}'` — `??` treats `""`
as present, so every case would get an empty final message, `valid_output` would
fail, and every `OK` case would report `FAILED`. It is also unnecessary: a bash
assignment written in front of a shell-function call is visible to the commands
that function runs, so a per-case `STUB_MODE=refusal run …` already reaches the
client.

`STUB_CALL_FILE` and `STUB_EVENT_LOG` are reset here rather than per case, so
every seat count and every call log covers exactly one runner invocation —
including the two seats of a fallback, which is the count the assertions read.

- [ ] **Step 3: Delete the codex binary stub and retarget the seat helper**

Delete lines **143-191**: the comment block introducing the stub, the
`cat > "$TMP/bin/codex" <<STUB … STUB` heredoc with its whole
`case "$CODEX_STUB_MODE"` body, and the `chmod +x "$TMP/bin/codex"` beneath it.
Keep line 142, the `# --- the outcome policy ---` banner: the section it labels
survives this task.
Nothing reaches a `codex` binary any more, so a stub binary left in place would
only mask a regression.

Then replace the `seat()` helper at lines 193-197, which currently reads:

```bash
seat() { # seat <mode> <kind> <extra-args...>
  rm -f "$TMP/calls" "$TMP"/o.md* "$TMP"/o.json*
  local mode="$1" k="$2"; shift 2
  CODEX_STUB_MODE="$mode" run --kind "$k" --cwd "$TMP/work" "$@"
}
```

with one that takes no mode, because the stub is scripted by `STUB_*` variables
a per-case prefix supplies:

```bash
seat() { # seat <kind> <extra-args...>; STUB_* in the environment scripts the stub
  rm -f "$TMP"/o.md* "$TMP"/o.json*
  local k="$1"; shift
  run --kind "$k" --cwd "$TMP/work" "$@"
}
```

`$TMP/calls` is deliberately no longer removed here. `run()` re-initialises it to
`0` on every invocation, which is what keeps the three "runs no codex" checks at
lines 318, 330 and 335 reading `0` instead of an empty string.

- [ ] **Step 4: Remap every outcome case**

Every `seat <mode> <kind> …` call becomes `<prefix> seat <kind> …`, where the
prefix is this table's second column. An empty prefix means the stub's defaults
are already right and the call carries none.

| Old `CODEX_STUB_MODE` | New environment prefix | Expected outcome |
|---|---|---|
| `ok-final` | *(none)* | `OK` |
| `ok` | `STUB_FINAL_MESSAGE='{"spec_verdict":"met","task_quality":18,"cannot_verify":[]}'` | `OK` |
| `ok-plan` | `STUB_FINAL_MESSAGE='{"executability":17,"coherence":16,"coverage":17,"assumptions":16,"findings":[]}'` | `OK` |
| `empty` | `STUB_EMPTY=1` | `FAILED` |
| `noout` | `STUB_EMPTY=1` | `FAILED` |
| `hang` | `STUB_MODE=hang` | `TIMEOUT`, one seat |
| `refuse-then-ok` | `STUB_REFUSE_ONCE=1` | `FALLBACK`, two seats |
| `refuse-always` | `STUB_MODE=refusal` | `FAILED`, two seats |
| `prose-fail` | `STUB_TURN_STATUS=1 STUB_FINAL_MESSAGE='the diff mentions an unsupported model'` | `FAILED`, one seat |
| `authfail` | `STUB_MODE=logged-out` | `FAILED`, one seat |
| `cancel` | `STUB_MODE=throw` | `FAILED`, one seat |
| `quota` | `STUB_MODE=quota` | `FAILED`, one seat, session marked off |
| `refuse-then-quota` | `STUB_REFUSE_ONCE=1 STUB_SECOND_MODE=quota` | `FAILED` on the fallback row, session marked off |

Three of these rows were unreachable in the previous draft, and each needs
something outside the table:

- **`hang`** works only against the Step 1 fixture ladder. The shipped rows bound
  a run at 1800 seconds; the fixture bounds it at 2, which is what lets the
  client's deadline fire inside the suite.
- **`authfail`** needs the stub's `logged-out` **turn** branch, which Task 1 adds.
  An `op:"turn"` request never reaches `getCodexAuthStatus`, so without that
  branch the case returns status 0 and proves nothing.
- **`refuse-then-quota`** needs `STUB_SECOND_MODE`. `STUB_REFUSE_ONCE=1` alone
  forces call 2 to `ok`, so the session would never be marked off and the
  assertion at line 359 would fail.

**Delete the `refuse-stdout` case at lines 252-255** rather than remapping it. It
existed to prove that a refusal arriving on stdout rather than on stderr still
falls back. The client classifies from the turn result's own error field, so
there is no stream to distinguish, and `STUB_MODE=refusal` already covers the
outcome the case asserted.

**Delete the fallback-row case at lines 246-250 as well** — `write_roster
"$SOL_ONLY"` followed by `seat refuse-always final`, asserting `the fallback row
is never retried against itself` with a seat count of 1. It worked only because
the catalog fixture forced selection onto the last row. After Task 7 the heavy
tier always selects `gpt-6-astra`, so the run falls back and the count reads 2,
which is what this table's `refuse-always` row already expects. The property is
not lost: the `--tier light` case at lines 306-308 asserts it, and `--tier` is a
usage error with `--kind final` (line 294), so this case cannot be rescued by
adding one.

The `prose-fail` row is the case that proves the migration's point: the old
runner grepped a transcript and would call that a refusal, while the client
classifies from the result's own error field and does not.

- [ ] **Step 4b: Restore the seat-count and refusal-log assertions**

`$TMP/calls` used to be written by the deleted binary stub. It is written by the
stub plugin now, through `STUB_CALL_FILE`, and `run()` resets it per invocation —
so the seven `check … "$(cat "$TMP/calls")"` assertions at lines 221, 227, 231,
235, 239, 244 and 308, and the `calls()` helper at line 313, keep working
unchanged once Steps 2 and 3 land. Lines 250 and 255 are deliberately **not** in
that list: Step 4 deletes the two cases that carry them.

The two log assertions at lines 257-262 do not. They read `$TMP/o.md.stderr` and
`$TMP/o.md.fallback.stderr` and require the first to be **non-empty**; `run_seat`
redirects node's stderr to those paths and node writes nothing against the stub.
The refusal text now travels in the result's `stderr` field and comes out in the
runner's own `refused (...)` message. Replace lines 257-262 with:

```bash
# The refusal has to survive into the fallback run, because the ledger quotes it.
# It travels in the result's own stderr field now and reaches the runner's
# message rather than a log file.
STUB_REFUSE_ONCE=1 seat final --out "$TMP/o.md" --base main >/dev/null
check "the refusal is quoted before the fallback runs" \
  "$(grep -c 'refused (.*); falling back to gpt-5.6-sol/high' "$TMP/err")" "1"
check "both seats ran, preferred rung first" \
  "$(awk '/^runAppServerTurn/{print $2}' "$TMP/events.log" | tr '\n' ',')" \
  "gpt-6-astra/high,gpt-5.6-sol/high,"
check "no seat ever reaches a review entry point" \
  "$(grep -c 'runAppServerReview' "$TMP/events.log")" "0"
```

- [ ] **Step 5: Fix the selection and evidence assertions**

`evidence=` appears in four expectations. Change all four to `evidence=none`:
lines 73 and 276, which expect `evidence=2026-09-14T13:35:00Z`, and lines 106 and
316, which expect `evidence=unknown`. After Task 7 every status line the runner
prints carries the constant.

Then delete the catalog fixtures and the cases built on them:

- **lines 37-51** — `write_roster()`'s `<advertised-json>` parameter and the
  `ASTRA`, `SOL_ONLY` and `EMPTY` constants. `write_roster` becomes a
  no-argument function emitting a row with no `advertised` key, and every
  `write_roster "$ASTRA"`, `write_roster "$SOL_ONLY"`, `write_roster "$EMPTY"`
  and `write_roster null` call becomes a bare `write_roster`.
- **lines 88-106** — the three fail-closed selection blocks: `catalog without
  astra falls back to sol`, `empty catalog falls back to sol`, `absent catalog
  falls back to sol`, and `absent catalog reports unknown evidence`. Selection no
  longer consults a catalog, so the preferred rung is always attempted and these
  four outcomes cannot occur.
- **line 125** — the `"advertised":null` field in the unusable-roster fixture.

Keep every remaining selection assertion naming `gpt-6-astra`: the heavy tier is
still the ladder's first row. The `--tier light` cases at lines 272-279 keep
selecting `gpt-5.6-sol`, still the last row.

- [ ] **Step 6: Replace the argv assertions with request-JSON assertions**

`--dry-run` prints `would-run:` and then one JSON object on line 2. The `tok()`
helper at line 76 tested one argv token per line and has nothing left to test.
Delete `tok` and every check that used it — lines 77-78, 79-81, 85-86, 92-93,
98-99, 104-105, 112-113, 116-117, 269-270, 274-275 and 285-286 — along with the
six `present` checks that matched argv text, at lines 82, 114, 115, 267, 282 and
283. Add one helper in `tok`'s place:

```bash
req_of() { sed -n '2p' <<<"$1"; } # req_of <dry-run output>; echoes the request JSON
```

Then write the replacements:

- **Lines 71-86**, after the existing `out=$(run --kind final … --dry-run)` at
  line 70:

```bash
present "the heavy tier selects astra" "$out" "codex-judge gpt-6-astra/high"
present "dry run reports OK" "$out" "status=OK"
present "dry run reports no catalog evidence" "$out" "evidence=none"
r=$(req_of "$out")
check "final: prints a turn request" "$(jq -r '.op' <<<"$r")" "turn"
check "final: carries the selected model" "$(jq -r '.model' <<<"$r")" "gpt-6-astra"
check "final: carries the selected effort" "$(jq -r '.effort' <<<"$r")" "high"
check "final: sends no base field" "$(jq -r 'has("base")' <<<"$r")" "false"
check "final: read-only sandbox" "$(jq -r '.sandbox' <<<"$r")" "read-only"
check "final: deadline in milliseconds" "$(jq -r '.deadlineMs > 0' <<<"$r")" "true"
```

  `final` sends neither a schema nor a base. Its criteria and its diff are
  composed into the prompt by the runner on a real run, and `--dry-run` returns
  before that happens.

- **Lines 111-117**, the risk3 block:

```bash
out=$(run --kind risk3 --cwd "$TMP/work" --out "$TMP/o.json" --prompt "$TMP/p.txt" --dry-run)
r=$(req_of "$out")
check "risk3: carries a schema path" \
  "$(jq -r '.schemaPath' <<<"$r" | grep -c 'codex-review-schema.json')" "1"
check "risk3: read-only sandbox" "$(jq -r '.sandbox' <<<"$r")" "read-only"
check "risk3: the kind reaches the request" "$(jq -r '.kind' <<<"$r")" "risk3"
```

- **Lines 266-270 and 281-286**, the task and plan blocks:

```bash
out=$(run --kind task --cwd "$TMP/work" --out "$TMP/o.json" --prompt "$TMP/p.txt" --dry-run)
r=$(req_of "$out")
check "task: passes the task-review schema" \
  "$(jq -r '.schemaPath' <<<"$r" | grep -c 'codex-review-schema.json')" "1"
present "task defaults to the heavy tier" "$out" "codex-judge gpt-6-astra/high"

out=$(run --kind plan --cwd "$TMP/work" --out "$TMP/o.json" --prompt "$TMP/p.txt" --dry-run)
r=$(req_of "$out")
check "plan: passes the plan-review schema" \
  "$(jq -r '.schemaPath' <<<"$r" | grep -c 'codex-plan-review-schema.json')" "1"
check "plan: read-only sandbox" "$(jq -r '.sandbox' <<<"$r")" "read-only"
present "plan takes the heavy selection" "$out" "codex-judge gpt-6-astra/high"
```

Lines 272-279, the light-tier cases, keep their `present` assertions on the
status line and lose only the `tok` check: the line already names the row that
was selected.

- [ ] **Step 7: Run the suite**

Run: `timeout 300 bash plugins/dr-superpowers/tests/codex-review.test.sh`
Expected: PASS, `0 failed`.

- [ ] **Step 8: Commit**

```bash
git add plugins/dr-superpowers/tests/codex-review.test.sh
git commit -m "test(superpowers): cover the review client path"
```

**Implementer:** dr-superpowers:impl-opus-low
**Evaluation:** files 0 - spec 1 - coupling 1 - risk 2 = 4

---

### Task 13: detect.test.sh and run-codex-task.test.sh: update for the plugin path

**Files:**
- Modify: `plugins/dr-superpowers/tests/detect.test.sh`
- Modify: `plugins/dr-superpowers/tests/run-codex-task.test.sh`

**Interfaces:**
- Consumes: the stub fixture contract in Contracts, and the roster shape from Tasks 8 and 9.
- Produces: nothing later tasks read.

`lanes.test.sh` validates `ladder.md` tables only and is **not** touched by this
plan. These two suites are the ones that cover the roster and the task runner.

- [ ] **Step 1: Give detect.test.sh a usable PATH**

`plugins/dr-superpowers/tests/detect.test.sh:38` runs with `PATH="$TMP/bin"`,
which holds shims for `jq timeout head tr` and a stub `codex` binary. After Task
9 the roster also needs `node` and `bash`. Add them as shims, **not** by
appending the real `PATH`: the sealed `PATH` is exactly what makes the
`cursor-agent`, `opencode` and `antigravity` "not present" assertions at lines
96-107 deterministic, and appending this machine's `PATH` would let a real
binary answer them. Extend the shim loop at lines 34-37:

```bash
for dep in jq timeout head tr node bash; do
  printf '#!%s\nexec "%s" "$@"\n' "$BASH_BIN" "$(command -v "$dep")" > "$TMP/bin/$dep"
  chmod +x "$TMP/bin/$dep"
done
```

and replace the `run()` helper at line 38 with:

```bash
# The codex row is probed through the plugin now, not through a codex binary on
# PATH, so PATH stays sealed to $TMP/bin and the locator is pointed at fixtures
# instead. CLAUDE_PROJECT_DIR is cleared because scripts/codex-plugin also reads
# a project's own .claude/settings*.json.
run() { PATH="$TMP/bin" CLAUDE_CONFIG_DIR="$TMP/config" CLAUDE_PROJECT_DIR= \
        DR_CODEX_POLICY="$TMP/policy.json" STUB_MODE="${STUB_MODE:-ok}" \
        "$BASH_BIN" "$SCRIPT"; }
```

`STUB_MODE="${STUB_MODE:-ok}"` is safe here, unlike `STUB_FINAL_MESSAGE` in Task
12: `ok` is the stub's real default, so the fallback value and the absent value
mean the same thing.

- [ ] **Step 2: Add the stub-plugin fixture**

`scripts/codex-plugin` reads a profile's settings, its installed-plugins file and
the policy file. All three are fixtures here. Add this directly below Step 1's
shim loop. It is **not** the block Task 12 Step 1 adds: that one also builds a git
repository and a ladder fixture, and this suite never runs the review runner and
has no `$TMP/work`.

```bash
# The locator reads a profile's settings and installed-plugins file; the version
# allowlist reads the policy file. Step 1's run() clears CLAUDE_PROJECT_DIR,
# because the locator also reads a project's own .claude/settings*.json.
STUB_PLUGIN="$HERE/fixtures/stub-codex-plugin"
mkdir -p "$TMP/config/plugins"
printf '{"enabledPlugins":{"codex@openai-codex":true}}\n' > "$TMP/config/settings.json"
jq -nc --arg p "$STUB_PLUGIN" \
  '{version:2, plugins:{"codex@openai-codex":[{scope:"user", installPath:$p, version:"1.0.3"}]}}' \
  > "$TMP/config/plugins/installed_plugins.json"
jq -nc '{plugin:"codex@openai-codex", versions:["1.0.3"],
         trust:{calibration:"pending", smoke:"pending"}}' > "$TMP/policy.json"
```

- [ ] **Step 3: Delete the codex binary stubs and the catalog fixtures**

In `plugins/dr-superpowers/tests/detect.test.sh`, delete by line:

- **53-54** — the `$TMP/bin/codex` writer and its `chmod +x`. Lines 65-66 and
  73-74 write that stub too, but each is paired with something else — an
  `auth.json` write at 66, a `run` at 74 — and Step 3b replaces the whole of
  52-61 and 63-77 regardless, so do not treat those two pairs as writer plus
  `chmod` here.
- **137-144** — the `cat > "$TMP/bin/codex" <<STUB … STUB` heredoc and its
  `chmod +x`.
- **133-192** — the whole `--- advertised model pairs ---` section, from its
  banner comment through `check "absent cache leaves codex usable"`. That is the
  `write_cache` helper at 146, its four calls at 148, 166, 171 and 182, the
  `rm -f "$TMP/codexhome/models_cache.json"` at 188, the `has_field` helper at
  161, the **twelve** assertions reading `.advertised` — lines 153, 154, 155,
  157, 162, 163, 168, 173, 174, 184, 190 and 191 — and the three
  catalog-behaviour checks at 175, 185 and 192 that do not name `.advertised`
  but exist only to exercise that section.
- **`CODEX_HOME`** wherever it is set: line 38, which Step 1's new `run()`
  already drops, and line 118, the `nojq` invocation, which keeps its `PATH` and
  loses only `CODEX_HOME="$TMP/codexhome"`.
- **`$TMP/codexhome`** — remove it from the `mkdir -p` at line 21; lines 64, 66
  and 71 (the `rm -f` and `printf` against `auth.json`) go with the cases Step 3b
  replaces.

The count is twelve, not eighteen: round 1's "18" added the `CODEX_HOME` lines to
the `.advertised` assertions.

- [ ] **Step 3b: Replace the cases the deleted stubs fed**

Deleting the three stub writers leaves three blocks of assertions with nothing
driving them. Replace each block; do not merely delete the writer above it.

**Lines 43-50, `--- nothing installed ---`.** "codex not present" now means the
plugin is not enabled, not that `PATH` is empty. Keep lines 45 and 46 as they
are and replace 47-50 with:

```bash
# No plugin enabled in the fixture profile, so there is no codex lane at all.
printf '{"enabledPlugins":{}}\n' > "$TMP/config/settings.json"
out=$(run)
check "no plugin: codex not present" "$(field codex present "$out")" "false"
check "no plugin: codex not usable" "$(field codex usable "$out")" "false"
check "no plugin: the reason names the plugin, not PATH" \
  "$(field codex reason "$out" | grep -qi 'plugin' && echo yes || echo no)" "yes"
```

**Lines 52-61, `--- codex installed and authenticated ---`.** Replace the banner,
both stub lines and all six checks with:

```bash
# --- codex enabled and logged in, both answered by the plugin ----------------
printf '{"enabledPlugins":{"codex@openai-codex":true}}\n' > "$TMP/config/settings.json"
out=$(run)
check "codex present from the plugin" "$(field codex present "$out")" "true"
check "codex version from the plugin" "$(field codex version "$out")" "1.0.3"
check "codex authed from the plugin" "$(field codex authed "$out")" "true"
check "codex batch capable" "$(field codex batch_capable "$out")" "true"
check "codex usable" "$(field codex usable "$out")" "true"
check "usable executor carries no reason" "$(field codex reason "$out")" "null"
```

**Lines 63-77, `--- codex installed but unauthenticated ---`.** Replace the
banner, the two stub writers, the `auth.json` writes and all six checks with:

```bash
# --- enabled but logged out, and a probe that fails outright -----------------
out=$(STUB_MODE=logged-out run)
check "logged out is not usable" "$(field codex usable "$out")" "false"
check "logged out says so" \
  "$(field codex reason "$out" | grep -qi 'logged in' && echo yes || echo no)" "yes"
check "logged out is explicit" "$(field codex auth_status "$out")" "logged_out"
out=$(STUB_MODE=throw run 2>"$TMP/probe.err")
check "a failed probe is distinct" "$(field codex auth_status "$out")" "probe_failed"
check "a failed probe is unusable" "$(field codex usable "$out")" "false"
check "the probe's own text is not exposed" \
  "$(printf '%s%s' "$out" "$(cat "$TMP/probe.err")" | grep -c 'stub: app-server exploded')" "0"
```

`STUB_MODE=throw` reaches `getCodexAuthStatus`'s throw branch, which Task 1 adds,
and the client turns that into `authed: null` — which Task 9 maps to
`auth_status=probe_failed`.

- [ ] **Step 4: Add roster cases for the plugin path**

Presence, version and auth are already covered by Step 3b. What is left is the
two facts that are new to the plugin path:

```bash
# --- the roster row carries a plugin root and no catalog ---------------------
row=$(run | jq -c '.[] | select(.id=="codex")')
check "codex row: no advertised field" "$(jq -r 'has("advertised")' <<<"$row")" "false"
check "codex row: path is the plugin root, not a binary" \
  "$(jq -r '.path' <<<"$row" | grep -c 'stub-codex-plugin')" "1"

row=$(STUB_MODE=logged-out run | jq -c '.[] | select(.id=="codex")')
check "logged out: names the plugin setup command, not codex login" \
  "$(jq -r '.reason' <<<"$row" | grep -c 'codex:setup')" "1"
```

Write the environment prefix inside the command substitution, as above.
`STUB_MODE=logged-out row=$(run | …)` is **two assignments**, not a prefixed
command: it would set `STUB_MODE` in the suite's own shell and leak it into every
later case.

- [ ] **Step 5: Update run-codex-task.test.sh**

Three facts about this suite, because the previous draft got all three wrong:

- It has **no** `$TMP/bin/codex` stub. Its only `$TMP/bin` use is the `nojq`
  shim at lines 176-178, which stays.
- Its invocation helper is `dry()` at line 36, which already passes `--dry-run`.
  There is no `run_task`.
- It needs **no** stub-plugin fixture. Every case it runs is a dry run, and Task
  10 keeps the plugin locator below the `--dry-run` return.

What it does have is about twenty assertions on the `codex exec` argv the dry run
used to print. Replace them by line.

**Lines 79-85** — `cmd=$(dry …)`, the eight-fragment `for frag` loop and the
`--dangerously-bypass` check:

```bash
req=$(dry --model gpt-5.5 --effort medium | sed -n '2p')
check "dry run: prints a turn request" "$(jq -r '.op' <<<"$req")" "turn"
check "dry run: carries the model" "$(jq -r '.model' <<<"$req")" "gpt-5.5"
check "dry run: carries the effort" "$(jq -r '.effort' <<<"$req")" "medium"
check "dry run: workspace-write sandbox" "$(jq -r '.sandbox' <<<"$req")" "workspace-write"
check "dry run: persists the thread" "$(jq -r '.persistThread' <<<"$req")" "true"
check "dry run: carries the report schema" \
  "$(jq -r '.schemaPath' <<<"$req" | grep -c 'codex-report-schema.json')" "1"
check "dry run: names the worktree" "$(jq -r '.cwd' <<<"$req")" "$TMP/work"
check "dry run: never bypasses the sandbox" \
  "$(jq -r '.sandbox' <<<"$req" | grep -c 'bypass')" "0"
```

**Lines 87-96** — the two timeout checks **and the comment at 90-94**. That
comment explains a SIGPIPE hazard specific to the old two-line `timeout=…` /
`codex …` output and the `grep -q` that read it; the replacement prints one JSON
line and reads it with `jq`, so delete the comment with the checks rather than
leaving stale prose. `timeout=<s>` is no longer printed at all: the bound travels
as `deadlineMs`.

```bash
check "deadline defaults from codex-timeout" "$(jq -r '.deadlineMs' <<<"$req")" "900000"
check "explicit timeout wins" \
  "$(dry --model gpt-5.5 --effort medium --timeout 42 | sed -n '2p' | jq -r '.deadlineMs')" "42000"
```

**Lines 98-121** — the resume block (four checks) and the flag-ordering block
(four checks, plus `res_cmd` at 115). Ordering is no longer a correctness
property: there is no argv, and the thread id is a request field. Delete the
`before()` helper at lines 22-31 and its comment, and replace both blocks with:

```bash
# A resumed run must still re-send the model and the effort: the client starts a
# fresh thread unless resumeThreadId is set, and a resumed thread has to carry
# the tier the ledger recorded.
res=$(dry --model gpt-5.5 --effort high --resume 01a0-thread | sed -n '2p')
check "resume carries the thread id" "$(jq -r '.resumeThreadId' <<<"$res")" "01a0-thread"
check "resume re-sends the model" "$(jq -r '.model' <<<"$res")" "gpt-5.5"
check "resume re-sends the effort" "$(jq -r '.effort' <<<"$res")" "high"
check "resume still asks for a persisted thread" "$(jq -r '.persistThread' <<<"$res")" "true"
```

**Lines 123-129** — the non-resume block:

```bash
plain=$(dry --model gpt-5.5 --effort medium | sed -n '2p')
check "a non-resume run sends no thread id" "$(jq -r '.resumeThreadId' <<<"$plain")" "null"
check "a non-resume run still names the worktree" "$(jq -r '.cwd' <<<"$plain")" "$TMP/work"
check "a non-resume run still asks for workspace-write" "$(jq -r '.sandbox' <<<"$plain")" "workspace-write"
```

**Lines 191-202** — the space round-trip, which greps `'^codex '` and `eval`s the
printed argv. JSON has no shell quoting to round-trip, but the path must still
arrive whole:

```bash
mkdir -p "$TMP/dir with space"
spaced=$(bash "$SCRIPT" --brief "$TMP/brief.md" --report "$TMP/report.md" \
  --cwd "$TMP/dir with space" --model gpt-5.5 --effort medium --dry-run 2>/dev/null \
  | sed -n '2p')
check "dry run carries a space-containing path whole" \
  "$(jq -r '.cwd' <<<"$spaced")" "$TMP/dir with space"
```

Lines 40-76 (the schema and validation checks), 131-189 (malformed input, the
missing-jq guard, and "rejected input prints nothing on stdout") and 204-205 are
untouched: none of them reads the argv.

- [ ] **Step 6: Run both suites**

Run:

```bash
timeout 300 bash plugins/dr-superpowers/tests/detect.test.sh
timeout 300 bash plugins/dr-superpowers/tests/run-codex-task.test.sh
```

Expected: both `0 failed`.

- [ ] **Step 7: Commit**

```bash
git add plugins/dr-superpowers/tests/detect.test.sh plugins/dr-superpowers/tests/run-codex-task.test.sh
git commit -m "test(superpowers): cover the plugin-backed roster"
```

**Implementer:** dr-superpowers:impl-opus-low
**Evaluation:** files 1 - spec 1 - coupling 1 - risk 1 = 4

---

### Task 14: reference/external-executor.md: retire the catalog prose

**Files:**
- Modify: `plugins/dr-superpowers/reference/external-executor.md:369-394,413-415,450,459-463,465-469`

**Interfaces:**
- Consumes: the status line in Contracts.
- Produces: prose that matches the shipped behaviour. Nothing later reads it.

Seven passages describe a model catalog, a `codex exec` argv, a refusal read from
a log file, or a coreutils `timeout` — none of which exist after Tasks 6, 7 and
8. Each has exact replacement text below; do not paraphrase, because
`tests/lanes.test.sh` and `tests/ladder.test.sh` read some of these lines.

**Work from the bottom of the file upwards, or match on the quoted text rather
than the line number.** Every line number below is from the unmodified file, and
Steps 2 and 4c each delete a paragraph, which shifts everything after it.

- [ ] **Step 1: The tier paragraph (369-373)**

Replace:

```text
`codex:light` passes `--tier light`, which runs the `codex-judge` block's last
row and never falls back. `codex:heavy` and `codex:heavy+judge-fable` pass
`--tier heavy`: the runner takes the block's first row when the local model
catalog advertises it, takes the last row whenever the catalog is absent,
unreadable or silent, and falls back once on a refusal. `--kind risk3` is the
```

with:

```text
`codex:light` passes `--tier light`, which runs the `codex-judge` block's last
row and never falls back. `codex:heavy` and `codex:heavy+judge-fable` pass
`--tier heavy`: the runner takes the block's first row, and falls back once to
the last row on a refusal. There is no catalog to consult first - the codex
plugin advertises no model list, and reading Codex's own cache would cross the
boundary the session gate exists to hold. `--kind risk3` is the
```

- [ ] **Step 2: The catalog substitution paragraph (388-394)**

Delete the whole paragraph, from `On a `--tier heavy` run, a status line naming the block's last row with`
through `nothing to say.` It described a selection that fell closed before the
run, which cannot happen now: the preferred rung is always attempted.

- [ ] **Step 3: The argv paragraph (413-415)**

Replace the whole paragraph, all three lines of it:

```text
Use `codex exec`, not `codex exec review`: the latter imposes its own report
shape. The schema is a plugin file, outside every worktree, so it can never land
in a task's commit.
```

with:

```text
Task and plan kinds send this plugin's own output schema, never Codex's review
report shape: a seat must return the criteria the Claude judges return. The
schema is a plugin file, outside every worktree, so it can never land in a
task's commit.
```

- [ ] **Step 4: The two status-line fences, the refusal-log sentence, and the second catalog paragraph**

Four edits here, not one. Line 459 is prose, not a fence: the two fences carrying
`evidence=<fetched_at>` are at 378 and 450.

**4a. Both fences (378 and 450).** Each reads:

```text
codex-judge <model>/<effort> status=OK|FALLBACK|TIMEOUT|FAILED exit=<n> out=<path> evidence=<fetched_at>
```

Change `evidence=<fetched_at>` to `evidence=none` in **both**, and add, directly
below the first fence only:

```text
`evidence=none` is constant. This plugin reads no model catalog, so there is no
date to quote; the field is kept only because skills and suites read the line's
shape.
```

**4b. The refusal-log sentence (381-386).** Replace:

```text
Read that line and nothing else. `OK` and `FALLBACK` are a seat that reviewed;
`FALLBACK` additionally means the preferred rung refused the run, so say the
substitution aloud and record it in the task's ledger line with the reason the
runner prints in its own `refused (...)` message — it reads that line from
`<out>.stderr` or `<out>.stdout`, because an API-level refusal arrives on the
JSON stream rather than on stderr.
```

with:

```text
Read that line and nothing else. `OK` and `FALLBACK` are a seat that reviewed;
`FALLBACK` additionally means the preferred rung refused the run, so say the
substitution aloud and record it in the task's ledger line with the reason the
runner prints in its own `refused (...)` message. That reason comes from the
client's own result rather than from a log file: a refusal is classified from
the turn's error field, so which stream carried it no longer matters.
```

**4c. The second catalog paragraph (459-463).** Delete it in full, from `A status
line naming the block's last row with` through `refused anything.` It is the same
substitution Step 2 deletes at 388-394, repeated in the final-review section, and
it ceases to exist for the same reason.

- [ ] **Step 5: The deadline paragraph (465-469)**

Replace:

```text
`codex exec review` is purpose-built for this and takes no sandbox flag, because
review is read-only by nature. Run the runner as a background Bash call: the
Bash tool's own `timeout` caps at ten minutes while a whole-branch round needs
more, and a background call is not bound by it at all. The bound is the
`codex-judge` row's third field, applied by the runner with coreutils `timeout`.
```

with:

```text
The final-review kind runs read-only by nature and takes no sandbox flag. Run
the runner as a background Bash call: the Bash tool's own `timeout` caps at ten
minutes while a whole-branch round needs more, and a background call is not
bound by it at all. The bound is the `codex-judge` row's third field, which the
runner passes to the client as a deadline; the client interrupts the turn and
reaps the broker when it expires.
```

- [ ] **Step 5b: Say how the final round is now composed**

Directly below the paragraph Step 5 replaced, add:

```text
The runner composes that round's prompt itself: `criteria/codex-final-review.md`
followed by `git diff <base>...HEAD`. It does not use the Codex plugin's own
review call, which reads only the model, the thread name and a target branch and
answers in Codex's report shape — a seat's criteria and its schema would both be
discarded. `--kind final` still takes no `--prompt`, and the round still returns
a markdown findings list, which is what [final-review.md](final-review.md) step 3
deduplicates.
```

- [ ] **Step 5c: The task-seat deadline sentence (355-359)**

One more passage names coreutils `timeout`, and it sits outside every range
above. Replace:

```text
plan's copy, applies the `codex-judge` row's bound with coreutils `timeout`, and
```

with:

```text
plan's copy, passes the `codex-judge` row's bound to the client as a deadline, and
```

- [ ] **Step 6: Verify no catalog prose survives**

Run:

```bash
grep -niE 'fetched_at|models_cache|did not advertise|coreutils' plugins/dr-superpowers/reference/external-executor.md
```

Expected: no output.

The pattern deliberately omits `catalog` and `advertis`. The replacement text
Steps 1 and 4a add uses both words — to say that no catalog is read — so a grep
matching them would send an implementer to rewrite what this task just wrote.

- [ ] **Step 7: Run the prose suites**

Run:

```bash
timeout 300 bash plugins/dr-superpowers/tests/lanes.test.sh
timeout 300 bash plugins/dr-superpowers/tests/ladder.test.sh
node scripts/validate-repository.mjs
```

Expected: both suites `0 failed`; the validator prints `valid`.

- [ ] **Step 8: Commit**

```bash
git add plugins/dr-superpowers/reference/external-executor.md
git commit -m "docs(superpowers): retire the catalog prose"
```

**Implementer:** dr-superpowers:impl-sonnet-medium
**Evaluation:** files 0 - spec 1 - coupling 1 - risk 0 = 2

---

### Task 15: Calibration and smoke notes

**Files:**
- Create: `docs/superpowers/notes/2026-09-16-codex-through-plugin-calibration.md`

**Interfaces:**
- Consumes: nothing.
- Produces: the evidence record the trust flip will amend. Nothing later reads it.

- [ ] **Step 1: Run the gate and record its line**

Run: `bash plugins/dr-superpowers/scripts/codex-gate`

Record the exact line. On this machine it is expected to read
`codex-gate usable=false reason=plugin-not-enabled review=false lane=false resets_at=- source=probe`.

- [ ] **Step 2: Write the note**

Create `docs/superpowers/notes/2026-09-16-codex-through-plugin-calibration.md`:

```markdown
# Codex through the plugin — calibration and smoke results

Spec: `docs/superpowers/specs/2026-09-16-dr-superpowers-codex-through-plugin-design.md` §11.
Run: 2026-09-16, not run to completion — paste the `codex-gate` line from Step 1 here.

Both gates replay through the migrated path: the review runner and the task
runner now reach Codex only through `scripts/lib/codex-client.mjs`. Neither can
run while the gate reports Codex unusable.

## Calibration

| Plan | Version | Status line | Recorded | Max delta | Result |
|---|---|---|---|---|---|
| project-state | d6c288c | - | 17 / 16 / 17 / 16 | - | PENDING — codex unusable |
| judge-seats | 01f5a2a | - | 17 / 18 / 16 / 16 | - | PENDING — codex unusable |
| inline-mode | 69c6b48 | - | 17 / 18 / 14 / 16 | - | PENDING — codex unusable |
| small-model | 5e96f14 | - | 17 / 17 / 16 / 17 | - | PENDING — codex unusable |

Gate: PENDING. The review surface stays off: `trust.calibration` in
`plugins/dr-superpowers/reference/codex-plugin.json` stays `pending`.

## Smoke test

Run: 2026-09-16, not run to completion — same gate line.

Gate: PENDING. The lane surface stays off: `trust.smoke` stays `pending`.

## What a later session must do

Codex quota resets 2026-09-20 17:03 (+07), and `codex@openai-codex` must be
enabled in the profile the session runs under — it is enabled in `~/.claude` but
not in `~/.claude-alt`, which is where this repository is developed. With both
true, re-run each gate, replace the PENDING rows with the measured results, and
flip the matching `trust` field in a plugin release.
```

- [ ] **Step 3: Confirm trust is untouched**

Run: `jq -c '.trust' plugins/dr-superpowers/reference/codex-plugin.json`
Expected: `{"calibration":"pending","smoke":"pending"}`

- [ ] **Step 4: Commit**

```bash
git add docs/superpowers/notes/2026-09-16-codex-through-plugin-calibration.md
git commit -m "docs(superpowers): record the plugin-path gates"
```

**Implementer:** dr-superpowers:impl-haiku
**Evaluation:** files 0 - spec 0 - coupling 0 - risk 0 = 0

---

### Task 16: README, manifests and the program amendment

**Files:**
- Modify: `plugins/dr-superpowers/README.md`
- Modify: `plugins/dr-superpowers/.claude-plugin/plugin.json`
- Modify: `plugins/dr-superpowers/.codex-plugin/plugin.json`
- Modify: `docs/superpowers/specs/2026-09-11-dr-superpowers-fork-design.md`

**Interfaces:**
- Consumes: nothing.
- Produces: nothing.

- [ ] **Step 1: Bump both manifests**

Set `"version": "1.10.0"` in `plugins/dr-superpowers/.claude-plugin/plugin.json` and `plugins/dr-superpowers/.codex-plugin/plugin.json`. The two must match.

- [ ] **Step 2: Update the README**

Five passages are stale, listed here with their line numbers in the unmodified
file. Edit them from the bottom up, or match on the quoted text.

**188-193.** In the sentence beginning `every Codex seat runs through`, replace
`which checks availability on each run and falls back to `gpt-5.6-sol` whenever
the local model catalog does not advertise Astra` with `which checks availability
on each run and falls back once to `gpt-5.6-sol` when Astra refuses the run`.

**168-175.** In the paragraph beginning `A different machine, account, or Codex
version`, replace `must verify advertised capabilities and supported CLI flags
before using the tables` with `must verify the tables against its own account
before relying on them`, and delete the sentence from `The flag-position fact
above is the one that has` through `only a re-probe can.` — it describes argv
parsing this plugin no longer does.

**163-166.** In the paragraph beginning `That probe is a dated observation`,
replace the last sentence, `Catalog listing is not entitlement, which is why the
judge seats fall back at runtime rather than trusting either list.`, with:

```markdown
This plugin reads no model catalog at all: the judge seats attempt the preferred
rung and fall back once on a refusal, which is the only evidence of entitlement
that has ever been reliable.
```

**150-161.** Delete both `codex exec resume` bullets — 150-153 and 154-161 — and
put one bullet in their place:

```markdown
- Resume is a request field, not a subcommand. `scripts/lib/codex-client.mjs`
  passes `resumeThreadId`, and the runner re-sends the model and the effort on
  every resumed turn, because a resumed thread that fell back to the user's
  config defaults would run a fix round at a tier the ledger does not record.
```

**After 161**, where the bullet list ends. Insert the paragraph describing the
plugin path. Not after 142: that line ends the reasoning-efforts bullet and 143
begins `- Codex **cannot commit**`, so a paragraph there lands mid-list.

```markdown
Every Codex interaction — the session gate, both runners and the executor
roster — goes through the official `codex@openai-codex` plugin.
`scripts/codex-plugin` locates it for the active profile and enforces a version
allowlist; `scripts/lib/codex-client.mjs` runs one turn through the plugin's own
client and reaps the broker it causes to exist. This plugin never names the
`codex` executable and never reads Codex-owned state.
```

Then confirm nothing stale survives:

```bash
grep -nE 'codex exec|codex binary|codex login|models_cache|CODEX_HOME|advertis' plugins/dr-superpowers/README.md
```

Expected: no output.

- [ ] **Step 3: Amend the program design**

At the end of the amendment list in `docs/superpowers/specs/2026-09-11-dr-superpowers-fork-design.md` §6, replace the paragraph beginning "A ninth sub-project, "Codex through the plugin", moves" with:

```markdown
**Amendment 2026-09-16 (sub-project 9 spec).** Sub-project 9, "Codex through the
plugin", is the last of nine. `scripts/lib/codex-client.mjs` becomes the single
seam to the official plugin; `run-codex-review.sh`, `run-codex-task.sh` and the
executor roster move onto it. The `models_cache.json` read is dropped, settling
ruling 18 by removing the catalog rather than relocating it, and the status
line's `evidence=` becomes the constant `none`. Ruling 12 is narrowed to the
gate: `runAppServerTurn` connects through a broker and its thread helpers are
unexported, so runs use broker mode with a reaper this plugin owns. Shipping is
gated on calibration and smoke replayed through the new path; both record
`PENDING` while Codex is unusable. Details:
`docs/superpowers/specs/2026-09-16-dr-superpowers-codex-through-plugin-design.md`.
```

- [ ] **Step 4: Full verification**

Run:

```bash
node scripts/validate-repository.mjs
timeout 900 node scripts/test-all.mjs
claude plugin validate plugins/dr-superpowers
```

Expected: the validator prints `valid`; `test-all` shows only the pre-existing `tests/ui-discovery.test.mjs` `rg: command not found` failure; `claude plugin validate` passes.

- [ ] **Step 5: Confirm the boundary holds**

Run:

```bash
grep -rnE 'command -v codex|codex --version|codex login|codex exec|CODEX_HOME|models_cache' plugins/dr-superpowers/scripts/
```

Expected: no output.

- [ ] **Step 6: Commit**

```bash
git add plugins/dr-superpowers/README.md plugins/dr-superpowers/.claude-plugin/plugin.json plugins/dr-superpowers/.codex-plugin/plugin.json docs/superpowers/specs/2026-09-11-dr-superpowers-fork-design.md
git commit -m "chore(superpowers): bump to 1.10.0"
```

**Implementer:** dr-superpowers:impl-sonnet-medium
**Evaluation:** files 2 - spec 0 - coupling 0 - risk 0 = 2
