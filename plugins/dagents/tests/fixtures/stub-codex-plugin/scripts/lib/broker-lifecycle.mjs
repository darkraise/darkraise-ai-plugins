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

// The client asks once, before the turn, whether a broker it must not touch
// already exists. Later loads return the post-turn session unless
// STUB_NO_BROKER is set, so a suite can still script the session away.
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
// STUB_SHUTDOWN_FAILS leaves the session visible to a later loadBrokerSession;
// the client tears down after every shutdown regardless, because the real
// broker never removes its session file.
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
