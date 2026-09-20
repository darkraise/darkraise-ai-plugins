# dr-superpowers — Codex session budget (design)

Date: 2026-09-20. Status: owner-approved design. Scope: `Host: codex` sessions
only. Claude-host measurement, verdicts and budget numbers are untouched.

## 1. What this is for

A Claude session gets a measured budget line and stops on a `handoff` verdict.
A Codex session gets nothing to measure, so `reference/session-budget.md` gives
it a count rule instead: hand off after every 3 completed tasks, or after any
task that needed 3 or more fix rounds.

The count rule is blunt. Three tasks may leave a session at a fifth of its
context or past the point where compaction fires, and the rule cannot tell those
apart. It was adopted because no measurement was thought to exist.

One does. Codex writes a session rollout that records the context size at every
turn, so a Codex session can be measured the way a Claude session is.

This design ships the measurement and the plumbing, and deliberately withholds
the verdict until the margin behind it has been measured rather than guessed
(§2.3, §9).

## 2. Decisions fixed here

Owner rulings, 2026-09-20:

1. **Measurement lands inside `scripts/lib/context.sh`.** Every consumer reaches
   the budget through `ctx_line`, so no caller changes (§8).
2. **Host detection is automatic, newest wins.** The Claude transcript and the
   Codex rollout are resolved independently; the more recently written one is
   the running session (§4.3). No flag, no environment variable.
3. **No verdict on Codex in this phase.** The line reports the measured number
   and keeps the `unknown` verdict, so the count rule stays in charge and no
   session is stopped by a number nobody has validated (§6).
4. **The margin is measured, not scaled.** Phase two sets the budget from
   observed per-task growth on Codex. This phase collects that data (§7).
5. **Only interactive rollouts are candidates.** An executor-lane run started by
   a Claude controller writes a rollout in the controller's own working
   directory; selecting it would strip that Claude session of its verdict. The
   search filters by recorded origin (§4.2, §4.3).
6. **The log lives under `.superpowers/sdd/`**, which self-ignores, so it can
   never enter a review snapshot (§7).

## 3. Evidence

Observed 2026-09-20 on this machine, Codex CLI 0.154.0, from rollouts under
`~/.codex/sessions/2026/09/`. The rollout schema is observed, not documented;
§5 states how a schema change must degrade.

**The context size is `last_token_usage.input_tokens`.** Sampled across one long
session, it reads:

```
19545 90303 171517 192610 222794 239510 | 51326 96945 115125 133449 154918
191368 208786 | 28186 40688 59510 63420 90074 123585 164644
```

It climbs, then drops sharply, then climbs again. Each drop lands on a
`compacted` record in the same file. That is the number a budget needs.

**`total_token_usage.input_tokens` is a cumulative counter, not a context size.**
At the same sample points it reads 19,545 → 619,153 → … → 28,023,960. Reading it
as a context size is the obvious mistake this design exists to prevent.

**Compaction fires near 245k.** The peak `last_token_usage.input_tokens` before
each drop, across the five sessions that reached compaction:

| Session | Drops | Peak before a drop |
|---|---|---|
| 2026-09-01 (a) | 5 | 243,489 |
| 2026-09-01 (b) | 1 | 232,012 |
| 2026-09-01 (c) | 1 | 224,892 |
| 2026-09-01 (d) | 2 | 229,761 |
| 2026-09-07 | 25 | 244,626 |

The trigger is somewhere above 244,626. This is one account on one model
(`gpt-6-astra`, the `model` in `~/.codex/config.toml`); it is not a published
figure and phase two must not treat it as one.

**Sessions are identifiable.** Every rollout's first line is a `session_meta`
entry carrying `session_id`, `cwd` and `cli_version`.

**Interactive and non-interactive runs are distinguishable.** That same entry
carries `originator` and `source`. Across the 25 newest rollouts on this machine
the observed pairs are `codex_exec`/`exec` for non-interactive runs and `cli` or
`vscode` for interactive ones. Several `exec` rollouts are timestamped seconds
apart — the signature of a batch of executor-lane tasks — and one records this
repository as its `cwd`.

**An unbounded scan is too slow.** A `grep -r` across the sessions tree on this
machine did not finish within 120 seconds. §4.2 bounds the search.

## 4. Finding this session's rollout

