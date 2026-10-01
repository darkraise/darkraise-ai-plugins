# dr-superpowers tier evaluation

Date: 2026-10-01
Status: design, owner-approved section by section on 2026-10-01.
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
- Claude Code 2.1.286 has `--model`, `--effort`, `--tools`,
  `--append-system-prompt-file`, `--setting-sources`, `--output-format json`,
  `--no-session-persistence` and `--max-budget-usd` (`claude --help`).
  `--bare` skips keychain reads, so it is not usable with subscription login.
- In the plans from 2026-09-14 onward, 145 of 153 tasks score 0 on spec
  completeness, 8 score 1 and none score 2: the plan supplies the code and the
  tests verbatim. An as-written replay therefore measures transcription,
  verification discipline and cost, not problem-solving.
- Across the ten completed plans dated 2026-09-15 to 2026-09-30 listed in
  `docs/superpowers/plans/completed.md`, 106 of 112 planned
  `git commit -m` messages match a commit in the log, so a task maps to its
  commit mechanically.
- Those ten plans hold 3, 7, 18, 45, 34 and 12 tasks at totals 0 to 5 and
  none at total 6. After stripping and re-scoring (below), 3, 8, 7, 6 and 0
  tasks fall on rows 2 to 6.
- Anthropic's guidance: Sonnet 5.5 at `medium` for well-specified agentic
  coding and `high` for harder or longer tasks, `xhigh`/`max` only where evals
  show a gain; Opus 5.5 defaults to `medium` and should get a fresh effort
  sweep. Source: <https://platform.claude.com/docs/en/build-with-claude/effort>.

## 1. Implementation cases

### Eligibility

A task is eligible when all of these hold:

- its plan is one of the ten completed plans above;
- it has exactly one `**Evaluation:**` line (not split into parts);
- its planned commit message matches exactly one commit (the *result commit*;
  its parent is the *base commit*);
- its `**Files:**` block names at least one `- Test:` file;
- the brief builds: `scripts/task-brief` at the eval's starting commit exits
  0 on the plan file as it stood at the base commit;
- the golden check passes: the grader (§3) passes on the result commit's tree
  and fails on the base commit's tree. Both checks are free.

### The two pools

**As-written.** The brief is the task text and the plan header's Global
Constraints and Contracts, as `scripts/task-brief` produces them. The case's
row is the task's recorded total.

**Stripped.** The brief is the same text with every fenced code block removed
whose lines match lines the result commit added to non-test files; a block
counts as matching when at least half of its non-blank lines appear among
those added lines. Test code and the `**Interfaces:**` block stay. Stripping
raises spec completeness to 2, so the task is re-scored as
`files + 2 + coupling + risk` and filed under that total. A stripped case is
kept only when the task's recorded spec is 0 or 1, at least one block was
removed, and `files + coupling <= 1`, so the re-scored task still satisfies
Rule S. The snapshot of a stripped case has `docs/superpowers/` deleted, so
the plan's code cannot be read from disk.

### Selection

Per row and pool, at most 8 cases. Eligible tasks are ordered by plan date
and task number and taken round-robin across plans. The result is
`evals/tiers/cases/manifest.tsv`, committed before any paid run. Its header
records the eval's starting commit: the commit the agent bodies, prompt
templates and `scripts/task-brief` are read from for every run. A case is
never added or dropped after results exist, except a case whose run cannot
start for a harness reason, which is recorded as excluded with the reason.

### Arms

The current agent is listed first.

| Row | Arms | As-written cases | Stripped cases |
|---|---|---|---|
| 0 | `impl-haiku`, `impl-sonnet-low` | up to 3 | - |
| 1 | `impl-sonnet-low`, `impl-haiku` | up to 7 | - |
| 2 | `impl-sonnet-medium`, `impl-sonnet-low` | 8 | up to 3 |
| 3 | `impl-sonnet-high`, `impl-sonnet-medium` | 8 | 8 |
| 4 | `impl-sonnet-high`, `impl-sonnet-medium` | 8 | up to 7 |
| 5 | `impl-opus-medium`, `impl-opus-low`, `impl-sonnet-high` | 8 | up to 6 |
| 6 | none | 0 | 0 |

