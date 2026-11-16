# Step 1b: Prove the UI

Run `ui-proof check --base MERGE_BASE --spec <the plan's Spec>` under
`timeout 120`, where MERGE_BASE is `git merge-base HEAD <base branch>` and
`<base branch>` is the branch this one was created from (Step 3 explains how
to find it; determine it now):

```bash
bash <plugin-root>/scripts/ui-proof check --base "$(git merge-base HEAD <base branch>)" --spec <the plan's Spec>
```

Drop `--spec` when there is no plan. **Exit 0** (it also prints `ok` when the
gate is off or no UI file changed): continue to Step 2. Any other status (2
for a bad base or spec, 124 for the timeout) means the check never ran: treat
it as exit 1, with its output as the FAIL lines.

**Exit 1:** the UI is unproven, and integrating it is blocked. In an auto
run, first run the dforge:ui-ux Prove phase and check again; only that second
exit 1 counts, and when it comes only from `unverifiable` rows, run
`scripts/auto-run stop --reason "ui proof needs the user"` first. Remember the
exit 1 for Step 4: it turns a recorded `merge` or `pr` into `keep`. Run
`scripts/finish-choice get [--plan PLAN_FILE]` now: when it prints `merge`,
`pr` or `keep` with no `answer` or `firedAt` field, or an auto run is bound,
continue to Step 2 (Step 4 keeps the branch). Otherwise present only these two options:

```
The UI is unproven (ui-proof check):
<its FAIL lines>

1. Prove it first — run the dforge:ui-ux Prove phase, then return to Step 1b
2. Keep the branch as-is (I'll handle it later)

Which option?
```

On option 2, run `scripts/finish-choice answer keep [--plan PLAN_FILE]`, skip
Steps 2 to 4, and carry out Step 5's Option 3 (Keep As-Is) and the steps after
it.
