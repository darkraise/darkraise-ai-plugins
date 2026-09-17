# dr-superpowers — Whole-plugin review fixes (design)

Date: 2026-09-17. Status: owner-approved design. A follow-up to the completed
ten-sub-project program (`docs/superpowers/specs/2026-09-11-dr-superpowers-fork-design.md`),
not an eleventh sub-project: the program design is not amended. Scope: the
findings of `.superpowers/handoff/whole-plugin-review-2026-09-17.md` (the review
of 1.11.0 after SP10 merged at d17b1f0) that change behaviour or an interface.
Release: 1.12.0.

## 1. What this is for

The review scored executor usability and cost efficiency lowest (12 of 20).
Four of its findings share a cause: a seat or contract left implicit.

- The skills say to run every script "from the plugin root", but the scripts
  find the repository from the working directory (I1).
- The final-review fix wave has no named agent (I2), and the final Claude
  review runs on "the most capable available" model, which is Fable on every
  plan (I5).
- One task totalling 4 puts a whole inline session on Opus, so every lighter
  task runs on Opus too, and the total-4 task itself gets no independent
  review (I4).

Two smaller findings touch the same rules: `plan-lint` rule 5 accepts Execution
lines the rule never produces (M2), and escalating a task out of inline mode can
pick a rung below the session that just failed it (M7).

Every finding was checked against the code on 2026-09-17; the triage is in
Appendix A. The stale-prose and small-script findings ship first as 1.11.1 (§8)
and are not part of this design's plan.

## 2. Decisions fixed here

Owner rulings, 2026-09-17:

1. **Working directory decides (I1).** Scripts are called by their plugin-root
   path with the working directory inside the project. A plan-taking script
   refuses a plan that lives in a different repository than the working
   directory (§3).
2. **Delegate total-4 tasks while they are a third of the plan or fewer (I4).**
   Past that, today's Opus inline session stands. Total-4 delegation does not
   count toward whole-plan subagent mode and does not trigger a preflight (§4).
3. **Final Claude review (I5):** `judge-opus`, or `judge-fable` when the plan is
   intricate (§5.1).
4. **Final fix wave (I2):** the highest tier among the tasks the findings touch,
   between `impl-sonnet-high` and `impl-opus-high` (§5.2).
5. **Batch first.** I3, M1, M5, M8, M9, M11, M12 and M13 ship as 1.11.1 before
   this design's plan runs (§8).

## 3. Working-directory contract (I1)

### 3.1 Evidence

- `sdd-workspace:35`, `next-step:48`, `repo-audit:14` and `lib/context.sh:29`
  call `git rev-parse --show-toplevel` in the working directory;
  `review-package` runs `git log` and `git diff` there.
- `plan_amendments_file` (`lib/plan.sh:260-266`) resolves from the plan's
  directory, so the two disagree when the plan and the working directory are in
  different checkouts.
- In this repository the plugin sits inside the project, which hides the bug.
  An installed copy (`~/.claude-alt/plugins/cache/darkraise/dr-superpowers/1.6.0`)
  is not a git repository, so a literal reader of "from the plugin root" gets an
  error rather than state written into the plugin copy.

### 3.2 The contract

Every `scripts/…` command is called as `bash <plugin-root>/scripts/<name>`, with
the working directory inside the project's worktree. A relative `PLAN_FILE`
resolves against that working directory.

- `skills/using-superpowers/SKILL.md` (Session Budget, first bullet) states the
  contract once.
- `scripts/session-start.sh:54` prints
  `Plugin root: <path> — call scripts by this path, with the working directory inside the project`.
- Every other site that says "from the plugin root (the path the session's
  entry point names; …)" says instead "(see using-superpowers §Session Budget)"
  or drops the parenthetical where the command already shows
  `<plugin-root>`: `executing-plans/SKILL.md:14,88,106,128`,
  `subagent-driven-development/SKILL.md:14,75,174,202`, `handoff/SKILL.md:66`,
  `resume-execution/SKILL.md:16`, `writing-plans/SKILL.md:283`,
  `reference/delegated-task.md:55,145`, `project-status/SKILL.md:17`,
  `brainstorming/SKILL.md:237`, `finishing-a-development-branch/SKILL.md:287`.
- On Codex the plugin root stays "the directory two levels above any skill
  file"; only the working-directory half is new there.
- The comment in `lib/codex-session.sh:4-6` is corrected to match.

### 3.3 The mismatch check

`lib/plan.sh` gains `plan_require_same_repo FILE`:

