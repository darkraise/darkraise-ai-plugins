# Architecture Critique - Review Criteria

Applied by dr-forge:brainstorming on the architectural path, after the spec
self-review and before the spec review. These are review lenses, not a scored
rubric: the prompt asks for ranked findings.

## Ground Truth Note

Judge the design the spec describes against the repository as it is. Read the
files the spec names before believing what it says about them. A stated
rationale ("kept simple on purpose", "we will add it later") is the author
grading the design and settles nothing; weigh the design itself.

## Criteria

### Simplest Sufficient Design {#simplest}

Look at the components, files and abstractions the spec introduces. Report a
finding when a simpler design meets every stated requirement, when an
abstraction has one use and no second one in sight, or when a boundary matches
no real seam in the code. Ignore requirements the spec never states; the next
criterion owns those.

### Unstated Requirements {#unstated}

Look for the non-functional requirements the design depends on without saying
so: latency, throughput, consistency, compatibility with existing callers and
stored data, platform support, cost. Report a finding when the design relies on
one silently or would violate one. Ignore failure handling, which the next
criterion owns.

### Failure and Change Paths {#failure}

Trace one realistic failure end to end through the design, and read its
migration and rollback story. Report a finding when a failure has no defined
outcome, when existing data or users have no path from the old behaviour to the
new, or when the plan is "we will figure it out". Ignore day-to-day operation,
which the next criterion owns.

### Operability {#operability}

Picture the person debugging this in production, or in a stuck automated run.
Report a finding when the design gives them no way to see what happened: no
log line, status, ledger entry or error message that names the cause. Ignore
code style and naming.
