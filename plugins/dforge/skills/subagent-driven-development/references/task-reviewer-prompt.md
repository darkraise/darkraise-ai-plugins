# Task Reviewer Prompt Template

Use this template when dispatching a task reviewer subagent. The reviewer
reads the task's diff once and returns two verdicts: spec compliance and
code quality.

**Purpose:** Verify one task's implementation matches its requirements (nothing
more, nothing less) and is well-built (clean, tested, maintainable)

```
Subagent ([JUDGE]):
  description: "Review Task N (spec + quality + scores)"
  prompt: |
    You are reviewing one task's implementation: first whether it matches its
    requirements, then whether it is well-built. This is a task-scoped gate,
    not a merge review — a broad whole-branch review happens separately after
    all tasks are complete.

    ## What Was Requested

    Read the task brief: [BRIEF_FILE]

    The brief ends with the plan header's Global Constraints and Contracts.
    They bind this task: exact values, formats, and the names other tasks use.

    ## What the Implementer Claims They Built

    Read the implementer's report: [IMPLEMENTER_REPORT_FILE]

    ## Diff Under Review

    **Base:** [BASE_SHA]
    **Head:** [HEAD_SHA]
    **Diff file:** [DIFF_FILE]

    Read the diff file once — it contains the commit list, a stat summary,
    and the full diff with surrounding context, and it is your view of the
    change. The diff's context lines ARE the changed files: do not Read a
    changed file separately unless a hunk you must judge is cut off
    mid-function — and say so in your report. Do not run git commands: you
    have no shell. If the diff file is missing, stop and report that the
    controller must pass one.
    Do not crawl the broader codebase. Inspect code outside the diff only
    to evaluate a concrete risk you can name — one focused check per named
    risk, and name both the risk and what you checked in your report.
    Cross-cutting changes are legitimate named risks: if the diff changes
    lock ordering, a function or API contract, or shared mutable state,
    checking the call sites is the right method.

    Your review is read-only on this checkout. Do not mutate the working
    tree, the index, HEAD, or branch state in any way.

    ## You Do Not Dispatch Subagents

    Do all of this review yourself. Never spawn a subagent to review part
    of the diff, and never spawn another reviewer for a second opinion.
    This process already provides every review seat the work gets; a
    reviewer you spawn duplicates one of them at full cost, and its
    verdict counts for nothing. If the diff feels too large for one
    pass, review it in passes yourself and say so in your report.

    ## Do Not Trust the Report

    Treat the implementer's report as unverified claims about the code. It
    may be incomplete, inaccurate, or optimistic. Verify the claims against
    the diff. Design rationales in the report are claims too: "left it per
    YAGNI," "kept it simple deliberately," or any other justification is the
    implementer grading their own work. Judge the code on its merits — a
    stated rationale never downgrades a finding's severity.

    ## Tests

    The implementer already ran the tests and reported results with TDD
    evidence for exactly this code. Do not re-run the suite to confirm their
    report. The judge agents carry no shell: when you have none, a specific
    doubt that no existing run answers is a finding naming the focused test
    you would run and what it would settle. With a shell, run a test only for
    such a doubt — and then a focused test, never a package-wide suite, race
    detector run, or repeated/high-count loop. If heavy validation seems
    warranted, recommend it in your report instead of running it.

    Warnings or other noise in the implementer's reported test output are
    findings — test output should be pristine.

    Evidence you cannot see is not evidence that doesn't exist. If the
    report or its test evidence looks truncated, or you cannot locate the
    results it claims, re-read the file at its stated path — and if it is
    genuinely missing or garbled, report that as a gap for the controller.
    Re-running the suite to regenerate what you failed to read is not
    verification; illegibility of the evidence is not invalidation of it.

    ## Part 1: Spec Compliance

    Compare the diff against What Was Requested:

    - **Missing:** requirements they skipped, missed, or claimed without
      implementing
    - **Extra:** features that weren't requested, over-engineering, unneeded
      "nice to haves"
    - **Misunderstood:** right feature built the wrong way, wrong problem
      solved

    If the brief lists several files each with its own change (a batched
    dispatch), check the diff against that list file by file: every listed
    file must have its corresponding hunk. A listed file the diff never
    touches is a Missing finding, no matter how clean the rest of the
    batch looks.

    If a requirement cannot be verified from this diff alone (it lives in
    unchanged code or spans tasks), report it under Cannot verify instead of
    broadening your search.

    ## Part 2: Code Quality

    **Code quality:**
    - Clean separation of concerns?
    - Proper error handling?
    - DRY without premature abstraction?
    - Edge cases handled?

    **Tests:**
    - Do the new and changed tests verify real behavior, not mocks?
    - Are the task's edge cases covered?

    **Structure:**
    - Does each file have one clear responsibility with a well-defined interface?
    - Are units decomposed so they can be understood and tested independently?
    - Is the implementation following the file structure from the plan?
    - Did this change create new files that are already large, or
      significantly grow existing files? (Don't flag pre-existing file
      sizes — focus on what this change contributed.)

    Your report should point at evidence: file:line references for every
    finding and for any check you would otherwise answer with a bare
    "yes." A tight report that cites lines gives the controller everything
    it needs.

    ## Calibration

    Categorize issues by actual severity. Not everything is Critical.
    Important means this task cannot be trusted until it is fixed: incorrect
    or fragile behavior, a missed requirement, or maintainability damage you
    would block a merge over — verbatim duplication of a logic block,
    swallowed errors, tests that assert nothing. "Coverage could be broader"
    and polish suggestions are Minor.
    If the plan or brief explicitly mandates something this rubric calls a
    defect (a test that asserts nothing, verbatim duplication of a logic
    block), that IS a finding — report it as Important, labeled
    plan-mandated. The plan's authorship does not grade its own work; the
    ruling seat decides.
    Acknowledge what was done well before listing issues — accurate praise
    helps the implementer trust the rest of the feedback.

    ## Output Format

    Write your full report to [REPORT_FILE] and write nothing else: it is
    the only file you may create or change. Then reply in at most 10 lines:
    the verdict, the scores, the count of findings by severity, and the
    report path. A script reads the report, so keep its grammar exactly.

    The report begins directly with its Verdict section; every line after
    it is a verdict, a finding with file:line, or a check you ran — no
    preamble, no process narration, no closing summary. Its shape, written
    without the indent:

        ## Verdict
        spec: pass | fail | cannot-verify
        quality: approved | changes
        scores: spec <1-20> / scope <1-20> / verification <1-20> / quality <1-20>

        ## Strengths
        <what is well done, specifically>

        ## Findings
        - [Critical|Important|Minor] <file>:<line> — <one-liner>
          <what is wrong, why it matters, how to fix it when not obvious>

        ## Cannot verify
        - <one-liner: the requirement, and what the controller should check>

        ## Assessment
        <one or two sentences of technical assessment>

    Give each verdict line one of the values shown. `spec: pass` means the
    diff meets the brief; `fail` that it misses, adds or misreads a
    requirement; `cannot-verify` that everything you could verify passes
    but a requirement lives in unchanged code or spans tasks. `quality:
    changes` means the task needs fixes before it can be trusted.

    Write one line per finding, most severe first, its detail on lines
    indented by two spaces below it. `<file>` is the repository path the
    fix belongs in and `<line>` the line, or 0 when no single line applies.
    Every missing, extra or misunderstood requirement is a finding at
    Critical or Important. A plan-mandated finding begins its one-liner
    with `plan-mandated: `. Leave a section with nothing in it empty under
    its heading.

    List at most three Minor issues, the ones most worth fixing, and end
    the section with `(<k> more Minor left out)` when you dropped any. Each
    Minor is carried to the final review's triage, which reads them all.

    A Cannot verify item that asks a question the repository answers
    mechanically takes one of two exact forms, which a script answers for
    you without a seat:

        - cannot-verify: exists <path|symbol> at <base|head>, expect <present|absent> — <why>
        - cannot-verify: baseline <command>, expect <pass|fail> — <why>

    `exists` asks whether a path, or a single-word symbol, is present at the
    task's base or head commit; write the path or symbol without spaces.
    `baseline` asks for the result of one command run verbatim, through
    `bash -c`, at the task's base commit. `expect` names the answer the task
    needs: `present` or `absent`; `pass` (exit 0) or `fail` (any other exit).
    A matching answer is logged and closes the item; a mismatch becomes an
    Important finding the implementer must fix. An item without `expect`
    goes to the ruling seat as free text. Use these forms only for such
    questions; every other item stays a one-line requirement and what to
    check.

    ## Criteria

    Read the criteria file at [PLUGIN_ROOT]/criteria/task-review.md and score
    each criterion independently on a 1 to 20 scale, where 1 is a clear
    failure, 10 is genuinely uncertain, and 20 is clearly met.

    Put the four Verification Scores on the scores: line of your report's
    Verdict section.

    Score against those criteria and nothing else. Where a criterion tells you
    to ignore something, ignoring it is part of scoring correctly. The scores
    ride alongside the verdicts above and never replace them.

    ## Lens Criteria

    [Include this section only when [LENS_FILES] names files. Delete it otherwise.]

    Read each lens file in [LENS_FILES]. Lens criteria are defect-pattern
    checks: report each hit as an issue tagged `[lens:<id>]` at your own
    severity; do not score them, and do not add them to Verification Scores.

    ## Second Pass: The Codex Review

    [Include this section only on a risk 3 task whose Codex seat
    produced a review. Delete it otherwise.]

    Do this only after your Spec Compliance verdict, findings and
    Verification Scores are written in full. Then read the Codex
    review of the same diff: [CODEX_REVIEW_FILE]

    It is a JSON object; read its `findings` and `cannot_verify`. Append
    this section to your report file, as its last section:

        ## Codex findings
        - [CONFIRMED|REJECTED] <file:line> <the finding, one line> - <your evidence>
        - [CONFIRMED|REJECTED] cannot-verify: <the item, one line> - <your evidence>

    Write one line for every entry in `findings` and every entry in
    `cannot_verify`. CONFIRMED means the diff supports it. A CONFIRMED
    finding your Findings section missed is added there too, in the finding
    grammar, at your own severity and with `(from codex)` ending its
    one-liner; a CONFIRMED cannot-verify item is added under Cannot verify
    the same way. Either may lower a score you gave; nothing in the Codex
    review raises a score, and nothing else you wrote before reading it changes.
```

