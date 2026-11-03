# agy Lane: Gemini First Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: the skill the **Execution:** line names — dforge:subagent-driven-development for `subagent`, dforge:executing-plans for `inline`. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Run every `agy` total on the Antigravity Gemini quota, spend Claude-through-`agy` only as the single retry after a Gemini run fails, and mark a quota per model family until the reset time the error names.

**Architecture:** New `agy-assignment`, `agy-successor` and `agy-timeout` rows in `reference/ladder.md`, which the wrapper admits from both blocks. The session library gains reset times and a separate `fallback` object that every write carries through. `agy-gate` expires both marks and prints them. `run-agy-task.sh` marks the family that hit the quota, reports which mark it wrote, and refuses `claude-` models while the fallback is off. The lane reference, README and plugin version follow.

**Tech Stack:** Bash (GNU and uutils coreutils, Git Bash), jq, dforge's bash test suites run by `node scripts/test-all.mjs`.

**Spec:** docs/dforge/specs/2026-11-03-agy-gemini-first-design.md

**Execution:** subagent — `claude --model sonnet --effort high` — most tasks are heavy (total 5 or more)

**Parallelism:** sequential — the spec's Execution strategy line: the ladder, gate, wrapper and lane reference are each touched by more than one part, and the gate consumes the session-file shape the library writes

**Task check:** none — full suite every 3 tasks

**Integration check:** `node scripts/test-all.mjs`

**CI:** `.github/workflows/validate.yml, .github/workflows/release.yml` — platforms: uutils (ubuntu-latest), Windows Git Bash — local: `node scripts/validate-repository.mjs`; `node scripts/test-all.mjs`; `claude plugin validate .`; `claude plugin validate plugins/dforge`; `claude plugin test plugins/dforge` — uncovered: uutils (ubuntu-latest), Windows Git Bash

**Plan review:** 2026-11-03 — dforge:judge-opus — executability 13 / coherence 16 / coverage 17 / assumptions 15 (round 1)

## Global Constraints

