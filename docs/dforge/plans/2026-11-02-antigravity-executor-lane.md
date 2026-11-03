# Antigravity Executor Lane Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: the skill the **Execution:** line names — dforge:subagent-driven-development for `subagent`, dforge:executing-plans for `inline`. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Register the Antigravity CLI (`agy`) as dforge's second external executor, preferred over Codex, so plan tasks run on Antigravity quota instead of native Claude subagents.

**Architecture:** A registry entry (`reference/executors/agy.json`) with its own locator, auth probe, gate and task wrapper built on the shared task libraries (`lib/task-state.sh`, `lib/task-execution.sh`, `lib/executor-session.sh`); ladder blocks for its score bands; a registry `priority` so planning routes each task to the first ticked executor whose gate admits it; a per-plan breaker. `scripts/run-codex-task.sh` is not modified.

**Tech Stack:** Bash (GNU and uutils coreutils, Git Bash), jq, Node (probe), `agy` 1.4.12, dforge's bash test suites run by `node scripts/test-all.mjs`.

**Spec:** docs/dforge/specs/2026-11-02-antigravity-executor-lane-design.md

**Execution:** subagent — `claude --model sonnet --effort high` — most tasks are heavy (total 5 or more)

**Parallelism:** sequential — the spec's Execution strategy line: the tasks form one chain through the registry, ladder, gate, wrapper and routing

**Task check:** none — full suite every 3 tasks

**Integration check:** `node scripts/test-all.mjs`

**CI:** `.github/workflows/validate.yml, .github/workflows/release.yml` — platforms: uutils (ubuntu-latest), Windows Git Bash — local: `node scripts/validate-repository.mjs`; `node scripts/test-all.mjs`; `claude plugin validate .`; `claude plugin validate plugins/dforge`; `claude plugin test plugins/dforge` — uncovered: uutils (ubuntu-latest), Windows Git Bash

**Plan review:** 2026-11-02 — dforge:judge-opus — executability 14 / coherence 14 / coverage 15 / assumptions 13 (round 1)

## Global Constraints

- Every new script follows the existing dforge script conventions: `#!/usr/bin/env bash`, `set -uo pipefail`, `die()` printing `<script>: <message>` to stderr with exit 2 on usage errors, jq reading JSON files on stdin (`jq … < "$file"`), `tr -d '\r'` on every value read from a native tool.
- Every test, CLI and network command carries an explicit timeout; tests never run the real `agy`, only the stub under `plugins/dforge/tests/fixtures/stub-agy/` placed first on a sealed PATH.
- Tests never touch `$HOME/.claude` or `$HOME/.gemini`: they export `HOME`, `DR_AGY_SESSION_DIR`, `DR_AGY_POLICY` and `CLAUDE_CODE_SESSION_ID` to paths under the suite's own temporary directory, and unset `CLAUDE_CONFIG_DIR`.
- Every new suite under `plugins/dforge/tests/` gets a weight in `scripts/test-shards.mjs`, measured on this host and rounded as its neighbours are.
- `scripts/run-codex-task.sh`, `scripts/codex-gate` and their tests keep their current behaviour and output; existing fixtures change only where a task says so.
- Commits use `<type>(<scope>): <subject>` (subject 50 characters or fewer, imperative, no period), author `Darkraise <quangtc94@gmail.com>`, and no AI attribution of any kind.
- Windows Git Bash: a native program (`git.exe`, `jq.exe`, `agy.exe`) given a path built from `$PWD`, `$(pwd)` or `$TMPDIR` gets a POSIX form it cannot open, or has its argument rewritten when path conversion is on (`MSYS_NO_PATHCONV` unset). Convert the path with `cygpath -m` before the call (dforge's `dr_native_path`, `plugins/dforge/scripts/lib/native-path.sh`), and feed `jq` a file on stdin in a script that exports `MSYS_NO_PATHCONV`.
- Windows Git Bash: the same directory is `/c/Users/x` in the shell and `C:/Users/x` from a native tool, so a string comparison never matches. Normalise both sides with `cygpath -m`, or compare with `-ef`.
- Windows Git Bash: files a Windows tool wrote, and native program output, end lines with `\r`, which `read`, `awk` and `[ = ]` keep. Pipe through `tr -d '\r'` before comparing or parsing.
- Windows Git Bash: `awk -v name=value` processes backslash escapes in the value, so a regex or a Windows path changes. Pass the value in the environment and read `ENVIRON["NAME"]`.
- Windows Git Bash: Node's `import()` of an absolute `D:/x/y.mjs` reads `d:` as a URL scheme and fails. Import with `import(pathToFileURL(path).href)`.
- uutils (ubuntu-latest): a lock built on `mkdir` failing when the directory exists does not exclude a second process. Create the lock file with `set -C` (noclobber), or use `flock`.
- uutils (ubuntu-latest): `timeout` signals only the command it started, so the command's children keep running. Run the command in its own process group (`setsid`) and signal the group.

## Contracts

**C1. Executor priority.** Registry entries may carry `"priority": <non-negative integer>`. `plugins/dforge/reference/executors/codex.json` gains `"priority": 20`; `agy.json` has `"priority": 10`. `bash scripts/executors ranked` prints every valid id, one per line, by ascending priority then id; an entry whose priority is absent ranks after every entry with one; a priority that is not a non-negative integer counts as absent and prints `executors: <id>: priority is not a non-negative integer` to stderr. Exit 0; `executors ranked <extra>` is a usage error (exit 2). `executors list` output does not change.

**C2. Ladder blocks** in `plugins/dforge/reference/ladder.md`, fenced exactly as the existing blocks (```` ```<name> ```` … ```` ``` ````):

```agy-lane-gate
min_score 0
max_score 8
max_risk 2
require_rule_s_clean true
require_external_enabled true
```

```agy-assignment
0 gemini-3.8-flash medium
1 gemini-3.8-flash medium
2 gemini-3.8-flash medium
3 claude-sonnet-5-5 medium
4 claude-sonnet-5-5 medium
5 claude-sonnet-5-5 high
6 claude-opus-5-5 high
7 claude-opus-5-5 high
8 claude-opus-5-5 high
```

```agy-successor
gemini-3.8-flash/medium claude-sonnet-5-5/medium
claude-sonnet-5-5/medium claude-sonnet-5-5/high
claude-sonnet-5-5/high claude-opus-5-5/high
claude-opus-5-5/high HANDBACK
```

```agy-timeout
gemini-3.8-flash/medium 900
claude-sonnet-5-5/medium 1200
claude-sonnet-5-5/high 1800
claude-opus-5-5/high 2400
```

Rows 0-2 of `agy-assignment`, the Gemini row of `agy-successor` and the Gemini row of `agy-timeout` are provisional until Task 7 rewrites them from calibration. Rank of a rung `<model>/<effort>` is `model_rank * 10 + effort_rank`: any model starting `gemini-` ranks 0, `claude-sonnet-5-5` 1, `claude-opus-5-5` 2; `low` 0, `medium` 1, `high` 2.

**C3. Stub `agy`.** `plugins/dforge/tests/fixtures/stub-agy/agy` (executable bash). Every call appends one line per argument, then a `--` line, to `$STUB_AGY_ARGS_LOG` when set. `agy --version` prints `${STUB_AGY_VERSION:-1.4.12}`. `agy models` prints `Fetching available models...` then `gemini-3.8-flash-medium<TAB>Gemini 3.8 Flash (Medium)` and `claude-sonnet-5-5-medium<TAB>Claude Sonnet 5.5 (Medium)` and exits 0, unless `STUB_AGY_AUTH=logged-out` (prints `Please sign in: run agy to log in` to stderr, exit 1) or `STUB_AGY_AUTH=broken` (exit 3, no output). A print-mode call (any call with `-p`) behaves per `STUB_AGY_MODE`:
- `done` (default): writes `$STUB_AGY_WRITE` (a path relative to the working directory, default `out.txt`) with content `stub`, prints `{"conversation_id":"${STUB_AGY_CONV:-conv-1}","status":"SUCCESS","response":"ok","structured_output":{"status":"DONE","summary":"stub summary","commit_subject":"feat(stub): add out","questions":[],"discovered_issues":[],"assumptions":[]},"usage":{"total_tokens":10}}`, exit 0;
- `blocked`: as `done` but `structured_output.status` is `BLOCKED` and nothing is written;
- `no-schema`: prints the `done` object without `structured_output`, exit 0;
- `error`: prints `{"conversation_id":"","status":"ERROR","response":"","error":"${STUB_AGY_ERROR:-something failed}","finished_reason":"error"}`, exit 1;
- `print-timeout`: prints `{"conversation_id":"conv-1","status":"SUCCESS","response":"","finished_reason":"print_timeout"}`, writes `[agy] print timeout after 5s with turn in progress; returning partial output` to stderr, exit 0;
- `hang`: starts `sleep 300 &` (a child in its process group), then `sleep 300` in the foreground;
- `git-commit`, `git-stash`, `git-branch`: does the `done` write, then runs `git add -A && git commit -qm stub`, `git stash -q -u` (with `-u`, because the stub's own write is untracked and a plain stash would move no ref), or `git branch stub-branch` respectively, then prints the `done` object;
- `outside-write`: does the `done` write and also writes `$STUB_AGY_OUTSIDE` (an absolute path), then prints the `done` object.

**C4. `scripts/agy-locate`.** No arguments. Finds `agy` on PATH; reads `agy --version` (bounded at 20 s, first line, `\r` stripped). Prints `agy-locate ok version=<v> root=<dir of the agy executable>` and exits 0 when `<v>` is at least `min_version` and below `max_major + 1` of the policy; otherwise prints `agy-locate off reason=plugin-not-installed` (no `agy` on PATH, or no version printed) or `agy-locate off reason=plugin-version:<v>` and exits 1. Policy path: `${DR_AGY_POLICY:-<plugin>/reference/agy-policy.json}`.

**C5. `reference/agy-policy.json`:** `{"cli": "agy", "min_version": "1.4.12", "max_major": 1, "calibrated": "1.4.12", "trust": {"smoke": "fail"}}`. Task 7 sets `trust.smoke` to `"pass"`.

**C6. `scripts/lib/agy-probe.mjs`.** `node agy-probe.mjs <root>`; stdin `{"op":"auth","cwd":"<path>"}`; runs `<root>/agy models` (falling back to `agy` on PATH) with a 30 s bound; stdout one JSON line `{"authed":true}` when it exits 0 and prints at least one line matching `^[a-z0-9.-]+\t`, `{"authed":false}` when its output matches `/sign in|log ?in|login|unauthenticated/i`, `{"authed":null}` otherwise. Any op other than `auth` prints `{"authed":null}` and exits 2.

**C7. `scripts/agy-gate [--refresh]`.** Prints one line `agy-gate usable=<true|false> reason=<r> review=false lane=<true|false> resets_at=- source=<probe|cache|setting>`, exit 0 (exit 2 on usage error or missing jq/node, or an unreadable policy file). Reasons: `ok`, `setting` (agyLane off; no probe), `plugin-not-installed`, `plugin-version:<v>`, `logged-out`, `probe-failed`, `quota`. `lane=true` only when usable, a session id exists (`CLAUDE_CODE_SESSION_ID`), `trust.smoke` is `pass`, and `agyLane` is on; usable but untrusted prints `usable=true reason=ok lane=false`. Session file (via `executor_session_file agy`, directory `${DR_AGY_SESSION_DIR:-…/agy-sessions}`): `{session_id, usable, review:false, lane, reason, checked_at, resets_at:null, resets_at_epoch:null, agy_version}`. Without `--refresh`, every cached answer except one whose reason is `setting` is reused, as `codex-gate` does; with `--refresh` everything is re-probed **except** a cached `usable:false, reason:"quota"`, which is kept for the session.

**C8. Setting `agyLane`** in `plugins/dforge/config/schema.mjs`, directly after `codexReview`:
`agyLane: { type: 'boolean', default: true, enforcedBy: 'script', group: 'Workflow', target: 'dforge', label: 'Agy tasks', title: 'Give tasks to Antigravity', description: 'Give plan tasks to the Antigravity CLI (agy) when its gate passes. Off keeps those tasks on Claude or Codex.' },`

**C9. `scripts/run-agy-task.sh`.** Same flags, control operations (`--recover-commit`, `--handback`, `--release`, `--amend-write-set`, `--accept-baseline`), durable task record and exit codes as `scripts/run-codex-task.sh`: 0 when DONE, 1 when the run ended not DONE, 2 on refusal before the run or a post-run failure needing recovery. `AGY_TASK_GATE` replaces the gate script path (tests point it at a stub gate). `--model` must appear in column 2 of `agy-assignment`; `--effort` one of `low medium high`; the timeout comes from `agy-timeout` keyed `<model>/<effort>` unless `--timeout` is given. The prompt file is `$DR_TASK_DIR/prompt/attempt-<n>.md` (brief, then `## Repository conventions (CLAUDE.md)` / `(AGENTS.md)` sections, then `scripts/agy-task-contract.md`). `agy` is invoked in `--cwd` with exactly: `--output-format json --json-schema <native path of scripts/agy-report-schema.json> --model <m> --effort <e> --dangerously-skip-permissions --add-dir <native path of $DR_TASK_DIR/prompt> --print-timeout <t>s [--conversation <thread>] -p "Your complete instructions are in <native path of the prompt file>. Read the whole file first and follow it."`. It runs in its own process group (`setsid` when available) under `timeout -k 10 <t + ${AGY_TASK_GRACE:-60}>` (`AGY_TASK_GRACE` exists so tests can shorten the outer margin), as a background job whose pid is kept and `wait`ed. Status line (last stdout line): `agy <model>/<effort> status=<DONE|BLOCKED|NEEDS_CONTEXT> exit=<0|1|124> commits=<a7>..<b7> thread=<conversation_id|unknown> report=<path>` followed by ` note=timed-out` and/or ` note=writer-unconfirmed` when they apply. The report (`--report` path) has the Codex report's sections with `- executor: agy <model> / <effort>`, and on a non-DONE run an `## Agy error` section whose fenced block holds `reason=<quota|timeout|unknown-model|error>`, `timedOut=true` (on either deadline), then the raw `.error` text.

**C10. Failure classification** in `run-agy-task.sh`: `exit=124` and `reason=timeout` when `.finished_reason == "print_timeout"` or the outer `timeout` fired; else `exit=1` when `agy` exited non-zero or `.status == "ERROR"`; else 0. `reason=quota` when `.error` matches `quota|rate.?limit|RESOURCE_EXHAUSTED|429` (case-insensitive), and then `executor_session_mark_off agy quota`. `reason=unknown-model` when `.error` matches `unknown model|model .* not (found|available|supported|recognized)` (case-insensitive). Otherwise `reason=error`. `writer_stopped=no` (task blocked, `note=writer-unconfirmed`) when, after `wait` and a TERM to the process group, any non-zombie process of that group is still listed by `ps -eo pid=,pgid=,stat=`; on Windows (`uname -s` matching `MINGW*|MSYS*`) whenever the outer `timeout` fired.

**C11. Git guard.** Before the run the wrapper saves `git for-each-ref --format='%(refname) %(objectname)'` and `git symbolic-ref -q HEAD` (repository of `--cwd`) to `$DR_TASK_DIR/refs-before.txt`; after the run, before staging, any difference blocks the task via `dr_task_block "agy changed git refs: <first differing refname>"`, and an index change blocks it naming the index, before staging; the run then reports `status=BLOCKED exit=1`. `scripts/agy-task-contract.md` tells the agent it must not run any git command that writes (add, commit, stash, reset, checkout, switch, rebase, branch, tag, update-ref, worktree).

**C12. `scripts/agy-report-schema.json`** is byte-identical to `scripts/codex-report-schema.json`.

**C13. `reference/executors/agy.json`:**
`{"id":"agy","locator":"scripts/agy-locate","probe":{"command":"scripts/lib/agy-probe.mjs","op":"auth"},"gate":"scripts/agy-gate","wrapper":"scripts/run-agy-task.sh","reference":"reference/executor-lane.md","session_dir":"agy-sessions","session_dir_env":"DR_AGY_SESSION_DIR","surfaces":["lane"],"priority":10,"blocks":{"gate":"agy-lane-gate","assignment":"agy-assignment","successor":"agy-successor","timeout":"agy-timeout"},"reasons":{"not_installed":"agy is not on PATH; install the Antigravity CLI","not_enabled":"agy is not usable on this machine","logged_out":"agy is installed but not signed in; run agy and sign in","probe_failed":"the agy auth probe failed; run agy models to see why"}}`
(pretty-printed with two-space indentation like `codex.json`).

**C14. Routing rule.** For a task, the chosen executor is the first id in `executors ranked` order that is named on the header's `> **External executors:**` line and whose gate block admits the task (total within `min_score`..`max_score`, risk at most `max_risk`, Rule S clean, no `**Override:**`). The header lists ticked ids comma-separated in ranked order, e.g. `> **External executors:** agy, codex`. `plan-lint` ERROR text: `Executor names <eid> but <first> ranks first and admits total <t>`. The lane-eligible WARN names the chosen executor and its rung: `lane-eligible with no **Executor:** line (<first> <rung>)`. `plan-revise` prints a unit's `rungs=` entries in ranked order.

**C15. `scripts/lane-breaker PLAN_FILE <id>`.** Reads the plan's ledger (`plan_ledger`). A task counts as a handback of `<id>` when it has an assignment line containing `executor <id> ` and any line for that task containing `HANDBACK`. Prints `lane-breaker <id> state=<open|tripped> handbacks=<n>` and exits 0; `tripped` when `n >= 2`, or when the ledger holds a line `Plan: executor <id> off - unreliable (<k> handbacks)`. No ledger: `state=open handbacks=0`. Exit 2 on usage error.

**C16. Calibration record:** `docs/dforge/notes/2026-11-02-agy-calibration.md`, a table with one row per run: `| Task replayed | Rung | Status | Tests | Scope | Judge | Wall s | Tokens |`, then a `**Decision:**` line naming the chosen 0-2 rung. Constraint added to `docs/superpowers/distilled/constraints.md` under `## Execution lanes`: heading `### The Antigravity executor lane is on`, body `When scripts/agy-gate reports lane=true, the planner ticks agy without asking and lists it before codex on the External executors line.`, then `Set by: owner, 2026-11-02 spec review ("Auto-tick (Recommended)")`, `Scope: every plan written for this repository on a Claude host`, `Source: docs/dforge/specs/2026-11-02-antigravity-executor-lane-design.md`.

## Assumptions (evidence)

- `agy -p` headless edits, JSON output, `--json-schema` → `structured_output`, `--conversation` resume, `--model`/`--effort`, exit 0/1: `agy` 1.4.12 runs in the scratchpad, 2026-11-02 (spec §Measured behaviour).
- `--print-timeout` returns exit 0 with `finished_reason: "print_timeout"`: measured 2026-11-02, `--print-timeout 5s` on `sleep 60`.
- Prompt via stdin is impossible and a 189 KB argument fails; pointer prompt plus `--add-dir` works: measured 2026-11-02.
- On uutils `timeout` does not signal the command's children: `plugins/dforge/reference/ci-parity.md` Pitfalls table; hence `setsid` in C9.
- `dr_task_validate_scope` already fails on HEAD or index change: `plugins/dforge/scripts/lib/task-state.sh:255`.
- plan-revise survey mode counts every registered executor, ticked or not: `plugins/dforge/scripts/plan-revise:232`; its survey cases at `plugins/dforge/tests/plan-revise.test.sh:276-278` read the real registry.
- Real `agy` behaviour on a full dforge task brief: unverified — Task 7 verifies it.
- Spec A4's batched clause needs no lint rule: batching is a dispatch-time choice that never appears in plan text, and `plugins/dforge/skills/subagent-driven-development/references/batching.md:10` already says "A batched task never runs on an external executor", for every executor. Task 8 tests the risk-3 and override clauses.
- `agy --version` prints the bare version and a newline (`1.4.12`); `agy models` prints one `<id><TAB><display name>` line per model on stdout (e.g. `gemini-4-argon-medium\tGemini 4 Argon (Medium)`) and `Fetching available models...` on stderr: `agy --version | od -c` and `agy models 2>/dev/null | od -c`, 2026-11-02. C4's first-line read and C6's `^[a-z0-9.-]+\t` match this; the stub's extra stdout line is harmless to both.
- Logged-out and quota error texts of `agy`: unverified and accepted — never observed, and no task can provoke them on demand. C6 and C10 patterns stand until a real occurrence; Task 7 records in its calibration notes any logged-out or quota text it meets.
- The Codex lane is off in this session (`codex-gate usable=false reason=setting`, 2026-11-02), so no task carries an `**Executor:**` line and the plan is Claude-only.
- Plan review round 1 scored assumptions 13 (borderline): its two assumption findings were answered by measuring `agy --version` and `agy models` (recorded above) and by accepting the unobservable logged-out and quota texts; depth standard caps review at one round.

## Task index

1. Rank executors by priority
2. Add the agy ladder blocks
3. Add the agy locator, auth probe and gate
4. Run a task on agy through a pointer prompt
5. Classify agy failures and confirm the writer stopped
6. Register agy and retire the antigravity row
7. Calibrate the Gemini rung and open the lane
8. Route each task to the first admitting executor
9. Stop offering agy after two handbacks in a plan
10. Document the agy lane and release 4.10.0

---

### Task 1: Rank executors by priority

**Files:**
- Modify: `plugins/dforge/scripts/executors` (header comment, usage text, new `ranked` subcommand)
- Modify: `plugins/dforge/reference/executors/codex.json` (add `"priority": 20`)
- Modify: `plugins/dforge/tests/fixtures/executors/codex.json` (the same one-line change; `executors.test.sh` requires it to equal the shipped entry)
- Test: `plugins/dforge/tests/executors.test.sh`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: Contract C1 (`executors ranked`, the optional `priority` field, `"priority": 20` on `codex.json`). Tasks 6 and 8 read `ranked` order.

**Implementer:** dforge:impl-opus-high
**Evaluation:** files 1 - spec 2 - coupling 2 - risk 1 = 6

- [ ] **Step 1: Write the failing test**

Edit `plugins/dforge/tests/executors.test.sh` in two places. The helpers `check`, `run`, `entry`, `EXEC`, `TMP`, `P` and `FIX` already exist.

First, insert this block immediately before the line `# --- usage -----------------------------------------------------------------`:

```bash
# --- ranked ------------------------------------------------------------------
# Priority decides which executor planning tries first. A malformed value must
# neither drop the entry nor abort the listing: it ranks as if absent, with one
# line on stderr.
mkdir -p "$TMP/rank"
rentry() { # rentry <id> [priority as a JSON literal]; no second argument leaves priority out
  jq -n --arg id "$1" --arg p "${2-}" '{id:$id, locator:"scripts/x-plugin",
    probe:{command:"scripts/lib/x-client.mjs", op:"auth"},
    wrapper:"scripts/run-x-task.sh", session_dir:($id + "-sessions"),
    surfaces:["lane"], blocks:{gate:"gate"}}
    + (if $p == "" then {} else {priority: ($p | fromjson)} end)' > "$TMP/rank/$1.json"
}
rentry alpha 20; rentry beta 10; rentry aardvark 10; rentry eta 0
rentry lambda 9; rentry theta 100
rentry gamma; rentry delta '"x"'; rentry epsilon -1; rentry zeta 1.5

check "ranked orders by ascending priority, numerically, ties by id, then the unranked by id" \
  "$(run "$TMP/rank" ranked 2>/dev/null | tr '\n' ' ')" \
  "eta lambda aardvark beta alpha theta delta epsilon gamma zeta "
check "ranked exits 0" "$(run "$TMP/rank" ranked >/dev/null 2>&1; echo $?)" "0"
check "ranked reports each invalid priority once on stderr and nothing else" \
  "$(run "$TMP/rank" ranked 2>&1 >/dev/null | sort | tr '\n' '|')" \
  "executors: delta: priority is not a non-negative integer|executors: epsilon: priority is not a non-negative integer|executors: zeta: priority is not a non-negative integer|"
check "ranked takes no argument" "$(run "$TMP/rank" ranked extra >/dev/null 2>&1; echo $?)" "2"
check "list ignores priority and stays silent about it" \
  "$(run "$TMP/rank" list 2>&1 | tr '\n' ' ')" \
  "aardvark alpha beta delta epsilon eta gamma lambda theta zeta "
check "a registry without priorities ranks by id" "$(run "$TMP/reg" ranked | tr '\n' ' ')" "alpha beta "
check "an empty registry ranks nothing and still exits 0" "$(run "$TMP/empty" ranked; echo "rc=$?")" "rc=0"
check "ranked skips a malformed entry like list does" \
  "$(printf 'not json\n' > "$TMP/reg/broken.json"; run "$TMP/reg" ranked 2>/dev/null | tr '\n' ' '; rm -f "$TMP/reg/broken.json")" "alpha beta "
check "the shipped codex entry carries priority 20" "$(bash "$EXEC" get codex priority)" "20"
check "the shipped registry ranks codex" "$(bash "$EXEC" ranked | grep -cx codex)" "1"

```

Second, insert this check immediately before the final `printf '\n%d passed, %d failed\n'` line:

```bash
check "the fixture registry ranks the prioritised codex entry before the unranked ones" \
  "$(run "$FIX" ranked | tr '\n' ' ')" "codex opencode stub "
```

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 300 bash plugins/dforge/tests/executors.test.sh`
Expected: FAIL. Every new `ranked` check fails (`executors: unknown subcommand: ranked`, exit 2), and `the shipped codex entry carries priority 20` fails because `codex.json` has no priority. The existing checks still pass.

- [ ] **Step 3: Implement**

1. `plugins/dforge/reference/executors/codex.json` and `plugins/dforge/tests/fixtures/executors/codex.json`: add `"priority": 20` as a top-level field after `"session_dir_env"`, keeping the two files byte-identical and the two-space indentation. `agy.json` (Task 6) will carry 10.
2. `plugins/dforge/scripts/executors`: add a `ranked` subcommand to the `case "$1"` dispatch. It takes no further argument (`executors ranked <extra>` is `die "usage: executors ranked"`, exit 2), and the top-of-file `Usage:` comment and the no-argument usage text both list it.
3. `ranked` starts from `list_ids`, so an invalid entry is skipped with the same stderr diagnostics `list` gives. For each valid id it reads the entry's `priority` with `jq` on stdin (`jq … < "$file"`, `tr -d '\r'` on the result). Three outcomes: the key is absent (silent, ranks after every prioritised entry); the key holds a JSON number that is `>= 0` and has no fractional part (a valid priority, `1.0` counts); any other value, including `null`, a string, a negative or fractional number (prints `executors: <id>: priority is not a non-negative integer` to stderr, then ranks as absent). Print each id on its own line, ordered by: prioritised before unranked, then priority numerically ascending, then id in byte order (`LC_ALL=C sort`). Exit 0 whatever the contents.
4. `list`, `get` and `path` do not change: `list` must not read or mention `priority`, and `valid_entry` stays as it is.

- [ ] **Step 4: Run test to verify it passes**

Run: `timeout 300 bash plugins/dforge/tests/executors.test.sh`
Expected: PASS, `0 failed`.

Run: `timeout 300 bash plugins/dforge/tests/executor-session.test.sh && timeout 600 bash plugins/dforge/tests/detect.test.sh`
Expected: PASS (neither suite is edited; both read the registry through `executors list` and `get`, which this task leaves unchanged).

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/scripts/executors plugins/dforge/reference/executors/codex.json plugins/dforge/tests/fixtures/executors/codex.json plugins/dforge/tests/executors.test.sh
git commit -m "feat(dforge): rank executors by priority"
```

### Task 2: Add the agy ladder blocks

**Files:**
- Modify: `plugins/dforge/reference/ladder.md` (section `## The external lane`: add the four agy blocks, rename the lane-gate heading, add per-executor subsections)
- Test: `plugins/dforge/tests/lanes.test.sh`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: Contract C2, the blocks `agy-lane-gate`, `agy-assignment`, `agy-successor`, `agy-timeout`, with the rank formula (any `gemini-` model 0, `claude-sonnet-5-5` 1, `claude-opus-5-5` 2; `low` 0, `medium` 1, `high` 2). Tasks 4, 5, 6, 7 and 8 read these blocks by name through `ladder_block` (`scripts/lib/plan.sh`), which matches the fence line exactly, so the existing `assignment` and `gate` blocks are not affected by the new names.

**Implementer:** dforge:impl-opus-high
**Evaluation:** files 1 - spec 2 - coupling 2 - risk 1 = 6

- [ ] **Step 1: Write the failing test**

Edit `plugins/dforge/tests/lanes.test.sh`. Insert this block immediately before the final `printf '\n%d passed, %d failed\n'` line. It reuses the file's `block`, `in_list` and `check` helpers and the `LADDER` variable, and defines its own `agy_` names so it never touches the Codex section's `assignment`, `successor` or `timeouts` variables. Rows 0-2 of `agy-assignment` are checked for well-formedness only, because the calibration task (Task 7) replaces them.

```bash
# --- the agy lane --------------------------------------------------------------
# agy admits wider bands than Codex, so its blocks are checked on their own.
AGY_MODELS="gemini-3.8-flash gemini-4-argon claude-sonnet-5-5 claude-opus-5-5"
AGY_EFFORTS="low medium high"

agy_gate=$(block agy-lane-gate)
agy_gate_field() { printf '%s\n' "$agy_gate" | awk -v k="$1" '$1 == k {print $2}'; }
check "agy-lane-gate has five lines" "$(printf '%s\n' "$agy_gate" | grep -c .)" "5"
check "agy-lane-gate min_score is 0" "$(agy_gate_field min_score)" "0"
check "agy-lane-gate max_score is 8" "$(agy_gate_field max_score)" "8"
check "agy-lane-gate max_risk is 2" "$(agy_gate_field max_risk)" "2"
check "agy-lane-gate requires a clean Rule S pass" "$(agy_gate_field require_rule_s_clean)" "true"
check "agy-lane-gate requires an enabled executor" "$(agy_gate_field require_external_enabled)" "true"

agy_assignment=$(block agy-assignment)
check "agy-assignment has 9 rows" "$(printf '%s\n' "$agy_assignment" | grep -c .)" "9"
bad_agy=NONE agy_scores=""
while read -r score model effort extra; do
  [ -n "$score" ] || continue
  in_list "$model" "$AGY_MODELS" || bad_agy="model:$score:$model"
  in_list "$effort" "$AGY_EFFORTS" || bad_agy="effort:$score:$effort"
  [ -z "$extra" ] || bad_agy="extra-field:$score"
  agy_scores="$agy_scores $score"
done <<< "$agy_assignment"
check "every agy-assignment rung names a known model and effort" "$bad_agy" "NONE"
check "agy-assignment has one row for each total 0 through 8" \
  "$(printf '%s\n' $agy_scores | sort -n | tr '\n' ' ')" "0 1 2 3 4 5 6 7 8 "
check "agy-assignment rows 3 to 8 mirror the native Claude table" \
  "$(printf '%s\n' "$agy_assignment" | awk '$1 >= 3' | tr '\n' ',')" \
  "3 claude-sonnet-5-5 medium,4 claude-sonnet-5-5 medium,5 claude-sonnet-5-5 high,6 claude-opus-5-5 high,7 claude-opus-5-5 high,8 claude-opus-5-5 high,"
check "the lowest agy-assignment row is the gate's min_score" \
  "$(printf '%s\n' "$agy_assignment" | awk 'NR == 1 || $1 < m { m = $1 } END { print m }')" "$(agy_gate_field min_score)"
check "the highest agy-assignment row is the gate's max_score" \
  "$(printf '%s\n' "$agy_assignment" | awk '$1 > m { m = $1 } END { print m }')" "$(agy_gate_field max_score)"

agy_rank() { # agy_rank <model>/<effort>: model_rank * 10 + effort_rank, or -1
  local m="${1%%/*}" e="${1##*/}" mr er
  case "$m" in gemini-*) mr=0 ;; claude-sonnet-5-5) mr=1 ;; claude-opus-5-5) mr=2 ;; *) echo -1; return ;; esac
  case "$e" in low) er=0 ;; medium) er=1 ;; high) er=2 ;; *) echo -1; return ;; esac
  echo $((mr * 10 + er))
}

agy_successor=$(block agy-successor)
agy_succ_of() { printf '%s\n' "$agy_successor" | awk -v k="$1" '$1 == k {print $2}'; }

bad_agy_rank=NONE
while read -r from to; do
  [ -n "$from" ] || continue
  [ "$to" = HANDBACK ] && continue
  from_rank=$(agy_rank "$from"); to_rank=$(agy_rank "$to")
  { [ "$from_rank" -lt 0 ] || [ "$to_rank" -lt 0 ]; } && { bad_agy_rank="unrankable:$from->$to"; continue; }
  [ "$to_rank" -gt "$from_rank" ] || bad_agy_rank="not-increasing:$from->$to"
done <<< "$agy_successor"
check "every agy-successor ranks strictly above its source" "$bad_agy_rank" "NONE"

bad_agy_family=NONE
while read -r from to; do
  case "$from" in gemini-*) case "$to" in claude-*) ;; *) bad_agy_family="$from->$to" ;; esac ;; esac
done <<< "$agy_successor"
check "a failed Gemini rung moves to a Claude rung, never to another Gemini effort" "$bad_agy_family" "NONE"

bad_agy_walk=NONE
while read -r start _; do
  [ -n "$start" ] || continue
  cur="$start"
  for _ in 1 2 3 4 5 6; do
    [ "$cur" = HANDBACK ] && break
    cur=$(agy_succ_of "$cur")
    [ -n "$cur" ] || { bad_agy_walk="dead-end-from:$start"; break; }
  done
  [ "$cur" = HANDBACK ] || bad_agy_walk="${bad_agy_walk#NONE}no-terminal-from:$start"
  [ "$bad_agy_walk" = NONE ] || break
done <<< "$agy_successor"
check "every agy-successor rung reaches HANDBACK without cycling" "$bad_agy_walk" "NONE"

bad_agy_entry=NONE
while read -r _ model effort; do
  [ -n "$model" ] || continue
  [ -n "$(agy_succ_of "$model/$effort")" ] || bad_agy_entry="$model/$effort"
done <<< "$agy_assignment"
check "every agy-assignment rung has a successor" "$bad_agy_entry" "NONE"

agy_timeouts=$(block agy-timeout)
bad_agy_timeout=NONE
while read -r from to; do
  [ -n "$from" ] || continue
  for rung in "$from" "$to"; do
    [ "$rung" = HANDBACK ] && continue
    secs=$(printf '%s\n' "$agy_timeouts" | awk -v k="$rung" '$1 == k {print $2}')
    [ -n "$secs" ] || { bad_agy_timeout="missing:$rung"; continue; }
    printf '%s' "$secs" | grep -qE '^[1-9][0-9]*$' || bad_agy_timeout="non-numeric:$rung"
  done
done <<< "$agy_successor"
while read -r _ model effort; do
  [ -n "$model" ] || continue
  [ -n "$(printf '%s\n' "$agy_timeouts" | awk -v k="$model/$effort" '$1 == k {print $2}')" ] || bad_agy_timeout="missing:$model/$effort"
done <<< "$agy_assignment"
check "every agy rung named in an assignment or a successor row has a numeric timeout" "$bad_agy_timeout" "NONE"

agy_too_long=NONE
while read -r pair secs; do
  [ -n "$pair" ] || continue
  [ $(( (secs + 120) * 1000 )) -le 7200000 ] || agy_too_long="$pair:$secs"
done <<< "$agy_timeouts"
check "every agy-timeout bound plus 120 s fits a background call's 7200000 ms cap" "$agy_too_long" "NONE"

check "no agy block names a Codex model" \
  "$(printf '%s\n' "$agy_gate" "$agy_assignment" "$agy_successor" "$agy_timeouts" | grep -c 'gpt-')" "0"

# --- ladder.md prose, one subsection per executor ------------------------------
check "ladder.md has a lane-gate subsection for each executor" \
  "$(grep -cE '^### The (Codex|agy) lane gate$' "$LADDER")" "2"
check "the single, executor-neutral lane-gate heading is gone" "$(grep -cxF '### The lane gate' "$LADDER")" "0"
check "ladder.md gives agy its assignment, successor and timeout subsections" \
  "$(grep -cE '^### Agy (assignment|successor|timeout)$' "$LADDER")" "3"
check "the agy gate subsection states why its floor is 0" \
  "$(grep -cF '`agy-lane-gate` has a floor of 0 because' "$LADDER")" "1"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 300 bash plugins/dforge/tests/lanes.test.sh`
Expected: FAIL. The `agy-lane-gate` field checks fail (the blocks do not exist, so every `block` call is empty), `agy-assignment has 9 rows` fails with `0`, and the four prose checks fail (`### The Codex lane gate` is still `### The lane gate`). Every pre-existing check still passes.

- [ ] **Step 3: Implement**

All edits are in `plugins/dforge/reference/ladder.md`, under `## The external lane`. Do not change any existing fenced block, and keep every sentence that `tests/ladder.test.sh` and the Codex half of `tests/lanes.test.sh` already pin (for example "`max_score 4` keeps them on the Claude ladder", "for tasks totalling 0 to 8 below", the `gpt-6.1-sol` rows and the `codex-judge` prose).

1. Rename the heading `### The lane gate` to `### The Codex lane gate`. Its fenced ```` ```gate ```` block and prose stay as they are (the registry entry for Codex still names the block `gate`).
2. In the section's opening paragraph, add one sentence saying that each registered executor has its own gate block named in its registry entry, and that planning consults executors in `executors ranked` order. Keep the existing sentence that the Claude ladder remains the sole backstop.
3. After the last existing subsection (`### Codex judge rung`), append the agy subsections in this order, each with its fenced block exactly as Contract C2 gives it (copy the block text from C2, fence tag included):
   - `### The agy lane gate`: the `agy-lane-gate` block, then prose. It states that all five conditions must hold; that `max_score 8` is Rule S's own ceiling (reducible 5 plus risk 3), so the gate adds no cap beyond it; that `max_risk 2` keeps risk-3 tasks on the Claude ladder; and why the floor differs from Codex's. One line of that prose must contain the exact phrase "`agy-lane-gate` has a floor of 0 because" (backticks included), followed by the reason: Codex's floor of 2 exists because a score-0 offload costs more to orchestrate than `impl-sonnet-low` costs to run, whereas `agy`'s purpose is to move work onto another quota, so even a score-0 task it takes is Claude quota saved.
   - `### Agy assignment`: the `agy-assignment` block, then prose saying totals 3 to 8 mirror the native Claude table (Sonnet medium, Sonnet high, Opus high) and that the models are those `agy models` lists.
   - `### Agy successor`: the `agy-successor` block, then prose in the style of the Codex successor section: a single-successor column consulted at most once per task; a failed Gemini run moves to Claude rather than to a higher Gemini effort, because the second attempt should differ in model family; `HANDBACK` resolves to the Claude assignment-table row for the task's score; the rank formula `model_rank * 10 + effort_rank` with every `gemini-` model 0, `claude-sonnet-5-5` 1, `claude-opus-5-5` 2 and efforts `low` 0, `medium` 1, `high` 2, which makes every successor rank strictly higher so every walk reaches `HANDBACK`.
   - `### Agy timeout`: the `agy-timeout` block, then one line saying the values are seconds.
4. Write no sentence in these subsections about the Gemini rows being provisional; Task 7 rewrites rows 0-2, the Gemini successor row and the Gemini timeout row without touching prose.

- [ ] **Step 4: Run test to verify it passes**

Run: `timeout 300 bash plugins/dforge/tests/lanes.test.sh`
Expected: PASS, `0 failed`.

Run: `timeout 300 bash plugins/dforge/tests/ladder.test.sh && timeout 1500 bash plugins/dforge/tests/plan-lint.test.sh && timeout 900 bash plugins/dforge/tests/plan-revise.test.sh`
Expected: PASS (these suites read `ladder.md` through `ladder_block` and must be unchanged by the new blocks and the renamed heading).

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/reference/ladder.md plugins/dforge/tests/lanes.test.sh
git commit -m "feat(dforge): add the agy ladder blocks"
```

### Task 3: Add the agy locator, auth probe and gate

Make `agy` detectable and gated for a session. The task is built in two parts that share one test suite, `plugins/dforge/tests/agy-gate.test.sh`: Part A adds the stub `agy` of Contract C3, the policy file, the locator and the auth probe; Part B adds the session gate and the `agyLane` setting on top of them. Task 4 and later tasks run the wrapper against the stub and call `agy-gate`; Task 6 registers the entry that names these scripts.

#### Part A: Add the stub agy, locator, policy and auth probe

**Files:**
- Create: `plugins/dforge/tests/fixtures/stub-agy/agy` (executable; the stub agy of Contract C3, used by this task's tests and by Tasks 4, 5, 6 and 7)
- Create: `plugins/dforge/scripts/agy-locate` (executable)
- Create: `plugins/dforge/reference/agy-policy.json`
- Create: `plugins/dforge/scripts/lib/agy-probe.mjs`
- Modify: `scripts/test-shards.mjs` (weight for the new suite)
- Test: `plugins/dforge/tests/agy-gate.test.sh` (new; holds the shared setup, the stub, policy, locator and probe sections and the final summary line. Part B appends the gate section)

**Interfaces:**
- Consumes: nothing from earlier tasks beyond the shared libraries already in the repository; the locator and probe read the policy file and spawn `agy`.
- Produces: Contracts C3 (the stub), C4 (`agy-locate`), C5 (`agy-policy.json`) and C6 (`agy-probe.mjs`). Part B consumes the locator, the probe, the policy file, the stub and the suite's shared setup (`check`, `skip`, `SEAL`, `SPAWNABLE`, `POLICY`).

**Implementer:** dforge:impl-sonnet-high
**Evaluation:** files 1 - spec 2 - coupling 2 - risk 0 = 5

- [ ] **Step 1: Write the failing test**

Create two things: the stub and the suite.

**1a. Create `plugins/dforge/tests/fixtures/stub-agy/agy`** with exactly this content, then `chmod +x` it. The `git stash` call uses `-u` because the stub's own write is an untracked file, and a plain `git stash` would then change no ref.

```bash
#!/usr/bin/env bash
# Stand-in for the Antigravity CLI. STUB_AGY_* variables choose what it does;
# STUB_AGY_ERROR must not contain a double quote or a backslash.
set -u

if [ -n "${STUB_AGY_ARGS_LOG:-}" ]; then
  { for arg in "$@"; do printf '%s\n' "$arg"; done; printf '%s\n' '--'; } >> "$STUB_AGY_ARGS_LOG"
fi

if [ "${1:-}" = --version ]; then
  printf '%s\n' "${STUB_AGY_VERSION:-1.4.12}"
  exit 0
fi

if [ "${1:-}" = models ]; then
  case "${STUB_AGY_AUTH:-ok}" in
    logged-out) printf 'Please sign in: run agy to log in\n' >&2; exit 1 ;;
    broken) exit 3 ;;
  esac
  printf 'Fetching available models...\n'
  printf 'gemini-3.8-flash-medium\tGemini 3.8 Flash (Medium)\n'
  printf 'claude-sonnet-5-5-medium\tClaude Sonnet 5.5 (Medium)\n'
  exit 0
