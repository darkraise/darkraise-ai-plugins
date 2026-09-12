# dr-superpowers 1.5.0 — inline mode (sub-project 5 design)

Date: 2026-09-12. Program design: `docs/superpowers/specs/2026-09-11-dr-superpowers-fork-design.md`
(§5 R1, R2, R3, R5, R6, R7, R8, R9; §6 item 5 — the last sub-project). This spec departs from the
program design in four places, recorded as a dated amendment under its §6 (see §11).

Goal: make `executing-plans` the mode the plan's `**Execution:**` line selects, not the fallback
for a host without subagents. One session implements every task itself, writes the same ledger the
subagent controller writes, sends the judgment it cannot own to the same ruling seat, and ends at
the same whole-branch final review — with a defined exit to subagent mode when a task will not
converge.

## 1. Decisions fixed here

- **Inline mode has no per-task and no per-group review** (owner answer). The whole-branch final
  review is its only review gate. Rejected: a judge review per contiguous group of tasks (R1's
  `Group <a>-<b>: review round R/<cap>` grammar would have carried it) and a judge review per task
  on the subagent cadence — a dispatch per task is most of what inline mode exists to avoid.
- **The ruling seat serves a reduced set of decision points inline** (owner answer):
  `blocked-plan`, `plan-conflict` and `final-residual`. The other five cannot arise without a task
  reviewer, an implementer subagent or an external executor. Rejected: full parity including the
  pre-flight scan (one whole-plan judge dispatch before Task 1, on plans chosen for being cheap);
  no seat at all (contradicts R3 and leaves R2's amendments with no author).
- **The final review moves to `reference/final-review.md`** (owner answer), shared by both
  execution skills, which reduce to a pointer plus their mode's entry condition. Rejected: an
  inline session loading the 852-line subagent skill to read one section; two copies of a
  procedure this program has already rewritten twice.
- **A mode switch runs one way and hands off** (owner answer). Inline escalates to subagent mode
  on the owner's instruction or on a defined non-convergence trigger; subagent mode drops to
  inline only on the owner's explicit instruction. Either direction happens only at a task
  boundary where every earlier task is complete (R1). The plan is never edited: `**Execution:**`
  is one of the lines `plan-amend` refuses to touch.
- **The Execution line stays binding** (R6). Upstream's note — "Superpowers works much better with
  access to subagents; if subagents are available, use subagent-driven-development instead" — is
  deleted. Subagent availability is not what chooses the mode.
- **`executing-plans` keeps its `scripts/next-step` call** (program design, amendment
  2026-09-11).
- **Version 1.5.0** on both manifests. Nothing about the plan format changes, so this is not
  breaking.

## 2. File layout

Paths relative to `plugins/dr-superpowers/`.

New:
- `reference/final-review.md`
- `tests/inline-mode.test.sh`

Changed:
- `skills/executing-plans/SKILL.md` — rewritten (§3–§7)
- `skills/subagent-driven-development/SKILL.md` — Final Review becomes a pointer (§7); one new
  recovery row and the inline-return direction of the mode switch (§6)
- `skills/resume-execution/SKILL.md` — route the final review by mode (§7)
- `skills/handoff/SKILL.md` — its hard-stop clause names subagent mode only; inline's last-task
  stop is soft (§3.5)
- `reference/session-budget.md` — inline's checkpoints and stops (§3.5)
- `scripts/next-step` — stdout diagnostics on every non-zero exit; escalated-mode routing (§8)
- `tests/next-step.test.sh`
- `README.md` — What you get, Session budget, What a plan looks like, Differences from upstream,
  Tests, Reference
- `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json` — 1.5.0

## 3. `executing-plans` rewritten (R5, R9)

Section order, replacing the current file end to end: After compaction · Select the host first ·
Overview · Setup · The Ledger · Session Budget · The Task Loop · The Ruling Seat · Switching to
subagent mode · Final Review · Finish · Common Rationalizations.

### 3.1 After compaction

Only the first 5,000 tokens of a skill body come back after compaction, so this block opens the
file, as it does in subagent-driven-development:

1. Run `scripts/sdd-workspace PLAN_FILE`, from the plugin root (two levels above this skill's
   directory), and read `progress.md` and `handoff.md` in the directory it prints.
2. Trust the ledger and `git log` over the summary; resume by the Recovery table in §4.
3. Run `scripts/context-size`. On exit 5, invoke dr-superpowers:handoff.
4. Re-read this skill in full before the next task.

### 3.2 Select the host first

On Codex, the ruling seat is a native judge at Astra high or above
([native-codex.md](../../reference/native-codex.md)); there is no budget line, so hand off after
every 3 completed tasks or after any task that needed 3 or more fix rounds (R7). Everything else in
this skill is host-neutral: inline mode dispatches nothing but the seat and the final review.

### 3.3 Setup

1. Ensure an isolated workspace with dr-superpowers:using-git-worktrees. Never start on
   main/master without the owner's explicit consent.
2. Resolve the workspace with `scripts/sdd-workspace PLAN_FILE`. The ledger is
   `<workspace>/progress.md`, first line `# SDD ledger — plan: <plan file path>`. A ledger whose
   first line names a different plan, or a stray ledger at the old flat path
   `.superpowers/sdd/progress.md`, belongs to another plan: leave it and start a fresh one.
   Recover each task's state with §4's Recovery table.
3. Create `<workspace>/handoff.md` from the template in dr-superpowers:handoff if it is absent.
4. Read the plan's header, never the whole plan: `scripts/task-brief --header PLAN_FILE`, then read
   `<workspace>/plan-header.md`. Note Global Constraints and Contracts, and create a todo per Task
   index entry. A plan with no Task index (pre-1.4.0) is walked with `scripts/task-brief PLAN_FILE
   N` for N = 1, 2, … until it exits 3. You never read the spec: the ruling seat and the final
   review do.
5. **Check the Execution line** (R5's gate at execution time). It must name `inline`. If it names
   `subagent`, log `Ruling: routed to subagent mode — the plan's Execution line names it — none`
   and invoke dr-superpowers:subagent-driven-development instead. If the plan carries no Execution
   line, log `Ruling: inline by invocation — plan predates the Execution line — if wrong, the run
   escalates at the first task that will not converge` and continue. The skill does not re-score
   the tasks: `plan-lint` enforced R5 when the plan was saved.
6. Resolve legacy names with [legacy-names.md](../../reference/legacy-names.md) at read time, never
   by editing the plan, one `Ruling: translated <old> -> <new> — legacy plugin name — none` per
   distinct name.

There is no pre-flight scan. It is one whole-plan judge dispatch, and R5-eligible plans are
low-coupling by construction; the seat still receives any plan defect that surfaces during
execution as a `blocked-plan` item.

### 3.4 Overview and the stops

The Overview carries, in inline wording, what the subagent skill's Overview carries:

- **Why inline.** The plan's tasks all score 3 or less with no task at risk 3, so each is a small
  change whose text carries the code. A dispatch per task would cost more in context rebuild than
  the task itself.
- **Continuous execution.** Do not pause between tasks to check in. "Should I continue?" prompts
  and progress summaries waste the owner's time.
- **Rulings, not stalls.** Decide mechanical problems yourself and record each as
  `Ruling: <what> — <why> — <cost if wrong>`, said aloud. Everything needing judgment about the
  plan, the spec or a finding goes to the ruling seat (§5). The present skill's instruction to
  "raise concerns with your human partner before starting" is deleted: that is the stall this
  program replaced with rulings.
- **Surgical execution.** Change only what the task names. Adjacent problems become
  `Task <N>: minor (deferred): <one-liner>` instead of fixes.
- **Four stops, and only these:** an irreversible or destructive operation; a security-sensitive
  action; a side effect outside this worktree that norms say you ask about first (a merge, a push
  to a shared branch, a publish); and a ruling-seat `BLOCKED` verdict.
- **Every session ends with the next step.** Any stop before the plan is finished — one of the
  four, a budget handoff, or the owner asking you to stop — runs `scripts/next-step PLAN_FILE` from
  the plugin root as its last action, and the block it prints is the last thing in the final
  message. On exit 4, say `latest.md` could not be written. When the plan finishes,
  dr-superpowers:finishing-a-development-branch runs it instead.

### 3.5 Session budget (R7)

`scripts/task-brief` ends every brief with the budget line, so the check before each task costs no
extra request; `scripts/context-size` runs after each `Task <N>: complete` line. On `handoff`,
finish the task in flight, write its ledger line, then invoke dr-superpowers:handoff — never
mid-task.

Inline's stops, which `reference/session-budget.md` and dr-superpowers:handoff must both state:

- The plan-saved stop is hard, as in every mode.
- **Inline's last task completing is a soft stop**: the final review runs in the same session
  unless the budget line says `handoff`. This already reads that way in `session-budget.md`; what
  changes is that dr-superpowers:handoff's "When" list names the hard stop as "every plan task is
  complete under subagent-driven-development" without saying what inline does, and gains the
  soft-stop clause.
- A mode switch (§6) is always a handoff.

### 3.6 The Task Loop

Per task, in order:

1. `scripts/task-brief PLAN_FILE N` and read the brief it prints. It applies any amendments (R2),
   carries the header's Global Constraints and Contracts, and ends with the budget line. You never
   read task text any other way.
2. Take the base commit (`git rev-parse --short HEAD`) and append the assigned line (§4).
3. Implement exactly the task's steps, in order, following dr-superpowers:test-driven-development
   where the task says so. Touch only the files and lines the task names.
4. Run the task's verifications as written. A step that says `Expected: PASS` is not done until you
   have seen it pass.
5. **Self-review your own diff against the brief** before committing: every step done, nothing
   outside the named files, no test that passes with a returned constant. This is the only
   per-task gate inline mode has.
6. Commit as the task's commit step specifies.
7. Append the complete line with its checkpoint (§4), in the same message as your other
   bookkeeping, and mark the todo complete.
8. Run `scripts/context-size`.

**When a verification will not pass.** Append a `fix round R/3` line, fix, and re-verify. Rounds 1
through 3 are yours. Still failing after `3/3` is the non-convergence trigger in §6 — not a fourth
round, and not a task you complete anyway.

**When the plan itself is wrong** — its steps contradict each other, its expected output cannot be
produced, a name it mandates does not exist — send a `blocked-plan` item to the seat (§5) rather
than improvising. **When the plan is merely silent**, rule and log it.

## 4. The ledger under inline mode (R1)

One grammar for both modes, which means inline reuses the assigned line with `inline` in the agent
slot rather than inventing a start marker. `ledger_done` (`scripts/lib/plan.sh:51`) and
`scripts/lib/snapshot.sh` are untouched.

```
# SDD ledger — plan: <path>
Task <N>: implementer inline (assigned; base <sha7>)
Task <N>: fix round R/3 (X addressed, Y open — <one-liners>; commits a..b; inline | escalated inline -> subagent)
Task <N>: minor (deferred): <one-liner>
Task <N>: parked — <finding> — Ruling: <why the code stands>
Task <N>: Ruling: <finding> — <what was decided and why>
Task <N>: Ruling: (unseated) <item> — <decision> — <cost if wrong>
Task <N>: BLOCKED — ruling seat — <what a human must decide>
Task <N>: Ruling: amendment A<k> — <reason> — <cost if wrong>
Task <N>: complete (commits a..b, unreviewed | K parked) — done: …; verified: <command → result>; remaining: none | <parked>; discovered: none | …; assumptions: none | …
Ruling: <what> — <why> — <cost if wrong>
Final review: clean (commits <merge-base7>..<head7>[, K parked])
```

- The scores clause is absent: R1 already makes it conditional on a judge having scored the task,
  and no judge scores a task inline.
- `unreviewed` replaces subagent mode's `review clean`. It parses identically and is honest about
  what happened; the branch's review is the `Final review:` line.
- The cap is 3, not 5. R1 writes the cap as a parameter (`review round R/<cap>`) for exactly this.
- No `Group` lines: inline has no group reviews.
- The checkpoint after the `—` is self-reported. `done` is a one-line summary of the deliverable,
  `verified` the covering command and its result, `remaining` the parked findings, and `discovered`
  and `assumptions` are what the subagent skill takes from an implementer's report sections. Inline
  writes no report file; the ledger line is the report.

**Recovery.** For task N, take the last line in file order among its `Task <N>:` lines, stepping
over `minor (deferred)`, `parked`, `Task <N>: Ruling:` and bare `Ruling:` lines:

| Last line | Action |
|---|---|
| `complete` | Done; never redo |
| `BLOCKED` | Terminal; a stop of the fourth class for any task depending on it; name it in the final message |
| `fix round R/3`, R < 3 | Resume at round R+1 |
| `fix round 3/3` | Go to §6's non-convergence trigger |
| `fix round …; escalated inline -> subagent` | This plan has left inline mode: invoke dr-superpowers:subagent-driven-development |
| `implementer inline (assigned; base <sha7>)` | If `git log <base>..HEAD` is non-empty, re-run the task's verifications and finish it from where the commits leave it; otherwise start the task |
| none | Not started |

## 5. The ruling seat inline (R3)

Three of the eight decision points can arise without a task reviewer, an implementer subagent or an
external executor:

| Kind | Decision point inline |
|---|---|
| `blocked-plan` | The plan is wrong and no path forward is a mechanical choice |
| `plan-conflict` | A final-review finding that conflicts with what the plan's text requires, or is labelled plan-mandated |
| `final-residual` | Findings still open after the final review's one fix wave |

`preflight` is dropped (§3.3). `cannot-verify` and `risk3-spread` come from a task reviewer's
output, `breaker` from a five-round review loop, and `codex-empty-diff` from the external executor
lane — none of which exists inline.

Everything else about the seat is unchanged and is not restated in the skill: the same
`<workspace>/rulings-<point>-<task>.md` items file, the same `ruling-prompt.md` template with its
placeholders expanded, `dr-superpowers:judge-fable` with `judge-opus` under the Fable-unavailable
rule said aloud, and the same four verdicts. An `AMEND` verdict is copied from its `## A?` line
through the New fence's closing line into `<workspace>/amend-<id>.md` and applied with
`scripts/plan-amend PLAN_FILE <workspace>/amend-<id>.md`; the next `task-brief` carries it. On
`rejected: …`, one fresh seat dispatch carrying the entry and the rejection output; a second
rejection is BLOCKED. R2 therefore holds unchanged in inline mode.

Because the prompt template lives under the subagent skill's `references/`, the rewritten
`executing-plans` links it by relative path
(`../subagent-driven-development/references/ruling-prompt.md`) rather than copying it, and
`scripts/validate-repository.mjs`' reference check covers the new link.

**When no subagent facility exists at all**, the seat is unreachable. Rule yourself, write
`Task <N>: Ruling: (unseated) <item> — <decision> — <cost if wrong>`, and say it aloud; the final
review re-examines every unseated ruling. A visible ruling the owner can rework beats a session
parked on a question, which is the same trade "rulings, not stalls" makes everywhere else.

## 6. Switching modes (R1)

**Direction and boundary.** Inline escalates to subagent mode; subagent mode drops to inline only
on the owner's explicit instruction, because the Execution line is binding (R6) and an automatic
downgrade would make it advisory. Either switch happens only at a task boundary where every earlier
task is complete.

**Triggers for the inline escalation:**

- The owner says so.
- A task is still failing its own verifications after `fix round 3/3`.
- A ruling-seat `CONFIRMED-GAP` whose named fix you have attempted and failed.

The trigger is mechanical, so it is the executor's ruling, not a seat verdict — the seat's four
verdicts say nothing about execution mode.

**Procedure.**

1. Append the escalation clause to the task's fix-round line:
   `Task <N>: fix round 3/3 (…; commits a..b; escalated inline -> subagent)`.
2. Log `Ruling: switch to subagent mode at Task <N> — <trigger> — if wrong, the remaining tasks
   each cost one dispatch that inline would not have spent`, and say it aloud.
3. Do not edit the plan. `**Execution:**` is protected from `plan-amend`, and the ledger is where
   the switch is recorded.
4. Invoke dr-superpowers:handoff. The switch is always a handoff: a controller does not want an
   inline session's implementation detail in its context, and subagent mode's value is a fresh
   controller reading the header and one brief.

**What subagent-driven-development gains.** One row in its Recovery table: a fix-round line
carrying `escalated inline -> subagent` means dispatch the task's `**Implementer:**` agent fresh,
at round 1 of 5, with the brief, the open findings and the commits the inline session left. Its
"vs. Executing Plans" and mode-switch paragraphs also gain the inline-return direction, so both
skills state the same rule.

## 7. `reference/final-review.md`

The procedure moves out of subagent-driven-development's Final Review section verbatim:
`scripts/review-package PLAN_FILE MERGE_BASE HEAD`; a general-purpose Claude reviewer on the most
capable available model using `requesting-code-review`'s `code-reviewer.md`, pointed at the
ledger's deferred-minor and parked lines, the complete lines' `discovered:` fields and every
borderline score; the Codex round from `external-executor.md` §Final-review Codex round, skipped
aloud when Codex is unusable; a `judge-fable` dedupe-and-verify dispatch over the union, tagging
each finding `claude`, `codex` or `both` and returning CONFIRMED or REJECTED with evidence; the
report, ranked most severe first; ONE fix dispatch with the complete list, never one fixer per
finding; exactly one scoped re-review over the fix range; `final-residual` items to the seat; no
second fix wave.

It gains a preamble on who runs it and when:

- **Subagent mode:** a fresh session. The last task's complete line is a hard stop, so the session
  handed off and dr-superpowers:resume-execution brought the next one here.
- **Inline mode:** the same session, unless the last budget line said `handoff`.
- **Either mode:** inline mode's unseated rulings (§5), when any exist, are listed for the reviewer
  alongside the parked and deferred lines.

Both skills reduce to a pointer plus that entry condition. `resume-execution`'s step 5 currently
routes "run the final whole-branch review" to subagent-driven-development unconditionally; it
routes by the plan's Execution line instead, exactly as its "start or resume at Task N" branch
already does.

## 8. `scripts/next-step` diagnostics and routing

Two changes, both testable:

- **Every non-zero exit prints one line on stdout as well as stderr**, in the form
  `next-step: <reason> — <what to do>`. Exits 2 (usage, or the plan file does not exist), 3 (the
  plan has no `Task N` heading) and 4 (`latest.md` could not be written) currently print nothing on
  stdout, so a session that surfaces only stdout sees an empty result from the one script whose job
  is saying what happens next. Observed 2026-09-12: pointed at a plan path that no longer resolved,
  the script "returned nothing". Exit codes and stderr text do not change.
- **Escalated-mode routing.** `next-step` derives the resume skill from the Execution line
  (`scripts/next-step:65-66`). When the plan's ledger exists and its last
  `escalated inline -> subagent` line is not followed by a later `implementer inline` line, the
  prompt names dr-superpowers:subagent-driven-development instead, so a handed-off switch resumes
  in the mode it switched to. The `--complete` and `--draft` paths are unaffected.

## 9. Verification

Program design §7: `node scripts/validate-repository.mjs`, `node scripts/test-all.mjs`,
`claude plugin validate` on the marketplace and every Claude plugin; bounded timeouts; every
started process cleaned up.

Two environment facts bind the run on this machine (2026-09-12): the git-backed suites
(`budget-line`, `context-size`, `snapshot`) must run directly under Bash with
`export TMPDIR="C:/Users/quang/AppData/Local/Temp"` in the same call, while `detect` and
`executor-recovery` must run through `node scripts/test-all.mjs` because they restrict `PATH`. Two
failures are pre-existing and environmental: `context-size` 18/19 and `tests/ui-discovery.test.mjs`
(`rg` not installed).

Tests (new `.test.sh` files are picked up by `test-all.mjs` automatically):

- `inline-mode.test.sh`, in the structural-assertion style of `criteria.test.sh` — these are claims
  about a document, checkable without a model:
  - `executing-plans/SKILL.md` calls `task-brief --header`, `task-brief PLAN_FILE N`,
    `sdd-workspace`, `context-size` and `next-step`, and names dr-superpowers:handoff and
    dr-superpowers:finishing-a-development-branch;
  - it opens with an "After compaction" section, as the other long execution skill does;
  - it links `../../reference/final-review.md` and
    `../subagent-driven-development/references/ruling-prompt.md`, and both targets exist;
  - it no longer contains the deleted upstream note (matched on "works much better with access to
    subagents");
  - it states the three seat kinds and no others, and states cap 3;
  - both execution skills link `final-review.md`, and neither still spells out
    `review-package PLAN_FILE MERGE_BASE HEAD` in its own body;
  - the ledger grammar block in each skill contains the shared line kinds (`minor (deferred)`,
    `parked`, `BLOCKED`, `Ruling:`, `Final review: clean`).
- `next-step.test.sh`: a missing plan file, a plan with no tasks and an unwritable `latest.md` each
  print a `next-step:` line on stdout and keep their exit codes; a ledger whose last fix-round line
  carries `escalated inline -> subagent` produces a prompt naming subagent-driven-development; the
  same ledger with a later `implementer inline` line goes back to naming executing-plans; existing
  expectations unchanged.
- `validate-repository.mjs`' reference check covers every new `dr-superpowers:` name and the new
  cross-skill relative links.

## 10. Out of scope

- R5's thresholds and `plan-lint`'s inline check (`scripts/plan-lint:222-224`): unchanged.
- An inline lane for external executors. The Codex executor lane stays subagent-only; a batched or
  inline task never runs on one.
- Retrofitting plans written before 1.5.0.
- Re-scoring a plan's tasks at execution time. `plan-lint` is the R5 gate, and it runs when the
  plan is saved.
- `plugins/darkmem-resume/` is the owner's live untracked work: never touched or committed.

## 11. Program amendment

Appended to the program design's §6 as `Amendment 2026-09-12 (sub-project 5 spec)`, committed with
the first draft of this spec:

- Inline mode has no per-task and no per-group review. The whole-branch final review is its only
  review gate, so R1's `Group <a>-<b>: review round R/<cap>` line belongs to subagent mode's
  batching alone.
- R3's seat serves three kinds inline — `blocked-plan`, `plan-conflict`, `final-residual` — and
  rules unseated, with the ledger marker `(unseated)`, only where no subagent facility exists.
- R1's cap parameter is realized as 3 inline and 5 in subagent mode.
- The mode switch of R1 is one-way and automatic in the inline-to-subagent direction, and always
  runs a handoff.

## 12. Risks

- **Inline mode's only gate is at the end.** A defect in Task 2 surfaces after Task 9, when the
  final review reads the branch. Mitigations: R5's eligibility bar keeps every task small and
  well-specified, the plan's own verification steps run per task, TDD applies where the task says
  so, and the non-convergence trigger catches a task that is failing rather than merely wrong. This
  is the owner's trade, taken knowingly.
- **The escalation path is the least-exercised path in the program.** Nothing has run it yet. A
  wrong switch costs a handoff and a dispatch per remaining task; a missed one costs a task that
  never converges. `inline-mode.test.sh` and `next-step.test.sh` pin the mechanics, not the
  judgment.
- **Extracting `final-review.md` edits subagent-driven-development**, which sub-project 4 rewrote
  earlier the same day. The change is a deletion plus a pointer, and no other branch is in flight,
  but it is the file that changes most often upstream (program design §8).
- **Self-reported checkpoints are weaker evidence than a judge's.** `done`, `verified`,
  `discovered` and `assumptions` come from the session that wrote the code. The final review reads
  them as claims to check, not as findings.
- **An unseated ruling is a real gap in R3.** It exists so a host without subagents can still run a
  plan; on Claude Code and Codex it should never fire. If it fires often, the host detection is
  wrong and the run should have been in subagent mode.
