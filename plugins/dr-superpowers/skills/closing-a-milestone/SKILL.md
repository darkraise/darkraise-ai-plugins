---
name: closing-a-milestone
description: Use when a roadmap milestone or project phase looks finished, when next-step names it, or before anyone says a phase or milestone is done - audits every requirement below it with an independent judge and closes it only on evidence
---

# Closing a Milestone

**Announce at start:** "I'm using the closing-a-milestone skill to audit milestone <M> before it is called done."

The session that built a milestone is the worst judge of whether it is
finished: it remembers what it did, not what was asked. A milestone on
`docs/superpowers/roadmap.md` is done only when `scripts/roadmap close` has
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
   dr-superpowers:project-status does, and stop. `verify` rows are the
   exception: they are built and wait on this audit, so continue with them.
3. **Gates.** When `docs/superpowers/gates.md` exists, run
   dr-superpowers:running-gates on the integration branch. A red gate stops the
   close. Keep each gate's output; the judge cannot run anything.
4. **Collect the rows.** Every row of the milestone register, and every row of
   each register covering an epic's spec, with its Acceptance cell. Rows
   `deferred` or `n/a` carry their notes and are audited as decisions, not as
   work.
5. **Commit, then dispatch the judge.** The tree must be clean. Dispatch
   dr-superpowers:judge-opus with [milestone-judge.md](references/milestone-judge.md),
   the commit SHA, the milestone's exit criteria, the product spec path, the
   rows, and the gate outputs. A fresh judge has no memory of the build; that
   is the point.
6. **Act on the verdict.**
   - Any `GAP`: write each back with
     `scripts/register set <file> <id> open --note "audit: <the judge's reason>"`
     (or `scripts/register add` for a gap no row names), report them, and stop.
     The milestone stays open; the reopened rows route like any other.
   - Any `UNVERIFIABLE`: put the row to your human partner with what evidence
     would settle it. It counts as a GAP until they rule.
   - All `MET`: go to step 7.
7. **Owner sign-off.** Present the verdict table and the exit criteria. On your
   human partner's approval, set each `verify` epic row to `done` with
   `scripts/register set`, then run
   `scripts/roadmap close M<n> --note "audit <date> <sha7>: <k> MET, <d> deferred"`,
   and commit the registers and the roadmap together.
8. **Next.** Run `scripts/roadmap status` and name the next milestone's first
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
