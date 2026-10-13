# Plan 1 inventory: darkmem store options

Gathered 2026-10-13 while starting writing-plans for plan 1 of
`docs/superpowers/specs/2026-10-13-darkmem-store-options-design.md`. Paths are
under `plugins/dr-forge/` unless they start with `docs/` or `scripts/validate`.

## Decisions made while planning (not in the spec)

- **Bootstrap.** Roots follow the *applied* store. Plan 1 reads
  `~/.dr-forge/stores.json` and the first-run rule (§4) but has no reconcile,
  so `darkmem-sync import` records both families `darkmem` via a new
  `writeApplied` once it verifies. Otherwise a newly mapped repository never
  syncs (`push`/`pull` sync only applied families).
- **Test helper.** `tests/darkmem-sync/helpers.mjs` `makeHome` must write a
  `stores.json` record applying both families `darkmem` by default (option
  `stores`, `null` writes none), or every existing push/pull test syncs nothing.
- **Entries.** One entry per complete ledger line, but a blank line joins the
  entry before it (avoids blank entries); a trailing line without `\n` is held
  (note, not failure); offset advances by the bytes sent. Properties only on
  lines starting `Task N:`: `task`; `state` = `done` for `^Task N: complete \(`,
  `blocked` for `^Task N: BLOCKED`, `review` for `^Task N: fix round `, `wip`
  for `^Task N: implementer \S+ \(assigned`; `commit` = second hash of
  `commits <a>..<b>`. Send `properties` only when non-empty. darkmem's
  `WorklogEntryIn` takes per-entry `properties` (darkmem
  `backend/app/schemas/worklog.py:68`). Push tests to update: "one entry per
  push" (push.test.mjs:134), the 70-line split test (:166, now 70 entries).
- **forge-config.** `resolve(env, warn)` in `scripts/lib/forge-config.mjs:179`
  gives env > file > default; call it with a no-op warn from
  `darkmem-config.mjs` (safe to import: its CLI is guarded). Group name
  `darkmem` must be added to `GROUPS` in `scripts/validate-repository.mjs:122`
  and to the tab list asserted at `tests/cockpit.test.ts:2259`; README settings
  table (`README.md` ~line 686) gets two rows; `tests/forge-config.test.sh:108`
  ROWS gets `documentStore darkmem local remote` and the progress twin.
- **Mirror roots.** `roots = { docsRoot, workRoot, worktreeRoot, families }`;
  `families` defaults to both true when absent (keeps mirror.test fixtures).
  `pathToUri(roots, file)`: names `docs/forge/…`/`docs/superpowers/…`, or an
  absolute path under `docsRoot` or under `worktreeRoot`'s docs dir; never a
  segment search. Callers: `darkmem-mirror.mjs` propertiesFor (467, 472);
  tests mirror.test.mjs:77-81.
- **`--mode`.** `node darkmem-config.mjs --mode` prints
  `documents\t<applied>\t<root>` and `progress\t<applied>\t<ledger root>\t<latest>`;
  ConfigError exit 2, outside git exit 3. Guard like forge-config.mjs's last
  lines. roots.sh must call it through `scripts/lib/native-path.sh`
  `dr_native_path` (as `scripts/forge-config` does) and `cygpath -u` its output
  on Windows.
- **roots.sh loading.** Lazy, cached in shell variables; a `$(…)` subshell
  loses the cache, so scripts that call helpers repeatedly call
  `forge_stores_init` in the main shell first. ConfigError exits the script.
- **Ledger scans.** Add `forge_ledger_files [ROOT]` printing
  `<ledger>\t<checkout|mirror>`: every worktree's ledgers when progress is
  local, the mirror's once when darkmem (worktree loops would repeat them).
- **Prose.** Skills already write `<docs>`/`<state>` resolved by
  `scripts/forge-path` (using-superpowers SKILL.md:63, reference/project-state.md:74-87),
  so `<docs>` follows once forge-path uses the roots. New tokens
  `<ledger dir>` and `<latest.md>` replace 22 lines in 8 files
  (`grep -rnE "<workspace>/(progress|handoff)\.md|<state>/handoff/latest\.md|<state>/sdd/[^ ]*progress\.md|<state>/sdd/<plan"`).
  forge-path gains `ledger SLUG`, `latest`, `store`.

## Shell call sites (rewire)

- Docs root: `lib/register.sh:93`, `lib/roadmap.sh:18,113`, `scripts/roadmap:60`,
  `session-start.sh:82`, `lib/auto-run.sh:135-140` (register name stays
  relative; file via `forge_resolve`), `next-step:319,322`.
- Latest: `lib/snapshot.sh:21`, `lib/auto-run.sh:188`, `repo-audit:97`,
  `next-step:143,146,155,423`.
- Ledgers: `lib/plan.sh:326` (plan_ledger), `lib/snapshot.sh:31`,
  `repo-audit:55` (+ `$wt/$plan_rel` → forge_resolve), `plan-revise:146-176`
  (ledger_for; rewrite) and `:185-189` (completed_form rel),
  `next-step:171,185`, `task-brief:98`, `turn-end.sh:33,109`.
- Same-repo check: `plan_require_same_repo` (plan.sh:432) → rename
  `plan_require_same_project`; callers plan-amend:23, review-package:24,
  sdd-workspace, next-step:129. `plan_repo_canon` (plan.sh:312) and
  `plan_amendments_file` (:416) fall back to the cwd top for a mirror plan.
  plan-lint:47,117 derive root/rel from the plan's dir.
- Stay local (machine state): `lib/auto-run.sh:28` auto-run.json,
  `lib/context.sh:310,461` budget log, `finish-choice:55` finish.json,
  `sdd-workspace` workspace, `task-state.sh:138`.

## Proposed task split (sequential)

1. Schema keys + validator group + README + forge-config and cockpit tests.
2. `resolveStores`, `storesPath`, `writeApplied`, `--mode` in darkmem-config.mjs
   (keep `resolveMode` until task 4); config tests.
3. Mirror: roots.families, listDocumentFiles/localChanges per family,
   `pathToUri(roots, …)`, propertiesFor; mirror tests.
4. darkmem-sync.mjs on resolveStores (status per family, offline key exit 3,
   `env` in context), import records applied, remove resolveMode, helpers
   `stores` option; cli/config/import tests.
5. Push/pull family gating, handoff uris with progress, `--workstream` needs
   progress; push/pull tests.
6. Ledger entry properties in push; push tests.
7. `lib/roots.sh` + forge-path kinds; new `tests/roots.test.sh` with a
   `tests/fixtures/darkmem-stores.sh` helper (config + stores.json + mirror).
8. plan.sh + same-project rename + its callers.
9. Library and hook call sites (register, roadmap, snapshot, auto-run,
   session-start, turn-end).
10. Script call sites (next-step, repo-audit, plan-revise, task-brief, plan-lint).
11. Prose tokens and the commit→push rule.
