---
name: dispatching-tiered-implementers
description: Use when executing a plan whose tasks carry an Implementer line - dispatches the named model and effort tiered subagent and escalates along a defined ladder
---

# Dispatching Tiered Implementers

Run superpowers:subagent-driven-development exactly as written, with one
substitution: the implementer dispatch names a fleet agent instead of
`general-purpose`.

**Announce at start:** "I'm using the dispatching-tiered-implementers skill to
dispatch each task's assigned implementer."

## What changes, and what does not

**Changes.** Four things:

1. The implementer dispatch passes
   `subagent_type: dcc-superpower-companions:impl-<model>-<effort>` and passes
   **no `model` argument**.
2. The task-review seat is a judge agent - `judge-fable`, or `judge-opus` when
   Fable is unavailable - dispatched with the criteria file appended to
   superpowers' reviewer prompt. See Score the review.
3. The scoped re-review is asked for one extra line, a progress reading, which
   can pull the escalation point from round 4 to round 3. See Progress.
4. The final whole-branch review gains a Codex round and a verification pass over
   the union of both reviewers' findings. See The final whole-branch review.

**Does not change.** The brief and report file protocol, the review package, the
five-round cap, the breaker and its adjudication rules, and the handoff to
superpowers:finishing-a-development-branch. Implementers are still never
dispatched in parallel, and superpowers' own final whole-branch review still runs
as written, keeping its own model selection - what changes is that it is no
longer the only reviewer.

## The superpowers instructions this supersedes

Three, all named here or below: the model-selection rule in this section, the
final whole-branch review under The final whole-branch review, and fix rounds 4
and 5 for an external task under Resuming a Codex task.

superpowers:subagent-driven-development states in bold that you must always
specify the model explicitly when dispatching a subagent, because an omitted
model inherits the session's model.

**For dispatches of this plugin's fleet agents, that is superseded.** The Agent
tool's `model` argument overrides the agent file's `model` frontmatter, but
there is no matching `effort` argument, so effort keeps its frontmatter value.
Passing a model can therefore produce a pairing the fleet does not ship: a
`model: haiku` argument landing on an agent whose file sets `effort: high` gives
Haiku an effort level it does not support, since Haiku ships one flavour with no
effort variants.

The rule's intent survives intact: the agent definition pins the model, so
nothing inherits the session default.

The supersession covers every fleet agent whose frontmatter pins a model - the
seven execution implementers, the nine reserve implementers, both judges, and
the scout. Passing a `model` argument to
any of them overrides the pin while `effort` keeps its frontmatter value, so the
agent runs at a tier the ledger does not record - the audit failure this plugin
exists to prevent. For a judge seat it is worse: the override silently bypasses
the Fable-unavailable protocol, which requires you to say the substitution
aloud.

The rule remains in force for general-purpose dispatches, which in this loop
means superpowers' final whole-branch review.

## Dispatch a task

**Read the task's `**Executor:**` line first.** A task carrying one runs on that
CLI - see Dispatch an external executor below - and the steps here are its
fallback. A task without one takes these steps directly.

1. Read the task's `**Implementer:**` line.
2. If that value names one of the nine reserve implementers - every name in the
   `reserve` table of [`../../reference/ladder.md`](../../reference/ladder.md)
   except `impl-opus-high`, which is an execution implementer and appears there
   only as the conditional entry edge - dispatch it as written and note the tier
   in the ledger line you already add:

   ```
   Task <N>: implementer impl-opus-max (assigned; reserve tier)
   ```

   No score reaches a reserve agent, so its presence in a plan is a human
   ruling, and a human ruling beats the rubric. Dispatch it as written; do not
   re-score the task down to an execution tier. A 0.1.0 plan naming one of these
   agents is honoured the same way, because the tier it recorded is the tier it
   asked for.
3. Dispatch with that value as `subagent_type`, using superpowers'
   `implementer-prompt.md` template unchanged for the prompt body. Where the
   template's header reads `Subagent (general-purpose):`, use the assigned
   agent instead.
4. Record the agent identity from the dispatch result, exactly as superpowers
   requires. Fix rounds 1 to 3 resume this agent.
