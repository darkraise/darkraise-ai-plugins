# r-code-executor-interface

Source: the final-review fix commit `58885f9`, reviewed at head `1f13cc8`.

## D1: an executor whose gate block is missing from the ladder passes the lane gate

- Where: `plugins/dr-superpowers/scripts/plan-lint`, the `**Executor:**` check and the lane-candidate loop
- Defect: the gate bounds are read with defaults, `${emin:-0}` and `${emax:-3}`, so a registry entry whose `blocks.gate` names a block the ladder does not carry admits every task at any score and risk, and is offered as a lane candidate. A gate that cannot be read fails open.
- Evidence: `58885f9` makes a missing gate block an ERROR on the task, skips the entry as a lane candidate with one diagnostic, and adds the `a missing gate block is an error, not an open gate` test.
- Minimum severity: Critical

## D2: an unusable executor with no declared reason is reported with an empty reason

- Where: `plugins/dr-superpowers/scripts/detect-executors.sh`, `entry_reason`
- Defect: `reasons.*` keys are optional in a registry entry, and `entry_reason` prints whatever `executors get` returns, so an entry that declares none makes the roster emit `usable: false` with `reason: ""`.
- Evidence: `58885f9` gives `entry_reason` a generated message when the entry declares none.
- Minimum severity: Important

## D3: the rung error names the assignment block by convention, not from the registry

- Where: `plugins/dr-superpowers/scripts/plan-lint`, the rung check of the `**Executor:**` line
- Defect: the message says `the $eid-assignment rung`, assuming every executor's assignment block is named `<id>-assignment`, although the registry entry names it in `blocks.assignment`.
- Evidence: `58885f9` prints `$(executor_field "$eid" blocks.assignment)` instead.
- Minimum severity: Important

## D4: the executor registry is not documented in the plugin

- Where: `plugins/dr-superpowers/README.md` and `plugins/dr-superpowers/reference/executor-lane.md`
- Defect: the branch adds `reference/executors/<id>.json` and `scripts/executors` as the way to add an executor, but neither the README nor the lane reference describes the registry, its entry schema, which fields are required, or what makes an entry invalid.
- Evidence: `58885f9` adds the README paragraph and the `## The executor registry` section with the field table.
- Minimum severity: Important

## D5: the neutral lane reference still names Codex in its generic rules

- Where: `plugins/dr-superpowers/reference/executor-lane.md`, "Resuming an executor task" and the failure table
- Defect: the executor-neutral part of the reference still says fix rounds "resume the same Codex session", keys a table row on `scripts/codex-gate`, and says "Two Codex runs have failed", so the generic rules read as Codex-only.
- Evidence: `58885f9` rewrites the three as "that executor's own session", "that executor's gate" and "Two executor runs have failed".
- Minimum severity: Important

## D6: every completed task is told to release an executor worktree

- Where: `plugins/dr-superpowers/reference/delegated-task.md`, "Release the worktree when the task is complete"
- Defect: the instruction applies to any task that reached a reviewed complete line and then runs the executor wrapper with `<id>`, but a task implemented by a Claude subagent has no executor and no wrapper to release.
- Evidence: `58885f9` scopes it to "a task that ran on an external executor".
- Minimum severity: Important
