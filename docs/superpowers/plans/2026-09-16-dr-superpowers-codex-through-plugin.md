# dr-superpowers Codex Through The Plugin Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: the skill the **Execution:** line names — dr-superpowers:subagent-driven-development for `subagent`, dr-superpowers:executing-plans for `inline`. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move every Codex run — the review runner, the task runner and the executor roster — off the `codex` executable and onto the official plugin's client library, through one new module, and drop the `models_cache.json` read that violates the "never read Codex-owned state" boundary.

**Architecture:** A new `scripts/lib/codex-client.mjs` receives an already-vetted plugin root on argv and a JSON request on stdin, runs exactly one Codex turn through the plugin's public `runAppServerTurn` (or `runAppServerReview` for `--kind final`), owns the deadline, the `turn/interrupt` and the broker reaper, and prints a JSON result. `run-codex-review.sh`, `run-codex-task.sh` and `detect-executors.sh` stay bash and keep every externally visible contract — argv, status line, exit codes, task record, resume semantics — replacing only the block that used to build and spawn a `codex exec` argv. `scripts/codex-plugin` remains the single locator and the single place the version allowlist is enforced.

**Tech Stack:** Bash, Node.js (ES modules), `jq`, the official `codex@openai-codex` plugin 1.0.3 client library (`scripts/lib/codex.mjs`, `scripts/lib/app-server.mjs`, `scripts/lib/broker-lifecycle.mjs`), Markdown, git.

**Spec:** `docs/superpowers/specs/2026-09-16-dr-superpowers-codex-through-plugin-design.md`

**Execution:** subagent — `claude --model sonnet --effort high` — Task 2 totals 5 (coupling 2, risk 2), above the inline band's ceiling of 4.

**Program:** `docs/superpowers/specs/2026-09-11-dr-superpowers-fork-design.md` — sub-project 9 of 9 — last

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
  "base": "<git ref>" | null,
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

**`op: "auth"`** ignores every turn field and returns `{ ok, reason, authed: true|false|null, detail }`, used by Task 9.

**Stub fixture contract** (Task 1; consumed by Tasks 2, 3, 4, 5, 6, 9, 10, 12, 13)

`tests/fixtures/stub-codex-plugin/` mirrors the real plugin's layout: `.claude-plugin/plugin.json`, `scripts/lib/codex.mjs`, `scripts/lib/app-server.mjs`, `scripts/lib/broker-lifecycle.mjs`. Behaviour is scripted by environment variables read at import time:

| Variable | Effect |
|---|---|
| `STUB_MODE` | `ok` (default), `refusal`, `quota`, `hang`, `throw`, `logged-out`, `unavailable` |
| `STUB_FINAL_MESSAGE` | the text `runAppServerTurn` returns as `finalMessage` |
| `STUB_TURN_STATUS` | `0` or `1`, default `0` |
| `STUB_EVENT_LOG` | file every stub call appends one line to, for assertions |
| `STUB_EMPTY` | `1` makes a turn return an empty `finalMessage` |
| `STUB_REFUSE_ONCE` | `1` refuses only the first call, so the fallback rung succeeds |
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
let calls = 0;

