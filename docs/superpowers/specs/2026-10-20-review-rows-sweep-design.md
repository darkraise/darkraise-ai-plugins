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
2. DF 26: sub-findings a, c and e are fixed, then bounded by a constraint
   (P3 item 5). Amended after the Fable review: b and d close `n/a` (see
   Scope).
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
with nothing staged. The triage found more plain reads in the same two
modules: three block on a named pipe (`renderCheckpoint`, `planFinished`,
and the checkout side of `documentsToLocal`'s killed-run comparison), and
two read after a `stat` that a swap can race (`fileHash`, and
`carriedDocuments`' document read). P1 fixes them with the rows they share a
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
- DF 26 closes `done` on P3, its note recording two sub-findings as `n/a`:
  b, because a successful call's `true || echo … >> progress.md` cannot be
  told by syntax from `grep -q 'Task N' progress.md || echo …`, which does
  write, and a failed call's `||` write is counted on purpose
  (`evals/controller/tests/transcript.test.mjs` case o1); d, not a defect,
  since the `{ …; } | tee -a` shape is counted on a successful call and
  correctly not on a failed one, whose `&&` gated the echo (case f2).

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
   `constants.O_NOFOLLOW` or `constants.O_NONBLOCK` is undefined (both are
   on Windows, which has no FIFO files) it keeps today's path: an `lstat`
   refusal of a link when `follow` is false, then `readFileSync`. Keying on
   either keeps the existing Windows-stub test
   (`reconcile-progress.test.mjs`, about line 375), which stubs only
   `O_NOFOLLOW`. `readNoFollow(file, constants)` stays, as
   `readRegular(file, { follow: false }, constants)`, so its callers and
   tests do not change. Check: unit tests for a FIFO (both `follow` values),
   a link (`ELOOP` only without `follow`), a directory, and the stubbed
   constants path with each constant removed.
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
   the mirror's `handoff/latest.md`, and one at the comparison's `dest` (the
   repository's `docs/dforge/…` copy); reconcile finishes with the failure or
   the differing line. The mirror side of the comparison cannot hold a FIFO
   (`listDocumentFiles` in `darkmem-mirror.mjs` lists regular files only), so
   it is reached through `t.mock.method(fs, …)` as the suite's race tests do.
4. **DM 64 and adjacent, following links.** `inProgress`'s `auto-run.json`,
   `planFinished`'s `completed.md` and `fileHash` read through
   `readRegular(file, { follow: true })`. A non-regular `auto-run.json` reads
   as no active run; the existing comment gains why that holds (`auto-run.sh`
   writes the record with tmp+mv, which replaces a link or a pipe at the
   path, so a pipe can never hold a run). An unreadable `completed.md` still
   reads as not finished. `fileHash` keeps `NOT_A_FILE` for a non-regular
   file and `null` for a missing one. Check: a FIFO at `auto-run.json` and
   at `completed.md` (both hang before the fix). Regression guards, which
   pass before the fix: a linked `auto-run.json` with `active: true` still
   refuses the move, and a FIFO at a `fileHash` path still reads as
   `NOT_A_FILE`. The swap between `fileHash`'s `stat` and its read is
   reached through `t.mock.method(fs, …)`.
5. **DM 63.** `uncarried()` calls `lstatSync(at, { throwIfNoEntry: false })`;
   a missing component returns "missing from the working tree".
   `carriedDocuments` reads each document through `readRegular` (no follow)
   inside a try and refuses with "could not be read (CODE)". On the second
   pass both land in `uncarriable`, so the drift check reports
   "`<uri>`: changed during the move" (the intended wording for a deleted
   file too: the uri is still tracked) and nothing is staged. Check: a
   tracked document deleted between the pull and the recheck (the suite's
   pull hook, or an `fs` mock if none reaches that window) gives that
   refusal, exit 1, and `git status` shows nothing staged. The read's
   `could not be read` path, whose `lstat` check runs first, is reached
   through `t.mock.method(fs, …)`.
6. **DM 65.** The second mirror-link check in `progressToDarkmem` (about
   line 375) refuses with "nothing was moved locally, and darkmem keeps what
   it accepted", the wording the module already uses after a partial
   refusal. Its first check (about line 302) keeps "nothing was sent or
   moved". Check: `reconcile-progress.test.mjs`'s relink assertion (about
   line 570, a link swapped in on `POST /api/v1/documents`) is updated to the
   new wording; the pre-send loop (about lines 770-779) keeps the old one.

FIFO checks skip on Windows.

### P2. Executor probe

Owns `scripts/detect-executors.sh` and `tests/detect.test.sh`.

1. **CX 17.** The probe request is built with `jq -nc --arg op "$probe_op"
   --arg cwd "$(dr_native_path "$PWD")" '{op:$op,cwd:$cwd}'`. Check: beside
   the existing cwd-log check (about line 254), `regrun` from `$TMP/a"b\c`
   with `STUB_PROBE_LOG` set logs exactly that path (today it logs `-`,
   because the stub cannot parse the request). `auth_status` is not
   asserted: the stub answers `authed: true` to input it cannot parse. The
   check skips on Windows, where those names are not allowed.

### P3. Eval parser

Owns `evals/controller/lib/sessions.mjs`,
`evals/controller/lib/transcript.mjs`, `evals/controller/lib/heredoc.mjs`
(item 2's Check reverts it temporarily), `evals/controller/tests/` and
`docs/superpowers/distilled/constraints.md`.

1. **DF 26.a, c.** A `bash` or `sh` invocation is not a run when a
   `-`-prefixed cluster that is not a `--` long option (`--norc`,
   `--noprofile` are not) holds `n` (`-n`, `-nx`, `-en`), or when `-o
   noexec` is given; a `-o` still consumes its value. Check: `bash -nx`,
   `bash -en` and `bash -o noexec` before a script path count no run; `bash
   -eo pipefail` and `bash --norc` still count one.
2. **DF 26.e.** The `<<-'EOF'` test is rewritten to fail without the tab
   handling. Shape: a failed call whose command is `false && cat >>
   .dforge/sdd/p/progress.md <<-'EOF'`, a body line `Task 22: complete (x)`,
   the terminator `\tEOF`, then `echo 'Task 23: complete (x)' >>
   .dforge/sdd/p/progress.md; false`; expected completed `['23']`. With the
   tab stripping reverted the heredoc swallows the echo and the result is
   `[]`. Check: the test fails with the stripping reverted in `heredoc.mjs`
   and passes with it.
3. Every Check line uses the suite's ledger form `Task N: complete (x)`,
   which `COMPLETE` in `transcript.mjs` requires.
4. Every case above has a test in the owning test file.
5. **Bound.** `docs/superpowers/distilled/constraints.md` gains a section in
   its existing form:

   ```markdown
   ## Evals

   ### Eval parser shapes need a real transcript
   A shell shape the controller's parser (`evals/controller/lib/`) miscounts is fixed only when it appears in a real controller transcript; a shape found by review alone closes `n/a` citing this constraint.
   Set by: owner, 2026-10-20 review-rows sweep design session
   Scope: `evals/controller/lib/` and every register row against it
   Source: docs/superpowers/specs/2026-10-20-review-rows-sweep-design.md@<hash>
   ```

   `<hash>` is the spec's latest commit when P3 runs: `git log -1
   --format=%h -- docs/superpowers/specs/2026-10-20-review-rows-sweep-design.md`.

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

No foundation part: nothing in P2-P4 imports P1's modules. The `docs/`
files have one owner each: P3 writes `constraints.md`, and P5 writes the four
registers in wave 3.

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

## Review rulings

Fable review, 2026-10-20 (commit 48bb63c, verdict: revise), all applied:

- H1, DF 26.b's `||` rule reversed test o1 and would stop counting the
  `grep -q … ||` idiom: b closes `n/a` (owner, Decision 2; Scope).
- H2, DF 26.d is counted on success and correctly not on failure (test f2):
  d closes `n/a` (owner, Decision 2; Scope).
- M1, the Windows-stub test stubs only `O_NOFOLLOW`: the fallback keys on
  either constant (P1.1).
- M2, Check lines lacked `(`, which `COMPLETE` requires (P3.3).
- M3, a refusal exits 1, not 0 (P1.5).
- M4, line 776 is the pre-send case: only line 570 changes (P1.6).
- M5, the roster suite is `tests/detect.test.sh`, and the stub answers
  `authed: true` to unparseable input: the Check asserts the logged path
  (P2.1).
- M6, the `<<-'EOF'` rewrite still passed both ways: an `&&`-gated shape
  that fails without the fix, and `heredoc.mjs` joins P3 (P3.2).
- M7, `fileHash` and the `carriedDocuments` read do not block today: their
  FIFO Checks are regression guards, the races go through `t.mock`, and the
  Problem's count is corrected (Problem, P1.4, P1.5).
- M8, the mirror side of the killed-run comparison cannot hold a FIFO: the
  FIFO goes at `dest`, the mirror side through `t.mock` (P1.3).
- L1 the linked-record Check is a regression guard, and the comment says "a
  link or a pipe" (P1.4); L2 long options are excluded (P3.1); L3 the
  constraint follows the file's form (P3.5); L4 the `docs/` owners are
  stated and `heredoc.mjs` is owned (P3, Parallel decomposition); L5 a
  deleted document's refusal reads "changed during the move" by design
  (P1.5).
