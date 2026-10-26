# Drafter Prompt Template

Use this template for each slice writing-plans §Drafting the tasks
dispatches: one dispatch per slice of 2-3 consecutive tasks, every slice in
one message.

```
Subagent (dforge:drafter-sonnet):
  description: "Draft plan tasks [A]-[B]"
  prompt: |
    You are drafting tasks [A] to [B] of an implementation plan. Other
    drafters are writing the plan's other tasks at the same time.

    **Spec:** [SPEC_PATH]
    **Plan:** [PLAN_PATH] - it holds the header and the Task index only.
    **Your slice:** tasks [A]-[B], titled as the Task index names them.
    **Write to:** [SLICE_PATH]
    **Skill:** [PLUGIN_ROOT]/skills/writing-plans/SKILL.md

    Read the spec, then the plan's header in full: its Global Constraints,
    Contracts, Assumptions and Task index are fixed, and every name one task
    produces and another consumes is in Contracts. Then read the skill's Task
    Structure, Task Right-Sizing and No Placeholders sections; your tasks
    follow them exactly.

    Write your tasks to [SLICE_PATH] as `### Task N: <title>` sections, in
    order, with the titles the Task index gives, and nothing else: no
    header, no index and no assignment lines (`**Implementer:**`,
    `**Evaluation:**`); the session scores the tasks after joining. Each task
    names its exact files and its interfaces, gives the complete code of its
    tests, and describes the implementation precisely without its code:
    implementation code appears only for a configuration value, a
    generated-file or migration command, or a fixed constant the spec names.
    Each task ends with the commands that verify it.

    Read the code your tasks change and the suite each task's tests join.
    Run your tests against the current tree in a scratch worktree of your own
    (`git worktree add --detach <scratch dir> HEAD`, removed before you
    finish), and confirm each fails for the reason the task fixes.
    Write nothing in this checkout except [SLICE_PATH].

    You do not dispatch subagents.

    When a task needs a name, file or format that Contracts does not give
    and another slice could also produce, do not invent it: report
    NEEDS_CONTEXT with the exact contract you need.

    Your final message is your report, and only this:
    - Status: DONE | NEEDS_CONTEXT | BLOCKED
    - One line: the slice path, or what you need.
```

**Placeholders:**
- `[A]`, `[B]` — the slice's first and last task numbers.
- `[SPEC_PATH]`, `[PLAN_PATH]` — absolute paths of the spec and the plan.
- `[SLICE_PATH]` — `<state>/drafts/<plan basename without .md>/tasks-[A]-[B].md`,
  with `<state>` from `bash <plugin-root>/scripts/dforge-path state`.
- `[PLUGIN_ROOT]` — the resolved dforge plugin directory.
