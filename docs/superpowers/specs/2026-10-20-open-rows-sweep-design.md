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
medium (DM 52), the rest low; no finding can lose data. Two row premises were
wrong: FS 48's test is feasible (the kit's `$.ui.close` takes a person
origin), and FS 49.b's throw is reachable at exactly 40 links.

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
`README.md`. Runs alone in wave 2.

1. DM 53, DM 60.c — the `persist` closure built in `darkmem-sync.mjs`
   (line 282) wraps a `saveState` write failure in a `StateError` naming the
   state file; `saveState` itself is unchanged, since
   `dforge-home-migrate.mjs` (P3) calls it directly. So the run
   stops with exit 2 and one line instead of reporting written documents as
   "not pulled" (`pull:147`) or crashing (`removeVanished`, `recon:523`).
   `StateError`'s export from `darkmem-mirror.mjs` is unchanged
   (`dforge-home-migrate.mjs` imports it). Check: a test turns
   `.sync-state.json` into a directory after the first document GET (pull)
   and right after the set-aside rename (reconcile); each prints one line
   naming the state file and no "not pulled" line.
2. DM 52 — in `pullLedgers` (`pull:173-186`), `pullCheckpoint`
   (`pull:232-237`) and `progressToLocal`'s `renderCheckpoint` write
   (`pmove:400-403`), the read, write and `persist()` of each step sit in a
   try/catch that adds a "failed:" line and sets `report.partial`, as
   `pullDocuments` does; a `StateError` from item 1 still propagates.
   `progressToLocal`'s catch (`pmove:489-490`) keeps re-throwing only what
   is neither a darkmem error nor a file-system error. Check: tests where
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
   uri to uris built once before the loop. Check: the existing case-twin
   test, plus one with two vanished documents.
6. DM 60.a — the recheck refusal (`recon:383`) also lists each uri added,
   removed or whose hash changed between `sent` and `again.documents`.
   Check: a document committed during the move is named.
7. DM 60.b — `statusLines` (`recon:238`) and the check at `recon:324` treat
   an entry as a rename or copy when either status column is `R` or `C`.
   Check: an intent-to-add rename (`git add -N`) gives one `" R … -> …"`
   line.
8. DM 60.d — `runGit` (`recon:29-31`) returns `result.error?.message`, used
   when stderr is empty. Check: with no git on `PATH` the reason is not
   empty.
9. DM 61.a, 61.b, 61.j — one no-follow read helper in
   `darkmem-progress-move.mjs`: open with `O_RDONLY | O_NOFOLLOW |
   O_NONBLOCK`, refuse unless `fstat` shows a regular file, then read. Where
   `fs.constants.O_NOFOLLOW` is undefined (Windows) it falls back to the
   current lstat-then-read. It replaces the reads at `pmove:74/79`,
   `pmove:518/523`, the post-write checks at `pmove:314, 323, 546, 557`, and
   `inProgress`'s read (`recon:198`), which reconcile imports. Check: a
   linked `progress.md` is refused, and a link to a named pipe swapped in
   from the stub's `onRequest` hook is refused within a few seconds.
10. DM 61.c — `ledgerFiles` (`mirror:140`) filters with `lstatSync(…,
    { throwIfNoEntry: false })`. Check: a dangling `progress.md` link
    refuses the move.
11. DM 61.d — the moved-aside path (`pmove:352-358`) writes the
    `.gitignore` files before it returns, and the count reads "1 source" /
    "N sources". Check: one blocked rename leaves the `.gitignore` written and
    the singular wording.
12. DM 61.e — the `lstat` calls at `pmove:74` and `pmove:518` move inside
    the read-error try/catch, so `EACCES` or `ENOTDIR` lists a problem line.
    Check: a directory that can be listed but not entered; the test skips
    when the suite runs as root.
13. DM 61.f — the refusal at `pmove:480` says "could not be listed" or
    "reached through symbolic links" according to the lines `mirrorLinks`
    returned. Check: an unlistable work directory.
14. DM 61.g — the changed-during-the-move refusal (`pmove:556`) also names
    the files already copied in that loop, as the catch at `pmove:562` does.
    Check: one file changes while another was copied; both are named.
