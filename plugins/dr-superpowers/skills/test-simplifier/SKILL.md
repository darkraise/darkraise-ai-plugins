---
name: test-simplifier
description: Use when a test sweep has become slow or heavy - long local runs, rising CI cost, or many tests added by a programme of plans - measures where the time goes, recovers it without deleting tests first, then merges or removes tests only where mutation evidence shows no fault goes uncaught
---

# Test Simplifier

**Announce at start:** "I'm using the test-simplifier skill to make <suite> faster without losing what it catches."

TDD adds a test every cycle and never takes one away. Over many plans a suite
collects near-duplicate examples, the same rule asserted at three layers,
mocked tests that restate the implementation, sleeps, and setup paid per test.
This skill gets the time back in the order that risks the least: measure,
speed up without deleting, tier the run, and only then remove or merge tests,
each removal proven by evidence an independent judge checks.

**Coverage never proves a test redundant.** It counts lines that ran, not
assertions that were made. Reducing suites by statement coverage has lost up to
a fifth of their fault detection; reducing by mutants killed lost none. Every
removal here is proven by faults caught, never by coverage alone.

## The ledger

Every run keeps one ledger, `docs/superpowers/test-simplifier/<YYYY-MM-DD>.md`:
the baseline, one row per phase or wave with `test-profile --brief` before and
after, every removal with its evidence, and every judge verdict with the SHA it
was given. It is how a later session resumes and how a reviewer audits a
deletion. Commit it with each wave.

## Phase 1. Measure

Run the suite once with JUnit XML output (every major runner emits it; the
flags are in [runners.md](references/runners.md)), then:

```bash
bash <plugin-root>/scripts/test-profile [--layer NAME=ERE]... <report dir>
```

Read the summary, never the raw XML. It gives time per layer, the slowest files
and tests, suite time spent outside any test case, and failed, skipped and
retried counts. Record it as the ledger's baseline, with the command that
produced the reports. A suite that is red at baseline is fixed or its failures
are listed first: a removal judged against a red suite proves nothing.

## Phase 2. Recover time without deleting

Work down the slowest files and tests. Only these fixes, which change how a
test runs and not what it asserts:

- a sleep becomes a poll, a callback or the framework's auto-wait;
- immutable or transaction-reset setup moves to a wider fixture scope;
- a real dependency in a unit test becomes an in-memory fake the project
  already has, or containers are reused across a local run;
- the runner runs in parallel or sharded;
- a non-deterministic test is quarantined, never deleted, with a ledger line
  naming its failure. Quarantine means a separate tag or tier that still runs in
  the full sweep.

After each fix the test still passes, and it still fails when the behaviour it
names is broken: break it once by hand and watch it go red. Commit fixes in
small batches and add a `--brief` row per batch. Phases 2 and 3 alone often take
the inner loop from hours to minutes; when they meet the goal your human partner
set, offer to stop here.

## Phase 3. Tier the run

Split the run into three tiers. Nothing is deleted.

| Tier | What runs | When |
|---|---|---|
| Inner loop | tests affected by the change set (impact selection, see [runners.md](references/runners.md)) | during TDD and per task |
| Branch gate | the fast layers in full | before merge, through dr-superpowers:running-gates |
| Full sweep | everything, slow layers and quarantine included | in CI after merge, or nightly |

Propose the tiers to your human partner as a diff to
`docs/superpowers/gates.md` (the branch gate, with a `Why:`) and one line for
`CLAUDE.md` or `AGENTS.md` naming the inner-loop command, then apply them only
on approval. Moving a slow layer out of the branch gate changes what proves a
merge; it is their call, not yours. A full sweep that no longer runs anywhere
is a deletion in disguise: the CI job that runs it must exist before the gate
narrows.

## Phase 4. Remove or merge, mutation-gated

Work in **waves**: one module or package, at most about twenty candidates,
never the whole suite. A wave changes **test files only**. Production code
untouched is what makes the before and after mutant sets identical and
comparable; a production change goes in its own commit outside the wave.

### Candidates

1. **Repeated across layers.** The same rule asserted at e2e or integration and
   again below. Keep the lowest test that fails for it; a higher test keeps only
   what crosses its boundary.
