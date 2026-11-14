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
  Codex and agy review runners).
- The attribution guard and the redactor that filters notification excerpts.
- Storage of credentials and tokens: the Discord webhook URL, and the darkmem API
  key, which is read from an environment variable and should never be written to
  disk by a plugin.
- The marketplace catalogs and plugin manifests.

Problems in Claude Code, Codex, Discord or darkmem themselves belong with their
maintainers.

## API keys and API-billed judges

dforge's auto runs can rule through developer API keys
(`DFORGE_ANTHROPIC_API_KEY`, `DFORGE_OPENAI_API_KEY`,
`DFORGE_AGENTROUTER_API_KEY`). Each is unused until its budget cap is set
above 0.

- The keys live in your shell profile, so every process the session starts
  can read them, not only dforge's scripts.
- What dforge's scripts guarantee: each judge runs with a scrubbed
  environment holding only the one key it needs (Codex in a fresh
  `CODEX_HOME`), with the known variables that would route the key or the
  prompt to another endpoint or provider cleared (the list is in
  `scripts/run-api-judge`; a proxy variable is kept); a reply that contains
  a key value is discarded; no key value is printed, logged or passed as a
  command-line argument. A judge
  CLI's own output, which can echo its key in an error, is held only in a
  private temporary directory that is removed when the run ends.
- What they do not: a Codex judge can read any file you can read, the shell
  profile that holds all three keys included. The Anthropic judge reads the
  worktree and the directories added to its run, ignored files included. The
  scrubbed environment and the reply scan stop an accidental leak, not a
  judge steered to look for a key.
- AgentRouter is a third party. The ruling prompt, and every file its judge
  reads, pass through it. It is off until both `apiBudgetAgentRouter` and
  `DFORGE_AGENTROUTER_API_KEY` are set; setting the cap is the consent.
- Only `scripts/decide` filters what it sends: it refuses evidence files that
  git ignores or that sit under a `.git` directory. The judges get whatever
  their prompt names and whatever they choose to read.
