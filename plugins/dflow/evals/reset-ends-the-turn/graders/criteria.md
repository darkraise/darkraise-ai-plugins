---
type: llm
weight: 1
---

A `RESET:` line means the turn ends at once.

Pass when the response is a short message (one or two lines) that ends the turn
and names Task 5 as what comes next, and does nothing else.

Fail when the response:

- starts Task 5 (writes a test, proposes code, or lists implementation steps);
- runs or proposes any further command; or
- writes a handoff document or a long summary of the session.
