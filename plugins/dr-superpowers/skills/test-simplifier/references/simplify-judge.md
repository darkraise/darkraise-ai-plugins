# Simplification judge contract

The two dispatch prompts for dr-superpowers:test-simplifier's judge seat. Fill
the placeholders and send one prompt as the whole instruction set: the judge
has no other context and no Bash, so everything it must compare is either a
path it can read or text in the prompt.

## Placeholders

- `[MODULE]` — the production module or package the wave covers.
- `[CANDIDATES]` — each candidate test, as `path::name`, with its class (1 to 5
  from the skill) and the action proposed: remove, merge into `<test>`, move to
  `<layer>`, rewrite.
- `[TESTS]` — the test file paths the wave touches, as they stood before it.
- `[COMMIT]` — the SHA of the wave's commit.
- `[DIFF]` — the output of `git show [COMMIT]`, in full.
- `[EVIDENCE]` — either the paths of the before and after mutation reports
  (saved under `.superpowers/test-simplifier/<wave>/`) with the killed-mutant
  counts, or the fault table from the ledger: each named fault, the kept tests
  run, and red or green.
- `[GUARDS]` — the regression tests, contract, error-path and security tests,
  and `gates.md` references among the wave's tests, as the ledger lists them.

## The fault prompt

Used only when the language has no mutation tool, before the wave changes
anything.

```markdown
You are naming the faults a set of tests catches today, so that a later change
can prove it still catches them. You are read-only: do not edit any file.

Module under test: [MODULE]
Candidate tests and the action proposed for each:
[CANDIDATES]

For EACH candidate, in this order:
1. Read the test and the production code it exercises.
2. Name three to five concrete faults in the production code that make this
   test fail today: the file, the line or function, and the exact edit, such as
   "`src/price.ts` `applyDiscount`: change `>=` to `>` on the threshold check".
   Each fault must be a plausible bug, not a deletion of the function. Prefer
   faults on the boundary, branch, error path and side effect the test asserts.
3. Say which assertion in the test catches each fault.

Do not consider what other tests catch. Do not judge whether the candidate
should be removed.

Output: one numbered list of faults per candidate, nothing else.
```

## The ruling prompt

```markdown
You are ruling on whether a change to a test suite lost any fault detection.
You are read-only: do not edit any file. Your verdict decides whether the
change stands or is reverted.

Module under test: [MODULE]
Candidates and the action taken on each:
[CANDIDATES]
Test files before the change: [TESTS]
The change, committed at [COMMIT]:
[DIFF]
Evidence:
[EVIDENCE]
Tests the rules say are never removed:
[GUARDS]

The working tree is clean at [COMMIT]. Read files from the working tree. Name
[COMMIT] in your report.

Work in this order. Do not skip to the verdict.

1. Confirm the diff touches test files and the ledger only. Any production file
   in it is a violation.
2. For EACH removed or merged test, list every assertion it made, numbered.
   For each numbered assertion, name the kept test and assertion that now
   checks the same thing, or say none does.
3. Read the evidence. For mutation reports: is every mutant killed before also
   killed after? List any that are not. For a fault table: did every named
   fault turn the kept tests red? List any that did not.
4. Check each test in [GUARDS] against the diff: still present, or the ledger
   names the kept test that now fails for its bug.
5. Return one verdict for the wave:
   - KEPT - no lost mutant or fault, every assertion maps to a kept one, and
     every guard holds.
   - LOST - a mutant or fault is no longer caught, or an assertion maps to
     nothing. List them.
   - VIOLATED - a production file changed, or a guard was removed without its
     named replacement. Quote the diff lines.

Map assertions before ruling. A judge that reads the summary in the ledger
grades the summary, and cannot notice the assertion that was quietly dropped
from a merged table.

Output: the step 1 finding, the numbered assertion mapping, the evidence
finding, the guard check, then the verdict. Nothing else.
```