async function turn(cwd, options, label) {
  calls += 1;
  log(`${label} ${options.model || "-"}/${options.effort || "-"} target=${options.target?.branch ?? "-"}`);
  let m = mode();
  if (process.env.STUB_REFUSE_ONCE === "1") m = calls === 1 ? "refusal" : "ok";
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

// The real runAppServerReview returns `reviewText`, not `finalMessage`
// (codex.mjs:950-960), and takes `options.target`, not a base string
// (codex.mjs:935). The stub mirrors both so a suite cannot pass against a
// shape the plugin never produces.
export async function runAppServerReview(cwd, options = {}) {
  const result = await turn(cwd, options, "runAppServerReview");
  const { finalMessage, ...rest } = result;
  return { ...rest, reviewText: finalMessage };
}

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
node -e "import('./plugins/dr-superpowers/tests/fixtures/stub-codex-plugin/scripts/lib/codex.mjs').then(m => console.log(typeof m.runAppServerTurn, typeof m.getCodexAuthStatus))"
```

Expected: `function function`

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
      resumeThreadId:null, persistThread:false, threadName:null, base:null,
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

# --- kind final routes to runAppServerReview ---
export STUB_EVENT_LOG="$TMP/events.log"
: > "$STUB_EVENT_LOG"
run "$(req '{"kind":"final","base":"main"}')" >/dev/null
check "final: routes to runAppServerReview" \
  "$(grep -c '^runAppServerReview' "$STUB_EVENT_LOG")" "1"
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

function emit(fields) {
  process.stdout.write(`${JSON.stringify({ ...EMPTY, ...fields })}\n`);
  process.exit(0);
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
  if (!root) emit({ reason: "bad-request", stderr: "a plugin root is required" });

  const req = parseRequest(await readStdin());
  if (!req) emit({ reason: "bad-request", stderr: "the request is not a valid turn or auth object" });

  let plugin;
  try {
    plugin = await loadPlugin(root);
  } catch (error) {
    emit({ reason: "plugin-api", stderr: String(error?.message ?? error) });
  }

  const availability = plugin.getCodexAvailability?.(req.cwd);
  if (availability && availability.available === false) {
    emit({ reason: "unavailable", stderr: String(availability.detail ?? "codex is unavailable") });
  }

  if (req.op === "auth") {
    try {
      // `loggedIn`, not `authenticated`: codex.mjs:831-864 is the shape.
      const status = await plugin.getCodexAuthStatus(req.cwd);
      const authed = status?.loggedIn === true;
      emit({
        ok: authed, authed, reason: authed ? null : "logged-out",
        stderr: String(status?.detail ?? "")
      });
    } catch (error) {
      emit({ reason: "plugin-api", authed: null, stderr: String(error?.message ?? error) });
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
      emit({ reason: "bad-request", stderr: `cannot read output schema: ${String(error?.message ?? error)}` });
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
  // runAppServerReview takes a structured target, not a base string
  // (codex.mjs:935; the shape is codex-companion.mjs:262).
  if (req.kind === "final") {
    options.target = req.base ? { type: "baseBranch", branch: req.base } : null;
  }

  let result;
  try {
    result = req.kind === "final"
      ? await plugin.runAppServerReview(req.cwd, options)
      : await plugin.runAppServerTurn(req.cwd, options);
  } catch (error) {
    emit({
      reason: "plugin-api", threadId: seen.threadId, turnId: seen.turnId,
      stderr: String(error?.message ?? error)
    });
  }

  const turnStatus = typeof result?.status === "number" ? result.status : null;
  emit({
    ok: turnStatus === 0,
    turnStatus,
    threadId: result?.threadId ?? seen.threadId,
    turnId: result?.turnId ?? seen.turnId,
    // runAppServerReview returns reviewText; runAppServerTurn returns
    // finalMessage. One field reaches bash either way.
    finalMessage: result?.finalMessage ?? result?.reviewText ?? null,
    reason: turnStatus === 0 ? null : "plugin-api",
    stderr: String(result?.stderr ?? "")
  });
}

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
    result = await Promise.race([
      req.kind === "final"
        ? plugin.runAppServerReview(req.cwd, options)
        : plugin.runAppServerTurn(req.cwd, options),
      expiry
    ]);
  } catch (error) {
    clearTimeout(timer);
    emit({
      reason: "plugin-api", threadId: seen.threadId, turnId: seen.turnId,
      stderr: String(error?.message ?? error)
    });
  }
  clearTimeout(timer);

  if (timedOut) {
    emit({
      reason: "timeout", timedOut: true, interrupted,
      threadId: seen.threadId, turnId: seen.turnId,
      stderr: "the deadline expired"
    });
  }

  const turnStatus = typeof result?.status === "number" ? result.status : null;
  emit({
    ok: turnStatus === 0,
    turnStatus,
    threadId: result?.threadId ?? seen.threadId,
    turnId: result?.turnId ?? seen.turnId,
    finalMessage: result?.finalMessage ?? result?.reviewText ?? null,
    reason: turnStatus === 0 ? null : "plugin-api",
    stderr: String(result?.stderr ?? "")
  });
}

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
  process.stdout.write(`${JSON.stringify({ ...EMPTY, ...fields, reaped })}\n`);
  process.exit(0);
}
```

Every existing `emit(...)` call becomes `await emit(...)`, and `main().catch(...)` becomes `main().catch(async (error) => await emit({ reason: "plugin-api", stderr: String(error?.message ?? error) }))`.

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
Expected: PASS — `31 passed, 0 failed`

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
    finalMessage: result?.finalMessage ?? result?.reviewText ?? null,
    refusal, quota, reason,
    stderr: String(result?.stderr ?? "")
  });
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `timeout 120 bash plugins/dr-superpowers/tests/codex-client.test.sh`
Expected: PASS — `40 passed, 0 failed`

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
- Modify: `plugins/dr-superpowers/scripts/run-codex-review.sh:229-277`

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
    --arg base "${base:-}" --argjson deadline "$(( $3 * 1000 ))" \
    '{op:"turn", kind:$kind, cwd:$cwd, model:$model, effort:$effort,
      prompt:$prompt,
      schemaPath:(if $schema == "" then null else $schema end),
      sandbox:"read-only", resumeThreadId:null, persistThread:false,
      threadName:null,
      base:(if $base == "" then null else $base end),
      deadlineMs:$deadline}')
  printf '%s' "$request" | node "$HERE/lib/codex-client.mjs" "$plugin_root" 2>"$4.stderr"
}

