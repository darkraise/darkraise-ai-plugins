# Open rows sweep

**Execution strategy:** parallel — the fixes fall into seven areas that share
no file (darkmem sync, cockpit, migration and validator, plan tooling and
config, auto-run, evals, repository tooling and docs); the darkmem part
(state saves, link handling in the mirror move) runs alone in its own wave

**Registers:** `2026-09-23-codex-v3.md`, `2026-09-24-darkmem-mirror.md`,
`2026-10-11-dr-forge.md`, `2026-10-12-forge-settings.md`,
`2026-10-17-dforge-rename.md`, `2026-10-18-auto-execution-default.md`, all
under `docs/superpowers/registers/`; this spec is added to each one's
`**Covers:**` line

**Approach:** inline - skip 1: every finding was located in the current tree
by the 2026-10-20 triage, with file and line evidence and a fix sketch

## Decisions

The owner's answers on 2026-10-20.

1. Fix every finding the triage found still real, low as well as medium.
2. DF 14 closes `done` on the local run of the CI-pinned Claude Code.
3. DM 55: the documentation changes to the real 140 s bound; the push keeps
   its 100 s.
4. The not-a-defect and accepted findings close as proposed.
5. One spec and one plan, executed as parallel subagent waves.
6. Both design sections approved as presented.

## Problem

The deferred-rows sweep (2026-10-19) left 20 rows `open` and DF 14 in
`verify`: findings its task and final reviews filed against its own fixes.
A triage on 2026-10-20 checked each against the current tree. One finding is
medium (DM 52), the rest low; no finding can lose data. One row premise was
wrong: FS 49.b's throw is reachable at exactly 40 links. FS 48's premise, that
the kit cannot raise a person's close, is unsettled: the plugin API omits
`origin` from `$.ui.close` (`PaneCloseArgs`), while the test kit's `$` is the
engine's own and is not declared locally; P2 item 1 settles it with a probe.

## Scope

Short names: CX codex-v3, DM darkmem-mirror, DF dr-forge, FS forge-settings,
DR dforge-rename, AE auto-execution-default. Sub-findings are lettered in the
order the row lists them. Code paths are relative to `plugins/dforge/` unless
they start with `scripts/validate-repository.mjs`, `scripts/test-all.mjs`,
`tests/repository-layout.test.mjs`, `tests/marketplace-smoke.ps1`, `docs/` or
`evals/`, which are repository-relative.

**Closed when this spec is committed, before any code changes:**

- `done`: DF 14, acceptance amended to "the CI-pinned Claude Code's `plugin
  validate` passes on the marketplace and plugins/dforge", note citing the
  2026-10-20 local run with 2.1.295.
- `n/a`, note giving the triage's reason: DF 22 (narrowing is compile-time
  and sound on the true branch), DR 45 (a: a dry-run limit documented in the
  script header and the migrate skill; b: the double run is deliberate), AE
  41 (a stale `stallFailedAt` delays a nudge at most about 3 minutes, and only
  for a run started outside the session's turns; the double clock read is
  cosmetic).
- Accepted sub-findings, recorded in their row's note, the row staying open
  for its real ones: DM 59.a (every error reaching it carries `code`), DM 60.e
  (the 30 s runner bound keeps the test inside its 60 s window), FS 49.a (a
  test of a test), DR 43.a and 43.c (a dry run names where the file is now,
  the convention the "would rename" line already follows), AE 39.b (jq's
  stderr is `ar_create`'s only diagnostic).
- DM 25: a note that the Stop push's worst case is 140 s (30 s lookup and
  100 s push, each with a 5 s kill grace); its item text stays as written.

**Fixed by this work:** every other open row. Each gets `--assigned` naming
the plan, and moves to `done` when its last real sub-finding lands. DM 54
closes `n/a` (not reproduced) once its diagnostic lands.

## Design

Each item is `register #row — fix. Check:` the test or read that shows it.
Line numbers are the triage's; an implementer re-reads the code first.

### P1. Darkmem sync

Owns `scripts/lib/darkmem-pull.mjs`, `darkmem-sync.mjs`,
`darkmem-reconcile.mjs`, `darkmem-progress-move.mjs`, `darkmem-mirror.mjs`
(all in `scripts/lib/`), `tests/darkmem-sync/` except `migrate.test.mjs`, and
`README.md`. Runs alone in wave 2. Its suite runs include
`tests/darkmem-sync/migrate.test.mjs`, which imports P1's `helpers.mjs`.

