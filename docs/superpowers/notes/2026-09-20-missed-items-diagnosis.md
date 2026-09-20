# Missed items across sessions — diagnosis (2026-09-20)

Owner report: when dr-superpowers works through a list of issues and findings, some items go missing after a few sessions, and the assistant claims completion, even when asked "what should we do next?". Evidence source: the darkraise-modder project (`D:\Repositories\Personal\darkraise-modder`).

## The incident (UX polish programme, 2026-09-18 to 2026-09-20)

The owner's list of 2026-09-18 (15 items) plus five adjacent findings became a hand-made item ledger: `darkraise-modder/docs/superpowers/plans/2026-09-18-ux-polish-programme-ledger.md` (22 rows). The programme design (`.../specs/2026-09-18-ux-polish-programme-design.md`) named four sub-projects: A framework bugs, B framework features, C modder surfaces, D workspace.

- The C brainstorm split C into C1 (shell surfaces) then C2 (Settings). Recorded only in the C1 spec header (`specs/2026-09-19-ux-polish-c1-shell-surfaces-design.md`, lines 4-5).
- B was also split into B1, B2, B3. C1 merged, then D, and C2 was never specced, planned or built.
- Ledger rows 4, 6, 16, 17 (Settings tabs and Card radius, code-editor preview, stale note, unused UI-font setting) stayed `planned`; rows 21, 22 stayed `planned` awaiting an owner ruling.
- End of D, session `a221af02-e26a-45c8-86d3-226450ce5799`: the finishing skill printed "After integration: the program is complete (this is sub-project 4 of 4)", and the modder's `merge-local` skill wrote a memory note saying the programme was complete.
- The owner noticed only by memory, session `219e1b04-6875-400a-82eb-02d9518521c5` (2026-09-20 ~06:14): "I remembered that I mentioned about Settings dialog revamp". The assistant answered "My memory note saying 'programme complete' after D is wrong; C2 is the gap."

Transcripts: `C:\Users\quang\.claude\projects\D--Repositories-Personal-darkraise-modder\<session>.jsonl` (mirrored under `.claude-alt`). Earlier "what should we do next?" answers: sessions `c82c648c-1c92-4710-808a-4a7461fab5d5` (2026-09-19 09:02) and `e5ecab9a-6fda-442d-9f37-8c89015562af` (13:10); both were correct because the assistant happened to read the ledger. Helper scripts: `.superpowers/handoff/tools/prompts.mjs <since-date>` lists user prompts per session; `dump.mjs <session-id> <from> <maxchars> [all]` dumps a session (edit the `dir` constant if the project path differs).

## Mechanism (verified by reading code and plans)

1. **The Program line is a frozen singly linked list.** `skills/writing-plans/SKILL.md:80-82` says `next:` is "copied from the program's decomposition". C1's plan (`darkraise-modder/docs/superpowers/plans/2026-09-19-ux-polish-c1-shell-surfaces.md:15`) says `sub-project 3 of 4 — next: D. Workspace`; D's says `4 of 4 — last`. The B1, B2 and B3 plans all say `2 of 4 — next: C. Modder surfaces`, although B2 and B3 followed B1. A split made in a child spec never propagates to the program's k-of-n or the successor pointer.
2. **Completion is read from that one line.** `scripts/next-step:171` prints "Nothing — every sub-project of `<spec>` is done" whenever the line ends `last` or k >= n. It reads no item-level source. The finishing skill's "After integration:" line comes from the same place.
3. **`plan-lint` checks only the line's shape** (`scripts/plan-lint:69-76`: pattern, k <= n, path exists). It never checks that every sub-project or split half has a plan, or that any list of source items is covered.
4. **`project-status` treats `completed.md` as "the only completion signal"** (`skills/project-status/SKILL.md:37-40`) and treats a program design as "never unplanned" (lines 44-50). No item ledger can veto "done". In the modder repo `completed.md` also lacks B1, B2, B3 and C1 because the owner's own `merge-local` skill skips finishing Step 5b, so the signal is unreliable there too.
5. **The modder's `status` skill** (`darkraise-modder/.claude/skills/status/SKILL.md`) lists plans, specs, sdd progress files, `latest.md` and darkmem milestone memory as sources, but not the programme ledger. After "programme complete" was written to memory, "what next?" would trust it.
6. **The follow-ups note only covers work that got a task.** Finishing Step 5b writes `docs/superpowers/notes/<slug>-followups.md` from deferred, parked and discovered lines; it first appears in commit `c0b6511` (2026-09-19). An item that never became a task has no line.

Root gap: dr-superpowers has no first-class list of source items. Item -> task -> done traceability exists only in the modder's hand-built ledger, which the plugin neither creates, reads nor enforces.

## Candidate fixes (from the session; none designed or approved)

1. Make an item ledger a first-class artifact; "programme complete" requires every row `done`, `n/a` or explicitly deferred.
2. `next-step`, `project-status` and the finishing skill read that ledger before saying complete.
3. `writing-plans` derives `k of n` and `next:` from the latest spec and ledger, not the frozen decomposition.
4. `plan-lint` flags a plan or spec that names a split (C1 then C2) with no plan for the second half.

## Not yet done

- Only this one programme was traced in depth. The owner says it happens "always, after a few sessions": check earlier projects (darkraise-modder Sep 9-10 editor-completion sessions under `...darkraise-modder--artifacts-editor-completion-darkraise-modder`, the Studio review batch `docs/superpowers/findings/2026-08-21-studio-review-batch-decisions.md`, other repos) for the same pattern and for other loss mechanisms (for example a list item dropped during spec or plan writing, or a fix that stayed unverified).
- Nothing in the plugin has been changed for this. Do not treat the candidate fixes as decided.
