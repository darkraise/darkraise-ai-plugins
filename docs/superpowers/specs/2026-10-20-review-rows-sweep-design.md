# Review rows sweep

**Execution strategy:** parallel — the darkmem part (reads in the mirror
moves) runs alone in wave 1; the executor probe, the eval parser and the
config test share no file and run together in wave 2

**Registers:** `2026-09-23-codex-v3.md`, `2026-09-24-darkmem-mirror.md`,
`2026-10-11-dr-forge.md`, `2026-10-12-forge-settings.md`, all under
`docs/superpowers/registers/`; this spec is added to each one's `**Covers:**`
line

**Approach:** inline - skip 1: every row was located in the current tree by
the 2026-10-20 triage, with file and line evidence and a fix sketch; the one
open approach (DM 64) was ruled by the owner

## Decisions

The owner's answers on 2026-10-20.

1. DM 64: `auto-run.json` is read following links and without blocking; a
   record that is not a regular file reads as no active run.
2. DF 26: the five sub-findings are fixed, then bounded by a constraint (P3
   item 6).
3. DF 21 stays `verify`, owed a Windows run by the owner.
4. DF 27: ripgrep is installed on this host and the test is run here.
5. One spec and one plan, executed as parallel subagent waves.
6. Both design sections approved as presented.

## Problem

The open-rows sweep (2026-10-20) left eight rows `open` and DF 21 in
`verify`: findings its final review filed, an adjacent finding from drafting
its plan (CX 17), and one Windows check this host cannot run. A triage on
2026-10-20 confirmed all nine against main at e2965b1. None can lose data:
the worst, DM 62 and DM 64, hang reconcile on a named pipe, and DM 63 exits 4
with nothing staged. The triage found four more plain reads in the same two
modules that block on a named pipe; P1 fixes them with the rows they share a
cause with.

## Scope

Short names: CX codex-v3, DM darkmem-mirror, DF dr-forge, FS forge-settings.
Sub-findings are lettered in the order the row lists them. Code paths are
relative to `plugins/dforge/` unless they start with `evals/` or `docs/`,
which are repository-relative.

**Not closed by code:**

- DF 21 stays `verify`. Its note is set to: "owed: on a Windows machine with
  the generated types (Claude Code writes them when it loads plugins/dforge
  from the folder), `node scripts/test-all.mjs` runs the tsc job rather than
  skipping it". The CI Windows job cannot settle it: it installs no tsc and
  has no generated types.
- DF 27 closes `done` on P6's local run.

## Design

### P1. Darkmem reads

Owns `scripts/lib/darkmem-progress-move.mjs`,
`scripts/lib/darkmem-reconcile.mjs` and `tests/darkmem-sync/`.

1. **Helper.** `readRegular(file, { follow = false } = {}, constants =
   fs.constants)`, exported from `darkmem-progress-move.mjs` as a function
   declaration (the import cycle with `darkmem-reconcile.mjs` needs it
   hoisted). It opens with `O_RDONLY | O_NONBLOCK`, adding `O_NOFOLLOW` when
   `follow` is false, `fstat`s the descriptor and throws `EISDIR` or `EFTYPE`
   for anything not a regular file, then reads from the descriptor. When
   `constants.O_NONBLOCK` is undefined (Windows, which has no FIFO files) it
   keeps today's path: an `lstat` refusal of a link when `follow` is false,
   then `readFileSync`. `readNoFollow(file, constants)` stays, as
   `readRegular(file, { follow: false }, constants)`, so its callers and
   tests do not change. Check: unit tests for a FIFO (both `follow` values),
   a link (`ELOOP` only without `follow`), a directory, and the stubbed
   constants path.
2. **DM 62.** `checkProgressTargets` (about line 173) and `progressToLocal`'s
   target pre-check (about line 618) read through `readRegular` (no follow).
   `ENOENT` keeps its meaning at each site; any other error joins the
   existing problems list with its code. Check: a FIFO at the mirror's
   `work/<rel>` and one at the checkout's `handoff.md`; reconcile finishes
   with the named problem.
3. **Adjacent.** `renderCheckpoint` (about line 457) reads the mirror's
   `handoff/latest.md` through `readRegular` (no follow); the killed-run
   comparison in `documentsToLocal` (about line 537) reads both sides through
   it (no follow) and names an unreadable file as differing. Check: a FIFO at
   each path; reconcile finishes with the failure or the differing line.
4. **DM 64 and adjacent, following links.** `inProgress`'s `auto-run.json`,
   `planFinished`'s `completed.md` and `fileHash` read through
   `readRegular(file, { follow: true })`. A non-regular `auto-run.json` reads
   as no active run; the existing comment gains why that holds (`auto-run.sh`
   writes the record with tmp+mv, which replaces whatever is at the path, so
   a pipe can never hold a run). An unreadable `completed.md` still reads as
   not finished. `fileHash` keeps `NOT_A_FILE` for a non-regular file and
   `null` for a missing one. Check: a FIFO at each path; a linked
   `auto-run.json` with `active: true` still refuses the move.
5. **DM 63.** `uncarried()` calls `lstatSync(at, { throwIfNoEntry: false })`;
   a missing component returns "missing from the working tree".
   `carriedDocuments` reads each document through `readRegular` (no follow)
   inside a try and refuses with "could not be read (CODE)". On the second
   pass both land in `uncarriable`, so the drift check reports "changed
   during the move" and nothing is staged. Check: a tracked document deleted
   between the pull and the recheck (the suite's pull hook, or an `fs` mock
   if none reaches that window) gives the "changed during the move" refusal,
   exit 0, and `git status` shows nothing staged.
