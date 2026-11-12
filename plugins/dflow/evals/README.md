# Eval suite

Six cases, each on a decision dflow exists to get right. They need no fixture
repository: each prompt states the situation and the graders judge the reply.

| Case | Decision under test |
| --- | --- |
| `depth-none` | A small change gets no plan, and the test comes before the change |
| `lean-plan` | A plan holds decisions, signatures and assertions, and names its risk |
| `third-failure` | Three failed verifies end in a choice, not another patch or a weakened test |
| `evidence-bound-finding` | A finding is recorded with evidence that fails while the defect exists |
| `reset-ends-the-turn` | A `RESET:` line ends the turn |
| `tests-per-behaviour` | One test per behaviour; none for wording, constants or style |

## Running it

```bash
claude plugin eval plugins/dflow --runs 1 --max-cost-usd 5 --no-publish
```

The run adds a no-plugin baseline arm and reports the score delta per case. A
case with no delta is not measuring the plugin: rewrite its prompt until the
baseline fails it.

Status on 2026-11-12: only `depth-none` has been run, once per arm (with the
plugin 1.00, without 0.00). One run is a smoke test, not a measurement. The
other five cases are authored and have not been run.

## What this suite does not measure

Token cost and end-to-end output quality on real tasks. For those, build the
same plan with dflow and with another workflow in two worktrees and compare
`dflow cost` with that workflow's own figures; that comparison has not been
run.
