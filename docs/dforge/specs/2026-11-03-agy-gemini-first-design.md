# agy lane: Gemini first

**Execution strategy:** sequential — `reference/ladder.md`, `scripts/run-agy-task.sh`, `scripts/agy-gate` and `reference/executor-lane.md` are each touched by more than one part, and the gate change consumes the session-file shape the wrapper change writes.
**Depth:** standard — interface

## Decisions

- **Rows for every total.** On 2026-11-03 the owner was shown the calibration results (`docs/dforge/notes/2026-11-03-agy-calibration-3-8.md`) and the recommendation: Flash medium on totals 0-2, Argon low on 3-4, Argon high on 5-8, Sonnet and Opus through `agy` as fallbacks, Argon timeout rows, a quota mark per model family, `Resets in …` read into `resets_at`, and a committed calibration note. Answer: "start that, also note that the claude quota in agy will drain quickly, so use and assign them wisely".
- **Claude quota.** Asked how dforge should spend the scarce Claude quota on Antigravity. Answer: "Fallback only (Recommended)": every total starts on Gemini. Claude through `agy` runs only as the single retry after a Gemini run fails on capability (Argon low → Sonnet medium, Argon high → Sonnet high), and a second failure goes back to native Claude.
- **Quota mark.** Asked how a Claude quota error through `agy` is handled. Answer: "Fallback mark (Recommended)": a Claude quota marks only the Claude fallback off until its reset time, the gate line reports it, and the wrapper refuses Claude models at preflight while the mark holds. A Gemini quota still closes the lane, but it reopens at the reset time read from the error, not at the end of the session.
- **Approaches.** Rejected: "No mark (do-less)": every later failed Gemini task would still spend one Claude run on the same 429. Rejected: "Two executors" (`agy-gemini` and `agy-claude`): it duplicates the registry entry, gate, planner ticking and breaker.
- **Execution strategy.** Not asked (`autoRun=on`); sequential, for the reason on the line above.
- **Breaker.** Asked (spec review) whether a hand-back for a drained Claude fallback counts toward the per-plan breaker. Answer: "Count it (Recommended)": it is recorded as `executor agy HANDBACK - fallback quota until <iso|session end>` and counts like any hand-back.
- **Early CI.** Answer: "No early run (Recommended)".

Early CI: none

Finish: pr
- **Opus through `agy`.** Not asked. It follows from the Claude quota answer, whose fallbacks are Sonnet only: no assignment or successor row names `claude-opus-5-5`, so its timeout row goes too. Native Opus is unchanged.
- **Total 5.** Not asked: Argon high, because the recommendation the owner approved names 5-8. No task scored 5 was replayed, but Argon high is the only rung measured on all three high tasks (Fable ruling).

## Goal

Run the `agy` lane on the Antigravity Gemini quota for every total it admits, and spend the much smaller Claude-on-Antigravity quota only where a Gemini run has already failed. A quota on one model family must not close the lane for the other, and a quota with a reset time must end at that time instead of at the end of the session.

## Evidence

`docs/dforge/notes/2026-11-03-agy-calibration-3-8.md` (this change commits it):
- Argon low passed all three replayed tasks scored 3-4, and Argon high passed all three scored 6-7. Each run was checked on its tests, its scope and a blind judge.
- Claude through `agy` hit `RESOURCE_EXHAUSTED (code 429): Individual quota reached. … Resets in 4h47m34s.` after about 500k tokens. Argon kept running afterwards.

## Design

### 1. Ladder blocks (`reference/ladder.md`)

```agy-assignment
0 gemini-3.8-flash medium
1 gemini-3.8-flash medium
2 gemini-3.8-flash medium
3 gemini-4-argon low
4 gemini-4-argon low
5 gemini-4-argon high
6 gemini-4-argon high
7 gemini-4-argon high
8 gemini-4-argon high
```

