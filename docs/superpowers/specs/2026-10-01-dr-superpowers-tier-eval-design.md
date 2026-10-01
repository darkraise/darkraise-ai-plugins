# dr-superpowers tier evaluation

Date: 2026-10-01
Status: design, owner-approved section by section on 2026-10-01; revised the
same day from the free prototype run (§Revision).
Register: `docs/superpowers/registers/2026-10-01-tier-reevaluation.md` row 1.
Row 2 (the mapping table update) gets its own spec once this eval has results.
Precedent: `docs/superpowers/specs/2026-09-29-dr-superpowers-sonnet-5-5-design.md`,
which moved score 4 to Sonnet 5.5 and declined two further moves for lack of
a measurement from this repository.
Supersedes the open decisions in the untracked note
`docs/superpowers/notes/2026-09-23-opus-5-5-effort-eval-design.md`; its review
corpus and runner shape are reused here.

## Rulings (owner, 2026-10-01)

1. **Measure before moving.** A paid pilot on this repository's own history,
   chosen over re-deriving the table from published figures.
2. **Everything is in scope:** implementer rows 0 to 6, the review seats, and
   the escalation targets.
3. **Two case pools:** each past task as the plan wrote it, and a stripped
   variant with the implementation code removed.
4. **One repetition, then decide** on a second for inconclusive rows.
5. **No paid run in the design session.** That session writes this spec and
   the plan, builds the harness, and hands off; the eval runs in a fresh
   session that does not share the 5-hour usage window with other sessions.

## Facts this design rests on

- The CLI is logged in through claude.ai on a Max plan with no API key set
  (`claude auth status`, 2026-10-01). `claude -p` draws from the subscription's
  usage limits; the separate Agent SDK credit announced for 2026-06-15 was
  paused. Source:
  <https://support.claude.com/en/articles/15036540-use-the-claude-agent-sdk-with-your-claude-plan>
  (updated 2026-06-16). Dollar figures below are the notional API prices the
  CLI reports in `total_cost_usd`; nothing is billed per token.
- Claude Code 2.1.286 has `--model`, `--effort`, `--tools`, `--allowedTools`,
  `--permission-mode`, `--append-system-prompt-file`, `--setting-sources`,
  `--output-format json`, `--no-session-persistence` and `--max-budget-usd`
  (`claude --help`). `--bare` skips keychain reads, so it is not usable with
  subscription login.
- In the plans from 2026-09-14 onward, 145 of 153 tasks score 0 on spec
  completeness, 8 score 1 and none score 2: the plan supplies the code and the
  tests verbatim. An as-written replay therefore measures transcription,
  verification discipline and cost, not problem-solving.
- The plans dated 2026-09-11 to 2026-09-30 hold 201 tasks. 112 of them pass every
  eligibility rule of §1, the free golden check included (run 2026-10-01): 7,
  20, 44, 28, 12 and 1 at totals 1 to 6, and none at total 0. After stripping
  and re-scoring, 3, 6, 2 and 1 fall on rows 3 to 6.
- Anthropic's guidance: Sonnet 5.5 at `medium` for well-specified agentic
  coding and `high` for harder or longer tasks, `xhigh`/`max` only where evals
  show a gain; Opus 5.5 defaults to `medium` and should get a fresh effort
  sweep. Source: <https://platform.claude.com/docs/en/build-with-claude/effort>.

## 1. Implementation cases

### Eligibility

A task is eligible when all of these hold:

- its plan is a dated file under `docs/superpowers/plans/` from 2026-09-11,
  the day dr-superpowers became the plugin these plans build, to 2026-09-30,
  the last plan written before this eval;
- it has exactly one `**Evaluation:**` line (not split into parts);
- its text holds exactly one `git commit -m` message, and that message
  matches exactly one commit (the *result commit*; its parent is the *base
  commit*);
- its `**Files:**` block names at least one runnable test file, `*.test.sh`
  or `*.test.mjs`, whether the line is labelled Test, Modify or Create, and
  every path labelled Test is such a file;
