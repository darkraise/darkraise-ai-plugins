---
type: llm
weight: 1
---

The reply must be a dflow plan document in the plugin's format.

Pass when all of these hold:

- A header with Goal, Acceptance, Docs and Risk. Every Acceptance line either
  holds a command in backticks or is marked `UI`.
- Risk is `concurrency` (or a task carries that risk), because reads and
  resets can overlap.
- A Design section that states decisions with their reasons and the exact
  signatures or data shapes, and holds no implementation code.
- Tasks headed `### Task N: …`, each with Files, After, Run and Size, test
  assertions listed as steps, and a `Verify:` step holding a command.
- No task contains a block of implementation code.

Fail when:

- the plan contains function bodies or other implementation code;
- a task has no verify command, or Acceptance lines have no command;
- the overlap of reads and resets is not treated as a risk anywhere; or
- the reply is a prose description instead of the plan document.