# The report is whatever the seat returned. Writing it here rather than in the
# client keeps the --out contract with bash, which owns it.
write_out() { # write_out <result-json>
  jq -r '.finalMessage // ""' <<<"$1" > "$out"
}
```

- [ ] **Step 2: Replace the outcome block**

Replace everything from `rc=$(run_seat "$model" "$effort" "$secs" "$out")` to the end of the file with:

```bash
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
git add plugins/dr-superpowers/scripts/run-codex-review.sh
git commit -m "feat(superpowers): run review seats through the client"
```

**Implementer:** dr-superpowers:impl-opus-low
**Evaluation:** files 0 - spec 0 - coupling 2 - risk 2 = 4

---

### Task 7: run-codex-review.sh: drop the catalog and dry-run argv

**Files:**
- Modify: `plugins/dr-superpowers/scripts/run-codex-review.sh:127-170`

**Interfaces:**
- Consumes: the status line in Contracts.
- Produces: `evidence=none` on every status line, and request JSON from `--dry-run`. Task 12 asserts both.

- [ ] **Step 1: Delete the catalog lookup**

In `plugins/dr-superpowers/scripts/run-codex-review.sh`, delete the whole block that computes `advertised`, `evidence` and `listed` from the roster row, and replace it with:

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
    --arg effort "$effort" --arg schema "${schema:-}" --arg base "${base:-}" \
    --argjson deadline "$(( secs * 1000 ))" \
    '{op:"turn", kind:$kind, cwd:$cwd, model:$model, effort:$effort,
      schemaPath:(if $schema == "" then null else $schema end),
      sandbox:"read-only",
      base:(if $base == "" then null else $base end),
      deadlineMs:$deadline}'
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

- [ ] **Step 4: Verify the dry run**

`--dry-run` returns before the locator runs, so this works on this machine even
though the gate reports `plugin-not-enabled`:

```bash
bash plugins/dr-superpowers/scripts/run-codex-review.sh --kind task \
  --cwd "$PWD" --out /tmp/dry.json --prompt /dev/null --dry-run 2>&1 | head -3
```

Expected: `would-run:` then a single JSON object naming `"op":"turn"`, then a status line ending `evidence=none`.

If it instead prints `status=FAILED`, the Step 1 insertion landed above the
`--dry-run` block; move it below `valid_output()`.

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
- Modify: `plugins/dr-superpowers/scripts/run-codex-task.sh:27,114-145,178,265-337`

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

```bash
# The plugin root, resolved once. scripts/codex-plugin owns the locator and the
# version allowlist; this script never names the codex executable.
plugin_line=$(bash "$HERE/codex-plugin") || die "the codex plugin is not usable: $plugin_line"
plugin_root=${plugin_line#*root=}

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
      persistThread:true, threadName:null, base:null, deadlineMs:$deadline}'
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
dr_task_update '.phase = "running" | .processes = []' || die 'cannot persist running phase'

result=$(build_request | node "$HERE/lib/codex-client.mjs" "$plugin_root" 2>"$report.stderr")
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

- [ ] **Step 6: Confirm nothing references the deleted machinery**

Run:

```bash
grep -nE 'codex_pid|codex_winpid|kill_codex_tree|set -m|set \+m|argv\[|command -v timeout' plugins/dr-superpowers/scripts/run-codex-task.sh
grep -nE '(^|\s)codex "\$|command -v codex|codex exec' plugins/dr-superpowers/scripts/run-codex-task.sh
```

Expected: no output from either.

- [ ] **Step 7: Run the task-runner suite**

Run: `timeout 300 bash plugins/dr-superpowers/tests/run-codex-task.test.sh`
Expected: FAIL on the four dry-run checks pinning `timeout=900`, `exec`, `-C` and `--output-schema`, and on every case driven by the `$TMP/bin/codex` stub binary. Task 13 updates them. Record the failing count in the ledger.

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
Replace the whole function with:

