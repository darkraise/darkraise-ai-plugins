# Drafter measurement — 2026-10-25

**Decision:** typed

**Untyped dispatch resolves to:** general-purpose

Subject: tasks 1-6 of `docs/dforge/plans/2026-10-24-ui-ux-skill.md` at `6df85ec4`, trimmed to its header and Task index rows 1-6, drafted as slices 1-2, 3-4 and 5-6. Each parent ran `claude --model opus --effort high`, read the spec, the trimmed plan and the drafter prompt, then dispatched the three drafters in one message. Prices in USD per million tokens (platform.claude.com pricing, 2026-10-25), input / 5-minute write / 1-hour write / cache read / output: Opus 5.5 4 / 5 / 8 / 0.20 / 20; Sonnet 5.5 2 / 2.50 / 4 / 0.10 / 10.

| Run | USD total | USD per task | Lint errors (excluding assignment lines) | Lint warnings | Review Critical | Review Important | Messages |
|---|---|---|---|---|---|---|---|
| fork | 6.60 | 1.10 | 0 | 0 | 2 | 5 | 92 |
| typed | 4.20 | 0.70 | 0 | 0 | 2 | 5 | 89 |

Decision rule (spec §4): the typed drafter wins unless it costs more per task than the fork, or its review finds a Critical the fork's does not, or more than one Important finding beyond the fork's; a tie goes to the typed drafter. The typed drafter costs less per task (0.70 against 1.10 USD), both of its Criticals are raised by the fork's review, and its Important count equals the fork's (5 against 5), so it wins.

## Notes

- Config directory `/root/.claude-alt2` for every nested session (its `model` setting was `opus[1m]` before and after). No NEEDS_CONTEXT or BLOCKED reports, no re-dispatches, and `unpriced` was empty for both runs. The fork run's `agents` output showed three `fork` drafters and the typed run's three `drafter-sonnet`; the typed run priced 5 Opus messages (the parent) and 84 Sonnet messages. The nested sessions ran without `--plugin-dir`.
- Fork review Critical 1: the plan stops after Task 6 while its header promises nineteen tasks, so most of the spec has no task (an effect of the trimmed subject).
- Fork review Critical 2: plan-lint reports 12 ERRORs because no task has `**Implementer:**` or `**Evaluation:**` lines; the drafter prompt omits them by design, and the session scores the tasks after joining.
- Typed review Critical 1: the same truncation (header promises nineteen tasks, the index lists six).
- Typed review Critical 2: spec coverage, listing the pieces no task builds. Same root cause as the truncation, and the fork's first Critical lists the same missing parts.
- Reviews are single Opus medium-effort rounds; the Important lists differ in content and cover Tasks 1-6 in both runs.
