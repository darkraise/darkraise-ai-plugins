# Handoff crossings: why sessions pass the 350k limit

Token-efficiency register row 16, investigated 2026-10-26 on both hosts
(this machine and 192.168.0.252), over every Claude transcript still kept
(about 30 days).

## Method

A crossing is a point where a main-loop session's context (input plus cache
read plus cache creation, deduplicated per message id) first reaches 350k,
counted again after each compaction. Each crossing is classified by the last
budget line that a measuring script (`task-brief`, `review-package`,
`context-size`, `task-step`, `auto-run`) printed in that session before it,
and the last skill invoked. Budget lines printed by test suites are ignored.

## Findings

1. **The count mixes in a limit that was not in force.** 221 crossings locally
   in 214 sessions, close to the register's 215. The budget lines show
   `of 790k` and `of 465k` until 2026-10-22, and `of 350k` from
   2026-10-22T08:51Z. 188 of the 221 crossings predate the 350k setting:
   they are crossings of a number that was not the limit.
2. **Since 350k took effect, crossings are by design.** 33 locally and 23 on
   192.168.0.252:
   - About 60% grew after a task started under the limit with an `ok` line.
     The limit is checked when a task starts (`reference/session-budget.md`
     reserves 140k for one task's growth). The largest growth after an ok
     line was about 112k (342k to 454k). In an auto run the next line says
     `compact` and the session compacts.
   - About 30% are in phases no budget line measures: writing-plans (13),
     systematic-debugging (2), brainstorming (2), another skill (1). Plan
     writing is measured once, at its start, against 525k.
   - The other three: two sessions with no dforge use, and one plan-writing
     session still under its 525k line.
3. **No session ignored a handoff verdict.** No session on either host started
   a task (`task-brief` or `task-step start`), or grew more than 60k, after a
   session-level `handoff` line. A `wave of N` handoff line only lowers the
   wave's width, and sessions did that.

## Ruling

Row 16 is not a bug: the 350k limit is a task-start threshold and holds as
one. Row 3's priced simulation should model it that way (a check at each task
start, plus up to 140k of growth within the task), use only transcripts from
2026-10-22T08:51Z on for the 350k baseline, and run after row 2 lands, since
the task-loop steps change per-task growth (152k against 313k at the last call
in docs/dforge/notes/2026-10-26-task-loop-measurement.md).

Plan writing is the one place that grows unmeasured. Two local plan-writing
sessions reached 483k and 493k and then compacted. Since 2026-10-26 the slice
drafters of register row 1 do most of that work outside the main session, so
whether it still grows that far is unmeasured.
