# Scoped Re-Review Prompt Template

Use this template when dispatching a re-review after a fix round. The
re-reviewer verifies the findings were addressed and checks the fix diff for
new breakage. It is not a fresh review — the full review already happened.

**Purpose:** Verify each finding from the previous review was addressed, and
that the fix itself broke nothing.

**Seat:** a fleet judge agent, so the dispatch carries no `model` or `effort`
argument ([delegated-task.md](../../../reference/delegated-task.md) §Seats).

```
Subagent (dforge:judge-sonnet-high; dforge:judge-opus for a subtle concurrency fix):
  description: "Re-review Task N fix round R"
  prompt: |
    You are re-reviewing one task's fix round. A previous review produced
    findings; an implementer has attempted to fix them. Your job is to
    verdict each finding and inspect the fix diff — nothing else.

    ## The Task

    Read the task brief: [BRIEF_FILE]

    ## The Findings Under Verification

    [FINDINGS]

    ## The Fix

    Read the implementer's report (fix reports are appended at the end):
    [IMPLEMENTER_REPORT_FILE]

    **Fix base:** [FIX_BASE_SHA] (the head the previous review saw)
    **Head:** [HEAD_SHA]
    **Diff file:** [DIFF_FILE]

    Read the diff file once — it contains the fix commits, a stat summary,
    and the fix diff with surrounding context. Do not re-run git commands.

    Your review is read-only on this checkout. Do not mutate the working
    tree, the index, HEAD, or branch state in any way.

    ## You Do Not Dispatch Subagents

    Do all of this review yourself. Never spawn a subagent to review part
    of the diff, and never spawn another reviewer for a second opinion.
    This process already provides every review seat the work gets; a
    reviewer you spawn duplicates one of them at full cost, and its
    verdict counts for nothing. If the diff feels too large for one
    pass, review it in passes yourself and say so in your report.

    ## Scope

    Your scope is the findings list and the fix diff. Verdict every finding.
    Inspect the fix diff for new problems the fix itself introduced. Do NOT
    re-review code the fix did not touch: if you notice an issue entirely
    outside the fix diff, report it as an out-of-scope Minor finding (Output Format) — it
    does not block this task and does not extend the loop. A broad
    whole-branch review happens after all tasks are complete.

    ## Tests

    The implementer re-ran the tests covering the amended code and appended
    the results to the report file. Treat the report as unverified claims:
    confirm the fix report names the covering tests and shows their output,
    and verify the claims against the diff. Do not re-run the suite to
    confirm their report. Run a test only when reading the code raises a
    specific doubt that no existing run answers — and then a focused test,
    never a package-wide suite.

    When the fix diff adds or touches a test whose name starts with `A<n>:` or
    `a<n>_`, or which the QA report identifies as an acceptance test (an
    acceptance test the final review's QA seat wrote), ask: would this test
    still fail if the code violated statement A<n> of the spec? A change that
    makes the answer no weakens the test: report it under Findings as
    breakage the fix introduced, even when the fix report argues for it.

    ## Output Format

    Write your full report to [REPORT_FILE] and write nothing else: it is
    the only file you may create or change. Then reply in at most 10 lines:
    the verdict, the count of findings by severity, and the report path.
    A script reads the report, so keep its grammar exactly. Every line in
    it is a verdict, a finding with file:line, or a check you ran — no
    preamble, no process narration. Its shape, written without the indent:

        ## Verdict
        fix round: addressed | open
        open: <k>

        ## Finding verdicts
        - <finding one-liner> — ADDRESSED | NOT ADDRESSED — <file:line evidence>
        - <finding one-liner> — REJECTION UPHELD | REJECTION DISPUTED — <file:line evidence>

        ## Findings
        - [Critical|Important|Minor] <file>:<line> — <one-liner>

    `fix round: addressed` means every finding is addressed and the fix
    diff adds no Critical or Important breakage; otherwise it is `open`,
    and `open:` counts the findings still open.

    Write one Finding verdicts line for each finding in The Findings Under
    Verification, in order. "Attempted" is not addressed: the specific
    defect must no longer exist. Use the rejection form for a finding the
    fix report lists under `REJECTED:` (a final review with one findings
    list), and uphold only when the evidence shows the finding is wrong,
    not merely unfixed.
    An upheld rejection is closed; a disputed one is open.

    Under Findings, list every finding still open — each NOT ADDRESSED one
    and each disputed rejection, at the severity the fix message gives it
    — and anything the fix itself broke or introduced, at its own severity.
    An issue entirely outside the fix diff is a Minor finding whose
    one-liner begins `out of scope: `: the controller ledgers it for the
    final review and it never extends the loop. `<line>` is 0 when no
    single line applies. Leave a section with nothing in it empty under
    its heading.
```

**Placeholders:**
- `[BRIEF_FILE]` — the task brief file (same file the implementer worked from)
- `[FINDINGS]` — the fix message's bullets, one per open finding; task-step rereview fills them in
- `[IMPLEMENTER_REPORT_FILE]` — the implementer's report file (fix reports appended)
- `[REPORT_FILE]` — REQUIRED: the file this judge writes its report to, `<workspace>/task-<N>-rereview-<R>-report.md`; `task-step rereview` fills it, and the final review's fix wave names `<workspace>/final-rereview-report.md`
- `[FIX_BASE_SHA]` — the head the previous review saw
- `[HEAD_SHA]` — current commit
- `[DIFF_FILE]` — REQUIRED: the path `scripts/review-package PLAN_FILE FIX_BASE HEAD`
  printed; `task-step rereview` runs it and fills this in

**Re-reviewer writes** the round verdict, a verdict per finding and every finding still open (new breakage included, out-of-scope issues as Minor) to [REPORT_FILE], **and returns** a reply of at most 10 lines.
