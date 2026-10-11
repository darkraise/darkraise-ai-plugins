// Stub auth probe satisfying the Contracts probe contract. STUB_PROBE picks
// the branch: ok, logged-out, or throw (a probe that answers without .authed,
// which the roster must read as probe_failed rather than as logged out).
import process from "node:process";

let raw = "";
for await (const chunk of process.stdin) raw += chunk;
let request = {};
try {
  request = JSON.parse(raw);
} catch {
  request = {};
}

const mode = process.env.STUB_PROBE || "ok";
const answer = { op: request.op ?? null, cwd: request.cwd ?? null };

if (mode === "throw") {
  answer.reason = "stub: probe exploded";
} else {
  answer.authed = mode !== "logged-out";
  answer.reason = answer.authed ? null : "logged-out";
}

if (process.env.STUB_PROBE_LOG) {
  const { appendFileSync } = await import("node:fs");
  try {
    appendFileSync(process.env.STUB_PROBE_LOG, `${request.cwd ?? "-"}\n`);
  } catch {
    // A test that cannot write its own log fails on the assertion instead.
  }
}
process.stdout.write(`${JSON.stringify(answer)}\n`);
