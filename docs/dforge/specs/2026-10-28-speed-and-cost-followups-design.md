# Speed-and-cost follow-ups

**Execution strategy:** parallel — the stop gate, the eval harness and the doc and test cleanups share no file with each other or with the security part; the security part (the judge write guard and task-step) carries the risk, so it runs alone.
**Depth:** full — risk

## Decisions

- **Row 27, baseline commands written by a review seat.** Question: "task-step verdict runs a review seat's `cannot-verify: baseline <command>` text through `bash -c`, unsandboxed, on your host … Which one?" Answer: "Plan-named only (Recommended)": "Run a baseline command only if its text appears verbatim in the approved plan (a backticked command in the task's section or header) or equals the task's recorded --suite command. Any other command goes to the ruling seat as free text." The original five options in final-fix-report.md were lost with the deleted ledger directory; the options put to the owner were rebuilt from the code.
- **Row 16, A17 demo.** Question: "Does this satisfy A17?" Answer: "Yes, close it". Row 16 was set to done on 2026-10-28.
- **Row 13, A19 demo.** Measured in this session on the Linux host: 0.02-0.03 s for a passing and a blocked 1,002-line report, three runs each, against the 2 s bar; `impl-stop-gate.test.sh` 70 passed. Row 13 was set to done on 2026-10-28.
- **Row 51, a status-less retry.** Question: "What should the gate do with a status-less retry from an agent it has already blocked?" Answer: "Re-check the report (Recommended)": "Treat it as still under the DONE contract: check the report file again and block if it still lacks a required section, up to the existing three-stop limit."
- **Rows 28-61, everything else.** Ruled by two read-only `dforge:judge-opus` checks of each row against main on 2026-10-28 (reports in `.dforge/rows-28-44-report.md` and `.dforge/rows-45-61-report.md`), adopted here:
  - drop, already fixed or wrong: 31, 37, 43; 41 duplicates row 27 and closes with it;
  - accept, no change: 40, 44, 49, 52, 55, 57, 58, 60, 61;
  - fix: 28, 29, 30, 32, 33, 34, 35, 36, 38, 39, 42, 45, 46, 47, 48, 50, 53, 54, 56, 59, and 51 above.