```bash
# The only child is node, which exits when the client does, and the client reaps
# the broker it caused to exist. Nothing here has a process group to signal.
cleanup() {
  [ -n "${TMPDIR_RUN:-}" ] && rm -rf "$TMPDIR_RUN"
  return 0
}
```

Keep whatever temporary-directory variable the existing `cleanup` removed; if it
removed none, the body is `return 0` alone.

- [ ] **Step 2: Record the reap in the task record**

Directly after the `discovered_thread` block Task 10 added, add:

```bash
# The client reaps the broker it caused to exist. Recording the outcome makes a
# leak visible in the task record rather than only in a process list. The
# default matters: a crashed node leaves $result empty, and a bare --argjson of
# an empty string makes jq error and the runner die.
dr_task_update '.reaped = $reaped' \
  --argjson reaped "$(jq -r 'if .reaped == true then true else false end' <<<"${result:-{\}}" 2>/dev/null || echo false)" \
  || die 'cannot persist reap outcome'
```

- [ ] **Step 3: Verify the record still validates**

`scripts/lib/task-state.sh` validates the record's shape. Confirm it tolerates
the new key before relying on it:

```bash
grep -n 'reaped\|required\|has(' plugins/dr-superpowers/scripts/lib/task-state.sh | head
timeout 300 bash plugins/dr-superpowers/tests/task-state.test.sh
```

Expected: the suite reports `0 failed`. If the validator rejects unknown keys,
add `reaped` to whatever list it checks, in the same commit.

- [ ] **Step 4: Verify no orphan is possible**

Run:

```bash
grep -nE 'kill_codex_tree|codex_pid|codex_winpid|taskkill|launch-pending' plugins/dr-superpowers/scripts/run-codex-task.sh
```

