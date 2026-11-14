# Jev decisions, warm cache and credit budgets

**Source:** owner's pasted list in session, 2026-11-14
**Covers:** docs/dforge/specs/2026-11-14-api-decisions-keep-warm-hydrogen-design.md

| # | Item | Assigned | Acceptance | State | Note |
|---|---|---|---|---|---|
| 1 | Use decision API/jev to decice which to do in auto run mode. | docs/dforge/plans/2026-11-14-api-decisions-keep-warm-hydrogen.md | Spec A1-A7, A19, A31: in an auto run a choice item goes first to the Decisions API (decide ask/record/report), and the ladder text starts there | planned | - |
| 2 | Need a mechanism when a shell run too long, the cache can be cold quickly while waiting it finish. | docs/dforge/plans/2026-11-14-api-decisions-keep-warm-hydrogen.md | Spec A21-A24, A29: outside an auto run the cockpit submits a keep-warm turn after keepWarm minutes of waiting on background work, at most six in a row | planned | - |
| 3 | agy add new model: hydrogen, update it. | docs/dforge/plans/2026-11-14-api-decisions-keep-warm-hydrogen.md | Spec A26-A28: Hydrogen is measured against Argon in ten agy Gemini review runs and takes Argon's roster slots only if it passes the spec's rule | planned | - |
| 4 | Utilize the free API credit ($200 for claude, $10 for agy,  $200 for openAI) | docs/dforge/plans/2026-11-14-api-decisions-keep-warm-hydrogen.md | Spec A8-A18, A20, A25, A30: an opus ruling runs first on the Anthropic then the OpenAI API budget, capped and charged; the Google credit stays unused by the owner's answer | planned | - |
| 5 | Utilize other budget of open AI model from agent router | docs/dforge/plans/2026-11-14-api-decisions-keep-warm-hydrogen.md | Spec A11-A18, A20 for the agentrouter budget: an opus ruling falls to an OpenAI model through AgentRouter after the two direct budgets, capped and charged | planned | - |