- It compares `git -C "$(dirname FILE)" rev-parse --show-toplevel` with
  `git rev-parse --show-toplevel` in the working directory, both in git's own
  output form (as `_plan_canon` already does).
- When they differ, or either is not a repository, it prints
  `<script>: <FILE> is in <plan top level>, but the working directory is in <cwd top level>; run from inside the plan's worktree`
  to stderr and exits 2. A working directory outside any repository prints
  `not inside a git repository` as today.
- A linked worktree and its primary checkout have different top levels, so a
  plan path into the primary checkout from a worktree session is refused.

Callers: `sdd-workspace` (so `task-brief` and `review-package` inherit it),
`review-package` (before its own git calls), and `next-step` (on the plan or
draft file it is given). `repo-audit` and `context-size` take no plan file and
are unchanged.

## 4. Delegating total-4 tasks (I4, M2)

### 4.1 Evidence and estimate

Prices (claude-api reference, cached 2026-06-24): Opus 5 $5/$25 per million
input/output tokens, Sonnet 5 $2/$10, a ratio of 2.5; Fable 5.1 $10/$50. How
the subscription limit weighs models is unverified.

Estimate, not measurement. From SP10 §3 (floor 57k, inline growth 19.1k per
task, one seat a median 238k units) and an assumed 25 requests per task, one
inline task costs about 330k units, and a 6-task inline session about 2M.

- One total-4 task today puts the session on Opus: about +3M units at Sonnet
  prices for a 6-task plan.
- Delegating it costs an `impl-opus-low` implementer, a task review and perhaps
  one fix round, about 1.2-1.8M, less the ~330k the session no longer spends:
  about 1-1.5M net.
- Delegation's cost grows per total-4 task; the Opus premium grows with the
  plan. Delegation wins below roughly two fifths of the tasks; the rule uses
  one third for margin.
- Not estimated: the thinking cost of raising a delegating session's effort to
  `high` (§4.3).

Quality: a total-4 task at risk 2 today gets only the session's self-review;
SP10 §9 rejected unreviewed risk-2 shared-path changes. Delegated, it gets the
ladder's own `impl-opus-low` and an independent review. The lighter tasks lose
an Opus upgrade the ladder never called for.

### 4.2 Which tasks are delegated

For a Claude-host plan with `N` tasks (counted by `### Task N` heading):

- **Heavy** is unchanged: highest total 5 or more, or risk 3, on any part
  (`plan_heavy`).
- **Four-band** tasks are those not heavy whose highest total is exactly 4.
- **Delegated** = heavy tasks, plus the four-band tasks when
  `3 x (four-band count) <= N`. Otherwise no four-band task is delegated.

`lib/plan.sh` gains `plan_delegated FILE`, printing `N<TAB>heavy` or
`N<TAB>total 4` per delegated task, ascending. `plan_heavy` keeps its meaning
and its callers.

Heavy tasks alone decide:

- whole-plan subagent mode (`2 x heavy > N`, SP10 §4.2), and
- the preflight (§4.5).

### 4.3 The Execution line (`writing-plans`)

The **self-implemented** tasks are the tasks not delegated.

- `subagent` when `2 x heavy > N`: `claude --model sonnet --effort high`, as
  today.
- Otherwise `inline`:
  - **Model:** `opus` when a self-implemented task totals 4 (so only when
    four-band tasks exceed a third of the plan); otherwise `sonnet`.
  - **Effort:** the assignment-table effort of the highest self-implemented
    total (`impl-haiku` counts as `low`), raised to `high` when any task is
    delegated.
  - Every task heavy, owner override to inline: `claude --model opus --effort
    high`, as today.
- The owner may override the line either way, as today.

### 4.4 `plan-lint` rule 5 (Claude host)

Replaces SP10 §4.3's bullets. A `Host: codex` plan is untouched.

| Condition | Finding |
|---|---|
| Any delegated task, inline plan | `NOTE header: delegated: Task 2 (heavy), Task 5 (total 4)` |
| Inline line, `2 x heavy > N` | `WARN header: Execution line is inline but <h> of <n> tasks are heavy` (unchanged) |
| Subagent line, `2 x heavy <= N` | `WARN header: Execution line is subagent but only <h> of <n> tasks are heavy` (unchanged) |
| Subagent line not `sonnet` / `high` | `WARN header: subagent Execution line should be claude --model sonnet --effort high` |
| Inline model not `sonnet` or `opus` | `ERROR header: inline execution needs --model sonnet or opus (model <m>)` |
| Inline, a self-implemented task totals 4, model not `opus` | `ERROR header: inline execution with a self-implemented task at total 4 needs --model opus` |
| Inline effort below the required effort (§4.3) | `ERROR header: inline execution needs --effort <required> or above (effort <e>)` |

