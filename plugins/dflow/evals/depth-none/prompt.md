---
max_turns: 6
allowed_tools: [Read, Glob, Grep, Skill]
---

This repository uses dflow. In `src/config.js` the retry limit is the constant
`MAX_RETRIES = 3`, used by one function, `fetchWithRetry` in `src/fetch.js`,
which has a test in `tests/fetch.test.js`. Change the limit to 5.

Do not edit anything yet. Tell me how you will proceed, step by step.