fi

print_mode=no
for arg in "$@"; do [ "$arg" = -p ] && print_mode=yes; done
[ "$print_mode" = yes ] || { printf 'stub-agy: unsupported call\n' >&2; exit 64; }

conv="${STUB_AGY_CONV:-conv-1}"
write_file() { printf 'stub\n' > "${STUB_AGY_WRITE:-out.txt}"; }
structured() { # structured <status>
  printf '{"status":"%s","summary":"stub summary","commit_subject":"feat(stub): add out","questions":[],"discovered_issues":[],"assumptions":[]}' "$1"
}
emit() { # emit <structured_output status | none>
  if [ "$1" = none ]; then
    printf '{"conversation_id":"%s","status":"SUCCESS","response":"ok","usage":{"total_tokens":10}}\n' "$conv"
  else
    printf '{"conversation_id":"%s","status":"SUCCESS","response":"ok","structured_output":%s,"usage":{"total_tokens":10}}\n' \
      "$conv" "$(structured "$1")"
  fi
}

case "${STUB_AGY_MODE:-done}" in
  done) write_file; emit DONE ;;
  blocked) emit BLOCKED ;;
  no-schema) write_file; emit none ;;
  error)
    printf '{"conversation_id":"","status":"ERROR","response":"","error":"%s","finished_reason":"error"}\n' \
      "${STUB_AGY_ERROR:-something failed}"
    exit 1 ;;
  print-timeout)
    printf '{"conversation_id":"conv-1","status":"SUCCESS","response":"","finished_reason":"print_timeout"}\n'
    printf '[agy] print timeout after 5s with turn in progress; returning partial output\n' >&2 ;;
  hang) sleep 300 & sleep 300 ;;
  git-commit) write_file; git add -A && git commit -qm stub; emit DONE ;;
  git-stash) write_file; git stash -q -u; emit DONE ;;
  git-branch) write_file; git branch stub-branch; emit DONE ;;
  outside-write) write_file; printf 'stub\n' > "$STUB_AGY_OUTSIDE"; emit DONE ;;
  *) printf 'stub-agy: unknown STUB_AGY_MODE\n' >&2; exit 64 ;;
esac
```

**1b. Create `plugins/dforge/tests/agy-gate.test.sh`** with exactly this content, then `chmod +x` it. The probe spawns `agy` from Node, and Node on Windows cannot run a bash-script stub; the suite detects that (`SPAWNABLE`) and prints `skip` lines for the cases that need a usable probe instead of failing them.

```bash
#!/usr/bin/env bash
# The agy gate decides whether a session may hand tasks to Antigravity, so every
# way it can say no is asserted here against the stub agy under
# fixtures/stub-agy. No case starts the real agy.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
P="$(cd "$HERE/.." && pwd)"
STUBDIR="$(cd "$HERE/fixtures/stub-agy" && pwd)"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
# The gate reads ~/.dforge/config.json; a temporary home keeps the real one out.
export HOME="$TMP/home"
mkdir -p "$HOME" "$TMP/work"
unset CLAUDE_CONFIG_DIR

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
skip() { printf 'skip - %s\n' "$1"; }

# A PATH holding every tool the scripts use and no agy, so "not installed" does
# not depend on the host having none. Only the directories of the tools the
# scripts run are linked: on Windows the rest of PATH is System32.
SEAL="$TMP/seal"
mkdir -p "$SEAL"
while IFS= read -r dir; do
  for tool in "$dir"/*; do
    name=${tool##*/}
    case "$name" in agy|agy.exe) continue ;; esac
    [ -e "$SEAL/$name" ] || ln -s "$tool" "$SEAL/$name" 2>/dev/null
  done
done < <(for tool in bash node jq git cat date; do dirname "$(type -P "$tool")"; done | sort -u)
# A Chocolatey shim such as jq.exe finds its program from its own directory, so
# these run from where they are. The link goes first: writing to it would
# overwrite the program it names.
for tool in jq node git; do
  rm -f "$SEAL/$tool"
  printf '#!%s\nexec "%s" "$@"\n' "$BASH" "$(type -P "$tool")" > "$SEAL/$tool"
  chmod +x "$SEAL/$tool"
done

# Node cannot run a bash-script stub on Windows; the probe cases need it to.
SPAWNABLE=$(node -e 'const r = require("child_process").spawnSync(process.argv[1], ["--version"], { encoding: "utf8" }); console.log(r.status === 0 ? "yes" : "no")' "$STUBDIR/agy" 2>/dev/null | tr -d '\r')

POLICY="$TMP/policy.json"
jq '.trust.smoke = "pass"' "$P/reference/agy-policy.json" > "$POLICY" 2>/dev/null
HIGHFLOOR="$TMP/highfloor.json"
jq '.min_version = "1.5.0"' "$POLICY" > "$HIGHFLOOR" 2>/dev/null

# --- the stub itself ---------------------------------------------------------
# Tasks 4 to 7 drive the wrapper through this stub, so its own shapes are pinned.
check "the stub is executable" "$([ -x "$STUBDIR/agy" ] && echo yes || echo no)" "yes"
check "the stub prints its version" "$("$STUBDIR/agy" --version | tr -d '\r')" "1.4.12"
check "the stub lists two model ids after its banner" \
  "$("$STUBDIR/agy" models | tr -d '\r' | grep -c "$(printf '^[a-z0-9.-]*\t')")" "2"
check "the stub can be logged out" "$(STUB_AGY_AUTH=logged-out "$STUBDIR/agy" models >/dev/null 2>&1; echo $?)" "1"
check "the stub can be broken" "$(STUB_AGY_AUTH=broken "$STUBDIR/agy" models >/dev/null 2>&1; echo $?)" "3"
mkdir -p "$TMP/stubwork"
stub_out=$(cd "$TMP/stubwork" && STUB_AGY_ARGS_LOG="$TMP/stub-args.log" "$STUBDIR/agy" --model m -p hi)
check "a print call logs one line per argument then a separator" \
  "$(tr '\n' ' ' < "$TMP/stub-args.log")" "--model m -p hi -- "
check "a print call reports DONE with a conversation id" \
  "$(jq -r '[.structured_output.status, .conversation_id, (.usage.total_tokens | tostring)] | join(",")' <<<"$stub_out")" "DONE,conv-1,10"
check "a print call writes the file the done mode names" "$(tr -d '\r' < "$TMP/stubwork/out.txt")" "stub"
stub_out=$(cd "$TMP/stubwork" && STUB_AGY_MODE=error STUB_AGY_ERROR='quota exhausted' "$STUBDIR/agy" -p hi; echo "rc=$?")
check "the error mode prints status ERROR, the text and exit 1" \
  "$(jq -sR -r 'split("\n") | [(.[0] | fromjson | [.status, .error, .finished_reason] | join(",")), .[1]] | join(" ")' <<<"$stub_out")" \
  "ERROR,quota exhausted,error rc=1"
stub_out=$(cd "$TMP/stubwork" && STUB_AGY_MODE=print-timeout "$STUBDIR/agy" -p hi 2>"$TMP/stub-err"; echo "rc=$?")
check "the print-timeout mode succeeds with finished_reason print_timeout" \
  "$(head -1 <<<"$stub_out" | jq -r '[.status, .finished_reason] | join(",")') $(tail -1 <<<"$stub_out")" "SUCCESS,print_timeout rc=0"
check "the print-timeout mode writes the timeout line to stderr" \
  "$(grep -c 'print timeout after 5s with turn in progress' "$TMP/stub-err")" "1"

# --- the policy file ---------------------------------------------------------
check "the policy states the cli, the version floor, the major ceiling and the calibrated version" \
  "$(jq -r '[.cli, .min_version, (.max_major | tostring), .calibrated] | join(",")' "$P/reference/agy-policy.json" 2>/dev/null | tr -d '\r')" \
  "agy,1.4.12,1,1.4.12"
# Task 7 flips fail to pass in its own commit; either value is valid here.
check "the policy records the smoke gate as fail or pass" \
  "$(jq -r '.trust.smoke | if . == "fail" or . == "pass" then "valid" else . end' "$P/reference/agy-policy.json" 2>/dev/null | tr -d '\r')" "valid"

