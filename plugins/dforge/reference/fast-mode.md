# Fast mode

dforge:brainstorming and dforge:systematic-debugging offer fast mode before the
full flow starts for a request; the `fastMode` setting can take it without
asking (`always`) or never offer it (`off`). Your human partner choosing it is
an instruction of theirs, so it outranks every skill for that request.

Once fast mode is taken:

- Say `Process: fast — <why>` on a line of its own.
- Work the request the way plain Claude Code would: explore, change, run what
  the change needs, and report.
- Invoke no further dforge skill for that request. Write no spec, plan,
  register, ledger, next-step block or finishing menu; ask no worktree or
  finish question; dispatch no seats, reviewers or judges.
- Ask only what the work cannot proceed without. Choosing fast mode is the
  approval, so neither the design gate nor the TDD mandate applies.
- Your human partner's own instructions (CLAUDE.md, AGENTS.md, direct
  requests) still apply, including how they verify, commit and push.

dforge's unplanned-work stop hold, its UI proof hold, its UI edit hook and the
cockpit's seat check stand down while the latest `Process:` line the main
session wrote is `Process: fast`. Plan ledger and auto run holds do not.

Fast mode covers one request. The next request is routed as usual and offered
the choice again; a full-flow `Process:` line turns the hooks back on.
