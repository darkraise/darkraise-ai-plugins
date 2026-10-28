## Lint and Review

1. **Lint.** Run `scripts/plan-lint PLAN_FILE`
   (see using-dforge §Session Budget) until it reports `0 errors`.
   Fix each WARN, or
   explain it in one line of the plan's Assumptions. The checker covers the
   header sections, the task headings and index, the Execution line,
   placeholders, and every task's assignment lines.
   Then run `scripts/depth-route PLAN_FILE` and say its line aloud
   (`depth=<d> spec=<d> tasks=<d> reason=<items>`). The depth sizes the review
   below and the handoff after it; `review-route` reads the same depth, so
   never pick it by hand.
2. **Review.** Write the lint output to the plan's workspace:
   `scripts/plan-lint PLAN_FILE > <workspace>/plan-lint.txt`, where
   `<workspace>` is the directory `scripts/sdd-workspace PLAN_FILE` prints.
   Before each round `<r>`, copy the plan to `<workspace>/plan-round-<r>.md`,
   then run `scripts/codex-gate` (say its line aloud when it ends `source=probe`),
   then `scripts/review-route PLAN_FILE --plan-round <r>`, and review with the
   seat it prints, using
   [plan-reviewer-prompt.md](plan-reviewer-prompt.md). The gate
   keeps an off answer for the session, so add `--refresh` when Codex may have
   come back since then, such as after a login. Every seat
   scores executability, coherence, coverage and assumptions (1-20) against
   [plan-review.md](../../../criteria/plan-review.md) and lists findings. On
   exit 2, review with `dforge:judge-opus` (on a Codex-host plan, a native
   judge at Astra high or above) and say why, quoting its message.
   - **`primary=native:<model>/<effort>`** (every round of a Codex-host plan).
     Dispatch a native judge at that pair or above
     ([native-codex.md](../../../reference/native-codex.md)): the full-plan
     template in round 1, the Later rounds template after it, each with
     `[REPORT_FILE]` set to `<workspace>/plan-review-round-<r>.md`. No Codex CLI
     round runs.
   - **`primary=codex:plan`** (round 1). Write the prompt its Round 1 on Codex
     section describes to `<workspace>/plan-review-prompt.md`, then run, as a
     background Bash call with `timeout` = (row bound + 120) × 1000 ms, 5520000
     today (the rung's bound is longer than a foreground call's ten-minute cap,
     and a background call's limit defaults to 30 minutes):

     ```bash
     bash scripts/run-codex-review.sh --kind plan --cwd <repository-root> \
       --out <workspace>/plan-review-round-1.json --prompt <workspace>/plan-review-prompt.md
     ```

     Read its one status line. `OK` and `FALLBACK` are a review: read the four
     scores and `findings` from the JSON. On `FALLBACK`, or a line naming
     `gpt-6.1-sol/xhigh` with `status=OK`, say the substitution aloud with the
     runner's reason or the line's `evidence=`. `TIMEOUT` or `FAILED` produced
     no review: dispatch the printed `fallback` (`dforge:judge-opus`)
     with the full-plan template and
     `[REPORT_FILE]` set to `<workspace>/plan-review-round-1.md`, and say why.
     Never run the Codex seat twice in one round.
   - **`reason=codex-off`** (round 1 while the gate has not opened the review
     surface). No Codex seat runs. The `primary` is `dforge:judge-opus`.
     Dispatch it with the full-plan template and
     `[REPORT_FILE]` set to `<workspace>/plan-review-round-1.md`, and say
     `codex off — <reason>`, quoting the gate line's `reason` (`untrusted`
     when it printed `usable=true`).
   - **`primary=dforge:judge-opus`** (every later round). Write
     `diff -u <workspace>/plan-round-<r-1>.md PLAN_FILE > <workspace>/plan-delta-<r>.diff`,
     dispatch the seat with the Later rounds template, passing that file and
     the previous round's findings file, with
     `[REPORT_FILE]` set to `<workspace>/plan-review-round-<r>.md`.

   The seat writes its report to that file and replies in at most 10 lines.
   Read the report's `## Verdict` section and its Critical and Important
   findings; the reply carries only the scores, the finding counts and the
   report path, never the findings themselves.
3. **Fix and repeat.** Fix every Critical and Important finding and re-lint;
   Minor findings are advisory. Run the next round only when a round returned
   a Critical finding or any score of 8 or below, and only while the round is
   below the `cap=` that `review-route` printed.
   On a Claude plan the cap is 2 whatever the task totals: round 2 is the
   delta round, and there is no third. Only the plan's depth lowers it: 1 at
   light and standard, so round 1 is the only round. On a
   Codex-host plan the cap follows the highest raw task total, not the weighted
   routing score, at every depth: 1 when it is 3 or less, 2 for 4 or 5, 3 for
   6. At the cap a Codex-host plan's Critical finding
   earns exactly one more delta round (`reason=cap-critical`), scoped to its
   fix, which earns no other; a Claude plan has no such round. A delta round
   replaces a fresh full review. Any Critical finding still open after the
   last round, and any score of 8 or below at the cap, go to your human partner
   (in an auto run, onto the pending list). A borderline score (9-13) gets
   a one-line decision in the plan's Assumptions.
4. **Record.** Only now, add the header line
   `**Plan review:** <YYYY-MM-DD> — <seat> — executability e / coherence c / coverage v / assumptions a (round r)`
   as the last line of the header, directly above `## Global Constraints`.
   `<seat>` is the seat that ran the last round:
   `codex <model> / <effort>` from the runner's status line, or the judge
   agent. The header template deliberately omits it, so `plan-lint` warns
   until the review has run.