1. DM 53, DM 60.c — the `persist` closure built in `darkmem-sync.mjs`
   (line 282) wraps a `saveState` write failure in a `StateError` naming the
   state file; `saveState` itself is unchanged, since
   `dforge-home-migrate.mjs` (P3) calls it directly. `main`'s `finally`
   (`darkmem-sync.mjs:318-332`) skips its own `saveState` when the run ended
   on that state-file `StateError`, and guards the save otherwise: a failed
   save prints one `darkmem-sync: <statePath> …` line and sets `code` to 2
   when it was 0. The lock is still released and the report lines (333-335)
   still print. So the run stops with exit 2 and one line instead of
   reporting written documents as "not pulled" (`pull:147`) or crashing
   (`removeVanished`, `recon:523`, and today's exit 4 from the `finally`).
   `StateError`'s export from `darkmem-mirror.mjs` is unchanged
   (`dforge-home-migrate.mjs` imports it). Check: a test turns
   `.sync-state.json` into a directory after the first document GET (pull)
   and from the hook on reconcile's final manifest read (the last request
   before the set-aside rename); each exits 2, prints one line naming the
   state file, the report lines gathered before it, and no "not pulled" line.
2. DM 52 — in `pullLedgers` (`pull:173-186`), `pullCheckpoint`
   (`pull:232-237`) and `progressToLocal`'s `renderCheckpoint` write
   (`pmove:400-403`), the read, write and `persist()` of each step sit in a
   try/catch that adds a "failed:" line and sets `report.partial`, as
   `pullDocuments` does; a `StateError` from item 1 still propagates.
   `darkmemRefusal` (`pmove:156-159`), which `progressToLocal`'s catch
   (`pmove:489-490`) calls, is unchanged: file-system errors no longer reach
   it because these try/catches handle them first. Check: tests where
   `work/sdd/k/progress.md` is a directory and where `sdd/k` is a file each
   exit 1 with a "failed:" line, and the document lines gathered before it
   are printed.
3. DM 54 — the assertion at `import.test.mjs:139` passes
   `result.stdout + result.stderr` as its message. Check: read.
4. DM 55 — `README.md` (line 326) states the Stop hook's worst case, 140 s:
   a 30 s config lookup and a 100 s push, each with a 5 s kill grace.
   `hooks.test.mjs` asserts the push's 100 s bound beside the lookup's 30 s
   (line 233). Check: the hooks test.
5. DM 59.b — the case-twin lookup (`pull:90`) uses a map from lower-cased
   uri to the list of non-archive filed uris, built once before the loop;
   the lookup picks an entry other than the vanished uri itself, since
   darkmem can hold two twins of one fold. Check: the existing case-twin
   test, plus one with two vanished documents.
6. DM 60.a — the recheck refusal (`recon:383`) also lists each uri added,
   removed or whose hash changed between `sent` and `again.documents`.
   Check: a document committed during the move is named.
7. DM 60.b — `statusLines` (`recon:238`) and the check at `recon:324` treat
   an entry as a rename or copy when either status column is `R` or `C`.
   Check: an intent-to-add rename (`git add -N`) gives one `" R … -> …"`
   line.
8. DM 60.d — `runGit` (`recon:29-31`) returns `result.error?.message`, used
   when stderr is empty. Check: a unit test of `runGit` (exported for it)
   with git stripped from `process.env.PATH` in-process gets a non-empty
   reason; the CLI cannot reach it without git, since `resolveStores` then
   answers local mode first, and a failing shim sets no `result.error`.
9. DM 61.a, 61.b, 61.j — one no-follow read helper in
   `darkmem-progress-move.mjs`, a `function` declaration (reconcile and the
   moves import each other, and `MOVES` at `recon:22-27` is built at module
   evaluation, so only hoisted declarations cross the cycle): open with
   `O_RDONLY | O_NOFOLLOW | O_NONBLOCK`, refuse unless `fstat` shows a
   regular file, then read. `ELOOP` from the open means a symbolic link; any
   other open error is the "could not be read" line. Where
   `fs.constants.O_NOFOLLOW` is undefined (Windows) it falls back to the
   current lstat-then-read. It guards the final path component only. It
   replaces the reads at `pmove:74/79`, `pmove:518/523`, the post-write
   checks at `pmove:314, 323, 546, 557`, and `inProgress`'s read
   (`recon:198`). Checks: a link to a named pipe swapped in from the stub's
   `onRequest` hook is refused within a few seconds at `progressToDarkmem`'s
   recheck (`pmove:314`, requests at 257-301 precede it) and at
   `inProgress` (`recon:198`) — these fail first; the checkout-side sites
   (518/523, 546/557) get the same case through the `offlineMove()` harness
   and `t.mock.method(fs, …)`, as `reconcile-progress.test.mjs:673-715`
   does; the existing linked-`progress.md` refusal
   (`reconcile-progress.test.mjs:636-650`) stays as a regression check; the
   Windows fallback has a unit test that stubs the constant away.
