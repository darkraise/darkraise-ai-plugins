# Planning notes — darkmem store options, Plan 2

Spec: `docs/superpowers/specs/2026-10-13-darkmem-store-options-design.md`
(Delivery item 2, §4, §5, §7). Register rows 3, 4, 5, 17, 18 of
`docs/superpowers/registers/2026-09-24-darkmem-mirror.md`. Gathered
2026-10-13 while writing the plan; the session handed off on budget before the
plan file was started. Paths below are under `plugins/dr-forge/`.

## Facts established

- darkmem server half is deployed (darkmem register row 84, 2026-09-28):
  `PATCH /api/v1/documents/{id}` body `{uri?, title?, pinned?, tags?, expected_hash?}`
  (extra keys 422), answers `{document_id}`; 409 on a stale `expected_hash` or a
  taken uri; 404 unknown id; 422 nothing to change. Keyed (capture scope).
  `GET /api/v1/documents/{id}/revisions?limit=&before=` → `{document_id, items:[{id, content_hash, actor, api_key_id, created_at}], next_before}`, newest first. Manifest item: `{id, uri, content_hash, updated_at}`.
- `scripts/lib/darkmem-client.mjs` has no document PATCH or revisions call; the
  stub (`tests/darkmem-sync/stub-server.mjs`) has neither route.
- `stores.json` read/write (`writeApplied`, `storesPath`) already exist in
  `darkmem-config.mjs` (Plan 1). `--mode` takes no directory and prints no project.
- Pull renders only OPEN workstreams; import closes what it files. So a progress
  move cannot verify through a mirror pull: verify each filed workstream with
  `remoteLedger(client, id)` (pull.mjs) instead.
- Import reads only the primary checkout's ledgers, never `latest.md` or linked
  worktrees (`darkmem-import.mjs:148`). `importLedger` is internal; export it for reuse.
- Pull today would re-create a document deleted locally but still in state
  (pending archive). Plan 2 must skip it when darkmem's hash equals the recorded one.
- `turn-end.sh` stdout is the Stop decision JSON: any push there must be silent.
  It exits early without jq / session id / turn stamp; put the push right after
  the session-id check. `hooks/hooks.json` has no `timeout` fields yet.
- Codex has no hooks at all (`.codex-plugin/plugin.json` `"hooks": {}`): its
  session-start reconcile and pull go in `skills/using-superpowers/references/codex-tools.md`.
- The commit→push rule for documents already exists (`reference/project-state.md:111`,
  brainstorming, handoff, closing-a-milestone, finishing). Missing: progress push
  at task boundaries, promotion, the `- Draft:` line, distilling-docs darkmem mode.
- Cockpit: `readRun` (`hooks/cockpit/register.tsx:2290-2357`); re-read trigger regex
  at `:619` matches `.forge|.superpowers` but not `~/.dr-forge/mirror` — add `\.dr-forge`.
  Atom types live in `types/index.d.ts:262-279`. Mod runs node as
  `$.process.run(['node', `${$.plugin.root}/scripts/lib/…`])`. The test mock's
  default process answer is PORCELAIN with exit 0, so a run with no mode lines
  must fall back silently (only a non-zero exit shows a note).
- Version is 2.2.0 in both manifests; Plan 1 deferred the bump to Plan 2.
- Executor lane closed: `codex-gate usable=false reason=plugin-not-enabled lane=false`.
- `skills/using-superpowers/SKILL.md` limit 5,100 bytes (`tests/hook.test.sh:183`), now 4,982.

## Design rulings made while planning (record in the plan's Assumptions)

- Archives cover the documents family only (uriFamily `documents`, never under
  `superpowers/archive/`), only when documents are applied darkmem, and skip with a
  note when the mirror's docs root is missing (a deleted mirror must not archive everything).
- Pull, documents family: skip archive uris; a uri in state but absent from the
  manifest is removed locally when unchanged, else a conflict; a local deletion with
  darkmem unchanged is left for push; with darkmem changed, darkmem's copy is pulled back with a note.
- New commands: `restore NAME`, `revision NAME` (prints `NAME@r<id>`; fails unless
  synced and unchanged), `reconcile`. `parse()` gains a `positional` count; COMMANDS
  gain `summary: false` for status, reconcile, revision. Reconcile sets
  `report.refused`; main's exit counts it.
- `--mode [DIR]`; modeLines adds `project\t<name>` when mapped (update the exact-output
  test at `tests/darkmem-sync/config.test.mjs:164`); `roots.sh` `forge_project`;
  `forge-path project` (exit 1 unmapped). Hooks and promotion prose key on it.
