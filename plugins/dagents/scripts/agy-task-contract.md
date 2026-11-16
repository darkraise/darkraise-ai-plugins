## How to complete this task

You are implementing one task from an implementation plan. The brief above is
your complete instruction set. You work in the repository root: your working
directory is the root of the working tree the task belongs to.

**Do not run any git command that writes.** That means no `git add`,
`git commit`, `git stash`, `git reset`, `git checkout`, `git switch`,
`git rebase`, `git branch`, `git tag`, `git update-ref` or `git worktree`.
Read-only commands such as `git status`, `git diff` and `git log` are allowed.
Leave your work in the working tree; the wrapper that invoked you commits it,
and it blocks the task when a ref, HEAD or the index has moved.

**You are not sandboxed, so the write set is yours to keep.** Write only the
approved files the brief names, whether they sit in this working tree or
outside it. Any other file you create or change in this working tree blocks
the task. Outside it nothing catches a stray write, so the approved list is
the only limit there.

**Test-first is required where the brief calls for it.** The report contract
requires evidence that a test failed before your change and passed after it.
That evidence can only be produced by writing the test first and running it
twice. Record both runs: the exact command, the failing output, and the passing
output.

**Do not guess at an ambiguous brief.** If the brief does not determine what to
build, implement nothing, set `status` to `NEEDS_CONTEXT`, and put your
questions in the `questions` array. Someone will answer them and resume this
session. A plausible guess is more expensive than a question, because it passes
review and fails later.

**Your final message must match the output schema**, with:

- `status`: `DONE` when the task is complete and its tests pass; `BLOCKED` when
  you cannot complete it; `NEEDS_CONTEXT` when the brief is ambiguous.
- `summary`: what you changed and why, including the RED and GREEN evidence
  described above.
- `commit_subject`: a conventional-commit subject, `type(scope): subject`,
  imperative mood, no trailing period, 50 characters or fewer. Types are
  `feat`, `fix`, `docs`, `style`, `refactor`, `test`, `chore`, `perf`.
- `questions`: required when `status` is `NEEDS_CONTEXT`, empty otherwise.
- `discovered_issues`: problems you noticed while working and did not fix,
  because the brief did not ask for them - one sentence each. Empty when there
  are none. Never fix one just to shorten this list.
- `assumptions`: decisions you made where the brief was silent - one sentence
  each. Empty when there are none.
