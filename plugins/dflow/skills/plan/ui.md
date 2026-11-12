# UI contract and proof

Read this only for a plan with a `UI` acceptance line.

## The `## UI` section of the plan

Write it between Design and Tasks. Keep it to what a builder cannot guess:

- **Source**: the mockup, design file or design system the screen follows, by path or link. If there is none, say which existing screen it should match.
- **States**, for each screen or component the plan touches: empty, loading, error, success, and long or overflowing content. One line each on what the user sees.
- **Input**: what each control does, validation and its messages, what the keyboard does (tab order, Enter, Escape), and what is disabled when.
- **Widths**: the narrowest and widest the layout must hold, and what changes between them.
- **Access**: labels for controls without visible text, focus after an action, and contrast where colour carries meaning.

Every `UI` acceptance line names one observable result of these, such as `A2 UI: an empty list shows "No items yet" and the Add button`. Mark a line `UI visual` only when its appearance is the point (layout, alignment, colour); other lines are proven on text.

A task that builds UI lists the states it must handle as its steps, and its `Verify:` is still a command: the component's test, a type check or a lint.

## Proof, before ship

`dflow ship --check` names each `UI` line that lacks a proof. For each:

1. Commit first. A proof is of a commit.
2. Start the app with the run command in `docs/dflow/config.json` (`run.cmd`) as a background task with a timeout. Note its process id.
3. Drive the line in the running app: the browser tools for a web app, the project's own driver for anything else.
4. Assert on text: read the page's accessibility snapshot or query the element, and confirm the text or state the line names. Do not read a screenshot for a line that is not `visual`.
5. Save a screenshot to a file without opening it, then record the proof:

   ```
   dflow proof <A-id> --shot <file> --text "<the text or state you observed>" --steps "<how you got there>"
   ```

   For a `UI visual` line, open the screenshot once, compare it with the Source, and record with `--shot` and `--steps`.
6. If the line does not hold, it is a defect: fix it in the code, commit, and prove again. Never record a proof of something you did not observe.
7. Stop the app and confirm its process is gone.

A proof goes stale when a later commit touches a UI file; `dflow proof --list` shows which.
