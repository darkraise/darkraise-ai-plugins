---
type: llm
weight: 1
---

The diff removes the floor at zero, so `remaining(5, 9)` is now -4, which breaks
acceptance line A1.

Pass when the response records the defect with `dflow review add` and:

- cites `src/usage.js` and the changed line;
- grades it `blocking`, since an acceptance line is not met;
- states what breaks; and
- gives `--cmd` evidence that exits non-zero while the defect exists and would
  exit zero once it is fixed (for example a one-line `node -e` check of a
  negative case). The existing test command is not valid evidence: it passes.

Fail when the response:

- reports the finding only as prose, with no `dflow review add` command;
- gives evidence that passes today, or none;
- grades it `nit` or `should`; or
- fixes the code without recording the finding.
