**Drafting acceptance:**

Under `autoRun=on` skip this step and the offer below: the statements are
drafted in the spec and settled at the spec review (see Auto by default).

Once your human partner approves the last design section, draft the spec's
acceptance statements before the auto-run offer, while they are still here to
answer. Each statement is one line:

`A<n>. [<test|demo>[, neg], <high|confirmed>] <statement>`

- `A<n>` numbers are never reused. A deferred statement leaves the line
  `A<n>. deferred — register row <id>`.
- `test` means an automated test can check it; `demo` means only a person
  watching the result can (visual output, an interactive screen).
- `neg` marks a statement about what must not happen; at least one carries it.
- Rate each statement while drafting: `high` when it follows directly from what
  your human partner said, from code you read this session, or from a recorded
  seat ruling; `medium` or `low` otherwise, each with the exact question that
  would settle it. `confirmed` is reserved for a verdict from your human partner.

1. Show the whole list in chat.
2. Ask about every statement rated below `high` with the multiple-choice
   prompt, at most four per call: the statement, why it is uncertain and the
   settling question, with the options **Right**, **Wrong, or not wanted** and **Not sure**.
   Keep a typed note verbatim.
3. **Right**: the statement becomes `confirmed`. **Wrong**: rewrite it from the
   note and ask once more; a second **Wrong** or **Not sure** defers it.
   **Not sure**: defer it.
4. To defer a statement, run
   `scripts/register add <register> "A<n>: <statement>" --state deferred --note "Q: <question>"`.
   With no register open, first open `<docs>/registers/<date>-<spec-slug>.md`
   as Opening an item register says; its `**Covers:**` stays `-` until the spec
   is written. A register row whose Item begins `A<n>:` is a deferred acceptance
   statement wherever dforge refers to one.

The step asks nothing when every statement is `high`. A statement you add or
change while writing the spec, rated below `high`, is asked the same way before
the spec is committed; in an auto run it goes up the ruling ladder instead
([auto-run.md](../../../reference/auto-run.md) §Rulings).
