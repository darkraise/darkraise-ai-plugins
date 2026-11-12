# Wording-pin deletion list (work order)

Approved 2026-11-12 by the Fable ruling seat under the owner's delegation (register docs/dforge/registers/2026-11-10-tdd-and-lifecycle-review.md, row 22). The count below was produced read-only on main at 1675af60; line numbers refer to that commit. The amendments R1-R7 and the dependencies in this header override the count where they differ.

## Reliability of the count

I checked four passages against the test files: `speed-and-cost.acceptance.test.sh` 90-125, `task-step-text.test.sh` 45-141 and 200-273, `review-route.test.sh` 391-425, and `impl-clauses.test.sh` whole. Every line number, label and target matched, and every DELETE row I read is a `grep` of a Markdown file with no script reader. The KEEP rows I read (`task-step-text` 84-85 and 106-118) are real consumers. The count is reliable as a work order. It has three weaknesses, ruled below: the parts disagree on two classes, section 4-pre misses dependencies outside `plugins/dforge/tests`, and its scope omits `evals/tiers/tests`.

## Amendments

All counted DELETE rows of `wording-pins.md` are approved, with these amendments. The executor applies the list by row label (line numbers are for 1675af60), deleting from the highest line down within each file.

- **R1, format contract: keep.** The owner's rule already excepts "wording a script parses, such as the Step 1 forms", and `plan-lint` parses those from plans, not from `test-step-forms.md`. So a pin stays when (a) its needle is itself a line form, key, sentinel or placeholder that the document tells a session, seat or plan author to write, not a sentence about one, and (b) one `rg` shows that form's fixed prefix matched in a regex, `case` pattern or `grep` under `plugins/dforge/scripts` or `plugins/dforge/hooks`. Part g5's 50 `format contract` rows and g3's six borderline `faster-plans` rows stay. The parts that deleted this class are rechecked, and only these candidates: `speed-and-cost.acceptance.test.sh` A3's Verified, bullet-grammar and `Report:` rows and line 187; `task-step-text.test.sh` 81-82, 131-133, 204-205, 208, 230-231, 268-269; `task-step-settle.test.sh` 30-31; `faster-plans` 514 and 644-646; `clean-session-phases` 183-185; and any g6a or g6b row whose own note says a script parses the pinned grammar. A candidate that fails (a) or (b) is deleted. Where two kept rows pin one form in one document, the acceptance suite's copy is deleted. Each kept row is named with its script `file:line` in the commit body.
- **R2, description frontmatter: delete.** No script reads a description's sentences. Add `review-route.test.sh` 510, 511, 514, 515; `ui-ux-skill.test.sh` 27-28; `inline-mode.test.sh` 177; `inline-only-execution.acceptance.test.sh` 266; `inline-only.acceptance.test.sh` 227-228. Frontmatter keys with parsed values (`name`, `tools`, `disallowedTools`, `skills`) stay.
- **R3, file shape: keep.** Remove from the list `criteria.test.sh` 35, 37, 42, 47, 51 (heading and id shape). They pin no sentence and do not break on rewording. `criteria.test.sh` loses only 78-81. Likewise kept: `process-roles` 53-55 and 201, `settings-skills` 105-109, `gates-manifest` 83-132, `seats` 49-50, the "Read ... before you" link lines, `sdd-references` 27-28, and the wrapper contract checks in `run-codex-task` and `run-agy-task`.
- **R4, records under `docs/`: delete.** An assertion on the wording, table, existence or clean state of a note, historical spec or distilled-constraints file is deleted. This confirms the counted `auto-default` 175-180, `review-depth` and `review-depth-qa` spec reads, `project-status` 109-112 and `review-route` 826-835, and adds `speed-and-cost-followups` A21 (470-475), `lanes.test.sh` 358-359 and the 12 calibration assertions in 363-436 (397-410 stay), and `agy-gemini-first` 355-358. The `git log -S` checks of `antigravity` A14 stay.
- **R5, whole files: nine.** The six listed (`delegated-suite`, `final-phase`, `impl-clauses`, `parallel-grouping`, `readme-unattended`, `waiting-text`), plus `project-status`, `distilling-docs` and `migrate-skill`, which would keep only existence or `name:` checks. `auto-run-skills` keeps its two sentinel rows under R1 and stays.
- **R6, `evals/tiers/tests`: in scope, by rule.** These are the longest sentence pins in the repository and the count never looked at them. Delete each `test(...)` whose assertions only match text read from `plugins/dforge/{skills,reference,criteria,agents}` or `README.md`, or from another test file. Keep any test that runs a script. Candidates by title, each to be confirmed by reading its body: `test-tiers-and-ci-parity.acceptance.test.mjs` lines 229, 400, 428, 435, 487, 496, 503, 513, 522, 530, 536, 548, 558, 570, 704, 712, 730, 736, 743, 755, 763, 902, 912, 920; and all six A2 "no sentence ... is lost by the split" tests of `speed-and-cost.acceptance.test.mjs` with `REWORDED`, `REMOVED`, `norm` and `SPLIT`. Row 17's "A2 (sentence split)" is this check; the count read it as the shell suite's A2 block, which also goes. The executor records the number removed.
- **R7, adjacent.** Fix the `fleet.test.sh:43` label (21 against 19 agents) in passing.

## Dependencies missing from section 4-pre

Section 4-pre is accepted, and it is incomplete. Add:
- `test-tiers-and-ci-parity.acceptance.test.mjs:232` reads `tests/delegated-suite.test.sh`; it goes with its test under R6, before that file is deleted.
- `plugins/dforge/README.md` 1277-1278 names `project-status.test.sh` and `distilling-docs.test.sh`.
- `scripts/test-all.mjs` 91 and 96: drop `a1`, `a14`, `a15`, `a16` and `A6` from the part lists in the commit that removes them, or the suite is called with a part it rejects.
- `scripts/test-shards.mjs`: remove the nine deleted files' weights. A stale weight does not fail `checkShellWeights`, which walks existing jobs, so this is tidiness and belongs in the last task.

## Task split

One plan, depth standard, finish by pull request. It also carries rows 16, 20 and 21, which gives the spec real `test` statements and the retained record its QA counts.
- The amended list is committed first as `docs/dforge/notes/2026-11-12-wording-pin-deletion-list.md`: `wording-pins.md` with R1-R7 at the top. The spec's Decisions name it as the work order, so a task that cites one part by heading is complete as written.
- Task 1: row 16 (test first).
- Task 2: dependents and meta-pins, so later tasks can delete freely: part g0, `auto-default` 161-162 and 165-172, and R6.
- Task 3: parts g1 and g2, with row 21 in `typed-seats-and-drafting.acceptance.sh`.
- Task 4: part g3, with row 20 and the `test-all.mjs` part lists.
- Task 5: part g5, first eight files. Task 6: part g5, remaining files.
- Task 7: part g6a. Task 8: part g6b.
- Task 9: weights, README lines, dead helpers and header comments the parts name, and the sweep below.
- Tasks 2-9 take Step 1 `No new test, because the task only deletes assertions and adds no behaviour; the remaining suites are the existing checks`. Each task ends with the suites it touched and their dependents green.


---

# Count (read-only, 1675af60)

Scope: plugins/dforge/tests/ (104 entries: 102 test files plus skill-view.sh and the darkmem-sync directory). Rule: docs/dforge/specs/2026-11-11-test-volume-rules-design.md, "Behavior, not text" (A17/A19). No repo file was edited and no suite was run. Line numbers are from the files as they stand on main at 1675af60.

## 1. Summary

- Total wording-pin assertions recommended DELETE: **2241**, in **55 of the 102 test files**. The other 47 files hold no wording pin (they run scripts, or feed fixtures to scripts, or check structure).
- Counting unit: one per assertion statement in the file; a loop over a list of phrases counts one per phrase; a loop over files with the same phrase counts once, except where the per-file part says it counts per iteration (group 3 counts loop iterations; speed-and-cost counts source lines and lists the executed count). Treat the totals as accurate to a few percent on those loops, not exact.
- A previous note said 56 of 99 files touch a skill/reference path. Verified: 55 hold at least one pin, but most of the paths in the rest are fixtures or script output. The cockpit.test.ts (7148 lines, 224 `.md` mentions) holds zero: all its fs handlers answer from in-memory maps.
- Borderline items are NOT in the totals; each part's section 3 lists them (for example description-frontmatter sentences, `format contract` KEEP rows in group 5, criteria heading-shape checks in criteria.test.sh counted as 5 of the 7 there, calibration records under docs/, "Read ... before you" link lines in sdd-references/skill-size/skill-split-planning).
- The named rulings: speed-and-cost A2 (sentence split, lines 90-125, 4 assertions) and A18 (native-codex.md byte identity, lines 516-524, 1 assertion; plus 7 other A18 sentence pins) are both in the DELETE list.

### Per-file DELETE counts (descending)

| Test file | DELETE | Part |
|---|---|---|
| task-step-text.test.sh | 222 | g2 |
| review-route.test.sh | 167 | g3 |
| inline-mode.test.sh | 133 | g5 |
| process-roles.test.sh | 127 | g5 |
| auto-run-skills.test.sh | 126 | g5 |
| project-status.test.sh | 122 | g3 |
| auto-default.test.sh | 116 | g5 |
| faster-plans.acceptance.test.sh | 111 | g3 |
| seats.test.sh | 87 | g5 |
| final-phase.test.sh | 79 | g6a |
| settings-skills.test.sh | 71 | g5 |
| review-depth-qa.acceptance.test.sh | 70 | g3 |
| review-depth.acceptance.test.sh | 67 | g3 |
| gates-manifest.test.sh | 66 | g6a |
| delegated-suite.test.sh | 63 | g6a |
| lanes.test.sh | 58 | g6b |
| test-simplifier.test.sh | 55 | g6b |
| auto-run-worktree-setting.acceptance.test.sh | 53 | g5 |
| auto-run-worktree-setting-qa.acceptance.test.sh | 46 | g5 |
| distilling-docs.test.sh | 44 | g6a |
| speed-and-cost.acceptance.test.sh | 40 | g0 |
| inline-only.acceptance.test.sh | 34 | g5 |
| ui-ux-skill.test.sh | 27 | g5 |
| waiting-text.test.sh | 20 | g6b |
| task-loop-steps.acceptance.test.sh | 17 | g2 |
| typed-seats-and-drafting.acceptance.sh | 17 | g2 |
| agy-gemini-first.acceptance.test.sh | 16 | g6a |
| plan-revise.test.sh | 16 | g1 |
| migrate-skill.test.sh | 16 | g6b |
| clean-session-phases.acceptance.test.sh | 14 | g2 |
| inline-only-execution.acceptance.test.sh | 13 | g5 |
| parallel-grouping.test.sh | 12 | g6b |
| ladder.test.sh | 11 | g6a |
| antigravity-executor-lane.acceptance.test.sh | 9 | g5 |
| readme-unattended.test.sh | 9 | g6b |
| speed-and-cost-followups.acceptance.test.sh | 9 | g0 |
| hook.test.sh | 8 | g6a |
| lane-breaker.test.sh | 8 | g6b |
| native-routing.test.sh | 8 | g6b |
| ui-ux-skill.acceptance.test.sh | 8 | g5 |
| criteria.test.sh | 7 | g1 |
| executor-recovery.test.sh | 6 | g6a |
| impl-clauses.test.sh | 5 | g6a |
| fleet.test.sh | 5 | g6a |
| task-step-base.test.sh | 3 | g2 |
| task-step-suite.test.sh | 3 | g2 |
| codex-review.test.sh | 3 | g6a |
| working-directory.test.sh | 3 | g6b |
| task-step-settle.test.sh | 2 | g2 |
| budget-line.test.sh | 2 | g5 |
| turn-end.test.sh | 2 | g6b |
| worktree-instructions.test.sh | 2 | g6b |
| executors.test.sh | 1 | g6a |
| dforge-config.test.sh | 1 | g6a |
| dforge-dir.test.sh | 1 | g6a |
| **Total** | **2241** | |

Files with 0 DELETE (checked): cockpit.test.ts, plan-lint, plan-lib, plan-amend, roadmap, register, review-record, lens-route, depth-route, next-step, retained-review-data.acceptance, test-volume-rules.acceptance, task-step.test.sh, the three task-loop-steps/typed-seats/clean-session .ts files, auto-run.test.sh, ui-proof.test.sh and the other files listed as clean in each part.

## 4-pre. Cross-file dependencies to fix when deleting (read before editing)

These are the edits outside the assertions themselves (also listed per part under each file's "counter / zero assertions" notes).

1. **No literal pass counts or TAP plans** exist in any file: every suite prints runtime `%d passed, %d failed`. No count needs updating.
2. **Files left with zero assertions (delete whole file and its entry in scripts/test-shards.mjs):** delegated-suite.test.sh (shards:57), final-phase.test.sh (:69), impl-clauses.test.sh (:74, only a file-count rider remains), parallel-grouping.test.sh (:88), readme-unattended.test.sh (:96), waiting-text.test.sh (:133). Near-empty: project-status.test.sh keeps 3 existence checks (shards:95); migrate-skill.test.sh keeps 2 structural checks (:85); auto-run-skills.test.sh keeps 2 `format contract` rows (:44) and goes empty if those are also deleted. test-shards.mjs and test-all.mjs also carry per-file timings and per-function shards (test-all.mjs:85, :91, :96); stale entries select nothing, but check whether test-shards.mjs fails on a listed-but-missing file.
3. **speed-and-cost.acceptance.test.sh line 111** ("no test file that existed before the split is gone", base e6f88a65) fails as soon as any test file present at that base is deleted, and its `retired` list (line 106) names only draft-pack.test.sh. The A2 block (90-125) is on the DELETE list and removes this; if A2 were kept it would need every deleted file added to `retired`.
4. **speed-and-cost-followups.acceptance.test.sh**: A6 (348-361) greps delegated-suite.test.sh and task-step-text.test.sh for the pinned sentences and is on the DELETE list. A20 (456-465) copies agents/ and runs impl-clauses.test.sh: if impl-clauses.test.sh is deleted whole, delete lines 456-465 too (and the `impl-clauses` mention). A12 (332-336) greps task-step-base.test.sh and task-step-settle.test.sh for case shapes; keep those cases when thinning those files (they hold only 3 and 2 DELETE rows). A20 line 454 requires no `SD=` line in the two review-depth acceptance tests.
5. **auto-default.test.sh lines 161-162** (excluded by group 5 as test-code hygiene, not counted) grep review-depth-qa.acceptance.test.sh for `FN=$(flat_skill "$FIN")` (exactly once) and review-depth acceptance tests for `SD=`. Deleting the review-depth-qa blocks that use `flat_skill` makes line 162 fail, so delete line 162 (and 161 if the `SD=` lines go). **auto-default.test.sh lines 165-172** run impl-clauses.test.sh on a copy of agents/: delete them together with impl-clauses.test.sh if that file is deleted whole.
6. **Dispatch lists inside suites**: faster-plans `ALL`/shards (functions a1, a14, a15, a16 become empty; test-all.mjs:91), review-depth `ALL` line 519 (drop a9, a11, a14, a15), review-depth-qa (a9, a11, a14, a15), task-loop-steps.acceptance `ALL=` line 693, agy-gemini-first.acceptance dispatch loop line 403 (drop `12`).
7. **Narrowing, not deleting**: seats.test.sh loops 138-146 also pin ruling-prompt.md and must be narrowed to the three templates that stay KEEP (see g5).
8. **Adjacent finding (not a pin)**: fleet.test.sh:43 label says 21 agents while its expected list and header say 19.

Section 2 (tables per file), section 3 (excluded borderline) and each file's own zero-assertion/counter notes are in the parts below, one part per group, unedited from the investigators. Within each part the tables carry the exact line numbers; section numbering inside a part is that part's own.



---

# PART g0

## speed-and-cost.acceptance.test.sh  (DELETE source assertion lines: 40)

Helpers that become unused after the deletions: `doc()` (line 57; only A3, A4, A5, A16, A18 use it), `base_known()` (line 59; only A2 and A18), and the `BASE` and `native_base` variables (line 25 BASE, line 518). `has`, `lacks`, `matches`, `check` stay in use (A5, A7, A9-A11).

| Lines | Label | Markdown + phrase pinned | Verdict |
|---|---|---|---|
| 90-125 (A2 block; assertions at 102, 103, 111, 123) | "A2: the split added reference files" / "every new reference file is linked from its SKILL.md on a 'before you' line" / "no test file that existed before the split is gone" / "every pre-split test that reads skill text still runs and passes" | skills/*/SKILL.md link line containing the word "before" next to `references/<name>`; plus a re-run of every pre-split test that greps skills | DELETE whole block. 102 and 111 are structural by themselves (count of added files; test files exist) but exist only to guard the split's wording; 103 pins a "before you" sentence around a link; 123 runs the pre-split pin tests (about four minutes) whose targets are being deleted. NOTE line 111: it FAILS when any test file present at base e6f88a65 is deleted (retired list at line 106 holds only draft-pack.test.sh) -> the block must go with the deletion list. |
| 176-183 (x2 sources: implementer-prompt.md and the generated task-1-dispatch.md; executed 16) | A3: "does not tell the implementer to run the full suite" / "run the whole suite" / "does not hand the implementer suite-run" / "tells it to run the focused tests that cover its change" / "names the Verified section" / "gives the pass bullet grammar" / "gives the fail bullet grammar" / "ends the reply with a Report: line" | skills/subagent-driven-development/references/implementer-prompt.md (template read by scripts/task-step:733, which copies it into the dispatch file; no script parses these sentences: the `## Verified` bullet grammar and Report: line are parsed by impl-stop-gate from the implementer's REPORT, not from the prompt) | DELETE (8 source lines, 16 executed). Dispatch-file half asserts script output, but only the template's prose, so it goes too. |
| 187 | "A3: the Report: line is the last element of the reply format" | implementer-prompt.md "Then report back with ONLY ... As the last line of your reply ... Report: <absolute path" | DELETE |
| 195-201 (7) | A4: "on a DONE report the controller starts suite-run" / "as a background command" / "at the task's head" / "and in the same turn runs the review step" / "and dispatches the review seat" / "for DONE_WITH_CONCERNS too" / "the SKILL.md sends each task through delegated-task.md" | reference/delegated-task.md section "The suite runs beside the review"; skills/subagent-driven-development/SKILL.md "For each task, or batch, run [delegated-task.md]" | DELETE (7). Line 205 (suite-run records a row) KEEP: script behaviour. |
| 247-248 (2 lines; 248 is the assertion, 247 its `doc` read) | "A5: delegated-task.md says a task is marked complete only after verdict passes" | reference/delegated-task.md "A task is marked complete only after `task-step verdict` passes" | DELETE (1) |
| 313-323 (loop over agents/impl-*.md; 4 source assertions at 316, 317, 318, 321) | A8: "carries the anti-hardcoding clause" / "report-incorrect-tests clause" / "tests-are-immutable clause" / "(non-Sonnet) carries the scope-limit clause" | agents/impl-*.md clauses ("general solution ... never one that only passes ... hardcoded", "when a test looks wrong, report it", "never edit or delete an existing test unless the brief names it", "change only what the brief asks for"). No script reads them (rg of scripts/ hooks/ config/ finds none). | DELETE (4 source lines; executed = 3 x agents + 1 x non-Sonnet agents). Line 312 (count of impl-*.md > 0) is structural; with the loop gone it is orphaned, delete with the A8 block (lines 310-324). |
| 492-500 (7) | A16: "the README has an unattended-runs section" / "documents auto mode" / "ties auto mode to wave implementers" / "gives the reason: a permission prompt stalls..." / "documents worktree.baseRef" / "set to \"head\"" / "gives the reason: default branches from origin while local main may be ahead" | plugins/dforge/README.md "## Unattended runs" section (config/schema.mjs 'Unattended runs' is a settings-group title, not read from README) | DELETE (7) -> whole A16 block (lines 490-501) |
| 506-512 (3) | A18: "(control) the base executing-plans inline rule is the sentence this plan replaced" / "executing-plans tells the inline session to run the task check once before committing" / "no longer asks for the full suite before every commit" | skills/executing-plans/SKILL.md + references: "Run the focused test while you work and the task check once before committing, in place of the full suite." (also git-shows the base version) | DELETE (3) |
| 520-521 (1) | "A18: reference/native-codex.md is byte-identical to its last planned edit" (git diff --stat vs 4bf4e4d2) | reference/native-codex.md whole file (identity freeze, named by the earlier ruling). Scripts only cite the file name/§Existing plans in error messages (review-route:65, task-step:583, plan-lint:96, plan-revise:282, lens-route:52) and do not parse it. | DELETE (1); delete lines 516-524 (comment + `native_base` block) |
| 525-531 (4) | A18: "the by-hand §2 runs suite-run itself" / "on a DONE report" / "in the background at the task's head" / "treats a non-baseline failure as the Important finding of §3" | reference/delegated-task.md "## The steps by hand" §2 | DELETE (4) |

Totals for speed-and-cost.acceptance.test.sh: source assertion lines A2=4, A3=9 (8 in the loop, 1 matches), A4=7, A5=1, A8=4, A16=7, A18=8 -> 40. Executed checks removed: A2 4, A3 17, A4 7, A5 1, A16 7, A18 8, plus A8 (3 per implementer agent file plus 1 per non-Sonnet agent).

After deletion the file keeps A1, A9, A10, A11 (and the A3/A4/A5/A6/A7 script-behaviour checks). Surviving counts need no plan: the file prints "%d passed, %d failed" at runtime (line 534), no literal count.
Cross-file: header comment lines 2-13 name A2/A3/A4/A8/A16/A18 and SKIP_PINS (line 13-14); scripts/test-all.mjs and scripts/test-shards.mjs list the file by name and test-shards.mjs:115 gives a 280 s timing (will shrink: A2 pin run is skipped under DR_TEST_ALL anyway).

## speed-and-cost-followups.acceptance.test.sh  (DELETE source assertion lines: 9; executed: 12)

| Lines | Label | Markdown + phrase pinned | Verdict |
|---|---|---|---|
| 348-361 (A6 block, 6 assertions at 353, 354, 355, 356, 357-358, 359-360; `doc()` redefined at 350) | A6: "task-reviewer-prompt.md says baseline runs only a command the plan names" / "delegated-task.md says a baseline command runs only when the plan names it" / "says a plan-named command runs unsandboxed" / "says review seats write only their report files" / "delegated-suite.test.sh pins the baseline, unsandboxed and report-file sentences" / "task-step-text.test.sh pins the reviewer prompt's baseline sentence" | skills/subagent-driven-development/references/task-reviewer-prompt.md; reference/delegated-task.md; the last two assert that OTHER test files contain pins (meta-pins) | DELETE whole block (6). The last two fail as soon as delegated-suite.test.sh / task-step-text.test.sh lose those pins. |
| 446 | "A20: process-graph.md has no ./references/ label" | skills/subagent-driven-development/references/process-graph.md absence of `./references/` | DELETE (borderline: link text; no script reads it) |
| 447-449 (loop, 4 executed, 1 source line 448) | "A20: <file> points at ledger.md or recovery.md for the Recovery table" | subagent-driven-development/SKILL.md, executing-plans/SKILL.md, both references/setup.md: a line with "recovery" naming ledger.md/recovery.md | DELETE (borderline: a link-wording check; skill-split-planning.test.sh already verifies links resolve) |
| 450 | "A20: writing-plans/SKILL.md names design-phase.md" | skills/writing-plans/SKILL.md mention of design-phase.md | DELETE (borderline: link wording) |

Totals: 6 (A6) + 3 (A20 lines 446, 448, 450) = 9 source lines; executed 6 + 1 + 4 + 1 = 12.

KEEP/other in this file (no pin): A1-A4, A7-A11, A13-A16 (impl-stop-gate/task-step/suite-run behaviour), A23 (validators), A12 lines 332-336 (greps the TEXT OF OTHER TEST FILES for case shapes; meta, not a skill/reference wording pin; still must be re-read if those suites change), 451-452 (runs skill-split-planning.test.sh), 453-454 (greps other tests for SD=), 456-465 (copies agents/ and runs impl-clauses.test.sh: depends on impl-clauses.test.sh surviving; see that file's table), 470-475 A21 (asserts on docs/dforge/notes/2026-10-28-pipeline-smoke.md, a docs note, not a skill/reference/criteria/agent/prompt file; borderline).
Counter note: runtime "%d passed" (line 497), no literal count. test-all.mjs:96 lists shard groups by test id ('A6' in group 1); removing A6 leaves a stale id that selects nothing (harmless; update for tidiness). Header comment lines 4-5 name statements A6/A20.

## test-volume-rules.acceptance.test.sh  (0 DELETE)
All assertions run plan-lint / lens-route on fixtures. Excluded: no wording pins. (Reads criteria/lenses/security.md only to copy and rewrite its `Applies:` line, line 247: fixture, consumed by lens-route.)



---

# PART g1

# g1: wording pins in the plan/roadmap/register/review/criteria/route suites

Scope: all ten files in /root/repositories/darkraise-ai-plugins/plugins/dforge/tests, each read in full.
Rule applied: docs/dforge/specs/2026-11-11-test-volume-rules-design.md, "Behavior, not text".
Line numbers are the current files (no edits made). All paths below are relative to plugins/dforge/tests/.

## 1. Totals

DELETE: 23 assertions in 2 files (plan-revise.test.sh 16, criteria.test.sh 7). Of the 7 in criteria.test.sh, 5 are BORDERLINE (shape-of-file checks, see section 2.2); the other 18 are clear.

| File | DELETE | KEEP / excluded |
|---|---|---|
| plan-lint.test.sh | 0 | all assertions read plan-lint output |
| plan-lib.test.sh | 0 | all assertions call lib/plan.sh functions |
| plan-amend.test.sh | 0 | all assertions run plan-amend / plan-lint |
| plan-revise.test.sh | 16 (357, 359-373) | rest run plan-revise; 356 and 358 structural (kept) |
| roadmap.test.sh | 0 | all assertions run scripts/roadmap, scripts/register |
| register.test.sh | 0 | all assertions run scripts/register or lib/register.sh |
| review-record.test.sh | 0 | all assertions run scripts/review-record |
| criteria.test.sh | 7 (35, 37, 42, 47, 51, 78, 81) | Applies checks KEEP(lens-route, review-record); ids/schema cross-checks KEEP(run-codex-review.sh); ASCII/exists structural |
| lens-route.test.sh | 0 | all assertions run scripts/lens-route |
| depth-route.test.sh | 0 | all assertions run scripts/depth-route and lib/depth.sh |

## 2. Per-file tables

### 2.1 plan-revise.test.sh (16 DELETE)

Block lines 350-373 ("the skill's prose, pinned where a rule would otherwise rot"). Every `present` call greps skills/revising-plans/SKILL.md (or using-dforge/SKILL.md) for a sentence. Consumer search: `rg -F` of each phrase over scripts/, hooks/, config/, evals/ found no reader. The only hit is "completed.md via PR, no ledger" (scripts/plan-revise:251), which plan-revise PRINTS as evidence text; no script READS the skill's copy of it, so it is still a pin.

| Line | Label | Markdown and phrase pinned | Verdict | Note |
|---|---|---|---|---|
| 356 | the skill exists | skills/revising-plans/SKILL.md existence | KEEP (structural, file existence) | optional: drop with the block if the judge wants it gone |
| 357 | the skill revises Claude plans only | revising-plans/SKILL.md: "revises Claude plans only" | DELETE | whole block, see below |
| 358 | the skill is named | revising-plans/SKILL.md: "name: revising-plans" | KEEP (structural, frontmatter name; `claude plugin validate`) | optional drop |
| 359 | the skill refuses a live plan | "Never edit a plan whose ledger names it" | DELETE | |
| 360 | the skill hard-stops a plan awaiting a merge | "completed.md via PR, no ledger" | DELETE | phrase also printed by scripts/plan-revise:251 as output; the skill copy is not read by any script |
| 361 | continues on a no-ledger plan only after confirmation | "Continue only on that explicit confirmation" | DELETE | |
| 362 | runs each gate rather than printing its path | `bash "$(bash <plugin-root>/scripts/executors path <id> gate)"` | DELETE | command is a skill instruction; scripts/executors does not read the skill |
| 363 | names the amend script, not a skill | "bash <plugin-root>/scripts/plan-amend" | DELETE | |
| 364 | scores before offering an executor | "Scoring precedes the executor question" | DELETE | |
| 365 | ticks only an executor the roster reports usable | "and the roster reports it" | DELETE | |
| 366 | filters the roster by the gate | "ignore every row whose gate did not print" | DELETE | |
| 367 | re-runs the report before settling execution | "Re-run plan-revise after writing the Executor" | DELETE | |
| 368 | reconciles an existing Executor line | "replace it with the printed rung" | DELETE | |
| 369 | takes the first rung when several are listed | "take the first, the highest-priority executor that admits the unit" | DELETE | |
| 370 | leaves a thin task unscored | "A guessed score is worse than a visible gap" | DELETE | |
| 371 | allows the split Rule S requires | "Splitting a task Rule S rejects is part of this skill" | DELETE | |
| 372 | the routing table lists the skill | skills/using-dforge/SKILL.md: "dforge:revising-plans" | DELETE | no script parses the routing table (scripts/ hooks/ config/ have no reader of using-dforge's table) |
| 373 | the skill pushes the revised plan | `10. **Push the revised plan.** Run \`bash <plugin-root>/scripts/darkmem-sync push\`` | DELETE | |

Whole-block / helper call-out:
- Delete lines 357, 359-373 (16 assertions). The comment at 350 and the `present()` helper (352-355) exist only for this block. `present` is still used by 358 if 358 stays; if the judge also drops 356 and 358, delete the entire block 350-373 plus `SK=` (351) and the helper, and the next section comment (375) follows directly.
- Recommended minimal edit: delete 359-373 and 357; keep 356, 358 (rewrite 358 as a plain `check`, or keep `present`).

### 2.2 criteria.test.sh (7 DELETE)

Consumers verified: scripts read criteria files only as follows. lens-route reads `^Applies: ` (scripts/lens-route:74); review-record reads `Applies:` of test-quality.md (scripts/review-record:117); plan-lint checks that criteria/lenses/<id>.md exists (scripts/plan-lint:470); task-step pastes criteria/task-review.md whole into a Codex prompt with `sed 's/^#/##/'` (scripts/task-step:911); run-codex-review.sh cats codex-final-review.md whole (scripts/run-codex-review.sh:219) and reads the two *-schema.json files. No script greps `## Ground Truth Note`, `## Criteria`, `### ` heading counts, `{#id}` slugs, `<severity>` or `No findings.` (rg over scripts/, hooks/, config/, evals/).

| Line(s) | Label | Markdown and phrase pinned | Verdict | Note |
|---|---|---|---|---|
| 20-23 | criteria directory / TEMPLATE.md exists | existence | KEEP (structural) | |
| 35-36 | `$base: has a ground truth note` | every criteria/*.md and lenses/*.md: `^## Ground Truth Note$` | DELETE (BORDERLINE: heading-shape check) | no script reads it; the file is read by a model, not parsed |
| 37-38 | `$base: has a criteria section` | `^## Criteria$` | DELETE (BORDERLINE) | |
| 42 (computed 40-41) | `$base: has 2 to 4 criteria` | count of `^### ` headings between 2 and 4 | DELETE (BORDERLINE) | |
| 47 (computed 46) | `$base: every criterion pins a slug-safe id` | `^### .*{#slug}$` on every heading | DELETE (BORDERLINE) | the only `{#id}` readers are the schema cross-checks at 100 and 125 (task-review and plan-review only), which are kept |
| 51-52 (computed 49-50) | `$base: criterion ids are unique` | uniqueness of `{#slug}` ids | DELETE (BORDERLINE) | |
| 55-56 | `$base: content is ASCII only` | encoding of every criteria file | KEEP (structural, encoding; files are catted into Codex requests by task-step and run-codex-review.sh) | |
| 60 | `$base: one Applies line` | lenses/*.md `^Applies: ` count | KEEP (lens-route:74, review-record:117) | |
| 61-62 | `$base: every Applies clause parses` | Applies grammar `always|ui-paths|paths ...|added ...` | KEEP (lens-route, the grammar it parses) | |
| 66-68 | the lenses exist | file list of criteria/lenses | KEEP (structural, file existence; lens-route and plan-lint:470 read these files) | |
| 74 | codex-final-review.md exists | existence | KEEP (structural; run-codex-review.sh:219) | |
| 76-77 | codex-final-review: content is ASCII only | encoding | KEEP (structural) | |
| 78-79 | codex-final-review: names the finding heading shape | codex-final-review.md: `` `### <severity>: <one-line claim>` `` | DELETE | sentence pin; run-codex-review.sh only cats the file and no script parses the seat's reply for this heading |
| 80-81 | codex-final-review: names the empty sentinel | codex-final-review.md: "write `No findings.` and stop" | DELETE | sentence pin; no script reads `No findings.` |
| 87-88 | task-review exposes the four contracted ids | task-review.md `{#quality #scope #spec #verification}` | KEEP (anchors the schema cross-check; task-step:913 and run-codex-review.sh read codex-review-schema.json, which must equal these ids) | borderline-kept: markdown ids, but guarded by the script-consumed schema |
| 94-106 | codex-review-schema checks | JSON schema vs task-review ids | KEEP (run-codex-review.sh:16) | |
| 110, 120 | plan-review.md / codex-plan-review-schema.json exist | existence | KEEP (structural) | |
| 112-113 | plan-review exposes the four contracted ids | plan-review.md `{#assumptions #coherence #coverage #executability}` | KEEP (same reason, schema read by run-codex-review.sh:17) | borderline-kept |
| 121-136 | codex-plan-review-schema checks | JSON schema | KEEP (run-codex-review.sh:17) | |

Whole-block / helper call-out:
- After deleting 35-38 and 40-52 the per-file loop (25-64) keeps only the ASCII check (54-56) and the lens Applies `case` (58-63). The local variables `headings`, `in_range`, `pinned`, `ids`, `uniq_ids` (lines 40-41, 46, 49-50) and the comments at 44-45 and 54 (keep 54, it describes the ASCII check) die with their checks: delete 40-52 whole.
- Delete 78-81 inside the `if [ -f "$FR" ]` block (76-82); that block keeps the ASCII check.
- Stale comments to rewrite if the above goes: header lines 1-8 (the "2-to-4 bound" paragraph and "criterion ids that stay stable"), lines 29-32 (mention "no ground-truth note, no criteria section and no pinned ids"), lines 70-72 ("its two load-bearing instructions are pinned").
- If the judge rejects the 5 BORDERLINE items, the clear DELETE count is 18 across both files minus those, i.e. plan-revise 16 + criteria 2 = 18.

## 3. EXCLUDED borderline cases (not counted)

- plan-lint.test.sh:621 greps scripts/plan-amend source for `--no-probe` (count 2): pins script text, not markdown.
- plan-lint.test.sh:551, 830-831, 905, 917, 923: copy or read reference/ladder.md and reference/codex-routing.json, but only as fixtures/inputs to plan-lint (ladder blocks and routing JSON are parsed by plan-lint via ladder_block), so behaviour.
- plan-lint.test.sh:1331-1379 (Step 1 forms) and 1395-1402 (Lenses lines): assertions on plan-lint output; the forms live in test-step-forms.md but the test only runs the script over its own fixtures.
- plan-lint.test.sh:70-135, 137-183 (claude_plan, codex_plan fixtures), plan-revise.test.sh:33-66, lens-route.test.sh:33-55, depth-route.test.sh:46-66: heredoc fixtures written by the test and fed to a script.
- plan-lint.test.sh:1404-1474 (UI/UX contract): fixture spec and plan fed to plan-lint.
- plan-revise.test.sh:70 "script exists": file existence of a script.
- plan-revise.test.sh:123-134, 182-185: read reference/ladder.md and stub-ladder fixture; ladder blocks are parsed by plan-revise.
- register.test.sh:308-316 "own register parses": runs `scripts/register check` over the repository's real register files; behaviour of the parser on real data, not text.
- review-record.test.sh:141-147: copies scripts and writes a fixture lens file to test the "no paths clause" error; behaviour.
- lens-route.test.sh:66 "the criteria path exists": checks the path the script printed exists; structural.
- lens-route.test.sh:178-186: copy of the real criteria/lenses with the Applies line sed-edited, fed to lens-route; behaviour of the Applies parser.
- criteria.test.sh:55-56, 76-77 (ASCII only): encoding check, structural.
- criteria.test.sh:87-88, 112-113: literal id lists; kept because the matching JSON schemas are script-consumed and the tests at 100 and 125 compare them. If the judge wants minimal retention, these two are the next-weakest KEEPs.
- plan-revise.test.sh:356, 358: file existence and frontmatter `name:`, kept as structural.
- test-step-forms.md, plan-review.md, writing-plans/SKILL.md, README: no file in this group greps any of them.

## 4. Counters and expected totals

- plan-revise.test.sh: deleting 16 assertions leaves every script-output assertion. The counter is the generic `pass`/`fail` in `check()` (lines 9-13) and the closing `printf '\n%d passed, %d failed\n'` (line 397); no literal expected total, no `1..N` plan. Nothing to update.
- criteria.test.sh: deleting 7 assertion sites leaves the ASCII, Applies, lenses, schema and id checks (never zero). Counter is the generic `check()` (15-18) and closing printf (138); no literal total. Nothing to update.
- Outside the files: scripts/test-shards.mjs:92 (`plan-revise.test.sh`: 560) and :55 (`criteria.test.sh`: 10) and scripts/test-all.mjs:85 (plan-revise 900) are runtime weights/limits in seconds, not assertion counts. Deleting grep-only checks changes neither run time materially; no edit needed.
- No file in this group has any other pin to touch. The other eight files need no edits.



---

# PART g2

# Wording pins in the g2 test group

All paths are under `plugins/dforge/tests/` unless stated. Line numbers are from the files as read on 2026-11-12 (checked out at main, clean). Consumers were checked by grepping `plugins/dforge/scripts`, `hooks`, `config`, `criteria`: the only scripts that read markdown at runtime are `task-step` (templates `implementer-prompt.md`, `task-reviewer-prompt.md`, `group-reviewer-prompt.md`, `re-review-prompt.md`: the fenced `prompt: |` body and the `[PLACEHOLDER]` tokens only; `criteria/task-review.md`; `agents/impl-*.md` existence), `lens-route`/`plan-lint`/`review-record` (`criteria/lenses/*.md`), `plan.sh`/`run-codex-*`/`run-agy-task.sh`/`plan-revise` (fenced blocks of `reference/ladder.md`), `run-codex-review.sh` (`criteria/codex-final-review.md`), `session-start.sh` (cats `skills/using-dforge/SKILL.md` whole). No script reads any sentence of `reference/delegated-task.md`, `parallel-waves.md`, `final-review.md`, `executor-lane.md`, `test-tiers.md`, `auto-run.md`, `session-budget.md`, `finishing-a-development-branch`, `handoff`, `subagent-driven-development/SKILL.md` or its `ledger.md`/`escalation.md`/etc., `writing-plans`, `requesting-code-review`, `executing-plans`, or `codex-tools.md`. Sentinel strings such as `Auto run: clearing` live in `scripts/turn-end.sh` and `hooks/cockpit/lib.ts` (`AUTO_SENTINELS`), but those read the assistant's message, not the skill text.

## 1. Totals

| file | DELETE | KEEP (by consumer or structure) |
|---|---|---|
| clean-session-phases.acceptance.test.sh | 14 | all remaining (script output); 2 structural excluded (A11 size) |
| clean-session-phases.acceptance.test.ts | 0 | all (cockpit behaviour) |
| task-loop-steps.acceptance.test.sh | 17 | all remaining; 3 subprocess assertions (687-690) excluded |
| task-loop-steps.acceptance.test.ts | 0 | all (cockpit behaviour) |
| task-step-base.test.sh | 3 | all remaining (script output) |
| task-step-settle.test.sh | 2 | all remaining (script output) |
| task-step-suite.test.sh | 3 | all remaining (script output) |
| task-step-text.test.sh | 222 | 7 lines / 11 assertions: 84-85 (impl-stop-gate), 106-109 (task-step fill), 117-118 (task-step); 105, 250, 262 structural |
| task-step.test.sh | 0 | all (script output) |
| typed-seats-and-drafting.acceptance.sh | 17 executed (18 call sites; 132 and 134 are alternative branches) | A5 fixtures to seats.test.sh, A12 arithmetic, A13 git state, A12 line 160-161 `lib.ts` constant |
| typed-seats-and-drafting.acceptance.test.ts | 0 | all (engine behaviour) |
| **Total** | **278 DELETE in 7 files** | |

## 2. Per-file tables

### clean-session-phases.acceptance.test.sh (14 DELETE)

| line(s) | test label | markdown file and phrase pinned | verdict | note |
|---|---|---|---|---|
| 124 | A4: auto-run.md does not name switch-resume | reference/auto-run.md: absent `switch-resume` | DELETE | Pairs with 120-123 (usage text, script output: KEEP `scripts/auto-run`) |
| 155-156 | A6: the Auto run section orders phase finish, handoff steps 0-3, next-step, clear --phase, Auto run: clearing | skills/finishing-a-development-branch/SKILL.md `## Auto run`: six phrases in order | DELETE | `ordered()` helper (39-49) exists only for this; delete whole |
| 157 | A6: it says the rule applies on a phase other than finish | finishing SKILL.md `## Auto run`: regex `(not\|other than) finish` | DELETE | |
| 158 | A6: it says phase finish continues the skill | finishing SKILL.md `## Auto run`: regex `phase finish ... (continue\|follow)` | DELETE | |
| 161 | A7: session-budget keeps the same-session sentence | reference/session-budget.md: `Once the final review is clean, finishing runs in the same session` | DELETE | |
| 163 | A7: the auto-run exception follows the sentence | session-budget.md: `auto run` within 160 chars after the sentence | DELETE | |
| 165 | A7: handoff's When keeps nothing stops finishing | skills/handoff/SKILL.md `## When`: `nothing stops finishing once the final review is clean` | DELETE | |
| 167 | A7: nothing outside the Auto run section names auto-run clear | finishing SKILL.md outside `## Auto run`: absent `auto-run clear` | DELETE | |
| 168 | A7: the Auto run section names auto-run clear | finishing SKILL.md `## Auto run`: `auto-run clear` count 1 | DELETE | |
| 183-185 (loop, 5 phrases) | A15: auto-run.md Finishing names <needle> | reference/auto-run.md `## Finishing`: `parked`; `Ruling:`; `final review residual`; `final-fix-report.md`; `final-rereview-report.md` | DELETE | |

Whole-block: lines 152-168 and 182-185 (the "document statements" block less A11) and the helpers `section()` (50-52), `flat()` (53), `ordered()` (39-49) are used nowhere else; `matches()` (35-38) is still used at line 105 and `has`/`lacks`/`check` remain. Also delete variables `FIN`, `auto_section`, `budget`, `tail_after`, `handoff_when`, `outside_auto`, `finishing` with them.

Script-output KEEP (spot list): 97-107 and 116-123 (`scripts/auto-run`, `next-step`), 139-150 (`next-step` block text and `auto-run status`), 217-280 (`scripts/review-package`).

### clean-session-phases.acceptance.test.ts (0 DELETE)

No markdown is read. Every assertion is on the cockpit engine's events (commands, auto-run calls, prompts, state file). KEEP.

### task-loop-steps.acceptance.test.sh (17 DELETE)

| line(s) | test label | markdown file and phrase pinned | verdict | note |
|---|---|---|---|---|
| 657 | A14: the skill tells a session to end the turn when only waiting remains | skills/subagent-driven-development/SKILL.md: regex `[Ee]nd the turn` | DELETE | |
| 658 | A14: and says it for the case where waiting is all that remains | sdd SKILL.md: regex `[Oo]nly waiting remains\|nothing left but waiting` | DELETE | |
| 659 | A14: the skill no longer carries the 290-second sleep wait | sdd SKILL.md: absent `sleep 29[0-9]` | DELETE | |
| 660 | A14: nor the stretch-over marker | sdd SKILL.md: absent `stretch-over` | DELETE | |
| 663-664 | A14: every mention of Monitor or sleep in the skill is a prohibition | sdd SKILL.md: every line matching `Monitor\|sleep` also has a prohibition word | DELETE | |
| 665 | A14: the skill does not prescribe a Monitor call | sdd SKILL.md: absent `Run/Use/... Monitor` | DELETE | |
| 666 | A14: codex-tools.md keeps wait_agent | skills/using-dforge/references/codex-tools.md: `wait_agent` | DELETE | |
| 667 | A14: codex-tools.md keeps bounded stretches | codex-tools.md: `bounded stretches` | DELETE | whole `a14()` function (651-668) deletes |
| 675 | A15: the re-review prompt names dforge:judge-sonnet-high | skills/subagent-driven-development/references/re-review-prompt.md: `dforge:judge-sonnet-high` | DELETE | task-step fills only placeholders and the `prompt: |` body; the seat line it prints (`seat: dforge:judge-sonnet-high`) is its own printf (task-step line 518), covered by task-step.test.sh |
| 676 | A15: and dforge:judge-opus for a subtle concurrency fix | re-review-prompt.md: `dforge:judge-opus for a subtle concurrency fix` | DELETE | |
| 677 | A15: it names no general-purpose seat | re-review-prompt.md: absent `general-purpose` | DELETE | |
| 678 | A15: it carries no model argument line | re-review-prompt.md: absent `^ *model:` | DELETE | |
| 679 | A15: it requires the diff file | re-review-prompt.md: `DIFF_FILE ... REQUIRED` | DELETE | the placeholder itself is consumed (task-step line ~487 dies on an unfilled one), the word REQUIRED is not |
| 680 | A15: it carries no git diff fallback | re-review-prompt.md: absent `git (diff\|show\|log)` | DELETE | |
| 681 | A15: it carries no fallback wording | re-review-prompt.md: absent `[Ff]all ?back ...` | DELETE | |
| 684 | A15: delegated-task.md's Scoped re-review row names no general-purpose seat | reference/delegated-task.md row `\| Scoped re-review`: absent `general-purpose` | DELETE | |
| 685 | A15: and names dforge:judge-sonnet-high | delegated-task.md Scoped re-review row: `dforge:judge-sonnet-high` | DELETE | |

Whole-block / helpers: `a14()` (lines 651-668) holds only wording pins and deletes whole. In `a15()` (672-691) the lines 673-685 (`RRP`, `text`, `DT`, `row`) go; lines 686-690 run `tests/seats.test.sh` as a subprocess (3 assertions, EXCLUDED, see section 3); if those are also dropped, delete `a15()` whole. Header comment lines 3-4 ("statements A1-A11, A14 and A15") need updating.

All other assertions in this file run `task-step`, `suite-run`, `in-flight`, `turn-end.sh`, `review-route`, `lens-route`, or `sdd-workspace` and check their output or files they write: KEEP.

### task-loop-steps.acceptance.test.ts (0 DELETE)

No markdown is read; engine behaviour (reconcile prompt, timers, failures). KEEP.

### task-step-base.test.sh (3 DELETE)

| line(s) | test label | markdown file and phrase pinned | verdict | note |
|---|---|---|---|---|
| 636 | the doc says a base run under rereview --covered takes up to an hour | reference/delegated-task.md: `which takes up to an hour (TASK_STEP_BASE_TIMEOUT)` | DELETE | |
| 637 | the doc no longer says it takes up to ten minutes | delegated-task.md: absent `which takes up to ten minutes` | DELETE | |
| 638 | the doc gives a Worktree setup its own time limit, twice | delegated-task.md: `as long again for a **Worktree setup:**` count 2 | DELETE | |

Whole-block: lines 634-638 (the `# Row 29` comment, the `dt=` flatten at 635 and the three checks) and the `DT=` assignment at line 10 delete whole. Everything else runs `task-step`/`suite-run` against fixtures: KEEP.

### task-step-settle.test.sh (2 DELETE)

| line(s) | test label | markdown file and phrase pinned | verdict | note |
|---|---|---|---|---|
| 30 | the reviewer prompt names the exists form | skills/subagent-driven-development/references/task-reviewer-prompt.md: `- cannot-verify: exists <path\|symbol> at <base\|head>, expect <present\|absent> - <why>` | DELETE | Borderline: `task-step verdict` parses this grammar in the reviewer's report; nothing reads the template line. The parse is tested by the rest of this file. |
| 31 | the reviewer prompt names the baseline form | task-reviewer-prompt.md: `- cannot-verify: baseline <command>, expect <pass\|fail> - <why>` | DELETE | same |

Whole-block: lines 30-31 and the `TRP=` assignment at line 11 delete whole. Everything else is `task-step verdict` behaviour: KEEP.

### task-step-suite.test.sh (3 DELETE)

| line(s) | test label | markdown file and phrase pinned | verdict | note |
|---|---|---|---|---|
| 327-328 | the doc: every failing line is in the fix file and the digest shows 20 | reference/delegated-task.md: `is in the fix file, however many; the digest shows the first 20 ...` | DELETE | |
| 329-330 | the doc: the last Verified section is the current evidence | delegated-task.md: `The last ## Verified section of the report is the current evidence` | DELETE | |
| 331-332 | the doc: past round 2 the line names the suite log | delegated-task.md: `Past round 2 verdict writes no fix file ...` | DELETE | |

Whole-block: lines 325-332 (the `# --- the doc says so ---` comment, `dt=` at 326, three checks) and the `DT=` assignment at line 11 delete whole. Everything else: KEEP.

### task-step-text.test.sh (222 DELETE)

Almost the whole file is wording pins. The 222 rows below are 181 single assertions plus 8 loops (41 phrases). Consumers checked: none of the targeted files' sentences is read by a script. Ledger-grammar lines (130-139, 204-214, 229-241, 268-273) document line forms that `next-step`, `wave` and `review-record` parse in the ledger, but those scripts read the ledger a session wrote, not these documentation sentences; the parse itself is tested in their own suites.

| line(s) | test label | markdown file and phrase pinned | verdict | note |
|---|---|---|---|---|
| 45 | delegated-task.md has the by-hand section | reference/delegated-task.md | "$(grep -c '^## The steps by hand' "$DT")" "1" | DELETE | |
| 47-49 (loop, 3 phrases) | the loop steps name <call> | reference/delegated-task.md (loop steps) | `task-step start PLAN_FILE N`; `task-step review PLAN_FILE N`; `task-step rereview PLAN_FILE N` | DELETE | |
| 50-52 (loop, 4 phrases) | the loop steps no longer carry: <gone> | reference/delegated-task.md (loop steps) | absent: `scripts/review-package`; `scripts/task-brief PLAN_FILE N`; `Record BASE`; `run scripts/lens-route` | DELETE | |
| 53 | only the cache rule runs date +%s in the loop steps | reference/delegated-task.md (loop steps) | "$(loop_steps \| grep -cF 'date +%s')" "1" | DELETE | |
| 54 | the fix message is a file of finding bullets | reference/delegated-task.md | '<workspace>/task-<N>-fix-<R>.md' | DELETE | |
| 55 | the fix message bullet format | reference/delegated-task.md | 'per open finding, - <file>: <finding one-liner>, then a blank line, t... | DELETE | |
| 56 | the skip rule needs --covered | reference/delegated-task.md | 'bash <plugin-root>/scripts/task-step rereview PLAN_FILE N (with --cov... | DELETE | |
| 57 | a skipped re-review is recorded on the fix-round line | reference/delegated-task.md | 're-review skipped (<n> lines)' | DELETE | |
| 58 | the review step names the checks | reference/delegated-task.md | 'lines, each clean or the short SHA and what it found' | DELETE | |
| 59 | a repeated start keeps the recorded base | reference/delegated-task.md | 'keeps the recorded BASE' | DELETE | |
| 60 | the Codex seat line carries the fallback judge | reference/delegated-task.md | 'the judge after fallback: as the seat when it' | DELETE | |
| 61 | a failed route is read off the seat line | reference/delegated-task.md | '(review-route exited <N>: …)' | DELETE | |
| 62 | the gate line position is stated | reference/delegated-task.md | 'A gate: line right' | DELETE | |
| 64 | waves open a task with --wave | reference/parallel-waves.md | 'bash <plugin-root>/scripts/task-step start PLAN_FILE N --wave <k>' | DELETE | |
| 65 | waves review against the task ref | reference/parallel-waves.md | '--head <TASK_REF> to' | DELETE | |
| 66 | waves pass the worktree to a Codex review | reference/parallel-waves.md | '--cwd <worktree>, so that a Codex seat' | DELETE | |
| 67 | an overlap rebase passes --base | reference/parallel-waves.md | 'task-step rereview PLAN_FILE N --head <TASK_REF> --base <that HEAD>' | DELETE | |
| 68 | waves batch the in-hand cannot-verify items | reference/parallel-waves.md | 'of every task whose review is in hand when one task reaches its canno... | DELETE | |
| 69 | the wave base check runs through suite-run | reference/parallel-waves.md | 'bash <plugin-root>/scripts/suite-run -- bash -c '"'"'<the check>'"'"'... | DELETE | |
| 70 | the wave integration check runs through suite-run | reference/parallel-waves.md | "$(grep -cF 'scripts/suite-run -- bash -c' "$PW")" "2" | DELETE | |
| 71 | the wave check output file is gone | reference/parallel-waves.md | 'wave-<k>-check.txt' | DELETE | |
| 73 | the final review runs suites through suite-run | reference/final-review.md | 'bash <plugin-root>/scripts/suite-run -- <command>' | DELETE | |
| 74 | finishing runs the suite through suite-run | skills/finishing-a-development-branch/SKILL.md | 'bash <plugin-root>/scripts/suite-run -- <test command>, in the backgr... | DELETE | |
| 75 | finishing verifies the merged result through suite-run | skills/finishing-a-development-branch/SKILL.md | 'bash <plugin-root>/scripts/suite-run -- <test command>' | DELETE | |
| 76 | implementers no longer run the full suite through suite-run | skills/subagent-driven-development/references/implementer-prompt.md | 'scripts/suite-run' | DELETE | |
| 77 | implementers no longer run the full suite before committing | skills/subagent-driven-development/references/implementer-prompt.md | 'full suite once before committing, not after every edit.' | DELETE | |
| 78 | implementers run the focused tests that cover their change | skills/subagent-driven-development/references/implementer-prompt.md | 'Before each commit, run the focused tests that cover what you changed... | DELETE | |
| 79 | the controller runs the task check beside the review | skills/subagent-driven-development/references/implementer-prompt.md | 'The controller runs the task check beside the review of your' | DELETE | |
| 80 | the run-control paragraph names context-size by plugin root | skills/subagent-driven-development/references/implementer-prompt.md | 'Never run [PLUGIN_ROOT]/scripts/context-size, scripts/auto-run or' | DELETE | |
| 81 | the report gains a Verified section | skills/subagent-driven-development/references/implementer-prompt.md | '## Verified: one bullet per command you ran to check your work.' | DELETE | |
| 82 | the reply ends with the Report line | skills/subagent-driven-development/references/implementer-prompt.md | 'Report: <absolute path of the report file>' | DELETE | |
| 87 | the example workflow starts a task with task-step | sdd references/example-workflow.md | '[task-step start PLAN_FILE 1:' | DELETE | |
| 88 | the example workflow reviews with task-step | sdd references/example-workflow.md | '[task-step review PLAN_FILE 1:' | DELETE | |
| 89 | the example workflow re-reviews with task-step | sdd references/example-workflow.md | '[task-step rereview PLAN_FILE 2:' | DELETE | |
| 90 | the example workflow no longer hand-runs review-package | sdd references/example-workflow.md | 'review-package PLAN_FILE a1b2c3d HEAD' | DELETE | |
| 91 | the budget line is on every task-step digest | skills/subagent-driven-development/SKILL.md | 'every scripts/task-step' | DELETE | |
| 92 | the rationalization row names the skip rule | sdd references/rationalizations.md | 'Only task-step rereview --covered skips one' | DELETE | |
| 93 | the rationalization row no longer says every round is re-reviewed | sdd references/rationalizations.md | 'Every round ends with a scoped re-review.' | DELETE | |
| 94 | inline mode hands delegated tasks to delegated-task.md | skills/executing-plans (SKILL+references view) | '[delegated-task.md](../../reference/delegated-task.md) for this task ... | DELETE | |
| 95 | inline mode restates no hand-run review mechanic | skills/executing-plans (view) | "$(grep -cE 'date \+%s\|codex-gate\|lens-route' "$INLINE")" "0" | DELETE | |
| 98 | the reviewer prompt: baseline runs only a command the plan names | .../task-reviewer-prompt.md | 'It runs only a command the plan names:' | DELETE | |
| 99 | the reviewer prompt names the Run and Check lines | .../task-reviewer-prompt.md | 'Integration check, or the command of one of the' | DELETE | |
| 100 | the reviewer prompt: copied exactly, anything else goes to the ruling seat | .../task-reviewer-prompt.md | 'copied exactly. Any other command is not run and goes to the ruling s... | DELETE | |
| 101 | the reviewer prompt no longer says a baseline command runs verbatim | .../task-reviewer-prompt.md | 'run verbatim, through' | DELETE | |
| 110 | the group package holds one section per task | sdd references/group-reviewer-prompt.md | 'one section per task, headed ## Task <N>' | DELETE | |
| 111 | the group reviewer scores each task on its own | sdd references/group-reviewer-prompt.md | 'Score each task on its own' | DELETE | |
| 112 | the group report holds one block per task | sdd references/group-reviewer-prompt.md | 'one block per task, headed ### Task <N>' | DELETE | |
| 113 | a group finding names its task | sdd references/group-reviewer-prompt.md | 'prefix its file with (Task <N>) ' | DELETE | |
| 114 | a finding in one task never fails another | sdd references/group-reviewer-prompt.md | 'A finding in one task never fails another task' | DELETE | |
| 115 | the group reviewer reads a section's lens files | sdd references/group-reviewer-prompt.md | 'a **Lenses:** line' | DELETE | |
| 116 | the group template takes no single diff placeholder | sdd references/group-reviewer-prompt.md | '[DIFF_FILE]' | DELETE | |
| 121 | DONE holds a grouped task | reference/delegated-task.md | 'bash <plugin-root>/scripts/task-step hold PLAN_FILE N' | DELETE | |
| 122 | exit 4 from hold means reviewed alone | reference/delegated-task.md | 'exit 4 means the task is reviewed alone' | DELETE | |
| 123 | the group review call | reference/delegated-task.md | 'bash <plugin-root>/scripts/task-step review --group PLAN_FILE N M …' | DELETE | |
| 124 | the group trigger | reference/delegated-task.md | 'when 4 tasks are held, before you dispatch a task review-route review... | DELETE | |
| 125 | nothing is dispatched while a group is open | reference/delegated-task.md | 'no new task is dispatched until the group is clean' | DELETE | |
| 126 | group fixes run one task at a time | reference/delegated-task.md | 'fixes inside a group run one task at a time' | DELETE | |
| 127 | a concerned or blocked member leaves the group | reference/delegated-task.md | 'leaves the group and is reviewed alone' | DELETE | |
| 128 | a member re-reviews on the moving group head | reference/delegated-task.md | "each member's re-review moves that head on" | DELETE | |
| 129 | a group runs two fix rounds | reference/delegated-task.md | 'A group runs at most two fix rounds' | DELETE | |
| 130 | each member gets its own complete line | reference/delegated-task.md | 'each member gets its own complete line once the group is clean' | DELETE | |
| 131 | the loop's recovery reads a held task | reference/delegated-task.md | '\| awaiting group review (commits …) \|' | DELETE | |
| 132 | the ledger grammar holds the awaiting line | sdd references/ledger.md | 'Task <N>: awaiting group review (commits <a7>..<b7>)' | DELETE | |
| 133 | the ledger grammar holds the group review line | sdd references/ledger.md | 'Group <list>: review round R/2 (Task <N>: <k> open — <one-liners> \| ... | DELETE | |
| 134 | a group list is a comma list or a range | sdd references/ledger.md | 'joined by commas (Group 4,6,7), or a contiguous range (Group <a>-<b>)... | DELETE | |
| 135 | a comma list covers the tasks it names | sdd references/ledger.md | 'a comma list covers the tasks it names' | DELETE | |
| 136 | the recovery table reads a held task | sdd references/ledger.md | '\| awaiting group review \| Reviewed by the next group dispatch' | DELETE | |
| 137 | the recovery table resumes a group review's round 2 per open member | sdd references/ledger.md | 'On a group review'"'"'s line (its clause starts Task <N>:), run round... | DELETE | |
| 138 | the recovery table sends a group review's open findings to the breaker | sdd references/ledger.md | 'Go to the breaker: a group review'"'"'s line (its clause starts Task ... | DELETE | |
| 139 | the recovery table has one row per Group round | sdd references/ledger.md | "$(grep -c '^\| review round [12]/2 on a' "$SDD_LEDGER")" "2" | DELETE | |
| 140 | after compaction a held task waits for its group | skills/subagent-driven-development/SKILL.md | 'awaiting group review is reviewed by the next group dispatch' | DELETE | |
| 141 | the process graph names the group template | sdd references/process-graph.md | './group-reviewer-prompt.md' | DELETE | |
| 142 | the overview no longer reviews every task alone | sdd skill + references (all) | <(sdd_text) 'a judge-scored task review after each task;' | DELETE | |
| 143 | waves hold a grouped task at its ref, in its worktree | reference/parallel-waves.md | 'task-step hold PLAN_FILE N --head <TASK_REF> --cwd <worktree>' | DELETE | |
| 144 | a wave task's hold carries its worktree | reference/delegated-task.md | '--head <task ref> --cwd <worktree>' | DELETE | |
| 145 | a Codex plan holds no task, in DONE and in the group section | reference/delegated-task.md | "$(grep -cF 'On a Host: codex plan no task is held: every task is revi... | DELETE | |
| 146 | a concerned task with only observations is still held | reference/delegated-task.md | 'in subagent mode hold the task first, as DONE says' | DELETE | |
| 147 | recovery never reruns a group review that ran | reference/delegated-task.md | 'the group review ran: never run review --group again' | DELETE | |
| 148 | a missing baseline is never a subset | reference/parallel-waves.md | 'A missing baseline file, an empty <current>, or a grep exit' | DELETE | |
| 149 | the subset test needs grep to exit 1 | reference/parallel-waves.md | 'grep -vxFf <baseline> <current> exits 1' | DELETE | |
| 150 | waves review grouped tasks before any merges | reference/parallel-waves.md | 'once every grouped task in the wave is held, before any of them merge... | DELETE | |
| 151 | a wave member's fix round stays in its worktree | reference/parallel-waves.md | "a member's fix round goes to that task's implementer in its worktree" | DELETE | |
| 152 | a grouped wave task merges once its group is clean | reference/parallel-waves.md | 'or, for a grouped task, its group is clean' | DELETE | |
| 163 | the loop holds two rounds | reference/delegated-task.md | 'Two rounds at most per task:' | DELETE | |
| 164 | round 1 resumes or re-dispatches by cache state | reference/delegated-task.md | '**Round 1 — resume or re-dispatch by cache state.**' | DELETE | |
| 165 | round 2 is a fresh dispatch on the successor rung | reference/delegated-task.md | '**Round 2 — a fresh dispatch on the successor rung.**' | DELETE | |
| 166 | a SPLIT successor keeps the rung for round 2 | reference/delegated-task.md | 'When the successor is SPLIT, round 2 is a fresh dispatch of the same ... | DELETE | |
| 167 | a reserve-tier task takes its reserve successor | reference/delegated-task.md | 'A reserve-tier task takes its reserve successor' | DELETE | |
| 168 | the breaker trips after round 2 | reference/delegated-task.md | "When round 2's re-review still leaves findings open" | DELETE | |
| 169 | the fix-round line counts to 2 | reference/delegated-task.md | 'Task <N>: fix round <R>/2 (' | DELETE | |
| 170 | recovery: round 1 resumes at round 2 | reference/delegated-task.md | '\| fix round 1/2, or fix round 1/5 from an older run \| Resume the lo... | DELETE | |
| 171 | recovery: round 2 goes to the breaker | reference/delegated-task.md | '\| fix round 2/2, or fix round R/5 with R >= 2 from an older run \| G... | DELETE | |
| 172 | a Codex host keeps five rounds | reference/delegated-task.md | 'A Codex host keeps its five-round cap (review_cap: 5)' | DELETE | |
| 173 | a Codex host's five-round schedule | reference/delegated-task.md | 'On a Host: codex plan the loop keeps five rounds:' | DELETE | |
| 174 | a Codex host's recovery row | reference/delegated-task.md | '\| fix round R/5 on a Host: codex plan \| Codex: R < 5 resumes the lo... | DELETE | |
| 175-178 (loop, 8 phrases) | the delegated loop drops: <gone> | reference/delegated-task.md | absent: `**Progress.**`; `progress <p> -> <q>`; `Rounds 4-5`; `Five rounds maximum`; `rounds 1-3 may resume it`; `The five-round cap is the same.`; `skip never triggers escalation`; `returns the progress reading` | DELETE | |
| 179 | the delegated loop names R/5 only for older runs | reference/delegated-task.md | "$DT" | DELETE | |
| 181 | escalation: round 2 climbs the ladder | sdd references/escalation.md | '- **Fix round 2.** Dispatch a fresh implementer on the successor rung... | DELETE | |
| 182 | escalation: the recorded round is 2/2 | sdd references/escalation.md | 'Task <N>: fix round 2/2 (1 addressed, 1 open - <one-liner>; commits <... | DELETE | |
| 183 | escalation: a split comes from the breaker | sdd references/escalation.md | "a split is reached only through the breaker's AMEND" | DELETE | |
| 184 | escalation: the split ruling counts two rounds | sdd references/escalation.md | 'impl-opus-high exhausted after 2 rounds' | DELETE | |
| 185-187 (loop, 4 phrases) | escalation drops: <gone> | sdd references/escalation.md | absent: `Fix rounds 4 and 5`; `progress has stalled`; `after 5 rounds`; `fix round 4/5` | DELETE | |
| 189-191 (loop, 3 phrases) | the re-review prompt drops: <gone> | sdd references/re-review-prompt.md | absent: `### Progress`; `**Progress:**`; `a progress reading` | DELETE | |
| 192 | the breaker item follows the second round | sdd references/ruling-prompt.md | 'breaker: findings still open after the second fix round.' | DELETE | |
| 193 | the breaker item no longer waits five rounds | sdd references/ruling-prompt.md | 'fifth fix round' | DELETE | |
| 195 | executor: round 1 resumes the session | reference/executor-lane.md | "Fix round 1 resumes that executor's own session" | DELETE | |
| 196 | executor: round 2 hands back | reference/executor-lane.md | '**Round 2 is HANDBACK.**' | DELETE | |
| 197 | executor: the failed-resume example is round 1 of 2 | reference/executor-lane.md | 'Task <N>: fix round 1/2 (0 addressed, 2 open - executor quota exhaust... | DELETE | |
| 198-200 (loop, 7 phrases) | executor-lane drops: <gone> | reference/executor-lane.md | absent: `Round 4 is`; `Fix rounds 1 to 3`; `five-round cap`; `stalled at round 3`; `rounds 4 and 5`; `two in a row`; `§Rounds 1-3` | DELETE | |
| 201 | ladder: the lane resumes once, then hands back | reference/ladder.md | 'resumes the same session on round 1 and hands back on round 2' | DELETE | |
| 202 | ladder: no fourth round on the lane | reference/ladder.md | 'heading for at round 4' | DELETE | |
| 204 | subagent mode: the fix-round grammar | sdd references/ledger.md | 'Task <N>: fix round R/2 (X addressed, Y open — <one-liners>; commits ... | DELETE | |
| 205 | subagent mode: the group round grammar | sdd references/ledger.md | ': review round R/2 (' | DELETE | |
| 206 | subagent mode: a group's round 1 resumes at round 2 | sdd references/ledger.md | "\| \review round 1/2\ on a \Group\ line, or \review round 1/5\ from a... | DELETE | |
| 207 | subagent mode: a group's round 2 goes to the breaker | sdd references/ledger.md | '\| review round 2/2 on a Group line, or review round R/5 with R >= 2 ... | DELETE | |
| 208 | subagent mode: the wave round grammar | sdd references/ledger.md | 'Wave <k>: fix round R/2 (<same fields as a fix round>)' | DELETE | |
| 209 | subagent mode: older ledgers map R/5 | sdd references/ledger.md | 'A Task, Group or Wave round line written before the two-round cap rea... | DELETE | |
| 210 | subagent mode: a Codex R/5 line is live | sdd references/ledger.md | 'On a Host: codex plan a Task or Wave round line reading R/5 is live, ... | DELETE | |
| 211 | subagent mode: compaction resumes round 1 at round 2 | skills/subagent-driven-development/SKILL.md | 'fix round 1/2 resumes at round 2 with a fresh dispatch' | DELETE | |
| 212 | subagent mode: the breaker row | sdd references/ruling-seat.md | '\| breaker \| Every finding still open after round 2/2 \|' | DELETE | |
| 213 | subagent mode: the flowchart caps at 2 | sdd references/process-graph.md | '"R = 2?"' | DELETE | |
| 214 | subagent mode: the example round has no progress field | sdd references/example-workflow.md | '[Ledger: Task 2: fix round 1/2 (2 addressed, 0 open; commits d4e5f6a.... | DELETE | |
| 215-217 (loop, 6 phrases) | subagent mode drops: <gone> | sdd skill + references (all, via sdd_text) | absent: `progress p -> q`; `stalled progress`; `round 1 of 5`; `Fix round R of 5`; `Progress: 18`; `"R = 5?"` | DELETE | |
| 218 | subagent mode names R/5 only for older runs | sdd SKILL.md | "$SDD" | DELETE | |
| 219 | the ledger names R/5 only for older runs | sdd references/ledger.md | "$SDD_LEDGER" | DELETE | |
| 220 | inline mode: delegated fix rounds stop at 2 | skills/executing-plans (SKILL+references view) | 'fix rounds up to 2 and' | DELETE | |
| 221 | inline mode: the breaker row | skills/executing-plans (SKILL+references view) | "\| \breaker\ \| A task's findings or verifications still open at its ... | DELETE | |
| 222 | inline mode names R/5 only for older runs | skills/executing-plans (view) | "$INLINE" | DELETE | |
| 228 | waves ask check-due which check closes a wave | reference/parallel-waves.md | 'bash <plugin-root>/scripts/wave check-due PLAN_FILE <k>' | DELETE | |
| 229 | every wave closes | reference/parallel-waves.md | 'Every wave closes with an integrated or a merged line, one-task and s... | DELETE | |
| 230 | the merged line | reference/parallel-waves.md | 'Wave <k>: merged (head <sha7>; check at wave <m>)' | DELETE | |
| 231 | the integrated line may be baseline-only | reference/parallel-waves.md | 'Wave <k>: integrated (head <sha7>; <command> → pass[; baseline failur... | DELETE | |
| 232 | a wave opens once every earlier wave is closed | reference/parallel-waves.md | 'every earlier wave closed by its integrated or merged line' | DELETE | |
| 233 | an ancestor with no task commits between proves the base | reference/parallel-waves.md | 'or an ancestor of HEAD with no task commits between' | DELETE | |
| 234 | a task commit outside any wave forces the fallback proof | reference/parallel-waves.md | 'Only a task commit outside any wave forces the fallback proof' | DELETE | |
| 235 | the base proof records its failures | reference/parallel-waves.md | '<workspace>/base-proof-failures.txt' | DELETE | |
| 236 | a new failure hands over every diff since the last pass | reference/parallel-waves.md | 'every task diff since the last passing check' | DELETE | |
| 237 | no in-flight run is exempt | reference/parallel-waves.md | 'None is exempt.' | DELETE | |
| 238 | an earlier cadence ruling is superseded | reference/parallel-waves.md | 'is superseded by this cadence and the red-baseline rule' | DELETE | |
| 239 | an overlap round counts toward two rounds | reference/parallel-waves.md | 'It counts toward the two rounds.' | DELETE | |
| 240 | recovery: a wave in flight has no closing line | reference/parallel-waves.md | 'A Wave <k>: started line with no later Wave <k>: integrated or Wave <... | DELETE | |
| 241 | a one-task wave is no longer line-free | reference/parallel-waves.md | 'with no Wave lines, no worktree and no merge' | DELETE | |
| 242 | waves no longer count five rounds | reference/parallel-waves.md | 'It counts toward the five' | DELETE | |
| 243 | waves name R/5 only for older runs | reference/parallel-waves.md | "$PW" | DELETE | |
| 244 | writing-plans: the optional Wave check header line | skills/writing-plans/SKILL.md | '**Wave check:** [waves only, optional:' | DELETE | |
| 245 | writing-plans: the waves rule names the Wave check | skills/writing-plans/SKILL.md | '**Wave check:**, optional, names a faster command' | DELETE | |
| 247 | writing-plans: the header template has a Task check line | skills/writing-plans/SKILL.md | '**Task check:** [<fast command> — <why>, or none — full suite every 3... | DELETE | |
| 248 | writing-plans: the Integration check line holds the full suite on every plan | skills/writing-plans/SKILL.md | '**Integration check:** [<command>: the full suite, on every plan]' | DELETE | |
| 249 | writing-plans: the Integration check line is no longer waves only | skills/writing-plans/SKILL.md | '**Integration check:** [waves only' | DELETE | |
| 251 | task check: the first source that applies wins | writing-plans references/task-check-line.md | 'Choose the first that applies' | DELETE | |
| 252 | task check: a gate with Tier: task comes first | writing-plans references/task-check-line.md | 'a gate in <docs>/gates.md with Tier: task' | DELETE | |
| 253 | task check: a fast full suite is its own task check | writing-plans references/task-check-line.md | 'the full suite itself, when its last passing run in suites.tsv took 3... | DELETE | |
| 254 | task check: impact selection comes from test-tiers.md | writing-plans references/task-check-line.md | 'an impact-selection command for the runner the project uses, from [te... | DELETE | |
| 255 | task check: none is the last resort | writing-plans references/task-check-line.md | 'none — full suite every 3 tasks, when none of those applies' | DELETE | |
| 256 | task check: a missing or six-column row is not fast | writing-plans references/task-check-line.md | 'A row that is missing, or has six columns and so no duration, counts ... | DELETE | |
| 257 | task check: only the checkout's own rows are read | writing-plans references/task-check-line.md | 'Read only rows of the checkout you run in' | DELETE | |
| 258 | task check: the row is found by suite-run's quoted key | writing-plans references/task-check-line.md | 'the quoted key suite-run records for bash -c <cmd> run from the top l... | DELETE | |
| 259 | task check: the duration is column 7 | writing-plans references/task-check-line.md | 'read its column 7, the duration in' | DELETE | |
| 260 | task check: the line ends with its reason | writing-plans references/task-check-line.md | 'End the line with — <why>' | DELETE | |
| 261 | integration check: on every plan, not only a waves plan | writing-plans references/task-check-line.md | '**Integration check:** holds the full suite command on every plan, no... | DELETE | |
| 263 | test-tiers: the Task check tier | reference/test-tiers.md | '\| Task check \|' | DELETE | |
| 264 | test-tiers: the Full suite tier | reference/test-tiers.md | '\| Full suite \|' | DELETE | |
| 265 | test-tiers: the Sweep tier | reference/test-tiers.md | '\| Sweep \|' | DELETE | |
| 266 | test-tiers: the impact-selection heading | reference/test-tiers.md | '## Impact selection' | DELETE | |
| 267 | test-tiers: the impact-selection table | reference/test-tiers.md | '\| pytest-testmon \|' | DELETE | |
| 268 | subagent mode: the merged grammar | sdd references/ledger.md | 'Wave <k>: merged (head <sha7>; check at wave <m>)' | DELETE | |
| 269 | subagent mode: the integrated grammar | sdd references/ledger.md | 'Wave <k>: integrated (head <sha7>; <command> → pass[; baseline failur... | DELETE | |
| 270 | subagent mode: compaction reads a merged line as closed | skills/subagent-driven-development/SKILL.md | 'A Wave <k>: started line with no later integrated or merged line' | DELETE | |
| 271 | subagent mode: recovery reads merged as closed | sdd references/ledger.md | 'Wave <k>: merged closes the wave as integrated does' | DELETE | |
| 272 | subagent mode: a one-task wave proves its base and closes by §5 | skills/subagent-driven-development/SKILL.md | 'A wave of one task runs in the checkout, proves its base first and cl... | DELETE | |
| 273 | subagent mode: the old integrated grammar is gone | sdd references/ledger.md | 'Wave <k>: integrated (head <sha7>; <command> → pass)' | DELETE | |
| 278 | the loop steps run task-step verdict | reference/delegated-task.md (loop steps) | "$([ "$(loop_steps \| grep -cF -- 'task-step verdict PLAN_FILE N')" -g... | DELETE | |
| 279 | the re-review is read through verdict --rereview | reference/delegated-task.md | 'bash <plugin-root>/scripts/task-step verdict PLAN_FILE N --rereview <... | DELETE | |
| 280 | verdict writes the fix file's bullets | reference/delegated-task.md | 'task-step verdict writes its bullets from the report' | DELETE | |
| 281 | the seat's report is never read | reference/delegated-task.md | 'Never Read the report file yourself' | DELETE | |
| 282 | a failed verdict restores the tracked files | reference/delegated-task.md | 'git -C <dir> checkout -- <files>' | DELETE | |
| 283 | a failed verdict is a Ruling line | reference/delegated-task.md | 'restored the committed state and re-dispatched once' | DELETE | |
| 284 | a second failure takes the fallback judge | reference/delegated-task.md | 'A second failure dispatches the route'"'"'s fallback judge' | DELETE | |
| 285 | the risk-3 check reads the report's last section | reference/delegated-task.md | 'A report whose ## Codex findings section is not its last' | DELETE | |
| 286 | the risk-3 check no longer reads the reply | reference/delegated-task.md | 'A reply whose ### Codex findings' | DELETE | |
| 287-292 (loop over 2 files, 3 checks each = 6) | <file>: an AMEND applies from the report / is no longer copied by hand / ruling report read by its Verdict section | sdd references/ruling-seat.md; skills/executing-plans (view) | `scripts/plan-amend PLAN_FILE --report ... --id A<k>`; absent `copy the entry, from its ## A? line`; `read only its ## Verdict section` | DELETE | |
| 293 | the example workflow reads the verdict with task-step | sdd references/example-workflow.md | '[task-step verdict PLAN_FILE 1:' | DELETE | |
| 294 | a header amendment's confirmation reads the first report | sdd references/ruling-seat.md | 'then the path of the first seat'"'"'s report' | DELETE | |
| 295 | by hand: the review prompt's two report placeholders | reference/delegated-task.md | '[IMPLEMENTER_REPORT_FILE] set to the implementer'"'"'s report and [RE... | DELETE | |
| 296 | the lane's review prompt no longer names a Verification Scores section | reference/executor-lane.md | 'rather than a markdown report file' | DELETE | |
| 297 | a group review is read through verdict --group | reference/delegated-task.md | 'bash <plugin-root>/scripts/task-step verdict PLAN_FILE N M … --group' | DELETE | |
| 298 | Codex seats apply the cannot-verify route | reference/delegated-task.md | 'the bands, the cannot-verify route and the fix loop' | DELETE | |
| 299 | a group applies the cannot-verify route | reference/delegated-task.md | 'cannot-verify route and plan-conflict route' | DELETE | |
| 300 | no ⚠️ route is left in delegated-task.md | reference/delegated-task.md | '⚠️ route' | DELETE | |

KEEP rows in this file (not pins):

| line(s) | test label | target | verdict | note |
|---|---|---|---|---|
| 84-85 | the prompt shows both Verified bullet forms; each Verified bullet form matches the stop gate's grammar | implementer-prompt.md example bullets, run against the grammar `scripts/impl-stop-gate` enforces (line 7-8, 120-123) | KEEP(scripts/impl-stop-gate) | extracts the example bullets and validates them against the script's grammar |
| 106-108 (loop, 4 phrases) | the group template carries <placeholder> | group-reviewer-prompt.md: `[GROUP_LIST]`, `[PACKAGE_FILE]`, `[REPORT_FILE]`, `[PLUGIN_ROOT]` | KEEP(scripts/task-step `do_group`, fill at line ~1071) | placeholders the script fills |
| 109 | the group template is a fenced prompt task-step can fill | group-reviewer-prompt.md: `  prompt: |` | KEEP(scripts/task-step `prompt_text`) | anchor the script's awk looks for |
| 117-118 | the group prompt holds no placeholder task-step does not fill | group-reviewer-prompt.md prompt body: placeholders other than the four | KEEP(scripts/task-step, dies on an unexpanded token) | |

Whole-file view: after deleting, the file keeps 84-85, 105-109, 117-118 and the structural 250 and 262 (existence only). Either keep it as a 11-assertion file, or move those into `task-step.test.sh` and delete this file. The helpers `lacks`, `names_flat`, `lacks_flat`, `flat`, `only_older`, `loop_steps`, the `. skill-view.sh` and `. fixtures/sdd-text.sh` sourcing, `SKILL_VIEW_DIR`/`trap`, `INLINE`, and every path variable except `GRP` and `IP` become unused and delete with the pins. Header comment lines 2-5 ("each is pinned by the text that carries it") no longer holds and needs rewriting.

### task-step.test.sh (0 DELETE)

All assertions run `task-step` and check its stdout, stderr, exit code, state files, generated dispatch/prompt/package files, or ledger. The assertions that read generated prompt text (176-182, 312-319, 342-347, 371-378, 479-481, 973-989, 1142) check what the script filled or dropped (`fill`, `drop_sections`, `prompt_text`), so they are behaviour. KEEP.

### typed-seats-and-drafting.acceptance.sh (17 DELETE)

| line(s) | test label | markdown file and phrase pinned | verdict | note |
|---|---|---|---|---|
| 63 | A5: requesting-code-review dispatches dforge:judge-opus | skills/requesting-code-review/SKILL.md: `Dispatch dforge:judge-opus` | DELETE | |
| 64 | A5: code-reviewer.md names dforge:judge-opus as the seat | requesting-code-review/references/code-reviewer.md: `Subagent (dforge:judge-opus):` | DELETE | |
| 65 | A5: requesting-code-review names no general-purpose seat | requesting-code-review SKILL.md: absent `general-purpose` | DELETE | |
| 66 | A5: code-reviewer.md names no general-purpose seat | code-reviewer.md: absent `general-purpose` | DELETE | |
| 67 | A5: requesting-code-review requires the diff file | requesting-code-review SKILL.md: `[DIFF_FILE] - REQUIRED` | DELETE | |
| 68 | A5: requesting-code-review writes the diff file with git diff for BASE..HEAD | requesting-code-review SKILL.md: `git diff -U10 "$BASE_SHA..$HEAD_SHA"` | DELETE | |
| 70 | A5: code-reviewer.md requires the diff file | code-reviewer.md: `[DIFF_FILE] (-\|em dash) REQUIRED` | DELETE | comment at 69 goes too |
| 71 | A5: code-reviewer.md offers no none option for the diff file | code-reviewer.md: absent `none` | DELETE | |
| 72 | A5: code-reviewer.md has no git fallback for the diff | code-reviewer.md: absent `git diff [BASE_SHA]\|derive it yourself` | DELETE | |
| 127 | A6: using-dforge has a Seats section | skills/using-dforge/SKILL.md `## Seats`: non-empty | DELETE | session-start.sh cats the file whole, it does not read this section |
| 128 | A6: typed seats only - a dforge: agent or a typed built-in | using-dforge SKILL.md `## Seats`: `names a seat: a dforge: agent or a typed built-in` | DELETE | |
| 129 | A6: general-purpose takes an explicit model | using-dforge `## Seats`: `general-purpose takes an explicit model` | DELETE | |
| 132 / 134 | A6: forks are not allowed / forks only for drafting (one branch runs, chosen by the note's Decision) | using-dforge `## Seats`: `No forks` or `[Ff]orks?.*draft` | DELETE | counted as one executed assertion |
| 136 | A6: read-only checks (register rows) go to a judge seat | using-dforge `## Seats`: `Read-only checks (register rows...) go to dforge:judge-sonnet-high` | DELETE | |
| 137 | A6: judge-opus for checks across several files | using-dforge `## Seats`: `dforge:judge-opus across several files` | DELETE | whole `if sel A6` block (124-138) deletes, incl. `decision=` at 130 |
| 179 | A14: writing-plans has the session draft every task, on any host | skills/writing-plans/SKILL.md `## Drafting the tasks`: `Draft every task in the session, at any plan size.` | DELETE | |
| 180 | A14: no Codex reference dispatches a drafting seat | reference/*codex*, .codex-plugin: absent `drafter\|drafting seat` | DELETE | whole `if sel A14` block (176-181) deletes |

Whole-block / helpers: `if sel A6` (124-138) and `if sel A14` (176-181) delete whole. In A5, lines 61-72 (`rcr`, `cr` flatten and the nine pins) delete; lines 74-121 stay (they copy the tree and run `tests/seats.test.sh` on fixtures: behaviour of a script). Then `section()` (35-37), `absent()` (26-29), `fm()` (38-44, already unused today) and the variables `RCR`, `CR`, `UD`, `WP` (54-57) are unused. `matches()` stays (A12, A13). Header comment lines 3-5 need updating.

### typed-seats-and-drafting.acceptance.test.ts (0 DELETE)

Imports `FORK_DRAFTING` and `seatDenial` from `hooks/cockpit/lib` and drives the engine; no markdown is read. KEEP.

## 3. EXCLUDED borderline cases

- clean-session-phases.acceptance.test.sh 177-178 (A11 every SKILL.md at most 20000 bytes; skills found): size limit, structural.
- clean-session-phases.acceptance.test.sh 179-180 (A11 runs `skill-size.test.sh`): another suite's exit code, structural.
- clean-session-phases.acceptance.test.sh 120-123 (usage text of `scripts/auto-run`): script output.
- task-loop-steps.acceptance.test.sh 687-690 (A15 runs `tests/seats.test.sh` and checks exit 0, no FAIL line, `0 failed`): subprocess of a lint script, not a pin; redundant with the CI run of seats.test.sh, judge may drop it.
- task-loop-steps.acceptance.test.sh 205, 211-212, 228, 234: `Second Pass` and `Lens` presence in generated prompts; `task-step` line 898 drops/keeps that section: script output.
- task-step-text.test.sh 105 (group template file exists), 250 (task-check-line.md exists, `-s`), 262 (test-tiers.md carries `# Test tiers`, used as an existence check): file existence, structural. Judge may delete 262 as a heading pin; no script reads test-tiers.md.
- task-step-text.test.sh 83 (extraction of Verified bullets): setup for 84-85, not an assertion.
- typed-seats-and-drafting.acceptance.sh 82, 96, 104, 121 (run `tests/seats.test.sh` against copies and fixtures): behaviour of a script on fixtures the test writes.
- typed-seats-and-drafting.acceptance.sh 150-157 (A12) and 173 (A13): assertions on the historical note `docs/dforge/notes/2026-10-25-drafter-measurement.md` (figures arithmetic, `a tie goes to the typed drafter`, `trimmed to its header and Task index rows 1-6`). Not in the named markdown set and not a skill, but no script reads the note. Not counted; if the judge wants them gone it is 8 more assertions (150, 151, 152, 153, 154, 155, 156, 157) plus 173 and the `row()` helper, which would leave A12 with only 160-161.
- typed-seats-and-drafting.acceptance.sh 160-161 (A12 `FORK_DRAFTING` is false): reads `hooks/cockpit/lib.ts`, code, KEEP.
- typed-seats-and-drafting.acceptance.sh 166-172 (A13): git state hygiene, structural.
- typed-seats-and-drafting.acceptance.sh 130 (decision read from the note): input to the A6 branch, goes with A6.
- task-step.test.sh 344-346 (Codex prompt asks for one JSON object, carries `#### Spec Compliance {#spec}`, drops report sections): `task-step` builds the Codex prompt from `criteria/task-review.md` and the heading is consumed by it; script output.
- task-step-settle.test.sh 30-31: counted as DELETE but borderline, because `task-step verdict` parses the grammar the template teaches.

## 4. Zero-assertion check, counters and plans

All files use dynamic `pass`/`fail` counters printed by a final `printf '\n%d passed, %d failed\n'`; none has a literal expected total, a `1..N` plan, or a plan-count to edit. No test registry lists assertion counts. Only these structural lines change:

| file | deleting leaves zero assertions? | counters / lists to update |
|---|---|---|
| clean-session-phases.acceptance.test.sh | no (about 100 remain) | none; summary line 282 is dynamic |
| task-loop-steps.acceptance.test.sh | no | `ALL="a1 ... a11 a14 a15"` at line 693 (drop `a14`, and `a15` if its remaining subprocess lines 686-690 are dropped); header comment lines 3-4 |
| task-step-base.test.sh | no | none; summary line 640 is dynamic |
| task-step-settle.test.sh | no | none; summary dynamic |
| task-step-suite.test.sh | no | none; summary line 334 is dynamic |
| task-step-text.test.sh | no, 11 assertions remain (84, 85, 105, 106-108 x4, 109, 117, 250, 262) | none; summary line 301 is dynamic; header comment 2-5 stale |
| typed-seats-and-drafting.acceptance.sh | no | header comment lines 3-5 (statement list A5, A6, A12, A13, A14); selector blocks `sel A6` and `sel A14` go; `sel A5` keeps 4 assertions |

## 5. Adjacent findings

- typed-seats-and-drafting.acceptance.sh `fm()` (lines 38-44) is defined and never called.
- task-step-text.test.sh line 5 header says each call "is pinned by the text that carries it"; that is the rule the volume spec rejects.
- Other test files not in this scope also source `skill-view.sh` and `fixtures/sdd-text.sh` (auto-run-skills, project-status, review-depth*, ui-ux-skill, process-roles, gates-manifest, sdd-references, inline-only, inline-mode, final-phase, review-route, waiting-text) and are probably full of the same pins.



---

# PART g3

# Wording-pin audit, group g3 (7 test files under plugins/dforge/tests)

All paths below are relative to /root/repositories/darkraise-ai-plugins/plugins/dforge/tests unless stated. Counts are executed assertions (a loop iteration counts as one). Line numbers are from the files as they stand now.

Consumer survey (done before classifying). Scripts, hooks and config that read markdown TEXT (not just cite a path in a message):
- scripts/task-step renders skills/subagent-driven-development/references/{task-reviewer-prompt,group-reviewer-prompt,re-review-prompt,implementer-prompt}.md (substitutes placeholders such as [REPORT_FILE]; refuses an unfilled one) and reads criteria/task-review.md. Its verdict parser (task-step ~1141-1200) requires a judge report to open with `## Verdict` and findings to match `- [Sev] (Task N)? file:line — text`.
- scripts/lib/plan.sh `ladder_block` reads the FENCED blocks of reference/ladder.md (assignment, escalation, reserve, gate, codex-*, agy-*). Prose outside the fences is not read.
- scripts/lens-route and review-record read criteria/lenses/*.md (the `Applies:` line); run-codex-review.sh reads criteria/codex-final-review.md; session-start.sh injects skills/using-dforge/SKILL.md whole; task-step checks agents/impl-*.md exist.
- reference/parallel-waves.md, delegated-task.md, executor-lane.md, native-codex.md, auto-run.md, session-budget.md, final-review.md, README.md, every other SKILL.md and references/*.md: scripts/hooks only CITE them by path in comments or error messages. No script reads their sentences.
- The ledger/handoff/register line grammars are parsed by scripts (review-record, next-step, task-step, cockpit lib.ts, register, roadmap) from the LEDGER/REGISTER FILES, not from the documentation of the grammar. A test that pins the documentation sentence is a pin even though the grammar itself is consumed.

## 1. Totals

| File | DELETE | KEEP markdown-text assertions (consumer) | Notes |
|---|---|---|---|
| faster-plans.acceptance.test.sh | 111 | 9 (task-step templates, 6 of them borderline) + 3 structural (`tools:` frontmatter) + 1 JSON | a1, a14, a15, a16 become empty |
| next-step.test.sh | 0 | 0 | every assertion is script output or a fixture fed to scripts |
| project-status.test.sh | 122 | 3 structural (file exists: lines 26, 49, 108) | whole file reduces to 3 existence checks |
| retained-review-data.acceptance.test.sh | 0 | 0 | script output; the lens-file edits (108, 395-408) are fixtures for review-record |
| review-depth-qa.acceptance.test.sh | 70 | 0 | a9, a11, a14, a15 become empty |
| review-depth.acceptance.test.sh | 67 | 0 | a9, a11, a14, a15 become empty |
| review-route.test.sh | 167 | 2 structural (version manifests 824-825) | |
| TOTAL | 537 | | 5 files affected (next-step and retained-review-data untouched) |

DELETE counts exclude the borderline EXCLUDED items in section 3.

## 2. Per-file tables

### 2.1 faster-plans.acceptance.test.sh (111 DELETE)

| Line(s) | Label (abbreviated) | Markdown pinned | Verdict | Note |
|---|---|---|---|---|
| 283 | A1 writing-plans says a task carries its interfaces | skills/writing-plans/SKILL.md (+references) | DELETE | whole a1() deletable |
| 284 | A1 complete code of its tests | same | DELETE | |
| 285 | A1 commands that verify it | same | DELETE | |
| 286 | A1 implementation code only for a configuration value | same | DELETE | |
| 287 | A1 generated-file or migration command | same | DELETE | |
| 288 | A1 fixed constant the spec names | same | DELETE | |
| 289 | A1 Step 3 carries no implementation code | same | DELETE | |
| 291 | A1 plan-reviewer prompt expects interfaces, test code, verify commands | skills/writing-plans/references/plan-reviewer-prompt.md | DELETE | no script reads it |
| 292 | A1 missing or stub test is a finding | same | DELETE | |
| 293 | A1 reviewer sent to criteria/plan-review.md | same | DELETE | |
| 294 | A1 plan-review criteria require interfaces + test code | criteria/plan-review.md | DELETE | no script reads criteria/plan-review.md |
| 295 | A1 criteria limit implementation code to three cases | criteria/plan-review.md | DELETE | |
| 514 | A7 recovery table: awaiting group review | skills/subagent-driven-development/references/ledger.md | DELETE | next-step behaviour is asserted at 503-509 (KEEP) |
| 515 | A7 delegated-task recovery table says the same | reference/delegated-task.md | DELETE | |
| 524 | A8 held tasks accumulate in sequential mode | reference/delegated-task.md | DELETE | |
| 525 | A8 group review runs when 4 held | same | DELETE | |
| 526 | A8 before a review=task dispatch | same | DELETE | |
| 527 | A8 after the plan's last task | same | DELETE | |
| 528 | A8 no new task until group clean | same | DELETE | |
| 529 | A8 fixes inside a group run one task at a time | same | DELETE | |
| 530 | A8 each member gets its own complete line | same | DELETE | |
| 531 | A8 skill flow reviews group at 4 held | skills/subagent-driven-development/references/process-graph.md | DELETE | |
| 622 | A9 parallel-waves dispatches group once every grouped task held | reference/parallel-waves.md | DELETE | |
| 644 | A10 ledger grammar attributes each finding clause to its task | skills/subagent-driven-development/references/ledger.md | DELETE | cockpit parseLedger is tested by cockpit_rounds (669-683, KEEP) |
| 645 | A10 parallel-waves shows the same attributed line | reference/parallel-waves.md | DELETE | |
| 646 | A10 delegated-task: one range per fixed member | reference/delegated-task.md | DELETE | |
| 714 | A11 round 2 is a fresh dispatch on successor rung | skills/subagent-driven-development/references/escalation.md | DELETE | |
| 715 | A11 same rung when successor is SPLIT | escalation.md | DELETE | |
| 716 | A11 split reached only through breaker's AMEND | escalation.md | DELETE | |
| 717 | A11 executor round 2 leaves lane by HANDBACK | escalation.md | DELETE | |
| 718 | A11 executor-lane.md hands round 2 back | reference/executor-lane.md (`HANDBACK`) | DELETE | lane-breaker/review-route read HANDBACK from the LEDGER, not this doc |
| 719 | A11 finding open after round 2 goes to breaker | reference/delegated-task.md | DELETE | |
| 720 | A11 ledger fix-round line is R/2 | ledger.md | DELETE | |
| 721 | A11 re-review prompt carries no Progress section (absent) | re-review-prompt.md | DELETE | task-step renders this file but only fills placeholders; the absence of a section is not consumed |
| 722 | A11 no `progress ... ->` in fix-round grammar (absent) | ledger.md | DELETE | |
| 776 | A12 skill maps R/5 on Task/Group/Wave line | ledger.md | DELETE | |
| 777 | A12 Task recovery table resumes 1/5 at round 2 | delegated-task.md | DELETE | |
| 778 | A12 R/5 with R>=2 to breaker | delegated-task.md | DELETE | |
| 779 | A12 Group recovery row 1/5 to round 2 | ledger.md | DELETE | |
| 780 | A12 review round R/5 R>=2 to breaker | ledger.md | DELETE | |
| 781 | A12 Wave R/5 rule | parallel-waves.md | DELETE | |
| 847 | A14 wave of one task closes like any wave | parallel-waves.md | DELETE | whole a14() 843-856 deletable |
| 848 | A14 every wave closes with integrated or merged | parallel-waves.md | DELETE | |
| 849 | A14 grammar has the merged line | parallel-waves.md | DELETE | |
| 850 | A14 merged closes a wave as integrated does | parallel-waves.md | DELETE | |
| 851 | A14 skill ledger grammar has merged line | ledger.md | DELETE | |
| 852 | A14 merged line whose head is HEAD proves base | parallel-waves.md | DELETE | |
| 853 | A14 then nothing reruns | parallel-waves.md | DELETE | |
| 854 | A14 wave of one runs base proof only | parallel-waves.md | DELETE | |
| 855 | A14 next wave starts on a closing line | parallel-waves.md | DELETE | |
| 863 | A15 base proof writes base-proof-failures.txt | parallel-waves.md | DELETE | whole a15() 860-872 deletable |
| 864 | A15 failing lines all in file counts as passing | parallel-waves.md | DELETE | |
| 865 | A15 integrated with baseline failures only | parallel-waves.md | DELETE | |
| 866 | A15 subset test | parallel-waves.md | DELETE | |
| 867 | A15 new failure logs check failed | parallel-waves.md | DELETE | |
| 868 | A15 fix dispatch gets every task diff | parallel-waves.md | DELETE | |
| 869 | A15 diff via review-package | parallel-waves.md | DELETE | |
| 870 | A15 from first wave's base | parallel-waves.md | DELETE | |
| 871 | A15 ledger grammar baseline clause | ledger.md | DELETE | |
| 879 | A16 ancestor of HEAD proves base | parallel-waves.md | DELETE | whole a16() 876-886 deletable |
| 880 | A16 only bookkeeping commits between | parallel-waves.md | DELETE | |
| 881 | A16 bookkeeping definition | parallel-waves.md | DELETE | |
| 882 | A16 then nothing reruns | parallel-waves.md | DELETE | |
| 883 | A16 only a task commit forces fallback proof | parallel-waves.md | DELETE | |
| 884 | A16 fallback is Wave check else Integration check | parallel-waves.md | DELETE | |
| 885 | A16 no closing line yet: full check | parallel-waves.md | DELETE | |
| 909 | A17 next plan-review round only on Critical / score <=8 | skills/writing-plans/SKILL.md (+refs) | DELETE | review-route cap behaviour is KEEP at 891-903 |
| 910 | A17 Claude plan cap 2, no third | writing-plans | DELETE | |
| 911 | A17 Fable runs one round | reference/auto-run.md | DELETE | scripts cite auto-run.md by path only |
| 912 | A17 second only when round 1 leaves Blocker/High | auto-run.md | DELETE | |
| 913 | A17 checks only those answers | auto-run.md | DELETE | |
| 914 | A17 brainstorming caps spec review at two rounds | skills/brainstorming/SKILL.md (+refs) | DELETE | |
| 915 | A17 second round only for Blocker or High | brainstorming | DELETE | |
| 941 (x6) | A18 <template> names the report file | ruling-prompt, plan-reviewer-prompt, architecture-critic-prompt, code-reviewer, milestone-judge, distil-judge | DELETE | loop 929-947, 6 of 9 iterations; [REPORT_FILE] is filled by the controller, not a script |
| 942 (x6) | A18 <template> fixes the `## Verdict` section | same 6 | DELETE | no script parses those reports' `## Verdict` |
| 943 (x9) | A18 <template> limits final message to 10 lines | all 9 templates | DELETE | no script reads "at most 10 lines" |
| 945 (x3) | A18 <template> fixes finding-line grammar | plan-reviewer-prompt, architecture-critic-prompt, code-reviewer | DELETE | |
| 951 | A18 final-review.md names final review's report file | reference/final-review.md | DELETE | |
| 952 | A18 and dedupe's report file | same | DELETE | |
| 953 | A18 limits both to 10 lines | same | DELETE | |
| 957 | A18 acceptance-qa.md names a report file | reference/acceptance-qa.md | DELETE | |
| 958 | A18 acceptance-qa.md fixes ## Verdict | same | DELETE | |
| 959 | A18 acceptance-qa.md 10 lines | same | DELETE | |
| 1256 | A23 native-codex.md preserves five-round cap | reference/native-codex.md | DELETE | |
| 1257 | A23 delegated-task keeps five rounds on Host: codex | delegated-task.md | DELETE | |
| 1258 | A23 Codex ledger line is fix round R/5 | delegated-task.md | DELETE | |
| 1259 | A23 Codex recovery row | delegated-task.md | DELETE | |
| 1260 | A23 skill reads Codex R/5 as live | ledger.md | DELETE | |
| 1261 | A23 native-codex keeps Rule S at 4 | native-codex.md | DELETE | plan-lint reads reference/codex-routing.json, not this doc |
| 1262 | A23 ladder keeps Codex carve-out reducible >= 4 | reference/ladder.md PROSE (not a fenced block) | DELETE | ladder_block reads fences only |
| 1263 | A23 writing-plans keeps code-given tasks on Codex host | writing-plans SKILL.md | DELETE | |

DELETE tally: A1 12, A7 2, A8 8, A9 1, A10 3, A11 9, A12 6, A14 9, A15 9, A16 7, A17 7, A18 30 (24 in the 929-947 loop + 3 + 3), A23 8 = 111.

KEEP (markdown text, consumer named):
- 941 x3, task-reviewer-prompt / group-reviewer-prompt / re-review-prompt `[REPORT_FILE]` placeholder: KEEP(task-step, which substitutes it at lines ~338, 814, 901, 1072 and refuses a template with an unfilled placeholder at 487).
- 942 x3 and 945 x3, the same three templates, `## Verdict` and finding-line grammar: KEEP(task-step verdict parser, ~1141-1200) but BORDERLINE: the parser reads the judge's report, not the template; the template is the only thing that makes the judge emit that format.
- 924 x3 (`tools:` frontmatter of judge-opus/-sonnet-high/-fable lists Write): structural frontmatter, KEEP.
- 1250 `codex-routing.json` review_cap: JSON consumed by scripts, KEEP.

Helpers/blocks deletable whole:
- a1() lines 275-296 (header comment 275, function 277-296).
- a14() 841-856, a15() 858-872, a16() 874-886 (section headers + bodies).
- Locals that become unused: 511-513 (a7), 521-523 (a8), 620-621 (a9), 641-643 (a10), 710-713 (a11), 772-775 (a12), 905-908 (a17), 1251-1255 (a23), and in a18 the `doc` use at 943/950/959 plus `text=` at 950 and 956.
- doc() (74) and skill_doc() (75-77) have no remaining caller once all of the above go (grep confirmed every call site is in a DELETE range).
- a18 loop 929-947: after deletion only 3 templates (task-reviewer, group-reviewer, re-review) keep assertions at 941/942/945; restructure the loop to those 3 and drop 943 and the other 6 entries. Findings flag (`yes`) stays for all 3.

### 2.2 next-step.test.sh (0 DELETE)

Every assertion runs next-step/register/roadmap and checks stdout, stderr, exit code or a file the script wrote. The only markdown it touches are fixtures it writes itself (plans, ledgers, registers, handoff). No assertion reads a plugin markdown file (grep for skills/, reference/, criteria/, agents/, README, SKILL.md found none). Nothing to delete.

### 2.3 project-status.test.sh (122 DELETE)

No script reads any text of reference/project-state.md, skills/project-status/SKILL.md or the other skills/READMEs pinned here (consumer survey above). Only three assertions survive: lines 25-26, 48-49, 107-108 (file exists), all structural.

| Line(s) | Label (abbreviated) | Markdown pinned | Verdict | Note |
|---|---|---|---|---|
| 30-38 loop (x6) | project-state names <docs>/gates.md, plans/completed.md, distilled/{constraints,gotchas,reference,rejected}.md | reference/project-state.md | DELETE | 6 phrases |
| 42, 43, 44, 45 | precedence heading, CLAUDE.md first, yields to, every file optional | project-state.md | DELETE | |
| 55, 56, 57 | status calls repo-audit; forbids sdd-workspace; forbids next-step | skills/project-status/SKILL.md | DELETE | |
| 62 | status reads the ledger dir | project-status SKILL.md | DELETE | |
| 63-65 loop (x2) | recovery reads ledger dir | skills/subagent-driven-development/SKILL.md, skills/executing-plans/SKILL.md | DELETE | |
| 66 | finishing reads rulings from ledger dir | skills/finishing-a-development-branch/SKILL.md | DELETE | |
| 70, 71 | task-heading discriminator `plan_tasks`; rejects Execution header | project-status SKILL.md | DELETE | |
| 74, 75 | names completed index; gates rules 4 and 5 | project-status SKILL.md | DELETE | |
| 79-80 | status rules table runs 0 to 9 in order | project-status SKILL.md | DELETE | one assertion (80); `rules=` at 79 goes |
| 81, 82 | rule 0 reads last line per task; routes to resume-execution | project-status SKILL.md | DELETE | |
| 85-87 | output sections in order | project-status SKILL.md | DELETE | one assertion (87); `sections=` at 85-86 goes |
| 89 | links project-state | project-status SKILL.md | DELETE | |
| 95, 96, 97 | resume loads constraints, gotchas, yields to | skills/resume-execution/SKILL.md | DELETE | |
| 98, 99 | brainstorming loads constraints, rejected | skills/brainstorming/SKILL.md | DELETE | |
| 104, 105 | project-state allows owner-decision entry; names writing-plans as constraints reader | project-state.md | DELETE | |
| 109, 110, 111, 112 | the Codex lane is declared on / cites spec / Set by owner / waits for session gate | docs/superpowers/distilled/constraints.md (repo doc, outside plugin tree) | DELETE | no script reads these entries; the lane gate is codex-gate output |
| 118, 119, 121, 122, 124, 125, 126 | registers dir, not only completion signal, either docs prefix, register can veto done, Open items, awaiting your check, seven sections | project-status SKILL.md | DELETE | 7 |
| 127 | state: registers listed | project-state.md | DELETE | |
| 134 | state: roadmap listed | project-state.md | DELETE | 134-151 is 18 assertions in all, one per line |
| 135, 136, 137, 138 | status reads roadmap / closed means done / routes to closing / verify-only rows | project-status SKILL.md | DELETE | |
| 139, 140, 141, 142, 143 | closing: sign-off, roadmap close M<n>, fresh judge, never done without closed, GAP reopens | skills/closing-a-milestone/SKILL.md | DELETE | |
| 144 | closing: judge brief `Verdict: CLOSE | KEEP OPEN` | skills/closing-a-milestone/references/milestone-judge.md | DELETE | scripts/roadmap close takes --note only, never reads a verdict |
| 145, 146 | planning: epic row; roadmap check | skills/planning-a-product/SKILL.md | DELETE | |
| 147 | planning: template has Foundations | planning-a-product/references/roadmap.md | DELETE | no script copies the template |
| 148, 149 | brainstorming routes new product; epic opens register | brainstorming SKILL.md | DELETE | |
| 150 | writing-plans no Program line for an epic | writing-plans SKILL.md | DELETE | |
| 151 | finishing settles the epic | finishing SKILL.md | DELETE | |
| 152-156 | old single-source rule is gone (absent) | project-status SKILL.md | DELETE | 1 assertion |
| 164-167 | closing: suite audit step 8 sits between 7 and 9 | closing-a-milestone SKILL.md | DELETE | 1 assertion (166); `step_line`, `s7 s8 s9` go |
| 168-182 | closing: 15 `says` (suites.tsv, names checkout, six-column, fewer than two rows, 20% growth, budget, gate, 20% only, test-simplifier scope, recommends only, suite-run key, two report lines, 20% arithmetic, merge rows) | closing-a-milestone SKILL.md | DELETE | 15 assertions; suite-run/suites.tsv behaviour is covered elsewhere |
| 183-187 | finishing execute-choice: suite-run bash -c, Integration check, runs with or without gates, one row per merge head, audit reads rows | skills/finishing-a-development-branch/references/execute-choice.md | DELETE | 5; `says` (160-163) and `FINREF` (159) go |
| 191, 193, 195, 196, 197, 198 | finishing register gate / line / register set / register add / either prefix / verify | finishing SKILL.md | DELETE | 6 (loop-free, multi-line needles) |
| 204, 206, 208 | brainstorming trigger two or more items; register before spec; register open | brainstorming SKILL.md | DELETE | |
| 210, 212 | writing-plans rows assigned; design-time deferral | skills/writing-plans/references/register-rows.md | DELETE | |
| 211 | writing-plans tasks cite rows | writing-plans SKILL.md | DELETE | |
| 216-219 loop (x2) | execution: rows go to doing | skill_view executing-plans, SDD references/setup.md | DELETE | |
| 220, 221-222 | README: register documented; states documented | README.md | DELETE | 2 (scripts/register owns the states) |
| 225, 227, 229 | status unresolved row outranks; Open items omitted when empty; finishing Program spec | project-status SKILL.md / finishing SKILL.md | DELETE | |
| 230-233 loop (x2) | execution: resolved row never set back to doing | executing-plans, SDD setup.md | DELETE | |
| 235, 237, 239 | finishing ignore every row; brainstorming Covers line x2 | finishing / brainstorming SKILL.md | DELETE | |
| 244-250 | project-state darkmem sync points section, stop points push, hooks reconcile, memory_add, mapping, notes file, commit note | project-state.md | DELETE | 7; darkmem-sync is tested as script behaviour elsewhere |
| 251-255 loop (x2 files, 2 assertions each) | pushes after each ledger line; push instruction | SDD references/ledger.md, executing-plans SKILL.md | DELETE | 4 |
| 256-260 | handoff: push line before Codex-only paragraph | skills/handoff/SKILL.md | DELETE | 1 assertion (259); `push_line`, `codex_line` go |
| 261-262 | codex-tools names the push | skills/using-dforge/references/codex-tools.md | DELETE | |

Tally by per-line count: 6 (loop 30-38) + 4 + 3 + 1 + 2 + 1 + 2 + 2 + 1 (80) + 2 + 1 (87) + 1 + 5 + 2 + 4 + 8 + 18 + 1 + 1 (166) + 20 (168-187) + 6 + 6 + 4 + 8 + 7 + 4 + 1 (259) + 1 (261) = 122.

Block/helper notes: after deletion the file keeps only 25-26, 48-49, 107-108. `skill-view.sh` (12), `fixtures/sdd-text.sh` (14), `present()` (21-24), `says()`, `SKILL_VIEW_DIR` (10-11) and every variable assignment become dead. Consider deleting the whole file and moving the 3 existence checks to the structural validator (scripts/validate-repository.mjs) if it does not already check them.

### 2.4 retained-review-data.acceptance.test.sh (0 DELETE)

All assertions run `scripts/review-record ratio|retain` and check stdout/exit code/files. The lens-file edits at 108 and 395-408 are fixtures: review-record reads `Applies:` from criteria/lenses/test-quality.md (consumer: review-record line 116). No plugin markdown wording is pinned.

### 2.5 review-depth-qa.acceptance.test.sh (70 DELETE)

| Line(s) | Label (abbreviated) | Markdown pinned | Verdict | Note |
|---|---|---|---|---|
| 461-474 (14, one per line) | A9: Critic: skipped (depth light); light/standard/full critic + Fable rules in brainstorming and auto-run.md; depth decides not trigger list; owner full gets critic; two absent checks (472, 473); User Review Gate message names skip (474) | skills/brainstorming/SKILL.md + references (architecture-critic.md, user-review-gate.md), reference/auto-run.md | DELETE | whole `if want A9` block 457-475 deletable (458-460 locals) |
| 481 | A10 writing-plans no longer records skipped plan review (absent) | skills/writing-plans/references/lint-and-review.md | DELETE | 482-491 (plan-lint behaviour) KEEP |
| 493-501 (9) | A10 handoff steps 0-4, plain context-size, not --plan, 1-3 tasks continue, 4+ keep handoff, hard stop, exception names no standard/full (absent), exception is light, handoff skill | skills/writing-plans/references/execution-handoff.md, skills/handoff/SKILL.md | DELETE | locals at 479-480 go |
| 508-515 (8) | A11 final-review.md light skip line, recovery treats skipped as complete, executing-plans/SDD skipped counts as complete (510, 511), codex round skipped, runs at full, logs Review depth before step 0 | reference/final-review.md, skills/executing-plans/SKILL.md, SDD references/ledger.md | DELETE | review-record reads the ledger lines (REVIEW_LINES, line 26) from the ledger file, not these docs |
| 516-519 | A11 Review depth line specified before step 0 (dline/gline compare) | final-review.md | DELETE | 1 assertion |
| 520, 521 | A11 tables: QA skipped at light only; Codex round skipped at light and standard | final-review.md | DELETE | |
| 522, 523, 524 | A11 ledger grammars hold Review depth line and skipped QA line | executing-plans SKILL.md, SDD ledger.md | DELETE | |
| 526 | A11 depth line does not begin with Final review (absent) | final-review.md | DELETE | whole `if want A11` block 505-527 deletable |
| 532, 533, 534, 535 | A12 gates / UI proof / Claude review / fix wave run at every depth | reference/final-review.md | DELETE | 546-557 (review-route --final, --final-fix, lens-route) KEEP |
| 536, 537, 538 | A12 README table rows | README.md | DELETE | |
| 540, 541, 542 | A12 depth never removes spec approval; specReview=false; approve option | brainstorming SKILL.md + refs | DELETE | |
| 543, 544 | A12 final review never skips gates / UI proof by depth (absent) | final-review.md | DELETE | locals FT (531), BT (539) go |
| 580, 581, 582, 583, 584 | A14 Process line text, Depth line placement, `depth-route --spec-triggers` | using-dforge SKILL.md, brainstorming SKILL.md | DELETE | depth-route reads the spec's **Depth:** line; it does not read the skill |
| 585-590 | A14 the 2026-10-27 review-depth spec has Depth below Execution strategy | docs/dforge/specs/2026-10-27-review-depth-design.md | DELETE | 1 assertion on a historical spec; `SPEC_DOC` (20) goes; whole `if want A14` block 578-592 deletable |
| 591 | A14 self-review checks Depth line | brainstorming SKILL.md | DELETE | |
| 597, 598, 599, 600 | A15 final-review step 4 appends each lens-skipped line, whatever its reason, not only cap (absent), names depth | reference/final-review.md | DELETE | lens-route prints these lines; the doc is not read |
| 602, 603 | A15 finishing lists every lens-skipped line; not only cap (absent) | finishing SKILL.md | DELETE | |
| 604, 605 | A15 auto-run.md Finishing lists lens-skipped lines; not only cap (absent) | auto-run.md | DELETE | |
| 606, 607, 608, 609 | A15 finishing / auto-run.md list test statements under not verified (depth light); keyed on Review depth: light; standard or full prints nothing | finishing SKILL.md, auto-run.md | DELETE | whole `if want A15` block 595-610 deletable (S4, FN locals) |

Tally: A9 14, A10 10, A11 15, A12 12, A14 7, A15 12 = 70.

Dead after deletion: lines 444-455 (BR AR WP BRR WPR HO FR FIN EX UD README) and 453 (sdd-text.sh source); helpers flat (36), flat_skill (37), sect (38-41). `present`/`absent`/`check` stay (used by A1-A8, A10 lint part, A12 routing part, A13, A16).
DEPENDENT TEST WILL BREAK: tests/auto-default.test.sh line 162 asserts that `FN=$(flat_skill "$FIN")` appears exactly once in this file (that is the A15 block, line 601), and line 161 / tests/speed-and-cost-followups.acceptance.test.sh 453-454 grep this file for `SD=` (0 expected, still 0). Line 162 of auto-default.test.sh is itself a pin on test-source text and must be deleted in the same change.

### 2.6 review-depth.acceptance.test.sh (67 DELETE)

| Line(s) | Label (abbreviated) | Markdown pinned | Verdict | Note |
|---|---|---|---|---|
| 394, 395, 396, 397, 398, 399 | A9 brainstorming reports Critic: skipped; fold no longer keys on triggers (lacks); spec review message carries depth; no second Fable round at standard; full keeps separate critic; depth decides | skills/brainstorming/SKILL.md + references | DELETE | whole a9() 391-400 deletable |
| 405, 406, 407, 408, 409, 410, 411, 412, 413 | A10 writing-plans: no skipped plan review (lacks), handoff steps 0-4, light 1-3 tasks, plain context-size, on ok, other result step 5, no gate-probe skip (lacks), hard-stop exception, 4+ tasks keeps handoff | skills/writing-plans/SKILL.md + refs | DELETE | 417-423 (plan-lint behaviour) KEEP; locals 403-404 go |
| 414, 415 | A10 handoff light plan stop; no longer every plan a hard stop (lacks) | skills/handoff/SKILL.md | DELETE | |
| 429, 430, 431, 432 | A11 final-review.md skip line, recovery complete, codex round skipped, logs Review depth | reference/final-review.md | DELETE | whole a11() 426-445 deletable |
| 434, 436, 438, 439, 440 | A11 depth logged before step 0; step 0.5 skip; step 2 codex skip; step 2 skip at light/standard; step 3 waits for no runner | final-review.md | DELETE | |
| 441, 442, 443, 444 | A11 executing-plans and SDD ledger list Review depth and skipped QA lines | skills/executing-plans/SKILL.md, SDD ledger.md | DELETE | |
| 467-473 (7) | A12 "the X step is found" guards (Gates, UI proof, Claude review dispatch, Claude review heading, fix wave, spec review stop, User Review Gate skip rules) | final-review.md, brainstorming SKILL.md | DELETE | they exist only to guard the lacks/has pins below |
| 474-483 (10) | A12 gates / UI proof / Claude review / heading / fix wave / gate skip rules name no depth or light (lacks) | final-review.md, brainstorming SKILL.md | DELETE | |
| 484, 485, 486, 487 | A12 spec review stop not skipped by specReview=false or by depth; no other skip; not said skipped | brainstorming SKILL.md | DELETE | |
| 488 | A12 light approve option says plan is not a stop | brainstorming SKILL.md + refs | DELETE | 449-456 (review-route --final) KEEP; locals/derivations 448, 457-466 go |
| 494, 495, 496, 497 | A14 Process line and Depth line templates | using-dforge SKILL.md, brainstorming SKILL.md | DELETE | |
| 498-500 | A14 review-depth spec has Depth below Execution strategy | docs/dforge/specs/2026-10-27-review-depth-design.md | DELETE | 1 assertion (499-500); whole a14() 491-501 deletable |
| 507 | A15 "step 4 is found" guard | final-review.md | DELETE | |
| 508, 509 | A15 step 4 writes lens-skipped lines; not only reason=cap (lacks) | final-review.md | DELETE | |
| 510, 511 | A15 finishing reads lens-skipped lines; not only cap (lacks) | finishing SKILL.md | DELETE | |
| 512 | A15 auto-run.md Finishing not only cap (lacks) | reference/auto-run.md | DELETE | |
| 513, 514 | A15 finishing lists unverified test statements at light; from statements tagged test | finishing SKILL.md | DELETE | |
| 515 | A15 attended finish lists lens-skipped at Step 3 | finishing SKILL.md | DELETE | |
| 516 | A15 auto-run.md Finishing lists them too | auto-run.md | DELETE | whole a15() 503-517 deletable |

Tally: A9 6, A10 11, A11 13, A12 22 (7 guards + 14 + 1), A14 5, A15 10 = 67.

Dead after deletion: 379-389 (BS UD AR WP HO FR EP FIN and the sdd-text.sh source), helpers doc (55), skill_doc (56-58), between (59-63). `matches` stays (a7 at 320, 322).
Update ALL (line 519): remove a9, a11, a14, a15 (the `case " $ALL "` guard at 524-527 rejects unknown names, but only for names passed on the command line; the default run calls every name in ALL, so a leftover name would fail with "command not found").

### 2.7 review-route.test.sh (167 DELETE)

Everything from 391 to 549, 816-835, 890-911 and 957-960 that reads a plugin markdown file. Routing behaviour (1-390, 552-815, 842-877, 919-999) is script output and stays.

| Line(s) | Label (abbreviated) | Markdown pinned | Verdict | Note |
|---|---|---|---|---|
| 394-407 (14, one per line) | writing-plans routes each round, snapshots plan, Codex plan kind, delta file, caps by score, re-rounds only on Critical, one more round at cap, Claude cap 2, no cap-from-totals (402 absent), inline on every plan, inline effort at risk 3, falls back to Opus, native plan-review seat, final review native fix seat | skills/writing-plans/references/{lint-and-review,execution-line}.md, reference/final-review.md | DELETE | |
| 408 | plan reviewer prompt names both round-1 Claude seats | plan-reviewer-prompt.md | DELETE | |
| 409 | using-dforge states the inline rule | skills/using-dforge/SKILL.md | DELETE | session-start injects the whole file; no logic reads this sentence |
| 410, 411, 412 | README inline floor; caps plan review at two rounds; no longer caps by total (absent) | README.md | DELETE | |
| 413 | writing-plans no longer dispatches a fresh full review (absent) | writing-plans SKILL.md + refs | DELETE | |
| 414, 415 | prompt has Codex round-1 section; names schema | plan-reviewer-prompt.md | DELETE | run-codex-review.sh reads the schema FILE, not this sentence |
| 420, 421, 422 | Codex round-1 read-only line, forbids edits, native judge read-only line | plan-reviewer-prompt.md | DELETE | |
| 423, 424, 425, 426 | delta template: section, [DELTA_FILE], verdicts prior findings, may read beyond | plan-reviewer-prompt.md | DELETE | |
| 429, 430, 431 | writing-plans gate before each round, codex-off round 1, lane only on lane=true | lint-and-review.md, assignment-procedure.md | DELETE | |
| 435-444 (10) | self-review block named in brainstorming and writing-plans; bounded design step 4; main agent only (x2); revision one new round (x2); block before plan review; skip-self-review flag; no re-run loop (444 absent) | brainstorming SKILL.md + refs, writing-plans SKILL.md | DELETE | |
| 447-456 (10) | do-less approach, Acceptance section, must-not-happen, riskiest assumption (x2), self-review items 6 and 7, plan's first task, acceptance ratings, assumption evidence | brainstorming/references/{design-phase,spec-document,spec-self-review}.md, writing-plans SKILL.md | DELETE | no script reads spec section names |
| 463-471 (9) | Seats table, light tier, risk 3 section, risk 2 section absent, failed-route fallback, task seats at risk 3, second pass points at loop, README drops risk 2 (absent), second pass at risk 3 only | reference/delegated-task.md, reference/executor-lane.md, README.md, task-reviewer-prompt.md | DELETE | task-step renders task-reviewer-prompt.md but fills placeholders only; this is a prose sentence inside it |
| 472, 473, 474, 475, 476, 477, 478 | no three-seat average (x2), no K=3 (x2), seat clause, runner name, scoped re-review seats | sdd_text (all SDD files), delegated-task.md | DELETE | |
| 481-488 (8) | carried breaker gap: completion, dispatch, flow graph, inline mode (x2), next task in plan order, final review, fix list without triage | delegated-task.md, SDD references/process-graph.md, executing-plans views, final-review.md | DELETE | |
| 491-496 (6) | pinned escalation-only implementer; FAILED deferral; no-redispatch; refresh gate; codex-off route; codex-off seat record | delegated-task.md | DELETE | |
| 497-500 (4) | task reviewer prompt: second pass section, [CODEX_REVIEW_FILE], order, no score raise | task-reviewer-prompt.md | DELETE | |
| 504, 505, 506, 507, 508, 509 | SDD routes ruling seat; no Fable pin (check); header amendment second seat; no keep-off-Opus (check); [CONFIRM_NOTE]; routes its judge | SDD SKILL.md, ruling-seat.md, ruling-prompt.md | DELETE | |
| 512 | judge-opus grades by consequence | agents/judge-opus.md body | DELETE | body text (not the description field) |
| 518-522 loop (18 files) | no `risk3-spread` anywhere (SDD SKILL + 10 SDD refs + ruling-prompt + executing-plans SKILL + 5 executing-plans refs) | skills/subagent-driven-development/**, skills/executing-plans/** | DELETE | absence-of-word sweep |
| 523 | inline mode reaches executor-empty-diff | executing-plans view | DELETE | |
| 528-540 (13) | lane reference sections, distilled constraints, tick without asking, Claude judge, no risk-3 seat, ladder light tier (534), gate before roster, gates in priority order, closed gate drops one, header lists ticked ids, first admitting executor, never hops | reference/executor-lane.md, reference/ladder.md prose (534) | DELETE | 534 is ladder prose outside the fences |
| 542, 543 | assignment-procedure: precedence gap closed (absent); first admitting executor | skills/writing-plans/references/assignment-procedure.md | DELETE | |
| 544, 545, 546, 547, 548, 549 | dispatch gate then roster; refreshes gate; refused model HANDBACK; refusal never takes successor (ladder prose 547); final Codex round needs review surface; seats name runner's gate | executor-lane.md, ladder.md prose | DELETE | |
| 818, 819, 820, 821 | README nineteen agents; no three-seat mean (absent); names review-route; plan-review schema | README.md | DELETE | |
| 826, 831, 834, 835 | program design names sub-projects 10, 8, 9; records session gate | docs/superpowers/specs/2026-09-11-dr-superpowers-fork-design.md (historical spec) | DELETE | |
| 827, 828 | approach advisor on Opus; load-bearing decision reaches advisor | skills/selecting-approaches/SKILL.md | DELETE | |
| 829, 830 | budget reference derives the budget; checkpoints finish the task in flight | reference/session-budget.md | DELETE | scripts/lib/context.sh implements the formula and only cites the doc |
| 832, 833 | README names session gate; trust per surface | README.md | DELETE | |
| 890-900 (11) | executor-lane.md: registry gate/blocks/wrapper, per-executor section, neutral ruling kind, background-call rule, two-failure budget, wedged-client case, resume section, no poll loop (absent), no survivor note (absent) | reference/executor-lane.md | DELETE | |
| 905-911 (7) | ruling prompt neutral kind / no Codex-only kind; ledger grammar executor-neutral; escalation resumes executor's own session (x2); loop resumes own session (x2) | ruling-prompt.md, SDD ledger.md, escalation.md, delegated-task.md | DELETE | |
| 957, 959 | ruling prompt: REWORD verdict; acceptance-ambiguous kind | ruling-prompt.md | DELETE | 953-956 (route output) KEEP |

Tally: 14+1+1+3+1+2+3+4+3+10+10+9+7+8+6+4+6+1+18+1+13+2+6+4+4+2+2+2+11+7+2 = 167.

Dead after deletion: lines 27-30 (SKILL_VIEW_DIR, skill-view.sh, EP_VIEW), 392-393 (WP, PRP), 434 (BS), 459-462 (SDD DT TRP) and 460 (sdd-text.sh source), 503 (RULP), 526-527 (EXEC LAD), 541 (AP), 817 (RD), 880 (LANE), 902-904 (RP ESC LOOP). Keep `present`/`absent` for 241, 246, 385 (stderr file checks). Update header comment lines 3-4 (it advertises "prose checks").

## 3. EXCLUDED borderline cases (kept)

- faster-plans 941/942/945 for task-reviewer-prompt, group-reviewer-prompt, re-review-prompt (9 assertions): task-step renders these and its verdict parser needs the judge to produce `## Verdict` and the finding grammar. Placeholders (3) are a clear KEEP; `## Verdict` and grammar (6) are borderline because the parser reads the report, not the template. Delete them if the judge holds that only literally-read text counts.
- faster-plans 924 (x3): `tools:` frontmatter line of judge agents lists Write; structural, harness reads it.
- faster-plans 1250: `codex-routing.json` review_cap; JSON read by scripts, not markdown.
- faster-plans 1181: old waves plan carries no `**Wave check:**` line; precondition for the `wave check-due` behaviour check at 1182-1183 on a real historical plan.
- faster-plans 1170-1177 (A22): run plan-lint on historical plans and check they are not edited; behaviour on real input.
- review-route 510, 511, 514, 515: phrases inside the `description:` frontmatter of judge-fable.md, judge-sonnet-high.md and judge-opus.md. The harness consumes that field for dispatch, so they are excluded as description-field checks, but no code depends on those exact sentences; the judge may reclassify them as DELETE (4 more).
- review-route 513: greps scripts/review-route SOURCE for `judge-fable` (not markdown); behaviour guard on the script.
- review-route 241, 246, 385: `present` on the script's stderr capture file; script output.
- review-route 823-825: manifest version consistency (JSON), structural.
- review-route 154, 881, 888-889: file exists/gone, structural.
- review-route 866-877: stub Executor routes like codex; script output; the greps are on stdout.
- review-depth-qa 483-491 and review-depth 417-423: plan-lint on a plan fixture whose header carries the skipped line; script behaviour.
- review-depth-qa A8 (373) and review-depth A8 (371): sed on a copy of criteria/lenses/security.md `Applies:` line then run lens-route; fixture for a script that reads that line.
- retained-review-data a1_lens_globs (105-116) and a14 (382-411): edit the lens copy's `Applies:` line; consumer review-record:116.
- review-depth-qa 20, 585-590 and review-depth 498-500 read docs/dforge/specs/2026-10-27-review-depth-design.md: counted as DELETE (historical spec structure, no script reads it); noted here because deleting only the assertion does not edit the spec.
- project-status 109-112 read docs/superpowers/distilled/constraints.md (repo doc outside the plugin tree): counted as DELETE; flagged because the path is outside the listed doc roots.

## 4. After deletion: empty tests, counters, dependents

- No file keeps a TAP plan, `1..N`, or literal expected total. Each prints `printf '\n%d passed, %d failed\n' "$pass" "$fail"` from a running counter (faster-plans 1275, project-status 264, retained-review-data 425, review-depth 534, review-depth-qa 661, review-route 1001, next-step 990), so no count needs editing.
- faster-plans.acceptance.test.sh: the file keeps most of A2-A13, A17 (routing part 891-903), A18 (3 templates + tools line), A19-A23. Functions left with ZERO assertions: a1, a14, a15, a16 (delete them and remove them from ALL at line 1266). REQUIRED FOLLOW-UP OUTSIDE THE FILE: /root/repositories/darkraise-ai-plugins/scripts/test-all.mjs line 91 shards this suite by test name, `a1..a8`, `a9..a16`, `a17..a23`; after removing a1, a14, a15, a16 the shard lists must drop those names or the runner calls undefined functions. Also update the header comment at lines 3-8 (statements A1-A23). scripts/test-shards.mjs line 68 holds a runtime weight (900 s) that will be stale but needs no edit to run.
- project-status.test.sh: not zero, but only 3 existence checks remain (26, 49, 108); consider removing the file and its weight at scripts/test-shards.mjs line 95.
- review-depth-qa.acceptance.test.sh: A9, A11, A14, A15 become empty (delete the `if want A9/A11/A14/A15` blocks at 457-475, 505-527, 578-592, 595-610). A10 and A12 keep their script-behaviour halves (482-491 and 546-557). tests/auto-default.test.sh line 162 (counts `FN=$(flat_skill "$FIN")` == 1 in this file) must be deleted with the A15 block; line 161 stays true.
- review-depth.acceptance.test.sh: a9, a11, a14, a15 become empty (functions at 391-400, 426-445, 491-501, 503-517); a10 and a12 keep behaviour halves (417-423, 449-456). Edit ALL at line 519 to `a1 a2 a3 a4 a5 a6 a7 a8 a10 a12 a13 a16`.
- review-route.test.sh: no function structure; deletions are top-level statements; its behaviour assertions remain.
- next-step.test.sh and retained-review-data.acceptance.test.sh: untouched.



---

# PART g4

# g4: wording pins in plugins/dforge/tests/cockpit.test.ts (7148 lines)

## 1. DELETE count

**0.** cockpit.test.ts contains no wording pins.

Basis: the file never reads a real markdown file. Its imports are `claude-code/testing` (a mod test harness) and `../hooks/cockpit/{lib,notify,config,native,settings-view,svg}`. There is no `node:fs`, `readFileSync`, `import.meta`, `__dirname` or path into `skills/`, `criteria/`, `agents/` or `README`. Every `fs.read`, `fs.exists`, `fs.list` and `fs.stat` handler (lines 520-545, 596, 972, 1699, 2499, 5467) answers from an in-memory `files` or `written` map, so the `.md` strings are virtual fixtures. `rg 'skills/|reference/|criteria/|agents/'` finds only the `reference/auto-run.md` hits listed in section 3. `rg -i 'skill|readme|criteria'` finds only `$.tool.call({ tool: 'Skill', skill: 'dforge:...' })` hooks input, the `dforge:judge-sonnet-high` seat names, and `.claude/` state paths. None of these assert document text.

## 2. Table

| Line(s) | Test name/label | Markdown file and phrase pinned | Verdict | Note |
|---|---|---|---|---|
| none | none | none | none | No row. Nothing in this file reads markdown text from the repo. |

## 3. EXCLUDED borderline cases

- 6376, 6388, 6508-6510, 6579, 6708: expected prompt strings `... End as reference/auto-run.md §Stopping says.` and `... end the turn as reference/auto-run.md §Ending a turn says.`. This is assertion on mod output (`w.prompts`) from the cockpit auto-run code. The test never opens `reference/auto-run.md`. The headings `## Stopping` (reference/auto-run.md:329) and `## Ending a turn` (:222) exist, but no assertion checks them.
- 172-214 (`PROGRESS`/`RESUMABLE`/`FINISHED`/`BLOCKED` handoff strings, `REGISTER`, `registerPrompt`): fixtures fed to `resumeOfferOf` and `promptRegisters`, which parse them. Behaviour, not a pin.
- 4078-4582 (ledger and plan text with `# SDD ledger`, `### Task N`): temp-world fixtures fed to the ledger and plan parsers in the cockpit mod. Behaviour.
- 4658-5224 (`.dforge/handoff/latest.md`, `progress.md`, `docs/dforge/plans/p.md`, mirror `latest.md`): virtual file-system fixtures. Assertions are on mod output (offers, prompts, rows).
- 875-1182 and 7079-7145 (`task-1-review-report.md`, `amendments.md`, `notes.md` in the review-seat write guard): path strings given to the guard, and its deny messages are asserted. Code behaviour.
- 702-707, 748-762 (`isAbsolutePath`, `gitTextFiles`, `--body-file`): path-parsing function behaviour.
- 131 (`? notes.md` in PORCELAIN), 3262 (`Read a.md`), 4285 and 4287 (`Write notes.md`): inputs to code under test.
- 5224 (`### Task 6: Write the README`): plan fixture row, not an assertion on README text.
- 5914-6761, 6968 (`Execute docs/plan.md.`): resume-prompt strings round-tripped through the auto-run mod. Behaviour.
- 789-792 (`seatDenial` messages matching /Execution line/ and /dforge:judge-sonnet-high/): assertion on function output, not on a skill file. Not checked against the source of the message text; it does not affect the count.

## 4. Impact of deleting

Nothing is deleted, so no describe block or the file is left empty, and no expected count needs updating. No line numbers shift.



---

# PART g5

# g5 wording-pin findings (16 test files under plugins/dforge/tests)

Read-only investigation; no repo file was edited. Rule applied: project spec `docs/dforge/specs/2026-11-11-test-volume-rules-design.md` ("Behavior, not text"). Scripts, hooks and config were grepped for each consumer named below (consumers: scripts/task-step, plan-lint, review-record, review-route, next-step, lane-breaker, finish-choice, ui-proof, ui-turn-end.sh, turn-end.sh, lib/plan.sh, lib/fast-mode.sh, lib/depth.sh, darkmem-mirror.mjs, hooks/cockpit/register.tsx and lib.ts).

Verdict key used in the tables:

- **DELETE**: no script, hook or config reads the pinned text (default reason: it is prose, a snippet, a heading, a pointer or an absent-phrase pin). A note appears only when something more specific needs saying (loop, helper, block).
- **KEEP(consumer)**: the pinned text is a placeholder or section a script reads from the file itself (`direct`), or the exact grammar token/line that a named script parses from the output the document tells a session to write (`format contract`: the script reads the ledger/report/header, not this file). The judge may downgrade a `format contract` row to DELETE; it is listed separately in the counts so that choice is easy.
- Borderline items are NOT counted as DELETE; they appear in section 3.
- Counting: each assertion statement is one assertion; a loop over a list of phrases counts one per phrase; a loop over files/skills with the same phrase counts once (the note says `loop ... over N files`).

## 1. Totals

**DELETE: 852 assertions in 14 of the 16 files.** KEEP(direct file read): 13. KEEP(format contract): 50. Borderline, not counted: 20.

| file | DELETE | KEEP direct | KEEP format contract | borderline (not counted) |
|---|---|---|---|---|
| antigravity-executor-lane.acceptance.test.sh | 9 | 0 | 1 | 6 |
| auto-default.test.sh | 116 | 0 | 5 | 0 |
| auto-run-skills.test.sh | 126 | 0 | 2 | 0 |
| auto-run-worktree-setting-qa.acceptance.test.sh | 46 | 0 | 0 | 0 |
| auto-run-worktree-setting.acceptance.test.sh | 53 | 0 | 0 | 1 |
| auto-run.test.sh | 0 | 0 | 0 | 0 |
| budget-line.test.sh | 2 | 0 | 0 | 0 |
| inline-mode.test.sh | 133 | 0 | 19 | 1 |
| inline-only-execution.acceptance.test.sh | 13 | 0 | 1 | 1 |
| inline-only.acceptance.test.sh | 34 | 0 | 1 | 4 |
| process-roles.test.sh | 127 | 2 | 3 | 2 |
| seats.test.sh | 87 | 11 | 15 | 1 |
| settings-skills.test.sh | 71 | 0 | 2 | 2 |
| ui-proof.test.sh | 0 | 0 | 0 | 0 |
| ui-ux-skill.acceptance.test.sh | 8 | 0 | 0 | 0 |
| ui-ux-skill.test.sh | 27 | 0 | 1 | 2 |

Files with no wording pin (script behaviour only): auto-run.test.sh, ui-proof.test.sh.

## 2. Per-file tables

### antigravity-executor-lane.acceptance.test.sh

DELETE 9, KEEP direct 0, KEEP format contract 1, borderline 6 (borderline rows are in section 3).

| line(s) | test label | markdown file: phrase pinned | verdict | note |
|---|---|---|---|---|
| 417 | A4: the lane reference keeps batched tasks off the lane | $lane: Batched tasks stay on the Claude lane | DELETE | A4 (415-418): executor-lane.md sentence; 416 `lane=$(doc ...)` is its helper variable |
| 418 | A4: and forbids an Executor line on a batched task | $lane: Do not write an ‘**Executor:**‘ line on a batched task | DELETE | A4 |
| 699 | A14: the constraints file carries the Antigravity lane entry | $entry: The Antigravity executor lane is on | DELETE | A14: distilled/constraints.md sentence (docs file); 697-698 are its variables and are then unused (with `doc()` at 159 if A4/A18 also go) |
| 700 | A14: the entry says to tick agy without asking when the gat… | $entry: lane=true.*ticks ‘agy‘ without asking\|ticks ‘agy‘ without asking | DELETE | A14 |
| 842 | A18: the lane reference states the ledger line | $lane: Plan: executor agy off - unreliable (2 handbacks) | KEEP(scripts/lane-breaker; format contract) | scripts/lane-breaker reads the ledger line `Plan: executor <id> off - unreliable (...)` (lane-breaker); pins the doc stating that exact line |
| 843 | A18: and sends a tripped agy task to the session | $lane: On \‘state=tripped\‘ run neither the gate, the roster nor the wrapper: fall back to the session | DELETE | A18: executor-lane.md sentence; 841 `lane=$(doc ...)` is its helper variable |
| 844 | A18: and tells a resumed controller the ledger is enough | $lane: A resumed controller needs nothing more | DELETE | A18 |
| 851 | A19: the lane reference has a Per-executor: agy section | got: $(grep -c '^## Per-executor: agy' "$ref")  want: 1 | DELETE | A19 (848-854): heading count in executor-lane.md; whole block is wording only (849-850 are its variables) |
| 852 | A19: the section states agy is unsandboxed | $section: [Uu]nsandboxed | DELETE | A19 |
| 853 | A19: the section states the fingerprints cover only the lin… | $section: fingerprints cover only the linked worktree and its refs | DELETE | A19 |

### auto-default.test.sh

DELETE 116, KEEP direct 0, KEEP format contract 5, borderline 0 (borderline rows are in section 3).

| line(s) | test label | markdown file: phrase pinned | verdict | note |
|---|---|---|---|---|
| 19 | the section | skills/brainstorming/SKILL.md: ## Auto by default (‘autoRun=on‘) | DELETE |  |
| 20 | the setting | skills/brainstorming/SKILL.md: - ‘autoRun=on‘, the default: the architectural path runs as Auto by defau… | DELETE |  |
| 21 | designApproval has no effect | skills/brainstorming/SKILL.md: ‘autoRun=on‘, which presents no design. | DELETE |  |
| 22 | specReview has no effect | skills/brainstorming/SKILL.md: Gate and go on to Implementation. It has no effect under ‘autoRun=on‘: | DELETE |  |
| 23 | the checklist points at the section | skills/brainstorming/SKILL.md: **Architectural:** (under ‘autoRun=on‘, the default on Claude Code, steps… | DELETE |  |
| 24 | no sub-project split | skills/brainstorming/SKILL.md: Under ‘autoRun=ask‘ or ‘autoRun=off‘ only (under ‘on‘, one spec covers th… | DELETE |  |
| 25 | one spec | skills/brainstorming/references/auto-by-default.md: One spec covers the whole request: no | DELETE |  |
| 26 | acceptance waits for the review | skills/brainstorming/references/drafting-acceptance.md: Under ‘autoRun=on‘ skip this step and the offer … | DELETE |  |
| 27 | no design presented | skills/brainstorming/references/design-phase.md: ; under ‘autoRun=on‘ present no design (see Auto by def… | DELETE |  |
| 28 | self-review accepts an open statement | skills/brainstorming/references/spec-self-review.md: Under ‘autoRun=on‘, a statement rated ‘medium‘ or ‘… | DELETE |  |
| 29 | the critic gets the decisions | skills/brainstorming/references/architecture-critic.md: spec path, the approved design sections verbatim… | DELETE |  |
| 30 | the gate is the spec review | skills/brainstorming/references/user-review-gate.md: Under ‘autoRun=on‘, this gate is the spec review me… | DELETE |  |
| 31 | no plan budget check in a run | skills/brainstorming/SKILL.md: an auto run skip this check: the plan is always written in this session. | DELETE |  |
| 32 | the review rulings section | skills/brainstorming/references/auto-by-default.md: ‘## Review rulings‘ | DELETE |  |
| 33 | the three approvals | skills/brainstorming/references/auto-by-default.md: - **Approve and run unattended**, **Approve, keep th… | DELETE |  |
| 34 | the finish line | skills/brainstorming/references/auto-by-default.md: ‘Finish: <merge\|pr\|keep>‘ line in ‘## Decisions‘; | KEEP(finish-choice; format contract) | finish-choice reads the spec `Finish:` line under `## Decisions` |
| 35 | specReview never skips it | skills/brainstorming/references/auto-by-default.md: ‘specReview=false‘ does not skip this stop. | DELETE |  |
| 36 | the finish line is a bare paragraph | skills/brainstorming/references/auto-by-default.md: recorded as its own paragraph (no list | DELETE |  |
| 37 | a review deferral carries its command | skills/brainstorming/references/auto-by-default.md: ‘scripts/register add <register> "A<n>: <statement>"… | DELETE |  |
| 38 | a review deferral opens a register | skills/brainstorming/references/auto-by-default.md: with no register open, first open ‘<docs>/registers/… | DELETE |  |
| 39 | start takes the deferrals' register | skills/brainstorming/references/auto-by-default.md: ‘--register <path>‘ when a register is open, and alw… | DELETE |  |
| 41 | writing-plans: a listed launch at the switch | skills/writing-plans/references/auto-run-plan.md: (on exit 5, wait for or stop what ‘scripts/in-flight‘ … | DELETE |  |
| 43 | finishing: get reads the spec line | skills/finishing-a-development-branch/SKILL.md: ‘Finish:‘ line itself and records it with ‘"source": "sp… | DELETE |  |
| 44 | finishing: a final residual keeps a merge | skills/finishing-a-development-branch/SKILL.md: the run added. ‘merge‘ also keeps when the run added a d… | DELETE |  |
| 45 | finishing: the final message lists residuals | skills/finishing-a-development-branch/SKILL.md: it; the ‘final review residual‘ rows among them), | DELETE |  |
| 46 | finishing: a deferred task keeps its rows deferred | skills/finishing-a-development-branch/SKILL.md: ‘(deferred by the auto run)‘ is set with | DELETE |  |
| 47 | finishing: no read-the-spec-and-set clause | got: $(cat "$FIN" "$P/skills/finishing-a-development-branch/references/"*.md \| tr '\n' ' ' \| tr -s ' '… | DELETE | absent-phrase pin |
| 48 | rulings are imported | skills/brainstorming/references/auto-by-default.md: ‘scripts/auto-run ruling add "Fable, spec: <line>"‘ | DELETE |  |
| 49 | the old pin survives | skills/brainstorming/SKILL.md: ‘autoRun=off‘: never offer an auto run | DELETE |  |
| 50 | a Codex host runs attended | skills/brainstorming/references/auto-by-default.md: and on a Codex host ‘on‘ behaves as ‘off‘. Steps 1-4 | DELETE |  |
| 51 | Fable's open items are asked at the review | skills/brainstorming/references/auto-by-default.md: - every item Fable left undecided, and every critic … | DELETE |  |
| 52 | critic prompt: the decisions | skills/brainstorming/references/architecture-critic-prompt.md: or under ‘autoRun=on‘ the spec's | DELETE |  |
| 53 | using-dforge: the approval is the spec review | skills/using-dforge/SKILL.md: still get approval (under ‘autoRun=on‘, the spec review). | DELETE |  |
| 65 | using-dforge: the Process line names the depth | skills/using-dforge/SKILL.md: $PROC | DELETE |  |
| 66 | using-dforge: the depth comes from depth-route | skills/using-dforge/SKILL.md: ‘<d>‘ from ‘scripts/depth-route --spec-triggers‘ | DELETE |  |
| 67 | brainstorming: the Process line names the depth | skills/brainstorming/SKILL.md: $PROC | DELETE |  |
| 68 | brainstorming: the depth comes from depth-route | skills/brainstorming/SKILL.md: take ‘<d>‘ from ‘scripts/depth-route --spec-triggers <ids>‘ | DELETE |  |
| 69 | brainstorming: a later trigger reruns depth-route and the d… | skills/brainstorming/SKILL.md: reruns ‘scripts/depth-route --spec-triggers‘ with the whole list, and the… | DELETE |  |
| 70 | brainstorming: an owner line survives the ratchet | skills/brainstorming/SKILL.md: a ‘**Depth:** <d> — owner‘ line is left as it is | DELETE |  |
| 71 | brainstorming: the depth decides the fold, not the triggers | skills/brainstorming/references/architecture-critic.md: The depth decides, not the trigger list | DELETE |  |
| 72 | brainstorming: an owner full line gets the separate critic | skills/brainstorming/references/architecture-critic.md: a spec whose line reads ‘**Depth:** full — owner… | DELETE |  |
| 73 | brainstorming: light runs the self-review round only | skills/brainstorming/references/auto-by-default.md: At ‘light‘, run the spec self-review round and nothi… | DELETE |  |
| 74 | brainstorming: standard folds the critic and runs no second… | skills/brainstorming/references/auto-by-default.md: with the critic folded into it (Architecture critic)… | DELETE |  |
| 75 | brainstorming: a Codex host runs the spec phase as full | skills/brainstorming/references/architecture-critic.md: On a Codex host the spec phase runs as ‘full‘ at… | DELETE |  |
| 76 | brainstorming: light reports the critic as skipped | skills/brainstorming/references/architecture-critic.md: ‘Critic: skipped (depth light)‘ | DELETE |  |
| 77 | brainstorming: the spec review names the depth | skills/brainstorming/references/auto-by-default.md: ‘Depth: <d> — <reasons>‘ | DELETE |  |
| 78 | brainstorming: the light approve option says the plan is no… | skills/brainstorming/references/auto-by-default.md: (depth light: the plan is not a stop; execution foll… | DELETE |  |
| 79 | brainstorming: the owner sets the depth under Changes needed | skills/brainstorming/references/auto-by-default.md: sets the depth by hand under **Changes needed**: wri… | DELETE |  |
| 80 | brainstorming: no rulings to import at light | skills/brainstorming/references/auto-by-default.md: (none at depth light) | DELETE |  |
| 81 | brainstorming: self-review checks the Depth line | skills/brainstorming/references/spec-self-review.md: its first word is ‘light‘, ‘standard‘ or ‘full‘ | DELETE |  |
| 82 | brainstorming: every architectural spec carries the Depth l… | skills/brainstorming/references/spec-document.md: carries a ‘**Depth:**‘ line directly below its ‘**Exec… | DELETE |  |
| 83 | brainstorming: the fold no longer keys on the Process line'… | <(cat "skills/brainstorming/SKILL.md" "skills/brainstorming/references/"*.md): your Process line names n… | DELETE | absent-phrase pin across all brainstorming md |
| 84 | auto-run.md: the spec depth sizes the phase | reference/auto-run.md: The spec's ‘**Depth:**‘ line sizes this phase | DELETE |  |
| 85 | auto-run.md: light dispatches no critic and no Fable review | reference/auto-run.md: dispatch no critic and no Fable review, record no spec ruling | DELETE |  |
| 86 | auto-run.md: light under ask reaches execution with no read… | reference/auto-run.md: reaches execution with no reader of the written spec | DELETE |  |
| 87 | auto-run.md: the critic folds at depth standard | reference/auto-run.md: folds the critic into Fable's first round at depth standard | DELETE |  |
| 88 | auto-run.md: no second Fable round at standard | reference/auto-run.md: at depth ‘standard‘ no second round runs | DELETE |  |
| 89 | auto-run.md: finishing lists every lens-skipped line | reference/auto-run.md: ‘final review lens-skipped <id> reason=<reason>‘ line in the ledger, whatever its… | DELETE |  |
| 90 | auto-run.md: light finishing lists the unverified test stat… | reference/auto-run.md: every ‘test‘ statement of the spec under ‘not verified (depth light)‘ | DELETE |  |
| 91 | brainstorming: the open line decides a second round only at… | skills/brainstorming/references/architecture-critic.md: decides whether a second round runs at depth ‘fu… | DELETE |  |
| 100 | ci-parity.md: $h | reference/ci-parity.md: $h | DELETE | loop 99-101 over 3 headings; counts as 3 assertions |
| 102 | ci-parity.md: the search order | reference/ci-parity.md: ‘.github/workflows/*.yml‘ first, then ‘.gitlab-ci.yml‘, ‘azure-pipelines.yml‘, ‘… | DELETE | ci-parity.md: no script reads it (plan-lint reads the plan `**CI:**` line only) |
| 103 | ci-parity.md: the table columns | reference/ci-parity.md: \| Platform \| Pitfall \| Do instead \| | DELETE | ci-parity.md: no script reads it (plan-lint reads the plan `**CI:**` line only) |
| 110 | ci-parity.md: five Windows Git Bash rows | got: $(rows_for 'Windows Git Bash')  want: 5 | DELETE | helper rows_for (104-109) is used only by 110-113 |
| 111 | ci-parity.md: three macOS rows | got: $(rows_for macOS)  want: 3 | DELETE | ci-parity.md: no script reads it (plan-lint reads the plan `**CI:**` line only) |
| 112 | ci-parity.md: two uutils rows | got: $(rows_for 'uutils (ubuntu-latest)')  want: 2 | DELETE | ci-parity.md: no script reads it (plan-lint reads the plan `**CI:**` line only) |
| 113-114 | ci-parity.md: the table holds those ten rows, a header and … | got: $(awk '/^## / { on = ($0 == "## Pitfalls"); next } on && /^\\|/ { n++ } END { print n + 0 }' $CIP) … | DELETE | ci-parity table row count |
| 119 | ci-parity.md Pitfalls names $needle | got: $got  want: yes | DELETE | loop 116-120 over 12 needles of the Pitfalls table; counts as 12 assertions |
| 121 | ci-parity.md: uncovered means the host is not that platform | reference/ci-parity.md: A platform is uncovered when the host running dforge is not that platform. | DELETE | ci-parity.md: no script reads it (plan-lint reads the plan `**CI:**` line only) |
| 122 | ci-parity.md: uutils is covered only by a uutils host | reference/ci-parity.md: only when ‘cp --version‘ names uutils | DELETE | ci-parity.md: no script reads it (plan-lint reads the plan `**CI:**` line only) |
| 123 | ci-parity.md: only workflow_dispatch workflows start early | reference/ci-parity.md: ‘workflow_dispatch‘ | DELETE | ci-parity.md: no script reads it (plan-lint reads the plan `**CI:**` line only) |
| 125 | writing-plans: the header template has a CI line | skills/writing-plans/SKILL.md: **CI:**  | KEEP(plan-lint; format contract) | plan-lint warns when a plan has no `**CI:**` line (scripts/plan-lint:673) |
| 126 | writing-plans: the CI line grammar | skills/writing-plans/references/ci-line.md: ‘<workflow files>‘ — platforms: <list> — local: ‘<cmd>‘; ‘<c… | KEEP(plan-lint; format contract) | plan-lint ci_shape (scripts/plan-lint:676) and scripts/ci-mirror parse this CI-line grammar |
| 127 | writing-plans: none when no CI configuration is found | skills/writing-plans/references/ci-line.md: write ‘**CI:** none‘ when no CI configuration is found | DELETE |  |
| 128 | writing-plans: uncovered names come from the Platform column | skills/writing-plans/references/ci-line.md: ‘uncovered:‘ lists names from the Platform column of the Pit… | DELETE |  |
| 129 | writing-plans: uncovered platforms copy their pitfalls rows | skills/writing-plans/references/ci-line.md: copy that platform's rows of the Pitfalls table in [ci-parit… | DELETE |  |
| 130 | writing-plans: the early-CI offer needs an uncovered platfo… | skills/writing-plans/references/ci-line.md: Offer the early CI run only when the CI line names an uncove… | DELETE |  |
| 131 | writing-plans: the owner's answer is the consent | skills/writing-plans/references/ci-line.md: your human partner's answer is the consent | DELETE |  |
| 132 | writing-plans: the early-CI wave form | skills/writing-plans/references/ci-line.md: **Early CI:** after wave <k> — consented <YYYY-MM-DD> | KEEP(plan-lint; format contract) | plan-lint Early CI header parse (scripts/plan-lint:682-707) |
| 133 | writing-plans: the early-CI task form | skills/writing-plans/references/ci-line.md: **Early CI:** after task <n> — consented <YYYY-MM-DD> | KEEP(plan-lint; format contract) | plan-lint Early CI header parse (scripts/plan-lint:682-707) |
| 134 | writing-plans: an auto run copies the recorded decision | skills/writing-plans/references/ci-line.md: ask nothing and copy the ‘Early CI:‘ line of the spec's ‘## … | DELETE |  |
| 135 | writing-plans: first and midway resolve to a point | skills/writing-plans/references/ci-line.md: ‘first‘ is ‘after wave 1‘ on a waves plan and ‘after task 1‘… | DELETE |  |
| 136 | writing-plans: no line without an uncovered platform | skills/writing-plans/references/ci-line.md: Write no ‘**Early CI:**‘ line when every platform is covered | DELETE |  |
| 138 | brainstorming: the spec phase reads the CI configuration | skills/brainstorming/references/auto-by-default.md: read the CI configuration as [ci-parity.md](../../..… | DELETE |  |
| 139 | brainstorming: the early-CI question needs an uncovered pla… | skills/brainstorming/references/auto-by-default.md: when the CI configuration has an uncovered platform,… | DELETE |  |
| 140 | brainstorming: the no-run option is recommended | skills/brainstorming/references/auto-by-default.md: No early run (Recommended) | DELETE |  |
| 141 | brainstorming: the answer goes to Decisions | skills/brainstorming/references/auto-by-default.md: record the answer in ‘## Decisions‘ as ‘Early CI: no… | DELETE | Decisions line is read by an LLM, no script parses `Early CI:` from a spec |
| 142 | brainstorming: the answer is the consent for the push and d… | skills/brainstorming/references/auto-by-default.md: the answer is the consent for the push and the workf… | DELETE |  |
| 148 | process-graph: no label points into ./references/ | got: $(grep -c '\./references/' "$SDD_REFS/process-graph.md")  want: 0 | DELETE | pointer-text pin (not a link resolver) |
| 150 | process-graph: a label names ./$template.md | skills/subagent-driven-development/references/process-graph.md: (./$template.md) | DELETE | loop 149-151 over 5 template names; counts as 5 assertions |
| 152 | subagent-driven-development: an older run's R/5 points at l… | skills/subagent-driven-development/SKILL.md: ‘R/5‘ maps as ledger.md §Recovery says | DELETE | pointer-text pin (not a link resolver) |
| 153 | subagent-driven-development setup: the Recovery table is in… | skills/subagent-driven-development/references/setup.md: the Recovery table in [ledger.md](ledger.md) §Re… | DELETE | pointer-text pin (not a link resolver) |
| 154 | executing-plans: the Recovery table is in recovery.md | skills/executing-plans/SKILL.md: see the Recovery table in [recovery.md](references/recovery.md) | DELETE | pointer-text pin (not a link resolver) |
| 155 | executing-plans setup: the Recovery table is in recovery.md | skills/executing-plans/references/setup.md: the Recovery table in [recovery.md](recovery.md) | DELETE | pointer-text pin (not a link resolver) |
| 156 | no Recovery pointer goes through The Ledger | <(cat "skills/subagent-driven-development/SKILL.md" "skills/subagent-driven-development/references/setup… | DELETE | pointer-text pin (not a link resolver) |
| 157 | no Recovery pointer names The Ledger's Recovery | skills/subagent-driven-development/SKILL.md: The Ledger's Recovery | DELETE | pointer-text pin (not a link resolver) |
| 159 | writing-plans: the spec's strategy line comes from design-p… | skills/writing-plans/SKILL.md: [design-phase.md](../brainstorming/references/design-phase.md) | DELETE | pointer-text pin (not a link resolver) |
| 160 | writing-plans: the question is not named by a section of br… | skills/writing-plans/SKILL.md: dforge:brainstorming §Choosing the execution strategy | DELETE | pointer-text pin (not a link resolver) |
| 175 | pipeline-smoke note: a Caveats section | ../../docs/dforge/notes/2026-10-28-pipeline-smoke.md: ## Caveats | DELETE | docs note outside plugin dirs; no script |
| 176 | pipeline-smoke note: the figures come from the last result … | ../../docs/dforge/notes/2026-10-28-pipeline-smoke.md: come from the last ‘result‘ event of each run only | DELETE | docs note outside plugin dirs; no script |
| 177 | pipeline-smoke note: the timeline includes subagent messages | ../../docs/dforge/notes/2026-10-28-pipeline-smoke.md: subagent messages included | DELETE | docs note outside plugin dirs; no script |
| 178 | pipeline-smoke note: the no-polling reading rests on the fi… | ../../docs/dforge/notes/2026-10-28-pipeline-smoke.md: rests on the ‘parent_tool_use_id‘-filtered check | DELETE | docs note outside plugin dirs; no script |
| 179 | pipeline-smoke note: p1_overlap was changed mid-run | ../../docs/dforge/notes/2026-10-28-pipeline-smoke.md: ‘p1_overlap‘ check | DELETE | docs note outside plugin dirs; no script |
| 180 | pipeline-smoke note: p1_overlap now groups by message id | ../../docs/dforge/notes/2026-10-28-pipeline-smoke.md: to group tool uses by message id | DELETE | docs note outside plugin dirs; no script |

### auto-run-skills.test.sh

DELETE 126, KEEP direct 0, KEEP format contract 2, borderline 0 (borderline rows are in section 3).

| line(s) | test label | markdown file: phrase pinned | verdict | note |
|---|---|---|---|---|
| 28 | $skill: the section | skills/$skill/SKILL.md: ## Auto run | DELETE | inside loop 26-53 over 2 skills (subagent-driven-development, executing-plans): same phrase, run twice |
| 29 | $skill: after a compaction | skills/$skill/SKILL.md: ‘scripts/auto-run after-compact‘ before step 0 above | DELETE | inside loop 26-53 over 2 skills (subagent-driven-development, executing-plans): same phrase, run twice |
| 30 | $skill: setup asks nothing, from the worktree | skills/$skill/SKILL.md: from the execution workspace | DELETE | inside loop 26-53 over 2 skills (subagent-driven-development, executing-plans): same phrase, run twice |
| 31 | $skill: exit 4 is a skipped workspace step | skills/$skill/SKILL.md: Exit 4 means the workspace step was skipped: | DELETE | inside loop 26-53 over 2 skills (subagent-driven-development, executing-plans): same phrase, run twice |
| 32 | $skill: no ledger goes to Setup | skills/$skill/SKILL.md: no ledger names this plan, no task has started: skip the rest of this | DELETE | inside loop 26-53 over 2 skills (subagent-driven-development, executing-plans): same phrase, run twice |
| 33 | $skill: setup due goes to Setup | skills/$skill/SKILL.md: 0. In an auto run, when ‘scripts/auto-run status‘ says setup is due, or when | DELETE | inside loop 26-53 over 2 skills (subagent-driven-development, executing-plans): same phrase, run twice |
| 34 | $skill: a task-complete stop | skills/$skill/SKILL.md: A ‘task-complete‘ exit 5 means the run stopped (a task was completed | DELETE | inside loop 26-53 over 2 skills (subagent-driven-development, executing-plans): same phrase, run twice |
| 35 | $skill: dependents come from the plan | skills/$skill/SKILL.md: names the task; in a plan without those lines, its ‘Consumes:‘ line cites | DELETE | inside loop 26-53 over 2 skills (subagent-driven-development, executing-plans): same phrase, run twice |
| 36 | $skill: compact still ends the turn at the final check | skills/$skill/SKILL.md: a ‘compact‘ line still ends the turn on ‘Auto run: compacting‘. | DELETE | inside loop 26-53 over 2 skills (subagent-driven-development, executing-plans): same phrase, run twice |
| 37 | $skill: no handoff rule at the final check | got: $(grep -c "Auto run section's \‘handoff\‘" "$F")  want: 0 | DELETE | inside loop 26-53 over 2 skills (subagent-driven-development, executing-plans): same phrase, run twice |
| 38 | $skill: blocked goes to Fable | skills/$skill/SKILL.md: ‘BLOCKED‘ goes on the pending list and one Fable batch runs at once | DELETE | inside loop 26-53 over 2 skills (subagent-driven-development, executing-plans): same phrase, run twice |
| 39 | $skill: the deferred line | skills/$skill/SKILL.md: Task <N>: complete (deferred by the auto run) | DELETE | inside loop 26-53 over 2 skills (subagent-driven-development, executing-plans): same phrase, run twice |
| 40 | $skill: dependents are deferred too | skills/$skill/SKILL.md: and every task that depends on it | DELETE | inside loop 26-53 over 2 skills (subagent-driven-development, executing-plans): same phrase, run twice |
| 41 | $skill: never performed | skills/$skill/SKILL.md: irreversible, security-sensitive or outside-the-worktree action is never | DELETE | inside loop 26-53 over 2 skills (subagent-driven-development, executing-plans): same phrase, run twice |
| 46 | $skill: each task resets the count | skills/$skill/SKILL.md: $after | DELETE | distinct phrase per skill (2 phrases); counts as 2 assertions |
| 47 | $skill: compact ends the turn | skills/$skill/SKILL.md: ‘Auto run: compacting‘ as its last line | KEEP(turn-end.sh; format contract) | turn-end.sh / cockpit lib.ts end an auto-run turn only on the `Auto run: compacting\|clearing\|switching` sentinel (scripts/turn-end.sh:104) |
| 48 | $skill: the step owns the clear | skills/$skill/SKILL.md: then run ‘scripts/auto-run clear‘ and end as auto-run.md §Clears says | DELETE | inside loop 26-53 over 2 skills (subagent-driven-development, executing-plans): same phrase, run twice |
| 49 | $skill: a handoff line waits for the task in flight | skills/$skill/SKILL.md: On ‘handoff‘, finish the task in | DELETE | inside loop 26-53 over 2 skills (subagent-driven-development, executing-plans): same phrase, run twice |
| 50 | $skill: the finish and the consented early CI are the outsi… | skills/$skill/SKILL.md: (the finish action and the consented Early CI push and dispatch are the exceptio… | DELETE | inside loop 26-53 over 2 skills (subagent-driven-development, executing-plans): same phrase, run twice |
| 51 | $skill: final review | skills/$skill/SKILL.md: run ‘scripts/auto-run phase final‘ | DELETE | inside loop 26-53 over 2 skills (subagent-driven-development, executing-plans): same phrase, run twice |
| 52 | $skill: the four stops give way | skills/$skill/SKILL.md: except in an auto run | DELETE | inside loop 26-53 over 2 skills (subagent-driven-development, executing-plans): same phrase, run twice |
| 54 | subagent-driven-development: a deferred task is not merged | skills/subagent-driven-development/SKILL.md: a deferred task's branch is | DELETE |  |
| 56 | executing-plans: step 7 runs task-complete | $EPF: auto run, run ‘scripts/auto-run task-complete‘, then the Fable batch when | DELETE |  |
| 57 | executing-plans: step 8 moves to the final phase | $EPF: ‘scripts/context-size --final‘; in an auto run it moves the run to the | DELETE |  |
| 58 | executing-plans: the budget section says so too | $EPF: Finishing is never budget-checked. In an auto run ‘--final‘ also moves the | DELETE |  |
| 59 | subagent-driven-development: the budget section says so | skills/subagent-driven-development/references/budget.md: from the ledger. In an auto run ‘--final‘ also … | DELETE |  |
| 60 | executing-plans: a task at its cap goes on the pending list | $EPF: In an auto run it goes on the pending list, as an exhausted ladder does. | DELETE |  |
| 61 | executing-plans: recovery sends an old switch to subagent m… | $EPF: \| ‘escalated inline -> subagent‘ \| This plan has left inline mode: use dforge:subagent-driven-de… | DELETE |  |
| 62 | delegated-task.md: task-complete after the complete line | reference/delegated-task.md: In an auto run, run ‘scripts/auto-run task-complete‘, then the Fable batch … | DELETE |  |
| 63 | parallel-waves.md: task-complete after the merge | reference/parallel-waves.md: ‘; merged <sha7>‘. In an auto run, run ‘scripts/auto-run task-complete‘ | DELETE |  |
| 64 | parallel-waves.md: before any budget check | reference/parallel-waves.md: right after it, before any budget check or dispatch; the Fable batch runs | DELETE |  |
| 65 | handoff: no mode switch clears by phase | got: $(grep -c 'clear --phase' "$P/skills/handoff/SKILL.md")  want: 0 | DELETE |  |
| 68 | auto-run.md: an unwritten handoff stops the run | reference/auto-run.md: If ‘scripts/next-step‘ exits 4, do not run ‘scripts/auto-run clear‘ | DELETE |  |
| 69 | auto-run.md: Stopping lists it | reference/auto-run.md: ‘scripts/next-step‘ exits 4 during a clear (see Clears). | DELETE |  |
| 70 | auto-run.md: a deferred task keeps the branch | reference/auto-run.md: also keeps the branch when the ledger holds a | DELETE |  |
| 71 | finishing: a deferred task keeps the branch | skills/finishing-a-development-branch/SKILL.md: ‘merge‘ keeps when the ledger holds a | DELETE |  |
| 72 | auto-run.md: the critic runs before Fable | reference/auto-run.md: After your own self-review round and the architecture critic | DELETE |  |
| 73 | auto-run.md: a late statement goes up the ladder | reference/auto-run.md: is never asked: it goes up the ladder under Rulings | DELETE |  |
| 74 | auto-run.md: an undecided critic Blocker | reference/auto-run.md: --note "critic Blocker unresolved" | DELETE |  |
| 75 | auto-run.md: a statement is deferred, not guessed | reference/auto-run.md: **An acceptance statement in the spec phase:** the statement is deferred, not | DELETE |  |
| 76 | auto-run.md: QA ambiguity is parked | reference/auto-run.md: **A QA ‘acceptance-ambiguous‘ item:** PARK it | DELETE |  |
| 77 | auto-run.md: QA ambiguity batches at once | reference/auto-run.md: A batch runs at once for a blocked task and for a QA | DELETE |  |
| 78 | auto-run.md: a critic Blocker takes its own note | reference/auto-run.md: it leaves undecided or without a suggestion to the run's register, except a | DELETE |  |
| 79 | auto-run.md: unverified acceptance keeps the branch | reference/auto-run.md: ‘merge‘ also keeps the branch when the ‘Acceptance QA: complete‘ line reports a n… | DELETE |  |
| 80 | auto-run.md: an untested statement keeps the branch | reference/auto-run.md: ‘cannot-test‘, or when the run added a deferred register row | DELETE |  |
| 81 | auto-run.md: fail and flaky counts are not read | reference/auto-run.md: at it. The line's ‘fail‘ and ‘flaky‘ counts are not read: they are taken | DELETE |  |
| 82 | auto-run.md: a deferred statement or unresolved Blocker kee… | reference/auto-run.md: whose Item begins ‘A<n>:‘ or whose Note is ‘critic Blocker unresolved‘ | DELETE |  |
| 83 | auto-run.md: the final message lists demos and lenses | reference/auto-run.md: every ‘demo‘ statement of the spec, every lens | DELETE |  |
| 85 | finishing: unverified acceptance keeps the branch | $FIN: ‘merge‘ also keeps when the ‘Acceptance QA: complete‘ line reports a nonzero count of | DELETE |  |
| 86 | finishing: an untested statement keeps the branch | $FIN: ‘cannot-test‘, or when the run added a deferred register | DELETE |  |
| 88-89 | $(basename "$f"): a fixed QA failure does not keep the bran… | got: $(grep -qF -- 'nonzero count of' "$f" && grep -A1 -F -- 'nonzero count of' "$f" \| grep -qF -- '‘fa… | DELETE | loop 87-90 over auto-run.md and finishing SKILL |
| 91 | finishing: a deferred statement or unresolved Blocker keeps… | $FIN: row whose Item begins ‘A<n>:‘ or whose Note is ‘critic Blocker unresolved‘. | DELETE |  |
| 92 | finishing: the final message lists demos and lenses | $FIN: every ‘demo‘ statement of the spec, every lens | DELETE |  |
| 93 | finishing: every lens-skipped line is read, whatever its re… | $FIN: a ‘final review lens-skipped <id> reason=<reason>‘ ledger line names, | DELETE |  |
| 94 | finishing: no lens-skipped line is read for reason=cap alone | got: $(grep -c 'lens-skipped <id> reason=cap' "$FIN")  want: 0 | DELETE |  |
| 95 | finishing: light lists the unverified test statements | $FIN: every ‘A<n>‘ statement tagged ‘test‘ under ‘not verified (depth light)‘ | DELETE |  |
| 96 | finishing: Step 3 lists them before the menu | $FIN: **Unverified at light depth.** When the ledger holds a ‘Review depth: light‘ | DELETE |  |
| 97 | finishing: a skipped QA line carries no counts | $FIN: An ‘Acceptance QA: skipped (depth light)‘ line carries no counts, so the | DELETE |  |
| 100 | auto-run.md: the default | reference/auto-run.md: The default on Claude Code (‘autoRun=on‘): once your human partner approves the | DELETE |  |
| 101 | auto-run.md: the switch section | reference/auto-run.md: ## The switch | DELETE |  |
| 102 | auto-run.md: the switching line | reference/auto-run.md: - ‘Auto run: switching‘ after ‘scripts/auto-run switch‘ exits 0. | KEEP(scripts/turn-end.sh; format contract) | same sentinel list (scripts/turn-end.sh:104) |
| 103 | auto-run.md: a saved plan goes through the switch | reference/auto-run.md: A saved plan moves through §The switch, where the cockpit runs the phase clear. | DELETE |  |
| 104 | auto-run.md: the switch clears the session | reference/auto-run.md: The cockpit then runs ‘scripts/auto-run clear --phase‘, clears the session and bi… | DELETE |  |
| 105 | auto-run.md: the switch's prompt has no after-compact lead | reference/auto-run.md: and submits the plan's first prompt. Follow it in the new session. | DELETE |  |
| 106 | auto-run.md: clears names the switch | reference/auto-run.md: **The switch** (§The switch): the cockpit runs ‘scripts/auto-run clear --phase‘ i… | DELETE |  |
| 107 | auto-run.md: no switch-resume | got: $(grep -c 'switch-resume' "$R")  want: 0 | DELETE |  |
| 108 | auto-run.md: no compacted --switch | got: $(grep -c 'compacted --switch' "$R")  want: 0 | DELETE |  |
| 109 | session-budget: the switch clears | reference/session-budget.md: no stop: the cockpit clears the session and starts execution | DELETE |  |
| 110 | handoff: the switch clears | skills/handoff/SKILL.md: only steps 0-3 below run, and the cockpit clears the session. | DELETE |  |
| 111 | readme: the switch clears | README.md: the cockpit clears the session and starts it on the plan's launch model | DELETE |  |
| 112 | auto-run.md: finishing reads the recorded choice | reference/auto-run.md: the choice ‘scripts/finish-choice get --plan PLAN_FILE‘ prints, which the spec | DELETE |  |
| 113 | auto-run.md: a spec-review deferral keeps a merge | reference/auto-run.md: deferred at the spec review, before the run started, counts as one the run | DELETE |  |
| 114 | auto-run.md: an old switch clears by phase | reference/auto-run.md: - **A plan that left inline mode before this change** (a ledger dforge:executing-… | DELETE |  |
| 115 | auto-run.md: the switch starts at Setup | reference/auto-run.md: execution skill starts at its Setup, workspace first: ‘scripts/auto-run status‘ | DELETE |  |
| 116 | auto-run.md: a listed launch is waited for | reference/auto-run.md: listed: run ‘scripts/in-flight‘, wait for or stop each launch it lists, and | DELETE |  |
| 117 | auto-run.md: a second exit 5 stops the run | reference/auto-run.md: ‘scripts/auto-run stop --reason "background work still running at the switch: <ne… | DELETE |  |
| 118 | auto-run.md: dependents come from the plan | reference/auto-run.md: ‘**Depends on:**‘ line names it, or, in a plan without those lines, a later | DELETE |  |
| 119 | auto-run.md: a final residual is a deferred row | reference/auto-run.md: ‘scripts/register add <run register> "<the finding>" --state deferred --note "fin… | DELETE |  |
| 120 | auto-run.md: a final residual keeps the branch | reference/auto-run.md: added. ‘merge‘ also keeps the branch when the run added a deferred row whose | DELETE |  |
| 121 | auto-run.md: a finish stops the run with no reason | reference/auto-run.md: stop‘ with no ‘--reason‘ before | DELETE |  |
| 122 | finishing: a finish stops the run with no reason | $FIN: stop‘ with no ‘--reason‘ before printing the next-step block | DELETE |  |
| 123 | final-review.md: a red gate in an auto run | reference/final-review.md: run ([auto-run.md](auto-run.md)), a red gate does not stop the review: the | DELETE |  |
| 124 | final-review.md: a second red stops the run | reference/final-review.md: ‘scripts/auto-run stop --reason "gate <name> red"‘ and ends as auto-run.md | DELETE |  |
| 126 | final-review.md: a manifest defect has its own reason | reference/final-review.md: a manifest defect does the same with the reason | DELETE |  |
| 127 | executing-plans: no mode switch clears by phase | got: $(grep -c 'clear --phase' "$EPF")  want: 0 | DELETE |  |
| 128 | using-git-worktrees: an auto run reads its state | skills/using-git-worktrees/SKILL.md: read the auto-run state (‘scripts/auto-run status‘), not the ‘workt… | DELETE |  |
| 129 | using-git-worktrees: the sandbox stops the run | skills/using-git-worktrees/SKILL.md: In an auto run under ‘isolation worktree‘, do not work in place: ru… | DELETE |  |
| 130 | using-git-worktrees: a red baseline is a ruling | skills/using-git-worktrees/SKILL.md: In an auto run, ask nothing: run ‘scripts/auto-run ruling add "Setu… | DELETE |  |
| 131 | finish-preference.md: get reads the spec line | reference/finish-preference.md: the plan's spec carries a ‘Finish: <merge\|pr\|keep>‘ line in ‘## Decisi… | DELETE |  |
| 132 | session-budget.md: the last task is never a stop | reference/session-budget.md: - **Never a stop:** the last task completing, in either mode. The final rev… | DELETE |  |
| 133 | finish-preference.md: the spec review's answer | reference/finish-preference.md: once the plan is attached. Finishing carries out that choice, or else | DELETE |  |
| 134 | README: the default | README.md: The default on Claude Code (‘autoRun=on‘). Brainstorming asks its clarifying | DELETE |  |
| 135 | README: the opt-outs | README.md: ‘autoRun=ask‘ offers the run once the design is approved instead, and | DELETE |  |
| 136 | README: the autoRun row | README.md: \| Workflow \| ‘autoRun‘ \| ‘on‘ \| | DELETE |  |
| 137 | README: the strategy row | README.md: \| Workflow \| ‘executionStrategy‘ \| ‘sequential‘ \| | DELETE |  |
| 139 | no prose names the code host 'the dforge' | got: $(grep -rlF "the dforge's" "$P/skills" "$P/reference" \| tr '\n' ' ')  want:  | DELETE | repo-wide absent-phrase lint over skills/ and reference/ |
| 146 | auto-run.md: the early CI push and dispatch are the second … | reference/auto-run.md: The finish action is the first exception. The second is the ‘**Early CI:**‘ push … | DELETE |  |
| 147 | delegated-task.md: the Early CI section | reference/delegated-task.md: ## Early CI | DELETE |  |
| 148 | delegated-task.md: without the line nothing pushes | reference/delegated-task.md: With no ‘**Early CI:**‘ line in the plan header, nothing in this loop pushe… | DELETE |  |
| 149 | delegated-task.md: consent gates the push | reference/delegated-task.md: Push only when the line carries ‘— consented <YYYY-MM-DD>‘. | DELETE |  |
| 150 | delegated-task.md: the task point | reference/delegated-task.md: For ‘after task <n>‘, run these steps right after the ‘Task <n>: complete‘ … | DELETE |  |
| 151 | delegated-task.md: the wave point | reference/delegated-task.md: For ‘after wave <k>‘, run them right after the ‘Wave <k>: integrated‘ or ‘W… | DELETE |  |
| 152 | delegated-task.md: the push | reference/delegated-task.md: Push the branch with ‘git push -u origin <branch>‘. | DELETE |  |
| 153 | delegated-task.md: only a feature branch is pushed | reference/delegated-task.md: push nothing and write ‘Early CI: skipped — <branch> is not a feature branc… | DELETE |  |
| 154 | delegated-task.md: dispatch only with workflow_dispatch | reference/delegated-task.md: Start CI with ‘gh workflow run <workflow> --ref <branch>‘ only when the wor… | DELETE |  |
| 155 | delegated-task.md: the workflow is the first dispatchable o… | reference/delegated-task.md: ‘<workflow>‘ is the first workflow file the plan's ‘**CI:**‘ line names tha… | DELETE |  |
| 156 | delegated-task.md: never a pull request | reference/delegated-task.md: Never open a pull request to start CI. | DELETE |  |
| 157 | delegated-task.md: run discovery | reference/delegated-task.md: Find the run with ‘gh run list --workflow <file> --branch <branch> --limit … | DELETE |  |
| 158 | delegated-task.md: the dispatched line | reference/delegated-task.md: Write ‘Early CI: dispatched run <id> at <sha7>‘ once the run is found. | DELETE |  |
| 159 | delegated-task.md: the background watch | reference/delegated-task.md: Run ‘gh run watch <id>‘ as a background Bash command, with the call's ‘time… | DELETE |  |
| 160 | delegated-task.md: the outcome lines | reference/delegated-task.md: When the watch ends, read ‘gh run view <id> --json conclusion,jobs‘ and wri… | DELETE |  |
| 161 | delegated-task.md: every watch outcome writes a line | reference/delegated-task.md: writes ‘Early CI: skipped — run <id> still running at 90 min‘. | DELETE |  |
| 162 | delegated-task.md: a git or gh failure is a skip | reference/delegated-task.md: Any failure of ‘git push‘ or ‘gh‘ prints one line, writes ‘Early CI: skippe… | DELETE |  |
| 163 | delegated-task.md: a red run is a fix bullet | reference/delegated-task.md: A red run is a bullet you write into the next task's fix file, as §4 does f… | DELETE |  |
| 164 | delegated-task.md: a red run with no task left | reference/delegated-task.md: With no task left, a red run is a final-review finding, debugged with dforg… | DELETE |  |
| 165 | delegated-task.md: recovery | reference/delegated-task.md: On recovery, a ‘dispatched‘ line with no ‘green‘, ‘red‘ or ‘skipped‘ line a… | DELETE |  |
| 167 | ledger.md: the grammar holds $line | skills/subagent-driven-development/references/ledger.md: $line | DELETE | loop 166-168 over 5 phrases; counts as 5 assertions |
| 170 | ledger.md: an unfinished early CI run is resumed first | skills/subagent-driven-development/references/ledger.md: Whatever the task lines say, a ledger that hold… | DELETE |  |
| 171 | recovery.md: an unfinished early CI run is resumed first | skills/executing-plans/references/recovery.md: Whatever the task lines say, a ledger that holds an ‘Earl… | DELETE |  |
| 172 | subagent-driven-development: Early CI runs at the point the… | skills/subagent-driven-development/SKILL.md: When the plan header has an ‘**Early CI:**‘ line, run [dele… | DELETE |  |
| 173 | executing-plans: step 7 runs Early CI | $EPF: run [delegated-task.md](../../reference/delegated-task.md) §Early CI when the header's ‘**Early CI… | DELETE |  |
| 177 | delegated-task.md: no step outside Early CI pushes the bran… | got: $(outside "$D" \| grep -cE 'git push\|gh workflow run\|gh run ')  want: 0 | DELETE | helper outside() (176) used only here |
| 178 | subagent-driven-development: nothing in the skill pushes th… | got: $(grep -cE 'git push\|gh workflow run\|gh run ' "$SDDF")  want: 0 | DELETE | absent-phrase pin |

### auto-run-worktree-setting-qa.acceptance.test.sh

DELETE 46, KEEP direct 0, KEEP format contract 0, borderline 0 (borderline rows are in section 3).

| line(s) | test label | markdown file: phrase pinned | verdict | note |
|---|---|---|---|---|
| 332 | A13: the auto-run paragraph exists | got: $([ -n "$body" ] && echo yes \|\| echo no)  want: yes | DELETE | t_A13: reads using-git-worktrees SKILL text |
| 333 | A13: reads the run's state with scripts/auto-run status | got: $(has "$body" 'scripts/auto-run status')  want: yes | DELETE | t_A13: reads using-git-worktrees SKILL text |
| 334 | A13: not the worktree setting | got: $(has "$body" 'not the ‘worktree‘ setting')  want: yes | DELETE | t_A13: reads using-git-worktrees SKILL text |
| 335 | A13: done before the linked-worktree check, in any checkout | got: $(has "$body" 'before the linked-worktree check')$(has "$body" 'in any checkout')  want: yesyes | DELETE | t_A13: reads using-git-worktrees SKILL text |
| 336 | A13: switches to a recorded branch when HEAD is elsewhere | got: $(has "$body" 'branch <name>')$(has "$body" 'git switch <name>')  want: yesyes | DELETE | t_A13: reads using-git-worktrees SKILL text |
| 337 | A13: creates auto/<plan slug> with git switch -c | got: $(has "$body" 'git switch -c auto/<plan slug>')  want: yes | DELETE | t_A13: reads using-git-worktrees SKILL text |
| 338 | A13: with a collision suffix | got: $(has "$body" '-2')  want: yes | DELETE | t_A13: reads using-git-worktrees SKILL text |
| 339 | A13: HEAD is the base or detached | got: $(has "$body" 'the run'"'"'s base')$(has "$body" 'detached')  want: yesyes | DELETE | t_A13: reads using-git-worktrees SKILL text |
| 340 | A13: under in-place, or in a linked worktree | got: $(has "$body" 'isolation in-place')$(has "$body" 'linked worktree')  want: yesyes | DELETE | t_A13: reads using-git-worktrees SKILL text |
| 341 | A13: calls setup-branch | got: $(has "$body" 'scripts/auto-run setup-branch <name>')  want: yes | DELETE | t_A13: reads using-git-worktrees SKILL text |
| 342 | A13: stops the run on staged changes | got: $(has "$body" 'staged changes in this checkout: <paths>')$(has "$body" 'scripts/auto-run stop --rea… | DELETE | t_A13: reads using-git-worktrees SKILL text |
| 343-344 | A13: creates the worktree without asking under worktree in … | got: $(has "$body" 'Under ‘isolation worktree‘ in the primary checkout, create the worktree without aski… | DELETE | t_A13: reads using-git-worktrees SKILL text |
| 351 | A14: step 5 asks the worktree question only when the worktr… | got: $(has "$s5" 'when the ‘worktree‘ setting is ‘ask‘')  want: yes | DELETE | t_A14: reads auto-by-default.md / auto-run-offer.md text |
| 352-353 | A14: the question offers the isolated worktree and the in-p… | got: $(has "$s5" '**Isolated worktree (Recommended)**')$(has "$s5" '**Work in place on a new branch')  w… | DELETE | t_A14: reads auto-by-default.md / auto-run-offer.md text |
| 354 | A14: asked in the last call, beside the approval question | got: $(has "$s5" 'in the last call')$(has "$s5" 'beside the approval question')  want: yesyes | DELETE | t_A14: reads auto-by-default.md / auto-run-offer.md text |
| 355 | A14: the question comes before the approval options in the … | got: $(before_in "$s5" 'Worktree: <worktree\|in-place>' '**Approve and run unattended**')  want: yes | DELETE | t_A14: reads auto-by-default.md / auto-run-offer.md text |
| 356 | A14: the answer is a Worktree: <worktree\|in-place> line in… | got: $(has "$s5" '‘Worktree: <worktree\|in-place>‘ line in ‘## Decisions‘')  want: yes | DELETE | t_A14: reads auto-by-default.md / auto-run-offer.md text |
| 357 | A14: step 6 passes --isolation | got: $(has "$s6" '--isolation <worktree\|in-place>')  want: yes | DELETE | t_A14: reads auto-by-default.md / auto-run-offer.md text |
| 358-359 | A14: step 6 takes the value from the line under ask, and fr… | got: $(has "$s6" 'under ‘ask‘')$(has "$s6" '‘worktree‘ under ‘always‘')$(has "$s6" '‘in-place‘ under ‘ne… | DELETE | t_A14: reads auto-by-default.md / auto-run-offer.md text |
| 362 | A14: the offer keeps its two options by default | got: $(has "$off" '1. Yes, run unattended')$(has "$off" '2. No, keep the normal stops')  want: yesyes | DELETE | t_A14: reads auto-by-default.md / auto-run-offer.md text |
| 363-364 | A14: under worktree=ask the offer has three options | got: $(has "$off" 'When the ‘worktree‘ setting is ‘ask‘')$(has "$off" '1. Yes, in an isolated worktree')… | DELETE | t_A14: reads auto-by-default.md / auto-run-offer.md text |
| 365 | A14: the offer passes --isolation, in-place for option 2 | got: $(has "$off" 'scripts/auto-run start --spec')$(has "$off" '--isolation <worktree\|in-place>')$(has … | DELETE | t_A14: reads auto-by-default.md / auto-run-offer.md text |
| 375 | A15: no skill or reference text says an auto run creates th… | got: $hits  want:  | DELETE | t_A15: scans every skills/reference md, README and config/schema.mjs for phrases |
| 376 | A15: the corrected paragraph says what never does | got: $(txt skills/using-git-worktrees/SKILL.md \| grep -c 'worktree=never‘ works in place')  want: 1 | DELETE | t_A15: scans every skills/reference md, README and config/schema.mjs for phrases |
| 377 | A15: the README says an in-place auto run for never | got: $(txt README.md \| grep -c '‘never‘ works in this checkout')  want: 1 | DELETE | t_A15: scans every skills/reference md, README and config/schema.mjs for phrases |
| 383 | A16: executor-lane.md refuses the primary checkout for the … | got: $(has "$lane" 'Refuse the primary checkout')  want: yes | DELETE | t_A16: reads executor-lane.md / auto-run-plan.md text |
| 384 | A16: runs task-step start first | got: $(has "$lane" 'run ‘task-step start‘')  want: yes | DELETE | t_A16: reads executor-lane.md / auto-run-plan.md text |
| 385 | A16: then neither the gate nor the wrapper, and the session… | got: $(has "$lane" 'neither the gate nor the wrapper')$(has "$lane" 'session review loop')  want: yesyes | DELETE | t_A16: reads executor-lane.md / auto-run-plan.md text |
| 386 | A16: task-step start comes before the neither-gate-nor-wrap… | got: $(before_in "$lane" 'task-step start' 'neither the gate nor the wrapper')  want: yes | DELETE | t_A16: reads executor-lane.md / auto-run-plan.md text |
| 387 | A16: records the executor unavailable line | got: $(has "$lane" 'Task <N>: implementer inline (assigned; base <sha7>; executor <id> unavailable - no … | DELETE | t_A16: reads executor-lane.md / auto-run-plan.md text |
| 388 | A16: continuing in the primary checkout is limited to workt… | got: $(txt reference/executor-lane.md \| grep -c 'In a worktree run the user can continue in the primary… | DELETE | t_A16: reads executor-lane.md / auto-run-plan.md text |
| 389-390 | A16: no other line lets the user continue in the primary ch… | got: $(txt reference/executor-lane.md \| grep -i 'user can continue in the primary checkout' \| grep -vc… | DELETE | t_A16: reads executor-lane.md / auto-run-plan.md text |
| 392 | A16: auto-run-plan.md ticks no executor when isolation is i… | got: $(has "$plan" 'tick nothing when ‘scripts/auto-run status‘ prints ‘isolation in-place‘')  want: yes | DELETE | t_A16: reads executor-lane.md / auto-run-plan.md text |
| 398 | A17: recovery.md's commit-anything-uncommitted excludes the… | got: $(has "$rec" 'except the carried paths')  want: yes | DELETE | t_A17: reads recovery.md / final-review.md / setup.md and greps md for `git add -A` |
| 399 | A17: recovery.md says it once per row that has it | got: $(printf '%s\n' "$rec" \| grep -c .):$(printf '%s\n' "$rec" \| grep -c 'carried')  want: 1:1 | DELETE | t_A17: reads recovery.md / final-review.md / setup.md and greps md for `git add -A` |
| 402 | A17: final-review.md has QA timeout cleanup sites | got: $([ "$nclean" -ge 1 ] && echo yes \|\| echo no)  want: yes | DELETE | t_A17: reads recovery.md / final-review.md / setup.md and greps md for `git add -A` |
| 403 | A17: every QA timeout cleanup site excludes carried paths | got: $nnever  want: $nclean | DELETE | t_A17: reads recovery.md / final-review.md / setup.md and greps md for `git add -A` |
| 405 | A17: executing-plans Setup states by-name staging | got: $(has "$setup" 'stage the paths it changed by name')$(has "$setup" 'never ‘git add -A‘ or ‘git add … | DELETE | t_A17: reads recovery.md / final-review.md / setup.md and greps md for `git add -A` |
| 407 | A17: no Setup or task-loop text stages with git add -A or g… | got: $viol  want:  | DELETE | t_A17: reads recovery.md / final-review.md / setup.md and greps md for `git add -A` |
| 413 | A18: the unattended-finish stop list names a refused checko… | got: $(has "$stops" 'a refused checkout, pull or merge of the base')  want: yes | DELETE | t_A18: reads finishing SKILL text |
| 414 | A18: and stops the run with scripts/auto-run stop | got: $(has "$stops" 'scripts/auto-run stop --reason')  want: yes | DELETE | t_A18: reads finishing SKILL text |
| 416-417 | A18: in place, pr and keep end with the branch line | got: $(has "$inplace" '‘pr‘ and ‘keep‘')$(has "$inplace" 'This checkout is on ‘auto/<slug>‘; your uncomm… | DELETE | t_A18: reads finishing SKILL text |
| 423 | A19: step 2 covers an auto run whose status names a recorde… | got: $(has "$step2" 'In an auto run whose ‘scripts/auto-run status‘ names ‘branch <name>‘')  want: yes | DELETE | t_A19: reads resume-execution SKILL text |
| 424-425 | A19: a vanished branch stops the run with the reason and as… | got: $(has "$step2" '‘git branch --list <name>‘ prints nothing')$(has "$step2" 'scripts/auto-run stop --… | DELETE | t_A19: reads resume-execution SKILL text |
| 426 | A19: a HEAD that is elsewhere is switched back with git swi… | got: $(has "$step2" 'When HEAD is not on it, run ‘git switch <name>‘')  want: yes | DELETE | t_A19: reads resume-execution SKILL text |
| 427 | A19: a refused switch stops the run the same way | got: $(has "$step2" 'a refused switch stops the run the same way')  want: yes | DELETE | t_A19: reads resume-execution SKILL text |

### auto-run-worktree-setting.acceptance.test.sh

DELETE 53, KEEP direct 0, KEEP format contract 0, borderline 1 (borderline rows are in section 3).

| line(s) | test label | markdown file: phrase pinned | verdict | note |
|---|---|---|---|---|
| 231 | A13: Step 0 reads the run state | skills/using-git-worktrees/SKILL.md: read the auto-run state (‘scripts/auto-run status‘), not the ‘workt… | DELETE |  |
| 232 | A13: a recorded branch is switched back to | skills/using-git-worktrees/SKILL.md: When the status names ‘branch <name>‘, switch to that branch | DELETE |  |
| 233 | A13: a base or detached HEAD gets the run's branch | skills/using-git-worktrees/SKILL.md: ‘git switch -c auto/<plan slug>‘ | DELETE |  |
| 234 | A13: setup-branch records it | skills/using-git-worktrees/SKILL.md: ‘scripts/auto-run setup-branch <name>‘ | DELETE |  |
| 235 | A13: staged changes stop the run | skills/using-git-worktrees/SKILL.md: staged changes in this checkout: <paths> | DELETE | the message is printed by scripts/auto-run (script output is asserted at 112); this pins the skill sentence |
| 236 | A13: a worktree run in the primary checkout creates it unas… | skills/using-git-worktrees/SKILL.md: Under ‘isolation worktree‘ in the primary checkout, create the work… | DELETE |  |
| 237-238 | A15: no skill says never creates the worktree in an auto run | got: $(grep -rlF -- '‘worktree=never‘ creates' "$P/skills" "$P/reference" \| wc -l \| tr -d ' ')  want: 0 | DELETE | grep -rlF absent-phrase over skills/ and reference/ |
| 240 | A19: resume switches back to the run's branch | skills/resume-execution/SKILL.md: When HEAD is not on it, run ‘git switch <name>‘ | DELETE |  |
| 241 | A19: a gone branch stops the run | skills/resume-execution/SKILL.md: the run's branch <name> is gone | DELETE |  |
| 242 | A19: no EnterWorktree into the primary checkout | skills/resume-execution/SKILL.md: Skip EnterWorktree when the recorded workspace is the primary checkout | DELETE |  |
| 243 | A19: auto-run.md lists the stop | reference/auto-run.md: the run's branch is gone | DELETE |  |
| 244 | auto-run.md: the worktree consent is asked under ask | reference/auto-run.md: the worktree consent (asked at the spec review under ‘worktree=ask‘) | DELETE |  |
| 246 | $(basename "$(dirname "$f")")/$(basename "$f"): no executio… | $f: from the execution worktree | DELETE | loop 245-248 over 3 files (absent) |
| 247 | $(basename "$(dirname "$f")")/$(basename "$f"): side effect… | $f: outside the execution workspace | DELETE | loop 245-248 over 3 files |
| 249 | executing-plans: Setup runs from the workspace | skills/executing-plans/SKILL.md: from the execution workspace | DELETE |  |
| 250 | executing-plans: exit 4 points at Step 0 | skills/executing-plans/SKILL.md: follow dforge:using-git-worktrees Step 0 for the run, then run the comm… | DELETE |  |
| 251 | subagent-driven-development: exit 4 points at Step 0 | skills/subagent-driven-development/SKILL.md: follow dforge:using-git-worktrees Step 0 for the run, then … | DELETE |  |
| 253 | $(basename "$(dirname "$f")"): exit 5 names every stop | $f: on the run base, off its branch or in the primary checkout, or a carried path was committed | DELETE | loop 252-254 over 2 skills |
| 255 | auto-run.md: the switch starts at Setup, workspace first | reference/auto-run.md: execution skill starts at its Setup, workspace first: ‘scripts/auto-run status‘ | DELETE |  |
| 259 | A16: the lane falls back in the primary checkout | reference/executor-lane.md: executor <id> unavailable - no linked worktree | DELETE |  |
| 260 | A16: after the plain task-step start | reference/executor-lane.md: run ‘task-step start‘ as the executor path does | DELETE |  |
| 261 | A16: users keep the primary checkout only in worktree runs | reference/executor-lane.md: In a worktree run the user can continue in the primary checkout | DELETE |  |
| 262 | A16: the auto-run offer ticks nothing in place | skills/writing-plans/references/auto-run-plan.md: tick nothing when ‘scripts/auto-run status‘ prints ‘is… | DELETE |  |
| 263 | A17: recovery leaves carried paths uncommitted | skills/executing-plans/references/recovery.md: commit anything uncommitted except the carried paths (‘sc… | DELETE |  |
| 264 | A17: QA cleanup never touches a carried path | reference/final-review.md: Never restore or delete a carried path (‘scripts/auto-run carried‘) | DELETE |  |
| 265 | A17: tasks stage by name | skills/executing-plans/references/setup.md: stage the paths it changed by name, never ‘git add -A‘ or ‘g… | DELETE |  |
| 269 | A17: no auto-run setup or task-loop text stages everything | got: $stray  want: 0 | DELETE | grep -E over concatenated skill text for `git add -A` (check spans 266-269) |
| 270 | executing-plans: a carried commit at phase final stops the … | skills/executing-plans/SKILL.md: is a carried path and was committed | DELETE |  |
| 271 | subagent-driven-development: a carried commit at phase fina… | skills/subagent-driven-development/SKILL.md: is a carried path and was committed | DELETE |  |
| 273 | executing-plans: the git-error refusal has its own stop rea… | skills/executing-plans/SKILL.md: $git_error_reason | DELETE |  |
| 274 | subagent-driven-development: both exit-4 lines give the git… | got: $(grep -cF "$git_error_reason" "$P/skills/subagent-driven-development/SKILL.md")  want: 2 | DELETE | grep -cF count of a sentence |
| 276 | A18: the git-error refusal of phase finish has its own stop… | skills/finishing-a-development-branch/SKILL.md: $git_error_reason | DELETE |  |
| 277 | A18: the stop list names checkout, pull and merge | skills/finishing-a-development-branch/SKILL.md: a refused checkout, pull or merge of the base | DELETE |  |
| 278 | A18: phase finish refusal stops the run | skills/finishing-a-development-branch/SKILL.md: is a carried path and was committed | DELETE |  |
| 279 | A18: a red merged suite lists the carried paths | skills/finishing-a-development-branch/SKILL.md: list the carried paths (‘scripts/auto-run carried‘) with… | DELETE |  |
| 280 | A18: pr and keep name the branch | skills/finishing-a-development-branch/SKILL.md: This checkout is on ‘auto/<slug>‘; your uncommitted chan… | DELETE |  |
| 284 | A14: the spec review asks under ask only | skills/brainstorming/references/auto-by-default.md: when the ‘worktree‘ setting is ‘ask‘ | DELETE |  |
| 285 | A14: in the last call beside the approval | skills/brainstorming/references/auto-by-default.md: in the last call, beside the approval question | DELETE |  |
| 286 | A14: the worktree option | skills/brainstorming/references/auto-by-default.md: **Isolated worktree (Recommended)** | DELETE |  |
| 287 | A14: the in-place option | skills/brainstorming/references/auto-by-default.md: **Work in place on a new branch — leave this checkou… | DELETE |  |
| 288 | A14: the Decisions line | skills/brainstorming/references/auto-by-default.md: ‘Worktree: <worktree\|in-place>‘ | DELETE | spec Decisions line `Worktree:` is read by an LLM; no script parses it |
| 289 | A14: step 6 passes the isolation | skills/brainstorming/references/auto-by-default.md: passes ‘--isolation <worktree\|in-place>‘ | DELETE |  |
| 291 | A14: offer option 1 | skills/brainstorming/references/auto-run-offer.md: 1. Yes, in an isolated worktree | DELETE |  |
| 292 | A14: offer option 2 | skills/brainstorming/references/auto-run-offer.md: 2. Yes, in place on a new branch (leave this checkout… | DELETE |  |
| 293 | A14: offer option 3 | skills/brainstorming/references/auto-run-offer.md: 3. No, keep the normal stops | DELETE |  |
| 294 | A14: the offer passes in-place | skills/brainstorming/references/auto-run-offer.md: --isolation in-place | DELETE |  |
| 295 | auto-run.md: start names the flag | reference/auto-run.md: --isolation <worktree\|in-place> | DELETE |  |
| 299 | README: auto runs follow the worktree setting | README.md: An auto run follows the ‘worktree‘ setting | DELETE |  |
| 377 | waves: an in-place run's plan is sequential | skills/writing-plans/references/auto-run-plan.md: In place, write ‘sequential‘ whatever the spec says | DELETE |  |
| 378 | waves: exit 3 never stashes a carried path | reference/parallel-waves.md: never stash a carried path | DELETE |  |
| 379 | Step 0: no branch and HEAD off the base stops the run | skills/using-git-worktrees/SKILL.md: With no branch recorded and HEAD on a branch other than the run's b… | DELETE |  |
| 380 | Step 0: a staged-changes refusal returns HEAD | skills/using-git-worktrees/SKILL.md: run ‘git checkout -‘ and ‘git branch -d <name>‘ | DELETE |  |
| 381 | resume: HEAD is checked in the recorded workspace | skills/resume-execution/SKILL.md: after step 3 has entered it when that is a linked worktree | DELETE |  |

### auto-run.test.sh

No wording pin. Every assertion runs a script and checks its output, exit status or state file, or checks the test-suite hygiene of other test files. (See section 3.)

### budget-line.test.sh

DELETE 2, KEEP direct 0, KEEP format contract 0, borderline 0 (borderline rows are in section 3).

| line(s) | test label | markdown file: phrase pinned | verdict | note |
|---|---|---|---|---|
| 311 | task reviewer: may open a left-out file | got: $(grep -c 'named on a ‘Left out:‘ line' "$P/skills/subagent-driven-development/references/task-revi… | DELETE | task-reviewer-prompt.md sentence about a `Left out:` line; review-package prints that line, no script reads the prompt sentence |
| 312 | group reviewer: may open a left-out file | got: $(grep -c 'named on a ‘Left out:‘ line' "$P/skills/subagent-driven-development/references/group-rev… | DELETE | same for group-reviewer-prompt.md |

### inline-mode.test.sh

DELETE 133, KEEP direct 0, KEEP format contract 19, borderline 1 (borderline rows are in section 3).

| line(s) | test label | markdown file: phrase pinned | verdict | note |
|---|---|---|---|---|
| 52 | calls $s | $INLINE: $s | DELETE | loop 51-53 over 6 script names mentioned in the skill; counts as 6 assertions |
| 57 | names handoff | $INLINE: dforge:handoff | DELETE |  |
| 58 | names finishing | $INLINE: dforge:finishing-a-development-branch | DELETE |  |
| 62-63 | opens with After compaction | got: $(grep -m 1 '^## ' "$INLINE")  want: ## After compaction | DELETE | heading-order pin on the skill view |
| 66 | links the shared final review | $INLINE: ../../reference/final-review.md | DELETE | link text |
| 67 | links the ruling prompt | $INLINE: ../subagent-driven-development/references/ruling-prompt.md | DELETE | link text |
| 76 | final review links the code reviewer | reference/final-review.md: ../skills/requesting-code-review/references/code-reviewer.md | DELETE | link text (not a resolver; 77-78 existence checks stay) |
| 79 | final review links the external executor | reference/final-review.md: executor-lane.md | DELETE | link text |
| 82 | final review links the re-review prompt | reference/final-review.md: ../skills/subagent-driven-development/references/re-review-prompt.md | DELETE | link text |
| 87-88 | drops the upstream subagent-availability note | $INLINE: works much better with access to subagents | DELETE |  |
| 92 | claims the $k kind | $INLINE: \‘$k\‘ | DELETE | loop 91-93 over 3 kind names; counts as 3 assertions |
| 97 | inline mode routes the executor empty-diff kind | $INLINE: executor-empty-diff | DELETE |  |
| 98 | inline mode no longer says it never runs an external execut… | $INLINE: no external executor | DELETE |  |
| 100 | claims the $k kind for delegated work | $INLINE: \‘$k\‘ | DELETE | loop 99-101 over 3 kind names; counts as 3 assertions |
| 102 | reads the Dispatch line | $INLINE: ‘**Dispatch:** delegated | DELETE |  |
| 103 | links the delegated loop | $INLINE: ../../reference/delegated-task.md | DELETE |  |
| 104 | a handoff waits for the task in flight | $INLINE: Never hand off in the middle of a task, | DELETE |  |
| 105 | subagent mode finishes the task before a handoff | $SDD_BUDGET: finish the task in flight — its reviews, fix rounds and | DELETE |  |
| 106 | subagent mode's last task is a soft stop | $SDD_BUDGET: continue to Final Review in this session | DELETE |  |
| 107 | a plan with heavy tasks gets a preflight | $INLINE: The ‘preflight‘ item runs when ‘plan-header.md‘ ends with a ‘**Heavy:**‘ line. | DELETE |  |
| 108 | the preflight no longer keys on a heavy Dispatch entry | $INLINE: naming at least one ‘(heavy)‘ task | DELETE |  |
| 109 | the kinds table no longer keys the preflight on any delegat… | $INLINE: when the plan delegates any task | DELETE |  |
| 110 | the preflight arises only for a heavy task | $INLINE: ‘preflight‘ arises only for a plan with a heavy task | DELETE |  |
| 111 | inline mode names only the executor delegation reason | $INLINE: ‘**Dispatch:** delegated — Task <a> (executor)‘ | DELETE |  |
| 112 | inline mode no longer delegates a heavy task | $INLINE: Task <a> (heavy) | DELETE |  |
| 113 | writing-plans no longer defines four-band tasks | <(cat "skills/writing-plans/SKILL.md" "skills/writing-plans/references/"*.md): four-band | DELETE |  |
| 114 | inline mode no longer delegates total-4 tasks | $INLINE: total-4 | DELETE |  |
| 115 | using-dforge no longer delegates total-4 tasks | skills/using-dforge/SKILL.md: total-4 | DELETE |  |
| 116 | README no longer delegates total-4 tasks | README.md: total-4 | DELETE |  |
| 117 | the delegated loop no longer delegates total-4 tasks | reference/delegated-task.md: total-4 | DELETE |  |
| 118 | inline routes the ruling seat | $INLINE: ‘scripts/review-route PLAN_FILE --ruling <kind> [<task> ...]‘ | DELETE |  |
| 119 | inline confirms a Header amendment | $INLINE: A Header amendment is confirmed by a second, independent ‘judge-opus‘ dispatch | DELETE |  |
| 120 | inline drops the no-preflight sentence | $INLINE: There is no pre-flight scan. | DELETE |  |
| 121 | inline no longer names judge-fable as the ruling seat | $INLINE: ‘dforge:judge-fable‘ (‘dforge:judge-opus‘ when Fable is | DELETE |  |
| 122 | inline no longer translates older plugin prefixes | $INLINE: translate a delegated task's \‘**Implementer:**\‘ agent before dispatching it | DELETE |  |
| 123 | inline drops the all-inert legacy sentence | $INLINE: no task is dispatched, so their names need no translation | DELETE |  |
| 124 | a task at its cap goes to the breaker, not to subagent mode | $INLINE: goes to the ruling seat as a ‘breaker‘ item (in an auto run, the | DELETE |  |
| 127 | states the fix cap | $INLINE: fix round R/3 | DELETE |  |
| 128 | inline no longer writes the escalation line | $INLINE: Task <N>: escalated inline -> subagent — <trigger> | DELETE |  |
| 129 | an owner request switches through the ledger line | $INLINE: ‘Task <N>: escalated inline -> subagent — owner request‘ | KEEP(scripts/lib/plan.sh; format contract) | scripts/lib/plan.sh ledger_left_inline and review-route parse `escalated inline -> subagent` ledger lines (review-route:172, plan.sh:383) |
| 130 | an owner request never edits the plan's Execution line | $INLINE: change the plan's Execution line | DELETE |  |
| 131 | inline recovery still reads an old escalation line | $INLINE: \| ‘escalated inline -> subagent‘ \| This plan has left inline mode | DELETE |  |
| 132 | subagent mode reads the escalation line | skills/subagent-driven-development/SKILL.md: escalated inline -> subagent | KEEP(script; format contract) | same parsers (ledger line token) |
| 134 | the inline recovery row ranks above both | $SDD_LEDGER: ranked strictly above both the task's \‘**Implementer:**\‘ agent and the inline session's r… | DELETE |  |
| 135 | escalation names the inline exit | skills/subagent-driven-development/references/escalation.md: ## Escalating out of inline mode | DELETE |  |
| 136 | escalation walks from the higher rung | skills/subagent-driven-development/references/escalation.md: dispatch its successor on the | DELETE |  |
| 137 | escalation gives the worked example | skills/subagent-driven-development/references/escalation.md: ‘impl-opus-high‘, not ‘impl-opus-low‘ | DELETE |  |
| 138 | escalation names the session rung | skills/subagent-driven-development/references/escalation.md: ‘impl-<model>-<effort>‘ (‘haiku‘ as ‘impl-h… | DELETE |  |
| 139 | an unavailable substitute ends in BLOCKED, not a loop | skills/subagent-driven-development/references/escalation.md: ‘Task <N>: BLOCKED — no available implement… | KEEP(scripts/next-step; format contract) | scripts/next-step parses `Task <N>: BLOCKED` ledger lines (next-step:488) |
| 140 | inline fix rounds record their outcome | $INLINE: passing \| still failing | DELETE |  |
| 141 | inline no longer marks the switch on a fix-round line | $INLINE: escalated inline -> subagent) | DELETE |  |
| 145 | inline ledger has: $line | $INLINE: $line | KEEP(next-step; format contract) | ledger grammar tokens: next-step:430 (`minor (deferred)`, `parked`, `Ruling:`), next-step:488 (`BLOCKED`), next-step:527 (`Final review: clean`), review-record:26 (`Review depth:`, `Acceptance QA: skipped`); loop 144-147 over 7 tokens, executing-plans skill view; counts as 7 assertions |
| 146 | subagent ledger has: $line | $SDD_LEDGER: $line | KEEP(script; format contract) | same 7 tokens against ledger.md; counts as 7 assertions |
| 150 | $s: a skipped QA line counts as complete on recovery | $f: Acceptance QA: skipped (depth light)‘ counts as ‘complete‘ on recovery. | DELETE |  |
| 151 | $s: the Review depth line is never recomputed | $f: and is read on recovery, never recomputed; it is | DELETE |  |
| 153 | $s: the ledger grammar block holds the line $line | got: $(grep -Fxc -- "$line" "$f")  want: 1 | KEEP(review-record; format contract) | review-record:26 REVIEW_LINES (`Review depth:`, `Acceptance QA: skipped`); loop 148-155 over 2 files x 2 lines (exact-line count in the ledger grammar block); counts as 2 assertions |
| 156 | inline marks an unreviewed completion | $INLINE: unreviewed | DELETE |  |
| 157 | inline assigns itself | $INLINE: implementer inline | DELETE |  |
| 160 | subagent mode links the shared final review | skills/subagent-driven-development/SKILL.md: final-review.md | DELETE |  |
| 161-162 | subagent mode no longer spells out the package call | skills/subagent-driven-development/SKILL.md: review-package PLAN_FILE MERGE_BASE HEAD | DELETE |  |
| 163-164 | inline mode does not spell out the package call | $INLINE: review-package PLAN_FILE MERGE_BASE HEAD | DELETE |  |
| 165-166 | the shared reference spells out the package call | reference/final-review.md: review-package PLAN_FILE MERGE_BASE HEAD | DELETE |  |
| 167 | the shared reference covers both modes | reference/final-review.md: Either execution mode | DELETE |  |
| 168 | final review routes the Claude seat | reference/final-review.md: ‘scripts/review-route PLAN_FILE --final‘ and dispatch | DELETE |  |
| 169 | final review drops the most capable model | reference/final-review.md: most capable | DELETE |  |
| 170 | final review routes the fix subagent | reference/final-review.md: ‘scripts/review-route PLAN_FILE --final-fix <file> [<file> ...]‘ | DELETE |  |
| 171 | final review ledgers the fix subagent | reference/final-review.md: ‘Final fix: implementer <agent> (assigned; base <sha7>)‘ | DELETE |  |
| 172 | subagent mode drops the most capable final seat | <(sdd_text): most capable available | DELETE |  |
| 173 | subagent mode drops the most capable final reviewer | <(sdd_text): final reviewer on the most capable model | DELETE |  |
| 174 | subagent ledger has the Final fix line | $SDD_LEDGER: Final fix: implementer <agent> (assigned; base <sha7>) | DELETE |  |
| 175 | subagent mode recovers a lost fix wave | $SDD_LEDGER: A ‘Final fix:‘ line and no ‘Final review:‘ line | DELETE |  |
| 176 | inline mode names the final seat | $INLINE: ‘scripts/review-route PLAN_FILE --final‘ prints | DELETE |  |
| 178 | README names the final seat | README.md: The final whole-branch review runs on ‘judge-opus‘ | DELETE |  |
| 184-185 | setup loads distilled constraints: $(basename "$(dirname "$… | $f: distilled/constraints.md | DELETE |  |
| 190 | final review runs gates first | reference/final-review.md: dforge:running-gates | DELETE |  |
| 191 | a red gate stops the review | reference/final-review.md: A red gate stops | DELETE |  |
| 196 | final review dedupes only two lists | reference/final-review.md: **Dedupe and verify, only with two lists.** | DELETE |  |
| 197 | final review names the one-list case | reference/final-review.md: **With one list** | DELETE |  |
| 198 | the fixer records rejections | reference/final-review.md: under ‘REJECTED: <finding>‘ | DELETE |  |
| 199 | disputed rejections go to the ruling seat | reference/final-review.md: ‘REJECTION DISPUTED‘ in the | DELETE |  |
| 200 | the re-review rules on rejections | skills/subagent-driven-development/references/re-review-prompt.md: REJECTION UPHELD \| | DELETE |  |
| 201 | an upheld rejection closes | skills/subagent-driven-development/references/re-review-prompt.md: An upheld rejection is closed; a disp… | DELETE |  |
| 202 | the Codex round rationale covers one list | reference/executor-lane.md: with one list the | DELETE |  |
| 203 | README drops the always-third-seat claim | README.md: which is why every finding goes through a third seat | DELETE |  |
| 210 | delegated loop heading: $h | got: $(grep -cxF -- "$h" "$DT")  want: 1 | DELETE | loop 208-211 over 8 headings of delegated-task.md; counts as 8 assertions |
| 214 | subagent mode no longer holds: $h | got: $(sdd_text \| grep -cxF -- "$h")  want: 0 | DELETE | loop 212-215 over 5 headings (absent from SDD text); counts as 5 assertions |
| 216 | subagent mode links the delegated loop | skills/subagent-driven-development/SKILL.md: ../../reference/delegated-task.md | DELETE |  |
| 217 | subagent mode defers per-task recovery | $SDD_LEDGER: Apply [delegated-task.md](../../../reference/delegated-task.md) §Recovery | DELETE |  |
| 225 | the delegated loop routes a Codex host's exit 2 | reference/delegated-task.md: the seat is a native judge at Astra high or above | DELETE |  |
| 226 | the delegated loop names the Codex escalation source | reference/delegated-task.md: come from the ‘codex-v4‘ selector | DELETE |  |
| 227 | the delegated loop handles a reply with no status | reference/delegated-task.md: **No status line:** | DELETE |  |
| 228 | a reply with no status is never DONE | reference/delegated-task.md: A reply without a status is not DONE | DELETE |  |
| 229 | no-status continuations are bounded | reference/delegated-task.md: After two continuations with no status | DELETE |  |
| 230 | a lost agent id means a fresh dispatch | reference/delegated-task.md: dispatch the same agent fresh with the brief path | DELETE |  |
| 231 | inline mode routes a Codex host's exit 2 | $INLINE: Codex host, where ‘review-route --ruling‘ exits 2 on every | DELETE |  |
| 232 | native Codex claims the exit 2 | reference/native-codex.md: ‘scripts/review-route‘ exits 2 for a task, a ruling or the final review on | DELETE |  |
| 233 | native Codex routes the plan-review cap | reference/native-codex.md: task's raw total (files+spec+coupling+risk, 0-6) under Claude's bands | DELETE |  |
| 234 | native Codex routes the final fix | reference/native-codex.md: rank 5 (‘gpt-6.1-sol / high‘) and capped at rank 9 (‘gpt-6-astra / xhigh‘) | DELETE |  |
| 235 | native Codex states plans carry no delegated task | reference/native-codex.md: A Codex plan therefore carries no delegated task | DELETE |  |
| 239 | the budget reference names the rollout source | reference/session-budget.md: source: rollout | DELETE |  |
| 240-241 | the budget reference states the Codex line carries no verdi… | reference/session-budget.md: measured — unknown | DELETE |  |
| 242 | the budget reference names the observations mode | reference/session-budget.md: --observations | DELETE |  |
| 243 | native Codex names the measured line | reference/native-codex.md: measured — unknown — source: rollout | DELETE |  |
| 244-245 | subagent mode no longer denies the Codex budget line | $SDD_BUDGET: On Codex there is no budget line | DELETE |  |
| 246-247 | inline mode no longer denies the Codex budget line | $INLINE: and there is no budget | DELETE |  |
| 248-249 | subagent mode names the measured Codex line | $SDD_BUDGET: carries a measured number but no verdict | DELETE |  |
| 250-251 | inline mode names the measured Codex line | $INLINE: carries a measured number but no verdict | DELETE |  |
| 252-253 | the handoff skill keeps the count rule authoritative | skills/handoff/SKILL.md: the measured number does not override it | DELETE |  |
| 365 | inline mode delegates every Executor line | $INLINE: A delegated task is one carrying an ‘**Executor:**‘ line | DELETE |  |
| 366 | writing-plans delegates every Executor line | skills/writing-plans/references/execution-line.md: A task carrying an ‘**Executor:**‘ line is delegated | DELETE |  |
| 367 | using-dforge delegates every Executor line | skills/using-dforge/SKILL.md: every task but those carrying an ‘**Executor:**‘ line | DELETE |  |
| 368 | README delegates every Executor line | README.md: exception is every task carrying an ‘**Executor:**‘ line | DELETE |  |
| 369 | the delegated loop delegates every Executor line | reference/delegated-task.md: ‘**Dispatch:** delegated‘: a task carrying an ‘**Executor:**‘ line | DELETE |  |
| 370 | writing-plans gates the roster per executor | skills/writing-plans/references/assignment-procedure.md: for every executor whose gate prints ‘lane=true‘ | DELETE |  |
| 371 | writing-plans allows one Executor line per task | skills/writing-plans/references/assignment-procedure.md: A task carries at most one ‘**Executor:**‘ line | DELETE |  |
| 372 | inline mode no longer calls executor lines inert | $INLINE: ‘**Executor:**‘ lines are inert for the tasks you | DELETE |  |
| 373 | writing-plans no longer reads executor lines only when dele… | <(cat "skills/writing-plans/SKILL.md" "skills/writing-plans/references/"*.md): the lines are read only f… | DELETE |  |
| 378 | ${doc#$P/} does not say inline mode implements every task i… | $doc: implements every task itself | DELETE | loop 377-380 over each executing-plans/writing-plans md and native-codex.md (absent phrase); 2 statements 378,379 |
| 379 | ${doc#$P/} does not say inline mode implements every task i… | $doc: implements every task in | DELETE | same loop |

### inline-only-execution.acceptance.test.sh

DELETE 13, KEEP direct 0, KEEP format contract 1, borderline 1 (borderline rows are in section 3).

| line(s) | test label | markdown file: phrase pinned | verdict | note |
|---|---|---|---|---|
| 247 | A8: no skill or reference names a drafter or scout agent | got: $hits  want:  | DELETE | A8: grep -rlE over skills/ and reference/ for drafter/scout agent names (absent-phrase pin); 248-249 are file-absence checks and stay |
| 268 | A10: using-dforge's executing-a-plan row names dforge:execu… | $row: dforge:executing-plans | DELETE | A10 (265-273): row of the using-dforge routing table; no script reads it |
| 271 | A10: the row does not name subagent-driven-development ahea… | $before: subagent-driven-development | DELETE | A10 |
| 272 | A10: the row keeps subagent mode for a plan whose line says… | $after: subagent | DELETE | A10 |
| 279 | A11: nothing outside the allowlist names the escalation lin… | got: $hits  want:  | DELETE | A11: grep -rl over skills/reference for the escalation line outside an allowlist; 280-285 (ledger_left_inline behaviour) stay |
| 442 | A16: executing-plans' setup keys its preflight item on the … | got: $([ -n "$para" ] && echo yes \|\| echo no)  want: yes | DELETE | A16: awk paragraph of executing-plans setup.md keyed on `preflight` and `**Heavy:**`; 440-441 are its helpers; the other A16 checks (task-brief output) stay |
| 448 | A17: executing-plans names the breaker ruling for a task at… | got: $([ -n "$para" ] && echo yes \|\| echo no)  want: yes | DELETE | A17 (446-451): whole block is wording only |
| 450 | A17: no skill or reference outside the deprecated skill say… | got: $hits  want:  | DELETE | A17: absent-phrase grep over skills/reference |
| 457 | A18: $skill states the Process line without a mode slot | $text: Process: <spike\|bounded\|architectural> | DELETE | A18 (455-460): loop over brainstorming and using-dforge; whole block is wording only |
| 458 | A18: $skill names no <inline\|subagent> slot | $(cat "LUGIN/skills/$skill"/SKILL.md "LUGIN/skills/$skill"/references/*.md 2>/dev/null): <(inline\\|suba… | DELETE | A18 |
| 459 | A18: $skill's Process line carries no inline or subagent wo… | $(grep -oE 'Process: <[^>]*>[^‘]*' <<<"$text"): inline\|subagent | DELETE | A18 |
| 466 | A19: executor-lane.md has the unavailable-executor ledger l… | $lane: implementer inline \(assigned; [^)]*; executor <id> unavailable - <reason>\) | DELETE | A19 (465-468): whole block is wording only; the `executor <id> unavailable` text is not parsed by a script |
| 467 | A19: executor-lane.md names the handback line | $lane: HANDBACK to inline | KEEP(scripts/review-route; format contract) | scripts/review-route:172,244 and lane-breaker parse `HANDBACK to <agent>` ledger tokens |
| 468 | A19: the unavailable-executor line names no agent in the im… | $(grep -E 'executor <id> unavailable - <reason>' <<<"$lane"): implementer (dforge:\|impl-) | DELETE | A19 |

### inline-only.acceptance.test.sh

DELETE 34, KEEP direct 0, KEEP format contract 1, borderline 4 (borderline rows are in section 3).

| line(s) | test label | markdown file: phrase pinned | verdict | note |
|---|---|---|---|---|
| 177-178 | A8: no skill or reference names the drafter | got: $(grep -rlF 'drafter-sonnet' "$P/skills" "$P/reference" \| wc -l \| tr -d ' ')  want: 0 | DELETE | A8: grep -rlF over skills/reference (check spans 177-178) |
| 179 | writing-plans drafts every task in the session | skills/writing-plans/SKILL.md: Draft every task in the session, at any plan size. | DELETE |  |
| 182-183 | A8: no skill or reference names the scout | got: $(grep -rlF 'scout-sonnet' "$P/skills" "$P/reference" \| wc -l \| tr -d ' ')  want: 0 | DELETE | A8: same for scout-sonnet (check spans 182-183) |
| 184 | selecting-approaches has two modes | skills/selecting-approaches/SKILL.md: Two modes: \‘inline\‘ and \‘advisor\‘. | DELETE |  |
| 190 | A17: a task at fix round 3/3 goes to the breaker | $EP: After ‘fix round 3/3‘, the task goes to the ruling seat as a ‘breaker‘ item. | DELETE | Task 7: skill_view of executing-plans |
| 191 | A17: no switch to subagent mode | $EP: Switching to subagent mode | DELETE |  |
| 193 | the session implements heavy tasks | $EP: You implement every task that carries no \‘**Executor:**\‘ line, heavy tasks included. | DELETE |  |
| 194 | risk-3 tasks run the session loop | $EP: ‘**Review:** per-task — risk 3‘ | DELETE |  |
| 195 | setup keys preflight on the Heavy line | skills/executing-plans/references/setup.md: The ‘preflight‘ item runs when ‘plan-header.md‘ ends with a … | DELETE |  |
| 196 | delegated-task documents the session loop | reference/delegated-task.md: ## The session review loop | DELETE |  |
| 197 | the session loop starts inline | reference/delegated-task.md: task-step start PLAN_FILE <N> --inline | DELETE |  |
| 198 | the session loop's fix slot | reference/delegated-task.md: ; session) | DELETE |  |
| 199 | recovery resumes the session loop | skills/executing-plans/references/recovery.md: ‘fix round R/2‘ whose last slot is ‘session‘ or ‘HANDBACK… | DELETE |  |
| 200 | an executor handback mid-loop stays in the session | reference/delegated-task.md: \| ‘fix round 1/2‘ whose last slot is ‘session‘ or ‘HANDBACK to inline‘ \| … | DELETE |  |
| 201 | the pre-review handback line resumes the session loop | skills/executing-plans/references/recovery.md: executor <id> HANDBACK - <reason>])‘ | DELETE |  |
| 202 | the breaker row covers any task at its cap | skills/executing-plans/references/ruling-seat.md: A task's findings or verifications still open at its c… | DELETE |  |
| 205 | A19: the unavailable line names the session | reference/executor-lane.md: implementer inline (assigned; base <sha7>; executor <id> unavailable - <reas… | DELETE | Task 8 |
| 206 | A19: a handback goes to the session | reference/executor-lane.md: HANDBACK to inline | KEEP(scripts/review-route; format contract) | scripts/review-route:172,244 and lane-breaker parse `HANDBACK to <agent>` ledger tokens |
| 207 | A19: no handback to an implementer agent | reference/executor-lane.md: HANDBACK to impl- | DELETE | Task 8 (absent) |
| 208 | handoff has no subagent-mode stop | skills/handoff/SKILL.md: inline to subagent mode | DELETE |  |
| 209 | session-budget has no subagent-mode stop | reference/session-budget.md: switches from inline to subagent mode | DELETE | Task 8 (absent) |
| 211-212 | A11: only the allowlist names the escalation line | got: $(grep -rlF 'escalated inline -> subagent' "$P/skills" "$P/reference" \| grep -vE "^($allow)  want:… | DELETE | A11: grep -rlF over skills/reference |
| 213-214 | A11: no reference names switching to subagent mode | got: $(grep -rliF 'switching to subagent mode' "$P/skills" "$P/reference" \| grep -v "$P/skills/subagent… | DELETE | A11 |
| 221 | execution line is always inline | skills/writing-plans/references/execution-line.md: Write ‘inline‘ on every plan. | DELETE |  |
| 222 | no heavy-majority rule | $WP: more than half the tasks are heavy | DELETE |  |
| 223 | parallel needs an explicit subagent line | $WP: Parallel waves apply only when the Execution line is \‘subagent\‘ | DELETE |  |
| 224 | Codex has no all-or-nothing inline rule | reference/native-codex.md: all-or-nothing inline rule | DELETE |  |
| 229 | A10: routing names executing-plans | skills/using-dforge/SKILL.md: \| Executing a plan \| dforge:executing-plans | DELETE |  |
| 231 | A18: $(basename "$(dirname "$f")") states the Process line | $f: Process: <spike\|bounded\|architectural> — <trigger \| no trigger> | DELETE | loop 230-233 over brainstorming and using-dforge SKILL |
| 232 | A18: $(basename "$(dirname "$f")") has no mode slot | $f: <inline\|subagent> | DELETE | loop 230-233 (absent) |
| 234 | brainstorming asks no strategy question | skills/brainstorming/SKILL.md: **Ask the execution strategy** | DELETE |  |
| 242 | README drops: $needle | README.md: $needle | DELETE | loop 241-243 over 4 README phrases (absent); counts as 4 assertions |

### process-roles.test.sh

DELETE 127, KEEP direct 2, KEEP format contract 3, borderline 2 (borderline rows are in section 3).

| line(s) | test label | markdown file: phrase pinned | verdict | note |
|---|---|---|---|---|
| 20 | qa: the seat | reference/acceptance-qa.md: dispatches ‘dforge:impl-sonnet-high‘ | DELETE |  |
| 21 | qa: never reads the plan | reference/acceptance-qa.md: You may not read the plan, the | DELETE |  |
| 22 | qa: expectations first | reference/acceptance-qa.md: the spec text alone, as literal values in the test | DELETE |  |
| 23 | qa: test names | reference/acceptance-qa.md: Each test name starts with ‘A<n>:‘ | DELETE |  |
| 24 | qa: never fixes the code | reference/acceptance-qa.md: An assertion failure is a finding, which you never fix | DELETE |  |
| 25 | qa: detached mutation worktree | reference/acceptance-qa.md: git worktree add --detach [WORKSPACE]/qa-mutation HEAD | DELETE |  |
| 26 | qa: tests are committed as they run | reference/acceptance-qa.md: Commit as you go: once a statement's test has run | DELETE |  |
| 27 | qa: the mutation baseline passes first | reference/acceptance-qa.md: run that statement's test there before changing anything | DELETE |  |
| 28 | qa: a setup error is not red | reference/acceptance-qa.md: A missing file, an import or a | DELETE |  |
| 29 | qa: report path | reference/acceptance-qa.md: ‘[WORKSPACE]/acceptance-report.md‘ | DELETE |  |
| 30 | qa: ambiguous result | reference/acceptance-qa.md: ‘cannot-test: ambiguous‘ | DELETE |  |
| 31 | qa: the report lists only the statements given | got: $(grep -qF -- 'demo — not executed' "$QA" && echo yes \|\| echo no)  want: no | DELETE | absent pin |
| 34 | analyst: the checklist step | skills/brainstorming/SKILL.md: 6. **Draft acceptance** — numbered, tagged, rated statements | DELETE |  |
| 35 | analyst: auto-run offer follows it | skills/brainstorming/references/auto-run-offer.md: right after the Draft acceptance step and before you | DELETE |  |
| 36 | analyst: the line format | skills/brainstorming/references/drafting-acceptance.md: ‘A<n>. [<test\|demo>[, neg], <high\|confirmed>] … | DELETE | statement-line grammar `A<n>. [<test\|demo>...]`: no script parses acceptance statements |
| 37 | analyst: the verdict options | skills/brainstorming/references/drafting-acceptance.md: **Right**, **Wrong, or not wanted** and **Not su… | DELETE |  |
| 38 | analyst: not sure defers | skills/brainstorming/references/auto-by-default.md: --state deferred --note "Q: <question>" | DELETE |  |
| 39 | analyst: confirmed is the human's | skills/brainstorming/references/drafting-acceptance.md: ‘confirmed‘ is reserved for a verdict from your … | DELETE |  |
| 40 | analyst: self-review item | skills/brainstorming/references/spec-self-review.md: every statement matches ‘A<n>. [<test\|demo>[, neg]… | DELETE | same grammar, spec-self-review.md |
| 44-45 | analyst: drafting sits between After the Design and the aut… | got: $([ -n "$after" ] && [ -n "$draft" ] && [ -n "$offer" ] && [ "$after" -lt "$draft" ] && [ "$draft" … | DELETE | heading-order check with grep -n on brainstorming SKILL (41-43 are its helpers) |
| 46 | analyst: the process graph | skills/brainstorming/references/process-flow.md: "Draft acceptance\n(rate; ask below high)" -> "Offer an… | DELETE |  |
| 47-48 | analyst: live spec self-review checks the format | skills/brainstorming/references/spec-self-review.md: no rating other than ‘high‘ or ‘confirmed‘ appears | DELETE |  |
| 49-50 | analyst: plans never build on a deferred statement | skills/writing-plans/references/register-rows.md: A row whose Item begins ‘A<n>:‘ is a deferred acceptan… | DELETE |  |
| 57 | critic: the prompt does not score | skills/brainstorming/references/architecture-critic-prompt.md: do not score them 1-20 | DELETE |  |
| 58 | critic: ranked findings | skills/brainstorming/references/architecture-critic-prompt.md: Blocker / High / Medium / Nit | DELETE |  |
| 59 | critic: one change | skills/brainstorming/references/architecture-critic-prompt.md: If I could change one thing, it would be | DELETE |  |
| 60 | critic: checklist step | skills/brainstorming/SKILL.md: 10. **Architecture critic** — one ‘dforge:judge-opus‘ round | DELETE |  |
| 61 | critic: findings section | skills/brainstorming/references/architecture-critic.md: answered in a ‘## Critic findings‘ section | DELETE |  |
| 62 | critic: counts in the review request | skills/brainstorming/references/architecture-critic.md: Critic: <b> Blocker, <h> High (<f> fixed, <a> an… | DELETE |  |
| 63-64 | critic: live Fable review checks answers | reference/auto-run.md: each answer to a Blocker or High finding | DELETE |  |
| 65 | critic: the process graph | skills/brainstorming/references/process-flow.md: "Architecture critic\n(one judge-opus round)" -> "User … | DELETE |  |
| 66 | critic: folded into Fable at depth standard | skills/brainstorming/references/architecture-critic.md: and the spec's depth is ‘standard‘, dispatch no … | DELETE |  |
| 67 | critic: depth full keeps the separate round | skills/brainstorming/references/architecture-critic.md: new-subsystem trigger gives it, keeps the separa… | DELETE |  |
| 68 | critic: the folded counts say so | skills/brainstorming/references/architecture-critic.md: followed by ‘ (in Fable's review)‘ when the crit… | DELETE |  |
| 69 | auto-run.md: the critic may fold into Fable | reference/auto-run.md: which folds the critic into | DELETE |  |
| 75-76 | final review: gates, QA, package, lenses in order | got: $([ -n "$g" ] && [ -n "$q" ] && [ -n "$k" ] && [ -n "$l" ] && [ "$g" -lt "$q" ] && [ "$q" -lt "$k" … | DELETE | whole block 71-76 (`at()` helper, g/q/k/l vars) exists only for this order pin |
| 77 | final review: QA skipped when complete | reference/final-review.md: the ledger already holds ‘Acceptance QA: complete‘ | DELETE |  |
| 78 | final review: recovery from the report | reference/final-review.md: ‘<workspace>/acceptance-report.md‘ exists, read it | DELETE |  |
| 79 | final review: recovery re-dispatch | reference/final-review.md: otherwise re-dispatch once with ‘[MODE]‘ ‘rerun‘ | DELETE |  |
| 80 | final review: leftover worktree | reference/final-review.md: git worktree remove --force <workspace>/qa-mutation | DELETE |  |
| 81 | final review: ambiguous goes to the ruling seat | reference/final-review.md: ‘scripts/review-route PLAN_FILE --ruling acceptance-ambiguous‘ | DELETE |  |
| 82 | final review: lens replies as files | reference/final-review.md: each lens seat writes its report to ‘<workspace>/lens-<id>-report.md‘ | DELETE |  |
| 83 | final review: residual acceptance failure | reference/final-review.md: is the one edit allowed on an acceptance test | DELETE |  |
| 84 | final review: a spent re-dispatch writes the report | reference/final-review.md: is spent: write ‘<workspace>/acceptance-report.md‘ yourself, with | DELETE |  |
| 85 | final review: the QA timer outlives the background default | reference/final-review.md: call's ‘timeout‘ set to (‘<s>‘ + 120) × 1000 ms | DELETE |  |
| 86 | final review: the QA timer scales with the statements | reference/final-review.md: ‘<s>‘ = 600 + 180 × the number of | DELETE |  |
| 87 | final review: QA runs alongside the review | reference/final-review.md: Then go on to step 1 without waiting | DELETE |  |
| 88 | final review: the fix wave waits for QA | reference/final-review.md: 3. **Wait for QA.** | DELETE |  |
| 89 | final review: the review reads the QA dispatch SHA | reference/final-review.md: passed as that SHA, never as the word ‘HEAD‘ | DELETE |  |
| 90 | final review: the re-review covers QA's commits | reference/final-review.md: so the range holds QA's | DELETE |  |
| 91 | final review: a small plan's lenses skip Minor | reference/final-review.md: [Report Critical and Important findings only; leave Minor ones | DELETE |  |
| 92 | final review: the ledger goes by path | reference/final-review.md: never paste the lines into the prompt | DELETE |  |
| 93 | re-review: added acceptance tests are checked | skills/subagent-driven-development/references/re-review-prompt.md: When the fix diff adds or touches a t… | DELETE |  |
| 94 | final review: V2 waits for QA to stop before cleanup | reference/final-review.md: Clean up only once it has stopped | DELETE |  |
| 95 | final review: the wait for a stopped QA agent is bounded | reference/final-review.md: finished, for 10 minutes at most in all. | DELETE |  |
| 96 | final review: a QA agent that cannot be stopped keeps its f… | reference/final-review.md: If it cannot be stopped, leave its files in place | DELETE |  |
| 97 | final review: a skipped Codex round has no status line to w… | reference/final-review.md: nothing to wait for: go straight to the one-list case | DELETE |  |
| 98 | final review: both acceptance test name forms are protected | reference/final-review.md: or with ‘a<n>_‘ where the framework forbids a colon | DELETE |  |
| 99 | final review: a test the QA report names is protected | reference/final-review.md: or which the QA report identifies as an | DELETE |  |
| 100 | re-review: a test the QA report names is protected | skills/subagent-driven-development/references/re-review-prompt.md: or which the QA report identifies as … | DELETE |  |
| 101 | re-review: both acceptance test name forms | skills/subagent-driven-development/references/re-review-prompt.md: starts with ‘A<n>:‘ or | DELETE |  |
| 102 | final review: demos are counted from the spec | reference/final-review.md: counted from the final report, except ‘<d>‘: the number of the spec's | DELETE |  |
| 103 | final review: qa findings join the Claude list | reference/final-review.md: ‘[qa]‘ finding from step 0.5 and every lens finding | DELETE |  |
| 104 | final review: qa findings skip the verifier | reference/final-review.md: A ‘[qa]‘ finding is not given to the verifier: it enters the fix wave as | DELETE |  |
| 107 | $s: dispatched line | $f: Acceptance QA: dispatched (base <sha7>) | DELETE | loop 105-112 over 2 files (ledger.md, executing-plans SKILL); `Acceptance QA: dispatched` is not in review-record REVIEW_LINES |
| 108 | $s: complete line | $f: Acceptance QA: complete — <p> pass, <f> fail, <k> flaky, <c> cannot-test, <d> demo | KEEP(scripts/review-record; format contract) | scripts/review-record REVIEW_LINES matches `Acceptance QA: complete` ledger lines (review-record:26) |
| 109 | $s: recovery points at step 0.5 | $f: ‘Acceptance QA:‘ lines are written by | DELETE | loop 105-112 |
| 110 | $s: recovery reads an existing report | $f: line and ‘<workspace>/acceptance-report.md‘ present means read the report | DELETE | loop 105-112 |
| 111 | $s: recovery re-dispatches once without a report | $f: with no report, re-dispatch QA once with ‘[MODE]‘ | DELETE | loop 105-112 |
| 114 | task review: lens-route per task | reference/delegated-task.md: ‘scripts/lens-route PLAN_FILE --task <N>‘, and writes | DELETE |  |
| 116 | task reviewer: lens section | skills/subagent-driven-development/references/task-reviewer-prompt.md: ## Lens Criteria | KEEP(scripts/task-step) | scripts/task-step drop_sections "Lens Criteria" on this template (task-step:897,907) |
| 117 | task reviewer: lenses are not scored | skills/subagent-driven-development/references/task-reviewer-prompt.md: do not score them, and do not add… | DELETE |  |
| 118 | task reviewer: the placeholder | skills/subagent-driven-development/references/task-reviewer-prompt.md: ‘[LENS_FILES]‘ — OPTIONAL | KEEP(scripts/task-step) | scripts/task-step fills `[LENS_FILES]` (task-step:903) |
| 119 | task reviewer: Minor issues are capped | skills/subagent-driven-development/references/task-reviewer-prompt.md: List at most three Minor issues, … | DELETE |  |
| 120-121 | re-review: the A<n> question | skills/subagent-driven-development/references/re-review-prompt.md: still fail if the code violated state… | DELETE |  |
| 122-123 | code reviewer: the A<n> question | skills/requesting-code-review/references/code-reviewer.md: would it fail if the code violated spec state… | DELETE |  |
| 124 | requesting review: security lens | skills/requesting-code-review/SKILL.md: criteria/lenses/security.md | DELETE | path mention of criteria/lenses/security.md in a skill; no script |
| 126-127 | milestone judge: A<n> tests are evidence | skills/closing-a-milestone/references/milestone-judge.md: is evidenced by the committed test whose name … | DELETE |  |
| 128-129 | gates template: claude-security example | skills/running-gates/references/gates-template.md: claude --agent claude-security:claude-security | DELETE |  |
| 131 | codex: critic and lens seats | reference/native-codex.md: The architecture critic and every review lens are native judges at rank 8 | DELETE |  |
| 132 | codex: QA seat | reference/native-codex.md: Acceptance QA is a native implementer at ‘gpt-6.1-sol / high‘ | DELETE |  |
| 135 | drafting: every task is drafted in the session | skills/writing-plans/SKILL.md: Draft every task in the session, at any plan size. | DELETE |  |
| 150 | shape: a task is a feature slice | skills/writing-plans/SKILL.md: A task is a feature slice | DELETE |  |
| 151 | shape: bite-sized granularity is gone | <(cat "skills/writing-plans/SKILL.md" "skills/writing-plans/references/"*.md): ## Bite-Sized Task Granul… | DELETE | absent pin over concatenated writing-plans md |
| 152 | shape: no bite-sized wording | <(cat "skills/writing-plans/SKILL.md" "skills/writing-plans/references/"*.md): bite-sized | DELETE | absent pin |
| 153 | shape: the task carries its interfaces, tests and verify co… | skills/writing-plans/SKILL.md: its interfaces, the complete code of its tests, the decisions it embodies | DELETE |  |
| 154 | shape: implementation code only where no test pins it | skills/writing-plans/SKILL.md: $ALLOWED | DELETE |  |
| 155 | shape: Step 3 describes the implementation | skills/writing-plans/SKILL.md: Step 3 describes the implementation; it carries no implementation code | DELETE |  |
| 156 | shape: Step 3 no longer carries the implementation | <(cat "skills/writing-plans/SKILL.md" "skills/writing-plans/references/"*.md): Step 3 carries the whole … | DELETE | absent pin |
| 157 | shape: a Codex host keeps code-given tasks | skills/writing-plans/SKILL.md: On a Codex host, tasks keep the code-given shape | DELETE |  |
| 158 | shape: tests that assert nothing are placeholders | skills/writing-plans/SKILL.md: Tests that describe behaviour without asserting it | DELETE |  |
| 159 | shape: the old how-not-shown ban is reworded | <(cat "skills/writing-plans/SKILL.md" "skills/writing-plans/references/"*.md): Steps that describe what … | DELETE | absent pin |
| 160 | shape: a Claude code task scores spec 2 | skills/writing-plans/references/assignment-procedure.md: so it scores spec 2 | DELETE |  |
| 161 | shape: Rule S at 6 on a Claude plan | skills/writing-plans/references/assignment-procedure.md: On a Claude plan, if ‘files + spec + coupling >… | DELETE |  |
| 162 | shape: Rule S at 4 on a Codex plan | skills/writing-plans/references/assignment-procedure.md: on a ‘Host: codex‘ plan, if it is ‘>= 4‘ | DELETE |  |
| 163 | shape: no host-blind Rule S at 4 | <(cat "skills/writing-plans/SKILL.md" "skills/writing-plans/references/"*.md): If ‘files + spec + coupli… | DELETE | absent pin |
| 164 | plan reviewer: a missing implementation body is not a findi… | skills/writing-plans/references/plan-reviewer-prompt.md: a missing implementation body is not a finding | DELETE |  |
| 165 | plan reviewer: a stub or missing test is | skills/writing-plans/references/plan-reviewer-prompt.md: a missing or stub test is | DELETE |  |
| 166 | plan review criteria: a precise description is not a gap | criteria/plan-review.md: a task that describes its implementation precisely without its code is not a gap | DELETE |  |
| 167 | plan review criteria: implementation code only where no tes… | criteria/plan-review.md: $ALLOWED | DELETE |  |
| 168 | plan review criteria: no host-blind complete-code rule | criteria/plan-review.md: exact file paths, every code step carries the complete code | DELETE | absent pin |
| 169 | assigning: a Claude code task scores spec 2 | skills/writing-plans/references/assigning-implementers.md: gives its tests and interfaces but not its im… | DELETE |  |
| 170 | assigning: the Claude cap is 8 | skills/writing-plans/references/assigning-implementers.md: Rule S caps a compliant Claude total at 8 | DELETE |  |
| 171 | assigning: no cap at 6 | skills/writing-plans/references/assigning-implementers.md: Rule S also caps a compliant total at 6 | DELETE | absent pin |
| 172 | spec review: Fable's second round needs an open Blocker or … | skills/brainstorming/references/auto-by-default.md: a second only when round 1 leaves a Blocker or High … | DELETE |  |
| 173 | spec review: the folded critic gets no second Fable round | skills/brainstorming/references/architecture-critic.md: No second Fable round runs at standard | DELETE |  |
| 174 | spec review: no unconditional answer check | <(cat "skills/brainstorming/SKILL.md" "skills/brainstorming/references/"*.md): which checks each Blocker… | DELETE | absent pin |
| 175 | auto-run.md: Fable's second round needs an open Blocker or … | reference/auto-run.md: A second runs only when round 1 leaves a Blocker or High finding open | DELETE |  |
| 176 | auto-run.md: no unconditional second round | reference/auto-run.md: At most two Fable rounds run (review, revise, re-review) | DELETE | absent pin |
| 178 | writing-plans forms: the Extend form heading | skills/writing-plans/references/test-step-forms.md: - [ ] **Step 1: Extend the test ‘<file>::<name>‘** | KEEP(scripts/plan-lint; format contract) | scripts/plan-lint step1_class parses the `Extend the test` heading (plan-lint:730) |
| 179 | writing-plans forms: the Covered by form heading | skills/writing-plans/references/test-step-forms.md: - [ ] **Step 1: Covered by Task <N>\'s test ‘<name>‘… | KEEP(scripts/plan-lint; format contract) | scripts/plan-lint step1_class parses the `Covered by Task <N>'s test` heading (plan-lint:731-732) |
| 180 | writing-plans forms: Covered by is for behaviour-free tasks… | skills/writing-plans/references/test-step-forms.md: only for a task that adds no new observable behaviour | DELETE |  |
| 181 | writing-plans forms: a task adding behaviour uses Extend | skills/writing-plans/references/test-step-forms.md: A task that adds behaviour uses Extend | DELETE |  |
| 182 | writing-plans forms: a Covered by task names the fault | skills/writing-plans/references/test-step-forms.md: The step names the fault in this task\'s code that t… | DELETE |  |
| 183 | writing-plans forms: a Covered by task writes no test of it… | skills/writing-plans/references/test-step-forms.md: The task has no step that writes its own failing tes… | DELETE |  |
| 184 | writing-plans forms: the Extend step must fail first | skills/writing-plans/references/test-step-forms.md: it must fail before the implementation, as a new tes… | DELETE |  |
| 188 | TDD: the Minimal row is replaced by the one-behaviour rule | skills/test-driven-development/SKILL.md: \| **One behaviour** \| Variants of one behaviour are rows of o… | DELETE |  |
| 189 | TDD: the Minimal row is gone | skills/test-driven-development/SKILL.md: \| **Minimal** \| | DELETE | absent pin |
| 190 | TDD REFACTOR: a branch test may go for a broader branch test | skills/test-driven-development/SKILL.md: Delete a test written on this branch when a broader test writte… | DELETE |  |
| 191 | TDD REFACTOR: the commit body names the faults | skills/test-driven-development/SKILL.md: The commit body names those faults | DELETE |  |
| 192 | TDD REFACTOR: only tests absent at the merge base | skills/test-driven-development/SKILL.md: covers only tests that do not exist at the branch\'s merge base | DELETE |  |
| 193 | TDD REFACTOR: never a regression test | skills/test-driven-development/SKILL.md: never a regression test that names a fixed bug | DELETE |  |
| 194 | TDD REFACTOR: older tests go to test-simplifier | skills/test-driven-development/SKILL.md: A test that predates the branch goes through dforge:test-simpli… | DELETE |  |
| 195 | good tests: find an existing test that fails for the change | skills/test-driven-development/references/writing-good-tests.md: After naming the change, find whether a… | DELETE |  |
| 196 | good tests: the gate function asks the same | skills/test-driven-development/references/writing-good-tests.md: An existing test already fails for it | DELETE |  |
| 197 | plan review: Redundant test scores LOW under Executability | criteria/plan-review.md: Redundant test: score LOW when a planned test fails for no fault that an existi… | DELETE |  |
| 198 | plan review: the reviewer names the overlapping test | criteria/plan-review.md: name the overlapping test in the finding | DELETE |  |
| 199 | plan review: a Covered by task is judged by its named fault | criteria/plan-review.md: judge its Executability by the fault the step names | DELETE |  |
| 200 | plan review: Redundant test is no fifth criterion | got: $(grep -c '^### ' "$PR")  want: 4 | DELETE | counts `### ` headings in plan-review.md; nothing reads them |
| 202 | final review: the fix wave deletes only branch tests | reference/final-review.md: The fix wave may delete only a test added on the branch, a test that does not… | DELETE |  |
| 203 | final review: never a regression test | reference/final-review.md: never a regression test that names a fixed bug | DELETE |  |
| 204 | final review: older tests are test-simplifier's | reference/final-review.md: a test that exists at MERGE_BASE is left for dforge:test-simplifier | DELETE |  |

### seats.test.sh

DELETE 87, KEEP direct 11, KEEP format contract 15, borderline 1 (borderline rows are in section 3).

| line(s) | test label | markdown file: phrase pinned | verdict | note |
|---|---|---|---|---|
| 103 | requesting review: the judge seat | skills/requesting-code-review/SKILL.md: Dispatch ‘dforge:judge-opus‘ as ‘subagent_type‘ | DELETE |  |
| 104 | requesting review: the diff file comes first | skills/requesting-code-review/SKILL.md: git diff -U10 "$BASE_SHA..$HEAD_SHA" | DELETE |  |
| 105 | requesting review: the diff file is checked before dispatch | skills/requesting-code-review/SKILL.md: [ -s "$DIFF_FILE" ] && ! git diff --quiet "$BASE_SHA..$HEAD_SHA" | DELETE |  |
| 106 | requesting review: the diff file needs a base | skills/requesting-code-review/SKILL.md: [ -n "$BASE_SHA" ] | DELETE |  |
| 107 | requesting review: the state directory ignores itself | skills/requesting-code-review/SKILL.md: dforge_self_ignore "$STATE_DIR" | DELETE |  |
| 108 | requesting review: no general-purpose seat | got: $(grep -c 'general-purpose' "$RCR")  want: 0 | DELETE | grep -c absent pin |
| 109 | code reviewer: the judge seat | skills/requesting-code-review/references/code-reviewer.md: Subagent (dforge:judge-opus): | DELETE |  |
| 110 | code reviewer: no git fallback | got: $(grep -c 'derive it yourself' "$CR")  want: 0 | DELETE | grep -c absent pin |
| 111 | code reviewer: the diff file is required | skills/requesting-code-review/references/code-reviewer.md: ‘[DIFF_FILE]‘ — REQUIRED | DELETE |  |
| 114 | re-review: the judge seat | skills/subagent-driven-development/references/re-review-prompt.md: Subagent (dforge:judge-sonnet-high; d… | DELETE |  |
| 115 | re-review: no general-purpose seat | got: $(grep -c 'general-purpose' "$RRP")  want: 0 | DELETE | grep -c absent pin |
| 116 | re-review: no model line | got: $(grep -c '^ model:' "$RRP")  want: 0 | DELETE | grep -c absent pin |
| 117 | re-review: no model placeholder | got: $(grep -c '\[MODEL\]' "$RRP")  want: 0 | KEEP(scripts/task-step) | scripts/task-step rereview refuses a template holding an unfilled `[MODEL]` placeholder (task-step:487) |
| 118 | re-review: no git fallback | got: $(grep -c 'git diff' "$RRP")  want: 0 | DELETE | grep -c absent pin |
| 119 | re-review: the diff file is required | skills/subagent-driven-development/references/re-review-prompt.md: ‘[DIFF_FILE]‘ — REQUIRED | KEEP(scripts/task-step) | scripts/task-step rereview fills `[DIFF_FILE]` (task-step:341) |
| 120 | re-review: the read-only clause stays | skills/subagent-driven-development/references/re-review-prompt.md: Your review is read-only on this chec… | DELETE |  |
| 121 | delegated loop: no general-purpose re-review row | got: $(grep -c '^\| Scoped re-review \| general-purpose' "$DT")  want: 0 | DELETE | grep -c absent pin |
| 122 | delegated loop: the re-review row names the judge seats | reference/delegated-task.md: \| Scoped re-review \| ‘dforge:judge-sonnet-high‘; ‘dforge:judge-opus‘ for … | DELETE |  |
| 123 | entry point: the Seats section | skills/using-dforge/SKILL.md: ## Seats | DELETE |  |
| 124 | entry point: general-purpose takes a model | skills/using-dforge/SKILL.md: ‘general-purpose‘ takes an explicit ‘model‘ | DELETE |  |
| 125 | entry point: read-only checks on a judge | skills/using-dforge/SKILL.md: Read-only checks (register rows, findings, a claim) go to ‘dforge:judge-so… | DELETE |  |
| 140 | $n: names the report file | $t: Write your full report to [REPORT_FILE] and write nothing else | KEEP(hooks/cockpit/register.tsx) | hooks/cockpit/register.tsx REPORT_LINE (`^\s*Write your full report to `) reads this line from the dispatch prompt (register.tsx:213,4144); loop 138-146 over 4 templates; consumer reads only the prefix |
| 141 | $n: the reply is at most 10 lines | $t: Then reply in at most 10 lines | DELETE | loop 138-146 over 4 templates |
| 142 | $n: the report opens with the Verdict section | got: $(grep -qE '^ *## Verdict$' "$t" 2>/dev/null && echo yes \|\| echo no)  want: yes | KEEP(scripts/task-step; format contract) | scripts/task-step parse_report requires `## Verdict` first (task-step:1141 parse_report); loop 138-146: the ruling-prompt iteration is a pin - restrict the loop to 3 templates |
| 143 | $n: the report file is a placeholder | $t: ‘[REPORT_FILE]‘ — REQUIRED | KEEP(task-step) | task-step fills `[REPORT_FILE]` in the task-reviewer, group-reviewer and re-review templates (task-step:338,901,1072); loop 138-146: the ruling-prompt iteration is a pin (no script fills it) - restrict the loop to 3 templates |
| 144 | $n: the final message is no longer the report | $t: Your final message is the report itself | DELETE | loop 138-146; absent pin |
| 145 | $n: the seat no longer says it cannot modify files | $t: You cannot modify files | DELETE | loop 138-146; absent pin |
| 149 | $n: the finding grammar | $t: - [Critical\|Important\|Minor] <file>:<line> — <one-liner> | KEEP(task-step; format contract) | task-step parse_report finding-line grammar (task-step parse_report finding regex); loop 147-151 over TRP and RRP |
| 150 | $n: the implementer's report has its own placeholder | $t: [IMPLEMENTER_REPORT_FILE] | KEEP(task-step) | task-step fills `[IMPLEMENTER_REPORT_FILE]` (task-step:337,901,909); loop 147-151 over TRP and RRP |
| 152 | task reviewer: the spec verdict key | skills/subagent-driven-development/references/task-reviewer-prompt.md: spec: pass \| fail \| cannot-veri… | KEEP(task-step; format contract) | task-step parse_report `spec:` key (task-step parse_report END block) |
| 153 | task reviewer: the quality verdict key | skills/subagent-driven-development/references/task-reviewer-prompt.md: quality: approved \| changes | KEEP(task-step; format contract) | task-step parse_report `quality:` key |
| 154 | task reviewer: the scores key | skills/subagent-driven-development/references/task-reviewer-prompt.md: scores: spec <1-20> / scope <1-20… | KEEP(task-step; format contract) | task-step parse_report `scores:` key (SCORES) |
| 155 | task reviewer: the cannot-verify section | skills/subagent-driven-development/references/task-reviewer-prompt.md: ## Cannot verify | KEEP(task-step; format contract) | task-step parse_report `## Cannot verify` section (task-step parse_report) |
| 156 | task reviewer: the Codex findings are a report section | got: $(grep -qE '^ *## Codex findings$' "$TRP" && echo yes \|\| echo no)  want: yes | KEEP(task-step; format contract) | task-step parse_report `## Codex findings` last-section rule (task-step parse_report) |
| 157 | task reviewer: no Verification Scores block | skills/subagent-driven-development/references/task-reviewer-prompt.md: ### Verification Scores | DELETE | absent pin |
| 158 | re-review: the round verdict key | skills/subagent-driven-development/references/re-review-prompt.md: fix round: addressed \| open | KEEP(task-step; format contract) | task-step parse_report `fix round` key (task-step parse_report) |
| 159 | re-review: the open count key | skills/subagent-driven-development/references/re-review-prompt.md: open: <k> | KEEP(task-step; format contract) | task-step parse_report `open` count key |
| 160 | re-review: the per-finding verdicts | skills/subagent-driven-development/references/re-review-prompt.md: ## Finding verdicts | DELETE | `## Finding verdicts` is not read by parse_report |
| 161 | group reviewer: the per-task finding grammar | skills/subagent-driven-development/references/group-reviewer-prompt.md: - [Critical\|Important\|Minor] (… | KEEP(task-step; format contract) | task-step parse_report group finding grammar `(Task <N>)` |
| 162 | group reviewer: per-task verdict keys | skills/subagent-driven-development/references/group-reviewer-prompt.md: Task <N> spec: pass \| fail \| c… | KEEP(task-step; format contract) | task-step parse_report group `Task <N> spec` keys |
| 163 | group reviewer: per-task scores | skills/subagent-driven-development/references/group-reviewer-prompt.md: Task <N> scores: spec <1-20> / s… | KEEP(task-step; format contract) | task-step parse_report group `Task <N> scores` keys |
| 164 | ruling: the item verdict lines | skills/subagent-driven-development/references/ruling-prompt.md: Verdict: CONFIRMED-GAP \| PARK \| AMEND … | DELETE | ruling-prompt / final-review prose; no script parses ruling reports |
| 165 | ruling: an AMEND names its entry | skills/subagent-driven-development/references/ruling-prompt.md: Amendment: A<k> | DELETE | ruling-prompt / final-review prose; no script parses ruling reports |
| 166 | ruling: entries are numbered in the report | skills/subagent-driven-development/references/ruling-prompt.md: ## A<k> — Task <N> | DELETE | ruling-prompt / final-review prose; no script parses ruling reports |
| 167 | ruling: a BLOCKED reply carries the decision | skills/subagent-driven-development/references/ruling-prompt.md: the decision a human must make | DELETE | ruling-prompt / final-review prose; no script parses ruling reports |
| 168 | ruling: the report file follows the items file | skills/subagent-driven-development/references/ruling-prompt.md: ‘<workspace>/rulings-<point>-<task>-repo… | DELETE | ruling-prompt / final-review prose; no script parses ruling reports |
| 169 | ruling: no unnumbered entry heading | skills/subagent-driven-development/references/ruling-prompt.md: ## A? — Task <N> | DELETE | absent pin |
| 170 | final review: the fix wave's re-review names the fixer's re… | reference/final-review.md: its ‘[IMPLEMENTER_REPORT_FILE]‘ being that file | DELETE | ruling-prompt / final-review prose; no script parses ruling reports |
| 171 | final review: the re-review's REPORT_FILE is not the fixer's | reference/final-review.md: its ‘[REPORT_FILE]‘ being that file | DELETE | absent pin |
| 182 | plan reviewer: both templates name the report file | got: $(count_of "$PRP" 'Write your full report to [REPORT_FILE] and write nothing else')  want: 2 | KEEP(register.tsx) | register.tsx REPORT_LINE (counts the two plan-review templates) |
| 183 | plan reviewer: both templates cap the reply | got: $(count_of "$PRP" 'Then reply in at most 10 lines')  want: 2 | DELETE | plan-reviewer, critic, spec-review, auto-run prose; no script parses these reports |
| 184 | plan reviewer: both reports open with the Verdict section | got: $(grep -cE '^ *## Verdict$' "$PRP")  want: 2 | DELETE | counts a heading in plan-reviewer-prompt; plan-review replies are not parsed by a script |
| 185 | plan reviewer: both carry the scores key | got: $(count_of "$PRP" 'scores: executability <1-20> / coherence <1-20> / coverage <1-20> / assumptions … | DELETE | plan-reviewer, critic, spec-review, auto-run prose; no script parses these reports |
| 186 | plan reviewer: both carry the finding grammar | got: $(count_of "$PRP" '- [Critical\|Important\|Minor] <file>:<line> — <one-liner>')  want: 2 | DELETE | plan-reviewer, critic, spec-review, auto-run prose; no script parses these reports |
| 187 | plan reviewer: the prior findings section | got: $(grep -cE '^ *## Prior findings$' "$PRP")  want: 1 | DELETE | plan-reviewer, critic, spec-review, auto-run prose; no script parses these reports |
| 188 | plan reviewer: the report file placeholder | skills/writing-plans/references/plan-reviewer-prompt.md: ‘[REPORT_FILE]‘ - REQUIRED: ‘<workspace>/plan-r… | DELETE | plan-reviewer, critic, spec-review, auto-run prose; no script parses these reports |
| 189 | plan reviewer: no longer forbids modifying files | skills/writing-plans/references/plan-reviewer-prompt.md: You cannot run commands, modify files, or dispa… | DELETE | absent pin |
| 190-191 | plan reviewer: the seat writes only its report, and change … | got: $(count_of "$PRP" 'You cannot run commands or dispatch subagents, and you write only the report fil… | DELETE | plan-reviewer, critic, spec-review, auto-run prose; no script parses these reports |
| 192 | writing-plans: the controller no longer saves the reply | <(cat "skills/writing-plans/SKILL.md" "skills/writing-plans/references/"*.md): save its reply to | DELETE | absent pin |
| 193 | writing-plans: nor saves each native reply | <(cat "skills/writing-plans/SKILL.md" "skills/writing-plans/references/"*.md): saving each | DELETE | absent pin |
| 194 | writing-plans: round 1 names the report file | skills/writing-plans/references/lint-and-review.md: ‘[REPORT_FILE]‘ set to ‘<workspace>/plan-review-roun… | DELETE | plan-reviewer, critic, spec-review, auto-run prose; no script parses these reports |
| 195 | writing-plans: later rounds name the report file | skills/writing-plans/references/lint-and-review.md: ‘[REPORT_FILE]‘ set to ‘<workspace>/plan-review-roun… | DELETE | plan-reviewer, critic, spec-review, auto-run prose; no script parses these reports |
| 196 | critic: names the report file | skills/brainstorming/references/architecture-critic-prompt.md: Write your full report to [REPORT_FILE] a… | KEEP(register.tsx) | register.tsx REPORT_LINE |
| 197 | critic: caps the reply | skills/brainstorming/references/architecture-critic-prompt.md: Then reply in at most 10 lines | DELETE | plan-reviewer, critic, spec-review, auto-run prose; no script parses these reports |
| 198 | critic: the report opens with the Verdict section | got: $(grep -cE '^ *## Verdict$' "$CP")  want: 1 | DELETE | plan-reviewer, critic, spec-review, auto-run prose; no script parses these reports |
| 199 | critic: the counts key | skills/brainstorming/references/architecture-critic-prompt.md: findings: <b> Blocker, <h> High, <m> Medi… | DELETE | plan-reviewer, critic, spec-review, auto-run prose; no script parses these reports |
| 200 | critic: the finding grammar on its own scale | skills/brainstorming/references/architecture-critic-prompt.md: - [Blocker\|High\|Medium\|Nit] <file>:<li… | DELETE | plan-reviewer, critic, spec-review, auto-run prose; no script parses these reports |
| 201 | critic: the report file | skills/brainstorming/references/architecture-critic-prompt.md: ‘<state>/critic-<spec name>-report.md‘ | DELETE | plan-reviewer, critic, spec-review, auto-run prose; no script parses these reports |
| 202 | spec review: the report file | skills/brainstorming/references/architecture-critic.md: ‘<state>/spec-review-<spec name>-<r>-report.md‘ | DELETE | plan-reviewer, critic, spec-review, auto-run prose; no script parses these reports |
| 203 | spec review: the reply rule | skills/brainstorming/references/architecture-critic.md: write nothing else, and reply in at most 10 lines | DELETE | plan-reviewer, critic, spec-review, auto-run prose; no script parses these reports |
| 204 | spec review: the open count decides a second round | skills/brainstorming/references/architecture-critic.md: open: <b> Blocker, <h> High | DELETE | plan-reviewer, critic, spec-review, auto-run prose; no script parses these reports |
| 205 | spec review: a folded critic's findings are in the report | <(cat "skills/brainstorming/SKILL.md" "skills/brainstorming/references/"*.md): so its reply carries the | DELETE | absent pin |
| 206 | auto run: the spec review's report file | reference/auto-run.md: ‘<state>/spec-review-<spec name>-<r>-report.md‘ | DELETE | plan-reviewer, critic, spec-review, auto-run prose; no script parses these reports |
| 207 | auto run: the pre-execution ruling's report file | reference/auto-run.md: ‘<state>/rulings-preexec-<k>-report.md‘ | DELETE | plan-reviewer, critic, spec-review, auto-run prose; no script parses these reports |
| 208 | auto run: the Fable batch's report file | reference/auto-run.md: ‘<state>/rulings-fable-<k>-report.md‘ | DELETE | plan-reviewer, critic, spec-review, auto-run prose; no script parses these reports |
| 209 | auto run: every seat it dispatches caps its reply | got: $(count_of "$AR" 'write nothing else, and reply in at most 10 lines')  want: 3 | DELETE | plan-reviewer, critic, spec-review, auto-run prose; no script parses these reports |
| 221 | code reviewer: names the report file | skills/requesting-code-review/references/code-reviewer.md: Write your full report to [REPORT_FILE] and w… | KEEP(register.tsx) | register.tsx REPORT_LINE |
| 222 | code reviewer: caps the reply | skills/requesting-code-review/references/code-reviewer.md: Then reply in at most 10 lines | DELETE |  |
| 223 | code reviewer: the report opens with the Verdict section | got: $(grep -qE '^ *## Verdict$' "$CR" && echo yes \|\| echo no)  want: yes | DELETE |  |
| 224 | code reviewer: the merge verdict key | skills/requesting-code-review/references/code-reviewer.md: ready to merge: yes \| no \| with fixes | DELETE |  |
| 225 | code reviewer: the finding grammar | skills/requesting-code-review/references/code-reviewer.md: - [Critical\|Important\|Minor] <file>:<line> … | DELETE |  |
| 226 | code reviewer: the report file placeholder | skills/requesting-code-review/references/code-reviewer.md: ‘[REPORT_FILE]‘ — REQUIRED | DELETE |  |
| 227 | requesting review: the report file beside the diff | skills/requesting-code-review/SKILL.md: REPORT_FILE="$STATE_DIR/review-$(git rev-parse --short "$HEAD_SH… | DELETE |  |
| 228 | final review: the reviewer's report file | reference/final-review.md: ‘[REPORT_FILE]‘ set to ‘<workspace>/final-review-report.md‘ | DELETE |  |
| 229 | final review: lens seats write their report | reference/final-review.md: each lens seat writes its report to ‘<workspace>/lens-<id>-report.md‘ | DELETE |  |
| 230 | final review: the lens finding grammar | reference/final-review.md: - [Critical\|Important\|Minor] <file>:<line> — [lens:<id>] <one-liner> | DELETE |  |
| 231 | final review: the dedupe report file | reference/final-review.md: ‘<workspace>/final-dedupe-report.md‘ | DELETE |  |
| 232 | final review: the lens and dedupe seats cap their reply | got: $(count_of "$FR" 'write nothing else, and reply in at most 10 lines')  want: 2 | DELETE |  |
| 233 | final review: the controller no longer saves lens replies | reference/final-review.md: save each reply to | DELETE | absent pin |
| 234 | milestone judge: writes its report file | skills/closing-a-milestone/references/milestone-judge.md: write nothing else | DELETE |  |
| 235 | milestone judge: caps the reply | skills/closing-a-milestone/references/milestone-judge.md: reply in at most 10 lines | DELETE |  |
| 236 | milestone judge: the report opens with the Verdict section | got: $(grep -qE '^ *## Verdict$' "$MJ" && echo yes \|\| echo no)  want: yes | DELETE |  |
| 237 | closing a milestone: the report file | skills/closing-a-milestone/SKILL.md: ‘<state>/milestone-M<n>-audit-report.md‘ | DELETE |  |
| 238 | distil judge: names the report file | skills/distilling-docs/references/distil-judge.md: Write your full report to [REPORT_FILE] and write not… | KEEP(register.tsx) | register.tsx REPORT_LINE |
| 239 | distil judge: caps the reply | skills/distilling-docs/references/distil-judge.md: Then reply in at most 10 lines | DELETE |  |
| 240 | distil judge: the report opens with the Verdict section | got: $(grep -qE '^ *## Verdict$' "$DJ" && echo yes \|\| echo no)  want: yes | DELETE |  |
| 241 | distil judge: the per-source verdict line | skills/distilling-docs/references/distil-judge.md: <source path>: CARRIED \| MISSING \| DISTORTED | DELETE |  |
| 242 | distilling: the judge's tools are stated as they are | skills/distilling-docs/SKILL.md: grants ‘Read, Grep, Glob, WebFetch‘ and | DELETE | absent pin |
| 243 | simplify judge: both prompts name the report file | got: $(count_of "$SJ" 'Write your full report to [REPORT_FILE] and write nothing else')  want: 2 | KEEP(register.tsx) | register.tsx REPORT_LINE (counts the two simplify-judge prompts) |
| 244 | simplify judge: both prompts cap the reply | got: $(count_of "$SJ" 'Then reply in at most 10 lines')  want: 2 | DELETE |  |
| 245 | simplify judge: the ruling verdict key | skills/test-simplifier/references/simplify-judge.md: verdict: KEPT \| LOST \| VIOLATED | DELETE |  |
| 246 | walkthrough judge: names the report file | skills/ui-ux/references/walkthrough.md: Write your full report to [REPORT_FILE] and write nothing else | KEEP(register.tsx) | register.tsx REPORT_LINE |
| 247 | walkthrough judge: caps the reply | skills/ui-ux/references/walkthrough.md: Then reply in at most 10 lines | DELETE |  |
| 248 | walkthrough judge: the verdict key | skills/ui-ux/references/walkthrough.md: verdict: ship \| fix [FINGERPRINT] | DELETE | ui-proof reads the proof report `**Judge:**` line and the judge file last line `Verdict: ship <fp>`, not this heading-section key |
| 249 | walkthrough: the controller no longer saves the reply | skills/ui-ux/references/walkthrough.md: Save the reply verbatim | DELETE | absent pin |
| 250 | approaches: the advisor caps its reply | got: $(count_of "$SA" 'write nothing else, and reply in at most 10 lines')  want: 1 | DELETE |  |
| 251 | approaches: the advisor's report file | skills/selecting-approaches/SKILL.md: ‘<state>/approaches-<decision>-advisor-report.md‘ | DELETE |  |
| 252 | README: the judges are no longer described as Write-free | README.md: frontmatter omits ‘Edit‘, ‘Write‘, and ‘Agent‘ | DELETE | absent pin |
| 253 | README: a judge writes only its report file | README.md: a judge writes only its report file | DELETE |  |
| 254 | native Codex: a judge writes only its report file | reference/native-codex.md: no file writes except the one report file the prompt names | DELETE |  |
| 275 | judge templates: every report path ends -report.md | got: $(bad_report_paths "${JUDGE_TEMPLATES[@]}")  want:  | KEEP(hooks/cockpit/register.tsx; format contract) | hooks/cockpit/register.tsx REPORT_PATH only lets a judge seat write a `-report.md` path (register.tsx:209); sweep over 19 md templates |
| 279 | walkthrough judge: the report file lies under .dforge | skills/ui-ux/references/walkthrough.md: ‘<checkout>/.dforge/ui-proof-<report name>-report.md‘ | KEEP(register.tsx; format contract) | register.tsx pathsIn: report paths under `<dir>/.dforge` ending `-report.md` |
| 281 | requesting review: the example report file is absolute | skills/requesting-code-review/SKILL.md: REPORT_FILE: .dforge/ | KEEP(register.tsx; format contract) | register.tsx path shape needs an absolute report path (pathShape `whole`) |

### settings-skills.test.sh

DELETE 71, KEEP direct 0, KEEP format contract 2, borderline 2 (borderline rows are in section 3).

| line(s) | test label | markdown file: phrase pinned | verdict | note |
|---|---|---|---|---|
| 27 | brainstorming has a Settings section | skills/brainstorming/SKILL.md: ## Settings | DELETE |  |
| 28 | brainstorming loads the settings when no line is in context | skills/brainstorming/SKILL.md: ‘scripts/dforge-config workflow‘ once before your first question | DELETE |  |
| 29 | brainstorming: instructions outrank a setting, and the gate… | skills/brainstorming/SKILL.md: setting, and no setting removes the approval gate. | DELETE |  |
| 30 | brainstorming: processBias | skills/brainstorming/SKILL.md: plainly holds; doubt resolves to bounded. | DELETE |  |
| 31 | brainstorming: questionStyle | skills/brainstorming/SKILL.md: ‘questionStyle=batched‘: ask all the clarifying questions in one message | DELETE |  |
| 32 | brainstorming: designApproval | skills/brainstorming/SKILL.md: ‘designApproval=whole‘: present every design section in one message and a… | DELETE |  |
| 33 | brainstorming: executionStrategy | skills/brainstorming/SKILL.md: - ‘executionStrategy‘: honoured only for a plan whose Execution line names | DELETE |  |
| 34 | brainstorming: an inline plan is sequential | skills/brainstorming/SKILL.md: records ‘**Execution strategy:** sequential — inline execution‘. | DELETE |  |
| 35 | brainstorming: specReview | skills/brainstorming/SKILL.md: ‘specReview=false‘: after the spec self-review block, skip the User Review | DELETE |  |
| 36 | brainstorming: the path rule points at processBias | skills/brainstorming/SKILL.md: (‘processBias‘ moves where doubt lands; see Settings). The | DELETE |  |
| 37 | brainstorming: the question rule points at questionStyle | skills/brainstorming/SKILL.md: (‘questionStyle=batched‘ asks them all in one message; see Settings) | DELETE |  |
| 40 | brainstorming offers fast mode | skills/brainstorming/SKILL.md: Fast mode, or the full dforge flow? | DELETE |  |
| 41 | brainstorming: the fast Process line | skills/brainstorming/SKILL.md: ‘Process: fast — <why>‘ | KEEP(scripts/lib/fast-mode.sh; format contract) | scripts/lib/fast-mode.sh and hooks/cockpit/lib.ts read a `Process: fast` line (fast-mode.sh:7,17; lib.ts:209) |
| 42 | brainstorming: fastMode=always | skills/brainstorming/SKILL.md: ‘fastMode=always‘: take fast mode without asking | DELETE |  |
| 43 | brainstorming: fastMode=off | skills/brainstorming/SKILL.md: ‘fastMode=off‘: never offer fast mode | DELETE |  |
| 44 | systematic-debugging offers fast mode | skills/systematic-debugging/SKILL.md: Fast mode, or the full dforge flow? | DELETE |  |
| 45 | using-dforge: a fast-mode choice outranks skills | skills/using-dforge/SKILL.md: direct requests, fast mode) outrank skills | DELETE |  |
| 46 | fast-mode.md: no further dforge skill | reference/fast-mode.md: Invoke no further dforge skill for that request. | DELETE |  |
| 47 | brainstorming: no strategy question is asked | skills/brainstorming/references/design-phase.md: Ask nothing. Every plan executes inline, one task after… | DELETE |  |
| 48 | brainstorming: the section rule points at designApproval | skills/brainstorming/references/design-phase.md: with ‘designApproval=whole‘, present every section in o… | DELETE |  |
| 49 | brainstorming: the review gate is skipped by the setting | skills/brainstorming/references/user-review-gate.md: With ‘specReview=false‘ (see Settings), skip this g… | DELETE |  |
| 50 | writing-plans loads the settings when no line is in context | skills/writing-plans/references/execution-line.md: run ‘scripts/dforge-config workflow‘ before you choos… | DELETE |  |
| 51 | writing-plans: instructions outrank a setting | skills/writing-plans/references/execution-line.md: own instructions outrank a setting. | DELETE |  |
| 52 | writing-plans: executionMode fixes the line | skills/writing-plans/references/execution-line.md: line when it is ‘inline‘ or ‘subagent‘. | DELETE |  |
| 53 | writing-plans: an inline plan is sequential | skills/writing-plans/references/execution-line.md: ‘**Parallelism:** sequential — inline execution‘ | DELETE |  |
| 54 | writing-plans: an inline plan asks no strategy question | skills/writing-plans/SKILL.md: otherwise write ‘**Parallelism:** sequential — inline execution‘ and ask | DELETE |  |
| 55 | writing-plans: executionStrategy answers a subagent plan's … | skills/writing-plans/SKILL.md: Under ‘ask‘, ask your human partner one question | DELETE |  |
| 56 | using-git-worktrees checks only the chosen directory | skills/using-git-worktrees/SKILL.md: git check-ignore -q "$LOCATION/" | DELETE | shell snippet quoted in skill text |
| 57 | using-git-worktrees picks pnpm from its lockfile | skills/using-git-worktrees/SKILL.md: if [ -f pnpm-lock.yaml ]; then pnpm install | DELETE | shell snippet quoted in skill text |
| 58 | using-git-worktrees loads the settings when no line is in c… | skills/using-git-worktrees/SKILL.md: run ‘scripts/dforge-config workflow‘ when no such line is in context | DELETE |  |
| 59 | using-git-worktrees: what each value does | skills/using-git-worktrees/SKILL.md: ‘worktree=always‘ creates the worktree without asking, ‘worktree=ne… | DELETE |  |
| 60 | using-git-worktrees: the setting decides only when no prefe… | skills/using-git-worktrees/SKILL.md: If not, the ‘worktree‘ setting decides | DELETE |  |
| 61 | finish-preference: finishAction | reference/finish-preference.md: finishAction | DELETE | `finishAction` is a config key; only the doc mention is pinned |
| 62 | finish-preference: the question offers Ask me then | reference/finish-preference.md: 4. Ask me then: show the finish menu and wait for my answer | DELETE |  |
| 64 | finishing: a recorded choice runs with no menu | skills/finishing-a-development-branch/SKILL.md: **A choice recorded before the run.** | DELETE |  |
| 65 | finishing: an answered record is never re-run | skills/finishing-a-development-branch/SKILL.md: A record whose ‘answer‘ field is set has been used | DELETE |  |
| 66 | finishing: a null base is found without asking | skills/finishing-a-development-branch/SKILL.md: upstream, as Step 3 does, without asking or confirming | DELETE |  |
| 67 | finishing: an upstream base must be another local branch | skills/finishing-a-development-branch/SKILL.md: a local branch other than this one | DELETE |  |
| 68 | finishing: Step 3 qualifies an upstream base as Step 4 does | skills/finishing-a-development-branch/SKILL.md: An upstream names the base only as Step 4 qualifies it | DELETE |  |
| 69 | finishing: a remote prefix is dropped only for a configured… | skills/finishing-a-development-branch/SKILL.md: when no local branch has the whole name and its first se… | DELETE |  |
| 70 | finishing: a fired legacy record is consumed | skills/finishing-a-development-branch/SKILL.md: with no ‘answer‘ or ‘firedAt‘ field | DELETE |  |
| 71 | finish-preference: a fired legacy record is consumed | reference/finish-preference.md: with no ‘answer‘ or ‘firedAt‘ field | DELETE |  |
| 72 | finishing: Step 3 asks nothing for a recorded choice | skills/finishing-a-development-branch/SKILL.md: never ask here: Step 4 says where its base comes from | DELETE |  |
| 73 | finish-preference: a setting's choice has no base branch | reference/finish-preference.md: ‘base‘ is null | DELETE |  |
| 76 | brainstorming: autoRun | skills/brainstorming/SKILL.md: ‘autoRun=off‘: never offer an auto run | DELETE |  |
| 77 | brainstorming offers the auto run | skills/brainstorming/references/auto-run-offer.md: Run the rest unattended? | DELETE |  |
| 78 | brainstorming: the review gate gives way to the Fable review | skills/brainstorming/references/user-review-gate.md: In an auto run (‘scripts/auto-run status‘ exits 0),… | DELETE |  |
| 79 | writing-plans: an auto run asks nothing | skills/writing-plans/references/auto-run-plan.md: nothing in this skill waits on your human partner | DELETE |  |
| 80 | writing-plans: planning choices go to Opus first | skills/writing-plans/references/auto-run-plan.md: ‘dforge:judge-opus‘ first, then the ladder | DELETE |  |
| 81 | writing-plans: the plan step ends with the switch | skills/writing-plans/references/auto-run-plan.md: ‘scripts/auto-run switch‘ and end the turn with ‘Auto … | DELETE |  |
| 82 | using-git-worktrees: a worktree run creates the worktree | skills/using-git-worktrees/SKILL.md: Under ‘isolation worktree‘ in the primary checkout, create the work… | DELETE |  |
| 83 | handoff: the caller owns the clear | skills/handoff/SKILL.md: never runs ‘scripts/auto-run clear‘ itself | DELETE |  |
| 84 | resume-execution: an auto run stops before asking | skills/resume-execution/SKILL.md: scripts/auto-run stop --reason | DELETE |  |
| 85 | finishing: an auto run shows no menu | skills/finishing-a-development-branch/SKILL.md: **Step 4 shows no menu.** | DELETE |  |
| 86 | finishing: the run's base | skills/finishing-a-development-branch/SKILL.md: the base ‘scripts/auto-run status‘ names | DELETE |  |
| 87 | finishing: a detached HEAD never merges in an auto run | skills/finishing-a-development-branch/SKILL.md: there is no merge, so ‘merge‘ keeps | DELETE |  |
| 88 | finishing: failing tests at Step 1 stop the run | skills/finishing-a-development-branch/SKILL.md: (failing tests at Step 1, a merged | DELETE |  |
| 90 | handoff: a design phase writes the Draft line | skills/handoff/SKILL.md: - Draft: ‘<spec path>‘ | KEEP(scripts/lib/darkmem-mirror.mjs; format contract) | scripts/lib/darkmem-mirror.mjs:750 parses `- Draft: \`<path>\`` in latest.md State |
| 91 | handoff: pushes once latest.md is written | skills/handoff/SKILL.md: run ‘scripts/darkmem-sync push‘ and promote | DELETE |  |
| 94 | README: sequential is the default | README.md: defaults to ‘sequential‘, and an inline plan always runs one task after | DELETE |  |
| 95 | README: sequential is not called the default | got: $(grep -cF 'sequentially (the default)' $P/README.md)  want: 0 | DELETE | absent pin |
| 96 | README: an auto run dispatches judge-fable | README.md: An auto run is the exception: it dispatches ‘judge-fable‘ | DELETE |  |
| 98 | codex-tools: routed dispatch never relies on a full-history… | skills/using-dforge/references/codex-tools.md: Never assume a full-history fork accepts ‘model‘ and | DELETE |  |
| 99 | codex-tools: no unconditional fork override claim | got: $(grep -cF 'Full-history forks accept ‘model‘' "$CT")  want: 0 | DELETE | absent pin |
| 100 | codex-tools: session start reconciles, then pulls | skills/using-dforge/references/codex-tools.md: bash <plugin-root>/scripts/darkmem-sync reconcile‘, then | DELETE |  |
| 101 | codex-tools: nothing pushes at the end of a turn | skills/using-dforge/references/codex-tools.md: nothing pushes for you at the end of a turn | DELETE |  |
| 114 | ${file#$P/} names no finish timer | got: $(tr '\n' ' ' < "$file" \| tr -s ' ' \| grep -cE 'finish-choice (arm\|due\|job)\|finishTimeout\|con… | DELETE | loop 113-115 over every skills/*/SKILL.md, references/*.md, reference/*.md and README (one absent-regex per file) |
| 119 | README: tasks carry tests, not implementation code | README.md: carries its interfaces and the complete code of its tests | DELETE |  |
| 120 | README: low-risk tasks are reviewed in groups | README.md: reviewed in groups | DELETE |  |
| 121 | README: two fix rounds | README.md: at most two fix rounds | DELETE |  |
| 122 | README: the full check runs every third wave | README.md: every third wave | DELETE |  |
| 123 | README: judges write their report to a file | README.md: writes its full report to a file | DELETE |  |
| 124 | README: no five-round loop | got: $(grep -cE 'fix rounds 4\|rounds 1 to 3\|and 5, at the BLOCKED' "$P/README.md")  want: 0 | DELETE | absent pin |

### ui-proof.test.sh

No wording pin. Every assertion runs a script and checks its output, exit status or state file, or checks the test-suite hygiene of other test files. (See section 3.)

### ui-ux-skill.acceptance.test.sh

DELETE 8, KEEP direct 0, KEEP format contract 0, borderline 0 (borderline rows are in section 3).

| line(s) | test label | markdown file: phrase pinned | verdict | note |
|---|---|---|---|---|
| 855 | A19: the final review names ui-proof check --base MERGE_BAS… | $fr: ui-proof check --base MERGE_BASE --spec | DELETE | A19 (851-863): whole function is wording only; `flat()` at 850 is used only by A19 and A21 |
| 856 | A19: the finishing skill names ui-proof check --base MERGE_… | $fin: ui-proof check --base MERGE_BASE --spec | DELETE | A19 |
| 859 | A19: the final review says exit 1 stops it | $fr: ui-proof check --base MERGE_BASE --spec.{0,600}[Ee]xit 1 stops | DELETE | A19 (LC_ALL=C matches) |
| 860 | A19: the finishing skill says exit 1 stops (blocks) integra… | $fin: ui-proof check --base MERGE_BASE --spec.{0,1500}[Ee]xit 1.{0,200}(stop\|block) | DELETE | A19 (LC_ALL=C matches) |
| 861-862 | A19: the final review names the auto-run path: prove, check… | $fr: [Ii]n an auto run, run the dforge:ui-ux Prove phase, then check again.{0,300}unverifiable.{0,200}au… | DELETE | A19 |
| 869-870 | A21: acceptance-qa.md says a statement starting with a cont… | $qa: starts with a contract ID.{0,120}is written for the UI test runner.{0,80}profile | DELETE | A21 (865-875): whole function is wording only |
| 871-872 | A21: SKILL.md says a behaviour statement is tagged demo whe… | $skill: tagged ‘demo‘ when the profile names no UI test runner | DELETE | A21 |
| 873-874 | A21: SKILL.md says a behaviour statement is tagged test whe… | $skill: tagged ‘test‘ when the profile names a UI test runner\|‘test‘ when the profile names a UI test r… | DELETE | A21 |

### ui-ux-skill.test.sh

DELETE 27, KEEP direct 0, KEEP format contract 1, borderline 2 (borderline rows are in section 3).

| line(s) | test label | markdown file: phrase pinned | verdict | note |
|---|---|---|---|---|
| 29 | the depth line | skills/ui-ux/SKILL.md: ‘**UI/UX depth:** <touch\|feature\|product> — <why>‘ | DELETE |  |
| 30 | state boards are asked at every depth | skills/ui-ux/SKILL.md: Ask at every depth; recommend yes at | DELETE |  |
| 31 | demo when no UI test runner | skills/ui-ux/SKILL.md: is tagged ‘demo‘ when the profile names no UI test runner | DELETE |  |
| 32 | the gate command | skills/ui-ux/SKILL.md: scripts/ui-proof check --base <ref> [--spec <spec>] | DELETE |  |
| 33 | the pending line | skills/ui-ux/SKILL.md: ‘UI proof: pending — <why>‘ | KEEP(scripts/ui-turn-end.sh; format contract) | scripts/ui-turn-end.sh:43 releases the stop on a last message line `UI proof: pending — <why>` |
| 34 | Accepted by needs the user's words | skills/ui-ux/SKILL.md: Never write ‘**Accepted by:**‘ unless the user said | DELETE |  |
| 35 | Codex runs the scripts by hand | skills/ui-ux/SKILL.md: runs no hooks: run ‘bash <plugin-root>/scripts/ui-lint | DELETE |  |
| 41 | $f guide ships marked unverified | skills/ui-ux/references/platforms/$f.md: **Status:** unverified | DELETE | loop 40-42 over 3 platform guides (`**Status:** unverified`); nothing reads the marker |
| 49 | final review runs the gate | reference/final-review.md: scripts/ui-proof check --base MERGE_BASE --spec <the plan's Spec> | DELETE |  |
| 50 | final review: exit 1 stops it like a red gate | reference/final-review.md: Exit 1 stops the review like a red gate | DELETE |  |
| 51 | final review: the auto-run path proves, then checks again | reference/final-review.md: phase, then check again, and go on when it passes | DELETE |  |
| 52 | final review: only an unverifiable row stops an auto run | reference/final-review.md: auto-run stop --reason "ui proof needs the user" | DELETE |  |
| 53 | final review: the check runs again after the fix wave | reference/final-review.md: step 0.2's ‘ui-proof check‘ again | DELETE |  |
| 54 | finishing runs the gate | $FIN: scripts/ui-proof check --base | DELETE |  |
| 55 | finishing: exit 1 keeps a recorded merge or pr | $FIN: turns a recorded ‘merge‘ or ‘pr‘ into ‘keep‘ | DELETE |  |
| 56 | finishing: the two-option prompt ends on the menu line | $FIN: 1. Prove it first | DELETE |  |
| 57 | finishing: Step 4 keeps a recorded merge after an unproven … | $FIN: When Step 1b's ‘ui-proof check‘ exited 1, ‘merge‘ and ‘pr‘ become ‘keep‘ | DELETE |  |
| 58 | finishing: only an unused recorded choice skips the two-opt… | $FIN: with no ‘answer‘ or ‘firedAt‘ field, or an auto run is bound | DELETE |  |
| 59 | finishing: the auto-run mapping keeps too | $FIN: ‘merge‘ and ‘pr‘ also keep when Step 1b's ‘ui-proof check‘ exited 1 | DELETE |  |
| 60 | finishing: an auto run stops for unverifiable rows | $FIN: auto-run stop --reason "ui proof needs the user" | DELETE |  |
| 61 | final review: step 0 goes on to step 0.2 | reference/final-review.md: say so in one line and go to step 0.2 | DELETE |  |
| 62 | verification: the UI claim row | skills/verification-before-completion/SKILL.md: \| The UI works \| | DELETE |  |
| 66 | the entry point routes UI work | skills/using-dforge/SKILL.md: \| Anything a user sees or does \| dforge:ui-ux \| | DELETE |  |
| 68 | brainstorming runs Shape before acceptance | skills/brainstorming/SKILL.md: invoke dforge:ui-ux before drafting acceptance | DELETE |  |
| 69 | debugging runs touch depth for UI fixes | skills/systematic-debugging/SKILL.md: Run ‘dforge:ui-ux‘ at touch depth | DELETE |  |
| 72 | writing-plans documents the UI/UX line | skills/writing-plans/SKILL.md: **UI/UX:** [only when the spec has a ‘## UI/UX contract‘ | DELETE |  |
| 73 | dispatch names render-before-report for UI tasks | reference/delegated-task.md: a brief that carries ‘## UI/UX contract items‘ is a UI task | DELETE |  |
| 74 | QA writes contract-ID statements for the UI test runner | reference/acceptance-qa.md: is written for the UI test runner the project's UI profile names | DELETE |  |

## 3. EXCLUDED (not counted as DELETE)

Non-pin assertions, by file (script behaviour, structure, fixtures):

- auto-default.test.sh: 98 and 158 (reference files exist and are non-empty: structural); 161-162 (grep other test files for `SD=` / `flat_skill`: hygiene of test code, not markdown); 165-172 (impl-clauses.test.sh run on a copy of agents/impl-*.md with an appended line: behaviour on a fixture the test writes).
- auto-run-skills.test.sh: none; every assertion reads markdown.
- auto-run.test.sh: every assertion runs scripts/auto-run (stdout, exit code, state file); 583-584 and 660 check script output text; 745-774 scan the other `*.sh` suites (test hygiene, no markdown).
- budget-line.test.sh: every assertion except 311-312 runs task-brief or review-package and checks output; fixtures are written by the test.
- ui-proof.test.sh: every assertion runs scripts/ui-proof on a temp repository.
- inline-mode.test.sh: 45-47, 68-71, 77-84, 207, 224 (file existence); 256-258 (links in delegated-task.md resolve: link check); 261-358 (task-brief output on fixtures the test writes).
- inline-only-execution.acceptance.test.sh: A1-A7, A9, A12, A14, A15 and the A16 header checks run plan-lint, task-brief, task-step, next-step, plan-revise, dforge-config and plan.sh functions; 248-249 (agent files absent); 280-285 (ledger_left_inline); 363-378 (A13 runs validate-repository and `claude plugin validate/test`).
- inline-only.acceptance.test.sh: 101-170 (same scripts); 175-176, 181, 192 (files absent); 185 (codex-routing.json value); 217 (ledger_left_inline); 239-240, 245 (manifest keywords and version).
- auto-run-worktree-setting.acceptance.test.sh: 71-228 and 305-375 run scripts/auto-run in throwaway repos; `has` at 73, 75, 77, 81, 103, 112, 119, 154, 194, 197, 310, 318, 326, 359, 372, 375 checks script output, not markdown; 300-302 plugin manifests.
- auto-run-worktree-setting-qa.acceptance.test.sh: t_A1 to t_A12, t_A20, t_A21 run scripts/auto-run.
- antigravity-executor-lane.acceptance.test.sh: A1-A11, A15-A18 (except 842-844) run executors, agy-gate, detect-executors.sh, run-agy-task.sh, plan-lint, plan-revise, lane-breaker on stubs; 356-364 and 757-779 read the data blocks of reference/ladder.md that plan-revise and run-agy-task.sh parse; 701 (agy-policy.json value); A17 (786-806) runs validators.
- ui-ux-skill.acceptance.test.sh: 302, 304 (SKILL.md exists, frontmatter `name: ui-ux`: structural); A4-A18 and A22 run ui-proof, ui-lint, plan-lint, task-brief, lens-route and the hooks.
- ui-ux-skill.test.sh: 25-26 (file exists, `name:` frontmatter), 38 (9 reference files exist), 43 (no macOS/iOS guide: directory listing), 67 (using-dforge SKILL.md at most 5500 bytes: size limit, session-start.sh injects it under a byte budget).
- seats.test.sh: 49-50 (scan of skills/ and reference/ for general-purpose seats without a model: a structural rule with its own fixtures; not counted either way, flag if the judge treats it as a wording pin); 60, 67, 82, 93, 98 (fixtures fed to the test-local `unmodelled` awk); 277-278 (fixture sweep self-test).

Borderline cases, one line each (not in the DELETE count):

- process-roles.test.sh 53-55: set of `{#id}` anchors in criteria/architecture-critique.md; no script reads them, but it is an id structure, not a sentence.
- process-roles.test.sh 201: `### Redundant Tests {#redundant}` heading in criteria/lenses/test-quality.md; spec 2026-11-11 keeps the matching heading assertion in the A12 eval test, so I did not count it.
- settings-skills.test.sh 105-109: keys with `enforcedBy: skill` come from config/schema.mjs, and each must be named by some SKILL.md; config-driven cross-check, not a sentence pin.
- seats.test.sh 280: walkthrough.md tells the controller to copy the judge file to `<report name>.judge.md`; scripts/ui-proof skips `*.judge.md` when listing reports (ui-proof:103), so the name is consumed.
- ui-ux-skill.test.sh 27-28: the `description:` frontmatter of skills/ui-ux/SKILL.md is read by the harness; the check pins words in it.
- inline-mode.test.sh 177: same, for the `description:` of agents/judge-opus.md (phrase `every final whole-branch review`).
- inline-only-execution.acceptance.test.sh 266 and inline-only.acceptance.test.sh 227-228: description of subagent-driven-development SKILL.md must start with "Deprecated".
- inline-only.acceptance.test.sh 172, 173, 237 and auto-run-worktree-setting.acceptance.test.sh 296: wording pins on non-markdown files (config/schema.mjs description string, hooks/cockpit/lib.ts source, JSON manifests); outside the markdown rule.
- antigravity-executor-lane.acceptance.test.sh 706, 708-710, 712, 720: A14 reads git history of docs/superpowers/distilled/constraints.md with `git log -S`; it checks commit ordering, so editing the sentence today cannot break it. (The two current-text pins at 699-700 are counted as DELETE.)
- auto-default.test.sh 175-180 (counted DELETE): pins docs/dforge/notes/2026-10-28-pipeline-smoke.md, a docs note outside skills/reference/criteria/agents; same nature, no script reads it. Drop them from the list if the judge wants only plugin directories.
- auto-default.test.sh 148-160 (counted DELETE): pointer-text pins (`(./implementer-prompt.md)`, `§Recovery` wording). They check the pointer text, not that links resolve, so they are not link-resolver checks.

## 4. Residue after deleting the DELETE rows

No file loses all of its assertions with the verdicts above. None has a literal expected total, TAP plan (`1..N`) or plan-count: every file increments `pass`/`fail` at run time and prints `N passed, M failed`, so no counter or plan edit is needed. The only external count is the per-suite weight map in scripts/test-shards.mjs (matters only if a whole file is removed).

- auto-default.test.sh: leaves the non-pin rows 98, 158, 161-162, 165-172 and the 5 format-contract rows (34, 125, 126, 132, 133). Helpers and variables that nothing uses after the deletion: `lacks` (60-62), `rows_for` (104-109), `pit` (115), B (18), FIN (42), AR (63), PROC (64), ABD (97). Still used: `names` (14-16), `flat`/`says` (55-59), W (40), CIL (96), CIP (95), SDD_REFS (147), TMP/trap (145-146). Header comment lines 2-3 ("each check is a whole instruction") go stale.
- auto-run-skills.test.sh: leaves only 47 (loop over 2 skills) and 102 (format contract). If the judge also downgrades those two, the file has zero assertions: delete the file and remove `'auto-run-skills.test.sh': 10` at scripts/test-shards.mjs:44. skill-view.sh keeps other callers (task-step-text, project-status, waiting-text, review-route, gates-manifest, final-phase tests).
- auto-run-worktree-setting-qa.acceptance.test.sh: delete t_A13 to t_A19 (329-428) and the text helpers `txt`, `between`, `flat`, `has`, `before_in` (311-327, only they use them); edit the statement loop at 495 to `A1 ... A12 A20 A21`; header comment lines 2-6 mention "the texts themselves" and go stale. Leaves t_A1-A12, t_A20, t_A21.
- auto-run-worktree-setting.acceptance.test.sh: `present` (28-31) and `absent` (32-35) helpers stay only if 296 (borderline) stays; otherwise delete them. `has` (36-39) stays (script output). Leaves the CLI checks.
- budget-line.test.sh: delete 311-312 (two lines); nothing else changes.
- inline-mode.test.sh: after deleting, `absent` (39-42), FINAL (16) and most `present` calls are unused; `present` stays for the format-contract rows 129, 132, 139, 145-146, 153. Leaves existence, link-resolution and task-brief behaviour checks.
- inline-only-execution.acceptance.test.sh: blocks A17 (446-451), A18 (455-461) and A19 (464-469) become empty (467 stays only if the format-contract verdict stands; otherwise delete A19 whole); A10 (264-273) keeps only 265-267 (266 borderline); delete 440-441 (helpers of 442) and the `selected` blocks that become empty.
- inline-only.acceptance.test.sh: delete `skill_view` setup lines 187-189 and 219-220 (EP, DT, WP are then unused except DT at 196-198 which are deleted too); `present`/`absent` stay only for the borderline rows 172, 173, 237.
- process-roles.test.sh: leaves 108, 116, 118, 178, 179 (kept) and borderline 53, 201. `lacks` (143-145), `at` (72) and the `g/q/k/l` variables (73-74) become unused; `says`/`flat` (139-142) stay for 178-179; `names` stays for 116, 118.
- seats.test.sh: leaves the KEEP rows, the sweep at 275-281 and the fixture lint 48-98. Delete the prose rows 141, 144, 145 of the loop at 138-146, and narrow that loop (and its rows 142 and 143, which are KEEP for three templates) to task-reviewer, group-reviewer and re-review prompts, otherwise the loop still pins ruling-prompt.md. `lacks` (131-133) is still used by the loop only if 144-145 stay; delete it with them. `count_of` (181) stays (182, 243).
- settings-skills.test.sh: leaves 41, 90 (format contract) and the borderline schema cross-check 105-109 and 9 (node guard). `names` stays.
- ui-ux-skill.test.sh: leaves 25-26, 33, 38, 43, 67 and borderline 27-28. After deleting, `skill_view` (FIN at 47), lines 9-11 (SKILL_VIEW_DIR, trap, source) are unused: delete them.
- antigravity-executor-lane.acceptance.test.sh: delete block A19 (847-854) whole; in A4 delete 415-418 (comment, `lane=` variable, two `has`); in A18 delete 843-844 (and 841 `lane=` plus 842 if the format-contract verdict on 842 is downgraded); in A14 delete 697-700 (`cons`, `entry`, two asserts). `doc()` (159) becomes unused unless 841-842 stay. Header comment lines 6-9 ("text of the shipped references") go stale.
- ui-ux-skill.acceptance.test.sh: delete t_A19 (851-863), t_A21 (865-875) and `flat()` (850); edit the id list at 925 to drop `A19 A21`.



---

# PART g6a

# g6a: wording pins in 27 test files (plugins/dforge/tests)

Method: every test file was searched for reads of markdown under skills/, reference/, criteria/, agents/, README. Each hit was read and each pinned phrase was grepped against scripts/, hooks/, config/ for a consumer. Counting: one assertion per `check/has/says/names/present/absent` source line; a loop over a phrase list counts each phrase; a loop over files counts once (runtime multiplicity noted). Line numbers are the current file lines.

Consumer facts established:
- scripts read reference/ladder.md only through its fenced blocks (assignment, escalation, reserve, retired, agy-assignment, agy-successor, agy-timeout, gate, codex-judge): scripts/lib/plan.sh `ladder_block`, plan-lint, plan-revise, run-agy-task.sh, run-codex-task.sh, run-codex-review.sh. No script reads ladder.md prose.
- scripts/session-start.sh `cat`s skills/using-dforge/SKILL.md whole into the hook payload (size matters, no sentence is read).
- No script reads or parses: reference/executor-lane.md, delegated-task.md, native-codex.md, external-task-recovery.md, final-review.md, session-budget.md, auto-run.md; skills/** (any SKILL.md or references/*.md); agents/*.md bodies (task-step:764 tests only that agents/<name>.md exists); README.md; gates.md or gates-template.md (grep for `gates.md`, `Known-flaky`, `Evidence:` in scripts/hooks/config returns nothing). Scripts mention these docs only as pointer strings in their own messages.

## 1. Totals per file

| File | DELETE | KEEP-by-consumer / structural (in the wording-adjacent area) | Test file becomes empty? |
|---|---|---|---|
| ladder.test.sh | 11 | many (fenced blocks, consumer: ladder_block users) | no |
| agy-gemini-first.acceptance.test.sh | 16 (A12: 14, A13: 2) | A1-A4 (consumers: run-agy-task.sh), A5-A11, A14 (script output) | no |
| distilling-docs.test.sh | 44 | 2 (existence) | 2 existence checks remain |
| delegated-suite.test.sh | 63 | 0 | YES, whole file |
| final-phase.test.sh | 79 sites (92 at runtime: the line 50 check runs once per each of 14 files) | 0 | YES, whole file |
| gates-manifest.test.sh | 66 | 2 existence + 1 template format check (see borderline) | 3 remain |
| impl-clauses.test.sh | 5 sites (x16 agents = 80 at runtime) plus line 42 that rides with them | 0 | YES (see note) |
| fleet.test.sh | 5 sites (118: x16 at runtime) | frontmatter and structural checks | no |
| executors.test.sh | 1 | rest are script output / data | no |
| executor-recovery.test.sh | 6 | rest are script behaviour | no |
| codex-review.test.sh | 3 | rest script behaviour | no |
| hook.test.sh | 8 (1 + 6 + 1) | 216 size cap (consumer: session-start.sh payload cap) | no |
| dforge-config.test.sh | 1 | | no |
| dforge-dir.test.sh | 1 | | no |
| agy-gate, ci-mirror, codex-client, codex-gate, context-size, darkmem-sync, detect, dforge-migrate, dforge-state, executor-recovery (other), executor-session, finish-choice, impl-stop-gate, in-flight | 0 | no markdown wording read (they run scripts / fixtures) | n/a |

TOTAL DELETE (source-line/phrase count): 11 + 16 + 44 + 63 + 79 + 66 + 5 + 5 + 1 + 6 + 3 + 8 + 1 + 1 = 309 (plus impl-clauses line 42 as a rider). Files affected: 14.
Runtime multiplicity is higher: impl-clauses 5x16 = 80, fleet 118 x16 = 16, final-phase line 50 x14.

## 2. Tables

### ladder.test.sh (11 DELETE)
Helper `prose()` line 69 and comment 67-68 exist only for 70-79: delete with them.

| Lines | Label | File / phrase | Verdict | Note |
|---|---|---|---|---|
| 69 (helper) | `prose()` | ladder.md prose grep | DELETE | helper used only by 70-79 |
| 70 | Rule S splits a Claude task at reducible 6 | ladder.md: "If `reducible >= 6`, or if `spec = 3`..." | DELETE | plan-lint implements Rule S in code, does not read this sentence |
| 71 | a Codex plan keeps Rule S at reducible 4 | ladder.md prose | DELETE | |
| 72 | the cap is derived from reducible 5 | ladder.md prose | DELETE | |
| 73 | the old cap derivation is gone | ladder.md absent phrase | DELETE | |
| 74 | a total of 9 means the gate was skipped | ladder.md prose | DELETE | |
| 75 | Opus takes totals 6 to 8 | ladder.md prose | DELETE | |
| 76 | a relaxed-gate plan fails an older plan-lint | ladder.md prose | DELETE | |
| 77 | the lane envelope no longer derives from reducible 3 | ladder.md absent phrase | DELETE | |
| 78 | the lane envelope names max_score | ladder.md prose | DELETE | |
| 79 | the light Codex judge covers totals 0 to 8 | ladder.md prose | DELETE | |
| 80 | impl-opus-high is dispatched for scores 6 to 8 | agents/impl-opus-high.md description sentence | DELETE | borderline: the description is harness-visible text but no script reads this sentence (see section 3) |
| 31, 35, 47-60, 64, 92-94, 98-247 | tables / graph / counts | ladder.md fenced blocks, agents/*.md existence | KEEP (plan-lint, plan-revise, run-*-task.sh via ladder_block) | |

### agy-gemini-first.acceptance.test.sh (16 DELETE)
`a12()` (lines 324-351, with comment header at 324) is wholly pins: delete the function. Also delete `LANE_DOC` (line 20), remove 12 from the dispatch loop at line 403 (`for t in 1 2 ... 14`), and the executor-lane.md mention in header comment lines 5-6. Keep the `section()` helper (55-57); `agy_error_section` (365) uses it on script output.

| Lines | Label | File / phrase | Verdict | Note |
|---|---|---|---|---|
| 330 | A12: When a run fails has one Capability row | executor-lane.md `## When a run fails` table | DELETE | inside a12 |
| 331 | capability row names the claude- successor | same | DELETE | |
| 332 | capability row reads the refreshed gate (--refresh) | same | DELETE | |
| 333 | capability row tests fallback=off | same | DELETE | |
| 334 | capability row hands back now (HANDBACK) | same | DELETE | |
| 335 | capability row records the fallback-quota handback | same | DELETE | lane-breaker reads HANDBACK in the ledger, not in this doc |
| 336 | capability row covers the session-end case | same | DELETE | |
| 339 | resume table has one row for the fallback refusal | `## When the resume itself fails` | DELETE | |
| 340 | that row hands back now | same | DELETE | |
| 341 | that row records the fallback-quota handback | same | DELETE | |
| 342 | that row covers the session-end case | same | DELETE | |
| 343 | that row is keyed on exit 2 | same | DELETE | |
| 347-348 | run table's transient row exempts a marked quota | `| Transient` row | DELETE | |
| 349-350 | resume table's transient row exempts a marked quota | same | DELETE | |
| 360 | ladder's agy-assignment section names the note | ladder.md `### Agy assignment` prose | DELETE | no script reads the section |
| 361 | and ties it to rows 3 to 8 | same | DELETE | |
| 118-119, 124-127, 133-151 | A1-A4 | ladder.md fenced blocks agy-assignment/successor/timeout | KEEP (scripts/run-agy-task.sh lines 107-119) | |
| 355-358 | A13 note exists / tracked / clean | docs note | EXCLUDED, see section 3 | |
| 372-400 | A14 | `## Agy error` section of the report run-agy-task.sh writes | KEEP (script output) | |

### distilling-docs.test.sh (44 DELETE, 2 KEEP)
Helper `present()` (16-19) is used only by pins: delete with them. No script reads skills/distilling-docs/** (scripts/darkmem-sync is only named in the skill text).

| Lines | Label | Target / phrase | Verdict |
|---|---|---|---|
| 25-27 (loop, 4 phrases) | names distilled/{constraints,gotchas,reference,rejected}.md | SKILL.md | DELETE |
| 28 | every entry carries Source | SKILL.md `Source:` | DELETE |
| 32, 33, 34, 35, 36, 37 | eligibility paths and the three conditions | SKILL.md | DELETE (6) |
| 41, 42, 43 | never-eligible rules | SKILL.md | DELETE (3) |
| 46 | dispatches judge-opus | SKILL.md | DELETE |
| 47-49 (loop, 3 phrases) | verdict CARRIED/MISSING/DISTORTED | SKILL.md | DELETE |
| 50, 51, 52 | enumerate first, commit before judging, no Bash | SKILL.md | DELETE (3) |
| 55, 56, 57 | one removal commit, never squashed, waves bounded | SKILL.md | DELETE (3) |
| 62-69 | darkmem: eight phrases | SKILL.md | DELETE (8) |
| 78, 79 | judge enumerates / maps | references/distil-judge.md | DELETE (2) |
| 80-82 (loop, 3 phrases) | judge contract verdicts | distil-judge.md | DELETE |
| 83, 84, 85, 86, 87, 88, 89 | judge contract phrases | distil-judge.md | DELETE (7) |
| 21-22 | exists: SKILL.md | structural | KEEP (existence) |
| 72-73 | exists: distil-judge.md | structural | KEEP (existence) |

Without the pins the file holds two existence checks. Recommend deleting the whole file; the judge decides whether two existence checks are worth keeping.

### delegated-suite.test.sh (63 DELETE: every assertion, whole file)
All assertions grep reference/delegated-task.md (sections via sed ranges), skills/executing-plans/SKILL.md, or reference/native-codex.md. Scripts (task-step, next-step) print their own `suite:` lines and cite delegated-task.md only as a pointer; none reads the doc. The helper functions (18-23: in_loop, by_hand, by_hand_flat, inline_flat, in_loop_flat, has) exist only for these pins.

| Lines | Verdict |
|---|---|
| 25-30, 32-40, 42-56, 57-59, 60-64, 65-78, 80-84, 86-88 (`has` calls, 61 assertions) | DELETE |
| 79 (check: the seat's text no longer described as run verbatim) | DELETE |
| 90 (check: loop steps still run `date +%s` once) | DELETE |
| 91 (check: native-codex.md carries no suite-run call) | DELETE |

Count: 25-30 (6) + 32-40 (9) + 42-59 (18) + 60-64 (5) + 65-78 (14) + 79 (1) + 80-84 (5) + 86-88 (3) + 90, 91 (2) = 63. Delete the whole file.

### final-phase.test.sh (79 sites DELETE: whole file)
Every assertion pins a sentence in skills/subagent-driven-development, executing-plans, finishing-a-development-branch, handoff, execute-choice.md, reference/final-review.md, session-budget.md, auto-run.md or README.md. Scripts only point at these docs. Helpers `names` (18-20), `flat` (54), `says` (55-57) and the `skill_view`/`sdd-text.sh` sourcing (11, 23) exist for these pins (skill-view.sh and fixtures/sdd-text.sh are still used by other test files; do not delete them).

| Lines | Content | Verdict |
|---|---|---|
| 29-48 (20 names/check) | handoff/final-phase wording in SDD, EP, H, FR, FIN, README, SDD_SETUP; 48 absence of "spec-to-plan" in handoff | DELETE |
| 49-51 (loop over 14 files; check at 50) | absence of "--final says handoff" regex | DELETE (1 site, x14 at runtime) |
| 58-67 (10 says/check) | finishing, session-budget, handoff, final-review, README wording; 61 is an awk over FIN sections | DELETE |
| 69-73 (5) | auto-run.md wording | DELETE |
| 74-77 (4) | handoff switch, depth-route, ledgered depth | DELETE |
| 78-83 (6) | final-review.md depth table rows | DELETE (no script parses the table; depth-route / lens-route own the real depth logic) |
| 84-99 (16) | final-review.md and finishing wording (integration check, suite-run, ci-mirror) | DELETE |
| 103-119 (17) | execute-choice.md Wait for CI section and finishing's CI line | DELETE |

### gates-manifest.test.sh (66 DELETE)
No script parses gates.md, gates-template.md or running-gates SKILL.md. Helpers `present`, `absent`, `present_flat` (20-31), `says_flat` (163), `skill_view` sourcing (10-12) and the `FIN`, `VBC`, `FR` variables (142, 143, 164, plus 170-172) exist only for pins. Remove them with the pins.

| Lines | Content | Verdict |
|---|---|---|
| 36 | manifest path in SKILL.md | DELETE |
| 39-41 (loop, 2 phrases) | required fields | DELETE |
| 42-44 (loop, 9 phrases) | optional fields | DELETE |
| 45 | "nine optional fields" | DELETE |
| 49-51 (loop, 4 phrases) | evidence values | DELETE |
| 52, 53, 54 | evidence default, Green text, exit 0 | DELETE |
| 58 | branch level | DELETE |
| 61-65 | first red, Known-flaky, manifest defect, merge-base, silent skip | DELETE (5) |
| 68, 69, 70 | merged caller names base; finishing PRE_MERGE; closing-a-milestone `all` | DELETE (3) |
| 71-77 | Tier and Budget wording | DELETE (7) |
| 134-140 | gates-template.md phrases (Setup:, Evidence: image, Copy the block..., nine optional, Tier: task, Tier: sweep, Budget: 900s) | DELETE (7) |
| 145-154 | finishing-a-development-branch wording | DELETE (10) |
| 159 | verification-before-completion never names running-gates | DELETE |
| 165-169 | final-review.md ci-mirror wording | DELETE (5) |
| 170-173 | ci-mirror before gates order (check at 173) | DELETE (1) |
| 174-179 | running-gates SKILL.md wording | DELETE (6) |
| 33-34, 80-81 | file exists | KEEP (structural) |
| 83-132 | awk validates gates-template.md against the documented field set | EXCLUDED, see section 3 |

### impl-clauses.test.sh (5 sites DELETE)
Pins clause sentences in agents/impl-*.md (loop over 16 files, lines 22-41). No script reads agent bodies.

| Lines | Label | Phrase | Verdict |
|---|---|---|---|
| 25-26 | the scope-limit clause | "Change only what the brief asks for..." | DELETE |
| 27-28 | write a general solution | "Write a general solution..." | DELETE |
| 29-30 | report a test that looks wrong | "When a test looks wrong..." | DELETE |
| 31-32 | existing tests are immutable | "Never edit or delete an existing test..." | DELETE |
| 33-40 | the three clauses follow the scope clause in order | awk on line order | DELETE |
| 42 | the fleet has sixteen implementers | count of files | rider: structural, but its counter `n` exists only for the loop; the exact agent list is already asserted at fleet.test.sh:43 |

Deleting 22-41 leaves only line 42. Recommend deleting the whole file; helpers `flat`, `says` (16-19) go with it.

### fleet.test.sh (5 sites DELETE)
| Lines | Label | Target | Verdict |
|---|---|---|---|
| 92 | judge writes only the report file | judge-*.md body "write only the report file" | DELETE |
| 93 | no longer says it cannot modify files | judge body absence | DELETE |
| 94 | its reply is not its whole verdict | judge body absence | DELETE |
| 95 | the description does not call it read-only | judge description 'Read-only' | DELETE (borderline, section 3) |
| 114-119 (comment 114-115; loop 116-119; check 117-118) | carries the end-of-turn rule | impl-*.md "Your final message ends your turn" | DELETE (x16 at runtime; whole loop) |
| 43, 49, 56, 65-84, 91, 96-98, 105-111 | name set, frontmatter fields, tools, disallowedTools, preloaded skills, isolation, ASCII | structural | KEEP |

### executors.test.sh (1 DELETE)
| Lines | Label | Target | Verdict |
|---|---|---|---|
| 200-203 (comment 200-201; check 202-203) | no prose describes the retired --json error stream | README.md, reference/executor-lane.md: absence of two phrases | DELETE |
| 126-127 | shipped agy block exists in the ladder | ladder.md fenced block name | KEEP (ladder_block consumers) |

### executor-recovery.test.sh (6 DELETE)
Delete the comment at 265, `LOOP` (266), and the two helpers `present` and `absent` (276-283), and `REC` (284). Both helpers are used only by 285-286 here.

| Lines | Label | Target | Verdict |
|---|---|---|---|
| 267-268 | the loop tells the controller to release the worktree | delegated-task.md | DELETE |
| 269-270 | the release resolves the wrapper through the registry | delegated-task.md | DELETE |
| 271-272 | a HANDBACK reconciles instead of releasing | delegated-task.md | DELETE |
| 273-274 | a finished HANDBACK task is released | delegated-task.md | DELETE |
| 285 | recovery guide resolves wrapper through the registry | external-task-recovery.md | DELETE |
| 286 | recovery guide no longer hardcodes the Codex wrapper | external-task-recovery.md | DELETE |
| 262-263 | second task refused for ownership | script stderr | KEEP (behaviour) |

### codex-review.test.sh (3 DELETE)
Delete comment 342-343, `SDD`/`sdd` (344-345), comment 348-349. Keep the `present` helper at line 59 (used on script output throughout).

| Lines | Label | Target | Verdict |
|---|---|---|---|
| 346 | the risk-3 caller names the runner | delegated-task.md "run-codex-review.sh" | DELETE |
| 347 | the risk-3 caller defers on FAILED | delegated-task.md "TIMEOUT or FAILED" | DELETE |
| 350 | the risk-3 caller does not redispatch a decided seat | delegated-task.md "never re-dispatch the Codex seat" | DELETE |

### hook.test.sh (8 DELETE)
| Lines | Label | Target | Verdict |
|---|---|---|---|
| 39-40 | using-dforge states the working-directory contract | skills/using-dforge/SKILL.md phrase | DELETE |
| 218-227 (comment 218-219, ENTRY 220, loop 221-227, 6 phrases) | routing names dforge:{project-status, running-gates, distilling-docs, test-simplifier, planning-a-product, closing-a-milestone} | using-dforge/SKILL.md | DELETE (6) |
| 228-232 | gates row is worded by workflow position | using-dforge/SKILL.md "Before the final review or merge" | DELETE |
| 215-217 | entry point at most 5,500 bytes | using-dforge/SKILL.md size | KEEP (structural size limit; session-start.sh shares a 10,000 character payload cap) |
| 41-45 | additionalContext names plugin root / entry skill | hook JSON output | KEEP (script output) |

### dforge-config.test.sh (1 DELETE)
| Lines | Label | Target | Verdict |
|---|---|---|---|
| 374-376 (comment 374, `groups` 375, check 376) | the README's tab hotkeys cover every settings group | README.md "press `1` to `N` to switch" | DELETE (`groups` is used only by 376) |
| 371 | finishAction title and description | config/schema.mjs | KEEP (config, not markdown) |

### dforge-dir.test.sh (1 DELETE)
| Lines | Label | Target | Verdict |
|---|---|---|---|
| 140-141 (comment 140, check 141) | codex-tools: names the older-layout check | skills/using-dforge/references/codex-tools.md "an `older layout` line" | DELETE |

## 3. EXCLUDED / borderline (one line each)

- ladder.test.sh:80 (counted DELETE): pins a sentence in an agent's description frontmatter. The harness reads the description as routing text, but no script reads this sentence; the judge may re-class as KEEP-structural.
- fleet.test.sh:95 (counted DELETE): same reasoning, absence of "Read-only" in a judge description.
- fleet.test.sh:107-108 and 85-86 (KEEP): `does not preload test-driven-development` greps the whole agent file, but its intent is the frontmatter `skills:` list consumed by the harness; `preloads verification-before-completion` is frontmatter too.
- fleet.test.sh:83-84 (KEEP): `tools:` / `disallowedTools` frontmatter, consumed by the harness.
- gates-manifest.test.sh:83-132 (not counted): an awk validator that checks gates-template.md against the field set, evidence values, Tier and Budget formats. It asserts no sentence, but no script consumes gates.md, so it guards the example only. Judge's call; if the pins are deleted this is the only remaining content-based check.
- agy-gemini-first.acceptance.test.sh:355-358 (not counted): the calibration note exists, is tracked, and has no uncommitted change. Structural existence/link check for a note the ladder prose names, but 358 fails on any dirty working tree (environment-sensitive). After 360-361 are deleted, nothing consumes the note.
- hook.test.sh:221-232 (counted DELETE): described as a reachability check (a cold session must see these skills in the entry point). It is still presence-of-wording in SKILL.md with no script reader.
- impl-clauses.test.sh:42 and fleet.test.sh:43 (KEEP): file-set checks, structural.
- ladder.test.sh:35, 98, 176 (KEEP): row counts of fenced blocks that ladder_block consumers parse.
- executors.test.sh:183-184 (KEEP): fixture JSON equals the shipped registry entry (data, not markdown).
- codex-client.test.sh:66 criteria/codex-review-schema.json and agy-gate/codex-gate reads of reference/*.json (KEEP): JSON config consumed by scripts.
- dforge-migrate.test.sh (KEEP, all): `dr-forge:` prefix checks run the migrate script against fixture plans written to a temp dir; behaviour, not pins.
- context-size.test.sh, in-flight.test.sh, finish-choice.test.sh, impl-stop-gate.test.sh, ci-mirror.test.sh (KEEP): markdown reads are fixtures the test writes and feeds to scripts.
- agy-gate.test.sh:159 (KEEP): `reference:"reference/executor-lane.md"` is a string in a fixture registry entry, not a read of the doc.

## 4. Per-file: empty after deletion? counters? other edits

No file has a literal expected total, TAP plan or `1..N`. All use dynamic `pass`/`fail` and print `%d passed, %d failed` (agy acceptance also prints skipped). No counter edits are needed.

| File | Empty after deletion? | Counter / plan | Other edits |
|---|---|---|---|
| ladder.test.sh | no | dynamic (249) | remove `prose()` 67-69 |
| agy-gemini-first.acceptance.test.sh | no | dynamic (407) | remove `a12` 324-351 and `LANE_DOC` line 20; dispatch loop line 403 must drop 12 (else `a12: command not found` when 12 is selected); header comment lines 3-6 |
| distilling-docs.test.sh | no (2 existence checks) | dynamic (91) | helper `present` 16-19 |
| delegated-suite.test.sh | YES (all 63) | dynamic (93) | delete whole file; check no CI/runner list names it (not verified) |
| final-phase.test.sh | YES (all 79) | dynamic (121) | delete whole file; check no CI/runner list names it (not verified) |
| gates-manifest.test.sh | no (3 remain) | dynamic (181) | remove helpers 20-31, 163, `skill_view` source 10-12, FIN/VBC/FR vars |
| impl-clauses.test.sh | YES except line 42 | dynamic (44) | recommend deleting whole file |
| fleet.test.sh | no | dynamic (121) | label at line 43 says "21 expected agents" but EXPECTED has 19 names; header line 2 says nineteen (stale label, adjacent finding) |
| executors.test.sh | no | dynamic (208) | none |
| executor-recovery.test.sh | no | dynamic (288) | helpers 276-283 |
| codex-review.test.sh | no | dynamic (352) | none |
| hook.test.sh | no | dynamic (230) | `ENTRY` var removed with its block |
| dforge-config.test.sh | no | dynamic (378) | `groups` var 375 |
| dforge-dir.test.sh | no | dynamic (143) | none |

Adjacent findings: (1) fleet.test.sh:43 label says 21 agents while the expected list and header say 19. (2) agy acceptance a13 line 358 fails on any uncommitted edit to the note, so it is sensitive to a dirty working tree. (3) Cannot confirm from this scope whether any CI manifest, shard list or runner script names delegated-suite.test.sh, final-phase.test.sh or impl-clauses.test.sh; check before deleting them whole.



---

# PART g6b

# g6b wording-pin audit (plugins/dforge/tests, 27 files)

All paths below are relative to /root/repositories/darkraise-ai-plugins/plugins/dforge. Line numbers are per file (exact, taken from `awk FNR`). Every test file keeps a plain `pass`/`fail` counter and prints `"%d passed, %d failed"` at the end; none has a TAP plan (`1..N`), a literal expected total or a plan-count, so deleting assertions needs no count edit anywhere. The only external list is `scripts/test-shards.mjs` (shard weights per file, see section 4).

Consumer check done before classifying: `rg` over scripts/, hooks/, config/ for the doc names and the pinned strings. Scripts that mention `executor-lane.md`, `delegated-task.md`, `native-codex.md`, `ladder.md prose`, `using-dforge` only cite the name inside an error/usage message, or (using-dforge SKILL.md) `session-start.sh` `cat`s the whole file into the hook context without parsing it. The only markdown text that scripts actually parse is the fenced blocks of `reference/ladder.md` (`ladder_block` in scripts/lib/plan.sh, run-codex-task.sh, run-agy-task.sh, run-codex-review.sh, plan-revise, task-step) and the ledgers/plans/registers/gates that tests write to a temp dir.

## 1. Totals

| File | DELETE | KEEP / other |
|---|---|---|
| lane-breaker.test.sh | 8 | script-output checks KEEP (lane-breaker) |
| lanes.test.sh | 58 | ladder.md fenced blocks KEEP (ladder_block, run-codex-task.sh, run-agy-task.sh, run-codex-review.sh, task-step) |
| lock.test.sh | 0 | all script behaviour |
| migrate-skill.test.sh | 16 | 2 structural (exists, `name:` frontmatter) |
| native-routing.test.sh | 8 | select-native-tier.sh behaviour KEEP |
| parallel-grouping.test.sh | 12 | none (whole file is pins) |
| polluter.test.sh | 0 | script behaviour |
| readme-unattended.test.sh | 9 | none (whole file is pins) |
| repo-audit.test.sh | 0 | script output |
| roots.test.sh | 0 | lib/roots.sh, dforge-path |
| run-agy-task.test.sh | 0 | wrapper behaviour; scripts/agy-task-contract.md is wrapper payload, see EXCLUDED |
| run-codex-task.test.sh | 0 | same |
| sdd-references.test.sh | 0 | structural (see EXCLUDED) |
| skill-size.test.sh | 0 | structural |
| skill-split-planning.test.sh | 0 | structural |
| skill-view.sh | 0 | helper only, no assertions |
| snapshot.test.sh | 0 | lib/snapshot.sh output |
| suite-run.test.sh | 0 | suite-run output |
| task-state.test.sh | 0 | lib/task-state.sh |
| test-simplifier.test.sh | 55 | 4 exists + test-profile output KEEP |
| turn-end.test.sh | 2 | turn-start/turn-end/session-start/auto-run behaviour KEEP |
| ui-hooks.test.sh | 0 | hooks + hooks.json config |
| ui-lint.test.sh | 0 | ui-lint on fixtures |
| waiting-text.test.sh | 20 | none (whole file is pins) |
| wave.test.sh | 0 | scripts/wave behaviour |
| working-directory.test.sh | 3 | script behaviour KEEP |
| worktree-instructions.test.sh | 2 | 2 executed-doc-example checks KEEP/EXCLUDED |
| **Total** | **193** | **11 files affected** |

## 2. Per-file tables

### lane-breaker.test.sh (8 DELETE)

Consumer note: scripts/lane-breaker reads the ledger only; the executor-lane.md / ledger.md / SKILL.md / delegated-task.md texts are not read by any script (scripts only cite them in comments).

| Line(s) | Label | Markdown + phrase | Verdict | Note |
|---|---|---|---|---|
| 84-85 | the lane reference records a handback before review where the breaker reads it | reference/executor-lane.md: `Task <N>: implementer inline (assigned; base <sha7>; executor <id> HANDBACK - <reason>)` | DELETE | the breaker reads the ledger, not this doc |
| 119 | dispatch runs the breaker before the gate | reference/executor-lane.md: `bash "<plugin-root>/scripts/lane-breaker" PLAN_FILE agy` | DELETE | |
| 120 | dispatch writes the plan line | executor-lane.md: `Plan: executor agy off - unreliable (2 handbacks)` | DELETE | |
| 121 | a tripped breaker dispatches the Implementer agent | executor-lane.md: `executor agy unavailable - off for this plan: ...` | DELETE | |
| 122 | the ledger grammar holds the plan line | skills/subagent-driven-development/references/ledger.md: `Plan: executor <id> off - unreliable (<k> handbacks)` | DELETE | |
| 123 | recovery reads the plan line through the breaker | ledger.md: `scripts/lane-breaker` | DELETE | |
| 124 | after compaction the breaker keeps the lane off | skills/subagent-driven-development/SKILL.md: `scripts/lane-breaker` | DELETE | |
| 125 | the delegated loop points at the breaker | reference/delegated-task.md: `scripts/lane-breaker` | DELETE | |

KEEP: lines 45-113 (all `check` on lane-breaker output/exit codes against temp ledgers).

Whole-block/helper: lines 114-125 (the "documents that tell a controller to run it" block) go whole, together with the `present()` helper (17-20) and the `EL`, `LG`, `SK`, `DT` constants (115-118). Nothing else uses them.

### lanes.test.sh (58 DELETE)

KEEP (consumer = ladder.md fenced blocks read by lib/plan.sh `ladder_block`, run-codex-task.sh, run-agy-task.sh, run-codex-review.sh, plan-revise, task-step): 41-77, 82-144, 146-199, 215-219, 221-346, 397-410 (block data checks), 428-432 (agy-policy.json trust vs. record, see EXCLUDED). `ladder.md` headings are NOT read by any script (`ladder_block` matches only the ```` ```TAG ```` fence line).

| Line(s) | Label | Markdown + phrase | Verdict | Note |
|---|---|---|---|---|
| 79 | executor-lane lists the max_score condition | reference/executor-lane.md: ``- `total <= max_score`,`` | DELETE | |
| 80 | the README no longer derives the lane from reducible 3 | README.md: absence of ``Rule S caps `reducible` at 3`` | DELETE | |
| 206 (cmd at 205) | no doc says a background call is unbounded | executor-lane.md, delegated-task.md, skills/writing-plans/SKILL.md: absence of `not bound by` / `with no timeout` | DELETE | |
| 208 (cmd at 207) | executor-lane states the timeout formula for the wrapper and both runners | executor-lane.md: `(rung\|row bound + 120) × 1000 ms` x3 | DELETE | |
| 213 (cmd at 212) | executor-lane keeps piped Node spawns off the Codex lane | executor-lane.md: `Tasks whose tests spawn piped Node child processes stay on the Claude lane` | DELETE | |
| 349-350 | ladder.md has a lane-gate subsection for each executor | ladder.md headings `### The (Codex\|agy) lane gate` | DELETE | headings are not parsed |
| 351 | the single, executor-neutral lane-gate heading is gone | ladder.md heading absence | DELETE | |
| 352-353 | ladder.md gives agy its assignment, successor and timeout subsections | ladder.md `### Agy (assignment\|successor\|timeout)` headings | DELETE | |
| 354-355 | the agy gate subsection states why its floor is 0 | ladder.md: ``agy-lane-gate` has a floor of 0 because`` | DELETE | |
| 356-357 | ladder.md names the 3-8 calibration note | ladder.md: `docs/dforge/notes/2026-11-03-agy-calibration-3-8.md` | DELETE | |
| 360-361 | ladder.md no longer says agy rows 3 to 8 mirror the native table | ladder.md absence of `Totals 3 to 8 mirror ...` | DELETE | |
| 442-446 | executor-lane outside the Codex sections no longer says: <phrase> | executor-lane.md (loop of 11 phrases: `codex-timeout`, `codex-assignment`, `codex-successor`, `## Codex error`, `codex lane is off`, `run-codex-task.sh`, `Codex ran`, `Codex finished cleanly`, `codex quota exhausted`, `Codex read the findings`, `Codex runs every task turn`) | DELETE x11 | helper `outside()` at 439 goes with it |
| 447-448 | the exit-2 text is executor-neutral | executor-lane.md: ``\`<id> lane is off for this session (<reason>)\` `` | DELETE | |
| 449 | the registry table lists priority | executor-lane.md: ``\| `priority` \|`` row | DELETE | registry data is reference/executors/*.json, read by scripts/executors; the table is prose |
| 450 | the lane reference has a Per-executor: agy section | executor-lane.md heading `## Per-executor: agy` | DELETE | no script reads the heading |
| 453-457 | Per-executor: agy says: <phrase> | executor-lane.md section (loop of 8: `unsandboxed`, `fingerprints cover only the linked worktree and its refs`, `fixed pointer sentence`, ``keeps a cached `reason=quota` ``, `git for-each-ref`, `finished_reason`, ``efforts `low`, `medium` and `high` ``, `lane-breaker`) | DELETE x8 | `agy_sec` (452) and `section()` (440) reused at 470-484 |
| 459-460 | the piped Node rule lives in the Codex section | executor-lane.md `## Per-executor: codex` | DELETE | |
| 461-462 | reaped is explained in the Codex section | executor-lane.md: ``phase` and `reaped` as **evidence, not proof**`` | DELETE | |
| 465-467 | the README names <phrase> | README.md (loop of 5: `Antigravity`, `scripts/run-agy-task.sh`, `scripts/agy-gate`, `scripts/lane-breaker`, `executors ranked`) | DELETE x5 | |
| 470-471 | capability row hands back when agy successor is Claude and fallback is off | executor-lane.md `\| Capability` row: `executor agy HANDBACK - fallback quota until <iso>` | DELETE | |
| 472-473 | the resume table hands back on the wrapper's fallback refusal | executor-lane.md table row | DELETE | |
| 474-475 | no table row carries a bare `<iso\|session end>` template | executor-lane.md absence | DELETE | |
| 476-477 | neither transient row retries a quota the wrapper marked | executor-lane.md `\| Transient` rows: `is not retried` x2 | DELETE | |
| 478-479 | an agy Executor line may name a successor rung | executor-lane.md: `outside its assignment and successor blocks` | DELETE | |
| 480-482 | Per-executor: agy's quota bullet says: <phrase> | executor-lane.md agy section (loop of 7: `separate limits`, `Individual quota reached`, `Resets in`, `fallback=off`, `fallback_resets_at=`, `marked=none`, `next gate call`) | DELETE x7 | |
| 483-484 | the agy section no longer says Antigravity publishes no reset time | executor-lane.md absence | DELETE | |
| 485-486 | the README no longer keeps the lane off for the session on every quota | README.md absence | DELETE | |
| 487-488 | the README says a Claude quota closes only the Claude fallback | README.md: `closes only the Claude fallback` | DELETE | |
| 489 | the README has a 4.11 migration section | README.md heading `## Migrating to 4.11` | DELETE | |
| 490-491 | the 4.11 migration section says old Claude agy lines fail plan-lint | README.md: ``fails `plan-lint` `` | DELETE | |
| 492-493 | the README no longer says agy takes totals 3-8 on Claude Sonnet or Opus | README.md absence | DELETE | |

DELETE count: 79, 80, 206, 208, 213 = 5; 349-361 group = 6 (349, 351, 353, 355, 357, 361); 442-462 group = 11 + 1 + 1 + 1 + 8 + 1 + 1 = 24; 465-467 = 5; 470-493 = 5 + 7 + 6 = 18. Total 5 + 6 + 24 + 5 + 18 = 58.

Whole-block/helper: lines 438-462 (executor-lane section checks) and 464-493 (README + lane-reference prose) are pure wording pins and can go as two whole blocks, together with `outside()` (439), `section()` (440), `agy_sec` (452), `codex_sec` (458), `RD` (464), `EL` (78), and `REF`/`SK` (203-204) once nothing uses them. Keep the heading-less data checks around them.

### lock.test.sh (0)
All checks run lib/lock.sh against temp lock dirs. KEEP.

### migrate-skill.test.sh (16 DELETE, 2 structural remain)
Consumer note: scripts/dforge-migrate does the migration; no script reads skills/migrate/SKILL.md or the using-dforge routing table.

| Line(s) | Label | Markdown + phrase | Verdict | Note |
|---|---|---|---|---|
| 27 (vars 24-26) | the dry run comes first | skills/migrate/SKILL.md line order of `scripts/dforge-migrate --dry-run` vs `Run ... dforge-migrate\` and show` | DELETE | order of prose lines |
| 28 | the confirmation comes before the migration | SKILL.md `Run nothing` before real run line | DELETE | |
| 29 | asks before migrating | SKILL.md `that writes before a yes` | DELETE | |
| 30 | asks before committing | SKILL.md `human partner agrees, and stage nothing` | DELETE | |
| 32 (var 31) | the commit confirmation follows the migration | SKILL.md line order | DELETE | |
| 33 | commits only what the commit lines name | SKILL.md `stage nothing the lines do not name` | DELETE | |
| 34 | names the plugin uninstall | SKILL.md ``dr-forge@darkraise` and `dr-superpowers@darkraise` `` | DELETE | |
| 35 | names the webhook keys dforge does not read | SKILL.md ``notifyUrl` and `notifyMention` `` | DELETE | |
| 36 | names the webhook command | SKILL.md `/cockpit notify url <url>` | DELETE | |
| 37 | names the mention command | SKILL.md `/cockpit notify mention <id>` | DELETE | |
| 40 (vars 38-39) | the webhook is copied before the uninstall | SKILL.md line order | DELETE | |
| 41 | names the environment rename | SKILL.md ``DFORGE_*` environment variables in place of `DR_FORGE_*` `` | DELETE | |
| 42 | writes nothing itself | SKILL.md `This skill writes nothing` | DELETE | |
| 43 | announces the repository, the home and darkmem | SKILL.md `to move this repository, ...` | DELETE | |
| 44 | says the real run can refuse where the dry run passed | SKILL.md `This run can refuse where the dry run exited 0` | DELETE | |
| 45 | the entry point routes to it | skills/using-dforge/SKILL.md `\| dforge:migrate \|` | DELETE | session-start.sh injects the whole file, no parsing |

KEEP/structural: 22 (SKILL.md exists), 23 (`name: migrate` frontmatter, harness-consumed).
Whole-block: lines 20-45 incl. `present()` (lines 11-14) and `line_of()` (20) are all pins. If the judge wants zero wording pins the file reduces to 2 structural assertions and can be deleted whole (then drop `'migrate-skill.test.sh': 10` at scripts/test-shards.mjs:85).

### native-routing.test.sh (8 DELETE)
Consumer note: select-native-tier.sh is exercised by lines 9-104 (KEEP). scripts only cite `reference/native-codex.md §Existing plans` in error messages (plan-lint:96, plan-revise:282, task-step:583).

| Line(s) | Label | Markdown + phrase | Verdict | Note |
|---|---|---|---|---|
| 106-117 (var 105) | Existing plans keeps: <needle> | reference/native-codex.md `## Existing plans` section; loop of 8 needles: `Obtain approval`, `human pin stays verbatim`, `4     gpt-5.6-terra / high`, `3     gpt-6-sol / low`, `## Policy conversion`, `Ruling: policy conversion codex-v3 -> codex-v4`, `consumed split/review budgets`, `caught mid-escalation` | DELETE x8 | whole block 105-117 incl. the `existing` awk extraction |

KEEP: 9-104 and 118-120 (extracts the ```` ```json ```` fence of native-codex.md and runs it through the selector; see EXCLUDED).

### parallel-grouping.test.sh (12 DELETE, whole file)
Consumer note: no script reads skills/writing-plans/SKILL.md or its references. `clear --phase` is a real auto-run subcommand but its absence from prose is a text pin.

| Line(s) | Label | Markdown + phrase | Verdict | Note |
|---|---|---|---|---|
| 22 | two groups | writing-plans/SKILL.md `1. **Draft the tasks as usual, then sort them into two groups.**` | DELETE | |
| 23 | the alone group | SKILL.md `**alone** — a task that cannot share a wave` | DELETE | |
| 24 | the parallel group | SKILL.md `**parallel** — every other task.` | DELETE | |
| 25 | depth decides the order | SKILL.md `Dependencies decide only the order. ...` | DELETE | |
| 26 | the worked example | SKILL.md `Task 6 on Tasks 3-5 give ...` | DELETE | |
| 27 | one plan in an auto run | references/auto-run-plan.md `**One plan.** ...` | DELETE | |
| 28 | the finish line is recorded | auto-run-plan.md `holds a Finish: <action> line, ...` | DELETE | |
| 29 | the switch ends the turn | auto-run-plan.md `scripts/auto-run switch ... Auto run: switching` | DELETE | |
| 30 | the handoff note | references/execution-handoff.md `an auto run the cockpit clears the session instead; ...` | DELETE | |
| 31 | sequential is the default | SKILL.md `the default is sequential). Under ask, ...` | DELETE | |
| 32 | no split under autoRun=on | SKILL.md `Under autoRun=on the spec covers the whole request ...` | DELETE | |
| 33 | no clear --phase is left | SKILL.md + references/*.md absence of `clear --phase` | DELETE | |

Whole file has zero other assertions: delete the file and drop `'parallel-grouping.test.sh': 10` at scripts/test-shards.mjs:88.

### polluter.test.sh (0)
Runs find-polluter.sh against stubs. KEEP.

### readme-unattended.test.sh (9 DELETE, whole file)
Consumer note: config/schema.mjs has a label "Unattended runs" for a setting, unrelated to README text; no script reads README.md.

| Line(s) | Label | Markdown + phrase | Verdict | Note |
|---|---|---|---|---|
| 19 | one Unattended runs heading | README.md `## Unattended runs` | DELETE | |
| 20 | the section has text | README.md section non-empty | DELETE | |
| 21 | auto mode is named with its flag | `--permission-mode auto` | DELETE | |
| 22 | auto mode gives its reason | `permission prompt` | DELETE | |
| 23 | worktree.baseRef set to head | `{ "worktree": { "baseRef": "head" } }` | DELETE | |
| 24 | baseRef reason: default branches from origin | `origin/<default-branch>` | DELETE | |
| 25 | baseRef reason: unpushed commits missing | `unpushed` | DELETE | |
| 26 | dforge's own auto run told apart | `reference/auto-run.md` | DELETE | |
| 27-28 | the section sits before Session budget | README heading order | DELETE | |

Whole file has zero other assertions: delete it and drop `'readme-unattended.test.sh': 10` at scripts/test-shards.mjs:96.

### repo-audit.test.sh, roots.test.sh, run-agy-task.test.sh, run-codex-task.test.sh, snapshot.test.sh, suite-run.test.sh, task-state.test.sh, wave.test.sh (0 each)
All assertions run scripts (repo-audit, lib/roots.sh, dforge-path, run-agy-task.sh, agy-gate, run-codex-task.sh, lib/snapshot.sh, suite-run, lib/task-state.sh, wave, sdd-workspace) against temp fixtures and check stdout/exit codes/state files. KEEP. (Contract-file greps in the two run-*-task tests: see EXCLUDED.)

### sdd-references.test.sh, skill-size.test.sh, skill-split-planning.test.sh (0 DELETE)
Structural: file exists/non-empty, relative links resolve, SKILL.md at or under 20,000 bytes, plus the `Read [x](references/x) before you ...` link line (see EXCLUDED for the two borderline forms). skill-view.sh is a sourced helper (no assertions); it is also sourced by tests outside this scope (task-step-text, auto-run-skills, project-status, ui-ux-skill, gates-manifest, final-phase, inline-mode, inline-only.acceptance, review-route), so do not delete it even if waiting-text.test.sh goes.

### test-simplifier.test.sh (55 DELETE)
Consumer note: scripts/test-profile reads JUnit XML, not skills; no script reads skills/test-simplifier/**, reference/test-tiers.md, using-dforge, test-driven-development or writing-plans SKILL.md text (`plan-lint:643` only cites test-tiers.md in a comment).

| Line(s) | Label | Markdown + phrase | Verdict | Note |
|---|---|---|---|---|
| 30 | runners points to the tiers reference | references/runners.md link text | DELETE | |
| 31 | runners keeps no copy of the impact table | runners.md absence `pytest-testmon` | DELETE | |
| 32 | the tiers reference holds the impact table | reference/test-tiers.md `\| jest --changedSince ...` | DELETE | |
| 35 | coverage never proves redundancy | SKILL.md | DELETE | |
| 36 | every killed mutant stays killed | SKILL.md | DELETE | |
| 37 | no-tool fallback: faults must be caught | SKILL.md | DELETE | |
| 38 | fault patches are reverted | SKILL.md | DELETE | |
| 41-44 | phase: <heading> | SKILL.md headings `## Phase 1..4` (loop of 4) | DELETE x4 | |
| 45 | flaky tests are quarantined, not deleted | SKILL.md | DELETE | |
| 46 | tier changes need approval | SKILL.md | DELETE | |
| 47 | full sweep must keep running somewhere | SKILL.md | DELETE | |
| 50 | waves change test files only | SKILL.md | DELETE | |
| 51 | waves are bounded | SKILL.md | DELETE | |
| 52 | never removed: regression tests | SKILL.md | DELETE | |
| 53 | never removed: gate dependencies | SKILL.md | DELETE | |
| 56 | dispatches judge-opus | SKILL.md | DELETE | |
| 57 | commit before judging | SKILL.md | DELETE | |
| 58-61 | verdict $v / judge contract verdict $v | SKILL.md and references/simplify-judge.md (loop KEPT/LOST/VIOLATED x2 files) | DELETE x6 | |
| 62 | judge maps assertions before ruling | simplify-judge.md | DELETE | |
| 63 | judge checks production files | simplify-judge.md | DELETE | |
| 64 | judge is read-only | simplify-judge.md | DELETE | |
| 65 | fault prompt names concrete edits | simplify-judge.md | DELETE | |
| 66 | judge names the SHA | simplify-judge.md | DELETE | |
| 69 | entry point routes to the skill | using-dforge/SKILL.md `dforge:test-simplifier` | DELETE | |
| 70 | TDD folds variants into a table | test-driven-development/SKILL.md | DELETE | |
| 71 | TDD asks for the lowest layer | test-driven-development/SKILL.md | DELETE | |
| 72 | plans keep e2e for user journeys | writing-plans/SKILL.md | DELETE | |
| 84-86 | phase 3 names the tier: <tier> | SKILL.md `\| Task check \|`, `\| Full suite \|`, `\| Sweep \|` (loop of 3) | DELETE x3 | |
| 87-89 | the old tier name is gone: <name> | SKILL.md absence (loop of 3: `Inner loop`, `Branch gate`, `full sweep`) | DELETE x3 | |
| 90 | phase 3 takes its tier sources from the shared reference | SKILL.md link text | DELETE | |
| 91 | phase 3 proposes a gates.md diff | SKILL.md | DELETE | |
| 92 | phase 3 proposes a Tier: task gate | SKILL.md | DELETE | |
| 93 | phase 3 proposes a Budget line | SKILL.md | DELETE | |
| 94 | scope: --modules | SKILL.md | DELETE | |
| 95 | scope: closing-a-milestone passes the modules | SKILL.md | DELETE | |
| 96 | scope: --since | SKILL.md | DELETE | |
| 97 | scope: phase 1 still profiles the whole suite | SKILL.md | DELETE | |
| 98 | scope: phase 4 waves stay inside the scope | SKILL.md | DELETE | |
| 99 | candidate class 6 | SKILL.md `6. **Subsumed scaffolding.**` | DELETE | |
| 100 | class 6 uses the same evidence | SKILL.md | DELETE | |
| 101 | division of labour heading | SKILL.md `## Division of labour` | DELETE | |
| 102 | branch tests go to the REFACTOR step and the lens | SKILL.md | DELETE | |
| 103 | this skill handles the default branch's tests | SKILL.md | DELETE | |

Count: 3 + 4 + 4 + 3 + 4 + 2 + 6 + 5 + 4 + 3 + 3 + 14 = 55.
KEEP: 25-27 (4 exists checks, structural) and 105-153 (scripts/test-profile output).
Whole-block/helper: lines 29-103 are all pins and go whole with `present()` (20-23), `says()` (76-79), `gone()` (80-83), and the `SKILL`/`JUDGE`/`RUNNERS`/`TIERS` constants if the exists loop (25-27) is dropped too. The header comment (lines 2-4, "pin what makes a removal safe") should be reworded to say the file only runs test-profile.

### turn-end.test.sh (2 DELETE)

| Line(s) | Label | Markdown + phrase | Verdict | Note |
|---|---|---|---|---|
| 290-294 (loop 291-294) | $s: finishing is a Skill tool call in the same turn | skills/subagent-driven-development/SKILL.md and skills/executing-plans/SKILL.md: `Finishing is a Skill tool call in this same turn` (2 skills) | DELETE x2 | turn-end.sh does not read the phrase; hooks/cockpit/register.tsx:537 mentions Skill tool calls in an unrelated comment |

KEEP: everything else (turn-start.sh, turn-end.sh, session-start.sh, auto-run, hooks.json wiring at 283-288).

### ui-hooks.test.sh, ui-lint.test.sh (0)
Hook scripts, ui-lint on `*.fixture` files and `hooks/hooks.json` (config). KEEP.

### waiting-text.test.sh (20 DELETE, whole file)
Consumer note: no script reads SKILL.md, delegated-task.md, codex-tools.md, ruling-seat.md or executing-plans text. `review-route` implements `reason=simple-kind` and `cannot-verify` routing in code, but does not read ruling-seat.md; `task-step` emits the `Ruling: cannot-verify — settled by task-step check` line from code.

| Line(s) | Label | Markdown + phrase | Verdict | Note |
|---|---|---|---|---|
| 45 | a Monitor wait is caught | temp fixture fed only to the test's own `polling()` grep | DELETE | self-test of a pin helper; no script involved |
| 50 | the prohibition is not caught | same | DELETE | same |
| 52 | subagent-driven-development prescribes no Monitor or sleep wait | sdd_text (SKILL.md + references) regex | DELETE | |
| 53-54 | a Claude Code session ends the turn when only waiting remains | SDD SKILL.md | DELETE | |
| 55 | the prohibition is stated | SDD SKILL.md ``Never wait with `Monitor`, `sleep` or a polling loop.`` | DELETE | |
| 56 | a notification turn starts with in-flight | SDD SKILL.md `scripts/in-flight` sentence | DELETE | |
| 57 | the bounded Monitor stretch is gone | sdd_text absence | DELETE | |
| 58 | the stretch advice is gone | sdd_text absence | DELETE | |
| 59 | Codex keeps its stretches in the skill | SDD SKILL.md | DELETE | |
| 60 | the delegated loop no longer says wait in bounded stretches | reference/delegated-task.md absence | DELETE | |
| 61-62 | the delegated loop points at the waiting rule | delegated-task.md | DELETE | |
| 64 | codex-tools keeps the bounded wait_agent stretch | skills/using-dforge/references/codex-tools.md | DELETE | |
| 65 | codex-tools keeps the five-minute floor | codex-tools.md | DELETE | |
| 67 | the ruling route takes a comma-separated kind list | references/ruling-seat.md | DELETE | |
| 68 | simple kinds route to judge-sonnet-high | ruling-seat.md | DELETE | |
| 69 | the other kinds stay on judge-opus | ruling-seat.md | DELETE | |
| 70 | a mechanical check settles a cannot-verify item | ruling-seat.md | DELETE | |
| 71 | a failed check is a fix-loop finding | ruling-seat.md | DELETE | |
| 72 | inline mode routes the simple kinds | executing-plans (skill_view) | DELETE | |
| 73 | inline mode settles by mechanical check | executing-plans (skill_view) | DELETE | |

Whole file has zero other assertions: delete it and drop `'waiting-text.test.sh': 10` at scripts/test-shards.mjs:133. `fixtures/sdd-text.sh` is also used by sdd-references.test.sh (and others), keep it.

### working-directory.test.sh (3 DELETE)

| Line(s) | Label | Markdown + phrase | Verdict | Note |
|---|---|---|---|---|
| 133-134 | no skill, reference or script says 'from the plugin root' | skills/**, reference/** (and scripts/) absence of the phrase | DELETE | |
| 135-136 | no skill or reference re-explains where the plugin root is | skills/**, reference/** absence of `the path the session's entry point names` | DELETE | |
| 139-140 | at least nine skill and reference files cite the contract | skills/**, reference/** count of `(see using-dforge §Session Budget)` >= 9 | DELETE | |

KEEP: 28-129, 148-170 (scripts' own working-directory refusals). The `P="$HERE/.."` at 131 is still used by 138, 146, 159-169.

### worktree-instructions.test.sh (2 DELETE)

| Line(s) | Label | Markdown + phrase | Verdict | Note |
|---|---|---|---|---|
| 24 | setup honors the declared package manager | skills/using-git-worktrees/SKILL.md ``packageManager` in `package.json` `` | DELETE | |
| 25 | Python setup identifies tooling | using-git-worktrees/SKILL.md `A pyproject.toml with none of those files names no tool` | DELETE | |

KEEP/EXCLUDED: 19-23 (extracts the `git check-ignore` command from the SKILL.md and runs it; behaviour of the example, see EXCLUDED). The `names()` helper at line 11 goes with the deletion.

## 3. EXCLUDED borderline cases

- lanes.test.sh 363-436 (calibration record checks: 371-373, 387-388, 395, 416, 418-426, 431-435): assert the table/header/Smoke line of docs/dforge/notes/2026-11-02-agy-calibration.md and the `### The Antigravity executor lane is on` heading in docs/superpowers/distilled/constraints.md. Outside the stated md set (history notes, not skills/reference/criteria/agents/README) and tied to `reference/agy-policy.json` `trust.smoke`; no script reads either doc. Judge decision: they are text pins on a historical record if the scope is widened; 12 candidate assertions. Lines 397-410 in that block check ladder blocks and are KEEP.
- lanes.test.sh 358-359 (the note ladder.md names is committed): file-existence check, structural, but orphaned if 356-357 are deleted; delete together if the judge agrees.
- lanes.test.sh 41 (ladder.md exists), 154 (codex-judge block present): structural / block data.
- native-routing.test.sh 118-120: extracts the ```` ```json ```` fence of reference/native-codex.md and runs it through select-native-tier.sh; asserts script output on a doc example. Kept as behaviour (the fence is not parsed by any script itself).
- worktree-instructions.test.sh 19-23: runs the `git check-ignore` line from using-git-worktrees/SKILL.md with a temp repo; asserts command exit codes, not a phrase. Kept.
- run-codex-task.test.sh 65 and run-agy-task.test.sh 70-76 (contract names `discovered_issues`, `assumptions`, `status`..., forbids `git add`...): scripts/codex-task-contract.md and scripts/agy-task-contract.md are the wrappers' prompt payload (read by run-codex-task.sh:206 `cat`, run-agy-task.sh:17 CONTRACT), not skill/reference docs. Kept; 17 assertions (run-agy-task.test.sh 69-76: 10 git words + 6 fields = 16; run-codex-task.test.sh 64-65: 1 count check). The judge may delete them if the payload is judged a pin.
- sdd-references.test.sh 27-28 (`## After compaction` heading kept; block links references/ledger.md): wording-ish, no script reads the heading (hooks/cockpit/register.tsx:159 names it in a message only). Treated as structural reachability. Judge may delete; 2 assertions. 29 (links resolve) is structural.
- sdd-references.test.sh 35-36 (x10), skill-size.test.sh 41-47 (x11), skill-split-planning.test.sh 53 (x18): the `Read [x](references/x) before you ...` line. Classified structural (link reachability after compaction truncation, the stated design in the skill-size header). Judge may treat as pins; counts 10, 11, 18.
- working-directory.test.sh 137-138: greps scripts/lib/snapshot.sh source for the sentence it emits (script text, not markdown). Kept.
- working-directory.test.sh 145-146: lints scripts/ for sibling `exec`; script source, not markdown. Kept.
- migrate-skill.test.sh 23 (`name: migrate`): frontmatter, harness-consumed. Kept.
- turn-end.test.sh 284-288, ui-hooks.test.sh 60-63 and 158-164: hooks.json config assertions. Kept.

## 4. Zero-leftover and counter/plan edits

No file uses a TAP plan, `1..N`, or a literal expected total; each prints the live `pass`/`fail` counters, so no count needs updating anywhere in these files.

| File | Leaves zero assertions? | Edits needed |
|---|---|---|
| lane-breaker.test.sh | No (45-113 remain) | remove lines 114-125, `present()` 17-20 |
| lanes.test.sh | No | remove the DELETE lines; drop now-unused `EL` (78), `REF`/`SK` (203-204), `outside()`/`section()` (439-440), `agy_sec`/`codex_sec` (452, 458), `RD` (464) |
| migrate-skill.test.sh | No, 2 structural (22, 23) remain; or delete the file whole | if deleted whole: remove `'migrate-skill.test.sh': 10` at scripts/test-shards.mjs:85 |
| native-routing.test.sh | No (9-104, 118-120 remain) | remove 105-117 |
| parallel-grouping.test.sh | Yes: zero left | delete file; remove scripts/test-shards.mjs:88 |
| readme-unattended.test.sh | Yes: zero left | delete file; remove scripts/test-shards.mjs:96 |
| test-simplifier.test.sh | No (4 exists + test-profile checks remain) | remove 29-103 and helpers 20-23, 76-83; reword header comment lines 2-4 |
| turn-end.test.sh | No | remove 290-294 |
| waiting-text.test.sh | Yes: zero left | delete file; remove scripts/test-shards.mjs:133; keep skill-view.sh and fixtures/sdd-text.sh (used elsewhere) |
| working-directory.test.sh | No | remove 133-136 and 139-140 (and comment at 130, 132) |
| worktree-instructions.test.sh | No (21, 23 remain) | remove 24-25 and `names()` at 11 |

scripts/test-shards.mjs is the repo-level shard weight table (outside tests/); it lists every test file by name, so whole-file deletions need the matching entry removed (lines 85/88/96/133 as above) or the shard planner may complain about unknown files; verify with `node scripts/validate-repository.mjs` after editing.
