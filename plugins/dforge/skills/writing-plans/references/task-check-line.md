## Write the Task check and Integration check lines

`**Integration check:**` holds the full suite command on every plan, not only on a waves plan.
It is the Full suite tier's command.

Choose the first that applies for `**Task check:**`:

1. a gate in `<docs>/gates.md` with `Tier: task`, its `Command`;
2. the full suite itself, when its last passing run in `suites.tsv` took 300
   seconds or less, because tiering a fast suite saves nothing;
3. an impact-selection command for the runner the project uses, from
   [test-tiers.md](../../../reference/test-tiers.md) (examples:
   `npx jest --changedSince=main`, `pytest --testmon`, `vitest --changed main`);
4. `none — full suite every 3 tasks`, when none of those applies.

Rule 2 reads the duration from `suites.tsv`. Read only rows of the checkout
you run in, from `<state>/suites.tsv` where `<state>` is
`scripts/dforge-path state`. A row matches when column 3 equals the quoted
key suite-run records for `bash -c <cmd>` run from the top level, which is
the output of
`printf '%q ' bash -c '<cmd>'` without its trailing space. Take the last
matching row whose column 4 is `0`, and read its column 7, the duration in
seconds. A row that is missing, or has six columns and so no duration, counts
as not fast.

End the line with `— <why>` naming which of the four rules chose it, for
example `— gate 2 has Tier: task` or `— the full suite last passed in 212 s`.
Rule 4 writes the line as `**Task check:** none — full suite every 3 tasks`.

Write the command as one code span. `scripts/plan-lint` warns on a missing
line and fails a malformed one. A waves plan without an `**Integration check:**`
line fails.
