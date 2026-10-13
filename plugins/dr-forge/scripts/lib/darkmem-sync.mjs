// darkmem-sync's entry point, run by scripts/darkmem-sync: argument parsing,
// the stores, lock, state and exit codes. The commands live in darkmem-pull.mjs,
// darkmem-push.mjs and darkmem-import.mjs; scripts/darkmem-sync documents the
// usage and exit codes.
import fs from "node:fs";
import path from "node:path";
import { ConfigError, resolveStores, runKey } from "./darkmem-config.mjs";
import { HttpError, TransportError, createClient } from "./darkmem-client.mjs";
import {
  ARCHIVE_PREFIX, DOC_PREFIX, StateError, UsageError, acquireLock, isArchiveUri, loadState, localChanges, lockOwner, pathToUri,
  saveState, sha256, uriFamily, uriToLocal,
} from "./darkmem-mirror.mjs";
import { importRepository } from "./darkmem-import.mjs";
import { pull, pullDocuments } from "./darkmem-pull.mjs";
import { push } from "./darkmem-push.mjs";
import { leftoverLines, pendingFamilies, reconcile, stayLine } from "./darkmem-reconcile.mjs";

const USAGE = "usage: darkmem-sync status | pull | push [--workstream KEY] | import [--replace] | restore NAME | revision NAME | reconcile";

const familyLine = (name, family) => `${name}: configured ${family.configured}, applied ${family.applied}${family.applied === "darkmem" ? "" : ", not synced"}`;

async function status({ cfg, roots, state, report, out }) {
  out(`darkmem-sync: project ${cfg.project} at ${cfg.url}; mirror ${cfg.mirror}`);
  out(familyLine("documents", cfg.documents));
  out(familyLine("progress", cfg.progress));
  for (const line of localChanges(roots, state)) out(line);
  report.conflicts.push(...(state.conflicts ?? []));
}

const notCitable = (name, reason) => `refused: ${name} is not synced and unchanged: ${reason}`;

// NAME@r<id>: the darkmem revision a distillation cites. Only a document the
// mirror holds exactly as darkmem does has one to cite; main refuses it
// before this runs when documents are not applied darkmem.
async function revision({ cfg, roots, state, client, report, args, out }) {
  const [name] = args;
  const refuse = reason => {
    out(notCitable(name, reason));
    report.refused += 1;
  };
  const uri = pathToUri(roots, name);
  const file = uri && uriFamily(uri) === "documents" && !isArchiveUri(uri) ? uriToLocal(roots, uri) : null;
  if (!file) return refuse("it does not name a document");
  const stat = fs.statSync(file, { throwIfNoEntry: false });
  if (!stat) return refuse(`${file} does not exist`);
  if (!stat.isFile()) return refuse(`${file} is not a file`);
  const local = sha256(fs.readFileSync(file));
  if (state.documents[uri] === undefined) return refuse("it was never synced");
  if (state.documents[uri] !== local) return refuse("it changed since the last sync; push first");
  const item = (await client.manifest(cfg.project, uri)).find(entry => entry.uri === uri);
  if (!item) return refuse("darkmem does not hold it");
  if (item.content_hash !== local) return refuse("darkmem's copy differs; pull first");
  const [newest] = (await client.revisions(item.id, { limit: 1 })).items;
  if (!newest) return refuse("darkmem lists no revision of it");
  // darkmem can file a newer version between the two reads.
  if (newest.content_hash !== local) return refuse("darkmem's newest revision differs; pull first");
  out(`${name}@r${String(newest.id)}`);
}

// A document name as ledgers and plans write it, docs/forge/<rest> or the
// pre-2.0 docs/superpowers/<rest>, as its uri superpowers/<rest>; null for a
// path, a handoff note, an archived copy, or a name that climbs.
function documentUri(name) {
  const match = /^(?:\.\/)?docs\/(?:forge|superpowers)\/(.+)$/.exec(name);
  if (!match || match[1].split("/").some(segment => segment === "" || segment === "." || segment === "..")) return null;
  const uri = `${DOC_PREFIX}/${match[1]}`;
  return uriFamily(uri) === "documents" && !isArchiveUri(uri) ? uri : null;
}

