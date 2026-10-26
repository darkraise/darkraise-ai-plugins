# Fewer review rounds, contract plans and short seat replies

**Execution strategy:** sequential — the review groups (§2), the fix-loop cap
(§3) and the seat replies (§6) all change `scripts/task-step`,
`scripts/review-route` and `reference/delegated-task.md`, so they cannot run
apart.

**Register:** `docs/dforge/registers/2026-10-26-faster-plans.md` rows 1-3, and
`docs/dforge/registers/2026-10-25-token-efficiency.md` row 14.

## Decisions

- **Review loop.** Shown that every task gets its own judge review and up to
  five fix rounds, about 1.3 judge dispatches per implementer dispatch in
  darkcloud's transcripts. Asked what replaces it. Answer: "Risk-tiered" — the
  option read: "Per-task judge review only for risky or heavy tasks (risk 2+ or
  total 5+). The rest are reviewed together, one review per wave or group
  diff. Fix rounds capped at 2, then the ruling seat. Final whole-branch review
  unchanged."
- **Plan shape.** Shown that the book-intel plan embeds complete code (62,046
  lines for 148 tasks) and took about ten hours to write and review. Asked
  what a task carries. Answer: "Contracts + tests, bigger tasks" — the option
  read: "Tasks carry interfaces, the failing tests (or exact test cases) and
  the decisions. No implementation code. Rule S is relaxed so a task is a
  feature slice, implemented by a higher rung (Sonnet high / Opus)."
- **Book-intel.** Asked what happens to the existing 148-task plan. Answer:
  "Leave it as is" — the option read: "Execute the current 148-task plan under
  the new review rules only; the plan shape change applies to future plans."
  So every execution-side change works on a plan written before this spec, and
  on its in-flight ledger, with no re-plan and no edit to the plan file.
- **Seat replies.** Not asked; the measurements decide it (see Problem). Every
  judge seat writes its full report to a file and replies with a short digest,
  the contract implementers already follow.
- **Codex hosts.** Not asked. A `Host: codex` plan keeps its `codex-v4`
  protocol whole: Rule S at `reducible >= 4`, `review_cap: 5`
  (`reference/codex-routing.json`), per-task review. Only §6's reply contract
  reaches it, through the shared prompt templates.
- **Book-intel's cadence ruling.** Asked whether its every-tenth-wave ruling
  gives way to §4 once this ships. Answer: "Supersede it" — the option read:
  "The red-baseline rule removes the reason for the old ruling, so book-intel
  switches to every 3rd wave plus risk-3 and last waves."
- **Spec review.** Answer: "Approve and run unattended"; finish: "Merge into
  main".

Finish: merge

## Problem

Measured on 2026-10-26.

**The plan builds the code twice.** `darkcloud/docs/dforge/plans/2026-10-26-book-intelligence.md`
is 62,046 lines for 148 tasks, about 420 lines per task, nearly all of it
code. Spec to reviewed plan took from 00:51 to 10:37, with a handoff between.
Implementers then retype that code. The ladder makes this the path of least
resistance: Rule S splits any task with `files + spec + coupling >= 4`, so a
task without its code (spec 2) may touch at most one file shape and consume
at most one interface.

**The run is paced by checks and task count.** The book-intel run in
`darkcloud/.worktrees/book-intelligence` completed 18 tasks between 10:56 and
13:42, about 9 minutes per task, and 6 of the 18 needed one fix round. At that
pace the 148 tasks need about 23 hours of session time before the final
review, spread over handoffs. The plan's full integration check takes about 25
minutes; run after each of its 61 waves, as the skill requires, it would add
about 25 hours. The run's controller already ruled to run it only every tenth
wave, because the check's baseline is red on a pre-plan TypeScript error
(ledger, `Ruling: while the web typecheck baseline is red …`).

**Seat replies fill the controller's context.** Final messages returned to
darkcloud sessions over the last 30 days (`~/.claude/projects`, results
matched to their Agent call by tool-use id):