- the brief builds: `scripts/task-brief` exits 0 on the plan file as it stood
  at the base commit;
- the golden check passes: the result commit changes no file outside the
  `**Files:**` block, the task's test files pass on the result commit's tree,
  and the same test files fail on the base commit's tree. All three are free.

### The two pools

**As-written.** The brief is the task text and the plan header's Global
Constraints and Contracts, as `scripts/task-brief` produces them from the
plan at the base commit. The case's row is the task's recorded total.

**Stripped.** The brief is the same text with every fenced code block removed
when more than half of its non-blank lines are lines the result commit added
to files outside every `tests/` directory. Test code and the `**Interfaces:**`
block stay. Stripping raises spec completeness to 2, so the task is re-scored
as `files + 2 + coupling + risk` and filed under that total. A stripped case
is kept only when the task's recorded spec is 0 or 1, at least one block was
removed, and `files + coupling <= 1`, so the re-scored task still satisfies
Rule S. The snapshot of a stripped case has `docs/superpowers/` deleted, so
the plan's code cannot be read from disk.

### Selection

Per row and pool, at most 8 cases. Eligible tasks are ordered by plan name
and task number and taken round-robin across plans. The result is
`evals/tiers/cases/manifest.tsv`, committed before any paid run, with every
task left out listed beside its reason in `cases/excluded.tsv`. The
manifest's first line records the start commit: the commit whose history was
enumerated. Agent bodies, prompt templates and `scripts/task-brief` are read
from the working tree, and the grid refuses to run when
`plugins/dr-superpowers` differs from the start commit. A case is never added
or dropped after results exist, except a case whose run cannot start for a
harness reason, which is recorded as excluded with the reason.

### Arms

The current agent is listed first. The counts are those of the manifest
built on 2026-10-01.

| Row | Arms | As-written cases | Stripped cases |
|---|---|---|---|
| 0 | none | 0 | - |
| 1 | `impl-sonnet-low`, `impl-haiku` | 7 | - |
| 2 | `impl-sonnet-medium`, `impl-sonnet-low` | 8 | 0 |
| 3 | `impl-sonnet-high`, `impl-sonnet-medium` | 8 | 3 |
| 4 | `impl-sonnet-high`, `impl-sonnet-medium` | 8 | 6 |
| 5 | `impl-opus-medium`, `impl-opus-low`, `impl-sonnet-high` | 8 | 2 |
| 6 | `impl-opus-high`, `impl-opus-medium` | 1 | 1 |

No total-0 task names a test file, so row 0 has no case and no arms.
`impl-sonnet-xhigh` is not an arm in the first repetition; it enters the
second only if `impl-sonnet-high` regresses on row 5.

## 2. Review cases

Ten cases, defined in `evals/tiers/cases/reviews/cases.json`, each with a
rubric of its known defects written and committed under
`evals/tiers/cases/reviews/` before any paid run.

- **Code review (6).** Final-review fix commits `fb05b23` (with `6d54b1e`),
  `58885f9`, `16752f6`, `ddb5ed4`, `d17b1f0`, `dea77c5`. Base is the commit
  that landed the branch's plan, head is the commit before the fix, and the
  rubric lists the defects the fix commit closed. The prompt is
  `skills/requesting-code-review/references/code-reviewer.md` with a pre-built
  diff file.
- **Plan review (4).** The calibration replays from
  `docs/superpowers/notes/2026-09-20-review-routing-calibration.md`:
  `project-state` at `d6c288c` (the cross-task `absent` helper, the vacuous
  needles, and the `repo-audit` working-directory defect), `judge-seats` at
  `01f5a2a`, `inline-mode` at `69c6b48`, `small-model` at `5e96f14`. The
  prompt is `skills/writing-plans/references/plan-reviewer-prompt.md`,
  round 1, with the plan's first `**Plan review:**` line stripped as that
  procedure does. The criteria file is the current plugin's, copied into the
  snapshot, because one replay predates it; the lint file says only that
  `plan-lint` was not run, so every arm sees the same input and no arm sees
  findings of a later `plan-lint`.

