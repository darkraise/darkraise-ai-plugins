---
type: llm
weight: 1
---

dflow's test rules allow one test per behaviour and none for wording that no
program parses, constants or how the code is written.

Pass when the response:

- writes a task with test steps for the two behaviours (the normal case and the
  zero case), adding cases to the existing table in `tests/format.test.js`
  rather than a new file;
- declines to add tests for the constant and for the use of template strings,
  saying why; and
- either declines to pin the exact wording or says the wording is asserted only
  as part of the behaviour's one test, not in tests of its own.

Fail when the response:

- lists a separate test for the constant, or for template strings;
- adds several tests that differ only in the message wording; or
- creates a new test file although a table exists.
