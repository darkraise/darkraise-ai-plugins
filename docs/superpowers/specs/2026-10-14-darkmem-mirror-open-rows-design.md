# darkmem mirror: resumable ledger import, absolute identities, Stop push, cockpit run errors

Date: 2026-10-14
Status: design, owner-approved row by row on 2026-10-14.
Register: `docs/superpowers/registers/2026-09-24-darkmem-mirror.md` rows 23,
24, 25 and 26. Row 6 stays `verify` and is not designed here.

**Execution strategy:** sequential — four small, file-disjoint changes plus one
release bump that touches every manifest; inline execution in one session.

## Rulings (owner, 2026-10-14)

1. **Row 23: resume, never purge.** A move stopped after an append batch
   resumes the import from where darkmem stops. Deleting darkmem's copy and
   re-importing was rejected: a move never overwrites darkmem (store-options
   spec §4). The `import` command keeps `--replace` as its recovery.
2. **Row 24: names from the roots only.** An absolute ledger identity is mapped
   to its name from the checkout's roots, as `pathToUri` does, never by
   searching for a `docs/forge` segment. An identity the roots cannot map stays
   unfinished, so the move refuses and names it.
3. **Row 25: the Stop push runs in the background now.** No Windows measurement
   gates the decision; row 6 records the timing as an observation.
4. **Row 26: settle the engine's wording with a probe.** The engine's types
   already say `$.process.run` rejects both when the command cannot start and
   when it outlives `timeoutMs`; a probe records the two messages.

## 1. Resuming a partial ledger import (row 23)

`importLedger` (`scripts/lib/darkmem-import.mjs`) splits a ledger with
`splitAtBlankLines` then `splitAtLimit`, appends the pieces in batches of
`MAX_ENTRIES_PER_APPEND`, and closes the workstream only after the last batch.
A move killed between batches leaves an open workstream holding the first
batches. Today `checkProgressTargets` (`scripts/lib/darkmem-progress-move.mjs`)
files a ledger darkmem holds byte for byte and refuses every other existing
copy, so the next reconcile refuses this one forever.

**Recognising a stopped import.** For a ledger source whose workstream exists,
`checkProgressTargets` reads darkmem's text and last sequence number
(`remoteLedger`) and classifies it:

- equal bytes: filed, as today;
- darkmem's bytes are a proper prefix of the local ledger, the workstream's
  state is not `closed`, and the prefix length equals the byte length of the
  first *k* pieces of the local ledger's split for some *k*: **partial**, with
  the workstream id, its last sequence number and *k*;
- anything else, including a closed workstream holding a prefix or a prefix
  ending inside a piece: a problem, as today
  (`darkmem already holds a different ledger for workstream <slug>`).

An open workstream with no ledger entries is the *k* = 0 case.

**Resuming.** `importLedger` takes an optional resume argument
`{ id, lastSeq, from }`. With it, the function skips the first `from` pieces and
sends each remaining batch with `expectedLastSeq` set to the last sequence
number darkmem answered (`last_seq` in the append answer), starting from
`lastSeq`. A 409 (another writer appended) or a 422 (an entry refused) records a
failure in the report and stops that ledger, as a 422 does today; the move then
refuses with "darkmem refused part of the progress; nothing was moved locally".
After the last batch the workstream is closed as before.

The move calls `importLedger` with the resume argument for each partial ledger,
and without it for a ledger darkmem does not hold. Everything after the import
is unchanged: the existing read-back compares darkmem's full text with the
local bytes before anything local moves, so a resume that went wrong refuses
there.

The `import` command (`importRepository`) is not changed.

## 2. Absolute ledger identities (row 24)

A ledger's identity line (`# SDD ledger — plan: <name>`) written before the
store-roots work can hold an absolute path such as
`/repo/docs/forge/plans/p.md`. `planFinished` (`scripts/lib/darkmem-reconcile.mjs`)
and `plan_finished` (`scripts/next-step`) both look for a backticked spelling of
the name in the `completed.md` beside the plan. The spellings of an absolute
name are the absolute name itself, while `completed.md` records the relative
`docs/forge/…` or `docs/superpowers/…` name, so a finished plan never matches
and `inProgress` blocks every move. (`planFile` already returns an absolute name
unchanged, and `forge_resolve` does the same, so both read the right
`completed.md`; only the match fails.)

**The rule, in both languages.** Before computing spellings, an absolute name is
mapped to its relative name from the checkout's roots:

