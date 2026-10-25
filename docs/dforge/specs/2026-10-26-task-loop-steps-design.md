# Task-loop steps, digests and cheaper seats

**Execution strategy:** sequential — the skill and reference rewrites (§6)
consume the interfaces of `task-step`, `suite-run`, `in-flight` and the new
ruling routes, and the one independent part, the cockpit watchdog (§1), is
small.

**Register:** `docs/dforge/registers/2026-10-25-token-efficiency.md` rows 2, 4
and the task-loop part of 6.

## Decisions

- **Rulings on the register.** Asked which rows the next spec covers. Answer:
  "#2 + #4 + #6's task-loop part". Rows 3, 5, 8, 14 and 15 are deferred, and
  row 16 is open, with their reasons in the register.
- **Waiting.** Shown that the 2026-10-25 typed-seats run spent about 67% of the
  orchestrator's context tokens on 110 five-minute polling waits. Asked how the
  task loop should wait. Answer: "End the turn, rely on notices" — the option
  read: "Claude Code re-invokes the session when an agent finishes. Drop the
  bounded-stretch Monitor polling. A lost child is caught by the cockpit
  watchdog, extended to bound how long background work may hold a run".
- **Step command.** Asked what shape row 2's per-task step command takes.
  Answer: "Phase subcommands" — `scripts/task-step <phase> PLAN N`, each
  wrapping today's scripts, writing the filled dispatch prompt to a file and
  printing a short digest plus that step's instructions.
- **Rulings.** Asked which rulings may leave judge-opus or the seat. Answer:
  "Mechanical checks + Sonnet kinds" — scripted checks settle their
  cannot-verify items without a seat; cannot-verify and executor-empty-diff go
  to judge-sonnet-high; the other kinds stay on judge-opus; items arising for
  one task or wave share a dispatch.
- **Re-review and suites.** Asked what changes for re-reviews and suite runs.
  Answer: "Typed re-review + suite record" — the option read: "Re-reviews run
  on dforge:judge-sonnet-high. A fix of at most 3 changed lines whose fix
  report names a passing covering test skips the re-review. A suite-run script
  records HEAD, command and exit, so the session reruns a suite only at a new
  HEAD, and prints failures as a digest."
- **Spec review.** Answer: "Approve and run unattended"; finish: "Merge into
  main".

Finish: merge

## Problem

The usage analysis of 2026-10-25 counted about 50 orchestrator calls per task
at 238k context. A profile of the typed-seats execution session
(`40cb3d10-fb44-41ea-a1f9-91e02a074fd1`: 330 main-loop calls over 5 tasks and
a final review) showed where they go:

- **Waits.** 110 `Monitor` calls of `sleep 290; echo stretch-over`, each
  followed by a text-only turn: 220 of 360 turns and 59.5M of 90.0M context
  tokens. `skills/subagent-driven-development/SKILL.md` §The Task Loop
  prescribes these bounded stretches, although Claude Code starts a new turn
  when a background agent or shell finishes, and `scripts/turn-end.sh` already
  lets a turn end while background work runs.
- **Plumbing.** Every review takes `review-package`, `date +%s`, `codex-gate`,
  `review-route --task N` and `lens-route --task N` as separate calls, then a
  hand-expanded prompt. Compound forms of these are refused by Claude Code's
  worktree guard after `EnterWorktree` (7 refusals in the profile).
- **Suite output.** The orchestrator dug through `test-all` output with
  `grep`/`sed`/`tail` (17 calls, 15k characters) and missed a failing suite,
  which cost a fix round. Two suites were re-run at finishing on a HEAD the
  final fix wave had already reported passing.
- **Rulings.** Every ruling kind routes to `dforge:judge-opus`
  (`scripts/review-route` `--ruling`). The same cannot-verify question (commit
  identity and attribution trailers) was answered by hand for four tasks.
- **Re-reviews.** `re-review-prompt.md` dispatches a `general-purpose` Sonnet
  seat with a git fallback, and every fix round gets one, however small.

Implementer and reviewer reports already reach the session as completion
messages (1-2k and 4-8k characters); no report file was read with `cat`. This
design therefore leaves the review result where it is and removes the waits,
the plumbing and the suite digging.

