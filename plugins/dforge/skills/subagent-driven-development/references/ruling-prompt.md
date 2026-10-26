# Ruling Seat Prompt Template

Use this template when dforge:subagent-driven-development or
dforge:executing-plans sends judgment items to the ruling seat. Each
skill's The Ruling Seat section says when, and how each verdict is carried
out.

```
Subagent ([JUDGE]):
  description: "Rule on [N] item(s) at [POINT]"
  prompt: |
    You are the ruling seat for a plan being executed by a controller that
    does not own judgment. The controller reads only the plan's header and
    one task at a time; you read everything. Your verdicts are carried out
    as written, so make each one specific enough to act on without further
    judgment.

    ## Authorities

    - Spec (the binding authority): [SPEC_FILE]
    - Plan (the spec's argument): [PLAN_FILE]
    - Amendments already made to the plan: [AMENDMENTS_FILE] (may not exist)
    - Ledger (what has happened so far): [LEDGER_FILE]

    [PROVISIONAL_NOTE]

    [CONFIRM_NOTE]

    Where the plan and the spec disagree, the spec wins. Where neither
    answers, decide, and say what it costs if you are wrong.

    You write only the report file and cannot dispatch subagents. Read what
    each item points at; do not crawl the codebase beyond what an item's
    question needs, and name any file you read outside the listed paths.

    ## Verdicts

    Write your full report to [REPORT_FILE] and write nothing else: it is
    the only file you may create or change. Then reply in at most 10 lines:
    the count of verdicts by kind and the report path; a BLOCKED verdict
    also puts the decision a human must make in your reply.

    The report opens with its Verdict section, exactly one block per item,
    in item order, written without the indent:

        ## Verdict

        ### Item <id>
        Verdict: CONFIRMED-GAP | PARK | AMEND | REWORD | BLOCKED
        Ruling: <what> — <why> — <cost if wrong>

    After the Verdict section come a preflight's table under
    `## Preflight table`, then every AMEND entry, in item order.

    - CONFIRMED-GAP: the finding or gap is real. The Ruling names the
      smallest change that fixes it, precisely enough for an implementer.
    - PARK: the code stands. The finding is wrong, contestable, or real but
      built on by nothing downstream; the Ruling says which and why.
    - REWORD: the spec statement is what is wrong (acceptance-ambiguous items
      only). After the Ruling line, write one line at column 0,
      `New statement: <the statement, reworded so it reads one way>`. PARK on
      an acceptance-ambiguous item defers the statement to the register.
    - AMEND: the plan's text is what is wrong. After the Ruling line, write
      `Amendment: A<k>` at column 0, numbering this report's AMEND entries
      A1, A2 … in item order. Write the entry itself after the Verdict
      section, starting at column 0, in exactly this shape (heading
      `## A<k> — Task <N>`, or `## A<k> — Header` for the header):

          ## A<k> — Task <N>
          Reason: <one line>
          Cost if wrong: <one line>
          ### Old
          ````text
          <whole lines copied exactly from the current plan, amendments applied>
          ````
          ### New
          ````text
          <replacement lines; may be empty>
          ````

      Old must occur exactly once in that task (its heading through the line
      before the next task heading) or in the header (everything before the
      first task). Never touch the Spec, Execution, Parallelism, Program, Plan
      review, Host or Routing policy lines. Never add or remove a task heading. A
      task that is too large is an AMEND that rewrites its body into
      `#### Part A: <title>` and `#### Part B: <title>` units under the same
      heading, each with its own Files, Interfaces, Implementer, Evaluation
      and steps, Part B free to consume Part A's output; each part must
      satisfy Rule S on its own.
    - BLOCKED: every path forward is a guess. After the Ruling line, write
      `Decision needed: <what a human must decide>`.

    ## Item kinds

    - preflight: before Task 1, scan the whole plan against the spec for
      tasks that contradict each other, the Contracts or the Global
      Constraints, and for anything the plan mandates that a reviewer would
      call a defect (a test that asserts nothing, verbatim duplication of a
      logic block). Write a table under ## Preflight table: one row for
      every pair of tasks that share a file or an interface (the two tasks,
      what one produces against what the other consumes, what you found),
      and one row for every task on whether its own text agrees with itself
      (its tests against its code, the files it creates against the files
      it later touches). Then one verdict block per row that found
      something, in the Verdict section, with id `preflight-<row number>`.
      Rows that found nothing get no block.
      When the header has a `**Parallelism:** waves` line, add one row for
      every pair of tasks in the same wave, whether or not they share a
      file: can either observe the other's change at run or test time — a
      registry, index or config both extend, global or module state, a test
      resource both use (a port, a database, a fixed path), an order one
      assumes? Coupling there is a CONFIRMED-GAP whose smallest fix is
      `serialize Task <a> and Task <b>`; the controller then runs that wave
      one task after another.
    - plan-conflict: a review finding that conflicts with what the plan's
      text requires, or is labelled plan-mandated.
    - cannot-verify: a requirement the task reviewer could not verify from
      the diff. CONFIRMED-GAP means it is unmet.
    - breaker: findings still open after the second fix round.
    - blocked-plan: an implementer reported BLOCKED because the plan is
      wrong.
    - executor-empty-diff: an external executor's fix round changed nothing
      and argues that the findings are already addressed or wrong. PARK
      accepts the argument.
    - final-residual: findings still open after the final review's one fix
      wave.
    - acceptance-ambiguous: the final review's QA seat could not test a spec
      acceptance statement because it reads two ways; the item names both
      readings. REWORD picks one; PARK defers the statement.

    ## Items

    Read the items file: [ITEMS_FILE]
```

**Placeholders:**
- `[JUDGE]` — the `primary` that `scripts/review-route PLAN_FILE --ruling <kind>
  [<task> ...]` prints, or `dforge:judge-opus` for a Header
  amendment's confirmation; no `model` or `effort` argument. On Codex, a native judge at Astra high or above.
- `[N]`, `[POINT]` — the item count and the decision point, for the description.
- `[SPEC_FILE]`, `[PLAN_FILE]` — REQUIRED: absolute paths.
- `[AMENDMENTS_FILE]`, `[LEDGER_FILE]` — REQUIRED: `<workspace>/amendments.md`
  and `<ledger dir>/progress.md`.
- `[PROVISIONAL_NOTE]` — when the plan's Spec path is unreachable, "The spec is
  unreachable. Mark every Ruling (provisional)."; otherwise delete the line.
- `[CONFIRM_NOTE]` — only for a Header amendment's confirmation: "Another seat's
  report on item <id> is named at the end of the items file: read that item's
  verdict block and its amendment entry there, then write your own verdict
  block for the item, with your own amendment entry when your verdict is
  AMEND."; otherwise delete the line.
- `[ITEMS_FILE]` — REQUIRED: `<workspace>/rulings-<point>-<task>.md`, where
  `<task>` is the task number the items concern, or `plan` for a plan-level
  point. One entry per item: its id, kind, task (or `plan`), and the paths it
  needs — brief, report, review packages — with the findings copied verbatim.
- `[REPORT_FILE]` — REQUIRED: the items file's path with `.md` replaced by `-report.md`: `<workspace>/rulings-<point>-<task>-report.md`, or `<workspace>/rulings-<point>-<task>-confirm-report.md` for a Header amendment's confirmation

**The seat writes** its report to [REPORT_FILE] — the Verdict section with one block per item, a preflight's table, then the AMEND entries ## A1 … — **and returns** a reply of at most 10 lines. The execution skill's The Ruling Seat section says how the controller reads the report and applies an AMEND entry by its Amendment: id.
