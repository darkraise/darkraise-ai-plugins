# The task review loop

One task's judge review, fix loop and complete line. dforge:executing-plans
runs it for a risk-3 task, which the session implements itself and a judge
reviews: §The session review loop. Sections 1 to 5 are the steps that loop
calls.

## Contract

- **The caller holds** the plan workspace, the ledger, a brief file from
  `scripts/task-brief` (one task's), and a ruling
  seat it can dispatch, per its own The Ruling Seat section.
- **The loop writes** only lines of the shared ledger grammar
  ([executing-plans](../skills/executing-plans/SKILL.md) §The Ledger).
- **The loop returns** on the task's `complete` line or on a `BLOCKED` line. A
  budget `handoff` waits for the `complete` line.

## Seats

| Seat | Agent | Model argument |
|---|---|---|
| Task reviewer | The seat `scripts/review-route PLAN_FILE --task <N>` prints (§3); its `fallback` when the reviewer panel returns no list (`lists=0`); say every substitution aloud. On a Codex host, a native judge at Astra high or above ([native-codex.md](native-codex.md)) | None |
| Scoped re-review | `dforge:judge-sonnet-high`; `dforge:judge-opus` for a subtle concurrency fix | None |

**Fleet agents take no `model` or `effort` argument.** The Agent tool's `model`
argument overrides the agent file's pinned model while `effort` keeps its
frontmatter value, and its `effort` argument (Claude Code 2.1.292 and later)
overrides the pinned effort while the model stays; either runs the agent at a
tier the ledger does not record.

General-purpose seats always take an explicit model:
[using-dforge](../skills/using-dforge/SKILL.md) §Seats.

**Turn count beats token price.** Wall-clock and context cost scale with how
many turns a subagent takes, and the cheapest models routinely take 2-3× the
turns on multi-step work. Use a mid-tier model as the floor for reviewers.

## 1. Open the task

**Open the task with one call:**
`bash <plugin-root>/scripts/task-brief --open PLAN_FILE N`. It writes the
brief, rewrites `<workspace>/plan-header.md`, appends the
`implementer inline (assigned; base <sha7>)` line once and prints the task
check and the budget line (see the caller's Session Budget section). That open
line is the task's BASE: `task-step review` creates
`<workspace>/task-<N>-step.json` from it, recording the suite command you pass
as `--suite '<suite command>'` (below), so you never carry a SHA. Calling
`--open` again for a task that has its open line adds none, and the review
still packages every commit made since that base. Exit 3 means the plan has no
such task; exit 2 on a `Host: codex` plan sends you to *The steps by hand*
below.

- **Suite command.** Read the plan header's `**Task check:**` line first,
  then resolve the plan's suite command once:
  - A plan with no `**Task check:**` line runs as it does today. Pass the
    suite command to its first `task-step review` as `--suite '<suite command>'`.
    It is the command on the plan header's
    `**Integration check:**` line; else the test command
    `<docs>/gates.md` declares (the `Command` of the gate that runs the
    project's tests); else one you decide from the project's manifest
    (`package.json` `scripts.test`, a Makefile `test` target, `cargo test`,
    `go test ./...`, `pytest`) and keep for the rest of the plan. `review`
    records it as the step file's `suite`, and the first `review --suite` on
    a plan logs `Task <N>: Ruling: suite command — <command> — none`. You run
    only the focused tests that cover your change while you work; §2 runs the
    suite.
  - A command task check is the suite command: every `task-step review`
    passes it, never the Integration check. The rest of the loop is
    unchanged.
  - With a task check of `none`, `review` passes no
    `--suite` on a task the schedule skips. The integration check is the command the first sub-bullet
    resolves. The schedule is by task number: the integration check runs on
    every task whose number is a multiple of 3 and on the last task. The
    controller decides at review time, in the same turn it starts the run.
    For a scheduled task, `task-step review` takes
    `--suite <integration check>` and `--suite-base <sha>`. `<sha>` is the head of the last full-suite run, or the plan base
    before the first run. The last full-suite run is the last row of
    `<state>/suites.tsv` (`dforge-path state`) whose command column is the
    key `suite-run` records for `bash -c '<integration check>'`, whatever its
    exit, and whose HEAD is the task's base or an ancestor of it
    (`git merge-base --is-ancestor <row head> <task base>`). A row at the task's own head, left by an earlier
    review of the task, never counts. The plan base is the `base` in the step
    file of the plan's first task. So a regression made by an earlier task is
    not excused as a base failure. `review` exits 2 when `--suite` comes
    without `--suite-base`, when `--suite-base` is not the task's base or an
    ancestor of it, and when a scheduled task gets no `--suite` and its step
    file records none. Normally `suites.tsv` already holds a row at `<sha>`, so the
    comparison costs nothing, but when `suites.tsv` has no row at `<sha>`,
    `verdict` runs the suite once there (for example after a fix round),
    bounded at 3600 seconds (`TASK_STEP_BASE_TIMEOUT`). A fix round runs a
    suite only when the review of its task did.
- **UI tasks:** a brief that carries `## UI/UX contract items` is a UI task
  (dforge:ui-ux). Render the result through the project UI profile's harness
  before you write the report, and map each cited ID in the report to a
  screenshot path or a test name; a cited ID with no evidence is a spec ❌ at
  review.
- If an earlier task parked a finding in the area this task touches, read that
  ledger entry first. If an earlier task's breaker carried a CONFIRMED-GAP to
  this task, the gap and the ruling's smallest unblocking change are part of
  this task's work, and its review checks that change.

## 2. The report and the suite

Task review always follows the report: write it as §The session review loop
step 2 says, then run `task-step review` (§3), which packages the diff and
records `t0`.

**The suite runs beside the review.** A task starts its suite as
soon as its report is written and its work is committed. Run
`bash <plugin-root>/scripts/suite-run -- bash -c '<suite command>'` as a
background Bash command from the checkout's top level, at the task's head, and in the same turn run
`task-step review` and dispatch its seat (§3). `<suite command>` is the one
`task-step review --suite` recorded, character for character: `verdict` finds
the run by the quoted form `suite-run` records for that command, so a command
typed differently, or run from a subdirectory, is never found. A command that
holds a single quote writes each `'` as `'\''` inside `bash -c '…'`: the shell
hands `bash -c` the original text, so the recorded key is unchanged. Every
`bash -c '<command>'` form in dforge follows this rule. The report's
`## Verified` section lists the focused tests you ran; this run is the full
suite. The last `## Verified` section of the report is the current
evidence: a fix round appends its own. End the turn when only waiting remains,
and run `task-step verdict` only once both the seat's report and the suite's
completion notification are in. A suite still running at a handoff shows in
`scripts/in-flight`, and the next session starts it again.
On a `Host: codex` plan `task-step` does not run: *The steps by hand* §2 starts
the suite.

Under a `none` task check, a task that §1's schedule skips starts no suite and
runs `task-step review` without `--suite`. A task the schedule names starts the
integration check as this section describes and passes `--suite` and
`--suite-base` to `task-step review`.

## 3. Review the task

Per-task reviews are task-scoped gates. The broad review happens once, at the
final whole-branch review. Never skip the task review, and never accept a
report missing either verdict — spec compliance AND task quality are both
required. Your own self-review never replaces the task review; both are
needed.

- **One call does the plumbing:**
  `bash <plugin-root>/scripts/task-step review PLAN_FILE N`. It packages the diff from the base
  the open line records to HEAD — never `HEAD~1`, which silently truncates
  multi-commit tasks — and records the review head and `t0`. It runs
  each reviewer family's gate (`scripts/codex-gate`, `scripts/agy-gate`),
  `scripts/review-route PLAN_FILE --task <N>` and
  `scripts/lens-route PLAN_FILE --task <N>`, and writes
  `<workspace>/task-<N>-review-prompt.md`:
  [task-reviewer-prompt.md](prompts/task-reviewer-prompt.md)
  with every placeholder filled in, the diff file, the plugin directory and
  each lens's `criteria=` path among them (a task with no lens has no lens
  section). It runs the mechanical checks below, and for a panel seat also
  writes the reviewers' prompt, `<workspace>/task-<N>-review-panel-prompt.md`.
  It prints at most 15 lines: the seat and its prompt
  file, for a panel seat the panel command and its timeout, the check lines,
  the state it recorded and the budget line. The diff never enters your own
  context, and a reviewer is never dispatched without it.
- **The seat:** dispatch the `seat:` line's `subagent_type`, with no `model`
  or `effort` argument, and the prompt "your complete instructions are in
  `<prompt file>`: read it first and follow it". When a judge seat returns
  and the suite's notification is in (§2), run
  `bash <plugin-root>/scripts/task-step verdict PLAN_FILE N` with the
  review's task numbers, and act on its digest. Always start `verdict` as a
  background Bash command and end the turn until its notification arrives: it
  may run the suite once at the base commit after a red suite (up to an hour),
  and it runs every `baseline` cannot-verify item (up to ten minutes each);
  each run takes as long again for a **Worktree setup:** command in the plan
  header.
  You never read the report, so you cannot tell beforehand that a `baseline`
  item is there, and a foreground `verdict` that the Bash tool times out writes
  no fix file and no digest.
  Never Read the report file yourself: the digest carries the verdicts, the
  scores, one line per Critical or Important finding and the cannot-verify
  items, and verdict has already written the fix file and logged the Minor
  findings. A `panel:light` seat that returned one list writes no report:
  read its JSON as Panel seats below says. A panel seat's line names the
  judge prompt and the judge, `seat: panel:light prompt: <judge prompt>
  fallback: <judge>` or `seat: panel:heavy+judge-opus prompt: <judge prompt>
  then: dforge:judge-opus`, and `panel: <command>` and `timeout: <ms>`
  follow it: run the panel as below, then the judge as Panel seats says. The
  judge prompt is already written, so you never run `review-route` again for
  it. Run a family's gate with `--refresh` before `task-step review` when that
  reviewer may have come back since an earlier off answer, such as after a
  login, because an off answer is kept for the session. A `gate:` line right
  after the digest's first line carries each family's answer in ranked order
  (`gate: agy=<open|untrusted|reason> codex=<…>`) when the route was
  `reason=reviewers-off` or a gate answered `source=probe`; say it aloud when
  a gate probed. A `seat:` line that names a judge alone was routed with
  `reason=reviewers-off`: no reviewer's surface is open for this session, no
  panel runs, and the seat clause records `(reviewers off — <answers>)` with
  the `gate:` line's answers. When the `seat:` line
  ends `(review-route exited <N>: …)`, `review-route` failed but
  `task-step review` still wrote the complete judge prompt: dispatch the
  `dforge:judge-opus` seat it names as printed, and say why, quoting that
  note. If `task-step review` itself exits 2 (a `lens-route` failure, a bad
  `--base`, `--head` or `--cwd`, an unexpanded placeholder, or a checkout
  whose tracked files it cannot record for the verdict check), it printed
  no digest and left its state file unchanged; any prompt file it left is
  stale: take *The steps by hand*.
  Codex hosts are the exception: `review-route --task` exits 2 on every `Host: codex`
  plan, and the seat is a native judge at Astra high or above
  ([native-codex.md](native-codex.md)).
- **Lenses:** the prompt file already carries each `lens-route` line's
  `criteria=` path. The reviewers' prompt carries no lens files: the
  Claude judge beside the panel reads them. On a `Host: codex` plan `lens-route`
  exits 2; choose the lenses as [native-codex.md](native-codex.md) says.
- **Reviewer inputs:** the brief file (it ends with the plan's Global
  Constraints and Contracts — the reviewer's attention lens), the
  implementer's report file, and the diff file, all named in the prompt file. Never tell the
  reviewer who wrote the diff: a judge that knows the author scores the
  author.
- Do not add open-ended directives like "check all uses" or "run race tests
  if useful" without a concrete, task-specific reason
- Do not ask a reviewer to re-run tests you already ran on the same code —
  the report carries the test evidence, and the suite run of §2 covers the
  rest
- Do not pre-judge findings for the reviewer — never instruct a reviewer to
  ignore or not flag a specific issue. If you believe a finding would be a
  false positive, let the reviewer raise it; the review loop and, at the
  cap, the ruling seat decide it. If the prompt you are writing contains "do not flag," "don't treat X
  as a defect," "at most Minor," or "the plan chose" — stop: you are
  pre-judging, usually to spare yourself a review loop.

**Scores are additive.** The verdict digest carries the spec and quality
verdicts and the four scores — spec, scope, verification, quality — each 1 to 20 against
[task-review.md](../criteria/task-review.md). Read them as bands: **1-8
fails** and joins the fix-loop trigger; **9-13** is borderline, recorded on
the complete line for the final review to triage, never settled by you;
**14-20 passes**. The verdicts still drive the loop; a report that drops a
verdict line is malformed: `task-step verdict` exits 5 on it (When
`task-step verdict` fails).

**Mechanical checks.** `task-step review` also checks the commits from the
base to the review head and prints `check identity:` and `check attribution:`
lines, each `clean` or the short SHA and what it found: an author or committer
that differs from `git config user.name` and `user.email`, or a
`Co-Authored-By:` or `Claude-Session:` trailer, or a line beginning
`Generated with`. A check that
found something is a finding for the fix loop. A reviewer's cannot-verify item
that a `clean` line answers is settled without a seat (executing-plans, The Ruling Seat).

**The suite line.** When the step file records a suite command, the verdict
digest carries exactly one `suite:` line, read from the run §2 started:

- `suite: pass (clean|dirty)`: nothing more to do. A `dirty` run counts: your
  own ledger lines leave the tree dirty, and the tracked-file check already
  guards the reviewed state.
- `suite: red (<k> failing, <b> baseline)`: each failing line that the base
  commit does not also fail is an Important finding,
  `suite: <failing line> fails at <head7>`, in the fix file, and `fix:` names
  that file. Only a base failure excuses a failing line. `verdict` reuses, in
  order, a `suites.tsv` row at the base commit in the checkout's state, then
  `<workspace>/task-<N>-base-failures.txt`, and only then runs the suite once
  at the base commit in a temporary worktree (after the header's
  `**Worktree setup:**`, bounded at 3600 seconds, or
  `TASK_STEP_BASE_TIMEOUT`), keeping that file and
  `<workspace>/task-<N>-base.log`. A base run that times out leaves
  `<workspace>/task-<N>-base-timeout`: later calls do not run it again, and
  every failure counts as new. A base that fails with no recognised test line
  counts as the one line `command exit <code>`, as the head does. With `k` at 0
  every failure is a base failure, and the task may complete. A suite run that
  was cut short (exit 124, or 126 and up) adds the finding
  `suite: suite did not finish (exit <code>) at <head7>` whatever its partial
  log shows.
  Every failing line that is not a base failure is in the fix file, however
  many; the digest shows the first 20 and then
  `suite: <k> more failing lines in <fix file>`.
  Past round 2 `verdict` writes no fix file, and that line reads
  `suite: <k> more failing lines in the suite log <log>`: the log holds every
  failing line, base failures included.
- `suite: not run (<command>)`: no run was recorded at the review head, and
  `verdict` exits 7 with no fix file. Run the suite (§2) at the review head
  and call `verdict` again.
- `suite: not scheduled (next at Task <N>)`: the plan's task check is `none`
  and no suite was scheduled for this task. `verdict` exits 0, and the task
  may complete.
- `suite: none recorded`: the task was started before `--suite` existed; the
  loop is as it was.

The reviewer's
`cannot-verify: exists <path|symbol> at <base|head>, expect <present|absent> — <why>`
and `cannot-verify: baseline <command>, expect <pass|fail> — <why>` items are
answered by `verdict` itself: `exists` by `git cat-file -e` (a path) or
`git grep -nwF` (a symbol) at the named commit, `baseline` by running the
command at the task's base commit as the suite is run there (log
`<workspace>/task-<N>-baseline-<k>.log` for the k-th). A file at the
repository root is written `./<name>`, so it is read as a path and not as a
symbol. A `baseline` command runs only when the plan names it: the step file's
suite command, the plan header's `**Integration check:**` command, or the first
code span of one of the task's `Run:` or `**Check:**` lines, byte for byte
after trimming. `verdict` runs the plan's copy of the command, never the seat's
text. A plan-named command still runs on the controller host, unsandboxed and
with your rights, as the suite is run there. Any other `baseline` command is
not run: it stays for the ruling seat, its digest line ending
` (command not named in the plan)`. Review seats can write only their report
files, the `-report.md` path under `.dforge` that the dispatch names or that
the "Write your full report to" line of its prompt file names (the cockpit
refuses any other write), so a seat cannot add a command to
the plan, its amendments or the step file. An item whose check could not
run (an unknown commit, a git error, a command that timed out or was not
found) stays for the ruling seat. An answer that matches
`expect` is logged
`Task <N>: Ruling: cannot-verify — settled by task-step check <exists|baseline> — <evidence>`
and the item does not appear in the digest, so no seat sees it. An answer
that does not match is an Important finding, file `cannot-verify`, line 0,
`<check>, expect <answer> — got <evidence>`, in the fix file, and `fix:`
names that file as for a reviewer finding. An item without `expect`, in any
other form, or whose check could not run, stays a `cannot-verify:` line for
the ruling seat.

**When `task-step verdict` fails.** Exit 5 means the seat wrote no report,
or one outside the grammar (a line under Findings or Cannot verify that is
neither a bullet nor its indented detail, or a `spec: fail`,
`quality: changes` or `fix round: open` with no Critical or Important
finding), and stderr says which; exit 6 means a tracked
file in the reviewed checkout changed during the review, or HEAD moved, and
stderr names the files and the checkout. On exit 6 put back the state the
review step recorded: run the `restore:` command stderr prints under each
file, and nothing broader. A file that was already dirty at review time
holds uncommitted edits HEAD lacks, so `git checkout --` would discard them.
Then, either way, log `Task <N>: Ruling: review seat <seat> <wrote no
report | wrote a malformed report | changed <files>> —
restored the recorded state and re-dispatched once
— none`, delete the report file, and re-dispatch the same seat once with the
same prompt file.
A second failure dispatches the route's fallback judge:
the judge after `fallback:` on the `seat:` line when it names one, otherwise
`dforge:judge-opus`, a fresh dispatch even when the failed seat was
judge-opus; say so. A third failure is `Task <N>: BLOCKED — review seat —
no usable report after three dispatches`. Exit 6 with
`run task-step review … first` means the review step never ran: run it.
Exit 7 is not a seat failure: it means the suite has no record at the review
head, so write no `Ruling:` line and re-dispatch no seat; run the suite and
call `verdict` again. Exits 5 and 6 are checked before 7.

**Panel seats.** `task-step review` wrote the reviewers' prompt to
`<workspace>/task-<N>-review-panel-prompt.md`, as
[external-review.md](external-review.md) §Task review seats describes, and
printed the panel command and its `timeout` (the command's `--cwd` is your
checkout's top level, or the `--cwd DIR` you passed to `task-step review`).
Run that command as a background Bash call with the printed `timeout`:
2590000 ms for `--tier light`, 5590000 for `--tier heavy`. Its shape is:

```bash
bash "<plugin-root>/scripts/run-review-panel" --kind task --tier <light|heavy> \
  --cwd <worktree-root> --out-dir <workspace>/task-<N>-review-panel \
  --prompt <workspace>/task-<N>-review-panel-prompt.md
```

It prints one status line per reviewer family, then `panel tier=<t>
lists=<n>`. Read those lines and take their word: `OK` and `FALLBACK` are a
reviewer that returned a list in `<out-dir>/<id>.json`, and on `FALLBACK` you
say the substitution aloud. `SKIPPED`, `TIMEOUT` and `FAILED` are a reviewer
that returned none: never run it again, since each runner has already applied
its own one-shot fallback. Then, by `lists=`:

- **`lists=0`:** dispatch the judge the `seat:` line names after `fallback:`
  or `then:` with the judge prompt file and one added line, "No external
  review file exists: skip the Second Pass section", and say so with each
  reviewer's reason.
- **`panel:light`, one list:** read that review from its JSON:
  `spec_verdict` (`compliant` or `issues`), `task_quality` (`approved` or
  `needs_fixes`), the four scores, `findings` and `cannot_verify`. Apply the
  bands, the cannot-verify route and the fix loop to it exactly as to a
  judge's report; its verdict and scores are the task's.
- **`panel:light`, two lists:** dispatch the judge after `fallback:` with the
  judge prompt file. Its Second Pass dedupes both lists and rules CONFIRMED
  or REJECTED on each finding; its verdict and scores are the task's.
- **`panel:heavy+judge-opus`, one or two lists:** dispatch
  `dforge:judge-opus` with the judge prompt file, whose Second Pass already
  names every list's path. The task's verdicts and scores are the judge's.
  Its findings, plus every external finding it marks CONFIRMED, drive the
  fix loop; each CONFIRMED cannot-verify item goes to the ruling seat as a
  `cannot-verify` item.

A report whose `## External findings` section is not its last formed its own
review after reading the lists; `task-step verdict` exits 5 on it. This
replaces the three-seat average earlier versions used for risk 3.

The digest's `cannot-verify:` lines are requirements
that live in unchanged code or span tasks. These do not block the rest of the
review, but each goes to the ruling seat as a `cannot-verify` item before
the task completes, unless a mechanical check settles it: the seat holds
the plan and cross-task context the reviewer lacks. A CONFIRMED-GAP is a
failed spec review — it enters the fix loop with the other findings.

## 4. The fix loop

The loop triggers when the digest shows `spec: fail`, any Critical or Important
finding line, any score of 1-8, or a cannot-verify item the ruling seat confirmed as a gap.

Before the loop starts, two routes leave it immediately:

- `task-step verdict` records Minor findings in the progress ledger
  (`Task <N>: minor (deferred): <file>:<line> — <one-liner>`); point the final
  whole-branch review at that list so it can triage which must be fixed
  before merge. A roll-up nobody reads is a silent discard. Minor findings
  never enter the loop.
- A finding labeled plan-mandated (its digest line's one-liner begins
  `plan-mandated:`) — or any finding that conflicts with
  what the plan's text requires — goes to the ruling seat as a
  `plan-conflict` item before you act on it; delete its bullet from the fix
  file before the fix dispatch. Do not dismiss the finding
  because the plan mandates it, and do not dispatch a fix that contradicts
  the plan without the seat's verdict in the ledger.

Everything else enters the loop. A fix round is one fix of your own plus one
scoped re-review. Two rounds at most per task:

Each round is your own fix, followed by one scoped re-review.

**Every round:** you fix, re-run the tests covering the amended code and
append your fix report to the same report file. Before dispatching the
re-review, confirm the fix report contains the covering tests, the command
run, and the output; dispatch the re-review once all three are present. Name the
covering test files in the fix message — a one-line fix does not need the
whole suite. The full suite is yours: when the fix is committed, start it at
the new head as §2 says (under a `none` task check, only when the review of
its task ran a suite) and run `rereview` in the same turn, so the fix head
has its own suite run beside its re-review.

**The fix message** is the file `<workspace>/task-<N>-fix-<R>.md`, `R` being
the round you are starting (1 for the first). Its first lines are one bullet
per open finding, `- <file>: <finding one-liner>`, then a blank line, then
what the fix needs: the finding's detail, the ruling's smallest fix, the
covering test files.
`task-step verdict` writes its bullets from the report, each `<file>`
carrying the finding's `:<line>`, with the severity lines after the blank
line; append the ruling's smallest fix and the covering test files below
them. Write the file yourself only for findings no report holds: a
mechanical check's finding, a CONFIRMED-GAP from the ruling seat, or a
light panel seat's JSON review. `task-step rereview` reads the bullets for the
findings list, so write the file before you call it.

**The re-review is scoped.** Run
`bash <plugin-root>/scripts/task-step rereview PLAN_FILE N`. It packages the
fix diff from the review head it recorded last to HEAD, records the new
review head, adds one to the recorded round, and writes
`<workspace>/task-<N>-rereview-<R>-prompt.md`:
[re-review-prompt.md](prompts/re-review-prompt.md)
with the findings from your fix message, the brief, the report file and the
diff path filled in. It prints the seat and that file; dispatch the seat with
the prompt "your complete instructions are in `<prompt file>`: read it first
and follow it". It prints `dforge:judge-sonnet-high`; for a subtle
concurrency fix dispatch `dforge:judge-opus` with the same file and say so.
When the seat returns, run
`bash <plugin-root>/scripts/task-step verdict PLAN_FILE N --rereview <R>`.
Its `fix round:` line says whether the round closed; its finding lines are
every finding still open, new breakage in the fix diff included, and it has
written them to the next round's fix file. After round 2 it writes no fix
file and its `fix:` line reads `breaker (round 2 of 2; …)`: send those
findings to the breaker. The re-reviewer's out-of-scope
issues reach the ledger as deferred Minor findings and never extend the loop.

**After each round,** append to the ledger:
`Task <N>: fix round <R>/2 (<X> addressed, <Y> open — <finding one-liners>; commits <a7>..<b7>; session)`

**The breaker.** When round 2's re-review still leaves findings open, stop
fixing and send every open finding to the ruling seat in one `breaker`
dispatch. The seat parks a finding that is wrong, contestable, or real but
built on by nothing downstream; returns CONFIRMED-GAP with the smallest
unblocking change for one a later task builds on; AMEND for a plan defect;
and BLOCKED when every path forward is a guess. Carry out each verdict (see
the caller's The Ruling Seat section). Parking a structural failure silently lets every dependent
task build on it, which is why the seat, not you, decides.

Send findings to the breaker only at the cap. Ending a loop earlier is
pre-judging with a different name. Every verdict is a ledger entry — a silent
discard is forbidden.

## 5. Complete the task

A task is marked complete only after `task-step verdict` passes: its digest
shows `fix: none` and a `suite:` line that is `pass`, `red` with 0 failing,
`not scheduled` or `none recorded`. A `suite: not run` (exit 7) or a `red`
with failing lines leaves the task open, and the fix loop (§4) or a suite run
(§2) comes first.

When the review comes back clean — or every open finding is parked, or
confirmed and carried into a later task, with a ruling at the cap — append the
completion line to the ledger in the same message as your other bookkeeping.
Write it with `scripts/task-close PLAN_FILE N '<checkpoint>' --review '<text>'`
(the checkpoint is the part after the dash, `<text>` the part inside the
parentheses after the commit range): it takes the range from the open line and
`HEAD`, pushes the ledger and runs the auto-run bookkeeping. A Codex plan has
no open line from `task-brief --open` (it exits 2 there), so `task-close`
exits 3 and you append the line by hand.
A confirmed gap goes to the next task that depends on this one; with none, to
the next task in plan order; after the last task, to the final review, written
`carried to final review`, where it is a confirmed finding:

- `Task <N>: complete (commits <base7>..<head7>, review clean; scores spec 17 / scope 18 / verification 15 / quality 16, seat <seat>) — done: …; verified: …; remaining: none; discovered: …; assumptions: …`
- `Task <N>: complete (commits <base7>..<head7>, <K> parked, <C> carried to Task <M>; scores …, seat <seat>) — …; remaining: <parked and carried one-liners>; …` after a tripped breaker; drop the `carried` clause when nothing was
- end the scores clause with `, seat <seat>`: the reviewers that returned a
  list and the judge, joined with `+` (`codex gpt-6.1-sol/xhigh`,
  `codex gpt-6.1-sol/xhigh+agy gemini-4-argon/high+judge-sonnet-high`,
  `agy gemini-4-argon/high+judge-opus`), or the judge's short name alone,
  followed by ` (<id> <STATUS> — <reason>)` for each reviewer that ran and
  returned no list, or by ` (reviewers off — <answers>)` when §3's `gate:`
  and `seat:` lines say no reviewer is open

In an auto run, run `scripts/auto-run task-complete`, then the Fable batch when
`scripts/auto-run decision list` prints anything.

Then mark the todo complete and move on. Never move to the next task while
the review has open Critical/Important issues that are neither fixed nor
parked or carried with a ruling at the cap.

## Early CI

An `**Early CI:**` line in the plan header names one point, `after task <n>`,
and the date your human partner consented to an early
push. With no `**Early CI:**` line in the plan header, nothing in this loop
pushes the branch or starts CI before finishing. Push only when the line
carries `— consented <YYYY-MM-DD>`. Run these steps right after the
`Task <n>: complete` line.

1. **Push.** Check the branch first: when HEAD is detached, or `<branch>` is
   `main`, `master`, the remote's default branch
   (`git symbolic-ref --short refs/remotes/origin/HEAD`) or the branch this
   one was created from, push nothing and write
   `Early CI: skipped — <branch> is not a feature branch`. Push the branch
   with `git push -u origin <branch>`.
2. **Start CI.** Start CI with `gh workflow run <workflow> --ref <branch>`
   only when the workflow file declares `workflow_dispatch`; otherwise print
   one line saying so and skip the early run. `<workflow>` is the first
   workflow file the plan's `**CI:**` line names that declares
   `workflow_dispatch`. Never open a pull request to start CI.
3. **Find the run.** `<file>` below is the `<workflow>` of step 2. Find the
   run with `gh run list --workflow <file> --branch <branch> --limit 1 --json databaseId,headSha`,
   retrying for up to 60 seconds until `headSha` is the pushed commit. Write
   `Early CI: dispatched run <id> at <sha7>` once the run is found. When none
   appears, write `Early CI: skipped — no run for <sha7> within 60 s`.
4. **Watch it in the background.** Run `gh run watch <id>` as a background
   Bash command, with the call's `timeout` set to (90 × 60 + 120) × 1000 ms,
   and keep working.

When the watch ends, read `gh run view <id> --json conclusion,jobs` and write
`Early CI: green run <id>`, or
`Early CI: red run <id> — <job>/<step>[, <job>/<step> ...]` naming each
failed job and its failed step. Any other conclusion (`cancelled`,
`timed_out`) with no failed step writes `Early CI: red run <id> — <conclusion>`.
A watch that ends with no conclusion, the run still going at 90 minutes,
writes `Early CI: skipped — run <id> still running at 90 min`. Any failure of
`git push` or `gh` prints one line, writes `Early CI: skipped — <reason>`, and
never stops the run. A `**CI:**` line that names no workflow declaring
`workflow_dispatch` writes the same `skipped` line. A red run is a bullet you
write into the next task's fix file, as §4 does for a mechanical check's
finding. Inline mode writes no fix files: there, debug a red run with
dforge:systematic-debugging before the next task's first step. With no task
left, a red run is a final-review finding, debugged with
dforge:systematic-debugging. On recovery, a `dispatched` line with no
`green`, `red` or `skipped` line after it gets
`gh run view <id> --json status,conclusion` once, and a new background watch
when the run is still going.

## The session review loop

dforge:executing-plans runs this loop for a task the session implements and a
judge reviews: a task whose brief's second line is
`**Review:** per-task — risk 3`. Nothing is dispatched to implement it; §3's
review, §4's verdicts and re-reviews and §5's complete line run as written,
with the session in the implementer's place.

1. **Start.** Run `bash <plugin-root>/scripts/task-brief --open PLAN_FILE <N>`.
   It writes the brief and the open line
   `Task <N>: implementer inline (assigned; base <sha7>)`; `task-step review`
   builds the step state from that line.
2. **Implement and report.** Implement, verify, self-review and commit as
   dforge:executing-plans §The Task Loop steps 3 to 6 say. Then write
   `<workspace>/task-<N>-report.md` in the implementer report shape
   ([implementer-prompt.md](prompts/implementer-prompt.md)
   §Report Format): status, commits, `## Verified`,
   `## Discovered issues (not fixed)` and `## Assumptions made`. The reviewer
   prompt names that file.
3. **Review.** Start the suite as §2's *The suite runs beside the review*
   says, run `bash <plugin-root>/scripts/task-step review PLAN_FILE <N>`,
   dispatch the seat it prints, and run `task-step verdict` once both are in
   (§3).
4. **Fix rounds, two at most.** Each round is your own fix, its covering
   tests appended to the report file under a new `## Verified` section, and
   the scoped `task-step rereview` (§4). After each
   round append
   `Task <N>: fix round <R>/2 (<X> addressed, <Y> open — <finding one-liners>; commits <a7>..<b7>; session)`.
   Minor and plan-mandated findings leave the loop as §4 says.
5. **Close.** A clean verdict writes §5's reviewed complete line, its scores
   clause ending `, seat <seat>`. After `2/2` with findings still open, send
   them to the ruling seat as one `breaker` item and carry out its verdicts
   (§4 The breaker); in an auto run the item goes on the pending list. Then
   run §Early CI when the header's `**Early CI:**` line names this task.

**Codex host.** `task-brief` writes the `**Review:**` line on Claude-host
plans only, and `task-step` and `review-route --task` exit 2 on a
`Host: codex` plan. There the loop runs for a task whose `**Evaluation:**`
line reads `risk=3`, through §The steps by hand §3 and §4, with a native judge
at Astra high or above as the seat ([native-codex.md](native-codex.md)).

## The steps by hand

`task-step` exits 2 on a `Host: codex` plan, and `task-step review` exits 2,
writing nothing, when `lens-route` does. Then run the mechanics yourself:

- **§1.** Record BASE (`git rev-parse HEAD`) before you start. Run
  `scripts/task-brief PLAN_FILE N` (see using-dforge §Session Budget): it
  prints `wrote <path>: <N> lines`, then the budget line; read the path out of
  the first line. Write the assigned line
  `Task <N>: implementer inline (assigned; base <sha7>)`.
- **§2.** On a DONE report, run
  `bash <plugin-root>/scripts/suite-run -- <suite command>` yourself in the
  background at the task's head and treat a non-baseline failure as §3's
  Important finding. `<suite command>` is resolved as §1's Suite command
  says: the task check, and under a `none` task check the integration check
  on the tasks §1 schedules, and no suite on the others.
  A failing line that the task's base commit also fails is baseline: run the
  suite once there, in a temporary worktree, and compare the failing lines as
  [final-review.md](final-review.md) **Baseline comparison** says. Under a `none` task check,
  compare with `<sha>` from §1, not with the task base commit.
- **§3.** Run `scripts/review-package PLAN_FILE BASE HEAD` (or, without bash:
  `git log --oneline`, `git diff --stat` and `git diff -U10` for the range,
  redirected to one uniquely named file) and pass the reviewer the path it
  prints; run `date +%s` in the same Bash call and keep the value as `t0`. Fill
  [task-reviewer-prompt.md](prompts/task-reviewer-prompt.md)
  yourself, `[PLUGIN_ROOT]` expanded to this plugin's resolved directory and
  `[LENS_FILES]` set to each `criteria=` path `scripts/lens-route PLAN_FILE --task <N>`
  prints (with none, delete that section),
  `[IMPLEMENTER_REPORT_FILE]` set to your report and `[REPORT_FILE]` to `<workspace>/task-<N>-review-report.md`.
  Check the commits' identity and
  attribution yourself, as the mechanical checks above describe.
  `task-step verdict` exits 2 on a `Host: codex` plan, so read the report's
  `## Verdict` section and its finding lines yourself and write the fix file
  from them.
- **§4.** Run `scripts/review-package PLAN_FILE FIX_BASE HEAD` where FIX_BASE
  is the head the previous review saw, with `date +%s` in the same call as the
  next round's `t0`, and fill the re-review prompt's placeholders yourself;
  its `[REPORT_FILE]` is `<workspace>/task-<N>-rereview-<R>-report.md`.

## Recovery

For a task whose last ledger line, read by the caller's Recovery rule, is:

| Last line | Action |
|---|---|
| An assigned line naming `executor <id> <model>/<effort>` (an executor lane run from before 5.0), or a later fix round of that task, with no complete line | The lane is gone, so the session implements the task. First run `git status`, show your human partner the leftovers, and keep or discard them as they decide; leftover run records under the git directory are inert. Then start the task as the caller's task loop says |
| `implementer <agent> (assigned …)`, the agent not `inline` (an older run's dispatch) | The session implements the task. If `git log <base>..HEAD` is non-empty, review it (§3); otherwise start the task as the caller's task loop says |
| `fix round R/5` on a `Host: codex` plan | Codex: R < 5 resumes the loop at round R+1 by the five-round schedule (§4); `fix round 5/5` goes to the breaker (§4) |
| `fix round 1/2` | The session finishes it: §The session review loop, from round 2 |
| `fix round 2/2`, or `fix round R/5` with R >= 2 from an older run | Go to the breaker (§4) |

On a Codex plan the Codex row wins; the `older run` mappings apply to a Claude plan only.