Expected: no output.

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
```

The stub fixture carries version `1.0.3` in its `.claude-plugin/plugin.json` and
ships `scripts/lib/app-server.mjs`, which is what `scripts/codex-plugin` checks
before calling a root usable.

- [ ] **Step 2: Carry the stub environment into every run**

The existing `run()` helper passes `PATH`, `CODEX_REVIEW_ROSTER` and
`CODEX_REVIEW_GATE`. Add the plugin-facing variables so a per-case `STUB_MODE`
reaches the client:

```bash
run() { # run <args...>
  PATH="$TMP/bin:$PATH" CODEX_REVIEW_ROSTER="$TMP/bin/detect-stub" CODEX_REVIEW_GATE="$TMP/gate-stub" \
    CLAUDE_CONFIG_DIR="$CLAUDE_CONFIG_DIR" CLAUDE_PROJECT_DIR= DR_CODEX_POLICY="$DR_CODEX_POLICY" \
    STUB_MODE="${STUB_MODE:-ok}" STUB_TURN_STATUS="${STUB_TURN_STATUS:-0}" \
    STUB_EMPTY="${STUB_EMPTY:-0}" STUB_REFUSE_ONCE="${STUB_REFUSE_ONCE:-0}" \
    STUB_FINAL_MESSAGE="${STUB_FINAL_MESSAGE:-}" STUB_EVENT_LOG="${STUB_EVENT_LOG:-}" \
    "$BASH_BIN" "$SCRIPT" "$@" 2>"$TMP/err"
}
```

- [ ] **Step 3: Delete the codex binary stub and its writer**

Delete the `$TMP/bin/codex` heredoc, every `chmod +x "$TMP/bin/codex"`, and the
helper that set `CODEX_STUB_MODE`. Nothing reaches a `codex` binary any more, so
a stub binary left in place would only mask a regression.

- [ ] **Step 4: Remap every outcome case**

Each old `CODEX_STUB_MODE` value has one replacement. The call shape becomes
`STUB_MODE=<mode> run --kind <k> --cwd "$TMP/work" --out "$TMP/o.md" --prompt "$TMP/p.md"`,
capturing into `out` and reading the last line for the status.

| Old `CODEX_STUB_MODE` | New environment | Expected status |
|---|---|---|
| `ok-final` | `STUB_MODE=ok` | `OK` |
| `empty` | `STUB_MODE=ok STUB_EMPTY=1` | `FAILED` |
| `noout` | `STUB_MODE=ok STUB_EMPTY=1` | `FAILED` |
| `hang` | `STUB_MODE=hang`, with the rung's seconds lowered by the fixture | `TIMEOUT` |
| `refuse-then-ok` | `STUB_REFUSE_ONCE=1` | `FALLBACK` |
| `refuse-always` | `STUB_MODE=refusal` | `FAILED` |
| `prose-fail` | `STUB_MODE=ok STUB_TURN_STATUS=1 STUB_FINAL_MESSAGE` quoting a refusal phrase | `FAILED`, and no fallback ran |
| `refuse-stdout` | `STUB_MODE=refusal` | `FAILED` |
| `authfail` | `STUB_MODE=logged-out` | `FAILED` |
| `cancel` | `STUB_MODE=throw` | `FAILED` |
| `refuse-then-quota` | `STUB_REFUSE_ONCE=1 STUB_MODE=quota` | `FAILED`, session marked off |

The `prose-fail` row is the case that proves the migration's point: the old
runner grepped a transcript and would call that a refusal, while the client
classifies from the result's own error field and does not.

- [ ] **Step 5: Fix the selection and evidence assertions**

The default heavy tier is the ladder's first row, `gpt-6-astra`, not
`gpt-5.6-sol`; keep every existing selection assertion naming `gpt-6-astra`.

Replace the check reading `evidence=2026-09-14T13:35:00Z` with:

```bash
present "dry run reports no catalog evidence" "$out" "evidence=none"
```

Then run `grep -n 'evidence=' plugins/dr-superpowers/tests/codex-review.test.sh`
and change every remaining expected value, including the `evidence=unknown` on
the gate-off branch, to `evidence=none`. Delete the cases exercising a catalog
that did or did not advertise a pair, and the advertised-pair roster fixtures
they used: a roster row no longer carries `advertised`.

- [ ] **Step 6: Replace the argv assertions**

Every check asserting that `--dry-run` printed a `codex exec` argv line becomes
an assertion on the request JSON, which is printed on the second line:

```bash
out=$(run --kind task --cwd "$TMP/work" --out "$TMP/o.md" --prompt "$TMP/p.md" --dry-run)
check "dry-run: prints a turn request" "$(sed -n '2p' <<<"$out" | jq -r '.op')" "turn"
check "dry-run: carries the model" "$(sed -n '2p' <<<"$out" | jq -r '.model')" "gpt-6-astra"
check "dry-run: read-only sandbox" "$(sed -n '2p' <<<"$out" | jq -r '.sandbox')" "read-only"
check "dry-run: deadline in milliseconds" "$(sed -n '2p' <<<"$out" | jq -r '.deadlineMs > 0')" "true"
```

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
holding shims for `jq timeout head tr` and a stub `codex` binary. After Task 9
the roster needs `node` and `bash`, so replace that helper with:

```bash
# node and bash are needed now: the codex row is probed through the plugin, not
# through a codex binary on PATH. The real PATH is appended rather than
# replaced, and the codex stub binary is gone, so a codex on this machine's PATH
# can no longer reach the roster.
run() { PATH="$TMP/bin:$PATH" CLAUDE_CONFIG_DIR="$TMP/config" CLAUDE_PROJECT_DIR= \
        DR_CODEX_POLICY="$TMP/policy.json" STUB_MODE="${STUB_MODE:-ok}" \
        "$BASH_BIN" "$SCRIPT"; }
```

- [ ] **Step 2: Add the stub-plugin fixture**

Add the same fixture block Task 12 Step 1 adds, using this suite's own `TMP`
variable, so `scripts/codex-plugin` resolves the Task 1 stub.

- [ ] **Step 3: Delete the codex binary stubs and the catalog fixtures**

Delete every `$TMP/bin/codex` writer and its `chmod +x` (lines 53-54, 65-66,
73-74 and the heredoc at 137-144), the `CODEX_HOME="$TMP/codexhome"` export and
the `$TMP/codexhome` tree, and all eighteen assertions reading `.advertised`,
including the cases distinguishing `null` from `[]`. None of that behaviour
exists after Tasks 8 and 9.

- [ ] **Step 4: Add roster cases for the plugin path**

```bash
# --- the codex row is plugin-backed, never PATH-backed ---
row=$(run | jq -c '.[] | select(.id=="codex")')
check "codex row: present from the plugin" "$(jq -r '.present' <<<"$row")" "true"
check "codex row: version from the plugin" "$(jq -r '.version' <<<"$row")" "1.0.3"
check "codex row: authed from the plugin" "$(jq -r '.authed' <<<"$row")" "true"
check "codex row: usable" "$(jq -r '.usable' <<<"$row")" "true"
check "codex row: no advertised field" "$(jq -r 'has("advertised")' <<<"$row")" "false"

