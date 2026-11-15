# dforge plugin review fixes

**Source:** four-seat dforge plugin review of b4f46903 (Fable, Codex gpt-6-astra, agy Argon, agy Hydrogen), verified by five judge-opus seats; .dforge/reviews/2026-11-15-plugin-review/consolidated.md (owner, 2026-11-15: "create plan to fix all the confirmed findings")
**Covers:** docs/dforge/specs/2026-11-15-plugin-review-fixes-design.md

| # | Item | Assigned | Acceptance | State | Note |
|---|---|---|---|---|---|
| 1 | [Critical] C2+F1. QA timeout cleanup deletes files it never proved were QA's | - | - | open | - |
| 2 | [Important] C3. Plans with the same basename share a workspace and a ledger | - | - | open | - |
| 3 | [Important] C6. A historical "Final review: clean" line counts as current approval | - | - | open | - |
| 4 | [Important] C7. The Codex task loop requires a command that refuses Codex plans | - | - | open | - |
| 5 | [Important] F6. The compaction snapshot shows a possibly stale latest.md as trusted and drops the ledger first | - | - | open | - |
| 6 | [Important] C4. Choosing a PR records completion before the push succeeds | - | - | open | - |
| 7 | [Important] C5. Keep As-Is routes the handoff as though the branch were integrated | - | - | open | - |
| 8 | [Important] C9. Unnamed suite failures at base and head count as the same baseline failure | - | - | open | - |
| 9 | [Important] C10. A suite pass can be recorded against a HEAD that was not tested | - | - | open | - |
| 10 | [Important] C11. A failed `git status` reads as a clean tree | - | - | open | - |
| 11 | [Important] H1+C19. Procedures require a literal `timeout` that macOS may not have | - | - | open | - |
| 12 | [Important] F2. A background service (dev server, watcher) switches off every plan-ending hold | - | - | open | - |
| 13 | [Important] C14+F8. Relaxed handoff mode: the cockpit drops the final-phase exemption, and the settings view locks a budget that auto runs still use | - | - | open | - |
| 14 | [Important] C15+F13. Fast mode: the budget nudge ignores it, and the hooks keep it in force past its one request | - | - | open | - |
| 15 | [Important] C18. Missing Node silently makes both stores local even when darkmem progress is applied | - | - | open | - |
| 16 | [Important] H6. Resume offer resolves register names against the checkout, not the docs store | - | - | open | - |
| 17 | [Important] C12. Judge write guard lets a re-review judge overwrite the prior round's report | - | - | open | - |
| 18 | [Important] C13+F22. Run card binds to the newest ledger by mtime, not the session's plan | - | - | open | - |
| 19 | [Important] A3+F17. parseLedger does not know `Task <N>: waiting — <question>` | - | - | open | - |
| 20 | [Important] F5. Plain-text questions never raise the `question` notification | - | - | open | - |
| 21 | [Important] A4. A deferred task reads and notifies as completed | - | - | open | - |
| 22 | [Important] F11. A Claude-key save stays shown as saved even when the engine drops it | - | - | open | - |
| 23 | [Important] C16. Codex loses designApproval and specReview overrides under the default autoRun | - | - | open | - |
| 24 | [Important] F4. A settings file that fails to parse silently resets every setting to its default | - | - | open | - |
| 25 | [Important, partial] C1+A1+A10. Plan amendments are not durable and are not applied by some consumers | - | - | open | - |
| 26 | [Important, partial] H2+A7. native-codex.md keeps retired review and dispatch rules | - | - | open | - |
| 27 | [Important, partial] A11. `ui-proof check` does not resolve cited screenshot paths through the document store | - | - | open | - |
| 28 | [Important, partial] F3. The budget scripts assume a 1,000,000-token window for every model that is not Haiku | - | - | open | - |
| 29 | [Important, partial] H4+A2+F28. ui-turn-end.sh: no transcript fallback, and no stand-down for handoffs, waiting questions or background waits | - | - | open | - |
| 30 | [Minor] F14. executing-plans states a delegated-task fix cap of 5 | - | - | open | - |
| 31 | [Minor] A13. final-review.md still tells the session to use "the fix subagent" | - | - | open | - |
| 32 | [Minor] F16. One latest.md serves every worktree, and auto-run clear does not check whose prompt it reads | - | - | open | - |
| 33 | [Minor] F31. An auto run left by a dead or replaced session cannot be stopped from the new session | - | - | open | - |
| 34 | [Minor] F12. The no-plan finish record is never cleared | - | - | open | - |
| 35 | [Minor] C20. agy version discovery runs unbounded without a literal `timeout` | - | - | open | - |
| 36 | [Minor] F26. Judge seats keep WebFetch with no limit on what they fetch | - | - | open | - |
| 37 | [Minor] F29. The reconcile prompt tells an auto run to stop the QA timer as idle | - | - | open | - |
| 38 | [Minor] H11+C22+F15. README documents an unplanned-commit Stop hold that the hook does not implement | - | - | open | - |
| 39 | [Minor] F23. Several hooks rescan the whole transcript or ledger directory on a hot path | - | - | open | - |
| 40 | [Minor] F27. Rules implemented twice (bash and TypeScript); the shell side scrapes English tool-result strings | - | - | open | - |
| 41 | [Minor] F35. Session start can block for minutes on darkmem with nothing shown | - | - | open | - |
| 42 | [Minor] F19. Attribution guard refuses human co-authors and mere mentions | - | - | open | - |
| 43 | [Minor] F20. A failing tool.call hook refuses every tool while guardAttribution is on | - | - | open | - |
| 44 | [Minor] F21. Unattended mode is read from the settings default, not from the session | - | - | open | - |
| 45 | [Minor] F24. session.start arms its timers only after an unguarded chain of reads | - | - | open | - |
| 46 | [Minor] F33. No ASCII rendering; setting problems shown only in the settings view | - | - | open | - |
| 47 | [Minor] F7. A skill-enforced setting changed outside the pane never reaches the session | - | - | open | - |
| 48 | [Minor] H9+F10. The two settings readers resolve an invalid stored value differently | - | - | open | - |
| 49 | [Minor] C17. Claude-settings writes skip the read-modify-write lock | - | - | open | - |
| 50 | [Minor] F9. The darkmem store rows stay editable while darkmem is off | - | - | open | - |
| 51 | [Minor] F34. One press of + on the AgentRouter cap records consent to send files to a third party | - | - | open | - |
| 52 | [Minor, partial] F18. task-close accepts any checkpoint text, and one substring marks a task "review clean" | - | - | open | - |
| 53 | [Minor, partial] A14+F25. The implementer persona and its stop gate describe a retired contract | - | - | open | - |
| 54 | [Minor, partial] H3. A register opened at spec review can keep `**Covers:** -` | - | - | open | - |
| 55 | [Minor, partial] C8. `finish-choice answer` fails when no preference was recorded | - | - | open | - |
| 56 | [Minor, partial] A5. `task-step` ignores `--cwd` for most git calls | - | - | open | - |
| 57 | [Minor, partial] A6. `task-step` keeps backticks and trailing notes on Integration check and Worktree setup | - | - | open | - |
| 58 | [Minor, partial] H12+C21. Reviewer timeout cleanup and descendant processes | - | - | open | - |
| 59 | [Minor, partial] F32. The default flow asks a process question before every request and ends the session after every plan | - | - | open | - |
| 60 | [Minor, partial] H7+F30. Model/effort switch: effortLevel not saved (H7), and a crash before restore leaves the launch model as default (F30) | - | - | open | - |
| 61 | [Minor, partial] H8+A8. Per-session state carried across /clear, /resume and compaction | - | - | open | - |
| 62 | [Minor, partial] A12. Judge guard rejects report paths with spaces or parentheses | - | - | open | - |
| 63 | [Minor, partial] H10+A9. Desktop settings rows: raw numbers in steppers, terminal layout for webhook rows, and a stuck error | - | - | open | - |
