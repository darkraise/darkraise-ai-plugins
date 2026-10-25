# Task-loop measurement — 2026-10-26

**Wait calls:** 0
**Run:** complete: all 6 tasks done (finished after 1923 s)

Subject: Tasks 1-6 of `docs/dforge/plans/2026-10-24-ui-ux-skill.md` at `6df85ec4`, trimmed to its header, a six-row Task index and six tasks; Task 1's Playwright probe is a two-step stand-in because the nested session has no Playwright MCP. The nested session ran `claude --model sonnet --effort high` in `/root/.claude-alt2` with `--setting-sources project,local` and `--plugin-dir` on a copy of this branch's `plugins/dforge` at `89d4180a`, answered the finish preference `keep`, and stopped at `Task 6: complete`: no final review and no finishing are in the count.

## Per task

| Span | Main-loop calls | Turns | Wait calls | Context at first call | Context at last call | Sum of context over turns |
|---|---|---|---|---|---|---|
| setup | 28 | 18 | 0 | 42747 | 88928 | 1348021 |
| Task 1 | 5 | 5 | 0 | 88928 | 94320 | 457719 |
| Task 2 | 7 | 6 | 0 | 94561 | 101438 | 585924 |
| Task 3 | 20 | 16 | 0 | 104079 | 125110 | 1831706 |
| Task 4 | 11 | 8 | 0 | 125389 | 137858 | 1042790 |
| Task 5 | 4 | 4 | 0 | 138141 | 140843 | 558262 |
| Task 6 | 8 | 7 | 0 | 142901 | 152202 | 1026364 |
| after Task 6 | 0 | 0 | 0 | - | - | - |
| total | 83 | 64 | 0 | | | 6850786 |

Calls are tool calls in the main loop; a turn is one assistant message that made calls; context is input plus cache tokens of the message that made the call, and the last column sums it over the span's turns. `Monitor` and Bash `sleep` calls are the wait calls.

## Against the baseline

The baseline is the typed-seats execution session `40cb3d10-fb44-41ea-a1f9-91e02a074fd1`: 330 main-loop calls over 5 tasks and a final review, 114 of them wait calls (Monitor calls: 113; Bash sleep calls: 1) by this counter. Through its fifth task's complete line it made 230 calls, 46.0 per task.

| | Main-loop calls | Tasks | Calls per task | Wait calls | Context at the last task's last call |
|---|---|---|---|---|---|
| Baseline, through Task 5 | 230 | 5 | 46.0 | 78 | 313,411 |
| This run | 83 | 6 | 13.8 | 0 | 152,202 |

Wait calls are zero, which is the one hard bar. Calls per task fall from 46.0 to 13.8 and the context at the last call from 313,411 to 152,202.

## Notes

- The count stops at the last task's complete line; the baseline's 330 includes the 100 calls after its fifth task's complete line (its final review and finishing) that this run did not execute.
- The two runs executed different plans: the baseline's tasks were larger and ran partly as a parallel wave (its Tasks 2 and 3 rows show one call each because Tasks 2-4 ran together), while this run's six tasks were mostly low-effort. The comparison shows the loop's call and wait overhead, not equal work.
- Fix rounds: Tasks 3 and 4 each needed one, and both re-reviews were skipped under the skip rule (2 and 3 changed lines). Task 3 also took an amendment (A3); Task 6 took two (A1, A2).
- Tasks 1 and 5 settled two `cannot-verify` items each by the `task-step review` identity and attribution checks, with no ruling seat. Task 1 also settled a suite-log item by reading the `suite-run` log directly.
- Reviews ran on `dforge:judge-sonnet-high` for Tasks 1, 2, 4, 5 and 6 and on `dforge:judge-opus` for Task 3.
- The wait ran as one background `measure.sh wait 7000` command. The script calls itself as `"$0"`, so the scratch file needed `chmod +x`; the first launch exited 126 on its first pass, the nested session kept running untouched, and the relaunch ran to completion.
- The nested transcript stays in the shared projects store (`/root/.claude-alt2/projects/-tmp-dforge-loop-measure-2026-10-26-clone--claude-worktrees-ui-ux-skill/219a3b13-aa54-4957-837a-316d8e12b0e3.jsonl`), which keeps about 30 days.