### 4.1 Where rollouts live

`${CODEX_HOME:-$HOME/.codex}/sessions/<YYYY>/<MM>/<DD>/rollout-<timestamp>-<uuid>.jsonl`.
`CODEX_HOME` is honoured because the CLI documents it as the root of its own
configuration. That rollouts follow it is inference, not an observed fact; if a
future CLI stores them elsewhere the search finds none and the line reads
`unknown`, which is the correct degradation.

The tree is partitioned by date, not by project, so unlike the Claude side there
is no per-directory key to look up. The search is by recorded working directory.

### 4.2 The search

Candidate directories are the ones `ctx_candidates` already produces: the
working directory, the repository root, and the primary checkout's root.

Walk day directories newest-first, and files newest-first by modification time
within them; the tree's `<YYYY>/<MM>/<DD>` layout makes that ordering cheap and
avoids stat-ing the whole history. For each file read only its first line, and
require both of:

- **Interactive origin.** `.payload.originator` is not `codex_exec` and
  `.payload.source` is not `exec`. §4.3 explains why this is load-bearing.
- **A matching directory.** `.payload.cwd` equals one of the candidates,
  compared in native form through the existing `ctx_native` helper — `cwd` is
  recorded in native Windows form (`D:\\Repositories\\...`) while the candidates
  are POSIX paths under Git Bash.

Stop at the first file satisfying both. At most 40 files are examined: a session
being written to is among the very newest, and §3 shows an unbounded walk is
not affordable. Examining none is not an error — it yields no rollout, which
§6 reports as `unknown`.

### 4.3 Choosing between hosts

Claude transcript resolution (`ctx_find_transcript`) and Codex rollout
resolution run independently. When both produce a file, the one with the later
modification time is the running session. When only one does, it is used. When
neither does, the line is `unknown` exactly as today.

Modification time decides because the live session is the one still being
appended to. A stale transcript from a previous session in the same directory
loses to an active rollout, and the reverse. Session records are never deleted,
so a `record` source does not by itself prove a live Claude session; modification
time is the right tiebreak between two stale candidates.

**Why §4.2's origin filter is load-bearing.** Modification time alone is not
enough, because this plugin itself produces the case where both hosts are live in
one directory: a Claude controller runs `Executor:` tasks through
`scripts/run-codex-task.sh --cwd <worktree>`, and those runs write rollouts whose
`cwd` is the controller's own worktree (§3). Without the filter, the
controller's next `review-package` line would flip to `source: rollout`, exit 3
and `unknown` in a Claude session that had a verdict moments earlier —
contradicting §1's promise that Claude-host verdicts are untouched. With the
filter, an executor rollout is never a candidate.

A native Codex subagent's rollout is expected to carry the same non-interactive
origin, which would keep §12's exclusion of subagent measurement true as well.
That is inference, not observation. If a native subagent proves to write an
interactive-origin rollout in the controller's directory, newest-wins selects the
wrong one and phase two must revisit this rule.

## 5. The measurement

`ctx_measure_rollout FILE` returns the context size, or nothing.

Read the last entry where `.type` is `event_msg` and `.payload.type` is
`token_count`, and return `.payload.info.last_token_usage.input_tokens`.

- **Entries whose `info` is null are skipped.** They occur in real sessions; the
  first `token_count` of a session that never issued a request is one.
- **No compaction-boundary handling.** Unlike the Claude reducer, which resets at
  a `compact_boundary` and reads its `postTokens`, nothing here reads the
  `compacted` record: a post-compaction `token_count` already reports the
  reduced size (§3). The `compacted` entry is evidence for this design, not an
  input to it.
- **Read the tail first**, as `ctx_measure` does: rollouts reach tens of
  megabytes, and a `compacted` entry embeds an entire `replacement_history`.
  Fall back to a full read only when the tail yields nothing.
- **A schema change degrades to `unknown`, never to a wrong number.** This is the
  rule already stated at the top of `scripts/lib/context.sh` and it governs here
  unchanged: no field is inferred, and a missing or unparseable field ends the
  measurement.

## 6. The budget line

On a Codex rollout the line is:

```
budget: 187k measured — unknown — source: rollout
```

