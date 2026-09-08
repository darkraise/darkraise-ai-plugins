# Native Codex execution

This policy applies only when the active host exposes native Codex agent tools.
Identify the host from callable tool schemas, never from a `codex` executable.
If the host is ambiguous, required Superpowers skills are missing, or model and
effort capabilities are not advertised, stop with the missing prerequisite.
Shared skill invocation activates this path; no Claude `Skill` hook is needed.

## Assignment and migration

Apply the existing four-axis rubric and Rule S before routing. New plans contain
`Host: codex` and `Routing policy: codex-v1`. Every task contains `Implementer`,
`Evaluation`, and `Assignment source: rubric` or `Assignment source: human`.
Native assignments use `codex <model> / <effort>`.

Treat an existing assignment without a source as human-pinned. Keep original
assignments fixed; actual attempts, promotions, and substitutions go in the
ledger. A plan authored for Claude requires a conversion preview showing old
and proposed assignments, preserving Evaluation and the prior assignment. Wait
for approval before adding Codex assignments. Do not rescore during conversion
or automatically translate reserve overrides. A Claude `Executor: codex` line
never starts recursive external CLI offload in a Codex host.

Intersect currently advertised model/effort pairs with applicable user policy at
planning and again immediately before dispatch. No paid capability probes. Read
[codex-routing.json](codex-routing.json), then run the bundled selector with jq:

```bash
bash <plugin-root>/scripts/select-native-tier.sh --request <request-file>
```

The request contains `policy`, `operation` (`assign` or `escalate`), `role`
(`implementer`, `scout`, or `judge`), score 0–6, `assignment_source`, a
`pinned_pair` for human assignments, `available_pairs` objects with model/effort,
`attempted_ranks`, `attempted_reserves` (effort names), `split_consumed`, and
`review_rounds`. Missing metadata is an error, not permission to inherit defaults.
Obey the returned action: dispatch the exact pair, obtain approval, split once,
or stop blocked. Announce promotions and record every attempt before dispatch.

Execution advances monotonically through available higher ranks. After the one
split, reset execution rank history for the new child task while preserving its
parent history and consumed split budget. If that child exhausts execution,
reserve proceeds through Astra max, then ultra, then blocked; skip unavailable
pairs. Never revisit reserve once exhausted. Transport retries reuse their exact
recorded pair and do not reset rank history, split budget, or the five-round cap.

## Dispatch and review

Use the active native dispatch schema with an isolated context and explicit
model and reasoning effort. Never assume full-history forks accept overrides.
Include all of the following directly in each child's task message:

- Its implementer, scout, or judge role and the applicable role instructions.
- Task brief, approved files, repository instructions, and relevant criteria.
- The verification-before-completion instructions and required evidence.
- Its exact model/effort and the expected report format.
- For scouts/judges: no file writes and no further delegation.

Claude agent frontmatter does not supply native restrictions or skill context.
Apply enforced per-agent read-only restrictions when the active tool supports
them. Otherwise disclose that the restrictions are instruction-only, ensure no
concurrent writers, and take a snapshot before and after the review:

```bash
source <plugin-root>/scripts/lib/task-state.sh
dr_snapshot <worktree> <snapshot-file-outside-worktree>
dr_task_assert_snapshot <snapshot-file-outside-worktree>
```

Any HEAD, index, tracked-file, or untracked-file change invalidates the review
and blocks continuation. Preserve those changes for inspection. These snapshots
detect drift, not authorship. If user/task policy requires enforced isolation,
stop when the client cannot provide it; instruction-only review is unavailable.

Resume the recorded implementer for fix rounds when supported, using the same
pair and task state. If resume is unsupported, report the lost context and use
a fresh isolated implementer with the complete fix package under the recorded
assignment; do not silently inherit the controller's model.

Scouts start at rank 3 or above, judges at rank 5 or above. Every review uses a
separate agent context with the full review package, never the implementer's
conversation. Preserve existing criteria scoring, best-of-three approach
selection, three independent risk-3 evaluations, and the five-round review cap.
For native final branch review use independent native reviewer contexts; do not
invoke a Codex CLI round. Independence here does not guarantee cross-provider
review. Record the restriction mode and this limitation in the ledger.

## Claude rename compatibility

On a Claude host only, translate the exact `dcc-superpower-companions:` prefix
to `dr-superpowers:` when its suffix names an existing bundled agent file.
Reject unknown suffixes. Preserve effort, Evaluation, and reserve overrides and
record the namespace translation in the ledger without rewriting the plan.
New Claude plans use `Host: claude` and `Routing policy: claude-v1`, with the
same assignment-source field. Native-to-Claude conversion uses the explicit
preview/approval process above and preserves previous assignments.
