---
type: llm
weight: 1
---

The change touches a couple of files, holds no open decision and carries no
risk, so the right process is no plan at all. This case is a guard: it fails
when the plugin makes Claude run a planning process for a trivial change.

Pass when the response:

- says no plan document is needed for this change, or simply proposes none, and
- puts the test before the constant: it updates or adds the test first, then
  changes the constant, then runs the tests that cover it.

A closing line that waits for the go-ahead is fine: the prompt asked for the
steps only. So is leaving the commit to the user.

Fail when the response:

- proposes writing a plan, a spec or a design document, or running
  `dflow plan new`, for this change;
- asks questions about scope or design before it will proceed; or
- changes the constant before touching the test, or skips the test.