A `claude-*` model id counts as the family its name contains (`claude-opus-5`
is `opus`); one naming neither `sonnet` nor `opus` is the model error. An effort
above the required one, and `opus` where `sonnet` would do, produce no finding. `plan-lint` reads the delegated set from `plan_delegated`, and its
private awk copy of the heavy rule is removed. Plans with no Execution line are
unchanged.

### 4.5 `task-brief` and `executing-plans`

- A delegated task's brief carries `**Dispatch:** delegated — total <t>, risk
  <r>` as its second line (format unchanged; the set now comes from
  `plan_delegated`).
- `task-brief --header` appends
  `**Dispatch:** delegated — Task 2 (heavy), Task 5 (total 4)`.
- `executing-plans` Setup (`:159-164`) runs the preflight when that line names
  at least one `(heavy)` task. The ruling-kinds table (`:326`) and `:334` say
  "a plan with a heavy task".
- A delegated four-band task runs `reference/delegated-task.md` exactly as a
  heavy task does; `review-route --task` already routes totals 4-6.
- The "Execution" paragraph of `using-superpowers` Process Depth, the README's
  execution-mode prose and `delegated-task.md`'s opening name both reasons for
  delegation.

## 5. Final-review seats (I5, I2)

### 5.1 The final Claude review

`scripts/review-route PLAN_FILE --final` prints one line in the existing format:

```
review-seat final primary=dr-superpowers:judge-fable fallback=dr-superpowers:judge-opus reason=intricate
review-seat final primary=dr-superpowers:judge-opus fallback=- reason=plain
```

`intricate` is the value `plan_shape` already computes (any task at risk 3 or
total 6, `review-route:63`).

- `reference/final-review.md` step 1 dispatches the printed `primary`, with
  `fallback` when Fable is unavailable or the owner declined it, said aloud.
- The seat is the named judge agent, not a general-purpose agent. The judge
  agents are read-only; the review always has a package file, so the template's
  git fallback (`code-reviewer.md:29-32`, used only when `[DIFF_FILE]` is
  `none`) never applies.
- The Seats table in `subagent-driven-development/SKILL.md:241-253` loses the
  "most capable available" row and prose; `executing-plans` Final Review points
  at the same step.
- `agents/judge-fable.md` and `agents/judge-opus.md` descriptions add the final
  review of an intricate plan and of a plain plan respectively.

A Codex-host plan keeps `reference/native-codex.md`'s own final-review seat.

### 5.2 The final fix wave (subagent mode)

`scripts/review-route PLAN_FILE --final-fix FILE [FILE ...]` prints:

```
review-seat final-fix primary=dr-superpowers:impl-opus-medium fallback=- reason=tasks:3,7
review-seat final-fix primary=dr-superpowers:impl-sonnet-high fallback=- reason=floor
```

- **Matching.** Each `FILE` (a repository-relative path, as findings name it) is
  matched against every task's `**Files:**` block entries (`Create:`, `Modify:`,
  `Test:`), ignoring a `:line-range` suffix. A split task's parts count as the
  task. The plan is read with amendments applied.
- **Tier per task.** The last `implementer <agent>` named on that task's
  assigned or fix-round lines in `<workspace>/progress.md` (an escalation's new
  agent counts); the task's `**Implementer:**` line when the ledger names none.
  An `inline` implementer counts as the Execution line's rung (§6).
- **Choice.** The highest rank (`reference/ladder.md` §Why this terminates)
  among matched tasks, raised to `impl-sonnet-high`, capped at
  `impl-opus-high`. No matched task gives `reason=floor`.
- **Ledger.** The controller appends
  `Final fix: implementer <agent> (assigned; base <sha7>)` before dispatch; the
  ledger grammar in `subagent-driven-development` gains the line. Recovery after
  compaction re-dispatches that agent fresh.
- **Inline mode** is unchanged: the session is the fixer.
- `reference/final-review.md:70-71` names the command.

## 6. Escalating out of inline mode (M7)

The recovery row for `escalated inline -> subagent`
(`subagent-driven-development/SKILL.md:304`) dispatches the first rung on the
escalation table whose rank is strictly above both:

- the task's `**Implementer:**` agent, and
- the inline session's rung: the Execution line's `--model` and `--effort` as
  `impl-<model>-<effort>` (`haiku` as `impl-haiku`).

The walk starts from whichever of the two ranks higher. When that start is
`impl-opus-high`, its successor is `SPLIT`, handled as the ladder already
handles it. `references/escalation.md` gains the same sentence. No script
changes: the controller already reads the table.

## 7. Interface changes

| Surface | Change |
|---|---|
| `scripts/lib/plan.sh` | `plan_require_same_repo`, `plan_delegated` |
| `scripts/sdd-workspace`, `scripts/review-package`, `scripts/next-step` | Call `plan_require_same_repo` (§3.3) |
| `scripts/session-start.sh` | Plugin-root line (§3.2) |
| `scripts/plan-lint` | Rule 5 (§4.4) |
| `scripts/task-brief` | Delegated set from `plan_delegated`; `--header` reasons (§4.5) |
| `scripts/review-route` | `--final`, `--final-fix` (§5) |
| `skills/using-superpowers/SKILL.md` | Contract; Process Depth delegation |
| `skills/writing-plans/SKILL.md` | Execution-line rule (§4.3); plugin-root wording |
| `skills/executing-plans/SKILL.md` | Preflight trigger; kinds table; Final Review; plugin-root wording |
| `skills/subagent-driven-development/SKILL.md` | Seats table; ledger `Final fix:` line; M7 recovery row; plugin-root wording |
| `skills/subagent-driven-development/references/escalation.md` | M7 sentence |
| `skills/handoff`, `resume-execution`, `project-status`, `brainstorming`, `finishing-a-development-branch` | Plugin-root wording |
| `reference/final-review.md` | Steps 1 and fix wave (§5) |
| `reference/delegated-task.md` | Delegation reasons; plugin-root wording |
| `scripts/lib/codex-session.sh` | Comment |
| `agents/judge-fable.md`, `agents/judge-opus.md` | Descriptions |
| `README.md` | Execution-mode and final-review prose |
| Both manifests | 1.11.1 -> 1.12.0 |

## 8. The preceding batch (1.11.1, not in this plan)

Implemented inline on its own branch before this plan, with no plan document:

- **I3** `codex-gate` with no session id prints `review=false lane=false` and
  keeps the probe's `usable` and `reason`; a test with `trust` pass; the
  dependency documented in `reference/external-executor.md`.
- **M5** `lib/context.sh:54,62` read `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects`;
  a test.
- **M1** `writing-plans/SKILL.md:253` and `README.md:131-134`.
- **M8** `resume-execution` step 5 checks the ledger for a left-inline line
  before choosing the skill.
- **M9** `executing-plans` step 8 runs `context-size` only after the last task.
- **M11** `README.md:18` (both budgets) and `lib/snapshot.sh:7` (entry-point
  size).
- **M12** `legacy-names.md` adds `judge-sonnet-high`.
- **M13** `--refresh` named in `writing-plans` §Lint and Review and
  `delegated-task.md` §3.

This design's plan branches from the batch's merge.

## 9. Approaches considered

- **I1: the plan path decides.** Rejected: two rules (plan-taking scripts by
  plan, `repo-audit` and `context-size` by working directory), and a plan path
  into the primary checkout from a worktree silently puts the ledger there and
  diffs the wrong history.
- **I1: wording only.** Rejected: leaves `plan_amendments_file` and
  `sdd-workspace` disagreeing on mismatched paths.
- **I4: always delegate total-4 tasks.** Rejected: a plan mostly of total-4
  tasks becomes many seats where one Opus session is cheaper.
- **I4: a `plan-lint` note only.** Rejected: a total-4 task has exhausted its
  reducible axes, so the writer has nothing to act on.
- **I4: count total-4 delegation toward subagent mode, or preflight on it.**
  Rejected: pushes plans back into the modes SP10 moved them out of.
- **I5: Fable always, as a named agent.** Rejected: twice the price on plans
  that are not intricate.
- **I5: Opus always.** Rejected: an intricate plan with Codex off would get no
  whole-branch Fable reading.
- **I2: always `impl-sonnet-high`, or always `impl-opus-medium`.** Rejected:
  the fix wave has no second wave or escalation, so the tier should follow the
  work.

## 10. Testing

Bash suites under `plugins/dr-superpowers/tests/`, each with its own temporary
repositories; no model calls.

- **Contract.** A plan in repository X with the working directory in repository
  Y: `sdd-workspace`, `review-package` and `next-step` exit 2 with the message;
  no `.superpowers/` directory is created in either. A linked worktree given its
  primary checkout's plan path: exit 2. The same-repository cases keep passing.
- **`plan_delegated`.** 6 tasks with one total-4: delegated. 6 tasks with two
  total-4: delegated. 6 tasks with three total-4: none delegated. A split task
  with a total-4 part. Heavy and four-band together.
- **`plan-lint` rule 5.** Every row of §4.4, including `haiku` and `fable`
  inline, a subagent line at `opus`, effort below and above the required one,
  and the NOTE reasons. The existing rule-5 cases updated for the NOTE format.
- **`task-brief`.** Dispatch line for a delegated four-band task; `--header`
  reasons; no line for four-band tasks past the third.
- **Preflight trigger** (structural, `inline-mode` suite): the Setup prose keys
  on a `(heavy)` entry.
- **`review-route --final`.** Intricate by risk 3, intricate by total 6, plain.
- **`review-route --final-fix`.** Floor; ceiling; the highest of two matched
  tasks; an escalated agent from the ledger; an unmatched file; a `:line-range`
  suffix; an amended Files block; an `inline` implementer.
- **M7** (structural): the recovery row and `escalation.md` name both ranks.
- `tests/ladder.test.sh` unchanged.

## 11. Verification

- `node scripts/validate-repository.mjs`
- `node scripts/test-all.mjs` and `for t in plugins/dr-superpowers/tests/*.test.sh; do bash "$t"; done`,
  each bounded by `timeout`
- `claude plugin validate` on the marketplace and every Claude plugin
- Known environment failure: `tests/ui-discovery.test.mjs` needs `rg` on PATH.

## 12. Out of scope

- M3 (a leftover Evaluation line above `#### Part A`) and a split-then-re-lint
  test: deferred.
- M4, M6, M10's section merge, M14, rewriting prose pins, and linting historical
  plans: rejected (Appendix A).
- Paths with spaces or non-ASCII characters: deferred.
- Moving `~/.claude/dr-superpowers` state under `CLAUDE_CONFIG_DIR`: writer and
  reader already agree.
- Measuring usage after SP10 or this change.
- Codex-host plans and `reference/native-codex.md`.

## Appendix A. Triage (checked 2026-09-17)

| ID | Real? | Ruling | Evidence |
|---|---|---|---|
| I1 | Yes; fails loudly rather than silently | §3 | Scripts use the working directory; `plan_amendments_file` the plan's; the installed cache is not a git repository |
| I2 | Yes | §5.2 | `final-review.md:70-71` names no agent |
| I3 | Yes; dormant (trust pending, id set under Claude Code) | Batch §8 | `codex-gate:79-82` vs `review-route:151`, `plan-lint:249` |
| I4 | Yes; SP10 §4.2 by design | §4 | `plan-lint:287-289` |
| I5 | Yes; deferred by SP10 §12 | §5.1 | `final-review.md:32-33` |
| M1 | Yes | Batch | `writing-plans:253`, `README:131-134` |
| M2 | Yes | §4.4 | `plan-lint:116` regex; no subagent or effort-tier check |
| M3 | Possible; over-routes, never under-routes | Deferred | Splits rewrite the body (`ruling-prompt.md:68-72`) |
| M4 | No | Rejected | Amendments may not touch the Execution line or task headings (`ruling-prompt.md:66-67`) |
| M5 | Yes; narrower (the record path works) | Batch | `context.sh:54,62` |
| M6 | Harmless; gaps, never collisions | Rejected | `plan-amend:64` takes max + 1 |
| M7 | Yes | §6 | `subagent-driven-development/SKILL.md:304` |
| M8 | Yes | Batch | `resume-execution:46-49`, `executing-plans:230` |
| M9 | Yes; mild | Batch | `executing-plans:262,298` duplicate the next brief's budget line |
| M10 | Not a defect | Rejected | The two Ruling Seat sections differ by mode; a session loads one; the parenthetical goes with §3.2 |
| M11 | Partly | Batch | `README:18`, `snapshot.sh:7` stale; `README:408` accurate; `session-budget.md:16` not stale |
| M12 | Yes; trivial | Batch | `legacy-names.md:53-73` |
| M13 | Yes | Batch | `codex-gate:46-47` keeps an epoch-less `false` all session |
| M14 | Not a defect | Rejected | A missing host prerequisite before a run is not a mid-run stall |
| Test gaps | Mixed | §10, §8 | Kept: cross-repository, trust pass without session id, `CLAUDE_CONFIG_DIR`. Deferred: split re-lint, special paths. Rejected: prose-pin rewrite, linting historical plans |