# --- the locator -------------------------------------------------------------
loc() { # loc [args...]; sets out and rc. LOC_PATH and LOC_POLICY override the defaults.
  out=$(cd "$TMP/work" && PATH="${LOC_PATH:-$STUBDIR:$SEAL}" DR_AGY_POLICY="${LOC_POLICY:-$POLICY}" \
    "$BASH" "$P/scripts/agy-locate" "$@" 2>"$TMP/err"); rc=$?
  out=${out//$'\r'/}
}
check "agy-locate exists" "$([ -f "$P/scripts/agy-locate" ] && echo yes || echo no)" "yes"
loc
check "an agy inside the range is ok, with its directory as root" "$out" "agy-locate ok version=1.4.12 root=$STUBDIR"
check "ok exits 0" "$rc" "0"
STUB_AGY_VERSION=1.9.3 loc
check "a minor above the floor is ok" "$out" "agy-locate ok version=1.9.3 root=$STUBDIR"
STUB_AGY_VERSION=1.4.11 loc
check "a version below the floor is off" "$out" "agy-locate off reason=plugin-version:1.4.11"
check "off exits 1" "$rc" "1"
STUB_AGY_VERSION=2.0.0 loc
check "a major above the ceiling is off" "$out" "agy-locate off reason=plugin-version:2.0.0"
STUB_AGY_VERSION=$'1.4.12\r' loc
check "a carriage return after the version is stripped" "$out" "agy-locate ok version=1.4.12 root=$STUBDIR"
STUB_AGY_VERSION=$'1.4.12\nsecond line' loc
check "only the first line of the version output counts" "$out" "agy-locate ok version=1.4.12 root=$STUBDIR"
LOC_POLICY="$HIGHFLOOR" loc
check "DR_AGY_POLICY replaces the policy path" "$out" "agy-locate off reason=plugin-version:1.4.12"
LOC_PATH="$SEAL" loc
check "no agy on PATH is not installed" "$out" "agy-locate off reason=plugin-not-installed"
check "not installed exits 1" "$rc" "1"
mkdir -p "$TMP/mute"
printf '#!/usr/bin/env bash\nexit 0\n' > "$TMP/mute/agy"; chmod +x "$TMP/mute/agy"
LOC_PATH="$TMP/mute:$SEAL" loc
check "an agy that prints no version counts as not installed" "$out" "agy-locate off reason=plugin-not-installed"
loc extra
check "an argument is a usage error" "$rc" "2"

# --- the probe ----------------------------------------------------------------
probe() { # probe <root> [stdin json]; prints the authed value
  local in=${2-}; [ -n "$in" ] || in='{"op":"auth","cwd":"."}'
  printf '%s' "$in" | (cd "$TMP/work" && PATH="$STUBDIR:$SEAL" node "$P/scripts/lib/agy-probe.mjs" "$1" 2>/dev/null) \
    | tail -1 | tr -d '\r' | jq -r '.authed | tostring'
}
check "agy-probe.mjs exists" "$([ -f "$P/scripts/lib/agy-probe.mjs" ] && echo yes || echo no)" "yes"
if [ "$SPAWNABLE" = yes ]; then
  check "a clean exit listing a model id is authed" "$(probe "$STUBDIR")" "true"
  check "output asking for a sign-in is not authed" "$(STUB_AGY_AUTH=logged-out probe "$STUBDIR")" "false"
  check "a failure that asks for nothing is unknown" "$(STUB_AGY_AUTH=broken probe "$STUBDIR")" "null"
  mkdir -p "$TMP/empty-root"
  check "a root without agy falls back to agy on PATH" "$(probe "$TMP/empty-root")" "true"
  check "an op other than auth answers null" "$(probe "$STUBDIR" '{"op":"quota","cwd":"."}')" "null"
  check "an op other than auth exits 2" \
    "$(printf '{"op":"quota","cwd":"."}' | PATH="$STUBDIR:$SEAL" node "$P/scripts/lib/agy-probe.mjs" "$STUBDIR" >/dev/null 2>&1; echo $?)" "2"
else
  skip "the probe cases: Node cannot run the bash-script stub on this platform"
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
```

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 600 bash plugins/dforge/tests/agy-gate.test.sh`
Expected: FAIL. The stub-itself checks pass. Every policy, locator and probe check fails (`agy-locate`, `agy-probe.mjs` and `reference/agy-policy.json` do not exist); the suite ends with a non-zero `failed` count.

- [ ] **Step 3: Implement**

1. **`plugins/dforge/reference/agy-policy.json`** (Contract C5, a configuration value; two-space indentation):

```json
{
  "cli": "agy",
  "min_version": "1.4.12",
  "max_major": 1,
  "calibrated": "1.4.12",
  "trust": { "smoke": "fail" }
}
```

2. **`plugins/dforge/scripts/agy-locate`** (Contract C4; `#!/usr/bin/env bash`, `set -uo pipefail`, `die()` printing `agy-locate: <message>` with exit 2; header comment in the style of `scripts/codex-plugin`). It takes no argument (usage error otherwise) and requires `jq` and a readable policy at `${DR_AGY_POLICY:-$HERE/../reference/agy-policy.json}`. It finds `agy` with `command -v`; none on PATH prints `agy-locate off reason=plugin-not-installed` and exits 1. It runs `agy --version` bounded at 20 seconds (under `timeout 20` when `timeout` exists), takes the first line with `\r` stripped, and treats an empty result the same as no agy (`plugin-not-installed`). It compares the version with the policy using the semver comparison `scripts/codex-plugin` uses (numeric components, at least `min_version`, first component at most `max_major`); outside the range it prints `agy-locate off reason=plugin-version:<v>` and exits 1. Otherwise it prints `agy-locate ok version=<v> root=<directory of the agy executable>` and exits 0.
3. **`plugins/dforge/scripts/lib/agy-probe.mjs`** (Contract C6; header comment in the style of `scripts/lib/codex-client.mjs`). `node agy-probe.mjs <root>` reads `{"op":"auth","cwd":"<path>"}` from stdin and always writes exactly one JSON line to stdout. Any op other than `auth`, or unreadable input, writes `{"authed":null}` and exits 2. For `auth` it runs `<root>/agy models` with `spawnSync` (no shell, 30 000 ms timeout, `cwd` from the request when it is a non-empty string, output as UTF-8), and falls back to `agy` on PATH when `<root>/agy` cannot be spawned. It joins stdout and stderr and answers `{"authed":true}` when the exit status is 0 and at least one line matches `^[a-z0-9.-]+\t`; otherwise `{"authed":false}` when the output matches `/sign in|log ?in|login|unauthenticated/i`; otherwise `{"authed":null}` (a timeout or a spawn failure included). It exits 0 for every answered `auth` request. Write the line with a callback on `process.stdout.write` before `process.exit`, as `codex-gate.mjs` does, so a piped answer is not dropped on Windows.
4. Mark `agy-locate` executable (`chmod +x`) and record that in git (`git add --chmod=+x`), as is `tests/fixtures/stub-agy/agy` and `tests/agy-gate.test.sh`.

- [ ] **Step 4: Run test to verify it passes**

Run: `timeout 600 bash plugins/dforge/tests/agy-gate.test.sh`
Expected: PASS, `0 failed` (on a platform where Node can run the stub; on Windows the probe cases print `skip` and the rest pass).

- [ ] **Step 5: Weight the suite and check the repository tests**

Every dforge shell suite needs a weight in `scripts/test-shards.mjs`. Time both suites in one session: `time timeout 600 bash plugins/dforge/tests/codex-gate.test.sh` and `time timeout 600 bash plugins/dforge/tests/agy-gate.test.sh`. Add `'agy-gate.test.sh': <w>,` to `windowsSeconds`, in alphabetical position (before `'auto-default.test.sh'`), where `<w>` is codex-gate's existing weight (122) multiplied by the ratio of the two measured wall times, rounded to the nearest multiple of 5, and at least 10. Part B re-measures it once the gate cases exist.

Run: `timeout 300 node --test tests/test-shards.test.mjs tests/repository-layout.test.mjs`
Expected: PASS (`test-shards.test.mjs` fails without the weight).

Run: `timeout 300 node scripts/validate-repository.mjs`
Expected: exit 0.

- [ ] **Step 6: Commit**

```bash
git add plugins/dforge/scripts/agy-locate plugins/dforge/scripts/lib/agy-probe.mjs plugins/dforge/reference/agy-policy.json plugins/dforge/tests/fixtures/stub-agy/agy plugins/dforge/tests/agy-gate.test.sh scripts/test-shards.mjs
git add --chmod=+x plugins/dforge/scripts/agy-locate plugins/dforge/tests/fixtures/stub-agy/agy plugins/dforge/tests/agy-gate.test.sh
git commit -m "feat(dforge): add the agy locator and auth probe"
```

#### Part B: Add the agy gate and the agyLane setting

**Files:**
- Create: `plugins/dforge/scripts/agy-gate` (executable)
- Modify: `plugins/dforge/config/schema.mjs` (add `agyLane` directly after `codexReview`)
- Modify: `scripts/test-shards.mjs` (re-measured weight for the suite)
- Test: `plugins/dforge/tests/agy-gate.test.sh` (append the gate section), `plugins/dforge/tests/dforge-config.test.sh` (extended)

**Interfaces:**
- Consumes: Part A's `scripts/agy-locate`, `scripts/lib/agy-probe.mjs`, `reference/agy-policy.json`, the stub `tests/fixtures/stub-agy/agy` and the suite `tests/agy-gate.test.sh`; `scripts/lib/executor-session.sh` (`executor_session_file`, `executor_session_write`), `scripts/lib/native-path.sh` (`dr_native_path`) and `scripts/lib/dforge-env.sh` (`dforge_setting`), all unchanged; `scripts/executors get` (Task 1 leaves it unchanged).
- Produces: Contracts C7 (`agy-gate`) and C8 (`agyLane`). Task 4 replaces the gate with a stub through `AGY_TASK_GATE`; the wrapper first calls the real `agy-gate` in Task 6, which registers the entry that names it.

**Implementer:** dforge:impl-opus-high
**Evaluation:** files 1 - spec 2 - coupling 2 - risk 1 = 6

The registry entry `agy.json` is Task 6's. Until then `executor_session_file agy` cannot find `session_dir`, so this part's gate tests point `DR_EXECUTORS_DIR` at a private registry holding a minimal `agy` entry.

- [ ] **Step 1: Write the failing test**

Make two edits: append the gate section to the suite, and extend `dforge-config.test.sh`.

**1a. Append the gate section to `plugins/dforge/tests/agy-gate.test.sh`.** Insert exactly this text directly after the closing `fi` of the probe section (the line before the blank line that precedes `printf '\n%d passed, %d failed\n' ...`). It uses the suite's existing `check`, `skip`, `SEAL`, `STUBDIR`, `SPAWNABLE` and `POLICY`. On Windows the cases that need a usable probe print `skip` instead of failing.

```bash
UNTRUSTED="$TMP/untrusted.json"
jq '.trust.smoke = "fail"' "$P/reference/agy-policy.json" > "$UNTRUSTED" 2>/dev/null

# --- the gate ------------------------------------------------------------------
REG="$TMP/reg"
mkdir -p "$REG"
jq -n '{id:"agy", locator:"scripts/agy-locate",
  probe:{command:"scripts/lib/agy-probe.mjs", op:"auth"},
  gate:"scripts/agy-gate", wrapper:"scripts/run-agy-task.sh",
  reference:"reference/executor-lane.md", session_dir:"agy-sessions",
  session_dir_env:"DR_AGY_SESSION_DIR", surfaces:["lane"], blocks:{gate:"agy-lane-gate"}}' > "$REG/agy.json"
SESS="$TMP/sessions"
ARGS="$TMP/args.log"
gate() { # gate [args...]; sets out and rc. GATE_PATH, GATE_POLICY and SID override the defaults.
  out=$(cd "$TMP/work" && PATH="${GATE_PATH:-$STUBDIR:$SEAL}" DR_AGY_POLICY="${GATE_POLICY:-$POLICY}" \
    DR_EXECUTORS_DIR="$REG" DR_AGY_SESSION_DIR="$SESS" CLAUDE_CODE_SESSION_ID="${SID-s1}" \
    STUB_AGY_ARGS_LOG="$ARGS" "$BASH" "$P/scripts/agy-gate" "$@" 2>"$TMP/err"); rc=$?
}
field() { jq -r ".$1 | tostring" "$SESS/s1.json" 2>/dev/null | tr -d '\r'; }
fresh() { rm -rf "$SESS" "$ARGS"; }
setting() { mkdir -p "$HOME/.dforge"; printf '%s\n' "$1" > "$HOME/.dforge/config.json"; }
mark_off() { (export DR_EXECUTORS_DIR="$REG" DR_AGY_SESSION_DIR="$SESS" CLAUDE_CODE_SESSION_ID=s1
  . "$P/scripts/lib/executor-session.sh"; executor_session_mark_off agy "$1"); }

check "agy-gate exists" "$([ -f "$P/scripts/agy-gate" ] && echo yes || echo no)" "yes"

fresh; GATE_PATH="$SEAL" gate
check "no agy on PATH turns the gate off" "$out" \
  "agy-gate usable=false reason=plugin-not-installed review=false lane=false resets_at=- source=probe"
check "the gate exits 0 when it answers" "$rc" "0"
fresh; STUB_AGY_VERSION=1.4.11 gate
check "a version out of range turns the gate off" "$out" \
  "agy-gate usable=false reason=plugin-version:1.4.11 review=false lane=false resets_at=- source=probe"
check "a version out of range never runs the auth probe" "$(grep -c '^models$' "$ARGS" 2>/dev/null)" "0"

# A quota mark needs no probe: the gate keeps it for the session, --refresh included.
fresh; mark_off quota
gate
check "a quota mark is reported from the session file" "$out" \
  "agy-gate usable=false reason=quota review=false lane=false resets_at=- source=cache"
gate --refresh
check "--refresh keeps a cached quota instead of probing it away" "$out" \
  "agy-gate usable=false reason=quota review=false lane=false resets_at=- source=cache"
check "keeping a quota starts no agy" "$([ -f "$ARGS" ] && echo yes || echo no)" "no"
check "the kept quota stays in the session file" "$(field usable)/$(field reason)" "false/quota"
SID=s2 gate
check "another session does not inherit the quota" \
  "$(case "$out" in *reason=quota*) echo inherited ;; *) echo own ;; esac)" "own"

fresh; GATE_POLICY="$TMP/none.json" gate
check "a missing policy file is a usage-level failure" "$rc" "2"
gate --bogus
check "an unknown flag is a usage error" "$rc" "2"
gate --refresh extra
check "an extra argument is a usage error" "$rc" "2"

setting '{"agyLane":false}'
fresh; gate
check "agyLane off answers without a probe" "$out" \
  "agy-gate usable=false reason=setting review=false lane=false resets_at=- source=setting"
check "agyLane off starts no agy" "$([ -f "$ARGS" ] && echo yes || echo no)" "no"
check "agyLane off is written for the readers" "$(field usable)/$(field reason)/$(field lane)" "false/setting/false"
setting '{}'

if [ "$SPAWNABLE" = yes ]; then
  fresh; gate
  check "a usable, trusted agy opens the lane" "$out" \
    "agy-gate usable=true reason=ok review=false lane=true resets_at=- source=probe"
  check "the session file records the answer" \
    "$(field session_id)/$(field usable)/$(field review)/$(field lane)/$(field reason)/$(field agy_version)" "s1/true/false/true/ok/1.4.12"
  check "the session file carries no reset time" "$(field resets_at)/$(field resets_at_epoch)" "null/null"
  check "the probe ran once" "$(grep -c '^models$' "$ARGS")" "1"
  gate
  check "a second call answers from the cache" "$out" \
    "agy-gate usable=true reason=ok review=false lane=true resets_at=- source=cache"
  check "a cached answer runs no agy" "$(grep -c '^models$' "$ARGS")" "1"
  GATE_POLICY="$UNTRUSTED" gate
  check "trust is read on every call, cache hit included" "$out" \
    "agy-gate usable=true reason=ok review=false lane=false resets_at=- source=cache"
  gate --refresh
  check "--refresh re-probes an ordinary cached answer" "$out" \
    "agy-gate usable=true reason=ok review=false lane=true resets_at=- source=probe"
  check "the re-probe ran agy models again" "$(grep -c '^models$' "$ARGS")" "2"

  fresh; GATE_POLICY="$UNTRUSTED" gate
  check "a usable but untrusted agy opens no lane" "$out" \
    "agy-gate usable=true reason=ok review=false lane=false resets_at=- source=probe"

  fresh; STUB_AGY_AUTH=logged-out gate
  check "a logged-out agy is off" "$out" \
    "agy-gate usable=false reason=logged-out review=false lane=false resets_at=- source=probe"
  gate
  check "a cached logged-out answer is reused without --refresh" "$out" \
    "agy-gate usable=false reason=logged-out review=false lane=false resets_at=- source=cache"
  gate --refresh
  check "--refresh re-probes a logged-out answer and finds the login" "$out" \
    "agy-gate usable=true reason=ok review=false lane=true resets_at=- source=probe"

  fresh; STUB_AGY_AUTH=broken gate
  check "an auth probe that answers nothing is probe-failed" "$out" \
    "agy-gate usable=false reason=probe-failed review=false lane=false resets_at=- source=probe"

  fresh; gate
  mark_off quota
  gate --refresh
  check "a quota mark made after a good probe also survives --refresh" "$out" \
    "agy-gate usable=false reason=quota review=false lane=false resets_at=- source=cache"
  check "the quota survives with the probe never re-run" "$(grep -c '^models$' "$ARGS")" "1"

  fresh; SID= gate
  check "no session id still answers, with the lane closed" "$out" \
    "agy-gate usable=true reason=ok review=false lane=false resets_at=- source=probe"
  check "no session id writes no file" "$(ls "$SESS" 2>/dev/null | wc -l | tr -d ' ')" "0"

  fresh; setting '{"agyLane":false}'; gate
  setting '{}'; gate
  check "switching agyLane back on probes again" "$out" \
    "agy-gate usable=true reason=ok review=false lane=true resets_at=- source=probe"
else
  skip "the gate cases that need a usable probe: Node cannot run the bash-script stub on this platform"
fi
```

**1b. Extend `plugins/dforge/tests/dforge-config.test.sh`** in two places.

Add this row to the first `ROWS` table, directly under the `codexReview false true 0` line:

```
agyLane true false maybe
```

Insert this check immediately before the line `fresh ar-off`:

```bash
check "agyLane: follows codexReview, labelled Agy tasks, enforced by script" \
  "$(node --input-type=module -e "import { pathToFileURL } from 'node:url'; const { default: schema } = await import(pathToFileURL(process.argv[1]).href); const keys = Object.keys(schema); console.log([keys[keys.indexOf('codexReview') + 1], schema.agyLane?.label, schema.agyLane?.enforcedBy, schema.agyLane?.group].join(' | '))" "$(cd "$HERE/../config" && pwd)/schema.mjs")" \
  'agyLane | Agy tasks | script | Workflow'
```

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 600 bash plugins/dforge/tests/agy-gate.test.sh`
Expected: FAIL. The stub, policy, locator and probe checks pass. Every gate check fails (`agy-gate` does not exist); the suite ends with a non-zero `failed` count.

Run: `timeout 600 bash plugins/dforge/tests/dforge-config.test.sh`
Expected: FAIL on the `agyLane` rows (`agyLane: default` reads nothing, because the key is unknown) and on `agyLane: follows codexReview…` (the check prints `lensCap | undefined | undefined | undefined`, not the wanted line). All other checks pass.

- [ ] **Step 3: Implement**

1. **`plugins/dforge/config/schema.mjs`**: add the `agyLane` entry of Contract C8 directly after the `codexReview` entry, in the file's existing multi-line style, with exactly C8's fields and strings (`type: 'boolean'`, `default: true`, `enforcedBy: 'script'`, `group: 'Workflow'`, `target: 'dforge'`, `label: 'Agy tasks'` (16 characters or fewer), title and description as C8 gives them). Do not touch README.md (Task 10 documents the setting).
2. **`plugins/dforge/scripts/agy-gate`** (Contract C7; header comment and structure follow `scripts/codex-gate`, minus the review surface, `plugin_version`, reset times and the gate-timeout variable). Sources `lib/executor-session.sh`, `lib/native-path.sh` and `lib/dforge-env.sh`. Accepts no argument or `--refresh` only (`die "usage: agy-gate [--refresh]"` otherwise), requires `jq` and `node`, and dies with exit 2 when the policy file is not readable. In order:
   1. `agyLane` comes from `dforge_setting agyLane true`. When it is `false`, the answer is `usable=false reason=setting source=setting` with no locator run and no probe.
   2. Otherwise, with a session file (`executor_session_file agy`) that is readable and parses, reuse its answer as `source=cache` when its reason is not `setting` and either `--refresh` was not given or the cached answer is `usable:false, reason:"quota"`. Read the cached fields with a non-whitespace separator (`\u001f`), as `codex-gate` does, and treat a torn or unparsable file as a miss. Every other cached answer, usable or not, is reused without `--refresh` (there is no reset time to expire it) and re-probed with it.
   3. Otherwise probe: run `bash "$HERE/agy-locate"`. Exit 0 yields the version and root from its `ok` line; run the probe with `MSYS_NO_PATHCONV=1` exported, `node "$HERE/lib/agy-probe.mjs" "$(dr_native_path "$root")"`, stdin built with `jq -cn --arg cwd "$(dr_native_path "$PWD")" '{op:"auth",cwd:$cwd}'`, under `timeout 45` when `timeout` exists, reading the last output line with `tr -d '\r'`. `authed` true gives `usable=true reason=ok`, false gives `usable=false reason=logged-out`, anything else (including no answer) gives `usable=false reason=probe-failed`. Locator exit 1 gives `usable=false` with the locator's `reason=` text verbatim (`plugin-not-installed` or `plugin-version:<v>`); any other locator exit is `die "agy-locate failed"`.
   4. `trust.smoke` is read from the policy on every call, cache hit or probe (`jq … < "$POLICY"`, `tr -d '\r'`). `lane` is true only when `usable` is true, a session file path exists (a session id is set), `trust.smoke` is `"pass"` and `agyLane` is on; `review` is always `false`.
   5. With a session file path, write it with `executor_session_write agy`: `{session_id, usable, review:false, lane, reason, checked_at, resets_at:null, resets_at_epoch:null, agy_version}` (`agy_version` null when unknown). Then print `agy-gate usable=<b> reason=<r> review=false lane=<b> resets_at=- source=<probe|cache|setting>` and exit 0.
3. Mark `agy-gate` executable (`chmod +x`) and record that in git (`git add --chmod=+x`).

- [ ] **Step 4: Run test to verify it passes**

Run: `timeout 600 bash plugins/dforge/tests/agy-gate.test.sh`
Expected: PASS, `0 failed` (on a platform where Node can run the stub; on Windows the probe and gate cases print `skip` and the rest pass).

Run: `timeout 600 bash plugins/dforge/tests/dforge-config.test.sh && timeout 600 bash plugins/dforge/tests/codex-gate.test.sh && timeout 300 bash plugins/dforge/tests/executor-session.test.sh`
Expected: PASS.

- [ ] **Step 5: Re-measure the suite weight and check the repository tests**

The suite now holds the gate cases, which dominate its run time. Time both suites in one session: `time timeout 600 bash plugins/dforge/tests/codex-gate.test.sh` and `time timeout 600 bash plugins/dforge/tests/agy-gate.test.sh`. Replace the value of `'agy-gate.test.sh': <w>,` that Part A added in `windowsSeconds` with `<w>` = codex-gate's existing weight (122) multiplied by the ratio of the two measured wall times, rounded to the nearest multiple of 5, and at least 10.

Run: `timeout 300 node --test tests/test-shards.test.mjs tests/repository-layout.test.mjs`
Expected: PASS. The `agyLane` label's 16-character limit is checked by `node scripts/validate-repository.mjs` (line 222); run it too: `timeout 120 node scripts/validate-repository.mjs`.

Run: `timeout 300 node scripts/validate-repository.mjs`
Expected: exit 0.

- [ ] **Step 6: Commit**

```bash
git add plugins/dforge/scripts/agy-gate plugins/dforge/config/schema.mjs plugins/dforge/tests/agy-gate.test.sh plugins/dforge/tests/dforge-config.test.sh scripts/test-shards.mjs
git add --chmod=+x plugins/dforge/scripts/agy-gate
git commit -m "feat(dforge): add the agy gate and agyLane setting"
```

### Task 4: Run a task on agy through a pointer prompt

**Files:**
- Create: `plugins/dforge/scripts/run-agy-task.sh`
- Create: `plugins/dforge/scripts/agy-report-schema.json` (a byte copy of `codex-report-schema.json`)
- Create: `plugins/dforge/scripts/agy-task-contract.md`
- Modify: `scripts/test-shards.mjs` (weight for the new suite)
- Test: `plugins/dforge/tests/run-agy-task.test.sh` (new)
- Read, not changed: `plugins/dforge/scripts/run-codex-task.sh` (the model to follow; it keeps its behaviour and output), `plugins/dforge/scripts/lib/task-state.sh`, `plugins/dforge/scripts/lib/task-execution.sh`, `plugins/dforge/scripts/lib/executor-session.sh`, `plugins/dforge/scripts/lib/native-path.sh`

**Interfaces:**
- Consumes: the `agy-assignment` and `agy-timeout` ladder blocks (C2, Task 2); the stub `agy` at `plugins/dforge/tests/fixtures/stub-agy/agy` (C3, created by Task 3); the gate line shape of C7 (the suite replaces the gate through `AGY_TASK_GATE`, so Task 3's `agy-gate` is not run here); the shared libraries unchanged: `dr_task_open`, `dr_task_update`, `dr_task_stage`, `dr_task_block`, `dr_task_validate_scope`, `dr_task_control`, `dr_snapshot`, `dr_canonical`, `dr_native_path`.
- Produces: `scripts/run-agy-task.sh` with C9's flags, control operations, prompt file, invocation, durable record, report and status line (classification of failures, the git guard and the writer-stopped scan are Task 5's, on top of this script); `scripts/agy-report-schema.json` (C12); `scripts/agy-task-contract.md` (the contract text C11 describes); the environment variable `AGY_TASK_GRACE` (seconds added to the timeout for the outer `timeout` bound, default 60; the suite sets it to 1 so an outer timeout takes seconds, nothing else sets it); the `--dry-run` output, `would-run:` then one JSON line with keys `model`, `effort`, `timeoutSeconds` (a number) and `conversation` (the resume thread or `null`); the suite `run-agy-task.test.sh` whose helpers Tasks 5 and 6 extend.

**Implementer:** dforge:impl-opus-high
**Evaluation:** files 1 - spec 2 - coupling 2 - risk 2 = 7

The wrapper is a sibling of `run-codex-task.sh`, not a refactor of it: copy that script's structure and keep every line of it that this task does not replace.

- [ ] **Step 1: Write the failing test**

Create `plugins/dforge/tests/run-agy-task.test.sh` with exactly this content (no `chmod`; the other suites are mode 100644 and run through `bash`).

```bash
#!/usr/bin/env bash
# The agy wrapper reaches a paid model through a pointer prompt, so these cases
# assert what the stub agy was handed and what the wrapper left behind. No case
# starts a real agy.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
P="$(cd "$HERE/.." && pwd)"
SCRIPT="$P/scripts/run-agy-task.sh"
STUBDIR="$HERE/fixtures/stub-agy"
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}

