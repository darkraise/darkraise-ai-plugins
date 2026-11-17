# Worktree cwd probe — 2026-11-18

Claude Code 2.1.326, run against a copy of `plugins/dforge` whose
`scripts/auto-run` was replaced by a stub that logs `$(pwd -P)` and its
arguments. Scratch repository `repo` (branch `main`) with a linked worktree
`w` (branch `w`); `CLAUDE_CONFIG_DIR=/root/.claude-alt2`, user setting sources
off, scratch `HOME`, no `--dangerously-skip-permissions`.

## Observations

1. **`cd` launch in `w`.** Bash `pwd`: `…/probe/w`. Cockpit Repo strip:
   `…/probe/w`, `⎇ w`. The cockpit's `auto-run --session <sid> pending`
   calls ran in `…/probe/w`.
2. **Launch in `repo`, then `EnterWorktree` on `../w`.** Before: strip
   `…/probe/repo`, `⎇ main`. `EnterWorktree` asked for a permission-root
   relocation ("a model-supplied worktree outside .claude/worktrees/"); after
   approval it printed `Switched to worktree on branch w`. Bash `pwd` and
   `git rev-parse --show-toplevel`: both `…/probe/w`. Strip: `…/probe/w`,
   `⎇ w`. Every `auto-run … pending` call logged for this session ran in
   `…/probe/w`.
3. **Handoff planted only in `w/.dforge/handoff/latest.md`** (a
   `## Next session` block with `Paste as the first prompt:` and a fenced
   prompt). After a one-line reply the cockpit pane showed the auto-run card
   and no Resume offer: the expected baseline, since before Tasks 2-3 the
   handoff path resolves to the primary's for every checkout.
4. **Reply ending `Auto run: compacting`.** The cockpit compacted and logged
   `…/probe/w --session <sid> compacted`, then `…/probe/w --session <sid>
   resumed`, and submitted its continue prompt.
5. **`/clear`.** Bash `pwd`: `…/probe/w`. Strip: `…/probe/w`, `⎇ w`. New log
   lines: `…/probe/w --session <new sid> pending` (twice); no `rebind` or
   `resumed` line on this manual clear (the stub never changes the run's
   state, so the cockpit saw nothing to rebind).

Cleanup: the probe's tmux session killed, no process left, the owner's
`settings.json` byte-identical (`cmp`), scratch directory removed.

## Verdicts

- cd launch: worktree
- EnterWorktree (Bash): worktree
- /clear: worktree
- resume offer read the worktree's handoff: no (baseline before Tasks 2-3)
- process.run follows EnterWorktree: yes

No case stays in the primary, so no fallback from the spec's riskiest
assumption section is needed.