| Seat | Replies | Average | Largest |
|---|---|---|---|
| judge-opus (reviews, rulings, plan and final review) | 964 | ~1,600 tokens | ~14,800 |
| judge-sonnet-high | 92 | ~1,000 | ~1,900 |
| judge-fable | 39 | ~3,300 | ~7,200 |
| implementers (all tiers) | ~700 | ~300 | ~1,000 |

Implementers already write their report to a file and reply in under 15
lines. Judges cannot: their agents hold only Read, Grep, Glob and WebFetch, so
the whole report is the reply, and it stays resident for the rest of the
session.

**What a plan without code costs.** The tier harness's `stripped` stage
(`evals/tiers/results/results.tsv`, rep 1) gives implementers prose,
signatures and tests but no implementation code. After the three cases the
owner excluded as case defects on 2026-10-02, first-attempt passes were Opus
tiers 6 of 6, impl-sonnet-high 8 of 8 and impl-sonnet-medium 6 of 6. The cases
were Rule-S-sized; none was a feature slice.

## Design

### 1. Plan shape: contracts and tests

`skills/writing-plans/SKILL.md`, `references/drafter-prompt.md`,
`references/plan-reviewer-prompt.md`, `reference/ladder.md` (Rule S, the gate
block, the prose that derives caps and the lane envelope from
`reducible <= 3`, and "Plans written before"), `scripts/plan-lint`,
`scripts/plan-revise`, `scripts/review-route`.

- **What a task carries.** Its files, its `**Interfaces:**` (exact signatures
  of what it produces and consumes), the complete code of its tests, the
  decisions it embodies, and the commands that verify it. It gives
  implementation code only where no test can pin the behaviour: a
  configuration value, a generated-file or migration command, a fixed
  constant the spec names. "No Placeholders" keeps its bans, and "steps that
  describe what to do without showing how" becomes "tests that describe
  behaviour without asserting it".
- **Claude plans only.** On a Codex host, Rule S at 4 would split a
  `files 1 + spec 2 + coupling 1` task, so writing-plans there keeps
  code-given tasks.
- **Task size.** A task is a feature slice: the smallest unit with its own
  test cycle that a reviewer could reject while approving its neighbour, now
  scored with spec 2. Task Right-Sizing keeps its wording; Bite-Sized Task
  Granularity is removed, since a step is no longer a two-minute transcription.
- **Rule S, Claude plans.** Split when `files + spec + coupling >= 6`, or when
  `spec = 3`. A compliant task has `reducible <= 5`, so `total <= 8`. A
  `Host: codex` plan keeps `reducible >= 4`: `native-codex.md` derives its
  weighted 0-9 score from `reducible <= 3`, and `codex-routing.json` ranks stop
  at 9. `plan-lint` and `plan-revise` apply the gate by host.
- **Assignment table.** Rows 0-6 are unchanged, so every plan written before
  this spec keeps its assignments and `plan-lint` keeps passing them. Rows 7
  and 8 name `impl-opus-high`. No spec-based floor: the corrected stripped
  record shows no tier failing a code-free task. The escalation and reserve
  tables are unchanged.
- **Executor lane.** The `gate` block gains `max_score 4`, read by `plan-lint`
  and the lane-gate script: `codex-assignment` has rows for totals 2-4 only, so
  a total-5 or total-6 task at risk 1 or below must not be offered the lane.
- **Drafters.** The drafter prompt stops asking for prototyped, tested code;
  it asks for the tests and the interfaces, run against the current tree to
  confirm they fail for the right reason.
- **Plan review.** At most two rounds. Round 2, on the delta template, keeps
  today's trigger (a Critical finding or any score of 8 or below); there is no
  third. `review-route --plan-round` stops deriving a cap from the highest
  task total, which would rise with every bigger task.
- **One-way compatibility.** A plan written under the relaxed gate fails
  `plan-lint` on an older plugin; ladder.md's "Plans written before" section
  says so.