## Design

### 1. Waiting (Claude Code)

`skills/subagent-driven-development/SKILL.md` §The Task Loop, "Waiting on
dispatched subagents", is rewritten for Claude Code:

- Agent dispatches run in the background on current Claude Code, and so do
  a Codex review seat and a suite longer than Bash's ten-minute foreground
  cap. While local work remains, keep working. With nothing left but waiting,
  end the turn; each completion notification starts the next turn. Never wait
  with `Monitor`, `sleep` or a polling loop.
- **On a turn that a notification started,** run `scripts/in-flight` before
  anything else and handle every launch that finished, including one whose
  notification was missed.

Codex keeps its bounded `wait_agent` stretches (`codex-tools.md`), since
completion mail does not wake an idle Codex session. `reference/delegated-task.md`
§2 ("wait in bounded stretches") points at the new rule.
`skills/handoff/SKILL.md` already says the same thing and is unchanged.

**`scripts/in-flight` prints ages.** Each line becomes
`<agent|shell> <task id> <started HH:MM> <idle Nm|idle -> <what>`: the start
is the launch result's transcript timestamp, and the idle age is the minutes
since the launch's activity file last changed. For a shell that is the file
its result names after `Output is being written to:`. For an agent it is the
file named after `output_file:`, as this host's launch results carry it
(2026-10-26: `output_file: /tmp/claude-0/<project>/<session>/tasks/<id>.output`),
and otherwise the agent's own transcript,
`<projects dir>/<session>/subagents/agent-<id>.jsonl`, which grows while the
agent works. The age is `-` only when neither exists. The scan keeps its existing `SINCE` bound (`inflight_scan`). `turn-end.sh`
and `next-step`, which read only the count and the `<what>` field, are
updated to the new field order.

**The cockpit watchdog.** Today the watchdog in `hooks/cockpit/register.tsx`
never wakes a bound auto run while background work holds it, so a hung child
would hold an unattended run indefinitely; with a stage pending, `autoStage`
books a failure once background work has deferred it for `DEFER_CAP_MS`
(30 minutes). New: when a bound run has had no live turn for `RECONCILE_MS`
(20 minutes) and only background work holds it, whether or not a stage is
pending, the cockpit submits one reconcile prompt:

> Background work has run 20 minutes since the last turn with no notification.
> Run `scripts/in-flight`. Stop with TaskStop each launch idle 30 minutes or
> more, and record a `Ruling:` line naming the task it served and that its
> result is void; leave the others running. Then continue the run, and end
> the turn again if only waiting remains.

It submits at most one such prompt per `RECONCILE_MS`, none outside an auto
run, and none while a turn is live. Because 20 minutes falls before the
30-minute deferral cap, the session can stop a hung launch before the stage's
failure is booked. The reconcile turn is a live turn, so it restarts the
stage's deferral clock (`autoDeferredSince` in `autoStage`); so that a stage
cannot be deferred forever, the third consecutive reconcile prompt for one
pending stage with no launch stopped and no notification between them books
the failure that `DEFER_CAP_MS` would have. The idle test is the
output file, not the launch's age, so a long but active implementer or Codex
seat (heavy reviews run up to 92 minutes) is never stopped. A background
suite that prints nothing for a long build step stays live because
`suite-run` writes a heartbeat line every 5 minutes (§4).

### 2. `scripts/task-step`

One command per mechanical phase of the delegated task loop
(`reference/delegated-task.md`), each a single plain call that passes the
worktree guard:

```
task-step start    PLAN_FILE N [M ...] [--wave K]
task-step review   PLAN_FILE N [M ...] [--base SHA] [--head REF]
task-step rereview PLAN_FILE N [M ...] [--base SHA] [--head REF] [--covered]
```

`N [M ...]` is a task, or a batch's task numbers. State lives in
`<workspace>/task-<N>-step.json`, named after the batch's first task: base,
head ref, review head, round and `t0`. A subcommand needs no SHA from the
session except where a parallel wave supplies one (below). Every subcommand
prints a digest of at most 15 lines, ending with the state it recorded (base,
review head, round, `t0`) and the budget line, as `task-brief` does. Exit
codes: 0 ok; 2 usage, or any subcommand on a `Host: codex` plan; 3 no such
task; 4 an amendment does not apply; 6 a required earlier step has not run
(`review` before `start`, `rereview` before `review`). Exit 5 is not used:
it is `context-size`'s handoff code.

