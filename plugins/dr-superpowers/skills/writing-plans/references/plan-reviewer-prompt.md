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
- `[JUDGE]` - `dr-superpowers:judge-fable`, or `dr-superpowers:judge-opus` when
  Fable is unavailable or declined (say the substitution aloud); no `model`
  argument. On Codex, a native judge at Astra high or above.
- `[PLUGIN_ROOT]` - REQUIRED: the resolved dr-superpowers plugin directory.
  Expand it before sending.
- `[PLAN_FILE]`, `[SPEC_FILE]` - REQUIRED: absolute paths.
- `[LINT_FILE]` - REQUIRED: `<workspace>/plan-lint.txt`, written with
  `scripts/plan-lint PLAN_FILE > <workspace>/plan-lint.txt` before dispatch.

**Reviewer returns:** findings graded Critical, Important or Minor, and four
scores. Bands: 1-8 fails, 9-13 borderline, 14-20 passes.