The counts are ceilings from the Evaluation lines; the golden check can lower
them. `impl-sonnet-xhigh` is not an arm in the first repetition; it enters
the second only if `impl-sonnet-high` regresses on row 5.

## 2. Review cases

Ten cases, each with a rubric of its known defects written and committed
under `evals/tiers/cases/reviews/` before any paid run.

- **Code review (6).** Final-review fix commits `fb05b23` (with `6d54b1e`),
  `58885f9`, `16752f6`, `ddb5ed4`, `d17b1f0`, `dea77c5`. Base is the branch's
  start, head is the commit before the fix, and the rubric lists the defects
  the fix commit closed. The prompt is
  `skills/requesting-code-review/references/code-reviewer.md` with a pre-built
  diff file.
- **Plan review (4).** The calibration replays from
  `docs/superpowers/notes/2026-09-20-review-routing-calibration.md`:
  `project-state` at `d6c288c` (the cross-task `absent` helper, the vacuous
  needles, and the `repo-audit` working-directory defect), `judge-seats` at
  `01f5a2a`, `inline-mode` at `69c6b48`, `small-model` at `5e96f14`. The
  prompt is `skills/writing-plans/references/plan-reviewer-prompt.md`,
  round 1, with the plan's first
  `**Plan review:**` line stripped as that procedure does.

Arms: `judge-opus` at `high` (current), `judge-opus` at `medium`,
`judge-sonnet-high`.

## 3. Grading

### Implementation runs

The grader, with no model call:

1. overwrites the task's `- Test:` files with the result commit's versions;
2. runs each of them under a timeout;
3. lists the files changed against the snapshot's initial commit, committed
   or not, and compares them with the task's `**Files:**` list;
4. reads the status word from the agent's final message.

| Outcome | Condition |
|---|---|
| `PASS` | tests pass, no file outside the list changed, status `DONE` or `DONE_WITH_CONCERNS` |
| `FAIL` | tests fail, or a file outside the list changed, with status `DONE` or `DONE_WITH_CONCERNS` |
| `BLOCKED` | status `BLOCKED` or `NEEDS_CONTEXT`, no status word, or the run hit its timeout |
| `NOT_RUN` | a rate limit or a harness error |

`NOT_RUN` cells are retried and never scored. Every row of
`results.tsv` also records the reported model, notional cost, duration and
turn count.

### Review runs

A grader on Opus 5.5 at `low` reads the review and the case rubric and, per
rubric defect, answers found or not found, quoting the finding it matched and
the severity the review gave it. A defect a later commit fixed should be
graded at least Important; a lower grade is recorded as under-graded, not as
a miss. Findings outside the rubric are listed for spot-checking and not
scored. Six review outputs are graded twice; if the two gradings disagree on
more than one defect in total, the grader prompt is fixed and every review is
re-graded before any decision is read off.

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

**Rows 0 and 1** compare Haiku 4.5 and Sonnet 5.5 at `low` in both
directions under the same rule: row 0 moves up to `impl-sonnet-low` only if
`impl-haiku` fails a case `impl-sonnet-low` passes; row 1 moves down to
`impl-haiku` only with no regression and a lower cost per `PASS`.

**A review seat** moves to a cheaper arm when that arm's pooled recall over
all rubric defects is at least the current judge's and it misses no defect
the current judge found and graded Critical. `judge-opus` at `medium`
replacing `high` changes the agent's effort; `judge-sonnet-high` matching
`judge-opus` at `high` supports raising the task-review band boundary above
total 3. That second inference is indirect, because no per-task review has a
recorded answer key, and the results note says so.

**Not measured, ruled by the owner from the results:**

- Row 6 has no case. It stays `impl-opus-high` unless the owner rules
  otherwise on seeing row 5.
- The escalation table is derived from the new assignment table by the
  existing model-before-effort rule and changes only if the set of execution
  agents changes.

