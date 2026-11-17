# UI proof: auto-run launch model without /model

**Contract:** touch
**Fingerprint:** 73ea50846f939017
**Platform:** terminal
**Viewports:** 200x60, 120x40
**Themes:** default
**Evidence:** local
**Judge:** ship 73ea50846f939017 — docs/dforge/ui-ux/proofs/2026-11-18-auto-run-launch-model.judge.md

## Delta

**UI/UX depth:** touch — the auto-run switch in the dforge and dagents cockpits (`plugins/dforge/hooks/cockpit/register.tsx`, `plugins/dagents/hooks/cockpit/register.tsx`) puts the cleared session on the plan's launch model by rewriting its main-loop requests instead of running `/model` and `/effort`

- **UI-1** — After an auto-run switch clears the session, the cockpit pane's Account card names the launch model and effort (`Sonnet · low effort`), where before the switch it named the session's model (`Haiku 5.5`).
- **UX-1** — The cleared session's main-loop replies come from the launch model; requests from subagents keep their own model.
- **UX-2** — The person's user `settings.json` is byte for byte the same after the switch, and no saved-defaults snapshot is written.
- **UX-3** — The cockpit runs `/clear` and nothing else: no `/model` or `/effort` appears, and the first prompt submitted is the handoff's own, with no note about a model it could not set or put back.
- **OP-1** — Proven at 200x60 and 120x40, default theme.
- **OP-2** — The readout reads without colour: the model and effort are words on the card.

## Results

| ID | Verdict | Evidence | Note |
|---|---|---|---|
| UI-1 | pass | .dforge/ui-ux/2026-11-18-auto-run-launch-model/dforge-before-200x60.ansi, .dforge/ui-ux/2026-11-18-auto-run-launch-model/dforge-after-200x60.ansi, .dforge/ui-ux/2026-11-18-auto-run-launch-model/dagents-before-200x60.ansi, .dforge/ui-ux/2026-11-18-auto-run-launch-model/dagents-after-200x60.ansi | In both cockpits the Account card reads `Haiku 5.5` before the switch and `Sonnet · low effort` after it, the launch command in the handoff being `claude --model sonnet --effort low`. The engine's own welcome header keeps `Haiku 5.5 with low effort`, the session default, in every capture: it is not a cockpit row |
| UX-1 | pass | the walks' transcripts under /root/.claude-alt2/projects/ (dforge: cdba8016… then 79e684e4…; dagents: 00dd3dbc… then 7ad0fde1…); test "sends the cleared session's main-loop requests on the launch model and effort, writing no settings" in plugins/dforge/tests/cockpit.test.ts and plugins/dagents/tests/cockpit.test.ts | The switch turn ran on `claude-haiku-5-5` in both walks; every assistant message of the cleared session ran on `claude-sonnet-5-5` (dforge 9, dagents 9). The tests assert a subagent step (`agentId` set) keeps `claude-opus-5-5`/`max` while the main-loop step goes out as `sonnet`/`high` |
| UX-2 | pass | sha256 of /root/.claude-alt2/settings.json before and after each walk; test "A41: … a switch now leaves no snapshot and writes no settings" in plugins/dforge/tests/plugin-review-fixes.acceptance.test.ts | `sha256sum -c` printed `OK` after the dforge walk and after the dagents walk. The scratch HOME of each walk holds no `.claude/dforge/sessions/saved-defaults` directory |
| UX-3 | pass | .dforge/ui-ux/2026-11-18-auto-run-launch-model/dforge-after-200x60.ansi, .dforge/ui-ux/2026-11-18-auto-run-launch-model/dagents-after-200x60.ansi; test "A1: with switch pending the cockpit clears, binds the new session and submits the first prompt on the launch model and effort" in both plugins' clean-session-phases.acceptance.test.ts | The only slash command on screen and in the transcripts is `/clear`; the next prompt, marked `Prompt from the dforge plugin`, is the handoff's first prompt verbatim, and the reply is `Probe resumed.`. The tests assert the command list equals `['/clear']` |
| OP-1 | pass | .dforge/ui-ux/2026-11-18-auto-run-launch-model/dforge-after-200x60.ansi, .dforge/ui-ux/2026-11-18-auto-run-launch-model/dforge-after-120x40.ansi, .dforge/ui-ux/2026-11-18-auto-run-launch-model/dagents-after-200x60.ansi, .dforge/ui-ux/2026-11-18-auto-run-launch-model/dagents-after-120x40.ansi | Each walk ran at 200x60 and the window was then resized to 120x40: the docked pane stays and its Account card still reads `Sonnet · low effort` |
| OP-2 | pass | .dforge/ui-ux/2026-11-18-auto-run-launch-model/dforge-after-200x60.ansi | The readout is the text `Sonnet · low effort`; no state depends on colour |

## Automated checks

- Walked on 2026-11-18 on Claude Code 2.1.326 in tmux, one walk per plugin from branch fix/open-bugs-and-rulings (`--plugin-dir plugins/<plugin>`, `--setting-sources project,local`, `CLAUDE_CONFIG_DIR=/root/.claude-alt2`, a scratch HOME and a scratch git repository, `--session-id` fixed, `--model haiku --effort low`). The run was seeded as a real one: an `auto-run.json` with the plan attached, a handoff `latest.md` naming the launch command and first prompt, then `scripts/auto-run --session <id> switch`, which wrote `pending: switch` and `launch: {model: sonnet, effort: low}`. The first turn ended on `Auto run: switching`; the cockpit cleared, rebound and submitted the first prompt. No bypass-permissions prompt was accepted, so the user settings saw no write from the harness either.
- For the dagents walk `WORKFLOW_GUARD_CLAUDE_DIR` pointed at an empty directory: the owner's config enables dforge@darkraise at user scope, and the workflow guard otherwise stands the dagents cockpit down to its conflict line. The guard is unrelated to this change.
- `claude plugin test`: plugins/dforge 692 pass, 0 fail when run alone; plugins/dagents 606 pass, 0 fail.

## Not proven

- A pointer press is not exercised: the change draws no new control.
- The engine's own header and its context window follow the session's model, not the rewritten one; the cockpit cannot change either.
