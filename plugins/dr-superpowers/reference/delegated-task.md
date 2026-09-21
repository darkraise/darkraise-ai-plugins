# The delegated task loop

One task's dispatch, review, fix loop and complete line.
dr-superpowers:subagent-driven-development runs it for every task, and
dr-superpowers:executing-plans runs it for each task whose brief carries
`**Dispatch:** delegated`: a heavy task, too large or risky to implement in the
session, or a total-4 task in a plan where those are a third of the tasks or
fewer, delegated so it gets an independent review without putting the whole
session on Opus.

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
| Task reviewer | The seat `scripts/review-route PLAN_FILE --task <N>` prints (§3); its `fallback` when a Codex seat's status line is `TIMEOUT` or `FAILED`; `dr-superpowers:judge-opus` wherever it names `judge-fable` and Fable is unavailable or your human partner declined it — say every substitution aloud. On a Codex host, a native judge at Astra high or above ([native-codex.md](native-codex.md)) | None |
| Scoped re-review | general-purpose | Explicit, cheap-to-mid |

**Fleet agents take no `model` argument.** The Agent tool's `model` argument
overrides the agent file's pinned model while `effort` keeps its frontmatter
value, so passing one runs the agent at a tier the ledger does not record — and,
for a judge seat, silently bypasses the Fable-unavailable rule, which requires
you to say the substitution aloud.

General-purpose seats always take an explicit model:
[subagent-driven-development](../skills/subagent-driven-development/SKILL.md) §Seats.

**Turn count beats token price.** Wall-clock and context cost scale with how
many turns a subagent takes, and the cheapest models routinely take 2-3× the
turns on multi-step work. Use a mid-tier model as the floor for reviewers.

## 1. Dispatch the implementer

Record BASE (`git rev-parse HEAD`) before dispatching — the review package,
the fix-round diffs, and the assigned line need it.

**Read the task's `**Executor:**` line first.** A task carrying one runs on
that CLI — follow [executor-lane.md](executor-lane.md)
§Dispatch — and the steps here are its fallback. A task without one takes
these steps directly.

- **Choose the agent.** Read the task's `**Implementer:**` line. A name from
  the reserve table of [ladder.md](ladder.md) — any `xhigh` or
  `max` agent, or any Fable tier — is a human ruling: dispatch it as written
  and note `reserve tier`. See [escalation.md](../skills/subagent-driven-development/references/escalation.md).
