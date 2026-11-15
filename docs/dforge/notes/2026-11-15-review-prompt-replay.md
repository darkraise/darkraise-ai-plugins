# Review prompt replay (M1)

Run 2026-11-15 on branch `auto/measured-proposals`. The old arm is
`code-reviewer.md` at `32472b56` (before the change); the new arm is the
evidence-bound, diff-first prompt of `c9cb7c14`. Every run was one
`dforge:judge-opus` dispatch reviewing a `scripts/review-package` package of
its range from a scratch clone checked out at the range head.

Ranges: b1 `b36eaf63..bc097711` (3 commits, requirements its commit
subjects), b3 `5bb5545f..e48eeafa` (44 commits, plan
`docs/dforge/plans/2026-11-13-reviewer-only-externals.md`), d
`9d46f4e..52da46e0` (23 commits, plan
`docs/dforge/plans/2026-11-13-dflow-hud-overhaul.md`). Runs went one at a time,
per range old-1, new-1, old-2, new-2. Tokens are the Agent result's
`subagent_tokens`.

A fresh `dforge:judge-opus` marked all 72 findings CONFIRMED or UNCONFIRMED
from one shuffled list that carried each finding's range but not its arm,
with every `Evidence:` line removed: 53 confirmed, 19 unconfirmed.

## Per run

| Run | Critical | Important | Minor | Confirmed C+I | Unconfirmed | Tokens |
|---|---|---|---|---|---|---|
| b1-old-1 | 0 | 2 | 9 | 2 | 5 | 170509 |
| b1-old-2 | 0 | 1 | 9 | 1 | 3 | 174268 |
| b1-new-1 | 0 | 2 | 3 | 2 | 1 | 170789 |
| b1-new-2 | 0 | 3 | 5 | 3 | 0 | 171168 |
| b3-old-1 | 0 | 2 | 3 | 2 | 2 | 139662 |
| b3-old-2 | 0 | 2 | 4 | 2 | 3 | 161121 |
| b3-new-1 | 0 | 1 | 1 | 1 | 0 | 150298 |
| b3-new-2 | 0 | 1 | 2 | 1 | 2 | 192771 |
| d-old-1 | 0 | 0 | 9 | 0 | 2 | 153552 |
| d-old-2 | 0 | 1 | 5 | 1 | 1 | 116401 |
| d-new-1 | 0 | 0 | 4 | 0 | 0 | 145080 |
| d-new-2 | 0 | 1 | 2 | 1 | 0 | 163871 |

## Per arm

| Arm | Findings | Unconfirmed | Unconfirmed share | Confirmed C+I | Tokens |
|---|---|---|---|---|---|
| old | 47 | 16 | 0.340 | 8 | 915513 |
| new | 25 | 3 | 0.120 | 8 | 993977 |

The unconfirmed share is unconfirmed findings summed over findings summed
across the arm's six runs.

## Result: kept

The keep rule holds: the new arm's confirmed Critical+Important (8) is not
below the old arm's (8), and its unconfirmed share (0.120) is below the old
arm's (0.340). Its tokens are not lower: 993977 against 915513, 8.6% more,
so the prompt buys precision, not cost. The new arm reported about half as
many findings, all of the drop in Minor ones (17 against 39).

M1 measures `code-reviewer.md` only. The lens prompt, the plan-reviewer
prompt and the fixer's reproduction rule in `final-review.md` take the same
evidence and diff-first rules and are judged by this proxy.

One extra dispatch (b1-old-1's first) is not counted: the review seat's write
guard refused its report because the dispatch prompt named no report file.
Each counted run read its filled prompt from a file the one-line dispatch
named, in both arms.