- **start** runs `task-brief`, records BASE, reads the `**Implementer:**` and
  `**Executor:**` lines, writes the assigned ledger line, and writes
  `<workspace>/task-<N>-dispatch.md`: `implementer-prompt.md` with the brief
  path, report path and plugin root expanded. It prints the `subagent_type`
  and the dispatch file. The session's Agent prompt is the dispatch file's
  path plus what only the session knows: the one line on where the task fits,
  interfaces from earlier tasks, and the verdicts that bear on it
  (delegated-task.md §1 items 1, 3 and 4). A task with an `**Executor:**` line
  prints `executor <id>: follow executor-lane.md §Dispatch` and writes no
  dispatch file. A missing or unknown `**Implementer:**` line is scored at
  dispatch as today, and the line says so. With `--wave K` the assigned line
  ends `; wave K`, as parallel-waves.md requires; the session adds the filled
  Parallel workspace section to its Agent prompt.
- **review** runs `review-package` from the base to the head (HEAD unless
  `--head` names the task ref), records `t0` and the review head, runs
  `codex-gate`, `review-route --task` and `lens-route --task`, and writes
  `<workspace>/task-<N>-review-prompt.md`, the judge prompt, with every
  placeholder expanded, including `[LENS_FILES]` (or the section removed). It
  always writes the judge prompt, because a Codex seat's `TIMEOUT` or
  `FAILED` falls back to it; on a risk-3 route it writes it with the Second
  Pass section and `[CODEX_REVIEW_FILE]` set. For a Codex seat it also writes
  the Codex prompt file and prints the exact `run-codex-review.sh` command
  with its timeout. It runs the mechanical checks in §3 and prints their
  lines. Its digest names the seat, the prompt files and the check lines.
- **rereview** packages FIX_BASE (the review head recorded by `review` or the
  last `rereview`, or `--base`) to the head, records the new review head and
  increments the recorded round,
  applies the skip rule in §5, and either prints
  `re-review: skipped (<n> changed lines, 1 finding, <file>)` or writes the
  re-review prompt and prints its seat.

**Waves.** In a parallel wave the review head is the task's ref and the base
moves after an overlap rebase (`reference/parallel-waves.md`). The session
passes `--head <task ref>` to `review` and `rereview`. After an overlap
rebase it passes `--base <new HEAD>` to the scoped re-review's `rereview`, as
FIX_BASE (parallel-waves.md); both are recorded in the state file.

**What stays the session's.** The review result arrives as the reviewer's
completion message, as today. The session reads the verdicts and scores,
writes the `minor (deferred)` lines, decides clean, fix round (resume, fresh
or escalated, by the rules of delegated-task.md §4) or ruling, writes the fix
message, and writes every fix-round, complete and `Ruling:` line. `task-step`
writes only the assigned line.

`task-step` is a wrapper: `task-brief`, `review-package`, `review-route`,
`lens-route` and `codex-gate` keep their interfaces and tests. On a
`Host: codex` plan it exits 2 and the Codex loop runs as today. In an auto run
the session still runs `scripts/auto-run task-complete` after the complete
line.

### 3. Rulings: mechanical checks, batching, Sonnet kinds

**Mechanical checks.** `task-step review` runs, for the commits from base to
the review head: author and committer equal to `git config user.name` and
`user.email`, and no `Co-Authored-By:`, `Claude-Session:` or `Generated with`
trailer or line. Each prints `check <name>: clean` or what it found. A
reviewer cannot-verify item that one of these lines settles is logged
`Task <N>: Ruling: cannot-verify — settled by task-step check <name> — none`
and goes to no seat. A check that finds something is a finding for the fix
loop.

**Batching.** Items arising at one decision point already share a dispatch. In
a parallel wave, the cannot-verify items of every task whose review is in hand
when one task reaches its cannot-verify point go to one dispatch. Items of a
task not yet reviewed, or not yet dispatched, never hold that dispatch back
(`reference/parallel-waves.md`).

