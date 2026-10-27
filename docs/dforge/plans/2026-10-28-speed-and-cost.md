# Speed and Cost Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: the skill the **Execution:** line names — dforge:subagent-driven-development for `subagent`, dforge:executing-plans for `inline`. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the spec's mechanical lane (skills under 20 KB, the full suite run by the controller beside the review, mechanical cannot-verify settlement, implementer clauses, an implementer stop gate, unattended-run docs and a prompt audit) and the pipeline replay eval that gates the measured lane.

**Architecture:** Text changes to dforge skills, references, agents and prompt templates; script changes in `plugins/dforge/scripts/task-step`, a new `plugins/dforge/scripts/impl-stop-gate` wired as a `SubagentStop` hook; and a new `pipeline` stage in `evals/tiers`. The measured lane (spec §6) starts after this plan merges, because its baseline is this plan's merge commit.

**Tech Stack:** Bash (POSIX tools only; runs on Linux, macOS and Windows Git Bash), jq, Node 22 for `.mjs` evals, the `claude` CLI 2.1.311 for plugin validation and live probes.

**Spec:** docs/dforge/specs/2026-10-27-speed-and-cost-design.md

**Execution:** subagent — `claude --model sonnet --effort high` — the plan runs parallel waves

**Parallelism:** waves — 1-6 | 7-9 | 10-12 | 13 | 14 | 15

**Integration check:** node scripts/test-all.mjs

**Worktree setup:** none

**Plan review:** 2026-10-28 — dforge:judge-opus — executability 16 / coherence 16 / coverage 15 / assumptions 16 (round 2)

## Global Constraints

- All paths are relative to the repository root `/root/repositories/darkraise-ai-plugins` (or the execution worktree's root) unless they start with `plugins/dforge/`, which is the plugin root.
- Every `plugins/dforge/skills/*/SKILL.md` stays at or under 20,000 bytes (`wc -c`) after any task's edits; from Task 10 on, `plugins/dforge/tests/skill-size.test.sh` enforces it.
- Codex hosts are unchanged: `plugins/dforge/reference/native-codex.md` and the executing-plans inline full-suite-before-commit rule are not edited; executing-plans `SKILL.md` changes only by Task 10's move of text into references, with no rule changed.
- Scripts are Bash with `set -uo pipefail` like their neighbours, use `grep`/`sed`/`awk`/`jq` only (no `rg`, no GNU-only flags: CI runs uutils on ubuntu-latest and Git Bash on Windows; `mkdir` is not atomic there, no `flock`, `MSYS_NO_PATHCONV` breaks `jq.exe` paths; strip `\r` from command output).
- Every test and CLI call is bounded (`timeout`), and a test leaves no process behind. A test needing a dead PID uses `sleep 0 & p=$!; wait $p`, never kills a fresh fork. Each test works under its own `mktemp -d` directory; no fixed path, port or shared state, so tasks of one wave never meet at run time.
- Unset `CLAUDE_CONFIG_DIR` in any test that reads a budget or settings.
- Test fixtures embedded in a test file prefix every plan line with `|` and strip it with `sed 's/^|//'`, so plan-lint's scans never read a quoted fixture as a task.
- Live `claude` runs (Tasks 1, 4, 6) call `/root/.local/bin/claude` (in Bash, `claude` is a shell function and exits 127), run under a temporary root with their own `HOME`, `XDG_*` and `CLAUDE_CONFIG_DIR` (into which only `.credentials.json` is copied from the session's `CLAUDE_CONFIG_DIR`, so the run is logged in but reads none of the owner's settings or plugins; Tasks 4 and 6 instead keep the session's `CLAUDE_CONFIG_DIR` with `--setting-sources project`, `CLAUDE_CODE_DISABLE_CLAUDE_MDS=1` and `--no-session-persistence`, because `/skill-doctor` reports on that directory's usage history and Task 4's probe was verified that way), never inside a real project checkout and never reading the owner's settings, and are never part of a test suite: CI has no API spend. Their output is recorded in a note under `docs/dforge/notes/`. Each live run is bounded with `timeout` and spends at most $10.
- Commits are `<type>(<scope>): <subject>` (type feat|fix|docs|style|refactor|test|chore|perf; subject at most 50 characters, imperative, no period), made as `Darkraise <quangtc94@gmail.com>`, with no `Co-Authored-By`, `Claude-Session` or any AI attribution. `git add` names explicit files. No version bump: `scripts/release.mjs` releases from commit types after CI.
- Validation for a task touching a skill, agent, hook or plugin manifest: `node scripts/validate-repository.mjs` and `timeout 120 /root/.local/bin/claude plugin validate plugins/dforge`.
- English only. Inclusive terms (allowlist/blocklist, primary/replica, main branch).
- Do not edit historical plans or specs under `docs/` or `docs/superpowers/`; preserve existing `DCC_*` variables and statusline storage paths.
- No blanket 1-hour subagent cache TTL and no `omitClaudeMd` on judges (measured as net losses, research note §1).

## Contracts

### Skill references

Produced by Tasks 2, 7 and 10.

- Moved material lives in `plugins/dforge/skills/<skill>/references/<topic>.md` (kebab-case topic), linked from the SKILL.md step that uses it by one line of the form `Read [<topic>.md](references/<topic>.md) before you <action>.`
- What stays in SKILL.md: frontmatter, the After compaction block when the skill has one, the entry rules, the step list and anything every step needs.
- A pin test that greps moved text is repointed at the reference file in the same task; no pin assertion is deleted.
- Task 10 also produces `plugins/dforge/tests/skill-view.sh`, a helper that prints a skill's `SKILL.md` followed by its `references/*.md`; Task 10's repointed pins grep that view.

### Size test

Produced by Task 10.

- `plugins/dforge/tests/skill-size.test.sh`: for each `plugins/dforge/skills/*/SKILL.md` over 20,000 bytes it prints `skill-size: <repository-relative path> <bytes> bytes (cap 20000)` and the test exits 1; with none over the cap it exits 0.

### Implementer report

Produced by Task 9; consumed by Task 15. Task 4 copies the grammar from this entry, not from Task 9's output.

- The report file gains a `## Verified` section: one bullet per command run, exactly `` - `<command>` — <pass|fail>: <n> passed, <m> failed `` (the separator is ` — `, U+2014 between spaces).
- The implementer's short reply carries `**Status:** DONE | DONE_WITH_CONCERNS | BLOCKED | NEEDS_CONTEXT` as today and ends with the line `Report: <absolute path of the report file>`.
- The implementer runs the focused tests that cover its change before each commit and no longer runs the full suite; the Run Control paragraph names `[PLUGIN_ROOT]/scripts/context-size`.
- Gate regexes (Task 4 uses these, extended regex): status `\*\*Status:\*\* (DONE|DONE_WITH_CONCERNS)([^A-Z_]|$)`; report line `^Report: (.+)$` (the last such line wins; the path is absolute, `/…` or `X:/…` or `X:\…`); verified bullet `` ^- `[^`]+` — (pass|fail)(: .*)?$ ``.

### Suite command and record

Produced by Task 12; consumed by Tasks 13, 14 and 15.

- `task-step start PLAN_FILE N [M ...] [--wave K] [--reset] [--suite '<command>']` stores the command as the string field `suite` in each `task-<N>-step.json`. The first `start --suite` on a plan whose ledger holds no `Ruling: suite command —` line appends `Task <N>: Ruling: suite command — <command> — none` to the ledger.
- The controller runs the suite as `bash <plugin-root>/scripts/suite-run -- bash -c '<command>'` from the checkout's top level, or from the `--cwd` directory for a wave task. Its record key is `printf '%q ' bash -c "<command>"` with the trailing space removed, which equals column 3 of `suites.tsv` for a run from the top level.
- `task-step verdict` reads `<state>/suites.tsv` of `--cwd` when given, else of the checkout (`<state>` from `bash <plugin-root>/scripts/dforge-path state` run there), and takes the last row whose column 1 is the review head and column 3 the record key; a `clean` or `dirty` row both count. It prints exactly one suite line among its digest:
  - `suite: pass (<clean|dirty>)` — exit code 0 row;
  - `suite: red (<k> failing, <b> baseline)` — a failing row, where `k` counts the failing lines that are not baseline and `b` those that are (`k` 0 means every failure is baseline and the task may complete); every non-baseline failing line becomes a finding with severity `Important`, file `suite`, line `0` and one-liner `suite: <failing line> fails at <head7>`, written to the fix file and printed like a reviewer finding, and `verdict` prints `fix: <fix file>`;
  - `suite: not run (<command>)` — no row: `verdict` writes no fix file and exits 8;
  - `suite: none recorded` — the step file has no `suite` field (a task started before this plan): behaviour as today.
- Exit 8 is new: "(verdict) the step file names a suite command with no record at the review head". Existing exits 0-7 keep their meaning; exit 5 and 6 are checked before 8.
- Task 12 adds these top-level functions to `plugins/dforge/scripts/task-step`, used by Tasks 13 and 14:
  - `suite_key COMMAND` prints `printf '%q ' bash -c "$COMMAND"` with the trailing space removed.
  - `suite_row STEP_FILE SHA [DIR]` reads `.suite` from STEP_FILE, takes the state directory from `dforge-path state` run in DIR (default the current directory), and prints the last tab-separated `suites.tsv` row whose column 1 is SHA and column 3 is `suite_key`; it prints nothing when there is no such row or no `.suite`.
  - `suite_failing_lines LOG` prints the Base runs pipeline's failing lines of LOG.
  - `suite_base_lines STEP_FILE N [DIR]` is the seam Task 13 replaces: Task 12 defines it as exactly the three lines `suite_base_lines() { # STEP_FILE N [DIR]`, `  return 0`, `}`, so it prints nothing. `do_verdict` calls it once, on a failing row only, and a failing line is baseline when `grep -xF` finds it in that output.
- Task 12 edits no file under `plugins/dforge/reference/` or `plugins/dforge/skills/`; the docs for exit 8 and the suite line belong to Task 15.
- Task 9 owns the pin changes for the implementer prompt: it flips the `task-step-text.test.sh` pin on the prompt's suite-run line to `lacks`, and repoints the two checks in `task-step.test.sh` and `task-loop-steps.acceptance.test.sh` that the dispatch file carries the expanded `scripts/suite-run -- ` at the expanded `scripts/context-size`.

### Base runs

Produced by Task 13; consumed by Task 14.

- Failing lines of a suite log: `grep -E '^[[:space:]]*(not ok|\(fail\)|FAIL)' <log> | cut -c1-200 | sed -E 's/^([[:space:]]*not ok) [0-9]+/\1/'`. A failing line is baseline when it appears exactly (`grep -xF`) in the base failing lines.
- `<workspace>/task-<N>-base-failures.txt` holds the base commit's failing lines for the task's recorded suite command, one per line, empty for a passing base. `verdict` reuses, in order: a `suites.tsv` row at the base sha with the record key in the checkout's state, then this file, then a fresh base run.
- `task-step` internal function `run_at_base BASE_SHA COMMAND OUT_LOG`: creates `git worktree add --detach <mktemp dir> BASE_SHA`, runs the plan header's `**Worktree setup:**` there when it is present and not `none`, runs `bash <plugin-root>/scripts/suite-run --timeout 600 -- bash -c "$COMMAND"` there, copies the run's log to `OUT_LOG`, removes the worktree with `git worktree remove --force`, and prints the suite's exit code.
- Base logs are kept as `<workspace>/task-<N>-base.log` (the suite) and `<workspace>/task-<N>-baseline-<k>.log` (the k-th baseline item of Task 14).
- `task-step rereview PLAN_FILE N --covered` skips the re-review only when the fix head's suite row (record key, fix head) passes or fails with baseline lines only; otherwise it prints `re-review: not skipped (suite <red|not run>)` and writes the re-review prompt as without `--covered`.

### Cannot-verify settlement

Produced by Task 14.

- The task-reviewer prompt's `## Cannot verify` items take, for mechanical questions, exactly `- cannot-verify: exists <path|symbol> at <base|head> — <why>` or `- cannot-verify: baseline <command> — <why>`.
- `exists`: when `git cat-file -e <sha>:<target>` succeeds the evidence is `path present`; else when the target contains `/` it is `path absent`; else `git grep -nwF -e <target> <sha>` and the evidence is the first hit as `<file>:<line>`, or `absent`.
- `baseline`: `run_at_base` on the task's base with the named command; the evidence is `exit <code>, log <workspace path of task-<N>-baseline-<k>.log>`.
- A settled item appends `Task <N>: Ruling: cannot-verify — settled by task-step check <exists|baseline> — <evidence>` to the ledger and is left out of the cannot-verify lines `verdict` prints for the ruling seat; a free-text item is printed as today.

### Stop gate

Produced by Task 4.

- `plugins/dforge/hooks/hooks.json` gains `"SubagentStop": [{ "matcher": "(dforge:)?impl-.*", "hooks": [{ "type": "command", "command": "bash \"${CLAUDE_PLUGIN_ROOT}/scripts/impl-stop-gate\"", "shell": "bash", "async": false, "timeout": 30 }] }]`, and its `description` mentions the gate.
- `plugins/dforge/scripts/impl-stop-gate` reads the hook JSON on stdin (`agent_type`, `agent_id`, `last_assistant_message`, `cwd`). It passes (exit 0, no output) unless `agent_type` matches `(^|:)impl-` and the message matches the status regex of Implementer report. When it acts it blocks with exit 2 and one stderr line `impl-stop-gate: <what is missing>` when the message has no `Report:` line, the file does not exist, it lacks `## Discovered issues (not fixed)` or `## Assumptions made`, or `## Verified` is missing or holds no bullet matching the verified-bullet regex.
- `<state>` is `bash "$CLAUDE_PLUGIN_ROOT/scripts/dforge-path" state` run from the input's `cwd`. Counter file `<state>/impl-stop-gate/<agent_id>`: line 1 the block count, line 2 the sha256 of the last blocked message, line 3 `passed` once the gate has let a stop through; an identical message does not raise the count. After two blocks the next distinct acting stop passes and appends `<epoch> <agent_id> <agent_type> pass-through after 2 blocks — <last reason>` to `<state>/impl-stop-gate.log`.
- The observed `SubagentStop` input from a real run is committed as `plugins/dforge/tests/fixtures/subagent-stop-input.json`, with long fields shortened.

### Pipeline eval

Produced by Tasks 1, 8 and 11.

- Task 1 writes `docs/dforge/notes/2026-10-28-pipeline-smoke.md` ending with `**Verdict:** HEADLESS` or `**Verdict:** TMUX`. On `TMUX` the task reports `DONE_WITH_CONCERNS` with the verdict as its first line, and the controller sends a `blocked-plan` item to the ruling seat before dispatching Task 8.
- `evals/tiers/arms.json` gains `"pipeline": { "baseline": "<ref>", "candidate": "<ref>" }`. An arm's tree is `snapshot(<ref>, <eval root>/arms/<ref7>)` from `evals/tiers/lib/snapshot.mjs`; its plugin directory is `<eval root>/arms/<ref7>/plugins/dforge`. No git worktree is created.
- Manifest `evals/tiers/cases/pipeline.tsv`, tab-separated with a header row: `case	plan	task	base	fixRounds`, where `plan` is a repository-relative plan path, `task` the task number, `base` the full sha the task started from and `fixRounds` the rounds it needed. 12 cases.
- `evals/tiers/lib/pipeline.mjs` exports `runPipelineCase({ c, arm, ref, run, root })` → `{ outcome, costUsd, seconds, dispatches, fixRounds, detail }`, `outcome` one of `PASS`, `FAIL`, `ERROR`.
- The `arm` column of `results/pipeline.tsv` is `<label>@<ref7>`, for example `baseline@e6f88a6`; the report groups rows by that string.
- Task 11 exports the existing case builder `candidate` from `evals/tiers/lib/cases.mjs` for the manifest builder.
- `evals/tiers/lib/results.mjs` exports `PIPELINE_RESULTS` (`results/pipeline.tsv`) and `PIPELINE_COLUMNS = ['rep', 'case', 'arm', 'run', 'outcome', 'costUsd', 'seconds', 'dispatches', 'fixRounds', 'detail']`.
- `node evals/tiers/run-grid.mjs --stage pipeline [--rep N]` runs every (case, arm, run 1-2) cell with no row yet; `results.tsv` and the other stages are untouched, and the start-commit refusal applies to every stage but `pipeline`. A baseline arm's rows are reused by any comparison against the same baseline ref.
- `node evals/tiers/report.mjs --pipeline [--rep N]` prints per arm `pass^2 <k>/<n>`, `cost $<total>` and `median <s>s`.

### Docs

Produced by Tasks 5 and 6.

- `plugins/dforge/README.md` gains a `## Unattended runs` section.
- `docs/dforge/notes/2026-10-27-prompt-audit.md` records the `/doctor prompt-audit` and `/skill-doctor` output; each proposed change becomes a row via `bash plugins/dforge/scripts/register add docs/dforge/registers/2026-10-27-speed-and-cost.md "<proposal>"`.

## Assumptions (evidence)

- `task-step` already uses exit 7 for "the fix loop is at its two-round cap" (`plugins/dforge/scripts/task-step:22-23`, read 2026-10-28), so "suite not run" takes exit 8 instead of the spec's exit 7; the behaviour is otherwise as the spec states.
- `suite-run` records `<HEAD> <clean|dirty> <command %q> <exit> <log> <epoch>` per row and prefixes `(<subdir>)` when run below the top level (`plugins/dforge/scripts/suite-run:6-17`, `:62-65`); it writes no failing lines to the row, so they come from the log.
- Releases bump versions from commit types (`scripts/release.mjs`, release commits such as `3f9713a3`), and `plugins/dforge` has no changelog file (`ls plugins/dforge`, 2026-10-28): the spec's "plugin version files and changelog" owned by part G need no task.
- The headless whole loop is unverified — Task 1 verifies the mechanism with the current plugin (a `claude -p` session that runs a background Bash command and an Agent dispatch together and continues after both notifications, and one replayed task to `Task N: complete`). The spec's overlap criterion for the new loop can run only after Task 15; the final review's acceptance QA runs one case on both arms with the candidate at this branch's head for A12.
- `SubagentStop` input's `agent_type` for a plugin agent (with or without the `dforge:` prefix) is unverified — Task 4 verifies it with one live run before the gate is written. Claude Code here is 2.1.311 (`/root/.local/bin/claude --version`, 2026-10-28), the version the gate needs.
- Whether `/doctor prompt-audit` and `/skill-doctor` run headless is unverified — Task 6 verifies it; when they do not, the owner runs one session and the task records its output (spec A17, confirmed).
- `task-step` keeps the task's base in the step file's `base` field and already prints cannot-verify items in `verdict` (`plugins/dforge/scripts/task-step`, `.base` and `cannot-verify: %s` lines, read 2026-10-28).
- The eval tests run only off Windows (`scripts/test-all.mjs:63`), so Tasks 8 and 11 need no Git Bash path handling.
- Task 10 repoints its pins at the `skill-view.sh` view of `SKILL.md` plus references instead of each reference file: one change instead of about 37 per-assertion edits, at the cost that a pin still passes if text moves back into `SKILL.md`. Tasks 2 and 7 repoint per assertion.
- A pipeline case's `fixRounds` is approximated from git history (commits touching the task's files before the next task's commit; a plan's last task counts 0), because ledgers survive only on the machine that ran the plan.
- A gate block can be followed by a final message without a `**Status:**` line, which the gate then passes; Task 4's block line asks for the full reply again (observed in Task 4's drafting probe, 2026-10-28).
- Spec acceptance A14 (merge rule) and A15 (first-batch spend) belong to the measured lane and are deferred with register rows 3, 4, 6, 10 and 15: the rule could be built on fixture numbers now, but it is only ever applied against `<M>`, which exists only after this plan merges, so by choice the follow-up plan implements and tests it beside its first use. Task 11's report prints the per-arm numbers the rule reads.
- Only task-loop implementers use the `**Status:** DONE` contract: `grep -rn 'implementer-prompt\|DONE_WITH_CONCERNS\|\*\*Status' plugins/dforge/reference/final-review.md plugins/dforge/reference/acceptance-qa.md` prints nothing (2026-10-28), so the final-review fix wave and acceptance QA `impl-*` dispatches pass the gate untouched. This static read stands in for the spec's live capture of such a reply.
- Task 14 settles structured cannot-verify items for single-task verdicts only; a group verdict sends them to the ruling seat as today, because a group review's items are not tied to one member's base. Repeated verdicts re-run `baseline` items; a task rarely gets more than two verdicts.
- Wave 1 holds six independent tasks (plan-lint warns it runs in parts of three); they share no file and depend on nothing, so splitting them into waves would only add ordering nobody needs.
- Register rows 3, 4, 6, 10 and 15 (measured lane items 1-3 and the stagger) are deferred to a follow-up plan: their baseline is this plan's merge commit `<M>`, which exists only after this plan merges. Rows 8, 9, 12 and 17 were deferred at the spec review.

## Task index

1. Probe the headless whole-loop replay
2. Split subagent-driven-development SKILL.md
3. Add the implementer agent clauses
4. Gate implementer stops on the report
5. Document unattended runs in the README
6. Record the prompt audit
7. Split brainstorming and writing-plans SKILL.md
8. Add the pipeline replay stage
9. Fix the implementer report grammar
10. Split the remaining skills and add the size test
11. Build the pipeline manifest and report
12. Read the suite record in task-step verdict
13. Compare suite failures against the base
14. Settle mechanical cannot-verify items
15. Run the suite beside the review in the controller

---

### Task 1: Probe the headless whole-loop replay

**Files:**
- Create: `docs/dforge/notes/2026-10-28-pipeline-smoke.md`

**Interfaces:**
- Consumes: Global Constraints (live `claude` runs: `/root/.local/bin/claude`, a temporary root with its own `HOME`, `XDG_*` and `CLAUDE_CONFIG_DIR`, bounded with `timeout`, at most $10 a run, recorded in a note); the `plugins/dforge` directory of this checkout, read only.
- Produces: the Contracts entry "Pipeline eval": `docs/dforge/notes/2026-10-28-pipeline-smoke.md`, whose last line is `**Verdict:** HEADLESS` or `**Verdict:** TMUX`.

**Items:** 11

**Depends on:** none

**Implementer:** dforge:impl-sonnet-low
**Evaluation:** files 0 - spec 1 - coupling 1 - risk 0 = 2

The design's riskiest assumption is that `claude -p` can run the controller's whole task loop: the controller ends its turn after dispatching work and each completion notification starts the next turn, and under `-p` the process may exit at the first wait. Two probes decide it, both in a temporary root outside any project checkout, nothing of which is committed but the note.

- P1 starts a background Bash command and a subagent in one message, ends the turn, and must print a sentinel line only after both completion notifications arrive.
- P2 runs one task of a one-task plan through the current plugin's `dforge:subagent-driven-development` in an isolated clone, up to its `Task 1: complete` ledger line, then lays the finished test over the clone and runs it.

A fresh `CLAUDE_CONFIG_DIR` holds no login: with none, `claude -p` answers "Not logged in" (checked 2026-10-28). The probe script therefore copies one file, `.credentials.json`, from the session's own `CLAUDE_CONFIG_DIR` into the run's temporary config directory (mode 600), so the run is logged in but reads none of the owner's settings or plugins. It passes no other file and no credential variable.

- [ ] **Step 1: Create the probe root and the probe script**

Run `ROOT=$(mktemp -d); echo "$ROOT"` and keep the printed path: every later command names it as `ROOT=<that path>`, because each command starts in a fresh shell. Write this file to `$ROOT/smoke.sh`:

````bash
#!/usr/bin/env bash
# Headless whole-loop probe.
# Usage: ROOT=<temp dir> REPO=<checkout> bash smoke.sh check-auth | p1 | p2 | verdict | note | clean
set -uo pipefail
: "${ROOT:?ROOT is the temporary root of the probe}" "${REPO:?REPO is the checkout that holds plugins/dforge}"
CLAUDE=${CLAUDE:-/root/.local/bin/claude}
PLUGIN="$REPO/plugins/dforge"
NOTE="$REPO/docs/dforge/notes/2026-10-28-pipeline-smoke.md"
CREDENTIALS="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/.credentials.json"
SENTINEL='PROBE-COMPLETE suite=SUITE-DONE judge=JUDGE-DONE'

# isolated <cwd> <prompt-file> <out-base> <budget-usd> <seconds> [claude args...]
# One headless run with its own HOME, XDG_* and CLAUDE_CONFIG_DIR. The only file
# that crosses over from the session's config directory is .credentials.json,
# so the run is logged in but reads none of the owner's settings or plugins.
isolated() {
  local cwd=$1 prompt=$2 out=$3 budget=$4 seconds=$5 code
  shift 5
  mkdir -p "$ROOT/home" "$ROOT/config" "$ROOT/xdg/config" "$ROOT/xdg/data" "$ROOT/xdg/cache" "$ROOT/xdg/state"
  cp "$CREDENTIALS" "$ROOT/config/.credentials.json" && chmod 600 "$ROOT/config/.credentials.json"
  (
    cd "$cwd" || exit 1
    env -i HOME="$ROOT/home" PATH="$PATH" CLAUDE_CONFIG_DIR="$ROOT/config" \
      XDG_CONFIG_HOME="$ROOT/xdg/config" XDG_DATA_HOME="$ROOT/xdg/data" \
      XDG_CACHE_HOME="$ROOT/xdg/cache" XDG_STATE_HOME="$ROOT/xdg/state" \
      IS_SANDBOX=1 CLAUDE_CODE_DISABLE_CLAUDE_MDS=1 \
      timeout --kill-after=10 "$seconds" "$CLAUDE" -p --model sonnet --effort high \
        --permission-mode bypassPermissions --setting-sources project,local \
        --output-format stream-json --verbose --max-budget-usd "$budget" \
        --no-session-persistence "$@" < "$prompt" > "$out.jsonl" 2> "$out.err"
  )
  code=$?
  echo "$code" > "$out.exit"
}

# result_field <stream> <jq expression over the result event>
result_field() { jq -r "select(.type==\"result\") | $2" "$1" 2>/dev/null | tail -n 1; }

# run_error <stream> - prints the error text when the run ended in an error or never produced a result
run_error() {
  local is_error text
  is_error=$(result_field "$1" '.is_error')
  text=$(result_field "$1" '.result')
  if [ -z "$is_error" ]; then echo "no result event: $(head -c 300 "${1%.jsonl}.err" 2>/dev/null)"
  elif [ "$is_error" = true ]; then echo "$text"; fi
}

make_fixture() { # make_fixture <dir> <hidden-dir>: a one-task project on branch replay-smoke; the finished test goes to <hidden-dir>
  local d=$1 h=$2
  mkdir -p "$d/docs" "$d/tests" "$h"
  cat > "$h/greet.test.sh" <<'TEST'
#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GREET="$HERE/../bin/greet"
fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then echo "ok   - $1"; else echo "FAIL - $1 (want [$3] got [$2])"; fail=1; fi
}
check "greets by name" "$(bash "$GREET" Ada)" "Hello, Ada!"
check "defaults to world" "$(bash "$GREET")" "Hello, world!"
exit $fail
TEST
  sed 's/^|//' > "$d/docs/spec.md" <<'SPEC'
|# Greeter design
|
|**Execution strategy:** sequential
|
|**Depth:** light — interface
|
|## Decisions
|
|- **Finish.** Keep the branch as it is.
|
|Finish: keep
|
|## Design
|
|`bin/greet [NAME]` prints `Hello, NAME!`, and `Hello, world!` when it gets no name.
|
|## Acceptance
|
|A1. [test, high] `bin/greet Ada` prints `Hello, Ada!` and `bin/greet` prints `Hello, world!`.
SPEC
  {
    sed 's/^|//' <<'HEADER'
|# Greeter Implementation Plan
|
|> **For agentic workers:** REQUIRED SUB-SKILL: the skill the **Execution:** line names — dforge:subagent-driven-development for `subagent`, dforge:executing-plans for `inline`. Steps use checkbox (`- [ ]`) syntax for tracking.
|
|**Goal:** Add a greeting command.
|
|**Architecture:** One Bash script and its test.
|
|**Tech Stack:** Bash.
|
|**Spec:** docs/spec.md
|
|**Execution:** subagent — `claude --model sonnet --effort high` — a one-task smoke replay
|
|**Integration check:** bash tests/greet.test.sh
|
|**Worktree setup:** none
|
|## Global Constraints
|
|- Bash only; no dependencies.
|- Commits are `<type>(<scope>): <subject>`.
|
|## Contracts
|
|None.
|
|## Assumptions (evidence)
|
|None.
|
|## Task index
|
|1. Add the greet command
|
|---
|
|### Task 1: Add the greet command
|
|**Files:**
|- Create: `bin/greet`
|- Test: `tests/greet.test.sh`
|
|**Interfaces:**
|- Consumes: nothing
|- Produces: `bin/greet [NAME]`, printing `Hello, NAME!` or `Hello, world!`
|
|**Implementer:** dforge:impl-sonnet-low
|**Evaluation:** files 0 - spec 0 - coupling 0 - risk 0 = 0
|
|- [ ] **Step 1: Write the failing test**
|
|```bash
HEADER
    cat "$h/greet.test.sh"
    sed 's/^|//' <<'TAIL'
|```
|
|- [ ] **Step 2: Run it to see it fail**
|
|Run: `bash tests/greet.test.sh`
|Expected: FAIL, `bin/greet` does not exist.
|
|- [ ] **Step 3: Write the implementation**
|
|```bash
|#!/usr/bin/env bash
|printf 'Hello, %s!\n' "${1:-world}"
|```
|
|- [ ] **Step 4: Run the test**
|
|Run: `bash tests/greet.test.sh`
|Expected: PASS.
|
|- [ ] **Step 5: Commit**
|
|```bash
|git add bin/greet tests/greet.test.sh
|git commit -m "feat(greet): add the greet command"
|```
TAIL
  } > "$d/docs/plan.md"
  (
    cd "$d" || exit 1
    git init -q -b replay-smoke
    git config user.name Darkraise
    git config user.email quangtc94@gmail.com
    git add docs
    git commit -q -m "docs: add the greeter plan"
  )
}

ledger_file() { find "$ROOT/clone" -name progress.md -path '*/sdd/*' 2>/dev/null | head -n 1; }

cmd_check_auth() {
  if [ ! -s "$CREDENTIALS" ]; then
    echo "NEEDS_CONTEXT: $CREDENTIALS does not exist, so the session has no login to copy into the run's own config directory."
    return 4
  fi
  echo "credentials file present"
}

cmd_p1() {
  mkdir -p "$ROOT/p1-work"
  cat > "$ROOT/p1-prompt.txt" <<PROMPT
Follow these steps exactly and ask nothing.

1. In ONE message make both of these tool calls together:
   a. a Bash call with run_in_background set to true, running exactly: sleep 25; echo SUITE-DONE # $ROOT
   b. an Agent call with subagent_type general-purpose whose prompt is: Run this Bash command and reply with its output only: sleep 15; echo JUDGE-DONE # $ROOT
2. Then end your turn with no further tool call. Never wait with sleep, Monitor or a polling loop.
3. Each completion arrives as a notification that starts a new turn. After both have arrived, print exactly one line, PROBE-COMPLETE suite=<the output of a> judge=<the output of b>, and stop.
PROMPT
  isolated "$ROOT/p1-work" "$ROOT/p1-prompt.txt" "$ROOT/p1" 1 420
  p1_report
}

# p1_overlap - the id of the assistant message that started a background Bash call and an Agent call together
p1_overlap() {
  jq -r 'select(.type=="assistant") | .message as $m
    | [$m.content[]? | select(.type=="tool_use")
       | if .name=="Bash" and (.input.run_in_background==true) then "bg" elif (.name=="Agent" or .name=="Task") then "agent" else empty end]
    | select(index("bg") and index("agent")) | $m.id' "$ROOT/p1.jsonl" 2>/dev/null | head -n 1
}

p1_timeline() {
  jq -r 'select(.type=="assistant") | .message | [.id, .stop_reason, ([.content[]? | select(.type=="tool_use") | .name] | join(","))] | @tsv' "$ROOT/p1.jsonl" 2>/dev/null
}

# p1_polling - the tool the session used to wait by polling, if any
p1_polling() {
  jq -r 'select(.type=="assistant" and .parent_tool_use_id == null) | .message.content[]?
    | select(.type=="tool_use")
    | select(.name=="Monitor" or (.name=="Bash" and (.input.run_in_background != true) and ((.input.command // "") | test("sleep"))))
    | .name' "$ROOT/p1.jsonl" 2>/dev/null | head -n 1
}

# p1_status - pass | wait-failure | error: <text>
p1_status() {
  local err final polled
  err=$(run_error "$ROOT/p1.jsonl")
  if [ -n "$err" ]; then echo "error: $err"; return; fi
  polled=$(p1_polling)
  if [ -n "$polled" ]; then echo "error: the session waited by polling with $polled instead of ending its turn"; return; fi
  final=$(result_field "$ROOT/p1.jsonl" '.result')
  if [ -n "$(p1_overlap)" ] && printf '%s' "$final" | grep -qF "$SENTINEL"; then echo pass; else echo wait-failure; fi
}

p1_report() {
  echo "background Bash and Agent in one message: $(p1_overlap)"
  echo "final result: $(result_field "$ROOT/p1.jsonl" '.result')"
  echo "cost/turns/ms: $(result_field "$ROOT/p1.jsonl" '[.total_cost_usd, .num_turns, .duration_ms] | @tsv')"
  echo "P1: $(p1_status)"
}

cmd_p2() {
  rm -rf "$ROOT/clone" "$ROOT/hidden"
  make_fixture "$ROOT/clone" "$ROOT/hidden"
  cat > "$ROOT/p2-prompt.txt" <<'PROMPT'
Invoke the Skill tool with dforge:subagent-driven-development and execute Task 1 of docs/plan.md.

This directory is already the isolated workspace, a git checkout on branch replay-smoke: create no worktree. Ask your human partner nothing. Log "Ruling: pre-flight — skipped (replay) — none" and go on without the pre-flight ruling. Run the task loop for Task 1 through its "Task 1: complete" ledger line, then stop: no final review, no finishing, no handoff. After the complete line, print the single line REPLAY-DONE.
PROMPT
  isolated "$ROOT/clone" "$ROOT/p2-prompt.txt" "$ROOT/p2" 8 1500 --plugin-dir "$PLUGIN"
  p2_report
}

# p2_status - pass | wait-failure | error: <text> | inconclusive: <why>
p2_status() {
  local err ledger complete last tests
  err=$(run_error "$ROOT/p2.jsonl")
  if [ -n "$err" ]; then echo "error: $err"; return; fi
  ledger=$(ledger_file)
  if [ -z "$ledger" ]; then echo "inconclusive: no ledger was written"; return; fi
  complete=$(grep -c '^Task 1: complete' "$ledger")
  last=$(grep '^Task 1:' "$ledger" | tail -n 1)
  if [ "$complete" -ge 1 ]; then
    cp "$ROOT/hidden/greet.test.sh" "$ROOT/clone/tests/greet.test.sh"
    if (cd "$ROOT/clone" && timeout 60 bash tests/greet.test.sh > "$ROOT/p2-hidden.txt" 2>&1); then echo pass; else echo "inconclusive: the complete line is there but the hidden test fails"; fi
    return
  fi
  case "$last" in
    "Task 1: implementer "*) echo wait-failure ;;
    *) echo "inconclusive: the last Task 1 ledger line is: ${last:-none}" ;;
  esac
}

p2_report() {
  local ledger
  ledger=$(ledger_file)
  echo "ledger: ${ledger:-none}"
  [ -n "$ledger" ] && grep '^Task 1:' "$ledger" | cut -c1-200
  echo "cost/turns/ms: $(result_field "$ROOT/p2.jsonl" '[.total_cost_usd, .num_turns, .duration_ms] | @tsv')"
  echo "P2: $(p2_status)"
  [ -f "$ROOT/p2-hidden.txt" ] && cat "$ROOT/p2-hidden.txt"
}

# verdict - HEADLESS | TMUX | INCONCLUSIVE: <why>
cmd_verdict() {
  local s1 s2
  s1=$(p1_status)
  case "$s1" in
    wait-failure) echo "TMUX"; return ;;
    pass) ;;
    *) echo "INCONCLUSIVE: P1 $s1"; return ;;
  esac
  s2=$(p2_status)
  case "$s2" in
    pass) echo "HEADLESS" ;;
    wait-failure) echo "TMUX" ;;
    *) echo "INCONCLUSIVE: P2 $s2" ;;
  esac
}

cmd_note() {
  local verdict ledger
  verdict=$(cmd_verdict)
  case "$verdict" in
    HEADLESS | TMUX) ;;
    *) echo "$verdict"; return 3 ;;
  esac
  ledger=$(ledger_file)
  mkdir -p "$(dirname "$NOTE")"
  {
    printf '# Pipeline smoke: can `claude -p` drive the whole task loop?\n\n'
    printf 'Run on 2026-10-28 with Claude Code %s, plugin commit %s, in a temporary root with its own HOME, XDG and CLAUDE_CONFIG_DIR (only .credentials.json copied in from the session). Spec: docs/dforge/specs/2026-10-27-speed-and-cost-design.md, Riskiest assumption.\n\n' \
      "$("$CLAUDE" --version 2>/dev/null | head -n 1)" "$(git -C "$REPO" rev-parse --short HEAD)"
    printf 'Every run used `claude -p --model sonnet --effort high --permission-mode bypassPermissions --setting-sources project,local --output-format stream-json --verbose --no-session-persistence` with `IS_SANDBOX=1`, a budget cap of $1 for P1 and $8 for P2, and a timeout of 420 s and 1500 s.\n\n'
    printf '## P1: a background Bash command and a subagent, then continue after both notifications\n\n'
    printf 'A `claude -p` session started `sleep 25` in the background and a general-purpose Agent running `sleep 15` in one message, ended its turn, and was asked to print one line after both completion notifications.\n\n'
    printf 'Assistant messages (id, stop_reason, tools):\n\n```\n%s\n```\n\n' "$(p1_timeline)"
    printf -- '- Both calls in one message: %s\n- Final result: `%s`\n- Cost, turns, milliseconds: %s\n- Outcome: %s\n\n' \
      "$(p1_overlap)" "$(result_field "$ROOT/p1.jsonl" '.result')" "$(result_field "$ROOT/p1.jsonl" '[.total_cost_usd, .num_turns, .duration_ms] | @tsv')" "$(p1_status)"
    printf '## P2: one task through the current plugin'"'"'s task loop\n\n'
    if [ -f "$ROOT/p2.jsonl" ]; then
      printf 'A one-task plan (docs/plan.md, Task 1 on `dforge:impl-sonnet-low`) in an isolated clone; `claude -p --plugin-dir %s` was told to run dforge:subagent-driven-development through the `Task 1: complete` line. The finished test was overlaid after the run and executed.\n\n' "plugins/dforge"
      printf 'Task 1 ledger lines:\n\n```\n%s\n```\n\n' "$( [ -n "$ledger" ] && grep '^Task 1:' "$ledger" | cut -c1-200 )"
      printf 'Hidden test:\n\n```\n%s\n```\n\n' "$(cat "$ROOT/p2-hidden.txt" 2>/dev/null)"
      printf -- '- Cost, turns, milliseconds: %s\n- Outcome: %s\n\n' "$(result_field "$ROOT/p2.jsonl" '[.total_cost_usd, .num_turns, .duration_ms] | @tsv')" "$(p2_status)"
    else
      printf 'Not run: P1 had already shown that the process ends at the first wait.\n\n'
    fi
    printf '## Conclusion\n\n'
    if [ "$verdict" = HEADLESS ]; then
      printf 'Under `claude -p` a turn that ends on pending background work resumes on each completion notification, and the controller finished a task loop without a human. The pipeline stage can drive `claude -p`; design section 5 stands.\n\n'
    else
      printf 'Under `claude -p` the process ended at the first wait, so the controller loop cannot finish headless. The pipeline stage must drive an interactive session in tmux, and design section 5 is amended before Task 8 starts.\n\n'
    fi
    printf '**Verdict:** %s\n' "$verdict"
  } > "$NOTE"
  echo "$verdict"
}

cmd_clean() {
  pgrep -af "echo (SUITE|JUDGE)-DONE # $ROOT" || echo "no probe process left"
  pkill -f "echo (SUITE|JUDGE)-DONE # $ROOT" 2>/dev/null || true
  rm -rf "$ROOT"
  echo "cleaned $ROOT"
}

case "${1:-}" in
  check-auth) cmd_check_auth ;;
  p1) cmd_p1 ;;
  p2) cmd_p2 ;;
  verdict) cmd_verdict ;;
  note) cmd_note ;;
  clean) cmd_clean ;;
  *) echo "usage: smoke.sh check-auth|p1|p2|verdict|note|clean" >&2; exit 2 ;;
esac
````

- [ ] **Step 2: Check that the session has credentials to copy**

Run: `ROOT=<root> REPO="$(git rev-parse --show-toplevel)" bash "$ROOT/smoke.sh" check-auth`
Expected: `credentials file present`. On exit 4 it prints a `NEEDS_CONTEXT:` line naming the missing file: run the `clean` command of Step 6, then stop and report NEEDS_CONTEXT with that line.

- [ ] **Step 3: Run P1**

Run, with the Bash tool's timeout at its 600000 ms maximum: `ROOT=<root> REPO="$(git rev-parse --show-toplevel)" bash "$ROOT/smoke.sh" p1`
Expected: it ends with `P1: pass` and a `final result:` line of `PROBE-COMPLETE suite=SUITE-DONE judge=JUDGE-DONE`; the run costs under $1.
- `P1: wait-failure` means the process ended before both notifications: skip Step 4 and go to Step 5.
- `P1: error: …` is not a verdict. A line naming a login means the copied credentials were refused: report NEEDS_CONTEXT as in Step 2. Any other error: run Step 3 once more, and report BLOCKED with the printed error if it repeats.

- [ ] **Step 4: Run P2**

Start it as a background command (it can take up to 25 minutes and costs at most $8) and end the turn; its completion notification starts the next one. Never wait with `sleep`, `Monitor` or a polling loop.
Run: `ROOT=<root> REPO="$(git rev-parse --show-toplevel)" bash "$ROOT/smoke.sh" p2`
Expected: it ends with `P2: pass`, the ledger lines of Task 1 including `Task 1: complete`, and the hidden test's `ok` lines.
- `P2: wait-failure` means the ledger stopped at the `implementer … (assigned` line: the process ended at the first wait.
- `P2: inconclusive: …` or `P2: error: …` is not a verdict: read `$ROOT/p2.jsonl` and `$ROOT/p2.err` for the cause, run Step 4 once more, and report BLOCKED with the printed reason if it repeats.

- [ ] **Step 5: Write the note**

Run: `ROOT=<root> REPO="$(git rev-parse --show-toplevel)" bash "$ROOT/smoke.sh" note`
Expected: `HEADLESS` or `TMUX`, and `docs/dforge/notes/2026-10-28-pipeline-smoke.md` written. On `INCONCLUSIVE: …` it writes nothing and exits 3: go back to the step the reason names, and never write the note by hand.

- [ ] **Step 6: Clean up**

Run: `ROOT=<root> REPO="$(git rev-parse --show-toplevel)" bash "$ROOT/smoke.sh" clean`
Expected: `no probe process left` and `cleaned <root>`. A listed process is one this probe started (its command line holds the root): the command kills it.

- [ ] **Step 7: Commit**

```bash
git add docs/dforge/notes/2026-10-28-pipeline-smoke.md
git commit -m "docs(dforge): record the pipeline smoke verdict"
```

**Check:** `tail -n 1 docs/dforge/notes/2026-10-28-pipeline-smoke.md` prints `**Verdict:** HEADLESS` or `**Verdict:** TMUX`, and `git status --short` is empty. When the verdict is `TMUX`, report `DONE_WITH_CONCERNS` and make `**Verdict:** TMUX` the first line of the report: the controller then sends a `blocked-plan` item to the ruling seat before it dispatches Task 8.

### Task 2: Split subagent-driven-development SKILL.md

**Files:**
- Modify: `plugins/dforge/skills/subagent-driven-development/SKILL.md` (49,422 bytes now, 17,935 after)
- Create: `plugins/dforge/skills/subagent-driven-development/references/batching.md`, `budget.md`, `example-workflow.md`, `finish-rulings.md`, `ledger.md`, `process-graph.md`, `rationale.md`, `rationalizations.md`, `ruling-seat.md`, `setup.md`
- Create: `plugins/dforge/tests/fixtures/sdd-text.sh`
- Test: `plugins/dforge/tests/sdd-references.test.sh` (new)
- Modify (pins repointed at the references): `plugins/dforge/tests/auto-run-skills.test.sh`, `faster-plans.acceptance.test.sh`, `final-phase.test.sh`, `inline-mode.test.sh`, `process-roles.test.sh`, `project-status.test.sh`, `review-depth-qa.acceptance.test.sh`, `review-depth.acceptance.test.sh`, `review-route.test.sh`, `task-step-text.test.sh`, `waiting-text.test.sh`, `working-directory.test.sh`

**Interfaces:**
- Consumes: Contracts "Skill references" (the reference layout and the `Read [<topic>.md](references/<topic>.md) before you <action>.` line).
- Produces: Contracts "Skill references" for this skill: ten references listed above, each linked from SKILL.md by such a line; SKILL.md at 17,935 bytes, which leaves later tasks in this skill (Tasks 9 and 15) about 2,000 bytes under the 20,000 cap. `tests/fixtures/sdd-text.sh` defines `SDD` and one `SDD_<TOPIC>` path variable per reference, and `sdd_text`, which prints SKILL.md and every moved reference.

**Items:** 14

**Depends on:** none

**Implementer:** dforge:impl-sonnet-high
**Evaluation:** files 2 - spec 0 - coupling 1 - risk 2 = 5

**What moves.** Text moves verbatim except two things: links written for SKILL.md are rewritten for a file one level deeper (`](../../reference/` becomes `](../../../reference/`, `](references/` becomes `](`), and each moved section leaves its `##` heading in SKILL.md with a `Read … before you …` line. Stays in SKILL.md: frontmatter, After compaction, Auto run, Select the host first, Overview (less its rationale paragraphs), When to Use, Seats, The Task Loop (less its batching paragraph), Final Review, Finish (less its closing paragraph). The Process flowchart becomes a five-step list, and the whole flowchart moves to `process-graph.md`. After compaction step 2 gains a pointer to the Recovery table in `ledger.md`, and When to Use points there too.

- [ ] **Step 1: Write the fixture and the new test, and see the test fail**

Create `plugins/dforge/tests/fixtures/sdd-text.sh`:

````bash
#!/usr/bin/env bash
# Sourced by the tests that pin text of the subagent-driven-development skill.
# SDD is its SKILL.md; each SDD_* below is a reference that holds text moved
# out of it to keep SKILL.md under 20 KB. sdd_text prints all of them, for a
# pin that asserts a phrase appears nowhere in the skill.
SDD_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../skills/subagent-driven-development" && pwd)"
SDD="$SDD_DIR/SKILL.md"
SDD_BATCHING="$SDD_DIR/references/batching.md"
SDD_BUDGET="$SDD_DIR/references/budget.md"
SDD_EXAMPLE="$SDD_DIR/references/example-workflow.md"
SDD_FINISH_RULINGS="$SDD_DIR/references/finish-rulings.md"
SDD_GRAPH="$SDD_DIR/references/process-graph.md"
SDD_LEDGER="$SDD_DIR/references/ledger.md"
SDD_RATIONALE="$SDD_DIR/references/rationale.md"
SDD_RATIONALIZATIONS="$SDD_DIR/references/rationalizations.md"
SDD_RULING_SEAT="$SDD_DIR/references/ruling-seat.md"
SDD_SETUP="$SDD_DIR/references/setup.md"

sdd_text() {
  cat "$SDD" "$SDD_BATCHING" "$SDD_BUDGET" "$SDD_EXAMPLE" "$SDD_FINISH_RULINGS" "$SDD_GRAPH" \
    "$SDD_LEDGER" "$SDD_RATIONALE" "$SDD_RATIONALIZATIONS" "$SDD_RULING_SEAT" "$SDD_SETUP"
}
````

Create `plugins/dforge/tests/sdd-references.test.sh`:

````bash
#!/usr/bin/env bash
# subagent-driven-development keeps SKILL.md small by moving what one step
# reads into references/. A moved reference must exist and be linked from
# SKILL.md by a "Read ... before you ..." line, so a session that lost the tail
# of the skill after compaction still reaches it, and every relative link in
# the skill and its moved references must resolve.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/fixtures/sdd-text.sh"

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}

# broken_links <file> - every relative link target in FILE that does not exist
broken_links() {
  local dir target
  dir=$(dirname "$1")
  grep -o '](\([^)#]*\)' "$1" | sed 's/^](//' | grep -v '^http' | while IFS= read -r target; do
    if [ -n "$target" ] && [ ! -e "$dir/$target" ]; then printf '%s\n' "$target"; fi
  done
}

check "SKILL.md keeps the After compaction block" "$(grep -c '^## After compaction$' "$SDD")" "1"
check "SKILL.md links ledger.md from the After compaction block" \
  "$(awk '/^## After compaction$/ { on = 1; next } /^## / { on = 0 } on' "$SDD" | grep -c 'references/ledger\.md')" "1"
check "SKILL.md: every relative link resolves" "$(broken_links "$SDD")" ""

for topic in batching budget example-workflow finish-rulings ledger process-graph rationale rationalizations ruling-seat setup; do
  ref="$SDD_DIR/references/$topic.md"
  check "references/$topic.md exists and is not empty" "$([ -s "$ref" ] && echo yes || echo no)" "yes"
  check "SKILL.md links $topic.md with a Read line" \
    "$(grep -cE "^Read \[$topic\.md\]\(references/$topic\.md\) before you " "$SDD")" "1"
  check "references/$topic.md: every relative link resolves" "$(broken_links "$ref")" ""
done

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
````

Run: `timeout 60 bash plugins/dforge/tests/sdd-references.test.sh | tail -3`
Expected: FAIL lines (`references/ledger.md exists and is not empty`, `SKILL.md links ledger.md with a Read line`, and the same for the nine other references), ending `12 passed, 21 failed`; grep also prints `No such file` errors for the references that do not exist yet.

- [ ] **Step 2: Split SKILL.md into the references**

Write `${TMPDIR:-/tmp}/dforge-split-sdd.sh`:

````bash
#!/usr/bin/env bash
set -euo pipefail
cd plugins/dforge/skills/subagent-driven-development
ORIG=$(mktemp)
cp SKILL.md "$ORIG"
trap 'rm -f "$ORIG"' EXIT

section() { # section <heading>: the lines under a "## " heading, without surrounding blank lines
  awk -v h="$1" '
    $0 == h { on = 1; next }
    on && /^## / { exit }
    on { if (!started && $0 == "") next; started = 1; buf[++n] = $0 }
    END { while (n > 0 && buf[n] == "") n--; for (i = 1; i <= n; i++) print buf[i] }
  ' "$ORIG"
}
cut_lines() { # cut_lines <start-regex> <end-regex>: print the lines from the first start match through the first end match (inclusive); an empty end regex stops at the first blank line (exclusive)
  awk -v s="$1" -v e="$2" '
    $0 ~ s { on = 1 }
    on && e == "" && $0 == "" { exit }
    on { print }
    on && e != "" && $0 ~ e { exit }
  ' "$ORIG"
}
replace_lines() { # replace_lines <start-regex> <end-regex> <replacement>, stdin to stdout: swap that range for one line
  awk -v s="$1" -v e="$2" -v r="$3" '
    !done && $0 ~ s { skip = 1; print r }
    skip && e == "" && $0 == "" { skip = 0; done = 1 }
    skip { if (e != "" && $0 ~ e) { skip = 0; done = 1 } next }
    { print }
  '
}
relink() { sed -e 's#\](\.\./\.\./reference/#](../../../reference/#g' -e 's#\](references/#](#g'; }
reference() { # reference <file> <title>, the body on stdin
  { printf '# %s\n\n' "$2"; relink; } > "references/$1"
}

WHY='^\*\*Why subagents:\*\*'
CORE='^\*\*Core principle:\*\*'
RIDE='^\*\*Your rulings ride in that message\.\*\*'
BATCH='^\*\*Batch small same-shape work\.\*\*'

section '## The Process' | reference process-graph.md 'The Process flowchart'
section '## Setup' | reference setup.md 'Setup'
section '## The Ledger' | reference ledger.md 'The Ledger'
section '## The Ruling Seat' | reference ruling-seat.md 'The Ruling Seat'
section '## Session Budget' | reference budget.md 'Session Budget'
section '## Common Rationalizations' | reference rationalizations.md 'Common Rationalizations'
section '## Example Workflow' | reference example-workflow.md 'Example Workflow'
cut_lines "$WHY" "$CORE" | reference rationale.md 'Why subagents and tiered agents'
cut_lines "$BATCH" '' | reference batching.md 'Batching small same-shape work'
cut_lines "$RIDE" '' | reference finish-rulings.md 'Your rulings ride in the finishing message'

keep() { printf '## %s\n\n' "$1"; section "## $1"; printf '\n'; }
stub() { printf '## %s\n\n' "$1"; cat; printf '\n'; }

{
  sed -n '1,7p' "$ORIG"
  printf '## After compaction\n\n'
  section '## After compaction' | awk '
    $0 == "2. Trust the ledger and `git log` over the summary. For each task the last" {
      print "2. Trust the ledger and `git log` over the summary. Read"
      print "   [ledger.md](references/ledger.md) §Recovery before you act on a ledger line. For each task the last"
      next
    }
    { print }
  '
  printf '\n'
  keep 'Auto run'
  keep 'Select the host first'
  printf '## Overview\n\n'
  section '## Overview' | replace_lines "$WHY" "$CORE" 'Read [rationale.md](references/rationale.md) before you explain or change why this mode uses subagents and tiered agents. A fleet dispatch passes neither `model` nor `effort`: either one overrides the pinned value.'
  printf '\n'
  printf '## When to Use\n\n'
  section '## When to Use' | sed -e 's#^below says what to do with it\.$#in [ledger.md](references/ledger.md) says what to do with it.#'
  printf '\n'
  stub 'The Process' <<'STUB'
The flowchart is in [process-graph.md](references/process-graph.md); per task the steps are:

1. Dispatch the implementer the task's `**Implementer:**` line names, with the dispatch file `task-step start` writes ([implementer-prompt.md](references/implementer-prompt.md)). On NEEDS_CONTEXT, supply the missing fact and re-dispatch when it is mechanical; otherwise send a `blocked-plan` item to the ruling seat.
2. `scripts/review-route` grades the task `review=group` or `review=task`. A group task is held with `task-step hold` and reviewed with the others at 4 held, before a `review=task` dispatch and after the last task ([group-reviewer-prompt.md](references/group-reviewer-prompt.md)); any other task gets its own judge ([task-reviewer-prompt.md](references/task-reviewer-prompt.md)).
3. Verdicts clean and no score from 1 to 8: append the `complete` line and take the next task.
4. Otherwise a finding that conflicts with plan text goes to the ruling seat first ([ruling-prompt.md](references/ruling-prompt.md)). Then run fix round R of 2 (R=1 resume or fresh by cache state, R=2 the successor rung, fresh), each followed by a scoped re-review ([re-review-prompt.md](references/re-review-prompt.md)).
5. A finding still open after round 2 goes to the ruling seat as a `breaker` item: a CONFIRMED-GAP or AMEND is carried forward, BLOCKED stops, the rest are parked in the ledger with the ruling. Then append the `complete` line.

After the last task: final review (a code reviewer and a Codex round, a judge verifies the union), ONE fix dispatch, one scoped re-review, the ruling seat on residuals, `Final review: clean`, then dforge:finishing-a-development-branch.

Read [process-graph.md](references/process-graph.md) before you route a state the steps above do not place.
STUB
  stub 'Setup' <<'STUB'
Ensure the work happens in an isolated workspace: use dforge:using-git-worktrees to create one or verify the existing one. Never start implementation on a main/master branch without your human partner's explicit consent.

Read [setup.md](references/setup.md) before you create the ledger or dispatch Task 1.
STUB
  keep 'Seats'
  stub 'The Ledger' <<'STUB'
This skill owns every line in `<ledger dir>/progress.md`.

Read [ledger.md](references/ledger.md) before you write a ledger line or recover a task's state.
STUB
  stub 'The Ruling Seat' <<'STUB'
Judgment belongs to the ruling seat, never to you, whatever model you run on.

Read [ruling-seat.md](references/ruling-seat.md) before you send it an item or carry out a verdict.
STUB
  stub 'Session Budget' <<'STUB'
`scripts/task-brief`, `scripts/review-package` and every `scripts/task-step` digest end their output with the budget line ([session-budget.md](../../reference/session-budget.md)).

Read [budget.md](references/budget.md) before you act on a budget verdict.
STUB
  printf '## The Task Loop\n\n'
  section '## The Task Loop' | replace_lines "$BATCH" '' 'Read [batching.md](references/batching.md) before you batch small same-shape tasks into one dispatch.'
  printf '\n'
  keep 'Final Review'
  printf '## Finish\n\n'
  section '## Finish' | replace_lines "$RIDE" '' 'Read [finish-rulings.md](references/finish-rulings.md) before you call the finishing skill: your rulings ride in its message.'
  printf '\n'
  stub 'Common Rationalizations' <<'STUB'
Read [rationalizations.md](references/rationalizations.md) before you skip a review, a re-review, a ledger line or a budget check.
STUB
  stub 'Example Workflow' <<'STUB'
Read [example-workflow.md](references/example-workflow.md) before you run your first task: it shows two tasks from Setup to finishing.
STUB
} | awk 'NF || !blank { print } { blank = !NF }' > SKILL.new
mv SKILL.new SKILL.md
````

Run, from the repository root: `bash "${TMPDIR:-/tmp}/dforge-split-sdd.sh"`
Expected: no output. Then `wc -c plugins/dforge/skills/subagent-driven-development/SKILL.md` prints a count under 18,500.

Prove that no line was lost. Every non-blank line of the committed SKILL.md must be in the new SKILL.md or in a moved reference, links rewritten as above. Run:

```bash
d=plugins/dforge/skills/subagent-driven-development
new=$(mktemp)
cat "$d/SKILL.md" "$d"/references/{batching,budget,example-workflow,finish-rulings,ledger,process-graph,rationale,rationalizations,ruling-seat,setup}.md > "$new"
git show "HEAD:$d/SKILL.md" | awk '
  FNR == NR { seen[$0] = 1; next }
  $0 == "" { next }
  {
    r = $0
    gsub(/\]\(\.\.\/\.\.\/reference\//, "](../../../reference/", r)
    gsub(/\]\(references\//, "](", r)
    if (!($0 in seen) && !(r in seen)) print FNR ": " $0
  }
' "$new" -
rm -f "$new"
```

Expected: exactly these two lines, the two sentences the split rewrote on purpose:

```
20: 2. Trust the ledger and `git log` over the summary. For each task the last
166: below says what to do with it.
```

- [ ] **Step 3: Repoint the pin tests at the references**

Twelve existing tests grep text that now lives in a reference. Each assertion stays: it names the reference that holds its text, an assertion that a phrase is gone checks `sdd_text`, and the loops that ran one assertion over both execution skills take the new file for this one. `working-directory.test.sh` counted nine files citing `(see using-dforge §Session Budget)`; the moved Setup text adds a tenth, so that count becomes "at least nine" and does not change again when other skills split.

Write `${TMPDIR:-/tmp}/dforge-repoint-sdd-pins.sh`:

````bash
#!/usr/bin/env bash
# Repoints the pin tests that grep text moved out of subagent-driven-development/SKILL.md.
set -euo pipefail
cd plugins/dforge/tests
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
edit() { sed -E -f "$1" "$2" > "$2.new" && cat "$2.new" > "$2" && rm -f "$2.new"; }

cat > "$T/task-step-text.sed" <<'EOF'
/^INLINE="\$P\/skills\/executing-plans\/SKILL\.md"$/a\
. "$HERE/fixtures/sdd-text.sh"
/^(names|lacks) "the example workflow /s/"\$SDD"/"$SDD_EXAMPLE"/
/^names "subagent mode: the example round has no progress field"/s/"\$SDD"/"$SDD_EXAMPLE"/
/^(names|lacks) "the rationalization row /s/"\$SDD"/"$SDD_RATIONALIZATIONS"/
/^(names|lacks) "(the ledger grammar |a group list |a comma list |the recovery table )/s/"\$SDD"/"$SDD_LEDGER"/
/^check "the recovery table has one row per Group round"/s/"\$SDD"/"$SDD_LEDGER"/
/^(names|lacks) "subagent mode: (the fix-round grammar|the group round grammar|a group's round [12] |the wave round grammar|older ledgers map R\/5|a Codex R\/5 line is live|the merged grammar|the integrated grammar|recovery reads merged as closed|the old integrated grammar is gone)/s/"\$SDD"/"$SDD_LEDGER"/
/^names "subagent mode: a Codex R\/5 line is live"/s|\(\.\./\.\./reference/delegated-task\.md\)|(../../../reference/delegated-task.md)|
/^names "(subagent mode: the breaker row|a header amendment's confirmation reads the first report)"/s/"\$SDD"/"$SDD_RULING_SEAT"/
/^names "(the process graph names the group template|subagent mode: the flowchart caps at 2)"/s/"\$SDD"/"$SDD_GRAPH"/
/^  lacks "subagent mode drops: \$gone" "\$SDD" "\$gone"$/c\
  check "subagent mode drops: $gone" "$(sdd_text | grep -cF -- "$gone")" "0"
/^only_older "subagent mode names R\/5 only for older runs" "\$SDD"$/a\
only_older "the ledger names R/5 only for older runs" "$SDD_LEDGER"
/^for f in "\$SDD" "\$INLINE"; do$/,/^done$/{
  s/^for f in "\$SDD" "\$INLINE"; do$/for f in "$SDD_RULING_SEAT" "$INLINE"; do/
  s|^  s=\$\(basename "\$\(dirname "\$f"\)"\)$|&/$(basename "$f")|
}
EOF
edit "$T/task-step-text.sed" task-step-text.test.sh

cat > "$T/final-phase.sed" <<'EOF'
/^SDD="\$P\/skills\/subagent-driven-development\/SKILL\.md"$/a\
. "$HERE/fixtures/sdd-text.sh"
/^names "subagent mode: (--final is for the record|the final phase never hands off)"/s/"\$SDD"/"$SDD_BUDGET"/
/^names "subagent mode: the spec's Finish line replaces the question"/s/"\$SDD"/"$SDD_SETUP"/
s/^for f in "\$SDD" "\$EP" "\$H" "\$FR"; do$/for f in "$SDD" "$SDD_BUDGET" "$SDD_LEDGER" "$EP" "$H" "$FR"; do/
EOF
edit "$T/final-phase.sed" final-phase.test.sh

cat > "$T/inline-mode.sed" <<'EOF'
/^FINAL="\$P\/reference\/final-review\.md"$/a\
. "$HERE/fixtures/sdd-text.sh"
/^present "subagent mode( finishes the task before a handoff|'s last task is a soft stop)"/s/"\$SDD"/"$SDD_BUDGET"/
/^present "the inline recovery row ranks above both"/s/"\$SDD"/"$SDD_LEDGER"/
/^  present "subagent ledger has: \$line"/s/"\$SDD"/"$SDD_LEDGER"/
/^present "subagent (ledger has the Final fix line|mode recovers a lost fix wave)"/s/"\$SDD"/"$SDD_LEDGER"/
/^present "subagent mode defers per-task recovery"/s/"\$SDD"/"$SDD_LEDGER"/
/^present "subagent mode defers per-task recovery"/s|\(\.\./\.\./reference/delegated-task\.md\)|(../../../reference/delegated-task.md)|
/^(absent "subagent mode no longer denies the Codex budget line"|present "subagent mode names the measured Codex line")/s/"\$SDD"/"$SDD_BUDGET"/
/^# One ledger grammar for both modes\.$/,/^present "inline marks an unreviewed completion"/{
  s/^for f in "\$INLINE" "\$SDD"; do$/for f in "$INLINE" "$SDD_LEDGER"; do/
  s|^  s=\$\(basename "\$\(dirname "\$f"\)"\)$|&/$(basename "$f")|
}
/^# A standing project constraint outranks a spec/,/^done$/{
  s/^for f in "\$INLINE" "\$SDD"; do$/for f in "$INLINE" "$SDD_SETUP"; do/
  s|\$\(basename "\$\(dirname "\$f"\)"\)|&/$(basename "$f")|
}
EOF
edit "$T/inline-mode.sed" inline-mode.test.sh

cat > "$T/waiting-text.sed" <<'EOF'
/^INLINE="\$P\/skills\/executing-plans\/SKILL\.md"$/a\
. "$HERE/fixtures/sdd-text.sh"
/^check "subagent-driven-development prescribes no Monitor or sleep wait"/c\
check "subagent-driven-development prescribes no Monitor or sleep wait" "$(polling <(sdd_text))" ""
/^names "(the ruling route takes a comma-separated kind list|simple kinds route to judge-sonnet-high|the other kinds stay on judge-opus|a mechanical check settles a cannot-verify item|a failed check is a fix-loop finding)"/s/"\$SDD"/"$SDD_RULING_SEAT"/
EOF
edit "$T/waiting-text.sed" waiting-text.test.sh

cat > "$T/review-route.sed" <<'EOF'
/^SDD="\$P\/skills\/subagent-driven-development\/SKILL\.md"$/a\
. "$HERE/fixtures/sdd-text.sh"
/^absent "SDD no longer averages three seats"/c\
check "SDD no longer averages three seats" "$(sdd_text | grep -cF -- 'average each criterion')" "0"
/^absent "SDD no longer writes K=3"/c\
check "SDD no longer writes K=3" "$(sdd_text | grep -cF -- 'K=3')" "0"
/^absent "SDD no longer pins the ruling seat to Fable"/c\
check "SDD no longer pins the ruling seat to Fable" "$(sdd_text | grep -cF -- '`dforge:judge-fable` (`judge-opus` under the Fable-unavailable rule,')" "0"
/^absent "SDD no longer keeps the confirmation off Opus"/c\
check "SDD no longer keeps the confirmation off Opus" "$(sdd_text | grep -cF -- 'never hand it')" "0"
/^present "the flow graph completes a task whose gap is carried"/s/"\$SDD"/"$SDD_GRAPH"/
/^present "SDD confirms a header amendment on a second seat"/s/"\$SDD"/"$SDD_RULING_SEAT"/
/^present "the ledger grammar is executor-neutral"/s/"\$SDD"/"$SDD_LEDGER"/
s|^for f in "\$P/skills/subagent-driven-development/SKILL\.md" \\$|for f in "$P/skills/subagent-driven-development/SKILL.md" "$SDD_RULING_SEAT" "$SDD_LEDGER" "$SDD_GRAPH" \\|
EOF
edit "$T/review-route.sed" review-route.test.sh

cat > "$T/process-roles.sed" <<'EOF'
/^P="\$HERE\/\.\."$/a\
. "$HERE/fixtures/sdd-text.sh"
/^for f in "\$P\/skills\/subagent-driven-development\/SKILL\.md" "\$P\/skills\/executing-plans\/SKILL\.md"; do$/,/^done$/{
  s|"\$P/skills/subagent-driven-development/SKILL\.md"|"$SDD_LEDGER"|
  s|^  s=\$\(basename "\$\(dirname "\$f"\)"\)$|&/$(basename "$f")|
}
EOF
edit "$T/process-roles.sed" process-roles.test.sh

cat > "$T/auto-run-skills.sed" <<'EOF'
/^names "subagent-driven-development: the budget section says so"/s|skills/subagent-driven-development/SKILL\.md|skills/subagent-driven-development/references/budget.md|
EOF
edit "$T/auto-run-skills.sed" auto-run-skills.test.sh

cat > "$T/project-status.sed" <<'EOF'
/^STATE="\$P\/reference\/project-state\.md"$/a\
. "$HERE/fixtures/sdd-text.sh"
/^for skill_file in "\$P\/skills\/executing-plans\/SKILL\.md" "\$P\/skills\/subagent-driven-development\/SKILL\.md"; do$/,/^done$/{
  s|"\$P/skills/subagent-driven-development/SKILL\.md"|"$SDD_SETUP"|
  s|\$\(basename "\$\(dirname "\$skill_file"\)"\)|&/$(basename "$skill_file")|
}
/^for skill in subagent-driven-development executing-plans; do$/,/^done$/c\
for skill_file in "$SDD_LEDGER" "$P/skills/executing-plans/SKILL.md"; do\
  present "$(basename "$(dirname "$skill_file")")/$(basename "$skill_file"): pushes after each ledger line" "$skill_file" '§darkmem sync points'\
  present "$(basename "$(dirname "$skill_file")")/$(basename "$skill_file"): the push instruction itself" "$skill_file" \\\
    'After each `complete` and `fix round` line, run `scripts/darkmem-sync push`;'\
done
EOF
edit "$T/project-status.sed" project-status.test.sh

cat > "$T/working-directory.sed" <<'EOF'
/^check "nine skill and reference files cite the contract" \\$/,/"9"$/c\
check "at least nine skill and reference files cite the contract" \\\
  "$([ "$(grep -rlF '(see using-dforge §Session Budget)' "$P/skills" "$P/reference" | wc -l | tr -d ' ')" -ge 9 ] \&\& echo yes || echo no)" "yes"
EOF
edit "$T/working-directory.sed" working-directory.test.sh

cat > "$T/faster-plans.sed" <<'EOF'
/^a8\(\) \{$/,/^\}$/s|skills/subagent-driven-development/SKILL\.md|skills/subagent-driven-development/references/process-graph.md|
s|skills/subagent-driven-development/SKILL\.md|skills/subagent-driven-development/references/ledger.md|
EOF
edit "$T/faster-plans.sed" faster-plans.acceptance.test.sh

cat > "$T/review-depth.sed" <<'EOF'
/^SD="\$PLUGIN\/skills\/subagent-driven-development\/SKILL\.md"$/a\
. "$HERE/fixtures/sdd-text.sh"
s|sd=\$\(doc "\$SD"\)|sd=$(doc "$SDD_LEDGER")|
EOF
edit "$T/review-depth.sed" review-depth.acceptance.test.sh

cat > "$T/review-depth-qa.sed" <<'EOF'
/^SD="\$PLUGIN\/skills\/subagent-driven-development\/SKILL\.md"$/a\
. "$HERE/fixtures/sdd-text.sh"
s|SDF=\$\(flat "\$SD"\)|SDF=$(flat "$SDD_LEDGER")|
EOF
edit "$T/review-depth-qa.sed" review-depth-qa.acceptance.test.sh
````

Run, from the repository root: `bash "${TMPDIR:-/tmp}/dforge-repoint-sdd-pins.sh"`
Expected: no output, and `git diff --stat -- plugins/dforge/tests | tail -1` prints `12 files changed, 98 insertions(+), 88 deletions(-)`.

- [ ] **Step 4: Run the tests**

Run:

```bash
for t in sdd-references task-step-text waiting-text final-phase inline-mode project-status process-roles review-route auto-run-skills working-directory review-depth.acceptance review-depth-qa.acceptance faster-plans.acceptance task-loop-steps.acceptance turn-end criteria seats; do
  printf '%s: ' "$t"
  timeout 1200 bash "plugins/dforge/tests/$t.test.sh" 2>&1 | tail -n 1
done
```

Expected: every line ends `, 0 failed`. `faster-plans.acceptance` takes several minutes; none of these tests starts a process that outlives it.

- [ ] **Step 5: Validate**

Run: `node scripts/validate-repository.mjs && timeout 120 /root/.local/bin/claude plugin validate plugins/dforge`
Expected: the repository check prints its validity line and the plugin check prints `Validation passed`.

- [ ] **Step 6: Commit**

```bash
git add plugins/dforge/skills/subagent-driven-development/SKILL.md plugins/dforge/skills/subagent-driven-development/references/batching.md plugins/dforge/skills/subagent-driven-development/references/budget.md plugins/dforge/skills/subagent-driven-development/references/example-workflow.md plugins/dforge/skills/subagent-driven-development/references/finish-rulings.md plugins/dforge/skills/subagent-driven-development/references/ledger.md plugins/dforge/skills/subagent-driven-development/references/process-graph.md plugins/dforge/skills/subagent-driven-development/references/rationale.md plugins/dforge/skills/subagent-driven-development/references/rationalizations.md plugins/dforge/skills/subagent-driven-development/references/ruling-seat.md plugins/dforge/skills/subagent-driven-development/references/setup.md plugins/dforge/tests/fixtures/sdd-text.sh plugins/dforge/tests/sdd-references.test.sh plugins/dforge/tests/auto-run-skills.test.sh plugins/dforge/tests/faster-plans.acceptance.test.sh plugins/dforge/tests/final-phase.test.sh plugins/dforge/tests/inline-mode.test.sh plugins/dforge/tests/process-roles.test.sh plugins/dforge/tests/project-status.test.sh plugins/dforge/tests/review-depth-qa.acceptance.test.sh plugins/dforge/tests/review-depth.acceptance.test.sh plugins/dforge/tests/review-route.test.sh plugins/dforge/tests/task-step-text.test.sh plugins/dforge/tests/waiting-text.test.sh plugins/dforge/tests/working-directory.test.sh
git commit -m "refactor(dforge): split sdd skill under 20 KB"
```

**Check:** `wc -c plugins/dforge/skills/subagent-driven-development/SKILL.md` prints a count at or under 20,000 (17,935 expected), `bash plugins/dforge/tests/sdd-references.test.sh | tail -n 1` prints `33 passed, 0 failed`, and the Step 4 loop ends every line with `, 0 failed`.

### Task 3: Add the implementer agent clauses

**Files:**
- Modify: `plugins/dforge/agents/impl-fable-high.md`, `impl-fable-low.md`, `impl-fable-max.md`, `impl-fable-medium.md`, `impl-fable-xhigh.md`, `impl-haiku.md`, `impl-opus-high.md`, `impl-opus-low.md`, `impl-opus-max.md`, `impl-opus-medium.md`, `impl-opus-xhigh.md`, `impl-sonnet-high.md`, `impl-sonnet-low.md`, `impl-sonnet-max.md`, `impl-sonnet-medium.md`, `impl-sonnet-xhigh.md`
- Test: `plugins/dforge/tests/impl-clauses.test.sh` (new)

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: in every `agents/impl-*.md`, the scope-limit clause followed by three clauses (a general solution, report a test that looks wrong, never edit or delete an existing test), which `tests/impl-clauses.test.sh` pins.

**Items:** 7

**Depends on:** none

**Implementer:** dforge:impl-sonnet-low
**Evaluation:** files 1 - spec 0 - coupling 0 - risk 1 = 2

The five Sonnet agents already carry the scope-limit clause (`Change only what the brief asks for. …`) as the paragraph after the end-of-turn rule; the three clauses go straight after it, ahead of any later paragraph (`impl-sonnet-low` has a verification paragraph, `impl-sonnet-max` and `impl-sonnet-xhigh` a stop-after-checks paragraph). The eleven Opus, Fable and Haiku agents have no scope-limit clause: they gain it and the three clauses at the end of the file. `tests/fleet.test.sh` requires agent files to be ASCII only, so the clauses use plain hyphens and colons.

- [ ] **Step 1: Write the failing test**

Create `plugins/dforge/tests/impl-clauses.test.sh`:

````bash
#!/usr/bin/env bash
# Every implementer tier carries the scope-limit clause, then the three clauses
# that keep tests honest: a general solution, report a wrong test, never touch
# an existing test. Prose wraps, so each clause is matched with its line breaks
# folded to spaces.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENTS="$HERE/../agents"

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
flat() { tr '\n' ' ' < "$1" | tr -s ' '; }
says() { # says <label> <file> <text>
  check "$1" "$(flat "$2" | grep -cF -- "$3")" "1"
}

n=0
for f in "$AGENTS"/impl-*.md; do
  n=$((n + 1))
  b=$(basename "$f" .md)
  says "$b: the scope-limit clause" "$f" \
    'Change only what the brief asks for. Do not add features, tests, files, docs or refactors the brief does not call for; if you think one would help, say so in your report instead.'
  says "$b: write a general solution" "$f" \
    'Write a general solution that is correct for every valid input, never one that only passes the specific inputs a test uses: no hardcoded expected values and no special-casing of test inputs.'
  says "$b: report a test that looks wrong" "$f" \
    'When a test looks wrong, report it as incorrect in your report instead of working around it or changing the code to satisfy it.'
  says "$b: existing tests are immutable" "$f" \
    'Never edit or delete an existing test unless the brief names it.'
  check "$b: the three clauses follow the scope clause, in order" \
    "$(awk '
      /^Change only what the brief asks for\./ { s = NR }
      /^Write a general solution/ { g = NR }
      /^When a test looks wrong/ { w = NR }
      /^Never edit or delete an existing test/ { e = NR }
      END { print (s && s < g && g < w && w < e) ? "yes" : "no" }
    ' "$f")" "yes"
done
check "the fleet has sixteen implementers" "$n" "16"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
````

- [ ] **Step 2: Run it to see it fail**

Run: `timeout 60 bash plugins/dforge/tests/impl-clauses.test.sh | tail -n 2`
Expected: `6 passed, 75 failed` (the five Sonnet scope-limit clauses and the file count pass; everything else fails).

- [ ] **Step 3: Add the clauses**

Write `${TMPDIR:-/tmp}/dforge-add-impl-clauses.sh`:

````bash
#!/usr/bin/env bash
set -euo pipefail
cd plugins/dforge/agents

scope=$(mktemp)
clauses=$(mktemp)
trap 'rm -f "$scope" "$clauses"' EXIT

cat > "$scope" <<'EOF'
Change only what the brief asks for. Do not add features, tests, files,
docs or refactors the brief does not call for; if you think one would
help, say so in your report instead.
EOF

cat > "$clauses" <<'EOF'
Write a general solution that is correct for every valid input, never one
that only passes the specific inputs a test uses: no hardcoded expected
values and no special-casing of test inputs.

When a test looks wrong, report it as incorrect in your report instead of
working around it or changing the code to satisfy it.

Never edit or delete an existing test unless the brief names it.
EOF

for f in impl-*.md; do
  if grep -q '^help, say so in your report instead\.$' "$f"; then
    awk -v c="$clauses" '
      { print }
      /^help, say so in your report instead\.$/ { print ""; while ((getline line < c) > 0) print line }
    ' "$f" > "$f.new"
  else
    { cat "$f"; printf '\n'; cat "$scope"; printf '\n'; cat "$clauses"; } > "$f.new"
  fi
  mv "$f.new" "$f"
done
````

Run, from the repository root: `bash "${TMPDIR:-/tmp}/dforge-add-impl-clauses.sh"`
Expected: no output; `git diff --stat -- plugins/dforge/agents | tail -n 1` prints `16 files changed, 188 insertions(+)`.

- [ ] **Step 4: Run the tests and validate**

Run:

```bash
timeout 60 bash plugins/dforge/tests/impl-clauses.test.sh | tail -n 1
timeout 120 bash plugins/dforge/tests/fleet.test.sh | tail -n 1
timeout 300 node --test evals/tiers/tests/*.test.mjs 2>&1 | grep -E '^ℹ (pass|fail)'
node scripts/validate-repository.mjs && timeout 120 /root/.local/bin/claude plugin validate plugins/dforge
```

Expected: `81 passed, 0 failed`; `0 failed` from the fleet test; `ℹ pass 81` and `ℹ fail 0`; then the repository validity line and `Validation passed`.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/agents/impl-fable-high.md plugins/dforge/agents/impl-fable-low.md plugins/dforge/agents/impl-fable-max.md plugins/dforge/agents/impl-fable-medium.md plugins/dforge/agents/impl-fable-xhigh.md plugins/dforge/agents/impl-haiku.md plugins/dforge/agents/impl-opus-high.md plugins/dforge/agents/impl-opus-low.md plugins/dforge/agents/impl-opus-max.md plugins/dforge/agents/impl-opus-medium.md plugins/dforge/agents/impl-opus-xhigh.md plugins/dforge/agents/impl-sonnet-high.md plugins/dforge/agents/impl-sonnet-low.md plugins/dforge/agents/impl-sonnet-max.md plugins/dforge/agents/impl-sonnet-medium.md plugins/dforge/agents/impl-sonnet-xhigh.md plugins/dforge/tests/impl-clauses.test.sh
git commit -m "feat(dforge): add test-integrity clauses to impl agents"
```

**Check:** `bash plugins/dforge/tests/impl-clauses.test.sh | tail -n 1` prints `81 passed, 0 failed`, and `bash plugins/dforge/tests/fleet.test.sh | tail -n 1` ends `0 failed`.


### Task 4: Gate implementer stops on the report

**Files:**
- Create: `plugins/dforge/scripts/impl-stop-gate`
- Create: `plugins/dforge/tests/impl-stop-gate.test.sh`
- Create: `plugins/dforge/tests/fixtures/subagent-stop-input.json`
- Create: `docs/dforge/notes/2026-10-28-subagent-stop-input.md`
- Modify: `plugins/dforge/hooks/hooks.json` (the `description` string, and a new `SubagentStop` entry after `Stop`)

**Interfaces:**
- Consumes: Contracts "Implementer report", as text only: the `## Verified` bullet grammar, the `Report:` line and the three gate regexes. The gate never reads `implementer-prompt.md`, which Task 9 rewrites in the same wave.
- Produces: Contracts "Stop gate": the `SubagentStop` entry in `hooks.json`, `scripts/impl-stop-gate`, its counter files under `<state>/impl-stop-gate/`, the log `<state>/impl-stop-gate.log`, and `tests/fixtures/subagent-stop-input.json`.

**Items:** 13

**Depends on:** none

**Implementer:** dforge:impl-sonnet-high
**Evaluation:** files 2 - spec 0 - coupling 1 - risk 2 = 5

- [ ] **Step 1: Write the live probe script**

The probe observes one real `SubagentStop` input before the gate is written. It lives outside the checkout and is removed in Step 11. A fresh `CLAUDE_CONFIG_DIR` has no login, so the probe inherits the session's `CLAUDE_CONFIG_DIR` for credentials only. Everything else stays isolated: `--setting-sources project` keeps the owner's settings out, `CLAUDE_CODE_DISABLE_CLAUDE_MDS=1` keeps their instructions out, `HOME` and the XDG directories are temporary, `--no-session-persistence` writes no transcript, and the run happens in an empty temporary directory, never in a checkout. Each run spends about $0.01 and is capped at $2.

Create `/tmp/dforge-task4-probe.sh`:

```bash
#!/usr/bin/env bash
# Live probe for the SubagentStop hook.
# Usage: bash /tmp/dforge-task4-probe.sh REPO_ROOT OUT_DIR MODE [NOTE_PATH]
#   MODE probe: a logging hook given by --settings records every SubagentStop input and blocks the first two stops;
#               with NOTE_PATH it also writes the observation note.
#   MODE wired: only the plugin's own hooks run; the gate's state directory is copied to OUT_DIR/state.
set -uo pipefail
REPO=$1 OUT=$2 MODE=$3 NOTE=${4:-}
[ -n "${CLAUDE_CONFIG_DIR:-}" ] || { echo "CLAUDE_CONFIG_DIR is unset: this session's login lives there"; exit 2; }
PROBE=$(mktemp -d)
mkdir -p "$PROBE/home" "$PROBE/work" "$PROBE/stops" "$OUT"
cat > "$PROBE/hook.sh" <<'HOOK'
#!/usr/bin/env bash
n=$(ls "$PROBE_STOPS" | wc -l | tr -d ' ')
cat > "$PROBE_STOPS/stop-$((n + 1)).json"
if [ "$n" -lt 2 ]; then echo "probe block $((n + 1)): end your reply with the line Report: $PROBE_STOPS/second.md" >&2; exit 2; fi
exit 0
HOOK
jq -n --arg c "bash $PROBE/hook.sh" '{hooks:{SubagentStop:[{matcher:".*",hooks:[{type:"command",command:$c}]}]}}' > "$PROBE/settings.json"
args=(-p --model haiku --setting-sources project --plugin-dir "$REPO/plugins/dforge" --allowedTools Agent --max-budget-usd 2 --output-format json --no-session-persistence)
[ "$MODE" = probe ] && args+=(--settings "$PROBE/settings.json")
version=$(/root/.local/bin/claude --version | cut -d' ' -f1)
cd "$PROBE/work" || exit 1
export HOME="$PROBE/home" XDG_CONFIG_HOME="$PROBE/home/.config" XDG_DATA_HOME="$PROBE/home/.local/share" XDG_CACHE_HOME="$PROBE/home/.cache"
export PROBE_STOPS="$PROBE/stops" CLAUDE_CODE_DISABLE_CLAUDE_MDS=1
timeout 240 /root/.local/bin/claude "${args[@]}" 'Dispatch the agent dforge:impl-haiku once with the prompt: Reply with exactly these two lines and do nothing else: "**Status:** DONE" then "Report: /nonexistent/report.md". Then say done.' > "$OUT/run.json" 2> "$OUT/run.err"
echo "claude exit $?"
cp "$PROBE/stops"/stop-*.json "$OUT/" 2>/dev/null
[ -d "$PROBE/work/.dforge" ] && cp -r "$PROBE/work/.dforge" "$OUT/state"
jq -r '"cost $\(.total_cost_usd)"' "$OUT/run.json"
rm -rf "$PROBE"
cd "$REPO" || exit 1

if [ "$MODE" = probe ] && [ -n "$NOTE" ]; then
  type=$(jq -r .agent_type "$OUT/stop-1.json")
  case $type in
    *:*) prefix="carries the plugin prefix (\`${type%%:*}:\`)" ;;
    *) prefix="carries no plugin prefix" ;;
  esac
  {
    printf '# SubagentStop input observed live\n\n'
    printf '**Run:** %s, Claude Code %s. `claude -p --model haiku --plugin-dir plugins/dforge` dispatched `dforge:impl-haiku` once; a hook given by `--settings` logged each `SubagentStop` input and blocked the first two stops with exit 2 and one stderr line.\n\n' "$(date +%F)" "$version"
    printf '**agent_type:** `%s`, which %s. The matcher `(dforge:)?impl-.*` and the gate'"'"'s own `(^|:)impl-` check both select it.\n\n' "$type" "$prefix"
    printf '**Fields of the first stop:** %s.\n\n' "$(jq -r 'keys | map("`" + . + "`") | join(", ")' "$OUT/stop-1.json")"
    printf '## Stops\n\n| Stop | stop_hook_active | last_assistant_message (first 160 characters) |\n|---|---|---|\n'
    for f in "$OUT"/stop-*.json; do
      jq -r --arg n "$(basename "$f" .json | sed 's/^stop-//')" '"| \($n) | \(.stop_hook_active) | `" + (.last_assistant_message | gsub("\n"; " / ") | gsub("[|`]"; "") | .[0:160]) + "` |"' "$f"
    done
    printf '\nExit 2 with a stderr line kept the subagent running: a block was followed by another stop of the same `agent_id`, and the line reached the agent as its next instruction. A retry'"'"'s final message is whatever the agent says after the block, so the gate'"'"'s block line asks for the full reply again, `**Status:**` line included.\n'
  } > "$NOTE"
  echo "wrote $NOTE"
fi
```

- [ ] **Step 2: Run the probe and read the observed input**

From the repository root:

```bash
rm -rf /tmp/dforge-task4-out
bash /tmp/dforge-task4-probe.sh "$PWD" /tmp/dforge-task4-out probe docs/dforge/notes/2026-10-28-subagent-stop-input.md
jq -r '[.agent_type, .stop_hook_active] | @tsv' /tmp/dforge-task4-out/stop-*.json
```

Expected: `claude exit 0`, a cost under `$0.10`, `wrote docs/dforge/notes/2026-10-28-subagent-stop-input.md`, then three lines:

```
dforge:impl-haiku	false
dforge:impl-haiku	true
dforge:impl-haiku	true
```

If the first column is not `dforge:impl-haiku`, use the observed value in the fixture (Step 3) and in the test's `the observed agent_type carries the plugin prefix` check (Step 4), and report DONE_WITH_CONCERNS naming it; the gate's own `(^|:)impl-` check accepts either form. If the run cannot authenticate or `/tmp/dforge-task4-out/stop-1.json` does not exist, report BLOCKED with the contents of `/tmp/dforge-task4-out/run.err`.

- [ ] **Step 3: Write the observed input as a fixture**

Create `plugins/dforge/tests/fixtures/subagent-stop-input.json` (long fields shortened, paths and ids replaced):

```json
{
  "session_id": "11111111-2222-4333-8444-555555555555",
  "transcript_path": "/home/user/.claude/projects/-tmp-probe-work/11111111-2222-4333-8444-555555555555.jsonl",
  "cwd": "/tmp/probe/work",
  "permission_mode": "default",
  "agent_id": "af385f8112824c5d7",
  "agent_type": "dforge:impl-haiku",
  "hook_event_name": "SubagentStop",
  "stop_hook_active": false,
  "agent_transcript_path": "/home/user/.claude/projects/-tmp-probe-work/11111111-2222-4333-8444-555555555555/subagents/agent-af385f8112824c5d7.jsonl",
  "last_assistant_message": "**Status:** DONE\nReport: /tmp/probe/reports/task-4-report.md"
}
```

- [ ] **Step 4: Write the failing test**

Create `plugins/dforge/tests/impl-stop-gate.test.sh`:

```bash
#!/usr/bin/env bash
# scripts/impl-stop-gate: the SubagentStop hook that holds an implementer's
# DONE report until its report file has the required structure. The input is
# shaped as Claude Code 2.1.311 sends it (tests/fixtures/subagent-stop-input.json).
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATE="$HERE/../scripts/impl-stop-gate"
PATHS="$HERE/../scripts/dforge-path"
HOOKS="$HERE/../hooks/hooks.json"
FIXTURE="$HERE/fixtures/subagent-stop-input.json"

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME"
unset CLAUDE_CONFIG_DIR CLAUDE_CODE_SESSION_ID AR_SESSION DFORGE_BUDGET CLAUDE_PROJECT_DIR

fjq() { MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' jq "$@"; }

REPO="$TMP/repo"
git init -q "$REPO"
STATE=$(cd "$REPO" && bash "$PATHS" state | tr -d '\r')

input() { # input <agent_type> <agent_id> <message> — the hook input, run from the repository
  fjq -nc --arg t "$1" --arg i "$2" --arg m "$3" --arg c "$REPO" \
    '{session_id:"s-1",cwd:$c,hook_event_name:"SubagentStop",stop_hook_active:false,agent_id:$i,agent_type:$t,last_assistant_message:$m}'
}
gate() { # gate <json> — sets CODE, OUT and ERR
  OUT=$(bash "$GATE" <<<"$1" 2>"$TMP/err"); CODE=$?
  ERR=$(tr -d '\r' < "$TMP/err")
}
has() { grep -cF -- "$2" <<<"$1"; }

good_report() { # good_report <file> — a report with every required section
  cat > "$1" <<'EOF'
# Report

## Summary
Did the work.

## Verified
- `bash plugins/dforge/tests/impl-stop-gate.test.sh` — pass: 30 passed, 0 failed
- `npm test -- one` — fail: 1 passed, 1 failed

## Discovered issues (not fixed)
None.

## Assumptions made
None.
EOF
}

R="$TMP/report.md"
good_report "$R"
DONE=$'**Status:** DONE\nReport: '"$R"

# --- the gate stands aside ---
gate "$(input dforge:judge-opus a-judge "$DONE")"
check "another agent type passes" "$CODE|$OUT|$ERR" "0||"
gate "$(input general-purpose a-gp $'**Status:** DONE\nReport: /nonexistent/report.md')"
check "a general-purpose agent with a missing report passes" "$CODE|$OUT|$ERR" "0||"
gate "$(input dforge:impl-sonnet-high a-b $'**Status:** BLOCKED\nReport: /nonexistent/report.md')"
check "BLOCKED passes" "$CODE|$OUT|$ERR" "0||"
gate "$(input dforge:impl-sonnet-high a-n $'**Status:** NEEDS_CONTEXT\nReport: /nonexistent/report.md')"
check "NEEDS_CONTEXT passes" "$CODE|$OUT|$ERR" "0||"
gate "$(input dforge:impl-sonnet-high a-free 'Fixed the typo in README.md and committed it.')"
check "a reply without the status contract passes" "$CODE|$OUT|$ERR" "0||"
gate '{"agent_type":"dforge:impl-haiku"'
check "malformed input passes" "$CODE|$OUT|$ERR" "0||"
gate "$(fjq -nc --arg m "$DONE" --arg c "$REPO" '{cwd:$c,agent_type:"dforge:impl-haiku",last_assistant_message:$m}')"
check "input with no agent_id passes" "$CODE|$OUT|$ERR" "0||"

# --- a complete report passes ---
gate "$(input dforge:impl-sonnet-high a-ok "$DONE")"
check "DONE with a complete report passes" "$CODE|$OUT|$ERR" "0||"
gate "$(input dforge:impl-sonnet-high a-ok $'**Status:** DONE_WITH_CONCERNS\nConcern: slow.\nReport: '"$R")"
check "DONE_WITH_CONCERNS with a complete report passes" "$CODE|$OUT|$ERR" "0||"
gate "$(input impl-opus-high a-ok "$DONE")"
check "an unprefixed agent type is checked too" "$CODE|$OUT|$ERR" "0||"
check "a passing stop writes no counter" "$([ -e "$STATE/impl-stop-gate/a-ok" ] && echo yes || echo no)" "no"
sed 's/$/\r/' "$R" > "$TMP/crlf.md"
gate "$(input dforge:impl-sonnet-high a-crlf $'**Status:** DONE\r\nReport: '"$TMP/crlf.md"$'\r')"
check "CRLF line endings pass" "$CODE|$OUT|$ERR" "0||"
gate "$(input dforge:impl-sonnet-high a-last "$(printf '**Status:** DONE\nReport: %s\nlater text\nReport: %s' "$TMP/missing.md" "$R")")"
check "the last Report line wins" "$CODE|$OUT|$ERR" "0||"

# --- each missing piece blocks and is named ---
gate "$(input dforge:impl-sonnet-high a-1 $'**Status:** DONE\nAll done.')"
check "no Report line: exit 2" "$CODE|$OUT" "2|"
check "no Report line: one stderr line naming it" "$(wc -l <<<"$ERR" | tr -d ' ')|$(has "$ERR" 'impl-stop-gate: your reply has no `Report: <absolute path>` line')" "1|1"
gate "$(input dforge:impl-sonnet-high a-2 $'**Status:** DONE\nReport: reports/task-4.md')"
check "relative Report path: exit 2 naming it" "$CODE|$(has "$ERR" 'is not absolute')" "2|1"
gate "$(input dforge:impl-sonnet-high a-3 $'**Status:** DONE\nReport: '"$TMP/missing.md")"
check "missing file: exit 2 naming it" "$CODE|$(has "$ERR" "the report file \`$TMP/missing.md\` does not exist")" "2|1"
grep -v '^## Discovered issues' "$R" > "$TMP/no-discovered.md"
gate "$(input dforge:impl-sonnet-high a-4 $'**Status:** DONE\nReport: '"$TMP/no-discovered.md")"
check "no Discovered issues heading: exit 2 naming it" "$CODE|$(has "$ERR" 'the report lacks `## Discovered issues (not fixed)`')" "2|1"
grep -v '^## Assumptions made' "$R" > "$TMP/no-assumptions.md"
gate "$(input dforge:impl-sonnet-high a-5 $'**Status:** DONE\nReport: '"$TMP/no-assumptions.md")"
check "no Assumptions heading: exit 2 naming it" "$CODE|$(has "$ERR" 'the report lacks `## Assumptions made`')" "2|1"
grep -v '^## Verified' "$R" > "$TMP/no-verified.md"
gate "$(input dforge:impl-sonnet-high a-6 $'**Status:** DONE\nReport: '"$TMP/no-verified.md")"
check "no Verified heading: exit 2 naming it" "$CODE|$(has "$ERR" 'the report lacks `## Verified`')" "2|1"
sed 's/^- `\(.*\)` — .*/- ran \1/' "$R" > "$TMP/prose-verified.md"
gate "$(input dforge:impl-sonnet-high a-7 $'**Status:** DONE\nReport: '"$TMP/prose-verified.md")"
check "Verified without a grammar bullet: exit 2 naming it" "$CODE|$(has "$ERR" '`## Verified` holds no bullet like')" "2|1"
sed 's/ — pass: .*/ - pass/; s/ — fail: .*/ - fail/' "$R" > "$TMP/hyphen-verified.md"
gate "$(input dforge:impl-sonnet-high a-8 $'**Status:** DONE\nReport: '"$TMP/hyphen-verified.md")"
check "a hyphen instead of the em dash: exit 2" "$CODE|$(has "$ERR" '`## Verified` holds no bullet like')" "2|1"
{ printf '## Verified\nnothing\n\n## Summary\n- `make test` — pass: 3 passed, 0 failed\n\n## Discovered issues (not fixed)\nNone.\n\n## Assumptions made\nNone.\n'; } > "$TMP/elsewhere.md"
gate "$(input dforge:impl-sonnet-high a-9 $'**Status:** DONE\nReport: '"$TMP/elsewhere.md")"
check "a bullet outside ## Verified does not count" "$CODE|$(has "$ERR" '`## Verified` holds no bullet like')" "2|1"
printf '# Task 4\n' > "$TMP/bare.md"
gate "$(input dforge:impl-sonnet-high a-10 $'**Status:** DONE\nReport: '"$TMP/bare.md")"
check "several gaps are named together" "$CODE|$(has "$ERR" 'lacks `## Discovered issues (not fixed)`; the report lacks `## Assumptions made`; the report lacks `## Verified`')" "2|1"

# --- the block counter ---
C="$STATE/impl-stop-gate/agent-1"
M1=$'**Status:** DONE\nFirst attempt.'
M2=$'**Status:** DONE\nSecond attempt.'
M3=$'**Status:** DONE\nThird attempt.'
M4=$'**Status:** DONE\nFourth attempt.'
gate "$(input dforge:impl-sonnet-high agent-1 "$M1")"
check "first stop blocks" "$CODE" "2"
check "the counter holds count 1" "$(sed -n 1p "$C")" "1"
H1=$(sed -n 2p "$C")
check "the counter holds a sha256" "$(grep -cE '^[0-9a-f]{64}$' <<<"$H1")" "1"
gate "$(input dforge:impl-sonnet-high agent-1 "$M1")"
check "the same stop again blocks" "$CODE" "2"
check "the same stop again does not raise the count" "$(sed -n 1p "$C")" "1"
check "a different agent id has its own counter" "$(gate "$(input dforge:impl-sonnet-high agent-2 "$M1")"; echo "$CODE|$(sed -n 1p "$STATE/impl-stop-gate/agent-2")")" "2|1"
gate "$(input dforge:impl-sonnet-high agent-1 "$M2")"
check "a second distinct stop blocks" "$CODE" "2"
check "the count is 2" "$(sed -n 1p "$C")" "2"
gate "$(input dforge:impl-sonnet-high agent-1 "$M2")"
check "the second stop fired twice still blocks" "$CODE" "2"
check "and the count stays 2" "$(sed -n 1p "$C")" "2"
check "no log before the pass-through" "$([ -e "$STATE/impl-stop-gate.log" ] && echo yes || echo no)" "no"
gate "$(input dforge:impl-sonnet-high agent-1 "$M3")"
check "the third distinct stop passes" "$CODE|$OUT|$ERR" "0||"
LOG="$STATE/impl-stop-gate.log"
check "the pass-through is logged once" "$(wc -l < "$LOG" | tr -d ' ')" "1"
check "the log line carries epoch, id, type and the last reason" \
  "$(grep -cE '^[0-9]+ agent-1 dforge:impl-sonnet-high pass-through after 2 blocks — your reply has no `Report: <absolute path>` line$' "$LOG")" "1"
gate "$(input dforge:impl-sonnet-high agent-1 "$M3")"
check "the pass-through stop fired twice passes" "$CODE|$OUT|$ERR" "0||"
gate "$(input dforge:impl-sonnet-high agent-1 "$M4")"
check "a later stop of the same agent passes" "$CODE|$OUT|$ERR" "0||"
check "and neither adds a log line" "$(wc -l < "$LOG" | tr -d ' ')" "1"
gate "$(input dforge:impl-sonnet-high agent-3 "$M1")"
gate "$(input dforge:impl-sonnet-high agent-3 "$DONE")"
check "a block followed by a complete report passes" "$CODE|$OUT|$ERR" "0||"

# --- no test runner, no network ---
STUBS="$TMP/stubs"; mkdir -p "$STUBS"
CALLS="$TMP/calls.log"; : > "$CALLS"
for tool in npm npx pnpm yarn bun pytest jest vitest mocha cargo go make mvn gradle dotnet curl wget nc ssh gh; do
  printf '#!/usr/bin/env bash\necho "%s $*" >> "%s"\nexit 0\n' "$tool" "$CALLS" > "$STUBS/$tool"
  chmod +x "$STUBS/$tool"
done
{ cat "$R"; printf '\n## Notes\n'; for i in $(seq 1 1000); do printf 'line %s of the long report\n' "$i"; done; } > "$TMP/long.md"
OUT=$(PATH="$STUBS:$PATH" bash "$GATE" <<<"$(input dforge:impl-sonnet-high a-long $'**Status:** DONE\nReport: '"$TMP/long.md")" 2>&1); CODE=$?
check "a 1,000-line complete report passes" "$CODE|$OUT" "0|"
grep -v '^## Assumptions made' "$TMP/long.md" > "$TMP/long-bad.md"
OUT=$(PATH="$STUBS:$PATH" bash "$GATE" <<<"$(input dforge:impl-sonnet-high a-long-bad $'**Status:** DONE\nReport: '"$TMP/long-bad.md")" 2>&1); CODE=$?
check "a 1,000-line incomplete report blocks" "$CODE" "2"
check "neither run invoked a test runner or a network tool" "$(wc -c < "$CALLS" | tr -d ' ')" "0"

# --- the observed SubagentStop input and the hooks.json wiring ---
check "the observed agent_type carries the plugin prefix" "$(jq -r .agent_type "$FIXTURE")" "dforge:impl-haiku"
check "the observed event name" "$(jq -r .hook_event_name "$FIXTURE")" "SubagentStop"
check "the observed input has the fields the gate reads" \
  "$(jq -r '[has("agent_id"), has("agent_type"), has("last_assistant_message"), has("cwd")] | all' "$FIXTURE")" "true"
MATCHER=$(jq -r '.hooks.SubagentStop[0].matcher' "$HOOKS")
check "hooks.json registers SubagentStop with the implementer matcher" "$MATCHER" '(dforge:)?impl-.*'
matches() { [[ $1 =~ ^($MATCHER)$ ]] && echo yes || echo no; }
check "the matcher selects the observed agent_type" "$(matches "$(jq -r .agent_type "$FIXTURE")")" "yes"
check "the matcher selects an unprefixed implementer" "$(matches impl-opus-high)" "yes"
check "the matcher leaves a judge alone" "$(matches dforge:judge-opus)" "no"
check "hooks.json runs the gate" "$(jq -r '.hooks.SubagentStop[0].hooks[0].command' "$HOOKS")" 'bash "${CLAUDE_PLUGIN_ROOT}/scripts/impl-stop-gate"'
check "the gate hook is synchronous, bash, 30 s" \
  "$(jq -r '.hooks.SubagentStop[0].hooks[0] | [.type, .async, .shell, .timeout] | map(tostring) | join(",")' "$HOOKS")" "command,false,bash,30"
check "the description mentions the gate" "$(jq -r .description "$HOOKS" | grep -c "implementer subagent's stop")" "1"
gate "$(jq -c --arg c "$REPO" '.cwd = $c' "$FIXTURE")"
check "the observed input drives the gate: it acts and finds no report" "$CODE|$(has "$ERR" 'does not exist')" "2|1"

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
```

- [ ] **Step 5: Run the test to verify it fails**

Run: `timeout 300 bash plugins/dforge/tests/impl-stop-gate.test.sh`
Expected: FAIL lines for every gate and wiring check, because `scripts/impl-stop-gate` and the `SubagentStop` entry do not exist; the last line reports `49 failed` and the exit status is 1.

- [ ] **Step 6: Write the gate**

Create `plugins/dforge/scripts/impl-stop-gate`:

```bash
#!/usr/bin/env bash
# SubagentStop hook: an implementer that reports DONE or DONE_WITH_CONCERNS
# must have written its report. Reads the hook input on stdin and blocks the
# stop (exit 2, one stderr line, which the subagent receives as its next
# instruction) when the reply has no `Report: <absolute path>` line, the file
# does not exist, it lacks `## Discovered issues (not fixed)` or
# `## Assumptions made`, or `## Verified` is missing or holds no bullet of the
# form "- `<command>` — pass|fail[: <n> passed, <m> failed]". Every other stop
# passes: other agent types, BLOCKED, NEEDS_CONTEXT, and any dispatch that
# does not use the status contract. It runs no tests and makes no network call.
#
# <state>/impl-stop-gate/<agent_id> holds the block count (line 1), the
# sha256 of the last blocked message (line 2) and "passed" once the gate has
# let a stop through (line 3). A stop whose hash equals the stored one is the
# same stop fired twice and does not raise the count. After two blocks the next
# distinct failing stop passes and appends one line to
# <state>/impl-stop-gate.log.
set -uo pipefail
export LC_ALL=C

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
command -v jq >/dev/null 2>&1 || exit 0
input=$(cat 2>/dev/null || true)
jq -e . >/dev/null 2>&1 <<<"$input" || exit 0

agent_type=$(jq -r '.agent_type // empty' <<<"$input" | tr -d '\r')
agent_id=$(jq -r '.agent_id // empty' <<<"$input" | tr -d '\r\n' | tr -c 'A-Za-z0-9._-' '-')
cwd=$(jq -r '.cwd // empty' <<<"$input" | tr -d '\r')
message=$(jq -r '.last_assistant_message // empty' <<<"$input" | tr -d '\r')

grep -qE '(^|:)impl-' <<<"$agent_type" || exit 0
grep -qE '\*\*Status:\*\* (DONE|DONE_WITH_CONCERNS)([^A-Z_]|$)' <<<"$message" || exit 0
[ -n "$agent_id" ] || exit 0

missing=()
report=$(grep -E '^Report: (.+)$' <<<"$message" | tail -n 1 | sed -E 's/^Report: //; s/[[:space:]]+$//')
if [ -z "$report" ]; then
  missing+=("your reply has no \`Report: <absolute path>\` line")
else
  case $report in
    /* | [A-Za-z]:[/\\]*) ;;
    *) missing+=("the \`Report:\` path \`$report\` is not absolute"); report="" ;;
  esac
fi
if [ -n "$report" ]; then
  file=${report//\\//}
  if command -v cygpath >/dev/null 2>&1; then file=$(cygpath -u "$file" 2>/dev/null || printf '%s' "$file"); fi
  if [ ! -f "$file" ]; then
    missing+=("the report file \`$report\` does not exist")
  else
    body=$(tr -d '\r' < "$file")
    grep -qE '^## Discovered issues \(not fixed\)[[:space:]]*$' <<<"$body" || missing+=("the report lacks \`## Discovered issues (not fixed)\`")
    grep -qE '^## Assumptions made[[:space:]]*$' <<<"$body" || missing+=("the report lacks \`## Assumptions made\`")
    if ! grep -qE '^## Verified[[:space:]]*$' <<<"$body"; then
      missing+=("the report lacks \`## Verified\`")
    else
      bullet=$(awk '
        /^## / { in_verified = ($0 ~ /^## Verified[ \t]*$/); next }
        in_verified && /^- `[^`]+` — (pass|fail)(: .*)?$/ { found = 1 }
        END { print found ? "yes" : "no" }' <<<"$body")
      [ "$bullet" = yes ] || missing+=("\`## Verified\` holds no bullet like: - \`<command>\` — pass: <n> passed, <m> failed")
    fi
  fi
fi
[ "${#missing[@]}" -gt 0 ] || exit 0

reason=""
for part in "${missing[@]}"; do reason="${reason:+$reason; }$part"; done
reason=$(printf '%s' "$reason" | cut -c1-400)

sha256() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum | cut -d' ' -f1
  elif command -v shasum >/dev/null 2>&1; then shasum -a 256 | cut -d' ' -f1
  else cksum | tr -d ' '
  fi
}
block() {
  printf 'impl-stop-gate: %s. Fix it, then end your reply again with its **Status:** line and its Report: line.\n' "$reason" >&2
  exit 2
}

cd "${cwd:-$PWD}" 2>/dev/null || exit 0
state=$(bash "$HERE/dforge-path" state 2>/dev/null | tr -d '\r') || exit 0
[ -n "$state" ] || exit 0
dir="$state/impl-stop-gate"
mkdir -p "$dir" 2>/dev/null || exit 0
counter="$dir/$agent_id"

count=0 last="" passed=""
if [ -f "$counter" ]; then
  { IFS= read -r count; IFS= read -r last; IFS= read -r passed; } < <(tr -d '\r' < "$counter")
fi
case $count in '' | *[!0-9]*) count=0 ;; esac
hash=$(printf '%s' "$message" | sha256)

[ "$passed" = passed ] && exit 0
[ "$hash" = "$last" ] && block
if [ "$count" -ge 2 ]; then
  printf '%s\n%s\npassed\n' "$count" "$last" > "$counter"
  printf '%s %s %s pass-through after 2 blocks — %s\n' "$(date +%s)" "$agent_id" "$agent_type" "$reason" >> "$state/impl-stop-gate.log"
  exit 0
fi
printf '%s\n%s\n' "$((count + 1))" "$hash" > "$counter"
block
```

- [ ] **Step 7: Register the hook**

In `plugins/dforge/hooks/hooks.json`, make two edits and leave everything else as it is.

First, extend the `description` string. Replace the end of it,

```
it holds a stop once when a turn leaves UI changes without a passing UI proof."
```

with

```
it holds a stop once when a turn leaves UI changes without a passing UI proof, and it blocks an implementer subagent's stop when its DONE report is missing or lacks its required sections."
```

Second, add the `SubagentStop` event after `Stop`. Replace the end of the file,

```
            "timeout": 60
          }
        ]
      }
    ]
  }
}
```

with

```
            "timeout": 60
          }
        ]
      }
    ],
    "SubagentStop": [
      {
        "matcher": "(dforge:)?impl-.*",
        "hooks": [
          {
            "type": "command",
            "command": "bash \"${CLAUDE_PLUGIN_ROOT}/scripts/impl-stop-gate\"",
            "shell": "bash",
            "async": false,
            "timeout": 30
          }
        ]
      }
    ]
  }
}
```

- [ ] **Step 8: Run the test to verify it passes**

Run: `timeout 300 bash plugins/dforge/tests/impl-stop-gate.test.sh`
Expected: every line `ok`, then `56 passed, 0 failed`, exit 0.

- [ ] **Step 9: Check the live wiring and the timing**

The first check loads the plugin with its own `hooks.json` (no logging hook) and dispatches an implementer whose reply names a report file that does not exist. The gate must block it, which leaves a counter file. The second check is spec A19: the gate on a complete 1,000-line report finishes in under 2 seconds.

Create `/tmp/dforge-task4-time.sh`:

```bash
#!/usr/bin/env bash
# Times the stop gate on a complete 1,000-line report. Usage: bash /tmp/dforge-task4-time.sh REPO_ROOT
set -uo pipefail
GATE="$1/plugins/dforge/scripts/impl-stop-gate"
T=$(mktemp -d)
R="$T/long.md"
{ printf '## Verified\n- `make test` — pass: 3 passed, 0 failed\n## Discovered issues (not fixed)\nNone.\n## Assumptions made\nNone.\n'; for i in $(seq 1 1000); do echo "line $i"; done; } > "$R"
jq -nc --arg m "**Status:** DONE
Report: $R" --arg c "$T" '{agent_id:"timing",agent_type:"dforge:impl-haiku",cwd:$c,last_assistant_message:$m}' > "$T/in.json"
s=$(date +%s%N)
bash "$GATE" < "$T/in.json"
echo "exit $? ms $(( ($(date +%s%N) - s) / 1000000 ))"
rm -rf "$T"
```

From the repository root:

```bash
rm -rf /tmp/dforge-task4-wired
bash /tmp/dforge-task4-probe.sh "$PWD" /tmp/dforge-task4-wired wired
for f in /tmp/dforge-task4-wired/state/impl-stop-gate/*; do head -n 1 "$f"; done
bash /tmp/dforge-task4-time.sh "$PWD"
```

Expected: `claude exit 0`; one counter line holding a number of at least `1` (the dispatch was blocked); then `exit 0 ms <N>` with `<N>` under 2000. If no counter file exists, run the wired probe once more (the model may have answered without a `**Status:** DONE` line); if there is still none, report BLOCKED with `/tmp/dforge-task4-wired/run.json`.

Record the wiring result in the note:

```bash
printf '\nWith the plugin'"'"'s own `hooks.json` loaded and no logging hook, the same dispatch left a gate counter of %s: the matcher selected the dispatch and the gate blocked it. The gate took %s ms on a complete 1,000-line report.\n' "$(cat /tmp/dforge-task4-wired/state/impl-stop-gate/* | head -n 1)" "$(bash /tmp/dforge-task4-time.sh "$PWD" | sed 's/.* ms //')" >> docs/dforge/notes/2026-10-28-subagent-stop-input.md
```

- [ ] **Step 10: Validate the plugin and the neighbouring hook tests**

Run each, bounded:

```bash
timeout 60 node scripts/validate-repository.mjs
timeout 120 /root/.local/bin/claude plugin validate plugins/dforge
timeout 300 bash plugins/dforge/tests/hook.test.sh
timeout 500 bash plugins/dforge/tests/turn-end.test.sh
timeout 300 bash plugins/dforge/tests/ui-hooks.test.sh
```

Expected: `Repository catalogs, manifests, versions, bundled links and the settings schema are valid.`; `✔ Validation passed`; and `0 failed` at the end of each test.

- [ ] **Step 11: Commit and clean up**

```bash
rm -rf /tmp/dforge-task4-out /tmp/dforge-task4-wired /tmp/dforge-task4-probe.sh /tmp/dforge-task4-time.sh
git add plugins/dforge/scripts/impl-stop-gate plugins/dforge/tests/impl-stop-gate.test.sh plugins/dforge/tests/fixtures/subagent-stop-input.json plugins/dforge/hooks/hooks.json docs/dforge/notes/2026-10-28-subagent-stop-input.md
git commit -m "feat(dforge): gate implementer stops on the report"
```

Expected: the commit succeeds, `git status --short` is empty, and no `claude` process started by the probes is still running.

### Task 5: Document unattended runs in the README

**Files:**
- Modify: `plugins/dforge/README.md` (a new section before `## Session budget`)
- Create: `plugins/dforge/tests/readme-unattended.test.sh`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: Contracts "Docs": the `## Unattended runs` section of `plugins/dforge/README.md`.

**Items:** 18

**Depends on:** none

**Implementer:** dforge:impl-sonnet-low
**Evaluation:** files 1 - spec 0 - coupling 0 - risk 0 = 1

- [ ] **Step 1: Write the failing test**

Create `plugins/dforge/tests/readme-unattended.test.sh`:

```bash
#!/usr/bin/env bash
# The README documents the two Claude Code settings an unattended parallel run
# needs, each with the reason it is needed.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
README="$HERE/../README.md"

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}

section=$(tr -d '\r' < "$README" | awk '/^## / { in_section = ($0 == "## Unattended runs"); next } in_section')
flat=$(tr -s ' \n' '  ' <<<"$section")
has() { if grep -qF -- "$1" <<<"$flat"; then echo yes; else echo no; fi; }

check "one Unattended runs heading" "$(tr -d '\r' < "$README" | grep -c '^## Unattended runs$')" "1"
check "the section has text" "$([ -n "$section" ] && echo yes || echo no)" "yes"
check "auto mode is named with its flag" "$(has '--permission-mode auto')" "yes"
check "auto mode gives its reason: a permission prompt stalls a wave implementer" "$(has 'permission prompt')" "yes"
check "worktree.baseRef is set to head in a settings snippet" "$(has '{ "worktree": { "baseRef": "head" } }')" "yes"
check "baseRef gives its reason: the default branches from origin" "$(has 'origin/<default-branch>')" "yes"
check "baseRef gives its reason: unpushed local commits are missing from the worktree" "$(has 'unpushed')" "yes"
check "dforge's own auto run is told apart from auto mode" "$(has 'reference/auto-run.md')" "yes"
check "the section sits before Session budget" \
  "$(tr -d '\r' < "$README" | awk '/^## Unattended runs$/ { a = NR } /^## Session budget$/ { b = NR } END { print (a > 0 && a < b) ? "yes" : "no" }')" "yes"

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `timeout 60 bash plugins/dforge/tests/readme-unattended.test.sh`
Expected: nine `FAIL` lines and `0 passed, 9 failed`, exit 1.

- [ ] **Step 3: Write the section**

In `plugins/dforge/README.md`, use the Edit tool with this `old_string`, which is unique (the heading and the first words of its paragraph):

```
## Session budget

Long sessions cost more than they look
```

and this `new_string`, which inserts the new section before them:

````markdown
## Unattended runs

Two Claude Code settings keep a parallel plan moving while nobody is at the
keyboard. They belong to Claude Code, and dforge neither sets nor reads them.

**Auto mode.** Start the session with `claude --permission-mode auto`. A wave
runs its implementers as subagents, several at once, and a tool call that needs
a permission prompt makes that implementer wait for an answer you are not there
to give, which holds up the whole wave. In auto mode a classifier approves
routine calls and blocks risky ones, so no implementer stops on a prompt. This is Claude Code's permission mode; dforge's
own auto run (see [reference/auto-run.md](reference/auto-run.md)) keeps a plan
going from approval to finishing and works under any permission mode.

**Wave worktrees from your local HEAD.** Set `worktree.baseRef` to `"head"` in
your user settings (`~/.claude/settings.json`):

```json
{ "worktree": { "baseRef": "head" } }
```

Claude Code creates each wave implementer's worktree itself. Its default,
`"fresh"`, branches from `origin/<default-branch>`, so when your local main is
ahead of origin, or the plan sits on a feature branch, the worktree lacks the
unpushed commits: the plan and the earlier waves' merged tasks. dforge's
dispatch detaches the implementer to the wave's base afterwards, but a worktree
that starts from your HEAD begins in the right place. The setting applies to
every worktree Claude Code creates for you, not only dforge's.

## Session budget

Long sessions cost more than they look
````

- [ ] **Step 4: Run the test to verify it passes**

Run: `timeout 60 bash plugins/dforge/tests/readme-unattended.test.sh`
Expected: nine `ok` lines, then `9 passed, 0 failed`, exit 0.

- [ ] **Step 5: Validate the repository**

Run: `timeout 60 node scripts/validate-repository.mjs`
Expected: `Repository catalogs, manifests, versions, bundled links and the settings schema are valid.`

- [ ] **Step 6: Commit**

```bash
git add plugins/dforge/README.md plugins/dforge/tests/readme-unattended.test.sh
git commit -m "docs(dforge): document unattended runs"
```

Expected: the commit succeeds and `git status --short` is empty.

### Task 6: Record the prompt audit

**Files:**
- Create: `docs/dforge/notes/2026-10-27-prompt-audit.md`
- Modify: `docs/dforge/registers/2026-10-27-speed-and-cost.md` (one deferred row per proposal, written by `scripts/register add`, never by hand)

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: Contracts "Docs": the prompt-audit note, and a register row for each change it proposes.

**Items:** 16

**Depends on:** none

**Implementer:** dforge:impl-sonnet-low
**Evaluation:** files 1 - spec 1 - coupling 0 - risk 0 = 2

The audit proposes; nothing in `plugins/dforge/` is edited here. `disable-model-invocation` is not a candidate: dforge skills invoke each other through the Skill tool (spec ruling of 2026-10-28). Both commands run headless in Claude Code 2.1.311: `/skill-doctor` reported a cost of $0 on a dry run, and `/doctor prompt-audit` took about 150 seconds and under $1. It audits a project's `.claude/` files and proposes edits for them, and proposes none for an installed plugin's files, so the run copies dforge's prompt files into a temporary project laid out as `.claude/skills`, `agents`, `reference` and `criteria`, which keeps the relative links between them intact.

- [ ] **Step 1: Write the run script**

Both commands authenticate through the session's `CLAUDE_CONFIG_DIR`, as in Task 4's probe, with `--setting-sources project`, `CLAUDE_CODE_DISABLE_CLAUDE_MDS=1` and `--no-session-persistence`. `/skill-doctor` reads the usage history of that config directory, which is what its report is made of, and writes nothing. The audit runs with a temporary `HOME`, read-only tools (`Read`, `Glob`, `Grep`) and a request that keeps it inside the temporary project, so none of the owner's `~/.claude` files is read or quoted. The spend cap is $10.

Create `/tmp/dforge-task6-run.sh`:

```bash
#!/usr/bin/env bash
# Runs /skill-doctor and /doctor prompt-audit headless for dforge.
# Usage: bash dforge-task6-run.sh REPO_ROOT WORK_DIR   (WORK_DIR must not exist yet)
set -uo pipefail
REPO=$1 W=$2
[ -n "${CLAUDE_CONFIG_DIR:-}" ] || { echo "CLAUDE_CONFIG_DIR is unset: this session's login lives there"; exit 2; }
[ ! -e "$W" ] || { echo "$W exists"; exit 2; }
mkdir -p "$W/project/.claude" "$W/empty" "$W/home"
for d in skills agents reference criteria; do cp -r "$REPO/plugins/dforge/$d" "$W/project/.claude/$d"; done
export CLAUDE_CODE_DISABLE_CLAUDE_MDS=1

cd "$W/empty" || exit 1
timeout 120 /root/.local/bin/claude -p --model haiku --setting-sources project --plugin-dir "$REPO/plugins/dforge" --max-budget-usd 1 --output-format json --no-session-persistence '/skill-doctor' > "$W/skill-doctor.json" 2> "$W/skill-doctor.err"
echo "skill-doctor exit $?"

cd "$W/project" || exit 1
export HOME="$W/home" XDG_CONFIG_HOME="$W/home/.config" XDG_DATA_HOME="$W/home/.local/share" XDG_CACHE_HOME="$W/home/.cache"
timeout 1500 /root/.local/bin/claude -p --model sonnet --setting-sources project --allowedTools Read,Glob,Grep --max-budget-usd 10 --output-format json --no-session-persistence "/doctor prompt-audit Audit only the files under this project's .claude directory. Do not read, quote or report on anything under ~/.claude or any other directory outside the project, and do not list installed plugins." > "$W/audit.json" 2> "$W/audit.err"
echo "prompt-audit exit $?"

for f in skill-doctor audit; do
  jq -r --arg f "$f" '"\($f): is_error=\(.is_error) cost=$\(.total_cost_usd) result_chars=\(.result | length)"' "$W/$f.json" 2>/dev/null || echo "$f: no JSON output"
done
```

- [ ] **Step 2: Run both commands**

From the repository root, as a background command (the audit takes a few minutes), and wait for its completion notification:

```bash
bash /tmp/dforge-task6-run.sh "$PWD" /tmp/dforge-task6-work
```

Expected output:

```
skill-doctor exit 0
prompt-audit exit 0
skill-doctor: is_error=false cost=$0 result_chars=<N>
audit: is_error=false cost=$<under 10> result_chars=<N>
```

If either command exits non-zero, reports `is_error=true` or returns an empty result, stop and report BLOCKED. Name the failing command and its `/tmp/dforge-task6-work/<skill-doctor|audit>.err` file, and say the owner must run `/doctor prompt-audit` and `/skill-doctor` once in a session of their own (spec A17 allows this); the controller then re-dispatches this task with that output.

- [ ] **Step 3: Choose the proposals**

Read the two results: `jq -r .result /tmp/dforge-task6-work/audit.json` and `jq -r .result /tmp/dforge-task6-work/skill-doctor.json`. A proposal is:

- a finding of the audit that names a dforge file (a path under `.claude/skills`, `agents`, `reference` or `criteria` in the audit's text; its dforge path is the same path under `plugins/dforge/`) and whose action is anything but `flag`; or
- an explicit recommendation printed by `/skill-doctor`, if its output holds one (it normally prints a usage table and no advice, so this is often empty).

Findings marked `flag`, and findings about files outside dforge, stay in the note and get no row. Write one line per proposal to `/tmp/dforge-task6-work/proposals.txt`: a sentence of at most 200 characters that names the change and the `plugins/dforge/...` path, with no `|`, tab or backtick. For example, a dry run of this audit produced the line `Rewrite the gratitude ban in plugins/dforge/skills/receiving-code-review/SKILL.md so it states its reason`; write the lines your own run supports. When the run proposes nothing, create the file empty with `: > /tmp/dforge-task6-work/proposals.txt`.

- [ ] **Step 4: Write the note and the register rows**

Create `/tmp/dforge-task6-record.sh`:

```bash
#!/usr/bin/env bash
# Writes the prompt-audit note and one deferred register row per proposal.
# Usage: bash dforge-task6-record.sh REPO_ROOT WORK_DIR
# WORK_DIR holds audit.json and skill-doctor.json (claude -p --output-format json) and proposals.txt (one proposal per line, may be empty).
set -uo pipefail
REPO=$1 W=$2
NOTE="$REPO/docs/dforge/notes/2026-10-27-prompt-audit.md"
REG="$REPO/docs/dforge/registers/2026-10-27-speed-and-cost.md"
REGISTER="$REPO/plugins/dforge/scripts/register"
version=$(/root/.local/bin/claude --version | cut -d' ' -f1)
{
  cat <<'HEAD'
# dforge prompt audit

HEAD
  printf '**Run:** %s, Claude Code %s.\n\n' "$(date +%F)" "$version"
  cat <<'SCOPE'
**Scope:** `/doctor prompt-audit` ran on `--model sonnet` over a copy of `plugins/dforge/skills`, `agents`, `reference` and `criteria`, laid out as a project's `.claude/` directory, because the audit proposes edits for a project's own files and none for an installed plugin's. The request kept it inside that directory, so nothing of the owner's `~/.claude` is read or quoted. `/skill-doctor` reads the usage history of the owner's Claude config directory and makes no model call.

**Ruling:** `disable-model-invocation` is not proposed. dforge skills invoke each other through the Skill tool, so no dforge skill qualifies (spec ruling of 2026-10-28).

**Method:** nothing was edited. A proposal below is a finding of the audit that names a dforge file and whose action is not `flag`, or an explicit recommendation in the `/skill-doctor` output; each one is a deferred register row.

## /doctor prompt-audit

~~~~markdown
SCOPE
  jq -r '.result' "$W/audit.json" | tr -d '\r'
  printf '~~~~\n\n## /skill-doctor\n\n~~~~text\n'
  jq -r '.result' "$W/skill-doctor.json" | tr -d '\r'
  printf '~~~~\n\n## Proposed changes\n\n'
  n=0
  while IFS= read -r line || [ -n "$line" ]; do
    [ -n "$line" ] || continue
    n=$((n + 1))
    printf -- '- P%s: %s\n' "$n" "$line"
  done < "$W/proposals.txt"
  [ "$n" -gt 0 ] || printf 'None: the audit proposed no change to a dforge file.\n'
} > "$NOTE"
while IFS= read -r line || [ -n "$line" ]; do
  [ -n "$line" ] || continue
  bash "$REGISTER" add "$REG" "$line" --state deferred --note "Proposed by the prompt audit (docs/dforge/notes/2026-10-27-prompt-audit.md); not applied by this plan" || exit 1
done < "$W/proposals.txt"
echo "note: $(wc -l < "$NOTE" | tr -d ' ') lines; proposals: $(grep -c '' "$W/proposals.txt")"
```

Run from the repository root:

```bash
bash /tmp/dforge-task6-record.sh "$PWD" /tmp/dforge-task6-work
```

Expected: `note: <N> lines; proposals: <K>`, with `<K>` equal to the number of lines in `proposals.txt`, and one `register add` per line, each exiting 0.

- [ ] **Step 5: Check the note and the register agree**

Create `/tmp/dforge-task6-check.sh`:

```bash
#!/usr/bin/env bash
# Usage: bash dforge-task6-check.sh REPO_ROOT
set -uo pipefail
REPO=$1
NOTE="$REPO/docs/dforge/notes/2026-10-27-prompt-audit.md"
REG="$REPO/docs/dforge/registers/2026-10-27-speed-and-cost.md"
fail=0
bad() { printf 'FAIL: %s\n' "$1"; fail=1; }
[ "$(grep -c '^## /doctor prompt-audit$' "$NOTE")" = 1 ] || bad "the note needs exactly one '## /doctor prompt-audit' heading"
[ "$(grep -c '^## /skill-doctor$' "$NOTE")" = 1 ] || bad "the note needs exactly one '## /skill-doctor' heading"
grep -q '^## Proposed changes$' "$NOTE" || bad "the note needs a '## Proposed changes' heading"
proposals=$(awk '/^## Proposed changes$/ { p = 1; next } p && /^- P[0-9]+: / { sub(/^- P[0-9]+: /, ""); print }' "$NOTE")
count=0
while IFS= read -r text; do
  [ -n "$text" ] || continue
  count=$((count + 1))
  [ "$(grep -cF -- "| $text | - |" "$REG")" = 1 ] || bad "no single register row for: $text"
done <<<"$proposals"
rows=$(grep -cF 'Proposed by the prompt audit (docs/dforge/notes/2026-10-27-prompt-audit.md)' "$REG")
[ "$rows" = "$count" ] || bad "$count proposals in the note, $rows audit rows in the register"
bash "$REPO/plugins/dforge/scripts/register" check "$REG" || bad "register check failed"
if [ "$fail" = 0 ]; then printf 'ok: %s proposals, %s register rows, note and register agree\n' "$count" "$rows"; fi
exit "$fail"
```

Run from the repository root: `bash /tmp/dforge-task6-check.sh "$PWD"`
Expected: `register: 0 errors`, then `ok: <K> proposals, <K> register rows, note and register agree`, exit 0.

- [ ] **Step 6: Commit and clean up**

```bash
git status --short
```

Expected: exactly the new note (`??`) and the modified register (` M`), and nothing under `plugins/`.

```bash
rm -rf /tmp/dforge-task6-work /tmp/dforge-task6-run.sh /tmp/dforge-task6-record.sh /tmp/dforge-task6-check.sh
git add docs/dforge/notes/2026-10-27-prompt-audit.md docs/dforge/registers/2026-10-27-speed-and-cost.md
git commit -m "docs(dforge): record the prompt audit"
```

Expected: the commit succeeds, `git status --short` is empty, and no `claude` process started by the run is still running.

### Task 7: Split brainstorming and writing-plans SKILL.md

**Files:**
- Modify: `plugins/dforge/skills/brainstorming/SKILL.md` (41,650 bytes now, 17,700 after)
- Modify: `plugins/dforge/skills/writing-plans/SKILL.md` (35,366 bytes now, 18,623 after)
- Create: `plugins/dforge/skills/brainstorming/references/process-flow.md`
- Create: `plugins/dforge/skills/brainstorming/references/design-phase.md`
- Create: `plugins/dforge/skills/brainstorming/references/auto-by-default.md`
- Create: `plugins/dforge/skills/brainstorming/references/drafting-acceptance.md`
- Create: `plugins/dforge/skills/brainstorming/references/auto-run-offer.md`
- Create: `plugins/dforge/skills/brainstorming/references/spec-document.md`
- Create: `plugins/dforge/skills/brainstorming/references/spec-self-review.md`
- Create: `plugins/dforge/skills/brainstorming/references/architecture-critic.md`
- Create: `plugins/dforge/skills/brainstorming/references/user-review-gate.md`
- Create: `plugins/dforge/skills/writing-plans/references/auto-run-plan.md`
- Create: `plugins/dforge/skills/writing-plans/references/execution-line.md`
- Create: `plugins/dforge/skills/writing-plans/references/assignment-procedure.md`
- Create: `plugins/dforge/skills/writing-plans/references/register-rows.md`
- Create: `plugins/dforge/skills/writing-plans/references/lint-and-review.md`
- Create: `plugins/dforge/skills/writing-plans/references/execution-handoff.md`
- Test: `plugins/dforge/tests/skill-split-planning.test.sh` (new)
- Modify: `plugins/dforge/tests/auto-default.test.sh`
- Modify: `plugins/dforge/tests/process-roles.test.sh`
- Modify: `plugins/dforge/tests/review-route.test.sh`
- Modify: `plugins/dforge/tests/settings-skills.test.sh`
- Modify: `plugins/dforge/tests/project-status.test.sh`
- Modify: `plugins/dforge/tests/inline-mode.test.sh`
- Modify: `plugins/dforge/tests/seats.test.sh`
- Modify: `plugins/dforge/tests/parallel-grouping.test.sh`
- Modify: `plugins/dforge/tests/review-depth.acceptance.test.sh`
- Modify: `plugins/dforge/tests/review-depth-qa.acceptance.test.sh`
- Modify: `plugins/dforge/tests/faster-plans.acceptance.test.sh`

**Interfaces:**
- Consumes: Contracts "Skill references" (the reference layout, the `Read [<topic>.md](references/<topic>.md) before you <action>.` line, and the rule that a pin test is repointed and no pin assertion is deleted).
- Produces: Contracts "Skill references" for these two skills: fifteen references, each linked from its SKILL.md heading by such a line; `brainstorming/SKILL.md` at 17,700 bytes and `writing-plans/SKILL.md` at 18,623, both under the 20,000-byte cap that Task 10's size test enforces.

**Items:** 14

**Depends on:** Task 2

**Implementer:** dforge:impl-sonnet-high
**Evaluation:** files 2 - spec 0 - coupling 1 - risk 2 = 5

**What moves.** Each moved section keeps its heading in SKILL.md, followed by one `Read … before you …` line, so every cross-reference by section name still lands on a heading. The reference file starts with the section's original heading line and holds the section's text unchanged, except that relative links gain one `../` for the extra directory (`](../../reference/` becomes `](../../../reference/`, `](references/` becomes `](`). Stays in SKILL.md: frontmatter, Three Paths, Settings, Red Flags, the Checklist, the "Terminal states" paragraph, The Process up to "Exploring approaches" plus "Understanding the idea", "Opening an item register" and "Self-reviewing a bounded design", and Implementation in brainstorming; Overview, Scope Check, File Structure, Task Right-Sizing, the Plan Document Header template and the Codex paragraph, Parallel waves, Drafting the tasks, Task Structure, No Placeholders and Self-Review in writing-plans. Parallel waves stays whole because `task-step-text.test.sh` pins its rule 7 and a task of this wave does not touch that file.

The two splits are done by a throwaway script that cuts each section by its exact heading line, so no moved text is retyped. The script and its inputs live in `/tmp/speed-cost-task7` and are deleted in the last step.

- [ ] **Step 1: Write the test and see it fail**

Create `plugins/dforge/tests/skill-split-planning.test.sh`:

```bash
#!/usr/bin/env bash
# brainstorming and writing-plans keep each moved section reachable: a
# reference file, a "Read ... before you ..." line at the step that needs it,
# links that still resolve, and a SKILL.md under the 20,000-byte cap.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
P="$HERE/.."

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}

broken_links() { # broken_links <markdown file>: relative link targets that do not exist
  local file=$1 dir target out=""
  dir=$(dirname "$file")
  for target in $(tr -d '\r' < "$file" | grep -o '](\([^)#]*\)' | sed 's/^](//'); do
    case "$target" in ''|http*|*'<'*|*'['*) continue ;; esac
    [ -e "$dir/$target" ] || out="$out $target"
  done
  printf '%s' "$out"
}

MOVED="
brainstorming:process-flow
brainstorming:design-phase
brainstorming:auto-by-default
brainstorming:drafting-acceptance
brainstorming:auto-run-offer
brainstorming:spec-document
brainstorming:spec-self-review
brainstorming:architecture-critic
brainstorming:user-review-gate
writing-plans:auto-run-plan
writing-plans:execution-line
writing-plans:assignment-procedure
writing-plans:register-rows
writing-plans:lint-and-review
writing-plans:execution-handoff
"

for entry in $MOVED; do
  skill=${entry%%:*}
  topic=${entry#*:}
  doc="$P/skills/$skill/SKILL.md"
  ref="$P/skills/$skill/references/$topic.md"
  check "$skill: $topic.md exists" "$([ -s "$ref" ] && echo yes || echo no)" "yes"
  check "$skill: SKILL.md links $topic.md once" "$(tr -d '\r' < "$doc" | grep -c "^Read \[$topic\.md\](references/$topic\.md) before you .*\.$")" "1"
  check "$skill: $topic.md has no broken link" "$(broken_links "$ref")" ""
done

for skill in brainstorming writing-plans; do
  doc="$P/skills/$skill/SKILL.md"
  check "$skill: SKILL.md has no broken link" "$(broken_links "$doc")" ""
  bytes=$(wc -c < "$doc" | tr -d ' ')
  check "$skill: SKILL.md is at most 20000 bytes" "$([ "$bytes" -le 20000 ] && echo yes || echo "no ($bytes)")" "yes"
done

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
```

- [ ] **Step 2: Run it to verify it fails**

Run: `timeout 60 bash plugins/dforge/tests/skill-split-planning.test.sh`
Expected: FAIL, with the lines `FAIL - brainstorming: process-flow.md exists` through `writing-plans: execution-handoff.md exists`, the fifteen missing `Read [...]` links, and `brainstorming: SKILL.md is at most 20000 bytes` reporting `no (41650)` (and `no (35366)` for writing-plans). Exit status 1.

- [ ] **Step 3: Write the splitting tools**

Create the directory with `mkdir -p /tmp/speed-cost-task7`, then create these five files in it.

`/tmp/speed-cost-task7/split-skill.mjs`:

```js
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { join } from 'node:path';

const [skillDir, movesFile] = process.argv.slice(2);
const skillPath = join(skillDir, 'SKILL.md');
const lines = readFileSync(skillPath, 'utf8').replace(/\r/g, '').split('\n');
const moves = JSON.parse(readFileSync(movesFile, 'utf8'));

const indexOfLine = (text, from = 0) => {
  const hits = [];
  for (let i = from; i < lines.length; i++) if (lines[i] === text) hits.push(i);
  if (hits.length !== 1) throw new Error(`expected exactly one line ${JSON.stringify(text)} from ${from}, found ${hits.length}`);
  return hits[0];
};

const plan = moves.map((m) => {
  const start = indexOfLine(m.start);
  const end = m.end === 'EOF' ? lines.length : indexOfLine(m.end, start + 1);
  return { ...m, s: start, e: end };
});

plan.sort((a, b) => a.s - b.s);
for (let i = 1; i < plan.length; i++) {
  if (plan[i].s < plan[i - 1].e) throw new Error(`overlap between ${plan[i - 1].topic} and ${plan[i].topic}`);
}

const trim = (arr) => {
  let a = 0;
  let b = arr.length;
  while (a < b && arr[a].trim() === '') a++;
  while (b > a && arr[b - 1].trim() === '') b--;
  return arr.slice(a, b);
};
const fixLinks = (text) => text.replace(/\]\(\.\.\/\.\.\//g, '](../../../').replace(/\]\(references\//g, '](');

mkdirSync(join(skillDir, 'references'), { recursive: true });
const out = [];
let cursor = 0;
for (const m of plan) {
  out.push(...lines.slice(cursor, m.s));
  const body = trim(lines.slice(m.s, m.e)).map(fixLinks);
  writeFileSync(join(skillDir, 'references', `${m.topic}.md`), `${body.join('\n')}\n`);
  out.push(m.keepHeading ? lines[m.s] : m.stubHeading, '', `Read [${m.topic}.md](references/${m.topic}.md) before you ${m.action}.`, '');
  cursor = m.e;
}
out.push(...lines.slice(cursor));
writeFileSync(skillPath, out.join('\n'));
```

`/tmp/speed-cost-task7/brainstorming-moves.json`:

```json
[
  {"topic": "process-flow", "start": "## Process Flow", "end": "**Terminal states are path-bound.** Architectural: the ONLY skill you", "keepHeading": true, "action": "change the order of the spec phase or the path a request takes through it"},
  {"topic": "design-phase", "start": "**Exploring approaches:**", "end": "## Auto by default (`autoRun=on`)", "keepHeading": false, "stubHeading": "**Exploring approaches, choosing the execution strategy, presenting the design:**", "action": "propose approaches, ask the execution strategy or present the design"},
  {"topic": "auto-by-default", "start": "## Auto by default (`autoRun=on`)", "end": "## After the Design (architectural path)", "keepHeading": true, "action": "write the spec under `autoRun=on`"},
  {"topic": "drafting-acceptance", "start": "**Drafting acceptance:**", "end": "**Offering an auto run:**", "keepHeading": true, "action": "draft the spec's acceptance statements"},
  {"topic": "auto-run-offer", "start": "**Offering an auto run:**", "end": "**Documentation:**", "keepHeading": true, "action": "offer an auto run"},
  {"topic": "spec-document", "start": "**Documentation:**", "end": "**Spec Self-Review:**", "keepHeading": true, "action": "write the spec document"},
  {"topic": "spec-self-review", "start": "**Spec Self-Review:**", "end": "**Architecture critic:**", "keepHeading": true, "action": "self-review the written spec"},
  {"topic": "architecture-critic", "start": "**Architecture critic:**", "end": "**User Review Gate:**", "keepHeading": true, "action": "run the architecture critic or Fable's spec review"},
  {"topic": "user-review-gate", "start": "**User Review Gate:**", "end": "**Implementation:**", "keepHeading": true, "action": "ask your human partner to review the written spec"}
]
```

`/tmp/speed-cost-task7/writing-plans-moves.json`:

```json
[
  {"topic": "auto-run-plan", "start": "## Auto run", "end": "## Scope Check", "keepHeading": true, "action": "write this plan when `scripts/auto-run status` exits 0"},
  {"topic": "execution-line", "start": "**Read the settings first.** Two workflow settings shape a plan,", "end": "## Parallel waves", "keepHeading": false, "stubHeading": "**Read the settings first, then choose the Execution line.**", "action": "write the header's Execution line"},
  {"topic": "assignment-procedure", "start": "## Assign an implementer to every task", "end": "## Assign the register rows", "keepHeading": true, "action": "score the tasks or write their assignment lines"},
  {"topic": "register-rows", "start": "## Assign the register rows", "end": "## No Placeholders", "keepHeading": true, "action": "tie register rows to the plan's tasks"},
  {"topic": "lint-and-review", "start": "## Lint and Review", "end": "## Execution Handoff", "keepHeading": true, "action": "lint the plan or dispatch a plan review round"},
  {"topic": "execution-handoff", "start": "## Execution Handoff", "end": "EOF", "keepHeading": true, "action": "end the planning session"}
]
```

`/tmp/speed-cost-task7/repoint-pins.mjs` rewrites, in one test file, each positive pin (`names`, `says`, `present`, ...) whose file argument is a brainstorming or writing-plans `SKILL.md` and whose quoted text now lives in a moved reference, so that it names that reference file instead. Negative pins (`lacks`, `absent`) are left as they are. It prints how many pins it repointed and lists any it could not resolve.

```js
import { readFileSync, writeFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';

const [testFile, pluginDir, ...moveFiles] = process.argv.slice(2);
const moved = new Set(moveFiles.flatMap((f) => JSON.parse(readFileSync(f, 'utf8')).map((m) => `${m.topic}.md`)));
const skills = ['brainstorming', 'writing-plans'];
const flat = (s) => s.replace(/\n/g, ' ').replace(/ +/g, ' ');
const docs = {};
for (const skill of skills) {
  const dir = join(pluginDir, 'skills', skill);
  docs[skill] = { skill: readFileSync(join(dir, 'SKILL.md'), 'utf8'), refs: {} };
  for (const name of readdirSync(join(dir, 'references')).filter((f) => moved.has(f))) docs[skill].refs[name] = readFileSync(join(dir, 'references', name), 'utf8');
}

// One bash word made of single-quoted, double-quoted and bare parts, evaluated without running anything.
function word(src) {
  let out = '';
  let i = 0;
  while (i < src.length) {
    const c = src[i];
    if (c === "'") {
      const j = src.indexOf("'", i + 1);
      if (j < 0) return null;
      out += src.slice(i + 1, j);
      i = j + 1;
    } else if (c === '"') {
      i++;
      while (i < src.length && src[i] !== '"') {
        if (src[i] === '\\' && '"\\$`'.includes(src[i + 1])) { out += src[i + 1]; i += 2; } else if (src[i] === '$' || src[i] === '`') return null; else out += src[i++];
      }
      if (src[i] !== '"') return null;
      i++;
    } else if (/\s/.test(c)) return null;
    else { out += c; i++; }
  }
  return out;
}

const negative = /^(lacks|absent|not_present|missing|never)/;
const lines = readFileSync(testFile, 'utf8').split('\n');
const vars = {};
const consts = {};
const assign = /^\s*(\w+)=("[^"]*skills\/(brainstorming|writing-plans)\/SKILL\.md")\s*$/;
let changed = 0;
const unresolved = [];
const out = lines.map((line, n) => {
  let tail = '';
  for (let k = n; lines[k].endsWith(' \\'); k++) tail += ` ${lines[k + 1].trim()}`;
  const c = line.match(/^(\w+)='([^']*)'$/);
  if (c) consts[c[1]] = c[2];
  const a = line.match(assign);
  if (a) { vars[a[1]] = { def: a[2], skill: a[3] }; return line; }
  const m = line.match(/^(\s*)(\w+) ("(?:[^"\\]|\\.)*") ("\$\{?(\w+)\}?"|"[^"]*skills\/(?:brainstorming|writing-plans)\/SKILL\.md") (.+)$/);
  if (!m) return line;
  const [, indent, fn, label, fileArg, varName, rest] = m;
  const v = varName ? vars[varName] : { def: fileArg, skill: skills.find((s) => fileArg.includes(`/${s}/`)) };
  if (!v || negative.test(fn)) return line;
  const joined = `${rest.replace(/\s*\\$/, '')}${tail}`.trim();
  const ref = joined.match(/^"\$(\w+)"$/);
  const needle = ref ? consts[ref[1]] ?? null : word(joined);
  if (needle === null) { unresolved.push(`${n + 1}: ${line.trim().slice(0, 100)}`); return line; }
  const d = docs[v.skill];
  const holds = (t) => t.includes(needle) || (fn === 'says' && flat(t).includes(flat(needle)));
  if (holds(d.skill)) return line;
  const hits = Object.entries(d.refs).filter(([, t]) => holds(t)).map(([f]) => f);
  if (hits.length === 0) { unresolved.push(`${n + 1}: no reference file holds it: ${line.trim().slice(0, 100)}`); return line; }
  hits.sort();
  changed++;
  return `${indent}${fn} ${label} ${v.def.replace('SKILL.md', `references/${hits[0]}`)} ${rest}`;
});
writeFileSync(testFile, out.join('\n'));
console.log(`${testFile}: repointed ${changed}, unresolved ${unresolved.length}`);
for (const u of unresolved) console.log(`  ${u}`);
```

`/tmp/speed-cost-task7/edit-tests.mjs` makes the edits that the script above cannot: three tests read a whole skill through a `doc`, `flat` or `sect` helper, so they gain a helper that reads the skill together with its references, and the section extractions point at the reference that now holds the section. Each edit states how many times its `from` text must occur and the script stops when the count differs.

```js
import { readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

const tests = process.argv[2];
const SKILL_DOC = `skill_doc() { # skill_doc <SKILL.md> — the skill and its references as one line, whitespace collapsed
  { doc "$1"; for ref in "$(dirname "$1")"/references/*.md; do doc "$ref"; done; }
}`;
const DOC = `doc() { tr -d '\\r' < "$1" | tr '\\n' ' ' | tr -s ' '; } # a file as one line, whitespace collapsed`;
const FLAT = `flat() { tr '\\n' ' ' < "$1" | tr -s ' '; }`;
const FLAT_SKILL = `flat_skill() { cat "$1" "$(dirname "$1")"/references/*.md | tr '\\n' ' ' | tr -s ' '; } # a skill and its references as one line`;

// [file, from, to, occurrences]
const edits = [
  ['review-depth.acceptance.test.sh', DOC, `${DOC}\n${SKILL_DOC}`, 1],
  ['review-depth.acceptance.test.sh', 'doc "$BS"', 'skill_doc "$BS"', 4],
  ['review-depth.acceptance.test.sh', 'doc "$WP"', 'skill_doc "$WP"', 1],
  ['faster-plans.acceptance.test.sh', DOC, `${DOC}\n${SKILL_DOC}`, 1],
  ['faster-plans.acceptance.test.sh', 'doc "$PLUGIN/skills/writing-plans/SKILL.md"', 'skill_doc "$PLUGIN/skills/writing-plans/SKILL.md"', 3],
  ['faster-plans.acceptance.test.sh', 'doc "$PLUGIN/skills/brainstorming/SKILL.md"', 'skill_doc "$PLUGIN/skills/brainstorming/SKILL.md"', 1],
  ['review-depth-qa.acceptance.test.sh', FLAT, `${FLAT}\n${FLAT_SKILL}`, 1],
  ['review-depth-qa.acceptance.test.sh', 'WP="$PLUGIN/skills/writing-plans/SKILL.md"', 'WP="$PLUGIN/skills/writing-plans/SKILL.md"\nBRR="$PLUGIN/skills/brainstorming/references"\nWPR="$PLUGIN/skills/writing-plans/references"', 1],
  ['review-depth-qa.acceptance.test.sh', 'B=$(flat "$BR")', 'B=$(flat_skill "$BR")', 1],
  ['review-depth-qa.acceptance.test.sh', `sect "$BR" '^\\*\\*Architecture critic:\\*\\*'`, `sect "$BRR/architecture-critic.md" '^\\*\\*Architecture critic:\\*\\*'`, 1],
  ['review-depth-qa.acceptance.test.sh', `sect "$BR" '^\\*\\*User Review Gate:\\*\\*'`, `sect "$BRR/user-review-gate.md" '^\\*\\*User Review Gate:\\*\\*'`, 1],
  ['review-depth-qa.acceptance.test.sh', 'W=$(flat "$WP"); WH=$(sect "$WP" ', 'W=$(flat_skill "$WP"); WH=$(sect "$WPR/execution-handoff.md" ', 1],
  ['review-depth-qa.acceptance.test.sh', `WR=$(sect "$WP" '^4\\. `, `WR=$(sect "$WPR/lint-and-review.md" '^4\\. `, 1],
  ['review-depth-qa.acceptance.test.sh', 'BT=$(flat "$BR")', 'BT=$(flat_skill "$BR")', 2],
];

for (const [name, from, to, count] of edits) {
  const file = join(tests, name);
  const text = readFileSync(file, 'utf8');
  const found = text.split(from).length - 1;
  if (found !== count) throw new Error(`${name}: expected ${count} of ${JSON.stringify(from)}, found ${found}`);
  writeFileSync(file, text.split(from).join(to));
}
console.log(`${edits.length} edits applied`);
```

- [ ] **Step 4: Split the two skills**

Run, from the repository root:

```bash
node /tmp/speed-cost-task7/split-skill.mjs plugins/dforge/skills/brainstorming /tmp/speed-cost-task7/brainstorming-moves.json
node /tmp/speed-cost-task7/split-skill.mjs plugins/dforge/skills/writing-plans /tmp/speed-cost-task7/writing-plans-moves.json
wc -c plugins/dforge/skills/brainstorming/SKILL.md plugins/dforge/skills/writing-plans/SKILL.md
```

Expected: no error; `wc -c` prints `17700` and `18623`. If the script stops with `expected exactly one line`, a heading was reworded by an earlier task: find the heading in the file and change the `start` or `end` string in the moves file to match, then rerun after `git checkout -- plugins/dforge/skills/<skill>/SKILL.md` and deleting the new reference files.

- [ ] **Step 5: Repoint the pins**

Run, from the repository root:

```bash
T=/tmp/speed-cost-task7
for t in auto-default process-roles review-route settings-skills project-status inline-mode seats; do
  node $T/repoint-pins.mjs plugins/dforge/tests/$t.test.sh plugins/dforge $T/brainstorming-moves.json $T/writing-plans-moves.json
done
node $T/edit-tests.mjs plugins/dforge/tests
```

Expected, in order: `auto-default.test.sh: repointed 31, unresolved 0`, `process-roles.test.sh: repointed 20, unresolved 0`, `review-route.test.sh: repointed 25, unresolved 0`, `settings-skills.test.sh: repointed 12, unresolved 0`, `project-status.test.sh: repointed 2, unresolved 0`, `inline-mode.test.sh: repointed 3, unresolved 0`, `seats.test.sh: repointed 5, unresolved 0`, then `14 edits applied`. An earlier task may have repointed a few of these pins already, which lowers a count; `unresolved` must stay 0. When `edit-tests.mjs` stops on a count, an earlier task changed that file: list the occurrences with `grep -n` on the `from` text, confirm each is a pin on brainstorming or writing-plans, and set the count in the script to what you found.

Then replace the whole of `plugins/dforge/tests/parallel-grouping.test.sh` (its checks of moved text now read the references; the rest are unchanged, and the `clear --phase` count now covers the skill and its references):

```bash
#!/usr/bin/env bash
# writing-plans sorts tasks into alone and parallel groups, orders waves by
# dependency depth, and an auto run's plan switches in place.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
W="$HERE/../skills/writing-plans/SKILL.md"
R="$HERE/../skills/writing-plans/references"

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
names() { # names <label> <text>
  check "$1" "$(grep -qF -- "$2" "$W" && echo yes || echo no)" "yes"
}
namesin() { # namesin <label> <file> <text>
  check "$1" "$(grep -qF -- "$3" "$2" && echo yes || echo no)" "yes"
}

names "two groups" '1. **Draft the tasks as usual, then sort them into two groups.**'
names "the alone group" '**alone** — a task that cannot share a wave'
names "the parallel group" '**parallel** — every other task.'
names "depth decides the order" 'Dependencies decide only the order. A task'"'"'s depth is one more than the'
names "the worked example" 'Task 6 on Tasks 3-5 give `waves — 1-2 | 3-5 | 6`. Every dependency sits in'
namesin "one plan in an auto run" "$R/auto-run-plan.md" '**One plan.** An auto run writes one plan for the whole spec and amends it'
namesin "the finish line is recorded" "$R/auto-run-plan.md" 'holds a `Finish: <action>` line, `scripts/finish-choice set <action> --plan'
namesin "the switch ends the turn" "$R/auto-run-plan.md" '`scripts/auto-run switch` and end the turn with `Auto run: switching`'
namesin "the handoff note" "$R/execution-handoff.md" 'an auto run the session switches in place instead; see Auto run'
names "parallel is the default" 'default is `parallel`), take that value and do not ask.'
names "no split under autoRun=on" 'Under `autoRun=on` the spec covers the whole request by design: write one plan for it, never suggest a split'
check "no clear --phase is left" "$(cat "$W" "$R"/*.md | grep -c 'clear --phase')" "0"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
```

- [ ] **Step 6: Run the tests to verify they pass**

Run, from the repository root:

```bash
unset CLAUDE_CONFIG_DIR
for t in skill-split-planning parallel-grouping auto-default process-roles review-route settings-skills project-status inline-mode seats test-simplifier ui-ux-skill task-step-text lanes next-step turn-end criteria review-depth.acceptance review-depth-qa.acceptance faster-plans.acceptance; do
  if timeout 900 bash plugins/dforge/tests/$t.test.sh > /dev/null 2>&1; then echo "ok   $t"; else echo "FAIL $t"; fi
done
```

Expected: nineteen `ok` lines and no `FAIL`. A `FAIL` names a pin the scripts did not reach: run that test without redirection, find the failing line, and repoint it at the reference file that holds the text (`grep -rnF` for the quoted text under `plugins/dforge/skills/<skill>/`), never by deleting the pin.

- [ ] **Step 7: Validate**

Run:

```bash
node scripts/validate-repository.mjs
timeout 120 /root/.local/bin/claude plugin validate plugins/dforge
```

Expected: `Repository catalogs, manifests, versions, bundled links and the settings schema are valid.` and `Validation passed`.

- [ ] **Step 8: Remove the tools and commit**

```bash
rm -rf /tmp/speed-cost-task7
git add plugins/dforge/skills/brainstorming plugins/dforge/skills/writing-plans plugins/dforge/tests/skill-split-planning.test.sh plugins/dforge/tests/auto-default.test.sh plugins/dforge/tests/process-roles.test.sh plugins/dforge/tests/review-route.test.sh plugins/dforge/tests/settings-skills.test.sh plugins/dforge/tests/project-status.test.sh plugins/dforge/tests/inline-mode.test.sh plugins/dforge/tests/seats.test.sh plugins/dforge/tests/parallel-grouping.test.sh plugins/dforge/tests/review-depth.acceptance.test.sh plugins/dforge/tests/review-depth-qa.acceptance.test.sh plugins/dforge/tests/faster-plans.acceptance.test.sh
git commit -m "refactor(dforge): split brainstorming and writing-plans"
```

### Task 8: Add the pipeline replay stage

**Files:**
- Create: `evals/tiers/lib/pipeline.mjs`
- Modify: `evals/tiers/lib/results.mjs`
- Modify: `evals/tiers/run-grid.mjs`
- Modify: `evals/tiers/arms.json`
- Modify: `evals/tiers/README.md`
- Modify: `evals/tiers/tests/stub-claude.mjs`
- Test: `evals/tiers/tests/pipeline.test.mjs` (new)

**Interfaces:**
- Consumes: Contracts "Pipeline eval" (the `arms.json` `pipeline` entry, `snapshot(<ref>, <eval root>/arms/<ref7>)`, the manifest columns, the `runPipelineCase` signature and result, `PIPELINE_RESULTS`, `PIPELINE_COLUMNS`, the `--stage pipeline` behaviour, and the rule that the start-commit refusal applies to every stage but `pipeline`); Task 1's `docs/dforge/notes/2026-10-28-pipeline-smoke.md`, which this task builds on only when it ends with `**Verdict:** HEADLESS`.
- Produces: Contracts "Pipeline eval": `runPipelineCase({ c, arm, ref, run, root })` in `evals/tiers/lib/pipeline.mjs`, `PIPELINE_RESULTS` and `PIPELINE_COLUMNS` in `lib/results.mjs`, the `pipeline` entry of `arms.json`, and `node evals/tiers/run-grid.mjs --stage pipeline [--rep N]`. Beyond the Contracts, the `arm` column of `results/pipeline.tsv` holds `<label>@<ref7>`, for example `baseline@e6f88a6` or `candidate@3f9713a`, where the label is the key in `arms.json`'s `pipeline` entry and `ref7` the first seven characters of the ref's commit; this is how a baseline measured at one ref serves every later comparison against that ref while a new candidate ref earns new cells. `runPipelineStage` is exported from `lib/pipeline.mjs` for `run-grid.mjs` only.

**Items:** 11

**Depends on:** Task 1

**Implementer:** dforge:impl-sonnet-medium
**Evaluation:** files 1 - spec 0 - coupling 2 - risk 0 = 3

Run first: `tail -n 1 docs/dforge/notes/2026-10-28-pipeline-smoke.md`. It must print `**Verdict:** HEADLESS`. On `**Verdict:** TMUX` stop and report BLOCKED: the controller amends the design before this task runs.

**How a case runs.** `runPipelineCase` builds the arm's plugin tree once (`snapshot` of the ref into `<root>/arms/<ref7>`; the plugin directory is `<root>/arms/<ref7>/plugins/dforge`), snapshots the case's base commit into `<root>/runs/<case>/<arm>-run<run>/work`, and starts one `claude -p` session there with `--plugin-dir <arm plugin>`. The session's HOME, the XDG directories, `CLAUDE_CONFIG_DIR` and `TMPDIR` are all directories of that run, the environment drops every `CLAUDE*`, `DCC_*` and `DFORGE_*` variable of the host except the credentials, and the only file taken from the session's own `CLAUDE_CONFIG_DIR` is `.credentials.json`, so the run is logged in but reads none of the owner's settings or plugins. The session is told to carry out the case's task through `dforge:subagent-driven-development` and stop at the ledger's `Task N: complete` line. Afterwards the harness reads the ledger (through the harness's own `sdd-workspace`, so every arm is read the same way), counts the controller's own `Agent` dispatches in its transcript, lays the hidden tests of the commit that finished the task over the clone, and runs them. A run passes when the session ended normally, the ledger holds the completion line, the hidden tests pass and no file outside the task's Files block changed. A rate limit or a harness error is an `ERROR` row and does not settle the cell; a run cut short after spending, or one that ends without a completion line, is a `FAIL`.

- [ ] **Step 1: Write the test and its stub, and see the test fail**

Replace the whole of `evals/tiers/tests/stub-claude.mjs` (it gains the `loop` and `loopstop` modes, a transcript, and a record of the run's isolated directories and config directory listing in `calls.log`; every earlier mode is unchanged):

```js
// Stands in for the `claude` CLI. Each call takes the next mode from
// $STUB_DIR/modes, records its arguments in $STUB_DIR/calls.log, acts in its
// working directory as that mode says, and prints the JSON a headless run
// prints.
import { appendFileSync, existsSync, mkdirSync, readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { PLAN } from './fixture.mjs';

const ISOLATION = ['HOME', 'XDG_CONFIG_HOME', 'XDG_CACHE_HOME', 'XDG_DATA_HOME', 'CLAUDE_CONFIG_DIR', 'TMPDIR'];
const dir = process.env.STUB_DIR;
const list = readFileSync(join(dir, 'modes'), 'utf8').split('\n').filter(Boolean);
const mode = list[0];
if (list.length > 1) writeFileSync(join(dir, 'modes'), list.slice(1).join('\n') + '\n');
appendFileSync(join(dir, 'calls.log'), JSON.stringify({ mode, cwd: process.cwd(), args: process.argv.slice(2), claudeMds: process.env.CLAUDE_CODE_DISABLE_CLAUDE_MDS, env: Object.fromEntries(ISOLATION.map(k => [k, process.env[k]])), config: process.env.CLAUDE_CONFIG_DIR && existsSync(process.env.CLAUDE_CONFIG_DIR) ? readdirSync(process.env.CLAUDE_CONFIG_DIR).sort() : [], prompt: readFileSync(0, 'utf8') }) + '\n');

const reply = (result, extra = {}) => console.log(JSON.stringify({ type: 'result', is_error: false, result, total_cost_usd: 0.5, num_turns: 3, modelUsage: { 'stub-model': {} }, ...extra }));
const apply = () => spawnSync('git', ['apply', join(dir, 'greet.patch')], { stdio: 'ignore' });
const file = name => existsSync(join(dir, name)) ? readFileSync(join(dir, name), 'utf8') : '';
// A controller session: the ledger where sdd-workspace puts it, and a
// transcript with two dispatches of its own and one inside a subagent's.
const session = ledger => {
  const script = fileURLToPath(new URL('../../../plugins/dforge/scripts/sdd-workspace', import.meta.url));
  const workspace = spawnSync('bash', [script, PLAN], { encoding: 'utf8' }).stdout.trim();
  writeFileSync(join(workspace, 'progress.md'), ledger.join('\n') + '\n');
  const projects = join(process.env.CLAUDE_CONFIG_DIR, 'projects/-work');
  mkdirSync(join(projects, 'session/subagents'), { recursive: true });
  const use = name => JSON.stringify({ message: { content: [{ type: 'tool_use', name }] } });
  writeFileSync(join(projects, 'session.jsonl'), [use('Agent'), use('Bash'), use('Agent')].join('\n') + '\n');
  writeFileSync(join(projects, 'session/subagents/agent-1.jsonl'), use('Agent') + '\n');
};

if (mode === 'pass') { apply(); reply('**Status:** DONE'); }
else if (mode === 'loop') { apply(); session(['Task 1: implementer impl-sonnet-low (assigned; base abc1234)', 'Task 1: fix round 1/2 (1 addressed, 0 open)', 'Task 1: complete (commits abc1234..def5678, review clean)']); reply('Task 1: complete'); }
else if (mode === 'loopstop') { apply(); session(['Task 1: implementer impl-sonnet-low (assigned; base abc1234)']); reply('stopped at the first wait'); }
else if (mode === 'slice') { spawnSync('git', ['apply', join(dir, 'slice.patch')], { stdio: 'ignore' }); reply('**Status:** DONE'); }
else if (mode === 'concerns') { apply(); reply('**Status:** DONE_WITH_CONCERNS'); }
else if (mode === 'failtest') { apply(); writeFileSync('src/greet.sh', 'echo nope\n'); reply('**Status:** DONE'); }
else if (mode === 'cheat') { apply(); writeFileSync('src/greet.sh', 'echo nope\n'); writeFileSync('tests/greet.test.sh', 'true\n'); reply('**Status:** DONE'); }
else if (mode === 'outside') { apply(); writeFileSync('extra.txt', 'x\n'); reply('**Status:** DONE'); }
else if (mode === 'blocked') { reply('**Status:** BLOCKED - the brief is unclear'); }
else if (mode === 'budget') { apply(); reply('', { is_error: true, subtype: 'error_max_budget_usd' }); process.exitCode = 1; }
else if (mode === 'limit') { reply("You've hit your usage limit", { is_error: true, total_cost_usd: 0 }); process.exitCode = 1; }
else if (mode === 'crash') { console.error('boom'); process.exitCode = 2; }
else if (mode === 'review') { mkdirSync('.superpowers/sdd/eval', { recursive: true }); writeFileSync('.superpowers/sdd/eval/review-report.md', file('review.md')); reply('Report: .superpowers/sdd/eval/review-report.md'); }
else if (mode === 'noreport') { reply('A review with no report file.'); }
else if (mode === 'grade') { reply(file('grade.json')); }
else { console.error(`stub-claude: unknown mode ${mode}`); process.exitCode = 2; }
```

Create `evals/tiers/tests/pipeline.test.mjs`:

```js
import assert from 'node:assert/strict';
import { existsSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { join, relative, sep } from 'node:path';
import { after, test } from 'node:test';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { PLAN, fixture, modes } from './fixture.mjs';

const fx = fixture();
after(() => rmSync(fx.top, { recursive: true, force: true }));
const { runPipelineCase } = await import('../lib/pipeline.mjs');
const { PIPELINE_COLUMNS, PIPELINE_RESULTS, readTsv } = await import('../lib/results.mjs');

const root = join(fx.top, 'eval-root');
const hostConfig = join(fx.top, 'host-config');
mkdirSync(hostConfig);
writeFileSync(join(hostConfig, '.credentials.json'), '{"login":true}');
writeFileSync(join(hostConfig, 'settings.json'), '{"model":"owner-choice"}');
process.env.CLAUDE_CONFIG_DIR = hostConfig;
const row = { case: 'p-fixture-t1', plan: PLAN, task: '1', base: fx.planned, fixRounds: '1' };
const calls = () => readFileSync(join(fx.stub, 'calls.log'), 'utf8').trim().split('\n').map(line => JSON.parse(line));
const inside = path => !relative(root, path).startsWith('..') && !relative(root, path).split(sep).includes('..');
const grid = (args = [], env = {}) => spawnSync(process.execPath, [fileURLToPath(new URL('../run-grid.mjs', import.meta.url)), '--stage', 'pipeline', ...args], { cwd: fx.repo, encoding: 'utf8', env: { ...process.env, TIER_EVAL_JOBS: '1', ...env } });

test('the results file has the pipeline columns', () => {
  assert.deepEqual(PIPELINE_COLUMNS, ['rep', 'case', 'arm', 'run', 'outcome', 'costUsd', 'seconds', 'dispatches', 'fixRounds', 'detail']);
  assert.equal(PIPELINE_RESULTS, join(fx.data, 'results/pipeline.tsv'));
});

test('a replayed case passes and reports cost, dispatches and fix rounds', async () => {
  modes(fx.stub, 'loop');
  const result = await runPipelineCase({ c: row, arm: 'baseline@1111111', ref: fx.planned, run: 1, root });
  assert.deepEqual(result, { outcome: 'PASS', costUsd: 0.5, seconds: result.seconds, dispatches: 2, fixRounds: 1, detail: '' });
});

test('a session that stops before the ledger shows the task complete fails', async () => {
  modes(fx.stub, 'loopstop');
  const result = await runPipelineCase({ c: row, arm: 'baseline@1111111', ref: fx.planned, run: 2, root });
  assert.deepEqual([result.outcome, result.detail, result.dispatches, result.fixRounds], ['FAIL', 'no-complete-line', 2, 0]);
});

test('a run that changes nothing fails the hidden tests', async () => {
  modes(fx.stub, 'blocked');
  const result = await runPipelineCase({ c: row, arm: 'baseline@1111111', ref: fx.planned, run: 3, root });
  assert.deepEqual([result.outcome, result.detail], ['FAIL', 'no-complete-line failed=tests/greet.test.sh']);
});

test('a rate limit is an ERROR row, not a failure', async () => {
  modes(fx.stub, 'limit');
  const result = await runPipelineCase({ c: row, arm: 'baseline@1111111', ref: fx.planned, run: 4, root });
  assert.equal(result.outcome, 'ERROR');
  assert.match(result.detail, /^limit: /);
});

test('every run works inside the eval root, under the plugin of its arm', () => {
  const made = calls().filter(call => call.args.includes('--plugin-dir'));
  assert.ok(made.length >= 4);
  for (const call of made) {
    const flag = name => call.args[call.args.indexOf(name) + 1];
    assert.ok(inside(call.cwd), call.cwd);
    assert.ok(inside(flag('--plugin-dir')), flag('--plugin-dir'));
    assert.match(flag('--plugin-dir'), /arms[\\/][0-9a-f]{7}[\\/]plugins[\\/]dforge$/);
    for (const value of Object.values(call.env)) assert.ok(inside(value), value);
    assert.equal(call.claudeMds, '1');
    assert.deepEqual(call.config, ['.claude.json', '.credentials.json']);
    assert.match(call.prompt, /^Use the dforge:subagent-driven-development skill to carry out Task 1 of docs\/superpowers\/plans\/2026-09-20-fixture\.md, and only that task\./);
  }
  assert.ok(existsSync(join(root, 'arms', fx.planned.slice(0, 7), 'plugins/dforge/marker.txt')));
});

test('the pipeline stage runs every missing cell and reuses a baseline measured at the same ref', () => {
  const arms = JSON.parse(readFileSync(join(fx.data, 'arms.json'), 'utf8'));
  writeFileSync(join(fx.data, 'arms.json'), JSON.stringify({ ...arms, pipeline: { baseline: fx.planned, candidate: fx.greet } }));
  writeFileSync(join(fx.data, 'cases/pipeline.tsv'), `case\tplan\ttask\tbase\tfixRounds\n${[row.case, row.plan, row.task, row.base, row.fixRounds].join('\t')}\n`);
  modes(fx.stub, 'loop');
  const first = grid();
  assert.equal(first.status, 0, first.stderr);
  assert.match(first.stdout, /run-grid stage=pipeline rep=1 ran=4 remaining=0 spent=2\.00 stop=-/);
  const rows = readTsv(PIPELINE_RESULTS);
  assert.deepEqual(rows.map(r => [r.arm, r.run, r.outcome, r.dispatches, r.fixRounds]), [
    [`baseline@${fx.planned.slice(0, 7)}`, '1', 'PASS', '2', '1'],
    [`baseline@${fx.planned.slice(0, 7)}`, '2', 'PASS', '2', '1'],
    [`candidate@${fx.greet.slice(0, 7)}`, '1', 'PASS', '2', '1'],
    [`candidate@${fx.greet.slice(0, 7)}`, '2', 'PASS', '2', '1'],
  ]);
  assert.match(readFileSync(PIPELINE_RESULTS, 'utf8').split('\n')[0], /^rep\tcase\tarm\trun\toutcome\tcostUsd\tseconds\tdispatches\tfixRounds\tdetail$/);

  writeFileSync(join(fx.data, 'arms.json'), JSON.stringify({ ...arms, pipeline: { baseline: fx.planned, candidate: fx.shout } }));
  const second = grid();
  assert.match(second.stdout, /ran=2 remaining=0 spent=3\.00/);
  assert.equal(readTsv(PIPELINE_RESULTS).length, 6);
  assert.match(grid().stdout, /ran=0 remaining=0/);
});

test('the pipeline stage stops at the spend cap and refuses a missing manifest', () => {
  assert.match(grid(['--rep', '2'], { TIER_EVAL_CAP_USD: '0' }).stdout, /ran=0 remaining=4 spent=0\.00 stop=cap/);
  rmSync(join(fx.data, 'cases/pipeline.tsv'));
  const none = grid(['--rep', '3']);
  assert.equal(none.status, 2);
  assert.match(none.stderr, /no pipeline manifest/);
});
```

- [ ] **Step 2: Run it to verify it fails**

Run: `timeout 300 node --test evals/tiers/tests/pipeline.test.mjs`
Expected: FAIL, the import of `../lib/pipeline.mjs` or of `PIPELINE_COLUMNS` failing (the module and the exports do not exist yet).

- [ ] **Step 3: Add the results exports and the arms entry**

In `evals/tiers/lib/results.mjs`, replace the line

```js
export const GRADE_COLUMNS = ['rep', 'case', 'arm', 'pass', 'defect', 'found', 'severity', 'quote'];
```

with

```js
export const GRADE_COLUMNS = ['rep', 'case', 'arm', 'pass', 'defect', 'found', 'severity', 'quote'];
export const PIPELINE_RESULTS = resolve(DATA, 'results/pipeline.tsv');
export const PIPELINE_COLUMNS = ['rep', 'case', 'arm', 'run', 'outcome', 'costUsd', 'seconds', 'dispatches', 'fixRounds', 'detail'];
```

In `evals/tiers/arms.json`, replace the line `  "grader": { "model": "opus", "effort": "low" }` with

```json
  "grader": { "model": "opus", "effort": "low" },
  "pipeline": { "baseline": "main", "candidate": "HEAD" }
```

- [ ] **Step 4: Write the pipeline module**

Create `evals/tiers/lib/pipeline.mjs`:

```js
import { copyFileSync, existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, writeFileSync } from 'node:fs';
import { homedir, tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { classify } from './claude.mjs';
import { planAt } from './cases.mjs';
import { changedFiles, overlayTests, runTests } from './grade.mjs';
import { commitMessages, filesBlock, taskText } from './plan.mjs';
import { PIPELINE_COLUMNS, PIPELINE_RESULTS, appendTsv, readTsv } from './results.mjs';
import { snapshot } from './snapshot.mjs';
import { DATA, PLUGIN, WORK, git, run as launch, sh } from './sh.mjs';

const CASE_SECONDS = 3600;
const BUDGET_USD = '10';
const DISPATCH_TOOLS = new Set(['Agent', 'Task']);
// Variables that would let a run reach the host's Claude Code state, kept out
// of the child's environment; credentials for the API stay in.
const HOST_STATE = /^(CLAUDE|DCC_|DFORGE_)/;
const CREDENTIALS = /^(ANTHROPIC_|CLAUDE_CODE_OAUTH_TOKEN$|CLAUDE_CODE_USE_(BEDROCK|VERTEX)$)/;

// armPlugin REF ROOT — the dforge plugin directory of REF's tree under ROOT/arms,
// materialised once. No git worktree is created.
export function armPlugin(ref, root) {
  const sha = git(['rev-parse', ref]).trim();
  const tree = join(root, 'arms', sha.slice(0, 7));
  const plugin = join(tree, 'plugins/dforge');
  if (!existsSync(plugin)) snapshot(sha, tree);
  return plugin;
}

// isolatedEnv DIR — the child's environment: its own HOME, XDG and Claude
// config directories under DIR, nothing of the host's Claude Code state.
function isolatedEnv(dir) {
  const kept = Object.entries(process.env).filter(([key]) => CREDENTIALS.test(key) || !HOST_STATE.test(key));
  const env = {
    ...Object.fromEntries(kept),
    HOME: join(dir, 'home'),
    XDG_CONFIG_HOME: join(dir, 'xdg/config'),
    XDG_CACHE_HOME: join(dir, 'xdg/cache'),
    XDG_DATA_HOME: join(dir, 'xdg/data'),
    XDG_STATE_HOME: join(dir, 'xdg/state'),
    CLAUDE_CONFIG_DIR: join(dir, 'claude'),
    TMPDIR: join(dir, 'tmp'),
    CLAUDE_CODE_DISABLE_CLAUDE_MDS: '1',
    IS_SANDBOX: '1',
  };
  for (const key of ['HOME', 'XDG_CONFIG_HOME', 'XDG_CACHE_HOME', 'XDG_DATA_HOME', 'XDG_STATE_HOME', 'CLAUDE_CONFIG_DIR', 'TMPDIR']) mkdirSync(env[key], { recursive: true });
  return env;
}

// gradingFor C — what the hidden-test grader needs for a manifest row: the
// paths the task may touch, its test files, and the first commit after the
// base that carries the task's commit message.
function gradingFor(c) {
  const tmp = mkdtempSync(join(tmpdir(), 'tier-eval-pipeline-'));
  try {
    const plan = planAt(c.base, c.plan, tmp);
    if (plan === null) throw new Error(`${c.plan} is missing at ${c.base}`);
    const text = taskText(plan, c.task);
    if (text === null) throw new Error(`${c.plan} has no Task ${c.task} at ${c.base}`);
    const { allowed, tests } = filesBlock(text);
    if (tests.length === 0) throw new Error(`Task ${c.task} names no test file`);
    const messages = commitMessages(text);
    const result = git(['log', '--reverse', '--format=%H%x09%s', `${c.base}..HEAD`]).split('\n').filter(Boolean)
      .map(line => line.split('\t')).find(([, subject]) => messages.includes(subject))?.[0];
    if (!result) throw new Error(`no commit after ${c.base} carries the message of Task ${c.task}`);
    return { allowed, tests, result };
  } finally {
    rmSync(tmp, { recursive: true, force: true });
  }
}

function controllerPrompt(c) {
  return [
    `Use the dforge:subagent-driven-development skill to carry out Task ${c.task} of ${c.plan}, and only that task.`,
    'Run it through the controller loop: the implementer, the suite beside the review, the task review and at most two fix rounds.',
    'Every earlier task of the plan is already in this repository. Nobody can answer a question: where the skill would ask, take the smallest reading and record it in the ledger.',
    `Wait as the skill says: when only waiting remains, end your turn; the completion notifications resume you. Stop when the ledger holds a "Task ${c.task}: complete" line or the task is parked.`,
    'Do not push, merge, open a pull request or change anything outside this repository.',
  ].join('\n');
}

function ledgerLines(work, plan, env) {
  const dir = sh('bash', [resolve(PLUGIN, 'scripts/sdd-workspace'), plan], { cwd: work, env }).out.trim();
  const file = join(dir, 'progress.md');
  return dir && existsSync(file) ? readFileSync(file, 'utf8').replace(/\r/g, '').split('\n') : [];
}

// dispatches CONFIG — the subagent dispatches the controller made, counted in
// its own transcript; subagent transcripts live in a subagents/ directory and
// are left out.
function dispatches(config) {
  let count = 0;
  const walk = dir => {
    for (const entry of readdirSync(dir, { withFileTypes: true })) {
      const path = join(dir, entry.name);
      if (entry.isDirectory()) { if (entry.name !== 'subagents') walk(path); continue; }
      if (!entry.name.endsWith('.jsonl')) continue;
      for (const line of readFileSync(path, 'utf8').split('\n').filter(Boolean)) {
        let message;
        try { message = JSON.parse(line).message; } catch { continue; }
        if (Array.isArray(message?.content)) count += message.content.filter(part => part.type === 'tool_use' && DISPATCH_TOOLS.has(part.name)).length;
      }
    }
  };
  if (existsSync(join(config, 'projects'))) walk(join(config, 'projects'));
  return count;
}

// runPipelineCase { c, arm, ref, run, root } — replays manifest row C once
// under the plugin of REF: an isolated clone at C's base commit, one headless
// controller session, then the hidden tests of the commit that finished the
// task. ARM labels the row, RUN is the run number, ROOT the eval's own
// directory: nothing the run touches lies outside it.
export async function runPipelineCase({ c, arm, ref, run, root }) {
  const failed = (detail, extra = {}) => ({ outcome: 'ERROR', costUsd: 0, seconds: 0, dispatches: 0, fixRounds: 0, detail, ...extra });
  try {
    const plugin = armPlugin(ref, root);
    const grading = gradingFor(c);
    const dir = join(root, 'runs', c.case, `${arm.replace('@', '-at-')}-run${run}`);
    rmSync(dir, { recursive: true, force: true });
    const work = join(dir, 'work');
    const initial = snapshot(c.base, work);
    const env = isolatedEnv(dir);
    const key = process.env.ANTHROPIC_API_KEY;
    writeFileSync(join(env.CLAUDE_CONFIG_DIR, '.claude.json'), JSON.stringify({
      hasCompletedOnboarding: true,
      customApiKeyResponses: { approved: key ? [key.slice(-20)] : [], rejected: [] },
      projects: { [work]: { hasTrustDialogAccepted: true } },
    }));
    // The login is the only thing taken from the session's config directory;
    // its settings, plugins and history stay out of the run.
    const credentials = join(process.env.CLAUDE_CONFIG_DIR ?? join(homedir(), '.claude'), '.credentials.json');
    if (existsSync(credentials)) copyFileSync(credentials, join(env.CLAUDE_CONFIG_DIR, '.credentials.json'));
    const prompt = controllerPrompt(c);
    writeFileSync(join(dir, 'prompt.txt'), prompt);
    const args = ['-p', '--model', 'sonnet', '--effort', 'high', '--plugin-dir', plugin, '--setting-sources', 'project',
      '--dangerously-skip-permissions', '--output-format', 'json', '--max-budget-usd', BUDGET_USD];
    const started = Date.now();
    const r = await launch(process.env.TIER_EVAL_CLAUDE ?? 'claude', args, { cwd: work, seconds: CASE_SECONDS, input: prompt, env });
    writeFileSync(join(dir, 'output.json'), r.out);
    writeFileSync(join(dir, 'stderr.txt'), r.err);
    const inv = classify(r, (Date.now() - started) / 1000);
    if (inv.kind === 'limit' || inv.kind === 'error') return failed(`${inv.kind}: ${inv.text.slice(0, 200)}`, { costUsd: inv.cost, seconds: inv.seconds });

    const ledger = ledgerLines(work, c.plan, env);
    const complete = ledger.some(line => line.startsWith(`Task ${c.task}: complete`));
    const fixRounds = ledger.filter(line => line.startsWith(`Task ${c.task}: fix round `)).length;
    const outside = changedFiles(work, initial).filter(p => !p.startsWith('.dforge/') && !grading.allowed.includes(p));
    if (!overlayTests(work, grading.result, grading.tests)) throw new Error(`a test file is missing at ${grading.result}`);
    const tested = await runTests(work, grading.tests);
    const detail = [
      inv.kind === 'ok' ? '' : `cut=${inv.kind}`,
      complete ? '' : 'no-complete-line',
      tested.pass ? '' : `failed=${tested.failed}`,
      outside.length > 0 ? `outside=${outside.join(',')}` : '',
    ].filter(Boolean).join(' ');
    const passed = inv.kind === 'ok' && complete && tested.pass && outside.length === 0;
    return { outcome: passed ? 'PASS' : 'FAIL', costUsd: inv.cost, seconds: inv.seconds, dispatches: dispatches(env.CLAUDE_CONFIG_DIR), fixRounds, detail };
  } catch (error) {
    return failed(`error: ${error.message.slice(0, 200)}`);
  }
}

// runPipelineStage { rep, jobs, capUsd, deadline } — every (case, arm, run)
// cell of cases/pipeline.tsv with no settled row in results/pipeline.tsv, run
// `jobs` at a time. An arm is keyed `<label>@<ref7>`, so a baseline measured
// once at a ref serves every later comparison against that ref. A row
// settles its cell unless it is an ERROR; a rate limit stops the stage.
export async function runPipelineStage({ rep, jobs, capUsd, deadline }) {
  const armsFile = resolve(DATA, 'arms.json');
  const refs = JSON.parse(readFileSync(armsFile, 'utf8')).pipeline;
  if (!refs?.baseline || !refs?.candidate) throw new Error(`${armsFile} has no "pipeline" entry with a baseline and a candidate ref`);
  const manifest = resolve(DATA, 'cases/pipeline.tsv');
  if (!existsSync(manifest)) throw new Error(`no pipeline manifest at ${manifest}`);
  const root = join(WORK, 'pipeline', `rep${rep}`);
  const arms = ['baseline', 'candidate'].map(label => {
    const sha = git(['rev-parse', refs[label]]).trim();
    return { ref: sha, key: `${label}@${sha.slice(0, 7)}` };
  });
  const cells = readTsv(manifest).flatMap(c => arms.flatMap(arm => [1, 2].map(run => ({ c, arm, run }))));
  const rows = () => readTsv(PIPELINE_RESULTS).filter(r => r.rep === String(rep));
  const pending = () => cells.filter(({ c, arm, run }) => !rows().some(r => r.case === c.case && r.arm === arm.key && r.run === String(run) && r.outcome !== 'ERROR'));
  const spent = () => rows().reduce((sum, r) => sum + Number(r.costUsd), 0);
  const queue = pending();
  for (const arm of arms) if (queue.some(cell => cell.arm === arm)) armPlugin(arm.ref, root);
  let stop = null, ran = 0;
  await Promise.all(Array.from({ length: jobs }, async () => {
    while (stop === null && queue.length > 0) {
      if (spent() >= capUsd) { stop = 'cap'; break; }
      if (Date.now() >= deadline) { stop = 'time'; break; }
      const { c, arm, run } = queue.shift();
      const result = await runPipelineCase({ c, arm: arm.key, ref: arm.ref, run, root });
      const row = { rep, case: c.case, arm: arm.key, run, ...result };
      appendTsv(PIPELINE_RESULTS, PIPELINE_COLUMNS, row);
      ran += 1;
      console.log(PIPELINE_COLUMNS.map(k => row[k] ?? '').join('\t'));
      if (row.outcome === 'ERROR' && row.detail.startsWith('limit')) stop = 'limit';
    }
  }));
  return { ran, remaining: pending().length, spent: spent(), stop };
}
```

- [ ] **Step 5: Add the stage to run-grid**

In `evals/tiers/run-grid.mjs` make four replacements.

Replace the usage line

```js
// Usage: node evals/tiers/run-grid.mjs --stage smoke|written|stripped|review|slice [--rep N] [--minutes M] [--pass P]
// The slice stage reads cases/slices.tsv, built by build-manifest.mjs --slices,
// and runs each slice case on every arm of arms.json's slice list.
```

with

```js
// Usage: node evals/tiers/run-grid.mjs --stage smoke|written|stripped|review|slice|pipeline [--rep N] [--minutes M] [--pass P]
// The slice stage reads cases/slices.tsv, built by build-manifest.mjs --slices,
// and runs each slice case on every arm of arms.json's slice list.
// The pipeline stage replays cases/pipeline.tsv under the baseline and the
// candidate ref of arms.json's pipeline entry, twice each, into
// results/pipeline.tsv; it does not read the start commit of manifest.tsv.
```

Replace `import { SLICES, readManifest } from './lib/cases.mjs';` with

```js
import { SLICES, readManifest } from './lib/cases.mjs';
import { runPipelineStage } from './lib/pipeline.mjs';
```

Replace `const STAGES = ['smoke', 'written', 'stripped', 'review', 'slice'];` with

```js
const STAGES = ['smoke', 'written', 'stripped', 'review', 'slice', 'pipeline'];
```

Replace the two lines

```js
if (stage === 'slice' && !existsSync(SLICES)) { console.error('run-grid: no slice manifest; run build-manifest.mjs --slices'); process.exit(2); }
const { start, cases } = readManifest(stage === 'slice' ? SLICES : undefined);
```

with

```js
if (stage === 'slice' && !existsSync(SLICES)) { console.error('run-grid: no slice manifest; run build-manifest.mjs --slices'); process.exit(2); }
if (stage === 'pipeline') {
  let summary;
  try { summary = await runPipelineStage({ rep, jobs: JOBS, capUsd: CAP_USD, deadline }); } catch (error) { console.error(`run-grid: ${error.message}`); process.exit(2); }
  console.log(`run-grid stage=pipeline rep=${rep} ran=${summary.ran} remaining=${summary.remaining} spent=${summary.spent.toFixed(2)} stop=${summary.stop ?? '-'}`);
  process.exit(summary.stop ? 3 : summary.remaining > 0 ? 1 : 0);
}
const { start, cases } = readManifest(stage === 'slice' ? SLICES : undefined);
```

- [ ] **Step 6: Document the stage**

In `evals/tiers/README.md`, add this row to the Commands table directly above the row that starts `| \`node evals/tiers/grade-case.mjs RUN_DIR\``:

```markdown
| `node evals/tiers/run-grid.mjs --stage pipeline [--rep N] [--minutes M]` | Replays every case of `cases/pipeline.tsv` under the baseline and the candidate ref of `arms.json`'s `pipeline` entry, two runs each, into `results/pipeline.tsv`; a cell with a settled row is skipped |
```

Add this row to the Files table directly below the `results/results.tsv` row:

```markdown
| `results/pipeline.tsv` | One line per pipeline run: `rep, case, arm, run, outcome, costUsd, seconds, dispatches, fixRounds, detail`; `arm` is `<label>@<ref7>` |
```

Add this paragraph at the end of the file:

```markdown
The pipeline stage materialises each arm's repository tree under `~/.cache/dr-tier-eval/pipeline/rep<N>/arms/<ref7>` and runs one `claude -p --plugin-dir <arm>/plugins/dforge` session per cell in a clone of the case's base commit. Each run has its own HOME, XDG directories, `CLAUDE_CONFIG_DIR` and `TMPDIR` beneath that root. The environment keeps the host's `ANTHROPIC_*` variables and `CLAUDE_CODE_OAUTH_TOKEN`, and the run's config directory receives a copy of the session's `.credentials.json` and nothing else, so the run is logged in but reads none of the owner's settings or plugins. No git worktree is created.
```

- [ ] **Step 7: Run the tests to verify they pass**

Run:

```bash
timeout 300 node --test evals/tiers/tests/pipeline.test.mjs
timeout 500 node --test evals/tiers/tests/*.test.mjs
```

Expected: the first prints eight passing tests; the second `pass 89` and `fail 0` (the eighty-one earlier tests plus the eight new ones; a count that differs by earlier tasks' additions is fine so long as `fail 0`).

- [ ] **Step 8: Validate and commit**

Run: `node scripts/validate-repository.mjs`
Expected: `Repository catalogs, manifests, versions, bundled links and the settings schema are valid.`

```bash
git add evals/tiers/lib/pipeline.mjs evals/tiers/lib/results.mjs evals/tiers/run-grid.mjs evals/tiers/arms.json evals/tiers/README.md evals/tiers/tests/stub-claude.mjs evals/tiers/tests/pipeline.test.mjs
git commit -m "feat(evals): add the pipeline replay stage"
```

### Task 9: Fix the implementer report grammar

**Files:**
- Modify: `plugins/dforge/skills/subagent-driven-development/references/implementer-prompt.md`
- Modify: `plugins/dforge/tests/task-step-text.test.sh`
- Modify: `plugins/dforge/tests/task-step.test.sh`
- Modify: `plugins/dforge/tests/task-loop-steps.acceptance.test.sh`

**Interfaces:**
- Consumes: Contracts "Implementer report" (the `## Verified` bullet form, the `Report:` last line, focused tests and no full suite, `[PLUGIN_ROOT]/scripts/context-size` in the Run Control paragraph, and the gate's bullet regex).
- Produces: Contracts "Implementer report": the subagent-mode implementer prompt carries the grammar that Task 4's stop gate checks and that Task 15 relies on; the prompt no longer names `suite-run`, and `[PLUGIN_ROOT]` keeps one use, in the Run Control paragraph.

**Items:** 1

**Depends on:** Task 2

**Implementer:** dforge:impl-sonnet-medium
**Evaluation:** files 1 - spec 0 - coupling 2 - risk 1 = 4

The pins that keep this prompt and the stop gate in step live here, not in the gate's test: `task-step-text.test.sh` extracts the two example bullets from the prompt and checks that each, with its placeholders filled in, matches the gate's bullet regex. Two other tests check that the dispatch file `task-step start` writes carries the expanded plugin root; they looked for `scripts/suite-run -- ` and now look for `scripts/context-size`, the one path left in the prompt. `evals/tiers/build-case.mjs` fills the same template and fails when a placeholder it names is missing, so every placeholder the prompt has now (`[BRIEF_FILE]`, `[REPORT_FILE]`, `[PLUGIN_ROOT]`, `[directory]`, the task name and the scene line) stays.

- [ ] **Step 1: Write the failing pins**

In `plugins/dforge/tests/task-step-text.test.sh`, replace the two lines

```bash
names "implementers run the full suite through suite-run" "$IP" '`bash [PLUGIN_ROOT]/scripts/suite-run -- <the suite command>` and report'
lacks "implementers no longer run the full suite before committing" "$IP" 'full suite once before committing, not after every edit.'
```

with

```bash
lacks "implementers no longer run the full suite through suite-run" "$IP" 'scripts/suite-run'
lacks "implementers no longer run the full suite before committing" "$IP" 'full suite once before committing, not after every edit.'
names "implementers run the focused tests that cover their change" "$IP" 'Before each commit, run the focused tests that cover what you changed -'
names "the controller runs the full suite beside the review" "$IP" 'The controller runs the full suite beside the review of your'
names "the run-control paragraph names context-size by plugin root" "$IP" 'Never run `[PLUGIN_ROOT]/scripts/context-size`, `scripts/auto-run` or'
names "the report gains a Verified section" "$IP" '`## Verified`: one bullet per command you ran to check your work.'
names "the reply ends with the Report line" "$IP" '`Report: <absolute path of the report file>`'
verified=$(grep -E '^ +- `<command>` — (pass|fail): <n> passed, <m> failed$' "$IP" | sed -E 's/^ +//; s/<command>/bash t.sh/; s/<n>/3/; s/<m>/0/')
check "the prompt shows both Verified bullet forms" "$(printf '%s\n' "$verified" | grep -c .)" "2"
check "each Verified bullet form matches the stop gate's grammar" "$(printf '%s\n' "$verified" | grep -cE '^- `[^`]+` — (pass|fail)(: .*)?$')" "2"
```

In `plugins/dforge/tests/task-step.test.sh`, replace

```bash
check "start: the plugin root is expanded to this plugin" "$(grep -c "bash $(cd "$P" && pwd)/scripts/suite-run -- " "$D")" "1"
```

with

```bash
check "start: the plugin root is expanded to this plugin" "$(grep -c "$(cd "$P" && pwd)/scripts/context-size" "$D")" "1"
```

In `plugins/dforge/tests/task-loop-steps.acceptance.test.sh`, replace

```bash
  has "A1: the dispatch carries the expanded plugin root" "$(cat "$D")" "$PLUGIN/scripts/suite-run"
```

with

```bash
  has "A1: the dispatch carries the expanded plugin root" "$(cat "$D")" "$PLUGIN/scripts/context-size"
```

- [ ] **Step 2: Run the fast test to verify it fails**

Run: `timeout 120 bash plugins/dforge/tests/task-step-text.test.sh`
Expected: FAIL on eight checks: `implementers no longer run the full suite through suite-run`, `implementers run the focused tests that cover their change`, `the controller runs the full suite beside the review`, `the run-control paragraph names context-size by plugin root`, `the report gains a Verified section`, `the reply ends with the Report line`, `the prompt shows both Verified bullet forms` and `each Verified bullet form matches the stop gate's grammar`.

- [ ] **Step 3: Edit the implementer prompt**

All edits are in `plugins/dforge/skills/subagent-driven-development/references/implementer-prompt.md`. The text sits inside the template's fenced `prompt: |` block, indented four spaces; keep that indent.

Replace

```
    While iterating, run the focused test for what you're changing before
    each commit, not the full suite after every edit. After your final
    commit, on a clean tree, run the project's full suite once through
    `bash [PLUGIN_ROOT]/scripts/suite-run -- <the suite command>` and report
    its digest in your report's test results: it records the HEAD it ran at,
    so the controller does not run the suite again on a HEAD you already
    covered.
```

with

```
    Before each commit, run the focused tests that cover what you changed -
    the test files or cases for the code you touched - and never the whole
    suite. The controller runs the full suite beside the review of your
    final commit, and a failure it finds there comes back to you as a
    finding. Write each command you ran, with its result, under `## Verified`
    in your report (see Report Format).
```

Replace

```
    Never run `scripts/context-size`, `scripts/auto-run` or
    `scripts/next-step` yourself:
```

with

```
    Never run `[PLUGIN_ROOT]/scripts/context-size`, `scripts/auto-run` or
    `scripts/next-step` yourself:
```

Replace

```
    Fix them, re-run the tests that cover the amended code, and append a fix
    report to your report file: what you changed, the covering tests you
    ran, the command, and the output. Reviewers will not re-run tests for
    you — your report is the test evidence. Then reply with the same short
    status contract as your first report.
```

with

```
    Fix them, re-run the tests that cover the amended code, and append a fix
    report to your report file: what you changed, and a `## Verified`
    section in the form below with one bullet per covering command you ran.
    Reviewers will not re-run tests for you — your report is the test
    evidence. Then reply with the same short status contract as your first
    report, ending with its `Report:` line.
```

Replace

```
    - What you tested and test results
    - **TDD Evidence**
```

with

```
    - What you tested, summarised, and anything you could not run
    - `## Verified`: one bullet per command you ran to check your work. Each
      bullet starts at the beginning of its line and has exactly this form,
      where the separator is a space, an em dash and a space, `pass` means
      the command exited 0, and the counts are the ones the command printed
      (a command that prints none is `1 passed, 0 failed` on exit 0 and
      `0 passed, 1 failed` otherwise):
      - `<command>` — pass: <n> passed, <m> failed
      - `<command>` — fail: <n> passed, <m> failed
    - **TDD Evidence**
```

Replace

```
    - Your concerns, if any
    - The report file path
```

with

```
    - Your concerns, if any
    - As the last line of your reply, exactly this on one line, with the
      path written out in full:
      `Report: <absolute path of the report file>`
```

Replace, in the Placeholders list at the end of the file,

```
- `[PLUGIN_ROOT]` — the resolved dforge plugin directory; expand it before
  sending, so the `suite-run` call above names a real path
```

with

```
- `[PLUGIN_ROOT]` — the resolved dforge plugin directory; expand it before
  sending, so the `context-size` path above names a real path
```

- [ ] **Step 4: Run the tests to verify they pass**

Run:

```bash
unset CLAUDE_CONFIG_DIR
timeout 120 bash plugins/dforge/tests/task-step-text.test.sh
timeout 1500 bash plugins/dforge/tests/task-step.test.sh
timeout 1300 bash plugins/dforge/tests/task-loop-steps.acceptance.test.sh
timeout 300 node --test evals/tiers/tests/text.test.mjs
```

Expected: every command exits 0 and ends with no `FAIL` line (`task-step-text.test.sh` prints `0 failed`).

- [ ] **Step 5: Validate and commit**

Run: `node scripts/validate-repository.mjs && timeout 120 /root/.local/bin/claude plugin validate plugins/dforge`
Expected: `Repository catalogs, manifests, versions, bundled links and the settings schema are valid.` and `Validation passed`.

```bash
git add plugins/dforge/skills/subagent-driven-development/references/implementer-prompt.md plugins/dforge/tests/task-step-text.test.sh plugins/dforge/tests/task-step.test.sh plugins/dforge/tests/task-loop-steps.acceptance.test.sh
git commit -m "feat(dforge): fix the implementer report grammar"
```

### Task 10: Split the remaining skills and add the size test

**Files:**
- Create: `plugins/dforge/tests/skill-size.test.sh`
- Create: `plugins/dforge/tests/skill-view.sh`
- Create: `plugins/dforge/skills/executing-plans/references/setup.md`
- Create: `plugins/dforge/skills/executing-plans/references/recovery.md`
- Create: `plugins/dforge/skills/executing-plans/references/ruling-seat.md`
- Create: `plugins/dforge/skills/executing-plans/references/switching.md`
- Create: `plugins/dforge/skills/executing-plans/references/finish-rulings.md`
- Create: `plugins/dforge/skills/executing-plans/references/rationalizations.md`
- Create: `plugins/dforge/skills/finishing-a-development-branch/references/ui-proof.md`
- Create: `plugins/dforge/skills/finishing-a-development-branch/references/execute-choice.md`
- Create: `plugins/dforge/skills/finishing-a-development-branch/references/cleanup.md`
- Create: `plugins/dforge/skills/finishing-a-development-branch/references/rationalizations.md`
- Create: `plugins/dforge/skills/writing-skills/references/discovery-optimization.md`
- Create: `plugins/dforge/skills/writing-skills/references/match-the-form.md`
- Modify: `plugins/dforge/skills/executing-plans/SKILL.md`
- Modify: `plugins/dforge/skills/finishing-a-development-branch/SKILL.md`
- Modify: `plugins/dforge/skills/writing-skills/SKILL.md`
- Modify: `plugins/dforge/tests/auto-run-skills.test.sh`
- Modify: `plugins/dforge/tests/final-phase.test.sh`
- Modify: `plugins/dforge/tests/gates-manifest.test.sh`
- Modify: `plugins/dforge/tests/inline-mode.test.sh`
- Modify: `plugins/dforge/tests/project-status.test.sh`
- Modify: `plugins/dforge/tests/task-step-text.test.sh`
- Modify: `plugins/dforge/tests/review-route.test.sh`
- Modify: `plugins/dforge/tests/ui-ux-skill.test.sh`
- Modify: `plugins/dforge/tests/waiting-text.test.sh`
- Modify: `plugins/dforge/tests/working-directory.test.sh`

**Interfaces:**
- Consumes: Contracts → Skill references (where moved material lives, the link-line form, no pin deleted). Tasks 2 and 7 have already brought `subagent-driven-development`, `brainstorming` and `writing-plans` under the cap, so this task's size test can pass for every skill.
- Produces: Contracts → Size test (`plugins/dforge/tests/skill-size.test.sh`). It also produces `plugins/dforge/tests/skill-view.sh`, a helper only this task's repointed pin tests source.

**Items:** 14

**Depends on:** Task 2, Task 7

**Implementer:** dforge:impl-sonnet-high
**Evaluation:** files 2 - spec 0 - coupling 1 - risk 2 = 5

Three skills are still over 20,000 bytes: `executing-plans` (about 35,700), `finishing-a-development-branch` (about 28,700) and `writing-skills` (about 26,300). The sections below are read at one step only, so their bodies move into `references/`; each section keeps its heading and gains one `Read [x](references/x) before you …` line, so a session that lost the tail after compaction still reaches them. Nothing is reworded: the text moves as it is, and relative links gain one `../` for the deeper directory. `finishing-a-development-branch` Step 5b is not moved because its text spells the retired `superpowers` path, which `scripts/validate-repository.mjs` allows only in that SKILL.md.

- [ ] **Step 1: Write the size test and the pin-view helper**

Create `plugins/dforge/tests/skill-size.test.sh`:

```bash
#!/usr/bin/env bash
# Every SKILL.md stays at or under 20,000 bytes: after a compaction Claude Code
# re-attaches only the first 5,000 tokens of an invoked skill, so text past the
# cap is lost to a long session. Text a step reads only at that step lives in
# references/, linked from the step by a "Read [x](references/x) before you ..."
# line.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
P="$HERE/.."
CAP=20000

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}

over_cap() { # over_cap <skills dir> — one line per SKILL.md over the cap
  local f bytes
  for f in "$1"/*/SKILL.md; do
    [ -f "$f" ] || continue
    bytes=$(wc -c < "$f" | tr -d ' \r')
    [ "$bytes" -le "$CAP" ] || printf 'skill-size: plugins/dforge/skills/%s/SKILL.md %s bytes (cap %s)\n' "$(basename "$(dirname "$f")")" "$bytes" "$CAP"
  done
}

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/at" "$TMP/over" "$TMP/way-over"
head -c 20000 /dev/zero | tr '\0' x > "$TMP/at/SKILL.md"
head -c 20001 /dev/zero | tr '\0' x > "$TMP/over/SKILL.md"
head -c 30000 /dev/zero | tr '\0' x > "$TMP/way-over/SKILL.md"
check "a skill at the cap passes; each skill over it is named with its size" "$(over_cap "$TMP")" \
  "$(printf 'skill-size: plugins/dforge/skills/over/SKILL.md 20001 bytes (cap 20000)\nskill-size: plugins/dforge/skills/way-over/SKILL.md 30000 bytes (cap 20000)')"

over=$(over_cap "$P/skills")
[ -z "$over" ] || printf '%s\n' "$over"
check "every SKILL.md is at most $CAP bytes" "$over" ""

linked() { # linked <skill> <reference> — SKILL.md has the Read line and the file exists
  check "$1 links references/$2" \
    "$(grep -cF "Read [$2](references/$2) before you " "$P/skills/$1/SKILL.md") $([ -s "$P/skills/$1/references/$2" ] && echo present || echo missing)" "1 present"
}
for ref in setup.md recovery.md ruling-seat.md switching.md finish-rulings.md rationalizations.md; do linked executing-plans "$ref"; done
for ref in ui-proof.md execute-choice.md cleanup.md rationalizations.md; do linked finishing-a-development-branch "$ref"; done
for ref in discovery-optimization.md match-the-form.md; do linked writing-skills "$ref"; done

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
```

Create `plugins/dforge/tests/skill-view.sh`:

```bash
# Sourced by pin tests after they set P (the plugin root) and SKILL_VIEW_DIR (a
# directory the test creates and removes). skill_view SKILL prints the path of
# a file named SKILL.md that holds the skill's SKILL.md followed by every file
# of its references/, so a pin finds text a split moved out of SKILL.md.
skill_view() {
  mkdir -p "$SKILL_VIEW_DIR/$1"
  cat "$P/skills/$1/SKILL.md" "$P/skills/$1"/references/*.md > "$SKILL_VIEW_DIR/$1/SKILL.md"
  printf '%s\n' "$SKILL_VIEW_DIR/$1/SKILL.md"
}
```

- [ ] **Step 2: Run the size test to see it fail**

Run: `timeout 60 bash plugins/dforge/tests/skill-size.test.sh`
Expected: exit 1. The output starts with one `skill-size: plugins/dforge/skills/<name>/SKILL.md <bytes> bytes (cap 20000)` line for each of `executing-plans`, `finishing-a-development-branch` and `writing-skills` (and for no other skill), then a FAIL for "every SKILL.md is at most 20000 bytes" and twelve FAIL lines, one per reference link.

- [ ] **Step 3: Write the split script**

Create the directory `${TMPDIR:-/tmp}/task10-split` (it is outside the repository and is removed in Step 9) and write `${TMPDIR:-/tmp}/task10-split/split-all.sh`:

```bash
#!/usr/bin/env bash
# Usage: bash split-all.sh PLUGIN_DIR
# Moves the bodies of the named sections out of three SKILL.md files into
# references/, leaving each section's heading and one "Read ... before you ..."
# line. A second run stops at the first move: its start line is already gone.
set -uo pipefail

# move_range SKILL_DIR START_PREFIX END_HEADING REF_NAME REF_TITLE LINK_LINE
# Moves the lines from the first one that starts with START_PREFIX up to, not
# including, the heading line END_HEADING (the end of the file when it is empty)
# into SKILL_DIR/references/REF_NAME, and puts LINK_LINE in their place.
# Relative links in the moved text gain one "../" for the deeper directory.
move_range() {
  local dir=$1 start=$2 endh=$3 ref=$4 title=$5 link=$6
  local skill=$dir/SKILL.md total s e
  total=$(grep -c '' "$skill")
  s=$(START=$start awk 'index($0, ENVIRON["START"]) == 1 { print NR; exit }' "$skill")
  [ -n "$s" ] || { echo "split: no line starts with: $start" >&2; return 1; }
  if [ -n "$endh" ]; then
    e=$(S=$s E=$endh awk 'NR > ENVIRON["S"] + 0 && $0 == ENVIRON["E"] { print NR; exit }' "$skill")
    [ -n "$e" ] || { echo "split: no heading line: $endh" >&2; return 1; }
  else
    e=$((total + 1))
  fi
  mkdir -p "$dir/references"
  {
    printf '# %s\n\n' "$title"
    sed -n "${s},$((e - 1))p" "$skill" | sed 's#\](\.\./#](../../#g' |
      awk '{ l[NR] = $0 } END { n = NR; while (n > 0 && l[n] == "") n--; for (i = 1; i <= n; i++) print l[i] }'
  } > "$dir/references/$ref"
  {
    sed -n "1,$((s - 1))p" "$skill"
    printf '%s\n' "$link"
    if [ "$e" -le "$total" ]; then printf '\n'; sed -n "${e},\$p" "$skill"; fi
  } > "$skill.new" && mv "$skill.new" "$skill"
}

S=$1/skills
D=$S/executing-plans
move_range "$D" 'Ensure the work happens in an isolated workspace: use' '## The Ledger' setup.md 'Setup' \
  'Read [setup.md](references/setup.md) before you set up the workspace, the ledger and the plan header.' || exit 1
move_range "$D" '**Recovery.** For task N' '## Session Budget' recovery.md 'Recovery and plan state' \
  'Read [recovery.md](references/recovery.md) before you resume a task from its last ledger line.' || exit 1
move_range "$D" 'Judgment about the plan, the spec or a finding belongs to the ruling seat' '## Switching to subagent mode' ruling-seat.md 'The Ruling Seat' \
  'Read [ruling-seat.md](references/ruling-seat.md) before you send the ruling seat an item or carry out its verdict.' || exit 1
move_range "$D" 'Inline mode has one exit, and it runs in one direction.' '## Final Review' switching.md 'Switching to subagent mode' \
  'Read [switching.md](references/switching.md) before you leave inline mode for subagent mode.' || exit 1
move_range "$D" '| Excuse | Reality |' '' rationalizations.md 'Common Rationalizations' \
  'Read [rationalizations.md](references/rationalizations.md) before you skip a step of the task loop.' || exit 1
move_range "$D" '**Your rulings ride in that message.**' '## Common Rationalizations' finish-rulings.md 'Rulings in the finishing message' \
  'Read [finish-rulings.md](references/finish-rulings.md) before you invoke finishing.' || exit 1

D=$S/finishing-a-development-branch
move_range "$D" 'Run `ui-proof check --base MERGE_BASE' '## Step 2: Detect Environment' ui-proof.md 'Step 1b: Prove the UI' \
  'Read [ui-proof.md](references/ui-proof.md) before you prove the UI.' || exit 1
move_range "$D" '**Whose choice it is.**' '## Step 5b: Record the plan as completed' execute-choice.md 'Step 5: Execute Choice' \
  'Read [execute-choice.md](references/execute-choice.md) before you carry out the chosen option.' || exit 1
move_range "$D" '**Runs for Option 1 and confirmed discards.**' '## Step 7: Report the Next Step' cleanup.md 'Step 6: Cleanup Workspace' \
  'Read [cleanup.md](references/cleanup.md) before you remove the worktree.' || exit 1
move_range "$D" '| Excuse | Reality |' '' rationalizations.md 'Common Rationalizations' \
  'Read [rationalizations.md](references/rationalizations.md) before you skip a step of finishing.' || exit 1

D=$S/writing-skills
move_range "$D" '**Critical for discovery:**' '## Flowchart Usage' discovery-optimization.md 'Skill Discovery Optimization (SDO)' \
  'Read [discovery-optimization.md](references/discovery-optimization.md) before you write or change a skill description, name or keyword.' || exit 1
move_range "$D" 'Before writing guidance, classify the baseline failure.' '## Bulletproofing Skills Against Rationalization' match-the-form.md 'Match the Form to the Failure' \
  'Read [match-the-form.md](references/match-the-form.md) before you write guidance for a failure.' || exit 1

wc -c "$S/executing-plans/SKILL.md" "$S/finishing-a-development-branch/SKILL.md" "$S/writing-skills/SKILL.md"
```

- [ ] **Step 4: Run the split from the repository root**

Run: `bash "${TMPDIR:-/tmp}/task10-split/split-all.sh" plugins/dforge`
Expected: exit 0 and three size lines near `19645`, `19262` and `18401` bytes (the script prints `wc -c` of the three SKILL.md files); each is at most 20,000. A second run stops at the first move with `split: no line starts with:` and exit 1, so do not run it twice.

Run: `timeout 60 bash plugins/dforge/tests/skill-size.test.sh`
Expected: `14 passed, 0 failed`.

- [ ] **Step 5: Run the pin tests to see which pins the move broke**

Run:

```bash
for t in auto-run-skills final-phase gates-manifest inline-mode project-status task-step-text review-route ui-ux-skill waiting-text working-directory; do
  timeout 900 bash plugins/dforge/tests/$t.test.sh > /dev/null 2>&1; echo "$t exit $?"
done
```

Expected: every line ends `exit 1`. Each of these tests greps text that now lives in a reference file (or counts the files that carry it). Pin tests are repointed, never deleted: the next step points each one at the skill's view, `SKILL.md` followed by its `references/*.md`, and changes the one count that grew.

- [ ] **Step 6: Repoint the pins**

Write `${TMPDIR:-/tmp}/task10-split/repoint-pins.mjs`:

```javascript
import { readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

const dir = process.argv[2];
const SETUP = 'SKILL_VIEW_DIR=$(mktemp -d)\ntrap \'rm -rf "$SKILL_VIEW_DIR"\' EXIT\n. "$HERE/skill-view.sh"\n';
const SETUP_TMP = 'SKILL_VIEW_DIR="$TMP/views"\nmkdir "$SKILL_VIEW_DIR"\n. "$HERE/skill-view.sh"\n';
const EP = 'executing-plans';
const FIN = 'finishing-a-development-branch';
const view = skill => `"$(skill_view ${skill})"`;
const P_LINE = 'P="$HERE/.."\n';

// file -> [[old, new], ...]; every old string must occur, and exactly once unless count is given.
const edits = {
  'auto-run-skills.test.sh': [
    ['unset CLAUDE_CONFIG_DIR CLAUDE_CODE_SESSION_ID DFORGE_BUDGET CLAUDE_PROJECT_DIR\n', `unset CLAUDE_CONFIG_DIR CLAUDE_CODE_SESSION_ID DFORGE_BUDGET CLAUDE_PROJECT_DIR\n${SETUP}`],
    ['EPF="$P/skills/executing-plans/SKILL.md"', `EPF=${view(EP)}`],
  ],
  'final-phase.test.sh': [
    [P_LINE, P_LINE + SETUP],
    ['EP="$P/skills/executing-plans/SKILL.md"', `EP=${view(EP)}`],
  ],
  'gates-manifest.test.sh': [
    [P_LINE, P_LINE + SETUP],
    ['present "finishing passes the pre-merge base" "$P/skills/finishing-a-development-branch/SKILL.md"', `present "finishing passes the pre-merge base" ${view(FIN)}`],
    ['FIN="$P/skills/finishing-a-development-branch/SKILL.md"', `FIN=${view(FIN)}`],
  ],
  'inline-mode.test.sh': [
    [P_LINE, P_LINE + SETUP],
    ['INLINE="$P/skills/executing-plans/SKILL.md"', `INLINE=${view(EP)}`],
  ],
  'project-status.test.sh': [
    [P_LINE, P_LINE + SETUP],
    ['for skill_file in "$P/skills/executing-plans/SKILL.md" "$P/skills/subagent-driven-development/SKILL.md"; do', `for skill_file in ${view(EP)} "$P/skills/subagent-driven-development/SKILL.md"; do`, 2],
  ],
  'task-step-text.test.sh': [
    [P_LINE, P_LINE + SETUP],
    ['INLINE="$P/skills/executing-plans/SKILL.md"', `INLINE=${view(EP)}`],
  ],
  'review-route.test.sh': [
    ['TMP=$(mktemp -d)\ntrap \'rm -rf "$TMP"\' EXIT\n', `TMP=$(mktemp -d)\ntrap 'rm -rf "$TMP"' EXIT\n${SETUP_TMP}EP_VIEW=${view(EP)}\n`],
    ['present "inline mode never fixes a delegated task\'s gap itself" "$P/skills/executing-plans/SKILL.md"', 'present "inline mode never fixes a delegated task\'s gap itself" "$EP_VIEW"'],
    ['present "inline mode carries a delegated breaker gap forward" "$P/skills/executing-plans/SKILL.md"', 'present "inline mode carries a delegated breaker gap forward" "$EP_VIEW"'],
    ['present "inline mode reaches the executor empty-diff kind" "$P/skills/executing-plans/SKILL.md"', 'present "inline mode reaches the executor empty-diff kind" "$EP_VIEW"'],
  ],
  'ui-ux-skill.test.sh': [
    [P_LINE, P_LINE + SETUP],
    ['FIN="$P/skills/finishing-a-development-branch/SKILL.md"', `FIN=${view(FIN)}`],
  ],
  'waiting-text.test.sh': [
    ['INLINE="$P/skills/executing-plans/SKILL.md"\n', ''],
    ['TMP="$(mktemp -d)"\ntrap \'rm -rf "$TMP"\' EXIT\n', `TMP="$(mktemp -d)"\ntrap 'rm -rf "$TMP"' EXIT\n${SETUP_TMP}INLINE=${view(EP)}\n`],
  ],
  'working-directory.test.sh': [
    ['check "nine skill and reference files cite the contract" \\\n  "$(grep -rlF \'(see using-dforge §Session Budget)\' "$P/skills" "$P/reference" | wc -l | tr -d \' \')" "9"', 'check "ten skill and reference files cite the contract" \\\n  "$(grep -rlF \'(see using-dforge §Session Budget)\' "$P/skills" "$P/reference" | wc -l | tr -d \' \')" "10"'],
  ],
};

for (const [name, list] of Object.entries(edits)) {
  const file = join(dir, name);
  let text = readFileSync(file, 'utf8');
  for (const [old, next, count = 1] of list) {
    const found = text.split(old).length - 1;
    if (found !== count) throw new Error(`${name}: expected ${count} of ${JSON.stringify(old)}, found ${found}`);
    text = text.split(old).join(next);
  }
  writeFileSync(file, text);
  console.log(`repointed ${name}`);
}
```

Run: `node "${TMPDIR:-/tmp}/task10-split/repoint-pins.mjs" plugins/dforge/tests`
Expected: ten `repointed <file>` lines. The script throws, naming the file and the text, when an edit's text is not found exactly as often as expected (a file changed since this plan was written); it writes a file only after all of that file's edits matched. On a throw, report `BLOCKED` with the message.

- [ ] **Step 7: Run the pin tests and the size test again**

Run the loop from Step 5 again.
Expected: every line ends `exit 0`.

Run: `timeout 60 bash plugins/dforge/tests/skill-size.test.sh`
Expected: `14 passed, 0 failed`.

- [ ] **Step 8: Validate the repository and the plugin**

Run: `timeout 120 node scripts/validate-repository.mjs`
Expected: `Repository catalogs, manifests, versions, bundled links and the settings schema are valid.`

Run: `timeout 120 /root/.local/bin/claude plugin validate plugins/dforge`
Expected: `Validation passed`.

- [ ] **Step 9: Remove the scratch directory and commit**

```bash
rm -rf "${TMPDIR:-/tmp}/task10-split"
git add plugins/dforge/tests/skill-size.test.sh plugins/dforge/tests/skill-view.sh \
  plugins/dforge/skills/executing-plans/SKILL.md \
  plugins/dforge/skills/executing-plans/references/setup.md \
  plugins/dforge/skills/executing-plans/references/recovery.md \
  plugins/dforge/skills/executing-plans/references/ruling-seat.md \
  plugins/dforge/skills/executing-plans/references/switching.md \
  plugins/dforge/skills/executing-plans/references/finish-rulings.md \
  plugins/dforge/skills/executing-plans/references/rationalizations.md \
  plugins/dforge/skills/finishing-a-development-branch/SKILL.md \
  plugins/dforge/skills/finishing-a-development-branch/references/ui-proof.md \
  plugins/dforge/skills/finishing-a-development-branch/references/execute-choice.md \
  plugins/dforge/skills/finishing-a-development-branch/references/cleanup.md \
  plugins/dforge/skills/finishing-a-development-branch/references/rationalizations.md \
  plugins/dforge/skills/writing-skills/SKILL.md \
  plugins/dforge/skills/writing-skills/references/discovery-optimization.md \
  plugins/dforge/skills/writing-skills/references/match-the-form.md \
  plugins/dforge/tests/auto-run-skills.test.sh plugins/dforge/tests/final-phase.test.sh \
  plugins/dforge/tests/gates-manifest.test.sh plugins/dforge/tests/inline-mode.test.sh \
  plugins/dforge/tests/project-status.test.sh plugins/dforge/tests/task-step-text.test.sh \
  plugins/dforge/tests/review-route.test.sh plugins/dforge/tests/ui-ux-skill.test.sh \
  plugins/dforge/tests/waiting-text.test.sh plugins/dforge/tests/working-directory.test.sh
git commit -m "refactor(dforge): split three skills under 20 KB"
```

### Task 11: Build the pipeline manifest and report

**Files:**
- Create: `evals/tiers/lib/pipeline-manifest.mjs`
- Create: `evals/tiers/build-pipeline-manifest.mjs`
- Create: `evals/tiers/lib/pipeline-report.mjs`
- Create: `evals/tiers/cases/pipeline.tsv`
- Modify: `evals/tiers/lib/cases.mjs`
- Modify: `evals/tiers/report.mjs`
- Modify: `evals/tiers/README.md`
- Test: `evals/tiers/tests/pipeline-manifest.test.mjs`
- Test: `evals/tiers/tests/pipeline-report.test.mjs`

**Interfaces:**
- Consumes: Contracts → Pipeline eval: `PIPELINE_RESULTS` and `PIPELINE_COLUMNS` from `evals/tiers/lib/results.mjs` (Task 8), and the manifest format of `cases/pipeline.tsv`.
- Produces: Contracts → Pipeline eval: `evals/tiers/cases/pipeline.tsv` with its 12 cases, and `node evals/tiers/report.mjs --pipeline [--rep N]`. It also exports `finishedPlans`, `fixRounds`, `pickCases`, `manifestText` and `summarize`, which nothing outside this task uses.

**Items:** 11

**Depends on:** Task 8

**Implementer:** dforge:impl-sonnet-medium
**Evaluation:** files 2 - spec 0 - coupling 1 - risk 0 = 3

The manifest takes its cases from the finished dforge plans listed in `docs/dforge/plans/completed.md`, through the case builder the tier eval already has (`candidate` in `evals/tiers/lib/cases.mjs`: one commit message per task, a plan at the base commit, a runnable hidden test) and its golden check (the hidden tests fail at the base commit and pass at the result commit). A task's `fixRounds` is the number of commits between its own commit and the next task's commit that touch a file of its Files block. The ledger holds the true count but survives only on the machine that ran the plan, so this approximation is what a clone can recompute; the last task of a plan counts 0 because what follows it is the final review's fixes. The 12 cases are the tasks with fix rounds first, then the rest round-robin across plans. The report reads `results/pipeline.tsv` and needs neither the tier manifest nor `arms.json`.

- [ ] **Step 1: Write the failing tests**

Create `evals/tiers/tests/pipeline-report.test.mjs`:

```javascript
import assert from 'node:assert/strict';
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { after, test } from 'node:test';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { summarize } from '../lib/pipeline-report.mjs';
import { PIPELINE_COLUMNS } from '../lib/results.mjs';

const row = (arm, id, run, outcome, costUsd, seconds, rep = '1') => ({ rep, case: id, arm, run: String(run), outcome, costUsd: String(costUsd), seconds: String(seconds), dispatches: '3', fixRounds: '0', detail: '' });
const ROWS = [
  row('baseline', 'a', 1, 'PASS', 1, 100), row('baseline', 'a', 2, 'PASS', 2, 200),
  row('baseline', 'b', 1, 'PASS', 1.5, 150), row('baseline', 'b', 2, 'FAIL', 1.5, 300),
  row('candidate', 'a', 1, 'PASS', 0.5, 80), row('candidate', 'a', 2, 'PASS', 0.5, 90),
  row('candidate', 'b', 1, 'PASS', 0.5, 70), row('candidate', 'b', 2, 'ERROR', 0.5, 60),
];

test('summarize counts the cases that passed both runs, the cost and the median wall time per arm', () => {
  assert.deepEqual(summarize(ROWS), [
    { arm: 'baseline', cases: 2, pass2: 1, cost: 6, median: 175 },
    { arm: 'candidate', cases: 2, pass2: 1, cost: 2, median: 75 },
  ]);
});

test('a later row for the same case, arm and run replaces the earlier one', () => {
  const [baseline] = summarize([...ROWS, row('baseline', 'b', 2, 'PASS', 1.5, 120)]);
  assert.deepEqual(baseline, { arm: 'baseline', cases: 2, pass2: 2, cost: 6, median: 135 });
});

test('a case with one run recorded does not pass twice', () => {
  const [only] = summarize([row('baseline', 'a', 1, 'PASS', 1, 100)]);
  assert.deepEqual([only.cases, only.pass2], [1, 0]);
});

const top = mkdtempSync(join(tmpdir(), 'pipeline-report-test-'));
after(() => rmSync(top, { recursive: true, force: true }));

test('report --pipeline prints one line per arm for the repetition asked for', () => {
  const data = join(top, 'data');
  mkdirSync(join(data, 'results'), { recursive: true });
  const rows = [...ROWS, row('baseline', 'a', 1, 'PASS', 9, 999, '2')];
  writeFileSync(join(data, 'results/pipeline.tsv'), [PIPELINE_COLUMNS.join('\t'), ...rows.map(r => PIPELINE_COLUMNS.map(k => r[k]).join('\t'))].join('\n') + '\n');
  const run = args => spawnSync(process.execPath, [fileURLToPath(new URL('../report.mjs', import.meta.url)), ...args], { encoding: 'utf8', env: { ...process.env, TIER_EVAL_DATA: data } });
  const first = run(['--pipeline']);
  assert.equal(first.status, 0, first.stderr);
  assert.equal(first.stdout, [
    '# Pipeline eval - repetition 1', '',
    '- `baseline`: pass^2 1/2, cost $6.00, median 175s',
    '- `candidate`: pass^2 1/2, cost $2.00, median 75s', '',
  ].join('\n'));
  const second = run(['--pipeline', '--rep', '2']);
  assert.match(second.stdout, /- `baseline`: pass\^2 0\/1, cost \$9\.00, median 999s/);
  assert.match(run(['--pipeline', '--rep', '3']).stdout, /No pipeline runs recorded\./);
});
```

Create `evals/tiers/tests/pipeline-manifest.test.mjs`:

```javascript
import assert from 'node:assert/strict';
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { after, test } from 'node:test';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

// A small repository the harness reads its history from; set before the
// harness modules load, as they read the variable once.
const top = mkdtempSync(join(tmpdir(), 'pipeline-manifest-test-'));
const repo = join(top, 'repo');
mkdirSync(repo);
process.env.TIER_EVAL_ROOT = repo;
after(() => rmSync(top, { recursive: true, force: true }));
const git = (...args) => spawnSync('git', ['-c', 'user.name=t', '-c', 'user.email=t@example.invalid', ...args], { cwd: repo, encoding: 'utf8' });
function commit(files, message) {
  for (const [path, text] of Object.entries(files)) {
    mkdirSync(dirname(join(repo, path)), { recursive: true });
    writeFileSync(join(repo, path), text);
  }
  git('add', '-A');
  git('commit', '-q', '-m', message);
  return git('rev-parse', 'HEAD').stdout.trim();
}
git('init', '-q', '-b', 'main');
commit({ 'a.txt': '1' }, 'chore: start');
const one = commit({ 'src/one.sh': 'echo 1' }, 'feat: one');
commit({ 'src/one.sh': 'echo 1b' }, 'fix: one review');
commit({ 'other.sh': 'x' }, 'fix: unrelated');
const two = commit({ 'src/two.sh': 'echo 2' }, 'feat: two');
const end = commit({ 'src/two.sh': 'echo 2b' }, 'fix: final review');
const own = new Set(['feat: one', 'feat: two']);

const { PIPELINE_CASES, caseId, finishedPlans, fixRounds, manifestText, pickCases } = await import('../lib/pipeline-manifest.mjs');

test('finishedPlans reads the plan and merge commit of each completed line', () => {
  const text = [
    '- 2026-10-24 `docs/dforge/plans/2026-10-24-ui-ux-skill.md` — merged into `main` at c98d3488',
    '- 2026-10-27 `docs/dforge/plans/2026-10-26-faster-plans.md` — merged into `main` at 922e16c',
    'a note that names no plan',
  ].join('\n');
  assert.deepEqual(finishedPlans(text), [
    { plan: 'docs/dforge/plans/2026-10-24-ui-ux-skill.md', merge: 'c98d3488' },
    { plan: 'docs/dforge/plans/2026-10-26-faster-plans.md', merge: '922e16c' },
  ]);
});

test('fixRounds counts the commits on a task\'s files before the next task commit', () => {
  assert.equal(fixRounds({ result: one, merge: end, allowed: ['src/one.sh'], own }), 1);
  assert.equal(fixRounds({ result: one, merge: end, allowed: ['src/one.sh', 'other.sh'], own }), 2);
  assert.equal(fixRounds({ result: one, merge: end, allowed: ['src/two.sh'], own }), 0);
});

test('the last task of a plan has no fix rounds: what follows it is the final review', () => {
  assert.equal(fixRounds({ result: two, merge: end, allowed: ['src/two.sh'], own }), 0);
});

const c = (plan, task, fixRounds) => ({ plan, task, fixRounds, base: 'b'.repeat(40) });

test('pickCases takes fix-round tasks first, then fills round-robin across plans', () => {
  const list = [c('p1', 1, 0), c('p1', 2, 0), c('p1', 3, 1), c('p2', 1, 0), c('p2', 2, 2), c('p3', 1, 0)];
  assert.deepEqual(pickCases(list, 4).map(x => `${x.plan}:${x.task}`), ['p1:1', 'p1:3', 'p2:1', 'p2:2']);
  assert.deepEqual(pickCases(list, 2).map(x => `${x.plan}:${x.task}`), ['p1:3', 'p2:2']);
  assert.equal(pickCases(list).length, 6);
});

test('the manifest is a header and one tab-separated row per case', () => {
  const text = manifestText([{ plan: 'docs/dforge/plans/2026-10-24-ui-ux-skill.md', task: 2, base: 'a'.repeat(40), fixRounds: 1 }]);
  assert.equal(text, `case\tplan\ttask\tbase\tfixRounds\np-ui-ux-skill-t2\tdocs/dforge/plans/2026-10-24-ui-ux-skill.md\t2\t${'a'.repeat(40)}\t1\n`);
  assert.equal(caseId({ plan: 'docs/dforge/plans/2026-10-26-faster-plans.md', task: 11 }), 'p-faster-plans-t11');
});

test('the committed pipeline manifest has 12 well-formed cases', () => {
  const root = resolve(fileURLToPath(new URL('../../../', import.meta.url)));
  const lines = readFileSync(join(root, 'evals/tiers/cases/pipeline.tsv'), 'utf8').split('\n').filter(Boolean);
  assert.equal(lines[0], 'case\tplan\ttask\tbase\tfixRounds');
  assert.equal(lines.length - 1, PIPELINE_CASES);
  const rows = lines.slice(1).map(line => line.split('\t'));
  assert.equal(new Set(rows.map(r => r[0])).size, PIPELINE_CASES);
  for (const [id, plan, task, base, rounds] of rows) {
    assert.match(id, /^p-[a-z0-9-]+-t[0-9]+$/);
    assert.ok(existsSync(join(root, plan)), `${plan} exists`);
    assert.match(task, /^[0-9]+$/);
    assert.match(base, /^[0-9a-f]{40}$/);
    assert.match(rounds, /^[0-9]+$/);
  }
});
```

- [ ] **Step 2: Run the tests to see them fail**

Run: `timeout 120 node --test evals/tiers/tests/pipeline-report.test.mjs evals/tiers/tests/pipeline-manifest.test.mjs`
Expected: both files fail to load with `ERR_MODULE_NOT_FOUND` for `lib/pipeline-report.mjs` and `lib/pipeline-manifest.mjs`.

- [ ] **Step 3: Write the library modules and the builder**

Create `evals/tiers/lib/pipeline-report.mjs`:

```javascript
// summarize ROWS — one entry per arm, in order of first appearance, from the
// rows of results/pipeline.tsv. A cell is a case, an arm and a run; its last
// row settles it. pass2 counts the cases whose runs 1 and 2 both passed, cost
// sums every cell and median is the median wall time of the cells in seconds.
export function summarize(rows) {
  const cells = new Map();
  for (const r of rows) cells.set(`${r.arm}\t${r.case}\t${r.run}`, r);
  const arms = new Map();
  for (const r of cells.values()) {
    const arm = arms.get(r.arm) ?? { arm: r.arm, byCase: new Map(), cost: 0, times: [] };
    arm.byCase.set(r.case, { ...arm.byCase.get(r.case), [r.run]: r.outcome });
    arm.cost += Number(r.costUsd) || 0;
    arm.times.push(Number(r.seconds) || 0);
    arms.set(r.arm, arm);
  }
  return [...arms.values()].map(({ arm, byCase, cost, times }) => {
    const sorted = [...times].sort((a, b) => a - b);
    const mid = sorted.length >> 1;
    const median = sorted.length % 2 === 1 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2;
    return {
      arm,
      cases: byCase.size,
      pass2: [...byCase.values()].filter(runs => runs[1] === 'PASS' && runs[2] === 'PASS').length,
      cost,
      median: Math.round(median),
    };
  });
}
```

Create `evals/tiers/lib/pipeline-manifest.mjs`:

```javascript
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { git } from './sh.mjs';
import { candidate, planAt, slug } from './cases.mjs';
import { commitMessages, taskText, tasks } from './plan.mjs';

export const PIPELINE_CASES = 12;

// finishedPlans TEXT — { plan, merge } for each line of completed.md that names
// a plan and the commit that merged it.
export function finishedPlans(text) {
  return text.split('\n').flatMap(line => {
    const m = line.match(/`(docs\/dforge\/plans\/[^`]+\.md)` — merged into `[^`]+` at ([0-9a-f]{7,40})\b/);
    return m ? [{ plan: m[1], merge: m[2] }] : [];
  });
}

// fixRounds { result, merge, allowed, own } — the review-fix commits of one
// task: the commits after its RESULT commit, up to the next commit that
// carries a task of the plan (OWN is the set of their subjects), that touch a
// path of the task's Files block ALLOWED. A plan's last task has none: what
// follows it is the final review's fixes. This approximates the fix rounds the
// ledger counted, which survive only on the machine that ran the plan.
export function fixRounds({ result, merge, allowed, own }) {
  const log = git(['log', '--reverse', '--no-merges', '--ancestry-path', '--format=@@%H%x09%s', '--name-only', `${result}..${merge}`])
    .split('@@').filter(Boolean).map(block => {
      const [head, ...files] = block.split('\n').filter(Boolean);
      return { subject: head.slice(head.indexOf('\t') + 1), files };
    });
  const next = log.findIndex(entry => own.has(entry.subject));
  if (next < 0) return 0;
  return log.slice(0, next).filter(entry => entry.files.some(file => allowed.includes(file))).length;
}

// pipelineCandidates START DONE — every task of the finished plans DONE that
// the case builder accepts, as { plan, task, title, base, result, allowed,
// tests, fixRounds }.
export function pipelineCandidates(start, done) {
  const subjects = new Map();
  for (const line of git(['log', '--format=%H%x09%s', start]).split('\n').filter(Boolean)) {
    const [sha, subject] = line.split('\t');
    subjects.set(subject, [...(subjects.get(subject) ?? []), sha]);
  }
  const tmp = mkdtempSync(join(tmpdir(), 'tier-eval-pipeline-'));
  const out = [];
  try {
    for (const { plan, merge } of done) {
      const head = planAt(start, plan, join(tmp, 'head'));
      if (head === null) continue;
      const list = tasks(head);
      const own = new Set(list.flatMap(({ n }) => commitMessages(taskText(head, n) ?? '')));
      for (const { n, title } of list) {
        const c = candidate(plan, n, taskText(head, n), subjects, join(tmp, 'work'));
        if (c.reason) continue;
        out.push({ plan, task: n, title, ...c, fixRounds: fixRounds({ result: c.result, merge, allowed: c.allowed, own }) });
      }
    }
  } finally {
    rmSync(tmp, { recursive: true, force: true });
  }
  return out;
}

// pickCases LIST TOTAL — TOTAL cases: first those that needed fix rounds, most
// rounds first, then the rest round-robin across plans in plan order.
export function pickCases(list, total = PIPELINE_CASES) {
  const byTask = (a, b) => a.plan.localeCompare(b.plan) || a.task - b.task;
  const picked = list.filter(c => c.fixRounds > 0).sort((a, b) => b.fixRounds - a.fixRounds || byTask(a, b)).slice(0, total);
  const byPlan = new Map();
  for (const c of list.filter(c => !picked.includes(c)).sort(byTask)) byPlan.set(c.plan, [...(byPlan.get(c.plan) ?? []), c]);
  while (picked.length < total && [...byPlan.values()].some(rest => rest.length > 0)) {
    for (const rest of byPlan.values()) {
      if (rest.length > 0 && picked.length < total) picked.push(rest.shift());
    }
  }
  return picked.sort(byTask);
}

export const caseId = c => `p-${slug(c.plan)}-t${c.task}`;

export function manifestText(cases) {
  const rows = cases.map(c => [caseId(c), c.plan, c.task, c.base, c.fixRounds].join('\t'));
  return ['case\tplan\ttask\tbase\tfixRounds', ...rows].join('\n') + '\n';
}
```

Create `evals/tiers/build-pipeline-manifest.mjs`:

```javascript
#!/usr/bin/env node
// Choose the 12 cases of the pipeline stage from the finished plans listed in
// docs/dforge/plans/completed.md and write cases/pipeline.tsv. Every case is
// golden-checked first: its hidden tests fail at the base commit and pass at
// the result commit. Tasks that needed fix rounds come first.
// Usage: node evals/tiers/build-pipeline-manifest.mjs
// Exit: 0 written; 1 fewer than 12 usable cases.
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { DATA, ROOT, git } from './lib/sh.mjs';
import { golden } from './lib/cases.mjs';
import { PIPELINE_CASES, finishedPlans, manifestText, pickCases, pipelineCandidates } from './lib/pipeline-manifest.mjs';

const JOBS = 6;
const MANIFEST = resolve(DATA, 'cases/pipeline.tsv');
const start = git(['rev-parse', 'HEAD']).trim();
const done = finishedPlans(readFileSync(resolve(ROOT, 'docs/dforge/plans/completed.md'), 'utf8'));
const queue = pipelineCandidates(start, done);
const total = queue.length;
const usable = [];
await Promise.all(Array.from({ length: JOBS }, async () => {
  for (let c = queue.shift(); c; c = queue.shift()) {
    if (await golden(c) === null) usable.push(c);
  }
}));
const picked = pickCases(usable);
if (picked.length < PIPELINE_CASES) {
  console.error(`build-pipeline-manifest: ${picked.length} usable cases of ${total}, need ${PIPELINE_CASES}`);
  process.exit(1);
}
mkdirSync(dirname(MANIFEST), { recursive: true });
writeFileSync(MANIFEST, manifestText(picked));
console.log(`build-pipeline-manifest: ${picked.length} cases (${picked.filter(c => c.fixRounds > 0).length} with a fix round) from ${usable.length} usable of ${total}`);
```

- [ ] **Step 4: Export the case builder's `candidate`**

In `evals/tiers/lib/cases.mjs`, replace the line

```javascript
function candidate(plan, task, headText, subjects, tmp) {
```

with

```javascript
export function candidate(plan, task, headText, subjects, tmp) {
```

- [ ] **Step 5: Add `--pipeline` to the report**

In `evals/tiers/report.mjs`, replace

```javascript
// Usage: node evals/tiers/report.mjs [--rep N] [--pass P]
```

with

```javascript
// Usage: node evals/tiers/report.mjs [--rep N] [--pass P]
//        node evals/tiers/report.mjs --pipeline [--rep N]
// --pipeline prints the pipeline stage's pass^2, cost and median wall time per arm.
```

Replace

```javascript
import { GRADES, RESULTS, readTsv, scored } from './lib/results.mjs';
```

with

```javascript
import { summarize } from './lib/pipeline-report.mjs';
import { GRADES, PIPELINE_RESULTS, RESULTS, readTsv, scored } from './lib/results.mjs';
```

Replace

```javascript
const { values } = parseArgs({ options: { rep: { type: 'string', default: '1' }, pass: { type: 'string', default: '1' } } });
const rep = values.rep;
```

with

```javascript
const { values } = parseArgs({ options: { rep: { type: 'string', default: '1' }, pass: { type: 'string', default: '1' }, pipeline: { type: 'boolean', default: false } } });
const rep = values.rep;
if (values.pipeline) {
  const lines = [`# Pipeline eval - repetition ${rep}`, ''];
  const arms = summarize(readTsv(PIPELINE_RESULTS).filter(r => r.rep === rep));
  if (arms.length === 0) lines.push('No pipeline runs recorded.');
  for (const a of arms) lines.push(`- \`${a.arm}\`: pass^2 ${a.pass2}/${a.cases}, cost $${a.cost.toFixed(2)}, median ${a.median}s`);
  console.log(lines.join('\n'));
  process.exit(0);
}
```

- [ ] **Step 6: Run the unit tests**

Run: `timeout 120 node --test evals/tiers/tests/pipeline-report.test.mjs evals/tiers/tests/pipeline-manifest.test.mjs`
Expected: all pass except the last test of `pipeline-manifest.test.mjs`, "the committed pipeline manifest has 12 well-formed cases", which fails with `ENOENT` for `cases/pipeline.tsv` until Step 7.

- [ ] **Step 7: Build the manifest**

The golden check runs each candidate's hidden tests twice, six candidates at a time, so the build takes up to about 25 minutes. Run it as a background command and wait for its completion notification:

```bash
timeout 3000 node evals/tiers/build-pipeline-manifest.mjs
```

Expected: exit 0 and a line like `build-pipeline-manifest: 12 cases (5 with a fix round) from 25 usable of 28`, with `evals/tiers/cases/pipeline.tsv` written: a header row and 12 rows, at least one with `fixRounds` above 0. Exit 1 (`N usable cases of M, need 12`) means fewer than 12 candidates passed the golden check; read the last lines of the output, do not lower the number 12 or edit the file by hand, and report `BLOCKED` with that output. The ids, bases and counts may differ from the example because the history has grown since.

- [ ] **Step 8: Document the commands**

In `evals/tiers/README.md`, after the table row

```markdown
| `node evals/tiers/report.mjs [--rep N] [--pass P]` | Prints the decision table, reading review grades of pass P |
```

add the rows

```markdown
| `node evals/tiers/build-pipeline-manifest.mjs` | Golden-checks the tasks of the finished plans in `docs/dforge/plans/completed.md`, picks 12 (tasks with fix rounds first) and writes `cases/pipeline.tsv` |
| `node evals/tiers/report.mjs --pipeline [--rep N]` | Prints pass^2, total cost and median wall time per pipeline arm from `results/pipeline.tsv` |
```

and in the Files table, after the `cases/slices-excluded.tsv` row, add

```markdown
| `cases/pipeline.tsv` | The 12 pipeline cases: case, plan, task, base commit and fix rounds |
```

- [ ] **Step 9: Run every harness test**

Run: `timeout 300 node --test evals/tiers/tests/*.test.mjs`
Expected: all tests pass, including "the committed pipeline manifest has 12 well-formed cases".

- [ ] **Step 10: Commit**

```bash
git add evals/tiers/lib/pipeline-manifest.mjs evals/tiers/build-pipeline-manifest.mjs evals/tiers/lib/pipeline-report.mjs \
  evals/tiers/cases/pipeline.tsv evals/tiers/lib/cases.mjs evals/tiers/report.mjs evals/tiers/README.md \
  evals/tiers/tests/pipeline-manifest.test.mjs evals/tiers/tests/pipeline-report.test.mjs
git commit -m "feat(evals): add the pipeline manifest and report"
```

### Task 12: Read the suite record in task-step verdict

**Files:**
- Modify: `plugins/dforge/scripts/task-step`
- Modify: `plugins/dforge/tests/task-step.test.sh`
- Test: `plugins/dforge/tests/task-step-suite.test.sh`

**Interfaces:**
- Consumes: `scripts/suite-run`'s record: `<state>/suites.tsv` rows `<HEAD> <clean|dirty> <command %q> <exit> <log> <epoch>`, unchanged by this plan.
- Produces: Contracts → Suite command and record: `task-step start … --suite '<command>'`, the `suite` field of the step file, the first-start ledger ruling, `task-step verdict`'s one suite line and exit 8, and the top-level functions `suite_key`, `suite_row`, `suite_failing_lines` and the empty seam `suite_base_lines`.

**Items:** 1

**Depends on:** Task 9

**Implementer:** dforge:impl-sonnet-high
**Evaluation:** files 1 - spec 0 - coupling 2 - risk 2 = 5

`task-step start` learns the suite command, and `task-step verdict` stops trusting a review alone: it looks up the suite-run record for the command at the review head. A pass, or failures that are all baseline, lets the task complete; any other failure becomes an Important finding in the fix file; no record exits 8 so the controller runs the suite and asks again. This task defines the baseline seam `suite_base_lines` as an empty function, so every failing line is a finding until Task 13 replaces it. A group's verdict checks the suite of its last member; a wave group checks none (its merged check is its suite), so it reports `suite: none recorded`. The digest gains one line, so the cannot-verify room shrinks by one line to keep the 20-line limit, and the one existing test that counted a cut cannot-verify list follows (Step 5). The task depends on Task 9 only because both edit `plugins/dforge/tests/task-step.test.sh`: it runs after Task 9's pin changes there. Task 15 documents the new line and exit in `reference/delegated-task.md`; this task edits nothing under `plugins/dforge/reference/` or `plugins/dforge/skills/`.

- [ ] **Step 1: Write the failing test**

Create `plugins/dforge/tests/task-step-suite.test.sh`:

```bash
#!/usr/bin/env bash
# task-step records a task's suite command at start and reads the suite-run
# record at the review head in verdict. Each case runs against a throwaway
# repository; suite-run writes the records the verdict reads.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
P="$HERE/.."
STEP="$P/scripts/task-step"
SUITE="$P/scripts/suite-run"

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}

TMP=$(mktemp -d)
if command -v cygpath >/dev/null 2>&1; then TMP=$(cygpath -m "$TMP"); fi
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
mkdir -p "$HOME/.claude"
export MSYS_NO_PATHCONV=1 GIT_CONFIG_NOSYSTEM=1 DFORGE_NO_SETTINGS=1
unset DFORGE_BUDGET DR_SUPERPOWERS_BUDGET CLAUDE_CONFIG_DIR CODEX_HOME CLAUDE_CODE_SESSION_ID AR_SESSION CLAUDE_PROJECT_DIR

REPO="$TMP/repo"
git init -q "$REPO"
cd "$REPO" || exit 1
git config user.name Darkraise
git config user.email dark@example.invalid
mkdir docs sub

sed 's/^|//' > docs/plan.md <<'PLAN'
|# Suite Fixture Plan
|
|**Goal:** Fixture.
|
|**Execution:** subagent — `claude --model sonnet --effort high` — fixture
|
|## Global Constraints
|
|- Fixture constraint.
|
|## Contracts
|
|- Fixture contract.
|
|## Task index
|
|1. first
|2. second
|3. third
|
|### Task 1: first
|
|**Implementer:** dforge:impl-sonnet-low
|**Evaluation:** files 0 - spec 0 - coupling 0 - risk 0 = 0
|
|Body one.
|
|### Task 2: second
|
|**Implementer:** dforge:impl-sonnet-low
|**Evaluation:** files 0 - spec 0 - coupling 0 - risk 0 = 0
|
|Body two.
|
|### Task 3: third
|
|**Implementer:** dforge:impl-sonnet-low
|**Evaluation:** files 0 - spec 0 - coupling 0 - risk 0 = 0
|
|Body three.
PLAN
printf '%s\n' 'cat result.txt' "grep -qx green result.txt" > suite.sh
printf 'green\n' > result.txt
git add -A && git commit -qm "docs: add fixture"

CMD='bash suite.sh'
KEY='bash -c bash\ suite.sh'
winpath() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s\n' "$1"; fi; }
WS=$(winpath "$(bash "$P/scripts/sdd-workspace" docs/plan.md)")
LEDGER="$WS/progress.md"
rm -f "$WS"/*
n=0
step() { out=$(bash "$STEP" "$@" 2>"$TMP/err"); rc=$?; err=$(cat "$TMP/err"); }
commit_result() { # commit_result <result.txt lines...> — a new commit; sets HEAD_SHA
  n=$((n + 1))
  printf '%s\n' "$@" > result.txt
  git add result.txt && git commit -qm "result $n"
  HEAD_SHA=$(git rev-parse HEAD | tr -d '\r')
}
set_review() { # set_review <task> <head> <checkout> — the state the review step leaves
  jq --arg h "$2" --arg c "$3" '.reviewHead = $h | .reviewCheck = {cwd: $c, head: $h, dirty: []}' "$WS/task-$1-step.json" > "$TMP/s.json" \
    && mv "$TMP/s.json" "$WS/task-$1-step.json"
}
report() { # report <file> — a passing task report
  printf '%s\n' '## Verdict' 'spec: pass' 'quality: approved' 'scores: spec 17 / scope 18 / verification 16 / quality 16' > "$1"
}
run_suite() { bash "$SUITE" -- bash -c "$CMD" >/dev/null 2>&1; true; }
first_block() { awk '{ sub(/\r$/, "") } /^$/ { exit } { print }' "$1" | tr '\n' ';'; }

# --- start --suite ---
step start docs/plan.md 1 --suite "$CMD"
check "start --suite: exit 0" "$rc" "0"
check "start --suite: the command is the step file's suite field" "$(jq -r '.suite' "$WS/task-1-step.json" | tr -d '\r')" "$CMD"
check "start --suite: the first start logs the ruling" "$(grep -cxF "Task 1: Ruling: suite command — $CMD — none" "$LEDGER")" "1"
step start docs/plan.md 2 --suite "$CMD"
check "start --suite: a second start adds no ruling" "$(grep -c 'Ruling: suite command' "$LEDGER")" "1"
step start docs/plan.md 3
check "start without --suite: no suite field" "$(jq -r '.suite // "absent"' "$WS/task-3-step.json" | tr -d '\r')" "absent"
step start docs/plan.md 3 --suite
check "start --suite without a command exits 2" "$rc" "2"
step review docs/plan.md 1 --suite x
check "review does not take --suite" "$rc" "2"

# --- verdict: no suite recorded ---
HEAD_SHA=$(git rev-parse HEAD | tr -d '\r')
set_review 3 "$HEAD_SHA" "$REPO"
report "$WS/task-3-review-report.md"
step verdict docs/plan.md 3
check "verdict, no suite field: exit 0" "$rc" "0"
check "verdict, no suite field: says none recorded" "$(grep '^suite: ' <<<"$out")" "suite: none recorded"

# --- verdict: no row at the review head ---
set_review 1 "$HEAD_SHA" "$REPO"
report "$WS/task-1-review-report.md"
step verdict docs/plan.md 1
check "verdict, no row: exit 8" "$rc" "8"
check "verdict, no row: names the command" "$(grep '^suite: ' <<<"$out")" "suite: not run ($CMD)"
check "verdict, no row: writes no fix file" "$(ls "$WS"/task-1-fix-*.md 2>/dev/null | wc -l | tr -d ' ')" "0"

# --- verdict: a passing row ---
run_suite
check "suite-run records the key verdict matches" "$(awk -F'\t' -v h="$HEAD_SHA" '$1 == h { print $3 }' .dforge/suites.tsv | tail -n 1)" "$KEY"
step verdict docs/plan.md 1
check "verdict, passing row: exit 0" "$rc" "0"
check "verdict, passing row: the suite line" "$(grep '^suite: ' <<<"$out")" "suite: pass (clean)"
check "verdict, passing row: no fix file" "$(grep '^fix: ' <<<"$out")" "fix: none"

# --- verdict: a dirty passing row counts ---
commit_result green green
set_review 1 "$HEAD_SHA" "$REPO"
printf 'x\n' > untracked.txt
run_suite
rm -f untracked.txt
step verdict docs/plan.md 1
check "verdict, dirty passing row: counts as a pass" "$rc $(grep '^suite: ' <<<"$out")" "0 suite: pass (dirty)"

# --- verdict: a failing row becomes findings ---
commit_result 'not ok 1 - alpha' 'not ok 2 - beta'
H7=${HEAD_SHA:0:7}
set_review 1 "$HEAD_SHA" "$REPO"
run_suite
step verdict docs/plan.md 1
check "verdict, failing row: exit 0" "$rc" "0"
check "verdict, failing row: the suite line" "$(grep '^suite: red' <<<"$out")" "suite: red (2 failing, 0 baseline)"
check "verdict, failing row: the findings line counts them" "$(grep '^findings: ' <<<"$out")" "findings: 0 Critical, 2 Important, 0 Minor"
check "verdict, failing row: one finding line per failing test" "$(grep '^Important ' <<<"$out" | tr '\n' ';')" \
  "Important 1 suite:0 — suite: not ok - alpha fails at $H7;Important 1 suite:0 — suite: not ok - beta fails at $H7;"
check "verdict, failing row: the fix line names the file" "$(grep '^fix: ' <<<"$out")" "fix: $WS/task-1-fix-1.md (2 findings)"
check "verdict, failing row: the fix file's bullets" "$(first_block "$WS/task-1-fix-1.md")" \
  "- suite: suite: not ok - alpha fails at $H7;- suite: suite: not ok - beta fails at $H7;"
check "verdict, failing row: exactly one suite line" "$(grep -c '^suite: ' <<<"$out")" "1"

# --- verdict: a failing run with no failing test line still fails the task ---
commit_result broken
H7=${HEAD_SHA:0:7}
set_review 1 "$HEAD_SHA" "$REPO"
rm -f "$WS"/task-1-fix-*.md
run_suite
step verdict docs/plan.md 1
check "verdict, failing run without test lines: one failing line" "$(grep '^suite: red' <<<"$out")" "suite: red (1 failing, 0 baseline)"
check "verdict, failing run without test lines: the finding names the exit code" "$(grep '^Important ' <<<"$out")" "Important 1 suite:0 — suite: command exit 1 fails at $H7"

# --- verdict: a row at another head or from a subdirectory does not match ---
commit_result green green green
set_review 1 "$HEAD_SHA" "$REPO"
(cd sub && bash "$SUITE" -- bash -c "$CMD" >/dev/null 2>&1; true)
step verdict docs/plan.md 1
check "verdict, row run from a subdirectory: not run, exit 8" "$rc $(grep '^suite: ' <<<"$out")" "8 suite: not run ($CMD)"
run_suite
commit_result green green green green
set_review 1 "$HEAD_SHA" "$REPO"
step verdict docs/plan.md 1
check "verdict, row at an earlier head: not run, exit 8" "$rc" "8"

# --- verdict: exits 5 and 6 come before 8 ---
set_review 1 "$HEAD_SHA" "$REPO"
rm -f "$WS/task-1-review-report.md"
step verdict docs/plan.md 1
check "verdict, no report and no row: exit 5" "$rc" "5"
report "$WS/task-1-review-report.md"
printf 'dirty\n' >> docs/plan.md
step verdict docs/plan.md 1
git checkout -q -- docs/plan.md
check "verdict, tracked file changed and no row: exit 6" "$rc" "6"

# --- verdict --cwd reads the state of that checkout ---
git worktree add -q --detach "$TMP/wt" HEAD
WT=$TMP/wt
git -C "$WT" -c user.name=Darkraise -c user.email=dark@example.invalid commit -q --allow-empty -m "wave work"
WT_SHA=$(git -C "$WT" rev-parse HEAD | tr -d '\r')
set_review 2 "$WT_SHA" "$WT"
report "$WS/task-2-review-report.md"
(cd "$WT" && bash "$SUITE" -- bash -c "$CMD" >/dev/null 2>&1; true)
step verdict docs/plan.md 2 --cwd "$WT"
check "verdict --cwd: the row in that checkout's state counts" "$rc $(grep '^suite: ' <<<"$out")" "0 suite: pass (clean)"
step verdict docs/plan.md 2
check "verdict without --cwd: the checkout's own state has no such row" "$rc" "8"

# --- verdict --group takes the suite of the last member ---
run_suite
G_HEAD=$HEAD_SHA
jq -n --arg h "$G_HEAD" --arg c "$REPO" '{tasks: [1, 2], reviewHead: $h, t0: 0, reviewChecks: [{cwd: $c, head: $h, dirty: []}]}' > "$WS/group-1,2-step.json"
{
  printf '## Verdict\n'
  for t in 1 2; do
    printf 'Task %s spec: pass\nTask %s quality: approved\nTask %s scores: spec 17 / scope 17 / verification 17 / quality 17\n' "$t" "$t" "$t"
  done
} > "$WS/group-1,2-review-report.md"
step verdict docs/plan.md 1 2 --group
check "verdict --group: the last member's suite is checked" "$rc $(grep '^suite: ' <<<"$out")" "0 suite: pass (clean)"
jq '.wave = 1' "$WS/task-2-step.json" > "$TMP/w.json" && mv "$TMP/w.json" "$WS/task-2-step.json"
rm -f .dforge/suites.tsv
step verdict docs/plan.md 1 2 --group
check "verdict --group: a wave group has no per-group suite" "$rc $(grep '^suite: ' <<<"$out")" "0 suite: none recorded"

git worktree remove --force "$WT"
printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
```

- [ ] **Step 2: Run the test to see it fail**

Run: `timeout 300 bash plugins/dforge/tests/task-step-suite.test.sh`
Expected: `7 passed, 27 failed`, with FAIL lines including "start --suite: exit 0" (task-step exits 2: `--suite` is not an option yet) and "verdict, no row: exit 8".

- [ ] **Step 3: Edit task-step**

Apply these eleven edits to `plugins/dforge/scripts/task-step`, in order. Every "replace" text occurs exactly once; every "insert" anchor occurs exactly once.

**Edit 1.** Replace

```bash
# Usage: task-step start  PLAN_FILE N [M ...] [--wave K] [--reset]
```

with

```bash
# Usage: task-step start  PLAN_FILE N [M ...] [--wave K] [--reset] [--suite COMMAND]
```

**Edit 2.** Replace

```bash
# not run, or (verdict) a tracked file changed during the review; 7 the fix
# loop is at its two-round cap.
```

with

```bash
# not run, or (verdict) a tracked file changed during the review; 7 the fix
# loop is at its two-round cap; 8 (verdict) the step file names a suite command
# with no record at the review head.
```

**Edit 3.** In the usage message, replace `usage: task-step start PLAN_FILE N [M ...] [--wave K] [--reset] |` with `usage: task-step start PLAN_FILE N [M ...] [--wave K] [--reset] [--suite COMMAND] |`.

**Edit 4.** Insert this immediately before the line `rr_usage() {`:

```bash
# suite_key COMMAND: the key suite-run records for `suite-run -- bash -c COMMAND`
# run from the top level: column 3 of suites.tsv.
suite_key() {
  local k
  k=$(printf '%q ' bash -c "$1")
  printf '%s\n' "${k% }"
}

# suite_row STEP_FILE SHA [DIR]: the last suites.tsv row whose HEAD is SHA and
# whose command is the step file's `suite`, from the state directory of DIR
# (default: the current directory). Prints nothing without a row or a suite.
suite_row() {
  local cmd sdir key
  cmd=$(jq -r '.suite // empty' "$1" 2>/dev/null | tr -d '\r')
  [ -n "$cmd" ] || return 0
  sdir=$(cd "${3:-.}" && bash "$HERE/dforge-path" state | tr -d '\r') || return 0
  [ -f "$sdir/suites.tsv" ] || return 0
  key=$(suite_key "$cmd")
  tr -d '\r' < "$sdir/suites.tsv" | RH=$2 K=$key awk -F'\t' '
    $1 == ENVIRON["RH"] && $3 == ENVIRON["K"] { row = $0 }
    END { if (row != "") print row }'
}

# suite_failing_lines LOG: the failing lines of a suite log, numbers dropped
# from TAP "not ok" lines so the same test reads the same at two commits.
suite_failing_lines() {
  [ -f "$1" ] || return 0
  tr -d '\r' < "$1" | grep -E '^[[:space:]]*(not ok|\(fail\)|FAIL)' | cut -c1-200 | sed -E 's/^([[:space:]]*not ok) [0-9]+/\1/'
}

suite_base_lines() { # STEP_FILE N [DIR]
  return 0
}

```

**Edit 5.** Replace

```bash
ids=() wave="" reset=0 base_arg="" head_arg="" cwd_arg="" vgroup=0 rereview_arg=""
```

with

```bash
ids=() wave="" reset=0 base_arg="" head_arg="" cwd_arg="" vgroup=0 rereview_arg="" suite_arg=""
```

**Edit 6.** Replace

```bash
    --reset) [ "$sub" = start ] || usage; reset=1; shift ;;
```

with

```bash
    --reset) [ "$sub" = start ] || usage; reset=1; shift ;;
    --suite) [ "$sub" = start ] && [ $# -ge 2 ] && [ -n "$2" ] || usage; suite_arg=$2; shift 2 ;;
```

**Edit 7.** Replace

```bash
      && mv "$state.tmp" "$state"
  fi

  if [ -z "$exec_id" ]; then
```

with

```bash
      && mv "$state.tmp" "$state"
  fi

  if [ -n "$suite_arg" ]; then
    jq --arg s "$suite_arg" '.suite = $s' "$state" > "$state.tmp" && mv "$state.tmp" "$state" || die "cannot update $state"
    ledger_init
    if [ "$(tr -d '\r' < "$ledger" | grep -cF 'Ruling: suite command —')" -eq 0 ]; then
      printf 'Task %s: Ruling: suite command — %s — none\n' "$first" "$suite_arg" >> "$ledger"
    fi
  fi

  if [ -z "$exec_id" ]; then
```

**Edit 8.** Insert this immediately before the line `do_verdict() {`:

```bash
# suite_check: reads the suite record for the review head and sets suite_state
# (none|pass|red|notrun) and suite_line; the findings a red suite adds are
# written to $TMP/suite-findings, one "task, severity, file, line, summary" row each.
suite_check() {
  local target st rh head7 row kind code log fails nfail nnew nbase line suite_cmd
  suite_state=none suite_line="suite: none recorded"
  : > "$TMP/suite-findings"
  target=${members[${#members[@]}-1]}
  st=$ws/task-$target-step.json
  [ -f "$st" ] || return 0
  suite_cmd=$(jq -r '.suite // empty' "$st" | tr -d '\r')
  [ -n "$suite_cmd" ] || return 0
  if [ "$vgroup" -eq 1 ] && [ -n "$(jq -r '.wave // empty' "$st" | tr -d '\r')" ]; then return 0; fi
  rh=$(jq -r '.reviewHead // empty' "$vstate" | tr -d '\r')
  head7=${rh:0:7}
  row=$(suite_row "$st" "$rh" "${cwd_arg:-.}")
  if [ -z "$row" ]; then
    suite_state=notrun suite_line="suite: not run ($suite_cmd)"
    return 0
  fi
  IFS=$'\t' read -r _ kind _ code log _ <<<"$row"
  if [ "$code" = 0 ]; then
    suite_state=pass suite_line="suite: pass ($kind)"
    return 0
  fi
  suite_state=red
  fails=$(suite_failing_lines "$log")
  [ -n "$fails" ] || fails="command exit $code"
  printf '%s\n' "$fails" > "$TMP/suite-fails"
  suite_base_lines "$st" "$target" "${cwd_arg:-.}" > "$TMP/suite-base"
  if [ -s "$TMP/suite-base" ]; then grep -vxF -f "$TMP/suite-base" "$TMP/suite-fails" > "$TMP/suite-new"; else cp "$TMP/suite-fails" "$TMP/suite-new"; fi
  nfail=$(grep -c '' "$TMP/suite-fails")
  nnew=$(grep -c '' "$TMP/suite-new")
  nbase=$((nfail - nnew))
  suite_line="suite: red ($nnew failing, $nbase baseline)"
  head -n 20 "$TMP/suite-new" | while IFS= read -r line; do
    printf '%s\tImportant\tsuite\t0\tsuite: %s fails at %s\n' "$target" "${line//$'\t'/ }" "$head7"
  done > "$TMP/suite-findings"
}

```

**Edit 9.** Replace

```bash
  [ "$rc" -eq 0 ] || die "$rpath: ${recs#E$'\t'}" 5

  : > "$TMP/serious"
```

with

```bash
  [ "$rc" -eq 0 ] || die "$rpath: ${recs#E$'\t'}" 5

  suite_check
  if [ "$suite_state" = notrun ]; then
    if [ "$vgroup" -eq 1 ]; then printf 'group %s: verdict from %s\n' "$list" "$rpath"
    else printf 'task %s: verdict from %s\n' "$idlist" "$rpath"; fi
    printf '%s\n' "$suite_line"
    exit 8
  fi

  : > "$TMP/serious"
```

**Edit 10.** Insert this immediately before the line `for t in "${members[@]}"; do` that is followed by the line `n=$(awk -F'\t' -v t="$t" ...`:

```bash
  if [ -s "$TMP/suite-findings" ]; then
    cat "$TMP/suite-findings" >> "$TMP/serious"
    while IFS=$'\t' read -r task sev file line one; do
      imp=$((imp + 1))
      flines+=("$sev $task $file:$line — $one")
    done < "$TMP/suite-findings"
  fi

```

**Edit 11.** Replace

```bash
  [ "${#flines[@]}" -eq 0 ] || printf '%s\n' "${flines[@]}"
  # Every line but the finding lines fits in 20: the first, the verdict lines,
  # and the findings, fix, minor, check and budget lines leave this many. A
  # group too large for that still gets one line saying how many items wait.
  room=$((20 - nv - 6))
```

with

```bash
  [ "${#flines[@]}" -eq 0 ] || printf '%s\n' "${flines[@]}"
  printf '%s\n' "$suite_line"
  # Every line but the finding lines fits in 20: the first, the verdict lines,
  # and the findings, suite, fix, minor, check and budget lines leave this many. A
  # group too large for that still gets one line saying how many items wait.
  room=$((20 - nv - 7))
```

- [ ] **Step 4: Run the new test to see it pass**

Run: `timeout 300 bash plugins/dforge/tests/task-step-suite.test.sh`
Expected: `34 passed, 0 failed`.

- [ ] **Step 5: Follow the one digest-budget pin in the existing test**

The five-member group digest in `plugins/dforge/tests/task-step.test.sh` now has one more line (`suite: none recorded`), so its 12 cannot-verify items are cut to the "more in the report" line alone. In that file replace

```bash
check "verdict, five members: the cannot-verify list is cut" "$(grep -c '^cannot-verify: (Task 6)' <<<"$gr_out")" "1"
check "verdict, five members: and says how many it cut" "$(grep -c '^cannot-verify: 11 more in the report$' <<<"$gr_out")" "1"
```

with

```bash
check "verdict, five members: the cannot-verify list is cut" "$(grep -c '^cannot-verify: (Task 6)' <<<"$gr_out")" "0"
check "verdict, five members: and says how many it cut" "$(grep -c '^cannot-verify: 12 more in the report$' <<<"$gr_out")" "1"
```

The line `check "verdict, five members: at most 20 lines besides the finding lines" … "20"` stays as it is and now passes because of the changed `room` arithmetic (Edit 11).

- [ ] **Step 6: Run the neighbouring suites**

Run:

```bash
timeout 900 bash plugins/dforge/tests/task-step.test.sh | tail -n 3
timeout 600 bash plugins/dforge/tests/task-step-text.test.sh | tail -n 1
timeout 900 bash plugins/dforge/tests/task-loop-steps.acceptance.test.sh | tail -n 1
timeout 300 bash plugins/dforge/tests/suite-run.test.sh | tail -n 1
```

Expected: each ends `<n> passed, 0 failed` (for `task-step.test.sh` `410 passed, 0 failed` on main before Task 9's pin edits; the count may differ, the failed count may not).

- [ ] **Step 7: Commit**

```bash
git add plugins/dforge/scripts/task-step plugins/dforge/tests/task-step.test.sh plugins/dforge/tests/task-step-suite.test.sh
git commit -m "feat(dforge): read the suite record in verdict"
```

### Task 13: Compare suite failures against the base

**Files:**
- Modify: `plugins/dforge/scripts/task-step` (the suite helper block Task 12 added, and `cmd_rereview`)
- Create: `plugins/dforge/tests/task-step-base.test.sh`

**Interfaces:**
- Consumes: Contracts "Suite command and record" (Task 12): the step file's `suite` field, the top-level functions `suite_key`, `suite_row`, `suite_failing_lines`, the seam `suite_base_lines` (exactly `suite_base_lines() { # STEP_FILE N [DIR]`, `  return 0`, `}`) and `do_verdict`'s single call to it on a failing row.
- Produces: Contracts "Base runs": `run_at_base BASE_SHA COMMAND OUT_LOG`, the real `suite_base_lines`, `<workspace>/task-<N>-base-failures.txt`, `<workspace>/task-<N>-base.log`, and `task-step rereview PLAN_FILE N --covered` skipping only on a covered suite. It also adds the internal helper `suite_gap STEP_FILE N SHA [DIR]` (no later task calls it).

**Items:** 1

**Depends on:** Task 12

**Implementer:** dforge:impl-sonnet-high
**Evaluation:** files 1 - spec 0 - coupling 2 - risk 2 = 5

- [ ] **Step 1: Write the failing test**

Create `plugins/dforge/tests/task-step-base.test.sh`. It drives `task-step` end to end in a throwaway repository: a suite script whose failing lines come from a tracked file, a `**Worktree setup:**` header line that marks the base worktree, and a marker file that counts how often the suite ran where.

```bash
#!/usr/bin/env bash
# task-step compares a red suite with the base commit's failures: verdict reuses
# a base row, then task-<N>-base-failures.txt, then runs the suite once at the
# base in a temporary worktree; rereview --covered skips only on a covered suite.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
P="$HERE/.."
S="$P/scripts"

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}

TMP=$(mktemp -d)
if command -v cygpath >/dev/null 2>&1; then TMP=$(cygpath -m "$TMP"); fi
winpath() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s\n' "$1"; fi; }
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" MSYS_NO_PATHCONV=1 GIT_CONFIG_NOSYSTEM=1 DFORGE_NO_SETTINGS=1
mkdir -p "$HOME/.claude"
unset DFORGE_BUDGET DR_SUPERPOWERS_BUDGET CLAUDE_CONFIG_DIR CODEX_HOME CLAUDE_CODE_SESSION_ID AR_SESSION CLAUDE_PROJECT_DIR
export DR_CODEX_SESSION_DIR="$TMP/sessions" CLAUDE_CODE_SESSION_ID=task-step-base-test
printf '%s\n' '#!/usr/bin/env bash' 'echo "codex-gate usable=true reason= review=true lane=false resets_at=- source=cache"' > "$TMP/gate-stub"
export TASK_STEP_CODEX_GATE="$TMP/gate-stub"
export SUITE_MARK="$TMP/marks"

# The helpers run before task-step's rereview dispatch, which exits before any
# later definition exists.
dispatch=$(grep -n '^if \[ "\${1:-}" = rereview \]; then$' "$S/task-step" | head -n 1 | cut -d: -f1)
for fn in suite_key suite_row suite_failing_lines suite_base_lines run_at_base suite_gap; do
  at=$(grep -n "^$fn() {" "$S/task-step" | head -n 1 | cut -d: -f1)
  check "$fn is defined before the rereview dispatch" "$([ -n "$at" ] && [ -n "$dispatch" ] && [ "$at" -lt "$dispatch" ] && echo yes || echo no)" "yes"
done

REPO="$TMP/repo"
git init -q "$REPO"
g() { git -C "$REPO" "$@"; }
g config user.name t
g config user.email t@example.invalid
mkdir -p "$REPO/docs"
sed 's/^|//' > "$REPO/docs/plan.md" <<'PLAN'
|# Base Run Fixture Plan
|
|**Goal:** Fixture.
|
|**Execution:** subagent — `claude --model sonnet --effort high` — fixture
|
|**Worktree setup:** `touch setup.done`
|
|## Task index
|
|1. One
|2. Two
|3. Three
|4. Four
|5. Five
|6. Six
|
|### Task 1: One
|
|**Files:**
|- Modify: `app.txt`
|
|**Implementer:** dforge:impl-sonnet-low
|**Evaluation:** files 0 - spec 0 - coupling 1 - risk 0 = 1
|
|### Task 2: Two
|
|**Files:**
|- Modify: `app.txt`
|
|**Implementer:** dforge:impl-sonnet-low
|**Evaluation:** files 0 - spec 0 - coupling 1 - risk 0 = 1
|
|### Task 3: Three
|
|**Files:**
|- Modify: `app.txt`
|
|**Implementer:** dforge:impl-sonnet-low
|**Evaluation:** files 0 - spec 0 - coupling 1 - risk 0 = 1
|
|### Task 4: Four
|
|**Files:**
|- Modify: `app.txt`
|
|**Implementer:** dforge:impl-sonnet-low
|**Evaluation:** files 0 - spec 0 - coupling 1 - risk 0 = 1
|
|### Task 5: Five
|
|**Files:**
|- Modify: `app.txt`
|
|**Implementer:** dforge:impl-sonnet-low
|**Evaluation:** files 0 - spec 0 - coupling 1 - risk 0 = 1
|
|### Task 6: Six
|
|**Files:**
|- Modify: `app.txt`
|
|**Implementer:** dforge:impl-sonnet-low
|**Evaluation:** files 0 - spec 0 - coupling 1 - risk 0 = 1
PLAN
cat > "$REPO/suite.sh" <<'SUITE'
#!/usr/bin/env bash
if [ -f setup.done ]; then echo setup >> "$SUITE_MARK"; else echo plain >> "$SUITE_MARK"; fi
if grep -q broken app.txt; then echo 'not ok 7 - app-broken'; fi
if [ -s failing.txt ]; then cat failing.txt; fi
! { [ -s failing.txt ] || grep -q broken app.txt; }
SUITE
seq 1 10 | sed 's/^/line /' > "$REPO/app.txt"
printf 'not ok 1 - alpha\n' > "$REPO/failing.txt"
g add -A && g commit -qm base

ts() { # ts <args...> — task-step in the fixture repo; sets out, err, rc
  out=$(cd "$REPO" && bash "$S/task-step" "$@" 2>"$TMP/err"); rc=$?
  err=$(cat "$TMP/err")
}
sr() { (cd "$REPO" && bash "$S/suite-run" -- bash -c 'bash suite.sh' >/dev/null 2>&1); } # the controller's own suite run
commit() { g add -A && g commit -qm "$1"; }
set_failing() { printf '%s' "$1" > "$REPO/failing.txt"; }
marks() { grep -c "^$1\$" "$SUITE_MARK" 2>/dev/null || true; }
clean_report() {
  cat > "$WS/task-$1-review-report.md" <<'REPORT'
## Verdict
spec: pass
quality: approved
scores: spec 17 / scope 17 / verification 16 / quality 16

## Strengths
Fine.

## Findings

## Cannot verify

## Assessment
Fine.
REPORT
}

ts start docs/plan.md 1 --suite 'bash suite.sh'
check "start --suite: exit 0" "$rc" "0"
WS=$(winpath "$(cd "$REPO" && bash "$S/sdd-workspace" docs/plan.md)")

# Task 1: no base row, no file: the suite runs once at the base, after the setup.
set_failing $'not ok 1 - alpha\nnot ok 2 - beta\n'
commit "work 1"
sr
ts review docs/plan.md 1
check "task 1: review exits 0" "$rc" "0"
clean_report 1
ts verdict docs/plan.md 1
check "task 1: verdict exits 0" "$rc" "0"
check "task 1: only the new failure is red" "$(grep '^suite: ' <<<"$out")" "suite: red (1 failing, 1 baseline)"
check "task 1: the fix file names beta and not alpha" "$(grep -qF beta "$WS/task-1-fix-1.md" && echo yes || echo no) $(grep -qF alpha "$WS/task-1-fix-1.md" && echo yes || echo no)" "yes no"
check "task 1: the base failures are kept" "$(cat "$WS/task-1-base-failures.txt")" "not ok - alpha"
check "task 1: the base log is kept" "$(grep -c alpha "$WS/task-1-base.log")" "1"
check "task 1: the setup ran in the base worktree, once" "$(marks setup)" "1"
check "task 1: the temporary worktree is gone" "$(g worktree list | wc -l | tr -d ' ')" "1"
ts verdict docs/plan.md 1
check "task 1: a second verdict reuses the file" "$(marks setup) $(grep '^suite: ' <<<"$out")" "1 suite: red (1 failing, 1 baseline)"

# Task 2: a suite row at the base sha (task 1's head) answers without a run.
ts start docs/plan.md 2 --suite 'bash suite.sh'
set_failing $'not ok 1 - alpha\nnot ok 2 - beta\nnot ok 3 - gamma\n'
commit "work 2"
sr
ts review docs/plan.md 2
clean_report 2
ts verdict docs/plan.md 2
check "task 2: the base row answers" "$(grep '^suite: ' <<<"$out") $(marks setup) $([ -e "$WS/task-2-base-failures.txt" ] && echo file || echo nofile)" "suite: red (1 failing, 2 baseline) 1 nofile"
check "task 2: the fix file names gamma and not beta" "$(grep -qF gamma "$WS/task-2-fix-1.md" && echo yes || echo no) $(grep -qF beta "$WS/task-2-fix-1.md" && echo yes || echo no)" "yes no"

# Task 3: a passing base gives an empty file, and the new failure is not baseline.
set_failing ''
commit "green"
ts start docs/plan.md 3 --suite 'bash suite.sh'
set_failing $'not ok 1 - delta\n'
commit "work 3"
sr
ts review docs/plan.md 3
clean_report 3
ts verdict docs/plan.md 3
check "task 3: a passing base leaves nothing to excuse" "$(grep '^suite: ' <<<"$out")" "suite: red (1 failing, 0 baseline)"
check "task 3: the empty file is kept" "$([ -f "$WS/task-3-base-failures.txt" ] && [ ! -s "$WS/task-3-base-failures.txt" ] && echo empty || echo other)" "empty"
check "task 3: the base run used the setup" "$(marks setup)" "2"

# Task 4: rereview --covered skips only when the fix head's suite is covered.
set_failing $'not ok 1 - alpha\n'
commit "red again"
ts start docs/plan.md 4 --suite 'bash suite.sh'
printf 'impl\n' >> "$REPO/app.txt"
commit "work 4"
ts review docs/plan.md 4
R0=$(g rev-parse HEAD)
cp "$WS/task-4-step.json" "$TMP/state4.0"
rr_case() { # rr_case <name> <fix: mod|broken|green> <run suite: yes|no> <want>
  g reset -q --hard "$R0"
  cp "$TMP/state4.0" "$WS/task-4-step.json"
  rm -f "$WS"/task-4-fix-*.md "$WS"/task-4-rereview-*-prompt.md
  case $2 in
    mod) awk 'NR == 2 { print "changed"; next } { print }' "$REPO/app.txt" > "$REPO/app.tmp" && mv "$REPO/app.tmp" "$REPO/app.txt" ;;
    broken) awk 'NR == 2 { print "broken"; next } { print }' "$REPO/app.txt" > "$REPO/app.tmp" && mv "$REPO/app.tmp" "$REPO/app.txt" ;;
    green) awk 'NR == 2 { print "changed"; next } { print }' "$REPO/app.txt" > "$REPO/app.tmp" && mv "$REPO/app.tmp" "$REPO/app.txt"; : > "$REPO/failing.txt" ;;
  esac
  commit fix
  printf -- '- app.txt: wrong value\n\nFixed.\n' > "$WS/task-4-fix-1.md"
  [ "$3" != yes ] || sr
  ts rereview docs/plan.md 4 --covered
  check "rereview $1" "$rc $(grep '^re-review: ' <<<"$out") $([ -f "$WS/task-4-rereview-1-prompt.md" ] && echo prompt || echo none)" "$4"
}
rr_case "no suite row for the fix head: not skipped" mod no "0 re-review: not skipped (suite not run) prompt"
rr_case "a non-baseline failure at the fix head: not skipped" broken yes "0 re-review: not skipped (suite red) prompt"
rr_case "baseline failures only: skipped" mod yes "0 re-review: skipped (2 changed lines, 1 finding, app.txt) none"
rr_case "a passing suite: skipped" green yes "0 re-review: skipped (3 changed lines, 1 finding, app.txt) none"
check "task 4: the base run happened once" "$(marks setup)" "3"

# Task 5: a task started before --suite existed keeps today's rule.
ts start docs/plan.md 5
printf 'impl\n' >> "$REPO/app.txt"
commit "work 5"
ts review docs/plan.md 5
printf -- '- app.txt: wrong value\n\nFixed.\n' > "$WS/task-5-fix-1.md"
awk 'NR == 3 { print "changed"; next } { print }' "$REPO/app.txt" > "$REPO/app.tmp" && mv "$REPO/app.tmp" "$REPO/app.txt"
commit fix
ts rereview docs/plan.md 5 --covered
check "no recorded suite: today's skip rule" "$rc $(grep '^re-review: ' <<<"$out")" "0 re-review: skipped (2 changed lines, 1 finding, app.txt)"

# Task 6: a base run that cannot start leaves no file, and every failure is new.
sed 's/`touch setup.done`/`false`/' "$REPO/docs/plan.md" > "$REPO/docs/plan.tmp" && mv "$REPO/docs/plan.tmp" "$REPO/docs/plan.md"
commit "setup that fails"
ts start docs/plan.md 6 --suite 'bash suite.sh'
set_failing $'not ok 1 - alpha\nnot ok 2 - zeta\n'
commit "work 6"
sr
ts review docs/plan.md 6
clean_report 6
ts verdict docs/plan.md 6
check "task 6: no base run, no baseline" "$(grep '^suite: ' <<<"$out")" "suite: red (2 failing, 0 baseline)"
check "task 6: the stderr says why" "$(grep -c 'no base run' <<<"$err") $(grep -c 'worktree setup failed' <<<"$err")" "1 1"
check "task 6: no file is kept, so the next verdict tries again" "$([ -e "$WS/task-6-base-failures.txt" ] && echo file || echo nofile)" "nofile"
check "task 6: the temporary worktree is gone" "$(g worktree list | wc -l | tr -d ' ')" "1"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `timeout 300 bash plugins/dforge/tests/task-step-base.test.sh`
Expected: FAIL lines including `run_at_base is defined before the rereview dispatch` and `suite_gap is defined before the rereview dispatch`, a `task 1: only the new failure is red` failure (the seam prints nothing, so the digest reads `suite: red (2 failing, 0 baseline)`), and the `rereview` cases that expect `not skipped (suite …)`; the run ends with a non-zero failure count and exit 1.

- [ ] **Step 3: Put every suite helper above the rereview dispatch**

`cmd_rereview` is a function that `task-step` calls near its top, and the script exits right after, so a function defined further down the file does not exist for it. Task 12 may have defined `suite_key`, `suite_row`, `suite_failing_lines` and `suite_base_lines` below that dispatch. This command moves any of the four that sit below the line `if [ "${1:-}" = rereview ]; then` to just above `rr_usage() {`, with the comment lines directly above each, and changes nothing when all four already sit above it:

```bash
f=plugins/dforge/scripts/task-step
awk '
  { line[NR] = $0 }
  END {
    n = split("suite_key suite_row suite_failing_lines suite_base_lines", names, " ")
    for (i = 1; i <= NR; i++) if (line[i] == "if [ \"${1:-}\" = rereview ]; then") dispatch = i
    if (!dispatch) { print "the rereview dispatch line is missing" > "/dev/stderr"; exit 2 }
    for (k = 1; k <= n; k++) {
      s = 0
      for (i = 1; i <= NR; i++) if (index(line[i], names[k] "() {") == 1) { s = i; break }
      if (!s) { print names[k] "() is not defined" > "/dev/stderr"; exit 2 }
      if (s < dispatch) continue
      e = s
      while (e <= NR && line[e] != "}") e++
      b = s
      while (b > 1 && line[b - 1] ~ /^#/) b--
      for (i = b; i <= e; i++) { move[i] = 1; moved = moved line[i] "\n" }
      moved = moved "\n"
      if (line[e + 1] == "") move[e + 1] = 1
    }
    for (i = 1; i <= NR; i++) {
      if (index(line[i], "rr_usage() {") == 1) printf "%s", moved
      if (!move[i]) print line[i]
    }
  }' "$f" > "$f.moved" && cat "$f.moved" > "$f"
rm -f "$f.moved"
bash -n "$f" && grep -n '^suite_key() {\|^suite_row() {\|^suite_failing_lines() {\|^suite_base_lines() {\|^rr_usage() {\|^if \[ "${1:-}" = rereview \]; then$' "$f"
```

Expected: no stderr line from `awk` (a `… is not defined` line means Task 12's functions are missing: report BLOCKED and stop), and the `grep` lists the four functions, then `rr_usage() {`, then the `if [ "${1:-}" = rereview ]; then` line last, each with a higher line number than the one before.

- [ ] **Step 4: Replace the seam with the base-run helpers**

In `plugins/dforge/scripts/task-step`, replace exactly these three lines (delete any comment lines Task 12 left directly above them as well):

```bash
suite_base_lines() { # STEP_FILE N [DIR]
  return 0
}
```

with:

```bash
# run_at_base BASE_SHA COMMAND OUT_LOG: runs COMMAND once at BASE_SHA in a
# temporary detached worktree, after the plan header's **Worktree setup:**
# command when it names one, through suite-run --timeout 600. Copies the run's
# log to OUT_LOG and prints the command's exit code. Prints nothing, and
# returns 1, when the worktree, its setup or the run's log is missing. The
# header is read from $src, the amended plan, when the caller has one.
run_at_base() {
  local sha=$1 cmd=$2 out=$3 wt line setup="" run log code rc=1
  if [ -n "${src:-}" ] && [ -f "$src" ]; then
    line=$(plan_header_line "$src" 'Worktree setup')
    setup=$(printf '%s' "${line#\*\*Worktree setup:\*\*}" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//; s/^`(.*)`$/\1/')
    [ "$setup" != none ] || setup=""
  fi
  wt=$(mktemp -d) || return 1
  if command -v cygpath >/dev/null 2>&1; then wt=$(cygpath -m "$wt"); fi
  if ! git worktree add --detach "$wt" "$sha" >/dev/null 2>&1; then
    rm -rf "$wt"
    echo "task-step: cannot create a worktree at ${sha:0:7}" >&2
    return 1
  fi
  if [ -n "$setup" ] && ! (cd "$wt" && bash -c "$setup") >/dev/null 2>&1; then
    echo "task-step: the worktree setup failed at ${sha:0:7}" >&2
  else
    run=$(cd "$wt" && bash "$HERE/suite-run" --timeout 600 -- bash -c "$cmd")
    code=$?
    log=$(printf '%s\n' "$run" | tr -d '\r' | sed -n 's/^log: //p' | tail -n 1)
    if [ -n "$log" ] && [ -f "$log" ] && cp "$log" "$out"; then
      printf '%s\n' "$code"
      rc=0
    fi
  fi
  git worktree remove --force "$wt" >/dev/null 2>&1 || rm -rf "$wt"
  git worktree prune >/dev/null 2>&1
  return $rc
}

# suite_base_lines STEP_FILE N [DIR]: the base commit's failing lines for the
# step file's suite command, one per line, nothing for a passing base. It
# reuses a suites.tsv row at the base in the checkout's state (then DIR's),
# then <workspace>/task-N-base-failures.txt, and only then runs the suite at
# the base. A base run that cannot finish writes no file, so a later call tries
# again, and every failing line counts as new meanwhile.
suite_base_lines() {
  local step=$1 n=$2 dir=${3:-} cmd base ws file row code log
  cmd=$(jq -r '.suite // empty' "$step" | tr -d '\r')
  base=$(jq -r '.base // empty' "$step" | tr -d '\r')
  [ -n "$cmd" ] && [ -n "$base" ] || return 0
  ws=$(dirname "$step")
  file=$ws/task-$n-base-failures.txt
  row=$(suite_row "$step" "$base")
  [ -n "$row" ] || [ -z "$dir" ] || row=$(suite_row "$step" "$base" "$dir")
  if [ -n "$row" ]; then
    code=$(cut -f4 <<<"$row")
    log=$(cut -f5 <<<"$row")
    [ "$code" != 0 ] || return 0
    if [ "$code" != 124 ] && [ -f "$log" ]; then
      suite_failing_lines "$log" || true
      return 0
    fi
  fi
  if [ -f "$file" ]; then cat "$file"; return 0; fi
  if ! code=$(run_at_base "$base" "$cmd" "$ws/task-$n-base.log") || [ "$code" = 124 ]; then
    echo "task-step: no base run at ${base:0:7}; every failing line counts as new" >&2
    return 0
  fi
  if [ "$code" = 0 ]; then
    : > "$file"
  else
    suite_failing_lines "$ws/task-$n-base.log" > "$file" || true
  fi
  cat "$file"
}

# suite_gap STEP_FILE N SHA [DIR]: nothing when the step file records no suite
# or SHA's suite row passes or fails with baseline lines only; otherwise "not
# run" (no row) or "red".
suite_gap() {
  local step=$1 n=$2 sha=$3 dir=${4:-.} row log base_lines line k=0
  [ -n "$(jq -r '.suite // empty' "$step" | tr -d '\r')" ] || return 0
  row=$(suite_row "$step" "$sha" "$dir")
  if [ -z "$row" ]; then echo "not run"; return 0; fi
  [ "$(cut -f4 <<<"$row")" != 0 ] || return 0
  log=$(cut -f5 <<<"$row")
  if [ ! -f "$log" ]; then echo red; return 0; fi
  base_lines=$(suite_base_lines "$step" "$n" "$dir")
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    k=$((k + 1))
    if ! grep -qxF -- "$line" <<<"$base_lines"; then echo red; return 0; fi
  done < <(suite_failing_lines "$log" || true)
  [ "$k" -gt 0 ] || echo red
}
```

`run_at_base` reads `$src`, which is `task-step`'s amended plan in the main flow and a local of `cmd_rereview` while it runs, so both callers see the header. A base failure that is also a head failure is compared with `grep -xF`, as Contracts "Base runs" says.

- [ ] **Step 5: Make `rereview --covered` need a covered suite**

In `cmd_rereview` of `plugins/dforge/scripts/task-step`, make three edits.

First, add two names to the `local` line. Replace:

```bash
  local pkg diff_file numstat a d f lines over touched risk3 skip why now prompt tpl ids group gstate check_dir snap
```

with:

```bash
  local pkg diff_file numstat a d f lines over touched risk3 skip why now prompt tpl ids group gstate check_dir snap suite_why suite_dir
```

Second, after the skip decision. Replace:

```bash
  else skip=1
  fi
```

with:

```bash
  else skip=1
  fi
  suite_why=""
  if [ "$skip" -eq 1 ]; then
    suite_dir=$(jq -r '.reviewCheck.cwd // .heldCwd // empty' "$state" | tr -d '\r')
    suite_why=$(suite_gap "$state" "$first" "$head_sha" "$suite_dir")
    if [ -n "$suite_why" ]; then skip=0 why="suite $suite_why"; fi
  fi
```

Third, in the not-skipped output. Replace:

```bash
    printf 'seat: dforge:judge-sonnet-high prompt: %s\n' "$prompt"
  fi
```

with:

```bash
    printf 'seat: dforge:judge-sonnet-high prompt: %s\n' "$prompt"
    [ -z "$suite_why" ] || printf 're-review: not skipped (suite %s)\n' "$suite_why"
  fi
```

A task whose step file has no `suite` field gets an empty `suite_why` from `suite_gap`, so it keeps today's skip rule. The suite row is looked up in the checkout the review recorded (`reviewCheck.cwd`, or `heldCwd`), so a wave task reads its worktree's `.dforge`.

- [ ] **Step 6: Run the new test and the neighbours**

Run: `timeout 300 bash plugins/dforge/tests/task-step-base.test.sh`
Expected: every line `ok`, ending `31 passed, 0 failed`.

Run: `timeout 600 bash plugins/dforge/tests/task-step.test.sh`
Expected: `0 failed`.

Run: `timeout 300 bash plugins/dforge/tests/suite-run.test.sh`
Expected: `0 failed`.

Run: `ps -eo pid,args | grep -c '[s]uite-run --timeout 600'`
Expected: `0` (no base run left behind), and `git worktree list` lists only the checkout.

- [ ] **Step 7: Commit**

```bash
git add plugins/dforge/scripts/task-step plugins/dforge/tests/task-step-base.test.sh
git commit -m "feat(task-step): compare suite failures to base"
```

### Task 14: Settle mechanical cannot-verify items

**Files:**
- Modify: `plugins/dforge/scripts/task-step` (two functions above `verdict_val`, one call in `do_verdict`)
- Modify: `plugins/dforge/skills/subagent-driven-development/references/task-reviewer-prompt.md`
- Create: `plugins/dforge/tests/task-step-settle.test.sh`

**Interfaces:**
- Consumes: Contracts "Base runs" (Task 13): `run_at_base BASE_SHA COMMAND OUT_LOG`. It also uses `do_verdict`'s `cvs` array, `vstate`, `ws`, `first`, `ledger`, `ledger_init` and `vgroup` as they are today.
- Produces: Contracts "Cannot-verify settlement": the two item forms in the task-reviewer prompt, and `task-step verdict` answering them (`exists` by `git cat-file -e` or `git grep -nwF`, `baseline` through `run_at_base`), logging `Task <N>: Ruling: cannot-verify — settled by task-step check <exists|baseline> — <evidence>` and leaving the item out of the digest's `cannot-verify:` lines.

**Items:** 5

**Depends on:** Task 12, Task 13

**Implementer:** dforge:impl-sonnet-medium
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 2 = 4

- [ ] **Step 1: Write the failing test**

Create `plugins/dforge/tests/task-step-settle.test.sh`. It checks the prompt text, then drives `verdict` over reports holding every item form: a present path, paths absent at head and present at base, a symbol with a hit, a missing symbol, a baseline command, free text and a malformed item.

```bash
#!/usr/bin/env bash
# task-step verdict answers a reviewer's structured cannot-verify items itself,
# logs each answer to the ledger and leaves free text for the ruling seat.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
P="$HERE/.."
S="$P/scripts"
TRP="$P/skills/subagent-driven-development/references/task-reviewer-prompt.md"

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}

TMP=$(mktemp -d)
if command -v cygpath >/dev/null 2>&1; then TMP=$(cygpath -m "$TMP"); fi
winpath() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s\n' "$1"; fi; }
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" MSYS_NO_PATHCONV=1 GIT_CONFIG_NOSYSTEM=1 DFORGE_NO_SETTINGS=1
mkdir -p "$HOME/.claude"
unset DFORGE_BUDGET DR_SUPERPOWERS_BUDGET CLAUDE_CONFIG_DIR CODEX_HOME CLAUDE_CODE_SESSION_ID AR_SESSION CLAUDE_PROJECT_DIR
export DR_CODEX_SESSION_DIR="$TMP/sessions" CLAUDE_CODE_SESSION_ID=task-step-settle-test
printf '%s\n' '#!/usr/bin/env bash' 'echo "codex-gate usable=true reason= review=true lane=false resets_at=- source=cache"' > "$TMP/gate-stub"
export TASK_STEP_CODEX_GATE="$TMP/gate-stub"

check "the reviewer prompt names the exists form" "$(grep -cF -- '- cannot-verify: exists <path|symbol> at <base|head> — <why it matters>' "$TRP")" "1"
check "the reviewer prompt names the baseline form" "$(grep -cF -- '- cannot-verify: baseline <command> — <why>' "$TRP")" "1"

REPO="$TMP/repo"
git init -q "$REPO"
g() { git -C "$REPO" "$@"; }
g config user.name t
g config user.email t@example.invalid
mkdir -p "$REPO/docs" "$REPO/lib"
sed 's/^|//' > "$REPO/docs/plan.md" <<'PLAN'
|# Settle Fixture Plan
|
|**Goal:** Fixture.
|
|**Execution:** subagent — `claude --model sonnet --effort high` — fixture
|
|## Task index
|
|1. One
|2. Two
|
|### Task 1: One
|
|**Files:**
|- Modify: `lib/new.sh`
|
|**Implementer:** dforge:impl-sonnet-low
|**Evaluation:** files 0 - spec 0 - coupling 1 - risk 0 = 1
|
|### Task 2: Two
|
|**Files:**
|- Modify: `lib/new.sh`
|
|**Implementer:** dforge:impl-sonnet-low
|**Evaluation:** files 0 - spec 0 - coupling 1 - risk 0 = 1
PLAN
printf '#!/usr/bin/env bash\necho old\n' > "$REPO/lib/old.sh"
printf '#!/usr/bin/env bash\necho "not ok 1 - alpha"\nexit 1\n' > "$REPO/check.sh"
g add -A && g commit -qm base

ts() { # ts <args...> — task-step in the fixture repo; sets out, err, rc
  out=$(cd "$REPO" && bash "$S/task-step" "$@" 2>"$TMP/err"); rc=$?
  err=$(cat "$TMP/err")
}
ledger_count() { grep -cxF -- "$1" "$LEDGER" 2>/dev/null || true; }

ts start docs/plan.md 1
check "start exits 0" "$rc" "0"
WS=$(winpath "$(cd "$REPO" && bash "$S/sdd-workspace" docs/plan.md)")
LEDGER="$WS/progress.md"
printf '#!/usr/bin/env bash\ncompute_total() {\n  echo 1\n}\n' > "$REPO/lib/new.sh"
g add -A && g commit -qm work
ts review docs/plan.md 1
check "review exits 0" "$rc" "0"

cat > "$WS/task-1-review-report.md" <<'REPORT'
## Verdict
spec: cannot-verify
quality: approved
scores: spec 15 / scope 17 / verification 12 / quality 16

## Strengths
Fine.

## Findings

## Cannot verify
- cannot-verify: exists lib/new.sh at head — the brief names this file
- cannot-verify: exists lib/old.sh at base — the brief says it predates the task
- cannot-verify: exists lib/gone.sh at head — the brief says it is removed
- cannot-verify: exists compute_total at head — callers need the function
- cannot-verify: exists no_such_symbol at head — the brief names a helper
- cannot-verify: baseline bash check.sh — does the check fail before the task
- the caller passes the flag
- cannot-verify: exists two words at head — a malformed target

## Assessment
Fine.
REPORT
ts verdict docs/plan.md 1
check "verdict exits 0" "$rc" "0"
check "only free text and the malformed item reach the ruling seat" "$(grep '^cannot-verify: ' <<<"$out")" \
  "cannot-verify: the caller passes the flag
cannot-verify: exists two words at head — a malformed target"
LINE="Task 1: Ruling: cannot-verify — settled by task-step check"
check "a present path" "$(ledger_count "$LINE exists — path present")" "2"
check "a path absent at head" "$(ledger_count "$LINE exists — path absent")" "1"
check "a symbol's first hit" "$(ledger_count "$LINE exists — lib/new.sh:2")" "1"
check "a missing symbol" "$(ledger_count "$LINE exists — absent")" "1"
check "a baseline command" "$(ledger_count "$LINE baseline — exit 1, log $WS/task-1-baseline-1.log")" "1"
check "the baseline log is kept" "$(grep -c alpha "$WS/task-1-baseline-1.log")" "1"
check "no temporary worktree is left" "$(g worktree list | wc -l | tr -d ' ')" "1"
ts verdict docs/plan.md 1
check "a second verdict logs nothing twice" "$(grep -c 'settled by task-step check' "$LEDGER")" "6"

# Free text alone goes to the seat as today, and nothing is run.
cat > "$WS/task-1-review-report.md" <<'REPORT'
## Verdict
spec: cannot-verify
quality: approved
scores: spec 15 / scope 17 / verification 12 / quality 16

## Strengths
Fine.

## Findings

## Cannot verify
- the caller passes the flag

## Assessment
Fine.
REPORT
before=$(grep -c . "$LEDGER")
ts verdict docs/plan.md 1
check "free text is printed" "$(grep '^cannot-verify: ' <<<"$out")" "cannot-verify: the caller passes the flag"
check "free text writes no ledger line" "$(grep -c . "$LEDGER")" "$before"

# Two baseline items write two logs.
ts start docs/plan.md 2
printf '#!/usr/bin/env bash\ncompute_total() {\n  echo 2\n}\n' > "$REPO/lib/new.sh"
g add -A && g commit -qm work2
ts review docs/plan.md 2
cat > "$WS/task-2-review-report.md" <<'REPORT'
## Verdict
spec: cannot-verify
quality: approved
scores: spec 15 / scope 17 / verification 12 / quality 16

## Strengths
Fine.

## Findings

## Cannot verify
- cannot-verify: baseline bash check.sh — does the check fail before the task
- cannot-verify: baseline bash check.sh — asked a second time

## Assessment
Fine.
REPORT
ts verdict docs/plan.md 2
check "two baseline items write two logs" "$([ -f "$WS/task-2-baseline-1.log" ] && [ -f "$WS/task-2-baseline-2.log" ] && echo both || echo missing)" "both"
check "a baseline item is settled with its own log" "$(ledger_count "Task 2: Ruling: cannot-verify — settled by task-step check baseline — exit 1, log $WS/task-2-baseline-2.log")" "1"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `timeout 300 bash plugins/dforge/tests/task-step-settle.test.sh`
Expected: FAIL on `the reviewer prompt names the exists form` and `the reviewer prompt names the baseline form`, on `only free text and the malformed item reach the ruling seat` (the digest still prints every item), and on each ledger check (`0` where `2`, `1`, … are wanted); exit 1.

- [ ] **Step 3: Add the two item forms to the task-reviewer prompt**

In `plugins/dforge/skills/subagent-driven-development/references/task-reviewer-prompt.md`, replace this paragraph (inside the fenced template, indented four spaces):

```text
    List at most three Minor issues, the ones most worth fixing, and end
    the section with `(<k> more Minor left out)` when you dropped any. Each
    Minor is carried to the final review's triage, which reads them all.
```

with:

```text
    List at most three Minor issues, the ones most worth fixing, and end
    the section with `(<k> more Minor left out)` when you dropped any. Each
    Minor is carried to the final review's triage, which reads them all.

    A Cannot verify item that asks a question the repository answers
    mechanically takes one of two exact forms, which a script answers for
    you without a seat:

        - cannot-verify: exists <path|symbol> at <base|head> — <why it matters>
        - cannot-verify: baseline <command> — <why>

    `exists` asks whether a path, or a single-word symbol, is present at the
    task's base or head commit; write the path or symbol without spaces.
    `baseline` asks for the result of one command run verbatim, through
    `bash -c`, at the task's base commit. Use them only for such questions;
    every other item stays a one-line requirement and what to check.
```

The separator in both forms is ` — ` (U+2014 between spaces). The template holds no square-bracket token, so `task-step review` still fills it without an unexpanded placeholder.

- [ ] **Step 4: Settle the items in `verdict`**

In `plugins/dforge/scripts/task-step`, insert these two functions immediately above the comment line `# verdict_val KEY: the value of the first Verdict line with that key, from`:

```bash
# settle_item ITEM BASE HEAD LOG: answers one structured cannot-verify item.
# Prints "<exists|baseline>\t<evidence>" and returns 0; returns 1 for free text,
# a malformed item, or a check that could not run.
settle_item() {
  local item=$1 base=$2 head=$3 log=$4 rest spec target where sha hit ev cmd code
  case $item in
    'cannot-verify: exists '*' — '*)
      rest=${item#cannot-verify: exists }
      spec=${rest%% — *}
      where=${spec##* at }
      target=${spec% at *}
      case $where in base) sha=$base ;; head) sha=$head ;; *) return 1 ;; esac
      case $target in '' | *' '*) return 1 ;; esac
      [ -n "$sha" ] || return 1
      if git cat-file -e "$sha:$target" 2>/dev/null; then
        ev="path present"
      elif [[ $target == */* ]]; then
        ev="path absent"
      else
        hit=$(git grep -nwF -e "$target" "$sha" 2>/dev/null | head -n 1 | tr -d '\r')
        if [ -n "$hit" ]; then
          ev=$(printf '%s\n' "${hit#"$sha":}" | awk -F: '{ print $1 ":" $2 }')
        else
          ev=absent
        fi
      fi
      printf 'exists\t%s\n' "$ev" ;;
    'cannot-verify: baseline '*' — '*)
      rest=${item#cannot-verify: baseline }
      cmd=${rest%% — *}
      [ -n "$cmd" ] && [ -n "$base" ] || return 1
      code=$(run_at_base "$base" "$cmd" "$log") || return 1
      printf 'baseline\texit %s, log %s\n' "$code" "$log" ;;
    *) return 1 ;;
  esac
}

# settle_cannot_verify: do_verdict's helper. It answers a single task's
# structured cannot-verify items, logs each to the ledger and removes them from
# do_verdict's cvs array, so only free text and items it could not check reach
# the ruling seat. A kept item loses its "cannot-verify: " prefix, which the
# digest line adds back. The k-th baseline item writes task-N-baseline-k.log.
settle_cannot_verify() {
  local item out kind ev line base head bk=0 j seen="" open=()
  [ "$vgroup" -eq 0 ] || return 0
  base=$(jq -r '.base // empty' "$vstate" | tr -d '\r')
  head=$(jq -r '.reviewHead // empty' "$vstate" | tr -d '\r')
  for item in ${cvs[@]+"${cvs[@]}"}; do
    case $item in 'cannot-verify: baseline '*) bk=$((bk + 1)) ;; esac
    if out=$(settle_item "$item" "$base" "$head" "$ws/task-$first-baseline-$bk.log"); then
      kind=${out%%$'\t'*}
      ev=${out#*$'\t'}
      line="Task $first: Ruling: cannot-verify — settled by task-step check $kind — $ev"
      j=$(printf '%s' "$seen" | grep -cxF -- "$line" || true)
      j=$((j + 1))
      seen="$seen$line"$'\n'
      if [ ! -f "$ledger" ] || [ "$(tr -d '\r' < "$ledger" | grep -cxF -- "$line")" -lt "$j" ]; then
        ledger_init
        printf '%s\n' "$line" >> "$ledger"
      fi
    else
      open+=("${item#cannot-verify: }")
    fi
  done
  cvs=(${open[@]+"${open[@]}"})
}
```

Then, in `do_verdict`, call it right after the loop that reads the parsed report records. Replace the single line:

```bash
  done <<<"$recs"
```

with:

```bash
  done <<<"$recs"
  settle_cannot_verify
```

`settle_cannot_verify` edits `do_verdict`'s own `cvs` array (bash scopes locals dynamically), so the digest code below, which prints `cannot-verify: <item>` for each remaining entry, is unchanged. A group verdict is left alone (`vgroup`), as are items in any other form. A line already in the ledger is not appended again, except that two items with the same evidence in one report log one line each.

- [ ] **Step 5: Run the new test and the neighbours**

Run: `timeout 300 bash plugins/dforge/tests/task-step-settle.test.sh`
Expected: every line `ok`, ending `18 passed, 0 failed`.

Run: `timeout 600 bash plugins/dforge/tests/task-step.test.sh`
Expected: `0 failed`.

Run: `timeout 300 bash plugins/dforge/tests/task-step-base.test.sh`
Expected: `0 failed`.

Run: `timeout 300 bash plugins/dforge/tests/seats.test.sh`
Expected: `0 failed`.

Run: `timeout 300 bash plugins/dforge/tests/process-roles.test.sh`
Expected: `0 failed`.

Run: `timeout 300 bash plugins/dforge/tests/review-route.test.sh`
Expected: `0 failed`.

- [ ] **Step 6: Validate the repository and the plugin**

Run: `node scripts/validate-repository.mjs`
Expected: `Repository catalogs, manifests, versions, bundled links and the settings schema are valid.`

Run: `timeout 120 /root/.local/bin/claude plugin validate plugins/dforge`
Expected: `Validation passed`.

- [ ] **Step 7: Commit**

```bash
git add plugins/dforge/scripts/task-step plugins/dforge/skills/subagent-driven-development/references/task-reviewer-prompt.md plugins/dforge/tests/task-step-settle.test.sh
git commit -m "feat(task-step): settle mechanical cannot-verify items"
```

### Task 15: Run the suite beside the review in the controller

**Files:**
- Modify: `plugins/dforge/reference/delegated-task.md`
- Create: `plugins/dforge/tests/delegated-suite.test.sh`

**Interfaces:**
- Consumes: Contracts "Implementer report" (Task 9: the `## Verified` section and the `Report:` line), "Suite command and record" (Task 12: `--suite`, the `suite:` lines, exit 8), "Base runs" (Task 13) and "Cannot-verify settlement" (Task 14).
- Produces: no Contracts entry; the controller's side of the loop in `reference/delegated-task.md`: the suite command resolution rule (§1), starting the suite beside the review (§2), reading the `suite:` lines and settled items (§3), the group and fix-round suites (§3a, §4), the completion rule (§5) and the by-hand suite run (*The steps by hand* §2). `skills/subagent-driven-development/SKILL.md`, `reference/native-codex.md` and `skills/executing-plans/SKILL.md` are not edited.

**Items:** 1, 2

**Depends on:** Task 9, Task 12, Task 13, Task 14

**Implementer:** dforge:impl-sonnet-high
**Evaluation:** files 1 - spec 0 - coupling 2 - risk 2 = 5

- [ ] **Step 1: Write the failing test**

Create `plugins/dforge/tests/delegated-suite.test.sh`. Each pin is one line of text, so a re-wrapped paragraph fails the test rather than slipping through.

```bash
#!/usr/bin/env bash
# The delegated task loop has the controller run the full suite beside the
# review, read it through task-step verdict and complete a task only after
# verdict passes. Codex hosts and inline mode keep their own suite rules.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
P="$HERE/.."
DT="$P/reference/delegated-task.md"
NC="$P/reference/native-codex.md"
INLINE="$P/skills/executing-plans/SKILL.md"

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
in_loop() { sed '/^## The steps by hand/,$d' "$DT" | grep -cF -- "$1"; } # in_loop <text> — matching lines in the loop steps
by_hand() { sed -n '/^## The steps by hand/,/^## Recovery/p' "$DT" | grep -cF -- "$1"; }
has() { check "$1" "$([ "$("$2" "$3")" -ge 1 ] && echo yes || echo no)" "yes"; } # has <label> <in_loop|by_hand> <text>

has "the start call carries --suite" in_loop "every start adds"
has "the suite command comes from the header's Integration check" in_loop '`**Integration check:**` line'
has "else from the gates file" in_loop '`<docs>/gates.md` declares'
has "else from the manifest" in_loop "from the project's manifest"
has "the first start logs a suite ruling" in_loop 'Task <N>: Ruling: suite command — <command> — none'
has "the implementer runs only focused tests" in_loop 'runs only the focused tests that cover its change'

has "the controller starts suite-run in the background" in_loop "bash <plugin-root>/scripts/suite-run -- bash -c '<suite command>'\` as a"
has "a wave task runs it from its worktree" in_loop 'a wave task: from its'
has "the review is dispatched in the same turn" in_loop 'in the same turn run'
has "verdict waits for both notifications" in_loop "only once both the seat's report and the suite's"
has "a held task starts no suite" in_loop 'A held task starts'
has "a wave's grouped tasks get no suite" in_loop "wave's merged check is their suite"
has "a group's suite starts at the last held head" in_loop "last held member's head"
has "a Codex plan starts the suite by hand" in_loop '*The steps by hand* §2 starts'
has "a fix head gets its own suite run" in_loop 'has its own suite run beside its re-review'

has "verdict reads the suite line: pass" in_loop '`suite: pass (clean|dirty)`'
has "verdict reads the suite line: red" in_loop '`suite: red (<k> failing, <b> baseline)`'
has "verdict reads the suite line: not run" in_loop '`suite: not run (<command>)`'
has "verdict reads the suite line: none recorded" in_loop '`suite: none recorded`'
has "a new failure is an Important finding" in_loop '`suite: <failing line> fails at <head7>`'
has "the base failures are reused in order" in_loop 'task-<N>-base-failures.txt'
has "the base run is bounded" in_loop 'bounded at 600 seconds'
has "exit 8 re-runs the suite and writes no ruling" in_loop 'Exit 8 is not a seat failure'
has "--covered waits for the fix head's suite" in_loop 'only after that run'"'"'s notification is'
has "a covered skip can be refused by the suite" in_loop '`re-review: not skipped (suite <red|not run>)`'
has "a structured item is settled by task-step" in_loop 'settled by task-step check <exists|baseline> — <evidence>'
has "a task completes only after verdict passes" in_loop 'A task is marked complete only after `task-step verdict` passes'

has "by hand: the controller runs suite-run itself on a DONE report" by_hand 'On a DONE report, run'
has "by hand: suite-run takes the suite command" by_hand 'scripts/suite-run -- <suite command>'
has "by hand: a non-baseline failure is §3's Important finding" by_hand "non-baseline failure as §3's"

check "the loop steps still run date +%s once, for the cache rule" "$(in_loop 'date +%s')" "1"
check "native-codex.md carries no suite-run call" "$(grep -cF 'suite-run' "$NC")" "0"
check "inline mode keeps its full-suite-before-commit rule" "$(grep -cF 'and the full suite once before committing' "$INLINE")" "1"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `timeout 120 bash plugins/dforge/tests/delegated-suite.test.sh`
Expected: FAIL on every `has` line (the reference holds none of the new text) while the last three `check` lines print `ok`; ends `3 passed, 30 failed` and exit 1.

- [ ] **Step 3: Resolve and record the suite command (§1)**

In `plugins/dforge/reference/delegated-task.md`, make two edits.

Replace:

```text
task number, `N M …`; a wave task adds `--wave K`). It runs `task-brief`,
```

with:

```text
task number, `N M …`; a wave task adds `--wave K`; every start adds
`--suite '<suite command>'`, below). It runs `task-brief`,
```

Then insert this bullet immediately above the bullet that begins `- **Task brief:**`:

```text
- **Suite command.** Resolve the plan's suite command once and pass it to
  every `task-step start` as `--suite '<suite command>'`, a wave task's too:
  the command on the plan header's `**Integration check:**` line; else the
  test command `<docs>/gates.md` declares (the `Command` of the gate that runs
  the project's tests); else one you decide from the project's manifest
  (`package.json` `scripts.test`, a Makefile `test` target, `cargo test`,
  `go test ./...`, `pytest`) and keep for the rest of the plan. `start` records
  it as the step file's `suite`, and the first `start --suite` on a plan
  logs `Task <N>: Ruling: suite command — <command> — none`. The implementer
  runs only the focused tests that cover its change; §2 has you run the suite.
```

- [ ] **Step 4: Start the suite beside the review (§2)**

In `plugins/dforge/reference/delegated-task.md`, insert this paragraph between the `**DONE_WITH_CONCERNS:**` paragraph and the `**NEEDS_CONTEXT:**` paragraph (the line before `**NEEDS_CONTEXT:**` is blank; keep one blank line on each side):

```text
**The suite runs beside the review.** A task reviewed alone (`hold` exited 4,
every task inline mode delegates, a batch) starts its suite as soon as its
DONE or DONE_WITH_CONCERNS report is in. Run
`bash <plugin-root>/scripts/suite-run -- bash -c '<suite command>'` as a
background Bash command from the checkout's top level (a wave task: from its
`--cwd` worktree), at the task's head, and in the same turn run
`task-step review` and dispatch its seat (§3). `<suite command>` is the one
`task-step start --suite` recorded, character for character: `verdict` finds
the run by the quoted form `suite-run` records for that command, so a command
typed differently, or run from a subdirectory, is never found. The report's
`## Verified` section lists the focused tests the implementer ran; this run is
the full suite. End the turn when only waiting remains, and run
`task-step verdict` only once both the seat's report and the suite's
completion notification are in. A suite still running at a handoff shows in
`scripts/in-flight`, and the next session starts it again. A held task starts
no suite now: its group's suite starts with the group review (§3a), and a
wave's grouped tasks get none, because the wave's merged check is their suite.
On a `Host: codex` plan `task-step` does not run: *The steps by hand* §2 starts
the suite.
```

- [ ] **Step 5: Read the suite in the review and verdict (§3)**

In `plugins/dforge/reference/delegated-task.md`, make four edits.

Replace:

```text
`<prompt file>`: read it first and follow it". When a judge seat returns,
  run `bash <plugin-root>/scripts/task-step verdict PLAN_FILE N` with the
  review's task numbers, and act on its digest.
```

with:

```text
`<prompt file>`: read it first and follow it". When a judge seat returns
  and the suite's notification is in (§2), run
  `bash <plugin-root>/scripts/task-step verdict PLAN_FILE N` with the
  review's task numbers, and act on its digest. When the suite's notification
  reads `suite: FAIL`, `verdict` may run the suite once at the base commit,
  which takes up to ten minutes: start it as a background command and end
  the turn.
```

Replace:

```text
- Do not ask a reviewer to re-run tests the implementer already ran on the
  same code — the implementer's report carries the test evidence
```

with:

```text
- Do not ask a reviewer to re-run tests the implementer already ran on the
  same code — the implementer's report carries the test evidence, and the
  suite run of §2 covers the rest
```

Insert this block between the paragraph that begins `**Mechanical checks.**` (it ends `The Ruling Seat).`) and the paragraph whose first line begins ``**When `task-step verdict` fails.** Exit 5 means the seat wrote no report,``, one blank line on each side:

```text
**The suite line.** When the step file records a suite command, the verdict
digest carries exactly one `suite:` line, read from the run §2 started:

- `suite: pass (clean|dirty)`: nothing more to do. A `dirty` run counts: your
  own ledger lines leave the tree dirty, and the tracked-file check already
  guards the reviewed state.
- `suite: red (<k> failing, <b> baseline)`: each failing line that the base
  commit does not also fail is an Important finding,
  `suite: <failing line> fails at <head7>`, in the fix file, and `fix:` names
  that file. Only a base failure excuses a failing line. `verdict` reuses, in
  order, a `suites.tsv` row at the base commit in the checkout's state, then
  `<workspace>/task-<N>-base-failures.txt`, and only then runs the suite once
  at the base commit in a temporary worktree (after the header's
  `**Worktree setup:**`, bounded at 600 seconds), keeping that file and
  `<workspace>/task-<N>-base.log`. With `k` at 0 every failure is a base
  failure, and the task may complete.
- `suite: not run (<command>)`: no run was recorded at the review head, and
  `verdict` exits 8 with no fix file. Run the suite (§2) at the review head
  and call `verdict` again.
- `suite: none recorded`: the task was started before `--suite` existed; the
  loop is as it was.

The reviewer's `cannot-verify: exists <path|symbol> at <base|head> — <why>` and
`cannot-verify: baseline <command> — <why>` items are answered by `verdict`
itself: `exists` by `git cat-file -e` (a path) or `git grep -nwF` (a symbol)
at the named commit, `baseline` by running the command at the task's base
commit as the suite is run there (log `<workspace>/task-<N>-baseline-<k>.log`
for the k-th). Each answer is logged
`Task <N>: Ruling: cannot-verify — settled by task-step check <exists|baseline> — <evidence>`
and the item does not appear in the digest, so no seat sees it. An item in
any other form, or a check that could not run, stays a `cannot-verify:` line.
```

Replace:

```text
`run task-step review … first` means the review step never ran: run it.
```

with:

```text
`run task-step review … first` means the review step never ran: run it.
Exit 8 is not a seat failure: it means the suite has no record at the review
head, so write no `Ruling:` line and re-dispatch no seat; run the suite and
call `verdict` again. Exits 5 and 6 are checked before 8.
```

- [ ] **Step 6: Group suite, fix-round suite and the completion rule (§3a, §4, §5)**

In `plugins/dforge/reference/delegated-task.md`, make four edits.

Replace:

```text
  instructions are in `<prompt file>`: read it first and follow it". When the
  group's seat returns, run
```

with:

```text
  instructions are in `<prompt file>`: read it first and follow it". In
  sequential mode start the group's suite (§2) once, in that same turn, at the
  last held member's head; a wave's group gets none. When the group's seat
  returns and that suite's notification is in, run
```

Replace:

```text
covering test files in the fix message — a one-line fix does not need the
whole suite.
```

with:

```text
covering test files in the fix message — a one-line fix does not need the
whole suite. The full suite is yours: when the fix is committed, start it at
the new head as §2 says and run `rereview` in the same turn, so the fix head
has its own suite run beside its re-review.
```

Replace:

```text
as its round. Without `--covered`, or in any other case, the re-review runs.
```

with:

```text
as its round. Without `--covered`, or in any other case, the re-review runs.
When the step file records a suite, `--covered` also needs the suite run at
the fix head to have finished: pass it only after that run's notification is
in. `rereview` then skips only when the fix head's suite passes or fails with
base failures only; otherwise it prints
`re-review: not skipped (suite <red|not run>)` and writes the prompt as it
does without `--covered`. A red fix-head suite can make `--covered` run the
suite once at the base commit, which takes up to ten minutes: start
`rereview --covered` as a background command and end the turn.
```

Replace:

```text
## 5. Complete the task

When the review comes back clean
```

with:

```text
## 5. Complete the task

A task is marked complete only after `task-step verdict` passes: its digest
shows `fix: none` and a `suite:` line that is `pass`, `red` with 0 failing,
or `none recorded`. A `suite: not run` (exit 8) or a `red` with failing lines
leaves the task open, and the fix loop (§4) or a suite run (§2) comes first.

When the review comes back clean
```

- [ ] **Step 7: Run the suite by hand where `task-step` does not run (*The steps by hand* §2)**

In `plugins/dforge/reference/delegated-task.md`, insert this bullet between the `- **§1.**` bullet (it ends `` `Task <N>: implementer <agent> (assigned; base <sha7>)`. ``) and the `- **§3.**` bullet:

```text
- **§2.** On a DONE report, run
  `bash <plugin-root>/scripts/suite-run -- <suite command>` yourself in the
  background at the task's head and treat a non-baseline failure as §3's
  Important finding. `<suite command>` is resolved as §1's Suite command says.
  A failing line that the task's base commit also fails is baseline: run the
  suite once there, in a temporary worktree, and compare the failing lines as
  [parallel-waves.md](parallel-waves.md) §1 does.
```

- [ ] **Step 8: Run the new test and every test that pins this file**

Run: `timeout 120 bash plugins/dforge/tests/delegated-suite.test.sh`
Expected: every line `ok`, ending `33 passed, 0 failed`.

Run: `timeout 300 bash plugins/dforge/tests/task-step-text.test.sh`
Expected: `0 failed` (it also asserts that the loop steps keep exactly one `date +%s`).

Run: `timeout 600 bash plugins/dforge/tests/task-loop-steps.acceptance.test.sh`
Expected: `0 failed`.

Run: `timeout 590 bash plugins/dforge/tests/faster-plans.acceptance.test.sh`
Expected: `0 failed`.

Run: `timeout 300 bash plugins/dforge/tests/lanes.test.sh`
Expected: `0 failed`.

Run: `timeout 300 bash plugins/dforge/tests/auto-run-skills.test.sh`
Expected: `0 failed`.

Run: `timeout 300 bash plugins/dforge/tests/ui-ux-skill.test.sh`
Expected: `0 failed`.

Run: `node scripts/validate-repository.mjs`
Expected: `Repository catalogs, manifests, versions, bundled links and the settings schema are valid.`

- [ ] **Step 9: Commit**

```bash
git add plugins/dforge/reference/delegated-task.md plugins/dforge/tests/delegated-suite.test.sh
git commit -m "docs(dforge): run the suite beside the review"
```