5. Note the assignment in the ledger superpowers already owns. Resolve its
   directory the way superpowers does — run its
   `scripts/sdd-workspace PLAN_FILE` and use the path it prints — rather than
   assuming a layout. The ledger is `progress.md` inside that directory.

   ```
   Task <N>: implementer <agent> (assigned)
   ```

   Never create a competing ledger. Superpowers owns five `Task <N>:` verbs —
   `complete`, `fix round`, `minor (deferred)`, `parked`, and `BLOCKED` — and
   no line you author may start with one of them. Its crash recovery keys on
   `Task <N>: complete`, and its final whole-branch review is pointed at the
   `minor (deferred)` and `parked` lines for triage, so a line either of them
   misreads costs a re-dispatch of finished work or a bogus merge blocker.
   Extending a line superpowers itself writes is a different act and is allowed
   in exactly three places: under Escalate, under Score the review, and under
   Progress.

   `Task <N>: implementer <agent> (assigned)` is the only line you add before
   the task's first review. Add it once, right after dispatch.

`sdd-workspace` prints a bare path, but `task-brief` does not — it prints
`wrote <path>: <N> lines`. Read the brief path out of that line; do not pipe
`task-brief`'s output into a dispatch prompt as if it were a filename.

## Dispatch an external executor

A task carrying an `**Executor:**` line runs on that CLI instead of its
`**Implementer:**` agent. Everything downstream - the review seat, the fix loop,
the ledger, the five-round cap - is unchanged, because the contract superpowers
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

**There is no separate worktree.** Codex runs in the SDD worktree, on the task
branch, where a Claude implementer would run. superpowers already created that
worktree at setup, and its finish step is `rm -rf <workspace>`, so a nested
worktree would be deleted out from under git.

1. **Guard the roster.** Run
   `bash "${CLAUDE_PLUGIN_ROOT}/scripts/detect-executors.sh"` and read the entry
   for the named executor. **Never trust the plan's copy** - it records what was
   available when the plan was written.

   If `usable` is false, dispatch the task's `**Implementer:**` agent on the
   Claude lane instead, say the substitution aloud, and record it, quoting the
   entry's `reason` field:

   ```
   Task <N>: implementer impl-sonnet-medium (assigned; executor codex unavailable - <reason>)
   ```

   Never fall back silently. A silent fallback makes the whole lane invisible.