**Sonnet kinds.** `review-route PLAN_FILE --ruling` accepts a comma-separated
kind list. It prints `primary=dforge:judge-sonnet-high` when every kind is
`cannot-verify` or `executor-empty-diff` and no named task is risk 3;
otherwise `dforge:judge-opus`, as today. The `reason=` field records which.
`preflight`, `plan-conflict`, `breaker`, `blocked-plan`, `final-residual` and
`acceptance-ambiguous` stay on judge-opus.

### 4. `scripts/suite-run`

```
suite-run [--timeout SECONDS] -- COMMAND [ARG ...]
```

It runs a test or validation command and records
`<HEAD sha>\t<clean|dirty>\t<command>\t<exit>\t<log path>\t<epoch>` in
`<workspace>/suites.tsv`, with the output in a log file under the workspace.
Clean means `git status --porcelain --untracked-files=all` prints nothing;
ignored files, such as a local `.env`, are outside the guarantee. Before
running, it looks for a row with the same HEAD, clean then and now, the same
command and exit 0; if one exists it prints `suite: reused pass at <sha7>
(<age>)` and exits 0 without running. A dirty tree never reuses and never
records a reusable row.

The digest is the exit code, the pass and fail counts it can read, and up to
20 failing-test lines (TAP `not ok`, Bun `(fail)`, lines starting `FAIL`). The
exit code is the verdict: on a non-zero exit with no failing line matched, it
prints the last 30 lines of the log instead, so a failure is never reported as
silence. Default timeout 3600 seconds; exit 124 on timeout. While the command
runs, `suite-run` prints `suite-run: running <m>m` every 5 minutes. A run expected to
pass ten minutes is launched as background Bash under §1.

The session runs every suite it would run itself through `suite-run`: the
wave integration check, the final review's checks and finishing's
verification. `implementer-prompt.md` asks implementers to run the project's
full suite through it after their final commit, on a clean tree, in place of
the pre-commit full run (targeted tests still run before committing). The row
lands in the `suites.tsv` of the checkout the
implementer ran in: in a sequential plan that is the session's own, so a
fixer's passing run at the final HEAD is reused at finishing; a wave task's
row stays in its worktree and is never reused, and after a merge HEAD differs
and the suite runs again — the run that caught two failures in the profile.

### 5. Re-reviews

`re-review-prompt.md` names `dforge:judge-sonnet-high` as `subagent_type` with
no model, or `dforge:judge-opus` for a subtle concurrency fix, makes
`[DIFF_FILE]` mandatory and drops the git fallback, as the typed-seats plan did
for `code-reviewer.md`. `reference/delegated-task.md` §Seats changes its Scoped
re-review row to match, and `tests/seats.test.sh` loses that row as a passing
general-purpose case.

**Skip rule.** `task-step rereview` skips the re-review only when all hold:

- exactly one finding is open;
- the fix diff changes at most 3 lines, added plus deleted, test files
  included, and touches the file the finding names;
- the task is not risk 3;
- the session passes `--covered`, having confirmed the fix report names the
  covering tests, the command and passing output, which delegated-task.md §4
  already requires before any re-review.

The open-finding count and the finding's file come from
`<workspace>/task-<N>-fix-<R>.md`, the fix message the session writes, whose
first lines are one `- <file>: <finding>` bullet per open finding. A skipped
re-review counts the finding as addressed; the fix-round line records
`re-review skipped (<n> lines)` in place of the progress reading, and a skip
never triggers escalation. The progress rule (delegated-task.md §4) then
compares the next reading with the last round that returned one.

### 6. The skill and reference text

- `reference/delegated-task.md` §1-§4 replace their mechanics (task-brief,
  BASE, review-package, `date +%s`, codex-gate, review-route, lens-route,
  placeholder expansion) with the `task-step` call for each step, and §4 gives
  the fix message's bullet format. What only the session decides stays: report
  handling (§2), the review result, escalation, the breaker, Codex seats'
  status handling, executor tasks.
- `skills/subagent-driven-development/SKILL.md` §The Task Loop (waiting),
  §Example Workflow and §The Ruling Seat (the kind list and the mechanical
  checks) follow.
- `reference/parallel-waves.md` gains the `--head`/`--base` arguments, the
  in-hand cannot-verify batch, and runs its integration check through
  `suite-run`.
