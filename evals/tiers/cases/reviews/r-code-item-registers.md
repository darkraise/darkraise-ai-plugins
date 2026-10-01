# r-code-item-registers

Source: the final-review fix commit `ddb5ed4`, reviewed at head `800e834`.

## D1: a register that no spec names is never read when designing

- Where: `plugins/dr-superpowers/skills/brainstorming/SKILL.md`, "Understanding the idea"
- Defect: the skill reads registers only through `register open --spec <spec>`. A register captured before anything was designed has `**Covers:** -`, so no `--spec` query reaches it and its open rows are missed.
- Evidence: `ddb5ed4` adds: list `docs/superpowers/registers/` and run `register open <file>` on every register whose Covers is `-`.
- Minimum severity: Important

## D2: nothing fills in the register's Covers line once the spec exists

- Where: `plugins/dr-superpowers/skills/brainstorming/SKILL.md`, "Opening an item register"
- Defect: the register is created with `**Covers:** -` and no step ever sets it to the spec's path, so the plan-side surfaces that look registers up by spec never see it.
- Evidence: `ddb5ed4` adds the instruction to set the Covers line once the spec is written.
- Minimum severity: Important

## D3: the register template omits the table's separator row

- Where: `plugins/dr-superpowers/skills/brainstorming/SKILL.md`, "Opening an item register"
- Defect: the skill gives the table header line but not the `|---|---|---|---|---|---|` separator row a Markdown table and the register parser need.
- Evidence: `ddb5ed4` adds the separator row to the instruction.
- Minimum severity: Important

## D4: starting a run sets resolved rows back to `doing`

- Where: `plugins/dr-superpowers/skills/executing-plans/SKILL.md` and `plugins/dr-superpowers/skills/subagent-driven-development/SKILL.md`, Setup
- Defect: both skills mark every row the plan carries as `doing` at the start of a run, so resuming a plan reopens rows already at `verify` or `done`.
- Evidence: `ddb5ed4` adds "skipping any row already at `verify` or `done`" to both.
- Minimum severity: Important

## D5: finishing checks only the plan's own spec, not the programme's

- Where: `plugins/dr-superpowers/skills/finishing-a-development-branch/SKILL.md`, the line above the options menu
- Defect: the open-rows check runs `register open --spec` for the plan's Spec path only. A programme's register covers the programme design, which the plan's `**Program:**` line names, so its open rows are missed.
- Evidence: `ddb5ed4` adds a second run with the spec the Program line names when that differs.
- Minimum severity: Important

## D6: finishing counts the rows this very plan resolves as still open

- Where: `plugins/dr-superpowers/skills/finishing-a-development-branch/SKILL.md`, the line above the options menu
- Defect: rows assigned to the plan being finished are still unresolved when the check runs, because a later step resolves them, so the skill always reports open rows for its own work.
- Evidence: `ddb5ed4` adds "Ignore every row whose `assigned` value is this plan's repository-relative path".
- Minimum severity: Important

## D7: project-status has no rule for an unresolved register row

- Where: `plugins/dr-superpowers/skills/project-status/SKILL.md`, the recommendation table
- Defect: with no plan in flight and a register still holding unresolved rows, the table falls through to "between programmes" and offers a fresh brainstorm, ignoring the open rows.
- Evidence: `ddb5ed4` inserts rule 6, "A register holds an unresolved row and no rule above matched", and renumbers the rest.
- Minimum severity: Important

## D8: the Open items section is printed even when nothing is open

- Where: `plugins/dr-superpowers/skills/project-status/SKILL.md`, the report sections
- Defect: the section is described unconditionally, so a project with no unresolved row still gets an empty Open items section.
- Evidence: `ddb5ed4` adds "omit when no register holds an unresolved row".
- Minimum severity: Important
