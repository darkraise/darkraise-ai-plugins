# Python Lens - Review Criteria

Applies: paths *.py

A review lens, not a scored rubric: report each hit as a finding tagged
[lens:lang-python] at your own severity. Known defect patterns only.

## Ground Truth Note

Judge the code the interpreter will execute. Type hints are not enforced at run
time.

## Criteria

### Binding Defects {#binding}

Report a finding for a mutable default argument, a closure in a loop that reads
the loop variable later (late binding), or a class attribute used as
per-instance state.

### Exception Defects {#exceptions}

Report a finding for a bare "except:", "except Exception" that swallows the
error, an exception re-raised without "from" where the cause matters, or
"assert" used for validation that "python -O" removes.

### Resource Defects {#resources}

Report a finding for a file, socket or lock opened without a context manager, a
subprocess call with no timeout or with "shell=True" on built strings, or a
generator left half-consumed while it holds a resource.
