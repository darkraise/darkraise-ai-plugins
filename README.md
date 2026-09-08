# Darkraise plugins

Plugins for Claude Code and Codex, distributed through the `darkraise` marketplace.
The repository is being renamed to `darkraise/darkraise-plugins`.

| Plugin | Claude Code | Codex |
| --- | --- | --- |
| [dr-status](plugins/dr-status/README.md) | Available | Not listed |
| [dr-superpowers](plugins/dr-superpowers/README.md) | Available | Available |
| [dcc-darkraise-ui](plugins/dcc-darkraise-ui/README.md) | Available | Available |
| [dcc-darkraise-win32ui](plugins/dcc-darkraise-win32ui/README.md) | Available | Available |

## Installation

Register the repository root, using its current Git URL or a local checkout.
After the GitHub rename, the root URL is
`https://github.com/darkraise/darkraise-plugins.git`.

Claude Code:

```text
/plugin marketplace add darkraise/darkraise-plugins
/plugin install dr-superpowers@darkraise
/plugin install dr-status@darkraise
```

For statusline registration, run `/dr-status install`, or `/dr-status install
--all` for all discovered accounts. Existing themes and account configuration
stay under `~/.claude/dcc-statusline.json`.

Codex uses `.agents/plugins/marketplace.json`; Claude uses
`.claude-plugin/marketplace.json`. Registering the root gives Codex only the
three supported plugins. Directly registering the Claude catalog file bypasses
root discovery and is outside the supported Codex installation route.

After the repository rename, install through Codex with:

```text
codex plugin marketplace add https://github.com/darkraise/darkraise-plugins.git
codex plugin list --marketplace darkraise --available
codex plugin add dr-superpowers@darkraise
```

A local checkout's absolute root path can replace the URL. Codex 0.153.4's CLI
rejects direct catalog-file registration; supported root discovery selects the
dedicated Codex catalog.

`dr-superpowers` requires Superpowers. Claude declares the dependency on
`superpowers` from `claude-plugins-official`; register that marketplace if it is
not already available. Codex requires the relevant installed Superpowers skills
and native agent tools. Native model/effort availability is checked against the
active client before dispatch; installation alone does not establish model parity.

## Migration

Refresh an existing root marketplace registration before installing renamed
plugins. A source pinned to an old commit must explicitly move to the revised
release. If adding the renamed URL conflicts with the existing `darkraise`
registration, record installed plugin IDs and scopes, remove the old registration,
add the new root, and reinstall the selected supported plugins. Preserve plugin
data when uninstalling; do not assume marketplace removal keeps installations.

Disable the old Claude `dcc-statusline` and `dcc-superpower-companions` plugins
before enabling `dr-status` and `dr-superpowers`, so their hooks do not run twice.
Statusline script storage remains `~/.claude/dcc-statusline/`; a registry at
`~/.claude/dcc-statusline-installations.json` remembers custom account destinations.
Set `DCC_STATUSLINE_HOME` only when installing or intentionally moving a copy.
Sync, status, doctor, and uninstall use the recorded destination afterward.

Telegram notification support is retired. Uninstall `dcc-telegram-notify` from
existing clients yourself; removing its catalog entry does not remove cached
installations. Likewise uninstall an old statusline installation from Codex.
Repository changes do not delete Telegram configuration, erase tokens, or revoke
the bot token. Those remain separate user-controlled actions.

## Development and validation

Public plugin names must match their directories and catalog entries. Add a
native Codex manifest only for a plugin supported by Codex. Shared client
manifests must have equal release versions. `dr-superpowers` explicitly sets
empty Codex hooks to prevent discovery of its Claude hook file.

Run repository validation and the maintained test suites with bounded commands.
Validate the Claude marketplace and each Claude plugin separately. Installation
and upgrade tests use disposable profiles, caches, and Git repositories; they
must never modify your installed plugins or invoke paid models.

[MIT](LICENSE) © 2026 Darkraise