### 2. Review groups

`reference/delegated-task.md`, `skills/subagent-driven-development/SKILL.md`,
`reference/parallel-waves.md`, `scripts/review-route`, `scripts/task-step`,
the task-reviewer template (a group variant), `hooks/cockpit/lib.ts`.

A task is **reviewed alone** (`review=task`) when its Evaluation line scores
risk 2 or more, or a total of 5 or more, and **grouped** (`review=group`)
otherwise. Delegation's "heavy" set in inline mode (`total >= 5 or risk = 3`)
is a subset of `review=task`, which is why inline mode needs no change.
Reviewed-alone tasks keep today's per-task review and seat routing. Grouped
tasks are reviewed by one judge dispatch over several tasks' diffs.

- **Seat.** `review-route --task N` prints `review=task` or `review=group`; a
  task with no Evaluation line prints `review=task reason=unscored` instead of
  exiting 2, and `task-step` treats any route exit 2 as `review=task`. With
  several tasks, `review-route` keeps routing by their highest total.
- **State.** `task-step hold PLAN_FILE N` runs when a grouped task's
  implementer reports DONE: it records the task's head and writes
  `Task <N>: awaiting group review (commits a..b)`. `task-step review --group
  PLAN_FILE N M …` writes `group-<list>-step.json`, packages one `base..head`
  diff per task, and fills the group template with one brief, report and diff
  per task, each labelled by task number, so a finding names its task. It also
  records `reviewHead` (the group head), `t0` and `round` in each member's
  `task-<N>-step.json`, so a member's fix round re-reviews with `task-step
  rereview PLAN_FILE N --base <group review head>` and `task-step verdict`
  finds its state.
- **Sequential.** Held tasks accumulate. A group review is triggered when 4
  tasks are held, before the next reviewed-alone task is dispatched, and after
  the plan's last task. Once triggered, no new task is dispatched until the
  group is clean, and fixes inside a group run one task at a time. A grouped
  task reporting BLOCKED, NEEDS_CONTEXT, or DONE_WITH_CONCERNS with a
  correctness concern leaves the group and is reviewed alone; the group
  reviews once its remaining members are held.
- **Waves.** A wave's reviewed-alone tasks are reviewed one by one in their
  worktrees, as today. Its grouped tasks are reviewed by one group dispatch
  once every grouped task in the wave is held, before any of them merges; a
  member's fix round goes to that task's implementer in its worktree.
- **Ledger.** `Group <list>: review round R/2 (Task 4: 1 open — …; Task 6:
  clean; Task 7: …; commits …)`, where `<list>` is comma-separated
  (`Group 4,6,7`) and the clause attributes every finding and fix commit to its
  task. Each task still gets its own `complete` line once the group is clean.
  Recovery reads `awaiting group review` as "reviewed by the next group
  dispatch". Same-shape batching (`Group <a>-<b>`) is unchanged: a contiguous
  range is a valid list. The cockpit's `parseLedger` accepts both forms.
- **Unchanged.** Minor findings never enter the fix loop. Plan-conflict and
  cannot-verify items go to the ruling seat. The final whole-branch review and
  acceptance QA are untouched: they are the gate a group review leans on.

### 3. The fix loop: two rounds

`reference/delegated-task.md`, `skills/subagent-driven-development/references/escalation.md`,
`skills/subagent-driven-development/references/re-review-prompt.md`,
`reference/executor-lane.md`, `reference/ladder.md` (the Codex successor
prose), `scripts/task-step`, `scripts/next-step`, and the
subagent-driven-development ledger grammar and Recovery table. Inline mode's
own escalation trigger is unchanged.

- Round 1 resumes the implementer or dispatches it fresh, by today's cache
  rule. Round 2 is a fresh dispatch of the successor rung on the escalation
  table. When the successor is `SPLIT` (from `impl-opus-high`), round 2 is a
  fresh dispatch of the same rung, and a split is reached only through the
  breaker's AMEND. A reserve-tier task takes its reserve successor.
- An executor-lane task: round 1 resumes the executor session; round 2 is a
  `HANDBACK` to the task's `**Implementer:**` agent; then the breaker.
- A finding still open after round 2 goes to the breaker (the ruling seat),
  which keeps its verdicts: CONFIRMED-GAP carried forward, PARK, AMEND,
  BLOCKED.
- The progress-stall rule is removed with rounds 3 to 5: the `**Progress:**`
  section leaves the re-review prompt and the `progress p -> q` field leaves
  the fix-round grammar. The re-review skip rule (`--covered`) is unchanged.
- `Task <N>: fix round R/2`, `Group <list>: review round R/2` and
  `Wave <k>: fix round R/2` replace the `R/5` forms. A ledger from an older run
  holding any of the three with `R/5` resumes at round 2 when R is 1 and at
  the breaker when R is 2 or more. A wave's merge-conflict round still counts
  as a round.

### 4. Wave integration check cadence

`reference/parallel-waves.md`, `skills/writing-plans/SKILL.md` (header),
`skills/subagent-driven-development/SKILL.md` (recovery), `scripts/wave`,
`scripts/next-step`.

- **When.** The plan's `**Integration check:**` runs after every third wave
  in the Parallelism line, after any wave holding a risk-3 task, and after the
  last wave. On the other waves the header's optional `**Wave check:**`
  command runs when present (a build and the fast unit suite, say); without
  one, the wave rests on each task's own tests and a clean merge.
  `scripts/wave check-due PLAN_FILE <k>` prints `full`, `wave-check` or `none`
  from the plan's wave numbers, so the controller never counts.
- **Every wave closes.** Every wave, one-task and serialized waves included,
  ends with `Wave <k>: integrated (…)` or
  `Wave <k>: merged (head <sha7>; check at wave <m>)`. Recovery treats
  `merged` as closed, and the next wave starts on it.
- **Proving the base.** A `merged` or `integrated` line proves the next
  wave's base when its sha is HEAD, or an ancestor of HEAD with no task
  commits between (bookkeeping commits do not count). Only a task commit
  outside any wave forces the fallback proof: the `**Wave check:**`, or the
  full check when the plan has none.
- **Red baseline.** The base proof writes its failing test names to
  `<workspace>/base-proof-failures.txt`, from `suite-run`'s digest. A full
  check whose failures are a subset of that file counts as passing, logged
  `integrated (…; baseline failures only)`. A new failure hands the fix
  dispatch every task diff since the last passing check.
- **In-flight runs.** None is exempt. Once the plugin carrying this spec is
  installed, book-intel's every-tenth-wave ruling (made because its baseline
  is red) is superseded by this cadence and the red-baseline rule; the
  controller logs one `Ruling:` line saying so.
- writing-plans adds the `**Wave check:**` line to the header template. An
  older plan without it runs the full check on this cadence and nothing
  between; a Header AMEND in `amendments.md` can add one without editing the
  plan file.

### 5. Spec review rounds

`skills/brainstorming/SKILL.md`, `reference/auto-run.md`.

The Fable spec review runs one round. A second runs only when round 1 leaves a
Blocker or High finding open, its own or a folded critic's, and checks only
those answers. The separate architecture critic for risk and new-subsystem
specs is unchanged.

### 6. Seat replies: report file and digest

`agents/judge-opus.md`, `agents/judge-sonnet-high.md`, `agents/judge-fable.md`
(their tool lists and the "You cannot modify files" text, which becomes "write
only the report file"), every judge prompt template (task reviewer and its
group variant, re-review, ruling, plan reviewer, architecture critic, final
review and its dedupe, acceptance QA, the closing-a-milestone and
distilling-docs verifiers), `scripts/task-step`, `scripts/plan-amend`.

- **The contract.** Each judge agent gains `Write`. Every judge prompt names a
  `[REPORT_FILE]` in the plan's workspace (or `<state>` outside a plan) and
  says: write the full report there, write nothing else, then reply in at most
  10 lines with the verdict, the scores, a count of findings by severity, and
  the report path. A `BLOCKED` ruling also puts the decision a human must make
  in the reply.
- **The report grammar.** Every report opens with a `## Verdict` section of
  fixed `key: value` lines (verdicts, scores, and for a ruling the `Verdict:`
  and `Ruling:` lines), then lists findings under fixed headings as
  `- [Critical|Important|Minor] <file>:<line> — <one-liner>`. Report files are
  `task-<N>-review-report.md`, `task-<N>-rereview-<R>-report.md`,
  `group-<list>-review-report.md` and `rulings-<point>-<task>-report.md`.
