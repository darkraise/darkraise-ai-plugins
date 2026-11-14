# Jev decisions, warm cache and credit budgets

**Source:** owner's pasted list in session, 2026-11-14
**Covers:** docs/dforge/specs/2026-11-14-api-decisions-keep-warm-hydrogen-design.md

| # | Item | Assigned | Acceptance | State | Note |
|---|---|---|---|---|---|
| 1 | Use decision API/jev to decice which to do in auto run mode. | docs/dforge/plans/2026-11-14-api-decisions-keep-warm-hydrogen.md | Spec A1-A7, A19, A31: in an auto run a choice item goes first to the Decisions API (decide ask/record/report), and the ladder text starts there | done | - |
| 2 | Need a mechanism when a shell run too long, the cache can be cold quickly while waiting it finish. | docs/dforge/plans/2026-11-14-api-decisions-keep-warm-hydrogen.md | Spec A21-A24, A29: outside an auto run the cockpit submits a keep-warm turn after keepWarm minutes of waiting on background work, at most six in a row | done | - |
| 3 | agy add new model: hydrogen, update it. | docs/dforge/plans/2026-11-14-api-decisions-keep-warm-hydrogen.md | Spec A26-A28: Hydrogen is measured against Argon in ten agy Gemini review runs and takes Argon's roster slots only if it passes the spec's rule | done | - |
| 4 | Utilize the free API credit ($200 for claude, $10 for agy,  $200 for openAI) | docs/dforge/plans/2026-11-14-api-decisions-keep-warm-hydrogen.md | Spec A8-A18, A20, A25, A30: an opus ruling runs first on the Anthropic then the OpenAI API budget, capped and charged; the Google credit stays unused by the owner's answer | verify | A20 owed: one live ruling per budget and a live decide ask once a DFORGE_*_API_KEY is set (row 6) |
| 5 | Utilize other budget of open AI model from agent router | docs/dforge/plans/2026-11-14-api-decisions-keep-warm-hydrogen.md | Spec A11-A18, A20 for the agentrouter budget: an opus ruling falls to an OpenAI model through AgentRouter after the two direct budgets, capped and charged | verify | A20 owed: one live ruling per budget and a live decide ask once a DFORGE_*_API_KEY is set (row 6) |
| 6 | A20: live rulings on the three API budgets and a live decide ask, plus whether Codex's last turn.completed usage line is a run's whole cost | - | - | deferred | final review: no DFORGE_*_API_KEY was set on this host, so A20 and the Codex cost question rest on documentation and stubs; run the CLI-check note's live checks once a key is set |
| 7 | agy Argon returns an empty review with status SUCCESS on a 9 MB final diff (it reaches for Bash under headless plan mode) | - | - | deferred | final review, adjacent: cap the embedded diff size or treat an empty SUCCESS as a failure that moves to the next row |
| 8 | run-api-judge's key-in-reply scan is an exact substring match, and the Codex shell inherits DFORGE_JUDGE_KEY (ruling r1: meets the spec; hardening needs a live Codex run) | - | - | deferred | final review residual |
| 9 | cockpit keep-warm: a turn of another origin that starts between the keep-warm submit and its turn takes the keep-warm mark (ruling r2: narrow window; fix depends on unverified engine turn text) | - | - | deferred | final review residual |
| 10 | cockpit keep-warm: no test pins the isKeepWarmSubmitted rollback after a failed submit (ruling r4) | - | - | deferred | final review residual |
| 11 | decide: a lost Decisions charge is a stderr line only, not logged in decisions.jsonl (ruling r5) | - | - | deferred | final review residual |
| 12 | acceptance A9 sets only OPENAI_API_KEY and ANTHROPIC_API_KEY; the routing-token variables are covered by api-judge.test.sh only (ruling r6) | - | - | deferred | final review residual |
| 13 | run-api-judge reason=snapshot (a pre-run snapshot that cannot be taken) has no test (ruling r7) | - | - | deferred | final review residual |
| 14 | turn-end.test.sh:75 — the 420-character reason cap counts the embedded plugin root path, so the check fails from a long checkout path (pre-existing at main) | - | - | open | - |
| 15 | acceptance A6 check named "holds the choice twice" asserts a count of 3 (the options list holds the option too): rename it or count only the recorded choice | - | - | open | - |
| 16 | claude plugin test sometimes reports "the file did not load" for cockpit.test.ts when several tests fail at once (1 of 3 runs on old code) | - | - | open | - |
| 17 | cockpit keep-warm: the S.waits guard in keepWarm cannot be pinned by a test (a main-loop wait makes the turn live first) | - | - | deferred | final review: rejection upheld in the scoped re-review; A22 waiting-on-the-person is covered through the live-turn path |
