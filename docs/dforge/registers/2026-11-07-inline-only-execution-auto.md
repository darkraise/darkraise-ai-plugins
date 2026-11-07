# Auto run: inline-only-execution

**Source:** items the auto run for `docs/dforge/specs/2026-11-07-inline-only-execution-design.md` deferred
**Covers:** docs/dforge/specs/2026-11-07-inline-only-execution-design.md

| # | Item | Assigned | Acceptance | State | Note |
|---|---|---|---|---|---|
| 1 | setup.md's owner-request bullet commits an Execution-line edit to subagent, while next-step's comment says a switch lives in the ledger and the plan is never edited; plan-lint WARNs on the edited line and no test pins the route | - | - | done | ruled: an owner request writes the escalation ledger line; the plan is never edited; pinned by inline-mode and A11 tests |
| 2 | Stale wording: plugins/dforge/README.md:1166 says the Execution line decides inline or subagent execution, README.md:460 says tiered dispatch, root README.md:24 says a tiered execution run | - | - | done | ruled: README wording follows inline-only, plus README item 10 and the deprecation sentence |