- **`task-step verdict PLAN_FILE N [M …] [--cwd DIR]`** runs when a review or
  re-review seat returns. It confirms the reviewed worktree's tracked files are
  as the review step left them, reads the report, and prints a digest: the
  verdicts, the scores, one line per Critical or Important finding with its
  file and task, and the cannot-verify items. It writes the next fix file's
  findings from the report, so the controller never pastes them.
- **Failures.** A missing report file, or a tracked file changed during the
  review, exits non-zero and names the files. The controller then restores the
  tracked files (`git checkout -- <files>`; the review saw the committed
  state), logs a `Ruling:`, discards the report and re-dispatches the seat
  once; a second failure dispatches the route's fallback judge and says so.
- **Outside the task loop.** Ruling, plan-review, final-review and
  spec-review seats follow the same contract; the controller reads only the
  `## Verdict` section. An AMEND body is extracted with
  `scripts/plan-amend PLAN_FILE --report <file> --id A<k>`, never copied by
  hand.

### 7. Tests and text checks

Each changed script keeps its suite in `plugins/dforge/tests/`
(`ladder.test.sh`, `lanes.test.sh`, `review-route.test.sh`,
`task-step.test.sh`, `task-step-text.test.sh`, `plan-lint.test.sh`,
`plan-revise.test.sh`, `plan-amend.test.sh`, `wave.test.sh`,
`next-step.test.sh`, `seats.test.sh`, `fleet.test.sh`, `cockpit.test.ts`),
with fixture plans in both the old and the new shape and a fixture ledger cut
from book-intel's. An acceptance suite, `tests/faster-plans.acceptance.test.sh`,
covers the statements below.

