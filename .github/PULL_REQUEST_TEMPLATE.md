## What and why

<!-- What this changes and the reason. Link the issue it closes. -->

## Checks run

- [ ] `node scripts/validate-repository.mjs`
- [ ] `node scripts/test-all.mjs`
- [ ] `node scripts/test-all.mjs --plugin dagents` (when dagents, `scripts/` or `tests/` changed)
- [ ] `claude plugin validate` on the marketplace and each changed Claude plugin
- [ ] `claude plugin test plugins/<plugin>` for each changed plugin among dforge, dagents and dflow

## Checklist

- [ ] A test covers the change and failed before it
- [ ] Claude and Codex manifest versions still agree
- [ ] Documentation is updated
