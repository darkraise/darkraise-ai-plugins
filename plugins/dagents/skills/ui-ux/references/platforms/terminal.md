# Terminal UI

**Status:** verified 2026-10-24 on Linux with tmux 3.5a: launch, send-keys, capture at 80 and 120 columns, kill.

- **Launch:** `tmux new-session -d -s uiux -x 80 -y 24 '<command>'`. The
  profile's UI paths must name the TUI's source files: there are no defaults
  for terminals.
- **Drive:** `tmux send-keys -t uiux <keys>` (`Tab`, `Enter`, `Escape`,
  `Up`, `Down`, literal text with `-l`).
- **Capture:** `tmux capture-pane -t uiux -p -e > <file>.ansi` at 80 columns,
  then `tmux resize-window -t uiux -x 120 -y 40` and capture again. A
  captured pane is the evidence for a terminal row (cite the `.ansi` file).
- **Themes:** run once with `NO_COLOR=1` and once with colour; check that no
  state is shown by colour alone.
- **Clean up:** `tmux kill-session -t uiux`.
