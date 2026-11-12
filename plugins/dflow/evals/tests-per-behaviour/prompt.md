---
max_turns: 8
allowed_tools: [Read, Glob, Grep, Skill]
---

This repository uses dflow. I am writing a dflow plan for a function
`formatLimit(remaining, limit)` that returns text such as `"12 of 50 left"`,
or `"limit reached"` when remaining is 0. It lives in `src/format.js`; the
project already has `tests/format.test.js` with a table of cases.

Write the one task for it, in the plan's task format. Be thorough about tests:
I want everything covered, including the exact wording of both messages, the
constant `DEFAULT_LIMIT = 50`, and that it uses template strings.
