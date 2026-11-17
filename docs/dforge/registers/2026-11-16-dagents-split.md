# dagents split

**Source:** owner request 2026-11-16 (owner's words), with the owner's method ruling: "checkout version 4.17.1, copy to new dagents plugin folder, update plugin definition file, then apply bug fixes from latest code base (dforge 5.0.0)"
**Covers:** docs/dforge/specs/2026-11-16-dagents-split-design.md

| # | Item | Assigned | Acceptance | State | Note |
|---|---|---|---|---|---|
| 1 | Move the dforge version 5 to new plugin named: dforge | docs/dforge/plans/2026-11-17-dagents-split.md | A2, A17, A19, A23, A28, A29 | verify | built on auto/dagents-split, unmerged; waits on the merge and a green Validate marketplace run (A19) |
| 2 | The last version of version 4.x move into new plugin named: dagents | docs/dforge/plans/2026-11-17-dagents-split.md | A1, A2, A5-A10, A13, A20, A21, A26 | verify | built on auto/dagents-split, unmerged; waits on the merge and a green Validate marketplace run (A19); A6 and A26 deferred as rows 9-10 |
| 3 | Add script to check when install plugin to prevent install and enable more than 1 of [dforge, dagents, dflow] at the same time | docs/dforge/plans/2026-11-17-dagents-split.md | A11, A12, A14-A18, A24, A25, A27 | verify | built on auto/dagents-split, unmerged; waits on the merge and a green Validate marketplace run (A19) |
| 4 | Also apply all the bugs fix from version 5 to version 4 | docs/dforge/plans/2026-11-17-dagents-split.md | A3, A4, A8, A22 | verify | built on auto/dagents-split, unmerged; waits on the merge and a green Validate marketplace run (A19); A8 passed in the finishing integration check at 73ed2f2f |
| 5 | New dagents plugin will start at version 1.0 | docs/dforge/plans/2026-11-17-dagents-split.md | A2 | verify | built on auto/dagents-split, unmerged; waits on the merge and a green Validate marketplace run (A19) |
| 6 | dagents does not follow dforge fixes that land after the split; a later backport reruns scripts/dagents-backport.mjs | - | - | deferred | spec out of scope: later dforge fixes |
| 7 | ar_switch matches the plan's file name as a substring of the first prompt (dagents and dforge alike) | - | - | deferred | final review: Task 14 minor; port dforge's fix when it lands |
| 8 | workflow-guard prunes a stand-down marker older than 7 days though its session may still run | - | - | deferred | final review lens:security minor; touch the marker on each guarded hook or prune only ended sessions |
| 9 | A6: dforge is spelled only where the allowlist and version-qualified origin text allow | - | - | deferred | rejection upheld: the test's filename regex omits hooks/cockpit/lib.ts, an older-spelling reader spec §3 allows |
| 10 | A26: a dagents push and pull request only the dagents client, dagents/ documents and dagents/ workstream keys | - | - | deferred | rejection upheld: migrateServer's superpowers/ and forge/ manifest requests are the 4.17.1 older-spelling move spec §3 keeps |
| 11 | dforge cockpit tests plugin-review-fixes A20 and api-decisions-keep-warm A22 time out at 5 s under host load; they predate 9d669ab3 | - | - | deferred | final review residual: raise their timeout if CI runners fail them |
| 12 | no test covers the mods' guard-check reset after a timed-out or failed check (dagents, dforge, dflow guardNow) | - | - | deferred | final review residual |
| 13 | backport row 279's fail@parent pass@port rests on a root run under a cygpath stub; the opt-in A4 replay cannot show a Windows-only skip | - | - | deferred | final review residual |