STUB_MODE=logged-out row=$(run | jq -c '.[] | select(.id=="codex")')
check "logged out: not usable" "$(jq -r '.usable' <<<"$row")" "false"
check "logged out: names the plugin, not codex login" \
  "$(jq -r '.reason' <<<"$row" | grep -c 'codex:setup')" "1"

# A profile that does not enable the plugin has no codex lane at all.
printf '{"enabledPlugins":{}}\n' > "$TMP/config/settings.json"
row=$(run | jq -c '.[] | select(.id=="codex")')
check "not enabled: not present" "$(jq -r '.present' <<<"$row")" "false"
check "not enabled: says so" "$(jq -r '.reason' <<<"$row" | grep -c 'not enabled')" "1"
printf '{"enabledPlugins":{"codex@openai-codex":true}}\n' > "$TMP/config/settings.json"
```

- [ ] **Step 5: Update run-codex-task.test.sh**

Add the same fixture block, clear `CLAUDE_PROJECT_DIR`, delete the
`$TMP/bin/codex` stub, and replace the four dry-run assertions that pinned
`timeout=900`, `exec`, `-C` and `--output-schema` with:

```bash
dry=$(run_task --dry-run)
check "task dry-run: prints a turn request" "$(sed -n '2p' <<<"$dry" | jq -r '.op')" "turn"
check "task dry-run: workspace-write sandbox" "$(sed -n '2p' <<<"$dry" | jq -r '.sandbox')" "workspace-write"
check "task dry-run: persists the thread" "$(sed -n '2p' <<<"$dry" | jq -r '.persistThread')" "true"
check "task dry-run: carries the report schema" \
  "$(sed -n '2p' <<<"$dry" | jq -r '.schemaPath' | grep -c 'codex-report-schema.json')" "1"
check "task dry-run: deadline in milliseconds" "$(sed -n '2p' <<<"$dry" | jq -r '.deadlineMs')" "900000"
```

Use whatever invocation helper the suite already defines in place of
`run_task`, adding `--dry-run` to it.

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
- Modify: `plugins/dr-superpowers/reference/external-executor.md:369-373,388-394,414,459,465-469`

**Interfaces:**
- Consumes: the status line in Contracts.
- Produces: prose that matches the shipped behaviour. Nothing later reads it.

Five passages describe a model catalog, a `codex exec` argv or a coreutils
`timeout` that no longer exist. Each has exact replacement text below; do not
paraphrase, because `tests/lanes.test.sh` and `tests/ladder.test.sh` read some of
these lines.

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

- [ ] **Step 3: The argv sentence (414)**

Replace:

```text
Use `codex exec`, not `codex exec review`: the latter imposes its own report
```

with:

```text
Task and plan kinds send this plugin's own output schema, never the review
report shape: a seat must return the criteria the Claude judges return. The
```

Read the following line and adjust its opening so the sentence still reads; the
point being preserved is that the review report shape is unsuitable for a seat.

- [ ] **Step 4: The status-line description (459)**

Replace the fenced example's trailing `evidence=<fetched_at>` with
`evidence=none`, and add directly below the fence:

```text
`evidence=none` is constant. This plugin reads no model catalog, so there is no
date to quote; the field is kept only because skills and suites read the line's
shape.
```

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

- [ ] **Step 6: Verify no catalog prose survives**

Run:

```bash
grep -niE 'catalog|advertis|fetched_at|models_cache|coreutils .timeout.' plugins/dr-superpowers/reference/external-executor.md
```

Expected: no output. If a hit remains, rewrite that sentence to match the
behaviour Tasks 6 and 7 shipped rather than deleting it blindly.

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

Run `grep -nE 'codex exec|codex CLI|codex binary|on PATH|codex login' plugins/dr-superpowers/README.md`
and rewrite each hit so it describes the plugin path. Where the hits form a
contiguous description of how Codex is invoked, replace that block with:

```markdown
Every Codex interaction — the session gate, both runners and the executor
roster — goes through the official `codex@openai-codex` plugin. `scripts/codex-plugin`
locates it for the active profile and enforces a version allowlist;
`scripts/lib/codex-client.mjs` runs one turn through the plugin's own client and
reaps the broker it causes to exist. This plugin never names the `codex`
executable and never reads Codex-owned state.
```

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
