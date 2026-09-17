# External executor lane

This reference holds the Claude-hosted Codex CLI lane.
dr-superpowers:writing-plans reads Planning; dr-superpowers:subagent-driven-development
reads everything else. A native Codex host never uses this lane: it follows
[native-codex.md](native-codex.md), and a Claude `**Executor:**` line never
starts recursive CLI offload in a Codex host.

The lane is a gate in front of the Claude assignment table, never a rung on the
escalation ladder. [ladder.md](ladder.md) explains why, and holds the `gate`,
`codex-assignment`, `codex-successor`, and `codex-timeout` blocks read below,
plus the `codex-judge` block the review seats' runner reads.

## Planning

Run this once per plan, after scoring every task and before writing any
assignment line. Run the session gate first:

```bash
bash "<plugin-root>/scripts/codex-gate"
```

Say its line aloud when it ends `source=probe`. Unless it prints `lane=true`, stop here:
ask nothing, run no roster, and write the plan Claude-only, saying
`codex off — <reason>` in one line, `<reason>` being the gate's `reason`
(`untrusted` when it printed `usable=true`). Otherwise run the roster:

```bash
bash "<plugin-root>/scripts/detect-executors.sh"
```

Read `docs/superpowers/distilled/constraints.md` first, when the project has
one. If a constraint there declares an executor's lane on and the roster reports
that executor `usable`, tick it without asking and say so in one line; the
question below then covers only the other executors. An absent file is not an
error.

Render the roster as a multi-select question: one tickable option per executor
whose `usable` is `true`, and a prose line naming every other detected executor
with its `reason`. **If no executor is usable, ask nothing** and write the plan
Claude-only - an empty checkbox is a worse answer than no checkbox.

Record the tick as one appended blockquote line in the plan header:

```markdown
> **External executors:** codex
```

Then apply the lane gate from the `gate` block of [ladder.md](ladder.md) to each
task. All four conditions must hold:

- an executor was ticked,
- the task cleared Rule S without a human override,
- `total >= min_score`,
- `risk <= max_risk`.

A task that passes the gate takes its model and effort from that file's
`codex-assignment` block and gains one extra line. A task that fails it is
assigned from the Claude table exactly as before and gains nothing.

**The `**Implementer:**` line still names the Claude agent for the score.** The
executor is an override on a second line, never a replacement on the first:

```markdown
**Implementer:** dr-superpowers:impl-sonnet-medium
**Executor:** codex gpt-5.5 / medium
**Evaluation:** files 0 - spec 1 - coupling 1 - risk 0 = 2
```

**Batched tasks stay on the Claude lane.** A batch is one dispatch covering
several tasks, which a per-task `**Executor:**` line and per-task thread id
cannot represent. Do not write an `**Executor:**` line on a batched task.

## Dispatch

A task carrying an `**Executor:**` line runs on that CLI instead of its
`**Implementer:**` agent. Everything downstream - the review seat, the fix loop,
the ledger, the five-round cap - is unchanged, because the contract the loop
enforces is files and commits, not a particular runtime.

**There is no driver subagent.** Run the wrapper yourself as a background Bash
call, exactly as you already run `sdd-workspace` and `task-brief`. It prints one
status line and writes everything else to files.

**Background is not a preference here, it is the only shape that works.** The
Bash tool's `timeout` caps at 600000 ms - ten minutes - and every rung in
`codex-timeout` is longer than that, from 900 seconds to 2400. There is no
foreground timeout you can pass that outlasts even the cheapest rung, so a
foreground call is cut mid-run and a controller reading that as a Codex failure
has misdiagnosed its own harness.

A background call is not bound by `timeout` at all - measured, not assumed: a
25-second command under a 5000 ms timeout ran to completion and exited 0. So
pass no timeout, let the wrapper's own poll loop be the bound it already is, and
wait for the completion notification. The wrapper polls for the rung's
`codex-timeout` seconds, kills Codex, and always prints a status line, which is
the guarantee that makes waiting safe.

If you have a reason to run one in the foreground anyway, the ceiling is raised
by the `BASH_MAX_TIMEOUT_MS` environment variable, which your human partner sets
before the session starts. You cannot raise it from inside one.

