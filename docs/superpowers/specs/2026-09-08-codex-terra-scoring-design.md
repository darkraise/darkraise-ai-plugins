# Native Codex Terra and 0–9 scoring

Status: Implemented and validated on 2026-09-08 for native Codex only, version
0.6.0. See the [execution record](../plans/2026-09-08-codex-terra-scoring.md).

## Decision

Introduce `codex-v2`, adding Terra between Luna and Sol and expanding the native
assignment score to integers 0–9. Keep the four existing axis definitions, each
scored 0–3, but calculate the native routing score as:

`files + spec completeness + coupling + 2 × risk`

Keep Rule S: split when files + spec completeness + coupling is at least 4;
settle the design before assigning when spec completeness is 3. After the gate,
the reducible subtotal is at most 3 and weighted risk contributes at most 6.
All ten scores are reachable without allowing larger tasks through the gate.

Record the four raw axes and the weighted routing score explicitly. A security,
data-loss, migration, or concurrency task still has raw risk 3; the independent
review requirement continues to use that raw risk, not the weighted contribution.

For example, files 1, spec 1, coupling 1, risk 2 gives native score 7. It remains
a bounded task and routes to Sol high.

## Assignment table

| Score | Model | Reasoning effort |
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

Scouts retain Sol medium as their minimum, now rank 6. Judges retain Astra high,
now rank 8. Reserve remains Astra max followed by ultra after the one permitted
split has been exhausted. The five-round review cap remains separate from the
number of model tiers; a task is not entitled to attempt all tiers.

Terra's placement is a policy recommendation informed by OpenAI's documented
model positioning, not a benchmark result. Exact cross-model effort comparisons
remain unmeasured. Only pairs advertised by the active native tool and allowed
by user policy may be dispatched. API documentation does not establish access
through a particular Codex account or CLI.

## Alternatives considered

Raising the reducible subtotal limit to 6 would also allow an unweighted maximum
of 9, but would admit tasks the current policy requires splitting. Merely
rescaling the old total would leave some of the ten integer rows unreachable.
Weighting risk supplies ten meaningful scores while preserving decomposition.

## Routing safeguards and existing plans

The selector must validate the four axes and calculate the score itself for
rubric assignments, including Rule S. Reject a supplied score that disagrees
with the calculation. Human-pinned assignments remain explicit overrides and
require approval before substitution.

Reject an initial assignment request that carries previous attempts. Once
reserve has begun, evaluate reserve progress before execution availability;
a newly advertised execution tier cannot return a task to a lower tier. Exhausted
ultra is terminal. Preserve the existing explicit split budget and review cap.

Never interpret `codex-v1` ranks as `codex-v2` ranks. Require an explicit conversion
preview for old plans, showing raw axes, old and proposed scores, and old and
proposed assignments. Preserve the original plan evaluation, human pins, and
attempt history. Conversion of an active task requires reconciliation at a task
boundary; do not relabel its existing attempts or reset its budgets. Unsupported
policy versions produce a conversion-required error rather than an automatic
substitution. Claude-to-Codex conversion must recalculate the weighted score from
preserved raw axes and disclose the change for approval.

## Implementation scope and verification

Update the native policy, selector, native execution reference, the three shared
skill host branches, and README. Keep Claude's existing rubric and external CLI
table distinct from native scoring. Clarify the CLI table's historical evidence.
Update both dr-superpowers manifests to the same next minor release.

Extend native routing tests to cover every reachable score, gate rejection,
score/axis disagreement, Terra capability gaps, role floors, human overrides,
policy conversion errors, changing capabilities after reserve, inconsistent
assignment history, split limits, and review limits. Use local fixtures without
paid model calls. Run the existing Claude ladder/lane tests and repository
validation to catch shared-skill and packaging regressions.

## Sources checked on 2026-09-08

- [GPT-5.6 Terra](https://developers.openai.com/api/docs/models/gpt-5.6-terra)
  describes Terra as balancing intelligence and cost and lists reasoning efforts.
- [OpenAI model comparison](https://developers.openai.com/api/docs/models/compare)
  distinguishes Terra, Sol, and Astra positioning.