- Scripts keep the dforge conventions: `#!/usr/bin/env bash`, `set -uo pipefail`, `die()` printing `<script>: <message>` to stderr with exit 2, jq reading JSON files on stdin (`jq … < "$file"`) inside scripts, and `tr -d '\r'` on every value read back from a native tool.
- Every test, CLI and network command carries an explicit timeout. Tests never run the real `agy`: only the stub under `plugins/dforge/tests/fixtures/stub-agy/` (or the acceptance test's own stub) on the suite's PATH.
- Tests never touch `$HOME/.claude` or `$HOME/.gemini`: they keep exporting `HOME`, `DR_AGY_SESSION_DIR`, `DR_AGY_POLICY` and `CLAUDE_CODE_SESSION_ID` under the suite's temporary directory, and unset `CLAUDE_CONFIG_DIR`.
- `scripts/run-codex-task.sh`, `scripts/codex-gate` and their tests keep their behaviour and output. Codex callers of `executor_session_mark_off` pass two arguments and get exactly today's record.
- Native Opus and the native Claude assignment table are unchanged; only the `agy-*` blocks change.
- Reset arithmetic uses `date -u +%s` and shell arithmetic only. An epoch becomes ISO 8601 UTC (`%Y-%m-%dT%H:%M:%SZ`) through GNU `date -u -d "@<epoch>"`, falling back to BSD `date -u -r <epoch>`, and is null when both fail.
- A test that depends on the clock brackets the run (`before=$(date -u +%s)` … `after=$(date -u +%s)`) and checks the value lies between `before + n` and `after + n`; it never pins an exact second.
- Commits use `<type>(<scope>): <subject>` (subject 50 characters or fewer, imperative, no period), author `Darkraise <quangtc94@gmail.com>`, and no AI attribution of any kind.
- Windows Git Bash: a native program (`git.exe`, `jq.exe`) given a path built from `$PWD`, `$(pwd)` or `$TMPDIR` gets a POSIX form it cannot open, or has its argument rewritten when path conversion is on (`MSYS_NO_PATHCONV` unset). Convert the path with `cygpath -m` before the call (dforge's `dr_native_path`, `plugins/dforge/scripts/lib/native-path.sh`), and feed `jq` a file on stdin in a script that exports `MSYS_NO_PATHCONV`.
- Windows Git Bash: files a Windows tool wrote, and native program output, end lines with `\r`, which `read`, `awk` and `[ = ]` keep. Pipe through `tr -d '\r'` before comparing or parsing.
- Windows Git Bash: `awk -v name=value` processes backslash escapes in the value, so a regex or a Windows path changes. Pass the value in the environment and read `ENVIRON["NAME"]`.
- uutils (ubuntu-latest): a lock built on `mkdir` failing when the directory exists does not exclude a second process. Create the lock file with `set -C` (noclobber), or use `flock`.
- uutils (ubuntu-latest): `timeout` signals only the command it started, so the command's children keep running. Run the command in its own process group (`setsid`) and signal the group.

## Contracts

**C1. Ladder blocks** in `plugins/dforge/reference/ladder.md`, replacing the current bodies of the three fenced blocks:

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

**C2. Wrapper admission.** `run-agy-task.sh` admits `--model` when it is column 2 of an `agy-assignment` row, or the model part (before `/`) of an `agy-successor` column-2 target other than `HANDBACK`. Any other model: exit 2 before anything is spawned, stderr `run-agy-task: model is not an agy-assignment or agy-successor rung: <model>`. The effort check and the `agy-timeout` lookup are unchanged.

**C3. Session file.** The `agy` session file may carry a `fallback` object, `{"usable": false, "reason": "quota", "resets_at": <ISO string|null>, "resets_at_epoch": <integer|null>}`, keys in that order. Top-level `resets_at` / `resets_at_epoch` hold the lane quota's reset.
- `executor_session_write <id> <json>`: when `<json>` has no `fallback` key and the prior file parses with a `fallback` object, the written file carries that object; when `<json>` has `"fallback": null`, the written file has no `fallback` key. Otherwise unchanged (one rename, week-old pruning).
- `executor_session_mark_off <id> <reason> [<epoch>]`: as today when the third argument is missing or empty. When it is a whole number, `resets_at_epoch` is that number (a JSON number) and `resets_at` its ISO form (null when both `date` forms fail). The prior `fallback` object is kept.
- `executor_session_mark_fallback_off <id> [<epoch>]`: new. Keeps every field of the prior file (`{}` when absent or unparsable), sets `session_id` to this session, and sets `fallback` to the object above with the epoch and its ISO form, or both null when the epoch is missing or empty. Returns 0 doing nothing when there is no session id.

**C4. Gate line.** `agy-gate usable=<bool> reason=<r> review=false lane=<bool> resets_at=<iso|-> fallback=<on|off> fallback_resets_at=<iso|-> source=<probe|cache|setting>`.
- A cached `usable:false, reason:"quota"` is reused, `--refresh` included, while its `resets_at_epoch` is null, absent, non-numeric, or greater than `date -u +%s`; then `resets_at=` prints the cached `resets_at` (`-` when the epoch reads null or `resets_at` is null), and the gate writes the cached reset fields back (both null when the epoch was non-numeric). Once the epoch is not in the future, the cache is not used and the gate probes.
- Other cached answers keep today's rules. A probe writes both reset fields null.
- `fallback` is read from the session file whenever the file is readable, whatever the source. With no object: `fallback=on fallback_resets_at=-`. With an object whose epoch is null, absent, non-numeric or in the future: `fallback=off`, `fallback_resets_at=` its `resets_at` when the epoch is numeric and `resets_at` is a string, else `-`, and the object is kept. With an epoch not in the future: `fallback=on fallback_resets_at=-`, and the gate's write passes `"fallback": null` so the object is dropped.

**C5. Wrapper quota marks and refusal.**
- Preflight, after the `lane=true` check: a `--model` beginning `claude-` needs ` fallback=on ` in the gate line. Otherwise exit 2 before `dr_task_open`, stderr `run-agy-task: the agy Claude fallback is off until <until> (quota)`, where `<until>` is the line's `fallback_resets_at` value, or `the end of the session` when it is `-`, empty or absent.
- On `reason=quota` with `quota_source=agy`, the wrapper reads `Resets in ` followed by `<n>d`, `<n>h`, `<n>m`, `<n>s` in that order, each optional, at least one present, from the cause text. The epoch is `date -u +%s` taken after `agy` exits plus those seconds; no match leaves it empty. A `claude-` model calls `executor_session_mark_fallback_off agy "$epoch"` and reports `marked=fallback`; any other model calls `executor_session_mark_off agy quota "$epoch"` and reports `marked=lane`. With `quota_source=stderr` nothing is marked and the report says `marked=none`.
- Report: the fenced block of `## Agy error` is `reason=<r>`, then on `reason=quota` a `marked=<lane|fallback|none>` line, then `until=<iso>` when a reset was parsed and its ISO form is not null, then `timedOut=true` when it applies, then the raw error text.

**C6. Ledger records** (reference text, written literally, with no `|` inside a table cell): a fallback-quota hand-back records `executor agy HANDBACK - fallback quota until <iso>`, or `executor agy HANDBACK - fallback quota until session end` when the reset is `-`; a lane-quota hand-back records `executor agy HANDBACK - quota`, plus ` until <iso>` when the refreshed gate's `resets_at` is not `-`.

## Assumptions (evidence)

- Antigravity limits Claude and Gemini separately, and its quota `.error` reads `RESOURCE_EXHAUSTED (code 429): Individual quota reached. Please upgrade your subscription to increase your limits. Resets in 4h47m34s.`: `docs/dforge/notes/2026-11-03-agy-calibration-3-8.md` (both H2 Claude runs failed at 14:09 and 14:11 on 2026-11-03, after which Argon completed H2 and H3).
- Whether Flash and Argon share one Gemini limit: unverified and accepted (spec, Riskiest assumption); closing the whole lane on a Gemini quota is the conservative reading.
- Only `scripts/agy-gate`, `scripts/run-agy-task.sh` and three suites (`agy-gate.test.sh`, `run-agy-task.test.sh`, `antigravity-executor-lane.acceptance.test.sh`) read or pin the `agy-gate` line: `rg -ln "agy-gate usable" plugins/dforge`, 2026-11-03.
- `tests/plan-lint.test.sh:825-830` reads the shipped `agy-assignment` block at run time, so its routing cases follow the new rows unchanged; `tests/lane-breaker.test.sh` uses ledger strings, not the ladder.
- `scripts/plan-revise` writes nothing and prints each unit's rung from the live block (`plugins/dforge/scripts/plan-revise:7-10`); dforge:revising-plans makes the edits. The migration note says so.
- The GNU-then-BSD `date` chain is already relied on in CI: `plugins/dforge/scripts/codex-gate:85-87`. `date -u -d @4070908800 +%Y-%m-%dT%H:%M:%SZ` printed `2099-01-01T00:00:00Z` on this host, 2026-11-03.
- Both stubs print a quota from an environment variable: `STUB_AGY_MODE=error STUB_AGY_ERROR=…` (`tests/run-agy-task.test.sh:255`) and `STUB_MODE=error STUB_ERROR=…` in the acceptance test (`antigravity-executor-lane.acceptance.test.sh:556`).
- There is no changelog file in the repository (`rg --files -uu | rg -i changelog`, 2026-11-03, no output); the migration sentence goes in a README `## Migrating to 4.11` section, as earlier releases did.
- `agy-gate` printed `lane=true` on 2026-11-03, but the installed 4.10.0 ladder routes totals 3-8 to Claude rungs through `agy`, which the owner ruled out, so no task carries an `**Executor:**` line. The ruling is in this auto run's ruling list (`scripts/auto-run ruling list`, "Planner, plan: agy executor offer — not ticked"), resting on the owner's 2026-11-03 answer quoted in the spec's Decisions; the four `lane-eligible` warnings plan-lint prints are that ruling. `codex-gate` printed `reason=setting`.
- Plan review round 1 scored executability 13 (borderline). All four Important findings (ambiguous insertion anchors in Task 2, two Task 4 checks that could not fail or could not pass, a `|` inside table cells) and the Minor ones were fixed in place; depth standard caps the review at one round.

## Task index

1. Route agy Gemini first and admit successor rungs
2. Mark quota resets and the Claude fallback in the gate
3. Mark the quota's family and refuse a closed fallback
4. Document the Gemini-first lane and release 4.11.0

---

### Task 1: Route agy Gemini first and admit successor rungs

**Files:**
- Modify: `plugins/dforge/reference/ladder.md` (the `### Agy assignment`, `### Agy successor` and `### Agy timeout` subsections)
- Modify: `plugins/dforge/scripts/run-agy-task.sh` (the admission check after `[ -d "$(dirname "$report")" ]`)
- Test: `plugins/dforge/tests/lanes.test.sh`
- Test: `plugins/dforge/tests/run-agy-task.test.sh`
- Test: `plugins/dforge/tests/antigravity-executor-lane.acceptance.test.sh`

**Interfaces:**
- Consumes: nothing from another task.
- Produces: C1 (the three blocks) and C2 (admission and its refusal message), which Tasks 3 and 4 rely on.

**Items:** 1, 2, 5, 6

**Implementer:** dforge:impl-opus-high
**Evaluation:** files 1 - spec 2 - coupling 2 - risk 2 = 7

- [ ] **Step 1: Extend the tests**

In `plugins/dforge/tests/lanes.test.sh`, replace the check that begins `check "agy-assignment rows 3 to 8 mirror the native Claude table"` (three lines) with:

```bash
check "agy-assignment runs Flash medium on 0-2, Argon low on 3-4 and Argon high on 5-8" \
  "$(printf '%s\n' "$agy_assignment" | tr '\n' ',')" \
  "0 gemini-3.8-flash medium,1 gemini-3.8-flash medium,2 gemini-3.8-flash medium,3 gemini-4-argon low,4 gemini-4-argon low,5 gemini-4-argon high,6 gemini-4-argon high,7 gemini-4-argon high,8 gemini-4-argon high,"
check "no agy-assignment row starts on a Claude model" \
  "$(printf '%s\n' "$agy_assignment" | awk '$2 ~ /^claude-/' | grep -c .)" "0"
```

Directly after the line `check "agy-successor block is present" …`, add:

```bash
check "agy-successor sends each Gemini rung to Sonnet and each Sonnet rung back" \
  "$(printf '%s\n' "$agy_successor" | tr '\n' ',')" \
  "gemini-3.8-flash/medium claude-sonnet-5-5/medium,gemini-4-argon/low claude-sonnet-5-5/medium,gemini-4-argon/high claude-sonnet-5-5/high,claude-sonnet-5-5/medium HANDBACK,claude-sonnet-5-5/high HANDBACK,"
bad_agy_claude=NONE
while read -r from to; do
  case "$from" in claude-*) [ "$to" = HANDBACK ] || bad_agy_claude="$from->$to" ;; esac
done <<< "$agy_successor"
check "every Claude agy-successor source hands back" "$bad_agy_claude" "NONE"
```

Directly after the line `check "agy-timeout block is present" …`, add:

```bash
check "agy-timeout gives Argon 900 s at low and 1500 s at high, one row per reachable rung" \
  "$(printf '%s\n' "$agy_timeouts" | tr '\n' ',')" \
  "gemini-3.8-flash/medium 900,gemini-4-argon/low 900,gemini-4-argon/high 1500,claude-sonnet-5-5/medium 1200,claude-sonnet-5-5/high 1800,"
check "no agy block names claude-opus-5-5" \
  "$(printf '%s\n' "$agy_assignment" "$agy_successor" "$agy_timeouts" | grep -c 'claude-opus-5-5')" "0"
```

Directly after the check `"the agy gate subsection states why its floor is 0"`, add:

```bash
check "ladder.md names the 3-8 calibration note as the source of agy rows 3-8" \
  "$(grep -cF 'docs/dforge/notes/2026-11-03-agy-calibration-3-8.md' "$LADDER")" "1"
check "the note ladder.md names is committed" \
  "$(git -C "$HERE/../../.." ls-files --error-unmatch docs/dforge/notes/2026-11-03-agy-calibration-3-8.md >/dev/null 2>&1 && echo yes || echo no)" "yes"
check "ladder.md no longer says agy rows 3 to 8 mirror the native table" \
  "$(grep -cF 'Totals 3 to 8 mirror the native Claude assignment table' "$LADDER")" "0"
```

Replace the line `smoke_rung=$(block agy-assignment | awk '$1 == 5 { print $2 "/" $3 }')` and the check name after it:

```bash
# The 2026-11-02 record is history: its smoke run used total 5's rung of the time.
smoke_rung=claude-sonnet-5-5/high
check "the 2026-11-02 smoke run used claude-sonnet-5-5/high" \
```

(the `"$(awk -F'|' -v r="$smoke_rung" …` argument lines below it stay as they are).

In `plugins/dforge/tests/run-agy-task.test.sh`, replace the line `check "rejects a rung with no agy-timeout row" "$(dry_rc --model claude-opus-5-5 --effort low)" "2"` with:

```bash
check "rejects a rung with no agy-timeout row" "$(dry_rc --model gemini-3.8-flash --effort low)" "2"
check "names the missing agy-timeout row" "$(grep -c 'no agy-timeout row for gemini-3.8-flash/low' "$fixture/err")" "1"
check "rejects claude-opus-5-5, which no agy block names" "$(dry_rc --model claude-opus-5-5 --effort high)" "2"
check "the refusal names both blocks" \
  "$(grep -c 'model is not an agy-assignment or agy-successor rung: claude-opus-5-5' "$fixture/err")" "1"
check "admits Argon low from agy-assignment" \
  "$(dry --model gemini-4-argon --effort low | sed -n '2p' | jq -r '.timeoutSeconds')" "900"
check "admits Argon high from agy-assignment" \
  "$(dry --model gemini-4-argon --effort high | sed -n '2p' | jq -r '.timeoutSeconds')" "1500"
check "admits a Claude rung named only in agy-successor" "$(dry_rc --model claude-sonnet-5-5 --effort high)" "0"
```

In the same file, change `run --model claude-opus-5-5 --effort high --resume conv-1` (above `check "a resume with another model is refused"`) to `run --model gemini-4-argon --effort high --resume conv-1`.

In `plugins/dforge/tests/antigravity-executor-lane.acceptance.test.sh`, A3: replace the comment `# Totals 3 to 8 mirror the native table: …` and the `for pair in "3 claude-sonnet-5-5 medium" …` line with:

```bash
  # Totals 3 to 8 run on Argon (docs/dforge/notes/2026-11-03-agy-calibration-3-8.md).
  for pair in "3 gemini-4-argon low" "4 gemini-4-argon low" "5 gemini-4-argon high" "6 gemini-4-argon high" "7 gemini-4-argon high" "8 gemini-4-argon high"; do
```

A9: change `runw --model claude-opus-5-5 --effort high --resume conv-pin` to `runw --model gemini-4-argon --effort high --resume conv-pin`.

A16: replace `check "A16: HANDBACK appears" "$(awk '$2 == "HANDBACK"' <<<"$succ" | wc -l | tr -d ' ')" "1"` with:

```bash
  check "A16: HANDBACK ends every Claude rung" "$(awk '$2 == "HANDBACK"' <<<"$succ" | wc -l | tr -d ' ')" \
    "$(awk '$1 ~ /^claude-/' <<<"$succ" | wc -l | tr -d ' ')"
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `timeout 300 bash plugins/dforge/tests/lanes.test.sh; timeout 600 bash plugins/dforge/tests/run-agy-task.test.sh; timeout 900 bash plugins/dforge/tests/antigravity-executor-lane.acceptance.test.sh A3 A9 A16`
Expected: FAIL on the new row checks, `ladder.md names the 3-8 calibration note`, `rejects claude-opus-5-5`, `the refusal names both blocks`, `admits Argon low/high`, the A3 Argon rows and A16's HANDBACK count.

- [ ] **Step 3: Implement**

1. `reference/ladder.md`: replace the bodies of the `agy-assignment`, `agy-successor` and `agy-timeout` fenced blocks with C1, exactly.
2. Under `### Agy assignment`, replace the paragraph beginning "Totals 3 to 8 mirror the native Claude assignment table" with one paragraph that names `docs/dforge/notes/2026-11-03-agy-calibration-3-8.md` exactly once as the source of rows 3-8 (Argon low passed all three replayed tasks scored 3-4, Argon high all three scored 6-7), says total 5 runs Argon high because it is the only rung measured on all three high tasks, and keeps the sentence that the models are those `agy models` lists. Add a paragraph saying why no row starts on Claude: the Claude quota on Antigravity is small (the calibration drained it after about 500k tokens), so it is spent only on the single retry after a Gemini run fails.
3. Under `### Agy successor`, keep the existing paragraphs; the ranking paragraph stays true. Add one sentence: every row is a Gemini source with a Claude target, or a Claude source with `HANDBACK`, and no row names `claude-opus-5-5`.
4. Under `### Agy timeout`, after "The values are seconds.", add: the Argon rows follow the 2026-11-02 rule, the larger of 900 and three times the slowest passing run rounded up to a multiple of 300 (low: 3 × 137 s = 411 s, so 900; high: 3 × 426 s = 1278 s, so 1500), and the Claude rows keep their values.
5. `scripts/run-agy-task.sh`: replace the admission line `block agy-assignment | awk '{print $2}' | sort -u | grep -qxF -- "$model" || die "model is not a rung in agy-assignment: $model"` so that the admitted set is C2's: column 2 of `agy-assignment` plus the model part of every `agy-successor` target that is not `HANDBACK`, still matched word-exact (`grep -qxF`). The refusal is C2's message through `die`. Do not move the check: it stays before the effort check and before `--dry-run` exits.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `timeout 300 bash plugins/dforge/tests/lanes.test.sh; timeout 600 bash plugins/dforge/tests/run-agy-task.test.sh; timeout 900 bash plugins/dforge/tests/antigravity-executor-lane.acceptance.test.sh A3 A9 A16`
Expected: each ends `0 failed`.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/reference/ladder.md plugins/dforge/scripts/run-agy-task.sh plugins/dforge/tests/lanes.test.sh plugins/dforge/tests/run-agy-task.test.sh plugins/dforge/tests/antigravity-executor-lane.acceptance.test.sh
git commit -m "feat(dforge): route agy Gemini first"
```

### Task 2: Mark quota resets and the Claude fallback in the gate

**Files:**
- Modify: `plugins/dforge/scripts/lib/executor-session.sh` (`executor_session_write`, `executor_session_mark_off`, a new `executor_session_mark_fallback_off`)
- Modify: `plugins/dforge/scripts/agy-gate` (header comment, cache read, session write, output line)
- Test: `plugins/dforge/tests/executor-session.test.sh`
- Test: `plugins/dforge/tests/agy-gate.test.sh`

**Interfaces:**
- Consumes: nothing from another task.
- Produces: C3 (session functions and file shape) and C4 (the gate line), which Task 3 relies on.

**Items:** 3, 4

**Implementer:** dforge:impl-opus-high
**Evaluation:** files 1 - spec 2 - coupling 2 - risk 2 = 7

- [ ] **Step 1: Extend the tests**

In `plugins/dforge/tests/executor-session.test.sh`, insert before the `# --- pruning ---` line (the existing two-argument `mark_off` cases stay unchanged):

```bash
# --- reset times and the fallback mark -------------------------------------
FAR=4070908800 FAR_ISO=2099-01-01T00:00:00Z
srec="$TMP/stub/session-test.json"
executor_session_write stub '{"session_id":"session-test","usable":true,"lane":true,"reason":"ok"}'
executor_session_mark_off stub quota "$FAR"
check "mark_off with a reset epoch records it as a number" \
  "$(jq -r '.resets_at_epoch | type' "$srec")/$(jq -r '.resets_at_epoch' "$srec")" "number/$FAR"
check "mark_off with a reset epoch records it in ISO 8601 UTC" "$(jq -r '.resets_at' "$srec")" "$FAR_ISO"
executor_session_mark_off stub quota ""
check "mark_off with an empty reset writes both reset fields null" \
  "$(jq -r '[.resets_at, .resets_at_epoch] | map(tostring) | join(",")' "$srec")" "null,null"

executor_session_write stub '{"session_id":"session-test","usable":true,"lane":true,"reason":"ok","stub_version":"0.0.0-stub"}'
executor_session_mark_fallback_off stub "$FAR"
check "mark_fallback_off leaves usable, lane, reason and versions alone" \
  "$(jq -r '[.usable, .lane, .reason, .stub_version] | map(tostring) | join(",")' "$srec")" "true,true,ok,0.0.0-stub"
check "mark_fallback_off writes the fallback object" \
  "$(jq -c '.fallback' "$srec")" "{\"usable\":false,\"reason\":\"quota\",\"resets_at\":\"$FAR_ISO\",\"resets_at_epoch\":$FAR}"
executor_session_mark_off stub quota
check "a lane mark_off keeps the fallback object" "$(jq -r '.fallback.resets_at_epoch' "$srec")" "$FAR"
executor_session_write stub '{"session_id":"session-test","usable":true,"lane":true,"reason":"ok"}'
check "a write without a fallback key keeps the prior fallback object" "$(jq -r '.fallback.reason' "$srec")" "quota"
executor_session_write stub '{"session_id":"session-test","usable":true,"lane":true,"reason":"ok","fallback":null}'
check "a write with fallback null drops the object" "$(jq -r 'has("fallback")' "$srec")" "false"
executor_session_mark_fallback_off stub ""
check "mark_fallback_off with no reset writes both reset fields null" \
  "$(jq -c '.fallback' "$srec")" '{"usable":false,"reason":"quota","resets_at":null,"resets_at_epoch":null}'
rm -f "$srec"
executor_session_mark_fallback_off stub "$FAR"
check "mark_fallback_off with no prior file writes the session id and the mark" \
  "$(jq -r '[.session_id, .fallback.reason, (.usable | tostring)] | join(",")' "$srec")" "session-test,quota,null"
rm -f "$srec"
check "mark_fallback_off without a session id succeeds" \
  "$(CLAUDE_CODE_SESSION_ID= executor_session_mark_fallback_off stub "$FAR"; echo $?)" "0"
check "mark_fallback_off without a session id writes no file" "$([ -e "$srec" ] && echo yes || echo no)" "no"
```

In `plugins/dforge/tests/agy-gate.test.sh`, first add the two new fields to every whole gate line the suite pins (each currently ends `resets_at=- source=…`):

```bash
sed -i 's/ resets_at=- source=/ resets_at=- fallback=on fallback_resets_at=- source=/' plugins/dforge/tests/agy-gate.test.sh
```

Then insert, in the `# --- the gate ---` section, directly after the line `setting '{}'` that follows the check `"agyLane off is written for the readers"` (and so directly before the second `if [ "$SPAWNABLE" = yes ]; then` of the file, not the first one, which opens the `agy-probe.mjs` cases above the gate helpers):

```bash
# --- reset times and the Claude fallback mark (A6, A7, A9, A10) ------------
FAR=4070908800 FAR_ISO=2099-01-01T00:00:00Z
seed() { mkdir -p "$SESS"; jq -cn "$1" > "$SESS/s1.json"; }
fresh; seed "{session_id:\"s1\", usable:false, review:false, lane:false, reason:\"quota\", checked_at:\"2026-11-03T00:00:00Z\", resets_at:\"$FAR_ISO\", resets_at_epoch:$FAR, agy_version:\"1.4.12\"}"
gate
check "an unexpired lane quota is kept and prints its reset" "$out" \
  "agy-gate usable=false reason=quota review=false lane=false resets_at=$FAR_ISO fallback=on fallback_resets_at=- source=cache"
gate --refresh
check "--refresh keeps an unexpired lane quota" "$out" \
  "agy-gate usable=false reason=quota review=false lane=false resets_at=$FAR_ISO fallback=on fallback_resets_at=- source=cache"
check "keeping the quota writes its reset time back" "$(field resets_at_epoch)/$(field resets_at)" "$FAR/$FAR_ISO"
check "keeping an unexpired quota starts no agy" "$([ -f "$ARGS" ] && echo yes || echo no)" "no"

fresh; seed '{session_id:"s1", usable:false, review:false, lane:false, reason:"quota", resets_at:"soon", resets_at_epoch:"soon"}'
gate --refresh
check "a non-numeric reset reads as none, so the quota holds for the session" "$out" \
  "agy-gate usable=false reason=quota review=false lane=false resets_at=- fallback=on fallback_resets_at=- source=cache"

fresh; seed "{session_id:\"s1\", usable:true, review:false, lane:true, reason:\"ok\", resets_at:null, resets_at_epoch:null, agy_version:\"1.4.12\", fallback:{usable:false, reason:\"quota\", resets_at:\"$FAR_ISO\", resets_at_epoch:$FAR}}"
gate
check "an unexpired fallback mark turns the fallback off and leaves the lane on" "$out" \
  "agy-gate usable=true reason=ok review=false lane=true resets_at=- fallback=off fallback_resets_at=$FAR_ISO source=cache"
check "the gate's write keeps the unexpired fallback mark" "$(field fallback.resets_at_epoch)" "$FAR"

fresh; seed '{session_id:"s1", usable:true, review:false, lane:true, reason:"ok", agy_version:"1.4.12", fallback:{usable:false, reason:"quota", resets_at:null, resets_at_epoch:null}}'
gate --refresh
check "a fallback mark with no reset holds for the session, --refresh included" \
  "$(sed 's/ source=.*//' <<<"$out")" \
  "agy-gate usable=$(field usable) reason=$(field reason) review=false lane=$(field lane) resets_at=- fallback=off fallback_resets_at=-"

fresh; seed '{session_id:"s1", usable:true, review:false, lane:true, reason:"ok", agy_version:"1.4.12", fallback:{usable:false, reason:"quota", resets_at:"1970-01-01T00:16:40Z", resets_at_epoch:1000}}'
gate
check "an expired fallback mark turns the fallback back on" "$out" \
  "agy-gate usable=true reason=ok review=false lane=true resets_at=- fallback=on fallback_resets_at=- source=cache"
check "the gate drops an expired fallback mark from the file" "$(jq -r 'has("fallback")' "$SESS/s1.json" | tr -d '\r')" "false"
```

(The `--refresh` case above compares against the file's own fields, so it holds whether or not the probe can run on this platform.)

Inside that second `if [ "$SPAWNABLE" = yes ]; then` block, directly before the `else` whose `skip` reads `the gate cases that need a usable probe`, add:

```bash
  fresh; seed '{session_id:"s1", usable:false, review:false, lane:false, reason:"quota", resets_at:"1970-01-01T00:16:40Z", resets_at_epoch:1000, agy_version:"1.4.12"}'
  gate
  check "an expired lane quota is probed again and the lane reopens" "$out" \
    "agy-gate usable=true reason=ok review=false lane=true resets_at=- fallback=on fallback_resets_at=- source=probe"
  check "the reopened lane carries no reset time" "$(field resets_at)/$(field resets_at_epoch)" "null/null"

  fresh; seed "{session_id:\"s1\", usable:false, review:false, lane:false, reason:\"logged-out\", agy_version:\"1.4.12\", fallback:{usable:false, reason:\"quota\", resets_at:\"$FAR_ISO\", resets_at_epoch:$FAR}}"
  gate --refresh
  check "a probe write keeps an unexpired fallback mark" "$out" \
    "agy-gate usable=true reason=ok review=false lane=true resets_at=- fallback=off fallback_resets_at=$FAR_ISO source=probe"
  check "the probe left the fallback object in the file" "$(field fallback.reason)/$(field fallback.resets_at_epoch)" "quota/$FAR"
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `timeout 120 bash plugins/dforge/tests/executor-session.test.sh; timeout 300 bash plugins/dforge/tests/agy-gate.test.sh`
Expected: FAIL: `mark_off with a reset epoch …`, `mark_fallback_off …` (command not found), every whole-line gate pin (no `fallback=` field yet), and the new reset and fallback cases.

- [ ] **Step 3: Implement**

1. `executor_session_write <id> <json>`: before the write, merge per C3: read the prior file parsed (an absent or unparsable file means no prior object); when `<json>` lacks a `fallback` key and the prior has a `fallback` object, add it; when `<json>` has `"fallback": null`, delete the key. Keep the single `mv -f` rename and the pruning. When `<json>` itself does not parse, write it unchanged as today.
2. Add a private helper that turns a whole-number epoch into the ISO form with the Global Constraints' `date` chain, printing nothing when both fail.
3. `executor_session_mark_off <id> <reason> [<epoch>]`: when the third argument matches `^[0-9]+$`, write `resets_at_epoch` as a JSON number and `resets_at` as its ISO form (null when the helper printed nothing); a missing or empty third argument writes both null exactly as today. Update the function's comment: the reset is the caller's to supply, and without one the mark lasts the session. Everything else in the record is unchanged; the `fallback` object survives through step 1. In the library's header comment, replace "a quota is account-wide, so the answer belongs to the session" with: a quota belongs to the account, not to any one project, so the answer belongs to the session; for `agy`, Claude and Gemini models are limited separately, which is why the file carries a separate `fallback` mark.
4. Add `executor_session_mark_fallback_off <id> [<epoch>]` per C3, writing through `executor_session_write`, with a comment saying it marks only the Claude fallback and leaves `usable`, `lane` and `reason` alone.
5. `scripts/agy-gate`:
   - Cache read: also read `resets_at`, `resets_at_epoch` (treat a value not matching `^[0-9]+$` as empty) and the `fallback` object. The `case "$c_usable"` clause reuses a cached `false:quota` only while the epoch is empty or greater than `date -u +%s`, with or without `--refresh`; other answers keep today's rule.
   - Fallback: computed per C4 whenever `$file` is readable, independent of the cache decision and of the setting.
   - Session write: a reused quota writes its cached `resets_at` (null when the epoch was empty) and `resets_at_epoch`; every other answer writes both null. Add `fallback: null` to the written object only when the mark expired, so the writer drops it; otherwise omit the key so the writer carries it.
   - Output: the C4 line.
   - Header: replace "a quota mark has no reset time and stays for the session, --refresh included" with: a quota mark lasts until the reset time the error named, or for the session when it named none, `--refresh` included; a quota on a Claude model marks only the Claude fallback, which the line reports as `fallback=` and `fallback_resets_at=`. Update the `# Output:` line to C4.
   - Keep the existing comment explaining why `--refresh` never probes a quota away, extended to say an expired reset is the one case that probes.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `timeout 120 bash plugins/dforge/tests/executor-session.test.sh; timeout 300 bash plugins/dforge/tests/agy-gate.test.sh; timeout 120 bash plugins/dforge/tests/codex-gate.test.sh`
Expected: each ends `0 failed`; `codex-gate.test.sh` proves the shared writer did not change Codex.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/scripts/lib/executor-session.sh plugins/dforge/scripts/agy-gate plugins/dforge/tests/executor-session.test.sh plugins/dforge/tests/agy-gate.test.sh
git commit -m "feat(dforge): expire agy quota marks at their reset"
```

### Task 3: Mark the quota's family and refuse a closed fallback

**Files:**
- Modify: `plugins/dforge/scripts/run-agy-task.sh` (the gate check after `gate_line=$(bash "$GATE" …`, the quota classification after `is_quota()`, the `## Agy error` block)
- Test: `plugins/dforge/tests/run-agy-task.test.sh`
- Test: `plugins/dforge/tests/antigravity-executor-lane.acceptance.test.sh`
- Modify: `scripts/test-shards.mjs` (the `'run-agy-task.test.sh'` weight and its comment)

**Interfaces:**
- Consumes: C2 from Task 1 (Gemini and successor rungs are admitted); C3 and C4 from Task 2 (`executor_session_mark_off` with an epoch, `executor_session_mark_fallback_off`, the gate's `fallback=` fields).
- Produces: C5 (the refusal message and the `marked=` / `until=` report lines), which Task 4 documents.

**Items:** 2, 3, 4

**Implementer:** dforge:impl-opus-high
**Evaluation:** files 1 - spec 2 - coupling 2 - risk 2 = 7

- [ ] **Step 1: Extend the tests**

Before editing anything, record the suite's baseline Linux time: `start=$(date +%s); timeout 600 bash plugins/dforge/tests/run-agy-task.test.sh >/dev/null; echo $(( $(date +%s) - start ))`. Keep the number for Step 4.

In `plugins/dforge/tests/run-agy-task.test.sh`, change the default stub line in the `printf '#!/usr/bin/env bash\nprintf …' > "$fixture/gate-stub"` command from `agy-gate usable=true reason=ok review=false lane=true resets_at=- source=cache` to `agy-gate usable=true reason=ok review=false lane=true resets_at=- fallback=on fallback_resets_at=- source=cache`.

Directly after the check `"a closed lane never launches agy"`, add:

```bash
# --- the Claude fallback runs only while the gate says fallback=on (A8) -------
FB_OFF='agy-gate usable=true reason=ok review=false lane=true resets_at=- fallback=off fallback_resets_at=2099-01-01T00:00:00Z source=cache'
n=$(calls)
newwork fallback-off
GATE_STUB_LINE="$FB_OFF" run
check "a Claude model is refused while the fallback is off" "$?" "2"
check "the refusal names the reset time" \
  "$(grep -c 'the agy Claude fallback is off until 2099-01-01T00:00:00Z (quota)' "$fixture/err")" "1"
newwork fallback-session
GATE_STUB_LINE='agy-gate usable=true reason=ok review=false lane=true resets_at=- fallback=off fallback_resets_at=- source=cache' run
check "a fallback mark with no reset refuses a Claude model" "$?" "2"
check "that refusal says the end of the session" \
  "$(grep -c 'the agy Claude fallback is off until the end of the session (quota)' "$fixture/err")" "1"
newwork fallback-absent
GATE_STUB_LINE='agy-gate usable=true reason=ok review=false lane=true resets_at=- source=cache' run
check "a gate line without the fallback field refuses a Claude model" "$?" "2"
check "the refused Claude runs never launch agy" "$(calls)" "$n"
newwork fallback-gemini
GATE_STUB_LINE="$FB_OFF" run --model gemini-3.8-flash --effort medium
check "a Gemini model still runs while the fallback is off" "$?" "0"
check "the Gemini run launched agy" "$(calls)" "$((n + 1))"
```

Replace the block from the line `newwork session-quota` through the check `"a quota seen only on stderr leaves the session file absent"` with:

```bash
sfield() { jq -r "$1 | tostring" "$session_file" 2>/dev/null | tr -d '\r'; }
iso() { date -u -d "@$1" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -r "$1" +%Y-%m-%dT%H:%M:%SZ; }
in_window() { # in_window <epoch> <before> <after> <seconds>
  if [ "$1" -ge $(( $2 + $4 )) ] 2>/dev/null && [ "$1" -le $(( $3 + $4 )) ]; then echo yes; else echo no; fi; }
seed_open() { rm -rf "$DR_AGY_SESSION_DIR"; mkdir -p "$DR_AGY_SESSION_DIR"
  printf '{"session_id":"run-agy-task-test","usable":true,"review":false,"lane":true,"reason":"ok","resets_at":null,"resets_at_epoch":null}\n' > "$session_file"; }
quota_lines() { grep -A"$1" '^reason=quota$' "$R" | tr -d '\r' | tr '\n' ' '; }
QUOTA_RESET='RESOURCE_EXHAUSTED (code 429): Individual quota reached. Please upgrade your subscription to increase your limits. Resets in 1h2m3s.'
QUOTA_BARE='Quota exceeded for this account'

# A Gemini quota closes the lane until the reset the error names (A6, A14).
seed_open; newwork lane-reset
before=$(date -u +%s)
STUB_AGY_MODE=error STUB_AGY_ERROR="$QUOTA_RESET" run --model gemini-3.8-flash --effort medium
after=$(date -u +%s)
epoch=$(sfield .resets_at_epoch)
check "a Gemini quota closes the lane" "$(session_state)" "false/false/quota"
check "a Gemini quota's reset is 3723 s after agy exits" "$(in_window "$epoch" "$before" "$after" 3723)" "yes"
check "a Gemini quota's reset is written in ISO 8601 UTC" "$(sfield .resets_at)" "$(iso "$epoch")"
check "a Gemini quota writes no fallback mark" "$(sfield 'has("fallback")')" "false"
check "the report says the lane was marked until the reset" "$(quota_lines 2)" "reason=quota marked=lane until=$(iso "$epoch") "

# Without a reset the lane stays closed for the session (A10).
seed_open; newwork lane-bare
STUB_AGY_MODE=error STUB_AGY_ERROR="$QUOTA_BARE" run --model gemini-3.8-flash --effort medium
check "a Gemini quota with no reset closes the lane for the session" \
  "$(session_state)/$(sfield .resets_at_epoch)" "false/false/quota/null"
check "the report says the lane was marked" "$(quota_lines 1)" "reason=quota marked=lane "
check "a quota with no reset prints no until line" "$(grep -c '^until=' "$R")" "0"

# A Claude quota closes only the fallback (A7, A10, A14).
seed_open; newwork fallback-reset
before=$(date -u +%s)
STUB_AGY_MODE=error STUB_AGY_ERROR="$QUOTA_RESET" run
after=$(date -u +%s)
epoch=$(sfield .fallback.resets_at_epoch)
check "a Claude quota leaves the lane open" "$(session_state)" "true/true/ok"
check "a Claude quota marks the fallback off" "$(sfield .fallback.usable)/$(sfield .fallback.reason)" "false/quota"
check "a Claude quota's reset is 3723 s after agy exits" "$(in_window "$epoch" "$before" "$after" 3723)" "yes"
check "a Claude quota's reset is written in ISO 8601 UTC" "$(sfield .fallback.resets_at)" "$(iso "$epoch")"
check "the report says the fallback was marked until the reset" "$(quota_lines 2)" "reason=quota marked=fallback until=$(iso "$epoch") "
seed_open; newwork fallback-bare
STUB_AGY_MODE=error STUB_AGY_ERROR="$QUOTA_BARE" run
check "a Claude quota with no reset marks the fallback for the session" \
  "$(session_state)/$(sfield .fallback.usable)/$(sfield .fallback.resets_at_epoch)" "true/true/ok/false/null"
check "the report says the fallback was marked" "$(quota_lines 1)" "reason=quota marked=fallback "

rm -rf "$DR_AGY_SESSION_DIR"
newwork session-text
STUB_AGY_MODE=text STUB_AGY_TEXT="RESOURCE_EXHAUSTED: try later" run --model gemini-3.8-flash --effort medium
check "a plain-text quota turns agy off for the session" "$(session_state)" "false/false/quota"
# stderr can carry output of the commands the model ran, so a quota word there
# labels the run but marks nothing (A11).
rm -rf "$DR_AGY_SESSION_DIR"
newwork session-stderr
PATH="$fixture/stderrshim:$PATH" run --model gemini-3.8-flash --effort medium
check "a quota seen only on stderr is still reported as quota" "$(grep -c '^reason=quota$' "$R")" "1"
check "a quota seen only on stderr reports marked=none" "$(quota_lines 1)" "reason=quota marked=none "
check "a quota seen only on stderr leaves the session file absent" "$([ -e "$session_file" ] && echo yes || echo no)" "no"
```

In the real-gate block (`if [ "$SPAWNABLE" = yes ]; then`), change `STUB_AGY_MODE=error STUB_AGY_ERROR="quota exceeded" run` to `STUB_AGY_MODE=error STUB_AGY_ERROR="quota exceeded" run --model gemini-3.8-flash --effort medium` and `run --task-id task-two` to `run --task-id task-two --model gemini-3.8-flash --effort medium`. Then, directly after the check `"the next wrapper call never runs agy"`, add:

```bash
  gate_line() { bash "$P/scripts/agy-gate" "$@" 2>/dev/null | tail -1 | tr -d '\r'; }
  # A reset time ends the lane mark: once it has passed, the gate probes again (A6).
  rm -rf "$DR_AGY_SESSION_DIR"; gate_line >/dev/null
  newwork quota-reset
  STUB_AGY_MODE=error STUB_AGY_ERROR="$QUOTA_RESET" run --model gemini-3.8-flash --effort medium
  epoch=$(sfield .resets_at_epoch)
  check "the gate prints the lane's reset time" "$(gate_line)" \
    "agy-gate usable=false reason=quota review=false lane=false resets_at=$(iso "$epoch") fallback=on fallback_resets_at=- source=cache"
  jq '.resets_at_epoch = 1000' "$session_file" > "$session_file.tmp" && mv -f "$session_file.tmp" "$session_file"
  check "a passed reset reopens the lane through a fresh probe" "$(gate_line)" \
    "agy-gate usable=true reason=ok review=false lane=true resets_at=- fallback=on fallback_resets_at=- source=probe"

  # A Claude quota closes only the fallback (A7, A10).
  newwork fallback-gate
  STUB_AGY_MODE=error STUB_AGY_ERROR="$QUOTA_RESET" run
  epoch=$(sfield .fallback.resets_at_epoch)
  check "after a Claude quota the gate keeps the lane and turns the fallback off" "$(gate_line)" \
    "agy-gate usable=true reason=ok review=false lane=true resets_at=- fallback=off fallback_resets_at=$(iso "$epoch") source=cache"
  n=$(calls)
  newwork fallback-gate-gemini
  run --model gemini-3.8-flash --effort medium
  check "a Gemini run still launches agy while the fallback is off" "$(calls)" "$((n + 1))"
  newwork fallback-gate-claude
  run
  check "a Claude run is refused while the fallback is off" "$?" "2"
  check "the refused Claude run never launches agy" "$(calls)" "$((n + 1))"
  rm -rf "$DR_AGY_SESSION_DIR"; gate_line >/dev/null
  newwork fallback-gate-bare
  STUB_AGY_MODE=error STUB_AGY_ERROR="$QUOTA_BARE" run
  check "a Claude quota with no reset keeps the fallback off through --refresh" "$(gate_line --refresh)" \
    "agy-gate usable=true reason=ok review=false lane=true resets_at=- fallback=off fallback_resets_at=- source=probe"
```

In `plugins/dforge/tests/antigravity-executor-lane.acceptance.test.sh`, A8: change `STUB_MODE=error STUB_ERROR="$text" runw` to `STUB_MODE=error STUB_ERROR="$text" runw --model gemini-3.8-flash --effort medium`, and change the comment above the control case to `# A different error text, or a quota on the Claude fallback, leaves the lane open.` Then, directly after the control's `matches "A8: control: a non-quota error leaves the lane on" …` line, add:

```bash
    fresh_session quota-claude
    newwork qclaude
    STUB_MODE=error STUB_ERROR='Quota exceeded for this account' runw
    g=$(gate --refresh)
    matches "A8: control: a Claude quota leaves the lane on" "$g" 'lane=true'
    has "A8: control: a Claude quota turns the fallback off" "$g" 'fallback=off'
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `timeout 600 bash plugins/dforge/tests/run-agy-task.test.sh; timeout 900 bash plugins/dforge/tests/antigravity-executor-lane.acceptance.test.sh A8`
Expected: FAIL on the fallback refusals, every `marked=` line, the Claude-quota cases (the lane closes instead), the reset windows and the real-gate reset chain; A8's Claude-quota control fails.

- [ ] **Step 3: Implement**

1. Preflight: directly after the `lane=true` check (still before `dr_canonical` and `dr_task_open`), add the C5 fallback check for a `--model` beginning `claude-`, failing closed on any line without ` fallback=on `, with C5's message through `die`.
2. Classification: after `quota_source` is set, compute the reset for `quota_source=agy` from `$cause` per C5. Match with bash `[[ … =~ … ]]` and `BASH_REMATCH` rather than `grep -o` or `sed -E` extensions, so GNU, uutils and Git Bash agree; a unit absent from the match counts 0, and a match with no unit is no match. Take the epoch with `date -u +%s` at this point (after `agy` exited) plus the seconds, and the ISO form with the Global Constraints' chain.
3. Replace `[ "$quota_source" != agy ] || executor_session_mark_off agy quota` with the family split of C5, keeping a variable for the `marked=` value (`none` for a stderr-only quota).
4. Replace the comment above it that begins "A quota is account-wide": Antigravity counts Claude and Gemini against separate limits, so a quota marks only the family that hit it, until the reset the error names or for the session when it names none; keep the existing sentences about trusting only `agy`'s own text and stdout.
5. `## Agy error`: after the `reason=%s` line, print `marked=<value>` when the reason is `quota`, then `until=<iso>` when it is not empty, before `timedOut=true` and the raw text (C5's order).

- [ ] **Step 4: Run the tests to verify they pass**

Run: `timeout 600 bash plugins/dforge/tests/run-agy-task.test.sh; timeout 900 bash plugins/dforge/tests/antigravity-executor-lane.acceptance.test.sh A8 A9`
Expected: each ends `0 failed`.

Then time the suite again as in Step 1. The Windows weight is a scheduling estimate: set `'run-agy-task.test.sh'` in `scripts/test-shards.mjs` to 390 × (new seconds ÷ baseline seconds), rounded up to a multiple of 10 (it stays 390 when the time did not grow), and add one line to the comment above `windowsSeconds` saying the weight was scaled by its Linux growth on 2026-11-03. If the result is above 480 (80% of the suite's 600 s limit), stop and report `BLOCKED` with both times: the suite then needs to run in parts. Run `timeout 120 node --test tests/test-shards.test.mjs`; expected: pass.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/scripts/run-agy-task.sh plugins/dforge/tests/run-agy-task.test.sh plugins/dforge/tests/antigravity-executor-lane.acceptance.test.sh scripts/test-shards.mjs
git commit -m "feat(dforge): mark an agy quota per model family"
```

### Task 4: Document the Gemini-first lane and release 4.11.0

**Files:**
- Modify: `plugins/dforge/reference/executor-lane.md` (the When a run fails table, the resume table, the Failure rows table, the `agy` Quota bullet)
- Modify: `plugins/dforge/README.md` (the `scripts/agy-gate` sentence, a new `## Migrating to 4.11` section)
- Modify: `plugins/dforge/.claude-plugin/plugin.json`, `plugins/dforge/.codex-plugin/plugin.json` (`"version"`)
- Test: `plugins/dforge/tests/lanes.test.sh`

**Interfaces:**
- Consumes: C1 and C2 (Task 1: the rows the migration section quotes, the admission the Failure rows table describes), C4 (Task 2: gate fields), C5 (Task 3: the refusal message and report lines) and C6 (ledger records).
- Produces: nothing another task consumes.

**Items:** 2, 3

**Implementer:** dforge:impl-sonnet-medium
**Evaluation:** files 2 - spec 1 - coupling 1 - risk 0 = 4

- [ ] **Step 1: Extend the test `plugins/dforge/tests/lanes.test.sh`**

Insert directly before the final `printf '\n%d passed, %d failed\n' …` line:

```bash
# --- the Gemini-first lane in the reference and the README ---
check "the capability row hands back when the agy successor is Claude and the fallback is off" \
  "$(grep -E '^\| Capability' "$EL" | grep -cF 'executor agy HANDBACK - fallback quota until <iso>')" "1"
check "the resume table hands back on the wrapper's fallback refusal" \
  "$(grep -E '^\|' "$EL" | grep -F 'the agy Claude fallback is off until' | grep -cF 'executor agy HANDBACK - fallback quota until <iso>')" "1"
check "no table row of the reference carries a bare <iso|session end> template" \
  "$(grep -E '^\|' "$EL" | grep -cF '<iso|session end>')" "0"
check "neither transient row retries a quota the wrapper marked" \
  "$(grep -E '^\| Transient' "$EL" | grep -cF 'is not retried')" "2"
check "an agy Executor line may name a successor rung" \
  "$(grep -cF 'outside its assignment and successor blocks' "$EL")" "1"
for need in 'separate limits' 'Individual quota reached' 'Resets in' 'fallback=off' 'fallback_resets_at=' 'marked=none' 'next gate call'; do
  check "Per-executor: agy's quota bullet says: $need" "$(grep -cF -- "$need" <<<"$agy_sec")" "1"
done
check "the agy section no longer says Antigravity publishes no reset time" \
  "$(grep -cF 'Antigravity publishes no reset time' <<<"$agy_sec")" "0"
check "the README no longer keeps the lane off for the session on every quota" \
  "$(tr '\n' ' ' < "$RD" | tr -s ' ' | grep -cF 'a quota failure keeps the lane off for the session')" "0"
check "the README says a Claude quota closes only the Claude fallback" \
  "$(tr '\n' ' ' < "$RD" | tr -s ' ' | grep -cF 'closes only the Claude fallback')" "1"
check "the README has a 4.11 migration section" "$(grep -cxF '## Migrating to 4.11' "$RD")" "1"
check "the 4.11 migration section says old Claude agy lines fail plan-lint" \
  "$(awk '/^## / { on = ($0 == "## Migrating to 4.11") } on' "$RD" | tr '\n' ' ' | grep -cF 'fails `plan-lint`')" "1"
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `timeout 300 bash plugins/dforge/tests/lanes.test.sh`
Expected: FAIL on every check added in Step 1 except `no table row of the reference carries a bare <iso|session end> template`, a guard that already passes and must keep passing.

- [ ] **Step 3: Implement**

1. `reference/executor-lane.md`, When a run fails table:
   - Transient row: keep "Retry once at the same rung" and add: an `agy` quota the wrapper marked (`marked=lane` or `marked=fallback` under `reason=quota`) is not retried: `HANDBACK` now. A lane quota records `executor agy HANDBACK - quota`, plus ` until <iso>` when the refreshed gate's `resets_at` is not `-`; a fallback quota records `executor agy HANDBACK - fallback quota until <iso>` (`until session end` when the gate's `fallback_resets_at` is `-`). A `marked=none` quota keeps the one retry. The row must contain the words "is not retried".
   - Capability row: keep the successor move and add: for `agy`, read `agy-gate --refresh` first; when the successor is a `claude-` rung and the line says `fallback=off`, `HANDBACK` now and record `executor agy HANDBACK - fallback quota until <iso>`, taking `<iso>` from `fallback_resets_at` (`until session end` when it is `-`). Never write `<iso|session end>` in a table cell: a bare `|` ends the cell. The hand-back counts toward the per-plan breaker.
2. Resume table (When the resume itself fails):
   - Transient row: add the same exception, with the words "is not retried": an `agy` quota the wrapper marked is `HANDBACK` now, recorded as in When a run fails.
   - New row directly above the `exit=2` row: Resume outcome "`exit=2` whose stderr says `the agy Claude fallback is off until …`"; Response "`HANDBACK` now, recorded on the fix-round line as `executor agy HANDBACK - fallback quota until <iso>` (`until session end` when the message says the end of the session). Re-issuing the resume would be refused again."
3. Failure rows table: the row beginning "The `**Executor:**` line names a model outside the executor's assignment block" says "(for `agy`, outside its assignment and successor blocks)" after "assignment block".
4. Per-executor: agy, the **Quota.** bullet: rewrite it to say, in order: Antigravity counts Claude and Gemini against separate limits, and its error names the reset, quoting `RESOURCE_EXHAUSTED (code 429): Individual quota reached. Please upgrade your subscription to increase your limits. Resets in 4h47m34s.`; the wrapper reads `Resets in <n>d<n>h<n>m<n>s` into a reset counted from when `agy` exits; a quota on a Gemini run marks the lane off until then and `agy-gate --refresh` keeps a cached `reason=quota` instead of re-probing it until the reset passes, printing it as `resets_at=`; a quota on a `claude-` run marks only the Claude fallback, which the gate prints as `fallback=off` with `fallback_resets_at=`, and the wrapper refuses `claude-` models at preflight while it holds; a quota with no `Resets in` keeps its mark for the session; only `agy`'s own `.error` text or non-JSON stdout marks anything, and a quota word found only in stderr gives `reason=quota` with `marked=none`; readers of the session file, such as `plan-lint`, see a mark lift only after the next gate call rewrites the file. Every phrase the Step 1 loop names must be present in the section, and the old sentence "Antigravity publishes no reset time" is gone from it. Leave the Codex section's Quota wording as it is.
5. `README.md`: in the paragraph about `scripts/agy-gate`, replace "a quota failure keeps the lane off for the session." with: a quota on a Gemini model closes the lane, and one on a Claude model closes only the Claude fallback, each until the reset time the error names, or for the session when it names none.
6. `README.md`: add a `## Migrating to 4.11` section directly above `## Migrating to 4.0`: dforge 4.11 runs the `agy` lane Gemini first (`gemini-3.8-flash medium` for totals 0-2, `gemini-4-argon low` for 3-4, `gemini-4-argon high` for 5-8), runs Claude through `agy` only as the retry after a Gemini run fails, and adds `fallback=` and `fallback_resets_at=` to the `agy-gate` line before `source=`. A plan whose `**Executor:** agy` lines name a `claude-` rung fails `plan-lint` until those lines are rewritten from the new block: `scripts/plan-revise` prints each task's rung, and dforge:revising-plans makes the edit.
7. Set `"version"` to `"4.11.0"` in both `plugin.json` files.

- [ ] **Step 4: Run the test to verify it passes**

Run: `timeout 300 bash plugins/dforge/tests/lanes.test.sh; jq -r .version plugins/dforge/.claude-plugin/plugin.json plugins/dforge/.codex-plugin/plugin.json; timeout 300 node scripts/validate-repository.mjs`
Expected: `0 failed`; `4.11.0` twice; validation passes.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/reference/executor-lane.md plugins/dforge/README.md plugins/dforge/tests/lanes.test.sh
git commit -m "docs(dforge): document the Gemini-first agy lane"
git add plugins/dforge/.claude-plugin/plugin.json plugins/dforge/.codex-plugin/plugin.json
git commit -m "chore(dforge): release 4.11.0"
```