Arms: `judge-opus` at `high` (current), `judge-opus` at `medium`,
`judge-sonnet-high`.

## 3. Grading

### Implementation runs

The grader, with no model call:

1. lists the files changed against the snapshot's initial commit, committed
   or not, and compares them with the task's `**Files:**` block;
2. overwrites the task's test files with the result commit's versions;
3. runs each of them under a timeout;
4. reads the status word from the agent's final message.

| Outcome | Condition |
|---|---|
| `PASS` | tests pass, no file outside the block changed, status `DONE` or `DONE_WITH_CONCERNS` |
| `FAIL` | tests fail, or a file outside the block changed, with status `DONE` or `DONE_WITH_CONCERNS` |
| `BLOCKED` | status `BLOCKED` or `NEEDS_CONTEXT`, no status word, or the run hit its timeout or its budget cap, or ended in an error after it had spent something |
| `NOT_RUN` | a rate limit, an error before the run spent anything, or a harness failure |
| `EXCLUDED` | recorded by a person, with the reason, for a case whose run cannot start; it takes the case out of the repetition for every arm |

`NOT_RUN` cells are retried and never scored. An error after spending is
`BLOCKED`, not `NOT_RUN`, so that it is not retried at full price on every
invocation. Every row of
`results.tsv` also records the reported model, notional cost, duration and
turn count.

### Review runs

A grader on Opus 5.5 at `low`, with no tools and no agent body, reads the
review and the case rubric and, per rubric defect, answers found or not
found, quoting the finding it matched and the severity the review gave it. A
defect counts as found only when that quote is really in the review. A
defect a later commit fixed should be graded at least Important; a lower
grade is counted as under-graded in the report, not as a miss. A review cell
that was cut short wrote no review and counts as missing every defect. Findings
outside the rubric are not scored; every review is kept in its run directory
for spot-checking. Grades go to
`results/review-grades.tsv`. Six review outputs are graded twice; if the two
gradings disagree on more than one defect in total, the grader prompt is
fixed and every review is re-graded under new pass numbers before any
decision is read off; the earlier grades stay in the file.

## 4. Decision rules

Fixed before the run. "Regression" means a case the current agent passes and
the candidate does not.

**An implementer row** moves to a cheaper arm when that arm has no
regression in either pool and its notional cost per `PASS` is lower. With
two cheaper arms on row 5, the cheapest arm with no regression wins. Exactly
one regression makes the row inconclusive: it does not move, and it is
proposed for the second repetition. Two or more regressions leave it
unchanged. A current agent that itself does not pass two or more of a row's
cases flags the row for a second repetition with the next agent up.

**On rows 2 to 6, a move resting on fewer than 4 stripped cases is an owner
ruling, not an automatic move.** On the 2026-10-01 manifest that is rows 2,
3, 5 and 6: the report states the move the as-written evidence supports and
the owner decides. Row 6 has two cases in all. Row 1 cannot hold a stripped
case, because a stripped task totals at least 2, so it moves on its
as-written evidence alone.

**A review seat** moves to a cheaper arm when that arm's pooled recall over
all rubric defects is at least the current judge's and it misses no defect
the current judge found and graded Critical. `judge-opus` at `medium`
replacing `high` changes the agent's effort; `judge-sonnet-high` matching
`judge-opus` at `high` supports raising the task-review band boundary above
total 3. That second inference is indirect, because no per-task review has a
recorded answer key, and the results note says so.

**Not measured, ruled by the owner from the results:**

- Row 0 has no case. It stays `impl-haiku` unless the owner rules otherwise
  on seeing how `impl-haiku` does on row 1.
- The escalation table is derived from the new assignment table by the
  existing model-before-effort rule and changes only if the set of execution
  agents changes.