`source` gains `rollout` alongside the existing `record`, `record?` and
`guessed`. The verdict is `unknown` and `ctx_line` returns exit 3, which
`reference/session-budget.md` already defines as "apply the count rule on Codex".
Every skill's handoff behaviour is therefore unchanged by this phase: a Codex
session still stops on the count rule, now with a measured number in front of it.

There is no denominator and no percentage, because no budget has been set. A
line that printed a percentage against a guessed window would be the one thing
§2.3 exists to prevent.

A rollout that is selected but cannot be measured prints
`budget: unknown — unknown — no usage entry in <path>` and returns 3. It
carries no denominator either, unlike the Claude failure line, which keeps the
Claude-derived one it prints today.

`DR_SUPERPOWERS_BUDGET` is ignored on a rollout measurement in this phase.
Honouring it would produce `ok` and `handoff` verdicts on Codex, which §2.3
forbids; it keeps its meaning on a Claude transcript.

## 7. Collecting the growth data

When a rollout measurement succeeds, `context-size` appends one tab-separated
row to `<primary checkout>/.superpowers/sdd/budget-log.tsv`:

```
<ISO-8601 UTC timestamp>	<tokens>	<caller>	<session id>
```

**The log must never be visible to git.** Only this repository's root
`.gitignore` lists `.superpowers/`; the plugin cannot assume any project has that
line, which is why `scripts/sdd-workspace` writes its own `*` `.gitignore` into
`.superpowers/sdd/`. An un-ignored file there would be real damage rather than
untidiness: `scripts/lib/task-state.sh` hashes untracked-but-not-ignored files
into the review snapshot, so a `context-size` call between `dr_snapshot` and
`dr_task_assert_snapshot` would invalidate a Codex review, and the same file
would block initial execution on the clean-worktree check and appear under
`repo-audit`'s dirty files. The log therefore lives inside `.superpowers/sdd/`,
and `context-size` creates that directory and writes `*` into its `.gitignore`
when absent, exactly as `sdd-workspace` does.

The file is append-only and is never read by the budget line itself.

`<caller>` comes from `DR_SUPERPOWERS_BUDGET_CALLER`, which `scripts/task-brief`
and `scripts/review-package` set when they invoke `context-size`. Unset means
`direct`. `review-package` sets `review-package`. `task-brief` sets
`task-brief:<TASK_NUMBER>` in its ordinary mode and `task-brief:header` in
`--header` mode, which has no task number and still calls `context-size`;
`--observations` ignores the header rows.

`task-brief` takes one task number per call, so **the difference between
consecutive `task-brief:<N>` rows within one session id is one task's growth** —
the number phase two needs. Carrying the task number means a delta is never
inferred from row order alone: a re-run brief, a resumed plan or a skipped task
is visible in the pair rather than silently averaged into it.

`scripts/context-size --observations` reads the log back and prints, per session
id, each consecutive `task-brief:<N>` delta and the session's own span, one row
per pair:

```
<session id>  Task 3 -> Task 4  +38k
<session id>  Task 4 -> Task 5  compacted
```

**A negative delta is a compaction marker, never data.** Compaction is the event
phase two calibrates against, so a pair whose second reading is lower than its
first prints `compacted` and contributes no number. Phase two takes its margin
from the positive deltas alone. (Labelled inference: a row written after a
`compacted` record but before the next `token_count` carries the pre-compaction
peak, which makes the following pair the negative one rather than that pair
itself.)

`--observations` takes no other arguments, writes nothing, and exits 0 with an
empty or absent log.

## 8. Interface changes

| Surface | Change |
|---|---|
| `scripts/lib/context.sh` | New rollout search, measurement and host choice; `ctx_line` gains the `rollout` source and the `measured` line form |
| `scripts/context-size` | New `--observations` mode; appends to the log on a rollout measurement |
| `scripts/task-brief`, `scripts/review-package` | Set `DR_SUPERPOWERS_BUDGET_CALLER` when calling `context-size` (`task-brief` includes its task number); output unchanged |
| `reference/session-budget.md` | Document the rollout source, the `measured` line, the log and why Codex has no verdict yet |
| `reference/native-codex.md` | Its §Execution modes and session ends says the budget line reads `unknown`; it must now say the line carries a measured number while the count rule still governs |
| `skills/subagent-driven-development/SKILL.md` | Line 409, "On Codex there is no budget line", becomes false: there is one, and it carries no verdict |
| `skills/handoff/SKILL.md` | Its count-rule bullet (line 26) stays in force, and should say the measured number does not override it |

