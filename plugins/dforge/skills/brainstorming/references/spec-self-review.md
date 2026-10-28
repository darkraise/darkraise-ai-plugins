**Spec Self-Review:**
After writing the spec document, look at it with fresh eyes. This round is
required, and it is yours: run it once, never through a subagent.

1. **Placeholder scan:** Any "TBD", "TODO", incomplete sections, or vague requirements? Fix them.
2. **Internal consistency:** Do any sections contradict each other? Does the architecture match the feature descriptions?
3. **Scope check:** Is this focused enough for a single implementation plan, or does it need decomposition (not under `autoRun=on` on Claude Code)?
4. **Ambiguity check:** Could any requirement be interpreted two different ways? If so, pick one and make it explicit.
5. **Execution strategy:** The `**Execution strategy:**` line is present. When it says parallel, every file in the Parallel decomposition has exactly one owner, and no part that may run beside another consumes its output. The `**Depth:**` line is present below it, and its first word is `light`, `standard` or `full`.
6. **Acceptance:** The `## Acceptance` section is present, every statement matches `A<n>. [<test|demo>[, neg], <high|confirmed>] <statement>` and is checkable by a test or a demo, at least one carries `neg`, and no rating other than `high` or `confirmed` appears. Under `autoRun=on`, a statement rated `medium` or `low` passes when it carries its `Q:`; the spec review settles it.
7. **Riskiest assumption:** The `## Riskiest assumption` section is present and names its evidence, or reads `unverified — the plan's first task verifies it`.

Fix any issues inline, then post `Self-review (round 1 of 1):` with one line
per item: clean, or what you fixed. Do not re-review after fixing.
A revision your human partner asks for gets one new round.
