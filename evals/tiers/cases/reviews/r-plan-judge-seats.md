# r-plan-judge-seats

Source: defects of the plan's own code that its execution exposed, fixed by `fb05b23` and `6d54b1e` on the same branch, and the finding the calibration record `docs/superpowers/notes/2026-09-20-review-routing-calibration.md` quotes under "The findings are substantive, not padding"; each confirmed in the plan at `01f5a2a`.

## D1: the refusal search matches any line of the whole transcript

- Where: Task 4, `is_refusal` in the code for `scripts/run-codex-review.sh`
- Defect: the plan's `is_refusal` greps both whole log files, unanchored, for refusal wording and for `http 400` or `status 400`. Codex writes its session transcript to those logs, so a run that merely quotes a refusal message is declared a refusal and buys a second full round.
- Evidence: `fb05b23` restricts the search to column-0 error lines; the faulty line is at plan line 939.
- Minimum severity: Important

## D2: the refusal reason is the first line of stderr, not the refusing line

- Where: Task 4, `refusal_line`
- Defect: the plan's `refusal_line` prints the first non-empty line of stderr then stdout, which is the CLI banner, so every substitution is reported with the banner as its reason.
- Evidence: `fb05b23` makes it read the matched error line; the faulty line is at plan line 944.
- Minimum severity: Important

## D3: the test stub refuses in a form Codex never emits

- Where: Task 4, the stub's `refuse-then-ok` and `refuse-always` modes in `tests/codex-review.test.sh`
- Defect: the stub refuses with `stream error: unsupported model …`. The tests therefore pass against a matcher that misreads real output, and no case covers output that only mentions a refusal.
- Evidence: `fb05b23` changes the stub to the observed `ERROR: {"type":"error",…}` line and adds a prose-only case; the stub lines are at plan lines 809 and 812.
- Minimum severity: Important

## D4: no test proves which model reaches the command

- Where: the dry-run selection tests of `tests/codex-review.test.sh`
- Defect: both judge rows run at the same effort and the tests assert only the effort and the printed `codex-judge` line, so a runner that passed the wrong model to `-m` would pass.
- Evidence: `fb05b23` adds a token check on `-m` to each selection case; the plan at `01f5a2a` has no such check.
- Minimum severity: Important

## D5: Contracts weakens risk-3 output validation to the presence of three keys

- Where: the header's Contracts, "Valid output", and Task 4's fixture
- Defect: Contracts defines a valid risk-3 report as JSON carrying the keys `spec_verdict`, `task_quality` and `cannot_verify`, although the seat's schema, `criteria/codex-review-schema.json`, also requires the four scores and constrains the verdict values. Task 4 therefore accepts its own fixture, which has no scores and invalid verdict values, and a caller would count an unusable report as a vote.
- Evidence: calibration record, the quoted `judge-seats` finding, verified in that run; the Contracts sentence is at plan line 76.
- Minimum severity: Critical

## D6: a fail-closed selection of the fallback rung is never reported as a substitution

- Where: the task that writes the review-seat prose of `reference/external-executor.md` (plan line 1092)
- Defect: the prose tells the controller to announce a substitution only on `FALLBACK`. When the catalog does not advertise the preferred rung, selection falls closed to the last row before the run and the status line says `status=OK`, so the substitution passes unannounced.
- Evidence: `fb05b23` adds the paragraph "A status line naming the block's last row with `status=OK` is a substitution as well" to both sections.
- Minimum severity: Important