- `reference/final-review.md` and `skills/finishing-a-development-branch`
  run their suites through `suite-run`.
- `skills/executing-plans` uses `task-step` for its delegated tasks, through
  delegated-task.md.

## Acceptance

A1. [test, high] `task-step start PLAN N` writes the assigned ledger line and a dispatch file with the brief path, report path and plugin root expanded, and prints the `subagent_type` and the dispatch path in at most 15 lines ending with the recorded state and the budget line.
A2. [test, high] `task-step review PLAN N` writes a judge prompt with no unexpanded placeholder, naming each `lens-route` criteria path (or no lens section when it prints none), names the seat `review-route --task` prints, and prints the mechanical check lines; for a Codex seat it also writes the Codex prompt and prints the runner command, and on risk 3 the judge prompt carries the Second Pass section.
A3. [test, neg, high] `task-step review` before `start` and `rereview` before `review` exit 6, and every subcommand on a `Host: codex` plan exits 2, writing nothing.
A4. [test, high] `task-step review --head REF` packages base..REF and records REF; `--base SHA` on `review` or `rereview` makes that package start at SHA and not at the recorded base; `start --wave K` ends the assigned line `; wave K`.
A5. [test, high] `task-step rereview` skips the re-review only with exactly one open finding, a fix of at most 3 changed lines (test files included) touching that finding's file, a task below risk 3 and `--covered`; otherwise it writes a re-review prompt for `dforge:judge-sonnet-high`.
A6. [test, neg, high] A fix that edits only a test file other than the finding's, or any fix while two findings are open, is never skipped.
A7. [test, high] `review-route --ruling` prints `dforge:judge-sonnet-high` when every kind is `cannot-verify` or `executor-empty-diff` and no named task is risk 3, and `dforge:judge-opus` for any other kind, any risk-3 task, or a mixed list.
A8. [test, high] The mechanical checks report a commit whose author or committer differs from `git config user.name`/`user.email`, or which carries a `Co-Authored-By:`, `Claude-Session:` or `Generated with` line, and print `clean` otherwise.
A9. [test, high] `suite-run` reuses a recorded pass only at the same HEAD, with a clean tree then and now, for the same command; any other case runs the command and records it.
A10. [test, neg, high] `suite-run` on a failing command whose output matches no failing-line pattern prints the log's last 30 lines and exits non-zero; it never reports a failure as a pass or as empty output.
A11. [test, high] `scripts/in-flight` prints each running launch's start time and idle minutes, from the output file its launch result names or, for an agent, its subagent transcript, and `-` when neither exists; `turn-end.sh` and `next-step` still count and name the launches.
A12. [test, high] In a bound auto run with no live turn for more than 20 minutes and only background work holding it, the cockpit submits one reconcile prompt naming `scripts/in-flight` and the 30-minute idle rule, and no second one within the next 20 minutes.
A13. [test, neg, high] The cockpit submits no reconcile prompt outside an auto run or while a turn is live; with a stage pending the reconcile prompt comes before the stage's 30-minute failure booking, and the third consecutive reconcile with nothing stopped books that failure instead of a fourth prompt.
A14. [test, high] `subagent-driven-development` tells a Claude Code session to end the turn when only waiting remains, and no longer prescribes `Monitor` or `sleep` waits; `codex-tools.md` keeps bounded `wait_agent` stretches.
A15. [test, high] `re-review-prompt.md` names `dforge:judge-sonnet-high` (or `dforge:judge-opus` for a subtle concurrency fix), requires a diff file and carries no git fallback, and `tests/seats.test.sh` finds no general-purpose re-review seat.
A16. [demo, high] An execution run of the trimmed six-task ui-ux subject from the drafter measurement makes no wait calls, and its report gives main-loop calls and context tokens per task against the profile's baseline (330 calls over 5 tasks).

## Riskiest assumption

