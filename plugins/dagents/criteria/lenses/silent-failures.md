# Silent Failures Lens - Review Criteria

Applies: added (catch|except|rescue|\|\| *true|2>/dev/null|\?\?|fallback)

A review lens, not a scored rubric: report each hit as a finding tagged
[lens:silent-failures] at your own severity.

## Ground Truth Note

A failure is silent when nobody downstream can tell it happened. Judge what the
code does when the operation fails, not what the happy path does. A log line
nobody reads is not handling.

## Criteria

### Swallowed Errors {#swallowed}

Look at every catch, except, rescue, "|| true", "2>/dev/null" and ignored
return value the diff adds. Report a finding when an error is caught and
dropped, replaced by a default, or logged and then treated as success, so the
caller proceeds on a false premise. Ignore fallbacks that are part of the
specified behaviour, which the next criterion owns.

### Fallbacks That Hide Failure {#fallback}

Look at default values, "??" and "||" chains, retries and alternate code paths.
Report a finding when a fallback makes a broken dependency look like a working
one: an empty list for a failed fetch, a cached value presented as fresh, a
retry loop with no final error. Ignore exit-status handling, which the next
criterion owns.

### Lost Exit Status {#status}

Look at pipelines, command substitutions, background jobs and process calls.
Report a finding when a non-zero status is lost: a pipeline without pipefail, a
"local x=$(cmd)" that masks the status, an awaited promise whose rejection is
ignored, a subprocess whose return code is never read.
