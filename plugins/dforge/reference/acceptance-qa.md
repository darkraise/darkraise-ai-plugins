# Acceptance QA

Step 0.5 of the final review ([final-review.md](final-review.md)). One
implementer seat that did not write the plan turns the spec's `test`
acceptance statements into executable tests against the built branch, so the
plan writer is not the only author of the tests that grade its work. This file
is the seat's brief; final-review.md §0.5 is the session's part.

## The dispatch

The session dispatches `dforge:impl-sonnet-high` (on a Codex host, the
native implementer `gpt-6.1-sol / high`) with this file and:

- `[SPEC]` — the spec's path.
- `[STATEMENTS]` — every `A<n>` line of the spec's `## Acceptance` section
  tagged `test`, verbatim.
- `[BASE]` and `[HEAD]` — the branch's merge base and its head.
- `[TEST_COMMAND]` — the test command the project's `gates.md` declares, or
  `none`.
- `[WORKSPACE]` — the plan's workspace directory.
- `[MODE]` — one of:
  - `first`: write and run a test for every statement;
  - `rerun`: the acceptance file may already exist from an earlier run that
    was cut off. Run it as it is, never rewrite a test in it, and write tests
    only for statements it does not cover yet;
  - `reword A<n>[, A<m>]`: the spec's text for those statements changed.
    Rewrite only their tests, from the new text, and run the whole file.

## What you may read

The spec, the repository's code at `[HEAD]`, its README and documentation, and
its existing tests for their layout and helpers. You may not read the plan, the
ledger, task reports, review packages or anything else under `[WORKSPACE]`
except the report you write. Independence from the plan is the point of this
seat: the plan's tests were written by the same author as its code.

## Procedure

1. **Expectations first.** For each statement, write its expected outcome from
   the spec text alone, as literal values in the test, before you read any
   implementation beyond the public surface: the CLI and its `--help`, HTTP
   routes, the exported API, and the files the code writes. When the code
   disagrees with the statement, the test follows the statement.
2. **Where tests live.** Put the tests in the project's existing test layout,
   in one file named `<spec-slug>.acceptance.<ext>` (the spec's file name
   without its date and `-design.md`), or the nearest name the test framework
   accepts. Each test name starts with `A<n>:`; where a test name cannot hold a
   colon, use `a<n>_<words>`. Test only through the public surface.
3. **Run, with a timeout.** Run the file with `[TEST_COMMAND]` scoped to it,
   or the framework's own runner, always under `timeout`. A setup or import
   error is your own bug: fix the test. An assertion failure is a finding, which you never fix: you do not
   edit the code under test. Re-run a failing test once; when the two runs
   disagree, record `flaky`.
   Commit as you go: once a statement's test has run, whatever its result,
   commit the acceptance file and the fixtures it needs, and nothing else, as
   `test(<scope>): add acceptance test A<n> for <spec-slug>` (several
   statements written together may share one commit). The session removes
   your uncommitted files when its timer stops you, so a test that is not
   committed is lost, and a `rerun` can only build on what was committed.
4. **Mutation check on every `neg` statement.** For each statement tagged
   `neg` whose test passed:
   - `git worktree add --detach [WORKSPACE]/qa-mutation HEAD`: step 3
     committed the acceptance file, so `HEAD` has it;
   - in that worktree, link the dependency directories the tests need from the
     main worktree (for example `node_modules` or a virtualenv), or run the
     plan's `**Worktree setup:**` command when the session gave you one;
   - run that statement's test there before changing anything. It must pass:
     a failure here is a setup bug in the mutation worktree, so fix the setup;
   - make one minimal change that violates the statement (remove the guard,
     invert the check, skip the refusal);
   - run that statement's test there and record `red` when its assertion
     fails and `green` when it still passes. A missing file, an import or a
     setup error is not `red`: fix the setup and run it again;
   - `git worktree remove --force [WORKSPACE]/qa-mutation`, then confirm with
     `git worktree list` and `git status` that the main worktree is unchanged.
5. **Report.** Commit anything step 3's commits left out, as step 3 says, and
   write the report below.

## The report

`[WORKSPACE]/acceptance-report.md`:

```markdown
| Statement | Test | Result | Mutation |
|---|---|---|---|
| A1 | `tests/foo.acceptance.sh` A1: rejects an empty name | pass | n/a |
| A2 | `tests/foo.acceptance.sh` A2: never writes outside the root | pass | red |

Command: timeout 300 bash tests/foo.acceptance.sh → 2 passed, 0 failed
```

Result is one of `pass`, `fail`, `flaky`, `cannot-test: ambiguous` (the
statement can be read two ways; name both readings in the Test cell),
`cannot-test: no-surface` (no public surface reaches the behaviour; say what
is missing) or `cannot-test: timeout`. Mutation is `red`, `green` or `n/a`.

## Never

- Never edit the code under test, and never weaken a test so that it passes.
- Never leave the mutation worktree behind.
- Never write outside the test layout and `[WORKSPACE]/acceptance-report.md`.
- Never run a test without a timeout.
