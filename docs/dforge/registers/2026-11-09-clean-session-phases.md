# Clean-session phases

**Source:** the owner's answer on 2026-11-09 naming the three token-saving changes to apply
**Covers:** docs/dforge/specs/2026-11-09-clean-session-phases-design.md

| # | Item | Assigned | Acceptance | State | Note |
|---|---|---|---|---|---|
| 1 | Run finish and CI in a clean session, since that phase cost 2.2M tokens at about 307k context per turn. | docs/dforge/plans/2026-11-09-clean-session-phases.md | A5-A7, A11, A15 | done | - |
| 2 | Stop judges from re-reading the whole diff. They cost about 3.6M, and the 125KB final diff was read 10 times. | docs/dforge/plans/2026-11-09-clean-session-phases.md | A8-A10, A14 | done | - |
| 3 | Start a fresh session after the plan is approved. | docs/dforge/plans/2026-11-09-clean-session-phases.md | A1-A4, A13 | done | - |
| 4 | review-package hides edits under the specs, plans and registers directories from a reviewer's diff, a non-Markdown file there included. | - | - | deferred | The owner chose this at the spec review; each omitted file is named on the Left out line. |
| 5 | skills/writing-plans/references/execution-handoff.md:5 still says the session switches in place; tests/parallel-grouping.test.sh:30 pins it. | - | - | done | The note now says the cockpit clears the session; the pin at tests/parallel-grouping.test.sh and the stale test labels follow it. |
| 6 | ui-lint reports raw colours at hooks/cockpit/register.tsx:1490 and :1543. | - | - | deferred | Owner's ruling 2026-11-09. Both colours predate this branch and ui-lint does not gate CI. The same orange is AMBER in hooks/cockpit/lib.ts and cockpit.test.ts pins it, so a two-line swap would split the terminal rows. Unifying the low-turns colours is its own cockpit change. |
| 7 | plugins/dforge/README.md:629 is 96 characters wide beside lines wrapped near 80. | - | - | done | Paragraph rewrapped near 80 columns. |
| 8 | Confirm review-package's exclude pathspecs work under Windows Git Bash; only the Windows CI shards on the next push can show it. | finishing: the pull request's CI run | - | done | Windows shard 10 of run 42572844293 passed clean-session-phases.acceptance on Git Bash, with review-package run without the exported MSYS_NO_PATHCONV. |
