# The delegated task loop

One task's dispatch, review, fix loop and complete line.
dforge:subagent-driven-development runs it for every task, and
dforge:executing-plans runs it for each task whose brief carries
`**Dispatch:** delegated`: a heavy task, too large or risky to implement in the
session, and every task carrying an `**Executor:**` line, which runs on that
executor's wrapper instead of an implementer subagent.

## Contract

- **The caller holds** the plan workspace, the ledger, a brief file from
  `scripts/task-brief` (one task's, or in subagent mode a batch's), and a ruling
  seat it can dispatch, per its own The Ruling Seat section.
- **The loop writes** only lines of the shared ledger grammar
  ([subagent-driven-development](../skills/subagent-driven-development/SKILL.md)
  §The Ledger).
- **The loop returns** on the task's `complete` line or on a `BLOCKED` line. A
  budget `handoff` waits for the `complete` line.

## Seats

| Seat | Agent | Model argument |
|---|---|---|
| Implementer | The task's `**Implementer:**` agent, as `subagent_type` | None |
| External implementer | The task's `**Executor:**` line, via [executor-lane.md](executor-lane.md) | Set by the wrapper |
| Task reviewer | The seat `scripts/review-route PLAN_FILE --task <N>` prints (§3); its `fallback` when a Codex seat's status line is `TIMEOUT` or `FAILED`; say every substitution aloud. On a Codex host, a native judge at Astra high or above ([native-codex.md](native-codex.md)) | None |
| Scoped re-review | `dforge:judge-sonnet-high`; `dforge:judge-opus` for a subtle concurrency fix | None |

**Fleet agents take no `model` or `effort` argument.** The Agent tool's `model`
argument overrides the agent file's pinned model while `effort` keeps its
frontmatter value, and its `effort` argument (Claude Code 2.1.292 and later)
overrides the pinned effort while the model stays; either runs the agent at a
tier the ledger does not record.

General-purpose seats always take an explicit model:
[subagent-driven-development](../skills/subagent-driven-development/SKILL.md) §Seats.

**Turn count beats token price.** Wall-clock and context cost scale with how
many turns a subagent takes, and the cheapest models routinely take 2-3× the
turns on multi-step work. Use a mid-tier model as the floor for reviewers.

## 1. Dispatch the implementer

**Read the task's `**Executor:**` line first.** A task carrying one runs on
that CLI — follow [executor-lane.md](executor-lane.md)
§Dispatch — and the steps here are its fallback. A task without one takes
these steps directly.

