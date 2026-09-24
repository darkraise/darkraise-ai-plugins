// darkmem-sync's entry point, run by scripts/darkmem-sync: argument parsing,
// mode, lock, state and exit codes. The commands live in darkmem-pull.mjs,
// darkmem-push.mjs and darkmem-import.mjs; scripts/darkmem-sync documents the
// usage and exit codes.
import path from "node:path";
import { ConfigError, resolveMode, runKey } from "./darkmem-config.mjs";
import { HttpError, TransportError, createClient } from "./darkmem-client.mjs";
import { StateError, UsageError, acquireLock, loadState, localChanges, lockOwner, saveState } from "./darkmem-mirror.mjs";
import { importRepository } from "./darkmem-import.mjs";
import { pull } from "./darkmem-pull.mjs";
import { push } from "./darkmem-push.mjs";

const USAGE = "usage: darkmem-sync status | pull | push [--workstream KEY] | import [--replace]";

async function status({ cfg, roots, state, report, out }) {
  out(`darkmem-sync: darkmem mode — project ${cfg.project} at ${cfg.url}; mirror ${cfg.mirror}`);
  for (const line of localChanges(roots, state)) out(line);
  report.conflicts.push(...(state.conflicts ?? []));
}

// options maps each accepted flag to whether it takes a value. needsDarkmem
// makes local mode a usage error; recordsConflicts keeps this run's conflicts
// in the state file for `status`.
const COMMANDS = {
  status: { options: {}, needsDarkmem: false, recordsConflicts: false, run: status },
  pull: { options: {}, needsDarkmem: false, recordsConflicts: true, run: pull },
  push: { options: { "--workstream": true }, needsDarkmem: false, recordsConflicts: true, run: push },
  import: { options: { "--replace": false }, needsDarkmem: true, recordsConflicts: false, run: importRepository },
};

function parse(argv) {
  const [name, ...rest] = argv;
  const command = Object.hasOwn(COMMANDS, name) ? COMMANDS[name] : null;
  if (!command) return null;
  const options = {};
  for (let i = 0; i < rest.length; i += 1) {
    const flag = rest[i];
    if (!Object.hasOwn(command.options, flag)) return null;
    if (command.options[flag]) {
      const value = rest[i + 1];
      if (value === undefined) return null;
      options[flag] = value;
      i += 1;
    } else {
      options[flag] = true;
    }
  }
  return { name, command, options };
}

function summary(name, report) {
  const counts = Object.entries(report.counts).map(([what, n]) => `${n} ${what}`).join(", ") || "nothing to do";
  return `darkmem-sync ${name}: ${counts}; ${report.conflicts.length} conflicts, ${report.failures.length} failures`;
}

async function main(argv, {
  cwd = process.cwd(),
  env = process.env,
  out = line => process.stdout.write(`${line}\n`),
  err = line => process.stderr.write(`${line}\n`),
} = {}) {
  const parsed = parse(argv);
  if (!parsed) {
    err(USAGE);
    return 2;
  }
  let cfg;
  try {
    cfg = resolveMode({ cwd, env });
  } catch (error) {
    if (!(error instanceof ConfigError)) throw error;
    err(`darkmem-sync: ${error.message}`);
    return 2;
  }
  if (cfg.mode === "local") {
    out(`darkmem-sync: local mode — ${cfg.reason}`);
    return parsed.command.needsDarkmem ? 2 : 0;
  }
  const release = acquireLock(cfg.mirror);
  if (!release) {
    const owner = lockOwner(cfg.mirror);
    const holder = owner ? `pid ${owner.pid} on ${owner.host}` : "an unknown process";
    err(`darkmem-sync: another darkmem-sync (${holder}) holds ${path.join(cfg.mirror, ".sync.lock")}; if that process is gone, remove the directory`);
    return 1;
  }
  const report = { conflicts: [], failures: [], notes: [], counts: {} };
  let state = null;
  let code = 0;
  try {
    state = loadState(cfg.statePath);
    const persist = () => saveState(cfg.statePath, state);
    const client = createClient({
      url: cfg.url,
      apiKey: cfg.apiKey,
      runKey: runKey({ cwd, env }),
      timeoutMs: Number(env.DARKMEM_SYNC_TIMEOUT_MS) || 10000,
    });
    const roots = { docsRoot: cfg.docsRoot, workRoot: cfg.workRoot };
    await parsed.command.run({ cfg, roots, state, persist, client, report, options: parsed.options, out });
  } catch (error) {
    if (error instanceof TransportError || error instanceof HttpError) {
      err(`darkmem-sync: ${parsed.name} failed: ${error.message}`);
      code = 3;
    } else if (error instanceof StateError || error instanceof UsageError) {
      err(`darkmem-sync: ${error.message}`);
      code = 2;
    } else {
      throw error;
    }
  } finally {
    try {
      if (state) {
        // A completed run replaces the recorded conflicts; a run that stopped
        // part-way adds what it found, since it never re-checked the rest.
        if (parsed.command.recordsConflicts) {
          state.conflicts = code === 0 ? report.conflicts : [...new Set([...state.conflicts, ...report.conflicts])];
        }
        saveState(cfg.statePath, state);
      }
    } finally {
      release();
    }
  }
  for (const line of report.conflicts) out(`conflict: ${line}`);
  for (const line of report.failures) out(`failed: ${line}`);
  for (const line of report.notes) out(`note: ${line}`);
  if (code !== 0) return code;
  if (parsed.name !== "status") out(summary(parsed.name, report));
  return report.conflicts.length || report.failures.length ? 1 : 0;
}

main(process.argv.slice(2)).then(
  code => { process.exitCode = code; },
  error => {
    process.stderr.write(`darkmem-sync: unexpected error: ${error?.stack ?? error}\n`);
    process.exitCode = 4;
  },
);