**What one repetition can show.** At most 16 paired trials per row and arm.
Zero regressions in 16 trials is consistent with a true regression rate up to
about 19% (rule of three); the results note states this bound beside every
proposed move.

## 5. Harness

All under `evals/tiers/` at the repository root: outside `plugins/`, so it
does not ship with any plugin and needs no catalog entry.

| Path | Purpose |
|---|---|
| `cases/manifest.tsv` | case id, plan, task, base commit, result commit, row, pool |
| `cases/reviews/<case>/` | rubric and case description per review case |
| `build-case` | snapshot and brief for one case; runs the golden check |
| `run-case` | one `claude -p` call for one case on one arm |
| `grade-case` | the implementation grader of §3 |
| `grade-review` | the review grader of §3 |
| `run-grid` | runs a stage's cells; resumable |
| `report` | `results/results.tsv` to the per-row decision table |
| `tests/*.test.sh` | harness tests against a stub `claude` on `PATH` |
| `results/results.tsv` | one line per run; committed |

Raw transcripts and snapshots live outside the repository in a scratch
directory and are not committed.

**A run.** `build-case` writes a `git archive` of the base commit into a
scratch directory, initialises a fresh repository there with one commit, and
writes the brief. `run-case` then calls, from that directory:

```
claude -p --model <model> --effort <effort> \
  --append-system-prompt-file <agent body> --setting-sources project \
  --tools <tool list> --output-format json --no-session-persistence \
  --max-budget-usd <cap> < prompt
```

- The agent body is `plugins/dr-superpowers/agents/<name>.md` at the eval's
  starting commit, frontmatter removed; `<model>` and `<effort>` come from the
  arm. `--effort` is omitted for `impl-haiku`, whose agent sets none.
- The prompt is the production template:
  `skills/subagent-driven-development/references/implementer-prompt.md` for
  implementation runs, with the brief path and the snapshot as the working
  directory, and the two templates §2 names for review runs.
- Implementation runs get the file and shell tools; review runs get `Read`,
  `Grep` and `Glob`.
- `--setting-sources project` keeps user-level plugins, hooks and global
  instructions out of the run while keeping the subscription login.

**Limits.** Concurrency 2. A wall-clock timeout per run, 30 minutes for
implementation and 20 for review, after which the harness kills the process
tree. `--max-budget-usd` 5 per run. `run-grid` stops when the notional cost
summed over every run of the first repetition, all stages together, reaches
250, and at the first rate-limit error, which it
records as `NOT_RUN`; the next invocation resumes at the first cell without a
scored result.

**Harness tests** run the scripts against a stub `claude` that returns
canned JSON, covering: a pass, a failing test, an out-of-scope file, a
blocked report, a rate-limit stop and resume, the stripped-brief rule, and
both halves of the golden check. They make no model call.

## 6. Stages of the paid run

Run in a fresh session. Each stage ends with a short report, and the owner
can stop between stages.

1. **Smoke, 6 runs.** One implementation run on Haiku, Sonnet and Opus, and
   one review run on Sonnet and Opus, plus one review grading. It must
   confirm three assumptions, and the run stops for a harness fix if any
   fails:
   - `--model` and `--effort` take effect alongside an appended system
     prompt (the JSON names the model; whether it names the effort is unknown
     until this run);
   - `--setting-sources project` excludes the dr-superpowers session-start
     hook;
   - the historical test suites run inside a `git archive` snapshot.
   The owner reads `/usage` before and after to get the share of the limit
   per run.
2. **As-written pool**, about 92 runs.
3. **Stripped pool**, about 54 runs.
4. **Review cases**, 30 runs and 30 gradings plus 6 repeat gradings.
5. **Report.** `docs/superpowers/notes/YYYY-MM-DD-tier-eval-results.md`,
   dated the day it is written: the
   per-row table, every regression with its case id, the mapping the rules of
   §4 produce, and the rows proposed for a second repetition.

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
  review seat, move, unchanged or inconclusive under §4.
