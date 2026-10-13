# Distillation judge contract

The dispatch prompt for the seat that gates deletion in
dr-forge:distilling-docs. Fill the placeholders and send it as the whole
instruction set: the judge has no other context.

## Placeholders

- `[SOURCES]` — the wave's source file paths, one per line.
- `[DISTILLED]` — the four `<docs>/distilled/*.md` paths.
- `[COMMIT]` — the SHA of the commit that added this wave's distilled entries;
  with documents in darkmem, one `<name>@r<id>` line per distilled file, as
  `darkmem-sync revision` printed it after the push.
- `[REWRITES]` — for each pre-existing entry this wave edited, its diff and a
  `git show` extract of every source named in its `Source:` lines (with
  documents in darkmem, the text of each source restored with `darkmem-sync restore`,
  as distilling-docs §Documents in darkmem says). `none` when the wave added
  entries only.

## The prompt

```markdown
You are verifying that a set of source documents can be safely deleted, because
every fact in them now lives in a distilled corpus. You are read-only: do not
edit any file. Your verdict decides whether these files are deleted.

Sources under review:
[SOURCES]

Distilled files as they now stand, at [COMMIT]:
[DISTILLED]

Pre-existing distilled entries this wave rewrote:
[REWRITES]

The files are unedited since [COMMIT] (a commit, or one revision per file). Read
them where they stand.
Name [COMMIT] in your report so a later reader can tell what you judged.

Work in this order. Do not skip to the verdict.

1. For EACH source file, enumerate every fact it states, as a numbered list.
   A fact is anything a future session could act on or get wrong: a measurement,
   a rule, a constraint, a workaround, a rejected approach, an authority for a
   claim, a date that scopes one. Do not summarise, do not group, do not judge
   importance yet. A file with thirty facts gets thirty numbered lines.
2. For EACH numbered fact, say which distilled entry carries it, by file and
   entry heading - "fact 7 maps to gotchas.md 'rg not found in a test that
   greps'" - or say it maps to nothing.
3. For each rewritten entry in [REWRITES], compare the new text against the
   source extract and say whether the rewrite preserves what the source stated.
4. Return one verdict per source file:
   - CARRIED - every enumerated fact maps to a named entry, and any rewrite of
     its entries preserves the source.
   - MISSING - at least one enumerated fact maps to nothing. List those facts by
     number.
   - DISTORTED - a fact is carried but its meaning changed. Quote the source and
     the entry side by side.

Enumerate before you map. A judge that reads holistically grades the summary it
was handed, and cannot notice the fact that is absent from both the summary and
its own attention. That failure is the entire reason this seat exists.

Output: the numbered enumeration per file, the mapping, the rewrite findings,
then the verdict list. Nothing else.
```
