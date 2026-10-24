# Auto run: ui-ux-skill

**Source:** items the auto run for `docs/dforge/specs/2026-10-24-ui-ux-skill-design.md` deferred
**Covers:** docs/dforge/specs/2026-10-24-ui-ux-skill-design.md

| # | Item | Assigned | Acceptance | State | Note |
|---|---|---|---|---|---|
| 1 | ui-ux: a UI file name containing a newline is still missed by the gate (names with a quote or backslash are handled) | - | - | n/a | git hash-object --stdin-paths cannot carry a newline in a path; not worth threading -z through every helper |
| 2 | ui-ux: ui-turn-end.sh accepts 'UI proof: pending' anywhere in the last message, with or without a reason | - | - | done | 9a07226c: only a closing line with a reason releases the hold |
| 3 | ui-ux: lens-route reads **Spec:** only as a backticked or bare path; a Markdown-link spec reference drops the spec-contract trigger | - | - | n/a | plan-lint rejects a Markdown-link Spec line; next-step, task-brief and finish-choice parse it the same way |
| 4 | ui-ux: no test asserts the *.test.* exclusion reaches lens routing (use app.test.tsx, not .ts) | - | - | done | f3fee152 |
| 5 | ui-ux: option 2 of finishing Step 1b's two-option prompt names no next step | - | - | done | b74194a1: option 2 records keep and runs Option 3 |
| 6 | ui-ux: the post-fix-wave Prove re-run in final-review.md has no defined end in an auto run (step 0.2 and finishing Step 1b catch it) | - | - | done | b74194a1: an auto run goes on to finishing Step 1b |
| 7 | ui-ux: several proof reports with the current fingerprint - only the last in sort order is checked | - | - | done | ac81820b: any passing report at the fingerprint proves the UI |
| 8 | ui-ux: uiux_filter and uiux_files loop over every tracked file in bash; slow in a very large repository | - | - | done | 34a33c39: one awk pass; 50000 paths 10.7 s -> 0.13 s |
| 9 | ui-ux: using-dforge dropped 'or a checklist' from the no-todo-tool line to stay under 5100 bytes | - | - | done | 34c06088 |
| 10 | ui-ux: tests/fixtures/ui-ux/walkthrough.html matches the default UI globs; held by the Stop hook in a session that ran the skill | - | - | n/a | holding an edited HTML page is intended; the pending line releases it |
| 11 | ui-ux: ui-lint reports a one-line ':root { --brand-color: #hex }' in a non-token file as raw-color (the exemption needs the declaration to start the line) | - | - | done | a5b90af9 |
| 12 | ui-ux: long unwrapped lines in lens-route, native-codex.md, final-review.md and the finishing skill | - | - | done | 040ca0f3: prose lines the ui-ux commits added; tables and code left |
| 13 | cockpit: two tests in plugins/dforge/tests/cockpit.test.ts fail on main (a Done held for background work, subagent approval); found by the ui-ux run, not caused by it | - | - | done | 1397eadb: CLI 2.1.310's $.tool.call runs tool.check, so the blanket ask denied hold()'s shell; tests now ask only for subagent calls |
