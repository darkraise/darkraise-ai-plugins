// Probe whether the Antigravity CLI (agy) is signed in.
//
// Usage: node agy-probe.mjs <root>   (request JSON on stdin)
// Request: {"op":"auth","cwd":"<path>"}
// Prints exactly one JSON line: {"authed": true|false|null}. An answered auth
// request exits 0; any other op, or unreadable input, answers null and exits 2.
//
// `agy models` makes no model call. A signed-in agy exits 0 and lists model ids
// as `<id><TAB><name>` lines after a banner; a signed-out one asks for a
// sign-in. Anything else (a timeout, a spawn failure, an unrelated error)
// proves nothing either way and answers null.
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";

const TIMEOUT_MS = 30000;
const MODEL_LINE = /^[a-z0-9.-]+\t/m;
const SIGN_IN = /sign in|log ?in|login|unauthenticated/i;

function answer(authed, code) {
  // A write to a pipe is asynchronous on macOS and Windows, so exiting straight
  // after it can drop the answer.
  process.stdout.write(`${JSON.stringify({ authed })}\n`, () => process.exit(code));
}

function readRequest() {
  try {
    const request = JSON.parse(fs.readFileSync(0, "utf8"));
    return request && typeof request === "object" ? request : null;
  } catch {
    return null;
  }
}

function listModels(command, cwd) {
  const options = { encoding: "utf8", timeout: TIMEOUT_MS, windowsHide: true };
  if (cwd) options.cwd = cwd;
  return spawnSync(command, ["models"], options);
}

const root = process.argv[2] ?? "";
const request = readRequest();
if (!request || request.op !== "auth") answer(null, 2);
else {
  const cwd = typeof request.cwd === "string" && request.cwd !== "" ? request.cwd : null;
  // A relative root would resolve against cwd, and Windows searches the cwd
  // for a bare name before PATH: a project directory could plant an agy.
  let result = path.isAbsolute(root) ? listModels(path.join(root, "agy"), cwd) : { error: { code: "ENOENT" } };
  if (result.error && result.error.code === "ENOENT") result = listModels("agy", os.tmpdir());
  if (result.error) answer(null, 0);
  else {
    const output = `${result.stdout ?? ""}\n${result.stderr ?? ""}`.replace(/\r/g, "");
    if (result.status === 0 && MODEL_LINE.test(output)) answer(true, 0);
    else if (SIGN_IN.test(output)) answer(false, 0);
    else answer(null, 0);
  }
}