2. **Run the wrapper**, using the brief path `task-brief` printed and the
   worktree's repository root:

   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/run-codex-task.sh" \
     --brief <brief> --report <workspace>/task-<N>-report.md \
     --cwd <worktree-root> --model <model> --effort <effort>
   ```

   `--cwd` is the repository root, not the workspace directory inside it. The
   wrapper refuses anything below the root with exit 2, because it stages with
   `git add -A` and a subdirectory would sweep unrelated work into the task's
   commit. The workspace `sdd-workspace` prints sits at
   `<worktree-root>/.superpowers/sdd/<plan-slug>`, so the root is that path's
   repository - `git rev-parse --show-toplevel`.

   The `**Executor:**` line writes the rung as `codex <model> / <effort>`; the
   wrapper takes the two as separate flags. The timeout comes from
   `reference/ladder.md`'s `codex-timeout` block, keyed by `<model>/<effort>`;
   do not pass `--timeout` unless you are deliberately overriding it.

   Record BASE before the run, as superpowers requires. The wrapper's status
   line reports the same range as `commits=<a7>..<b7>` once the run finishes.

3. **Record the assignment** by extending the `(assigned)` line this skill
   already owns, reading the thread id from the status line's `thread=` field:

   ```
   Task <N>: implementer impl-sonnet-medium (assigned; executor codex gpt-5.5/medium, thread 01a0...)
   ```

   The thread id must reach the ledger. It also lands in the report file. If it
   lived only in your context, a compaction would turn round 2 into a fresh
   dispatch wearing a resume's name.

4. **Review as normal.** Dispatch the judge exactly as for a Claude task. Do not
   tell it which lane produced the diff: a judge that knows the author scores
   the author, and nothing in its inputs needs to change to keep it unaware.

## When a run fails

A failed *run* is not a failed *review*, and they take different paths. The
wrapper's exit code says which case you are in:

| Exit | Meaning |
|------|---------|
| 0 | `status=DONE`. Proceed to review, unless the report carries the empty-diff note below |
| 1 | Codex ran and did not reach DONE. Read the `status=` field on the same line |
| 2 | No status line was printed. Read the wrapper's own stderr before doing anything - see below |

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
| Transient - network, rate limit, 5xx in `<report>.stderr` | Retry once at the same rung |
| Timeout - the run's wall time reached the rung's `codex-timeout` value | Retry once at the same rung with `--timeout` raised. Do not take the successor rung: it is a slower model and would time out too |
| Capability - empty diff, or `status=BLOCKED` with no transient cause | Move one rung via the `codex-successor` block and run once |
| `status=NEEDS_CONTEXT` | Answer the questions the report lists, then resume (below). Not a failure and not a retry, even though it also exits 1 |
| Any failure a second time | `HANDBACK` |

A timeout is only identifiable from the wall time you observed, because the
wrapper prints no marker for it: it forces `status=BLOCKED` whenever Codex exits
non-zero, so a timed-out run and a capability block look identical on the status
line. You launched the wrapper, so you are the one who knows.

One case does carry a marker. `note=codex-may-still-be-running` on the status
line, and the matching note in the report, mean the child outlived both kills
and the wrapper's grace window - only a timeout reaches that path. Check for and
end that process before retrying, or the retry puts two Codex runs in the same
worktree.

A second `NEEDS_CONTEXT` on the same task is a capability failure: take the
successor rung or hand back. A one-shot agent that could not resolve the brief
after one clarification will not resolve it after two.

At most two Codex runs may *fail* per task before Claude takes over. Fix-round
resumes are not failures and do not count against that budget. `HANDBACK` is an
action, not a rung: dispatch the task's `**Implementer:**` agent on the Claude
lane and let the ordinary ladder govern from there. Record it inside the line the
loop is already writing, never as a line of its own.

**Exit 2 always means the run produced no status line** - the status line is the
last thing a completed run prints. Read the final `run-codex-task:` line from the
wrapper's own stderr, which is the command output you already have; it is not in
`<report>.stderr`, which only ever holds Codex's own stderr and is not created at
all when the wrapper refuses before launching. Two shapes:

- **Refused before launching.** The message names anything other than the two
  git failures below - an invalid model or effort, a missing `codex-timeout` row,
  a cwd that is not the repository root, a brief or schema it could not read, or
  a stale verdict file it could not clear. Codex never ran and the tree is
  untouched. The plan or the tables are wrong; fix them rather than retrying.
- **Failed after running.** The message is `git add failed` or `commit failed`.
  Codex ran and its work is staged but uncommitted, and the wrapper reported no
  report and no thread id. Recovering the thread id from `<report>.jsonl` is
  possible but not worth it when the tree needs manual repair anyway, so treat
  the round as unresumable. Recover the tree before anything
  else - a later `git add -A` would otherwise sweep this work into another task's
  commit - then treat it as a run failure and re-dispatch fresh or hand back.

## Resuming a Codex task

Fix rounds 1 to 3 resume the same Codex session, mirroring superpowers' rule that
those rounds resume the same implementer to preserve its model, effort, and
context. Write the open findings verbatim into a file and pass that file as the
brief - the wrapper appends the task contract to every run, resume included:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/run-codex-task.sh" \
  --brief <feedback-file> --report <workspace>/task-<N>-report-r<K>.md \
  --cwd <worktree-root> --model <model> --effort <effort> --resume <thread-id>
```

Give each round its own report path. The wrapper truncates whatever `--report`
names, so reusing one path erases the earlier round that superpowers expects the
fix reports to accumulate in. Hand the re-reviewer the round's own report.

Keep every round's report inside the workspace directory `sdd-workspace` prints -
superpowers' `.gitignore` entry covers it. In a host repository that does not
ignore that path, reuse one report path and copy it aside between rounds instead,
because the wrapper only un-stages the artefacts of the report path it was given.

**Round 4 is `HANDBACK`.** The Claude implementer inherits the working tree, the
commits, and the report, which is superpowers' own "supply the context and
re-dispatch" case. If Progress says the loop has stalled at round 3, the handback
happens at round 3 instead: that rule pulls this lane's exit point earlier
exactly as it pulls the Claude ladder's, and it may never push it later.

