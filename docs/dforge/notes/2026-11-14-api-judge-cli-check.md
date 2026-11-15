# API judge CLI check

Run 2026-11-14 on Claude Code 2.1.325 and codex-cli 0.163.0. No key value
appears here: keys are named by their variables.

## Flags

Claude CLI (`claude --help`):

- `--bare`: "Minimal mode: skip hooks …, LSP, plugin sync, attribution,
  auto-memory, background prefetches, keychain reads, and CLAUDE.md
  auto-discovery. … Anthropic auth is strictly ANTHROPIC_API_KEY or
  apiKeyHelper via --settings (OAuth and keychain are never read)."
- `-p, --print`: "Print response and exit (useful for pipes)."
- `--output-format <format>`: "Output format (only works with --print):
  "text" (default), "json" (single result), or "stream-json"".
- `--model <model>`: "Model for the current session. Provide an alias … or
  a model's full name."
- `--add-dir <directories...>`: "Additional directories to allow tool access to".
- `--tools <tools...>`: "Specify the list of available tools from the
  built-in set. Use "" to disable all tools, "default" to use the default
  set, or specify tool names (e.g. "Bash,Edit,Read")." (`--allowed-tools`
  only pre-approves and is not the restriction.)
- `--effort <level>`: "Effort level for the current session (low, medium,
  high, xhigh, max)".

`--add-dir` and `--tools` take variadic values, so a positional prompt after
either is swallowed as a value. The prompt goes on stdin: with stdin empty
the CLI exits 1 with `Input must be provided either through stdin or as a
prompt argument when using --print`; with the prompt on stdin and both
variadic flags present it reached the API (the 401 below).

Codex CLI (`codex exec --help`):

- `-c, --config <key=value>`: "Override a configuration value that would
  otherwise be loaded from `~/.codex/config.toml`. Use a dotted path …"
- `-m, --model <MODEL>`: "Model the agent should use".
- `--json`: "Print events to stdout as JSONL".
- `-o, --output-last-message <FILE>`: "Specifies file where the last message
  from the agent should be written".
- `-s, --sandbox <SANDBOX_MODE>`: "[possible values: read-only,
  workspace-write, danger-full-access]".
- `--skip-git-repo-check`: "Allow running Codex outside a Git repository".
- `[PROMPT]`: "If not provided as an argument (or if `-` is used),
  instructions are read from stdin."
- Missing: an effort flag. Effort is set with `-c model_reasoning_effort="<effort>"`.
- `-C, --cd <DIR>` sets the working root. `--add-dir <DIR>` makes a
  directory writable, so the judge line does not pass it: the read-only
  sandbox already reads outside the working root.

## Anthropic command

Run with `<cwd>` as the working directory, the prompt file on stdin, every
`DFORGE_*_API_KEY`, `OPENAI_API_KEY` and `ANTHROPIC_API_KEY` removed from the
child's environment and only `ANTHROPIC_API_KEY` set from the budget's key:

```
cd <cwd> && env -u DFORGE_OPENAI_API_KEY -u DFORGE_ANTHROPIC_API_KEY -u DFORGE_AGENTROUTER_API_KEY -u OPENAI_API_KEY ANTHROPIC_API_KEY="$DFORGE_ANTHROPIC_API_KEY" claude --bare -p --output-format json --model <model> --effort <effort> --tools Read,Grep,Glob --add-dir <add-dir> < <prompt>
```

`--add-dir <add-dir>` repeats once per directory and is left out when there
is none.

## Codex command

Run with `CODEX_HOME` set to a fresh empty directory, the prompt file on
stdin, every `DFORGE_*_API_KEY`, `OPENAI_API_KEY` and `ANTHROPIC_API_KEY`
removed, and `DFORGE_JUDGE_KEY` set from the budget's key. `<base-url>` is
`https://api.openai.com/v1` for `openai` and `https://agentrouter.org/v1`
for `agentrouter`; `<key-variable>` is `DFORGE_OPENAI_API_KEY` or
`DFORGE_AGENTROUTER_API_KEY`:

```
env -u DFORGE_OPENAI_API_KEY -u DFORGE_ANTHROPIC_API_KEY -u DFORGE_AGENTROUTER_API_KEY -u OPENAI_API_KEY -u ANTHROPIC_API_KEY CODEX_HOME=<fresh-dir> DFORGE_JUDGE_KEY="$<key-variable>" codex exec -c 'model_provider="dforge"' -c 'model_providers.dforge.name="dforge"' -c 'model_providers.dforge.base_url="<base-url>"' -c 'model_providers.dforge.env_key="DFORGE_JUDGE_KEY"' -c 'model_providers.dforge.wire_api="responses"' -c 'model_reasoning_effort="<effort>"' -m <model> --sandbox read-only --skip-git-repo-check --json -o <last-message-file> -C <cwd> - < <prompt>
```