## Acceptance

A1. [test, high] writing-plans, its drafter prompt and its plan-reviewer prompt require every code task to give its interfaces, the complete code of its tests and its verify commands, and allow implementation code only for configuration values, generated-file or migration commands and constants the spec names.
A2. [test, high] On a Claude plan, `plan-lint` accepts a task scoring `files + spec + coupling` of 5 and rejects one of 6, and rejects any `spec = 3` task without a human override; on a `Host: codex` plan it still rejects 4.
A3. [test, high] The assignment table maps totals 0-6 exactly as before this spec and maps 7 and 8 to `impl-opus-high`.
A4. [test, neg, high] The executor-lane gate never admits a task with a total above 4.
A5. [test, high] `review-route --task N` prints `review=task` for a task with risk 2 or more or total 5 or more, `review=task reason=unscored` for a task with no Evaluation line, and `review=group` otherwise.
A6. [test, neg, high] A `review=task` task is never packaged into a group review, and a group review never contains a task without an `awaiting group review` line.
A7. [test, high] `task-step hold` writes the `awaiting group review` line with the task's commit range, and recovery after compaction reviews a held task in the next group dispatch without re-dispatching its implementer.
A8. [test, high] In sequential mode one group review is dispatched when 4 tasks are held, before a `review=task` task is dispatched, and after the plan's last task; no task is dispatched while a group review or its fix rounds are open; each member gets its own `complete` line after the group is clean.
A9. [test, high] A group review package holds one diff per task, from that task's base to its head, labelled with its task number, and in a wave it is dispatched before any member merges.
A10. [test, high] The `Group <list>` ledger line attributes findings and commits per task, and the cockpit's Run card shows its round for both a comma list and a range.
A11. [test, high] A fix loop holds at most two rounds; round 2 dispatches the successor rung, or the same rung when the successor is `SPLIT`; an executor task's round 2 is a `HANDBACK` to its Implementer; a finding open after round 2 goes to the ruling seat.
A12. [test, high] A ledger written before this spec with a `Task`, `Group` or `Wave` fix or review round `R/5` resumes at round 2 when R is 1 and at the breaker when R is 2 or more.
A13. [test, high] `wave check-due` prints `full` for waves 3, 6, 9 …, for a wave holding a risk-3 task and for the last wave, `wave-check` for other waves when the header has a `**Wave check:**` line, and `none` otherwise.
A14. [test, high] Every wave, one-task and serialized waves included, ends with an `integrated` or `merged` line, and a wave whose predecessor's `merged` line names HEAD starts without rerunning the full check.
A15. [test, high] A full check whose failures are a subset of `base-proof-failures.txt` is logged as `integrated (…; baseline failures only)`; a new failure hands the fix dispatch every task diff since the last passing check.
A16. [test, neg, high] A `merged` line whose sha is an ancestor of HEAD with only bookkeeping commits between proves the base without rerunning the full check; a task commit outside any wave forces the fallback proof.
A17. [test, high] Plan review runs at most two rounds, the second only on a Critical finding or a score of 8 or below; spec review by Fable runs a second round only when round 1 left a Blocker or High open.
A18. [test, high] Every judge agent lists `Write`, and every judge prompt template names `[REPORT_FILE]`, fixes the `## Verdict` section and the finding-line grammar, and limits the final message to 10 lines.
A19. [test, high] `task-step verdict` prints a digest of at most 20 lines plus one line per Critical or Important finding, read from the report file, and writes the next fix file's findings.
A20. [test, neg, high] `task-step verdict` exits non-zero and names the files when a tracked file in the reviewed worktree changed during the review, and when the report file is missing.
A21. [test, high] `plan-amend --report <file> --id A<k>` applies the AMEND entry from a ruling report exactly as from a hand-copied file.
A22. [test, neg, high] A plan written before this spec, with spec-0 tasks, totals up to 6, no `**Wave check:**` line and `fix round R/5` ledger lines, passes `plan-lint` unchanged and runs under §2-§4 without any edit to the plan file.
A23. [test, neg, high] A `Host: codex` plan keeps per-task review, five fix rounds and Rule S at 4.