- under the docs root in use (the mirror's `superpowers/` while documents are
  in darkmem, else the checkout's `docs/forge` or `docs/superpowers`): the docs
  name plus the path below it;
- else under the checkout's top level: the path below it.

Comparisons use resolved paths, case-insensitive on Windows, as `pathToUri` and
`samePath` do. A name that maps under neither keeps its absolute spelling, so it
never matches, the plan counts as unfinished, and the move refuses naming it.
No segment search is ever done.

In bash, `plan_finished ROOT NAME` passes an absolute NAME through `forge_name`
(`scripts/lib/roots.sh`) with ROOT as the directory, which already implements
the roots mapping, including the Git Bash `cygpath -m` and physical-path
retries. In JS, `planFinished(cfg, checkout, name)` gets a small helper beside
`planFile` that applies the same two bases. `planFile` keeps reading the
absolute path for the location of `completed.md`.

In `next-step`, `plan_finished` is called on a register row's Assigned cell, so
an absolute Assigned cell naming a finished plan is now reported as stale like a
relative one.

## 3. The Stop push in the background (row 25)

`turn-end.sh` runs `darkmem_push_quietly` first, synchronously, with a 100 s
bound, inside a hook whose `timeout` in `hooks/hooks.json` is 120 s. The rest of
the hook (the `auto-run` query, bounded at 15 s, the transcript scan and the
decision) runs after it. A slow darkmem therefore delays every turn's end, and a
push near its bound can run the hook past 120 s, which kills it and loses its
block decision.

**Change.** A new script, `scripts/darkmem-stop-push.sh`, reads the Stop payload
(`session_id`, `cwd`), sources `scripts/lib/darkmem-hook.sh` and calls
`darkmem_push_quietly`. It prints nothing and exits 0 whatever happens.
`hooks/hooks.json` lists it as a second command hook in the Stop group with
`"async": true` and no `timeout`. `turn-end.sh` no longer sources the library or
pushes; its header comment drops the push paragraph.

What the hooks reference (https://code.claude.com/docs/en/hooks.md, read
2026-10-14) says about async command hooks, and what follows from it:

- Claude Code starts the process and continues without waiting, and all
  matching hooks run in parallel, so `turn-end.sh`'s decision no longer waits
  on darkmem.
- An async hook's `decision` has no effect; the push never decides anything.
- Claude Code does not enforce `timeout` on an async command hook. The push
  stays bounded by `_darkmem_run`'s 100 s GNU `timeout`; where no `timeout`
  binary exists (macOS), by darkmem-sync's per-request client timeout
  (`DARKMEM_SYNC_TIMEOUT_MS`, 10 s by default), as today.
- In a `-p` run, Claude Code cancels an async hook still running at teardown;
  for an interactive exit the docs do not say. A push cut short is the case
  darkmem-sync already handles for a killed or timed-out push: ledger appends
  carry `expected_last_seq`, `darkmem-push.mjs` reconciles a 409 against
  darkmem's copy, and the next push sends the rest.

Pushes from overlapping turns are already serialised by darkmem-sync's lock.
The skills' explicit stop points keep pushing, so the Stop push stays a safety
net.

## 4. How the cockpit reads a failed run (row 26)

`readRoots` (`hooks/cockpit/register.tsx`) runs
`node scripts/lib/darkmem-config.mjs --mode <primary>` with a 5 s timeout. The
engine's types (`claude-code.d.ts`, Claude Code 2.1.296, `process.run`) state
that `run` resolves `{ exitCode, stdout, stderr }` for any exit code and rejects
when the command cannot start or is still running at the timeout. So:

- the resolved branch's `exitCode !== 127` guard can never see 127 from a
  missing `node` (there is no shell); it is removed, and the `NO_NODE` stderr
  test on a resolved run stays (a node that starts and fails to load is
  ordinary failure output);
- a rejection is either a missing `node` or a timeout, and today the elapsed
  time decides which.

**Probe.** A throwaway mod, run in a nested session with no model turn (a fresh
`CLAUDE_CONFIG_DIR` in the scratchpad, `--plugin-dir <probe>`), calls
`$.process.run(['dr-forge-no-such-command'])` and
`$.process.run(['sleep', '10'], { timeoutMs: 500 })` and writes both rejection
messages and error names to a file. The probe is not committed; its two
messages and the Claude Code version are quoted in the register row's note.

- If the missing-command rejection carries `ENOENT` (as `error.code` or in its
  message) and the timeout rejection does not, `readRoots` decides on that:
  the missing-`node` rejection sets no note, the timeout rejection sets the
  existing "gave no answer within 5 seconds" note, and the `$.clock.now()`
  elapsed-time check and its comment are removed.
- If they do not, the elapsed-time check stays, its comment cites the probe,
  and the row closes as "the engine does not distinguish".

## 5. Testing

- **Row 23** (`tests/darkmem-sync/reconcile-progress.test.mjs`, against the
  stub server): a ledger longer than one batch whose first batch alone sits on
  an open workstream moves, ends closed, and reads back byte-identical; the
  *k* = 0 case moves; a closed workstream holding a prefix, a prefix ending
  inside a piece, and a non-prefix each refuse with nothing moved; a 409 during
  the resumed append refuses with nothing moved locally.
- **Row 24** (`tests/darkmem-sync/reconcile.test.mjs` and
  `tests/next-step.test.sh`): a ledger whose identity is the absolute path of a
  plan inside the checkout, recorded in `completed.md`, no longer blocks the
  move; the same with documents in darkmem (identity under the mirror's
  `superpowers/`); an absolute identity under a path that does not exist still
  blocks and is named; an absolute Assigned cell naming a finished plan is
  reported stale by `next-step`.
- **Row 25** (`tests/turn-end.test.sh`, `tests/darkmem-sync/hooks.test.mjs`):
  `turn-end.sh` with darkmem configured makes no darkmem request; the new
  script pushes and prints nothing; a hooks.json check that the Stop group
  holds both hooks, the push hook is async, and `turn-end.sh` stays synchronous.
- **Row 26** (`tests/cockpit.test.ts`): rejections shaped like the probe's two
  messages produce no note and the timeout note respectively, whatever the
  elapsed time; a resolved non-zero exit still shows its first stderr line.
- Repository validation as `CLAUDE.md` lists it, with versions bumped together.

## Delivery

One plan, sequential, inline: rows 24, 23, 25, then 26 (the probe first), then
the release bump. Row 6's Windows check runs on the pull request that carries
this work and the 188 local commits before it; opening that pull request waits
for the owner's go-ahead.

## Not in scope

- Row 20's other half (sync roots pointing into the working tree) and row 22's
  hazards.
- Resuming a stopped `import` command run.
- Measuring the push on Windows (row 6).
