# UI proof: the cockpit reads the session checkout's handoff

**Contract:** touch
**Fingerprint:** 2406b7defe6d1675
**Platform:** terminal
**Viewports:** 200x60, 120x40
**Themes:** default
**Evidence:** local
**Judge:** ship 2406b7defe6d1675 — docs/dforge/ui-ux/proofs/2026-11-18-per-worktree-handoff.judge.md

## Delta

**UI/UX depth:** touch — the resume offer in the dforge and dagents cockpits (`plugins/dforge/hooks/cockpit/register.tsx`, `plugins/dagents/hooks/cockpit/register.tsx`) reads the session checkout's own `latest.md` instead of the primary's, names it by absolute path in the fallback prompt, and runs `scripts/auto-run` in the session checkout (plan `docs/dforge/plans/2026-11-18-per-worktree-handoff.md`, Task 8)

- **UI-1** — In a session launched in a linked worktree, the pane's Resumable work card and the band show the Next line of the worktree's handoff ("Probe: the worktree's next step."), while the primary's handoff holds a different block written at the same time ("Probe: the primary's next step.") that is not shown.
- **UX-1** — Resume, reached by keyboard (`ctrl+x tab`, Enter), submits the worktree handoff's first prompt, which opens ``Start in `<worktree>` (branch w); its handoff is `<worktree>/.dforge/handoff/latest.md`.``
- **UX-2** — When the handoff has no fenced first prompt, Resume submits `Resume the work in <absolute handoff path> with the <plugin> resume-execution skill.`
- **UX-3** — A worktree session whose own checkout holds no handoff raises no offer from the primary's; when the session's worktree directory is gone, the offer falls back to the primary's handoff.
- **UX-4** — Every `scripts/auto-run` call the cockpit makes runs in the session's checkout, or in the primary when the session's worktree directory is gone, so the stop calls still reach the run.
- **OP-1** — Proven at 200x60 and 120x40, default theme, in both plugins.
- **OP-2** — The offer reads without colour: the Next line and the prompt are words.

## Results

