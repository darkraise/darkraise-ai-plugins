# Controller model evaluation harness

Decides whether dforge's subagent-mode controller should move from
`claude --model sonnet --effort high` to Opus 5.5 at `low`. The question, the
evidence and the decision rules are in
`docs/superpowers/notes/2026-10-17-controller-model-eval.md`.

This is Stage 1 of that note: it reads Claude Code transcripts and calls no
model. Stage 2, the controlled replay, is planned only if Stage 1 ends
`ambiguous`. POSIX only.

## Commands

Run them from the repository root.

| Command | What it does |
|---|---|
| `node evals/controller/measure.mjs --plan SLUG --repo PATH` | The controller metrics of one plan's controller sessions in the repository at PATH, as JSON |
| `node evals/controller/measure.mjs --session FILE ...` | The same for named transcripts |
| `node evals/controller/pilot-report.mjs` | One row per plan in `pilot.tsv`, then `stage1: keep, switch, ambiguous or incomplete` |
| `node --test evals/controller/tests/*.test.mjs` | The harness tests |

## Running the pilot

For each of the next 6 subagent-mode plans, alternating and starting with
`opus@low`:

1. Add a row to `pilot.tsv`: the plan's repository-relative path, its
   repository (a sibling directory name of this repository, or an absolute
   path), the arm, and a note.
2. For an `opus@low` row, change the plan's `**Execution:**` line to
   `claude --model opus --effort low` and commit it before the first execution
   session. Every handoff and resume guide takes its launch command from that
   line, so changing only the first launch would put later sessions back on
   Sonnet. `plan-lint` only warns about the override. Leave a `sonnet@high`
   plan's line as it is.
3. Execute each plan in sessions of its own: a session that also executes
   another plan cannot be priced per plan.
4. When all 6 plans are done, run `pilot-report.mjs`. On `ambiguous`, plan
   Stage 2.

A plan's controller sessions are the repository's transcripts, its worktrees'
included, that invoked `subagent-driven-development` and ran `task-brief`,
`review-route` or `review-package` on that plan. A plan is complete when every
`### Task N` heading of the plan, as committed at the repository's `HEAD`, has a
`Task N: complete (` ledger line written in those sessions; a line the auto run
marked `deferred by the auto run` does not count.

Only rows whose `status` is `ok` enter the decision:

| Status | Meaning |
|---|---|
| `ok` | Measured and usable |
| `no-sessions` | No controller session found yet |
| `shared` | A session also executed another plan, so its cost cannot be split |
| `mismatch` | A controller session ran on a model or effort other than the arm's |
| `unpriced` | A model has no price in `lib/transcript.mjs` |
| `no-plan` | The plan cannot be read at the repository's `HEAD`, or has no task |

## Metrics

| Metric | Meaning |
|---|---|
| `controllerCost`, `subagentCost` | Transcript tokens priced per meter at the rates in `lib/transcript.mjs` |
| `dispatches` | Agent dispatches plus Codex task and review runs |
| `calls` | Controller API calls, one per message; the note's baseline is 5.8 per dispatch |
| `costPerDispatch` | `controllerCost / dispatches` |
| `sleeps`, `listAgents` | Busy-wait calls: bare `sleep N` commands and ListAgents calls |
| `nudges` | Messages typed by a person asking about status or running work |
| `seatMisses` | Routes `review-route` printed whose next review (or, for a final fix, next implementer) dispatch went to another seat, or never came |
| `inFlight` | Background launches still running at a handoff or at the end of a session, as `scripts/in-flight` counts them |

A plan's failures are `inFlight + seatMisses + nudges`, plus one when
`sleeps + listAgents` reaches 20.

## Environment

| Variable | Default |
|---|---|
| `CONTROLLER_EVAL_PROJECTS` | `~/.claude/projects` |
| `CONTROLLER_EVAL_REPOS` | the directory holding this repository |
| `CONTROLLER_EVAL_DATA` | `evals/controller` |
