# UI profile

**Platform:** terminal — Claude Code mods (the dforge cockpit, the dflow HUD) drawn by Claude Code's Ink renderer
**Harness:** a nested Claude Code session (`/root/.local/bin/claude`) in tmux with the plugin under test loaded, captured with `tmux capture-pane -e` to `.ansi` files under `.dforge/ui-ux/<proof>/`
**UI test runner:** `claude plugin test plugins/<plugin>` (the mod's `register.test.tsx`), plus the plugin's Node suite for pure view modules
**UI paths:** `plugins/*/hooks/*.tsx` `plugins/*/hooks/*.ts` `plugins/*/hooks/*.mjs`
**Design system:** the dforge cockpit's vocabulary: rounded framed cards in a per-section color, the title (a collapse button) and headline on the top rule, `▰▱` meters with `┃` and `┊` marks, rounded buttons with an underlined hotkey letter, a framed two-line band above the prompt
**Token paths:** none; colors are Ink color names and the cockpit's hex accents
**Viewports:** 200x60, 120x40 (terminal columns x rows)
**Themes:** default (Claude Code emits color under `NO_COLOR=1`, so there is no second theme to walk; every row must read without color)
**Users:** the repository owner running dforge and dflow builds, keyboard-first, often in long unattended sessions
**Voice:** plain, sentence case, short labels, verbs on buttons
**Screenshots:** local

## Decisions

- 2026-11-13 — The desktop app draws the terminal layout for the dflow HUD; no SVG flight deck.