| ID | Verdict | Evidence | Note |
|---|---|---|---|
| UI-1 | pass | .dforge/ui-ux/2026-11-18-per-worktree-handoff/dforge-card-200x60.ansi, .dforge/ui-ux/2026-11-18-per-worktree-handoff/dagents-card-200x60.ansi | Both handoffs were written by the real `next-step --adhoc --phase build --next …`, one in the worktree and one in the primary, a few seconds apart. In each plugin the pane's card reads `↻ Resumable work · handed off just now` / `Next: Probe: the worktree's next step.` and the band reads `↻ Resumable work · handed off just now — Next: Probe: the worktree's next step.`. "primary's next step" appears in no capture of this walk |
| UX-1 | pass | .dforge/ui-ux/2026-11-18-per-worktree-handoff/dforge-resume-focus-200x60.ansi, .dforge/ui-ux/2026-11-18-per-worktree-handoff/dforge-resume-200x60.ansi, .dforge/ui-ux/2026-11-18-per-worktree-handoff/dagents-resume-focus-200x60.ansi, .dforge/ui-ux/2026-11-18-per-worktree-handoff/dagents-resume-200x60.ansi | In each plugin `ctrl+x tab` put the focus ring on `[ Resume ]`: the focus capture draws it in reverse video (SGR `1;7`), where the card capture before the keypress draws it bold only (SGR `1`). Enter then submitted, under `Prompt from the dforge plugin` (`dagents` in the dagents walk), `Start in …/uiw/wt (branch w); its handoff is …/uiw/wt/.dforge/handoff/latest.md. If your working directory is not …/uiw/wt, enter it first. Continue the unplanned work recorded in …: Probe: the worktree's next step.`. The turn then failed `Invalid API key`, as the placeholder key makes every turn fail. Claude Code draws Markdown code spans without their backticks |
| UX-2 | pass | test "resume offer > names the absolute handoff path in the fallback resume prompt (spec A9)" in plugins/dforge/tests/cockpit.test.ts and plugins/dagents/tests/cockpit.test.ts | The test asserts the submitted prompt equals `Resume the work in /home/me/code/shop-wt/.dforge/handoff/latest.md with the dforge resume-execution skill.` (`.dagents`, `dagents` in dagents). Not walked live: a handoff without a fenced prompt raises no card on its own, and the recomputed block next-step prints always has one |
| UX-3 | pass | tests "resume offer > reads the session worktree's handoff, not the primary's (spec A9)" and "resume offer > runs from the primary checkout when the session's directory is gone" in both cockpit.test.ts files | The first runs a worktree session with only the primary's handoff present and asserts no next-step recompute starts, so no offer exists; the second removes the worktree directory and its handoff and asserts the recompute then runs from the primary |
| UX-4 | pass | tests "auto run > passes the session checkout to every auto-run call (spec A8)" and "auto run > runs auto-run from the primary when the session's checkout is gone" in both cockpit.test.ts files; docs/dforge/notes/2026-11-18-worktree-cwd-probe.md | The first test declares the worktree directory and asserts every auto-run argv starts `bash -c cd -- "$1" && shift && exec bash "$@" auto-run /home/me/code/shop-wt `; the second leaves the worktree directory out and asserts every argv cds into the primary `/home/me/code/shop` and the `compacted` call still runs. The probe note shows the cockpit's process calls already run in the worktree after `EnterWorktree`, so the `cd --` makes that explicit rather than changing it |
| OP-1 | pass | .dforge/ui-ux/2026-11-18-per-worktree-handoff/dforge-card-200x60.ansi, .dforge/ui-ux/2026-11-18-per-worktree-handoff/dforge-card-120x40.ansi, .dforge/ui-ux/2026-11-18-per-worktree-handoff/dforge-after-120x40.ansi, .dforge/ui-ux/2026-11-18-per-worktree-handoff/dagents-card-200x60.ansi, .dforge/ui-ux/2026-11-18-per-worktree-handoff/dagents-card-120x40.ansi | At 120x40, before any Resume, the dforge pane card still reads `↻ Resumable work · handed off just now` over `Next: Probe: the worktree's next step.`, with the session path cut to `/…/scratchpad/uiw-dforge/wt`; the narrower dforge band keeps its title, `[ Resume ]` and `Dismiss` but truncates its text with `…` before the Next line, which the card beside it carries. The dagents session at 120x40 draws no pane, and its band, a full window wide, carries the whole Next line with `[ Resume ]` and `Dismiss`. `dforge-after-120x40` is after Resume and shows the submitted `Start in` prompt wrapped to the window |
| OP-2 | pass | .dforge/ui-ux/2026-11-18-per-worktree-handoff/dforge-card-200x60.ansi | The offer is the text of the Next line and the prompt; no state depends on colour |

## Automated checks

- Re-walked on 2026-11-18 after the final review's fix wave changed `autoRunCall` in both register.tsx (8e29f331), from branch auto/per-worktree-handoff at 6a6bc3a4; every capture above is from this walk and replaces the one taken at 7b86861c. One tmux session per plugin with `window-size manual` (the shared server's `window-size latest` otherwise sizes a new window to 210x63), captured at 120x40 and 200x60 by resizing the same window before Resume, and for dforge again at 120x40 after Resume. The first walk ran on Claude Code 2.1.326 in tmux, one walk per plugin, plus a second short walk per plugin for the 120x40 card and the dagents focus capture, from branch auto/per-worktree-handoff at 7b86861c (`--plugin-dir plugins/<plugin>`, `--setting-sources project,local`, a fresh `CLAUDE_CONFIG_DIR` with a placeholder API key approved in its `.claude.json`, a scratch HOME, a scratch git repository `repo` with a linked worktree `wt` on branch `w`, the session launched in `wt`). For the dagents walk `WORKFLOW_GUARD_CLAUDE_DIR` pointed at an empty directory. No bypass-permissions prompt was shown or accepted.
- `claude plugin test` at 6a6bc3a4: plugins/dforge 702 pass, 0 fail; plugins/dagents 616 pass, 0 fail.

## Not proven

- A pointer press is not exercised: the change draws no new control, and tmux sends no clicks.
- The auto-run `cd --` and its fallback to the primary are proven by test and by the Task 1 probe, not by a live auto run in this walk.
