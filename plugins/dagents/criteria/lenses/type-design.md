# Type Design Lens - Review Criteria

Applies: added ^[[:space:]]*(export[[:space:]]+)?((public|internal|private|protected|abstract|sealed|static|readonly|partial)[[:space:]]+)*(interface|type|class|struct|record|enum)[[:space:]]+[A-Z]

A review lens, not a scored rubric: report each hit as a finding tagged
[lens:type-design] at your own severity.

## Ground Truth Note

Judge the types the diff declares by the states they allow, not by their names
or comments.

## Criteria

### Invariants in Types {#invariants}

Look at each added type. Report a finding when it can represent a state the
code treats as impossible: two fields that must not both be set, a status
string where a closed set exists, a nullable field that is never null after
construction, a number that must stay in a range. Ignore visibility, which the
next criterion owns.

### Encapsulation {#encapsulation}

Report a finding when a type exposes mutable internals that callers can use to
break its invariants, or when callers must remember a call order the type could
enforce itself.
