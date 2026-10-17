## What and why

<!-- What this changes and the reason. Link the issue it closes. -->

## Checks run

- [ ] `node scripts/validate-repository.mjs`
- [ ] `node scripts/test-all.mjs`
- [ ] `claude plugin validate` on the marketplace and each changed Claude plugin
- [ ] `claude plugin test plugins/dforge` (when dforge changed)

## Checklist

- [ ] A test covers the change and failed before it
- [ ] Claude and Codex manifest versions still agree
- [ ] Documentation is updated
