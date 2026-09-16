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
  // The deadline is ours, not coreutils timeout: on Windows `timeout` kills
  // only node and strands the app-server it spawned. Interrupting needs both
  // ids, which is why they are captured from progress above.
  const deadlineMs = Number(req.deadlineMs) > 0 ? Number(req.deadlineMs) : 600000;
  let timedOut = false;
  let interrupted = false;
  let timer = null;

  // The interrupt itself is bounded. The real interruptAppServerTurn connects
  // to the broker and awaits an initialize RPC, the turn/interrupt RPC and a
  // close, none with a timeout of its own (codex.mjs:866-906,
  // app-server.mjs:281-319), and the broker that most needs interrupting is
  // the one least likely to answer. An unanswered RPC here would leave the race
  // unsettled and this process hanging with no result for bash to read.
  const INTERRUPT_GRACE_MS = 5000;
  const expiry = new Promise((resolve) => {
    timer = setTimeout(async () => {
      timedOut = true;
      let grace = null;
      try {
        const outcome = await Promise.race([
          plugin.interruptAppServerTurn(req.cwd, {
            threadId: seen.threadId,
            turnId: seen.turnId
          }),
          new Promise((settle) => {
            grace = setTimeout(() => settle(null), INTERRUPT_GRACE_MS);
          })
        ]);
        interrupted = outcome?.interrupted === true;
      } catch {
        // An interrupt that fails leaves the reaper as the remaining recourse.
      }
      clearTimeout(grace);
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