// Moves the newest archived copy of a document back to its uri, under the
// archived copy's hash, then pulls documents (wiring spec §2). main refuses it
// before this runs when documents are not applied darkmem.
async function restore(context) {
  const { cfg, roots, client, report, args, out } = context;
  const [name] = args;
  const uri = documentUri(name);
  if (!uri) throw new UsageError(`${name} does not name a document`);
  const refuse = reason => {
    out(`refused: ${reason}`);
    report.refused += 1;
  };
  const rest = uri.slice(DOC_PREFIX.length + 1);
  const items = await client.manifest(cfg.project, DOC_PREFIX);
  if (items.some(item => item.uri === uri)) return refuse(`${uri} is occupied on darkmem; move or rename that document first`);
  // superpowers/archive/<stamp>/<rest>: a stamp sorts by time.
  const newest = items
    .filter(item => isArchiveUri(item.uri) && item.uri.slice(ARCHIVE_PREFIX.length + 1).replace(/^[^/]+\//, "") === rest)
    .sort((a, b) => (a.uri < b.uri ? -1 : a.uri > b.uri ? 1 : 0))
    .at(-1);
  if (!newest) return refuse(`no archived copy of ${uri} on darkmem`);
  try {
    await client.moveDocument(newest.id, { uri, expectedHash: newest.content_hash });
  } catch (error) {
    if (error instanceof HttpError && error.status === 409) return refuse(`darkmem refused to move ${newest.uri} back: ${error.detail}`);
    throw error;
  }
  out(`restored: ${uri} from ${newest.uri}`);
  report.counts.documents = 0;
  await pullDocuments({ ...context, roots: { ...roots, families: { documents: true, progress: false } } });
}

// options maps each accepted flag to whether it takes a value; positional is
// how many arguments follow the command. needsKey skips the command when the
// API key is unset, since the mirror stays usable offline; syncsFamilies makes
// it a no-op when no family is applied darkmem; recordsConflicts keeps this
// run's conflicts in the state file for `status`; summary prints the closing
// count line. refuseLocal marks a command that needs documents applied
// darkmem: main calls it instead of the command when the repository is
// unmapped or its documents are applied local, and returns its exit code.
const COMMANDS = {
  status: { options: {}, positional: 0, needsKey: false, syncsFamilies: false, recordsConflicts: false, summary: false, run: status },
  pull: { options: {}, positional: 0, needsKey: true, syncsFamilies: true, recordsConflicts: true, summary: true, run: pull },
  push: { options: { "--workstream": true }, positional: 0, needsKey: true, syncsFamilies: true, recordsConflicts: true, summary: true, run: push },
  import: { options: { "--replace": false }, positional: 0, needsKey: true, syncsFamilies: false, recordsConflicts: false, summary: true, run: importRepository },
  reconcile: { options: {}, positional: 0, needsKey: false, syncsFamilies: false, recordsConflicts: false, summary: false, run: reconcile },
  restore: {
    options: {}, positional: 1, needsKey: true, syncsFamilies: false, recordsConflicts: false, summary: true, run: restore,
    refuseLocal: ({ err }) => {
      err("darkmem-sync: restore needs documents applied darkmem");
      return 2;
    },
  },
  revision: {
    options: {}, positional: 1, needsKey: true, syncsFamilies: false, recordsConflicts: false, summary: false, run: revision,
    refuseLocal: ({ args, reason, out }) => {
      out(notCitable(args[0], reason));
      return 1;
    },
  },
};

function parse(argv) {
  const [name, ...rest] = argv;
  const command = Object.hasOwn(COMMANDS, name) ? COMMANDS[name] : null;
  if (!command) return null;
  const options = {};
  const args = [];
  for (let i = 0; i < rest.length; i += 1) {
    const flag = rest[i];
    if (Object.hasOwn(command.options, flag)) {
      if (command.options[flag]) {
        const value = rest[i + 1];
        if (value === undefined) return null;
        options[flag] = value;
        i += 1;
      } else {
        options[flag] = true;
      }
    } else if (!flag.startsWith("--") && args.length < command.positional) {
      args.push(flag);
    } else {
      return null;
    }
  }
  if (args.length !== command.positional) return null;
  return { name, command, options, args };
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
  let stores;
  try {
    stores = resolveStores({ cwd, env });
  } catch (error) {
    if (!(error instanceof ConfigError)) throw error;
    err(`darkmem-sync: ${error.message}`);
    return 2;
  }
  if (!stores.sync) {
    if (parsed.command.refuseLocal) return parsed.command.refuseLocal({ args: parsed.args, reason: `local mode — ${stores.reason}`, out, err });
    out(`darkmem-sync: local mode — ${stores.reason}`);
    return parsed.name === "import" ? 2 : 0;
  }
  const cfg = { ...stores.sync, repoRoot: stores.repoRoot, worktreeRoot: stores.worktreeRoot, documents: stores.documents, progress: stores.progress };
  const families = { documents: cfg.documents.applied === "darkmem", progress: cfg.progress.applied === "darkmem" };
  if (parsed.command.refuseLocal && !families.documents) {
    return parsed.command.refuseLocal({ args: parsed.args, reason: "documents are applied local", out, err });
  }
  if (parsed.command.syncsFamilies && !families.documents && !families.progress) {
    out(`darkmem-sync: nothing to ${parsed.name}: documents and progress are both applied local`);
    return 0;
  }
  // Nothing to move takes no lock and calls nothing; the leftover warning
  // still prints, since session start runs reconcile every time.
  if (parsed.name === "reconcile" && !pendingFamilies(cfg).length) {
    for (const line of leftoverLines(cfg)) out(line);
    return 0;
  }
  if (parsed.command.needsKey && !cfg.apiKey) {
    err(`darkmem-sync: ${parsed.name} skipped: ${cfg.keyEnv} is not set; working offline from the mirror`);
    return 3;
  }
  const release = acquireLock(cfg.mirror);
  if (!release && parsed.name === "reconcile") {
    for (const family of pendingFamilies(cfg)) out(stayLine(cfg, family, "another darkmem-sync holds the mirror lock"));
    return 1;
  }
  if (!release) {
    const owner = lockOwner(cfg.mirror);
    const holder = owner ? `pid ${owner.pid} on ${owner.host}` : "an unknown process";
    err(`darkmem-sync: another darkmem-sync (${holder}) holds ${path.join(cfg.mirror, ".sync.lock")}; if that process is gone, remove the directory`);
    return 1;
  }
  const report = { conflicts: [], failures: [], notes: [], counts: {}, partial: false, refused: 0 };
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
    const roots = { docsRoot: cfg.documents.root, workRoot: path.join(cfg.mirror, "work"), worktreeRoot: cfg.worktreeRoot, families };
    await parsed.command.run({ cfg, roots, state, persist, client, report, options: parsed.options, args: parsed.args, out, env });
  } catch (error) {
    if (error instanceof TransportError || error instanceof HttpError) {
      err(`darkmem-sync: ${parsed.name} failed: ${error.message}`);
      code = 3;
    } else if (error instanceof StateError || error instanceof UsageError) {
      err(`darkmem-sync: ${error.message}`);
      code = 2;
    } else {
      code = 4;
      throw error;
    }
  } finally {
    try {
      if (state) {
        // A completed run replaces the recorded conflicts; a run that stopped
        // part-way, or failed an item or phase darkmem answered with an error,
        // adds what it found, since it never re-checked the rest.
        if (parsed.command.recordsConflicts) {
          state.conflicts = code === 0 && !report.partial ? report.conflicts : [...new Set([...state.conflicts, ...report.conflicts])];
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
  if (parsed.command.summary) out(summary(parsed.name, report));
  return report.conflicts.length || report.failures.length || report.refused ? 1 : 0;
}

main(process.argv.slice(2)).then(
  code => { process.exitCode = code; },
  error => {
    process.stderr.write(`darkmem-sync: unexpected error: ${error?.stack ?? error}\n`);
    process.exitCode = 4;
  },
);
