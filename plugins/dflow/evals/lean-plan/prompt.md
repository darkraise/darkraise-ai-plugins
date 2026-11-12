---
max_turns: 8
allowed_tools: [Read, Glob, Grep, Skill]
---

This repository uses dflow. It is a Node service with `src/api/`, `src/store/`
and `tests/`, and `npm test -- <file>` runs one test file.

Plan this feature: an endpoint `GET /usage` that returns the caller's request
count for the current day, read from a new store module, and a nightly job
that resets the counts. Reads and resets can overlap.

Do not create files. Reply with the full text of the plan document you would
write.
