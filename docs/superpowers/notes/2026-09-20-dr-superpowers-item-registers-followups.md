# Item registers — follow-ups left open

Plan `docs/superpowers/plans/2026-09-20-dr-superpowers-item-registers.md`, merged at `ddb5ed4`. No register covers this plan's own spec, so the open work is listed here rather than as rows.

## Deferred minors

- Task 5: the `register set` calls in `tests/next-step.test.sh` (around lines 558-567) have unchecked exit status.
- Task 5: no test builds two covering registers with open rows, so the `reg_list` comma join and the cross-register count in `scripts/next-step` are untested.
- Task 5: the `+N more` suffix has no separator, so four open rows read `#16 Stale note +1 more`.
- Task 5: `scripts/next-step` takes `assigned` from the first open row only, so a register mixing assignments routes to whichever row comes first.
- Task 5: the register branch of `scripts/next-step` drops the `; sub-project k of n is done` suffix that its sibling branches carry.
- Task 5: two near-identical header-path `sed` extractions in `scripts/next-step`; make a `lib/plan.sh` helper at a third use.
- Final review 6: `register set` and `register add` rewrite a CRLF register as LF.
- Final review 8: `lib/register.sh` admits identifier 0 as a row while `register check` rejects it.
- Final review 9: the short-row message in `register check` miscounts a row that lacks its trailing pipe.
- Final review 11: `plan-lint` scans `**Items:**` across the whole plan, not per task.
- Final review 14: the "open rows" message is phrased differently in `next-step` and in the finishing skill, and there is no `register new` verb, so a register's header is still written by hand.
- Final review 15: no test covers two covering registers with open rows (same gap as the Task 5 entry above).

## Discovered

- Task 6: `tests/plan-lint.test.sh` takes about 4m20s on this machine, so a 120s or 200s bound kills it silently.
- Task 12: `tests/budget-line.test.sh` hardcodes a 465k window where this machine's `autoCompactWindow` of 650000 gives 790k, so three assertions fail (identical at the base commit before this plan).