A `CODEX_HOME` under `/tmp` prints `WARNING: proceeding, even though we could
not create PATH aliases: Refusing to create helper binaries under temporary
dir "/tmp"` on stderr; the run continues.

## Cost and usage fields

Anthropic, `--output-format json` (one object): the reply text is `.result`,
the cost is `.total_cost_usd`, the failure flag is `.is_error`, and token
counts are `.usage.input_tokens`, `.usage.cache_read_input_tokens`,
`.usage.cache_creation_input_tokens` and `.usage.output_tokens`. A failed
call also carries `.api_error_status` and `.api_error_type`. Seen on the
invalid-key run only (cost 0); their values on a successful call are
unverified — no key was set.

Codex, `--json` (JSONL): unverified — no key was set. The Codex
non-interactive mode guide (https://learn.chatgpt.com/docs/non-interactive-mode,
read 2026-11-14) says "Event types include `thread.started`, `turn.started`,
`turn.completed`, `turn.failed`, `item.*`, and `error`", and its sample
`turn.completed` line carries
`"usage":{"input_tokens":24763,"cached_input_tokens":24448,"output_tokens":122,"reasoning_output_tokens":0}`;
the reply is the `item.completed` line whose item is an agent message, and
`-o` writes the last message to a file. A failed call writes `error` lines and
a `turn.failed` line with `.error.message`.

The Codex error text repeats the key it was given: the invalid-key run
printed `Incorrect API key provided: sk-invalid.` in its `error` and
`turn.failed` lines. Treat Codex stdout and stderr as able to hold the key.

## Results

- Invalid-key runs, each from a scratch directory with only `README.md`:
  - Anthropic: exit 1 in 2 s, `"api_error_status":401`,
    `"api_error_type":"authentication_error"`, `"result":"Invalid API key ·
    Fix external API key"`. Bare mode did not fall back to the subscription
    login.
  - Codex on `https://api.openai.com/v1`: exit 1 in 9 s after five retries,
    `401 Unauthorized … invalid_api_key` from `/v1/responses`;
    `sha256sum ~/.codex/auth.json` unchanged before and after.
  - Codex on `https://agentrouter.org/v1`: exit 1, `401 Unauthorized` from
    `https://agentrouter.org/v1/responses`; `~/.codex/auth.json` unchanged.
- Real-key runs: not run — `DFORGE_ANTHROPIC_API_KEY` unset; not run —
  `DFORGE_OPENAI_API_KEY` unset; not run — `DFORGE_AGENTROUTER_API_KEY` unset.
- `anthropic`: verified to the authentication error only.
- `openai`: verified to the authentication error only.
- `agentrouter`: verified to the authentication error only.

Live checks, Task 10 (2026-11-15), in a scratch `HOME` and a scratch
repository with a bound auto run:

- `anthropic` live ruling: not run — `DFORGE_ANTHROPIC_API_KEY` unset.
- `openai` live ruling: not run — `DFORGE_OPENAI_API_KEY` unset.
- `agentrouter` live ruling: not run — `DFORGE_AGENTROUTER_API_KEY` unset.
- Decisions request (`decide ask`, `decisionApi` `shadow`): not run —
  `DFORGE_OPENAI_API_KEY` unset.
- Whether the last Codex `turn.completed` usage line is a run's whole cost
  stays unverified: no Codex run reached a model.
- `sha256sum ~/.codex/auth.json`: `d86229e2f303d11b…` before and after,
  unchanged.
- `claude auth status`: `loggedIn: true`, `authMethod: claude.ai`,
  `apiProvider: firstParty` before and after, unchanged; no
  `ANTHROPIC_API_KEY` in the session's environment, so the session stayed on
  the subscription.

Live checks repeated 2026-11-15 with all three keys set, same scratch setup:

- First pass: all three rulings reached their models and were charged
  (0.0085, 0.1252, 0.1281 USD), then ended `status=FAILED reason=wrote`.
  The scratch repository did not ignore `.dforge/`, and `run-api-judge`
  appends its `started` line to `<state>/api-judge.log` after the
  before-snapshot. Reproduced with the stub judge; register row 18 of
  `docs/dforge/registers/2026-11-14-decisions-cache-and-credits.md`.