## Riskiest assumption

That implementers finish a feature-slice task from its contracts and tests,
at the rung §1 assigns, within the two fix rounds §3 allows, often enough that
fewer, bigger tasks finish sooner than many transcription tasks.

Evidence so far: the tier harness's `stripped` stage, rep 1
(`evals/tiers/results/results.tsv`, read 2026-10-26): after the three
owner-excluded case defects, every tier passed every code-free case on the
first attempt (Opus 6 of 6, Sonnet high 8 of 8, Sonnet medium 6 of 6). Those
cases were Rule-S-sized, not feature slices.

unverified — the plan's first task verifies it: build five slice-sized
stripped cases from this repository's plan history (two or three consecutive
past tasks merged into one brief, scored under §1) and run
`impl-sonnet-high`, `impl-opus-medium` and `impl-opus-high` on them through
`evals/tiers/run-grid.mjs`. Four of five passing on the arm §1 assigns keeps
§1 as written; fewer stops the plan for a ruling on the slice size before any
later task builds on it.

## Review rulings

- Fable, spec: round 1 — lane gate gains `max_score 4` (codex-assignment covers totals 2-4 only).
- Fable, spec: round 1 — Rule S relaxes for Claude plans only; `Host: codex` keeps `reducible >= 4`.
- Fable, spec: round 1 — no Opus floor; stripped figures corrected for the three owner-excluded case defects.
- Fable, spec: round 1 — plan review keeps today's round-2 trigger; only the cap (2) changes.
- Fable, spec: round 1 — §1 files add plan-revise and ladder.md's derived-cap prose.
- Fable, spec: round 1 — "reviewed alone" / "grouped" replace "heavy", which inline delegation already defines.
- Fable, spec: round 1 — `review-route --task` prints `review=task reason=unscored` rather than exiting 2.
- Fable, spec: round 1 — group state: `task-step hold`, `review --group`, group step file, per-task packaging, rereview `--base`.
- Fable, spec: round 1 — sequential groups block new dispatches until clean; a concerned or blocked member leaves the group.
- Fable, spec: round 1 — Group lines attribute per task; cockpit `parseLedger` accepts comma lists.
- Fable, spec: round 1 — old `R/5` mapping covers Task, Group and Wave lines.
- Fable, spec: round 1 — `SPLIT` successor keeps the same rung for round 2; reserve tasks take their reserve successor.
- Fable, spec: round 1 — executor tasks: resume, then HANDBACK, then breaker; Codex keeps `review_cap: 5`.
- Fable, spec: round 1 — the Progress section and `progress p -> q` field are removed with the stall rule.
- Fable, spec: round 1 — a `merged` line naming HEAD proves the next wave's base.
- Fable, spec: round 1 — baseline-only failures count as a pass.
- Fable, spec: round 1 — every wave closes with integrated or merged; `wave check-due` decides the cadence.
- Fable, spec: round 1 — every third wave plus risk-3 waves and the last (≈29 checks for book-intel against 61).
- Fable, spec: round 1 — fixed report grammar and report file names for `task-step verdict`.
- Fable, spec: round 1 — a judge that edits code: restore, Ruling, re-dispatch once, then the fallback judge; `verdict --cwd`.
- Fable, spec: round 1 — AMEND bodies extracted by `plan-amend --report`.
- Fable, spec: round 1 — §7 adds fleet, lanes and cockpit tests; the judges' "cannot modify files" text changes.
- Fable, spec: round 1 — acceptance added for the gate, Codex, hold, cadence, executor rounds, cockpit and held-task recovery.
- Fable, spec: round 2 — base-proof failures recorded in `base-proof-failures.txt` and compared as a set.
- Fable, spec: round 2 — a `merged` sha that is an ancestor of HEAD with no task commits between proves the base.
- Fable, spec: round 2 — the contracts-and-tests plan shape is Claude-only.
- Fable, spec: round 2 — `review --group` records reviewHead, t0 and round in each member's step file.
- Controller: round 2 — no in-flight exemption; book-intel's every-tenth-wave ruling is superseded once the plugin is installed (Fable: the owner's call; the owner chose "Supersede it").

## Critic findings

Folded into Fable's round 1. Critic: 0 Blocker, 4 High (4 fixed, 0 answered),
3 Medium, 2 Nit.

- High, §4: no outcome for a red baseline — fixed by the Red baseline rule.
- High, §4: base proof reran the full check after a skipped wave — fixed by Proving the base.
- High, §1: relaxed Rule S broke Codex scoring and the lane gate — fixed by the Codex carve-out and `max_score 4`.
- High, §2: group review had no state model — fixed by `hold`, `review --group` and the group step file.
- Medium, §2: deferred group fixes blur commit ranges and contend for the checkout — fixed: fixes run one at a time and the Group line names per-task commits.
- Medium, §6: no report grammar for `verdict` — fixed by the report grammar.
- Medium, §2: cockpit drops comma-list Group lines — fixed (§2 Ledger, A10).
- Nit, §1: one-way plan-lint compatibility — noted in §1.
- Nit, §2: "most code-free tasks score 5 or more" did not follow — sentence dropped.
