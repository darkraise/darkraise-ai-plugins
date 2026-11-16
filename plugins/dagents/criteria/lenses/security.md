# Security Lens - Review Criteria

Applies: always

A review lens, not a scored rubric: report each hit as a finding tagged
[lens:security] at your own severity. Read by the final review and by a
risk-3 task review whose plan names it.

## Ground Truth Note

Judge the code in the diff, not the comments or commit messages that describe
it. A comment saying input is validated is not validation: find the check. A
passing test shows an attack path is closed only when it exercises that path.

## Criteria

### Injection and Unsafe Construction {#injection}

Look at every shell command, query, file path, URL, regular expression or
template the diff builds from data that can come from outside the process:
arguments, environment, files, network, user or hook input. Report a finding
when that data reaches the construct without quoting, parameterisation or an
allowlist, including eval, unquoted shell expansion and path joins that allow
"..". Ignore secrets, which the next criterion owns.

### Secrets and Credentials {#secrets}

Look at added literals, configuration, logs, error messages and test fixtures.
Report a finding when a credential, token, key or connection string is
hardcoded, logged, echoed into an error, written to a world-readable file or
committed as a fixture. Ignore authorization logic.

### Authorization and Trust Boundaries {#authz}

Look at code that decides who may do what, and at data crossing a trust
boundary: deserialisation, downloaded files, plugin or hook input. Report a
finding when a check is missing, runs after the action it guards, can be
bypassed by a default, or when untrusted data is deserialised or executed
without validation. Ignore construction defects, which the first criterion owns.