- Second pass, `.dforge/` ignored as in a dforge project:
  - `anthropic` live ruling: verified live 2026-11-15:
    `anthropic:claude-opus-5-5/medium status=OK … spent=0.0034 reason=none`,
    report opens with `## Verdict`, `api-spend status` spent 0.0034.
  - `openai` live ruling: verified live 2026-11-15:
    `openai:gpt-6-astra/xhigh status=OK … spent=0.1390 reason=none`, report
    opens with `## Verdict`, spent 0.1390.
  - `agentrouter` live ruling: verified live 2026-11-15:
    `agentrouter:gpt-6-astra/xhigh status=OK … spent=0.1258 reason=none`,
    report opens with `## Verdict`, spent 0.1258.
  - Decisions request: verified live 2026-11-15: `no ruling reason=shadow`;
    the `decisions.jsonl` line holds `choice`, `choice_reversed`,
    `confidence` 0.82 and `confidence_reversed` 0.61.
- `sha256sum ~/.codex/auth.json`: `d86229e2f303d11b…` before and after both
  passes; the `claude auth status` output digest is unchanged too.
- Whether the last Codex `turn.completed` usage line is a run's whole cost
  stays unverified: these one-shot rulings were not inspected for more than
  one `turn.completed` line.

## Demos

Run in the scratch repository (`.dforge/` ignored, one commit, an auto run
bound to the made-up session `demo-session-1`) under a scratch `HOME`, with
`AR_SESSION=demo-session-1` and `API_JUDGE_CLAUDE` exported, following
`plugins/dforge/reference/auto-run.md` §Rulings. Settings were set with
`dforge-config set` before each step: rung 1 with `decisionApi` `on` and
`apiBudgetOpenai` 5; rung 2 with `apiBudgetAnthropic` 5 and the other caps 0;
the last run with every cap 0.

```text
### A19: a choice item at rung 1
$ bash plugins/dforge/scripts/decide ask --id demo-1 --question "Which lock should the spool use?" --options "a noclobber lock file | a mkdir lock directory" --evidence docs/s.md
no ruling reason=closed
[exit 3]

### A19: the same item at rung 2 (run-api-judge before judge-opus)
The judge here is the test stub plugins/dforge/tests/fixtures/stub-api-judge/claude: no API key is set on this host.
$ API_JUDGE_CLAUDE=plugins/dforge/tests/fixtures/stub-api-judge/claude DFORGE_ANTHROPIC_API_KEY=sk-test-anthropic-SENTINEL bash plugins/dforge/scripts/run-api-judge --prompt .dforge/demo-prompt.md --report .dforge/rulings-preexec-1-report.md --cwd .
api-judge anthropic:claude-opus-5-5/medium started
api-judge anthropic:claude-opus-5-5/medium status=OK exit=0 out=<scratch repository>/.dforge/rulings-preexec-1-report.md spent=0.2500 reason=none
[exit 0]

$ cat .dforge/rulings-preexec-1-report.md
## Verdict
ruling: a noclobber lock file — it holds on uutils

### A19: the subscription seat only after exit 3
$ bash plugins/dforge/scripts/run-api-judge --prompt .dforge/demo-prompt.md --report .dforge/rulings-preexec-1-report.md --cwd .
api-judge anthropic:claude-opus-5-5/medium status=SKIPPED exit=0 out=- spent=0.0000 reason=off
api-judge openai:gpt-6-astra/xhigh status=SKIPPED exit=0 out=- spent=0.0000 reason=off
api-judge agentrouter:gpt-6-astra/xhigh status=SKIPPED exit=0 out=- spent=0.0000 reason=off
[exit 3]

exit 3 — the subscription seat is dispatched at this point, and not before

### A30: api-spend status
$ bash plugins/dforge/scripts/api-spend status   # scratch HOME
api-budget anthropic open=false spent=0.2500 cap=0.0000 reason=off
api-budget openai open=false spent=0.0000 cap=0.0000 reason=off
api-budget agentrouter open=false spent=0.0000 cap=0.0000 reason=off
[exit 0]

$ bash plugins/dforge/scripts/api-spend status   # real HOME
api-budget anthropic open=false spent=0.0000 cap=0.0000 reason=off
api-budget openai open=false spent=0.0000 cap=0.0000 reason=off
api-budget agentrouter open=false spent=0.0000 cap=0.0000 reason=off
[exit 0]

```
