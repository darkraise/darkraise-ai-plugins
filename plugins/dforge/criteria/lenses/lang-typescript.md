# TypeScript and JavaScript Lens - Review Criteria

Applies: paths *.ts *.tsx *.js *.jsx *.mjs *.cjs *.mts *.cts

A review lens, not a scored rubric: report each hit as a finding tagged
[lens:lang-typescript] at your own severity. Known defect patterns only.

## Ground Truth Note

Judge the code the runtime will execute. Type annotations and casts are claims
the compiler may not check.

## Criteria

### Async Defects {#async}

Report a finding for a promise that is neither awaited nor returned (a floating
promise), an async callback passed to forEach, a missing await before a value
is used, or a rejection with no handler.

### Type Holes {#types}

Report a finding for "any" or an "as" cast that hides a real type error, a
non-null assertion on a value that can be null, "==" or "!=" where coercion
changes the result, or JSON parsed into a type without validation.

### Module Defects {#modules}

Report a finding for ESM and CommonJS mixed in one package without a boundary,
a default import of a module with only named exports (or the reverse),
__dirname or require in an ES module, or an import path missing the extension
an ES module needs.
