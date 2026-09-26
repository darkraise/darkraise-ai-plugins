# dr-superpowers: darkmem as the store for planning documents and progress

Date: 2026-09-23
Status: design, owner-approved on 2026-09-23 alongside the server half.
Delivered in two increments (see Delivery). Depends on increment 1 (and, for
revisions, increment 3) of the server spec.
Server spec: `darkmem` repository,
`docs/superpowers/specs/2026-09-23-work-log-lane-design.md` (§2 is the REST
contract this spec consumes).

## Why

dr-superpowers writes two families of files into every repository it works in:

- **Planning documents**, committed: `docs/superpowers/{specs,plans,registers,distilled,notes}/`.
  In the darkmem repository that is 53 specs, 102 plans and the registers,
  7.2 MB.
- **Working files**, gitignored and local to one machine:
  `.superpowers/sdd/<plan>/progress.md` (the append-only ledger),
  `.superpowers/sdd/<plan>/handoff.md` (constraints, gotchas, open questions),
  `.superpowers/handoff/latest.md` (the resume checkpoint), plus review
  packages and budget telemetry. 19 MB in the darkmem checkout.

The owner wants both out of the repositories and into darkmem, where they are
searchable, watchable from the browser, and available on any machine — while
agents keep reading and editing files with their ordinary tools.

## Decisions (owner, 2026-09-23)

- darkmem is the source of truth for everything above except review packages
  and machine-local telemetry.
- The plugin works on a **local mirror outside the repository**, synced with
  darkmem.
- Without a darkmem mapping the plugin behaves exactly as today.

## 1. Configuration and modes

`~/.dr-superpowers/config.json`, user-level and never in a repository:

```json
{
  "darkmem": {
    "url": "http://<darkmem host>",
    "api_key_env": "DARKMEM_API_KEY",
    "repos": {
      "/root/repositories/darkmem": { "project": "darkmem" }
    }
  }
}
```

A repository is matched by its primary checkout's absolute path (the same
root `scripts/lib/context.sh` already derives for `.superpowers`). The key is
read from the named environment variable, never stored in the file. No
mapping, or no key, means **local mode**: every path is what it is today.

## 2. Two roots

Every one of the 92 references to `docs/superpowers` or `.superpowers` across
31 plugin files (skills, scripts, hooks, reference) resolves through two
helpers added to `scripts/lib`:

| Helper | Local mode | darkmem mode |
|---|---|---|
| `sp_docs_root` | `<repo>/docs/superpowers` | `~/.dr-superpowers/mirror/<project>/superpowers` |
| `sp_work_root` | `<repo>/.superpowers` | `~/.dr-superpowers/mirror/<project>/work` |

Skills name paths through the same two roots in prose (`<docs root>/specs/…`),
with the local-mode expansion stated once in `using-superpowers`, so a skill
reads correctly in both modes.

One mirror per project, shared by every worktree of that repository — the
semantics `.superpowers` already has. `budget-log.tsv` and review packages
stay under `<repo>/.superpowers` in both modes and are never synced.

## 3. `scripts/darkmem-sync`

A plugin script speaking the server's keyed REST surface (server spec §2: the
work-log routes, `POST /documents`, `GET /documents/by-uri`, the manifest and
the revision routes; every other document route stays login-only and is not
used). Sync state (per-file last synced hash, per-ledger last pushed byte
offset) lives in `<mirror>/.sync-state.json`.

**Run key.** `session-start.sh` already reads the hook's `session_id` from
stdin; it also persists it beside the transcript path it saves today, and
`darkmem-sync` sends it as the run's declared identity with
`X-Darkmem-Client: dr-superpowers`. The server refuses an undeclared run, so a
sync with no session id available — Codex, whose manifest declares no hooks —
falls back to `codex:<hostname>:<date>`, one run per machine per day. That
fallback is coarse by construction and stated as such: two Codex sessions on
one machine in one day share a run key, which only affects telling their lines
apart, never which workstream they land in.

- **`pull`** — read the project's manifest under the `superpowers/` uri prefix
  and fetch only documents whose `content_hash` differs from the recorded one
  into `sp_docs_root`, recording the new hashes; a local file with unpushed
  changes is never overwritten, it is reported as a conflict. For
  each open workstream, render `work/sdd/<key>/progress.md` by concatenating
  its `ledger` entries in order (each entry is the exact text once appended,
  newlines included). `work/handoff/latest.md` gets the newest `checkpoint`
  entry across the project's open workstreams — the most recent stop, which is
  what the single `latest.md` means today — when it is newer than the local
  one.
