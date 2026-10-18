# Opus 5.5 effort sweep — eval design (not yet run)

Written 2026-09-23. Status: superseded, never run. Its seat table predates
`judge-opus` moving to `medium` on 2026-10-02, and the controller's model and
effort were settled on 2026-10-18 in
`docs/superpowers/research/reports/Sonnet high versus Opus low controller.md`.

## Why

Anthropic's guidance for Claude Opus 5.5 is to run an effort sweep on your own
evals rather than carry settings over from Opus 5: the default is `medium`,
Opus 5.5 at `medium` matches or beats Opus 5 at `high` on coding and knowledge
work, and at a given level it thinks more than Opus 5 did.

- <https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-opus-5-5> (§Calibrate effort)
- <https://platform.claude.com/docs/en/build-with-claude/effort> (§Recommended effort levels for Claude Opus 5.5)

## What the sweep decides

The lowest effort per Opus 5.5 seat that loses no measurable quality:

| Seat | Current effort | Reaches it |
|---|---|---|
| `judge-opus` | `high` | every review and ruling seat since 1.18.0 |
| `impl-opus-low` / `-medium` / `-high` | `low` / `medium` / `high` | tasks scoring 4 / 5 / 6 |
| main interactive session | `high` (`/effort`) | covered by the implementation cases |

## Gold corpus

Both case types come from this repository's git history, so each has a known
answer.

**Review cases (target 15-25).** A branch state before a review, plus the
defects that review confirmed and a later commit fixed; the fix commit is the
answer key.

- Final-review fix commits: `fb05b23` (+ `6d54b1e`), `58885f9`, `16752f6`,
  `ddb5ed4`, `d17b1f0`, `dea77c5`. For each, base = the branch's start, head =
  the commit before the fix.
- The four plan-review calibration replays from
  `2026-09-20-review-routing-calibration.md`: `project-state` at `d6c288c`
  (planted defects: the `absent` helper defined in Task 3 and used only by
  Task 11; vacuous needles `"CLAUDE.md"`, `"optional"`, `'seven'`,
  `'exit 0'`; plus the verified Task 2 "run `repo-audit` from the plugin root"
  Critical), `judge-seats` at `01f5a2a`, `inline-mode` at `69c6b48`,
  `small-model` at `5e96f14`.

**Implementation cases (target 10-15).** Tasks from completed plans with a
total of 4-6. The implementer gets the `scripts/task-brief` output in a
snapshot at the task's base commit; the grader runs the tests from the task's
historical commit against the result as hidden tests, and checks the diff
stays inside the task's `**Files:**` list.

## Runner

One call per case × effort × repetition, in a `git archive` snapshot of the
base commit so no later fix leaks in:

```
claude -p --model claude-opus-5-5 --effort <low|medium|high|xhigh> \
  --tools Read,Grep,Glob --append-system-prompt-file <seat agent body> \
  --output-format json --no-session-persistence --max-budget-usd <cap> < prompt
```

- Prompts are the production templates: `plan-reviewer-prompt.md` (round 1),
  `requesting-code-review/references/code-reviewer.md` with a pre-built diff
  file, `implementer-prompt.md`.
- Plan replays strip the plan's first `**Plan review:**` line, as the
  calibration procedure does (review-routing plan, Task 10 Step 1).
- Implementation runs get write tools and a disposable worktree instead.
- The JSON output gives the answer text, `total_cost_usd`, duration and turn
  count; append one line per run to a results file.
- All flags above exist in Claude Code 2.1.280 (`claude --help`).

## Grading

- **Reviews:** recall of known defects, graded by Opus 5.5 at `low` against a
  per-case rubric and required to quote the matching finding; severity check
  (a defect that was fixed should be at least Important); findings outside the
  rubric listed for spot-checking, not scored; grader consistency checked by
  grading a sample twice.
- **Implementation:** hidden-test pass rate, scope, and cost per *completed*
  task (a run that later needs escalation is not cheaper).

## Size, repetitions, decision rule

- Sweep `low`, `medium`, `high`, `xhigh`; add `max` only if `xhigh` beats
  `high`. Every level runs the same cases (paired comparison).
- Noise floor ≈ `1/sqrt(cases × reps)` on a pass rate (claude-api skill,
  `shared/evals/eval-audit.md` §5): 20 cases × 3 reps resolves only about ±13
  points.
- Decision: per seat, the lowest effort within the noise floor of the best
  level, with severity grading holding. Not simply the top scorer.

## Cost and pilot

Measured on the 2026-09-23 judge replay at `high`: 107k-129k tokens and
3-4 minutes per review. Full grid (20 × 4 levels × 3 reps = 240 runs) is
roughly 30M tokens (inference; lower effort uses less).

Pilot first: 8 review cases × `low` / `medium` / `high` × 2 reps = 48 runs,
about 5M tokens. It proves the harness and shows whether effort matters for
reviews at all; expand only if it shows a gap worth resolving.

## Baseline already measured

2026-09-23 replay, both seats at `high`, one run each (darkmem has the
details):

- Plan review, `project-state` at `d6c288c`: Opus 5.5 found the helper defect
  (graded Minor) and the needles on instance; Fable 5.1 found the helper
  (Important) and the needles on substance; neither found the `repo-audit`
  Critical.
- Code review, `judge-seats` at `f88429b`: Opus 5.5 found the unanchored
  refusal search, the banner-line refusal reason and the weakened risk-3
  check; Fable 5.1 found only the refusal search.

## Open decisions before running

1. Where the harness lives: committed `evals/effort/` or scratch.
2. Scope: review pilot only, or pilot then implementation cases.
3. Usage budget for the run.
