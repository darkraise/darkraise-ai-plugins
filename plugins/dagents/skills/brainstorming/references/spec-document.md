**Documentation:**

- Write the validated design (spec) to `<docs>/specs/YYYY-MM-DD-<topic>-design.md`
  - (User preferences for spec location override this default)
- Every architectural spec carries a `**Depth:**` line directly below its
  `**Execution strategy:**` line: `**Depth:** <light|standard|full> — <reason ids>`,
  the `depth=` and `reason=` that `scripts/depth-route --spec-triggers`
  printed for the Process line's triggers, or `**Depth:** <d> — owner` when
  your human partner set it. `## Decisions` sits below it. A spec without the
  line routes at `full`.
- Every spec has an `## Acceptance` section holding the statements settled in
  Drafting acceptance, one per line in the form
  `A<n>. [<test|demo>[, neg], <high|confirmed>] <statement>`. Cover the main
  path, the errors and edge cases, and at least one thing that must not happen
  (`neg`). State observable behaviour, not the implementation, and give a word
  like "fast" its number. When a register covers the spec, a row's Acceptance
  cell can cite these numbers.
- Every spec has a `## Riskiest assumption` section: the one assumption that,
  if wrong, sinks the design, with its evidence (a command and the date it ran,
  a `file:line`, or a documentation URL). Without evidence, find out before the
  plan, as cheaply as correctness allows, and record what you found. When only
  code the plan builds can tell, write
  `unverified — the plan's first task verifies it`, so a wrong design fails
  before the rest is built on it.
- Use elements-of-style:writing-clearly-and-concisely skill if available
- Commit the design document to git (push instead while documents live in darkmem; see project-state.md)
