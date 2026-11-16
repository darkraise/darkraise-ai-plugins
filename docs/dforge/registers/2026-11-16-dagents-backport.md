# dagents backport

**Source:** every dforge commit since dforge-v4.17.1, for docs/dforge/specs/2026-11-16-dagents-split-design.md §2
**Covers:** -

| # | Item | Assigned | Acceptance | State | Note |
|---|---|---|---|---|---|
| 1 | 147082b feat(dforge): add the agy review runner | - | - | n/a | feature: adds run-agy-review.sh and worktree-snapshot.sh, dforge 5's agy reviewer seat, which dagents does not have |
| 2 | 6c2159c refactor(dforge): stop routing by Executor lines | - | - | n/a | feature: stops Executor-line routing in review-route, next-step and task-step, which dagents keeps with its executor lane |
| 3 | 5b36192 refactor(dforge)!: retire the external executor lane | - | - | n/a | feature: removes the external executor lane (run-codex-task.sh, run-agy-task.sh, lane-breaker), which dagents keeps |
| 4 | c8a1819 refactor(dforge): warn on obsolete Executor lines | - | - | n/a | feature: turns plan-lint's Executor checks into an obsolete-line warning, while dagents keeps the executor lane |
| 5 | 2495846 refactor(dforge): remove revising-plans and plan-revise | - | - | n/a | feature: removes revising-plans and plan-revise, which dagents keeps |
| 6 | ff847ca refactor(dforge): make the registry review-only | - | - | n/a | feature: makes the executors registry review-only (detect-executors.sh, executors), while dagents' registry still drives the lane |
| 7 | eb85a46 refactor(dforge): drop the Codex lane surface | - | - | n/a | feature: drops the codexLane setting and codex-gate's lane field, which dagents keeps |
| 8 | 30eeb8d feat(dforge): add the agy review switch | - | - | n/a | feature: adds the agyReview setting and agy-gate's review switch for dforge 5's agy reviewer |
| 9 | 439fbd6 feat(dforge): run external reviewers as a panel | - | - | n/a | 5-only |
| 10 | b7e6ca5 fix(dforge): keep the review panel inside its bound | - | - | n/a | 5-only |
| 11 | 13b2555 feat(dforge): route reviews to the reviewer panel | - | - | n/a | feature: routes review-route's seats to dforge 5's reviewer panel |
| 12 | 2f9803b feat(dforge): run the panel from task-step | - | - | n/a | feature: runs dforge 5's reviewer panel from task-step |
| 13 | e427bde test(dforge): complete the cockpit test fixtures | - | - | done | port 5d14b6f; fail@parent pass@port |
| 14 | f1167a7 docs(dforge): describe the reviewer panel | - | - | n/a | docs-only: describes dforge 5's reviewer panel in delegated-task.md, external-review.md and final-review.md |
| 15 | 35419b0 docs(dforge): drop the executor lane from skills | - | - | n/a | docs-only: drops the executor lane from the skills, which dagents keeps |
| 16 | dd5e658 docs(dforge): document the reviewer-only release | - | - | n/a | feature: documents dforge 5's reviewer-only release in the README and manifests, with its acceptance suite |
| 17 | c1f739b test(dforge): add reviewer-only acceptance tests | - | - | n/a | test-only: adds reviewer-only-externals.acceptance.test.sh for dforge 5's reviewer panel |
| 18 | 48f0caa fix(dforge): keep the Second Pass note on one line | - | - | done | port f490210; fail@parent pass@port |
| 19 | 7a8610d fix(dforge): check string enums in agy answers | - | - | n/a | 5-only |
| 20 | b8fd3e5 fix(dforge): reject an empty agy final review | - | - | n/a | 5-only |
| 21 | 8669084 fix(dforge): drop a failed reviewer's out file | - | - | n/a | 5-only |
| 22 | 0492abe fix(dforge): keep each gate's stderr in the panel | - | - | n/a | 5-only |
| 23 | 571ec2d fix(dforge): fail a family with no ladder block | - | - | n/a | 5-only |
| 24 | f25afb5 test(dforge): cover the panel's computed bound | - | - | n/a | 5-only |
| 25 | 0875ab5 test(dforge): tighten the review panel suite | - | - | n/a | test-only: tightens review-panel.test.sh, a dforge 5 suite |
| 26 | 5c7aedd fix(dforge): check git config and hooks after agy | - | - | n/a | 5-only |
| 27 | f7d8467 test(dforge): check agy resets and an unknown base | - | - | n/a | test-only: extends agy-review.test.sh, a dforge 5 suite |
| 28 | 49ec859 test(dforge): retest codexReview off to on | - | - | n/a | test-only: dagents' codex-gate.test.sh already clears the cache before switching codexReview back on and expects source=probe |
| 29 | 0fca483 fix(dforge): harden the agy git-state check | - | - | n/a | 5-only |
| 30 | 02a858c test(dforge): drop checks that exact checks cover | - | - | n/a | test-only: removes checks in lanes.test.sh and task-step.test.sh that other checks cover; dagents' copies still hold |
| 31 | 0ebde99 test(dforge): check the 5.0 WARN and mid-lane rule | - | - | n/a | test-only: extends reviewer-only.acceptance.test.sh, a dforge 5 suite |
| 32 | 9712236 docs(dforge): drop HANDBACK from fix-round lines | - | - | n/a | docs-only: HANDBACK stays a fix-round outcome in dagents' delegated-task.md, since dagents keeps the executor lane |
| 33 | 06822b8 fix(dforge): name worktree-snapshot in its errors | - | - | n/a | 5-only |
| 34 | 0c58f7f docs(dforge): run the final panel in a worktree | - | - | n/a | docs-only: runs dforge 5's final reviewer panel in a worktree (external-review.md, final-review.md) |
| 35 | 62799cd fix(dforge): catch hook mode and config reorders | - | - | n/a | 5-only |
| 36 | e48eeaf fix(dforge): stop on a shared git state write | - | - | n/a | 5-only |
| 37 | 0786918 test(dforge): match the A18 release line anywhere | - | - | n/a | test-only: reviewer-only-externals.acceptance.test.sh is a dforge 5 suite |
| 38 | a109465 fix(dforge): run tools when a pane read fails | - | - | done | port d298556; fail@parent pass@port |
| 39 | 2470dcd docs(dforge): use neutral gates in the template | - | - | done | port 6b4e525; text-only plugins/dagents/skills/running-gates/references/gates-template.md |
| 40 | 094b6d9 refactor(dforge): drop orphan approach criteria | - | - | done | port 05c9ab5; text-only plugins/dagents/skills/selecting-approaches/SKILL.md |
| 41 | b10487c docs(dforge): make helper commands runnable | - | - | done | port a1799b7; text-only plugins/dagents/skills/writing-skills/SKILL.md |
| 42 | 777c30b chore(dforge): drop depth_name and a dead fixture | - | - | n/a | feature: removes the unused depth_name in lib/depth.sh and an unused fixture; no behaviour changes |
| 43 | fe1cf47 fix(dforge): read a finding on a path with a space | - | - | done | port c1b5260; fail@parent pass@port |
| 44 | a5a366a fix(dforge): match lens paths on non-ASCII names | - | - | done | port 11f7e2e; fail@parent pass@port |
| 45 | 65e912d fix(dforge): keep a BLOCKED decision's own dashes | - | - | done | port a1c364c; fail@parent pass@port |
| 46 | 859596e perf(dforge): scan the transcript only for a hold | - | - | n/a | feature: perf change to turn-end.sh's transcript scan |
| 47 | 9e1511e perf(dforge): start no node without darkmem | - | - | n/a | feature: perf change resolving local stores in lib/roots.sh without node |
| 48 | b3a641b fix(dforge): offer Resume again after /clear | - | - | done | port dd460dd; fail@parent pass@port |
| 49 | 533ab53 perf(dforge): pace the pane's git reads | - | - | n/a | feature: perf change pacing the cockpit's git reads in register.tsx |
| 50 | 1c95820 fix(dforge): skip the gauge for an unknown window | - | - | done | port 532af27; fail@parent pass@port |
| 51 | 90ceee5 refactor(dforge): drop the unused isPing export | - | - | n/a | feature: removes the unused isPing export from hooks/cockpit/notify.ts |
| 52 | ee1705c fix(dforge): keep a Claude budget line off Codex rollouts | - | - | done | port 7c71c53; fail@parent pass@port |
| 53 | 19a1527 fix(dforge): accept gtimeout and gate on a missing timeout | - | - | done | port eac7231; fail@parent pass@port |
| 54 | 74f54ff fix(dforge): drop a killed base run's worktree | - | - | done | port bf87d5a; fail@parent pass@port |
| 55 | f9256ee fix(dforge): mask the webhook in a failed send's reason | - | - | done | port e680b58; fail@parent pass@port |
| 56 | 2d3577e fix(dforge): drop the notify url verb | - | - | done | port da23299; fail@parent pass@port |
| 57 | 942711c fix(dforge): cancel approval waits when a session ends | - | - | done | port be8219e; fail@parent pass@port |
| 58 | dbc1d44 fix(dforge): end a spawn TaskStop stopped by name | - | - | done | port aa27456; fail@parent pass@port |
| 59 | 71baa5f fix(dforge): keep Discord sends off the hook budget | - | - | done | port 335b25c; fail@parent pass@port |
| 60 | 77e4127 docs(dforge): fix migrate script name and tested range | - | - | done | port 3e101db; text-only plugins/dagents/README.md |
| 61 | 99bbab2 test(dforge): drop two tests that cannot hold in CI | - | - | n/a | test-only: drops reviewer-only-externals' A18 and review-depth-qa's pre-spec comparisons; dagents' review-depth-qa looks for plugins/dagents in an archive of plugins/dforge, so those comparisons always skip |
| 62 | e46cd66 test(dforge): drop absence checks that cannot fail | - | - | n/a | test-only: removes absence checks in plan-lint and acceptance suites that cannot fail; dagents' copies pass and guard nothing less |
| 63 | aaf3140 refactor(dforge): move the live prompt templates out of the SDD skill | - | - | n/a | feature: moves the live prompt templates from the subagent-driven-development skill to reference/prompts, a dforge 5 restructure |
| 64 | 864ffe4 perf(dforge): skip darkmem push in the task loop when off | - | - | n/a | feature: perf change skipping darkmem-sync push in executing-plans when darkmem is off |
| 65 | 5516b26 docs(dforge): move baseline compare to final-review | - | - | n/a | docs-only: moves the baseline comparison out of parallel-waves.md, which dagents keeps and final-review.md still cites |
| 66 | 53e1807 refactor(dforge): remove parallel waves | - | - | n/a | feature: removes parallel waves (wave, plan-lint wave checks), which dagents keeps |
| 67 | 3a69a43 refactor(dforge): remove group review and hold | - | - | n/a | feature: removes group review and hold from task-step and next-step, which dagents keeps |
| 68 | 4d5e4d0 refactor(dforge): retire subagent execution mode | - | - | n/a | feature: retires subagent execution mode, which dagents keeps |
| 69 | 7950420 refactor(evals): remove the tier eval harness | - | - | n/a | test-only: removes the tier eval harness checks from the speed-and-cost acceptance suites |
| 70 | 2da644a refactor(dforge): drop dispatch and fix-wave routing | - | - | n/a | feature: drops dispatch and fix-wave routing from review-route and task-step, which dagents keeps |
| 71 | f198d4a refactor(dforge): remove 15 implementer agents | - | - | n/a | feature: removes the 15 implementer agents, which dagents keeps |
| 72 | 15a7a6b refactor(dforge): stop requiring Implementer lines | - | - | n/a | feature: stops plan-lint requiring Implementer lines, which dagents' assignment still needs |
| 73 | eced2ee docs(dforge): describe the single-agent fleet | - | - | n/a | docs-only: describes dforge 5's single-agent fleet in the README |
| 74 | 9a214ac refactor(dforge): reduce the ladder to the floor table | - | - | n/a | feature: reduces ladder.md to the floor table, retiring the score ladder dagents keeps |
| 75 | 76c672f test(dforge): drop retired agent names from fixtures | - | - | n/a | test-only: drops retired agent names from fixtures; dagents keeps those agents |
| 76 | 8a6b567 feat(dforge): add task-brief --open and task-close | - | - | n/a | feature: adds task-brief --open and task-close |
| 77 | 976d3dc docs(dforge): describe task-brief --open and task-close | - | - | n/a | docs-only: describes task-brief --open and task-close, dforge 5 additions |
| 78 | 0235edf test(dforge): fit budget-line and shards to the open brief | - | - | n/a | test-only: fits budget-line.test.sh to the open brief, a dforge 5 feature |
| 79 | 9045f7a refactor(dforge): drop --no-probe and --kind risk3 | - | - | n/a | feature: drops --no-probe and --kind risk3 from plan-amend, plan-lint and the review runners, which dagents keeps |
| 80 | c97cdef refactor(dforge): remove the Codex roster probe | - | - | n/a | feature: removes the Codex roster probe from detect-executors.sh, which dagents' executor lane uses |
| 81 | 95553d5 refactor(dforge): drop dead tool names and FORK_DRAFTING | - | - | n/a | feature: removes tool names and the FORK_DRAFTING switch from the cockpit and hooks after dforge 5's retirements |
| 82 | d18b699 chore: remove the stale smoke script and two skill references | - | - | n/a | feature: replaces writing-skills' pasted best-practices copy with its URL and drops an example; housekeeping, no defect |
| 83 | b53c2ea docs(dforge): correct the agent descriptions | - | - | n/a | docs-only: rewrites the agent descriptions for dforge 5's retired score bands; dagents' descriptions match its routing |
| 84 | bbf92e7 perf(dforge): trim the session-start injection | - | - | n/a | feature: perf change trimming session-start.sh's injection |
| 85 | 0c512f4 perf(dforge): skip the external round with no reviewer open | - | - | n/a | feature: perf change skipping the external review round in review-route when no reviewer is open |
| 86 | 5f19c45 test(dforge): drop the reviewer-only README pin suite | - | - | n/a | test-only: drops reviewer-only.acceptance.test.sh, a dforge 5 suite |
| 87 | 0c3ab97 fix(dforge): type the notify timers so cancel checks | - | - | done | port df2e117; fail@parent pass@port |
| 88 | ce5e1f7 test(dforge): drop reference and README prose pins | - | - | n/a | test-only: drops prose pins in review-route and reviewer-only-externals suites on dforge 5 text |
| 89 | 71dc441 test(dforge): drop Dispatch and retired-role tombstones | - | - | n/a | test-only: drops tombstone checks for Dispatch and roles dforge 5 retired |
| 90 | fd4c8e9 test(dforge): drop absence checks no script can fail | - | - | n/a | test-only: drops absence checks in inline-only, next-step and plan-lint suites that no script can fail |
| 91 | e2d49d9 test(dforge): remove an unread fixture and an unused helper | - | - | n/a | test-only: removes an unread fixture and an unused helper from faster-plans.acceptance.test.sh |
| 92 | 03498f5 test(dforge): drop suite-run copies from the task-loop suite | - | - | n/a | test-only: drops duplicate suite-run checks from task-loop-steps.acceptance.test.sh |
| 93 | 42d226b test(dforge): drop duplicate cap, link and lensCap checks | - | - | n/a | test-only: drops duplicate cap, link and lensCap checks across acceptance suites |
| 94 | d102363 test(dforge): drop re-run suites and duplicate acceptance cases | - | - | n/a | test-only: drops re-run suites and duplicate acceptance cases |
| 95 | f5e0fd9 fix(dforge): say what happens next when the UI stop is held | - | - | done | port 038abe1; fail@parent pass@port |
| 96 | 31bd659 feat(dforge): ship /dforge:cockpit as a command file | - | - | n/a | 5-only |
| 97 | bc09771 fix(dforge): cockpit issues, update frequency and settings | - | - | done | port 55b907b; fail@parent pass@port |
| 98 | 12f6d95 feat(dforge): add API budgets and the spend file | - | - | n/a | feature: adds API budgets and the api-spend file |
| 99 | f38bc95 feat(dforge): add the Decisions API ruling rung | - | - | n/a | 5-only |
| 100 | e31290c feat(dforge): record and report Decisions API rulings | - | - | n/a | 5-only |
| 101 | 4d12902 fix(dforge): refuse git-directory files as evidence | - | - | n/a | 5-only |
| 102 | 0509664 fix(dforge): refuse nested .git paths as evidence | - | - | n/a | 5-only |
| 103 | 7873ba3 feat(dforge): run rulings on API-billed judges | - | - | n/a | feature: adds run-api-judge for API-billed ruling judges |
| 104 | e072bd5 feat(dforge): scrub, prove and charge API judge runs | - | - | n/a | 5-only |
| 105 | e5bc2f7 feat(dforge): start auto-run rulings at the API rungs | - | - | n/a | feature: starts auto-run rulings at the API rungs |
| 106 | 13dbd00 feat(dforge): keep the prompt cache warm while waiting | - | - | n/a | feature: keeps the prompt cache warm while the cockpit waits |
| 107 | eadd832 feat(dforge): place Gemini Hydrogen by measurement | - | - | n/a | feature: places Gemini Hydrogen in agy-policy.json by measurement |
| 108 | a778864 fix(dforge): keep the finishing skill under its cap | - | - | n/a | 5-only: trims a sentence the API-rung commits added to finishing's SKILL.md; dagents' copy is 19962 bytes, under the cap |
| 109 | a7fc54c docs(dforge): document API budgets and keep-warm | - | - | open | - |
| 110 | 1a56515 test(dforge): add acceptance tests A1-A18 | - | - | open | - |
| 111 | fe2bd8b test(dforge): add acceptance tests A21-A24 | - | - | open | - |
| 112 | 0de8685 fix(dforge): keep the held Done on a failed keep-warm | - | - | open | - |
| 113 | b52542f fix(dforge): harden run-api-judge's edge cases | - | - | open | - |
| 114 | 6de4b68 fix(dforge): close a budget on an unreadable spend file | - | - | open | - |
| 115 | f89c163 fix(dforge): charge unmetered Decisions requests | - | - | open | - |
| 116 | 70a0d0f docs(dforge): state the judge scrub and budget skips | - | - | open | - |
| 117 | a2ee8ee test(dforge): name AR_SESSION in the acceptance suite | - | - | open | - |
| 118 | 997ef1a fix(dforge): estimate only maybe-billed requests | - | - | open | - |
| 119 | 8a501b6 fix(dforge): clear Foundry and cloud base URLs too | - | - | open | - |
| 120 | 70407cd test(dforge): widen the api-judge chain timings | - | - | open | - |
| 121 | a5ccd1d test(dforge): cap stop reason without the root path | - | - | open | - |
| 122 | 075f139 test(dforge): name the A6 choice count accurately | - | - | open | - |
| 123 | 173d4ea docs(dforge): clear a stale review panel tree | - | - | open | - |
| 124 | 540167a fix(dforge): name the git floor in agy reviews | - | - | open | - |
| 125 | 15b67f2 docs(dforge): clear a locked review panel tree | - | - | open | - |
| 126 | 131075f test(dforge): pin the agy git floor boundary | - | - | open | - |
| 127 | e6a989d feat(dforge): trust agy review after live runs | - | - | open | - |
| 128 | bfb1a3c fix(dforge): ignore state before an API ruling | - | - | open | - |
| 129 | bc26f61 docs(dforge): give skill rules their reasons | - | - | open | - |
| 130 | 1037b07 docs(dforge): drop model lines from agent bodies | - | - | open | - |
| 131 | 2a85be4 docs(dforge): drop dated history from references | - | - | open | - |
| 132 | 235f759 docs(dforge): state one quote rule for bash -c | - | - | open | - |
| 133 | 39420d1 docs(dforge): lease the Early CI branch delete | - | - | open | - |
| 134 | d012344 fix(dforge): mark only the keep-warm turn itself | - | - | open | - |
| 135 | 1918182 fix(dforge): log a lost Decisions charge | - | - | open | - |
| 136 | c991f75 test(dforge): pin the api-judge snapshot failure | - | - | open | - |
| 137 | 4f3456a test(dforge): cover routing tokens in acceptance A9 | - | - | open | - |
| 138 | 3ea0dbf test(dforge): pin two unpinned plan-lint rules | - | - | open | - |
| 139 | 4fdf6d0 test(dforge): cover the ci-mirror malformed paths | - | - | open | - |
| 140 | 40c7219 test(dforge): reconcile A6 with the expect ruling | - | - | open | - |
| 141 | d33358f fix(dforge): lock executor session writes | - | - | open | - |
| 142 | 6b40c9d fix(dforge): read whole output paths in in-flight | - | - | open | - |
| 143 | cdd46ef test(dforge): close two gaps in task-loop acceptance | - | - | open | - |
| 144 | 04dc582 fix(dforge): keep a quick SIGKILL out of timeouts | - | - | open | - |
| 145 | e0fdf31 fix(dforge): flag only template placeholders | - | - | open | - |
| 146 | d84da62 fix(dforge): stop task-step on a lost state write | - | - | open | - |
| 147 | 1189ce4 fix(dforge): keep the judge key out of Codex shells | - | - | open | - |
| 148 | c9cb7c1 feat(dforge): require evidence in review findings | - | - | open | - |
| 149 | a843d5b feat(dforge): check plan task paths and ranges | - | - | open | - |
| 150 | 5423d0a feat(dforge): group code lenses into code-quality | - | - | open | - |
| 151 | dba4859 docs(dforge): describe the code-quality lens | - | - | open | - |
| 152 | c1bfc62 refactor(dforge): drop the small-fix re-review skip | - | - | open | - |
| 153 | 16ea57d docs(dforge): drop the stale implementer wording | - | - | open | - |
| 154 | 461e2cc feat(dforge): plan tests as contracts | - | - | open | - |
| 155 | 9176b2e test(dforge): add acceptance tests A1-A12 for measured-proposals | - | - | open | - |
| 156 | 0fbdf11 fix(dforge): bound the commands a fixer runs | - | - | open | - |
| 157 | 2cda77f fix(dforge): group every lang lens into code-quality | - | - | open | - |
| 158 | 9b0e9c8 test(dforge): cover range lists and later creators | - | - | open | - |
| 159 | 5b0edf2 test(dforge): rename checks for the removed skip | - | - | open | - |
| 160 | e749351 docs(dforge): name test contracts in scoring docs | - | - | open | - |
| 161 | fd1e039 fix(dforge): trim finishing under its size cap | - | - | open | - |
| 162 | 5e04dac test(dforge): drop the stale --covered rereview case | - | - | open | - |
| 163 | 70701f3 docs(dforge): say test contracts in the Rule S gate | - | - | open | - |
| 164 | 4b19885 docs(dforge): route read-only rejections to the check | - | - | open | - |
| 165 | b73a6ec test(dforge): simplify task-step rereview tests | - | - | open | - |
| 166 | 9d649bb fix(dforge): hold a retry ending over running work | - | - | open | - |
| 167 | b4f4690 feat(dforge): let a mid-plan question end the turn | - | - | open | - |
| 168 | d3e735d feat(dforge): write a per-session state file | - | - | open | - |
| 169 | bde86b0 feat(dforge): read the cockpit session state file | - | - | open | - |
| 170 | 38b6011 feat(dforge): tell services and timers from work | - | - | open | - |
| 171 | 5854428 feat(dforge): share the service list with the cockpit | - | - | open | - |
| 172 | cf6550a fix(dforge): let services pass the in-flight check | - | - | open | - |
| 173 | 48db0cc fix(dforge): route a stale clean review to re-review | - | - | open | - |
| 174 | 9037384 fix(dforge): hold stops over services and stale reviews | - | - | open | - |
| 175 | 20ed236 fix(dforge): read the window, never assume a million | - | - | open | - |
| 176 | 95b93b9 fix(dforge): scope fast mode to its request or session | - | - | open | - |
| 177 | 6606385 fix(dforge): scope cockpit fast mode and its nudge | - | - | open | - |
| 178 | 8b24b72 fix(dforge): trust only this session's handoff in snapshots | - | - | open | - |
| 179 | badc9e9 fix(dforge): let the UI proof hold stand down | - | - | open | - |
| 180 | 1b13c36 fix(dforge): clean up only the files QA listed | - | - | open | - |
| 181 | bd6ab26 fix(dforge): keep QA files when carried is unread | - | - | open | - |
| 182 | 37e9bfa fix(dforge): keep amendments beside the ledger | - | - | open | - |
| 183 | efac8da fix(dforge): refuse a plan whose amendments went missing | - | - | open | - |
| 184 | 4054dd5 fix(dforge): sync amendments with the ledger | - | - | open | - |
| 185 | 015f424 fix(dforge): read and keep plan amendments | - | - | open | - |
| 186 | 0b12fd4 fix(dforge): check plan identity when opening a task | - | - | open | - |
| 187 | 40e2086 fix(dforge): route Keep as-is and late PR records | - | - | open | - |
| 188 | afca0c6 fix(dforge): guard auto-run clear and stop stale runs | - | - | open | - |
| 189 | bc11017 fix(dforge): refuse local stores without node | - | - | open | - |
| 190 | df0a5cd fix(dforge): never excuse or reuse unproven suite runs | - | - | open | - |
| 191 | b8b3b7d fix(dforge): bound commands where only gtimeout exists | - | - | open | - |
| 192 | 2f16c67 fix(dforge): reap the whole runner tree without setsid | - | - | open | - |
| 193 | 5b7b473 fix(dforge): resolve proof screenshots through the store | - | - | open | - |
| 194 | ce31831 fix(dforge): retarget the stop gate to the QA report | - | - | open | - |
| 195 | a11442b fix(dforge): keep Codex workflow overrides | - | - | open | - |
| 196 | 8430aee docs(dforge): drop retired rules, add session fast mode | - | - | open | - |
| 197 | 044d471 fix(dforge): show waiting and deferred tasks in the cockpit | - | - | open | - |
| 198 | 3f9d5e7 fix(dforge): bind the Run card to the session's plan | - | - | open | - |
| 199 | e46380d fix(dforge): narrow the write and attribution guards | - | - | open | - |
| 200 | f1082e9 fix(dforge): read stdin messages and pointer prompts | - | - | open | - |
| 201 | 107efb4 fix(dforge): survive a crash between switch and restore | - | - | open | - |
| 202 | 4aa4f42 feat(dforge): add ASCII glyphs and honest saved settings | - | - | open | - |
| 203 | 7e870d8 fix(dforge): report a settings file that does not parse | - | - | open | - |
| 204 | 9b6c760 fix(dforge): resolve settings once and lock Claude writes | - | - | open | - |
| 205 | 16857b1 fix(dforge): lock inert rows and confirm API consent | - | - | open | - |
| 206 | dfd11ae test(dforge): add QA acceptance A1-A6, A34, A56 | - | - | open | - |
| 207 | ab96799 test(dforge): add QA acceptance A7-A11 | - | - | open | - |
| 208 | c7911f6 test(dforge): add QA acceptance A12, A13 | - | - | open | - |
| 209 | ee1f5bf test(dforge): add QA acceptance A14, A16 | - | - | open | - |
| 210 | 49a4f53 test(dforge): add QA acceptance A15, A17-A18, A22-A23 | - | - | open | - |
| 211 | 1470d40 test(dforge): add QA acceptance A21, A25-A28 | - | - | open | - |
| 212 | 6ff6a5d test(dforge): add QA acceptance A29-A33, A35, A52 | - | - | open | - |
| 213 | 780fb0c test(dforge): add QA acceptance A3 | - | - | open | - |
| 214 | 3311598 test(dforge): add QA acceptance A14, A19-A20, A24, A31 | - | - | open | - |
| 215 | 8da9057 test(dforge): add QA acceptance A37-A42 | - | - | open | - |
| 216 | a0af39c test(dforge): add QA acceptance A43-A50, A54 | - | - | open | - |
| 217 | 7e9f0ef test(dforge): add QA acceptance A24 control | - | - | open | - |
| 218 | 4f69002 fix(dforge): read whole command for unseen messages | - | - | open | - |
| 219 | f573f5f fix(dforge): clear the worktree's no-plan record | - | - | open | - |
| 220 | 790c81f fix(dforge): wrap cut rows under ASCII glyphs | - | - | open | - |
| 221 | 2ab23fc test(dforge): pin desktop webhook rows and units | - | - | open | - |
| 222 | d0822c3 fix(dforge): spell out the AgentRouter cap consent | - | - | open | - |
| 223 | 0331c84 fix(dforge): make the snapshot sweep act on facts | - | - | open | - |
| 224 | 56c8d44 fix(dforge): reread a session read a step failed | - | - | open | - |
| 225 | 2b10898 fix(dforge): name listed QA paths already dirty | - | - | open | - |
| 226 | 11d2dab test(dforge): pin the question notification titles | - | - | open | - |
| 227 | 40c6f49 test(dforge): gate an unprefixed type's bad report | - | - | open | - |
| 228 | ab50c31 fix(dforge): keep finishing's skill under its cap | - | - | open | - |
| 229 | ea30d1d docs(dforge): fix stale names in reference text | - | - | open | - |
| 230 | c7abb03 fix(dforge): refuse a multi-line task-close review | - | - | open | - |
| 231 | 4bd215a fix(dforge): keep dashed commands out of jq options | - | - | open | - |
| 232 | da61668 fix(dforge): recheck a stale run inside the lock | - | - | open | - |
| 233 | 8fbb79c fix(dforge): match a clear's plan name whole | - | - | open | - |
| 234 | e429076 fix(dforge): say when a register's Covers is unset | - | - | open | - |
| 235 | f29f7c7 fix(dforge): read only this checkout's ledgers | - | - | open | - |
| 236 | a6b1c7c fix(dforge): ignore a subagent's permission mode | - | - | open | - |
| 237 | f3d54ce fix(dforge): read a failed history walk as stale | - | - | open | - |
| 238 | b5f4761 fix(dforge): count an unparsed stores.json applied | - | - | open | - |
| 239 | 640a767 test(dforge): run no-node cases beside a shared bin | - | - | open | - |
| 240 | 8ad97cc fix(dforge): name a timed-out agy --version | - | - | open | - |
| 241 | 912916c fix(dforge): check the panel's kill left nothing | - | - | open | - |
| 242 | 6095c1f fix(dforge): show setting problems and stale runs | - | - | open | - |
| 243 | a22aad3 fix(dforge): say what to do when a save is undone | - | - | open | - |
| 244 | 735233f fix(dforge): name a waiting task in the dense row | - | - | open | - |
| 245 | 83bd7ca test(dforge): bound a session-start pull overrun | - | - | open | - |
| 246 | 0103738 test(dforge): give A21 room on slow runners | - | - | open | - |
| 247 | 7bcfc5f test(dforge): keep A11's runs out of the checkout | - | - | open | - |
| 248 | ecd418e fix(dforge): keep git's reason for a failed undo | - | - | open | - |
| 249 | ed407a7 test(dforge): keep the docs root's amendments/ out | - | - | open | - |
| 250 | 424e19d fix(dforge): read an unreadable beat as unknown | - | - | open | - |
| 251 | f5e9103 fix(dforge): match a written message file by name | - | - | open | - |
| 252 | 656edd4 test(dforge): pin A10's nothing-follows clear | - | - | open | - |
| 253 | 4edda5a fix(dforge): fit the did-not-stick toast in its box | - | - | open | - |
| 254 | fbf0121 fix(dforge): focus Confirm after the consent press | - | - | open | - |
| 255 | 642b774 fix(dforge): retry only the session steps that failed | - | - | open | - |
| 256 | dd15eb1 test(dforge): pin a kept Claude-key save as toastless | - | - | open | - |
| 257 | 37334d9 refactor(dforge): move next-step's router to route.sh | - | - | open | - |
| 258 | 4d08f3c fix(dforge): route spec rows by the spec's plans | - | - | open | - |
| 259 | 53fe7f8 feat(dforge): add next-step --print and a marker | - | - | open | - |
| 260 | f6c1db9 fix(dforge): read completed.md and worktree ledgers | - | - | open | - |
| 261 | cd486fb feat(dforge): add the plan-less next-step --project | - | - | open | - |
| 262 | 3c7a1d0 feat(dforge): recompute latest.md with --print --latest | - | - | open | - |
| 263 | f617f51 fix(dforge): recompute handoff lines in repo-audit | - | - | open | - |
| 264 | 7d0d94d fix(dforge): recompute the cockpit resume offer | - | - | open | - |
| 265 | eb49724 fix(dforge): release a stop only on a written block | - | - | open | - |
| 266 | e9e0dc9 fix(dforge): hold turns that merge or close work | - | - | open | - |
| 267 | 0e10e32 fix(dforge): name only a plain plan path in a hold | - | - | open | - |
| 268 | c75c2c6 fix(dforge): keep row notes in roadmap settle | - | - | open | - |
| 269 | 8624f84 docs(dforge): end milestone flows on next-step | - | - | open | - |
| 270 | a004ff0 docs(dforge): read the next step from next-step | - | - | open | - |
| 271 | c49d96a fix(dforge): file project checkpoints in darkmem | - | - | open | - |
| 272 | 9fda4ea test(dforge): add acceptance tests A1-A11, A14-A19, A23-A31 for next-session-routing | - | - | open | - |
| 273 | 241ad5e test(dforge): add acceptance tests A12, A13 for next-session-routing | - | - | open | - |
| 274 | 2ff5031 test(dforge): add acceptance test A22 for next-session-routing | - | - | open | - |
| 275 | 8d15fb8 fix(dforge): harden the next-step latest recompute | - | - | open | - |
| 276 | 53d9182 fix(dforge): recompute the resume offer after a run | - | - | open | - |
| 277 | 38bb71d fix(dforge): name only a plain plan in a ledger hold | - | - | open | - |
| 278 | 3648e9f chore(dforge): weigh the routing acceptance suite | - | - | open | - |
| 279 | addd102 test(dforge): skip the directory-mode check on Windows | - | - | open | - |
| 280 | 9f2161e fix(dforge): drop built rows with no current milestone | - | - | open | - |
| 281 | d7089d6 fix(dforge): keep full refs after a removed checkout | - | - | open | - |
| 282 | 86c359c docs(dforge): route rules 4-5 without an index to rule 6 | - | - | open | - |
| 283 | 71ab192 fix(dforge): record a Codex host in the next-step marker | - | - | open | - |
