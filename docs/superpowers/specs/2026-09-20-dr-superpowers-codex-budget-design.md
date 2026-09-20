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

Walk rollout files newest-first by modification time. For each, read only its
first line, extract `.payload.cwd`, and compare it against each candidate in
native form through the existing `ctx_native` helper — `cwd` is recorded in
native Windows form (`D:\\Repositories\\...`) while the candidates are POSIX
paths under Git Bash. Stop at the first match.

At most 40 files are examined. A session being written to is among the very
newest, and §3 shows an unbounded walk is not affordable. Examining none is not
an error: it yields no rollout, which §6 reports as `unknown`.

### 4.3 Choosing between hosts

Claude transcript resolution (`ctx_find_transcript`) and Codex rollout
resolution run independently. When both produce a file, the one with the later
modification time is the running session. When only one does, it is used. When
neither does, the line is `unknown` exactly as today.

Modification time decides because the live session is the one still being
appended to. A stale transcript from a previous session in the same directory
loses to an active rollout, and the reverse.

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

## 7. Collecting the growth data

When a rollout measurement succeeds, `context-size` appends one tab-separated
row to `<primary checkout>/.superpowers/budget-log.tsv`:

```
<ISO-8601 UTC timestamp>	<tokens>	<caller>	<session id>
```

The directory is already git-ignored. The file is append-only and is never read
by the budget line itself.

`<caller>` comes from `DR_SUPERPOWERS_BUDGET_CALLER`, which `scripts/task-brief`
and `scripts/review-package` set when they invoke `context-size`. Unset means
`direct`. `task-brief` sets `task-brief:<TASK_NUMBER>`, taking the number from
its own second argument; `review-package` sets `review-package`.

`task-brief` takes one task number per call, so **the difference between
consecutive `task-brief:<N>` rows within one session id is one task's growth** —
the number phase two needs. Carrying the task number means a delta is never
inferred from row order alone: a re-run brief, a resumed plan or a skipped task
is visible in the pair rather than silently averaged into it.

`scripts/context-size --observations` reads the log back and prints, per session
id, each consecutive `task-brief` delta and the session's own span. It takes no
other arguments, writes nothing, and exits 0 with an empty log.

## 8. Interface changes

| Surface | Change |
|---|---|
| `scripts/lib/context.sh` | New rollout search, measurement and host choice; `ctx_line` gains the `rollout` source and the `measured` line form |
| `scripts/context-size` | New `--observations` mode; appends to the log on a rollout measurement |
| `scripts/task-brief`, `scripts/review-package` | Set `DR_SUPERPOWERS_BUDGET_CALLER` when calling `context-size` (`task-brief` includes its task number); output unchanged |
| `reference/session-budget.md` | Document the rollout source, the `measured` line, the log and why Codex has no verdict yet |
| `reference/native-codex.md` | Its §Execution modes and session ends says the budget line reads `unknown`; it must now say the line carries a measured number while the count rule still governs |

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
6. With both a Claude transcript and a Codex rollout present, the one with the
   later modification time wins, asserted in both directions.
7. A rollout measurement prints `budget: <N>k measured — unknown — source: rollout`
   and `ctx_line` returns 3.
8. The search stops after 40 files and reports no rollout rather than hanging.
9. A malformed or truncated rollout yields `unknown`, not a number.
10. A successful rollout measurement appends one well-formed row to
    `budget-log.tsv`; a Claude measurement appends none.
11. `DR_SUPERPOWERS_BUDGET_CALLER` lands in the row; unset writes `direct`;
    `task-brief` writes its own task number into the tag.
12. `--observations` prints the per-task deltas for consecutive `task-brief:<N>`
    rows within a session id, names both task numbers in each pair, ignores
    other callers' rows, does not pair rows across session ids, and exits 0 on
    an empty or absent log.
13. Every existing Claude assertion in `tests/context-size.test.sh` and
    `tests/budget-line.test.sh` still passes unchanged.

## 11. Verification

`node scripts/test-all.mjs` green, `node scripts/validate-repository.mjs` clean,
and `claude plugin validate` passing on the marketplace and every Claude plugin.

## 12. Out of scope

- Any Codex `handoff` verdict, budget number or compaction constant (§9).
- Changes to the count rule, to Claude measurement, or to any skill's stop rules.
- Reading Codex rate-limit or quota fields, which rollouts also carry.
- Measuring a Codex subagent's context; the budget line has always described the
  controller's session only.
