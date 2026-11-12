# Test Quality Lens - Review Criteria

Applies: paths tests/* */tests/* test/* */test/* *__tests__/* *.test.* *_test.* *.spec.* test_*.py */test_*.py

A review lens, not a scored rubric: report each hit as a finding tagged
[lens:test-quality] at your own severity.

## Ground Truth Note

A test is worth its run time only if it fails when the behaviour it names
breaks. Judge each changed test by imagining the code broken in the way the
test's name describes.

## Criteria

### Tests That Cannot Fail {#cannot_fail}

Look at every added or changed test. Report a finding when it asserts nothing,
asserts only that code ran, would pass against a stub that returns a constant,
reads its expected value from the code under test, or is skipped. Ignore what
the test is coupled to, which the next criterion owns.

### Tests Pinned to Implementation {#pinned}

Report a finding when a test checks private structure, call order or mock
interactions instead of observable behaviour, so a correct refactor would break
it. Ignore missing cases, which the next criterion owns.

### Missing Cases {#missing}

Look at the branches the diff adds in the code under test. Report a finding
when an error path, a boundary value or a "must not happen" case has no test
that reaches it, and only when you can name the input that reaches that branch
and the wrong result it produces. A gap you cannot name both for is not a
finding.

### Redundant Tests {#redundant}

Among the tests in files the branch changes, report a test that fails for no
fault that another test does not also catch, and name the test that covers it.
A redundant test added on the branch is Important: the fix is to merge the
tests into a row of a table, or to delete the redundant one. A redundant test
that exists at the merge base, covered by a test added on the branch, is
Important with its one-liner beginning `deferred: test-simplifier` followed by
an em dash and a space; it is never fixed in the review. Ignore tests that
cannot fail, which the first criterion owns.