**Reserve an exclusive linked worktree.** Refuse the primary checkout. Stop other
controller-owned writing agents/watchers there before offload; require manual
editing to cease in that worktree. The user can continue in the primary
checkout. Fingerprints detect drift, not who wrote it. Never remove a blocked or
unreconciled worktree. Read [external-task-recovery.md](external-task-recovery.md)
for ownership, artifacts, approved write sets, and recovery operations.

1. **Gate, then guard the roster.** Run `bash "<plugin-root>/scripts/codex-gate"`
   first, saying its line aloud when it ends `source=probe`.
   Unless it prints `lane=true`, run neither the roster nor the wrapper:
   dispatch the task's `**Implementer:**` agent on the Claude lane, say the
   substitution aloud, and record it with the line below, quoting the gate's
   `reason` (`untrusted` when it printed `usable=true`). Otherwise run
   `bash "<plugin-root>/scripts/detect-executors.sh"` and read the entry
   for the named executor. **Never trust the plan's copy** - it records what was
   available when the plan was written.

   If `usable` is false, dispatch the task's `**Implementer:**` agent on the
   Claude lane instead, say the substitution aloud, and record it, quoting the
   entry's `reason` field:

   ```
   Task <N>: implementer impl-sonnet-medium (assigned; base <sha7>; executor codex unavailable - <reason>)
   ```

   Never fall back silently. A silent fallback makes the whole lane invisible.

2. **Run the wrapper**, using the brief path `task-brief` printed and the
   worktree's repository root:

   ```bash
   bash "<plugin-root>/scripts/run-codex-task.sh" \
     --brief <brief> --report <workspace>/task-<N>-report.md \
     --cwd <worktree-root> --task-id <stable-task-id> --write-set <approved-paths.json> --model <model> --effort <effort>
   ```

   `--cwd` is the linked worktree root. Use the same task ID for initial runs,
   retries, and fix resumes, independently of the report filename. Derive the
   JSON write set from the plan's explicit create/modify/delete paths. The wrapper
   requires a clean initial index and worktree, stores authoritative artifacts
   under that worktree's Git directory, and stages only its verified scoped diff.
   Human-readable reports belong outside the checkout or in its ignored
   `.superpowers` workspace. An unignored report path is rejected.
   The `**Executor:**` line writes the rung as `codex <model> / <effort>`; the
   wrapper takes the two as separate flags. The timeout comes from
   [ladder.md](ladder.md)'s `codex-timeout` block, keyed by `<model>/<effort>`;
   do not pass `--timeout` unless you are deliberately overriding it.

   Record BASE before the run. The wrapper's status line reports the same range
   as `commits=<a7>..<b7>` once the run finishes.

3. **Record the assignment** when the wrapper's status line arrives, reading the
   thread id from its `thread=` field:

   ```
   Task <N>: implementer impl-sonnet-medium (assigned; base <sha7>; executor codex gpt-5.5/medium, thread 01a0...)
   ```

   The thread id must reach the ledger. It also lands in the report file. If it
   lived only in your context, a compaction would turn round 2 into a fresh
   dispatch wearing a resume's name.

4. **Review with the routed seat.** Run `scripts/review-route PLAN_FILE --task <N>`
   and review with the seat it prints. A task carrying an `**Executor:**` line
   always routes to a Claude judge, so Codex never reviews its own work. Do not
   tell the judge which lane produced the diff: a judge that knows the author
   scores the author, and nothing in its inputs needs to change to keep it
   unaware.

The wrapper's report carries `## Discovered issues (not fixed)` and
`## Assumptions made` exactly as a Claude implementer's report does, so the
task's complete line takes its checkpoint fields from it the same way.

## When a run fails

A failed *run* is not a failed *review*, and they take different paths. The
wrapper's exit code says which case you are in:

| Exit | Meaning |
|------|---------|
| 0 | `status=DONE`. Proceed to review, unless the report carries the empty-diff note below |
| 1 | Codex ran and did not reach DONE. Read the `status=` field on the same line |
| 2 | No status line was printed. Read the wrapper's own stderr before doing anything - see below |

