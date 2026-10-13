# darkmem Store Options, Plan 2 (Moves and Triggers) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: the skill the **Execution:** line names — dr-superpowers:subagent-driven-development for `subagent`, dr-superpowers:executing-plans for `inline`. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move a mapped repository's documents and progress between the checkout and darkmem automatically when their configured store changes, sync at session start and at every stop, archive and restore deleted documents, treat the two docs prefixes as one name, and let the cockpit read through the roots.

**Architecture:** A new `darkmem-sync reconcile` command (`scripts/lib/darkmem-reconcile.mjs`) compares each family's configured and applied store and runs one of four moves under §4's refusals, recording success in `~/.dr-forge/stores.json`. Push archives deleted documents through darkmem's `PATCH /documents/{id}` and pull removes unchanged local copies; `restore` and `revision` complete the archive cycle. A sourced `scripts/lib/darkmem-hook.sh` runs reconcile and pull at session start and a silent push at Stop. `roots.sh` gains `forge_name_key`, which every name comparison in the shell scripts goes through. The cockpit reads its roots from `darkmem-config.mjs --mode DIR`.

**Tech Stack:** Node ES modules with `node:test` and the in-process stub server (darkmem-sync), bash + git (scripts and shell suites), TypeScript mod (cockpit, `claude plugin test`), Markdown skills.

**Spec:** docs/superpowers/specs/2026-10-13-darkmem-store-options-design.md

**Execution:** inline — `claude --model sonnet --effort high` — 10 of 28 tasks are heavy (Tasks 8, 9, 10, 11, 15, 16, 17, 19, 20, 22) and 13 carry a codex Executor line; all are delegated, and the session implements Tasks 2, 5, 12, 27 and 28 (total 4 or less)

**Plan review:** 2026-10-13 — dr-superpowers:judge-opus — executability 15 / coherence 17 / coverage 17 / assumptions 17 (round 2)

> **External executors:** codex

**Parallelism:** sequential — the spec's Execution strategy: the moves build on the sync commands, and the triggers and the cockpit build on the moves

## Global Constraints

