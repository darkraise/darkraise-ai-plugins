# C# Lens - Review Criteria

Applies: paths *.cs

A review lens, not a scored rubric: report each hit as a finding tagged
[lens:lang-csharp] at your own severity. Known defect patterns only.

## Ground Truth Note

Judge the code the runtime will execute. Nullable annotations and analyzer
suppressions are claims, not checks.

## Criteria

### Async Defects {#async}

Report a finding for "async void" outside an event handler, ".Result",
".Wait()" or ".GetAwaiter().GetResult()" on a task (sync over async), a task
that is started and never awaited, or a CancellationToken accepted and ignored.

### Resource Lifetime {#disposal}

Report a finding for an IDisposable that is created and not disposed (no
"using"), an event handler subscribed and never removed on a longer-lived
publisher, or a timer or stream kept alive by a static reference.

### Null and Capture Defects {#nulls}

Report a finding for the null-forgiving "!" on a value that can be null, a
nullable warning suppressed instead of handled, or a loop variable of a "for"
loop captured by a closure that runs later.
