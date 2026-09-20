// Stub of codex@openai-codex 1.0.3 scripts/lib/codex.mjs, for dr-superpowers
// tests. Behaviour is scripted by STUB_* environment variables so a suite can
// drive every branch of codex-client.mjs without a real Codex, a real account
// or a real broker.
import fs from "node:fs";
import path from "node:path";

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
export async function getCodexAuthStatus(cwd) {
  log(`getCodexAuthStatus ${cwd ?? "-"}`);
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
  log(`${label} ${options.model || "-"}/${options.effort || "-"} sandbox=${options.sandbox ?? "-"} schema=${options.outputSchema ? "yes" : "no"} resume=${options.resumeThreadId ?? "-"} persist=${options.persistThread === true}`);
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
  // The task runner's suite pins scope validation, staging and commit, which
  // need a turn that changes the worktree. Paths are relative to cwd.
  if (process.env.STUB_WRITE_PATH) {
    fs.writeFileSync(path.join(cwd, process.env.STUB_WRITE_PATH), `${process.env.STUB_WRITE_CONTENT ?? "produced"}\n`);
  }
  if (process.env.STUB_DELETE_PATH) {
    fs.rmSync(path.join(cwd, process.env.STUB_DELETE_PATH), { force: true });
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