- All paths below are relative to `plugins/dr-forge/` unless they start with `docs/` or name the repository-root scripts `scripts/test-all.mjs` and `scripts/validate-repository.mjs`.
- English only. Commit messages: `<type>(dr-forge): <subject>`, subject at most 50 characters, imperative, no period. No AI attribution of any kind; commit as `Darkraise <quangtc94@gmail.com>`.
- Inside `plugins/dr-forge/`, write skill references as `dr-forge:<name>`, never `dr-superpowers:` (`scripts/validate-repository.mjs` rejects the legacy names).
- Comments only where the why is non-obvious, matching the surrounding files.
- Bash executables use `set -uo pipefail`; libraries are sourced and define functions only. Scripts call `grep`, never `rg` (`rg` is a shell function on the development host, not a binary).
- Node code uses built-in modules only; no new dependency anywhere.
- Every new shell check sets `HOME` to a directory under the suite's own `mktemp -d` and never reads the real home directory. New `node:test` cases build their HOME with `makeHome` and their repository with `makeRepo` (`tests/darkmem-sync/helpers.mjs`), and talk to darkmem only through `startStub` (`tests/darkmem-sync/stub-server.mjs`). A test that runs a hook script deletes `CLAUDE_CONFIG_DIR` from the environment it passes.
- Bound every run, from the repository root: one shell suite `timeout 600 bash plugins/dr-forge/tests/<name>.test.sh`; one sync file `timeout 300 node --test plugins/dr-forge/tests/darkmem-sync/<file>.test.mjs`; the whole sync suite `timeout 900 bash plugins/dr-forge/tests/darkmem-sync.test.sh`; the mod suite `timeout 600 claude plugin test plugins/dr-forge`.
- darkmem uris do not change: documents stay under `superpowers/`, a plan's handoff note at `superpowers/handoff/<slug>.md`, archives under `superpowers/archive/<stamp>/<rest>`. No darkmem server change: the server half (`PATCH /api/v1/documents/{id}`, `GET /api/v1/documents/{id}/revisions`) is deployed.
- `<stamp>` is always UTC `YYYYMMDDTHHMMSSZ` (C3's `utcStamp`).
- Preserve every `DCC_*` variable and the pre-2.0 fallbacks (`~/.dr-superpowers/`, `docs/superpowers/`, `.superpowers/`, `DR_SUPERPOWERS_SESSION_ID`). Names are still written as `forge_name` prints them; nothing on disk or on darkmem is rewritten to the other prefix.
- With no `~/.dr-forge/config.json`, every existing suite passes unchanged and no command, hook or skill step changes what it prints.
- Workspaces stay local in both stores: briefs, reports, review packages, `amendments.md`, `auto-run.json`, `finish.json` and `budget-log.tsv` keep their current paths.
- Do not edit historical plans or specs, and do not touch the untracked `docs/superpowers/notes/2026-09-23-opus-5-5-effort-eval-design.md`.
- `skills/using-superpowers/SKILL.md` stays at or under 5,100 bytes (`tests/hook.test.sh`); it is 4,982 bytes before this plan.

## Contracts

**C1. Name keys** (`scripts/lib/roots.sh`, Task 1). Pure string functions; neither calls `forge_stores_init`.

- `forge_name_key NAME` prints one line: NAME with a leading `./` stripped, and with a first segment pair that is exactly `docs/superpowers` (the whole name) or begins `docs/superpowers/` rewritten to `docs/forge`. Every other name, `docs/superpowersx/a.md` and absolute paths included, is printed unchanged (after the `./` strip).
- `forge_name_spellings NAME` prints the key, then, when the key is `docs/forge` or begins `docs/forge/`, the same name under `docs/superpowers` on a second line. A search of `completed.md` runs `grep -qF` once per printed line and accepts either.

**C2. Client calls** (`scripts/lib/darkmem-client.mjs`).

- `moveDocument(documentId, { uri, expectedHash })` → `PATCH /api/v1/documents/{documentId}` with body `{ uri, expected_hash }` (`expected_hash` left out when `expectedHash` is falsy); resolves darkmem's `{ document_id }`. darkmem answers 409 for a stale `expected_hash` or a uri already taken, 404 for an unknown id, 422 for nothing to change or an unknown body key; each rejects as `HttpError` with that status. (Task 7)
- `revisions(documentId, { limit, before } = {})` → one page of `GET /api/v1/documents/{documentId}/revisions?limit=&before=`, resolved as darkmem's `{ document_id, items: [{ id, content_hash, actor, api_key_id, created_at }], next_before }`, newest first. The sync treats `id` as opaque and prints it with `String(id)`. (Task 7)
- The stub (`tests/darkmem-sync/stub-server.mjs`) serves both routes with those answers; every stored write of a document's content appends `{ id: <next integer>, content_hash, actor: "stub", api_key_id: null, created_at }` to that document's revision list.

**C3. Archive helpers** (`scripts/lib/darkmem-mirror.mjs`, Task 8).

- `ARCHIVE_PREFIX = "superpowers/archive"`; `isArchiveUri(uri)` is true for `superpowers/archive` and anything under `superpowers/archive/`.
- `utcStamp(date = new Date())` → `YYYYMMDDTHHMMSSZ` in UTC (for example `20261013T091502Z`).
- `archiveUri(uri, stamp)` → `superpowers/archive/<stamp>/<rest>` for `uri = superpowers/<rest>`.
- A file under `<docs root>/archive/` (`archive` as the first segment below the docs root) is reserved like `handoff/`: `listDocumentFiles` lists it with uri `null`, so push and import name it in a reserved warning and never sync it, and `status` prints it as `reserved:`. `status` prints `deleted: <uri>` for each uri in `state.documents` whose `uriFamily` is `documents` and whose mirror file is gone, while documents are applied darkmem.
- `RESERVED_DIRS = { handoff: "handoff notes", archive: "archived documents" }` names the reserved first segments below the docs root; reserved-file messages name the directory.
- Push archives (Task 9) and counts `archived`; pull (Task 10) skips archive uris, removes an unchanged local copy whose uri left the manifest, and counts `removed`. Each count is appended to its summary line only when non-zero. When the whole docs root is missing, push archives nothing (with a note) and pull brings every document back.

**C4. darkmem-sync CLI** (`scripts/lib/darkmem-sync.mjs`, `scripts/darkmem-sync`).

- Task 11 owns parsing, `refused`, the usage line, the `scripts/darkmem-sync` header comment (every command, including `reconcile`, and exit 1 for a refusal) and `revision`; Task 12 owns `restore`.
- Usage line, exactly: `usage: darkmem-sync status | pull | push [--workstream KEY] | import [--replace] | restore NAME | revision NAME | reconcile`.
- Each `COMMANDS` entry gains `positional` (the number of positional arguments it takes, default `0`) and `summary` (default `true`; `false` for `status`, `revision` and `reconcile`). `parse` returns `{ name, command, options, args }`; a wrong positional count is a usage error (exit 2). Every command's context gains `args` (the positional arguments, an array). An entry may carry `refuseLocal({ args, reason, out, err })`, which returns an exit code: `main` calls it instead of the command, before the API-key check, when the repository is unmapped (`reason` is `local mode — <stores.reason>`) or its documents are applied local (`reason` is `documents are applied local`).
- The report gains `refused: 0`. A command that refuses increments it; `main` returns 1 when `refused`, `conflicts` or `failures` is non-zero, after printing its lines.
- `restore NAME` (`positional: 1`, `needsKey: true`, `syncsFamilies: false`, `recordsConflicts: false`, documents applied darkmem required, else `refuseLocal` prints `darkmem-sync: restore needs documents applied darkmem` and exits 2). NAME must be `docs/forge/<rest>` or `docs/superpowers/<rest>` (an optional leading `./`; no empty, `.` or `..` segment; not a handoff note or an archived copy), else the `UsageError` `<NAME> does not name a document` (exit 2); it moves the newest archived copy (`superpowers/archive/<stamp>/<rest>`, newest `<stamp>`) back to `superpowers/<rest>` with `expectedHash` set to the archived copy's hash, then pulls documents. Prints `restored: superpowers/<rest> from superpowers/archive/<stamp>/<rest>`. Refused (report `refused` + 1, line `refused: <reason>`) when no archived copy exists or `superpowers/<rest>` is occupied.
- `revision NAME` (`positional: 1`, `needsKey: true`, `syncsFamilies: false`, `summary: false`). Prints exactly `NAME@r<id>` (NAME as given) with the newest revision id, exit 0, when documents are applied darkmem, the mirror file exists, `state.documents[uri]` equals its hash, and both the manifest's `content_hash` and the newest revision's `content_hash` equal it; when documents are not applied darkmem (unmapped included), `refuseLocal` prints the refused line with the `refuseLocal` reason and exits 1. Otherwise prints `refused: <NAME> is not synced and unchanged: <reason>` and exits 1.
- `reconcile` (`positional: 0`, `needsKey: false`, `syncsFamilies: false`, `summary: false`) runs C7. (Task 15)

**C5. `--mode [DIR]`** (`scripts/lib/darkmem-config.mjs`, Task 13). `node darkmem-config.mjs --mode [DIR]` resolves the stores for DIR (default the working directory) and prints `modeLines(stores)`: `documents\t<applied>\t<root>`, `progress\t<applied>\t<ledgerRoot>\t<latestFile>`, then, only when the repository is mapped, `project\t<project>`. Exit codes as before (2 ConfigError or usage, 3 not inside git). Usage line `usage: darkmem-config.mjs --mode [DIR]`.

**C6. Project helpers** (Task 14). `roots.sh` `forge_project [DIR]` prints the mapped project and returns 0, or prints nothing and returns 1 when the repository is unmapped, outside git, or node is missing. `forge-path project` prints the same and exits 1 when unmapped; its usage line gains `| project`.

**C7. Reconcile** (`scripts/lib/darkmem-reconcile.mjs`).

- Exports `reconcile(context)` (the command), `inProgressReason(context)` (C8's check: `null`, or `{ reason, details }`; a move calls it again after any pull it makes), `pendingFamilies(cfg)` (the families, in the order `documents`, `progress`, whose `configured` differs from `applied`) and `stayLine(cfg, family, reason)`, plus `refreshContext(context)` (re-reads the stores with `resolveStores({ cwd: context.cfg.worktreeRoot, env: context.env })` and rebuilds `context.cfg` and `context.roots` as `main` builds them; `reconcile` calls it after every successful move, so a later move must read `context.cfg` and `context.roots`, never a copy taken before), `mirrorRoots(cfg, family)`, `nameSpellings(name)` and `leftoverLines(cfg)`.
- `main` runs reconcile only when `pendingFamilies(cfg)` is non-empty (else it prints only the leftover warning, when it applies, and exits 0, without taking the lock or calling darkmem); when the lock is held it prints `stayLine` for each pending family with reason `another darkmem-sync holds the mirror lock`, and exits 1.
- Output lines, each family's first line starting `darkmem-sync reconcile: `:
  - success: `darkmem-sync reconcile: <family> moved to <store>`, then detail lines indented two spaces;
  - refusal: `darkmem-sync reconcile: <family> stay <applied> (configured <configured>): <reason>`, then detail lines indented two spaces (for example one per file a §7.2 check names);
  - leftover warning (documents applied darkmem and the working directory's checkout has a docs directory): `darkmem-sync reconcile: <absolute docs dir> is not read while documents are applied darkmem`.
- Each move is `async (context) => ({ moved: true, details: [...] } | { moved: false, reason, details: [...] })`, registered in a `MOVES` table under `"<family>:<target store>"`; a missing entry refuses with reason `no move from <applied> to <configured>`. Success calls `writeApplied(env, cfg.repoRoot, { [family]: target })`. Refusals common to every move, checked first: a plan in progress (C8), the API key unset (`<keyEnv> is not set`), darkmem unreachable (a `TransportError` from a manifest read, reason `darkmem is unreachable: <message>`), or darkmem refusing that read (an `HttpError`, reason `darkmem refused the manifest read: <message>`). A `TransportError` or `HttpError` thrown inside a move becomes a refusal with reason `darkmem failed during the move: <message>`. Once the common refusals pass and before the first move, `reconcile` records both families' currently applied stores with `writeApplied`, so a refused move's partial sync state can never tip the first-run rule. Each move calls `inProgressReason(context)` again after its own pull, before it deletes, copies or renames anything.
- Documents returning to the checkout are carried only when each mirror file's hash equals darkmem's manifest hash after the move's pull; a mirror file that differs from darkmem's, or that darkmem does not hold, refuses the move with reason `the mirror does not match darkmem; nothing was copied`.
- Mirror roots for a move: `{ docsRoot: <mirror>/superpowers, workRoot: <mirror>/work, worktreeRoot: cfg.repoRoot, families: { documents, progress } }` with only the moving family true.
- Backup directories: `<checkout>/<state dir>/moved-<stamp>/` for progress sources moved into darkmem; `<mirror>/work-moved-<stamp>/` and `<mirror>/superpowers-moved-<stamp>/` for mirror trees moved out.

**C8. In progress** (Task 15). A plan is in progress when `<primary state dir>/sdd/auto-run.json` holds `"active": true`, or a ledger in the progress family's source location (every worktree's `<state dir>/sdd/*/progress.md` from `git worktree list --porcelain` when progress is applied local; `<mirror>/work/sdd/*/progress.md` when darkmem) names a plan whose `completed.md` (beside the resolved plan) contains neither backticked spelling of its name (C1's two spellings, mirrored in JavaScript), or has no identity line. Reason: `a plan is in progress: <name or ledger path>` (the first one found), with the rest as detail lines.

**C9. Import reuse** (`scripts/lib/darkmem-import.mjs`, Task 18). `importLedger(context, roots, ledger)` is exported unchanged in behaviour; `ledger = { slug, text, mtime, id: null }`; on success it sets `ledger.id` and closes the workstream; a 422 pushes a failure line and leaves `ledger.id` null.

**C10. Hook library** (`scripts/lib/darkmem-hook.sh`, Task 21). Sourced; defines functions only; each returns 0 whatever happens.

- `darkmem_session_lines DIR SID [ROOM]` prints nothing when node is missing or the repository is unmapped (`forge_project DIR`, called in a subshell, fails); a malformed config prints its one-line ConfigError reason instead. Otherwise it runs, with `DR_FORGE_SESSION_ID=SID` exported and the working directory DIR, `darkmem-sync reconcile` (bounded at 200 seconds) then `darkmem-sync pull` (60 seconds), and drops lines starting `note:`, lines containing `nothing to pull`, and a pull summary that reports nothing (`darkmem-sync pull: 0 documents, 0 ledgers, 0 checkpoints; 0 conflicts, 0 failures`). It fits the rest: every unindented line is kept, in order, while ROOM characters hold it (ROOM defaults to no limit; 100 characters stay free for the closing line); indented detail lines fill what is left so the total is at most 20 lines; when anything is left out, one closing line `darkmem-sync: <n> more lines; run darkmem-sync reconcile or status to see them` counts it.
- `session-start.sh` runs it on every source, compaction included, passing as ROOM the characters left under the hook's 10,000-character cap after the entry point, the roadmap line and the settings line.
- `darkmem_push_quietly DIR SID` runs `darkmem-sync push` the same way (bounded at 100 seconds) with every output stream discarded.
- The bounds use `timeout` only when it is on PATH (macOS has none); there the hook's own timeout is the only bound.
- `hooks/hooks.json` gives the SessionStart hook `"timeout": 300` and the Stop hook `"timeout": 120`.

**C11. Stop-point push.** Skill prose runs `bash <plugin-root>/scripts/darkmem-sync push` at the stop points (Tasks 23 and 24): each ledger write at a task boundary or fix round, a saved spec or plan (a revised plan included: revising-plans step 10), and in the handoff skill after `scripts/next-step` has written `latest.md`; in local mode it prints one line and exits 0, so the prose needs no mode check.

**C12. Progress move module** (`scripts/lib/darkmem-progress-move.mjs`, created by Task 18; tests in `tests/darkmem-sync/reconcile-progress.test.mjs`).

- `gatherLocalProgress(cfg)` (Task 18) → `{ problems, files, sources }`; each item is `{ kind: "ledger"|"handoff"|"latest", slug?, uri?, file, stateDir, rel, buffer }` with `rel` `/`-separated: `sdd/<slug>/progress.md`, `sdd/<slug>/handoff.md` or `handoff/latest.md`. It reads the primary checkout first, then every linked worktree `git worktree list --porcelain` names; `latest.md` comes from the primary only. `files` holds every copy found, `sources` one item per `rel`; `problems` lists unusable plan directories, empty or non-UTF-8 text, and copies of one `rel` that differ between checkouts.
- `checkProgressTargets({ cfg, client }, sources)` (Task 18) → `{ problems, filed }`: `filed` is a `Map` slug → workstream id for ledgers darkmem holds byte for byte; `problems` names each different ledger or handoff note on darkmem and each differing mirror file under `<mirror>/work/<rel>`.
- Module-private `local(base, rel)` (Task 18) → `path.join(base, ...rel.split("/"))`.
- Module-private, from Task 19: `refuse(reason, details = [])` → `{ moved: false, reason, details }`; `darkmemRefusal(error, details = [])` turns a `TransportError` or `HttpError` into a refusal and rethrows anything else; `scratchReport()` → a report whose `counts` start `{ workstreams: 0, documents: 0, ledgers: 0, checkpoints: 0 }`; `checkoutRoots(cfg, stateDir)` → `{ docsRoot, workRoot: stateDir, worktreeRoot: <checkout> }` (`docsRoot` the checkout's own `forgeDir("docs", checkout)` while documents are applied local, `cfg.documents.root` while darkmem); `async newestCheckpoint(context, workstreams)` → the newest `resume(...).checkpoint` across `workstreams` by `isoMicros(created_at)`, or `null`.
- `progressToDarkmem(context)` (Task 19) and `progressToLocal(context)` (Task 20) are registered as `MOVES["progress:darkmem"]` and `MOVES["progress:local"]`.
- Test helpers: `LEDGER(name)` (identity line `docs/forge/plans/<name>.md`) and `LATEST` (a `## State` naming `docs/forge/plans/p1.md`) from Task 18; `setup(t, target)` (Task 19) → `{ stub, repo, worktree, home, env, mirror, docsRoot, workRoot, seed, state(), stores(), reconcile() }`, a mapped repository whose only pending family is progress, moving toward `target`, with p1, p2 and p4 committed in `docs/forge/plans/completed.md` before a linked worktree `side` is cut; `movedAside(dir)` (Task 19) → the `moved-<stamp>` directories under `<dir>/.forge`.

**C13. Cockpit roots** (Task 26; consumed by Task 27).

- `types/index.d.ts`: `export type CockpitRoots = { docs: { store: 'local' | 'darkmem'; root: string }; progress: { store: 'local' | 'darkmem'; ledgerRoot: string; latestFile: string }; project: string | null }`; `PluginState['dr-forge']` gains `rootsNote: string | null`.
- `hooks/cockpit/lib.ts`: `parseModeLines(text: string): CockpitRoots | null` reads C5's output; null unless there is a `documents` line and a `progress` line whose store is `local` or `darkmem`; `project` is null without a `project` line.
- `hooks/cockpit/register.tsx`: atom `rootsNote` (`atom({ plugin: 'dr-forge', key: 'rootsNote' } as const, null)`); `S.roots: { key: string; value: CockpitRoots | null }`; top-level `async function readRoots($: EngineInterface, primary: string): Promise<CockpitRoots | null>` runs `['node', `${$.plugin.root}/scripts/lib/darkmem-config.mjs`, '--mode', primary]` with `{ timeoutMs: 5000 }`, cached on `` `${primary}|${<HOME>/.dr-forge/stores.json mtimeMs ?? 'none'}` ``; it returns null to keep the checkout paths and sets `rootsNote` to the first non-empty stderr line on a non-zero exit, `darkmem-config.mjs --mode gave no answer within 5 seconds` on a rejection whose message lacks `ENOENT`, else null. `readRun` calls `readRoots($, root)` after `stateDirOf`.
- `tests/cockpit.test.ts`: `World` gains `modeOut?: { exitCode: number; stdout: string; stderr: string } | 'missing'` (default git porcelain with exit 0; `missing` rejects with `spawn node ENOENT`), `modeRuns?: string[]` (the DIR each `--mode` call names) and `primary?: string`; `describe('cockpit roots')` defines `MIRROR`, `MODE`, `LEDGER`, `PLAN` and `checkoutFiles()`.

## Assumptions (evidence)

- darkmem's server half is deployed: `PATCH /api/v1/documents/{id}` takes `{uri?, title?, pinned?, tags?, expected_hash?}` (extra keys 422), answers `{document_id}`, 409 on a stale `expected_hash` or a taken uri, 404 unknown id, 422 nothing to change; `GET /api/v1/documents/{id}/revisions?limit=&before=` answers `{document_id, items:[{id, content_hash, actor, api_key_id, created_at}], next_before}`, newest first; manifest items are `{id, uri, content_hash, updated_at}` — darkmem register row 84, deployed 2026-09-28, recorded in `docs/superpowers/notes/2026-10-13-darkmem-plan-2-notes.md`. The revision `id`'s JSON type is unverified; C2 treats it as opaque, so either type works.
- `stores.json` read and write already exist (`writeApplied`, `storesPath`, first-run rule in `resolveStores`) — `scripts/lib/darkmem-config.mjs:66-123`, read 2026-10-13.
- Pull renders only open workstreams, and import closes what it files (`scripts/lib/darkmem-pull.mjs:168-182`, `scripts/lib/darkmem-import.mjs:49-65`), so a progress move verifies each filed workstream with `remoteLedger`, never a mirror pull.
- `turn-end.sh`'s stdout is the Stop hook's decision JSON, so the Stop push must print nothing (`scripts/turn-end.sh`, handoff gotcha 2026-10-13).
- Codex runs no hooks (`.codex-plugin/plugin.json` `"hooks": {}`): its session-start reconcile and pull are prose in `skills/using-superpowers/references/codex-tools.md`.
- The cockpit test mock answers an unknown process command with git porcelain and exit 0 (`tests/cockpit.test.ts`), so a `--mode` answer without mode lines falls back to checkout paths silently.
- The Codex executor lane is open: `codex-gate` printed `usable=true reason=ok review=true lane=true` (probe, 2026-10-13) and `detect-executors.sh` reported `codex` usable; `docs/superpowers/distilled/constraints.md` ("The Codex executor lane is on") ticks it without asking. Every task with total 2 or more and risk 1 or less carries an `**Executor:**` line from ladder.md's `codex-assignment` block.
- `auto-run.json` lives at `<primary state dir>/sdd/auto-run.json` and marks a run with `"active": true` — `scripts/lib/auto-run.sh:28,150`.
- Archives cover the documents family only, only while documents are applied darkmem, and are skipped with a note when the mirror's docs root is missing, so a deleted mirror never archives everything (planning ruling 2026-10-13, notes file).
- The handoff push runs after `scripts/next-step` writes `latest.md`, not at handoff step 1 as the parent spec §4 says: a push at step 1 would never send `latest.md`, and Codex has no Stop hook to send it later (planning ruling 2026-10-13).
- `session-start.sh` sets `session_id` only when jq is present under `set -u` (`scripts/session-start.sh:14-21`), and output over 10,000 characters is replaced by a file reference (`:99-102`), so the darkmem lines use `${session_id:-}` and are trimmed to the room left.
- Saved specs already say to push instead of commit when documents are in darkmem (`skills/brainstorming/SKILL.md:367`, `skills/handoff/SKILL.md:85`, `reference/project-state.md:111`), so writing-plans and revising-plans need no edit.
- A progress move into darkmem killed part-way through a ledger longer than one append (100 entries) leaves a partial workstream, and every retry refuses until `import --replace` purges it; accepted, since a refusal never loses data.
- `darkmem-reconcile.mjs` and `darkmem-progress-move.mjs` import each other. The cycle is safe because the moves are hoisted `async function` declarations that `MOVES` reads at evaluation, and `inProgressReason` is read only at call time (ECMAScript module instantiation initialises function declarations before any module body runs).
- The only reader of `--mode` output before this plan is `roots.sh`, which ignores unknown line kinds (`scripts/lib/roots.sh:57-64`), so the added `project` line is safe.
- SessionStart runs reconcile and pull for every source, `compact` included: the spec makes no exception (plan review ruling 2026-10-13).
- A progress move into darkmem sends `latest.md` as a checkpoint on the workstream it names and closes that workstream again if it was closed, so other machines and later pulls see it; the parent notes' "not sent" ruling is reversed (plan review ruling 2026-10-13).
- Documents returning to the checkout land in `docs/forge` even when a legacy `docs/superpowers` directory exists; it is left untouched and named as not read (plan review ruling 2026-10-13, replacing the notes' refusal).
- Register row 19 (legacy-only global keys) stays deferred; this plan does not migrate config files.

## Task index

1. Name keys for either docs prefix
2. plan_ledger compares name keys
3. next-step and the status skills match either prefix
4. plan-revise and plan-lint compare name keys
5. register_for_spec compares name keys
6. roadmap compares name keys
7. Document move and revisions calls
8. Archive helpers, the reserved archive directory, and deleted lines in status
9. Push archives documents deleted from the mirror
10. Pull skips archives, removes vanished documents, keeps local deletions
11. Positional arguments and darkmem-sync revision
12. darkmem-sync restore
13. --mode takes a checkout and prints the project
14. forge_project and forge-path project
15. reconcile command, refusals and in-progress check
16. move documents from the repository into darkmem
17. move documents from darkmem back into the repository
18. Gather and check local progress for a move
19. Move progress from the checkouts into darkmem
20. Move progress from darkmem back into the checkout
21. darkmem hook library
22. Reconcile, pull and push from the hooks
23. Push and promote at the stop points
24. Draft line, handoff push and Codex session start
25. Distil documents kept in darkmem
26. Cockpit reads its roots from --mode
27. Cockpit run card reads through the roots
28. Document the moves and release 2.3.0

---

### Task 1: Name keys for either docs prefix

**Files:**
- Modify: `scripts/lib/roots.sh:111` (insert before the `# forge_resolve NAME [DIR]` comment)
- Test: `tests/roots.test.sh:90` (insert before `# --- a --mode run that prints nothing stops the script ---`)

**Interfaces:**
- Consumes: nothing
- Produces: C1 `forge_name_key NAME`, `forge_name_spellings NAME`

**Items:** 18

**Implementer:** dr-superpowers:impl-sonnet-medium
**Executor:** codex gpt-6.1-sol / medium
**Evaluation:** files 1 - spec 0 - coupling 2 - risk 0 = 3

- [ ] **Step 1: Write the failing test**

In `tests/roots.test.sh`, insert above the line `# --- a --mode run that prints nothing stops the script ---`:

```bash
# --- one name under either docs prefix (spec §7.1) ---
check "name key: the pre-2.0 prefix" "$(forge_name_key docs/superpowers/plans/p.md)" "docs/forge/plans/p.md"
check "name key: the dr-forge prefix" "$(forge_name_key docs/forge/plans/p.md)" "docs/forge/plans/p.md"
check "name key: a bare docs/superpowers" "$(forge_name_key docs/superpowers)" "docs/forge"
check "name key: a leading ./" "$(forge_name_key ./docs/superpowers/specs/s.md)" "docs/forge/specs/s.md"
check "name key: docs/superpowersx is another name" "$(forge_name_key docs/superpowersx/a.md)" "docs/superpowersx/a.md"
check "name key: a name outside the docs directory" "$(forge_name_key .forge/sdd/p/progress.md)" ".forge/sdd/p/progress.md"
check "name key: an absolute path stays" "$(forge_name_key /x/docs/superpowers/a.md)" "/x/docs/superpowers/a.md"
check "name spellings: a document name" \
  "$(forge_name_spellings docs/superpowers/plans/p.md | tr '\n' '|')" "docs/forge/plans/p.md|docs/superpowers/plans/p.md|"
check "name spellings: the docs directory itself" \
  "$(forge_name_spellings ./docs/forge | tr '\n' '|')" "docs/forge|docs/superpowers|"
check "name spellings: any other name" "$(forge_name_spellings .forge/x.md | tr '\n' '|')" ".forge/x.md|"

```

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 600 bash plugins/dr-forge/tests/roots.test.sh`
Expected: FAIL lines for every `name key:` and `name spellings:` check (`forge_name_key: command not found` on stderr), last line `… passed, 10 failed`, exit 1.

- [ ] **Step 3: Write the implementation**

In `scripts/lib/roots.sh`, insert above the comment `# forge_resolve NAME [DIR] — a document name (docs/forge/… or the pre-2.0`:

```bash
# forge_name_key NAME — the one name both docs prefixes share (store options
# spec §7.1): docs/superpowers/<rest> is docs/forge/<rest>. A checkout's prefix
# differs between branches and machines, and a move to darkmem changes it, so
# every comparison of two document names compares their keys.
forge_name_key() {
  local name=${1#./}
  case $name in
    docs/superpowers) printf 'docs/forge\n' ;;
    docs/superpowers/*) printf 'docs/forge/%s\n' "${name#docs/superpowers/}" ;;
    *) printf '%s\n' "$name" ;;
  esac
}

# forge_name_spellings NAME — the key, then for a document name the same name
# under docs/superpowers. completed.md and register cells keep the spelling
# they were written with, so a search runs once per line and accepts either.
forge_name_spellings() {
  local key
  key=$(forge_name_key "$1")
  printf '%s\n' "$key"
  case $key in
    docs/forge) printf 'docs/superpowers\n' ;;
    docs/forge/*) printf 'docs/superpowers/%s\n' "${key#docs/forge/}" ;;
  esac
}

```

- [ ] **Step 4: Run test to verify it passes**

Run: `timeout 600 bash plugins/dr-forge/tests/roots.test.sh`
Expected: every line `ok`, last line `… passed, 0 failed`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-forge/scripts/lib/roots.sh plugins/dr-forge/tests/roots.test.sh
git commit -m "feat(dr-forge): add docs prefix name keys"
```

### Task 2: plan_ledger compares name keys

**Files:**
- Modify: `scripts/lib/plan.sh:326-343` (`plan_ledger`)
- Test: `tests/plan-lib.test.sh:375` and `:394` (insert after the two checks named below)

**Interfaces:**
- Consumes: C1 `forge_name_key`
- Produces: nothing new; `plan_ledger PLAN` now finds a ledger whose identity line names PLAN under the other docs prefix

**Items:** 18

**Implementer:** dr-superpowers:impl-sonnet-medium
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 2 = 4

- [ ] **Step 1: Write the failing test**

In `tests/plan-lib.test.sh`, after the check `"plan_ledger: an absolute mirror path names it too"` (its second line ends `"$M/work/sdd/mp/progress.md"`, line 375), insert:

```bash
printf '# SDD ledger — plan: docs/superpowers/plans/mp.md\n' > "$M/work/sdd/mp/progress.md"
check "plan_ledger: the pre-2.0 prefix names a mirror plan" \
  "$(cd "$SR" && HOME=$SH plan_ledger "$M/superpowers/plans/mp.md")" "$M/work/sdd/mp/progress.md"
```

After the check `"plan_ledger: a checkout plan finds its mirror ledger"` (two lines, ending line 394), insert:

```bash
printf '# SDD ledger — plan: docs/superpowers/plans/lp.md\n' > "$M/work/sdd/lp/progress.md"
check "plan_ledger: the pre-2.0 prefix names a checkout plan" \
  "$(cd "$SR" && HOME=$SH plan_ledger "$STOP/docs/forge/plans/lp.md")" "$M/work/sdd/lp/progress.md"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 600 bash plugins/dr-forge/tests/plan-lib.test.sh`
Expected: `FAIL - plan_ledger: the pre-2.0 prefix names a mirror plan` and `FAIL - plan_ledger: the pre-2.0 prefix names a checkout plan` (got `[]`), last line `… passed, 2 failed`.

- [ ] **Step 3: Write the implementation**

In `scripts/lib/plan.sh`, replace the whole `plan_ledger` block (comment and function, lines 326-343) with:

```bash
# plan_ledger PLAN — the plan's ledger file when it exists and its identity line
# names PLAN; nothing otherwise. A stale ledger under the same slug is ignored.
# Plan and identity are compared as name keys, so a ledger in darkmem can name a
# plan in the checkout and the reverse, under either docs prefix.
plan_ledger() {
  local ctx want file named
  ctx=$(_plan_ctx "$1")
  want=$(forge_name_key "$(forge_name "$1" "$ctx")")
  file="$(forge_ledger_dir "$(basename "$1" .md)" "$ctx")/progress.md"
  [ -f "$file" ] || return 0
  named=$(ledger_plan "$file")
  [ -n "$named" ] || return 0
  if command -v cygpath >/dev/null 2>&1; then
    named=$(cygpath -m "$named" 2>/dev/null || printf '%s' "$named")
  fi
  [ "$(forge_name_key "$(forge_name "$named" "$ctx")")" != "$want" ] || printf '%s\n' "$file"
  return 0
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `timeout 600 bash plugins/dr-forge/tests/plan-lib.test.sh`
Expected: last line `… passed, 0 failed`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-forge/scripts/lib/plan.sh plugins/dr-forge/tests/plan-lib.test.sh
git commit -m "fix(dr-forge): key plan_ledger names"
```

### Task 3: next-step and the status skills match either prefix

**Files:**
- Modify: `scripts/next-step:87-94` (`plan_finished`), `:192` (ledger check), `:277` (register-row loop)
- Modify: `skills/project-status/SKILL.md:40`, `skills/finishing-a-development-branch/SKILL.md:274`
- Test: `tests/next-step.test.sh:644` and `:649`, `tests/project-status.test.sh:107` and `:149`

**Interfaces:**
- Consumes: C1 `forge_name_key`, `forge_name_spellings`
- Produces: nothing new

**Items:** 18

**Implementer:** dr-superpowers:impl-sonnet-medium
**Executor:** codex gpt-6.1-sol / high
**Evaluation:** files 2 - spec 0 - coupling 1 - risk 1 = 4

- [ ] **Step 1: Write the failing tests**

In `tests/next-step.test.sh`, after line 644 (`has "routing: names rows left on finished plans" "$OUT" "Still assigned to a finished plan: #1, #6"`), insert:

```bash
# Either docs prefix names the same plan (spec §7.1): a completed.md entry and
# an Assigned cell spelled docs/forge/ match the docs/superpowers/ plan.
printf '# Completed plans\n\n- 2026-01-01 `docs/forge/plans/inc1.md` — merged into `main` at abc1234\n' \
  > "$GREPO/docs/superpowers/plans/completed.md"
bash "$HERE/../scripts/register" set "$GREG" 1 doing --assigned docs/forge/plans/inc2.md >/dev/null
OUT=$(cd "$GREPO" && bash "$SCRIPT" --complete docs/superpowers/plans/inc2.md 2>&1)
has "routing: either prefix names a finished plan" "$OUT" "Still assigned to a finished plan: #1, #6"
printf '# Completed plans\n\n- 2026-01-01 `docs/superpowers/plans/inc1.md` — merged into `main` at abc1234\n' \
  > "$GREPO/docs/superpowers/plans/completed.md"
bash "$HERE/../scripts/register" set "$GREG" 1 doing --assigned docs/superpowers/plans/inc2.md >/dev/null
```

After the line `has "routing: an assigned plan with a ledger resumes" …` (line 649 before the insert above; it stays directly before `rm -rf "$GREPO/.forge/sdd/inc3"`), insert:

```bash
printf '# SDD ledger — plan: docs/forge/plans/inc3.md\nTask 1: complete (x)\n' > "$GREPO/.forge/sdd/inc3/progress.md"
OUT=$(cd "$GREPO" && bash "$SCRIPT" docs/superpowers/plans/inc3.md 2>&1)
has "ledger check: an identity line under the other prefix is this plan's" "$OUT" "all 1 tasks complete."
```

In `tests/project-status.test.sh`, after the two-line `present "status: completed.md is no longer the only completion signal" …` (ends line 107), insert:

```bash
present "status: either docs prefix names one document" "$SKILL" "Either prefix names the same document"
```

After `present "finishing: discovered work becomes a row" "$FIN" "scripts/register add"` (line 149), insert:

```bash
present "finishing: either docs prefix names one document" "$FIN" "Either prefix names the same document"
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `timeout 600 bash plugins/dr-forge/tests/next-step.test.sh`
Expected: `FAIL - routing: either prefix names a finished plan` and `FAIL - ledger check: an identity line under the other prefix is this plan's` (the output says `belongs to another plan and is ignored`), exit 1.

Run: `timeout 600 bash plugins/dr-forge/tests/project-status.test.sh`
Expected: the two `either docs prefix names one document` checks FAIL, exit 1.

- [ ] **Step 3: Write the implementation**

In `scripts/next-step`, replace lines 87-94 (the `plan_finished` comment and function) with:

```bash
# plan_finished ROOT NAME — true when the completed.md beside the plan NAME
# records it. Matched on the backticked name, as plan-revise does, so one
# plan's name that is a substring of another's cannot claim its outcome; an
# entry under either docs prefix counts.
plan_finished() {
  local f s
  f="$(dirname "$(forge_resolve "$2" "$1")")/completed.md"
  [ -f "$f" ] || return 1
  while IFS= read -r s; do
    grep -qF "\`$s\`" "$f" && return 0
  done < <(forge_name_spellings "$2")
  return 1
}
```

Replace line 192:

```bash
    if [ -n "$ledger_plan_path" ] && [ "$(forge_name "$ledger_plan_path")" = "$rel" ]; then
```

with:

```bash
    if [ -n "$ledger_plan_path" ] && [ "$(forge_name_key "$(forge_name "$ledger_plan_path")")" = "$(forge_name_key "$rel")" ]; then
```

Replace line 277:

```bash
        elif [ "$a" = "$rel" ] || plan_finished "$root" "$a"; then
```

with:

```bash
        elif [ "$(forge_name_key "$a")" = "$(forge_name_key "$rel")" ] || plan_finished "$root" "$a"; then
```

In `skills/project-status/SKILL.md`, after line 40 (`     completion signal either — the work may be unmerged.`), insert:

```markdown
     Either prefix names the same document: `docs/superpowers/<rest>` in a
     ledger, a `completed.md` entry or a register cell matches `docs/forge/<rest>`.
```

In `skills/finishing-a-development-branch/SKILL.md`, after the closing fence of the two line forms (line 274, the ```` ``` ```` below `… — via PR`), insert a blank line and:

```markdown
Either prefix names the same document: an entry spelled `docs/superpowers/<rest>`
already records the plan `docs/forge/<rest>`, so never add a second line for it.
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `timeout 600 bash plugins/dr-forge/tests/next-step.test.sh`
Expected: last line `… passed, 0 failed`, exit 0.

Run: `timeout 600 bash plugins/dr-forge/tests/project-status.test.sh`
Expected: exit 0, no FAIL lines.

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-forge/scripts/next-step plugins/dr-forge/tests/next-step.test.sh \
  plugins/dr-forge/skills/project-status/SKILL.md plugins/dr-forge/skills/finishing-a-development-branch/SKILL.md \
  plugins/dr-forge/tests/project-status.test.sh
git commit -m "fix(dr-forge): key next-step name matches"
```

### Task 4: plan-revise and plan-lint compare name keys

**Files:**
- Modify: `scripts/plan-revise:140-189` (`ledger_for`, `completed_form`)
- Modify: `scripts/plan-lint:117-153` (register-row checks)
- Test: `tests/plan-revise.test.sh:346`, `tests/plan-lint.test.sh:613`

**Interfaces:**
- Consumes: C1 `forge_name_key`, `forge_name_spellings`
- Produces: nothing new

**Items:** 18

**Implementer:** dr-superpowers:impl-sonnet-medium
**Executor:** codex gpt-6.1-sol / high
**Evaluation:** files 2 - spec 0 - coupling 1 - risk 1 = 4

- [ ] **Step 1: Write the failing tests**

In `tests/plan-revise.test.sh`, after line 346 (`check "darkmem survey: the evidence names the mirror" …`), insert:

```bash
printf '# SDD ledger — plan: docs/superpowers/plans/mp.md\n' > "$M/work/sdd/mp/progress.md"
row=$(cd "$SR" && HOME=$SH bash "$SCRIPT" --survey "$M/superpowers/plans" | grep '^plan  mp\.md')
check "darkmem survey: a ledger under the other prefix is live" "$(field live "$row")" "yes"
rm -f "$M/work/sdd/mp/progress.md"
printf -- '- 2026-10-13 `docs/superpowers/plans/mp.md` — merged into `main` at abc1234\n' > "$M/superpowers/plans/completed.md"
row=$(cd "$SR" && HOME=$SH bash "$SCRIPT" --survey "$M/superpowers/plans" | grep '^plan  mp\.md')
check "darkmem survey: a completed entry under the other prefix" "$(field live "$row")" "no"
```

In `tests/plan-lint.test.sh`, insert above line 614 (`# A plan with no covering register lints exactly as it did before.`):

```bash
# Either docs prefix names this plan: an Assigned cell spelled docs/forge/ is
# its row (spec §7.1).
cat > "$LREPO/docs/superpowers/registers/r.md" <<'REG'
# R — item register

**Source:** review 2026-09-20
**Covers:** docs/superpowers/specs/s-design.md

| # | Item | Assigned | Acceptance | State | Note |
|---|---|---|---|---|---|
| 1 | Covered | docs/forge/plans/p.md | - | planned | - |
| 2 | Someone else's | C2 | - | planned | - |
REG
write_plan "next: Two" ""
OUT=$(cd "$LREPO" && bash "$LINT" docs/superpowers/plans/p.md --no-probe 2>&1)
has "plan-lint: an Assigned cell under the other prefix is this plan's" "$OUT" \
  "ERROR header: register row #1 is assigned to this plan but no task cites it"
write_plan "last" "**Items:** 1"
OUT=$(cd "$LREPO" && bash "$LINT" docs/superpowers/plans/p.md --no-probe 2>&1)
has "plan-lint: 'last' leaves out this plan's row under the other prefix" "$OUT" \
  "ERROR header: Program line says 'last' while register rows are open: #2"

```

- [ ] **Step 2: Run tests to verify they fail**

Run: `timeout 600 bash plugins/dr-forge/tests/plan-revise.test.sh`
Expected: `FAIL - darkmem survey: a ledger under the other prefix is live` (got `unknown`) and `FAIL - darkmem survey: a completed entry under the other prefix` (got `unknown`), exit 1.

Run: `timeout 600 bash plugins/dr-forge/tests/plan-lint.test.sh`
Expected: both new `plan-lint:` checks FAIL (the second sees `open: #1, #2`), exit 1.

- [ ] **Step 3: Write the implementation**

In `scripts/plan-revise`, in `ledger_for`, replace:

```bash
  want=$(forge_name "$1" "$ctx")
```

with:

```bash
  want=$(forge_name_key "$(forge_name "$1" "$ctx")")
```

and replace line 166:

```bash
    [ "$named" = "$want" ] || continue
```

with:

```bash
    [ "$(forge_name_key "$named")" = "$want" ] || continue
```

Change the last sentence of the `ledger_for` comment (lines 140-146) from `Identities compare as names;` to `Identities compare as name keys, so either docs prefix matches;`.

Replace the `completed_form` comment and function (lines 172-189) with:

```bash
# completed_form PLAN — "merged", "pr" or nothing, from the completed.md beside
# the plan. The entry is matched on the plan's name under either docs prefix,
# not a basename substring: "docs/scored.md" is a substring of
# "docs/unscored.md" and would otherwise claim another plan's outcome. Merged
# outranks via PR whatever their order, because finishing-a-development-branch
# writes the via-PR line before the push and the merged line after the merge.
completed_form() {
  local f rel hits s
  f="$(cd "$(dirname "$1")" && pwd)/completed.md"
  [ -f "$f" ] || return 0
  rel=$(forge_name "$1" "$(_plan_ctx "$1")")
  hits=$(while IFS= read -r s; do grep -F "\`$s\`" "$f" 2>/dev/null; done < <(forge_name_spellings "$rel"))
  [ -n "$hits" ] || return 0
  if grep -qF 'merged into' <<<"$hits"; then printf 'merged\n'
  elif grep -qF 'via PR' <<<"$hits"; then printf 'pr\n'
  fi
}
```

In `scripts/plan-lint`, after line 117 (`  plan_rel=$(forge_name "$plan" "$root")`), add:

```bash
  plan_key=$(forge_name_key "$plan_rel")
```

Replace line 140:

```bash
      [ "$rassigned" = "$plan_rel" ] || continue
```

with:

```bash
      [ "$(forge_name_key "$rassigned")" = "$plan_key" ] || continue
```

Replace line 151:

```bash
      others=$(awk -F'\t' -v p="$plan_rel" '$3 != p { printf "%s#%s", (c++ ? ", " : ""), $1 }' "$TMP/reg-open")
```

with:

```bash
      others=""
      while IFS=$'\t' read -r rid _ rassigned _; do
        [ "$(forge_name_key "$rassigned")" = "$plan_key" ] || others="${others:+$others, }#$rid"
      done < "$TMP/reg-open"
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `timeout 600 bash plugins/dr-forge/tests/plan-revise.test.sh`
Expected: last line `… passed, 0 failed`, exit 0.

Run: `timeout 600 bash plugins/dr-forge/tests/plan-lint.test.sh`
Expected: exit 0, no FAIL lines.

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-forge/scripts/plan-revise plugins/dr-forge/scripts/plan-lint \
  plugins/dr-forge/tests/plan-revise.test.sh plugins/dr-forge/tests/plan-lint.test.sh
git commit -m "fix(dr-forge): key plan-revise and plan-lint names"
```

### Task 5: register_for_spec compares name keys

**Files:**
- Modify: `scripts/lib/register.sh:101-124` (`register_for_spec`)
- Test: `tests/register.test.sh:84`

**Interfaces:**
- Consumes: C1 `forge_name_key`
- Produces: nothing new; `register_for_spec ROOT SPEC...` (used by next-step, plan-lint, register, roadmap) matches a `**Covers:**` entry under either docs prefix

**Items:** 18

**Implementer:** dr-superpowers:impl-sonnet-medium
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 2 = 4

- [ ] **Step 1: Write the failing test**

In `tests/register.test.sh`, after line 84 (`check "register_for_spec: no spec argument prints nothing" "$(register_for_spec "$ROOT")" ""`), insert:

```bash
check "register_for_spec: the other docs prefix matches" \
  "$(register_for_spec "$ROOT" docs/forge/specs/a-design.md | xargs -n1 basename | tr '\n' ' ')" "one.md "
check "register_for_spec: a leading ./ and the other prefix match" \
  "$(register_for_spec "$ROOT" ./docs/forge/specs/b-design.md | xargs -n1 basename | tr '\n' ' ')" "one.md "
check "register_for_spec: docs/superpowersx is another name" \
  "$(register_for_spec "$ROOT" docs/superpowersx/specs/a-design.md)" ""
```

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 600 bash plugins/dr-forge/tests/register.test.sh`
Expected: `FAIL - register_for_spec: the other docs prefix matches` and `FAIL - register_for_spec: a leading ./ and the other prefix match` (got `[]`), last line `… passed, 2 failed`.

- [ ] **Step 3: Write the implementation**

In `scripts/lib/register.sh`, replace lines 101-124 (comment and `register_for_spec`) with:

```bash
# register_for_spec ROOT SPEC... — the registers covering any of the given
# specs. Resolution runs this way round so that a plan cannot carry a stale
# pointer to a register. Covers entries and specs compare as name keys, so
# either docs prefix matches.
register_for_spec() {
  local root="$1" f cov want
  shift
  [ $# -gt 0 ] || return 0
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    while IFS= read -r cov; do
      [ -n "$cov" ] || continue
      cov=$(forge_name_key "$cov")
      for want in "$@"; do
        if [ "$cov" = "$(forge_name_key "$want")" ]; then
          printf '%s\n' "$f"
          break 2
        fi
      done
    done < <(register_covers "$f")
  done < <(register_files "$root")
  return 0
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `timeout 600 bash plugins/dr-forge/tests/register.test.sh`
Expected: last line `… passed, 0 failed`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-forge/scripts/lib/register.sh plugins/dr-forge/tests/register.test.sh
git commit -m "fix(dr-forge): key register Covers matches"
```

### Task 6: roadmap compares name keys

**Files:**
- Modify: `scripts/lib/roadmap.sh:85` (`roadmap_unresolved`), `scripts/roadmap:292` (`cmd_settle`)
- Test: `tests/roadmap.test.sh:123`, `:131`, `:216`

**Interfaces:**
- Consumes: C1 `forge_name_key`; `register_for_spec` matching either prefix (Task 5)
- Produces: nothing new

**Items:** 18

**Implementer:** dr-superpowers:impl-sonnet-medium
**Executor:** codex gpt-6.1-sol / medium
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 1 = 3

- [ ] **Step 1: Write the failing tests**

In `tests/roadmap.test.sh`, after line 123 (`check "settle: the epic is untouched" …`), insert:

```bash
run bash "$RM" settle --root "$ROOT" --spec docs/forge/specs/2026-10-08-billing-design.md
check "settle: the other docs prefix still refuses while open" "$(grep -c '^not settled' <<<"$OUT")" "1"
```

After line 131 (`check "settle: idempotent" …`, line 133 once the two lines above are in), insert:

```bash
bash "$REG" set "$D/registers/m1.md" 1 doing >/dev/null
run bash "$RM" settle --root "$ROOT" --spec docs/forge/specs/2026-10-08-billing-design.md
check "settle: an epic matches its spec under the other docs prefix" \
  "$(register_rows "$D/registers/m1.md" | awk -F'\t' '$1 == 1 { print $5 }')" "verify"
```

At the end of the darkmem section, after the check `"roadmap_unresolved: rows named by register name"` (its second line ends `"$(printf 'docs/forge/registers/m1.md\t2')"`, line 216) and before the final `printf '\n%d passed…`, insert:

```bash
mkdir -p "$M/superpowers/specs"
printf '# X\n' > "$M/superpowers/specs/x.md"
register "$M/superpowers/registers/m9.md" "docs/forge/specs/x.md" \
  '| 1 | Epic | docs/forge/specs/x.md | - | open | - |'
check "roadmap_unresolved: the milestone register under the other prefix is not listed twice" \
  "$(HOME=$SH roadmap_unresolved "$SR" docs/superpowers/registers/m9.md | cut -f1,2 | tr '\n' '|')" \
  "$(printf 'docs/superpowers/registers/m9.md\t1|docs/forge/registers/m1.md\t2|')"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 600 bash plugins/dr-forge/tests/roadmap.test.sh`
Expected: `FAIL - settle: an epic matches its spec under the other docs prefix` (got `doing`) and `FAIL - roadmap_unresolved: the milestone register under the other prefix is not listed twice` (m9's row appears again as `docs/forge/registers/m9.md`), exit 1. The refusal check passes already through `register_for_spec`.

- [ ] **Step 3: Write the implementation**

In `scripts/lib/roadmap.sh`, replace line 85:

```bash
      [ "$rel" != "$reg" ] || continue
```

with:

```bash
      [ "$(forge_name_key "$rel")" != "$(forge_name_key "$reg")" ] || continue
```

In `scripts/roadmap` (`cmd_settle`), replace line 292:

```bash
      [ "$a" = "$spec" ] || continue
```

with:

```bash
      [ "$(forge_name_key "$a")" = "$(forge_name_key "$spec")" ] || continue
```

- [ ] **Step 4: Run test to verify it passes**

Run: `timeout 600 bash plugins/dr-forge/tests/roadmap.test.sh`
Expected: last line `… passed, 0 failed`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-forge/scripts/lib/roadmap.sh plugins/dr-forge/scripts/roadmap plugins/dr-forge/tests/roadmap.test.sh
git commit -m "fix(dr-forge): key roadmap register matches"
```

### Task 7: Document move and revisions calls

**Files:**
- Modify: `scripts/lib/darkmem-client.mjs:1-4` (header comment), `scripts/lib/darkmem-client.mjs:86-90` (after `putDocument`)
- Modify: `tests/darkmem-sync/stub-server.mjs:1-10` (header comment), `:28` (db), `:79` (content write), `:85` (new routes after the POST documents block)
- Test: `tests/darkmem-sync/client.test.mjs` (two new tests before the `failItem` test)

**Interfaces:**
- Consumes: none.
- Produces: C2 — `moveDocument(documentId, { uri, expectedHash })`, `revisions(documentId, { limit, before })`, and the stub's PATCH and revisions routes with per-document revision lists.

**Implementer:** dr-superpowers:impl-sonnet-medium
**Executor:** codex gpt-6.1-sol / medium
**Evaluation:** files 1 - spec 0 - coupling 2 - risk 0 = 3

- [ ] **Step 1: Write the failing tests**

Add to `tests/darkmem-sync/client.test.mjs`, before the test named `failItem records any darkmem answer but a 401 …`:

```js
test("a document moves to a free uri under its hash; a stale hash or a taken uri is a 409, an unknown id a 404", () => withStub({}, async (stub, client) => {
  const a = await client.putDocument({ project: "p", uri: "superpowers/a.md", content: "a" });
  await client.putDocument({ project: "p", uri: "superpowers/b.md", content: "b" });
  const status = promise => promise.then(() => 200, error => (error instanceof HttpError ? error.status : -1));
  assert.equal(await status(client.moveDocument(a.document_id, { uri: "superpowers/x.md", expectedHash: "0".repeat(64) })), 409);
  assert.equal(await status(client.moveDocument(a.document_id, { uri: "superpowers/b.md", expectedHash: a.content_hash })), 409);
  assert.equal(await status(client.moveDocument("no-such-id", { uri: "superpowers/x.md" })), 404);
  const archived = "superpowers/archive/20261013T091502Z/a.md";
  assert.deepEqual(await client.moveDocument(a.document_id, { uri: archived, expectedHash: a.content_hash }), { document_id: a.document_id });
  const [unknown, moved] = stub.db.requests.slice(-2);
  assert.equal("expected_hash" in unknown.body, false);
  assert.equal(moved.method, "PATCH");
  assert.equal(moved.path, `/api/v1/documents/${a.document_id}`);
  assert.deepEqual(moved.body, { uri: archived, expected_hash: a.content_hash });
  assert.deepEqual((await client.manifest("p", "superpowers")).map(i => i.uri), [archived, "superpowers/b.md"]);
}));

test("revisions list a document's content writes newest first, one page at a time", () => withStub({}, async (stub, client) => {
  const first = await client.putDocument({ project: "p", uri: "superpowers/a.md", content: "one" });
  await client.putDocument({ project: "p", uri: "superpowers/a.md", content: "one" });
  const second = await client.putDocument({ project: "p", uri: "superpowers/a.md", content: "two" });
  const page = await client.revisions(first.document_id, { limit: 1 });
  assert.equal(page.document_id, first.document_id);
  assert.deepEqual(page.items.map(r => r.content_hash), [second.content_hash]);
  const rest = await client.revisions(first.document_id, { limit: 1, before: page.next_before });
  assert.deepEqual(rest.items.map(r => r.content_hash), [first.content_hash]);
  assert.deepEqual(Object.keys(rest.items[0]).sort(), ["actor", "api_key_id", "content_hash", "created_at", "id"]);
  assert.equal((await client.revisions(first.document_id)).items.length, 2, "an unchanged put records no revision");
}));
```

- [ ] **Step 2: Run them to verify they fail**

Run: `timeout 300 node --test plugins/dr-forge/tests/darkmem-sync/client.test.mjs`
Expected: FAIL — `TypeError: client.moveDocument is not a function` and `client.revisions is not a function`.

- [ ] **Step 3: Add the client calls**

In `scripts/lib/darkmem-client.mjs`, replace the header comment (lines 1-4) with:

```js
// The keyed REST surface darkmem serves a mirror (work-log lane spec §2): the
// work-log routes, POST /documents, GET /documents/by-uri, the manifest, and a
// document's move (PATCH /documents/{id}) and revisions. Every call carries the
// API key, names this client, and gives up after a bounded timeout.
```

After the `putDocument` method (ends at line 90), add:

```js
    moveDocument(documentId, { uri, expectedHash }) {
      const body = { uri };
      if (expectedHash) body.expected_hash = expectedHash;
      return call("PATCH", `/api/v1/documents/${encodeURIComponent(documentId)}`, { body });
    },
    revisions(documentId, { limit, before } = {}) {
      return call("GET", `/api/v1/documents/${encodeURIComponent(documentId)}/revisions`, { query: { limit, before } });
    },
```

- [ ] **Step 4: Add the stub routes**

In `tests/darkmem-sync/stub-server.mjs`, replace the header comment's last sentence pair (lines 7-10, from `// 404 text; every list is keyset-paged.` to the end of the comment) with:

```js
// 404 text; a document PATCH moves it to a free uri, under expected_hash when
// given (409 on a stale hash or a taken uri, 404 on an unknown id, 422 on an
// unknown field or nothing to change); every content write records a revision,
// listed newest first; every list is keyset-paged. db.failures injects answers:
// {method, path, status, detail, commit}, where commit: true applies the
// request first and then answers the failure, which is what a lost response
// looks like.
```

Replace line 28 with:

```js
  const db = { documents: new Map(), workstreams: [], requests: [], failures: [], nextSeq: 1, nextRevision: 1, clock: Date.now() };
```

Replace line 79 with:

```js
      if (outcome !== "unchanged") {
        Object.assign(doc, { content, content_hash: hash, updated_at: tick() });
        doc.revisions = [...(doc.revisions ?? []), { id: db.nextRevision++, content_hash: hash, actor: "stub", api_key_id: null, created_at: doc.updated_at }];
      }
```

After the POST documents block (the `}` closing it, line 85), add:

```js
    if (method === "GET" && (m = p.match(/^\/api\/v1\/documents\/([^/]+)\/revisions$/))) {
      const doc = [...db.documents.values()].find(d => d.id === m[1]);
      if (!doc) return send(404, { detail: `no document with id '${m[1]}'` });
      const limit = limitOf(url, 50);
      const before = q.get("before") === null ? Infinity : Number(q.get("before"));
      const items = (doc.revisions ?? []).filter(r => r.id < before).reverse().slice(0, limit);
      return send(200, { document_id: doc.id, items, next_before: items.length === limit ? items.at(-1).id : null });
    }
    if (method === "PATCH" && (m = p.match(/^\/api\/v1\/documents\/([^/]+)$/))) {
      const doc = [...db.documents.values()].find(d => d.id === m[1]);
      if (!doc) return send(404, { detail: `no document with id '${m[1]}'` });
      const unknown = Object.keys(body ?? {}).filter(k => !["uri", "title", "pinned", "tags", "expected_hash"].includes(k));
      if (unknown.length) return send(422, { detail: `unknown fields: ${unknown.join(", ")}` });
      if (!["uri", "title", "pinned", "tags"].some(k => body?.[k] !== undefined)) return send(422, { detail: "nothing to change" });
      if (body.expected_hash !== undefined && body.expected_hash !== null && body.expected_hash !== doc.content_hash) {
        return send(409, { detail: `expected_hash ${body.expected_hash} does not match the document's current content_hash ${doc.content_hash}` });
      }
      if (body.uri !== undefined && body.uri !== doc.uri) {
        if (db.documents.has(docKey(doc.project, body.uri))) return send(409, { detail: `uri '${body.uri}' is taken in project '${doc.project}'` });
        db.documents.delete(docKey(doc.project, doc.uri));
        doc.uri = body.uri;
        db.documents.set(docKey(doc.project, doc.uri), doc);
      }
      for (const k of ["title", "pinned", "tags"]) if (body[k] !== undefined) doc[k] = body[k];
      doc.updated_at = tick();
      return send(200, { document_id: doc.id });
    }
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `timeout 300 node --test plugins/dr-forge/tests/darkmem-sync/client.test.mjs`
Expected: PASS, every test.

Run: `timeout 900 bash plugins/dr-forge/tests/darkmem-sync.test.sh`
Expected: PASS (the stub change touches every sync suite).

- [ ] **Step 6: Commit**

```bash
git add plugins/dr-forge/scripts/lib/darkmem-client.mjs plugins/dr-forge/tests/darkmem-sync/stub-server.mjs plugins/dr-forge/tests/darkmem-sync/client.test.mjs
git commit -m "feat(dr-forge): add document move and revisions calls"
```

### Task 8: Archive helpers, the reserved archive directory, and deleted lines in status

**Files:**
- Modify: `scripts/lib/darkmem-mirror.mjs:13` (constants), `:88-112` (`listDocumentFiles`), `:564-587` (`localChanges`), new helpers after `uriFamily` (ends line 56)
- Modify: `scripts/lib/darkmem-import.mjs:11-14` (import), `:25-28` (reserved problem line)
- Test: `tests/darkmem-sync/mirror.test.mjs` (import list lines 7-11; the test at :31-42; two new tests)

**Interfaces:**
- Consumes: none.
- Produces: C3 — `ARCHIVE_PREFIX`, `isArchiveUri(uri)`, `utcStamp(date)`, `archiveUri(uri, stamp)`; also `RESERVED_DIRS` (`{ handoff: "handoff notes", archive: "archived documents" }`, the docs root's top-level directories whose files get uri `null`); `localChanges` prints `deleted: <uri>`.

**Implementer:** dr-superpowers:impl-sonnet-high
**Evaluation:** files 1 - spec 0 - coupling 2 - risk 2 = 5

- [ ] **Step 1: Write the failing tests**

In `tests/darkmem-sync/mirror.test.mjs`, replace the import block (lines 7-11) with:

```js
import {
  EMPTY_SHA, StateError, acquireLock, archiveUri, caseGroups, checkpointTarget, lockOwner, decodeUtf8, emptyState, familiesOf,
  isArchiveUri, isoMicros, ledgerEntries, ledgerFiles, ledgerPlanPath, lineProperties, listDocumentFiles, loadState, localChanges,
  pathToUri, propertiesFor, saveState, sha256, splitAtBlankLines, splitAtLimit, unsupportedPlanDirs, uriFamily, uriProblem, uriToLocal,
  utcStamp, utf8Fault,
} from "../../scripts/lib/darkmem-mirror.mjs";
```

Replace the test `document files list docs and handoff notes, skip dotfiles, and reserve docs/handoff` (lines 31-42) with:

```js
test("document files list docs and handoff notes, skip dotfiles, and reserve docs/handoff and docs/archive", () => {
  const { roots } = mirror();
  write(path.join(roots.docsRoot, "specs", "a.md"), "a");
  write(path.join(roots.docsRoot, ".hidden"), "h");
  write(path.join(roots.docsRoot, "handoff", "x.md"), "x");
  write(path.join(roots.docsRoot, "archive", "20261013T091502Z", "a.md"), "old");
  write(path.join(roots.workRoot, "sdd", "p1", "handoff.md"), "h");
  write(path.join(roots.workRoot, "sdd", "p1", "progress.md"), "l");
  write(path.join(roots.workRoot, "sdd", "bad name", "progress.md"), "l");
  assert.deepEqual(listDocumentFiles(roots).map(f => f.uri), [null, null, "superpowers/specs/a.md", "superpowers/handoff/p1.md"]);
  assert.deepEqual(ledgerFiles(roots.workRoot).map(f => f.slug), ["p1"]);
  assert.deepEqual(unsupportedPlanDirs(roots.workRoot), [path.join(roots.workRoot, "sdd", "bad name")]);
});

test("archive uris carry a UTC stamp under superpowers/archive/", () => {
  assert.equal(utcStamp(new Date("2026-10-13T09:15:02.789Z")), "20261013T091502Z");
  assert.match(utcStamp(), /^\d{8}T\d{6}Z$/);
  assert.equal(archiveUri("superpowers/specs/a.md", "20261013T091502Z"), "superpowers/archive/20261013T091502Z/specs/a.md");
  for (const uri of ["superpowers/archive", "superpowers/archive/20261013T091502Z/specs/a.md"]) assert.equal(isArchiveUri(uri), true, uri);
  for (const uri of ["superpowers/archives/a.md", "superpowers/specs/archive/a.md", "superpowers/a.md"]) assert.equal(isArchiveUri(uri), false, uri);
});

test("localChanges names a synced document deleted from the mirror, only while documents sync", () => {
  const { roots } = mirror();
  const state = emptyState();
  write(path.join(roots.docsRoot, "kept.md"), "k");
  state.documents["superpowers/kept.md"] = sha256("k");
  state.documents["superpowers/specs/gone.md"] = sha256("g");
  state.documents["superpowers/handoff/p1.md"] = sha256("h");
  write(path.join(roots.docsRoot, "archive", "x.md"), "x");
  assert.deepEqual(localChanges(roots, state), [
    `reserved: ${path.join("archive", "x.md")} (the docs root's archive/ directory is not synced)`,
    "deleted: superpowers/specs/gone.md",
  ]);
  assert.deepEqual(localChanges({ ...roots, families: { documents: false, progress: true } }, state), []);
});
```

- [ ] **Step 2: Run them to verify they fail**

Run: `timeout 300 node --test plugins/dr-forge/tests/darkmem-sync/mirror.test.mjs`
Expected: FAIL — `SyntaxError: The requested module … does not provide an export named 'archiveUri'`.

- [ ] **Step 3: Write the implementation**

In `scripts/lib/darkmem-mirror.mjs`, replace line 13 (`const HANDOFF_DIR = "handoff";`) with:

```js
const HANDOFF_DIR = "handoff";
export const ARCHIVE_PREFIX = `${DOC_PREFIX}/archive`;
// Top-level directories of the docs root whose files are never documents:
// their uri spaces hold the plans' handoff notes and the archived documents.
export const RESERVED_DIRS = { handoff: "handoff notes", archive: "archived documents" };
```

After `uriFamily` (its closing `}` is line 56), add:

```js
export function isArchiveUri(uri) {
  return uri === ARCHIVE_PREFIX || String(uri).startsWith(`${ARCHIVE_PREFIX}/`);
}

// UTC as YYYYMMDDTHHMMSSZ: archive stamps and the moves' backup directories.
export function utcStamp(date = new Date()) {
  return date.toISOString().replace(/\.\d+Z$/, "Z").replace(/[-:]/g, "");
}

// Where a deleted document is archived: superpowers/<rest> becomes
// superpowers/archive/<stamp>/<rest>, so a name deleted twice never collides.
export function archiveUri(uri, stamp) {
  return `${ARCHIVE_PREFIX}/${stamp}/${String(uri).slice(DOC_PREFIX.length + 1)}`;
}
```

In `listDocumentFiles`, replace the comment lines 88-91 with:

```js
// Every document file the mirror syncs, with its uri: files under the docs
// root when documents sync, then each plan's handoff.md when progress does.
// Dotfiles are never synced. A file under the docs root's handoff/ or
// archive/ directory gets uri null: those uri spaces belong to the handoff
// notes and the archived documents.
```

and replace line 101 with:

```js
      else if (entry.isFile()) found.push({ file, uri: Object.hasOwn(RESERVED_DIRS, next[0]) ? null : `${DOC_PREFIX}/${next.join("/")}` });
```

In `localChanges`, replace the reserved branch (lines 567-570) with:

```js
    if (!uri) {
      const rel = path.relative(roots.docsRoot, file);
      lines.push(`reserved: ${rel} (the docs root's ${rel.split(path.sep)[0]}/ directory is not synced)`);
      continue;
    }
```

and directly after that `for` loop's closing `}` (before `if (!familiesOf(roots).progress) return lines;`), add:

```js
  // Synced documents whose mirror file is gone: push archives them.
  if (familiesOf(roots).documents) {
    for (const uri of Object.keys(state.documents).sort()) {
      if (uriFamily(uri) !== "documents" || isArchiveUri(uri)) continue;
      const file = uriToLocal(roots, uri);
      if (file && !fs.existsSync(file)) lines.push(`deleted: ${uri}`);
    }
  }
```

In `scripts/lib/darkmem-import.mjs`, replace the mirror import (lines 11-14) with:

```js
import {
  MAX_ENTRIES_PER_APPEND, RESERVED_DIRS, decodeUtf8, emptyState, ledgerFiles, ledgerPlanPath, listDocumentFiles, propertiesFor,
  splitAtBlankLines, splitAtLimit, unsupportedPlanDirs, uriToLocal,
} from "./darkmem-mirror.mjs";
```

and replace the reserved branch in `readSources` (lines 25-28) with:

```js
    if (!uri) {
      const top = path.relative(roots.docsRoot, file).split(path.sep)[0];
      problems.push(`${file}: the docs directory's ${top}/ is reserved for ${RESERVED_DIRS[top]}`);
      continue;
    }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `timeout 300 node --test plugins/dr-forge/tests/darkmem-sync/mirror.test.mjs`
Expected: PASS.

Run: `timeout 900 bash plugins/dr-forge/tests/darkmem-sync.test.sh`
Expected: PASS (push's reserved-note test still sees the handoff/ text unchanged).

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-forge/scripts/lib/darkmem-mirror.mjs plugins/dr-forge/scripts/lib/darkmem-import.mjs plugins/dr-forge/tests/darkmem-sync/mirror.test.mjs
git commit -m "feat(dr-forge): reserve the mirror's archive directory"
```

### Task 9: Push archives documents deleted from the mirror

**Files:**
- Modify: `scripts/lib/darkmem-push.mjs:10-14` (import), `:121-124` (reserved note), new `archiveDeleted` before `pushDocuments` (line 111), `:349` (`push`)
- Test: `tests/darkmem-sync/push.test.mjs` (four new tests at the end)

**Interfaces:**
- Consumes: C2 `moveDocument` (Task 7); C3 `archiveUri`, `isArchiveUri`, `utcStamp`, `deleted:` status lines (Task 8).
- Produces: push's `archived` count (printed only when non-zero, after `checkpoints` in the summary).

**Implementer:** dr-superpowers:impl-sonnet-high
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 3 = 5

- [ ] **Step 1: Write the failing tests**

Append to `tests/darkmem-sync/push.test.mjs`:

```js
test("a synced document deleted from the mirror is archived under its recorded hash and its record dropped", async t => {
  const s = await setup(t);
  write(path.join(s.docsRoot, "specs", "a.md"), "# A\n");
  write(path.join(s.docsRoot, "specs", "b.md"), "# B\n");
  assert.equal((await s.push()).code, 0);
  fs.rmSync(path.join(s.docsRoot, "specs", "a.md"));
  assert.match((await run(["status"], { cwd: s.repo, env: s.env })).stdout, /^deleted: superpowers\/specs\/a\.md$/m);
  const result = await s.push();
  assert.equal(result.code, 0, result.stdout + result.stderr);
  assert.match(result.stdout, /darkmem-sync push: 0 documents, 0 ledger entries, 0 checkpoints, 1 archived; 0 conflicts, 0 failures/);
  const patch = s.stub.db.requests.find(r => r.method === "PATCH");
  assert.equal(patch.body.expected_hash, sha("# A\n"));
  assert.match(patch.body.uri, /^superpowers\/archive\/\d{8}T\d{6}Z\/specs\/a\.md$/);
  assert.deepEqual([...s.stub.db.documents.values()].map(d => d.uri).sort(), [patch.body.uri, "superpowers/specs/b.md"]);
  assert.deepEqual(Object.keys(JSON.parse(read(path.join(s.mirror, ".sync-state.json"))).documents), ["superpowers/specs/b.md"]);
  assert.doesNotMatch((await run(["status"], { cwd: s.repo, env: s.env })).stdout, /deleted:/);
  assert.doesNotMatch((await s.push()).stdout, /archived/, "nothing is archived twice");
});

test("a deleted document darkmem changed is a conflict that keeps its record; one darkmem no longer holds is dropped", async t => {
  const s = await setup(t);
  write(path.join(s.docsRoot, "a.md"), "a\n");
  write(path.join(s.docsRoot, "b.md"), "b\n");
  await s.push();
  await s.seed.putDocument({ project: "proj", uri: "superpowers/a.md", content: "remote\n", expectedHash: sha("a\n") });
  s.stub.db.documents.delete("proj\u0000superpowers/b.md");
  fs.rmSync(path.join(s.docsRoot, "a.md"));
  fs.rmSync(path.join(s.docsRoot, "b.md"));
  const result = await s.push();
  assert.equal(result.code, 1);
  assert.match(result.stdout, /^conflict: superpowers\/a\.md: deleted locally and changed on darkmem; pull to bring darkmem's copy back$/m);
  assert.equal(s.stub.db.requests.some(r => r.method === "PATCH"), false);
  assert.deepEqual(Object.keys(JSON.parse(read(path.join(s.mirror, ".sync-state.json"))).documents), ["superpowers/a.md"]);
});

test("a refused move is a conflict that keeps the record; a move whose answer was lost is settled by the next push", async t => {
  const s = await setup(t);
  write(path.join(s.docsRoot, "a.md"), "a\n");
  write(path.join(s.docsRoot, "b.md"), "b\n");
  await s.push();
  fs.rmSync(path.join(s.docsRoot, "a.md"));
  fs.rmSync(path.join(s.docsRoot, "b.md"));
  s.stub.db.failures.push({ method: "PATCH", path: "/api/v1/documents/", status: 409, detail: "uri is taken" });
  s.stub.db.failures.push({ method: "PATCH", path: "/api/v1/documents/", status: 503, detail: "busy", commit: true });
  const first = await s.push();
  assert.equal(first.code, 1);
  assert.match(first.stdout, /^conflict: superpowers\/a\.md: deleted locally, but darkmem refused to archive it \(darkmem said: uri is taken\); pull, then delete it again$/m);
  assert.match(first.stdout, /^failed: superpowers\/b\.md: darkmem answered 503: busy$/m);
  const second = await s.push();
  assert.equal(second.code, 0, second.stdout + second.stderr);
  assert.match(second.stdout, /, 1 archived;/);
  assert.equal(s.stub.db.requests.filter(r => r.method === "PATCH").length, 3, "the lost move is not sent again");
  assert.deepEqual(Object.keys(JSON.parse(read(path.join(s.mirror, ".sync-state.json"))).documents), []);
});

test("a missing docs root, documents applied local, or a deleted handoff note archive nothing", async t => {
  const s = await setup(t);
  write(path.join(s.docsRoot, "a.md"), "a\n");
  write(path.join(s.workRoot, "sdd", "p1", "handoff.md"), "h\n");
  await s.push();
  fs.rmSync(path.join(s.workRoot, "sdd", "p1", "handoff.md"));
  fs.rmSync(s.docsRoot, { recursive: true });
  const gone = await s.push();
  assert.equal(gone.code, 0, gone.stdout + gone.stderr);
  assert.match(gone.stdout, /^note: 1 synced documents are missing because .*superpowers is gone; none archived — pull to bring them back$/m);
  write(path.join(s.docsRoot, "b.md"), "b\n");
  fs.writeFileSync(path.join(s.home, ".dr-forge", "stores.json"), JSON.stringify({ [s.repo]: { documents: "local", progress: "darkmem" } }));
  assert.equal((await s.push()).code, 0);
  assert.equal(s.stub.db.requests.some(r => r.method === "PATCH"), false);
});
```

- [ ] **Step 2: Run them to verify they fail**

Run: `timeout 300 node --test plugins/dr-forge/tests/darkmem-sync/push.test.mjs`
Expected: FAIL — the first new test finds no `1 archived` in the summary; the second sees exit 0 and no conflict line.

- [ ] **Step 3: Write the implementation**

In `scripts/lib/darkmem-push.mjs`, replace the mirror import (lines 10-14) with:

```js
import {
  DOC_PREFIX, EMPTY_SHA, MAX_ENTRIES_PER_APPEND, MAX_ENTRY_CHARS, UsageError, archiveUri, caseGroups, checkpointTarget, decodeUtf8,
  familiesOf, isArchiveUri, isoMicros, ledgerEntries, ledgerFiles, ledgerPlanPath, listDocumentFiles, propertiesFor, sha256, splitAtLimit,
  unsupportedPlanDirs, uriFamily, uriProblem, uriToLocal, utcStamp, utf8Fault, validKey,
} from "./darkmem-mirror.mjs";
```

In `pushDocuments`, replace the reserved branch (lines 121-124) with:

```js
    if (!uri) {
      const rel = path.relative(roots.docsRoot, file).split(path.sep).join("/");
      report.notes.push(`${rel}: the docs root's ${rel.split("/")[0]}/ directory is reserved, not pushed`);
      continue;
    }
```

Before `async function pushDocuments(context) {` (line 111), add:

```js
// Every synced document whose mirror file is gone moves on darkmem to
// superpowers/archive/<stamp>/<rest> under its recorded hash, so an edit made
// on darkmem since the last sync is never archived unseen; restore moves it
// back. A missing docs root archives nothing: a lost mirror is not a request
// to archive every document.
async function archiveDeleted(context) {
  const { cfg, client, roots, state, persist, report } = context;
  const gone = Object.keys(state.documents).sort().filter(uri => {
    if (uriFamily(uri) !== "documents" || isArchiveUri(uri)) return false;
    const file = uriToLocal(roots, uri);
    return file !== null && !fs.existsSync(file);
  });
  if (!gone.length) return;
  if (!fs.existsSync(roots.docsRoot)) {
    report.notes.push(`${gone.length} synced documents are missing because ${roots.docsRoot} is gone; none archived — pull to bring them back`);
    return;
  }
  let remote;
  try {
    remote = new Map((await client.manifest(cfg.project, DOC_PREFIX)).map(item => [item.uri, item]));
  } catch (error) {
    failItem(report, "document manifest", error, "; no document archived");
    return;
  }
  const stamp = utcStamp();
  for (const uri of gone) {
    const recorded = state.documents[uri];
    const item = remote.get(uri);
    if (!item) {
      // Gone from darkmem too, perhaps by this mirror's own move whose answer
      // was lost: nothing is left to archive.
      delete state.documents[uri];
      persist();
      continue;
    }
    if (item.content_hash !== recorded) {
      report.conflicts.push(`${uri}: deleted locally and changed on darkmem; pull to bring darkmem's copy back`);
      continue;
    }
    try {
      await client.moveDocument(item.id, { uri: archiveUri(uri, stamp), expectedHash: recorded });
    } catch (error) {
      if (error instanceof HttpError && error.status === 409) {
        report.conflicts.push(`${uri}: deleted locally, but darkmem refused to archive it (darkmem said: ${error.detail}); pull, then delete it again`);
        continue;
      }
      failItem(report, uri, error);
      continue;
    }
    delete state.documents[uri];
    persist();
    report.counts.archived = (report.counts.archived ?? 0) + 1;
  }
}
```

In `push`, replace line 349 (`await pushDocuments(context);`) with:

```js
  await pushDocuments(context);
  if (families.documents) await archiveDeleted(context);
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `timeout 300 node --test plugins/dr-forge/tests/darkmem-sync/push.test.mjs`
Expected: PASS, the existing tests included (their summaries never archive, so they print no `archived` count).

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-forge/scripts/lib/darkmem-push.mjs plugins/dr-forge/tests/darkmem-sync/push.test.mjs
git commit -m "feat(dr-forge): archive documents deleted from mirror"
```

### Task 10: Pull skips archives, removes vanished documents, keeps local deletions

**Files:**
- Modify: `scripts/lib/darkmem-pull.mjs:7-9` (import), `:26-64` (`pullDocument`), `:66-92` (`pullDocuments`), new `removeVanished` before `pullDocuments`
- Test: `tests/darkmem-sync/pull.test.mjs` (three new tests at the end)

**Interfaces:**
- Consumes: C3 `isArchiveUri` (Task 8); C2 `moveDocument` in the tests' seed client (Task 7).
- Produces: pull's `removed` count (printed only when non-zero); `pullDocuments(context)` keeps its signature, which reconcile and restore call.

**Implementer:** dr-superpowers:impl-sonnet-high
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 3 = 5

- [ ] **Step 1: Write the failing tests**

Append to `tests/darkmem-sync/pull.test.mjs`:

```js
test("pull never writes an archived copy", async t => {
  const s = await setup(t);
  await s.seed.putDocument({ project: "proj", uri: "superpowers/archive/20261013T091502Z/specs/a.md", content: "old\n" });
  await s.seed.putDocument({ project: "proj", uri: "superpowers/specs/b.md", content: "b\n" });
  const result = await s.pull();
  assert.equal(result.code, 0, result.stdout + result.stderr);
  assert.equal(fs.existsSync(path.join(s.docsRoot, "archive")), false);
  assert.deepEqual(Object.keys(s.state().documents), ["superpowers/specs/b.md"]);
});

test("a document archived elsewhere is removed when unchanged and kept as a conflict when edited", async t => {
  const s = await setup(t);
  await s.seed.putDocument({ project: "proj", uri: "superpowers/a.md", content: "a\n" });
  await s.seed.putDocument({ project: "proj", uri: "superpowers/b.md", content: "b\n" });
  await s.pull();
  const id = uri => s.stub.db.documents.get(`proj\u0000${uri}`).id;
  await s.seed.moveDocument(id("superpowers/a.md"), { uri: "superpowers/archive/20261013T091502Z/a.md" });
  await s.seed.moveDocument(id("superpowers/b.md"), { uri: "superpowers/archive/20261013T091502Z/b.md" });
  write(path.join(s.docsRoot, "b.md"), "edited\n");
  const result = await s.pull();
  assert.equal(result.code, 1);
  assert.match(result.stdout, /^conflict: superpowers\/b\.md: archived or deleted on darkmem, and changed locally; the local file stays — push it under a new name, or delete it$/m);
  assert.match(result.stdout, /darkmem-sync pull: 0 documents, 0 ledgers, 0 checkpoints, 1 removed; 1 conflicts, 0 failures/);
  assert.equal(fs.existsSync(path.join(s.docsRoot, "a.md")), false);
  assert.equal(read(path.join(s.docsRoot, "b.md")), "edited\n");
  assert.deepEqual(Object.keys(s.state().documents), ["superpowers/b.md"]);
});

test("a local deletion waits for push while darkmem is unchanged; a changed copy or a lost docs root comes back", async t => {
  const s = await setup(t);
  await s.seed.putDocument({ project: "proj", uri: "superpowers/a.md", content: "one\n" });
  await s.seed.putDocument({ project: "proj", uri: "superpowers/b.md", content: "b\n" });
  await s.pull();
  fs.rmSync(path.join(s.docsRoot, "a.md"));
  const before = fetches(s.stub);
  assert.equal((await s.pull()).code, 0);
  assert.equal(fs.existsSync(path.join(s.docsRoot, "a.md")), false);
  assert.equal(fetches(s.stub), before, "nothing is fetched for a deletion push will archive");
  await s.seed.putDocument({ project: "proj", uri: "superpowers/a.md", content: "two\n", expectedHash: sha("one\n") });
  const changed = await s.pull();
  assert.equal(changed.code, 0, changed.stdout + changed.stderr);
  assert.match(changed.stdout, /^note: superpowers\/a\.md: deleted locally but changed on darkmem; darkmem's copy pulled back$/m);
  assert.equal(read(path.join(s.docsRoot, "a.md")), "two\n");
  fs.rmSync(s.docsRoot, { recursive: true });
  assert.equal((await s.pull()).code, 0);
  assert.equal(read(path.join(s.docsRoot, "a.md")), "two\n");
  assert.equal(read(path.join(s.docsRoot, "b.md")), "b\n");
});
```

- [ ] **Step 2: Run them to verify they fail**

Run: `timeout 300 node --test plugins/dr-forge/tests/darkmem-sync/pull.test.mjs`
Expected: FAIL — the archived copy is written under `superpowers/archive/`, the vanished `a.md` stays, and the deleted `a.md` is fetched again.

- [ ] **Step 3: Write the implementation**

In `scripts/lib/darkmem-pull.mjs`, replace the mirror import (lines 7-9) with:

```js
import {
  DOC_PREFIX, caseGroups, familiesOf, isArchiveUri, isoMicros, sha256, uriFamily, uriProblem, uriToLocal, validKey, writeFileAtomic,
} from "./darkmem-mirror.mjs";
```

Replace `pullDocument` (lines 23-64, comment included) with:

```js
// One manifest item whose hash differs from the mirror's copy. The local file
// is hashed again after the fetch, because an edit can land while the request
// is out. keepDeletions leaves a synced document deleted from the mirror to
// push, which archives it, while darkmem still holds the copy that was deleted.
async function pullDocument({ cfg, client, roots, state, persist, report }, item, keepDeletions) {
  // Checked before the mapping, which refuses some of these names on its own
  // (a handoff uri needs a workstream key) and would only note them.
  const problem = uriProblem(item.uri);
  if (problem) {
    report.failures.push(`${item.uri}: ${problem}, so not every mirror can hold it as a file; not pulled — rename it on darkmem by hand`);
    return;
  }
  const file = uriToLocal(roots, item.uri);
  if (!file) {
    report.notes.push(`${item.uri}: has no place in the mirror, skipped`);
    return;
  }
  const local = localHash(file);
  if (local === item.content_hash) {
    state.documents[item.uri] = local;
    return;
  }
  const deleted = keepDeletions && local === null && state.documents[item.uri] !== undefined && uriFamily(item.uri) === "documents";
  if (deleted && item.content_hash === state.documents[item.uri]) return;
  // darkmem has not moved since the last sync: a local edit is push's to
  // send, not a conflict.
  if (local !== null && item.content_hash === state.documents[item.uri]) return;
  if (local !== null && local !== state.documents[item.uri]) {
    report.conflicts.push(`${item.uri}: changed locally and on darkmem; ${RESOLVE}`);
    return;
  }
  const doc = await client.getDocument(cfg.project, item.uri);
  if (typeof doc.content !== "string") {
    report.notes.push(`${item.uri}: darkmem holds no text for it, skipped`);
    return;
  }
  if (localHash(file) !== local) {
    report.conflicts.push(`${item.uri}: changed locally during the pull; ${RESOLVE}`);
    return;
  }
  writeFileAtomic(file, doc.content);
  state.documents[item.uri] = doc.content_hash;
  persist();
  report.counts.documents += 1;
  if (deleted) report.notes.push(`${item.uri}: deleted locally but changed on darkmem; darkmem's copy pulled back`);
}

// A synced document darkmem no longer holds was archived or deleted
// elsewhere: an unchanged local copy goes with it, an edited one stays.
function removeVanished({ roots, state, persist, report }, filed) {
  for (const uri of Object.keys(state.documents).sort()) {
    if (filed.has(uri) || uriFamily(uri) !== "documents" || isArchiveUri(uri)) continue;
    const file = uriToLocal(roots, uri);
    if (!file) continue;
    const local = localHash(file);
    if (local !== null && local !== state.documents[uri]) {
      report.conflicts.push(`${uri}: archived or deleted on darkmem, and changed locally; the local file stays — push it under a new name, or delete it`);
      continue;
    }
    if (local !== null) {
      fs.rmSync(file);
      report.counts.removed = (report.counts.removed ?? 0) + 1;
    }
    delete state.documents[uri];
    persist();
  }
}
```

Replace `pullDocuments` (lines 66-92, comment included) with:

```js
// Every document under superpowers/ but the archives. Uris that differ only
// in case are one file on a case-insensitive file system, so none of them is
// written. A docs root that is gone entirely is a lost mirror, not a set of
// deletions, so every document is pulled back into it.
export async function pullDocuments(context) {
  const { cfg, client, roots, report } = context;
  let items;
  try {
    items = await client.manifest(cfg.project, DOC_PREFIX);
  } catch (error) {
    failItem(report, "document manifest", error, "; no document pulled");
    return;
  }
  const families = familiesOf(roots);
  const keepDeletions = families.documents && fs.existsSync(roots.docsRoot);
  const filed = new Set(items.map(item => item.uri));
  items = items.filter(item => !isArchiveUri(item.uri) && families[uriFamily(item.uri)]);
  const twins = caseGroups(items.map(item => item.uri));
  for (const group of twins) {
    report.conflicts.push(`${group.join(", ")}: differ only in case, which a case-insensitive file system holds as one file; none of them pulled — rename or delete all but one on darkmem by hand (the sync has no rename or delete route)`);
  }
  const held = new Set(twins.flat());
  for (const item of items) {
    if (!item.content_hash || held.has(item.uri)) continue;
    try {
      await pullDocument(context, item, keepDeletions);
    } catch (error) {
      failItem(report, item.uri, error);
    }
  }
  if (families.documents) removeVanished(context, filed);
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `timeout 300 node --test plugins/dr-forge/tests/darkmem-sync/pull.test.mjs`
Expected: PASS, the existing tests included.

Run: `timeout 300 node --test plugins/dr-forge/tests/darkmem-sync/import.test.mjs`
Expected: PASS (import's verification pulls into a scratch mirror through `pullDocuments`).

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-forge/scripts/lib/darkmem-pull.mjs plugins/dr-forge/tests/darkmem-sync/pull.test.mjs
git commit -m "feat(dr-forge): remove documents archived elsewhere"
```

### Task 11: Positional arguments and darkmem-sync revision

**Files:**
- Modify: `scripts/lib/darkmem-sync.mjs:5-13` (imports, `USAGE`), `:25-54` (`COMMANDS`, `parse`), `:80-89` (local-mode and family checks), `:101` (report), `:114` (context), `:144-146` (exit), new `revision` after `status` (line 23)
- Modify: `scripts/darkmem-sync:1-15` (header comment)
- Test: `tests/darkmem-sync/restore.test.mjs` (new)

**Interfaces:**
- Consumes: C2 `revisions` (Task 7).
- Produces: C4 — `positional` and `summary` on every `COMMANDS` entry, the optional `refuseLocal` hook, `parse` → `{ name, command, options, args }`, `context.args`, `report.refused`, the exact usage line, and the `revision NAME` command.

**Implementer:** dr-superpowers:impl-sonnet-high
**Evaluation:** files 1 - spec 0 - coupling 2 - risk 2 = 5

- [ ] **Step 1: Write the failing tests**

Create `tests/darkmem-sync/restore.test.mjs`:

```js
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import test from "node:test";
import { createClient } from "../../scripts/lib/darkmem-client.mjs";
import { STUB_KEY, sha, startStub } from "./stub-server.mjs";
import { makeHome, makeRepo, run, write } from "./helpers.mjs";

const USAGE = "usage: darkmem-sync status | pull | push [--workstream KEY] | import [--replace] | restore NAME | revision NAME | reconcile\n";

async function setup(t, stubOptions = {}) {
  const stub = await startStub(stubOptions);
  t.after(() => stub.close());
  const repo = makeRepo();
  const home = makeHome({ repo, url: stub.url });
  const seed = createClient({ url: stub.url, apiKey: STUB_KEY, runKey: "seed" });
  const sync = (...args) => run(args, { cwd: repo, env: home.env });
  return { stub, repo, ...home, seed, sync };
}

test("revision prints the newest revision of a synced, unchanged document under the name given", async t => {
  const s = await setup(t);
  write(path.join(s.docsRoot, "notes", "n.md"), "one\n");
  await s.sync("push");
  write(path.join(s.docsRoot, "notes", "n.md"), "two\n");
  await s.sync("push");
  const newest = s.stub.db.documents.get("proj\u0000superpowers/notes/n.md").revisions.at(-1).id;
  for (const name of ["docs/forge/notes/n.md", "docs/superpowers/notes/n.md"]) {
    const result = await s.sync("revision", name);
    assert.equal(result.code, 0, result.stdout + result.stderr);
    assert.equal(result.stdout, `${name}@r${newest}\n`);
  }
});

test("revision refuses a document that is unsynced, edited, behind darkmem, missing or local", async t => {
  const s = await setup(t);
  write(path.join(s.docsRoot, "a.md"), "a\n");
  const unsynced = await s.sync("revision", "docs/forge/a.md");
  assert.equal(unsynced.code, 1);
  assert.equal(unsynced.stdout, "refused: docs/forge/a.md is not synced and unchanged: it was never synced\n");
  await s.sync("push");
  write(path.join(s.docsRoot, "a.md"), "edited\n");
  assert.match((await s.sync("revision", "docs/forge/a.md")).stdout, /: it changed since the last sync; push first\n$/);
  write(path.join(s.docsRoot, "a.md"), "a\n");
  await s.seed.putDocument({ project: "proj", uri: "superpowers/a.md", content: "remote\n" });
  assert.match((await s.sync("revision", "docs/forge/a.md")).stdout, /: darkmem's copy differs; pull first\n$/);
  assert.match((await s.sync("revision", "docs/forge/missing.md")).stdout, /missing\.md does not exist\n$/);
  fs.writeFileSync(path.join(s.home, ".dr-forge", "stores.json"), JSON.stringify({ [s.repo]: { documents: "local", progress: "darkmem" } }));
  const local = await s.sync("revision", "docs/forge/a.md");
  assert.equal(local.code, 1);
  assert.match(local.stdout, /: documents are applied local\n$/);
});

test("revision refuses when darkmem files a newer version between the manifest read and the revisions read", async t => {
  let armed = false;
  const s = await setup(t, {
    onRequest: (request, db) => {
      if (!armed || !request.path.endsWith("/revisions")) return;
      armed = false;
      const doc = db.documents.get("proj\u0000superpowers/a.md");
      Object.assign(doc, { content: "newer\n", content_hash: sha("newer\n") });
      doc.revisions.push({ id: db.nextRevision++, content_hash: sha("newer\n"), actor: "stub", api_key_id: null, created_at: new Date().toISOString() });
    },
  });
  write(path.join(s.docsRoot, "a.md"), "a\n");
  await s.sync("push");
  armed = true;
  const result = await s.sync("revision", "docs/forge/a.md");
  assert.equal(result.code, 1);
  assert.equal(result.stdout, "refused: docs/forge/a.md is not synced and unchanged: darkmem's newest revision differs; pull first\n");
});

test("revision refuses in an unmapped repository", async () => {
  const repo = makeRepo();
  const { env } = makeHome({ repo, config: null });
  const result = await run(["revision", "docs/forge/a.md"], { cwd: repo, env });
  assert.equal(result.code, 1);
  assert.match(result.stdout, /^refused: docs\/forge\/a\.md is not synced and unchanged: local mode — no .*config\.json\n$/);
});

test("a missing or extra argument is a usage error", async t => {
  const s = await setup(t);
  for (const args of [["revision"], ["revision", "a", "b"], ["status", "x"], ["push", "x"]]) {
    const result = await s.sync(...args);
    assert.equal(result.code, 2, args.join(" "));
    assert.equal(result.stderr, USAGE);
  }
});
```

- [ ] **Step 2: Run them to verify they fail**

Run: `timeout 300 node --test plugins/dr-forge/tests/darkmem-sync/restore.test.mjs`
Expected: FAIL — `revision` is an unknown command (exit 2), the unmapped repository exits 0 with the local-mode line, and the usage line lacks `restore NAME | revision NAME | reconcile`.

- [ ] **Step 3: Write the implementation**

In `scripts/lib/darkmem-sync.mjs`, replace lines 5-13 (imports and `USAGE`) with:

```js
import fs from "node:fs";
import path from "node:path";
import { ConfigError, resolveStores, runKey } from "./darkmem-config.mjs";
import { HttpError, TransportError, createClient } from "./darkmem-client.mjs";
import {
  StateError, UsageError, acquireLock, isArchiveUri, loadState, localChanges, lockOwner, pathToUri, saveState, sha256, uriFamily,
  uriToLocal,
} from "./darkmem-mirror.mjs";
import { importRepository } from "./darkmem-import.mjs";
import { pull } from "./darkmem-pull.mjs";
import { push } from "./darkmem-push.mjs";

const USAGE = "usage: darkmem-sync status | pull | push [--workstream KEY] | import [--replace] | restore NAME | revision NAME | reconcile";
```

After `status` (its closing `}` is line 23), add:

```js
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
  if (!fs.existsSync(file)) return refuse(`${file} does not exist`);
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
```

Replace lines 25-54 (the `COMMANDS` comment, `COMMANDS` and `parse`) with:

```js
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
```

Replace lines 80-89 (from `if (!stores.sync) {` through the `syncsFamilies` check's closing `}`) with:

```js
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
```

Replace line 101 (the report) with:

```js
  const report = { conflicts: [], failures: [], notes: [], counts: {}, partial: false, refused: 0 };
```

Replace line 114 (the `run` call) with:

```js
    await parsed.command.run({ cfg, roots, state, persist, client, report, options: parsed.options, args: parsed.args, out, env });
```

Replace lines 144-146 (the end of `main`) with:

```js
  if (code !== 0) return code;
  if (parsed.command.summary) out(summary(parsed.name, report));
  return report.conflicts.length || report.failures.length || report.refused ? 1 : 0;
```

In `scripts/darkmem-sync`, replace the header comment (lines 2-15, from `# Keep this repository's` to the end of the `# Exit:` block) with:

```bash
# Keep this repository's dr-forge documents and progress in darkmem.
#
# A repository mapped in ~/.dr-forge/config.json (~/.dr-superpowers/ before 2.0)
# syncs a mirror at ~/.dr-forge/mirror/<project>/ (~/.dr-superpowers/ before
# 2.0): superpowers/ (specs, plans, registers, notes) while its documents are
# applied darkmem, work/sdd/<plan>/{progress.md,handoff.md} and
# work/handoff/latest.md while its progress is. ~/.dr-forge/stores.json records
# the applied stores; documentStore and progressSource choose them. reconcile
# moves each family whose configured store differs from its applied store, or
# prints a line saying where it stays and why it was refused. push archives a
# document deleted from the mirror under superpowers/archive/<stamp>/; restore
# brings back the newest archived copy of a document name; revision prints
# NAME@r<id>, the darkmem revision a synced, unchanged document cites. An
# unmapped repository is local mode: every command except import prints one
# line and does nothing.
#
# Usage: darkmem-sync status | pull | push [--workstream KEY] | import [--replace] | restore NAME | revision NAME | reconcile
# Exit: 0 done, or no family applied darkmem; 1 conflicts, refused or failed
#       items, a refused restore, revision or reconcile move, or another sync
#       holds the mirror; 2 usage, a malformed config, stores or state file, or import in
#       local mode; 3 darkmem unreachable, the API key unset (pull, push,
#       import, restore, revision), or an answer that stopped the command; 4 an
#       unexpected error (a bug)
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `timeout 300 node --test plugins/dr-forge/tests/darkmem-sync/restore.test.mjs`
Expected: PASS.

Run: `timeout 900 bash plugins/dr-forge/tests/darkmem-sync.test.sh`
Expected: PASS (every command's parsing and summary changed shape).

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-forge/scripts/lib/darkmem-sync.mjs plugins/dr-forge/scripts/darkmem-sync plugins/dr-forge/tests/darkmem-sync/restore.test.mjs
git commit -m "feat(dr-forge): add darkmem-sync revision command"
```

### Task 12: darkmem-sync restore

**Files:**
- Modify: `scripts/lib/darkmem-sync.mjs` (imports; new `restore` after `revision`; the `restore` entry in `COMMANDS`)
- Test: `tests/darkmem-sync/restore.test.mjs` (three new tests at the end; `read` added to the helpers import)

**Interfaces:**
- Consumes: C2 `moveDocument` (Task 7); C3 `ARCHIVE_PREFIX`, `isArchiveUri` (Task 8); C4 `args`, `refused`, `positional`, `refuseLocal` (Task 11); `pullDocuments(context)` (Task 10).
- Produces: C4 `restore NAME`.

**Implementer:** dr-superpowers:impl-sonnet-medium
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 2 = 4

- [ ] **Step 1: Write the failing tests**

In `tests/darkmem-sync/restore.test.mjs`, add `read` to the helpers import:

```js
import { makeHome, makeRepo, read, run, write } from "./helpers.mjs";
```

Append:

```js
test("restore moves the newest archived copy back under its hash and pulls it", async t => {
  const s = await setup(t);
  write(path.join(s.docsRoot, "specs", "a.md"), "one\n");
  await s.sync("push");
  fs.rmSync(path.join(s.docsRoot, "specs", "a.md"));
  await s.sync("push");
  await s.seed.putDocument({ project: "proj", uri: "superpowers/archive/20000101T000000Z/specs/a.md", content: "ancient\n" });
  const result = await s.sync("restore", "docs/superpowers/specs/a.md");
  assert.equal(result.code, 0, result.stdout + result.stderr);
  assert.match(result.stdout, /^restored: superpowers\/specs\/a\.md from superpowers\/archive\/\d{8}T\d{6}Z\/specs\/a\.md$/m);
  assert.doesNotMatch(result.stdout, /20000101T000000Z/);
  assert.match(result.stdout, /^darkmem-sync restore: 1 documents; 0 conflicts, 0 failures$/m);
  assert.equal(read(path.join(s.docsRoot, "specs", "a.md")), "one\n");
  const patch = s.stub.db.requests.filter(r => r.method === "PATCH").at(-1);
  assert.deepEqual(patch.body, { uri: "superpowers/specs/a.md", expected_hash: sha("one\n") });
});

test("restore refuses an occupied uri or a name with no archived copy, and needs documents applied darkmem", async t => {
  const s = await setup(t);
  await s.seed.putDocument({ project: "proj", uri: "superpowers/a.md", content: "live\n" });
  await s.seed.putDocument({ project: "proj", uri: "superpowers/archive/20261013T091502Z/a.md", content: "old\n" });
  const occupied = await s.sync("restore", "docs/forge/a.md");
  assert.equal(occupied.code, 1);
  assert.match(occupied.stdout, /^refused: superpowers\/a\.md is occupied on darkmem; move or rename that document first$/m);
  const none = await s.sync("restore", "docs/forge/b.md");
  assert.equal(none.code, 1);
  assert.match(none.stdout, /^refused: no archived copy of superpowers\/b\.md on darkmem$/m);
  assert.equal(s.stub.db.requests.some(r => r.method === "PATCH"), false);
  fs.writeFileSync(path.join(s.home, ".dr-forge", "stores.json"), JSON.stringify({ [s.repo]: { documents: "local", progress: "darkmem" } }));
  const local = await s.sync("restore", "docs/forge/a.md");
  assert.equal(local.code, 2);
  assert.equal(local.stderr, "darkmem-sync: restore needs documents applied darkmem\n");
});

test("restore takes only a document name and refuses in an unmapped repository", async t => {
  const s = await setup(t);
  await s.seed.putDocument({ project: "proj", uri: "superpowers/archive/20261013T091502Z/a.md", content: "old\n" });
  for (const name of [path.join(s.docsRoot, "a.md"), "a.md", "docs/forge/../a.md", "docs/forge/./a.md", "docs/forge/handoff/p1.md", "docs/forge/archive/20261013T091502Z/a.md"]) {
    const result = await s.sync("restore", name);
    assert.equal(result.code, 2, name);
    assert.equal(result.stderr, `darkmem-sync: ${name} does not name a document\n`);
  }
  assert.equal(s.stub.db.requests.some(r => r.method === "PATCH"), false);
  const repo = makeRepo();
  const { env } = makeHome({ repo, config: null });
  const unmapped = await run(["restore", "docs/forge/a.md"], { cwd: repo, env });
  assert.equal(unmapped.code, 2);
  assert.equal(unmapped.stderr, "darkmem-sync: restore needs documents applied darkmem\n");
});
```

- [ ] **Step 2: Run them to verify they fail**

Run: `timeout 300 node --test plugins/dr-forge/tests/darkmem-sync/restore.test.mjs`
Expected: FAIL — `restore` is a usage error (exit 2) printing the usage line, and the unmapped repository prints the local-mode line with exit 0.

- [ ] **Step 3: Write the implementation**

In `scripts/lib/darkmem-sync.mjs`, replace the mirror import with:

```js
import {
  ARCHIVE_PREFIX, DOC_PREFIX, StateError, UsageError, acquireLock, isArchiveUri, loadState, localChanges, lockOwner, pathToUri,
  saveState, sha256, uriFamily, uriToLocal,
} from "./darkmem-mirror.mjs";
```

and the pull import with:

```js
import { pull, pullDocuments } from "./darkmem-pull.mjs";
```

After `revision`, add:

```js
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
```

In `COMMANDS`, after the `import` entry, add (recordsConflicts is false: the pull covers documents only, so its conflicts must not replace the progress conflicts `status` keeps):

```js
  restore: {
    options: {}, positional: 1, needsKey: true, syncsFamilies: false, recordsConflicts: false, summary: true, run: restore,
    refuseLocal: ({ err }) => {
      err("darkmem-sync: restore needs documents applied darkmem");
      return 2;
    },
  },
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `timeout 300 node --test plugins/dr-forge/tests/darkmem-sync/restore.test.mjs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-forge/scripts/lib/darkmem-sync.mjs plugins/dr-forge/tests/darkmem-sync/restore.test.mjs
git commit -m "feat(dr-forge): add darkmem-sync restore command"
```

### Task 13: --mode takes a checkout and prints the project

**Files:**
- Modify: `scripts/lib/darkmem-config.mjs:215-220` (`modeLines`), `:252-272` (CLI)
- Test: `tests/darkmem-sync/config.test.mjs:164-182` (the exact-output test) and one new test after it

**Interfaces:**
- Consumes: none.
- Produces: C5 — `--mode [DIR]` and the `project\t<project>` line.

**Implementer:** dr-superpowers:impl-sonnet-medium
**Executor:** codex gpt-6.1-sol / high
**Evaluation:** files 1 - spec 0 - coupling 2 - risk 1 = 4

- [ ] **Step 1: Write the failing tests**

In `tests/darkmem-sync/config.test.mjs`, in the test `--mode prints each family's applied store and roots; a ConfigError exits 2 and no repository 3`, rename it to `--mode prints each family's applied store and roots and the project; a ConfigError exits 2 and no repository 3` and replace its expected output with:

```js
  assert.equal(result.stdout, [
    `documents\tlocal\t${path.join(repo, "docs", "forge")}`,
    `progress\tdarkmem\t${path.join(mirror, "work", "sdd")}\t${path.join(mirror, "work", "handoff", "latest.md")}`,
    "project\tproj",
    "",
  ].join("\n"));
```

After that test, add:

```js
test("--mode DIR resolves that checkout from anywhere; an unmapped one prints no project line", () => {
  const repo = makeRepo();
  const { env, mirror } = makeHome({ repo });
  const mode = (cwd, args) => spawnSync(process.execPath, [MODULE, ...args], { cwd, env, encoding: "utf8", timeout: 10000 });
  const elsewhere = scratch("dms-plain-");
  const result = mode(elsewhere, ["--mode", repo]);
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.stdout, [
    `documents\tdarkmem\t${path.join(mirror, "superpowers")}`,
    `progress\tdarkmem\t${path.join(mirror, "work", "sdd")}\t${path.join(mirror, "work", "handoff", "latest.md")}`,
    "project\tproj",
    "",
  ].join("\n"));
  assert.equal(mode(path.dirname(repo), ["--mode", path.basename(repo)]).stdout, result.stdout, "a relative DIR resolves against the working directory");
  const unmapped = mode(elsewhere, ["--mode", makeRepo()]);
  assert.equal(unmapped.status, 0, unmapped.stderr);
  assert.doesNotMatch(unmapped.stdout, /^project\t/m);
  assert.equal(mode(elsewhere, ["--mode", elsewhere]).status, 3);
  const extra = mode(elsewhere, ["--mode", repo, "extra"]);
  assert.equal(extra.status, 2);
  assert.equal(extra.stderr, "usage: darkmem-config.mjs --mode [DIR]\n");
});
```

- [ ] **Step 2: Run them to verify they fail**

Run: `timeout 300 node --test plugins/dr-forge/tests/darkmem-sync/config.test.mjs`
Expected: FAIL — no `project\tproj` line, and `--mode DIR` exits 2 with the old usage line.

- [ ] **Step 3: Write the implementation**

In `scripts/lib/darkmem-config.mjs`, replace `modeLines` (lines 215-220) with:

```js
export function modeLines(stores) {
  const lines = [
    `documents\t${stores.documents.applied}\t${stores.documents.root}`,
    `progress\t${stores.progress.applied}\t${stores.progress.ledgerRoot}\t${stores.progress.latestFile}`,
  ];
  if (stores.sync) lines.push(`project\t${stores.sync.project}`);
  return lines;
}
```

Replace the CLI block (lines 252-272) with:

```js
// `node darkmem-config.mjs --mode [DIR]`, which scripts/lib/roots.sh reads.
// DIR names the checkout for a caller that cannot set the working directory:
// a mod's process call sets none.
if (isMain()) {
  const [flag, dir, ...extra] = process.argv.slice(2);
  if (flag !== "--mode" || extra.length) {
    process.stderr.write("usage: darkmem-config.mjs --mode [DIR]\n");
    process.exitCode = 2;
  } else {
    try {
      const stores = resolveStores({ cwd: dir === undefined ? process.cwd() : path.resolve(dir) });
      if (stores.worktreeRoot) {
        process.stdout.write(`${modeLines(stores).join("\n")}\n`);
      } else {
        process.stderr.write("darkmem-config: not inside a git repository\n");
        process.exitCode = 3;
      }
    } catch (error) {
      if (!(error instanceof ConfigError)) throw error;
      process.stderr.write(`darkmem-config: ${error.message}\n`);
      process.exitCode = 2;
    }
  }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `timeout 300 node --test plugins/dr-forge/tests/darkmem-sync/config.test.mjs`
Expected: PASS.

Run: `timeout 600 bash plugins/dr-forge/tests/roots.test.sh`
Expected: PASS (`roots.sh` ignores the new `project` line until Task 14 reads it).

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-forge/scripts/lib/darkmem-config.mjs plugins/dr-forge/tests/darkmem-sync/config.test.mjs
git commit -m "feat(dr-forge): take a checkout and print the project"
```

### Task 14: forge_project and forge-path project

**Files:**
- Modify: `scripts/lib/roots.sh:16-17` (cache variables), `:27-39` (`_forge_local`), `:56` (reset), `:57-65` (read loop), new `forge_project` after line 82
- Modify: `scripts/forge-path:2,11,14-25` (usage comment, `usage`, `case`)
- Test: `tests/roots.test.sh` (new section before `# --- a --mode run that prints nothing stops the script ---`, line 91)

**Interfaces:**
- Consumes: C5 `project\t<project>` line (Task 13).
- Produces: C6 — `forge_project [DIR]` and `forge-path project`.

**Implementer:** dr-superpowers:impl-sonnet-medium
**Executor:** codex gpt-6.1-sol / high
**Evaluation:** files 1 - spec 0 - coupling 2 - risk 1 = 4

- [ ] **Step 1: Write the failing tests**

In `tests/roots.test.sh`, before the line `# --- a --mode run that prints nothing stops the script ---`, add:

```bash
# --- the mapped project, from roots.sh and from forge-path ---
FP="$HERE/../scripts/forge-path"
MIRROR=$(stores_home "$HOME" "$REPO" superpowers local local)
check "project: mapped, from a worktree" "$(cd "$WT" && forge_project)" "superpowers"
check "project: forge-path" "$(cd "$WT" && bash "$FP" project)" "superpowers"
OTHER="$TMP/other"
git init -q -b main "$OTHER"
git -C "$OTHER" commit -q --allow-empty -m init
(cd "$OTHER" && forge_project > "$TMP/project-out")
check "project: unmapped is status 1" "$?" "1"
check "project: unmapped prints nothing" "$(cat "$TMP/project-out")" ""
(cd "$OTHER" && bash "$FP" project > "$TMP/project-out")
check "project: forge-path unmapped exits 1" "$?" "1"
check "project: forge-path unmapped prints nothing" "$(cat "$TMP/project-out")" ""
(cd "$TMP" && forge_project > /dev/null)
check "project: outside git is status 1" "$?" "1"
(cd "$WT" && bash "$FP" project extra > /dev/null 2>&1)
check "project: forge-path takes no argument" "$?" "2"
```

- [ ] **Step 2: Run them to verify they fail**

Run: `timeout 600 bash plugins/dr-forge/tests/roots.test.sh`
Expected: FAIL — `forge_project: command not found`, and `forge-path project` exits 2 with the usage line.

- [ ] **Step 3: Write the implementation**

In `scripts/lib/roots.sh`, replace line 17 with:

```bash
_FORGE_PROGRESS_STORE="" _FORGE_LEDGER_ROOT="" _FORGE_LATEST="" _FORGE_PROJECT=""
```

In `_forge_local`, replace line 38 (`_FORGE_LATEST="$(forge_dir state "$primary")/handoff/latest.md"`) with:

```bash
  _FORGE_LATEST="$(forge_dir state "$primary")/handoff/latest.md"
  _FORGE_PROJECT=""
```

Replace line 56 with:

```bash
  _FORGE_DOCS_STORE="" _FORGE_DOCS_ROOT="" _FORGE_PROGRESS_STORE="" _FORGE_LEDGER_ROOT="" _FORGE_LATEST="" _FORGE_PROJECT=""
```

In the read loop, replace the `case $kind in … esac` block (lines 58-64) with:

```bash
    case $kind in
      documents) _FORGE_DOCS_STORE=$store _FORGE_DOCS_ROOT=$(_forge_path "$root") ;;
      progress)
        _FORGE_PROGRESS_STORE=$store _FORGE_LEDGER_ROOT=$(_forge_path "$root")
        _FORGE_LATEST=$(_forge_path "$extra")
        ;;
      project) _FORGE_PROJECT=$store ;;
    esac
```

After line 82 (`forge_ledger_dir() …`), add:

```bash
# forge_project [DIR] — the darkmem project the repository is mapped to;
# status 1 with nothing printed when it is unmapped, outside git or without node.
forge_project() { forge_stores_init "${1:-}"; [ -n "$_FORGE_PROJECT" ] || return 1; printf '%s\n' "$_FORGE_PROJECT"; }
```

In `scripts/forge-path`, replace lines 2-7 (the header comment) with:

```bash
# forge-path state [RELATIVE] | docs [RELATIVE] | ledger SLUG | latest | store | name PATH | project
# Where this repository's dr-forge files live: the state directory (.forge/,
# or the pre-2.0 .superpowers/; always in the checkout), the docs root and a
# plan's ledger directory and latest.md (in the checkout or in the darkmem
# mirror, as documentStore and progressSource apply them), each family's
# applied store, the repository-relative name of a path, or the darkmem
# project the repository is mapped to (exit 1 when it is unmapped).
```

Replace the `usage` line (line 11) with:

```bash
usage() { echo "usage: forge-path state|docs [RELATIVE] | ledger SLUG | latest | store | name PATH | project" >&2; exit 2; }
```

and in the `case`, after the `name)` arm (line 23), add:

```bash
  project) [ $# -eq 1 ] || usage; forge_project; exit $? ;;
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `timeout 600 bash plugins/dr-forge/tests/roots.test.sh`
Expected: PASS, `0 failed`.

Run: `timeout 600 bash plugins/dr-forge/tests/forge-dir.test.sh`
Expected: PASS (the forge-path checks there are unchanged).

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-forge/scripts/lib/roots.sh plugins/dr-forge/scripts/forge-path plugins/dr-forge/tests/roots.test.sh
git commit -m "feat(dr-forge): add forge_project and forge-path project"
```

### Task 15: reconcile command, refusals and in-progress check

**Files:**
- Create: `scripts/lib/darkmem-reconcile.mjs`
- Modify: `scripts/lib/darkmem-sync.mjs` (imports at lines 5-11, the `COMMANDS` table at lines 29-34, and `main` around the local-family check and the lock at lines 86-100; Task 12 has already shifted these lines — anchor on the quoted text)
- Test: `tests/darkmem-sync/reconcile.test.mjs` (create)

**Interfaces:**
- Consumes: C4 (`positional`, `summary`, `args`, `report.refused`, the usage line naming `reconcile`, from Tasks 11 and 12); `writeApplied`, `forgeDir` and `resolveStores` from `darkmem-config.mjs`; `ledgerPlanPath` and `DOC_PREFIX` from `darkmem-mirror.mjs`.
- Produces: C7 (`reconcile`, `inProgressReason(context)` → `null | { reason, details }`, `pendingFamilies`, `stayLine`, the `MOVES` table holding only the documents entries — Tasks 19 and 20 add `"progress:darkmem": progressToDarkmem` and `"progress:local": progressToLocal`, imported from `scripts/lib/darkmem-progress-move.mjs` — the output lines, the lock-held stay lines), C8 (`inProgress(cfg)`, the list `inProgressReason` summarises), and these exports: `refreshContext(context)`, `mirrorRoots(cfg, family)`, `nameSpellings(name)`, `leftoverLines(cfg)`. Module-internal helpers the documents moves call: `runGit(cwd, args, input)` → `{ status, stdout, stderr }`, `slash(file)`, `dirEntries(dir)`. Test helpers in `reconcile.test.mjs` later tasks reuse: `mapped(repo, { url, entry, stores })`, `cfgFor(cwd, env)`, `reconcile(cwd, env)`, `LEDGER(name)`, `storesOf(home, repo)`.

**Items:** 5

**Implementer:** dr-superpowers:impl-sonnet-high
**Evaluation:** files 1 - spec 0 - coupling 2 - risk 2 = 5

- [ ] **Step 1: Write the failing tests**

Create `tests/darkmem-sync/reconcile.test.mjs`:

```js
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import test from "node:test";
import { createClient } from "../../scripts/lib/darkmem-client.mjs";
import { resolveStores, writeApplied } from "../../scripts/lib/darkmem-config.mjs";
import {
  inProgress, inProgressReason, nameSpellings, pendingFamilies, refreshContext, stayLine,
} from "../../scripts/lib/darkmem-reconcile.mjs";
import { STUB_KEY, sha, startStub } from "./stub-server.mjs";
import { git, makeHome, makeRepo, read, run, scratch, write } from "./helpers.mjs";

// A HOME mapping `repo` to project "proj" with the mapping entry's overrides,
// and stores.json recording `stores` (null: no record).
function mapped(repo, { url = "http://127.0.0.1:9", entry = {}, stores = { documents: "local", progress: "local" } } = {}) {
  return makeHome({ repo, url, stores, config: { darkmem: { url, api_key_env: "DARKMEM_API_KEY", repos: { [repo]: { project: "proj", ...entry } } } } });
}

// The command context's cfg, built as main builds it.
function cfgFor(cwd, env) {
  const stores = resolveStores({ cwd, env });
  return { ...stores.sync, repoRoot: stores.repoRoot, worktreeRoot: stores.worktreeRoot, documents: stores.documents, progress: stores.progress };
}

const reconcile = (cwd, env) => run(["reconcile"], { cwd, env });
const LEDGER = name => `# SDD ledger — plan: ${name}\nTask 1: complete (abc)\n`;
const storesOf = (home, repo) => JSON.parse(read(path.join(home, ".dr-forge", "stores.json")))[repo];

test("a document name has one key under either prefix", () => {
  assert.deepEqual(nameSpellings("docs/superpowers/plans/p.md"), ["docs/forge/plans/p.md", "docs/superpowers/plans/p.md"]);
  assert.deepEqual(nameSpellings("./docs/forge/plans/p.md"), ["docs/forge/plans/p.md", "docs/superpowers/plans/p.md"]);
  assert.deepEqual(nameSpellings("docs/superpowers"), ["docs/forge", "docs/superpowers"]);
  assert.deepEqual(nameSpellings("docs/superpowersx/a.md"), ["docs/superpowersx/a.md"]);
  assert.deepEqual(nameSpellings("/abs/docs/superpowers/a.md"), ["/abs/docs/superpowers/a.md"]);
});

test("pending families are those whose configured store differs from the applied one", () => {
  const repo = makeRepo();
  const { env } = mapped(repo, { entry: { progressSource: "local" } });
  const cfg = cfgFor(repo, env);
  assert.deepEqual(pendingFamilies(cfg), ["documents"]);
  assert.equal(stayLine(cfg, "documents", "why"), "darkmem-sync reconcile: documents stay local (configured darkmem): why");
});

test("refreshContext re-reads the stores, so a second move sees the roots the first produced", () => {
  const repo = makeRepo();
  const { env, docsRoot } = mapped(repo, { entry: { progressSource: "local" } });
  const context = { cfg: cfgFor(repo, env), env };
  assert.equal(context.cfg.documents.root, path.join(repo, "docs", "forge"));
  writeApplied(env, repo, { documents: "darkmem" });
  refreshContext(context);
  assert.equal(context.cfg.documents.applied, "darkmem");
  assert.equal(context.cfg.documents.root, docsRoot);
  assert.equal(context.roots.docsRoot, docsRoot);
  assert.deepEqual(context.roots.families, { documents: true, progress: false });
});

test("an unmapped repository is local mode", async () => {
  const repo = makeRepo();
  const { env } = makeHome({ repo, config: null });
  const result = await reconcile(repo, env);
  assert.equal(result.code, 0, result.stderr);
  assert.match(result.stdout, /^darkmem-sync: local mode — /);
});

test("with nothing to move reconcile prints nothing, takes no lock and calls nothing", async t => {
  const stub = await startStub();
  t.after(() => stub.close());
  const repo = makeRepo();
  const { env, mirror } = mapped(repo, { url: stub.url, entry: { documentStore: "local", progressSource: "local" } });
  const result = await reconcile(repo, env);
  assert.equal(result.code, 0, result.stderr);
  assert.equal(result.stdout, "");
  assert.equal(stub.db.requests.length, 0);
  assert.equal(fs.existsSync(path.join(mirror, ".sync.lock")), false);
});

test("with no record, a family whose files the sync state lists counts as applied darkmem", async () => {
  const repo = makeRepo();
  const { env, mirror } = mapped(repo, { entry: { progressSource: "local" }, stores: null });
  delete env.DARKMEM_API_KEY;
  const before = await reconcile(repo, env);
  assert.equal(before.code, 1);
  assert.equal(before.stdout, "darkmem-sync reconcile: documents stay local (configured darkmem): DARKMEM_API_KEY is not set\n");
  write(path.join(mirror, ".sync-state.json"), JSON.stringify({
    version: 1, documents: { "superpowers/specs/a.md": sha("a") }, ledgers: {}, checkpoint: null, checkpointAt: null, conflicts: [],
  }));
  const after = await reconcile(repo, env);
  assert.equal(after.code, 0, after.stderr);
  assert.equal(after.stdout, "");
});

test("each common refusal names every pending family and records nothing", async () => {
  const repo = makeRepo();
  const { env, home, mirror } = mapped(repo);
  const lines = reason => ["documents", "progress"].map(f => `darkmem-sync reconcile: ${f} stay local (configured darkmem): ${reason}`);
  const noKey = { ...env };
  delete noKey.DARKMEM_API_KEY;
  const missing = await reconcile(repo, noKey);
  assert.equal(missing.code, 1);
  assert.equal(missing.stdout, `${lines("DARKMEM_API_KEY is not set").join("\n")}\n`);
  const unreachable = await reconcile(repo, env);
  assert.equal(unreachable.code, 1);
  assert.equal(unreachable.stdout.split("\n").filter(line => /stay local \(configured darkmem\): darkmem is unreachable: /.test(line)).length, 2, unreachable.stdout);
  fs.mkdirSync(path.join(mirror, ".sync.lock"), { recursive: true });
  const locked = await reconcile(repo, env);
  assert.equal(locked.code, 1);
  assert.equal(locked.stdout, `${lines("another darkmem-sync holds the mirror lock").join("\n")}\n`);
  assert.deepEqual(storesOf(home, repo), { documents: "local", progress: "local" });
});

test("reconcile refuses every pending family while a plan is in progress", async t => {
  const stub = await startStub();
  t.after(() => stub.close());
  const repo = makeRepo();
  const { env } = mapped(repo, { url: stub.url });
  write(path.join(repo, ".forge", "sdd", "p1", "progress.md"), LEDGER("docs/forge/plans/p1.md"));
  write(path.join(repo, ".forge", "sdd", "p2", "progress.md"), LEDGER("docs/forge/plans/p2.md"));
  const result = await reconcile(repo, env);
  assert.equal(result.code, 1);
  assert.equal(result.stdout, [
    "darkmem-sync reconcile: documents stay local (configured darkmem): a plan is in progress: docs/forge/plans/p1.md",
    "  docs/forge/plans/p2.md",
    "darkmem-sync reconcile: progress stay local (configured darkmem): a plan is in progress: docs/forge/plans/p1.md",
    "  docs/forge/plans/p2.md",
    "",
  ].join("\n"));
  assert.equal(stub.db.requests.length, 0);
});

test("a ledger whose plan completed.md does not record is in progress, under either spelling", () => {
  const repo = makeRepo();
  const { env } = mapped(repo, { entry: { documentStore: "local", progressSource: "local" } });
  const completed = path.join(repo, "docs", "forge", "plans", "completed.md");
  write(path.join(repo, ".forge", "sdd", "p1", "progress.md"), LEDGER("docs/superpowers/plans/p1.md"));
  write(path.join(repo, "docs", "forge", "plans", "p1.md"), "# P1\n");
  assert.deepEqual(inProgress(cfgFor(repo, env)), ["docs/superpowers/plans/p1.md"]);
  write(completed, "- `docs/forge/plans/p1.md` — done\n");
  assert.deepEqual(inProgress(cfgFor(repo, env)), []);
  write(completed, "- `docs/superpowers/plans/p1.md` — done\n");
  assert.deepEqual(inProgress(cfgFor(repo, env)), []);
  write(completed, "- `docs/forge/plans/p10.md` — done\n");
  assert.deepEqual(inProgress(cfgFor(repo, env)), ["docs/superpowers/plans/p1.md"]);
});

test("every worktree's ledgers count while progress is local, and a ledger without an identity line is in progress", () => {
  const repo = makeRepo();
  const { env } = mapped(repo, { entry: { documentStore: "local", progressSource: "local" } });
  const linked = path.join(scratch("dms-wt-"), "wt");
  git(repo, "worktree", "add", "-q", linked);
  write(path.join(linked, ".forge", "sdd", "p2", "progress.md"), LEDGER("docs/forge/plans/p2.md"));
  write(path.join(repo, ".forge", "sdd", "odd", "progress.md"), "Task 1: complete (abc)\n");
  assert.deepEqual(inProgress(cfgFor(repo, env)).sort(), [path.join(repo, ".forge", "sdd", "odd", "progress.md"), "docs/forge/plans/p2.md"].sort());
});

test("while progress is applied darkmem only the mirror's ledgers count, resolved under the applied docs root", () => {
  const repo = makeRepo();
  const { env, docsRoot, workRoot } = mapped(repo, { stores: { documents: "darkmem", progress: "darkmem" } });
  write(path.join(repo, ".forge", "sdd", "local", "progress.md"), LEDGER("docs/forge/plans/local.md"));
  write(path.join(workRoot, "sdd", "p3", "progress.md"), LEDGER("docs/forge/plans/p3.md"));
  assert.deepEqual(inProgress(cfgFor(repo, env)), ["docs/forge/plans/p3.md"]);
  write(path.join(docsRoot, "plans", "completed.md"), "- `docs/superpowers/plans/p3.md`\n");
  assert.deepEqual(inProgress(cfgFor(repo, env)), []);
});

test("an active auto run is in progress", () => {
  const repo = makeRepo();
  const { env } = mapped(repo);
  const file = path.join(repo, ".forge", "sdd", "auto-run.json");
  write(file, JSON.stringify({ active: true, spec: "docs/forge/specs/s.md" }));
  assert.deepEqual(inProgress(cfgFor(repo, env)), ["an auto run is active"]);
  assert.deepEqual(inProgressReason({ cfg: cfgFor(repo, env) }), { reason: "a plan is in progress: an auto run is active", details: [] });
  write(file, JSON.stringify({ active: false }));
  assert.deepEqual(inProgress(cfgFor(repo, env)), []);
  assert.equal(inProgressReason({ cfg: cfgFor(repo, env) }), null);
});

test("a docs directory left in the checkout while documents are applied darkmem is named as not read", async () => {
  const repo = makeRepo();
  const { env } = mapped(repo, { entry: { progressSource: "local" }, stores: { documents: "darkmem", progress: "local" } });
  write(path.join(repo, "docs", "forge", "specs", "a.md"), "# A\n");
  const result = await reconcile(repo, env);
  assert.equal(result.code, 0, result.stderr);
  assert.equal(result.stdout, `darkmem-sync reconcile: ${path.join(repo, "docs", "forge")} is not read while documents are applied darkmem\n`);
});
```

`createClient` and `STUB_KEY` are imported here for the move tasks' tests, which append to this file. The end-to-end check that a second move in one run sees the first move's roots (documents and progress both moving) belongs to the progress move tasks, the first point where both families have a move.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `timeout 300 node --test plugins/dr-forge/tests/darkmem-sync/reconcile.test.mjs`
Expected: FAIL — `Cannot find module '…/scripts/lib/darkmem-reconcile.mjs'`.

- [ ] **Step 3: Write the module**

Create `scripts/lib/darkmem-reconcile.mjs`:

```js
// darkmem-sync reconcile (darkmem store options spec §4, §7.2): move each
// family whose configured store differs from its applied store, under §4's
// refusals, and record each completed move in ~/.dr-forge/stores.json.
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { HttpError, TransportError } from "./darkmem-client.mjs";
import { forgeDir, resolveStores, writeApplied } from "./darkmem-config.mjs";
import { DOC_PREFIX, ledgerPlanPath } from "./darkmem-mirror.mjs";

const FAMILIES = ["documents", "progress"];
const LEGACY = "docs/superpowers";
const DOCS = "docs/forge";

// Each move, under "<family>:<target store>". A move answers
// { moved: true, details } or { moved: false, reason, details }.
const MOVES = {};

function runGit(cwd, args, input) {
  const result = spawnSync("git", ["-C", cwd, ...args], { encoding: "utf8", timeout: 60000, input, maxBuffer: 64 * 1024 * 1024 });
  return { status: result.status, stdout: result.stdout ?? "", stderr: result.stderr ?? "" };
}

const slash = file => file.split(path.sep).join("/");

function dirEntries(dir) {
  try {
    return fs.readdirSync(dir, { withFileTypes: true }).filter(entry => entry.isDirectory()).map(entry => entry.name).sort();
  } catch (error) {
    if (error.code === "ENOENT") return [];
    throw error;
  }
}

// One document name under either docs prefix (spec §7.1), as forge_name_key
// and forge_name_spellings spell it in roots.sh.
export function nameSpellings(name) {
  const text = String(name).replace(/^\.\//, "");
  const key = text === LEGACY || text.startsWith(`${LEGACY}/`) ? `${DOCS}${text.slice(LEGACY.length)}` : text;
  return key === DOCS || key.startsWith(`${DOCS}/`) ? [key, `${LEGACY}${key.slice(DOCS.length)}`] : [key];
}

export function pendingFamilies(cfg) {
  return FAMILIES.filter(family => cfg[family].configured !== cfg[family].applied);
}

export function stayLine(cfg, family, reason) {
  return `darkmem-sync reconcile: ${family} stay ${cfg[family].applied} (configured ${cfg[family].configured}): ${reason}`;
}

// The mirror subtree one move reads or fills, with only that family synced.
export function mirrorRoots(cfg, family) {
  return {
    docsRoot: path.join(cfg.mirror, "superpowers"),
    workRoot: path.join(cfg.mirror, "work"),
    worktreeRoot: cfg.repoRoot,
    families: { documents: family === "documents", progress: family === "progress" },
  };
}

// Re-reads the stores after a move, so the next move sees the roots the
// last one produced; cfg and roots are rebuilt as main builds them.
export function refreshContext(context) {
  const stores = resolveStores({ cwd: context.cfg.worktreeRoot, env: context.env });
  const cfg = { ...stores.sync, repoRoot: stores.repoRoot, worktreeRoot: stores.worktreeRoot, documents: stores.documents, progress: stores.progress };
  context.cfg = cfg;
  context.roots = {
    docsRoot: cfg.documents.root,
    workRoot: path.join(cfg.mirror, "work"),
    worktreeRoot: cfg.worktreeRoot,
    families: { documents: cfg.documents.applied === "darkmem", progress: cfg.progress.applied === "darkmem" },
  };
}

export function leftoverLines(cfg) {
  if (cfg.documents.applied !== "darkmem" || !cfg.worktreeRoot) return [];
  return [path.join(cfg.worktreeRoot, "docs", "forge"), path.join(cfg.worktreeRoot, "docs", "superpowers")]
    .filter(dir => fs.existsSync(dir))
    .map(dir => `darkmem-sync reconcile: ${dir} is not read while documents are applied darkmem`);
}

// Where the ledgers live: every worktree's state directory while progress is
// local, the mirror's work tree while it is darkmem.
function ledgerSources(cfg) {
  if (cfg.progress.applied === "darkmem") return [{ sdd: path.join(cfg.mirror, "work", "sdd"), checkout: cfg.repoRoot }];
  const listing = runGit(cfg.repoRoot, ["worktree", "list", "--porcelain"]);
  const trees = listing.status === 0
    ? listing.stdout.split(/\r?\n/).filter(line => line.startsWith("worktree ")).map(line => line.slice("worktree ".length))
    : [cfg.repoRoot];
  return trees.map(tree => ({ sdd: path.join(forgeDir("state", tree), "sdd"), checkout: tree }));
}

function planFile(cfg, checkout, name) {
  if (path.isAbsolute(name)) return name;
  const [key] = nameSpellings(name);
  if (key === DOCS || key.startsWith(`${DOCS}/`)) {
    const docsRoot = cfg.documents.applied === "darkmem" ? path.join(cfg.mirror, "superpowers") : forgeDir("docs", checkout);
    return path.join(docsRoot, ...key.slice(DOCS.length).split("/").filter(Boolean));
  }
  return path.join(checkout, key);
}

// Matched on the backticked name, as plan_finished does, so one plan's name
// that is a substring of another's cannot claim its outcome.
function planFinished(cfg, checkout, name) {
  let text;
  try {
    text = fs.readFileSync(path.join(path.dirname(planFile(cfg, checkout, name)), "completed.md"), "utf8");
  } catch {
    return false;
  }
  return nameSpellings(name).some(spelling => text.includes(`\`${spelling}\``));
}

// Why no move may run now (spec §4, C8): an active auto run, then each ledger
// whose plan completed.md does not record, by its plan name, or by its path
// when it has no identity line.
export function inProgress(cfg) {
  const found = [];
  try {
    const run = JSON.parse(fs.readFileSync(path.join(forgeDir("state", cfg.repoRoot), "sdd", "auto-run.json"), "utf8"));
    if (run?.active === true) found.push("an auto run is active");
  } catch {
    // No auto run, or an unreadable record, which auto-run.sh reads as inactive too.
  }
  for (const { sdd, checkout } of ledgerSources(cfg)) {
    for (const slug of dirEntries(sdd)) {
      const ledger = path.join(sdd, slug, "progress.md");
      let text;
      try {
        text = fs.readFileSync(ledger, "utf8");
      } catch {
        continue;
      }
      const name = ledgerPlanPath(text);
      if (!name) found.push(ledger);
      else if (!planFinished(cfg, checkout, name)) found.push(name);
    }
  }
  return found;
}

// C8's refusal: null, or the first in-progress item as the reason and the
// rest as details. A move calls it again after its own pull.
export function inProgressReason(context) {
  const found = inProgress(context.cfg);
  return found.length ? { reason: `a plan is in progress: ${found[0]}`, details: found.slice(1) } : null;
}

export async function reconcile(context) {
  const { client, env, out, report } = context;
  const pending = pendingFamilies(context.cfg);
  const refuseAll = (reason, details = []) => {
    for (const family of pending) {
      out(stayLine(context.cfg, family, reason));
      for (const line of details) out(`  ${line}`);
      report.refused += 1;
    }
  };
  const busy = inProgressReason(context);
  if (busy) return refuseAll(busy.reason, busy.details);
  if (!context.cfg.apiKey) return refuseAll(`${context.cfg.keyEnv} is not set`);
  try {
    await client.manifest(context.cfg.project, DOC_PREFIX);
  } catch (error) {
    if (error instanceof TransportError) return refuseAll(`darkmem is unreachable: ${error.message}`);
    if (error instanceof HttpError) return refuseAll(`darkmem refused the manifest read: ${error.message}`);
    throw error;
  }
  // Without a record the applied store follows the sync state (first-run
  // rule), which a refused move's partial pull could tip to darkmem; the
  // record pins it first. A recorded family is rewritten with its own value.
  writeApplied(env, context.cfg.repoRoot, { documents: context.cfg.documents.applied, progress: context.cfg.progress.applied });
  for (const family of pending) {
    const { cfg } = context;
    const target = cfg[family].configured;
    const move = MOVES[`${family}:${target}`];
    let result;
    if (!move) {
      result = { moved: false, reason: `no move from ${cfg[family].applied} to ${target}`, details: [] };
    } else {
      try {
        result = await move(context);
      } catch (error) {
        if (!(error instanceof TransportError || error instanceof HttpError)) throw error;
        result = { moved: false, reason: `darkmem failed during the move: ${error.message}`, details: [] };
      }
    }
    if (result.moved) {
      writeApplied(env, cfg.repoRoot, { [family]: target });
      refreshContext(context);
      out(`darkmem-sync reconcile: ${family} moved to ${target}`);
    } else {
      out(stayLine(context.cfg, family, result.reason));
      report.refused += 1;
    }
    for (const line of result.details) out(`  ${line}`);
  }
  for (const line of leftoverLines(context.cfg)) out(line);
}
```

- [ ] **Step 4: Wire it into `darkmem-sync.mjs`**

Add the import after the `darkmem-pull.mjs` import line:

```js
import { leftoverLines, pendingFamilies, reconcile, stayLine } from "./darkmem-reconcile.mjs";
```

Add to `COMMANDS`, after the `import` entry (the other fields as Task 12 spelled them for its entries):

```js
  reconcile: { options: {}, positional: 0, needsKey: false, syncsFamilies: false, recordsConflicts: false, summary: false, run: reconcile },
```

In `main`, immediately before `if (parsed.command.needsKey && !cfg.apiKey) {`, insert:

```js
  // Nothing to move takes no lock and calls nothing; the leftover warning
  // still prints, since session start runs reconcile every time.
  if (parsed.name === "reconcile" && !pendingFamilies(cfg).length) {
    for (const line of leftoverLines(cfg)) out(line);
    return 0;
  }
```

Replace

```js
  const release = acquireLock(cfg.mirror);
  if (!release) {
```

with

```js
  const release = acquireLock(cfg.mirror);
  if (!release && parsed.name === "reconcile") {
    for (const family of pendingFamilies(cfg)) out(stayLine(cfg, family, "another darkmem-sync holds the mirror lock"));
    return 1;
  }
  if (!release) {
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `timeout 300 node --test plugins/dr-forge/tests/darkmem-sync/reconcile.test.mjs`
Expected: PASS, 13 tests.

Run: `timeout 900 bash plugins/dr-forge/tests/darkmem-sync.test.sh`
Expected: PASS (every other sync suite unchanged).

- [ ] **Step 6: Commit**

```bash
git add plugins/dr-forge/scripts/lib/darkmem-reconcile.mjs plugins/dr-forge/scripts/lib/darkmem-sync.mjs plugins/dr-forge/tests/darkmem-sync/reconcile.test.mjs
git commit -m "feat(dr-forge): add darkmem-sync reconcile"
```

### Task 16: move documents from the repository into darkmem

**Files:**
- Modify: `scripts/lib/darkmem-reconcile.mjs` (imports, the `MOVES` table, new functions after `inProgressReason`)
- Test: `tests/darkmem-sync/reconcile.test.mjs` (append)

**Interfaces:**
- Consumes: C7's `MOVES` table, `inProgressReason`, `mirrorRoots`, `runGit` and `slash` (Task 15); `pullDocuments` from `darkmem-pull.mjs` (it skips archive uris and removes unchanged deleted copies after Task 8); `uriProblem`, `caseGroups`, `decodeUtf8`, `sha256` from `darkmem-mirror.mjs`; the test helpers `mapped`, `cfgFor`, `reconcile`, `LEDGER`, `storesOf`.
- Produces: the `"documents:darkmem"` move; module-internal `pullReport()` and `fileHash(file)`, which Task 17 reuses; test helpers `docsRepo(t, files, { stores, stub })`, `commitAll(repo, message)`, `writes(stub, from)`, `at(repo, name)`.

**Items:** 5

**Implementer:** dr-superpowers:impl-sonnet-high
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 3 = 5

- [ ] **Step 1: Write the failing tests**

Append to `tests/darkmem-sync/reconcile.test.mjs`:

```js
// A repository whose committed docs/forge holds `files` (name -> content),
// mapped with documents configured darkmem; progress stays local. `stores` is
// the stores.json record (null: none); `stub` is passed to startStub.
async function docsRepo(t, files = { "specs/a.md": "# A\n" }, { stores = { documents: "local", progress: "local" }, stub: stubOptions = {} } = {}) {
  const stub = await startStub(stubOptions);
  t.after(() => stub.close());
  const repo = makeRepo();
  for (const [name, content] of Object.entries(files)) write(path.join(repo, "docs", "forge", ...name.split("/")), content);
  git(repo, "add", "-A");
  git(repo, "commit", "-q", "-m", "docs");
  const home = mapped(repo, { url: stub.url, entry: { progressSource: "local" }, stores });
  const seed = createClient({ url: stub.url, apiKey: STUB_KEY, runKey: "seed" });
  return { stub, repo, seed, ...home, stores: () => storesOf(home.home, repo), reconcile: () => reconcile(repo, home.env) };
}

const commitAll = (repo, message) => {
  git(repo, "add", "-A");
  git(repo, "commit", "-q", "-m", message);
};
const writes = (stub, from = 0) => stub.db.requests.slice(from).filter(r => r.method === "POST" || r.method === "PATCH");
const at = (repo, name) => path.join(repo, ...name.split("/"));

test("documents move into darkmem: imported, pulled into the mirror, verified, and their deletion staged", async t => {
  const s = await docsRepo(t, { "specs/a.md": "# A\n", "plans/p.md": "# P\n**Spec:** docs/forge/specs/a.md\n" });
  write(path.join(s.repo, "CLAUDE.md"), "See docs/superpowers/specs/a.md\n");
  write(path.join(s.repo, "README.md"), "No citations\n");
  commitAll(s.repo, "cite");
  await s.seed.putDocument({ project: "proj", uri: "superpowers/specs/a.md", content: "# A\n" });
  const result = await s.reconcile();
  assert.equal(result.code, 0, result.stdout + result.stderr);
  assert.match(result.stdout, /^darkmem-sync reconcile: documents moved to darkmem$/m);
  assert.ok(result.stdout.includes(`  the deletion of docs/forge is staged in ${s.repo}; commit it\n`), result.stdout);
  assert.ok(result.stdout.includes("    CLAUDE.md\n"), result.stdout);
  assert.doesNotMatch(result.stdout, /README\.md/);
  assert.equal(read(path.join(s.docsRoot, "plans", "p.md")), "# P\n**Spec:** docs/forge/specs/a.md\n");
  assert.equal(s.stub.db.documents.size, 2);
  assert.equal(writes(s.stub).filter(r => r.body?.uri === "superpowers/specs/a.md").length, 1, "the copy darkmem already held is not sent again");
  assert.equal(git(s.repo, "status", "--porcelain"), "D  docs/forge/plans/p.md\nD  docs/forge/specs/a.md");
  assert.equal(fs.existsSync(path.join(s.repo, "docs", "forge")), false);
  assert.deepEqual(s.stores(), { documents: "darkmem", progress: "local" });
  const again = await s.reconcile();
  assert.equal(again.code, 0, again.stderr);
  assert.equal(again.stdout, "");
});

test("a docs directory with no tracked files moves without staging anything, and is then named as not read", async t => {
  const stub = await startStub();
  t.after(() => stub.close());
  const repo = makeRepo();
  fs.mkdirSync(path.join(repo, "docs", "forge", "specs"), { recursive: true });
  const { env, home, docsRoot } = mapped(repo, { url: stub.url, entry: { progressSource: "local" } });
  await createClient({ url: stub.url, apiKey: STUB_KEY, runKey: "seed" }).putDocument({ project: "proj", uri: "superpowers/specs/b.md", content: "# B\n" });
  const result = await reconcile(repo, env);
  assert.equal(result.code, 0, result.stdout + result.stderr);
  assert.match(result.stdout, /^darkmem-sync reconcile: documents moved to darkmem$/m);
  assert.ok(result.stdout.includes("  docs/forge holds no tracked files; nothing to stage\n"), result.stdout);
  assert.ok(result.stdout.includes(`darkmem-sync reconcile: ${path.join(repo, "docs", "forge")} is not read while documents are applied darkmem\n`), result.stdout);
  assert.equal(read(path.join(docsRoot, "specs", "b.md")), "# B\n");
  assert.equal(git(repo, "status", "--porcelain"), "");
  assert.deepEqual(storesOf(home, repo), { documents: "darkmem", progress: "local" });
});

test("the citation list stops at 20 and counts the rest, and does not refuse the move", async t => {
  const s = await docsRepo(t);
  for (let i = 0; i < 23; i += 1) write(path.join(s.repo, "cite", `f${String(i).padStart(2, "0")}.md`), "docs/forge/specs/a.md\n");
  commitAll(s.repo, "cite");
  const result = await s.reconcile();
  assert.equal(result.code, 0, result.stdout + result.stderr);
  assert.ok(result.stdout.includes("    cite/f19.md\n"), result.stdout);
  assert.doesNotMatch(result.stdout, /cite\/f20\.md/);
  assert.ok(result.stdout.includes("  and 3 more\n"), result.stdout);
});

const caseFolds = (() => {
  const dir = scratch("dms-case-");
  fs.writeFileSync(path.join(dir, "a"), "");
  return fs.existsSync(path.join(dir, "A"));
})();
const UNCARRIED = [
  { kind: "a dotfile at depth", named: "docs/forge/specs/.draft.md", plant: repo => write(at(repo, "docs/forge/specs/.draft.md"), "x\n") },
  { kind: "a dot directory", named: "docs/forge/.cache/x.md", plant: repo => write(at(repo, "docs/forge/.cache/x.md"), "x\n") },
  { kind: "a symbolic link", named: "docs/forge/link.md", skip: process.platform === "win32", plant: repo => fs.symlinkSync("specs/a.md", at(repo, "docs/forge/link.md")) },
  { kind: "a file under handoff/", named: "docs/forge/handoff/x.md", plant: repo => write(at(repo, "docs/forge/handoff/x.md"), "x\n") },
  { kind: "a file under archive/", named: "docs/forge/archive/x.md", plant: repo => write(at(repo, "docs/forge/archive/x.md"), "x\n") },
  { kind: "an empty file", named: "docs/forge/empty.md", plant: repo => write(at(repo, "docs/forge/empty.md"), "") },
  { kind: "a file that is not UTF-8", named: "docs/forge/bin.md", plant: repo => write(at(repo, "docs/forge/bin.md"), Buffer.from([0x41, 0xff, 0x0a])) },
  { kind: "a name uriProblem rejects", named: "docs/forge/specs/aux.md", skip: process.platform === "win32", plant: repo => write(at(repo, "docs/forge/specs/aux.md"), "x\n") },
  { kind: "a case twin", named: "docs/forge/specs/A.md", skip: caseFolds, plant: repo => write(at(repo, "docs/forge/specs/A.md"), "# twin\n") },
  {
    kind: "an ignored file", named: "docs/forge/secret.md",
    plant: repo => {
      write(at(repo, ".gitignore"), "docs/forge/secret.md\n");
      write(at(repo, "docs/forge/secret.md"), "s\n");
    },
  },
];

for (const { kind, named, plant, skip = false } of UNCARRIED) {
  test(`documents stay local when the docs directory holds ${kind}`, { skip }, async t => {
    const s = await docsRepo(t);
    plant(s.repo);
    commitAll(s.repo, "plant");
    const result = await s.reconcile();
    assert.equal(result.code, 1, result.stdout + result.stderr);
    assert.match(result.stdout, /^darkmem-sync reconcile: documents stay local \(configured darkmem\): docs\/forge holds files the move cannot carry$/m);
    assert.ok(result.stdout.includes(`  ${named}`), result.stdout);
    assert.deepEqual(writes(s.stub), []);
    assert.equal(s.stub.db.documents.size, 0);
    assert.deepEqual(s.stores(), { documents: "local", progress: "local" });
    assert.equal(git(s.repo, "status", "--porcelain"), "");
  });
}

test("documents stay local while the docs directory has uncommitted changes", async t => {
  const s = await docsRepo(t);
  write(path.join(s.repo, "docs", "forge", "specs", "a.md"), "# A edited\n");
  write(path.join(s.repo, "docs", "forge", "new.md"), "new\n");
  const result = await s.reconcile();
  assert.equal(result.code, 1);
  assert.match(result.stdout, /^darkmem-sync reconcile: documents stay local \(configured darkmem\): docs\/forge has uncommitted changes$/m);
  assert.match(result.stdout, /^ {3}M docs\/forge\/specs\/a\.md$/m);
  assert.match(result.stdout, /^ {2}\?\? docs\/forge\/new\.md$/m);
  assert.deepEqual(writes(s.stub), []);
});

test("a different version on darkmem refuses the move before anything is sent", async t => {
  const s = await docsRepo(t, { "specs/a.md": "# A\n", "specs/b.md": "# B\n" });
  await s.seed.putDocument({ project: "proj", uri: "superpowers/specs/a.md", content: "# A on darkmem\n" });
  const from = s.stub.db.requests.length;
  const result = await s.reconcile();
  assert.equal(result.code, 1);
  assert.match(result.stdout, /^darkmem-sync reconcile: documents stay local \(configured darkmem\): darkmem holds a different version of some documents; nothing was sent$/m);
  assert.match(result.stdout, /^ {2}superpowers\/specs\/a\.md: darkmem holds a different version$/m);
  assert.deepEqual(writes(s.stub, from), []);
  assert.equal(s.stub.db.documents.size, 1);
  assert.equal(git(s.repo, "status", "--porcelain"), "");
});

test("a pull that reads back different bytes refuses the move, keeps the repository copy, and with no record keeps documents applied local", async t => {
  const s = await docsRepo(t, undefined, { stores: null, stub: { transformContent: content => `${content}altered\n` } });
  const result = await s.reconcile();
  assert.equal(result.code, 1, result.stdout + result.stderr);
  assert.match(result.stdout, /^darkmem-sync reconcile: documents stay local \(configured darkmem\): a pull of darkmem's copy differs from the repository$/m);
  assert.match(result.stdout, /^ {2}superpowers\/specs\/a\.md: the mirror's copy differs from the repository's$/m);
  assert.equal(read(at(s.repo, "docs/forge/specs/a.md")), "# A\n");
  assert.equal(git(s.repo, "status", "--porcelain"), "");
  assert.deepEqual(s.stores(), { documents: "local", progress: "local" });
  assert.equal(cfgFor(s.repo, s.env).documents.applied, "local", "the pulled sync state does not tip the first-run rule");
});

test("a plan that starts during the pull stops the move before the deletion is staged", async t => {
  let repo;
  const s = await docsRepo(t, undefined, {
    stub: {
      onRequest: request => {
        if (repo && request.path === "/api/v1/documents/by-uri") write(at(repo, ".forge/sdd/late/progress.md"), LEDGER("docs/forge/plans/late.md"));
      },
    },
  });
  repo = s.repo;
  const result = await s.reconcile();
  assert.equal(result.code, 1, result.stdout + result.stderr);
  assert.match(result.stdout, /^darkmem-sync reconcile: documents stay local \(configured darkmem\): a plan is in progress: docs\/forge\/plans\/late\.md$/m);
  assert.equal(git(s.repo, "diff", "--cached", "--name-only"), "");
  assert.equal(read(at(s.repo, "docs/forge/specs/a.md")), "# A\n");
  assert.deepEqual(s.stores(), { documents: "local", progress: "local" });
});
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `timeout 300 node --test plugins/dr-forge/tests/darkmem-sync/reconcile.test.mjs`
Expected: FAIL — the new tests see `documents stay local (configured darkmem): no move from local to darkmem`.

- [ ] **Step 3: Write the move**

In `scripts/lib/darkmem-reconcile.mjs`, replace the mirror import line

```js
import { DOC_PREFIX, ledgerPlanPath } from "./darkmem-mirror.mjs";
```

with

```js
import { DOC_PREFIX, caseGroups, decodeUtf8, ledgerPlanPath, sha256, uriProblem } from "./darkmem-mirror.mjs";
import { pullDocuments } from "./darkmem-pull.mjs";
```

Replace `const MOVES = {};` with

```js
const MOVES = {
  "documents:darkmem": documentsToDarkmem,
};
```

Add after `inProgressReason`:

```js
const pullReport = () => ({ conflicts: [], failures: [], notes: [], counts: { documents: 0, ledgers: 0, checkpoints: 0 }, partial: false, refused: 0 });
const fileHash = file => (fs.existsSync(file) ? sha256(fs.readFileSync(file)) : null);

// Why the mirror would never sync a tracked file (spec §7.2), or null.
function uncarried(docsDir, parts) {
  if (parts.some(part => part.startsWith("."))) return "a dot name, which the mirror never syncs";
  if (parts[0] === "handoff") return "under handoff/, which is reserved for plan handoff notes";
  if (parts[0] === "archive") return "under archive/, which is reserved for deletion archives";
  let at = docsDir;
  for (const part of parts) {
    at = path.join(at, part);
    if (fs.lstatSync(at).isSymbolicLink()) return "a symbolic link, or reached through one, which the mirror never syncs";
  }
  return fs.lstatSync(at).isFile() ? null : "not a regular file";
}

// The tracked documents the move carries, and every file it cannot (§7.2).
// Tracked is the test because git rm -r deletes only tracked paths.
function carriedDocuments(repoRoot, docsDir, rel) {
  const problems = [];
  const documents = [];
  const listed = runGit(repoRoot, ["ls-files", "-z", "--", rel]);
  for (const file of listed.stdout.split("\0").filter(Boolean)) {
    const parts = file.slice(rel.length + 1).split("/");
    const why = uncarried(docsDir, parts);
    if (why) {
      problems.push(`${file}: ${why}`);
      continue;
    }
    const buffer = fs.readFileSync(path.join(docsDir, ...parts));
    const content = decodeUtf8(buffer);
    if (!content) {
      problems.push(`${file}: empty or not UTF-8 text, which darkmem cannot store`);
      continue;
    }
    const uri = `${DOC_PREFIX}/${parts.join("/")}`;
    const problem = uriProblem(uri);
    if (problem) {
      problems.push(`${file}: ${problem}`);
      continue;
    }
    documents.push({ file, parts, uri, content, hash: sha256(buffer) });
  }
  const fileOf = new Map(documents.map(doc => [doc.uri, doc.file]));
  for (const group of caseGroups(documents.map(doc => doc.uri))) {
    problems.push(`${group.map(uri => fileOf.get(uri)).join(", ")}: differ only in case, which a case-insensitive file system holds as one file`);
  }
  // The mirror walks the filesystem, so it would carry an ignored file, and
  // git rm -r would leave it behind.
  const ignored = runGit(repoRoot, ["status", "--porcelain", "-z", "--ignored=matching", "--untracked-files=all", "--", rel]);
  for (const item of ignored.stdout.split("\0")) {
    if (item.startsWith("!! ")) problems.push(`${item.slice(3)}: ignored by git, so the mirror would carry it and git rm would leave it behind`);
  }
  return { problems, documents };
}

// Documents, repository -> darkmem (spec §4): nothing is sent until every
// check passes, darkmem's copies are never overwritten, and the repository
// copy is removed only after a pull into the mirror reads back every file.
// A missing or empty docs directory has nothing tracked and moves as is.
async function documentsToDarkmem(context) {
  const { cfg, client } = context;
  const docsDir = forgeDir("docs", cfg.repoRoot);
  const rel = slash(path.relative(cfg.repoRoot, docsDir));
  const dirty = runGit(cfg.repoRoot, ["status", "--porcelain", "--untracked-files=all", "--", rel]);
  if (dirty.status !== 0) return { moved: false, reason: `git status failed: ${dirty.stderr.trim()}`, details: [] };
  if (dirty.stdout.trim()) return { moved: false, reason: `${rel} has uncommitted changes`, details: dirty.stdout.split("\n").filter(Boolean) };
  const { problems, documents } = carriedDocuments(cfg.repoRoot, docsDir, rel);
  if (problems.length) return { moved: false, reason: `${rel} holds files the move cannot carry`, details: problems };
  // Import puts without a hash precondition, so this check is what keeps
  // darkmem's copies; the window between it and the puts is accepted.
  const remote = new Map((await client.manifest(cfg.project, DOC_PREFIX)).map(item => [item.uri, item.content_hash]));
  const differing = [];
  for (const doc of documents) {
    const held = remote.get(doc.uri);
    if (held !== undefined && held !== doc.hash) differing.push(`${doc.uri}: darkmem holds a different version`);
    const twins = [...remote.keys()].filter(uri => uri !== doc.uri && uri.toLowerCase() === doc.uri.toLowerCase()).sort();
    if (twins.length) differing.push(`${doc.uri}: darkmem holds ${twins.join(", ")}, which differ only in case`);
  }
  if (differing.length) return { moved: false, reason: "darkmem holds a different version of some documents; nothing was sent", details: differing };
  for (const doc of documents) {
    if (!remote.has(doc.uri)) await client.putDocument({ project: cfg.project, uri: doc.uri, content: doc.content });
  }
  const mirror = mirrorRoots(cfg, "documents");
  const pulled = pullReport();
  await pullDocuments({ ...context, roots: mirror, report: pulled });
  if (pulled.conflicts.length || pulled.failures.length) {
    return { moved: false, reason: "the pull into the mirror did not complete; the repository copy stays", details: [...pulled.conflicts, ...pulled.failures] };
  }
  const busy = inProgressReason(context);
  if (busy) return { moved: false, ...busy };
  const mismatched = documents
    .filter(doc => fileHash(path.join(mirror.docsRoot, ...doc.parts)) !== doc.hash)
    .map(doc => `${doc.uri}: the mirror's copy differs from the repository's`);
  if (mismatched.length) return { moved: false, reason: "a pull of darkmem's copy differs from the repository", details: mismatched };
  if (!documents.length) return { moved: true, details: [`${rel} holds no tracked files; nothing to stage`] };
  const removed = runGit(cfg.repoRoot, ["rm", "-r", "-q", "--", rel]);
  if (removed.status !== 0) return { moved: false, reason: `git rm failed: ${removed.stderr.trim()}`, details: [] };
  const details = [`the deletion of ${rel} is staged in ${cfg.repoRoot}; commit it`];
  const cites = runGit(cfg.repoRoot, ["grep", "-I", "-l", "-F", "-e", "docs/superpowers/", "-e", "docs/forge/", "--", ".", `:(exclude)${rel}`]);
  const citing = cites.status === 0 ? cites.stdout.split("\n").filter(Boolean) : [];
  if (citing.length) {
    details.push("these tracked files cite docs/superpowers/ or docs/forge/ names; rewrite them before you commit the deletion:");
    details.push(...citing.slice(0, 20).map(file => `  ${file}`));
    if (citing.length > 20) details.push(`and ${citing.length - 20} more`);
  }
  return { moved: true, details };
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `timeout 300 node --test plugins/dr-forge/tests/darkmem-sync/reconcile.test.mjs`
Expected: PASS (on Linux every §7.2 kind runs; Windows skips the symbolic link and device-name kinds, and a case-folding file system skips the case twin).

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-forge/scripts/lib/darkmem-reconcile.mjs plugins/dr-forge/tests/darkmem-sync/reconcile.test.mjs
git commit -m "feat(dr-forge): move documents into darkmem"
```

### Task 17: move documents from darkmem back into the repository

**Files:**
- Modify: `scripts/lib/darkmem-reconcile.mjs` (imports, the `MOVES` table, a new function after `documentsToDarkmem`)
- Test: `tests/darkmem-sync/reconcile.test.mjs` (append)

**Interfaces:**
- Consumes: C3 `utcStamp` and `isArchiveUri` (Task 8); C7's `MOVES`, `inProgressReason`, `mirrorRoots`, `runGit`, `slash` (Task 15) and `pullReport`, `fileHash` (Task 16); `listDocumentFiles` and `uriFamily` from `darkmem-mirror.mjs`; the test helpers `mapped`, `reconcile`, `LEDGER`, `storesOf`, `commitAll`, `at`.
- Produces: the `"documents:local"` move.

**Items:** 5

**Implementer:** dr-superpowers:impl-sonnet-high
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 3 = 5

- [ ] **Step 1: Write the failing tests**

Append to `tests/darkmem-sync/reconcile.test.mjs`:

```js
// Documents applied darkmem and configured local, darkmem holding two of them.
async function darkmemDocs(t) {
  const stub = await startStub();
  t.after(() => stub.close());
  const repo = makeRepo();
  const home = mapped(repo, { url: stub.url, entry: { documentStore: "local", progressSource: "local" }, stores: { documents: "darkmem", progress: "local" } });
  const seed = createClient({ url: stub.url, apiKey: STUB_KEY, runKey: "seed" });
  await seed.putDocument({ project: "proj", uri: "superpowers/specs/a.md", content: "# A\n" });
  await seed.putDocument({ project: "proj", uri: "superpowers/plans/p.md", content: "# P\n" });
  return {
    stub, repo, seed, ...home,
    stores: () => storesOf(home.home, repo),
    reconcile: () => reconcile(repo, home.env),
    pull: () => run(["pull"], { cwd: repo, env: home.env }),
  };
}

test("documents move back into docs/forge, untracked, and the mirror copy is set aside", async t => {
  const s = await darkmemDocs(t);
  write(path.join(s.repo, ".gitattributes"), "docs/superpowers/plans/completed.md merge=union\n");
  write(path.join(s.repo, ".gitignore"), "docs/forge/plans/\n");
  commitAll(s.repo, "attributes");
  write(path.join(s.repo, "docs", "forge", "specs", "a.md"), "# A\n");
  const result = await s.reconcile();
  assert.equal(result.code, 0, result.stdout + result.stderr);
  assert.match(result.stdout, /^darkmem-sync reconcile: documents moved to local$/m);
  assert.ok(result.stdout.includes("  copied 2 files into docs/forge, untracked; commit them\n"), result.stdout);
  assert.ok(result.stdout.includes("  docs/forge/plans/p.md: ignored by git, so a commit would leave it out\n"), result.stdout);
  assert.ok(result.stdout.includes("  .gitattributes line 1 still names docs/superpowers/: docs/superpowers/plans/completed.md merge=union\n"), result.stdout);
  assert.equal(read(path.join(s.repo, "docs", "forge", "plans", "p.md")), "# P\n");
  assert.equal(fs.existsSync(s.docsRoot), false);
  const aside = fs.readdirSync(s.mirror).filter(name => /^superpowers-moved-\d{8}T\d{6}Z$/.test(name));
  assert.equal(aside.length, 1);
  assert.equal(read(path.join(s.mirror, aside[0], "specs", "a.md")), "# A\n");
  assert.deepEqual(Object.keys(JSON.parse(read(path.join(s.mirror, ".sync-state.json"))).documents), []);
  assert.deepEqual(s.stores(), { documents: "local", progress: "local" });
  assert.equal(s.stub.db.documents.size, 2, "darkmem keeps its copy");
  const again = await s.reconcile();
  assert.equal(again.code, 0, again.stderr);
  assert.equal(again.stdout, "");
});

test("a legacy docs/superpowers directory stays untouched and is named as not read", async t => {
  const s = await darkmemDocs(t);
  write(path.join(s.repo, "docs", "superpowers", "old.md"), "old\n");
  const result = await s.reconcile();
  assert.equal(result.code, 0, result.stdout + result.stderr);
  assert.match(result.stdout, /^darkmem-sync reconcile: documents moved to local$/m);
  assert.ok(result.stdout.includes(`  ${path.join(s.repo, "docs", "superpowers")} is a legacy docs directory and is not read; documents now live in docs/forge\n`), result.stdout);
  assert.equal(read(path.join(s.repo, "docs", "superpowers", "old.md")), "old\n");
  assert.equal(read(path.join(s.repo, "docs", "forge", "specs", "a.md")), "# A\n");
  assert.deepEqual(s.stores(), { documents: "local", progress: "local" });
});

test("a differing file already in docs/forge refuses the move and nothing is copied", async t => {
  const s = await darkmemDocs(t);
  write(path.join(s.repo, "docs", "forge", "specs", "a.md"), "# A local\n");
  const result = await s.reconcile();
  assert.equal(result.code, 1);
  assert.match(result.stdout, /^darkmem-sync reconcile: documents stay darkmem \(configured local\): docs\/forge already holds different copies; nothing was copied$/m);
  assert.ok(result.stdout.includes("  docs/forge/specs/a.md: already exists with different content\n"), result.stdout);
  assert.equal(fs.existsSync(path.join(s.repo, "docs", "forge", "plans", "p.md")), false);
  assert.equal(read(path.join(s.docsRoot, "plans", "p.md")), "# P\n");
  assert.deepEqual(s.stores(), { documents: "darkmem", progress: "local" });
});

test("a mirror copy that differs from darkmem's refuses the move before anything is copied or set aside", async t => {
  const s = await darkmemDocs(t);
  assert.equal((await s.pull()).code, 0);
  write(path.join(s.docsRoot, "specs", "a.md"), "# A corrupted\n");
  const result = await s.reconcile();
  assert.equal(result.code, 1, result.stdout + result.stderr);
  assert.match(result.stdout, /^darkmem-sync reconcile: documents stay darkmem \(configured local\): the mirror does not match darkmem; nothing was copied$/m);
  assert.ok(result.stdout.includes("  superpowers/specs/a.md: the mirror's copy differs from darkmem's; push or discard it first\n"), result.stdout);
  assert.equal(fs.existsSync(path.join(s.repo, "docs", "forge")), false);
  assert.equal(read(path.join(s.docsRoot, "specs", "a.md")), "# A corrupted\n");
  assert.deepEqual(fs.readdirSync(s.mirror).filter(name => name.startsWith("superpowers-moved-")), []);
  assert.deepEqual(s.stores(), { documents: "darkmem", progress: "local" });
});

test("a completed.md the pull changes is checked again before anything is copied", async t => {
  const s = await darkmemDocs(t);
  await s.seed.putDocument({ project: "proj", uri: "superpowers/plans/completed.md", content: "- `docs/forge/plans/p.md`\n" });
  assert.equal((await s.pull()).code, 0);
  write(at(s.repo, ".forge/sdd/p/progress.md"), LEDGER("docs/forge/plans/p.md"));
  await s.seed.putDocument({ project: "proj", uri: "superpowers/plans/completed.md", content: "- `docs/forge/plans/other.md`\n" });
  const result = await s.reconcile();
  assert.equal(result.code, 1, result.stdout + result.stderr);
  assert.match(result.stdout, /^darkmem-sync reconcile: documents stay darkmem \(configured local\): a plan is in progress: docs\/forge\/plans\/p\.md$/m);
  assert.equal(fs.existsSync(path.join(s.repo, "docs", "forge")), false);
  assert.equal(fs.existsSync(s.docsRoot), true);
  assert.deepEqual(s.stores(), { documents: "darkmem", progress: "local" });
});
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `timeout 300 node --test plugins/dr-forge/tests/darkmem-sync/reconcile.test.mjs`
Expected: FAIL — the new tests see `documents stay darkmem (configured local): no move from darkmem to local`.

- [ ] **Step 3: Write the move**

Replace the mirror import line with

```js
import {
  DOC_PREFIX, caseGroups, decodeUtf8, isArchiveUri, ledgerPlanPath, listDocumentFiles, sha256, uriFamily, uriProblem, utcStamp,
} from "./darkmem-mirror.mjs";
```

Add the entry to `MOVES`:

```js
const MOVES = {
  "documents:darkmem": documentsToDarkmem,
  "documents:local": documentsToLocal,
};
```

Add after `documentsToDarkmem`:

```js
// Documents, darkmem -> repository (spec §4): the mirror, brought up to
// darkmem and matching darkmem's hashes, is copied into docs/forge untracked;
// darkmem keeps its copy, and the mirror tree is set aside so a later move
// back cannot meet stale files. A legacy docs/superpowers is left alone:
// docs/forge outranks it once it exists.
async function documentsToLocal(context) {
  const { cfg, client, state, persist } = context;
  const mirror = mirrorRoots(cfg, "documents");
  const pulled = pullReport();
  await pullDocuments({ ...context, roots: mirror, report: pulled });
  if (pulled.conflicts.length || pulled.failures.length) {
    return { moved: false, reason: "the mirror could not be brought up to darkmem", details: [...pulled.conflicts, ...pulled.failures] };
  }
  const busy = inProgressReason(context);
  if (busy) return { moved: false, ...busy };
  const remote = new Map((await client.manifest(cfg.project, DOC_PREFIX))
    .filter(item => uriFamily(item.uri) === "documents" && !isArchiveUri(item.uri))
    .map(item => [item.uri, item.content_hash]));
  const target = path.join(cfg.repoRoot, "docs", "forge");
  // A file under the docs root's handoff/ or archive/ has uri null: never synced, not carried.
  const files = listDocumentFiles(mirror).filter(item => item.uri).map(({ file, uri }) => {
    const dest = path.join(target, path.relative(mirror.docsRoot, file));
    return { file, uri, dest, name: slash(path.relative(cfg.repoRoot, dest)), hash: fileHash(file) };
  });
  // Only what darkmem holds is carried, so an unpushed or damaged mirror
  // copy never lands in the repository as if it were darkmem's.
  const unverified = files.filter(item => remote.get(item.uri) !== item.hash).map(item => (remote.has(item.uri)
    ? `${item.uri}: the mirror's copy differs from darkmem's; push or discard it first`
    : `${item.uri}: not on darkmem; push or discard it first`));
  if (unverified.length) return { moved: false, reason: "the mirror does not match darkmem; nothing was copied", details: unverified };
  // A killed earlier run may have copied some files: equal ones are fine.
  const differing = files
    .filter(({ file, dest }) => fs.existsSync(dest) && !fs.readFileSync(dest).equals(fs.readFileSync(file)))
    .map(({ name }) => `${name}: already exists with different content`);
  if (differing.length) return { moved: false, reason: "docs/forge already holds different copies; nothing was copied", details: differing };
  for (const { file, dest } of files) {
    fs.mkdirSync(path.dirname(dest), { recursive: true });
    fs.copyFileSync(file, dest);
  }
  const mismatched = files.filter(({ dest, hash }) => fileHash(dest) !== hash).map(({ name }) => `${name}: differs from the mirror's copy`);
  if (mismatched.length) return { moved: false, reason: "a copied file differs from the mirror's", details: mismatched };
  for (const uri of Object.keys(state.documents)) {
    if (uriFamily(uri) === "documents") delete state.documents[uri];
  }
  persist();
  if (fs.existsSync(mirror.docsRoot)) fs.renameSync(mirror.docsRoot, path.join(cfg.mirror, `superpowers-moved-${utcStamp()}`));
  const details = [`copied ${files.length} files into docs/forge, untracked; commit them`];
  const legacy = path.join(cfg.repoRoot, "docs", "superpowers");
  if (fs.existsSync(legacy)) details.push(`${legacy} is a legacy docs directory and is not read; documents now live in docs/forge`);
  // A repository moved under the parent spec's §6 ignored its docs directory.
  const ignored = runGit(cfg.repoRoot, ["check-ignore", "--stdin"], files.map(({ name }) => name).join("\n"));
  for (const name of ignored.stdout.split("\n").filter(Boolean)) details.push(`${name}: ignored by git, so a commit would leave it out`);
  let attributes = "";
  try {
    attributes = fs.readFileSync(path.join(cfg.repoRoot, ".gitattributes"), "utf8");
  } catch {
    // No .gitattributes; nothing names the old prefix.
  }
  attributes.split(/\r?\n/).forEach((line, index) => {
    if (line.includes("docs/superpowers/")) details.push(`.gitattributes line ${index + 1} still names docs/superpowers/: ${line}`);
  });
  return { moved: true, details };
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `timeout 300 node --test plugins/dr-forge/tests/darkmem-sync/reconcile.test.mjs`
Expected: PASS.

Run: `timeout 900 bash plugins/dr-forge/tests/darkmem-sync.test.sh`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-forge/scripts/lib/darkmem-reconcile.mjs plugins/dr-forge/tests/darkmem-sync/reconcile.test.mjs
git commit -m "feat(dr-forge): move documents back from darkmem"
```

### Task 18: Gather and check local progress for a move

**Files:**
- Create: `scripts/lib/darkmem-progress-move.mjs`
- Modify: `scripts/lib/darkmem-import.mjs:49` (export `importLedger`)
- Test: `tests/darkmem-sync/reconcile-progress.test.mjs` (create)

**Interfaces:**
- Consumes: existing `forgeDir` (`darkmem-config.mjs`), `ledgerFiles`, `listDocumentFiles`, `unsupportedPlanDirs`, `decodeUtf8`, `sha256`, `DOC_PREFIX` (`darkmem-mirror.mjs`), `remoteLedger` (`darkmem-pull.mjs`).
- Produces: C9 (`importLedger` exported); C12's module file, `gatherLocalProgress`, `checkProgressTargets` and `local`, and the test file's `LEDGER` and `LATEST`.

**Items:** 5

**Implementer:** dr-superpowers:impl-sonnet-medium
**Executor:** codex gpt-6.1-sol / high
**Evaluation:** files 1 - spec 0 - coupling 2 - risk 1 = 4

- [ ] **Step 1: Write the failing tests**

Create `tests/darkmem-sync/reconcile-progress.test.mjs` (the later progress tasks append to it, so it imports what they use too):

```js
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import test from "node:test";
import { createClient } from "../../scripts/lib/darkmem-client.mjs";
import { checkProgressTargets, gatherLocalProgress } from "../../scripts/lib/darkmem-progress-move.mjs";
import { STUB_KEY, sha, startStub } from "./stub-server.mjs";
import { git, makeHome, makeRepo, read, run, scratch, write } from "./helpers.mjs";

const LEDGER = name => `# SDD ledger — plan: docs/forge/plans/${name}.md\nTask 1: complete (commits aaaa..bbbb)\n`;
const LATEST = "## State\n- Plan: `docs/forge/plans/p1.md`\n";

function repoWithWorktree() {
  const repo = makeRepo();
  const worktree = path.join(scratch("dms-wt-"), "side");
  git(repo, "worktree", "add", "-q", "-b", "side", worktree);
  return { repo, worktree };
}

test("progress sources come from every checkout, and agreeing copies are one source", () => {
  const { repo, worktree } = repoWithWorktree();
  write(path.join(repo, ".forge", "sdd", "p1", "progress.md"), LEDGER("p1"));
  write(path.join(repo, ".forge", "sdd", "p1", "handoff.md"), "# Handoff p1\n");
  write(path.join(repo, ".forge", "sdd", "p1", "brief.md"), "a workspace file, not progress\n");
  write(path.join(repo, ".forge", "handoff", "latest.md"), LATEST);
  write(path.join(worktree, ".forge", "sdd", "p1", "progress.md"), LEDGER("p1"));
  write(path.join(worktree, ".forge", "sdd", "p2", "progress.md"), LEDGER("p2"));
  write(path.join(worktree, ".forge", "handoff", "latest.md"), "a linked worktree's latest.md is not progress\n");
  const { problems, files, sources } = gatherLocalProgress({ repoRoot: repo });
  assert.deepEqual(problems, []);
  assert.deepEqual(sources.map(item => item.rel).sort(), ["handoff/latest.md", "sdd/p1/handoff.md", "sdd/p1/progress.md", "sdd/p2/progress.md"]);
  assert.equal(files.length, 5);
  assert.equal(sources.find(item => item.kind === "handoff").uri, "superpowers/handoff/p1.md");
});

test("an unusable plan directory, unreadable text and disagreeing copies are all problems", () => {
  const { repo, worktree } = repoWithWorktree();
  write(path.join(repo, ".forge", "sdd", "bad name", "handoff.md"), "# note\n");
  write(path.join(repo, ".forge", "sdd", "p1", "progress.md"), LEDGER("p1"));
  write(path.join(worktree, ".forge", "sdd", "p1", "progress.md"), `${LEDGER("p1")}Task 2: complete (commits cccc..dddd)\n`);
  write(path.join(repo, ".forge", "sdd", "p3", "handoff.md"), Buffer.from([0xff, 0xfe]));
  const { problems } = gatherLocalProgress({ repoRoot: repo });
  assert.equal(problems.length, 3, problems.join("\n"));
  assert.match(problems.join("\n"), /bad name: not a usable workstream key$/m);
  assert.match(problems.join("\n"), /^sdd\/p1\/progress\.md: .+ and .+ differ$/m);
  assert.match(problems.join("\n"), /p3[\\/]handoff\.md: empty or not UTF-8 text$/m);
});

test("an equal ledger on darkmem is already filed; a different ledger, handoff note or mirror copy is a problem", async t => {
  const stub = await startStub();
  t.after(() => stub.close());
  const client = createClient({ url: stub.url, apiKey: STUB_KEY, runKey: "seed" });
  const repo = makeRepo();
  const mirror = scratch("dms-mirror-");
  write(path.join(repo, ".forge", "sdd", "p1", "progress.md"), LEDGER("p1"));
  write(path.join(repo, ".forge", "sdd", "p2", "progress.md"), LEDGER("p2"));
  write(path.join(repo, ".forge", "sdd", "p2", "handoff.md"), "# local note\n");
  write(path.join(repo, ".forge", "handoff", "latest.md"), "local latest\n");
  const { workstream } = await client.append({ project: "proj", workstream: "p1", entries: [{ kind: "ledger", body: LEDGER("p1") }] });
  await client.append({ project: "proj", workstream: "p2", entries: [{ kind: "ledger", body: "# SDD ledger — plan: elsewhere\n" }] });
  await client.putDocument({ project: "proj", uri: "superpowers/handoff/p2.md", content: "# darkmem note\n" });
  write(path.join(mirror, "work", "handoff", "latest.md"), "mirror latest\n");
  const { sources } = gatherLocalProgress({ repoRoot: repo });
  const { problems, filed } = await checkProgressTargets({ cfg: { project: "proj", mirror }, client }, sources);
  assert.deepEqual([...filed], [["p1", workstream.id]]);
  assert.equal(problems.length, 3, problems.join("\n"));
  assert.match(problems.join("\n"), /^sdd\/p2\/progress\.md: darkmem already holds a different ledger for workstream p2$/m);
  assert.match(problems.join("\n"), /^superpowers\/handoff\/p2\.md: darkmem already holds a different handoff note$/m);
  assert.match(problems.join("\n"), /work[\\/]handoff[\\/]latest\.md: the mirror already holds a different copy of handoff\/latest\.md$/m);
});
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `timeout 300 node --test plugins/dr-forge/tests/darkmem-sync/reconcile-progress.test.mjs`
Expected: FAIL with `ERR_MODULE_NOT_FOUND` naming `darkmem-progress-move.mjs`.

- [ ] **Step 3: Write the implementation**

In `scripts/lib/darkmem-import.mjs` line 49, change `async function importLedger({ cfg, client, report }, roots, ledger) {` to:

```js
export async function importLedger({ cfg, client, report }, roots, ledger) {
```

Create `scripts/lib/darkmem-progress-move.mjs`:

```js
// The progress family's moves (darkmem store options spec §4): every
// checkout's plan ledgers and handoff notes, and the primary checkout's
// latest.md, into darkmem; and the mirror's back into the primary checkout.
// Nothing is deleted: a source is moved to a dated backup only after its
// copy reads back identical.
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { forgeDir } from "./darkmem-config.mjs";
import { DOC_PREFIX, decodeUtf8, ledgerFiles, listDocumentFiles, sha256, unsupportedPlanDirs } from "./darkmem-mirror.mjs";
import { remoteLedger } from "./darkmem-pull.mjs";

const local = (base, rel) => path.join(base, ...rel.split("/"));

// The primary checkout first, then every linked worktree git lists.
function checkouts(repoRoot) {
  const result = spawnSync("git", ["-C", repoRoot, "worktree", "list", "--porcelain"], { encoding: "utf8", timeout: 10000 });
  if (result.status !== 0) return { problem: `git worktree list failed in ${repoRoot}: ${(result.stderr || result.error?.message || "").trim()}` };
  const listed = result.stdout.split(/\r?\n/).filter(line => line.startsWith("worktree ")).map(line => line.slice("worktree ".length));
  return { dirs: [repoRoot, ...listed.filter(dir => path.resolve(dir) !== path.resolve(repoRoot))] };
}

// Every progress file the checkouts hold, and the sources a move carries: one
// per mirror path, since a worktree cut while a ledger existed holds a copy of
// it. Copies that differ, a plan directory that is not a workstream key, and
// empty or non-UTF-8 text are problems; every one is collected.
export function gatherLocalProgress(cfg) {
  const listed = checkouts(cfg.repoRoot);
  if (listed.problem) return { problems: [listed.problem], files: [], sources: [] };
  const problems = [];
  const files = [];
  for (const checkout of listed.dirs) {
    const stateDir = forgeDir("state", checkout);
    for (const dir of unsupportedPlanDirs(stateDir)) problems.push(`${dir}: not a usable workstream key`);
    for (const { slug, file } of ledgerFiles(stateDir)) files.push({ kind: "ledger", slug, file, stateDir, rel: `sdd/${slug}/progress.md` });
    for (const { file, uri } of listDocumentFiles({ workRoot: stateDir, families: { documents: false, progress: true } })) {
      const slug = path.basename(path.dirname(file));
      files.push({ kind: "handoff", slug, uri, file, stateDir, rel: `sdd/${slug}/handoff.md` });
    }
  }
  const primaryState = forgeDir("state", cfg.repoRoot);
  const latest = path.join(primaryState, "handoff", "latest.md");
  if (fs.existsSync(latest)) files.push({ kind: "latest", file: latest, stateDir: primaryState, rel: "handoff/latest.md" });
  const sources = [];
  const byRel = new Map();
  for (const item of files) {
    item.buffer = fs.readFileSync(item.file);
    if (!decodeUtf8(item.buffer)) {
      problems.push(`${item.file}: empty or not UTF-8 text`);
      continue;
    }
    const seen = byRel.get(item.rel);
    if (!seen) {
      byRel.set(item.rel, item);
      sources.push(item);
    } else if (!seen.buffer.equals(item.buffer)) {
      problems.push(`${item.rel}: ${seen.file} and ${item.file} differ`);
    }
  }
  return { problems, files, sources };
}

// What darkmem and the mirror already hold at each source's place. A ledger
// darkmem holds byte for byte is already filed, so a move stopped part-way
// runs again; any other existing copy that differs is a problem, so nothing
// is overwritten.
export async function checkProgressTargets({ cfg, client }, sources) {
  const problems = [];
  const filed = new Map();
  for (const item of sources) {
    const target = local(path.join(cfg.mirror, "work"), item.rel);
    if (fs.existsSync(target) && !fs.readFileSync(target).equals(item.buffer)) {
      problems.push(`${target}: the mirror already holds a different copy of ${item.rel}`);
    }
  }
  const notes = new Map((await client.manifest(cfg.project, `${DOC_PREFIX}/handoff`)).map(doc => [doc.uri, doc.content_hash]));
  for (const item of sources) {
    if (item.kind === "handoff") {
      const hash = notes.get(item.uri);
      if (hash !== undefined && hash !== sha256(item.buffer)) problems.push(`${item.uri}: darkmem already holds a different handoff note`);
    } else if (item.kind === "ledger") {
      const existing = await client.resume(cfg.project, item.slug);
      if (!existing) continue;
      const { text } = await remoteLedger(client, existing.workstream.id);
      if (Buffer.from(text, "utf8").equals(item.buffer)) filed.set(item.slug, existing.workstream.id);
      else problems.push(`${item.rel}: darkmem already holds a different ledger for workstream ${item.slug}`);
    }
  }
  return { problems, filed };
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `timeout 300 node --test plugins/dr-forge/tests/darkmem-sync/reconcile-progress.test.mjs`
Expected: PASS, 3 tests. Then `timeout 300 node --test plugins/dr-forge/tests/darkmem-sync/import.test.mjs` — PASS (the export changes nothing else).

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-forge/scripts/lib/darkmem-progress-move.mjs plugins/dr-forge/scripts/lib/darkmem-import.mjs plugins/dr-forge/tests/darkmem-sync/reconcile-progress.test.mjs
git commit -m "feat(dr-forge): gather progress for a store move"
```

### Task 19: Move progress from the checkouts into darkmem

**Files:**
- Modify: `scripts/lib/darkmem-progress-move.mjs` (imports; append `refuse`, `darkmemRefusal`, `scratchReport`, `progressToDarkmem`)
- Modify: `scripts/lib/darkmem-reconcile.mjs` (one import, one `MOVES` entry)
- Test: `tests/darkmem-sync/reconcile-progress.test.mjs` (append)

**Interfaces:**
- Consumes: C7 (`MOVES` table, move result shape, the core's common refusals, `writeApplied` on success, two-space detail lines, `report.refused` → exit 1, `refreshContext` after each successful move, so a move reads `context.cfg` when it is called), C9 (`importLedger`), C3 (`utcStamp`), C12 (`gatherLocalProgress`, `checkProgressTargets`, `local`, `LEDGER`, `LATEST`).
- Produces: `progressToDarkmem(context)` registered as `MOVES["progress:darkmem"]`; C12's `refuse`, `darkmemRefusal`, `scratchReport`, `checkoutRoots`, `newestCheckpoint`, and the test file's `setup` and `movedAside`.

**Items:** 5

**Implementer:** dr-superpowers:impl-opus-high
**Evaluation:** files 1 - spec 0 - coupling 2 - risk 3 = 6

- [ ] **Step 1: Write the failing tests**

Append to `tests/darkmem-sync/reconcile-progress.test.mjs`:

```js
// A mapped repository whose only pending family is progress, moving toward
// `target`. Plans p1, p2 and p4 are recorded in completed.md, committed before
// the linked worktree is cut, so no ledger counts as in progress in either
// checkout; p4's plan file is written by the test that needs it.
async function setup(t, target) {
  const stub = await startStub();
  t.after(() => stub.close());
  const repo = makeRepo();
  write(path.join(repo, "docs", "forge", "plans", "p1.md"), "# p1\n");
  write(path.join(repo, "docs", "forge", "plans", "p2.md"), "# p2\n");
  write(path.join(repo, "docs", "forge", "plans", "completed.md"), "- `docs/forge/plans/p1.md`\n- `docs/forge/plans/p2.md`\n- `docs/forge/plans/p4.md`\n");
  git(repo, "add", "docs");
  git(repo, "commit", "-q", "-m", "plans");
  const worktree = path.join(scratch("dms-wt-"), "side");
  git(repo, "worktree", "add", "-q", "-b", "side", worktree);
  const home = makeHome({
    repo,
    config: { darkmem: { url: stub.url, api_key_env: "DARKMEM_API_KEY", repos: { [repo]: { project: "proj", documentStore: "local", progressSource: target } } } },
    stores: { documents: "local", progress: target === "darkmem" ? "local" : "darkmem" },
  });
  const seed = createClient({ url: stub.url, apiKey: STUB_KEY, runKey: "seed" });
  return {
    stub, repo, worktree, ...home, seed,
    state: () => JSON.parse(fs.readFileSync(path.join(home.mirror, ".sync-state.json"), "utf8")),
    stores: () => JSON.parse(fs.readFileSync(path.join(home.home, ".dr-forge", "stores.json"), "utf8"))[repo],
    reconcile: () => run(["reconcile"], { cwd: repo, env: home.env }),
  };
}

const movedAside = dir => (fs.existsSync(path.join(dir, ".forge")) ? fs.readdirSync(path.join(dir, ".forge")).filter(name => /^moved-\d{8}T\d{6}Z$/.test(name)) : []);

test("progress moves into darkmem from every checkout, and a second run does nothing", async t => {
  const s = await setup(t, "darkmem");
  write(path.join(s.repo, ".forge", "sdd", "p1", "progress.md"), LEDGER("p1"));
  write(path.join(s.repo, ".forge", "sdd", "p1", "handoff.md"), "# Handoff p1\n");
  write(path.join(s.repo, ".forge", "sdd", "p1", "brief.md"), "workspace\n");
  write(path.join(s.repo, ".forge", "handoff", "latest.md"), LATEST);
  write(path.join(s.worktree, ".forge", "sdd", "p1", "progress.md"), LEDGER("p1"));
  write(path.join(s.worktree, ".forge", "sdd", "p2", "progress.md"), LEDGER("p2"));
  const result = await s.reconcile();
  assert.equal(result.code, 0, result.stdout + result.stderr);
  assert.match(result.stdout, /^darkmem-sync reconcile: progress moved to darkmem$/m);
  for (const key of ["p1", "p2"]) {
    const ws = s.stub.db.workstreams.find(w => w.key === key);
    assert.equal(ws.state, "closed");
    const ledger = ws.entries.filter(e => e.kind === "ledger");
    assert.equal(ledger.map(e => e.body).join(""), LEDGER(key));
    assert.equal(read(path.join(s.workRoot, "sdd", key, "progress.md")), LEDGER(key));
    assert.deepEqual(s.state().ledgers[key], { offset: Buffer.byteLength(LEDGER(key)), prefix: sha(LEDGER(key)), lastSeq: ledger.at(-1).seq });
  }
  assert.equal(s.stub.db.documents.get("proj\u0000superpowers/handoff/p1.md").content, "# Handoff p1\n");
  assert.equal(read(path.join(s.workRoot, "sdd", "p1", "handoff.md")), "# Handoff p1\n");
  assert.equal(s.state().documents["superpowers/handoff/p1.md"], sha("# Handoff p1\n"));
  assert.equal(read(path.join(s.workRoot, "handoff", "latest.md")), LATEST);
  const p1 = s.stub.db.workstreams.find(w => w.key === "p1");
  const [checkpoint, ...more] = p1.entries.filter(e => e.kind === "checkpoint");
  assert.equal(checkpoint.body, LATEST, "latest.md is filed as a checkpoint of the plan it names");
  assert.deepEqual(more, []);
  assert.equal(p1.state, "closed", "a closed workstream is closed again after its checkpoint");
  assert.equal(s.state().checkpoint, sha(LATEST));
  assert.equal(s.state().checkpointAt, checkpoint.created_at);
  assert.match(result.stdout, /^ {2}latest\.md filed as a checkpoint of p1$/m);
  assert.deepEqual(s.stores(), { documents: "local", progress: "darkmem" });
  const [primaryAside] = movedAside(s.repo);
  assert.equal(read(path.join(s.repo, ".forge", primaryAside, "sdd", "p1", "progress.md")), LEDGER("p1"));
  assert.equal(read(path.join(s.repo, ".forge", primaryAside, "sdd", "p1", "handoff.md")), "# Handoff p1\n");
  assert.equal(read(path.join(s.repo, ".forge", primaryAside, "handoff", "latest.md")), LATEST);
  assert.equal(fs.existsSync(path.join(s.repo, ".forge", "sdd", "p1", "progress.md")), false);
  assert.equal(read(path.join(s.repo, ".forge", "sdd", "p1", "brief.md")), "workspace\n", "workspaces stay");
  const [sideAside] = movedAside(s.worktree);
  assert.equal(read(path.join(s.worktree, ".forge", sideAside, "sdd", "p2", "progress.md")), LEDGER("p2"));
  assert.equal(fs.existsSync(path.join(s.worktree, ".forge", "sdd", "p1", "progress.md")), false);
  const again = await s.reconcile();
  assert.equal(again.code, 0, again.stdout + again.stderr);
  assert.equal(again.stdout, "");
});

test("a ledger darkmem already holds unchanged is not filed again, so a stopped move can run again", async t => {
  const s = await setup(t, "darkmem");
  write(path.join(s.repo, ".forge", "sdd", "p1", "progress.md"), LEDGER("p1"));
  await s.seed.append({ project: "proj", workstream: "p1", entries: [{ kind: "ledger", body: LEDGER("p1") }] });
  const result = await s.reconcile();
  assert.equal(result.code, 0, result.stdout + result.stderr);
  assert.match(result.stdout, /^darkmem-sync reconcile: progress moved to darkmem$/m);
  const ws = s.stub.db.workstreams.find(w => w.key === "p1");
  assert.equal(ws.entries.length, 1);
  assert.equal(ws.state, "closed");
  assert.equal(s.state().ledgers.p1.lastSeq, ws.entries[0].seq);
});

test("a latest.md that names no plan is copied unsent, behind darkmem's newest checkpoint", async t => {
  const s = await setup(t, "darkmem");
  const { workstream } = await s.seed.append({ project: "proj", workstream: "p9", entries: [{ kind: "checkpoint", body: "## State\n- Plan: `docs/forge/plans/p9.md`\n" }] });
  write(path.join(s.repo, ".forge", "handoff", "latest.md"), "a note with no State section\n");
  const result = await s.reconcile();
  assert.equal(result.code, 0, result.stdout + result.stderr);
  assert.match(result.stdout, /^darkmem-sync reconcile: progress moved to darkmem$/m);
  assert.match(result.stdout, /^ {2}latest\.md names no plan or draft; copied to the mirror, not sent$/m);
  assert.equal(read(path.join(s.workRoot, "handoff", "latest.md")), "a note with no State section\n");
  assert.equal(s.state().checkpoint, sha("a note with no State section\n"));
  assert.equal(s.state().checkpointAt, workstream.last_entry_at);
  assert.equal(s.stub.db.workstreams.flatMap(w => w.entries).filter(e => e.kind === "checkpoint").length, 1);
});

test("a ledger's workstream properties read its plan in its own checkout", async t => {
  const s = await setup(t, "darkmem");
  write(path.join(s.worktree, "docs", "forge", "plans", "p4.md"), "# p4\n\n**Spec:** `docs/forge/specs/s4.md`\n");
  write(path.join(s.worktree, ".forge", "sdd", "p4", "progress.md"), LEDGER("p4"));
  const result = await s.reconcile();
  assert.equal(result.code, 0, result.stdout + result.stderr);
  const { plan_uri, spec_uri } = s.stub.db.workstreams.find(w => w.key === "p4").properties;
  assert.deepEqual({ plan_uri, spec_uri }, { plan_uri: "superpowers/plans/p4.md", spec_uri: "superpowers/specs/s4.md" });
});

test("documents and progress both move to darkmem in one run, and the ledger's properties read the plan from the mirror", async t => {
  const s = await setup(t, "darkmem");
  write(path.join(s.repo, "docs", "forge", "plans", "p1.md"), "# p1\n\n**Spec:** `docs/forge/specs/s1.md`\n");
  write(path.join(s.repo, "docs", "forge", "specs", "s1.md"), "# s1\n");
  git(s.repo, "add", "docs");
  git(s.repo, "commit", "-q", "-m", "spec");
  write(path.join(s.home, ".dr-forge", "config.json"), JSON.stringify({ darkmem: { url: s.stub.url, api_key_env: "DARKMEM_API_KEY", repos: { [s.repo]: { project: "proj" } } } }));
  write(path.join(s.repo, ".forge", "sdd", "p1", "progress.md"), LEDGER("p1"));
  const result = await s.reconcile();
  assert.equal(result.code, 0, result.stdout + result.stderr);
  assert.match(result.stdout, /^darkmem-sync reconcile: documents moved to darkmem$/m);
  assert.match(result.stdout, /^darkmem-sync reconcile: progress moved to darkmem$/m);
  assert.equal(fs.existsSync(path.join(s.repo, "docs", "forge", "plans", "p1.md")), false, "the documents move ran first and removed the checkout's copy");
  const { plan_uri, spec_uri } = s.stub.db.workstreams.find(w => w.key === "p1").properties;
  assert.deepEqual({ plan_uri, spec_uri }, { plan_uri: "superpowers/plans/p1.md", spec_uri: "superpowers/specs/s1.md" });
  assert.deepEqual(s.stores(), { documents: "darkmem", progress: "darkmem" });
});

const UP_REFUSALS = [
  {
    name: "copies of one ledger that differ between checkouts",
    plant: async s => {
      write(path.join(s.repo, ".forge", "sdd", "p1", "progress.md"), LEDGER("p1"));
      write(path.join(s.worktree, ".forge", "sdd", "p1", "progress.md"), `${LEDGER("p1")}Task 2: complete (commits cccc..dddd)\n`);
    },
    detail: /^ {2}sdd\/p1\/progress\.md: .+ and .+ differ$/m,
  },
  {
    name: "a plan directory that is not a workstream key",
    plant: async s => write(path.join(s.repo, ".forge", "sdd", "bad name", "handoff.md"), "# note\n"),
    detail: /^ {2}.+bad name: not a usable workstream key$/m,
  },
  {
    name: "a different ledger on darkmem",
    plant: async s => {
      write(path.join(s.repo, ".forge", "sdd", "p1", "progress.md"), LEDGER("p1"));
      await s.seed.append({ project: "proj", workstream: "p1", entries: [{ kind: "ledger", body: "# SDD ledger — plan: elsewhere\n" }] });
    },
    detail: /^ {2}sdd\/p1\/progress\.md: darkmem already holds a different ledger for workstream p1$/m,
  },
  {
    name: "a different copy in the mirror",
    plant: async s => {
      write(path.join(s.repo, ".forge", "sdd", "p1", "progress.md"), LEDGER("p1"));
      write(path.join(s.workRoot, "sdd", "p1", "progress.md"), "other\n");
    },
    detail: /the mirror already holds a different copy of sdd\/p1\/progress\.md$/m,
  },
];

for (const row of UP_REFUSALS) {
  test(`progress stays local on ${row.name}, and nothing is sent or moved`, async t => {
    const s = await setup(t, "darkmem");
    await row.plant(s);
    const before = s.stub.db.requests.length;
    const result = await s.reconcile();
    assert.equal(result.code, 1, result.stdout + result.stderr);
    assert.match(result.stdout, /^darkmem-sync reconcile: progress stay local \(configured darkmem\): /m);
    assert.match(result.stdout, row.detail);
    assert.deepEqual(s.stub.db.requests.slice(before).filter(r => r.method !== "GET").map(r => `${r.method} ${r.path}`), []);
    assert.equal(s.stores().progress, "local");
    assert.deepEqual(movedAside(s.repo), []);
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `timeout 300 node --test plugins/dr-forge/tests/darkmem-sync/reconcile-progress.test.mjs`
Expected: FAIL — the five new success tests print `darkmem-sync reconcile: progress stay local (configured darkmem): no move from local to darkmem` instead of `progress moved to darkmem`; the refusal rows fail on their detail line.

- [ ] **Step 3: Write the implementation**

In `scripts/lib/darkmem-progress-move.mjs`, replace the import block with:

```js
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { HttpError, TransportError } from "./darkmem-client.mjs";
import { forgeDir } from "./darkmem-config.mjs";
import { importLedger } from "./darkmem-import.mjs";
import {
  DOC_PREFIX, checkpointTarget, decodeUtf8, isoMicros, ledgerFiles, listDocumentFiles, propertiesFor, sha256, unsupportedPlanDirs,
  utcStamp, writeFileAtomic,
} from "./darkmem-mirror.mjs";
import { remoteLedger } from "./darkmem-pull.mjs";
```

Append to the end of the same file:

```js
const refuse = (reason, details = []) => ({ moved: false, reason, details });

// An answer from darkmem, or none, ends a move as a refusal; anything else is
// a bug and propagates.
function darkmemRefusal(error, details = []) {
  if (error instanceof TransportError) return refuse(`darkmem is unreachable: ${error.message}`, details);
  if (error instanceof HttpError) return refuse(`darkmem answered ${error.status}: ${error.detail}; nothing was moved locally`, details);
  throw error;
}

// The report a move hands the sync code it reuses, so that code's lines
// become the move's details rather than the command's.
const scratchReport = () => ({ conflicts: [], failures: [], notes: [], counts: { workstreams: 0, documents: 0, ledgers: 0, checkpoints: 0 }, partial: false });

// The roots a checkout's progress reads its plans through: that checkout's
// own docs directory while documents are local, since a plan may exist only
// on its branch; the mirror's while they are darkmem.
const checkoutRoots = (cfg, stateDir) => ({
  docsRoot: cfg.documents.applied === "darkmem" ? cfg.documents.root : forgeDir("docs", path.dirname(stateDir)),
  workRoot: stateDir,
  worktreeRoot: path.dirname(stateDir),
});

// The newest checkpoint darkmem holds across `workstreams`, or null.
async function newestCheckpoint({ cfg, client }, workstreams) {
  let newest = null;
  for (const ws of workstreams) {
    const checkpoint = (await client.resume(cfg.project, ws.key))?.checkpoint;
    if (checkpoint && (!newest || isoMicros(checkpoint.created_at) > isoMicros(newest.created_at))) newest = checkpoint;
  }
  return newest;
}

// latest.md becomes a checkpoint of the plan or draft it names, so other
// machines receive it; a workstream that was closed is closed again. One that
// names neither is copied unsent, dated at darkmem's newest checkpoint so a
// pull only replaces it with a newer one. Answers { hash, at, detail }, or
// { problem } when darkmem reads it back different.
async function fileLatest(context, item) {
  const { cfg, client } = context;
  const body = decodeUtf8(item.buffer);
  const hash = sha256(item.buffer);
  const target = checkpointTarget(body);
  if (!target) {
    const newest = await newestCheckpoint(context, await client.workstreams(cfg.project));
    return { hash, at: newest?.created_at ?? null, detail: "latest.md names no plan or draft; copied to the mirror, not sent" };
  }
  const before = await client.resume(cfg.project, target.slug);
  let at = before?.checkpoint && sha256(Buffer.from(before.checkpoint.body, "utf8")) === hash ? before.checkpoint.created_at : null;
  if (!at) {
    const properties = propertiesFor(checkoutRoots(cfg, item.stateDir), target.slug, target.path);
    const answer = await client.append({ project: cfg.project, workstream: target.slug, properties, entries: [{ kind: "checkpoint", body }] });
    at = answer.workstream.last_entry_at;
  }
  if (before?.workstream.state === "closed") {
    const after = await client.resume(cfg.project, target.slug);
    if (after.workstream.state !== "closed") await client.updateWorkstream(after.workstream.id, { state: "closed", retain: true });
  }
  const filed = (await client.resume(cfg.project, target.slug))?.checkpoint;
  if (!filed || sha256(Buffer.from(filed.body, "utf8")) !== hash) return { problem: "handoff/latest.md: darkmem's checkpoint reads back different" };
  return { hash, at, detail: `latest.md filed as a checkpoint of ${target.slug}` };
}

export async function progressToDarkmem(context) {
  const { cfg, client, state, persist } = context;
  const { problems, files, sources } = gatherLocalProgress(cfg);
  if (problems.length) return refuse("the checkouts hold progress the move cannot carry", problems);
  const report = scratchReport();
  const ids = new Map();
  const lastSeqs = new Map();
  let latest = null;
  try {
    const checked = await checkProgressTargets(context, sources);
    if (checked.problems.length) return refuse("darkmem or the mirror already holds different progress", checked.problems);
    // Every ledger here belongs to a finished plan (reconcile refuses while
    // one is in progress), so one a stopped move filed is closed like the rest.
    for (const [slug, id] of checked.filed) {
      ids.set(slug, id);
      await client.updateWorkstream(id, { state: "closed", retain: true });
    }
    for (const item of sources) {
      if (item.kind === "ledger" && !ids.has(item.slug)) {
        const ledger = { slug: item.slug, text: decodeUtf8(item.buffer), mtime: fs.statSync(item.file).mtime.toISOString(), id: null };
        await importLedger({ ...context, report }, checkoutRoots(cfg, item.stateDir), ledger);
        if (ledger.id) ids.set(item.slug, ledger.id);
      } else if (item.kind === "handoff") {
        await client.putDocument({ project: cfg.project, uri: item.uri, content: decodeUtf8(item.buffer) });
      }
    }
    if (report.failures.length) return refuse("darkmem refused part of the progress; nothing was moved locally", report.failures);
    const differing = [];
    for (const item of sources) {
      if (item.kind === "ledger") {
        const { text, lastSeq } = await remoteLedger(client, ids.get(item.slug));
        lastSeqs.set(item.slug, lastSeq);
        if (!Buffer.from(text, "utf8").equals(item.buffer)) differing.push(`${item.rel}: darkmem's copy reads back different`);
      } else if (item.kind === "handoff" && (await client.getDocument(cfg.project, item.uri)).content_hash !== sha256(item.buffer)) {
        differing.push(`${item.uri}: darkmem's copy reads back different`);
      }
    }
    if (differing.length) return refuse("a read-back of darkmem's copies differs; nothing was moved locally", differing);
    const latestItem = sources.find(item => item.kind === "latest");
    if (latestItem) {
      latest = await fileLatest(context, latestItem);
      if (latest.problem) return refuse("a read-back of darkmem's copies differs; nothing was moved locally", [latest.problem]);
    }
  } catch (error) {
    return darkmemRefusal(error, report.failures);
  }
  const workRoot = path.join(cfg.mirror, "work");
  for (const item of sources) writeFileAtomic(local(workRoot, item.rel), item.buffer);
  const unread = sources.filter(item => !fs.readFileSync(local(workRoot, item.rel)).equals(item.buffer));
  if (unread.length) return refuse("a copy into the mirror reads back different", unread.map(item => local(workRoot, item.rel)));
  for (const item of sources) {
    if (item.kind === "ledger") {
      state.ledgers[item.slug] = { offset: item.buffer.length, prefix: sha256(item.buffer), lastSeq: lastSeqs.get(item.slug) };
    } else if (item.kind === "handoff") {
      state.documents[item.uri] = sha256(item.buffer);
    } else {
      state.checkpoint = latest.hash;
      state.checkpointAt = latest.at;
    }
  }
  persist();
  const aside = `moved-${utcStamp()}`;
  const backups = new Set();
  for (const item of files) {
    const target = local(path.join(item.stateDir, aside), item.rel);
    fs.mkdirSync(path.dirname(target), { recursive: true });
    fs.renameSync(item.file, target);
    backups.add(path.join(item.stateDir, aside));
  }
  const count = kind => sources.filter(item => item.kind === kind).length;
  return {
    moved: true,
    details: [
      `${count("ledger")} ledgers and ${count("handoff")} handoff notes in darkmem`,
      ...(latest ? [latest.detail] : []),
      ...[...backups].map(dir => `sources moved to ${dir}`),
    ],
  };
}
```

In `scripts/lib/darkmem-reconcile.mjs`, add beside the module's other imports:

```js
import { progressToDarkmem } from "./darkmem-progress-move.mjs";
```

and add this entry to the `MOVES` object literal:

```js
  "progress:darkmem": progressToDarkmem,
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `timeout 300 node --test plugins/dr-forge/tests/darkmem-sync/reconcile-progress.test.mjs`
Expected: PASS, 12 tests. Then `timeout 900 bash plugins/dr-forge/tests/darkmem-sync.test.sh` — PASS.

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-forge/scripts/lib/darkmem-progress-move.mjs plugins/dr-forge/scripts/lib/darkmem-reconcile.mjs plugins/dr-forge/tests/darkmem-sync/reconcile-progress.test.mjs
git commit -m "feat(dr-forge): move progress into darkmem"
```

### Task 20: Move progress from darkmem back into the checkout

**Files:**
- Modify: `scripts/lib/darkmem-progress-move.mjs` (two imports; append `progressToLocal`)
- Modify: `scripts/lib/darkmem-reconcile.mjs` (import; one `MOVES` entry)
- Test: `tests/darkmem-sync/reconcile-progress.test.mjs` (append)

**Interfaces:**
- Consumes: C7 (`MOVES`, result shape, `writeApplied` on success, `inProgressReason(context)` called again after the move's own pull), C3 (`utcStamp`), C12 (`refuse`, `darkmemRefusal`, `scratchReport`, `local`, `newestCheckpoint`, `setup`, `LEDGER`, `LATEST`), existing `pullDocuments` and `pullLedgers` (`darkmem-pull.mjs`) and `uriFamily`.
- Produces: `progressToLocal(context)` registered as `MOVES["progress:local"]`.

**Items:** 5

**Implementer:** dr-superpowers:impl-opus-high
**Evaluation:** files 1 - spec 0 - coupling 2 - risk 3 = 6

- [ ] **Step 1: Write the failing tests**

Append to `tests/darkmem-sync/reconcile-progress.test.mjs`:

```js
test("progress moves back into the primary checkout from closed and open workstreams, and darkmem keeps its copy", async t => {
  const s = await setup(t, "local");
  const { workstream } = await s.seed.append({ project: "proj", workstream: "p1", entries: [{ kind: "ledger", body: LEDGER("p1") }] });
  await s.seed.append({ project: "proj", workstream: "p1", entries: [{ kind: "checkpoint", body: LATEST }] });
  await s.seed.updateWorkstream(workstream.id, { state: "closed", retain: true });
  await s.seed.append({ project: "proj", workstream: "p2", entries: [{ kind: "ledger", body: LEDGER("p2") }] });
  await s.seed.putDocument({ project: "proj", uri: "superpowers/handoff/p1.md", content: "# Handoff p1\n" });
  assert.equal(fs.existsSync(s.mirror), false, "the mirror starts empty");
  const result = await s.reconcile();
  assert.equal(result.code, 0, result.stdout + result.stderr);
  assert.match(result.stdout, /^darkmem-sync reconcile: progress moved to local$/m);
  const stateDir = path.join(s.repo, ".forge");
  assert.equal(read(path.join(stateDir, "sdd", "p1", "progress.md")), LEDGER("p1"), "a closed workstream's ledger comes back");
  assert.equal(read(path.join(stateDir, "sdd", "p2", "progress.md")), LEDGER("p2"));
  assert.equal(read(path.join(stateDir, "sdd", "p1", "handoff.md")), "# Handoff p1\n");
  assert.equal(read(path.join(stateDir, "handoff", "latest.md")), LATEST);
  assert.equal(fs.existsSync(s.workRoot), false);
  const [aside] = fs.readdirSync(s.mirror).filter(name => /^work-moved-\d{8}T\d{6}Z$/.test(name));
  assert.equal(read(path.join(s.mirror, aside, "sdd", "p1", "progress.md")), LEDGER("p1"));
  const after = s.state();
  assert.deepEqual(after.ledgers, {});
  assert.equal(after.checkpoint, null);
  assert.equal(after.checkpointAt, null);
  assert.deepEqual(after.pendingLinks, []);
  assert.equal("superpowers/handoff/p1.md" in after.documents, false);
  assert.deepEqual(s.stores(), { documents: "local", progress: "local" });
  assert.equal(s.stub.db.workstreams.length, 2);
  assert.equal(s.stub.db.documents.has("proj\u0000superpowers/handoff/p1.md"), true);
  const again = await s.reconcile();
  assert.equal(again.code, 0, again.stdout + again.stderr);
  assert.equal(again.stdout, "");
});

test("progress stays in darkmem when the primary checkout holds a different file", async t => {
  const s = await setup(t, "local");
  await s.seed.append({ project: "proj", workstream: "p1", entries: [{ kind: "ledger", body: LEDGER("p1") }] });
  write(path.join(s.repo, ".forge", "sdd", "p1", "progress.md"), "a local ledger\n");
  const result = await s.reconcile();
  assert.equal(result.code, 1, result.stdout + result.stderr);
  assert.match(result.stdout, /^darkmem-sync reconcile: progress stay darkmem \(configured local\): /m);
  assert.match(result.stdout, /^ {2}.+sdd[\\/]p1[\\/]progress\.md: differs from the mirror's sdd\/p1\/progress\.md$/m);
  assert.equal(read(path.join(s.repo, ".forge", "sdd", "p1", "progress.md")), "a local ledger\n");
  assert.equal(read(path.join(s.workRoot, "sdd", "p1", "progress.md")), LEDGER("p1"));
  assert.equal(s.stores().progress, "darkmem");
});

test("a workstream opened on darkmem since the mirror's last pull, for an unfinished plan, keeps progress in darkmem", async t => {
  const s = await setup(t, "local");
  await s.seed.append({ project: "proj", workstream: "p3", entries: [{ kind: "ledger", body: "# SDD ledger — plan: docs/forge/plans/p3.md\nTask 1: implementer x (assigned)\n" }] });
  const result = await s.reconcile();
  assert.equal(result.code, 1, result.stdout + result.stderr);
  assert.match(result.stdout, /^darkmem-sync reconcile: progress stay darkmem \(configured local\): a plan is in progress: /m);
  assert.equal(fs.existsSync(path.join(s.repo, ".forge", "sdd", "p3")), false, "nothing is copied");
  assert.equal(fs.existsSync(path.join(s.workRoot, "sdd", "p3", "progress.md")), true, "the mirror keeps the pulled ledger");
  assert.equal(s.stores().progress, "darkmem");
});
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `timeout 300 node --test plugins/dr-forge/tests/darkmem-sync/reconcile-progress.test.mjs`
Expected: FAIL — the first two new tests print `darkmem-sync reconcile: progress stay darkmem (configured local): no move from darkmem to local`; the third fails on its `a plan is in progress` match for the same reason.

- [ ] **Step 3: Write the implementation**

In `scripts/lib/darkmem-progress-move.mjs`, add `uriFamily` to the `./darkmem-mirror.mjs` import list and change the `./darkmem-pull.mjs` import to the two lines:

```js
import { pullDocuments, pullLedgers, remoteLedger } from "./darkmem-pull.mjs";
import { inProgressReason } from "./darkmem-reconcile.mjs";
```

The two modules import each other; that is safe because `inProgressReason` is only called at run time, never while the modules load.

Append to the end of the same file:

```js
// The latest.md file for `newest`, unless the mirror's copy is newer or holds
// a local edit; pull's rule, applied across every workstream.
function renderCheckpoint({ state, persist, report }, workRoot, newest) {
  if (!newest || (state.checkpointAt && isoMicros(newest.created_at) <= isoMicros(state.checkpointAt))) return;
  const file = path.join(workRoot, "handoff", "latest.md");
  const remote = Buffer.from(newest.body, "utf8");
  const hash = sha256(remote);
  const current = fs.existsSync(file) ? sha256(fs.readFileSync(file)) : null;
  if (current !== null && current !== hash && current !== state.checkpoint) {
    report.conflicts.push("handoff/latest.md: changed locally, and darkmem holds a newer checkpoint");
    return;
  }
  if (current !== hash) writeFileAtomic(file, remote);
  state.checkpoint = hash;
  state.checkpointAt = newest.created_at;
  persist();
}

// The mirror is brought up to darkmem first. A pull renders only open
// workstreams, and every imported ledger is closed, so this renders every
// workstream's ledger and the newest checkpoint across all of them; darkmem
// keeps its copy.
export async function progressToLocal(context) {
  const { cfg, client, state, persist } = context;
  const workRoot = path.join(cfg.mirror, "work");
  const roots = { docsRoot: path.join(cfg.mirror, DOC_PREFIX), workRoot, worktreeRoot: cfg.repoRoot, families: { documents: false, progress: true } };
  const report = scratchReport();
  try {
    const pulling = { ...context, roots, report };
    await pullDocuments(pulling);
    const every = await client.workstreams(cfg.project);
    await pullLedgers(pulling, every);
    renderCheckpoint(pulling, workRoot, await newestCheckpoint(context, every));
  } catch (error) {
    return darkmemRefusal(error);
  }
  const unclean = [...report.conflicts.map(line => `conflict: ${line}`), ...report.failures.map(line => `failed: ${line}`)];
  if (unclean.length) return refuse("the pull into the mirror did not finish cleanly", unclean);
  // The pull can bring a workstream another machine opened since this
  // mirror's last pull, which reconcile's own check never saw.
  const busy = inProgressReason(context);
  if (busy) return refuse(busy.reason, busy.details);
  const stateDir = forgeDir("state", cfg.repoRoot);
  const problems = unsupportedPlanDirs(workRoot).map(dir => `${dir}: not a usable workstream key`);
  const sources = [
    ...ledgerFiles(workRoot).map(({ slug, file }) => ({ file, rel: `sdd/${slug}/progress.md` })),
    ...listDocumentFiles(roots).map(({ file }) => ({ file, rel: `sdd/${path.basename(path.dirname(file))}/handoff.md` })),
  ];
  const latest = path.join(workRoot, "handoff", "latest.md");
  if (fs.existsSync(latest)) sources.push({ file: latest, rel: "handoff/latest.md" });
  for (const item of sources) {
    item.buffer = fs.readFileSync(item.file);
    item.target = local(stateDir, item.rel);
    if (fs.existsSync(item.target) && !fs.readFileSync(item.target).equals(item.buffer)) {
      problems.push(`${item.target}: differs from the mirror's ${item.rel}`);
    }
  }
  if (problems.length) return refuse("the primary checkout cannot take the mirror's progress", problems);
  for (const item of sources) {
    fs.mkdirSync(path.dirname(item.target), { recursive: true });
    fs.copyFileSync(item.file, item.target);
  }
  const differing = sources.filter(item => !fs.readFileSync(item.target).equals(item.buffer)).map(item => `${item.target}: the copy reads back different`);
  if (differing.length) return refuse("a copy into the primary checkout reads back different", differing);
  const details = [`${sources.length} files copied into ${stateDir}`];
  // Moved, not deleted: left in place, these copies would meet a later move
  // back to darkmem as differing files.
  if (fs.existsSync(workRoot)) {
    const aside = path.join(cfg.mirror, `work-moved-${utcStamp()}`);
    fs.renameSync(workRoot, aside);
    details.push(`the mirror's copies moved to ${aside}`);
  }
  state.ledgers = Object.create(null);
  state.checkpoint = null;
  state.checkpointAt = null;
  state.pendingLinks = [];
  for (const uri of Object.keys(state.documents)) {
    if (uriFamily(uri) === "progress") delete state.documents[uri];
  }
  persist();
  return { moved: true, details };
}
```

In `scripts/lib/darkmem-reconcile.mjs`, change the progress-move import to:

```js
import { progressToDarkmem, progressToLocal } from "./darkmem-progress-move.mjs";
```

and add this entry to the `MOVES` object literal:

```js
  "progress:local": progressToLocal,
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `timeout 300 node --test plugins/dr-forge/tests/darkmem-sync/reconcile-progress.test.mjs`
Expected: PASS, 15 tests. Then `timeout 900 bash plugins/dr-forge/tests/darkmem-sync.test.sh` — PASS.

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-forge/scripts/lib/darkmem-progress-move.mjs plugins/dr-forge/scripts/lib/darkmem-reconcile.mjs plugins/dr-forge/tests/darkmem-sync/reconcile-progress.test.mjs
git commit -m "feat(dr-forge): move progress back to a checkout"
```

### Task 21: darkmem hook library

**Files:**
- Create: `scripts/lib/darkmem-hook.sh`
- Test: `tests/darkmem-sync/hooks.test.mjs` (create)

**Interfaces:**
- Consumes: C4 (`darkmem-sync reconcile`, `pull`, `push` and their output), C6 (`forge_project`), C7 and C8 (the refusal line the test expects).
- Produces: C10 (`darkmem_session_lines DIR SID`, `darkmem_push_quietly DIR SID`), which Task 22 sources from both hooks.

**Items:** 3

**Implementer:** dr-superpowers:impl-sonnet-medium
**Executor:** codex gpt-6.1-sol / high
**Evaluation:** files 1 - spec 0 - coupling 2 - risk 1 = 4

- [ ] **Step 1: Write the failing test**

Create `tests/darkmem-sync/hooks.test.mjs`:

```js
import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";
import { createClient } from "../../scripts/lib/darkmem-client.mjs";
import { STUB_KEY, startStub } from "./stub-server.mjs";
import { makeHome, makeRepo, write } from "./helpers.mjs";

const LIB = fileURLToPath(new URL("../../scripts/lib/darkmem-hook.sh", import.meta.url));

// Runs bash asynchronously: the stub in this process must keep answering.
function bash(args, { cwd, env, input }) {
  return new Promise(resolve => {
    const child = execFile(process.env.DR_TEST_BASH ?? "bash", args, { cwd, env, timeout: 120000 }, (error, stdout, stderr) => {
      resolve({ code: error ? (typeof error.code === "number" ? error.code : -1) : 0, stdout, stderr });
    });
    child.stdin.end(input ?? "");
  });
}

const sessionLines = (dir, sid, env, room = "") => bash(["-c", '. "$1"; darkmem_session_lines "$2" "$3" "$4"', "hook-test", LIB, dir, sid, room], { cwd: dir, env });
const MORE = /^darkmem-sync: (\d+) more lines; run darkmem-sync reconcile or status to see them$/m;
const pushQuietly = (dir, sid, env) => bash(["-c", '. "$1"; darkmem_push_quietly "$2" "$3"', "hook-test", LIB, dir, sid], { cwd: dir, env });

// The hooks must export the session id themselves, so the test environment
// carries none.
function hookEnv(home) {
  const env = { ...home.env };
  delete env.DR_FORGE_SESSION_ID;
  delete env.DR_SUPERPOWERS_SESSION_ID;
  delete env.CLAUDE_CONFIG_DIR;
  return env;
}

async function setup(t, homeOptions = {}) {
  const stub = await startStub();
  t.after(() => stub.close());
  const repo = makeRepo();
  const home = makeHome({ repo, url: stub.url, ...homeOptions });
  const seed = createClient({ url: stub.url, apiKey: STUB_KEY, runKey: "seed" });
  return { stub, repo, home, seed, env: hookEnv(home) };
}

test("session lines show reconcile's refusal and pull's result, without notes", async t => {
  const s = await setup(t, { stores: { documents: "darkmem", progress: "local" } });
  write(path.join(s.repo, ".forge", "sdd", "p1", "progress.md"), "# SDD ledger — plan: docs/forge/plans/p1.md\nTask 1: implementer x (assigned; base abc1234)\n");
  await s.seed.putDocument({ project: "proj", uri: "superpowers/specs/a.md", content: "# A\n" });
  await s.seed.putDocument({ project: "proj", uri: "superpowers/.x.md", content: "hidden\n" });
  const result = await sessionLines(s.repo, "sid-hook", s.env);
  assert.equal(result.code, 0, result.stderr);
  assert.match(result.stdout, /^darkmem-sync reconcile: progress stay local \(configured darkmem\): a plan is in progress/m);
  assert.match(result.stdout, /^darkmem-sync pull: 1 documents, 0 ledgers, 0 checkpoints; 0 conflicts, 0 failures$/m);
  assert.doesNotMatch(result.stdout, /^note:/m);
});

test("the line cap trims only detail lines, keeping both families' lines", async t => {
  const s = await setup(t, { stores: { documents: "local", progress: "local" } });
  for (let i = 0; i < 25; i += 1) {
    const slug = `p${String(i).padStart(2, "0")}`;
    write(path.join(s.repo, ".forge", "sdd", slug, "progress.md"), `# SDD ledger — plan: docs/forge/plans/${slug}.md\nTask 1: a\n`);
  }
  const result = await sessionLines(s.repo, "sid-hook", s.env);
  assert.equal(result.code, 0, result.stderr);
  const lines = result.stdout.split("\n").filter(Boolean);
  assert.equal(lines.length, 20);
  assert.match(result.stdout, /^darkmem-sync reconcile: documents stay local \(configured darkmem\): a plan is in progress/m);
  assert.match(result.stdout, /^darkmem-sync reconcile: progress stay local \(configured darkmem\): a plan is in progress/m);
  assert.match(lines.at(-1), MORE);
  assert.equal(lines.filter(line => /^[ \t]/.test(line)).length, 17);
});

test("unindented lines outlast the line cap; the character room trims them last", async t => {
  const s = await setup(t);
  for (let i = 0; i < 25; i += 1) {
    await s.seed.putDocument({ project: "proj", uri: `superpowers/n${String(i).padStart(2, "0")}.`, content: "x\n" });
  }
  const result = await sessionLines(s.repo, "sid-hook", s.env);
  assert.equal(result.code, 0, result.stderr);
  const lines = result.stdout.split("\n").filter(Boolean);
  assert.equal(lines.filter(line => line.startsWith("failed: superpowers/n")).length, 25);
  assert.match(lines.at(-1), /^darkmem-sync pull: 0 documents, 0 ledgers, 0 checkpoints; 0 conflicts, 25 failures$/);
  assert.doesNotMatch(result.stdout, MORE);
  const tight = await sessionLines(s.repo, "sid-hook", s.env, "400");
  assert.ok(tight.stdout.length <= 400, `${tight.stdout.length} characters`);
  assert.match(tight.stdout, /^failed: superpowers\/n00\.: /m);
  assert.match(tight.stdout.trimEnd().split("\n").at(-1), MORE);
});

test("session lines print nothing for an unmapped repository or one with nothing to pull", async t => {
  const s = await setup(t);
  const other = makeHome({ repo: makeRepo(), url: s.stub.url });
  assert.deepEqual(await sessionLines(s.repo, "sid-hook", hookEnv(other)), { code: 0, stdout: "", stderr: "" });
  const none = makeHome({ repo: s.repo, url: s.stub.url, config: null });
  assert.deepEqual(await sessionLines(s.repo, "sid-hook", hookEnv(none)), { code: 0, stdout: "", stderr: "" });
  const local = makeHome({
    repo: s.repo, url: s.stub.url, stores: { documents: "local", progress: "local" },
    config: { darkmem: { url: s.stub.url, api_key_env: "DARKMEM_API_KEY", repos: { [s.repo]: { project: "proj", documentStore: "local", progressSource: "local" } } } },
  });
  assert.deepEqual(await sessionLines(s.repo, "sid-hook", hookEnv(local)), { code: 0, stdout: "", stderr: "" });
  assert.equal(s.stub.db.requests.length, 0);
});

test("a pull that changes nothing prints no line", async t => {
  const s = await setup(t);
  const result = await sessionLines(s.repo, "sid-hook", s.env);
  assert.deepEqual(result, { code: 0, stdout: "", stderr: "" });
  assert.ok(s.stub.db.requests.some(r => r.path === "/api/v1/documents/manifest"), "the pull ran");
});

test("the quiet push prints nothing and declares the session it was given", async t => {
  const s = await setup(t);
  write(path.join(s.home.workRoot, "sdd", "p1", "progress.md"), "# SDD ledger — plan: docs/forge/plans/p1.md\nTask 1: a\n");
  const result = await pushQuietly(s.repo, "sid-hook", s.env);
  assert.deepEqual(result, { code: 0, stdout: "", stderr: "" });
  const append = s.stub.db.requests.find(r => r.method === "POST" && r.path === "/api/v1/worklog/entries");
  assert.ok(append, "push appended the ledger");
  assert.equal(append.body.run_key, "sid-hook");
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 300 node --test plugins/dr-forge/tests/darkmem-sync/hooks.test.mjs`
Expected: FAIL — all 6 tests (bash cannot source the missing `darkmem-hook.sh`, so stdout is empty and stderr names the file).

- [ ] **Step 3: Write the implementation**

Create `scripts/lib/darkmem-hook.sh`:

```bash
# Sourced. darkmem sync from the Claude Code hooks (darkmem store options spec
# §5): reconcile and pull at session start, a silent push at Stop. Defines
# functions only; each returns 0 whatever happens, since a hook must never fail
# on a sync. The session id is exported into every darkmem-sync call, so the
# run darkmem records is the session's, not the per-directory fallback.

. "$(dirname "${BASH_SOURCE[0]}")/roots.sh"
_DARKMEM_HOOK_SCRIPTS=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

# No config file means no mapping, and costs no node start: the common case
# for a repository that never used darkmem.
_darkmem_configured() {
  command -v node >/dev/null 2>&1 || return 1
  [ -f "${HOME:-}/.dr-forge/config.json" ] || [ -f "${HOME:-}/.dr-superpowers/config.json" ]
}

# _darkmem_run DIR SID SECONDS COMMAND — darkmem-sync COMMAND in DIR, bounded
# when GNU timeout exists (macOS ships none; the hook's own timeout bounds it).
_darkmem_run() {
  if command -v timeout >/dev/null 2>&1; then
    (cd "$1" 2>/dev/null && DR_FORGE_SESSION_ID=$2 timeout "$3" bash "$_DARKMEM_HOOK_SCRIPTS/darkmem-sync" "$4" </dev/null)
  else
    (cd "$1" 2>/dev/null && DR_FORGE_SESSION_ID=$2 bash "$_DARKMEM_HOOK_SCRIPTS/darkmem-sync" "$4" </dev/null)
  fi
}

# _darkmem_fit MAXLINES MAXCHARS — the lines on stdin, fitted. Every unindented
# line (a family's reconcile line, a conflict, a failure, a summary) is kept, in
# order, while the character room holds it; indented detail lines fill what is
# left of both rooms; one closing line counts what was left out. 100 characters
# stay free for that line.
_darkmem_fit() {
  awk -v maxlines="$1" -v maxchars="$2" '
    { line[NR] = $0; detail[NR] = ($0 ~ /^[ \t]/) }
    END {
      room = maxchars - 100
      for (i = 1; i <= NR; i++) {
        if (detail[i]) { details++; continue }
        size = length(line[i]) + 1
        if (used + size <= room) { keep[i] = 1; used += size; tops++ }
      }
      slots = maxlines - tops
      if (details > slots) slots--
      for (i = 1; i <= NR; i++) {
        if (!detail[i] || slots <= 0) continue
        size = length(line[i]) + 1
        if (used + size <= room) { keep[i] = 1; used += size; slots--; shown++ }
      }
      for (i = 1; i <= NR; i++) if (keep[i]) print line[i]
      if (NR > tops + shown) printf "darkmem-sync: %d more lines; run darkmem-sync reconcile or status to see them\n", NR - tops - shown
    }'
}

# darkmem_session_lines DIR SID [ROOM] — reconcile's and pull's lines for the
# session start note, without notes, "nothing to pull" or a pull summary that
# reports nothing, fitted to 20 lines and ROOM characters (default: no
# character limit). A malformed config prints its one-line reason instead.
darkmem_session_lines() {
  local reason status
  _darkmem_configured || return 0
  reason=$( (forge_project "$1" >/dev/null) 2>&1 )
  status=$?
  case $status in
    0) ;;
    1) return 0 ;;
    *) printf '%s\n' "$reason" | head -n 1; return 0 ;;
  esac
  { _darkmem_run "$1" "$2" 200 reconcile 2>&1; _darkmem_run "$1" "$2" 60 pull 2>&1; } \
    | tr -d '\r' \
    | grep -v -e '^note:' -e 'nothing to pull' \
        -e '^darkmem-sync pull: 0 documents, 0 ledgers, 0 checkpoints; 0 conflicts, 0 failures$' \
    | _darkmem_fit 20 "${3:-1000000}"
  return 0
}

# darkmem_push_quietly DIR SID — the Stop hook's push. Its stdout is the hook's
# decision JSON, so nothing may reach it.
darkmem_push_quietly() {
  _darkmem_configured || return 0
  (forge_project "$1") >/dev/null 2>&1 || return 0
  _darkmem_run "$1" "$2" 100 push >/dev/null 2>&1
  return 0
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `timeout 300 node --test plugins/dr-forge/tests/darkmem-sync/hooks.test.mjs`
Expected: PASS (6 tests). Then the whole sync suite: `timeout 900 bash plugins/dr-forge/tests/darkmem-sync.test.sh` — PASS.

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-forge/scripts/lib/darkmem-hook.sh plugins/dr-forge/tests/darkmem-sync/hooks.test.mjs
git commit -m "feat(dr-forge): add darkmem hook library"
```

### Task 22: Reconcile, pull and push from the hooks

**Files:**
- Modify: `scripts/session-start.sh:97-105` (a darkmem block after the settings line, on every source; the compaction cap)
- Modify: `scripts/turn-end.sh:22-27` (the push after the session-id check, the recursion guard moved below it)
- Modify: `hooks/hooks.json` (whole file: two `timeout` fields and the description)
- Test: `tests/darkmem-sync/hooks.test.mjs` (append)

**Interfaces:**
- Consumes: C10 (`darkmem_session_lines`, `darkmem_push_quietly`, the hook timeouts).
- Produces: none.

**Items:** 3

**Implementer:** dr-superpowers:impl-sonnet-high
**Evaluation:** files 2 - spec 0 - coupling 1 - risk 2 = 5

- [ ] **Step 1: Write the failing test**

Append to `tests/darkmem-sync/hooks.test.mjs` (add `spawnSync` to the existing `node:child_process` import and `fs` as `import fs from "node:fs";`):

```js
const SCRIPTS = fileURLToPath(new URL("../../scripts/", import.meta.url));
const HOOKS_JSON = fileURLToPath(new URL("../../hooks/hooks.json", import.meta.url));
const hasJq = spawnSync("jq", ["--version"]).status === 0;
const runHook = (name, payload, options) => bash([path.join(SCRIPTS, name)], { ...options, input: JSON.stringify(payload) });

test("the hooks are bounded: SessionStart 300 seconds, Stop 120", () => {
  const hooks = JSON.parse(fs.readFileSync(HOOKS_JSON, "utf8")).hooks;
  assert.equal(hooks.SessionStart[0].hooks[0].timeout, 300);
  assert.equal(hooks.Stop[0].hooks[0].timeout, 120);
});

test("session start adds the darkmem lines on every source, compaction included", { skip: !hasJq && "jq is not on PATH" }, async t => {
  const s = await setup(t);
  const payload = source => ({ hook_event_name: "SessionStart", session_id: "sid-start", transcript_path: "", cwd: s.repo, source });
  for (const [source, uri] of [["startup", "superpowers/specs/a.md"], ["compact", "superpowers/specs/b.md"]]) {
    await s.seed.putDocument({ project: "proj", uri, content: `# ${uri}\n` });
    const result = await runHook("session-start.sh", payload(source), { cwd: s.repo, env: s.env });
    assert.equal(result.code, 0, result.stderr);
    const context = JSON.parse(result.stdout).hookSpecificOutput.additionalContext;
    assert.match(context, /darkmem-sync pull: 1 documents, 0 ledgers, 0 checkpoints; 0 conflicts, 0 failures/, source);
    assert.match(context, /dr-forge:using-superpowers/, source);
  }
});

test("the Stop hook pushes under its session id, a retried stop too, and prints nothing", { skip: !hasJq && "jq is not on PATH" }, async t => {
  const s = await setup(t);
  const ledger = path.join(s.home.workRoot, "sdd", "p1", "progress.md");
  write(ledger, "# SDD ledger — plan: docs/forge/plans/p1.md\nTask 1: a\n");
  const payload = active => ({ hook_event_name: "Stop", session_id: "sid-stop", cwd: s.repo, transcript_path: "", stop_hook_active: active });
  const appends = () => s.stub.db.requests.filter(r => r.method === "POST" && r.path === "/api/v1/worklog/entries");
  assert.deepEqual(await runHook("turn-end.sh", payload(false), { cwd: s.repo, env: s.env }), { code: 0, stdout: "", stderr: "" });
  assert.equal(appends().length, 1, "the Stop hook pushed the ledger");
  fs.appendFileSync(ledger, "Task 1: complete (commits abc1234..def5678, review clean)\n");
  assert.deepEqual(await runHook("turn-end.sh", payload(true), { cwd: s.repo, env: s.env }), { code: 0, stdout: "", stderr: "" });
  assert.equal(appends().length, 2, "a retried stop pushes the lines written since");
  assert.ok(appends().every(r => r.body.run_key === "sid-stop"));
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 300 node --test plugins/dr-forge/tests/darkmem-sync/hooks.test.mjs`
Expected: FAIL — the timeout test (`undefined !== 300`), the session-start test (no `darkmem-sync pull:` line in the startup context) and the Stop test (no append request).

- [ ] **Step 3: Write the implementation**

In `scripts/session-start.sh`, insert after the settings block (after line 97, the `fi` that closes `if [ -n "$settings_line" ]`):

```bash

# darkmem's reconcile and pull (darkmem store options spec §5), on every
# source: a line per moved or refused family and the pull's result, fitted to
# the room the hook's 10,000-character cap leaves the entry point. A
# compaction's snapshot gets what remains after them.
darkmem_lines=""
if . "${SCRIPT_DIR}/lib/darkmem-hook.sh" 2>/dev/null; then
  room=$(( 9500 - ${#content} - 400 - ${#roadmap_line} - ${#settings_line} ))
  darkmem_lines=$(darkmem_session_lines "${cwd:-$PWD}" "${session_id:-}" "$room" \
    | tr -d '\001-\010\013\014\016-\037')
  if [ -n "$darkmem_lines" ]; then
    context="${context}\n\n$(escape_for_json "$darkmem_lines")"
  fi
fi
```

and change the compaction cap line (line 105 before the insertion) from

```bash
  cap=$(( 9500 - ${#content} - 400 - ${#roadmap_line} - ${#settings_line} ))
```

to

```bash
  cap=$(( 9500 - ${#content} - 400 - ${#roadmap_line} - ${#settings_line} - ${#darkmem_lines} ))
```

In `scripts/turn-end.sh`, replace lines 22-27:

```bash
[ "$(jq -r '.stop_hook_active // false' <<<"$stdin_json")" = "true" ] && exit 0

session_id=$(jq -r '.session_id // empty' <<<"$stdin_json")
cwd=$(jq -r '.cwd // empty' <<<"$stdin_json")
transcript_path=$(jq -r '.transcript_path // empty' <<<"$stdin_json")
[ -n "$session_id" ] || exit 0
```

with (the recursion guard moves below the push and still guards every blocking decision):

```bash
session_id=$(jq -r '.session_id // empty' <<<"$stdin_json")
cwd=$(jq -r '.cwd // empty' <<<"$stdin_json")
transcript_path=$(jq -r '.transcript_path // empty' <<<"$stdin_json")
[ -n "$session_id" ] || exit 0

# darkmem's safety-net push (darkmem store options spec §5), before the
# recursion guard and every early exit below, so every stop sends the work
# before it, a retried stop included. stdout is this hook's decision, so the
# push prints nothing.
if . "${SCRIPT_DIR}/lib/darkmem-hook.sh" 2>/dev/null; then
  darkmem_push_quietly "${cwd:-$PWD}" "$session_id"
fi
[ "$(jq -r '.stop_hook_active // false' <<<"$stdin_json")" = "true" ] && exit 0
```

Replace `hooks/hooks.json` with:

```json
{
  "description": "Loads the cockpit mod, injects the dr-forge entry point at session start, persists the session's transcript path for budget tooling, appends a compaction snapshot after compaction, runs darkmem's reconcile and pull at session start and pushes at each stop for a repository mapped to darkmem, and holds a stop once when a turn that advanced a plan ends without the finishing menu or the next step.",
  "modules": ["./cockpit/register.tsx"],
  "hooks": {
    "SessionStart": [
      {
        "matcher": "startup|resume|clear|compact",
        "hooks": [
          {
            "type": "command",
            "command": "bash \"${CLAUDE_PLUGIN_ROOT}/scripts/session-start.sh\"",
            "shell": "bash",
            "async": false,
            "timeout": 300
          }
        ]
      }
    ],
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash \"${CLAUDE_PLUGIN_ROOT}/scripts/turn-start.sh\"",
            "shell": "bash",
            "async": false
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash \"${CLAUDE_PLUGIN_ROOT}/scripts/turn-end.sh\"",
            "shell": "bash",
            "async": false,
            "timeout": 120
          }
        ]
      }
    ]
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `timeout 300 node --test plugins/dr-forge/tests/darkmem-sync/hooks.test.mjs`
Expected: PASS (9 tests).
Run: `timeout 600 bash plugins/dr-forge/tests/hook.test.sh` and `timeout 600 bash plugins/dr-forge/tests/turn-end.test.sh`
Expected: both PASS unchanged (their HOME holds no darkmem config, so the hooks print exactly what they printed before).
Run: `timeout 600 claude plugin validate plugins/dr-forge`
Expected: the plugin validates with the new `timeout` fields.

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-forge/scripts/session-start.sh plugins/dr-forge/scripts/turn-end.sh plugins/dr-forge/hooks/hooks.json plugins/dr-forge/tests/darkmem-sync/hooks.test.mjs
git commit -m "feat(dr-forge): sync darkmem from session hooks"
```

### Task 23: Push and promote at the stop points

**Files:**
- Modify: `reference/project-state.md:114` (append a section after the last line)
- Modify: `skills/subagent-driven-development/SKILL.md:345` (one bullet before the first ledger-format bullet)
- Modify: `skills/executing-plans/SKILL.md:254` (one bullet before the first ledger-format bullet)
- Modify: `skills/revising-plans/SKILL.md:125` (a step 10 after step 9, Verify)
- Test: `tests/project-status.test.sh:193` (checks before the final summary)
- Test: `tests/plan-revise.test.sh:332` (one check after the routing-table check)

**Interfaces:**
- Consumes: C6 (`forge-path project`), C11 (stop-point push).
- Produces: the `§darkmem sync points` section that Task 24's prose cites.

**Items:** 3, 4

**Implementer:** dr-superpowers:impl-sonnet-medium
**Executor:** codex gpt-6.1-sol / high
**Evaluation:** files 2 - spec 0 - coupling 1 - risk 1 = 4

- [ ] **Step 1: Write the failing test**

In `tests/project-status.test.sh`, insert before the final `printf '\n%d passed, %d failed\n' "$pass" "$fail"` line:

```bash
# darkmem's stop points and promotion (store options spec §5): one rule in the
# shared reference, cited from both execution modes' ledger sections.
present "project-state: the sync points section" "$STATE" "## darkmem sync points"
present "project-state: stop points push" "$STATE" 'Run `bash <plugin-root>/scripts/darkmem-sync push` at each stop point'
present "project-state: the hooks reconcile, pull and push" "$STATE" 'runs `darkmem-sync reconcile`, then `pull`'
present "project-state: promotion uses memory_add" "$STATE" 'with `memory_add`, one fact per call, tagged `project/<project>`'
present "project-state: promotion keys on the mapping" "$STATE" 'when `forge-path project` prints a project'
for skill in subagent-driven-development executing-plans; do
  present "$skill: pushes after each ledger line" "$P/skills/$skill/SKILL.md" '§darkmem sync points'
done
```

In `tests/plan-revise.test.sh`, insert after line 332 (`present "the routing table lists the skill" …`):

```bash
present "the skill pushes the revised plan" "$SK" '10. **Push the revised plan.** Run `bash <plugin-root>/scripts/darkmem-sync push`'
```

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 600 bash plugins/dr-forge/tests/project-status.test.sh`
Expected: FAIL — 7 `FAIL - project-state: …` / `… pushes after each ledger line` lines.
Run: `timeout 600 bash plugins/dr-forge/tests/plan-revise.test.sh`
Expected: FAIL — `FAIL - the skill pushes the revised plan`.

- [ ] **Step 3: Write the implementation**

Append to `reference/project-state.md` (after line 114, `unchanged.`):

```markdown

## darkmem sync points

Run `bash <plugin-root>/scripts/darkmem-sync push` at each stop point: after
every `Task <N>: complete` and fix-round ledger line, after a spec or plan is
saved, and at handoff once `scripts/next-step` has written `<latest.md>`. In a
repository that is not mapped to darkmem it prints one line and exits 0, so no
check comes first. On Claude Code the SessionStart hook runs `darkmem-sync reconcile`, then `pull`,
and the Stop hook pushes as a safety net. Codex has no hooks, so there these
steps and the session-start step in
`skills/using-superpowers/references/codex-tools.md` are the only triggers.

**Promotion to memory.** At each `Task <N>: complete` line and at handoff,
when `forge-path project` prints a project and the darkmem MCP tools are
available, record the durable facts the work established (decisions and
their reasons, root causes and fixes, constraints) with `memory_add`, one fact per call, tagged `project/<project>`.
Ledger lines, progress and commit hashes stay in the work log.
```

In `skills/subagent-driven-development/SKILL.md`, insert before line 345 (`- Every task gets its own assigned line and its own complete line, including`):

```markdown
- After each `complete` and `fix round` line, run `scripts/darkmem-sync push`;
  at `complete`, also promote the task's durable facts
  ([project-state.md](../../reference/project-state.md) §darkmem sync points).
```

In `skills/executing-plans/SKILL.md`, insert before line 254 (``- `implementer inline` is this mode's assigned line. You are the implementer,``):

```markdown
- After each `complete` and `fix round` line, run `scripts/darkmem-sync push`;
  at `complete`, also promote the task's durable facts
  ([project-state.md](../../reference/project-state.md) §darkmem sync points).
```

In `skills/revising-plans/SKILL.md`, insert after line 125 (the last line of step 9, `   matching the \`recommend\` row.`):

```markdown
10. **Push the revised plan.** Run `bash <plugin-root>/scripts/darkmem-sync push`
   once the plan is saved, so a plan kept in darkmem carries the revision
   ([project-state.md](../../reference/project-state.md) §darkmem sync points).
   In a repository not mapped to darkmem it prints one line and changes nothing.
```

- [ ] **Step 4: Run test to verify it passes**

Run: `timeout 600 bash plugins/dr-forge/tests/project-status.test.sh` and `timeout 600 bash plugins/dr-forge/tests/plan-revise.test.sh`
Expected: both PASS, `0 failed`.
Run: `timeout 600 bash plugins/dr-forge/tests/inline-mode.test.sh`
Expected: PASS (it reads executing-plans; the bullet changes nothing it pins).

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-forge/reference/project-state.md plugins/dr-forge/skills/subagent-driven-development/SKILL.md plugins/dr-forge/skills/executing-plans/SKILL.md plugins/dr-forge/skills/revising-plans/SKILL.md plugins/dr-forge/tests/project-status.test.sh plugins/dr-forge/tests/plan-revise.test.sh
git commit -m "docs(dr-forge): push and promote at stop points"
```

### Task 24: Draft line, handoff push and Codex session start

**Files:**
- Modify: `skills/handoff/SKILL.md:105` (the design-phase `State` sentence) and `:123` (a paragraph closing step 4)
- Modify: `skills/using-superpowers/references/codex-tools.md:115` (append a section)
- Test: `tests/settings-skills.test.sh` (checks after the `finishing: failing tests at Step 1 stop the run` line)

**Interfaces:**
- Consumes: C4 (`darkmem-sync reconcile`, `pull`, `push`), C6 (`forge-path project`), C11, and the `§darkmem sync points` section Task 23 adds to `reference/project-state.md`.
- Produces: the literal ``- Draft: `<spec path>` `` line, which `checkpointTarget` (`scripts/lib/darkmem-mirror.mjs`) already reads.

**Items:** 3, 4

**Implementer:** dr-superpowers:impl-sonnet-medium
**Executor:** codex gpt-6.1-sol / medium
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 1 = 3

- [ ] **Step 1: Write the failing test**

In `tests/settings-skills.test.sh`, insert after the line `names "finishing: failing tests at Step 1 stop the run" "$P/skills/finishing-a-development-branch/SKILL.md" '(failing tests at Step 1, a merged'`:

```bash
H="$P/skills/handoff/SKILL.md"
names "handoff: a design phase writes the Draft line" "$H" '- Draft: `<spec path>`'
names "handoff: pushes once latest.md is written" "$H" 'run `scripts/darkmem-sync push` and promote'
CT="$P/skills/using-superpowers/references/codex-tools.md"
names "codex-tools: session start reconciles, then pulls" "$CT" 'bash <plugin-root>/scripts/darkmem-sync reconcile`, then'
names "codex-tools: nothing pushes at the end of a turn" "$CT" 'nothing pushes for you at the end of a turn'
```

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 600 bash plugins/dr-forge/tests/settings-skills.test.sh`
Expected: FAIL — 4 lines `FAIL - handoff: …` / `FAIL - codex-tools: …`.

- [ ] **Step 3: Write the implementation**

In `skills/handoff/SKILL.md`, replace line 105:

```markdown
   In a design phase, `State` names the draft instead of a plan and ledger.
```

with:

```markdown
   In a design phase, `State` names the draft instead of a plan and ledger,
   on the line ``- Draft: `<spec path>` `` in place of the `- Plan:` line, where
   `<spec path>` is the draft's name (`forge-path name`). darkmem files the
   checkpoint under the workstream either line names.
```

Then insert after line 123 (`own host in its header, so the execution call needs no flag.`), still inside step 4:

```markdown

   Then run `scripts/darkmem-sync push` and promote the session's durable
   facts ([project-state.md](../../reference/project-state.md) §darkmem sync
   points): the push carries the ledger, `handoff.md` and `latest.md`.
```

Keep the line beginning `Then run` unbroken as written: the test greps for its first words on one line.

Append to `skills/using-superpowers/references/codex-tools.md` (after line 115):

```markdown

## darkmem at session start

Codex runs no hooks. In a repository mapped to darkmem
(`bash <plugin-root>/scripts/forge-path project` prints its project), start
each session with `bash <plugin-root>/scripts/darkmem-sync reconcile`, then `bash <plugin-root>/scripts/darkmem-sync pull`,
and read what they print: a `darkmem-sync reconcile:` line names a family
that moved or stayed and why. Push at the stop points
[project-state.md](../../../reference/project-state.md) §darkmem sync points
names; nothing pushes for you at the end of a turn.
```

- [ ] **Step 4: Run test to verify it passes**

Run: `timeout 600 bash plugins/dr-forge/tests/settings-skills.test.sh`
Expected: PASS, `0 failed`.
Run: `timeout 600 bash plugins/dr-forge/tests/hook.test.sh`
Expected: PASS (the entry point is untouched and stays under 5,100 bytes).

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-forge/skills/handoff/SKILL.md plugins/dr-forge/skills/using-superpowers/references/codex-tools.md plugins/dr-forge/tests/settings-skills.test.sh
git commit -m "docs(dr-forge): add Draft line and darkmem handoff"
```

### Task 25: Distil documents kept in darkmem

**Files:**
- Modify: `skills/distilling-docs/SKILL.md:156` (a section before `## An external memory store`)
- Modify: `skills/distilling-docs/references/distil-judge.md:11-14,26,32` (the `[COMMIT]` and `[REWRITES]` placeholders and the two prompt lines that assume a git tree)
- Test: `tests/distilling-docs.test.sh` (checks after the `waves are bounded` line, and after the `judge rules on rewritten entries too` line)

**Interfaces:**
- Consumes: C3 (`superpowers/archive/<stamp>/`), C4 (`darkmem-sync revision NAME`, `darkmem-sync restore NAME`).
- Produces: none.

**Implementer:** dr-superpowers:impl-sonnet-medium
**Executor:** codex gpt-6.1-sol / medium
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 1 = 3

- [ ] **Step 1: Write the failing test**

In `tests/distilling-docs.test.sh`, insert after the line `present "waves are bounded" "$SKILL" 'never the whole tree'`:

```bash

# Documents in darkmem (wiring spec §2): the mirror is untracked, so synced and
# unchanged replaces tracked and clean, a revision replaces the SHA, two pushes
# replace the two commits, and restore replaces git revert.
present "darkmem: follows the document store" "$SKILL" 'prints `documents darkmem`'
present "darkmem: eligible means synced and unchanged" "$SKILL" 'bash <plugin-root>/scripts/darkmem-sync revision <name>'
present "darkmem: Source cites the revision" "$SKILL" '`<name>@r<id>`'
present "darkmem: two pushes" "$SKILL" 'The two commits become two pushes.'
present "darkmem: deletions are archived" "$SKILL" 'superpowers/archive/<stamp>/'
present "darkmem: restore replaces git revert" "$SKILL" 'bash <plugin-root>/scripts/darkmem-sync restore <name>'
present "darkmem: a rewrite reads the restored source" "$SKILL" 'restore <name>` brings the archived copy back'
```

and after the line `present "judge rules on rewritten entries too" "$JUDGE" 'rewrite'`:

```bash
present "judge accepts one revision per file in darkmem" "$JUDGE" 'one `<name>@r<id>` line per distilled file'
present "judge reads the files unedited since the snapshot" "$JUDGE" 'unedited since [COMMIT]'
present "judge rewrites carry the restored source in darkmem" "$JUDGE" 'the text of each source restored with `darkmem-sync restore`'
```

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 600 bash plugins/dr-forge/tests/distilling-docs.test.sh`
Expected: FAIL — 7 lines `FAIL - darkmem: …` and 3 lines `FAIL - judge …`.

- [ ] **Step 3: Write the implementation**

In `skills/distilling-docs/SKILL.md`, insert before line 156 (`## An external memory store`):

```markdown
## Documents in darkmem

While `bash <plugin-root>/scripts/forge-path store` prints `documents darkmem`,
`<docs>` is the darkmem mirror, which git does not track. Four rules above
change; everything else stands.

- **Eligible** replaces tracked and clean: `bash <plugin-root>/scripts/darkmem-sync revision <name>`
  exits 0, which it does only for a file synced and unchanged since the last
  push. `<name>` is the file's name (`forge-path name <path>`). Unreferenced is
  checked as above, over the checkout's tracked files, the mirror's documents
  outside those two directories, and `<latest.md>`.
- **`Source:`** cites `<name>@r<id>`, the line `revision` printed, captured
  before deletion; darkmem keeps that revision.
- **The two commits become two pushes.** Write the entries and run
  `darkmem-sync push`; give the judge each distilled file's `revision` line
  where it expects the SHA, and hold the mirror unedited until the verdicts
  return. Then delete exactly the `CARRIED` sources from the mirror and push
  again: push moves each deleted document to `superpowers/archive/<stamp>/`
  on darkmem. Never add entries and delete sources in one push.
- **Recovery** is `bash <plugin-root>/scripts/darkmem-sync restore <name>`,
  which moves the newest archived copy back and pulls it, in place of
  `git revert`.
- **Rewrites** of an earlier wave's entries need the exact text of each
  source their `Source:` lines cite, where local mode uses `git show`.
  `darkmem-sync restore <name>` brings the archived copy back into the mirror;
  it is the cited revision, because only a synced, unchanged file was
  eligible. Quote it in the judge's `[REWRITES]`, and delete it again in this
  wave's removal push.

```

Then edit `skills/distilling-docs/references/distil-judge.md`. Replace lines 11-14:

```markdown
- `[COMMIT]` — the SHA of the commit that added this wave's distilled entries.
- `[REWRITES]` — for each pre-existing entry this wave edited, its diff and a
  `git show` extract of every source named in its `Source:` lines. `none` when
  the wave added entries only.
```

with:

```markdown
- `[COMMIT]` — the SHA of the commit that added this wave's distilled entries;
  with documents in darkmem, one `<name>@r<id>` line per distilled file, as
  `darkmem-sync revision` printed it after the push.
- `[REWRITES]` — for each pre-existing entry this wave edited, its diff and a
  `git show` extract of every source named in its `Source:` lines (with
  documents in darkmem, the text of each source restored with `darkmem-sync restore`,
  as distilling-docs §Documents in darkmem says). `none` when the wave added
  entries only.
```

Replace line 26:

```markdown
Distilled files as they now stand, committed at [COMMIT]:
```

with:

```markdown
Distilled files as they now stand, at [COMMIT]:
```

Replace line 32:

```markdown
The working tree is clean at [COMMIT]. Read the files from the working tree.
```

with:

```markdown
The files are unedited since [COMMIT] (a commit, or one revision per file). Read
them where they stand.
```

- [ ] **Step 4: Run test to verify it passes**

Run: `timeout 600 bash plugins/dr-forge/tests/distilling-docs.test.sh`
Expected: PASS, `0 failed`.

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-forge/skills/distilling-docs/SKILL.md plugins/dr-forge/skills/distilling-docs/references/distil-judge.md plugins/dr-forge/tests/distilling-docs.test.sh
git commit -m "docs(dr-forge): distil documents kept in darkmem"
```

### Task 26: Cockpit reads its roots from --mode

**Files:**
- Modify: `types/index.d.ts:185-194` (add `CockpitRoots` after `CockpitFinish`), `types/index.d.ts:270-273` (atom `rootsNote`)
- Modify: `hooks/cockpit/lib.ts:1` (type import), `hooks/cockpit/lib.ts:756-772` (add `parseModeLines` after `parseFinish`)
- Modify: `hooks/cockpit/register.tsx:3-73` (imports), `:174-177` (atom), `:619` (re-read trigger), `:656-660`, `:1050-1085`, `:1340-1372`, `:1575-1630` (the pane's plan section), `:1971-2008` (`S`), `:2290-2297` (`readRun` calls the new reader)
- Test: `tests/cockpit.test.ts` (imports `:4-47`, `World` `:141-205`, the `process.run` mock `:274-313`, a new `describe('cockpit roots')` after the `run card` describe ending at `:2111`)

**Interfaces:**
- Consumes: C5 (`darkmem-config.mjs --mode DIR` output, exit codes).
- Produces: C13 (`CockpitRoots`, `rootsNote`, `parseModeLines`, `S.roots`, `readRoots`, the test `World` fields and the `cockpit roots` describe's constants), consumed by Task 27.

**Items:** 17

**Implementer:** dr-superpowers:impl-sonnet-medium
**Executor:** codex gpt-6.1-sol / high
**Evaluation:** files 2 - spec 0 - coupling 1 - risk 1 = 4

The cockpit asks `darkmem-config.mjs --mode <primary>` where the families live, once per primary checkout and `~/.dr-forge/stores.json` modification time. A failing run keeps today's checkout paths and shows its first stderr line in the plan section; no `node`, or a run that prints no mode lines (the test mock answers unknown commands with git porcelain and exit 0), keeps them silently. This task only reads and reports the roots; Task 27 makes `readRun` use them.

- [ ] **Step 1: Write the failing tests**

In `tests/cockpit.test.ts`, add `parseModeLines` to the import from `'../hooks/cockpit/lib'`:

```ts
  parseLedger,
  parseModeLines,
  planTasks,
```

Add three fields to `type World`, after `autoFile?: { text: string }`:

```ts
  /** What `darkmem-config.mjs --mode` answers; `missing` rejects as a missing node does. Git porcelain with exit 0 unless said. */
  modeOut?: { exitCode: number; stdout: string; stderr: string } | 'missing'
  /** The directory each `--mode` call names. */
  modeRuns?: string[]
  /** The primary checkout `git rev-parse --git-common-dir` points into; the session's repository unless said. */
  primary?: string
```

In `world`'s `on('process.run', …)` handler, replace the last two lines

```ts
    const stdout = argv === 'hostname' ? 'devbox\n' : argv.startsWith('git rev-parse') ? '/home/me/code/shop/.git\n' : PORCELAIN
    return { value: { exitCode: 0, stdout, stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }
```

with

```ts
    if (argv.includes('/scripts/lib/darkmem-config.mjs ')) {
      w.modeRuns?.push(e.argv[e.argv.length - 1] ?? '')
      if (w.modeOut === 'missing') throw new Error('spawn node ENOENT')
      const out = w.modeOut ?? { exitCode: 0, stdout: PORCELAIN, stderr: '' }
      return { value: { ...out, isStdoutTruncated: false, isStderrTruncated: false } }
    }
    const stdout = argv === 'hostname' ? 'devbox\n' : argv.startsWith('git rev-parse') ? `${w.primary ?? '/home/me/code/shop'}/.git\n` : PORCELAIN
    return { value: { exitCode: 0, stdout, stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }
```

After the closing `})` of `describe('run card', …)` (the line before `describe('flight deck', …)`), add:

```ts
describe('cockpit roots', () => {
  const MIRROR = '/home/me/.dr-forge/mirror/shop'
  const MODE = [
    `documents\tdarkmem\t${MIRROR}/superpowers`,
    `progress\tdarkmem\t${MIRROR}/work/sdd\t${MIRROR}/work/handoff/latest.md`,
    'project\tshop',
    '',
  ].join('\n')
  const LEDGER = '# SDD ledger — plan: docs/superpowers/plans/p.md\nTask 1: implementer dr-forge:impl-sonnet-low (assigned; base abc1234)\n'
  const PLAN = '# Plan\n\n### Task 1: Add the helpers\n\n### Task 2: Draw the card\n'
  const checkoutFiles = (): NonNullable<World['files']> => ({
    '/home/me/code/shop/.forge/sdd/p/progress.md': { text: LEDGER, mtimeMs: 2_000_000 },
    '/home/me/code/shop/docs/superpowers/plans/p.md': { text: PLAN },
  })

  test('reads the roots --mode prints', () => {
    expect(parseModeLines(MODE)).toEqual({
      docs: { store: 'darkmem', root: `${MIRROR}/superpowers` },
      progress: { store: 'darkmem', ledgerRoot: `${MIRROR}/work/sdd`, latestFile: `${MIRROR}/work/handoff/latest.md` },
      project: 'shop',
    })
    expect(parseModeLines('documents\tlocal\t/r/docs/forge\nprogress\tlocal\t/r/.forge/sdd\t/r/.forge/handoff/latest.md\n')?.project).toBeNull()
    expect(parseModeLines(PORCELAIN)).toBeNull()
    expect(parseModeLines('documents\tlocal\t/r/docs/forge\n')).toBeNull()
    expect(parseModeLines('documents\telsewhere\t/r\nprogress\tlocal\t/a\t/b\n')).toBeNull()
  })

  test('a failing --mode keeps the checkout paths and says why', async ($, on) => {
    const files = checkoutFiles()
    const stderr = 'darkmem-config: /home/me/.dr-forge/stores.json is not valid JSON: Unexpected token\nat line 2\n'
    world(on, { ...SIGNED_IN, files, modeOut: { exitCode: 2, stdout: '', stderr } })
    signedIn(on, files)
    await $.tool.call({ tool: 'Skill', skill: 'dr-forge:subagent-driven-development' })
    await $.session.start(START)
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    expect(await ui.find({ type: 'Text', text: /Task 1: Add the helpers/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /^darkmem-config: \/home\/me\/\.dr-forge\/stores\.json is not valid JSON: Unexpected token$/ })).toBeDefined()
    await ui.unmount()
    const desk = await $.ui.mount({ ...PANE, surface: 'desktop' })
    expect(JSON.stringify(await desk.drawn())).toContain('stores.json is not valid JSON')
  })

  test('without node the checkout paths stay silently', async ($, on) => {
    const files = checkoutFiles()
    world(on, { ...SIGNED_IN, files, modeOut: 'missing' })
    signedIn(on, files)
    await $.tool.call({ tool: 'Skill', skill: 'dr-forge:subagent-driven-development' })
    await $.session.start(START)
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    expect(await ui.find({ type: 'Text', text: /Task 1: Add the helpers/ })).toBeDefined()
    expect(await ui.find({ key: 'plan-roots' })).toBeUndefined()
  })

  test('a run that prints no mode lines keeps the checkout paths silently', async ($, on) => {
    const files = checkoutFiles()
    const modeRuns: string[] = []
    world(on, { ...SIGNED_IN, files, modeRuns })
    signedIn(on, files)
    await $.tool.call({ tool: 'Skill', skill: 'dr-forge:subagent-driven-development' })
    await $.session.start(START)
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    expect(modeRuns).toEqual(['/home/me/code/shop'])
    expect(await ui.find({ type: 'Text', text: /Task 1: Add the helpers/ })).toBeDefined()
    expect(await ui.find({ key: 'plan-roots' })).toBeUndefined()
  })

  test('reads the roots once per stores.json change, re-read from a mirror path', async ($, on) => {
    const files: NonNullable<World['files']> = { ...checkoutFiles(), '/home/me/.dr-forge/stores.json': { text: '{}', mtimeMs: 1 } }
    const modeRuns: string[] = []
    world(on, { ...SIGNED_IN, files, modeRuns })
    signedIn(on, files)
    await $.session.start(START)
    expect(modeRuns).toEqual(['/home/me/code/shop'])
    await $.tool.call({ tool: 'Bash', command: 'cat ~/.dr-forge/mirror/shop/work/sdd/p/progress.md' })
    expect(modeRuns).toHaveLength(1)
    files['/home/me/.dr-forge/stores.json']!.mtimeMs = 2
    await $.tool.call({ tool: 'Bash', command: 'cat ~/.dr-forge/mirror/shop/work/sdd/p/progress.md' })
    expect(modeRuns).toEqual(['/home/me/code/shop', '/home/me/code/shop'])
  })
})
```

The last test also proves the re-read trigger: a tool call naming only `~/.dr-forge/…` reaches `readRun` once the trigger matches `\.dr-forge`.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `timeout 600 claude plugin test plugins/dr-forge`
Expected: FAIL — `parseModeLines` is not exported from `hooks/cockpit/lib.ts`, so the file fails to load (every test fails); exit 1.

- [ ] **Step 3: Write the implementation**

`types/index.d.ts` — after the closing `}` of `export type CockpitFinish = { … }`, add:

```ts

/** Where a repository's documents and progress live, as `darkmem-config.mjs --mode` prints them. */
export type CockpitRoots = {
  docs: { store: 'local' | 'darkmem'; root: string }
  progress: { store: 'local' | 'darkmem'; ledgerRoot: string; latestFile: string }
  /** The darkmem project the repository is mapped to; null when it is not. */
  project: string | null
}
```

and in `PluginState['dr-forge']`, after `handoffAt: number | null`, add:

```ts
      /** Why the plan section reads checkout paths, not the roots `--mode` names: its first line of stderr; null otherwise. */
      rootsNote: string | null
```

`hooks/cockpit/lib.ts` — change line 1 to

```ts
import type { CockpitAutoRun, CockpitFinish, CockpitRoots } from '../../types'
```

and after the closing `}` of `parseFinish`, add:

```ts

/**
 * The roots `darkmem-config.mjs --mode` prints (darkmem store options spec
 * §7.3): a documents and a progress line, then a project line when the
 * repository is mapped. Null when either family's line is missing.
 */
export function parseModeLines(text: string): CockpitRoots | null {
  let docs: CockpitRoots['docs'] | null = null
  let progress: CockpitRoots['progress'] | null = null
  let project: string | null = null
  for (const line of text.split(/\r?\n/)) {
    const [kind, store, root, extra] = line.split('\t')
    if (kind === 'project' && store) project = store
    if (store !== 'local' && store !== 'darkmem') continue
    if (kind === 'documents' && root) docs = { store, root }
    if (kind === 'progress' && root && extra) progress = { store, ledgerRoot: root, latestFile: extra }
  }
  return docs === null || progress === null ? null : { docs, progress, project }
}
```

`hooks/cockpit/register.tsx`:

1. In the `import type { … } from '../../types'` list, after `  CockpitRefusal,` add `  CockpitRoots,`. In the `import { … } from './lib'` list, after `  parseLedger,` add `  parseModeLines,`.

2. After `const handoffAt = atom({ plugin: 'dr-forge', key: 'handoffAt' } as const, null)` add:

```ts
const rootsNote = atom({ plugin: 'dr-forge', key: 'rootsNote' } as const, null)
```

3. In `const S = { … }`, after the `autoTimer: null as Timer | null,` line add:

```ts
  // The roots --mode last named, and the primary checkout and stores.json
  // modification time they were read for.
  roots: { key: '', value: null } as { key: string; value: CockpitRoots | null },
```

4. Directly above `// The run's ledger, its plan's tasks, and the newest handoff: read from the` add:

```ts
// The roots darkmem-config.mjs --mode names for the primary checkout (store
// options spec §7.3). Read again when the checkout or ~/.dr-forge/stores.json
// changes, so the session that ran a move sees the new roots. Null keeps the
// checkout paths: silently without node or mode lines, with a note in the
// pane when the run fails or outruns its 5 seconds.
async function readRoots($: EngineInterface, primary: string): Promise<CockpitRoots | null> {
  const home = (await read($, place))?.home ?? null
  const stores = home === null ? null : await $.fs.stat(`${home}/.dr-forge/stores.json`).catch(() => null)
  const key = `${primary}|${stores?.mtimeMs ?? 'none'}`
  if (S.roots.key === key) return S.roots.value
  let value: CockpitRoots | null = null
  let note: string | null = null
  try {
    const ran = await $.process.run(['node', `${$.plugin.root}/scripts/lib/darkmem-config.mjs`, '--mode', primary], { timeoutMs: 5000 })
    if (ran.exitCode === 0) value = parseModeLines(ran.stdout)
    else note = ran.stderr.split(/\r?\n/).map(line => line.trim()).find(Boolean) ?? `darkmem-config.mjs --mode exited ${ran.exitCode}`
  } catch (error) {
    // The run could not start (no node) or outran its timeout.
    if (!/ENOENT/.test(String(error))) note = 'darkmem-config.mjs --mode gave no answer within 5 seconds'
  }
  S.roots = { key, value }
  if ((await read($, rootsNote)) !== note) await update($, rootsNote, () => note)
  return value
}

```

5. In `readRun`, after `  const state = await stateDirOf($, root)` add:

```ts
  await readRoots($, root)
```

6. Replace the re-read trigger line

```ts
      if (/\.forge|\.superpowers|finish-choice/.test(JSON.stringify(e))) await readRun($)
```

with

```ts
      if (/\.forge|\.superpowers|\.dr-forge|\.dr-superpowers|finish-choice/.test(JSON.stringify(e))) await readRun($)
```

7. In the `ui.render` Pane handler, after `    const handoffTime = await read($, handoffAt)` add:

```ts
    const rootsNow = await read($, rootsNote)
```

and replace

```tsx
    const runCard = () => {
      if (summary === null) return null
```

with

```tsx
    // Why the plan section reads checkout paths rather than the roots.
    const rootsLine = rootsNow !== null && (
      <Text key="plan-roots" color="red" wrap="truncate-end">
        {rootsNow}
      </Text>
    )
    const runCard = () => {
      if (summary === null) return null
```

8. In `runCard`, replace

```tsx
        summary.plan !== null && (
          <Text key="plan-path" dimColor wrap="truncate-end">
            plan {summary.plan}
          </Text>
        ),
```

with

```tsx
        summary.plan !== null && (
          <Text key="plan-path" dimColor wrap="truncate-end">
            plan {summary.plan}
          </Text>
        ),
        rootsLine,
```

9. In the terminal sections, replace

```tsx
        ) : items.length > 0 &&
        section(
```

with

```tsx
        ) : items.length > 0 ? (
        section(
```

and replace the end of that Plan section

```tsx
          finishNow !== null && finishLine(finishNow, now).length > 0 && (
            <Text key="plan-finish" wrap="truncate-end">
              {drawRuns('plan-finish-runs', finishLine(finishNow, now))}
            </Text>
          ),
        ),
      repo:
```

with

```tsx
          finishNow !== null && finishLine(finishNow, now).length > 0 && (
            <Text key="plan-finish" wrap="truncate-end">
              {drawRuns('plan-finish-runs', finishLine(finishNow, now))}
            </Text>
          ),
          rootsLine,
        )
        ) : (
          rootsLine !== false &&
          section(
            'plan',
            'Plan',
            'red',
            <Text key="plan-head" dimColor>
              checkout paths
            </Text>,
            rootsLine,
          )
        ),
      repo:
```

10. In the desktop `plan: (() => { … })()` panel, after

```ts
            if (summary.plan !== null) lines.push({ kind: 'text', small: true, left: [{ text: summary.plan, mono: true, dim: true }] })
```

add

```ts
            if (rootsNow !== null) lines.push({ kind: 'text', small: true, left: [{ text: rootsNow, color: 'red' }] })
```

replace

```ts
          if (items.length === 0) return false
```

with

```ts
          if (items.length === 0) return rootsNow !== null && panel('plan', 'Plan', 'red', [{ text: 'checkout paths' }], [{ kind: 'text', small: true, left: [{ text: rootsNow, color: 'red' }] }])
```

and in the Plan panel's line list, directly above

```ts
            ...(finishNow !== null && finishLine(finishNow, now).length > 0 ? [{ kind: 'chips', chips: [{ ...pill(finishLine(finishNow, now).map(run => run.text).join('')), color: 'yellow' }] } as PanelLine] : []),
          ])
```

add

```ts
            ...(rootsNow !== null ? [{ kind: 'text', small: true, left: [{ text: rootsNow, color: 'red' }] } as PanelLine] : []),
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `timeout 600 claude plugin test plugins/dr-forge`
Expected: PASS — `0 fail`, the five `cockpit roots > …` tests among the passes, exit 0.

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-forge/types/index.d.ts plugins/dr-forge/hooks/cockpit/lib.ts plugins/dr-forge/hooks/cockpit/register.tsx plugins/dr-forge/tests/cockpit.test.ts
git commit -m "feat(dr-forge): read cockpit roots from --mode"
```

### Task 27: Cockpit run card reads through the roots

**Files:**
- Modify: `hooks/cockpit/lib.ts:116-118` (add `docsLeaf` after `stateLeaf`), `hooks/cockpit/lib.ts:495-497` (add `planCandidates` after `isAbsolutePath`)
- Modify: `hooks/cockpit/register.tsx:47-56` (imports), `:108-110` (`resumePrompt`), `:1971-2008` (`S`), `:2290-2357` (`readRun`, new `finishPath`)
- Test: `tests/cockpit.test.ts` (imports, `describe('cockpit roots')` from Task 26)

**Interfaces:**
- Consumes: C5; C13 (from Task 26).
- Produces: nothing another task consumes.

**Items:** 17

**Implementer:** dr-superpowers:impl-sonnet-medium
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 2 = 4

`readRun` takes the ledger root and `latest.md` from the roots, resolves a document-named plan under the docs root while documents are in darkmem, and otherwise under each checkout's own docs directory (`docs/forge`, or `docs/superpowers` where only it exists) whichever prefix the ledger spells, session checkout first, and reads `finish.json` from the session's checkout before the primary, since it stays in the workspace of the worktree that ran the plan. The Resume prompt names the mirror's `latest.md` while progress is in darkmem.

- [ ] **Step 1: Write the failing tests**

In `tests/cockpit.test.ts`, extend the lib import:

```ts
  docsLeaf,
  parseModeLines,
  planCandidates,
  planTasks,
```

Inside `describe('cockpit roots', …)`, after the last test, add:

```ts
  test('resolves a plan under the docs root in darkmem, under the docs directory of each checkout otherwise', () => {
    expect(docsLeaf(new Set(['forge', 'superpowers']))).toBe('forge')
    expect(docsLeaf(new Set(['superpowers']))).toBe('superpowers')
    expect(docsLeaf(new Set())).toBe('forge')
    const darkmem = { store: 'darkmem' as const, root: `${MIRROR}/superpowers` }
    const w = { root: '/w', docsDir: '/w/docs/forge' }
    const p = { root: '/p', docsDir: '/p/docs/superpowers' }
    for (const name of ['docs/superpowers/plans/p.md', 'docs/forge/plans/p.md', './docs/forge/plans/p.md']) {
      expect(planCandidates(name, darkmem, [w, p])).toEqual([`${MIRROR}/superpowers/plans/p.md`])
      // Either prefix names the same document, read under whichever docs directory each checkout has.
      expect(planCandidates(name, { store: 'local', root: '/p/docs/superpowers' }, [w, p])).toEqual(['/w/docs/forge/plans/p.md', '/p/docs/superpowers/plans/p.md'])
      expect(planCandidates(name, null, [p, p])).toEqual(['/p/docs/superpowers/plans/p.md'])
    }
    expect(planCandidates('docs/plans/p.md', null, [w, p])).toEqual(['/w/docs/plans/p.md', '/p/docs/plans/p.md'])
    expect(planCandidates('/abs/plans/p.md', darkmem, [w])).toEqual(['/abs/plans/p.md'])
    expect(planCandidates('docs/superpowersx/p.md', darkmem, [w])).toEqual(['/w/docs/superpowersx/p.md'])
  })

  test('reads a plan named under docs/superpowers from a checkout that has only docs/forge', async ($, on) => {
    const files: World['files'] = {
      '/home/me/code/shop/.forge/sdd/p/progress.md': { text: LEDGER, mtimeMs: 2_000_000 },
      '/home/me/code/shop/docs/forge/plans/p.md': { text: PLAN },
    }
    world(on, { ...SIGNED_IN, files })
    signedIn(on, files)
    await $.tool.call({ tool: 'Skill', skill: 'dr-forge:subagent-driven-development' })
    await $.session.start(START)
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    expect(await ui.find({ type: 'Text', text: /Task 2: Draw the card/ })).toBeDefined()
  })

  test('reads a plan named under docs/forge from a checkout that has only docs/superpowers', async ($, on) => {
    const files: World['files'] = {
      '/home/me/code/shop/.forge/sdd/p/progress.md': { text: LEDGER.replace('docs/superpowers', 'docs/forge'), mtimeMs: 2_000_000 },
      '/home/me/code/shop/docs/superpowers/plans/p.md': { text: PLAN },
    }
    world(on, { ...SIGNED_IN, files })
    signedIn(on, files)
    await $.tool.call({ tool: 'Skill', skill: 'dr-forge:subagent-driven-development' })
    await $.session.start(START)
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    expect(await ui.find({ type: 'Text', text: /Task 2: Draw the card/ })).toBeDefined()
  })

  test('reads the ledger and the plan from the mirror when both families are in darkmem', async ($, on) => {
    const files: World['files'] = {
      [`${MIRROR}/work/sdd/p/progress.md`]: { text: LEDGER, mtimeMs: 2_000_000 },
      [`${MIRROR}/superpowers/plans/p.md`]: { text: PLAN },
    }
    world(on, { ...SIGNED_IN, files, modeOut: { exitCode: 0, stdout: MODE, stderr: '' } })
    signedIn(on, files)
    await $.tool.call({ tool: 'Skill', skill: 'dr-forge:subagent-driven-development' })
    await $.session.start(START)
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    expect(await ui.find({ type: 'Text', text: 'Run' })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /Task 2: Draw the card/ })).toBeDefined()
    expect(await ui.find({ key: 'plan-roots' })).toBeUndefined()
  })

  test('offers Resume for latest.md in the mirror, naming it', async ($, on) => {
    const files: World['files'] = { [`${MIRROR}/work/handoff/latest.md`]: { text: '# Handoff', mtimeMs: 900_000 } }
    const prompts: string[] = []
    world(on, { ...SIGNED_IN, files, prompts, modeOut: { exitCode: 0, stdout: MODE, stderr: '' } })
    signedIn(on, files)
    await $.session.start(START)
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    await ui.press({ key: 'pane-resume' })
    expect(prompts).toEqual([expect.stringContaining(`${MIRROR}/work/handoff/latest.md`)])
  })

  test("reads finish.json and a local plan from the session's worktree before the primary", async ($, on) => {
    const files: World['files'] = {
      '/home/me/code/main/.forge/sdd/p/progress.md': { text: LEDGER, mtimeMs: 2_000_000 },
      '/home/me/code/main/.forge/sdd/p/finish.json': { text: '{"action":"merge","base":"main","chosenAt":900}' },
      '/home/me/code/main/docs/superpowers/plans/p.md': { text: '# Plan\n\n### Task 1: Old title\n' },
      '/home/me/code/shop/.forge/sdd/p/finish.json': { text: '{"action":"pr","base":"main","chosenAt":900}' },
      '/home/me/code/shop/docs/superpowers/plans/p.md': { text: PLAN },
    }
    world(on, { ...SIGNED_IN, files, primary: '/home/me/code/main' })
    signedIn(on, files)
    await $.tool.call({ tool: 'Skill', skill: 'dr-forge:subagent-driven-development' })
    await $.session.start(START)
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    expect(await ui.find({ type: 'Text', text: /Task 1: Add the helpers/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /Finish push and open a PR/ })).toBeDefined()
  })

  test('a changed stores.json moves the card to the new roots', async ($, on) => {
    const files: NonNullable<World['files']> = {
      '/home/me/.dr-forge/stores.json': { text: '{}', mtimeMs: 1 },
      [`${MIRROR}/work/sdd/p/progress.md`]: { text: LEDGER, mtimeMs: 2_000_000 },
      [`${MIRROR}/superpowers/plans/p.md`]: { text: PLAN },
    }
    const w: World = { ...SIGNED_IN, files }
    world(on, w)
    signedIn(on, files)
    await $.tool.call({ tool: 'Skill', skill: 'dr-forge:subagent-driven-development' })
    await $.session.start(START)
    let ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    expect(await ui.find({ type: 'Text', text: 'Run' })).toBeUndefined()
    await ui.unmount()
    w.modeOut = { exitCode: 0, stdout: MODE, stderr: '' }
    files['/home/me/.dr-forge/stores.json']!.mtimeMs = 2
    await $.tool.call({ tool: 'Bash', command: 'cat ~/.dr-forge/stores.json' })
    ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    expect(await ui.find({ type: 'Text', text: 'Run' })).toBeDefined()
  })
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `timeout 600 claude plugin test plugins/dr-forge`
Expected: FAIL — `planCandidates` is not exported from `hooks/cockpit/lib.ts`, so the file fails to load; exit 1.

- [ ] **Step 3: Write the implementation**

`hooks/cockpit/lib.ts` — after the closing `}` of `stateLeaf`, add:

```ts

/** The docs directory's name under a checkout's docs/: forge, or the pre-2.0 superpowers where only that exists. */
export function docsLeaf(names: ReadonlySet<string>): string {
  return !names.has('forge') && names.has('superpowers') ? 'superpowers' : 'forge'
}
```

and after the closing `}` of `isAbsolutePath`, add:

```ts

/**
 * Where a ledger's plan name may be read, in order (darkmem store options spec
 * §7.1 and §7.3): an absolute name as written; a document name under either
 * prefix under the docs root while documents are in darkmem, else under each
 * checkout's own docs directory, since docs/superpowers/<rest> and
 * docs/forge/<rest> name one document; any other name under each checkout.
 * The session's checkout comes first.
 */
export function planCandidates(plan: string, docs: CockpitRoots['docs'] | null, checkouts: readonly { root: string; docsDir: string }[]): string[] {
  if (isAbsolutePath(plan)) return [plan]
  const name = plan.replace(/^\.\//, '')
  const doc = /^docs\/(?:forge|superpowers)(?:\/(.*))?$/.exec(name)
  const under = (dir: string) => (doc?.[1] ? `${dir}/${doc[1]}` : dir)
  if (doc && docs?.store === 'darkmem') return [under(docs.root)]
  const seen = new Set<string>()
  return checkouts.filter(one => !seen.has(one.root) && Boolean(seen.add(one.root))).map(one => (doc ? under(one.docsDir) : `${one.root}/${name}`))
}
```

`hooks/cockpit/register.tsx`:

1. In the `import { … } from './lib'` list, after `  parseModeLines,` add `  planCandidates,` and `  docsLeaf,`, and delete the line `  isAbsolutePath,` (its only use moves into `planCandidates`).

2. Replace `resumePrompt`:

```ts
function resumePrompt(): string {
  return `Resume the work in ${S.latestName ?? `${S.stateLeaf}/handoff/latest.md`} with the dr-forge resume-execution skill.`
}
```

3. In `const S = { … }`, after the `roots: …` entry Task 26 added, add:

```ts
  // latest.md's absolute path while progress is in darkmem; null while it is
  // in the checkout, where the resume prompt names it by its state directory.
  latestName: null as string | null,
```

4. Replace the comment above `readRun` and the function's opening, from

```ts
// The run's ledger, its plan's tasks, and the newest handoff: read from the
// primary checkout, S.where dr-forge keeps .forge/ (.superpowers/ before 2.0).
async function readRun($: EngineInterface) {
  const root = S.where.primary ?? (await read($, place))?.root ?? null
  if (root === null) return
  const state = await stateDirOf($, root)
  await readRoots($, root)
  try {
    const handoff = await $.fs.stat(`${state}/handoff/latest.md`).catch(() => null)
    const handoffTime = handoff?.kind === 'file' ? handoff.mtimeMs : null
    if ((await read($, handoffAt)) !== handoffTime) await update($, handoffAt, () => handoffTime)
    const base = `${state}/sdd`
    const entries = await $.fs.list(base).catch(() => [])
    let newest: { path: string; at: number } | null = null
    for (const entry of entries) {
      if (entry.kind !== 'dir') continue
      const info = await $.fs.stat(`${base}/${entry.name}/progress.md`).catch(() => null)
      if (info?.kind === 'file' && (newest === null || info.mtimeMs > newest.at)) newest = { path: `${base}/${entry.name}/progress.md`, at: info.mtimeMs }
    }
    await readFinish($, newest === null ? `${base}/finish.json` : newest.path.replace(/progress\.md$/, 'finish.json'))
```

to

```ts
// finish.json for the newest ledger's slug, or the no-plan one: it stays in
// the workspace of the worktree that ran the plan, so the session's checkout
// is read first, then the primary; the primary's path when neither has one.
async function finishPath($: EngineInterface, checkouts: readonly string[], slug: string | null): Promise<string> {
  const paths: string[] = []
  for (const dir of checkouts) {
    const leaf = stateLeaf(new Set((await $.fs.list(dir).catch(() => [])).map(entry => entry.name)))
    paths.push(slug === null ? `${dir}/${leaf}/sdd/finish.json` : `${dir}/${leaf}/sdd/${slug}/finish.json`)
  }
  for (const path of paths) {
    if ((await $.fs.stat(path).catch(() => null))?.kind === 'file') return path
  }
  return paths[paths.length - 1] ?? ''
}

// The run's ledger, its plan's tasks, and the newest handoff, read where the
// roots put them (store options spec §7.3): the primary checkout's state
// directory (.forge/, .superpowers/ before 2.0) while progress is local, the
// darkmem mirror while it is not.
async function readRun($: EngineInterface) {
  const session = (await read($, place))?.root ?? null
  const root = S.where.primary ?? session
  if (root === null) return
  const state = await stateDirOf($, root)
  const roots = await readRoots($, root)
  const latest = roots?.progress.latestFile ?? `${state}/handoff/latest.md`
  S.latestName = roots?.progress.store === 'darkmem' ? latest : null
  const checkouts = [...new Set([session, root].filter((dir): dir is string => dir !== null))]
  try {
    const handoff = await $.fs.stat(latest).catch(() => null)
    const handoffTime = handoff?.kind === 'file' ? handoff.mtimeMs : null
    if ((await read($, handoffAt)) !== handoffTime) await update($, handoffAt, () => handoffTime)
    const base = roots?.progress.ledgerRoot ?? `${state}/sdd`
    const entries = await $.fs.list(base).catch(() => [])
    let newest: { slug: string; path: string; at: number } | null = null
    for (const entry of entries) {
      if (entry.kind !== 'dir') continue
      const info = await $.fs.stat(`${base}/${entry.name}/progress.md`).catch(() => null)
      if (info?.kind === 'file' && (newest === null || info.mtimeMs > newest.at)) newest = { slug: entry.name, path: `${base}/${entry.name}/progress.md`, at: info.mtimeMs }
    }
    await readFinish($, await finishPath($, checkouts, newest?.slug ?? null))
```

`finishPath` lists names itself rather than calling `stateDirOf`, which would overwrite `S.stateLeaf` with the session checkout's.

5. In `readRun`, replace the plan lookup

```ts
    if (ledger.plan !== null) {
      const planPath = isAbsolutePath(ledger.plan) ? ledger.plan : null
      for (const candidate of planPath === null ? [(await read($, place))?.root, root].filter(Boolean).map(dir => `${dir}/${ledger.plan}`) : [planPath]) {
```

with

```ts
    if (ledger.plan !== null) {
      const places: { root: string; docsDir: string }[] = []
      for (const dir of checkouts) {
        places.push({ root: dir, docsDir: `${dir}/docs/${docsLeaf(new Set((await $.fs.list(`${dir}/docs`).catch(() => [])).map(entry => entry.name)))}` })
      }
      for (const candidate of planCandidates(ledger.plan, roots?.docs ?? null, places)) {
```

The rest of `readRun` is unchanged.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `timeout 600 claude plugin test plugins/dr-forge`
Expected: PASS — `0 fail`, the twelve `cockpit roots > …` tests and every existing `run card > …` test among the passes, exit 0.

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-forge/hooks/cockpit/lib.ts plugins/dr-forge/hooks/cockpit/register.tsx plugins/dr-forge/tests/cockpit.test.ts
git commit -m "feat(dr-forge): read cockpit run through the roots"
```

### Task 28: Document the moves and release 2.3.0

**Files:**
- Modify: `README.md:274-298` (the **darkmem mirror (optional).** paragraph)
- Modify: `.claude-plugin/plugin.json:5`
- Modify: `.codex-plugin/plugin.json:3`

**Interfaces:**
- Consumes: C4 (`restore`, `revision`, `reconcile`), C7, C10, C11 — documented, not called.
- Produces: none.

**Implementer:** dr-superpowers:impl-sonnet-low
**Evaluation:** files 1 - spec 0 - coupling 0 - risk 0 = 1

- [ ] **Step 1: Rewrite the end of the README paragraph**

In `README.md`, replace the text from `` `import` moves an existing `docs/forge/` and its `` through the paragraph's last line (`does nothing.`) with:

```markdown
  `import` files an existing `docs/forge/` and its ledgers once, verified byte
  for byte. A changed `documentStore` or `progressSource` moves its family at
  the next session start: `reconcile` copies the files across, verifies every
  hash, records the new store in `stores.json`, and leaves documents leaving
  the repository as a staged `git rm` for you to commit. It refuses, naming
  the reason, while a plan is in progress, while darkmem is unreachable or the
  key is unset, or when a file cannot be carried (a dotfile, a symbolic link,
  an empty or non-UTF-8 file, a name some platform cannot hold, a case twin,
  an ignored file); it never overwrites a different darkmem copy, and moved
  progress files are kept under a dated `moved-<stamp>` backup. Session start
  runs `reconcile` and `pull`; the Stop hook and the skills' stop points run
  `push`. A document deleted from the mirror is archived on darkmem under
  `superpowers/archive/<stamp>/` and `restore <name>` brings it back;
  `revision <name>` prints the `<name>@r<id>` a distilled `Source:` line
  cites. `docs/superpowers/<rest>` and `docs/forge/<rest>` name the same
  document everywhere names are compared. A conflict is reported, never
  merged. Without the key the mirror still works offline and `pull` and
  `push` say why they skipped. Without a mapping every command but `import`
  prints one line and does nothing.
```

- [ ] **Step 2: Bump the version**

In `.claude-plugin/plugin.json` and `.codex-plugin/plugin.json`, change `"version": "2.2.0"` to `"version": "2.3.0"`.

- [ ] **Step 3: Run the repository validation**

Run: `node scripts/validate-repository.mjs`
Expected: exit 0.

- [ ] **Step 4: Run the plan's full validation**

From the repository root: `timeout 2700 node scripts/test-all.mjs`, `claude plugin validate .`, `claude plugin validate plugins/<name>` for each Claude plugin in `.claude-plugin/marketplace.json` (`dr-forge`, `dr-status`, `dcc-darkraise-ui`, `dcc-darkraise-win32ui`), and `timeout 600 claude plugin test plugins/dr-forge`.
Expected: all pass. Then confirm no process the run started is still alive (`pgrep -f darkmem-sync`, `pgrep -f 'node --test'` print nothing this run started).

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-forge/README.md plugins/dr-forge/.claude-plugin/plugin.json plugins/dr-forge/.codex-plugin/plugin.json
git commit -m "docs(dr-forge): document store moves, release 2.3.0"
```
