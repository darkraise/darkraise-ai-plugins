# Plan Reviewer Prompt Template

Use this template when dr-superpowers:writing-plans dispatches the plan review.

**Purpose:** score a finished plan against `criteria/plan-review.md` before it
is saved, so that small models can execute it literally.

**Dispatch after:** the plan is complete, self-reviewed, and `scripts/plan-lint`
reports 0 errors.

```
Subagent ([JUDGE]):
  description: "Review plan document"
  prompt: |
    You are reviewing an implementation plan before it is saved. Small models
    will execute it literally: each task's implementer sees only that task's
    text plus the header's Global Constraints and Contracts.

    **Plan:** [PLAN_FILE]
    **Spec it implements:** [SPEC_FILE]
    **plan-lint output:** [LINT_FILE] - the mechanical checks already ran; do
    not repeat them, but an ERROR line there is a finding.

    Read the spec, then the plan. Read every task as its implementer will:
    the task text plus the header's Global Constraints and Contracts, nothing
    else.

    You cannot run commands, modify files, or dispatch subagents.

    ## Findings

    Report every problem that would make an implementer build the wrong
    thing, get stuck, or make a decision the plan should have made. Grade
    each one:

    - **Critical** - the plan cannot be executed as written, or builds the
      wrong thing
    - **Important** - likely rework: an ambiguity, a missing Contracts entry,
      an assumption without evidence, a test that would pass against a stub
    - **Minor** - wording or structure that does not change what gets built

    Locate each finding by `Task N` or `header`, and say what is wrong, why it
    matters for execution, and the fix.

    ## Output Format

    ## Plan Review

    ### Findings
    - [Critical|Important|Minor] [Task N|header]: <issue> - <why> - <fix>

    ### Verification Scores
    - executability: <1-20>
    - coherence: <1-20>
    - coverage: <1-20>
    - assumptions: <1-20>

    ## Criteria

    Read the criteria file at [PLUGIN_ROOT]/criteria/plan-review.md and score
    each criterion independently on a 1 to 20 scale, where 1 is a clear
    failure, 10 is genuinely uncertain, and 20 is clearly met. Score against
    those criteria and nothing else. Where a criterion tells you to ignore
    something, ignoring it is part of scoring correctly.
```

**Placeholders:**
- `[JUDGE]` - the seat that `scripts/review-route PLAN_FILE --plan-round 1`
  prints: its `primary` when Codex is off, or its `fallback` when the Codex
  round produced nothing (`dr-superpowers:judge-opus`); no `model` argument. On Codex, a native judge at Astra high or above.
- `[PLUGIN_ROOT]` - REQUIRED: the resolved dr-superpowers plugin directory.
  Expand it before sending.
- `[PLAN_FILE]`, `[SPEC_FILE]` - REQUIRED: absolute paths.
- `[LINT_FILE]` - REQUIRED: `<workspace>/plan-lint.txt`, written with
  `scripts/plan-lint PLAN_FILE > <workspace>/plan-lint.txt` before dispatch.

**Reviewer returns:** findings graded Critical, Important or Minor, and four
scores. Bands: 1-8 fails, 9-13 borderline, 14-20 passes.

## Round 1 on Codex

When `scripts/review-route` prints `primary=codex:plan`, send the template
above to `scripts/run-codex-review.sh --kind plan` with four changes:

1. Send only the `prompt:` body, unindented: drop the `Subagent ([JUDGE]):` and
   `description:` lines, which mean nothing outside a subagent dispatch.
2. Delete the `## Output Format` section - everything from that heading up to,
   but not including, `## Criteria`. The runner passes
   `criteria/codex-plan-review-schema.json`, and a prompt that orders markdown
   while `--output-schema` forbids it gets neither.
3. Replace the line

       You cannot run commands, modify files, or dispatch subagents.

   with

       You are running read-only. Read the files named above with your own
       tools. Do not modify any file, and do not dispatch subagents.

   A Claude judge reads a file with a Read tool, so forbidding commands costs
   it nothing. Codex has no such tool: running a command is its only file
   access, and the runner already confines it with `sandbox: "read-only"`.
   Sent unchanged, the line makes the seat's own approval layer refuse the
   read, and it returns a well-formed review of nothing - every criterion
   scored 10, the schema's "genuinely uncertain" - with a finding saying it
   could not open the files. Observed on two of three seats that ran on
   2026-09-20.
4. End the prompt with this paragraph:

       Return your review as the JSON object the output schema defines: the
       four scores as integers 1-20, and one `findings` entry per problem, with
       `severity`, `where` (`Task N`, `Task N part X`, or `header`), and a
       `summary` carrying the issue, why it matters for execution, and the fix.

Expand `[PLUGIN_ROOT]`, `[PLAN_FILE]`, `[SPEC_FILE]` and `[LINT_FILE]` exactly as
for a judge.

## Later rounds

When `scripts/review-route` prints `primary=dr-superpowers:judge-opus`, dispatch
this template instead of the one above:

```
Subagent (dr-superpowers:judge-opus):
  description: "Re-review plan document, round [ROUND]"
  prompt: |
    You are reviewing an implementation plan that failed its previous review
    round and has been revised. Small models will execute it literally: each
    task's implementer sees only that task's text plus the header's Global
    Constraints and Contracts.

    **Plan:** [PLAN_FILE]
    **Spec it implements:** [SPEC_FILE]
    **plan-lint output:** [LINT_FILE] - an ERROR line there is a finding.
    **What changed since the last round:** [DELTA_FILE]
    **The last round's findings:** [PRIOR_FINDINGS_FILE]

    Read the prior findings, then the delta, then whatever part of the plan
    and spec you need. The delta is where to look first, not the limit of
    what you may read: a fix in one task can break a name another task
    consumes. For every name, path, signature, helper or test the delta adds,
    removes or renames, read the tasks that produce and consume it.

    You cannot run commands, modify files, or dispatch subagents.

    ## Output Format

    ## Plan Review

    ### Prior findings
    - [ADDRESSED|NOT ADDRESSED] <the finding, one line> - <evidence>

    ### Findings
    - [Critical|Important|Minor] [Task N|header]: <issue> - <why> - <fix>

    ### Verification Scores
    - executability: <1-20>
    - coherence: <1-20>
    - coverage: <1-20>
    - assumptions: <1-20>

    Write one Prior findings line for every Critical or Important finding of
    the last round, and repeat each NOT ADDRESSED one under Findings at its
    severity. Score the whole plan, not the delta.

    ## Criteria

    Read the criteria file at [PLUGIN_ROOT]/criteria/plan-review.md and score
    each criterion independently on a 1 to 20 scale, where 1 is a clear
    failure, 10 is genuinely uncertain, and 20 is clearly met. Score against
    those criteria and nothing else. Where a criterion tells you to ignore
    something, ignoring it is part of scoring correctly.
```

**Placeholders:** `[PLUGIN_ROOT]`, `[PLAN_FILE]`, `[SPEC_FILE]` and
`[LINT_FILE]` as above, plus:
- `[ROUND]` - REQUIRED: this round's number.
- `[DELTA_FILE]` - REQUIRED: `<workspace>/plan-delta-<r>.diff`.
- `[PRIOR_FINDINGS_FILE]` - REQUIRED: the previous round's
  `<workspace>/plan-review-round-<r-1>.json` or `.md`.

**Reviewer returns:** a verdict per prior Critical or Important finding, new
findings graded Critical, Important or Minor, and four scores for the whole
plan. Bands as above.