```agy-successor
gemini-3.8-flash/medium claude-sonnet-5-5/medium
gemini-4-argon/low claude-sonnet-5-5/medium
gemini-4-argon/high claude-sonnet-5-5/high
claude-sonnet-5-5/medium HANDBACK
claude-sonnet-5-5/high HANDBACK
```

```agy-timeout
gemini-3.8-flash/medium 900
gemini-4-argon/low 900
gemini-4-argon/high 1500
claude-sonnet-5-5/medium 1200
claude-sonnet-5-5/high 1800
```

How the timeout rows are derived:
- Argon timeouts use the rule of the 2026-11-02 calibration: the larger of 900 and three times the slowest passing run, rounded up to a multiple of 300.
  - Low: 3 × 137 s = 411 s, so the 900 s floor applies.
  - High: 3 × 426 s = 1278 s, rounded up to 1500 s.
- The Claude rows keep their current values.
- The `claude-opus-5-5/high` row and the Opus successor row are removed, because nothing reaches them.

The prose around the blocks changes:
- "Totals 3 to 8 mirror the native Claude assignment table" becomes one sentence naming the 2026-11-03 calibration note as the source of rows 3-8.
- A paragraph says why no row starts on Claude: that quota is small and is spent only on a retry.
- The ranking rule (`model_rank * 10 + effort_rank`, Gemini models rank 0) still makes every successor rank strictly above its source. Every row is a Gemini source with a Claude target, or a Claude source with `HANDBACK`.

### 2. Wrapper admission (`scripts/run-agy-task.sh`)

The wrapper admits a model when it names a rung in `agy-assignment` or a successor target in `agy-successor`. Today it admits only assignment rungs, which would refuse every Claude fallback once no assignment row names Claude. The refusal message becomes `model is not an agy-assignment or agy-successor rung: <model>`. The effort check and the `agy-timeout` lookup are unchanged. The Failure rows table of `reference/executor-lane.md` says "a model outside the executor's assignment block"; for `agy` it becomes "outside its assignment and successor blocks".

### 3. Quota classification and marks

On a quota whose source is `agy` (its `.error` text or non-JSON stdout; a stderr-only quota still marks nothing):

- **Reset time.** The wrapper reads `Resets in <n>d<n>h<n>m<n>s` from the cause text. Each unit is optional, but at least one must be present.
  - The reset becomes `resets_at_epoch` = the wrapper's `date -u +%s` after `agy` exits, plus those seconds. `agy` emits the duration earlier, possibly minutes before a long run ends, so the mark can outlive the quota by that much. The drift is in the safe direction and is accepted.
  - `resets_at` is the same instant in ISO 8601 UTC, formatted as `scripts/codex-gate` does: GNU `date -u -d @<epoch>`, falling back to BSD `date -u -r <epoch>`, and null when both fail.
  - With no match, both are null.
