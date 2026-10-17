# Docs and Comments Lens - Review Criteria

Applies: paths *.md ; added ^[[:space:]]*(//|/\*|\*[[:space:]]|#[[:space:]])

A review lens, not a scored rubric: report each hit as a finding tagged
[lens:docs-comments] at your own severity.

## Ground Truth Note

The code is the authority. A comment or document that disagrees with it is the
defect, however well written.

## Criteria

### Accuracy {#accuracy}

Look at every comment and document line the diff adds or leaves next to changed
code. Report a finding when it states behaviour, a name, a path, a default, a
count or an exit code the code does not have. Ignore stale references
elsewhere, which the next criterion owns.

### Rot {#rot}

Search the repository for references to names, paths, flags and section
headings the diff renames or removes. Report a finding for each document or
comment still pointing at the old one.