This supersedes superpowers' rounds 4 and 5 instruction to escalate to a *more
capable* model. Handing back lands the task on the Claude assignment-table row
for its score, which is the same tier the rubric picked before the fix rounds
happened. The argument for parity is that a change of model family plus a fresh
context satisfies the rule's intent, and that the recorded score is the only
evidence-free anchor available. Say the handback aloud when it happens.

## Escalate

Read the escalation table from
[`../../reference/ladder.md`](../../reference/ladder.md). Escalation applies at
three points - the two superpowers defines, plus one this skill adds:

- **Fix rounds 4 and 5**, where superpowers dispatches a fresh implementer on a
  more capable model.
- **The BLOCKED handler**, where superpowers re-dispatches on a more capable
  model when the task requires more reasoning. A BLOCKED report caused by
  missing context is not an escalation: supply the context and re-dispatch the
  same agent, as superpowers says.
- **Round 3, when progress has stalled** - see Progress below. This can only
  pull the escalation point earlier, never later.

None of the three applies to a task running on an external executor. Its fix
rounds resume the same Codex session and it leaves the lane by `HANDBACK`
instead of by climbing a rung - see Resuming a Codex task above.

Escalation does **not** apply to fix rounds 1 and 2, nor to round 3 unless
Progress says the loop has stalled. Those rounds resume the original agent,
which preserves its model, its effort, and its context. Re-dispatching a
different tier there discards exactly what superpowers is preserving.

Record each escalation **inside** superpowers' own fix-round line, by appending
one clause to the line it already writes at the end of the round:

```
Task <N>: fix round 4/5 (1 addressed, 1 open - <one-liner>; commits <a7>..<b7>; escalated <old-agent> -> <new-agent>)
```

Do not write a separate escalation line. Superpowers' crash recovery reads a
task's *last* ledger line and treats a task whose last line is a fix round as
mid-loop, to be resumed at the next round. Any line of your own that lands after
a fix-round line hides it, and a controller resuming after compaction reads the
task as never started, then re-dispatches work that is already done. Folding the
clause in keeps a fix-round line last at every moment, so the task recovers
exactly as it would under vanilla superpowers — including a crash partway
through round 4, where the last line is still `fix round 3/5` and the loop
resumes at round 4. The escalated agent does not need its own line to survive a
crash: the ladder is deterministic, so the round number and the original
assignment re-derive it.

A BLOCKED-handler escalation has no fix-round line to extend, because it happens
outside the fix loop. Superpowers records nothing there either, so record
nothing: re-dispatch on the successor and let the next line the loop writes
carry the state.

The ladder's top rung is `impl-opus-high`, whose successor is `SPLIT` - an
action, not an agent. When it is exhausted, do not report BLOCKED yet: break the
task's remaining work into smaller tasks, score each against Rule S, and
dispatch them fresh. Record it as a ruling in the ledger:

```
Ruling: split Task <N> at the top rung into <N>a and <N>b - impl-opus-high exhausted after 5 rounds - if wrong, the halves review separately and merge back
```

This `Ruling:` line is exempt from the last-line rule above, because it is not a
`Task <N>:` line. Superpowers writes its own `Ruling:` lines in the same
position after the cap, so crash recovery already steps over them when it looks
for a task's last `Task <N>:` verb.

**A task may be split-escalated once.** If a split half also exhausts
`impl-opus-high`, the task has resisted both capability and decomposition, and
only then does it enter the reserve chain in
[`../../reference/ladder.md`](../../reference/ladder.md). It enters at
`impl-opus-xhigh` and walks one successor per further exhaustion. Record the
entry as its own ruling, and say it aloud:

```
Ruling: Task <N>a enters the reserve at impl-opus-xhigh - impl-opus-high exhausted again after the split - if wrong, the task is BLOCKED instead and waits for a human
```

A reserve dispatch is the one place this loop spends above the tier the plan
recorded. It should never be a surprise, which is why it is said aloud as well
as written down. Like the split ruling above it, this line is exempt from the
last-line rule, because it is not a `Task <N>:` line.

`impl-fable-max` has no successor. When it exhausts, report BLOCKED through
superpowers' existing contract. Do not loop, and do not split a second time.

## Score the review

superpowers dispatches a task reviewer. Dispatch `judge-fable` for that seat
instead of a general-purpose agent, and hand it the criteria file alongside the
inputs superpowers already specifies.

**If Fable is unavailable on this account, or your human partner has said not to
use it, dispatch `judge-opus` instead and say so.** Never substitute silently.

