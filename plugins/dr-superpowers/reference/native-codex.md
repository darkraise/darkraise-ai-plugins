# Native Codex execution

This policy applies only when the active host exposes native Codex agent tools.
Identify the host from callable tool schemas, never from a `codex` executable.
If the host is ambiguous, required Superpowers skills are missing, or model and
effort capabilities are not advertised, stop with the missing prerequisite.
Shared skill invocation activates this path; no Claude `Skill` hook is needed.

## Scoring and assignment

Read the four raw axis definitions in [ladder.md](ladder.md). Each axis remains
an integer from 0 through 3. Apply Rule S first: files + spec + coupling must be
less than 4, and spec must be less than 3. Then calculate the native routing score:

`files + spec + coupling + 2 × risk`

The maximum is 9: the reducible subtotal contributes at most 3, weighted risk
at most 6. All scores 0–9 are reachable without weakening Rule S. Claude uses
the unweighted total in ladder.md; its assignment and external CLI tables do
not apply to native Codex.

New plans contain `Host: codex` and `Routing policy: codex-v2`. Every task contains
`Implementer`, `Evaluation`, and `Assignment source: rubric` or `Assignment source: human`.
Native assignments use `codex <model> / <effort>`. Evaluation preserves all four
raw axes and explicitly labels the weighted routing score, for example:

```text
**Implementer:** codex gpt-5.6-sol / high
**Evaluation:** files=1, spec=1, coupling=1, risk=2; weighted routing score=7
**Assignment source:** rubric
```

The machine policy is [codex-routing.json](codex-routing.json):

| Score/rank | Model | Reasoning effort |
| --- | --- | --- |
| 0 | gpt-5.6-luna | low |
| 1 | gpt-5.6-luna | medium |
| 2 | gpt-5.6-terra | low |
| 3 | gpt-5.6-terra | medium |
| 4 | gpt-5.6-terra | high |
| 5 | gpt-5.6-sol | low |
| 6 | gpt-5.6-sol | medium |
| 7 | gpt-5.6-sol | high |
| 8 | gpt-6-astra | high |
| 9 | gpt-6-astra | xhigh |

These tiers are policy choices, not benchmark results. Only currently advertised
and user-allowed model/effort pairs can run; API model availability does not
establish access through a native client or the external CLI.

## Existing plans

Treat an existing assignment without a source as human-pinned. Keep original
assignments fixed; actual attempts, promotions, and substitutions go in the
ledger. The selector rejects codex-v1 and unknown policy versions with a
conversion-required error. Never reinterpret their scores or ranks as v2.

For an old Codex or Claude plan, preview the preserved raw axes, original policy,
old total, new weighted score, and old/proposed assignments. Obtain approval
before recording the converted plan. Recalculate the total from existing axes;
do not change the underlying assessments to fit a preferred tier. If axes are
missing, obtain an explicit evaluation instead of inferring them from the total.
Keep original evaluations and assignments in the conversion record, preserve
human pins, and never automatically translate reserve overrides.

Convert active work only at a reconciled task boundary. Preserve policy-tagged
attempt history and consumed split/review budgets; never relabel old attempts,
fabricate v2 ranks, or reset budgets to make a request pass. If v2 cannot represent
the active history, stop for an explicit handoff decision. A fresh unstarted v2
task can have empty local history while retaining the prior task record.
A Claude `Executor: codex` line never starts recursive CLI offload in a Codex host.

## Selector contract

Intersect currently advertised model/effort pairs with applicable user policy at
planning and again immediately before dispatch. No paid capability probes. Read
[codex-routing.json](codex-routing.json), then run the bundled selector with jq:

```bash
bash <plugin-root>/scripts/select-native-tier.sh --request <request-file>
```

Provide exactly one JSON object with `policy`, `operation` (`assign` or `escalate`),
`role` (`implementer`, `scout`, or `judge`), `assignment_source`, `available_pairs`
objects with model/effort, `attempted_ranks`, `attempted_reserves` (effort names),
`split_consumed`, and `review_rounds`. Rubric requests require
`axes: {files,spec,coupling,risk}`. The selector enforces Rule S and calculates
the score; an optional `score` must be an integer 0–9 equal to that calculation.
The result includes the calculated score even when capability filtering promotes
the returned rank. Missing metadata is an error, not permission to inherit defaults.

This complete example dispatches Sol high when that is the allowed advertised pair:

```json
{
  "policy": "codex-v2",
  "operation": "assign",
  "role": "implementer",
  "assignment_source": "rubric",
  "axes": {"files": 1, "spec": 1, "coupling": 1, "risk": 2},
  "available_pairs": [{"model": "gpt-5.6-sol", "effort": "high"}],
  "attempted_ranks": [],
  "attempted_reserves": [],
  "split_consumed": false,
  "review_rounds": 0
}
```

Human requests use `assignment_source: human` and an explicit
`pinned_pair: {model,effort}`. Axes and score are not used for human selection;
preserve their evaluation in the plan. Human approval can override Rule S or
choose reserve directly, but cannot bypass capability filtering or the review cap.
An unavailable pin or any proposed escalation returns `approval` before substitution.

Initial `assign` requests must have empty attempt histories. Rubric `escalate`
requires prior execution attempts. Execution ranks must be unique and increasing;
reserve efforts follow max then ultra, with skipped unavailable efforts allowed.
Rubric reserve history requires an implementer whose split budget is consumed.
Transport retries reuse the prior dispatch directly; they are not fresh assignment
or capability escalation requests, and do not append duplicate ranks.

Obey the returned action: dispatch the exact pair, obtain approval, split once,
or stop blocked. Invalid requests exit 2 without a decision. Announce promotions
and record every attempt after selection and before launching the agent.

Execution advances monotonically through available higher ranks. After the one
split, reset execution rank history for the new child task while preserving its
parent history and consumed split budget. If that child exhausts execution,
reserve proceeds through Astra max, then ultra, then blocked; skip unavailable
pairs. Once reserve has begun, it takes precedence over newly available execution
tiers. Ultra exhaustion is terminal; neither execution tiers nor max can restart.
Transport retries reuse their exact recorded pair and do not reset rank history,
split budget, or the five-round cap.

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

Scouts start at rank 6 (Sol medium) or above, judges at rank 8 (Astra high) or above.
For rubric routing, evaluate the bounded scout or review brief itself. An
implementer task with spec=3 must first receive approach work; do not submit its
unresolved implementation axes as the scout assignment or invent passing axes.
Every review uses a separate agent context with the full review package, never the implementer's
conversation. Preserve existing criteria scoring, best-of-three approach
selection, three independent evaluations for raw risk 3, and the five-round
review cap. Raw risk stays 0–3; its doubled score contribution is not a new risk
category. Ten execution tiers do not grant ten review rounds.
For native final branch review use independent native reviewer contexts; do not
invoke a Codex CLI round. Independence here does not guarantee cross-provider
review. Record the restriction mode and this limitation in the ledger.

## Claude rename compatibility

On a Claude host only, translate the exact `dr-superpowers:` prefix
to `dr-superpowers:` when its suffix names an existing bundled agent file.
Reject unknown suffixes. Preserve effort, Evaluation, and reserve overrides and
record the namespace translation in the ledger without rewriting the plan.
New Claude plans use `Host: claude` and `Routing policy: claude-v1`, with the
same assignment-source field. Native-to-Claude conversion uses the explicit
preview/approval process above: preserve raw axes and previous assignments, and
explicitly recalculate Claude's unweighted total for its own policy.
