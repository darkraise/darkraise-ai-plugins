# Bash Lens - Review Criteria

Applies: paths *.sh *.bash ; added ^#!.*(bash|/sh)

A review lens, not a scored rubric: report each hit as a finding tagged
[lens:lang-bash] at your own severity. Known defect patterns only. Scripts here
must also run under Git Bash on Windows and on macOS.

## Ground Truth Note

Judge what the shell will do with the text, including word splitting and glob
expansion, not what the author meant.

## Criteria

### Quoting and Expansion {#quoting}

Report a finding for an unquoted variable or command substitution that can hold
spaces, newlines or glob characters, an unquoted array expansion, a "for" loop
over "ls" output, or a pattern left unquoted where a literal was meant.

### Error Handling {#errors}

Report a finding for a "cd" without "|| exit" or a check, a pipeline whose
failure is lost without pipefail, "local x=$(cmd)" that masks the status of
cmd, a "set -e" relied on inside a function called from a condition, or a
command run with no timeout where it can hang.

### Portability {#portability}

Report a finding for GNU-only or BSD-only flags with no fallback ("sed -i"
without a suffix check, "readlink -f", "date -d", "grep -P"), a bash-only
construct in a script with a /bin/sh shebang, or a path that assumes "/" where
Git Bash hands a Windows path.