- **Task brief:** run `scripts/task-brief PLAN_FILE N`
  (see using-superpowers §Session Budget) — it extracts the task's full text
  to a uniquely named file and prints `wrote <path>: <N> lines`, then the
  budget line (see the caller's Session Budget section). Read the path out of the first line; do
  not pipe the output into a prompt as if it were a filename. Compose the
  dispatch so the brief stays the single source of
  requirements. Your dispatch should contain: (1) one line on where this
  task fits in the project; (2) the brief path, introduced as "read this
  first — it is your requirements, with the exact values to use verbatim,
  and it ends with the plan's Global Constraints and Contracts";
  (3) interfaces and decisions from earlier tasks that the brief cannot
  know; (4) the ruling-seat verdicts in the ledger that bear on this task,
  copied verbatim (an ambiguity you notice in the brief goes to the seat as a
  `plan-conflict` item before you dispatch) — and, when the brief names a
  skill under an old plugin prefix, that legacy names resolve per
  `reference/legacy-names.md`; (5) the report-file
  path and report contract. Exact values (numbers, magic strings, signatures,
  test cases) appear only in the brief. Never make a subagent read the whole
  plan file. A brief whose task the seat split into `#### Part` units is
  dispatched one part at a time, in order, the dispatch naming the part;
  the assigned line carries `; part <X>`.
- **Report file:** name the implementer's report file after the brief
  (brief `…/task-N-brief.md` → report `…/task-N-report.md`) and put it in
  the dispatch prompt. The implementer writes the full report there and
  returns only status, commits, a one-line test summary, and concerns.
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
  a pointer to that ledger entry in the dispatch.
- Dispatch with the agent as `subagent_type` and no `model` argument, using
  [implementer-prompt.md](../skills/subagent-driven-development/references/implementer-prompt.md). Never dispatch a
  `fork` implementer: it would inherit your whole context.
- Record the implementer's agent identity from the dispatch result — fix
  rounds 1-3 may resume it — and write the assigned line:
  `Task <N>: implementer <agent> (assigned; base <sha7>)`.
- Never dispatch multiple implementation subagents in parallel (conflicts).

**Dispatch problems are rulings.** Each is said aloud and logged as a
`Ruling:` line; none falls back silently and none stops the run:

| Problem | Ruling |
|---|---|
| No `**Implementer:**` line | Score the task with the rubric in [ladder.md](ladder.md), dispatch that agent, and note `scored at dispatch` on the assigned line |
| A name in neither the assignment nor the reserve table, after legacy translation | Score at dispatch and dispatch the scored agent |
| The implementer's model is unavailable on this account | Same effort one model down; where none exists, the ladder successor — see [escalation.md](../skills/subagent-driven-development/references/escalation.md) |
| Fable unavailable inside a reserve chain entered automatically | `Task <N>: BLOCKED` with the reason — the Opus rungs below it already failed |
| An `**Executor:**` line the wrapper cannot run | `HANDBACK` to the `**Implementer:**` agent — see [executor-lane.md](executor-lane.md) §Failure rows |

## 2. Handle the report

Implementer subagents report one of four statuses. Handle each appropriately:

**DONE:** Generate the review package and dispatch the task reviewer (step 3).
Run `date +%s` in the same Bash call as `review-package` and keep the value as
`t0` — the cache rule in step 4 needs it.

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

**Never** ignore an escalation or force the same model to retry without changes. If the implementer said it's stuck, something needs to change.

## 3. Review the task

Per-task reviews are task-scoped gates. The broad review happens once, at the
final whole-branch review. Never skip the task review, and never accept a
report missing either verdict — spec compliance AND task quality are both
required. Implementer self-review never replaces the task review; both are
needed.

- Hand the reviewer its diff as a file: run
  `scripts/review-package PLAN_FILE BASE HEAD`
  (see using-superpowers §Session Budget), and pass the reviewer the
  file path it prints (or, without bash: `git log --oneline`, `git diff --stat`,
  and `git diff -U10` for the range, redirected to one uniquely named
  file). The output never enters your own context. Use the BASE you recorded
  before dispatching the implementer — never `HEAD~1`, which silently
  truncates multi-commit tasks. Never dispatch a task reviewer without a diff
  file.
- **The seat:** run `scripts/codex-gate` (say its line aloud when it ends
  `source=probe`; add `--refresh` when Codex may have come back since an
  earlier off answer, such as after a login, because an off answer is kept for
  the session), then `scripts/review-route PLAN_FILE --task <N>` (all of a
  batch's task numbers for a batch), and review with the `primary` it prints.
  A judge seat gets [task-reviewer-prompt.md](../skills/subagent-driven-development/references/task-reviewer-prompt.md)
  with `[PLUGIN_ROOT]` expanded to this plugin's resolved directory; a Codex
  seat is run as below. On `reason=codex-off` the review surface is off for
  this session: the `primary` is a judge, no Codex seat runs, and the seat
  clause records `(codex off — <reason>)` with the gate line's `reason`
  (`untrusted` when it printed `usable=true`). If `review-route` exits 2,
  review with `dr-superpowers:judge-opus` and say why, quoting its message.
  Codex hosts are the exception: `review-route` exits 2 on every `Host: codex`
  plan, and the seat is a native judge at Astra high or above
  ([native-codex.md](native-codex.md)).
- **Reviewer inputs:** the brief file (it ends with the plan's Global
  Constraints and Contracts — the reviewer's attention lens), the report
  file, and the review package. Never tell the reviewer which lane produced
  the diff: a judge that knows the author scores the author.
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

**Scores are additive.** The judge returns the spec and quality verdicts and
four scores — spec, scope, verification, quality — each 1 to 20 against
[task-review.md](../criteria/task-review.md). Read them as bands: **1-8
fails** and joins the fix-loop trigger; **9-13** is borderline, recorded on
the complete line for the final review to triage, never settled by you;
**14-20 passes**. The verdicts still drive the loop; a
judge that returns scores but drops the verdicts has produced an unusable
review — re-dispatch it.

**Codex seats.** Write the task-reviewer prompt for Codex as
[executor-lane.md](executor-lane.md) §Codex task review
seats describes, to `<workspace>/task-<N>-review-codex-prompt.md`, and run it
as a background Bash call with no timeout:

```bash
bash "<plugin-root>/scripts/run-codex-review.sh" --kind task --tier <light|heavy> \
  --cwd <worktree-root> --out <workspace>/task-<N>-review-codex.json \
  --prompt <workspace>/task-<N>-review-codex-prompt.md
```

`codex:light` is `--tier light`; `codex:heavy` and `codex:heavy+judge-fable` are
`--tier heavy`. Read the runner's status line and take its word: `OK` and
`FALLBACK` are a seat that reviewed — on `FALLBACK`, or a `--tier heavy` line
naming `gpt-5.6-sol/high` with `status=OK`, say the substitution aloud — and
`TIMEOUT or FAILED` is a seat that did not: dispatch the route's `fallback`
seat with the ordinary prompt, say so with the runner's reason, and
never re-dispatch the Codex seat. The runner has already applied its own one-shot
fallback, so a second attempt here would turn one refused run into two. A
`FAILED` whose reason reads `codex is off for this session` is the same case:
the runner's own gate refused, or a quota error turned Codex off for the rest of
the session, so the next task's `review-route` names Claude seats. Read a
Codex review from its JSON — `spec_verdict` (`compliant` or `issues`),
`task_quality` (`approved` or `needs_fixes`), the four scores, `findings` and
`cannot_verify` — and apply the bands, the ⚠️ route and the fix loop to it
exactly as to a judge's report.

**Risk 3.** On `primary=codex:heavy+judge-fable`, run the Codex seat
first, then dispatch `dr-superpowers:judge-fable` (`judge-opus` under the
Fable-unavailable rule) with the task-reviewer prompt and its Second Pass
section, `[CODEX_REVIEW_FILE]` set to the Codex seat's `--out` path. The task's
verdicts and scores are Fable's. Fable's findings, plus every Codex finding it
marks CONFIRMED, drive the fix loop; each CONFIRMED cannot-verify item goes to
the ruling seat as a `cannot-verify` item. A reply whose `### Codex findings`
section is not its last section formed its own review after reading Codex's:
re-dispatch it. If the Codex seat produced nothing, dispatch Fable without the
Second Pass section and say so. This replaces the three-seat average earlier
versions used for risk 3.

The task reviewer may report "⚠️ Cannot verify from diff" items — requirements
that live in unchanged code or span tasks. These do not block the rest of the
review, but each goes to the ruling seat as a `cannot-verify` item before
the task completes: the seat holds the plan and cross-task context the
reviewer lacks. A CONFIRMED-GAP is a failed spec review — it enters the fix
loop with the other findings.

## 4. The fix loop

The loop triggers when the review reports spec ❌, any Critical or Important
finding, any score of 1-8, or a ⚠️ item the ruling seat confirmed as a gap.

Before the loop starts, two routes leave it immediately:

- Record Minor findings in the progress ledger as you go
  (`Task <N>: minor (deferred): <one-liner>`), and point the final
  whole-branch review at that list so it can triage which must be fixed
  before merge. A roll-up nobody reads is a silent discard. Minor findings
  never enter the loop.
- A finding labeled plan-mandated — or any finding that conflicts with
  what the plan's text requires — goes to the ruling seat as a
  `plan-conflict` item before you act on it. Do not dismiss the finding
  because the plan mandates it, and do not dispatch a fix that contradicts
  the plan without the seat's verdict in the ledger.

Everything else enters the loop. A fix round is one fix dispatch plus one
scoped re-review. Five rounds maximum per task:

**Rounds 1-3 — resume or re-dispatch by cache state.** Resuming keeps the
implementer's context, but a cold resume re-writes that whole context into the
cache. Resume only when all of these hold:

- your harness can send another message to the live agent, and its agent id is
  still in your context (compaction loses it — then the answer is always fresh);
- and either `t1 − t0 < 300` seconds, or the implementer's context is under
  about 100k tokens.

`t1` is `date +%s` from a dedicated Bash call immediately before you decide.
The context figure is the token total the Agent tool reported when the
implementer finished; if no such figure was reported, the time test decides
alone. Otherwise dispatch a fresh copy of the same agent carrying the brief
path, the report-file path, and the findings — the report file is the
persistent memory either way — and note `fresh (<why>)` on the fix-round line.
That is not an escalation. A task on an external executor resumes its Codex
session instead — see [executor-lane.md](executor-lane.md)
§Resuming a Codex task.

**Rounds 4-5 — escalate.** Dispatch a fresh implementer on the successor rung
from [ladder.md](ladder.md)'s escalation table, with the brief
path, the report-file path, the open findings, and this framing: "A prior
implementer attempted this task [N] times; you own it now. Read the report file
for what was tried." A loop that survives three resumes usually means the
implementer cannot see its own problem — fresh eyes and a capability bump in
one move. An external task hands back to its `**Implementer:**` agent instead.

**Progress.** The re-reviewer returns `**Progress:** <1-20>`. If round N's
reading is less than or equal to round N-1's, escalate at the start of the next
round rather than waiting for round 4. Never escalate before round 3, and never
later than round 4. Record the reading on the fix-round line
(`progress 11 -> 9`).

**Split and reserve.** The top rung `impl-opus-high` escalates to `SPLIT`:
send a `blocked-plan` item; the seat's AMEND rewrites the task's body into
`#### Part A` / `#### Part B` units under the same number, which you apply
with `scripts/plan-amend` and dispatch in order, one part per dispatch. A task
is split once; a part that exhausts `impl-opus-high` again enters the reserve
at `impl-opus-xhigh`, said aloud; `impl-fable-max` exhausted is
`Task <N>: BLOCKED`. Both splits and reserve entries are `Ruling:` lines. The
details are in [escalation.md](../skills/subagent-driven-development/references/escalation.md).
On a Codex host the rungs are not these: escalation, the single split and the
reserve chain all come from the `codex-v2` selector
([native-codex.md](native-codex.md) §Selector contract), which the caller runs
through `scripts/select-native-tier.sh`. The five-round cap is the same.

**Every round, either way:** the implementer fixes, re-runs the tests
covering the amended code, appends its fix report to the same report file,
and returns the short contract. Before re-dispatching the reviewer, confirm
the fix report contains the covering tests, the command run, and the
output; dispatch the re-review once all three are present. Name the
covering test files in the fix message — a one-line fix does not need the
whole suite.

**The re-review is scoped.** Run `scripts/review-package PLAN_FILE FIX_BASE HEAD`
where FIX_BASE is the head the previous review saw, and dispatch
[re-review-prompt.md](../skills/subagent-driven-development/references/re-review-prompt.md) with the findings list, the
brief, the report file, and the printed diff path. The re-reviewer verdicts
each finding ADDRESSED or NOT ADDRESSED, flags new breakage in the fix
diff only, and returns the progress reading. New Critical/Important breakage in
the fix diff joins the open findings list. Out-of-scope observations go to the
ledger as deferred minors — they never extend the loop. Run `date +%s` with that
`review-package` call too: it is the next round's `t0`.

**After each round,** append to the ledger:
`Task <N>: fix round <R>/5 (<X> addressed, <Y> open — <finding one-liners>; commits <a7>..<b7>; progress <p> -> <q>; resumed | fresh (<why>) | escalated <old> -> <new> | HANDBACK to <agent>)`

Never fix findings yourself in the controller session — your context stays
clean for coordination, and controller fixes skip review.

**The breaker.** When round 5's re-review still leaves findings open, stop
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

When the review comes back clean — or every open finding is parked with a
ruling at the cap — append the completion line to the ledger in the same
message as your other bookkeeping:

- `Task <N>: complete (commits <base7>..<head7>, review clean; scores spec 17 / scope 18 / verification 15 / quality 16, seat <seat>) — done: …; verified: …; remaining: none; discovered: …; assumptions: …`
- `Task <N>: complete (commits <base7>..<head7>, <K> parked; scores …, seat <seat>) — …; remaining: <parked one-liners>; …` after a tripped breaker
- end the scores clause with `, seat <seat>`: `codex gpt-5.6-sol/high`,
  `codex gpt-6-astra/high+judge-fable`, or the judge's short name, followed by
  ` (codex <STATUS> — <reason>)` when it replaced a Codex seat, or by
  ` (codex off — <reason>)` when `review-route` printed `reason=codex-off`

**Release the worktree when the task is complete.** A task that reached a
reviewed complete line no longer owns its worktree:

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
[external-task-recovery.md](external-task-recovery.md) §Ownership before the
implementer is dispatched; a bare `--release` there would drop the record the
recovery procedure reads.

Then mark the todo complete and move on. Never move to the next task while
the review has open Critical/Important issues that are neither fixed nor
parked-with-ruling at the cap.

## Recovery

For a task whose last ledger line, read by the caller's Recovery rule, is:

| Last line | Action |
|---|---|
| `implementer <agent> (assigned …)`, the agent not `inline` | If the report file has a status and `git log <base>..HEAD` is non-empty, review it (§3); otherwise dispatch the same agent fresh (§1) |
| `fix round R/5`, R < 5 | Resume the loop at round R+1 — after compaction the agent id is gone, so the cache rule makes it a fresh dispatch |
| `fix round 5/5` | Go to the breaker (§4) |