**Open the task with one call:**
`bash <plugin-root>/scripts/task-step start PLAN_FILE N` (a batch passes every
task number, `N M …`; a wave task adds `--wave K`). It runs `task-brief`,
records BASE in `<workspace>/task-<N>-step.json`, writes the
assigned line (below), and writes `<workspace>/task-<N>-dispatch.md`:
[implementer-prompt.md](../skills/subagent-driven-development/references/implementer-prompt.md)
with the brief path, the report path and the plugin root filled in. It prints
at most 15 lines: the `subagent_type`, the dispatch file's path, the state it
recorded and the budget line (see the caller's Session Budget section). Every
later step reads that state file, so you never carry a SHA. Calling `start`
again for a task whose state file exists — a task resumed after a restart, a
dispatch repeated — keeps the recorded BASE, round and review head and writes
no second assigned line, so the review still packages every commit made since
the first dispatch; pass `--reset` only to discard the state and start over,
and say why on the ledger. A task with an
`**Executor:**` line prints `executor <id>: follow executor-lane.md
§Dispatch` and writes no dispatch file. Exit 3 means the plan has no such
task; exit 2 on a `Host: codex` plan sends you to *The steps by hand* below.

- **Choose the agent.** Read the task's `**Implementer:**` line. A name from
  the reserve table of [ladder.md](ladder.md) — any `xhigh` or
  `max` agent, or any Fable tier — is a human ruling: dispatch it as written
  and note `reserve tier`. See [escalation.md](../skills/subagent-driven-development/references/escalation.md).
- **Task brief:** `task-step start` extracted it to
  `<workspace>/task-<N>-brief.md` (see using-dforge §Session Budget). The
  brief stays the single source of requirements: the dispatch file tells the
  implementer to read it first, with the exact values to use verbatim, and it
  ends with the plan's Global Constraints and Contracts. Your Agent prompt
  holds only what the dispatch file cannot know: (1) one line on where this
  task fits in the project; (2) "your complete instructions are in
  `<dispatch file>`: read it first and follow it"; (3) interfaces and
  decisions from earlier tasks that the brief cannot know; (4) the
  ruling-seat verdicts in the ledger that bear on this task, copied verbatim
  (an ambiguity you notice in the brief goes to the seat as a `plan-conflict`
  item before you dispatch). Exact values (numbers, magic strings,
  signatures, test cases) appear only in the brief. Never make a subagent
  read the whole plan file. A brief whose task the seat split into
  `#### Part` units is dispatched one part at a time, in order, the prompt
  naming the part; its assigned line carries `; part <X>`.
- **Report file:** the dispatch file names it after the brief (brief
  `…/task-N-brief.md` → report `…/task-N-report.md`). The implementer writes
  the full report there and returns only status, commits, a one-line test
  summary, and concerns.
- **UI tasks:** a brief that carries `## UI/UX contract items` is a UI task
  (dforge:ui-ux). Say in the Agent prompt that the implementer renders the result
  through the project UI profile's harness before reporting, and that the
  report maps each cited ID to a screenshot path or a test name; a cited ID
  with no evidence is a spec ❌ at review.
- A dispatch prompt describes one task, not the session's history. Do not
  paste accumulated prior-task summaries ("state after Tasks 1-3") into
  later dispatches — a real session's dispatch hit 42k chars of which 99%
  was pasted history. A fresh subagent needs its brief, which already
  carries its task, the Contracts and the Global Constraints. Nothing else.
- The dispatch carries the no-subagents contract (it is in the
  implementer template): the implementer never dispatches subagents —
  not helpers, and never a reviewer. Review arrives from you, after the
  report.
- If an earlier task parked a finding in the area this task touches, carry
  a pointer to that ledger entry in the dispatch. If an earlier task's breaker
  carried a CONFIRMED-GAP to this task, the dispatch names the gap and the
  ruling's smallest unblocking change as part of this task's work, and its
  review checks that change.
- Dispatch the printed `subagent_type` with no `model` or `effort` argument
  and the prompt above. Never dispatch a `fork` implementer: it would inherit
  your whole context.
- Record the implementer's agent identity from the dispatch result — fix
  round 1 may resume it. `start` already wrote
  `Task <N>: implementer <agent> (assigned; base <sha7>)`, ending
  `; wave <k>)` for a wave task. When what you dispatch differs from that
  line, or needs a note it cannot know — an agent scored at dispatch, a
  substitute for an unavailable model, a reserve tier, a `#### Part` — append
  a new assigned line for it with the note (`; scored at dispatch`,
  `; reserve tier`, `; part <X>`), as an escalation does: the last assigned
  line decides.
- Never dispatch multiple implementation subagents in parallel (conflicts),
  except the tasks of one parallel wave, each in its own worktree
  ([parallel-waves.md](parallel-waves.md)).

**Dispatch problems are rulings.** Each is said aloud and logged as a
`Ruling:` line; none falls back silently and none stops the run:

| Problem | Ruling |
|---|---|
| No `**Implementer:**` line | Score the task with the rubric in [ladder.md](ladder.md), dispatch that agent, and note `scored at dispatch` on the assigned line |
| A name in none of [ladder.md](ladder.md)'s assignment, escalation or reserve tables (`impl-haiku`, `impl-opus-low` and `impl-opus-medium` appear only in the escalation table, and a human `**Override:**` may pin them) | Score at dispatch and dispatch the scored agent |
| The implementer's model is unavailable on this account | Same effort one model down; where none exists, the ladder successor — see [escalation.md](../skills/subagent-driven-development/references/escalation.md) |
| Fable unavailable inside a reserve chain entered automatically | `Task <N>: BLOCKED` with the reason — the Opus rungs below it already failed |
| An `**Executor:**` line the wrapper cannot run | `HANDBACK` to the `**Implementer:**` agent — see [executor-lane.md](executor-lane.md) §Failure rows |

## 2. Handle the report

Implementer subagents report one of four statuses, or none. Handle each appropriately:

**DONE:** In subagent mode, hold the task first:
`bash <plugin-root>/scripts/task-step hold PLAN_FILE N` (a wave task adds
`--head <task ref>`). Exit 0 holds the task for its group review (§3a) and
writes its `awaiting group review` line; exit 4 means the task is reviewed alone: review it (step 3). Inline mode never holds a task: it reviews every
task it delegates alone, including an `**Executor:**` task that
`review-route` grades `review=group`, so it goes straight to step 3, as a
batch does. `task-step review` packages the
diff and records `t0`, the time the cache rule in step 4 needs.

**DONE_WITH_CONCERNS:** The implementer completed the work but flagged doubts. Read the concerns before proceeding. If the concerns are about correctness or scope, pass them to the task reviewer with its other inputs; the review loop decides them. If they're observations (e.g., "this file is getting large"), note them and proceed to review.

**NEEDS_CONTEXT:** The implementer needs information that wasn't provided.
If the answer is mechanical - a path, a name, a value that the header, an
earlier task's report or the ledger already holds - supply it and re-dispatch
the same agent, and log `Task <N>: Ruling: supplied <what> — <where it came
from> — none`. Anything else is a question about what the plan means: send it
to the ruling seat as a `blocked-plan` item and re-dispatch with the verdict.
You never answer a requirements question from your own reading of one brief.

**BLOCKED:** The implementer cannot complete the task. Assess the blocker:
1. If it's a context problem, provide more context and re-dispatch the same agent
2. If the task requires more reasoning, re-dispatch on the successor rung and write a new assigned line — see [escalation.md](../skills/subagent-driven-development/references/escalation.md)
3. If the task is too large, send a `blocked-plan` item; a split is the seat's CONFIRMED-GAP naming it, logged as a `Ruling:` line
4. If the plan itself is wrong, send a `blocked-plan` item to the ruling seat and carry out its verdict; an AMEND re-dispatches from a fresh brief

**A grouped task that does not report a plain DONE:** a task `review-route`
grades `review=group` that reports BLOCKED, NEEDS_CONTEXT, or
DONE_WITH_CONCERNS with a correctness or scope concern leaves the group and is reviewed alone (step 3), even when it later reports DONE. The group reviews
once its remaining members are held.

**Still listed after its report:** on Claude Code, an implementer that left a
shell or agent of its own running stays listed after it reports, whatever its
status, and its notification says it "stopped with background work of its own
still running". Once you have acted on the report, stop it with `TaskStop`
(its report stands) so nothing it left keeps running into a handoff or the
finishing menu. `scripts/in-flight` lists any you missed.

**No status line:** the reply carries no `**Status:**` line, usually because
the implementer ended its turn on a progress note that announces a next step
instead of taking it. A reply without a status is not DONE, whatever it says
was finished. If the report file carries a status, act on that one. Otherwise,
while your harness can send another message to the live agent and its id is
still in your context, send it one message naming what is still open - the
brief's unfinished steps and whatever the reply said comes next - telling it to
continue, or to report BLOCKED with what blocks it; say the continuation aloud.
If the reply says a command or subagent it started is still running, let that
finish first: wait as subagent-driven-development's Waiting on dispatched
subagents says (on Claude Code, end the turn; on Codex, bounded `wait_agent`
stretches), and stop it with `TaskStop` if it outlives the rung's bound.
After two continuations with no status, handle the task as
BLOCKED with the reason `no report after two continuations`. When you cannot
message the agent, dispatch the same agent fresh with the brief path, the
report-file path and `git log <base>..HEAD` as what the earlier run committed.

**Never** ignore an escalation or force the same model to retry without changes. If the implementer said it's stuck, something needs to change.

## 3. Review the task

Per-task reviews are task-scoped gates. The broad review happens once, at the
final whole-branch review. Never skip the task review, and never accept a
report missing either verdict — spec compliance AND task quality are both
required. Implementer self-review never replaces the task review; both are
needed.

- **One call does the plumbing:**
  `bash <plugin-root>/scripts/task-step review PLAN_FILE N` (all of a batch's
  task numbers for a batch; a wave task adds `--head <task ref>` and
  `--cwd <worktree>`, see [parallel-waves.md](parallel-waves.md)). It packages the diff from the base
  `start` recorded to HEAD — never `HEAD~1`, which silently truncates
  multi-commit tasks — and records the review head and `t0`. It runs
  `scripts/codex-gate`, `scripts/review-route PLAN_FILE --task <N>` and
  `scripts/lens-route PLAN_FILE --task <N>`, and writes
  `<workspace>/task-<N>-review-prompt.md`:
  [task-reviewer-prompt.md](../skills/subagent-driven-development/references/task-reviewer-prompt.md)
  with every placeholder filled in, the diff file, the plugin directory and
  each lens's `criteria=` path among them (a task with no lens has no lens
  section). It runs the mechanical checks below, and for a Codex seat also
  writes the Codex prompt. It prints at most 15 lines: the seat and its prompt
  file, for a Codex seat the runner command and its timeout, the check lines,
  the state it recorded and the budget line. The diff never enters your own
  context, and a reviewer is never dispatched without it.