No skill's decision rules change. `repo-audit` needs no change: it prints
whatever `context-size` prints.

## 9. Phase two, gated on data

Not in scope for the plan this spec produces. It runs once
`context-size --observations` has per-task deltas from several real Codex
sessions:

1. Set the compaction point from observation (§3 puts it above 244,626 on this
   account and model), as a constant in `context.sh` beside `CTX_COMPACT_PCT`.
2. Set the margin from the measured per-task deltas, not from Claude's 140,000
   and not from a scaled fraction of it.
3. Return `ok` and `handoff` from a Codex measurement, and retire the count rule
   in `reference/session-budget.md` and `skills/handoff/SKILL.md`.

Phase two is a separate spec. Nothing in this phase may assume its numbers.

## 10. Testing

Against a synthetic rollout tree under `plugins/dr-superpowers/tests/fixtures/`,
with `CODEX_HOME` and `HOME` pointed into a temporary directory:

1. A rollout whose last `token_count` carries usage measures to its
   `last_token_usage.input_tokens`.
2. A trailing `token_count` with `"info":null` is skipped in favour of the last
   entry that has usage.
3. A rollout containing a `compacted` record followed by a smaller
   `token_count` measures the smaller number — no boundary arithmetic.
4. A rollout whose `session_meta.cwd` matches no candidate is not selected.
5. A `cwd` in native Windows form matches a POSIX candidate for the same
   directory.
6. With both a Claude transcript and a Codex rollout present, and both of
   interactive origin, the one with the later modification time wins, asserted
   in both directions.
7. A rollout whose `originator` is `codex_exec` (or whose `source` is `exec`)
   is never selected, even when it is the newest file and its `cwd` matches. With
   a Claude transcript also present, the Claude verdict survives unchanged —
   this is the executor-lane case of §4.3.
8. A rollout measurement prints `budget: <N>k measured — unknown — source: rollout`
   and `ctx_line` returns 3.
9. The search bound holds at its boundary: a matching rollout that is the 40th
   newest is found, and one that is the 41st newest is not.
10. A malformed or truncated rollout yields
   `budget: unknown — unknown — no usage entry in <path>` and exit 3, not a
   number and not a Claude-derived denominator.
11. `DR_SUPERPOWERS_BUDGET` set to a number does not produce a verdict on a
   rollout measurement, and still applies on a Claude transcript.
12. A successful rollout measurement appends one well-formed row to
    `budget-log.tsv`; a Claude measurement appends none. The log's directory is
    created with a `*` `.gitignore` when absent, and `git status --porcelain
    --untracked-files=all` in the checkout is empty afterwards.
13. `DR_SUPERPOWERS_BUDGET_CALLER` lands in the row; unset writes `direct`;
    `task-brief` writes its own task number into the tag.
14. `--observations` prints the per-task deltas for consecutive `task-brief:<N>`
    rows within a session id in the §7 format, names both task numbers in each
    pair, prints `compacted` for a negative delta and no number, ignores
    `task-brief:header` and other callers' rows, does not pair rows across
    session ids, and exits 0 on an empty or absent log.
15. Every existing Claude assertion in `tests/context-size.test.sh` and
    `tests/budget-line.test.sh` still passes unchanged. Both suites `unset
    CODEX_HOME` alongside the `HOME` they already redirect, so a developer's real
    rollout tree can never enter the walk during a test run.

Fixtures are built from a real `session_meta` line with its instruction text
redacted, and the implementation pins the session id to its jq path the way
§4.2 pins `.payload.cwd`, so a field-name change fails a test rather than
silently logging empty ids.

## 11. Verification

`node scripts/test-all.mjs` green, `node scripts/validate-repository.mjs` clean,
and `claude plugin validate` passing on the marketplace and every Claude plugin.

## 12. Out of scope

- Any Codex `handoff` verdict, budget number or compaction constant (§9).
- Changes to the count rule, to Claude measurement, or to any skill's stop rules.
- Reading Codex rate-limit or quota fields, which rollouts also carry.
- Measuring a Codex subagent's context; the budget line has always described the
  controller's session only.
