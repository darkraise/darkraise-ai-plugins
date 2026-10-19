# Deferred rows sweep

**Execution strategy:** parallel — the findings fall into areas that share
no file (cockpit, auto-run scripts, darkmem sync, migration, config and plan
tooling, validation and evals, skill text); the three risky areas
(concurrency, data loss, migration) run alone in their own waves

**Registers:** the nine registers listed under Scope; this spec is added to
each one's `**Covers:**` line

**Approach:** inline - skip 1: every finding was located in the current tree
by the 2026-10-19 triage, with file and line evidence and a fix sketch

## Decisions

The owner's answers on 2026-10-19.

1. Triage every deferred row first, then fix what is still real.
2. Scope: every real finding, medium and low.
3. The nine tier-eval rows close as `n/a` ("tier eval closed; reopen if it
   runs again"); the controller-eval and slug-test rows are fixed.
4. One spec and one plan, executed as parallel subagent waves.
5. Design sections approved as presented.

## Problem

153 register rows sat in `deferred`. A triage on 2026-10-19 checked each
against the current tree (bundle rows 9, 10, 25 and 32 of the auto-execution
register were split into their sub-findings, 175 entries in all): 127 are
still real, none high, 61 medium and 66 low; 16 were fixed by later work, 13
are obsolete, 18 are environment limits or accepted trade-offs, and 1 needs
darkmem's server. A deferred row that is still real is a known defect nobody
is tracking toward a fix, and a closed one still listed as deferred hides the
real ones.

## Scope

Register short names used below:

| Short | Register |
|---|---|
| CX | `2026-09-23-codex-v3.md` |
| DM | `2026-09-24-darkmem-mirror.md` |
| TR | `2026-10-01-tier-reevaluation.md` |
| DF | `2026-10-11-dr-forge.md` |
| FS | `2026-10-12-forge-settings.md` |
| DR | `2026-10-17-dforge-rename.md` |
| PR | `2026-10-17-process-roles.md` |
| RO | `2026-10-17-run-order-finish-controller.md` |
| AE | `2026-10-18-auto-execution-default.md` |

All under `docs/superpowers/registers/`. Code paths below are relative to
`plugins/dforge/` unless they start with `scripts/validate-repository.mjs`,
`tests/repository-layout.test.mjs`, `scripts/test-all.mjs`, `.github/`,
`docs/` or `evals/`, which are repository-relative.

**Closed when this spec is committed, before any code changes:**

- `done`, note citing the fixing commit or code: DM 11; TR 14;
  DF 12, 16; FS 5, 13, 20, 28, 29, 31, 33, 35.
- `n/a`, note giving the triage's reason: CX 15; DM 8, 19, 29 (needs a
  create-if-absent put on darkmem's server); TR 13; FS 6, 8, 10, 12, 14-19,
  21-24, 26, 42, 43, 45; DR 4, 22, 29, 41; RO 14, 18, 19; AE 12, 38.
- `n/a`, note "tier eval closed; reopen if it runs again": TR 4-12.
- Bundle rows AE 9, 10, 25, 32 stay open; their note records the closed
  sub-findings (9.L2, 25.L5, 32.L3, 32.L8 fixed) and they move to `done` when
  their last real sub-finding lands.

**Fixed by this work** (every other deferred row): each gets `--assigned`
naming the plan, and moves to `done` when its fix lands. DF 14 can be
verified only by a CI run, which needs `main` pushed (the owner's call): its
fix lands here and the row goes to `verify`, not `done`.

## Design

Each finding below is `register #row — fix. Check:` the test or read that
shows it. The triage's evidence lines are the starting point; an implementer
re-reads the code before changing it, since line numbers drift.

### P1. Cockpit

Owns `hooks/cockpit/register.tsx`, `hooks/cockpit/config.ts`,
`hooks/cockpit/lib.ts`, `tests/cockpit.test.ts`.

1. AE #8 — `refresh` does not send the handoff note, and measures against
   `finalLimitFor`, once the session's plan has every task complete (the
   attended final phase). Check: a cockpit test with all tasks complete,
   tokens between `budgetFor` and `finalLimitFor`, sees no note.
2. AE 32.L1 — in the switch stage a `skip` from `$.session.compact` is booked
   as `compacted --switch` and the stage proceeds to switch-resume; it is not
   a failure. Check: cockpit test.
3. AE 32.L4 — the cockpit derives the primary checkout as `ar_primary_root`
   does: `git -C <dirname of the common dir> rev-parse --show-toplevel`.
   Check: cockpit test with a linked worktree.
4. AE 32.L7 — the plugin root is quoted (`bash "<root>/scripts/auto-run" …`)
   in every model-facing prompt the cockpit builds. Check: cockpit test reads
   the stall prompt.
5. AE #34 — the deferral clock resets while a turn is live; after a failed
   `stalled` call the watchdog retries no sooner than one `STALL_MS` later;
   `beat` has its own catch so it cannot abort the tick. Check: cockpit tests
   for the cap's exit 5 and non-zero branches, and a live turn with idle
   activity that the watchdog leaves alone only because of the turn guard.
6. RO #21 — Check only: a cockpit test counts `ui.invalidate` across
   `clock.advance(5000)` after a finish without wait and expects none.
7. DF #17 — `importSettings` runs `node <root>/scripts/lib/dforge-config.mjs
   get --json` through `$.process.run`, whose atomic legacy import replaces
   the mod's exists-then-write. Check: cockpit test.
8. FS #25, FS #41 — `claudeLocks` names an invalid merged value in its lock
   text (for example "50000 from a project or managed file, not valid").
   Check: cockpit test.
9. FS #27 — the settings `edit`/`show` path clears `notifier.editing`, and
   the webhook and mention submits call `show({})` first. Check: cockpit
   tests for one open editor and for a cleared pending reset.
10. FS #30 — Check only: cockpit tests for strict mode at 276,250 tokens
    (59%) and relaxed cases crossing the nudge and handoff levels.
11. FS #32 — Check only: cockpit tests change a skill setting, then fire
    `$.agent.spawn` and close the pane, one note each.
12. DM #27 (cockpit half) — `readRoots`' cache key adds the mtime of
    `~/.dforge/config.json`. Check: cockpit test.
13. DM #28 (cockpit half) — `NO_NODE` matches only the start-failure wording,
    not any stderr containing ENOENT. Check: cockpit test.
14. DM #46 — after a timeout `S.roots` stays unset so the next turn retries,
    and the spawn is skipped when neither `~/.dforge/config.json` nor
    `stores.json` exists. Check: cockpit tests.
15. DR #5 — the repeated `\.dforge` alternative is removed. Check: read.

No P1 task carries an `**Executor:**` line: the cockpit suite does not load
in the Codex sandbox (AE #12).

### P2. Auto-run scripts

Owns `scripts/lib/auto-run.sh`, `scripts/auto-run`, `scripts/turn-end.sh`,
`scripts/session-start.sh`, `scripts/lib/context.sh`, `tests/auto-run.test.sh`,
`tests/turn-end.test.sh`, and the session lines of any other suite named in
item 2.

1. AE 32.L2 — `ar_start` writes under the same lock as `ar_update`. Check:
   a test holds the lock and shows `start` waits for it.
2. AE 32.L5 — a subagent's shell carries the controller's
   `CLAUDE_CODE_SESSION_ID` and the same set of `CLAUDE_*` variables
   (probed 2026-10-19), so no script can tell the two apart and no
   script-level guard is possible. Two fixes close the paths that exist:
   every test suite that reaches `ctx_line`, an `ar_*` function or
   `scripts/auto-run` sets `AR_SESSION` and `CLAUDE_CODE_SESSION_ID` to test
   values or unsets them, so an implementer running the suite during an auto
   run cannot bind to it; and P3 item 15 forbids the run-control commands in
   the implementer prompt. Check: a test scans `tests/*.sh` and fails on a
   suite that runs `context-size`, `auto-run` or sources `auto-run.sh`
   without setting or unsetting both variables.
3. AE 32.L6 — `ar_verdict` clears a stale `resume` pending. Check: test.
4. AE 32.L7 (script half) — `turn-end.sh` quotes the plugin root in its hold
   reasons. Check: `turn-end.test.sh`.
5. AE #33 — `ar_beat_age` rejects a negative (future) age; `session-start.sh`
   makes the cockpit directory outside the `record` branch; the test `beat`
   helper passes the session id through the same `tr` as `ar_beat_file`.
   Check: tests at 180 s, 181 s and a future stamp.
6. AE #35 — stop reasons are built from the `AR_*_CAP` variables. Check:
   tests for `ar_start`'s `stalls`, `stalledAt` and `compactionsSinceTask`
   fields, a state file without them, final and finish compactions against
   `compactionsSinceTask`, and `after-compact`'s unknown-size branch with
   setup due.
7. AE #37 — `ar_task_complete` stops the run in the primary checkout only in
   the `execute` or `final` phase. Check: test in the spec and plan phases.
8. AE 9.L4 — the `ctx_line` header comment covers exit 6 and the bound-run
   branch; `scripts/auto-run`'s usage glosses `clear --phase`. Check: read.

### P3. Skills, reference and documentation

Owns `skills/*/SKILL.md` and `skills/*/references/*` except `skills/migrate/`,
`reference/*.md`, `README.md`, `scripts/lib/snapshot.sh` (a comment only),
`tests/project-status.test.sh`, `tests/hook.test.sh`,
`tests/repo-audit.test.sh`. Text that must stay with a test: when a phrase a
suite greps for changes, the suite changes with it in the same task, and a
suite owned by another part is not edited — the phrase is kept.

1. AE 9.L1 — the README settings rows for `designApproval` and `specReview`
   say "no effect under `autoRun=on`".
2. AE 9.L3 — prose over 80 columns in `reference/auto-run.md` and the
   handoff, finishing and writing-plans skills is rewrapped; code spans that
   cannot break stay.
3. AE 9.L5 — handoff's "A hard stop: the plan is saved" bullet says "outside
   an auto run"; `reference/final-review.md` §Who runs it says what an auto
   run's `compact` line does there.
4. AE 10.L1-L5 — brainstorming: the `specReview=false` skip at the User
   Review Gate is prefixed "Outside `autoRun=on`,"; self-review item 3's
   decomposition question is qualified "(not under `autoRun=on`)"; the
   auto-run exemption leads the `context-size --plan` bullet; checklist step
   12 names the Auto by default spec review; the process graph gains the
   `autoRun=on` branch (draft acceptance, write spec, Fable review, spec
   review stop).
5. AE 25.L1 — both execution skills name the two execution-phase lines
   (`Auto run: compacting`, `Auto run: clearing`) instead of "one of the two".
6. AE 25.L2 — `reference/final-review.md` step 4 writes the review's
   `lens-skipped` lines to the ledger; finishing and `reference/auto-run.md`
   §Finishing list them from the ledger instead of running `lens-route
   --final` after the merge, when base..HEAD is empty.
7. AE 25.L3 — both execution skills and `reference/auto-run.md` §After a
   compaction tell the controller to run `scripts/auto-run after-compact`
   after any compaction, prompted or not.
8. AE 25.L4 — in a wave, a deferred task's ledger line and register row name
   its unmerged task ref, and the "kept for the final review" claim is
   dropped for that case (`reference/auto-run.md`, both execution skills,
   `reference/parallel-waves.md`).
9. AE 25.L6 — every unqualified `autoRun=on` clause the triage listed
   (brainstorming, writing-plans, using-dforge) says "on Claude Code".
   `skills/using-dforge/SKILL.md` stays within `tests/hook.test.sh`'s 5,100
   byte cap: reword to fit rather than raise the cap.
10. AE 25.L7 — finishing's auto-run Step 4 mapping keeps the
    `scripts/finish-choice answer <action> --plan PLAN_FILE` call.
11. AE 25.L8 — brainstorming step 5 presents the spec review again after
    Changes needed; writing-plans' no-answer default follows the
    `executionStrategy` setting; `reference/final-review.md` excludes a
    deferred task's acceptance failures from the fix wave. Part (b) is
    already covered by the Stop hook's push and needs no change.
12. AE #36 — `reference/auto-run.md` §Clears handles `next-step`'s in-flight
    exit 5 (wait or stop, retry once, then stop the run), matching §The
    switch step 3.
13. PR #7 — `reference/final-review.md`'s recovery path applies (b)'s
    "write or complete … cannot-test: timeout" and restores QA's uncommitted
    paths; "0.5" becomes a heading or bullet; the file is rewrapped.
14. FS #36 — the long parenthetical in both execution skills is rewrapped.
15. AE 32.L5 (prompt half) — `skills/subagent-driven-development/references/
    implementer-prompt.md` says never to run `context-size`, `auto-run` or
    `next-step`; those belong to the controller.
16. DR #30 — `skills/using-dforge/references/codex-tools.md`'s "Pre-3.0
    layout check" heading becomes "Older layout check".
17. DR #31 — the "pre-3.0:" labels in `tests/hook.test.sh` and
    `tests/repo-audit.test.sh` become "older layout:", and repo-audit's
    ", and the command" label is fixed.
18. DR #39 — the README's Migrating to 4.0 section tells dr-superpowers and
    dr-cockpit users to install dforge directly.
19. CX #8 — the "OpenAI documents ultra as using subagents" sentence in
    `reference/native-codex.md` gets the source URL and an as-of date; if no
    OpenAI page states it, the sentence is removed.
20. CX #14 — revising-plans names the stderr text "is a Codex-host plan" as
    the way to tell the Codex refusal from plan-revise's other exit 2s.
21. DM #28 (skill half) — distilling-docs' stop path says to undo the
    restore.
22. DM #45 — `tests/project-status.test.sh` asserts the executing skills'
    push instruction itself; handoff's push sentence moves ahead of the
    Codex paragraph; `codex-tools.md` names `darkmem-sync push`.
23. DF #18 (plugin half) — `scripts/lib/snapshot.sh`'s size comment says
    about 5,000 bytes and the cap stays 5,100 (item 9).

Check for the whole part: the suites that read skill text
(`project-status`, `hook`, `repo-audit`, `auto-run-skills`, `inline-mode`,
`process-roles`, `settings-skills`, `final-phase`, `auto-default`) pass, and
each changed passage is read once against its finding.

### P4. darkmem sync

Owns `scripts/lib/darkmem-*.mjs`, `scripts/lib/darkmem-hook.sh`,
`scripts/darkmem-stop-push.sh`, `scripts/darkmem-sync`, `scripts/lib/roots.sh`,
`scripts/lib/plan.sh`, `tests/darkmem-sync/*` except `migrate.test.mjs`,
`tests/darkmem-sync.test.sh`, `tests/roots.test.sh`, `tests/next-step.test.sh`,
`tests/plan-lib.test.sh`.

1. DM #9 — `primaryRoot` falls back to `--show-toplevel` (or
   `--show-superproject-working-tree`) when the common-dir lookup fails, and
   `samePath` compares realpaths. Check: tests for a submodule and a
   symbolic-linked path.
2. DM #10 — `propertiesFor` catches only ENOENT; `splitAtLimit` rejects a
   limit under 2; `loadState` uses `statSync` with an ENOENT check. Check:
   tests.
3. DM #12 — `checkpointAt` is kept per workstream; a state file with the old
   single value uses it for every workstream until each is next written.
   Check: tests for two workstreams and for an old state file.
4. DM #13 — import leaves refused uris and slugs out of `verify`'s
   comparison, so no scratch directory is kept for them. Check: test.
5. DM #20 — `pathToUri` tries every `git worktree list` checkout's
   `docs/dforge`. Check: test.
6. DM #22 — `_plan_ctx` skips paths under `~/.dforge/mirror`; `dforge_name`
   tests `$DIR/$file`; a submodule resolves through item 1. Check: tests,
   including `ConfigError` through `plan_ledger`.
7. DM #27 (hook half) — `_darkmem_fit`'s first pass stops at the first miss.
   Check: test.
8. DM #28 (reconcile half) — the recheck refusal passes `again.failed` and
   `again.problems` as details; a git grep status other than 0 or 1 is a
   failure. Check: tests, including a checkpoint that reads back different.
9. DM #30 — the aside renames are guarded and a failure is one line naming
   the files left to move. Check: test.
10. DM #31 — `renderCheckpoint` does not return early when `latest.md` is
    missing; each copy re-checks its target just before copying. Check:
    tests.
11. DM #33 — `dforge_name_key` and `nameSpellings` strip a trailing slash.
    Check: `next-step.test.sh` case with a `docs/forge` Assigned cell against
    a `docs/superpowers` completed entry.
12. DM #35 — the stub server sets `next_before` only when items remain.
    Check: the pull tests still pass against the corrected stub.
13. DM #36 — `archiveDeleted` reports a note when darkmem no longer holds the
    document, and reuses `pushDocuments`' manifest. Check: test.
14. DM #37 — `removeVanished` guards the removal, re-hashes just before it,
    and skips a file whose name case-folds to a filed uri. Check: tests,
    including the `isArchiveUri` guard.
15. DM #38 — an empty `--mode` DIR is a usage error; `roots.test.sh` drops
    its unused `MIRROR` assignments and gains a no-node `dforge_project`
    case. Check: tests.
16. DM #39 — untracked details use `git status --porcelain -z`; a null grep
    status is a failure; `fileHash` returns a sentinel for a non-file.
    Check: tests.
17. DM #40 — `documentsToLocal` renames before persisting, refuses when
    `docs/dforge` is not a directory, and lstats `mirror.docsRoot`. Check:
    tests.
18. DM #41 — `readdirSync(sdd)` is guarded and a symbolic-linked
    `progress.md` is refused. Check: tests, including a `git worktree list`
    failure.
19. DM #42 — `fileLatest` closes a workstream it opened; the 422 refusal says
    what darkmem now holds. Check: tests, including the post-write recheck.
20. DM #43 — `progressToLocal` wraps its copy loop in a refusal, rejects a
    `stateRel` starting with `..`, and lstats mirror sources. Check: tests,
    including `renderCheckpoint`'s read failure.
21. DM #44 — Check only: hook tests for a malformed `~/.dforge/config.json`
    and a session-start room under 100.
22. DM #50 — `darkmem-stop-push.sh` bounds only the config lookup, leaving
    the push to its own bound. The bash 3.2 watchdog stays untested: CI has
    no macOS runner. Check: test.
23. DR #9 — the three "pre-3.0" comments read "older (superpowers/ or
    forge/)". Check: read.
24. DR #32 — a bare `dforge_resolve docs/forge` case; the suffix is computed
    once in `dforge_name_spellings`. Check: test.
25. DR #33 — the two comments are rewrapped. Check: read.
26. DR #34 — the restore case asserts exit code 1. Check: test.
27. DR #35 — `pathToUri` rejects an empty segment. Check: test.

### P5. Migration

Owns `scripts/dforge-migrate`, `scripts/lib/dforge-home-migrate.mjs`,
`scripts/lib/dforge-dir.sh`, `skills/migrate/SKILL.md`,
`tests/dforge-migrate.test.sh`, `tests/darkmem-sync/migrate.test.mjs`,
`tests/migrate-skill.test.sh`, `tests/dforge-dir.test.sh`.

`dforge-home-migrate.mjs`:

1. DR #7 — the message names the prefixes actually found in the state.
2. DR #8 — Check only: tests with `forge/` uris in state but no `forge/`
   folder, and with old uris in `pendingLinks`.
3. DR #10 — home-level mirror moves are marked by a flag, not a `/mirror`
   path suffix, so a project mirror named `mirror` gets its dry-run line.
4. DR #11 — the dry run reports a held `.sync.lock` and a `loadState` error
   as foretold refusals.
5. DR #12 — dry-run tests compare file contents (path and hash), not
   listings.
6. DR #13 — `rmdirSync` errors other than ENOTEMPTY and ENOENT are reported.
7. DR #14 — a `config.json` that is not a plain object is refused before the
   merge.

`dforge-migrate`:

8. DR #15 — `rewrite_prefixes` skips fenced code blocks.
9. DR #16 — tests assert the `moved … -> …` and `rewrote the plugin
   prefixes in …` lines.
10. DR #17, DR #18 — `dir_link_in` silences find's stderr and treats a
    non-zero find exit as holding a link.
11. DR #19 — `mv_plain` returns non-zero on refusal and `migrate_docs` sets
    `docs_ok=0`.
12. DR #20 — handoff notes under an old state directory that survives the
    merge are not rewritten.
13. DR #21, DR #25 — a dry run prints "foretold refusals in the home; see
    above" instead of "did not finish".
14. DR #23 — `rewrite_names` returns 1 when `renamed_lines` fails, before the
    `cmp`.
15. DR #40 — `merge_into`'s dry run prints `would move FROM -> TO` when FROM
    is empty.

Skill and tests:

16. DR #24 — `skills/migrate/SKILL.md` says a dry run can exit 0 where the
    real run refuses a merge between directories an earlier line creates.
17. DR #26 — `migrate-skill.test.sh` checks that the commit confirmation
    follows the real-run line.
18. DR #27 — the skill's announcement covers the repository, the home and
    darkmem.
19. DR #28 — `dforge-dir.test.sh` gains a mixed `.superpowers` + `.forge`
    case and a primary-checkout `.forge` case.

Check: every behaviour change above has a test in the owning suite that
fails before the change.

### P6. Config and plan tooling

Owns `scripts/lib/dforge-config.mjs`, `scripts/lib/dforge-env.sh`,
`scripts/plan-lint`, `scripts/plan-revise`, `scripts/lib/roadmap.sh`,
`tests/dforge-config.test.sh`, `tests/settings-skills.test.sh`,
`tests/plan-lint.test.sh`, `tests/plan-revise.test.sh`,
`tests/ladder.test.sh`, `tests/roadmap.test.sh`.

1. FS #7 — the dead `|| value=""` in `dforge-env.sh` is removed; the
   `[ -n "$value" ]` fallback stays. Check: read and the suite.
2. FS #9 — `realTarget` follows a chain of links to the first non-link or
   missing path, with a hop limit. Check: test with a dangling two-link
   chain.
3. FS #11 — when running as root, `writeFile` gives the temporary file the
   original's owner and group before the rename. Check: test, skipped when
   not root.
4. FS #34 — the per-key loop in `settings-skills.test.sh` matches a
   backticked key or `key=`, not the bare word. Check: the suite.
5. CX #9 — the fenced-header fixture asserts the pair and tier errors are
   suppressed and the summary reads 1 error. Check: the suite.
6. CX #10 — `plan-lint`'s `Host: codex` check and `plan-revise`'s
   `is_codex_plan` skip fenced lines. Check: a fenced-Host fixture.
7. CX #11 — the Routing-policy read allows a backticked value. Check:
   fixture.
8. CX #12 — `plan-lint` exits 2 with a clear message when the policy file
   cannot be read. Check: test.
9. CX #13 — Check only: a converted plan with a `## Policy conversion` record
   before `## Task index` lints clean.
10. TR #15 — `plan-revise.test.sh` uses `impl-sonnet-low` for total-2 tasks.
11. TR #16 — `ladder.test.sh` skips blank lines and reports every offending
    row. Check: the suite.
12. DM #34 — register rows are read with a delimiter that keeps empty cells
    in `plan-lint` and `roadmap.sh`, and `roadmap_unresolved` de-duplicates on
    `dforge_name_key`. Check: tests with an empty cell.

### P7. Validation, CI and evals

Owns `scripts/validate-repository.mjs`, `tests/repository-layout.test.mjs`,
`scripts/test-all.mjs`, `.github/workflows/validate.yml`,
`tests/marketplace-smoke.ps1`, `docs/testing/dual-client-marketplace-validation.md`,
`plugins/dforge/tests/review-route.test.sh`, `evals/controller/**`,
`evals/tiers/tests/cases.test.mjs`.

1. FS #4 — Check only: layout cases for a boolean entry with `unit` or
   `zero`, and a number entry with `floor` and `min: 1`.
2. DR #36 — the forge lookbehind drops `_` and the redundant `DR_FORGE`
   alternative goes. Check: layout cases for `my_forge_dir`.
3. DR #37 — Check only: layout cases for a forge name under
   `plugins/dforge/LICENSES/` and the dcc sweep's exemptions.
4. DR #38 — one shared exemption pattern; non-text files are skipped before
   lines are split. Check: layout case with a binary file.
5. DF #14 — the marketplace `plugin validate` step uses the same CLI version
   as the dforge step. Check: read; the row goes to `verify` until a CI run.
6. DF #15 — the smoke script's `superpowers@claude-plugins-official` check
   and its marketplace add are removed, and the validation doc's dependency
   bullet goes. Check: read (no PowerShell on this host).
7. DF #18 (doc half) — the validation doc says dforge's manifest.
8. RO #11 — `scripts/test-all.mjs` runs `tsc --noEmit -p plugins/dforge`,
   bounded, when `tsc` and the generated types exist, and prints a skipped
   line otherwise. Check: run it here (it prints the skipped line).
9. RO #27 — the transcript reader ignores `is_error` for Bash calls, so a
   ledger line written before a failing command is kept. Check: test.
10. RO #28 — `PER_TASK` accepts any path before the script name; a pilot
    test reaches the `unpriced` status. Check: tests.
11. DM #32 — `review-route.test.sh` reads the expected version from the
    manifest instead of pinning 4.1.0. Check: the suite.
12. DR #6 — Check only: a `…-dforge-<name>.md` slug case.

### P8. Release

Runs last, alone. Owns `config/schema.mjs` and, for this part only,
`scripts/lib/dforge-config.mjs`, `hooks/cockpit/config.ts`, the two
manifests and `README.md`.

1. DF #20 — the value check moves into `config/schema.mjs` and both
   `dforge-config.mjs` and the cockpit's `config.ts` call it; the validator
   keeps its own schema-level rules. Check: the dforge-config, layout and
   cockpit suites.
2. Version 4.2.0 in `.claude-plugin/plugin.json` and
   `.codex-plugin/plugin.json`, with a README entry for 4.2.0.
3. Register bookkeeping: every fixed row is `done` (DF 14 `verify`) and each
   bundle row closes; `scripts/register check` passes on all nine registers.
   That is the installed plugin's script: this repository keeps the
   `docs/superpowers/` layout, which the in-tree dforge copy resolves to a
   `docs/dforge/` that does not exist here, so every Covers path fails it.

## Parallel decomposition

There is no foundation part: no type, schema or file is shared between
parts in waves 1-4, and the one cross-part change (DF #20) is in P8.

| Wave | Parts | Why |
|---|---|---|
| 1 | P1, P3, P6, P7 | no risk work, no shared file |
| 2 | P4 | data loss: removes, renames and copies user documents |
| 3 | P5 | migration of homes and repositories |
| 4 | P2 | concurrency: the state file's lock |
| 5 | P8 | touches files P1 and P6 own |

Tests do not collide at run time: each suite makes its own temporary
directories, and the cockpit suite runs under `claude plugin test`. P3's text
changes name the P2 behaviours they describe (items 6, 7, 12, 15) as this spec
fixes them, so P3 consumes the spec, not P2's output.

## Testing

Each part runs its owning suites before and after (a behaviour change has a
test that fails first). After each wave merge: `node scripts/test-all.mjs`,
`node scripts/validate-repository.mjs`, `claude plugin validate` on the
marketplace and every Claude plugin, and `claude plugin test plugins/dforge`,
each with a timeout and nothing left running.

## Acceptance

A1. [test, high] Every item in P1-P8 is fixed as written and its Check
passes.
A2. [test, high] `node scripts/test-all.mjs`, `node
scripts/validate-repository.mjs`, `claude plugin validate` on the marketplace
and each Claude plugin, and `claude plugin test plugins/dforge` pass on the
merged branch.
A3. [read, high] No row in the nine registers is `deferred` except where a
later finding of this work adds one; DF 14 is `verify`; each closed-without-
code row carries its triage note; the installed plugin's `scripts/register
check` is clean on all nine (P8 item 3).
A4. [test, high] Both dforge manifests read 4.2.0 and the review-route suite
no longer pins a version.
A5. [read, medium] `skills/using-dforge/SKILL.md` is at most 5,100 bytes.

## Riskiest assumption

That the darkmem fixes (P4) change no behaviour a user relies on beyond what
each item names. Items 14, 17 and 20 change when files are removed, renamed
or copied; each needs a test that fails first and an implementer who re-reads
the surrounding refusal paths. The per-workstream `checkpointAt` (item 3) is
the one state-format change; an old state file must keep working.
