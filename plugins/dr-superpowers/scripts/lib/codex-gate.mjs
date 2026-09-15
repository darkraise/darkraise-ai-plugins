// Probe Codex availability through the codex plugin's own app-server client.
//
// Usage: node codex-gate.mjs <plugin-root> <cwd> <timeout-ms>
// Prints one JSON object: {"usable": bool, "reason": string, "resets_at_epoch": seconds|null}.
//
// Two requests, neither of which runs a model: account/read for the login, and
// account/rateLimits/read for the quota. The plugin's `setup` command reports
// ready with the quota exhausted, so the rate-limit read is the only signal that
// catches it. Direct mode (disableBroker) is deliberate: the broker is a detached
// daemon the plugin's own SessionEnd hook owns, and it would outlive this probe.
import path from "node:path";
import { pathToFileURL } from "node:url";

const [root, cwd, timeoutArg] = process.argv.slice(2);
let client = null;
let settled = false;

async function finish(usable, reason, resetsAtEpoch = null) {
  if (settled) return;
  settled = true;
  try {
    await client?.close();
  } catch {
    // A client that fails to close has already lost its app-server.
  }
  process.stdout.write(`${JSON.stringify({ usable, reason, resets_at_epoch: resetsAtEpoch })}\n`);
  process.exit(0);
}

// The deadline is ours, not coreutils timeout: on Windows `timeout` kills only
// node and strands the app-server it spawned, while close() ends that tree. A
// connect that hangs before returning a client leaves nothing to close.
setTimeout(() => finish(false, "timeout"), Number(timeoutArg) > 0 ? Number(timeoutArg) : 30000);

async function probe() {
  let mod;
  try {
    mod = await import(pathToFileURL(path.join(root, "scripts", "lib", "app-server.mjs")).href);
  } catch {
    return finish(false, "plugin-api");
  }
  const Client = mod?.CodexAppServerClient;
  if (typeof Client?.connect !== "function") return finish(false, "plugin-api");

  try {
    client = await Client.connect(cwd, { disableBroker: true });
  } catch {
    return finish(false, "plugin-api");
  }
  if (settled) return;

  let account;
  try {
    account = await client.request("account/read", { refreshToken: false });
  } catch {
    return finish(false, "plugin-api");
  }
  // The rule the plugin's own buildAppServerAuthStatus applies.
  const type = account?.account?.type;
  if (!(type === "chatgpt" || type === "apiKey" || account?.requiresOpenaiAuth === false)) {
    return finish(false, "logged-out");
  }

  let limits;
  try {
    limits = await client.request("account/rateLimits/read", {});
  } catch (error) {
    const message = String(error?.message ?? error ?? "");
    const missing = message.includes("unknown variant") || message.includes("unknown method");
    return finish(false, missing ? "method-missing" : "plugin-api");
  }
  if (typeof limits?.ordinaryUsageAllowed !== "boolean") return finish(false, "plugin-api");

  const primary = limits.rateLimits?.primary;
  const used = typeof primary?.usedPercent === "number" ? primary.usedPercent : 0;
  if (limits.ordinaryUsageAllowed === true && used < 100) return finish(true, "ok");
  return finish(false, "quota", typeof primary?.resetsAt === "number" ? primary.resetsAt : null);
}

probe().catch(() => finish(false, "plugin-api"));