6. **DM 65.** The second mirror-link check in `progressToDarkmem` (about
   line 375) refuses with "nothing was moved locally, and darkmem keeps what
   it accepted", the wording the module already uses after a partial
   refusal. Its first check (about line 302) keeps "nothing was sent or
   moved". Check: `reconcile-progress.test.mjs`'s assertions for the relink
   case (about lines 570 and 776) are updated to the new wording, and the
   pre-send case still asserts the old one.

FIFO checks skip on Windows.

### P2. Executor probe

Owns `scripts/detect-executors.sh` and `tests/executors.test.sh`.

1. **CX 17.** The probe request is built with `jq -nc --arg op "$probe_op"
   --arg cwd "$(dr_native_path "$PWD")" '{op:$op,cwd:$cwd}'`. Check:
   detection run from a directory whose name holds `"` and `\` passes the
   stub probe (`tests/fixtures/executors/bin/stub-probe.mjs`) valid JSON
   carrying the exact path, and `auth_status` is not `probe_failed`. The
   check skips on Windows, where those names are not allowed.

### P3. Eval parser

Owns `evals/controller/lib/sessions.mjs`,
`evals/controller/lib/transcript.mjs` and `evals/controller/tests/`.

1. **DF 26.a, c.** A `bash` or `sh` invocation is not a run when any
   short-flag cluster holds `n` (`-n`, `-nx`, `-en`) or when `-o noexec` is
   given; a `-o` still consumes its value. Check: `bash -nx`, `bash -en`
   and `bash -o noexec` before a script path count no run; `bash -eo
   pipefail` still counts one.
2. **DF 26.b.** A ledger write after `||` in the same list is not counted.
   Check: `true || echo "Task 3: complete" >> progress.md` counts no write;
   `git commit && echo "Task 3: complete" >> progress.md` still counts one.
3. **DF 26.d.** A `{ …; }` group piped to `tee -a` on the ledger counts the
   write. Check: `{ git commit && echo "Task 8: complete"; } | tee -a
   progress.md` counts one.
4. **DF 26.e.** The `<<-'EOF'` test is rewritten to fail without the tab
   handling: its body holds a line that equals the delimiter only once
   leading tabs are stripped, with a counted command after it. Check: the
   test fails with the tab stripping reverted and passes with it.
5. Every case above has a test in the owning test file.
6. **Bound.** `docs/superpowers/distilled/constraints.md` gains: "Eval
   parser shapes: a shell shape the controller's parser miscounts is fixed
   only when it appears in a real controller transcript; a shape found by
   review alone closes `n/a` citing this constraint. Set by: owner,
   2026-10-20 review-rows sweep. Scope: `evals/controller/lib/`. Source:
   this spec." P3 owns that file.

### P4. Config chain cap

Owns `tests/dforge-config.test.sh`.

1. **FS 50.** A 41-link dangling chain makes `fc set` exit non-zero and
   creates nothing at the chain's end. The 40-link `fc set` and its `$?`
   check share one line, as the file's refusal checks do. Check: the new
   test fails with `MAX_LINK_HOPS` raised to 41 and passes as shipped.

### P5. Release

Runs last, alone. Owns `.claude-plugin/plugin.json` and
`.codex-plugin/plugin.json` of `plugins/dforge`.

1. Version 4.2.2 in both manifests.
2. Register bookkeeping: dr-superpowers:finishing-a-development-branch
   resolves every row the plan covers, and sets DF 21's note as in Scope.

### P6. Host check (DF 27)

No repository files. Runs in wave 3 beside P5.

1. `apt-get install -y ripgrep` on this host (a system change outside the
   repository). The `rg` shell function still shadows the binary in
   interactive shells; the test's `bash -c 'command -v rg'` sees the binary.
2. `node --test tests/ui-discovery.test.mjs` runs the Win32 discovery test
   rather than skipping it, and passes. DF 27 closes `done` on that output.

## Parallel decomposition

No foundation part: nothing in P2-P4 imports P1's modules, and P3's
constraint line is the only `docs/` file any part writes.

| Wave | Parts | Why |
|---|---|---|
| 1 | P1 | reads in the mirror moves, which stage a document deletion |
| 2 | P2, P3, P4 | no risk work, no shared file |
| 3 | P5, P6 | the version files; a host check with no files |

Tests do not collide at run time: each suite makes its own temporary
directories, and the FIFOs live inside P1's.

## Testing

Each part runs its owning suites before and after; a behaviour change has a
test that fails first. After each wave merge: `node scripts/test-all.mjs`,
`node scripts/validate-repository.mjs`, `claude plugin validate` on the
marketplace and every Claude plugin, and `claude plugin test plugins/dforge`,
each with a timeout and nothing left running.

## Acceptance

A1. [test, high] Every item in P1-P6 is fixed as written and its Check
passes.
A2. [test, high] `node scripts/test-all.mjs`, `node
scripts/validate-repository.mjs`, `claude plugin validate` on the marketplace
and each Claude plugin, and `claude plugin test plugins/dforge` pass on the
merged branch.
A3. [read, high] `grep '| open |'` over the four registers finds no row
except one a later finding of this work adds; DF 21 is `verify` with the
Scope note; every row has six cells.
A4. [test, high] Both dforge manifests read 4.2.2.

## Riskiest assumption

That opening a FIFO with `O_RDONLY | O_NONBLOCK` returns at once on Linux and
macOS when no writer is attached, so `fstat` can refuse it before any read.
POSIX specifies that for a read-only non-blocking open; the P1 item 1 unit
test is the check on this host, and macOS is unverified here.