**Prompt order matters.** Put the invariant material first - the brief path, the
report path, the diff path, and superpowers' process rules - and the criteria
block last. On the K=3 path below, the three prompts then share a long identical
prefix, which is the only reason the ordering is specified.

Append to superpowers' task-reviewer prompt:

```
## Criteria

Read the criteria file at [PLUGIN_ROOT]/criteria/task-review.md and score each
criterion independently on a 1 to 20 scale, where 1 is a clear failure, 10 is
genuinely uncertain, and 20 is clearly met.

Add this block to the end of your report, after the Assessment section:

### Verification Scores
- spec: <1-20>
- verification: <1-20>
- quality: <1-20>

Score against those criteria and nothing else. Where a criterion tells you to
ignore something, ignoring it is part of scoring correctly.
```

Expand `[PLUGIN_ROOT]` to this plugin's directory before sending the prompt. A
judge handed the literal token cannot open the file. The hook uses
`${CLAUDE_PLUGIN_ROOT}` for the same value; in a dispatch prompt you write the
resolved path.

**The scores are additive.** superpowers' fix loop triggers on its spec-failure
verdict, on Critical findings, and on Important findings. Keep every one of
those; the scores ride alongside and never replace them. A judge that returns
scores but drops the verdicts has produced an unusable review - re-dispatch it.

Read the scores as bands: **1-8 fails** and joins the fix-loop trigger; **9-13**
is borderline, recorded and adjudicated by you; **14-20 passes**.

Record the scores by extending superpowers' own completion line, whether one
judge scored the task or three:

```
Task <N>: complete (commits <base7>..<head7>, review clean; scores spec 17 / verification 15 / quality 16)
```

Never author a separate scores line. Superpowers keys crash recovery off
`Task <N>: complete`, and a line landing after it hides it.

### Repeated evaluation on risk-3 tasks

When the task's `**Evaluation:**` line scored **risk 3**, dispatch three judges
independently on the same inputs and average each criterion. Risk is the one
axis Rule S cannot reduce, so it is the one place worth paying three times.

**Disagreement is the signal, not the mean.** If the three scores for any
criterion spread by more than 6 points, read the diff yourself rather than
trusting the average. A wide spread means the criterion failed to discriminate
on this diff, which is a fact about the review, not about the code.

**One of the three seats is Codex**, when it is usable. Risk-3 tasks are excluded
from the executor lane by `max_risk 1` in the `gate` block of
[`../../reference/ladder.md`](../../reference/ladder.md), so this seat never
reviews Codex's own work - a property the final whole-branch review below does
not share. Establish usability the way this skill already does - run
`bash "${CLAUDE_PLUGIN_ROOT}/scripts/detect-executors.sh"` and read the `usable`
field for `codex`; never trust the plan's copy.

Run it as a background Bash call, for the reason Dispatch an external executor
gives: the Bash tool's `timeout` caps at ten minutes, this rung's
`codex-timeout` row is 1800 seconds, and a background call is not bound by
`timeout` at all.

**This seat needs its own bound, unlike the task wrapper.** It calls `codex`
directly, so there is no wrapper poll loop to kill a run that never returns.
Wrap it in coreutils `timeout` at the rung's value. The task wrapper avoids
`timeout` deliberately - a process between it and node breaks `taskkill`'s tree
walk - but that reasoning is about killing a *writing* Codex cleanly before a
commit. This seat is `-s read-only` and commits nothing, so a blunt kill costs
nothing but the round.

```bash
timeout 1800 codex exec -s read-only -m gpt-5.6-sol -c model_reasoning_effort=high \
  --output-schema <schema-path> -o <workspace>/task-<N>-review-codex.json \
  -C <worktree-root> < <prompt-file>
```

A `timeout` exit of 124 is a seat that produced no score. Fall back to the third
Claude judge below rather than averaging two scores as if three had voted.

Use `codex exec`, not `codex exec review`: the latter imposes its own report
shape, and this seat must return the criteria the other two judges return. The
prompt is superpowers' task-reviewer prompt with the criteria block from Score
the review appended, with one change. **For this seat the criteria block's
output-format paragraph is replaced by the schema, not appended to it.** The
schema carries the same three criterion names and the same 1 to 20 range, and the
final message is JSON rather than a markdown `### Verification Scores` section.
Send the criteria themselves - where to look, what scores high, what to ignore -
and let the schema state the shape. Sent unedited, the prompt would order
markdown while `--output-schema` forbids it.