**What one repetition can show.** At most 14 paired trials per row and arm.
Zero regressions in 14 trials is consistent with a true regression rate up to
about 21% (rule of three); the report states this bound beside every row.

## 5. Harness

All under `evals/tiers/` at the repository root: outside `plugins/`, so it
does not ship with any plugin and needs no catalog entry. Node, no
dependencies, POSIX only.

| Path | Purpose |
|---|---|
| `arms.json` | the arms of §1 and §2, and the grader's model and effort |
| `cases/manifest.tsv` | case id, pool, row, plan, task, base commit, result commit |
| `cases/excluded.tsv` | every task left out, with the reason |
| `cases/reviews/cases.json` | the ten review cases |
| `cases/reviews/<case>.md` | the rubric of one review case |
| `build-manifest.mjs` | enumerates, golden-checks and selects the cases |
| `build-case.mjs` | snapshot, brief and prompt for one case |
| `run-case.mjs` | one `claude -p` call for one case on one arm, then its grade |
| `grade-case.mjs` | the implementation grader of §3 |
| `grade-review.mjs` | the review grader of §3 |
| `run-grid.mjs` | runs a stage's cells; resumable |
| `report.mjs` | `results/results.tsv` to the decision table of §4 |
| `tests/*.test.mjs` | harness tests against a stub `claude` |
| `results/results.tsv` | one line per run; committed |
| `results/review-grades.tsv` | one line per rubric defect per graded review; committed |

Snapshots and transcripts live outside the repository, under
`~/.cache/dr-tier-eval`, and are not committed.

**A run.** `build-case.mjs` writes a `git archive` of the base commit into a
scratch directory, initialises a fresh repository there with one commit, and
writes the brief under `.superpowers/sdd/eval/`, where production puts it.
`run-case.mjs` then calls, from that directory:

```
claude -p --model <model> --effort <effort> \
  --append-system-prompt-file <agent body> --setting-sources project \
  --tools <tool list> --allowedTools <tool list> --permission-mode acceptEdits \
  --output-format json --no-session-persistence --max-budget-usd 5 < prompt
```

- The agent body is `plugins/dr-superpowers/agents/<name>.md` with its
  frontmatter removed; `<model>` and `<effort>` come from that frontmatter,
  and an arm written `<name>@<effort>` overrides the effort. `--effort` is
  omitted for `impl-haiku`, whose agent sets none.
- The prompt is the production template:
  `skills/subagent-driven-development/references/implementer-prompt.md` for
  implementation runs, with the brief path and the snapshot as the working
  directory, and the two templates §2 names for review runs.
- Implementation runs get `Bash`, `Edit`, `Write`, `Read`, `Grep` and `Glob`;
  review runs get `Read`, `Grep` and `Glob`.
- `--setting-sources project` keeps user-level plugins, hooks and global
  instructions out of the run while keeping the subscription login.

**Limits.** Concurrency 2. A wall-clock timeout per run, 30 minutes for
implementation and 20 for review, after which the harness kills the process
tree. `--max-budget-usd` 5 per run. `run-grid.mjs` stops when the notional
cost summed over every run of the repetition, all stages together, reaches
250, and at the first rate-limit error, which it records as `NOT_RUN`; the
next invocation resumes at the first cell without a scored result.
`--minutes M` stops starting cells after M minutes, so a long stage runs in
slices, and a signal that stops the grid kills every run it started.

**Harness tests** run the scripts against a stub `claude` that returns
canned JSON, on a throwaway fixture repository, covering: a pass, a failing
test, a rewritten test, an out-of-scope file, a blocked report, a rate-limit
stop and resume, the spend cap, the stripped-brief rule, and both halves of
the golden check. They make no model call. `scripts/test-all.mjs` runs them
on every platform but Windows.

## 6. Stages of the paid run

Run in a fresh session. Each stage ends with a short report, and the owner
can stop between stages.

