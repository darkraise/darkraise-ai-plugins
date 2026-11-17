## Score every task

Every task records its score, so the Execution line's floor and the risk-3
tasks a judge reviews are properties of the plan rather than judgments made
from memory during execution. Do this after the tasks are drafted and before
the plan is committed. Retrofitting an existing plan is the same process: read
it, score each task, and add the lines.

**Codex host:** follow [native-codex.md](../../../reference/native-codex.md) — its
`codex-v4` selector, plan headers and conversion rules replace the Claude
floor table below.

1. **Score** each task on the four axes in
   [ladder.md](../../../reference/ladder.md) — files, spec completeness,
   coupling, risk. Never restate its tables or work from memory. Score the
   task as its brief will carry it — the task text plus the header's Global
   Constraints and Contracts: if those contain the complete code and exact
   signatures, spec completeness is 0. Count file shapes, not file instances.
   A Claude plan's code task carries its test contracts and interfaces but no
   implementation, so it scores spec 2.
2. **Apply Rule S before the table.** On a Claude plan, if
   `files + spec + coupling >= 6`, split the task where a reviewer could
   reject one half while approving the other, and re-score both halves; on a
   `Host: codex` plan, if it is `>= 4`, do the same. If `spec = 3`, the
   approach is undecided: settle it with dforge:selecting-approaches, rewrite
   the task with the decision in its steps, and re-score. Never answer a
   reducible axis with a bigger model.
3. **Read the floor.** The execution floor table in ladder.md maps the
   highest total to the least model and effort the Execution line may name;
   see [execution-line.md](execution-line.md).
4. **Write the lines** directly below the task's `**Depends on:**` line, or
   its `**Items:**` line, or its `**Interfaces:**` block when it has neither,
   in this order:
   - `**Evaluation:**` — always, for example
     `files 0 - spec 1 - coupling 1 - risk 0 = 2`
   - `**Approach:**` — only when the task involved an approach decision:
     `inline` or `advisor`, a dash,
     and a one-line reason; an
     `inline` reason cites a skip condition by number
   - `**Lenses:**` — only on a task scored risk 3, and optional there: the
     lens ids under `criteria/lenses/` that match why the task is risky,
     comma-separated, for example `security` for an authentication change. The
     task's Claude review seat reads them as defect patterns; `plan-lint`
     rejects the line below risk 3 and an id with no lens file. The line
     names part ids (`lang-bash`, `type-design`, ...), never `code-quality`,
     which has no lens file.

   ```markdown
   **Evaluation:** files 1 - spec 0 - coupling 2 - risk 2 = 5
   **Approach:** inline - skip 2: follows the existing exporter pattern
   ```

5. **Keep the heading form** `### Task N: <name>`: `scripts/task-brief` finds a
   task by a heading that begins with `Task <N>`.

A kept `spec = 3` carries an `**Override:** <reason>` line below the
Evaluation line, and `plan-lint` then reports it as a warning. Never write an
Override line yourself. Write no `**Implementer:**` line: an older plan's is
ignored. No task carries an `**Executor:**` line: `plan-lint` warns that one
is obsolete.
[assigning-implementers.md](assigning-implementers.md) explains why
each of these rules exists.