**This plugin ships no criteria schema.** `scripts/codex-report-schema.json` is
the implementer report's shape, not this one. Write the criteria schema before
the run - one integer 1 to 20 for each of `spec`, `verification`, and `quality`,
alongside superpowers' own verdicts - and write it **outside the worktree**, to a
temporary path. Reports live in the workspace because superpowers' `.gitignore`
entry covers that directory, but this skill already names host repositories where
it does not, and a schema is a throwaway input rather than an artefact worth that
bet: untracked inside the worktree, it is one `git add -A` from landing in the
next executor-lane task's commit.

If Codex is not usable, dispatch the third judge seat as before - `judge-fable`,
or `judge-opus` under the Fable-unavailable rule above - and say so. Average and
read the spread exactly as this section already specifies; a Codex seat changes
who scores, not how the scores are read.

Record the reading in the ledger line you already write:

```
Task <N>: complete (commits <base7>..<head7>, review clean; scores spec 17 / verification 15 / quality 16, K=3)
```

## Progress

Ask the re-reviewer for one extra line, and only the re-reviewer:

```
**Progress:** <1-20>
```

Answering: given everything the implementer has done so far, would the current
state already satisfy the task? Anchors match the review bands - 1 certainly
not, 10 uncertain, 20 verified complete.

**If round N's progress is less than or equal to round N-1's, escalate at the
start of the next round** rather than waiting for round 4. A fix loop whose
progress is flat or falling is not converging, and two more rounds on the same
agent buy nothing.

**Never escalate before round 3.** superpowers resumes the same implementer on
rounds 1 to 3 specifically to preserve its model, its effort, and its context.
This rule may pull the escalation point from 4 to 3; it may never pull it to 2,
and it may never delay it past 4.

Fold the reading into superpowers' own fix-round line, for the reason this skill
already gives about lines that land after a fix-round line:

```
Task <N>: fix round 3/5 (1 addressed, 1 open - stale cache; commits a7f..b21; progress 11 -> 9; escalated impl-sonnet-medium -> impl-opus-medium)
```

## Failure modes

| Situation | Response |
|-----------|----------|
| Task has no `**Implementer:**` line | Score it with the rubric in `reference/ladder.md`, dispatch, and record `Task <N>: implementer <agent> (scored at dispatch)` |
| The line names one of the nine reserve implementers | Dispatch it as written and note `reserve tier` in the ledger. No score reaches one, so it is a human ruling. `impl-opus-high` is not one of them - it is the score-6 assignment |
| The line names an agent in neither the assignment nor the reserve table | Stop and ask your human partner. Never fall back silently |
| Fable is unavailable or declined for a judge seat | Dispatch `judge-opus`, say so, and continue |
| An implementer's model is unavailable on this account | Substitute the same effort one model down, state the substitution in the ledger and to your partner, and continue. From Sonnet there is no such rung - stop and ask instead |
| Escalation exhausted at impl-opus-high | Split the remaining work once; if a half also exhausts, enter the reserve at `impl-opus-xhigh` |
| Reserve exhausted at impl-fable-max | Report BLOCKED per superpowers. There is no rung above it and no second split |
| Task has an `**Executor:**` line and the CLI is usable | Run the wrapper; do not dispatch a subagent for it |
| Task has an `**Executor:**` line and the CLI is missing, unauthenticated, or not batch-capable | Dispatch the `**Implementer:**` agent, say the substitution aloud, record the roster's `reason` in the ledger |
| The `**Executor:**` line names a model outside `codex-assignment`, an effort outside `low`/`medium`/`high`/`xhigh`/`ultra`, or a pair with no `codex-timeout` row | Stop and ask your human partner. The wrapper refuses all three with exit 2 anyway |
| Wrapper exits 2 with a `git add failed` or `commit failed` message | Codex ran and left its work staged but uncommitted, with no report and no thread id. Recover the tree first, then re-dispatch fresh or hand back |
| Wrapper exits 2 with any other message | It refused before launching Codex. A validation error, not a run failure. The plan or the table is wrong; fix it rather than retrying |
| Two Codex runs have failed | `HANDBACK` to the `**Implementer:**` agent and continue on the Claude ladder |

