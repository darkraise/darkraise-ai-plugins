# Migration

Notes for moving to the current plugin names and for re-registering the
marketplace. dforge's own upgrade steps live in its README:
[Migrating to 4.0](../plugins/dforge/README.md#migrating-to-40).

## Re-registering the marketplace

Refresh an existing root marketplace registration before installing renamed
plugins. A source pinned to an old commit must explicitly move to the revised
release. If adding the renamed URL conflicts with the existing `darkraise`
registration, record the installed plugin IDs and scopes, remove the old
registration, add the new root, and reinstall the selected supported plugins.
Preserve plugin data when uninstalling; do not assume that removing a
marketplace keeps its installations.

## Replaced plugins

Disable the old Claude `dcc-statusline` and `dcc-superpower-companions` plugins
before enabling `dr-status` and `dforge`, so their hooks do not run twice.

`dr-forge` 2.0.0 replaces `dr-superpowers` and `dr-cockpit`: install it, start
one session so it imports their settings, then uninstall both (see
[Migrating from dr-superpowers and dr-cockpit](../plugins/dforge/README.md#migrating-from-dr-superpowers-and-dr-cockpit)).
`dr-forge` 3.0.0 then renames the pre-3.0 repository directories and the home
with `forge-migrate` (see
[Migrating to 3.0](../plugins/dforge/README.md#migrating-to-30)).

`dforge` 4.0.0 replaces `dr-forge`: install `dforge@darkraise`, uninstall
`dr-forge@darkraise`, and run `/dforge:migrate` in each repository. It takes a
dr-superpowers repository straight to 4.0 as well (see
[Migrating to 4.0](../plugins/dforge/README.md#migrating-to-40)).

`darkraise-ui` and `darkraise-win32ui` 0.3.0 replace `dcc-darkraise-ui` and
`dcc-darkraise-win32ui`, with the same skills: install the new names, then
uninstall the old ones.

## Status line

Statusline script storage remains `~/.claude/dcc-statusline/`; a registry at
`~/.claude/dcc-statusline-installations.json` remembers custom account
destinations. Set `DCC_STATUSLINE_HOME` only when installing or intentionally
moving a copy. Sync, status, doctor and uninstall use the recorded destination
afterward. To register the status line, run `/dr-status install`, or
`/dr-status install --all` for all discovered accounts.

## Retired plugins

Telegram notification support is retired. Uninstall `dcc-telegram-notify` from
existing clients yourself; removing its catalog entry does not remove cached
installations. Likewise uninstall an old statusline installation from Codex.
Repository changes do not delete Telegram configuration, erase tokens or revoke
the bot token. Those remain separate actions for you to take.