That ending the turn is a safe way to wait: a completion notification
reliably starts the next turn for every background launch the loop makes
(Agent dispatches and background Bash), so no progress depends on polling.
Evidence: this design session (2026-10-26) was restarted by task
notifications for two background Bash runs and two background Agents;
`scripts/turn-end.sh` lets a plain stop pass while background work runs; and
`skills/handoff/SKILL.md` already prescribes it. The gap is a hung child that
never notifies, covered for auto runs by the watchdog in §1. Its idle test
needs an activity file per agent: this host's Agent launch results name an
`output_file:` (observed 2026-10-26), while the repository's test fixtures,
modelled on an older result, carry none, so the subagent transcript is the
fallback. That the watchdog
guard (`!S.isTurnLive && !S.autoBusy && auto.active && isMainBackground($)`
with `activity.endedAt`, `hooks/cockpit/register.tsx`) can drive the reconcile
prompt is read from code, not yet exercised. Status: unverified for the
hung-child case — the plan's first task verifies it.

## Review rulings

- Fable, spec: §2 review file — judges have no Write tool, so `task-step verdict` and the reviewer-written review file are dropped; the review stays the completion message and the loop decisions stay the session's.
- Fable, spec: §3 wave batching — only the tasks whose reviews are in hand are batched, so a wave wider than its slots cannot deadlock.
- Fable, spec: §5 skip rule — test files count, the fix must touch the finding's file, and only a single open finding may skip.
- Fable, spec: §2 waves — `--head` and `--base` arguments carry the wave's task ref and rebased base; a wave task's `suites.tsv` row is never reused.
- Fable, spec: §1 reconcile — the bound is 30 minutes of output-file idleness, `in-flight` prints start and idle times, and the prompt fires at 20 minutes, before `autoStage`'s 30-minute failure booking.
- Fable, spec: §2 review — the judge prompt is always written beside a Codex prompt, with the Second Pass section on risk 3.
- Fable, spec: §1 foreground — not adopted: on this host Agent calls made without `run_in_background` ran in the background (this session's dispatches, 2026-10-26; `scripts/lib/snapshot.sh` captures an agentId from every Agent result), so end-the-turn is the wait.
- Fable, spec (round 2): §2 waves — `rereview --base` carries an overlap rebase's FIX_BASE; `start --wave K` writes the wave's assigned line; the session adds the Parallel workspace section.
- Fable, spec (round 2): §1 idle source — agents fall back to their subagent transcript; the `output_file:` line is quoted as observed; the third reconcile with nothing stopped books the stage failure, since the reconcile turn restarts the deferral clock.
- Fable, spec (round 2): §4 reuse — implementers run the full suite through `suite-run` after their final commit, so a clean-tree pass exists to reuse.
- Fable, spec (round 2): §5 progress — after a skip, the next reading compares with the last round that returned one.
- Fable, spec (round 2): §2 `rereview --round` dropped; the state file's round increments.
- Fable, spec (round 2): §1 quiet suites — `suite-run` prints a heartbeat every 5 minutes.
- Fable, spec: §4 clean — `git status --porcelain --untracked-files=all`; ignored files are outside the guarantee; long suites run in the background.
- Fable, spec: §2 digest — prints the recorded base, review head, round and `t0`.
- Fable, spec: A16 (was A15) — reports against the profile's baseline; the only hard bar is zero wait calls.
- Fable, spec: Decisions vs §5 width — stands at 3 lines: the chosen option's text named "at most 3 changed lines".

## Critic findings

Folded into Fable's first review round.

- Blocker — the reviewer could not write the review file `verdict` parses. Fixed: `verdict` dropped (§2).
- Blocker — wave-level cannot-verify batching deadlocked a wave wider than its slots. Fixed: in-hand tasks only (§3).
- High — the skip rule let a test-only fix through. Fixed (§5).
- High — the state model ignored parallel waves. Fixed: `--head`/`--base` (§2), `suites.tsv` per checkout (§4).
- High — the reconcile prompt named a bound that does not exist. Fixed: output-file idleness and `in-flight` ages (§1).
- Medium — a Codex seat needs the judge prompt too. Fixed (§2).
- Medium — judge-format parsing was fragile. Moot: no parsing remains.
- Medium — foreground dispatch is the simplest wait. Answered: Agent calls run in the background on this host (Review rulings).
- Nit — the digest should show the recorded state; `in-flight` per turn rescans the transcript. Fixed: the digest prints it (§2); the scan keeps its `SINCE` bound (§1).
