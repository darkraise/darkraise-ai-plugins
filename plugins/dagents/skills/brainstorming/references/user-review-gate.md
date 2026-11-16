**User Review Gate:**
Under `autoRun=on`, this gate is the spec review message in Auto by default.
In an auto run (`scripts/auto-run status` exits 0), skip this gate: run the
Fable spec review in [auto-run.md](../../../reference/auto-run.md) §The spec, then
go to Implementation.
Outside `autoRun=on`, the `specReview` setting can skip this gate.
With `specReview=false` (see Settings), skip this gate and go to Implementation.
Otherwise, after posting the self-review block, ask the user to review the
written spec before proceeding:

> "Spec written and committed to `<path>`. Depth: <d> — <reasons>. Critic: <b> Blocker, <h> High (<f> fixed, <a> answered), <m> Medium. Please review it and let me know if you want to make any changes before we start writing out the implementation plan."

At depth light, `Critic: skipped (depth light)` replaces the counts. Your human
partner may set the depth in the reply; write `**Depth:** <d> — owner` in the
spec.

Wait for the user's response. If they request changes, make them and run one new self-review round. Only proceed once the user approves.