**Refresh the gate first.** After any run whose status is not `DONE`, run
`bash "<plugin-root>/scripts/codex-gate" --refresh` before the next Codex use of
any kind - a retry, a successor rung, a resume or a review seat - so a quota or
login failure turns Codex off for the rest of the session. When the refreshed
line no longer says `lane=true`, the response is `HANDBACK` whatever the tables
below say; record it with the gate's `reason`.

**This section covers an initial run.** A resume round that fails takes a
different path, because two of the responses below are unavailable to it - see
When the resume itself fails.

A run failure is exit 1 with `status=BLOCKED`, or exit 0 with an empty diff.

An empty diff is the report's `- note: DONE with an empty diff; nothing was
committed` line, not `base==head` alone. Identical shas with no such note mean
the wrapper skipped the commit because `commit_subject` came back empty. Check
the working tree before acting: if it is dirty, Codex did real work that was
never staged - stage it, commit it under a conventional subject, and review as
normal. If it is clean, nothing was produced and this is the empty-diff
capability failure below; take the successor rung.

| Failure | Response |
|---------|----------|
| Transient - network, rate limit, quota, 5xx, named in the report's `## Codex error` section | Retry once at the same rung |
| Timeout - `note=timed-out` on the status line, `exit=124` | Retry once at the same rung with `--timeout` raised. Do not take the successor rung: it is a slower model and would time out too |
| Capability - empty diff, or `status=BLOCKED` with no transient cause | Move one rung via the `codex-successor` block and run once |
| `status=NEEDS_CONTEXT` | Answer the questions the report lists, then resume (below). Not a failure and not a retry, even though it also exits 1 |
| Any failure a second time | `HANDBACK` |

**Read `## Codex error` in the report, not `<report>.stderr`.** Codex reports API
failures - quota, rate limit, auth, 5xx - as events on its `--json` stream, which
is stdout, so they land in `<report>.jsonl` and never in `<report>.stderr`. The
wrapper lifts the first such event into that section for you. stderr holds the
CLI's own complaints instead - a rejected flag, a missing directory - which are
the failures that produce no error event at all, and the report still tails it
underneath.

`status` alone cannot tell you which failure you have, because it is forced to
`BLOCKED` on any non-zero exit. Two other fields separate the cases:

- **`exit=`** on the status line, and `- exit:` in the report, is Codex's own
  exit code. `exit=2` is an argument-parse failure that took milliseconds and no
  model call, and it means this wrapper and this CLI disagree - fix that rather
  than retrying or changing rung. `exit=1` with a `## Codex error` section is an
  ordinary failed run. `exit=0` with `status=BLOCKED` is the odd one: Codex
  finished cleanly and wrote no verdict, which is a capability failure.
- **`note=timed-out`**, with `exit=124`, means the wrapper's poll loop hit the
  rung's `codex-timeout` and killed Codex. You do not have to infer this from
  wall time - which you could not do anyway, since the wrapper runs as a
  background call and you are not watching the clock.

`note=codex-may-still-be-running` means the child outlived both kills and the
grace window - only a timeout reaches that path, so it appears alongside
`note=timed-out`. Check for and end that process before retrying, or the retry
puts two Codex runs in the same worktree.

A second `NEEDS_CONTEXT` on the same task is a capability failure: take the
successor rung or hand back. A one-shot agent that could not resolve the brief
after one clarification will not resolve it after two.

At most two Codex runs may *fail* per task before Claude takes over. Fix-round
resumes are not failures and do not count against that budget. `HANDBACK` is an
action, not a rung: dispatch the task's `**Implementer:**` agent on the Claude
lane and let the ordinary ladder govern from there. Record it inside the line the
loop is already writing, never as a line of its own.

**Exit 2 requires inspecting durable state before retry.** It can mean preflight,
state persistence, staging, or commit failure. Read the task record's phase and
error; never infer that Codex did not run from the exit code alone. Follow
[external-task-recovery.md](external-task-recovery.md). A failed commit can be
recovered without a model call. Never recover through whole-tree staging or
infer ownership from an old report. Scope changes and manual repairs need a
recorded approved amendment or baseline before automatic work continues.

## Resuming a Codex task

Fix rounds 1 to 3 resume the same Codex session, as a Claude implementer's
rounds do, to preserve its model, effort, and context. The resume-or-re-dispatch
cache rule (R4) does not apply here: the session runs on a separate
subscription, so there is no Claude cache cost to protect. Write the open
findings verbatim into a file and pass that file as the brief - the wrapper
appends the task contract to every run, resume included:

```bash
bash "<plugin-root>/scripts/run-codex-task.sh" \
  --brief <feedback-file> --report <workspace>/task-<N>-report-r<K>.md \
  --cwd <worktree-root> --task-id <stable-task-id> --write-set <approved-paths.json> --model <model> --effort <effort> --resume <thread-id> --review-round <K>
```

Give each round its own report path. The wrapper replaces the human report that
`--report` names, so reusing one path erases the earlier round that the loop
expects the fix reports to accumulate in. Hand the re-reviewer the round's own
report.

Keep every round's report inside the workspace directory `sdd-workspace` prints -
that directory is git-ignored. If that workspace is not ignored, write reports
outside the checkout, because the wrapper only un-stages the artefacts of the
report path it was given.

**Round 4 is `HANDBACK`.** The Claude implementer inherits the working tree, the
commits, and the report, which is the loop's own "supply the context and
re-dispatch" case. If the progress reading says the loop has stalled at round 3,
the handback happens at round 3 instead: that rule pulls this lane's exit point
earlier exactly as it pulls the Claude ladder's, and it may never push it later.

Handing back lands the task on the Claude assignment-table row for its score -
the tier the rubric picked before the fix rounds happened. The change of model
family plus a fresh context is the capability change rounds 4 and 5 exist to
buy. Say the handback aloud when it happens.

## When the resume itself fails

When a fix round *runs* and produces a bad diff, the fix loop handles it: that is
what the rounds are for. This section is about the other case - the round never
produced a diff to review, because the resume run failed the way an initial run
can fail. When a run fails is written for initial runs and does not apply here
unchanged, because two of its responses are unavailable to a fix round.

**The successor column is never consulted.** `codex-successor` is read only by a
failed initial run - [ladder.md](ladder.md) says so, and the reason is that
changing rung mid-fix-loop discards the session context those rounds exist to
preserve. A fix round that cannot proceed leaves the lane by `HANDBACK` instead,
which is where round 4 was taking it anyway.

**The two-failure budget is not consulted either.** That budget counts failed
*initial* runs, and fix-round resumes do not count against it. These rounds are
bounded by their own rule below and by the five-round cap.

| Resume outcome | Response |
|----------------|----------|
| Transient - the report's `## Codex error` names a rate limit, quota, network, or 5xx | Retry the same resume once, same rung, same thread |
| `note=timed-out` with `exit=124` | Retry the same resume once with `--timeout` raised |
| `exit=2` | The wrapper refused before launching, so nothing ran and the thread is untouched. A validation error in what you passed; fix it and re-issue the same resume. This does not count as a failed round |
| `status=BLOCKED`, or `exit=0` with no verdict, and no transient cause | `HANDBACK` now, rather than at round 4 |
| A second failure of any kind in the same round | `HANDBACK` |

**An empty diff means something different here.** When a run fails calls
`exit 0` with an empty diff a capability failure, that is a statement about an
initial run, where producing nothing means the agent could not start. A fix round
that returns `DONE` with an empty diff has read the findings and elected to
change nothing, which is a position, not a failure. Read the report's summary:
if it argues the findings are already addressed or wrong, send that claim to
the ruling seat as a `codex-empty-diff` item (subagent-driven-development, The
Ruling Seat) and carry out its verdict. Do not re-dispatch the round to force a diff. Two
consecutive empty-diff rounds are a stalled loop - `HANDBACK`.

Record any of this inside the fix-round line the loop is already writing, never
as a line of its own:

```
Task <N>: fix round 2/5 (0 addressed, 2 open - codex quota exhausted, retried once then handed back; commits a7f..a7f; HANDBACK to impl-sonnet-medium)
```

A handback from a failed resume is still a handback: say it aloud, and let the
ordinary Claude ladder govern from there.

## Codex task review seats

`scripts/review-route PLAN_FILE --task <N>` names a Codex seat for every task
without an `**Executor:**` line: `codex:light` for totals 0 to 3 and
`codex:heavy` for 4 to 6 at any risk up to 2,
and `codex:heavy+judge-fable` at risk 3. A task carrying
an `**Executor:**` line routes to a Claude judge, so these seats never review
Codex's own work - a property the final-review Codex round does not share.
Batched tasks never carry one, and route on the batch's highest total and risk.