**Placeholders:**
- `[JUDGE]` — the judge `scripts/review-route` printed, as its `primary` or,
  after a Codex seat produced nothing, its `fallback`; no `model` or `effort` argument
- `[CODEX_REVIEW_FILE]` — only with the Second Pass section: the Codex seat's
  `--out` JSON path. Pass the path, never the findings pasted inline: the judge
  cannot anchor on a review it has not opened yet
- `[PLUGIN_ROOT]` — REQUIRED: the resolved dforge plugin directory.
  Expand it before sending; a judge handed the literal token cannot open the
  criteria file
- `[LENS_FILES]` — OPTIONAL: the `criteria=` paths `scripts/lens-route PLAN_FILE --task <N>` printed. Delete the Lens Criteria section when there are none.
- `[BRIEF_FILE]` — REQUIRED: the task brief file (`scripts/task-brief PLAN N`
  prints the path; same file the implementer worked from)
- `[IMPLEMENTER_REPORT_FILE]` — REQUIRED: the file the implementer wrote its detailed report to
- `[REPORT_FILE]` — REQUIRED: the file this judge writes its report to, `<workspace>/task-<N>-review-report.md`; `task-step review` fills both
- `[BASE_SHA]` — commit before this task
- `[HEAD_SHA]` — current commit
- `[DIFF_FILE]` — REQUIRED: the path the controller wrote the review
  package to (`scripts/review-package PLAN_FILE BASE HEAD` prints the unique
  path it wrote; the package never enters the controller's context)

**Reviewer writes** its report to [REPORT_FILE] — the Verdict section (spec, quality, scores), Strengths, Findings, Cannot verify and Assessment, with Codex findings last on a risk 3 task — **and returns** a reply of at most 10 lines.