- **The seat:** dispatch the `seat:` line's `subagent_type`, with no `model`
  or `effort` argument, and the prompt "your complete instructions are in
  `<prompt file>`: read it first and follow it". When a judge seat returns,
  run `bash <plugin-root>/scripts/task-step verdict PLAN_FILE N` with the
  review's task numbers, and act on its digest.
  Never Read the report file yourself: the digest carries the verdicts, the
  scores, one line per Critical or Important finding and the cannot-verify
  items, and verdict has already written the fix file and logged the Minor
  findings. A `codex:light` seat that reviewed writes no report: read its JSON
  as Codex seats below says. A Codex seat's line names
  both prompt files, `seat: codex:light prompt: <Codex prompt> fallback:
  <judge> prompt: <judge prompt>` or `seat: codex:heavy+judge-opus prompt:
  <Codex prompt> then: dforge:judge-opus prompt: <judge prompt>`: run the
  Codex seat as below, with the judge after `fallback:` as the seat when it
  fails and the judge after `then:` as the risk 3 second pass. Both judge
  prompts are already written, so you never run `review-route` again for
  them. Run `scripts/codex-gate --refresh` before `task-step review` when
  Codex may have come back since an earlier off answer, such as after a
  login, because an off answer is kept for the session. A `gate:` line right
  after the digest's first line carries the gate's answer when the route was
  `reason=codex-off` or the gate answered `source=probe`; say it aloud when
  it ends `source=probe`. A task without an `**Executor:**` line
  whose `seat:` line names a judge was routed with `reason=codex-off`: the
  review surface is off for this session, no Codex seat runs, and the seat
  clause records `(codex off — <reason>)` with the `reason` on the `gate:`
  line (`untrusted` when it printed `usable=true`). When the `seat:` line
  ends `(review-route exited <N>: …)`, `review-route` failed but
  `task-step review` still wrote the complete judge prompt: dispatch the
  `dforge:judge-opus` seat it names as printed, and say why, quoting that
  note. If `task-step review` itself exits 2 (a `lens-route` failure, a bad
  `--base`, `--head` or `--cwd`, or an unexpanded placeholder), it printed
  no digest and left its state file unchanged; any prompt file it left is
  stale: take *The steps by hand*.
  Codex hosts are the exception: `review-route --task` exits 2 on every `Host: codex`
  plan, and the seat is a native judge at Astra high or above
  ([native-codex.md](native-codex.md)).
