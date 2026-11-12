# Gotchas

Symptom first. Delete an entry when its cause is fixed.

- node --test <directory> fails on Node 24 with a single failed test named after the directory; name the files by glob (plans/2026-11-12-dflow-v1.md, 2026-11-12)
- In a mod test a stubbed clock.every or clock.after that resolves runs its callback after the test ends and rejects with '$.state.get refused'; answer those stubs with { deny } instead (plans/2026-11-12-dflow-v1.md, 2026-11-12)