- Reconcile is its own module `scripts/lib/darkmem-reconcile.mjs`, lock taken by main,
  `needsKey: false` (missing key is a refusal line). Output lines:
  `darkmem-sync reconcile: <family> moved to <store>` / `… <family> stay <applied> (configured <c>): <reason>`, details indented.
  In progress = an active `auto-run.json`, or any ledger (every worktree's when progress
  is local, the mirror's when darkmem) whose plan has no `completed.md` entry beside it
  in either spelling; a ledger with no identity line counts as in progress.
- Documents → darkmem: dirty check (`git status --porcelain --untracked-files=all`),
  §7.2 checks on `git ls-files -z` (dot segments, symlink via lstat, top-level
  `handoff/` and `archive/` reserved, empty/non-UTF-8, uriProblem, caseGroups, ignored via
  `--ignored=matching`), manifest hash precheck, put the missing ones, re-read manifest
  hashes, pull into the mirror (documents only) and compare, `git rm -r -q`, citations note
  (`git grep -I -l`, first 20 plus a count).
- Documents → local: refuse if `docs/superpowers` exists in the primary; pull; copy
  mirror docs into `docs/forge` refusing on a differing existing file; compare; drop
  documents-family state; move `<mirror>/superpowers` to `superpowers-moved-<stamp>`
  (stale mirror files would otherwise conflict on a later flip back); notes for
  `git check-ignore` hits and `.gitattributes` lines naming `docs/superpowers/`.
- Progress → darkmem: gather every worktree's ledgers and plan `handoff.md`; refuse on
  unusable dirs or a slug in two checkouts with different bytes; an existing workstream
  whose ledger text equals the file counts as already filed (makes a killed run
  retryable), otherwise refuse; precheck the mirror for differing files; file with
  exported `importLedger`, put handoff notes, verify via `remoteLedger`/getDocument;
  copy into the mirror with state records (offset, prefix, lastSeq); copy `latest.md`
  with `state.checkpoint` = its hash, `checkpointAt` null (not sent: it names a finished
  plan); move sources to `<state>/moved-<stamp>/`.
- Progress → local: `pull` with progress-only roots; copy ledgers, handoff notes and
  `latest.md` into the primary's `<state>`; refuse on differing files; compare; move
  `<mirror>/work` to `work-moved-<stamp>`; clear ledger, checkpoint, pendingLinks and
  handoff-uri state.
- Hooks: `scripts/lib/darkmem-hook.sh` with `darkmem_session_lines DIR SID`
  (reconcile then pull, drop `note:` and "nothing to pull" lines, at most 20) and
  `darkmem_push_quietly DIR SID`. session-start runs it except on `compact`, adds the
  lines to the context and subtracts them from the snapshot cap. hooks.json timeouts:
  SessionStart 300, Stop 120. Hook tests as node tests with the stub
  (`tests/darkmem-sync/hooks.test.mjs`), deleting `DR_FORGE_SESSION_ID` from the env to
  prove the hook exports it (check the append's `run_key`).
- Cockpit: `parseModeLines` in `hooks/cockpit/lib.ts`, type `CockpitRoots` and atom
  `rootsNote` in `types/index.d.ts`; `readRoots` cached on `root|stores.json mtime`;
  World mock gains `modeOut`. finish.json and local plans: session checkout first, then primary.

## Task outline (sequential; scores to be confirmed with ladder.md)

1. `forge_name_key` in `roots.sh` + `tests/roots.test.sh` (Rule S forced the split).
2. Key in `plan.sh` `plan_ledger` and `next-step` (ledger check ~:192, `plan_finished` :92, register loop :277) + plan-lib and next-step tests.
3. Key in `plan-revise` (`ledger_for` :166, `completed_form` :180) and `plan-lint` (:140, awk :151) + tests.
4. Key in `register.sh` `register_for_spec` :116, `lib/roadmap.sh` :85, `roadmap` :292 + register/roadmap tests.
5. Client `moveDocument`/stub PATCH; archive on push, pull skip/remove, status `deleted:`.
6. Client `revisions`/stub revisions; `restore` and `revision` commands; positional args.
7. `--mode [DIR]` + project line, `forge_project`, `forge-path project`.
8-11. Reconcile: skeleton + refusals + documents→darkmem; documents→local; progress→darkmem; progress→local (risk 3 each).
12. Hook triggers (session-start, turn-end, hooks.json, darkmem-hook.sh, hooks.test.mjs).
13. Skill prose: project-state stop-point push + promotion (`forge-path project`, `memory_add` tagged `project/<name>`), SDD/executing-plans/handoff pointers, handoff `- Draft:` line, codex-tools.md, project-status and finishing one-sentence name-key notes.
14. distilling-docs darkmem section (eligibility via `revision`, `Source: <name>@r<id>`, two pushes, `restore`).
15. Cockpit (§7.3).
16. README, version 2.3.0 in both manifests, full validation.