10. DM 61.c — `ledgerFiles` (`mirror:137-141`) is unchanged, since
    `localChanges`, `pushLedgers` and `gatherSources` would crash on a
    dangling link it no longer skipped. The two moves (`pmove:61` and
    `pmove:502`) list ledgers through their own lstat-based listing, so a
    dangling `progress.md` link reaches the link check. Check: a dangling
    `progress.md` link refuses the move; `status` still exits as before.
11. DM 61.d — the moved-aside path (`pmove:352-358`) writes the
    `.gitignore` files before it returns, and the count reads "1 source" /
    "N sources". Check: one blocked rename leaves the `.gitignore` written and
    the singular wording.
12. DM 61.e — satisfied by item 9: the helper replaces the separate
    `lstat` at `pmove:74` and `pmove:518`, and its open error (`EACCES`,
    `ENOTDIR`) is the problem line. Check: `t.mock.method(fs, 'openSync')`
    throwing `EACCES` lists a problem line, so the test does not depend on
    running as non-root.
13. DM 61.f — the refusal at `pmove:480` says "could not be listed" or
    "reached through symbolic links" according to the lines `mirrorLinks`
    returned. Check: an unlistable work directory.
14. DM 61.g — the changed-during-the-move refusal (`pmove:556`) also names
    the files already copied in that loop, as the catch at `pmove:562` does.
    Check: through `offlineMove()`, a mocked `mkdirSync` edits one target
    while another is copied; both are named (no request falls inside that
    loop, so the stub's hook cannot reach it).
15. DM 61.h — an `EEXIST` from the exclusive copy (`pmove:552`) reports
    "changed during the move". Check: through `offlineMove()`, a mocked
    `copyFileSync` throws `EEXIST`.
16. DM 61.i — `progressToDarkmem` checks `cfg.mirror`, its `work`
    directory and the plan directories for links (`mirrorLinks` or a lstat
    of the path) before `checkProgressTargets`. Check: a linked `work/sdd/k`
    refuses the move.
17. DM 61.j (adjacent) — `dirEntries` (`recon:38`) counts a plan directory
    reached through a link as in progress, without reading through it (item
    9's helper still follows a linked directory in the path), so it blocks a
    documents move. Check: an `sdd/k` link whose target holds a finished
    ledger refuses a documents move and names the link; today the move
    proceeds.

### P2. Cockpit

Owns `tests/cockpit.test.ts`.

1. FS 48 — first a one-line probe under `claude plugin test`: does the kit's
   `$.ui.close` accept `origin: { kind: 'person' }` and reach the mod's
   `ui.close` hook? If yes, a test modelled on the one at
   `cockpit.test.ts:3612` replaces the
   `settings-back` close with the engine's own `$.ui.close({ id: 'dforge',
   origin: { kind: 'person' } })`, and asserts the settings note is appended
   once and the pane does not reopen. If the kit refuses that call, the task
   reports BLOCKED with the refusal; it does not work around it.

### P3. Migration and validator

Owns `scripts/lib/dforge-home-migrate.mjs`,
`tests/darkmem-sync/migrate.test.mjs`, `tests/migrate-skill.test.sh`,
`scripts/validate-repository.mjs`, `tests/repository-layout.test.mjs`.

1. DR 43.b — a read error from `readJson` (`dforge-home-migrate.mjs:118-124`)
   at the config merge (187-188) becomes a `refuse(...)` and `continue`, as
   the other refusals in that loop do; at the old config (265), the current
   `~/.dforge/config.json` in the darkmem-copy block (269) and `stores.json`
   (305), none inside a loop, it refuses and skips that block. Checks:
   `~/.dr-forge/config.json` holding `{not json` beside a
   `~/.dforge/config.json` and an `only-old.txt` gives one refusal, moves
   `only-old.txt`, and the dry run prints the same refusal; a malformed
   `~/.dforge/config.json` with no `~/.dr-forge/config.json` and a darkmem
   mapping in `~/.dr-superpowers/config.json` gives one refusal and the run
   finishes.
2. DR 43.d — an array variant of the darkmem-copy test (`migrate.test.mjs`
   line 426): the file is unchanged and no "copied" line appears.
3. DR 46 — `present "asks before committing" "$SKILL" "human partner agrees,
   and stage nothing"` above the ordering check (`migrate-skill.test.sh:30`).
   Check: the suite fails with "human partner agrees" temporarily removed
   from `skills/migrate/SKILL.md` (the suite reads that path, line 9) and
   passes once it is restored.
4. DR 47.a — `textLines` (`scripts/validate-repository.mjs:12`) decodes a
   file starting with a UTF-16 byte-order mark (`FF FE`, `FE FF`) as UTF-16
   before the NUL-byte rule. Check: a UTF-16LE fixture with a BOM holding
   `dr-forge` reports an error.
5. DR 47.b — the binary fixture (`repository-layout.test.mjs:145`) puts the
   NUL mid-file, e.g. `'superpowers dr-forge\u0000 dcc-darkraise-ui\n'`.
   Check: the test.

### P4. Plan tooling and config

Owns `scripts/plan-lint`, `tests/plan-lint.test.sh`,
`scripts/lib/dforge-config.mjs`, `tests/dforge-config.test.sh`.

1. CX 16.a — `plan-lint` (lines 78-80) checks `command -v jq` first; with jq
   present, an empty version says the routing file "cannot be parsed" or
   "has no version" (`jq empty` decides which). The existing case at
   `plan-lint.test.sh:472-478` is a failing-jq shim, so it becomes the
   "cannot be parsed" branch; the new message keeps its needle "cannot read
   the routing policy version from" (line 477). Checks: a version-less file
   and a corrupt file each name their cause and not "jq installed"; a true
   no-jq case runs with a `PATH` directory of links to the other tools the
   script needs, without jq.
2. CX 16.b — the suite exports `HOME="$TMP/home"` once at its top; the
   name-key cases keep their own `HOME`. Check: the suite passes when started
   with `HOME` pointing at a scratch directory whose `.dforge/config.json` is
   malformed; the developer's real `~/.dforge` is never touched.
3. FS 49.b — the link-hop loop (`dforge-config.mjs:115-123`) also follows
   the 40th hop (`hop <= MAX_LINK_HOPS`). Check: a write through a 40-link
   dangling chain lands on the chain's final path.

### P5. Auto-run

Owns `tests/auto-run.test.sh`, `scripts/session-start.sh`,
`tests/turn-end.test.sh`.

1. AE 39.a — in the `flock` variant (`auto-run.test.sh:287, 307`) the holder
   touches `$STATE.ready` once it holds the lock, and the test waits for that
   file instead of `sleep 0.5`. The test removes `$STATE.ready` before
   starting each holder, and the wait fails the case after 10 s rather than
   hanging. Check: the suite.
2. AE 39.c — `session-start.sh`'s persistence block (sessions, cockpit and
   turns directories, lines 23-56) runs only when `HOME` is non-empty.
   Check: a `turn-end.test.sh` case with `HOME=` puts logging `mkdir` and
   `find` shims on `PATH` (as `tests/darkmem-sync/hooks.test.mjs:222-227`
   does for `timeout`), asserts no logged argument starts with `/.claude`,
   and that the injection still prints; it holds whether or not the suite
   runs as root, and never writes `/.claude` on the host.

