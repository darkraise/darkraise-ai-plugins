## Auto by default (`autoRun=on`)

The default on Claude Code. Only the architectural path changes: a spike or a
bounded task runs as above, and on a Codex host `on` behaves as `off`. Steps 1-5
of the checklist run as written; the execution-strategy question is asked only
when the setting is `ask`. Then:

1. **Write the spec directly.** Present no design section and ask no
   acceptance question first. One spec covers the whole request: no
   sub-project decomposition, no program spec, no `**Program:**` line. A new
   product still goes to dforge:planning-a-product.
2. **Record the decisions.** Below its `**Execution strategy:**` and
   `**Depth:**` lines the spec carries a `## Decisions` section: every
   clarifying question and approach
   choice, with your human partner's answer quoted. The critic and Fable check
   the spec against it in place of approved design sections.
3. **Acceptance in the spec.** Draft and rate the statements as Drafting
   acceptance says, but ask nothing yet: a statement rated below `high` keeps
   its `Q:` until the spec review.
4. **Reviews before the stop,** by the spec's depth. At `light`, run the spec
   self-review round and nothing else: no critic, no Fable review, no
   `## Review rulings` section. At `standard`, run it, then one
   `dforge:judge-fable` round on the spec against its `## Decisions` with the
   critic folded into it (Architecture critic), and no second round. At
   `full`, run it, then the architecture critic, then `dforge:judge-fable` on
   the spec against its `## Decisions`: one round, and a second only when
   round 1 leaves a Blocker or High finding open, checking only those
   answers. Apply what Fable rules and list each ruling as one line in a
   `## Review rulings` section of the spec.
5. **The spec review**, the one stop: one message, its questions asked with the
   multiple-choice prompt, at most four per call:
   - the spec path, `Depth: <d> — <reasons>` (the `depth=` and `reason=` of
     `scripts/depth-route --spec-triggers`, or `owner`), the `Critic: …` counts
     (at `light`, `Critic: skipped (depth light)`) and the number of Fable
     rulings;
   - every statement rated below `high`, asked as Drafting acceptance asks it;
     a deferral runs
     `scripts/register add <register> "A<n>: <statement>" --state deferred --note "Q: <question>"`;
     with no register open, first open `<docs>/registers/<date>-<spec-slug>.md`
     as Opening an item register says;
   - every item Fable left undecided, and every critic Blocker it did not
     settle, with the recommended option first;
   - when `finishAction` is `ask`: merge into `<current branch>`, open a pull
     request, or keep the branch, recorded as its own paragraph (no list
     marker, nothing after the value) holding one
     `Finish: <merge|pr|keep>` line in `## Decisions`;
   - **Approve and run unattended**, **Approve, keep the normal stops**, or
     **Changes needed**.

   At `light`, the **Approve, keep the normal stops** option adds "(depth
   light: the plan is not a stop; execution follows in this session)". Your
   human partner sets the depth by hand under **Changes needed**: write
   `**Depth:** <d> — owner` in the spec. The plan checkpoint can still raise
   it, and the ratchet never replaces an owner line.

   Apply the answers to the spec. **Changes needed** gets the revision and one
   new self-review round; the critic and Fable do not run again. Then present
   this step's message again, with the questions still open, until your human
   partner picks one of the two approvals.
   `specReview=false` does not skip this stop.
6. **Start the run.** On **Approve and run unattended**, commit the spec and
   the register, run `scripts/auto-run start --spec <spec>` (add
   `--register <path>` when a register is open, and always the register
   step 5's deferrals went to), then import each
   `## Review rulings` line with
   `scripts/auto-run ruling add "Fable, spec: <line>"` (none at depth light).
   Invoke dforge:writing-plans in this session: `scripts/context-size --plan`
   does not run. On exit 2 or 4 from `start`, say why in one line and continue
   as **Approve, keep the normal stops**.
7. **Approve, keep the normal stops** commits the spec and the register and
   continues at Implementation below, with no run.

From step 6 on, [auto-run.md](../../../reference/auto-run.md) applies.
