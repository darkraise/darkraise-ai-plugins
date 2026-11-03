# agy lane: Gemini first

**Source:** owner, 2026-11-03 session: the agy calibration for totals 3-8 and the owner's reply "start that, also note that the claude quota in agy will drain quickly, so use and assign them wisely"
**Covers:** docs/dforge/specs/2026-11-03-agy-gemini-first-design.md

| # | Item | Assigned | Acceptance | State | Note |
|---|---|---|---|---|---|
| 1 | Assign Flash medium to totals 0-2, Argon low to 3-4 and Argon high to 5-8 in the agy ladder | docs/dforge/plans/2026-11-03-agy-gemini-first.md | A1, A3, A5 | done | - |
| 2 | the claude quota in agy will drain quickly, so use and assign them wisely | docs/dforge/plans/2026-11-03-agy-gemini-first.md | A2, A7, A8, A12 | done | - |
| 3 | Track the agy quota per model family instead of turning the whole lane off | docs/dforge/plans/2026-11-03-agy-gemini-first.md | A7, A9, A11, A14 | done | - |
| 4 | Read Resets in ... from the quota error into the gate's resets_at field | docs/dforge/plans/2026-11-03-agy-gemini-first.md | A6, A10, A14 | done | - |
| 5 | Add Argon timeout rows (900 s for low, 1500 s for high, three times the slowest passing run) | docs/dforge/plans/2026-11-03-agy-gemini-first.md | A4 | done | - |
| 6 | Commit a calibration note for totals 3-8 that also records the first real quota error text | docs/dforge/plans/2026-11-03-agy-gemini-first.md | A13 | done | - |
| 7 | codex-gate:58 has the same 19+ digit epoch overflow that agy-gate had; cap it at 18 digits (Codex behaviour was out of scope for this plan) | e5522dee | - | done | a cached epoch past 18 digits reads as stale (0), as a non-numeric one did; agy-gate's empty-means-no-reset rule left out to keep Codex behaviour |
| 8 | agy-gemini-first.acceptance.test.sh:207: the A7 'still finishes' check reads a stale $? and cannot fail | fcc37312 | - | done | rc captured right after the Gemini run; a mutant with a failing run now fails the check |
| 9 | executor_session_mark_fallback_off reads the prior file once, so a lane mark written in the same milliseconds can be overwritten; the epoch-to-ISO date chain and the prior-file parse are duplicated across run-agy-task.sh and executor-session.sh | 88eaac27 | - | done | duplication only: executor_session_iso (also codex-gate) and one prior-file parse, which fixes mark_off on a two-object file; the race clause is row 12 |
| 10 | deferred minors: quota phrase checks in lanes.test.sh only test presence; Codex Quota bullet keeps the generic 'publishes no reset time' sentence; ladder.md still ranks claude-opus-5-5; reset regex reads only the first 'Resets in' and is case-sensitive | - | - | deferred | final review minors, none must be fixed before merge |
| 11 | darkmem-sync hooks.test.mjs 'GNU timeout escalates to SIGKILL' failed once with EPIPE under parallel load (passes alone) | 54e9f131, 69de0b9d | - | done | root cause: a write error on the bash() helper's stdin had no listener (EPIPE on POSIX, EOF on Windows pipes); reproduced in 10 of 72 loaded runs across three watchdog tests, 0 of 72 after |
| 12 | executor_session_mark_fallback_off reads the prior file once, so a lane mark written in the same milliseconds can be overwritten | - | - | deferred | split from row 9; a lost mark self-heals at one quota-failed launch; a real fix needs a portable mkdir lock with stale recovery, which is concurrency work for its own spec, and a gate probe that predates the quota can still rewrite a fresh mark |