- **Report.** The `## Agy error` section gains `marked=lane`, `marked=fallback` or `marked=none` under its `reason=` line, and `until=<iso>` when a reset was parsed. The report alone then explains the next gate line.
- **Family.** A `claude-` model is the fallback family. Any other model is the lane family.
- **Lane family quota.** `executor_session_mark_off agy quota <epoch>` marks the lane off and records the reset time. `executor_session_mark_off` gains an optional third argument for this; Codex's callers pass none and are unchanged.
- **Fallback quota.** The new `executor_session_mark_fallback_off agy <epoch>` writes a `fallback` object (`{usable: false, reason: "quota", resets_at, resets_at_epoch}`) into the session file and leaves `usable` and `lane` as they are.
- **Preserved through every write.** `executor_session_write` callers (the gate's probe write and `executor_session_mark_off`) carry an existing `fallback` object through unchanged, so a probe or a lane mark never erases an unexpired fallback mark.
- **Comment fix.** The comment "A quota is account-wide" is corrected: Antigravity counts Claude and Gemini against separate limits.

### 4. Gate (`scripts/agy-gate`)

The line gains two fields before `source=`:

`agy-gate usable=<bool> reason=<r> review=false lane=<bool> resets_at=<iso|-> fallback=<on|off> fallback_resets_at=<iso|-> source=<probe|cache|setting>`

- **Lane quota.** A cached `reason=quota` is reused while its `resets_at_epoch` is null or in the future, `--refresh` included, as `agy-gate`'s own `false:quota` clause does today. Once the epoch has passed, the gate probes again and the lane reopens. `resets_at=` prints the lane quota's reset, or `-`.
- **Fallback mark.** `fallback=off` while the `fallback` object's epoch is null or in the future. When the epoch has passed, the gate drops the object and prints `fallback=on`.
- **Other answers.** A missing or non-numeric epoch reads as null, so the mark holds for the session. This deliberately differs from `scripts/codex-gate`, which reads a bad epoch as 0 and re-probes: `agy`'s auth probe cannot see a quota, so a re-probe would wrongly reopen the lane. A setting-forced answer is still never cached as a quota.
- **File readers.** Readers of the session file (`executor_session_on agy lane`, as `plan-lint` uses) see the lane reopen only after the next gate call rewrites the file. Codex has the same property, and the planner runs the gate before it reads the roster.

### 5. Wrapper preflight and controller rules

- **Fallback refusal.** The wrapper runs a `claude-` model only when the gate line says `fallback=on`, the same fail-closed rule as its `lane=true` check. A line without the field, from a stub or an older gate, refuses too. Otherwise it exits 2 before launching `agy` with `the agy Claude fallback is off until <iso|the end of the session> (quota)`. This is the existing preflight path, whose ruling is `HANDBACK`.
- **Capability row** (`reference/executor-lane.md`, When a run fails). Before moving to the successor, read the refreshed gate line. When the successor is a `claude-` rung and the line says `fallback=off`, hand back now and record `executor agy HANDBACK - fallback quota until <iso|session end>`. The handback after a lane quota likewise records the gate's `reason` with `until <iso>` when `resets_at` is not `-`. The ledger is the only record a resumed controller has of when Claude through `agy` returns.
- **Resume refusal** (When the resume itself fails). A new row: exit 2 whose stderr says `the agy Claude fallback is off until …` is `HANDBACK` now, recorded on the fix-round line as `executor agy HANDBACK - fallback quota until <iso|session end>`. Without this row, the table's `exit=2` row would re-issue the same resume, which the wrapper refuses again.
- **Transient rows.** In both the initial-run table and the resume table, a quota the wrapper marked is not retried: a lane quota makes the refreshed gate say `lane=false`, and a fallback quota makes the retry a preflight refusal. A stderr-only quota keeps the one retry.
- **Docs.** The `agy` Quota bullet of `reference/executor-lane.md` describes both families, both marks, the reset times and the file-reader note above, and records the observed error text. It keeps the phrase "keeps a cached `reason=quota`" that `tests/lanes.test.sh` pins. The `agy-gate` header (purpose and Output line) and `plugins/dforge/README.md`'s "a quota failure keeps the lane off for the session" change with the gate.

### 6. Calibration note and release

- `docs/dforge/notes/2026-11-03-agy-calibration-3-8.md` is committed with this spec.
- The plugin releases as 4.11.0, with a changelog entry for the new rows, the fallback mark and the gate fields. The entry also says that a plan whose `agy` Executor lines name a Claude rung fails `plan-lint` until `plan-revise` rewrites it. No plan in this repository carries such a line; other repositories using the plugin may.

## Testing

- `tests/lanes.test.sh` pins:
  - the new rows;
  - no `claude-` model in `agy-assignment`;
  - every Gemini assignment rung has a Claude successor;
  - every Claude rung has `HANDBACK`;
  - a timeout row for every rung reachable from the assignment and successor blocks, and none other.

  The "rows 3 to 8 mirror the native Claude table" check is replaced. The 2026-11-02 record check "the smoke run used the rung that total 5 is assigned" pins `claude-sonnet-5-5/high` literally, because that note records the history of the earlier calibration, not the live row.
- `tests/run-agy-task.test.sh` uses the stub `agy`:
  - a lane quota and a fallback quota, each with and without `Resets in`;
  - admission of a successor-only model;
  - the preflight refusal under `fallback=off`, with no `agy` launched;
  - a stderr-only quota marks nothing.
- The gate tests use a hand-written session file, and drive expiry by rewriting `resets_at_epoch` to a past value, as `tests/codex-gate.test.sh` does:
  - an expired and an unexpired lane quota, under `--refresh` too;
  - an expired and an unexpired fallback mark;
  - a probe write keeps the fallback object.
- Every existing test that matches a whole gate line gains the two fields. The `agy` gate stubs in `tests/run-agy-task.test.sh` and the acceptance test gain `fallback=on fallback_resets_at=-`; the Codex stubs are untouched.
- Three tests use `claude-opus-5-5` as a valid but different rung, which the admission check now refuses earlier and with a different message. Each is retargeted: `tests/run-agy-task.test.sh` "rejects a rung with no agy-timeout row" (dropped if no admitted rung lacks a timeout row), "a resume with another model is refused", and the acceptance test's A9 pin.
- `tests/executor-session.test.sh` keeps its two-argument `executor_session_mark_off` cases for Codex.
- `tests/run-agy-task.test.sh` pins the `marked=` and `until=` lines beside its existing `reason=quota` checks.
- `tests/antigravity-executor-lane.acceptance.test.sh` follows the new rows.
- Windows Git Bash runs the same suites in CI. The reset arithmetic uses `date -u +%s` and shell arithmetic only, with `\r` stripped from every value read back.

## Acceptance

A1. [test, high] `agy-assignment` names `gemini-3.8-flash medium` for totals 0-2, `gemini-4-argon low` for 3-4 and `gemini-4-argon high` for 5-8.
A2. [test, neg, high] No `agy-assignment` row names a `claude-` model, and no `agy-successor` or `agy-timeout` row names `claude-opus-5-5`.
A3. [test, high] `agy-successor` maps `gemini-3.8-flash/medium` and `gemini-4-argon/low` to `claude-sonnet-5-5/medium`, `gemini-4-argon/high` to `claude-sonnet-5-5/high`, and both Sonnet rungs to `HANDBACK`.
A4. [test, high] `agy-timeout` holds `gemini-4-argon/low 900` and `gemini-4-argon/high 1500`, has a row for every rung reachable from the assignment and successor blocks, and no other row.
A5. [test, high] The wrapper runs a `claude-sonnet-5-5` successor rung, and refuses with exit 2, before launching `agy`, a model that is in neither block.
A6. [test, high] An `agy` `.error` quota carrying `Resets in 1h2m3s` on a Gemini run makes the next gate line read `lane=false reason=quota`, with `resets_at` 3723 s after the wrapper exits, give or take 5 s. After the session file's `resets_at_epoch` is rewritten to a past value, the next gate call reads `source=probe` and `lane=true`.
A7. [test, high] The same error on a `claude-` run makes the next gate line carry `lane=true`, `fallback=off` and a `fallback_resets_at` 3723 s after the wrapper exits, give or take 5 s, and a Gemini run still launches `agy`.
A8. [test, neg, high] Unless the gate line says `fallback=on`, the wrapper refuses a `claude-` model with exit 2 and `agy` is never launched. This covers both `fallback=off` and a line without the field.
A9. [test, neg, high] Neither a gate probe write nor a lane mark-off removes an unexpired fallback mark.
A10. [test, high] A quota error without `Resets in` keeps the mark for the rest of the session, `--refresh` included: the lane for a Gemini run, the fallback for a `claude-` run.
A11. [test, neg, high] A quota word found only in stderr marks neither the lane nor the fallback.
A12. [test, high] `reference/executor-lane.md` hands back, recording `executor agy HANDBACK - fallback quota until <iso|session end>`, in two places: the capability row of When a run fails, when the successor is a `claude-` rung and the refreshed gate line says `fallback=off`; and a row of When the resume itself fails, for the wrapper's fallback refusal. Neither table's transient row retries a quota the wrapper marked.
A13. [test, high] `docs/dforge/notes/2026-11-03-agy-calibration-3-8.md` is committed, and `reference/ladder.md` names it as the source of `agy-assignment` rows 3-8.
A14. [test, high] After an `agy`-sourced quota, the report's `## Agy error` section carries `marked=lane` for a Gemini run, `marked=fallback` for a `claude-` run and `marked=none` for a stderr-only quota, plus `until=<iso>` when the error carried `Resets in`.

## Riskiest assumption

Antigravity limits Claude and Gemini separately, and a quota error states its reset as `Resets in <duration>` in `agy`'s `.error` field. Evidence from 2026-11-03, host time, in `docs/dforge/notes/2026-11-03-agy-calibration-3-8.md`:
- Both Claude runs of H2 failed at 14:09 and 14:11 with `.error` = `… Individual quota reached. … Resets in 4h47m34s.` (and 4h45m41s).
- `gemini-4-argon/high` then completed H2 at 14:14 and H3 at 14:18-14:21, with gate refreshes reading `usable=true`.

Still unverified:
- whether Flash and Argon share one Gemini limit (if they do not, closing the whole lane on a Gemini quota is conservative but safe);
- the duration format for resets longer than a day (the parser accepts a `d` unit, and an unparsed reset falls back to a session-long mark);
- what a short rate-limit throttle looks like: `is_quota` treats it as a quota, so one without `Resets in` marks the lane for the session. The next calibration records its text.

## Review rulings

- Fable, spec: assignment rows stand, as approved.
- Fable, spec: successor rows stand: the rank rule, the walk and the stale check in `tests/lanes.test.sh` all hold.
- Fable, spec: Opus removal stands. The three tests that use `claude-opus-5-5` as a valid rung are retargeted (Testing).
- Fable, spec: total 5 stays Argon high. The former A13 question is withdrawn because 5-8 is inside the approved recommendation.
- Fable, spec: wrapper admission stands. The Failure rows table names the successor block too (§2).
- Fable, spec: the fallback check is fail-closed: a `claude-` model needs `fallback=on` (§5, A8).
- Fable, spec: a refused Claude-fallback resume gets its own `HANDBACK` row in When the resume itself fails, and both transient rows skip a marked quota (§5, A12).
- Fable, spec: `executor_session_mark_off` keeps its two-argument form for Codex, and the Codex test cases stay (Testing).
- Fable, spec: the ISO reset uses GNU `date -d @`, falling back to BSD `date -r` (§3).
- Fable, spec: the gate's citation is corrected. `--refresh` keeping a quota is `agy-gate`'s own rule, and the bad-epoch reading is a deliberate difference from `codex-gate` (§4).
- Fable, spec: phrase pins and docs follow the gate: the `lanes.test.sh` phrase, the `agy-gate` header and README (§5).
- Fable, spec: A6 drives expiry by rewriting the epoch.
- Fable, spec: the 2026-11-02 record check pins `claude-sonnet-5-5/high` literally (Testing).

## Critic findings

Folded into Fable's round.
- [High] A refused fallback resume loops through "re-issue the same resume". Fixed by the resume-table row (§5).
- [Medium] The fallback check was fail-open on a line without the field. Fixed (§5, A8).
- [Medium] The ledger reason carried no reset time. Fixed: `until <iso|session end>` on both handback kinds (§5).
- [Medium] The report did not say which mark the wrapper wrote. Fixed: `marked=` and `until=` lines (§3, A14).
- [Medium] No migration story for plans written under the old rows. Fixed: a changelog sentence (§6).
- [Medium] `Resets in` is relative to `agy`'s emit time. Fixed: the drift is stated and accepted, and A6 and A7 measure from the wrapper's exit (§3).
- [Nit] File readers see the lane closed until the next gate call. Stated (§4).
- [Nit] The execution-strategy rationale rests on the file list. No change.
- [Nit] A rate limit without `Resets in` produces a session-long mark. Listed under Still unverified.
