---
type: llm
weight: 1
---

The change touches a couple of files, holds no open decision and carries no
risk, so the right process is no plan at all.

Pass when the response:

- says no plan document is needed for this change (for example a `Depth: none`
  line), and
- describes changing or adding the test first, then the constant, then running
  the tests that cover it and committing.

Fail when the response:

- proposes writing a plan, a spec or a design document, or running
  `dflow plan new`, for this change;
- asks the user clarifying questions before proceeding; or
- skips the test.
