# UI Proof - Verifier Criteria

A judge seat reads this file, the UI/UX contract, the proof report and every
screenshot and state board the report cites, and rules whether the built UI
keeps the contract.

## Ground Truth Note

Trust only what you can see: a screenshot you opened, a state board, or a
named test whose file you read. Do NOT trust the report's verdict column, its
notes or the session's claims of success. An item whose evidence you cannot
open is unproven. A screenshot of a whole page proves nothing about a control
or a state it does not show at a readable size.

## Criteria

### Every Item Has Evidence {#coverage}

Look at the contract's items (for a touch report, its Delta items) and the
report's Results rows. Score HIGH when every item has a row whose evidence you
opened and which shows that item. Score LOW when an item has no row, its
evidence is missing or unreadable, or the evidence shows a different item or
state. A row marked unverifiable has no evidence by design: do not score it
LOW for that. It counts as covered when the report quotes the user accepting
that item (an `**Accepted by:**` line), and you judge only whether the stated
reason is a real limit of this host and whether the quote names that item.

### Built Matches Promised {#fidelity}

Compare each screenshot with the state board and the UI and Output promise
items it answers. Score HIGH when components, tokens, hierarchy, spacing
rhythm and copy match what was promised; pixel offsets need not. Score LOW
when the build drops an element, substitutes a different component, uses
colours or type outside the design system, or changes the copy.

### Every State Is Shown {#states}

Look at the contract's state matrix and interaction items. Score HIGH when
each data state (loading, empty, error, worst-case content and the others the
contract lists) and each control state (hover, keyboard focus, disabled,
pending, invalid) has a screenshot or a test at the viewports and themes the
report names, and the keyboard-only walk is evidenced. Score LOW when only the
default path is shown.

### Deviations Are Cited {#deviations}

Look at every row marked deviation and every difference you found yourself.
Score HIGH when each one cites the user's answer, a profile decision or an
accessibility need that forced it. Score LOW when a difference is uncited or
marked pass.

## Output

Score each criterion 1 to 20. List each disputed item as
"- <ID>: <what the evidence shows instead>". The verdict is ship only when
every criterion scores 15 or more and no item is disputed; otherwise it is
fix. End with exactly one line, "Verdict: ship <fingerprint>" or
"Verdict: fix <fingerprint>", using the fingerprint the dispatch names.
