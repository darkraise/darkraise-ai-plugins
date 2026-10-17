# Test Quality Lens - Review Criteria

Applies: paths *tests/* *test/* *__tests__/* *.test.* *_test.* *.spec.* *test_*.py

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
that reaches it.
