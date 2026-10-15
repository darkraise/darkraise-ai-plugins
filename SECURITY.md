# Security policy

## Reporting a vulnerability

Please do not open a public issue for a security problem. Report it privately
through GitHub: open the repository's **Security** tab and choose **Report a
vulnerability**. Include the plugin and version, what an attacker can do, and
the steps to reproduce it.

You can expect an acknowledgement within a week. Fixes are released as a new
plugin version, and the advisory credits the reporter unless asked otherwise.

## Supported versions

Only the latest release of each plugin receives security fixes.

## Scope

These plugins run on your machine with your permissions, so the following are in
scope:

- Hooks and scripts that run shell commands, read or write files, or call a
  network service (for example the Discord webhook, the darkmem sync and the
  Codex executor lane).
- The attribution guard and the redactor that filters notification excerpts.
- Storage of credentials and tokens: the Discord webhook URL, and the darkmem API
  key, which is read from an environment variable and should never be written to
  disk by a plugin.
- The marketplace catalogs and plugin manifests.

Problems in Claude Code, Codex, Discord or darkmem themselves belong with their
maintainers.
