## How to complete this task

You are implementing one task from an implementation plan. The brief above is
your complete instruction set.

**You cannot use git.** Your sandbox denies writes to `.git`, so `git add`,
`git commit`, and `git stash` will fail. Do not attempt them. Leave your work in
the working tree; the wrapper that invoked you commits it.

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
