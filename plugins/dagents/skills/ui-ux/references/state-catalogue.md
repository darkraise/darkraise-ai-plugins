# State catalogue

Walk this catalogue for every surface and control in the contract. Each state
the surface can reach goes into its state matrix item; a state it cannot reach
is named as unreachable, so the judge does not count it missing.

## Data states (per surface)

| State | Define |
|---|---|
| loading, first load | what shows, whether layout shifts, when a skeleton appears |
| loading, refresh | whether the old data stays visible |
| empty, first use | what belongs here and the one next action |
| empty, filtered | which filter emptied it and how to clear it |
| partial | some items failed or are still loading |
| error | what happened, how to recover, what stays usable |
| offline | what still works and what is queued |
| permission denied | what the user may do instead |
| stale or conflicting | someone else changed it meanwhile |
| worst-case content | see Worst-case data |
| success | how completion is confirmed |

## Control states (per interactive element)

Default, hover, keyboard focus, active (pressed), disabled (and why), pending,
selected or checked, invalid, read-only.

## Flow states

- Every entry point, deep links included.
- The main path, step by step.
- Alternate paths, and cancel at every step.
- Undo and back.
- Session expiry or reauthentication mid-flow.
- Interruption (closing the window, losing the connection) and how it resumes.

## Worst-case data

Demo data is chosen to make a design look good. The proof uses data chosen to
break it:

- the longest realistic names, titles and labels, and one unbroken string
  (a URL or an identifier);
- the largest realistic counts: items, columns, notifications, digits in
  amounts;
- empty, null and missing values for every optional field, and a missing
  image;
- right-to-left text, diacritics and emoji;
- zero, one and many of every collection;
- dates at the boundaries: today, the far past, the far future, other time
  zones.

Load it through the same boundary the real data uses (the API, a fixture, a
seed script), never by editing the component. A development-only switch
between demo and worst-case data is the cheapest way to keep it.