- **Row 29.** The 3600 s base-run default stands (the repository's `task-step.test.sh` shard alone runs 1340 s, `scripts/test-shards.mjs`); the spec's and plan's 600 s figure for the base suite run is superseded. `baseline` items keep 600 s.
- **Amended plan.** The plan text a baseline command is matched against is the amended plan task-step already reads (`$src`), so a header amendment that changes a task's commands takes effect. Amendments are the controller's to write; §1's write guard keeps review seats out of `amendments.md`.
- **Judge write guard (added after the architecture critic).** The critic's Blocker showed that the owner's choice holds only if a review seat cannot write the files task-step trusts: the judge seats carry an unscoped Write tool (`plugins/dforge/agents/judge-*.md:6`), and nothing enforces "writes only its report file". §1 adds the guard; the spec review confirms it.
- **Execution strategy.** `executionStrategy=parallel` is in force; recorded without asking.

## Design

### 1. No review seat's text reaches `bash -c` (rows 27, 41, 44)

Two changes, both required: a seat cannot write the inputs task-step trusts, and task-step runs only commands taken from those inputs. Review text still reaches the implementer as findings (the fix file, `rr_render`'s findings), as designed: a model with its own permissions chooses what to run from it.

**Judge write guard.** The cockpit's `tool.call` hook refuses a `Write`, `Edit`, `MultiEdit` or `NotebookEdit` call made in a judge seat's loop unless its target is a report path that seat's dispatch names. The check is the first thing the hook does, and only those four tools in a subagent loop (`e.agentId` set) look the agent up, so the main loop and every other call pay nothing.

- A loop is a judge's when the `spawns` record for `e.agentId` has seat `dforge:judge-*`, or `$.agent.list()` names that type; either suffices. `spawns` never drops an entry whose `isDone` is false.
- The allowed paths are captured in the `agent.spawn` hook from the dispatch prompt: every absolute path ending `-report.md` that lies under an allowed root, kept with the spawn record. A judge whose prompt names none may write no file. The allowed roots are `<checkout>/.dforge` and `<primary>/.dforge` as the cockpit already computes them (`readPlace`), refreshed on a worktree move; when neither is known the guard refuses.
- Paths: a relative target is refused. The target (`file_path`, or `notebook_path` for NotebookEdit) and each allowed path are normalised to forward slashes, with `.` and `..` resolved lexically, a drive letter lower-cased, and the comparison case-insensitive on win32. The target must equal an allowed path, no directory between the root and the target may be a symlink, and the target must not itself be one. A mismatch fails closed.
- The refusal reads `dforge: a review seat writes only the report file its dispatch names (<allowed paths>); <path> is not one.` and is recorded with the other cockpit refusals.
- The hook's `.catch` refuses a write-tool call from a judge loop whatever `guardAttribution` says, with a message naming the write guard, so an error before the check cannot let the write through.

Other agent types and the main loop are untouched. A call whose agent id neither `spawns` nor `$.agent.list()` names (a workflow agent, an engine fork) is untouched. On a Codex host the cockpit does not run; the Codex reviewer already runs `read-only` (`scripts/run-codex-review.sh:146`), and native Codex judges keep their host's sandbox.

**Plan-named commands.** `settle_item` runs a `cannot-verify: baseline <command>, expect <pass|fail>` item only when `<command>` is plan-named for the task being settled. Whitespace means space and tab. After trimming leading and trailing whitespace, the command must be byte-identical to one of:

- the task's recorded suite command (the step file's `.suite`);
- the plan header's `**Integration check:**` command: the line's text after the label, trimmed, with one enclosing backtick pair removed when present (the rule `run_at_base` already applies to `**Worktree setup:**`);
- the first inline code span on a line of `plan_task_text "$src" <task>` that begins, after optional leading whitespace, list marker or `|`, with `Run:` or `**Check:**`.

An inline code span is text between two single backticks on one line, outside any fenced block; a double-backtick span never matches. Fenced blocks never contribute: plans put file bodies and multi-line scripts there (the speed-and-cost plan's fences hold `rm -rf "$ROOT/clone" "$ROOT/hidden"` and `git commit` lines). `bash -c` receives the plan's copy of the string, never the seat's text.

A command that is not plan-named is never run: `settle_item` returns 2, a status no other path uses, and `settle_cannot_verify` keeps the item for the ruling seat with ` (command not named in the plan)` appended to its digest line. Every other unsettled item (malformed, timed out, 126 or 127, no worktree) still returns 1 and carries no suffix. Everything else about a plan-named item is unchanged: `run_at_base`, the 600 s bound, the log, match and mismatch.

Text follows the code:

- `task-reviewer-prompt.md`: `baseline` runs only the task's suite command, the plan's Integration check, or the command of one of the task's `Run:` or `**Check:**` lines, copied exactly; any other command is not run and goes to the ruling seat.
- `reference/delegated-task.md`: the "unsandboxed and with your rights" sentence says a baseline command runs only when the plan names it, that a plan-named command still runs unsandboxed with your rights as the suite does, and that review seats can write only their report files.

### 2. task-step robustness (rows 29, 30, 32, 33, 36, 38, 39, 42)

- **Worktree setup is bounded and logged (32).** In `run_at_base`, the `**Worktree setup:**` command runs as `timeout -k 10 <secs> bash -c "$setup" < /dev/null`, the same form `suite-run` uses, with the run's seconds bound, and its output goes to `<OUT_LOG>.setup.log` instead of `/dev/null`. On a setup timeout, `run_at_base` copies `<OUT_LOG>.setup.log` to `OUT_LOG`, prints `124` and returns 0, so `suite_base_lines` writes `task-<N>-base-timeout` as for a run timeout and a later `verdict` or `rereview` does not run the setup again, and `settle_item` sends a baseline item to the seat. A setup that fails for any other reason prints `task-step: the worktree setup failed at <sha7> (log <path>)`, removes the worktree, prints nothing on stdout and returns 1. The setup and the run each get the full bound, so one base run may take up to twice it.
- **Every new suite failure reaches the fix file (36).** `suite_check` writes one Important finding per non-baseline failing line, with no cap, and the Important count is the full total. Where `do_verdict` prints the finding lines, it prints at most the first 20 suite findings and, when there are more, one line `suite: <k> more failing lines in <fix file>`. `delegated-task.md` says so.
- **`rereview --base` on a sequential group member is refused (33).** `rereview` exits 2 with `task-step: --base does not apply to a group member; see delegated-task.md §3a` when the step file belongs to a sequential group (has `group` and no head ref). Wave tasks, which carry a head ref, keep `--base`.
- **An unreadable or missing step file is not "none recorded" (38).** Before `suite_check`, `suite_base_lines` or `suite_gap` read `.suite`, the caller checks in its own shell (not inside a `$(…)`) that the step file parses (`jq -e .`); in a group verdict a missing member step file counts too. Either dies with exit 6 and `cannot read <file>`, the exit `do_verdict` already uses for a missing or unread state file.
- **Binary hits are not evidence (39).** The symbol `git grep` in `settle_item` passes `-I`, so a symbol found only in a binary file reads as absent.
- **Doc (29).** `delegated-task.md`'s "takes up to ten minutes" for a red fix-head suite under `rereview --covered` reads "up to an hour (`TASK_STEP_BASE_TIMEOUT`)".
- **Doc (53).** `delegated-task.md` says the last `## Verified` section of the report is the current evidence.
- **Tests (30, 42).** `task-step-base.test.sh` gains a passing base row (no base run, `0 baseline`), a base row with exit 124 (falls through to a run), and a `verdict --cwd` that finds the base row only in that checkout's state. `task-step-settle.test.sh` gains `exists ./notes.txt at head, expect present` with verdict run from a subdirectory.

### 3. Stop gate (rows 35, 51, 53)

- **A blocked agent's next stop is checked even without a status (51).** A block writes `awaiting` on the counter file's line 3. The next stop of that agent id is checked as a DONE reply (the `Report:` line, the file and its sections) when it has no `**Status:**` line and line 3 reads `awaiting`. A status-less stop of an `awaiting` agent passes and clears line 3 when its text, or the first `**Status:**` line of its report file, matches `/(^|[^A-Za-z])\**Status:\**[ \t]*(BLOCKED|NEEDS_CONTEXT)/i`. Any stop that passes for an `awaiting` agent clears line 3 (the existing pass-through still writes `passed`), so later status-less replies of a resumed agent pass as today. The two-block and five-fire limits are unchanged. A status-less stop that cannot enter `cwd`, find the state directory or find its counter passes silently, with no fallback-log line; an agent never blocked keeps today's behaviour.
- **Only the last `## Verified` counts (53).** The awk resets `found` at every `## Verified` heading, so a fix round's appended section must hold its own valid bullet.
- **Test isolation (35).** `impl-stop-gate.test.sh` unsets `XDG_STATE_HOME`.

### 4. Eval harness (rows 34, 59)

- `evals/tiers/lib/pipeline.mjs`: `CLAUDE_CODE_USE_BEDROCK` and `CLAUDE_CODE_USE_VERTEX` leave the credential allowlist, matching the comment that cloud tokens stay out, and `isolatedEnv` sets `TMP` and `TEMP` to the same isolated directory as `TMPDIR`.
- `evals/tiers/lib/pipeline-manifest.mjs`: the git log is split on a NUL record separator instead of `@@`; `pipeline-manifest.test.mjs` gains a `fixRounds` case whose commit subject contains `@@`.

### 5. Docs and tests (rows 28, 45, 46, 47, 48, 50, 54, 56)

- **28.** `draft-pack` removes `<state>/drafts` too when it is empty after a join; `draft-pack.test.sh` asserts it is gone.
- **45.** `process-graph.md` labels say `./implementer-prompt.md` and so on, not `./references/…`.
- **46.** `subagent-driven-development/SKILL.md`, `executing-plans/SKILL.md` and both skills' `references/setup.md` point straight at `ledger.md` §Recovery and `recovery.md`.
- **47.** The unused `SD=` lines leave `review-depth.acceptance.test.sh` and `review-depth-qa.acceptance.test.sh`.
- **48.** `writing-plans/SKILL.md` names `brainstorming/references/design-phase.md` for the execution-strategy question.
- **50.** `auto-default.test.sh`'s negative check flattens the text before it searches; `review-depth-qa.acceptance.test.sh` uses `flat_skill`.
- **54.** `impl-clauses.test.sh`'s `says` counts occurrences, not lines.
- **56.** `docs/dforge/notes/2026-10-28-pipeline-smoke.md` gains a Caveats paragraph: the cost, turn and time figures come from the last `result` event only; the timeline includes subagent messages and the no-polling reading rests on the `parent_tool_use_id`-filtered check; `p1_overlap` was changed mid-run to group tool uses by message id. The historical plan is not edited.

### Error handling

Every new refusal fails closed: a judge write outside its report path, an unnamed baseline command, an unreadable step file and a timed-out setup are refused or reach the seat with a message; none reads as a pass. The one fail-open path is a Claude Code session where the cockpit mod did not load: a Claude Code older than the mod engine, or a `claude -p` run if mods do not load there (the plan's first task checks it). The write guard is then off, and since every file `verdict` trusts lives under the state directory a judge could then write, no mechanical second lock exists; the plan-named rule still keeps commands a seat merely writes in its report from running. The spec review records whether the owner accepts this residual.

## Parallel decomposition

| Part | Owns | Wave |
|---|---|---|
| A. Security and task-step (§1, §2) | `plugins/dforge/hooks/cockpit/register.tsx`, `plugins/dforge/tests/cockpit.test.ts`, `plugins/dforge/scripts/task-step`, `tests/task-step-*.test.sh`, `tests/delegated-suite.test.sh`, `reference/delegated-task.md`, `skills/subagent-driven-development/references/task-reviewer-prompt.md` | 2, alone (security) |
| B. Stop gate (§3) | `scripts/impl-stop-gate`, `tests/impl-stop-gate.test.sh` | 1 |
| C. Eval harness (§4) | `evals/tiers/lib/pipeline.mjs`, `evals/tiers/lib/pipeline-manifest.mjs`, `evals/tiers/tests/pipeline.test.mjs`, `evals/tiers/tests/pipeline-manifest.test.mjs` | 1 |
| D. Docs and tests (§5) | `scripts/draft-pack`, `tests/draft-pack.test.sh`, `process-graph.md`, the four §Recovery pointer files, `writing-plans/SKILL.md`, the two review-depth acceptance tests, `auto-default.test.sh`, `impl-clauses.test.sh`, the pipeline-smoke note | 1 |

No foundation part: no part consumes another's output. B, C and D run together; each suite builds its own `mktemp -d` repository, so their tests share no path. A runs after wave 1 merges, its tasks in sequence, the write guard first. The register is written only by the controller.

## Acceptance

A1. [test, high] A `cannot-verify: baseline <command>, expect pass` item whose command is the first code span of a `Run:` line in the task's text is run at the base commit and settled, as today.
A2. [test, high] A baseline item whose command is the header's Integration check, the first span of a task `**Check:**` line, or the task's recorded `--suite` command is run and settled.
A3. [test, neg, high] None of these is run, each leaving a marker file it would create absent: a command found nowhere in the plan; a command that contains a plan-named one (`<named>; touch marker`); a trimmed line of a fenced block in the task's text; the second code span of a `Run:` line. Each stays a `cannot-verify:` line in the digest ending ` (command not named in the plan)` and adds no ledger line.
A4. [test, neg, high] A plan-named baseline command that times out stays for the seat without the ` (command not named in the plan)` suffix.
A5. [test, neg, high] With the cockpit loaded, a `dforge:judge-*` subagent's Write to `<state>/sdd/<plan>/amendments.md`, to a task's step file, to a plan file or to a path outside the state directory is refused with the guard's message, and so are its Writes to `<ws>/task-1-report.md` and `<ws>/task-2-review-report.md` when its dispatch named only `<ws>/task-1-review-report.md`, to a relative path, to a `..` path, and through a symlinked directory; its Write to the named `<ws>/task-1-review-report.md` (also given as `C:\…` on win32) is allowed; a write-tool call from a judge loop while `$.agent.list()` throws and the attribution guard is off is refused; a `dforge:impl-*` subagent's and the main loop's Writes are not affected. The test drives the guard through `agent.spawn` with agent ids.
A6. [test, high] Pinned in `tests/delegated-suite.test.sh` and `tests/task-step-text.test.sh`: `task-reviewer-prompt.md` and `delegated-task.md` state that `baseline` runs only a plan-named command, and `delegated-task.md` says a plan-named command runs unsandboxed and that review seats write only their report files.
A7. [test, neg, high] A `**Worktree setup:**` command that sleeps past the bound does not hang `verdict`: the item goes to the seat, `<OUT_LOG>.setup.log` exists, and no temporary worktree is left (`git worktree list`); for the suite's base run, a second `verdict` does not run the setup again.
A8. [test, high] A red suite with 25 non-baseline failing lines writes 25 suite findings to the fix file and counts 25 Important; the digest shows 20 of them and `suite: 5 more failing lines in <fix file>`.
A9. [test, neg, high] `rereview --base <sha>` on a sequential group member exits 2 and leaves the step file's `.base` unchanged; on a wave task with a head ref it is accepted.
A10. [test, neg, high] `verdict --group` whose last member's step file is missing or not valid JSON exits 6 naming the file and does not print `suite: none recorded`.
A11. [test, neg, high] An `exists <symbol> at head, expect present` item whose symbol appears only in a binary file settles as a mismatch (absent), not as present.
A12. [test, high] `task-step-base.test.sh` covers a passing base row, an exit-124 base row and a `--cwd` base row; `task-step-settle.test.sh` covers a `./<name>` exists item from a subdirectory.
A13. [test, high] After one block, a retry from the same agent id with a `Report:` line, no `**Status:**` line and a report still missing `## Verified` exits 2; the same retry with a complete report exits 0.
A14. [test, neg, high] Each of these exits 0: a retry after a block whose text says `Status: blocked`; a status-less retry after a block whose report file's first status line is `**Status:** BLOCKED`; a status-less reply after a block followed by a complete DONE; a status-less reply after a block followed by `**Status:** BLOCKED`; any status-less reply from an agent never blocked, with no line added to the fallback log.
A15. [test, neg, high] A report with two `## Verified` sections, the first holding a valid bullet and the last holding none, is blocked.
A16. [test, high] `impl-stop-gate.test.sh` passes with `XDG_STATE_HOME` set in the calling environment and writes nothing under it.
A17. [test, neg, high] `isolatedEnv` passes no `CLAUDE_CODE_USE_BEDROCK` or `CLAUDE_CODE_USE_VERTEX` from the host, and its `TMP`, `TEMP` and `TMPDIR` all lie under the eval root.
A18. [test, high] `fixRounds` counts a commit whose subject contains `@@` as one commit.
A19. [test, neg, high] After `draft-pack` joins a plan's slices, neither `<state>/drafts/<plan>` nor an empty `<state>/drafts` remains.
A20. [test, high] The §5 text fixes hold: no `./references/` label in `process-graph.md`, the four Recovery pointers name `ledger.md` or `recovery.md`, `writing-plans/SKILL.md` names `design-phase.md`, `skill-split-planning.test.sh` reports no broken link, no `SD=` line in the two acceptance tests, and `impl-clauses.test.sh`, run against a temporary copy of the plugin with one clause duplicated in one `impl-*.md`, prints a FAIL line.
A21. [test, high] The pipeline-smoke note has a Caveats paragraph naming the last-`result`-event figures, the subagent timeline and the `p1_overlap` change.
A22. [demo, high] A live probe on the Linux host: a `dforge:judge-sonnet-high` dispatch told to write a file outside its report path is refused by the guard, and its report write succeeds.
A23. [test, high] `node scripts/validate-repository.mjs`, `node scripts/test-all.mjs` and `claude plugin validate` on the marketplace and every Claude plugin pass, and the CI run for the pushed commit is green on every job, the Windows shards included.

## Riskiest assumption

That the cockpit's `tool.call` hook runs before every tool call a judge subagent makes, background dispatches included, and that `$.agent.list()` names that agent's type at the time, so the guard sees every judge Write before it happens. If wrong, a review seat can still write `amendments.md` or a step file and row 27 stays open. The guard also assumes dforge's review dispatches name their report file as an absolute path under the state directory. Evidence so far: the hook is registered for every tool and already reads `e.agentId` for subagent loops (`plugins/dforge/hooks/cockpit/register.tsx:720-731`); the engine types say `agentId` names "the loop this call runs in: for a subagent … the `id` `$.agent.list()` gives it" and `AgentInfo.type` is "the agent type it was spawned as" (`claude-code.d.ts` of Claude Code 2.1.310, AgentLoop and AgentInfo). unverified — the plan's first task verifies it with A22's live probe, in an interactive session and a `claude -p` run, before the rest of §1 is built.

A weaker assumption, which only costs savings if wrong: reviewers' baseline questions name commands the plan's `Run:` and `**Check:**` lines already show (`docs/dforge/plans/2026-10-28-speed-and-cost.md:561`, `:596`, `:695`, `:1115` are the shape). If wrong, the design stays safe but inert, and every baseline item reaches the ruling seat.

## Critic findings

- **Blocker — the seat can write the allowlist's sources.** Fixed: §1's judge write guard, A5, A22, and the riskiest assumption now names the guard.
- **High — any code span or fenced line becomes runnable.** Fixed: §1 narrows plan-named commands to `.suite`, the Integration check and the first span of task `Run:` and `**Check:**` lines; fenced blocks never contribute (A3).
- **High — the blocked state never clears.** Fixed: §3's `awaiting` mark, cleared by any passing stop (A14).
- **Medium — a timed-out setup is retried each verdict.** Fixed: `timeout -k 10 … < /dev/null` and the base-timeout marker (§2, A7).
- **Medium — one return code cannot carry the label.** Fixed: return 2 for an unnamed command (§1, A4).
- **Medium — the counter lookup comes after the early exit.** Fixed: a status-less stop with no state directory or counter passes silently (§3, A14).
- **Medium — a missing step file still reads none recorded.** Fixed: missing counts in a group verdict (§2, A10).
- **Nit — the matching rule leaves terms undefined.** Fixed: whitespace, span and "the plan's copy runs" are defined in §1.
- **Nit — near-miss status lines.** Fixed: BLOCKED and NEEDS_CONTEXT are detected loosely (§3, A14).
- **Nit — the digest cap belongs in do_verdict.** Fixed (§2, A8).
- **Nit — die inside `$(suite_gap …)`.** Fixed: the parse check runs in the caller's shell (§2).

## Review rulings

- Fable, spec: §1 guard — only the report paths the dispatch names are writable, captured at `agent.spawn` from the prompt; a judge naming none writes nothing.
- Fable, spec: §2 setup timeout — `run_at_base` prints 124 and returns 0 with the setup log as `OUT_LOG`, so the base-timeout marker is written; the setup and the run each get the full bound.
- Fable, spec: §1 `.catch` — the write check runs first and the `.catch` refuses a judge's write-tool call whatever `guardAttribution` says.
- Fable, spec: §1 judge lookup — the `spawns` record or `$.agent.list()` suffices; `spawns` keeps every running entry; the test drives `agent.spawn`.
- Fable, spec: §1 roots — `<checkout>/.dforge` and `<primary>/.dforge` from `readPlace`; unknown roots refuse.
- Fable, spec: §1 paths — relative refused; lexical normalisation, win32 case-insensitive; no symlink between root and target.
- Fable, spec: §1 Integration check — the line's text after the label, one backtick pair removed.
- Fable, spec: §3 `awaiting` — a report file's BLOCKED or NEEDS_CONTEXT status passes; an unenterable `cwd` passes silently.
- Fable, spec: Error handling — the fail-open sessions are named and the residual goes to the owner.
- Fable, spec: Decomposition — `evals/tiers/tests/pipeline.test.mjs` to Part C, `tests/delegated-suite.test.sh` to Part A.
- Fable, spec: A6 and A20 — named test files and a duplicated-clause copy.
- Fable, spec: §1 heading — scoped to `bash -c`; findings still reach the implementer as designed.
- Fable, spec: §1 cost — lookup only for the four write tools in a subagent loop.
