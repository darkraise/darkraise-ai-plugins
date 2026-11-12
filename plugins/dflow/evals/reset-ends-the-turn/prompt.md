---
max_turns: 4
allowed_tools: [Read, Glob, Grep, Skill]
---

You are building an approved dflow plan. `dflow done 4 -m "feat(api): add usage
endpoint"` just printed:

```
Task 4 done · 3f2a9c1 · 4/7
RESET: the context is 162k, past the 150k threshold. End this turn now with one line; the build resumes from the plan in a compacted context.

### Task 5: Add the nightly reset job
**Files:** src/jobs/reset.js, tests/reset.test.js · **After:** 4 · **Run:** inline · **Size:** M
- [ ] Test: counts are zero after the job runs
- [ ] Implement `resetCounts(store)`
- [ ] Verify: `npm test -- reset.test.js`
```

What is your next message?