1. **Smoke, 5 runs, 1 grading and 2 probes.** One implementation run on
   Haiku, Sonnet and Opus, one review run on Sonnet and Opus, and one review
   grading. They are ordinary cells of the grid, so their results count. Two
   further Haiku calls with no tools probe the CLI: one asks whether the
   session-start hook's text or the owner's global instructions reached its
   context, the other runs under a one-cent budget to record what a budget
   stop looks like. The stage must
   confirm three assumptions, and the run stops for a harness fix if any
   fails:
   - `--model` and `--effort` take effect alongside an appended system
     prompt (the JSON names the model; whether it names the effort is unknown
     until this run);
   - `--setting-sources project` excludes the dr-superpowers session-start
     hook, and the tool and permission flags let an implementation run edit
     files and run commands without a prompt;
   - the historical test suites run inside a `git archive` snapshot during a
     real run as they did in the golden check.
   The owner reads `/usage` before and after to get the share of the limit
   per run.
2. **As-written pool**, 88 runs.
3. **Stripped pool**, 26 runs.
4. **Review cases**, 30 runs and 30 gradings plus 6 repeat gradings.
5. **Report.** `docs/superpowers/notes/YYYY-MM-DD-tier-eval-results.md`,
   dated the day it is written: the output of `report.mjs`, every regression
   with its case id, the mapping the rules of §4 produce, the rulings left to
   the owner, and the rows proposed for a second repetition.

## Out of scope

- Any change to `reference/ladder.md`, `scripts/review-route`, an agent's
  `effort:` or any other shipped file. Register row 2 covers them, in a
  second spec written from the results.
- Fable tiers, the Codex lane and native Codex routing.
- A second repetition; the owner decides on it from the report.

## Acceptance

Register row 1 is done when:

- `evals/tiers/` holds the harness of §5 and its tests pass with no model
  call;
- the manifest and the ten review rubrics are committed before the first
  paid run;
- `results/results.tsv` holds a scored or excluded line for every cell of
  stages 2 to 4;
- the results note of §6 step 5 is committed and states, per row and per
  review seat, move, unchanged, inconclusive or owner ruling under §4.

## Revision

Changes made on 2026-10-01 after the section-by-section approval, each from
the free prototype run on this repository's history:

- **Plans.** Every dated plan from 2026-09-11 to 2026-09-30, not only the ten listed in
  `completed.md`: the golden check, not that list, is what proves a task
  landed. This is what gives row 6 its one case.
- **Test files.** A runnable test file counts whether labelled Test, Modify
  or Create. Plans list an existing test file under Modify, and the first
  rule left 43 of 116 tasks without a test.
- **Golden check.** Also requires that the result commit stays inside the
  `**Files:**` block, so the scope rule is one the historical run itself met.
- **Stripping.** "More than half", not "at least half": a two-line test block
  sharing one line with the implementation was being removed.
- **Pool sizes.** The stripped pool has 12 cases, not about 21, and row 0 has
  none in either pool. §1's table carries the real counts, row 0 lost its
  arms and row 6 gained two.
- **Thin evidence.** On rows 2 to 6, a move resting on fewer than 4 stripped
  cases became an owner ruling (§4), because the approved rule would
  otherwise move a row on two or three stripped cases, or on none.
- **Start commit.** The plugin is read from the working tree behind a drift
  guard, in place of reading every file at the start commit.
- **Grader.** A found defect needs a quote that is really in the review.
- **Budget cap.** A run that reaches its per-run budget is `BLOCKED`, and so
  is one that ends in an error after spending.
- **Harness failures.** A harness exception is `NOT_RUN` for that cell, and
  `EXCLUDED` exists so a person can take out a case that can never run.
- **Cut-short reviews.** A review cell with no review misses every defect,
  so every arm ends with a grade per defect.
- **Re-grading.** New pass numbers, so a grader fix does not erase grades.
- **Plan-review inputs.** A fixed lint file and the current criteria file,
  for the reasons §2 gives.
