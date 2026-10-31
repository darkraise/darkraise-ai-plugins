---
name: closing-a-milestone
description: Use when a roadmap milestone or project phase looks finished, when next-step names it, or before anyone says a phase or milestone is done - audits every requirement below it with an independent judge and closes it only on evidence
---

# Closing a Milestone

**Announce at start:** "I'm using the closing-a-milestone skill to audit milestone <M> before it is called done."

The session that built a milestone is the worst judge of whether it is
finished: it remembers what it did, not what was asked. A milestone on
`<docs>/roadmap.md` is done only when `scripts/roadmap close` has
written `closed`, and this skill is the only path to that command.

<HARD-GATE>
Never tell your human partner a phase or milestone is done, complete or
finished unless `scripts/roadmap status` shows it `closed`. Say what
`scripts/roadmap open` lists instead.
</HARD-GATE>

## Steps

1. **Pick the milestone.** The one named, else the current one from
   `scripts/roadmap status`. Milestones close in order; `close` refuses
   otherwise.
2. **Mechanical check.** Run `scripts/roadmap open M<n>`. Exit 1 means rows are
   unresolved: report them, route by their Assigned cells as
   dforge:project-status does, and stop. `verify` rows are the
   exception: they are built and wait on this audit, so continue with them.
3. **Gates.** When `<docs>/gates.md` exists, run
   dforge:running-gates on the integration branch with the base `all`, so
   every gate runs, conditional ones included. A red gate stops the
   close. Keep each gate's output; the judge cannot run anything.
4. **Collect the rows.** Every row of the milestone register, and every row of
   each register covering an epic's spec, with its Acceptance cell. Rows
   `deferred` or `n/a` carry their notes and are audited as decisions, not as
   work.
5. **Commit, then dispatch the judge.** The tree must be clean. Dispatch
   dforge:judge-opus with [milestone-judge.md](references/milestone-judge.md),
   the commit SHA, the milestone's exit criteria, the product spec path, the
   rows, and the gate outputs, and the report file
   `<state>/milestone-M<n>-audit-report.md`, outside the tree so it stays clean.
   A fresh judge has no memory of the build; that is the point.
6. **Act on the verdict.** Read the report's ## Verdict section and its GAP and
   UNVERIFIABLE rows.
   - Any `GAP`: write each back with
     `scripts/register set <file> <id> open --note "audit: <the judge's reason>"`
     (or `scripts/register add` for a gap no row names), report them, and stop.
     The milestone stays open; the reopened rows route like any other.
   - Any `UNVERIFIABLE`: put the row to your human partner with what evidence
     would settle it. It counts as a GAP until they rule.
   - All `MET`: go to step 7.
7. **Owner sign-off.** Present the verdict table and the exit criteria. On your
   human partner's approval, set every `verify` row the audit covered to
   `done` with `scripts/register set` — epic rows in the milestone register
   and requirement rows in the registers below them alike, each in its own
   register: `roadmap close` refuses while any of them is still `verify`. Then
   run
   `scripts/roadmap close M<n> --note "audit <date> <sha7>: <k> MET, <d> deferred"`,
   and commit the registers and the roadmap together (or push them, while documents live in darkmem).
8. **Suite cost.** This step runs after `roadmap close`, in the checkout the
   skill runs in: the main checkout. It holds the rows because finishing's
   merged-result verification leaves one full-suite row at each merge head.
   A plan's own worktree rows are gone with the worktree. The audit reads
   `suites.tsv` from the state directory of the checkout it runs in
   (`bash <plugin-root>/scripts/dforge-path state`). The full-suite command is
   the `**Integration check:**` command of the plans the milestone merged, else
   the project's full test command. A row counts when column 2 is `clean`,
   column 4 is `0`, column 7 is a non-negative integer, and column 3 equals the
   key suite-run writes for `bash -c '<command>'` run from the top level:
   `printf '%q ' bash -c '<command>'` without the trailing space. A six-column
   row has no duration and is skipped. `<d1>` is the duration of the last
   counted row whose HEAD (column 1) is the milestone's head, the commit step 5
   gave the judge, or one of its ancestors (`git merge-base --is-ancestor`).
   `<d0>` is the duration of the last counted row at or before the previous
   milestone's close, the sha7 in its `closed` note in `scripts/roadmap status`.
   With no previous milestone, `<d0>` is the oldest counted row's duration.
   With fewer than two rows it says so and recommends nothing. The same holds
   when `<d0>` and `<d1>` come from the same row. It prints
   `Suite cost: <state>/suites.tsv of <checkout top level> holds <n> full-suite row(s) with a duration; two are needed, so nothing is recommended.`
   This is the expected answer until two plans have merged under this version.
   Otherwise it prints
   `Suite cost: <state>/suites.tsv of <checkout top level>: <d0>s at <sha7> to <d1>s at <sha7> (<change>%).`
   The audit names that checkout in the report. It recommends the cleanup when
   the full suite grew by 20% or more (`<d1> * 100 >= <d0> * 120` and
   `<d1> > <d0>`) or passes a declared `Budget:`. The budget is the
   `Budget: <seconds>s` line of the gate in `<docs>/gates.md` whose `Command`
   equals the plan's `**Integration check:**`, byte for byte. Passing it means
   `<d1>` is above the seconds. When no such gate exists, the audit uses the
   20% rule only. The recommendation is the line
   `Next: dforge:test-simplifier --modules <paths>`. `<paths>` are the distinct
   directories of the files outside `<docs>` in
   `git diff --name-only <previous close sha7>..<milestone head>`, from the root
   commit when there is no previous milestone. It recommends only and removes
   nothing.
9. **Next.** Run `scripts/roadmap status` and name the next milestone's first
   open epic, or say the roadmap is complete.

## Red Flags

| Thought | Reality |
|---------|---------|
| "All the plans are merged, so the milestone is done" | Merged plans are not requirements met. Run the audit. |
| "I built it, I know it works" | That is why a fresh judge audits it. |
| "The judge said GAP but it's minor" | Reopen the row; your human partner can defer it with a note. Never close over a GAP. |
| "The gate is flaky, I'll skip it" | A red gate stops the close. Fix it, or get a ruling recorded in `gates.md`. |
| "I'll mark it closed in the table" | `roadmap check` rejects a hand-closed milestone. Only `roadmap close` writes it. |
| "Hardening can be folded into the release" | Each milestone closes on its own rows. Move rows explicitly, with a note. |