- **`push`** —
  - documents: every file whose hash differs from the recorded one goes up
    through `document_put` with `expected_hash` set to the recorded hash; a
    `409` is reported as a conflict and the local file is left as it is;
  - ledgers: the bytes appended to `progress.md` since the last recorded offset
    go up as one `ledger` entry — the whole chunk verbatim, never split into
    lines, so blank lines and multi-line tables survive and the server's
    concatenation reproduces the file exactly; a ledger file shorter than the
    recorded offset, or whose already-pushed prefix hash changed, is refused
    as a rewrite rather than guessed at. A chunk longer than the server's
    65,536-character entry limit is split at the last newline under it, so
    the concatenation stays exact;
  - checkpoint: a changed `latest.md` becomes one `checkpoint` entry in the
    workstream given by `--workstream <key>`, which the handoff skill always
    passes (it knows the plan or draft it is stopping on); without the flag,
    the slug of the `Plan:` or draft path in `latest.md`'s `## State` section;
    when neither names one, the checkpoint is refused and reported rather
    than filed under a guessed key;
  - `handoff.md` is a document (`superpowers/handoff/<plan slug>.md`).
- **`status`** — local changes, unpushed ledger bytes, conflicts.
- **`import`** — the one-time move: push every file under
  `<repo>/docs/superpowers/`, then each `.superpowers/sdd/<plan>/progress.md`
  as a workstream that is closed after its entries land (entries are chunks
  split at blank-line boundaries with the separators kept inside the chunks,
  so concatenation is exact; `properties.imported_mtime` carries the file's
  modification time, since chunks have no timestamps of their own), and each
  `handoff.md` as its document. A ledger spans several append calls (at most
  100 entries each), so an import interrupted midway leaves a partial
  workstream; re-running `import` refuses any workstream that already holds
  entries unless given `--replace`, which purges it first (an admin-scoped
  key) — a plain re-run never appends duplicates. Imported workstreams are closed with
  `retain = true`, so the server's retention never deletes them (server spec
  §6). It finishes with a `pull` into a scratch
  directory and a byte comparison against the source files; any difference
  fails the import.

Workstream identity: the plan or design slug is the key; `properties` carries
`plan_uri`, `spec_uri` and `handoff_uri` so the server's `worklog_resume`
names what to pull. The run key is the session identity the client already
declares to darkmem.

Every call has a bounded timeout. `pull` at session start fails open: on any
error it prints one line and the session continues on the mirror as it is.

## 4. When sync runs

- `SessionStart` (the existing hook) runs `pull` after its current work.
- The skills' existing stop points gain a `push`: the ledger write after each
  task and fix round (subagent-driven-development, executing-plans), handoff
  step 1, and a saved spec or plan (brainstorming, writing-plans,
  revising-plans).
- On Claude Code, a `Stop` hook runs `push` as a safety net. Codex has no
  hooks; there the skill steps are the only trigger.
- Offline, work continues on the mirror; the next successful `push` sends it,
  and conflicts surface then.

## 5. Promotion to memory

At task-complete and handoff, the skills gain one instruction, mirroring the
server's MCP instructions: record the durable facts this run established —
decisions and reasons, root causes and fixes, constraints — with
`memory_add`, one per entry; ledger lines and progress stay in the work log.

## 6. Moving a repository

Per repository, owner-run: configure the mapping, run `import`, confirm its
round-trip check passed, then delete `docs/superpowers/` in a commit of its
own and add it to `.gitignore`. Never automatic. The darkmem repository
additionally rewrites its `CLAUDE.md` citations first (server spec §4).

## 7. Testing

- Local mode: the existing suites pass unchanged with no config file present.
- darkmem mode against a stub HTTP server: pull writes files and state; push
  sends only changed documents with the recorded `expected_hash`; a `409`
  leaves the local file and reports a conflict; ledger push sends exactly the
  appended bytes as one entry and refuses a rewritten prefix; pull fetches
  only documents whose manifest hash changed; a missing session id takes the
  stated fallback run key; `import`'s round-trip check
  fails on a single changed byte; `pull` fails open on a refused connection
  within its timeout.
- `node scripts/validate-repository.mjs` and `claude plugin validate`, per the
  repository's CLAUDE.md.

## Delivery (amended 2026-09-24)

Two increments, so the sync can be built and tested before any skill depends
on it:

1. **The sync client** — §1, §3 and the §7 tests: `scripts/darkmem-sync` with
   `status`, `pull`, `push` and `import`, usable by hand and changing nothing
   in local mode. Plan: `docs/superpowers/plans/2026-09-24-darkmem-sync-client.md`.
2. **Wiring** — §2's two roots through every script and skill, §4's triggers
   and §5's promotion instruction. It needs one decision this design did not
   make: how a plan that lives in the mirror, outside the repository, is
   identified, since `plan_require_same_repo`, ledger identity lines, register
   `Covers` paths and `plans/completed.md` all name plans by
   repository-relative path.

§6 stays owner-run, after increment 2 and after the server's increment 1 is
deployed. The register `docs/superpowers/registers/2026-09-24-darkmem-mirror.md`
tracks all of it.

## Not in scope

- Syncing review packages or budget telemetry.
- A daemon or file watcher; sync runs at the stop points above.
- Merging concurrent edits of one document; a conflict is reported for the
  agent to resolve.