### P6. Evals

Owns `evals/controller/lib/sessions.mjs`, `evals/controller/lib/transcript.mjs`,
`evals/controller/tests/sessions.test.mjs`,
`evals/controller/tests/transcript.test.mjs`.

1. DF 24.a — `sessions.test.mjs` asserts `cat $S/task-brief docs/plans/x.md`
   and `sed -n 1p …/task-brief x.md` yield no slug; if either matches, the
   pattern (`sessions.mjs:18`) requires `bash` or command position.
2. DF 24.b — a `planSlugs` unit test for `S=/p/scripts; bash $S/task-brief
   docs/plans/x.md 1`.
3. DF 24.c — `transcript.mjs:134` splits the command on shell list
   separators (`;`, newline, and an `&` that is not part of `&&`); for each
   list holding a ledger redirect it asks whether an `&&` precedes that
   redirect inside the list, and counts the "Task N: complete" hits of that
   list only. Check: `echo 'Task 1: complete …'
   >> progress.md; false && echo 'Task 2: complete …' >> progress.md` counts
   Task 1 only, and `x && y; echo 'Task 3: complete …' >> progress.md;
   false` counts Task 3.

### P7. Repository tooling and docs

Owns `scripts/test-all.mjs`, `tests/marketplace-smoke.ps1`,
`docs/testing/dual-client-marketplace-validation.md`.

1. DF 21 — on `win32`, `test-all.mjs` probes and runs tsc through
   `process.env.ComSpec ?? 'cmd.exe'` with `/d /s /c tsc …`: Node refuses to
   spawn a `.cmd` file without a shell (`EINVAL` since the April 2024
   security releases), and `run` needs no new option. The skip reason reads
   "tsc not found". Check: Windows only; the task reports it unverified on
   this host, and `node scripts/test-all.mjs --list` still lists the tsc job
   on Linux.