- **Lenses:** the prompt file already carries each `lens-route` line's
  `criteria=` path. A Codex seat gets no lens files: on a risk-3 task the
  Claude judge beside it reads them. On a `Host: codex` plan `lens-route`
  exits 2; choose the lenses as [native-codex.md](native-codex.md) says.
- **Reviewer inputs:** the brief file (it ends with the plan's Global
  Constraints and Contracts — the reviewer's attention lens), the
  implementer's report file, and the diff file, all named in the prompt file. Never tell the
  reviewer which lane produced the diff: a judge that knows the author scores
  the author.
- Do not add open-ended directives like "check all uses" or "run race tests
  if useful" without a concrete, task-specific reason
- Do not ask a reviewer to re-run tests the implementer already ran on the
  same code — the implementer's report carries the test evidence
- Do not pre-judge findings for the reviewer — never instruct a reviewer to
  ignore or not flag a specific issue. If you believe a finding would be a
  false positive, let the reviewer raise it; the review loop and, at the
  cap, the ruling seat decide it. If the prompt you are writing contains "do not flag," "don't treat X
  as a defect," "at most Minor," or "the plan chose" — stop: you are
  pre-judging, usually to spare yourself a review loop.

**Scores are additive.** The verdict digest carries the spec and quality
verdicts and the four scores — spec, scope, verification, quality — each 1 to 20 against
[task-review.md](../criteria/task-review.md). Read them as bands: **1-8
fails** and joins the fix-loop trigger; **9-13** is borderline, recorded on
the complete line for the final review to triage, never settled by you;
**14-20 passes**. The verdicts still drive the loop; a report that drops a
verdict line is malformed: `task-step verdict` exits 5 on it (When
`task-step verdict` fails).

**Mechanical checks.** `task-step review` also checks the commits from the
base to the review head and prints `check identity:` and `check attribution:`
lines, each `clean` or the short SHA and what it found: an author or committer
that differs from `git config user.name` and `user.email`, or a
`Co-Authored-By:` or `Claude-Session:` trailer, or a line beginning
`Generated with`. A check that
found something is a finding for the fix loop. A reviewer's cannot-verify item
that a `clean` line answers is settled without a seat (subagent-driven-development,
The Ruling Seat).

**When `task-step verdict` fails.** Exit 5 means the seat wrote no report,
or one outside the grammar, and stderr says which; exit 6 means a tracked
file in the reviewed checkout changed during the review, or HEAD moved, and
stderr names the files and the checkout. The review saw the committed
state, so on exit 6 restore it with
`git -C <dir> checkout -- <files>`.
Then, either way, log `Task <N>: Ruling: review seat <seat> <wrote no
report | wrote a malformed report | changed <files>> —
restored the committed state and re-dispatched once
— none`, delete the report file, and re-dispatch the same seat once with the
same prompt file.
A second failure dispatches the route's fallback judge:
the judge after `fallback:` on the `seat:` line when it names one, otherwise
`dforge:judge-opus`, a fresh dispatch even when the failed seat was
judge-opus; say so. A third failure is `Task <N>: BLOCKED — review seat —
no usable report after three dispatches`. Exit 6 with
`run task-step review … first` means the review step never ran: run it.

**Codex seats.** `task-step review` wrote the task-reviewer prompt for Codex,
as [executor-lane.md](executor-lane.md) §Codex task review
seats describes, to `<workspace>/task-<N>-review-codex-prompt.md`, and printed
the runner command and its `timeout` (the command's `--cwd` is your checkout's
top level, or the `--cwd DIR` you passed to `task-step review`). Run that
command as a background Bash
call with `timeout` = (row bound + 120) × 1000 ms: 2520000
for `--tier light`, 5520000 for `--tier heavy`; its shape is:

```bash
bash "<plugin-root>/scripts/run-codex-review.sh" --kind task --tier <light|heavy> \
  --cwd <worktree-root> --out <workspace>/task-<N>-review-codex.json \
  --prompt <workspace>/task-<N>-review-codex-prompt.md
```

`codex:light` is `--tier light`; `codex:heavy+judge-opus` is `--tier heavy`. Read the runner's status line and take its word: `OK` and
`FALLBACK` are a seat that reviewed — on `FALLBACK`, or a `--tier heavy` line
naming `gpt-6.1-sol/xhigh` with `status=OK`, say the substitution aloud — and
`TIMEOUT or FAILED` is a seat that did not: dispatch the route's `fallback`
seat (the judge after `fallback:` on the `seat:` line `task-step review` printed) with the judge
prompt file, say so with the runner's reason, and
never re-dispatch the Codex seat. The runner has already applied its own one-shot
fallback, so a second attempt here would turn one refused run into two. A
`FAILED` whose reason reads `codex is off for this session` is the same case:
the runner's own gate refused, or a quota error turned Codex off for the rest of
the session, so the next task's `review-route` names Claude seats. Read a
Codex review from its JSON — `spec_verdict` (`compliant` or `issues`),
`task_quality` (`approved` or `needs_fixes`), the four scores, `findings` and
`cannot_verify` — and apply the bands, the cannot-verify route and the fix loop to it
exactly as to a judge's report.

**Risk 3.** On `primary=codex:heavy+judge-opus`, run the Codex seat
first, then dispatch `dforge:judge-opus` with the judge prompt file, whose
Second Pass section already names the Codex seat's `--out` path. The task's
verdicts and scores are the judge's. Its findings,
plus every Codex finding it marks CONFIRMED, drive the fix loop; each CONFIRMED
cannot-verify item goes to the ruling seat as a `cannot-verify` item.
A report whose `## Codex findings` section is not its last formed its own
review after reading Codex's; `task-step verdict` exits 5 on it. If the Codex seat produced nothing, dispatch the judge with the
same prompt file and one added line, "No Codex review file exists: skip the
Second Pass section", and say so. This replaces the three-seat average earlier
versions used for risk 3.

The digest's `cannot-verify:` lines are requirements
that live in unchanged code or span tasks. These do not block the rest of the
review, but each goes to the ruling seat as a `cannot-verify` item before
the task completes, unless a mechanical check settles it: the seat holds
the plan and cross-task context the reviewer lacks. A CONFIRMED-GAP is a
failed spec review — it enters the fix loop with the other findings.

## 3a. Review a group

A task held in §2 is reviewed with other held tasks in one judge dispatch. In
sequential mode held tasks accumulate, and the group review runs
when 4 tasks are held, before you dispatch a task `review-route` reviews alone, and after the plan's last task.
Run `review-route PLAN_FILE --task <next>` to read the next task's tier before
dispatching it. A parallel wave reviews its grouped tasks as
[parallel-waves.md](parallel-waves.md) §3 says. Once the group review is
triggered, no new task is dispatched until the group is clean, and
fixes inside a group run one task at a time.

- **One call does the plumbing:**
  `bash <plugin-root>/scripts/task-step review --group PLAN_FILE N M …`,
  naming every held task. It packages each member's diff from its base to its
  held head, one section per task, writes the prompt from
  [group-reviewer-prompt.md](../skills/subagent-driven-development/references/group-reviewer-prompt.md),
  runs the mechanical checks for every member, and prints the `seat:` line,
  the check lines, the state it recorded and the budget line. Dispatch the
  `seat:` line's judge as §3 says for a judge, with the prompt "your complete
  instructions are in `<prompt file>`: read it first and follow it". When the
  group's seat returns, run
  `bash <plugin-root>/scripts/task-step verdict PLAN_FILE N M … --group`
  with every member's number and act on its digest: it reads
  `group-<list>-review-report.md`, writes one fix file per member with a
  Critical or Important finding, and logs each member's Minor findings. A
  member's fix round is read alone with
  `task-step verdict PLAN_FILE N --rereview <R>`. A group never gets a Codex
  seat.
- **The report** holds one block per task. Apply §3's verdicts, score bands,
  cannot-verify route and plan-conflict route to each task on its own, and §4's Minor
  rule (`Task <N>: minor (deferred): …`).
- **Fix rounds.** A member with findings enters §4's fix loop with the fix
  message `<workspace>/task-<N>-fix-<R>.md`, and is re-reviewed with
  `bash <plugin-root>/scripts/task-step rereview PLAN_FILE N` and no `--base`:
  `review --group` recorded the group head as its review head, and
  each member's re-review moves that head on, so a fix diff holds only that
  member's fix. A group runs at most two fix rounds. After each round append
  the group line (subagent-driven-development §The Ledger): one clause per
  member, and in its `commits` clause one `<a7>..<b7> (Task <N>)` range per
  member fixed in that round, in sequential and wave mode alike. Findings
  still open after round 2 go to the breaker as §4 says. Members write no
  `Task <N>: fix round` lines: the `Group` line is their round record. A group
  with a round line is never reviewed again: `review --group` refuses its
  members (exit 4), and its later rounds are member re-reviews.
- **Completion:** each member gets its own `complete` line once the group is clean, or once the breaker has ruled on its open findings (§5).

## 4. The fix loop

The loop triggers when the digest shows `spec: fail`, any Critical or Important
finding line, any score of 1-8, or a cannot-verify item the ruling seat confirmed as a gap.

Before the loop starts, two routes leave it immediately:

- `task-step verdict` records Minor findings in the progress ledger
  (`Task <N>: minor (deferred): <file>:<line> — <one-liner>`); point the final
  whole-branch review at that list so it can triage which must be fixed
  before merge. A roll-up nobody reads is a silent discard. Minor findings
  never enter the loop.
- A finding labeled plan-mandated (its digest line's one-liner begins
  `plan-mandated:`) — or any finding that conflicts with
  what the plan's text requires — goes to the ruling seat as a
  `plan-conflict` item before you act on it; delete its bullet from the fix
  file before the fix dispatch. Do not dismiss the finding
  because the plan mandates it, and do not dispatch a fix that contradicts
  the plan without the seat's verdict in the ledger.

Everything else enters the loop. A fix round is one fix dispatch plus one
scoped re-review. Two rounds at most per task:

**Round 1 — resume or re-dispatch by cache state.** Resuming keeps the
implementer's context, but a cold resume re-writes that whole context into the
cache. Resume only when all of these hold:

- your harness can send another message to the live agent, and its agent id is
  still in your context (compaction loses it — then the answer is always fresh);
- and either `t1 − t0 < 300` seconds, or the implementer's context is under
  about 100k tokens.

`t0` is the one on the latest `state:` line a `task-step` digest printed; `t1`
is `date +%s` from a dedicated Bash call immediately before you decide.
The context figure is the token total the Agent tool reported when the
implementer finished; if no such figure was reported, the time test decides
alone. Otherwise dispatch a fresh copy of the same agent carrying the brief
path, the report-file path, and the findings — the report file is the
persistent memory either way — and note `fresh (<why>)` on the fix-round line.
That is not an escalation.
A task on an external executor resumes that executor's own session instead
— see [executor-lane.md](executor-lane.md) §Resuming an executor task.

**Round 2 — a fresh dispatch on the successor rung.** Dispatch a fresh
implementer on the successor rung from [ladder.md](ladder.md)'s escalation
table, with the brief path, the report-file path, the open findings, and this
framing: "A prior implementer attempted this task [N] times; you own it now.
Read the report file for what was tried." A finding round 1 did not close
usually means the implementer cannot see its own problem — fresh eyes and a
capability bump in one move.
When the successor is `SPLIT`, round 2 is a fresh dispatch of the same rung (`impl-opus-high`):
a split is reached only through the breaker's AMEND (below).
A reserve-tier task takes its reserve successor from ladder.md's reserve
table; `impl-fable-max`, whose successor is `BLOCKED`, writes
`Task <N>: BLOCKED — impl-fable-max exhausted — <what a human must decide>`
instead of a round 2. An external task's round 2 is a `HANDBACK` to its
`**Implementer:**` agent ([executor-lane.md](executor-lane.md)).

**Split and reserve.** A split follows a tripped breaker: a finding still
open after round 2 on `impl-opus-high` goes to the breaker, whose AMEND may
rewrite the task's body into `#### Part A` / `#### Part B` units under the
same number, which you apply with `scripts/plan-amend` and dispatch in order,
one part per dispatch. A task is split once: a part on `impl-opus-high` takes
its reserve successor `impl-opus-xhigh` at round 2, said aloud. Both splits
and reserve entries are `Ruling:` lines. The details are in
[escalation.md](../skills/subagent-driven-development/references/escalation.md).
On a Codex host the rungs are not these: escalation, the single split and the
reserve chain all come from the `codex-v4` selector
([native-codex.md](native-codex.md) §Selector contract), which the caller runs
through `scripts/select-native-tier.sh`. A Codex host keeps its five-round cap (`review_cap: 5`) from [codex-routing.json](codex-routing.json).

On a `Host: codex` plan the loop keeps five rounds: rounds 1-3 resume the recorded implementer by Round 1's cache rule, rounds 4 and 5 are fresh dispatches of the pair the selector returns for an `escalate` request, the Codex ledger line is `Task <N>: fix round <R>/5 (…)` with the fields above, and the breaker trips when round 5's re-review still leaves findings open; neither host reads a progress reading.

**Every round, either way:** the implementer fixes, re-runs the tests
covering the amended code, appends its fix report to the same report file,
and returns the short contract. Before re-dispatching the reviewer, confirm
the fix report contains the covering tests, the command run, and the
output; dispatch the re-review once all three are present. Name the
covering test files in the fix message — a one-line fix does not need the
whole suite.

**The fix message** is the file `<workspace>/task-<N>-fix-<R>.md`, `R` being
the round you are starting (1 for the first). Its first lines are one bullet
per open finding, `- <file>: <finding one-liner>`, then a blank line, then
what the implementer needs: the finding's detail, the ruling's smallest fix,
the covering test files. Send the implementer, resumed or fresh, the file's
path rather than its text.
`task-step verdict` writes its bullets from the report, each `<file>`
carrying the finding's `:<line>`, with the severity lines after the blank
line; append the ruling's smallest fix and the covering test files below
them. Write the file yourself only for findings no report holds: a
mechanical check's finding, a CONFIRMED-GAP from the ruling seat, or a
Codex seat's JSON review. `task-step rereview` reads the bullets for the
findings list and the skip rule, so write the file before you call it.

**The re-review is scoped.** Run
`bash <plugin-root>/scripts/task-step rereview PLAN_FILE N` (with `--covered`
under the skip rule below). It packages the fix diff from the review head it
recorded last to HEAD, records the new review head, adds one to the
recorded round, and writes
`<workspace>/task-<N>-rereview-<R>-prompt.md`:
[re-review-prompt.md](../skills/subagent-driven-development/references/re-review-prompt.md)
with the findings from your fix message, the brief, the report file and the
diff path filled in. It prints the seat and that file; dispatch the seat with
the prompt "your complete instructions are in `<prompt file>`: read it first
and follow it". It prints `dforge:judge-sonnet-high`; for a subtle
concurrency fix dispatch `dforge:judge-opus` with the same file and say so.
When the seat returns, run
`bash <plugin-root>/scripts/task-step verdict PLAN_FILE N --rereview <R>`.
Its `fix round:` line says whether the round closed; its finding lines are
every finding still open, new breakage in the fix diff included, and it has
written them to the next round's fix file. The re-reviewer's out-of-scope
issues reach the ledger as deferred Minor findings and never extend the loop.

**The skip rule.** Pass `--covered` only after confirming that the fix report
names the covering tests, the command and passing output. With it,
`rereview` skips the re-review when exactly one finding is open, the fix
changes at most 3 lines (added plus deleted, test files included) and touches
that finding's file, and the task is not risk 3. It prints
`re-review: skipped (<n> changed lines, 1 finding, <file>)` and writes no
prompt: count the finding addressed, dispatch no seat, and write the fix-round
line with `re-review skipped (<n> lines)`. A skipped re-review still counts
as its round. Without `--covered`, or in any other case, the re-review runs.

**After each round,** append to the ledger:
`Task <N>: fix round <R>/2 (<X> addressed, <Y> open — <finding one-liners>; commits <a7>..<b7>[; re-review skipped (<n> lines)]; resumed | fresh (<why>) | escalated <old> -> <new> | HANDBACK to <agent>)`

Never fix findings yourself in the controller session — your context stays
clean for coordination, and controller fixes skip review.

**The breaker.** When round 2's re-review still leaves findings open, stop
dispatching and send every open finding to the ruling seat in one `breaker`
dispatch. The seat parks a finding that is wrong, contestable, or real but
built on by nothing downstream; returns CONFIRMED-GAP with the smallest
unblocking change for one a later task builds on; AMEND for a plan defect;
and BLOCKED when every path forward is a guess. Carry out each verdict (see
the caller's The Ruling Seat section). Parking a structural failure silently lets every dependent
task build on it, which is why the seat, not you, decides.

Send findings to the breaker only at the cap. Ending a loop earlier is
pre-judging with a different name. Every verdict is a ledger entry — a silent
discard is forbidden.

## 5. Complete the task

When the review comes back clean — or every open finding is parked, or
confirmed and carried into a later task, with a ruling at the cap — append the
completion line to the ledger in the same message as your other bookkeeping.
A confirmed gap goes to the next task that depends on this one; with none, to
the next task in plan order; after the last task, to the final review, written
`carried to final review`, where it is a confirmed finding:

- `Task <N>: complete (commits <base7>..<head7>, review clean; scores spec 17 / scope 18 / verification 15 / quality 16, seat <seat>) — done: …; verified: …; remaining: none; discovered: …; assumptions: …`
- `Task <N>: complete (commits <base7>..<head7>, <K> parked, <C> carried to Task <M>; scores …, seat <seat>) — …; remaining: <parked and carried one-liners>; …` after a tripped breaker; drop the `carried` clause when nothing was
- end the scores clause with `, seat <seat>`: `codex gpt-6.1-sol/xhigh`,
  `codex gpt-6-astra/xhigh+judge-opus`, or the judge's short name, followed by
  ` (codex <STATUS> — <reason>)` when it replaced a Codex seat, or by
  ` (codex off — <reason>)` when §3's `gate:` and `seat:` lines say Codex is off
- a group member's complete line (§3a) takes its `commits` range from its
  `awaiting group review` line and ends its scores clause
  `, seat <judge> (group <list>)`

In an auto run, run `scripts/auto-run task-complete`, then the Fable batch when
`scripts/auto-run decision list` prints anything.

**Release the worktree when the task is complete.** A task that ran on an
external executor and reached a reviewed complete line no longer owns its
worktree:

```bash
bash "$(bash "<plugin-root>/scripts/executors" path <id> wrapper)" \
  --cwd <worktree-root> --task-id <stable-task-id> --release
```

`<id>` is the first token of the task's `**Executor:**` line.
`scripts/lib/task-state.sh` keeps an `owner.json` per worktree and refuses a
different task id in it, so an unreleased worktree fails the next offload's
preflight. An inline plan offloads several tasks into one worktree in
sequence, which makes this the ordinary case rather than a recovery step.

**After a `HANDBACK`, reconcile rather than release.** The Claude implementer
inherits the worktree, its commits and its report, so ownership passes to a
task that is still in flight. Follow
[external-task-recovery.md](external-task-recovery.md) before the
implementer is dispatched; a bare `--release` there would drop the record the
recovery procedure reads. Once that implementer's task reaches its reviewed
complete line with a clean worktree, release the handed-back task with the
same `--release` command, or every later offload into that worktree fails
preflight.

Then mark the todo complete and move on. Never move to the next task while
the review has open Critical/Important issues that are neither fixed nor
parked or carried with a ruling at the cap.

## The steps by hand

`task-step` exits 2 on a `Host: codex` plan, and `task-step review` exits 2,
writing nothing, when `lens-route` does. Then run the mechanics yourself:

- **§1.** Record BASE (`git rev-parse HEAD`) before dispatching. Run
  `scripts/task-brief PLAN_FILE N` (see using-dforge §Session Budget): it
  prints `wrote <path>: <N> lines`, then the budget line; read the path out of
  the first line and never pipe the output into a prompt as if it were a
  filename. Dispatch with
  [implementer-prompt.md](../skills/subagent-driven-development/references/implementer-prompt.md),
  its placeholders filled in, the brief path introduced as "read this first —
  it is your requirements, with the exact values to use verbatim, and it ends
  with the plan's Global Constraints and Contracts" and the report-file path
  named after the brief. Write the assigned line
  `Task <N>: implementer <agent> (assigned; base <sha7>)`.
- **§3.** Run `scripts/review-package PLAN_FILE BASE HEAD` (or, without bash:
  `git log --oneline`, `git diff --stat` and `git diff -U10` for the range,
  redirected to one uniquely named file) and pass the reviewer the path it
  prints; run `date +%s` in the same Bash call and keep the value as `t0`. Fill
  [task-reviewer-prompt.md](../skills/subagent-driven-development/references/task-reviewer-prompt.md)
  yourself, `[PLUGIN_ROOT]` expanded to this plugin's resolved directory and
  `[LENS_FILES]` set to each `criteria=` path `scripts/lens-route PLAN_FILE --task <N>`
  prints (with none, delete that section),
  `[IMPLEMENTER_REPORT_FILE]` set to the implementer's report and `[REPORT_FILE]` to `<workspace>/task-<N>-review-report.md`.
  Check the commits' identity and
  attribution yourself, as the mechanical checks above describe.
  `task-step verdict` exits 2 on a `Host: codex` plan, so read the report's
  `## Verdict` section and its finding lines yourself and write the fix file
  from them.
- **§4.** Run `scripts/review-package PLAN_FILE FIX_BASE HEAD` where FIX_BASE
  is the head the previous review saw, with `date +%s` in the same call as the
  next round's `t0`, and fill the re-review prompt's placeholders yourself;
  its `[REPORT_FILE]` is `<workspace>/task-<N>-rereview-<R>-report.md`.

## Recovery

For a task whose last ledger line, read by the caller's Recovery rule, is:

| Last line | Action |
|---|---|
| `implementer <agent> (assigned …)`, the agent not `inline` | If the report file has a status and `git log <base>..HEAD` is non-empty, review it (§3); otherwise dispatch the same agent fresh (§1) |
| `fix round R/5` on a `Host: codex` plan | Codex: R < 5 resumes the loop at round R+1 by the five-round schedule (§4); `fix round 5/5` goes to the breaker (§4) |
| `fix round 1/2`, or `fix round 1/5` from an older run | Resume the loop at round 2 — a fresh dispatch on the successor rung (§4) |
| `fix round 2/2`, or `fix round R/5` with R >= 2 from an older run | Go to the breaker (§4) |
| `awaiting group review (commits …)` | Held: never re-dispatch its implementer. It is reviewed by the next group dispatch (§3a), which the trigger above starts |
| `review round 1/2` on a group review's `Group` line | Run round 2 (§3a) for each member whose clause is open, one member at a time — after compaction the agent ids are gone, so each is a fresh dispatch |
| `review round 2/2` on a group review's `Group` line | Send each member's open findings to the breaker (§4) |

On a Codex plan the Codex row wins; the `older run` mappings apply to a Claude plan only.