The silent-fallback rule matters more than it looks. If a bad agent name quietly
degraded to the session default, every task would run at the session's model and
effort and nothing in the output would reveal it. That is precisely the
expensive-model failure superpowers' Model Selection section exists to prevent.

The unavailable-model row covers Opus not being on every account. Drop the model
one rung and keep the effort the score asked for. State the substitution in the
ledger and to your partner; never substitute silently. Fable unavailability is a
different case, handled by the judge-seat row above it.

That substitution runs out below Sonnet. Haiku ships in one flavour with no
effort variants, so "same effort, one model down" has no target from a
`impl-sonnet-*` agent, and dropping to `impl-haiku` would silently discard the
effort level the score asked for. If Sonnet itself is unavailable, say so and
ask your partner rather than inventing a rung.

Inside the reserve the same substitution has a target at every effort:
`impl-fable-max` drops to `impl-opus-max`, `impl-fable-xhigh` to
`impl-opus-xhigh`, and `impl-fable-high` to `impl-opus-high`. That works for a
hand-assigned Fable tier. It does not work for a task walking the chain
automatically, which reached Fable precisely by exhausting those Opus rungs -
re-dispatching one of them would re-run an agent that already failed. When Fable
is unavailable and the reserve was entered automatically, report BLOCKED
instead and say why.

## The final whole-branch review

superpowers' final whole-branch review runs unchanged, including its own model
selection. This adds a second reviewer and a verification pass over the union of
what both of them find.

**This supersedes a written promise.** The plugin's README said, until this lane
landed, that the final whole-branch review and its model selection were
untouched. The review itself still is, but it is no longer the last word, and
that is recorded here rather than left to accrete silently.

1. **Run superpowers' review** exactly as written. Keep its findings.
2. **Run a Codex round** over the same branch, as a background Bash call:

   ```bash
   (cd <worktree-root> && timeout 1800 codex exec review --base <base-branch> \
     -m gpt-5.6-sol -c model_reasoning_effort=high \
     -o <workspace>/final-review-codex.md)
   ```

   `codex exec review` is purpose-built for this and takes no sandbox flag,
   because review is read-only by nature. It takes no `-C` either, so the working
   directory is the only way to point it at the worktree - hence the subshell.
   Bound it with coreutils `timeout`, not the Bash tool's: this is a direct
   `codex` call with no wrapper poll loop behind it, and the tool's own `timeout`
   caps at ten minutes while a whole-branch round needs more. 1800 seconds
   matches the `gpt-5.6-sol/high` row in `codex-timeout`, which is the closest
   thing to a figure for a round that block has no row for, and a whole branch is
   more to read than one task. Establish usability with the same
   `detect-executors.sh` check the risk-3 seat uses; if Codex is not usable, or
   if `timeout` returns 124, skip this round, say so, and report superpowers'
   review alone.

   Unlike the risk-3 seat, this round is **not** self-review-free. The branch
   contains whatever the executor lane produced, so Codex is reviewing some of
   its own commits. That is what the third seat in step 4 is for: every finding
   is verified by an agent that wrote none of the code, whichever reviewer
   raised it.
3. **Dedupe into one list**, tagging each finding `claude`, `codex`, or `both`.
   Two findings are the same when they name the same defect in the same place,
   not merely the same file.
4. **Verify each surviving finding** with `judge-fable` - `judge-opus` under the
   Fable-unavailable rule - in one dispatch for the whole list, returning
   `CONFIRMED` or `REJECTED` with evidence for each. The verifier is a third
   seat, so neither reviewer grades its own work.
5. **Report** confirmed findings ranked most severe first, then the rejected ones
   with the reason each was rejected. A finding both reviewers raised and the
   judge confirmed is the strongest signal available in this loop; say so.

Confirmed findings from both reviewers form one list, and that list is what
superpowers' final-review flow acts on - its single fix dispatch, its one scoped
re-review, and its adjudication of residuals, all unchanged. A confirmed finding
gates the handoff exactly as one of superpowers' own does, whichever reviewer
raised it; a rejected one never does. Nothing about the Codex round's provenance
changes a finding's weight once the third seat has confirmed it.

The handoff to superpowers:finishing-a-development-branch is unchanged.
