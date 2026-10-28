## Assign an implementer to every task

Every task records which implementer runs it, so the choice is a property of
the plan rather than a judgment made from memory at dispatch time. Do this
after the tasks are drafted and before the plan is committed. Retrofitting an
existing plan is the same process: read it, rename any skill or agent written
under an older plugin prefix to its `dforge:` name, score each task, and add
the lines.

**Codex host:** follow [native-codex.md](../../../reference/native-codex.md) — its
`codex-v4` selector, plan headers, assignment-source fields, and conversion
rules replace the Claude table, fleet, and external CLI lane below. Honor the
user's inline or delegation preference on either host.

1. **Score** each task on the four axes in
   [ladder.md](../../../reference/ladder.md) — files, spec completeness,
   coupling, risk. Never restate its tables or work from memory. Score the
   task as its brief will carry it — the task text plus the header's Global
   Constraints and Contracts: if those contain the complete code and exact
   signatures, spec completeness is 0. Count file shapes, not file instances.
   A Claude plan's code task carries its tests and interfaces but no
   implementation, so it scores spec 2.
2. **Apply Rule S before the table.** On a Claude plan, if
   `files + spec + coupling >= 6`, split the task where a reviewer could
   reject one half while approving the other, and re-score both halves; on a
   `Host: codex` plan, if it is `>= 4`, do the same. If `spec = 3`, the
   approach is undecided: settle it with dforge:selecting-approaches, rewrite
   the task with the decision in its steps, and re-score. Never answer a
   reducible axis with a bigger model.
3. **Assign** from the assignment table, which the total indexes directly.
   Never assign a reserve agent — any `xhigh` or `max` effort, any Fable
   tier. Only a human edit puts one in a plan.
4. **Offer an external executor** and apply the lane gate — see
   [executor-lane.md](../../../reference/executor-lane.md) §Planning. Every id
   `scripts/executors list` prints has its own gate; run each, resolved with
   `bash "$(bash scripts/executors path <id> gate)"`, before the roster, and
   make the offer once per plan
   for every executor whose gate prints `lane=true`. If none is usable, ask
   nothing.
5. **Write the lines** directly below the task's `**Depends on:**` line, or
   its `**Items:**` line, or its `**Interfaces:**` block when it has neither,
   in this order:
   - `**Implementer:**` — always; the fully qualified agent, for example
     `dforge:impl-sonnet-low`
   - `**Executor:**` — only when the lane gate passed, for example
     `codex gpt-6.1-sol / low`
   - `**Evaluation:**` — always, for example
     `files 0 - spec 1 - coupling 1 - risk 0 = 2`
   - `**Approach:**` — only when the task involved an approach decision:
     `inline`, `advisor`, or `best-of-3`, a dash, and a one-line reason; an
     `inline` reason cites a skip condition by number
   - `**Lenses:**` — only on a task scored risk 3, and optional there: the
     lens ids under `criteria/lenses/` that match why the task is risky,
     comma-separated, for example `security` for an authentication change. The
     task's Claude review seat reads them as defect patterns; `plan-lint`
     rejects the line below risk 3 and an id with no lens file.

   ```markdown
   **Implementer:** dforge:impl-sonnet-high
   **Evaluation:** files 1 - spec 0 - coupling 2 - risk 2 = 5
   **Approach:** inline - skip 2: follows the existing exporter pattern
   ```

6. **Keep the heading form** `### Task N: <name>`: `scripts/task-brief` finds a
   task by a heading that begins with `Task <N>`.

**A task carries at most one `**Executor:**` line, and you choose it.** When
two ticked executors' gates both admit a task, nothing mechanical picks
between them: write one line, and `plan-lint` validates only what is written.
No precedence rule is introduced here — with one registered executor there is
no choice to make, and a rule invented now would be untested against a real
second executor.

A human may edit any `**Implementer:**` line by hand;
dforge:subagent-driven-development obeys it and never recomputes.
Leave the `**Evaluation:**` line in place — the gap between the score and the
choice is the interesting part. A hand edit that breaks a checked rule — a
reserve tier, a kept `spec = 3`, a table mismatch — carries an
`**Override:** <reason>` line below the Evaluation line, and `plan-lint` then
reports it as a warning. Never write an Override line yourself. Under
dforge:executing-plans the lines are read for the delegated tasks,
which include every task carrying an `**Executor:**` line.
[assigning-implementers.md](assigning-implementers.md) explains why
each of these rules exists.