# Every path the suite writes lives under $fixture, and the real session files,
# policy and Antigravity login stay out of reach.
export HOME="$fixture/home" DR_AGY_SESSION_DIR="$fixture/sessions" DR_AGY_POLICY="$fixture/policy.json" \
  CLAUDE_CODE_SESSION_ID=run-agy-task-test CLAUDE_PROJECT_DIR=
unset CLAUDE_CONFIG_DIR
mkdir -p "$HOME"
printf '{"cli":"agy","min_version":"1.4.12","max_major":1,"calibrated":"1.4.12","trust":{"smoke":"pass"}}\n' > "$DR_AGY_POLICY"
export STUB_AGY_ARGS_LOG="$fixture/args.log"
export PATH="$STUBDIR:$PATH"
check "agy resolves to the stub" "$([ "$(command -v agy)" -ef "$STUBDIR/agy" ] && echo yes || echo no)" "yes"

printf '#!/usr/bin/env bash\nprintf "%%s\\n" "${GATE_STUB_LINE:-agy-gate usable=true reason=ok review=false lane=true resets_at=- source=cache}"\n' > "$fixture/gate-stub"
export AGY_TASK_GATE="$fixture/gate-stub"

native() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi; }
calls() { if [ -f "$STUB_AGY_ARGS_LOG" ]; then grep -c '^-p$' "$STUB_AGY_ARGS_LOG" || true; else echo 0; fi; }
last_call() { awk '$0 == "--" { last = cur; cur = ""; next } { cur = cur $0 "\n" } END { printf "%s", last }' "$STUB_AGY_ARGS_LOG"; }
arg_after() { last_call | tr -d '\r' | awk -v f="$1" 'p { print; exit } $0 == f { p = 1 }'; }
has_arg() { last_call | tr -d '\r' | grep -qxF -- "$1" && echo yes || echo no; }

git init -q "$fixture/primary"
git -C "$fixture/primary" config user.email fixture@example.com
git -C "$fixture/primary" config user.name Fixture
git -C "$fixture/primary" config core.autocrlf false
printf 'base\n' > "$fixture/primary/base.txt"
printf 'claude conventions\n' > "$fixture/primary/CLAUDE.md"
printf 'agents conventions\n' > "$fixture/primary/AGENTS.md"
git -C "$fixture/primary" add base.txt CLAUDE.md AGENTS.md
git -C "$fixture/primary" commit -qm 'test: seed fixture'
printf 'Implement only the approved files.\n' > "$fixture/brief.md"
printf '["base.txt","out.txt","second.txt","new file.txt"]\n' > "$fixture/scope.json"

newwork() { # newwork <name>; sets W (worktree) and R (human report)
  W="$fixture/$1"; R="$fixture/$1.report.md"
  git -C "$fixture/primary" worktree add -qb "$1" "$W"
}
run() { bash "$SCRIPT" --cwd "$W" --task-id task-one --write-set "$fixture/scope.json" \
  --brief "$fixture/brief.md" --report "$R" --model claude-sonnet-5-5 --effort medium "$@" > "$fixture/out" 2> "$fixture/err"; }
dry() { bash "$SCRIPT" --brief "$fixture/brief.md" --report "$fixture/dry.md" --cwd "$fixture/primary" --dry-run "$@" 2>"$fixture/err"; }
dry_rc() { dry "$@" >/dev/null; echo $?; }
state_of() { # state_of <worktree>
  printf '%s/dforge/tasks/%s/state.json' "$(git -C "$1" rev-parse --absolute-git-dir)" "$(printf task-one | git -C "$1" hash-object --stdin)"
}
status_line() { tail -1 "$fixture/out" | tr -d '\r'; }

# --- the files the wrapper reads ----------------------------------------------
check "the wrapper exists" "$([ -f "$SCRIPT" ] && echo yes || echo no)" "yes"
check "the report schema is byte-identical to the codex schema" \
  "$(cmp -s "$P/scripts/agy-report-schema.json" "$P/scripts/codex-report-schema.json" && echo yes || echo no)" "yes"
for word in add commit stash reset checkout switch rebase branch tag update-ref worktree; do
  check "the contract forbids git $word" \
    "$(grep -qF "git $word" "$P/scripts/agy-task-contract.md" && echo yes || echo no)" "yes"
done
for field in status summary commit_subject questions discovered_issues assumptions; do
  check "the contract names the $field field" \
    "$(grep -qF "\`$field\`" "$P/scripts/agy-task-contract.md" && echo yes || echo no)" "yes"
done

# --- validation happens before anything is spawned ----------------------------
check "rejects a model absent from agy-assignment" "$(dry_rc --model gpt-4o --effort medium)" "2"
check "rejects a codex model" "$(dry_rc --model gpt-6.1-sol --effort medium)" "2"
check "rejects xhigh, which only codex accepts" "$(dry_rc --model claude-sonnet-5-5 --effort xhigh)" "2"
check "rejects a multi-word effort" "$(dry_rc --model claude-sonnet-5-5 --effort 'medium high')" "2"
check "rejects a rung with no agy-timeout row" "$(dry_rc --model claude-opus-5-5 --effort low)" "2"
check "rejects a non-numeric timeout" "$(dry_rc --model claude-sonnet-5-5 --effort medium --timeout 30m)" "2"
check "rejects an unknown flag" "$(dry_rc --model claude-sonnet-5-5 --effort medium --bogus x)" "2"
check "rejects a missing brief" \
  "$(bash "$SCRIPT" --brief "$fixture/nope.md" --report "$fixture/r.md" --cwd "$fixture/primary" --model claude-sonnet-5-5 --effort medium --dry-run >/dev/null 2>&1; echo $?)" "2"
check "a trailing flag with no value exits 2 rather than hanging" \
  "$(timeout 10 bash "$SCRIPT" --brief "$fixture/brief.md" --report "$fixture/r.md" --cwd "$fixture/primary" --model claude-sonnet-5-5 --effort medium --resume >/dev/null 2>&1; echo $?)" "2"
check "accepts a valid rung" "$(dry_rc --model claude-sonnet-5-5 --effort medium)" "0"
check "validation reaches agy never" "$(calls)" "0"
req=$(dry --model claude-sonnet-5-5 --effort medium | sed -n '2p')
check "dry run: the timeout comes from agy-timeout" "$(jq -r '.timeoutSeconds' <<<"$req")" "1200"
check "dry run: an explicit timeout wins" \
  "$(dry --model claude-sonnet-5-5 --effort high --timeout 42 | sed -n '2p' | jq -r '.timeoutSeconds')" "42"
check "dry run: a resume names its conversation" \
  "$(dry --model claude-sonnet-5-5 --effort medium --resume conv-9 | sed -n '2p' | jq -r '.conversation')" "conv-9"
check "dry run: a fresh run names no conversation" "$(jq -r '.conversation' <<<"$req")" "null"

# --- a closed lane never reaches agy -------------------------------------------
newwork closed
GATE_STUB_LINE='agy-gate usable=false reason=quota review=false lane=false resets_at=- source=cache' run
check "a closed lane is refused" "$?" "2"
check "a closed lane names the gate reason" "$(grep -c 'agy lane is off for this session (quota)' "$fixture/err")" "1"
check "a closed lane never launches agy" "$(calls)" "0"

# --- a DONE run commits the approved write set (A6) ----------------------------
newwork happy
base="$(git -C "$W" rev-parse HEAD)"
run
check "a DONE run exits 0" "$?" "0"
head="$(git -C "$W" rev-parse HEAD)"
line="$(status_line)"
check "the status line names rung, status, exit, commits and thread" \
  "${line%% report=*}" "agy claude-sonnet-5-5/medium status=DONE exit=0 commits=${base:0:7}..${head:0:7} thread=conv-1"
check "the status line names a report that exists" "$([ -f "${line##*report=}" ] && echo yes || echo no)" "yes"
check "the commit holds the produced file" "$(git -C "$W" show HEAD:out.txt 2>/dev/null)" "stub"
check "the commit holds nothing else" "$(git -C "$W" show --name-only --format= HEAD | tr -d '\r')" "out.txt"
check "the commit carries the reported subject" "$(git -C "$W" log -1 --format=%s)" "feat(stub): add out"
check "the report names the rung" "$(grep -c '^- executor: agy claude-sonnet-5-5 / medium$' "$R")" "1"
check "the report carries the summary" "$(grep -A2 '^## Summary$' "$R" | tail -1 | tr -d '\r')" "stub summary"
check "the report says None for empty assumptions" "$(grep -A2 '^## Assumptions made$' "$R" | tail -1 | tr -d '\r')" "None"
state="$(state_of "$W")"
check "the record is complete" "$(jq -r .phase "$state")" "complete"
check "the record keeps the conversation" "$(jq -r .thread "$state")" "conv-1"
check "the record points the prompt artifact at the prompt directory" \
  "$(jq -r .artifacts.prompt "$state" | grep -c '/prompt/attempt-1\.md$')" "1"

# --- the prompt reaches agy as a pointer only (A10) ---------------------------
taskdir="$(cd "$(dirname "$state")" && pwd -P)"
promptfile="$taskdir/prompt/attempt-1.md"
check "the prompt file holds the brief" "$(head -1 "$promptfile" | tr -d '\r')" "Implement only the approved files."
check "the prompt file inlines CLAUDE.md under its heading" \
  "$(grep -A2 '^## Repository conventions (CLAUDE.md)$' "$promptfile" | tail -1 | tr -d '\r')" "claude conventions"
check "the prompt file inlines AGENTS.md under its heading" \
  "$(grep -A2 '^## Repository conventions (AGENTS.md)$' "$promptfile" | tail -1 | tr -d '\r')" "agents conventions"
check "the prompt file ends with the task contract" "$(grep -c '^## How to complete this task$' "$promptfile")" "1"
# Paths are compared by identity, not by spelling: on Windows an 8.3 TEMP makes
# the wrapper's native form and this suite's differ while naming one file.
posix() { if command -v cygpath >/dev/null 2>&1; then cygpath -u "$1"; else printf '%s' "$1"; fi; }
same() { [ "$(posix "$1")" -ef "$2" ] && echo same || echo "differs: $1"; }
pointer="$(arg_after -p)"
pointed="${pointer#Your complete instructions are in }"; pointed="${pointed%. Read the whole file first and follow it.}"
check "the -p argument is the pointer sentence" \
  "$(printf '%s' "$pointer" | sed -E 's/^Your complete instructions are in .+\. Read the whole file first and follow it\.$/pointer/')" "pointer"
check "the pointer names the prompt file" "$(same "$pointed" "$promptfile")" "same"
check "--add-dir names the prompt directory" "$(same "$(arg_after --add-dir)" "$taskdir/prompt")" "same"
check "the prompt directory holds no task record" "$([ -e "$taskdir/prompt/state.json" ] && echo yes || echo no)" "no"
check "the task record sits beside the prompt directory" "$([ -f "$taskdir/state.json" ] && echo yes || echo no)" "yes"
check "agy gets the report schema" "$(same "$(arg_after --json-schema)" "$P/scripts/agy-report-schema.json")" "same"
check "agy gets the model" "$(arg_after --model)" "claude-sonnet-5-5"
check "agy gets the effort" "$(arg_after --effort)" "medium"
check "agy gets the print timeout from agy-timeout" "$(arg_after --print-timeout)" "1200s"
check "agy asks for JSON output" "$(arg_after --output-format)" "json"
check "agy runs unattended" "$(has_arg --dangerously-skip-permissions)" "yes"
check "a fresh run passes no conversation" "$(has_arg --conversation)" "no"

newwork big
marker=BRIEFMARKER9
{ for _ in $(seq 1 2500); do printf '%s %s\n' "$marker" "a line of brief text that makes the file large padding padding padding"; done; } > "$fixture/big-brief.md"
run --brief "$fixture/big-brief.md"
check "a 200 KB brief still runs" "$?" "0"
check "a large brief still passes the same sentence" "$(arg_after -p | grep -c '^Your complete instructions are in .*\. Read the whole file first and follow it\.$')" "1"
check "no argument carries the brief" "$(grep -c "$marker" "$STUB_AGY_ARGS_LOG" || true)" "0"
bigtask="$(cd "$(dirname "$(state_of "$W")")" && pwd -P)"
check "the brief lands in the prompt file" "$(grep -c "$marker" "$bigtask/prompt/attempt-1.md")" "2500"

# --- a resume pins thread, model and effort (A9) -------------------------------
newwork resume
run
check "resume fixture: first run succeeds" "$?" "0"
STUB_AGY_WRITE=second.txt run --resume conv-1
check "a matching resume succeeds" "$?" "0"
check "a resume passes the thread as --conversation" "$(arg_after --conversation)" "conv-1"
check "a resume repeats the model" "$(arg_after --model)" "claude-sonnet-5-5"
check "a resume repeats the effort" "$(arg_after --effort)" "medium"
check "the resume commit holds its own file" "$(git -C "$W" show HEAD:second.txt 2>/dev/null)" "stub"
check "the second attempt writes a second prompt file" \
  "$([ -f "$(cd "$(dirname "$(state_of "$W")")" && pwd -P)/prompt/attempt-2.md" ] && echo yes || echo no)" "yes"
n=$(calls)
run --resume other-thread
check "a resume with another thread is refused" "$?" "2"
run --effort high --resume conv-1
check "a resume with another effort is refused" "$?" "2"
run --model claude-opus-5-5 --effort high --resume conv-1
check "a resume with another model is refused" "$?" "2"
check "a refused resume never reaches agy" "$(calls)" "$n"

# --- an incomplete run leaves pending work, and recovery hands it back ---------
newwork pending
STUB_AGY_MODE=blocked run
check "a BLOCKED verdict is not DONE" "$?" "1"
check "a BLOCKED verdict reports the status" "$(status_line | grep -c 'status=BLOCKED exit=0 ')" "1"
check "a BLOCKED verdict persists pending state" "$(jq -r .phase "$(state_of "$W")")" "pending"
check "a BLOCKED verdict commits nothing" "$(git -C "$W" log --format=%s | wc -l | tr -d ' ')" "1"
check "a BLOCKED report carries an agy error section" "$(grep -c '^## Agy error$' "$R")" "1"
STUB_AGY_MODE=no-schema run
check "a run with no structured output is not DONE" "$?" "1"
check "a run with no structured output reports BLOCKED" "$(status_line | grep -c 'status=BLOCKED ')" "1"
check "a failure with no error text says so" "$(grep -c '^agy returned no error text$' "$R")" "1"
bash "$SCRIPT" --cwd "$W" --task-id task-one --handback > "$fixture/out" 2> "$fixture/err"
check "handback transfers the stopped pending task" "$?" "0"
run
check "a handed-back task cannot resume" "$?" "2"
printf 'claude finished\n' > "$W/out.txt"
git -C "$W" add out.txt
git -C "$W" commit -qm 'feat(test): finish handed-back task'
bash "$SCRIPT" --cwd "$W" --task-id task-one --release > "$fixture/out" 2> "$fixture/err"
check "a finished handed-back task releases ownership" "$?" "0"
run --task-id task-two
check "a released worktree accepts a new task" "$?" "0"

# --- a failed commit is recovered without agy ---------------------------------
newwork recover
printf '#!/usr/bin/env bash\nexit 1\n' > "$fixture/primary/.git/hooks/pre-commit"
chmod +x "$fixture/primary/.git/hooks/pre-commit"
run
check "a commit hook failure exits two" "$?" "2"
check "a commit hook failure blocks the task" "$(jq -r .phase "$(state_of "$W")")" "blocked"
rm -f "$fixture/primary/.git/hooks/pre-commit"
n=$(calls)
bash "$SCRIPT" --cwd "$W" --task-id task-one --recover-commit > "$fixture/out" 2> "$fixture/err"
check "commit recovery succeeds" "$?" "0"
check "commit recovery never launches agy" "$(calls)" "$n"
check "the recovered commit holds the produced file" "$(git -C "$W" show HEAD:out.txt 2>/dev/null)" "stub"

# --- output outside the write set is never committed ---------------------------
newwork outside
STUB_AGY_MODE=outside-write STUB_AGY_OUTSIDE="$W/rogue.txt" run
check "an out-of-scope file blocks committing" "$?" "2"
check "an out-of-scope file is preserved" "$(cat "$W/rogue.txt" 2>/dev/null)" "stub"
check "an out-of-scope file is not committed" "$(git -C "$W" ls-tree --name-only HEAD rogue.txt)" ""
check "an out-of-scope file blocks the task record" "$(jq -r .phase "$(state_of "$W")")" "blocked"
printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
```

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 600 bash plugins/dforge/tests/run-agy-task.test.sh`
Expected: FAIL, ending `<n> passed, <m> failed` with `m` greater than 0 and exit status 1. `agy resolves to the stub` passes; `the wrapper exists` and the schema byte-identity check read `no`; every contract, validation, run, resume and recovery check fails because `bash` cannot open the missing script (exit 127) or the missing files. The run takes a few seconds and leaves no process behind.

- [ ] **Step 3: Implement**

1. **Schema.** Create `scripts/agy-report-schema.json` as a byte copy; this is a generated-file command, run from the repository root:

```bash
cp plugins/dforge/scripts/codex-report-schema.json plugins/dforge/scripts/agy-report-schema.json
```

2. **Contract text.** Create `scripts/agy-task-contract.md`, modelled on `codex-task-contract.md` (heading `## How to complete this task`, bold lead-ins, the bullet list of schema fields), with these changes. It tells the agent that the brief is its complete instruction set and that it works in the repository root. It replaces the Codex file's "You cannot use git" paragraph with a prohibition of every git command that writes, naming each as `git <word>` in the text: `git add`, `git commit`, `git stash`, `git reset`, `git checkout`, `git switch`, `git rebase`, `git branch`, `git tag`, `git update-ref` and `git worktree`; read-only commands (`git status`, `git diff`, `git log`) are allowed; the wrapper commits, and blocks the task when a ref, HEAD or the index has moved. It adds a paragraph that the agent is not sandboxed and must write only the approved files named in the brief, in this working tree or outside it. It keeps the test-first paragraph and the "do not guess at an ambiguous brief" paragraph (`NEEDS_CONTEXT` with questions). Its closing list names each of the six schema fields in backticks, one field per bullet (`status`, `summary`, `commit_subject`, `questions`, `discovered_issues`, `assumptions`), with the same meanings as the Codex file. Do not call the agent's sandbox read-only anywhere.

