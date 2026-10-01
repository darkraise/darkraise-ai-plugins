# r-code-execution-cost

Source: the final-review fix commit `d17b1f0`, reviewed at head `be03aeb`.

## D1: the README still sends every judgment call to judge-fable

- Where: `plugins/dr-superpowers/README.md`, "Small-model planning"
- Defect: the branch routes the ruling seat by stakes, `judge-opus` for routine items and `judge-fable` for critical ones, as `review-route --ruling` prints, but the README still says judgment calls go to a ruling seat named `judge-fable`.
- Evidence: `d17b1f0` rewrites the sentence to name both seats and `review-route --ruling`.
- Minimum severity: Important

## D2: executing-plans says Executor lines are inert although delegated tasks read them

- Where: `plugins/dr-superpowers/skills/executing-plans/SKILL.md`, "Resolve legacy names"
- Defect: the skill says "`**Executor:**` lines are inert in this mode: nothing goes to an external executor", but the branch makes an inline plan delegate tasks, and a delegated task's Executor line is read by `delegated-task.md` §1.
- Evidence: `d17b1f0` narrows it to "inert for the tasks you implement; a delegated task's is read by delegated-task.md §1".
- Minimum severity: Important

## D3: the example transcript dispatches judge-fable for task reviews

- Where: `plugins/dr-superpowers/skills/subagent-driven-development/SKILL.md`, the example run
- Defect: the worked example dispatches `judge-fable` to review each task, but task reviews are routed by `scripts/review-route`, which prints `judge-sonnet-high` for these tasks.
- Evidence: `d17b1f0` rewrites both example lines to run `review-route --task` and dispatch `judge-sonnet-high`.
- Minimum severity: Important

## D4: the controller's budget-line example shows the wrong budget

- Where: `plugins/dr-superpowers/skills/subagent-driven-development/SKILL.md`, "Session Budget"
- Defect: the example budget line reads `312k of 475k (65%)`, the budget of a session that is not controlling a subagent-mode plan; a subagent-mode controller's budget is 350,000 tokens per `reference/session-budget.md`.
- Evidence: `d17b1f0` changes the example to `312k of 350k (89%)`.
- Minimum severity: Important
