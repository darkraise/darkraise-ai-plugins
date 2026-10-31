## The CI line

Read the CI configuration as [ci-parity.md](../../../reference/ci-parity.md)
says, then fill the header line `**CI:**` on every plan: write `**CI:** none`
when no CI configuration is found, else write the line in this form:
`` **CI:** `<workflow files>` — platforms: <list> — local: `<cmd>`; `<cmd>` — uncovered: <platforms or none> ``.

The `local:` commands are the ones ci-parity.md says to keep, one code span
each, separated by `; `. `uncovered:` lists names from the Platform column of
the Pitfalls table, comma-separated, or `none`.

## The Global Constraints copy

For every uncovered platform, copy that platform's rows of the Pitfalls table
in [ci-parity.md](../../../reference/ci-parity.md) into `## Global Constraints`,
one line per row, so every task brief carries them.

## The Early CI line

Offer the early CI run only when the CI line names an uncovered platform.
Write no `**Early CI:**` line when every platform is covered.

Attended, ask with the multiple-choice prompt once the plan's task count and
waves are known. The options are `No early run (Recommended)`, the first
point and the midway point. Name each point concretely: `after wave <k>` on a
waves plan, `after task <n>` on a sequential plan. Say that an early run
pushes the branch and starts the workflow but never opens a pull request;
your human partner's answer is the consent.

A point other than "No early run" is written with today's date, as
`**Early CI:** after wave <k> — consented <YYYY-MM-DD>` or
`**Early CI:** after task <n> — consented <YYYY-MM-DD>`.

In an auto run (`scripts/auto-run status` exits 0), ask nothing and copy the
`Early CI:` line of the spec's `## Decisions`:

- `Early CI: none` writes no line.
- `Early CI: <first|midway> — consented <date>` writes the header line with
  that date. `first` is `after wave 1` on a waves plan and `after task 1` on a
  sequential plan. `midway` is `after wave <ceil(waves/2)>` on a waves plan
  and `after task <ceil(tasks/2)>` on a sequential plan.
- A spec with no such decision writes no line.