The controller runs `scripts/codex-gate` before `review-route`, which names no
Codex seat while the gate has not opened the review surface. The runner runs the
gate again before its roster and reports `FAILED` with
`run-codex-review: codex is off for this session (<reason>)` unless it says
`usable=true`; a quota error during a run turns Codex off for the rest of the
session. It then establishes usability from the roster itself and never trusts the
plan's copy, passes the `codex-judge` row's bound to the client as a deadline, and
reports `FAILED` with the roster's own `reason` when Codex is not usable. Run it
as a background Bash call: the Bash tool's `timeout` caps at ten minutes, the
rung's bound is longer, and a background call is not bound by it at all.

```bash
bash "<plugin-root>/scripts/run-codex-review.sh" --kind task --tier <light|heavy> \
  --cwd <worktree-root> --out <workspace>/task-<N>-review-codex.json \
  --prompt <workspace>/task-<N>-review-codex-prompt.md
```

`codex:light` passes `--tier light`, which runs the `codex-judge` block's last
row and never falls back. `codex:heavy` and `codex:heavy+judge-fable` pass
`--tier heavy`: the runner takes the block's first row, and falls back once to
the last row on a refusal. There is no catalog to consult first - the codex
plugin advertises no model list, and reading Codex's own cache would cross the
boundary the session gate exists to hold. `--kind risk3` is the
same seat under its earlier name and stays accepted. The runner prints one
status line:

```
codex-judge <model>/<effort> status=OK|FALLBACK|TIMEOUT|FAILED exit=<n> out=<path> evidence=none
```

`evidence=none` is constant. This plugin reads no model catalog, so there is no
date to quote; the field is kept only because skills and suites read the line's
shape.

Read that line and nothing else. `OK` and `FALLBACK` are a seat that reviewed;
`FALLBACK` additionally means the preferred rung refused the run, so say the
substitution aloud and record it in the task's ledger line with the reason the
runner prints in its own `refused (...)` message. That reason comes from the
client's own result rather than from a log file: a refusal is classified from
the turn's error field, so which stream carried it no longer matters.

`TIMEOUT` or `FAILED` is a seat that produced no review. Dispatch the route's
`fallback` seat with the ordinary task-reviewer prompt and say so. Never read an
absent or malformed report as a clean review: the runner has already
distinguished a report that is missing from one that is merely unfavourable.

**The prompt** is
[task-reviewer-prompt.md](../skills/subagent-driven-development/references/task-reviewer-prompt.md)
with its criteria block, with three changes. Send only the `prompt:` body,
without the `Subagent ([JUDGE]):` and `description:` lines. Leave out the Second
Pass section: that pass is Fable's. And **replace the Output Format section and
the criteria block's output-format paragraph with the schema, rather than
appending to them.** The shipped schema, `criteria/codex-review-schema.json`,
carries the four criterion names, the 1 to 20 range, and the spec and quality
verdicts, and the final message is JSON rather than a markdown
`### Verification Scores` section. Send the criteria themselves - where to look,
what scores high, what to ignore - and let the schema state the shape. Sent
unedited, the prompt would order markdown while `--output-schema` forbids it.

Task and plan kinds send this plugin's own output schema, never Codex's review
report shape: a seat must return the criteria the Claude judges return. The
schema is a plugin file, outside every worktree, so it can never land in a
task's commit.

**At risk 3** this review is the first of two steps: the controller then
dispatches `judge-fable` with the Second Pass section naming this seat's
`--out` path, per [delegated-task.md](delegated-task.md) §3 Review the task.
Fable's verdicts and scores are the task's.

## Final-review Codex round

The final whole-branch review adds this round. Run the session gate first:

```bash
bash "<plugin-root>/scripts/codex-gate"
```

Say its line aloud when it ends `source=probe`.
Unless it prints `review=true`, skip the round: say `codex off — <reason>`,
`<reason>` being the gate's `reason` (`untrusted` when it printed
`usable=true`), and report the Claude review alone. Otherwise the runner decides
whether Codex is usable:

```bash
bash "<plugin-root>/scripts/run-codex-review.sh" --kind final \
  --cwd <worktree-root> --out <workspace>/final-review-codex.md \
  --base <base-branch>
```

`<base-branch>` is the branch this one forked from, not the review package's
`MERGE_BASE` sha: whether `--base` resolves a sha is unverified, and a branch
name is what this round has always passed. The runner owns the model, the
effort, the bound and the outcome, and prints one status line:

```
codex-judge <model>/<effort> status=OK|FALLBACK|TIMEOUT|FAILED exit=<n> out=<path> evidence=none
```

`OK` and `FALLBACK` are a round that produced findings; on `FALLBACK` say the
substitution aloud, because the round was judged by the fallback rung rather
than the preferred one. `TIMEOUT` and `FAILED` mean this round produced
nothing: skip it, say so, and report the Claude review alone, exactly as a
missing Codex has always been reported.

The final-review kind runs read-only by nature and takes no sandbox flag. Run
the runner as a background Bash call: the Bash tool's own `timeout` caps at ten
minutes while a whole-branch round needs more, and a background call is not
bound by it at all. The bound is the `codex-judge` row's third field, which the
runner passes to the client as a deadline; the client interrupts the turn and
reaps the broker when it expires.

The runner composes that round's prompt itself: `criteria/codex-final-review.md`
followed by `git diff <base>...HEAD`. It does not use the Codex plugin's own
review call, which reads only the model, the thread name and a target branch and
answers in Codex's report shape — a seat's criteria and its schema would both be
discarded. `--kind final` still takes no `--prompt`, and the round still returns
a markdown findings list, which is what [final-review.md](final-review.md) step 3
deduplicates.

The runner establishes usability itself from the same `detect-executors.sh`
roster the task seats use, so this round needs no separate guard; a Codex that
is not usable comes back as `status=FAILED` with the roster's own reason on
stderr.

Unlike the task seats, this round is **not** self-review-free. The branch
contains whatever the executor lane produced, so Codex is reviewing some of its
own commits. That is why every finding - whichever reviewer raised it - is then
verified by a judge that wrote none of the code.

## Failure rows

| Situation | Response |
|-----------|----------|
| Task has an `**Executor:**` line and `scripts/codex-gate` does not print `lane=true` | Dispatch the `**Implementer:**` agent, say the substitution aloud, record the gate's `reason` in the assigned line |
| Task has an `**Executor:**` line, the gate prints `lane=true`, and the CLI is usable | Run the wrapper; do not dispatch a subagent for it |
| Task has an `**Executor:**` line and the CLI is missing, unauthenticated, or not batch-capable | Dispatch the `**Implementer:**` agent, say the substitution aloud, record the roster's `reason` in the assigned line |
| The `**Executor:**` line names a model outside `codex-assignment`, an effort outside `low`/`medium`/`high`/`xhigh`/`ultra`, or a pair with no `codex-timeout` row | Ruling: dispatch the `**Implementer:**` agent (`HANDBACK`), say it aloud. The wrapper refuses all three with exit 2 anyway |
| Wrapper exits 2 during staging or commit | Read the durable record; use commit recovery after exact snapshot validation, or explicit reconciliation. Never rerun the model merely to retry a commit |
| Wrapper exits 2 on an initial run with any other message | It refused before launching Codex: a validation error, not a run failure. Ruling: `HANDBACK` to the `**Implementer:**` agent; never retry it unchanged |
| Two Codex runs have failed | `HANDBACK` to the `**Implementer:**` agent and continue on the Claude ladder |
| A fix-round resume failed to run at all | See When the resume itself fails. Never take the successor rung: `codex-successor` is read only by a failed initial run |
| A fix round returned DONE with an empty diff | Codex read the findings and changed nothing on purpose. Send the report's argument to the ruling seat as a `codex-empty-diff` item rather than re-dispatching; two in a row is a stalled loop and a `HANDBACK` |
| A review seat's status line says `FALLBACK` | The preferred judge rung refused the run and the runner already used the fallback once. Not a failure: record the substitution and its reason in the ledger line you are already writing |

Every ruling above is logged as `Ruling: <what> — <why> — <cost if wrong>` and
said aloud. None of them stops the run.
