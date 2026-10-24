# Playwright MCP and worktree evidence paths

Probe run 2026-10-24 in the execution worktree
`/root/repositories/darkraise-ai-plugins/.claude/worktrees/ui-ux-skill`, from
the session that had entered that worktree.

- **Absolute worktree path:** written to
  `<WT>/.dforge/ui-ux/probe/abs.png` (5174 bytes). The tool echoed the path
  relative to the worktree, `.dforge/ui-ux/probe/abs.png`.
- **Bare filename:** landed at `<WT>/bare-probe.png`, the worktree root, not the
  primary checkout. Observed from the session that entered the worktree; an
  earlier probe from a subagent, whose working directory was the primary
  checkout, put a bare filename in the primary checkout's root.
- **Snapshot files:** `<WT>/.playwright-mcp/page-<timestamp>.yml`.

The walkthrough (`plugins/dforge/skills/ui-ux/references/walkthrough.md`) saves
screenshots by absolute path into `<checkout>/.dforge/ui-ux/<slug>/` and, when
the tool refuses that path, by bare filename and then moves the file.