15. DM 61.h — an `EEXIST` from the exclusive copy (`pmove:552`) reports
    "changed during the move". Check: the target is created from the stub's
    `onRequest` hook.
16. DM 61.i — `progressToDarkmem` checks `cfg.mirror`, its `work`
    directory and the plan directories for links (`mirrorLinks` or a lstat
    of the path) before `checkProgressTargets`. Check: a linked `work/sdd/k`
    refuses the move.
17. DM 61.j (adjacent) — `dirEntries` (`recon:38`) counts a plan directory
    reached through a link as in progress, so it blocks a documents move.
    Check: test.

### P2. Cockpit

Owns `tests/cockpit.test.ts`.

1. FS 48 — a test modelled on the one at `cockpit.test.ts:3612` replaces the
   `settings-back` close with the engine's own `$.ui.close({ id: 'dforge',
   origin: { kind: 'person' } })`, and asserts the settings note is appended
   once and the pane does not reopen. If the kit refuses that call, the task
   reports BLOCKED with the refusal; it does not work around it.

### P3. Migration and validator

Owns `scripts/lib/dforge-home-migrate.mjs`,
`tests/darkmem-sync/migrate.test.mjs`, `tests/migrate-skill.test.sh`,
`scripts/validate-repository.mjs`, `tests/repository-layout.test.mjs`.

1. DR 43.b — a read error from `readJson` (`dforge-home-migrate.mjs:118-124`)
   at the config merge (187-188), the old config (265) and `stores.json`
   (305) becomes a `refuse(...)` and `continue`, as the other refusals do.
   Check: `~/.dr-forge/config.json` holding `{not json` beside a
   `~/.dforge/config.json` and an `only-old.txt` gives one refusal, moves
   `only-old.txt`, and the dry run prints the same refusal.
2. DR 43.d — an array variant of the darkmem-copy test (`migrate.test.mjs`
   line 426): the file is unchanged and no "copied" line appears.
3. DR 46 — `present "asks before committing" "$SKILL" "human partner agrees,
   and stage nothing"` above the ordering check (`migrate-skill.test.sh:30`).
   Check: the suite fails on a scratch copy with "human partner agrees"
   removed.
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
   "has no version" (`jq empty` decides which). Check: beside the no-jq case
   (`plan-lint.test.sh:472`), a version-less file and a corrupt file each
   name their cause and not "jq installed".
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
   file with a bound instead of `sleep 0.5`. Check: the suite.
2. AE 39.c — `session-start.sh`'s persistence block (sessions, cockpit and
   turns directories, lines 23-56) runs only when `HOME` is non-empty.
   Check: a `turn-end.test.sh` case with `HOME=` and a scratch root creates
   nothing and still prints the injection.

### P6. Evals

Owns `evals/controller/lib/sessions.mjs`, `evals/controller/lib/transcript.mjs`,
`evals/controller/tests/sessions.test.mjs`,
`evals/controller/tests/transcript.test.mjs`.

1. DF 24.a — `sessions.test.mjs` asserts `cat $S/task-brief docs/plans/x.md`
   and `sed -n 1p …/task-brief x.md` yield no slug; if either matches, the
   pattern (`sessions.mjs:18`) requires `bash` or command position.
2. DF 24.b — a `planSlugs` unit test for `S=/p/scripts; bash $S/task-brief
   docs/plans/x.md 1`.
3. DF 24.c — `transcript.mjs:134` splits the command at each ledger redirect
   and decides the `&&` question per segment, counting the "Task N:
   complete" hits of that segment only. Check: `echo 'Task 1: complete …'
   >> progress.md; false && echo 'Task 2: complete …' >> progress.md` counts
   Task 1 only, and `x && y; echo 'Task 3: complete …' >> progress.md;
   false` counts Task 3.

### P7. Repository tooling and docs

Owns `scripts/test-all.mjs`, `tests/marketplace-smoke.ps1`,
`docs/testing/dual-client-marketplace-validation.md`.

1. DF 21 — on `win32`, `test-all.mjs` probes and runs `tsc.cmd`, and the
   skip reason reads "tsc not found". Check: Windows only; the task reports
   it unverified on this host, and `node scripts/test-all.mjs --list` still
   lists the tsc job on Linux.
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
P3 imports nothing P1 changes.

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
