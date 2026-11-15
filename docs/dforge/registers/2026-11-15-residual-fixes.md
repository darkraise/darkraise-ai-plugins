# Residual fixes

**Source:** triage of deferred rows, 2026-11-15 (owner: fix in a fresh session; check each against current code first)
**Covers:** -

| # | Item | Assigned | Acceptance | State | Note |
|---|---|---|---|---|---|
| 1 | agy Argon returns an empty review with status SUCCESS on a 9 MB final diff (it reaches for Bash under headless plan mode) | - | - | open | from 2026-11-14-decisions-cache-and-credits.md #7 |
| 2 | run-api-judge's key-in-reply scan is an exact substring match, and the Codex shell inherits DFORGE_JUDGE_KEY (ruling r1: meets the spec; hardening needs a live Codex run) | - | - | open | from 2026-11-14-decisions-cache-and-credits.md #8 |
| 3 | cockpit keep-warm: a turn of another origin that starts between the keep-warm submit and its turn takes the keep-warm mark (ruling r2: narrow window; fix depends on unverified engine turn text) | - | - | open | from 2026-11-14-decisions-cache-and-credits.md #9 |
| 4 | cockpit keep-warm: no test pins the isKeepWarmSubmitted rollback after a failed submit (ruling r4) | - | - | open | from 2026-11-14-decisions-cache-and-credits.md #10 |
| 5 | decide: a lost Decisions charge is a stderr line only, not logged in decisions.jsonl (ruling r5) | - | - | open | from 2026-11-14-decisions-cache-and-credits.md #11 |
| 6 | acceptance A9 sets only OPENAI_API_KEY and ANTHROPIC_API_KEY; the routing-token variables are covered by api-judge.test.sh only (ruling r6) | - | - | open | from 2026-11-14-decisions-cache-and-credits.md #12 |
| 7 | run-api-judge reason=snapshot (a pre-run snapshot that cannot be taken) has no test (ruling r7) | - | - | open | from 2026-11-14-decisions-cache-and-credits.md #13 |
| 8 | Codex judge cost: check whether the last turn.completed usage line of a codex exec --json run is the run's whole cost (a multi-turn run's stream), now that the API keys are set | - | - | open | from 2026-11-14-decisions-cache-and-credits.md #6 |
| 9 | Final review follow-up: one escaping rule for a single quote in bash -c '<cmd>' used by final-review.md step 1, finishing Step 1 and execute-choice.md | - | - | open | from 2026-10-31-test-cost-and-ci.md #6 |
| 10 | Final review follow-up: committed tests for the extra plan-lint rules (waves Integration check, after-task on a waves plan, long digit string, fenced Covered by) and the ci-mirror malformed-line paths | - | - | open | from 2026-10-31-test-cost-and-ci.md #7 |
| 11 | Final review follow-up: delete the remote branch with one git push --force-with-lease=<branch>:<sha> origin :<branch> instead of an ancestor check and a separate delete | - | - | open | from 2026-10-31-test-cost-and-ci.md #8 |
| 12 | spec section 1 wording: the cockpit books the reconcile failure on the fourth window after three prompts; A13 says instead of a fourth prompt. Ruled PARK; the owner may reword section 1 to after the third consecutive reconcile prompt, the next window books the failure | - | - | open | from 2026-10-25-token-efficiency.md #21 |
| 13 | deferred minors of the task-loop run: suite-run maps every exit 137 to timeout 124; no canonical suite command is named for reuse; cmd_rereview duplicates the main path (preflight-10); in-flight paths with spaces are cut; task-step start treats any bracketed capital token such as [WIP] in a task title as an unexpanded placeholder; do_review's jq && mv has no die; acceptance test line 704 asserts a string that never appears; A11's next-step half has no acceptance test; Task 2: symlink check skipped silently where ln -s copies, agent output_file keeps a trailing period, a future mtime prints idle 0m | - | - | open | from 2026-10-25-token-efficiency.md #23 |
| 14 | review-route.test.sh:725: the fenced-Executor test and the real-Executor-line test are redundant (deferred: test-simplifier) | - | - | open | from 2026-11-12-reviewer-only-externals.md #11 |
| 15 | Rewrite the pressure language in plugins/dforge/skills/systematic-debugging/SKILL.md so it states its reasons (ALWAYS, MUST, ESPECIALLY, letter-of-the-process line) | - | - | open | from 2026-10-27-speed-and-cost.md #19 |
| 16 | Remove the tiredness and just-this-once rationalizations and the lying line in plugins/dforge/skills/verification-before-completion/SKILL.md, keeping the Iron Law and Gate Function | - | - | open | from 2026-10-27-speed-and-cost.md #20 |
| 17 | Rewrite the NEVER phrase list in plugins/dforge/skills/receiving-code-review/SKILL.md as a positive instruction and drop the dangling instruction-file reference | - | - | open | from 2026-10-27-speed-and-cost.md #21 |
| 18 | Remove the repeated NEVER summarize and CRITICAL description rule in plugins/dforge/skills/writing-skills/SKILL.md, keeping the reasoned account of lines 154-158 | - | - | open | from 2026-10-27-speed-and-cost.md #22 |
| 19 | Remove the sentence naming the model and effort from the body of every plugins/dforge/agents/*.md file, since frontmatter is the source of truth | - | - | open | from 2026-10-27-speed-and-cost.md #23 |
| 20 | Rewrite the used-to-be checklist history in plugins/dforge/skills/writing-plans/references/assigning-implementers.md to state only that plan-lint checks the rules | - | - | open | from 2026-10-27-speed-and-cost.md #24 |
| 21 | Rewrite the dated codex-v4 vendor narrative in plugins/dforge/reference/native-codex.md, keeping the no-calibration-replay caveat and the v3 rank table | - | - | open | from 2026-10-27-speed-and-cost.md #25 |
| 22 | A6: a structured cannot-verify item in the spec's Design §2 form (no expect) is settled by task-step verdict | - | - | open | from 2026-10-27-speed-and-cost.md #26 |
| 23 | executor_session_mark_fallback_off reads the prior file once, so a lane mark written in the same milliseconds can be overwritten | - | - | open | from 2026-11-03-agy-gemini-first.md #12 |