2. DF 23.b — the blank line before the `git init` block (about line 104) is
   restored.
3. DF 23 (adjacent) — the "Verified outcomes" bullets 03765c6 rewrote are
   labelled current-state notes, not results of the 2026-09-08 run. Check:
   read.

### P8. Release

Runs last, alone. Owns `.claude-plugin/plugin.json` and
`.codex-plugin/plugin.json` of `plugins/dforge`.

1. Version 4.2.1 in both manifests.
2. Register bookkeeping: dr-superpowers:finishing-a-development-branch
   resolves every row the plan covers. The repository's `scripts/register
   check` cannot judge these registers (it resolves `docs/dforge/`, which
   this repository does not use); the check is A3's grep.

## Parallel decomposition

No foundation part: P1's `StateError` change stays inside its own files, and
P3 imports nothing P1 changes. P3's `migrate.test.mjs` imports P1's
`tests/darkmem-sync/helpers.mjs`; wave 1 leaves that file untouched, and P1's
wave-2 runs include `migrate.test.mjs`.

| Wave | Parts | Why |
|---|---|---|
| 1 | P2, P3, P4, P5, P6, P7 | no risk work, no shared file |
| 2 | P1 | state saves and link handling in the mirror move |
| 3 | P8 | the version files |

Tests do not collide at run time: each suite makes its own temporary
directories (P4 item 2 gives plan-lint one for `HOME`), and the cockpit suite
runs under `claude plugin test`.

## Testing

Each part runs its owning suites before and after; a behaviour change has a
test that fails first. After each wave merge: `node scripts/test-all.mjs`,
`node scripts/validate-repository.mjs`, `claude plugin validate` on the
marketplace and every Claude plugin, and `claude plugin test plugins/dforge`,
each with a timeout and nothing left running.

## Acceptance

A1. [test, high] Every item in P1-P8 is fixed as written and its Check
passes, except P7 item 1's Windows run, reported unverified.
A2. [test, high] `node scripts/test-all.mjs`, `node
scripts/validate-repository.mjs`, `claude plugin validate` on the marketplace
and each Claude plugin, and `claude plugin test plugins/dforge` pass on the
merged branch.
A3. [read, high] `grep '| open |'` over the six registers finds no row except
one a later finding of this work adds; DF 14 is `done`; each row closed
without code carries a `triage 2026-10-20` note; every row has six cells.
A4. [test, high] Both dforge manifests read 4.2.1.

## Riskiest assumption

That the no-follow read (P1 item 9) behaves the same on macOS and Linux and
degrades to today's behaviour on Windows. `O_NOFOLLOW` on a link fails with
`ELOOP` on Linux and macOS; the helper treats that as "a symbolic link" and
any other open error as a read error. A Windows run of the darkmem suites is
not available on this host, so the fallback is covered by a unit test that
stubs the constant away.

## Review rulings

Fable review, 2026-10-20 (commit a7f8384, verdict: revise), all applied:

- H1, `main`'s `finally` re-saved the unwritable state and exited 4: it
  skips or guards the save (P1.1).
- H2, spawning `tsc.cmd` without a shell throws `EINVAL`: tsc runs through
  `cmd.exe` on Windows (P7.1).
- M1, `ledgerFiles` has three other callers: it stays, the moves list
  ledgers themselves (P1.10).
- M2, no request falls inside several race windows: those Checks use
  `offlineMove()` and `fs` mocks, and each FIFO site is named (P1.1, 9, 14,
  15).
- M3, `runGit` is unreachable without git through the CLI: a unit test
  (P1.8).
- M4, the `&&` rule contradicted its own Check: split on list separators
  (P6.3).
- M5, the empty-`HOME` Check could not fail as non-root: `mkdir` and `find`
  shims (P5.2).
- M6, a leftover ready file: removed before each holder, 10 s bound (P5.1).
- M7, line 269 was unguarded: added, with its variant (P3.1).
- L1 the FS 48 premise is unsettled: a probe first (Problem, P2.1); L2 the
  FIFO cases are the fails-first ones (P1.9); L3 item 12 is the helper's
  error path (P1.12); L4 `darkmemRefusal` is unchanged (P1.2); L5 the map's
  shape (P1.5); L6 the failing-jq case and its needle (P4.1); L7 the
  consent Check edits the real skill temporarily (P3.3); L8 item 17's Check
  (P1.17); L9 the helper is a function declaration (P1.9); L10 P1's runs
  include `migrate.test.mjs` (P1, Parallel decomposition).