3. **The wrapper.** Create `scripts/run-agy-task.sh` (`#!/usr/bin/env bash`, `set -uo pipefail`; a header comment in the style of `run-codex-task.sh` saying it runs one plan task on agy and leaves a report in the implementer report format). Follow `run-codex-task.sh` section by section; keep each section's logic and comments that still apply, and make only these changes.
   1. *Setup.* `HERE` and `LADDER` as there; `SCHEMA` is `agy-report-schema.json`, `CONTRACT` is `agy-task-contract.md`, `GATE="${AGY_TASK_GATE:-$HERE/agy-gate}"` (tests point it at a stub gate), `GRACE="${AGY_TASK_GRACE:-60}"`. Source `lib/task-state.sh`, `lib/task-execution.sh`, `lib/executor-session.sh` and `lib/native-path.sh`. `VALID_EFFORTS="low medium high"`. `die` prints `run-agy-task: <message>` and exits 2. `block()` is unchanged.
   2. *Arguments and control operations.* The argument loop (including `--dry-run`, `--review-round`, the "missing value for" guard and the three flag-less and two value-taking control operations) and the `if [ -n "$operation" ]` block are copied unchanged.
   3. *Preflight validation*, in `run-codex-task.sh`'s order and with its messages where they apply: required flags, brief and cwd exist, schema and contract files exist (`die "contract not found: ..."`), `jq` and GNU `timeout` on PATH, `report` made absolute and its directory checked. The model must be column 2 of some `agy-assignment` row (`die "model is not a rung in agy-assignment: <m>"`); the effort one of `low medium high`, word-exact (`die "invalid reasoning effort: <e> (valid: low medium high)"`); the timeout defaults to the `agy-timeout` row keyed `<model>/<effort>` (`die "no agy-timeout row for <model>/<effort>"`) and must be whole seconds; `--review-round` needs a resume and a round 1 to 5.
   4. *Dry run.* After validation, `--dry-run` prints `would-run:` and the one JSON line described under Produces, then exits 0. It needs no gate, task id, `agy` or git repository.
   5. *Live-run gates.* `--task-id` is required (`die '--task-id is required'`). `agy` must be on PATH (`die "agy is required but not on PATH"`; this check is after the dry run, so validation tests do not need it). Read `$GATE` exactly as `run-codex-task.sh` reads its gate; a line without ` lane=true ` is `die "agy lane is off for this session (<reason>)"`, reason from the line, or `no gate answer`.
   6. *Opening the task* is copied unchanged: canonical cwd, report-path rules, `dr_task_open`, the phase and release checks, HEAD drift, the pending-snapshot check, the resume check that thread, model and effort equal the record (`die 'resume thread/model/effort does not match task record'`), the review-round check, the before snapshot and the attempt number. The first `dr_task_update` of the attempt records the same fields as the Codex wrapper, except `.artifacts`, which becomes `{report, prompt, result, last, stderr}`: `report` is `$DR_TASK_DIR/attempt-<n>.md`, `prompt` is `$DR_TASK_DIR/prompt/attempt-<n>.md`, `result` is `<report>.json` (agy's raw stdout), `last` is `<report>.last.json` (the verdict) and `stderr` is `<report>.stderr`.
   7. *Prompt file.* `mkdir -p "$DR_TASK_DIR/prompt"`, then write the prompt file: the brief, then for each of `CLAUDE.md` and `AGENTS.md` present in the cwd the section `## Repository conventions (<name>)` followed by the file, then a blank line and the contract text. Nothing but prompt files lives in that directory, because agy is given access to it; the task record stays in `$DR_TASK_DIR`.
   8. *Repository root and base* as in the Codex wrapper (`--show-prefix` empty, `base=$(git rev-parse HEAD)`). The interrupt trap and `cleanup` also stay as there (a run left in phase `running` is blocked on exit); Task 5 adds to them.
   9. *Clearing stale output.* Remove the previous `last`, `result` and `report` files and verify the clear, as the Codex wrapper does; persist `.phase = "running" | .processes = []`.
   10. *Invocation.* Build the pointer as the fixed sentence `Your complete instructions are in <dr_native_path of the prompt file>. Read the whole file first and follow it.` and run agy from the cwd with exactly these arguments, in this order: `--output-format json`, `--json-schema <dr_native_path of the schema>`, `--model <m>`, `--effort <e>`, `--dangerously-skip-permissions`, `--add-dir <dr_native_path of $DR_TASK_DIR/prompt>`, `--print-timeout <t>s`, then `--conversation <thread>` only when `--resume` was given, then `-p <pointer>`. Launch it as a background subshell: `cd` to the cwd, stdin from `/dev/null`, stdout to the `result` file, stderr to the `stderr` file, then `exec` `setsid` (only when `command -v setsid` succeeds) `timeout -k 10 $((t + GRACE))` `agy ...`. Keep the job's pid in `agy_pid` and `wait` on it, keeping the wait status as `agy_rc`. Job control is off in a script, so the job's pid is also its process group id once `setsid` has run; Task 5 relies on that.
   11. *Reading the result.* If the `result` file is not a JSON object, replace its content with `{}`. The verdict file is `.structured_output` when that is an object (written compactly to `last`; removed when absent). The thread is `.conversation_id` when non-empty: persist it with `dr_task_update '.thread = $thread'` and use it; otherwise keep `${thread:-<the record's thread or unknown>}` exactly as the Codex wrapper does. `agy_error` is `.error // ""`, `\r` stripped. `rc` is 1 when `agy_rc` is not 0 or `.status` is `ERROR`, else 0. Status, summary, subject, discovered issues and assumptions are parsed from the verdict file as the Codex wrapper does, and a non-zero `rc` forces `BLOCKED`.
   12. *Staging.* DONE runs `dr_task_stage "$before_snapshot" "$subject"` and dies `staging/commit failed; inspect durable task record and recover explicitly` on failure, then records whether HEAD moved (`committed=empty` when it did not). Any other status runs `dr_task_validate_scope` (blocking and dying `task scope drift` on failure) and persists the `pending` phase with a fresh snapshot. These two branches are the Codex wrapper's, without its writer-stopped branch (Task 5 adds one).
   13. *Report.* Same sections as the Codex wrapper, written to `$DR_TASK_DIR/attempt-<n>.md` and copied to the caller's `--report` path: `- executor: agy <model> / <effort>`, `- thread:`, `- status:`, `- exit:`, `- commits: <a7>..<b7>`, the empty-diff note, then `## Summary`, `## Discovered issues (not fixed)`, `## Assumptions made`, `## Questions` for `NEEDS_CONTEXT`, and for any status but DONE a `## Agy error` section whose fenced block holds `.error` (`\r` stripped) or, when that is empty, the sentence `agy returned no error text`, followed by the Codex wrapper's `## Working tree` section with the last 20 stderr lines.
   14. *Status line and exit code.* The last stdout line is `agy <model>/<effort> status=<s> exit=<rc> commits=<a7>..<b7> thread=<thread> report=<human report path>`; the script exits 0 only when the status is DONE.
   15. In the header comment, state why `AGY_TASK_GRACE` exists (the outer bound is the print timeout plus a margin, and tests shorten the margin).

- [ ] **Step 4: Run test to verify it passes**

Run: `timeout 600 bash plugins/dforge/tests/run-agy-task.test.sh`
Expected: PASS, ending `0 failed`.

Run: `timeout 600 bash plugins/dforge/tests/run-codex-task.test.sh && timeout 600 bash plugins/dforge/tests/executor-recovery.test.sh`
Expected: PASS, both `0 failed` (the Codex wrapper is untouched).

Run: `git diff --quiet -- plugins/dforge/scripts/run-codex-task.sh plugins/dforge/scripts/codex-report-schema.json plugins/dforge/scripts/codex-task-contract.md plugins/dforge/scripts/lib; echo $?`
Expected: `0`.

- [ ] **Step 5: Weight the suite and commit**

Every dforge shell suite needs a weight in `scripts/test-shards.mjs`. Time this suite and its neighbour in one session: `time timeout 600 bash plugins/dforge/tests/run-agy-task.test.sh` and `time timeout 600 bash plugins/dforge/tests/executor-recovery.test.sh`. Add `'run-agy-task.test.sh': <w>,` to `windowsSeconds`, between `'roots.test.sh'` and `'run-codex-task.test.sh'`, where `<w>` is executor-recovery's existing weight (295) multiplied by the ratio of the two measured wall times, rounded to the nearest multiple of 5, and at least 10.

Run: `timeout 300 node --test tests/test-shards.test.mjs`
Expected: PASS (it fails without the weight).

```bash
git add plugins/dforge/scripts/run-agy-task.sh plugins/dforge/scripts/agy-report-schema.json plugins/dforge/scripts/agy-task-contract.md plugins/dforge/tests/run-agy-task.test.sh scripts/test-shards.mjs
git commit -m "feat(dforge): add the agy task wrapper"
```

### Task 5: Classify agy failures and confirm the writer stopped

**Files:**
- Modify: `plugins/dforge/scripts/run-agy-task.sh`
- Modify: `scripts/test-shards.mjs` (re-measure the suite's weight)
- Test: `plugins/dforge/tests/run-agy-task.test.sh` (extended)

**Interfaces:**
- Consumes: Task 4's wrapper and suite helpers (`newwork`, `run`, `state_of`, `status_line`, `calls`, `check`, the stub on PATH); the stub modes `error`, `print-timeout`, `hang`, `git-commit`, `git-stash`, `git-branch` and `no-schema` (C3); `executor_session_mark_off` (unchanged library). The registry entry that makes `executor_session_mark_off agy` write a file is Task 6's, so this task asserts the report and the status line, and Task 6 asserts the session file.
- Produces: C10 (exit normalisation to 0/1/124, `reason=` and `timedOut=true` in `## Agy error`, `note=timed-out`, `note=writer-unconfirmed`, the quota mark-off call) and C11 (`$DR_TASK_DIR/refs-before.txt` and the post-run comparison that blocks the task with `agy changed git refs: <ref>`, or `agy changed the git index`). Task 7 reads `note=writer-unconfirmed`, and the controller tables read `reason=`, `timedOut=true` and `exit=124`.

**Implementer:** dforge:impl-opus-high
**Evaluation:** files 1 - spec 2 - coupling 1 - risk 2 = 6

- [ ] **Step 1: Write the failing test**

Append this section to `plugins/dforge/tests/run-agy-task.test.sh`, directly above the closing `printf '\n%d passed, %d failed\n' "$pass" "$fail"` line. It uses the suite's `newwork`, `run`, `state_of`, `status_line`, `calls`, `check`, `STUBDIR`, `SCRIPT`, `fixture`, `W` and `R`. The stub's `hang` mode needs `AGY_TASK_GRACE=1` so the outer bound is two seconds; the `sleepers` helper counts `sleep 300` processes by pid so a leak shows as a difference, and the section kills what it finds.

```bash
# --- a failed run says why, in the keys the controller reads ------------------
case "$(uname -s)" in MINGW*|MSYS*) windows=yes ;; *) windows=no ;; esac
skip() { printf 'skip - %s\n' "$1"; }

newwork classify
errcase() { # errcase <label> <mode> <error text> <reason> <exit>
  STUB_AGY_MODE="$2" STUB_AGY_ERROR="$3" run
  check "$1: the run is not DONE" "$?" "1"
  check "$1: the status line is BLOCKED with exit $5" \
    "$(status_line | sed -n 's/.* status=\([A-Z_]*\) exit=\([0-9]*\) .*/\1 \2/p')" "BLOCKED $5"
  check "$1: the report names reason $4" "$(grep -c "^reason=$4\$" "$R")" "1"
}
errcase "a plain error" error "something failed" error 1
check "a plain error carries the raw error text" "$(grep -c '^something failed$' "$R")" "1"
check "a plain error is not a timeout" "$(grep -c '^timedOut=true$' "$R")" "0"
check "a plain error has no timeout note" "$(status_line | grep -c 'note=')" "0"
check "a plain error leaves pending work" "$(jq -r .phase "$(state_of "$W")")" "pending"
errcase "an unrecognised failure with no text" no-schema "" error 0
errcase "an unknown model" error "unknown model gemini-9-flash" unknown-model 1
errcase "a withdrawn model" error "Model foo-1 not found" unknown-model 1
errcase "a quota error" error "Quota exceeded for this account" quota 1
errcase "a 429" error "HTTP 429 Too Many Requests" quota 1
errcase "a rate limit in any case" error "Rate-Limit reached" quota 1
errcase "a resource exhaustion" error "RESOURCE_EXHAUSTED: try later" quota 1
errcase "a print timeout" print-timeout "" timeout 124
check "a print timeout reports timedOut" "$(grep -c '^timedOut=true$' "$R")" "1"
check "a print timeout is flagged on the status line" "$(status_line | grep -c ' note=timed-out')" "1"
check "a print timeout is never DONE" "$(status_line | grep -c 'status=DONE')" "0"
check "a stopped print timeout leaves pending work" "$(jq -r .phase "$(state_of "$W")")" "pending"

# --- a clean run is confirmed stopped, a hung one is bounded ------------------
newwork clean
run
check "a clean run carries no note" "$(status_line | grep -c 'note=')" "0"

sleepers() { ps -eo pid=,args= 2>/dev/null | awk '$2 == "sleep" && $3 == "300" { print $1 }' | sort; }
newwork outer
before="$(sleepers)"
AGY_TASK_GRACE=1 STUB_AGY_MODE=hang run --timeout 1
check "an outer timeout is not DONE" "$?" "1"
check "an outer timeout reports exit 124" "$(status_line | grep -c 'status=BLOCKED exit=124 ')" "1"
check "an outer timeout is flagged timed-out" "$(status_line | grep -c ' note=timed-out')" "1"
check "an outer timeout reports reason timeout" "$(grep -c '^reason=timeout$' "$R")" "1"
check "an outer timeout reports timedOut" "$(grep -c '^timedOut=true$' "$R")" "1"
check "an outer timeout names its bound in the report" "$(grep -c '^- note: timed out after 1s$' "$R")" "1"
if [ "$windows" = no ]; then
  leaked="$(comm -13 <(printf '%s\n' "$before") <(sleepers))"
  check "an outer timeout leaves no process in the group" "$leaked" ""
  [ -z "$leaked" ] || kill -KILL $leaked 2>/dev/null
  check "a confirmed stop leaves pending work" "$(jq -r .phase "$(state_of "$W")")" "pending"
  check "a confirmed stop carries no unconfirmed note" "$(status_line | grep -c 'writer-unconfirmed')" "0"
else
  check "on Windows an outer kill is never confirmed" "$(status_line | grep -c ' note=writer-unconfirmed')" "1"
fi

# A process that ignores TERM outlives the run: nothing proves the writer stopped.
if [ "$windows" = no ]; then
  mkdir -p "$fixture/stubborn"
  cat > "$fixture/stubborn/agy" <<SHIM
#!/usr/bin/env bash
( trap '' TERM; exec sleep 25 ) &
printf '%s\n' "\$!" > "$fixture/stubborn.pid"
exec "$STUBDIR/agy" "\$@"
SHIM
  chmod +x "$fixture/stubborn/agy"
  newwork survivor
  PATH="$fixture/stubborn:$PATH" run
  check "a surviving process is not DONE" "$?" "1"
  check "a surviving process is flagged unconfirmed" "$(status_line | grep -c ' note=writer-unconfirmed')" "1"
  check "a surviving process is not reported as a timeout" "$(status_line | grep -c 'note=timed-out')" "0"
  check "a surviving process blocks the task" "$(jq -r .phase "$(state_of "$W")")" "blocked"
  check "a surviving process commits nothing" "$(git -C "$W" log --format=%s | grep -c 'feat(stub)')" "0"
  check "the report says the stop was not confirmed" \
    "$(grep -c '^- note: agy run not confirmed stopped; the task is blocked until it is$' "$R")" "1"
  run
  check "a blocked unconfirmed task cannot relaunch" "$?" "2"
  kill -KILL "$(cat "$fixture/stubborn.pid")" 2>/dev/null || true
else
  skip "a TERM-proof survivor needs POSIX process groups"
fi

# An interrupt stops the group it started and blocks the task.
if [ "$windows" = no ]; then
  newwork interrupted
  before="$(sleepers)"
  n=$(calls)
  STUB_AGY_MODE=hang bash "$SCRIPT" --cwd "$W" --task-id task-one --write-set "$fixture/scope.json" \
    --brief "$fixture/brief.md" --report "$R" --model claude-sonnet-5-5 --effort medium --timeout 120 \
    > "$fixture/out" 2> "$fixture/err" &
  wrapper=$!
  for _ in $(seq 1 50); do [ "$(calls)" -gt "$n" ] && break; sleep 0.2; done
  kill -TERM "$wrapper"
  wait "$wrapper"
  check "an interrupted run exits 143" "$?" "143"
  check "an interrupted run blocks the task" "$(jq -r .phase "$(state_of "$W")")" "blocked"
  leaked="$(comm -13 <(printf '%s\n' "$before") <(sleepers))"
  check "an interrupted run leaves no process in the group" "$leaked" ""
  [ -z "$leaked" ] || kill -KILL $leaked 2>/dev/null
else
  skip "an interrupt test needs POSIX signals"
fi

# --- agy may not move refs or the index (A7) ----------------------------------
guard_case() { # guard_case <name> <mode> <file agy writes> <ref the report names>
  newwork "$1"
  STUB_AGY_MODE="$2" STUB_AGY_WRITE="$3" run
  check "$1: the run is not DONE" "$?" "1"
  check "$1: the status line is BLOCKED exit 1" "$(status_line | grep -c 'status=BLOCKED exit=1 ')" "1"
  check "$1: the report names the moved ref" "$(grep -c "agy changed git refs: $4" "$R")" "1"
  check "$1: the task is blocked" "$(jq -r .phase "$(state_of "$W")")" "blocked"
  check "$1: nothing is committed under the reported subject" "$(git -C "$W" log --format=%s HEAD | grep -c 'feat(stub): add out')" "0"
}
guard_case guard-commit git-commit base.txt refs/heads/guard-commit
guard_case guard-stash git-stash base.txt refs/stash
guard_case guard-branch git-branch out.txt refs/heads/stub-branch

mkdir -p "$fixture/indexshim"
cat > "$fixture/indexshim/agy" <<SHIM
#!/usr/bin/env bash
"$STUBDIR/agy" "\$@"
rc=\$?
git add -- out.txt
exit \$rc
SHIM
chmod +x "$fixture/indexshim/agy"
newwork guard-index
PATH="$fixture/indexshim:$PATH" run
check "an index change is not DONE" "$?" "1"
check "an index change is named in the report" "$(grep -c 'agy changed the git index' "$R")" "1"
check "an index change blocks the task" "$(jq -r .phase "$(state_of "$W")")" "blocked"
check "an index change commits nothing" "$(git -C "$W" log --format=%s | grep -c 'feat(stub)')" "0"
check "an index change leaves the staged file in place" "$(git -C "$W" diff --cached --name-only | tr -d '\r')" "out.txt"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 600 bash plugins/dforge/tests/run-agy-task.test.sh`
Expected: FAIL. Task 4's checks still pass. In the new section these fail: every `names reason <r>` check and the `timedOut` checks (the report has no keys yet); the print-timeout and outer-timeout status lines (`exit=1`, not `exit=124`, and no `note=timed-out`); the three `guard-*` cases and the index case (the wrapper commits the changed state or dies without a report instead of blocking with the named ref); the survivor case (no `note=writer-unconfirmed`); and the interrupt case (the group is not stopped, so `sleep 300` processes remain until the section kills them). `a clean run carries no note` and `a plain error carries the raw error text` pass already.

- [ ] **Step 3: Implement**

All changes are in `scripts/run-agy-task.sh`; the numbers follow the order the code runs in.

1. *Git guard, before the run.* After `base` is known and before the phase becomes `running`, write `$DR_TASK_DIR/refs-before.txt` through one helper that item 7 reuses after the run: the output of `git -C "$cwd" for-each-ref --format='%(refname) %(objectname)'`, then one final line `HEAD <git rev-parse HEAD> <git symbolic-ref -q HEAD, or the word detached>`, with `\r` stripped. A failure to write it is `die 'cannot record git refs'`.
2. *Interrupt.* `cleanup` (the EXIT trap) first sends `kill -TERM -- "-$agy_pid"` to the recorded group when `agy_pid` is non-empty, ignoring errors, then does what it did. Clear `agy_pid` once the run has been confirmed over (item 4).
3. *Outer timeout.* After `wait`, `outer_fired` is yes when `agy_rc` is 124 or 137 (GNU `timeout` exits 137 when it had to send KILL).
4. *Writer stopped.* Replaces the unconditional `writer_stopped=yes`. On Windows (`uname -s` matching `MINGW*|MSYS*`), where `ps` does not list native processes: `writer_stopped=no` exactly when `outer_fired` is yes. Elsewhere: count the members of the process group `agy_pid` with `ps -eo pid=,pgid=,stat=`, excluding zombies (a `stat` starting `Z`; a zombie whose parent is gone is not a writer, and a container whose init does not reap would otherwise report one forever). When there are members, send `kill -TERM -- "-$agy_pid"`, re-count every half second up to six times, and set `writer_stopped=no` if any member is left. A run that ended by itself, or by `--print-timeout`, with an empty group is stopped, with no delay.
5. *Exit normalisation.* `finished_reason` is read from the result (`\r` stripped). `timed_out` is yes when `finished_reason` is `print_timeout` or `outer_fired` is yes. `rc` is 124 when `timed_out`; else 1 when `agy_rc` is not 0 or `.status` is `ERROR`; else 0. A non-zero `rc` forces the status to `BLOCKED`, as before.
6. *Reason.* From `agy_error`, matched case-insensitively with `grep -iE`, first match wins: `quota` for `quota|rate.?limit|RESOURCE_EXHAUSTED|429`; `unknown-model` for `unknown model|model .* not (found|available|supported|recognized)`; `timeout` when `timed_out` is yes; otherwise `error`. When the reason is `quota`, call `executor_session_mark_off agy quota`. The `## Agy error` fenced block now starts with `reason=<reason>`, then `timedOut=true` only when `timed_out` is yes, then the raw error text or the `agy returned no error text` sentence.
7. *Git guard, after the run.* After the writer-stopped scan and before any staging, write the same snapshot to `$DR_TASK_DIR/refs-after.txt` and compute `guard`. Compare the `refs/` lines of the two files, each sorted with `LC_ALL=C sort`, using `comm -3`; when they differ, `guard` is `agy changed git refs: <refname>` with the refname of the first differing line (strip the indentation `comm` adds, then take the first field; an added, removed or moved ref all differ). Otherwise, when the `HEAD` lines differ, `guard` is `agy changed git refs: HEAD`. Otherwise, when `git -C "$cwd" ls-files --stage -z | base64 | tr -d '\r\n'` differs from `.index` of the before snapshot (the expression `dr_snapshot` stores), `guard` is `agy changed the git index`. A non-empty `guard` forces the status to `BLOCKED`, raises `rc` to 1 when it was 0, and takes the first branch of the staging decision: `dr_task_block "$guard"` (dying `cannot persist blocked task` on failure), no staging, no scope check. Add `- note: <guard>; the task is blocked` to the report after the `- commits:` line.
8. *Unconfirmed writer.* `writer_stopped=no` forces `BLOCKED`, raises `rc` to 1 when it was 0, and takes the second branch (after the guard): `dr_task_block 'agy run not confirmed stopped; confirm it ended before recovery'`, no staging. Add `- note: agy run not confirmed stopped; the task is blocked until it is` to the report. The order of the staging branches is now: guard, unconfirmed writer, DONE (stage), anything else (scope check and `pending`).
9. *Timeout note.* When `timed_out`, add `- note: timed out after <timeout_s>s` to the report.
10. *Status line.* Append ` note=timed-out` when `timed_out` is yes, then ` note=writer-unconfirmed` when `writer_stopped` is no, in that order.

- [ ] **Step 4: Run test to verify it passes**

Run: `timeout 600 bash plugins/dforge/tests/run-agy-task.test.sh`
Expected: PASS, ending `0 failed`; on Windows the process-group cases print `skip` lines.

Run: `ps -eo pid=,args= | grep -E 'sleep (300|25)$' | grep -v grep; true`
Expected: no output (no process of the suite is left).

Run: `timeout 600 bash plugins/dforge/tests/run-codex-task.test.sh && timeout 600 bash plugins/dforge/tests/executor-recovery.test.sh`
Expected: PASS.

- [ ] **Step 5: Re-weigh the suite and commit**

The suite grew. Re-time it against `executor-recovery.test.sh` as Task 4 Step 5 did, and update the `'run-agy-task.test.sh'` weight in `scripts/test-shards.mjs` by the same rule.

Run: `timeout 300 node --test tests/test-shards.test.mjs`
Expected: PASS.

```bash
git add plugins/dforge/scripts/run-agy-task.sh plugins/dforge/tests/run-agy-task.test.sh scripts/test-shards.mjs
git commit -m "feat(dforge): classify agy failures"
```

### Task 6: Register agy and retire the antigravity row

**Files:**
- Create: `plugins/dforge/reference/executors/agy.json`
- Modify: `plugins/dforge/scripts/detect-executors.sh`
- Test: `plugins/dforge/tests/detect.test.sh`, `plugins/dforge/tests/executors.test.sh`, `plugins/dforge/tests/run-agy-task.test.sh` (extended), `plugins/dforge/tests/plan-revise.test.sh` (survey pinned)
- Unchanged by design: `plugins/dforge/tests/fixtures/executors/` (the fixture registry stays codex, opencode, stub)

**Interfaces:**
- Consumes: `scripts/executors ranked` and `"priority": 20` on `codex.json` (C1, Task 1); `scripts/agy-locate`, `scripts/lib/agy-probe.mjs`, `scripts/agy-gate`, `reference/agy-policy.json` and the stub `agy` (C3 to C7, Task 3); `scripts/run-agy-task.sh` (Tasks 4 and 5); the four ladder blocks of the entry (C2, Task 2).
- Produces: the registry entry of C13. From here on `executors get agy session_dir`, `session_dir_env` and `surfaces` resolve, so `executor_session_file agy`, `executor_session_mark_off agy quota` (Task 5) and `agy-gate` (Task 3) read and write a real session file; `executors list` prints `agy` then `codex`; `executors ranked` prints `agy` before `codex` (A2); `detect-executors.sh` reports an `agy` row and no `antigravity` row (A1); the survey cases of `plan-revise.test.sh` no longer read the shipped registry. Task 8 routes tasks by the order `ranked` prints, and Task 7 runs the wrapper through the registered entry.

**Implementer:** dforge:impl-opus-high
**Evaluation:** files 1 - spec 2 - coupling 2 - risk 2 = 7

Registering agy changes the output of existing suites. Run against a tree with the entry but without this task's edits, `detect.test.sh` reports five executors (`agy` and `antigravity` both) and `plan-revise.test.sh` counts a score-5 task as eligible in survey mode (`the survey does not count a unit above max_score` reads 1, because agy's gate admits totals up to 8). The edits below are made in the same task for that reason.

- [ ] **Step 1: Write the failing test**

Four edits to test files, (a) to (d). Edit (a) passes on the current tree already; (b), (c) and (d) fail on it.

**(a) `plugins/dforge/tests/plan-revise.test.sh`**: pin the survey to the fixture registry, because survey mode counts every registered executor. Replace the line `survey() { (cd "$SUR" && bash "$SCRIPT" --survey docs); }` with:

```bash
survey() { (cd "$SUR" && DR_EXECUTORS_DIR="$FIXREG" bash "$SCRIPT" --survey docs); }
```

(`FIXREG` is defined earlier in the file as `$HERE/fixtures/executors`.)

**(b) `plugins/dforge/tests/executors.test.sh`**: insert this section immediately after the check named `the shipped codex probe resolves to a real file` (the last check of the `# --- the shipped entry` section), before `# --- usage`.

```bash
# --- the shipped agy entry -----------------------------------------------------
check "the shipped registry lists agy before codex" \
  "$(bash "$EXEC" list | tr '\n' ' ')" "agy codex "
check "the shipped registry ranks agy before codex" \
  "$(bash "$EXEC" ranked | tr '\n' ' ')" "agy codex "
check "the shipped agy entry has priority 10" "$(bash "$EXEC" get agy priority)" "10"
check "the shipped agy entry names the real locator" \
  "$(bash "$EXEC" get agy locator)" "scripts/agy-locate"
check "the shipped agy entry names its gate" "$(bash "$EXEC" get agy gate)" "scripts/agy-gate"
check "the shipped agy entry names its wrapper" \
  "$(bash "$EXEC" get agy wrapper)" "scripts/run-agy-task.sh"
check "the shipped agy entry names its session directory" \
  "$(bash "$EXEC" get agy session_dir)" "agy-sessions"
check "the shipped agy entry names its session directory override" \
  "$(bash "$EXEC" get agy session_dir_env)" "DR_AGY_SESSION_DIR"
check "the shipped agy entry opens only the lane" \
  "$(bash "$EXEC" get agy surfaces | tr '\n' ',')" "lane,"
check "the shipped agy entry declares no missing reason" \
  "$(bash "$EXEC" get agy reasons.missing >/dev/null 2>&1; echo $?)" "1"
for key in locator probe.command gate wrapper; do
  check "the shipped agy $key resolves to a real file" \
    "$([ -f "$(bash "$EXEC" path agy "$key")" ] && echo yes || echo no)" "yes"
done
for key in gate assignment successor timeout; do
  block=$(bash "$EXEC" get agy "blocks.$key")
  check "the shipped agy $key block exists in the ladder" \
    "$(grep -cx "\`\`\`$block" "$P/reference/ladder.md")" "1"
done
```

**(c) `plugins/dforge/tests/detect.test.sh`**, five edits.

1. In the `for dep in jq timeout head tr node bash dirname cygpath sort grep; do` shim loop, extend the list with the commands `scripts/agy-locate` may run, so the sealed PATH does not hide them (a name that does not exist on the host is skipped by the loop's `command -v` test):

```bash
for dep in jq timeout head tr node bash dirname cygpath sort grep sed awk cat cut uname tail; do
```

2. After the line `export DR_CODEX_SESSION_DIR="$TMP/sessions" CLAUDE_CODE_SESSION_ID=detect-test` add the isolation for agy:

```bash
export HOME="$TMP/home" DR_AGY_SESSION_DIR="$TMP/agy-sessions"
mkdir -p "$HOME"
jq -nc '{cli:"agy", min_version:"1.4.12", max_major:1, calibrated:"1.4.12", trust:{smoke:"fail"}}' > "$TMP/agy-policy.json"
```

3. In `run()`, replace the final line `"$BASH_BIN" "$SCRIPT"; }` with the two lines below, so the stub's version and login state and the policy reach the locator and probe:

```bash
        DR_AGY_POLICY="$TMP/agy-policy.json" STUB_AGY_VERSION="${STUB_AGY_VERSION:-1.4.12}" \
        STUB_AGY_AUTH="${STUB_AGY_AUTH:-ok}" "$BASH_BIN" "$SCRIPT"; }
```

4. Replace the check `empty PATH: reports all four executors` (the `jq 'length'` one) with:

```bash
check "empty PATH: reports the four executors by id" \
  "$(jq -r '[.[].id] | sort | join(",")' <<<"$out")" "agy,codex,cursor-agent,opencode"
```

5. Replace the whole section from `# --- antigravity is present but never dispatchable` up to, not including, `# --- batch-capable tools with no lane` with:

```bash
# --- agy is a registered executor, and antigravity has no row ----------------
# The old antigravity row said its only agent mode opens a GUI session. agy is
# the headless Antigravity CLI, so a registered lane replaces that row instead
# of a PATH probe sitting beside it.
install_agy() { printf '#!%s\nexec "%s" "%s" "$@"\n' "$BASH_BIN" "$BASH_BIN" "$HERE/fixtures/stub-agy/agy" > "$TMP/bin/agy"; chmod +x "$TMP/bin/agy"; }
make_stub antigravity "Antigravity 1.107.0"
out=$(run)
check "an antigravity binary adds no row" "$(jq '[.[] | select(.id == "antigravity")] | length' <<<"$out")" "0"
rm -f "$TMP/bin/antigravity"

check "agy absent is not present" "$(field agy present "$out")" "false"
check "agy absent is not usable" "$(field agy usable "$out")" "false"
check "agy absent uses the entry's not_installed reason" \
  "$(field agy reason "$out")" "agy is not on PATH; install the Antigravity CLI"

install_agy
out=$(run)
check "agy present from its locator" "$(field agy present "$out")" "true"
check "agy version from its locator" "$(field agy version "$out")" "1.4.12"
check "agy is batch capable" "$(field agy batch_capable "$out")" "true"
check "agy yields exactly one row" "$(jq '[.[] | select(.id == "agy")] | length' <<<"$out")" "1"
check "the agy row's path is the directory holding agy" "$(field agy path "$out" | grep -c '/bin$')" "1"
out=$(STUB_AGY_VERSION=0.9.0 run)
check "an agy below the version floor is not usable" "$(field agy usable "$out")" "false"
check "an agy below the version floor names the version" "$(field agy reason "$out" | grep -c '0\.9\.0')" "1"

# The auth probe spawns agy from Node, which cannot run a bash-script stub on
# Windows.
SPAWNABLE=$(node -e 'const r = require("child_process").spawnSync(process.argv[1], ["--version"], { encoding: "utf8" }); console.log(r.status === 0 ? "yes" : "no")' "$TMP/bin/agy" 2>/dev/null | tr -d '\r')
if [ "$SPAWNABLE" = yes ]; then
  out=$(run)
  check "agy authed from its probe" "$(field agy authed "$out")" "true"
  check "agy is usable" "$(field agy usable "$out")" "true"
  check "a usable agy carries no reason" "$(field agy reason "$out")" "null"
  out=$(STUB_AGY_AUTH=logged-out run)
  check "a signed-out agy is explicit" "$(field agy auth_status "$out")" "logged_out"
  check "a signed-out agy is not usable" "$(field agy usable "$out")" "false"
  check "a signed-out agy uses the entry's remedy" "$(field agy reason "$out" | grep -c 'run agy and sign in')" "1"
  out=$(STUB_AGY_AUTH=broken run)
  check "an agy whose models call fails is a failed probe" "$(field agy auth_status "$out")" "probe_failed"
  check "a failed agy probe uses the entry's reason" "$(field agy reason "$out" | grep -c 'agy models')" "1"
else
  printf 'skip - the agy probe cases: Node cannot run the bash-script stub on this platform\n'
fi
rm -f "$TMP/bin/agy"
```

**(d) `plugins/dforge/tests/run-agy-task.test.sh`**: append this section directly above the closing `printf '\n%d passed, %d failed\n' "$pass" "$fail"` line. The first part needs only the registry entry (the wrapper's `executor_session_mark_off agy quota` has written nothing until now); the second runs the real `agy-gate` through a quota failure (A8).

```bash
# --- a quota closes the lane for the rest of the session (A8) ------------------
session_file="$DR_AGY_SESSION_DIR/run-agy-task-test.json"
session_state() { jq -r '[.usable, .lane, .reason] | map(tostring) | join("/")' "$session_file" 2>/dev/null | tr -d '\r'; }
rm -rf "$DR_AGY_SESSION_DIR"
newwork session-plain
STUB_AGY_MODE=error STUB_AGY_ERROR="something failed" run
check "a plain error leaves the session file absent" "$([ -e "$session_file" ] && echo yes || echo no)" "no"
newwork session-model
STUB_AGY_MODE=error STUB_AGY_ERROR="unknown model gemini-9-flash" run
check "an unknown model leaves the session file absent" "$([ -e "$session_file" ] && echo yes || echo no)" "no"
newwork session-quota
STUB_AGY_MODE=error STUB_AGY_ERROR="Quota exceeded for this account" run
check "a quota error turns agy off for the session" "$(session_state)" "false/false/quota"

# The same quota through the real gate: it keeps the answer past --refresh. Node
# cannot run a bash-script stub on Windows, and the gate's probe spawns agy.
SPAWNABLE=$(node -e 'const r = require("child_process").spawnSync(process.argv[1], ["--version"], { encoding: "utf8" }); console.log(r.status === 0 ? "yes" : "no")' "$STUBDIR/agy" 2>/dev/null | tr -d '\r')
if [ "$SPAWNABLE" = yes ]; then
  saved_gate="$AGY_TASK_GATE"
  unset AGY_TASK_GATE
  rm -rf "$DR_AGY_SESSION_DIR"
  gate_fields() { bash "$P/scripts/agy-gate" "$@" 2>/dev/null | tail -1 | tr -d '\r' \
    | sed -n 's/.* usable=\([a-z]*\) reason=\([^ ]*\) .* lane=\([a-z]*\) .*/\1 \2 \3/p'; }
  check "the real gate opens the lane on a trusted, signed-in stub" "$(gate_fields)" "true ok true"
  newwork quota
  STUB_AGY_MODE=error STUB_AGY_ERROR="quota exceeded" run
  check "a quota run through the real gate is not DONE" "$?" "1"
  check "the gate reports quota after the run" "$(gate_fields)" "false quota false"
  check "the gate keeps quota through --refresh" "$(gate_fields --refresh)" "false quota false"
  n=$(calls)
  run --task-id task-two
  check "the next wrapper call is refused" "$?" "2"
  check "the next wrapper call names quota" "$(grep -c 'agy lane is off for this session (quota)' "$fixture/err")" "1"
  check "the next wrapper call never runs agy" "$(calls)" "$n"
  export AGY_TASK_GATE="$saved_gate"
else
  skip "the real-gate quota chain needs a probe that can run the stub"
fi
```

`plugins/dforge/tests/plan-lint.test.sh` needs no edit: it passes unchanged with the entry registered.

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 600 bash plugins/dforge/tests/executors.test.sh`
Expected: FAIL on every check of the new `shipped agy entry` section except `the shipped agy entry declares no missing reason`, which passes vacuously until the entry exists (`list` prints `codex ` only; `ranked` prints `codex ` only; `get agy ...` exits 1 with no value).

Run: `timeout 600 bash plugins/dforge/tests/detect.test.sh`
Expected: FAIL on `empty PATH: reports the four executors by id` (the ids include `antigravity` and not `agy`), `an antigravity binary adds no row`, and every `agy` check (no `agy` row exists).

Run: `timeout 600 bash plugins/dforge/tests/run-agy-task.test.sh`
Expected: FAIL on `a quota error turns agy off for the session` (the session file is not written, so its state reads empty) and, where Node can run the stub, on the real-gate chain (`agy-gate` finds no `session_dir`, has no session file, and prints `lane=false`, so the first chain check reads `true ok false`). The other checks, `a plain error leaves the session file absent` and `an unknown model leaves the session file absent` included, pass.

Run: `timeout 600 bash plugins/dforge/tests/plan-revise.test.sh`
Expected: PASS (the pin changes nothing while only codex is registered).

- [ ] **Step 3: Implement**

1. **`plugins/dforge/reference/executors/agy.json`** (Contract C13, a configuration value; two-space indentation like `codex.json`; no trailing whitespace):

```json
{
  "id": "agy",
  "locator": "scripts/agy-locate",
  "probe": { "command": "scripts/lib/agy-probe.mjs", "op": "auth" },
  "gate": "scripts/agy-gate",
  "wrapper": "scripts/run-agy-task.sh",
  "reference": "reference/executor-lane.md",
  "session_dir": "agy-sessions",
  "session_dir_env": "DR_AGY_SESSION_DIR",
  "surfaces": ["lane"],
  "priority": 10,
  "blocks": {
    "gate": "agy-lane-gate",
    "assignment": "agy-assignment",
    "successor": "agy-successor",
    "timeout": "agy-timeout"
  },
  "reasons": {
    "not_installed": "agy is not on PATH; install the Antigravity CLI",
    "not_enabled": "agy is not usable on this machine",
    "logged_out": "agy is installed but not signed in; run agy and sign in",
    "probe_failed": "the agy auth probe failed; run agy models to see why"
  }
}
```

2. **`plugins/dforge/scripts/detect-executors.sh`**: delete the line `path_row antigravity false "installed, but its only agent mode ..."` (the stale row, whose GUI-only reason the 2026-09-22 survey found wrong), and delete the header-comment sentence `Antigravity fails that test on its interface, not on its installation.` so the comment no longer names a CLI the script does not special-case. Leave `emit`, its `batch_capable` parameter and the `cursor-agent` and `opencode` rows as they are. The `agy` row needs no code: it is registered, so `emit` reaches it through its locator, probe and `reasons` like `codex`.
3. Change nothing else. In particular `codex.json` and the fixture registry are Task 1's, and the ladder, gate and wrapper are earlier tasks'.

- [ ] **Step 4: Run test to verify it passes**

Run each with its own timeout:

```bash
timeout 600 bash plugins/dforge/tests/executors.test.sh
timeout 600 bash plugins/dforge/tests/detect.test.sh
timeout 600 bash plugins/dforge/tests/run-agy-task.test.sh
timeout 600 bash plugins/dforge/tests/plan-revise.test.sh
timeout 900 bash plugins/dforge/tests/plan-lint.test.sh
timeout 600 bash plugins/dforge/tests/review-route.test.sh
timeout 600 bash plugins/dforge/tests/executor-session.test.sh
timeout 600 bash plugins/dforge/tests/agy-gate.test.sh
timeout 600 bash plugins/dforge/tests/codex-gate.test.sh
timeout 300 node scripts/validate-repository.mjs
```

Expected: every suite ends `0 failed` and the validator exits 0; `detect.test.sh` and `agy-gate.test.sh` print `skip` lines on Windows only. The roster now reads `agy` first: `bash plugins/dforge/scripts/detect-executors.sh | jq -r '.[].id'` lists `agy`, `codex`, `cursor-agent`, `opencode` and no `antigravity`.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/reference/executors/agy.json plugins/dforge/scripts/detect-executors.sh plugins/dforge/tests/detect.test.sh plugins/dforge/tests/executors.test.sh plugins/dforge/tests/run-agy-task.test.sh plugins/dforge/tests/plan-revise.test.sh
git commit -m "feat(dforge): register agy as an executor"
```

### Task 7: Calibrate the Gemini rung and open the lane

**Files:**
- Create: `docs/dforge/notes/2026-11-02-agy-calibration.md`
- Modify: `plugins/dforge/reference/ladder.md` (the `agy-assignment` rows for totals 0-2; the `agy-successor` and `agy-timeout` rows of the 0-2 rung; any sentence that calls those rows provisional)
- Modify: `plugins/dforge/tests/lanes.test.sh` (a new section directly above the closing `printf '\n%d passed, %d failed\n'` line)
- Modify, after this task's review passes (Step 9): `plugins/dforge/reference/agy-policy.json`, `docs/superpowers/distilled/constraints.md`

**Interfaces:**
- Consumes: the C2 ladder blocks (Task 2); `scripts/agy-gate`, `scripts/agy-locate`, `reference/agy-policy.json` (C4, C5, C7; Task 3); `scripts/run-agy-task.sh` (C9, C10, C11; Tasks 4-5); the registry entry `reference/executors/agy.json` (C13; Task 6).
- Produces: the calibration record (C16); the final `agy-assignment` rows 0-2, the matching `agy-successor` and `agy-timeout` rows (C2, rewritten from the result); `trust.smoke: "pass"` (C5) and the auto-tick constraint (C16), both set in one separate commit after review.

**Implementer:** dforge:impl-opus-high
**Evaluation:** files 1 - spec 2 - coupling 2 - risk 1 = 6

This task spends Antigravity quota and dispatches Claude judges, and an implementer subagent cannot dispatch those judges itself: Step 4, item 7 has it report NEEDS_CONTEXT with the saved judge inputs, the controller dispatches `dforge:judge-sonnet-high` once per run, and the implementer is resumed with the verdicts. It runs on this Linux host only. Steps 1-8 are the implementer's; Step 9 is run by the controller after this task's Claude review has no open Critical or Important finding, because A12 orders the trust flip after that review and in its own commit.

- [ ] **Step 1: Write the failing test**

Append this section to `plugins/dforge/tests/lanes.test.sh`, directly above the closing `printf '\n%d passed, %d failed\n' "$pass" "$fail"` line. It uses the suite's own `block`, `check` and `HERE`.

```bash
# --- the agy calibration record and the lane's trust ---
# Rows 0-2 of agy-assignment, that rung's successor and timeout rows, and the
# trust flag all come from replayed runs, so the record of those runs is
# checked against what it decided.
NOTES="$HERE/../../../docs/dforge/notes/2026-11-02-agy-calibration.md"
POLICY="$HERE/../reference/agy-policy.json"
CONSTRAINTS="$HERE/../../../docs/superpowers/distilled/constraints.md"

check "the calibration record exists" "$([ -f "$NOTES" ] && echo yes || echo no)" "yes"
check "the record's table has the agreed header" \
  "$(grep -cxF '| Task replayed | Rung | Status | Tests | Scope | Judge | Wall s | Tokens |' "$NOTES" 2>/dev/null)" "1"

passes() { # passes <rung> - replayed tasks (R rows) that rung passed on every column
  awk -F'|' -v r="$1" '
    function t(s) { gsub(/^ +| +$/, "", s); return s }
    t($3) == r && t($2) ~ /^R[0-9]/ && t($4) == "DONE" && t($5) == "pass" && t($6) == "clean" && t($7) == "pass" { seen[t($2)] = 1 }
    END { n = 0; for (k in seen) n++; print n }
  ' "$NOTES" 2>/dev/null
}
decision=$(sed -n 's|^\*\*Decision:\*\* totals 0-2 run \([a-z0-9.-]*/[a-z]*\).*$|\1|p' "$NOTES" 2>/dev/null | head -n 1)
expected=claude-sonnet-5-5/low
for c in gemini-3.8-flash/low gemini-3.8-flash/medium gemini-4-argon/low; do
  if [ "$(passes "$c")" = 3 ]; then expected=$c; break; fi
done
check "the decision is the cheapest candidate that passed all three replays, else the Claude rung" \
  "${decision:-none}" "$expected"

tried=yes
for c in gemini-3.8-flash/low gemini-3.8-flash/medium gemini-4-argon/low; do
  [ "$c" != "$decision" ] || break
  [ "$(grep -cF -- "| $c |" "$NOTES" 2>/dev/null || true)" -ge 1 ] 2>/dev/null || tried=no
done
check "every candidate cheaper than the decision was run" "$tried" "yes"

band=$(block agy-assignment | awk '$1 + 0 <= 2 { print $2 "/" $3 }' | sort -u | tr '\n' ' ' | sed 's/ $//')
check "agy-assignment rows 0, 1 and 2 all name the decision" "$band" "${decision:-none}"
check "agy-assignment has exactly three rows at or below total 2" \
  "$(block agy-assignment | awk '$1 + 0 <= 2' | grep -c .)" "3"
check "the 0-2 rung's successor is claude-sonnet-5-5/medium" \
  "$(block agy-successor | awk -v k="$decision" '$1 == k { print $2 }')" "claude-sonnet-5-5/medium"
secs=$(block agy-timeout | awk -v k="$decision" '$1 == k { print $2 }')
check "the 0-2 rung has a timeout between 900 and 6900 seconds" \
  "$([ "${secs:-0}" -ge 900 ] && [ "${secs:-0}" -le 6900 ] && echo yes || echo no)" "yes"

reach=$( { block agy-assignment | awk '{ print $2 "/" $3 }'; block agy-successor | awk '$2 != "HANDBACK" { print $2 }'; } | sort -u)
stale=$( { block agy-successor | awk '{ print $1 }'; block agy-timeout | awk '{ print $1 }'; } \
  | sort -u | grep -vxF -f <(printf '%s\n' "$reach") | tr '\n' ' ' | sed 's/ $//')
check "no successor or timeout row names a rung that nothing reaches" "${stale:-NONE}" "NONE"

badnum=$(awk -F'|' '
  function t(s) { gsub(/^ +| +$/, "", s); return s }
  t($2) ~ /^[RS][0-9]/ && (t($8) !~ /^[0-9]+$/ || t($9) !~ /^[0-9]+$/) { n++ }
  END { print n + 0 }' "$NOTES" 2>/dev/null)
check "every run row carries numeric wall seconds and tokens" "${badnum:-x}" "0"

check "the record states a smoke result" \
  "$(grep -cE '^\*\*Smoke:\*\* (pass|fail)' "$NOTES" 2>/dev/null)" "1"
smoke_rung=$(block agy-assignment | awk '$1 == 5 { print $2 "/" $3 }')
check "the smoke run used the rung that total 5 is assigned" \
  "$(awk -F'|' -v r="$smoke_rung" '
    function t(s) { gsub(/^ +| +$/, "", s); return s }
    t($2) ~ /^S1/ && t($3) == r { n++ }
    END { print n + 0 }' "$NOTES" 2>/dev/null)" "1"

smoke=$(jq -r '.trust.smoke // "absent"' < "$POLICY" 2>/dev/null | tr -d '\r')
want=0
[ "$smoke" != pass ] || want=1
check "the auto-tick constraint exists exactly when trust.smoke is pass" \
  "$(grep -cxF '### The Antigravity executor lane is on' "$CONSTRAINTS")" "$want"
if [ "$smoke" = pass ]; then
  check "a smoke pass is recorded before the lane opens" \
    "$(grep -c '^\*\*Smoke:\*\* pass' "$NOTES" 2>/dev/null)" "1"
fi
```

The `AGY_MODELS` allowlist in `lanes.test.sh` already names every calibration candidate and `claude-sonnet-5-5`, so no decision needs it extended.

- [ ] **Step 2: Run the test to verify it fails**

Run: `timeout 120 bash plugins/dforge/tests/lanes.test.sh | grep -c '^FAIL'`
Expected: a non-zero count. The new rows fail because `docs/dforge/notes/2026-11-02-agy-calibration.md` does not exist and rows 0-2 still read `gemini-3.8-flash medium`; every earlier row still passes.

- [ ] **Step 3: Prepare a scratch plugin copy and a trusted gate**

Work from the plan's linked worktree. Every `agy` run in this task goes through `run-agy-task.sh` by hand, against a scratch copy of the plugin, with `DR_AGY_POLICY` exported to a trusted copy of the policy for all three gate reads (the planning read, the controller's dispatch read and the wrapper's own), and a private session directory so no cached answer from before the trust flag leaks in.

```bash
SCR=$(mktemp -d "${TMPDIR:-/tmp}/agy-calibration.XXXXXX")
REPO=$(git rev-parse --show-toplevel)
PRIMARY=$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")
cp -a "$REPO/plugins/dforge" "$SCR/plugin"
jq '.trust.smoke = "pass"' < "$REPO/plugins/dforge/reference/agy-policy.json" > "$SCR/agy-policy.json"
export DR_AGY_POLICY="$SCR/agy-policy.json" DR_AGY_SESSION_DIR="$SCR/sessions"
export CLAUDE_CODE_SESSION_ID="${CLAUDE_CODE_SESSION_ID:-agy-calibration}"
sed -i '/^```agy-assignment$/,/^```$/ s/^8 .*$/&\n9 gemini-4-argon low/' "$SCR/plugin/reference/ladder.md"
timeout 60 bash "$SCR/plugin/scripts/agy-locate"
timeout 90 bash "$SCR/plugin/scripts/agy-gate"
```

The `sed` adds a calibration-only row to the scratch ladder so the wrapper admits `gemini-4-argon`; the committed ladder is untouched. Expected: `agy-locate ok version=1.4.12 ...` and an `agy-gate` line ending `lane=true`. Anything else stops the task with BLOCKED, naming the line.

- [ ] **Step 4: Replay the three tasks, cheapest candidate first**

The replay set (each total 0-2, each with its own tests; all in this repository's completed plans):

| Key | Plan and task | Parent commit | Original commit | Task's own tests (run on the result) |
|---|---|---|---|---|
| R1 impl-clauses | `docs/dforge/plans/2026-10-28-speed-and-cost.md` Task 3, total 2 | `2c3add12` | `236975e3` | `timeout 120 bash plugins/dforge/tests/impl-clauses.test.sh` ends `81 passed, 0 failed`; `timeout 120 bash plugins/dforge/tests/fleet.test.sh` ends `0 failed` |
| R2 ui-lint | `docs/dforge/plans/2026-10-24-ui-ux-skill.md` Task 4, total 1 | `f706fdbc` | `b977b6c6` | `timeout 120 bash plugins/dforge/tests/ui-lint.test.sh` ends `0 failed` |
| R3 ui-ux-proof | `docs/dforge/plans/2026-10-24-ui-ux-skill.md` Task 5, total 0 | `b977b6c6` | `d80f69c0` | `timeout 120 bash plugins/dforge/tests/criteria.test.sh` ends `0 failed` |

The candidates, cheapest first: `gemini-3.8-flash/low`, `gemini-3.8-flash/medium`, `gemini-4-argon/low`. Run one candidate over R1, R2, R3 in that order and stop that candidate at its first failed run (no row for the tasks it did not reach); then start the next candidate. Stop the whole step at the first candidate that passes all three: it is the decision. Per-candidate slugs are `flash-low`, `flash-medium`, `argon-low`. Each Gemini run passes `--timeout 900`, since `gemini-3.8-flash/low` and `gemini-4-argon/low` have no `agy-timeout` row.

For one run, with `K` the key (`R1`), `RUN=$K-$slug`, `PLAN`/`N`/`PARENT`/`ORIG` from the table, `M`/`E` the candidate's model and effort:

1. Worktree, brief and write set:
   ```bash
   git worktree add -q -b "calib/$RUN" "$SCR/wt-$RUN" "$PARENT"
   timeout 60 bash "$SCR/plugin/scripts/task-brief" "$SCR/wt-$RUN/$PLAN" "$N" "$SCR/brief-$RUN.md"
   git diff-tree --no-commit-id --name-only -r "$ORIG" | jq -R -s 'split("\n") | map(select(length > 0))' > "$SCR/writeset-$K.json"
   git -C "$SCR/wt-$RUN" status --porcelain
   ```
   The last command must print nothing (the wrapper refuses a dirty worktree).
2. Fingerprint what an unsandboxed `agy` could touch, before the run:
   ```bash
   for d in "$REPO" "$PRIMARY"; do git -C "$d" status --porcelain; done > "$SCR/status-before-$RUN.txt"
   git for-each-ref --format='%(refname) %(objectname)' | grep -v '^refs/heads/calib/' > "$SCR/refs-before-$RUN.txt"
   ```
3. Run the wrapper as a background Bash call whose `timeout` is (900 + 120) × 1000 ms (the bound for the smoke run in Step 6 is read from `agy-timeout`), and wait for its completion notification:
   ```bash
   t0=$(date +%s)
   bash "$SCR/plugin/scripts/run-agy-task.sh" --brief "$SCR/brief-$RUN.md" --report "$SCR/report-$RUN.md" \
     --cwd "$SCR/wt-$RUN" --task-id "calib-$RUN" --write-set "$SCR/writeset-$K.json" \
     --model "$M" --effort "$E" --timeout 900 > "$SCR/out-$RUN.txt" 2> "$SCR/err-$RUN.txt"
   rc=$?; t1=$(date +%s); wall=$((t1 - t0)); tail -n 1 "$SCR/out-$RUN.txt"
   timeout 90 bash "$SCR/plugin/scripts/agy-gate" --refresh
   ```
   Status is the `status=` field of that last line (`DONE`, `BLOCKED`, `NEEDS_CONTEXT`). An exit 2 printed no status line and is not a model failure: read `err-$RUN.txt` and the task record's `phase`; a preflight refusal (bad flag, dirty tree, closed gate) is fixed and re-run without a row, a later phase is recorded as Status `blocked` and the run fails. A refreshed gate line saying `reason=quota` stops the whole task with BLOCKED, naming the runs that did not happen: the lane cannot be calibrated this session.
4. Tokens: `agy` returns `usage.total_tokens` in its result object, which the wrapper keeps as the attempt's `result` artifact (`<attempt report>.json`) in the task directory, `<worktree git dir>/dforge/tasks/<hash of the task id>/`. Read its path from the task record:
   ```bash
   tdir="$(git -C "$SCR/wt-$RUN" rev-parse --absolute-git-dir)/dforge/tasks/$(printf '%s' "calib-$RUN" | git -C "$SCR/wt-$RUN" hash-object --stdin)"
   result=$(jq -r '.artifacts.result // empty' < "$tdir/state.json" 2>/dev/null)
   tokens=$(jq -r '.usage.total_tokens // empty' < "$result" 2>/dev/null | head -n 1)
   [ -n "$tokens" ] || tokens=n/a
   ```
   When `tokens` is still `n/a` for a run that executed, report NEEDS_CONTEXT: the wrapper must keep the result object.
5. Scope. After the run, all four must be empty: the changed files outside the write set (`git -C "$SCR/wt-$RUN" diff --name-only "$PARENT" HEAD | sort | comm -23 - <(jq -r '.[]' < "$SCR/writeset-$K.json" | sort)`), a difference in `status-before-$RUN.txt` (re-run the loop of item 2 into `status-after-$RUN.txt` and `diff` them), a difference in the refs (`git for-each-ref --format='%(refname) %(objectname)' | grep -v '^refs/heads/calib/' | diff "$SCR/refs-before-$RUN.txt" -`), and a wrapper note `writer-unconfirmed`. Scope is `clean` when all are empty, otherwise `violated` with the first difference named in the note under the table.
6. Tests, only when Status is `DONE`. Verify the result in a throwaway worktree with the original commit's test files restored over it, so a result that weakened its own tests still fails:
   ```bash
   git worktree add -q --detach "$SCR/verify-$RUN" "$(git -C "$SCR/wt-$RUN" rev-parse HEAD)"
   jq -r '.[] | select(startswith("plugins/dforge/tests/"))' < "$SCR/writeset-$K.json" | xargs -r git -C "$SCR/verify-$RUN" checkout "$ORIG" --
   ```
   Then run the table's test commands inside `$SCR/verify-$RUN`. Tests are `pass` when every command exits 0 with the stated last line.
7. Judge, only when Status is `DONE`, Tests `pass` and Scope `clean`. Write the diff (`git -C "$SCR/wt-$RUN" diff "$PARENT" HEAD > "$SCR/diff-$RUN.diff"`) and a copy of the report without the lines that name the author (`sed -e '/^- executor:/d' -e '/^## Agy error/,$d' "$SCR/report-$RUN.md" > "$SCR/report-$RUN-blind.md"`). Copy the brief, the blind report and the diff into `$SCR/judge/$RUN/` as `brief.md`, `report.md` and `diff.diff`. When you can dispatch agents, dispatch `dforge:judge-sonnet-high` yourself with `skills/subagent-driven-development/references/task-reviewer-prompt.md` and those three files, saying nothing about `agy`, Gemini or Antigravity, and have it write `$SCR/judge/$RUN/verdict.md`. An implementer subagent cannot dispatch: it finishes every other run of the current candidate first, then reports `NEEDS_CONTEXT — judge verdicts needed: <each $SCR/judge/<RUN> directory>; scratch root $SCR`. The controller dispatches that judge once per listed directory with the same template and the same silence about the author, each writing `verdict.md` there, then resumes the implementer with the list of written verdicts. The run passes the judge when its `verdict.md` reads `spec: pass` and `quality: approved`. `$SCR` lives outside the worktree and survives the hand-off; never delete it before Step 8.
8. Row. Append `| <K> <name> | <M>/<E> | <Status> | <pass|fail|n/a> | <clean|violated> | <pass|fail|n/a> | <wall> | <tokens> |` to `$SCR/rows.md`. A run passes only when Status is `DONE` and Tests, Scope and Judge are `pass`, `clean`, `pass`.

- [ ] **Step 5: Decide the 0-2 rung and rewrite the ladder rows**

The decision is the first candidate, in the Step 4 order, whose three runs all passed; when none did, it is `claude-sonnet-5-5/low`, the native rung, and the lane's Gemini use ends here. Edit `plugins/dforge/reference/ladder.md`:

1. `agy-assignment`: rows `0`, `1` and `2` name the decision's model and effort (for example `0 gemini-3.8-flash low`); rows 3-8 stay as they are.
2. `agy-successor`: the row whose source is the 0-2 rung reads `<decision> claude-sonnet-5-5/medium`. Delete the provisional `gemini-3.8-flash/medium` row when the decision is a different rung, and add the row when it is missing. Every other row stays.
3. `agy-timeout`: the row for the decision reads `<decision> <seconds>`, where seconds is the larger of 900 and three times the slowest passing run's wall seconds of that rung, rounded up to a multiple of 300 and capped at 6900; the Claude fallback, never measured, takes 900. Delete the provisional `gemini-3.8-flash/medium` row when the decision is a different rung.
4. If `ladder.md` carries a sentence that calls rows 0-2 provisional (`rg -n -i provisional plugins/dforge/reference/ladder.md`), replace it with one sentence naming `docs/dforge/notes/2026-11-02-agy-calibration.md` as the source of those rows.

- [ ] **Step 6: Smoke one real task at its Claude rung**

Replay one more task, scored 3-5, through the same item 1-8 procedure with these differences. It is `S1 plan-lint-header-lines`: `docs/dforge/plans/2026-10-31-test-tiers-and-ci-parity.md` Task 3 (total 5), parent `d4a8af8a`, original commit `d814996b`, write set `plugins/dforge/scripts/plan-lint` and `plugins/dforge/tests/plan-lint.test.sh`, tests `timeout 900 bash plugins/dforge/tests/plan-lint.test.sh` ending `0 failed`. Its model and effort are the `agy-assignment` row for total 5 (`awk '$1 == 5 { print $2, $3 }'` over the `agy-assignment` block of the committed ladder), run with no `--timeout` flag so the wrapper reads `agy-timeout`; the background call's `timeout` is that bound + 120 seconds, in milliseconds. This is the riskiest assumption: a brief of tens of kilobytes with a TDD contract must reach a valid verdict inside the write set.

The smoke passes under the same rule as a calibration run (DONE, tests, scope, judge). If it fails, record the row and `**Smoke:** fail - <reason>`, commit per Step 8 with the lane left closed, and report BLOCKED: nothing downstream may build on the lane.

- [ ] **Step 7: Write the calibration record**

Create `docs/dforge/notes/2026-11-02-agy-calibration.md`: a title, two sentences on what was replayed and why (the three tasks and their original commits, the candidate order, the pass rule), the table, the results of Steps 5-6, and a `Left in place` list. The table is the header below, its separator row, then the rows of `$SCR/rows.md` in the order run, then the `S1` row:

```markdown
| Task replayed | Rung | Status | Tests | Scope | Judge | Wall s | Tokens |
|---|---|---|---|---|---|---|---|
```

After the table, exactly these two lines (the suite parses them):

```markdown
**Decision:** totals 0-2 run <model>/<effort> - <one sentence: the cheapest candidate that passed all three, or why none did>
**Smoke:** pass
```

`**Smoke:** fail - <reason>` replaces the second line when Step 6 failed. A violated Scope, a failed run or a judge finding is explained in one line each under the table. `Left in place` names every scratch worktree whose task did not reach `complete` (a blocked task's worktree is never removed); say `none` when there are none.

- [ ] **Step 8: Run the tests, clean up and commit**

Run: `timeout 120 bash plugins/dforge/tests/lanes.test.sh | tail -n 3` — expected `0 failed`. Run `timeout 120 bash plugins/dforge/tests/ladder.test.sh | tail -n 1` — expected `0 failed`.

Clean up what this task started. For each run whose task reached `complete`: release it (`bash "$SCR/plugin/scripts/run-agy-task.sh" --cwd "$SCR/wt-$RUN" --task-id "calib-$RUN" --release`), then `git worktree remove "$SCR/wt-$RUN"`, `git worktree remove --force "$SCR/verify-$RUN"` and `git branch -D "calib/$RUN"`. Leave every worktree that is blocked or unreleased where it is. Then `pgrep -x agy` must print nothing and `git -C "$REPO" status --porcelain` must list only this task's three files; remove `$SCR` only when no worktree is left in it.

```bash
git add docs/dforge/notes/2026-11-02-agy-calibration.md plugins/dforge/reference/ladder.md plugins/dforge/tests/lanes.test.sh
git commit -m "feat(dforge): set the agy rung for totals 0-2"
```

Report DONE with the decision and the smoke result in one line. Do not touch `agy-policy.json` or `constraints.md`.

- [ ] **Step 9: Open the lane (controller, after review)**

Run only when `**Smoke:** pass` is on the record and this task's Claude review has no open Critical or Important finding. Two edits, one commit:

1. `plugins/dforge/reference/agy-policy.json`: change `"smoke": "fail"` to `"smoke": "pass"` and nothing else. Then `rg -n 'smoke' plugins/dforge/tests` and update any test that pins the shipped file's `fail` value.
2. `docs/superpowers/distilled/constraints.md`: under `## Execution lanes`, directly after the entry `### The Codex executor lane is on` and before `### Codex reviews run only on demand`, add:

```markdown
### The Antigravity executor lane is on
When `scripts/agy-gate` reports `lane=true`, the planner ticks `agy` without asking and lists it before `codex` on the External executors line.
Set by: owner, 2026-11-02 spec review ("Auto-tick (Recommended)")
Scope: every plan written for this repository on a Claude host
Source: docs/dforge/specs/2026-11-02-antigravity-executor-lane-design.md
```

Run `timeout 120 bash plugins/dforge/tests/lanes.test.sh | tail -n 1` (expected `0 failed`), then `bash plugins/dforge/scripts/agy-gate --refresh` once without `DR_AGY_POLICY` so this session's cached answer reflects the shipped policy.

```bash
git add plugins/dforge/reference/agy-policy.json docs/superpowers/distilled/constraints.md
git commit -m "feat(dforge): open the agy lane"
```

**Check:** `timeout 120 bash plugins/dforge/tests/lanes.test.sh | tail -n 1` and `timeout 120 bash plugins/dforge/tests/ladder.test.sh | tail -n 1` both end `0 failed`; `git show --stat HEAD` lists exactly `agy-policy.json` and `constraints.md`; `git log --oneline -3` shows the open-the-lane commit after the rung commit.

### Task 8: Route each task to the first admitting executor

Make Contract C14 true in two parts. Part A teaches `plan-lint` and `plan-revise` to rank executors by priority, so a task's `**Executor:**` line must name the first ticked executor whose gate admits it. Part B states that rule in the planning prose (`executor-lane.md`, the assignment procedure and the revising-plans skill) and pins the wording.

#### Part A: Route by priority in plan-lint and plan-revise

**Files:**
- Modify: `plugins/dforge/scripts/plan-lint` (the `lane_gates` loop, the Executor-line branch, the lane-eligible warning)
- Modify: `plugins/dforge/scripts/plan-revise` (the ticked-executor loop and the header comment)
- Test: `plugins/dforge/tests/plan-lint.test.sh`, `plugins/dforge/tests/plan-revise.test.sh`

**Interfaces:**
- Consumes: `executors ranked` (C1; Task 1); the `agy-lane-gate`, `agy-assignment` blocks and the registry entry (C2, C13; Tasks 2 and 6), whose rows 0-2 are final after Task 7.
- Produces: the script half of the routing rule C14: `plan-lint` ERROR `Executor names <eid> but <first> ranks first and admits total <t>`; the WARN `lane-eligible with no **Executor:** line (<first> <rung>)` naming one executor per task; `plan-revise` printing `rungs=` in ranked order, for headers listing ticked ids in ranked order such as `> **External executors:** agy, codex`. Part B documents the same rule.

**Implementer:** dforge:impl-opus-high
**Evaluation:** files 1 - spec 2 - coupling 2 - risk 2 = 7

- [ ] **Step 1: Write the failing tests**

**1a. `plugins/dforge/tests/plan-lint.test.sh`, with the real registry and ladder (agy priority 10, codex 20).** Add this section directly before the line `# --- Executor lines are validated against their own executor ---...` (the one that exports `DR_EXECUTORS_DIR`), so `DR_EXECUTORS_DIR` and `DR_LADDER` are still unset here.

```bash
# --- priority routing: agy ranks before codex ---
export DR_AGY_SESSION_DIR="$TMP/agy-sessions"
agy_rung() { # agy_rung <total> - "<model> / <effort>" from the shipped agy-assignment block
  tr -d '\r' < "$HERE/../reference/ladder.md" \
    | awk -v t="$1" '$0 == "```agy-assignment" { f = 1; next } f && /^```/ { exit } f && $1 == t { print $2 " / " $3 }'
}
esc() { printf '%s' "${1//\//\\/}"; }
R2=$(agy_rung 2); R4=$(agy_rung 4); R5=$(agy_rung 5)
T2='s/files 0 - spec 0 - coupling 1 - risk 0 = 1/files 0 - spec 1 - coupling 1 - risk 0 = 2/'
EV2='s/^(\*\*Evaluation:\*\* files 0 - spec 1 - coupling 1 - risk 0 = 2)$/\1\n**Executor:** '
TICK() { printf 's/^(\\*\\*Program:\\*\\* .*)$/\\1\\n\\n> **External executors:** %s/' "$1"; }

variant r1.md "$T2; ${EV2}agy $(esc "$R2")/; $(TICK 'agy, codex')"
lint r1.md
lacks "agy named while both are ticked: the line is accepted" "$out" "ERROR Task 1"
variant r2.md "$T2; ${EV2}codex gpt-6.1-sol \/ low/; $(TICK 'agy, codex')"
lint r2.md
has "codex named while agy ranks first and admits the task" "$out" \
  "ERROR Task 1: Executor names codex but agy ranks first and admits total 2"
variant r3.md "$T2; ${EV2}codex gpt-6.1-sol \/ low/; $(TICK 'codex, agy')"
lint r3.md
has "rank decides, not the order of the header line" "$out" \
  "ERROR Task 1: Executor names codex but agy ranks first and admits total 2"
variant r4.md "$T2; ${EV2}codex gpt-6.1-sol \/ low/; $(TICK 'codex')"
lint r4.md
lacks "agy unticked: a codex line is unchanged" "$out" "ERROR Task 1"
lacks "agy unticked: no ranking finding" "$out" "ranks first"

variant r5.md "s/files 0 - spec 1 - coupling 1 - risk 2 = 4/files 0 - spec 1 - coupling 1 - risk 3 = 5/; s/impl-sonnet-medium\$/impl-sonnet-high/; s/^(\*\*Evaluation:\*\* files 0 - spec 1 - coupling 1 - risk 3 = 5)\$/\1\n**Executor:** agy $(esc "$R5")/; $(TICK 'agy, codex')"
lint r5.md
has "a risk-3 task never takes an agy line" "$out" \
  "ERROR Task 2: total 5 / risk 3 fails the lane gate (min_score 0, max_score 8, max_risk 2)"
variant r6.md "s/^(\*\*Approach:\*\* .*)\$/\1\n**Override:** kept\n**Executor:** agy $(esc "$R4")/; $(TICK 'agy')"
lint r6.md
has "a human override never takes an agy line" "$out" \
  "ERROR Task 2: an Executor line on an overridden task fails the lane gate"

OLD_ROSTER="${PLAN_LINT_ROSTER:-}"
lane_surface true
variant w1.md "$T2"
mkdir -p "$DR_AGY_SESSION_DIR"
printf '{"session_id":"plan-lint-test","usable":true,"review":false,"lane":true}\n' \
  > "$DR_AGY_SESSION_DIR/plan-lint-test.json"
cat > both.sh <<EOF
printf 'called\n' >> "$TMP/probe-calls"
echo '[{"id":"agy","usable":true,"reason":null},{"id":"codex","usable":true,"reason":null}]'
EOF
export PLAN_LINT_ROSTER="$TMP/both.sh"
rm -f probe-calls; lint w1.md
has "both usable: the warning names the first admitting executor" "$out" \
  "WARN Task 1: lane-eligible with no **Executor:** line (agy $R2)"
lacks "both usable: the second admitting executor is not named" "$out" \
  "lane-eligible with no **Executor:** line (codex"
has "agy alone admits a risk-2 task" "$out" \
  "WARN Task 2: lane-eligible with no **Executor:** line (agy $R4)"
check "both usable: the roster still runs once" "$(calls)" "1"
rm -f "$DR_AGY_SESSION_DIR/plan-lint-test.json"
rm -f probe-calls; lint w1.md
has "agy off: codex is named as before" "$out" \
  "WARN Task 1: lane-eligible with no **Executor:** line (codex gpt-6.1-sol / low)"
lacks "agy off: a risk-2 task is not named" "$out" "WARN Task 2: lane-eligible"
export PLAN_LINT_ROSTER="$OLD_ROSTER"
unset DR_AGY_SESSION_DIR
```

**1b. The same file, inside the fixture section,** directly after the line `has "the header must name the line's executor" ...`. Priority, not name order, decides: the fixture `stub` (10) sorts after `codex` (20) by name.

```bash
# --- ranking is by priority, not by name ---
RANKED="$TMP/ranked-reg"; mkdir -p "$RANKED"
jq '. + {priority: 20}' < "$HERE/fixtures/executors/codex.json" > "$RANKED/codex.json"
jq '. + {priority: 10}' < "$HERE/fixtures/executors/stub.json" > "$RANKED/stub.json"
export DR_EXECUTORS_DIR="$RANKED"
variant k1.md "$T2; ${EV2}codex gpt-6.1-sol \/ low/; $(TICK 'codex, stub')"
lint k1.md
has "a lower priority number outranks a lower name" "$out" \
  "ERROR Task 1: Executor names codex but stub ranks first and admits total 2"
variant k2.md "$T2; ${EV2}stub stub-model \/ medium/; $(TICK 'codex, stub')"
lint k2.md
lacks "the executor that ranks first may be named" "$out" "ranks first"
export DR_EXECUTORS_DIR="$HERE/fixtures/executors"
```

**1c. `plugins/dforge/tests/plan-revise.test.sh`.** Add this directly after the row `check "a ticked executor is reported" ...`:

```bash
agyrung() { # agyrung <total> - "<model>/<effort>" from the shipped agy-assignment block
  tr -d '\r' < "$HERE/../reference/ladder.md" \
    | awk -v t="$1" '$0 == "```agy-assignment" { f = 1; next } f && /^```/ { exit } f && $1 == t { print $2 "/" $3 }'
}
both() { hdr '
> **External executors:** codex, agy
' "$1"; }

plan "$(mktask 1 0 1 0 2)"
check "codex alone ticked: rungs are unchanged" "$(field rungs "$(unit1)")" "codex:gpt-6.1-sol/low"
both "$(mktask 1 0 1 0 2)"
check "both ticked: rungs follow priority, not the header order" \
  "$(field rungs "$(unit1)")" "agy:$(agyrung 2),codex:gpt-6.1-sol/low"
check "both ticked: the unit passes the gate" "$(field gate "$(unit1)")" "pass"
both "$(mktask 0 0 1 0 1)"
check "both ticked: a total-1 unit is admitted by agy alone" "$(field rungs "$(unit1)")" "agy:$(agyrung 1)"
both "$(mktask 1 1 1 3 6)"
check "both ticked: a risk-3 unit is admitted by neither" "$(field gate "$(unit1)")" "fail:risk"
check "both ticked: a risk-3 unit has no rung" "$(field rungs "$(unit1)")" ""
```

The survey helper is already pinned to the fixture registry by Task 6, so nothing about it changes here.

- [ ] **Step 2: Run the tests to verify they fail**

Run, each bounded:
`timeout 900 bash plugins/dforge/tests/plan-lint.test.sh | grep -E '^FAIL|passed,'`
`timeout 600 bash plugins/dforge/tests/plan-revise.test.sh | grep -E '^FAIL|passed,'`
Expected: FAIL rows for the two ranking ERRORs, the single-executor WARN and the `rungs=` order; the codex-only rows (`r4`, `agy unticked`, `codex alone ticked`) already pass.

- [ ] **Step 3: Implement the routing**

1. `plan-lint`, the `lane_gates` loop (`done < <(bash "$HERE/executors" list ...)`): read `executors ranked` instead of `executors list`, so the rows of `lane_gates` and `lane` are in priority order. Nothing else about the loop changes.
2. `plan-lint`, the Executor-line branch (after `eid` is known to be registered and its gate readable): build the ticked ids from the header's `> **External executors:**` line (strip the label, split on commas and spaces, compare words, not substrings). Walk `lane_gates` in order. Stop with no finding when the walk reaches the row for `eid` itself. Before that, the first row that is ticked, whose gate admits this task (total within `min_score`..`max_score`, risk at most `max_risk`) and for which Rule S is clean (`a + b + c` below `rule_s_limit` and `b` below 3) yields `say ERROR "$where" "Executor names $eid but $first ranks first and admits total $t"`. Overridden tasks already fail earlier and never reach it. Every existing check in the branch (registered id, gate readable, rung, header names the id) stays and keeps its text.
3. `plan-lint`, the lane-eligible warning: the `lane` rows are already one per admitting executor in ranked order. In the final loop that prints them, keep the set of `where` labels already warned and skip a second row for a label; the existing filters (lane surface on, roster row usable) apply before a row counts, so the first row printed is the first admitting executor that is on and usable. The warning text is unchanged.
4. `plan-revise`: build the list the per-unit loop iterates (`for eid in $ticked`) from `executors ranked` filtered to the ticked ids, followed by any ticked id the registry does not print, in header order, so the "no gate thresholds" diagnostic still fires. Update the header comment: priority now chooses between eligible executors; the skill still performs the edits. The `header` row's `executors=` keeps the order as written. Survey mode is unchanged.

- [ ] **Step 4: Run the tests to verify they pass**

Run the two commands of Step 2, then
`timeout 300 bash plugins/dforge/tests/inline-mode.test.sh | tail -n 1`, `timeout 120 bash plugins/dforge/tests/skill-split-planning.test.sh | tail -n 1`, `timeout 120 bash plugins/dforge/tests/lanes.test.sh | tail -n 1`.
Expected: every one ends `0 failed`. `plan-lint.test.sh` keeps its exact warning counts on the existing fixtures.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/scripts/plan-lint plugins/dforge/scripts/plan-revise plugins/dforge/tests/plan-lint.test.sh plugins/dforge/tests/plan-revise.test.sh
git commit -m "feat(dforge): rank executors in plan-lint and revise"
```

**Check:** the two suites of Step 2 and the three of Step 4 end `0 failed`; `bash plugins/dforge/scripts/plan-revise <a plan ticking codex>` prints the same rows as before this task.

#### Part B: State the routing rule in the planning prose

**Files:**
- Modify: `plugins/dforge/reference/executor-lane.md` (§Planning, and one sentence in §Dispatch step 1)
- Modify: `plugins/dforge/skills/writing-plans/references/assignment-procedure.md`
- Modify: `plugins/dforge/skills/revising-plans/SKILL.md` (steps 6-7 wording on several `rungs=`)
- Test: `plugins/dforge/tests/review-route.test.sh`, `plugins/dforge/tests/plan-revise.test.sh` (one prose row)

**Interfaces:**
- Consumes: Part A's behaviour: `plan-lint` rejects a line naming a lower-ranked executor, and `plan-revise` prints `rungs=` in ranked order. The prose must describe exactly that.
- Produces: the prose half of the routing rule C14: the header line `> **External executors:** agy, codex` (ticked ids in ranked order) in `executor-lane.md`, the first-admitting-executor sentences in `executor-lane.md` and `assignment-procedure.md`, and the revising-plans wording on taking the first rung. Tasks 9 and 10 build on these files.

**Implementer:** dforge:impl-sonnet-high
**Evaluation:** files 2 - spec 2 - coupling 1 - risk 0 = 5

- [ ] **Step 1: Write the failing tests**

**1a. Prose pins in `plugins/dforge/tests/review-route.test.sh`.** Replace the row at the line `present "planning runs the gate before the roster" "$EXEC" 'Unless it prints `lane=true`, stop here:'` with the first row below and add the others after it. Each pinned phrase must sit on one line of its file.

```bash
present "planning runs the gate before the roster" "$EXEC" 'Unless at least one gate prints `lane=true`, stop here:'
present "planning runs every gate in priority order" "$EXEC" 'Run the session gate of each registered executor in `executors ranked` order'
present "a closed gate drops only its own executor" "$EXEC" 'A gate that does not print `lane=true` drops only its own executor'
present "the header lists ticked ids in priority order" "$EXEC" '> **External executors:** agy, codex'
present "each task takes the first admitting ticked executor" "$EXEC" 'Each task goes to the first ticked executor, in priority order, whose gate block admits it'
present "a closed gate never hops to the next executor" "$EXEC" 'never to the next ranked executor'
AP="$P/skills/writing-plans/references/assignment-procedure.md"
absent "the precedence gap is closed" "$AP" 'No precedence rule is introduced here'
present "writing-plans routes to the first admitting executor" "$AP" 'the first ticked executor in `executors ranked` order whose gate admits it'
```

**1b. The revising-plans pin in `plugins/dforge/tests/plan-revise.test.sh`,** next to the other `present` rows for `$SK`:

```bash
present "the skill takes the first rung when several are listed" "$SK" "take the first, the highest-priority executor that admits the unit"
```

- [ ] **Step 2: Run the tests to verify they fail**

Run, each bounded:
`timeout 300 bash plugins/dforge/tests/review-route.test.sh | grep -E '^FAIL|passed,'`
`timeout 600 bash plugins/dforge/tests/plan-revise.test.sh | grep -E '^FAIL|passed,'`
Expected: FAIL rows for each new prose pin in `review-route.test.sh` (including `the precedence gap is closed`, because the old sentence is still there) and for `the skill takes the first rung when several are listed`; every other row passes.

- [ ] **Step 3: Write the prose**

1. `reference/executor-lane.md` §Planning, edited by quoted anchor (line numbers move):
   - Replace the text from `Run the session gate first:` through the sentence that ends `Otherwise run the roster:` (the bash example, the `Say its line aloud` sentence and the `Unless it prints` sentence) with: run the session gate of each registered executor in `executors ranked` order (the sentence `Run the session gate of each registered executor in \`executors ranked\` order`, then the existing bash example with `<id>`), say a gate's line aloud when it ends `source=probe`, and state that `A gate that does not print \`lane=true\` drops only its own executor`: say `<id> off — <reason>` in one line (`<reason>` the gate's `reason`, `untrusted` when it printed `usable=true`). Then `Unless at least one gate prints \`lane=true\`, stop here:` ask nothing, run no roster, write the plan Claude-only. Otherwise run the roster.
   - The offer and constraint paragraphs keep their meaning (`tick it without asking` stays) but read per executor: an executor is offerable when its gate printed `lane=true` and the roster reports it `usable`.
   - The header example becomes `> **External executors:** agy, codex`, with a sentence that it lists the ticked ids comma-separated in `executors ranked` order.
   - The sentence introducing the gate bullets reads: `Each task goes to the first ticked executor, in priority order, whose gate block admits it.` The bullet list keeps its five conditions and every bullet's text, except the first, which becomes `- the executor was ticked,`; the line `- \`total <= max_score\`,` must remain exactly. After the bullets add one sentence: with both agy and codex ticked, totals 0-8 at risk 2 or below go to agy and Codex receives nothing, and with agy unticked or off Codex's routing is unchanged. The task's `**Executor:**` line names that executor's rung from its assignment block.
   - Leave the paragraph `**Tasks whose tests spawn piped Node child processes stay on the Claude lane.**` where it is (Task 10 moves it to Codex's section).
2. `reference/executor-lane.md` §Dispatch step 1, directly after the sentence ending `and record it with the line below, quoting the gate's \`reason\``, add: the substitution always lands on the task's `**Implementer:**` agent, `never to the next ranked executor`.
3. `skills/writing-plans/references/assignment-procedure.md`: in step 4 keep the phrase `for every executor whose gate prints \`lane=true\`` and add that the offer's ticks are written in `executors ranked` order. Replace the closing paragraph that begins `**A task carries at most one` (keep its first sentence, `A task carries at most one \`**Executor:**\` line`) so it says the line names the first ticked executor in `executors ranked` order whose gate admits it, that `plan-lint` rejects a line naming another executor while a higher-priority ticked executor admits the task, and that no choice is left to the planner. Delete the sentence `No precedence rule is introduced here`.
4. `skills/revising-plans/SKILL.md` steps 6-7: the header line example becomes `> **External executors:** <id>[, <id>]` in ranked order; replace `Where \`rungs=\` lists several, you choose one;` with `Where \`rungs=\` lists several, take the first, the highest-priority executor that admits the unit;` and make the reconcile sentence read: if the unit's id is absent from `rungs=`, or is not its first id, or its rung differs from the one printed for that id, replace it with the printed rung of the first id. The phrase `replace it with the printed rung` must remain.

- [ ] **Step 4: Run the tests to verify they pass**

Run the two commands of Step 2, then
`timeout 300 bash plugins/dforge/tests/inline-mode.test.sh | tail -n 1`, `timeout 120 bash plugins/dforge/tests/skill-split-planning.test.sh | tail -n 1`, `timeout 120 bash plugins/dforge/tests/lanes.test.sh | tail -n 1`, and the Part A suites `timeout 900 bash plugins/dforge/tests/plan-lint.test.sh | tail -n 1`.
Expected: every one ends `0 failed`.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/reference/executor-lane.md plugins/dforge/skills/writing-plans/references/assignment-procedure.md plugins/dforge/skills/revising-plans/SKILL.md plugins/dforge/tests/review-route.test.sh plugins/dforge/tests/plan-revise.test.sh
git commit -m "docs(dforge): state the executor routing rule"
```

**Check:** `review-route.test.sh`, `plan-revise.test.sh`, `inline-mode.test.sh`, `skill-split-planning.test.sh` and `lanes.test.sh` end `0 failed`; `rg -n 'No precedence rule' plugins/dforge/skills plugins/dforge/reference` prints nothing.

### Task 9: Stop offering agy after two handbacks in a plan

**Files:**
- Create: `plugins/dforge/scripts/lane-breaker`
- Modify: `plugins/dforge/reference/executor-lane.md` (§Dispatch, a paragraph before the numbered list)
- Modify: `plugins/dforge/skills/subagent-driven-development/references/ledger.md` (the grammar block, the bullets after it, the Plan state paragraph)
- Modify: `plugins/dforge/skills/subagent-driven-development/SKILL.md` (§After compaction, step 2; one sentence, the file stays under 20,000 bytes)
- Modify: `plugins/dforge/reference/delegated-task.md` (§1, the paragraph beginning `**Read the task's \`**Executor:**\` line first.**`)
- Modify: `scripts/test-shards.mjs` (a weight for the new suite)
- Test: `plugins/dforge/tests/lane-breaker.test.sh` (new)

**Interfaces:**
- Consumes: `plan_ledger` and `plan_locate` from `scripts/lib/plan.sh`; the ledger grammar of `references/ledger.md`.
- Produces: `scripts/lane-breaker PLAN_FILE <id>` (C15) printing `lane-breaker <id> state=<open|tripped> handbacks=<n>`; the ledger line `Plan: executor <id> off - unreliable (<k> handbacks)`.

**Implementer:** dforge:impl-opus-high
**Evaluation:** files 2 - spec 2 - coupling 1 - risk 1 = 6

- [ ] **Step 1: Write the failing test**

Create `plugins/dforge/tests/lane-breaker.test.sh`:

```bash
#!/usr/bin/env bash
# lane-breaker reads a plan's ledger and says whether an executor has been
# handed back from twice, which turns that executor off for the rest of the
# plan. The ledger is the only memory a resumed controller has, so every
# answer comes from it.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
P="$HERE/.."
BREAKER="$P/scripts/lane-breaker"

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
present() { # present <name> <file> <needle>
  if grep -qF -- "$3" "$2" 2>/dev/null; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       missing: [%s] in %s\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
mkdir -p "$HOME"
unset CLAUDE_CONFIG_DIR

REPO="$TMP/repo"
git init -q "$REPO"
mkdir -p "$REPO/docs" "$REPO/.dforge/sdd/plan"
printf '# Breaker Fixture Plan\n\n### Task 1: One\n\n**Files:**\n- Create: `a.txt`\n' > "$REPO/docs/plan.md"
LEDGER="$REPO/.dforge/sdd/plan/progress.md"
PLAN="$REPO/docs/plan.md"

ledger() { printf '%s\n' '# SDD ledger — plan: docs/plan.md' "$@" > "$LEDGER"; }
breaker() { bash "$BREAKER" "$PLAN" "$1" 2>&1; }

AGY1='Task 1: implementer impl-sonnet-low (assigned; base aaaaaaa; executor agy gemini-3.8-flash/medium, thread t1)'
HB1='Task 1: fix round 1/2 (0 addressed, 2 open — x; commits aaaaaaa..aaaaaaa; HANDBACK to impl-sonnet-low)'
AGY4='Task 4: implementer impl-sonnet-low (assigned; base ddddddd; executor agy claude-sonnet-5-5/medium, thread t4)'
HB4='Task 4: fix round 2/2 (0 addressed, 1 open — y; commits ddddddd..ddddddd; HANDBACK to impl-sonnet-low)'
CODEX3='Task 3: implementer impl-sonnet-low (assigned; base ccccccc; executor codex gpt-6.1-sol/low, thread t3)'
HB3='Task 3: fix round 1/2 (0 addressed, 1 open — z; commits ccccccc..ccccccc; HANDBACK to impl-sonnet-low)'

check "the script exists" "$([ -f "$BREAKER" ] && echo yes || echo no)" "yes"

rm -f "$LEDGER"
check "no ledger: open with no handbacks" "$(breaker agy)" "lane-breaker agy state=open handbacks=0"

ledger "$AGY1" "$HB1" "$HB1" 'Task 2: implementer impl-sonnet-low (assigned; base bbbbbbb; executor agy claude-sonnet-5-5/medium, thread t2)' 'Task 2: complete (commits bbbbbbb..bbbbbbb, review clean) — done: x'
check "one handed-back agy task counts once, however many lines say HANDBACK" \
  "$(breaker agy)" "lane-breaker agy state=open handbacks=1"

ledger "$AGY1" "$HB1" "$CODEX3" "$HB3"
check "another executor's handback is not agy's" "$(breaker agy)" "lane-breaker agy state=open handbacks=1"
check "and is counted for its own id" "$(breaker codex)" "lane-breaker codex state=open handbacks=1"

ledger "$AGY1" "$HB1" "$CODEX3" "$HB3" "$AGY4" "$HB4"
check "two handed-back agy tasks trip the breaker" "$(breaker agy)" "lane-breaker agy state=tripped handbacks=2"
check "codex stays open at one" "$(breaker codex)" "lane-breaker codex state=open handbacks=1"

ledger 'Task 1: implementer impl-sonnet-low (assigned; base aaaaaaa; executor codex gpt-6.1-sol/low, thread t1)' \
  'Task 1: fix round 1/2 (0 addressed, 1 open — x; commits aaaaaaa..aaaaaaa; HANDBACK to impl-sonnet-low)' \
  'Task 10: implementer impl-sonnet-low (assigned; base bbbbbbb; executor agy claude-sonnet-5-5/medium, thread t10)'
check "Task 10 is not Task 1" "$(breaker agy)" "lane-breaker agy state=open handbacks=0"

ledger 'Task 5: implementer impl-sonnet-low (assigned; base eeeeeee; executor agy unavailable - off for this plan: unreliable (2 handbacks))' \
  'Task 5: complete (commits eeeeeee..eeeeeee, review clean) — done: x'
check "a task substituted onto its Implementer is not a handback" "$(breaker agy)" "lane-breaker agy state=open handbacks=0"

ledger 'Plan: executor agy off - unreliable (2 handbacks)'
check "the Plan line trips the breaker whatever the count" "$(breaker agy)" "lane-breaker agy state=tripped handbacks=0"
ledger 'Plan: executor codex off - unreliable (2 handbacks)'
check "a Plan line for another executor does not trip agy" "$(breaker agy)" "lane-breaker agy state=open handbacks=0"

ledger "$AGY1" "$HB1" "$AGY4" "$HB4"
sed -i 's/$/\r/' "$LEDGER"
check "a CRLF ledger reads the same" "$(breaker agy)" "lane-breaker agy state=tripped handbacks=2"

bash "$BREAKER" >/dev/null 2>&1; check "no argument exits 2" "$?" "2"
bash "$BREAKER" "$PLAN" >/dev/null 2>&1; check "no executor id exits 2" "$?" "2"
bash "$BREAKER" "$PLAN" 'Agy!' >/dev/null 2>&1; check "a malformed executor id exits 2" "$?" "2"
bash "$BREAKER" "$PLAN" agy extra >/dev/null 2>&1; check "an extra argument exits 2" "$?" "2"
bash "$BREAKER" "$REPO/docs/missing.md" agy >/dev/null 2>&1; check "a missing plan exits 2" "$?" "2"

# --- the documents that tell a controller to run it ---
EL="$P/reference/executor-lane.md"
LG="$P/skills/subagent-driven-development/references/ledger.md"
SK="$P/skills/subagent-driven-development/SKILL.md"
DT="$P/reference/delegated-task.md"
present "dispatch runs the breaker before the gate" "$EL" 'bash "<plugin-root>/scripts/lane-breaker" PLAN_FILE agy'
present "dispatch writes the plan line" "$EL" 'Plan: executor agy off - unreliable (2 handbacks)'
present "a tripped breaker dispatches the Implementer agent" "$EL" 'executor agy unavailable - off for this plan: unreliable (2 handbacks)'
present "the ledger grammar holds the plan line" "$LG" 'Plan: executor <id> off - unreliable (<k> handbacks)'
present "recovery reads the plan line through the breaker" "$LG" 'scripts/lane-breaker'
present "after compaction the breaker keeps the lane off" "$SK" 'scripts/lane-breaker'
present "the delegated loop points at the breaker" "$DT" 'scripts/lane-breaker'

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `timeout 120 bash plugins/dforge/tests/lane-breaker.test.sh | tail -n 3`
Expected: FAIL rows for every behaviour row (the script does not exist) and for each prose pin; `the script exists` fails first. Also run `timeout 120 node --test tests/test-shards.test.mjs 2>&1 | grep -E '^ℹ (pass|fail)'`: expected a non-zero `ℹ fail` count, the failure naming `lane-breaker.test.sh` as a suite with no weight.

- [ ] **Step 3: Implement the breaker and its documents**

1. `scripts/lane-breaker` follows the script conventions in Global Constraints (`#!/usr/bin/env bash`, `set -uo pipefail`, `die()` printing `lane-breaker: <message>` to stderr with exit 2), sources `lib/plan.sh`, and takes exactly `PLAN_FILE <id>`: any other argument count, an `<id>` that does not match `^[a-z][a-z0-9-]*$`, or a plan that `plan_locate` does not resolve to an existing file exits 2.
2. It reads the ledger with `plan_ledger`, strips `\r`, and when there is none prints `lane-breaker <id> state=open handbacks=0`. Otherwise one `awk` pass over the `Task <N>:` lines (matched by `^Task [0-9]+:`, so Task 10 is never Task 1) marks a task as assigned to `<id>` when a line contains `executor <id> ` (trailing space; the id arrives through `ENVIRON`) and as handed back when any of its lines contains `HANDBACK`; the count is the tasks with both marks. A line matching `^Plan: executor <id> off - unreliable \(` also trips it. It prints `lane-breaker <id> state=<tripped|open> handbacks=<n>`: tripped when `n` is at least 2 or the Plan line exists. Exit 0.
3. `reference/executor-lane.md` §Dispatch: directly before the numbered list that starts `1. **Gate, then guard the roster.**`, add a paragraph headed `**The per-plan breaker (agy only).**`. Before step 1 for a task whose `**Executor:**` line names `agy`, run `bash "<plugin-root>/scripts/lane-breaker" PLAN_FILE agy`. On `state=tripped` run neither the gate, the roster nor the wrapper: dispatch the task's `**Implementer:**` agent, say `agy off — unreliable (2 handbacks)` aloud, and record the assigned line `Task <N>: implementer <agent> (assigned; base <sha7>; executor agy unavailable - off for this plan: unreliable (2 handbacks))`. After the line recording any agy task's handback is written, run the breaker again; when it prints `state=tripped` and the ledger holds no `Plan: executor agy off - unreliable` line, say the same sentence aloud and append `Plan: executor agy off - unreliable (2 handbacks)`. The breaker is additive to the per-task rules; `agyLane` stays the manual switch; a resumed controller needs nothing more, because every dispatch reads the ledger through the breaker.
4. `references/ledger.md`: add `Plan: executor <id> off - unreliable (<k> handbacks)` to the grammar block, a bullet saying it is written by executor-lane.md §Dispatch, names no task so no per-task Recovery row reads it, and is read by `scripts/lane-breaker`; and one sentence in the Plan state paragraph that a ledger holding it keeps that executor off for the rest of the plan.
5. `skills/subagent-driven-development/SKILL.md`, §After compaction step 2: one sentence that a `Plan: executor <id> off - unreliable` ledger line keeps that executor off, and dispatch reads it through `scripts/lane-breaker`. Check `wc -c` stays at or below 20,000.
6. `reference/delegated-task.md` §1, after the `**Read the task's \`**Executor:**\` line first.**` paragraph: one sentence that for an `agy` task the dispatch first runs `scripts/lane-breaker` (executor-lane.md §Dispatch).
7. `scripts/test-shards.mjs`: add `'lane-breaker.test.sh': 10,` after `'ladder.test.sh': 10,`, a weight of 10 if the suite runs in under 10 seconds on this host (`time bash plugins/dforge/tests/lane-breaker.test.sh`), the measured whole seconds rounded up otherwise.

- [ ] **Step 4: Run the tests to verify they pass**

Run:
`timeout 120 bash plugins/dforge/tests/lane-breaker.test.sh | tail -n 1` — expected `0 failed`.
`timeout 120 node --test tests/test-shards.test.mjs 2>&1 | grep -E '^ℹ (pass|fail)'` — expected `ℹ fail 0`.
`timeout 120 bash plugins/dforge/tests/skill-size.test.sh | tail -n 1`, `timeout 300 bash plugins/dforge/tests/sdd-references.test.sh | tail -n 1`, `timeout 300 bash plugins/dforge/tests/review-route.test.sh | tail -n 1` — each ends `0 failed`.
Ledger readers must not choke on the new line: `timeout 600 bash plugins/dforge/tests/next-step.test.sh | tail -n 1` and `timeout 300 bash plugins/dforge/tests/in-flight.test.sh | tail -n 1` end `0 failed`.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/scripts/lane-breaker plugins/dforge/tests/lane-breaker.test.sh plugins/dforge/reference/executor-lane.md plugins/dforge/reference/delegated-task.md plugins/dforge/skills/subagent-driven-development/references/ledger.md plugins/dforge/skills/subagent-driven-development/SKILL.md scripts/test-shards.mjs
git commit -m "feat(dforge): add the per-plan agy breaker"
```

**Check:** `bash plugins/dforge/tests/lane-breaker.test.sh | tail -n 1` ends `0 failed`, and `bash plugins/dforge/scripts/lane-breaker <a plan with no ledger> agy` prints `lane-breaker agy state=open handbacks=0`.

### Task 10: Document the agy lane and release 4.10.0

**Files:**
- Modify: `plugins/dforge/reference/executor-lane.md` (the single-executor passages, the registry table, the two per-executor sections)
- Modify: `plugins/dforge/README.md` (the lane section, the session-gate paragraph, the registry paragraph, the `scripts/` list)
- Modify: `plugins/dforge/.claude-plugin/plugin.json`, `plugins/dforge/.codex-plugin/plugin.json` (version)
- Test: `plugins/dforge/tests/lanes.test.sh`, `plugins/dforge/tests/review-route.test.sh`

**Interfaces:**
- Consumes: everything Tasks 1-9 produced, by name: `executors ranked` (C1), the C2 blocks, `agy-gate` (C7), `run-agy-task.sh` and its `## Agy error` section (C9, C10), the git guard (C11), `lane-breaker` (C15).
- Produces: `## Per-executor: agy` and `## Per-executor: codex` in `executor-lane.md`; plugin version 4.10.0.

**Implementer:** dforge:impl-sonnet-high
**Evaluation:** files 2 - spec 2 - coupling 1 - risk 0 = 5

- [ ] **Step 1: Write the failing tests**

Part A: append to `plugins/dforge/tests/lanes.test.sh`, directly above the closing `printf '\n%d passed, %d failed\n'` line (after Task 7's section). `EL` is already defined in this suite as the path of `reference/executor-lane.md`.

```bash
# --- the lane reference is executor-neutral, with a section per executor ---
outside() { awk 'BEGIN { on = 1 } /^## / { on = ($0 != "## Codex task review seats" && $0 != "## Final-review Codex round" && $0 != "## Per-executor: codex") } on' "$EL"; }
section() { awk -v h="$1" '/^## / { on = ($0 == "## " h) } on' "$EL" | tr '\n' ' ' | tr -s ' '; }

for gone in 'codex-timeout' 'codex-assignment' 'codex-successor' '## Codex error' 'codex lane is off' \
            'run-codex-task.sh' 'Codex ran' 'Codex finished cleanly' 'codex quota exhausted' \
            'Codex read the findings' 'Codex runs every task turn'; do
  check "executor-lane outside the Codex sections no longer says: $gone" "$(outside | grep -cF -- "$gone")" "0"
done
check "the exit-2 text is executor-neutral" \
  "$(grep -cF '`<id> lane is off for this session (<reason>)`' "$EL")" "1"
check "the registry table lists priority" "$(grep -c '^| `priority` |' "$EL")" "1"
check "the lane reference has a Per-executor: agy section" "$(grep -cxF '## Per-executor: agy' "$EL")" "1"

agy_sec=$(section 'Per-executor: agy')
for need in 'unsandboxed' 'fingerprints cover only the linked worktree and its refs' 'fixed pointer sentence' \
            'keeps a cached `reason=quota`' 'git for-each-ref' 'finished_reason' 'efforts `low`, `medium` and `high`' \
            'lane-breaker'; do
  check "Per-executor: agy says: $need" "$(grep -cF -- "$need" <<<"$agy_sec")" "1"
done
codex_sec=$(section 'Per-executor: codex')
check "the piped Node rule lives in the Codex section" \
  "$(grep -cF 'Tasks whose tests spawn piped Node child processes stay on the Claude lane' <<<"$codex_sec")" "1"
check "reaped is explained in the Codex section" \
  "$(grep -cF 'phase` and `reaped` as **evidence, not proof**' <<<"$codex_sec")" "1"

RD="$HERE/../README.md"
for need in 'Antigravity' 'scripts/run-agy-task.sh' 'scripts/agy-gate' 'scripts/lane-breaker' 'executors ranked'; do
  check "the README names $need" "$([ "$(grep -cF -- "$need" "$RD")" -ge 1 ] && echo yes || echo no)" "yes"
done
```

Part B: in `plugins/dforge/tests/review-route.test.sh`, replace the row at the line `present "a refused model hands back at once" "$EXEC" '| Refusal - \`refusal=true\` in the report'"'"'s \`## Codex error\` section | \`HANDBACK\` now'` with:

```bash
present "a refused model hands back at once" "$EXEC" '| Refusal - a refusal marker in the report'"'"'s `## <Id> error` section (`refusal=true` for Codex, `reason=unknown-model` for agy) | `HANDBACK` now'
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `timeout 120 bash plugins/dforge/tests/lanes.test.sh | grep -E '^FAIL|passed,'` and `timeout 300 bash plugins/dforge/tests/review-route.test.sh | grep -E '^FAIL|passed,'`
Expected: FAIL rows for each forbidden string still present, the neutral exit-2 text, the `priority` row, both Per-executor sections and the README names; the refusal pin fails until the row is reworded.

- [ ] **Step 3: Rewrite the lane reference and the README**

1. `reference/executor-lane.md`, edited by quoted anchor. Tasks 8 and 9 already rewrote §Planning and added the breaker paragraph; leave them. Make these passages executor-neutral, each naming `<id>`, `## <Id> error` and the blocks `executors get <id> blocks.<name>` instead of Codex's:
   - the second paragraph of the opening (`The lane is a gate in front of the Claude assignment table ...`): the blocks are `the blocks the registry entry names` (`gate`, assignment, successor, timeout; the `codex-judge` block is Codex's review seats').
   - §Dispatch, the background-call paragraph that begins `**Background is not a preference here`: every rung in an executor's timeout block is longer than ten minutes (from 900 seconds); `a controller reading that as an executor failure`. Keep `(rung bound + 120) × 1000 ms` exactly as written (the suite counts it three times).
   - §Dispatch step 1: the exit-2 text is `` `<id> lane is off for this session (<reason>)` ``.
   - §When a run fails: exit table row 1 reads `The executor ran and did not reach DONE`; the refresh paragraph says `before the next use of that executor of any kind`; the failure table rows read `## <Id> error`, and the Timeout row reads `Timeout - \`note=timed-out\` on the status line, \`exit=124\` or \`timedOut=true\` in the error section, without \`note=writer-unconfirmed\``; the Refusal row becomes exactly `| Refusal - a refusal marker in the report's \`## <Id> error\` section (\`refusal=true\` for Codex, \`reason=unknown-model\` for agy) | \`HANDBACK\` now. The account does not offer that model or effort, and every successor rung is the same model, so a retry or a successor would be refused too |`; the paragraph `**Read \`## Codex error\` ...**` becomes `**Read \`## <Id> error\` in the report, not \`<report>.stderr\`.**` with the keys `reason=`, `timedOut=true` and the executor-specific marker; the `exit=` bullet describes the wrapper's normalised 0, 1 or 124 for any executor; the exit-2 paragraph says `never infer that the executor did not run`.
   - §When the resume itself fails: the transient row names `## <Id> error`; the example ledger line says `executor quota exhausted`.
   - §Failure rows: the validation row reads `names a model outside the executor's assignment block, an effort its wrapper does not admit, or a pair with no row in its timeout block`; the empty-diff row begins `The executor read the findings and changed nothing on purpose`.
   - Move the paragraph `**Tasks whose tests spawn piped Node child processes stay on the Claude lane.**` out of §Planning into `## Per-executor: codex` as a bullet, keeping its first sentence verbatim and adding that it applies to Codex only (it runs in `workspace-write`); `agy` has no sandbox.
   - Move `## When the client itself wedges` into `## Per-executor: codex` as a `### When the client itself wedges` subsection, text unchanged, so that `reaped` is Codex's alone.
   - The registry field table gains a row `| \`priority\` | no | A non-negative integer; lower ranks first in \`executors ranked\`; an entry without one ranks after every entry with one |`, and the sentence below the table names `executors ranked`.
   - Add `## Per-executor: agy` after the Codex section, as bullets that between them contain these phrases verbatim: `unsandboxed` (it runs with the reach of a native Claude implementer subagent: it can write anywhere the user can, including other worktrees, the primary checkout and the home directory; accepted by the owner, so a recovery reader must know that the fingerprints cover only the linked worktree and its refs); `fixed pointer sentence` (the brief reaches `agy` as a file under `$DR_TASK_DIR/prompt/`, never as an argument, and `--add-dir` names only that directory); `keeps a cached \`reason=quota\`` (Antigravity publishes no reset time, so a quota failure marks the lane off for the session and `agy-gate --refresh` keeps that answer); `git for-each-ref` (the contract forbids git writes; the wrapper compares refs and the symbolic HEAD before and after the run and blocks on any difference, while HEAD and index changes are caught by the scope check); `finished_reason` (a print timeout exits 0 with \`finished_reason: "print_timeout"\` and is classified \`exit=124\`, \`reason=timeout\`); `efforts \`low\`, \`medium\` and \`high\``; `lane-breaker` (after two handbacks in a plan the lane is off for that plan). Also state: surfaces are `lane` only, so no review seat exists and Claude judges review its work; piped Node children are fine; `reason=` is one of `quota`, `timeout`, `unknown-model`, `error`.
2. `README.md`: rewrite the paragraph `**An external executor lane.**` for two executors: `agy` (priority 10) takes totals 0-8 at risk 2 or below, Gemini or Claude by score, implementation only, and Codex (priority 20) keeps the tasks `agy` refuses; planning gives each task to the first ticked executor whose gate admits it; the gate-floor paragraph stays, attributed to Codex; add the `agyLane` setting (`Agy tasks`), the unsandboxed-reach note in one sentence and the per-plan breaker. The registry paragraph (`reference/executors/ holds one JSON entry ...`) adds `executors ranked` and `priority`. The session-gate paragraph gains one sentence on `scripts/agy-gate`. The `scripts/` list gains `agy-locate`, `agy-gate`, `run-agy-task.sh`, `agy-report-schema.json` (byte-identical to `codex-report-schema.json`), `agy-task-contract.md`, `lib/agy-probe.mjs` and `lane-breaker`.
3. Both plugin manifests: set `"version"` to `"4.10.0"`, in each file, nothing else. This is a configuration value with no test of its own: `release.mjs` tags a hand bump at its own commit, so this is the last commit that touches `plugins/dforge/` in the plan.

- [ ] **Step 4: Run the tests and validate**

Run:
```bash
timeout 120 bash plugins/dforge/tests/lanes.test.sh | tail -n 1
timeout 300 bash plugins/dforge/tests/review-route.test.sh | tail -n 1
timeout 120 bash plugins/dforge/tests/ladder.test.sh | tail -n 1
timeout 120 bash plugins/dforge/tests/executors.test.sh | tail -n 1
timeout 600 /root/.local/bin/claude plugin test plugins/dforge
timeout 120 node scripts/validate-repository.mjs
timeout 180 /root/.local/bin/claude plugin validate plugins/dforge
timeout 180 /root/.local/bin/claude plugin validate .
```
Expected: the four suites end `0 failed`; `claude plugin test plugins/dforge` passes; `validate-repository.mjs` prints `Repository catalogs, manifests, versions, bundled links and the settings schema are valid.`; both `claude plugin validate` runs report `Validation passed`.

- [ ] **Step 5: Commit the documents, then the release**

```bash
git add plugins/dforge/reference/executor-lane.md plugins/dforge/README.md plugins/dforge/tests/lanes.test.sh plugins/dforge/tests/review-route.test.sh
git commit -m "docs(dforge): document the agy executor lane"
git add plugins/dforge/.claude-plugin/plugin.json plugins/dforge/.codex-plugin/plugin.json
git commit -m "chore(dforge): release 4.10.0"
```

**Check:** `jq -r .version < plugins/dforge/.claude-plugin/plugin.json` and the same for `.codex-plugin/plugin.json` both print `4.10.0`; `node scripts/validate-repository.mjs` passes; `node scripts/test-all.mjs` (bounded at 3600 seconds) ends with no failed suite.