2. **Near-duplicate examples.** Merge into one table-driven or parametrized
   test with literal expected values, or one property test.
3. **Change-detector tests.** Assertions on calls, mocks or large snapshots that
   break on a refactor and not on a bug. Rewrite at the behaviour boundary, or
   remove when a behaviour test already covers it.
4. **E2E for edge cases.** Move the case down a layer; keep one e2e test per
   user journey.
5. **No outcome asserted.** A test that only executes code. Give it the
   assertion its name promises, or remove it.

### Never removed

Whatever the evidence says:
- a regression test naming a fixed bug, unless the ledger names the kept test
  that now fails for that bug;
- the only test of a public contract, an error path, or a security check;
- a test that a `gates.md` entry or its `Why:` line relies on;
- a quarantined test: fix it or leave it.

### Evidence

**With a mutation tool for the language** ([runners.md](references/runners.md)),
scoped to the wave's module:

1. Before the wave, run it against the module with the current tests. Save the
   report under `.superpowers/test-simplifier/<wave>/before`, and record the
   killed (or timed-out) count in the ledger.
2. Make the wave's changes. Run the module's tests: green.
3. Run the mutation tool again, same scope and configuration, saving to
   `.../<wave>/after`. **Every mutant killed before is killed after.** One
   mutant newly surviving fails the wave: restore the test that killed it, or
   strengthen a kept one, and re-run.
4. Coverage of the module does not drop either. Both must hold.

**Without one**, the faults must still be caught. Before changing anything,
dispatch dr-superpowers:judge-opus with the *fault* prompt in
[simplify-judge.md](references/simplify-judge.md): for each candidate it names
three to five concrete faults that candidate catches today. Then make the wave's
changes and, for each named fault, apply it to the production code as a
temporary patch, run the module's tests, record red or green in the ledger's
fault table, and revert the patch. Every named fault must turn the kept tests
red. A fault that stays green fails the wave as a surviving mutant does. After
the last revert, `git status --porcelain` shows no production file.

### Verification

Commit the wave, including its ledger section with the evidence, before the
judge runs, and dispatch dr-superpowers:judge-opus with the *ruling* prompt in
[simplify-judge.md](references/simplify-judge.md), naming that SHA and carrying
its `git show` output, since the judge has no Bash. The working tree stays
clean at that SHA until the verdict returns.

| Verdict | Meaning | Consequence |
|---|---|---|
| `KEPT` | No killed mutant or named fault lost; never-removed rules held; merged tests assert what the originals asserted | The wave stands |
| `LOST` | A fault or mutant the old tests caught is no longer caught | Restore or strengthen, re-commit, re-judge |
| `VIOLATED` | A never-removed rule broke, or production code changed in the wave | Revert that part, re-commit, re-judge |

A wave the judge does not return `KEPT` against its commit is reverted, not
left in place. Commits:

```
test(<scope>): speed up <area> tests          # phase 2, per batch
test(<scope>): simplify <module> tests        # phase 4, one per wave
```

## Report

End with the ledger's baseline and final `--brief` rows side by side, the time
recovered per phase, removals and merges per candidate class, every quarantined
test, and the tier changes still awaiting approval.

## Red Flags

| Thought | Reality |
|---------|---------|
| "Coverage didn't drop, so the test was redundant" | Coverage counts execution, not assertions. Only mutants or named faults prove it. |
| "Deleting the slow e2e suite is the quickest win" | Phases 2 and 3 first. Moving it to the full sweep keeps it; deleting it does not. |
| "I'll fix this production bug while I'm in the wave" | The wave changes test files only, or the before and after mutants differ. |
| "This flaky test is noise, remove it" | Quarantine it. A flake is a bug in the test or the code, not evidence of redundancy. |
| "The mutation run is slow, I'll skip it for this wave" | Then the wave removes nothing. Scope the run to the module instead. |
| "The judge will say KEPT" | Dispatch it against a commit. The wave stands on the verdict, not the expectation. |
| "I'll run the mutation tool on the whole repo" | One module per wave. A repo-wide run costs more than the suite it is slimming. |
